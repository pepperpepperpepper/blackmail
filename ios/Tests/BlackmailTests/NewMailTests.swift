import XCTest
@testable import Blackmail

/// New mail without a tap while the app is in front (B-049): `MailWatch`
/// over the shipping repository and client and `ScriptedIMAPServer`, whose
/// `arrive` and `removeElsewhere` tell a connection of mail only as Gmail
/// did (B-045), with a clock the test moves, so the half minute between
/// checks costs nothing and the commands counted are the ones the app sends.
/// The list is `ListLetters`, shown or held by `ListPlaces.showsNews` as the
/// message list does it.
final class NewMailTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "NewMailTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var clock: ManualClock!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        clock = ManualClock()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
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

    private func uid(_ id: String) -> UInt32 { UInt32(id.split(separator: "/").last ?? "")! }

    private var verbs: [String] { server.log.map(\.verb) }

    /// The `index`th command logged, or "none", so a test with fewer
    /// commands than it expects fails rather than stopping the run.
    private func command(_ index: Int) -> String {
        index < server.log.count ? server.log[index].command : "none"
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

    /// Letters he sends himself from another device, `count` of them, an
    /// hour apart after the newest in the Inbox. Their UIDs in the Inbox,
    /// oldest first.
    @discardableResult
    private func lettersToHimself(_ count: Int, about word: String = "note") -> [UInt32] {
        (1...count).compactMap { n in
            server.arrive(Server.Letter(from: Server.owner, to: [Server.owner],
                                        subject: "A \(word) to self \(n)",
                                        date: Server.newestDate.addingTimeInterval(Double(n) * 3_600),
                                        text: "Shared from Safari on the phone.\r\n",
                                        messageID: "<self-\(word)-\(n)@example.com>"),
                          in: [Server.inbox, Server.allMail])[Server.inbox]
        }
    }

    /// The Inbox's unread letters on the server now.
    private var inboxUnread: Int {
        server.uids(in: Server.inbox).filter {
            !server.flags(uid: $0, in: Server.inbox).contains("\\Seen")
        }.count
    }

    /// The screens, as the watch sees them: the Inbox's list in
    /// `ListLetters`, taken, put on or held by the calls
    /// `MessageListViewController` makes, where he is set by hand; the
    /// folder pane's Inbox count; and what the watch has asked of them.
    @MainActor
    private final class Screen: MailWatchTarget {
        let letters = ListLetters()
        var mailboxID = "inbox"
        var inboxInFront = true
        var atTop = true
        var searching = false
        var ticked = false
        var touching = false
        /// False once he has jumped to a day, whose top is not the Inbox's
        /// newest letter (`reachedNewestMessage`).
        var fromNewest = true
        /// Whether the first page came.
        var fetched = true
        var paneCount: Int?
        private(set) var sweeps = 0
        private(set) var outcomes: [MailWatch.Outcome] = []
        /// Quiet fetches afresh started, as the list starts them.
        private(set) var refetches = 0
        /// The line under the list.
        private(set) var line = UpdatedLine()

        var watchedInbox: (mailboxID: String, letters: [String])? {
            guard inboxInFront,
                  let watched = letters.toWatch(fromNewest: fromNewest, fetched: fetched) else {
                return nil
            }
            return (mailboxID, watched)
        }

        var shownInboxUnread: Int? { paneCount }

        func found(_ news: FolderNews, in mailboxID: String) -> NewsTaken {
            guard inboxInFront, mailboxID == self.mailboxID else { return .notTaken }
            let taken = letters.take(news, fromNewest: fromNewest)
            showIfAtTop()
            return taken
        }

        /// What the list does at each check, and whenever he may be back at
        /// the top. Returns the letters put on.
        @discardableResult
        func showIfAtTop() -> [MessageSummary] {
            switch letters.putNewsOn(atTop: atTop, searching: searching, ticked: ticked,
                                     touching: touching) {
            case .wait:
                return []
            case .refetch:
                refetches += 1
                return []
            case .shown(let added):
                return added
            }
        }

        func countsChanged() { sweeps += 1 }

        func checked(_ outcome: MailWatch.Outcome) {
            outcomes.append(outcome)
            line.checked(outcome, listing: mailboxID)
        }

        var subjects: [String] { letters.shown.map(\.subject) }
    }

    /// The Inbox's first page on screen, as launch leaves it.
    @MainActor
    private func inboxOnScreen(_ repository: IMAPMailRepository) async throws -> Screen {
        let screen = Screen()
        let page = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        screen.letters.fetchedAfresh(page)
        return screen
    }

    @MainActor
    private func watch(_ repository: IMAPMailRepository, over screen: Screen) -> MailWatch {
        let clock = self.clock!
        let watch = MailWatch(repository: repository, now: { clock.now() },
                              sleep: { try await clock.sleep(for: $0) })
        watch.target = screen
        return watch
    }

    // MARK: - A letter arrives

    /// The gap this closes: a letter reaches the Inbox while he has it open,
    /// and it is on the list within the half minute, with no tap. Nothing is
    /// asked before the half minute is up. The check is a NOOP, which Gmail
    /// answers with the new EXISTS; a SEARCH from the lowest letter the list
    /// holds, which finds the one new UID; and a FETCH of that one letter's
    /// summary, nothing else. Its preview is the usual 2 KB. The folder
    /// counts are swept once. The current code sends nothing at all: the
    /// letter stays off the list until Refresh.
    @MainActor
    func testALetterThatArrivesWhileTheAppIsOpenIsListedWithinTheIntervalWithoutATap() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let before = screen.letters.shown.map(\.id)
        let lowest = screen.letters.folder.map { uid($0.id) }.min()!
        let watch = watch(repository, over: screen)
        watch.start()
        try await until { self.clock.sleeping == 1 }
        let arrived = lettersToHimself(1)
        server.clearLog()

        clock.advance(by: MailWatch.interval - 1)
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(watch.checks, 0)
        XCTAssertEqual(screen.letters.shown.map(\.id), before)

        clock.advance(by: 1)
        try await until { watch.checks == 1 }
        XCTAssertEqual(screen.letters.shown.first.map { uid($0.id) }, arrived.first)
        XCTAssertEqual(screen.subjects.first, "A note to self 1")
        XCTAssertEqual(Array(screen.letters.shown.dropFirst().map(\.id)), before, "nothing else moved")
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(command(1), "UID SEARCH UID \(lowest):*")
        XCTAssertTrue(command(2).hasPrefix("UID FETCH \(arrived[0]) ("), command(2))
        XCTAssertEqual(server.log.map(\.selected), Array(repeating: Server.inbox, count: 3))
        XCTAssertEqual(screen.sweeps, 1)
        XCTAssertEqual(screen.outcomes, [.listed(mailboxID: "inbox", at: clock.now())])

        server.clearLog()
        let previews = try await repository.previews(for: [screen.letters.shown[0].id], in: "inbox")
        XCTAssertEqual(previews.values.first, "Shared from Safari on the phone.")
        XCTAssertEqual(server.log.count, 1)
        XCTAssertTrue(command(0).hasSuffix("<0.2048>)"), command(0))
        await watch.stop()?.value
    }

    /// Two letters, one check apart, with him scrolled down the list: each
    /// check fetches only its own new letter, the one held already counting
    /// as known. Nothing on the list changes until he is back at the top,
    /// and then both go on, newest first, and a letter taken out elsewhere
    /// meanwhile comes off. The counts follow at each check all the same.
    @MainActor
    func testWhileHeIsScrolledDownEachLetterIsFetchedOnceAndHeld() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let before = screen.letters.shown
        let watch = watch(repository, over: screen)
        screen.atTop = false

        let first = lettersToHimself(1)
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(screen.letters.shown, before)
        XCTAssertEqual(screen.sweeps, 1)

        let second = lettersToHimself(1, about: "link")
        server.removeElsewhere(uid: uid(before[1].id), from: Server.inbox)
        server.clearLog()
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])
        XCTAssertTrue(command(2).hasPrefix("UID FETCH \(second[0]) ("), command(2))
        XCTAssertEqual(screen.letters.shown, before, "nothing moved under him")
        XCTAssertEqual(screen.sweeps, 2)

        screen.atTop = true
        let added = screen.showIfAtTop()
        XCTAssertEqual(added.map { uid($0.id) }, [second[0], first[0]])
        XCTAssertEqual(screen.letters.shown.map(\.id),
                       added.map(\.id) + before.filter { $0.id != before[1].id }.map(\.id))
        // Paging goes on from the last letter the last page gave.
        XCTAssertEqual(screen.letters.cursor, before.last?.id)
    }

    /// A letter archived or binned from the phone leaves the list the same
    /// way: the NOOP brings the EXPUNGE, the SEARCH says which letter, and
    /// nothing is fetched.
    @MainActor
    func testALetterRemovedElsewhereLeavesTheList() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let before = screen.letters.shown
        let watch = watch(repository, over: screen)
        server.removeElsewhere(uid: uid(before[0].id), from: Server.inbox)
        server.clearLog()

        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH"])
        XCTAssertEqual(screen.letters.shown.map(\.id), before.dropFirst().map(\.id))
        XCTAssertEqual(screen.sweeps, 1)
    }

    // MARK: - What a check costs

    /// Nothing arriving, which is nearly every check: one NOOP each, in the
    /// Inbox, and nothing on the list or the counts. The NOOP is the
    /// connection proven as well, so a Flag in the next ninety seconds goes
    /// without B-024's probe; and it is the Inbox's news asked for, so a
    /// Refresh a moment after it sends no NOOP of its own (B-045).
    @MainActor
    func testWhenNothingArrivesACheckIsOneNOOP() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let before = screen.letters.shown
        let watch = watch(repository, over: screen)
        server.clearLog()

        for _ in 1...3 {
            clock.advance(by: MailWatch.interval)
            await watch.check()
        }
        XCTAssertEqual(verbs, ["NOOP", "NOOP", "NOOP"])
        XCTAssertEqual(server.log.map(\.selected), Array(repeating: Server.inbox, count: 3))
        XCTAssertEqual(screen.letters.shown, before)
        XCTAssertEqual(screen.sweeps, 0)
        XCTAssertEqual(screen.outcomes.count, 3)

        // Two minutes since he last did anything, eighty seconds since the
        // last check.
        clock.advance(by: 80)
        server.clearLog()
        try await repository.setFlagged(true, on: before[3])
        XCTAssertEqual(verbs, ["UID STORE"])

        clock.advance(by: MailWatch.interval)
        await watch.check()
        clock.advance(by: 1)
        server.clearLog()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(verbs, ["UID SEARCH", "UID FETCH"])
    }

    /// With another folder in front, a check is one STATUS of the Inbox,
    /// which leaves the folder he is in selected, and the counts are swept
    /// only when the Inbox's count is not what the folder pane shows. No
    /// letter of the Inbox's is searched for or fetched.
    ///
    /// Answered, the STATUS proves the connection too: a Flag in Sent eighty
    /// seconds after the last check sends no probe.
    @MainActor
    func testWithAnotherFolderInFrontACheckIsOneSTATUSAndTheInboxCountFollows() async throws {
        let repository = makeRepository()
        let sent = try await repository.listMessages(in: "sent", beforeUID: nil, limit: 50)
        let screen = Screen()
        screen.inboxInFront = false
        screen.paneCount = inboxUnread
        let watch = watch(repository, over: screen)
        server.clearLog()

        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(server.log.map(\.command), ["STATUS \"INBOX\" (UNSEEN)"])
        XCTAssertEqual(screen.sweeps, 0)

        lettersToHimself(1)
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(server.log.map(\.command), Array(repeating: "STATUS \"INBOX\" (UNSEEN)", count: 2))
        XCTAssertEqual(server.log.map(\.selected), [Server.sent, Server.sent])
        XCTAssertEqual(screen.sweeps, 1)
        XCTAssertEqual(screen.outcomes.count, 2)
        XCTAssertTrue(screen.outcomes.allSatisfy { if case .reached = $0 { return true }; return false })

        clock.advance(by: 80)
        server.clearLog()
        try await repository.setFlagged(true, on: sent[0])
        XCTAssertEqual(verbs, ["UID STORE"])
    }

    /// Another folder's work has left All Mail open on the connection, an
    /// All Mailboxes search here: the check SELECTs the Inbox in place of the
    /// NOOP, and searches, since a SELECT is a view of the mailbox nobody
    /// has searched. The check after is a NOOP again.
    @MainActor
    func testACheckAfterAnotherMailboxWasOpenedSELECTsTheInbox() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        _ = try await repository.search(in: "inbox", query: "garden", scope: .allMailboxes,
                                        beforeUID: nil, limit: 50)
        let watch = watch(repository, over: screen)
        let arrived = lettersToHimself(1)
        server.clearLog()

        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(verbs, ["SELECT", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(server.log.map(\.selected), [Server.allMail, Server.inbox, Server.inbox])
        XCTAssertEqual(screen.letters.shown.first.map { uid($0.id) }, arrived.first)

        server.clearLog()
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(verbs, ["NOOP"])
    }

    // MARK: - His taps first

    /// A letter he opens while the check's NOOP is on the wire waits for
    /// that one answer, and goes before the SEARCH and the FETCH the check
    /// then needs, each of which is a hold of the connection of its own.
    /// And one he opens while the check is still waiting for the connection,
    /// here behind the folder counts' STATUS, goes first, ahead of the check.
    @MainActor
    func testATapDuringACheckGoesFirst() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let letter = screen.letters.shown[3]
        let watch = watch(repository, over: screen)
        lettersToHimself(1)
        server.clearLog()

        server.holdReplies(to: "NOOP")
        clock.advance(by: MailWatch.interval)
        let checking = Task { await watch.check() }
        try await until { self.server.log.contains { $0.verb == "NOOP" } }
        let tap = Task { try await repository.open(letter) }
        try await until { await repository.waitingForExchange == 1 }
        await server.releaseReplies(to: "NOOP")
        let opened = try await finishing { try await tap.value }
        await checking.value
        XCTAssertEqual(opened.subject, letter.subject)
        XCTAssertEqual(verbs, ["NOOP", "UID FETCH", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(command(1), "UID FETCH \(uid(letter.id)) (UID BODY.PEEK[])")
        XCTAssertEqual(screen.subjects.first, "A note to self 1")

        server.clearLog()
        server.holdReplies(to: "STATUS")
        let sweep = Task { try await repository.listMailboxes() }
        try await until { self.server.log.contains { $0.verb == "STATUS" } }
        clock.advance(by: MailWatch.interval)
        let checkingAgain = Task { await watch.check() }
        try await until { await repository.waitingForExchange == 1 }
        let tapAgain = Task { try await repository.open(letter) }
        try await until { await repository.waitingForExchange == 2 }
        await server.releaseReplies(to: "STATUS")
        _ = try await finishing { try await tapAgain.value }
        await checkingAgain.value
        _ = try await finishing { try await sweep.value }
        XCTAssertEqual(Array(verbs.prefix(4)), ["LIST", "STATUS", "UID FETCH", "NOOP"])
    }

    /// He picks the iPad up, quiet long enough for a write to probe, and
    /// bins a letter while the check's NOOP is out, and the socket turns out
    /// to be dead. The check does not count the connection proven until its
    /// NOOP is answered, so the Delete probes for itself and its MOVE goes
    /// once, on the new connection (B-024). Stamped as the NOOP went, as
    /// `connected()` stamps a call, the Delete would have skipped its probe.
    ///
    /// The probe's retry is a race with the check's reconnect, and passes
    /// without the retry rule it rests on in most runs; the rule itself is
    /// `testAReadGoesAgainOnlyWhenItsConnectionWasTornDown`.
    @MainActor
    func testADeleteMadeWhileACheckIsOutGoesOnceOnTheNewConnection() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let letter = screen.letters.shown[0]
        let watch = watch(repository, over: screen)
        clock.advance(by: 91)
        server.clearLog()

        server.holdReplies(to: "NOOP")
        let checking = Task { await watch.check() }
        try await until { self.server.log.contains { $0.verb == "NOOP" } }
        let deleted = Task { try await repository.delete(letter) }
        try await until { await repository.waitingForExchange == 1 }
        await server.resetConnections()
        await server.releaseReplies(to: "NOOP")

        try await finishing { try await deleted.value }
        await checking.value
        let moves = server.log.filter { $0.verb == "UID MOVE" }
        XCTAssertEqual(moves.map(\.connection), [2])
        let delete = server.log.filter { $0.connection == 2 }.map(\.verb)
        let move = try XCTUnwrap(delete.firstIndex(of: "UID MOVE"))
        XCTAssertTrue(delete[..<move].contains("NOOP"), "\(delete)")
        XCTAssertEqual(server.connectionsOpened, 2)
        XCTAssertFalse(server.uids(in: Server.inbox).contains(uid(letter.id)))
    }

    /// The same while the watch runs, which is every moment the app is in
    /// front: the check half a minute ago proved the connection, so the
    /// Delete sends no probe, and waits behind the check's NOOP. The NOOP
    /// finds the socket dead and tears the connection down; the Delete's
    /// turn comes with no connection, and not a byte of it has gone, so it
    /// goes once, on the new one. It used to fail there, with nothing sent,
    /// and a write is never sent twice: the letter stayed in the Inbox. On
    /// a half-open socket that was every write in the thirty seconds the
    /// NOOP waited.
    @MainActor
    func testADeleteMadeWhileACheckFindsTheSocketDeadGoesOnceOnTheNewConnection() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let letter = screen.letters.shown[0]
        let watch = watch(repository, over: screen)
        clock.advance(by: MailWatch.interval)
        await watch.check()
        clock.advance(by: MailWatch.interval)
        server.clearLog()

        server.holdReplies(to: "NOOP")
        let checking = Task { await watch.check() }
        try await until { self.server.log.contains { $0.verb == "NOOP" } }
        let deleted = Task { try await repository.delete(letter) }
        try await until { await repository.waitingForExchange == 1 }
        await server.resetConnections()
        await server.releaseReplies(to: "NOOP")

        try await finishing { try await deleted.value }
        await checking.value
        XCTAssertEqual(server.log.filter { $0.verb == "UID MOVE" }.map(\.connection), [2],
                       "\(server.log)")
        XCTAssertEqual(server.lostWrites, [])
        XCTAssertEqual(server.connectionsOpened, 2)
        XCTAssertFalse(server.uids(in: Server.inbox).contains(uid(letter.id)))
        XCTAssertEqual(screen.outcomes.last, .listed(mailboxID: "inbox", at: clock.now()))
    }

    /// What `sendingOnce` must not turn into: a write that went out on a
    /// socket that had died is not sent again, since the server may have
    /// carried it out before the socket went. It fails, as it always has.
    @MainActor
    func testAWriteThatWentOutOnADeadSocketIsStillNotSentAgain() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let letter = screen.letters.shown[3]
        let watch = watch(repository, over: screen)
        clock.advance(by: MailWatch.interval)
        await watch.check()
        await server.resetConnections()
        clock.advance(by: 10)
        server.clearLog()

        do {
            try await repository.setFlagged(true, on: letter)
            XCTFail("a Flag written into a dead socket cannot have been answered")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        XCTAssertEqual(server.lostWrites.map(\.verb), ["UID STORE"])
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// The rule a read's retry goes by (`IMAPMailRepository.retries`), in
    /// each state a failed read can find the connection in. The one the
    /// calls reach only in the order two tasks happen to run in is the
    /// first: the read's connection torn down, and another call's reconnect
    /// already up when it looks. It used to ask whether the connection was
    /// down, took that for a refusal on a live connection, and did not go
    /// again; a probe in front of a write failed with it.
    func testAReadGoesAgainOnlyWhenItsConnectionWasTornDown() {
        typealias Attempt = IMAPMailRepository.Attempt
        let up = Attempt(connected: true, lost: 3, failedConnects: 1)
        let dropped = MailError.cannotConnect
        func retries(_ error: MailError = dropped, began: Attempt = up, after: Attempt) -> Bool {
            IMAPMailRepository.retries(error, began: began, after: after)
        }
        XCTAssertTrue(retries(after: Attempt(connected: true, lost: 4, failedConnects: 1)),
                      "torn down, and connected again by another call before it looked")
        XCTAssertTrue(retries(after: Attempt(connected: false, lost: 4, failedConnects: 1)),
                      "torn down, and still down")
        XCTAssertFalse(retries(after: up), "refused on a connection that stayed up")
        XCTAssertFalse(retries(after: Attempt(connected: false, lost: 4, failedConnects: 2)),
                       "an attempt to connect failed while it waited")
        XCTAssertFalse(retries(began: Attempt(connected: false, lost: 3, failedConnects: 1),
                               after: Attempt(connected: false, lost: 3, failedConnects: 2)),
                       "it had to connect, and the connect failed")
        XCTAssertFalse(retries(.passwordNeedsUpdating,
                               after: Attempt(connected: false, lost: 4, failedConnects: 1)),
                       "a refused password")
    }

    // MARK: - Away, and a refused password

    /// Checks while the app is in front; none while it is away, however long,
    /// and the letter that came meanwhile is listed half a minute after it is
    /// back.
    @MainActor
    func testNothingIsCheckedWhileTheAppIsAway() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let watch = watch(repository, over: screen)
        watch.start()
        try await until { self.clock.sleeping == 1 }
        server.clearLog()
        clock.advance(by: MailWatch.interval)
        try await until { watch.checks == 1 }
        XCTAssertEqual(verbs, ["NOOP"])

        try await until { self.clock.sleeping == 1 }
        await watch.stop()?.value
        XCTAssertFalse(watch.isWatching)
        XCTAssertEqual(clock.sleeping, 0)
        let arrived = lettersToHimself(1)
        server.clearLog()
        for _ in 1...10 { clock.advance(by: MailWatch.interval) }
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(watch.checks, 1)
        XCTAssertNotEqual(screen.letters.shown.first.map { uid($0.id) }, arrived.first)

        watch.start()
        try await until { self.clock.sleeping == 1 }
        clock.advance(by: MailWatch.interval)
        try await until { watch.checks == 2 }
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(screen.letters.shown.first.map { uid($0.id) }, arrived.first)
        await watch.stop()?.value
    }

    /// The app goes into the background with a check's NOOP on the wire and
    /// a letter to find. The NOOP is answered, as any command on the wire
    /// is, and nothing after it is sent: no SEARCH, no FETCH, and nothing
    /// said on the line.
    @MainActor
    func testACheckOutAsTheAppGoesAwaySendsNothingAfterItsCommand() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let before = screen.letters.shown
        let watch = watch(repository, over: screen)
        lettersToHimself(1)
        server.clearLog()
        server.holdReplies(to: "NOOP")
        watch.start()
        try await until { self.clock.sleeping == 1 }
        clock.advance(by: MailWatch.interval)
        try await until { self.server.log.contains { $0.verb == "NOOP" } }

        let stopped = watch.stop()
        await server.releaseReplies(to: "NOOP")
        await stopped?.value
        XCTAssertEqual(verbs, ["NOOP"])
        XCTAssertEqual(server.log.map(\.status), ["OK"])
        XCTAssertEqual(watch.checks, 0)
        XCTAssertEqual(screen.outcomes, [])
        XCTAssertEqual(screen.letters.shown, before)
    }

    /// The app goes away with the check's SEARCH or its FETCH on the wire,
    /// the letter found. It is not put on while he is away, and the first
    /// check after he is back searches for it again and lists it, though
    /// its NOOP says nothing has changed: the server told the session of it
    /// once, on the NOOP before. It used to stay off the list, check after
    /// check, under "Updated Just Now", until another letter came.
    @MainActor
    func testALetterFoundAsTheAppGoesAwayIsListedByTheFirstCheckAfterItComesBack() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let watch = watch(repository, over: screen)
        for held in ["UID SEARCH", "UID FETCH"] {
            let arrived = lettersToHimself(1, about: held == "UID SEARCH" ? "search" : "fetch")
            server.clearLog()
            server.holdReplies(to: held)
            watch.start()
            try await until { self.clock.sleeping == 1 }
            clock.advance(by: MailWatch.interval)
            try await until { self.server.log.contains { $0.verb == held } }
            let stopped = watch.stop()
            await server.releaseReplies(to: held)
            await stopped?.value
            XCTAssertNotEqual(screen.letters.shown.first.map { uid($0.id) }, arrived.first, held)
            XCTAssertTrue(watch.searchOwed, held)

            server.clearLog()
            clock.advance(by: MailWatch.interval)
            await watch.check()
            XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"], held)
            XCTAssertEqual(screen.letters.shown.first.map { uid($0.id) }, arrived.first, held)
            XCTAssertFalse(watch.searchOwed, held)

            server.clearLog()
            clock.advance(by: MailWatch.interval)
            await watch.check()
            XCTAssertEqual(verbs, ["NOOP"], held)
        }
    }

    /// With nothing new, or with a renumbered Inbox found on the reconnect,
    /// a check answered after the app has gone says nothing on the line and
    /// hands the list nothing: a fetch afresh started then would be sent
    /// while he is away.
    @MainActor
    func testACheckAnsweredAfterTheAppHasGoneHandsTheListNothing() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let watch = watch(repository, over: screen)

        for renumbering in [false, true] {
            server.clearLog()
            let held = renumbering ? "SELECT" : "NOOP"
            if renumbering {
                server.renumber(Server.inbox, validity: 700_001, firstUID: 1_000)
                await server.resetConnections()
            }
            server.holdReplies(to: held)
            watch.start()
            try await until { self.clock.sleeping == 1 }
            clock.advance(by: MailWatch.interval)
            try await until { self.server.log.contains { $0.verb == held } }
            let stopped = watch.stop()
            await server.releaseReplies(to: held)
            await stopped?.value
            XCTAssertEqual(watch.checks, 0, held)
            XCTAssertEqual(screen.outcomes, [], held)
            XCTAssertFalse(screen.letters.refetchOwed, held)
            XCTAssertEqual(screen.sweeps, 0, held)
        }
    }

    /// Another folder in front, and the app goes away with the check's
    /// STATUS on the wire, the Inbox's count changed: no sweep of the
    /// counts, which would be a LIST and a STATUS a folder sent while he
    /// is away, and nothing said on the line.
    @MainActor
    func testACountAnsweredAfterTheAppHasGoneSweepsNothing() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "sent", beforeUID: nil, limit: 50)
        let screen = Screen()
        screen.inboxInFront = false
        screen.paneCount = inboxUnread
        let watch = watch(repository, over: screen)
        lettersToHimself(1)
        server.clearLog()

        server.holdReplies(to: "STATUS")
        watch.start()
        try await until { self.clock.sleeping == 1 }
        clock.advance(by: MailWatch.interval)
        try await until { self.server.log.contains { $0.verb == "STATUS" } }
        let stopped = watch.stop()
        await server.releaseReplies(to: "STATUS")
        await stopped?.value
        XCTAssertEqual(verbs, ["STATUS"])
        XCTAssertEqual(screen.sweeps, 0)
        XCTAssertEqual(screen.outcomes, [])
    }

    /// Started again before it has been stopped, as a return to the app can
    /// start it while launch's start is still to come: one loop, so one
    /// check each half minute. Two would put two checks side by side.
    @MainActor
    func testStartingTwiceStartsOneLoop() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let watch = watch(repository, over: screen)
        watch.start()
        try await until { self.clock.sleeping == 1 }
        watch.start()
        // Long enough for a second loop, were there one, to go to sleep.
        for _ in 0..<20 where clock.sleeping == 1 {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(clock.sleeping, 1)
        await watch.stop()?.value
        XCTAssertEqual(clock.sleeping, 0)
    }

    /// The app password revoked while he reads, and the socket gone in the
    /// quiet. The check that finds the socket dead reconnects, as a read
    /// does, and its LOGIN is refused: said on the line, and that is the
    /// last password the watch sends. A letter he taps a moment later is
    /// told without the password going again; checks send nothing at all
    /// for as long as he stays. What he does still tries: a Refresh after a
    /// minute sends it once. Once Gmail takes it again and a Refresh of his
    /// logs in, the checks go on.
    @MainActor
    func testARefusedPasswordStopsTheChecksUntilHisOwnLoginIsAccepted() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let letter = screen.letters.shown[3]
        let watch = watch(repository, over: screen)
        var logins: Int { server.log.filter { $0.verb == "LOGIN" }.count }

        server.passwordRevoked = true
        await server.resetConnections()
        server.clearLog()
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(server.lostWrites.map(\.verb), ["NOOP"])
        XCTAssertEqual(server.log.map { "\($0.verb) \($0.status ?? "-")" }, ["LOGIN NO"])
        XCTAssertEqual(screen.outcomes, [.failed(.passwordNeedsUpdating, at: clock.now())])

        clock.advance(by: 10)
        do {
            _ = try await repository.open(letter)
            XCTFail("opened with a refused password")
        } catch {
            XCTAssertEqual(error as? MailError, .passwordNeedsUpdating)
        }
        XCTAssertEqual(logins, 1)

        for _ in 1...6 {
            clock.advance(by: MailWatch.interval)
            await watch.check()
        }
        XCTAssertEqual(logins, 1)
        XCTAssertEqual(server.log.count, 1)
        XCTAssertEqual(screen.outcomes.count, 7)
        XCTAssertTrue(screen.outcomes.allSatisfy {
            if case .failed(.passwordNeedsUpdating, _) = $0 { return true }
            return false
        })

        _ = try? await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(logins, 2)
        for _ in 1...2 {
            clock.advance(by: MailWatch.interval)
            await watch.check()
        }
        XCTAssertEqual(logins, 2)

        server.passwordRevoked = false
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(logins, 3)
        let arrived = lettersToHimself(1)
        server.clearLog()
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(screen.letters.shown.first.map { uid($0.id) }, arrived.first)

        // His LOGIN accepted is the end of the refusal: the next socket that
        // dies is replaced by the check that finds it, password and all.
        await server.resetConnections()
        let later = lettersToHimself(1, about: "link")
        server.clearLog()
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(verbs, ["LOGIN", "SELECT", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(screen.letters.shown.first.map { uid($0.id) }, later.first)
        XCTAssertEqual(screen.outcomes.last, .listed(mailboxID: "inbox", at: clock.now()))
    }

    /// A connection made with no LOGIN at all, a server that greets with
    /// PREAUTH, ends a refusal as an accepted LOGIN does: the checks go on,
    /// and replace the next socket that dies.
    @MainActor
    func testAConnectionMadeWithoutALoginEndsTheRefusalToo() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let watch = watch(repository, over: screen)
        server.passwordRevoked = true
        await server.resetConnections()
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(screen.outcomes, [.failed(.passwordNeedsUpdating, at: clock.now())])

        server.greeting = .preauthenticated(announcingCapabilities: true)
        clock.advance(by: 61)
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        await server.resetConnections()
        let arrived = lettersToHimself(1)
        server.clearLog()
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(verbs, ["SELECT", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(screen.letters.shown.first.map { uid($0.id) }, arrived.first)
    }

    /// Wi-Fi off: the check finds the socket dead and cannot connect, and
    /// says so. Each check after tries to connect again, which with no
    /// network fails before any password is sent; once the network is back,
    /// the next check connects and lists what came meanwhile.
    @MainActor
    func testWithNoConnectionEachCheckSaysSoAndTheFirstAfterItListsWhatCame() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let watch = watch(repository, over: screen)

        server.isSilent = true
        server.timeout = .milliseconds(20)
        await server.resetConnections()
        clock.advance(by: MailWatch.interval)
        await watch.check()
        guard case .failed(.cannotConnect, _)? = screen.outcomes.last else {
            return XCTFail("\(screen.outcomes)")
        }

        let arrived = lettersToHimself(1)
        server.isSilent = false
        server.timeout = .seconds(1)
        server.clearLog()
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(verbs, ["LOGIN", "SELECT", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(screen.letters.shown.first.map { uid($0.id) }, arrived.first)
        XCTAssertEqual(screen.outcomes.last, .listed(mailboxID: "inbox", at: clock.now()))

        // A connection the check makes is proven by its LOGIN, however the
        // rest of the check goes: a Flag eighty seconds on sends no probe.
        let letter = screen.letters.shown[3]
        await server.resetConnections()
        server.refusedVerbs = ["SELECT"]
        server.clearLog()
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(verbs, ["LOGIN", "SELECT"])
        server.refusedVerbs = []
        clock.advance(by: 80)
        server.clearLog()
        try await repository.setFlagged(true, on: letter)
        XCTAssertEqual(verbs, ["SELECT", "UID STORE"])
    }

    /// A LOGIN refused for a reason that is not the password, Gmail's
    /// `[ALERT]` asking for a sign-in on the web, stops the checks just the
    /// same: every half minute it would be the same loop of failed logins.
    @MainActor
    func testALoginRefusedForAnotherReasonStopsTheChecksToo() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let watch = watch(repository, over: screen)
        server.passwordRevoked = true
        server.loginRefusal = "[ALERT] Please log in via your web browser (Failure)"
        await server.resetConnections()
        server.clearLog()

        for _ in 1...5 {
            clock.advance(by: MailWatch.interval)
            await watch.check()
        }
        XCTAssertEqual(server.log.map { "\($0.verb) \($0.status ?? "-")" }, ["LOGIN NO"])
        XCTAssertEqual(screen.outcomes.count, 5)
        XCTAssertTrue(screen.outcomes.allSatisfy {
            if case .failed(.cannotConnect, _) = $0 { return true }
            return false
        })
    }

    /// More than a page arrived between two checks, after hours of the list
    /// held back, or a renumbered Inbox found on a reconnect: the list is
    /// owed a fetch afresh when he is back at the top, and no letter is
    /// fetched for it here. Fifty-one new letters on top of the list would
    /// leave a gap under them that paging never fills.
    @MainActor
    func testMoreThanAPageAtOnceOrARenumberingIsFetchedAfreshNotAddedTo() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let before = screen.letters.shown
        let watch = watch(repository, over: screen)
        screen.atTop = false
        lettersToHimself(IMAPMailRepository.mostNews + 1)
        server.clearLog()

        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH"])
        XCTAssertTrue(screen.letters.refetchOwed)
        XCTAssertEqual(screen.letters.shown, before)
        XCTAssertEqual(screen.sweeps, 1)

        // Renumbered while he is scrolled down: every check says so again,
        // and the counts are swept once, not every half minute. Back at the
        // top, the list is fetched afresh.
        let renumbered = Screen()
        _ = renumbered.letters.fetchedAfresh(before)
        renumbered.atTop = false
        server.renumber(Server.inbox, validity: 700_001, firstUID: 1_000)
        await server.resetConnections()
        server.clearLog()
        watch.target = renumbered
        for _ in 1...3 {
            clock.advance(by: MailWatch.interval)
            await watch.check()
        }
        XCTAssertEqual(verbs, ["LOGIN", "SELECT", "NOOP", "NOOP"])
        XCTAssertTrue(renumbered.letters.refetchOwed)
        XCTAssertEqual(renumbered.sweeps, 1)
        XCTAssertEqual(renumbered.refetches, 0)
        renumbered.atTop = true
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(renumbered.refetches, 1)
    }

    /// A day jumped to, or an Inbox whose first page never came: nothing of
    /// the list is checked, only the Inbox's count, one STATUS a check. A
    /// day's lowest letter is not the Inbox's, and every letter above it
    /// would come back as new; a list that never came would SEARCH the
    /// whole Inbox.
    @MainActor
    func testADayJumpedToOrAListThatNeverCameIsOnlyCounted() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        screen.fromNewest = false
        let watch = watch(repository, over: screen)
        lettersToHimself(1)
        server.clearLog()
        for _ in 1...2 {
            clock.advance(by: MailWatch.interval)
            await watch.check()
        }
        XCTAssertEqual(server.log.map(\.command), Array(repeating: "STATUS \"INBOX\" (UNSEEN)", count: 2))
        XCTAssertFalse(screen.letters.holdsNews)

        let never = Screen()
        never.fetched = false
        watch.target = never
        server.clearLog()
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(server.log.map(\.command), ["STATUS \"INBOX\" (UNSEEN)"])
    }

    /// He jumps to a day while a check that found a letter is out. The day
    /// does not take it, since its top is not the Inbox's; the counts
    /// follow it all the same; and once the list starts at the newest
    /// letter again, the next check searches for it and lists it, though
    /// the server has told the session of it already.
    @MainActor
    func testALetterFoundAsHeJumpsToADayIsListedOnceHeIsBackAtTheNewest() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let before = screen.letters.shown
        let watch = watch(repository, over: screen)
        let arrived = lettersToHimself(1)

        server.holdReplies(to: "UID FETCH")
        clock.advance(by: MailWatch.interval)
        let checking = Task { await watch.check() }
        try await until { self.server.log.contains { $0.verb == "UID FETCH" } }
        screen.fromNewest = false
        await server.releaseReplies(to: "UID FETCH")
        await checking.value
        XCTAssertEqual(screen.letters.shown, before)
        XCTAssertFalse(screen.letters.holdsNews)
        XCTAssertEqual(screen.sweeps, 1)

        screen.fromNewest = true
        server.clearLog()
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(screen.letters.shown.first.map { uid($0.id) }, arrived.first)
        XCTAssertEqual(screen.sweeps, 2)

        // A jump during a check that found nothing costs no sweep.
        server.clearLog()
        server.holdReplies(to: "NOOP")
        clock.advance(by: MailWatch.interval)
        let quiet = Task { await watch.check() }
        try await until { self.server.log.contains { $0.verb == "NOOP" } }
        screen.fromNewest = false
        await server.releaseReplies(to: "NOOP")
        await quiet.value
        XCTAssertEqual(screen.sweeps, 2)
        XCTAssertFalse(watch.searchOwed)
    }

    /// A letter came while his finger rested on the list, a tap on a row,
    /// and was held. Lifting a finger that never dragged tells the list
    /// nothing; the next check does, with nothing new, and it goes on.
    @MainActor
    func testALetterHeldUnderAFingerGoesOnAtTheNextCheckOnceItIsLifted() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let before = screen.letters.shown
        let watch = watch(repository, over: screen)
        screen.touching = true
        let arrived = lettersToHimself(1)
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(screen.letters.shown, before)
        XCTAssertTrue(screen.letters.holdsNews)

        screen.touching = false
        server.clearLog()
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(verbs, ["NOOP"])
        XCTAssertEqual(screen.letters.shown.first.map { uid($0.id) }, arrived.first)
        XCTAssertEqual(screen.sweeps, 1)
    }

    /// The server refuses part of a check that has found a letter, Gmail's
    /// `[UNAVAILABLE]` to the SEARCH or to the FETCH of the new letter, on a
    /// connection that stays up. The line says the check failed, and the
    /// next check searches again and lists it, though its NOOP says nothing
    /// has changed.
    @MainActor
    func testALetterACheckFailedToFetchIsListedByTheNext() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let watch = watch(repository, over: screen)
        for refused in ["UID SEARCH", "UID FETCH"] {
            let arrived = lettersToHimself(1, about: refused == "UID SEARCH" ? "search" : "fetch")
            server.refusedVerbs = [refused]
            clock.advance(by: MailWatch.interval)
            await watch.check()
            guard case .failed(.cannotConnect, _)? = screen.outcomes.last else {
                return XCTFail("\(refused): \(screen.outcomes)")
            }
            XCTAssertNotEqual(screen.letters.shown.first.map { uid($0.id) }, arrived.first, refused)

            server.refusedVerbs = []
            server.clearLog()
            clock.advance(by: MailWatch.interval)
            await watch.check()
            XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"], refused)
            XCTAssertEqual(screen.letters.shown.first.map { uid($0.id) }, arrived.first, refused)
            XCTAssertEqual(screen.outcomes.last, .listed(mailboxID: "inbox", at: clock.now()), refused)
        }
    }

    /// The watch's sweeps are quiet: one that fails leaves the counts with
    /// no alert, since he did nothing. Merged with one he asked for, before
    /// or after it, it is his, and says so. Dropped at launch, what was
    /// asked for is forgotten, whoever asked.
    @MainActor
    func testTheWatchsSweepsAreQuietUnlessMergedWithOneOfHis() async throws {
        var ran: [Bool] = []
        let sweeps = SweepCoalescer { quietly in ran.append(quietly) }
        sweeps.request(quietly: true)
        await sweeps.idle()
        sweeps.request(quietly: true)
        sweeps.request()
        await sweeps.idle()
        sweeps.request()
        sweeps.request(quietly: true)
        await sweeps.idle()
        XCTAssertEqual(ran, [true, false, false])

        ran = []
        let held = SweepCoalescer(held: true) { quietly in ran.append(quietly) }
        held.request()
        held.release(runningOwed: false)
        held.request(quietly: true)
        await held.idle()
        XCTAssertEqual(ran, [true])
    }

    /// An All Mailboxes search showing over the Inbox, which leaves All Mail
    /// open on the connection. The checks ask only for the Inbox's count, a
    /// STATUS that leaves All Mail selected, so the next page of results
    /// needs no SELECT to get back; a letter that comes meanwhile is counted
    /// at once and listed by the first check after the search ends.
    @MainActor
    func testWhileASearchShowsOnlyTheInboxCountIsCheckedAndTheSearchKeepsItsMailbox() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        screen.paneCount = inboxUnread
        let watch = watch(repository, over: screen)
        let hits = try await repository.search(in: "inbox", query: "garden", scope: .allMailboxes,
                                               beforeUID: nil, limit: 20)
        screen.letters.showResults(hits)
        let arrived = lettersToHimself(1)
        server.clearLog()

        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(server.log.map(\.command), ["STATUS \"INBOX\" (UNSEEN)"])
        XCTAssertEqual(screen.sweeps, 1)
        XCTAssertEqual(screen.letters.shown, hits)
        let next = try await repository.search(in: "inbox", query: "garden", scope: .allMailboxes,
                                               beforeUID: hits.last?.id, limit: 20)
        XCTAssertFalse(next.isEmpty)
        XCTAssertEqual(verbs, ["STATUS", "UID FETCH"])
        XCTAssertEqual(server.log.map(\.selected), [Server.allMail, Server.allMail])

        screen.letters.endSearch()
        server.clearLog()
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(verbs, ["SELECT", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(screen.letters.shown.first.map { uid($0.id) }, arrived.first)
    }

    /// Gmail told the session of a letter on the answer to the previews'
    /// FETCH, not on a NOOP, so the check's NOOP says nothing of it; the
    /// check searches all the same, and lists it. Nor does a date jump that
    /// found nothing that recent count as a listing of the Inbox, since the
    /// list on screen stays the one it was; nor a Refresh the server
    /// refused. Either used to let the check skip its SEARCH, and the letter
    /// waited for the next one to arrive.
    @MainActor
    func testALetterToldOfOnAnotherAnswerIsListedByTheNextCheck() async throws {
        let repository = makeRepository()
        let screen = try await inboxOnScreen(repository)
        let watch = watch(repository, over: screen)
        var ids = screen.letters.shown.prefix(5).map(\.id)

        clock.advance(by: 5)
        let first = lettersToHimself(1)
        _ = try await repository.previews(for: ids, in: "inbox")
        let far = Server.newestDate.addingTimeInterval(30 * 86_400)
        let window = try await repository.messages(around: far, in: "inbox", limit: 20)
        XCTAssertNil(window, "nothing that recent: the list stays")
        server.clearLog()
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(screen.letters.shown.first.map { uid($0.id) }, first.first)

        let second = lettersToHimself(1, about: "link")
        ids = screen.letters.shown.prefix(5).map(\.id)
        _ = try await repository.previews(for: ids, in: "inbox")
        server.refusedVerbs = ["UID SEARCH"]
        clock.advance(by: 5)
        do {
            _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
            XCTFail("a refused SEARCH listed the Inbox")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        server.refusedVerbs = []
        server.clearLog()
        clock.advance(by: MailWatch.interval)
        await watch.check()
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(screen.letters.shown.first.map { uid($0.id) }, second.first)
    }
}
