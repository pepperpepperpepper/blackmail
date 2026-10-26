import XCTest
@testable import Blackmail

/// What Photo Library hands over as Photos keeps it (B-142): no copy asked
/// of Photos (`.current`), whose compatible copy held a file coordination
/// claim on the app that calling the read off did not end, and a video
/// made H.264 in the app instead, from the staged original, where the read
/// calls it off (`ShareItems.stageRead`, `compatible`).
///
/// The routing runs here, through the shipping staging and read handle,
/// with the test's own conversion; AVFoundation's side, which never builds
/// on this host, is read from its source. What goes is H.264 or nothing:
/// the copy at its own size, else a 720p one, else the video left out, as
/// B-108 left out a compatible copy over the room. A photo goes as before:
/// a HEIC with no JPEG beside it is made a JPEG in the app, under the same
/// name, at its own size where it fits, as Photos' JPEG of it went.
final class VideoCompatibleTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        Diagnostics.clear()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("VideoCompatibleTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Staged in the test's own directory, each file in a directory of its
    /// own, as `AttachmentStore` stages them; what was taken away, kept.
    private final class Disk {
        let directory: URL
        private(set) var copied: [String] = []
        private(set) var discarded: [URL] = []

        init(_ directory: URL) { self.directory = directory }

        private func folder() throws -> URL {
            let folder = directory.appendingPathComponent("staged", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }

        func copy(_ source: URL, _ filename: String) throws -> URL {
            let url = try folder().appendingPathComponent(filename)
            try FileManager.default.copyItem(at: source, to: url)
            copied.append(filename)
            return url
        }

        func place(_ filename: String) throws -> URL {
            try folder().appendingPathComponent(filename)
        }

        func write(_ data: Data, _ filename: String) throws -> URL {
            let url = try folder().appendingPathComponent(filename)
            try data.write(to: url)
            return url
        }

        func discard(_ url: URL) {
            discarded.append(url)
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }

    private func staging(_ disk: Disk, room: Int64 = ShareItems.Staging.budget) -> ShareItems.Staging {
        ShareItems.Staging(room: room, write: disk.write, copy: disk.copy, place: disk.place,
                           discard: disk.discard)
    }

    /// A file of `bytes` the provider hands over, as Photos hands over the
    /// video it keeps.
    private func given(_ name: String, bytes: Int64) throws -> URL {
        let folder = directory.appendingPathComponent("given-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Self.sized(url, bytes)
        return url
    }

    static func sized(_ url: URL, _ bytes: Int64) throws {
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(bytes))
        try handle.close()
    }

    private final class Got {
        var calls = 0
        var item: SharedItem?
        func take(_ item: SharedItem?) {
            calls += 1
            self.item = item
        }
    }

    /// A video read as Photos keeps it, `bytes` long, through the share
    /// sheet's staging of a provider's file, made H.264 by `videos`.
    private func read(_ url: URL, bytes: Int64, staging: ShareItems.Staging,
                      loading: ShareItems.Loading = ShareItems.Loading(),
                      videos: ShareItems.VideoConversion?) -> Got {
        let got = Got()
        ShareItems.stageRead(url, size: bytes, type: "com.apple.quicktime-movie", suggested: true,
                             name: url.lastPathComponent, mimeType: "video/quicktime",
                             videos: videos, staging: staging, loading: loading, done: got.take)
        return got
    }

    private func notes() -> [String] {
        Diagnostics.entries.filter { $0.direction == .note }.map(\.text)
            .filter { $0.hasPrefix("SHARE-FILE") || $0.hasPrefix("SHARE-VIDEO") }
    }

    private func exists(_ url: URL?) -> Bool {
        url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    // MARK: - The routing

    /// The original fits and its H.264 copy fits: the copy goes, in the
    /// original's place, under its name and type, and the original staged
    /// is taken away, its room given back. The conversion is begun from
    /// the staged copy of the original, never from the file the provider
    /// handed over, which is let go as the read's call back returns; it
    /// writes as QuickTime, a ".MOV" staying one.
    func testAVideoThatFitsIsMadeH264AndItsCopyGoesInItsPlace() throws {
        let disk = Disk(directory)
        let staging = staging(disk)
        let conversion = FakeVideoConversion()
        let original = try given("IMG_0195.MOV", bytes: 12_000_000)

        let got = read(original, bytes: 12_000_000, staging: staging, videos: conversion.videos)
        XCTAssertEqual(got.calls, 0, "not before its conversion has ended")
        let asked = try XCTUnwrap(conversion.asked.last)
        XCTAssertEqual(conversion.asked.count, 1)
        XCTAssertNotEqual(asked.from, original, "from the staged copy")
        XCTAssertTrue(asked.from.path.hasPrefix(directory.appendingPathComponent("staged").path))
        XCTAssertTrue(exists(asked.from))
        XCTAssertEqual(asked.to.lastPathComponent, "IMG_0195.MOV")
        XCTAssertNotEqual(asked.to.deletingLastPathComponent(), asked.from.deletingLastPathComponent())
        XCTAssertFalse(exists(asked.to))
        XCTAssertEqual(asked.fileType, "com.apple.quicktime-movie")
        XCTAssertEqual(asked.copy, .ownSize, "at its own size first")
        XCTAssertEqual(asked.limit, 30_000_000, "stopped 5 MB past the room the original had")
        XCTAssertEqual(staging.staged, 12_000_000)

        try conversion.make(bytes: 18_000_000)
        XCTAssertEqual(got.calls, 1)
        XCTAssertEqual(got.item, .file(asked.to, filename: "IMG_0195.MOV", mimeType: "video/quicktime",
                                       size: 18_000_000))
        XCTAssertTrue(exists(asked.to))
        XCTAssertFalse(exists(asked.from), "the original taken away")
        XCTAssertEqual(staging.staged, 18_000_000, "the copy's weight, not both")
        XCTAssertEqual(notes(), [
            "SHARE-FILE read=com.apple.quicktime-movie name=suggested \"IMG_0195.MOV\" "
                + "mime=video/quicktime bytes=12000000 went=staged",
            "SHARE-VIDEO made H.264, bytes=18000000 from=12000000 codec=avc1"])
    }

    /// The original fits and its H.264 copy at its own size does not: a
    /// second copy, of at most 1280 by 720, with the same room and limit,
    /// and that goes where it fits. The room is what the original had, the
    /// rows before it in it: a copy of exactly that goes, one a byte over
    /// does not. A copy cut short at its limit is never taken, even where
    /// it measures within the room: a video cut short does not go.
    func testACopyOverTheRoomIsMadeAgainAt720pAndThatGoesWhereItFits() throws {
        let disk = Disk(directory)
        let staging = staging(disk, room: 20_000_000)
        XCTAssertNotNil(staging.photo(Data(count: 5_000_000), named: "IMG_0001.JPG"))
        let conversion = FakeVideoConversion()

        let first = try given("IMG_0196.MOV", bytes: 12_000_000)
        let fits = read(first, bytes: 12_000_000, staging: staging, videos: conversion.videos)
        let fitting = try XCTUnwrap(conversion.asked.last)
        XCTAssertEqual(fitting.limit, 20_000_000, "the room it had, 15 MB, and 5")
        try conversion.make(bytes: 15_000_000)
        XCTAssertEqual(conversion.asked.count, 1, "no second copy")
        XCTAssertEqual(fits.item, .file(fitting.to, filename: "IMG_0196.MOV",
                                        mimeType: "video/quicktime", size: 15_000_000),
                       "exactly the room the original had")
        XCTAssertEqual(staging.staged, 20_000_000)
        staging.unstage(try XCTUnwrap(fits.item))
        XCTAssertEqual(staging.staged, 5_000_000)

        for cutShort in [false, true] {
            Diagnostics.clear()
            let second = try given("IMG_0197.MOV", bytes: 12_000_000)
            let over = read(second, bytes: 12_000_000, staging: staging, videos: conversion.videos)
            let own = try XCTUnwrap(conversion.asked.last)
            if cutShort {
                try VideoCompatibleTests.sized(own.to, 14_000_000)
                conversion.end(.cutShort)
            } else {
                try conversion.make(bytes: 15_000_001)
            }
            XCTAssertEqual(over.calls, 0, "not yet: a smaller copy")
            XCTAssertFalse(exists(own.to), "the first copy taken away")
            let small = try XCTUnwrap(conversion.asked.last)
            XCTAssertEqual(conversion.asked.count, cutShort ? 5 : 3)
            XCTAssertEqual(small.copy, .at720p)
            XCTAssertEqual(small.from, own.from, "from the staged original again")
            XCTAssertEqual(small.limit, 20_000_000)
            XCTAssertEqual(small.fileType, "com.apple.quicktime-movie")
            XCTAssertNotEqual(small.to, own.to)
            try conversion.make(bytes: 9_000_000)
            XCTAssertEqual(over.calls, 1)
            XCTAssertEqual(over.item, .file(small.to, filename: "IMG_0197.MOV",
                                            mimeType: "video/quicktime", size: 9_000_000),
                           "the 720p copy goes, under its name and type")
            XCTAssertFalse(exists(own.from), "the original taken away")
            XCTAssertEqual(staging.staged, 14_000_000)
            XCTAssertEqual(notes(), [
                "SHARE-FILE read=com.apple.quicktime-movie name=suggested \"IMG_0197.MOV\" "
                    + "mime=video/quicktime bytes=12000000 went=staged",
                cutShort
                    ? "SHARE-VIDEO its H.264 copy cut short at its limit, bytes=14000000, with the "
                        + "letter's room, 15 MB left: a 720p copy"
                    : "SHARE-VIDEO its H.264 copy bytes=15000001, more than the letter's room, "
                        + "15 MB left: a 720p copy",
                "SHARE-VIDEO made H.264 at 720p, bytes=9000000 from=12000000 codec=avc1"])
            staging.unstage(try XCTUnwrap(over.item))
        }
    }

    /// Neither copy fits: the video is left out, as B-108 left out Photos'
    /// copy over the room, the original, HEVC, never going in their place.
    /// The original and both copies are taken away and the room given
    /// back; nothing goes, and the composer says the video could not be
    /// attached. A copy that reads back as not H.264, or a conversion that
    /// fails, the same: nothing goes but H.264.
    func testAVideoWithNoH264CopyThatFitsIsLeftOutNotSentAsItsOriginal() throws {
        let disk = Disk(directory)
        let staging = staging(disk, room: 20_000_000)
        let conversion = FakeVideoConversion()

        let original = try given("IMG_0198.MOV", bytes: 18_000_000)
        let got = read(original, bytes: 18_000_000, staging: staging, videos: conversion.videos)
        let own = try XCTUnwrap(conversion.asked.last)
        try conversion.make(bytes: 24_000_000)
        let small = try XCTUnwrap(conversion.asked.last)
        XCTAssertEqual(small.copy, .at720p)
        try VideoCompatibleTests.sized(small.to, 20_000_002)
        conversion.end(.cutShort)
        XCTAssertEqual(got.calls, 1)
        XCTAssertNil(got.item, "left out")
        XCTAssertEqual(conversion.asked.count, 2, "no third copy")
        XCTAssertFalse(exists(own.from), "the original taken away")
        XCTAssertFalse(exists(own.to))
        XCTAssertFalse(exists(small.to))
        XCTAssertEqual(staging.staged, 0, "the room given back")
        XCTAssertEqual(notes(), [
            "SHARE-FILE read=com.apple.quicktime-movie name=suggested \"IMG_0198.MOV\" "
                + "mime=video/quicktime bytes=18000000 went=staged",
            "SHARE-VIDEO its H.264 copy bytes=24000000, more than the letter's room, 20 MB left: "
                + "a 720p copy",
            "SHARE-VIDEO its 720p H.264 copy cut short at its limit, bytes=20000002, with the "
                + "letter's room, 20 MB left: left out"])

        Diagnostics.clear()
        let again = read(try given("IMG_0199.MOV", bytes: 18_000_000), bytes: 18_000_000,
                         staging: staging, videos: conversion.videos)
        try conversion.make(bytes: 21_000_000)
        try conversion.make(bytes: 20_000_001)
        XCTAssertNil(again.item)
        XCTAssertEqual(staging.staged, 0)
        XCTAssertEqual(notes().last, "SHARE-VIDEO its 720p H.264 copy bytes=20000001, more than "
                                     + "the letter's room, 20 MB left: left out")

        for (said, line) in [(ShareItems.Converted.made(codecs: ["hvc1"]),
                              "SHARE-VIDEO its copy read back as hvc1, not H.264: left out"),
                             (.failed(code: -11800),
                              "SHARE-VIDEO not made H.264, failed code=-11800: left out"),
                             (.failed(code: nil),
                              "SHARE-VIDEO not made H.264, failed: left out")] {
            Diagnostics.clear()
            let loading = ShareItems.Loading()
            let got = read(try given("IMG_0200.MOV", bytes: 2_000_000), bytes: 2_000_000,
                           staging: staging, loading: loading, videos: conversion.videos)
            let asked = try XCTUnwrap(conversion.asked.last)
            if said == .made(codecs: ["hvc1"]) { try VideoCompatibleTests.sized(asked.to, 1_000) }
            conversion.end(said)
            XCTAssertEqual(got.calls, 1)
            XCTAssertNil(got.item, "\(said)")
            XCTAssertFalse(exists(asked.from))
            XCTAssertFalse(exists(asked.to))
            XCTAssertEqual(staging.staged, 0)
            XCTAssertFalse(loading.wasInterrupted)
            XCTAssertEqual(notes().last, line)
        }
    }

    /// The original does not fit: left out at once after the read, as
    /// before, never copied, and nothing made of it.
    func testAVideoLargerThanTheRoomIsLeftOutAtOnceAndNothingIsMade() throws {
        let disk = Disk(directory)
        let staging = staging(disk)
        let conversion = FakeVideoConversion()
        let original = try given("IMG_0185.MOV", bytes: 750_122_885)

        let got = read(original, bytes: 750_122_885, staging: staging, videos: conversion.videos)
        XCTAssertEqual(got.calls, 1, "at once")
        XCTAssertNil(got.item)
        XCTAssertEqual(conversion.asked.count, 0, "no conversion")
        XCTAssertEqual(disk.copied, [], "never copied")
        XCTAssertEqual(staging.staged, 0)
        XCTAssertEqual(notes(), [
            "SHARE-FILE read=com.apple.quicktime-movie name=suggested \"IMG_0185.MOV\" "
                + "mime=video/quicktime bytes=750122885 went=left out, more than the letter's "
                + "room, 25 MB left"])
    }

    /// The read called off while its video is made H.264, as the app goes,
    /// at a count-out or as the letter closes: the conversion is called off
    /// with it, and whatever it then says, nothing goes, the original and
    /// the copy taken away and the room given back. Called off before its
    /// conversion could begin, none is begun. A conversion handed over
    /// after the read was called off is called off at once.
    func testCallingTheReadOffCallsOffItsConversion() throws {
        let disk = Disk(directory)
        let staging = staging(disk)
        let conversion = FakeVideoConversion()

        for said in [ShareItems.Converted.cancelled, .made(codecs: ["avc1"]), .cutShort, .interrupted,
                     .failed(code: -11800)] {
            Diagnostics.clear()
            let loading = ShareItems.Loading()
            let original = try given("IMG_0201.MOV", bytes: 3_000_000)
            let got = read(original, bytes: 3_000_000, staging: staging, loading: loading,
                           videos: conversion.videos)
            let asked = try XCTUnwrap(conversion.asked.last)
            let before = conversion.calledOff
            loading.cancel()
            XCTAssertEqual(conversion.calledOff, before + 1, "called off with the read")
            XCTAssertEqual(got.calls, 0)
            if said == .made(codecs: ["avc1"]) || said == .cutShort {
                try VideoCompatibleTests.sized(asked.to, 4_000_000)
            }
            conversion.end(said)
            XCTAssertEqual(got.calls, 1)
            XCTAssertNil(got.item, "\(said)")
            XCTAssertFalse(exists(asked.from), "the original taken away")
            XCTAssertFalse(exists(asked.to), "and the copy")
            XCTAssertEqual(staging.staged, 0, "the room given back")
            XCTAssertFalse(loading.wasInterrupted)
            XCTAssertEqual(notes().last, "SHARE-VIDEO called off")
        }

        // Called off while its 720p copy is made: that copy called off.
        Diagnostics.clear()
        let second = ShareItems.Loading()
        let got = read(try given("IMG_0203.MOV", bytes: 3_000_000), bytes: 3_000_000,
                       staging: staging, loading: second, videos: conversion.videos)
        try conversion.make(bytes: 26_000_000)
        let small = try XCTUnwrap(conversion.asked.last)
        XCTAssertEqual(small.copy, .at720p)
        let before = conversion.calledOff
        second.cancel()
        XCTAssertEqual(conversion.calledOff, before + 2, "both copies' call-offs, the second's live")
        try VideoCompatibleTests.sized(small.to, 1_000)
        conversion.end(.made(codecs: ["avc1"]))
        XCTAssertEqual(got.calls, 1)
        XCTAssertNil(got.item)
        XCTAssertFalse(exists(small.from))
        XCTAssertFalse(exists(small.to))
        XCTAssertEqual(staging.staged, 0)
        XCTAssertEqual(notes().last, "SHARE-VIDEO called off")

        Diagnostics.clear()
        let early = ShareItems.Loading()
        early.cancel()
        let asked = conversion.asked.count
        let none = read(try given("IMG_0202.MOV", bytes: 1_000), bytes: 1_000, staging: staging,
                        loading: early, videos: conversion.videos)
        XCTAssertEqual(conversion.asked.count, asked, "none begun")
        XCTAssertEqual(none.calls, 1)
        XCTAssertNil(none.item)
        XCTAssertEqual(staging.staged, 0)
        XCTAssertEqual(notes().last, "SHARE-VIDEO called off")

        var after = 0
        early.track(conversion: { after += 1 })
        XCTAssertEqual(after, 1, "handed over after the call-off, called off at once")
        let live = ShareItems.Loading()
        live.track(Progress(totalUnitCount: 1))
        live.track(conversion: { after += 1 })
        XCTAssertEqual(after, 1)
        live.cancel()
        XCTAssertEqual(after, 2, "with the loads")
    }

    /// A video H.264 already goes as it came, as Photos' compatible copy
    /// left one (the round's IMG_0206, an H.264 .mp4), at once, with no
    /// copy made; the copy's place is taken away.
    func testAVideoH264AlreadyGoesAsItCame() throws {
        let disk = Disk(directory)
        let staging = staging(disk)
        let conversion = FakeVideoConversion()
        let original = try given("IMG_0206.mp4", bytes: 2_000_000)
        let loading = ShareItems.Loading()
        let got = read(original, bytes: 2_000_000, staging: staging, loading: loading,
                       videos: conversion.videos)
        let asked = try XCTUnwrap(conversion.asked.last)
        XCTAssertEqual(asked.fileType, "public.mpeg-4", "an .mp4 written as one")
        conversion.end(.notNeeded)
        XCTAssertEqual(conversion.asked.count, 1)
        XCTAssertEqual(got.item, .file(asked.from, filename: "IMG_0206.mp4",
                                       mimeType: "video/quicktime", size: 2_000_000))
        XCTAssertTrue(exists(asked.from))
        XCTAssertTrue(disk.discarded.contains(asked.to))
        XCTAssertFalse(loading.wasInterrupted)
        XCTAssertEqual(notes().last, "SHARE-VIDEO goes as it came, H.264 already")
    }

    /// AVFoundation stops the conversion as the app goes into the
    /// background, an encoder being what an app gives up there: the
    /// original is handed back, the copy taken away, and the read marked
    /// so (`wasInterrupted`), for the composer to set it aside while the
    /// app is away rather than take it (`ComposeIntake`).
    func testAConversionStoppedAsTheAppGoesHandsBackTheOriginalMarked() throws {
        let disk = Disk(directory)
        let staging = staging(disk)
        let conversion = FakeVideoConversion()
        let loading = ShareItems.Loading()
        let got = read(try given("IMG_0226.MOV", bytes: 9_000_000), bytes: 9_000_000,
                       staging: staging, loading: loading, videos: conversion.videos)
        let asked = try XCTUnwrap(conversion.asked.last)
        XCTAssertFalse(loading.wasInterrupted)
        conversion.end(.interrupted)
        XCTAssertTrue(loading.wasInterrupted)
        XCTAssertFalse(loading.isCancelled)
        XCTAssertEqual(got.item, .file(asked.from, filename: "IMG_0226.MOV",
                                       mimeType: "video/quicktime", size: 9_000_000))
        XCTAssertFalse(exists(asked.to))
        XCTAssertEqual(notes().last, "SHARE-VIDEO not made H.264, stopped as the app went")
    }

    /// With no conversion, the share sheet's: a video goes as the sharing
    /// app handed it over, at once, as before; Photos hands the sheet its
    /// own H.264 copy (B-070).
    func testWithNoConversionAVideoGoesAsItCame() throws {
        let disk = Disk(directory)
        let staging = staging(disk)
        let got = read(try given("IMG_7001.MOV", bytes: 19_284_661), bytes: 19_284_661,
                       staging: staging, videos: nil)
        XCTAssertEqual(got.calls, 1)
        guard case let .file(url, filename, mimeType, size)? = got.item else {
            return XCTFail("not staged")
        }
        XCTAssertTrue(exists(url))
        XCTAssertEqual(filename, "IMG_7001.MOV")
        XCTAssertEqual(mimeType, "video/quicktime")
        XCTAssertEqual(size, 19_284_661)
        XCTAssertEqual(notes().count, 1, "no SHARE-VIDEO line")
    }

    /// Which videos are made H.264: any whose pictures are not H.264
    /// already, HEVC above all, and not one H.264 already or with no
    /// pictures. The codec's four letters as CoreMedia gives them, and the
    /// file type the copy is written as, by the name's extension.
    func testWhatIsMadeH264AndAsWhatFile() {
        XCTAssertTrue(ShareItems.needsH264(codecs: ["hvc1"]), "HEVC, as an iPad films")
        XCTAssertTrue(ShareItems.needsH264(codecs: ["hev1"]))
        XCTAssertTrue(ShareItems.needsH264(codecs: ["dvh1"]), "Dolby Vision's HEVC")
        XCTAssertTrue(ShareItems.needsH264(codecs: ["apcn"]), "ProRes")
        XCTAssertTrue(ShareItems.needsH264(codecs: ["avc1", "hvc1"]))
        XCTAssertFalse(ShareItems.needsH264(codecs: ["avc1"]))
        XCTAssertFalse(ShareItems.needsH264(codecs: ["avc3", "avc1"]))
        XCTAssertFalse(ShareItems.needsH264(codecs: []), "no pictures")

        XCTAssertEqual(ShareItems.fourCC(0x6876_6331), "hvc1")
        XCTAssertEqual(ShareItems.fourCC(0x6176_6331), "avc1")
        XCTAssertEqual(ShareItems.fourCC(0x0000_0000), "????")

        XCTAssertEqual(ShareItems.exportType(for: "IMG_0195.MOV"), "com.apple.quicktime-movie")
        XCTAssertEqual(ShareItems.exportType(for: "IMG_0195.mov"), "com.apple.quicktime-movie")
        XCTAssertEqual(ShareItems.exportType(for: "Clip.mp4"), "public.mpeg-4")
        XCTAssertEqual(ShareItems.exportType(for: "Clip.M4V"), "com.apple.m4v-video")
        XCTAssertEqual(ShareItems.exportType(for: "Clip"), "com.apple.quicktime-movie")
    }

    // MARK: - A photo, as before

    /// A photo picked as Photos keeps it goes out as before, a JPEG under
    /// the name Photos' compatible JPEG went by. A HEIC, offered with no
    /// JPEG beside it, is read as HEIC and made a JPEG in the app, at its
    /// own size, a camera's 4032 by 3024 decoded whole with the memory an
    /// app has, and named "IMG_0772.jpg", the name the compatible JPEG went
    /// by as its own bytes. A JPEG kept as one goes as its own bytes, as
    /// before; where Photos offers a JPEG beside a HEIC, the JPEG.
    func testAPhotoPickedAsPhotosKeepsItGoesAsBefore() {
        let budget = ShareItems.Staging.budget
        XCTAssertEqual(SharedPhoto.fileType(offered: ["public.heic"]), "public.heic")
        XCTAssertEqual(SharedPhoto.way(type: "public.heic", size: 2_400_000, room: budget,
                                       carriesLocation: false), .jpeg)
        XCTAssertEqual(SharedPhoto.way(type: "public.heic", size: 2_400_000, room: budget,
                                       carriesLocation: true), .jpeg)
        let heic = SharedPhoto.named(suggested: "IMG_0772", file: "IMG_0772.HEIC")
        let compatible = SharedPhoto.named(suggested: "IMG_0772", file: "IMG_0772.jpeg")
        XCTAssertEqual(SharedPhoto.name(heic, way: .jpeg, number: 0), "IMG_0772.jpg")
        XCTAssertEqual(SharedPhoto.name(compatible, way: .own, number: 0), "IMG_0772.jpg",
                       "the name it went by before")
        let most = SharedPhoto.most(.ownSizeWhereItFits, size: 2_400_000, room: budget)
        XCTAssertEqual(SharedPhoto.size(width: 4032, height: 3024, most: most),
                       .init(width: 4032, height: 3024))
        XCTAssertEqual(SharedPhoto.factor(width: 4032, height: 3024, type: "public.heic",
                                          available: 1_000_000_000, most: most), 1)

        XCTAssertEqual(SharedPhoto.fileType(offered: ["public.jpeg"]), "public.jpeg")
        XCTAssertEqual(SharedPhoto.way(type: "public.jpeg", size: 2_400_000, room: budget,
                                       carriesLocation: true), .own)
        XCTAssertEqual(SharedPhoto.fileType(offered: ["public.heic", "public.jpeg"]), "public.jpeg")
        XCTAssertEqual(ComposeIntake.kind(offered: ["public.heic"], isMovie: { _ in false }), .picture)
    }

    /// A HEIC larger than 4096 px goes at its own size from the composer,
    /// as Photos' JPEG of it went whole as its own bytes before the picker
    /// took what Photos keeps: a 24-megapixel iPhone photo, 5712 by 4284,
    /// whole, not 2856 by 2142; a 48-megapixel one, 8064 by 6048, whole,
    /// not 4032; and a panorama from his iPad, 13000 by 2900, whole, not
    /// 3250. Read at 1 where the memory allows it, the app's, and at a
    /// half where it does not. The share sheet, in an extension's memory,
    /// keeps them at 4096 px at most, as before. A HEIC over the room, as
    /// a JPEG over the room before, at 4096 px at most; and one made at its
    /// own size whose JPEG is over the room made again at 4096 px, where
    /// that is smaller. The composer's staging is the one that lets them
    /// go whole; a share's is not.
    func testAPhotoOver4096PxGoesAtItsOwnSizeFromTheComposer() {
        let budget = ShareItems.Staging.budget
        let room = SharedPhoto.most(.ownSizeWhereItFits, size: 6_000_000, room: budget)
        XCTAssertEqual(room, SharedPhoto.ownSize)
        let sheet = SharedPhoto.most(.longestSide, size: 6_000_000, room: budget)
        XCTAssertEqual(sheet, 4096)
        let app: Int64 = 1_200_000_000

        for (width, height, capped) in [(5712, 4284, SharedPhoto.Size(width: 2856, height: 2142)),
                                        (8064, 6048, SharedPhoto.Size(width: 4032, height: 3024)),
                                        (13000, 2900, SharedPhoto.Size(width: 3250, height: 725)),
                                        (2900, 13000, SharedPhoto.Size(width: 725, height: 3250))] {
            let whole = SharedPhoto.Size(width: width, height: height)
            XCTAssertEqual(SharedPhoto.factor(width: width, height: height, type: "public.heic",
                                              available: app, most: room), 1, "\(width)")
            XCTAssertEqual(SharedPhoto.size(width: width, height: height, factor: 1, most: room),
                           whole, "the composer: its own size")
            XCTAssertEqual(SharedPhoto.size(width: width, height: height, most: room), whole)
            XCTAssertEqual(SharedPhoto.size(width: width, height: height, most: sheet), capped,
                           "the share sheet: as before")
            XCTAssertEqual(SharedPhoto.size(width: width, height: height), capped)
            XCTAssertEqual(SharedPhoto.again(width: width, height: height, factor: 1, most: room),
                           4096, "over the room, made again at 4096")
            XCTAssertNil(SharedPhoto.again(width: width, height: height, factor: 1, most: sheet))
        }
        // The memory: a 48-megapixel HEIC whole holds about 283 MB; with
        // 400 MB left it is read at a half, 4032, and goes so. A panorama
        // read at a half goes at a half of its own size, 6500, not at the
        // share sheet's 4096 or less.
        XCTAssertEqual(SharedPhoto.factor(width: 13000, height: 2900, type: "public.heic",
                                          available: 300_000_000, most: room), 2)
        XCTAssertEqual(SharedPhoto.size(width: 13000, height: 2900, factor: 2, most: room),
                       .init(width: 6500, height: 1450))
        XCTAssertEqual(SharedPhoto.size(width: 13000, height: 2900, factor: 2, most: sheet),
                       .init(width: 3250, height: 725))
        XCTAssertEqual(SharedPhoto.factor(width: 8064, height: 6048, type: "public.heic",
                                          available: 400_000_000, most: room), 2)
        XCTAssertEqual(SharedPhoto.size(width: 8064, height: 6048, factor: 2, most: room),
                       .init(width: 4032, height: 3024))
        XCTAssertNil(SharedPhoto.again(width: 8064, height: 6048, factor: 2, most: room),
                     "no smaller at 4096")
        XCTAssertNil(SharedPhoto.again(width: 4032, height: 3024, factor: 1, most: room),
                     "a camera's photo is 4096 px or less already")

        XCTAssertEqual(SharedPhoto.most(.ownSizeWhereItFits, size: 26_000_000, room: budget), 4096,
                       "over the room as it is: at 4096 at most, as before")
        XCTAssertEqual(SharedPhoto.most(.ownSizeWhereItFits, size: 0, room: budget), 4096,
                       "its size not known")

        XCTAssertEqual(ShareItems.Staging().photos, .longestSide, "a share's")
        XCTAssertEqual(ComposeIntake.staging(room: budget, unnamed: 0, moves: false).photos,
                       .ownSizeWhereItFits, "the composer's")

        var report = SharedPhoto.Report(offered: ["public.heic"], read: "public.heic",
                                        named: .suggested("IMG_0901"))
        report.name = "IMG_0901.jpg"
        report.went = .jpeg(factor: 1, available: app)
        report.made = .init(width: 5712, height: 4284)
        report.bytes = 7_400_000
        XCTAssertEqual(report.line, "SHARE-PICTURE offered=public.heic read=public.heic "
                       + "name=suggested \"IMG_0901.jpg\" way=JPEG at factor 1, 1200 MB available "
                       + "size=5712x4284 bytes=7400000")
        report.went = .jpeg(factor: 2, available: app)
        report.made = .init(width: 2856, height: 2142)
        report.ownSizeOverRoom = 26_100_000
        report.bytes = 2_100_000
        XCTAssertEqual(report.line, "SHARE-PICTURE offered=public.heic read=public.heic "
                       + "name=suggested \"IMG_0901.jpg\" way=JPEG at factor 2, 1200 MB available "
                       + "(at its own size 26100000 bytes, more than the letter's room) "
                       + "size=2856x2142 bytes=2100000")
    }

    // MARK: - The wiring, read from the source

    private var ios: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
    }

    /// Comment lines out, runs of white space as one space.
    private func source(_ path: String) throws -> String {
        try String(contentsOf: ios.appendingPathComponent(path), encoding: .utf8)
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

    private func count(_ text: String, in code: String) -> Int {
        code.components(separatedBy: text).count - 1
    }

    /// AVFoundation's conversion: the video tracks' codecs read without
    /// blocking, the decision the suite's (`needsH264`), then an export
    /// session at the preset the copy asks, the highest quality at its own
    /// size and 1280x720 for the second, both H.264, written as the file
    /// type asked where the session can, for a network, stopped at the
    /// limit it is handed; begun under the lock unless called off first,
    /// and called off by `cancelExport`; stopped as the app went said so
    /// by AVFoundation's own code. Written, its length is read back beside
    /// the video's, shorter by more than half a second taken as cut short,
    /// and its codecs read back for the routing and the log. No API newer
    /// than the SDK, so nothing behind `#available`.
    func testTheConversionIsAVFoundationsExportCalledOffByTheRead() throws {
        let code = try source("Sources/Blackmail/Share/VideoH264.swift")
        inOrder(["#if canImport(UIKit) && canImport(AVFoundation)",
                 "import AVFoundation",
                 "static let h264 = ShareItems.VideoConversion { from, to, fileType, copy, limit, done in",
                 "let export = H264Export()",
                 "let asset = AVURLAsset(url: from)",
                 "asset.loadTracks(withMediaType: .video) { tracks, error in",
                 "return done(.failed(code: (error as NSError?)?.code))",
                 "guard let found = await ShareItems.VideoConversion.codecs(of: tracks) else {",
                 "guard ShareItems.needsH264(codecs: found) else { return done(.notNeeded) }",
                 "let preset = copy == .ownSize ? AVAssetExportPresetHighestQuality : "
                    + "AVAssetExportPreset1280x720",
                 "export.begin(asset, preset: preset, to: to, fileType: fileType, limit: limit, "
                    + "done: done)",
                 "return { export.cancel() }",
                 "fileprivate static func codecs(of tracks: [AVAssetTrack]) async -> [String]? {",
                 "try? await track.load(.formatDescriptions)",
                 "ShareItems.fourCC(CMFormatDescriptionGetMediaSubType($0))",
                 "fileprivate static func readBack(_ asset: AVAsset, _ url: URL,",
                 "let copy = AVURLAsset(url: url)",
                 "if let whole = try? await asset.load(.duration),",
                 "let written = try? await copy.load(.duration),",
                 "whole.isNumeric, written.isNumeric,",
                 "CMTimeGetSeconds(written) < CMTimeGetSeconds(whole) - ShareItems.cutShortBy {",
                 "return done(.cutShort)",
                 "let tracks = (try? await copy.loadTracks(withMediaType: .video)) ?? []",
                 "let found = await ShareItems.VideoConversion.codecs(of: tracks) ?? []",
                 "done(.made(codecs: found))"], in: code)
        inOrder(["func begin(_ asset: AVAsset, preset: String, to: URL, fileType: String, limit: Int64,",
                 "AVAssetExportSession(asset: asset, presetName: preset)",
                 "let asked = AVFileType(rawValue: fileType)",
                 "let types = session.supportedFileTypes",
                 "types.contains(asked) ? asked : types.contains(.mov) ? .mov : nil",
                 "session.outputURL = to",
                 "session.outputFileType = type",
                 "session.shouldOptimizeForNetworkUse = true",
                 "session.fileLengthLimit = limit",
                 "lock.lock()",
                 "defer { lock.unlock() }",
                 "guard !cancelled else { return done(.cancelled) }",
                 "self.session = session",
                 "session.exportAsynchronously {",
                 "case .completed: ShareItems.VideoConversion.readBack(asset, to, done: done)",
                 "case .cancelled: done(.cancelled)",
                 "&& error?.code == AVError.Code.operationInterrupted.rawValue",
                 "done(interrupted ? .interrupted : .failed(code: error?.code))",
                 "func cancel() {",
                 "cancelled = true",
                 "let session = self.session",
                 "lock.unlock()",
                 "session?.cancelExport()"], in: code)
        XCTAssertEqual(count("AVAssetExportPreset", in: code), 2, "two presets, both H.264")
        XCTAssertFalse(code.contains("HEVC"), "no HEVC preset")
        XCTAssertFalse(code.contains("#available"))
        XCTAssertEqual(count("fileLengthLimit = limit", in: code), 1)
        XCTAssertEqual(ShareItems.copyMargin, 5_000_000)
        XCTAssertEqual(ShareItems.cutShortBy, 0.5)

        let items = try source("Sources/Blackmail/Share/ShareItems.swift")
        inOrder(["static func compatible(_ original: SharedItem, staging: Staging, loading: Loading,",
                 "let room = staging.room + size",
                 "func make(_ which: VideoCopy) {",
                 "guard !loading.isCancelled else { return calledOff(nil) }",
                 "let callOff = conversion.convert(url, copy, exportType(for: filename), which, "
                    + "room + copyMargin) { converted in",
                 "guard !loading.isCancelled else { return calledOff(copy) }",
                 "loading.track(conversion: callOff)",
                 "make(.ownSize)"], in: items)
    }

    /// The composer hands its video conversion to the read; the share
    /// sheet hands none, so what it is shared goes as the sharing app hands
    /// it over; the read's video branch hands it on for a video alone.
    func testTheComposerMakesVideosH264AndTheShareSheetDoesNot() throws {
        let composer = try source("Sources/Blackmail/UI/ComposeViewController.swift")
        XCTAssertEqual(count("videos: .h264", in: composer), 1)
        XCTAssertTrue(composer.contains("config.preferredAssetRepresentationMode = .current"))
        let share = try source("Sources/Blackmail/Share/ShareViewController.swift")
        XCTAssertEqual(count("videos: nil", in: share), 1)
        XCTAssertEqual(count("videos: .h264", in: share), 0)
        XCTAssertTrue(share.contains("read(provider, title: title, staging: staging, tally: tally, "
                                     + "videos: nil, done: done)"))
        XCTAssertTrue(share.contains("videos: movie != nil ? videos : nil"))
        XCTAssertEqual(count("stageRead(", in: share), 1)
    }
}

/// A video conversion that waits for the test: what it was asked, each
/// answered by `make` or `end`, and how often it was called off.
final class FakeVideoConversion {
    struct Asked: Equatable {
        let from: URL
        let to: URL
        let fileType: String
        let copy: ShareItems.VideoCopy
        let limit: Int64
    }

    private(set) var asked: [Asked] = []
    private var dones: [(ShareItems.Converted) -> Void] = []
    private(set) var calledOff = 0

    var videos: ShareItems.VideoConversion {
        ShareItems.VideoConversion { [self] from, to, fileType, copy, limit, done in
            asked.append(Asked(from: from, to: to, fileType: fileType, copy: copy, limit: limit))
            dones.append(done)
            return { [self] in calledOff += 1 }
        }
    }

    /// The last asked written whole, `bytes` long, where it was asked to
    /// be, and said made, its codecs read back as `codecs`.
    func make(bytes: Int64, codecs: [String] = ["avc1"]) throws {
        let to = try XCTUnwrap(asked.last).to
        try VideoCompatibleTests.sized(to, bytes)
        end(.made(codecs: codecs))
    }

    /// The last asked ended so.
    func end(_ converted: ShareItems.Converted) {
        dones.last?(converted)
    }
}
