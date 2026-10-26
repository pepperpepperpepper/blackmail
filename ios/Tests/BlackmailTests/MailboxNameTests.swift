import XCTest
@testable import Blackmail

/// What the screens call a folder (B-047, B-144).
///
/// IMAP names the inbox "INBOX". The sidebar's first row read that way, and
/// so did the list's title once he had tapped it, while the same list opened
/// at launch was titled "Inbox". Mail says "Inbox" everywhere, and "Sent"
/// and "Junk" for Gmail's Sent Mail and Spam (B-144). The sidebar, its
/// VoiceOver label, the list's title, the Move sheet and the label over his
/// letter brought in from Sent all show `Mailbox.displayName`; these check
/// the rule, that it leaves the names used on the wire alone, and that no
/// screen has gone back to the server's name.
final class MailboxNameTests: XCTestCase {

    private static let suite = "MailboxNameTests"

    override func tearDown() {
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        super.tearDown()
    }

    func testTheInboxIsInboxHoweverTheServerSpellsIt() {
        for spelling in ["INBOX", "Inbox", "inbox"] {
            let inbox = Mailbox(id: spelling, name: spelling, unreadCount: 3, role: .inbox)
            XCTAssertEqual(inbox.displayName, "Inbox", spelling)
            XCTAssertEqual(inbox.name, spelling, "the server's own name is kept")
        }
    }

    func testTheListIsCalledTheSameAtLaunchAndAfterTheTap() {
        // The folder the list opens on at launch, before the server has
        // been heard from, and the row LIST gives for the same folder.
        let listed = Mailbox(id: "INBOX", name: "INBOX", unreadCount: 6, role: .inbox)
        XCTAssertEqual(Mailbox.inboxBeforeListing.displayName, "Inbox")
        XCTAssertEqual(listed.displayName, Mailbox.inboxBeforeListing.displayName)
        // And it is the same folder: the sidebar finds the listed row for it.
        XCTAssertEqual([listed].firstIndex(matchingMailboxID: Mailbox.inboxBeforeListing.id), 0)
    }

    func testVoiceOverReadsTheNameTheRowShows() {
        let inbox = Mailbox(id: "INBOX", name: "INBOX", unreadCount: 6, role: .inbox)
        XCTAssertEqual(inbox.accessibilityLabel, "Inbox, 6 unread")
        let read = Mailbox(id: "INBOX", name: "INBOX", unreadCount: 0, role: .inbox)
        XCTAssertEqual(read.accessibilityLabel, "Inbox")
        let sent = Mailbox(id: "[Gmail]/Sent Mail", name: "Sent Mail", unreadCount: 2,
                           role: .sent, depth: 1)
        XCTAssertEqual(sent.accessibilityLabel, "Sent, 2 unread")
        let junk = Mailbox(id: "[Gmail]/Spam", name: "Spam", unreadCount: 0, role: .junk, depth: 1)
        XCTAssertEqual(junk.accessibilityLabel, "Junk")
    }

    /// Gmail's Sent Mail is "Sent" and its Spam "Junk", Mail's words, by
    /// the role LIST gives them, whatever they are called (B-144). The
    /// server's id and name are kept: they are what goes on the wire.
    func testSentAndJunkAreMailsWordsByTheirRole() {
        for (id, name) in [("[Gmail]/Sent Mail", "Sent Mail"), ("[Google Mail]/Sent Mail", "Sent Mail"),
                           ("Sent Items", "Sent Items"), ("Sent", "Sent")] {
            let sent = Mailbox(id: id, name: name, unreadCount: 0, role: .sent, depth: 1)
            XCTAssertEqual(sent.displayName, "Sent", name)
            XCTAssertEqual(sent.id, id, "the server's own id is kept")
            XCTAssertEqual(sent.name, name, "the server's own name is kept")
        }
        for (id, name) in [("[Gmail]/Spam", "Spam"), ("Junk E-mail", "Junk E-mail"), ("Junk", "Junk")] {
            let junk = Mailbox(id: id, name: name, unreadCount: 4, role: .junk, depth: 1)
            XCTAssertEqual(junk.displayName, "Junk", name)
            XCTAssertEqual(junk.id, id)
            XCTAssertEqual(junk.name, name)
        }
    }

