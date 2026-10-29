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
        XCTAssertNotNil(place(of: "init(_ category: UIContentSizeCategory) { "
                                  + "self = .drawn(at: Step(category), bold: UIAccessibility.isBoldTextEnabled) }",
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

    // MARK: - Held at Large (Changed 2026-10-27)

    /// Every screen is drawn at Large whatever the iPad's text size, UIKit's
    /// own parts too: the size read is Large (`TextSize.drawn`, run in
    /// `TextSizeTests`), and a trait of Large is put on the three panes
    /// (`SteadyChromeTests`), on every sheet of the app's as it is made,
    /// through its presentation, so with all pushed on it, Settings' pages
    /// among them, and on the share sheet's form. Every sheet of the app's
    /// is made by the one maker, and nothing else reads the text size.
    /// Everything put up is known, file by file: the app's sheets, by the
    /// maker; its questions and action sheets, and the Share sheet, each
    /// held as it is put up (`testEveryQuestionAndActionSheetIsHeldAtLarge`);
    /// and iOS's own controllers, Quick Look, the photo and document
    /// pickers and the print panel. No presentation style is set anywhere
    /// but in the maker and on Quick Look, so no sheet is put up as a page
    /// sheet, or has its style changed after the maker, which would make a
    /// new presentation without the trait.
    func testEveryScreenIsHeldAtLarge() throws {
        let reading = try source("Theme/TextSizeReading.swift")
        XCTAssertNotNil(place(of: "static let heldTextSize = "
                                  + "UITraitCollection(preferredContentSizeCategory: .large)", in: reading))
        XCTAssertNotNil(place(of: "static func formSheet(_ root: UIViewController) -> UINavigationController { "
                                  + "let nav = UINavigationController(rootViewController: root) "
                                  + "nav.modalPresentationStyle = .formSheet "
                                  + "nav.presentationController?.overrideTraitCollection = .heldTextSize "
                                  + "return nav }", in: reading))

        let share = try source("Share/ShareViewController.swift")
        XCTAssertNotNil(place(of: "addChild(nav) setOverrideTraitCollection(.heldTextSize, forChild: nav) "
                                  + "nav.view.frame = view.bounds", in: share))

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail")
        let files = try XCTUnwrap(FileManager.default.enumerator(atPath: root.path))
            .compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }
        XCTAssertGreaterThan(files.count, 50)
        // What each file puts up, in the order it is written: `nav`, a
        // sheet of the maker's; an alert controller (`alert`, `ask`, `menu`,
        // `confirm`, and `sheet` but in the connection log, where it is the
        // Share sheet); `picker`, the photo picker or the document picker;
        // `preview`, Quick Look; `share`, the Share sheet; `from: anchor`,
        // the print panel.
        let presented: [String: [String]] = [
            "App/AppDelegate.swift": ["nav"],
            "Share/ShareViewController.swift": ["confirm"],
            "UI/ComposeViewController.swift": ["picker", "picker", "sheet"],
            "UI/DiagnosticsViewController.swift": ["sheet", "nav"],
            "UI/DiscardConfirmation.swift": ["sheet", "sheet"],
            "UI/EraseConfirmation.swift": ["alert"],
            "UI/ErrorPresenter.swift": ["alert", "alert"],
            "UI/LetterPrint.swift": ["from: anchor"],
            "UI/MessageDetailViewController.swift": [
                "UIDocumentPickerViewController(forExporting: [url], asCopy: true)", "share",
                "preview", "sheet", "nav", "sheet", "nav", "sheet", "sheet", "nav"],
            "UI/MessageListViewController.swift": ["nav", "sheet", "nav", "nav", "sheet", "nav", "nav", "nav"],
            "UI/RecipientField.swift": ["menu"],
            "UI/SettingsViewController.swift": ["ask", "alert"],
        ]
        let presenting = try NSRegularExpression(
            pattern: #"(?<![A-Za-z0-9_])present\(([^,()]+(?:\([^()]*\))?), animated:"#)
        var sheets = 0
        for file in files {
            let code = try source(file)
            let made = count("UINavigationController.formSheet(", in: code)
            sheets += made
            let found = presenting.matches(in: code, range: NSRange(code.startIndex..., in: code))
                .map { String(code[Range($0.range(at: 1), in: code)!]) }
            XCTAssertEqual(found, presented[file] ?? [], file)
            XCTAssertEqual(found.filter { $0 == "nav" }.count, made, "every sheet put up is the maker's, \(file)")
            switch file {
            case "Theme/TextSizeReading.swift":
                XCTAssertEqual(count("modalPresentationStyle", in: code), 1, file)
            case "UI/MessageDetailViewController.swift":
                // One Quick Look for a tap, the held menu and Markup and
                // Reply (B-176).
                XCTAssertEqual(count("modalPresentationStyle", in: code), 1, file)
                XCTAssertEqual(count("let preview = QLPreviewController() preview.dataSource = self", in: code), 1, file)
                XCTAssertEqual(count("preview.modalPresentationStyle = .fullScreen", in: code), 1, file)
            default:
                XCTAssertFalse(code.contains("modalPresentationStyle"), file)
            }
            switch file {
            case "Theme/TextSizeReading.swift":
                XCTAssertEqual(count(".formSheet", in: code), 1, file)
            case "UI/RootViewController.swift":
                XCTAssertEqual(count("UINavigationController(rootViewController:", in: code), 3, file)
            case "App/AppDelegate.swift":
                // The setup form, the window's own first screen, not a sheet.
                XCTAssertEqual(count("UINavigationController(rootViewController: setup)", in: code), 1, file)
                XCTAssertEqual(count("UINavigationController(rootViewController:", in: code), 1, file)
            default:
                XCTAssertFalse(code.contains("UINavigationController(rootViewController:"), file)
                XCTAssertFalse(code.contains("modalPresentationStyle = .formSheet"), file)
            }
            // The app's own answer, Large (`testTheAppsOwnSizeIsLargeAtItsRoot`).
            if !["Theme/TextSizeReading.swift", "Share/ShareViewController.swift",
                 "App/BlackmailApplication.swift"].contains(file) {
                XCTAssertFalse(code.contains("preferredContentSizeCategory"), file)
            }
        }
        XCTAssertEqual(sheets, 11, "the composer five times, Settings, Move three times, "
                                   + "Go to Date and the connection log")
        XCTAssertEqual(Set(presented.keys).subtracting(files), [], "every file listed is there")
    }

    /// The app's window, and the share sheet's, are limited to Large, the
    /// least and the most, so that what the traits on the panes and the
    /// sheets do not reach keeps its layout too: the setup form, which is
    /// the window's own first screen with no parent to hold it. The app's
    /// set before its first screen is made; the share sheet's as it
    /// appears, where its window is first there, beside the dark style
    /// that reaches its Cancel question. The one other limit is each
    /// question's own (`heldAtLarge`), at Large too. Nothing else sets a
    /// limit that could let a part of a screen grow.
    func testTheWindowsAreHeldAtLarge() throws {
        let app = try source("App/AppDelegate.swift")
        let made = try XCTUnwrap(place(of: "let window = UIWindow(frame: UIScreen.main.bounds)", in: app))
        let held = try XCTUnwrap(place(of: "window.minimumContentSizeCategory = .large "
                                           + "window.maximumContentSizeCategory = .large", in: app))
        let first = try XCTUnwrap(place(of: "window.rootViewController = Self.makeRoot()", in: app))
        XCTAssertLessThan(made, held)
        XCTAssertLessThan(held, first, "before the first screen is made")

        let share = try source("Share/ShareViewController.swift")
        XCTAssertNotNil(place(of: "public override func viewWillAppear(_ animated: Bool) { "
                                  + "super.viewWillAppear(animated) "
                                  + "view.window?.overrideUserInterfaceStyle = .dark "
                                  + "view.window?.minimumContentSizeCategory = .large "
                                  + "view.window?.maximumContentSizeCategory = .large ", in: share))

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail")
        let files = try XCTUnwrap(FileManager.default.enumerator(atPath: root.path))
            .compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }
        for file in files {
            let code = try source(file)
            let limits = count("minimumContentSizeCategory", in: code) + count("maximumContentSizeCategory", in: code)
            switch file {
            case "App/AppDelegate.swift", "Share/ShareViewController.swift", "Theme/TextSizeReading.swift":
                XCTAssertEqual(limits, 2, file)
            default:
                XCTAssertEqual(limits, 0, file)
            }
        }
    }

    /// Every question, action sheet and Share sheet the app puts up is
    /// held at Large on its own (B-166, found on the test iPad 2026-10-28):
    /// on 16.5.1 the window's limits did not reach the bubble menu, the
    /// Reply sheet, the Flag popover or Add Another Email, which grew at the
    /// larger sizes. The one helper puts the trait of Large on the
    /// presentation, keeping any trait already there, and limits the
    /// controller's own view to Large. Every `UIAlertController` and
    /// `UIActivityViewController` made anywhere in the sources, those there
    /// now and any made later, is made as `let NAME = …(` and held,
    /// `NAME.heldAtLarge()`, as the last thing before it is presented or
    /// handed back by its maker: one made and not held fails here. Neither
    /// type is named in any other way but as a weak var's type or a
    /// maker's return type, so one made by `.init(`, through a subclass or
    /// under another name fails here too.
    func testEveryQuestionAndActionSheetIsHeldAtLarge() throws {
        let reading = try source("Theme/TextSizeReading.swift")
        XCTAssertNotNil(place(of: "extension UIViewController { "
                                  + "@discardableResult func heldAtLarge() -> Self { "
                                  + "if let presentation = presentationController { "
                                  + "presentation.overrideTraitCollection = UITraitCollection( "
                                  + "traitsFrom: [presentation.overrideTraitCollection, .heldTextSize]"
                                  + ".compactMap { $0 }) } "
                                  + "view.minimumContentSizeCategory = .large "
                                  + "view.maximumContentSizeCategory = .large "
                                  + "return self } }", in: reading))

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail")
        let files = try XCTUnwrap(FileManager.default.enumerator(atPath: root.path))
            .compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }
        XCTAssertGreaterThan(files.count, 50)
        // Every time either type is named, in a file's code: made, as a
        // weak var's type, or as a maker's return type, and in no other
        // way, so that none is made by `.init(`, by `= .init(` after the
        // type, by a subclass or under another name, out of this test's
        // sight.
        let either = "(?:UIAlertController|UIActivityViewController)"
        let named = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])\#(either)(?![A-Za-z0-9_])"#)
        let made = try NSRegularExpression(pattern: #"let ([A-Za-z_][A-Za-z0-9_]*) = \#(either)\("#)
        let kept = try NSRegularExpression(pattern: #"weak var [A-Za-z_][A-Za-z0-9_]*: \#(either)\?"#)
        let handed = try NSRegularExpression(pattern: #"\) -> \#(either) \{"#)
        var sites: [String] = []
        for file in files {
            let code = try source(file)
            let whole = NSRange(code.startIndex..., in: code)
            let lets = made.matches(in: code, range: whole)
            XCTAssertEqual(named.numberOfMatches(in: code, range: whole),
                           lets.count + kept.numberOfMatches(in: code, range: whole)
                               + handed.numberOfMatches(in: code, range: whole),
                           "each made as let NAME = …(, or named as a weak var's or a maker's type, \(file)")
            for found in lets {
                let name = String(code[Range(found.range(at: 1), in: code)!])
                let rest = String(code[Range(found.range, in: code)!.upperBound...])
                let leaves = try NSRegularExpression(
                    pattern: "(?<![A-Za-z0-9_])(?:present\\(\(name), animated:|return \(name)(?![A-Za-z0-9_]))")
                let gone = try XCTUnwrap(leaves.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
                                         "\(file): \(name) is presented or handed back")
                let before = String(rest[..<Range(gone.range, in: rest)!.lowerBound])
                let held = try NSRegularExpression(pattern: "(?<![A-Za-z0-9_])\(name)\\.heldAtLarge\\(\\) (?:[a-z]+\\.)?$")
                XCTAssertEqual(held.numberOfMatches(in: before, range: NSRange(before.startIndex..., in: before)), 1,
                               "\(file): \(name) held just before it is put up or handed back")
                sites.append(file)
            }
        }
        XCTAssertEqual(sites.count, 17, "fifteen questions and action sheets, and two Share sheets: \(sites.sorted())")
        // Their words, which on 16.5.1 grew under the trait and the limits
        // (round r6-k-fix, 2026-10-28), believed to follow the app's own
        // size, not shown: the app is its own principal class, which
        // answers Large for that size (`testTheAppsOwnSizeIsLargeAtItsRoot`).
        XCTAssertNotNil(place(of: Self.principalClassWired, in: try entryPoint("BlackmailApp")))
    }

    /// The app's executable, `main.swift` of `target`, as `source` reads a
    /// file of the library.
    private func entryPoint(_ target: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/\(target)/main.swift")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    private static let principalClassWired = "UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, "
        + "NSStringFromClass(BlackmailApplication.self), NSStringFromClass(AppDelegate.self))"

    /// The app's own text size is Large at its root (B-166, found on the
    /// test iPad 2026-10-28, the second round): on 16.5.1 a question's,
    /// an action sheet's and the bubble menu's frames kept Large under
    /// `heldAtLarge` and their words grew, an alert's labels believed to
    /// follow the app's `preferredContentSizeCategory`, not shown (the
    /// host has no UIKit to run). The app is launched as
    /// its own subclass of `UIApplication`, named in `main.swift`, whose
    /// one override answers Large, the step the app is drawn at whatever
    /// the iPad's (`TextSize.drawn`). The share extension, a process of its
    /// own whose application UIKit makes, names none. Nothing else subclasses
    /// `UIApplication`; the app's size is read in one place,
    /// `TextSizes.app`, which hears iOS's word of a change; and the one
    /// other reader of a change of size, by its traits, is the share
    /// sheet's, which the extension keeps.
    func testTheAppsOwnSizeIsLargeAtItsRoot() throws {
        let application = try source("App/BlackmailApplication.swift")
        XCTAssertNotNil(place(of: "public final class BlackmailApplication: UIApplication { "
                                  + "public override var preferredContentSizeCategory: "
                                  + "UIContentSizeCategory { .large } }", in: application))
        let main = try entryPoint("BlackmailApp")
        XCTAssertNotNil(place(of: Self.principalClassWired, in: main))
        XCTAssertEqual(count("UIApplicationMain(", in: main), 1)
        let share = try entryPoint("BlackmailShare")
        XCTAssertFalse(share.contains("BlackmailApplication"))
        XCTAssertFalse(share.contains("UIApplicationMain"))
        // Large is the step the app is drawn at, at every size iOS has.
        for step in TextSize.Step.allCases {
            XCTAssertEqual(TextSize.drawn(at: step, bold: false).step, .large, "\(step)")
            XCTAssertEqual(TextSize.drawn(at: step, bold: true), TextSize(step: .large, bold: true), "\(step)")
        }

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail")
        let files = try XCTUnwrap(FileManager.default.enumerator(atPath: root.path))
            .compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }
        XCTAssertGreaterThan(files.count, 50)
        let subclass = try NSRegularExpression(pattern: #"class\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*UIApplication\s*[,{]"#)
        for file in files {
            let code = try source(file)
            let whole = NSRange(code.startIndex..., in: code)
            XCTAssertEqual(subclass.numberOfMatches(in: code, range: whole),
                           file == "App/BlackmailApplication.swift" ? 1 : 0, file)
            XCTAssertEqual(count("preferredContentSizeCategory", in: code), [
                "App/BlackmailApplication.swift": 1,
                "Theme/TextSizeReading.swift": 2,
                "Share/ShareViewController.swift": 3,
            ][file] ?? 0, file)
            XCTAssertEqual(count("UIApplication.shared.preferredContentSizeCategory", in: code),
                           file == "Theme/TextSizeReading.swift" ? 1 : 0, file)
            XCTAssertEqual(count("UIContentSizeCategory.didChangeNotification", in: code),
                           ["Theme/TextSizeReading.swift", "Share/ShareViewController.swift"].contains(file) ? 1 : 0,
                           file)
            XCTAssertEqual(count("traitCollectionDidChange", in: code),
                           file == "Share/ShareViewController.swift" ? 2 : 0, file)
        }
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
    /// a regroup, which holds his place, at the change: the place taken
    /// before the height is set, while the rows are at the old one, and
    /// handed to the regroup, which takes its own only when given none.
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
        XCTAssertNotNil(place(of: "@objc private func textSizeChanged() { let here = place() "
                                  + "tableView.rowHeight = Theme.messageRowHeightScaled "
                                  + "emptyLabel.font = Theme.fontListSubject searchBar.restyle() "
                                  + "regroup(from: here) }",
                              in: list))
        XCTAssertNotNil(place(of: "private func regroup(highlighting opened: String? = nil, "
                                  + "to move: ListPlaces.Move = .stay, from held: ListPlace? = nil) { "
                                  + "let before = held ?? place()", in: list))
        let band = try source("UI/SearchHeaderView.swift")
        XCTAssertNotNil(place(of: "func restyle() { recentHeading.font = Theme.fontListSender "
                                  + "for row in recentRows { row.restyle() } setNeedsLayout() }", in: band))
    }

    /// The Mailboxes: the rows at their height and drawn again, the
    /// highlight put back, at the change; their names, counts and icons
    /// read from `Theme` as each row is drawn. At Large the rows are the
    /// 44 they were; at any other size each is as tall as its name, never
    /// under the rows' height there, in the Mailboxes and the Move sheet
    /// alike, and measured again when a count comes or goes in place.
    func testTheMailboxesFollowTheSize() throws {
        let folders = try source("UI/MailboxListViewController.swift")
        XCTAssertNotNil(place(of: "NotificationCenter.default.addObserver(self, selector: #selector(textSizeChanged), "
                                  + "name: TextSizes.didChange, object: nil)", in: folders))
        XCTAssertNotNil(place(of: "@objc private func textSizeChanged() { "
                                  + "FolderCell.size(tableView) redraw() }", in: folders))
        let configure = try section(folders, from: "private func configure(_ cell: UITableViewCell, "
                                        + "with mailbox: Mailbox) {", to: "cell.accessibilityLabel")
        for wiring in ["content.textProperties.font = Theme.fontMailboxName",
                       "content.image = Theme.symbol(icon(for: mailbox.role))",
                       "label.font = Theme.fontMailboxCount",
                       "cell.contentConfiguration = content (cell as? FolderCell)?.holdFloor()"] {
            XCTAssertTrue(configure.contains(wiring), wiring)
        }
        let adjust = try section(folders, from: "func adjustUnreadCounts(", to: "AppBadge.app.counted")
        XCTAssertTrue(adjust.contains("configure(cell, with: folder) patched = true }"), adjust)
        XCTAssertTrue(adjust.contains("if patched, Theme.textSize.step != .large { "
                                      + "tableView.beginUpdates() tableView.endUpdates() }"), adjust)

        let move = try source("UI/MoveMessageViewController.swift")
        XCTAssertNotNil(place(of: "cell.contentConfiguration = content (cell as? FolderCell)?.holdFloor() "
                                  + "return cell", in: move))
        for (file, code) in [("folders", folders), ("move", move)] {
            XCTAssertNotNil(place(of: "tableView.register(FolderCell.self, forCellReuseIdentifier: \"Mailbox\") "
                                      + "FolderCell.size(tableView)", in: code), file)
            XCTAssertFalse(code.contains("rowHeight = Theme.mailboxRowHeightScaled"), file)
        }

        let cell = try source("UI/FolderCell.swift")
        XCTAssertNotNil(place(of: "static func size(_ table: UITableView) { "
                                  + "if Theme.textSize.step == .large { "
                                  + "table.rowHeight = Theme.mailboxRowHeightScaled "
                                  + "table.estimatedRowHeight = UITableView.automaticDimension } else { "
                                  + "table.rowHeight = UITableView.automaticDimension "
                                  + "table.estimatedRowHeight = Theme.mailboxRowHeightScaled } }", in: cell))
        XCTAssertNotNil(place(of: "let floor = contentView.heightAnchor.constraint("
                                  + "greaterThanOrEqualToConstant: 0) floor.priority = UILayoutPriority(999)",
                              in: cell))
        XCTAssertNotNil(place(of: "func holdFloor() { floor.constant = Theme.mailboxRowHeightScaled "
                                  + "floor.isActive = Theme.textSize.step != .large }", in: cell))
        XCTAssertFalse(cell.contains("numberOfLines"), "the name on as many lines as it takes")
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
                       "let style = pageStyle, held = remote.waits(m.id) loads.start({ m }, prepare: { m in "
                        + "(m, PanePage.letter(m, style: style, heldBack: held)) }, settle: { [weak self] "
                        + "result in guard let self, case .success(let (m, page)) = result, "
                        + "self.message?.id == m.id else { return } self.draw(m, page: page) })",
                       "+ drawn.filter { $0.id == stackFocus.letter }, inStack: true)",
                       "renderConversation(entries) for (id, body) in again.bodies { fill(id, body) }",
                       "case .notice(let lines): renderNotice(lines)"] {
            XCTAssertTrue(owed.contains(wiring), wiring)
        }
        XCTAssertNotNil(place(of: "super.viewDidAppear(animated) drawAgain() restyleIfOwed() }", in: pane))
        XCTAssertNotNil(place(of: "@objc private func appBecameActive() { drawAgain() restyleIfOwed() }", in: pane))
        XCTAssertNotNil(place(of: ".init(inset: Int(Theme.detailContentInsetLeft), "
                                  + "bodyPointSize: Int(Theme.scaled(17)),", in: pane))
        XCTAssertNotNil(place(of: "load(ConversationDocument.html(entries: entries, inset: style.inset, "
                                  + "bodyPointSize: style.bodyPointSize, lineHeight: style.lineHeight, "
                                  + "stacked: Theme.textSize.stacksRowDate, smartInvert: style.smartInvert, "
                                  + "colourFilter: style.colourFilter), "
                                  + "as: .conversation(entries))",
                              in: pane))
        XCTAssertEqual(count("ConversationDocument.html(", in: pane), 1, "the stack is built in one place")

        let header = try source("UI/MessageHeaderView.swift")
        XCTAssertNotNil(place(of: "func restyle() { senderLabel.font = Theme.fontDetailSender "
                                  + "toLabel.font = Theme.fontDetailMeta ccLabel.font = Theme.fontDetailMeta "
                                  + "subjectLabel.font = Theme.fontDetailSubject "
                                  + "dateLabel.font = Theme.fontDetailMeta "
                                  + "setNeedsLayout() }", in: header))
        // A file's row went with B-170: its tile in the body is at the
        // pane's scale by the page's head (`BodyFiles.sizeRule`; int19).
        XCTAssertFalse(header.contains("attachmentButtons"))
    }

    /// The composer and the share sheet: each caption, field, line and the
    /// body kept as a step, run again at the change with the files' rows
    /// made again and the addresses offered at their height; no line of
    /// either held at 44 whatever the size, and a line of bubbles in To
    /// growing with its names. Each step sets its line's height, and its
    /// caption's room and place, again, not its type alone: a step that
    /// set only the fonts would leave an open composer's lines at their
    /// old height, its words cut, until it was opened again.
    func testTheComposerAndTheShareSheetFollowTheSize() throws {
        let steps = [
            "restyles.keep { [ccToggle] in ccToggle.titleLabel?.font = Theme.fontDetailMeta "
                + "toggleHeight.constant = Theme.lineHeight }",
            "label.font = Theme.fontDetailMeta field.font = .systemFont(ofSize: Theme.scaled(17)) "
                + "captionWidth.constant = Theme.scaled(72) height.constant = Theme.lineHeight }",
            "label.font = Theme.fontDetailMeta field.font = .systemFont(ofSize: Theme.scaled(17)) "
                + "captionY.constant = Theme.lineHeight / 2 captionWidth.constant = Theme.scaled(72) }",
        ]
        for file in ["UI/ComposeViewController.swift", "Share/ShareViewController.swift"] {
            let code = try source(file)
            for step in steps { XCTAssertEqual(count(step, in: code), 1, "\(file): \(step)") }
        }
        XCTAssertNotNil(place(of: "button.configuration?.attributedTitle?.font = Theme.fontDetailMeta } "
                                  + "height.constant = Theme.lineHeight }",
                              in: try source("UI/ComposeViewController.swift")))
        XCTAssertNotNil(place(of: "restyles.keep { label.font = Theme.fontDetailMeta "
                                  + "height.constant = Theme.lineHeight }",
                              in: try source("Share/ShareViewController.swift")))
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
