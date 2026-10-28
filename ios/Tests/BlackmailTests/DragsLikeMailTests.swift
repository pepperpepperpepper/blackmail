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

    // MARK: - Undo after the pane's Delete (the plan's Q1)

    private func trashStep(of row: MessageSummary) -> UndoableMove {
        UndoableMove(kind: .trash, letters: [UndoableMove.Letter(
            row: row, landing: MoveLanding(folder: "[Gmail]/Trash", id: "9/41", letter: 7))])
    }

    /// After a Delete the server took, the next letter's read mark is a
    /// step on top of the Trash's, whichever the server answers first: a
    /// mark taken first waits for the Trash and comes with it, after it; a
    /// mark taken after it comes at once. "Read", of the letters taken, not
    /// one kept on the iPad.
    @MainActor
    func testAfterThePanesDeleteTheReadMarkGoesOnTopOfTheTrash() throws {
        let gone = letter("1/10"), next = letter("1/11", read: false)
        let after = PaneUndoSteps(after: .delete)
        XCTAssertEqual(after.answered(trashStep(of: gone)), nil, "nothing waiting")
        let read = try XCTUnwrap(after.readTaken([next]))
        XCTAssertEqual(read, UndoableRead(read: true, letters: [next]))
        XCTAssertEqual(Undoable.read(read).actionName, "Read")

        let first = PaneUndoSteps(after: .delete)
        XCTAssertNil(first.readTaken([next]), "waits for the Trash")
        XCTAssertEqual(first.answered(trashStep(of: gone)), UndoableRead(read: true, letters: [next]))
        XCTAssertNil(first.answered(trashStep(of: gone)), "answered once")

        let kept = PaneUndoSteps(after: .delete)
        _ = kept.answered(trashStep(of: gone))
        XCTAssertNil(kept.readTaken([letter("local:abc")]))
        XCTAssertNil(kept.readTaken([]))
        XCTAssertEqual(kept.readTaken([letter("local:abc"), next])?.letters, [next])
    }

    /// Only as seen: no step for the read mark after a Delete refused, or
    /// one with no step (an erase inside Trash), whether the mark came
    /// before the answer or after it; nor after a Move, a Flag or a read
    /// mark from the pane.
    @MainActor
    func testTheReadMarkIsNoStepWhereTheDeleteMadeNone() {
        let gone = letter("1/10"), next = letter("1/11", read: false)
        let refusedFirst = PaneUndoSteps(after: .delete)
        XCTAssertNil(refusedFirst.answered(nil))
        XCTAssertNil(refusedFirst.readTaken([next]))

        let markFirst = PaneUndoSteps(after: .delete)
        XCTAssertNil(markFirst.readTaken([next]))
        XCTAssertNil(markFirst.answered(nil), "the waiting mark dropped")
        XCTAssertNil(markFirst.readTaken([next]))

        let notes = Mailbox(id: "Notes", name: "Notes", unreadCount: 0, role: nil)
        for action: PaneAction in [.move(to: notes), .flag(true), .read(false)] {
            let steps = PaneUndoSteps(after: action)
            XCTAssertNil(steps.readTaken([next]), "\(action)")
            XCTAssertNil(steps.answered(trashStep(of: gone)), "\(action)")
            XCTAssertNil(steps.readTaken([next]), "\(action)")
        }
    }

    /// The container: the Trash's step added as before, then the read
    /// mark's, from `PaneUndoSteps`, each a step of its own once the undo
    /// manager's open group has closed; a refusal answers it with none.
    /// The list hands the container the letters the server took the mark
    /// on, once every STORE is answered, from the letter it opens after
    /// the pane's Delete alone.
    func testThePanesDeleteMakesTheReadMarkAStepOfItsOwn() throws {
        let root = try source("UI/RootViewController.swift")
        for line in [
            "let letters = list.letters let steps = PaneUndoSteps(after: action)",
            "if let step { self?.canUndo(.move(step), from: letters) } "
                + "if let read = steps.answered(step) { self?.canUndoAlone(.read(read), from: letters) }",
            "taken: { guard let next else { return } list.openNext(next, readTaken: { "
                + "[weak self, weak letters] took in if let read = steps.readTaken(took) { "
                + "self?.canUndoAlone(.read(read), from: letters) } }) })",
            "if refused != nil { _ = steps.answered(nil) }",
            "private func canUndoAlone(_ step: Undoable, from letters: ListLetters?) { "
                + "guard undos.groupingLevel > 0 else { return canUndo(step, from: letters) } "
                + "waitingSteps.append(UndoStep(step, from: letters)) }",
            "NotificationCenter.default.addObserver(self, selector: #selector(undoGroupClosed), "
                + "name: .NSUndoManagerDidCloseUndoGroup, object: undos)",
            "@objc private func undoGroupClosed() { guard !waitingSteps.isEmpty else { return } "
                + "Task { @MainActor [weak self] in guard let self else { return } "
                + "let waiting = self.waitingSteps self.waitingSteps = [] "
                + "for box in waiting { self.canUndoAlone(box.step, from: box.letters) } } }",
        ] {
            XCTAssertTrue(root.contains(line), line)
        }
        XCTAssertEqual(root.components(separatedBy: "PaneUndoSteps(").count - 1, 1)
        XCTAssertEqual(root.components(separatedBy: "readTaken: ").count - 1, 1)

        let list = try source("UI/MessageListViewController.swift")
        for line in [
            "let sends = marked.map { sendRead($0) } guard let taken else { return } "
                + "Task { @MainActor in var took: [MessageSummary] = [] "
                + "for (m, send) in zip(marked, sends) { if await send.value { took.append(m) } } "
                + "taken(took) } }",
            "private func sendRead(_ summary: MessageSummary) -> Task<Bool, Never> {",
            "self.letters.read(m) return true } }",
        ] {
            XCTAssertTrue(list.contains(line), line)
        }
        XCTAssertTrue(list.contains("self.onMessagesChanged?() return false } catch {"))
        XCTAssertTrue(list.contains("self.letters.readAnswered(m.id, landed: false) self.regroup() "
                                    + "return false }"))
        // Passed on from `openNext` alone; a tap on a row passes none.
        XCTAssertEqual(list.components(separatedBy: "readTaken: readTaken").count - 1, 2)
        XCTAssertEqual(list.components(separatedBy: "taken: readTaken").count - 1, 2)
        XCTAssertTrue(list.contains("open(thread, at: ip) case let .thread(thread): "
                                    + "open(thread.newest, at: ip) } } override func "
                                    + "tableView(_ t: UITableView, didDeselectRowAt"))
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
