import XCTest
@testable import Blackmail

/// A letter's colours in the dark pane as the comparison with Mail on the
/// test iPad saw them (B-173), with nothing on the pane moved: a light
/// letter's white a sheet in its column, with the pane's black round it;
/// and Mail's line over a letter whose pictures from the web are held back
/// in Mail's colours, whatever the letter. His signature's grey sheet is
/// `SignatureLikeMailTests`'.
final class LetterColoursLikeMailTests: XCTestCase {

    /// What the pane's invert, `invert(1) hue-rotate(180deg)`, makes of
    /// the colour `rgb`, by CSS's definitions of the two, in sRGB, each
    /// channel kept between 0 and 1, rounded to a byte.
    static func inverted(_ rgb: (Int, Int, Int)) -> [Int] {
        let turn: [[Double]] = [[-0.574, 1.430, 0.144], [0.426, 0.430, 0.144], [0.426, 1.430, -0.856]]
        let x = [rgb.0, rgb.1, rgb.2].map { 1 - Double($0) / 255 }
        return turn.map { row in
            Int((min(1, max(0, zip(row, x).map(*).reduce(0, +))) * 255).rounded())
        }
    }

    private let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)

    private func letter(_ html: String?, text: String? = nil, id: String = "7/3") -> Message {
        Message(id: id, mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                senderAddress: "sam@example.com", to: ["me@example.com"], cc: [],
                subject: "The garden", date: Date(timeIntervalSince1970: 1_790_000_000),
                textBody: text, htmlBody: html, attachments: [])
    }

    /// The style of a page: everything before its `</style>`.
    private func rules(of page: String) throws -> String {
        try XCTUnwrap(page.components(separatedBy: "</style>").first)
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

    /// A light letter's white stops at its column, as Mail's sheet does: on
    /// its own page, `#bm`'s white is clipped to its content, so its margin,
    /// the pane's inset, is the pane's black; the margin is as it was, so
    /// the words are where they were. In a stack, a light body's the same,
    /// its padding as it was. An inverted letter's white is not clipped,
    /// as the invert makes all of it the pane's black; a letter in its own
    /// colours, and a plain one, have no white.
    func testALightLettersWhiteStopsAtItsColumn() throws {
        let web = letter(DarkLikeMailTests.withAWebPicture)
        XCTAssertEqual(LetterScheme.of(html: web.htmlBody!), .light)
        let page = try rules(of: XCTUnwrap(PanePage.letter(web, style: style)))
        XCTAssertTrue(page.contains("  #bm { padding: 26px;\n"), page)
        XCTAssertTrue(page.contains("#bm { background: #fff; background-clip: content-box; color-scheme: light only; }"),
                      page)
        XCTAssertEqual(page.components(separatedBy: "background-clip").count - 1, 1)

        let plainHTML = letter("<p>Hi</p>")
        let own = letter(DarkLikeMailTests.darkReady)
        let plain = letter(nil, text: "Hi")
        for m in [plainHTML, own, plain] {
            let sheet = try rules(of: XCTUnwrap(PanePage.letter(m, style: style)))
            XCTAssertFalse(sheet.contains("background-clip"), m.htmlBody ?? "plain")
        }
        XCTAssertTrue(try rules(of: XCTUnwrap(PanePage.letter(plainHTML, style: style)))
                        .contains("#bm { filter: \(SignatureSheet.invert); background: #fff; }"))

        let sheet = try rules(of: stack([web, plainHTML, own, plain]))
        XCTAssertTrue(sheet.contains(
            ".bm-light { background: #fff; background-clip: content-box; color: #000; color-scheme: light only; }"),
                      sheet)
        XCTAssertTrue(sheet.contains(".bm-body { padding: 0 26px 26px 26px;"), sheet)
        XCTAssertTrue(sheet.contains(".bm-html { filter: \(SignatureSheet.invert); background: #fff;\n"), sheet)
        XCTAssertEqual(sheet.components(separatedBy: "background-clip").count - 1, 1)
    }

    /// Mail's line in Mail's colours whatever the letter (B-173): white
    /// words and its blue on the pane's black, the rule the stack's. On a
    /// letter drawn light or in its own colours, not inverted, Mail's own,
    /// by the head's rule; on one inverted, the colours the invert turns
    /// to Mail's, written on the line and by the head's rule: white for
    /// black, black for white, the rule's grey, and the nearest blue the
    /// invert gives. The line's place and shape as they were: the page's
    /// first thing, one line, its button at the right, a rule under it.
    func testMailsLineIsInMailsColoursWhateverTheLetter() throws {
        XCTAssertEqual(RemoteContent.mail, .init(words: "#fff", button: "#0A84FF", rule: "#38383a", ground: "#000"))
        XCTAssertEqual(RemoteContent.underInvert,
                       .init(words: "#000", button: "#1597FF", rule: "#c7c7c5", ground: "#fff"))
        XCTAssertEqual(Self.inverted((0x00, 0x00, 0x00)), [255, 255, 255])
        XCTAssertEqual(Self.inverted((0xff, 0xff, 0xff)), [0, 0, 0])
        XCTAssertEqual(Self.inverted((0xc7, 0xc7, 0xc5)), [56, 56, 54])
        XCTAssertEqual(Self.inverted((0x15, 0x97, 0xff)), [14, 144, 248])

        let line = RemoteContent.line(for: "7/3")
        XCTAssertEqual(line, "<div class=\"bm-unloaded\" style=\"display: flex; align-items: baseline; gap: 12px; "
                       + "margin: 0 0 1em 0; padding: 0 0 10px 0; border-bottom: 0.5px solid #c7c7c5; "
                       + "background-color: #fff; white-space: normal;\">"
                       + "<span style=\"flex: 1 1 auto; color: #000;\">Message contains unloaded images.</span>"
                       + "<a href=\"bmimages:?letter=7/3\" style=\"flex: 0 0 auto; color: #1597FF; "
                       + "text-decoration: none;\">Load All Images</a></div>")
        XCTAssertEqual(RemoteContent.colourRule(in: "#bm", inverted: false),
                       "#bm .bm-unloaded { background-color: #000 !important; border-bottom-color: #38383a !important; } "
                       + "#bm .bm-unloaded span { color: #fff !important; } "
                       + "#bm .bm-unloaded a { color: #0A84FF !important; }")
        XCTAssertEqual(RemoteContent.colourRule(in: ".bm-html", inverted: true),
                       ".bm-html .bm-unloaded { background-color: #fff !important; "
                       + "border-bottom-color: #c7c7c5 !important; } "
                       + ".bm-html .bm-unloaded span { color: #000 !important; } "
                       + ".bm-html .bm-unloaded a { color: #1597FF !important; }")

        let inverted = letter("<link rel=\"stylesheet\" href=\"https://example.com/a.css\"><p>Hi</p>")
        let light = letter(DarkLikeMailTests.withAWebPicture)
        let own = letter(DarkLikeMailTests.darkReady)
        for (m, scheme) in [(inverted, LetterScheme.inverted), (light, .light), (own, .own)] {
            XCTAssertEqual(LetterScheme.of(html: m.htmlBody!), scheme)
            let page = try XCTUnwrap(PanePage.letter(m, style: style, heldBack: true))
            let sheet = try rules(of: page)
            XCTAssertTrue(page.contains("<div id=\"bm\">" + line), "\(scheme)")
            XCTAssertTrue(sheet.contains("\n  " + RemoteContent.colourRule(in: "#bm", inverted: scheme == .inverted)
                                         + "\n"), sheet)
            XCTAssertFalse(sheet.contains(RemoteContent.colourRule(in: "#bm", inverted: scheme != .inverted)),
                           "\(scheme)")
            XCTAssertEqual(sheet.components(separatedBy: ".bm-unloaded span").count - 1, 1, "\(scheme)")
            // Not held back, no line and no rule for it: the page as it was.
            XCTAssertFalse(try XCTUnwrap(PanePage.letter(m, style: style)).contains("bm-unloaded"), "\(scheme)")
        }

        let sheet = try rules(of: stack([inverted, light, own]))
        for (scope, under) in [(".bm-html", true), (".bm-light", false), (".bm-own", false)] {
            XCTAssertTrue(sheet.contains("\n  " + RemoteContent.colourRule(in: scope, inverted: under) + "\n"), scope)
        }
        XCTAssertEqual(sheet.components(separatedBy: ".bm-unloaded span").count - 1, 3)
        XCTAssertTrue(PanePage.stackBody(inverted, heldBack: "7/3").html.hasPrefix(line))
    }
}
