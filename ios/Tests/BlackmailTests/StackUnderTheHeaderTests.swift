import XCTest
@testable import Blackmail

/// A conversation's stack under a header that changes height (B-128).
///
/// The header over the stack names the letter he opened, and grows by a Cc
/// line, or a 44 pt row per file, for a letter that has them, and shrinks
/// for one that has fewer. B-074 scrolled the stack by as much the other
/// way, so the line he tapped stayed where it was on the glass; but the
/// glass under the header's new bottom edge is the header's, so the top of
/// the pane went under it. Seen on the test iPad in B-055's and B-095's
/// checks: a header that gained a Cc line at a tap in the stack left the
/// stack's first line half under it until he scrolled. Now the stack keeps
/// its offset and hangs from the header: what was at the top of the pane
/// stays there, wholly under the header.
///
/// The glass is modelled as the pane lays it out: the stack's web view
/// pinned to the header's bottom edge, a line at `top` in the stack drawn
/// at the header's bottom plus `top` less the offset the stack is scrolled
/// to. The offset after the change is the one `keepPlace` sets.
final class StackUnderTheHeaderTests: XCTestCase {

    /// The pane's own heights, near enough: a closed line about 45 pt, 12
    /// above and below a line of text; a Cc line about 20; a file's row 44.
    private let line = 45.0
    private let cc = 20.0
    private let fileRow = 44.0

    /// Where the top of a line at `top` in the stack is on the glass.
    private func onGlass(_ top: Double, headerBottom: Double, offset: Double) -> Double {
        headerBottom + top - offset
    }

    /// The offset `keepPlace` leaves the stack at once the header has
    /// grown by `grown`.
    private func after(_ current: Double, grew grown: Double, range: ClosedRange<Double>) -> Double {
        StackPlace.offset(from: current, headerGrewBy: grown, range: range) ?? current
    }

    /// The stack at its very top, its first line at the top of the pane: the
    /// header gains a Cc line, or a Cc line and two files' rows, and the
    /// line is still wholly under it, at its new bottom edge. B-074's rule
    /// put it 20 pt, half a line, under the header.
    func testTheStacksFirstLineStaysWhollyUnderAHeaderThatGains() {
        let header = 200.0
        for grown in [cc, cc + 2 * fileRow, fileRow] {
            let offset = after(0, grew: grown, range: 0...4_000)
            XCTAssertEqual(onGlass(0, headerBottom: header + grown, offset: offset), header + grown,
                           "grown by \(grown): the first line's top at the header's new bottom")
        }
    }

    /// The stack as it opens, the line of the letter before the one it
    /// opens at at the top of the pane (`ConversationDocument.opensAt`),
    /// and that line tapped, the commonest line to tap: a header that gains
    /// leaves it wholly under it, at the top of the pane; a header that
    /// loses a Cc line leaves it at the top too, with nothing of the line
    /// above it showing, where B-074's rule drew 20 pt of that line over it.
    func testTheLineAtTheTopOfThePaneStaysAtTheTopWhicheverWayTheHeaderChanges() {
        let header = 200.0
        let tapped = line              // the second line, the first above it out of sight
        for grown in [cc, -cc, fileRow, -fileRow, cc + 3 * fileRow, -(cc + fileRow)] {
            let offset = after(tapped, grew: grown, range: 0...4_000)
            let bottom = header + grown
            XCTAssertEqual(onGlass(tapped, headerBottom: bottom, offset: offset), bottom,
                           "grown by \(grown): the tapped line at the top of the pane, whole")
            XCTAssertLessThanOrEqual(onGlass(tapped - line, headerBottom: bottom, offset: offset) + line,
                                     bottom, "grown by \(grown): nothing of the line above in sight")
        }
    }

    /// Whatever the change and wherever the stack is scrolled, nothing that
    /// was in sight under the header goes under it: the offset never grows.
    /// It is the one it had, or, where a header that shrank leaves the
    /// stack past its end, its end, which moves the stack down; and always
    /// one the stack can be scrolled to.
    func testNothingInSightGoesUnderTheHeader() {
        for grown in [-132.0, -44, -20, -0.5, 0.5, 20, 44, 132] {
            for highest in [0.0, 300, 980, 1_000, 4_000] {
                for current in stride(from: 0.0, through: 1_000, by: 25) {
                    let offset = after(current, grew: grown, range: 0...highest)
                    XCTAssertLessThanOrEqual(offset, max(current, 0), "\(grown) \(highest) \(current)")
                    XCTAssertTrue((0...highest).contains(offset), "\(grown) \(highest) \(current)")
                    if current <= highest {
                        XCTAssertEqual(offset, current, "kept: \(grown) \(highest) \(current)")
                    }
                }
            }
        }
    }

    /// In the pane, the header's change sets the offset by `StackPlace`
    /// alone, once laid out, and nothing else in it scrolls the stack.
    func testThePaneScrollsTheStackOnlyByStackPlace() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/UI/MessageDetailViewController.swift")
        let code = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .joined(separator: " ")
        XCTAssertEqual(code.components(separatedBy: "contentOffset").count, 3,
                       "read once and written once, both in `keepPlace`")
        XCTAssertTrue(code.contains(
            "guard let y = StackPlace.offset(from: Double(scroll.contentOffset.y), "
            + "headerGrewBy: Double(header.frame.height - before), range: lowest...highest) "
            + "else { return } scroll.contentOffset.y = CGFloat(y) }"))
        XCTAssertFalse(code.contains("setContentOffset"))
        XCTAssertFalse(code.contains("scrollRectToVisible"))
    }
}
