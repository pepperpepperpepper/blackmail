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

    /// Staged nowhere for a photo: the test keeps what was written, and
    /// refuses the names it is told to, as a full disk would. A copy is a
    /// file on the disk, in a directory of the test's own, of the size
    /// `makes` says, nothing in it, for staging to measure (B-070).
    private final class Disk {
        var written: [String: Data] = [:]
        var copied: [String: URL] = [:]
        var refuses: Set<String> = []
        /// What a copy of each name comes to on the disk.
        var makes: [String: Int64] = [:]
        private(set) var discarded: [URL] = []
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareItemsTests-\(UUID().uuidString)", isDirectory: true)

        func write(_ data: Data, _ filename: String) throws -> URL {
            guard !refuses.contains(filename) else { throw CocoaError(.fileWriteOutOfSpace) }
            written[filename] = data
            return URL(fileURLWithPath: "/staged/\(filename)")
        }

        func copy(_ source: URL, _ filename: String) throws -> URL {
            guard !refuses.contains(filename) else { throw CocoaError(.fileWriteOutOfSpace) }
            copied[filename] = source
            let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(filename)
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(makes[filename] ?? 0))
            try handle.close()
            return url
        }

        func discard(_ url: URL) {
            discarded.append(url)
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    private func staging(_ disk: Disk) -> ShareItems.Staging {
        ShareItems.Staging(write: disk.write, copy: disk.copy, discard: disk.discard)
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
        disk.makes["Scan.pdf"] = budget - 1_000
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

    /// The letter counts the copy as the disk has it, not as the sharing
    /// app said (B-070): what Send checks the file against before it goes.
    /// A copy larger than the room left is taken away again, and the room
    /// is as it was.
    func testAStagedFileIsTheSizeTheDiskHasNotTheSharingAppsWord() {
        let disk = Disk()
        let staging = staging(disk)
        let clip = URL(fileURLWithPath: "/shared/Clip.mov")
        disk.makes["Clip.mov"] = 5_000
        let item = staging.file(at: clip, size: 4_000, named: "Clip.mov", mimeType: "video/quicktime")
        guard case let .file(url, filename, mimeType, size)? = item else {
            return XCTFail("not staged: \(String(describing: item))")
        }
        XCTAssertEqual(size, 5_000, "measured, not the 4,000 it was said to be")
        XCTAssertEqual(filename, "Clip.mov")
        XCTAssertEqual(mimeType, "video/quicktime")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(staging.staged, 5_000)

        let budget = ShareItems.Staging.budget
        disk.makes["Long.mov"] = budget
        XCTAssertNil(staging.file(at: URL(fileURLWithPath: "/shared/Long.mov"), size: 1_000,
                                  named: "Long.mov", mimeType: "video/quicktime"),
                     "said to fit, larger than the room once copied")
        XCTAssertEqual(disk.discarded.map(\.lastPathComponent), ["Long.mov"], "taken away again")
        XCTAssertNotNil(disk.copied["Long.mov"])
        XCTAssertEqual(staging.staged, 5_000)
    }

    /// The size a file's line in the log has, and why it was left out, is
    /// what its copy measured where it was copied: a copy larger than the
    /// room is said to be, not said to be a file not copied. A file never
    /// copied has no measure, and keeps the sharing app's word.
    func testACopyLargerThanTheRoomIsSaidToBeSo() {
        let disk = Disk()
        let staging = staging(disk)
        let budget = ShareItems.Staging.budget
        disk.makes["Clip.mov"] = 5_000
        XCTAssertNotNil(staging.file(at: URL(fileURLWithPath: "/shared/Clip.mov"), size: 4_000,
                                     named: "Clip.mov", mimeType: "video/quicktime"))
        XCTAssertEqual(staging.lastMeasured, 5_000)

        let room = staging.room
        disk.makes["Long.mov"] = budget
        let long = staging.file(at: URL(fileURLWithPath: "/shared/Long.mov"), size: 1_000,
                                named: "Long.mov", mimeType: "video/quicktime")
        XCTAssertNil(long)
        XCTAssertEqual(staging.lastMeasured, budget, "what the copy measured")
        XCTAssertEqual(ShareItems.fileWent(long, size: staging.lastMeasured ?? 1_000, room: room),
                       .noRoom(left: room))

        let huge = staging.file(at: URL(fileURLWithPath: "/shared/Huge.mov"), size: budget,
                                named: "Huge.mov", mimeType: "video/quicktime")
        XCTAssertNil(huge)
        XCTAssertNil(disk.copied["Huge.mov"])
        XCTAssertNil(staging.lastMeasured, "never copied, so never measured")
        XCTAssertEqual(ShareItems.fileWent(huge, size: staging.lastMeasured ?? budget, room: room),
                       .noRoom(left: room))

        disk.refuses = ["Broken.mov"]
        let broken = staging.file(at: URL(fileURLWithPath: "/shared/Broken.mov"), size: 10,
                                  named: "Broken.mov", mimeType: "video/quicktime")
        XCTAssertNil(broken)
        XCTAssertNil(staging.lastMeasured)
        XCTAssertEqual(ShareItems.fileWent(broken, size: staging.lastMeasured ?? 10, room: room),
                       .notCopied)
        XCTAssertEqual(staging.staged, 5_000)
    }

    // MARK: - A video (B-070)

    /// A video is taken as QuickTime whenever it is offered, whatever the
    /// order: the original ".MOV" Photos keeps. Then MPEG-4, then M4V, then
    /// whatever else is a video. Nothing for what is not one.
    func testAVideoIsTakenAsQuickTimeWhateverTheOrder() {
        let movies: Set<String> = ["com.apple.quicktime-movie", "public.mpeg-4",
                                   "com.apple.m4v-video", "public.avi", "public.movie"]
        func type(_ offered: [String]) -> String? {
            ShareItems.movieType(offered: offered, isMovie: movies.contains)
        }
        XCTAssertEqual(type(["public.mpeg-4", "com.apple.quicktime-movie"]), "com.apple.quicktime-movie")
        XCTAssertEqual(type(["com.apple.quicktime-movie", "public.mpeg-4"]), "com.apple.quicktime-movie")
        XCTAssertEqual(type(["public.data", "com.apple.m4v-video", "public.mpeg-4"]), "public.mpeg-4")
        XCTAssertEqual(type(["com.apple.m4v-video"]), "com.apple.m4v-video")
        XCTAssertEqual(type(["public.data", "public.avi"]), "public.avi")
        XCTAssertNil(type(["com.adobe.pdf", "public.data"]))
        XCTAssertNil(type([]))
    }

    /// A video left out is said as a photo is, and with photos: the words
    /// in place of the letter when nothing but photos and videos was
    /// offered and none came, a line over the letter otherwise. Awaiting
    /// the owner's approval.
    func testAVideoLeftOutIsSaidAsAPhotoIs() {
        func said(_ pictures: Int, _ attached: Int, _ videos: Int, _ videosAttached: Int,
                  others: Int = 0) -> ShareItems.LeftOut? {
            ShareItems.leftOut(pictures: pictures, attached: attached, videos: videos,
                               videosAttached: videosAttached, others: others)
        }
        XCTAssertNil(said(0, 0, 1, 1))
        XCTAssertNil(said(2, 2, 3, 3, others: 1))
        XCTAssertEqual(said(0, 0, 1, 0), .instead("The video could not be attached."))
        XCTAssertEqual(said(0, 0, 2, 0), .instead("The videos could not be attached."))
        XCTAssertEqual(said(1, 0, 1, 0), .instead("The photo and the video could not be attached."))
        XCTAssertEqual(said(1, 0, 2, 0), .instead("The photo and the videos could not be attached."))
        XCTAssertEqual(said(2, 0, 1, 0), .instead("The photos and the video could not be attached."))
        XCTAssertEqual(said(3, 0, 2, 0), .instead("The photos and videos could not be attached."))
        XCTAssertEqual(said(0, 0, 2, 1), .line("1 video could not be attached."))
        XCTAssertEqual(said(0, 0, 5, 2), .line("3 videos could not be attached."))
        XCTAssertEqual(said(0, 0, 1, 0, others: 1), .line("1 video could not be attached."))
        XCTAssertEqual(said(2, 2, 1, 0), .line("1 video could not be attached."))
        XCTAssertEqual(said(2, 1, 1, 1), .line("1 photo could not be attached."))
        XCTAssertEqual(said(2, 0, 1, 1), .line("2 photos could not be attached."))
        XCTAssertEqual(said(1, 0, 1, 0, others: 1), .line("1 photo and 1 video could not be attached."))
        XCTAssertEqual(said(3, 1, 3, 0), .line("2 photos and 3 videos could not be attached."))
        XCTAssertEqual(said(2, 1, 2, 1), .line("1 photo and 1 video could not be attached."))
        // A photo's words as they were.
        XCTAssertEqual(said(1, 0, 0, 0), .instead("The photo could not be attached."))
        XCTAssertEqual(said(2, 0, 0, 0), .instead("The photos could not be attached."))
        XCTAssertEqual(said(2, 1, 0, 0), .line("1 photo could not be attached."))
        XCTAssertEqual(ShareItems.leftOut(pictures: 1, attached: 0, others: 0),
                       .instead("The photo could not be attached."))

        let tally = ShareItems.Tally()
        tally.offered = 3
        tally.pictures = 1
        tally.attached = 1
        tally.videos = 2
        tally.videosAttached = 1
        XCTAssertEqual(tally.leftOut, .line("1 video could not be attached."))
    }

    /// What became of a file that is not a picture, for the log: its type,
    /// where its name came from and the name as the log has names, its MIME
    /// type, its bytes, and staged or why not. Nothing of a title someone
    /// gave it but its length.
    func testAFilesLineSaysWhatBecameOfIt() {
        XCTAssertEqual(ShareItems.fileNote(read: "com.apple.quicktime-movie", suggested: false,
                                           name: "IMG_0001.MOV", mimeType: "video/quicktime",
                                           bytes: 19_000_000, went: .staged),
                       "SHARE-FILE read=com.apple.quicktime-movie name=file \"IMG_0001.MOV\""
                       + " mime=video/quicktime bytes=19000000 went=staged")
        XCTAssertEqual(ShareItems.fileNote(read: "public.mpeg-4", suggested: true,
                                           name: "Sam's birthday.mp4", mimeType: "video/mp4",
                                           bytes: 30_000_000, went: .noRoom(left: 24_999_000)),
                       "SHARE-FILE read=public.mpeg-4 name=suggested \"{14 chars}.mp4\""
                       + " mime=video/mp4 bytes=30000000"
                       + " went=left out, more than the letter's room, 24 MB left")
        XCTAssertEqual(ShareItems.fileNote(read: "public.movie", suggested: false, name: "",
                                           mimeType: "-", bytes: 0, went: .notGiven),
                       "SHARE-FILE read=public.movie name=none \"{0 chars}\" mime=- bytes=0"
                       + " went=left out, not given")
        let item = SharedItem.file(URL(fileURLWithPath: "/staged/x"), filename: "x",
                                   mimeType: "video/mp4", size: 1)
        XCTAssertEqual(ShareItems.fileWent(item, size: 1, room: 10), .staged)
        XCTAssertEqual(ShareItems.fileWent(nil, size: 11, room: 10), .noRoom(left: 10))
        XCTAssertEqual(ShareItems.fileWent(nil, size: 10, room: 10), .notCopied)
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
