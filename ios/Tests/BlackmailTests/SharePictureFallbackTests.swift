import XCTest
@testable import Blackmail

/// B-090: a picture shared from the screenshot editor, "The photo could not
/// be attached." on the test iPad, three times of three. A provider that
/// says it holds a picture is read as every picture type it offers, in its
/// own order, before it is given up; then as the `UIImage` it gives, made a
/// PNG or a JPEG here, bounded by the memory, and named as Mail names a
/// picture with no name. And when the sheet says something could not be
/// attached, its lines in the log are written where a check reads them.
/// The rules here; UIKit and ImageIO doing them are on the iPad only, so
/// their wiring is read from the source, as `SharedPhotoTests` reads it.
final class SharePictureFallbackTests: XCTestCase {

    // MARK: - Every picture type, in the provider's order

    /// What `UTType` says is a picture, for the types used here.
    private let pictures: Set<String> = [
        "public.png", "public.jpeg", "public.heic", "public.tiff", "public.image",
        "com.adobe.raw-image", "com.apple.private.photos.thumbnail.standard",
    ]

    private func types(_ first: String, _ offered: [String]) -> [String] {
        SharedPhoto.typesToRead(first: first, offered: offered, isImage: pictures.contains)
    }

    /// The type chosen first, as before; then every other picture type the
    /// provider offers, in its order, each once. Not what is not a picture,
    /// nor a private type, the Photos app's thumbnails among them.
    func testEveryPictureTypeIsTriedInTheProvidersOrderAfterTheOneChosen() {
        XCTAssertEqual(types("public.png", ["public.png"]), ["public.png"])
        XCTAssertEqual(types("public.png", ["public.png", "public.url", "public.jpeg",
                                            "com.apple.uikit.image"]),
                       ["public.png", "public.jpeg"])
        XCTAssertEqual(types("public.jpeg", ["public.heic", "public.jpeg", "public.tiff"]),
                       ["public.jpeg", "public.heic", "public.tiff"],
                       "the JPEG first, as chosen; the rest in the provider's order")
        XCTAssertEqual(types("public.jpeg", ["public.tiff", "public.heic", "public.jpeg"]),
                       ["public.jpeg", "public.tiff", "public.heic"])
        XCTAssertEqual(types("public.image", ["public.png"]), ["public.image", "public.png"],
                       "a provider counted by what UIImage reads")
        XCTAssertEqual(types("public.jpeg", ["com.apple.private.photos.thumbnail.standard",
                                             "public.heic", "public.jpeg"]),
                       ["public.jpeg", "public.heic"], "never its thumbnail")
        XCTAssertEqual(types("public.png", ["public.png", "public.png", "public.jpeg",
                                            "public.jpeg"]),
                       ["public.png", "public.jpeg"], "each once")
        XCTAssertEqual(types("com.adobe.raw-image", ["com.adobe.raw-image"]),
                       ["com.adobe.raw-image"])
        XCTAssertEqual(types("public.png", []), ["public.png"])
    }

    // MARK: - The object, bounded

    /// Twelve bytes a pixel at the peak: four decoded, at three times, as
    /// every decoder nobody measured is taken.
    func testAnObjectsPeakIsTwelveBytesAPixel() {
        XCTAssertEqual(SharedPhoto.objectMostPixels, 9_000_000)
        XCTAssertEqual(SharedPhoto.objectPeak(width: 1000, height: 1000), 12_000_000)
        XCTAssertEqual(SharedPhoto.objectPeak(width: 2160, height: 1620), 41_990_400,
                       "his iPad's screen")
        XCTAssertEqual(SharedPhoto.objectPeak(width: 8000, height: 6000), 576_000_000)
        XCTAssertEqual(SharedPhoto.objectPeak(width: 0, height: 6000), 0)
    }

    /// Never more than 9 million pixels, whatever the memory says: a
    /// 48-megapixel object is left out with a terabyte to spare.
    func testAnObjectOverNineMillionPixelsIsNeverMadeAFile() {
        let plenty: Int64 = 1 << 40
        XCTAssertEqual(SharedPhoto.objectRefused(width: 8000, height: 6000, available: plenty),
                       .leftOut("an object of 48000000 pixels, more than 9000000"))
        XCTAssertEqual(SharedPhoto.objectRefused(width: 6000, height: 8000, available: plenty),
                       .leftOut("an object of 48000000 pixels, more than 9000000"))
        XCTAssertNil(SharedPhoto.objectRefused(width: 3000, height: 3000, available: plenty),
                     "9 million exactly")
        XCTAssertEqual(SharedPhoto.objectRefused(width: 3001, height: 3000, available: plenty),
                       .leftOut("an object of 9003000 pixels, more than 9000000"))
        XCTAssertEqual(SharedPhoto.objectRefused(width: 40_000, height: 40_000, available: nil),
                       .leftOut("an object of 1600000000 pixels, more than 9000000"))
    }

