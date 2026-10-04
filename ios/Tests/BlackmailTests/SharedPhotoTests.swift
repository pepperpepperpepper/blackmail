import XCTest
@testable import Blackmail

/// A picture shared into the extension (B-036, 2026-10-04): read from its
/// file and made a JPEG of at most 4096 px, asked of ImageIO at a size its
/// decoder reaches by halving, so a large photo is decoded at a half, a
/// quarter or an eighth, and no longer gets the extension killed and the
/// sheet gone. And a picture that could not be attached said so. The rules
/// here; ImageIO and UIKit doing them are on the iPad only, so their wiring
/// is read from the source, as the screens' is.
final class SharedPhotoTests: XCTestCase {

    // MARK: - Its size

    private func size(_ width: Int, _ height: Int) -> SharedPhoto.Size? {
        SharedPhoto.size(width: width, height: height)
    }

    private func pixels(_ width: Int, _ height: Int) -> SharedPhoto.Size {
        SharedPhoto.Size(width: width, height: height)
    }

    /// Larger than 4096, the longest side at a half, a quarter or an
    /// eighth, the first that is no more than 4096, whichever way up, and
    /// the other in proportion: a 48-megapixel photo, a 24-megapixel one, a
    /// panorama, a square. A picture a little over the bound goes at half
    /// of it; a half exactly 4096 goes at 4096; an odd side's half is
    /// rounded down.
    func testALargePhotoGoesAtTheHalfQuarterOrEighthItIsDecodedAt() {
        XCTAssertEqual(size(8064, 6048), pixels(4032, 3024))
        XCTAssertEqual(size(6048, 8064), pixels(3024, 4032))
        XCTAssertEqual(size(5712, 4284), pixels(2856, 2142))
        XCTAssertEqual(size(4284, 5712), pixels(2142, 2856))
        XCTAssertEqual(size(16_000, 4_000), pixels(4000, 1000))
        XCTAssertEqual(size(4_000, 16_000), pixels(1000, 4000))
        XCTAssertEqual(size(9000, 9000), pixels(2250, 2250))
        XCTAssertEqual(size(4097, 3000), pixels(2048, 1500))
        XCTAssertEqual(size(8192, 8192), pixels(4096, 4096))
        XCTAssertEqual(size(8193, 6000), pixels(4096, 3000))
        XCTAssertEqual(size(8194, 6000), pixels(2048, 1500))
        XCTAssertEqual(size(8064, 6048)?.longest, 4032)
    }

    /// The factor a picture is read at: the smallest of 1, 2, 4 and 8 that
    /// brings its longest side to 4096 or less, in whole pixels rounded
    /// down; past an eighth, an eighth all the same.
    func testTheFactorIsTheSmallestThatBringsItTo4096() {
        XCTAssertEqual(SharedPhoto.factors, [1, 2, 4, 8])
        let expected = [(1, 1), (4032, 1), (4096, 1), (4097, 2), (5712, 2), (8064, 2),
                        (8193, 2), (8194, 4), (16_000, 4), (16_387, 4), (16_388, 8),
                        (32_775, 8), (32_776, 8), (100_000, 8)]
        for (longest, factor) in expected {
            XCTAssertEqual(SharedPhoto.factor(longest: longest), factor, "\(longest)")
        }
    }

    /// Past an eighth, over 32768 px, the longest side 4096: the decoder
    /// reads the eighth, larger, and it is made smaller from that.
    func testPastAnEighthItGoesAt4096() {
        XCTAssertEqual(size(32_775, 8_000), pixels(4096, 1000), "an eighth, rounded down")
        XCTAssertEqual(size(32_776, 8_000), pixels(4096, 1000), "past it")
        XCTAssertEqual(size(40_000, 10_000), pixels(4096, 1024))
        XCTAssertEqual(size(10_000, 40_000), pixels(1024, 4096))
        XCTAssertEqual(size(100_000, 100_000), pixels(4096, 4096))
    }

