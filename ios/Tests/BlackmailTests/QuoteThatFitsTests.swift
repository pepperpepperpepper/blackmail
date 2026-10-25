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
    private func longLetter(paragraphs: Int = 28_000, shortened: Bool = true) -> Message {
        let whole = "<html><body>" + (1...paragraphs).map { "<p>\(paragraph($0))</p>\n" }.joined()
            + "</body></html>"
        let fetched = shortened ? String(decoding: whole.utf8.prefix(2 << 20), as: UTF8.self) : whole
        var m = Message(id: "600001/77", mailboxID: "INBOX",
                        sender: "Jane Example <jane@example.com>", senderAddress: "jane@example.com",
                        to: ["sam@example.com"], cc: [], subject: "The long letter", date: when,
                        textBody: nil, htmlBody: fetched, attachments: [],
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
    /// at its last whole character, never through one; white space left at
    /// the end taken off; and a text that was itself only the beginning
    /// loses its last line even when it fits.
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

    /// A letter under the bound, the reply of every day and a long one he
    /// wrote, opens as it is.
    func testALetterUnderTheBoundOpensAsItIs() {
        let everyDay = reply(plainLetter("Lunch on Sunday?\n\nJane"))
        XCTAssertEqual(ComposeForm.bounded(everyDay).body, everyDay.body)
        let long = String(repeating: "A line he wrote, and another.\n", count: 4_000)
        XCTAssertLessThan(long.utf8.count, ComposeForm.largestBody)
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
