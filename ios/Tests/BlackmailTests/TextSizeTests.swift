import XCTest
@testable import Blackmail

/// B-166: the app's type follows the iPad's text size and Bold Text, as
/// Mail's does, live, where it was fixed at the factory size (D-007,
/// B-071). The parts that are not UIKit are run here: Apple's sizes, the
/// app at Large exactly as it was, a row's lines at every size with
/// nothing on it overlapping and the row growing, the date never cut up to
/// the largest of the seven ordinary sizes and on a line of its own at the
/// accessibility sizes, the heights a finger has to hit, the size read and
/// said once on the main queue after it is applied, the steps a sheet
/// keeps, and the reading pane's document drawn again at a new size. The
/// UIKit wiring is read from its source in `TextSizeWiringTests`.
final class TextSizeTests: XCTestCase {

    private typealias Step = TextSize.Step

    // MARK: - Apple's sizes, and Large as it was

    /// The twelve sizes iOS has, in its order, each with Apple's body size
    /// for it; Large, 17, the factory one, with Bold Text off; the five
    /// accessibility sizes the last five. The scale at Large is exactly 1.
    func testAppleSizesAndLargeIsTheFactory() {
        XCTAssertEqual(Step.allCases.map(\.body), [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53])
        XCTAssertEqual(Step.allCases.filter(\.isAccessibility),
                       [.accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
                        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge])
        XCTAssertEqual(TextSize.factory, TextSize(step: .large, bold: false))
        XCTAssertEqual(TextSize.factory.scale, 1)
        XCTAssertEqual(TextSize(step: .large, bold: true).scale, 1, "Bold Text changes no size")
        XCTAssertFalse(TextSize.factory.stacksRowDate)
        XCTAssertEqual(TextSize(step: .extraExtraExtraLarge, bold: false).scale, 23.0 / 17.0)
        XCTAssertEqual(TextSize(step: .accessibilityExtraExtraExtraLarge, bold: false).scaled(17), 53)
        XCTAssertNotEqual(TextSize.factory, TextSize(step: .large, bold: true),
                          "a switch of Bold Text alone is a change")
    }

    /// Every size the app's type and rows take, at Large, is the number it
    /// always was: each passes through `scaled` unchanged, the row's lines
    /// are its baselines in `Theme`, 24, 44, 64 and 84, the date on the
    /// names' line, a pitch of 20 and a height of 96, and the date's room
    /// on the top line is as it was at every width the list has.
    func testEveryNumberAtLargeIsAsItWas() throws {
        let large = TextSize.factory
        for points: CGFloat in [11, 12, 14, 15, 16, 17, 30, 32, 44, 60, 72, 96] {
            XCTAssertEqual(large.scaled(points), points)
        }
        XCTAssertEqual(large.tappable(44, floor: 44), 44)
        let lines = RowLines(large, names: 24, subject: 44, preview1: 64, preview2: 84, height: 96)
        XCTAssertEqual([lines.names, lines.date, lines.subject, lines.preview, lines.pitch, lines.height],
                       [24, 24, 44, 64, 20, 96])
        XCTAssertFalse(lines.stacked)
        for right: CGFloat in [285, 245, 360, 320] {
            for mark: CGFloat? in [nil, 18] {
                for date: CGFloat in [0, 68, 80, 1_000] {
                    XCTAssertEqual(RowTopLine(left: 29, right: right, mark: mark, gap: 5, date: date,
                                              scale: large.scale,
                                              stacked: large.stacksRowDate),
                                   RowTopLine(left: 29, right: right, mark: mark, gap: 5, date: date))
                }
            }
        }
        // The numbers handed to the row are Theme's, and are these.
        let theme = try Self.source("Theme/Theme.swift")
        for line in ["static let messageRowHeight: CGFloat = 96",
                     "static let senderBaseline: CGFloat = 24",
                     "static let subjectBaseline: CGFloat = 44",
                     "static let previewLine1Baseline: CGFloat = 64",
                     "static let previewLine2Baseline: CGFloat = 84",
                     "static var messageRowLines: RowLines { RowLines(textSize, names: senderBaseline, "
                        + "subject: subjectBaseline, preview1: previewLine1Baseline, "
                        + "preview2: previewLine2Baseline, height: messageRowHeight) }",
                     "static var textSize = TextSize.factory",
                     "static var textScale: CGFloat { textSize.scale }",
                     "static func scaled(_ points: CGFloat) -> CGFloat { (points * textScale).rounded() }"] {
            XCTAssertTrue(theme.contains(line), line)
        }
    }

