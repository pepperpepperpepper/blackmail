import XCTest
@testable import Blackmail

/// The drags on a row, More, Ask Before Deleting and Undo as Mail's
/// (B-175), from the side-by-side round of 2026-10-27: More's "Trash" and
/// "Move Message…", in Mail's order with Archive Message after it
/// (comparison C-04); under Ask Before Deleting, only the pane's Trash and
/// the Edit bar's ask, a slow drag's Trash and More's going at once (C-08);
/// and a read mark from a full drag a step of Undo, "Undo Read" or "Undo
/// Unread" (C-07b). How an Undo of it goes on the server is
/// `UndoMovesTests`'.
///
/// The rules are `RowMore`'s, `DiscardQuestion`'s and `UndoableRead`'s,
/// run here; the controllers are UIKit, so how they use them is read from
/// their source, comment lines out, as `RowSwipesTests` reads it.
final class DragsLikeMailTests: XCTestCase {

    private func row(read: Bool = true, flagged: Bool = false, role: Mailbox.Role? = .inbox,
                     canArchive: Bool = true) -> RowSwipes.Row {
        RowSwipes.Row(read: read, flagged: flagged, role: role, onThisIPadOnly: false,
                      canArchive: canArchive)
    }

    // MARK: - More (D1, D2)

    /// Mail's words: "Trash", the Edit bar's, where it said "Trash
    /// Message"; "Move Message…" with Mail's dots (`MOVE_MESSAGE`); and
    /// Mail's order, Move Message… before Archive Message and Move to Junk.
    func testMoresWordsAndOrderAreMails() {
        XCTAssertEqual(RowMore.Item.trashMessage.title, "Trash")
        XCTAssertEqual(RowMore.Item.trashMessage.title, EditBar.trash)
        XCTAssertEqual(RowMore.Item.moveMessage.title, "Move Message\u{2026}")
        XCTAssertEqual(RowMore.Item.archiveMessage.title, "Archive Message")
        XCTAssertEqual(RowMore.Item.deleteMessage.title, "Delete Message")
        let junk = Mailbox(id: "[Gmail]/Spam", name: "Spam", unreadCount: 0, role: .junk)
        XCTAssertEqual(RowMore.items(for: row(), junk: junk),
                       [.reply, .replyAll, .forward, .trashMessage, .flag, .markAsUnread,
                        .moveMessage, .archiveMessage, .moveToJunk(junk)])
        XCTAssertEqual(RowMore.items(for: row(read: false, flagged: true)),
                       [.reply, .replyAll, .forward, .trashMessage, .unflag, .markAsRead,
                        .moveMessage, .archiveMessage])
    }

    /// Archive Message where the row can be archived, by the rule every
    /// Archive goes by (`SwipeOptions.archives`): not without an All Mail
    /// or from it, nor in Drafts or the Trash, where the fourth item is
    /// Delete Message; and once, in the fourth place, where the account
    /// discards into the Archive.
    func testArchiveMessageWhereTheRowCanBeArchivedAndOnce() {
        XCTAssertFalse(RowMore.items(for: row(canArchive: false)).contains(.archiveMessage))
        XCTAssertFalse(RowMore.items(for: row(role: .drafts)).contains(.archiveMessage))
        let trash = RowMore.items(for: row(role: .trash))
        XCTAssertEqual(trash[3], .deleteMessage)
        XCTAssertFalse(trash.contains(.archiveMessage))
        XCTAssertTrue(RowMore.items(for: row(role: nil)).contains(.archiveMessage), "a label")
        let archiving = SwipeOptions(swipeLeft: .flag, swipeRight: .mark, discardInto: .archive)
        let items = RowMore.items(for: row(), options: archiving)
        XCTAssertEqual(items[3], .archiveMessage)
        XCTAssertEqual(items.filter { $0 == .archiveMessage }.count, 1)
        XCTAssertFalse(items.contains(.trashMessage))
    }

    // MARK: - Ask Before Deleting (D3, D4)

    /// On: the pane's Trash and the Edit bar's ask, in Mail's words; a slow
    /// drag's button tapped, More's item and a full drag ask nothing, Trash
    /// or Archive, of a letter or of a conversation.
    func testOnlyThePaneAndTheEditBarAsk() {
        for from: DiscardQuestion.From in [.rowButton, .more, .fullDrag] {
            for verb: DiscardQuestion.Verb in [.trash, .archive] {
                for count in [1, 3] {
                    XCTAssertNil(DiscardQuestion.before(verb, letters: count, from: from, asking: true),
                                 "\(from) \(verb) \(count)")
                }
            }
        }
        XCTAssertEqual(DiscardQuestion.before(.trash, letters: 1, from: .pane, asking: true)?.button,
                       "Trash Message")
        XCTAssertEqual(DiscardQuestion.before(.archive, letters: 1, from: .pane, asking: true)?.button,
                       "Archive Message")
        XCTAssertEqual(DiscardQuestion.before(.trash, letters: 2, from: .editBar, asking: true)?.button,
                       "Trash 2 Messages")
    }

