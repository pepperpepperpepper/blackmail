import XCTest
@testable import Blackmail

/// Somebody else's markup, made fit to go inside one of his letters
/// (`QuotedMarkup`, B-050).
///
/// What a reply or forward quotes is whatever a stranger sent, and it leaves
/// under his name. These pin what is kept, a letter's text, links, pictures,
/// tables and inline styling, and what is not: anything that runs, anything
/// that reaches outside the quote, and any picture reference the letter
/// cannot answer.
final class QuotedMarkupTests: XCTestCase {

    private func made(_ html: String, _ pictures: [String: String] = [:]) -> String {
        QuotedMarkup.safe(html, pictures: pictures)
    }

    // MARK: - What a letter is made of stays

    func testTextLinksTablesPicturesAndInlineStylesGoThroughAsTheyWere() {
        let html = """
            <table width="600" style="border-collapse: collapse;"><tr>\
            <td style="color: #333333; font-size: 15px;">Dear <b>Carlo</b>,</td></tr>\
            <tr><td><a href="https://example.com/offer?a=1&amp;b=2" target="_blank">\
            the offer</a> and <img src="https://example.com/p.png" alt="A &quot;view&quot;" \
            width="300"></td></tr></table>
            """
        let out = made(html)
        XCTAssertTrue(out.contains("<table width=\"600\" style=\"border-collapse: collapse;\">"), out)
        XCTAssertTrue(out.contains("<td style=\"color: #333333; font-size: 15px;\">Dear <b>Carlo</b>,</td>"), out)
        XCTAssertTrue(out.contains("<a href=\"https://example.com/offer?a=1&amp;b=2\" target=\"_blank\">"
                                   + "the offer</a>"), out)
        XCTAssertTrue(out.contains("<img src=\"https://example.com/p.png\" alt=\"A &quot;view&quot;\" "
                                   + "width=\"300\">"), out)
    }

    func testTheSendersDocumentWrapperAndHeadAreTakenOff() {
        let out = made("""
            <!DOCTYPE html><html><head><title>Receipt</title><style>p { color: red }</style>\
            </head><body style="margin: 0"><p>Thanks for your order.</p></body></html>
            """)
        XCTAssertEqual(out, "<p>Thanks for your order.</p>")
        // Outlook's Word markup leaves its settings in the head as bare XML,
        // whose words a browser would show if the head were only untagged.
        XCTAssertEqual(made("<html><head><xml><w:WordDocument><w:View>Normal</w:View>"
                            + "<w:Zoom>0</w:Zoom></w:WordDocument></xml></head>"
                            + "<body><p>Hello</p></body></html>"), "<p>Hello</p>")
    }

    func testAHeadItsSenderNeverClosedEndsWhereABrowserEndsIt() {
        // HTML lets `</head>` be left out. Taken to the end of the markup,
        // such a head took the whole letter with it.
        XCTAssertEqual(made("<html><head><title>Receipt</title><body><p>Thanks for your order.</p>"
                            + "</body></html>"), "<p>Thanks for your order.</p>")
        XCTAssertEqual(made("<head><meta charset=\"utf-8\"><style>p { color: red }</style>"
                            + "<!-- x --><p>Hi</p>"), "<p>Hi</p>")
        XCTAssertEqual(made("<head><title>T</title>Plain words"), "Plain words")
        // A `<body>` ends it even when a `</head>` comes later, which is
        // then a stray closing tag.
        XCTAssertEqual(made("<head><title>T</title><body><p>x</p></head><p>y</p>"),
                       "<p>x</p><p>y</p>")
    }

    func testItTakesOffWhatTheReadingPanesWrapperTakesOff() {
        // `DocumentWrapper` strips the reading pane's letter; the pass does
        // the same in its own stride rather than paying for its regular
        // expressions first.
        for html in [
            "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>T</title>"
                + "</head><body bgcolor=\"#fff\"><div>One</div></body></html>",
            "<html><body><header>Top</header><p>Two</p></body></html>",
            "<div>Three</div><html><head><style>x{}</style></head><body>Four</body></html>",
        ] {
            XCTAssertEqual(made(html), made(DocumentWrapper.stripped(from: html)), html)
        }
    }

