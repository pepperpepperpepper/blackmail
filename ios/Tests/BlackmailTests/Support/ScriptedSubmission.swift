import Foundation
@testable import Blackmail

/// Gmail's submission server, as far as a letter needs it, and the transport
/// `SMTPClient` reaches it through. Nothing is sent anywhere.
///
/// It notes, for every line it hands back, how long the client allowed the
/// read to wait (`reads`), and keeps each letter it is given (`letters`).
///
/// Deterministic: every reply is ready the moment its command has been
/// written, and a read with nothing to come fails at once, as a silent peer
/// fails at its deadline. One instance can stand for several connections in
/// turn: each `open()` starts a fresh conversation with the greeting, as a
/// new connection would, and keeps what the earlier ones recorded.
actor ScriptedSubmission: MailTransport {

    struct Read {
        let line: String
        let wait: ReplyWait
    }

    /// Every line handed back, with the wait the client allowed for it.
    private(set) var reads: [Read] = []
    /// Each letter as the server would store it: the bytes after DATA, up to
    /// and including the CRLF in front of the terminating dot, with the
    /// dot-stuffing undone.
    private(set) var letters: [Data] = []

    private var pending: [String] = []
    private var inbound = Data()
    private var inData = false

    func open() async throws {
        pending = ["220 smtp.gmail.com ESMTP ready"]
        inbound = Data()
        inData = false
    }

    func close() {}

    func write(_ data: Data) async throws {
        inbound.append(data)
        while true {
            if inData {
                guard let end = inbound.range(of: Data("\r\n.\r\n".utf8)) else { return }
                let stuffed = String(decoding: inbound[inbound.startIndex..<end.lowerBound],
                                     as: UTF8.self) + "\r\n"
                inbound.removeSubrange(inbound.startIndex..<end.upperBound)
                inData = false
                var letter = stuffed.replacingOccurrences(of: "\r\n..", with: "\r\n.")
                if letter.hasPrefix("..") { letter.removeFirst() }
                letters.append(Data(letter.utf8))
                pending.append("250 2.0.0 OK queued as 1234")
                continue
            }
            guard let end = inbound.range(of: Data("\r\n".utf8)) else { return }
            let line = String(decoding: inbound[inbound.startIndex..<end.lowerBound], as: UTF8.self)
            inbound.removeSubrange(inbound.startIndex..<end.upperBound)
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
            pending.append("221 2.0.0 closing connection")
        } else {
            pending.append("502 5.5.1 Unrecognized command")
        }
    }

    func writeLine(_ line: String) async throws {
        try await write(Data((line + "\r\n").utf8))
    }

    func readLine(_ wait: ReplyWait) async throws -> String {
        guard !pending.isEmpty else { throw MailTransportError.timedOut }
        let line = pending.removeFirst()
        reads.append(Read(line: line, wait: wait))
        return line
    }

    func read(exactly count: Int) async throws -> Data {
        throw MailTransportError.closed
    }
}
