import XCTest
@testable import Blackmail

/// A printed letter's page (`PrintPage`, B-110): light, black on white, its
/// header as Mail prints it, labelled lines with the date in Mail's form
/// (B-172), then its body as the pane shows it, cut to a limit.
///
/// The pane's own page is dark, plain text white on black and HTML under an
/// invert, which prints as it is drawn, white on black, since a build
/// stamped before iOS 16.4 prints backgrounds (the test iPad, 2026-10-23),
/// or white on white with them off. So the page printed is a page of its
/// own, and the body in it is checked here against the pane's, byte for
/// byte.
final class PrintPageTests: XCTestCase {

    private let style = PrintPage.Style(senderPointSize: 17, metaPointSize: 15, subjectPointSize: 17,
                                        bodyPointSize: 17, lineHeight: 1.41)
    private let posix = Locale(identifier: "en_US_POSIX")
    private let utc = TimeZone(identifier: "UTC")!
    /// A size in words that says which number it was given.
    private let size: (Int64) -> String = { "\($0) bytes" }
    /// The date of `letter`, 2026-09-21 14:13:20 UTC, as Mail prints it.
    private var printed: String {
        MailFormat.printedTimestamp(Date(timeIntervalSince1970: 1_790_000_000), locale: posix, timeZone: utc)
    }
    /// `letter`'s header in words.
    private var headInWords: String {
        "From: Sam Example sam@example.com\nSubject: The garden\nDate: \(printed)\n"
            + "To: Jane Example jane@example.com, sam@example.com"
    }

    private func page(_ m: Message) -> String {
        PrintPage.letter(m, style: style, size: size, locale: posix, timeZone: utc)
    }

    /// The page's style sheet, up to its end.
    private func sheet(_ page: String) throws -> String {
        try XCTUnwrap(page.components(separatedBy: "</style>").first)
    }

    /// What the page has in `#bm`, the letter's body.
    private func body(_ page: String) throws -> String {
        let start = try XCTUnwrap(page.range(of: "<div id=\"bm\">"))
        let end = try XCTUnwrap(page.range(of: "</div></body></html>", options: .backwards))
        return String(page[start.upperBound..<end.lowerBound])
    }

    /// What the page has in `#bm-head`, the letter's header.
    private func head(_ page: String) throws -> String {
        let start = try XCTUnwrap(page.range(of: "<div id=\"bm-head\">"))
        let end = try XCTUnwrap(page.range(of: "</div><div id=\"bm\">"))
        return String(page[start.upperBound..<end.lowerBound])
    }

    private func letter(sender: String = "Sam Example <sam@example.com>",
                        to: [String] = ["Jane Example <jane@example.com>", "sam@example.com"],
                        cc: [String] = [], subject: String = "The garden",
                        date: Date = Date(timeIntervalSince1970: 1_790_000_000),
                        text: String? = "Hello.", html: String? = nil,
                        attachments: [Attachment] = []) -> Message {
        Message(id: "7/3", mailboxID: "INBOX", sender: sender, senderAddress: "sam@example.com",
                to: to, cc: cc, subject: subject, date: date, textBody: text, htmlBody: html,
                attachments: attachments)
    }

    private let files = [
        Attachment(id: "2", filename: "plan.pdf", mimeType: "application/pdf", size: 2_048),
        Attachment(id: "3", filename: "notes.txt", mimeType: "text/plain", size: nil),
        // A picture the body shows: no line, as it has no row in the pane.
        Attachment(id: "4", filename: "logo.png", mimeType: "image/png", size: 900,
                   contentID: "logo@example.com", isInline: true),
        // A PDF sent inline, as Apple Mail sends one: a file (B-101).
        Attachment(id: "5", filename: "scan.pdf", mimeType: "application/pdf", size: 10,
                   isInline: true),
    ]

    // MARK: - Light

    /// Light, for plain and HTML letters alike: no invert of any kind, no
    /// black page, white with black words, light only, and a long line
    /// wrapped as the pane wraps it. None of the pane's dark rules.
    func testThePageIsLight() throws {
        for (i, m) in PaneLetters.all.enumerated() {
            let page = self.page(m)
            let sheet = try self.sheet(page)
            for dark in ["filter", "invert", "hue-rotate", "background: #000", "#0A84FF", "color: #fff"] {
                XCTAssertFalse(sheet.contains(dark), "letter \(i): \(dark)")
            }
            XCTAssertTrue(page.hasPrefix("<!DOCTYPE html><html><head><meta charset=\"utf-8\">\n"
                                         + "<meta name=\"color-scheme\" content=\"light only\">\n"), "letter \(i)")
            XCTAssertTrue(sheet.contains("html, body { margin: 0; padding: 0; background: #fff; color: #000; }"),
                          "letter \(i)")
            XCTAssertTrue(sheet.contains("color: #000; word-wrap: break-word;"), "letter \(i)")
            XCTAssertTrue(sheet.contains("img, table { max-width: 100% !important; height: auto; }"))
            XCTAssertTrue(sheet.contains("a { color: #007AFF; }"))
            if let pane = PanePage.letter(m, style: .init(inset: 26, bodyPointSize: 17, lineHeight: 1.41)) {
                XCTAssertTrue(pane.contains("background: #000;"), "the pane's page is the dark one")
                XCTAssertFalse(page.contains(try self.sheet(pane)), "letter \(i)")
            }
        }
    }

    /// The pane's sizes: the header's lines at the pane's lines' size,
    /// Mail's lines all one size since B-172, and the body's at its line
    /// height; the sender's and the subject's sizes not used on paper.
    func testThePageIsInThePanesSizes() throws {
        let big = PrintPage.Style(senderPointSize: 21, metaPointSize: 19, subjectPointSize: 22,
                                  bodyPointSize: 23, lineHeight: 1.5)
        let sheet = try self.sheet(PrintPage.letter(letter(), style: big, size: size))
        for rule in ["font: 19px -apple-system, sans-serif;", "font: 23px -apple-system, sans-serif;",
                     "line-height: 1.5;"] {
            XCTAssertTrue(sheet.contains(rule), rule)
        }
        for unused in ["21px", "22px"] { XCTAssertFalse(sheet.contains(unused), unused) }
        XCTAssertTrue(sheet.contains("#bm-head { break-inside: avoid;"), "the header is never split")
        XCTAssertTrue(sheet.contains("border-top: 0.5px solid #c8c8c8;"), "the rule, light")
        XCTAssertTrue(sheet.contains("color: #8e8e8e;"), "the lines, grey")
    }

