import XCTest
@testable import Blackmail

/// His signature drawn as Mail draws it, with the rest of its letter
/// (B-146), on Mail's grey sheet (B-173). The pane inverts a letter's HTML,
/// the sheet's words' black with it, so they are white like the letter's,
/// and leaves its pictures as drawn; and the sheet and its tables have a
/// grey under the invert, rgb(204, 204, 204), which the invert turns to
/// the grey Mail was seen to draw under it in Dark Mode on the test iPad,
/// rgb(51, 51, 51), so the black logo shows on it, and his cells' white
/// borders the same grey, so no lines show in it, as none do in Mail's.
/// Each where the white is declared. On a letter's own page
/// with the sheet in it, and in a conversation's stack, under the HTML the
/// stack inverts. From B-146 until B-173 the sheet was black, the logo
/// hard to see; until B-146 both pages inverted it back, white with black
/// words.
///
/// What he sends is as it was: the sheet in his letters' markup
/// (`AppleMailHTML.signatureOpen`), and the printed page, which prints it
/// as written. The pane's one invert string (`SignatureSheet.invert`) is
/// kept, both pages inverting by it.
final class SignatureLikeMailTests: XCTestCase {

    private let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)

    /// His letter, as this app sends it with his signature, the logo a
    /// picture of its own by `cid:`.
    private var signed: Message {
        PaneLetters.letter(text: "Lunch on Sunday?\n\n--\nSam Example", html: PanePageTests.signedLetter,
                           pictures: ["sig-logo"])
    }

    /// The style of a page: everything before its `</style>`.
    private func rules(of page: String) throws -> String {
        try XCTUnwrap(page.components(separatedBy: "</style>").first)
    }

    /// Every filter in `style`, in order.
    private func filters(_ style: String) -> [String] {
        style.components(separatedBy: "filter:").dropFirst()
            .map { String($0.prefix(while: { $0 != ";" })).trimmingCharacters(in: .whitespaces) }
    }

    /// The stack's document for `letters`, each open, its body as the pane
    /// makes it.
    private func stack(_ letters: [Message]) -> String {
        ConversationDocument.html(
            entries: letters.map { m in
                .init(id: m.id, sender: m.sender, date: m.date, body: PanePage.stackBody(m),
                      isExpanded: true, preview: "")
            },
            inset: style.inset, bodyPointSize: style.bodyPointSize, lineHeight: style.lineHeight)
    }

    /// A letter on its own: the rule for the sheet after Mail's bars, the
    /// sheet and its tables grey under the invert where they declare their
    /// white, and the borders written white the same grey, its only change. The
    /// style's only filters are the invert, on the letter and on its
    /// pictures, which leaves the logo as drawn; none cancels it for the
    /// sheet. The markup as it came, the sheet's own white and black in
    /// it, the logo pointed at the loader inside it.
    func testALetterAloneHasMailsGreySheet() throws {
        let page = try XCTUnwrap(PanePage.letter(signed, style: style))
        let sheet = try rules(of: page)
        XCTAssertEqual(SignatureSheet.css(in: "#bm"),
                       "#bm .bm-signature[style*=\"background-color: #ffffff\"], "
                       + "#bm .bm-signature[style*=\"background-color: rgb(255, 255, 255)\"], "
                       + "#bm .bm-signature table[style^=\"color: rgb(0, 0, 0); background-color: rgb(255, 255, 255); \"] "
                       + "{ background-color: rgb(204, 204, 204) !important; } "
                       + "#bm .bm-signature [style*=\"solid rgb(255, 255, 255)\"] "
                       + "{ border-color: rgb(204, 204, 204) !important; }")
        XCTAssertEqual(filters(sheet), [SignatureSheet.invert, SignatureSheet.invert])
        XCTAssertTrue(sheet.hasSuffix("""
            #bm { filter: \(SignatureSheet.invert); background: #fff; }
            #bm img, #bm video, #bm svg, #bm picture, #bm [style*="background-image"] {
                filter: \(SignatureSheet.invert); }
            \(QuoteBars.css(in: "#bm", palette: QuoteBars.inverted))
            \(SignatureSheet.css(in: "#bm"))

            """), sheet)
        XCTAssertEqual(sheet.components(separatedBy: "bm-signature").count - 1, 4)

        let body = PanePage.content(text: nil, html: PanePageTests.signedLetter, known: ["sig-logo"],
                                    flowed: false)
        XCTAssertTrue(page.contains("<div id=\"bm\">" + body + "</div>"), page)
        XCTAssertTrue(body.contains(AppleMailHTML.signatureOpen + "<div dir=\"ltr\">"
                                    + "<table style=\"" + AppleMailHTML.signatureTableStyle + "\">"
                                    + "<tr><td><img src=\"bmcid://sig-logo\" width=\"70\">"), body)
    }

    /// In a conversation's stack the same: the rule for the sheet under
    /// `.bm-html`, once, whatever its letters, as their bodies come after
    /// the stack's style; the one invert on the letter and its pictures,
    /// the letter's body as it came.
    func testAConversationHasMailsGreySheet() throws {
        let reply = PaneLetters.letter(text: "Yes, Sunday.", html: PanePageTests.quotingSignedLetter)
        for letters in [[signed, reply], [reply], []] {
            let sheet = try rules(of: stack(letters))
            XCTAssertEqual(sheet.components(separatedBy: SignatureSheet.css(in: ".bm-html")).count - 1, 1)
            XCTAssertEqual(sheet.components(separatedBy: "bm-signature").count - 1, 4)
            XCTAssertEqual(filters(sheet), [SignatureSheet.invert, SignatureSheet.invert])
        }
        let html = stack([signed, reply])
        XCTAssertTrue(try rules(of: html).contains(".bm-html { filter: \(SignatureSheet.invert); background: #fff;"))
        let body = PanePage.content(text: nil, html: PanePageTests.signedLetter, known: ["sig-logo"],
                                    flowed: false)
        XCTAssertEqual(PanePage.stackBody(signed), .init(html: body, isHTML: true))
        XCTAssertTrue(html.contains("<div class=\"bm-body bm-html\">" + body + "</div>"), html)
    }

    /// A letter's own page has the rule only where it is inverted and the
    /// sheet is in it: his letter, a reply quoting it with the class kept,
    /// a sheet that has lost its style, where the rule finds no white to
    /// grey, so it has no sheet, as Mail draws none. Not a letter of the pane's set with
    /// no sheet, so its page is as it was; not his letter drawn light, by a
    /// picture from the web, whose sheet is as written on its white; not a
    /// plain letter whose words are the marker. Each HTML letter's page
    /// inverted by the one string, its pictures by it too, nothing else
    /// filtered; a plain letter's not at all.
    func testOnlyAnInvertedLetterWithTheSheetHasItsRule() throws {
        let quoting = PaneLetters.letter(text: "Yes, Sunday.", html: PanePageTests.quotingSignedLetter)
        let bare = PaneLetters.letter(text: "Sam Example",
                                      html: "<p>Lunch?</p><div class=\"bm-signature\">Sam Example</div>")
        let light = PaneLetters.letter(text: "Lunch on Sunday?",
                                       html: "<p><img src=\"https://example.com/roses.jpg\"></p>"
                                           + PanePageTests.signedLetter)
        let plain = PaneLetters.letter(text: AppleMailHTML.signatureOpen + "Sam Example"
                                       + AppleMailHTML.signatureClose)
        let cases = PaneLetters.all.map { ($0, false) }
            + [(signed, true), (quoting, true), (bare, true), (light, false), (plain, false)]
        var drawn = 0
        for (i, (m, has)) in cases.enumerated() {
            guard let page = PanePage.letter(m, style: style) else { continue }
            drawn += 1
            let sheet = try rules(of: page)
            XCTAssertEqual(sheet.contains(SignatureSheet.css(in: "#bm")), has, "letter \(i)")
            XCTAssertEqual(sheet.contains("bm-signature"), has, "letter \(i)")
            let inverted = m.htmlBody.map { LetterScheme.of(html: $0) == .inverted } ?? false
            XCTAssertEqual(filters(sheet), inverted ? [SignatureSheet.invert, SignatureSheet.invert] : [],
                           "letter \(i)")
            XCTAssertEqual(inverted, m.htmlBody != nil && i != cases.count - 2, "letter \(i)")
        }
        XCTAssertGreaterThan(drawn, 15)
        XCTAssertEqual(LetterScheme.of(html: light.htmlBody!), .light)
        XCTAssertFalse(try rules(of: stack([light])).contains("filter: none"))
        // The markup of a sheet that has lost its style, as it came: no
        // white of its own for the rule to put the grey under.
        XCTAssertTrue(try XCTUnwrap(PanePage.letter(bare, style: style))
                        .contains("<div class=\"bm-signature\">Sam Example</div>"))
        for white in SignatureSheet.sheetWhites + [AppleMailHTML.signatureTableStyle, SignatureSheet.borderWhite] {
            XCTAssertFalse(try XCTUnwrap(bare.htmlBody).contains(white), white)
        }
    }

    /// His signature as it is stored, its cells' borders declared white as
    /// his are, `border: 0.99609pt solid rgb(255, 255, 255)`, his name and
    /// numbers as `signatureMarkup`'s.
    static let borderedSignature: String = {
        let cell = "border: 0.99609pt solid rgb(255, 255, 255); vertical-align: top; padding: 5pt; overflow: hidden;"
        return "<div dir=\"ltr\"><table style=\"font-family: UICTFontTextStyleTallBody; "
            + "-webkit-text-size-adjust: auto;\"><tbody><tr><td rowspan=\"2\" style=\"\(cell)\">"
            + "<span style=\"border: none; display: inline-block; overflow: hidden; width: 73px; height: 73px; "
            + "background-color: rgba(255, 255, 255, 0);\"><img src=\"cid:sig-logo\" width=\"70\"></span></td>"
            + "<td style=\"\(cell)\"><b>Sam Example</b><br>555-555-0142</td></tr>"
            + "<tr><td style=\"\(cell)\"><a href=\"https://example.com\">example.com</a></td></tr>"
            + "</tbody></table></div>"
    }()

    /// The `style` of every `<tag` in `html`, in order; "" for one with none.
    private func styles(of tag: String, in html: String) -> [String] {
        html.components(separatedBy: "<" + tag).dropFirst().compactMap { rest in
            guard let next = rest.first, next == " " || next == ">" else { return nil }
            let open = String(rest.prefix(while: { $0 != ">" }))
            guard let start = open.range(of: "style=\"") else { return "" }
            return String(open[start.upperBound...].prefix(while: { $0 != "\"" }))
        }
    }

    /// His signature's white borders are the sheet's grey (B-173): Mail
    /// turns the white his cells' borders declare to the grey it turns the
    /// sheet's white to, and its shots show one plain grey sheet, no lines
    /// in it. Under the pane's invert alone they were black, rgb(0, 0, 0),
    /// on the grey: a grid Mail does not draw. In the letter as this app
    /// sends it the rule finds each of the white it stands for, and only
    /// those: the sheet's white, his table's, which begins with this app's
    /// (as every table it writes there does), and each cell's border, not
    /// the span round his photo with no border or the transparent white.
    /// The markup as it came, the borders' widths with it.
    func testHisSignaturesWhiteBordersAreTheSheetsGrey() throws {
        let signature = "Sam Example\n555-555-0142"
        let html = AppleMailHTML.document(body: "Lunch on Sunday?" + Draft.signatureBlock(signature),
                                          signature: signature, signatureHTML: Self.borderedSignature)
        let m = PaneLetters.letter(text: "Lunch on Sunday?\n\n--\nSam Example", html: html, pictures: ["sig-logo"])
        XCTAssertEqual(LetterScheme.of(html: html), .inverted)
        let page = try XCTUnwrap(PanePage.letter(m, style: style))
        XCTAssertTrue(try rules(of: page).contains("\n" + SignatureSheet.css(in: "#bm") + "\n"), page)
        XCTAssertTrue(try rules(of: stack([m])).contains(SignatureSheet.css(in: ".bm-html")))
        XCTAssertEqual(SignatureSheet.borderWhite, "solid rgb(255, 255, 255)")
        XCTAssertTrue(SignatureSheet.css(in: "#bm").hasSuffix(" #bm .bm-signature [style*=\"solid rgb(255, 255, 255)\"] "
                                                              + "{ border-color: rgb(204, 204, 204) !important; }"))

        let body = PanePage.content(text: nil, html: html, known: ["sig-logo"], flowed: false)
        XCTAssertTrue(page.contains("<div id=\"bm\">" + body + "</div>"), page)
        let sheet = try XCTUnwrap(body.components(separatedBy: "<div class=\"bm-signature\"").last)
        XCTAssertTrue(body.contains(AppleMailHTML.signatureOpen), body)
        XCTAssertTrue(SignatureSheet.sheetWhites.contains { AppleMailHTML.signatureOpen.contains($0) })
        let tables = styles(of: "table", in: sheet)
        XCTAssertEqual(tables.count, 1)
        XCTAssertTrue(tables.allSatisfy { $0.hasPrefix(AppleMailHTML.signatureTableStyle) }, "\(tables)")
        let cells = styles(of: "td", in: sheet)
        XCTAssertEqual(cells.count, 3)
        XCTAssertTrue(cells.allSatisfy { $0.hasPrefix("border: 0.99609pt " + SignatureSheet.borderWhite + ";") },
                      "\(cells)")
        for other in ["div", "span", "img", "b", "a"] {
            XCTAssertFalse(styles(of: other, in: sheet).contains { $0.contains(SignatureSheet.borderWhite) }, other)
        }
        XCTAssertEqual(styles(of: "span", in: sheet).count, 1)

        // Every table this app writes into the sheet begins with its white,
        // the one the rule looks for, whatever the table had.
        for table in ["<table>", "<table style=\"font-family: Georgia;\">", "<table cellpadding=\"4\" style=\"width:100%\">"] {
            let out = AppleMailHTML.onWhitePaper(table + "<tr><td>x</td></tr></table>")
            XCTAssertEqual(styles(of: "table", in: out).map { $0.hasPrefix(AppleMailHTML.signatureTableStyle) },
                           [true], out)
        }

        // The white border, inverted, was black on the grey; under the rule
        // it is the sheet's grey, rgb(51, 51, 51).
        XCTAssertEqual(LetterColoursLikeMailTests.inverted((255, 255, 255)), [0, 0, 0])
        XCTAssertEqual(LetterColoursLikeMailTests.inverted((204, 204, 204)), [51, 51, 51])
    }

    /// The grey under the invert is Mail's grey once inverted: the invert,
    /// then the hue turned half round, as CSS defines them, turn 204 to 51
    /// on each channel, and leave a grey grey.
    func testTheGreyUnderTheInvertIsMailsGrey() {
        XCTAssertEqual(SignatureSheet.underInvert, "rgb(204, 204, 204)")
        XCTAssertEqual(LetterColoursLikeMailTests.inverted((204, 204, 204)), [51, 51, 51])
    }

    /// What he sends is as it was: every letter with his signature carries
    /// the sheet in its markup, its white and black and a light scheme
    /// written on it, for whoever reads it elsewhere. And the pane inverts
    /// by the one string, `invert(1) hue-rotate(180deg)`.
    func testWhatHeSendsAndTheInvertAreAsTheyWere() {
        XCTAssertEqual(AppleMailHTML.signatureOpen, "<div class=\"bm-signature\" style=\""
                       + "background-color: #ffffff; color: #000000; color-scheme: light;\">")
        XCTAssertTrue(PanePageTests.signedLetter.contains(AppleMailHTML.signatureOpen))
        XCTAssertEqual(SignatureSheet.invert, "invert(1) hue-rotate(180deg)")
    }
}
