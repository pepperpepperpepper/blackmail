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
/// the close, the QUIT itself when `holdsQuit`, whose write waits until
/// `releaseQuit()`, and the letter's reply when `holdsLetterReply`, which a
/// read waits for until `releaseLetterReply()`, `hangUp(with:)` or
/// `deadlinePasses()`.
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
    /// The server's first words.
    private let greeting: String
    /// What AUTH PLAIN is answered with, in place of 235 or `refusesPassword`'s
    /// 535: Gmail's "454 4.7.0" for a login it cannot deal with now, or its
    /// 534 of several lines, CRLF between them.
    private let authReply: String?
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
    /// The connection goes as the letter's terminating dot arrives, before
    /// its reply: a DATA cut off before the 250, with the letter perhaps
    /// taken, perhaps not. Every read after it fails with `cutWith`.
    private let hangsUpBeforeLetterReply: Bool
    /// The letter's reply kept back until `releaseLetterReply()` or
    /// `hangUp()`: a server slow to answer, or a line dying under it.
    private let holdsLetterReply: Bool
    /// AUTH answered 535, as Gmail refuses an app password revoked.
    private let refusesPassword: Bool
    /// The one password AUTH PLAIN takes, where set: any other is answered
    /// 535. Nil takes any, unless `refusesPassword`.
    private let takesOnly: String?
    /// RCPT TO answered 550 for these addresses, in upper case.
    private let refusedRecipients: Set<String>

    private var pending: [String] = []
    private var inbound = Data()
    private var inData = false
    private var quitHeld = false
    private var hungUp = false
    private var waitingForQuitReply: CheckedContinuation<Void, Error>?
    private var quitParked: CheckedContinuation<Void, Never>?
    private var quitReleased = false
    private var letterHeld = false
    private var waitingForLetterReply: CheckedContinuation<Void, Error>?
    /// What a read or write fails with once the line has gone: `.closed`, a
    /// peer that hung up, `.posix`, a link that failed, or `.timedOut`, a
    /// deadline that passed.
    private var lineError: MailTransportError

    init(letterReply: String = "250 2.0.0 OK queued as 1234",
         greeting: String = "220 smtp.gmail.com ESMTP ready",
         authReply: String? = nil,
         holdsQuitReply: Bool = false,
         hangsUpAfterLetter: Bool = false,
         holdsQuit: Bool = false,
         failsToOpen: Bool = false,
         hangsUpBeforeLetterReply: Bool = false,
         cutWith: MailTransportError = .closed,
         holdsLetterReply: Bool = false,
         refusesPassword: Bool = false,
         takesOnly password: String? = nil,
         refusedRecipients: Set<String> = []) {
        self.letterReply = letterReply
        self.greeting = greeting
        self.authReply = authReply
        self.lineError = cutWith
        self.holdsQuitReply = holdsQuitReply
        self.hangsUpAfterLetter = hangsUpAfterLetter
        self.holdsQuit = holdsQuit
        self.failsToOpen = failsToOpen
        self.hangsUpBeforeLetterReply = hangsUpBeforeLetterReply
        self.holdsLetterReply = holdsLetterReply
        self.refusesPassword = refusesPassword
        self.takesOnly = password
        self.refusedRecipients = Set(refusedRecipients.map { $0.uppercased() })
    }

    /// A letter's reply is being held, the letter itself arrived.
    var isHoldingLetterReply: Bool { letterHeld }

    /// Lets the held reply to the letter go.
    func releaseLetterReply() {
        guard letterHeld else { return }
        letterHeld = false
        pending.append(letterReply)
        waitingForLetterReply?.resume()
        waitingForLetterReply = nil
    }

    /// The line dies: every read and write from now on fails with `error`,
    /// a read waiting for the letter's reply included.
    func hangUp(with error: MailTransportError = .closed) {
        hungUp = true
        lineError = error
        letterHeld = false
        waitingForLetterReply?.resume(throwing: error)
        waitingForLetterReply = nil
    }

    /// The read waiting for the letter's reply reaches its deadline, as the
    /// device's does after a suspension that outlived it: the transport
    /// closes itself and the read fails with `.timedOut`, as
    /// `LinkTransport.fill` has it.
    func deadlinePasses() {
        hangUp(with: .timedOut)
        isClosed = true
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
        pending.append(greeting)
    }

    func close() {
        isClosed = true
        waitingForQuitReply?.resume(throwing: MailTransportError.closed)
        waitingForQuitReply = nil
        waitingForLetterReply?.resume(throwing: MailTransportError.closed)
        waitingForLetterReply = nil
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
        try checkLine()
        if holdsQuit, !quitReleased, data == Data("QUIT\r\n".utf8) {
            await withCheckedContinuation { quitParked = $0 }
            try checkLine()
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
                if hangsUpBeforeLetterReply {
                    hungUp = true
                } else if holdsLetterReply {
                    letterHeld = true
                } else {
                    pending.append(letterReply)
                }
                continue
            }
            guard let end = inbound.range(of: Data("\r\n".utf8)) else { return }
            let line = String(decoding: inbound[inbound.startIndex..<end.lowerBound], as: UTF8.self)
            inbound.removeSubrange(inbound.startIndex..<end.upperBound)
            commands.append(line)
            answer(line.uppercased(), as: line)
        }
    }

    /// `command` upper-cased, and `line` as it came, whose base64 the
    /// upper-casing would spoil.
    private func answer(_ command: String, as line: String) {
        if command.hasPrefix("EHLO") {
            pending += ["250-smtp.gmail.com at your service", "250-SIZE 35882577",
                        "250-8BITMIME", "250-AUTH LOGIN PLAIN", "250 SMTPUTF8"]
        } else if command.hasPrefix("AUTH PLAIN") {
            let refused = refusesPassword
                || takesOnly.map { $0 != Self.password(inPlain: line) } == true
            // A reply of several lines, as Gmail's 534 is, is written with
            // CRLF between them, and handed back a line at a time.
            pending += (authReply ?? (refused ? "535 5.7.8 Username and Password not accepted"
                                              : "235 2.7.0 Accepted"))
                .components(separatedBy: "\r\n")
        } else if command.hasPrefix("RCPT TO"),
                  refusedRecipients.contains(where: { command.contains("<\($0)>") }) {
            pending.append("550 5.1.1 The email account that you tried to reach does not exist")
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

    /// The password in `AUTH PLAIN <base64>`, nil if it has none.
    static func password(inPlain line: String) -> String? {
        guard let blob = line.split(separator: " ").last,
              let data = Data(base64Encoded: String(blob)) else { return nil }
        return String(decoding: data, as: UTF8.self).split(separator: "\0",
            omittingEmptySubsequences: false).last.map(String.init)
    }

    func writeLine(_ line: String) async throws {
        try await write(Data((line + "\r\n").utf8))
    }

    /// Fails once the line has gone: closed by the client, or cut.
    private func checkLine() throws {
        if hungUp { throw lineError }
        if isClosed { throw MailTransportError.closed }
    }

    func readLine(_ wait: ReplyWait) async throws -> String {
        try checkLine()
        if pending.isEmpty, quitHeld {
            try await withCheckedThrowingContinuation { waitingForQuitReply = $0 }
        }
        if pending.isEmpty, letterHeld {
            try await withCheckedThrowingContinuation { waitingForLetterReply = $0 }
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

    /// Never asked: `SMTPClient` times none of its replies.
    func startTimingQuiet(on clock: @escaping @Sendable () -> Date) {}

    var longestQuiet: TimeInterval { 0 }
}