    // MARK: - A row at every size

    /// The ink of a line of `points` type on `baseline`: SF's ascender and
    /// descender at 0.96 and 0.25 of the size, a little over UIKit's own
    /// for the system font, 16.2 and 4.1 at 17 pt.
    private func ink(_ baseline: CGFloat, _ points: CGFloat) -> ClosedRange<CGFloat> {
        (baseline - 0.96 * points)...(baseline + 0.25 * points)
    }

    /// At each of the twelve sizes a row's lines, the names at 17, the date,
    /// the subject and the two preview lines at 15, each scaled and rounded
    /// as `Theme`'s fonts are, lie one under the other with nothing of one
    /// over the next, and the last inside the row. The row grows with the
    /// size, and every accessibility size's row is taller than the largest
    /// of the seven's. At the accessibility sizes the date has the line
    /// under the names, a pitch lower, and the rest of the row is a pitch
    /// lower too.
    func testARowsLinesNeverOverlapAndTheRowGrows() {
        var heights: [CGFloat] = []
        for step in Step.allCases {
            let size = TextSize(step: step, bold: false)
            let lines = RowLines(size, names: 24, subject: 44, preview1: 64, preview2: 84, height: 96)
            let name = size.scaled(17)
            let small = size.scaled(15)
            var stack = [ink(lines.names, name)]
            if lines.stacked { stack.append(ink(lines.date, small)) }
            stack += [ink(lines.subject, small), ink(lines.preview, small),
                      ink(lines.preview + lines.pitch, small)]
            for (upper, lower) in zip(stack, stack.dropFirst()) {
                XCTAssertLessThan(upper.upperBound, lower.lowerBound, "\(step)")
            }
            XCTAssertGreaterThan(stack[0].lowerBound, 0, "\(step)")
            XCTAssertLessThan(stack[stack.count - 1].upperBound, lines.height, "\(step)")
            XCTAssertEqual(lines.stacked, step.isAccessibility, "\(step)")
            if lines.stacked {
                XCTAssertEqual(lines.date, 44 * size.scale, accuracy: 0.001, "\(step)")
                XCTAssertEqual(lines.subject, 64 * size.scale, accuracy: 0.001, "\(step)")
                XCTAssertEqual(lines.height, (116 * size.scale).rounded(), "\(step)")
            } else {
                XCTAssertEqual(lines.date, lines.names, "\(step)")
                XCTAssertEqual(lines.height, (96 * size.scale).rounded(), "\(step)")
            }
            heights.append(lines.height)
        }
        XCTAssertEqual(heights, heights.sorted())
        XCTAssertEqual(Set(heights).count, heights.count, "every size its own height")
        XCTAssertEqual(heights[3], 96)
        XCTAssertEqual(heights[6], 130, "the largest of the seven")
        XCTAssertEqual(heights.last, 362, "the largest of all")
        XCTAssertGreaterThan(heights[7], heights[6] * (28.0 / 23.0), "a line more than the type grew")
    }

