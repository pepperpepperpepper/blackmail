import XCTest
@testable import Blackmail

/// The composer's Photo Library and Attach File (B-108), read from the
/// source: UIKit's side never builds on this host. Comment lines out, runs
/// of white space as one space, as `SentSoundTests` reads the sheets.
final class ComposerFilesWiringTests: XCTestCase {

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

    /// Photo Library: photos and videos, five at a time, as Photos keeps
    /// them, with no copy made (`.current`, B-142), through PHPicker,
    /// which asks no permission; each read by the share sheet's intake once
    /// the picker has been put away, a video made H.264 in the app
    /// (`videos: .h264`).
    func testPhotoLibraryOffersPhotosAndVideosFiveAtATimeAsPhotosKeepsThem() throws {
        let code = try source(Self.composer)
        inOrder(["@objc private func photoLibraryTapped() {",
                 "var config = PHPickerConfiguration()",
                 "config.filter = .any(of: [.images, .videos])",
                 "config.selectionLimit = 5",
                 "config.preferredAssetRepresentationMode = .current",
                 "let picker = PHPickerViewController(configuration: config)",
                 "picker.delegate = self",
                 "present(picker, animated: true)"], in: code)
        inOrder(["func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {",
                 "picker.dismiss(animated: true)",
                 "intake.take(results.map { result in",
                 "let provider = result.itemProvider",
                 "let kind = ComposeIntake.kind(offered: provider.registeredTypeIdentifiers, "
                    + "isMovie: { UTType($0)?.conforms(to: .movie) == true })",
                 "return ComposeIntake.Item(name: provider.suggestedName, kind: kind) { staging, tally, done in",
                 "ShareItems.read(provider, title: nil, staging: staging, tally: tally, videos: .h264, "
                    + "done: done)"],
                in: code)
        XCTAssertFalse(code.contains(".compatible"), "no copy asked of Photos (B-142)")
        XCTAssertEqual(count("preferredAssetRepresentationMode", in: code), 1)
        XCTAssertFalse(code.contains("suggestedName ?? \"\""), "a row with no name says what it is")
        XCTAssertEqual(count("PHPickerConfiguration(", in: code), 1)
        XCTAssertEqual(count("PHPickerConfiguration(photoLibrary", in: code), 0,
                       "no library, so no permission")
        XCTAssertFalse(code.contains("config.filter = .images"))
    }

