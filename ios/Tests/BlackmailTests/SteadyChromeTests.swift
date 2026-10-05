import XCTest
@testable import Blackmail

/// What the iPadOS 18 pass found the main screens doing that Mail does not
/// (B-071): highlights lost under a file's preview, symbols that grew and
/// shrank with the iPad's text size, controls in Settings and the search
/// field with no name for VoiceOver, and "Passwords" offered over the
/// signature.
///
/// All of it is UIKit, which never builds on this host, so the wiring is
/// read from the source, as `PaneNavigationTests` reads the reading pane's:
/// comment lines out, and runs of white space as one space. What each
/// screen draws was seen on the iOS 18.6 simulator; see the entry.
final class SteadyChromeTests: XCTestCase {

    /// `path` is under `Sources/Blackmail`.
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

    /// Where `text` first is in `code`, failing if it is not there.
    private func place(of text: String, in code: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String.Index? {
        let found = code.range(of: text)?.lowerBound
        XCTAssertNotNil(found, text, file: file, line: line)
        return found
    }

    private func count(_ text: String, in code: String) -> Int {
        code.components(separatedBy: text).count - 1
    }

    // MARK: - The highlights

    /// Neither list lets UIKit clear its highlight when it comes back into
    /// view, as it does by default, and as it did when a file's preview,
    /// which covers the screen, closed. Said in the initializer, before the
    /// view first appears, and nothing else in either list clears a row on
    /// appearing.
    func testNeitherListClearsItsHighlightOnAppearing() throws {
        for (file, initializer) in [
            ("UI/MailboxListViewController.swift",
             "init(repository: MailRepository) { self.repository = repository super.init(style: .plain) "
                + "title = \"Mailboxes\""),
            ("UI/MessageListViewController.swift",
             "init(repository: MailRepository, mailbox: Mailbox) { self.repository = repository "
                + "self.mailbox = mailbox super.init(style: .plain) title = mailbox.displayName"),
        ] {
            let code = try source(file)
            guard let start = place(of: initializer, in: code),
                  let set = place(of: "clearsSelectionOnViewWillAppear = false", in: code) else { continue }
            XCTAssertLessThan(start, set, file)
            let rest = code[code.index(start, offsetBy: initializer.count)...]
            let end = try XCTUnwrap(rest.range(of: "required init?(coder: NSCoder)")?.lowerBound, file)
            XCTAssertLessThan(set, end, "\(file): set in the initializer")
            XCTAssertEqual(count("clearsSelectionOnViewWillAppear", in: code), 1, file)
            XCTAssertFalse(code.contains("viewWillAppear"), file)
        }
    }

    /// The preview that cleared them is the one that covers the whole
    /// screen. Were it a sheet, the lists would never appear again under it.
    func testTheFilesPreviewStillCoversTheScreen() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        XCTAssertNotNil(place(of: "let preview = QLPreviewController()", in: code))
        XCTAssertNotNil(place(of: "preview.modalPresentationStyle = .fullScreen", in: code))
    }

    // MARK: - Symbols at a fixed size

    /// One size for every symbol UIKit would size itself: 17 pt, the large
    /// scale, regular, which is what UIKit drew each at with the iPad's
    /// text size at its default, measured on the simulator. A point size,
    /// which no text size changes, and not a text style, which every text
    /// size does. It moves with `textScale` alone.
    func testTheSymbolSizeIsAPointSize() throws {
        let code = try source("Theme/Theme.swift")
        XCTAssertNotNil(place(of: "static var symbolSize: UIImage.SymbolConfiguration { "
                                  + "UIImage.SymbolConfiguration(pointSize: scaled(17), weight: .regular, "
                                  + "scale: .large) }", in: code))
        XCTAssertNotNil(place(of: "static func symbol(_ name: String) -> UIImage? { "
                                  + "UIImage(systemName: name, withConfiguration: symbolSize) }", in: code))
        XCTAssertFalse(code.contains("textStyle"))
    }

