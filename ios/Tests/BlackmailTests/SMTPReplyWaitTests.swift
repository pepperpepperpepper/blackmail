import XCTest
@testable import Blackmail

/// Which of `SMTPClient`'s reads may wait on the long bound.
///
/// The conversation runs over a transport that answers the way Gmail's
/// submission server does and notes, for every line it hands back, how long
/// the client allowed the read to wait. Nothing is sent anywhere.
final class SMTPReplyWaitTests: XCTestCase {

    override func tearDown() {
        // `send` leaves its transcript in the temporary directory, as it does
        // on the device, where that is the evidence. Here it is litter, and
        // a failed send leaves it under the other name.
        for outcome in ["ok", "fail"] {
            let transcript = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
            try? FileManager.default.removeItem(atPath: transcript)
        }
        super.tearDown()
    }

    /// Only the reply to the letter itself: the 250 after DATA's terminating
    /// dot, which comes once the whole letter has crossed his uplink and
    /// Gmail has taken it. Every other reply answers a command line and keeps
    /// the short bound, so a server that has gone quiet is still found out
    /// in seconds.
    func testOnlyTheReplyToTheLetterItselfWaitsOnTheLongBound() async throws {
        let transport = ScriptedSubmission()
        let account = MailAccount(address: "owner@example.com", username: "owner@example.com")
        let client = SMTPClient(account: account, transport: { _, _ in transport })

        try await client.send(Data("Subject: Sunday\r\n\r\nSee you at one.\r\n".utf8),
                              from: "owner@example.com", to: ["carlo@example.org"],
                              password: "app-password")

        let reads = await transport.reads
        XCTAssertEqual(reads.filter { $0.wait == .afterUpload }.map(\.line),
                       ["250 2.0.0 OK queued as 1234"])
        XCTAssertEqual(reads.map(\.line).last, "221 2.0.0 closing connection")
        XCTAssertEqual(reads.filter { $0.wait == .ordinary }.count, reads.count - 1)
    }
}

/// Gmail's submission server, as far as one letter needs it.
private actor ScriptedSubmission: MailTransport {

    struct Read {
        let line: String
        let wait: ReplyWait
    }

    private(set) var reads: [Read] = []
    private var pending: [String] = []
    private var inbound = Data()
    private var inData = false

    func open() async throws {
        pending.append("220 smtp.gmail.com ESMTP ready")
    }

    func close() {}

    func write(_ data: Data) async throws {
        inbound.append(data)
        while true {
            if inData {
                guard let end = inbound.range(of: Data("\r\n.\r\n".utf8)) else { return }
                inbound.removeSubrange(inbound.startIndex..<end.upperBound)
                inData = false
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
