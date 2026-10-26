import XCTest
@testable import Blackmail

/// His signature drawn as Mail draws it, with the rest of its letter
/// (B-146): no white sheet under it, on a letter's own page or in a
/// conversation's stack. The pane inverts a letter's HTML, the sheet's
/// white and its words' black with it, so the sheet is black and its words
/// white like the letter's, and leaves its pictures as drawn, the logo
/// dark on the black: as Mail's `apple-invert-lightness()` draws a letter
/// that declares no colour scheme in Dark Mode (read in its code, not
/// seen). Until B-146 both pages inverted the sheet back, white with black
/// words: the stack since the first version, a letter alone since B-130.
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

    /// A letter on its own: no rule for the sheet, so it takes the page's
    /// invert with the rest. The style's only filters are the invert, on
    /// the letter and on its pictures, which leaves the logo as drawn;
    /// none cancels it for the sheet, and no `filter: none` leaves the
    /// sheet's pictures out of the pictures' rule. Mail's bars straight
    /// after the pictures' rule. The markup as it came, the sheet's own
    /// white and black in it, the logo pointed at the loader inside it.
    func testALetterAloneHasNoWhiteSheet() throws {
        let page = try XCTUnwrap(PanePage.letter(signed, style: style))
        let sheet = try rules(of: page)
        XCTAssertFalse(sheet.contains("bm-signature"), sheet)
        XCTAssertEqual(filters(sheet), [SignatureSheet.invert, SignatureSheet.invert])
        XCTAssertTrue(sheet.hasSuffix("""
            #bm { filter: \(SignatureSheet.invert); background: #fff; }
            #bm img, #bm video, #bm svg, #bm picture, #bm [style*="background-image"] {
                filter: \(SignatureSheet.invert); }
            \(QuoteBars.css(in: "#bm"))

            """), sheet)

        let body = PanePage.content(text: nil, html: PanePageTests.signedLetter, known: ["sig-logo"])
        XCTAssertTrue(page.contains("<div id=\"bm\">" + body + "</div>"), page)
        XCTAssertTrue(body.contains(AppleMailHTML.signatureOpen + "<div dir=\"ltr\">"
                                    + "<table style=\"" + AppleMailHTML.signatureTableStyle + "\">"
                                    + "<tr><td><img src=\"bmcid://sig-logo\" width=\"70\">"), body)
    }

    /// In a conversation's stack the same: no rule for the sheet under
    /// `.bm-html`, the one invert on the letter and its pictures, the
    /// letter's body as it came.
    func testAConversationHasNoWhiteSheet() throws {
        let reply = PaneLetters.letter(text: "Yes, Sunday.", html: PanePageTests.quotingSignedLetter)
        let html = stack([signed, reply])
        let sheet = try rules(of: html)
        XCTAssertFalse(sheet.contains("bm-signature"), sheet)
        XCTAssertEqual(filters(sheet), [SignatureSheet.invert, SignatureSheet.invert])
        XCTAssertTrue(sheet.contains(".bm-html { filter: \(SignatureSheet.invert); background: #fff;"), sheet)
        let body = PanePage.content(text: nil, html: PanePageTests.signedLetter, known: ["sig-logo"])
        XCTAssertEqual(PanePage.stackBody(signed), .init(html: body, isHTML: true))
        XCTAssertTrue(html.contains("<div class=\"bm-body bm-html\">" + body + "</div>"), html)
    }

    /// No page the pane draws has a rule for the sheet: every letter of the
    /// pane's set, his own, a reply quoting it with the class kept, a sheet
    /// that has lost its style, and a plain letter whose words are the
    /// marker, alone and in one stack. Each HTML letter's page inverted by
    /// the one string, its pictures by it too, nothing else filtered; a
    /// plain letter's not at all.
    func testNoPageHasARuleForTheSheet() throws {
        let quoting = PaneLetters.letter(text: "Yes, Sunday.", html: PanePageTests.quotingSignedLetter)
        let bare = PaneLetters.letter(text: "Sam Example",
                                      html: "<p>Lunch?</p><div class=\"bm-signature\">Sam Example</div>")
        let plain = PaneLetters.letter(text: AppleMailHTML.signatureOpen + "Sam Example"
                                       + AppleMailHTML.signatureClose)
        let all = PaneLetters.all + [signed, quoting, bare, plain]
        var drawn = 0
        for (i, m) in all.enumerated() {
            guard let page = PanePage.letter(m, style: style) else { continue }
            drawn += 1
            let sheet = try rules(of: page)
            XCTAssertFalse(sheet.contains("bm-signature"), "letter \(i)")
            XCTAssertEqual(filters(sheet),
                           m.htmlBody == nil ? [] : [SignatureSheet.invert, SignatureSheet.invert], "letter \(i)")
        }
        XCTAssertGreaterThan(drawn, 15)
        let sheet = try rules(of: stack(all))
        XCTAssertFalse(sheet.contains("bm-signature"))
        XCTAssertFalse(sheet.contains("filter: none"))
        // The markup of a sheet that has lost its style, as it came.
        XCTAssertTrue(try XCTUnwrap(PanePage.letter(bare, style: style))
                        .contains("<div class=\"bm-signature\">Sam Example</div>"))
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
