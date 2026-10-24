import XCTest
@testable import Blackmail

/// A printed letter's page (`PrintPage`, B-110): light, black on white, its
/// header as the reading pane's header draws it with the date written out
/// in full, then its body as the pane shows it, cut to a limit.
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

    /// The pane's sizes: the sender's, the lines', the subject's, and the
    /// body's at its line height.
    func testThePageIsInThePanesSizes() throws {
        let big = PrintPage.Style(senderPointSize: 21, metaPointSize: 19, subjectPointSize: 22,
                                  bodyPointSize: 23, lineHeight: 1.5)
        let sheet = try self.sheet(PrintPage.letter(letter(), style: big, size: size))
        for rule in ["font: 600 21px -apple-system, sans-serif;", "font: 19px -apple-system, sans-serif;",
                     "font: bold 22px -apple-system, sans-serif;", "font: 23px -apple-system, sans-serif;",
                     "line-height: 1.5;"] {
            XCTAssertTrue(sheet.contains(rule), rule)
        }
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

    /// The pane's lines in the pane's order: the sender, To, Cc, a rule,
    /// the subject, the date, the files, a rule. Names, as the pane writes
    /// them; a file's size, or its name alone; no line for a picture the
    /// body shows.
    func testTheHeaderIsThePanesInItsOrder() throws {
        let m = letter(cc: ["\"Carlo Rossi\" <carlo@example.com>"], attachments: files)
        let date = "September 21, 2026 at 2:13\u{202F}PM"
        XCTAssertEqual(try head(page(m)),
                       "<div class=\"bm-sender\">Sam Example</div>"
                       + "<div class=\"bm-meta\">To: Jane Example, sam@example.com</div>"
                       + "<div class=\"bm-meta\">Cc: Carlo Rossi</div>"
                       + "<div class=\"bm-rule\"></div>"
                       + "<div class=\"bm-subject\">The garden</div>"
                       + "<div class=\"bm-meta\">\(date)</div>"
                       + "<div class=\"bm-meta\">plan.pdf (2048 bytes)</div>"
                       + "<div class=\"bm-meta\">notes.txt</div>"
                       + "<div class=\"bm-meta\">scan.pdf (10 bytes)</div>"
                       + "<div class=\"bm-rule\"></div>")
        XCTAssertEqual(PrintPage.head(m, size: size, locale: posix, timeZone: utc),
                       .init(sender: "Sam Example", to: "To: Jane Example, sam@example.com",
                             cc: "Cc: Carlo Rossi", subject: "The garden", date: date,
                             files: ["plan.pdf (2048 bytes)", "notes.txt", "scan.pdf (10 bytes)"]))
    }

    /// "To: me" with no To, no Cc line with no Cc, and "(no subject)".
    func testTheHeaderSaysWhatThePaneSaysOfNothing() throws {
        let head = try self.head(page(letter(to: [], subject: "")))
        XCTAssertTrue(head.contains("<div class=\"bm-meta\">To: me</div><div class=\"bm-rule\"></div>"), head)
        XCTAssertFalse(head.contains("Cc:"), head)
        XCTAssertTrue(head.contains("<div class=\"bm-subject\">(no subject)</div>"), head)
        XCTAssertEqual(head.components(separatedBy: "<div class=\"bm-rule\"></div>").count - 1, 2)
    }

    /// The date written out in full, for a letter of today, one of
    /// yesterday and one of last year alike, never "Today" or
    /// "Yesterday": the paper is read on another day. On screen the pane's
    /// words are as they were, and the same as these for a letter older
    /// than yesterday.
    func testTheDateIsWrittenOutInFull() throws {
        let now = Date()
        let day: TimeInterval = 86_400
        for date in [now.addingTimeInterval(-60), now.addingTimeInterval(-day),
                     now.addingTimeInterval(-3 * day), now.addingTimeInterval(-400 * day)] {
            let full = MailFormat.fullTimestamp(date, locale: posix, timeZone: utc)
            XCTAssertEqual(PrintPage.head(letter(date: date), size: size, locale: posix, timeZone: utc).date,
                           full)
            XCTAssertTrue(try head(page(letter(date: date))).contains(">\(full)<"))
            XCTAssertFalse(full.contains("Today") || full.contains("Yesterday"), full)
            XCTAssertTrue(PrintPage.words(letter(date: date), size: size, locale: posix, timeZone: utc)
                            .contains("\n\(full)\n"))
        }
        XCTAssertEqual(MailFormat.fullTimestamp(Date(timeIntervalSince1970: 1_790_000_000),
                                                locale: posix, timeZone: utc),
                       "September 21, 2026 at 2:13\u{202F}PM")
        // On screen, as it was: today's and yesterday's relative, and the
        // rest the same words as on paper.
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
    }

    /// Every value of the header escaped, as text: a sender with an
    /// ampersand and an address, a subject with a script in it, a file
    /// whose name has `&` and `<`. The only attributes in the header are
    /// its own classes, and the page has no script of its own.
    func testTheHeaderIsEscaped() throws {
        let m = letter(sender: "Smith & Sons <x@y>", to: ["\"A <b>\" <a@b.example>"],
                       subject: "<script>alert(1)</script> & more",
                       attachments: [Attachment(id: "2", filename: "a & b <c>.pdf",
                                                mimeType: "application/pdf", size: 5)])
        let page = self.page(m)
        let head = try self.head(page)
        XCTAssertTrue(head.contains("<div class=\"bm-sender\">Smith &amp; Sons</div>"), head)
        XCTAssertTrue(head.contains(">&lt;script&gt;alert(1)&lt;/script&gt; &amp; more<"), head)
        XCTAssertTrue(head.contains(">a &amp; b &lt;c&gt;.pdf (5 bytes)<"), head)
        XCTAssertFalse(page.contains("<script"), page)
        let divs = head.components(separatedBy: "<div").count - 1
        let classes = head.components(separatedBy: "<div class=\"bm-").count - 1
        XCTAssertEqual(divs, classes)
        XCTAssertEqual(head.components(separatedBy: "=").count - 1, divs, "no attribute but the class")
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
                                           known: PanePage.contentIDs(of: m))
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

    /// Mail's bars beside quoted text (B-101): the pane's own string, at
    /// the end of an HTML letter's style; none for a plain letter.
    func testTheQuoteBarsAreThePanes() throws {
        let rules = QuoteBars.css(in: "#bm")
        let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)
        for m in PaneLetters.all {
            let sheet = try self.sheet(page(m))
            if m.htmlBody != nil, let pane = PanePage.letter(m, style: style) {
                XCTAssertTrue(sheet.hasSuffix("\n" + rules + "\n"), sheet)
                XCTAssertTrue(try self.sheet(pane).contains("\n" + rules + "\n"))
            } else {
                XCTAssertFalse(sheet.contains("blockquote"), sheet)
            }
        }
    }

    // MARK: - In words

    /// The words: the header's lines with the date in full, a blank line,
    /// the text, its leading blank lines gone.
    func testTheWordsAreTheHeaderAndTheText() {
        let m = letter(cc: ["Carlo <carlo@example.com>"], text: "\n\nHello.\nSam", attachments: files)
        XCTAssertEqual(PrintPage.words(m, size: size, locale: posix, timeZone: utc),
                       "Sam Example\nTo: Jane Example, sam@example.com\nCc: Carlo\nThe garden\n"
                       + "September 21, 2026 at 2:13\u{202F}PM\nplan.pdf (2048 bytes)\nnotes.txt\n"
                       + "scan.pdf (10 bytes)\n\nHello.\nSam")
        let none = letter(to: [], subject: "", text: nil)
        XCTAssertEqual(PrintPage.words(none, size: size, locale: posix, timeZone: utc),
                       "Sam Example\nTo: me\n(no subject)\nSeptember 21, 2026 at 2:13\u{202F}PM\n\n"
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
