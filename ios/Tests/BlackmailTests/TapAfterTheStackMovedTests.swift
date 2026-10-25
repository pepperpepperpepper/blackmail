import XCTest
@testable import Blackmail

/// A line pressed just after the stack moved with the header (B-128).
///
/// The stack hangs from the header over it, and the header changes height
/// as he opens a letter with a Cc line or a file the last one had not, or
/// without one it had, at the tap since B-129: the whole stack moves on
/// the glass by as much, a Cc line about 20 pt, a file's row 44 pt. A
/// second tap made at once where the first was, a double tap or a tap to
/// close a letter opened by mistake, lands that far off the line it was
/// meant for, on the line above or below, and opened that letter, which
/// then took the header and the toolbar. The page cannot see the move: the
/// web view moves on the glass, and the page's own coordinates, which the
/// script's check of a line moved under the finger reads, do not change.
/// So the pane tells the script (`ConversationDocument.Shift`), and a line
/// pressed within a second of its word does nothing, nor one pressed as it
/// comes; its lift stops WebKit's own tap, as the script's tap does.
///
/// The stack is three letters he has read, J0 and J1 closed, J2, the
/// newest, open, the pane opened at J1's line (`opensAt`), run on the
/// stack's own script in node (`ModelPage`). J1 opened by its line, its
/// "Loading…" under it, J2's line is at 68 to 106 in the page. J1's header
/// a Cc line and a file's row shorter than J2's, 64 pt, the stack moves up
/// by as much, and the glass where J1's line was, 20, is at 84 in the
/// page: J2's line.
final class TapAfterTheStackMovedTests: XCTestCase {

    private typealias Step = ModelPage.Step

    private static let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func inbox(_ n: Int) -> MessageSummary {
        MessageSummary(id: "1/\(n)", mailboxID: "INBOX", sender: "Jane Example <jane@example.com>",
                       subject: "Re: the roof", preview: "letter \(n)",
                       date: Self.base.addingTimeInterval(Double(n) * 60),
                       isRead: true, isFlagged: false, threadID: "1700000000000000042",
                       gmailMessageID: UInt64(9_000 + n),
                       arrived: Self.base.addingTimeInterval(Double(n) * 60))
    }

    private var page: String {
        let stack = ConversationDocument.stack(of: MessageThread(messages: [inbox(5), inbox(4), inbox(3)]))
        return ConversationDocument.html(entries: stack, inset: 20, bodyPointSize: 17, lineHeight: 1.4)
    }

    private let j1 = "m1_4", j2 = "m1_5"

    /// J1's line tapped at 500, opening it, and the pane's word that the
    /// header changed height 40 ms after, as the tap's message has come
    /// and the header has been laid out.
    private let firstTap: [Step] = [.down(500, y: 20), .up(560), .shift(600)]

    private func run(_ steps: [Step], script: String = ConversationDocument.script) throws -> ModelPage.Run {
        do {
            return try ModelPage.run(script, page: page, steps: steps, end: 3_000)
        } catch is ModelPage.NoNode {
            throw XCTSkip("node is not on this host")
        }
    }

    /// The stack as the pane opens it: J1's line at the top, J2's under it.
    func testTheStackOpensAtJ1sLine() throws {
        let first = try XCTUnwrap(try run([]).frames.first)
        XCTAssertEqual(first.top(j1), 0)
        XCTAssertEqual(first.top(j2), 38)
    }

    /// The double tap: the second tap 300 ms after the first, where the
    /// first was on the glass, now J2's line in the page. It does nothing,
    /// and WebKit's own tap is stopped, its click, should it come anyway,
    /// let pass; J1 opened, J2 still open. Without the pane's word the
    /// second tap closed J2.
    func testASecondTapJustAfterTheStackMovedDoesNothing() throws {
        let second: [Step] = [.down(800, y: 84), .up(860), .clickLine(870, j2)]
        let run = try run(firstTap + second)
        XCTAssertEqual(run.posts, [ModelPage.Run.Post(id: j1, open: true)])
        XCTAssertEqual(run.frames.last?.sections.first { $0.id == j2 }?.open, true)
        XCTAssertEqual(run.stopped, 2, "the first tap's and the second's")
        XCTAssertEqual(run.errors, [])

        let unsaid = try self.run(firstTap.filter { $0.action != "shift" } + second)
        XCTAssertEqual(unsaid.posts, [ModelPage.Run.Post(id: j1, open: true),
                                      ModelPage.Run.Post(id: j2, open: false)],
                       "without the pane's word, the letter below closed")
    }

