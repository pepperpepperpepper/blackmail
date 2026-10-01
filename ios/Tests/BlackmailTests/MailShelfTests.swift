import XCTest
@testable import Blackmail

/// The store under D-016's copy of his mail (`MailShelf`), on its own, in a
/// directory of the test's own laid out as Application Support is: a file
/// of another format or a damaged one, a saved password, another account's
/// copy, and how long the launch's read takes. What the repository keeps in
/// it, and when, is `KeptCopyTests`.
final class MailShelfTests: XCTestCase {

    private var base: URL!
    private var support: URL { base.appendingPathComponent("Application Support", isDirectory: true) }
    private var kept: URL { support.appendingPathComponent("Kept", isDirectory: true) }

    override func setUp() {
        super.setUp()
        base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("MailShelfTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let base {
            MailShelf.wipe(root: kept)
            try? FileManager.default.removeItem(at: base)
        }
        base = nil
        super.tearDown()
    }

    private func shelf(for address: String = "owner@example.com",
                       host: String = "imap.gmail.com") -> MailShelf {
        MailShelf(root: kept, address: address, host: host)
    }

    private static let folders = [
        Mailbox(id: "INBOX", name: "INBOX", unreadCount: 6, role: .inbox),
        Mailbox(id: "[Gmail]/Drafts", name: "Drafts", unreadCount: 0, role: .drafts, depth: 1),
        Mailbox(id: "[Gmail]/Sent Mail", name: "Sent Mail", unreadCount: 0, role: .sent, depth: 1),
        Mailbox(id: "[Gmail]/All Mail", name: "All Mail", unreadCount: 6, role: .archive, depth: 1),
    ]

    /// Fifty rows the size of his: a name and an address, a subject, two
    /// lines of preview, three folders counted, a file on every fifth.
    private func rows(_ count: Int = 50, in mailboxID: String = "INBOX") -> [MessageSummary] {
        let senders = ["Sam Example <sam@example.com>", "Carlo <carlo@example.org>",
                       "jane@example.com"]
        let preview = String(repeating: "A few words about the garden and the weather. ", count: 4)
        let photo = Attachment(id: "2", filename: "photo.jpg", mimeType: "image/jpeg", size: 120_000)
        return (0..<count).map { (i: Int) -> MessageSummary in
            let uid: Int = 9_000 - i
            let thread: UInt64 = 1_700_000_000_000_000_000 + UInt64(i)
            let message: UInt64 = 1_800_000_000_000_000_000 + UInt64(i)
            let date = Date(timeIntervalSince1970: 1_790_000_000 - Double(i) * 3_600)
            var row = MessageSummary(id: "1/\(uid)", mailboxID: mailboxID,
                                     sender: senders[i % senders.count],
                                     subject: "Letter \(i): about the garden, the tickets and the dinner",
                                     preview: preview, date: date, isRead: i > 5,
                                     isFlagged: i % 11 == 0)
            row.hasAttachment = i % 5 == 0
            row.threadID = "\(thread)"
            row.gmailMessageID = message
            row.countedFolderIDs = ["INBOX", "[Gmail]/All Mail", "[Gmail]/Important"]
            row.attachments = i % 5 == 0 ? [photo] : []
            return row
        }
    }

    /// The file a page is kept in, found by what it says it is.
    private func pageFile(of folder: String, under directory: URL) throws -> URL {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        for name in names where name.hasPrefix("page-") {
            let url = directory.appendingPathComponent(name)
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            if (object as? [String: Any])?["folder"] as? String == folder { return url }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    // MARK: - A bad file

    /// A page written by a build of another format, a page cut off, and a
    /// folder list that is not JSON at all: each reads as nothing kept, is
    /// deleted, and stops nothing else. A page of this format beside them
    /// still reads.
    func testAFileOfAnotherFormatOrADamagedOneIsNothingKeptAndGoes() throws {
        let writing = shelf()
        writing.took(folders: Self.folders)
        writing.took(page: rows(), of: "INBOX", validity: 1)
        writing.took(page: rows(10, in: "[Gmail]/Sent Mail"), of: "[Gmail]/Sent Mail", validity: 4)
        writing.took(page: rows(3, in: "[Gmail]/Drafts"), of: "[Gmail]/Drafts", validity: 3)
        writing.flush()

        let directory = writing.directory
        let inbox = try pageFile(of: "INBOX", under: directory)
        let sent = try pageFile(of: "[Gmail]/Sent Mail", under: directory)
        let list = directory.appendingPathComponent("folders.json")
        var later = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: inbox))
                                    as? [String: Any])
        later["format"] = MailShelf.format + 1
        try JSONSerialization.data(withJSONObject: later).write(to: inbox)
        let whole = try Data(contentsOf: sent)
        try whole.prefix(whole.count / 2).write(to: sent)
        try Data("{".utf8).write(to: list)

