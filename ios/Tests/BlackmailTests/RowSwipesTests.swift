import XCTest
@testable import Blackmail

/// Mail's drags on a row of the list (B-156), as iPadOS 18 Mail with its
/// factory Swipe Options: what each side shows, in what order and words,
/// for each kind of row; what Mail's other Swipe Options would show, set in
/// one place; More's sheet; and, read from the list's source, what each
/// button does: Edit mode's own batch, on every letter of the row.
final class RowSwipesTests: XCTestCase {

    private func row(read: Bool = true, flagged: Bool = false, role: Mailbox.Role? = .inbox,
                     local: Bool = false, canArchive: Bool = true) -> RowSwipes.Row {
        RowSwipes.Row(read: read, flagged: flagged, role: role, onThisIPadOnly: local,
                      canArchive: canArchive)
    }

    // MARK: - Mail's factory values

    /// His options are Mail's as it comes until his own are read: Swipe Left
    /// Flag, Swipe Right Mark as Read, and the Trash for what he discards.
    func testHisOptionsAreMailsFactoryValues() {
        XCTAssertEqual(SwipeOptions.his, SwipeOptions.factory)
        XCTAssertEqual(SwipeOptions.factory,
                       SwipeOptions(swipeLeft: .flag, swipeRight: .mark, discardInto: .trash))
    }

    /// A slow drag to the left shows More, Flag and Trash, the Trash at the
    /// row's edge and so what a full drag does; a drag to the right Mark as
    /// Read on a row with a dot, Mark as Unread on one without. Flag reads
    /// Unflag on a flagged row. Mail's words, its symbols, as UIKit takes
    /// them, the edge's first.
    func testADragShowsMoreFlagAndTrashToTheLeftAndTheReadMarkToTheRight() {
        let unread = RowSwipes.sides(for: row(read: false), editing: false)
        XCTAssertEqual(unread, RowSwipes.Sides(left: [.trash, .flag, .more], right: [.markRead]))
        XCTAssertEqual(unread.left.map(\.title), ["Trash", "Flag", "More"])
        XCTAssertEqual(unread.right.map(\.title), ["Read"])
        XCTAssertEqual(unread.left.map(\.symbol), ["trash.fill", "flag.fill", "ellipsis.circle.fill"])

        let read = RowSwipes.sides(for: row(read: true, flagged: true), editing: false)
        XCTAssertEqual(read, RowSwipes.Sides(left: [.trash, .unflag, .more], right: [.markUnread]))
        XCTAssertEqual(read.left.map(\.title), ["Trash", "Unflag", "More"])
        XCTAssertEqual(read.right.map(\.title), ["Unread"])
        XCTAssertEqual(read.right.map(\.symbol), ["envelope.badge.fill"])
        XCTAssertEqual(RowSwipes.Action.markRead.symbol, "envelope.open.fill")

        for role: Mailbox.Role? in [.inbox, .sent, .archive, .junk, .drafts, nil] {
            XCTAssertEqual(RowSwipes.sides(for: row(role: role), editing: false).left.first, .trash,
                           "\(String(describing: role))")
        }
    }

    /// Inside Trash the Trash is Delete, which erases, and asks first
    /// (`MessageListViewController.swiped`). Nothing in Edit mode, in the
    /// Outbox, or on a letter on this iPad only.
    func testInsideTrashItIsDeleteAndThereIsNothingInEditModeOrOnTheIPadsOwnLetters() {
        let trash = RowSwipes.sides(for: row(role: .trash), editing: false)
        XCTAssertEqual(trash.left, [.delete, .flag, .more])
        XCTAssertEqual(trash.left.first?.title, "Delete")
        XCTAssertEqual(trash.right, [.markUnread])
        XCTAssertEqual(RowSwipes.sides(for: row(), editing: true), .none)
        XCTAssertEqual(RowSwipes.sides(for: row(role: .outbox), editing: false), .none)
        XCTAssertEqual(RowSwipes.sides(for: row(role: .drafts, local: true), editing: false), .none)
        XCTAssertEqual(RowSwipes.Sides.none, RowSwipes.Sides(left: [], right: []))
    }

