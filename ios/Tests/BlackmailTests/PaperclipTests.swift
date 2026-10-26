import XCTest
@testable import Blackmail

/// Mail's paperclip at the right of the keyboard's shortcut bar while he
/// types in the letter (B-154): a menu of Attach File and Photo Library,
/// opening the pickers the two buttons under the files open, which stay.
/// Its words are run here; the bar is UIKit's, so its wiring is read from
/// the source, comment lines out and runs of white space as one space, as
/// `ComposerFilesWiringTests` reads the composer.
final class PaperclipTests: XCTestCase {

    private var ios: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: ios.appendingPathComponent(path), encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    private static let composer = "Sources/Blackmail/UI/ComposeViewController.swift"

    private func count(_ text: String, in code: String) -> Int {
        code.components(separatedBy: text).count - 1
    }

    private func inOrder(_ steps: [String], in code: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        var from = code.startIndex
        for step in steps {
            guard let found = code.range(of: step, range: from..<code.endIndex) else {
                return XCTFail("missing, or out of order: \(step)", file: file, line: line)
            }
            from = found.upperBound
        }
    }

    /// The menu: Attach File, then Photo Library, in Mail's words, each
    /// with the symbol of its button under the files; nothing for the
    /// camera. The paperclip's own symbol and Mail's name for it.
    func testTheMenuIsAttachFileThenPhotoLibraryInMailsWords() {
        XCTAssertEqual(ComposeForm.Attach.paperclip, [.attachFile, .photoLibrary])
        XCTAssertEqual(ComposeForm.Attach.paperclip.map(\.words), ["Attach File", "Photo Library"])
        XCTAssertEqual(ComposeForm.Attach.paperclip.map(\.symbol), ["doc", "photo.on.rectangle"])
        XCTAssertEqual(Set(ComposeForm.Attach.paperclip), Set(ComposeForm.Attach.allCases),
                       "every way in, once")
        XCTAssertEqual(ComposeForm.Attach.paperclipSymbol, "paperclip")
        XCTAssertEqual(ComposeForm.Attach.paperclipName, "Insert Attachment Actions")
    }

    /// In the body's own shortcut bar, after what the system puts at its
    /// right, made as the sheet loads, before the body can take the caret
    /// (`readyToType`, as the sheet appears):
    /// one bar button, a paperclip whose menu opens at a tap, of the two
    /// choices in order, each opening the picker its button opens.
    func testThePaperclipIsInTheBodysShortcutBarWithTheMenu() throws {
        let code = try source(Self.composer)
        inOrder(["override func viewDidLoad() {",
                 "bodyView.delegate = self",
                 "scroller.addSubview(bodyView)",
                 "paperclipInTheShortcutBar()",
                 "configureSuggestions()",
                 "private func currentLetter() -> Draft {"], in: code)
        inOrder(["private func paperclipInTheShortcutBar() {",
                 "let menu = UIMenu(children: ComposeForm.Attach.paperclip.map { choice in",
                 "UIAction(title: choice.words, image: UIImage(systemName: choice.symbol)) { [weak self] _ in",
                 "switch choice {",
                 "case .attachFile: self?.attachFileTapped()",
                 "case .photoLibrary: self?.photoLibraryTapped()",
                 "let paperclip = UIBarButtonItem(image: UIImage(systemName: ComposeForm.Attach.paperclipSymbol), "
                    + "menu: menu)",
                 "paperclip.accessibilityLabel = ComposeForm.Attach.paperclipName",
                 "paperclipItem = paperclip",
                 "let bar = bodyView.inputAssistantItem",
                 "bar.trailingBarButtonGroups = bar.trailingBarButtonGroups "
                    + "+ [UIBarButtonItemGroup(barButtonItems: [paperclip], representativeItem: nil)]",
                 "@objc private func photoLibraryTapped() {"], in: code)
        XCTAssertEqual(count("paperclipInTheShortcutBar()", in: code), 2, "made once, and called once")
        XCTAssertEqual(count("inputAssistantItem", in: code), 1, "the body's bar alone")
        XCTAssertEqual(count("leadingBarButtonGroups", in: code), 0, "Undo, Redo and Paste as they are")
        XCTAssertEqual(count("trailingBarButtonGroups =", in: code), 1)
        XCTAssertFalse(code.contains("paperclip.primaryAction"), "the menu opens at a tap")
        XCTAssertFalse(code.contains("paperclip.target"), "the menu opens at a tap")
    }

    /// The two buttons under the files stay, and the paperclip is held with
    /// them while a letter goes.
    func testTheButtonsStayAndThePaperclipIsHeldWithThem() throws {
        let code = try source(Self.composer)
        XCTAssertTrue(code.contains("stack.addArrangedSubview(attachRow())"))
        inOrder(["let photos = attachButton(.photoLibrary, action: #selector(photoLibraryTapped))",
                 "let files = attachButton(.attachFile, action: #selector(attachFileTapped))"], in: code)
        inOrder(["private func draw(_ look: ComposeActions.Look) {",
                 "photoButton?.isEnabled = !sending",
                 "fileButton?.isEnabled = !sending",
                 "paperclipItem?.isEnabled = !sending"], in: code)
    }

    /// Never over Send: Send and what stands in its place while a letter
    /// goes are the sheet's bar at the top, and the paperclip is not in it.
    func testThePaperclipIsNeverWhereSendIs() throws {
        let code = try source(Self.composer)
        XCTAssertEqual(count("navigationItem.rightBarButtonItem = sendItem", in: code), 1)
        XCTAssertEqual(count("navigationItem.rightBarButtonItems = [sendItem]", in: code), 1)
        XCTAssertEqual(count("navigationItem.rightBarButtonItems = [sendingWordsItem, sendingSpinnerItem]",
                             in: code), 1)
        XCTAssertEqual(count("navigationItem.rightBarButtonItems =", in: code), 2)
        XCTAssertEqual(count("navigationItem.leftBarButtonItem =", in: code), 1)
        XCTAssertFalse(code.contains("navigationItem.rightBarButtonItems?.append"))
        XCTAssertEqual(count("paperclipItem", in: code), 3, "held, set and drawn, nowhere else")
    }

    /// Not in the share sheet (B-108): no shortcut bar of its own there,
    /// and no other source touches one.
    func testTheShareSheetHasNoPaperclip() throws {
        let walk = FileManager.default.enumerator(at: ios.appendingPathComponent("Sources"),
                                                  includingPropertiesForKeys: nil)
        var read = 0
        var inBars: [String] = []
        while let url = walk?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            read += 1
            let file = try String(contentsOf: url, encoding: .utf8)
            if file.contains("inputAssistantItem") { inBars.append(url.lastPathComponent) }
            if url.path.contains("/Share/") {
                XCTAssertFalse(file.contains("ComposeForm.Attach"), url.lastPathComponent)
                XCTAssertFalse(file.contains("BarButtonGroups"), url.lastPathComponent)
            }
        }
        XCTAssertGreaterThan(read, 100)
        XCTAssertEqual(inBars, ["ComposeViewController.swift"])
    }
}
