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
                          results: [MessageSummary]) -> (ListLetters, Billed) {
        let list = ListLetters()
        let billed = Billed()
        list.onUnreadCountChanged = { billed.record($0, $1) }
        _ = list.fetchedAfresh(folder)
        list.showResults(results)
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
                                    + "self.letters.readAnswered(m.id, landed: true)"), list)
        XCTAssertTrue(list.contains("for m in marked { letters.reading(m, read: true) }"))
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

    // MARK: - Helpers

    private func letter(_ id: String, mailbox: String, message: UInt64?,
                        subject: String = "Letter 9: garden") -> MessageSummary {
        MessageSummary(id: id, mailboxID: mailbox, sender: "Sam Example <sam@example.com>",
                       subject: subject, preview: "", date: Server.newestDate,
                       isRead: false, isFlagged: false, threadID: "77",
                       gmailMessageID: message)
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
}
