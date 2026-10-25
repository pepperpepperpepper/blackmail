import XCTest
@testable import Blackmail

/// A share's subject from what the sharing app hands over (B-125). Mail's
/// is the app's answer to the share sheet's subject question, which iOS
/// asks for Mail and never for a share extension, and Mail fetches nothing
/// for it; an extension has the item's title and its words. In the shapes
/// seen in the iPadOS 18.6 simulator and on the test iPad: Safari's page
/// title as the item's words, an app's words beside its link the same, the
/// YouTube app's link alone. Reading the extension's items is UIKit's and
/// never builds here, so its one line is read from the source. The one
/// thing the share sheet fetches is a YouTube video's title, for the
/// YouTube app's link alone, by the owner's ruling of 2026-10-25 (B-126).
final class ShareNameTests: XCTestCase {

    private let signature = "Sam"
    private let page = URL(string: "https://en.wikipedia.org/wiki/Opera_house")!
    private let video = URL(string: "https://youtu.be/abc123?si=xyz")!

    /// Safari hands its page's title over as the item's words and gives it
    /// no title of its own: the subject is the page's title, the one Mail
    /// gives the same share.
    func testSafarisPageTitleIsTheSubject() {
        let name = ShareItems.name(title: nil, words: "Opera house - Wikipedia")
        XCTAssertEqual(name, "Opera house - Wikipedia")
        let draft = ShareLetter.draft(from: [.link(page, title: name)], signature: signature)
        XCTAssertEqual(draft.subject, "Opera house - Wikipedia")
        XCTAssertEqual(draft.body, page.absoluteString + "\n\n" + signature)
    }

    /// An app that hands over an item of its own with a title: the title,
    /// before any words the item carries.
    func testAnAppsOwnTitleComesFirst() {
        XCTAssertEqual(ShareItems.name(title: " Tosca, Act 2 \n", words: "Watch this"), "Tosca, Act 2")
        XCTAssertEqual(ShareItems.name(title: "  ", words: "Watch this"), "Watch this")
        XCTAssertEqual(ShareItems.name(title: "", words: nil), nil)
    }

    /// The YouTube app hands over the link alone: nothing names it, so the
    /// subject begins empty, and the link alone is the body. YouTube's
    /// title, asked as the sheet comes up, is what fills it (B-126).
    func testALinkNamedByNothingHasNoSubject() {
        let name = ShareItems.name(title: nil, words: nil)
        XCTAssertNil(name)
        let draft = ShareLetter.draft(from: [.link(video, title: name)], signature: signature)
        XCTAssertEqual(draft.subject, "")
        XCTAssertEqual(draft.body, video.absoluteString + "\n\n" + signature)
        XCTAssertNil(ShareItems.name(title: " \n", words: "\t "), "blank names nothing")
    }

    /// The extension's items read through `ShareItems.name`, the title then
    /// the words, nothing else.
    func testTheItemsAreNamedByTheRule() throws {
        let code = try source("Share/ShareViewController.swift")
        XCTAssertTrue(code.contains("let title = ShareItems.name(title: item.attributedTitle?.string, "
            + "words: item.attributedContentText?.string)"))
        XCTAssertEqual(code.components(separatedBy: "attributedContentText").count - 1, 1)
    }

    /// The share sheet fetches one thing, a YouTube video's title from
    /// YouTube's oEmbed, in one file, `VideoTitle` (B-126). No other file of
    /// it fetches anything: no LinkPresentation, no URL session or
    /// connection, no web view, no page asked for. And `VideoTitle` asks
    /// that one address alone, on a session that keeps nothing.
    func testTheShareSheetFetchesOnlyAVideosTitle() throws {
        let share = sources.appendingPathComponent("Share")
        let files = try FileManager.default.contentsOfDirectory(atPath: share.path)
            .filter { $0.hasSuffix(".swift") }.sorted()
        for known in ["ShareItems.swift", "ShareLetter.swift", "ShareMirror.swift",
                      "ShareSheet.swift", "ShareViewController.swift", "VideoTitle.swift"] {
            XCTAssertTrue(files.contains(known), "every file of the share sheet is read: \(known)")
        }
        let fetches = ["LinkPresentation", "LPMetadataProvider", "startFetchingMetadata",
                       "URLSession", "dataTask(", "Data(contentsOf: url", "oembed",
                       "WKWebView", "NSURLConnection"]
        for file in files where file != "VideoTitle.swift" {
            let code = try source("Share/\(file)")
            for fetch in fetches {
                XCTAssertFalse(code.lowercased().contains(fetch.lowercased()), "\(file): \(fetch)")
            }
        }
        let asking = try source("Share/VideoTitle.swift")
        for never in ["LinkPresentation", "LPMetadataProvider", "startFetchingMetadata",
                      "WKWebView", "NSURLConnection", "Data(contentsOf:", "URLSession.shared"] {
            XCTAssertFalse(asking.contains(never), never)
        }
        let addresses = asking.components(separatedBy: "\"").filter { $0.contains("://") }
        XCTAssertEqual(addresses, ["https://www.youtube.com/oembed?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3D"],
                       "one address, YouTube's oEmbed")
        XCTAssertEqual(asking.components(separatedBy: "URLSession(configuration:").count - 1, 1)
        XCTAssertEqual(asking.components(separatedBy: "dataTask(").count - 1, 1)
        for kept in ["URLSessionConfiguration.ephemeral", "settings.httpShouldSetCookies = false",
                     "settings.httpCookieAcceptPolicy = .never", "settings.urlCache = nil",
                     "settings.waitsForConnectivity = false"] {
            XCTAssertTrue(asking.contains(kept), kept)
        }
    }

    /// The sheet asks for the title of the video `ShareSheet.videoToName`
    /// picks, through `VideoTitle.web`, once the sheet is built; what comes
    /// goes through `ShareSheet.named` before it touches Subject, and Subject
    /// typed in is noted as typed.
    func testTheSheetAsksAndFillsByTheRule() throws {
        let code = try source("Share/ShareViewController.swift")
        XCTAssertTrue(code.contains("video = sheet.videoToName(in: items)"))
        XCTAssertTrue(code.contains("updateSend() askForTheTitle() }"))
        XCTAssertEqual(code.components(separatedBy: "VideoTitle.ask(").count - 1, 1)
        XCTAssertTrue(code.contains("VideoTitle.ask(for: video, through: VideoTitle.web)"))
        XCTAssertTrue(code.contains("let named = self.sheet.named(subject, now: self.subjectField.text ?? \"\", "
            + "typed: self.subjectTyped) if let named { self.subjectField.text = named "
            + "self.title = ComposeForm.title(subject: named) }"))
        XCTAssertEqual(code.components(separatedBy: "subjectField.text =").count - 1, 1,
                       "Subject is written only with what `named` allows")
        XCTAssertTrue(code.contains("@objc private func subjectChanged() { subjectTyped = true"))
    }

    /// The app's sources, `ios/Sources/Blackmail`.
    private var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail")
    }

    /// The file's code with its comment lines dropped and its spacing
    /// made single, so a line is found however it is wrapped.
    private func source(_ path: String) throws -> String {
        let url = sources.appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }
}
