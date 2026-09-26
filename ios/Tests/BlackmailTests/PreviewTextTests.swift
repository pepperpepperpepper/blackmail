import XCTest
@testable import Blackmail

/// Tests for the list-row preview text.
///
/// Every case here is a fragment, because that is all the app ever has: the
/// preview is built from the first two (or eight) kilobytes of a body, so the
/// input routinely stops mid-character, mid-tag or mid-stylesheet. The failure
/// this file is really guarding against is not an ugly preview but a *wrong*
/// one — mojibake across a whole row because a single accented character was
/// cut in half at the end.
final class PreviewTextTests: XCTestCase {

    // MARK: - Truncated UTF-8

    func testSplitCharacterAtTheEndIsDroppedRatherThanPoisoningTheWholeString() {
        // "café au lait, encore" cut so the final é loses its second byte.
        var data = Data("Bonjour, voici le café au lait et un peu de texte".utf8)
        data.append(0xC3)                       // the lead byte of an é, alone

        let trimmed = PreviewText.trimmingSplitCharacter(data)
        XCTAssertNotNil(String(data: trimmed, encoding: .utf8),
                        "a dangling lead byte must not survive")
        XCTAssertEqual(String(data: trimmed, encoding: .utf8),
                       "Bonjour, voici le café au lait et un peu de texte",
                       "and the text before it must be untouched")
    }

    func testAThreeByteCharacterCutAfterOneByteIsAlsoHandled() {
        var data = Data("Prices in euros: ".utf8)
        data.append(contentsOf: [0xE2, 0x82])   // two thirds of a €
        XCTAssertEqual(String(data: PreviewText.trimmingSplitCharacter(data), encoding: .utf8),
                       "Prices in euros: ")
    }

    func testGenuineLatin1IsNotTrimmed() {
        // Latin-1 has high bytes throughout, so dropping the tail never makes
        // it decode as UTF-8 — and trimming it would be wrong, since the
        // charset decoder downstream reads it correctly as it stands.
        let data = Data([0x4A, 0xE9, 0x72, 0xF4, 0x6D, 0x65, 0x20, 0xE0, 0x20, 0x50, 0x61, 0x72, 0xEE, 0x73])
        XCTAssertEqual(PreviewText.trimmingSplitCharacter(data), data)
    }

    func testCompleteTextIsReturnedUnchanged() {
        let data = Data("nothing wrong with this at all".utf8)
        XCTAssertEqual(PreviewText.trimmingSplitCharacter(data), data)
    }

    // MARK: - Plain text

    func testPlainTextIsFlattenedToOneRunOfWords() {
        let body = """


            Dear Margaret,

            The appointment   is on Tuesday.
            """
        XCTAssertEqual(PreviewText.fromPlainText(body),
                       "Dear Margaret, The appointment is on Tuesday.")
    }

    func testPreviewIsBoundedSoARowNeverHoldsAPageOfText() {
        let long = String(repeating: "word ", count: 500)
        XCTAssertLessThanOrEqual(PreviewText.fromPlainText(long).count,
                                 PreviewText.maximumCharacters)
    }

    func testEmptyBodyGivesEmptyPreviewRatherThanWhitespace() {
        XCTAssertEqual(PreviewText.fromPlainText("\n\n   \n"), "")
    }

    // MARK: - HTML

    func testHTMLTagsBecomeWordBoundariesNotDeletions() {
        // The failure this catches is "JanFeb": tags joined rather than spaced.
        XCTAssertEqual(PreviewText.fromHTML("<td>Jan</td><td>Feb</td>"), "Jan Feb")
    }

    func testStyleAndScriptContentsNeverReachTheReader() {
        let html = """
            <html><head><style>td { padding: 0 } .wrap { width: 600px }</style></head>
            <body><script>var x = 1;</script><p>Your order has shipped.</p></body></html>
            """
        XCTAssertEqual(PreviewText.fromHTML(html), "Your order has shipped.")
    }

    func testConditionalCommentsAreDropped() {
        let html = "<!--[if mso]><table width=600><![endif]--><p>Hello there</p>"
        XCTAssertEqual(PreviewText.fromHTML(html), "Hello there")
    }

