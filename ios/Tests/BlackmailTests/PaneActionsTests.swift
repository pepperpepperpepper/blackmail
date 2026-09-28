import XCTest
@testable import Blackmail

/// Delete, Move and Flag from the reading pane: what each sends, and what it
/// does to the list beside the pane and the folder counts. Over
/// `ScriptedIMAPServer` through the shipping repository, with the list's
/// own letters, `ListLetters`, which `MessageListViewController` draws.
///
/// All three used to reload the whole list and sweep every folder's count:
/// about fourteen commands, and every preview again, for one letter binned.
final class PaneActionsTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "PaneActionsTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        server = nil
        book = nil
        super.tearDown()
    }

    private func makeRepository() -> IMAPMailRepository {
        IMAPMailRepository(account: server.account, password: server.password,
                           transport: server.transportFactory, recipients: book)
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

    /// The counts' sweeps as the folder pane runs them, counted.
    @MainActor
    private func makeSweeps(_ repository: IMAPMailRepository, counted: Counter) -> SweepCoalescer {
        SweepCoalescer {
            counted.add()
            _ = try? await repository.listMailboxes()
        }
    }

    private static let sweep = ["LIST"] + Array(repeating: "STATUS", count: 7)

    /// The list's letters as `MessageListViewController` holds them: the
    /// folder's first page, fetched from the top, and a search's hits over
    /// it if there are any.
    @MainActor
    private func makeList(folder: [MessageSummary],
                          results: [MessageSummary]? = nil) -> (ListLetters, CountChanges) {
        let list = ListLetters()
        let counts = CountChanges()
        list.onUnreadCountChanged = { counts.record($0, $1) }
        _ = list.fetchedAfresh(folder)
        if let results { list.showResults(results) }
        return (list, counts)
    }

    // MARK: - What each action does

    func testWhatEachActionDoesToTheListAndTheCounts() {
        typealias Effect = PaneActions.Effect
        let trash = Mailbox(id: Server.trash, name: "Trash", unreadCount: 0, role: .trash)
        let spam = Mailbox(id: Server.spam, name: "Spam", unreadCount: 0, role: .junk)
        let sent = Mailbox(id: Server.sent, name: "Sent Mail", unreadCount: 0, role: .sent)
        let archive = Mailbox(id: Server.allMail, name: "All Mail", unreadCount: 0, role: .archive)
        let binned = Effect(removesRow: true, leavesEveryFolder: true, alsoFiledIn: nil,
                            sweepsIfUnread: true)

        XCTAssertEqual(PaneActions.effect(of: .delete, onLetterIn: .inbox), binned)
        XCTAssertEqual(PaneActions.effect(of: .delete, onLetterIn: .archive), binned)
        XCTAssertEqual(PaneActions.effect(of: .delete, onLetterIn: .junk), binned)
        XCTAssertEqual(PaneActions.effect(of: .delete, onLetterIn: nil), binned)
        // Inside Trash the one off Trash's count is the whole change.
        XCTAssertEqual(PaneActions.effect(of: .delete, onLetterIn: .trash),
                       Effect(removesRow: true, leavesEveryFolder: true, alsoFiledIn: nil,
                              sweepsIfUnread: false))
        // Moved to Trash or Spam is binned by another name, from anywhere.
        for role: Mailbox.Role? in [.inbox, .archive, .trash, nil] {
            XCTAssertEqual(PaneActions.effect(of: .move(to: trash), onLetterIn: role), binned)
            XCTAssertEqual(PaneActions.effect(of: .move(to: spam), onLetterIn: role), binned)
        }
        // Moved out of All Mail it is still in All Mail.
        XCTAssertEqual(PaneActions.effect(of: .move(to: sent), onLetterIn: .archive),
                       Effect(removesRow: false, leavesEveryFolder: false,
                              alsoFiledIn: Server.sent, sweepsIfUnread: true))
        for role: Mailbox.Role? in [.inbox, .sent, .trash, .junk, nil] {
            XCTAssertEqual(PaneActions.effect(of: .move(to: sent), onLetterIn: role),
                           Effect(removesRow: true, leavesEveryFolder: false, alsoFiledIn: nil,
                                  sweepsIfUnread: true))
        }
        XCTAssertEqual(PaneActions.effect(of: .move(to: archive), onLetterIn: .inbox).removesRow, true)
        for flagged in [true, false] {
            XCTAssertEqual(PaneActions.effect(of: .flag(flagged), onLetterIn: .inbox),
                           Effect(removesRow: false, leavesEveryFolder: false, alsoFiledIn: nil,
                                  sweepsIfUnread: true))
        }
    }

    func testTheFolderALetterWasListedFromIsFoundInEitherSpelling() {
        let folders = [Mailbox(id: "inbox", name: "Inbox", unreadCount: 0, role: .inbox),
                       Mailbox(id: Server.inbox, name: "INBOX", unreadCount: 0, role: .inbox),
                       Mailbox(id: Server.allMail, name: "All Mail", unreadCount: 0, role: .archive),
                       Mailbox(id: Server.trash, name: "Trash", unreadCount: 0, role: .trash)]
        XCTAssertEqual(folders.role(of: "inbox"), .inbox)
        XCTAssertEqual(folders.role(of: "INBOX"), .inbox)
        XCTAssertEqual(folders.role(of: Server.allMail), .archive)
        XCTAssertEqual(folders.role(of: Server.trash), .trash)
        XCTAssertNil(folders.role(of: "Receipts"))
        // No folders listed yet: a role word still says what it is.
        XCTAssertEqual([Mailbox]().role(of: "trash"), .trash)
        XCTAssertNil([Mailbox]().role(of: Server.trash))
    }

    // MARK: - Delete

    /// A read letter binned from the reading pane: its UID MOVE and nothing
    /// else. No SEARCH ALL, no page FETCH, no previews, no LIST or STATUS.
    /// The row goes at the tap, before the server has answered.
    func testDeleteFromThePaneSendsMoveAndNothingElse() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        _ = try await repository.previews(for: rows.map(\.id), in: "inbox")
        let letter = rows[10]
        XCTAssertTrue(letter.isRead)
        let (list, counts) = await makeList(folder: rows)
        let sweeps = Counter()
        let coalescer = await makeSweeps(repository, counted: sweeps)
        server.clearLog()

        server.holdReplies(to: "UID MOVE")
        let deleted = Task {
            await PaneActions.run(.delete, on: letter, inFolderWithRole: .inbox, list: list,
                                  repository: repository, requestSweep: { coalescer.request() })
        }
        try await until { self.server.log.contains { $0.verb == "UID MOVE" } }
        let atTheTap = await list.shown.map(\.id)
        XCTAssertFalse(atTheTap.contains(letter.id))
        XCTAssertEqual(atTheTap.count, rows.count - 1)
        await server.releaseReplies(to: "UID MOVE")
        let done = try await finishing { await deleted.value }
        await coalescer.idle()

        XCTAssertTrue(done)
        XCTAssertEqual(server.log.map(\.command),
                       ["UID MOVE \(uid(letter.id)) \"\(Server.trash)\""])
        XCTAssertEqual(sweeps.value, 0)
        let billed = await counts.billed
        XCTAssertEqual(billed, [])
        let after = await list.shown.map(\.id)
        XCTAssertEqual(after, atTheTap)
        XCTAssertFalse(server.uids(in: Server.inbox).contains(uid(letter.id)))
    }

    /// Binned while still unread, it takes one off every folder it was
    /// counted in, once, and the counts are swept for Trash's. Asked about
    /// again, it is not billed again.
    func testAnUnreadLetterBinnedFromThePaneIsBilledOnceAndTheCountsSwept() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = rows[0]
        XCTAssertFalse(letter.isRead)
        XCTAssertEqual(letter.countedFolderIDs, [Server.inbox, Server.allMail])
        let (list, counts) = await makeList(folder: rows)
        let sweeps = Counter()
        let coalescer = await makeSweeps(repository, counted: sweeps)
        server.clearLog()

        let done = await PaneActions.run(.delete, on: letter, inFolderWithRole: .inbox, list: list,
                                         repository: repository,
                                         requestSweep: { coalescer.request() })
        await coalescer.idle()

        XCTAssertTrue(done)
        XCTAssertEqual(server.log.map(\.verb), ["UID MOVE"] + Self.sweep)
        XCTAssertEqual(sweeps.value, 1)
        var billed = await counts.billed
        XCTAssertEqual(billed, [[Server.inbox, Server.allMail]])
        await list.removalLanded(letter, fromEveryFolder: true)
        billed = await counts.billed
        XCTAssertEqual(billed, [[Server.inbox, Server.allMail]])
    }

    /// Opened, so marked read, and then binned: the read took the one off,
    /// and the Delete takes nothing more and sweeps for nothing. The pane's
    /// copy still says unread, as it does for every letter just opened: the
    /// list marks it read after handing the pane the row.
    func testALetterReadAndThenBinnedIsBilledOnlyForTheRead() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = rows[1]
        XCTAssertFalse(letter.isRead)
        let (list, counts) = await makeList(folder: rows)
        let sweeps = Counter()
        let coalescer = await makeSweeps(repository, counted: sweeps)
        try await repository.setRead(true, id: letter.id, mailboxID: letter.mailboxID)
        // What the list does at the tap, and once the read mark has landed.
        await list.setRead(letter.id, read: true)
        await list.read(letter)
        server.clearLog()

        let done = await PaneActions.run(.delete, on: letter, inFolderWithRole: .inbox, list: list,
                                         repository: repository,
                                         requestSweep: { coalescer.request() })
        await coalescer.idle()

        XCTAssertTrue(done)
        XCTAssertEqual(server.log.map(\.verb), ["UID MOVE"])
        XCTAssertEqual(sweeps.value, 0)
        let billed = await counts.billed
        XCTAssertEqual(billed, [[Server.inbox, Server.allMail]])
    }

    /// Opened, so its dot went at the tap, and binned while the read mark
    /// was on its way; the read mark then failed, and the list put the dot
    /// back while the MOVE was still out. The letter left the Inbox unread,
    /// so it is billed once when the MOVE lands and the counts are swept.
    /// Whether it was unread is read off the list then, not at the tap,
    /// when the dot had gone: read at the tap, it was billed for nothing
    /// and the counts stayed one high.
    func testWhetherABinnedLetterWasUnreadIsReadOffTheListWhenTheMoveLands() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = rows[1]
        XCTAssertFalse(letter.isRead)
        let (list, counts) = await makeList(folder: rows)
        let sweeps = Counter()
        let coalescer = await makeSweeps(repository, counted: sweeps)
        await list.setRead(letter.id, read: true)
        server.clearLog()

        server.holdReplies(to: "UID MOVE")
        let deleted = Task {
            await PaneActions.run(.delete, on: letter, inFolderWithRole: .inbox, list: list,
                                  repository: repository, requestSweep: { coalescer.request() })
        }
        try await until { self.server.log.contains { $0.verb == "UID MOVE" } }
        await list.setRead(letter.id, read: false)
        await server.releaseReplies(to: "UID MOVE")
        let done = try await finishing { await deleted.value }
        await coalescer.idle()

        XCTAssertTrue(done)
        let billed = await counts.billed
        XCTAssertEqual(billed, [[Server.inbox, Server.allMail]])
        XCTAssertEqual(sweeps.value, 1)
        XCTAssertEqual(server.log.map(\.verb), ["UID MOVE"] + Self.sweep)
    }

    /// Delete inside Trash sets `\Deleted` and moves nothing. The row goes,
    /// an unread letter comes off Trash's count, and that is the whole
    /// change, so nothing is swept.
    func testDeleteInsideTrashOnlySetsDeletedAndSweepsNothing() async throws {
        let arrived = server.deliver(Server.Letter(from: Server.carlo, to: [Server.owner],
                                                   subject: "Binned unread",
                                                   date: Server.newestDate,
                                                   text: "Never read.\r\n",
                                                   messageID: "<binned-unread@example.org>"),
                                     to: [Server.trash])
        let repository = makeRepository()
        _ = try await repository.folders()
        let rows = try await repository.listMessages(in: Server.trash, beforeUID: nil, limit: 50)
        let letter = try XCTUnwrap(rows.first { $0.subject == "Binned unread" })
        XCTAssertFalse(letter.isRead)
        let (list, counts) = await makeList(folder: rows)
        let sweeps = Counter()
        let coalescer = await makeSweeps(repository, counted: sweeps)
        server.clearLog()

        let done = await PaneActions.run(.delete, on: letter, inFolderWithRole: .trash, list: list,
                                         repository: repository,
                                         requestSweep: { coalescer.request() })
        await coalescer.idle()

        XCTAssertTrue(done)
        XCTAssertEqual(server.log.map(\.command),
                       ["UID STORE \(try XCTUnwrap(arrived[Server.trash])) +FLAGS.SILENT (\\Deleted)"])
        XCTAssertEqual(sweeps.value, 0)
        let billed = await counts.billed
        XCTAssertEqual(billed, [[Server.trash]])
        let shown = await list.shown.map(\.id)
        XCTAssertFalse(shown.contains(letter.id))
    }

    /// The server refuses: the row comes back, nothing is billed, nothing
    /// swept, and the MOVE went once, into the dead socket, and was not
    /// sent again on a new connection.
    func testADeleteTheServerRefusesPutsTheRowBack() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = rows[0]
        let (list, counts) = await makeList(folder: rows)
        let sweeps = Counter()
        let coalescer = await makeSweeps(repository, counted: sweeps)
        await server.resetConnections()

        let done = await PaneActions.run(.delete, on: letter, inFolderWithRole: .inbox, list: list,
                                         repository: repository,
                                         requestSweep: { coalescer.request() })
        await coalescer.idle()

        XCTAssertFalse(done)
        let shown = await list.shown.map(\.id)
        XCTAssertEqual(shown, rows.map(\.id))
        let billed = await counts.billed
        XCTAssertEqual(billed, [])
        XCTAssertEqual(sweeps.value, 0)
        XCTAssertEqual(server.lostWrites.map(\.verb), ["UID MOVE"])
        XCTAssertEqual(server.connectionsOpened, 1)
        XCTAssertTrue(server.uids(in: Server.inbox).contains(uid(letter.id)))
    }

    /// An All Mailboxes hit binned from the pane, whose letter is also a
    /// row of the Inbox under it: both go, and it is billed once. Left in
    /// the Inbox's rows it would come back when the search is cancelled,
    /// and open empty, since the Inbox no longer holds that UID.
    func testAHitBinnedFromASearchTakesTheSameLetterOffTheFolderUnderIt() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let hits = try await repository.search(in: "inbox", query: "Letter 118", scope: .allMailboxes,
                                               beforeUID: nil, limit: 50)
        let hit = try XCTUnwrap(hits.first { $0.mailboxID == Server.allMail })
        let twin = try XCTUnwrap(rows.first { $0.subject == hit.subject })
        XCTAssertNotEqual(hit.id, twin.id)
        XCTAssertFalse(hit.isRead)
        let (list, counts) = await makeList(folder: rows, results: hits)
        server.clearLog()

        let done = await PaneActions.run(.delete, on: hit, inFolderWithRole: .archive, list: list,
                                         repository: repository, requestSweep: {})

        XCTAssertTrue(done)
        let shown = await list.shown.map(\.id)
        XCTAssertFalse(shown.contains(hit.id))
        await list.endSearch()
        let folder = await list.shown.map(\.id)
        XCTAssertFalse(folder.contains(twin.id))
        XCTAssertEqual(folder.count, rows.count - 1)
        let billed = await counts.billed
        XCTAssertEqual(billed.count, 1)
        XCTAssertFalse(server.uids(in: Server.inbox).contains(uid(twin.id)))
        XCTAssertFalse(server.uids(in: Server.allMail).contains(uid(hit.id)))
    }

    // MARK: - Move

    /// Moved out of All Mail, a letter is still in All Mail, and its row
    /// stays, now counted in the folder it went to as well. Unread, the
    /// counts are swept for that folder's.
    func testMoveOutOfAllMailKeepsTheRow() async throws {
        let arrived = server.deliver(Server.Letter(from: Server.jane, to: [Server.owner],
                                                   subject: "Archived unread",
                                                   date: Server.newestDate.addingTimeInterval(60),
                                                   text: "Filed without reading.\r\n",
                                                   messageID: "<archived@example.com>"),
                                     to: [Server.allMail])
        let repository = makeRepository()
        _ = try await repository.folders()
        let rows = try await repository.listMessages(in: Server.allMail, beforeUID: nil, limit: 50)
        let letter = try XCTUnwrap(rows.first { $0.subject == "Archived unread" })
        let (list, counts) = await makeList(folder: rows)
        let sweeps = Counter()
        let coalescer = await makeSweeps(repository, counted: sweeps)
        let inbox = Mailbox(id: Server.inbox, name: "Inbox", unreadCount: 0, role: .inbox)
        server.clearLog()

        let done = await PaneActions.run(.move(to: inbox), on: letter, inFolderWithRole: .archive,
                                         list: list, repository: repository,
                                         requestSweep: { coalescer.request() })
        await coalescer.idle()

        XCTAssertTrue(done)
        XCTAssertEqual(server.log.map(\.verb), ["UID MOVE"] + Self.sweep)
        XCTAssertEqual(sweeps.value, 1)
        let shown = await list.shown.map(\.id)
        XCTAssertEqual(shown, rows.map(\.id))
        let kept = await list.letter(letter.id)
        XCTAssertEqual(kept?.countedFolderIDs, [Server.allMail, Server.inbox])
        let billed = await counts.billed
        XCTAssertEqual(billed, [])
        XCTAssertTrue(server.uids(in: Server.allMail).contains(try XCTUnwrap(arrived[Server.allMail])))
        XCTAssertEqual(server.letter(uid: server.uids(in: Server.inbox).last!, in: Server.inbox)?.subject,
                       "Archived unread")
    }

    /// Moved out of the Inbox, a read letter's row goes and nothing else
    /// is sent: no count can have changed.
    func testMovingAReadLetterSendsTheMoveAlone() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = rows[20]
        XCTAssertTrue(letter.isRead)
        let (list, counts) = await makeList(folder: rows)
        let sweeps = Counter()
        let coalescer = await makeSweeps(repository, counted: sweeps)
        let sent = Mailbox(id: Server.sent, name: "Sent Mail", unreadCount: 0, role: .sent)
        server.clearLog()

        let done = await PaneActions.run(.move(to: sent), on: letter, inFolderWithRole: .inbox,
                                         list: list, repository: repository,
                                         requestSweep: { coalescer.request() })
        await coalescer.idle()

        XCTAssertTrue(done)
        XCTAssertEqual(server.log.map(\.verb), ["UID MOVE"])
        XCTAssertEqual(sweeps.value, 0)
        let shown = await list.shown.map(\.id)
        XCTAssertFalse(shown.contains(letter.id))
        let billed = await counts.billed
        XCTAssertEqual(billed, [])
    }

    // MARK: - Flag

    /// Flagged at the tap, before the server has answered; one STORE and
    /// nothing else for a read letter. An unread one's flag changes
    /// Starred's count, so that one is swept.
    func testFlagFromThePanePatchesTheRowAtOnceAndSendsTheStoreAlone() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = rows[12]
        XCTAssertTrue(letter.isRead)
        XCTAssertFalse(letter.isFlagged)
        let (list, _) = await makeList(folder: rows)
        let sweeps = Counter()
        let coalescer = await makeSweeps(repository, counted: sweeps)
        server.clearLog()

        server.holdReplies(to: "UID STORE")
        let flagged = Task {
            await PaneActions.run(.flag(true), on: letter, inFolderWithRole: .inbox, list: list,
                                  repository: repository, requestSweep: { coalescer.request() })
        }
        try await until { self.server.log.contains { $0.verb == "UID STORE" } }
        let atTheTap = await list.letter(letter.id)
        XCTAssertEqual(atTheTap?.isFlagged, true)
        await server.releaseReplies(to: "UID STORE")
        let done = try await finishing { await flagged.value }
        await coalescer.idle()

        XCTAssertTrue(done)
        XCTAssertEqual(server.log.map(\.command),
                       ["UID STORE \(uid(letter.id)) +FLAGS.SILENT (\\Flagged)"])
        XCTAssertEqual(sweeps.value, 0)

        let unread = rows[0]
        server.clearLog()
        let alsoDone = await PaneActions.run(.flag(true), on: unread, inFolderWithRole: .inbox,
                                             list: list, repository: repository,
                                             requestSweep: { coalescer.request() })
        await coalescer.idle()
        XCTAssertTrue(alsoDone)
        XCTAssertEqual(server.log.map(\.verb), ["UID STORE"] + Self.sweep)
        XCTAssertEqual(sweeps.value, 1)
    }

    /// A flag STORE that fails puts the flag back. It used to be sent with
    /// `try?`, so the row kept a flag Gmail did not have.
    func testAFlagTheServerRefusesIsPutBack() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = rows[12]
        let (list, _) = await makeList(folder: rows)
        await server.resetConnections()

        let done = await PaneActions.run(.flag(true), on: letter, inFolderWithRole: .inbox,
                                         list: list, repository: repository, requestSweep: {})

        XCTAssertFalse(done)
        let after = await list.letter(letter.id)
        XCTAssertEqual(after?.isFlagged, false)
        XCTAssertEqual(server.lostWrites.map(\.verb), ["UID STORE"])
        XCTAssertFalse(server.flags(uid: uid(letter.id), in: Server.inbox).contains("\\Flagged"))
    }

    /// Flagged from an All Mailboxes hit, the letter's row in the Inbox
    /// under the search is flagged with it, so cancelling the search, which
    /// puts the Inbox's rows back without a round trip, shows the flag.
    /// Before the pane's Flag edited the list in place, its reload fetched
    /// the Inbox again. A flag the server refuses comes off both.
    func testAFlagOnAHitShowsOnTheSameLetterInTheFolderUnderIt() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let hits = try await repository.search(in: "inbox", query: "Letter 112",
                                               scope: .allMailboxes, beforeUID: nil, limit: 50)
        let hit = try XCTUnwrap(hits.first { $0.mailboxID == Server.allMail })
        let twin = try XCTUnwrap(rows.first { $0.subject == hit.subject })
        XCTAssertNotEqual(hit.id, twin.id)
        XCTAssertFalse(twin.isFlagged)
        let (list, _) = await makeList(folder: rows, results: hits)
        server.clearLog()

        let done = await PaneActions.run(.flag(true), on: hit, inFolderWithRole: .archive,
                                         list: list, repository: repository, requestSweep: {})
        XCTAssertTrue(done)
        XCTAssertEqual(server.log.map(\.verb), ["UID STORE"])
        await list.endSearch()
        let inboxRow = await list.letter(twin.id)
        XCTAssertEqual(inboxRow?.isFlagged, true)
        XCTAssertTrue(server.flags(uid: uid(twin.id), in: Server.inbox).contains("\\Flagged"))

        let others = try await repository.search(in: "inbox", query: "Letter 113",
                                                 scope: .allMailboxes, beforeUID: nil, limit: 50)
        let other = try XCTUnwrap(others.first { $0.mailboxID == Server.allMail })
        let otherTwin = try XCTUnwrap(rows.first { $0.subject == other.subject })
        await list.showResults(others)
        await server.resetConnections()
        let refused = await PaneActions.run(.flag(true), on: other, inFolderWithRole: .archive,
                                            list: list, repository: repository, requestSweep: {})
        XCTAssertFalse(refused)
        let hitAfter = await list.letter(other.id)
        XCTAssertEqual(hitAfter?.isFlagged, false)
        let twinAfter = await list.letter(otherTwin.id)
        XCTAssertEqual(twinAfter?.isFlagged, false)
    }

    // MARK: - The rules underneath

    func testRemovedLettersAreHiddenUntilPutBackOrTheListIsFetchedAgain() {
        let letters = (1...5).map { summary(id: "7/\($0)") }
        var removed = RemovedLetters()
        XCTAssertEqual(removed.remaining(letters).map(\.id), letters.map(\.id))

        removed.take("7/2", with: ["9/2"])
        XCTAssertEqual(removed.remaining(letters).map(\.id), ["7/1", "7/3", "7/4", "7/5"])
        XCTAssertTrue(removed.hides("9/2"))
        removed.putBack("7/2")
        XCTAssertEqual(removed.remaining(letters).map(\.id), letters.map(\.id))
        XCTAssertFalse(removed.hides("9/2"))

        removed.take("7/3")
        removed.take("7/4")
        removed.land("7/3")
        // A fetch afresh is the server's say: landed removals are not hidden
        // any more, one still on its way is.
        removed.listReplaced()
        XCTAssertEqual(removed.remaining(letters).map(\.id), ["7/1", "7/2", "7/3", "7/5"])
        removed.land("7/4")
        XCTAssertEqual(removed.remaining(letters).map(\.id), ["7/1", "7/2", "7/3", "7/5"])
        // Landing something never taken is nothing.
        removed.land("7/1")
        XCTAssertEqual(removed.remaining(letters).map(\.id), ["7/1", "7/2", "7/3", "7/5"])
    }

    /// A letter binned from the bottom of the list is hidden, not cut out,
    /// so the next page is still asked for from the last letter the last
    /// page gave, and comes whole. Cut out, the cursor would move up to a
    /// letter already paged past: a search's next page would be replayed
    /// from there, binned hit and all, and a folder's would ask the server
    /// again for the UID it had just moved away.
    func testALetterBinnedFromTheBottomStillMarksWherePagingHasGot() async throws {
        let repository = makeRepository()
        let first = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let (list, _) = await makeList(folder: first)
        let bottom = try XCTUnwrap(first.last)
        let done = await PaneActions.run(.delete, on: bottom, inFolderWithRole: .inbox, list: list,
                                         repository: repository, requestSweep: {})
        XCTAssertTrue(done)
        let shown = await list.shown.map(\.id)
        XCTAssertEqual(shown, first.dropLast().map(\.id))

        let cursor = await list.cursor
        XCTAssertEqual(cursor, bottom.id)
        server.clearLog()
        let next = try await repository.listMessages(in: "inbox", beforeUID: cursor, limit: 10)
        XCTAssertEqual(next.count, 10)
        XCTAssertEqual(server.log.map(\.verb), ["UID FETCH"])
        _ = await list.appendPage(next, toResults: false)
        let paged = await list.shown.map(\.id)
        XCTAssertEqual(paged, first.dropLast().map(\.id) + next.map(\.id))
    }

    // MARK: - Paging past a letter binned further down

    /// Pages the folder down from where the list has got, as `loadNextPage`
    /// does, a page at a time from the list's cursor, until a page comes
    /// back short, which the list reads as the end of the folder. Returns
    /// how many of the folder's letters the list then holds.
    private func pageToTheEnd(_ list: ListLetters, _ repository: IMAPMailRepository,
                              pageSize: Int) async throws -> Int {
        while true {
            let cursor = await list.cursor
            let page = try await repository.listMessages(in: "inbox", beforeUID: cursor,
                                                         limit: pageSize)
            _ = await list.appendPage(page, toResults: false)
            if page.count < pageSize { break }
        }
        return await list.folder.count
    }

    /// A search hit in the folder, below the pages loaded so far, binned
    /// from the pane. Its UID is still in the snapshot the folder pages
    /// through, and the page that would have held it used to come back one
    /// short, which the list took for the end of the folder: after
    /// cancelling the search, everything older than it was out of reach
    /// until the next Refresh. Before the pane's Delete edited the list in
    /// place, its reload read the snapshot again.
    func testALetterBinnedFromASearchBelowTheLoadedPagesDoesNotEndTheFolder() async throws {
        let repository = makeRepository()
        let first = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let hits = try await repository.search(in: "inbox", query: "Letter 60",
                                               scope: .currentMailbox, beforeUID: nil, limit: 10)
        let hit = try XCTUnwrap(hits.first { $0.subject.hasPrefix("Letter 60:") })
        XCTAssertFalse(first.contains { $0.id == hit.id })
        let (list, _) = await makeList(folder: first, results: hits)

        let done = await PaneActions.run(.delete, on: hit, inFolderWithRole: .inbox, list: list,
                                         repository: repository, requestSweep: {})
        XCTAssertTrue(done)
        await list.endSearch()

        let paged = try await pageToTheEnd(list, repository, pageSize: 10)
        XCTAssertFalse(server.uids(in: Server.inbox).contains(uid(hit.id)))
        XCTAssertEqual(paged, server.uids(in: Server.inbox).count)
    }

    /// The same from All Mailboxes: the hit binned is All Mail's copy, and
    /// the Inbox's copy of the letter, below its loaded pages, goes with it.
    func testAnAllMailboxesHitBinnedWhoseInboxCopyIsNotLoadedDoesNotEndTheInbox() async throws {
        let repository = makeRepository()
        let first = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let hits = try await repository.search(in: "inbox", query: "Letter 60",
                                               scope: .allMailboxes, beforeUID: nil, limit: 10)
        let hit = try XCTUnwrap(hits.first {
            $0.mailboxID == Server.allMail && $0.subject.hasPrefix("Letter 60:")
        })
        let inboxCount = server.uids(in: Server.inbox).count
        let (list, _) = await makeList(folder: first, results: hits)

        let done = await PaneActions.run(.delete, on: hit, inFolderWithRole: .archive, list: list,
                                         repository: repository, requestSweep: {})
        XCTAssertTrue(done)
        await list.endSearch()

        XCTAssertEqual(server.uids(in: Server.inbox).count, inboxCount - 1)
        let paged = try await pageToTheEnd(list, repository, pageSize: 10)
        XCTAssertEqual(paged, inboxCount - 1)
    }

    /// Upward after a date jump, the same: a letter above the window gone
    /// since the jump no longer stops the list short of the newest mail.
    func testAPageUpwardAfterAJumpIsWholeWhenALetterAboveHasGone() async throws {
        let repository = makeRepository()
        let day = Server.newestDate.addingTimeInterval(-70 * 86_400)
        let jumped = try await repository.messages(around: day, in: "inbox", limit: 10)
        let window = try XCTUnwrap(jumped)
        let top = try XCTUnwrap(window.messages.first)
        let inbox = server.uids(in: Server.inbox)
        let above = inbox[try XCTUnwrap(inbox.firstIndex(of: uid(top.id))) + 3]
        try await repository.delete("\(server.uidValidity(of: Server.inbox))/\(above)",
                                    from: "inbox")

        var newest = top.id
        var loaded = 0
        while true {
            let page = try await repository.listMessages(in: "inbox", afterUID: newest, limit: 10)
            loaded += page.count
            if let first = page.first { newest = first.id }
            if page.count < 10 { break }
        }
        let remaining = server.uids(in: Server.inbox)
        XCTAssertEqual(uid(newest), remaining.last)
        XCTAssertEqual(loaded, remaining.filter { $0 > uid(top.id) }.count)
    }

    func testReadBillingTakesEachLetterOffOnceAndMarkingUnreadPutsItBack() {
        var billing = ReadBilling()
        let letter = summary(id: "1/1", counted: ["INBOX", "[Gmail]/All Mail"])
        XCTAssertEqual(billing.read(letter), ["INBOX", "[Gmail]/All Mail"])
        XCTAssertNil(billing.read(letter))
        XCTAssertEqual(billing.unread(letter), ["INBOX", "[Gmail]/All Mail"])
        XCTAssertEqual(billing.read(letter), ["INBOX", "[Gmail]/All Mail"])

        // No labels to say: the folder it was listed from.
        XCTAssertEqual(billing.read(summary(id: "1/2", mailbox: "inbox")), ["inbox"])

        // Gone while unread: taken off once. Gone once read: nothing.
        let unread = summary(id: "1/3", counted: ["INBOX"])
        XCTAssertEqual(billing.left(unread), ["INBOX"])
        XCTAssertNil(billing.left(unread))
        var read = summary(id: "1/4", counted: ["INBOX"])
        read.isRead = true
        XCTAssertNil(billing.left(read))

        // The same letter under another mailbox's id, read or billed there,
        // is one count on the server, already taken off.
        let hit = summary(id: "2/5", mailbox: "[Gmail]/All Mail", counted: ["INBOX"])
        var readTwin = summary(id: "1/5", counted: ["INBOX"])
        readTwin.isRead = true
        XCTAssertNil(billing.left(hit, twins: [readTwin]))
        let billedTwin = summary(id: "1/1", counted: ["INBOX"])
        XCTAssertNil(billing.left(summary(id: "2/1", mailbox: "[Gmail]/All Mail"),
                                  twins: [billedTwin]))
        XCTAssertEqual(billing.left(summary(id: "2/6", mailbox: "[Gmail]/All Mail",
                                            counted: ["INBOX"]),
                                    twins: [summary(id: "1/6")]),
                       ["INBOX"])
    }

    func testTwinsAreTheSameLetterInAnotherMailboxAndNeverTwoInOne() {
        let hit = summary(id: "2/9", mailbox: "[Gmail]/All Mail", thread: "77")
        let inbox = summary(id: "1/9", mailbox: "inbox", thread: "77")
        let sameFolder = summary(id: "2/10", mailbox: "[Gmail]/All Mail", thread: "77")
        var other = summary(id: "1/10", mailbox: "inbox", thread: "77")
        other.subject = "Re: something else"
        XCTAssertEqual(ListEdit.twins(of: hit, among: [inbox, sameFolder, other, inbox]).map(\.id),
                       ["1/9"])
        XCTAssertEqual(ListEdit.twins(of: inbox, among: [hit]).map(\.id), ["2/9"])
        // Without Gmail's thread id there is no All Mail to hold a twin.
        XCTAssertEqual(ListEdit.twins(of: summary(id: "2/9", mailbox: "a"),
                                      among: [summary(id: "1/9", mailbox: "b")]), [])
    }

    func testPreviewsAlreadyShownGoAcrossToTheSameLettersFetchedAgain() {
        var shown = [summary(id: "1/1"), summary(id: "1/2"), summary(id: "1/3")]
        shown[0].preview = "first"
        shown[2].preview = "third"
        var fetched = [summary(id: "1/4"), summary(id: "1/3"), summary(id: "1/2"),
                       summary(id: "1/1")]
        fetched[2].preview = "already"
        let carried = ListEdit.carryingPreviews(from: shown, into: fetched)
        XCTAssertEqual(carried.map(\.id), fetched.map(\.id))
        XCTAssertEqual(carried.map(\.preview), ["", "third", "already", "first"])
    }

    /// A second Flag on the letter whose Flag is on its way is a double
    /// tap, and goes nowhere; a Flag on another letter goes. It used to be
    /// one Flag for the whole pane, so flagging the next letter he opened
    /// while the last one's STORE waited, behind a probe and a reconnect or
    /// a half-open socket's read deadline, was dropped without a word. One
    /// Delete at a time, whatever the pane shows.
    func testAFlagTappedTwiceOnOneLetterGoesOnceAndAnotherLettersFlagStillGoes() {
        var writes = PaneWrites()
        XCTAssertTrue(writes.startFlag("1/1"))
        XCTAssertFalse(writes.startFlag("1/1"))
        XCTAssertTrue(writes.startFlag("1/2"))
        writes.flagAnswered("1/1")
        XCTAssertTrue(writes.startFlag("1/1"))
        XCTAssertFalse(writes.startFlag("1/2"))

        XCTAssertFalse(writes.deleting)
        XCTAssertTrue(writes.startDelete())
        XCTAssertTrue(writes.deleting)
        XCTAssertFalse(writes.startDelete())
        writes.deleteAnswered()
        XCTAssertFalse(writes.deleting)
        XCTAssertTrue(writes.startDelete())
    }

    /// A regroup puts back every row that was selected, by id: in Edit mode
    /// they are his ticks, and the reading pane now edits the list whatever
    /// mode it is in. A letter the pane marks read is highlighted as the
    /// one open there, but not in Edit mode, where that would tick its
    /// conversation for him.
    func testARegroupKeepsEveryTickAndALetterOpenedInEditModeTicksNothing() {
        let threads = [MessageThread(messages: [summary(id: "1/9"), summary(id: "1/8")]),
                       MessageThread(messages: [summary(id: "1/7")]),
                       MessageThread(messages: [summary(id: "1/6"), summary(id: "1/5")]),
                       MessageThread(messages: [summary(id: "1/4")])]

        XCTAssertEqual(ListEdit.selectedRows(in: threads, kept: ["1/9", "1/7", "1/4"],
                                             opened: "1/5", editing: true), [0, 1, 3])
        // Out of Edit mode, the one open in the pane.
        XCTAssertEqual(ListEdit.selectedRows(in: threads, kept: ["1/6"], opened: "1/5",
                                             editing: false), [2])
        XCTAssertEqual(ListEdit.selectedRows(in: threads, kept: ["1/9"], opened: "1/5",
                                             editing: false), [2])
        XCTAssertEqual(ListEdit.selectedRows(in: threads, kept: [], opened: "1/8",
                                             editing: false), [0])
        XCTAssertEqual(ListEdit.selectedRows(in: threads, kept: ["1/7"], opened: nil,
                                             editing: false), [1])
        // A tick held by a letter that has since merged into a conversation
        // finds the conversation's row; one whose row has gone finds none.
        XCTAssertEqual(ListEdit.selectedRows(in: threads, kept: ["1/5", "1/3"], opened: nil,
                                             editing: true), [2])
        XCTAssertEqual(ListEdit.selectedRows(in: threads, kept: [], opened: nil,
                                             editing: false), [])
    }

    private func summary(id: String, mailbox: String = "inbox", thread: String? = nil,
                         counted: [String] = []) -> MessageSummary {
        MessageSummary(id: id, mailboxID: mailbox, sender: "Sam Example <sam@example.com>",
                       subject: "Letter 5: garden", preview: "", date: Server.newestDate,
                       isRead: false, isFlagged: false, threadID: thread,
                       countedFolderIDs: counted)
    }
}

/// What the list says to the folder counts, written down.
@MainActor
private final class CountChanges {
    /// The folders each letter billed as read came off, one entry per letter.
    private(set) var billed: [[String]] = []
    /// The folders each letter marked unread again went back on.
    private(set) var restored: [[String]] = []

    func record(_ folders: [String], _ delta: Int) {
        if delta < 0 { billed.append(folders) } else { restored.append(folders) }
    }
}