    /// Mail's other Swipe Options, set in `SwipeOptions` alone: None, Mark,
    /// Flag, Move Message or Archive on either side, and the Archive for
    /// what he discards, which takes the Trash's place, but where there is
    /// no All Mail to archive into, or the row is in it.
    func testMailsOtherSwipeOptionsAreSetInOnePlace() {
        func sides(_ row: RowSwipes.Row, _ left: SwipeOptions.Choice,
                   _ right: SwipeOptions.Choice,
                   _ discard: SwipeOptions.Discard = .trash) -> RowSwipes.Sides {
            RowSwipes.sides(for: row, editing: false,
                            options: SwipeOptions(swipeLeft: left, swipeRight: right,
                                                  discardInto: discard))
        }
        let plain = row(read: false)
        XCTAssertEqual(sides(plain, .none, .none), RowSwipes.Sides(left: [.trash, .more], right: []))
        XCTAssertEqual(sides(plain, .mark, .flag),
                       RowSwipes.Sides(left: [.trash, .markRead, .more], right: [.flag]))
        XCTAssertEqual(sides(plain, .move, .move),
                       RowSwipes.Sides(left: [.trash, .move, .more], right: [.move]))
        XCTAssertEqual(sides(plain, .archive, .archive),
                       RowSwipes.Sides(left: [.trash, .archive, .more], right: [.archive]))
        XCTAssertEqual(sides(row(canArchive: false), .archive, .archive),
                       RowSwipes.Sides(left: [.trash, .more], right: []))
        XCTAssertEqual(sides(plain, .flag, .mark, .archive),
                       RowSwipes.Sides(left: [.archive, .flag, .more], right: [.markRead]))
        XCTAssertEqual(sides(plain, .archive, .mark, .archive),
                       RowSwipes.Sides(left: [.archive, .more], right: [.markRead]), "once")
        XCTAssertEqual(sides(row(canArchive: false), .flag, .mark, .archive).left.first, .trash)
        XCTAssertEqual(sides(row(role: .trash), .flag, .mark, .archive).left.first, .delete)
        XCTAssertEqual(SwipeOptions.Choice.allCases, [.none, .mark, .flag, .move, .archive])
        XCTAssertEqual([RowSwipes.Action.archive, .move].map(\.title), ["Archive", "Move"])
    }

    /// More's sheet: Reply, Reply All, Forward, then Trash Message, then
    /// Flag or Unflag and Mark as Unread or Mark as Read as the row is, in
    /// the Flag sheet's words, and Move Message, and Cancel, in the order of
    /// Mail's sheet. Archive Message in Trash Message's place where the
    /// account discards into the Archive and there is one; inside Trash
    /// Delete Message.
    func testMoreOpensMailsSheetWithTheActionsBlackmailHas() {
        XCTAssertEqual(RowMore.items(for: row(read: true, flagged: false)).map(\.title),
                       ["Reply", "Reply All", "Forward", "Trash Message", "Flag", "Mark as Unread",
                        "Move Message"])
        XCTAssertEqual(RowMore.items(for: row(read: false, flagged: true)).map(\.title),
                       ["Reply", "Reply All", "Forward", "Trash Message", "Unflag", "Mark as Read",
                        "Move Message"])
        XCTAssertEqual(RowMore.items(for: row(role: .trash))[3], .deleteMessage)
        XCTAssertEqual(RowMore.Item.deleteMessage.title, "Delete Message")
        let archiving = SwipeOptions(swipeLeft: .flag, swipeRight: .mark, discardInto: .archive)
        XCTAssertEqual(RowMore.items(for: row(), options: archiving)[3].title, "Archive Message")
        XCTAssertEqual(RowMore.items(for: row(canArchive: false), options: archiving)[3],
                       .trashMessage)
        XCTAssertEqual(RowMore.items(for: row(role: .trash), options: archiving)[3], .deleteMessage)
        XCTAssertEqual(RowMore.cancel, "Cancel")
    }