    /// Under the bound, three fifths of the memory left, or of the 80 MB
    /// assumed when the iPad does not say. A picture of his screen and of
    /// the test iPad's fits the assumed; the largest iPad screen needs
    /// more, and fits what an extension of 120 MB has.
    func testUnderTheBoundTheMemoryLeftDecides() {
        XCTAssertNil(SharedPhoto.objectRefused(width: 2160, height: 1620, available: nil),
                     "his iPad's screen, 42 MB of the 48 assumed")
        XCTAssertNil(SharedPhoto.objectRefused(width: 1620, height: 2160, available: nil))
        XCTAssertNil(SharedPhoto.objectRefused(width: 2388, height: 1668, available: nil),
                     "the test iPad's screen")
        XCTAssertNil(SharedPhoto.objectRefused(width: 1668, height: 2388, available: nil))
        XCTAssertEqual(SharedPhoto.objectRefused(width: 2752, height: 2064, available: nil),
                       .tooLargeForMemory(needs: 68_161_536, available: nil))
        XCTAssertNil(SharedPhoto.objectRefused(width: 2752, height: 2064, available: 120_000_000))
        XCTAssertEqual(SharedPhoto.objectRefused(width: 2160, height: 1620, available: 60_000_000),
                       .tooLargeForMemory(needs: 41_990_400, available: 60_000_000))
        XCTAssertNil(SharedPhoto.objectRefused(width: 1000, height: 1000, available: 20_000_000),
                     "its peak exactly three fifths")
        XCTAssertEqual(SharedPhoto.objectRefused(width: 1000, height: 1000, available: 19_999_999),
                       .tooLargeForMemory(needs: 12_000_000, available: 19_999_999))
        XCTAssertEqual(SharedPhoto.objectRefused(width: 0, height: 1620, available: nil),
                       .leftOut("an object with no size"))
        XCTAssertEqual(SharedPhoto.objectRefused(width: 2160, height: -1, available: nil),
                       .leftOut("an object with no size"))
    }

    /// One left out for the memory says what would have had to be left,
    /// more than what was, as a JPEG left out does.
    func testAnObjectLeftOutForTheMemorySaysWhatItNeeded() throws {
        var report = SharedPhoto.Report(offered: ["public.png"], read: "object", named: .none)
        report.unopened = ["public.png"]
        report.went = try XCTUnwrap(SharedPhoto.objectRefused(width: 2160, height: 1620,
                                                              available: 60_000_000))
        XCTAssertEqual(report.line,
                       "SHARE-PICTURE offered=public.png read=public.png,object name=none \"{0 chars}\""
                       + " way=left out, 70 MB needed at the least, 60 MB available bytes=0")
    }

    // MARK: - A PNG or a JPEG, named as Mail names one

    private let png = SharedPhoto.Way.whole(filenameExtension: "png", mimeType: "image/png")

    /// A PNG where the provider says it is one, as a picture of the screen
    /// is, or where it has a clear part; otherwise a JPEG. A JPEG offered
    /// ahead of the PNG is the provider's best, as for a file.
    func testAnObjectGoesAsAPNGWhereItIsOneOrHasAClearPart() {
        XCTAssertEqual(SharedPhoto.objectWay(offered: ["public.png"], hasAlpha: false), png)
        XCTAssertEqual(SharedPhoto.objectWay(offered: ["public.png"], hasAlpha: true), png)
        XCTAssertEqual(SharedPhoto.objectWay(offered: ["public.jpeg"], hasAlpha: true), png)
        XCTAssertEqual(SharedPhoto.objectWay(offered: [], hasAlpha: true), png)
        XCTAssertEqual(SharedPhoto.objectWay(offered: ["public.jpeg"], hasAlpha: false), .jpeg)
        XCTAssertEqual(SharedPhoto.objectWay(offered: ["public.image"], hasAlpha: false), .jpeg)
        XCTAssertEqual(SharedPhoto.objectWay(offered: [], hasAlpha: false), .jpeg)
        XCTAssertEqual(SharedPhoto.objectWay(offered: ["public.jpeg", "public.png"],
                                             hasAlpha: false), .jpeg)
        XCTAssertEqual(SharedPhoto.objectWay(offered: ["public.url", "public.png"],
                                             hasAlpha: false), png)
        XCTAssertEqual(SharedPhoto.objectWay(offered: ["public.heic"], hasAlpha: false), .jpeg)
    }