    /// Every longest side from 1 to 40000 px. What is asked is never more
    /// than the decoder's own share of it, rounded up as a decoder rounds,
    /// so it never has to decode at the factor below; never more than 4096;
    /// up to 32775 px exactly its share, so the decoder holds no more than
    /// 4097 px of it; and no smaller factor would have done.
    func testWhatIsAskedIsAlwaysReachedByHalving() {
        var unreached: [Int] = [], tooLarge: [Int] = [], notItsShare: [Int] = []
        var notSmallest: [Int] = []
        for longest in 1...40_000 {
            let factor = SharedPhoto.factor(longest: longest)
            guard let asked = size(longest, 1)?.longest else { return XCTFail("\(longest)") }
            let decoded = (longest + factor - 1) / factor
            if asked > decoded { unreached.append(longest) }
            if asked > 4096 { tooLarge.append(longest) }
            if longest <= 32_775, asked != longest / factor || decoded > 4097 {
                notItsShare.append(longest)
            }
            if factor > 1, longest / (factor / 2) <= 4096 { notSmallest.append(longest) }
        }
        XCTAssertTrue(unreached.isEmpty, "\(unreached.count), first \(unreached.prefix(3))")
        XCTAssertTrue(tooLarge.isEmpty, "\(tooLarge.count), first \(tooLarge.prefix(3))")
        XCTAssertTrue(notItsShare.isEmpty, "\(notItsShare.count), first \(notItsShare.prefix(3))")
        XCTAssertTrue(notSmallest.isEmpty, "\(notSmallest.count), first \(notSmallest.prefix(3))")
    }

    /// A photo from his iPad's camera, 4032 px, and anything else no larger
    /// than 4096, goes at its own size: never made bigger.
    func testASmallerPictureIsNeverMadeLarger() {
        XCTAssertEqual(size(4032, 3024), pixels(4032, 3024))
        XCTAssertEqual(size(3024, 4032), pixels(3024, 4032))
        XCTAssertEqual(size(4096, 4096), pixels(4096, 4096))
        XCTAssertEqual(size(4096, 1), pixels(4096, 1))
        XCTAssertEqual(size(1000, 800), pixels(1000, 800))
        XCTAssertEqual(size(1, 1), pixels(1, 1))
    }

    /// The shorter side to the nearest pixel, a half up, and never less
    /// than one; a picture that does not say its size has none.
    func testTheShorterSideIsRoundedToTheNearestPixelAndNeverNothing() {
        XCTAssertEqual(size(8192, 4097), pixels(4096, 2049), "2048.5 goes up")
        XCTAssertEqual(size(8192, 4095), pixels(4096, 2048), "2047.5 goes up")
        XCTAssertEqual(size(12_288, 4_099), pixels(3072, 1025), "1024.75 to the nearest")
        XCTAssertEqual(size(12_288, 4_097), pixels(3072, 1024), "1024.25 to the nearest")
        XCTAssertEqual(size(30_000, 10), pixels(3750, 1), "1.25")
        XCTAssertEqual(size(30_000, 3), pixels(3750, 1), "0.375 is still one pixel")
        XCTAssertEqual(size(50_000, 5), pixels(4096, 1), "0.41 is still one pixel")
        XCTAssertNil(size(0, 3024))
        XCTAssertNil(size(4032, 0))
        XCTAssertNil(size(-1, 10))
    }

    // MARK: - Which of what is offered

    /// The original, first of the still pictures offered: Photos' HEIC
    /// rather than the JPEG it adds, the first of anything ahead of its
    /// private thumbnails; a RAW photo only when nothing else is offered;
    /// any picture at all last.
    func testTheOriginalIsReadAheadOfACopy() {
        XCTAssertEqual(SharedPhoto.fileType(offered: ["public.heic", "public.jpeg"]),
                       "public.heic")
        XCTAssertEqual(SharedPhoto.fileType(offered: ["public.jpeg", "public.heic"]),
                       "public.jpeg")
        XCTAssertEqual(SharedPhoto.fileType(offered: ["com.apple.private.photos.thumbnail.standard",
                                                      "com.apple.live-photo-bundle",
                                                      "public.heic"]),
                       "public.heic")
        XCTAssertEqual(SharedPhoto.fileType(offered: ["com.adobe.raw-image", "public.heic"]),
                       "public.heic")
        XCTAssertEqual(SharedPhoto.fileType(offered: ["com.adobe.raw-image"]),
                       "com.adobe.raw-image")
        XCTAssertEqual(SharedPhoto.fileType(offered: ["public.image", "public.raw-image-x"]),
                       "public.image")
        XCTAssertEqual(SharedPhoto.fileType(offered: ["public.url", "public.png"]), "public.png")
        XCTAssertEqual(SharedPhoto.fileType(offered: ["com.compuserve.gif"]),
                       "com.compuserve.gif")
        for type in ["public.jpeg", "public.png", "public.tiff", "org.webmproject.webp",
                     "public.heif", "public.avif"] {
            XCTAssertEqual(SharedPhoto.fileType(offered: [type]), type)
        }
    }

