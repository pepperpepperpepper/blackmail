import XCTest
@testable import Blackmail

/// A plain letter's quotes drawn as Mail draws them (B-147): lines begun
/// with `>` made Mail's `<blockquote type="cite">`, one inside another for
/// each mark more, the marks taken out, with Mail's bars beside them
/// (`QuoteBars`), on a letter's own page, in a conversation's stack and on
/// paper. Until B-147 they were drawn as typed, marks and all, with no bar
/// (B-101). How deep a quote is goes by whether the letter is flowed text
/// (`Message.textIsFlowed`), read from its parts. A line begun `>From `,
/// the letter's links and its escaping are as they were.
final class PlainQuoteBarsTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private let open = "<blockquote type=\"cite\">"
    private let close = "</blockquote>"

    private func html(_ text: String, flowed: Bool = false,
                      escaping: TextLinks.Escaping = .ampersandAndLessThan) -> String {
        PlainQuotes.html(Substring(text), flowed: flowed, escaping: escaping)
    }

    // MARK: - The quotes

    /// A run of lines begun "> " is one quote, Mail's blockquote, the marks
    /// and the one space after them taken out; it begins at the start of
    /// its first line and ends after the break of its last, so the page,
    /// which keeps the lines, draws them where they were. A quoted line
    /// with nothing after its mark is a blank line in the quote; the
    /// spaces after the first are the words'.
    func testAQuoteIsMailsBlockquoteItsMarksTakenOut() {
        XCTAssertEqual(html("Hi Sam,\n\nOn Monday, Carlo wrote:\n> Lunch on Sunday?\n> At one.\n\nYes."),
                       "Hi Sam,\n\nOn Monday, Carlo wrote:\n\(open)Lunch on Sunday?\nAt one.\n\(close)\nYes.")
        XCTAssertEqual(html("> One.\n>\n>Two.\n>   Three."),
                       "\(open)One.\n\nTwo.\n  Three.\(close)")
        XCTAssertEqual(html(">"), "\(open)\(close)")
        XCTAssertEqual(html("Above.\n> Quoted.\n"), "Above.\n\(open)Quoted.\n\(close)")
    }

    /// Each mark more is a quote one level deeper, inside the one before,
    /// and fewer close them again. In a letter that is not flowed text the
    /// marks may have spaces between them: "> > " is two, as ">> " is, and
    /// "> >> " three.
    func testEachMarkMoreIsADeeperQuote() {
        XCTAssertEqual(html("> One.\n> > Two.\n>> Two too.\n> >> Three.\n> One again.\nNone."),
                       "\(open)One.\n\(open)Two.\nTwo too.\n\(open)Three.\n\(close)\(close)"
                       + "One again.\n\(close)None.")
        XCTAssertEqual(html(">>> Three at once.\nNone."), "\(open)\(open)\(open)Three at once.\n"
                       + "\(close)\(close)\(close)None.")
        XCTAssertEqual(html(">  >  > Spaced."), "\(open)\(open)\(open)Spaced.\(close)\(close)\(close)")
    }

    /// In flowed text (RFC 3676) the depth is the unbroken run of marks:
    /// ">> " is two, and "> > " one, its words "> …", as the RFC writes a
    /// quote and Mail reads one.
    func testFlowedTextCountsTheUnbrokenRun() {
        XCTAssertEqual(html("> One.\n> > Still one.\n>> Two.\nNone.", flowed: true),
                       "\(open)One.\n> Still one.\n\(open)Two.\n\(close)\(close)None.")
        XCTAssertEqual(html("> > Still one.", flowed: true, escaping: .ampersandAndBrackets),
                       "\(open)&gt; Still one.\(close)")
    }

    /// Not a quote, and drawn as it came: a line begun ">From ", as a mail
    /// store keeps a line its sender began "From "; a line with a space
    /// before its mark; a mark in the middle of a line. A letter with no
    /// quote in it comes out byte for byte as `TextLinks.plain` writes it,
    /// in both escapings, flowed or not.
    func testFromLinesAndEverythingElseAreAsBefore() {
        let text = ">From here to there.\n > Not a quote.\nTwo > one.\n>Fromage is a quote."
        XCTAssertEqual(html(text), ">From here to there.\n > Not a quote.\nTwo > one.\n"
                       + "\(open)Fromage is a quote.\(close)")
        XCTAssertEqual(html(">From here, flowed.", flowed: true), ">From here, flowed.")
        for plain in PaneLetters.all.compactMap(\.textBody) + ["", "\n", "x", ">From x\n>From y",
                                                               "https://example.com/a?b=1&c=2 <b>"] {
            guard !plain.split(separator: "\n").contains(where: { $0.hasPrefix(">") && !$0.hasPrefix(">From ") })
            else { continue }
            for escaping in [TextLinks.Escaping.ampersandAndLessThan, .ampersandAndBrackets] {
                for flowed in [false, true] {
                    XCTAssertEqual(html(plain, flowed: flowed, escaping: escaping),
                                   TextLinks.plain(Substring(plain), escaping: escaping),
                                   String(reflecting: plain))
                }
            }
        }
    }

    /// Links are made in a quote as anywhere else, a link at the very
    /// start of a quoted line inside the quote; the words escaped as the
    /// page escapes them, in each escaping.
    func testLinksAndEscapingAreThePagesOwn() {
        XCTAssertEqual(html("> See https://example.com/a and www.example.com.\n>> mailto:sam@example.com"),
                       "\(open)See <a href=\"https://example.com/a\">https://example.com/a</a> and "
                       + "<a href=\"http://www.example.com\">www.example.com</a>.\n\(open)"
                       + "<a href=\"mailto:sam@example.com\">mailto:sam@example.com</a>\(close)\(close)")
        XCTAssertEqual(html("> a < b & c > d \"e\""), "\(open)a &lt; b &amp; c > d \"e\"\(close)")
        XCTAssertEqual(html("> a < b & c > d", escaping: .ampersandAndBrackets),
                       "\(open)a &lt; b &amp; c &gt; d\(close)")
        // A tag that falls where a link begins goes before the link.
        let made = TextLinks.plain(Array("x https://example.com".utf8), escaping: .ampersandAndLessThan,
                                   tags: [.init(at: 2, html: "<i>"), .init(at: 21, html: "</i>")])
        XCTAssertEqual(made, "x <i><a href=\"https://example.com\">https://example.com</a></i>")
    }

    /// Bounded: a quote deeper than `deepest` is drawn that deep, the marks
    /// past it as words; a letter whose quotes would add more markup than
    /// it is long, or 64 KiB for a short one, is drawn as before.
    func testDeepAndManyQuotesAreBounded() {
        XCTAssertEqual(PlainQuotes.deepest, 32)
        let deep = String(repeating: ">", count: 40) + " Deep."
        for flowed in [false, true] {
            XCTAssertEqual(html(deep, flowed: flowed), String(repeating: open, count: 32) + ">>>>>>>> Deep."
                           + String(repeating: close, count: 32))
        }
        XCTAssertEqual(PlainQuotes.markupAllowed(10), 64 * 1_024)
        XCTAssertEqual(PlainQuotes.markupAllowed(200_000), 200_000)

        // In and out on every other line: 37 bytes of markup a quote,
        // twelve times the letter.
        let many = String(repeating: ">\n\n", count: 40_000)
        XCTAssertEqual(html(many), TextLinks.plain(Substring(many), escaping: .ampersandAndLessThan))
        // Under the limit, every one made.
        let some = String(repeating: "> Yes.\nNo.\n", count: 1_000)
        XCTAssertEqual(html(some).components(separatedBy: open).count - 1, 1_000)
    }

    // MARK: - The pages

    /// The pane's set has one letter with quotes: Carlo's two lines.
    private var quoted: Message { PaneLetters.all[PanePageTests.quoted] }

    private let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)

    /// Mail's dark colours, from MessageUI's asset catalog: violet, teal,
    /// green, as Mail draws them in Dark Mode on a page that is not
    /// inverted.
    func testMailsDarkColours() {
        XCTAssertEqual(QuoteBars.dark, ["rgb(191, 90, 242)", "rgb(0, 200, 250)", "rgb(87, 217, 119)"])
        let quote = ":is(blockquote[type=cite i], blockquote[class~=gmail_quote])"
        XCTAssertEqual(QuoteBars.css(in: "#bm", palette: QuoteBars.dark), [
            "#bm \(quote) { padding-left: 5px !important; margin: 0 !important; "
                + "border-left: 1px solid rgb(191, 90, 242) !important; color: rgb(191, 90, 242) !important; }",
            "#bm \(quote) \(quote) { padding-left: 5px !important; margin: 0 !important; "
                + "border-left: 1px solid rgb(0, 200, 250) !important; color: rgb(0, 200, 250) !important; }",
            "#bm \(quote) \(quote) \(quote) { padding-left: 5px !important; margin: 0 !important; "
                + "border-left: 1px solid rgb(87, 217, 119) !important; color: rgb(87, 217, 119) !important; }",
        ].joined(separator: "\n"))
    }

    /// A plain letter on its own: its quote Mail's blockquote, the marks
    /// gone, the words around it as before; Mail's rules under `#bm` in
    /// its dark colours, none in its light ones, and nothing inverted.
    func testALetterOnItsOwnHasTheBarsInMailsDarkColours() throws {
        let page = try XCTUnwrap(PanePage.letter(quoted, style: style))
        let body = "Dear Sam,\n\nIt's &lt;b>not&lt;/b> bold &amp; it's \"quoted\" > here.\n\u{2028}é \u{1F4EE}\n\n"
            + "\(open)On Monday, Carlo wrote:\nThe roses?\(close)"
        XCTAssertTrue(page.contains("<div id=\"bm\">\(body)</div>"), page)
        let sheet = try XCTUnwrap(page.components(separatedBy: "</style>").first)
        XCTAssertTrue(sheet.contains("  a { color: #0A84FF; }\n  "
                                     + QuoteBars.css(in: "#bm", palette: QuoteBars.dark) + "\n"), sheet)
        XCTAssertTrue(sheet.contains("white-space: pre-wrap;"))
        for light in QuoteBars.colours + ["filter", "invert"] {
            XCTAssertFalse(sheet.contains(light), light)
        }
    }

    /// In a conversation's stack the same letter's body is the same quote,
    /// escaped as the stack escapes text, at first draw and by `bmFill`;
    /// the stack's rules under `.bm-text`, a plain letter's body, in Mail's
    /// dark colours, beside the HTML's light ones under `.bm-html`.
    func testAConversationHasTheBarsToo() throws {
        let body = PanePage.stackBody(quoted)
        XCTAssertEqual(body, .init(html: "Dear Sam,\n\nIt's &lt;b&gt;not&lt;/b&gt; bold &amp; it's \"quoted\" "
                                   + "&gt; here.\n\u{2028}é \u{1F4EE}\n\n"
                                   + "\(open)On Monday, Carlo wrote:\nThe roses?\(close)", isHTML: false))
        let html = ConversationDocument.html(
            entries: [.init(id: quoted.id, sender: quoted.sender, date: quoted.date, body: body,
                            isExpanded: true, preview: "")],
            inset: style.inset, bodyPointSize: style.bodyPointSize, lineHeight: style.lineHeight)
        XCTAssertTrue(html.contains("<div class=\"bm-body bm-text\">\(body.html)</div>"), html)
        XCTAssertTrue(html.contains("\n" + QuoteBars.css(in: ".bm-html") + "\n"
                                    + QuoteBars.css(in: ".bm-text", palette: QuoteBars.dark) + "\n"), html)
        let fill = ConversationDocument.Fill(sectionID: "m1_1", body: body)
        XCTAssertEqual(try XCTUnwrap(fill.arguments["html"] as? String), body.html)
    }

    /// On paper the same quote, with Mail's light colours, as the paper is
    /// white and not inverted; none of the pane's dark ones.
    func testThePrintHasTheBarsInMailsLightColours() throws {
        let page = PrintPage.letter(quoted, style: .init(senderPointSize: 17, metaPointSize: 15,
                                                          subjectPointSize: 18, bodyPointSize: 17,
                                                          lineHeight: 1.41),
                                    size: { "\($0) bytes" })
        XCTAssertTrue(page.contains("\(open)On Monday, Carlo wrote:\nThe roses?\(close)</div></body>"), page)
        let sheet = try XCTUnwrap(page.components(separatedBy: "</style>").first)
        XCTAssertTrue(sheet.hasSuffix("\n" + QuoteBars.css(in: "#bm") + "\n"), sheet)
        for dark in QuoteBars.dark { XCTAssertFalse(sheet.contains(dark), dark) }
    }

    /// A flowed letter's page counts by the unbroken run; the same words
    /// not flowed, by the spaced one.
    func testAFlowedLettersPageCountsAsFlowedText() throws {
        var m = PaneLetters.letter(text: "> One.\n> > Two?")
        let spaced = try XCTUnwrap(PanePage.letter(m, style: style))
        XCTAssertTrue(spaced.contains("<div id=\"bm\">\(open)One.\n\(open)Two?\(close)\(close)</div>"), spaced)
        m.textIsFlowed = true
        let flowed = try XCTUnwrap(PanePage.letter(m, style: style))
        XCTAssertTrue(flowed.contains("<div id=\"bm\">\(open)One.\n> Two?\(close)</div>"), flowed)
        XCTAssertEqual(PanePage.stackBody(m).html, "\(open)One.\n&gt; Two?\(close)")
    }

    // MARK: - Flowed, read from the letter

    private func letter(_ body: String) -> Data {
        Data(("From: Carlo <carlo@example.org>\r\nTo: owner@example.com\r\nSubject: Lunch\r\n"
              + "Date: Mon, 20 Sep 2026 10:00:00 +0000\r\nMessage-ID: <lunch@example.org>\r\n"
              + "MIME-Version: 1.0\r\n" + body).utf8)
    }

    private func mime(_ subtype: String, _ parts: [String]) -> String {
        "Content-Type: multipart/\(subtype); boundary=\"B\"\r\n\r\n"
            + parts.map { "--B\r\n" + $0 + "\r\n" }.joined() + "--B--\r\n"
    }

    /// A letter's plain words are flowed text when every part of them says
    /// `format=flowed`, in any case, quoted or not: a plain letter of one
    /// part, Apple Mail's plain words beside its HTML; and not when one
    /// part does not, nor for a letter with no plain part of its own.
    func testFlowedIsReadFromTheLetter() {
        let flowed = "Content-Type: text/plain; charset=utf-8; format=flowed\r\n\r\n> > Lunch?\r\n"
        let fixed = "Content-Type: text/plain; charset=utf-8\r\n\r\n> > Lunch?\r\n"
        let html = "Content-Type: text/html; charset=utf-8\r\n\r\n<p>Lunch?</p>\r\n"
        let cases: [(String, Bool, String)] = [
            (flowed, true, "flowed"),
            (fixed, false, "not flowed"),
            ("Content-Type: text/plain; FORMAT=\"Flowed\"; delsp=yes\r\n\r\nLunch?\r\n", true, "quoted, capitals"),
            (mime("alternative", [flowed, html]), true, "Apple Mail's pair"),
            (mime("mixed", [flowed, fixed]), false, "one part not flowed"),
            (mime("mixed", [flowed, flowed]), true, "every part flowed"),
            (html, false, "HTML alone"),
        ]
        for (body, expected, name) in cases {
            let decoded = MIMEDecoder.decodeMessage(letter(body))
            XCTAssertEqual(decoded.textIsFlowed, expected, name)
            let structure = MIMEDecoder.parse(letter(body)).structure
            XCTAssertEqual(MIMEDecoder.bodyPlan(of: structure).textIsFlowed, expected, name)
        }
    }

    /// Through the shipping repository and the scripted server, as Gmail
    /// describes and serves a letter: a flowed letter opened whole and one
    /// too large to fetch whole, opened in part, both flowed, their pages
    /// counting by the unbroken run; a letter not flowed, not.
    func testTheRepositoryReadsFlowedWholeAndInPart() async throws {
        let server = ScriptedIMAPServer(inboxCount: 2)
        let suite = "PlainQuoteBarsTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let book = RecipientBook(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = IMAPMailRepository(
            account: server.account, password: server.password, transport: server.transportFactory,
            recipients: book, signatureImages: { [] }, shelf: keptShelf(for: server.account),
            largeLetterBytes: 4_000, largeLetterSectionBytes: 1_000)

        let words = "> One.\r\n> > Two?\r\n"
        let long = String(repeating: "The rest of a long letter.\r\n", count: 200)
        let letters: [(String, String, Bool, Bool)] = [
            ("Whole", "format=flowed", true, false),
            ("Long", "format=flowed", true, true),
            ("Fixed", "format=fixed", false, false),
        ]
        var uids: [String: UInt32] = [:]
        for (i, (subject, format, _, isLong)) in letters.enumerated() {
            let raw = "From: Carlo <carlo@example.org>\r\nTo: owner@example.com\r\nSubject: \(subject)\r\n"
                + "Date: Mon, 20 Sep 2026 10:00:00 +0000\r\nMessage-ID: <\(subject)@example.org>\r\n"
                + "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8; \(format)\r\n\r\n"
                + words + (isLong ? long : "")
            let letter = Server.Letter(from: Server.carlo, to: [Server.owner], subject: subject,
                                       date: Server.newestDate.addingTimeInterval(Double(i + 1) * 60),
                                       text: "", messageID: "<\(subject)@example.org>")
            uids[subject] = try XCTUnwrap(server.deliver(described: Data(raw.utf8), as: letter,
                                                         to: [Server.inbox])[Server.inbox])
        }
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        for (subject, _, isFlowed, isLong) in letters {
            let uid = try XCTUnwrap(uids[subject])
            let row = try XCTUnwrap(rows.first { $0.id.hasSuffix("/\(uid)") }, subject)
            let m = try await repository.open(row)
            XCTAssertEqual(m.textIsFlowed, isFlowed, subject)
            XCTAssertEqual(m.isShortened, isLong, subject)
            let page = try XCTUnwrap(PanePage.letter(m, style: style), subject)
            XCTAssertTrue(page.contains(isFlowed ? "\(open)One.\n> Two?\n\(close)"
                                                 : "\(open)One.\n\(open)Two?\n\(close)\(close)"), page)
        }
        XCTAssertEqual(server.violations, [])
    }
}
