import XCTest
@testable import Blackmail

/// The reading pane's pages, built from a downloaded letter away from the
/// main thread (`PanePage`). The building moved out of
/// `MessageDetailViewController` unchanged, and the page must come out byte
/// for byte as the pane built it there: the pane's CSS, the invert trick and
/// the inline-image rewrite all act on it, and "equivalent" markup is not
/// something anyone can vouch for without the iPad.
///
/// Since B-055 a link written out in a letter is made a link (`TextLinks`),
/// and that is the one change to a letter's markup: a letter with none comes
/// out as it did, and the letter here with one differs by its `<a>` alone.
/// Since B-101 an HTML letter's page has Mail's bars beside quoted text
/// (`QuoteBars`), rules added to its style and nothing else.
final class PanePageTests: XCTestCase {

    /// The pane's measurements as `Theme` gives them on the iPad.
    private let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)

    // MARK: - The pane's code before it moved, kept as the reference

    /// `MessageDetailViewController.render` as it was, with `Theme`'s
    /// numbers taken from `style`; nil where it drew the empty notice.
    private func previousPage(_ m: Message) -> String? {
        let known = Set(m.attachments.compactMap(\.contentID))
        guard !MailText.hasNoVisibleContent(text: m.textBody, html: m.htmlBody) else { return nil }
        let isHTML = m.htmlBody != nil
        let content = isHTML
            ? InlineImageRewriter.rewrite(DocumentWrapper.stripped(from: m.htmlBody!), known: known)
            : (m.textBody ?? "")
                .drop(while: { $0 == "\n" || $0 == "\r" })
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
        let smartInvert = isHTML
            ? """
              #bm { filter: invert(1) hue-rotate(180deg); background: #fff; }
              #bm img, #bm video, #bm svg, #bm picture, #bm [style*="background-image"] {
                  filter: invert(1) hue-rotate(180deg); }
              """
            : ""
        let wrapped = """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html { -webkit-text-size-adjust: 100%; }
          html, body { margin: 0; padding: 0; background: #000; }
          #bm { padding: \(style.inset)px;
                font: \(style.bodyPointSize)px -apple-system, sans-serif;
                line-height: \(style.lineHeight);
                color: \(isHTML ? "#000" : "#fff"); word-wrap: break-word;\
        \(isHTML ? "" : " white-space: pre-wrap;") }
          img, table { max-width: 100% !important; height: auto; }
          a { color: \(isHTML ? "#007AFF" : "#0A84FF"); }
          \(smartInvert)
        </style></head><body><div id="bm">\(content)</div></body></html>
        """
        return wrapped
    }

    /// `MessageDetailViewController.drawBody` as it was.
    private func previousStackBody(_ m: Message) -> ConversationDocument.Entry.Rendered {
        let known = Set(m.attachments.compactMap(\.contentID))
        let isHTML = m.htmlBody != nil
        let empty = MailText.hasNoVisibleContent(text: m.textBody, html: m.htmlBody)
        let content = empty
            ? "<span class=\"bm-waiting\">\(MailText.emptyBodyNotice)</span>"
            : (isHTML
               ? InlineImageRewriter.rewrite(DocumentWrapper.stripped(from: m.htmlBody!), known: known)
               : ConversationDocument.escape(String((m.textBody ?? "").drop(while: {
                   $0 == "\n" || $0 == "\r" }))))
        return .init(html: content, isHTML: isHTML && !empty)
    }

    // MARK: - Letters

    private func letter(text: String? = nil, html: String? = nil,
                        pictures: [String] = []) -> Message {
        let attachments = pictures.enumerated().map { i, cid in
            Attachment(id: "\(i + 2)", filename: "image\(i).png", mimeType: "image/png",
                       size: 2_000, contentID: cid)
        }
        return Message(id: "7/3", mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                       senderAddress: "sam@example.com", to: ["me@example.com"], cc: [],
                       subject: "The garden", date: Date(timeIntervalSince1970: 1_790_000_000),
                       textBody: text, htmlBody: html, attachments: attachments)
    }

    /// A newsletter of about `kilobytes`: a styled wrapper, sections under
    /// HTML5 `<header>`s, tables, inline styles, pictures by `cid:`, links,
    /// quotes of both kinds and text outside ASCII.
    static func newsletter(kilobytes: Int) -> String {
        var html = """
        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
        <html xmlns="http://www.w3.org/1999/xhtml"><head><meta charset="utf-8"><title>Garden club news</title>
        <style type="text/css">body { margin: 0 } .wrap { width: 600px } td { padding: 8px }</style></head>
        <body style="margin:0; padding:0;" bgcolor="#ffffff"><img src="cid:logo@example.com" width="120">
        """
        var i = 0
        while html.utf8.count < kilobytes * 1_024 {
            i += 1
            html += """
            <header class="masthead"><h2>Section \(i): the spring show</h2></header>
            <table class="wrap" cellpadding="0" style="border-collapse: collapse; font-family: Georgia, serif;">
            <tr><td style="color:#333333;">It's on the 12th, at the hall on the corner — "bring a chair".
            Entries close on Friday; the café opens at ten. <a href="https://example.com/show/\(i)">Details</a>
            &amp; tickets at the door, £5 &lt;cash only&gt;.</td>
            <td><img src="cid:photo\(i % 7)@example.com" alt="Photo \(i)"> <img src="cid:gone@example.com"></td></tr>
            </table>
            <blockquote style="margin:0 0 0 .8ex; border-left:1px #ccc solid;">On Monday, Sam wrote:<br>
            Can we bring the roses?</blockquote>

            """
        }
        return html + "</body></html>"
    }

    private var letters: [Message] {
        let pictures = ["logo@example.com"] + (0..<7).map { "photo\($0)@example.com" }
        return [
            // Shapes of real mail, as `DocumentWrapperTests` has them.
            letter(html: """
            <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "x">
            <html lang="en"><head><title>Garden club news</title>
            <style type="text/css">body { margin: 0 }</style></head>
            <body style="margin:0; padding:0;"><table class="wrap"><tr><td><p>The spring show
            is on the 12th.</p></td></tr></table></body></html>
            """),
            letter(html: "<HTML><HEAD>\r\n<META http-equiv=Content-Type content=\"text/html\">\r\n"
                   + "<STYLE>P.MsoNormal { MARGIN: 0cm }</STYLE></HEAD>\r\n<BODY lang=EN-GB>\r\n"
                   + "<DIV class=WordSection1><P class=MsoNormal>Dear Sam,</P></DIV></BODY></HTML>"),
            letter(text: "See you on Sunday.\n\nCarlo",
                   html: "<html><head></head><body style=\"overflow-wrap: break-word;\">"
                   + "<div dir=\"ltr\">See you on Sunday.<br><br><div>Carlo</div></div></body></html>"),
            letter(html: "<div dir=\"ltr\">Thanks for the photos.<div><br></div><div>Sam</div></div>"),
            letter(html: "<html><head><title>News</title></head><body><header><h1>Garden club</h1>"
                   + "</header><p>Look.</p></body></html>"),
            // Pictures: known, unknown, and a letter that is only a picture.
            letter(html: "<p>Logo: <img src=\"cid:logo@example.com\"> and <img src='CID:gone'></p>",
                   pictures: ["logo@example.com"]),
            letter(html: "<img src=\"cid:photo0@example.com\">", pictures: ["photo0@example.com"]),
            // Nothing in them, which the pane says in words.
            letter(html: "<html><body>  <br> </body></html>"),
            letter(text: " \n\n \t"),
            letter(),
            // Plain text: this app's own replies open with blank lines, and
            // text carries everything markup would take for its own.
            letter(text: "\n\nDear Sam,\n\nIt's <b>not</b> bold & it's \"quoted\" > here.\n"
                   + "\u{2028}é \u{1F4EE}\n\n> On Monday, Carlo wrote:\n> The roses?"),
            // The one with a link written in it (`linked`).
            letter(text: "\n\nhttps://example.com/a?b=1&c=2 </script>"),
            // A newsletter big enough to matter, in a debug build.
            letter(html: Self.newsletter(kilobytes: 48), pictures: pictures),
            letter(text: String(repeating: "A line of a long plain letter, <with> & more.\n", count: 800)),
            // A CRLF is one Character to Swift, so the trim never took it;
            // the decoder has made every line end LF by the time it gets here.
            letter(text: "\r\n\nDear Sam,"),
            // Replies, with quotes Mail draws a bar beside (B-101).
            letter(text: "Yes, Sunday.", html: Self.appleMailReply),
            letter(text: "Thanks!", html: Self.gmailReply),
        ]
    }

    /// A reply from Mail on an iPad, its quote three deep, as Mail writes
    /// one: the attribution in a blockquote of its own, and bare
    /// blockquotes, with no style.
    static let appleMailReply = "<html><head><meta http-equiv=\"content-type\" "
        + "content=\"text/html; charset=utf-8\"></head><body dir=\"auto\">"
        + "<div dir=\"ltr\">Yes, Sunday.</div><div dir=\"ltr\"><br><blockquote type=\"cite\">"
        + "On 20 Oct 2026, at 09:12, Sam Example wrote:<br><br></blockquote></div>"
        + "<blockquote type=\"cite\"><div dir=\"ltr\">Lunch on Sunday?<br>"
        + "<blockquote type=\"cite\">Or Saturday?<blockquote type=\"cite\">The garden is ready."
        + "</blockquote></blockquote></div></blockquote></body></html>"

    /// The markup the pane draws of it: the wrapper gone, nothing else.
    static let appleMailReplyBody = "<div dir=\"ltr\">Yes, Sunday.</div><div dir=\"ltr\"><br>"
        + "<blockquote type=\"cite\">On 20 Oct 2026, at 09:12, Sam Example wrote:<br><br>"
        + "</blockquote></div><blockquote type=\"cite\"><div dir=\"ltr\">Lunch on Sunday?<br>"
        + "<blockquote type=\"cite\">Or Saturday?<blockquote type=\"cite\">The garden is ready."
        + "</blockquote></blockquote></div></blockquote>"

    /// A reply from Gmail's web page: its quote a `gmail_quote` with Gmail's
    /// own grey bar written on it.
    static let gmailReply = "<div dir=\"ltr\">Thanks!</div><br><div class=\"gmail_quote\">"
        + "<div dir=\"ltr\" class=\"gmail_attr\">On Mon, 20 Oct 2026 at 09:12, Sam Example wrote:"
        + "<br></div><blockquote class=\"gmail_quote\" style=\"margin:0px 0px 0px 0.8ex;"
        + "border-left:1px solid rgb(204,204,204);padding-left:1ex\"><div dir=\"ltr\">"
        + "Lunch on Sunday?</div></blockquote></div>"

    // MARK: - Byte for byte

    /// Which of `letters` has a link written in it.
    private static let linked = 11

    /// Byte for byte, but for Mail's quote bars (B-101): in an HTML
    /// letter's style once, after the invert, and in a plain letter's not
    /// at all. Taken out, the page is the page the pane built.
    func testALettersPageComesOutByteForByteAsThePaneBuiltIt() {
        let bars = "\n" + QuoteBars.css(in: "#bm")
        for (i, m) in letters.enumerated() where i != Self.linked {
            let page = PanePage.letter(m, style: style)
            XCTAssertEqual(page.map { $0.components(separatedBy: bars).count - 1 },
                           page.map { _ in m.htmlBody == nil ? 0 : 1 }, "letter \(i)")
            XCTAssertEqual(page.map { Array($0.replacingOccurrences(of: bars, with: "").utf8) },
                           previousPage(m).map { Array($0.utf8) }, "letter \(i)")
        }
    }

    func testAStackBodyComesOutByteForByteAsThePaneBuiltIt() {
        for (i, m) in letters.enumerated() where i != Self.linked {
            let body = PanePage.stackBody(m)
            let previous = previousStackBody(m)
            XCTAssertEqual(Array(body.html.utf8), Array(previous.html.utf8), "letter \(i)")
            XCTAssertEqual(body.isHTML, previous.isHTML, "letter \(i)")
        }
    }

    /// The letter with a link in it: the page the pane built, and the stack
    /// body, with the link made a link and nothing else changed. Escaped as
    /// before around it and in it, `&` as `&amp;` in the address too, and the
    /// `</script>` after it still words.
    func testALinkIsTheOnlyChangeToTheLetterWithOne() throws {
        let m = letters[Self.linked]
        let written = "https://example.com/a?b=1&amp;c=2"
        let link = "<a href=\"\(written)\">\(written)</a>"
        let before = try XCTUnwrap(previousPage(m))
        XCTAssertTrue(before.contains("<div id=\"bm\">\(written) &lt;/script></div>"), before)
        XCTAssertEqual(PanePage.letter(m, style: style),
                       before.replacingOccurrences(of: "<div id=\"bm\">\(written) ",
                                                   with: "<div id=\"bm\">\(link) "))
        XCTAssertEqual(PanePage.stackBody(m),
                       .init(html: "\(link) &lt;/script&gt;", isHTML: false))
        XCTAssertEqual(previousStackBody(m), .init(html: "\(written) &lt;/script&gt;", isHTML: false))
    }

    /// An HTML letter's links written in its text are made links too, in
    /// its page and in its stack body alike, after its wrapper has come off
    /// and its pictures are pointed at the loader.
    func testAnHTMLLettersLinksAreMadeLinksInBothPlaces() throws {
        let m = letter(html: "<html><body><p>Photos: https://example.com/garden.</p>"
                       + "<img src=\"cid:logo@example.com\"></body></html>",
                       pictures: ["logo@example.com"])
        let body = "<p>Photos: <a href=\"https://example.com/garden\">https://example.com/garden</a>.</p>"
            + "<img src=\"bmcid://logo%40example.com\">"
        XCTAssertTrue(try XCTUnwrap(PanePage.letter(m, style: style)).contains("<div id=\"bm\">\(body)</div>"))
        XCTAssertEqual(PanePage.stackBody(m), .init(html: body, isHTML: true))
    }

    /// Spot checks that the reference above is the page he sees: the
    /// wrapper gone, the known picture pointed at the loader and the unknown
    /// one left alone, the words for an empty letter, and text escaped with
    /// its leading blank lines gone.
    func testThePagesSayWhatThePaneShows() throws {
        let pictured = try XCTUnwrap(PanePage.letter(letters[5], style: style))
        XCTAssertTrue(pictured.contains("<img src=\"bmcid://logo%40example.com\">"), pictured)
        XCTAssertTrue(pictured.contains("<img src='cid:gone'>"), pictured)
        XCTAssertTrue(pictured.contains("#bm { filter: invert(1)"), "HTML is inverted")
        XCTAssertNil(PanePage.letter(letters[7], style: style), "nothing in it")
        XCTAssertEqual(PanePage.stackBody(letters[9]),
                       .init(html: "<span class=\"bm-waiting\">This message has no text.</span>",
                             isHTML: false))
        let text = try XCTUnwrap(PanePage.letter(letters[10], style: style))
        XCTAssertTrue(text.contains("<div id=\"bm\">Dear Sam,\n\nIt's &lt;b>not&lt;/b> bold &amp;"),
                      text)
        XCTAssertTrue(text.contains("white-space: pre-wrap;"))
        XCTAssertTrue(PanePage.stackBody(letters[10]).html
                        .hasPrefix("Dear Sam,\n\nIt's &lt;b&gt;not&lt;/b&gt; bold &amp;"))
        XCTAssertEqual(PanePage.contentIDs(of: letters[12]).count, 8)
    }

    // MARK: - Mail's bars beside quoted text (B-101)

    /// Mail's own rules, from iOS 18.6's MessageUI: its quote, `type=cite`,
    /// and Gmail's, one, two and three deep, in any mix of the two; 5 px
    /// from the words, no margin, a 1 px bar, the words in the bar's
    /// colour, violet, teal and green, every one important; and each under
    /// `#bm`, the letter's own element on the page.
    func testAnHTMLLettersPageHasMailsBarsBesideQuotedText() throws {
        let quote = ":is(blockquote[type=cite i], blockquote[class~=gmail_quote])"
        func rule(_ selector: String, _ colour: String) -> String {
            "\(selector) { padding-left: 5px !important; margin: 0 !important; "
                + "border-left: 1px solid \(colour) !important; color: \(colour) !important; }"
        }
        let rules = [
            rule("#bm \(quote)", "rgb(88, 86, 214)"),
            rule("#bm \(quote) \(quote)", "rgb(0, 175, 205)"),
            rule("#bm \(quote) \(quote) \(quote)", "rgb(18, 192, 14)"),
        ]
        XCTAssertEqual(QuoteBars.css(in: "#bm"), rules.joined(separator: "\n"))

        for m in [letters[letters.count - 2], letters[letters.count - 1]] {
            let page = try XCTUnwrap(PanePage.letter(m, style: style))
            let sheet = try XCTUnwrap(page.components(separatedBy: "</style>").first)
            // After the invert, so the pictures' rule is untouched, and
            // every rule's selector under #bm.
            XCTAssertTrue(sheet.hasSuffix("filter: invert(1) hue-rotate(180deg); }\n"
                                          + rules.joined(separator: "\n") + "\n"), sheet)
            XCTAssertEqual(sheet.components(separatedBy: "blockquote[").count - 1, 2 + 4 + 6)
            XCTAssertEqual(sheet.components(separatedBy: "#bm :is(").count - 1, 3)
            XCTAssertEqual(sheet.components(separatedBy: " !important;").count - 1, 12 + 1,
                           "each rule's four, and the pictures' width")
        }
        // A plain letter's quotes are words: no rule for a blockquote.
        let plain = try XCTUnwrap(PanePage.letter(letters[10], style: style))
        XCTAssertFalse(plain.contains("blockquote"), plain)
    }

    /// Mail's reply and Gmail's keep their markup byte for byte, on the
    /// letter's page and in a conversation's stack: the bars are rules in
    /// the style, and the quotes are drawn as they came, Gmail's own grey
    /// bar still written on its quote.
    func testARepliesMarkupIsAsItCameForTheBars() throws {
        let replies = [(letters[letters.count - 2], Self.appleMailReplyBody),
                       (letters[letters.count - 1], Self.gmailReply)]
        for (m, body) in replies {
            let page = try XCTUnwrap(PanePage.letter(m, style: style))
            XCTAssertTrue(page.hasSuffix("<div id=\"bm\">\(body)</div></body></html>"), page)
            XCTAssertEqual(PanePage.stackBody(m), .init(html: body, isHTML: true))
        }
    }
}
