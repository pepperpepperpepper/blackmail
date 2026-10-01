import XCTest
@testable import Blackmail

/// Links written out as words in a letter, made tappable while the pane's
/// page is built (`TextLinks`). The pane runs no script of a letter's and
/// has WebKit's data detectors off, so an address written in a letter is
/// words unless the page carries it as `<a>`.
///
/// A letter is a stranger's text going into an HTML page, so most of what
/// is pinned here is what must NOT happen: markup let through, an attribute
/// or a script linked, a link inside a link, a letter changed that has no
/// link in it.
final class TextLinksTests: XCTestCase {

    /// The pane's own escaping of a plain letter (`PanePage.letter`).
    private func escape(_ text: Substring) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    }

    private func plain(_ text: String) -> String {
        TextLinks.plain(Substring(text), escaping: .ampersandAndLessThan)
    }

    /// The links `plain` makes of `text`, as their text.
    private func linked(_ text: String) -> [String] {
        let bytes = Array(text.utf8)
        return TextLinks.found(in: bytes, markup: false).map {
            String(decoding: bytes[$0.start..<$0.end], as: UTF8.self)
        }
    }

    private func anchors(in page: String) -> Int {
        page.components(separatedBy: "<a ").count - 1
    }

    // MARK: - Plain text

    /// A letter with no link in it is exactly what the pane made of it
    /// before, with each page's own escaping: every letter of his that
    /// carries no link reads as it did.
    func testALetterWithNoLinkIsEscapedAndNothingMore() {
        for text in ["", "Dear Sam,\n\nIt's <b>not</b> bold & it's \"quoted\" > here.",
                     "http:// and https:// alone", "www.example and www.", "mailto: nobody",
                     "ftp://example.com", "xhttp://example.com", "sam@www.example.com",
                     "\u{2028}é \u{1F4EE} &amp; &lt; <<>> \u{0}", "wwwexample.com", "https://\u{201D}"] {
            XCTAssertEqual(plain(text), escape(Substring(text)), text.debugDescription)
            XCTAssertEqual(TextLinks.plain(Substring(text), escaping: .ampersandAndBrackets),
                           ConversationDocument.escape(text), text.debugDescription)
        }
    }

    func testEachKindOfLinkBecomesALinkThatGoesWhereItSays() {
        XCTAssertEqual(plain("Watch https://youtu.be/aBcD3fGh1Jk?t=42 now"),
                       "Watch <a href=\"https://youtu.be/aBcD3fGh1Jk?t=42\">"
                       + "https://youtu.be/aBcD3fGh1Jk?t=42</a> now")
        XCTAssertEqual(plain("http://example.com/garden"),
                       "<a href=\"http://example.com/garden\">http://example.com/garden</a>")
        // `www.` goes to http://, as Mail sends it.
        XCTAssertEqual(plain("See www.example.com/show today"),
                       "See <a href=\"http://www.example.com/show\">www.example.com/show</a> today")
        XCTAssertEqual(plain("Write to mailto:sam@example.com?subject=Roses"),
                       "Write to <a href=\"mailto:sam@example.com?subject=Roses\">"
                       + "mailto:sam@example.com?subject=Roses</a>")
        // In any case.
        XCTAssertEqual(linked("HTTPS://EXAMPLE.COM/A WWW.EXAMPLE.COM MailTo:sam@example.com"),
                       ["HTTPS://EXAMPLE.COM/A", "WWW.EXAMPLE.COM", "MailTo:sam@example.com"])
    }

    /// Mail gives the punctuation that ends a sentence back to it, and keeps
    /// a bracket the link itself opened: a Wikipedia address ends `_(film)`.
    func testTheSentencesPunctuationIsGivenBack() {
        let url = "https://example.com/a"
        for (text, link) in [
            ("\(url).", url), ("\(url),", url), ("\(url);", url), ("\(url):", url),
            ("\(url)!", url), ("\(url)?", url), ("\(url)...", url), ("\(url)?!", url),
            ("'\(url)'", url), ("*\(url)*", url), ("(\(url))", url), ("(see \(url)).", url),
            ("[\(url)]", url), ("<\(url)>", url), ("\"\(url)\"", url),
            ("\u{201C}\(url)\u{201D}", url), ("\u{2018}\(url)\u{2019}", url),
            ("\u{00AB}\(url)\u{00BB}", url), ("\(url)\u{2026}", url),
            ("https://en.wikipedia.org/wiki/Roses_(film)", "https://en.wikipedia.org/wiki/Roses_(film)"),
            ("(https://en.wikipedia.org/wiki/Roses_(film)).", "https://en.wikipedia.org/wiki/Roses_(film)"),
            ("https://example.com/a?b=1&c=2#top.", "https://example.com/a?b=1&c=2#top"),
            ("https://example.com/", "https://example.com/"),
            ("http://[2001:db8::1]/a].", "http://[2001:db8::1]/a"),
            ("www.example.com.", "www.example.com"),
            ("mailto:sam@example.com.", "mailto:sam@example.com"),
        ] {
            XCTAssertEqual(linked(text), [link], text)
        }
    }

    func testALinkEndsAtSpaceLineBreakAndTheInvisibleSpaces() {
        XCTAssertEqual(linked("https://a.example.com\nhttps://b.example.com\r\nwww.c.example.com\tx"),
                       ["https://a.example.com", "https://b.example.com", "www.c.example.com"])
        for space in ["\u{00A0}", "\u{2009}", "\u{3000}", "\u{200B}", "\u{FEFF}", "\u{2028}"] {
            XCTAssertEqual(linked("https://example.com/a\(space)b"), ["https://example.com/a"],
                           space.unicodeScalars.first!.debugDescription)
        }
        XCTAssertEqual(linked("https://example.com/caf\u{00E9}/\u{1F339}"),
                       ["https://example.com/caf\u{00E9}/\u{1F339}"])
    }

    /// Not links: run on from a word, a scheme with nothing after it, a
    /// `www.` whose host has no dot, a `www` inside an address or a host
    /// already under way, a `mailto:` with no `@`.
    func testWhatIsNotALink() {
        for text in ["xhttp://example.com", "3https://example.com", "http://", "https://.",
                     "https://-", "http:// example.com", "www.", "www.example", "www..com",
                     "sam@www.example.com", "a.www.example.com", "//www.example.com",
                     "mailto:", "mailto:sam", "mailto:sam@", "mailto:sam@.",
                     "mailto:mailto:mailto:",
                     // Control characters one bit away from `:` and `/`.
                     "http\u{1A}\u{0F}\u{0F}example.com", "www\u{0E}example.com"] {
            XCTAssertEqual(linked(text), [], text)
        }
    }

    /// Every character is in one link at most: a `www.` or a second
    /// address inside a link is part of it.
    func testNothingIsLinkedTwice() {
        for text in ["https://www.example.com", "http://example.com/http://example.org",
                     "https://example.com/?next=www.example.org", "mailto:www.sam@example.com",
                     "https://example.com/mailto:sam@example.com"] {
            let page = plain(text)
            XCTAssertEqual(anchors(in: page), 1, page)
            XCTAssertEqual(linked(text), [text])
        }
        XCTAssertEqual(anchors(in: plain("https://a.example.com https://b.example.com")), 2)
    }

    /// The link's text is escaped as the words around it are, and its
    /// address as an attribute: the sender's `<`, `&` and `"` never reach
    /// the page as markup.
    func testALinkIsEscapedInsideAndOut() {
        let page = plain("a <b> & https://example.com/a?b=1&c=it's \"then\" <script>")
        XCTAssertEqual(page, "a &lt;b> &amp; <a href=\"https://example.com/a?b=1&amp;c=it's\">"
                       + "https://example.com/a?b=1&amp;c=it's</a> \"then\" &lt;script>")
        // With the conversation's escaping, `>` as well.
        let stack = TextLinks.plain("x > https://example.com/a>b", escaping: .ampersandAndBrackets)
        XCTAssertEqual(stack, "x &gt; <a href=\"https://example.com/a\">https://example.com/a</a>&gt;b")
    }

    // MARK: - HTML

    private func html(_ markup: String) -> String { TextLinks.html(markup) }

    /// A link in an HTML letter's text is the text as it stands, references
    /// and all, so it reads as it did; `&amp;` is the `&` it means, and the
    /// sentence's full stop is given back.
    func testALinkInHTMLTextBecomesALink() {
        XCTAssertEqual(html("<p>See https://example.com/a?b=1&amp;c=2.</p>"),
                       "<p>See <a href=\"https://example.com/a?b=1&amp;c=2\">"
                       + "https://example.com/a?b=1&amp;c=2</a>.</p>")
        XCTAssertEqual(html("<div>www.example.com</div><div>mailto:sam@example.com</div>"),
                       "<div><a href=\"http://www.example.com\">www.example.com</a></div>"
                       + "<div><a href=\"mailto:sam@example.com\">mailto:sam@example.com</a></div>")
        // A trailing `&amp;` is the `&`: its `;` is not a sentence's.
        XCTAssertEqual(html("https://example.com/?a=1&amp;"),
                       "<a href=\"https://example.com/?a=1&amp;\">https://example.com/?a=1&amp;</a>")
    }

    /// Any other character reference may stand for a space, a quote or a
    /// bracket, and ends the link; so does one without its `;` that reads
    /// as `<`, `>`, `"` or a no-break space.
    func testACharacterReferenceEndsALink() {
        for (markup, link) in [
            ("&lt;https://example.com/a&gt;", "https://example.com/a"),
            ("&quot;https://example.com/a&quot;", "https://example.com/a"),
            ("&nbsp;https://example.com/a&nbsp;b", "https://example.com/a"),
            ("https://example.com/a&#32;b", "https://example.com/a"),
            ("https://example.com/a&#x3C;b", "https://example.com/a"),
            ("https://example.com/a&rsquo;s", "https://example.com/a"),
            ("https://example.com/a&lt b", "https://example.com/a"),
            ("https://example.com/?a=1&b=2", "https://example.com/?a=1&b=2"),
        ] {
            let bytes = Array(markup.utf8)
            XCTAssertEqual(TextLinks.found(in: bytes, markup: true).map {
                String(decoding: bytes[$0.start..<$0.end], as: UTF8.self)
            }, [link], markup)
        }
    }

    /// Nothing but text is linked: not the sender's own links, nor
    /// anything inside a tag, an attribute, a comment or a declaration,
    /// nor a script, a style, a title, a text box, a list box, a picture
    /// drawn in SVG or MathML, a frame or `<noscript>`, nor the raw text of
    /// `<xmp>`, `<noembed>` and `<noframes>`, where WebKit would show an
    /// `<a>` as the characters it is written with. Such an element ends
    /// only at its own end tag, its name followed by white space, `/` or
    /// `>`: `</textareax>` is text inside the box, and so is what follows.
    func testOnlyTextIsLinked() {
        for markup in [
            "<a href=\"https://example.com\">https://example.com</a>",
            "<A HREF=https://example.com><b>see https://example.com/b</b></A>",
            "<a name=\"top\">www.example.com</a>",
            "<img alt=\"https://example.com\" src=\"cid:x\">",
            "<div title='www.example.com' data-x=https://example.com>",
            "<div title=\"a > https://example.com\">",
            "<p class=https://example.com/>",
            "<style>/* https://example.com */ a { color: red }</style>",
            "<STYLE type=text/css>@import url(https://example.com/a.css);</STYLE >",
            "<script>var u = \"https://example.com\";</script>",
            "<title>www.example.com</title>",
            "<textarea>https://example.com</textarea>",
            "<xmp>https://example.com</xmp>",
            "<noembed>https://example.com</noembed>",
            "<noframes>https://example.com</noframes>",
            "<textarea>x</textareax> https://example.com</textarea>",
            "<title>x</titles> https://example.com</title>",
            "<xmp>x</xmp2> https://example.com</xmp>",
            "<select><option>https://example.com</option></select>",
            "<svg><text>https://example.com</text></svg>",
            "<math><mtext>https://example.com</mtext></math>",
            "<iframe>https://example.com</iframe>",
            "<noscript>https://example.com</noscript>",
            "<!-- https://example.com -->",
            "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0\" \"http://www.w3.org/TR/xhtml1/DTD/x.dtd\">",
            "<![CDATA[ https://example.com ]]>",
            "<?xml version=\"1.0\" href=\"https://example.com\"?>",
            "</div title=\"https://example.com\">",
            "</ https://example.com>",
        ] {
            XCTAssertEqual(html(markup), markup, markup)
        }
    }

    /// After each of those, text is text again, and its links are linked.
    func testTextAfterMarkupIsLinkedAgain() {
        for markup in ["<a href=\"x\">x</a>", "<A HREF=x>x</A>", "<style>a{}</style>",
                       "<script>x</script >", "<!---->", "<!-->", "<!--->", "<!-- x --!>",
                       "<textarea>x</TEXTAREA>", "<img src='a>b'>", "<br/>", "<p class=x>",
                       "<!DOCTYPE html>", "a < b", "</>", "<iframe src=x></iframe>",
                       "<table><tr><td><a href=x>x</a>"] {
            XCTAssertEqual(html(markup + " https://example.com"),
                           markup + " <a href=\"https://example.com\">https://example.com</a>",
                           markup)
        }
    }

    /// Where the markup does not go on in a way the pass can follow, the
    /// rest of the letter is left exactly as it came, and what came before
    /// keeps its links.
    func testMarkupThePassCannotFollowIsLeftAlone() {
        let first = "<p>https://a.example.com "
        let linkedFirst = "<p><a href=\"https://a.example.com\">https://a.example.com</a> "
        for rest in ["<!-- https://b.example.com", "<script>https://b.example.com",
                     "<div title=\"https://b.example.com", "<div https://b.example.com",
                     "<plaintext>https://b.example.com", "<a href=x>https://b.example.com",
                     "</div", "<style>x</style",
                     // Where HTML can leave a sender's `<a>` open unseen.
                     "<svg><p><a href=x></svg> https://b.example.com",
                     "<math><b><a href=x></math> https://b.example.com",
                     "<noscript><a href=x></noscript> https://b.example.com",
                     "<select></td><a href=x></select> https://b.example.com",
                     "<script><!--<script></script></script> https://b.example.com",
                     "<SVG></SVG> https://b.example.com"] {
            XCTAssertEqual(html(first + rest), linkedFirst + rest, rest)
        }
    }

    /// HTML ignores an `</a>` that would close the sender's `<a>` across a
    /// table, a cell, a caption, an object or a template the `<a>`
    /// encloses, and what follows is still inside the sender's link: so the
    /// rest of the letter is taken to be, and nothing more is linked in it.
    /// An `<a>` and its `</a>` inside one cell close as ever.
    func testASendersLinkAroundATableIsNeverTakenAsClosed() {
        for enclosed in ["<table><tr><td>", "<td>", "<th>", "<caption>", "<object>", "<template>",
                         "<applet>", "<marquee>", "<TABLE class=x>"] {
            let markup = "<a href=x>\(enclosed)</a> https://b.example.com</td></table> https://c.example.com"
            XCTAssertEqual(html(markup), markup, enclosed)
        }
        XCTAssertEqual(html("<table><tr><td><a href=x>x</a> https://b.example.com</td></tr></table>"),
                       "<table><tr><td><a href=x>x</a> "
                       + "<a href=\"https://b.example.com\">https://b.example.com</a></td></tr></table>")
    }

    /// A letter with no link written in its text comes back as it came,
    /// the same string.
    func testAnHTMLLetterWithNoLinkInItsTextComesBackAsItCame() {
        let newsletter = PanePageTests.newsletter(kilobytes: 48)
        XCTAssertEqual(Array(html(newsletter).utf8), Array(newsletter.utf8))
    }

    // MARK: - Seeded letters

    /// Letters put together at random, from a fixed seed, out of the
    /// pieces that matter here: addresses of every kind, words and
    /// punctuation, references, tags with attributes quoted every way, the
    /// sender's own links, scripts, styles, comments, declarations, and
    /// the tables and foreign markup that make HTML hold a link open. For
    /// each: what the pass adds is `<a href="…">` and `</a>` around a link
    /// whose text is its address, and nothing else, so taking them out
    /// gives the letter back byte for byte; and doing it twice changes
    /// nothing, since a link is never linked again.
    func testSeededLettersGainLinksAndNothingElse() {
        var seed: UInt64 = 20_260_930
        func next(_ n: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(n))
        }
        func pick(_ choices: [String]) -> String { choices[next(choices.count)] }
        let addresses = ["https://example.com/a?b=1&amp;c=2", "http://example.com/x_(y)",
                         "www.example.com/p", "mailto:sam@example.com?subject=Hi", "HTTPS://EXAMPLE.COM",
                         "https://example.com/&quot;x", "https://example.com&lt;b", "www.a.example.org.",
                         "https://en.wikipedia.org/wiki/Roses_(film)", "https://example.com/caf\u{00E9}",
                         "https://example.com/a&nbsp;b", "https://example.com/?a=1&b=2", "mailto:nobody", "www.x"]
        let words = ["Dear", "Sam,", "(", ")", ".", "&amp;", "&lt;", "&gt;", "&nbsp;", "&", "<", ">", "\"",
                     "'", "\u{201C}", "\u{201D}", "\n", " ", "a<b", "&#169;", "\u{2014}"]
        let markup = ["<p>", "</p>", "<div class=x>", "</div>", "<b>", "</b>", "<br/>", "<table>", "<tr>",
                      "<td>", "</td>", "</table>", "<img src='a>b' alt=\"https://example.com\">",
                      "<a class=s href=\"https://example.com\">", "</a>", "<!-- https://example.com -->",
                      "<style>a{}</style>", "<script>var u='https://example.com'</script>", "<!DOCTYPE html>",
                      "<title>www.example.com</title>", "<object>", "<svg><p><a href=x></svg>", "</ x>",
                      "<span title='www.example.com' data=https://example.com>", "</span>"]
        for _ in 0..<1_500 {
            var letter = ""
            for _ in 0..<(1 + next(14)) {
                switch next(3) {
                case 0: letter += pick(addresses)
                case 1: letter += pick(words) + pick(["", " "])
                default: letter += pick(markup)
                }
            }
            let linked = TextLinks.html(letter)
            XCTAssertEqual(TextLinks.html(linked), linked, letter.debugDescription)
            XCTAssertEqual(unlinked(linked), letter, letter.debugDescription)
        }
    }

    /// `page` with every `<a href="X">T</a>` this pass writes taken out,
    /// T kept: those whose address is their text, or `http://` and it.
    private func unlinked(_ page: String) -> String {
        var out = ""
        var rest = Substring(page)
        while let open = rest.range(of: "<a href=\"") {
            out += rest[..<open.lowerBound]
            let after = rest[open.upperBound...]
            guard let hrefEnd = after.range(of: "\">"),
                  let close = after[hrefEnd.upperBound...].range(of: "</a>") else {
                out += rest[open.lowerBound...]
                return out
            }
            let href = after[..<hrefEnd.lowerBound]
            let text = after[hrefEnd.upperBound..<close.lowerBound]
            if href == text || href == "http://" + text {
                out += text
                rest = after[close.upperBound...]
            } else {
                out += rest[open.lowerBound..<open.upperBound]
                rest = after
            }
        }
        return out + rest
    }

    // MARK: - The work grows with the letter

    /// Letters built to make a pass like this go back over what it has
    /// read: false starts, links that fail at the end of a long run, runs of
    /// brackets for the balance, tags, comments and scripts left open. Each
    /// is measured at 32 KB and at 128 KB, by the bytes the pass looks at
    /// rather than by the clock, which does not flake. The pass is linear:
    /// four times the letter is about four times the steps, and five is the
    /// bound, where going back over each run would be sixteen. The larger
    /// is held to a few steps a byte as well.
    func testNoLetterMakesTheWorkGrowFasterThanTheLetter() {
        func hostile(_ bytes: Int) -> [(String, Bool)] {
            func repeated(_ unit: String) -> String {
                String(repeating: unit, count: bytes / unit.utf8.count)
            }
            return [
                (repeated("mailto:"), false),
                (repeated("mailto:a"), false),
                (repeated("www.-"), false),
                (repeated("http://."), false),
                (repeated("https://"), false),
                ("https://example.com/" + repeated("."), false),
                ("https://example.com/" + repeated(")"), false),
                ("mailto:a@" + repeated("."), false),
                ("www.a" + repeated("a"), false),
                (repeated("www.a=www="), false),
                (repeated("www.a?"), false),
                (repeated("www.a#"), false),
                (repeated("<!--"), true),
                (repeated("<a "), true),
                (repeated("<"), true),
                (repeated("</"), true),
                (repeated("<script>"), true),
                (repeated("<svg>"), true),
                (repeated("<plaintext"), true),
                (repeated("&amp;"), true),
                ("https://" + repeated("&amp;"), true),
                ("https://example.com/" + repeated("&amp;."), true),
                (repeated("<div title=\"x\" "), true),
                (repeated("https://example.com&lt;"), true),
                (repeated("<script></scrip"), true),
            ]
        }
        let small = hostile(32 * 1_024), large = hostile(128 * 1_024)
        for ((text, markup), (big, _)) in zip(small, large) {
            let quarter = TextLinks.steps(in: Array(text.utf8), markup: markup)
            let whole = TextLinks.steps(in: Array(big.utf8), markup: markup)
            let name = String(text.prefix(24)).debugDescription
            XCTAssertLessThanOrEqual(whole, quarter * 5, "\(name): \(quarter), then \(whole)")
            XCTAssertLessThanOrEqual(whole, big.utf8.count * 8, "\(name): \(whole)")
        }
    }
}
