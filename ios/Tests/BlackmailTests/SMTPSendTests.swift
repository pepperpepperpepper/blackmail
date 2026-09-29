import XCTest
@testable import Blackmail

/// Where a send ends. The letter is delivered at the 250 after DATA, and
/// `send` returns there: QUIT, the close and the transcript follow without
/// anyone waiting on them, and nothing after that 250 can make the letter an
/// error. Driven against a scripted submission server; nothing is sent
/// anywhere.
final class SMTPSendTests: XCTestCase {

    private let account = MailAccount(address: "owner@example.com", username: "owner@example.com")
    private let letter = Data("Subject: Sunday\r\n\r\nSee you at one.\r\n".utf8)

    override func setUp() {
        super.setUp()
        Diagnostics.clear()
        // A session is named for the second it began in, so a send made
        // earlier in the same second as this test's shares its name. A file
        // it left, from a test that failed before it was let go of, would
        // pass this test's checks for its own.
        for outcome in ["ok", "fail"] { try? FileManager.default.removeItem(atPath: transcript(outcome)) }
    }

    override func tearDown() {
        for outcome in ["ok", "fail"] { try? FileManager.default.removeItem(atPath: transcript(outcome)) }
        super.tearDown()
    }

    /// Where `CaptureProbe` puts a send's transcript, by default the last
    /// one's.
    private func transcript(_ outcome: String, session: String = CaptureProbe.session) -> String {
        (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("blackmail-send-\(session)-\(outcome).txt")
    }

    /// Waits, a millisecond at a time and never for more than a second,
    /// until `condition` holds.
    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    private func client(_ server: ScriptedSubmission) -> SMTPClient {
        SMTPClient(account: account, transport: { _, _ in server })
    }

    // MARK: - Returning at the 250

    /// A server that holds back its 221, as one does that is slow to say
    /// goodbye, or a line that died after the letter went: `send` has
    /// returned by then, having never read it. It used to wait for the 221,
    /// and on a dead line for the whole read deadline, with the letter
    /// already delivered and the composer still up. QUIT is still written,
    /// the connection still closed, and the transcript still written, after.
    func testSendReturnsAtTheLettersReplyWithoutWaitingForQUITs() async throws {
        let server = ScriptedSubmission(holdsQuitReply: true)
        let client = client(server)
        let letter = letter

        try await finishing(within: 1) {
            try await client.send(letter, from: "owner@example.com", to: ["carlo@example.org"],
                                  password: "app-password")
        }
        await client.lettingGo?.value

        let reads = await server.reads.map(\.line)
        XCTAssertEqual(reads.last, "250 2.0.0 OK queued as 1234", "nothing read after the letter's reply")
        let quit = await server.receivedQuit
        let closed = await server.isClosed
        XCTAssertTrue(quit, "QUIT is still written")
        XCTAssertTrue(closed, "and the connection closed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: transcript("ok")),
                      "the transcript is still written (B-034)")
        await server.releaseQuitReply()
    }

    /// Everything after the 250 comes after the return: while the QUIT is
    /// still going out, `send` has returned, the connection is still open
    /// and there is no transcript. They used to come before it, and a
    /// server that says goodbye at once cannot tell the two orders apart.
    /// The transcript is filed under the session of the letter it is the
    /// transcript of, not under whichever has begun since, as the next
    /// letter's would have by the time it is written.
    func testTheGoodbyeTheCloseAndTheTranscriptAllComeAfterTheReturn() async throws {
        let server = ScriptedSubmission(holdsQuit: true)
        let client = client(server)
        let letter = letter

        try await finishing(within: 1) {
            try await client.send(letter, from: "owner@example.com", to: ["carlo@example.org"],
                                  password: "app-password")
        }
        let session = CaptureProbe.session
        try await until { await server.isHoldingQuit }
        let closedFirst = await server.isClosed
        XCTAssertFalse(closedFirst, "closed before the QUIT had gone")
        XCTAssertFalse(FileManager.default.fileExists(atPath: transcript("ok")),
                       "the transcript was written before the return")

        // The next letter begins while this one is still being let go of.
        CaptureProbe.beginSession("next")
        await server.releaseQuit()
        await client.lettingGo?.value

        let quit = await server.receivedQuit
        let closed = await server.isClosed
        XCTAssertTrue(quit)
        XCTAssertTrue(closed)
        let own = transcript("ok", session: session)
        XCTAssertTrue(FileManager.default.fileExists(atPath: own), "filed under its own session")
        XCTAssertFalse(FileManager.default.fileExists(atPath: transcript("ok")),
                       "filed under the next letter's")
        try? FileManager.default.removeItem(atPath: own)
    }

    /// A connect that fails, as one does with no signal: `send` says it
    /// could not connect, and the connection is still closed after it, for
    /// the reason `send` gives. Nothing was said to the server, so there is
    /// no QUIT and no transcript.
    func testAConnectThatFailsIsStillLetGoOf() async throws {
        let server = ScriptedSubmission(failsToOpen: true)
        let client = client(server)

        do {
            try await client.send(letter, from: "owner@example.com", to: ["carlo@example.org"],
                                  password: "app-password")
            XCTFail("a letter went without a connection")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        await client.lettingGo?.value

        let closed = await server.isClosed
        let quit = await server.receivedQuit
        XCTAssertTrue(closed, "closed although it never opened")
        XCTAssertFalse(quit)
        for outcome in ["ok", "fail"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: transcript(outcome)), outcome)
        }
    }

