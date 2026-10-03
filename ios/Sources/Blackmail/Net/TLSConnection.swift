// Guarded so this file compiles away on a host without Network.
// The library is built for Linux too, so the parsers and the protocol
// clients can be tested in seconds instead of through a device cycle;
// there the clients run over a `MailTransport` fake instead of this.
#if canImport(Network)

import Foundation
import Network

/// A TLS byte stream over `NWConnection`, with the buffering that line-based
/// mail protocols need.
///
/// Written rather than taken from a package, deliberately. Every Swift mail
/// library either drags in its own crypto (`swift-nio-ssl` vendors BoringSSL,
/// which is C plus platform-gated assembly and is exactly where a Linux →
/// arm64-apple-ios cross-compile dies) or is Objective-C++ over a native
/// dependency tree that assumes Xcode. `Network.framework` is in the SDK we
/// build against — `Network.tbd` is a real 175 KB stub with headers and a
/// module map, not one of the 404-byte re-export placeholders that forced us
/// off the iOS 18 SDK — so the system TLS stack costs us no dependency at all.
///
/// IMAP and SMTP are both "write a line, read lines until a terminator", with
/// the one complication that IMAP can splice binary literals into the middle
/// of a response. So this exposes both `readLine()` and `read(exactly:)` over
/// one shared buffer; a caller that reads a `{123}` literal marker can take
/// the next 123 bytes raw and then carry on reading lines.
///
/// An actor, because `NWConnection` calls back on its own queue and every
/// caller here is `async`. Serialising access also means a command and its
/// response cannot interleave with another command's.
///
/// Only the link is here: starting the connection, a receive, a send, a
/// cancel. The framing, the deadlines and what each one does when it fires,
/// what `close()` ends, and the B-034 probes are `LinkTransport`'s, which
/// the host tests run through the scripted server's link. This file does not
/// compile on the host, so anything that can be decided without `Network`
/// belongs there, not here.
///
/// The clients see it only as a `MailTransport`, which is what lets them build
/// and run on the Linux host against a scripted server.
actor TLSConnection: LinkTransport {

    /// What the app itself runs on: implicit TLS through `Network.framework`.
    static let factory: MailTransportFactory = { host, port in
        TLSConnection(host: host, port: port)
    }

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "wtf.uhoh.blackmail.net")
    var stream = LinkStream()

    /// Bounds every individual step: the connect with its TLS handshake, each
    /// read, and each piece of a write. A mail server that accepts the TCP
    /// connection and then says nothing must not hang the app forever — that
    /// failure mode looks exactly like a frozen screen to the user, which is
    /// the single worst thing this product can do.
    ///
    /// Tighter, on purpose, than the TCP bounds set below. The connect's
    /// bound covers the TCP and the TLS handshakes together in the time
    /// `connectionTimeout` gives TCP alone, and a piece of a write gets half
    /// of `connectionDropTime`. A path that is alive but stalls for longer
    /// than this, a long handover in the middle of a photo upload, is cut
    /// off where TCP would have waited it out. That is accepted: the
    /// transport cannot tell that stall from a dead path, and a write cut
    /// off fails cleanly. A letter's terminating dot goes only once the
    /// whole of it has, so a letter cut off is "not sent" and is not
    /// delivered, and a draft cut off is not saved.
    let ordinaryDeadline: TimeInterval

    /// The bound on a read of `ReplyWait.afterUpload`. Ten minutes is RFC
    /// 5321's figure (§4.5.3.2.6) for the reply to DATA's terminating dot,
    /// given there for the same reason: a spurious timeout at that point
    /// delivers the letter twice. It only ever runs its course against a
    /// server that is alive and silent. A path that has died while the tail
    /// of the upload was still unacknowledged is dropped by
    /// `connectionDropTime` below well before it.
    let uploadReplyDeadline: TimeInterval

    /// The bound on a read of `ReplyWait.serverWork`: the reply to a SEARCH,
    /// a SELECT or a STATUS, which Gmail starts only once it has worked
    /// through the mailbox. Three ordinary deadlines. What it costs: a path
    /// that dies while one of those commands waits is given up on at a
    /// minute and a half rather than half a minute. Once the command's bytes
    /// are acknowledged, `connectionDropTime` has nothing outstanding to
    /// time, and keepalive declares a dead peer only about two minutes
    /// after the last traffic, so it is this bound that ends the wait.
    let serverWorkDeadline: TimeInterval

    init(host: String, port: UInt16, timeout: TimeInterval = 30,
         uploadReplyTimeout: TimeInterval = 600, serverWorkTimeout: TimeInterval = 90) {
        self.ordinaryDeadline = timeout
        self.uploadReplyDeadline = uploadReplyTimeout
        self.serverWorkDeadline = serverWorkTimeout
        // Implicit TLS (IMAPS 993, SMTPS 465) rather than STARTTLS. One fewer
        // state to get wrong, and no window in which credentials could be sent
        // over a plaintext socket because an upgrade silently failed.
        let tls = NWProtocolTLS.Options()
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = Int(timeout)

        // Keepalive, so that a socket which dies while he is reading a letter
        // (a Wi-Fi roam, a router forgetting the NAT mapping) is found dead by
        // the stack during the quiet rather than by his next tap. Without it
        // that tap wrote into a dead socket and waited out the whole read
        // deadline before anything reconnected. With it the connection has
        // already failed, the command fails at once, and the read retry
        // reconnects without the wait.
        //
        // The numbers are conservative on purpose. The first probe goes after
        // a minute of quiet, about as long as he spends on a letter, and a
        // live peer answers it, so the steady cost is one small packet per
        // quiet minute while the app holds a connection. It does not keep the
        // session alive: Gmail ends an idle IMAP session after about thirty
        // minutes whatever TCP does, and the probes stop with it, so an iPad
        // left on the table pays for at most half an hour of them. Three
        // misses twenty seconds apart, not one, so a dropped packet or a brief
        // handover is not a dropped connection; a dead peer is declared two
        // minutes after the last traffic.
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 60
        tcp.keepaliveInterval = 20
        tcp.keepaliveCount = 3
        // Keepalive only probes a connection with nothing outstanding. This
        // covers the other case: bytes sent and left unacknowledged for a
        // minute, retransmissions and all, mean the path is gone. That is a
        // command written into a dead socket, or the tail of an upload whose
        // reply is waiting on `uploadReplyDeadline`. A slow uplink is not
        // affected: its segments are acknowledged, only slowly.
        tcp.connectionDropTime = 60
        let params = NWParameters(tls: tls, tcp: tcp)
        self.connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: params)
    }

    // MARK: - The link

    func startLink(reporting report: @escaping @Sendable (Error?) -> Void) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                report(nil)
            case .failed(let error):
                report(Self.map(error))
            case .waiting(let error):
                // .waiting means "no route / cannot reach it yet". For a mail
                // client that is a failure to report, not something to sit
                // in: the user is owed "Can't connect" promptly.
                report(Self.map(error))
            case .cancelled:
                report(MailTransportError.closed)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func receiveFromLink() async throws -> Data {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
                data, _, _, error in
                if let error { c.resume(throwing: Self.map(error)); return }
                if let data, !data.isEmpty { c.resume(returning: data); return }
                // No data and no error: the peer closed. Surfacing this as
                // .closed rather than looping is what stops a half-open
                // connection spinning the CPU forever.
                c.resume(throwing: MailTransportError.closed)
            }
        }
    }

    func sendToLink(_ piece: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.send(content: piece, completion: .contentProcessed { error in
                // Unmapped, so the WIRE-ACK line reads as it always has; see
                // `transportError`.
                if let error { c.resume(throwing: error) } else { c.resume() }
            })
        }
    }

    /// `cancel()` completes a pending receive or send with an error, and a
    /// pending connect is settled by `close()` itself, so the state handler
    /// has nothing left to do.
    func closeLink() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    static func transportError(_ sendError: Error) -> Error {
        (sendError as? NWError).map(map) ?? sendError
    }

    // MARK: - Helpers

    /// Delegates to `MailText`, which is Foundation-only so the parsers that
    /// also need it can be compiled and tested on a host without `Network`.
    static func decode(_ data: Data) -> String { MailText.decode(data) }

    private static func map(_ error: NWError) -> MailTransportError {
        switch error {
        case .tls(let status):  return .tls("TLS status \(status)")
        case .posix(let code):  return .posix("POSIX \(code.rawValue)")
        default:                return .posix(String(describing: error))
        }
    }
}

#endif
