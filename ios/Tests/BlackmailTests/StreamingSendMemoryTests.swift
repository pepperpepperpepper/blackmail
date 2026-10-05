import XCTest
@testable import Blackmail

/// What Send holds does not grow with the letter's files (B-070): a video
/// of 19,000,000 bytes, as large as his go, sent from the disk through
/// `Submission` and the shipping SMTP client to a server that keeps
/// nothing of it, raises the test's high-water mark by less than 8 MB.
/// Built whole, the letter and its payload raised it by about 98 MB
/// (2026-10-05, B-070's Found in KNOWN_ISSUES). Measured first; then the
/// letter that arrived, its count and CRC, is held to the reference
/// builder's, which is made afterwards, outside the measure.
///
/// On this host, in a debug build, by Linux's high-water mark
/// (`PeakMemory`): not the iPad, nor its allocator. What `.contentProcessed`
/// holds in the iPad's network stack is not in it either; that is what the
/// iPad's "while it went" line says.
final class StreamingSendMemoryTests: XCTestCase {

    private let account = MailAccount(address: "owner@example.com", username: "owner@example.com",
                                      displayName: "Sam Example")
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StreamingSendMemoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        for outcome in ["ok", "fail"] {
            try? FileManager.default.removeItem(atPath: (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt"))
        }
        super.tearDown()
    }

    func testANineteenMegabyteVideoGoesInMemoryThatDoesNotGrowWithIt() async throws {
        try await sendsWithin(8_000_000, size: 19_000_000)
    }

    func testATwentyFiveMegabyteVideoTheSame() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BLACKMAIL_LARGE_TESTS"] != nil,
                          "set BLACKMAIL_LARGE_TESTS to send 25 MB")
        try await sendsWithin(8_000_000, size: 25_000_000)
    }

    private func sendsWithin(_ bound: Int, size: Int) async throws {
        // Written a megabyte at a time, so the file is never in memory
        // whole before the measure either.
        let url = directory.appendingPathComponent("IMG_0001.MOV")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        var written = 0
        while written < size {
            let length = min(1_000_000, size - written)
            try handle.write(contentsOf: LetterCorpus.bytes(length, seed: written + 1))
            written += length
        }
        try handle.close()

        var draft = Draft()
        draft.to = ["carlo@example.org"]
        draft.subject = "The video"
        draft.body = "Here it is."
        let server = ScriptedSubmission(keepsLetters: false)
        let messageID = "<b070-memory@example.com>"
        let growth = try await PeakMemory.growth {
            try await Submission.send(
                draft, from: account, password: "app-password",
                through: SMTPClient(account: account, transport: { _, _ in server }),
                threadHeaders: nil,
                attachments: { [("IMG_0001.MOV", "video/quicktime",
                                 .disk(url, attachedSize: Int64(size)))] },
                htmlBody: nil, inlineImages: [], messageID: messageID, progress: nil,
                date: date, boundaryToken: Counting().next)
        }
        guard let growth else { throw XCTSkip("the high-water mark cannot be read here") }
        let plan = Diagnostics.entries.map(\.text).last { $0.hasPrefix("LETTER-PLAN") } ?? ""
        print("B070-MEMORY size=\(size) growth=\(growth) \(plan)")
        XCTAssertLessThan(growth, bound, "\(growth) bytes for a file of \(size)")

        let digests = await server.letterDigests
        let raw = ReferenceBuilder.build(draft: draft, from: account, date: date,
                                         messageID: messageID,
                                         attachments: [("IMG_0001.MOV", "video/quicktime",
                                                        try Data(contentsOf: url))],
                                         boundaryToken: Counting().next)
        let letter = SMTPClient.dataPayload(raw).dropLast(3)
        var crc = CRC32()
        crc.update(letter)
        XCTAssertEqual(digests.count, 1)
        XCTAssertEqual(digests.first?.count, letter.count)
        XCTAssertEqual(digests.first?.crc, crc.value)
    }
}
