import XCTest
@testable import Blackmail

/// A letter's colours in the dark pane as the comparison with Mail on the
/// test iPad saw them (B-173), with nothing on the pane moved: a light
/// letter's white a sheet in its column, with the pane's black round it.
final class LetterColoursLikeMailTests: XCTestCase {

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
}