    /// A page, words, a document, a video, a drawing ImageIO cannot read:
    /// none is read as a picture, and each goes on as it did.
    func testWhatIsNotAPictureIsNotReadAsOne() {
        for offered in [["public.url"], ["public.url", "public.plain-text"],
                        ["public.plain-text"], ["com.adobe.pdf"],
                        ["com.apple.quicktime-movie"], ["public.mpeg-4"],
                        ["public.svg-image"], ["public.file-url"], []] {
            XCTAssertNil(SharedPhoto.fileType(offered: offered), "\(offered)")
        }
    }

    // MARK: - Whole or a JPEG

    private let gif = SharedPhoto.Way.whole(filenameExtension: "gif", mimeType: "image/gif")
    private let png = SharedPhoto.Way.whole(filenameExtension: "png", mimeType: "image/png")

    /// A GIF or a PNG goes as the file it is while it is no larger than a
    /// fifth of the letter, fits in what is left of it, and says nothing of
    /// where it was; past any of those it is made a JPEG. Every other
    /// picture is made a JPEG, however small, a camera's JPEG included.
    func testAGIFOrAPNGGoesWholeOnlyWhenSmallFittingAndSilentOnWhere() {
        let most = SharedPhoto.wholeAtMost
        let room = ShareItems.Staging.budget
        func way(_ type: String, _ size: Int64, room: Int64 = room,
                 located: Bool = false) -> SharedPhoto.Way {
            SharedPhoto.way(type: type, size: size, room: room, carriesLocation: located)
        }

        XCTAssertEqual(way("com.compuserve.gif", 2_000_000), gif)
        XCTAssertEqual(way("public.png", 1_500_000), png)
        XCTAssertEqual(way("com.compuserve.gif", most), gif, "exactly the bound")
        XCTAssertEqual(way("com.compuserve.gif", most + 1), .jpeg)
        XCTAssertEqual(way("public.png", most + 1), .jpeg)
        XCTAssertEqual(way("public.png", 1_500_000, room: 1_499_999), .jpeg)
        XCTAssertEqual(way("public.png", 1_500_000, room: 1_500_000), png, "exactly the room")
        XCTAssertEqual(way("public.png", 1_500_000, located: true), .jpeg)
        XCTAssertEqual(way("com.compuserve.gif", 1_500_000, located: true), .jpeg)
        XCTAssertEqual(way("public.png", 0), .jpeg, "a size it would not say")

        for type in ["public.jpeg", "public.heic", "public.tiff", "com.adobe.raw-image",
                     "public.image"] {
            XCTAssertEqual(way(type, 200_000), .jpeg, type)
        }
    }

    /// Five pictures kept whole always fit in a letter together.
    func testFiveKeptWholeFitTogether() {
        XCTAssertEqual(SharedPhoto.wholeAtMost, 5_000_000)
        XCTAssertLessThanOrEqual(SharedPhoto.wholeAtMost * 5, ShareItems.Staging.budget)
    }

    // MARK: - Its name