    /// "Wednesday", the widest date the list writes, 80 points at 15
    /// (`ConversationRowLikeMailTests`), is never cut at any of the seven
    /// ordinary sizes, marked or not, in three panes and in two, in Edit
    /// mode, where UIKit's circles take more of the row at the larger
    /// sizes, and inside a conversation, set in 20: the date's room grows
    /// with its type, and the names give way. Nothing on the line is over
    /// anything else, and the names keep some of it.
    func testTheDateIsNeverCutAtTheSevenSizes() {
        for step in Step.allCases where !step.isAccessibility {
            let size = TextSize(step: step, bold: false)
            let wednesday = 80 * size.scaled(15) / 15
            let mark = 18 * size.scale
            for left: CGFloat in [29, 49] {
                for right: CGFloat in [285, 245, 233, 360, 320, 308] {
                    for marked in [false, true] {
                        let line = RowTopLine(left: left, right: right, mark: marked ? mark : nil, gap: 5,
                                              date: wednesday, scale: size.scale, stacked: false)
                        let at = "\(step) \(left) \(right) \(marked)"
                        XCTAssertGreaterThanOrEqual(line.dateWidth + 0.001, wednesday, at)
                        XCTAssertGreaterThan(line.namesWidth, 0, at)
                        XCTAssertLessThanOrEqual(line.namesX + line.namesWidth + 8, line.dateX + 0.001, at)
                        XCTAssertLessThanOrEqual(line.dateX + line.dateWidth, right + 0.001, at)
                        if let markX = line.markX {
                            XCTAssertEqual(line.dateX + line.dateWidth + 5, markX, accuracy: 0.001, at)
                            XCTAssertEqual(markX + mark, right, accuracy: 0.001, at)
                        }
                    }
                }
            }
        }
    }

    /// Above Large the names lose no more of the top line than the date
    /// needs: 110 points, as at Large, or the date's own width where that
    /// is more, never its 110 scaled with the type, which at the largest of
    /// the seven kept 149 of a three-pane line of 256 for "Wednesday"'s
    /// 107 and left the names 99. Under Large, as it was, scaled.
    func testTheNamesKeepAllButTheDatesRoom() {
        let largest = TextSize(step: .extraExtraExtraLarge, bold: false)
        let wednesday = 80 * largest.scaled(15) / 15
        let line = RowTopLine(left: 29, right: 285, mark: nil, gap: 5, date: wednesday,
                              scale: largest.scale)
        XCTAssertEqual(line.dateWidth, 110)
        XCTAssertEqual(line.namesWidth, 138, "256 less the date's 110 and the 8 between")
        let wide = RowTopLine(left: 29, right: 285, mark: nil, gap: 5, date: 120, scale: largest.scale)
        XCTAssertEqual(wide.dateWidth, 120, "a date wider than 110 has its own width")
        XCTAssertEqual(wide.namesWidth, 128)
        let narrow = RowTopLine(left: 49, right: 120, mark: nil, gap: 5, date: 120, scale: largest.scale)
        XCTAssertEqual(narrow.dateWidth, 71 * 0.45 * largest.scale, accuracy: 0.001,
                       "never more than the line's scaled share")
        let small = TextSize(step: .extraSmall, bold: false)
        let under = RowTopLine(left: 29, right: 285, mark: nil, gap: 5, date: 60, scale: small.scale)
        XCTAssertEqual(under.dateWidth, min(110 * small.scale, 256 * 0.45 * small.scale), accuracy: 0.001)
    }

    /// The reply or forward arrow's square, centred on the dot's 14 points
    /// from the row's edge with the names at 29, grows with the type and
    /// never past the gutter, which stays as at Large: inside the row's
    /// left edge and a point short of the names at every size, 12 at
    /// Large, scaled up to the third accessibility size, 28 at the two
    /// largest, where scaled it was 33 and 37 and ran off the edge and into
    /// the names.
    func testTheArrowStaysInTheGutter() {
        var boxes: [CGFloat] = []
        for step in Step.allCases {
            let size = TextSize(step: step, bold: false)
            let box = RowLines.gutterBox(12, at: size, centre: 14, textLeft: 29)
            XCTAssertGreaterThanOrEqual(14 - box / 2, 0, "\(step)")
            XCTAssertLessThanOrEqual(14 + box / 2, 28, "\(step)")
            if step <= .accessibilityExtraLarge { XCTAssertEqual(box, size.scaled(12), "\(step)") }
            boxes.append(box)
        }
        XCTAssertEqual(boxes[3], 12)
        XCTAssertEqual(boxes, boxes.sorted())
        XCTAssertEqual(boxes.suffix(2), [28, 28])
        // An indented row, a conversation's own letter, moves the dot and the
        // names alike, so its gutter is the same.
        XCTAssertEqual(RowLines.gutterBox(12, at: TextSize(step: .accessibilityExtraExtraExtraLarge, bold: false),
                                          centre: 14 + 20, textLeft: 29 + 20), 28)
    }

