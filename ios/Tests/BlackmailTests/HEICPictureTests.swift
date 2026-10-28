import XCTest
@testable import Blackmail

/// A HEIC picture among a letter's words, its part `image/heic` and shown
/// by `cid:`, on iPadOS 16, whose WebKit draws no HEIC: the loader serves
/// it as a JPEG made of it, drawn at most 2048 px on its longer side, away
/// from the main thread, one at a time; from iPadOS 17 as it came. On the
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

    /// The JPEGs are made one at a time (`HEICPicture.turns`): of five
    /// asking at once, never two at their turn together, each its turn
    /// once, and the turns given back, so the next is had at once; a
    /// limit of two never has three. Found in the review of the fix: each
    /// HEIC of a letter began its decode at once.
    func testTheJPEGsAreMadeOneAtATime() async {
        XCTAssertEqual(HEICPicture.atOnce, 1)
        XCTAssertEqual(HEICPicture.turns.limit, 1)
        for limit in [1, 2] {
            let turns = HEICPicture.Turns(limit: limit)
            let log = TurnLog()
            await withTaskGroup(of: Void.self) { group in
                for i in 0..<5 {
                    group.addTask {
                        await turns.take()
                        await log.enter(i)
                        try? await Task.sleep(nanoseconds: 10_000_000)
                        await log.leave()
                        await turns.give()
                    }
                }
            }
            let most = await log.most
            let had = await log.had
            XCTAssertLessThanOrEqual(most, limit, "limit \(limit)")
            XCTAssertEqual(had.sorted(), [0, 1, 2, 3, 4], "limit \(limit)")
            for _ in 0..<limit { await turns.take() }
            for _ in 0..<limit { await turns.give() }
        }
    }

    /// The loader, read: after the part is fetched, a HEIC where the
    /// system draws none goes through `served` in a detached task, off the
    /// main thread, at its turn and not for a request stopped while it
    /// waited, before WebKit is answered; the system read by its
    /// version, 17; the JPEG made by ImageIO's thumbnail, upright, at most
    /// `maxPixels`, at the shared photo's quality.
    func testTheLoaderMakesTheJPEGAwayFromTheMainThread() throws {
        let loader = try source("UI/InlineImageLoader.swift")
        XCTAssertTrue(loader.contains(
            "requests.answering(key, with: Task { @MainActor in var result = try? await fetch(contentID) "
                + "if let (data, kind) = result, !HEICPicture.systemDrawsHEIC, HEICPicture.isHEIC(kind) { "
                + "await HEICPicture.turns.take() if !Task.isCancelled { "
                + "let served = await Task.detached(priority: .userInitiated) { "
                + "HEICPicture.served(data, as: kind, drawsHEIC: false, jpeg: HEICPicture.jpeg) }.value "
                + "result = (served.data, served.mimeType) } await HEICPicture.turns.give() } "
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
        XCTAssertFalse(imageIO.contains("UIImage"), "made by ImageIO's thumbnail alone")
        XCTAssertFalse(imageIO.contains("#available"))
    }

    /// An attached HEIC, an iPhone's photo the letter does not show by
    /// `cid:`, is drawn in the body as a photo, as Mail draws it on
    /// iPadOS 16.5.1 (B-176), where it was a tile marked "HEIC": an `<img>`
    /// from the loader by its picture's address, in an HTML letter and a
    /// plain one, its map naming its kind as it came, a HEIC, which the
    /// loader serves as the JPEG made of it below 17; held, the photo's
    /// menu. A TIFF is still a tile; a HEIC the letter shows by `cid:` is
    /// drawn there, once.
    func testAnAttachedHEICIsDrawnAsAPhoto() throws {
        let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)
        let photo = Attachment(id: "2", filename: "IMG_1220.HEIC", mimeType: "image/heic", size: 2_300_000)
        let tiff = Attachment(id: "3", filename: "scan.tiff", mimeType: "image/tiff", size: 900_000)
        for (html, text) in [("<p>Our garden.</p>", nil), (nil, "Our garden.")] as [(String?, String?)] {
            let m = Message(id: "7/3", mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                            senderAddress: "jane@example.com", to: [], cc: [], subject: "Garden",
                            date: Date(timeIntervalSince1970: 1_792_679_717), textBody: text,
                            htmlBody: html, attachments: [photo, tiff])
            let page = try XCTUnwrap(PanePage.letter(m, style: style))
            XCTAssertTrue(page.contains("<img src=\"bmcid://bmfile-m7_3-2\" alt=\"IMG_1220.HEIC\">"), page)
            XCTAssertFalse(page.contains("bmfile:2?letter=7/3"), "no tile for the photo")
            XCTAssertTrue(page.contains("bmfile:3?letter=7/3"), "the TIFF a tile")
            XCTAssertFalse(page.contains(">HEIC</text>"), "no tile's icon marked HEIC")
            let map = PanePage.pictures(of: [m])
            XCTAssertEqual(map["bmfile-m7_3-2"],
                           PanePage.Picture(messageID: "7/3", mailboxID: "INBOX", section: "2", mimeType: "image/heic"))
            XCTAssertNil(map["bmfile-m7_3-3"])
            XCTAssertTrue(HEICPicture.isHEIC(try XCTUnwrap(map["bmfile-m7_3-2"]).mimeType), "a JPEG below 17")
            XCTAssertEqual(PanePictures.file("bmfile-m7_3-2", of: m), photo)
            XCTAssertEqual(PanePictures.menu(for: photo), PanePictures.menu)
        }
        let shown = Attachment(id: "2", filename: "IMG_1220.HEIC", mimeType: "image/heic", size: 2_300_000,
                               contentID: "photo1", isInline: true)
        let m = Message(id: "7/3", mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                        senderAddress: "jane@example.com", to: [], cc: [], subject: "Garden",
                        date: Date(timeIntervalSince1970: 1_792_679_717), textBody: nil,
                        htmlBody: "<p>Our garden.</p><img src=\"cid:photo1\">", attachments: [shown])
        let page = try XCTUnwrap(PanePage.letter(m, style: style))
        XCTAssertEqual(page.components(separatedBy: "<img ").count - 1, 1, page)
        XCTAssertFalse(page.contains("bmfile-m7_3-2"), "drawn by the letter, not again")
    }

    /// Who had a turn, and the most at theirs at once.
    private actor TurnLog {
        private(set) var had: [Int] = []
        private(set) var most = 0
        private var inside = 0

        func enter(_ i: Int) {
            inside += 1
            most = max(most, inside)
            had.append(i)
        }

        func leave() {
            inside -= 1
        }
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
