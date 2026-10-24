import XCTest
@testable import Blackmail

/// A share's subject from what the sharing app hands over (B-125). Mail's
/// is the app's answer to the share sheet's subject question, which iOS
/// asks for Mail and never for a share extension, and Mail fetches nothing
/// for it; an extension has the item's title and its words. In the shapes
/// seen in the iPadOS 18.6 simulator and on the test iPad: Safari's page
/// title as the item's words, an app's words beside its link the same, the
/// YouTube app's link alone. Reading the extension's items is UIKit's and
/// never builds here, so its one line is read from the source; and nothing
/// in the share sheet fetches a page.
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
    /// subject is left empty, and the link alone is the body.
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

    /// Mail fetches nothing to name a share, so nothing in the share sheet
    /// does: no LinkPresentation, no URL session, no page asked for.
    func testNothingInTheShareSheetFetchesThePage() throws {
        for file in ["Share/ShareViewController.swift", "Share/ShareItems.swift",
                     "Share/ShareLetter.swift", "Share/ShareSheet.swift"] {
            let code = try source(file)
            for fetch in ["LinkPresentation", "LPMetadataProvider", "startFetchingMetadata",
                          "URLSession", "dataTask(", "Data(contentsOf: url", "oembed"] {
                XCTAssertFalse(code.lowercased().contains(fetch.lowercased()), "\(file): \(fetch)")
            }
        }
    }

    /// The file's code with its comment lines dropped and its spacing
    /// made single, so a line is found however it is wrapped.
    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }
}
