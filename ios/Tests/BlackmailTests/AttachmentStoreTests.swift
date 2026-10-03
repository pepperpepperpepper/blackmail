import XCTest
@testable import Blackmail

/// Tests for the one place in the app that creates a file whose NAME a
/// stranger chose.
///
/// An attachment's filename comes off the wire from whoever sent the
/// message. It reaches `appendingPathComponent`, and a name that resolves to
/// a directory or climbs out of one puts the write somewhere nobody
/// intended. None of that is exotic input — it is one header field.
final class AttachmentStoreTests: XCTestCase {

    override func tearDown() {
        AttachmentStore.purge()
        super.tearDown()
    }

    // MARK: - Names that must not escape

    func testPathSeparatorsAreStripped() {
        XCTAssertEqual(AttachmentStore.safeFilename("../../Documents/bootstrap.json"),
                       "bootstrap.json")
        XCTAssertEqual(AttachmentStore.safeFilename("/etc/passwd"), "passwd")
        XCTAssertEqual(AttachmentStore.safeFilename(#"..\..\windows\system32\x.dll"#), "x.dll")
    }

    func testDotAndDotDotBecomeAPlainName() {
        // Both survive every character filter — neither contains anything
        // illegal — and both name a DIRECTORY, so appending them hands back
        // the parent rather than a file.
        XCTAssertEqual(AttachmentStore.safeFilename(".."), "attachment")
        XCTAssertEqual(AttachmentStore.safeFilename("."), "attachment")
    }

    func testEmptyAndWhitespaceNamesGetAFallback() {
        XCTAssertEqual(AttachmentStore.safeFilename(""), "attachment")
        XCTAssertEqual(AttachmentStore.safeFilename("   "), "attachment")
        XCTAssertEqual(AttachmentStore.safeFilename("\n\t"), "attachment")
    }

    func testControlCharactersAndColonsAreRemoved() {
        XCTAssertEqual(AttachmentStore.safeFilename("re\u{0}port\u{7}.pdf"), "report.pdf")
        XCTAssertEqual(AttachmentStore.safeFilename("a:b.pdf"), "ab.pdf")
    }

    func testAnAbsurdlyLongNameIsCutFromTheBackNotTheFront() {
        let long = String(repeating: "a", count: 4000) + ".pdf"
        let safe = AttachmentStore.safeFilename(long)
        XCTAssertLessThanOrEqual(safe.count, 120)
        XCTAssertTrue(safe.allSatisfy { $0 == "a" },
                      "the front is what survives; truncating the other way would keep .pdf and lose the name")
    }

    func testOrdinaryNamesArriveUntouched() {
        // Over-sanitising costs the reader the name of his own document.
        for name in ["Invoice-QX7T2KDA-0001.pdf", "Receipt 1234.pdf",
                     "photo (1).jpeg", "Résumé.docx", "报告.pdf", "a.b.c.tar.gz"] {
            XCTAssertEqual(AttachmentStore.safeFilename(name), name)
        }
    }

    // MARK: - Writing

    func testWrittenFileLandsInsideTheStoreAndHoldsTheBytes() throws {
        let bytes = Data("%PDF-1.4 hello".utf8)
        let url = try AttachmentStore.write(bytes, named: "receipt.pdf")

        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(url.lastPathComponent, "receipt.pdf",
                       "the reader should see the name the sender gave it")
        XCTAssertTrue(url.standardizedFileURL.path
            .hasPrefix(AttachmentStore.root.standardizedFileURL.path),
                      "the write escaped the store: \(url.path)")
    }

    func testAHostileNameStillLandsInsideTheStore() throws {
        let url = try AttachmentStore.write(Data("x".utf8), named: "../../escaped.txt")
        XCTAssertTrue(url.standardizedFileURL.path
            .hasPrefix(AttachmentStore.root.standardizedFileURL.path),
                      "escaped to \(url.path)")
        XCTAssertEqual(url.lastPathComponent, "escaped.txt")
    }

    func testTwoFilesWithTheSameNameDoNotCollide() throws {
        let first = try AttachmentStore.write(Data("one".utf8), named: "scan.pdf")
        let second = try AttachmentStore.write(Data("two".utf8), named: "scan.pdf")

        XCTAssertNotEqual(first, second)
        // Both keep the sender's name; it is the DIRECTORY that differs, so
        // neither has to be shown to the reader as "scan-2.pdf".
        XCTAssertEqual(first.lastPathComponent, "scan.pdf")
        XCTAssertEqual(second.lastPathComponent, "scan.pdf")
        XCTAssertEqual(try Data(contentsOf: first), Data("one".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("two".utf8))
    }

    /// A file handed over by another app is copied in under a safe name,
    /// as bytes are written, and the original is left where it was.
    func testACopiedFileLandsInsideTheStore() throws {
        let original = try AttachmentStore.write(Data("%PDF-1.4 scan".utf8), named: "handed-over")
        let url = try AttachmentStore.copy(original, named: "../Scan.pdf")

        XCTAssertEqual(try Data(contentsOf: url), Data("%PDF-1.4 scan".utf8))
        XCTAssertEqual(url.lastPathComponent, "Scan.pdf")
        XCTAssertTrue(url.standardizedFileURL.path
            .hasPrefix(AttachmentStore.root.standardizedFileURL.path), url.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testPurgeRemovesEverything() throws {
        let url = try AttachmentStore.write(Data("x".utf8), named: "a.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        AttachmentStore.purge()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: AttachmentStore.root.path))
    }

    func testWritingStillWorksAfterAPurge() throws {
        AttachmentStore.purge()
        // The store recreates its directory rather than assuming one launch
        // made it: purge happens at launch, and opening a file happens later.
        let url = try AttachmentStore.write(Data("x".utf8), named: "a.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Removing what was staged (B-063)

    private var files: FileManager { .default }

    /// A directory of its own for a test, outside the store, standing in
    /// for Application Support where a letter kept on the iPad lives.
    private func elsewhere() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AttachmentStoreTests-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Only a directory the store made, directly in it and named by a UUID,
    /// counts as staging; a file anywhere else, a letter kept on the iPad
    /// above all, has none, and so nothing that could be removed for it.
    func testOnlyADirectoryTheStoreMadeIsAStagingDirectory() throws {
        let root = AttachmentStore.root
        let staged = try AttachmentStore.write(Data("x".utf8), named: "receipt.pdf")
        XCTAssertEqual(AttachmentStore.stagingDirectory(of: staged)?.path,
                       staged.deletingLastPathComponent().standardizedFileURL.path)
        let copied = try AttachmentStore.copy(staged, named: "copy.pdf")
        XCTAssertEqual(AttachmentStore.stagingDirectory(of: copied)?.path,
                       copied.deletingLastPathComponent().standardizedFileURL.path)

        let uuid = UUID().uuidString
        let kept = try elsewhere().appendingPathComponent("letter-1/\(uuid.lowercased())")
        let none: [(String, URL)] = [
            ("a letter kept on the iPad", kept),
            ("a file in the store itself", root.appendingPathComponent("receipt.pdf")),
            ("a directory deeper down",
             root.appendingPathComponent("\(uuid)/inner/receipt.pdf")),
            ("a directory not named by the store",
             root.appendingPathComponent("Letters/receipt.pdf")),
            ("the store itself", root),
            ("a staging directory, not a file in one",
             root.appendingPathComponent(uuid, isDirectory: true)),
            ("a way out of the store",
             root.appendingPathComponent("\(uuid)/../../\(uuid)/receipt.pdf")),
            ("the store's parent", root.deletingLastPathComponent()
                .appendingPathComponent("\(uuid)/receipt.pdf")),
            ("not a file at all", URL(string: "https://example.com\(root.path)/\(uuid)/a.pdf")!),
        ]
        for (label, url) in none {
            XCTAssertNil(AttachmentStore.stagingDirectory(of: url), label)
        }
        // A path that comes back into the store names the directory it
        // comes back to, which the store did make.
        let back = root.appendingPathComponent("\(uuid)/../\(staged.deletingLastPathComponent().lastPathComponent)/receipt.pdf")
        XCTAssertEqual(AttachmentStore.stagingDirectory(of: back)?.path,
                       staged.deletingLastPathComponent().standardizedFileURL.path)
    }

    /// Removing a staged file takes its directory and nothing else: not the
    /// file beside it, not the store, not a file kept elsewhere.
    func testRemovingAStagedFileTakesItsDirectoryAndNothingElse() throws {
        let first = try AttachmentStore.write(Data("one".utf8), named: "scan.pdf")
        let second = try AttachmentStore.write(Data("two".utf8), named: "scan.pdf")
        let kept = try elsewhere().appendingPathComponent("photo")
        try Data("kept".utf8).write(to: kept)

        AttachmentStore.removeStaged(first)
        AttachmentStore.removeStaged(kept)
        AttachmentStore.removeStaged(AttachmentStore.root)

        XCTAssertFalse(files.fileExists(atPath: first.deletingLastPathComponent().path))
        XCTAssertEqual(try Data(contentsOf: second), Data("two".utf8))
        XCTAssertEqual(try Data(contentsOf: kept), Data("kept".utf8))
        XCTAssertTrue(files.fileExists(atPath: AttachmentStore.root.path))
        // Twice is nothing.
        AttachmentStore.removeStaged(first)
    }

    /// The reading pane's way with a file he opens, as it runs: the last one
    /// goes as the next is written, and not before, so the store never
    /// holds more than one, and the one it holds is the last he opened,
    /// whole, for a print of it to read after its preview has closed. The
    /// launch's purge takes that.
    func testOpeningFileAfterFileLeavesOneCopyAtMostTheLastWhole() throws {
        AttachmentStore.purge()
        func staged() throws -> [String] {
            (try? files.contentsOfDirectory(atPath: AttachmentStore.root.path)) ?? []
        }
        var shown: URL?
        for name in ["scan.pdf", "receipt.pdf", "photo.jpg"] {
            if let previous = shown { AttachmentStore.removeStaged(previous) }
            shown = try AttachmentStore.write(Data(name.utf8), named: name)
            XCTAssertEqual(try staged().count, 1, name)
        }
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(shown)), Data("photo.jpg".utf8))
        AttachmentStore.purge()
        XCTAssertEqual(try staged(), [])
    }

    /// The composer's photos: everything it staged goes when it does, and a
    /// letter kept on the iPad keeps its photo, which is a link of its own
    /// in its own directory, byte for byte. The kept file's URL handed in
    /// as well, as a letter reopened from the iPad carries it, is left
    /// alone.
    @MainActor
    func testAComposersPhotosGoAndAKeptLettersPhotoStays() throws {
        let photo = Data((0..<4_096).map { UInt8($0 % 251) })
        let garden = try AttachmentStore.write(photo, named: "Garden.jpg")
        let roof = try AttachmentStore.write(Data(photo.reversed()), named: "Roof.jpg")
        var draft = Draft()
        draft.to = ["carlo@example.org"]
        draft.subject = "Sunday"
        draft.attachments = [DraftAttachment(source: .localFile(garden), filename: "Garden.jpg",
                                             mimeType: "image/jpeg", size: Int64(photo.count))]
        let store = LocalDraftStore(root: try elsewhere())
        let letter = try store.keep(draft, as: "letter-1", unfinished: true, account: nil)
        guard case .localFile(let keptPhoto)? = letter.draft.attachments.first?.source else {
            return XCTFail("the kept photo should be a file of the letter")
        }

        let staged = StagedFiles()
        staged.record(garden)
        staged.record(roof)
        staged.record(keptPhoto)
        staged.removeAll()

        XCTAssertFalse(files.fileExists(atPath: garden.deletingLastPathComponent().path))
        XCTAssertFalse(files.fileExists(atPath: roof.deletingLastPathComponent().path))
        XCTAssertEqual(try Data(contentsOf: keptPhoto), photo)
        let back = try XCTUnwrap(store.letter("letter-1"))
        guard case .localFile(let url)? = back.draft.attachments.first?.source else {
            return XCTFail("the kept letter lost its photo")
        }
        XCTAssertEqual(try Data(contentsOf: url), photo)
        XCTAssertEqual(staged.urls, [])
    }

    // MARK: - The wiring, read from the screens' source (B-063)

    /// The screens are UIKit and never build on this host, so their wiring
    /// is read from their source, as `PaneNavigationTests` reads the pane's:
    /// comment lines out, and runs of white space as one space.
    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/UI/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    /// Where each of `steps` is in `code`, in that order, failing for one
    /// missing or out of order.
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

    /// The reading pane: no file written over a preview that is up; the
    /// last copy removed as the next is written, and there alone, then
    /// presented. Never as the preview closes: Print reads the file after
    /// its panel has closed. Nothing hears the preview close, and the item
    /// is never force-unwrapped.
    func testThePaneKeepsOneCopyOfAnOpenedFileAndRemovesItOnlyAsTheNextIsWritten() throws {
        let code = try source("MessageDetailViewController.swift")
        inOrder(["guard presentedViewController == nil else { return }",
                 "if let shown = previewURL { AttachmentStore.removeStaged(shown) }",
                 "previewURL = nil",
                 "previewURL = try AttachmentStore.write(data, named: attachment.filename)",
                 "preview.dataSource = self",
                 "present(preview, animated: true)"], in: code)
        XCTAssertEqual(code.components(separatedBy: "removeStaged").count - 1, 1)
        XCTAssertEqual(code.components(separatedBy: "previewURL = nil").count - 1, 1)
        XCTAssertTrue(code.contains("extension MessageDetailViewController: QLPreviewControllerDataSource {"))
        XCTAssertFalse(code.contains("QLPreviewControllerDelegate"))
        XCTAssertFalse(code.contains("preview.delegate"))
        XCTAssertFalse(code.contains("previewControllerDidDismiss"))
        XCTAssertFalse(code.contains("previewControllerWillDismiss"))
        XCTAssertFalse(code.contains("previewURL!"))
    }

    /// The composer: each photo it stages recorded, and the lot removed
    /// in `deinit` and nowhere else. Send and Save Draft are handed a
    /// closure that holds the composer, so it cannot go while either is
    /// still reading the photos (`ComposeActionsTests`).
    func testTheComposerRemovesWhatItStagedOnlyAsItGoes() throws {
        let code = try source("ComposeViewController.swift")
        inOrder(["guard let url = try? AttachmentStore.write(data, named: filename) else {",
                 "staged.record(url)",
                 "draft.attachments.append(DraftAttachment(source: .localFile(url),"], in: code)
        XCTAssertTrue(code.contains("deinit { staged.removeAll() }"))
        XCTAssertEqual(code.components(separatedBy: "removeAll()").count - 1, 1)
        XCTAssertEqual(code.components(separatedBy: "AttachmentStore.write(").count - 1, 1)
        XCTAssertFalse(code.contains("removeStaged"))
        XCTAssertTrue(code.contains("self.actions.saveAndClose({ self.draft }, then: nil)"))
        XCTAssertTrue(code.contains("actions.send({ self.draft }, then: onDraftsChanged, "
                                    + "draftSent: onDraftSent)"))
        XCTAssertTrue(code.contains("actions.edited { self.currentLetter() }"))
        XCTAssertTrue(code.contains("actions.putAside { self.currentLetter() }"))
    }
}