    /// Attach File: the document picker for any file that is data, as
    /// copies, several at a time; no security-scoped access anywhere, and
    /// each handed to the intake with its type from `UTType`.
    func testAttachFileOpensTheDocumentPickerForAnyFileAsCopies() throws {
        let code = try source(Self.composer)
        inOrder(["@objc private func attachFileTapped() {",
                 "let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.data], asCopy: true)",
                 "picker.allowsMultipleSelection = true",
                 "picker.delegate = self",
                 "present(picker, animated: true)"], in: code)
        inOrder(["func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {",
                 "intake.take(urls.map { url in",
                 "ComposeIntake.file(at: url, mimeType: { UTType(filenameExtension: $0)?.preferredMIMEType })"],
                in: code)
        XCTAssertTrue(code.contains("UIDocumentPickerDelegate {"))
        XCTAssertTrue(code.contains("import UniformTypeIdentifiers"))
        let walk = FileManager.default.enumerator(at: ios.appendingPathComponent("Sources"),
                                                  includingPropertiesForKeys: nil)
        var read = 0
        while let url = walk?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            read += 1
            let file = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(file.contains("startAccessingSecurityScopedResource"), url.lastPathComponent)
        }
        XCTAssertGreaterThan(read, 100)
    }

    /// No camera, no scanner, no drawing: nothing asks for the camera, and
    /// the Info.plist has no words for it, nor any key a document picker
    /// opened as copies would need.
    func testNothingAsksForTheCamera() throws {
        let plist = try String(contentsOf: ios.appendingPathComponent("Resources/Info.plist"),
                               encoding: .utf8)
        for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription",
                    "UISupportsDocumentBrowser", "LSSupportsOpeningDocumentsInPlace",
                    "UIFileSharingEnabled"] {
            XCTAssertFalse(plist.contains(key), key)
        }
        let code = try source(Self.composer)
        for never in ["UIImagePickerController", "VNDocumentCamera", "PKCanvasView", ".camera"] {
            XCTAssertFalse(code.contains(never), never)
        }
    }

    /// The composer makes no picture of its own: no `jpegData`, no
    /// `UIImage` loaded from a provider. What it is handed is read as the
    /// share sheet reads it, and the old ".jpg" name is gone.
    func testTheComposerMakesNoJPEGOfItsOwn() throws {
        let code = try source(Self.composer)
        for never in ["jpegData(", "pngData(", "loadObject(", "canLoadObject(",
                      "AttachmentStore.write(", "+ \".jpg\"", ".attachmentFailed"] {
            XCTAssertEqual(count(never, in: code), 0, never)
        }
        XCTAssertEqual(count("ShareItems.read(", in: code), 1)
        let share = try source("Sources/Blackmail/Share/ShareViewController.swift")
        XCTAssertTrue(share.contains("static func read(_ provider: NSItemProvider, title: String?, "
                                     + "staging: Staging, tally: Tally, videos: VideoConversion?, "
                                     + "done: @escaping (SharedItem?) -> Void) -> Loading {"))
        XCTAssertFalse(share.contains("private static func read("))
    }

    /// The two buttons, in Mail's words with their symbols, each the size
    /// of its words; both held while a letter goes; "Attach Photo" gone.
    func testTheTwoButtonsAreMailsWordsAndHeldWhileALetterGoes() throws {
        let code = try source(Self.composer)
        inOrder(["private func attachRow() -> UIView {",
                 "let photos = attachButton(\"Photo Library\", symbol: \"photo.on.rectangle\", "
                    + "action: #selector(photoLibraryTapped))",
                 "let files = attachButton(\"Attach File\", symbol: \"doc\", "
                    + "action: #selector(attachFileTapped))",
                 "photoButton = photos",
                 "fileButton = files",
                 "files.leadingAnchor.constraint(equalTo: photos.trailingAnchor)",
                 "private func attachButton(_ words: String, symbol: String, action: Selector) -> UIButton {",
                 "config.image = UIImage(systemName: symbol)",
                 "config.preferredSymbolConfigurationForImage = "
                    + "UIImage.SymbolConfiguration(font: Theme.fontDetailMeta)",
                 "var title = AttributedString(words)",
                 "title.font = Theme.fontDetailMeta",
                 "button.addTarget(self, action: action, for: .touchUpInside)"], in: code)
        XCTAssertFalse(code.contains("Attach Photo"))
        inOrder(["private func draw(_ look: ComposeActions.Look) {",
                 "navigationItem.leftBarButtonItem?.isEnabled = !sending",
                 "photoButton?.isEnabled = !sending",
                 "fileButton?.isEnabled = !sending"], in: code)
        XCTAssertEqual(count("Photo Library\"", in: code), 1)
        XCTAssertEqual(count("Attach File\"", in: code), 1)
    }

    /// Something on its way in has a row, its name and a spinner, after
    /// the letter's own rows; what could not be attached is said over the
    /// sheet once nothing else is up over it, and not once it has gone.
    func testTheRowsWhileItComesAndTheWordsAfter() throws {
        let code = try source(Self.composer)
        inOrder(["private func rebuildAttachments() {",
                 "for (index, attachment) in draft.attachments.enumerated() {",
                 "attachmentsStack.addArrangedSubview(attachmentRow(attachment, at: index))",
                 "for coming in intake.coming {",
                 "attachmentsStack.addArrangedSubview(comingRow(coming))",
                 "private func comingRow(_ coming: ComposeIntake.Coming) -> UIView {",
                 "label.text = coming.name",
                 "let spinner = UIActivityIndicatorView(style: .medium)",
                 "spinner.startAnimating()"], in: code)
        inOrder(["private lazy var intake = ComposeIntake(",
                 "actions: actions,",
                 "rows: { [weak self] in self?.draft.attachments ?? [] },",
                 "landed: { [weak self] url, row in self?.landed(url, row) },",
                 "changed: { [weak self] in self?.rebuildAttachments() },",
                 "tell: { [weak self] words in self?.say(words) })"], in: code)
        inOrder(["private func say(_ words: String) {",
                 "guard viewIfLoaded?.window != nil else { return }",
                 "guard presentedViewController == nil else {",
                 "self?.say(words)",
                 "return",
                 "ErrorPresenter.tell(words, on: self)"], in: code)
    }

    /// The bound on what is coming in stops as the app goes into the
    /// background and runs again from its return (`ComposeIntake.away`,
    /// `back`).
    func testTheBoundStopsWhileTheAppIsAway() throws {
        let code = try source(Self.composer)
        inOrder(["centre.addObserver(self, selector: #selector(leavingTheApp), "
                    + "name: UIApplication.didEnterBackgroundNotification, object: nil)",
                 "centre.addObserver(self, selector: #selector(backInTheApp), "
                    + "name: UIApplication.willEnterForegroundNotification, object: nil)",
                 "@objc private func leavingTheApp() {",
                 "intake.away()",
                 "actions.putAside { self.currentLetter() }",
                 "@objc private func backInTheApp() {",
                 "intake.back()",
                 "}"], in: code)
        XCTAssertEqual(count("intake.away()", in: code), 1)
        XCTAssertEqual(count("intake.back()", in: code), 1)
    }

    /// A photo or a video still being read in as the app goes is called
    /// off (B-142). `ShareItems.read` hands back its read, and every load
    /// it begins is the one the read calls off: a video's, whose line then
    /// says so, and each of a picture's ways, the next not begun once it is
    /// called off. The composer hands that read to the intake as the
    /// closure's one expression, and leaving the app calls it off before
    /// the letter is kept; coming back reads it again.
    func testAReadUnderWayIsCalledOffAsTheAppGoes() throws {
        let share = try source("Sources/Blackmail/Share/ShareViewController.swift")
        inOrder(["static func read(_ provider: NSItemProvider, title: String?, staging: Staging, "
                    + "tally: Tally, videos: VideoConversion?, done: @escaping (SharedItem?) -> Void) -> Loading {",
                 "let loading = Loading()",
                 "picture(provider, type: type, staging: staging, loading: loading) { item in",
                 "let progress = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in",
                 "went: loading.isCancelled ? .calledOff : .notGiven))",
                 "return done(nil)",
                 "done(item)",
                 "loading.track(progress)",
                 "} else {",
                 "done(nil)",
                 "return loading"], in: share)
        XCTAssertEqual(count("loading.track(", in: share), 1)

        let imageIO = try source("Sources/Blackmail/Share/SharedPhotoImageIO.swift")
        inOrder(["private static func picture(_ provider: NSItemProvider, as types: ArraySlice<String>, "
                    + "unopened: [String], staging: Staging, loading: Loading,",
                 "guard !loading.isCancelled else {",
                 "return calledOff(",
                 "guard let type = types.first else {",
                 "let progress = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in",
                 "case .unopened: break",
                 "guard !loading.isCancelled else {",
                 "report.went = .leftOut(\"called off\")",
                 "return finish(nil, report, done)",
                 "let progress = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in",
                 "loading.track(progress)",
                 "loading.track(progress)",
                 "static func calledOff("], in: imageIO)
        XCTAssertEqual(count("loading.track(", in: imageIO), 2)

        let object = try source("Sources/Blackmail/Share/SharedPhotoObject.swift")
        inOrder(["let progress = provider.loadObject(ofClass: UIImage.self) { object, _ in",
                 "loading.track(progress)",
                 "private static func item(",
                 "guard !loading.isCancelled else {",
                 "return calledOff(",
                 "provider.loadItem(forTypeIdentifier: type, options: nil) { object, _ in"], in: object)

        let composer = try source(Self.composer)
        XCTAssertTrue(composer.contains(
            "kind: kind) { staging, tally, done in "
            + "ShareItems.read(provider, title: nil, staging: staging, tally: tally, videos: .h264, "
            + "done: done) }"),
            "the read handed back, as the closure's one expression")
        inOrder(["@objc private func leavingTheApp() {",
                 "intake.away()",
                 "actions.putAside { self.currentLetter() }",
                 "}",
                 "@objc private func backInTheApp() {",
                 "intake.back()",
                 "}"], in: composer)
    }

    /// The sheet closing with nothing waiting for what is coming calls the
    /// read under way off (B-142): every way the composer closes without
    /// Send or Save Draft goes through `ComposeActions`, Delete Draft, a
    /// Cancel that asks nothing and the sheet put away, which tells the
    /// intake (`whenClosed`, pinned on the host by `ComposerFilesTests`).
    /// The sheet's one `dismiss` is `ComposeActions`'.
    func testClosingTheSheetReachesTheIntake() throws {
        let composer = try source(Self.composer)
        inOrder(["dismiss: { [weak self] in self?.close() },",
                 "private lazy var intake = ComposeIntake( actions: actions,"], in: composer)
        inOrder(["override func viewDidDisappear(_ animated: Bool) {",
                 "guard navigationController?.isBeingDismissed ?? isBeingDismissed else { return }",
                 "actions.sheetGone { currentLetter() }"], in: composer)
        inOrder(["@objc private func cancelTapped() {",
                 "actions.closeWithoutAsking { letter }",
                 "self.actions.saveAndClose({ self.draft }, then: nil)",
                 "self.actions.deleteAndClose(self.draft.savedID, letter: self.draft.savedLetter,"],
                in: composer)
        let intake = try source("Sources/Blackmail/Mail/ComposeIntake.swift")
        XCTAssertTrue(intake.contains("actions.whenClosed { [weak self] in self?.close() }"))
    }

    /// At launch the staging and the Inbox go, in the app and the share
    /// extension both; a file is moved in as class C, as one copied is.
    func testThePurgeAtLaunchAndTheMove() throws {
        let app = try source("Sources/Blackmail/App/AppDelegate.swift")
        XCTAssertTrue(app.contains("AttachmentStore.purge()"))
        let store = try source("Sources/Blackmail/Mail/AttachmentStore.swift")
        inOrder(["static func purge(inbox: URL? = inbox()) {",
                 "try? FileManager.default.removeItem(at: root)",
                 "if let inbox { try? FileManager.default.removeItem(at: inbox) }"], in: store)
        inOrder(["static func move(_ source: URL, named filename: String) throws -> URL {",
                 "let url = try place(for: filename)",
                 "try FileManager.default.moveItem(at: source, to: url)",
                 "readableWhileLocked(url)",
                 "return url"], in: store)
        inOrder(["return temporary.appendingPathComponent(bundle + \"-Inbox\", isDirectory: true)"],
                in: store)
    }
}