    /// The sharing app's suggested name without the extension it came
    /// with, and with the one it goes with; "Photo" without one.
    func testAPictureIsNamedAsSuggestedWithTheExtensionItGoesWith() {
        func name(_ suggested: String?, _ way: SharedPhoto.Way = .jpeg) -> String {
            SharedPhoto.name(suggested: suggested, way: way)
        }
        XCTAssertEqual(name("IMG_0412"), "IMG_0412.jpg")
        XCTAssertEqual(name("IMG_0412.HEIC"), "IMG_0412.jpg")
        XCTAssertEqual(name("IMG_0412.jpeg"), "IMG_0412.jpg")
        XCTAssertEqual(name("Garden.png"), "Garden.jpg")
        XCTAssertEqual(name(nil), "Photo.jpg")
        XCTAssertEqual(name(""), "Photo.jpg")
        XCTAssertEqual(name("  "), "Photo.jpg")
        XCTAssertEqual(name(".heic"), "Photo.jpg")
        XCTAssertEqual(name("Mr. Brown"), "Mr. Brown.jpg", "not a picture's extension")
        XCTAssertEqual(name("Sunday 3.10"), "Sunday 3.10.jpg")
        XCTAssertEqual(name("Dancing cat.gif", gif), "Dancing cat.gif")
        XCTAssertEqual(name("Dancing cat", gif), "Dancing cat.gif")
        XCTAssertEqual(name("Screenshot 2026-10-04 at 10.12.PNG", png),
                       "Screenshot 2026-10-04 at 10.12.png")
        XCTAssertEqual(name(nil, png), "Photo.png")
    }

    // MARK: - What goes with it

    /// What ImageIO reads out of a photo from an iPad's camera, its keys as
    /// ImageIO names them, the place made up.
    private let cameraPhoto: [String: Any] = [
        "PixelWidth": 4032, "PixelHeight": 3024, "Orientation": 6, "Depth": 8,
        "ColorModel": "RGB", "ProfileName": "Display P3", "DPIWidth": 72, "DPIHeight": 72,
        "PrimaryImage": true,
        "{Exif}": [
            "DateTimeOriginal": "2026:09:20 14:03:11",
            "OffsetTimeOriginal": "-04:00",
            "DateTimeDigitized": "2026:09:20 14:03:11",
            "OffsetTime": "-04:00",
            "LensMake": "Apple",
            "LensModel": "iPad back camera 3.3mm f/2.4",
            "SubjectArea": [2015, 1511, 2217, 1330],
            "PixelXDimension": 4032,
            "PixelYDimension": 3024,
        ] as [String: Any],
        "{GPS}": [
            "Latitude": 12.3456, "LatitudeRef": "N",
            "Longitude": 65.4321, "LongitudeRef": "W",
            "Altitude": 21.5, "Speed": 0, "ImgDirection": 181.2,
        ] as [String: Any],
        "{TIFF}": [
            "Make": "Apple", "Model": "iPad", "Software": "17.6.1",
            "Orientation": 6, "DateTime": "2026:09:20 14:03:11",
            "HostComputer": "iPad",
        ] as [String: Any],
        "{IPTC}": ["City": "Nowhere", "Country/PrimaryLocationName": "Elsewhere"] as [String: Any],
        "{MakerApple}": ["1": 14, "8": [0.1, -0.9, 0.2]] as [String: Any],
        "{HEIF}": ["CameraExtrinsics": ["Position": [0, 0, 0]]] as [String: Any],
    ]

    /// Only the moment it was taken goes, with its offset from UTC: no
    /// location, no orientation (the picture is turned upright as it is
    /// made), no camera, nothing of Apple's.
    func testOnlyTheMomentItWasTakenGoes() {
        let kept = SharedPhoto.kept(cameraPhoto)
        XCTAssertEqual(Set(kept.keys), ["{Exif}"])
        XCTAssertEqual(kept["{Exif}"] as? [String: String],
                       ["DateTimeOriginal": "2026:09:20 14:03:11", "OffsetTimeOriginal": "-04:00"])
        for gone in ["{GPS}", "{IPTC}", "Orientation", "{TIFF}", "{MakerApple}", "{HEIF}",
                     "ProfileName", "PixelWidth"] {
            XCTAssertNil(kept[gone], gone)
        }
    }

    /// A picture that says nothing of when it was taken goes with nothing
    /// at all; a list of what may go keeps out what it does not name.
    func testAPictureWithoutItsMomentGoesWithNothing() {
        XCTAssertTrue(SharedPhoto.kept([:]).isEmpty)
        XCTAssertTrue(SharedPhoto.kept(["{GPS}": ["Latitude": 12.3456] as [String: Any],
                                        "Orientation": 3]).isEmpty)
        XCTAssertTrue(SharedPhoto.kept(["{Exif}": ["LensMake": "Apple"] as [String: Any]]).isEmpty)
        XCTAssertTrue(SharedPhoto.kept(["{Exif}": ["GPSLatitude": 12.3456,
                                                   "SomethingNew": "x"] as [String: Any]]).isEmpty)
    }

