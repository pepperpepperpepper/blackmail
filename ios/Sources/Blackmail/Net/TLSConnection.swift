// Guarded so this file compiles away on a host without Network.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
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
actor TLSConnection {

    enum ConnectionError: Error {
        case notConnected
        case closed
        case timedOut
        case tls(String)
        case posix(String)
    }

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "wtf.uhoh.blackmail.net")
    private var buffer = Data()
    private var isOpen = false

    /// `timeout` bounds every individual read. A mail server that accepts the
    /// TCP connection and then says nothing must not hang the app forever —
    /// that failure mode looks exactly like a frozen screen to the user, which
    /// is the single worst thing this product can do.
    private let timeout: TimeInterval

    init(host: String, port: UInt16, timeout: TimeInterval = 30) {
        self.timeout = timeout
        // Implicit TLS (IMAPS 993, SMTPS 465) rather than STARTTLS. One fewer
        // state to get wrong, and no window in which credentials could be sent
        // over a plaintext socket because an upgrade silently failed.
        let tls = NWProtocolTLS.Options()
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = Int(timeout)
        let params = NWParameters(tls: tls, tcp: tcp)
        self.connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: params)
    }

    // MARK: - Lifecycle

    func open() async throws {
        guard !isOpen else { return }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            // `resumed` guards against NWConnection reporting .failed after
            // .ready, or .waiting repeatedly: a continuation resumed twice is
            // a crash, not an error.
            var resumed = false
            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    c.resume()
                case .failed(let error):
                    resumed = true
                    c.resume(throwing: Self.map(error))
                case .waiting(let error):
                    // .waiting means "no route / cannot reach it yet". For a
                    // mail client that is a failure to report, not something
                    // to sit in: the user is owed "Can't connect" promptly.
                    resumed = true
                    c.resume(throwing: Self.map(error))
                case .cancelled:
                    resumed = true
                    c.resume(throwing: ConnectionError.closed)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
        isOpen = true
    }

    func close() {
        isOpen = false
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    // MARK: - Writing

    func write(_ data: Data) async throws {
        guard isOpen else { throw ConnectionError.notConnected }
        // B-034 instrumentation. Length only, and only for bulk writes: every
        // command line goes through here too, including `AUTH PLAIN <secret>`,
        // and the length of that line is the length of the credential. A
        // 1 KB floor logs the DATA payload and nothing else.
        let watched = data.count > 1024
        if watched { Diagnostics.log(.note, "WIRE-OUT bytes=\(data.count)") }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                // The ACK is the half that matters for "the transport is lying
                // to its own log": a transcript showing the 250 that follows,
                // with no ACK before it, means this continuation never
                // resumed — a different bug with a different next step.
                if watched {
                    Diagnostics.log(.note, "WIRE-ACK err=\(error.map(String.init(describing:)) ?? "none")")
                }
                if let error { c.resume(throwing: Self.map(error)) } else { c.resume() }
            })
        }
    }

    func writeLine(_ line: String) async throws {
        try await write(Data((line + "\r\n").utf8))
    }

    // MARK: - Reading

    /// One CRLF-terminated line, without the terminator.
    ///
    /// Returns the bytes as a `String` decoded leniently: a server may send a
    /// header in any charset, and throwing on invalid UTF-8 would turn one
    /// badly-encoded message into a dead mailbox. Anything that needs the raw
    /// bytes uses `read(exactly:)` instead.
    func readLine() async throws -> String {
        while true {
            if let range = buffer.range(of: Data([0x0D, 0x0A])) {
                let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return Self.decode(line)
            }
            try await fill()
        }
    }

    /// Exactly `count` bytes, for an IMAP literal. The literal's length comes
    /// from the `{n}` the server just sent, so this must not stop at a CRLF —
    /// a message body is full of them.
    func read(exactly count: Int) async throws -> Data {
        while buffer.count < count {
            try await fill()
        }
        let out = buffer.prefix(count)
        buffer.removeFirst(count)
        return Data(out)
    }

    /// Pulls one chunk from the socket into the buffer, or throws.
    private func fill() async throws {
        guard isOpen else { throw ConnectionError.notConnected }
        let chunk: Data = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { [connection] in
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
                        data, _, isComplete, error in
                        if let error { c.resume(throwing: Self.map(error)); return }
                        if let data, !data.isEmpty { c.resume(returning: data); return }
                        // No data and no error: the peer closed. Surfacing this
                        // as .closed rather than looping is what stops a
                        // half-open connection spinning the CPU forever.
                        c.resume(throwing: isComplete ? ConnectionError.closed
                                                      : ConnectionError.closed)
                    }
                }
            }
            group.addTask { [timeout] in
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ConnectionError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw ConnectionError.closed }
            return first
        }
        buffer.append(chunk)
    }

    // MARK: - Helpers

    /// Delegates to `MailText`, which is Foundation-only so the parsers that
    /// also need it can be compiled and tested on a host without `Network`.
    static func decode(_ data: Data) -> String { MailText.decode(data) }

    private static func map(_ error: NWError) -> ConnectionError {
        switch error {
        case .tls(let status):  return .tls("TLS status \(status)")
        case .posix(let code):  return .posix("POSIX \(code.rawValue)")
        default:                return .posix(String(describing: error))
        }
    }
}

#endif