    // MARK: - The list, read

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

    private func part(of code: String, from start: String, through end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start), start)
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex), end)
        return String(code[from.lowerBound..<to.upperBound])
    }

    /// Both sides come from `RowSwipes` for the row as it is, never nil,
    /// each button `.normal` in Mail's colour, the edge's done by a full
    /// drag. The Trash is Edit mode's Delete, at once, of every letter of
    /// the row (`runBatch`: the rows off at the tap, the pane emptied if it
    /// shows one, a refused letter back where it stood, a step of Undo);
    /// inside Trash it asks first, and the row slides back while it does.
    /// Flag and the read mark go by `ListBatch` on the letters they change;
    /// More's Reply goes to the pane, which makes the letter.
    func testEachButtonDoesWhatEditModeDoesOnEveryLetterOfTheRow() throws {
        let list = try source("UI/MessageListViewController.swift")
        for line in [
            "trailingSwipeActionsConfigurationForRowAt ip: IndexPath) -> UISwipeActionsConfiguration? "
                + "{ swipes(at: ip, \\.left) }",
            "leadingSwipeActionsConfigurationForRowAt ip: IndexPath) -> UISwipeActionsConfiguration? "
                + "{ swipes(at: ip, \\.right) }",
            "guard threads.indices.contains(ip.row) else { return UISwipeActionsConfiguration(actions: "
                + "[]) }",
            "let sides = RowSwipes.sides(for: swipeRow(thread), editing: inEditMode)",
            "let button = UIContextualAction(style: .normal, title: action.title) { [weak self] _, _, "
                + "done in done(self?.swiped(action, on: RowKey(thread)) ?? false) }",
            "configuration.performsFirstActionWithFullSwipe = true",
            "case .trash, .delete: return Theme.destructive case .flag, .unflag: return Theme.flagTint "
                + "case .markRead, .markUnread: return Theme.tintBlue",
            "case .more: return Theme.swipeMore",
            "onThisIPadOnly: isOutbox || thread.messages.contains { LocalDraft.key(ofRow: $0.id) != nil }",
            "return (threads[row], onServer(ListBatch.letters(ticked: [row], in: threads)))",
            // By its id and its folder: two folders' letters can share an id.
            "init(_ thread: MessageThread) { id = thread.id folder = thread.newest.mailboxID }",
            "guard let row = threads.firstIndex(where: { RowKey($0) == key }) else { return nil }",
            "case .trash: runBatch(.delete, on: chosen, saying: StatusLine.deleting) return true",
            "case .delete: guard let question = EraseQuestion.before(deleting: chosen, role: { "
                + "self.role(of: $0) }) else { runBatch(.delete, on: chosen, saying: "
                + "StatusLine.deleting) return true } EraseConfirmation.ask(question, on: self) { "
                + "[weak self] in self?.runBatch(.delete, on: chosen, saying: StatusLine.deleting) } "
                + "return false",
            "case .flag, .unflag: return mark(.flag(action == .flag), on: key)",
            "case .markRead, .markUnread: return mark(.read(action == .markRead), on: key)",
            "case .more: showMore(for: key) return true",
            "guard !changing.isEmpty, !changing.contains(where: { letters.flagOnItsWay($0.id) || "
                + "letters.dot(on: $0)?.onItsWay == true }) else { return false }",
            "onAnswer?(row.thread.newest, item == .replyAll, item == .forward, place)",
            // More's Trash Message is the drag's own Trash; inside Trash its
            // Delete Message asks first, as the drag's Delete.
            "for item in RowMore.items(for: swipeRow(row.thread)) {",
            "case .trashMessage: _ = swiped(.trash, on: key) case .archiveMessage: _ = "
                + "swiped(.archive, on: key) case .deleteMessage: _ = swiped(.delete, on: key)",
            "self.runBatch(.move(to: destination), on: row.letters, saying: StatusLine.moving)",
        ] {
            XCTAssertTrue(list.contains(line), line)
        }
        XCTAssertFalse(list.contains("style: .destructive, title:"),
                       "a destructive button would take the row out of the table itself")
        XCTAssertFalse(list.contains("commit editingStyle"))
        let swiped = try part(of: list, from: "private func swiped(", through: "case .more:")
        XCTAssertTrue(swiped.contains("EraseQuestion.before(deleting: chosen"))
        XCTAssertEqual(swiped.components(separatedBy: "EraseConfirmation.ask").count - 1, 1,
                       "the one question, inside Trash")
        XCTAssertFalse(swiped.contains("try?"))

        let root = try source("UI/RootViewController.swift")
        XCTAssertTrue(root.contains("list.onAnswer = { [weak self] letter, all, forward, row in "
            + "self?.detail.answer(letter, all: all, forward: forward, over: row) }"))
        let pane = try source("UI/MessageDetailViewController.swift")
        for line in [
            "guard answering == nil else { return } answering = letter.id",
            "m = try await repository.openLetter(letter)",
            "guard forward ? ReplyFiles.forwardAsks(m) : ReplyFiles.asks(m) else { return "
                + "self.openCompose(replyTo: m, all: all, forward: forward) } "
                + "self.askAboutFiles(over: row) { [weak self] in self?.openCompose(replyTo: m, "
                + "all: all, forward: forward, included: $0) }",
        ] {
            XCTAssertTrue(pane.contains(line), line)
        }
    }

    /// Edit mode is the list's own, on from Edit to Done, and never the
    /// table's `isEditing`, which UIKit turns on while a drag holds a row's
    /// buttons open: read as Edit mode, every button did nothing, and the
    /// row slid back. Nothing in the list reads the table's; the swipe's
    /// start and end are not handed to UITableViewController, which would
    /// put the controller into editing.
    func testEditModeIsTheListsOwnAndNotTheTablesWhichADragTurnsOn() throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertFalse(list.contains("tableView.isEditing"))
        XCTAssertFalse(list.contains("t.isEditing"))
        XCTAssertTrue(list.contains("private var inEditMode = false"))
        XCTAssertTrue(list.contains("let editing = !inEditMode inEditMode = editing "
            + "tableView.setEditing(editing, animated: true)"))
        XCTAssertEqual(list.components(separatedBy: "inEditMode = ").count - 1, 2,
                       "declared, and set by Edit and Done alone")
        for line in [
            "let sides = RowSwipes.sides(for: swipeRow(thread), editing: inEditMode)",
            "guard !inEditMode, let row = lettersOfRow(key), !row.letters.isEmpty else {",
            "private func chose(_ item: RowMore.Item, on key: RowKey) { guard !inEditMode, ",
            "override func tableView(_ t: UITableView, willBeginEditingRowAt ip: IndexPath) {}",
            "override func tableView(_ t: UITableView, didEndEditingRowAt ip: IndexPath?) { "
                + "highlightLetterInPane() }",
        ] {
            XCTAssertTrue(list.contains(line), line)
        }
        XCTAssertFalse(list.contains("super.tableView(t, willBeginEditingRowAt"))
        XCTAssertFalse(list.contains("super.tableView(t, didEndEditingRowAt"))
    }

    /// The colours are Mail's and the theme's: More's grey and Archive's
    /// purple, the rest the theme's red, orange and blue.
    func testTheButtonsHaveMailsColours() throws {
        let theme = try source("Theme/Theme.swift")
        XCTAssertTrue(theme.contains("static let swipeMore = UIColor(red: 142 / 255, green: 142 / 255, "
            + "blue: 147 / 255, alpha: 1)"))
        XCTAssertTrue(theme.contains("static let swipeArchive = UIColor(red: 191 / 255, green: 90 / "
            + "255, blue: 242 / 255, alpha: 1)"))
    }
}