    /// Only the Inbox, Sent and Junk are renamed, and only by their role:
    /// a label of his called "Sent Mail" or "Spam" keeps its name, as does
    /// one called "Sent", and Gmail's All Mail, Drafts and Trash keep
    /// theirs (B-144).
    func testOnlyTheInboxSentAndJunkRolesAreRenamed() {
        // A folder of his own under the inbox, and labels named like the
        // folders that are renamed, with no role.
        for name in ["Receipts", "Sent Mail", "Spam", "Sent", "Junk", "Inbox Old"] {
            let label = Mailbox(id: "INBOX/" + name, name: name, unreadCount: 0, role: nil, depth: 1)
            XCTAssertEqual(label.displayName, name)
            let top = Mailbox(id: name, name: name, unreadCount: 0, role: nil)
            XCTAssertEqual(top.displayName, name)
        }
        for (name, role) in [("All Mail", Mailbox.Role.archive), ("Drafts", .drafts),
                             ("Trash", .trash), ("Bin", .trash)] {
            let gmails = Mailbox(id: "[Gmail]/" + name, name: name, unreadCount: 0,
                                 role: role, depth: 1)
            XCTAssertEqual(gmails.displayName, name)
        }
        XCTAssertEqual(Mailbox(id: "outbox", name: "Outbox", unreadCount: 0, role: .outbox).displayName,
                       "Outbox")
    }

    func testTheListedInboxReadsInboxAndGmailsOtherFoldersKeepTheirNames() async throws {
        let server = ScriptedIMAPServer()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        let repository = IMAPMailRepository(account: server.account, password: server.password,
                                            transport: server.transportFactory,
                                            recipients: RecipientBook(defaults: defaults),
                                            shelf: keptShelf(for: server.account))

        let folders = try await repository.folders()
        let inbox = try XCTUnwrap(folders.first)
        XCTAssertEqual(inbox.displayName, "Inbox")
        // Unchanged: what the repository resolves and SELECTs.
        XCTAssertEqual(inbox.id, "INBOX")
        XCTAssertEqual(inbox.name, "INBOX")

        // Gmail's Sent Mail and Spam in Mail's words, in the pane's order;
        // the rest as LIST names them (B-144). Their names unchanged.
        let others = Array(folders.dropFirst())
        XCTAssertEqual(others.map(\.displayName),
                       ["Drafts", "Sent", "Junk", "Trash", "All Mail", "Starred"])
        XCTAssertEqual(others.map(\.name),
                       ["Drafts", "Sent Mail", "Spam", "Trash", "All Mail", "Starred"])
        XCTAssertEqual(others.map(\.id).filter { $0.hasPrefix("[Gmail]/") }.count, others.count)
        XCTAssertEqual(server.violations, [])
    }

    // MARK: - The screens

    /// The screens that show a folder, the sidebar's rows, the list's title
    /// and the Move sheet, are UIKit and built only for the device, so no
    /// test on this host runs them: one of them put back to `name` would
    /// leave every other test here passing. So their source is read instead.
    /// No line of it may show a folder's `name`, and each of the three shows
    /// `displayName`.
    func testNoScreenShowsTheServersNameForAFolder() throws {
        let ui = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/UI", isDirectory: true)
        let files = try FileManager.default
            .contentsOfDirectory(at: ui, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        // `mailbox.name`, `inbox.name`, `mailboxes[ip.row].name`,
        // `folders[i].name`: a folder, by whatever it is called, and its name.
        let serverName = try NSRegularExpression(
            pattern: #"\w*(mailbox|folder|inbox)\w*(\[[^\]]*\])?\.name\b"#,
            options: .caseInsensitive)

        var shown: [String] = []
        var showingDisplayName: Set<String> = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            if source.contains(".displayName") { showingDisplayName.insert(file.lastPathComponent) }
            for (n, line) in source.components(separatedBy: "\n").enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"),
                      serverName.firstMatch(in: code, range: NSRange(code.startIndex..., in: code))
                        != nil else { continue }
                shown.append("\(file.lastPathComponent):\(n + 1): \(code)")
            }
        }
        XCTAssertEqual(shown, [])
        XCTAssertTrue(showingDisplayName.isSuperset(of: ["MailboxListViewController.swift",
                                                         "MessageListViewController.swift",
                                                         "MoveMessageViewController.swift"]),
                      "\(showingDisplayName.sorted())")
    }
}