    /// Named as B-036 names a picture, by the way it goes: the sharing
    /// app's suggestion where it has one, never a file's, since an object
    /// has none; with no name, "image0.png" for a picture of the screen or
    /// one with a clear part, "image0.jpeg" for any other, counted on
    /// across the share.
    func testAnObjectIsNamedAsMailNamesAPictureWithNoName() {
        func name(_ suggested: String?, _ offered: [String], alpha: Bool = false,
                  _ number: Int) -> String {
            SharedPhoto.name(SharedPhoto.named(suggested: suggested, file: nil),
                             way: SharedPhoto.objectWay(offered: offered, hasAlpha: alpha),
                             number: number)
        }
        XCTAssertEqual(SharedPhoto.named(suggested: nil, file: nil), .none)
        XCTAssertEqual(SharedPhoto.named(suggested: "  ", file: nil), .none)
        XCTAssertEqual(SharedPhoto.named(suggested: ".png", file: nil), .none)
        XCTAssertEqual(name(nil, ["public.png"], 0), "image0.png")
        XCTAssertEqual(name(nil, ["public.png"], 1), "image1.png")
        XCTAssertEqual(name(nil, ["public.jpeg"], 0), "image0.jpeg")
        XCTAssertEqual(name(nil, [], alpha: true, 0), "image0.png", "a clear part")
        XCTAssertEqual(name("", ["public.image"], 2), "image2.jpeg")
        XCTAssertEqual(name("Markup.PNG", ["public.png"], 0), "Markup.png")
        XCTAssertEqual(name("Markup", ["public.jpeg"], 0), "Markup.jpg")
        XCTAssertEqual(name("IMG_0001.HEIC", ["public.heic"], 0), "IMG_0001.jpg")
    }

    /// What an object is written as, the MIME type it goes with and the
    /// extension of its name, all from the one way: a PNG, "image/png" and
    /// ".png"; or a JPEG, "image/jpeg" and ".jpeg". Never a PNG's bytes
    /// under a JPEG's type or name, nor the other way about.
    func testAnObjectsBytesTheirTypeAndItsNameComeFromTheOneWay() {
        XCTAssertTrue(SharedPhoto.objectFile(png).png)
        XCTAssertEqual(SharedPhoto.objectFile(png).mimeType, "image/png")
        XCTAssertFalse(SharedPhoto.objectFile(.jpeg).png)
        XCTAssertEqual(SharedPhoto.objectFile(.jpeg).mimeType, "image/jpeg")
        XCTAssertFalse(SharedPhoto.objectFile(.own).png)
        XCTAssertEqual(SharedPhoto.objectFile(.own).mimeType, "image/jpeg")
        let offers: [[String]] = [["public.png"], ["public.jpeg"], ["public.image"], [],
                                  ["public.jpeg", "public.png"], ["public.url", "public.png"],
                                  ["public.heic"]]
        var seen: Set<String> = []
        for offered in offers {
            for alpha in [false, true] {
                let way = SharedPhoto.objectWay(offered: offered, hasAlpha: alpha)
                let file = SharedPhoto.objectFile(way)
                let name = SharedPhoto.name(.none, way: way, number: 0)
                let said = "\(offered) alpha \(alpha)"
                XCTAssertEqual(file.mimeType, file.png ? "image/png" : "image/jpeg", said)
                XCTAssertEqual(name, file.png ? "image0.png" : "image0.jpeg", said)
                let suggested = SharedPhoto.name(.suggested("Markup"), way: way, number: 0)
                XCTAssertEqual(suggested, file.png ? "Markup.png" : "Markup.jpg", said)
                seen.insert(file.mimeType)
            }
        }
        XCTAssertEqual(seen, ["image/png", "image/jpeg"], "both ways met")
        XCTAssertEqual(SharedPhoto.objectFile(SharedPhoto.objectWay(offered: ["public.png"],
                                                                    hasAlpha: false)).png, true,
                       "a picture of the screen, a PNG")
        XCTAssertEqual(SharedPhoto.objectFile(SharedPhoto.objectWay(offered: ["public.jpeg"],
                                                                    hasAlpha: false)).png, false)
    }

    /// An object is written before its size is known, so the room is
    /// weighed on what was written. Larger than what is left of the
    /// letter's 25 MB, it is taken away again and its line says "no
    /// room", as a JPEG made here does; one ImageIO did not write says
    /// "not written". What was written is measured either way.
    func testAnObjectWrittenLargerThanTheRoomIsSaidToHaveNoRoom() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharePictureFallbackTests-\(UUID().uuidString)",
                                    isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var discarded: [String] = []
        let staging = ShareItems.Staging(
            write: { _, name in URL(fileURLWithPath: "/staged/\(name)") },
            copy: { _, name in URL(fileURLWithPath: "/staged/\(name)") },
            place: { name in
                let place = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
                return place.appendingPathComponent(name)
            },
            discard: { url in
                discarded.append(url.lastPathComponent)
                _ = try? FileManager.default.removeItem(at: url)
            })
        XCTAssertNotNil(staging.photo(Data(count: Int(ShareItems.Staging.budget) - 500),
                                      named: "IMG_0001.JPG"))
        XCTAssertEqual(staging.room, 500)
        func object(_ size: Int, writes: Bool = true) -> SharedItem? {
            staging.written(named: "image0.png", mimeType: "image/png", expected: 0,
                            unnamed: true) { url in
                writes && FileManager.default.createFile(atPath: url.path,
                                                         contents: Data(count: size))
            }
        }

