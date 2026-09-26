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
}