    /// The header's lines and the page's notices print grey, as drawn: the
    /// header's rule and each notice's block print in their own colours
    /// (`exact`), and nothing else on the page does, so the sender's words
    /// are still WebKit's to make legible on white. With no backgrounds
    /// printed (`LetterPrint`), WebKit changes any text under 4.5:1 on
    /// white, and on iPadOS 16.5 and 18 lightens one of luminance 0.5 or
    /// less: the lines' `#8e8e8e` would print `#e2e2e2`, all but white.
    /// Mail's printed header, drawn by UIKit, keeps its greys. The pane's
    /// own line and page are as they were, with none of it.
    func testTheHeaderAndTheNoticesPrintInTheirOwnGreys() throws {
        let exact = "-webkit-print-color-adjust: exact;"
        let block = "<div style=\"\(exact)\">"
        func count(_ text: String) -> Int { text.components(separatedBy: "print-color-adjust").count - 1 }
        for (i, m) in (PaneLetters.all + [letter(text: nil)]).enumerated() {
            let page = self.page(m)
            let sheet = try self.sheet(page)
            let head = try XCTUnwrap(sheet.range(of: "#bm-head {"), "letter \(i)")
            let rule = sheet[head.lowerBound...].prefix(while: { $0 != "}" })
            XCTAssertTrue(rule.contains(exact), "letter \(i): \(rule)")
            XCTAssertEqual(count(sheet), 1, "letter \(i): the header's rule only")
            let empty = MailText.hasNoVisibleContent(text: m.textBody, html: m.htmlBody)
            XCTAssertEqual(count(try body(page)), empty ? 1 : 0, "letter \(i): a notice of ours alone")
            if let pane = PanePage.letter(m, style: .init(inset: 26, bodyPointSize: 17, lineHeight: 1.41)) {
                XCTAssertEqual(count(pane), 0, "letter \(i)")
            }
        }
        for notice in [PrintPage.empty, PrintPage.shortened] {
            XCTAssertTrue(notice.hasPrefix(block + "<p style=\"color: #8e8e"), notice)
            XCTAssertTrue(notice.hasSuffix("</p></div>"), notice)
            XCTAssertEqual(count(notice), 1, notice)
        }
        XCTAssertEqual(PrintPage.shortened, block + PanePage.shortenedLine + "</div>")
        XCTAssertEqual(count(PanePage.shortenedLine), 0)
        var cut = letter(text: "The beginning.")
        cut.isShortened = true
        let printed = try body(page(cut))
        XCTAssertTrue(printed.hasPrefix(block + PanePage.shortenedLine + "</div>The beginning."), printed)
        XCTAssertEqual(count(printed), 1)
    }

    // MARK: - The header

    /// Mail's lines in Mail's order (B-172): From, Subject, Date, To, and
    /// Cc after To; each label grey, set to the right, in a cell of its
    /// own; each name black with its address grey after it, a person with
    /// no name the address alone; one rule under them. No file, as the
    /// pane's header has none (B-170): each is in the body. A line each for
    /// the letter in words, a file's size or its name alone, and none for a
    /// picture the body shows.
    func testTheHeaderIsMailsLabelledLines() throws {
        let m = letter(cc: ["\"Carlo Rossi\" <carlo@example.com>"], attachments: files)
        func row(_ label: String, _ value: String) -> String {
            "<tr><td class=\"bm-label\">\(label)</td><td class=\"bm-value\">\(value)</td></tr>"
        }
        func person(_ name: String, _ address: String) -> String {
            "<span class=\"bm-name\">\(name)</span> <span class=\"bm-address\">\(address)</span>"
        }
        XCTAssertEqual(try head(page(m)),
                       "<table>"
                       + row("From:", person("Sam Example", "sam@example.com"))
                       + row("Subject:", "The garden")
                       + row("Date:", printed)
                       + row("To:", person("Jane Example", "jane@example.com") + ", "
                             + "<span class=\"bm-name\">sam@example.com</span>")
                       + row("Cc:", person("Carlo Rossi", "carlo@example.com"))
                       + "</table><div class=\"bm-rule\"></div>")
        XCTAssertEqual(PrintPage.head(m, size: size, locale: posix, timeZone: utc),
                       .init(from: .init(name: "Sam Example", address: "sam@example.com"),
                             subject: "The garden", date: printed,
                             to: [.init(name: "Jane Example", address: "jane@example.com"),
                                  .init(name: "sam@example.com", address: nil)],
                             cc: [.init(name: "Carlo Rossi", address: "carlo@example.com")],
                             files: ["plan.pdf (2048 bytes)", "notes.txt", "scan.pdf (10 bytes)"]))
        let sheet = try self.sheet(page(m))
        for rule in [".bm-label { color: #8e8e8e; text-align: right;", ".bm-value { color: #000; text-align: left;",
                     ".bm-address { color: #8e8e8e; }"] {
            XCTAssertTrue(sheet.contains(rule), rule)
        }
    }

    /// The header's table in the same document as the sender's markup,
    /// whose own `<style>` in the body still applies on paper: a letter
    /// that boxes every `td`, stretches every `table`, or, with
    /// `!important`, sets each `td` as a block, does not reach the header's
    /// lines, which print as they do with no such style. Each property such
    /// a rule could change is the header's own, `!important`, on its
    /// table, its rows and its cells; with no such style nothing changes.
    func testTheHeaderKeepsItsLinesUnderTheSendersTableStyles() throws {
        let html = "<style>td { border: 1px solid #ccc; background: #eee; } table { width: 100%; }"
            + " @media (max-width: 600px) { td { display: block !important; } }</style>"
            + "<table><tr><td>Hello.</td></tr></table>"
        let page = self.page(letter(text: nil, html: html))
        let sheet = try self.sheet(page)
        XCTAssertTrue(try body(page).contains("td { display: block !important; }"), "the sender's style is there")
        func rule(_ selector: String) throws -> Substring {
            let at = try XCTUnwrap(sheet.range(of: selector + " {"), selector)
            return sheet[at.upperBound...].prefix(while: { $0 != "}" })
        }
        let shields: [(String, [String])] = [
            ("#bm-head table", ["border: 0 !important;", "background: none !important;",
                                "width: auto !important;", "display: table !important;",
                                "border-collapse: collapse !important;", "border-spacing: 0 !important;",
                                "margin: 0 !important;"]),
            ("#bm-head tr", ["border: 0 !important;", "background: none !important;",
                             "display: table-row !important;"]),
            ("#bm-head td", ["border: 0 !important;", "background: none !important;",
                             "width: auto !important;", "display: table-cell !important;"]),
        ]
        for (selector, declarations) in shields {
            let declared = try rule(selector)
            for declaration in declarations {
                XCTAssertTrue(declared.contains(declaration), "\(selector): \(declaration) in \(declared)")
            }
        }
    }

