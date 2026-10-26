import XCTest
@testable import Blackmail

/// The row of the letter open in the reading pane keeps its highlight where
/// the table drops it with the letter still open (B-133): at Edit mode's
/// Done, Edit mode having cleared the selection as it began, and on a day's
/// list after Go to Date, whose rows replace the list's. Mail keeps the
/// open message's row selected.
///
/// Which row is `ListEdit.paneRow`'s, run here. What the controller does
/// with it is UIKit, which the suite cannot run, and is read from the
/// source at the foot: the row selected without a scroll and without a
/// tap, never in Edit mode, at Done, as a day's rows are drawn and in any
/// redraw with no selection to put back, from the letters the pane says
/// it shows.
final class OpenLetterHighlightTests: XCTestCase {

    private func letter(_ uid: Int, thread: String) -> MessageSummary {
        MessageSummary(id: "7/\(uid)", mailboxID: "INBOX",
                       sender: "Sam Example <sam@example.com>", subject: "About \(thread)",
                       preview: "", date: Date(timeIntervalSince1970: 1_790_000_000 + Double(uid) * 3_600),
                       isRead: true, isFlagged: false, threadID: thread)
    }

    private func rows(_ letters: [MessageSummary]) -> [MessageThread] {
        MessageThread.rows(for: letters, grouped: true)
    }

    /// A letter alone: the row that carries it. A conversation the pane
    /// shows, its newest first: the conversation's row, found by its newest
    /// or, on a day's list that holds the conversation without its newest,
    /// by the next of its letters the list has. The letter the pane opened
    /// first wins over the rest of its conversation, and nothing is found
    /// for an empty pane or a letter the list does not have. Grouping off,
    /// a letter's own row.
    func testTheRowIsTheOneHoldingTheFirstLetterThePaneShowsThatTheListHas() {
        let folder = [letter(150, thread: "A"), letter(149, thread: "B"), letter(148, thread: "C"),
                      letter(147, thread: "A"), letter(146, thread: "D"), letter(145, thread: "A")]
        let list = rows(folder)
        XCTAssertEqual(list.map(\.id), ["7/150", "7/149", "7/148", "7/146"])

        XCTAssertEqual(ListEdit.paneRow(in: list, showing: ["7/148"]), 2, "a letter alone")
        XCTAssertEqual(ListEdit.paneRow(in: list, showing: ["7/150", "7/147", "7/145"]), 0,
                       "the conversation, by its newest")
        XCTAssertEqual(ListEdit.paneRow(in: list, showing: ["7/146"]), 3)

        // A day's list from 147 down: A without its newest letter.
        let day = rows(Array(folder.dropFirst(3)))
        XCTAssertEqual(day.map(\.id), ["7/147", "7/146"])
        XCTAssertEqual(ListEdit.paneRow(in: day, showing: ["7/150", "7/147", "7/145"]), 0,
                       "the conversation's row by another of its letters")
        XCTAssertNil(ListEdit.paneRow(in: day, showing: ["7/149"]), "not on the day's list")
        XCTAssertNil(ListEdit.paneRow(in: list, showing: []), "the pane empty")
        XCTAssertNil(ListEdit.paneRow(in: list, showing: ["9/150"]), "another mailbox's id")

        // The first the list has wins, whatever row holds the rest.
        let apart = [MessageThread(messages: [folder[0]]), MessageThread(messages: [folder[3]])]
        XCTAssertEqual(ListEdit.paneRow(in: apart, showing: ["7/147", "7/150"]), 1)
        XCTAssertEqual(ListEdit.paneRow(in: apart, showing: ["7/150", "7/147"]), 0)

        let ungrouped = MessageThread.rows(for: folder, grouped: false)
        XCTAssertEqual(ListEdit.paneRow(in: ungrouped, showing: ["7/147"]), 3)
    }

    // MARK: - The controller, read

    /// The list highlights the row by the letters the pane shows, with
    /// `selectRow`, which scrolls nowhere with `.none` and tells the
    /// delegate nothing, so nothing is opened, marked read or fetched; and
    /// never in Edit mode, where a selected row is a tick. It does so at
    /// Done, before what Done lets go on goes on, and as a day's rows are
    /// drawn, straight after the reload that dropped the highlight. Every
    /// other redraw puts back the selection it took, and only with none to
    /// put back, out of Edit mode, highlights the pane's letter: a page
    /// that brings its row after a day without it, a search's Cancel. The
    /// container hands it the pane's letters; the pane's
    /// are the letter it opened, or its conversation's newest, then the
    /// rest of its stack, the newest first, and none when it is empty.
    func testTheControllerHighlightsThePanesLetterAtDoneAndOnADaysList() throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertEqual(flat(body(after: "private func highlightLetterInPane()", in: list)),
                       "{ guard !inEditMode, let row = ListEdit.paneRow(in: threads, "
                       + "showing: lettersInPane()) else { return } tableView.selectRow(at: "
                       + "IndexPath(row: row, section: 0), animated: false, scrollPosition: .none) }")
        XCTAssertTrue(list.contains("var lettersInPane: () -> [String] = { [] }"))

        let edit = flat(body(after: "@objc private func editTapped()", in: list))
        inOrder(["tableView.setEditing(editing, animated: true)",
                 "if !editing { highlightLetterInPane() landFreshPage() showNewsIfAtTop() }"],
                in: edit)
        let show = flat(body(after: "private func show(_ window: MessageWindow)", in: list))
        inOrder(["rebuildRows()", "tableView.reloadData()", "highlightLetterInPane()",
                 "tableView.scrollToRow("], in: show)
        // And as a drag's buttons close (B-156).
        XCTAssertEqual(lines(of: list, containing: "highlightLetterInPane()"),
                       ["highlightLetterInPane()", "highlightLetterInPane()",
                        "private func highlightLetterInPane() {", "highlightLetterInPane()"])
        XCTAssertEqual(flat(body(after: "didEndEditingRowAt ip: IndexPath?)", in: list)),
                       "{ highlightLetterInPane() }")
        // Every other redraw puts back the selection it took, and with none
        // to put back, out of Edit mode, highlights the pane's letter.
        XCTAssertTrue(flat(body(after: "private func regroup(highlighting", in: list)).contains(
            "let threads = self.threads var selection = before.selection(in: threads, "
            + "opened: opened, editing: inEditMode) if selection.isEmpty, "
            + "!inEditMode, let row = ListEdit.paneRow(in: threads, "
            + "showing: lettersInPane()) { selection = [row] } for row in selection { "
            + "tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, "
            + "scrollPosition: .none) }"))
        XCTAssertEqual(lines(of: list, containing: "lettersInPane()").count, 2)

        let root = flat(try source("UI/RootViewController.swift"))
        XCTAssertTrue(root.contains("list.lettersInPane = { [weak self] in "
                                    + "self?.detail.lettersShown ?? [] }"))
        let pane = flat(try source("UI/MessageDetailViewController.swift"))
        XCTAssertTrue(pane.contains("var lettersShown: [String] { guard let summary else { return [] } "
                                    + "return [summary.id] + stackLetters.reversed().map(\\.id)"
                                    + ".filter { $0 != summary.id } }"))
    }

    // MARK: - Reading the source

    /// A file under `Sources/Blackmail`, its comment lines taken out.
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
        XCTFail("\(opener) never closes", file: file, line: line)
        return ""
    }

    /// The lines of `code` that contain `text`, trimmed.
    private func lines(of code: String, containing text: String) -> [String] {
        code.components(separatedBy: "\n")
            .filter { $0.contains(text) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Whitespace runs as one space.
    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).joined(separator: " ")
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