    func testTextAndEntitiesAreCopiedAsTheyCame() {
        XCTAssertEqual(made("caf&eacute; &amp; cr&egrave;me &#8212; 5 &lt; 6"),
                       "caf&eacute; &amp; cr&egrave;me &#8212; 5 &lt; 6")
        // A `<` that opens no tag is text, and stays text.
        XCTAssertEqual(made("5 < 6 and <3"), "5 &lt; 6 and &lt;3")
    }

    // MARK: - Nothing that runs

    func testNoScriptEventHandlerFrameFormOrObjectSurvives() {
        let html = """
            <p onclick="steal()">Keep me</p>\
            <script>alert(1)</script><SCRIPT type="text/javascript">alert(2)</SCRIPT>\
            <img src="https://example.com/x.png" onerror="alert(3)" OnLoad="alert(4)">\
            <iframe src="https://evil.example/"></iframe>\
            <form action="https://evil.example/post"><input name="pw"><button>Go</button></form>\
            <object data="x.swf"><param name="a" value="b">fallback</object>\
            <embed src="x.swf"><applet code="x"></applet>\
            <svg onload="alert(5)"><script>alert(6)</script></svg>\
            <math><mi xlink:href="javascript:alert(7)">x</mi></math>\
            <meta http-equiv="refresh" content="0;url=https://evil.example/">\
            <base href="https://evil.example/"><link rel="stylesheet" href="https://evil.example/s.css">\
            <style>body { display: none }</style>\
            <!-- <script>alert(8)</script> -->\
            <select><option>one</option></select><textarea><script>alert(9)</script></textarea>\
            <p>Also keep me</p>
            """
        let out = made(html).lowercased()
        for banned in ["<script", "alert", "onclick", "onerror", "onload", "<iframe", "<form",
                       "<input", "<button", "<object", "<param", "<embed", "<applet", "<svg",
                       "<math", "<meta", "<base", "<link", "<style", "<!--", "<select",
                       "<textarea", "evil.example", "javascript"] {
            XCTAssertFalse(out.contains(banned), "\(banned) survived in \(out)")
        }
        XCTAssertTrue(out.contains("<p>keep me</p>"), out)
        XCTAssertTrue(out.contains("<p>also keep me</p>"), out)
        XCTAssertTrue(out.contains("<img src=\"https://example.com/x.png\">"), out)
        // A button's words are prose; only the control goes.
        XCTAssertTrue(out.contains("go"), out)
    }

    func testAScriptAddressIsRefusedHoweverItIsSpelt() {
        let spellings = [
            "javascript:alert(1)",
            "JavaScript:alert(1)",
            " javascript:alert(1)",
            "java\tscript:alert(1)",
            "jav&#x61;script:alert(1)",
            "jav&#97;script:alert(1)",
            "jav&#0000097script:alert(1)",
            "javascript&colon;alert(1)",
            "javascript&#58;alert(1)",
            "vbscript:msgbox(1)",
            "data:text/html;base64,PHNjcmlwdD4=",
            "data:image/svg+xml;base64,PHN2Zz4=",
            "jav&unknownentity;ascript:alert(1)",
        ]
        for spelling in spellings {
            let out = made("<a href=\"\(spelling)\">link</a>")
            XCTAssertEqual(out, "<a>link</a>", "\(spelling) became \(out)")
        }
        // A picture whose source is refused is not kept at all.
        XCTAssertEqual(made("<p><img src=\"javascript:alert(1)\">x</p>"), "<p>x</p>")
    }

    func testALinkDoesNotReportItsClickAndAPictureSetStaysOnTheWeb() {
        XCTAssertEqual(made("<a href=\"https://example.com/a\" ping=\"https://track.example/\">x</a>"),
                       "<a href=\"https://example.com/a\">x</a>")
        XCTAssertEqual(made("<img src=\"https://example.com/a.png\" "
                            + "srcset=\"https://example.com/a.png 1x, https://example.com/b.png 2x\">"),
                       "<img src=\"https://example.com/a.png\" "
                       + "srcset=\"https://example.com/a.png 1x, https://example.com/b.png 2x\">")
        XCTAssertEqual(made("<img src=\"https://example.com/a.png\" "
                            + "srcset=\"https://example.com/a.png 1x, javascript:alert(1) 2x\">"),
                       "<img src=\"https://example.com/a.png\">")
    }

