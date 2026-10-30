import XCTest
@testable import Blackmail

/// An HTML letter's quotes in Dark as Mail's (B-180): compared with Mail
/// 16.5.1 on the test iPad, 2026-10-29 (round r6-n-compare, C-4b), Mail's
/// HTML letter has its quotes in the same dark colours as its plain
/// letter's, and the line before its quote, ending "wrote:", with the
/// first level's bar and colour; the owner's ruling of that day, copy
/// Apple Mail.
final class HTMLQuotesLikeMailTests: XCTestCase {

    private let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)

    /// The round's letter: Mail's "wrote:" line as a `<p>`, then three
    /// quotes one inside another, and back to the first.
    static let reply = "<p>Yes, that works.</p>\n<p>On Monday, Carlo wrote:</p>\n"
        + "<blockquote type=\"cite\">Shall we meet?<blockquote type=\"cite\">At ten?"
        + "<blockquote type=\"cite\">Or eleven.</blockquote></blockquote>Back to one.</blockquote>"
        + "<p>Sam</p>"

    static let marked = reply.replacingOccurrences(of: "<p>On Monday", with: "<p class=\"bm-attribution\">On Monday")

    private func letter(_ html: String) -> Message {
        PaneLetters.letter(html: html)
    }

    private func sheet(_ page: String) throws -> String {
        try XCTUnwrap(page.components(separatedBy: "</style>").first)
    }

    // MARK: - The colours

    /// `invert(1) hue-rotate(180deg)` on an sRGB colour, as WebKit's filter
    /// draws it: the invert, then the hue turn's matrix, clamped at the end.
    private func throughTheInvert(_ c: [Double]) -> [Double] {
        let m: [[Double]] = [[-0.574, 1.430, 0.144], [0.426, 0.430, 0.144], [0.426, 1.430, -0.856]]
        let v = c.map { 255 - $0 }
        return m.map { row in min(255, max(0, zip(row, v).map(*).reduce(0, +))) }
    }

    private func rgb(_ s: String) throws -> [Double] {
        XCTAssertTrue(s.hasPrefix("rgb(") && s.hasSuffix(")"), s)
        let parts = s.dropFirst(4).dropLast().split(separator: ",").map {
            Double($0.trimmingCharacters(in: .whitespaces))
        }
        return try parts.map { try XCTUnwrap($0) }
    }

    private func distance(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).map { ($0 - $1) * ($0 - $1) }.reduce(0, +).squareRoot()
    }

    /// The sum is the round's: Mail's light violet through the invert is
    /// what the round measured on Blackmail's HTML letter.
    func testTheInvertTurnsMailsLightVioletIntoWhatTheRoundMeasured() throws {
        let measured: [Double] = [152, 150, 255]
        XCTAssertLessThan(distance(throughTheInvert(try rgb(QuoteBars.colours[0])), measured), 2)
    }

    /// Each colour of `inverted` comes out through the invert as Mail's
    /// dark one, the first within 2, the second and third as near as the
    /// invert can come (it clamps), and none of the colours a step from it
    /// in any channel nearer: solved again here.
    func testTheInvertedColoursComeOutMailsDarkOnes() throws {
        let within: [Double] = [2, 44, 15]
        for level in 0..<3 {
            let light = try rgb(QuoteBars.inverted[level])
            let dark = try rgb(QuoteBars.dark[level])
            let near = distance(throughTheInvert(light), dark)
            XCTAssertLessThan(near, within[level], "level \(level + 1)")
            for dr in -1...1 { for dg in -1...1 { for db in -1...1 {
                let other = [light[0] + Double(dr), light[1] + Double(dg), light[2] + Double(db)]
                guard other.allSatisfy({ (0...255).contains($0) }) else { continue }
                XCTAssertGreaterThanOrEqual(distance(throughTheInvert(other), dark), near - 0.001,
                                            "level \(level + 1) \(other)")
            } } }
        }
        XCTAssertEqual(QuoteBars.inverted, ["rgb(201, 100, 252)", "rgb(0, 144, 230)", "rgb(0, 111, 25)"])
    }

    // MARK: - The pages

    /// The round's letter on its own, inverted: its quotes in the colours
    /// the invert turns into Mail's dark ones, and its "wrote:" line
    /// marked, with the first level's rule; none of the light colours.
    func testAnInvertedLettersQuotesAndItsLineAreMailsDarkColours() throws {
        let m = letter(Self.reply)
        XCTAssertEqual(LetterScheme.of(html: Self.reply), .inverted)
        let page = try XCTUnwrap(PanePage.letter(m, style: style))
        let sheet = try self.sheet(page)
        XCTAssertTrue(sheet.contains("\n" + QuoteBars.css(in: "#bm", palette: QuoteBars.inverted) + "\n"
                                     + QuoteBars.attributionCSS(in: "#bm", palette: QuoteBars.inverted) + "\n"),
                      sheet)
        XCTAssertEqual(QuoteBars.attributionCSS(in: "#bm", palette: QuoteBars.inverted),
                       "#bm .bm-attribution { padding-left: 5px !important; "
                       + "border-left: 1px solid rgb(201, 100, 252) !important; "
                       + "color: rgb(201, 100, 252) !important; }\n"
                       + "#bm \(QuoteBars.quote) .bm-attribution { padding-left: 5px !important; "
                       + "border-left: 1px solid rgb(0, 144, 230) !important; "
                       + "color: rgb(0, 144, 230) !important; }\n"
                       + "#bm \(QuoteBars.quote) \(QuoteBars.quote) .bm-attribution { padding-left: 5px !important; "
                       + "border-left: 1px solid rgb(0, 111, 25) !important; "
                       + "color: rgb(0, 111, 25) !important; }")
        for light in QuoteBars.colours { XCTAssertFalse(sheet.contains(light), light) }
        XCTAssertTrue(page.contains("<div id=\"bm\">\(Self.marked)</div>"), page)
    }

    /// In a conversation's stack the same: its body marked, and the stack's
    /// rules for an inverted letter's quotes and line in the inverted
    /// colours, a light letter's in the light ones and one in its own
    /// colours in the dark ones.
    func testTheStackHasTheSameColoursAndLine() throws {
        let body = PanePage.stackBody(letter(Self.reply))
        XCTAssertEqual(body.html, Self.marked)
        let html = ConversationDocument.html(
            entries: [.init(id: "1/2", sender: "Jane <j@example.com>", date: Date(timeIntervalSince1970: 0),
                            body: body, isExpanded: true, preview: "")],
            inset: 20, bodyPointSize: 17, lineHeight: 1.4)
        let sheet = try self.sheet(html)
        for (scope, palette) in [(".bm-html", QuoteBars.inverted), (".bm-light", QuoteBars.colours),
                                 (".bm-own", QuoteBars.dark)] {
            XCTAssertTrue(sheet.contains(QuoteBars.css(in: scope, palette: palette) + "\n"
                                         + QuoteBars.attributionCSS(in: scope, palette: palette) + "\n"),
                          scope)
        }
        XCTAssertFalse(sheet.contains(".bm-html :is(blockquote[type=cite i], blockquote[class~=gmail_quote]) "
                                      + "{ padding-left: 5px !important; margin: 0 !important; "
                                      + "border-left: 1px solid rgb(88, 86, 214)"))
        XCTAssertFalse(sheet.contains(".bm-text .bm-attribution"), "a plain letter's line is in its quote")
    }

    /// A light letter, drawn on its own white, keeps Mail's light colours,
    /// its line with them; one in its own colours, the dark ones.
    func testALightLetterAndOneInItsOwnColoursKeepTheirPalettes() throws {
        let light = "<img src=\"https://example.com/a.png\">" + Self.reply
        XCTAssertEqual(LetterScheme.of(html: light), .light)
        let lightSheet = try sheet(try XCTUnwrap(PanePage.letter(letter(light), style: style)))
        XCTAssertTrue(lightSheet.contains(QuoteBars.css(in: "#bm") + "\n"
                                          + QuoteBars.attributionCSS(in: "#bm")), lightSheet)
        XCTAssertFalse(lightSheet.contains(QuoteBars.inverted[0]))

        let own = "<html><head><meta name=\"color-scheme\" content=\"light dark\"></head><body>"
            + Self.reply + "</body></html>"
        XCTAssertEqual(LetterScheme.of(html: own), .own)
        let ownPage = try XCTUnwrap(PanePage.letter(letter(own), style: style))
        let ownSheet = try sheet(ownPage)
        XCTAssertTrue(ownSheet.contains(QuoteBars.css(in: "#bm", palette: QuoteBars.dark) + "\n"
                                        + QuoteBars.attributionCSS(in: "#bm", palette: QuoteBars.dark)), ownSheet)
        XCTAssertTrue(ownPage.contains("<p class=\"bm-attribution\">On Monday"), ownPage)
    }

    /// On paper, white and not inverted, the light colours, the line's
    /// too; a letter with no such line has no rule for it.
    func testThePaperHasTheLineInTheLightColour() throws {
        let style = PrintPage.Style(senderPointSize: 17, metaPointSize: 15, subjectPointSize: 18,
                                    bodyPointSize: 17, lineHeight: 1.41)
        let page = PrintPage.letter(letter(Self.reply), style: style, size: { "\($0) bytes" })
        let sheet = try self.sheet(page)
        XCTAssertTrue(sheet.hasSuffix("\n" + QuoteBars.css(in: "#bm") + "\n"
                                      + QuoteBars.attributionCSS(in: "#bm") + "\n"), sheet)
        XCTAssertTrue(page.contains(Self.marked), page)
        let none = PrintPage.letter(letter("<p>No quote here.</p>"), style: style, size: { "\($0) bytes" })
        XCTAssertFalse(none.contains("bm-attribution"), none)
    }

    /// A plain letter's page is as it was: its line is drawn in its quote
    /// (`PlainQuotes`, B-172), and no rule for a marked line is added.
    func testAPlainLettersPageIsAsItWas() throws {
        let m = PaneLetters.letter(text: "Yes.\n\nOn Monday, Carlo wrote:\n> The roses?")
        let page = try XCTUnwrap(PanePage.letter(m, style: style))
        XCTAssertFalse(page.contains("bm-attribution"), page)
        XCTAssertFalse(PanePage.stackBody(m).html.contains("bm-attribution"))
    }

    // MARK: - Which line is marked

    func testGmailsLineKeepsItsClassAndGainsOne() {
        let html = "<div dir=\"ltr\">Thanks!</div><br><div class=\"gmail_quote\">"
            + "<div dir=\"ltr\" class=\"gmail_attr\">On Mon, 20 Oct 2026 at 09:12, Sam Example &lt;"
            + "<a href=\"mailto:sam@example.com\">sam@example.com</a>&gt; wrote:<br></div>"
            + "<blockquote class=\"gmail_quote\" style=\"margin:0px\">Lunch?</blockquote></div>"
        XCTAssertEqual(QuoteBars.attributed(html),
                       html.replacingOccurrences(of: "class=\"gmail_attr\"",
                                                 with: "class=\"gmail_attr bm-attribution\""))
    }

    func testALineAQuoteClosesIsMarked() {
        XCTAssertEqual(QuoteBars.attributed("<p>On Monday, Carlo wrote:<blockquote type=cite>x</blockquote>"),
                       "<p class=\"bm-attribution\">On Monday, Carlo wrote:<blockquote type=cite>x</blockquote>")
        XCTAssertEqual(QuoteBars.attributed("<P>On Monday, Carlo wrote:&nbsp;</P>\r\n<BLOCKQUOTE TYPE=\"CITE\">x"),
                       "<P class=\"bm-attribution\">On Monday, Carlo wrote:&nbsp;</P>\r\n<BLOCKQUOTE TYPE=\"CITE\">x")
        XCTAssertEqual(QuoteBars.attributed("<div><span>On Monday, Carlo wrote:</span> </div>"
                                            + "<blockquote type=\"cite\">x</blockquote>"),
                       "<div class=\"bm-attribution\"><span>On Monday, Carlo wrote:</span> </div>"
                       + "<blockquote type=\"cite\">x</blockquote>")
    }

    func testItsOtherClassesAreKeptHoweverWritten() {
        let quote = "<blockquote type=\"cite\">x</blockquote>"
        XCTAssertEqual(QuoteBars.attributed("<div class=a>On Monday, Carlo wrote:</div>" + quote),
                       "<div class=\"a bm-attribution\">On Monday, Carlo wrote:</div>" + quote)
        XCTAssertEqual(QuoteBars.attributed("<div class='a b'>On Monday, Carlo wrote:</div>" + quote),
                       "<div class='a b bm-attribution'>On Monday, Carlo wrote:</div>" + quote)
        XCTAssertEqual(QuoteBars.attributed("<div class=\"\">On Monday, Carlo wrote:</div>" + quote),
                       "<div class=\"bm-attribution\">On Monday, Carlo wrote:</div>" + quote)
        XCTAssertEqual(QuoteBars.attributed("<div class id=x>On Monday, Carlo wrote:</div>" + quote),
                       "<div class=\"bm-attribution\" id=x>On Monday, Carlo wrote:</div>" + quote)
    }

    /// Only the line seen in Mail: none not ending "wrote:", none with
    /// anything between it and the quote,
    /// none of words not in an element of their own, none before a
    /// blockquote that is no quote, and Mail's own reply, its line in a
    /// quote already, as it came; a letter with none byte for byte.
    func testNoOtherLineIsMarked() {
        let unchanged = [
            "<p>On Monday, Carlo said:</p><blockquote type=\"cite\">x</blockquote>",
            "<p>On Monday, Carlo wrote:</p><br><blockquote type=\"cite\">x</blockquote>",
            "<p>On Monday, Carlo wrote:</p>Hi<blockquote type=\"cite\">x</blockquote>",
            "On Monday, Carlo wrote:<blockquote type=\"cite\">x</blockquote>",
            "<p>On Monday, Carlo wrote:</p><blockquote>x</blockquote>",
            "<p>On Monday, Carlo wrote:</p><!-- --><blockquote type=\"cite\">x</blockquote>",
            "<style>p::after { content: 'wrote:' }</style><blockquote type=\"cite\">x</blockquote>",
            PanePageTests.appleMailReplyBody,
            "<p>Nothing quoted, though it wrote: a blockquote word.</p>",
        ]
        for html in unchanged {
            XCTAssertEqual(QuoteBars.attributed(html), html)
        }
        // Each line before a top-level quote is its own.
        let two = "<p>A wrote:</p><blockquote type=\"cite\">x</blockquote><p>B wrote:</p>"
            + "<blockquote class=\"gmail_quote\">y</blockquote>"
        XCTAssertEqual(QuoteBars.attributed(two), two.replacingOccurrences(of: "<p>", with: "<p class=\"bm-attribution\">"))
    }

    // MARK: - The line inside a quote (B-180, fixed again)

    /// A Gmail reply to a reply, as Gmail writes it: its line, its quote,
    /// and in the quote the earlier letter's line and quote, each line a
    /// `div.gmail_attr` in a `div.gmail_quote`.
    static let gmailNested = "<div dir=\"ltr\">Fine by me.</div><br><div class=\"gmail_quote\">"
        + "<div dir=\"ltr\" class=\"gmail_attr\">On Tue, 28 Oct 2026 at 10:02, Sam Example &lt;"
        + "<a href=\"mailto:sam@example.com\">sam@example.com</a>&gt; wrote:<br></div>"
        + "<blockquote class=\"gmail_quote\" style=\"margin:0px 0px 0px 0.8ex\">"
        + "<div dir=\"ltr\">Thursday, then.</div><br><div class=\"gmail_quote\">"
        + "<div dir=\"ltr\" class=\"gmail_attr\">On Mon, 27 Oct 2026 at 18:40, Pat Example &lt;"
        + "<a href=\"mailto:pat@example.net\">pat@example.net</a>&gt; wrote:<br></div>"
        + "<blockquote class=\"gmail_quote\" style=\"margin:0px 0px 0px 0.8ex\">Lunch this week?"
        + "</blockquote></div></blockquote></div>"

    /// Gmail's nested line, inside the first level before the second, is
    /// marked as its top line is: Mail draws it as the second level's.
    func testGmailsNestedLineIsMarked() {
        XCTAssertEqual(QuoteBars.attributed(Self.gmailNested),
                       Self.gmailNested.replacingOccurrences(of: "class=\"gmail_attr\"",
                                                             with: "class=\"gmail_attr bm-attribution\""))
        XCTAssertEqual(QuoteBars.attributed(Self.gmailNested).components(separatedBy: "bm-attribution").count - 1, 2)
        // Mail's own form one level down, and two.
        XCTAssertEqual(QuoteBars.attributed("<blockquote type=\"cite\"><p>On Monday, Carlo wrote:</p>"
                                            + "<blockquote type=\"cite\">x</blockquote></blockquote>"),
                       "<blockquote type=\"cite\"><p class=\"bm-attribution\">On Monday, Carlo wrote:</p>"
                       + "<blockquote type=\"cite\">x</blockquote></blockquote>")
        XCTAssertEqual(QuoteBars.attributed("<blockquote type=cite><blockquote type=cite><p>X wrote:</p>"
                                            + "<blockquote type=cite>x</blockquote></blockquote></blockquote>"),
                       "<blockquote type=cite><blockquote type=cite><p class=\"bm-attribution\">X wrote:</p>"
                       + "<blockquote type=cite>x</blockquote></blockquote></blockquote>")
    }

    /// Inside a quote, as at the top, a line not ending "wrote:", one with
    /// something between it and the quote, and Mail's own reply quoted,
    /// its line in a quote of its own, are as they came.
    func testANestedLineNotSeenInMailStaysBare() {
        let unchanged = [
            "<blockquote type=\"cite\"><p>On Monday, Carlo said:</p><blockquote type=\"cite\">x</blockquote>"
                + "</blockquote>",
            "<blockquote type=\"cite\"><p>On Monday, Carlo wrote:</p><br><blockquote type=\"cite\">x"
                + "</blockquote></blockquote>",
            "<blockquote type=\"cite\">" + PanePageTests.appleMailReplyBody + "</blockquote>",
        ]
        for html in unchanged {
            XCTAssertEqual(QuoteBars.attributed(html), html)
        }
    }

    /// The line's rule has one line a level: at the top the first colour,
    /// as before, byte for byte; inside one quote the second, inside two
    /// the third, each in the page's palette.
    func testTheLinesRuleHasOneLineALevel() {
        let quote = QuoteBars.quote
        func line(_ selector: String, _ colour: String) -> String {
            "\(selector) { padding-left: 5px !important; "
                + "border-left: 1px solid \(colour) !important; color: \(colour) !important; }"
        }
        for (scope, palette) in [("#bm", QuoteBars.inverted), (".bm-light", QuoteBars.colours),
                                 (".bm-own", QuoteBars.dark)] {
            XCTAssertEqual(QuoteBars.attributionCSS(in: scope, palette: palette).components(separatedBy: "\n"),
                           [line("\(scope) .bm-attribution", palette[0]),
                            line("\(scope) \(quote) .bm-attribution", palette[1]),
                            line("\(scope) \(quote) \(quote) .bm-attribution", palette[2])], scope)
        }
        XCTAssertEqual(QuoteBars.attributionCSS(in: "#bm", palette: QuoteBars.inverted)
                        .components(separatedBy: "\n").dropFirst().first,
                       "#bm \(quote) .bm-attribution { padding-left: 5px !important; "
                       + "border-left: 1px solid rgb(0, 144, 230) !important; color: rgb(0, 144, 230) !important; }")
    }

    /// The nested reply on its own page, in a stack and on paper: both
    /// lines marked, and each page's rule for the second level's line in
    /// its palette.
    func testTheNestedReplysPagesHaveTheSecondLevelsLine() throws {
        let m = letter(Self.gmailNested)
        let marked = QuoteBars.attributed(Self.gmailNested)
        XCTAssertEqual(LetterScheme.of(html: Self.gmailNested), .inverted)
        let page = try XCTUnwrap(PanePage.letter(m, style: style))
        XCTAssertTrue(page.contains(marked), page)
        XCTAssertTrue(try sheet(page).contains("#bm \(QuoteBars.quote) .bm-attribution { padding-left: 5px !important; "
                                               + "border-left: 1px solid \(QuoteBars.inverted[1]) !important;"))
        XCTAssertEqual(PanePage.stackBody(m).html, marked)
        let stack = ConversationDocument.html(
            entries: [.init(id: "1/2", sender: "Jane <j@example.com>", date: Date(timeIntervalSince1970: 0),
                            body: PanePage.stackBody(m), isExpanded: true, preview: "")],
            inset: 20, bodyPointSize: 17, lineHeight: 1.4)
        XCTAssertTrue(try sheet(stack).contains(".bm-html \(QuoteBars.quote) .bm-attribution "
                                                + "{ padding-left: 5px !important; "
                                                + "border-left: 1px solid \(QuoteBars.inverted[1]) !important;"))
        let printStyle = PrintPage.Style(senderPointSize: 17, metaPointSize: 15, subjectPointSize: 18,
                                         bodyPointSize: 17, lineHeight: 1.41)
        let paper = PrintPage.letter(m, style: printStyle, size: { "\($0) bytes" })
        XCTAssertTrue(paper.contains(marked), paper)
        XCTAssertTrue(try sheet(paper).contains("#bm \(QuoteBars.quote) .bm-attribution { padding-left: 5px !important; "
                                                + "border-left: 1px solid \(QuoteBars.colours[1]) !important;"))
    }

    /// A stranger's letter cannot make the reading slow: one of 20,000
    /// elements opened and never closed, then quotes, is read at once.
    func testADeepLetterIsReadNoFurther() {
        let deep = String(repeating: "<div>", count: 20_000) + "<p>X wrote:</p><blockquote type=cite>x"
        XCTAssertEqual(QuoteBars.attributed(deep), deep)
        let wide = String(repeating: "<p>X wrote:</p><blockquote type=cite>x</blockquote>", count: 2_000)
        XCTAssertEqual(QuoteBars.attributed(wide).components(separatedBy: "bm-attribution").count - 1, 2_000)
    }
}