        XCTAssertNil(object(900))
        XCTAssertEqual(staging.lastMeasured, 900, "what was written, measured")
        XCTAssertEqual(SharedPhoto.objectLeftOut(measured: staging.lastMeasured, room: staging.room),
                       .leftOut("no room"))
        XCTAssertEqual(discarded, ["image0.png"], "taken away again")
        var report = SharedPhoto.Report(offered: ["public.png"], read: "object", named: .none)
        report.unopened = ["public.png"]
        report.name = "image0.png"
        report.went = SharedPhoto.objectLeftOut(measured: staging.lastMeasured, room: staging.room)
        XCTAssertTrue(report.line.hasSuffix(" way=left out, no room bytes=0"), report.line)

        XCTAssertNil(object(900, writes: false))
        XCTAssertNil(staging.lastMeasured, "nothing written, nothing measured")
        XCTAssertEqual(SharedPhoto.objectLeftOut(measured: staging.lastMeasured, room: staging.room),
                       .leftOut("not written"))

        XCTAssertNil(object(0))
        XCTAssertEqual(staging.lastMeasured, 0)
        XCTAssertEqual(SharedPhoto.objectLeftOut(measured: staging.lastMeasured, room: staging.room),
                       .leftOut("not written"), "written empty")

        XCTAssertNotNil(object(500), "the room exactly")
        XCTAssertEqual(staging.lastMeasured, 500)
        XCTAssertEqual(staging.room, 0)
        XCTAssertEqual(SharedPhoto.objectLeftOut(measured: 500, room: 500), .leftOut("not written"))
        XCTAssertEqual(SharedPhoto.objectLeftOut(measured: 501, room: 500), .leftOut("no room"))
        XCTAssertEqual(SharedPhoto.objectLeftOut(measured: nil, room: 0), .leftOut("not written"))
    }

    /// Two from the editor in one share: "image0.png", then "image1.png",
    /// each written straight onto the disk where it is staged and counted
    /// as written, nothing through memory.
    func testTwoObjectsInAShareAreImage0AndImage1() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharePictureFallbackTests-\(UUID().uuidString)",
                                    isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var throughMemory = 0
        let staging = ShareItems.Staging(
            write: { _, name in throughMemory += 1; return URL(fileURLWithPath: "/staged/\(name)") },
            copy: { _, name in URL(fileURLWithPath: "/staged/\(name)") },
            place: { name in
                let place = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
                return place.appendingPathComponent(name)
            },
            discard: { url in _ = try? FileManager.default.removeItem(at: url) })
        var names: [String] = []
        for size in [700, 900] {
            let way = SharedPhoto.objectWay(offered: ["public.png"], hasAlpha: false)
            let name = SharedPhoto.name(SharedPhoto.named(suggested: nil, file: nil), way: way,
                                        number: staging.unnamed)
            let item = staging.written(named: name, mimeType: "image/png", expected: 0,
                                       unnamed: true) { url in
                FileManager.default.createFile(atPath: url.path, contents: Data(count: size))
            }
            guard case .file(let url, let filename, let mimeType, let staged) = try XCTUnwrap(item)
            else { return XCTFail("not a file") }
            XCTAssertEqual(url.lastPathComponent, name)
            XCTAssertEqual(filename, name)
            XCTAssertEqual(mimeType, "image/png")
            XCTAssertEqual(staged, Int64(size))
            names.append(filename)
        }
        XCTAssertEqual(names, ["image0.png", "image1.png"])
        XCTAssertEqual(staging.staged, 1_600)
        XCTAssertEqual(throughMemory, 0)
    }

    /// UIKit's turn as EXIF has it, every one of the eight, so a picture is
    /// never sent on its side: up 1, down 3, left 8, right 6, and mirrored
    /// 2, 4, 5, 7. Anything else is upright.
    func testTheOrientationTagIsUIKitsTurnAsEXIFHasIt() {
        let exif = (0...7).map { SharedPhoto.exifOrientation(imageOrientation: $0) }
        XCTAssertEqual(exif, [1, 3, 8, 6, 2, 4, 5, 7])
        XCTAssertEqual(SharedPhoto.exifOrientation(imageOrientation: 8), 1)
        XCTAssertEqual(SharedPhoto.exifOrientation(imageOrientation: -1), 1)
    }

    // MARK: - The log

    /// Every type tried is in its line, in the order tried, the last the
    /// one that decided: the object, the item, or a type not opened.
    func testTheLogSaysEveryTypeTriedAndHowTheObjectWent() {
        var report = SharedPhoto.Report(offered: ["public.png"], read: "object", named: .none)
        report.unopened = ["public.png"]
        report.name = "image0.png"
        report.went = .object(png: true, available: 140_400_000)
        report.bytes = 2_100_000
        XCTAssertEqual(report.line,
                       "SHARE-PICTURE offered=public.png read=public.png,object"
                       + " name=none \"image0.png\" way=PNG made of the object, 140 MB available"
                       + " bytes=2100000")

        var item = SharedPhoto.Report(offered: ["public.jpeg"], read: "item", named: .none)
        item.unopened = ["public.jpeg", "object"]
        item.name = "image0.jpeg"
        item.went = .object(png: false, available: nil)
        XCTAssertTrue(item.line.contains(" read=public.jpeg,object,item name=none \"image0.jpeg\""
                                         + " way=JPEG made of the object, memory unknown,"
                                         + " 80 MB assumed bytes=0"), item.line)

        var next = SharedPhoto.Report(offered: ["public.png", "public.jpeg"], read: "public.jpeg",
                                      named: .file("IMG_0775.PNG"))
        next.unopened = ["public.png"]
        next.inside = "public.png"
        next.name = "IMG_0775.PNG"
        next.went = .whole
        XCTAssertTrue(next.line.contains(" read=public.png,public.jpeg (public.png inside) name=file"),
                      next.line)

        var none = SharedPhoto.Report(offered: ["public.png"], read: "item", named: .none)
        none.unopened = ["public.png", "object"]
        XCTAssertTrue(none.line.hasSuffix(" read=public.png,object,item name=none \"{0 chars}\""
                                          + " way=left out, not opened bytes=0"), none.line)

        let first = SharedPhoto.Report(offered: ["public.jpeg"], read: "public.jpeg", named: .none)
        XCTAssertTrue(first.line.contains(" read=public.jpeg name="), "as before, read at once")
    }

    // MARK: - The lines kept when something is left out

    private var directory: String!

    override func setUp() {
        super.setUp()
        directory = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("SharePictureFallbackTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: directory,
                                                 withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(atPath: directory) }
        directory = nil
        super.tearDown()
    }

    private var left: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).sorted()
    }

    /// A picture left out, with no letter or with one: the log so far is
    /// written as a send's end writes it, tagged `left-out`, its
    /// `SHARE-PICTURE` line in it. Nothing when everything came.
    func testAPictureLeftOutLeavesItsLinesWhereACheckReadsThem() throws {
        let real = CaptureProbe.directory
        CaptureProbe.directory = directory
        defer { CaptureProbe.directory = real }
        let mark = "SHARE-PICTURE offered=public.png read=public.png,object,item mark=\(UUID())"
        Diagnostics.log(.note, mark)

        ShareItems.keepLog(for: nil, session: "everything")
        XCTAssertEqual(left, [], "nothing left out, nothing written")

        ShareItems.keepLog(for: .instead("The photo could not be attached."), session: "none")
        XCTAssertEqual(left, ["blackmail-send-none-left-out.txt"])
        let written = try String(contentsOfFile: (directory as NSString)
            .appendingPathComponent("blackmail-send-none-left-out.txt"), encoding: .utf8)
        XCTAssertTrue(written.contains(mark), "the transcript a send writes")

        ShareItems.keepLog(for: .line("1 photo could not be attached."), session: "some")
        XCTAssertEqual(left, ["blackmail-send-none-left-out.txt",
                              "blackmail-send-some-left-out.txt"])
        XCTAssertEqual(ShareItems.leftOutTag, "left-out")
    }

    /// Kept among the send's transcripts, the newest ten in all, as each
    /// send's end keeps them.
    func testTheNewestTenAreKeptWithTheSends() {
        let real = CaptureProbe.directory
        CaptureProbe.directory = directory
        defer { CaptureProbe.directory = real }
        for n in 1...12 {
            let path = (directory as NSString).appendingPathComponent("blackmail-send-\(n)-ok.txt")
            FileManager.default.createFile(atPath: path, contents: Data("x".utf8))
            let when = Date(timeIntervalSinceNow: -1000 + Double(n))
            try? FileManager.default.setAttributes([.modificationDate: when], ofItemAtPath: path)
        }
        ShareItems.keepLog(for: .instead("The photos could not be attached."), session: "newest")
        XCTAssertEqual(left.count, CaptureProbe.kept)
        XCTAssertTrue(left.contains("blackmail-send-newest-left-out.txt"))
        XCTAssertFalse(left.contains("blackmail-send-1-ok.txt"))
        XCTAssertFalse(left.contains("blackmail-send-2-ok.txt"))
        XCTAssertFalse(left.contains("blackmail-send-3-ok.txt"))
    }

    /// Under its own time by default, never the session of the last send,
    /// which `CaptureProbe.session` holds.
    func testItIsWrittenUnderItsOwnTime() {
        let real = CaptureProbe.directory
        CaptureProbe.directory = directory
        defer { CaptureProbe.directory = real }
        let before = Int(Date().timeIntervalSince1970)
        ShareItems.keepLog(for: .instead("The photo could not be attached."))
        let after = Int(Date().timeIntervalSince1970)
        XCTAssertEqual(left.count, 1)
        let stamp = left.first.flatMap { name -> Int? in
            Int(name.dropFirst("blackmail-send-".count).dropLast("-left-out.txt".count))
        }
        XCTAssertNotNil(stamp, "\(left)")
        if let stamp { XCTAssertTrue((before...after).contains(stamp), "\(stamp)") }
    }

    // MARK: - The iPad's part, read from its source

    /// The share code's source, comment lines out and runs of white space
    /// as one space, as `SharedPhotoTests` reads it.
    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/Share/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
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

    private func count(_ step: String, in code: String) -> Int {
        code.components(separatedBy: step).count - 1
    }

    private func part(of code: String, from start: String, to end: String) throws -> String {
        let begun = try XCTUnwrap(code.range(of: start), start)
        let ended = try XCTUnwrap(code.range(of: end, range: begun.upperBound..<code.endIndex), end)
        return String(code[begun.lowerBound..<ended.lowerBound])
    }

    /// Each type, by `UTType`'s word that it is a picture, as its file and
    /// then its bytes; only a type that gave nothing ImageIO opens goes on
    /// to the next, carrying what was tried; none left, the object. A
    /// picture opened and not made one, or left out for the room or the
    /// memory, is answered there.
    func testEachTypeIsReadAsItsFileThenItsBytesThenTheNext() throws {
        let code = try source("SharedPhotoImageIO.swift")
        inOrder(["static func picture(_ provider: NSItemProvider, type: String, staging: Staging,",
                 "let types = SharedPhoto.typesToRead(first: type, offered: provider.registeredTypeIdentifiers,",
                 "isImage: { UTType($0)?.conforms(to: .image) == true })",
                 "picture(provider, as: types[...], unopened: [], staging: staging, loading: loading, done: done)",
                 "private static func picture(_ provider: NSItemProvider, as types: ArraySlice<String>,",
                 "guard let type = types.first else {",
                 "return object(provider, unopened: unopened, staging: staging, loading: loading, done: done)",
                 "provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in",
                 "var report = SharedPhoto.Report(offered: offered, read: type, named: named)",
                 "report.unopened = unopened",
                 "switch fromFile {",
                 "case .staged(let item): return finish(item, report, done)",
                 "case .undecodable: return finish(nil, report, done)",
                 "case .unopened: break",
                 "provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in",
                 "switch fromBytes {",
                 "case .staged(let item): finish(item, fromItsBytes, done)",
                 "case .undecodable: finish(nil, fromItsBytes, done)",
                 "case .unopened:",
                 "picture(provider, as: types.dropFirst(), unopened: unopened + [type], staging: staging, loading: loading, done: done)"],
                in: code)
        XCTAssertEqual(count("types.dropFirst()", in: code), 1, "on to the next only there")
        XCTAssertEqual(count("object(provider,", in: code), 1)
        XCTAssertEqual(count("SharedPhoto.typesToRead(", in: code), 1)
    }

    /// What ImageIO opens and finds no picture in is not opened (B-090):
    /// it opens bytes that are no picture at all, a keyed archive or words,
    /// and finds nothing in them, with no type and a count of nought. So a
    /// file with no picture in it goes on to its bytes, and bytes with none
    /// in them to the next type and then the object, as a file not given
    /// does; never left out there as a picture that could not be made one.
    func testAFileOrBytesWithNoPictureInThemGoOnToTheNextWay() throws {
        let code = try source("SharedPhotoImageIO.swift")
        let file = try part(of: code, from: "private static func read(file url: URL?,",
                            to: "private static func read(bytes data: Data?,")
        inOrder(["guard let url,",
                 "let source = CGImageSourceCreateWithURL(url as CFURL, SharedPhoto.reading),",
                 "CGImageSourceGetCount(source) > 0",
                 "else { return .unopened }",
                 "return stage(source,"],
                in: file)
        let bytes = try part(of: code, from: "private static func read(bytes data: Data?,",
                             to: "static func picture(item: NSSecureCoding?,")
        inOrder(["guard let data,",
                 "let source = CGImageSourceCreateWithData(data as CFData, SharedPhoto.reading),",
                 "CGImageSourceGetCount(source) > 0",
                 "else { return .unopened }",
                 "return stage(source,"],
                in: bytes)
        // Every way a picture is read goes through those two.
        XCTAssertEqual(count("CGImageSourceCreateWithURL(", in: code), 2, "and the read back")
        XCTAssertEqual(count("CGImageSourceCreateWithData(", in: code), 1)
        XCTAssertEqual(count("return stage(source,", in: code), 2)
        XCTAssertEqual(count("read(file: url,", in: code), 2, "a type's file, and the item's")
        XCTAssertEqual(count("read(bytes: data,", in: code), 2, "a type's bytes, and the item's")
        // A picture in it that no picture could be made of is answered in
        // `stage`, as before.
        let stage = try part(of: code, from: "private static func stage(",
                             to: "extension SharedPhoto {")
        inOrder(["guard index < CGImageSourceGetCount(source) else {",
                 "report.went = .leftOut(\"no picture at its index\")",
                 "return .undecodable"],
                in: stage)
        XCTAssertEqual(count("return .unopened", in: stage), 0)
    }

    /// The provider's own item, where it is a file on this iPad or bytes
    /// and not a `UIImage`: read by ImageIO as a type's file or bytes are,
    /// the file named by its own name; anything else, a web address or
    /// nothing, left out with the line it has.
    func testAnItemThatIsAFileOrBytesIsReadAsAFileOrBytesAre() throws {
        let code = try source("SharedPhotoImageIO.swift")
        let item = try part(of: code, from: "static func picture(item: NSSecureCoding?,",
                            to: "static func finish(")
        inOrder(["static func picture(item: NSSecureCoding?, type: String, suggested: String?, staging: Staging, report: inout SharedPhoto.Report) -> SharedItem? {",
                 "let fromItem: Picture",
                 "if let url = item as? URL, url.isFileURL {",
                 "let named = SharedPhoto.named(suggested: suggested, file: url.lastPathComponent)",
                 "report.named = named",
                 "fromItem = read(file: url, type: type, named: named, staging: staging, report: &report)",
                 "} else if let data = item as? Data {",
                 "fromItem = read(bytes: data, type: type, named: report.named, staging: staging, report: &report)",
                 "} else {",
                 "return nil",
                 "guard case .staged(let staged) = fromItem else { return nil }",
                 "return staged"],
                in: item)
        for never in ["Diagnostics.log(", "finish(", "done(", "UIImage", "CGImageSourceCreate"] {
            XCTAssertFalse(item.contains(never), never)
        }
        // In the item's callback, where the file lasts, before any
        // `UIImage` is made of it, and its line through `finish`.
        let object = try source("SharedPhotoObject.swift")
        inOrder(["provider.loadItem(forTypeIdentifier: type, options: nil) { object, _ in",
                 "guard let image = object as? UIImage else {",
                 "let staged = picture(item: object, type: type, suggested: suggested, staging: staging, report: &report)",
                 "return finish(staged, report, done)",
                 "}",
                 "made(image,"],
                in: object)
        XCTAssertEqual(count("picture(item:", in: object), 1)
        XCTAssertEqual(count("picture(item:", in: code), 1, "its one definition")
    }

    /// The object: a `UIImage` as `UIImage` reads it, or the provider's own
    /// item where that made none, each made a file in its own pool; its
    /// size checked against the bound and the memory read right before,
    /// and only then a PNG or a JPEG chosen, named, and written straight
    /// onto the disk where it is staged. Never `pngData`, `jpegData` or a
    /// drawing; the only properties written the orientation and the
    /// JPEG's quality, so no location can go.
    func testTheObjectIsBoundedBeforeItIsDecodedAndWrittenStraightOntoTheDisk() throws {
        let code = try source("SharedPhotoObject.swift")
        inOrder(["static func object(_ provider: NSItemProvider, unopened: [String], staging: Staging,",
                 "let named = SharedPhoto.named(suggested: provider.suggestedName, file: nil)",
                 "guard provider.canLoadObject(ofClass: UIImage.self) else {",
                 "return item(provider, unopened: unopened, staging: staging, loading: loading, done: done)",
                 "provider.loadObject(ofClass: UIImage.self) { object, _ in",
                 "guard let image = object as? UIImage else {",
                 "return item(provider, unopened: unopened + [\"object\"], staging: staging,",
                 "var report = SharedPhoto.Report(offered: offered, read: \"object\", named: named)",
                 "report.unopened = unopened",
                 "let staged = autoreleasepool {",
                 "made(image, named: named, offered: offered, staging: staging, report: &report)",
                 "finish(staged, report, done)",
                 "private static func item(",
                 "let suggested = provider.suggestedName",
                 "let named = SharedPhoto.named(suggested: suggested, file: nil)",
                 "let type = unopened.first ?? UTType.image.identifier",
                 "provider.loadItem(forTypeIdentifier: type, options: nil) { object, _ in",
                 "var report = SharedPhoto.Report(offered: offered, read: \"item\", named: named)",
                 "report.unopened = unopened",
                 "guard let image = object as? UIImage else {",
                 "let staged = picture(item: object, type: type, suggested: suggested, staging: staging, report: &report)",
                 "return finish(staged, report, done)",
                 "let staged = autoreleasepool {",
                 "made(image, named: named, offered: offered, staging: staging, report: &report)",
                 "finish(staged, report, done)"],
                in: code)
        let made = try part(of: code, from: "private static func made(", to: "extension SharedPhoto {")
        inOrder(["guard let picture = image.cgImage else {",
                 "report.went = .leftOut(\"no picture in the object\")",
                 "return nil",
                 "let available = SharedPhoto.availableMemory()",
                 "if let refused = SharedPhoto.objectRefused(width: picture.width, height: picture.height, available: available) {",
                 "report.went = refused",
                 "return nil",
                 "switch picture.alphaInfo {",
                 "case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false",
                 "default: hasAlpha = true",
                 "let way = SharedPhoto.objectWay(offered: offered, hasAlpha: hasAlpha)",
                 "let file = SharedPhoto.objectFile(way)",
                 "let name = SharedPhoto.name(named, way: way, number: staging.unnamed)",
                 "report.went = .object(png: file.png, available: available)",
                 "let orientation = SharedPhoto.exifOrientation(imageOrientation: image.imageOrientation.rawValue)",
                 "let item = staging.written(named: name, mimeType: file.mimeType, expected: 0, unnamed: named == .none) { url in",
                 "SharedPhoto.write(picture, png: file.png, orientation: orientation, to: url)",
                 "if item == nil {",
                 "report.went = SharedPhoto.objectLeftOut(measured: staging.lastMeasured, room: staging.room)",
                 "return item"],
                in: made)
        // The bytes, their MIME type and the name all from the one way:
        // nothing in `made` says PNG or JPEG of its own (`objectFile`).
        XCTAssertEqual(count("SharedPhoto.objectFile(way)", in: made), 1)
        XCTAssertEqual(count("file.png", in: made), 2)
        XCTAssertEqual(count("file.mimeType", in: made), 1)
        XCTAssertEqual(count("way: way", in: made), 1)
        for never in ["\"image/", "way != ", "way == ", "case .whole", "png: png",
                      ".leftOut(\"not written\")", ".leftOut(\"no room\")"] {
            XCTAssertFalse(made.contains(never), never)
        }
        XCTAssertEqual(count("staging.written(", in: code), 1)
        XCTAssertEqual(count("staging.photo(", in: code), 0, "nothing through memory")
        XCTAssertEqual(count("staging.file(", in: code), 0)
        XCTAssertEqual(count("SharedPhoto.write(", in: code), 1, "only once it is allowed")
        XCTAssertEqual(count("made(image,", in: code), 2)

        let write = try part(of: code, from: "static func write(", to: "#endif")
        inOrder(["let type = png ? UTType.png.identifier : UTType.jpeg.identifier",
                 "guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else { return false }",
                 "var written: [CFString: Any] = [:]",
                 "if orientation != 1 { written[kCGImagePropertyOrientation] = orientation }",
                 "if !png { written[kCGImageDestinationLossyCompressionQuality] = quality }",
                 "CGImageDestinationAddImage(destination, picture, written as CFDictionary)",
                 "return CGImageDestinationFinalize(destination)"],
                in: write)
        XCTAssertEqual(count("written[", in: code), 2, "the orientation and the quality alone")
        for never in ["pngData(", "jpegData(", "UIGraphics", "draw(", "UIImage(",
                      "CGImageDestinationAddImageFromSource", "kCGImageDestinationMetadata",
                      "CGImageDestinationCreateWithData", "kCGImagePropertyGPSDictionary"] {
            XCTAssertFalse(code.contains(never), never)
        }
    }

    /// The `UIImage` only there: no other file of the share code loads an
    /// object or makes a picture of one, and only one of each in that.
    func testTheObjectIsTheOnlyUIImageInTheShareCode() throws {
        let object = try source("SharedPhotoObject.swift")
        XCTAssertEqual(count("loadObject(", in: object), 1)
        XCTAssertEqual(count("loadItem(", in: object), 1)
        for file in ["ShareViewController.swift", "SharedPhotoImageIO.swift", "ShareItems.swift",
                     "SharedPhoto.swift"] {
            let code = try source(file)
            XCTAssertEqual(count("loadObject(", in: code), 0, file)
            XCTAssertEqual(count(".cgImage", in: code), 0, file)
            XCTAssertEqual(count("as? UIImage", in: code), 0, file)
        }
        XCTAssertEqual(count("loadItem(", in: try source("SharedPhotoImageIO.swift")), 0)
    }

    /// The sheet writes the lines out once the share's pictures are read,
    /// with what it will say of them, after it is told.
    func testTheSheetKeepsTheLogWhenItSaysSomethingWasLeftOut() throws {
        let sheet = try source("ShareViewController.swift")
        inOrder(["oneAtATime(loads) { items in",
                 "let leftOut = tally.leftOut",
                 "Task { @MainActor in completion(items, leftOut) }",
                 "keepLog(for: leftOut)",
                 "}"],
                in: sheet)
        XCTAssertEqual(count("keepLog(", in: sheet), 1)
        let items = try source("ShareItems.swift")
        inOrder(["static func keepLog(for leftOut: LeftOut?,",
                 "session: String = String(Int(Date().timeIntervalSince1970))) {",
                 "guard leftOut != nil else { return }",
                 "CaptureProbe.dumpTranscript(leftOutTag, session: session)"],
                in: items)
    }
}
