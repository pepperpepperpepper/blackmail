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

    // MARK: - Commands the server works on (B-063)

    /// Gmail says nothing in answer to a SEARCH, a SELECT or a STATUS until
    /// it has worked through the mailbox, and his All Mail is hundreds of
    /// thousands of letters. Each is waited for three ordinary deadlines
    /// (`ReplyWait.serverWork`), the device's 90 seconds to its 30; here
    /// 180 ms to 60. Each answer is held back for 90 ms, the device's 45
    /// seconds, and comes, on the same connection.
    func testASearchSelectOrStatusSilentPastAnOrdinaryDeadlineIsWaitedFor() async throws {
        server.timeout = .milliseconds(60)
        let client = try await connectedClient()
        let quiet = Duration.milliseconds(90)
        server.delays = ["UID SEARCH": quiet, "SELECT": quiet, "STATUS": quiet]

        var started = ContinuousClock.now
        let counts = try await finishing { try await client.status(Server.allMail) }
        XCTAssertEqual(counts["MESSAGES"], UInt32(server.uids(in: Server.allMail).count))
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - started, quiet)

        started = ContinuousClock.now
        let found = try await finishing { try await client.searchAll(in: Server.allMail) }
        XCTAssertEqual(found.uids, server.uids(in: Server.allMail))
        // The SELECT of All Mail and its SEARCH, each held back.
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - started, quiet * 2)

        let connected = await client.isConnected
        XCTAssertTrue(connected)
        XCTAssertEqual(server.connectionsOpened, 1)
        XCTAssertEqual(server.log.map { "\($0.verb) \($0.status ?? "")" },
                       ["LOGIN OK", "SELECT OK", "UID SEARCH OK", "STATUS OK",
                        "SELECT OK", "UID SEARCH OK"])
    }

    /// The same silence after any other command is a dead line, cut off at
    /// the ordinary deadline as before: a letter's FETCH, and the NOOP in
    /// front of a write.
    func testAnyOtherCommandSilentAsLongIsCutOffAtTheOrdinaryDeadline() async throws {
        for verb in ["UID FETCH", "NOOP"] {
            server = ScriptedIMAPServer()
            server.timeout = .milliseconds(60)
            let client = try await connectedClient()
            let uid = try XCTUnwrap(server.uids(in: Server.inbox).first)
            let validity = inboxValidity
            server.delays = [verb: .milliseconds(90)]

            let started = ContinuousClock.now
            do {
                _ = try await finishing(within: 1) {
                    if verb == "NOOP" {
                        try await client.noop()
                    } else {
                        _ = try await client.fetchBody(uid: uid, section: nil, in: Server.inbox,
                                                       validity: validity)
                    }
                }
                XCTFail("\(verb): an answer later than the ordinary deadline was waited for")
            } catch {
                XCTAssertEqual(error as? MailError, .cannotConnect, verb)
            }
            XCTAssertGreaterThanOrEqual(ContinuousClock.now - started, .milliseconds(60), verb)
            let connected = await client.isConnected
            XCTAssertFalse(connected, verb)
        }
    }

    /// A SEARCH whose answer never comes is still given up on, at its own
    /// bound, and the transcript names it.
    func testASearchSilentPastItsOwnBoundIsCutOff() async throws {
        server.timeout = .milliseconds(60)
        let client = try await connectedClient()
        Diagnostics.clear()
        server.holdReplies(to: "UID SEARCH")

        let started = ContinuousClock.now
        do {
            _ = try await finishing(within: 2) { try await client.searchAll(in: Server.inbox) }
            XCTFail("a SEARCH that was never answered cannot have found anything")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - started, .milliseconds(180))
        let connected = await client.isConnected
        XCTAssertFalse(connected)
        let notes = Diagnostics.entries.filter { $0.direction == .note }.map(\.text)
        XCTAssertTrue(notes.contains("DEADLINE read serverWork bound=0.18s"), "\(notes)")
    }

    /// Go to Date's SEARCH, which asks for the lowest letter alone (`UID
    /// SEARCH RETURN (MIN)`), is on the same bound: silent 90 ms, the
    /// device's 45 seconds, and waited for, on the same connection.
    func testADateJumpsSearchSilentPastAnOrdinaryDeadlineIsWaitedFor() async throws {
        server.timeout = .milliseconds(60)
        let client = try await connectedClient()
        server.clearLog()
        let quiet = Duration.milliseconds(90)
        server.delays = ["UID SEARCH": quiet]
        // The newest twenty letters in the Inbox, one a day.
        let dated = "SENTSINCE \"02-Sep-2026\""

        let started = ContinuousClock.now
        let opened = try await finishing {
            try await client.page(in: Server.inbox, searching: [.lowest(dated), "ALL"]) { _ in [] }
        }
        XCTAssertEqual(opened.found[0].uids.count, 1)
        XCTAssertEqual(opened.found[1].uids, server.uids(in: Server.inbox))
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - started, quiet * 2)

        let connected = await client.isConnected
        XCTAssertTrue(connected)
        XCTAssertEqual(server.connectionsOpened, 1)
        XCTAssertEqual(server.log.map { "\($0.command) \($0.status ?? "")" },
                       ["UID SEARCH RETURN (MIN) \(dated) OK", "UID SEARCH ALL OK"])
    }

    /// So is the plain SEARCH sent again when a server will not take the
    /// CHARSET a search for a word with an accent in it goes with: refused
    /// after 90 ms, sent again, answered after as long, and both waited
    /// for, on the same connection.
    func testASearchSentAgainWithoutItsCHARSETSilentAsLongIsWaitedFor() async throws {
        server.timeout = .milliseconds(60)
        server.refusesCharset = true
        let client = try await connectedClient()
        server.clearLog()
        let quiet = Duration.milliseconds(90)
        server.delays = ["UID SEARCH": quiet]
        let words = "FROM \"Müller\""

        let started = ContinuousClock.now
        _ = try await finishing { try await client.search(words, in: Server.inbox) }
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - started, quiet * 2)

        let connected = await client.isConnected
        XCTAssertTrue(connected)
        XCTAssertEqual(server.connectionsOpened, 1)
        XCTAssertEqual(server.log.map { "\($0.command) \($0.status ?? "")" },
                       ["UID SEARCH CHARSET UTF-8 \(words) BAD", "UID SEARCH \(words) OK"])
    }

    /// The longer bound is on every silence in the answer, not only the
    /// one before it starts. Gmail may say a line at once, an EXISTS or
    /// EXPUNGE it owes the session, or SELECT's FLAGS, and then work on
    /// through the mailbox before it says the rest. Here the answer's
    /// untagged lines come at once and its tagged line is held 90 ms, the
    /// device's 45 seconds, once the client has read the start and is
    /// waiting for the rest: a SEARCH, a SELECT, a STATUS and Go to Date's
    /// `UID SEARCH RETURN (MIN)` each come through it, on the same
    /// connection.
    func testASearchSelectOrStatusWhoseRestComesAfterAPausePastAnOrdinaryDeadlineIsWaitedFor()
        async throws {
        for (verb, jump) in [("UID SEARCH", false), ("SELECT", false), ("STATUS", false),
                             ("UID SEARCH", true)] {
            let label = jump ? "RETURN (MIN)" : verb
            server = ScriptedIMAPServer()
            server.timeout = .milliseconds(60)
            let client = try await connectedClient()
            let server = self.server!
            let completion = Server.completion(of: verb)
            server.completesApart = [verb]
            server.holdReplies(to: completion)
            server.clearLog()

            let call = Task {
                switch (verb, jump) {
                case ("STATUS", _):
                    let counts = try await client.status(Server.allMail)
                    XCTAssertEqual(counts["MESSAGES"], UInt32(server.uids(in: Server.allMail).count))
                case ("SELECT", _):
                    let found = try await client.searchAll(in: Server.allMail)
                    XCTAssertEqual(found.uids, server.uids(in: Server.allMail))
                case (_, true):
                    let opened = try await client.page(in: Server.inbox,
                                                       searching: [.lowest("SENTSINCE \"02-Sep-2026\"")]) { _ in [] }
                    XCTAssertEqual(opened.found[0].uids.count, 1)
                default:
                    let found = try await client.search("FROM \"carlo@example.org\"", in: Server.inbox)
                    XCTAssertFalse(found.uids.isEmpty)
                }
            }
            try await waitUntil { await self.waitingOnTheLink(held: completion) }
            let paused = ContinuousClock.now
            try await Task.sleep(for: .milliseconds(90))
            await server.releaseReplies(to: completion)
            do {
                try await finishing { try await call.value }
            } catch {
                XCTFail("\(label): the rest of the answer, after a pause, was not waited for: \(error)")
            }
            XCTAssertGreaterThanOrEqual(ContinuousClock.now - paused, .milliseconds(90), label)

            let connected = await client.isConnected
            XCTAssertTrue(connected, label)
            XCTAssertEqual(server.connectionsOpened, 1, label)
            XCTAssertTrue(server.log.contains { $0.verb == verb && $0.status == "OK" }, label)
        }
    }

    /// The same pause in the answer to any other command is a dead line,
    /// cut off at the ordinary deadline as before: a letter's FETCH whose
    /// untagged line, the letter and all, comes at once, and whose tagged
    /// line does not.
    func testAnyOtherCommandWhoseRestPausesAsLongIsCutOffAtTheOrdinaryDeadline() async throws {
        server.timeout = .milliseconds(60)
        let client = try await connectedClient()
        let uid = try XCTUnwrap(server.uids(in: Server.inbox).first)
        let validity = inboxValidity
        let verb = "UID FETCH"
        let completion = Server.completion(of: verb)
        server.completesApart = [verb]
        server.holdReplies(to: completion)

        let call = Task {
            try await client.fetchBody(uid: uid, section: nil, in: Server.inbox, validity: validity)
        }
        try await waitUntil { await self.waitingOnTheLink(held: completion) }
        let paused = ContinuousClock.now
        try await Task.sleep(for: .milliseconds(90))
        await server.releaseReplies(to: completion)
        do {
            _ = try await finishing(within: 1) { try await call.value }
            XCTFail("a FETCH whose answer paused past the ordinary deadline was waited for")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - paused, .milliseconds(60))
        let connected = await client.isConnected
        XCTAssertFalse(connected)
    }

    // MARK: - Slow answers in the log (B-063)

    /// A client on a clock the test moves, connected, with the Inbox
    /// selected and the log cleared.
    private func clockedClient(_ clock: ManualClock) async throws -> IMAPClient {
        let client = IMAPClient(account: server.account, transport: server.transportFactory,
                                now: { clock.now() })
        try await client.connect(password: server.password)
        _ = try await client.searchAll(in: Server.inbox)
        Diagnostics.clear()
        return client
    }

    /// Runs `body` with the replies to `verb` held while `meanwhile` runs,
    /// then lets them go and waits for it. `meanwhile` runs once the client
    /// is waiting on the link for the answer, so a clock it moves times
    /// that wait.
    private func held(_ verb: String, _ body: @escaping @Sendable () async throws -> Void,
                      meanwhile: () -> Void) async throws {
        server.holdReplies(to: verb)
        let call = Task { try await body() }
        try await waitUntil { await self.waitingOnTheLink(held: verb) }
        meanwhile()
        await server.releaseReplies(to: verb)
        try await finishing { try await call.value }
    }

    /// Whether a reply to `verb` is being held and the client is waiting
    /// on the link for it.
    private func waitingOnTheLink(held verb: String) async -> Bool {
        guard await server.heldReplies(to: verb) > 0 else { return false }
        return await server.readsWaiting() > 0
    }

    /// A second at most for `condition`, a millisecond at a time.
    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("waited a second, and it never came")
    }

    private var notes: [String] {
        Diagnostics.entries.filter { $0.direction == .note }.map(\.text)
    }

    /// An answer that took longer than five seconds says so in the
    /// connection log, with the command's verb and two times and nothing
    /// else: not the words searched for, not the mailbox's name. One that
    /// took less says nothing. Timed on the client's clock, here one the
    /// test moves while the answer is held, all of it in one silence, so
    /// the two times are the same. Each command's silences are its own:
    /// the SEARCH after the SELECT's 41 seconds says its own 6.5.
    func testASlowAnswerIsNotedWithItsVerbAndNothingElse() async throws {
        let clock = ManualClock()
        let client = try await clockedClient(clock)

        try await held("SELECT", {
            _ = try await client.searchAll(in: Server.allMail)
        }, meanwhile: { clock.advance(by: 41.25) })
        try await held("UID SEARCH", {
            _ = try await client.search("FROM \"carlo@example.org\"", in: Server.inbox)
        }, meanwhile: { clock.advance(by: 6.5) })
        try await held("STATUS", {
            _ = try await client.status(Server.sent)
        }, meanwhile: { clock.advance(by: 4.9) })

        XCTAssertEqual(notes, ["SLOW SELECT ms=41250 quiet=41250",
                               "SLOW UID SEARCH ms=6500 quiet=6500"])
    }

    /// The bound is on each silence in an answer, one read's wait for the
    /// next bytes, so the note says the longest of them, `quiet`, beside
    /// the whole, `ms`. An answer whose start came 2 seconds after the
    /// command and whose tagged line came 13 seconds after that is
    /// `ms=15000 quiet=13000`. One whose start came at once and whose end
    /// took 15 seconds is `quiet=15000`, its first byte having taken none;
    /// one whose start took 13 seconds and whose end 2, `quiet=13000`; and
    /// two silences of 7.5 seconds, `quiet=7500`: the longest, not the
    /// first, not the last, not the sum.
    func testASlowNoteSaysTheLongestSilenceInTheAnswer() async throws {
        let clock = ManualClock()
        let client = try await clockedClient(clock)
        let verb = "UID SEARCH"
        let completion = Server.completion(of: verb)
        server.completesApart = [verb]

        for (before, after, quiet) in [(2.0, 13.0, 13_000), (0.0, 15.0, 15_000),
                                       (13.0, 2.0, 13_000), (7.5, 7.5, 7_500)] {
            Diagnostics.clear()
            server.holdReplies(to: verb)
            server.holdReplies(to: completion)
            let call = Task { _ = try await client.search("FROM \"carlo@example.org\"", in: Server.inbox) }
            try await waitUntil { await self.waitingOnTheLink(held: verb) }
            clock.advance(by: before)
            await server.releaseReplies(to: verb)
            // The answer's start read, the client waiting for the rest, and
            // the tagged line still held.
            try await waitUntil {
                guard Diagnostics.entries.contains(where: {
                    $0.direction == .received && $0.text.hasPrefix("* SEARCH")
                }) else { return false }
                return await self.waitingOnTheLink(held: completion)
            }
            clock.advance(by: after)
            await server.releaseReplies(to: completion)
            try await finishing { try await call.value }

            XCTAssertEqual(notes, ["SLOW UID SEARCH ms=15000 quiet=\(quiet)"], "\(before), \(after)")
        }
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// Every command's answer is timed the same way, not only the three on
    /// the long bound: a letter's FETCH whose letter came 3 seconds after it
    /// was asked for and whose tagged line came 6 seconds after that is
    /// `ms=9000 quiet=6000`.
    func testASlowNoteTimesTheSilencesOfAnOrdinaryCommandToo() async throws {
        let clock = ManualClock()
        let client = try await clockedClient(clock)
        let uid = try XCTUnwrap(server.uids(in: Server.inbox).first)
        let validity = inboxValidity
        let verb = "UID FETCH"
        let completion = Server.completion(of: verb)
        server.completesApart = [verb]
        server.holdReplies(to: verb)
        server.holdReplies(to: completion)

        let call = Task {
            try await client.fetchBody(uid: uid, section: nil, in: Server.inbox, validity: validity)
        }
        try await waitUntil { await self.waitingOnTheLink(held: verb) }
        clock.advance(by: 3)
        await server.releaseReplies(to: verb)
        try await waitUntil {
            guard Diagnostics.entries.contains(where: {
                $0.direction == .received && $0.text.contains(" FETCH (")
            }) else { return false }
            return await self.waitingOnTheLink(held: completion)
        }
        clock.advance(by: 6)
        await server.releaseReplies(to: completion)
        _ = try await finishing { try await call.value }

        XCTAssertEqual(notes, ["SLOW UID FETCH ms=9000 quiet=6000"])
    }

    /// An answer read only once the app is back from the background is not
    /// noted at all: iOS may have held the app still for hours with it
    /// waiting, and that time is not Gmail's. Nor is one the app went away
    /// during. A command after that is noted as ever.
    func testNoSlowNoteForACommandTheAppWentAwayOrCameBackDuring() async throws {
        let clock = ManualClock()
        let client = try await clockedClient(clock)

        try await held("UID SEARCH", {
            _ = try await client.search("FROM \"carlo@example.org\"", in: Server.inbox)
        }, meanwhile: {
            Diagnostics.wentAwayOrCameBack()      // away
            clock.advance(by: 3 * 3_600)
            Diagnostics.wentAwayOrCameBack()      // and back
        })
        try await held("STATUS", {
            _ = try await client.status(Server.sent)
        }, meanwhile: {
            clock.advance(by: 20)
            Diagnostics.wentAwayOrCameBack()      // away, the answer read in time
        })
        Diagnostics.wentAwayOrCameBack()          // back
        XCTAssertEqual(notes, [])

        try await held("UID SEARCH", {
            _ = try await client.search("FROM \"carlo@example.org\"", in: Server.inbox)
        }, meanwhile: { clock.advance(by: 6.5) })
        XCTAssertEqual(notes, ["SLOW UID SEARCH ms=6500 quiet=6500"])
    }

    /// The app says when it goes away and when it comes back, each first
    /// thing it does but for the launch's finish: in `AppDelegate`, which
    /// is UIKit and never builds on this host, so read from its source, as
    /// `SafeStartTests` reads it.
    func testTheAppSaysWhenItGoesAwayAndWhenItComesBack() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/App/AppDelegate.swift")
        let code = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
        XCTAssertTrue(code.contains("public func applicationDidEnterBackground(_ application: "
                                    + "UIApplication) { SafeStart.app.finished() "
                                    + "Diagnostics.wentAwayOrCameBack() "))
        XCTAssertTrue(code.contains("public func applicationWillEnterForeground(_ application: "
                                    + "UIApplication) { Diagnostics.wentAwayOrCameBack() "))
        XCTAssertEqual(code.components(separatedBy: "Diagnostics.wentAwayOrCameBack()").count - 1, 2)
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