    /// At the accessibility sizes the names have the whole line, and the
    /// date the line under them, ending where it always ends, before the
    /// mark on a marked row, and as wide as the line leaves it.
    func testAtTheAccessibilitySizesTheDateHasALineOfItsOwn() {
        let size = TextSize(step: .accessibilityExtraExtraExtraLarge, bold: false)
        XCTAssertTrue(size.stacksRowDate)
        let marked = RowTopLine(left: 29, right: 285, mark: 50, gap: 5, date: 230,
                                scale: size.scale, stacked: true)
        XCTAssertEqual(marked.namesX, 29)
        XCTAssertEqual(marked.namesWidth, 256)
        XCTAssertEqual(marked.markX, 235)
        XCTAssertEqual(marked.dateX, 29)
        XCTAssertEqual(marked.dateWidth, 201, "to 5 before the mark")
        let plain = RowTopLine(left: 29, right: 285, mark: nil, gap: 5, date: 230,
                               scale: size.scale, stacked: true)
        XCTAssertNil(plain.markX)
        XCTAssertEqual(plain.dateX + plain.dateWidth, 285)
        XCTAssertEqual(plain.namesWidth, 256)
    }

    /// A height a finger hits is never under 44, however small the size:
    /// a folder's row and a line of the composer at the three sizes under
    /// Large are 44, as at Large; above it they grow with the type.
    func testATappableHeightIsNeverUnder44() {
        for step in Step.allCases {
            let size = TextSize(step: step, bold: false)
            let row = size.tappable(44, floor: 44)
            if step <= .large {
                XCTAssertEqual(row, 44, "\(step)")
            } else {
                XCTAssertEqual(row, size.scaled(44), "\(step)")
                XCTAssertGreaterThan(row, 44, "\(step)")
            }
        }
        let theme = try? Self.source("Theme/Theme.swift")
        XCTAssertTrue(theme?.contains("static var mailboxRowHeightScaled: CGFloat { "
                                      + "textSize.tappable(mailboxRowHeight, floor: minHitTarget) }") ?? false)
        XCTAssertTrue(theme?.contains("static var lineHeight: CGFloat { "
                                      + "textSize.tappable(minHitTarget, floor: minHitTarget) }") ?? false)
    }

    // MARK: - Read, applied, said

    private final class Heard {
        var applied: [TextSize] = []
        var said: [TextSize] = []
        var main: [Bool] = []
    }

    private func settle() {
        let drained = expectation(description: "the main queue ran")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
    }

