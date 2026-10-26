import XCTest
@testable import Blackmail

/// Move to Junk, and Move to Inbox inside Junk, at the end of the Flag
/// button's sheet (B-106, ruled 2026-10-26: copy Apple Mail): when each is
/// offered, and what each sends, over `ScriptedIMAPServer` through the
/// shipping repository with the list's own letters.
final class MoveToJunkTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "MoveToJunkTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!

    private let spam = Mailbox(id: Server.spam, name: "Spam", unreadCount: 0, role: .junk)
    private let inbox = Mailbox(id: Server.inbox, name: "INBOX", unreadCount: 0, role: .inbox)

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

    // MARK: - When it is offered

    /// Last, after Flag and the read mark, from every folder but Junk:
    /// the Inbox, All Mail, Sent Mail, Trash and a label.
    func testEveryFolderButSpamGivesMoveToJunkLast() {
        let folders = FlagMenu.Folders(role: nil, junk: spam, inbox: inbox)
        for role: Mailbox.Role? in [.inbox, .archive, .sent, .trash, nil] {
            var here = folders
            here.role = role
            XCTAssertEqual(FlagMenu.items(flagged: false, read: true, local: false, in: here),
                           [.flag, .markAsUnread, .moveToJunk(spam)], "\(String(describing: role))")
            XCTAssertEqual(FlagMenu.items(flagged: true, read: false, local: false, in: here),
                           [.unflag, .markAsRead, .moveToJunk(spam)])
        }
    }

    /// Inside Junk, Move to Inbox in its place, to the Inbox listed.
    func testSpamGivesMoveToInbox() {
        let here = FlagMenu.Folders(role: .junk, junk: spam, inbox: inbox)
        XCTAssertEqual(FlagMenu.items(flagged: false, read: true, local: false, in: here),
                       [.flag, .markAsUnread, .moveToInbox(inbox)])
        let noInbox = FlagMenu.Folders(role: .junk, junk: spam, inbox: nil)
        XCTAssertEqual(FlagMenu.items(flagged: false, read: true, local: false, in: noInbox),
                       [.flag, .markAsUnread])
    }

    /// No folder with the `\Junk` role listed, as when Spam's "Show in
    /// IMAP" is off: no third item. Nor for a letter kept on the iPad, nor
    /// with no folders handed at all.
    func testNoJunkFolderListedGivesNoThirdItem() {
        let none = FlagMenu.Folders(role: .inbox, junk: nil, inbox: inbox)
        XCTAssertEqual(FlagMenu.items(flagged: false, read: true, local: false, in: none),
                       [.flag, .markAsUnread])
        let listed = FlagMenu.Folders(role: .inbox, junk: spam, inbox: inbox)
        XCTAssertEqual(FlagMenu.items(flagged: false, read: true, local: true, in: listed), [.flag])
        XCTAssertEqual(FlagMenu.items(flagged: false, read: true, local: false),
                       [.flag, .markAsUnread])
    }

    func testTheWords() {
        XCTAssertEqual(FlagMenu.Item.moveToJunk(spam).title, "Move to Junk")
        XCTAssertEqual(FlagMenu.Item.moveToInbox(inbox).title, "Move to Inbox")
    }

    /// Spam's "Show in IMAP" off: LIST does not name it, so the folders the
    /// sheet is handed have no `\Junk` role, and there is no third item.
    func testWithSpamNotShownInIMAPThereIsNoJunkFolderToMoveTo() async throws {
        server.unlistedMailboxes = [Server.spam]
        let repository = makeRepository()
        let listed = try await repository.listMailboxes()
        XCTAssertNil(listed.first { $0.role == .junk })
        XCTAssertNotNil(listed.first { $0.role == .inbox })
        let here = FlagMenu.Folders(role: .inbox, junk: listed.first { $0.role == .junk },
                                    inbox: listed.first { $0.role == .inbox })
        XCTAssertEqual(FlagMenu.items(flagged: false, read: true, local: false, in: here),
                       [.flag, .markAsUnread])
    }

    // MARK: - What it sends

    /// One UID MOVE, to the folder LIST names `\Junk`: the row goes at the
    /// tap, before the server has answered, and the letter is in Spam and
    /// nowhere else.
    func testMoveToJunkSendsOneMoveToTheFolderListedAsJunk() async throws {
        let repository = makeRepository()
        let listed = try await repository.listMailboxes()
        let junk = try XCTUnwrap(listed.first { $0.role == .junk })
        XCTAssertEqual(junk.id, Server.spam)
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = rows[12]
        XCTAssertTrue(letter.isRead)
        let list = await makeList(folder: rows)
        server.clearLog()

        server.holdReplies(to: "UID MOVE")
        let moved = Task {
            await PaneActions.run(.move(to: junk), on: letter, inFolderWithRole: .inbox, list: list,
                                  repository: repository, requestSweep: {})
        }
        try await until { self.server.log.contains { $0.verb == "UID MOVE" } }
        let atTheTap = await list.shown.map(\.id)
        XCTAssertFalse(atTheTap.contains(letter.id))
        await server.releaseReplies(to: "UID MOVE")
        let done = try await finishing { await moved.value }

        XCTAssertTrue(done)
        XCTAssertEqual(server.log.map(\.command), ["UID MOVE \(uid(letter.id)) \"\(Server.spam)\""])
        XCTAssertFalse(server.uids(in: Server.inbox).contains(uid(letter.id)))
        XCTAssertTrue(server.uids(in: Server.spam).contains {
            server.gmailMessageID(uid: $0, in: Server.spam) == letter.gmailMessageID
        })
        let after = await list.shown.map(\.id)
        XCTAssertFalse(after.contains(letter.id))
    }

    /// Refused, the row comes back where it stood, and the letter is still
    /// in the Inbox.
    func testAMoveToJunkTheServerRefusesPutsTheRowBack() async throws {
        let repository = makeRepository()
        let listed = try await repository.listMailboxes()
        let junk = try XCTUnwrap(listed.first { $0.role == .junk })
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = rows[12]
        let list = await makeList(folder: rows)
        await server.resetConnections()

        let done = await PaneActions.run(.move(to: junk), on: letter, inFolderWithRole: .inbox,
                                         list: list, repository: repository, requestSweep: {})

        XCTAssertFalse(done)
        let shown = await list.shown.map(\.id)
        XCTAssertEqual(shown, rows.map(\.id))
        XCTAssertEqual(server.lostWrites.map(\.verb), ["UID MOVE"])
        XCTAssertTrue(server.uids(in: Server.inbox).contains(uid(letter.id)))
    }

    /// Inside Junk, Move to Inbox: one UID MOVE to the Inbox LIST names,
    /// and the row leaves Junk.
    func testMoveToInboxFromSpamSendsOneMoveToTheInbox() async throws {
        let repository = makeRepository()
        let listed = try await repository.listMailboxes()
        let junk = try XCTUnwrap(listed.first { $0.role == .junk })
        let inbox = try XCTUnwrap(listed.first { $0.role == .inbox })
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        try await repository.move(rows[12], to: junk.id)
        let spamRows = try await repository.listMessages(in: junk.id, beforeUID: nil, limit: 50)
        let letter = try XCTUnwrap(spamRows.first { $0.gmailMessageID == rows[12].gmailMessageID })
        let list = await makeList(folder: spamRows)
        server.clearLog()

        let done = await PaneActions.run(.move(to: inbox), on: letter, inFolderWithRole: .junk,
                                         list: list, repository: repository, requestSweep: {})

        XCTAssertTrue(done)
        XCTAssertEqual(server.log.filter { $0.verb == "UID MOVE" }.map(\.command),
                       ["UID MOVE \(uid(letter.id)) \"\(Server.inbox)\""])
        XCTAssertTrue(server.uids(in: Server.inbox).contains {
            server.gmailMessageID(uid: $0, in: Server.inbox) == letter.gmailMessageID
        })
        let shown = await list.shown.map(\.id)
        XCTAssertFalse(shown.contains(letter.id))
    }

    // MARK: - Read from the source

    /// The pane offers them from the folders the container hands it, and
    /// moves the one letter the toolbar acts on as its Move does: emptied
    /// at the tap, through `perform`, which says "Moving…". The container
    /// hands the folders LIST named by their roles.
    func testThePaneMovesTheOneLetterToTheFoldersListed() throws {
        let pane = try source("UI/MessageDetailViewController.swift")
        let chosen = try section(of: pane, from: "private func choose(", to: "private func setFlag(")
        XCTAssertTrue(chosen.contains("case .moveToJunk(let folder), .moveToInbox(let folder): "
                                      + "guard let s = summary else { return } move(s, to: folder)"), chosen)
        let move = try section(of: pane, from: "private func move(_ s: MessageSummary, to destination: Mailbox) {",
                               to: "@objc private func deleteTapped()")
        XCTAssertTrue(move.contains("if summary?.id == s.id { showEmpty() } Task { @MainActor in "
                                    + "if let refused = await self.performed(.move(to: destination), on: s) { "
                                    + "ErrorPresenter.show(reaching: refused, on: self) } } }"), move)
        XCTAssertTrue(pane.contains("excluding: s.mailboxID) { [weak self] destination in "
                                    + "self?.move(s, to: destination) }"))
        XCTAssertTrue(pane.contains("in: foldersForJunk?(s) ?? FlagMenu.Folders())"))

        let root = try source("UI/RootViewController.swift")
        XCTAssertTrue(root.contains(
            "detail.foldersForJunk = { [weak self] letter in guard let self else { return FlagMenu.Folders() } "
            + "let folders = [self.list.shownMailbox] + self.mailboxList.folders "
            + "return FlagMenu.Folders(role: folders.role(of: letter.mailboxID), "
            + "junk: self.mailboxList.mailbox(for: .junk), inbox: self.mailboxList.mailbox(for: .inbox)) }"))
        XCTAssertTrue(root.contains("if case .move = action { moving = self.list.working(StatusLine.moving) }"))
    }

    /// The words are the sheet's alone: never in Edit mode, where Select
    /// All is the thirty-thousand-letter accident, nor anywhere else.
    func testMoveToJunkIsInTheFlagButtonsSheetAlone() throws {
        for file in try sources() {
            let code = try source(file, under: "")
            for word in ["Move to Junk", "Move to Inbox", "Move to Spam", "moveToJunk", "moveToInbox"]
            where file != "Blackmail/Mail/FlagMenu.swift" && file != "Blackmail/UI/MessageDetailViewController.swift" {
                XCTAssertFalse(code.contains(word), "\(file): \(word)")
            }
        }
        let flagMenu = try String(contentsOf: sourceRoot.appendingPathComponent("Blackmail/Mail/FlagMenu.swift"),
                                  encoding: .utf8)
        XCTAssertTrue(flagMenu.contains("case .moveToJunk: return \"Move to Junk\""))
        let pane = try String(contentsOf: sourceRoot
            .appendingPathComponent("Blackmail/UI/MessageDetailViewController.swift"), encoding: .utf8)
        XCTAssertFalse(pane.contains("\"Move to"), "the pane's words are FlagMenu's")
    }

    // MARK: - Helpers

    private func makeRepository() -> IMAPMailRepository {
        IMAPMailRepository(account: server.account, password: server.password,
                           transport: server.transportFactory, recipients: book,
                           shelf: keptShelf(for: server.account))
    }

    @MainActor
    private func makeList(folder: [MessageSummary]) -> ListLetters {
        let list = ListLetters()
        _ = list.fetchedAfresh(folder)
        return list
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

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources", isDirectory: true)
    }

    private func sources() throws -> [String] {
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sourceRoot,
                                                                  includingPropertiesForKeys: nil))
        let base = sourceRoot.standardizedFileURL.path + "/"
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { String($0.standardizedFileURL.path.dropFirst(base.count)) }
            .sorted()
    }

    /// The file's code with its comment lines dropped and its spacing made
    /// single, so a line is found however it is wrapped.
    private func source(_ path: String, under target: String = "Blackmail/") throws -> String {
        try String(contentsOf: sourceRoot.appendingPathComponent(target + path), encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    private func section(of code: String, from start: String, to end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start), start)
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex), end)
        return String(code[from.lowerBound..<to.lowerBound])
    }
}