    /// A GPS position or a place's name is a location; a screenshot's
    /// metadata, and a GIF's, are not.
    func testALocationIsFoundWhereverTheFileKeepsIt() {
        XCTAssertTrue(SharedPhoto.carriesLocation(cameraPhoto))
        XCTAssertTrue(SharedPhoto.carriesLocation(["{GPS}": ["Latitude": 12.3456] as [String: Any]]))
        XCTAssertTrue(SharedPhoto.carriesLocation(["{GPS}": [String: Any]()]))
        XCTAssertTrue(SharedPhoto.carriesLocation(["{IPTC}": ["City": "Nowhere"] as [String: Any]]))
        XCTAssertFalse(SharedPhoto.carriesLocation([
            "PixelWidth": 2732, "PixelHeight": 2048, "ProfileName": "Display P3",
            "{Exif}": ["UserComment": "Screenshot"] as [String: Any],
            "{PNG}": ["InterlaceType": 0] as [String: Any],
        ]))
        XCTAssertFalse(SharedPhoto.carriesLocation([
            "{GIF}": ["HasGlobalColorMap": true, "LoopCount": 0] as [String: Any],
        ]))
        XCTAssertEqual(SharedPhoto.locationPaths, ["exif:GPSLatitude", "exif:GPSLongitude"])
    }

    // MARK: - Staged

    /// Staged nowhere, as `ShareItemsTests` stages.
    private final class Disk {
        var written: [String: Data] = [:]
        func write(_ data: Data, _ filename: String) throws -> URL {
            written[filename] = data
            return URL(fileURLWithPath: "/staged/\(filename)")
        }
        func copy(_ source: URL, _ filename: String) throws -> URL {
            URL(fileURLWithPath: "/staged/\(filename)")
        }
    }

    /// A picture's bytes kept whole go as their own type, and the room
    /// left shrinks by what each staged.
    func testBytesKeptWholeGoAsTheirOwnTypeAndTheRoomShrinks() {
        let disk = Disk()
        let staging = ShareItems.Staging(write: disk.write, copy: disk.copy)
        XCTAssertEqual(staging.room, ShareItems.Staging.budget)

        let gif = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
        XCTAssertEqual(staging.photo(gif, named: "Dancing cat.gif", mimeType: "image/gif"),
                       .file(URL(fileURLWithPath: "/staged/Dancing cat.gif"),
                             filename: "Dancing cat.gif", mimeType: "image/gif", size: 6))
        XCTAssertEqual(staging.room, ShareItems.Staging.budget - 6)
        XCTAssertEqual(staging.photo(Data(count: 10), named: "IMG_0412.jpg"),
                       .file(URL(fileURLWithPath: "/staged/IMG_0412.jpg"),
                             filename: "IMG_0412.jpg", mimeType: "image/jpeg", size: 10))
        XCTAssertEqual(staging.room, ShareItems.Staging.budget - 16)
        XCTAssertEqual(disk.written["Dancing cat.gif"], gif)
    }

    // MARK: - ImageIO's part, read from its source

    /// The extension's source, comment lines out and runs of white space as
    /// one space, as `AttachmentStoreTests` reads the screens'.
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

    private func count(_ step: String, in code: String) -> Int {
        code.components(separatedBy: step).count - 1
    }

    /// A share's items: a picture first, by the types offered or, failing
    /// one this knows, by what `UIImage` could read, and then read by
    /// `picture`; never loaded as a `UIImage`, never `jpegData`, anywhere
    /// in the extension.
    func testASharedPictureIsReadByImageIONeverAsAUIImage() throws {
        let sheet = try source("ShareViewController.swift")
        inOrder(["if let type = SharedPhoto.fileType(offered: provider.registeredTypeIdentifiers)",
                 "?? (provider.canLoadObject(ofClass: UIImage.self) ? UTType.image.identifier : nil) {",
                 "picture(provider, type: type, staging: staging) { item in",
                 "} else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),"],
                in: sheet)
        for file in ["ShareViewController.swift", "SharedPhotoImageIO.swift", "ShareItems.swift",
                     "SharedPhoto.swift"] {
            let code = try source(file)
            XCTAssertEqual(count("loadObject(", in: code), 0, file)
            XCTAssertEqual(count("jpegData(", in: code), 0, file)
            XCTAssertEqual(count("pngData(", in: code), 0, file)
            XCTAssertEqual(count("UIImage(", in: code), 0, file)
        }
    }