    /// The size is read and applied as the watch is made, before any screen
    /// is. At iOS's word it is read again on the main queue, applied, and
    /// only then said, on the main queue, so a screen drawing at the word
    /// reads the new one; once for words that come together, and not at
    /// all for a word with nothing changed. Bold Text alone is a change.
    /// A word said on another thread is read on the main queue all the same.
    func testTheSizeIsAppliedThenSaidOnceOnTheMainQueue() {
        let center = NotificationCenter()
        let word = Notification.Name("TextSizeTestsWord")
        var now = TextSize.factory
        let heard = Heard()
        var applied: TextSize?
        let sizes = TextSizes(notifications: center, names: [word], read: { now },
                              apply: { size in heard.applied.append(size); applied = size })
        XCTAssertEqual(heard.applied, [.factory], "applied as it is made")
        let token = center.addObserver(forName: TextSizes.didChange, object: nil, queue: nil) { note in
            guard (note.object as AnyObject?) === sizes else { return }
            heard.said.append(applied ?? .factory)
            heard.main.append(Thread.isMainThread)
        }
        defer { center.removeObserver(token) }

        now = TextSize(step: .extraExtraExtraLarge, bold: false)
        center.post(name: word, object: nil)
        center.post(name: word, object: nil)
        XCTAssertEqual(heard.said, [], "not before the main queue has run")
        settle()
        XCTAssertEqual(heard.applied.last, now)
        XCTAssertEqual(heard.said, [now], "said once, after it was applied")
        XCTAssertEqual(sizes.current, now)

        center.post(name: word, object: nil)
        settle()
        XCTAssertEqual(heard.said.count, 1, "nothing changed, nothing said")

        now = TextSize(step: .extraExtraExtraLarge, bold: true)
        let away = expectation(description: "said on another thread")
        DispatchQueue.global().async {
            center.post(name: word, object: nil)
            away.fulfill()
        }
        wait(for: [away], timeout: 5)
        settle()
        XCTAssertEqual(heard.said, [TextSize(step: .extraExtraExtraLarge, bold: false), now])
        XCTAssertEqual(heard.main, [true, true])
        XCTAssertEqual(heard.applied.count, 3)
    }

    /// A screen's steps run as each is kept, and all of them again, in the
    /// order kept, at each change.
    func testRestylesRunAtOnceAndAgainInOrder() {
        let restyles = Restyles()
        var ran: [String] = []
        restyles.keep { ran.append("caption") }
        restyles.keep { ran.append("line") }
        XCTAssertEqual(ran, ["caption", "line"])
        restyles.again()
        restyles.again()
        XCTAssertEqual(ran, ["caption", "line", "caption", "line", "caption", "line"])
    }

    // MARK: - The reading pane drawn again at a new size

    private typealias Server = ScriptedIMAPServer

    private final class Navigation {}

    private func entry(_ id: String, open: Bool = false) -> ConversationDocument.Entry {
        ConversationDocument.Entry(id: id, sender: "Sam Example <sam@example.com>",
                                   date: Server.newestDate, body: nil, isExpanded: open,
                                   preview: "A few words")
    }

    private let letter = Message.heading(for: MessageSummary(
        id: "7/3", mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
        subject: "The garden", preview: "", date: Server.newestDate,
        isRead: true, isFlagged: false))

    /// What the pane shows is handed back to be drawn at the new size, with
    /// nothing in the document changed by it: the letter, to have its page
    /// built anew; a conversation as a redraw has it, its stack bare and
    /// the bodies that came, in its order, with which letters are open; the
    /// grey words; and nothing for a pane with nothing of a letter's.
    func testThePaneIsHandedBackToBeDrawnAtTheNewSize() throws {
        var document = PaneDocument()
        XCTAssertNil(document.restyled(), "nothing yet")
        document.loaded(.blank, navigation: nil)
        XCTAssertNil(document.restyled(), "the empty page")

        document.loaded(.letter(letter, page: "<p>at 17</p>"), navigation: nil)
        guard case .letter(let again, _)? = document.restyled()?.content else {
            return XCTFail("the letter")
        }
        XCTAssertEqual(again.id, "7/3")
        XCTAssertNotNil(document.restyled(), "as often as the size changes")

        document.loaded(.notice([PaneNotice.loading]), navigation: nil)
        guard case .notice(let lines)? = document.restyled()?.content else {
            return XCTFail("the grey words")
        }
        XCTAssertEqual(lines, [PaneNotice.loading])

        document.loaded(.conversation([entry("7/3", open: true), entry("7/2"), entry("7/1")]),
                        navigation: nil)
        let body = ConversationDocument.Entry.Rendered(html: "Dear Sam,", isHTML: false)
        _ = document.fill("7/3", with: body)
        document.setOpen(true, "7/1")
        let restyle = try XCTUnwrap(document.restyled())
        guard case .conversation(let stack) = restyle.content else { return XCTFail("the stack") }
        XCTAssertEqual(stack.map(\.id), ["7/3", "7/2", "7/1"])
        XCTAssertEqual(stack.map(\.isExpanded), [true, false, true])
        XCTAssertEqual(stack.map(\.body), [nil, nil, nil], "no body in the document")
        XCTAssertEqual(restyle.bodies.map(\.id), ["7/3"])
        XCTAssertEqual(restyle.bodies.map(\.body), [body])
        XCTAssertEqual(document.body(of: "7/3"), body, "the document as it was")
        XCTAssertNil(document.redraw(), "nothing was lost")
    }

