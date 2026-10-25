import XCTest
@testable import Blackmail

/// A reply to a letter that fills its 2 MB froze the app (B-140).
///
/// On the test iPad, a letter whose HTML part was over 2 MB and nearly all
/// words, shown with "Only the beginning of this message is shown.": Reply
/// was tapped, the keyboard rose with no sheet over the pane, and the app
/// took no touch for ten minutes until it was ended. The quote was every
/// word of the 2 MB fetched, about 1.7 MB, put into a text view as tall as
/// its words. Now a quote puts at most `QuotedOriginal.largestWords` of
/// them into the composer, at a line's end, says where it stops as a
/// letter shown in part says it, and reads no more of the markup than
/// those words need; and the composer opens on no more than
/// `ComposeForm.largestBody` of any letter.
final class QuoteThatFitsTests: XCTestCase {

    private let signature = "Sam Example\n555-555-0142"
    private let notice = "Only the beginning of this message is shown."
    private let when = Date(timeIntervalSince1970: 1_790_000_000)

    private var account: MailAccount {
        MailAccount(address: "sam@example.com", username: "sam@example.com",
                    displayName: "Sam Example", signature: signature)
    }

    /// A paragraph of the long letter: about 75 characters of words, its
    /// number in it, so where a quote stops can be read.
    private func paragraph(_ n: Int) -> String {
        "Paragraph \(String(format: "%05d", n)) of the long letter, words and more words to fill it."
    }

    /// The fixture's shape: an HTML part of paragraphs over 2 MB, cut at
    /// the 2 MiB the pane fetches (`<0.2097152>`), shown only in part.
    private func longLetter(paragraphs: Int = 28_000, shortened: Bool = true, html: String? = nil,
                            attachments: [Attachment] = []) -> Message {
        let whole = html ?? "<html><body>"
            + (1...paragraphs).map { "<p>\(paragraph($0))</p>\n" }.joined() + "</body></html>"
        let fetched = shortened ? String(decoding: whole.utf8.prefix(2 << 20), as: UTF8.self) : whole
        var m = Message(id: "600001/77", mailboxID: "INBOX",
                        sender: "Jane Example <jane@example.com>", senderAddress: "jane@example.com",
                        to: ["sam@example.com"], cc: [], subject: "The long letter", date: when,
                        textBody: nil, htmlBody: fetched, attachments: attachments,
                        messageID: "<long-1@example.com>")
        m.isShortened = shortened
        return m
    }

    private func plainLetter(_ text: String) -> Message {
        Message(id: "600001/78", mailboxID: "INBOX",
                sender: "Jane Example <jane@example.com>", senderAddress: "jane@example.com",
                to: ["sam@example.com"], cc: [], subject: "The long letter", date: when,
                textBody: text, htmlBody: nil, attachments: [],
                messageID: "<long-2@example.com>")
    }

