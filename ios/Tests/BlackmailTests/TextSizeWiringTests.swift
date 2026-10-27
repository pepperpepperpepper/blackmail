import XCTest
@testable import Blackmail

/// B-166's UIKit wiring, read from the source, as `SteadyChromeTests` reads
/// B-071's: comment lines out, and runs of white space as one space. What
/// the size does is run in `TextSizeTests`; here, that the app reads the
/// iPad's before its first screen and at each change, that each screen
/// named in the ruling, the list's rows, the Mailboxes, the reading pane's
/// header and its letter, the composer and the share sheet, sets its type
/// again when it changes, and that the bars and the bands of a fixed
/// height keep theirs.
final class TextSizeWiringTests: XCTestCase {

    private func source(_ path: String) throws -> String { try TextSizeTests.source(path) }

    private func place(of text: String, in code: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String.Index? {
        let found = code.range(of: text)?.lowerBound
        XCTAssertNotNil(found, text, file: file, line: line)
        return found
    }

    private func count(_ text: String, in code: String) -> Int {
        code.components(separatedBy: text).count - 1
    }

    /// From `start` to `end` in `code`, failing if either is not there.
    private func section(_ code: String, from start: String, to end: String) throws -> String {
        let begin = try XCTUnwrap(code.range(of: start), start)
        let rest = code[begin.upperBound...]
        let stop = try XCTUnwrap(rest.range(of: end), end)
        return String(rest[..<stop.lowerBound])
    }

    // MARK: - Read before the first screen, and at each change

    /// The app's size is read at launch, before the first screen is made,
    /// from what iOS hands the app, the Per-App size among it, with Bold
    /// Text; read again at iOS's words for either, and as the app comes
    /// back; and put in `Theme`. UIKit's twelve names are the twelve sizes
    /// in their order, an unspecified one Large.
    func testTheAppReadsTheIPadsSizeBeforeItsFirstScreen() throws {
        let app = try source("App/AppDelegate.swift")
        let read = try XCTUnwrap(place(of: "_ = TextSizes.app", in: app))
        let first = try XCTUnwrap(place(of: "window.rootViewController = Self.makeRoot()", in: app))
        XCTAssertLessThan(read, first)

        let reading = try source("Theme/TextSizeReading.swift")
        XCTAssertNotNil(place(of: "static let app = TextSizes( names: [UIContentSizeCategory.didChangeNotification, "
                                  + "UIAccessibility.boldTextStatusDidChangeNotification, "
                                  + "UIApplication.didBecomeActiveNotification], "
                                  + "read: { TextSize(UIApplication.shared.preferredContentSizeCategory) }, "
                                  + "apply: { Theme.textSize = $0 })", in: reading))
        XCTAssertNotNil(place(of: "self.init(step: Step(category), bold: UIAccessibility.isBoldTextEnabled)",
                              in: reading))
        let mapping = try section(reading, from: "init(_ category: UIContentSizeCategory) { switch category {",
                                  to: "default: self = .large }")
        let cases = mapping.components(separatedBy: "case .").dropFirst().map {
            String($0.prefix(while: { $0 != ":" }))
        }
        let steps = TextSize.Step.allCases.map { "\($0)" }
        XCTAssertEqual(cases, steps)
        for step in steps { XCTAssertTrue(mapping.contains("case .\(step): self = .\(step)"), step) }
    }

    /// The share sheet has no `UIApplication`: it reads its own traits,
    /// before anything of the sheet is made, again as they change and as
    /// the sheet appears, and never the screen's, which the app's style
    /// rule keeps out (`InfoPlistTests`).
    func testTheShareSheetReadsItsOwnTraits() throws {
        let share = try source("Share/ShareViewController.swift")
        XCTAssertFalse(share.contains("UIApplication.shared"))
        XCTAssertFalse(share.contains("UIScreen.main.traitCollection"))
        XCTAssertNotNil(place(of: "read: { [weak self] in "
                                  + "TextSize(self?.traitCollection.preferredContentSizeCategory ?? .unspecified) }, "
                                  + "apply: { Theme.textSize = $0 })", in: share))
        let load = try section(share, from: "public override func viewDidLoad() { super.viewDidLoad()",
                               to: "nav.view.tintAdjustmentMode")
        XCTAssertTrue(load.hasPrefix(" _ = sizes "), load)
        XCTAssertNotNil(place(of: "if previous?.preferredContentSizeCategory != "
                                  + "traitCollection.preferredContentSizeCategory { sizes.look() }", in: share))
        XCTAssertNotNil(place(of: "presentationController?.delegate = self sizes.look() }", in: share))
    }

    // MARK: - The type, and what keeps its size

    /// The type of the rows, the Mailboxes, the header and the letter goes
    /// through `scaled`; the bars', the line under the list's, and the
    /// fixed controls' does not, as UIKit's bars keep theirs.
    func testTheBarsKeepTheirSizeAndTheWordsFollow() throws {
        let theme = try source("Theme/Theme.swift")
        for font in ["fontListSender", "fontListSubject", "fontListPreview", "fontListTimestamp",
                     "fontMailboxName", "fontMailboxCount", "fontDetailSender", "fontDetailMeta",
                     "fontDetailSubject"] {
            let line = try section(theme, from: "static var \(font): UIFont {", to: "}")
            XCTAssertTrue(line.contains("scaled("), font)
        }
        for (font, size) in [("fontNavTitle", "17, weight: .semibold"), ("fontBarButton", "17"),
                             ("fontToolbarStatus", "11"), ("fontControl", "15")] {
            let line = try section(theme, from: "static var \(font): UIFont {", to: "}")
            XCTAssertEqual(line, " .systemFont(ofSize: \(size)) ", font)
        }
        let band = try source("UI/SearchHeaderView.swift")
        for wiring in ["field.font = Theme.fontControl",
                       "label.text = \"Search\" label.font = Theme.fontControl",
                       "[.foregroundColor: Theme.secondaryText, .font: Theme.fontControl], for: .normal)",
                       "[.foregroundColor: UIColor.white, .font: Theme.fontControl], for: .selected)"] {
            XCTAssertNotNil(place(of: wiring, in: band))
        }
        let jump = try source("UI/JumpToDateViewController.swift")
        XCTAssertEqual(count(".font: Theme.fontControl]", in: jump), 2)
        XCTAssertNotNil(place(of: "explain.font = Theme.fontControl", in: jump))
        XCTAssertFalse(jump.contains("fontDetailMeta"))
    }

    // MARK: - Each screen at a change

    /// The list's rows: each cell sets its type, and the mark drawn at the
    /// date's size, as it is made and whenever it is given a row after the
    /// size changed; it places its lines by `RowLines`, the date on its own
    /// line at the accessibility sizes, and never by Theme's baselines at
    /// Large alone. The list sets the rows' height and draws them again by
    /// a regroup, which holds his place, at the change.
    func testTheListsRowsFollowTheSize() throws {
        let cell = try source("UI/MessageCell.swift")
        XCTAssertNotNil(place(of: "func configure(with m: MessageSummary, marked: Bool) { restyle()", in: cell))
        XCTAssertNotNil(place(of: "private func restyle() { guard styled != Theme.textSize else { return } "
                                  + "styled = Theme.textSize senderLabel.font = Theme.fontListSender "
                                  + "timestampLabel.font = Theme.fontListTimestamp "
                                  + "subjectLabel.font = Theme.fontListSubject "
                                  + "previewLabel.font = Theme.fontListPreview "
                                  + "conversationMark.image = UIImage(systemName: \"chevron.forward.circle\", "
                                  + "withConfiguration: Theme.conversationMarkSymbol) setNeedsLayout() }", in: cell))
        XCTAssertEqual(count("restyle()", in: cell), 3, "declared, in the initializer and in configure")
        XCTAssertNotNil(place(of: "let lines = Theme.messageRowLines", in: cell))
        XCTAssertNotNil(place(of: "let figures = lines.date - timestampLabel.font.capHeight / 2", in: cell))
        XCTAssertNotNil(place(of: "place(subjectLabel, baseline: lines.subject, left: left, width: subjectWidth)",
                              in: cell))
        XCTAssertNotNil(place(of: "let pitch = lines.pitch let firstBaseline = lines.preview", in: cell))
        XCTAssertNotNil(place(of: "ps.minimumLineHeight = Theme.messageRowLines.pitch", in: cell))
        XCTAssertNotNil(place(of: "let y = ((baseline - label.font.ascender) * scale).rounded() / scale",
                              in: cell))
        for large in ["Theme.senderBaseline", "Theme.subjectBaseline", "Theme.previewLine1Baseline",
                      "Theme.previewLine2Baseline"] {
            XCTAssertFalse(cell.contains(large), large)
        }

        let list = try source("UI/MessageListViewController.swift")
        XCTAssertNotNil(place(of: "NotificationCenter.default.addObserver(self, selector: #selector(textSizeChanged), "
                                  + "name: TextSizes.didChange, object: nil)", in: list))
        XCTAssertNotNil(place(of: "@objc private func textSizeChanged() { "
                                  + "tableView.rowHeight = Theme.messageRowHeightScaled "
                                  + "emptyLabel.font = Theme.fontListSubject searchBar.restyle() regroup() }",
                              in: list))
        let band = try source("UI/SearchHeaderView.swift")
        XCTAssertNotNil(place(of: "func restyle() { recentHeading.font = Theme.fontListSender "
                                  + "for row in recentRows { row.restyle() } setNeedsLayout() }", in: band))
    }

    /// The Mailboxes: the rows at their height and drawn again, the
    /// highlight put back, at the change; their names, counts and icons
    /// read from `Theme` as each row is drawn.
    func testTheMailboxesFollowTheSize() throws {
        let folders = try source("UI/MailboxListViewController.swift")
        XCTAssertNotNil(place(of: "NotificationCenter.default.addObserver(self, selector: #selector(textSizeChanged), "
                                  + "name: TextSizes.didChange, object: nil)", in: folders))
        XCTAssertNotNil(place(of: "@objc private func textSizeChanged() { "
                                  + "tableView.rowHeight = Theme.mailboxRowHeightScaled redraw() }", in: folders))
        let configure = try section(folders, from: "private func configure(_ cell: UITableViewCell, "
                                        + "with mailbox: Mailbox) {", to: "cell.accessibilityLabel")
        for wiring in ["content.textProperties.font = Theme.fontMailboxName",
                       "content.image = Theme.symbol(icon(for: mailbox.role))",
                       "label.font = Theme.fontMailboxCount"] {
            XCTAssertTrue(configure.contains(wiring), wiring)
        }
    }

    /// The reading pane: the header's type at once; the letter drawn again
    /// at the new size from what the pane holds, its page built anew, once
    /// the pane can be seen and the app is in front, and owed until then.
    func testTheReadingPaneFollowsTheSize() throws {
        let pane = try source("UI/MessageDetailViewController.swift")
        XCTAssertNotNil(place(of: "NotificationCenter.default.addObserver(self, selector: #selector(textSizeChanged), "
                                  + "name: TextSizes.didChange, object: nil)", in: pane))
        XCTAssertNotNil(place(of: "@objc private func textSizeChanged() { header.restyle() "
                                  + "placeholder.font = Theme.fontDetailMeta restyleOwed = true restyleIfOwed() }",
                              in: pane))
        let owed = try section(pane, from: "private func restyleIfOwed() {",
                               to: "@objc private func datesChanged()")
        for wiring in ["guard restyleOwed, UIApplication.shared.applicationState == .active, "
                        + "viewIfLoaded?.window != nil else { return } restyleOwed = false "
                        + "guard let again = document.restyled() else { return }",
                       "case .letter(let m, _):",
                       "draw(m, page: PanePage.letter(m, style: pageStyle))",
                       "renderConversation(entries) for (id, body) in again.bodies { fill(id, body) }",
                       "case .notice(let lines): renderNotice(lines)"] {
            XCTAssertTrue(owed.contains(wiring), wiring)
        }
        XCTAssertNotNil(place(of: "super.viewDidAppear(animated) drawAgain() restyleIfOwed() }", in: pane))
        XCTAssertNotNil(place(of: "@objc private func appBecameActive() { drawAgain() restyleIfOwed() }", in: pane))
        XCTAssertNotNil(place(of: ".init(inset: Int(Theme.detailContentInsetLeft), "
                                  + "bodyPointSize: Int(Theme.scaled(17)),", in: pane))

        let header = try source("UI/MessageHeaderView.swift")
        XCTAssertNotNil(place(of: "func restyle() { senderLabel.font = Theme.fontDetailSender "
                                  + "toLabel.font = Theme.fontDetailMeta ccLabel.font = Theme.fontDetailMeta "
                                  + "subjectLabel.font = Theme.fontDetailSubject "
                                  + "dateLabel.font = Theme.fontDetailMeta "
                                  + "for button in attachmentButtons.values { "
                                  + "button.configuration?.image = Theme.symbol(\"paperclip\") "
                                  + "button.configuration?.preferredSymbolConfigurationForImage = Theme.symbolSize "
                                  + "button.configuration?.attributedTitle?.font = Theme.fontDetailMeta } "
                                  + "setNeedsLayout() }", in: header))
    }

    /// The composer and the share sheet: each caption, field, line and the
    /// body kept as a step, run again at the change with the files' rows
    /// made again and the addresses offered at their height; no line of
    /// either held at 44 whatever the size, and a line of bubbles in To
    /// growing with its names.
    func testTheComposerAndTheShareSheetFollowTheSize() throws {
        for (file, offered) in [("UI/ComposeViewController.swift",
                                 "if let field = activeAddressField { layoutSuggestions(under: field) }"),
                                ("Share/ShareViewController.swift",
                                 "if let field = activeAddressField { place(under: field) }")] {
            let code = try source(file)
            XCTAssertNotNil(place(of: "private let restyles = Restyles()", in: code), file)
            XCTAssertNotNil(place(of: "selector: #selector(textSizeChanged), name: TextSizes.didChange, "
                                      + "object: nil)", in: code), file)
            let change = try section(code, from: "@objc private func textSizeChanged() {", to: "}")
            XCTAssertTrue(change.hasPrefix(" restyles.again() rebuildAttachments() suggestionsView.rowHeight = "),
                          file)
            XCTAssertTrue(code.contains("suggestionsView.reloadData() " + offered + " view.setNeedsLayout() }"),
                          file)
            XCTAssertTrue(code.contains("restyles.keep { [bodyView] in bodyView.font = "
                                        + ".systemFont(ofSize: Theme.scaled(17)) }"), file)
            XCTAssertEqual(count("restyles.keep {", in: code), 5,
                           "the toggle, the body, Subject, To/Cc/Bcc, and the composer's buttons for "
                           + "files or the share sheet's note: \(file)")
            XCTAssertEqual(count("label.font = Theme.fontDetailMeta field.font = "
                                 + ".systemFont(ofSize: Theme.scaled(17))", in: code), 2, file)
            XCTAssertFalse(code.contains("equalToConstant: Theme.minHitTarget)"), file)
            XCTAssertFalse(code.contains("equalToConstant: 72)"), file)
            XCTAssertFalse(code.contains("Theme.minHitTarget / 2"), file)
        }
        let field = try source("UI/RecipientField.swift")
        for wiring in ["private lazy var height = heightAnchor.constraint(equalToConstant: Theme.lineHeight)",
                       "let line = Theme.lineHeight let tall = Theme.scaled(Theme.recipientBubbleHeight)",
                       "look.background.cornerRadius = Theme.scaled(Theme.recipientBubbleHeight) / 2",
                       "var font: UIFont = .systemFont(ofSize: Theme.scaled(17)) { didSet { "
                        + "input.font = font rebuild() } }"] {
            XCTAssertNotNil(place(of: wiring, in: field))
        }
    }
}