    func testTheAddressesMailUsesAreKept() {
        for address in ["https://example.com/a", "http://example.com/a", "mailto:jane@example.com",
                        "tel:+15555550142", "#top", "/relative/path"] {
            XCTAssertEqual(made("<a href=\"\(address)\">x</a>"), "<a href=\"\(address)\">x</a>")
        }
        XCTAssertEqual(made("<img src=\"data:image/png;base64,iVBORw0KGgo=\">"),
                       "<img src=\"data:image/png;base64,iVBORw0KGgo=\">")
    }

    func testAStyleThatCanRunCodeGoesAndOneThatCannotStays() {
        for style in ["width: expression(alert(1))", "background: url(javascript:alert(1))",
                      "background: url('vbscript:x')", "-moz-binding: url(x.xml#y)",
                      "behavior: url(x.htc)", "width: expr/**/ession(alert(1))",
                      "background: url(\\6a avascript:alert(1))", "@import 'x.css'",
                      "background: url(javascript&colon;alert(1))"] {
            let out = made("<p style=\"\(style)\">x</p>")
            XCTAssertEqual(out, "<p>x</p>", "\(style) became \(out)")
        }
        XCTAssertEqual(made("<td style=\"background: url(https://example.com/bg.png) #fff\">x</td>"),
                       "<td style=\"background: url(https://example.com/bg.png) #fff\">x</td>")
    }

    // MARK: - Nothing reaches outside the quote

    func testAStyleThatCanDrawOverTheLetterAroundItGoes() {
        // The quote sits below his words and his signature. Nothing in it
        // may be drawn over them, where a stranger's words would pass as
        // his.
        XCTAssertEqual(made("<div style=\"position:fixed;top:0;left:0;width:100%;height:100%;"
                            + "background:#fff;z-index:9999\">I resign, effective today.</div>"
                            + "<p>Hi</p>"),
                       "<div>I resign, effective today.</div><p>Hi</p>")
        for style in ["position: absolute", "POSITION: Fixed !important", "position: sticky",
                      "position: relative; top: -400px", "position: relative; bottom: 400px",
                      "inset: -400px 0 0", "margin-top: -400px", "margin: 0 0 -20px",
                      "margin: calc(0px - 400px) 0 0", "-webkit-margin-before: -400px",
                      "transform: translateY(-400px)", "-webkit-transform: translateY(-400px)",
                      "translate: 0 -400px", "rotate: 180deg", "z-index: 10",
                      "color: red; @x { a: b } position: fixed"] {
            let out = made("<div style=\"\(style)\">x</div>")
            XCTAssertEqual(out, "<div>x</div>", "\(style) became \(out)")
        }
        for style in ["position: relative", "position: static", "margin: 0 auto",
                      "margin-top: 12px", "text-transform: uppercase",
                      "-webkit-text-size-adjust: 100%"] {
            XCTAssertEqual(made("<div style=\"\(style)\">x</div>"),
                           "<div style=\"\(style)\">x</div>", style)
        }
    }

    func testAStrayClosingTagCannotCloseTheQuoteAroundIt() {
        // The original is dropped inside Mail's
        // `<blockquote type="cite"><div dir="ltr">`. A `</div></blockquote>`
        // of its own would end that quote early, and everything after it
        // would sit below the bar as if he had written it.
        let out = made("<p>Inside</p></div></blockquote></td></body>After")
        XCTAssertEqual(out, "<p>Inside</p>After")
    }

    func testWhatTheOriginalLeavesOpenIsClosedAtTheEnd() {
        XCTAssertEqual(made("<div><table><tr><td><b>x"), "<div><table><tr><td><b>x</b></table></div>")
        // A paragraph or cell a browser closes by itself is left to it: an
        // extra `</p>` is read as an empty paragraph.
        XCTAssertEqual(made("<p>one<p>two"), "<p>one<p>two")
    }