    private func reply(_ m: Message) -> Draft {
        Draft.replying(to: m, all: false, myAddress: "sam@example.com", signature: signature)
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// The most a reply's body can come to with its quote at the ceiling:
    /// the signature, the attribution, the quote's words with their "> ",
    /// and the line under them.
    private func replyCeiling(_ m: Message) -> Int {
        Draft.signatureBlock(signature).utf8.count + 2
            + MailFormat.quoteAttribution(m.date, sender: m.sender).utf8.count + 1
            + QuotedOriginal.largestWords
            + QuotedOriginal.shortenedEnding.replacingOccurrences(of: "\n", with: "\n> ").utf8.count
    }

    // MARK: - The fixture's letter

    /// The round's letter: the reply's body is under the bound, the quote
    /// ends at a whole paragraph and then says where it stops, once, after
    /// "> " as every line of it; the HTML twin quotes the same words with
    /// the grey line, and none of the letter past them. And the composer
    /// takes the body as it is.
    func testAReplyToALetterThatFillsItsTwoMegabytesStaysUnderTheBound() throws {
        let m = longLetter()
        XCTAssertEqual(m.htmlBody?.utf8.count, 2 << 20, "the 2 MiB fetched of it")
        XCTAssertGreaterThan(m.quotableText.utf8.count, 1_700_000, "the round's 1.7 MB of words")
        let draft = reply(m)

        XCTAssertLessThanOrEqual(draft.body.utf8.count, replyCeiling(m))
        XCTAssertLessThanOrEqual(draft.body.utf8.count, ComposeForm.largestBody)
        XCTAssertGreaterThan(draft.body.utf8.count, QuotedOriginal.largestWords * 9 / 10,
                             "the quote fills the bound, it is not left nearly empty")
        XCTAssertTrue(draft.body.hasSuffix("\n> \n> " + notice), String(draft.body.suffix(200)))
        XCTAssertEqual(occurrences(of: notice, in: draft.body), 1)
        XCTAssertTrue(draft.body.contains("\n> " + paragraph(1) + "\n"))
        // The last line of words is a whole paragraph, the one after it
        // nowhere.
        let lines = draft.body.components(separatedBy: "\n")
        let last = lines[lines.count - 3]
        let number = try XCTUnwrap(Int(last.dropFirst("> Paragraph ".count).prefix(5)))
        XCTAssertEqual(last, "> " + paragraph(number))
        XCTAssertFalse(draft.body.contains(paragraph(number + 1)))
        XCTAssertGreaterThan(number, 500)

        let quote = try XCTUnwrap(draft.quote)
        XCTAssertTrue(quote.isShortened)
        XCTAssertTrue(quote.isIntact(in: draft.body))
        XCTAssertNil(quote.html, "his words are quoted, not the 2 MB of markup")

        let html = try XCTUnwrap(AppleMailHTML.letter(for: draft, account: account).html)
        XCTAssertTrue(html.hasSuffix(AppleMailHTML.shortenedLine + "</div></blockquote></body></html>"),
                      String(html.suffix(300)))
        XCTAssertEqual(occurrences(of: notice, in: html), 1)
        XCTAssertTrue(html.contains(paragraph(number)))
        XCTAssertFalse(html.contains(paragraph(number + 1)))
        XCTAssertLessThan(html.utf8.count, 4 * QuotedOriginal.largestWords)

        // The composer: nothing more to cut, the body as the reply made it.
        XCTAssertEqual(ComposeForm.bounded(draft).body, draft.body)
    }

    /// Forward, the same: its quote has no "> ", and ends with the line
    /// under a blank one.
    func testAForwardOfItStaysUnderTheBoundToo() throws {
        let m = longLetter()
        let draft = Draft.forwarding(m, signature: signature)
        let header = "Begin forwarded message:\n\nFrom: Jane Example <jane@example.com>\n"
        XCTAssertTrue(draft.body.contains(header), draft.body.prefix(400).description)
        XCTAssertLessThanOrEqual(draft.body.utf8.count, QuotedOriginal.largestWords + 1_000)
        XCTAssertTrue(draft.body.hasSuffix("\n\n" + notice))
        XCTAssertEqual(occurrences(of: notice, in: draft.body), 1)
        let quote = try XCTUnwrap(draft.quote)
        XCTAssertTrue(quote.isShortened)
        XCTAssertNil(quote.html)
        XCTAssertTrue(quote.isIntact(in: draft.body))
        let html = try XCTUnwrap(AppleMailHTML.letter(for: draft, account: account).html)
        XCTAssertEqual(occurrences(of: notice, in: html), 1)
        XCTAssertLessThan(html.utf8.count, 4 * QuotedOriginal.largestWords)
        XCTAssertEqual(ComposeForm.bounded(draft).body, draft.body)
    }

    /// The tap's own cost: the markup is read in pieces from its start and
    /// no further than the words that fit need, a small part of the 2 MB.
    func testTheTwoMegabytesAreNotReadWhole() {
        let m = longLetter()
        let html = m.htmlBody ?? ""
        let made = HTMLText.plainText(from: html, limit: QuotedOriginal.largestWords)
        XCTAssertTrue(made.isCut)
        XCTAssertEqual(made.read, QuotedOriginal.largestWords * 4)
        XCTAssertLessThan(made.read, html.count / 4)
        XCTAssertTrue(made.text.hasPrefix(paragraph(1) + "\n\n" + paragraph(2)))
        // Made the same way as the whole, as far as it goes.
        let whole = HTMLText.plainText(from: html)
        let lastBreak = made.text.lastIndex(of: "\n") ?? made.text.startIndex
        XCTAssertTrue(whole.hasPrefix(String(made.text[..<lastBreak])))
    }

    /// A plain letter of two megabytes, not shown in part: its quote is cut
    /// at the bound all the same, and says so.
    func testAPlainLetterOfTwoMegabytesIsCutAndSaysSo() throws {
        let text = (1...26_000).map(paragraph).joined(separator: "\n")
        let m = plainLetter(text)
        let draft = reply(m)
        XCTAssertLessThanOrEqual(draft.body.utf8.count, replyCeiling(m))
        XCTAssertTrue(draft.body.hasSuffix("\n> \n> " + notice))
        XCTAssertEqual(occurrences(of: notice, in: draft.body), 1)
        let quote = try XCTUnwrap(draft.quote)
        XCTAssertTrue(quote.isShortened, "cut here, it is shortened though the letter came whole")
        let html = try XCTUnwrap(AppleMailHTML.letter(for: draft, account: account).html)
        XCTAssertEqual(occurrences(of: notice, in: html), 1)
        XCTAssertEqual(ComposeForm.bounded(draft).body, draft.body)
    }

    /// A letter whose words fit is quoted as it always was: every word,
    /// its markup carried, no line under it. Just under the ceiling too,
    /// with the "> " counted.
    func testALetterWhoseWordsFitIsQuotedWholeAsBefore() throws {
        for count in [3, 800] {
            let m = longLetter(paragraphs: count, shortened: false)
            let draft = reply(m)
            let expected = MailFormat.quoteAttribution(m.date, sender: m.sender) + "\n> "
                + m.quotableText.replacingOccurrences(of: "\n", with: "\n> ")
            XCTAssertTrue(draft.body.hasSuffix(expected))
            XCTAssertFalse(draft.body.contains(notice))
            let quote = try XCTUnwrap(draft.quote)
            XCTAssertFalse(quote.isShortened)
            XCTAssertEqual(quote.html, m.htmlBody)
            let forward = Draft.forwarding(m, signature: signature)
            XCTAssertTrue(forward.body.hasSuffix("\n\n" + m.quotableText))
            XCTAssertEqual(forward.quote?.html, m.htmlBody)
        }
        // A forward's quote at the ceiling exactly, its lines whole: as it is.
        var lines: [String] = []
        var size = 0
        while size + paragraph(lines.count + 1).utf8.count + 1 <= QuotedOriginal.largestWords {
            lines.append(paragraph(lines.count + 1))
            size += paragraph(lines.count).utf8.count + 1
        }
        let words = lines.joined(separator: "\n")
        XCTAssertLessThanOrEqual(words.utf8.count, QuotedOriginal.largestWords)
        XCTAssertNil(QuotedOriginal.cut(words, within: QuotedOriginal.largestWords))
        let forward = Draft.forwarding(plainLetter(words), signature: signature)
        XCTAssertTrue(forward.body.hasSuffix("\n\n" + words))
        XCTAssertNotNil(QuotedOriginal.cut(words, within: QuotedOriginal.largestWords, prefix: 2),
                        "with a reply's \"> \" the same words do not fit")
    }

    // MARK: - The cut

    /// Where a quote is cut: at the end of the last line that fits, its
    /// "> " counted; a paragraph too long for that at its last space, or
    /// at its last whole character, never through one, a flag, a family
    /// joined by zero-width joiners or a letter and its accent included;
    /// no more than `lines` lines; white space left at the end taken off;
    /// and a text that was itself only the beginning loses its last line
    /// even when it fits.
    func testTheCutIsAtALinesEnd() {
        XCTAssertNil(QuotedOriginal.cut("one\ntwo", within: 7))
        XCTAssertEqual(QuotedOriginal.cut("one\ntwo\nthree", within: 9), "one\ntwo")
        XCTAssertEqual(QuotedOriginal.cut("one\ntwo\nthree", within: 12), "one\ntwo")
        XCTAssertNil(QuotedOriginal.cut("one\ntwo", within: 11, prefix: 2))
        XCTAssertEqual(QuotedOriginal.cut("one\ntwo", within: 10, prefix: 2), "one")
        XCTAssertEqual(QuotedOriginal.cut("one\n\n\ntwo three", within: 8), "one")
        // A line end before half the limit: the long line is cut at a space.
        XCTAssertEqual(QuotedOriginal.cut("a\nthe long paragraph goes on", within: 21),
                       "a\nthe long paragraph")
        // No space at all: at the last whole character.
        XCTAssertEqual(QuotedOriginal.cut("abcdefghij", within: 4), "abcd")
        XCTAssertEqual(QuotedOriginal.cut("ééééé", within: 5), "éé")
        XCTAssertEqual(QuotedOriginal.cut("👍👍", within: 7), "👍")
        // A whole character as Swift has it, and as the text view draws
        // it: not half a flag, nor a family without its last member and a
        // joiner left hanging, nor a letter without the accent after it.
        let flags = "🇺🇸🇺🇸🇺🇸"
        XCTAssertEqual(QuotedOriginal.cut(flags, within: 6), "")
        XCTAssertEqual(QuotedOriginal.cut(flags, within: 12), "🇺🇸")
        XCTAssertEqual(QuotedOriginal.cut(flags, within: 16), "🇺🇸🇺🇸")
        let family = "👨\u{200D}👩\u{200D}👧"
        XCTAssertEqual(family.utf8.count, 18)
        XCTAssertEqual(QuotedOriginal.cut(family + family, within: 25), family)
        XCTAssertEqual(QuotedOriginal.cut(family + family, within: 17), "")
        let accent = "e\u{0301}"
        XCTAssertEqual(QuotedOriginal.cut(accent + accent + accent, within: 4), accent)
        XCTAssertEqual(QuotedOriginal.cut(accent + accent + accent, within: 5), accent)
        XCTAssertEqual(QuotedOriginal.cut(accent + accent + accent, within: 6), accent + accent)
        // No more than `lines` lines, at a line's end, however few bytes.
        XCTAssertEqual(QuotedOriginal.cut("a\nb\nc", within: 100, lines: 2), "a\nb")
        XCTAssertNil(QuotedOriginal.cut("a\nb", within: 100, lines: 2))
        XCTAssertEqual(QuotedOriginal.cut("a\nb\nc", within: 100, lines: 1), "a")
        XCTAssertEqual(QuotedOriginal.cut("a\n\n\nb", within: 100, lines: 3), "a")
        XCTAssertEqual(QuotedOriginal.cut("one\ntwo\nthree", within: 9, lines: 3), "one\ntwo",
                       "the bytes first, when they are fewer")
        XCTAssertEqual(QuotedOriginal.cut("one\ntwo\nthr", within: 100, lines: 2, more: true), "one\ntwo")
        // Only the beginning: its last line goes even when it fits.
        XCTAssertEqual(QuotedOriginal.cut("one\ntwo\nthr", within: 100, more: true), "one\ntwo")
        XCTAssertEqual(QuotedOriginal.cut("one", within: 100, more: true), "one")
        XCTAssertNil(QuotedOriginal.cut("", within: 100))
    }

    /// The limited reading of the markup: the whole letter's text, not cut,
    /// when the words do not pass the limit; past a style sheet longer than
    /// the first piece, the next pieces are read until the words are found.
    func testTheMarkupIsReadInPiecesUntilTheWordsAreFound() {
        let small = "<p>Hello <b>there</b></p><p>Second &amp; last</p>"
        let made = HTMLText.plainText(from: small, limit: 1_000)
        XCTAssertEqual(made.text, HTMLText.plainText(from: small))
        XCTAssertFalse(made.isCut)
        XCTAssertEqual(made.read, small.count)

        let style = "<style>" + String(repeating: "p { margin: 0 } ", count: 625) + "</style>"
        let styled = style + (1...1_000).map { "<p>\(paragraph($0))</p>" }.joined()
        let found = HTMLText.plainText(from: styled, limit: 500)
        XCTAssertTrue(found.isCut)
        XCTAssertTrue(found.text.hasPrefix(paragraph(1)), String(found.text.prefix(100)))
        XCTAssertEqual(found.read, 500 * 4 * 4 * 4, "three pieces, each four times the last")
        XCTAssertLessThan(found.read, styled.count)
    }

    // MARK: - Short lines

    private func lineCount(_ text: String) -> Int {
        text.utf8.lazy.filter { $0 == 0x0A }.count + 1
    }

    /// A letter of short lines, far more of them in 64 KiB than of the
    /// round's paragraphs: its quote stops at `largestLines` lines, at a
    /// whole line, and says so once, after "> " in a reply. A plain letter
    /// of 30,000 numbers, an HTML one of 60,000 one-letter paragraphs, and
    /// a forward of 60,000 lines of "a". The composer takes each as it is.
    func testALetterOfShortLinesIsQuotedNoMoreThanTheLinesBound() throws {
        let numbers = (1...30_000).map { String(format: "%05d", $0) }.joined(separator: "\n")
        let m = plainLetter(numbers)
        let draft = reply(m)
        let quote = try XCTUnwrap(draft.body.range(of: "> 00001\n"))
        let quoted = String(draft.body[quote.lowerBound...])
        XCTAssertEqual(lineCount(quoted), QuotedOriginal.largestLines + 2, String(quoted.suffix(80)))
        XCTAssertTrue(quoted.hasSuffix("> 02000\n> \n> " + notice), String(quoted.suffix(80)))
        XCTAssertFalse(quoted.contains("02001"))
        XCTAssertLessThan(quoted.utf8.count, QuotedOriginal.largestWords / 3, "the lines, not the bytes")
        XCTAssertTrue(try XCTUnwrap(draft.quote).isShortened)
        XCTAssertEqual(ComposeForm.bounded(draft).body, draft.body)
        XCTAssertLessThan(lineCount(draft.body), ComposeForm.largestLines)

        let paragraphs = "<html><body>" + String(repeating: "<p>a</p>", count: 60_000) + "</body></html>"
        let fromHTML = reply(longLetter(shortened: false, html: paragraphs))
        XCTAssertLessThanOrEqual(lineCount(fromHTML.body), lineCount(draft.body))
        XCTAssertTrue(fromHTML.body.hasSuffix("> a\n> \n> " + notice), String(fromHTML.body.suffix(80)))
        XCTAssertEqual(occurrences(of: notice, in: fromHTML.body), 1)
        XCTAssertEqual(ComposeForm.bounded(fromHTML).body, fromHTML.body)

        let forward = Draft.forwarding(plainLetter(String(repeating: "a\n", count: 60_000)),
                                       signature: signature)
        let header = try XCTUnwrap(forward.body.range(of: "Subject: The long letter\n\n"))
        let words = String(forward.body[header.upperBound...])
        XCTAssertEqual(lineCount(words), QuotedOriginal.largestLines + 2)
        XCTAssertTrue(words.hasSuffix("a\n\n" + notice))
        XCTAssertEqual(ComposeForm.bounded(forward).body, forward.body)
    }

    /// The composer's own bound on lines: a body of more than
    /// `largestLines` short lines, far under `largestBody`, a draft or a
    /// `mailto:` link's, is cut at a whole line to `largestLines` with the
    /// ending; one of exactly `largestLines` lines opens as it is.
    func testTheComposerTakesNoMoreThanItsLines() throws {
        let most = ComposeForm.largestLines
        let exactly = (1...most).map { String(format: "%05d", $0) }.joined(separator: "\n")
        XCTAssertEqual(ComposeForm.bounded(body: exactly), exactly)
        let over = exactly + "\n" + String(format: "%05d", most + 1)
        let cut = ComposeForm.bounded(body: over)
        XCTAssertEqual(lineCount(cut), most)
        XCTAssertTrue(cut.hasSuffix("\n" + String(format: "%05d", most - 2) + "\n\n" + notice),
                      String(cut.suffix(80)))
        let quoted = ComposeForm.bounded(body: (1...50_000).map { "> \($0)" }.joined(separator: "\n"))
        XCTAssertEqual(lineCount(quoted), most)
        XCTAssertTrue(quoted.hasSuffix("> \(most - 2)\n> \n> " + notice), String(quoted.suffix(80)))

        let link = try XCTUnwrap(URL(string: "mailto:jane@example.com?body="
            + (1...50_000).map(String.init).joined(separator: "%0D%0A")))
        let draft = try XCTUnwrap(MailtoLink.draft(from: link, signature: signature))
        XCTAssertGreaterThan(lineCount(draft.body), 50_000)
        let opened = ComposeForm.bounded(draft)
        XCTAssertEqual(lineCount(opened.body), most)
        XCTAssertTrue(opened.body.hasPrefix("1\n2\n3\n"))
        XCTAssertTrue(opened.body.hasSuffix("\n\(most - 2)\n\n" + notice), String(opened.body.suffix(80)))

        // B-140's check: a link of 6,000 numbers stops at 3998, and one of
        // 2,000 long lines, some 180 KB, at the bytes, after line 1472.
        let numbers = try XCTUnwrap(URL(string: "mailto:nobody@example.com?subject=B-140%20lines&body="
            + (1...6_000).map(String.init).joined(separator: "%0D%0A")))
        let six = ComposeForm.bounded(try XCTUnwrap(MailtoLink.draft(from: numbers, signature: signature)))
        XCTAssertTrue(six.body.hasSuffix("\n3997\n3998\n\n" + notice))
        let long = (1...2_000).map {
            "Line \(String(format: "%04d", $0)) of the long link, written to fill the composer "
                + "to its bound and a little more."
        }
        let words = try XCTUnwrap(URL(string: "mailto:nobody@example.com?subject=B-140%20long&body="
            + long.map { $0.replacingOccurrences(of: " ", with: "%20") }.joined(separator: "%0D%0A")))
        let draft2 = try XCTUnwrap(MailtoLink.draft(from: words, signature: signature))
        XCTAssertGreaterThan(draft2.body.utf8.count, 170_000)
        let bounded = ComposeForm.bounded(draft2).body
        XCTAssertLessThanOrEqual(bounded.utf8.count, ComposeForm.largestBody)
        XCTAssertTrue(bounded.hasSuffix(long[1_471] + "\n\n" + notice), String(bounded.suffix(160)))
    }

    // MARK: - What Reply and Forward read

    /// Reply, Reply All and Forward of the round's letter read no more of
    /// its markup than the words they keep need, a quarter of it and
    /// less, through `Message.quoted`, which the drafts are made from (the
    /// composer, read, below). A text part reads no markup. As first
    /// built, `quoted` asking for the markup whole failed nothing: the cut
    /// made the same quote of it.
    func testReplyAndForwardReadNoMoreOfTheMarkupThanTheyKeep() throws {
        let m = longLetter()
        let markup = try XCTUnwrap(m.htmlBody).count
        for prefix in ["> ", ""] {
            let quoted = m.quoted(eachLineAfter: prefix)
            XCTAssertTrue(quoted.isCut)
            XCTAssertLessThanOrEqual(quoted.read, 4 * QuotedOriginal.largestWords, prefix)
            XCTAssertLessThan(quoted.read, markup / 4, prefix)
        }
        XCTAssertEqual(plainLetter("Lunch?").quoted().read, 0)
        // The drafts quote what `quoted` makes, word for word.
        XCTAssertTrue(reply(m).body.hasSuffix(m.quoted(eachLineAfter: "> ").text))
        XCTAssertTrue(Draft.forwarding(m, signature: signature).body.hasSuffix(m.quoted().text))
    }

    // MARK: - A forward's rows

    /// A forward whose quote is cut, answered Don't Include, carries no
    /// rows: the pictures it would carry are those its quote shows, and the
    /// cut quote, words alone, shows none, so they would have gone as
    /// files. Include carries every part, as always; a letter whose words
    /// fit still carries its body's pictures with Don't Include.
    func testDontIncludeOnACutForwardCarriesNoPictures() throws {
        let photo = Attachment(id: "2", filename: "garden.jpg", mimeType: "image/jpeg", size: 1_200,
                               contentID: "garden", isInline: true)
        let pdf = Attachment(id: "3", filename: "Programme.pdf", mimeType: "application/pdf", size: 22)
        let long = longLetter(attachments: [photo, pdf])
        XCTAssertEqual(Draft.forwarding(long, includingFiles: false).attachments, [])
        XCTAssertEqual(Draft.forwarding(long, includingFiles: true).attachments.map(\.filename),
                       ["garden.jpg", "Programme.pdf"])
        let short = longLetter(paragraphs: 3, shortened: false, attachments: [photo, pdf])
        XCTAssertEqual(Draft.forwarding(short, includingFiles: false).attachments.map(\.filename),
                       ["garden.jpg"])
    }

    // MARK: - The share sheet

    /// Text shared from another app goes into the share sheet's own text
    /// view, as tall as its words, bounded as the composer's is: a
    /// megabyte of it comes to no more than `largestBody` and
    /// `largestLines` with the ending, his signature under it. A short one
    /// as it was.
    func testTextSharedIsBoundedAsTheComposersIs() {
        let huge = (1...26_000).map(paragraph).joined(separator: "\n")
        let block = Draft.signatureBlock(signature)
        let draft = ShareLetter.draft(from: [.text(huge)], signature: signature)
        XCTAssertTrue(draft.body.hasSuffix(".\n\n" + notice + block), String(draft.body.suffix(200)))
        XCTAssertLessThanOrEqual(draft.body.utf8.count, ComposeForm.largestBody + block.utf8.count)
        XCTAssertEqual(occurrences(of: notice, in: draft.body), 1)
        let lines = ShareLetter.draft(from: [.text(String(repeating: "a\n", count: 60_000) + "z")],
                                      signature: signature)
        XCTAssertLessThanOrEqual(lineCount(lines.body), ComposeForm.largestLines + lineCount(block))
        let short = ShareLetter.draft(from: [.text("Have a look at this.")], signature: signature)
        XCTAssertEqual(short.body, "Have a look at this." + block)
    }

    // MARK: - The markup read on from piece to piece

    /// Each piece of the markup is walked on from where the last stopped,
    /// a tag, a comment, a quoted `>` or a style sheet across its end
    /// included: at every limit, what is made is the whole's text as far
    /// as it goes, and all of it once the words do not pass the limit.
    /// Markup with few words is read once, to its end.
    func testThePiecesAreWalkedOnNotAgain() {
        let piece = "<div class=\"a\"><style>p { x: 1 }</style><!-- a > b --><p title=\"x > y\">"
            + "Hello &amp; <b>wel</b>come</p><table><tr><td>one</td><td>two</td></tr></table>"
            + "<!--[if mso]><p>no</p><![endif]--><br>caf\u{00E9} e\u{0301} 🇺🇸</div>\n"
        let html = String(repeating: piece, count: 40)
        let whole = HTMLText.plainText(from: html)
        let words = whole.unicodeScalars.filter { !$0.properties.isWhitespace }.count
        for limit in 1...words + 5 {
            let made = HTMLText.plainText(from: html, limit: limit)
            if made.isCut {
                let lastBreak = made.text.lastIndex(of: "\n") ?? made.text.startIndex
                XCTAssertTrue(whole.hasPrefix(String(made.text[..<lastBreak])), "limit \(limit)")
            } else {
                XCTAssertEqual(made.text, whole, "limit \(limit)")
                XCTAssertEqual(made.read, html.count)
            }
        }
        // A picture written into the letter, 2 MB of it, and a few words.
        let picture = "<p>Hello, here is the photo.</p><img src=\"data:image/png;base64,"
            + String(repeating: "QUJDRA==", count: 250_000) + "\"><p>Love, Jane</p>"
        let made = HTMLText.plainText(from: picture, limit: QuotedOriginal.largestWords)
        XCTAssertFalse(made.isCut)
        XCTAssertEqual(made.text, HTMLText.plainText(from: picture))
        XCTAssertEqual(made.read, picture.count)
    }

    /// Read: one walk for all the pieces, made before the first and gone
    /// on with by each (`walk`), and the scan starting where it stopped,
    /// not at the start; each piece read on from the last, not from the
    /// start of the markup. As first built, every piece was read and
    /// walked again from the start, the same text made, three times the
    /// work for a letter of markup and few words.
    func testEachPieceIsWalkedOnFromTheLast() throws {
        let code = try source("MIME/HTMLText.swift")
        let limited = try XCTUnwrap(code.range(of: "static func plainText(from html: String, limit: Int)"))
        let body = String(code[limited.upperBound...].prefix(1_200))
        XCTAssertTrue(body.contains(
            "var rest = html.makeIterator() var chars: [Character] = [] var walk = Walk() "
                + "var take = max(limit, 1) * 4 while true {"), body)
        XCTAssertTrue(body.contains("while chars.count < take { guard let c = rest.next() else {"), body)
        XCTAssertTrue(body.contains("scan(chars, limit: limit, walk: &walk)"), body)
        XCTAssertEqual(code.components(separatedBy: "Walk()").count - 1, 2, "here and for the whole")
        XCTAssertTrue(code.contains("var out = walk.out var skipping = walk.skipping var i = walk.at "
                                    + "var words = walk.words"))
        XCTAssertFalse(code.contains("Array(html[..<"))
    }

    // MARK: - Every other letter the composer opens on

    /// A draft reopened from Drafts with such a quote, written in another
    /// client or saved by a build before the bound: fetched whole, as his
    /// own letter is, and the composer given no more than its bound, ended
    /// with the line after "> " as the quote's lines are. His words above
    /// it are all there.
    func testADraftWithSuchAQuoteOpensUnderTheBound() throws {
        let quoted = (1...26_000).map { "> " + paragraph($0) }.joined(separator: "\n")
        let body = "My words at the top.\n\nSam Example\n\nOn Sunday, Jane wrote:\n" + quoted
        let saved = Message(id: "600003/9", mailboxID: "[Gmail]/Drafts", sender: "Sam Example",
                            senderAddress: "sam@example.com", to: ["jane@example.com"], cc: [],
                            subject: "Re: The long letter", date: when, textBody: body,
                            htmlBody: nil, attachments: [])
        let reopened = Draft.reopening(saved, signatureImages: [])
        XCTAssertEqual(reopened.body, body, "fetched whole, and taken up whole")
        let opened = ComposeForm.bounded(reopened)
        XCTAssertLessThanOrEqual(opened.body.utf8.count, ComposeForm.largestBody)
        XCTAssertGreaterThan(opened.body.utf8.count, ComposeForm.largestBody * 9 / 10)
        XCTAssertTrue(opened.body.hasPrefix("My words at the top.\n\nSam Example\n\nOn Sunday"))
        XCTAssertTrue(opened.body.hasSuffix("\n> \n> " + notice), String(opened.body.suffix(200)))
        XCTAssertEqual(occurrences(of: notice, in: opened.body), 1)
        XCTAssertEqual(opened.to, reopened.to)
        XCTAssertEqual(opened.subject, reopened.subject)
        XCTAssertEqual(opened.savedID, reopened.savedID)

        // Not a quote's line: the line under a blank one, no "> ", after
        // a whole line.
        let plain = ComposeForm.bounded(body: (1...26_000).map(paragraph).joined(separator: "\n"))
        XCTAssertLessThanOrEqual(plain.utf8.count, ComposeForm.largestBody)
        XCTAssertTrue(plain.hasSuffix(".\n\n" + notice), String(plain.suffix(200)))
        XCTAssertFalse(plain.contains("> " + notice))
    }

    /// A draft written as HTML alone in another client, of 2 MB: its words
    /// are made from no more of its markup than the composer is given, and
    /// end with the line.
    func testAnHTMLDraftOfTwoMegabytesIsReadNoFurtherThanTheBound() {
        var saved = longLetter()
        saved.isShortened = false
        let reopened = Draft.reopening(saved, signatureImages: [])
        XCTAssertLessThanOrEqual(reopened.body.utf8.count, ComposeForm.largestBody)
        XCTAssertTrue(reopened.body.hasSuffix("\n\n" + notice))
        XCTAssertTrue(reopened.body.hasPrefix(paragraph(1)))
        XCTAssertEqual(ComposeForm.bounded(reopened).body, reopened.body)
    }

    /// A letter under the bounds, the reply of every day and a long one he
    /// wrote, opens as it is.
    func testALetterUnderTheBoundOpensAsItIs() {
        let everyDay = reply(plainLetter("Lunch on Sunday?\n\nJane"))
        XCTAssertEqual(ComposeForm.bounded(everyDay).body, everyDay.body)
        let long = String(repeating: "A line he wrote, and another, and a third one.\n", count: 2_500)
        XCTAssertLessThan(long.utf8.count, ComposeForm.largestBody)
        XCTAssertGreaterThan(long.utf8.count, ComposeForm.largestBody * 8 / 10)
        XCTAssertEqual(ComposeForm.bounded(body: long), long)
    }

    /// A reply made here to the long letter, saved as a draft and taken up
    /// again: under the bound still, and not cut a second time.
    func testASavedReplyToItComesBackWhole() throws {
        let draft = reply(longLetter())
        let letter = AppleMailHTML.letter(for: draft, account: account, forDraft: true)
        let raw = RFC5322Builder.build(draft: draft, from: account, date: when,
                                       messageID: "<saved@example.com>", attachments: [],
                                       includeBcc: true, htmlBody: letter.html, inlineImages: [])
        let decoded = MIMEDecoder.decodeMessage(raw)
        let saved = Message(id: "600003/10", mailboxID: "[Gmail]/Drafts", sender: "Sam Example",
                            senderAddress: "sam@example.com", to: draft.to, cc: draft.cc,
                            subject: draft.subject, date: when, textBody: decoded.text,
                            htmlBody: decoded.html, attachments: decoded.attachments)
        let back = Draft.reopening(saved, signatureImages: [])
        XCTAssertEqual(back.body.trimmingCharacters(in: .newlines),
                       draft.body.trimmingCharacters(in: .newlines))
        XCTAssertEqual(ComposeForm.bounded(back).body, back.body)
        XCTAssertEqual(occurrences(of: notice, in: back.body), 1)
        let quote = try XCTUnwrap(back.quote)
        XCTAssertTrue(quote.isIntact(in: back.body))
        let html = try XCTUnwrap(AppleMailHTML.letter(for: back, account: account).html)
        XCTAssertEqual(occurrences(of: notice, in: html), 1, String(html.suffix(400)))
    }

    // MARK: - The composer, read

    /// Every sheet the app's composer opens is given its letter through
    /// the one initializer, which bounds the body before anything else
    /// reads it; the text view is given the bounded body and nothing else,
    /// and it is still a view as tall as its words, which is why it is
    /// bounded. Reply and Forward make their drafts in the model.
    func testTheComposerIsGivenTheBoundedBody() throws {
        let code = try source("UI/ComposeViewController.swift")
        XCTAssertTrue(code.contains(
            "init(repository: MailRepository, draft: Draft, key: String? = nil, "
                + "replyFiles: ReplyFiles? = nil) { self.repository = repository "
                + "self.draft = ComposeForm.bounded(draft)"), code)
        XCTAssertEqual(code.components(separatedBy: "self.draft = ").count - 1, 1)
        XCTAssertEqual(code.components(separatedBy: "bodyView.text = ").count - 1, 1)
        XCTAssertTrue(code.contains("bodyView.text = draft.body"))
        XCTAssertEqual(code.components(separatedBy: "draft = ").count - 1, 1, "the init's alone")
        XCTAssertTrue(code.contains("bodyView.isScrollEnabled = false"))
        XCTAssertEqual(code.components(separatedBy: "init(repository:").count - 1, 1)

        let pane = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(pane.contains("draft = .forwarding(m, signature: signature, "
                                    + "includingFiles: included ?? true)"))
        XCTAssertTrue(pane.contains("draft = .replying(to: m, all: all, "
                                    + "mine: OwnAddresses(account: account),"))

        let model = try source("Model/MailModels.swift")
        XCTAssertEqual(model.components(separatedBy: "HTMLText.plainText(from: htmlBody)").count - 1, 1,
                       "read whole only for `quotableText` itself")
        XCTAssertFalse(model.contains("quotedWords"))
        // Reply and Forward quote through `quoted`, which reads the markup
        // no further than the words that fit, and bounds them in bytes and
        // in lines; nothing else asks for all of it.
        XCTAssertTrue(model.contains("let quoted = m.quoted(eachLineAfter: \"> \")"))
        XCTAssertTrue(model.contains("let quoted = m.quoted() region += "))
        XCTAssertTrue(model.contains(
            "let limit = QuotedOriginal.largestWords let made = quotableText(within: limit) "
                + "let cut = QuotedOriginal.cut(made.text, within: limit, lines: QuotedOriginal.largestLines, "
                + "prefix: prefix.utf8.count, more: made.isCut)"))
        XCTAssertEqual(model.components(separatedBy: "quotableText(within: ").count - 1, 2,
                       "`quoted`, and a draft written as HTML alone")
        XCTAssertTrue(model.contains("m.quotableText(within: ComposeForm.largestBody)"))
        XCTAssertEqual(model.components(separatedBy: ".quoted(").count - 1, 2)
    }

    // MARK: - Helpers

    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(file)")
        let text = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        return text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .joined(separator: " ")
    }
}
