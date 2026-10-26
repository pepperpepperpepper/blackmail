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
/// on this host, is read from its source. A photo goes as before: a HEIC
/// with no JPEG beside it is made a JPEG in the app, under the same name.
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
            "SHARE-VIDEO made H.264, bytes=18000000 from=12000000"])
    }

    /// The original fits and its H.264 copy does not: the original goes,
    /// HEVC, rather than the video left out. The room is what the original
    /// had, the rows before it in it: a copy of exactly that goes, one a
    /// byte over does not.
    func testAnH264CopyLargerThanTheRoomLeavesTheOriginalToGo() throws {
        let disk = Disk(directory)
        let staging = staging(disk, room: 20_000_000)
        XCTAssertNotNil(staging.photo(Data(count: 5_000_000), named: "IMG_0001.JPG"))
        let conversion = FakeVideoConversion()

        let first = try given("IMG_0196.MOV", bytes: 12_000_000)
        let fits = read(first, bytes: 12_000_000, staging: staging, videos: conversion.videos)
        let fitting = try XCTUnwrap(conversion.asked.last)
        try conversion.make(bytes: 15_000_000)
        XCTAssertEqual(fits.item, .file(fitting.to, filename: "IMG_0196.MOV",
                                        mimeType: "video/quicktime", size: 15_000_000),
                       "exactly the room the original had")
        XCTAssertEqual(staging.staged, 20_000_000)
        staging.unstage(try XCTUnwrap(fits.item))
        XCTAssertEqual(staging.staged, 5_000_000)

        let second = try given("IMG_0197.MOV", bytes: 12_000_000)
        let over = read(second, bytes: 12_000_000, staging: staging, videos: conversion.videos)
        let asked = try XCTUnwrap(conversion.asked.last)
        try conversion.make(bytes: 15_000_001)
        XCTAssertEqual(over.calls, 1)
        XCTAssertEqual(over.item, .file(asked.from, filename: "IMG_0197.MOV",
                                        mimeType: "video/quicktime", size: 12_000_000),
                       "the original goes")
        XCTAssertTrue(exists(asked.from))
        XCTAssertFalse(exists(asked.to), "the copy taken away")
        XCTAssertEqual(staging.lastMeasured, 15_000_001)
        XCTAssertEqual(staging.staged, 17_000_000)
        XCTAssertEqual(notes().last, "SHARE-VIDEO its H.264 copy bytes=15000001, more than the "
                                    + "letter's room, 15 MB left: the original goes")
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

        for said in [ShareItems.Converted.cancelled, .made, .interrupted, .failed(code: -11800)] {
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
            if said == .made { try VideoCompatibleTests.sized(asked.to, 4_000_000) }
            conversion.end(said)
            XCTAssertEqual(got.calls, 1)
            XCTAssertNil(got.item, "\(said)")
            XCTAssertFalse(exists(asked.from), "the original taken away")
            XCTAssertFalse(exists(asked.to), "and the copy")
            XCTAssertEqual(staging.staged, 0, "the room given back")
            XCTAssertFalse(loading.wasInterrupted)
            XCTAssertEqual(notes().last, "SHARE-VIDEO called off")
        }

        Diagnostics.clear()
        let early = ShareItems.Loading()
        early.cancel()
        let asked = conversion.asked.count
        let got = read(try given("IMG_0202.MOV", bytes: 1_000), bytes: 1_000, staging: staging,
                       loading: early, videos: conversion.videos)
        XCTAssertEqual(conversion.asked.count, asked, "none begun")
        XCTAssertEqual(got.calls, 1)
        XCTAssertNil(got.item)
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
    /// left one (the round's IMG_0206, an H.264 .mp4); so does one whose
    /// conversion failed, which fits as itself, rather than left out. The
    /// copy's place is taken away either way.
    func testAVideoH264AlreadyOrWhoseConversionFailsGoesAsItCame() throws {
        let disk = Disk(directory)
        let staging = staging(disk)
        let conversion = FakeVideoConversion()
        for (said, line) in [(ShareItems.Converted.notNeeded,
                              "SHARE-VIDEO goes as it came, H.264 already"),
                             (.failed(code: -11800),
                              "SHARE-VIDEO not made H.264, failed code=-11800: the original goes"),
                             (.failed(code: nil),
                              "SHARE-VIDEO not made H.264, failed: the original goes")] {
            let original = try given("IMG_0206.mp4", bytes: 2_000_000)
            let loading = ShareItems.Loading()
            let got = read(original, bytes: 2_000_000, staging: staging, loading: loading,
                           videos: conversion.videos)
            let asked = try XCTUnwrap(conversion.asked.last)
            XCTAssertEqual(asked.fileType, "public.mpeg-4", "an .mp4 written as one")
            conversion.end(said)
            XCTAssertEqual(got.item, .file(asked.from, filename: "IMG_0206.mp4",
                                           mimeType: "video/quicktime", size: 2_000_000))
            XCTAssertTrue(exists(asked.from))
            XCTAssertTrue(disk.discarded.contains(asked.to))
            XCTAssertFalse(loading.wasInterrupted)
            XCTAssertEqual(notes().last, line)
            if let item = got.item { staging.unstage(item) }
        }
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
        XCTAssertEqual(SharedPhoto.size(width: 4032, height: 3024), .init(width: 4032, height: 3024))
        XCTAssertEqual(SharedPhoto.factor(width: 4032, height: 3024, type: "public.heic",
                                          available: 1_000_000_000), 1)

        XCTAssertEqual(SharedPhoto.fileType(offered: ["public.jpeg"]), "public.jpeg")
        XCTAssertEqual(SharedPhoto.way(type: "public.jpeg", size: 2_400_000, room: budget,
                                       carriesLocation: true), .own)
        XCTAssertEqual(SharedPhoto.fileType(offered: ["public.heic", "public.jpeg"]), "public.jpeg")
        XCTAssertEqual(ComposeIntake.kind(offered: ["public.heic"], isMovie: { _ in false }), .picture)
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
    /// session at the highest quality, H.264, written as the file type
    /// asked where the session can, for a network; begun under the lock
    /// unless called off first, and called off by `cancelExport`; stopped
    /// as the app went said so by AVFoundation's own code. No API newer
    /// than the SDK, so nothing behind `#available`.
    func testTheConversionIsAVFoundationsExportCalledOffByTheRead() throws {
        let code = try source("Sources/Blackmail/Share/VideoH264.swift")
        inOrder(["#if canImport(UIKit) && canImport(AVFoundation)",
                 "import AVFoundation",
                 "static let h264 = ShareItems.VideoConversion { from, to, fileType, done in",
                 "let export = H264Export()",
                 "let asset = AVURLAsset(url: from)",
                 "asset.loadTracks(withMediaType: .video) { tracks, error in",
                 "return done(.failed(code: (error as NSError?)?.code))",
                 "try? await track.load(.formatDescriptions)",
                 "ShareItems.fourCC(CMFormatDescriptionGetMediaSubType($0))",
                 "guard ShareItems.needsH264(codecs: codecs) else { return done(.notNeeded) }",
                 "export.begin(asset, to: to, fileType: fileType, done: done)",
                 "return { export.cancel() }"], in: code)
        inOrder(["func begin(_ asset: AVAsset, to: URL, fileType: String,",
                 "AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)",
                 "let asked = AVFileType(rawValue: fileType)",
                 "let types = session.supportedFileTypes",
                 "types.contains(asked) ? asked : types.contains(.mov) ? .mov : nil",
                 "session.outputURL = to",
                 "session.outputFileType = type",
                 "session.shouldOptimizeForNetworkUse = true",
                 "lock.lock()",
                 "defer { lock.unlock() }",
                 "guard !cancelled else { return done(.cancelled) }",
                 "self.session = session",
                 "session.exportAsynchronously {",
                 "case .completed: done(.made)",
                 "case .cancelled: done(.cancelled)",
                 "&& error?.code == AVError.Code.operationInterrupted.rawValue",
                 "done(interrupted ? .interrupted : .failed(code: error?.code))",
                 "func cancel() {",
                 "cancelled = true",
                 "let session = self.session",
                 "lock.unlock()",
                 "session?.cancelExport()"], in: code)
        XCTAssertEqual(count("AVAssetExportPreset", in: code), 1, "one preset")
        XCTAssertFalse(code.contains("#available"))
        XCTAssertFalse(code.contains("fileLengthLimit"), "no video cut short to fit")

        let items = try source("Sources/Blackmail/Share/ShareItems.swift")
        inOrder(["static func compatible(_ original: SharedItem, staging: Staging, loading: Loading,",
                 "guard !loading.isCancelled else { return calledOff(nil) }",
                 "let callOff = conversion.convert(url, copy, exportType(for: filename)) { converted in",
                 "guard !loading.isCancelled else { return calledOff(copy) }",
                 "loading.track(conversion: callOff)"], in: items)
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
    }

    private(set) var asked: [Asked] = []
    private var dones: [(ShareItems.Converted) -> Void] = []
    private(set) var calledOff = 0

    var videos: ShareItems.VideoConversion {
        ShareItems.VideoConversion { [self] from, to, fileType, done in
            asked.append(Asked(from: from, to: to, fileType: fileType))
            dones.append(done)
            return { [self] in calledOff += 1 }
        }
    }

    /// The last asked written whole, `bytes` long, where it was asked to
    /// be, and said made.
    func make(bytes: Int64) throws {
        let to = try XCTUnwrap(asked.last).to
        try VideoCompatibleTests.sized(to, bytes)
        end(.made)
    }

    /// The last asked ended so.
    func end(_ converted: ShareItems.Converted) {
        dones.last?(converted)
    }
}
