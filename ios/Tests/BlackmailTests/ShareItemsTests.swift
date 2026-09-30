import XCTest
@testable import Blackmail

/// What a share hands over, taken in (B-036): one item at a time, each
/// file on the disk as it arrives and only while the share's files still
/// fit in a letter that could go, words that are only an address taken as
/// the link they are, and a file's name with its extension.
final class ShareItemsTests: XCTestCase {

    // MARK: - One at a time

    /// Loads that call back later, on another thread, as item providers
    /// do: each begins only once the one before it has called back, and
    /// what they found arrives in their order, without the ones that found
    /// nothing.
    func testItemsAreTakenInOneAtATimeInTheirOrder() {
        let tally = Tally()
        let loads: [(@escaping (Int?) -> Void) -> Void] = (0..<5).map { index in
            { done in
                tally.begin(index)
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(2)) {
                    tally.end()
                    done(index == 2 ? nil : index)
                }
            }
        }

        let finished = expectation(description: "done")
        ShareItems.oneAtATime(loads) { tally.finish($0); finished.fulfill() }
        wait(for: [finished], timeout: 5)

        XCTAssertEqual(tally.most, 1, "never two at once")
        XCTAssertEqual(tally.begun, [0, 1, 2, 3, 4])
        XCTAssertEqual(tally.found, [0, 1, 3, 4])
    }

    /// How many loads are running, from any thread.
    private final class Tally: @unchecked Sendable {
        private let lock = NSLock()
        private var running = 0
        private(set) var most = 0
        private(set) var begun: [Int] = []
        private(set) var found: [Int]?

        func begin(_ index: Int) {
            lock.lock()
            running += 1
            most = max(most, running)
            begun.append(index)
            lock.unlock()
        }

        func end() {
            lock.lock()
            running -= 1
            lock.unlock()
        }

        func finish(_ found: [Int]) {
            lock.lock()
            self.found = found
            lock.unlock()
        }
    }

    func testNothingSharedIsNothingFound() {
        var found: [Int]?
        ShareItems.oneAtATime([(@escaping (Int?) -> Void) -> Void]()) { found = $0 }
        XCTAssertEqual(found, [])
    }

    // MARK: - Staging

    /// Staged nowhere: the test keeps what was written or copied, and
    /// refuses the names it is told to, as a full disk would.
    private final class Disk {
        var written: [String: Data] = [:]
        var copied: [String: URL] = [:]
        var refuses: Set<String> = []

        func write(_ data: Data, _ filename: String) throws -> URL {
            guard !refuses.contains(filename) else { throw CocoaError(.fileWriteOutOfSpace) }
            written[filename] = data
            return URL(fileURLWithPath: "/staged/\(filename)")
        }

        func copy(_ source: URL, _ filename: String) throws -> URL {
            guard !refuses.contains(filename) else { throw CocoaError(.fileWriteOutOfSpace) }
            copied[filename] = source
            return URL(fileURLWithPath: "/staged/\(filename)")
        }
    }

    private func staging(_ disk: Disk) -> ShareItems.Staging {
        ShareItems.Staging(write: disk.write, copy: disk.copy)
    }

    /// A photograph goes onto the disk as it arrives, and the letter gets
    /// where it went, not the bytes.
    func testAPhotoIsStagedAsItArrives() {
        let disk = Disk()
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
        let item = staging(disk).photo(jpeg, named: "Garden.jpg")

        XCTAssertEqual(item, .file(URL(fileURLWithPath: "/staged/Garden.jpg"),
                                   filename: "Garden.jpg", mimeType: "image/jpeg", size: 7))
        XCTAssertEqual(disk.written["Garden.jpg"], jpeg)
    }

    /// A file too big for what is left of a letter that could go is left
    /// out without being copied, let alone read; a smaller one after it
    /// that still fits goes.
    func testAFileThatCannotGoIsNotEvenCopied() {
        let disk = Disk()
        let staging = staging(disk)
        let budget = ShareItems.Staging.budget
        let video = URL(fileURLWithPath: "/shared/Party.mov")
        let scan = URL(fileURLWithPath: "/shared/Scan.pdf")

        XCTAssertNotNil(staging.photo(Data(count: 1_000), named: "Garden.jpg"))
        XCTAssertNil(staging.file(at: video, size: budget, named: "Party.mov",
                                  mimeType: "video/quicktime"))
        XCTAssertNil(disk.copied["Party.mov"], "never copied")
        XCTAssertNotNil(staging.file(at: scan, size: budget - 1_000, named: "Scan.pdf",
                                     mimeType: "application/pdf"),
                        "exactly the room that was left")
        XCTAssertEqual(disk.copied["Scan.pdf"], scan)
        XCTAssertEqual(staging.staged, budget)
    }

    /// A file that could not be written is left out, costs none of the
    /// room, and the rest go.
    func testAFileThatCannotBeStagedIsLeftOut() {
        let disk = Disk()
        disk.refuses = ["Broken.jpg"]
        let staging = staging(disk)

        XCTAssertNil(staging.photo(Data(count: 10), named: "Broken.jpg"))
        XCTAssertNotNil(staging.photo(Data(count: 20), named: "Fine.jpg"))
        XCTAssertEqual(staging.staged, 20)
    }

    // MARK: - Words and names

    /// Words that are only a web address are the link, with the title the
    /// sharing app offered; anything else is words, as they came.
    func testWordsThatAreOnlyAnAddressAreALink() {
        let page = URL(string: "https://example.org/page")!
        XCTAssertEqual(ShareItems.item(fromText: "  https://example.org/page\n", title: "Page"),
                       .link(page, title: "Page"))
        XCTAssertEqual(ShareItems.item(fromText: "HTTP://example.org/page", title: nil),
                       .link(URL(string: "HTTP://example.org/page")!, title: nil))
        XCTAssertEqual(ShareItems.item(fromText: "Look https://example.org/page", title: nil),
                       .text("Look https://example.org/page"))
        XCTAssertEqual(ShareItems.item(fromText: "ftp://example.org/file", title: nil),
                       .text("ftp://example.org/file"))
        XCTAssertEqual(ShareItems.item(fromText: "Three lines\nof a poem", title: nil),
                       .text("Three lines\nof a poem"))
    }

    /// The suggested name keeps the file's extension, which is what tells a
    /// reader's client how to open it, and is not given it twice.
    func testAFilesNameKeepsItsExtension() {
        let file = URL(fileURLWithPath: "/shared/IMG_0001.pdf")
        XCTAssertEqual(ShareItems.filename(suggested: "Receipt", for: file), "Receipt.pdf")
        XCTAssertEqual(ShareItems.filename(suggested: "Receipt.pdf", for: file), "Receipt.pdf")
        XCTAssertEqual(ShareItems.filename(suggested: "Receipt.PDF", for: file), "Receipt.PDF")
        XCTAssertEqual(ShareItems.filename(suggested: nil, for: file), "IMG_0001.pdf")
        XCTAssertEqual(ShareItems.filename(suggested: "Notes",
                                           for: URL(fileURLWithPath: "/shared/notes")),
                       "Notes", "no extension to add, and no bare dot")
    }
}