    func testSelfClosedForeignContentAndAnEmptyCommentEndWhereABrowserEndsThem() {
        // `<svg/>` and `<math/>` have nothing inside them, and `<!-->` is a
        // whole comment. Read any other way, each took the rest with it.
        XCTAssertEqual(made("<p>a</p><svg/><p>rest</p>"), "<p>a</p><p>rest</p>")
        XCTAssertEqual(made("<p>a</p><math /><p>rest</p>"), "<p>a</p><p>rest</p>")
        XCTAssertEqual(made("<p>a</p><!--><p>b</p>"), "<p>a</p><p>b</p>")
    }

    func testAnAttributeIsWrittenOnceAndOnlyUnderAName() {
        // A quote in a name would close the value it is written into.
        XCTAssertEqual(made("<p a\"b=\"c\">x</p>"), "<p>x</p>")
        // The first of a repeated attribute is the one a browser uses, and
        // the only one that goes, so a second `src` cannot bring a picture
        // along that nothing shows.
        let (out, shown) = QuotedMarkup.made(
            "<img src=\"https://example.com/a.png\" src=\"cid:p\">", pictures: ["p": "bmquote1.x"])
        XCTAssertEqual(out, "<img src=\"https://example.com/a.png\">")
        XCTAssertEqual(shown, [])
    }

    func testMarkupCutOffMidTagEndsThere() {
        XCTAssertEqual(made("<p>whole</p><img src=\"https://exa"), "<p>whole</p>")
        XCTAssertEqual(made("<p>whole</p><!-- never closed <p>lost</p>"), "<p>whole</p>")
        XCTAssertEqual(made("<p>whole</p><script>alert(1)"), "<p>whole</p>")
    }

    // MARK: - Pictures by Content-ID

    func testAPictureTheLetterCarriesIsRenamedAndOneItDoesNotIsLeftOut() {
        let (out, shown) = QuotedMarkup.made("""
            <img src="cid:photo1@example"><img src="CID:sig-logo"><img src="cid:gone">\
            <td background="cid:photo1@example">x</td>\
            <div style="background-image: url('cid:photo1@example')">y</div>
            """, pictures: ["photo1@example": "bmquote1.abc", "sig-logo": "bmquote2.abc"])
        XCTAssertEqual(out, """
            <img src="cid:bmquote1.abc"><img src="cid:bmquote2.abc">\
            <td background="cid:bmquote1.abc">x</td>\
            <div style="background-image: url('cid:bmquote1.abc')">y</div>
            """)
        XCTAssertEqual(shown, ["bmquote1.abc", "bmquote2.abc"])
        XCTAssertFalse(out.contains("sig-logo"), "the signature's own id must not be left in the quote")
        XCTAssertFalse(out.contains("gone"))
    }

    func testAPictureIsFoundHoweverItsIDIsSpelt() {
        let (out, shown) = QuotedMarkup.made(
            "<img src=\"cid:II_Garden01\"><img src=\"cid:a%20b@x\">",
            pictures: ["ii_garden01": "bmquote1.x", "a b@x": "bmquote2.x"])
        XCTAssertEqual(out, "<img src=\"cid:bmquote1.x\"><img src=\"cid:bmquote2.x\">")
        XCTAssertEqual(shown, ["bmquote1.x", "bmquote2.x"])
    }

    func testEveryReferenceInAStyleIsRenamedOrTheStyleGoes() {
        // Two of the same picture: the second is looked for past the first
        // one's new id, which begins with the old one.
        let (out, shown) = QuotedMarkup.made(
            "<div style=\"background-image:url(cid:b); border-image:url(cid:b)\">x</div>",
            pictures: ["b": "bmquote1.0123456789ab"])
        XCTAssertEqual(out, "<div style=\"background-image:url(cid:bmquote1.0123456789ab); "
                       + "border-image:url(cid:bmquote1.0123456789ab)\">x</div>")
        XCTAssertEqual(shown, ["bmquote1.0123456789ab"])
        // A picture named other than by `url()`, as `image-set()` names
        // one, cannot keep an id that may be one of this letter's own.
        XCTAssertEqual(made("<p style=\"background-image: image-set('cid:sig-logo' 1x)\">x</p>",
                            ["sig-logo": "bmquote2.abc"]), "<p>x</p>")
    }

