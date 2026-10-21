import XCTest
@testable import Blackmail

/// B-091: nothing is written onto a connection the system has said has no
/// network path. Seen on the test iPad with Airplane Mode turned on while a
/// connection was open: Flag in the reading pane wrote its STORE onto the
/// connection, nothing answered, and only some 19 s later, when the stack
/// gave the connection up, did the flag go back with "Can't connect to mail
/// server."; a letter tapped meanwhile said "Loading…" for the same 19 s
/// behind it.
///
/// Over the shipping repository and client and `ScriptedIMAPServer`, whose
/// `hasNoPath` is Airplane Mode: every open link is told it has no path, as
/// `NWConnection`'s viability tells the device's, bytes written onto such a
/// link go nowhere and are never answered, and a new connection fails at
/// once, as one started with no network goes `.waiting`. The deadline is
/// five seconds and every call is given one, so a command written onto the
/// cut link fails the test by its wait as well as by `lostWrites`. The
/// device's half, the viability handler, is read from `TLSConnection`'s
/// source, which never builds on this host.
final class NoPathTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "NoPathTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var clock: ManualClock!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        server.timeout = .seconds(5)
        clock = ManualClock()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        Diagnostics.clear()
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        server = nil
        book = nil
        clock = nil
        super.tearDown()
    }

    private func makeRepository() -> IMAPMailRepository {
        let clock = self.clock!
        return IMAPMailRepository(account: server.account, password: server.password,
                                  transport: server.transportFactory, recipients: book,
                                  now: { clock.now() }, shelf: keptShelf(for: server.account))
    }

    /// A repository with the Inbox's first page listed, on connection 1,
    /// and the log and the connection log cleared after it.
    private func listed() async throws -> (IMAPMailRepository, [MessageSummary]) {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        XCTAssertEqual(server.connectionsOpened, 1)
        server.clearLog()
        Diagnostics.clear()
        return (repository, rows)
    }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    private func uid(_ id: String) -> UInt32 { UInt32(id.split(separator: "/").last ?? "")! }

    /// The connection log's lines about the path, and nothing else.
    private var pathNotes: [String] {
        Diagnostics.entries.filter { $0.direction == .note }.map(\.text)
            .filter { $0.hasPrefix("NO-PATH") || $0.hasPrefix("LINK ") }
    }

    /// Lines the client wrote, in the connection log.
    private var sentLines: [String] {
        Diagnostics.entries.filter { $0.direction == .sent }.map(\.text)
    }

    /// `body`'s failure, which must come within a second: the deadline is
    /// five.
    private func refusal(file: StaticString = #filePath, line: UInt = #line,
                         _ body: @escaping @Sendable () async throws -> Void) async -> MailError? {
        let started = ContinuousClock.now
        do {
            try await finishing(within: 1, file: file, line: line) { try await body() }
            XCTFail("refused, with no network", file: file, line: line)
            return nil
        } catch {
            XCTAssertLessThan(ContinuousClock.now - started, .milliseconds(500),
                              "refused at once", file: file, line: line)
            return error as? MailError
        }
    }

    // MARK: - Refused at once, nothing written

    /// Airplane Mode on with the connection open, and Flag: refused at
    /// once, with not a byte of the STORE written, and the connection let
    /// go of. The write is not sent; with no network the one new connection
    /// it is allowed fails at once too.
    func testAFlagWithThePathGoneIsRefusedAtOnceWithNothingWritten() async throws {
        let (repository, rows) = try await listed()
        let letter = rows[3]
        XCTAssertFalse(letter.isFlagged)

        server.hasNoPath = true
        let failure = await refusal { try await repository.setFlagged(true, on: letter) }

        XCTAssertEqual(failure, .cannotConnect)
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(server.lostWrites, [])
        XCTAssertEqual(sentLines, [])
        XCTAssertFalse(server.flags(uid: uid(letter.id), in: Server.inbox).contains("\\Flagged"))
        XCTAssertEqual(pathNotes, ["LINK viable=false", "NO-PATH UID STORE not-sent"])
        let connected = await repository.isConnected
        XCTAssertFalse(connected)
        XCTAssertEqual(server.connectionsBegun, 2)
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// The same after ninety seconds of quiet, where a write probes the
    /// connection first (B-024): the probe's NOOP is kept off the link as
    /// the STORE is, and the write is refused at once.
    func testAFlagAfterAQuietWithThePathGoneIsRefusedAtOnceProbeAndAll() async throws {
        let (repository, rows) = try await listed()
        clock.advance(by: 91)

        server.hasNoPath = true
        let failure = await refusal { try await repository.setFlagged(true, on: rows[3]) }

        XCTAssertEqual(failure, .cannotConnect)
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(server.lostWrites, [])
        XCTAssertEqual(pathNotes, ["LINK viable=false", "NO-PATH NOOP not-sent"])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// A letter opened with the path gone: its FETCH is kept off the link,
    /// and the read's one retry, on a new connection, fails at once. The
    /// pane says the letter could not be downloaded at once, not after the
    /// stack has given the connection up.
    func testALetterOpenedWithThePathGoneIsRefusedAtOnceWithNothingWritten() async throws {
        let (repository, rows) = try await listed()

        server.hasNoPath = true
        let failure = await refusal { _ = try await repository.open(rows[0]) }

        XCTAssertEqual(failure, .cannotConnect)
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(server.lostWrites, [])
        XCTAssertEqual(sentLines, [])
        XCTAssertEqual(pathNotes, ["LINK viable=false", "NO-PATH UID FETCH not-sent"])
        XCTAssertEqual(server.connectionsBegun, 2)
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// The iPad's case as it was seen: Flag in the pane, and a letter
    /// tapped straight after it, with the path gone. Both are refused at
    /// once and nothing is written; the letter used to say "Loading…" for
    /// as long as the STORE ahead of it waited.
    func testAFlagAndALetterTappedBehindItWithThePathGoneAreBothRefusedAtOnce() async throws {
        let (repository, rows) = try await listed()
        server.hasNoPath = true

        let started = ContinuousClock.now
        let flagged = Task { try await repository.setFlagged(true, on: rows[3]) }
        let opened = Task { _ = try await repository.open(rows[0]) }
        var failures: [MailError?] = []
        do { try await finishing(within: 1) { try await flagged.value } }
        catch { failures.append(error as? MailError) }
        do { try await finishing(within: 1) { try await opened.value } }
        catch { failures.append(error as? MailError) }

        XCTAssertEqual(failures, [.cannotConnect, .cannotConnect])
        XCTAssertLessThan(ContinuousClock.now - started, .milliseconds(500))
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(server.lostWrites, [])
        XCTAssertEqual(sentLines, [])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// The watch's check with the path gone: its NOOP is kept off the link
    /// too, so it is no command on the wire for his next tap to wait
    /// behind, and the check fails at once.
    func testTheWatchsCheckWithThePathGoneIsRefusedAtOnce() async throws {
        let (repository, rows) = try await listed()

        server.hasNoPath = true
        let failure = await refusal {
            _ = try await repository.news(in: "inbox", known: rows.map(\.id), searchingAnyway: false)
        }

        XCTAssertEqual(failure, .cannotConnect)
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(server.lostWrites, [])
        XCTAssertEqual(pathNotes, ["LINK viable=false", "NO-PATH NOOP not-sent"])
    }

    // MARK: - Once, never twice

    /// The connection open has no path, and there is a network for a new
    /// one: the Wi-Fi it was made on gone, the line back another way. A
    /// Delete is kept off the old link with nothing of it written, so it is
    /// a write not sent, and it goes once, on the new connection. Written
    /// onto the old link it went nowhere, and since nothing could say it
    /// had not gone, it could never be sent again: the letter stayed.
    func testADeleteKeptOffALinkWithNoPathGoesOnceOnANewConnection() async throws {
        let (repository, rows) = try await listed()
        let letter = rows[0]

        server.losePathOfOpenLinks()
        try await finishing(within: 1) { try await repository.delete(letter) }

        XCTAssertEqual(server.log.map { "\($0.connection):\($0.verb)" },
                       ["2:LOGIN", "2:SELECT", "2:UID MOVE"])
        XCTAssertEqual(server.lostWrites, [])
        XCTAssertFalse(server.uids(in: Server.inbox).contains(uid(letter.id)))
        XCTAssertEqual(pathNotes, ["LINK viable=false", "NO-PATH UID MOVE not-sent"])
        XCTAssertEqual(server.connectionsOpened, 2)
    }

    /// Airplane Mode on, Flag refused; Airplane Mode off, and the next
    /// Flag connects and goes once. The refused one is not sent at all,
    /// then or later: nothing is kept to go when the network is back
    /// (D-016).
    func testWithThePathBackTheNextFlagGoesOnce() async throws {
        let (repository, rows) = try await listed()
        let letter = rows[3]

        server.hasNoPath = true
        let failure = await refusal { try await repository.setFlagged(true, on: letter) }
        XCTAssertEqual(failure, .cannotConnect)

        server.hasNoPath = false
        try await finishing(within: 1) { try await repository.setFlagged(true, on: letter) }

        XCTAssertEqual(server.log.map { "\($0.connection):\($0.verb)" },
                       ["3:LOGIN", "3:SELECT", "3:UID STORE"])
        XCTAssertEqual(server.lostWrites, [])
        XCTAssertTrue(server.flags(uid: uid(letter.id), in: Server.inbox).contains("\\Flagged"))
        XCTAssertEqual(sentLines.filter { $0.contains("UID STORE") }.count, 1)
        XCTAssertEqual(pathNotes, ["LINK viable=false", "NO-PATH UID STORE not-sent"])
    }

    // MARK: - What is left alone

    /// A STORE already written when the path goes is left alone: its answer
    /// is read when it comes, here because it was on its way already, and
    /// the Flag lands, once. Only the letter he taps behind it is kept off
    /// the link, and it opens on a new connection where there is one. The
    /// rejected way to do better, closing the connection as the path goes,
    /// would have cut the STORE off with its answer on the way.
    func testACommandAlreadyOnTheWireIsLeftAloneAndTheNextIsKeptOffTheLink() async throws {
        let (repository, rows) = try await listed()
        let letter = rows[3]

        server.holdReplies(to: "UID STORE")
        let flagged = Task { try await repository.setFlagged(true, on: letter) }
        try await until { self.server.log.contains { $0.verb == "UID STORE" } }
        let opened = Task { try await repository.open(rows[0]) }
        try await until { await repository.waitingForExchange == 1 }
        server.losePathOfOpenLinks()
        await server.releaseReplies(to: "UID STORE")

        try await finishing(within: 1) { try await flagged.value }
        let open = try await finishing(within: 1) { try await opened.value }

        XCTAssertEqual(open.subject, rows[0].subject)
        XCTAssertEqual(server.log.map { "\($0.connection):\($0.verb)" },
                       ["1:UID STORE", "2:LOGIN", "2:SELECT", "2:UID FETCH"])
        XCTAssertEqual(server.lostWrites, [])
        XCTAssertTrue(server.flags(uid: uid(letter.id), in: Server.inbox).contains("\\Flagged"))
        XCTAssertEqual(sentLines.filter { $0.contains("UID STORE") }.count, 1)
        XCTAssertEqual(pathNotes, ["LINK viable=false", "NO-PATH UID FETCH not-sent"])
    }

    /// On a good path nothing changes: a Flag, a letter, a Delete, each its
    /// one command on the connection already open, and nothing in the log
    /// about the path. A path lost and found again on the same link with
    /// nothing written meanwhile leaves the link as it was, used as before,
    /// with no reconnect.
    func testOnAGoodPathNothingIsKeptBackAndAPathBackOnTheSameLinkIsUsedAsBefore() async throws {
        let (repository, rows) = try await listed()

        try await repository.setFlagged(true, on: rows[3])
        _ = try await repository.open(rows[0])
        XCTAssertEqual(pathNotes, [])

        server.hasNoPath = true
        server.hasNoPath = false
        try await repository.setFlagged(false, on: rows[3])
        try await repository.delete(rows[5])

        XCTAssertEqual(server.log.map { "\($0.connection):\($0.verb)" },
                       ["1:UID STORE", "1:UID FETCH", "1:UID STORE", "1:UID MOVE"])
        XCTAssertEqual(server.lostWrites, [])
        XCTAssertEqual(server.connectionsBegun, 1)
        XCTAssertEqual(pathNotes, ["LINK viable=false", "LINK viable=true"])
    }

    // MARK: - The link

    /// What the link is told is what the transport says, a line in the log
    /// for each change and none for a word that changes nothing; and a link
    /// never told anything has a path.
    func testALinkSaysWhenItLosesItsPathAndWhenItIsBack() async throws {
        let transport = server.transportFactory("imap.example.com", server.port)
        try await transport.open()
        var gone = await transport.pathIsGone
        XCTAssertFalse(gone)

        server.losePathOfOpenLinks()
        gone = await transport.pathIsGone
        XCTAssertTrue(gone)
        server.losePathOfOpenLinks()
        server.hasNoPath = false
        gone = await transport.pathIsGone
        XCTAssertFalse(gone)
        XCTAssertEqual(pathNotes, ["LINK viable=false", "LINK viable=true"])

        let untold = LinkViability()
        XCTAssertTrue(untold.isViable)
        untold.said(true)
        XCTAssertEqual(pathNotes, ["LINK viable=false", "LINK viable=true"])
        untold.said(false)
        XCTAssertFalse(untold.isViable)
        await transport.close()
    }

    /// The device's half, from `TLSConnection`'s source, which never builds
    /// here: the link tells the transport's `LinkViability` what
    /// `NWConnection`'s viability says, from a handler set before the
    /// connection starts, so nothing it says is missed; up is a path,
    /// told before the report, so the LOGIN after it is never refused for a
    /// word said while it was being made; and the handler is let go of with
    /// the connection, before the cancel.
    func testTheDeviceLinkHearsTheSystemsViabilityAndLetsGoOfItWhenClosed() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/Net/TLSConnection.swift")
        let code = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")

        XCTAssertTrue(code.contains(
            "func startLink(reporting report: @escaping @Sendable (Error?) -> Void) { "
            + "let viability = stream.viability connection.stateUpdateHandler = { state in "
            + "switch state { case .ready: viability.said(true) report(nil) "))
        XCTAssertTrue(code.contains(
            "connection.viabilityUpdateHandler = { viability.said($0) } "
            + "connection.start(queue: queue) }"))
        XCTAssertTrue(code.contains(
            "func closeLink() { connection.stateUpdateHandler = nil "
            + "connection.viabilityUpdateHandler = nil connection.cancel() }"))
        XCTAssertEqual(code.components(separatedBy: "viabilityUpdateHandler").count - 1, 2)
        XCTAssertEqual(code.components(separatedBy: "viability.said(").count - 1, 2)
    }
}
