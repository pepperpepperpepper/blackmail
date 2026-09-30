import XCTest
@testable import Blackmail

/// The letter a share starts as (B-036), in the shape Mail's share sheet
/// gives it: the page's title as the subject, the address alone above his
/// signature, a shared photo attached, and the HTML twin with the address
/// as a link rather than words.
final class ShareLetterTests: XCTestCase {

    private let signature = "Sam\nSomewhere, 1 Example Street"
    private let page = URL(string: "https://en.wikipedia.org/wiki/Mercury_(planet)?wprov=sfti1&x=1#Orbit")!
    private let video = URL(string: "https://youtu.be/abc123?si=xyz")!

    private func letter(_ items: [SharedItem]) -> Draft {
        ShareLetter.draft(from: items, signature: signature)
    }

    // MARK: - Subject and body

    /// A link with no title, as some apps share one: the address alone,
    /// above the signature, nothing typed and no subject.
    func testALinkAloneIsTheBodyAboveTheSignature() {
        let draft = letter([.link(page, title: nil)])
        XCTAssertEqual(draft.subject, "")
        XCTAssertEqual(draft.body, page.absoluteString + "\n\n" + signature)
        XCTAssertTrue(draft.attachments.isEmpty)
        XCTAssertTrue(draft.to.isEmpty, "he chooses who it goes to")
    }

    /// Safari and YouTube both give the page's title, which Mail makes the
    /// subject. A title over several lines is one line, and a "title" that
    /// is only the address again is no title.
    func testALinksTitleIsTheSubject() {
        XCTAssertEqual(letter([.link(video, title: "  A Concert,\n Live \n")]).subject,
                       "A Concert, Live")
        XCTAssertEqual(letter([.link(video, title: video.absoluteString)]).subject, "")
        XCTAssertEqual(letter([.link(video, title: "   ")]).subject, "")
    }

    func testTextAloneIsTheBody() {
        let draft = letter([.text("  Three lines\nof a poem\n\n")])
        XCTAssertEqual(draft.subject, "")
        XCTAssertEqual(draft.body, "Three lines\nof a poem\n\n" + signature)
    }

    /// Some apps send the address a second time as text beside the link,
    /// and some send words with the address in them. Either way it is in
    /// the letter once.
    func testTheAddressIsWrittenOnce() {
        XCTAssertEqual(letter([.link(video, title: "A Concert"), .text(video.absoluteString)]).body,
                       video.absoluteString + "\n\n" + signature)
        XCTAssertEqual(letter([.text("Worth a look " + video.absoluteString),
                               .link(video, title: nil)]).body,
                       "Worth a look " + video.absoluteString + "\n\n" + signature)
    }

    /// The same link, or the same words, handed over twice, as an app that
    /// offers both a page and its URL can: written once.
    func testTheSameThingSharedTwiceIsWrittenOnce() {
        XCTAssertEqual(letter([.link(video, title: nil), .link(video, title: nil)]).body,
                       video.absoluteString + "\n\n" + signature)
        XCTAssertEqual(letter([.text("A poem"), .text(" A poem\n")]).body,
                       "A poem\n\n" + signature)
    }

    /// A photograph goes with the letter as a staged file, as one chosen in
    /// the composer does, and a shared photo alone is a blank letter with
    /// his signature and the photo. Where it was staged is `ShareItems`'.
    func testAPhotoIsAttachedAsAStagedFile() throws {
        let staged = URL(fileURLWithPath: "/staged/1/Garden.jpg")
        let draft = letter([.file(staged, filename: "Garden.jpg", mimeType: "image/jpeg", size: 7),
                            .link(video, title: nil),
                            .file(URL(fileURLWithPath: "/staged/2/Fine.jpg"), filename: "Fine.jpg",
                                  mimeType: "image/jpeg", size: 9)])

        XCTAssertEqual(draft.body, video.absoluteString + "\n\n" + signature)
        XCTAssertEqual(draft.attachments.map(\.filename), ["Garden.jpg", "Fine.jpg"])
        let attached = try XCTUnwrap(draft.attachments.first)
        XCTAssertEqual(attached.mimeType, "image/jpeg")
        XCTAssertEqual(attached.size, 7)
        guard case let .localFile(url) = attached.source else {
            return XCTFail("a shared photo is a file on this device, not a message part")
        }
        XCTAssertEqual(url, staged)

        let alone = letter([.file(staged, filename: "Garden.jpg", mimeType: "image/jpeg", size: 7)])
        XCTAssertEqual(alone.body, Draft.blank(signature: signature).body)
    }

    func testNoSignatureMeansNoSignatureLines() {
        let draft = ShareLetter.draft(from: [.link(page, title: nil)], signature: "")
        XCTAssertEqual(draft.body, page.absoluteString)
    }

    // MARK: - The HTML twin

    private func account(signatureHTML: String = "") -> MailAccount {
        MailAccount(address: "owner@example.com", username: "owner@example.com",
                    signature: signature, signatureHTML: signatureHTML)
    }

