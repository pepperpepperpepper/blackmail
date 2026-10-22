import XCTest
@testable import Blackmail

/// What a draft's APPEND holds, made whole (D-017's revisit, B-108). The
/// composer attaches videos and any file up to the letter's 25 MB since
/// B-108, and Save Draft still makes the letter whole in the app's memory
/// before it goes to Drafts, where Send makes it a block at a time.
///
/// Measured behind `BLACKMAIL_LARGE_TESTS`, by Linux's high-water mark in a
/// debug build (`PeakMemory`), as `StreamingSendMemoryTests` measures Send:
/// not the iPad, nor its allocator. First the letter alone, its file read
/// whole and the letter built from it, as `IMAPMailRepository.append` makes
/// it; then the whole Save Draft through the shipping repository to the
/// scripted server, which keeps its own copies of what it is sent, so that
/// figure is the app's and the server's together, an upper bound. The
/// bounds are loose: the numbers are what D-017 records.
final class DraftAppendMemoryTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DraftAppendMemoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        super.tearDown()
    }

    func testTheWholeAppendOfATwentyFiveMegabyteDraft() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BLACKMAIL_LARGE_TESTS"] != nil,
                          "set BLACKMAIL_LARGE_TESTS to save a draft of 25 MB")
        let size = 25_000_000
        // Written a megabyte at a time, so the file is never in memory
        // whole before the measure.
        let url = directory.appendingPathComponent("IMG_0001.MOV")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        var written = 0
        while written < size {
            let length = min(1_000_000, size - written)
            try handle.write(contentsOf: LetterCorpus.bytes(length, seed: written + 3))
            written += length
        }
        try handle.close()

        let server = ScriptedIMAPServer()
        var draft = Draft()
        draft.to = ["carlo@example.org"]
        draft.subject = "The video"
        draft.body = "Here it is."
        draft.attachments = [DraftAttachment(source: .localFile(url), filename: "IMG_0001.MOV",
                                             mimeType: "video/quicktime", size: Int64(size))]

        var length = 0
        let account = server.account
        let built = try await PeakMemory.growth {
            let letter = AppleMailHTML.letter(for: draft, account: account, forDraft: true)
            let data = try Data(contentsOf: url)
            let raw = RFC5322Builder.build(draft: draft, from: account,
                                           messageID: "<b108-append@example.com>",
                                           attachments: [("IMG_0001.MOV", "video/quicktime", data)],
                                           includeBcc: true, htmlBody: letter.html)
            length = raw.count
        }
        guard let built else { throw XCTSkip("the high-water mark cannot be read here") }

        let defaults = UserDefaults(suiteName: "DraftAppendMemoryTests")!
        defaults.removePersistentDomain(forName: "DraftAppendMemoryTests")
        let repository = IMAPMailRepository(
            account: server.account, password: server.password,
            transport: server.transportFactory, recipients: RecipientBook(defaults: defaults),
            signatureImages: { [] }, shelf: keptShelf(for: server.account))
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        var saved: String?
        let whole = try await PeakMemory.growth {
            saved = try await repository.saveDraft(draft)
        }
        defaults.removePersistentDomain(forName: "DraftAppendMemoryTests")
        print("B108-APPEND size=\(size) letter=\(length) built=\(built) "
              + "saved=\(whole.map(String.init) ?? "-")")
        XCTAssertNotNil(saved)
        XCTAssertGreaterThan(length, size * 4 / 3)
        XCTAssertLessThan(built, 8 * size, "\(built) bytes to build a letter of \(length)")
        XCTAssertEqual(server.violations, [])
    }
}