    /// The reading pane's five buttons and the calendar, the folders'
    /// icons, and a file's paperclip in a letter's header, each at
    /// `Theme.symbolSize`. The paperclip and the icons say so to their
    /// button and their row as well, which otherwise put a size of their
    /// own on the image.
    func testTheSymbolsUIKitSizedAreFixed() throws {
        let toolbar = try source("UI/MessageDetailViewController.swift")
        XCTAssertNotNil(place(of: "let item = UIBarButtonItem(image: Theme.symbol(name), style: .plain, "
                                  + "target: self, action: sel)", in: toolbar))
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertNotNil(place(of: "let jump = UIBarButtonItem(image: Theme.symbol(\"calendar\"), style: .plain,",
                              in: list))
        let header = try source("UI/MessageHeaderView.swift")
        XCTAssertNotNil(place(of: "config.image = Theme.symbol(\"paperclip\") "
                                  + "config.preferredSymbolConfigurationForImage = Theme.symbolSize", in: header))
        let folders = try source("UI/MailboxListViewController.swift")
        XCTAssertNotNil(place(of: "content.image = Theme.symbol(icon(for: mailbox.role)) "
                                  + "content.imageProperties.preferredSymbolConfiguration = Theme.symbolSize",
                              in: folders))
    }

    /// No symbol on the mail screens is left to UIKit to size. Each is made
    /// with a configuration of its own, or sits in an image view of a fixed
    /// size that scales it to fit: the row's paperclip and flag, and the
    /// search field's magnifier, which were seen not to change by a pixel
    /// at any text size. The composer and the share sheet are not read
    /// here; their paperclip is B-069's.
    func testNoSymbolOnTheMailScreensIsLeftToUIKit() throws {
        let fixedFrames = [
            "attachmentIcon.image = UIImage(systemName: \"paperclip\")",
            "flagIcon.image = UIImage(systemName: \"flag.fill\")",
            "let icon = UIImageView(image: UIImage(systemName: \"magnifyingglass\"))",
        ]
        for file in ["MailboxListViewController", "MessageListViewController", "MessageDetailViewController",
                     "MessageHeaderView", "MessageCell", "SearchHeaderView", "RootViewController",
                     "MoveMessageViewController", "JumpToDateViewController", "SettingsViewController",
                     "DiagnosticsViewController", "AccountSetupViewController", "EraseConfirmation",
                     "ErrorPresenter"] {
            let code = try source("UI/\(file).swift")
            var rest = code[...]
            while let at = rest.range(of: "UIImage(systemName:") {
                let call = String(code[at.lowerBound...].prefix(90))
                let sized = call.contains("withConfiguration:")
                let framed = fixedFrames.contains { fixed in
                    code.range(of: fixed).map { $0.contains(at.lowerBound) } ?? false
                }
                XCTAssertTrue(sized || framed, "\(file): \(call)")
                rest = code[at.upperBound...]
            }
            XCTAssertFalse(code.contains("UIBarButtonItem(image: UIImage("), file)
        }
        let cell = try source("UI/MessageCell.swift")
        XCTAssertNotNil(place(of: "attachmentIcon.contentMode = .scaleAspectFit", in: cell))
        XCTAssertNotNil(place(of: "flagIcon.contentMode = .scaleAspectFit", in: cell))
        let search = try source("UI/SearchHeaderView.swift")
        XCTAssertNotNil(place(of: "icon.widthAnchor.constraint(equalToConstant: 15), "
                                  + "icon.heightAnchor.constraint(equalToConstant: 15),", in: search))
    }

    /// The folders and the list are laid out as at the default text size,
    /// whatever the iPad's is: at the accessibility sizes UIKit lays a
    /// folder's icon out in a way of its own, which a fixed symbol and room
    /// did not hold, and Edit mode's circles take no size at all. Said by
    /// the container once its panes are its children, for those two panes
    /// and not the reading pane, whose symbols have a size of their own.
    func testTheFoldersAndTheListAreLaidOutAtTheDefaultTextSize() throws {
        let code = try source("UI/RootViewController.swift")
        let children = try XCTUnwrap(place(of: "for child in [mailboxNav, listNav, detailNav] { addChild(child) "
                                               + "child.view.translatesAutoresizingMaskIntoConstraints = false "
                                               + "view.addSubview(child.view) child.didMove(toParent: self) }",
                                           in: code))
        let held = try XCTUnwrap(place(of: "for nav in [mailboxNav, listNav] { setOverrideTraitCollection("
                                           + "UITraitCollection(preferredContentSizeCategory: .large), "
                                           + "forChild: nav) }",
                                       in: code))
        XCTAssertLessThan(children, held)
        XCTAssertEqual(count("setOverrideTraitCollection", in: code), 1)
        XCTAssertEqual(count("preferredContentSizeCategory", in: code), 1)
    }

