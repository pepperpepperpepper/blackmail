import XCTest
@testable import Blackmail

/// The exchange gate in `IMAPClient` and what cancellation does at it, over
/// `ScriptedIMAPServer`.
///
/// The rule under test: a task cancelled before it reaches the gate, or
/// while it waits in line, throws `CancellationError` and writes nothing;
/// one cancelled after it has the gate finishes its exchange and gets its
/// reply, and the connection it was using stays up for the next command.
final class ExchangeGateTests: XCTestCase {

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

    /// Logged in, the Inbox selected, and the log cleared.
    private func connectedClient() async throws -> IMAPClient {
        let client = IMAPClient(account: server.account, transport: server.transportFactory)
        try await client.connect(password: server.password)
        _ = try await client.searchAll(in: Server.inbox)
        server.clearLog()
        return client
    }

    private var inboxValidity: UInt32 { server.uidValidity(of: Server.inbox) }

    /// A millisecond at a time, for a second at most.
    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    private func flagged(_ uid: UInt32) -> Bool {
        server.flags(uid: uid, in: Server.inbox).contains("\\Flagged")
    }

    // MARK: - Cancelled on the wire

    /// A search replaced by the next keystroke while its reply is on its way
    /// back. It gets the reply, the connection is still up, and the next
    /// command reads its own answer rather than the tail of this one.
    func testACommandCancelledOnTheWireStillGetsItsReplyAndTheConnectionStaysUp() async throws {
        let client = try await connectedClient()
        server.holdReplies(to: "UID SEARCH")
        let search = Task { try await client.search("SUBJECT \"garden\"", in: Server.inbox).uids }
        try await until { self.server.log.contains { $0.verb == "UID SEARCH" } }

        search.cancel()
        await server.releaseReplies(to: "UID SEARCH")
        let hits = try await finishing { try await search.value }

        let gardens = server.uids(in: Server.inbox).filter {
            server.letter(uid: $0, in: Server.inbox)?.subject.contains("garden") == true
        }
        XCTAssertFalse(gardens.isEmpty)
        XCTAssertEqual(hits, gardens)
        let connected = await client.isConnected
        XCTAssertTrue(connected, "cancelling a command cost the connection")

        let all = try await finishing { try await client.searchAll(in: Server.inbox).uids }
        XCTAssertEqual(all, server.uids(in: Server.inbox))
        XCTAssertEqual(server.connectionsOpened, 1)
        XCTAssertEqual(server.log.map(\.status), ["OK", "OK"])
    }

    // MARK: - Cancelled in line