    /// A touch that lands within the second does nothing, even lifted after
    /// it; one that lands after the second is a tap, as before.
    func testATouchAfterTheSecondIsATapAgain() throws {
        let inside = try run(firstTap + [.down(1_550, y: 84), .up(1_700), .clickLine(1_710, j2)])
        XCTAssertEqual(inside.posts, [ModelPage.Run.Post(id: j1, open: true)])

        let after = try run(firstTap + [.down(1_650, y: 84), .up(1_710)])
        XCTAssertEqual(after.posts, [ModelPage.Run.Post(id: j1, open: true),
                                     ModelPage.Run.Post(id: j2, open: false)])
    }

    /// A finger already on a line as the word comes: the line moved under
    /// it on the glass, so its lift does nothing, as for a line that moved
    /// as letters above it grew, and WebKit's tap is stopped. The same
    /// touch with no word opens J1.
    func testAFingerDownAsTheStackMovesOpensNothing() throws {
        let steps: [Step] = [.down(500, y: 20), .shift(540), .up(600), .clickLine(610, j1)]
        let run = try run(steps)
        XCTAssertEqual(run.posts, [])
        XCTAssertEqual(run.stopped, 1)
        XCTAssertEqual(run.frames.last?.sections.first { $0.id == j1 }?.open, false)

        let unsaid = try self.run(steps.filter { $0.action != "shift" })
        XCTAssertEqual(unsaid.posts, [ModelPage.Run.Post(id: j1, open: true)])
    }

    /// The script, read: a second, a press in it not lit and its lift
    /// toggling nothing, and the word marking a press already down.
    func testTheScriptIgnoresALinePressedInTheSecondAfterTheWord() {
        let script = flat(ConversationDocument.script)
        for wiring in [
            "var bmShifted = -1e9; var bmShiftQuiet = 1000;",
            "var shifted = performance.now() - bmShifted < bmShiftQuiet; "
                + "if (!shifted) head.classList.add('bm-press');",
            "function bmPaneShifted() { bmShifted = performance.now(); if (!bmPress) return; "
                + "bmPress.shifted = true; bmPress.head.classList.remove('bm-press'); }",
            "event.preventDefault(); bmQuiet = { head: press.head, until: performance.now() + 1000 }; "
                + "if (performance.now() - press.at > bmHold) return; if (press.shifted) return;",
        ] {
            XCTAssertTrue(script.contains(wiring), wiring)
        }
        XCTAssertEqual(ConversationDocument.Shift.script, "bmPaneShifted()")
    }

    /// The pane tells the script every time the header changes height as a
    /// letter takes it, at the tap or as its body lands, and only then, in
    /// the app's content world, where the script is.
    func testThePaneTellsTheScriptWhenTheHeaderChangesHeight() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/UI/MessageDetailViewController.swift")
        let code = flat(try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n"))
        XCTAssertTrue(code.contains(
            "private func keepPlace(headerWas before: CGFloat) { view.layoutIfNeeded() "
            + "let grown = Double(header.frame.height - before) guard grown != 0 else { return } "
            + "webView.callAsyncJavaScript(ConversationDocument.Shift.script, arguments: [:], "
            + "in: nil, in: .defaultClient)"), "keepPlace")
        XCTAssertEqual(code.components(separatedBy: "ConversationDocument.Shift.script").count - 1, 1)
        XCTAssertEqual(code.components(separatedBy: "keepPlace(headerWas: before)").count - 1, 2,
                       "the tap's header and the landed letter's")
    }

    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }
}