    /// Its file first, inside the callback that is all the file lasts,
    /// opened by ImageIO and staged there, in an autorelease pool; only
    /// when ImageIO could not open it, its bytes, the same way. One answer
    /// each way, and nothing tried again once staged or left out.
    func testAPictureIsReadFromItsFileThenItsBytesEachInItsOwnPool() throws {
        let code = try source("SharedPhotoImageIO.swift")
        inOrder(["provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in",
                 "let fromFile = autoreleasepool {",
                 "guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, SharedPhoto.reading) else { return .unopened }",
                 "staging.file(at: url, size: size, named: name, mimeType: mimeType)",
                 "switch fromFile {",
                 "case .staged(let item): return done(item)",
                 "case .undecodable: return done(nil)",
                 "case .unopened: break",
                 "}",
                 "provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in",
                 "let fromBytes = autoreleasepool {",
                 "guard let data, let source = CGImageSourceCreateWithData(data as CFData, SharedPhoto.reading) else { return .unopened }",
                 "staging.photo(data, named: name, mimeType: mimeType)",
                 "if case .staged(let item) = fromBytes { done(item) } else { done(nil) }"],
                in: code)
        XCTAssertEqual(count("loadFileRepresentation(", in: code), 1)
        XCTAssertEqual(count("loadDataRepresentation(", in: code), 1)
        XCTAssertEqual(count("autoreleasepool", in: code), 2)
        XCTAssertEqual(count("done(", in: code), 4)
        XCTAssertTrue(code.contains("static let reading = [kCGImageSourceShouldCache: false] as CFDictionary"))
    }

    /// Unopened, and only that, sends it on to its bytes: no file given, or
    /// none ImageIO knows. Opened and no picture made of it (no image at
    /// its index, or the JPEG not made) it is left out there, and its
    /// bytes are never read into memory to fail the same way.
    func testAPictureOpenedAndNotDecodedIsNotReadAgainAsItsBytes() throws {
        let code = try source("SharedPhotoImageIO.swift")
        inOrder(["private enum Picture {", "case staged(SharedItem?)", "case unopened",
                 "case undecodable", "}"], in: code)
        inOrder(["guard index < CGImageSourceGetCount(source) else { return .undecodable }",
                 "guard let jpeg = SharedPhoto.jpeg(from: source, at: index, properties: properties) else { return .undecodable }"],
                in: code)
        XCTAssertEqual(count("return .unopened", in: code), 2, "the file and the bytes not opened")
        XCTAssertEqual(count("return .undecodable", in: code), 2)
        XCTAssertEqual(count(".unreadable", in: code), 0)
        let switched = try XCTUnwrap(code.range(of: "switch fromFile {"))
        let bytes = try XCTUnwrap(code.range(of: "provider.loadDataRepresentation("))
        let between = String(code[switched.upperBound..<bytes.lowerBound])
        XCTAssertEqual(count("return done(nil)", in: between), 1)
        XCTAssertEqual(count("break", in: between), 1)
    }