    /// No To line with nobody in To, where the paper said "To: me"; no Cc
    /// line with no Cc; "(no subject)", as the pane says; one rule.
    func testTheHeaderSaysWhatThePaneSaysOfNothing() throws {
        let head = try self.head(page(letter(to: [], subject: "")))
        XCTAssertFalse(head.contains("To:"), head)
        XCTAssertFalse(head.contains("Cc:"), head)
        XCTAssertTrue(head.contains("<td class=\"bm-value\">(no subject)</td>"), head)
        XCTAssertEqual(head.components(separatedBy: "<div class=\"bm-rule\"></div>").count - 1, 1)
    }

    /// The date in Mail's form, the medium date and the medium time with
    /// its seconds, for a letter of today, one of yesterday and one of last
    /// year alike, never "Today" or "Yesterday": the paper is read on
    /// another day. On screen the pane's words are as they were.
    func testTheDateIsMailsPrintedForm() throws {
        let now = Date()
        let day: TimeInterval = 86_400
        for date in [now.addingTimeInterval(-60), now.addingTimeInterval(-day),
                     now.addingTimeInterval(-3 * day), now.addingTimeInterval(-400 * day)] {
            let form = MailFormat.printedTimestamp(date, locale: posix, timeZone: utc)
            XCTAssertEqual(PrintPage.head(letter(date: date), size: size, locale: posix, timeZone: utc).date,
                           form)
            XCTAssertTrue(try head(page(letter(date: date))).contains(">\(form)<"))
            XCTAssertFalse(form.contains("Today") || form.contains("Yesterday"), form)
            XCTAssertTrue(PrintPage.words(letter(date: date), size: size, locale: posix, timeZone: utc)
                            .contains("\nDate: \(form)\n"))
        }
        XCTAssertTrue(printed.hasPrefix("Sep 21, 2026"), printed)
        XCTAssertTrue(printed.contains("2:13:20"), printed)
        // On screen, as it was: today's and yesterday's relative, and the
        // rest the pane's long form.
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        func onScreen(_ date: Date) -> String {
            MailFormat.detailTimestamp(date, now: at, locale: posix, timeZone: utc)
        }
        XCTAssertEqual(onScreen(at), "Today at 2:13\u{202F}PM")
        XCTAssertEqual(onScreen(at.addingTimeInterval(-day)), "Yesterday at 2:13\u{202F}PM")
        for back in [3.0, 8.0, 400.0] {
            let date = at.addingTimeInterval(-back * day)
            XCTAssertEqual(onScreen(date), MailFormat.fullTimestamp(date, locale: posix, timeZone: utc))
        }
        XCTAssertEqual(MailFormat.fullTimestamp(at, locale: posix, timeZone: utc),
                       "September 21, 2026 at 2:13\u{202F}PM")
    }

    /// Every value of the header escaped, as text: a sender with an
    /// ampersand and an address, a subject with a script in it; and a
    /// file whose name has `&` and `<`, in the body from B-170 and on
    /// neither since B-185. The only attributes in the header are its own
    /// classes, and the page has no script of its own.
    func testTheHeaderIsEscaped() throws {
        let m = letter(sender: "Smith & Sons <x@y>", to: ["\"A <b>\" <a@b.example>"],
                       subject: "<script>alert(1)</script> & more",
                       attachments: [Attachment(id: "2", filename: "a & b <c>.pdf",
                                                mimeType: "application/pdf", size: 5)])
        let page = self.page(m)
        let head = try self.head(page)
        XCTAssertTrue(head.contains("<span class=\"bm-name\">Smith &amp; Sons</span>"), head)
        XCTAssertTrue(head.contains(">&lt;script&gt;alert(1)&lt;/script&gt; &amp; more<"), head)
        XCTAssertFalse(head.contains(".pdf"), head)
        XCTAssertFalse(try body(page).contains(".pdf"), page)
        XCTAssertFalse(page.contains("<script"), page)
        let classes = head.components(separatedBy: " class=\"bm-").count - 1
        XCTAssertEqual(classes, 4 + 2 + 2 + 4 + 1, "From's four, Subject's two, Date's two, To's four, the rule")
        XCTAssertEqual(head.components(separatedBy: "=").count - 1, classes, "no attribute but the class")
    }

    // MARK: - The body

    /// For every letter, the body is the pane's, byte for byte
    /// (`PanePage.content`), its pictures but for their decoding
    /// (`decodedAtOnce`), or the pane's words for a letter with nothing in
    /// it; plain text keeps its lines, and HTML does not. The pane's own
    /// page is as it was, with no `decoding` of ours.
    func testTheBodyIsThePanesByteForByte() throws {
        for (i, m) in PaneLetters.all.enumerated() {
            let page = self.page(m)
            let printed = try body(page)
            if MailText.hasNoVisibleContent(text: m.textBody, html: m.htmlBody) {
                XCTAssertEqual(printed, PrintPage.empty, "letter \(i)")
                continue
            }
            let content = PanePage.content(text: m.textBody, html: m.htmlBody,
                                           known: PanePage.contentIDs(of: m), flowed: m.textIsFlowed)
            XCTAssertEqual(Array(printed.utf8), Array(PrintPage.decodedAtOnce(content).utf8), "letter \(i)")
            if !content.lowercased().contains("<img") {
                XCTAssertEqual(Array(printed.utf8), Array(content.utf8), "letter \(i)")
            }
            // And the same as the pane's page has in its #bm.
            let pane = try XCTUnwrap(PanePage.letter(m, style: .init(inset: 26, bodyPointSize: 17,
                                                                      lineHeight: 1.41)))
            XCTAssertEqual(try body(pane), content, "letter \(i)")
            XCTAssertFalse(pane.contains("decoding"), "letter \(i)")
            XCTAssertEqual(try sheet(page).contains("white-space: pre-wrap;"), m.htmlBody == nil, "letter \(i)")
        }
    }

    /// The letter's pictures by `cid:` pointed at the loader, the known
    /// ones only; plain text escaped with its leading blank lines gone.
    func testThePicturesAndTheTextAreThePanes() throws {
        let letters = PaneLetters.all
        let pictured = try body(page(letters[5]))
        XCTAssertTrue(pictured.contains("<img decoding=sync src=\"bmcid://logo%40example.com\">"), pictured)
        XCTAssertTrue(pictured.contains("<img decoding=sync src='cid:gone'>"), pictured)
        let text = try body(page(letters[10]))
        XCTAssertTrue(text.hasPrefix("Dear Sam,\n\nIt's &lt;b>not&lt;/b> bold &amp;"), text)
    }

