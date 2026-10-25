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
    /// grown by `grown`, the stack's top at `lowest`.
    private func after(_ current: Double, grew grown: Double, lowest: Double = 0) -> Double {
        StackPlace.offset(from: current, headerGrewBy: grown, lowest: lowest) ?? current
    }

    /// The stack at its very top, its first line at the top of the pane: the
    /// header gains a Cc line, or a Cc line and two files' rows, and the
    /// line is still wholly under it, at its new bottom edge. B-074's rule
    /// put it 20 pt, half a line, under the header.
    func testTheStacksFirstLineStaysWhollyUnderAHeaderThatGains() {
        let header = 200.0
        for grown in [cc, cc + 2 * fileRow, fileRow] {
            let offset = after(0, grew: grown)
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
            let offset = after(tapped, grew: grown)
            let bottom = header + grown
            XCTAssertEqual(onGlass(tapped, headerBottom: bottom, offset: offset), bottom,
                           "grown by \(grown): the tapped line at the top of the pane, whole")
            XCTAssertLessThanOrEqual(onGlass(tapped - line, headerBottom: bottom, offset: offset) + line,
                                     bottom, "grown by \(grown): nothing of the line above in sight")
        }
    }

    /// Whatever the change and wherever the stack is scrolled, nothing that
    /// was in sight under the header goes under it: the offset never grows.
    /// It is the one it had, or, for a stack pulled down past its top as
    /// the header changes, its top, as before.
    func testNothingInSightGoesUnderTheHeader() {
        for grown in [-132.0, -44, -20, -0.5, 0.5, 20, 44, 132] {
            for lowest in [0.0, -20] {
                for current in stride(from: -60.0, through: 1_000, by: 25) {
                    let offset = after(current, grew: grown, lowest: lowest)
                    XCTAssertEqual(offset, max(current, lowest), "\(grown) \(lowest) \(current)")
                }
            }
        }
        XCTAssertNil(StackPlace.offset(from: -30, headerGrewBy: 0, lowest: 0), "no change, nothing done")
    }

    /// A stack opened with its newest letter short, the line above it at
    /// the top of the pane, which puts the offset 45 pt from the end: the
    /// last letter is as tall as the pane (`min-height: 100vh`), its line
    /// and its body inside that. The header shrinks by a Cc line and a
    /// file's row, 64 pt, or by two rows and a Cc line, 108. The offset is
    /// the one it had, though the end the scroll view has as `keepPlace`
    /// runs, the page as it was before WebKit lays it out for the taller
    /// pane, is that much nearer; laid out again, the last letter grows
    /// with the pane, the end is where it was, and the line is the top
    /// line, whole, nothing of the line above it in sight. Held to the old
    /// end, the stack was pulled down to it, and 19 pt of the line above
    /// showed at the top and stayed; for 108, all of it and 18 pt of the
    /// line before.
    func testAShortNewestLetterAtTheEndKeepsTheLineAtTheTopWhenTheHeaderShrinks() {
        let header = 264.0, pane = 600.0
        let above = 4 * line                       // four closed lines over the newest
        let held = above - line                    // the fourth line at the top of the pane
        for shrunk in [cc + fileRow, cc + 2 * fileRow] {
            let stale = above + pane - (pane + shrunk)
            XCTAssertLessThan(stale, held, "the old page's end is nearer than the offset")
            let offset = after(held, grew: -shrunk)
            XCTAssertEqual(offset, held, "shrunk by \(shrunk): kept")
            let end = above + (pane + shrunk) - (pane + shrunk)
            XCTAssertLessThanOrEqual(offset, end, "one the page laid out again can scroll to")
            let bottom = header - shrunk
            XCTAssertEqual(onGlass(held, headerBottom: bottom, offset: offset), bottom)
            XCTAssertLessThanOrEqual(onGlass(held - line, headerBottom: bottom, offset: offset) + line, bottom,
                                     "shrunk by \(shrunk): nothing of the line above in sight")
        }
    }

    /// In the pane, the header's change sets the offset by `StackPlace`
    /// alone, once laid out, held at the stack's top alone, and nothing
    /// else in it scrolls the stack.
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
            "guard let y = StackPlace.offset(from: Double(scroll.contentOffset.y), headerGrewBy: grown, "
            + "lowest: -Double(scroll.adjustedContentInset.top)) "
            + "else { return } scroll.contentOffset.y = CGFloat(y) }"))
        XCTAssertFalse(code.contains("contentSize"), "the stack's end is not held to")
        XCTAssertFalse(code.contains("setContentOffset"))
        XCTAssertFalse(code.contains("scrollRectToVisible"))
    }
}
