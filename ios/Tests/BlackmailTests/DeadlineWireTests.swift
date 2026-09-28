import XCTest
@testable import Blackmail

/// The transport's deadlines through the real `IMAPClient`, over
/// `ScriptedIMAPServer`, whose transport races its connect, reads and writes
/// exactly as `TLSConnection` does.
///
/// Deadlines here are tens of milliseconds where the device's are seconds,
/// and every test that waits on one is bounded by `finishing`, so a deadline
/// that failed to fire fails the test instead of hanging the suite.
final class DeadlineWireTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private var server: ScriptedIMAPServer!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        server = nil
        super.tearDown()
    }

    private func connectedClient() async throws -> IMAPClient {
        let client = IMAPClient(account: server.account, transport: server.transportFactory)
        try await client.connect(password: server.password)
        _ = try await client.searchAll(in: Server.inbox)
        return client
    }

    private var inboxValidity: UInt32 { server.uidValidity(of: Server.inbox) }

    // MARK: - Silence

    /// The reply to a FETCH never comes in time: the socket died mid-reply,
    /// or a roam left it half open. The read is cut off at its deadline and
    /// the connection closed. The reply then turns up late, and nothing ever
    /// reads it: the next command, on a new connection, gets its own answer.
    func testAReplyThatMissesItsDeadlineIsNeverReadAsAnotherCommandsAnswer() async throws {
        server.timeout = .milliseconds(20)
        let client = try await connectedClient()
        let uids = server.uids(in: Server.inbox)
        let validity = inboxValidity
        server.holdReplies(to: "UID FETCH")

        let started = ContinuousClock.now
        do {
            _ = try await finishing(within: 1) {
                try await client.fetchBody(uid: uids[0], section: nil, in: Server.inbox, validity: validity)
            }
            XCTFail("a reply that never came cannot have been read")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - started, .milliseconds(20))
        let connected = await client.isConnected
        XCTAssertFalse(connected)

        // Late. The connection it was meant for has gone.
        await server.releaseReplies(to: "UID FETCH")

        let password = server.password
        let raw = try await finishing {
            try await client.connect(password: password)
            return try await client.fetchBody(uid: uids[1], section: nil, in: Server.inbox,
                                              validity: validity)
        }
        let body = String(decoding: raw, as: UTF8.self)
        XCTAssertTrue(body.contains("<letter-2@example.org>"), body)
        XCTAssertFalse(body.contains("<letter-1@example.org>"))
        XCTAssertEqual(server.connectionsOpened, 2)
    }

    /// A connection whose TLS handshake never finishes: a middlebox that
    /// takes the SYN and then sits on the ClientHello. `open()` is bounded
    /// as a whole, not only its TCP half.
    func testAConnectWhoseHandshakeNeverFinishesFailsAtTheDeadline() async throws {
        server.timeout = .milliseconds(20)
        server.handshakeStalls = true
        let client = IMAPClient(account: server.account, transport: server.transportFactory)
        let password = server.password
        do {
            try await finishing(within: 1) { try await client.connect(password: password) }
            XCTFail("a handshake that never finished cannot have connected")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        XCTAssertEqual(server.connectionsOpened, 0)

        // And the gate it held while connecting has been let go of.
        server.handshakeStalls = false
        try await finishing { try await client.connect(password: password) }
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// And what that connect leaves behind is nothing. Its handshake is
    /// still waiting on the link when the deadline fires, and no link
    /// promises another word about it once it has been let go of, so
    /// closing the transport has to end it. Left waiting, it would hold a
    /// task and the transport, and on the device the connection with them,
    /// for good: one more for every attempt on a network that swallows the
    /// handshake.
    func testAConnectCutOffAtItsDeadlineLeavesNothingWaitingOnTheLink() async throws {
        server.timeout = .milliseconds(20)
        server.handshakeStalls = true
        let client = IMAPClient(account: server.account, transport: server.transportFactory)
        let password = server.password
        do {
            try await finishing(within: 1) { try await client.connect(password: password) }
            XCTFail("a handshake that never finished cannot have connected")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }

        // A second at most. The client let go of the transport when the
        // connect failed, so only a task still waiting on it can hold it.
        for _ in 0..<1_000 {
            if server.transportsInMemory == 0 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(server.transportsInMemory, 0,
                       "the connect cut off at its deadline is still waiting on its link")
    }

    // MARK: - Writes

    /// An uplink that has stopped: not one piece of the command goes out.
    /// The write is cut off at the deadline rather than waiting forever for
    /// a line that is not coming back.
    func testAWriteThatStopsMovingIsCutOffAtTheDeadline() async throws {
        server.timeout = .milliseconds(20)
        let client = try await connectedClient()
        let uid = try XCTUnwrap(server.uids(in: Server.inbox).first)
        let validity = inboxValidity
        server.clearLog()
        server.uplinkDelay = .seconds(30)

        do {
            try await finishing(within: 1) {
                try await client.store(uid: uid, flag: "\\Flagged", set: true,
                                       in: Server.inbox, validity: validity)
            }
            XCTFail("a write that never left cannot have been answered")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        XCTAssertEqual(server.log, [])
        let connected = await client.isConnected
        XCTAssertFalse(connected)
    }

    /// A draft carrying photographs, saved over a slow uplink. Every piece
    /// of the upload goes inside the deadline and the whole of it takes
    /// several deadlines; then Gmail takes longer than an ordinary deadline
    /// to answer, as it does once it has the whole letter to file. Neither
    /// is a dead line, and neither may be cut off. The uplink's time is
    /// charged by size, so the same letter handed over in one lump would
    /// take all of it inside one deadline, and be cut off.
    func testASlowButProgressingAppendIsNotCutOff() async throws {
        server.timeout = .milliseconds(20)
        let client = IMAPClient(account: server.account, transport: server.transportFactory)
        try await client.connect(password: server.password)

        let pieces = 10
        let body = String(repeating: String(repeating: "x", count: 1_022) + "\r\n",
                          count: pieces * TransportDeadline.writeChunkBytes / 1_024)
        let raw = Data(("From: owner@example.com\r\nTo: carlo@example.org\r\n"
                        + "Subject: Photos from Sunday\r\nMessage-ID: <photos@example.com>\r\n\r\n"
                        + body).utf8)
        server.uplinkDelay = .milliseconds(3)
        server.delays = ["APPEND": .milliseconds(40)]

        let started = ContinuousClock.now
        let appended = try await finishing {
            try await client.append(raw, to: Server.drafts, flags: ["\\Draft", "\\Seen"])
        }
        XCTAssertGreaterThan(ContinuousClock.now - started, .milliseconds(60),
                             "the upload and its answer should outlast several deadlines")

        let uid = try XCTUnwrap(appended?.uid)
        XCTAssertEqual(server.letter(uid: uid, in: Server.drafts)?.subject, "Photos from Sunday")
        XCTAssertEqual(server.log.last?.verb, "APPEND")
        XCTAssertEqual(server.log.last?.status, "OK")
        let connected = await client.isConnected
        XCTAssertTrue(connected)
    }
}