    /// The JPEG: a thumbnail, from the picture itself, of the longest side
    /// `size` gives and never more, the factor it is read at passed too
    /// where it is one, turned upright, decoded there; encoded with what
    /// `kept` keeps and the quality, and nothing copied from the picture's
    /// file besides.
    func testTheJPEGIsAThumbnailOfAtMost4096UprightWithOnlyWhatIsKept() throws {
        let code = try source("SharedPhotoImageIO.swift")
        inOrder(["let index = CGImageSourceGetPrimaryImageIndex(source)",
                 "guard index < CGImageSourceGetCount(source) else { return .undecodable }",
                 "let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)"],
                in: code)
        inOrder(["let width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0",
                 "let height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0",
                 "let longest = size(width: width, height: height)?.longest ?? longestSide",
                 "let halving = factor(longest: max(width, height))",
                 "var thumbnail: [CFString: Any] = [",
                 "kCGImageSourceCreateThumbnailFromImageAlways: true,",
                 "kCGImageSourceThumbnailMaxPixelSize: longest,",
                 "kCGImageSourceCreateThumbnailWithTransform: true,",
                 "kCGImageSourceShouldCacheImmediately: true,",
                 "if halving > 1 { thumbnail[kCGImageSourceSubsampleFactor] = halving }",
                 "CGImageSourceCreateThumbnailAtIndex(source, index, thumbnail as CFDictionary)",
                 "CGImageDestinationCreateWithData( jpeg as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)",
                 "var written = kept(properties)",
                 "written[kCGImageDestinationLossyCompressionQuality as String] = quality",
                 "CGImageDestinationAddImage(destination, image, written as CFDictionary)",
                 "guard CGImageDestinationFinalize(destination) else { return nil }"],
                in: code)
        XCTAssertEqual(count("CGImageDestinationAddImage(", in: code), 1)
        XCTAssertEqual(count("written[", in: code), 1)
        XCTAssertEqual(count("kCGImageSourceSubsampleFactor", in: code), 1)
        XCTAssertEqual(count("thumbnail[", in: code), 1)
        for never in ["CGImageDestinationAddImageFromSource", "CGImageDestinationCopyImageSource",
                      "kCGImageSourceCreateThumbnailFromImageIfAbsent", "CGImageSourceCreateImageAtIndex",
                      "kCGImageSourceShouldCache: true"] {
            XCTAssertFalse(code.contains(never), never)
        }
    }

    /// Whole or a JPEG as `way` says, with the room left, and a location
    /// looked for three ways before a GIF or PNG may go whole: the rule's
    /// own keys, ImageIO's own name for GPS, and the XMP.
    func testWholeOnlyAsTheRuleSaysAndNeverWithALocation() throws {
        let code = try source("SharedPhotoImageIO.swift")
        inOrder(["let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil)",
                 "let located = SharedPhoto.carriesLocation(properties)",
                 "|| properties[kCGImagePropertyGPSDictionary as String] != nil",
                 "|| SharedPhoto.locationPaths.contains { path in",
                 "CGImageMetadataCopyTagWithPath($0, nil, path as CFString)",
                 "let way = SharedPhoto.way(type: type, size: size, room: staging.room, carriesLocation: located)",
                 "if case .whole(_, let mimeType) = way {",
                 "return .staged(whole(SharedPhoto.name(suggested: suggested, way: way), mimeType))",
                 "guard let jpeg = SharedPhoto.jpeg(from: source, at: index, properties: properties)",
                 "return .staged(staging.photo(jpeg, named: SharedPhoto.name(suggested: suggested, way: .jpeg)))"],
                in: code)
        XCTAssertEqual(count("staging.file(", in: code), 1, "a file copied only whole")
        XCTAssertEqual(count("staging.photo(", in: code), 2, "bytes kept whole, and the JPEG")
    }

    // MARK: - A picture left out

    private func leftOut(_ pictures: Int, _ attached: Int,
                         others: Int = 0) -> ShareItems.LeftOut? {
        ShareItems.leftOut(pictures: pictures, attached: attached, others: others)
    }

    /// Every picture attached, or none offered: nothing said.
    func testNothingIsSaidWhenEveryPictureCame() {
        XCTAssertNil(leftOut(0, 0))
        XCTAssertNil(leftOut(0, 0, others: 1))
        XCTAssertNil(leftOut(1, 1))
        XCTAssertNil(leftOut(5, 5))
        XCTAssertNil(leftOut(2, 2, others: 1))
    }

    /// Some left out, and something else came: a line over the letter,
    /// saying how many.
    func testAPictureLeftOutIsALineOverTheLetter() {
        XCTAssertEqual(leftOut(2, 1), .line("1 photo could not be attached."))
        XCTAssertEqual(leftOut(5, 3), .line("2 photos could not be attached."))
        XCTAssertEqual(leftOut(5, 1), .line("4 photos could not be attached."))
        XCTAssertEqual(leftOut(1, 0, others: 1), .line("1 photo could not be attached."),
                       "a link came with it")
        XCTAssertEqual(leftOut(3, 0, others: 2), .line("3 photos could not be attached."))
        XCTAssertEqual(leftOut(2, 1, others: 1), .line("1 photo could not be attached."))
    }

