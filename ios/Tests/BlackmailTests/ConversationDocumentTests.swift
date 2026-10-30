import XCTest
@testable import Blackmail

/// Tests for a conversation drawn as one document.
///
/// The reading pane shows a thread as a stack of letters (B-022), and it
/// does it in a SINGLE web view rather than one per message — a column of
/// web views is the usual way and it brings the usual defect, each one
/// reporting its height a moment after the others so the text jumps while
/// he is reading. That decision moves the risk into this file: the whole
/// stack is now a string, and a message body is hostile input that ends up
/// inside an HTML document, and goes to the page's script as an argument.
final class ConversationDocumentTests: XCTestCase {

    private func entry(_ id: String, sender: String = "Jane <j@x.com>",
                       expanded: Bool = false, preview: String = "hello",
                       body: ConversationDocument.Entry.Rendered? = nil)
        -> ConversationDocument.Entry {
        ConversationDocument.Entry(
            id: id, sender: sender,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            body: body, isExpanded: expanded, preview: preview)
    }

    private func document(_ entries: [ConversationDocument.Entry]) -> String {
        ConversationDocument.html(entries: entries, inset: 20,
                                  bodyPointSize: 17, lineHeight: 1.4)
    }

    // MARK: - The stack

    func testEveryLetterGetsASection() {
        let html = document([entry("1/3"), entry("1/2"), entry("1/1")])
        for id in ["1/3", "1/2", "1/1"] {
            XCTAssertTrue(html.contains("id=\"\(ConversationDocument.sectionID(for: id))\""),
                          "missing \(id)")
        }
    }

    func testTheSectionIdIsUsableAsACSSSelector() {
        // A message id is "<uidvalidity>/<uid>" and a slash is not legal in
        // a selector; getElementById would find nothing and every body
        // would silently fail to arrive.
        let id = ConversationDocument.sectionID(for: "1/9")
        XCTAssertFalse(id.contains("/"))
        XCTAssertEqual(id, "m1_9")
    }

    func testOnlyTheExpandedLetterCarriesTheOpenClass() {
        let html = document([entry("1/2", expanded: true), entry("1/1")])
        XCTAssertTrue(html.contains("class=\"bm-letter bm-open\" id=\"m1_2\""), html)
        XCTAssertTrue(html.contains("class=\"bm-letter\" id=\"m1_1\""), html)
    }

    func testALetterWithNoBodyYetSaysSoRatherThanShowingNothing() {
        // An expanded letter whose fetch has not returned must not look
        // like a letter with nothing in it — that is exactly the failure
        // B-026 is about, and it is indistinguishable from the real thing.
        XCTAssertTrue(document([entry("1/1", expanded: true)]).contains("Loading"))
    }

    func testALoadedBodyIsPlacedInItsSection() {
        let html = document([entry("1/1", expanded: true,
                                   body: .init(html: "<p>the text</p>", isHTML: true))])
        XCTAssertTrue(html.contains("<p>the text</p>"), html)
        XCTAssertFalse(html.contains("Loading"))
    }

    // MARK: - Plain and HTML letters in one thread

    func testAnHTMLLetterIsInvertedAndAPlainOneIsNot() {
        // A conversation mixes both, and the invert trick is what makes a
        // sender's white page readable on a black one. Applied to plain
        // text — which is already light on dark — it would produce black on
        // white in the middle of the stack.
        let html = document([
            entry("1/2", expanded: true, body: .init(html: "<p>x</p>", isHTML: true)),
            entry("1/1", expanded: true, body: .init(html: "plain words", isHTML: false)),
        ])
        XCTAssertTrue(html.contains("bm-body bm-html"), html)
        XCTAssertTrue(html.contains("bm-body bm-text"), html)
    }

    func testTheInvertIsScopedToALetterAndNotTheWholeDocument() {
        // Scoped to `.bm-html`, never to `body`: a document-wide filter
        // would invert the plain letters too.
        let html = document([entry("1/1")])
        XCTAssertTrue(html.contains(".bm-html { filter: invert(1)"), html)
        XCTAssertFalse(html.contains("body { filter:"))
    }

    // MARK: - A sender cannot break the page

    func testMarkupInASenderNameIsEscaped() {
        let html = document([entry("1/1", sender: "<script>bad()</script> <j@x.com>")])
        XCTAssertFalse(html.contains("<script>bad()"), html)
        XCTAssertTrue(html.contains("&lt;script&gt;"), html)
    }

