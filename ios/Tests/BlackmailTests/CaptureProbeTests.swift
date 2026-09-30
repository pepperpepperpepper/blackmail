import XCTest
@testable import Blackmail

/// The send transcripts on the iPad are kept to the newest `CaptureProbe.kept`.
final class CaptureProbeTests: XCTestCase {

    private var directory: String!

    override func setUp() {
        super.setUp()
        directory = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("CaptureProbeTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: directory,
                                                 withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(atPath: directory) }
        directory = nil
        super.tearDown()
    }

    /// Writes `name` with a modification time `age` seconds before a fixed
    /// moment, so the order does not depend on how fast the test runs.
    private func file(_ name: String, age: TimeInterval) {
        let path = (directory as NSString).appendingPathComponent(name)
        FileManager.default.createFile(atPath: path, contents: Data("x".utf8))
        let when = Date(timeIntervalSince1970: 1_790_000_000 - age)
        try? FileManager.default.setAttributes([.modificationDate: when], ofItemAtPath: path)
    }

    private var left: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).sorted()
    }

    func testOnlyTheNewestTenTranscriptsStay() {
        for n in 1...13 { file("blackmail-send-\(n)-ok.txt", age: TimeInterval(100 - n)) }
        CaptureProbe.prune(in: directory, keeping: CaptureProbe.kept)
        XCTAssertEqual(CaptureProbe.kept, 10)
        XCTAssertEqual(left, (4...13).map { "blackmail-send-\($0)-ok.txt" }.sorted())
    }

    func testNothingButTranscriptsIsTouched() {
        for n in 1...12 { file("blackmail-send-\(n)-fail.txt", age: TimeInterval(100 - n)) }
        file("blackmail-send-notes.log", age: 500)
        file("other.txt", age: 500)
        file("Attachments", age: 500)
        CaptureProbe.prune(in: directory, keeping: 10)
        XCTAssertTrue(left.contains("blackmail-send-notes.log"))
        XCTAssertTrue(left.contains("other.txt"))
        XCTAssertTrue(left.contains("Attachments"))
        XCTAssertFalse(left.contains("blackmail-send-1-fail.txt"))
        XCTAssertFalse(left.contains("blackmail-send-2-fail.txt"))
        XCTAssertEqual(left.filter { $0.hasPrefix("blackmail-send-") && $0.hasSuffix(".txt") }.count, 10)
    }

    func testTenOrFewerAreLeftAlone() {
        for n in 1...10 { file("blackmail-send-\(n)-ok.txt", age: TimeInterval(100 - n)) }
        CaptureProbe.prune(in: directory, keeping: 10)
        XCTAssertEqual(left.count, 10)
    }

    /// Each send's transcript prunes the rest, so a thirteenth send leaves
    /// ten files, its own among them.
    func testEachTranscriptWrittenLeavesTheNewestTen() {
        let real = CaptureProbe.directory
        CaptureProbe.directory = directory
        defer { CaptureProbe.directory = real }
        for n in 1...12 { file("blackmail-send-old\(n)-ok.txt", age: TimeInterval(100 - n)) }
        CaptureProbe.dumpTranscript("ok", session: "newest")
        XCTAssertEqual(left.count, 10)
        XCTAssertTrue(left.contains("blackmail-send-newest-ok.txt"))
        XCTAssertFalse(left.contains("blackmail-send-old1-ok.txt"))
    }

    /// Two written in the same instant are told apart by name, so the
    /// same one goes every time.
    func testATieIsBrokenByName() {
        for name in ["blackmail-send-b-ok.txt", "blackmail-send-a-ok.txt", "blackmail-send-c-ok.txt"] {
            file(name, age: 5)
        }
        CaptureProbe.prune(in: directory, keeping: 2)
        XCTAssertEqual(left, ["blackmail-send-b-ok.txt", "blackmail-send-c-ok.txt"])
    }
}