    func testThePicturesAMarkupRefersToAreFound() {
        XCTAssertEqual(QuotedMarkup.contentIDs(shownBy: """
            <img src="cid:ii_one"><img src='cid:two@x'> url(cid:three) <p>no cid here</p>
            """), ["ii_one", "two@x", "three"])
    }

    // MARK: - Addresses in plain text

    func testAWebAddressInPlainTextBecomesALink() {
        XCTAssertEqual(QuotedMarkup.linked("See https://www.youtube.com/watch?v=abc&t=10 now"),
                       "See <a href=\"https://www.youtube.com/watch?v=abc&amp;t=10\">"
                       + "https://www.youtube.com/watch?v=abc&amp;t=10</a> now")
    }

    func testAWikipediaAddressKeepsItsBracketsAndASentenceKeepsItsFullStop() {
        XCTAssertEqual(QuotedMarkup.linked("Read https://en.wikipedia.org/wiki/Mercury_(planet)."),
                       "Read <a href=\"https://en.wikipedia.org/wiki/Mercury_(planet)\">"
                       + "https://en.wikipedia.org/wiki/Mercury_(planet)</a>.")
        XCTAssertEqual(QuotedMarkup.linked("(see https://example.com/a)"),
                       "(see <a href=\"https://example.com/a\">https://example.com/a</a>)")
    }

    func testAWwwAddressIsLinkedToTheWeb() {
        XCTAssertEqual(QuotedMarkup.linked("at www.example.org, today"),
                       "at <a href=\"http://www.example.org\">www.example.org</a>, today")
    }

    func testALongLineFullOfAddressesIsLinkedInOnePass() {
        // A pasted list of links, as one line of 100 kB. Searched afresh to
        // the end of the line for each kind of address after each address,
        // this took seconds, on the actor Send and Save Draft wait on.
        var line = ""
        var n = 0
        while line.utf8.count < 100_000 {
            n += 1
            line += "see https://example.com/story/\(n) or www.example.org/\(n), "
        }
        let started = Date()
        let out = QuotedMarkup.linked(line)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(out.components(separatedBy: "<a href=").count - 1, 2 * n)
        XCTAssertTrue(out.hasSuffix("<a href=\"http://www.example.org/\(n)\">"
                                    + "www.example.org/\(n)</a>, "), String(out.suffix(120)))
        XCTAssertLessThan(elapsed, 1, "\(elapsed) s")
    }

    func testAnAddressStartsAWordAndAnAccentBelongsToItsLetter() {
        XCTAssertEqual(QuotedMarkup.linked("catchwww.example.org"), "catchwww.example.org")
        XCTAssertEqual(QuotedMarkup.linked("caf\u{E9}www.example.org"), "caf\u{E9}www.example.org")
        XCTAssertEqual(QuotedMarkup.linked("cafe\u{301}www.example.org"),
                       "cafe\u{301}www.example.org")
        XCTAssertEqual(QuotedMarkup.linked("\u{00A0}HTTPS://Example.com/A]"),
                       "\u{00A0}<a href=\"HTTPS://Example.com/A\">HTTPS://Example.com/A</a>]")
        XCTAssertEqual(QuotedMarkup.linked("[www.example.org/a_[b]]"),
                       "[<a href=\"http://www.example.org/a_[b]\">www.example.org/a_[b]</a>]")
    }

    func testTextThatIsNotAnAddressIsOnlyEscaped() {
        XCTAssertEqual(QuotedMarkup.linked("a < b & jane@www.example.com"),
                       "a &lt; b &amp; jane@www.example.com")
        XCTAssertEqual(QuotedMarkup.linked("just http:// and nothing"), "just http:// and nothing")
    }
}