    // MARK: - Undo (D5)

    private func letter(_ id: String, read: Bool = true) -> MessageSummary {
        MessageSummary(id: id, mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                       subject: "Lunch on Sunday", preview: "", date: Date(timeIntervalSince1970: 0),
                       isRead: read, isFlagged: false, gmailMessageID: 7)
    }

    /// A read mark the server took is a step: "Undo Read" for a Read,
    /// "Undo Unread" for an Unread, Mail's words (`OPERATION_READ_DESC`,
    /// `OPERATION_UNREAD_DESC`); of the letters taken, not a letter kept on
    /// the iPad; nothing for none, and none for a Flag, a Trash or a Move.
    func testAReadMarkIsAStepOfUndoInMailsWords() throws {
        let one = letter("1/10"), two = letter("1/11", read: false)
        let unread = try XCTUnwrap(UndoableRead.after(.read(false), took: [one, two]))
        XCTAssertEqual(unread, UndoableRead(read: false, letters: [one, two]))
        XCTAssertEqual(unread.actionName, "Unread")
        XCTAssertEqual(Undoable.read(unread).actionName, "Unread")
        XCTAssertEqual(UndoableRead.after(.read(true), took: [two])?.actionName, "Read")
        let kept = letter("local:abc")
        XCTAssertEqual(UndoableRead.after(.read(true), took: [kept, one])?.letters, [one])
        XCTAssertNil(UndoableRead.after(.read(true), took: [kept]))
        XCTAssertNil(UndoableRead.after(.read(true), took: []))
        let notes = Mailbox(id: "Notes", name: "Notes", unreadCount: 0, role: nil)
        for action: PaneAction in [.flag(true), .flag(false), .delete, .move(to: notes)] {
            XCTAssertNil(UndoableRead.after(action, took: [one]), "\(action)")
        }
    }

    /// The list makes the step from a full drag's read mark alone, after
    /// the server has taken it, a Flag's step as before; More's marks and
    /// a button tapped make none. The container undoes it with
    /// `UndoMoves`, and what failed is a step again.
    func testAFullDragsReadMarkIsTheOnlyOneMadeAStep() throws {
        let list = try source("UI/MessageListViewController.swift")
        for line in [
            "case .markRead, .markUnread: return mark(.read(action == .markRead), on: key, "
                + "undoable: from == .fullDrag)",
            "private func mark(_ action: PaneAction, on key: RowKey, undoable: Bool = false) -> Bool {",
            "let took = changing.filter { outcome.taken.contains($0.id) } "
                + "if let step = UndoableFlag.after(action, took: took) { "
                + "self.onUndoable?(.flag(step), self.letters) } "
                + "else if undoable, let step = UndoableRead.after(action, took: took) { "
                + "self.onUndoable?(.read(step), self.letters) }",
            "case .markAsRead: _ = mark(.read(true), on: key)",
            "case .markAsUnread: _ = mark(.read(false), on: key)",
            "done(self.swiped(action, on: RowKey(thread), from: whole ? .fullDrag : .rowButton))",
        ] {
            XCTAssertTrue(list.contains(line), line)
        }
        XCTAssertEqual(list.components(separatedBy: "undoable: ").count - 1, 2,
                       "the full drag's, and none by default")
        XCTAssertEqual(list.components(separatedBy: "UndoableRead.").count - 1, 1)

        let root = try source("UI/RootViewController.swift")
        for line in [
            "case .read(let read): undo(read, into: letters)",
            "private func undo(_ step: UndoableRead, into letters: ListLetters?) { "
                + "Task { @MainActor [weak self] in guard let self else { return } "
                + "let outcome = await UndoMoves.run(step, repository: self.repository, list: letters, "
                + "requestSweep: { [weak self] in self?.refreshMailboxes() }) "
                + "if let left = outcome.left { self.canUndo(.read(left), from: letters) } "
                + "if let refusal = outcome.refusal { ErrorPresenter.show(reaching: refusal, on: self) } } }",
        ] {
            XCTAssertTrue(root.contains(line), line)
        }
    }

    // MARK: - Reading the source

    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }
}