    /// The link is a link in the HTML, `&` written as `&amp;` in the href
    /// as HTML needs, and the plain part keeps the bare address.
    func testTheHTMLTwinCarriesTheLinkAsALink() throws {
        let draft = letter([.link(page, title: "Mercury")])
        let html = try XCTUnwrap(ShareLetter.html(for: draft, account: account()))
        let escaped = "https://en.wikipedia.org/wiki/Mercury_(planet)?wprov=sfti1&amp;x=1#Orbit"

        XCTAssertTrue(html.hasPrefix(AppleMailHTML.documentOpen))
        XCTAssertTrue(html.contains("<a href=\"\(escaped)\">\(escaped)</a>"), html)
        XCTAssertTrue(html.contains(AppleMailHTML.signatureAnchor), "his signature, as the app sends it")
        XCTAssertTrue(html.contains("Somewhere, 1 Example Street"))
        XCTAssertTrue(draft.body.hasPrefix(page.absoluteString), "the plain part keeps the bare address")
    }

    /// A plain signature alone would send the letter as text; a link is a
    /// rich element, so a shared link always has its HTML twin.
    func testALinkHasAnHTMLTwinEvenWithAPlainSignature() {
        let draft = letter([.link(video, title: nil)])
        XCTAssertNil(AppleMailHTML.part(for: draft, account: account()),
                     "what the app alone would send")
        XCTAssertNotNil(ShareLetter.html(for: draft, account: account()))
    }

    /// Links belong to what he typed. The signature's own markup, and its
    /// own addresses, go out exactly as they are.
    func testTheSignatureIsLeftAsItIs() throws {
        let markup = "<table><tr><td>Sam</td><td>https://example.org/sam "
            + "<a href=\"https://example.org\">example.org</a></td></tr></table>"
        let draft = letter([.link(video, title: nil)])
        let html = try XCTUnwrap(ShareLetter.html(for: draft, account: account(signatureHTML: markup)))
        let tail = String(html[html.range(of: AppleMailHTML.signatureAnchor)!.lowerBound...])

        XCTAssertTrue(tail.contains(AppleMailHTML.onWhitePaper(markup)), tail)
        XCTAssertEqual(html.components(separatedBy: "<a href=").count - 1, 2,
                       "his one link and the signature's own, nothing more")
    }

    /// Without a link it is whatever the app would send for the same
    /// letter.
    func testALetterWithNoLinkIsWhatTheAppWouldSend() {
        let draft = letter([.text("Only words")])
        XCTAssertEqual(ShareLetter.html(for: draft, account: account()),
                       AppleMailHTML.part(for: draft, account: account()))
        let rich = account(signatureHTML: "<b>Sam</b>")
        XCTAssertEqual(ShareLetter.html(for: draft, account: rich),
                       AppleMailHTML.part(for: draft, account: rich))
    }

    /// Where a link ends in running text: before a full stop or a comma,
    /// before a closing bracket it did not open, before the `&nbsp;` the
    /// envelope writes for a trailing space, and before the escaped angle
    /// brackets of an address written the plain-text way.
    func testALinkEndsWhereTheSentenceTakesOver() {
        XCTAssertEqual(ShareLetter.linked("See https://example.org/a, then."),
                       "See <a href=\"https://example.org/a\">https://example.org/a</a>, then.")
        XCTAssertEqual(ShareLetter.linked("(https://example.org/b)"),
                       "(<a href=\"https://example.org/b\">https://example.org/b</a>)")
        XCTAssertEqual(ShareLetter.linked("https://example.org/Mercury_(planet)."),
                       "<a href=\"https://example.org/Mercury_(planet)\">"
                       + "https://example.org/Mercury_(planet)</a>.")
        XCTAssertEqual(ShareLetter.linked("<div>http://example.org/c&nbsp;</div>"),
                       "<div><a href=\"http://example.org/c\">http://example.org/c</a>&nbsp;</div>")
        XCTAssertEqual(ShareLetter.linked("no link here"), "no link here")
        XCTAssertEqual(ShareLetter.linked(AppleMailHTML.escape("See <https://example.org/page> now")),
                       "See &lt;<a href=\"https://example.org/page\">https://example.org/page</a>&gt; now")
        XCTAssertEqual(ShareLetter.linked(AppleMailHTML.escape("https://example.org/?a=1&b=2&")),
                       "<a href=\"https://example.org/?a=1&amp;b=2&amp;\">"
                       + "https://example.org/?a=1&amp;b=2&amp;</a>",
                       "an ampersand is part of the address, the last one too")
    }

    /// The same, through the whole letter: an address in angle brackets
    /// links to the page, and the brackets stay words.
    func testAnAddressInAngleBracketsLinksToThePage() throws {
        var draft = letter([.link(video, title: nil)])
        draft.body = "Look <https://example.org/page>" + Draft.signatureBlock(signature)
        let html = try XCTUnwrap(ShareLetter.html(for: draft, account: account()))
        XCTAssertTrue(html.contains("Look &lt;<a href=\"https://example.org/page\">"
                                    + "https://example.org/page</a>&gt;"), html)
    }
}
