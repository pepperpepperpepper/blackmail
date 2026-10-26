import XCTest
@testable import Blackmail

/// The message list's Edit mode in Mail's words (B-144): "Edit", and
/// "Cancel" to leave it, where it said "Done"; the bar's third button
/// "Trash", or "Delete" inside the Trash, in the bar's own colour, where it
/// said "Delete" in red everywhere.
///
/// The words and the rule are `EditBar`'s, run here. The controller is
/// UIKit and built only for the device, so how it uses them is read from
/// its source, comment lines out, as `OpenLetterHighlightTests` reads it.
final class EditBarTests: XCTestCase {

    // MARK: - The words

    func testEditAndCancel() {
        XCTAssertEqual(EditBar.edit, "Edit")
        XCTAssertEqual(EditBar.cancel, "Cancel")
    }

    /// "Delete" in the Trash alone, where the button erases; "Trash" in
    /// every other folder, the Outbox and a folder with no role included.
    func testTheThirdButtonIsTrashOutsideTheTrashAndDeleteInIt() {
        XCTAssertEqual(EditBar.deleteTitle(inFolderWithRole: .trash), "Delete")
        for role in [Mailbox.Role.inbox, .sent, .drafts, .archive, .junk, .outbox] {
            XCTAssertEqual(EditBar.deleteTitle(inFolderWithRole: role), "Trash", "\(role)")
        }
        XCTAssertEqual(EditBar.deleteTitle(inFolderWithRole: nil), "Trash", "a label")
    }

    /// "Delete" exactly where `EraseQuestion` asks before the tap, the
    /// Trash, so the bar's word and the question's red Delete agree. Not
    /// everywhere the tap cannot be taken back: the Outbox's letters, and
    /// those kept on the iPad in Drafts, go from the iPad with nothing
    /// asked under "Trash", the ruling's word, a question left to the
    /// owner.
    func testDeleteIsSaidWhereTheEraseQuestionIsAsked() {
        for role in [Mailbox.Role.inbox, .sent, .drafts, .trash, .archive, .junk, .outbox] {
            XCTAssertEqual(EditBar.deleteTitle(inFolderWithRole: role) == "Delete",
                           EraseQuestion.erases(fromFolderWithRole: role), "\(role)")
        }
    }

    // MARK: - The controller

    /// The bar is Mail's, in Mail's order, Select All, Mark, Move, then the
    /// third button by the list's folder, with no colour of its own; the
    /// red is gone from the list.
    func testTheBarsThirdButtonIsTitledByTheFolderInTheBarsColour() throws {
        let list = try source("UI/MessageListViewController.swift")
        let bar = flat(body(after: "private func buildBottomBar()", in: list))
        inOrder(["markItem = UIBarButtonItem(title: \"Mark\", style: .plain, target: self, "
                    + "action: #selector(markSelected))",
                 "moveItem = UIBarButtonItem(title: \"Move\", style: .plain, target: self, "
                    + "action: #selector(moveSelected))",
                 "deleteItem = UIBarButtonItem(title: EditBar.deleteTitle(inFolderWithRole: "
                    + "mailbox.role), style: .plain, target: self, action: #selector(deleteSelected))",
                 "for item in [markItem, moveItem, deleteItem, selectAllItem] { "
                    + "item?.setTitleTextAttributes([.font: Theme.fontBarButton], for: .normal) }",
                 "editItems = [selectAllItem, flex, markItem, flex, moveItem, flex, deleteItem]"],
                in: bar)
        XCTAssertFalse(list.contains("deleteItem.tintColor"), "the bar's own colour")
        // The red is a drag's Trash alone, as Mail's (B-156), never the bar's.
        XCTAssertEqual(count("Theme.destructive", in: list), 1)
        XCTAssertTrue(list.contains("case .trash, .delete: return Theme.destructive"))
        XCTAssertFalse(bar.contains("tintColor"), "no item of the bar has a colour of its own")
        XCTAssertEqual(count("deleteItem = ", in: list), 1)
        XCTAssertEqual(count("deleteItem.title", in: list), 0, "titled once, for its folder")
        XCTAssertFalse(list.contains("private var mailbox"), "the folder is the list's for good")
        XCTAssertTrue(list.contains("private let mailbox: Mailbox"))
    }

    /// "Edit" as the list opens, "Cancel" while Edit mode is on and "Edit"
    /// again after it, in the one place that switches it; "Done" and
    /// "Delete" said nowhere in the list.
    func testEditModeIsLeftWithCancel() throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(flat(list).contains(
            "navigationItem.rightBarButtonItem = UIBarButtonItem( title: EditBar.edit, style: .plain, "
                + "target: self, action: #selector(editTapped))"))
        let edit = flat(body(after: "@objc private func editTapped()", in: list))
        // Edit mode is the list's own, not the table's `isEditing`, which a
        // drag on a row turns on too (B-156).
        inOrder(["let editing = !inEditMode",
                 "inEditMode = editing",
                 "tableView.setEditing(editing, animated: true)",
                 "navigationItem.rightBarButtonItem?.title = editing ? EditBar.cancel : EditBar.edit"],
                in: edit)
        XCTAssertEqual(count("rightBarButtonItem?.title", in: list), 1)
        XCTAssertEqual(count("rightBarButtonItem = ", in: list), 1)
        // The Mark sheet's own Cancel is UIKit's cancel button, and stays.
        XCTAssertEqual(count("\"Cancel\"", in: list), 1)
        XCTAssertTrue(list.contains("sheet.addAction(UIAlertAction(title: \"Cancel\", style: .cancel))"))
        for word in ["\"Done\"", "\"Delete\"", "\"Edit\"", "\"Trash\""] {
            XCTAssertFalse(list.contains(word), word)
        }
        // No width of its own: the button is as wide as its word, so the
        // title beside it gives way to "Cancel" (D-009).
        XCTAssertFalse(list.contains("rightBarButtonItem?.width"))
        XCTAssertFalse(list.contains("rightBarButtonItem.width"))
    }

    // MARK: - Reading the source

    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The braces after the first `opener` in `code`, and everything in them.
    private func body(after opener: String, in code: String,
                      file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let start = code.range(of: opener),
              let brace = code[start.upperBound...].firstIndex(of: "{") else {
            XCTFail("no \(opener)", file: file, line: line)
            return ""
        }
        var depth = 0
        var i = brace
        while i < code.endIndex {
            if code[i] == "{" { depth += 1 }
            if code[i] == "}" {
                depth -= 1
                if depth == 0 { return String(code[brace...i]) }
            }
            i = code.index(after: i)
        }
        XCTFail("unclosed \(opener)", file: file, line: line)
        return ""
    }

    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).joined(separator: " ")
    }

    private func count(_ needle: String, in code: String) -> Int {
        code.components(separatedBy: needle).count - 1
    }

    /// Each of `steps` in `code`, in that order.
    private func inOrder(_ steps: [String], in code: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        var from = code.startIndex
        for step in steps {
            guard let found = code.range(of: step, range: from..<code.endIndex) else {
                XCTFail("not in order: \(step)\n\(code)", file: file, line: line)
                return
            }
            from = found.upperBound
        }
    }
}
