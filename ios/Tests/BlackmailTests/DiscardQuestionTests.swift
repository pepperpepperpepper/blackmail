import XCTest
@testable import Blackmail

/// Mail's Ask Before Deleting (B-168): off from the factory, nothing asked
/// but the erase inside Trash, as before; on, a Trash or an Archive of a
/// letter asks first, in Mail's words, from the reading pane, the Edit bar,
/// a drag's button and More, and a full drag goes at once, as Mail's does.
///
/// The sheet is UIKit's and the iPad's to show; the setting, the words, the
/// rule and the wiring, read from the source, are here.
final class DiscardQuestionTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: MessagesOptions.askBeforeDeletingKey)
        super.tearDown()
    }

    // MARK: - The setting

    /// Off from the factory, read from one place under its own key; a value
    /// written is read back; one written as something else is the factory's.
    func testAskBeforeDeletingIsOffFromTheFactoryReadFromOnePlace() {
        XCTAssertEqual(MessagesOptions.askBeforeDeletingKey, "blackmail.askBeforeDeleting")
        UserDefaults.standard.removeObject(forKey: MessagesOptions.askBeforeDeletingKey)
        XCTAssertFalse(MessagesOptions.askBeforeDeleting)
        XCTAssertNil(DiscardQuestion.before(.trash, letters: 1, from: .pane))
        MessagesOptions.askBeforeDeleting = true
        XCTAssertEqual(UserDefaults.standard.object(forKey: MessagesOptions.askBeforeDeletingKey) as? Bool, true)
        XCTAssertTrue(MessagesOptions.askBeforeDeleting)
        XCTAssertEqual(DiscardQuestion.before(.trash, letters: 1, from: .pane)?.button, "Trash Message")
        MessagesOptions.askBeforeDeleting = false
        XCTAssertFalse(MessagesOptions.askBeforeDeleting)
        UserDefaults.standard.set(1, forKey: MessagesOptions.askBeforeDeletingKey)
        XCTAssertFalse(MessagesOptions.askBeforeDeleting)
        XCTAssertFalse(SafeStart.viewSettings.contains(MessagesOptions.askBeforeDeletingKey))
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
        XCTAssertEqual(button(.trash, 1, .rowButton), "Trash Message")
        XCTAssertEqual(button(.trash, 3, .rowButton), "Trash Messages")
        XCTAssertEqual(button(.trash, 1, .more), "Trash Message")
        XCTAssertEqual(button(.trash, 2, .more), "Trash Messages")
        XCTAssertEqual(button(.archive, 1, .rowButton), "Archive Message")
        XCTAssertEqual(button(.archive, 4, .more), "Archive Messages")
        XCTAssertEqual(button(.trash, 1, .editBar), "Trash 1 Message")
        XCTAssertEqual(button(.trash, 3, .editBar), "Trash 3 Messages")
        XCTAssertEqual(button(.trash, 12, .editBar), "Trash 12 Messages")
        XCTAssertEqual(button(.archive, 2, .editBar), "Archive 2 Messages")
        XCTAssertNil(button(.trash, 0, .editBar))
        XCTAssertEqual(DiscardQuestion.cancel, "Cancel")
    }

    /// A full drag never asks, of a letter or a conversation, Trash or
    /// Archive; a button tapped is told from it by its width, over three
    /// fifths of the row being a full drag, so a tap is never taken for one.
    func testAFullDragNeverAsks() {
        for verb: DiscardQuestion.Verb in [.trash, .archive] {
            for count in [1, 3] {
                XCTAssertNil(DiscardQuestion.before(verb, letters: count, from: .fullDrag, asking: true))
            }
        }
        XCTAssertFalse(DiscardQuestion.fullDrag(button: 90, row: 320))
        XCTAssertFalse(DiscardQuestion.fullDrag(button: 150, row: 375))
        XCTAssertFalse(DiscardQuestion.fullDrag(button: 191, row: 320))
        XCTAssertTrue(DiscardQuestion.fullDrag(button: 200, row: 320))
        XCTAssertTrue(DiscardQuestion.fullDrag(button: 320, row: 320))
        XCTAssertTrue(DiscardQuestion.fullDrag(button: 700, row: 694))
        XCTAssertFalse(DiscardQuestion.fullDrag(button: 90, row: 0))
    }

    // MARK: - The wiring

    /// The sheet: an action sheet, its red button Mail's words, then Cancel,
    /// from the button tapped or over the row, `go` only on the red one.
    /// The pane's Delete and the Edit bar's ask it where the erase question
    /// is not asked, and go at once where neither is; a drag's button and
    /// More's item ask it over the row, the row sliding back; a full drag
    /// told by the button's width goes at once. The erase question inside
    /// Trash is as it was, and the only one there.
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
                + "guard let asked = DiscardQuestion.before(.trash, letters: 1, from: .pane) else { "
                + "delete(s) return } DiscardConfirmation.ask(asked, on: self, from: actionItems[.delete]) "
                + "{ [weak self] in guard let self, self.summary?.id == s.id else { return } self.delete(s) } "
                + "return } EraseConfirmation.ask(question, on: self)"))
        XCTAssertEqual(pane.components(separatedBy: "DiscardQuestion.before(").count - 1, 1)

        let list = try source("UI/MessageListViewController.swift")
        for line in [
            "guard let question = EraseQuestion.before(deleting: chosen, role: { self.role(of: $0) }) else { "
                + "guard let asked = DiscardQuestion.before(.trash, letters: chosen.count, from: .editBar) "
                + "else { delete(chosen) return } DiscardConfirmation.ask(asked, on: self, from: deleteItem) "
                + "{ [weak self] in self?.delete(chosen) } return } "
                + "EraseConfirmation.ask(question, on: self) { [weak self] in self?.delete(chosen) }",
            "let whole = DiscardQuestion.fullDrag(button: Double(source.bounds.width), "
                + "row: Double(self.tableView.bounds.width)) "
                + "done(self.swiped(action, on: RowKey(thread), from: whole ? .fullDrag : .rowButton))",
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
        XCTAssertEqual(list.components(separatedBy: "DiscardQuestion.before(").count - 1, 2,
                       "the Edit bar's, and a row's")
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
