import XCTest
@testable import Blackmail

/// A letter's HTML drawn in the dark pane as Mail draws it in Dark Mode
/// (B-169): inverted only where Mail turns a letter to the dark, a letter
/// that declares no colour scheme and has no picture from the web and no
/// background picture on its body; light, on its own white, a letter with
/// such a picture, or one that declares a light scheme only; in its own
/// colours, its style for the dark with it, one that declares the dark.
/// Read in iOS 18.6's MobileMailUI (`_styleForSystemAppearance`,
/// `_declaredColorSchemes`) and MessageUI, not seen. Each letter of a
/// conversation decided on its own; a plain letter and the printed page as
/// they were. Until B-169 the pane inverted every HTML letter (D-010).
final class DarkLikeMailTests: XCTestCase {

    private let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)

    private func scheme(_ html: String) -> LetterScheme {
        LetterScheme.of(html: html)
    }

    private func letter(_ html: String?, text: String? = nil, id: String = "7/3",
                        pictures: [String] = []) -> Message {
        let attachments = pictures.enumerated().map { i, cid in
            Attachment(id: "\(i + 2)", filename: "image\(i).png", mimeType: "image/png",
                       size: 2_000, contentID: cid)
        }
        return Message(id: id, mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                       senderAddress: "sam@example.com", to: ["me@example.com"], cc: [],
                       subject: "The garden", date: Date(timeIntervalSince1970: 1_790_000_000),
                       textBody: text, htmlBody: html, attachments: attachments)
    }

    /// The style of a page: everything before its `</style>`.
    private func rules(of page: String) throws -> String {
        try XCTUnwrap(page.components(separatedBy: "</style>").first)
    }

    private func filters(_ style: String) -> [String] {
        style.components(separatedBy: "filter:").dropFirst()
            .map { String($0.prefix(while: { $0 != ";" })).trimmingCharacters(in: .whitespaces) }
    }

    /// A newsletter as they are made to be read in the dark: both schemes
    /// declared, by `<meta>` and on the root, white cards with dark words
    /// in the light, and its rules for the dark in its head; a picture from
    /// the web in it, which a declared scheme makes no matter.
    static let darkReady = """
        <!DOCTYPE html><html lang="en"><head>
        <meta name="color-scheme" content="light dark">
        <meta name="supported-color-schemes" content="light dark">
        <style type="text/css">
        :root { color-scheme: light dark; supported-color-schemes: light dark; }
        body { margin: 0 !important; padding: 0 !important; background: #f2f2f7; }
        .card, td { background: #ffffff; color: #222222; }
        @media (prefers-color-scheme: dark) {
          body, .card { background: #1c1c1e !important; color: #f2f2f7 !important; }
        }
        @font-face { font-family: Garden; src: url(https://fonts.example.com/g.woff2); }
        /* the links */ a { color: #0b57d0; }
        </style>
        <!--[if mso]><style>td { font-family: Arial; }</style><![endif]-->
        </head>
        <body style="margin:0;">
        <table class="card"><tr><td><img src="https://example.com/news/top.png" width="600" alt="">
        <p>The spring show is on the 12th.</p></td></tr></table>
        </body></html>
        """

    /// The same newsletter's head rules, as the pane draws them inside the
    /// letter's box, `#bm-own-7_3`, which stands for its root, and the
    /// `div` in it that stands for its body.
    static let darkReadyScoped = """
        .bm-own-root:where(#bm-own-7_3) { color-scheme: light dark; supported-color-schemes: light dark; }
        div:where(#bm-own-7_3 > .bm-own-body) { margin: 0 !important; padding: 0 !important; background: #f2f2f7; }
        :where(#bm-own-7_3) .card, :where(#bm-own-7_3) td { background: #ffffff; color: #222222; }
        @media (prefers-color-scheme: dark) {
        div:where(#bm-own-7_3 > .bm-own-body), :where(#bm-own-7_3) .card { background: #1c1c1e !important; color: #f2f2f7 !important; }
        }
        @font-face { font-family: Garden; src: url(https://fonts.example.com/g.woff2); }
        :where(#bm-own-7_3) a { color: #0b57d0; }

        """

    /// A letter with a picture from the web in it and no scheme declared.
    static let withAWebPicture = """
        <html><head><meta http-equiv="content-type" content="text/html; charset=utf-8"></head>
        <body><div dir="ltr">Look at the roses.<br><img src="https://example.com/roses.jpg" width="480"></div>
        <blockquote type="cite">On Monday, Sam wrote:<br>The garden is ready.</blockquote></body></html>
        """

    // MARK: - Mail's rule

    /// A letter that declares no scheme, with no picture from the web and
    /// no background picture on its body, is turned to the dark, as Mail's
    /// colour filter turns it: every shape of the pane's set, his own
    /// letter with its signature and logo by `cid:`, Mail's reply and
    /// Gmail's, pictures of its own and in its data, and a picture from
    /// the web only where Mail does not count one.
    func testALetterWithNoSchemeAndNoPictureFromTheWebIsInverted() {
        var html = PaneLetters.all.compactMap(\.htmlBody)
        html += [
            "<p>Hi</p>", PanePageTests.signedLetter, PanePageTests.appleMailReply, PanePageTests.gmailReply,
            "<img src=\"cid:photo1@example.com\">", "<img src=\"data:image/png;base64,iVBORw0KGgo=\">",
            "<img src=\"https://t.example.com/open?u=1\" width=\"1\" height=\"1\" border=\"0\">",
            "<img src=\"https://t.example.com/o.gif\" style=\"height:1px !important;width:1px !important;\">",
            "<img src=\"https://t.example.com/o.gif\" width=\"1\">",
            "<img src=\"https://t.example.com/o.gif\" width=\"0\" height=\"0\">",
            "<img src=\"https://t.example.com/o.gif\" style=\"width:0;height:0\" width=\"300\">",
            "<img class=\"lp-rich-link-media\" src=\"https://example.com/card.png\">",
            "<img src=\"roses.jpg\">", "<img src=\"//example.com/roses.jpg\">", "<img src=\"\">", "<img>",
            "<!-- <img src=\"https://example.com/roses.jpg\"> --><p>x</p>",
            "<!--[if mso]><img src=\"https://example.com/roses.jpg\"><![endif]--><p>x</p>",
            "<script><img src=\"https://example.com/roses.jpg\"></script>",
            "<title><img src=\"https://example.com/roses.jpg\"></title><textarea><img src=\"https://x/y\"></textarea>",
            "<style>p::after { content: '<img src=\"https://example.com/roses.jpg\">'; }</style><p>x</p>",
            "<p style=\"background-image:url(https://example.com/bg.png)\">Not the body</p>",
            "<table background=\"https://example.com/bg.png\"><tr><td>Not the body</td></tr></table>",
        ]
        for (i, h) in html.enumerated() {
            XCTAssertEqual(scheme(h), .inverted, "letter \(i): \(h.prefix(120))")
        }
    }

    /// A picture from the web, an `<img>` whose address begins `http` once
    /// made whole and more than 1 px wide or tall, draws the letter light,
    /// as Mail's `apple-mail-light-only`: in any case, quoted or not,
    /// written with a reference, against a `<base>` of the web, and
    /// measured as its style or its attributes have it, neither given
    /// counting it.
    func testAPictureFromTheWebDrawsTheLetterLight() {
        for h in [
            Self.withAWebPicture,
            "<img src=\"http://example.com/a.png\">", "<IMG SRC=HTTPS://EXAMPLE.COM/A.PNG>",
            "<img src='  https://example.com/a.png\n'>", "<img src=\"htt\nps://example.com/a.png\">",
            "<img src=\"&#104;ttps://example.com/a.png\">", "<image src=\"https://example.com/a.png\">",
            "<base href=\"https://example.com/news/\"><img src=\"roses.jpg\">",
            "<img src=\"https://example.com/rule.png\" width=\"600\" height=\"1\">",
            "<img src=\"https://example.com/a.png\" width=\"1\" height=\"40\">",
            "<img src=\"https://example.com/a.png\" width=\"100%\">",
            "<img src=\"https://example.com/a.png\" width=\"1\" style=\"width: 100%\">",
            "<img src=\"https://example.com/a.png\" style=\"display:none\">",
            "<img src=\"https://example.com/a.png\" width=\"2\">",
            "<img class=\"photo\" src=\"https://example.com/a.png\">",
        ] {
            XCTAssertEqual(scheme(h), .light, h)
        }
    }

    /// A background picture on the letter's body draws it light, as Mail
    /// asks WebKit for the body's: any picture, the letter's own too, or a
    /// gradient; from its `background`, its `style` or a rule for the body
    /// alone, the one that wins, a later `<body>` adding what the first
    /// lacks, as HTML has it. A colour alone, or none, after it takes the
    /// picture away; the body named by a class, or media that do not match
    /// the dark pane, is not read.
    func testABackgroundPictureOnTheBodyDrawsTheLetterLight() {
        for h in [
            "<body background=\"bg.jpg\"><p>x</p></body>",
            "<body background=\"cid:paper@example.com\"><p>x</p></body>",
            "<body style=\"background-image:url('https://example.com/bg.png')\"><p>x</p></body>",
            "<body style=\"background: #fff url(paper.png) repeat\"><p>x</p></body>",
            "<body style=\"background: linear-gradient(#fff, #eee)\"><p>x</p></body>",
            "<style>body { background: url(paper.png) }</style><p>x</p>",
            "<style>html body { background-image: url(paper.png) }</style><p>x</p>",
            "<style>:root > body { background-image: url(paper.png) }</style><p>x</p>",
            "<style>@media (prefers-color-scheme: dark) { body { background: url(n.png) } }</style><p>x</p>",
            "<style>body { background: url(paper.png) !important }</style><body style=\"background:#fff\">x",
            "<body background=\"bg.jpg\" style=\"background-color: #fff\"><p>x</p></body>",
            "<html><body><p>x</p><html><body background=\"late.jpg\"><p>y</p>",
            "<body style=\"background: url(a.png)\"><body style=\"background: #fff\"><p>x</p>",
        ] {
            XCTAssertEqual(scheme(h), .light, h)
        }
        for h in [
            "<body background=\"\"><p>x</p></body>", "<body background=\"  \"><p>x</p></body>",
            "<body bgcolor=\"#eeeeee\"><p>x</p></body>",
            "<body style=\"background: #eee\"><p>x</p></body>",
            "<body background=\"bg.jpg\" style=\"background: none\"><p>x</p></body>",
            "<style>body { background: #fff }</style><body background=\"bg.jpg\"><p>x</p></body>",
            "<style>body.news { background: url(paper.png) }</style><body class=\"news\"><p>x</p></body>",
            "<style>@media print { body { background: url(paper.png) } }</style><p>x</p>",
            "<style>@media (max-width: 600px) { body { background: url(paper.png) } }</style><p>x</p>",
            "<style>/* body { background: url(paper.png) } */</style><p>x</p>",
        ] {
            XCTAssertEqual(scheme(h), .inverted, h)
        }
    }

    /// A letter that declares its schemes is drawn as it declares them,
    /// before any picture is looked at: light only for `light` or `only`
    /// without `dark`, in its own colours otherwise. The root's
    /// `color-scheme` first, `supported-color-schemes` its old name, the
    /// one that wins at the root; then the last `<meta
    /// name="color-scheme">`, its name as written. A `<meta
    /// name="supported-color-schemes">` alone declares nothing, as Mail's
    /// script never reaches it.
    func testADeclaredSchemeDecidesBeforeAnyPicture() {
        let picture = "<img src=\"https://example.com/a.png\">"
        let cases: [(String, LetterScheme)] = [
            (Self.darkReady, .own),
            ("<meta name=\"color-scheme\" content=\"light dark\"><p>x</p>", .own),
            ("<meta name=\"color-scheme\" content=\"dark\"><p>x</p>", .own),
            ("<meta name=\"color-scheme\" content=\"DARK light\">" + picture, .own),
            ("<meta name=\"color-scheme\" content=\"light\"><p>x</p>", .light),
            ("<meta name=\"color-scheme\" content=\"only light\"><p>x</p>", .light),
            ("<meta name=\"color-scheme\" content=\"light dark\"><body background=\"b.png\">", .own),
            ("<meta name=\"color-scheme\" content=\"light dark\"><meta name=\"color-scheme\" content=\"light\">",
             .light),
            ("<meta name=\"color-scheme\" content=\"dark\"><meta name=\"color-scheme\" content=\"\"><p>x</p>",
             .inverted),
            ("<meta name=\"color-scheme\" content=\"dark\"><meta name=\"color-scheme\"><p>x</p>", .inverted),
            ("<meta name=\"color-scheme\" content=\" \"><p>x</p>", .own),
            ("<meta name=\"supported-color-schemes\" content=\"light dark\"><p>x</p>", .inverted),
            ("<meta name=\"supported-color-schemes\" content=\"light dark\">" + picture, .light),
            ("<meta name=\"Color-Scheme\" content=\"dark\"><p>x</p>", .inverted),
            ("<!-- <meta name=\"color-scheme\" content=\"dark\"> --><p>x</p>", .inverted),
            ("<p>x</p><meta name=\"color-scheme\" content=\"dark\">", .own),
            ("<style>:root { color-scheme: light dark; }</style><p>x</p>", .own),
            ("<style>html { color-scheme: light }</style>" + picture, .light),
            ("<style>:root { color-scheme: light only; }</style><p>x</p>", .light),
            ("<style>HTML:ROOT { Color-Scheme: Dark }</style><p>x</p>", .own),
            ("<style>html { supported-color-schemes: light dark }</style><p>x</p>", .own),
            ("<html style=\"color-scheme: dark\"><p>x</p>", .own),
            ("<style>:root { color-scheme: normal }</style><meta name=\"color-scheme\" content=\"dark\">", .own),
            ("<style>:root { color-scheme: normal }</style><p>x</p>", .inverted),
            ("<style>:root { color-scheme: inherit }</style>" + picture, .light),
            ("<style>:root { color-scheme: light }</style><meta name=\"color-scheme\" content=\"dark\">", .light),
            ("<style>.x { color-scheme: dark } body { color-scheme: dark }</style><p>x</p>", .inverted),
            ("<style>html, .x { color-scheme: dark }</style><p>x</p>", .own),
            ("<style>:root { color-scheme: dark } html { color-scheme: light }</style><p>x</p>", .own),
            ("<style>html { color-scheme: light !important } :root { color-scheme: dark }</style>", .light),
            ("<html style=\"color-scheme: light\"><style>:root { color-scheme: dark }</style>", .light),
            ("<html style=\"color-scheme: light\"><style>:root { color-scheme: dark !important }</style>", .own),
            ("<style>:root { color-scheme: dark } :root { color-scheme: only }</style>", .own),
            ("<style>:root { color-scheme: light only dark }</style><p>x</p>", .inverted),
            ("<style>:root { color-scheme: var(--scheme) }</style><p>x</p>", .inverted),
            ("<style>@media (prefers-color-scheme: dark) { :root { color-scheme: dark } }</style>", .own),
            ("<style>@media only screen and (prefers-color-scheme: dark) { :root { color-scheme: dark } }</style>",
             .own),
            ("<style>@media print { :root { color-scheme: dark } }</style><p>x</p>", .inverted),
            ("<style>@media (prefers-color-scheme: light) { :root { color-scheme: dark } }</style>", .inverted),
            ("<style>@supports (color-scheme: dark) { :root { color-scheme: dark } }</style>", .own),
            ("<style>/* :root { color-scheme: dark } */</style><p>x</p>", .inverted),
            ("<!--[if mso]><style>:root { color-scheme: dark }</style><![endif]--><p>x</p>", .inverted),
        ]
        for (h, expected) in cases {
            XCTAssertEqual(scheme(h), expected, h)
        }
    }

    /// The pane's set of ordinary letters as Mail would draw them: those
    /// with a picture from the web drawn light, every other inverted, none
    /// declaring a scheme.
    func testOrdinaryMailIsDrawnAsMailWould() {
        let documents = OrdinaryMail.documents()
        let schemes = OrdinaryMail.schemes()
        XCTAssertEqual(schemes.count, documents.count)
        for (h, s) in zip(documents, schemes) {
            let web = h.contains("<img src=\"https://example.com/p")
            XCTAssertEqual(s, web ? .light : .inverted, String(h.prefix(200)))
        }
        XCTAssertGreaterThan(schemes.filter { $0 == .light }.count, 5)
        XCTAssertGreaterThan(schemes.filter { $0 == .inverted }.count, 5)
    }

    // MARK: - A letter on its own

    /// A letter Mail turns to the dark has the page it always had: every
    /// HTML letter of the pane's set, his own and the replies, the same
    /// byte for byte as the page drawn inverted, and in a stack the class
    /// it always had.
    func testAnInvertedLettersPageIsAsItWas() throws {
        let letters = PaneLetters.all + [letter(PanePageTests.signedLetter, pictures: ["sig-logo"]),
                                         letter(PanePageTests.appleMailReply), letter(PanePageTests.gmailReply)]
        var drawn = 0
        for (i, m) in letters.enumerated() where m.htmlBody != nil {
            XCTAssertEqual(PanePage.letter(m, style: style), PanePage.letter(m, style: style, scheme: .inverted),
                           "letter \(i)")
            let body = PanePage.stackBody(m)
            XCTAssertEqual(body.scheme, .inverted, "letter \(i)")
            XCTAssertEqual(body.kind, body.isHTML ? "bm-html" : "bm-text", "letter \(i)")
            drawn += 1
        }
        XCTAssertGreaterThan(drawn, 10)
        let page = try XCTUnwrap(PanePage.letter(letter("<p>Hi</p>"), style: style))
        XCTAssertEqual(filters(try rules(of: page)), [SignatureSheet.invert, SignatureSheet.invert])
    }

    /// A letter with a picture from the web is drawn light, as Mail draws
    /// it, as its sender made it: black words on its own white, its
    /// pictures as they are, no filter anywhere, Mail's bars in its light
    /// colours, its links Mail's light blue; the pane's black around it.
    /// Its markup is what an inverted letter's would be.
    func testALetterWithAPictureFromTheWebIsDrawnOnItsOwnWhite() throws {
        let m = letter(Self.withAWebPicture)
        let page = try XCTUnwrap(PanePage.letter(m, style: style))
        let sheet = try rules(of: page)
        XCTAssertEqual(filters(sheet), [])
        XCTAssertTrue(sheet.contains("  html, body { margin: 0; padding: 0; background: #000; }"), sheet)
        XCTAssertTrue(sheet.contains("        color: #000; word-wrap: break-word; }"), sheet)
        XCTAssertTrue(sheet.hasSuffix("  a { color: #007AFF; }\n  #bm { background: #fff; color-scheme: light only; }\n"
                                      + QuoteBars.css(in: "#bm") + "\n"), sheet)
        let body = PanePage.content(text: nil, html: Self.withAWebPicture, known: [], flowed: false)
        XCTAssertTrue(page.hasSuffix("<div id=\"bm\">" + body + "</div></body></html>"), page)
        XCTAssertTrue(body.contains("<img src=\"https://example.com/roses.jpg\" width=\"480\">"), body)
        XCTAssertEqual(PanePage.letter(m, style: style, scheme: .inverted)?
                        .hasSuffix("<div id=\"bm\">" + body + "</div></body></html>"), true)
        // A light scheme declared, the same.
        let declared = letter("<meta name=\"color-scheme\" content=\"light\"><p>Hi</p>")
        XCTAssertTrue(try rules(of: XCTUnwrap(PanePage.letter(declared, style: style)))
                        .contains("#bm { background: #fff; color-scheme: light only; }"))
    }

    /// A letter that declares the dark is drawn in its own colours: no
    /// filter, words white on the pane's black, its scheme the dark one,
    /// Mail's bars in its dark colours and links in its dark blue; and its
    /// head's style, which the wrapper's removal takes off with the head,
    /// in front of its markup, each rule made to apply in the letter's box
    /// alone, its rules for the dark among them, `@import` left out, a
    /// style in an Outlook comment not read.
    func testALetterThatDeclaresTheDarkHasItsOwnColours() throws {
        let m = letter(Self.darkReady)
        let page = try XCTUnwrap(PanePage.letter(m, style: style))
        let sheet = try rules(of: page)
        XCTAssertEqual(filters(sheet), [])
        XCTAssertTrue(sheet.contains("        color: #fff; word-wrap: break-word; }"), sheet)
        XCTAssertTrue(sheet.hasSuffix("  a { color: #0A84FF; }\n  #bm { color-scheme: light dark; }\n"
                                      + QuoteBars.css(in: "#bm", palette: QuoteBars.dark) + "\n"), sheet)
        let markup = PanePage.content(text: nil, html: Self.darkReady, known: [], flowed: false)
        let box = "<div id=\"bm-own-7_3\" class=\"bm-own-root\"><style>\n" + Self.darkReadyScoped + "</style>"
            + "<div class=\"bm-own-body\" style=\"margin:0;\">" + markup + "</div></div>"
        XCTAssertTrue(page.hasSuffix("<div id=\"bm\">" + box + "</div></body></html>"), page)
        XCTAssertFalse(page.contains("@import"))
        XCTAssertFalse(page.contains("font-family: Arial"))
        XCTAssertEqual(PanePage.stackBody(m), .init(html: box, isHTML: true, scheme: .own))
        // With no style in its head and nothing on its body, the two `div`s
        // alone.
        let bare = letter("<meta name=\"color-scheme\" content=\"light dark\"><p>Hi</p>", id: "12/40")
        XCTAssertEqual(PanePage.stackBody(bare).html,
                       "<div id=\"bm-own-12_40\" class=\"bm-own-root\"><div class=\"bm-own-body\">"
                        + "<meta name=\"color-scheme\" content=\"light dark\"><p>Hi</p></div></div>")
    }

    /// A letter in its own colours keeps what its body had, which the
    /// wrapper's removal takes off with the body's tag, on the `div` that
    /// stands for its body: its `style`, so a white page that is its
    /// body's is white under its dark words, not the pane's black; its
    /// `class`, so its rules for the dark that name the body by it have
    /// it, inside the box; its `bgcolor` and `text` as the `div`'s
    /// background and colour, by a rule in front of the head's that weighs
    /// nothing, as HTML weighs them below every rule. Each escaped where it
    /// goes; a later body adding only what the first lacked; a colour that
    /// is none, none.
    func testALetterInItsOwnColoursKeepsWhatItsBodyHad() throws {
        let white = letter("<meta name=\"color-scheme\" content=\"light dark\">"
                           + "<body style=\"background-color:#ffffff\"><p style=\"color:#333333\">Hello</p></body>")
        XCTAssertEqual(scheme(white.htmlBody ?? ""), .own)
        let box = "<div id=\"bm-own-7_3\" class=\"bm-own-root\">"
            + "<div class=\"bm-own-body\" style=\"background-color:#ffffff\">"
            + "<meta name=\"color-scheme\" content=\"light dark\"><p style=\"color:#333333\">Hello</p></div></div>"
        let page = try XCTUnwrap(PanePage.letter(white, style: style))
        XCTAssertTrue(page.hasSuffix("<div id=\"bm\">" + box + "</div></body></html>"), page)
        XCTAssertEqual(PanePage.stackBody(white).html, box)

        let news = """
            <html><head><meta name="color-scheme" content="light dark"><style>
            body { background: #ffffff; }
            @media (prefers-color-scheme: dark) { .body { background: #1c1c1e !important; } .body p { color: #ffffff !important; } }
            </style></head><body class="body \tnews" bgcolor="ffffff" text="#333"><p>Hello</p></body></html>
            """
        XCTAssertEqual(scheme(news), .own)
        XCTAssertEqual(PanePage.stackBody(letter(news, id: "9/5")).html, """
            <div id="bm-own-9_5" class="bm-own-root"><style>
            :where(#bm-own-9_5 > .bm-own-body) { background-color: #ffffff; color: #333333; }

            div:where(#bm-own-9_5 > .bm-own-body) { background: #ffffff; }
            @media (prefers-color-scheme: dark) {
            :where(#bm-own-9_5) .body { background: #1c1c1e !important; }
            :where(#bm-own-9_5) .body p { color: #ffffff !important; }
            }
            </style><div class="bm-own-body body news"><p>Hello</p></div></div>
            """)

        let marked = letter("""
            <meta name="color-scheme" content="dark"><body class='a"b' style='font-family:"Garden", serif; \
            background:url(x.png?a=1&amp;b=2)' bgcolor="transparent"><p>x</p>
            <body class="later" text="" style="color:red" bgcolor="#fff"><p>y</p></body>
            """, id: "4/8")
        XCTAssertEqual(PanePage.stackBody(marked).html, """
            <div id="bm-own-4_8" class="bm-own-root"><div class="bm-own-body a&quot;b" \
            style="font-family:&quot;Garden&quot;, serif; background:url(x.png?a=1&amp;b=2)">\
            <meta name="color-scheme" content="dark"><p>x</p>
            <p>y</p></div></div>
            """)
    }

    /// A body's `bgcolor` and `text` read as WebKit reads a legacy colour
    /// value (`HTMLElement::parseLegacyColorValue`): none for an empty one
    /// or `transparent`, black for white space alone, a name for CSS,
    /// `#rgb` doubled, and any other by its hex digits, others made `0`,
    /// in three parts cut to their last eight, their common leading zeros
    /// dropped down to two, then cut to two; the first 128 after a `#`.
    func testABodysColoursAreReadAsWebKitReadsThem() {
        let cases: [(String, String?)] = [
            ("#ffffff", "#ffffff"), ("ffffff", "#ffffff"), ("#FFF", "#ffffff"), ("  #EEE\n", "#eeeeee"),
            ("fff", "#0f0f0f"), ("f", "#0f0000"), ("add", "#0a0d0d"), ("White", "white"),
            ("transparent", nil), ("TRANSPARENT", nil), ("", nil), (" \t ", "#000000"), ("#", "#000000"),
            ("#ffffff;", "#ffff00"), ("rgb(255,255,255)", "#005025"), ("#1a2b3c4d5e6f7", "#1ac46f"),
            ("#0000ff0000ff0000ff", "#ffffff"), ("#" + String(repeating: "0", count: 127) + "f", "#0000f0"),
            (String(repeating: "0", count: 128) + "f", "#000000"), ("1\u{1F600}", "#010000"),
        ]
        for (value, colour) in cases {
            XCTAssertEqual(LetterCSS.legacyColour(value), colour, value)
        }
    }

    // MARK: - A conversation

    /// Each letter of a conversation is drawn as Mail draws it, decided on
    /// its own: its body's class in the stack, at the first draw and by
    /// `bmFill`; the stack's style with the rules for each, the invert on
    /// the inverted letters' class alone; two letters in their own colours
    /// each in a box of its own, its head's rules for it alone.
    func testEachLetterOfAConversationIsDrawnOnItsOwn() throws {
        let letters = [
            letter("<p>Lunch on Sunday?</p>", id: "9/1"),
            letter(Self.withAWebPicture, id: "9/2"),
            letter(Self.darkReady, id: "9/3"),
            letter(nil, text: "Yes, Sunday.\n> Lunch on Sunday?", id: "9/4"),
            letter(Self.darkReady.replacingOccurrences(of: "#0b57d0", with: "#1a73e8"), id: "9/5"),
        ]
        let bodies = letters.map { PanePage.stackBody($0) }
        XCTAssertEqual(bodies.map(\.kind), ["bm-html", "bm-light", "bm-own", "bm-text", "bm-own"])
        let html = ConversationDocument.html(
            entries: zip(letters, bodies).map { m, body in
                .init(id: m.id, sender: m.sender, date: m.date, body: body, isExpanded: true, preview: "")
            },
            inset: style.inset, bodyPointSize: style.bodyPointSize, lineHeight: style.lineHeight)
        for (m, body) in zip(letters, bodies) {
            XCTAssertTrue(html.contains("<div class=\"bm-body \(body.kind)\">" + body.html + "</div>"), m.id)
            let fill = ConversationDocument.Fill(sectionID: ConversationDocument.sectionID(for: m.id), body: body)
            XCTAssertEqual(fill.arguments["scheme"] as? String, body.isHTML ? body.kind : "bm-html")
            XCTAssertEqual(fill.arguments["isHTML"] as? Bool, body.isHTML)
        }
        XCTAssertTrue(bodies[2].html.hasPrefix(
            "<div id=\"bm-own-9_3\" class=\"bm-own-root\"><style>\n.bm-own-root:where(#bm-own-9_3) {"))
        XCTAssertTrue(bodies[4].html.hasPrefix(
            "<div id=\"bm-own-9_5\" class=\"bm-own-root\"><style>\n.bm-own-root:where(#bm-own-9_5) {"))
        XCTAssertTrue(bodies[4].html.contains(":where(#bm-own-9_5) a { color: #1a73e8; }"))
        XCTAssertFalse(bodies[4].html.contains("bm-own-9_3"))

        let sheet = try rules(of: html)
        XCTAssertEqual(filters(sheet), [SignatureSheet.invert, SignatureSheet.invert])
        XCTAssertTrue(sheet.contains(".bm-html { filter: \(SignatureSheet.invert); background: #fff;"), sheet)
        for rule in [
            ".bm-light { background: #fff; color: #000; color-scheme: light only; }",
            ":where(.bm-light) a { color: #007AFF; }",
            ".bm-own { color: #fff; color-scheme: light dark; }",
            ":where(.bm-own) a { color: #0A84FF; }",
            "\n" + QuoteBars.css(in: ".bm-light") + "\n",
            "\n" + QuoteBars.css(in: ".bm-own", palette: QuoteBars.dark) + "\n",
        ] {
            XCTAssertTrue(sheet.contains(rule), rule)
        }
        XCTAssertFalse(sheet.contains(".bm-light {" + " filter"))
    }

    /// The stack's script gives a body the class its scheme says as it
    /// puts it in (`bmFill`): run in node on a page of stand-ins, light,
    /// own and inverted markup, text whatever its scheme, and any other
    /// word for markup, or none, as the stack's old three arguments had it,
    /// inverted.
    func testTheStacksScriptGivesABodyItsScheme() throws {
        let program = """
            const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
            const bodies = {};
            globalThis.window = { addEventListener() {}, pageYOffset: 0, innerHeight: 700 };
            globalThis.performance = { now() { return 0; } };
            globalThis.document = {
              body: { querySelectorAll() { return []; } },
              getElementById(id) {
                if (id === 'bm') return null;
                if (!bodies[id]) bodies[id] = { className: 'bm-body bm-text', innerHTML: '',
                                                querySelectorAll() { return []; } };
                const body = bodies[id];
                return { querySelector() { return body; } };
              },
              querySelectorAll() { return []; },
              querySelector() { return null; },
            };
            (0, eval)(input.script);
            const out = {};
            for (const f of input.fills) {
              if (f.scheme == null) bmFill(f.id, f.html, f.isHTML);
              else bmFill(f.id, f.html, f.isHTML, f.scheme);
              out[f.id] = [bodies[f.id].className, bodies[f.id].innerHTML];
            }
            process.stdout.write(JSON.stringify(out));
            """
        struct Fill: Encodable {
            let id: String, html: String, isHTML: Bool, scheme: String?
        }
        struct Input: Encodable {
            let script: String
            let fills: [Fill]
        }
        let fills = [
            Fill(id: "m1", html: "<p>a</p>", isHTML: true, scheme: "bm-light"),
            Fill(id: "m2", html: "<p>b</p>", isHTML: true, scheme: "bm-own"),
            Fill(id: "m3", html: "<p>c</p>", isHTML: true, scheme: "bm-html"),
            Fill(id: "m4", html: "d", isHTML: false, scheme: "bm-light"),
            Fill(id: "m5", html: "<p>e</p>", isHTML: true, scheme: "bm-letter bm-open"),
            Fill(id: "m6", html: "<p>f</p>", isHTML: true, scheme: nil),
        ]
        let input = try JSONEncoder().encode(Input(script: ConversationDocument.script, fills: fills))
        let out = try runNode(program, input: input)
        let classes = try XCTUnwrap(JSONSerialization.jsonObject(with: out) as? [String: [String]])
        XCTAssertEqual(classes["m1"], ["bm-body bm-light", "<p>a</p>"])
        XCTAssertEqual(classes["m2"], ["bm-body bm-own", "<p>b</p>"])
        XCTAssertEqual(classes["m3"], ["bm-body bm-html", "<p>c</p>"])
        XCTAssertEqual(classes["m4"], ["bm-body bm-text", "d"])
        XCTAssertEqual(classes["m5"], ["bm-body bm-html", "<p>e</p>"])
        XCTAssertEqual(classes["m6"], ["bm-body bm-html", "<p>f</p>"])
    }

    // MARK: - What is as it was

    /// The printed page is as it was for a letter drawn light or in its
    /// own colours: white paper, no filter, the letter's markup as the
    /// pane's body before B-169, no box and no style brought from its head.
    /// A plain letter's pane page has no scheme, its words white as ever.
    func testPrintAndAPlainLetterAreAsTheyWere() throws {
        let size: (Int64) -> String = { "\($0) bytes" }
        let printStyle = PrintPage.Style(senderPointSize: 17, metaPointSize: 15, subjectPointSize: 17,
                                         bodyPointSize: 17, lineHeight: 1.41)
        for html in [Self.withAWebPicture, Self.darkReady] {
            let page = PrintPage.letter(letter(html), style: printStyle, size: size,
                                        locale: Locale(identifier: "en_US_POSIX"),
                                        timeZone: TimeZone(identifier: "UTC")!)
            XCTAssertFalse(page.contains("filter"), page)
            XCTAssertFalse(page.contains("bm-own"), page)
            XCTAssertFalse(page.contains("color-scheme: light dark"), page)
            XCTAssertTrue(page.contains("<meta name=\"color-scheme\" content=\"light only\">"), page)
            let body = PrintPage.body(letter(html)).html
            XCTAssertTrue(page.contains(body), page)
            XCTAssertTrue(body.contains("The spring show") || body.contains("Look at the roses."), body)
            XCTAssertFalse(body.contains("prefers-color-scheme"), body)
        }
        let plain = try XCTUnwrap(PanePage.letter(letter(nil, text: "Yes.\n> Lunch?"), style: style))
        let sheet = try rules(of: plain)
        XCTAssertEqual(filters(sheet), [])
        XCTAssertFalse(sheet.contains("color-scheme"))
        XCTAssertTrue(sheet.hasSuffix("  a { color: #0A84FF; }\n  " + PanePageTests.plainBars + "\n"), sheet)
    }

    // MARK: - The head's style, scoped

    /// Each rule of a letter's head applies inside its box alone: a rule
    /// for its root, its body, or a run of them, the box's or the body's
    /// `div`'s, each named by a compound that weighs what it stood for
    /// (`div` a type's, `.bm-own-root` a class's, the box by `:where`, which
    /// weighs nothing), so `body td` weighs two types as in Mail, not an
    /// id; the body's compound with more in it the body's `div` with it; a
    /// child of the body the `div`'s child; any other inside the box, by
    /// `:where`. At-rules that name no element kept as they are, `@media`
    /// and its kin gone through, `@starting-style` too, any other with a
    /// block, `@scope` among them, left out, `@import` and `@charset` left
    /// out, a rule no browser would read left out, comments gone, and the
    /// sheet unable to end its `<style>`.
    func testAHeadsRulesApplyInsideTheLetterAlone() {
        let css = """
            @charset "utf-8";
            @import url("https://example.com/a.css") screen;
            html, BODY, :root, html body, html > body { color: #222; }
            body > table, html body .x, .y body { margin: 0; }
            body td, body.x p, BODY:hover, html:root, :root:root .y { color: #000; }
            * { box-sizing: border-box; } p, h1:hover::after { color: red; }
            @media screen and (max-width: 600px) { .wrap { width: 100% !important; } }
            @supports (display: grid) { @media (prefers-color-scheme: dark) { td { color: #eee; } } }
            @keyframes spin { from { transform: rotate(0); } to { transform: rotate(1turn); } }
            @-webkit-keyframes fade { from { opacity: 0; } }
            @page { margin: 1cm; }
            @scope (body) { p { color: red; } }
            @starting-style { p { opacity: 0; } }
            @-ms-viewport { width: device-width; }
            a[href*="{"] { content: "}"; } /* a comment with } in it */
            } .broken { color: blue; }
            .z { background: url(a</style>b.png); }
            .unclosed { color: green;
            """
        let body = "div:where(#box > .bm-own-body)"
        XCTAssertEqual(LetterCSS.scoped(css, in: "#box"), """
            div:where(#box), \(body), .bm-own-root:where(#box), div:where(#box) \(body), div:where(#box) > \(body) { color: #222; }
            \(body) > table, div:where(#box) \(body) .x, :where(#box) .y body { margin: 0; }
            \(body) td, \(body).x p, \(body):hover, div.bm-own-root:where(#box), .bm-own-root.bm-own-root:where(#box) .y { color: #000; }
            :where(#box) * { box-sizing: border-box; }
            :where(#box) p, :where(#box) h1:hover::after { color: red; }
            @media screen and (max-width: 600px) {
            :where(#box) .wrap { width: 100% !important; }
            }
            @supports (display: grid) {
            @media (prefers-color-scheme: dark) {
            :where(#box) td { color: #eee; }
            }
            }
            @keyframes spin { from { transform: rotate(0); } to { transform: rotate(1turn); } }
            @-webkit-keyframes fade { from { opacity: 0; } }
            @page { margin: 1cm; }
            @starting-style {
            :where(#box) p { opacity: 0; }
            }
            :where(#box) a[href*="{"] { content: "}"; }
            :where(#box) .z { background: url(a<\\/style>b.png); }
            :where(#box) .unclosed { color: green;}

            """)
    }

    /// The style sheets brought back are the head's, which the wrapper's
    /// removal takes off, in their order: every head it takes off, a
    /// forwarded document's too; not one in a comment, and not one in the
    /// body, which stays in the markup as it was.
    func testTheStylesBroughtBackAreTheHeadsTheWrapperTakesOff() {
        let html = """
            <html><head><style>.a { color: red; }</style><!-- <style>.no { }</style> -->
            <STYLE type="text/css">.b { color: blue; }</STYLE></head>
            <body><style>.c { color: green; }</style><p>x</p>
            <html><head><style>.d { color: gray; }</style></head><body><p>y</p></body></html></body></html>
            """
        XCTAssertEqual(LetterScheme.headStyles(of: html),
                       [".a { color: red; }", ".b { color: blue; }", ".d { color: gray; }"])
        XCTAssertTrue(DocumentWrapper.stripped(from: html).contains("<style>.c { color: green; }</style>"))
        XCTAssertEqual(LetterScheme.headStyles(of: "<p>No head</p>"), [])
    }

    // MARK: - Letters made to be slow

    /// Half a megabyte made to make the reading slow, each read once, in
    /// well under the bound where reading any of it twice for each piece
    /// would take minutes: a tag, a comment, a style and a quote never
    /// closed, braces never closed, at-rules by the ten thousand never
    /// closed, rules and attributes by the ten thousand, pictures by the
    /// forty thousand, and a head of ten thousand styles brought back.
    ///
    /// Each read is bounded at 3 s. The heaviest, a sheet of 83,333 rules
    /// scoped, took 0.53 s in a debug build, then the 20,833 rules for the
    /// root read, 0.41 s, the head of 17,857 styles brought back, 0.38 s,
    /// and the 45,454 pictures read, 0.34 s: the bound is more than five
    /// times the slowest. The pictures are many and small so that a list
    /// of them copied for each picture, which reads it again for each, is
    /// far over the bound: 42 s, where 9,615 larger ones took 2.2 s.
    func testALetterMadeToBeSlowIsReadOnce() {
        let size = 500_000
        let bound: TimeInterval = 3
        let letters = [
            "<img src=\"" + String(repeating: "a", count: size),
            "<!--" + String(repeating: "-", count: size),
            "<style>" + String(repeating: "{", count: size),
            "<style>" + String(repeating: "@media (", count: size / 8),
            "<style>" + String(repeating: ":root{color-scheme:dark}", count: size / 24),
            String(repeating: "<a ", count: size / 3),
            String(repeating: "<img src=a>", count: size / 11),
            "<meta name=\"color-scheme\" content=\"dark\"><head>"
                + String(repeating: "<style>.a{color:red}</style>", count: size / 28) + "</head><p>x</p>",
            "<meta name=\"color-scheme\" content=\"dark\"><head><style>"
                + String(repeating: "/*", count: size / 2) + "</style></head>",
        ]
        for (i, h) in letters.enumerated() {
            let m = letter(h)
            var started = Date()
            _ = LetterScheme.of(html: h)
            let read = Date().timeIntervalSince(started)
            started = Date()
            _ = PanePage.inOwnColours("", of: m)
            let brought = Date().timeIntervalSince(started)
            XCTAssertLessThan(read, bound, "letter \(i) read: \(read) s")
            XCTAssertLessThan(brought, bound, "letter \(i) its head's style: \(brought) s")
        }
        let started = Date()
        _ = LetterCSS.scoped(String(repeating: "a{b:c}", count: size / 6), in: "#box")
        let scoped = Date().timeIntervalSince(started)
        XCTAssertLessThan(scoped, bound, "scoped: \(scoped) s")
    }

    /// Held back, a letter in its own colours is read for its style once,
    /// as one not held back is: Mail's line and its box are given the same
    /// frame (`PanePage.ownFrame`), on its page and in a stack, and
    /// `PanePage.held` reads nothing of its own. The reading is what
    /// `testALetterMadeToBeSlowIsReadOnce` bounds; done twice, Block All
    /// Remote Content doubled it (int19).
    func testAHeldBackLetterInItsOwnColoursIsReadOnce() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/Mail/PanePage.swift")
        let code = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
        let held = try XCTUnwrap(code.range(of: "static func held("))
        let after = try XCTUnwrap(code.range(of: "static func shortened(", range: held.upperBound..<code.endIndex))
        XCTAssertFalse(code[held.lowerBound..<after.lowerBound].contains("ownFrame(of:"),
                       "the line reads the frame it is given")
        for line in [
            "let frame = drawn == .own ? ownFrame(of: m) : nil "
                + "let held = heldBack ? Self.held(m, as: m.id, ownFrame: frame) : \"\"",
            "let content = frame.map { inOwnColours(html, of: m, heldBack: !held.isEmpty, frame: $0) } ?? html",
            "let frame = drawn == .own && !empty ? ownFrame(of: m) : nil "
                + "let held = empty ? \"\" : heldBack.map { Self.held(m, as: $0, ownFrame: frame) } ?? \"\"",
            "if let frame { content = inOwnColours(content, of: m, heldBack: !held.isEmpty, frame: frame) }",
            "let frame = frame ?? ownFrame(of: m)",
        ] {
            XCTAssertTrue(code.contains(line), line)
        }
        XCTAssertEqual(code.components(separatedBy: "ownFrame(of: m)").count - 1, 3)
    }

    // MARK: - With Block All Remote Content (B-168)

    /// Held back, a letter is judged by its markup as it came: one with a
    /// picture from the web is light, its picture held back. One in its own
    /// colours has the web's `url()`s in its head's style and on its body
    /// held back too, as its markup's are, and Mail's line over it though
    /// only its style asks the web, in Mail's dark colours, on its page and
    /// in a stack; not held back, its style as it came. Integration, int19.
    func testAHeldBackLetterKeepsItsSchemeAndItsStyleLoadsNothing() throws {
        let web = letter(Self.withAWebPicture)
        let light = try XCTUnwrap(PanePage.letter(web, style: style, heldBack: true))
        XCTAssertTrue(light.contains("#bm { background: #fff; color-scheme: light only; }"), light)
        XCTAssertTrue(light.contains("src=\"bmoffhttps://example.com/roses.jpg\""))
        XCTAssertTrue(light.contains(RemoteContent.unloaded))
        XCTAssertEqual(PanePage.stackBody(web, heldBack: "7/3").kind, "bm-light")

        let own = letter("""
            <html><head><meta name="color-scheme" content="light dark">
            <style>body { background: url(https://example.com/paper.png); }
            @media (prefers-color-scheme: dark) { p { color: #eeeeee; } }</style></head>
            <body style="background-image: url('https://example.com/b.png')"><p>Hello</p></body></html>
            """)
        XCTAssertEqual(scheme(own.htmlBody!), .own)
        let held = try XCTUnwrap(PanePage.letter(own, style: style, heldBack: true))
        let body = PanePage.stackBody(own, heldBack: "7/3")
        XCTAssertEqual(body.kind, "bm-own")
        for page in [held, body.html] {
            XCTAssertTrue(page.contains("bmoffhttps://example.com/paper.png"), page)
            XCTAssertTrue(page.contains("bmoffhttps://example.com/b.png"), page)
            XCTAssertFalse(page.contains("url(https:"), page)
            XCTAssertFalse(page.contains("url('https:"), page)
            XCTAssertTrue(page.contains(RemoteContent.line(for: "7/3")), page)
        }
        XCTAssertTrue(held.contains(RemoteContent.darkRule(in: "#bm")))
        let shown = try XCTUnwrap(PanePage.letter(own, style: style))
        XCTAssertTrue(shown.contains("url(https://example.com/paper.png)"), shown)
        XCTAssertFalse(shown.contains(RemoteContent.unloaded))
        XCTAssertEqual(PanePage.letter(own, style: style, heldBack: false), shown)
    }

    // MARK: - node

    private struct NoNode: Error {}

    /// Runs `program` in node with `input` on its standard input, and
    /// returns what it wrote; skips where there is no node.
    private func runNode(_ program: String, input: Data) throws -> Data {
        let node = Process()
        node.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        node.arguments = ["node", "-e", program]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        node.standardInput = stdin
        node.standardOutput = stdout
        node.standardError = stderr
        do { try node.run() } catch { throw XCTSkip("no node on this host") }
        stdin.fileHandleForWriting.write(input)
        try stdin.fileHandleForWriting.close()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        node.waitUntilExit()
        if node.terminationStatus == 127 { throw XCTSkip("no node on this host") }
        XCTAssertEqual(node.terminationStatus, 0, String(data: err, encoding: .utf8) ?? "")
        return out
    }
}