    /// Every picture of the printed page decoded as it is drawn: each
    /// `<img>` of every letter's page has `decoding=sync` first, so the page
    /// is never drawn into the PDF with a picture half decoded, as a kept
    /// letter's photo was printed blank on the test iPad, 2026-10-23. Seen
    /// whole: a picture by `cid:`, one in capitals, one whose sender asked
    /// for `decoding="async"` (the first of two attributes is the one HTML
    /// keeps), `<img/`, a line break after the name, `<img>`, `<image`,
    /// which HTML reads as `<img`, and an `<img` inside an alt text, which
    /// gains words and no quote; `<imgx`, `</img>` and an `<img` with no end
    /// left alone; and the letters around it, of two and four bytes, whole.
    func testEveryPictureOfThePrintedPageIsDecodedAsItIsDrawn() throws {
        let html = "é<p><img src=\"cid:logo@example.com\"> <IMG SRC=x.png><img decoding=\"async\" src=y>"
            + "<img/src=z><img\nsrc=w><img><Image src=v><img alt=\"an <img in it\" src=u>"
            + "<imgx src=t></img><p>img \u{1F4EE}<img"
        let decoded = PrintPage.decodedAtOnce(html)
        XCTAssertEqual(decoded,
                       "é<p><img decoding=sync src=\"cid:logo@example.com\"> <IMG decoding=sync SRC=x.png>"
                       + "<img decoding=sync decoding=\"async\" src=y>"
                       + "<img decoding=sync /src=z><img decoding=sync\nsrc=w><img decoding=sync >"
                       + "<Image decoding=sync src=v><img decoding=sync alt=\"an <img decoding=sync in it\" src=u>"
                       + "<imgx src=t></img><p>img \u{1F4EE}<img")
        XCTAssertEqual(decoded.filter { $0 == "\"" }.count, html.filter { $0 == "\"" }.count)
        for none in ["", "<p>No pictures. <imgx> </img> img</p>", "<IMG"] {
            XCTAssertEqual(PrintPage.decodedAtOnce(none), none)
        }

        // In every letter's page: each picture's tag, and only in the body.
        let tag = try NSRegularExpression(pattern: "<(img|image)(?=[\\s/>])", options: [.caseInsensitive])
        let decodedTag = try NSRegularExpression(pattern: "<(img|image) decoding=sync[\\s/>]",
                                                 options: [.caseInsensitive])
        func count(_ pattern: NSRegularExpression, _ text: String) -> Int {
            pattern.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        }
        var pictures = 0
        for (i, m) in (PaneLetters.all + [letter(text: nil, html: html)]).enumerated() {
            let page = self.page(m)
            XCTAssertEqual(count(decodedTag, page), count(tag, page), "letter \(i)")
            XCTAssertEqual(count(decodedTag, try body(page)), count(decodedTag, page), "letter \(i)")
            pictures += count(tag, page)
        }
        XCTAssertGreaterThan(pictures, 20)
    }

    /// A letter the pane shows only the beginning of has the pane's grey
    /// line above it, as in the pane.
    func testALetterThePaneShortenedSaysSo() throws {
        var m = letter(text: "The beginning.")
        XCTAssertFalse(try body(page(m)).contains(MailText.shortenedNotice))
        m.isShortened = true
        XCTAssertEqual(try body(page(m)), PrintPage.shortened + "The beginning.")
        var html = letter(text: nil, html: "<p>The beginning.</p>")
        html.isShortened = true
        XCTAssertEqual(try body(page(html)), PrintPage.shortened + "<p>The beginning.</p>")
        XCTAssertTrue(PrintPage.shortened.contains(PanePage.shortenedLine), "the pane's own line")
    }

    /// A plain letter over 128 KiB, and an HTML one over 512 KiB, are cut,
    /// at the last whole character under the limit, with the pane's line
    /// above them.
    func testALetterOverItsLimitIsCutAtAWholeCharacter() throws {
        // "a" and then é's, two bytes each: the limit falls in the middle
        // of the last one.
        let plain = "a" + String(repeating: "é", count: PrintPage.textLimit / 2)
        XCTAssertEqual(plain.utf8.count, PrintPage.textLimit + 1)
        let printed = try body(page(letter(text: plain)))
        XCTAssertTrue(printed.hasPrefix(PrintPage.shortened), "the line above it")
        let kept = String(printed.dropFirst(PrintPage.shortened.count))
        XCTAssertTrue(kept.hasSuffix("é"))
        XCTAssertLessThanOrEqual(kept.utf8.count, PrintPage.textLimit)
        XCTAssertEqual(kept.utf8.count, PrintPage.textLimit - 1)
        XCTAssertEqual(kept, String(plain.dropLast()))

        let markup = "<p>" + String(repeating: "é", count: PrintPage.htmlLimit / 2)
        let html = try body(page(letter(text: "Hello", html: markup)))
        XCTAssertTrue(html.hasPrefix(PrintPage.shortened))
        let cut = String(html.dropFirst(PrintPage.shortened.count))
        XCTAssertTrue(cut.hasSuffix("é"))
        XCTAssertLessThanOrEqual(cut.utf8.count, PrintPage.htmlLimit)
        XCTAssertEqual(cut, String(markup.dropLast(2)))

        // At the limit, nothing is cut, and nothing said.
        let full = String(repeating: "a", count: PrintPage.textLimit)
        XCTAssertEqual(try body(page(letter(text: full))), full)
    }

    /// The cut never breaks a character: not a letter with its accent
    /// after it, not a flag, not a character of four bytes.
    func testTheCutKeepsEveryCharacterWhole() {
        XCTAssertNil(PrintPage.cut("abc", to: 3))
        XCTAssertEqual(PrintPage.cut("abcd", to: 3), "abc")
        XCTAssertEqual(PrintPage.cut("ab" + "e\u{301}" + "z", to: 4), "ab")
        XCTAssertEqual(PrintPage.cut("ab" + "e\u{301}" + "z", to: 5), "ab" + "e\u{301}")
        XCTAssertEqual(PrintPage.cut("a\u{1F1EC}\u{1F1E7}b", to: 6), "a")
        XCTAssertEqual(PrintPage.cut("a\u{1F4EE}b", to: 4), "a")
        XCTAssertEqual(PrintPage.cut("a\u{1F4EE}b", to: 5), "a\u{1F4EE}")
        XCTAssertEqual(PrintPage.cut("éé", to: 1), "")
        // Through Foundation, as a body decoded there may be.
        let bridged = NSString(string: "a" + String(repeating: "é", count: 10)) as String
        XCTAssertEqual(PrintPage.cut(bridged, to: 10), "a" + String(repeating: "é", count: 4))
    }

