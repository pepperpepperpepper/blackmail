import XCTest
@testable import Blackmail

/// A picture shared into the extension (B-036). Since 2026-10-05 as Apple
/// Mail sends it: a JPEG as its own bytes, never decoded, its metadata
/// replaced, under its file's name; a GIF or PNG whole; "image0.jpeg" for
/// one with no name. Any other, or one too large for the letter, read
/// from its file and made a JPEG of at most 4096 px (2026-10-04), asked of
/// ImageIO at a size its decoder reaches by halving, so a large photo is
/// decoded at a half, a quarter or an eighth, and at a larger factor where
/// the memory left asks it, or left out and said where nothing fits. And a
/// picture that could not be attached said so. The rules here; ImageIO and
/// UIKit doing them are on the iPad only, so their wiring is read from the
/// source, as the screens' is.
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

    /// A factor larger than the least, which the memory may ask for: the
    /// longest side at that factor, rounded down, the other in proportion,
    /// so the size asked for and the factor the decoder is told agree. A
    /// factor smaller than the least is raised to it, so nothing goes past
    /// 4096; and a tiny picture at an eighth is still a pixel.
    func testAFactorTheMemoryAsksForIsTheSizeAskedFor() {
        func size(_ width: Int, _ height: Int, at factor: Int) -> SharedPhoto.Size? {
            SharedPhoto.size(width: width, height: height, factor: factor)
        }
        XCTAssertEqual(size(4032, 3024, at: 2), pixels(2016, 1512), "his camera's, at a half")
        XCTAssertEqual(size(3024, 4032, at: 2), pixels(1512, 2016))
        XCTAssertEqual(size(4032, 3024, at: 8), pixels(504, 378))
        XCTAssertEqual(size(8064, 6048, at: 4), pixels(2016, 1512))
        XCTAssertEqual(size(8064, 6048, at: 1), pixels(4032, 3024), "never less than the least")
        XCTAssertEqual(size(4032, 3024, at: 1), pixels(4032, 3024))
        XCTAssertEqual(size(5, 3, at: 8), pixels(1, 1))
        XCTAssertNil(size(0, 3024, at: 2))
        for longest in [1, 4032, 4097, 8064, 16_000, 40_000] {
            XCTAssertEqual(size(longest, 1000, at: 1), self.size(longest, 1000), "\(longest)")
        }
    }

    // MARK: - Which of what is offered

    /// A JPEG whenever one is offered, ahead of the HEIC beside it in
    /// either order: what Photos hands Mail, made from a HEIC in Photos'
    /// own process. Not ahead of a GIF or a PNG offered before it, which
    /// is the picture as it is. Otherwise the first still offered, the
    /// first of anything ahead of Photos' private thumbnails; a RAW photo
    /// only when nothing else is offered; any picture at all last.
    func testTheJPEGPhotosHandsMailIsReadFirst() {
        XCTAssertEqual(SharedPhoto.fileType(offered: ["public.heic", "public.jpeg"]),
                       "public.jpeg")
        XCTAssertEqual(SharedPhoto.fileType(offered: ["public.jpeg", "public.heic"]),
                       "public.jpeg")
        XCTAssertEqual(SharedPhoto.fileType(offered: ["public.tiff", "public.jpeg"]),
                       "public.jpeg")
        XCTAssertEqual(SharedPhoto.fileType(offered: ["org.webmproject.webp", "public.jpeg"]),
                       "public.jpeg")
        XCTAssertEqual(SharedPhoto.fileType(offered: ["com.adobe.raw-image", "public.jpeg"]),
                       "public.jpeg")
        XCTAssertEqual(SharedPhoto.fileType(offered: ["com.apple.private.photos.thumbnail.standard",
                                                      "public.heic", "public.jpeg"]),
                       "public.jpeg")
        XCTAssertEqual(SharedPhoto.fileType(offered: ["public.png", "public.jpeg"]), "public.png",
                       "a screenshot as the PNG it is")
        XCTAssertEqual(SharedPhoto.fileType(offered: ["com.compuserve.gif", "public.jpeg"]),
                       "com.compuserve.gif", "still moving")
        XCTAssertEqual(SharedPhoto.fileType(offered: ["public.jpeg", "public.png"]), "public.jpeg")
        XCTAssertEqual(SharedPhoto.fileType(offered: ["com.apple.private.photos.thumbnail.standard",
                                                      "com.apple.live-photo-bundle",
                                                      "public.heic"]),
                       "public.heic", "no JPEG offered")
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

    // MARK: - Its own bytes, whole, or a JPEG

    private let gif = SharedPhoto.Way.whole(filenameExtension: "gif", mimeType: "image/gif")
    private let png = SharedPhoto.Way.whole(filenameExtension: "png", mimeType: "image/png")

    private func way(_ type: String, _ size: Int64, room: Int64 = ShareItems.Staging.budget,
                     located: Bool = false) -> SharedPhoto.Way {
        SharedPhoto.way(type: type, size: size, room: room, carriesLocation: located)
    }

    /// A JPEG that fits in what is left of the letter goes as its own
    /// bytes, however large, a location or not: its metadata is replaced
    /// on the way. One byte over the room, it is made a JPEG, shrunk, as
    /// Mail would send it by Mail Drop.
    func testAJPEGThatFitsGoesAsItsOwnBytes() {
        XCTAssertEqual(way("public.jpeg", 3_000_000), .own)
        XCTAssertEqual(way("public.jpeg", 3_000_000, located: true), .own)
        XCTAssertEqual(way("public.jpeg", 24_000_000), .own, "no bound but the room")
        XCTAssertEqual(way("public.jpeg", ShareItems.Staging.budget), .own, "exactly the room")
        XCTAssertEqual(way("public.jpeg", ShareItems.Staging.budget + 1), .jpeg)
        XCTAssertEqual(way("public.jpeg", 3_000_000, room: 3_000_000), .own, "exactly the room")
        XCTAssertEqual(way("public.jpeg", 3_000_001, room: 3_000_000), .jpeg)
        XCTAssertEqual(way("public.jpeg", 3_000_000, room: 0), .jpeg)
        XCTAssertEqual(way("public.jpeg", 0), .jpeg, "a size it would not say")
    }

    /// A GIF or a PNG goes as the file it is while it fits in what is left
    /// of the letter and says nothing of where it was, at any size: no
    /// fifth of the letter now, Mail having no bound at Actual Size. With
    /// a location, or past the room, it is made a JPEG.
    func testAGIFOrAPNGGoesWholeWhenItFitsAndIsSilentOnWhere() {
        XCTAssertEqual(way("com.compuserve.gif", 2_000_000), gif)
        XCTAssertEqual(way("public.png", 1_500_000), png)
        XCTAssertEqual(way("com.compuserve.gif", 5_000_001), gif, "over the old 5 MB")
        XCTAssertEqual(way("public.png", 12_000_000), png)
        XCTAssertEqual(way("public.png", ShareItems.Staging.budget), png, "exactly the room")
        XCTAssertEqual(way("public.png", ShareItems.Staging.budget + 1), .jpeg)
        XCTAssertEqual(way("public.png", 1_500_000, room: 1_499_999), .jpeg)
        XCTAssertEqual(way("public.png", 1_500_000, room: 1_500_000), png, "exactly the room")
        XCTAssertEqual(way("public.png", 1_500_000, located: true), .jpeg)
        XCTAssertEqual(way("com.compuserve.gif", 1_500_000, located: true), .jpeg)
        XCTAssertEqual(way("public.png", 0), .jpeg, "a size it would not say")
    }

    /// Every other picture is made a JPEG, however small: what Mail would
    /// get from Photos as a JPEG, this did not.
    func testAnyOtherPictureIsMadeAJPEG() {
        for type in ["public.heic", "public.heif", "public.tiff", "org.webmproject.webp",
                     "public.avif", "com.microsoft.bmp", "com.adobe.raw-image", "public.image"] {
            XCTAssertEqual(way(type, 200_000), .jpeg, type)
        }
    }

    // MARK: - The memory Send takes

    private func sendRoom(_ staged: Int64, _ available: Int64,
                          room: Int64 = ShareItems.Staging.budget) -> Int64 {
        SharedPhoto.sendRoom(room: room, staged: staged, available: available)
    }

    /// The letter is built whole at Send, five times its files at its
    /// height, so a picture goes as itself only while the letter, it
    /// with them, takes three fifths of the memory left or less: 9.6 MB
    /// of letter with the 80 MB assumed, 18 MB with 150 MB, less what is
    /// staged; never more than the letter's own room, and never less than
    /// nought.
    func testTheRoomIsWhatSendCanBuildInTheMemoryLeft() {
        XCTAssertEqual(SharedPhoto.sendPeak, 5)
        XCTAssertEqual(sendRoom(0, 80_000_000), 9_600_000)
        XCTAssertEqual(sendRoom(0, SharedPhoto.assumedAvailable), 9_600_000)
        XCTAssertEqual(sendRoom(0, 150_000_000), 18_000_000)
        XCTAssertEqual(sendRoom(4_000_000, 80_000_000), 5_600_000, "less what is staged")
        XCTAssertEqual(sendRoom(9_600_000, 80_000_000), 0)
        XCTAssertEqual(sendRoom(12_000_000, 80_000_000), 0, "never less than nought")
        XCTAssertEqual(sendRoom(0, 1_000_000_000), ShareItems.Staging.budget,
                       "never more than the letter's own room")
        XCTAssertEqual(sendRoom(0, 1_000_000_000, room: 3_000_000), 3_000_000)
        XCTAssertEqual(sendRoom(0, 0), 0)
        XCTAssertEqual(sendRoom(0, -5), 0)

        let room = sendRoom(0, 80_000_000)
        XCTAssertEqual(way("public.jpeg", 9_600_000, room: room), .own, "exactly the room")
        XCTAssertEqual(way("public.jpeg", 9_600_001, room: room), .jpeg)
        XCTAssertEqual(way("public.png", 9_600_001, room: room), .jpeg)
        XCTAssertEqual(way("public.jpeg", 5_600_001, room: sendRoom(4_000_000, 80_000_000)), .jpeg)
    }

    /// Why a JPEG, a GIF or a PNG goes as a JPEG made here, for the log:
    /// its size not known, a location in a GIF or PNG, the letter's room,
    /// then Send's. Nothing for one that goes as itself, nor for a
    /// picture that never could.
    func testWhyAPictureDoesNotGoAsItselfIsSaid() {
        func why(_ type: String, _ size: Int64, room: Int64 = 25_000_000,
                 send: Int64 = 9_600_000, located: Bool = false) -> String? {
            SharedPhoto.notItself(type: type, size: size, room: room, sendRoom: send,
                                  carriesLocation: located)
        }
        XCTAssertNil(why("public.jpeg", 9_600_000))
        XCTAssertNil(why("public.jpeg", 3_000_000, located: true), "its metadata is replaced")
        XCTAssertNil(why("public.png", 9_600_000))
        XCTAssertEqual(why("public.jpeg", 9_600_001),
                       "more than Send could build, room for 9 MB")
        XCTAssertEqual(why("com.compuserve.gif", 9_600_001),
                       "more than Send could build, room for 9 MB")
        XCTAssertEqual(why("public.jpeg", 15_000_001, room: 15_000_000, send: 2_000_000),
                       "more than the letter's room, 15 MB left")
        XCTAssertEqual(why("public.png", 1_000, located: true), "it says where it was")
        XCTAssertEqual(why("public.jpeg", 0), "its size not known")
        for type in ["public.heic", "public.tiff", "org.webmproject.webp", "public.image"] {
            XCTAssertNil(why(type, 30_000_000, room: 1, send: 1, located: true), type)
        }
    }

    // MARK: - Its name

    /// The sharing app's suggestion first; then the name of the file it
    /// handed over, which is how Photos names a photo; then none. Blank,
    /// or nothing but an extension, is no name, and the next is tried.
    func testTheNameComesFromTheSuggestionThenTheFileThenNothing() {
        func named(_ suggested: String?, _ file: String?) -> SharedPhoto.Named {
            SharedPhoto.named(suggested: suggested, file: file)
        }
        XCTAssertEqual(named("Garden", "IMG_0776.JPG"), .suggested("Garden"))
        XCTAssertEqual(named("  Garden \n", "IMG_0776.JPG"), .suggested("Garden"))
        XCTAssertEqual(named(nil, "IMG_0776.JPG"), .file("IMG_0776.JPG"))
        XCTAssertEqual(named("", "IMG_0776.JPG"), .file("IMG_0776.JPG"))
        XCTAssertEqual(named("  ", "IMG_0776.JPG"), .file("IMG_0776.JPG"))
        XCTAssertEqual(named(".heic", "IMG_0776.JPG"), .file("IMG_0776.JPG"))
        XCTAssertEqual(named(nil, "IMG_0412"), .file("IMG_0412"), "no extension is still a name")
        XCTAssertEqual(named(nil, ".jpg"), SharedPhoto.Named.none)
        XCTAssertEqual(named(nil, " .jpg "), SharedPhoto.Named.none)
        XCTAssertEqual(named(nil, ""), SharedPhoto.Named.none)
        XCTAssertEqual(named(nil, nil), SharedPhoto.Named.none)
        XCTAssertEqual(named("  ", nil), SharedPhoto.Named.none)
    }

    /// As its own bytes or whole, the file's name as it is, case and all,
    /// as in his Sent mail; a file whose extension says another type takes
    /// the one it goes with.
    func testAPictureAsItsOwnBytesKeepsItsFilesNameAsItIs() {
        func name(_ file: String, _ way: SharedPhoto.Way) -> String {
            SharedPhoto.name(.file(file), way: way, number: 0)
        }
        XCTAssertEqual(name("IMG_0776.JPG", .own), "IMG_0776.JPG")
        XCTAssertEqual(name("IMG_0774.jpg", .own), "IMG_0774.jpg", "Photos' JPEG of a HEIC")
        XCTAssertEqual(name("IMG_0774.jpeg", .own), "IMG_0774.jpeg")
        XCTAssertEqual(name("IMG_0775.PNG", png), "IMG_0775.PNG")
        XCTAssertEqual(name("Dancing cat.gif", gif), "Dancing cat.gif")
        XCTAssertEqual(name("IMG_0412.HEIC", .own), "IMG_0412.jpg", "not what it is")
        XCTAssertEqual(name("IMG_0412", .own), "IMG_0412.jpg")
        XCTAssertEqual(name("IMG_0775.PNG", gif), "IMG_0775.gif")
    }

    /// Made a JPEG here, the file's name ends ".jpg", whatever it ended
    /// with: what was its own extension is not kept.
    func testAPictureMadeAJPEGKeepsItsNameAndEndsJpg() {
        func name(_ file: String) -> String {
            SharedPhoto.name(.file(file), way: .jpeg, number: 0)
        }
        XCTAssertEqual(name("IMG_0777.JPG"), "IMG_0777.jpg")
        XCTAssertEqual(name("IMG_0412.HEIC"), "IMG_0412.jpg")
        XCTAssertEqual(name("IMG_0775.PNG"), "IMG_0775.jpg")
        XCTAssertEqual(name("Wide.tiff"), "Wide.jpg")
        XCTAssertEqual(name("IMG_0412"), "IMG_0412.jpg")
    }

    /// A suggestion as before: without the extension it came with, and
    /// with the one it goes with, ".jpg" for a JPEG either way.
    func testASuggestedNameTakesTheExtensionItGoesWith() {
        func name(_ suggested: String, _ way: SharedPhoto.Way = .jpeg) -> String {
            SharedPhoto.name(.suggested(suggested), way: way, number: 0)
        }
        XCTAssertEqual(name("IMG_0412"), "IMG_0412.jpg")
        XCTAssertEqual(name("IMG_0412.HEIC"), "IMG_0412.jpg")
        XCTAssertEqual(name("IMG_0412.jpeg"), "IMG_0412.jpg")
        XCTAssertEqual(name("IMG_0412.JPG", .own), "IMG_0412.jpg")
        XCTAssertEqual(name("Garden.png"), "Garden.jpg")
        XCTAssertEqual(name("Mr. Brown"), "Mr. Brown.jpg", "not a picture's extension")
        XCTAssertEqual(name("Sunday 3.10"), "Sunday 3.10.jpg")
        XCTAssertEqual(name("Dancing cat.gif", gif), "Dancing cat.gif")
        XCTAssertEqual(name("Dancing cat", gif), "Dancing cat.gif")
        XCTAssertEqual(name("Screenshot 2026-10-04 at 10.12.PNG", png),
                       "Screenshot 2026-10-04 at 10.12.png")
    }

    /// No name: "image" and its number, ".jpeg" for a JPEG, as his own or
    /// made here, and its own extension whole. Never "Photo".
    func testAPictureWithNoNameIsImageAndANumber() {
        func name(_ way: SharedPhoto.Way, _ number: Int) -> String {
            SharedPhoto.name(.none, way: way, number: number)
        }
        XCTAssertEqual(name(.own, 0), "image0.jpeg")
        XCTAssertEqual(name(.jpeg, 0), "image0.jpeg")
        XCTAssertEqual(name(png, 1), "image1.png")
        XCTAssertEqual(name(gif, 2), "image2.gif")
        XCTAssertEqual(name(.jpeg, 12), "image12.jpeg")
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

    /// Into a JPEG made here only the moment it was taken goes, with its
    /// offset from UTC: no location, no orientation (the picture is turned
    /// upright as it is made), no camera, nothing of Apple's.
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

    /// With its own bytes, the moment it was taken and its orientation, as
    /// a tag, since those pixels are not turned; nothing else, no location.
    func testWithItsOwnBytesTheMomentAndTheOrientationGo() {
        let kept = SharedPhoto.keptOwn(cameraPhoto)
        XCTAssertEqual(Set(kept.keys), ["{Exif}", "{TIFF}"])
        XCTAssertEqual(kept["{Exif}"] as? [String: String],
                       ["DateTimeOriginal": "2026:09:20 14:03:11", "OffsetTimeOriginal": "-04:00"])
        XCTAssertEqual(kept["{TIFF}"] as? [String: Int], ["Orientation": 6])
        XCTAssertEqual(SharedPhoto.keptOwn(["Orientation": 8])["{TIFF}"] as? [String: Int],
                       ["Orientation": 8], "ImageIO's own reading of it")
        XCTAssertEqual(SharedPhoto.keptOwn(["{TIFF}": ["Orientation": 3] as [String: Any],
                                            "Orientation": 1])["{TIFF}"] as? [String: Int],
                       ["Orientation": 3], "the file's own first")
        XCTAssertTrue(SharedPhoto.keptOwn(["{TIFF}": ["Orientation": 9] as [String: Any]]).isEmpty)
        XCTAssertTrue(SharedPhoto.keptOwn(["{TIFF}": ["Make": "Apple"] as [String: Any],
                                           "{GPS}": ["Latitude": 12.3456] as [String: Any]]).isEmpty)
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

    /// A photo written as its own bytes, read back, is thrown away when it
    /// still says where it was, by GPS or IPTC, or carries Apple's notes or
    /// a maker's note; not for what `keptOwn` put in it, nor for what
    /// ImageIO writes of its own.
    func testWhatIsReadBackMayNotSayMoreThanWasKept() {
        for kept: [String: Any] in [
            [:],
            ["{Exif}": ["DateTimeOriginal": "2026:09:20 14:03:11",
                        "OffsetTimeOriginal": "-04:00"] as [String: Any]],
            ["{TIFF}": ["Orientation": 8] as [String: Any]],
            ["Orientation": 8, "ProfileName": "Display P3", "PixelWidth": 8064,
             "PixelHeight": 6048, "ColorModel": "RGB", "Depth": 8],
            ["{Exif}": ["PixelXDimension": 8064, "PixelYDimension": 6048,
                        "ColorSpace": 65535] as [String: Any],
             "{JFIF}": ["DensityUnit": 0] as [String: Any]],
        ] {
            XCTAssertFalse(SharedPhoto.keepsMoreThanReplaced(kept), "\(kept)")
        }
        for more: [String: Any] in [
            ["{GPS}": ["Latitude": 12.3456] as [String: Any]],
            ["{GPS}": [String: Any]()],
            ["{IPTC}": ["City": "Nowhere"] as [String: Any]],
            ["{MakerApple}": ["8": 1] as [String: Any]],
            ["{Exif}": ["DateTimeOriginal": "2026:09:20 14:03:11",
                        "MakerNote": Data([1, 2, 3])] as [String: Any]],
            cameraPhoto,
        ] {
            XCTAssertTrue(SharedPhoto.keepsMoreThanReplaced(more), "\(more)")
        }
    }

    // MARK: - The memory it takes

    private func factor(_ width: Int, _ height: Int, _ type: String,
                        _ available: Int64) -> Int? {
        SharedPhoto.factor(width: width, height: height, type: type, available: available)
    }

    /// The peak, as measured on the test iPad: a JPEG three times its
    /// decoded picture, a HEIC 1.2, and the JPEG made at a byte a pixel.
    func testThePeakIsTheDecodersShareAndTheJPEGMade() {
        XCTAssertEqual(SharedPhoto.decoding(type: "public.jpeg"), .init(peak: 3, halves: true))
        XCTAssertEqual(SharedPhoto.decoding(type: "public.heic"), .init(peak: 1.2, halves: true))
        XCTAssertEqual(SharedPhoto.decoding(type: "public.png"), .init(peak: 3, halves: true))
        for type in ["org.webmproject.webp", "com.compuserve.gif", "com.microsoft.bmp",
                     "public.avif", "com.adobe.raw-image", "public.image"] {
            XCTAssertEqual(SharedPhoto.decoding(type: type), .init(peak: 3, halves: false), type)
        }
        func peak(_ w: Int, _ h: Int, _ type: String, _ factor: Int) -> Int64 {
            SharedPhoto.peak(width: w, height: h, type: type, factor: factor)
        }
        XCTAssertEqual(peak(4032, 3024, "public.jpeg", 1), 146_313_216 + 12_192_768)
        XCTAssertEqual(peak(4032, 3024, "public.jpeg", 2), 36_578_304 + 3_048_192)
        XCTAssertEqual(peak(4032, 3024, "public.heic", 1), 70_718_054)
        XCTAssertEqual(peak(8064, 6048, "public.jpeg", 1), peak(8064, 6048, "public.jpeg", 2),
                       "never read at less than the least")
        XCTAssertEqual(peak(4032, 3024, "org.webmproject.webp", 8), 146_313_216 + 190_512,
                       "decoded whole at any factor")
        XCTAssertEqual(SharedPhoto.leastPeak(width: 8064, height: 6048, type: "public.jpeg"),
                       9_906_624, "an eighth")
        XCTAssertEqual(SharedPhoto.leastPeak(width: 4032, height: 3024,
                                             type: "org.webmproject.webp"),
                       146_313_216 + 12_192_768, "its least, made at its own size")
    }

    /// With memory to spare, the least factor, as before: the memory never
    /// makes a picture smaller than it had to be.
    func testWithMemoryToSpareItIsReadAtTheLeastFactor() {
        let plenty: Int64 = 1_000_000_000_000
        for longest in [1, 1000, 4032, 4096, 4097, 8064, 8193, 16_000, 16_388, 32_776, 40_000] {
            for type in ["public.jpeg", "public.heic", "public.png", "org.webmproject.webp"] {
                XCTAssertEqual(factor(longest, longest * 3 / 4 + 1, type, plenty),
                               SharedPhoto.factor(longest: longest), "\(longest) \(type)")
            }
        }
    }

    /// A 12-megapixel JPEG is read whole with 264 MB left, which no iPad
    /// here gives an extension, and at a half below it; a HEIC of his
    /// camera whole with 118 MB, a half below; at each factor to the byte,
    /// the peak against three fifths of what is left.
    func testTheMemoryAsksForALargerFactorAtItsBounds() {
        XCTAssertEqual(SharedPhoto.memoryShare, 0.6)
        XCTAssertEqual(factor(4032, 3024, "public.jpeg", 264_176_640), 1)
        XCTAssertEqual(factor(4032, 3024, "public.jpeg", 264_176_639), 2)
        XCTAssertEqual(factor(4032, 3024, "public.jpeg", 66_044_160), 2)
        XCTAssertEqual(factor(4032, 3024, "public.jpeg", 66_044_159), 4)
        XCTAssertEqual(factor(4032, 3024, "public.jpeg", 16_511_040), 4)
        XCTAssertEqual(factor(4032, 3024, "public.jpeg", 16_511_039), 8)
        XCTAssertEqual(factor(4032, 3024, "public.heic", 117_863_424), 1)
        XCTAssertEqual(factor(4032, 3024, "public.heic", 117_863_423), 2)
        XCTAssertEqual(factor(3024, 4032, "public.heic", 140_000_000), 1, "the test iPad, about")
        XCTAssertEqual(factor(8064, 6048, "public.jpeg", 264_176_640), 2)
        XCTAssertEqual(factor(8064, 6048, "public.jpeg", 264_176_639), 4)
        XCTAssertEqual(factor(8064, 6048, "public.heic", 117_863_424), 2)
        XCTAssertEqual(factor(16_000, 4_000, "public.jpeg", 86_666_667), 4)
        XCTAssertEqual(factor(16_000, 4_000, "public.jpeg", 86_666_666), 8)
    }

    /// Where even an eighth would not fit, nothing: the picture is left out
    /// and said, not the extension killed. A picture decoded whole
    /// whatever is asked is tried at its least factor alone, gaining
    /// nothing from a larger one.
    func testWhereNothingFitsThePictureIsLeftOut() {
        XCTAssertEqual(factor(4032, 3024, "public.jpeg", 4_127_760), 8)
        XCTAssertNil(factor(4032, 3024, "public.jpeg", 4_127_759))
        XCTAssertEqual(factor(8064, 6048, "public.jpeg", 16_511_040), 8)
        XCTAssertNil(factor(8064, 6048, "public.jpeg", 16_511_039))
        XCTAssertNil(factor(40_000, 10_000, "public.jpeg", 131_990_506))
        XCTAssertEqual(factor(40_000, 10_000, "public.jpeg", 131_990_507), 8)
        XCTAssertEqual(factor(4032, 3024, "org.webmproject.webp", 264_176_640), 1)
        XCTAssertNil(factor(4032, 3024, "org.webmproject.webp", 264_176_639),
                     "not halved for the JPEG's sake")
        XCTAssertNil(factor(8064, 6048, "org.webmproject.webp", 900_000_000),
                     "48 megapixels decoded whole")
        XCTAssertNil(factor(4032, 3024, "public.jpeg", 0))
    }

    /// A picture that does not say its size is read as before, at 1, and
    /// what is not known is assumed: 80 MB.
    func testAPictureOfNoSizeIsReadAsBeforeAndUnknownMemoryIsAssumed() {
        XCTAssertEqual(factor(0, 0, "public.jpeg", 1), 1)
        XCTAssertEqual(factor(4032, 0, "public.heic", 0), 1)
        XCTAssertEqual(SharedPhoto.assumedAvailable, 80_000_000)
        XCTAssertEqual(factor(4032, 3024, "public.heic", SharedPhoto.assumedAvailable), 2)
    }

    /// More memory never a larger factor, nor a picture left out that less
    /// memory took, for any size up to 40000 px, each type.
    func testMoreMemoryNeverMakesItSmaller() {
        var worse: [String] = []
        for type in ["public.jpeg", "public.heic", "org.webmproject.webp"] {
            for longest in stride(from: 500, through: 40_000, by: 500) {
                var last: Int?
                for megabytes in stride(from: 5, through: 400, by: 5) {
                    let now = factor(longest, longest / 2, type, Int64(megabytes) * 1_000_000)
                    if let before = last, now.map({ $0 > before }) ?? true {
                        worse.append("\(type) \(longest) \(megabytes)")
                    }
                    last = now
                }
            }
        }
        XCTAssertTrue(worse.isEmpty, "\(worse.count), first \(worse.prefix(3))")
    }

    // MARK: - Staged

    /// Staged nowhere, as `ShareItemsTests` stages, and a file written
    /// straight onto the disk placed in a directory of the test's own.
    private final class Disk {
        var written: [String: Data] = [:]
        var placed: [URL] = []
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedPhotoTests-\(UUID().uuidString)", isDirectory: true)

        func write(_ data: Data, _ filename: String) throws -> URL {
            written[filename] = data
            return URL(fileURLWithPath: "/staged/\(filename)")
        }
        func copy(_ source: URL, _ filename: String) throws -> URL {
            URL(fileURLWithPath: "/staged/\(filename)")
        }
        func place(_ filename: String) throws -> URL {
            let url = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            placed.append(url.appendingPathComponent(filename))
            return url.appendingPathComponent(filename)
        }
        func discard(_ url: URL) {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
        func staging() -> ShareItems.Staging {
            ShareItems.Staging(write: write, copy: copy, place: place, discard: discard)
        }
        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    /// A picture's bytes kept whole go as their own type, and the room
    /// left shrinks by what each staged.
    func testBytesKeptWholeGoAsTheirOwnTypeAndTheRoomShrinks() {
        let disk = Disk()
        let staging = disk.staging()
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

    /// Its own bytes written straight to where they are staged: the room
    /// looked for by the size of the file it came from, before anything is
    /// written; the file as written counted, which is what the letter
    /// carries.
    func testItsOwnBytesAreWrittenWhereTheyAreStagedAndCountedAsWritten() throws {
        let disk = Disk()
        let staging = disk.staging()
        var handed: URL?
        let item = staging.written(named: "IMG_0776.JPG", mimeType: "image/jpeg",
                                   expected: 3_000) { url in
            handed = url
            return FileManager.default.createFile(atPath: url.path, contents: Data(count: 2_900))
        }
        let url = try XCTUnwrap(handed)
        XCTAssertEqual(url.lastPathComponent, "IMG_0776.JPG")
        XCTAssertEqual(item, .file(url, filename: "IMG_0776.JPG", mimeType: "image/jpeg",
                                   size: 2_900))
        XCTAssertEqual(staging.staged, 2_900)
        XCTAssertTrue(disk.exists(url))
        XCTAssertTrue(disk.written.isEmpty, "nothing through memory")
    }

    /// No room for the file it comes from: nothing placed, nothing
    /// written. Written larger than the room, or not written at all: taken
    /// away again, and the room as it was.
    func testItsOwnBytesWithoutRoomOrNotWrittenLeaveNothing() throws {
        let disk = Disk()
        let staging = disk.staging()
        XCTAssertNotNil(staging.photo(Data(count: 1_000), named: "First.jpg"))
        let room = staging.room

        var called = false
        XCTAssertNil(staging.written(named: "IMG_0776.JPG", mimeType: "image/jpeg",
                                     expected: room + 1) { _ in called = true; return true })
        XCTAssertFalse(called, "not even begun")
        XCTAssertTrue(disk.placed.isEmpty)

        var tooLarge: URL?
        XCTAssertNil(staging.written(named: "IMG_0777.JPG", mimeType: "image/jpeg",
                                     expected: room) { url in
            tooLarge = url
            guard FileManager.default.createFile(atPath: url.path, contents: nil),
                  let handle = try? FileHandle(forWritingTo: url) else { return false }
            handle.truncateFile(atOffset: UInt64(room) + 1)
            handle.closeFile()
            return true
        })
        XCTAssertFalse(disk.exists(try XCTUnwrap(tooLarge)), "taken away again")

        var failed: URL?
        XCTAssertNil(staging.written(named: "IMG_0778.JPG", mimeType: "image/jpeg",
                                     expected: 10) { url in
            failed = url
            _ = FileManager.default.createFile(atPath: url.path, contents: Data(count: 5))
            return false
        })
        XCTAssertFalse(disk.exists(try XCTUnwrap(failed)), "taken away again")
        XCTAssertEqual(staging.room, room)
        XCTAssertEqual(staging.staged, 1_000)
    }

    /// The pictures with no name are counted per share, one count for
    /// every type and every way staged, and only when staged: a second
    /// share begins again at nought.
    func testThePicturesWithNoNameAreCountedPerShareAcrossTypes() {
        let disk = Disk()
        let staging = disk.staging()
        func next(_ way: SharedPhoto.Way) -> String {
            SharedPhoto.name(.none, way: way, number: staging.unnamed)
        }
        XCTAssertEqual(staging.unnamed, 0)
        let first = next(.jpeg)
        XCTAssertNotNil(staging.photo(Data(count: 10), named: first, unnamed: true))
        let second = next(png)
        XCTAssertNotNil(staging.file(at: URL(fileURLWithPath: "/shared/x"), size: 10,
                                     named: second, mimeType: "image/png", unnamed: true))
        XCTAssertNotNil(staging.photo(Data(count: 10), named: "IMG_0776.JPG"), "a named one")
        let third = next(.own)
        XCTAssertNotNil(staging.written(named: third, mimeType: "image/jpeg", expected: 10,
                                        unnamed: true) { url in
            FileManager.default.createFile(atPath: url.path, contents: Data(count: 10))
        })
        XCTAssertNil(staging.photo(Data(count: Int(ShareItems.Staging.budget)),
                                   named: next(.jpeg), unnamed: true), "left out")
        let fourth = next(gif)
        XCTAssertEqual([first, second, third, fourth],
                       ["image0.jpeg", "image1.png", "image2.jpeg", "image3.gif"])
        XCTAssertEqual(disk.staging().unnamed, 0, "a share of its own")
    }

    // MARK: - The log

    private func report(_ named: SharedPhoto.Named, _ name: String,
                        _ went: SharedPhoto.Went, inside: String? = "public.jpeg",
                        bytes: Int64) -> SharedPhoto.Report {
        var report = SharedPhoto.Report(offered: ["public.jpeg", "public.heic"],
                                        read: "public.jpeg", named: named)
        report.inside = inside
        report.name = name
        report.went = went
        report.bytes = bytes
        return report
    }

    /// One line a picture: what was offered, in order; what was read; the
    /// name and where it came from; the way; the bytes staged.
    func testTheLogSaysWhatWasOfferedReadNamedAndHowItWent() {
        XCTAssertEqual(report(.file("IMG_0776.JPG"), "IMG_0776.JPG", .own, bytes: 2_345_678).line,
                       "SHARE-PICTURE offered=public.jpeg,public.heic read=public.jpeg"
                       + " name=file \"IMG_0776.JPG\" way=own bytes, metadata replaced"
                       + " bytes=2345678")
        XCTAssertEqual(report(.none, "image0.png", .whole, inside: "public.png", bytes: 900).line,
                       "SHARE-PICTURE offered=public.jpeg,public.heic read=public.jpeg"
                       + " (public.png inside) name=none \"image0.png\" way=copied whole"
                       + " bytes=900")
        var shrunk = report(.suggested("Garden"), "Garden.jpg",
                            .jpeg(factor: 2, available: 140_400_000), bytes: 812_000)
        shrunk.fellBack = "CopyImageSource failed"
        XCTAssertEqual(shrunk.line,
                       "SHARE-PICTURE offered=public.jpeg,public.heic read=public.jpeg"
                       + " name=suggested \"{6 chars}.jpg\" way=JPEG at factor 2, 140 MB available"
                       + " (not as its own bytes: CopyImageSource failed) bytes=812000")
        XCTAssertTrue(report(.none, "image0.jpeg", .jpeg(factor: 1, available: nil), bytes: 1).line
            .contains("way=JPEG at factor 1, memory unknown, 80 MB assumed bytes=1"))
        XCTAssertTrue(report(.file("IMG_0412.HEIC"), "",
                             .tooLargeForMemory(needs: 9_906_624, available: 12_000_000),
                             bytes: 0).line
            .hasSuffix("way=left out, 17 MB needed at the least, 12 MB available bytes=0"))
        XCTAssertTrue(report(.none, "", .notOpened, bytes: 0).line
            .hasSuffix("way=left out, not opened bytes=0"))
        XCTAssertTrue(report(.none, "", .leftOut("no room"), bytes: 0).line
            .hasSuffix("way=left out, no room bytes=0"))
    }

    /// A name goes in the log as it is only when a device made it, Photos'
    /// IMG_ and digits or image and digits made here; any other is a title
    /// someone gave it, and goes by its length and its extension: the log
    /// says what happened in numbers, never who or what about.
    func testANameInTheLogIsAsItIsOnlyWhereADeviceMadeIt() {
        let line = report(.suggested("Garden party at Sam's"), "Garden party at Sam's.jpg", .own,
                          bytes: 1).line
        XCTAssertFalse(line.contains("Garden"), line)
        XCTAssertFalse(line.contains("Sam"), line)
        XCTAssertTrue(line.contains("name=suggested \"{21 chars}.jpg\""), line)
        XCTAssertTrue(report(.file("IMG_0775.PNG"), "IMG_0775.PNG", .whole, bytes: 1).line
            .contains("name=file \"IMG_0775.PNG\""))
        func logged(_ name: String) -> String { SharedPhoto.Report.logged(name) }
        for kept in ["IMG_0776.JPG", "IMG_0412.jpg", "IMG_12345.heic", "image0.jpeg", "image1.png",
                     "image12.gif"] {
            XCTAssertEqual(logged(kept), kept)
        }
        XCTAssertEqual(logged("IMG_Sam.jpg"), "{7 chars}.jpg")
        XCTAssertEqual(logged("IMG_.jpg"), "{4 chars}.jpg")
        XCTAssertEqual(logged("image.jpeg"), "{5 chars}.jpeg")
        XCTAssertEqual(logged("imageSam.jpeg"), "{8 chars}.jpeg")
        XCTAssertEqual(logged("IMG_0776"), "{8 chars}", "no extension")
        XCTAssertEqual(logged("IMG_0776.J G"), "{8 chars}", "an extension that is words")
        XCTAssertEqual(logged("Sam.verylong"), "{3 chars}")
        XCTAssertEqual(logged("IMG_\u{0661}\u{0662}.jpg"), "{6 chars}.jpg", "digits, not ASCII")
        XCTAssertEqual(logged("12 Elm Street.png"), "{13 chars}.png")
        XCTAssertEqual(logged(""), "{0 chars}")
    }

    /// A picture left out for the memory says what would have had to be
    /// left, more than what was: the peak over the three fifths a decode
    /// may take, rounded up, and what was left rounded down. Every one
    /// left out, every size and type here.
    func testALeftOutLineNeedsMoreThanWasLeft() {
        var wrong: [String] = []
        for type in ["public.jpeg", "public.heic", "org.webmproject.webp"] {
            for longest in stride(from: 1000, through: 40_000, by: 1000) {
                for megabytes in stride(from: 1, through: 1_000, by: 1) {
                    let available = Int64(megabytes) * 1_000_000 + 500_000
                    let height = longest * 3 / 4
                    guard factor(longest, height, type, available) == nil else { continue }
                    let needs = SharedPhoto.leastPeak(width: longest, height: height, type: type)
                    let line = report(.none, "", .tooLargeForMemory(needs: needs,
                                                                    available: available),
                                      bytes: 0).line
                    let numbers = line.components(separatedBy: "way=left out, ").last?
                        .split(separator: " ").compactMap { Int($0) } ?? []
                    if numbers.count < 2 || numbers[0] <= numbers[1] {
                        wrong.append("\(type) \(longest) \(megabytes): \(line)")
                    }
                }
            }
        }
        XCTAssertTrue(wrong.isEmpty, "\(wrong.count), first \(wrong.prefix(2))")
    }

    /// At each step of Send a line: the files read and their bytes, then
    /// built, then sent, each with the memory left and the least since the
    /// extension started; numbers only.
    func testSendSaysTheMemoryLeftAtEachStep() {
        XCTAssertEqual(SharedPhoto.sendNote("files read", files: [2_345_678, 900],
                                            memory: .init(available: 79_900_000,
                                                          least: 41_200_000)),
                       "SHARE-SEND files read, 2 files 2346578 bytes, 79 MB available,"
                       + " 41 MB at the least")
        XCTAssertEqual(SharedPhoto.sendNote("built", memory: .init(available: 52_000_000)),
                       "SHARE-SEND built, 52 MB available")
        XCTAssertEqual(SharedPhoto.sendNote("sent", memory: .init()),
                       "SHARE-SEND sent, memory unknown")
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

    /// The part of `code` from `start` to the next `end` after it.
    private func part(of code: String, from start: String, to end: String) throws -> String {
        let begun = try XCTUnwrap(code.range(of: start), start)
        let ended = try XCTUnwrap(code.range(of: end, range: begun.upperBound..<code.endIndex), end)
        return String(code[begun.lowerBound..<ended.lowerBound])
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
    /// each way, through `finish`, and nothing tried again once staged or
    /// left out.
    func testAPictureIsReadFromItsFileThenItsBytesEachInItsOwnPool() throws {
        let code = try source("SharedPhotoImageIO.swift")
        inOrder(["provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in",
                 "let fromFile = autoreleasepool {",
                 "guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, SharedPhoto.reading) else { return .unopened }",
                 "staging.file(at: url, size: size, named: name, mimeType: mimeType, unnamed: named == .none)",
                 "switch fromFile {",
                 "case .staged(let item): return finish(item, report, done)",
                 "case .undecodable: return finish(nil, report, done)",
                 "case .unopened: break",
                 "}",
                 "provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in",
                 "let fromBytes = autoreleasepool {",
                 "guard let data, let source = CGImageSourceCreateWithData(data as CFData, SharedPhoto.reading) else { return .unopened }",
                 "staging.photo(data, named: name, mimeType: mimeType, unnamed: named == .none)",
                 "if case .staged(let item) = fromBytes { finish(item, fromItsBytes, done) } else { finish(nil, fromItsBytes, done) }"],
                in: code)
        XCTAssertEqual(count("loadFileRepresentation(", in: code), 1)
        XCTAssertEqual(count("loadDataRepresentation(", in: code), 1)
        XCTAssertEqual(count("autoreleasepool", in: code), 2)
        XCTAssertEqual(count("finish(", in: code), 5, "four answers and the one place they go")
        XCTAssertEqual(count("done(", in: code), 1)
        XCTAssertTrue(code.contains("static let reading = [kCGImageSourceShouldCache: false] as CFDictionary"))
    }

    /// The name: the suggestion taken before the file is asked for, the
    /// file's own name inside its callback, while there is a file, and
    /// both handed to the rule once, for either way it is read. Each
    /// staging told whether the name is a number.
    func testTheNameIsTakenFromTheFileWhileThereIsOne() throws {
        let code = try source("SharedPhotoImageIO.swift")
        inOrder(["let suggested = provider.suggestedName",
                 "provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in",
                 "let named = SharedPhoto.named(suggested: suggested, file: url?.lastPathComponent)",
                 "let fromFile = autoreleasepool {"],
                in: code)
        XCTAssertEqual(count("lastPathComponent", in: code), 1)
        XCTAssertEqual(count("SharedPhoto.named(", in: code), 1)
        XCTAssertEqual(count("unnamed: named == .none", in: code), 4)
        XCTAssertEqual(count("SharedPhoto.name(named, way: way, number: staging.unnamed)", in: code), 2)
        XCTAssertEqual(count("SharedPhoto.name(named, way: .jpeg, number: staging.unnamed)", in: code), 1)
    }

    /// Unopened, and only that, sends it on to its bytes: no file given, or
    /// none ImageIO knows. Opened and no picture made of it (no image at
    /// its index, or the JPEG not made) it is left out there, and its
    /// bytes are never read into memory to fail the same way.
    func testAPictureOpenedAndNotDecodedIsNotReadAgainAsItsBytes() throws {
        let code = try source("SharedPhotoImageIO.swift")
        inOrder(["private enum Picture {", "case staged(SharedItem?)", "case unopened",
                 "case undecodable", "}"], in: code)
        inOrder(["guard index < CGImageSourceGetCount(source) else {",
                 "return .undecodable",
                 "guard let jpeg = SharedPhoto.jpeg(from: source, at: index, properties: properties, factor: factor) else {",
                 "return .undecodable"],
                in: code)
        XCTAssertEqual(count("return .unopened", in: code), 2, "the file and the bytes not opened")
        XCTAssertEqual(count("return .undecodable", in: code), 2)
        XCTAssertEqual(count(".unreadable", in: code), 0)
        let between = try part(of: code, from: "switch fromFile {",
                               to: "provider.loadDataRepresentation(")
        XCTAssertEqual(count("return finish(nil, report, done)", in: between), 1)
        XCTAssertEqual(count("break", in: between), 1)
    }

    /// Its own bytes: copied by ImageIO into a file of the type the source
    /// says it is, at the place staging hands out, with a metadata made
    /// fresh holding only what `keptOwn` keeps, given alone, so every EXIF,
    /// IPTC and XMP tag the file had is replaced. Never merged, never the
    /// GPS left out by ImageIO's own flag, never the orientation as an
    /// option beside it, never `AddImageFromSource`. And what was written
    /// read back before it is staged: one that still says more than was
    /// kept, or holds more than one picture, is thrown away and the photo
    /// made a JPEG.
    func testItsOwnBytesAreCopiedWithTheirMetadataReplaced() throws {
        let code = try source("SharedPhotoImageIO.swift")
        let copy = try part(of: code, from: "static func copy(", to: "static func availableMemory()")
        inOrder(["guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else { return false }",
                 "let metadata = CGImageMetadataCreateMutable()",
                 "for (dictionary, values) in keptOwn(properties) {",
                 "for (name, value) in values {",
                 "CGImageMetadataSetValueMatchingImageProperty(metadata, dictionary as CFString, name as CFString, value as CFTypeRef)",
                 "let replaced = [kCGImageDestinationMetadata: metadata] as CFDictionary",
                 "return CGImageDestinationCopyImageSource(destination, source, replaced, nil)"],
                in: copy)
        XCTAssertEqual(count("CGImageDestinationCopyImageSource(", in: code), 1, "only there")
        XCTAssertEqual(count("kCGImageDestinationMetadata", in: code), 1)
        XCTAssertEqual(count("CGImageMetadataCreateMutable()", in: code), 1)
        for never in ["kCGImageDestinationMergeMetadata", "kCGImageMetadataShouldExcludeGPS",
                      "kCGImageMetadataShouldExcludeXMP", "kCGImageDestinationOrientation",
                      "CGImageDestinationAddImageFromSource", "CGImageMetadataCreateMutableCopy"] {
            XCTAssertFalse(code.contains(never), never)
        }

        inOrder(["let kind = CGImageSourceGetType(source).map { $0 as String } ?? type",
                 "let way = SharedPhoto.way(type: kind, size: size, room: room, carriesLocation: located)",
                 "case .own:",
                 "staging.written(named: name, mimeType: \"image/jpeg\", expected: size, unnamed: named == .none, { url in",
                 "copied = SharedPhoto.copy(source, type: kind, properties: properties, to: url)",
                 "guard copied == true else { return false }",
                 "still = SharedPhoto.readBack(url)",
                 "return still == nil",
                 "report.went = .own",
                 "return .staged(item)",
                 "report.fellBack = copied == nil ? \"no place on the disk\" : copied == false ? \"CopyImageSource failed\" : still.map { \"the file written \\($0)\" } ?? \"too large for the room as written\"",
                 "case .jpeg: break",
                 "SharedPhoto.jpeg(from: source, at: index, properties: properties, factor: factor)"],
                in: code)
        XCTAssertEqual(count("staging.written(", in: code), 1)
        XCTAssertEqual(count("SharedPhoto.readBack(", in: code), 1)

        let readBack = try part(of: code, from: "static func readBack(", to: "static func availableMemory()")
        inOrder(["guard let written = CGImageSourceCreateWithURL(url as CFURL, reading) else {",
                 "return \"could not be read back\"",
                 "let count = CGImageSourceGetCount(written)",
                 "guard count == 1 else { return \"holds \\(count) pictures\" }",
                 "let properties = CGImageSourceCopyPropertiesAtIndex(written, 0, nil)",
                 "let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]",
                 "let metadata = CGImageSourceCopyMetadataAtIndex(written, 0, nil)",
                 "let says = keepsMoreThanReplaced(properties)",
                 "|| properties[kCGImagePropertyGPSDictionary as String] != nil",
                 "|| properties[kCGImagePropertyIPTCDictionary as String] != nil",
                 "|| properties[kCGImagePropertyMakerAppleDictionary as String] != nil",
                 "|| exif?[kCGImagePropertyExifMakerNote as String] != nil",
                 "|| locationPaths.contains { path in",
                 "CGImageMetadataCopyTagWithPath($0, nil, path as CFString)",
                 "return says ? \"still says more than was kept\" : nil"],
                in: readBack)
    }

    /// The room a picture has is weighed against the memory Send will
    /// build the letter in, read as it is staged, before the way is
    /// decided; and the reason one goes as a JPEG made here is put in its
    /// line. Never the letter's room alone.
    func testTheRoomIsWeighedAgainstSendBeforeTheWay() throws {
        let code = try source("SharedPhotoImageIO.swift")
        inOrder(["let kind = CGImageSourceGetType(source).map { $0 as String } ?? type",
                 "let room = SharedPhoto.sendRoom(room: staging.room, staged: staging.staged, available: SharedPhoto.availableMemory() ?? SharedPhoto.assumedAvailable)",
                 "let way = SharedPhoto.way(type: kind, size: size, room: room, carriesLocation: located)",
                 "report.fellBack = SharedPhoto.notItself(type: kind, size: size, room: staging.room, sendRoom: room, carriesLocation: located)",
                 "switch way {"],
                in: code)
        XCTAssertEqual(count("SharedPhoto.way(", in: code), 1)
        XCTAssertEqual(count("SharedPhoto.sendRoom(", in: code), 1)
    }

    /// The memory left is read before each decode, from the iPad's own
    /// figure, then `task_info`'s, and what neither says is assumed. The
    /// factor it gives is the one the JPEG is made at; none, and the
    /// picture is left out there, counted, never read as its bytes.
    func testTheMemoryLeftIsReadRightBeforeEachDecode() throws {
        let code = try source("SharedPhotoImageIO.swift")
        XCTAssertTrue(code.contains("import os"))
        inOrder(["static func availableMemory() -> Int64? {",
                 "let available = os_proc_available_memory()",
                 "if available > 0 { return Int64(available) }",
                 "guard let info = limited() else { return nil }",
                 "return Int64(clamping: info.limit_bytes_remaining)",
                 "static func memory() -> Memory {",
                 "let least = limited().map { info in",
                 "Int64(clamping: info.phys_footprint) + Int64(clamping: info.limit_bytes_remaining) - info.ledger_phys_footprint_peak",
                 "return Memory(available: availableMemory(), least: least)",
                 "private static func limited() -> task_vm_info_data_t? {",
                 "task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)",
                 "MemoryLayout<task_vm_info_data_t>.offset(of: \\.limit_bytes_remaining)",
                 "info.limit_bytes_remaining > 0 else { return nil }",
                 "return info"],
                in: code)
        inOrder(["case .jpeg: break",
                 "let width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0",
                 "let height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0",
                 "let available = SharedPhoto.availableMemory()",
                 "guard let factor = SharedPhoto.factor(width: width, height: height, type: kind, available: available ?? SharedPhoto.assumedAvailable) else {",
                 "report.went = .tooLargeForMemory(",
                 "needs: SharedPhoto.leastPeak(width: width, height: height, type: kind),",
                 "return .staged(nil)",
                 "report.went = .jpeg(factor: factor, available: available)",
                 "guard let jpeg = SharedPhoto.jpeg(from: source, at: index, properties: properties, factor: factor)"],
                in: code)
        XCTAssertEqual(count("SharedPhoto.availableMemory()", in: code), 2,
                       "for the room at Send, and right before the decode")
        XCTAssertEqual(count("CGImageSourceCreateThumbnailAtIndex(", in: code), 1)
    }

    /// The JPEG: a thumbnail, from the picture itself, of the longest side
    /// `size` gives at the factor it is read at and never more, the factor
    /// passed too where it is one, turned upright, decoded there; encoded
    /// with what `kept` keeps and the quality, and nothing copied from the
    /// picture's file besides.
    func testTheJPEGIsAThumbnailOfAtMost4096UprightWithOnlyWhatIsKept() throws {
        let code = try source("SharedPhotoImageIO.swift")
        inOrder(["let index = CGImageSourceGetPrimaryImageIndex(source)",
                 "guard index < CGImageSourceGetCount(source) else {",
                 "let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)"],
                in: code)
        inOrder(["properties: [String: Any], factor halving: Int) -> Data? {",
                 "let width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0",
                 "let height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0",
                 "let longest = size(width: width, height: height, factor: halving)?.longest ?? longestSide",
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
        XCTAssertEqual(count("factor(longest:", in: code), 0, "the factor is the one handed in")
        for never in ["CGImageDestinationAddImageFromSource",
                      "kCGImageSourceCreateThumbnailFromImageIfAbsent", "CGImageSourceCreateImageAtIndex",
                      "kCGImageSourceShouldCache: true"] {
            XCTAssertFalse(code.contains(never), never)
        }
    }

    /// Its own bytes, whole, or a JPEG as `way` says, by the type the file
    /// says it is, with the room left, and a location looked for three ways
    /// before a GIF or PNG may go whole: the rule's own keys, ImageIO's own
    /// name for GPS, and the XMP.
    func testWholeOnlyAsTheRuleSaysAndNeverWithALocation() throws {
        let code = try source("SharedPhotoImageIO.swift")
        inOrder(["let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil)",
                 "let located = SharedPhoto.carriesLocation(properties)",
                 "|| properties[kCGImagePropertyGPSDictionary as String] != nil",
                 "|| SharedPhoto.locationPaths.contains { path in",
                 "CGImageMetadataCopyTagWithPath($0, nil, path as CFString)",
                 "let kind = CGImageSourceGetType(source).map { $0 as String } ?? type",
                 "let way = SharedPhoto.way(type: kind, size: size, room: room, carriesLocation: located)",
                 "case .whole(_, let mimeType):",
                 "let name = SharedPhoto.name(named, way: way, number: staging.unnamed)",
                 "let item = whole(name, mimeType)",
                 "return .staged(item)",
                 "case .own:",
                 "case .jpeg: break",
                 "let name = SharedPhoto.name(named, way: .jpeg, number: staging.unnamed)",
                 "let item = staging.photo(jpeg, named: name, unnamed: named == .none)",
                 "return .staged(item)"],
                in: code)
        XCTAssertEqual(count("staging.file(", in: code), 1, "a file copied only whole")
        XCTAssertEqual(count("staging.photo(", in: code), 2, "bytes kept whole, and the JPEG")
    }

    /// One line in the log for each picture, as it ends, with the bytes it
    /// staged, and only then the answer; nothing of its metadata in it.
    func testEachPictureLeavesOneLineInTheLog() throws {
        let code = try source("SharedPhotoImageIO.swift")
        let finish = try part(of: code, from: "private static func finish(",
                              to: "private enum Picture {")
        inOrder(["var report = report",
                 "if case .file(_, _, _, let size) = item { report.bytes = size }",
                 "Diagnostics.log(.note, report.line)",
                 "done(item)"],
                in: finish)
        XCTAssertEqual(count("Diagnostics.log(", in: code), 1)
        inOrder(["var report = SharedPhoto.Report(offered: offered, read: type, named: named)",
                 "report.inside = kind"], in: code)
        let photo = try source("SharedPhoto.swift")
        let report = try part(of: photo, from: "struct Report {", to: "private static func megabytes(")
        for never in ["properties", "GPS", "Latitude", "{Exif}"] {
            XCTAssertFalse(report.contains(never), never)
        }
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

    /// Each share's lines in the log begin with a line of their own,
    /// written before the first picture is read: iOS may keep the
    /// extension from one share to the next, and the log is not cleared,
    /// so a send's transcript can hold the share before as well.
    func testEachShareBeginsItsLinesInTheLog() throws {
        let sheet = try source("ShareViewController.swift")
        inOrder(["let staging = Staging()",
                 "for provider in item.attachments ?? [] {",
                 "tally.offered += 1",
                 "Diagnostics.log(.note, \"SHARE-BEGIN offered=\\(loads.count)\")",
                 "oneAtATime(loads) { items in"],
                in: sheet)
        XCTAssertEqual(count("SHARE-BEGIN", in: sheet), 1)
        XCTAssertEqual(count("Diagnostics.clear()", in: sheet), 0,
                       "a failed send's transcript kept for the next")
    }

    /// The sheet is told the extension's memory, as the iPad says it, for
    /// its lines at Send.
    func testTheSheetIsToldTheMemoryForSend() throws {
        let sheet = try source("ShareViewController.swift")
        inOrder(["sheet = ShareSheet(",
                 "transport: TLSConnection.factory,",
                 "memory: { SharedPhoto.memory() },",
                 "noteSent:"],
                in: sheet)
    }
}
