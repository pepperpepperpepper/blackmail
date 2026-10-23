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
        PaneLetters.letter(text: text, html: html, pictures: pictures)
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

    /// The shapes of real mail the pane is checked against, which a printed
    /// letter is checked against too (`PrintPageTests`).
    private var letters: [Message] { PaneLetters.all }

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

    // MARK: - The pictures' loader (B-110)

    /// `MessageDetailViewController.prepareInlineImages`'s map as it was
    /// built there, before the pane and a printed letter both read it from
    /// `PanePage.pictures`.
    private func previousPictures(_ letters: [Message])
        -> [String: (letter: Message, section: String, mimeType: String)] {
        var parts: [String: (letter: Message, section: String, mimeType: String)] = [:]
        for m in letters {
            for attachment in m.attachments {
                guard let cid = attachment.contentID else { continue }
                parts[cid] = (m, attachment.id, attachment.mimeType)
            }
        }
        return parts
    }

    /// The map the pane built: each `Content-ID` to its part and its
    /// letter, by id and folder; a file with none left out; and where two
    /// letters use the same id, the later letter's.
    func testThePicturesAreTheMapThePaneBuiltTheLaterLetterWinning() {
        let first = Message(
            id: "7/3", mailboxID: "INBOX", sender: "Sam <sam@example.com>", senderAddress: "sam@example.com",
            to: [], cc: [], subject: "One", date: Date(timeIntervalSince1970: 0), textBody: nil,
            htmlBody: "<img src=\"cid:a\"><img src=\"cid:shared\">",
            attachments: [Attachment(id: "2", filename: "a.png", mimeType: "image/png", size: 1, contentID: "a"),
                          Attachment(id: "3", filename: "s.gif", mimeType: "image/gif", size: 1,
                                     contentID: "shared"),
                          Attachment(id: "4", filename: "plan.pdf", mimeType: "application/pdf", size: 1)])
        let second = Message(
            id: "7/3", mailboxID: "[Gmail]/Sent Mail", sender: "Me <me@example.com>",
            senderAddress: "me@example.com", to: [], cc: [], subject: "Two", date: Date(timeIntervalSince1970: 0),
            textBody: nil, htmlBody: "<img src=\"cid:shared\">",
            attachments: [Attachment(id: "2", filename: "s.jpg", mimeType: "image/jpeg", size: 1,
                                     contentID: "shared")])
        for shown in [[first, second], [second, first], [first], [], letters] {
            let map = PanePage.pictures(of: shown)
            let previous = previousPictures(shown)
            XCTAssertEqual(Set(map.keys), Set(previous.keys))
            for (cid, part) in previous {
                XCTAssertEqual(map[cid], .init(messageID: part.letter.id, mailboxID: part.letter.mailboxID,
                                               section: part.section, mimeType: part.mimeType), cid)
            }
        }
        XCTAssertEqual(PanePage.pictures(of: [first, second])["shared"],
                       .init(messageID: "7/3", mailboxID: "[Gmail]/Sent Mail", section: "2",
                             mimeType: "image/jpeg"))
        XCTAssertEqual(PanePage.pictures(of: [second, first])["shared"],
                       .init(messageID: "7/3", mailboxID: "INBOX", section: "3", mimeType: "image/gif"))
        XCTAssertEqual(PanePage.pictures(of: [letters[12]]).count, 8)
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

    /// A letter shown only in part is never said to have no text: what was
    /// not fetched of it, or what the server would not give, can be all its
    /// words. Its page and its stack body say it is only the beginning, over
    /// whatever came; the same letter whole, with nothing in it, is still
    /// "This message has no text." (B-114).
    func testALetterShownOnlyInPartIsNeverSaidToHaveNoText() throws {
        let notice = "<p style=\"color: #8e8e93; margin: 0 0 1em 0; white-space: normal;\">"
            + MailText.shortenedNotice + "</p>"
        for (text, html) in [("", nil), ("\n\n", nil), (nil, ""), (nil, "<div> </div>"),
                             (nil, nil)] as [(String?, String?)] {
            var m = letter(text: text, html: html)
            XCTAssertNil(PanePage.letter(m, style: style), "\(String(reflecting: text)) \(String(reflecting: html))")
            XCTAssertEqual(PanePage.stackBody(m).html,
                           "<span class=\"bm-waiting\">\(MailText.emptyBodyNotice)</span>")
            m.isShortened = true
            let page = try XCTUnwrap(PanePage.letter(m, style: style),
                                     "\(String(reflecting: text)) \(String(reflecting: html))")
            XCTAssertTrue(page.contains("<div id=\"bm\">" + notice), page)
            XCTAssertFalse(page.contains(MailText.emptyBodyNotice), page)
            let stack = PanePage.stackBody(m)
            XCTAssertTrue(stack.html.hasPrefix(notice), stack.html)
            XCTAssertFalse(stack.html.contains(MailText.emptyBodyNotice), stack.html)
            XCTAssertEqual(stack.isHTML, html != nil)
        }
    }
}