    /// A share of pictures alone, of which none came: the words in place
    /// of the letter, not an empty letter to send.
    func testNothingCameOfPicturesAloneIsSaidInPlaceOfTheLetter() {
        XCTAssertEqual(leftOut(1, 0), .instead("The photo could not be attached."))
        XCTAssertEqual(leftOut(2, 0), .instead("The photos could not be attached."))
        XCTAssertEqual(leftOut(5, 0), .instead("The photos could not be attached."))
    }

    /// The tally hands the rule what it counted, the others being what
    /// was offered that was not a picture.
    func testTheTallyCountsTheOthersAsWhatWasNotAPicture() {
        let tally = ShareItems.Tally()
        XCTAssertNil(tally.leftOut)
        tally.offered = 1
        tally.pictures = 1
        XCTAssertEqual(tally.leftOut, .instead("The photo could not be attached."))
        tally.offered = 2
        XCTAssertEqual(tally.leftOut, .line("1 photo could not be attached."))
        tally.attached = 1
        XCTAssertNil(tally.leftOut)
        tally.offered = 3
        tally.pictures = 3
        XCTAssertEqual(tally.leftOut, .line("2 photos could not be attached."))
    }

    /// The sheet: every thing offered counted, each picture and each one
    /// attached; the rule's answer handed on with what came. With nothing
    /// to show the words and Cancel in place of the letter; otherwise the
    /// letter, its line above what is attached.
    func testTheSheetSaysWhatCouldNotBeAttached() throws {
        let sheet = try source("ShareViewController.swift")
        inOrder(["completion: @escaping @MainActor ([SharedItem], LeftOut?) -> Void) {",
                 "let staging = Staging()",
                 "let tally = Tally()",
                 "for provider in item.attachments ?? [] {",
                 "tally.offered += 1",
                 "read(provider, title: title, staging: staging, tally: tally, done: done)",
                 "oneAtATime(loads) { items in",
                 "let leftOut = tally.leftOut",
                 "Task { @MainActor in completion(items, leftOut) }"],
                in: sheet)
        inOrder(["tally: Tally, done: @escaping (SharedItem?) -> Void) {",
                 "?? (provider.canLoadObject(ofClass: UIImage.self) ? UTType.image.identifier : nil) {",
                 "tally.pictures += 1",
                 "picture(provider, type: type, staging: staging) { item in",
                 "if item != nil { tally.attached += 1 }",
                 "done(item)",
                 "} else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),"],
                in: sheet)
        XCTAssertEqual(count("tally.offered += 1", in: sheet), 1)
        XCTAssertEqual(count("tally.pictures += 1", in: sheet), 1)
        XCTAssertEqual(count("tally.attached += 1", in: sheet), 1)

        inOrder(["ShareItems.load(from: extensionContext) { [weak self] items, leftOut in",
                 "self?.show(items, leftOut: leftOut, shared: shared)",
                 "private func show(_ items: [SharedItem], leftOut: ShareItems.LeftOut?, shared: ShareMirror.Shared) {",
                 "if case .instead(let words) = leftOut {",
                 "nav.setViewControllers([ShareUnavailableViewController(words: words) {",
                 "return",
                 "if case .line(let words) = leftOut { line = words }",
                 "let form = ShareComposeViewController( shared: shared, items: items, leftOut: line,"],
                in: sheet)
        inOrder(["init(words: String, close: @escaping () -> Void) {",
                 "label.text = words"], in: sheet)
        inOrder(["self.leftOut = leftOut",
                 "stack.addArrangedSubview(row(\"Subject:\", subjectField, draft.subject))",
                 "if let leftOut { stack.addArrangedSubview(note(leftOut)) }",
                 "stack.addArrangedSubview(attachmentsStack)",
                 "private func note(_ words: String) -> UIView {",
                 "label.text = words",
                 "label.textColor = Theme.primaryText",
                 "container.addSubview(v)"],
                in: sheet)
    }
}