    /// With the document lost to WebKit, the size's redraw is the loss's
    /// redraw, drawn at once, and the one that would have followed has
    /// nothing left to do; lost again at once, it is a document drawn again,
    /// and the pane says it could not be shown, as `PaneDocument` has it.
    func testALostDocumentIsRedrawnOnceAtTheNewSize() throws {
        var document = PaneDocument()
        document.loaded(.letter(letter, page: "<p>at 17</p>"), navigation: nil)
        document.contentProcessEnded()
        let restyle = try XCTUnwrap(document.restyled())
        guard case .letter = restyle.content else { return XCTFail("the letter") }
        XCTAssertNil(document.redraw(), "drawn already")
        let navigation = Navigation()
        document.loaded(restyle.content, navigation: ObjectIdentifier(navigation))
        document.contentProcessEnded()
        guard case .notice(let lines) = try XCTUnwrap(document.redraw()).content else {
            return XCTFail("the words")
        }
        XCTAssertEqual(lines, [PaneDocument.cannotShow])
    }

    // MARK: - A conversation's lines

    /// At the accessibility sizes each part of a letter's line in a
    /// conversation has a line of its own: the line wraps, the name takes
    /// the width and may go on to a second line, the date comes under it at
    /// its left, and a closed letter's first words under that. The rules
    /// come after the line's own, which they override, and only then: at
    /// every other size the document is as it was, to the byte.
    func testAConversationsLinesStackAtTheAccessibilitySizes() {
        let stack = [entry("7/3", open: true), entry("7/2")]
        let plain = ConversationDocument.html(entries: stack, inset: 20, bodyPointSize: 17, lineHeight: 1.41)
        XCTAssertEqual(ConversationDocument.html(entries: stack, inset: 20, bodyPointSize: 17, lineHeight: 1.41,
                                                 stacked: false), plain)
        XCTAssertFalse(plain.contains("flex-wrap"))
        let big = ConversationDocument.html(entries: stack, inset: 20, bodyPointSize: 53, lineHeight: 1.41,
                                            stacked: true)
        let rules = ConversationDocument.stackedLines
        for rule in [".bm-head { flex-wrap: wrap; }",
                     ".bm-from { flex: 1 1 100%; min-width: 0; overflow-wrap: anywhere; }",
                     ".bm-when { flex: 1 1 100%; margin-left: 0; order: 1; }",
                     ".bm-peek { flex: 1 1 100%; min-width: 0; order: 2; }"] {
            XCTAssertTrue(rules.contains(rule), rule)
        }
        XCTAssertFalse(rules.contains("white-space"), "the name is never held to one line")
        guard let own = big.range(of: ".bm-when { color: #8e8e93; font-size: 50px;"),
              let over = big.range(of: rules), let end = big.range(of: "</style>") else {
            return XCTFail("the rules")
        }
        XCTAssertLessThan(own.lowerBound, over.lowerBound, "after the line's own rules")
        XCTAssertLessThan(over.upperBound, end.lowerBound, "in the style sheet")
        let sized = ConversationDocument.html(entries: stack, inset: 20, bodyPointSize: 53, lineHeight: 1.41)
        XCTAssertEqual(big.replacingOccurrences(of: rules, with: ""), sized, "nothing else")
    }

    // MARK: - Helpers

    /// `path` under `Sources/Blackmail`, comment lines out and white space
    /// as one space, as `SteadyChromeTests` reads it.
    static func source(_ path: String) throws -> String {
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