    func testMarkupInAPreviewIsEscaped() {
        let html = document([entry("1/1", preview: "a < b & c > d")])
        XCTAssertTrue(html.contains("a &lt; b &amp; c &gt; d"), html)
    }

    // MARK: - Injecting a body afterwards

    /// Bodies with everything that used to have to be escaped by hand to
    /// survive a JavaScript string literal: quotes of both kinds,
    /// backslashes, line breaks of every sort including U+2028 and U+2029,
    /// which end a line of script even inside a string, a closing
    /// `</script>`, which ends the element wherever it appears, NUL, and
    /// text outside the Basic Multilingual Plane.
    static let awkwardBodies = [
        "it's here", "\"quoted\" and 'quoted'", "a\\b\\\\c\\", "a\nb\rc\r\nd",
        "before\u{2028}after\u{2029}end", "text </script> more <script>alert(1)</script>",
        "</SCRIPT", "nul \u{0}here", "\\x3C and \\u2028 written out", "\u{1F4EE} \u{10FFFF} é",
        "${template} `backtick` \\' \\\"", "",
    ]

    /// A body goes to the page's `bmFill` as an argument, exactly as it is:
    /// nothing escaped, so nothing to get wrong, and nothing done to it on
    /// the main thread. It used to be written into the script, escaped a
    /// character at a time. Escaping it now as well would show him the
    /// backslashes.
    func testABodyGoesToTheFillAsItIs() throws {
        for html in Self.awkwardBodies {
            for isHTML in [true, false] {
                let fill = ConversationDocument.Fill(
                    sectionID: "m1_9", body: .init(html: html, isHTML: isHTML))
                let arguments = fill.arguments
                XCTAssertEqual(arguments.count, 4)
                XCTAssertEqual(arguments["scheme"] as? String, "bm-html")
                XCTAssertEqual(arguments["id"] as? String, "m1_9")
                let sent = try XCTUnwrap(arguments["html"] as? String)
                XCTAssertEqual(Array(sent.utf8), Array(html.utf8), html.debugDescription)
                XCTAssertEqual(arguments["isHTML"] as? Bool, isHTML)
            }
        }
    }

    /// What the web view is asked to run is the same few characters for
    /// every body, naming `bmFill`'s own parameters, which the stack's user
    /// script defines, in the app's world. The fourth, `scheme`, the class
    /// a body of markup takes, as Mail draws it in Dark Mode (B-169).
    func testTheFillCallsTheStacksOwnFunctionByItsArguments() {
        XCTAssertEqual(ConversationDocument.Fill.script, "bmFill(id, html, isHTML, scheme)")
        let fill = ConversationDocument.Fill(sectionID: "m1_9",
                                             body: .init(html: "x", isHTML: true))
        XCTAssertEqual(Set(fill.arguments.keys), ["id", "html", "isHTML", "scheme"])
        XCTAssertTrue(ConversationDocument.script.contains("function bmFill(id, html, isHTML, scheme) {"))
    }

    // MARK: - No script in the document

    /// The pane runs none of a page's own script, this document's
    /// included, so the document carries none: no `<script>`, and no
    /// `onclick` or any other handler written on an element, which would
    /// not run, and would leave no letter that could be opened.
    func testTheDocumentCarriesNoScriptOfItsOwn() {
        let html = document([entry("1/3", expanded: true,
                                   body: .init(html: "<p>x</p>", isHTML: true)),
                             entry("1/2"), entry("1/1")]).lowercased()
        XCTAssertFalse(html.contains("<script"), html)
        let handler = try! NSRegularExpression(pattern: #"<[^>]*\son[a-z]+\s*="#)
        XCTAssertNil(handler.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), html)
    }

