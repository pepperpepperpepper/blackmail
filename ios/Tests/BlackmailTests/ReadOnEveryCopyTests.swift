import XCTest
@testable import Blackmail

/// A letter read from its All Mailboxes hit (B-089). Seen on the iPad on
/// 2026-10-03: the Inbox's row for the same letter kept its unread dot
/// until the list was fetched again, though the server had the letter as
/// read and the Inbox's count had gone down. The hit is All Mail's row,
/// under All Mail's id; the read mark went on that id alone, and the
/// Inbox's row under the search, which cancelling the search puts back
/// without a round trip, was left as it was. The kept copy did the same:
/// the hit names a row of All Mail, and the Inbox's kept row was changed
/// only when All Mail's kept page held the hit.
///
/// Now a read mark, from a tap, from Edit mode's Mark or from the reading
/// pane, goes on every row the list holds of the letter, by its Gmail
/// message id, and the kept pages the same; a refusal puts every one back.
/// Over `ScriptedIMAPServer` through the shipping repository, with the
/// list's own letters, `ListLetters`, as `MessageListViewController` calls
/// them.
final class ReadOnEveryCopyTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "ReadOnEveryCopyTests"

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

    private func makeRepository(shelf: MailShelf? = nil) -> IMAPMailRepository {
        IMAPMailRepository(account: server.account, password: server.password,
                           transport: server.transportFactory, recipients: book,
                           shelf: shelf ?? keptShelf(for: server.account))
    }

    private func uid(_ id: String) -> UInt32 { UInt32(id.split(separator: "/").last ?? "")! }

    /// The list as it stands under an All Mailboxes search: the Inbox's
    /// first page, fetched from the top, and the hits over it.
    @MainActor
    private func makeList(folder: [MessageSummary],
                          results: [MessageSummary]?) -> (ListLetters, Billed) {
        let list = ListLetters()
        let billed = Billed()
        list.onUnreadCountChanged = { billed.record($0, $1) }
        _ = list.fetchedAfresh(folder)
        if let results { list.showResults(results) }
        return (list, billed)
    }

    /// The Inbox's first page, the All Mailboxes hits for `query`, All
    /// Mail's hit and the Inbox's row of the same letter, under two ids.
    private func hitAndInboxRow(_ query: String, repository: IMAPMailRepository) async throws
        -> (rows: [MessageSummary], hits: [MessageSummary], hit: MessageSummary,
            row: MessageSummary) {
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let hits = try await repository.search(in: "inbox", query: query, scope: .allMailboxes,
                                               beforeUID: nil, limit: 50)
        let hit = try XCTUnwrap(hits.first { $0.mailboxID == Server.allMail })
        let row = try XCTUnwrap(rows.first { $0.gmailMessageID == hit.gmailMessageID })
        XCTAssertNotEqual(hit.id, row.id)
        XCTAssertEqual(hit.subject, row.subject)
        return (rows, hits, hit, row)
    }

    // MARK: - The list

    /// Tapped from the hits: the Inbox's row loses its dot at the tap with
    /// the hit's, keeps it off over a listing of the Inbox asked before the
    /// server took the mark, and shows read when the search is cancelled.
    /// One STORE, on the hit's own UID, and the counts billed once.
    func testALetterReadFromAnAllMailboxesHitIsReadInTheInboxUnderTheSearch() async throws {
        let repository = makeRepository()
        let (rows, hits, hit, row) = try await hitAndInboxRow("Letter 117", repository: repository)
        XCTAssertFalse(hit.isRead)
        XCTAssertFalse(row.isRead)
        let (list, billed) = await makeList(folder: rows, results: hits)
        // A listing of the Inbox from the top, on its way under the search.
        let asked = await list.askingAfresh()
        server.clearLog()

        // What the tap does (`markReadIfNeeded`), then what its answer does
        // (`sendRead`).
        await list.reading(hit, read: true)
        let atTheTap = await list.letter(row.id)
        XCTAssertEqual(atTheTap?.isRead, true, "the Inbox's row loses its dot at the tap")
        try await repository.setRead(true, on: hit)
        await list.readAnswered(hit.id, landed: true)
        await list.read(hit)
        XCTAssertEqual(server.log.map(\.verb), ["UID STORE"])
        XCTAssertTrue(server.log[0].command.contains("STORE \(uid(hit.id)) "))

        // The listing lands as the server had the Inbox when it was asked.
        _ = await list.fetchedUnderSearch(rows, asked: asked)
        let underIt = await list.letter(row.id)
        XCTAssertEqual(underIt?.isRead, true, "a listing asked before the mark does not bring it back")
        await list.endSearch()
        let shown = await list.shown.first { $0.id == row.id }
        XCTAssertEqual(shown?.isRead, true, "the search cancelled, the Inbox's row is read")
        XCTAssertTrue(server.flags(uid: uid(row.id), in: Server.inbox).contains("\\Seen"))
        let counted = await billed.billed
        XCTAssertEqual(counted.count, 1, "billed once")

        // A listing asked after the server took the mark has the say on
        // the Inbox's row: here, that it was marked unread elsewhere since.
        let later = await list.askingAfresh()
        var elsewhere = rows
        let i = try XCTUnwrap(elsewhere.firstIndex { $0.id == row.id })
        elsewhere[i].isRead = false
        _ = await list.fetchedAfresh(elsewhere, asked: later)
        let since = await list.letter(row.id)
        XCTAssertEqual(since?.isRead, false, "the listing asked since has the say")
    }

    /// A read mark on a hit that the server refuses puts the dot back on
    /// the hit and on the Inbox's row, and nothing is billed.
    func testARefusedReadMarkOnAHitPutsTheDotBackOnTheInboxsRowToo() async throws {
        let repository = makeRepository()
        let (rows, hits, hit, row) = try await hitAndInboxRow("Letter 117", repository: repository)
        let (list, billed) = await makeList(folder: rows, results: hits)

        await list.reading(hit, read: true)
        server.refusedVerbs = ["UID STORE"]
        let refused: Bool
        do {
            try await repository.setRead(true, on: hit)
            refused = false
        } catch {
            refused = true
        }
        XCTAssertTrue(refused)
        await list.readAnswered(hit.id, landed: false)

        let hitAfter = await list.letter(hit.id)
        XCTAssertEqual(hitAfter?.isRead, false)
        await list.endSearch()
        let rowAfter = await list.letter(row.id)
        XCTAssertEqual(rowAfter?.isRead, false, "the dot is back on the Inbox's row")
        XCTAssertFalse(server.flags(uid: uid(row.id), in: Server.inbox).contains("\\Seen"))
        let counted = await billed.billed
        XCTAssertEqual(counted, [])
    }

    /// Edit mode's Mark on a hit goes the same way, both ways: Mark as
    /// Unread puts the dot on the Inbox's row too, and Mark as Read takes
    /// it off again, each once the server has taken it (`applyRead`).
    func testEditModesMarkOnAHitMarksTheInboxsRowToo() async throws {
        let repository = makeRepository()
        let (rows, hits, hit, row) = try await hitAndInboxRow("Letter 110", repository: repository)
        XCTAssertTrue(hit.isRead)
        XCTAssertTrue(row.isRead)
        let (list, billed) = await makeList(folder: rows, results: hits)

        try await repository.setRead(false, on: hit)
        await list.reading(hit, read: false)
        await list.readAnswered(hit.id, landed: true)
        await list.unread(hit)
        let unread = await list.letter(row.id)
        XCTAssertEqual(unread?.isRead, false, "Mark as Unread")
        XCTAssertFalse(server.flags(uid: uid(row.id), in: Server.inbox).contains("\\Seen"))

        var marked = hit
        marked.isRead = false
        try await repository.setRead(true, on: marked)
        await list.reading(marked, read: true)
        await list.readAnswered(marked.id, landed: true)
        await list.read(marked)
        await list.endSearch()
        let read = await list.letter(row.id)
        XCTAssertEqual(read?.isRead, true, "Mark as Read")
        let (counted, restored) = await (billed.billed, billed.restored)
        XCTAssertEqual(counted.count, 1)
        XCTAssertEqual(restored.count, 1)
    }

    /// The reading pane can still hold the hit after the search has ended,
    /// and mark a letter of its conversation read: the list has no row
    /// under the hit's id any more, and the Inbox's row of the same letter
    /// is found from the letter itself (`markRead`, `markReadIfNeeded`).
    func testAReadMarkMadeAfterTheSearchEndedReachesTheInboxsRow() async throws {
        let repository = makeRepository()
        let (rows, hits, hit, row) = try await hitAndInboxRow("Letter 117", repository: repository)
        let (list, _) = await makeList(folder: rows, results: hits)
        await list.endSearch()
        let gone = await list.letter(hit.id)
        XCTAssertNil(gone)

        await list.reading(hit, read: true)
        try await repository.setRead(true, on: hit)
        await list.readAnswered(hit.id, landed: true)
        let after = await list.letter(row.id)
        XCTAssertEqual(after?.isRead, true)
    }

    /// The same letter is found by its Gmail message id, under any other
    /// id the list holds it by; as a twin only where a row has no such id;
    /// never another letter whose Gmail id differs, though it shares every
    /// other field; never the letter's own id, and each row once.
    func testTheCopiesOfALetterAreFoundByItsGmailID() {
        let hit = letter("2/9", mailbox: Server.allMail, message: 41)
        let inbox = letter("1/9", mailbox: Server.inbox, message: 41)
        let starred = letter("3/4", mailbox: Server.starred, message: 41, subject: "Other")
        let another = letter("1/10", mailbox: Server.inbox, message: 42)
        let noID = letter("1/11", mailbox: Server.inbox, message: nil)
        XCTAssertEqual(ListEdit.copies(of: hit, among: [hit, inbox, starred, another, noID, inbox])
            .map(\.id), ["1/9", "3/4", "1/11"])
        XCTAssertEqual(ListEdit.copies(of: inbox, among: [hit]).map(\.id), ["2/9"])
        // With no Gmail id, as a twin: across mailboxes only.
        let plain = letter("2/9", mailbox: Server.allMail, message: nil)
        XCTAssertEqual(ListEdit.copies(of: plain, among: [inbox, letter("2/8", mailbox: Server.allMail,
                                                                        message: nil)]).map(\.id),
                       ["1/9"])
    }

    /// Edit mode's Mark hands the list the letter, as the tap does, so the
    /// copies are found from it.
    func testEditModesMarkHandsTheListTheLetter() throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains("self.letters.reading(m, read: read) "
                                    + "self.letters.readTaken(m, read: read)"), list)
        XCTAssertTrue(list.contains("for m in marked { letters.reading(m, read: true) }"))
    }

    // MARK: - The watch's news

    /// The watch found the letter while he was scrolled down, and holds the
    /// Inbox's copy, unread, to go on when he is back at the top. He reads
    /// it from its All Mailboxes hit and cancels the search: the news goes
    /// on, and the Inbox's row has no dot, billed once. Put on as it was
    /// fetched, the row had its dot back, and a tap on it sent a second
    /// STORE. Mark as Unread on a hit reaches a held copy the same way.
    @MainActor
    func testALetterReadFromItsHitWhileTheWatchHoldsItsInboxCopyGoesOnRead() throws {
        let (row, hit) = inboxRowAndHit()
        let (list, billed) = makeList(folder: [olderRow()], results: nil)
        XCTAssertTrue(list.hold(FolderNews(arrived: [row])))

        list.showResults([hit])
        try tap(hit.id, on: list)
        _ = list.endSearch()
        XCTAssertEqual(list.putNewsOn(atTop: true, searching: false, ticked: false, touching: false),
                       .shown([readCopy(of: row)]))
        XCTAssertEqual(list.shown.map(\.id), [row.id, olderRow().id])
        XCTAssertEqual(list.letter(row.id)?.isRead, true, "the news goes on without its dot")
        XCTAssertEqual(billed.billed.count, 1, "billed once")

        // Read on the server, held, and marked unread from its hit.
        var other = letter("1/10", mailbox: Server.inbox, message: 42,
                           counted: [Server.inbox, Server.allMail])
        other.isRead = true
        var otherHit = letter("2/10", mailbox: Server.allMail, message: 42,
                              counted: [Server.allMail, Server.inbox])
        otherHit.isRead = true
        XCTAssertTrue(list.hold(FolderNews(arrived: [other])))
        list.showResults([otherHit])
        try markUnread(otherHit.id, on: list)
        _ = list.endSearch()
        _ = list.showNews()
        XCTAssertEqual(list.letter(other.id)?.isRead, false, "Mark as Unread reaches the news")
        XCTAssertEqual(billed.restored.count, 1)
    }

    /// A check of the Inbox asked before the search began, and before the
    /// STORE, that lands after the server has taken the mark: it brings the
    /// Inbox's copy as the server had it when asked, unread, and the copy
    /// takes his mark as it is held, by its Gmail id. The search cancelled,
    /// it goes on read, billed once. A check that lands while the STORE is
    /// still out takes the mark too, and keeps it once the STORE lands.
    /// And once a listing asked after the server took the mark has come,
    /// the server has the say on news as on the rest.
    @MainActor
    func testACheckAskedBeforeTheStoreThatLandsAfterItBringsTheLetterRead() throws {
        let (row, hit) = inboxRowAndHit()
        let (list, billed) = makeList(folder: [olderRow()], results: nil)
        XCTAssertNotNil(list.toWatch(fromNewest: true, fetched: true), "the check is asked")
        list.showResults([hit])
        try tap(hit.id, on: list)

        XCTAssertEqual(list.take(FolderNews(arrived: [row]), fromNewest: true), .new)
        XCTAssertEqual(list.putNewsOn(atTop: true, searching: true, ticked: false, touching: false),
                       .wait, "held while the search shows")
        _ = list.endSearch()
        _ = list.putNewsOn(atTop: true, searching: false, ticked: false, touching: false)
        XCTAssertEqual(list.letter(row.id)?.isRead, true, "the news goes on read")
        XCTAssertEqual(billed.billed.count, 1, "billed once")

        // The STORE still out as the check lands, then taken.
        let (other, otherHit) = (letter("1/10", mailbox: Server.inbox, message: 42),
                                 letter("2/10", mailbox: Server.allMail, message: 42))
        list.showResults([otherHit])
        list.reading(otherHit, read: true)
        XCTAssertTrue(list.hold(FolderNews(arrived: [other])))
        list.readAnswered(otherHit.id, landed: true)
        _ = list.endSearch()
        _ = list.showNews()
        XCTAssertEqual(list.letter(other.id)?.isRead, true, "taken while held")

        // A listing asked after the server took it: the server's word.
        let (third, thirdHit) = (letter("1/11", mailbox: Server.inbox, message: 43),
                                 letter("2/11", mailbox: Server.allMail, message: 43))
        list.showResults([thirdHit])
        try tap(thirdHit.id, on: list)
        let since = list.askingAfresh()
        _ = list.fetchedUnderSearch(list.folder, asked: since)
        XCTAssertTrue(list.hold(FolderNews(arrived: [third])))
        _ = list.endSearch()
        _ = list.showNews()
        XCTAssertEqual(list.letter(third.id)?.isRead, false, "a listing asked since has the say")
    }

    /// The Inbox's page asked before the STORE (a fresh page over the kept
    /// one, landing under the search) brings the letter's Inbox copy as the
    /// server had it then, unread, though the list did not hold that copy
    /// when he read the hit. It takes his mark by its Gmail id, and the
    /// letter is billed once.
    @MainActor
    func testAPageAskedBeforeTheStoreBringsTheLettersInboxCopyRead() throws {
        let (row, hit) = inboxRowAndHit()
        let (list, billed) = makeList(folder: [olderRow()], results: [hit])
        let asked = list.askingAfresh()
        try tap(hit.id, on: list)
        _ = list.fetchedUnderSearch([row, olderRow()], asked: asked)
        _ = list.endSearch()
        XCTAssertEqual(list.letter(row.id)?.isRead, true, "the page's copy of the hit he read")
        XCTAssertEqual(billed.billed.count, 1, "billed once")
    }

    /// The same page landing while the STORE is still out: the copy takes
    /// the mark, and the dot comes back on it when the server refuses.
    @MainActor
    func testAPageThatLandsWhileTheStoreIsOutTakesTheMarkAndARefusalPutsTheDotBack() {
        let (row, hit) = inboxRowAndHit()
        let (list, _) = makeList(folder: [olderRow()], results: [hit])
        let asked = list.askingAfresh()
        list.reading(hit, read: true)
        _ = list.fetchedUnderSearch([row, olderRow()], asked: asked)
        XCTAssertEqual(list.letter(row.id)?.isRead, true, "while the STORE is out")
        list.readAnswered(hit.id, landed: false)
        XCTAssertEqual(list.letter(row.id)?.isRead, false, "refused")
    }

    /// The server refuses the read mark made on a hit: the dot goes back on
    /// the Inbox's copy the watch holds, whether it was held before the
    /// mark or came while the STORE was out, and nothing is billed.
    @MainActor
    func testARefusedReadMarkPutsTheDotBackOnTheWatchsNews() {
        let (row, hit) = inboxRowAndHit()
        let (list, billed) = makeList(folder: [olderRow()], results: [hit])
        XCTAssertTrue(list.hold(FolderNews(arrived: [row])))
        list.reading(hit, read: true)
        list.readAnswered(hit.id, landed: false)
        _ = list.endSearch()
        _ = list.showNews()
        XCTAssertEqual(list.letter(row.id)?.isRead, false, "held before the mark")

        let (other, otherHit) = (letter("1/10", mailbox: Server.inbox, message: 42),
                                 letter("2/10", mailbox: Server.allMail, message: 42))
        list.showResults([otherHit])
        list.reading(otherHit, read: true)
        XCTAssertTrue(list.hold(FolderNews(arrived: [other])))
        list.readAnswered(otherHit.id, landed: false)
        _ = list.endSearch()
        _ = list.showNews()
        XCTAssertEqual(list.letter(other.id)?.isRead, false, "come while the STORE was out")
        XCTAssertEqual(billed.billed, [])
    }

    /// Read from its All Mail hit in one search, and marked unread from its
    /// Starred hit in the next: the Inbox's copy the watch then brings goes
    /// on unread, as he last left it, whichever mark is found first.
    @MainActor
    func testTheNewsTakesTheLastReadMarkMadeOnTheLetter() throws {
        let (row, hit) = inboxRowAndHit()
        let (list, _) = makeList(folder: [olderRow()], results: [hit])
        try tap(hit.id, on: list)
        _ = list.endSearch()
        let starred = readCopy(of: letter("3/9", mailbox: Server.starred, message: 41,
                                          counted: [Server.starred, Server.inbox]))
        list.showResults([starred])
        try markUnread(starred.id, on: list)
        _ = list.endSearch()

        XCTAssertTrue(list.hold(FolderNews(arrived: [readCopy(of: row)])))
        _ = list.showNews()
        XCTAssertEqual(list.letter(row.id)?.isRead, false)
    }

    // MARK: - The counts

    /// Read in the Inbox, marked unread on its All Mailboxes hit, and read
    /// in the Inbox again, where the dot is back once the search is
    /// cancelled: the counts end one lower than they began, as the letter
    /// is read. Billed by row, the unread on the hit forgot only the hit,
    /// the Inbox's row was billed already, and the counts ended where they
    /// began, one for a letter with no dot.
    func testReadInTheInboxMarkedUnreadOnItsHitAndReadThereAgainIsOneOff() async throws {
        let (row, hit) = inboxRowAndHit()
        let (list, billed) = await makeList(folder: [row], results: nil)
        try await tap(row.id, on: list)

        // He searches All Mailboxes: the server has the letter as read.
        var readHit = hit
        readHit.isRead = true
        await list.showResults([readHit])
        try await markUnread(hit.id, on: list)
        _ = await list.endSearch()
        try await tap(row.id, on: list)

        let (inbox, allMail) = await (billed.net(Server.inbox), billed.net(Server.allMail))
        XCTAssertEqual(inbox, -1, "one off the Inbox's count: the letter is read")
        XCTAssertEqual(allMail, -1)
    }

    /// Read from its hit, marked unread on the Inbox's row once the search
    /// is cancelled, and read from its hit again in a new search: one off,
    /// as the letter is read. Billed by row, the hit came off nothing the
    /// second time.
    func testReadFromItsHitMarkedUnreadInTheInboxAndReadFromTheHitAgainIsOneOff() async throws {
        let (row, hit) = inboxRowAndHit()
        let (list, billed) = await makeList(folder: [row], results: [hit])
        try await tap(hit.id, on: list)
        _ = await list.endSearch()
        try await markUnread(row.id, on: list)

        // He searches again: the server has the letter as unread.
        await list.showResults([hit])
        try await tap(hit.id, on: list)

        let (inbox, allMail) = await (billed.net(Server.inbox), billed.net(Server.allMail))
        XCTAssertEqual(inbox, -1, "one off the Inbox's count: the letter is read")
        XCTAssertEqual(allMail, -1)
    }

    /// The counts go by the letter, not the row: read on one copy, it is
    /// billed on all of them, and marked unread on any copy, the billing
    /// is forgotten for all. A row with no Gmail id goes by its own id, so
    /// two of them are two letters; and the same letter under another id,
    /// billed by its Gmail id, keeps a row of it with none from being
    /// billed again when it is binned (`left`).
    func testTheCountsBillALetterOnceWhicheverCopyIsRead() {
        let (row, hit) = inboxRowAndHit()
        let folders = [Server.allMail, Server.inbox]
        var billing = ReadBilling()
        XCTAssertEqual(billing.read(hit), folders)
        XCTAssertNil(billing.read(row), "read on another copy: billed already")
        XCTAssertEqual(billing.unread(row), [Server.inbox, Server.allMail])
        XCTAssertEqual(billing.read(hit), folders, "read again after an unread on another copy")
        XCTAssertNil(billing.left(row))

        let another = letter("1/10", mailbox: Server.inbox, message: 42)
        XCTAssertNotNil(billing.read(another), "another Gmail id: another letter")
        XCTAssertNotNil(billing.read(letter("1/11", mailbox: Server.inbox, message: nil)))
        XCTAssertNotNil(billing.read(letter("1/12", mailbox: Server.inbox, message: nil)),
                        "no Gmail id: by the row's own id")

        let billedThere = letter("2/13", mailbox: Server.allMail, message: 43)
        XCTAssertNotNil(billing.read(billedThere))
        XCTAssertNil(billing.left(letter("1/13", mailbox: Server.inbox, message: nil),
                                  twins: [billedThere]))
    }

    // MARK: - The kept copy

    /// A read mark and a flag on a hit change the Inbox's kept row of the
    /// same letter, whether All Mail has never been opened, and has no kept
    /// page, or its kept page does not reach so far down; and a launch
    /// draws them so.
    func testAReadMarkOrAFlagOnAHitChangesTheInboxsKeptRow() async throws {
        let shelf = keptShelf(for: server.account)
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.folders()
        func kept(_ letter: MessageSummary, on kept: MailShelf = shelf) -> MessageSummary? {
            kept.page(of: "inbox")?.rows.first { $0.id == letter.id }
        }

        // All Mail never opened.
        let (_, _, hit, row) = try await hitAndInboxRow("Letter 117", repository: repository)
        XCTAssertNil(shelf.page(of: Server.allMail))
        XCTAssertEqual(kept(row)?.isRead, false)
        try await repository.setRead(true, on: hit)
        try await repository.setFlagged(true, on: hit)
        XCTAssertEqual(kept(row)?.isRead, true, "read on the Inbox's kept page")
        XCTAssertEqual(kept(row)?.isFlagged, true, "flagged on the Inbox's kept page")

        // All Mail's page kept, without the letter on it.
        _ = try await repository.listMessages(in: Server.allMail, beforeUID: nil, limit: 50)
        let (_, _, older, olderRow) = try await hitAndInboxRow("Letter 75", repository: repository)
        XCTAssertFalse(shelf.page(of: Server.allMail)?.rows
            .contains { $0.gmailMessageID == older.gmailMessageID } ?? true)
        XCTAssertEqual(kept(olderRow)?.isRead, true)
        try await repository.setRead(false, on: older)
        XCTAssertEqual(kept(olderRow)?.isRead, false, "marked unread on the Inbox's kept page")

        shelf.flush()
        let relaunched = keptShelf(for: server.account)
        XCTAssertEqual(kept(row, on: relaunched)?.isRead, true)
        XCTAssertEqual(kept(row, on: relaunched)?.isFlagged, true)
        XCTAssertEqual(kept(olderRow, on: relaunched)?.isRead, false)
    }

    /// Binned from its All Mailboxes hit, or marked as spam from it, with
    /// All Mail never opened: the Inbox's kept row of the same letter goes
    /// with it, found by the Gmail id the MOVE named, and a launch does not
    /// draw it; the Inbox's other kept rows stay. Found from the hit's own
    /// kept row alone, there was none, and the Inbox's row stayed.
    func testALetterBinnedOrMarkedAsSpamFromItsHitLeavesTheInboxsKeptPage() async throws {
        let shelf = keptShelf(for: server.account)
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.folders()
        func kept(_ letter: MessageSummary, on kept: MailShelf = shelf) -> MessageSummary? {
            kept.page(of: "inbox")?.rows.first { $0.id == letter.id }
        }
        let (_, _, binned, binnedRow) = try await hitAndInboxRow("Letter 117", repository: repository)
        let (_, _, spam, spamRow) = try await hitAndInboxRow("Letter 75", repository: repository)
        XCTAssertNil(shelf.page(of: Server.allMail))
        let before = try XCTUnwrap(shelf.page(of: "inbox")?.rows.count)
        XCTAssertNotNil(kept(binnedRow))
        XCTAssertNotNil(kept(spamRow))

        try await repository.delete(binned)
        try await repository.move(spam, to: Server.spam)
        XCTAssertNil(kept(binnedRow), "binned from its hit")
        XCTAssertNil(kept(spamRow), "marked as spam from its hit")

        shelf.flush()
        let relaunched = keptShelf(for: server.account)
        XCTAssertNil(kept(binnedRow, on: relaunched))
        XCTAssertNil(kept(spamRow, on: relaunched))
        XCTAssertEqual(relaunched.page(of: "inbox")?.rows.count, before - 2)
    }

    // MARK: - Helpers

    private func letter(_ id: String, mailbox: String, message: UInt64?,
                        subject: String = "Letter 9: garden",
                        counted: [String] = []) -> MessageSummary {
        MessageSummary(id: id, mailboxID: mailbox, sender: "Sam Example <sam@example.com>",
                       subject: subject, preview: "", date: Server.newestDate,
                       isRead: false, isFlagged: false, threadID: "77",
                       gmailMessageID: message, countedFolderIDs: counted)
    }

    /// One unread letter, as the Inbox lists it and as an All Mailboxes
    /// search finds it in All Mail: two ids, one Gmail id, counted in the
    /// same folders, each listing its own first.
    private func inboxRowAndHit() -> (row: MessageSummary, hit: MessageSummary) {
        (letter("1/9", mailbox: Server.inbox, message: 41, counted: [Server.inbox, Server.allMail]),
         letter("2/9", mailbox: Server.allMail, message: 41, counted: [Server.allMail, Server.inbox]))
    }

    /// An older letter of the Inbox, read, under the news.
    private func olderRow() -> MessageSummary {
        var older = letter("1/5", mailbox: Server.inbox, message: 30, subject: "Older")
        older.isRead = true
        return older
    }

    private func readCopy(of letter: MessageSummary) -> MessageSummary {
        var read = letter
        read.isRead = true
        return read
    }

    /// A tap on the unread row the list shows under `id`, the server
    /// taking the mark (`markReadIfNeeded`, `sendRead`).
    @MainActor
    private func tap(_ id: String, on list: ListLetters) throws {
        let shown = try XCTUnwrap(list.shown.first { $0.id == id })
        XCTAssertFalse(shown.isRead, "the row tapped has its dot")
        list.reading(shown, read: true)
        list.readAnswered(shown.id, landed: true)
        var read = shown
        read.isRead = true
        list.read(read)
    }

    /// Edit mode's Mark as Unread on the read row the list shows under
    /// `id`, the server taking it (`applyRead`).
    @MainActor
    private func markUnread(_ id: String, on list: ListLetters) throws {
        let shown = try XCTUnwrap(list.shown.first { $0.id == id })
        XCTAssertTrue(shown.isRead, "the row marked has no dot")
        list.reading(shown, read: false)
        list.readAnswered(shown.id, landed: true)
        list.unread(shown)
    }

    /// The file's code with its comment lines dropped and its spacing
    /// made single, so a line is found however it is wrapped.
    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }
}

/// What the list says to the folder counts, written down.
@MainActor
private final class Billed {
    /// The folders each letter billed as read came off.
    private(set) var billed: [[String]] = []
    /// The folders each letter marked unread again went back on.
    private(set) var restored: [[String]] = []

    func record(_ folders: [String], _ delta: Int) {
        if delta < 0 { billed.append(folders) } else { restored.append(folders) }
    }

    /// What `folder`'s count has moved by, all told.
    func net(_ folder: String) -> Int {
        restored.filter { $0.contains(folder) }.count - billed.filter { $0.contains(folder) }.count
    }
}
