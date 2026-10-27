import XCTest
@testable import Blackmail

/// A HEIC picture among a letter's words, its part `image/heic` and shown
/// by `cid:`, on iPadOS 16, whose WebKit draws no HEIC: the loader serves
/// it as a JPEG made of it, at most 2048 px on its longer side, decoded at
/// that size, away from the main thread; from iPadOS 17 as it came. On the
/// test iPad, iPadOS 16.5.1, such a picture was a small box with WebKit's
/// broken picture in it (2026-10-27). The making of the JPEG is ImageIO,
/// read from its source; what is served is run here (B-171).
final class HEICPictureTests: XCTestCase {

    private let heic = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63])
    private let made = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0xFF, 0xD9])

    /// Below 17 a HEIC, by any of its names and in any case, is served as
    /// the JPEG made of it, as `image/jpeg`; from 17, and any other kind
    /// at all, as it came, the JPEG never made. One no JPEG could be made
    /// of is served as it came.
    func testAHEICIsServedAsAJPEGWhereWebKitDrawsNone() {
        var asked = 0
        let jpeg: (Data) -> Data? = { [made] _ in asked += 1; return made }
        for kind in ["image/heic", "image/HEIC", "IMAGE/HEIF", "image/heic-sequence", "image/heif-sequence",
                     "image/heic; name=\"IMG_1220.HEIC\"", " image/heif "] {
            let served = HEICPicture.served(heic, as: kind, drawsHEIC: false, jpeg: jpeg)
            XCTAssertEqual(served.data, made, kind)
            XCTAssertEqual(served.mimeType, "image/jpeg", kind)
            XCTAssertTrue(HEICPicture.isHEIC(kind), kind)
        }
        XCTAssertEqual(asked, 7)
        asked = 0
        for kind in ["image/heic", "image/heif"] {
            let served = HEICPicture.served(heic, as: kind, drawsHEIC: true, jpeg: jpeg)
            XCTAssertEqual(served.data, heic)
            XCTAssertEqual(served.mimeType, kind)
        }
        for kind in ["image/jpeg", "image/png", "image/gif", "image/webp", "application/pdf",
                     "image/heics", "image/avif", ""] {
            let served = HEICPicture.served(heic, as: kind, drawsHEIC: false, jpeg: jpeg)
            XCTAssertEqual(served.data, heic, kind)
            XCTAssertEqual(served.mimeType, kind, kind)
            XCTAssertFalse(HEICPicture.isHEIC(kind), kind)
        }
        XCTAssertEqual(asked, 0, "no JPEG made where none is served")
        for none in [nil, Data()] as [Data?] {
            let served = HEICPicture.served(heic, as: "image/heic", drawsHEIC: false, jpeg: { _ in none })
            XCTAssertEqual(served.data, heic)
            XCTAssertEqual(served.mimeType, "image/heic")
        }
        XCTAssertEqual(HEICPicture.maxPixels, 2048)
    }

    /// The loader, read: after the part is fetched, a HEIC where the
    /// system draws none goes through `served` in a detached task, off the
    /// main thread, before WebKit is answered; the system read by its
    /// version, 17; the JPEG made by ImageIO's thumbnail, upright, at most
    /// `maxPixels`, at the shared photo's quality.
    func testTheLoaderMakesTheJPEGAwayFromTheMainThread() throws {
        let loader = try source("UI/InlineImageLoader.swift")
        XCTAssertTrue(loader.contains(
            "requests.answering(key, with: Task { @MainActor in var result = try? await fetch(contentID) "
                + "if let (data, kind) = result, !HEICPicture.systemDrawsHEIC, HEICPicture.isHEIC(kind) { "
                + "let served = await Task.detached(priority: .userInitiated) { "
                + "HEICPicture.served(data, as: kind, drawsHEIC: false, jpeg: HEICPicture.jpeg) }.value "
                + "result = (served.data, served.mimeType) } "
                + "self.finish(task, key: key, with: result?.0, mimeType: result?.1) })"), loader)
        let imageIO = try source("UI/HEICPictureImageIO.swift")
        for line in [
            "static let systemDrawsHEIC = ProcessInfo.processInfo.isOperatingSystemAtLeast( "
                + "OperatingSystemVersion(majorVersion: 17, minorVersion: 0, patchVersion: 0))",
            "kCGImageSourceCreateThumbnailFromImageAlways: true, "
                + "kCGImageSourceCreateThumbnailWithTransform: true, "
                + "kCGImageSourceThumbnailMaxPixelSize: maxPixels,",
            "guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)",
            "CGImageDestinationCreateWithData(out, \"public.jpeg\" as CFString, 1, nil)",
            "[kCGImageDestinationLossyCompressionQuality: SharedPhoto.quality] as CFDictionary",
        ] {
            XCTAssertTrue(imageIO.contains(line), line)
        }
        XCTAssertFalse(imageIO.contains("UIImage"), "never decoded whole")
        XCTAssertFalse(imageIO.contains("#available"))
    }

    /// The source of `file` under `Sources/Blackmail`, comments out and
    /// its white space one space.
    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/" + file)
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }
}