    /// The stack's script wires each letter's line with `addEventListener`:
    /// the lines that are the body's own, found as the document ends, so a
    /// line a letter draws in its markup, put in later by `bmFill`, is never
    /// wired; and on a single letter's page, the one with `#bm`, none at
    /// all. A tap toggles the letter's section, as the line's `onclick`
    /// did, and tells the pane which letter and whether it opened, as that
    /// did, through `bmLetter`.
    func testTheStacksScriptWiresEachLineAndTellsThePane() {
        let script = ConversationDocument.script
        for wiring in [
            "if (document.getElementById('bm')) return;",
            "document.querySelectorAll('body > .bm-letter > .bm-head')",
            "addEventListener('click', function (event) {",
            "bmToggle(event.currentTarget.parentNode);",
            "var opening = !section.classList.contains('bm-open');",
            "section.classList.toggle('bm-open');",
            "window.webkit.messageHandlers.bmLetter.postMessage({ id: section.id, open: opening });",
            "body.className = 'bm-body ' + (isHTML ? bmScheme(scheme) : 'bm-text');",
            "body.innerHTML = html;",
        ] {
            XCTAssertTrue(script.contains(wiring), wiring)
        }
        XCTAssertFalse(script.contains("onclick"))
        // Every line of the stack is a direct child's of the body, and so
        // is found: each section sits at the top level of the document,
        // which has no `#bm`. A letter's own page has one.
        let html = document([entry("1/2"), entry("1/1")])
        XCTAssertTrue(html.contains("<body>\n<div class=\"bm-letter\" id=\"m1_2\">\n  <div class=\"bm-head\">"),
                      html)
        XCTAssertFalse(html.contains("id=\"bm\""))
        let page = PanePage.letter(Message(id: "7/3", mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                                           senderAddress: "sam@example.com", to: [], cc: [], subject: "x",
                                           date: Date(timeIntervalSince1970: 1_790_000_000), textBody: nil,
                                           htmlBody: "<p>Hi</p>", attachments: []),
                                   style: .init(inset: 26, bodyPointSize: 17, lineHeight: 1.41))
        XCTAssertTrue(page?.contains("<div id=\"bm\">") == true)
    }

    // MARK: - Mail's bars beside quoted text (B-101)

    /// The stack has Mail's rules for its letters' quotes, as a letter's own
    /// page has them (`PanePageTests`), each under `.bm-html`, a letter's
    /// HTML, in the colours the invert turns into Mail's dark ones, with
    /// the "wrote:" line's (B-180); and under `.bm-text`, a plain
    /// letter's, in its dark ones (B-147); never the stack's own lines.
    /// After the rule for the HTML's pictures and the signature's grey
    /// sheet (B-146, B-173).
    func testTheStackHasMailsBarsBesideAnHTMLLettersQuotes() throws {
        let quote = ":is(blockquote[type=cite i], blockquote[class~=gmail_quote])"
        func rule(_ selector: String, _ colour: String) -> String {
            "\(selector) { padding-left: 5px !important; margin: 0 !important; "
                + "border-left: 1px solid \(colour) !important; color: \(colour) !important; }"
        }
        let rules = [
            rule(".bm-html \(quote)", "rgb(201, 100, 252)"),
            rule(".bm-html \(quote) \(quote)", "rgb(0, 144, 230)"),
            rule(".bm-html \(quote) \(quote) \(quote)", "rgb(0, 111, 25)"),
        ].joined(separator: "\n")
        XCTAssertEqual(QuoteBars.css(in: ".bm-html", palette: QuoteBars.inverted), rules)
        // The line before a quote, one rule a level, in the colour of the
        // quote after it (B-180, fixed again).
        let line = [(".bm-html .bm-attribution", "rgb(201, 100, 252)"),
                    (".bm-html \(quote) .bm-attribution", "rgb(0, 144, 230)"),
                    (".bm-html \(quote) \(quote) .bm-attribution", "rgb(0, 111, 25)")].map {
            "\($0.0) { padding-left: 5px !important; "
                + "border-left: 1px solid \($0.1) !important; color: \($0.1) !important; }"
        }.joined(separator: "\n")

        let html = document([entry("1/2", expanded: true, body: .init(html: "<p>x</p>", isHTML: true)),
                             entry("1/1", expanded: true, body: .init(html: "> words", isHTML: false))])
        let sheet = try XCTUnwrap(html.components(separatedBy: "</style>").first)
        XCTAssertTrue(sheet.contains("""
                     filter: \(SignatureSheet.invert); }
          /* A signature's white sheet is inverted with the rest of its
             letter (B-146), grey under the invert so it is Mail's grey
             sheet, its logo showing on it, its white borders lost in it
             (SignatureSheet, B-173). */
          \(SignatureSheet.css(in: ".bm-html"))
          /* Mail's bars beside quoted text (B-101): a letter's HTML in the
             light colours the invert turns into Mail's dark ones, as Mail's
             HTML letter has them in Dark Mode (QuoteBars.inverted, B-180),
             and the line before a quote ending "wrote:" with the bar and
             colour of the quote after it; a plain letter's quotes, Mail's
             blockquotes too (PlainQuotes, B-147), in its dark ones, as a
             plain letter is not inverted. */
        \(rules)
        \(line)
        \(QuoteBars.css(in: ".bm-text", palette: QuoteBars.dark))
          .bm-body img, .bm-body table {
        """), sheet)
        // Four sets since B-169: the HTML inverted, the text, and the HTML
        // drawn light and in its own colours (`DarkLikeMailTests`); the
        // line's rules for the three HTML sets, a quote at its second
        // level and two at its third.
        XCTAssertEqual(sheet.components(separatedBy: "blockquote[").count - 1, 4 * (2 + 4 + 6) + 3 * (2 + 4))
        XCTAssertEqual(sheet.components(separatedBy: ".bm-html :is(").count - 1, 3 + 2)
        XCTAssertEqual(sheet.components(separatedBy: ".bm-text :is(").count - 1, 3)
        XCTAssertFalse(sheet.contains("#bm"), "the letter's own page's scope")
    }

