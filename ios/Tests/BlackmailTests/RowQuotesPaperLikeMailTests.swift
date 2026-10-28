import XCTest
@testable import Blackmail

/// What a row says, a plain letter's quotes, and the paper, as Mail has
/// them (B-172), from the side by side of Mail 16.5.1 and Blackmail on
/// the test iPad, 2026-10-27 (round r6-i-compare): the paperclip on a
/// letter whose only files are pictures it shows by `cid:` (C-02b); a
/// plain letter's preview without its quotes (C-02b); the line above a
/// quote, "… wrote:", drawn inside it, and a `>From ` line a quote
/// (C-11c), on paper too (C-17c); and the printed header's labelled lines
/// with addresses, and its date (C-17b). Nothing on a screen moves: the
/// paperclip is the row's own, in its place; the preview is the row's two
/// grey lines; the quotes are the letter's lines; the header is paper's.
final class RowQuotesPaperLikeMailTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private let open = "<blockquote type=\"cite\">"
    private let close = "</blockquote>"

    /// The plain letter of the round, "R6 B-147 plain", as Sam Plain sent it.
    private let samPlain = "Yes, Sunday.\n\nOn Monday, Carlo wrote:\n> Lunch on Sunday?\n> > Or Saturday?\n"
        + ">> The garden is ready.\n> > > Three deep.\n>>>> Four deep.\n> See https://example.com/b147\n"
        + "> Back to one.\n>From the store's line.\n\nSam\n"
    /// "R6 B-147 flowed", Flo Flowed's, sent `format=flowed`.
    private let floFlowed = "Yes.\n> One.\n> > Still one.\n>> Two.\n"

    // MARK: - A1: the paperclip

    private static let header = "From: Hana <hana@example.net>\r\nTo: owner@example.com\r\nSubject: Pictures\r\n"
        + "Date: Mon, 26 Oct 2026 10:00:00 +0000\r\nMessage-ID: <pictures@example.net>\r\nMIME-Version: 1.0\r\n"

    private static let html = "Content-Type: text/html; charset=utf-8\r\n\r\n"
        + "<p>The words.</p><img src=\"cid:photo@example.net\">\r\n"

    /// A picture shown by `cid:`, its disposition and its name as given.
    private static func picture(_ headers: String) -> String {
        "Content-Type: image/jpeg" + headers
            + "Content-Transfer-Encoding: base64\r\nContent-ID: <photo@example.net>\r\n\r\n/9j/4AAQ\r\n"
    }

    private static func multipart(_ subtype: String, _ boundary: String, _ parts: [String]) -> String {
        "Content-Type: multipart/\(subtype); boundary=\"\(boundary)\"\r\n\r\n"
            + parts.map { "--\(boundary)\r\n" + $0 + "\r\n" }.joined() + "--\(boundary)--\r\n"
    }

    private static let named = "; name=\"h-photo.jpg\"\r\nContent-Disposition: inline; filename=\"h-photo.jpg\"\r\n"
    private static let unnamed = "\r\nContent-Disposition: inline\r\n"
    private static let typeNamed = "; name=\"h-photo.jpg\"\r\nContent-Disposition: inline\r\n"

    /// The shapes the round saw clipped by Mail, and those it did not.
    private var shapes: [(name: String, raw: String, clip: Bool)] {
        let words = "Content-Type: text/plain; charset=utf-8\r\n\r\nThe words.\r\n"
        return [
            // "R6 B-169 plain html" and "web picture": the HTML and its photo.
            ("related, a named photo by cid", Self.header
                + Self.multipart("related", "R", [Self.html, Self.picture(Self.named)]), true),
            // "R6 B-150 photo", an iPhone's: plain words beside the HTML and its photo.
            ("alternative of words and related", Self.header + Self.multipart("alternative", "A", [
                words, Self.multipart("related", "R", [Self.html, Self.picture(Self.named)]),
            ]), true),
            // Named in its Content-Type alone, as some senders name one.
            ("related, a photo named by its type", Self.header
                + Self.multipart("related", "R", [Self.html, Self.picture(Self.typeNamed)]), true),
            // "R6 B-172 noname" and its control, seen 2026-10-28: a photo
            // by cid with no filename and no name, clipped by Mail too.
            ("related, a photo with no name", Self.header
                + Self.multipart("related", "R", [Self.html, Self.picture(Self.unnamed)]), true),
            // Not seen: a named picture by cid outside multipart/related, as before.
            ("mixed, a named photo by cid", Self.header
                + Self.multipart("mixed", "M", [Self.html, Self.picture(Self.named)]), false),
            ("a plain letter with no file", Self.header + words, false),
        ]
    }

    /// Mail's paperclip on a letter whose only file is a picture it shows
    /// by `cid:` inside multipart/related, named, as on the four rows of
    /// the round, or with no name, as on "R6 B-172 noname" and its control
    /// in Mail on 2026-10-28; none for one outside multipart/related, which
    /// was not seen, nor for a letter with no file, "R6 B-172 nofile". The
    /// tiles are not changed: such a picture is no file the pane draws or
    /// lists.
    func testAPictureTheLetterShowsGivesItsRowThePaperclip() throws {
        for shape in shapes {
            let raw = Data(shape.raw.utf8)
            let structure = MIMEDecoder.parseStructure(raw)
            XCTAssertEqual(IMAPMailRepository.hasAttachment(structure), shape.clip, shape.name)
            XCTAssertEqual(MIMEDecoder.listedAttachments(in: structure).map(\.filename), [], shape.name)
            let letter = Message(id: "7/3", mailboxID: "INBOX", sender: "Hana <hana@example.net>",
                                 senderAddress: "hana@example.net", to: [], cc: [], subject: "Pictures",
                                 date: Date(timeIntervalSince1970: 1_792_000_000),
                                 textBody: MIMEDecoder.decodeMessage(raw).text,
                                 htmlBody: MIMEDecoder.decodeMessage(raw).html,
                                 attachments: MIMEDecoder.decodeMessage(raw).attachments)
            XCTAssertEqual(letter.listedAttachments.map(\.filename), [], shape.name)
        }
        let related = MIMEDecoder.parseStructure(Data(shapes[0].raw.utf8))
        let photo = try XCTUnwrap(MIMEDecoder.part(at: "2", in: related))
        XCTAssertFalse(photo.isListedFile, "still no file in the pane")
        XCTAssertTrue(IMAPMailRepository.isRelatedPicture(photo))
        XCTAssertFalse(IMAPMailRepository.isRelatedPicture(try XCTUnwrap(MIMEDecoder.part(at: "1", in: related))))
        let unnamed = MIMEDecoder.parseStructure(Data(shapes[3].raw.utf8))
        let bare = try XCTUnwrap(MIMEDecoder.part(at: "2", in: unnamed))
        XCTAssertNil(MIMEDecoder.decodedFilename(bare), "no name")
        XCTAssertFalse(bare.isListedFile, "no file in the pane either")
        XCTAssertTrue(IMAPMailRepository.isRelatedPicture(bare))
    }

    /// Through the shipping repository and the scripted server, as Gmail
    /// describes a letter: the list's row of an HTML letter with its photo
    /// by `cid:` has the paperclip, named or not, and a plain letter's has
    /// none.
    func testTheListsRowHasThePaperclip() async throws {
        let server = ScriptedIMAPServer(inboxCount: 1)
        let suite = "RowQuotesPaperLikeMailTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = IMAPMailRepository(
            account: server.account, password: server.password, transport: server.transportFactory,
            recipients: RecipientBook(defaults: defaults), signatureImages: { [] },
            shelf: keptShelf(for: server.account))
        var uids: [(uid: UInt32, clip: Bool)] = []
        let listed = [shapes[0], shapes[3], shapes[5]]
        XCTAssertEqual(listed.map(\.clip), [true, true, false])
        for (i, shape) in listed.enumerated() {
            let letter = Server.Letter(from: Server.carlo, to: [Server.owner], subject: shape.name,
                                       date: Server.newestDate.addingTimeInterval(Double(i + 1) * 60),
                                       text: "", messageID: "<shape\(i)@example.net>")
            uids.append((try XCTUnwrap(server.deliver(described: Data(shape.raw.utf8), as: letter,
                                                      to: [Server.inbox])[Server.inbox]), shape.clip))
        }
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        for (uid, clip) in uids {
            let row = try XCTUnwrap(rows.first { $0.id.hasSuffix("/\(uid)") })
            XCTAssertEqual(row.hasAttachment, clip, row.subject)
        }
        XCTAssertEqual(server.violations, [])
    }

    // MARK: - A1: a draft kept on the iPad

    /// Whom the kept drafts are to, as the composer's field keeps them.
    private static let to = "Carlo <carlo@example.org>"

    /// The signature's logo as Settings keeps it, under the Content-ID its
    /// markup shows it by.
    private static let logo = SignatureImages.InlineImage(
        contentID: "sig-logo@example.net", filename: "logo.png", mimeType: "image/png",
        dataBase64: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).base64EncodedString())

    /// A letter kept on the iPad has in Drafts the paperclip the row of its
    /// copy on the server will have once Drafts is fetched: under "On this
    /// iPad only", as the copy it became until then, and reopened from that
    /// copy, whose signature's pictures are no rows of his. The copy is the
    /// one the shipping repository APPENDs, read as the list reads a
    /// letter's structure. A letter with markup carries the signature's
    /// pictures, each named in multipart/related, which Mail clips a letter
    /// for; one with no markup, or with no picture that goes, has no
    /// paperclip.
    /// Before, the row counted his files alone and gained the paperclip by
    /// itself when Drafts was next fetched.
    func testAKeptDraftsRowHasThePaperclipItsCopyOnTheServerWillHave() async throws {
        let server = ScriptedIMAPServer()
        let suite = "RowQuotesPaperLikeMailTests.kept"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        var signed = server.account
        signed.signature = "Carlo"
        signed.signatureHTML = "<div><b>Carlo</b><br><img src=\"cid:sig-logo@example.net\"></div>"
        var plain = server.account
        plain.signature = "Carlo"
        let broken = SignatureImages.InlineImage(contentID: "sig-logo@example.net", filename: "logo.png",
                                                 mimeType: "image/png", dataBase64: "!!!")
        let untyped = SignatureImages.InlineImage(contentID: "sig-logo@example.net", filename: "logo.png",
                                                  mimeType: "application/octet-stream",
                                                  dataBase64: Self.logo.dataBase64)
        let signedBody = "Yes, Sunday.\n\nCarlo"
        let reply = "Yes, Sunday.\n\nOn Monday, Sam wrote:\n> Lunch on Sunday?"
        let cases: [(name: String, body: String, account: MailAccount,
                     images: [SignatureImages.InlineImage], clip: Bool)] = [
            ("signed, with the logo", signedBody, signed, [Self.logo], true),
            ("signed, with no pictures", signedBody, signed, [], false),
            ("the signature taken off", "Yes, Sunday.", signed, [Self.logo], false),
            ("a signature with no markup", signedBody, plain, [Self.logo], false),
            ("a reply, a signature with no markup", reply, plain, [Self.logo], true),
            ("a picture that will not decode", signedBody, signed, [broken], false),
            // Named and inline all the same: listed as a file.
            ("a picture kept with no picture's type", signedBody, signed, [untyped], true),
        ]
        for c in cases {
            let account = c.account
            let images = c.images
            let repository = IMAPMailRepository(
                account: server.account, password: server.password, transport: server.transportFactory,
                saved: { account }, recipients: RecipientBook(defaults: defaults),
                signatureImages: { images }, shelf: keptShelf(for: server.account))
            let draft = Draft(to: [Self.to], subject: c.name, body: c.body)
            let saved = try await repository.saveDraft(draft)
            let id = try XCTUnwrap(saved)
            let uid = try XCTUnwrap(id.split(separator: "/").last.flatMap { UInt32($0) })
            let raw = try XCTUnwrap(server.raw(uid: uid, in: Server.drafts))
            let onServer = IMAPMailRepository.hasAttachment(MIMEDecoder.parseStructure(raw))
            XCTAssertEqual(onServer, c.clip, c.name)

            let signing = LocalDraft.Signing(account: account, images: images)
            func kept(_ draft: Draft) -> LocalDraft {
                LocalDraft(key: "letter-1", draft: draft, version: "v", tried: [], unfinished: false,
                           keptAt: Server.newestDate, account: server.account.address, gone: false)
            }
            XCTAssertEqual(kept(draft).row(in: Server.drafts, from: "Owner", signing: signing)
                .hasAttachment, onServer, c.name)
            XCTAssertEqual(kept(draft).row(in: Server.drafts, from: "Owner", onServerAs: id,
                                           signing: signing).hasAttachment, onServer, c.name)
            let decoded = MIMEDecoder.decodeMessage(raw)
            let copy = Message(id: id, mailboxID: Server.drafts, sender: "Owner",
                               senderAddress: server.account.address, to: [Self.to], cc: [],
                               subject: c.name, date: Server.newestDate, textBody: decoded.text,
                               htmlBody: decoded.html, attachments: decoded.attachments)
            let reopened = Draft.reopening(copy, signatureImages: images)
            XCTAssertEqual(reopened.attachments.count, 0, c.name)
            XCTAssertEqual(kept(reopened).row(in: Server.drafts, from: "Owner", signing: signing)
                .hasAttachment, onServer, c.name)
        }
        XCTAssertEqual(server.violations, [])
    }

    /// Whether a letter goes with markup, asked without making it, is what
    /// making it says: plain words, a signature with markup or without, a
    /// reply's and a forward's quote in the words, a quote kept as given or
    /// changed, and one of his photos among his words.
    func testMakesMarkupIsWhatTheLetterMakes() {
        var signed = ScriptedIMAPServer().account
        signed.signature = "Carlo"
        signed.signatureHTML = "<div><b>Carlo</b></div>"
        var plain = signed
        plain.signatureHTML = ""
        let region = "On Monday, Sam wrote:\n> Lunch on Sunday?"
        func draft(_ body: String, quote: Bool = false, photo: Bool = false) -> Draft {
            var draft = Draft(to: [Self.to], subject: "Lunch", body: body)
            if quote {
                draft.quote = QuotedOriginal(kind: .reply, region: region, html: "<p>Lunch on Sunday?</p>",
                                             pictures: [])
            }
            if photo {
                draft.attachments = [DraftAttachment(source: .localFile(URL(fileURLWithPath: "/staged/1/IMG_1.jpg")),
                                                     filename: "IMG_1.jpg", mimeType: "image/jpeg", size: 10)]
            }
            return draft
        }
        let drafts = [
            draft("Yes, Sunday."),
            draft("Yes, Sunday.\n\nCarlo"),
            draft("Yes, Sunday.\n\n" + region),
            draft("Yes, Sunday.\n\n" + region, quote: true),
            draft("Yes, Sunday.\n\nOn Monday, Sam wrote:\n> Lunch, changed.", quote: true),
            draft("Yes, Sunday.\n\nBegin forwarded message:\n\nFrom: Sam\nLunch on Sunday?"),
            draft("Yes, Sunday.", photo: true),
        ]
        var made: [Bool] = []
        for account in [signed, plain] {
            for (n, draft) in drafts.enumerated() {
                let markup = AppleMailHTML.letter(for: draft, account: account).html != nil
                XCTAssertEqual(AppleMailHTML.makesMarkup(for: draft, account: account), markup,
                               "\(account.signatureHTML.isEmpty ? "plain" : "signed") \(n)")
                made.append(markup)
            }
        }
        XCTAssertEqual(made, [false, true, true, true, true, true, true,
                              false, false, true, true, true, true, true])
    }

    // MARK: - A2: the preview

    /// Mail's previews of the round's two quoted letters: "Yes, Sunday.
    /// Sam" and "Yes.", the quoted lines, the `>From ` line and the
    /// "wrote:" line above them left out; through the repository's
    /// preview of a fetched part too.
    func testAQuotedPlainLettersPreviewIsItsOwnWords() throws {
        XCTAssertEqual(PreviewText.fromPlainText(samPlain), "Yes, Sunday. Sam")
        XCTAssertEqual(PreviewText.fromPlainText(floFlowed), "Yes.")
        XCTAssertEqual(PreviewText.fromPlainText(samPlain.replacingOccurrences(of: "\n", with: "\r\n")),
                       "Yes, Sunday. Sam")
        let raw = Data((Self.header + "Content-Type: text/plain; charset=utf-8\r\n\r\n"
                        + samPlain.replacingOccurrences(of: "\n", with: "\r\n")).utf8)
        let parsed = MIMEDecoder.parse(raw)
        let part = try XCTUnwrap(MIMEDecoder.previewPart(parsed.structure))
        let body = try XCTUnwrap(parsed.bodies[part.section])
        XCTAssertEqual(IMAPMailRepository.preview(from: body, part: part), "Yes, Sunday. Sam")
    }

    /// Only what was seen is left out: a line above a quote that does not
    /// end "wrote:", one with a blank line between, a mark after a space or
    /// in a line stay; a letter of nothing but quotes is as it was; an
    /// HTML letter's quote is as it was; a letter with no quote is as it was.
    func testOnlyQuotesAndTheirWroteLineAreLeftOut() {
        XCTAssertEqual(PreviewText.fromPlainText("See below:\n> Quoted.\nAbove it."), "See below: Above it.")
        XCTAssertEqual(PreviewText.fromPlainText("Sam wrote:\n\n> Quoted.\nYes."), "Sam wrote: Yes.")
        XCTAssertEqual(PreviewText.fromPlainText(" > Not a quote.\nTwo > one."), "> Not a quote. Two > one.")
        XCTAssertEqual(PreviewText.fromPlainText("Sam wrote:\n> One.\n> Two."), "Sam wrote: > One. > Two.")
        XCTAssertEqual(PreviewText.fromPlainText("I wrote:"), "I wrote:")
        XCTAssertEqual(PreviewText.fromPlainText("Dear Sam,\n\nThe roses."), "Dear Sam, The roses.")
        XCTAssertEqual(PreviewText.fromHTML("<p>Yes.</p><blockquote type=\"cite\">Quoted.</blockquote>"),
                       "Yes. Quoted.")
        XCTAssertEqual(PreviewText.withoutQuotes("No quote > here."), "No quote > here.")
    }

    // MARK: - A3, A4: the quotes in the pane

    private func html(_ text: String, flowed: Bool = false) -> String {
        PlainQuotes.html(Substring(text), flowed: flowed, escaping: .ampersandAndLessThan)
    }

    /// The round's letter as Mail drew it: "On Monday, Carlo wrote:" inside
    /// the first quote, at its first level, and "From the store's line." a
    /// quote of one level, its mark not shown.
    func testTheWroteLineAndTheFromLineAreInsideTheQuote() {
        let link = "<a href=\"https://example.com/b147\">https://example.com/b147</a>"
        XCTAssertEqual(html(samPlain),
                       "Yes, Sunday.\n\n\(open)On Monday, Carlo wrote:\nLunch on Sunday?\n"
                       + "\(open)Or Saturday?\nThe garden is ready.\n\(open)Three deep.\n\(open)Four deep.\n"
                       + "\(close)\(close)\(close)See \(link)\nBack to one.\nFrom the store's line.\n"
                       + "\(close)\nSam\n")
        // Flowed or not, a ">From " line is a quote of one level.
        for flowed in [false, true] {
            XCTAssertEqual(html(">From here to there.", flowed: flowed), "\(open)From here to there.\(close)")
        }
        // Above a deeper quote, the line goes in at the first level.
        XCTAssertEqual(html("Sam wrote:\n>> Two.\nYes."), "\(open)Sam wrote:\n\(open)Two.\n\(close)\(close)Yes.")
        XCTAssertEqual(html("Sam wrote:  \r\n> One."), "\(open)Sam wrote:  \r\nOne.\(close)")
    }

    /// Only a line ending "wrote:" directly above a quote: one ending
    /// otherwise, one with a blank line between, and one with no quote
    /// under it are drawn as before, outside.
    func testOtherLinesAboveAQuoteAreAsBefore() {
        XCTAssertEqual(html("See below:\n> Quoted."), "See below:\n\(open)Quoted.\(close)")
        XCTAssertEqual(html("Sam wrote:\n\n> Quoted."), "Sam wrote:\n\n\(open)Quoted.\(close)")
        XCTAssertEqual(html("Sam wrote:\nYes."), TextLinks.plain(Substring("Sam wrote:\nYes."),
                                                                 escaping: .ampersandAndLessThan))
        XCTAssertEqual(html("I wrote:"), "I wrote:")
        XCTAssertEqual(PlainQuotes.isAttribution(Array("On Monday, Carlo wrote: \t\r".utf8), from: 0, to: 26),
                       true)
        XCTAssertEqual(PlainQuotes.isAttribution(Array("rote:".utf8), from: 0, to: 5), false)
    }

    // MARK: - A5: the quotes on paper

    /// On paper the same: the "wrote:" line and the `>From ` line inside
    /// the light first-level quote, as Mail prints them.
    func testOnPaperTheWroteLineAndTheFromLineAreInsideTheQuote() throws {
        let m = PaneLetters.letter(text: samPlain)
        let page = PrintPage.letter(m, style: .init(senderPointSize: 17, metaPointSize: 15, subjectPointSize: 18,
                                                    bodyPointSize: 17, lineHeight: 1.41),
                                    size: { "\($0) bytes" })
        XCTAssertTrue(page.contains("<div id=\"bm\">Yes, Sunday.\n\n\(open)On Monday, Carlo wrote:\n"
                                    + "Lunch on Sunday?\n\(open)"), page)
        XCTAssertTrue(page.contains("Back to one.\nFrom the store's line.\n\(close)\nSam\n</div>"), page)
        XCTAssertFalse(page.contains("&gt;From the") || page.contains(">From the"), page)
        let sheet = try XCTUnwrap(page.components(separatedBy: "</style>").first)
        XCTAssertTrue(sheet.contains(QuoteBars.css(in: "#bm")), sheet)
    }

    // MARK: - A6, A7: the printed header and date

    private let posix = Locale(identifier: "en_US_POSIX")
    private let utc = TimeZone(identifier: "UTC")!

    /// Mail's lines, in its order, with its words: From, Subject, Date,
    /// To, each name with its address; the date the medium date and the
    /// medium time, its seconds, never the pane's long form.
    func testThePrintedHeaderIsMailsLabelledLines() {
        let m = Message(id: "7/3", mailboxID: "INBOX", sender: "\"Sam Plain\" <sam.b147@example.net>",
                        senderAddress: "sam.b147@example.net", to: ["Carlo <owner@example.com>"], cc: [],
                        subject: "R6 B-147 plain rm", date: Date(timeIntervalSince1970: 1_793_107_545),
                        textBody: samPlain, htmlBody: nil, attachments: [])
        let head = PrintPage.head(m, size: { "\($0)" }, locale: posix, timeZone: utc)
        XCTAssertEqual(head.lines.map(\.label), ["From:", "Subject:", "Date:", "To:"])
        XCTAssertEqual(head.from, .init(name: "Sam Plain", address: "sam.b147@example.net"))
        XCTAssertEqual(head.to, [.init(name: "Carlo", address: "owner@example.com")])
        XCTAssertEqual(head.lines.map(PrintPage.inWords), [
            "From: Sam Plain sam.b147@example.net", "Subject: R6 B-147 plain rm",
            "Date: " + head.date, "To: Carlo owner@example.com",
        ])
        // The medium date and the medium time, as the iPad's formatter
        // writes them: Oct 27, 2026, and 1:25:45 PM with its seconds.
        let formatter = DisplayDates.formatter(.mediumDateAndMediumTime, locale: posix, timeZone: utc)
        XCTAssertEqual(head.date, formatter.string(from: m.date))
        XCTAssertEqual(formatter.dateStyle, .medium)
        XCTAssertEqual(formatter.timeStyle, .medium)
        XCTAssertTrue(head.date.hasPrefix("Oct 27, 2026"), head.date)
        XCTAssertTrue(head.date.contains("1:25:45"), head.date)
        XCTAssertNotEqual(head.date, MailFormat.fullTimestamp(m.date, locale: posix, timeZone: utc))
        XCTAssertEqual(MailFormat.printedTimestamp(m.date, locale: posix, timeZone: utc), head.date)
    }
}