    /// Three taps queued behind a slow command, the middle one cancelled
    /// while it waits. It comes back at once, without waiting for the command
    /// ahead of it, and nothing of it reaches the wire. The other two go in
    /// the order they arrived.
    func testAWaiterCancelledInLineNeverWritesItsCommandAndTheRestKeepTheirOrder() async throws {
        let client = try await connectedClient()
        let uids = server.uids(in: Server.inbox)
        let validity = inboxValidity
        server.holdReplies(to: "UID SEARCH")
        let first = Task { try await client.searchAll(in: Server.inbox).uids }
        try await until { self.server.log.contains { $0.verb == "UID SEARCH" } }

        var queued: [Task<Void, Error>] = []
        for (position, uid) in uids.prefix(3).enumerated() {
            queued.append(Task {
                try await client.store(uid: uid, flag: "\\Flagged", set: true,
                                       in: Server.inbox, validity: validity)
            })
            try await until { await client.waitingForExchange == position + 1 }
        }
        let taps = queued

        taps[1].cancel()
        do {
            try await finishing(within: 1) { try await taps[1].value }
            XCTFail("a command cancelled before its turn was sent anyway")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        // Still held, so that came back without waiting for its turn.
        XCTAssertEqual(server.log.map(\.verb), ["UID SEARCH"])
        let waiting = await client.waitingForExchange
        XCTAssertEqual(waiting, 2)

        await server.releaseReplies(to: "UID SEARCH")
        let all = try await finishing { try await first.value }
        XCTAssertEqual(all, uids)
        try await finishing { try await taps[0].value }
        try await finishing { try await taps[2].value }

        XCTAssertEqual(server.log.map(\.command),
                       ["UID SEARCH ALL",
                        "UID STORE \(uids[0]) +FLAGS.SILENT (\\Flagged)",
                        "UID STORE \(uids[2]) +FLAGS.SILENT (\\Flagged)"])
        XCTAssertEqual([flagged(uids[0]), flagged(uids[1]), flagged(uids[2])], [true, false, true])

        // Leaving the line did not wedge the gate.
        try await finishing {
            try await client.store(uid: uids[1], flag: "\\Flagged", set: true,
                                   in: Server.inbox, validity: validity)
        }
        XCTAssertTrue(flagged(uids[1]))
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// Two lines behind the command on the wire. Queued in the order
    /// background, interactive, background, interactive, background, then
    /// the rest of the writes, a MOVE, the NOOP that probes before a
    /// write and a draft's EXPUNGE, and last a close. They go interactive
    /// first and first come first served within each line, so the writes
    /// reach the server in the order they were made. The close waits for
    /// the background commands asked for before it. The last background
    /// command is cancelled in line and leaves without writing, as it would
    /// from a line of one.
    func testTheInteractiveLineGoesFirstAndEachLineKeepsItsOwnOrder() async throws {
        let client = try await connectedClient()
        let uids = server.uids(in: Server.inbox)
        let validity = inboxValidity
        server.holdReplies(to: "UID SEARCH")
        let first = Task { try await client.searchAll(in: Server.inbox).uids }
        try await until { self.server.log.contains { $0.verb == "UID SEARCH" } }

        let work: [@Sendable () async throws -> Void] = [
            { _ = try await client.fetchSummaries(uids: [uids[0]], in: Server.inbox, validity: validity) },
            { try await client.store(uid: uids[1], flag: "\\Flagged", set: true,
                                     in: Server.inbox, validity: validity) },
            { _ = try await client.status(Server.sent, items: ["UNSEEN"]) },
            { _ = try await client.fetchBody(uid: uids[2], section: nil, in: Server.inbox,
                                             validity: validity) },
            { _ = try await client.fetchSummaries(uids: [uids[3]], in: Server.inbox, validity: validity) },
            { try await client.move(uid: uids[4], from: Server.inbox, validity: validity, to: Server.sent) },
            { try await client.noop() },
            { try await client.expunge(uid: uids[5], in: Server.inbox, validity: validity) },
            { await client.disconnect() },
        ]
        var queued: [Task<Void, Error>] = []
        for (position, run) in work.enumerated() {
            queued.append(Task { try await run() })
            try await until { await client.waitingForExchange == position + 1 }
        }
        let tasks = queued

        tasks[4].cancel()
        do {
            try await finishing(within: 1) { try await tasks[4].value }
            XCTFail("a background command cancelled in line was sent anyway")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(server.log.map(\.verb), ["UID SEARCH"])

        await server.releaseReplies(to: "UID SEARCH")
        _ = try await finishing { try await first.value }
        for (position, task) in tasks.enumerated() where position != 4 {
            try await finishing { try await task.value }
        }

        XCTAssertEqual(server.log.map(\.command).dropFirst(), [
            "UID STORE \(uids[1]) +FLAGS.SILENT (\\Flagged)",
            "UID FETCH \(uids[2]) (UID BODY.PEEK[])",
            "UID MOVE \(uids[4]) \"[Gmail]/Sent Mail\"",
            "NOOP",
            "UID STORE \(uids[5]) +FLAGS.SILENT (\\Deleted)",
            "UID EXPUNGE \(uids[5])",
            "UID FETCH \(uids[0]) (UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODYSTRUCTURE "
                + "X-GM-LABELS X-GM-THRID)",
            "STATUS \"[Gmail]/Sent Mail\" (UNSEEN)",
            "LOGOUT",
        ])
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// A task already cancelled when it reaches a free gate is refused
    /// there too. Whether a cancelled caller's command goes out must not
    /// depend on whether somebody else happened to be using the socket.
    func testACallerAlreadyCancelledSendsNothingEvenWhenTheSocketIsFree() async throws {
        let client = try await connectedClient()
        let uid = try XCTUnwrap(server.uids(in: Server.inbox).first)
        let validity = inboxValidity
        let tap = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await client.store(uid: uid, flag: "\\Flagged", set: true,
                                   in: Server.inbox, validity: validity)
        }
        do {
            try await finishing { try await tap.value }
            XCTFail("a cancelled caller's command was sent")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(server.log, [])
        XCTAssertFalse(flagged(uid))
        let connected = await client.isConnected
        XCTAssertTrue(connected)
    }

    /// Closing is the exception: a caller on its way out closes the
    /// connection whatever its own state. It still waits its turn, behind
    /// the command on the wire, rather than writing LOGOUT over that
    /// command's reply.
    func testACancelledCallerStillLogsOutAndStillWaitsItsTurnToDoIt() async throws {
        let client = try await connectedClient()
        server.holdReplies(to: "UID SEARCH")
        let search = Task { try await client.searchAll(in: Server.inbox).uids }
        try await until { self.server.log.contains { $0.verb == "UID SEARCH" } }

        let leaving = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await client.disconnect()
        }
        try await until { await client.waitingForExchange == 1 }
        XCTAssertEqual(server.log.map(\.verb), ["UID SEARCH"])

        await server.releaseReplies(to: "UID SEARCH")
        let all = try await finishing { try await search.value }
        XCTAssertEqual(all, server.uids(in: Server.inbox))
        try await finishing { await leaving.value }
        XCTAssertEqual(server.log.map(\.verb), ["UID SEARCH", "LOGOUT"])
        let connected = await client.isConnected
        XCTAssertFalse(connected)
    }
}