    /// One rule for a signature's white sheet, its colour (B-173): the
    /// sheet is inverted with the rest of its letter (B-146), and is grey
    /// under the invert where it declares its white, its white borders
    /// too, so it is Mail's grey sheet. Until B-146 the stack
    /// inverted it back, white with black words, since its first version
    /// (B-130 gave a letter on its own the same rules); no filter for it.
    func testTheStackHasOneRuleForASignaturesSheetItsColour() throws {
        let html = document([entry("1/1")])
        let sheet = try XCTUnwrap(html.components(separatedBy: "</style>").first)
        XCTAssertEqual(sheet.components(separatedBy: "bm-signature").count - 1, 4, sheet)
        XCTAssertEqual(SignatureSheet.css(in: ".bm-html"),
                       ".bm-html .bm-signature[style*=\"background-color: #ffffff\"], "
                       + ".bm-html .bm-signature[style*=\"background-color: rgb(255, 255, 255)\"], "
                       + ".bm-html .bm-signature table[style^=\"color: rgb(0, 0, 0); background-color: rgb(255, 255, 255); \"] "
                       + "{ background-color: rgb(204, 204, 204) !important; } "
                       + ".bm-html .bm-signature [style*=\"solid rgb(255, 255, 255)\"] "
                       + "{ border-color: rgb(204, 204, 204) !important; }")
        XCTAssertTrue(sheet.contains("\n  " + SignatureSheet.css(in: ".bm-html") + "\n"), sheet)
        XCTAssertFalse(sheet.contains("filter: none"), sheet)
    }

    /// Every filter in the stack's style is the one invert, the string a
    /// letter on its own is inverted by too (`SignatureSheet.invert`): the
    /// letter's HTML and its pictures, nothing else.
    func testEveryFilterInTheStackIsTheOneInvert() throws {
        let html = document([entry("1/1")])
        let sheet = try XCTUnwrap(html.components(separatedBy: "</style>").first)
        XCTAssertTrue(sheet.contains(".bm-html { filter: \(SignatureSheet.invert); background: #fff;"), sheet)
        let filters = sheet.components(separatedBy: "filter:").dropFirst()
            .map { String($0.prefix(while: { $0 != ";" })).trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(filters, [SignatureSheet.invert, SignatureSheet.invert])
    }

    /// Mail's reply and Gmail's go into their sections as they came, at
    /// first draw and by `bmFill`: the bars are rules in the style.
    func testARepliesMarkupGoesIntoTheStackAsItCame() throws {
        for body in [PanePageTests.appleMailReplyBody, PanePageTests.gmailReply] {
            let rendered = ConversationDocument.Entry.Rendered(html: body, isHTML: true)
            let html = document([entry("1/1", expanded: true, body: rendered)])
            XCTAssertTrue(html.contains("<div class=\"bm-body bm-html\">\(body)</div>"), html)
            let fill = ConversationDocument.Fill(sectionID: "m1_1", body: rendered)
            XCTAssertEqual(try XCTUnwrap(fill.arguments["html"] as? String), body)
        }
    }

    // MARK: - The document is well formed

    func testEveryLetterIsClosedAndTheCountsBalance() {
        let html = document([entry("1/3"), entry("1/2"), entry("1/1")])
        let opens = html.components(separatedBy: "<div class=\"bm-letter").count - 1
        XCTAssertEqual(opens, 3)
        XCTAssertTrue(html.hasSuffix("</body></html>"), String(html.suffix(40)))
    }

    func testAnEmptyConversationStillProducesAValidDocument() {
        let html = document([])
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.hasSuffix("</body></html>"))
    }
}
