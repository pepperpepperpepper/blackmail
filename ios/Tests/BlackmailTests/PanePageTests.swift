import XCTest
@testable import Blackmail

/// The reading pane's pages, built from a downloaded letter away from the
/// main thread (`PanePage`). The building moved out of
/// `MessageDetailViewController` unchanged, and the page must come out byte
/// for byte as the pane built it there: the pane's CSS, the invert trick and
/// the inline-image rewrite all act on it, and "equivalent" markup is not
/// something anyone can vouch for without the iPad.
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
            letter(text: "\n\nhttps://example.com/a?b=1&c=2 </script>"),
            // A newsletter big enough to matter, in a debug build.
            letter(html: Self.newsletter(kilobytes: 48), pictures: pictures),
            letter(text: String(repeating: "A line of a long plain letter, <with> & more.\n", count: 800)),
            // A CRLF is one Character to Swift, so the trim never took it;
            // the decoder has made every line end LF by the time it gets here.
            letter(text: "\r\n\nDear Sam,"),
        ]
    }

    // MARK: - Byte for byte

    func testALettersPageComesOutByteForByteAsThePaneBuiltIt() {
        for (i, m) in letters.enumerated() {
            let page = PanePage.letter(m, style: style)
            XCTAssertEqual(page.map { Array($0.utf8) }, previousPage(m).map { Array($0.utf8) },
                           "letter \(i)")
        }
    }

    func testAStackBodyComesOutByteForByteAsThePaneBuiltIt() {
        for (i, m) in letters.enumerated() {
            let body = PanePage.stackBody(m)
            let previous = previousStackBody(m)
            XCTAssertEqual(Array(body.html.utf8), Array(previous.html.utf8), "letter \(i)")
            XCTAssertEqual(body.isHTML, previous.isHTML, "letter \(i)")
        }
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
}
