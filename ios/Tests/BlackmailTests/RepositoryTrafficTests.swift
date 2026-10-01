import XCTest
@testable import Blackmail

/// The work the repository does that he did not ask for: the address book
/// written out once per page rather than once per address, the Inbox opened
/// before any folder is counted, the counts' sweeps merged, the Move sheet's
/// folder names without the sweep, and a jump to a day in place of the page
/// it used to follow. Over `ScriptedIMAPServer`, through the shipping
/// repository and client, so the counts below are commands the app sends.
final class RepositoryTrafficTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "RepositoryTrafficTests"

    private var server: ScriptedIMAPServer!
    private var defaults: CountingDefaults!
    private var book: RecipientBook!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        defaults = CountingDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        server = nil
        defaults = nil
        book = nil
        super.tearDown()
    }

    private func makeRepository(password: String? = nil) -> IMAPMailRepository {
        IMAPMailRepository(account: server.account, password: password ?? server.password,
                           transport: server.transportFactory, recipients: book,
                           shelf: keptShelf(for: server.account))
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

    private func unread(in folders: [Mailbox]?, _ mailbox: String) -> Int? {
        folders?.first { $0.id == mailbox }?.unreadCount
    }

    // MARK: - The address book

    /// Fifty rows name a hundred addresses, a sender and a recipient each,
    /// and the whole book used to be encoded and written for every one of
    /// them, on the repository's actor, with every other call to the
    /// repository waiting behind it.
    func testAPageOfRowsWritesTheAddressBookOnceAndNotOncePerAddress() async throws {
        let repository = makeRepository()
        // His own address is noted as the repository is made, and written
        // with the first page.
        XCTAssertEqual(defaults.writes.value, 0)

        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(rows.count, 50)
        XCTAssertEqual(defaults.writes.value, 1)

        let next = try await repository.listMessages(in: "inbox", beforeUID: rows.last?.id, limit: 50)
        XCTAssertEqual(next.count, 50)
        XCTAssertEqual(defaults.writes.value, 2)

        // A search everywhere draws rows from three mailboxes, the binned
        // hits of Trash and Spam and a page of All Mail: one write each.
        let hits = try await repository.search(in: "inbox", query: "garden", scope: .allMailboxes,
                                               beforeUID: nil, limit: 50)
        XCTAssertEqual(Set(hits.map(\.mailboxID)), [Server.trash, Server.spam, Server.allMail])
        XCTAssertEqual(defaults.writes.value, 5)

        // And what was written is everything noted, his own address among it.
        let reopened = RecipientBook(defaults: defaults)
        XCTAssertEqual(Set(reopened.suggestions(for: "", limit: 100).map(\.address)),
                       [Server.owner.address, Server.sam.address, Server.carlo.address,
                        Server.jane.address, "prizes@example.net"])
    }

    // MARK: - Launch

    /// What the container does at launch, all at once: the folder pane asks
    /// for the names and for the counts, and the Inbox opens itself. The
    /// counts are held, as the pane holds them, until the Inbox's first page
    /// has been tried.
    ///
    /// The Inbox's role used to be found by the whole sweep, so its SELECT
    /// came after a STATUS for every folder, with the pane's own sweep
    /// interleaved on top: eighteen or so commands deep on his account.
    func testAColdLaunchOpensTheInboxBeforeItCountsAnyFolder() async throws {
        let repository = makeRepository()
        let swept = Deliveries()
        let sweeps = await SweepCoalescer(held: true) {
            if let folders = try? await repository.listMailboxes() { swept.add(folders) }
        }

        await sweeps.request()
        async let names = repository.folders()
        async let firstPage = repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let (folders, rows) = try await (names, firstPage)
        let beforeTheCounts = server.log.map(\.command)
        await sweeps.release(runningOwed: true)
        try await finishing { await sweeps.idle() }

        // LOGIN, the one LIST the names and the Inbox's role share, and the
        // Inbox's first page, with nothing counted before it.
        XCTAssertEqual(beforeTheCounts.count, 5, "\(beforeTheCounts)")
        XCTAssertEqual(Array(server.log.prefix(5).map(\.verb)),
                       ["LOGIN", "LIST", "SELECT", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(server.log[2].command, "SELECT \"INBOX\"")
        // Then the sweep, whole.
        XCTAssertEqual(Array(server.log.dropFirst(5).map(\.verb)),
                       ["LIST"] + Array(repeating: "STATUS", count: 7))
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        XCTAssertEqual(server.connectionsOpened, 1)

        XCTAssertEqual(rows.count, 50)
        XCTAssertEqual(swept.all.count, 1)
        XCTAssertEqual(unread(in: swept.all.last, Server.inbox), 6)
        XCTAssertEqual(folders.map(\.id), swept.all.last?.map(\.id))
        XCTAssertTrue(folders.allSatisfy { $0.unreadCount == 0 })
        // The roles came from that LIST, so the first page's rows are
        // counted in All Mail as well as the Inbox, and reading one of them
        // takes All Mail's count down too.
        XCTAssertTrue(rows.allSatisfy { $0.countedFolderIDs.contains(Server.allMail) })
    }

    /// Held sweeps send nothing, however often they are asked for, and are
    /// one sweep when let go.
    func testHeldSweepsSendNothingUntilLetGoAndThenRunOnce() async throws {
        let repository = makeRepository()
        _ = try await repository.folders()
        server.clearLog()
        let swept = Deliveries()
        let sweeps = await SweepCoalescer(held: true) {
            if let folders = try? await repository.listMailboxes() { swept.add(folders) }
        }
        for _ in 0..<4 { await sweeps.request() }
        await sweeps.idle()
        XCTAssertEqual(server.log, [])

        await sweeps.release(runningOwed: true)
        try await finishing { await sweeps.idle() }
        XCTAssertEqual(server.log.map(\.verb), ["LIST"] + Array(repeating: "STATUS", count: 7))
        XCTAssertEqual(swept.all.count, 1)
    }

    /// A launch that cannot get a connection: a password Gmail refuses, and
    /// a server that never answers. The folder names and the Inbox share one
    /// attempt, and the held counts are dropped with the first page.
    ///
    /// Let go whichever way the page went, the sweep would connect again
    /// straight after the failure. The client takes a connect that comes
    /// after a failed one for him trying again, so the same wrong password
    /// would go a second time, and an unreachable server would cost a
    /// second connect timeout, thirty seconds each on the iPad.
    ///
    /// The connection is held in its handshake until both calls are waiting
    /// for it, as they are at launch, where they ask in the same instant.
    /// Left to the scheduler, the second call now and then started only
    /// after the attempt had failed, which the client rightly takes for
    /// another attempt, and the test failed with two connections.
    func testALaunchThatCannotConnectTriesOnceAndLeavesTheCountsUnasked() async throws {
        let failures: [(label: String, password: String?, silent: Bool)] = [
            ("refused password", "not-the-password", false),
            ("no answer", nil, true),
        ]
        for (label, password, silent) in failures {
            server = ScriptedIMAPServer()
            server.isSilent = silent
            server.holdHandshakes()
            let repository = makeRepository(password: password)
            let sweeps = await SweepCoalescer(held: true) {
                _ = try? await repository.listMailboxes()
            }

            await sweeps.request()
            async let names = try? repository.folders()
            async let firstPage = try? repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
            try await until { await repository.waitingForExchange == 1 }
            // Short only where the silence is the point: the greeting that
            // never comes. The refused password's replies come at once, and
            // a short deadline on them could fire first on a busy machine.
            if silent { server.timeout = .milliseconds(20) }
            await server.releaseHandshakes()
            let (folders, rows) = await (names, firstPage)
            await sweeps.release(runningOwed: rows != nil)
            try await finishing { await sweeps.idle() }

            XCTAssertNil(folders, label)
            XCTAssertNil(rows, label)
            XCTAssertEqual(server.log.map(\.verb), silent ? [] : ["LOGIN"], label)
            XCTAssertEqual(server.connectionsOpened, 1, label)
        }
    }

    // MARK: - Sweeps

    /// Six requests for the counts while one sweep is running: a letter
    /// arrives after that sweep has counted the Inbox, and every request
    /// after it wants the counts to show it. The first sweep finishes, and
    /// one more runs, not five; it counts the new letter.
    func testOverlappingSweepRequestsRunOneMoreSweepAndItCountsTheLastChange() async throws {
        let repository = makeRepository()
        _ = try await repository.folders()
        server.clearLog()
        let swept = Deliveries()
        let sweeps = await SweepCoalescer {
            if let folders = try? await repository.listMailboxes() { swept.add(folders) }
        }

        server.holdReplies(to: "STATUS")
        await sweeps.request()
        try await until { self.server.log.contains { $0.verb == "STATUS" } }
        XCTAssertEqual(server.log.last?.command, "STATUS \"INBOX\" (UNSEEN)")
        server.deliver(Server.Letter(from: Server.carlo, to: [Server.owner],
                                     subject: "Arrived mid-sweep",
                                     date: Server.newestDate.addingTimeInterval(3_600),
                                     text: "It came while the counts were being taken.\r\n",
                                     messageID: "<mid-sweep@example.org>"),
                       to: [Server.inbox, Server.allMail])
        for _ in 0..<5 { await sweeps.request() }
        await server.releaseReplies(to: "STATUS")
        try await finishing { await sweeps.idle() }

        XCTAssertEqual(server.log.filter { $0.verb == "LIST" }.count, 2)
        XCTAssertEqual(server.log.filter { $0.verb == "STATUS" }.count, 14)
        XCTAssertEqual(swept.all.count, 2)
        XCTAssertEqual(unread(in: swept.all.first, Server.inbox), 6)
        XCTAssertEqual(unread(in: swept.all.last, Server.inbox), 7)
        XCTAssertEqual(unread(in: swept.all.last, Server.allMail), 7)

        // A request after they are over is a sweep of its own.
        await sweeps.request()
        try await finishing { await sweeps.idle() }
        XCTAssertEqual(swept.all.count, 3)
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
    }

    /// A sweep that finds the connection dead, and the server not answering
    /// when it reconnects, connects once more and gives up. Whether the
    /// socket was reset while the iPad slept or the server merely went
    /// quiet, that is two connections in all, the first one's and the
    /// reconnect.
    ///
    /// The LIST is retried in the listing it shares, and that is the only
    /// retry. A second around the whole sweep would take the inner
    /// reconnect's failure, which leaves the client disconnected, for a
    /// dropped socket and connect a third time: on the iPad, a second
    /// connect timeout with the connection's gate held.
    func testASweepThatCannotReconnectConnectsOnceMoreAndNoMore() async throws {
        let failures: [(label: String, reset: Bool)] = [
            ("gone quiet", false),
            ("socket reset, then quiet", true),
        ]
        for (label, reset) in failures {
            server = ScriptedIMAPServer()
            server.timeout = .milliseconds(20)
            let repository = makeRepository()
            _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)

            if reset { await server.resetConnections() }
            server.isSilent = true
            do {
                _ = try await finishing(within: 1) { try await repository.listMailboxes() }
                XCTFail("\(label): a server that stopped answering cannot have listed its folders")
            } catch {
                XCTAssertEqual(error as? MailError, .cannotConnect, label)
            }
            XCTAssertEqual(server.connectionsOpened, 2, label)

            // And the next sweep, with the server back, works.
            server.isSilent = false
            let folders = try await finishing { try await repository.listMailboxes() }
            XCTAssertEqual(unread(in: folders, Server.inbox), 6, label)
            XCTAssertEqual(server.connectionsOpened, 3, label)
        }
    }

    /// He reads an unread letter while a sweep is out, one that had already
    /// counted the Inbox before the letter's flag reached the server. That
    /// sweep comes back with the Inbox one too many; the pane puts its read
    /// mark on it as it lands (`FolderCounts.land`, B-059), and, taking it
    /// off, asks for one more sweep if one is out, and that one counts the
    /// letter read.
    ///
    /// At launch this is the usual case rather than a rare one: the counts
    /// are asked for once the Inbox's rows are up, which is when he taps the
    /// newest unread letter.
    func testALetterReadWhileASweepIsOutIsCountedByTheSweepAfterIt() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = try XCTUnwrap(rows.first { !$0.isRead })
        server.clearLog()
        let swept = Deliveries()
        let sweeps = await SweepCoalescer {
            if let folders = try? await repository.listMailboxes() { swept.add(folders) }
        }

        // With no sweep out, the pane's arithmetic stands on the last one's
        // counts and nothing is sent.
        await sweeps.requestIfRunning()
        await sweeps.idle()
        XCTAssertEqual(server.log, [])

        // The Inbox counted with the letter still unread; the STORE waits
        // for the connection and then goes ahead of the rest of the sweep.
        server.holdReplies(to: "STATUS")
        await sweeps.request()
        try await until { self.server.log.contains { $0.verb == "STATUS" } }
        XCTAssertEqual(server.log.last?.command, "STATUS \"INBOX\" (UNSEEN)")
        server.holdReplies(to: "UID STORE")
        async let read: Void = repository.setRead(true, on: letter)
        try await until { await repository.waitingForExchange > 0 }
        await server.releaseReplies(to: "STATUS")
        try await until { self.server.log.contains { $0.verb == "UID STORE" } }
        // The rest of the sweep waits until the pane has done its sum.
        server.holdReplies(to: "STATUS")
        await server.releaseReplies(to: "UID STORE")
        try await read

        await sweeps.requestIfRunning()
        await server.releaseReplies(to: "STATUS")
        try await finishing { await sweeps.idle() }

        XCTAssertEqual(server.log.map(\.verb),
                       ["LIST", "STATUS", "UID STORE"] + Array(repeating: "STATUS", count: 6)
                        + ["LIST"] + Array(repeating: "STATUS", count: 7))
        XCTAssertEqual(swept.all.count, 2)
        XCTAssertEqual(unread(in: swept.all.first, Server.inbox), 6)
        XCTAssertEqual(unread(in: swept.all.last, Server.inbox), 5)
        XCTAssertEqual(unread(in: swept.all.last, Server.allMail), 5)
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
    }

    // MARK: - The Move sheet

    /// The sheet shows folder names and nothing else. From cold that is one
    /// LIST, and once the folders have been listed it is nothing at all. It
    /// used to be the whole sweep, a STATUS per folder, every time it opened.
    func testTheMoveSheetsFoldersAreOneLISTFromColdAndNothingOnceListed() async throws {
        let repository = makeRepository()
        let cold = try await repository.folders()
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN", "LIST"])
        XCTAssertEqual(cold.map(\.id), [Server.inbox, Server.drafts, Server.sent, Server.spam,
                                        Server.trash, Server.allMail, Server.starred])
        XCTAssertTrue(cold.allSatisfy { $0.unreadCount == 0 })

        let swept = try await repository.listMailboxes()
        server.clearLog()
        let listed = try await repository.folders()
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(listed.map(\.id), swept.map(\.id))
        XCTAssertEqual(listed.map(\.name), swept.map(\.name))

        // A folder opened by its role word finds its real name there too.
        _ = try await repository.listMessages(in: "sent", beforeUID: nil, limit: 5)
        XCTAssertEqual(server.log.map(\.command).first, "SELECT \"[Gmail]/Sent Mail\"")
        XCTAssertFalse(server.log.contains { $0.verb == "LIST" || $0.verb == "STATUS" })
    }

    // MARK: - A folder opened to jump to a day

    /// All Mail opened in order to jump to a day loads the day and nothing
    /// else. It used to load its newest page first, draw today's mail and
    /// then replace it.
    func testAFolderOpenedToJumpLoadsTheDayInsteadOfItsNewestPage() async throws {
        let repository = makeRepository()
        _ = try await repository.folders()
        server.clearLog()
        let day = Server.newestDate.addingTimeInterval(-40 * 86_400)

        var landed: MessageWindow?
        var newestPages = 0
        let fellBack = await ListOpening.open(
            at: day,
            jump: { day in
                do {
                    landed = try await repository.messages(around: day, in: Server.allMail, limit: 50)
                    return landed == nil ? .nothingThatRecent : .landed
                } catch {
                    return .failed(.cannotConnect)
                }
            },
            newest: {
                newestPages += 1
                _ = try? await repository.listMessages(in: Server.allMail, beforeUID: nil, limit: 50)
            })

        XCTAssertNil(fellBack)
        XCTAssertEqual(newestPages, 0)
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(server.log.first?.command, "SELECT \"[Gmail]/All Mail\"")
        let window = try XCTUnwrap(landed)
        XCTAssertGreaterThanOrEqual(window.landedOn, day)
        XCTAssertLessThan(window.landedOn, day.addingTimeInterval(86_400))
    }

    /// A day with nothing on or after it leaves the jump nothing to show,
    /// so the newest page is loaded after it and the caller told why.
    func testAJumpPastTheNewestMailFallsBackToTheNewestPage() async throws {
        let repository = makeRepository()
        _ = try await repository.folders()
        server.clearLog()

        var newest: [MessageSummary] = []
        let fellBack = await ListOpening.open(
            at: Server.newestDate.addingTimeInterval(30 * 86_400),
            jump: { day in
                do {
                    let window = try await repository.messages(around: day, in: Server.allMail, limit: 50)
                    return window == nil ? .nothingThatRecent : .landed
                } catch {
                    return .failed(.cannotConnect)
                }
            },
            newest: {
                newest = (try? await repository.listMessages(in: Server.allMail, beforeUID: nil,
                                                             limit: 50)) ?? []
            })

        XCTAssertEqual(fellBack, .nothingThatRecent)
        XCTAssertEqual(newest.count, 50)
        XCTAssertEqual(server.log.map(\.command).suffix(2).first, "UID SEARCH ALL")
        XCTAssertEqual(server.log.last?.verb, "UID FETCH")
    }

    /// A jump that fails falls back to the newest page too, so the pane is
    /// not left empty. One overtaken by a refresh or a search leaves the
    /// list to that, and a list opened with no day loads its newest page.
    func testAFailedJumpFallsBackAndAnOvertakenOneLeavesTheListAlone() async {
        let day = Server.newestDate
        var calls: [String] = []

        let failed = await ListOpening.open(at: day,
                                            jump: { _ in calls.append("jump"); return .failed(.cannotConnect) },
                                            newest: { calls.append("newest") })
        XCTAssertEqual(failed, .failed(.cannotConnect))
        XCTAssertEqual(calls, ["jump", "newest"])

        calls = []
        let overtaken = await ListOpening.open(at: day,
                                               jump: { _ in calls.append("jump"); return .superseded },
                                               newest: { calls.append("newest") })
        XCTAssertNil(overtaken)
        XCTAssertEqual(calls, ["jump"])

        calls = []
        let plain = await ListOpening.open(at: nil,
                                           jump: { _ in calls.append("jump"); return .landed },
                                           newest: { calls.append("newest") })
        XCTAssertNil(plain)
        XCTAssertEqual(calls, ["newest"])
    }

    /// A jump that fails once the list has moved on, to a search he typed
    /// while it was on its way, leaves the list to the search: no newest
    /// page, which would clear the search box, and nothing said about the
    /// failure. The same failure for the list still on screen falls back.
    ///
    /// Only a jump that succeeded was checked against the list's
    /// generation at first, so a failure was reported as one whatever had
    /// happened meanwhile.
    func testAJumpThatFailsAfterTheListMovedOnLeavesTheListAlone() async throws {
        let repository = makeRepository()
        _ = try await repository.folders()
        server.refusedMailboxes = [Server.allMail]

        for movedOn in [true, false] {
            server.clearLog()
            // The list's generation; a search bumps it.
            let generation = Counter()
            let newestPages = Counter()
            server.holdReplies(to: "SELECT")
            async let opened = ListOpening.open(
                at: Server.newestDate,
                jump: { day in
                    let asked = generation.value
                    let fetched: Result<MessageWindow?, Error>
                    do {
                        fetched = .success(try await repository.messages(around: day, in: Server.allMail,
                                                                         limit: 50))
                    } catch {
                        fetched = .failure(error)
                    }
                    return ListOpening.settle(fetched, current: asked == generation.value)
                },
                newest: { newestPages.add() })
            try await until { self.server.log.contains { $0.verb == "SELECT" } }
            if movedOn { generation.add() }
            await server.releaseReplies(to: "SELECT")
            let fellBack = await opened

            XCTAssertEqual(server.log.map(\.status), ["NO"], "moved on: \(movedOn)")
            XCTAssertEqual(fellBack, movedOn ? nil : .failed(.cannotConnect), "moved on: \(movedOn)")
            XCTAssertEqual(newestPages.value, movedOn ? 0 : 1, "moved on: \(movedOn)")
        }
    }

    /// The rest of what a jump can come to.
    func testAJumpSettlesAsLandedAsNothingThatRecentOrAsOvertaken() {
        let letter = MessageSummary(id: "1/5", mailboxID: Server.allMail, sender: "Sam Example",
                                    subject: "Letter 5: garden", preview: "",
                                    date: Server.newestDate, isRead: true, isFlagged: false)
        let window = MessageWindow(messages: [letter], anchorIndex: 0, reachedNewest: true,
                                   reachedOldest: true, landedOn: Server.newestDate)
        var empty = window
        empty.messages = []
        XCTAssertEqual(ListOpening.settle(.success(window), current: true), .landed)
        XCTAssertEqual(ListOpening.settle(.success(window), current: false), .superseded)
        XCTAssertEqual(ListOpening.settle(.success(nil), current: true), .nothingThatRecent)
        XCTAssertEqual(ListOpening.settle(.success(empty), current: true), .nothingThatRecent)
        XCTAssertEqual(ListOpening.settle(.success(nil), current: false), .superseded)
        XCTAssertEqual(ListOpening.settle(.failure(MailError.cannotConnect), current: true),
                       .failed(.cannotConnect))
        // What the alert says is what was caught: a refused password is
        // told as the password's, not as the connection's.
        XCTAssertEqual(ListOpening.settle(.failure(MailError.passwordNeedsUpdating), current: true),
                       .failed(.passwordNeedsUpdating))
    }
}

/// Defaults that count how often anything is written to them. The address
/// book is the only thing that writes to these.
final class CountingDefaults: UserDefaults, @unchecked Sendable {
    let writes = Counter()

    override func set(_ value: Any?, forKey defaultName: String) {
        writes.add()
        super.set(value, forKey: defaultName)
    }
}

/// What each sweep delivered, in order, from whichever task delivered it.
private final class Deliveries: @unchecked Sendable {
    private let lock = NSLock()
    private var delivered: [[Mailbox]] = []

    var all: [[Mailbox]] {
        lock.lock()
        defer { lock.unlock() }
        return delivered
    }

    func add(_ folders: [Mailbox]) {
        lock.lock()
        delivered.append(folders)
        lock.unlock()
    }
}