    // MARK: - Names for VoiceOver

    /// Each control in Settings is called by its caption, the words over or
    /// beside it, and the captions over the fields read as they did. The
    /// words beside the switch are not read: the switch is called by them,
    /// and the row is one stop, as Mail's is.
    func testEachControlInSettingsIsCalledByItsCaption() throws {
        let code = try source("UI/SettingsViewController.swift")
        for wiring in [
            "let nameCaption = \"Your name, as recipients will see it\" "
                + "stack.addArrangedSubview(caption(nameCaption))",
            "nameField.accessibilityLabel = nameCaption",
            "let signatureCaption = \"Signature — added to the bottom of everything you send\" "
                + "stack.addArrangedSubview(caption(signatureCaption)) "
                + "signatureView.accessibilityLabel = signatureCaption",
            "let passwordCaption = \"New app password — leave blank to keep the one you have\" "
                + "stack.addArrangedSubview(caption(passwordCaption))",
            "passwordField.accessibilityLabel = passwordCaption",
            "private static let organizeTitle = \"Organize by Thread\"",
            "label.text = Self.organizeTitle label.isAccessibilityElement = false",
            "organizeSwitch.accessibilityLabel = Self.organizeTitle",
        ] {
            XCTAssertNotNil(place(of: wiring, in: code))
        }
    }

    /// The search field is called "Search", and is a search field, as
    /// Mail's is. The magnifier and the word drawn in it are not read as
    /// two more things called "Search".
    func testTheSearchFieldIsCalledSearch() throws {
        let code = try source("UI/SearchHeaderView.swift")
        XCTAssertNotNil(place(of: "private let field = SearchField()", in: code))
        XCTAssertNotNil(place(of: "field.accessibilityLabel = \"Search\"", in: code))
        XCTAssertNotNil(place(of: "private final class SearchField: UITextField { "
                                  + "override var accessibilityTraits: UIAccessibilityTraits { "
                                  + "get { super.accessibilityTraits.union(.searchField) } "
                                  + "set { super.accessibilityTraits = newValue } } }", in: code))
        let icon = try XCTUnwrap(place(of: "let icon = UIImageView(image: UIImage(systemName: \"magnifyingglass\"))",
                                       in: code))
        let unread = try XCTUnwrap(place(of: "icon.isAccessibilityElement = false "
                                             + "label.isAccessibilityElement = false", in: code))
        XCTAssertLessThan(icon, unread)
    }

    // MARK: - Passwords

    /// The app password is the form's one password, and a new one, so iOS
    /// offers no saved password over it or over the signature box before
    /// it. Only while it is masked: unmasked there is no passcode, and B-009
    /// is what a field iOS knows for a password brings. The name is a name.
    /// Nothing else on the form has a content type.
    func testOnlyTheMaskedAppPasswordIsAPassword() throws {
        let code = try source("UI/SettingsViewController.swift")
        let masked = try XCTUnwrap(place(of: "let masked = Self.deviceHasPasscode()", in: code))
        let typed = try XCTUnwrap(place(of: "if masked { passwordField.textContentType = .newPassword }",
                                        in: code))
        XCTAssertLessThan(masked, typed)
        XCTAssertNotNil(place(of: "nameField.textContentType = .name", in: code))
        XCTAssertEqual(count("textContentType", in: code), 2)
        XCTAssertFalse(code.contains(".password }"))
        XCTAssertFalse(code.contains(".username"))
    }
}