        let relaunched = shelf()
        XCTAssertNil(relaunched.folders)
        XCTAssertNil(relaunched.page(of: "inbox"), "another format")
        XCTAssertNil(relaunched.page(of: "[Gmail]/Sent Mail"), "cut off")
        XCTAssertEqual(relaunched.page(of: "[Gmail]/Drafts")?.rows.count, 3)
        for file in [inbox, sent, list] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), file.lastPathComponent)
        }
        // And it keeps again, as a launch with nothing kept does.
        relaunched.took(page: rows(), of: "INBOX", validity: 1)
        relaunched.flush()
        XCTAssertEqual(shelf().page(of: "inbox")?.rows.count, 50)
    }

    // MARK: - A row's Cc

    /// A row's Cc is kept with it and read back, so a launch draws the
    /// header's Cc line from the tap as a fetched row does (B-055). A row
    /// with none is written as it always was, and a page kept before the
    /// rows carried a Cc reads, its rows with none: no new format.
    func testARowsCcIsKeptAndAPageKeptWithoutOneStillReads() throws {
        var kept = rows(10)
        kept[0].cc = ["Pat Example <pat@example.com>", "lee@example.com"]
        let writing = shelf()
        writing.took(page: kept, of: "INBOX", validity: 1)
        writing.flush()
        XCTAssertEqual(shelf().page(of: "inbox")?.rows.map(\.cc), kept.map(\.cc))

        // The page as a build before the Cc wrote it: no row names one.
        let file = try pageFile(of: "INBOX", under: writing.directory)
        var page = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file))
                                    as? [String: Any])
        var records = try XCTUnwrap(page["rows"] as? [[String: Any]])
        XCTAssertEqual(records.filter { $0["cc"] != nil }.count, 1, "only the row with a Cc")
        for i in records.indices { records[i]["cc"] = nil }
        page["rows"] = records
        try JSONSerialization.data(withJSONObject: page).write(to: file)

        let older = try XCTUnwrap(shelf().page(of: "inbox")).rows
        XCTAssertEqual(older.map(\.id), kept.map(\.id))
        XCTAssertEqual(older.map(\.cc), Array(repeating: [], count: 10))
    }

    // MARK: - His own counts

    /// His read and unread marks move the kept counts as they move the
    /// folder pane's, by the pane's ids (the role word or the LIST name),
    /// never below none, and the next launch reads them: a letter marked
    /// unread is on the count it draws, not off it until a sweep lands.
    func testHisOwnMarksMoveTheKeptCountsAsTheyMoveThePanes() throws {
        let one = shelf()
        one.took(folders: Self.folders)
        one.counted(["inbox", "[Gmail]/All Mail"], by: 1)
        one.counted(["INBOX", "[Gmail]/Drafts", "[Gmail]/Nowhere"], by: -1)
        one.counted(["[Gmail]/Drafts"], by: -1)
        one.counted(["[Gmail]/Sent Mail"], by: 1)
        one.flush()

        let counts = (shelf().folders ?? []).reduce(into: [String: Int]()) {
            $0[$1.id] = $1.unreadCount
        }
        XCTAssertEqual(counts, ["INBOX": 6, "[Gmail]/Drafts": 0,
                                "[Gmail]/Sent Mail": 1, "[Gmail]/All Mail": 7])
    }

    /// With nothing kept there is nothing to move, and nothing is made up.
    func testWithNoFoldersKeptAMarkKeepsNoCounts() {
        let one = shelf()
        one.counted(["INBOX"], by: 1)
        one.flush()
        XCTAssertNil(shelf().folders)
    }

    // MARK: - A saved password

    /// Saving a password throws away the whole of `Kept/`, and nothing else
    /// under Application Support: the letters `LocalDrafts` keeps beside it
    /// are all still there. The shelf that was running reads and keeps
    /// nothing more; the next launch's keeps again. In the app the two are
    /// siblings, so the one cannot reach into the other.
    @MainActor
    func testASavedPasswordWipesTheCopyAndLeavesTheLettersKeptByLocalDrafts() throws {
        let drafts = support.appendingPathComponent("Local Drafts", isDirectory: true)
        var letter = Draft()
        letter.to = ["sam@example.com"]
        letter.subject = "Half a letter"
        letter.body = "Started before the password changed."
        try LocalDraftStore(root: drafts).keep(letter, as: "k1", unfinished: true,
                                               account: "owner@example.com")
        let running = shelf()
        running.took(folders: Self.folders)
        running.took(page: rows(), of: "INBOX", validity: 1)
        running.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: running.directory.path))

        MailShelf.wipe(root: kept)

        XCTAssertFalse(FileManager.default.fileExists(atPath: kept.path))
        XCTAssertEqual(LocalDraftStore(root: drafts).letters().map(\.draft.subject), ["Half a letter"])
        XCTAssertNil(running.page(of: "inbox"))
        XCTAssertNil(running.folders)
        running.took(page: rows(), of: "INBOX", validity: 1)
        running.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: kept.path), "keeps nothing more")

        let next = shelf()
        XCTAssertNil(next.page(of: "inbox"))
        next.took(page: rows(), of: "INBOX", validity: 1)
        next.flush()
        XCTAssertEqual(shelf().page(of: "inbox")?.rows.count, 50)

        XCTAssertEqual(MailShelf.appRoot.deletingLastPathComponent().standardizedFileURL,
                       LocalDraftStore.appRoot.deletingLastPathComponent().standardizedFileURL)
        XCTAssertEqual(MailShelf.appRoot.lastPathComponent, "Kept")
        XCTAssertEqual(LocalDraftStore.appRoot.lastPathComponent, "Local Drafts")
    }

    // MARK: - Another account

    /// The copy is the account's, by its address and server: a shelf made
    /// for another removes every other directory under `Kept/`, a stray
    /// file included. The same address in other case is the same account.
    func testAnotherAccountsCopyGoesAsTheShelfIsMade() throws {
        let theirs = shelf(for: "carlo@example.org")
        theirs.took(page: rows(), of: "INBOX", validity: 1)
        theirs.flush()
        let elsewhere = shelf(for: "owner@example.com", host: "imap.example.net")
        XCTAssertFalse(FileManager.default.fileExists(atPath: theirs.directory.path))
        elsewhere.took(page: rows(), of: "INBOX", validity: 1)
        elsewhere.flush()
        try Data("left over".utf8).write(to: kept.appendingPathComponent("stray"))

        let mine = shelf(for: " Owner@Example.com ")
        XCTAssertNil(mine.page(of: "inbox"), "another server's is not this account's")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: kept.path), [])
        mine.took(page: rows(), of: "INBOX", validity: 1)
        mine.flush()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: kept.path),
                       [mine.directory.lastPathComponent])
        XCTAssertEqual(shelf(for: "owner@example.com").page(of: "inbox")?.rows.count, 50)
        XCTAssertNotEqual(mine.directory, theirs.directory)
        XCTAssertNotEqual(mine.directory, elsewhere.directory)
    }

    // MARK: - The launch's read

    /// What a launch reads before its first frame: the folder list and the
    /// Inbox's fifty rows, by a shelf made afresh, which lists `Kept/` as it
    /// is made, read whole and right fifteen times over. On the main thread,
    /// so it has to be quick, and it is timed here, in the debug build the
    /// suite runs, and the figures printed for PERFORMANCE.md, which has
    /// them against the 30 ms past which it would have to move off the main
    /// thread. Not asserted: the suite is run with several copies at once,
    /// and a loaded host would fail a time limit with nothing wrong.
    func testTheLaunchsReadOfTheFoldersAndTheInboxIsTimed() throws {
        let writing = shelf()
        writing.took(folders: Self.folders)
        writing.took(page: rows(), of: "INBOX", validity: 1)
        writing.flush()
        let bytes = try Data(contentsOf: pageFile(of: "INBOX", under: writing.directory)).count

        var times: [Duration] = []
        for _ in 0..<15 {
            let started = ContinuousClock.now
            let launch = shelf()
            let folders = launch.folders
            let page = launch.page(of: "inbox")
            times.append(ContinuousClock.now - started)
            XCTAssertEqual(folders?.count, 4)
            XCTAssertEqual(page?.rows.count, 50)
            XCTAssertEqual(page?.rows.first?.attachments.first?.filename, "photo.jpg")
        }
        let median = times.sorted()[times.count / 2]
        print("MailShelf launch read: \(bytes) bytes, median \(median), "
              + "fastest \(times.min()!), slowest \(times.max()!)")
    }
}
