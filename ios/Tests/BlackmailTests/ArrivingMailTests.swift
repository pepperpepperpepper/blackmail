import XCTest
@testable import Blackmail

/// Mail that reaches the server while a mailbox is open on the connection,
/// and letters taken out of it elsewhere (B-045). A SEARCH answers from what
/// the server has told the session, and Gmail tells it when it chooses: on
/// the iPad a Refresh of the open Inbox listed the letters it already had,
/// and the three that had arrived were announced during the FETCH after the
/// SEARCH. `ScriptedIMAPServer.arrive` and `removeElsewhere` behave that
/// way. Over the shipping repository and client, with a clock the test
/// moves, so the commands counted are the ones the app sends.
final class ArrivingMailTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "ArrivingMailTests"

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

    private func searchHere(_ repository: IMAPMailRepository,
                            for query: String) async throws -> [MessageSummary] {
        try await repository.search(in: "inbox", query: query, scope: .currentMailbox,
                                    beforeUID: nil, limit: 50)
    }

    /// Letters he sends himself from the iPad, `count` of them, an hour
    /// apart after the newest in the Inbox. Their UIDs in the Inbox, oldest
    /// first.
    @discardableResult
    private func lettersToHimself(_ count: Int, about word: String = "note") -> [UInt32] {
        (1...count).compactMap { n in
            server.arrive(Server.Letter(from: Server.owner, to: [Server.owner],
                                        subject: "A \(word) to self \(n)",
                                        date: Server.newestDate.addingTimeInterval(Double(n) * 3_600),
                                        text: "Sent from the iPad to the same account.\r\n",
                                        messageID: "<self-\(word)-\(n)@example.com>"),
                          in: [Server.inbox, Server.allMail])[Server.inbox]
        }
    }

    // MARK: - Refresh

    /// What he did on the iPad: three letters to himself with the Inbox
    /// open, then Refresh. The Refresh's SEARCH used to go straight to the
    /// open Inbox, which Gmail answered with the seventeen letters it had
    /// announced, and the three were told of during the FETCH after it, too
    /// late for the list: a second Refresh showed them. The NOOP ahead of
    /// the SEARCH, in the same hold, has Gmail tell of them first, and it is
    /// the one command the Refresh adds.
    func testARefreshOfTheOpenInboxListsTheLettersThatArrivedOnTheFirstReload() async throws {
        let repository = makeRepository()
        let before = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        clock.advance(by: 60)
        let arrived = lettersToHimself(3)
        server.clearLog()

        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(rows.prefix(3).map { uid($0.id) }, arrived.reversed())
        XCTAssertEqual(rows.prefix(3).map(\.subject),
                       ["A note to self 3", "A note to self 2", "A note to self 1"])
        XCTAssertEqual(Array(rows.dropFirst(3).map(\.id)), Array(before.prefix(47).map(\.id)))
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(server.log.map(\.selected), Array(repeating: Server.inbox, count: 3))
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
    }

    /// A letter archived or binned from another client since the list was
    /// fetched: Gmail tells the session with an EXPUNGE on the same NOOP,
    /// so the same rule takes it off the list, for nothing more.
    func testARefreshOfTheOpenInboxNoLongerListsALetterRemovedElsewhere() async throws {
        let repository = makeRepository()
        let before = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        clock.advance(by: 60)
        server.removeElsewhere(uid: uid(before[0].id), from: Server.inbox)
        server.clearLog()

        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertFalse(rows.contains { $0.id == before[0].id })
        XCTAssertEqual(rows.first?.id, before[1].id)
        XCTAssertEqual(rows.count, 50)
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])
    }

    /// Refresh tapped again while he waits for a letter: three seconds on,
    /// it asks again, and finds the letter that came in between. Within two
    /// seconds of the last question it does not ask, which is a double tap,
    /// or a folder opened and refreshed at once.
    func testARefreshAsksAgainOnceTwoSecondsHaveGone() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()

        // The folder has just been opened: its SELECT has asked.
        clock.advance(by: 1.9)
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(verbs, ["UID SEARCH", "UID FETCH"])

        clock.advance(by: 30)
        server.clearLog()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let arrived = lettersToHimself(1)
        clock.advance(by: 3)
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(rows.first.map { uid($0.id) }, arrived.first)
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH", "NOOP", "UID SEARCH", "UID FETCH"])
    }

    /// The warm-up's NOOP as he picks the iPad up, and a write's probe after
    /// ninety seconds of quiet, have asked for the Inbox's news already, so
    /// the Refresh straight after either sends no NOOP of its own.
    func testARefreshStraightAfterTheWarmUpOrAWriteProbeSharesItsNOOP() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)

        clock.advance(by: 91)
        lettersToHimself(1, about: "warm")
        server.clearLog()
        await repository.warmUp()
        let afterWarmUp = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(afterWarmUp.first?.subject, "A warm to self 1")

        clock.advance(by: 91)
        lettersToHimself(1, about: "probe")
        server.clearLog()
        try await repository.setFlagged(true, on: rows[3])
        let afterWrite = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(verbs, ["NOOP", "UID STORE", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(afterWrite.first?.subject, "A probe to self 1")
    }

    /// A SELECT has asked for the folder's news however long its answer
    /// takes, and nothing comes between it and the SEARCH in the same hold.
    /// Timed from when it went, a SELECT answered after two seconds, All
    /// Mail's on Gmail or any on a poor link, was followed by a NOOP it had
    /// made pointless, a round trip more on the slowest folder opens. The
    /// same for a search in a folder the connection does not have open.
    func testASlowSELECTIsNotFollowedByANOOP() async throws {
        let clock = self.clock!
        let client = IMAPClient(account: server.account, transport: server.transportFactory,
                                now: { clock.now() })
        try await client.connect(password: server.password)

        server.holdReplies(to: "SELECT")
        let opened = Task { try await client.page(in: Server.allMail, searching: ["ALL"]) { _ in [] } }
        try await until { self.server.log.contains { $0.verb == "SELECT" } }
        clock.advance(by: 2.5)
        await server.releaseReplies(to: "SELECT")
        _ = try await finishing { try await opened.value }

        server.holdReplies(to: "SELECT")
        let searched = Task {
            try await client.search("ALL", across: [IMAPSearchTarget(mailbox: Server.sent,
                                                                     summariesOfNewest: 0)])
        }
        try await until { self.server.log.filter { $0.verb == "SELECT" }.count == 2 }
        clock.advance(by: 2.5)
        await server.releaseReplies(to: "SELECT")
        _ = try await finishing { try await searched.value }

        XCTAssertEqual(verbs, ["LOGIN", "SELECT", "UID SEARCH", "SELECT", "UID SEARCH"])
        await client.disconnect()
    }

    /// The clock set back, by the network's time after a flat battery or
    /// by hand, dates the last question after now. Taken for a moment ago,
    /// as a negative age was, it kept every Refresh and every search from
    /// asking until the clock caught up: here, an hour of missing mail.
    func testAClockSetBackStillLetsARefreshAndASearchAsk() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        clock.advance(by: 60)
        _ = try await searchHere(repository, for: "zeppelin")

        clock.advance(by: -3_600)
        let arrived = lettersToHimself(1)
        server.clearLog()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(rows.first.map { uid($0.id) }, arrived.first)
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])

        // The burst the search before the step started is dated after now
        // as well.
        clock.advance(by: 5)
        let found = lettersToHimself(1, about: "zeppelin")
        server.clearLog()
        let hits = try await searchHere(repository, for: "zeppelin")
        XCTAssertEqual(hits.map { uid($0.id) }, found)
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])
    }

    /// A socket that died in the quiet before a Refresh, a date jump or a
    /// search in the open folder, which is how a socket dies on the iPad.
    /// The first thing written into it is the NOOP that asks for the
    /// folder's news, not the SEARCH. It is lost, the read goes again on
    /// one new connection, whose SELECT asks in its place, and the rows are
    /// the ones a live socket gives.
    func testAfterADeadSocketTheNOOPIsLostAndTheListingLandsOnOneReconnect() async throws {
        let repository = makeRepository()
        let listed = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)
        let day = Server.newestDate.addingTimeInterval(-40 * 86_400)
        let jump = try await repository.messages(around: day, in: "inbox", limit: 20)
        let jumped = try XCTUnwrap(jump)
        let found = try await searchHere(repository, for: "dinner")
        XCTAssertFalse(found.isEmpty)

        func deadSocket() async {
            clock.advance(by: 300)
            await server.resetConnections()
            server.clearLog()
        }

        await deadSocket()
        let refreshed = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)
        XCTAssertEqual(refreshed.map(\.id), listed.map(\.id))
        XCTAssertEqual(server.lostWrites.map(\.verb), ["NOOP"])
        XCTAssertEqual(verbs, ["LOGIN", "SELECT", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(Set(server.log.map(\.connection)), [2])

        await deadSocket()
        let rejump = try await repository.messages(around: day, in: "inbox", limit: 20)
        let rejumped = try XCTUnwrap(rejump)
        XCTAssertEqual(rejumped.messages.map(\.id), jumped.messages.map(\.id))
        XCTAssertEqual(rejumped.anchorIndex, jumped.anchorIndex)
        XCTAssertEqual(server.lostWrites.map(\.verb), ["NOOP"])
        XCTAssertEqual(verbs, ["LOGIN", "SELECT", "UID SEARCH", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(Set(server.log.map(\.connection)), [3])

        await deadSocket()
        let refound = try await searchHere(repository, for: "dinner")
        XCTAssertEqual(refound.map(\.id), found.map(\.id))
        XCTAssertEqual(server.lostWrites.map(\.verb), ["NOOP"])
        XCTAssertEqual(verbs, ["LOGIN", "SELECT", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(Set(server.log.map(\.connection)), [4])

        XCTAssertEqual(server.connectionsOpened, 4)
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
    }

    // MARK: - Paging and the date jump

    /// Paging walks the listing the Refresh took, so it asks for nothing:
    /// mail arriving while he scrolls through last year must not renumber
    /// what is under his thumb.
    func testAPageAddsNoCommand() async throws {
        let repository = makeRepository()
        let first = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        clock.advance(by: 60)
        lettersToHimself(2)
        server.clearLog()

        let next = try await repository.listMessages(in: "inbox", beforeUID: first.last?.id, limit: 50)
        XCTAssertEqual(next.count, 50)
        XCTAssertEqual(verbs, ["UID FETCH"])
    }

    /// A page whose snapshot has gone from under the list SEARCHes the
    /// folder again, and asks for no news first: the page is cut below a
    /// letter on screen, and what a NOOP would announce comes above it. So
    /// it adds nothing but the SEARCH it cannot do without. Here the second
    /// repository has the Inbox open from a search, and no snapshot of it.
    func testAPageWhoseSnapshotHasGoneAsksForNothingEither() async throws {
        let lister = makeRepository()
        let rows = try await lister.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let searcher = makeRepository()
        _ = try await searchHere(searcher, for: "dinner")
        clock.advance(by: 60)
        lettersToHimself(2)
        server.clearLog()

        let next = try await searcher.listMessages(in: "inbox", beforeUID: rows[5].id, limit: 20)
        XCTAssertEqual(next.map(\.id), rows[6..<26].map(\.id))
        XCTAssertEqual(verbs, ["UID SEARCH", "UID FETCH"])
    }

    /// A jump to a day in the open folder is a listing too: it lands on a
    /// letter that arrived after the folder was opened. Its SEARCH for the
    /// day used to find nothing on or after it, and the jump said so.
    func testADateJumpInTheOpenFolderLandsOnALetterThatArrivedSinceItWasOpened() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        clock.advance(by: 60)
        // Two days after the newest letter, so that it is the only one on
        // or after its day in any time zone the suite runs in.
        let day = Server.newestDate.addingTimeInterval(2 * 86_400)
        let arrived = server.arrive(Server.Letter(from: Server.owner, to: [Server.owner],
                                                  subject: "Two days on", date: day,
                                                  text: "Sent from the iPad to the same account.\r\n",
                                                  messageID: "<two-days-on@example.com>"),
                                    in: [Server.inbox, Server.allMail])
        server.clearLog()

        let window = try await repository.messages(around: day, in: "inbox", limit: 20)
        let landed = try XCTUnwrap(window)
        XCTAssertEqual(uid(landed.messages[landed.anchorIndex].id), arrived[Server.inbox])
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID SEARCH", "UID FETCH"])
    }

    // MARK: - Search

    /// A search of the open mailbox, the Current Mailbox scope, for a word
    /// in a letter that arrived after the mailbox was opened. Its SEARCH
    /// used to go to the open mailbox without asking, and found nothing.
    func testASearchOfTheOpenMailboxFindsALetterThatArrivedAfterItWasOpened() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        clock.advance(by: 60)
        let arrived = lettersToHimself(1, about: "zeppelin")
        server.clearLog()

        let hits = try await repository.search(in: "inbox", query: "zeppelin", scope: .currentMailbox,
                                               beforeUID: nil, limit: 50)
        XCTAssertEqual(hits.map { uid($0.id) }, arrived)
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])
    }

    /// What a search costs a keystroke. In the open mailbox, the first
    /// search of a burst asks, and the rest ride on its answer while it is
    /// under ten seconds old. All Mailboxes, with the Inbox open, SELECTs
    /// each of its mailboxes every time, which asks, and adds nothing.
    func testTheFirstKeystrokeOfABurstAsksAndTheRestAddNothing() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        clock.advance(by: 60)
        lettersToHimself(1, about: "zeppelin")
        server.clearLog()

        // A key every two seconds, the whole burst inside ten.
        for query in ["zep", "zepp", "zeppe", "zeppel", "zeppelin"] {
            let hits = try await repository.search(in: "inbox", query: query, scope: .currentMailbox,
                                                   beforeUID: nil, limit: 50)
            XCTAssertEqual(hits.map(\.subject), ["A zeppelin to self 1"])
            clock.advance(by: 2)
        }
        XCTAssertEqual(verbs.filter { $0 == "NOOP" }.count, 1)
        XCTAssertEqual(verbs.first, "NOOP")
        XCTAssertEqual(verbs.filter { $0 == "UID SEARCH" }.count, 5)
        XCTAssertEqual(verbs.count, 11)

        // A pause of ten seconds, and the next search asks again.
        clock.advance(by: 10)
        server.clearLog()
        _ = try await repository.search(in: "inbox", query: "zeppelin", scope: .currentMailbox,
                                        beforeUID: nil, limit: 50)
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])

        // Everywhere: Trash, Spam and All Mail each SELECTed, no NOOP.
        clock.advance(by: 60)
        for query in ["zep", "zeppelin"] {
            server.clearLog()
            let hits = try await repository.search(in: "inbox", query: query, scope: .allMailboxes,
                                                   beforeUID: nil, limit: 50)
            XCTAssertEqual(hits.map(\.subject), ["A zeppelin to self 1"])
            XCTAssertEqual(verbs, ["SELECT", "UID SEARCH", "SELECT", "UID SEARCH",
                                   "SELECT", "UID SEARCH", "UID FETCH"])
            clock.advance(by: 60)
        }
    }

    /// The first search of a burst asks even a few seconds after the
    /// folder was opened or refreshed, for the letter he is looking for may
    /// have come in between. The ten seconds a burst goes on used to be
    /// timed from the SELECT or the Refresh's NOOP, so neither search here
    /// asked, and neither found its letter.
    func testTheFirstSearchAsksSoonAfterTheFolderWasOpenedOrRefreshed() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        clock.advance(by: 5)
        let first = lettersToHimself(1, about: "zeppelin")
        clock.advance(by: 3)
        server.clearLog()
        let hits = try await searchHere(repository, for: "zeppelin")
        XCTAssertEqual(hits.map { uid($0.id) }, first)
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])

        clock.advance(by: 60)
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        clock.advance(by: 3)
        let second = lettersToHimself(1, about: "dirigible")
        clock.advance(by: 2)
        server.clearLog()
        let found = try await searchHere(repository, for: "dirigible")
        XCTAssertEqual(found.map { uid($0.id) }, second)
        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])
    }

    // MARK: - The count the connection log reports

    /// The SESSION-IDENT line puts the server's count beside the listing's,
    /// which is how the iPad's log showed the listing short. The count now
    /// follows the EXISTS and EXPUNGE the NOOP brings, and an EXISTS that
    /// rides on a FETCH within the two seconds, where nothing was asked, so
    /// a listing that missed mail still shows as one.
    func testTheCountFollowsTheExistsAndExpungeTheServerSends() async throws {
        let clock = self.clock!
        let client = IMAPClient(account: server.account, transport: server.transportFactory,
                                now: { clock.now() })
        try await client.connect(password: server.password)
        let opened = try await client.page(in: Server.inbox, searching: ["ALL"]) { _ in [] }
        XCTAssertEqual(opened.found[0].uids.count, 120)
        let exists = await client.lastReport(for: Server.inbox)?.exists
        XCTAssertEqual(exists, 120)

        clock.advance(by: 60)
        lettersToHimself(3)
        server.removeElsewhere(uid: opened.found[0].uids[0], from: Server.inbox)
        let caughtUp = try await client.page(in: Server.inbox, searching: ["ALL"]) { _ in [] }
        XCTAssertEqual(caughtUp.found[0].uids.count, 122)
        let afterNOOP = await client.lastReport(for: Server.inbox)?.exists
        XCTAssertEqual(afterNOOP, 122)

        let late = lettersToHimself(1, about: "late")
        let short = try await client.page(in: Server.inbox, searching: ["ALL"]) { found in
            Array(found[0].suffix(5))
        }
        XCTAssertEqual(short.found[0].uids.count, 122)
        XCTAssertFalse(short.found[0].uids.contains(late[0]))
        let afterFetch = await client.lastReport(for: Server.inbox)?.exists
        XCTAssertEqual(afterFetch, 123)
        XCTAssertEqual(server.log.map(\.verb),
                       ["LOGIN", "SELECT", "UID SEARCH", "NOOP", "UID SEARCH", "UID SEARCH", "UID FETCH"])

        // An answer with an EXPUNGE and no EXISTS counts down from where
        // the last EXISTS left it, not from the SELECT's.
        clock.advance(by: 60)
        server.removeElsewhere(uid: opened.found[0].uids[1], from: Server.inbox)
        server.clearLog()
        _ = try await client.page(in: Server.inbox, searching: ["ALL"]) { _ in [] }
        XCTAssertEqual(server.log.map(\.verb), ["NOOP", "UID SEARCH"])
        let afterExpunge = await client.lastReport(for: Server.inbox)?.exists
        XCTAssertEqual(afterExpunge, 122)

        // A SELECT's EXISTS is the count of the mailbox it opens, not of the
        // one it leaves.
        _ = try await client.page(in: Server.sent, searching: ["ALL"]) { _ in [] }
        let inbox = await client.lastReport(for: Server.inbox)?.exists
        let sent = await client.lastReport(for: Server.sent)?.exists
        XCTAssertEqual(inbox, 122)
        XCTAssertEqual(sent, 8)
        await client.disconnect()
    }
}