    func testAttributeContainingAngleBracketDoesNotSpillIntoTheText() {
        // Cut at the first '>' this reads as: b"> Compare
        XCTAssertEqual(PreviewText.fromHTML(#"<img alt="a > b"><span>Compare</span>"#),
                       "Compare")
    }

    func testEntitiesAreDecoded() {
        XCTAssertEqual(PreviewText.fromHTML("<p>Marks &amp; Spencer &#8212; 10&nbsp;items</p>"),
                       "Marks & Spencer \u{2014} 10 items")
    }

    func testABareAmpersandInRunningTextSurvives() {
        XCTAssertEqual(PreviewText.fromHTML("<p>Marks & Spencer</p>"), "Marks & Spencer")
    }

    func testNonsenseNumericEntityIsLeftAloneRatherThanCrashing() {
        // 0xD800 is a surrogate: not a scalar, and Unicode.Scalar rejects it.
        XCTAssertEqual(PreviewText.fromHTML("<p>&#55296; ok</p>"), "&#55296; ok")
    }

    func testPreheaderPaddingDoesNotSwallowTheWholePreview() {
        // A real marketing pattern: zero-width joiners padded out so that the
        // body text does not appear in the client's preview. Treating them as
        // spaces would leave nothing but the 240-character cap of blanks.
        let padding = String(repeating: "&zwnj;&nbsp;", count: 200)
        let html = "<div>Your statement is ready\(padding)</div><p>Body text here</p>"
        XCTAssertEqual(PreviewText.fromHTML(html), "Your statement is ready Body text here")
    }

    /// The window is a fixed byte count, so it lands wherever it lands.
    func testAWindowThatStoppedInsideAStylesheetYieldsNothingRatherThanCSS() {
        let html = "<html><head><style>td { padding: 0 } .wrap { width: 6"
        XCTAssertEqual(PreviewText.fromHTML(html), "",
                       "an unterminated <style> must not leak its contents")
    }

    func testAWindowThatStoppedMidTagEndsTheTextThere() {
        XCTAssertEqual(PreviewText.fromHTML("<p>The first sentence.</p><p class=\"bo"),
                       "The first sentence.")
    }

    func testHTMLPreviewIsBoundedToo() {
        let html = "<p>" + String(repeating: "word ", count: 500) + "</p>"
        XCTAssertLessThanOrEqual(PreviewText.fromHTML(html).count, PreviewText.maximumCharacters)
    }

    // MARK: - Choosing the part to fetch

    func testPlainTextIsPreferredOverHTMLInAnAlternative() {
        // Preferring plain is not only about not having to strip tags: the
        // plain alternative is a fraction of the size, and this choice is what
        // keeps a page of previews to kilobytes instead of hundreds of them.
        var plain = MIMEPart()
        plain.type = "text"; plain.subtype = "plain"; plain.section = "1"
        var html = MIMEPart()
        html.type = "text"; html.subtype = "html"; html.section = "2"
        var root = MIMEPart()
        root.type = "multipart"; root.subtype = "alternative"; root.section = ""
        root.children = [plain, html]

        XCTAssertEqual(MIMEDecoder.previewPart(root)?.section, "1")
    }

    func testHTMLIsUsedWhenThereIsNoPlainAlternative() {
        var html = MIMEPart()
        html.type = "text"; html.subtype = "html"; html.section = "1"
        XCTAssertEqual(MIMEDecoder.previewPart(html)?.subtype, "html")
    }

    func testAnAttachmentIsNeverMistakenForTheBody() {
        // A 4 MB log.txt must not become the preview.
        var log = MIMEPart()
        log.type = "text"; log.subtype = "plain"; log.section = "2"
        log.disposition = "attachment"
        log.dispositionParameters = ["filename": "log.txt"]
        var body = MIMEPart()
        body.type = "text"; body.subtype = "plain"; body.section = "1"
        var root = MIMEPart()
        root.type = "multipart"; root.subtype = "mixed"; root.section = ""
        root.children = [body, log]

        XCTAssertEqual(MIMEDecoder.previewPart(root)?.section, "1")
    }

    func testAMessageWithNoTextPartAtAllHasNoPreviewPart() {
        var image = MIMEPart()
        image.type = "image"; image.subtype = "jpeg"; image.section = "1"
        image.dispositionParameters = ["filename": "scan.jpg"]
        XCTAssertNil(MIMEDecoder.previewPart(image))
    }
}
