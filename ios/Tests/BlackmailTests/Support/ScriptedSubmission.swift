import Foundation
@testable import Blackmail

/// Gmail's submission server, as far as one letter needs it, and the
/// transport `SMTPClient` reaches it through. Nothing is sent anywhere.
///
/// A plain `MailTransport` rather than a `LinkTransport`, so it can note, for
/// every line it hands back, how long the client allowed the read to wait
/// (`reads`), which is decided above the link. A write goes in pieces
/// through `TransportDeadline.write`, as the device's does, so the progress
/// a letter reports is the progress the device would report.
///
/// Deterministic: every reply is ready the moment its command has been
/// written, and a read with nothing to come fails at once, as a silent peer
/// fails at its deadline. The exceptions wait for the test: QUIT's 221 when
/// `holdsQuitReply`, which a read waits for until `releaseQuitReply()` or
/// the close, and the QUIT itself when `holdsQuit`, whose write waits until
/// `releaseQuit()`.
actor ScriptedSubmission: MailTransport {

    struct Read: Equatable {
        let line: String
        let wait: ReplyWait
    }

    /// Every line handed back, with the wait the client allowed for it.
    private(set) var reads: [Read] = []
    /// Every command line received, in order.
    private(set) var commands: [String] = []
    /// Each letter as it arrived after DATA, up to and including the CRLF
    /// in front of the terminating dot.
    private(set) var letters: [Data] = []
    /// Closed by the client.
    private(set) var isClosed = false

    /// What the letter's terminating dot is answered with.
    private let letterReply: String
    /// QUIT's 221 kept back until `releaseQuitReply()`: a server slow to say
    /// goodbye, or a line that has died since the letter's 250.
    private let holdsQuitReply: Bool
    /// The connection goes the moment the letter's reply has been read:
    /// every write and read after it fails.
    private let hangsUpAfterLetter: Bool
    /// The write of QUIT kept from finishing until `releaseQuit()`: a
    /// goodbye that takes its time to go, so a test can see what has and
    /// has not happened before it has.
    private let holdsQuit: Bool
    /// `open()` fails, as a connect with no route does.
    private let failsToOpen: Bool

    private var pending: [String] = []
    private var inbound = Data()
    private var inData = false
    private var quitHeld = false
    private var hungUp = false
    private var waitingForQuitReply: CheckedContinuation<Void, Error>?
    private var quitParked: CheckedContinuation<Void, Never>?
    private var quitReleased = false

    init(letterReply: String = "250 2.0.0 OK queued as 1234",
         holdsQuitReply: Bool = false,
         hangsUpAfterLetter: Bool = false,
         holdsQuit: Bool = false,
         failsToOpen: Bool = false) {
        self.letterReply = letterReply
        self.holdsQuitReply = holdsQuitReply
        self.hangsUpAfterLetter = hangsUpAfterLetter
        self.holdsQuit = holdsQuit
        self.failsToOpen = failsToOpen
    }

    var receivedQuit: Bool { commands.contains("QUIT") }

    /// A write of QUIT is waiting for `releaseQuit()`.
    var isHoldingQuit: Bool { quitParked != nil }

    /// Lets a held QUIT go, now or when it comes.
    func releaseQuit() {
        quitReleased = true
        quitParked?.resume()
        quitParked = nil
    }

    func open() async throws {
        guard !failsToOpen else { throw MailTransportError.timedOut }
        pending.append("220 smtp.gmail.com ESMTP ready")
    }

    func close() {
        isClosed = true
        waitingForQuitReply?.resume(throwing: MailTransportError.closed)
        waitingForQuitReply = nil
    }

    /// Lets the held 221 go, to a read that is waiting for it or to the
    /// next one.
    func releaseQuitReply() {
        guard quitHeld else { return }
        quitHeld = false
        pending.append("221 2.0.0 closing connection")
        waitingForQuitReply?.resume()
        waitingForQuitReply = nil
    }

    func write(_ data: Data, progress: UploadProgress?) async throws {
        guard !hungUp, !isClosed else { throw MailTransportError.closed }
        if holdsQuit, !quitReleased, data == Data("QUIT\r\n".utf8) {
            await withCheckedContinuation { quitParked = $0 }
            guard !hungUp, !isClosed else { throw MailTransportError.closed }
        }
        try await TransportDeadline.write(data, within: 5, onExpiry: {}, progress: progress) {
            [self] piece in await self.take(piece)
        }
    }

    private func take(_ piece: Data) {
        inbound.append(piece)
        while true {
            if inData {
                guard let end = inbound.range(of: Data("\r\n.\r\n".utf8)) else { return }
                letters.append(inbound.subdata(in: inbound.startIndex..<(end.lowerBound + 2)))
                inbound.removeSubrange(inbound.startIndex..<end.upperBound)
                inData = false
                pending.append(letterReply)
                continue
            }
            guard let end = inbound.range(of: Data("\r\n".utf8)) else { return }
            let line = String(decoding: inbound[inbound.startIndex..<end.lowerBound], as: UTF8.self)
            inbound.removeSubrange(inbound.startIndex..<end.upperBound)
            commands.append(line)
            answer(line.uppercased())
        }
    }

    private func answer(_ command: String) {
        if command.hasPrefix("EHLO") {
            pending += ["250-smtp.gmail.com at your service", "250-SIZE 35882577",
                        "250-8BITMIME", "250-AUTH LOGIN PLAIN", "250 SMTPUTF8"]
        } else if command.hasPrefix("AUTH PLAIN") {
            pending.append("235 2.7.0 Accepted")
        } else if command.hasPrefix("MAIL FROM") || command.hasPrefix("RCPT TO") {
            pending.append("250 2.1.0 OK")
        } else if command == "DATA" {
            inData = true
            pending.append("354 Go ahead")
        } else if command == "QUIT" {
            if holdsQuitReply {
                quitHeld = true
            } else {
                pending.append("221 2.0.0 closing connection")
            }
        } else {
            pending.append("502 5.5.1 Unrecognized command")
        }
    }

    func writeLine(_ line: String) async throws {
        try await write(Data((line + "\r\n").utf8))
    }

    func readLine(_ wait: ReplyWait) async throws -> String {
        guard !hungUp, !isClosed else { throw MailTransportError.closed }
        if pending.isEmpty, quitHeld {
            try await withCheckedThrowingContinuation { waitingForQuitReply = $0 }
        }
        guard !pending.isEmpty else { throw MailTransportError.timedOut }
        let line = pending.removeFirst()
        reads.append(Read(line: line, wait: wait))
        if hangsUpAfterLetter, line == letterReply { hungUp = true }
        return line
    }

    func read(exactly count: Int) async throws -> Data {
        throw MailTransportError.closed
    }
}
