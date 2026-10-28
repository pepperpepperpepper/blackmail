import XCTest
@testable import Blackmail

/// Mail's Ask Before Deleting (B-168): off from the factory, nothing asked
/// but the erase inside Trash, as before; on, a Trash or an Archive of a
/// letter asks first, in Mail's words, from the reading pane and the Edit
/// bar; a drag's button, More and a full drag go at once, as Mail's did on
/// the test iPad (B-175).
///
/// The sheet is UIKit's and the iPad's to show; the setting, the words, the
/// rule and the wiring, read from the source, are here.
final class DiscardQuestionTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: MailOptions.Option.askBeforeDeleting.key)
        super.tearDown()
    }

    // MARK: - The setting

    /// Off from the factory, read from one place under its own key; a value
    /// written is read back; one written as something else is the factory's.
    func testAskBeforeDeletingIsOffFromTheFactoryReadFromOnePlace() {
        XCTAssertEqual(MailOptions.Option.askBeforeDeleting.key, "blackmail.askBeforeDeleting")
        UserDefaults.standard.removeObject(forKey: MailOptions.Option.askBeforeDeleting.key)
        XCTAssertFalse(MailOptions.askBeforeDeleting)
        XCTAssertNil(DiscardQuestion.before(.trash, letters: 1, from: .pane))
        MailOptions.askBeforeDeleting = true
        XCTAssertEqual(UserDefaults.standard.object(forKey: MailOptions.Option.askBeforeDeleting.key) as? Bool, true)
        XCTAssertTrue(MailOptions.askBeforeDeleting)
        XCTAssertEqual(DiscardQuestion.before(.trash, letters: 1, from: .pane)?.button, "Trash Message")
        MailOptions.askBeforeDeleting = false
        XCTAssertFalse(MailOptions.askBeforeDeleting)
        UserDefaults.standard.set(1, forKey: MailOptions.Option.askBeforeDeleting.key)
        XCTAssertFalse(MailOptions.askBeforeDeleting)
        XCTAssertFalse(SafeStart.viewSettings.contains(MailOptions.Option.askBeforeDeleting.key))
    }

    // MARK: - The words and the rule

    /// Off, nothing is asked, from anywhere, of any number.
    func testOffNothingIsAsked() {
        for from: DiscardQuestion.From in [.pane, .editBar, .rowButton, .more, .fullDrag] {
            for verb: DiscardQuestion.Verb in [.trash, .archive] {
                for count in [1, 2, 7] {
                    XCTAssertNil(DiscardQuestion.before(verb, letters: count, from: from, asking: false))
                }
            }
        }
    }

    /// On, Mail's words: a letter's "Trash Message" or "Archive Message",
    /// a conversation's "Trash Messages", a selection's counted "Trash 3
    /// Messages" and "Trash 1 Message"; Cancel. Nothing for no letters.
    func testOnMailsWordsByWhereItWasAsked() {
        func button(_ verb: DiscardQuestion.Verb, _ count: Int, _ from: DiscardQuestion.From) -> String? {
            DiscardQuestion.before(verb, letters: count, from: from, asking: true)?.button
        }
        XCTAssertEqual(button(.trash, 1, .pane), "Trash Message")
        XCTAssertEqual(button(.trash, 3, .pane), "Trash Messages")
        XCTAssertEqual(button(.archive, 1, .pane), "Archive Message")
        XCTAssertEqual(button(.archive, 4, .pane), "Archive Messages")
        XCTAssertEqual(button(.trash, 1, .editBar), "Trash 1 Message")
        XCTAssertEqual(button(.trash, 3, .editBar), "Trash 3 Messages")
        XCTAssertEqual(button(.trash, 12, .editBar), "Trash 12 Messages")
        XCTAssertEqual(button(.archive, 2, .editBar), "Archive 2 Messages")
        XCTAssertNil(button(.trash, 0, .editBar))
        XCTAssertEqual(DiscardQuestion.cancel, "Cancel")
    }

    /// A full drag never asks, of a letter or a conversation, Trash or
    /// Archive; a button tapped is told from it by the drag's own pan, not
    /// the button's width: done as the pan ends, or within a third of a
    /// second of its lift, a full drag; done with the pan not ended and no
    /// lift that near, a tap. By the width, a full drag on the test iPad
    /// asked: its Trash was 53 to 56 per cent of the row as the finger
    /// lifted, under the three fifths that counted (2026-10-27). Since
    /// B-175 neither asks; the tell is kept for a read mark's step of Undo.
    func testAFullDragNeverAsks() {
        for verb: DiscardQuestion.Verb in [.trash, .archive] {
            for count in [1, 3] {
                XCTAssertNil(DiscardQuestion.before(verb, letters: count, from: .fullDrag, asking: true))
            }
        }
        XCTAssertEqual(DiscardQuestion.liftWindow, 0.3)
        // A full drag: the pan ended as its button is done, or just before.
        XCTAssertTrue(DiscardQuestion.fullDrag(panEnded: true, sinceLift: nil))
        XCTAssertTrue(DiscardQuestion.fullDrag(panEnded: true, sinceLift: 12))
        XCTAssertTrue(DiscardQuestion.fullDrag(panEnded: false, sinceLift: 0))
        XCTAssertTrue(DiscardQuestion.fullDrag(panEnded: false, sinceLift: 0.05))
        XCTAssertTrue(DiscardQuestion.fullDrag(panEnded: false, sinceLift: 0.29))
        // A tap: on a list never dragged, or after a slow drag's lift.
        XCTAssertFalse(DiscardQuestion.fullDrag(panEnded: false, sinceLift: nil))
        XCTAssertFalse(DiscardQuestion.fullDrag(panEnded: false, sinceLift: 0.3))
        XCTAssertFalse(DiscardQuestion.fullDrag(panEnded: false, sinceLift: 0.8))
        XCTAssertFalse(DiscardQuestion.fullDrag(panEnded: false, sinceLift: 40))
        XCTAssertFalse(DiscardQuestion.fullDrag(panEnded: false, sinceLift: -1))
        // And so the question: none for the full drag, nor, since B-175,
        // for the tap.
        for (ended, since) in [(true, nil), (false, 0.1), (false, 1.5),
                               (false, nil)] as [(Bool, Double?)] {
            let from: DiscardQuestion.From = DiscardQuestion.fullDrag(panEnded: ended, sinceLift: since)
                ? .fullDrag : .rowButton
            XCTAssertNil(DiscardQuestion.before(.trash, letters: 1, from: from, asking: true))
        }
    }

    // MARK: - The wiring

    /// The sheet: an action sheet, its red button Mail's words, then Cancel,
    /// from the button tapped or over the row, `go` only on the red one.
    /// Under Archive Mailbox (B-167) the Edit bar asks Mail's Archive
    /// words, counted, where its tap archives every letter, and the
    /// Trash's where it sends any to the Trash: the sheet says what the tap
    /// does, not the button's word. Under "Archive", an All Mailboxes
    /// search's hits from All Mail go to the Trash, and the sheet says so
    /// (integration, int19).
    func testTheEditBarAsksInItsOwnWord() {
        let archiving = SwipeOptions(swipeLeft: .flag, swipeRight: .mark, discardInto: .archive)
        let allMail = Mailbox(id: "[Gmail]/All Mail", name: "All Mail", unreadCount: 0, role: .archive)
        let folders: [String: Mailbox.Role] = ["INBOX": .inbox, "[Gmail]/Spam": .junk,
                                               "[Gmail]/All Mail": .archive]
        func letter(_ id: String, in mailbox: String) -> MessageSummary {
            MessageSummary(id: id, mailboxID: mailbox, sender: "Sam Example <sam@example.com>",
                           subject: "Lunch on Sunday", preview: "", date: Date(timeIntervalSince1970: 0),
                           isRead: false, isFlagged: false)
        }
        func verb(_ letters: [MessageSummary]) -> DiscardQuestion.Verb {
            EditBar.discardVerb(for: EditBar.discarding(letters, role: { folders[$0] },
                                                        allMail: allMail, options: archiving))
        }
        let inbox = letter("1/1", in: "INBOX"), spam = letter("2/1", in: "[Gmail]/Spam")
        let all = [letter("3/1", in: "[Gmail]/All Mail"), letter("3/2", in: "[Gmail]/All Mail")]
        // The list's word is "Archive" (an All Mailboxes search from the
        // Inbox); the hits from All Mail go to the Trash, and so says the sheet.
        XCTAssertEqual(EditBar.deleteTitle(inFolderWithRole: .inbox, canArchive: true, options: archiving),
                       "Archive")
        XCTAssertEqual(verb(all), .trash)
        XCTAssertEqual(verb([inbox] + all), .trash)
        XCTAssertEqual(verb([inbox, spam]), .archive)
        // The factory's Deleted Mailbox, or no All Mail: the Trash.
        XCTAssertEqual(EditBar.discardVerb(for: EditBar.discarding([inbox], role: { folders[$0] },
                                                                   allMail: allMail)), .trash)
        XCTAssertEqual(EditBar.discardVerb(for: EditBar.discarding([inbox], role: { folders[$0] },
                                                                   allMail: nil, options: archiving)),
                       .trash)
        XCTAssertEqual(DiscardQuestion.before(verb([inbox, spam]), letters: 2,
                                              from: .editBar, asking: true)?.button,
                       "Archive 2 Messages")
        XCTAssertEqual(DiscardQuestion.before(verb(all), letters: 2,
                                              from: .editBar, asking: true)?.button,
                       "Trash 2 Messages")
        XCTAssertEqual(DiscardQuestion.before(.archive, letters: 1, from: .pane, asking: true)?.button,
                       "Archive Message")
    }

    /// The pane's Delete and the Edit bar's ask it where the erase question
    /// is not asked, and go at once where neither is; a drag's button and
    /// More's item go through the same wire over the row, which asks
    /// nothing from them since B-175. The erase question inside Trash is as
    /// it was, and the only one there.
    func testTheWiringAsksWhereMailAsks() throws {
        let sheet = try source("UI/DiscardConfirmation.swift")
        for line in [
            "let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)",
            "sheet.addAction(UIAlertAction(title: question.button, style: .destructive) { _ in go() }) "
                + "sheet.addAction(UIAlertAction(title: DiscardQuestion.cancel, style: .cancel)) return sheet",
            "sheet.popoverPresentationController?.barButtonItem = item vc.present(sheet, animated: true)",
            "sheet.popoverPresentationController?.sourceView = place.view "
                + "sheet.popoverPresentationController?.sourceRect = place.rect vc.present(sheet, animated: true)",
        ] {
            XCTAssertTrue(sheet.contains(line), line)
        }

        let pane = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(pane.contains(
            "guard let question = questionBeforeDeleting?(s) else { "
                + "let verb: DiscardQuestion.Verb = archiveTarget?(s) == nil ? .trash : .archive "
                + "guard let asked = DiscardQuestion.before(verb, letters: 1, from: .pane) else { "
                + "delete(s) return } DiscardConfirmation.ask(asked, on: self, from: actionItems[.delete]) "
                + "{ [weak self] in guard let self, self.summary?.id == s.id else { return } self.delete(s) } "
                + "return } EraseConfirmation.ask(question, on: self)"))
        XCTAssertEqual(pane.components(separatedBy: "DiscardQuestion.before(").count - 1, 1)

        let list = try source("UI/MessageListViewController.swift")
        for line in [
            "guard let question = EditBar.question(before: chosen, role: { self.role(of: $0) }, "
                + "allMail: allMail) else { "
                + "let split = EditBar.discarding(chosen, role: { self.role(of: $0) }, allMail: allMail) "
                + "guard let asked = DiscardQuestion.before(EditBar.discardVerb(for: split), "
                + "letters: chosen.count, from: .editBar) else { delete(chosen) return } DiscardConfirmation.ask(asked, on: self, from: deleteItem) "
                + "{ [weak self] in self?.delete(chosen) } return } "
                + "EraseConfirmation.ask(question, on: self) { [weak self] in guard let self else { return } "
                + "let archived = EditBar.discarding(chosen, role: { self.role(of: $0) }, "
                + "allMail: self.allMail).archived "
                + "guard let asked = DiscardQuestion.before(.archive, letters: archived.count, "
                + "from: .editBar) else { self.delete(chosen) return } "
                + "DiscardConfirmation.ask(asked, on: self, from: self.deleteItem) { [weak self] in "
                + "self?.delete(chosen) } }",
            "let whole = DiscardQuestion.fullDrag( panEnded: self.swipePans.contains { $0.state == .ended }, "
                + "sinceLift: self.swipeLift.map { CACurrentMediaTime() - $0 }) "
                + "done(self.swiped(action, on: RowKey(thread), from: whole ? .fullDrag : .rowButton))",
            "override func tableView(_ t: UITableView, willBeginEditingRowAt ip: IndexPath) { "
                + "for case let pan as UIPanGestureRecognizer in t.gestureRecognizers ?? [] "
                + "where pan !== t.panGestureRecognizer { "
                + "pan.addTarget(self, action: #selector(swipePan(_:))) "
                + "if !swipePans.contains(where: { $0 === pan }) { swipePans.append(pan) } } }",
            "@objc private func swipePan(_ pan: UIPanGestureRecognizer) { "
                + "if pan.state == .ended { swipeLift = CACurrentMediaTime() } }",
            "case .trash: return discard(.trash, chosen, on: key, from: from) { [weak self] in "
                + "self?.runBatch(.delete, on: chosen, saying: StatusLine.deleting, fromRow: true) }",
            "case .archive: guard let all = archive(for: row.thread) else { return false } "
                + "return discard(.archive, chosen, on: key, from: from) { [weak self] in "
                + "self?.runBatch(.move(to: all), on: chosen, saying: StatusLine.moving, fromRow: true) }",
            "guard let asked = DiscardQuestion.before(verb, letters: letters.count, from: from) else { "
                + "go() return true } let place = placeOfRow(key) ?? "
                + "(view: tableView as UIView, rect: tableView.bounds) "
                + "DiscardConfirmation.ask(asked, on: self, over: place, go: go) return false }",
            "case .trashMessage: _ = swiped(.trash, on: key, from: .more)",
            "case .archiveMessage: _ = swiped(.archive, on: key, from: .more)",
        ] {
            XCTAssertTrue(list.contains(line), line)
        }
        XCTAssertEqual(list.components(separatedBy: "DiscardQuestion.before(").count - 1, 3,
                       "the Edit bar's, after its erase question, and a row's")
        XCTAssertEqual(list.components(separatedBy: "discard(.").count - 1, 2, "Trash and Archive")
        // Inside Trash the erase question alone, from a drag as from More.
        let swiped = try XCTUnwrap(list.range(of: "case .delete: guard let question = EraseQuestion.before("))
        XCTAssertFalse(list[swiped.lowerBound...].prefix(400).contains("DiscardQuestion"))
    }

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