    /// A letter with nothing in it prints the pane's words, grey.
    func testALetterWithNothingInItSaysSo() throws {
        for m in [letter(text: nil), letter(text: " \n\t"), letter(text: nil, html: "<html><body> <br></body></html>")] {
            XCTAssertEqual(try body(page(m)), PrintPage.empty)
        }
        XCTAssertTrue(PrintPage.empty.contains(">" + MailText.emptyBodyNotice + "<"))
        XCTAssertTrue(PrintPage.empty.contains("color: #8e8e8e;"))
    }

    /// The shapes of a letter with nothing in it that `PanePageTests`
    /// checks the pane with: empty words, blank lines, empty HTML, HTML of
    /// a space, and no body at all.
    private let nothing: [(text: String?, html: String?)] = [("", nil), ("\n\n", nil), (nil, ""),
                                                             (nil, "<div> </div>"), (nil, nil)]

    /// A letter shown only in part is never printed as having no text, as
    /// the pane never says it has none (B-114, B-131): what was not fetched
    /// of it, or what the server would not give, can be all its words. With
    /// nothing in what came, its page's body is the pane's grey line, "Only
    /// the beginning…", over that nothing, as the pane's `#bm` has it, and
    /// never "This message has no text."; the same letter whole still
    /// prints the pane's words for one, as it is said to have none.
    func testALetterShownOnlyInPartWithNothingInItIsNeverPrintedAsHavingNoText() throws {
        let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)
        for (text, html) in nothing {
            let label = "\(String(reflecting: text)) \(String(reflecting: html))"
            var m = letter(text: text, html: html)
            XCTAssertTrue(PanePage.isEmpty(m), label)
            XCTAssertEqual(try body(page(m)), PrintPage.empty, label)
            m.isShortened = true
            XCTAssertFalse(PanePage.isEmpty(m), label)
            let printed = try body(page(m))
            XCTAssertTrue(printed.hasPrefix(PrintPage.shortened), label)
            XCTAssertFalse(printed.contains(MailText.emptyBodyNotice), label)
            XCTAssertEqual(PrintPage.body(m).isHTML, html != nil, label)
            let came = String(printed.dropFirst(PrintPage.shortened.count))
            let pane = try XCTUnwrap(PanePage.letter(m, style: style), label)
            XCTAssertTrue(pane.contains("<div id=\"bm\">" + PanePage.shortenedLine + came + "</div></body>"),
                          label)
        }
    }

    /// The same in words, for when the page could not be drawn: a letter
    /// shown only in part with nothing in what came is its header and the
    /// pane's line, "Only the beginning…", and never "This message has no
    /// text."; whole, it is its header and the pane's words for one. A
    /// letter that is only a picture, which the pane shows and never says
    /// has no text, is its header alone; and a letter shown in part with
    /// words is the line over them, as before.
    func testALetterShownOnlyInPartWithNothingInItIsNeverSaidInWordsToHaveNoText() {
        let head = headInWords
        func words(_ m: Message) -> String {
            PrintPage.words(m, size: size, locale: posix, timeZone: utc)
        }
        for (text, html) in nothing {
            let label = "\(String(reflecting: text)) \(String(reflecting: html))"
            var m = letter(text: text, html: html)
            XCTAssertEqual(words(m), head + "\n\n" + MailText.emptyBodyNotice, label)
            m.isShortened = true
            XCTAssertEqual(words(m), head + "\n\n" + MailText.shortenedNotice, label)
        }
        let picture = letter(text: nil, html: "<img src=\"cid:logo@example.com\">")
        XCTAssertFalse(PanePage.isEmpty(picture))
        XCTAssertEqual(words(picture), head)
        var some = letter(text: "\n\nThe beginning.")
        some.isShortened = true
        XCTAssertEqual(words(some), head + "\n\n" + MailText.shortenedNotice + "\n\nThe beginning.")
    }

    /// Mail's bars beside quoted text (B-101): the pane's own string, at
    /// the end of every letter's style, in Mail's light colours on the
    /// paper; a plain letter's too since B-147, its quotes Mail's
    /// blockquotes as in the pane, whose plain page has Mail's dark ones.
    /// An inverted letter's pane has the colours the invert turns into
    /// Mail's dark ones since B-180, and Gmail's "wrote:" line its rule,
    /// on paper in the light colour.
    func testTheQuoteBarsAreThePanes() throws {
        let rules = QuoteBars.css(in: "#bm")
        let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)
        for (i, m) in PaneLetters.all.enumerated() {
            let sheet = try self.sheet(page(m))
            let line = m.htmlBody == PanePageTests.gmailReply ? QuoteBars.attributionCSS(in: "#bm") + "\n" : ""
            XCTAssertTrue(sheet.hasSuffix("\n" + rules + "\n" + line), "letter \(i)")
            XCTAssertFalse(sheet.contains(QuoteBars.dark[0]), "letter \(i)")
            XCTAssertFalse(sheet.contains(QuoteBars.inverted[0]), "letter \(i)")
            guard let pane = PanePage.letter(m, style: style) else { continue }
            XCTAssertTrue(try self.sheet(pane).contains(m.htmlBody != nil
                                                        ? "\n" + QuoteBars.css(in: "#bm", palette: QuoteBars.inverted)
                                                            + "\n"
                                                        : QuoteBars.css(in: "#bm", palette: QuoteBars.dark)),
                          "letter \(i)")
        }
    }

    /// A signature's white sheet prints as written, as it did: the paper
    /// has no invert and no filter, so the sheet's own white and black,
    /// declared in its markup, and its logo as drawn, the body being the
    /// pane's, byte for byte, the logo decoded as it is drawn. The pane's
    /// page inverts it with the rest (B-146) and has a rule for its colour
    /// alone, Mail's grey sheet once inverted (B-173), which the paper
    /// has not.
    func testASignaturesSheetPrintsAsWritten() throws {
        let logo = Attachment(id: "2", filename: "logo.png", mimeType: "image/png", size: 900,
                              contentID: "sig-logo", isInline: true)
        let m = letter(text: "Lunch on Sunday?", html: PanePageTests.signedLetter, attachments: [logo])
        let page = self.page(m)
        let sheet = try self.sheet(page)
        for pane in ["bm-signature", "filter", "invert"] {
            XCTAssertFalse(sheet.contains(pane), pane)
        }
        let content = PanePage.content(text: nil, html: PanePageTests.signedLetter, known: ["sig-logo"],
                                       flowed: false)
        let printed = try body(page)
        XCTAssertEqual(printed, PrintPage.decodedAtOnce(content))
        XCTAssertTrue(AppleMailHTML.signatureOpen.contains("background-color: #ffffff; color: #000000;"))
        XCTAssertTrue(printed.contains(AppleMailHTML.signatureOpen + "<div dir=\"ltr\"><table style=\""
                                       + AppleMailHTML.signatureTableStyle + "\"><tr><td>"
                                       + "<img decoding=sync src=\"bmcid://sig-logo\" width=\"70\">"), printed)
        let pane = try XCTUnwrap(PanePage.letter(m, style: .init(inset: 26, bodyPointSize: 17, lineHeight: 1.41)))
        XCTAssertTrue(try self.sheet(pane).contains(SignatureSheet.css(in: "#bm")))
    }

    // MARK: - In words

    /// The words: the header's lines as Mail prints them (B-172), a blank
    /// line, the text, its leading blank lines gone, and the files after
    /// it, as the page draws them after the words (B-170).
    func testTheWordsAreTheHeaderAndTheText() {
        let m = letter(cc: ["Carlo <carlo@example.com>"], text: "\n\nHello.\nSam", attachments: files)
        XCTAssertEqual(PrintPage.words(m, size: size, locale: posix, timeZone: utc),
                       headInWords + "\nCc: Carlo carlo@example.com\n\nHello.\nSam\n\n"
                       + "plan.pdf (2048 bytes)\nnotes.txt\nscan.pdf (10 bytes)")
        let none = letter(to: [], subject: "", text: nil)
        XCTAssertEqual(PrintPage.words(none, size: size, locale: posix, timeZone: utc),
                       "From: Sam Example sam@example.com\nSubject: (no subject)\nDate: \(printed)\n\n"
                       + MailText.emptyBodyNotice)
    }

    /// An HTML letter's words are its text made from its markup, as a
    /// reply quotes it (`HTMLText`).
    func testAnHTMLLettersWordsAreItsText() {
        let html = "<html><head><style>p { color: red }</style></head><body><p>Dear Sam,</p>"
            + "<p>The roses &amp; the lilies.</p></body></html>"
        for text: String? in [nil, " \n"] {
            let words = PrintPage.words(letter(text: text, html: html), size: size, locale: posix, timeZone: utc)
            XCTAssertTrue(words.hasSuffix("\n\n" + HTMLText.plainText(from: html)), words)
            XCTAssertTrue(words.contains("The roses & the lilies."), words)
        }
    }

    /// The words under the same limit as the page, with the pane's line
    /// above them, and for a letter the pane shortened too.
    func testTheWordsAreCutAndSaySo() {
        let plain = "a" + String(repeating: "é", count: PrintPage.textLimit / 2)
        let words = PrintPage.words(letter(text: plain), size: size, locale: posix, timeZone: utc)
        let parts = words.components(separatedBy: "\n\n")
        XCTAssertEqual(parts.count, 3, "the header, the line, the text")
        guard parts.count == 3 else { return }
        XCTAssertEqual(parts[1], MailText.shortenedNotice)
        XCTAssertEqual(parts[2], String(plain.dropLast()))
        var shortened = letter(text: "The beginning.")
        shortened.isShortened = true
        XCTAssertTrue(PrintPage.words(shortened, size: size, locale: posix, timeZone: utc)
                        .hasSuffix("\n\n" + MailText.shortenedNotice + "\n\nThe beginning."))
    }

    /// An HTML letter over 512 KiB is cut before it is made words, as its
    /// page cuts it, and says so as its page does: the pane's line over
    /// what the cut leaves, words or none. A long style sheet first, which
    /// makes no words, is the header and the line alone in words, never
    /// "This message has no text." and never the header alone; the words
    /// before a long comment, the line over them. A letter whose own plain
    /// words are printed, whole, has no line.
    func testAnHTMLLetterCutHereSaysSoInWordsAsOnItsPage() throws {
        let head = headInWords
        func words(_ m: Message) -> String {
            PrintPage.words(m, size: size, locale: posix, timeZone: utc)
        }
        let rule = "p { color: #333333; margin: 0 0 1em 0; }\n"
        let styled = "<html><head><style>"
            + String(repeating: rule, count: PrintPage.htmlLimit / rule.utf8.count + 1)
            + "</style></head><body><p>Dear Sam,</p><p>The roses.</p></body></html>"
        let commented = "<p>Dear Sam,</p><!-- "
            + String(repeating: "x", count: PrintPage.htmlLimit) + " --><p>The roses.</p>"
        for markup in [styled, commented] {
            XCTAssertGreaterThan(markup.utf8.count, PrintPage.htmlLimit)
            XCTAssertTrue(HTMLText.plainText(from: markup).contains("The roses."))
        }
        XCTAssertEqual(HTMLText.plainText(from: try XCTUnwrap(PrintPage.cut(styled, to: PrintPage.htmlLimit)))
                        .trimmingCharacters(in: .whitespacesAndNewlines), "", "the cut makes no words")

        for text: String? in [nil, " \n"] {
            let m = letter(text: text, html: styled)
            XCTAssertFalse(PanePage.isEmpty(m))
            XCTAssertEqual(words(m), head + "\n\n" + MailText.shortenedNotice)
            let printed = try body(page(m))
            XCTAssertTrue(printed.hasPrefix(PrintPage.shortened), "its page has the line")
            XCTAssertFalse(printed.contains(MailText.emptyBodyNotice))

            let said = letter(text: text, html: commented)
            XCTAssertEqual(words(said), head + "\n\n" + MailText.shortenedNotice + "\n\nDear Sam,")
            XCTAssertTrue(try body(page(said)).hasPrefix(PrintPage.shortened), "its page has the line")
        }
        let plain = letter(text: "Dear Sam,\nThe roses.", html: styled)
        XCTAssertEqual(words(plain), head + "\n\nDear Sam,\nThe roses.")
    }

    /// The page and the words of one print, made together with the pane's
    /// question asked once, are the page and the words made apart, for a
    /// letter with nothing in it, whole and shown in part, one that is only
    /// a picture, one with words, and one cut here.
    func testThePageAndTheWordsMadeTogetherAreTheirOwn() {
        var letters = nothing.map { letter(text: $0.text, html: $0.html) }
        letters += letters.map { var m = $0; m.isShortened = true; return m }
        letters += [letter(text: nil, html: "<img src=\"cid:logo@example.com\">", attachments: files),
                    letter(text: "Hello."), letter(text: nil, html: "<p>Hello.</p>"),
                    letter(text: nil, html: "<p>" + String(repeating: "a", count: PrintPage.htmlLimit + 1))]
        for (i, m) in letters.enumerated() {
            let made = PrintPage.made(m, style: style, size: size, locale: posix, timeZone: utc)
            XCTAssertEqual(made.page, page(m), "letter \(i)")
            XCTAssertEqual(made.words, PrintPage.words(m, size: size, locale: posix, timeZone: utc),
                           "letter \(i)")
        }
    }

    // MARK: - A PDF's pages (B-185, fixed again)

    /// The page of `m` with its PDFs' pages handed in, each page the
    /// number of its strips, as `LetterPrint` hands them.
    private func page(_ m: Message, pdfPages: [String: [Int]]) -> String {
        PrintPage.letter(m, style: style, size: size, locale: posix, timeZone: utc, pdfPages: pdfPages)
    }

    /// The picture of strip `strip` of page `n` of the PDF at `section` of
    /// `m`, as printed.
    private func pdfPage(_ section: String, _ n: Int, strip: Int = 1, of m: Message) -> String {
        "src=\"bmcid://"
            + InlineImageRewriter.escapedHost(PrintPage.pdfPageID(section, page: n, strip: strip, of: m.id)) + "\""
    }

    /// A letter of words and a PDF prints the PDF's page under the words,
    /// as Mail 16.5.1 prints it (round r6-p-copy, 29 October 2026, "Page 1
    /// of 2"): its strips the column's width, decoded as they are drawn,
    /// in order after `#bm`'s words and none before them; in an HTML
    /// letter and a plain one. With nothing handed in, the words alone, as
    /// before.
    func testAPDFsPageIsPrintedUnderTheWords() throws {
        let pdf = Attachment(id: "2", filename: "plan.pdf", mimeType: "application/pdf", size: 2_048)
        for m in [letter(text: "Our garden.", attachments: [pdf]),
                  letter(text: nil, html: "<p>Our garden.</p>", attachments: [pdf])] {
            let printed = try body(page(m, pdfPages: ["2": [1]]))
            let words = try XCTUnwrap(printed.range(of: "Our garden."))
            let picture = try XCTUnwrap(printed.range(of: pdfPage("2", 1, of: m)))
            XCTAssertLessThan(words.upperBound, picture.lowerBound, "under the words")
            XCTAssertEqual(printed.components(separatedBy: "<img ").count - 1, 1, "one strip, one picture")
            XCTAssertTrue(printed.hasSuffix("<img decoding=sync class=\"" + PrintPage.pdfPageClass + "\" "
                                            + pdfPage("2", 1, of: m) + " alt=\"\" style=\""
                                            + PrintPage.pdfPageStyle + "\">"), printed)
            XCTAssertTrue(PrintPage.pdfPageStyle.contains("width: 100% !important;"))
            XCTAssertTrue(PrintPage.pdfPageStyle.contains("display: block !important;"))
            XCTAssertFalse(PrintPage.pdfPageStyle.contains("break"), "no break of its own")
            XCTAssertEqual(page(m, pdfPages: [:]), page(m), "nothing handed in, the words alone")
            XCTAssertFalse(page(m).contains("bmpdf-"))
        }
        // Two pages of eight strips and three: every strip, in order; the
        // words in the same place.
        let two = letter(text: "Our garden.", attachments: [pdf])
        let printed = try body(page(two, pdfPages: ["2": [8, 3]]))
        XCTAssertEqual(printed.components(separatedBy: "<img ").count - 1, 11)
        var last = printed.startIndex
        for (n, strips) in [(1, 8), (2, 3)] {
            for strip in 1...strips {
                let here = try XCTUnwrap(printed.range(of: pdfPage("2", n, strip: strip, of: two)), "\(n) \(strip)")
                XCTAssertLessThan(last, here.lowerBound)
                last = here.upperBound
            }
        }
        XCTAssertFalse(printed.contains(pdfPage("2", 1, strip: 9, of: two)))
        XCTAssertTrue(printed.hasPrefix("Our garden."), printed)
        // A page that could not be drawn prints nothing, and the next is
        // still its own page.
        let broken = try body(page(two, pdfPages: ["2": [0, 2]]))
        XCTAssertEqual(broken.components(separatedBy: "<img ").count - 1, 2)
        XCTAssertTrue(broken.contains(pdfPage("2", 2, strip: 2, of: two)))
    }

    /// A page is cut into strips 180 pixels tall, 90 points on paper, the
    /// last what is left: so a page starts under the words and runs on to
    /// the next sheet, as WebKit's print layout moves a picture shorter
    /// than a sheet that does not fit to the next sheet whole.
    func testAPDFsPageIsCutIntoStrips() {
        XCTAssertEqual(PrintPage.pdfStripHeight, 180)
        XCTAssertEqual(PrintPage.pdfStrips(height: 1_398), Array(repeating: 180, count: 7) + [138])
        XCTAssertEqual(PrintPage.pdfStrips(height: 360), [180, 180])
        XCTAssertEqual(PrintPage.pdfStrips(height: 1), [1])
        XCTAssertEqual(PrintPage.pdfStrips(height: 0), [])
        XCTAssertEqual(PrintPage.pdfStrips(height: 4_320).count, 24)
        XCTAssertEqual(PrintPage.pdfStrips(height: 1_398).reduce(0, +), 1_398)
    }

    /// Only a PDF's pages print: a picture file, a text file or a PDF with
    /// nothing handed in print no page, as Mail prints none (B-185 as
    /// seen); pages for a part that is no PDF of the letter, or of none,
    /// draw nothing. A PDF sent with no kind of its own is one by its name.
    /// The picture file of this plain letter prints as its photo since
    /// round r6-u-pdf (`photos(of:cut:)`), never as a page.
    func testOnlyAPDFsPagesArePrinted() throws {
        let photo = Attachment(id: "2", filename: "IMG_0182.jpg", mimeType: "image/jpeg", size: 9)
        let notes = Attachment(id: "3", filename: "notes.txt", mimeType: "text/plain", size: 9)
        let plan = Attachment(id: "4", filename: "plan.pdf", mimeType: "application/pdf", size: 9)
        let bare = Attachment(id: "5", filename: "Scan.PDF", mimeType: "application/octet-stream", size: 9)
        let m = letter(text: "Our garden.", attachments: [photo, notes, plan, bare])
        XCTAssertEqual(PrintPage.pdfs(of: m).map(\.id), ["4", "5"])
        let none = try body(page(m, pdfPages: ["2": [1], "3": [1], "9": [1]]))
        XCTAssertTrue(none.hasPrefix("Our garden."), none)
        XCTAssertFalse(none.contains("bmpdf-"), none)
        XCTAssertEqual(none, try body(page(m)), "no page")
        let printed = try body(page(m, pdfPages: ["2": [1], "3": [1], "5": [1]]))
        XCTAssertEqual(printed.components(separatedBy: PrintPage.pdfPageClass).count - 1, 1)
        XCTAssertTrue(printed.contains(pdfPage("5", 1, of: m)))
        XCTAssertFalse(printed.contains("bmpdf-m7_3-2-"), "no picture file")
        XCTAssertFalse(printed.contains("bmpdf-m7_3-4-"), "nothing handed in, no page")
        XCTAssertTrue(PrintPage.isPDF(Attachment(id: "6", filename: "a", mimeType: "Application/PDF; name=a",
                                                 size: nil)))
        XCTAssertFalse(PrintPage.isPDF(Attachment(id: "6", filename: "a.pdf", mimeType: "text/plain",
                                                  size: nil)))
        // A letter of a PDF alone: its page under the header.
        let alone = letter(text: nil, attachments: [plan])
        XCTAssertTrue(try body(page(alone, pdfPages: ["4": [1]])).hasPrefix("<img decoding=sync"))
    }

    /// At most `pdfPageLimit` pages of the letter's PDFs in all, the first
    /// PDF the letter lists first: the cap is the letter's, as its reason,
    /// the print's memory, is, never each PDF's.
    func testAPDFsPagesStopAtTheLimit() throws {
        XCTAssertEqual(PrintPage.pdfPageLimit, 20)
        XCTAssertEqual(PrintPage.pdfPageWidth, 1_080, "twice the column's 540 points")
        XCTAssertEqual(PrintPage.pdfPageHeightLimit, 4_320)
        let one = Attachment(id: "2", filename: "one.pdf", mimeType: "application/pdf", size: 9)
        let two = Attachment(id: "3", filename: "two.pdf", mimeType: "application/pdf", size: 9)
        let three = Attachment(id: "4", filename: "three.pdf", mimeType: "application/pdf", size: 9)
        let m = letter(text: "Hello.", attachments: [one, two, three])
        // One PDF past the limit alone: twenty of its pages, none of the next.
        XCTAssertEqual(PrintPage.pdfPagesPrinted(m, counts: ["2": 57, "3": 3]), ["2": 20])
        var printed = try body(page(m, pdfPages: ["2": Array(repeating: 1, count: 57), "3": [1, 1, 1]]))
        XCTAssertEqual(printed.components(separatedBy: "<img ").count - 1, 20)
        XCTAssertTrue(printed.contains(pdfPage("2", 20, of: m)))
        XCTAssertFalse(printed.contains(pdfPage("2", 21, of: m)))
        XCTAssertFalse(printed.contains(pdfPage("3", 1, of: m)))
        // Three scans of nine pages: nine, nine and two, in the letter's
        // order, whatever order the counts came in.
        XCTAssertEqual(PrintPage.pdfPagesPrinted(m, counts: ["4": 9, "3": 9, "2": 9]),
                       ["2": 9, "3": 9, "4": 2])
        printed = try body(page(m, pdfPages: ["4": Array(repeating: 2, count: 9),
                                              "3": Array(repeating: 2, count: 9),
                                              "2": Array(repeating: 2, count: 9)]))
        XCTAssertEqual(printed.components(separatedBy: "<img ").count - 1, 40, "twenty pages of two strips")
        let last = try XCTUnwrap(printed.range(of: pdfPage("2", 9, strip: 2, of: m)))
        let next = try XCTUnwrap(printed.range(of: pdfPage("3", 1, of: m)))
        XCTAssertLessThan(last.upperBound, next.lowerBound, "in the order the letter lists them")
        XCTAssertTrue(printed.contains(pdfPage("4", 2, strip: 2, of: m)))
        XCTAssertFalse(printed.contains(pdfPage("4", 3, of: m)))
        XCTAssertEqual(PrintPage.pdfPagesPrinted(m, counts: ["2": 0, "3": -1, "9": 4]), [:])
        XCTAssertEqual(try body(page(m, pdfPages: ["2": [], "3": []])), "Hello.")
    }

    /// The address of each strip comes back through the loader's own
    /// reading of what WebKit asks it for (`InlineImageRewriter.contentID`)
    /// as the address the job keeps the strip under, so the loader finds
    /// it; each strip's and each page's its own, and another letter's
    /// another.
    func testAPDFPagesAddressComesBackThroughTheLoader() throws {
        let plan = Attachment(id: "1.2", filename: "plan.pdf", mimeType: "application/pdf", size: 9)
        let photo = Attachment(id: "3", filename: "photo.jpg", mimeType: "image/jpeg", size: 9)
        let m = letter(text: "Hello.", attachments: [plan, photo])
        let printed = page(m, pdfPages: ["1.2": [2, 2]])
        var seen: Set<String> = []
        for n in [1, 2] {
            for strip in [1, 2] {
                let src = pdfPage("1.2", n, strip: strip, of: m)
                XCTAssertTrue(printed.contains(src))
                let address = String(src.dropFirst("src=\"".count).dropLast())
                let url = try XCTUnwrap(URL(string: address))
                let id = try XCTUnwrap(InlineImageRewriter.contentID(of: url))
                XCTAssertEqual(id, PrintPage.pdfPageID("1.2", page: n, strip: strip, of: m.id))
                seen.insert(id)
            }
        }
        XCTAssertEqual(seen.count, 4)
        XCTAssertNotEqual(PrintPage.pdfPageID("1.2", page: 1, strip: 1, of: "7/4"),
                          PrintPage.pdfPageID("1.2", page: 1, strip: 1, of: m.id))
        XCTAssertNotEqual(PrintPage.pdfPageID("1.2", page: 11, strip: 1, of: m.id),
                          PrintPage.pdfPageID("1.2", page: 1, strip: 11, of: m.id))
    }

    /// A letter shown only in part has its PDF's pages above its words,
    /// under the grey line, as the pane puts its files there: its markup
    /// ends wherever the cut fell, and would take in what came after it.
    func testALetterShownInPartHasItsPDFsPagesAboveItsWords() throws {
        let plan = Attachment(id: "2", filename: "plan.pdf", mimeType: "application/pdf", size: 9)
        var m = letter(text: nil, html: "<p>The beginning.</p><!-- cut", attachments: [plan])
        m.isShortened = true
        let printed = try body(page(m, pdfPages: ["2": [1]]))
        XCTAssertTrue(printed.hasPrefix(PrintPage.shortened + "<img decoding=sync"), printed)
        XCTAssertTrue(printed.hasSuffix("<p>The beginning.</p><!-- cut"), printed)
    }

    // MARK: - The job

    func testTheJobIsNamedForTheSubject() {
        XCTAssertEqual(PrintPage.jobName(letter(subject: "The garden")), "The garden")
        XCTAssertEqual(PrintPage.jobName(letter(subject: "")), "(no subject)")
    }

    /// US Letter with a half-inch margin, and the limits.
    func testThePaperAndTheLimits() {
        XCTAssertEqual(PrintPage.paperWidth, 612)
        XCTAssertEqual(PrintPage.paperHeight, 792)
        XCTAssertEqual(PrintPage.margin, 36)
        XCTAssertEqual(PrintPage.textLimit, 128 * 1_024)
        XCTAssertEqual(PrintPage.htmlLimit, 512 * 1_024)
    }
}
