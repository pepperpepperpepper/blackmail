import XCTest
@testable import Blackmail

/// Tests for the pictures that live inside a message.
///
/// An HTML mail points at its own images with `<img src="cid:…">`, and
/// nothing in this app resolved one, so every inline picture rendered as a
/// grey box. That is not a rare shape in HIS mail: 23 of 30 recent
/// attachment-bearing messages in his own mailbox reference at least one —
/// screenshots he forwards to himself, photographs people send him, and the
/// signature block of every correspondent writing from Apple Mail.
final class InlineImageTests: XCTestCase {

    private let scheme = InlineImageRewriter.scheme

    // MARK: - Finding the id

    func testTheAnglesComeOffAContentIDHeader() {
        // The header writes `<ii_1a0b>` and the body writes `cid:ii_1a0b`.
        // One side has to agree with the other or nothing ever matches.
        XCTAssertEqual(MIMEDecoder.strippedContentID("<ii_1a0b5a437217d709>"),
                       "ii_1a0b5a437217d709")
    }

    func testABareContentIDIsTakenAsItIs() {
        XCTAssertEqual(MIMEDecoder.strippedContentID("image001.png@01D9"),
                       "image001.png@01D9")
    }

    func testAHeaderThatRedundantlySaysCidIsHandled() {
        XCTAssertEqual(MIMEDecoder.strippedContentID("<cid:image001.png>"), "image001.png")
    }

    func testNothingUsableGivesNil() {
        XCTAssertNil(MIMEDecoder.strippedContentID(nil))
        XCTAssertNil(MIMEDecoder.strippedContentID(""))
        XCTAssertNil(MIMEDecoder.strippedContentID("   "))
        XCTAssertNil(MIMEDecoder.strippedContentID("<>"))
    }

    // MARK: - Rewriting the body

    func testAKnownReferenceIsPointedAtTheHandler() {
        XCTAssertEqual(
            InlineImageRewriter.rewrite("<img src=\"cid:abc123\">", known: ["abc123"]),
            "<img src=\"\(scheme)://abc123\">")
    }

    func testSingleQuotesWork() {
        XCTAssertEqual(
            InlineImageRewriter.rewrite("<img src='cid:abc123'>", known: ["abc123"]),
            "<img src='\(scheme)://abc123'>")
    }

    func testAReferenceToAPartTheMessageDOESNOTHaveIsLeftAlone() {
        // Mail forwarded through a list routinely points at images that were
        // stripped on the way. Sending those to the handler would mean a
        // fetch and a round trip per picture that cannot exist.
        XCTAssertEqual(
            InlineImageRewriter.rewrite("<img src=\"cid:gone\">", known: ["abc123"]),
            "<img src=\"cid:gone\">")
    }

    func testEveryReferenceInAMessageIsRewrittenNotJustTheFirst() {
        let html = "<img src=\"cid:a\"><p>x</p><img src=\"cid:b\">"
        XCTAssertEqual(
            InlineImageRewriter.rewrite(html, known: ["a", "b"]),
            "<img src=\"\(scheme)://a\"><p>x</p><img src=\"\(scheme)://b\">")
    }

    func testTextThatMerelyContainsTheWordCidIsNotDisturbed() {
        let prose = "the acid test, and cid: with nothing after it"
        XCTAssertEqual(InlineImageRewriter.rewrite(prose, known: ["a"]), prose)
    }

    func testAMessageWithNoReferencesComesBackUntouchedAndFast() {
        let html = "<p>Just a letter</p>"
        XCTAssertEqual(InlineImageRewriter.rewrite(html, known: ["a"]), html)
    }

    func testAnIdWithCharactersAURLHostCannotHoldIsEscaped() {
        // A Content-ID legitimately contains "@", and Outlook's look like
        // "image001.png@01D9F0A2.1B2C3D40".
        let rewritten = InlineImageRewriter.rewrite(
            "<img src=\"cid:image001.png@01D9\">", known: ["image001.png@01D9"])
        XCTAssertTrue(rewritten.contains("\(scheme)://image001.png%4001D9"), rewritten)
        XCTAssertFalse(rewritten.contains("@"), "an unescaped @ makes the host userinfo")
    }

    func testTheEscapingRoundTripsBackToTheOriginalId() {
        // The handler percent-DECODES what it is given, so anything the
        // rewriter escapes has to come back identical or the lookup misses.
        for id in ["image001.png@01D9", "ii_1a0b", "a b", "x/y", "50%"] {
            let escaped = InlineImageRewriter.escapedHost(id)
            XCTAssertEqual(escaped.removingPercentEncoding, id, "round trip failed for \(id)")
        }
    }

    // MARK: - The decoder hands the id through

    func testAnInlineImagePartCarriesItsContentIDOntoTheAttachment() {
        let raw = Data("""
        From: a@b.com\r
        Subject: pictures\r
        MIME-Version: 1.0\r
        Content-Type: multipart/related; boundary="X"\r
        \r
        --X\r
        Content-Type: text/html; charset=utf-8\r
        \r
        <p>see <img src="cid:ii_9z"></p>\r
        --X\r
        Content-Type: image/png\r
        Content-ID: <ii_9z>\r
        Content-Transfer-Encoding: base64\r
        Content-Disposition: inline; filename="shot.png"\r
        \r
        aGVsbG8=\r
        --X--\r
        """.utf8)

        let decoded = MIMEDecoder.decodeMessage(raw)
        let image = decoded.attachments.first { $0.mimeType == "image/png" }
        XCTAssertEqual(image?.contentID, "ii_9z",
                       "without this the body's cid: reference can never be resolved")
    }
}