    /// The line goes the moment the 250 has been read: QUIT cannot be
    /// written and there is nothing to close. The letter went, and that is
    /// what `send` says.
    func testALineThatDiesAfterTheLettersReplyStillCountsAsSent() async throws {
        let server = ScriptedSubmission(hangsUpAfterLetter: true)
        let client = client(server)

        try await client.send(letter, from: "owner@example.com", to: ["carlo@example.org"],
                              password: "app-password")
        await client.lettingGo?.value

        let letters = await server.letters
        XCTAssertEqual(letters.count, 1)
        let quit = await server.receivedQuit
        XCTAssertFalse(quit, "the QUIT could not be written")
        XCTAssertTrue(FileManager.default.fileExists(atPath: transcript("ok")))
    }

    /// The server throws the letter away at the end of DATA: that is still
    /// an error, the size refusal still its own, and the connection is still
    /// let go of the same way, with the transcript under `-fail`.
    func testALetterRefusedAtTheEndOfDATAIsStillNotSent() async throws {
        for (reply, expected) in [("554 5.7.0 Message rejected", MailError.notSent),
                                  ("552 5.3.4 Message size exceeds fixed limit",
                                   MailError.messageTooLarge)] {
            let server = ScriptedSubmission(letterReply: reply)
            let client = client(server)
            do {
                try await client.send(letter, from: "owner@example.com", to: ["carlo@example.org"],
                                      password: "app-password")
                XCTFail("\(reply) was taken for a delivered letter")
            } catch {
                XCTAssertEqual(error as? MailError, expected, reply)
            }
            await client.lettingGo?.value
            let quit = await server.receivedQuit
            let closed = await server.isClosed
            XCTAssertTrue(quit, reply)
            XCTAssertTrue(closed, reply)
            XCTAssertTrue(FileManager.default.fileExists(atPath: transcript("fail")), reply)
            // Each send is its own session, and the next may start in
            // another second, so this one's file is cleared here.
            try? FileManager.default.removeItem(atPath: transcript("fail"))
        }
    }

    // MARK: - How much has gone

    /// The letter's write says how much of it the network has taken, a
    /// piece at a time, ending at the whole payload; the command lines
    /// around it say nothing.
    func testTheLettersWriteReportsItsProgress() async throws {
        let server = ScriptedSubmission()
        let client = client(server)
        let body = String(repeating: String(repeating: "x", count: 998) + "\r\n", count: 200)
        let raw = Data(("Subject: Photos\r\n\r\n" + body).utf8)
        let reports = Reports()

        try await client.send(raw, from: "owner@example.com", to: ["carlo@example.org"],
                              password: "app-password", progress: { reports.add($0, $1) })
        await client.lettingGo?.value

        let payload = SMTPClient.dataPayload(raw).count
        let piece = TransportDeadline.writeChunkBytes
        XCTAssertEqual(reports.all.map(\.written),
                       Array(stride(from: piece, to: payload, by: piece)) + [payload])
        XCTAssertEqual(Set(reports.all.map(\.total)), [payload])
    }

    /// And from the repository, which is what the composer calls: the
    /// letter goes once, the progress reaches the caller, and the call
    /// returns at the 250 while QUIT's 221 is still held back.
    func testTheRepositoryPassesTheProgressOnAndReturnsAtTheLettersReply() async throws {
        let server = ScriptedSubmission(holdsQuitReply: true)
        let book = RecipientBook(defaults: UserDefaults(suiteName: "SMTPSendTests")!)
        defer { UserDefaults(suiteName: "SMTPSendTests")?.removePersistentDomain(forName: "SMTPSendTests") }
        let repository = IMAPMailRepository(account: account, password: "app-password",
                                            transport: { _, _ in server }, recipients: book)
        let draft = Draft(to: ["carlo@example.org"], subject: "The garden",
                          body: String(repeating: "A long letter about the garden. ", count: 3_000))
        let reports = Reports()

        try await finishing(within: 1) {
            try await repository.send(draft, progress: { reports.add($0, $1) })
        }

        let letters = await server.letters
        XCTAssertEqual(letters.count, 1)
        XCTAssertGreaterThan(reports.all.count, 1)
        XCTAssertEqual(reports.all.last?.written, reports.all.last?.total)
        // The connection is let go of after the return; wait for its
        // transcript, so it is not left behind by the test.
        try await until { FileManager.default.fileExists(atPath: self.transcript("ok")) }
        await server.releaseQuitReply()
    }
}

/// Progress reports, from any thread.
private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var reports: [(written: Int, total: Int)] = []

    var all: [(written: Int, total: Int)] {
        lock.lock()
        defer { lock.unlock() }
        return reports
    }

    func add(_ written: Int, _ total: Int) {
        lock.lock()
        reports.append((written, total))
        lock.unlock()
    }
}
