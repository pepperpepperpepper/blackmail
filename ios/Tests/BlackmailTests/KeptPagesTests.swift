import XCTest
@testable import Blackmail

/// More than one page of a folder kept on the iPad (B-160, the first of its
/// three parts): Mail keeps every letter's line it has synced, so with no
/// connection he scrolls past the first fifty. Here the kept rows are the
/// folder's from the top, contiguous, as far as they were listed, up to 500
/// of the Inbox and 200 of any other: a page listed below goes on the kept
/// page when the kept rows reach it, and a fresh first page keeps the kept
/// rows below it as far as they go on from it in the folder's UIDs now.
///
/// The store through the shelf, the rule the list keeps its rows by at the
/// swap, and the listing over the scripted server through the shipping
/// repository and client, launch after launch, with the line taken down
/// for the offline one.
final class KeptPagesTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "KeptPagesTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var line: PagesLine!
    private var root: URL!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        line = PagesLine()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("KeptPagesTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        if let root {
            MailShelf.wipe(root: kept)
            try? FileManager.default.removeItem(at: root)
        }
        server = nil
        book = nil
        line = nil
        root = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private var kept: URL { root.appendingPathComponent("Kept", isDirectory: true) }

    private func makeShelf() -> MailShelf {
        MailShelf(root: kept, address: server.username, host: server.account.imapHost)
    }

    private func makeRepository(shelf: MailShelf) -> IMAPMailRepository {
        let imap = server.transportFactory
        let line = self.line!
        return IMAPMailRepository(
            account: server.account, password: server.password,
            transport: { host, port in line.isUp ? imap(host, port) : imap(host, 1) },
            recipients: book, signatureImages: { [] }, shelf: shelf)
    }

    private static let base = Date(timeIntervalSince1970: 1_790_000_000)

    /// A row of `folder` under UID `uid`, its Gmail id `uid` + 9000 unless
    /// `gmail` says otherwise; newer with the UID.
    private func row(_ uid: UInt32, _ folder: String = Server.inbox, validity: UInt32 = 1,
                     gmail: UInt64? = nil, preview: String = "", read: Bool = true) -> MessageSummary {
        MessageSummary(id: "\(validity)/\(uid)", mailboxID: folder, sender: "Sam Example <sam@example.com>",
                       subject: "Letter \(uid)", preview: preview,
                       date: Self.base.addingTimeInterval(Double(uid) * 60), isRead: read,
                       isFlagged: false, threadID: String(70_000 + uid),
                       gmailMessageID: gmail ?? UInt64(9_000 + uid))
    }

    /// Rows `from` down to `to`, newest first.
    private func rows(_ from: UInt32, _ to: UInt32, _ folder: String = Server.inbox,
                      validity: UInt32 = 1) -> [MessageSummary] {
        stride(from: from, through: to, by: -1).map { row($0, folder, validity: validity) }
    }

    private func uids(_ from: UInt32, _ to: UInt32) -> [UInt32] {
        Array(stride(from: from, through: to, by: -1))
    }

    private func keptUIDs(_ shelf: MailShelf, _ folder: String = Server.inbox) -> [UInt32] {
        (shelf.page(of: folder)?.rows ?? []).compactMap { UInt32($0.id.split(separator: "/").last ?? "") }
    }

    // MARK: - The store

    /// A page listed below the kept rows' last goes on after them, and the
    /// next launch has them all, in order, from the top.
    func testPagesListedBelowGoOnTheKeptPageIntoTheNextLaunch() {
        let shelf = makeShelf()
        shelf.took(page: rows(200, 151), of: Server.inbox, validity: 1)
        shelf.took(more: rows(150, 101), of: Server.inbox, validity: 1, below: 151)
        shelf.took(more: rows(100, 81), of: Server.inbox, validity: 1, below: 101)
        XCTAssertEqual(keptUIDs(shelf), uids(200, 81))
        shelf.flush()
        let next = makeShelf()
        XCTAssertEqual(keptUIDs(next), uids(200, 81))
        XCTAssertEqual(next.page(of: "inbox")?.rows.map(\.mailboxID).first, "inbox")
    }

    /// Only contiguous from the top: nothing from a page below a cursor the
    /// kept rows do not reach, nor before the folder has been listed from
    /// the top in this launch, nor under another UIDVALIDITY.
    func testAPageThatWouldLeaveAGapIsNotKept() {
        let shelf = makeShelf()
        shelf.took(page: rows(200, 151), of: Server.inbox, validity: 1)
        shelf.took(more: rows(120, 101), of: Server.inbox, validity: 1, below: 121)
        XCTAssertEqual(keptUIDs(shelf), uids(200, 151), "a gap above it")
        shelf.took(more: rows(150, 101, validity: 2), of: Server.inbox, validity: 2, below: 151)
        XCTAssertEqual(keptUIDs(shelf), uids(200, 151), "another UIDVALIDITY")
        shelf.flush()

        let next = makeShelf()
        next.took(more: rows(150, 101), of: Server.inbox, validity: 1, below: 151)
        XCTAssertEqual(keptUIDs(next), uids(200, 151), "not listed from the top in this launch")
    }

    /// A page listed below a cursor above the kept rows' last takes the
    /// place of the kept rows it covers, its marks and words the server's
    /// now, and the kept rows below it stay as far as they go on from it.
    func testAPageOverKeptRowsReplacesThemAndKeepsWhatGoesOn() {
        let shelf = makeShelf()
        shelf.took(page: rows(200, 101), of: Server.inbox, validity: 1)
        shelf.previews(["1/120": "kept words"], in: Server.inbox)
        var page = rows(150, 121)
        page[0].isRead = false
        shelf.took(more: page, of: Server.inbox, validity: 1, below: 151, continuing: uids(120, 101))
        XCTAssertEqual(keptUIDs(shelf), uids(200, 101))
        XCTAssertEqual(shelf.page(of: Server.inbox)?.rows.first { $0.id == "1/150" }?.isRead, false)
        XCTAssertEqual(shelf.page(of: Server.inbox)?.rows.first { $0.id == "1/120" }?.preview, "kept words")

        shelf.took(more: rows(150, 121), of: Server.inbox, validity: 1, below: 151,
                   continuing: [120, 119, 117])
        XCTAssertEqual(keptUIDs(shelf), uids(200, 119) + [117], "118 gone from the folder")
        shelf.took(more: rows(150, 121), of: Server.inbox, validity: 1, below: 151, continuing: [])
        XCTAssertEqual(keptUIDs(shelf), uids(200, 121), "nothing goes on from it")
    }

    /// A fresh first page keeps the kept rows below it that go on from it
    /// in the folder's UIDs now, their words with them: a letter gone from
    /// the folder elsewhere drops out, and the rows stop at the first UID
    /// with none kept. With new mail above, the page overlaps the kept rows
    /// and they go on below it.
    func testAFreshFirstPageKeepsTheRowsThatGoOnBelowIt() {
        let shelf = makeShelf()
        shelf.took(page: rows(200, 151), of: Server.inbox, validity: 1)
        shelf.took(more: rows(150, 101), of: Server.inbox, validity: 1, below: 151)
        shelf.previews(["1/140": "words of 140"], in: Server.inbox)
        shelf.flush()

        let next = makeShelf()
        let fresh = rows(205, 156)
        next.took(page: fresh, of: Server.inbox, validity: 1,
                  continuing: uids(155, 131) + uids(129, 90))
        XCTAssertEqual(keptUIDs(next), uids(205, 131) + uids(129, 101), "130 gone, 100 never kept")
        XCTAssertEqual(next.page(of: Server.inbox)?.rows.first { $0.id == "1/140" }?.preview, "words of 140")
        next.took(page: fresh, of: Server.inbox, validity: 1, continuing: [])
        XCTAssertEqual(keptUIDs(next), uids(205, 156), "nothing below")
    }

    /// Never the wrong mailbox: kept rows below a fresh page that shares no
    /// letter with them under the same UID and Gmail id are not kept, and a
    /// page below whose rows name other letters under kept UIDs keeps none
    /// below it.
    func testRowsBelowAreKeptOnlyFromTheSameMailbox() {
        let shelf = makeShelf()
        shelf.took(page: rows(200, 101), of: Server.inbox, validity: 1)
        shelf.flush()

        let apart = makeShelf()
        apart.took(page: rows(300, 251), of: Server.inbox, validity: 1, continuing: uids(200, 101))
        XCTAssertEqual(keptUIDs(apart), uids(300, 251), "nothing in common with the kept rows")

        let again = makeShelf()
        again.took(page: rows(300, 251), of: Server.inbox, validity: 1)
        again.took(more: rows(250, 201), of: Server.inbox, validity: 1, below: 251)
        var other = rows(200, 191)
        other[0] = row(200, gmail: 1)
        again.took(page: rows(260, 211), of: Server.inbox, validity: 1, continuing: uids(210, 201))
        XCTAssertEqual(keptUIDs(again), uids(260, 201))
        again.took(more: other, of: Server.inbox, validity: 1, below: 201, continuing: [])
        XCTAssertEqual(keptUIDs(again), uids(260, 191))
        again.took(more: [row(205, gmail: 5)], of: Server.inbox, validity: 1, below: 206,
                   continuing: uids(204, 191))
        XCTAssertEqual(keptUIDs(again), uids(260, 205), "another letter under a kept UID: none below")
    }

    /// At most 500 rows of the Inbox, 200 of any other folder, and about
    /// half a megabyte of either, the newest kept.
    func testTheBounds() throws {
        let shelf = makeShelf()
        shelf.took(page: rows(1_000, 951), of: Server.inbox, validity: 1)
        var cursor: UInt32 = 951
        while cursor > 400 {
            shelf.took(more: rows(cursor - 1, cursor - 50), of: Server.inbox, validity: 1, below: cursor)
            cursor -= 50
        }
        XCTAssertEqual(keptUIDs(shelf), uids(1_000, 501))
        XCTAssertEqual(MailShelf.mostInboxRows, 500)

        shelf.took(page: rows(1_000, 951, Server.allMail), of: Server.allMail, validity: 1)
        cursor = 951
        while cursor > 600 {
            shelf.took(more: rows(cursor - 1, cursor - 50, Server.allMail), of: Server.allMail,
                       validity: 1, below: cursor)
            cursor -= 50
        }
        XCTAssertEqual(keptUIDs(shelf, Server.allMail), uids(1_000, 801))
        XCTAssertEqual(MailShelf.mostRows, 200)

        let wordy = String(repeating: "word ", count: 600)
        var heavy = rows(1_000, 951, Server.trash)
        for i in heavy.indices { heavy[i].preview = wordy }
        shelf.took(page: heavy, of: Server.trash, validity: 1)
        cursor = 951
        while cursor > 801 {
            var more = rows(cursor - 1, cursor - 50, Server.trash)
            for i in more.indices { more[i].preview = wordy }
            shelf.took(more: more, of: Server.trash, validity: 1, below: cursor)
            cursor -= 50
        }
        let kept = keptUIDs(shelf, Server.trash)
        XCTAssertLessThan(kept.count, 200)
        XCTAssertGreaterThan(kept.count, 50)
        XCTAssertEqual(kept, uids(1_000, 1_000 - UInt32(kept.count) + 1), "the newest, contiguous")
        shelf.flush()
        let file = try XCTUnwrap(pageFile(Server.trash))
        XCTAssertLessThan(try Data(contentsOf: file).count, MailShelf.mostPageBytes + 64 << 10)
    }

    private func pageFile(_ folder: String) -> URL? {
        let files = FileManager.default
        for account in (try? files.contentsOfDirectory(at: kept, includingPropertiesForKeys: nil)) ?? [] {
            let name = "page-\(MailShelf.hash(folder)).json"
            let url = account.appendingPathComponent(name)
            if files.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    // MARK: - The list at the swap

    /// The kept rows below the fresh page, for a list scrolled down them as
    /// it lands: the kept page's rows after the fresh page's, and none when
    /// the kept rows do not begin with them.
    func testTheKeptTailBelowTheFreshPage() {
        let fresh = rows(205, 156)
        let keptRows = rows(205, 156) + rows(155, 120)
        XCTAssertEqual(ListOpening.keptTail(below: fresh, in: keptRows).map(\.id), rows(155, 120).map(\.id))
        XCTAssertEqual(ListOpening.keptTail(below: fresh, in: fresh), [])
        XCTAssertEqual(ListOpening.keptTail(below: fresh, in: rows(204, 120)), [])
        XCTAssertEqual(ListOpening.keptTail(below: [], in: keptRows), [])
    }

    /// The list carries the kept rows below the fresh page where he has
    /// scrolled down them, and under a search; at the top the page goes in
    /// alone. Read from the source.
    func testTheListCarriesTheKeptTailWhereHeHasScrolled() throws {
        let code = try source("UI/MessageListViewController.swift")
        let land = try section(of: code, from: "private func landFreshPage() {", to: "private func waitForLift()")
        XCTAssertTrue(land.contains("case .top: unpreviewed = letters.fetchedAfresh(first, asked: fresh.asked)"))
        XCTAssertTrue(land.contains("unpreviewed = letters.fetchedAfresh(first + keptTail(below: first), "
                                    + "asked: fresh.asked)"))
        XCTAssertTrue(land.contains("unpreviewed = letters.fetchedUnderSearch(first + keptTail(below: first), "
                                    + "asked: fresh.asked)"))
        XCTAssertTrue(code.contains("guard let kept = repository.shelf?.page(of: mailbox.id) else { return [] } "
                                    + "return ListOpening.keptTail(below: first, in: kept.rows)"))
        let reload = try section(of: code, from: "func reload(keepingPlace: Bool = false",
                                 to: "private var voiceOver = ListVoiceOver()")
        XCTAssertFalse(reload.contains("keptTail"), "a Refresh is the server's page alone")
    }

    // MARK: - Over the server

    /// The Inbox listed and paged in one launch is there, every row, at the
    /// next launch with no connection, in the first frame, nothing sent; and
    /// a launch with a connection keeps the rows below its fresh page, a
    /// letter taken out elsewhere dropping out.
    func testAFolderPagedIsKeptAndGoesOnAfterTheNextListing() async throws {
        let first = makeShelf()
        let repository = makeRepository(shelf: first)
        let top = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let second = try await repository.listMessages(in: "inbox", beforeUID: top.last?.id, limit: 50)
        let third = try await repository.listMessages(in: "inbox", beforeUID: second.last?.id, limit: 50)
        XCTAssertEqual(top.count + second.count + third.count, 120)
        first.flush()
        let all = (top + second + third).map(\.id)
        XCTAssertEqual(first.page(of: "inbox")?.rows.map(\.id), all)

        line.isUp = false
        server.clearLog()
        let offline = makeShelf()
        XCTAssertEqual(offline.page(of: "inbox")?.rows.map(\.id), all, "the next launch's first frame")
        XCTAssertEqual(server.log, [])

        line.isUp = true
        let gone = try XCTUnwrap(UInt32(second[10].id.split(separator: "/").last ?? ""))
        server.removeElsewhere(uid: gone, from: Server.inbox)
        let again = makeShelf()
        let online = makeRepository(shelf: again)
        _ = try await online.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(again.page(of: "inbox")?.rows.map(\.id), all.filter { $0 != second[10].id })
    }

    /// A day jumped to, and a page below it, are not kept: the kept rows
    /// stay the folder's from the top. A search's hits neither.
    func testADayAndItsPagesAreNotKept() async throws {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let top = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let day = Server.newestDate.addingTimeInterval(-50 * 86_400)
        let window = try await repository.messages(around: day, in: "inbox", limit: 50)
        let below = try await repository.listMessages(in: "inbox", beforeUID: window?.messages.last?.id,
                                                      limit: 50)
        XCTAssertFalse(below.isEmpty)
        _ = try await repository.search(in: "inbox", query: "garden ", scope: .currentMailbox,
                                        beforeUID: nil, limit: 50)
        XCTAssertEqual(shelf.page(of: "inbox")?.rows.map(\.id), top.map(\.id))
    }

    // MARK: - Source

    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }

    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/\(file)")
        let text = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        return flat(text)
    }

    private func section(of code: String, from start: String, to end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start), start)
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex), end)
        return String(code[from.lowerBound..<to.lowerBound])
    }
}

/// The connection, up or down.
private final class PagesLine: @unchecked Sendable {
    private let lock = NSLock()
    private var up = true

    var isUp: Bool {
        get { lock.lock(); defer { lock.unlock() }; return up }
        set { lock.lock(); up = newValue; lock.unlock() }
    }
}
