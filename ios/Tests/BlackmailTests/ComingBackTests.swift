import XCTest
@testable import Blackmail

/// Picking the iPad up again: the connection probed and replaced before he
/// taps anything (`IMAPMailRepository.warmUp`), and after a long absence
/// the Inbox fetched again in the list already on screen (`Sitting`). Over
/// `ScriptedIMAPServer`, with a clock the test moves, so ninety seconds of
/// quiet cost nothing.
final class ComingBackTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "ComingBackTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var clock: Clock!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        clock = Clock()
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

    private func makeRepository(password: String? = nil) -> IMAPMailRepository {
        let clock = self.clock!
        return IMAPMailRepository(account: server.account, password: password ?? server.password,
                                  transport: server.transportFactory, recipients: book,
                                  now: { clock.now() })
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

    // MARK: - The warm-up

    /// The socket died while the iPad slept. The NOOP sent as he comes back
    /// finds it dead, and the connection is replaced there and then; the
    /// letter he opens next is a SELECT and a FETCH on the new one. The
    /// first letter used to find the dead socket itself: its FETCH written
    /// into it, the teardown, and a whole reconnect, all while he waited.
    func testTheWarmUpNOOPReplacesAResetSocketBeforeTheNextOpen() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        clock.advance(by: 91)
        await server.resetConnections()
        server.clearLog()

        await repository.warmUp()
        XCTAssertEqual(server.lostWrites.map(\.command), ["NOOP"])
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN"])
        XCTAssertEqual(server.connectionsOpened, 2)

        server.clearLog()
        let letter = try await repository.loadMessage(id: rows[0].id, mailboxID: rows[0].mailboxID)
        XCTAssertEqual(letter.subject, rows[0].subject)
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID FETCH"])
        XCTAssertEqual(server.log.map(\.connection), [2, 2])
        XCTAssertEqual(server.lostWrites, [])
        XCTAssertEqual(server.connectionsOpened, 2)
    }

    /// On a live connection the NOOP is all: one round trip, and the
    /// letter after it needs no SELECT.
    func testTheWarmUpOnALiveConnectionIsOneNOOP() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        clock.advance(by: 91)
        server.clearLog()

        await repository.warmUp()
        XCTAssertEqual(server.log.map(\.verb), ["NOOP"])
        // Just probed, so a write straight after it is not probed again.
        server.clearLog()
        try await repository.setFlagged(true, id: rows[3].id, mailboxID: rows[3].mailboxID)
        XCTAssertEqual(server.log.map(\.verb), ["UID STORE"])
    }

    /// He picks the iPad up and bins the letter still open in the pane
    /// while the warm-up's NOOP is out, and the socket turns out to be dead.
    /// The Delete probes for itself: its NOOP fails with the warm-up's, and
    /// the MOVE goes once, on the new connection. The warm-up used to count
    /// the connection as proven as its NOOP went, so the Delete skipped its
    /// probe, reached the connection after the NOOP had torn it down, and
    /// failed with "Can't connect"; a write is never sent twice, so the
    /// letter stayed in the Inbox.
    func testADeleteMadeWhileTheWarmUpNOOPIsOutGoesOnceOnTheNewConnection() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let letter = rows[0]
        clock.advance(by: 91)
        server.clearLog()

        server.holdReplies(to: "NOOP")
        let warm = Task { await repository.warmUp() }
        try await until { self.server.log.contains { $0.verb == "NOOP" } }
        let deleted = Task { try await repository.delete(letter.id, from: letter.mailboxID) }
        try await until { await repository.waitingForExchange == 1 }
        await server.resetConnections()
        await server.releaseReplies(to: "NOOP")

        try await finishing { try await deleted.value }
        await warm.value
        XCTAssertEqual(server.log.map { "\($0.connection):\($0.verb)" },
                       ["1:NOOP", "2:LOGIN", "2:NOOP", "2:SELECT", "2:UID MOVE"])
        XCTAssertEqual(server.lostWrites, [])
        XCTAssertEqual(server.connectionsOpened, 2)
        XCTAssertFalse(server.uids(in: Server.inbox).contains(uid(letter.id)))
    }

    /// The same with the socket left half open, the usual state after the
    /// network dropped it while the iPad slept: the warm-up's NOOP gets no
    /// answer and is cut off at the read deadline, and the Flag he made
    /// meanwhile still lands, once, on the new connection.
    func testAFlagMadeWhileTheWarmUpNOOPStallsOnAHalfOpenSocketStillLands() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let letter = rows[3]
        XCTAssertFalse(letter.isFlagged)
        clock.advance(by: 91)
        server.timeout = .milliseconds(40)
        server.clearLog()

        server.holdReplies(to: "NOOP")
        let warm = Task { await repository.warmUp() }
        try await until { self.server.log.contains { $0.verb == "NOOP" } }
        let flagged = Task {
            try await repository.setFlagged(true, id: letter.id, mailboxID: letter.mailboxID)
        }
        try await until { await repository.waitingForExchange == 1 }
        try await until { self.server.log.contains { $0.verb == "LOGIN" } }
        await server.releaseReplies(to: "NOOP")

        try await finishing { try await flagged.value }
        await warm.value
        XCTAssertEqual(server.log.map { "\($0.connection):\($0.verb)" },
                       ["1:NOOP", "2:LOGIN", "2:NOOP", "2:SELECT", "2:UID STORE"])
        XCTAssertTrue(server.flags(uid: uid(letter.id), in: Server.inbox).contains("\\Flagged"))
    }

    /// A short interruption sends nothing, whatever state the socket is in:
    /// the connection has not been quiet long enough to have died of it.
    /// Nor does a return to no connection at all, a launch that could not
    /// connect or a password already refused: that is not the warm-up's to
    /// try again.
    func testTheWarmUpSendsNothingAfterAShortQuietOrWithNoConnection() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        clock.advance(by: 89)
        server.clearLog()
        await repository.warmUp()
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(server.lostWrites, [])

        server = ScriptedIMAPServer()
        let refused = makeRepository(password: "not-the-password")
        _ = try? await refused.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN"])
        clock.advance(by: 3_600)
        await refused.warmUp()
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN"])
        XCTAssertEqual(server.connectionsOpened, 1)

        let never = makeRepository()
        await never.warmUp()
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// The password was refused at the warm-up, and Gmail took it again a
    /// moment later, as it now and then refuses a correct app password. For
    /// a minute every call is answered with the refusal, without sending
    /// the password again. After that a call is him trying again, and a
    /// Refresh logs in and fetches the page, where the refusal used to stand
    /// until he next came back to the app, with nothing to tell him so.
    func testAPasswordRefusedAtTheWarmUpStandsForAMinuteOnly() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        clock.advance(by: 91)
        await server.resetConnections()
        server.passwordRevoked = true
        server.clearLog()

        await repository.warmUp()
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN"])
        server.passwordRevoked = false

        clock.advance(by: 30)
        do {
            _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
            XCTFail("the refusal still stands")
        } catch {
            XCTAssertEqual(error as? MailError, .passwordNeedsUpdating)
        }
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN"])

        clock.advance(by: 31)
        let page = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        XCTAssertEqual(page.count, 10)
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN", "LOGIN", "SELECT", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(server.log.map(\.status), ["NO", "OK", "OK", "OK", "OK"])
    }

    /// The password was revoked while he was away. The warm-up's new
    /// connection is refused, and that is the answer to the letter he then
    /// taps, both its FETCH and its read mark, without the password going
    /// again. The next time he comes back it is his to try again, once.
    func testAPasswordRefusedAtTheWarmUpIsNotSentAgainByTheFirstTap() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        clock.advance(by: 91)
        await server.resetConnections()
        server.passwordRevoked = true
        server.clearLog()

        await repository.warmUp()
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN"])
        XCTAssertEqual(server.log.first?.status, "NO")

        let letter = rows[0]
        async let opened: Message = repository.loadMessage(id: letter.id, mailboxID: letter.mailboxID)
        async let read: Void = repository.setRead(true, id: letter.id, mailboxID: letter.mailboxID)
        var failures: [MailError?] = []
        do { _ = try await opened } catch { failures.append(error as? MailError) }
        do { try await read } catch { failures.append(error as? MailError) }
        XCTAssertEqual(failures, [.passwordNeedsUpdating, .passwordNeedsUpdating])
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN"])

        // Back again later: no connection, so no warm-up; his tap tries once.
        clock.advance(by: 600)
        await repository.warmUp()
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN"])
        do {
            _ = try await repository.loadMessage(id: letter.id, mailboxID: letter.mailboxID)
            XCTFail("the password is still refused")
        } catch {
            XCTAssertEqual(error as? MailError, .passwordNeedsUpdating)
        }
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN", "LOGIN"])
        XCTAssertFalse(server.log.contains { $0.verb == "LOGOUT" })
    }

    /// The warm-up's NOOP waits in the background line: a letter he taps
    /// while it is still waiting for the connection goes first.
    func testALetterTappedDuringTheWarmUpGoesAheadOfItsNOOP() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        server.clearLog()

        server.holdReplies(to: "LIST")
        let sweep = Task { try await repository.listMailboxes() }
        try await until { self.server.log.contains { $0.verb == "LIST" } }
        clock.advance(by: 91)
        let warm = Task { await repository.warmUp() }
        try await until { await repository.waitingForExchange == 1 }
        let open = Task { try await repository.loadMessage(id: rows[0].id, mailboxID: rows[0].mailboxID) }
        try await until { await repository.waitingForExchange == 2 }
        await server.releaseReplies(to: "LIST")

        _ = try await finishing { try await open.value }
        await warm.value
        _ = try await finishing { try await sweep.value }
        XCTAssertEqual(Array(server.log.map(\.verb).prefix(3)), ["LIST", "UID FETCH", "NOOP"])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    // MARK: - Back after a long absence

    func testWhatComingBackDoesToTheList() {
        let long = Sitting.awayBeforeReturningToInbox + 1
        XCTAssertEqual(Sitting.onReturn(after: 60, showingInbox: true, sheetOpen: false), .stay)
        XCTAssertEqual(Sitting.onReturn(after: 60, showingInbox: false, sheetOpen: false), .stay)
        XCTAssertEqual(Sitting.onReturn(after: Sitting.awayBeforeReturningToInbox,
                                        showingInbox: false, sheetOpen: false), .stay)
        // The Inbox already showing is fetched again where it is; it used
        // to be replaced by a new, empty list.
        XCTAssertEqual(Sitting.onReturn(after: long, showingInbox: true, sheetOpen: false),
                       .refreshInbox)
        XCTAssertEqual(Sitting.onReturn(after: long, showingInbox: false, sheetOpen: false),
                       .openInbox)
        // Never over a sheet: a half-written letter is left alone.
        XCTAssertEqual(Sitting.onReturn(after: long, showingInbox: true, sheetOpen: true), .stay)
        XCTAssertEqual(Sitting.onReturn(after: long, showingInbox: false, sheetOpen: true), .stay)
    }

    /// Back after a long absence to the Inbox: its first page, the preview
    /// of the one letter that arrived meanwhile and of nothing else, and
    /// only then the folder counts. The previews already on screen go
    /// across by id, where every one used to be blanked and fetched again,
    /// and the counts used to be asked for at the same moment as the page.
    func testComingBackToTheInboxFetchesThePageThenOnlyNewPreviewsThenTheCounts() async throws {
        let repository = makeRepository()
        let before = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let previews = try await repository.previews(for: before.map(\.id), in: "inbox")
        // The list on screen, as `MessageListViewController` holds it: the
        // page, and every preview drawn.
        let list = await ListLetters()
        _ = await list.fetchedAfresh(before)
        await list.apply(previews: previews)
        let shown = await list.folder
        XCTAssertTrue(shown.allSatisfy { !$0.preview.isEmpty })
        let arrived = server.deliver(Server.Letter(from: Server.sam, to: [Server.owner],
                                                   subject: "While you were out",
                                                   date: Server.newestDate.addingTimeInterval(3_600),
                                                   text: "Came in while the iPad was asleep.\r\n",
                                                   messageID: "<while-away@example.com>"),
                                     to: [Server.inbox, Server.allMail])
        let newUID = try XCTUnwrap(arrived[Server.inbox])
        server.clearLog()
        let counted = Counter()

        // What `returnToNewest` does, through the list's `reload`: the page,
        // the list's own merge of it, and the previews that merge says are
        // missing.
        await Sitting.refresh(
            newest: {
                guard let fetched = try? await repository.listMessages(in: "inbox", beforeUID: nil,
                                                                       limit: 50) else { return false }
                let unpreviewed = list.fetchedAfresh(fetched)
                _ = try? await repository.previews(for: unpreviewed.map(\.id), in: "inbox")
                return true
            },
            counts: {
                counted.add()
                Task { _ = try? await repository.listMailboxes() }
            })
        try await until { self.server.log.filter { $0.verb == "STATUS" }.count == 7 }
        let page = await list.folder

        XCTAssertEqual(page.first?.subject, "While you were out")
        XCTAssertEqual(page.filter { $0.preview.isEmpty }.map(\.subject), ["While you were out"])
        XCTAssertEqual(server.log.map(\.verb),
                       ["UID SEARCH", "UID FETCH", "UID FETCH", "LIST"]
                        + Array(repeating: "STATUS", count: 7))
        XCTAssertTrue(server.log[2].command.hasPrefix("UID FETCH \(newUID) (UID BODY.PEEK["),
                      server.log[2].command)
        XCTAssertEqual(counted.value, 1)
    }

    /// Back to another folder: the Inbox opens as a new list that fetches
    /// its own first page and says afterwards whether it came. The counts
    /// follow `refresh`'s rule: once the page has come, and not at all if
    /// it could not be fetched.
    func testBackFromAnotherFolderTheCountsWaitForTheInboxPage() async {
        let counted = Counter()
        await Sitting.afterNewest(came: false, counts: { counted.add() })
        XCTAssertEqual(counted.value, 0)
        await Sitting.afterNewest(came: true, counts: { counted.add() })
        XCTAssertEqual(counted.value, 1)
    }

    /// Back to a password revoked while he was away: the page cannot be
    /// fetched, and the counts are not asked for, which would connect again
    /// straight after and send the refused password a second time.
    func testComingBackToARefusedPasswordSendsItOnce() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        await server.resetConnections()
        server.passwordRevoked = true
        server.clearLog()
        let counted = Counter()

        await Sitting.refresh(
            newest: {
                (try? await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)) != nil
            },
            counts: {
                counted.add()
                Task { _ = try? await repository.listMailboxes() }
            })
        try await Task.sleep(for: .milliseconds(10))

        XCTAssertEqual(counted.value, 0)
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN"])
        XCTAssertEqual(server.connectionsOpened, 2)
    }
}

/// A clock a test moves by hand.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_790_000_000)

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current += seconds
        lock.unlock()
    }
}
