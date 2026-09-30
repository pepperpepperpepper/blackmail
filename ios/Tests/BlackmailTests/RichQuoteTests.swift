import XCTest
@testable import Blackmail

/// Reply and Forward send the original as it looked (B-050).
///
/// The composer stays plain text (D-013), and the letter's text/plain part
/// is exactly what it was. The HTML twin now carries the original's own
/// markup inside Mail's quote, under Mail's attribution or its "Begin
/// forwarded message:" block, as long as he has not touched the quote; a
/// forward's pictures go as related parts under Content-IDs of their own,
/// and a reply carries none of the original's parts. Once he has touched
/// the quote, the HTML shows only what he left.
///
/// Each letter here is built and read back with the app's own MIME reader,
/// so what is checked is what a recipient's client would be handed. The
/// first half builds with the same pieces the repository uses; the second
/// runs the shipping repository over the scripted server, with a submission
/// server on port 465 that keeps what it is given.
final class RichQuoteTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    // MARK: - Him, and the letter he answers

    private let signature = "Sam Example\n555-555-0142"
    private let signatureHTML = "<div dir=\"ltr\"><table><tr><td><img src=\"cid:sig-logo\" "
        + "width=\"35\" height=\"25\"></td><td><b>Sam Example</b></td></tr></table></div>"
    private let logoBytes = Data((0..<900).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) })

    private var logo: SignatureImages.InlineImage {
        SignatureImages.InlineImage(contentID: "sig-logo", filename: "logo.png",
                                    mimeType: "image/png",
                                    dataBase64: logoBytes.base64EncodedString())
    }

    private var account: MailAccount {
        MailAccount(address: "sam@example.com", username: "sam@example.com",
                    displayName: "Sam Example", signature: signature,
                    signatureHTML: signatureHTML)
    }

    /// Jane's photograph and her own logo, both shown in her letter by
    /// `cid:`. Her logo's id is the same as his signature's.
    private let gardenBytes = Data((0..<1200).map { UInt8(truncatingIfNeeded: $0 &* 11 &+ 5) })
    private let janeLogoBytes = Data((0..<600).map { UInt8(truncatingIfNeeded: $0 &* 3 &+ 17) })
    private let programmeBytes = Data("%PDF-1.4 the programme".utf8)

    private let originalHTML = """
        <html><head><style>p { margin: 0 }</style></head><body style="margin: 0">\
        <table width="600"><tr><td style="color: #333333;">\
        <p>Here is the <b>garden</b> in June.</p>\
        <img src="cid:ii_garden01" width="400" alt="The garden">\
        <p>Tickets at <a href="https://example.com/tickets?day=sat&amp;n=2">the box office</a>.</p>\
        <p>Second paragraph he may cut.</p>\
        </td></tr></table>\
        <p><img src="cid:sig-logo" width="35"> Jane Example</p>\
        </body></html>
        """

    private let originalText = """
        Here is the garden in June.

        Tickets at the box office: https://example.com/tickets

        Second paragraph he may cut.

        Jane Example
        """

    private let when = Date(timeIntervalSince1970: 1_790_000_000)

    private func original(text: String? = nil, html: String? = nil, cc: [String] = [],
                          plainOnly: Bool = false, noParts: Bool = false) -> Message {
        Message(id: "600001/41", mailboxID: Server.inbox,
                sender: "Jane Example <jane@example.com>", senderAddress: "jane@example.com",
                to: ["sam@example.com"], cc: cc, subject: "The garden", date: when,
                textBody: text ?? originalText,
                htmlBody: plainOnly ? nil : (html ?? originalHTML),
                attachments: plainOnly || noParts ? [] : [
                    Attachment(id: "2", filename: "garden.jpg", mimeType: "image/jpeg",
                               size: 1200, contentID: "ii_garden01", isInline: true),
                    Attachment(id: "3", filename: "logo.png", mimeType: "image/png",
                               size: 600, contentID: "sig-logo", isInline: true),
                    Attachment(id: "4", filename: "Programme.pdf", mimeType: "application/pdf",
                               size: 22),
                ],
                messageID: "<garden-1@example.com>")
    }

    private var originalParts: [String: Data] {
        ["2": gardenBytes, "3": janeLogoBytes, "4": programmeBytes]
    }

    private func reply(_ m: Message? = nil) -> Draft {
        Draft.replying(to: m ?? original(), all: false, myAddress: "sam@example.com",
                       signature: signature)
    }

    private func forward(_ m: Message? = nil) -> Draft {
        Draft.forwarding(m ?? original(), signature: signature)
    }

    // MARK: - Building and reading back

    /// The letter as the repository builds it (`send`), with the parts'
    /// bytes handed in rather than fetched.
    private func built(_ draft: Draft, forDraft: Bool = false) -> Data {
        let letter = AppleMailHTML.letter(for: draft, account: account,
                                          reserving: SignatureImages.contentIDs(of: [logo]),
                                          forDraft: forDraft)
        let parts = originalParts
        func bytes(_ source: DraftAttachment.Source) -> Data {
            guard case let .messagePart(_, _, section) = source else { return Data() }
            return parts[section] ?? Data()
        }
        return RFC5322Builder.build(
            draft: draft, from: account, date: when, messageID: "<built@example.com>",
            attachments: letter.files.map { ($0.filename, $0.mimeType, bytes($0.source)) },
            includeBcc: forDraft,
            htmlBody: letter.html,
            inlineImages: SignatureImages.parts(of: [logo]) + letter.pictures.map {
                ($0.contentID, $0.picture.filename, $0.picture.mimeType,
                 bytes($0.picture.source))
            })
    }

    private struct Part: Equatable {
        let filename: String
        let contentID: String?
        let isInline: Bool
        let data: Data
    }

    /// A letter as a reader's client is handed it.
    private struct Sent {
        /// The text/plain part as it is on the wire, still quoted-printable.
        var plainWire = Data()
        var plain = ""
        var html = ""
        /// Every part but the words.
        var parts: [Part] = []
    }

    private func read(_ raw: Data) -> Sent {
        let parsed = MIMEDecoder.parse(raw)
        let decoded = MIMEDecoder.flatten(parsed.structure) { parsed.bodies[$0.section] }
        var sent = Sent()
        func walk(_ part: MIMEPart) {
            if part.mimeType == "text/plain", sent.plainWire.isEmpty {
                sent.plainWire = parsed.bodies[part.section] ?? Data()
            }
            part.children.forEach(walk)
        }
        walk(parsed.structure)
        sent.plain = decoded.text ?? ""
        sent.html = decoded.html ?? ""
        sent.parts = decoded.attachments.map { a in
            let encoding = MIMEDecoder.part(at: a.id, in: parsed.structure)?.encoding ?? "7bit"
            return Part(filename: a.filename, contentID: a.contentID, isInline: a.isInline,
                        data: MIMEDecoder.decodeTransfer(parsed.bodies[a.id] ?? Data(),
                                                         encoding: encoding))
        }
        return sent
    }

    /// What the HTML holds inside the quote's last cite blockquote: the
    /// original, as the letter shows it.
    private func quoted(_ html: String) -> String {
        let open = "<blockquote type=\"cite\"><div dir=\"ltr\">"
        guard let at = html.range(of: open, options: .backwards) else { return "" }
        return String(html[at.upperBound...])
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: - Reply

    func testAReplyQuotesTheOriginalsOwnMarkupInsideMailsQuote() {
        let sent = read(built(reply()))

        // Mail's attribution, in its own cite blockquote, and the original
        // in the one beside it: the shape read off his device.
        let attribution = AppleMailHTML.escape(MailFormat.quoteAttribution(
            when, sender: "Jane Example <jane@example.com>"))
        XCTAssertTrue(sent.html.contains("<div dir=\"ltr\"><br><blockquote type=\"cite\">"
                                         + attribution + "<br><br></blockquote></div>"),
                      sent.html)
        let quote = quoted(sent.html)
        XCTAssertTrue(quote.contains("<table width=\"600\"><tr><td style=\"color: #333333;\">"),
                      quote)
        XCTAssertTrue(quote.contains("<p>Here is the <b>garden</b> in June.</p>"), quote)
        XCTAssertTrue(quote.contains("<a href=\"https://example.com/tickets?day=sat&amp;n=2\">"
                                     + "the box office</a>"), quote)
        XCTAssertTrue(sent.html.hasSuffix("</div></blockquote></body></html>"), sent.html)
        // Her document's wrapper and stylesheet are hers, not the letter's.
        XCTAssertFalse(sent.html.contains("<style"), sent.html)
        XCTAssertFalse(sent.html.contains("margin: 0"), sent.html)
        XCTAssertEqual(occurrences(of: "<body", in: sent.html), 1)
    }

    func testReplyAllQuotesTheSameWay() {
        let draft = Draft.replying(to: original(cc: ["carlo@example.org"]), all: true,
                                   myAddress: "sam@example.com", signature: signature)
        XCTAssertEqual(draft.cc, ["carlo@example.org"])
        XCTAssertTrue(quoted(read(built(draft)).html).contains("<b>garden</b>"))
    }

    func testAForwardsPicturesGoInlineUnderIDsOfTheirOwnAndHisLogoOnce() {
        let sent = read(built(forward()))

        // His logo once, under his signature's id, and shown once: by his
        // signature. Her logo was written `cid:sig-logo` too, and must not
        // be shown as his, nor his as hers.
        XCTAssertEqual(sent.parts.filter { $0.data == logoBytes }.map(\.contentID), ["sig-logo"])
        XCTAssertEqual(occurrences(of: "cid:sig-logo", in: sent.html), 1, sent.html)

        // Her photograph and her logo, once each, inline, each under an id
        // of its own.
        let garden = sent.parts.filter { $0.data == gardenBytes }
        let hers = sent.parts.filter { $0.data == janeLogoBytes }
        XCTAssertEqual(garden.map(\.isInline), [true])
        XCTAssertEqual(hers.map(\.isInline), [true])
        XCTAssertNotEqual(hers.first?.contentID, "sig-logo")

        // Every Content-ID once, every one shown by the markup, and nothing
        // shown that the letter does not carry.
        let ids = sent.parts.compactMap(\.contentID)
        XCTAssertEqual(ids.count, 3, "\(sent.parts.map(\.filename))")
        XCTAssertEqual(Set(ids).count, ids.count, "\(ids)")
        XCTAssertEqual(QuotedMarkup.contentIDs(shownBy: sent.html), Set(ids))
        XCTAssertTrue(quoted(sent.html).contains("<img src=\"cid:\(garden.first?.contentID ?? "?")\" "
                                                 + "width=\"400\" alt=\"The garden\">"))
    }

    func testAReplyCarriesNoneOfTheOriginalsPartsAndLeavesOutWhatShowedThem() {
        // A reply has never carried the original's parts: every reply to a
        // letter of photographs would send the photographs back, with no
        // row to show they were going. The rest of the letter still goes as
        // it looked, its pictures on the web included.
        let html = originalHTML.replacingOccurrences(
            of: "<p>Second paragraph he may cut.</p>",
            with: "<p><img src=\"https://example.com/map.png\" alt=\"Map\"> Second paragraph.</p>")
        let draft = reply(original(html: html))
        let sent = read(built(draft))

        XCTAssertEqual(sent.parts.map(\.contentID), ["sig-logo"], "\(sent.parts.map(\.filename))")
        XCTAssertEqual(sent.parts.map(\.data), [logoBytes])
        let quote = quoted(sent.html)
        XCTAssertFalse(quote.contains("cid:"), quote)
        XCTAssertFalse(quote.contains("alt=\"The garden\""), "its <img> goes with it")
        XCTAssertTrue(quote.contains("<p>Here is the <b>garden</b> in June.</p>"), quote)
        XCTAssertTrue(quote.contains("<img src=\"https://example.com/map.png\" alt=\"Map\">"),
                      quote)
        XCTAssertEqual(occurrences(of: "cid:sig-logo", in: sent.html), 1,
                       "his logo, by his signature")

        // So there is nothing of hers to fetch at Send or at Save Draft.
        let letter = AppleMailHTML.letter(for: draft, account: account, reserving: ["sig-logo"])
        XCTAssertTrue(letter.pictures.isEmpty)
        XCTAssertTrue(letter.files.isEmpty)
    }

    func testAPartTheMarkupDoesNotShowStaysBehindOrGoesAsAFile() {
        // Some senders give their files Content-IDs too. A part the markup
        // does not show is a file, not a picture in the letter: a forward
        // sends it as the file it was, and a reply leaves it behind, as it
        // leaves everything of hers.
        let m = Message(id: "600001/42", mailboxID: Server.inbox,
                        sender: "Jane Example <jane@example.com>",
                        senderAddress: "jane@example.com", to: ["sam@example.com"], cc: [],
                        subject: "The garden", date: when, textBody: originalText,
                        htmlBody: originalHTML,
                        attachments: [
                            Attachment(id: "2", filename: "garden.jpg", mimeType: "image/jpeg",
                                       size: 1200, contentID: "ii_garden01", isInline: true),
                            Attachment(id: "4", filename: "Programme.pdf",
                                       mimeType: "application/pdf", size: 22,
                                       contentID: "programme@example.com"),
                        ])
        let replied = read(built(reply(m)))
        XCTAssertEqual(replied.parts.map(\.contentID), ["sig-logo"],
                       "\(replied.parts.map(\.filename))")

        let forwarded = read(built(forward(m)))
        XCTAssertEqual(forwarded.parts.filter { $0.data == programmeBytes }.map(\.isInline),
                       [false])
        XCTAssertEqual(forwarded.parts.filter { $0.data == gardenBytes }.map(\.isInline), [true])
    }

    // MARK: - Forward

    func testAForwardCarriesTheOriginalUnderMailsForwardHeader() {
        let m = original(cc: ["Carlo <carlo@example.org>"])
        let sent = read(built(forward(m)))

        XCTAssertTrue(sent.html.contains(
            "<div dir=\"ltr\"><br><br><br>Begin forwarded message:<br><br></div>"
            + "<blockquote type=\"cite\"><div dir=\"ltr\">"
            + "<b>From:</b> Jane Example &lt;jane@example.com&gt;<br>"
            + "<b>Date:</b> \(MailFormat.forwardedDate(when))<br>"
            + "<b>To:</b> sam@example.com<br>"
            + "<b>Cc:</b> Carlo &lt;carlo@example.org&gt;<br>"
            + "<b>Subject:</b> <b>The garden</b><br><br></div></blockquote>"), sent.html)
        let quote = quoted(sent.html)
        XCTAssertTrue(quote.contains("<table width=\"600\">"), quote)
        XCTAssertTrue(quote.contains("<a href=\"https://example.com/tickets?day=sat&amp;n=2\">"),
                      quote)
        // Who else had it, in the words he sees too.
        XCTAssertTrue(sent.plain.contains("To: sam@example.com\nCc: Carlo <carlo@example.org>\n"
                                          + "Subject: The garden\n"), sent.plain)
    }

    func testAForwardSendsItsShownPicturesInlineAndItsFilesAsFiles() {
        let draft = forward()
        // The composer lists every part, as it always has, so he can see
        // what the forward weighs and take any of it off.
        XCTAssertEqual(draft.attachments.map(\.filename),
                       ["garden.jpg", "logo.png", "Programme.pdf"])

        let sent = read(built(draft))
        XCTAssertEqual(sent.parts.filter { $0.data == gardenBytes }.map(\.isInline), [true])
        XCTAssertEqual(sent.parts.filter { $0.data == janeLogoBytes }.map(\.isInline), [true])
        XCTAssertEqual(sent.parts.filter { $0.data == programmeBytes }.map(\.isInline), [false])
        // What raises a paperclip: the programme, and nothing else.
        XCTAssertEqual(sent.parts.filter { !$0.isInline }.map(\.filename), ["Programme.pdf"])
        XCTAssertEqual(sent.parts.count, 4, "\(sent.parts.map(\.filename))")
    }

    func testAPictureHeTookOffAForwardDoesNotGoAtAll() {
        var draft = forward()
        draft.attachments.removeAll { $0.filename == "garden.jpg" }
        let sent = read(built(draft))

        XCTAssertFalse(sent.parts.contains { $0.data == gardenBytes })
        XCTAssertFalse(sent.html.contains("The garden\""), "its <img> goes with it")
        XCTAssertTrue(quoted(sent.html).contains("<table width=\"600\">"),
                      "the rest of the original still goes as it looked")
    }

    // MARK: - What he sees is what goes

    func testAnEditedQuoteFallsBackToWhatHeLeftAndNeverSendsWhatHeCut() {
        var draft = reply()
        draft.body = draft.body.replacingOccurrences(of: "> Second paragraph he may cut.\n",
                                                     with: "")
        XCTAssertFalse(draft.body.contains("Second paragraph"))
        let sent = read(built(draft))

        XCTAssertFalse(sent.html.contains("Second paragraph"), "he cut it from the letter he saw")
        XCTAssertFalse(quoted(sent.html).contains("<table"),
                       "the original's markup is not what he left")
        XCTAssertFalse(sent.html.contains("width=\"600\""), sent.html)
        XCTAssertFalse(sent.parts.contains { $0.data == gardenBytes }, "nor are its pictures")
        // What he left, in Mail's quote, with its address still a link.
        let quote = quoted(sent.html)
        XCTAssertTrue(quote.hasPrefix("Here is the garden in June.<div><br></div>"), quote)
        XCTAssertTrue(quote.contains("<div>Tickets at the box office: "
                                     + "<a href=\"https://example.com/tickets\">"
                                     + "https://example.com/tickets</a></div>"), quote)
    }

    func testAWordChangedInsideTheQuoteIsAnEditToo() {
        var draft = forward()
        draft.body = draft.body.replacingOccurrences(of: "garden in June", with: "garden in May")
        let sent = read(built(draft))
        XCTAssertFalse(sent.html.contains("June"), sent.html)
        XCTAssertTrue(sent.html.contains("garden in May"), sent.html)
        // A forward he has changed sends its pictures as it always did, as
        // the files he can see listed.
        XCTAssertEqual(sent.parts.filter { $0.data == gardenBytes }.map(\.isInline), [false])
    }

    func testADeletedQuoteSendsNothingOfTheOriginal() {
        var draft = reply()
        draft.body = "Lovely." + Draft.signatureBlock(signature)
        let sent = read(built(draft))

        XCTAssertFalse(sent.html.contains("blockquote"), sent.html)
        XCTAssertFalse(sent.html.contains("garden"), sent.html)
        XCTAssertEqual(sent.parts.map(\.contentID), ["sig-logo"])
    }

    func testWhatHeTypesAboveTheQuoteDoesNotCountAsAnEdit() {
        var draft = reply()
        draft.body = "Lovely, thank you." + draft.body
        let sent = read(built(draft))
        XCTAssertTrue(sent.html.hasPrefix(AppleMailHTML.documentOpen + "Lovely, thank you."))
        XCTAssertTrue(quoted(sent.html).contains("<b>garden</b>"))
    }

    func testWordsTypedOntoTheAttributionLineAreAnEditAndGoWhole() throws {
        // The quote counts as untouched only while it starts a line of its
        // own. Typed straight onto the attribution line, his words would
        // otherwise lose their last byte where the quote is taken off,
        // splitting a character of more than one byte in two.
        let fresh = reply()
        let quote = try XCTUnwrap(fresh.quote)
        for typed in ["Oui, tr\u{E8}s bien", "Oui, d\u{E9}j\u{E0}"] {
            var draft = fresh
            draft.body = typed + quote.region
            XCTAssertFalse(quote.isIntact(in: draft.body), typed)
            // No signature, and no quote a reader could take for one, so
            // the letter goes as the words he sees, whole, with no HTML.
            XCTAssertNil(AppleMailHTML.part(for: draft, account: account), typed)
        }
    }

    // MARK: - A plain-text original

    func testAPlainTextOriginalIsQuotedAsHTMLWithItsAddressesLinked() {
        let m = original(text: "Worth a look: https://en.wikipedia.org/wiki/Mercury_(planet)\n"
                         + "and www.example.org.", plainOnly: true)
        for draft in [reply(m), forward(m)] {
            let quote = quoted(read(built(draft)).html)
            XCTAssertTrue(quote.hasPrefix("Worth a look: "
                                          + "<a href=\"https://en.wikipedia.org/wiki/Mercury_(planet)\">"
                                          + "https://en.wikipedia.org/wiki/Mercury_(planet)</a>"
                                          + "<div>and <a href=\"http://www.example.org\">"
                                          + "www.example.org</a>.</div>"), quote)
        }
    }

    // MARK: - An original that shows nothing, or never closes its head

    func testAnOriginalWhoseMarkupShowsNothingIsQuotedByItsWords() {
        // An empty text/html part, and one made of nothing the sanitizer
        // keeps. The composer showed him the words, so the words go, their
        // address a link, rather than an empty quote.
        let nothingKept = "<html><head><title>x</title></head>"
            + "<body><script>x()</script></body></html>"
        for html in ["", nothingKept] {
            for draft in [reply(original(html: html)), forward(original(html: html))] {
                let quote = quoted(read(built(draft)).html)
                XCTAssertTrue(quote.hasPrefix("Here is the garden in June."), quote)
                XCTAssertTrue(quote.contains("<a href=\"https://example.com/tickets\">"), quote)
            }
        }
    }

    func testAnOriginalThatNeverClosesItsHeadIsQuotedAsItLooked() {
        // HTML lets a sender leave `</head>` out; a browser ends the head at
        // the `<body>`, and so does the quote.
        let html = "<html><head><title>Receipt</title><body>"
            + "<p>Thanks for your <b>order</b>.</p></body></html>"
        let m = original(text: "Thanks for your order.", html: html, noParts: true)
        for draft in [reply(m), forward(m)] {
            let quote = quoted(read(built(draft)).html)
            XCTAssertTrue(quote.hasPrefix("<p>Thanks for your <b>order</b>.</p>"), quote)
        }
    }

    // MARK: - Nothing of the original runs

    func testNoScriptOrEventHandlerInTheOriginalLeavesInHisLetter() {
        let hostile = """
            <html><head><script>alert(1)</script></head><body onload="alert(2)">\
            <p onmouseover="alert(3)">Dear Sam,</p>\
            <img src="cid:ii_garden01" onerror="alert(4)">\
            <a href="javascript:alert(5)">click</a> <a href="https://example.com/ok">fine</a>\
            <iframe src="https://evil.example/"></iframe>\
            <form action="https://evil.example/"><input name="pw"></form>\
            </body></html>
            """
        for draft in [reply(original(html: hostile)), forward(original(html: hostile))] {
            let html = read(built(draft)).html.lowercased()
            for banned in ["<script", "alert", "onload", "onmouseover", "onerror", "javascript",
                           "<iframe", "<form", "<input", "evil.example"] {
                XCTAssertFalse(html.contains(banned), "\(banned) in \(html)")
            }
            XCTAssertTrue(html.contains("<p>dear sam,</p>"), html)
            XCTAssertTrue(html.contains("<a href=\"https://example.com/ok\">fine</a>"), html)
        }
    }

    // MARK: - The words are what they were

    func testThePlainPartIsByteForByteWhatItWasBefore() {
        let m = original()
        // The bodies as `replying` and `forwarding` have always made them.
        let replyBody = Draft.signatureBlock(signature)
            + "\n\n" + MailFormat.quoteAttribution(m.date, sender: m.sender)
            + "\n> " + m.quotableText.replacingOccurrences(of: "\n", with: "\n> ")
        let forwardBody = Draft.signatureBlock(signature)
            + "\n\nBegin forwarded message:\n\n"
            + "From: Jane Example <jane@example.com>\n"
            + "Date: \(MailFormat.forwardedDate(m.date))\n"
            + "To: sam@example.com\n"
            + "Subject: The garden\n\n"
            + m.quotableText

        for (draft, body) in [(reply(m), replyBody), (forward(m), forwardBody)] {
            XCTAssertEqual(draft.body, body)
            let sent = read(built(draft))
            XCTAssertEqual(sent.plainWire, Data(RFC5322Builder.quotedPrintable(body).utf8))
            // And the same bytes as the letter with no original carried at all.
            var flat = draft
            flat.quote = nil
            XCTAssertEqual(read(built(flat)).plainWire, sent.plainWire)
        }
    }

    // MARK: - Size

    /// A newsletter of about `bytes`: row after row of pictures on the web,
    /// links and inline styling, and how many stories it has.
    private func newsletter(bytes: Int) -> (html: String, stories: Int) {
        var html = "<html><head><style>.x { color: red }</style></head><body>"
            + "<table width=\"600\" style=\"margin: 0 auto;\">"
        var n = 0
        while html.utf8.count < bytes {
            n += 1
            html += "<tr><td style=\"padding: 12px; font-family: Georgia, serif; color: #222;\">"
                + "<img src=\"https://img.example.com/story\(n).jpg\" width=\"560\" alt=\"Story \(n)\">"
                + "<h2 style=\"font-size: 20px;\">Story \(n): the week in the garden</h2>"
                + "<p>Some words about story \(n), with <b>bold</b> and <i>italic</i> in them, "
                + "and a <a href=\"https://news.example.com/s/\(n)?utm_source=mail&amp;id=\(n)\">"
                + "link to read more</a>.</p></td></tr>"
        }
        return (html + "</table><p>Last story: \(n)</p></body></html>", n)
    }

    func testANewsletterSizedOriginalStaysWithinTheSizeRules() {
        let (markup, stories) = newsletter(bytes: 256 << 10)
        let m = original(text: "The newsletter, as text.", html: markup, noParts: true)
        let raw = built(forward(m))
        let sent = read(raw)

        // All of it, to the last story, as it looked.
        XCTAssertTrue(sent.html.contains("https://news.example.com/s/1?utm_source=mail&amp;id=1"))
        XCTAssertTrue(sent.html.hasSuffix("<p>Last story: \(stories)</p>"
                                          + "</div></blockquote></body></html>"))
        // Its pictures stay on the web: none is fetched and none is sent.
        XCTAssertTrue(sent.html.contains("<img src=\"https://img.example.com/story1.jpg\""))
        XCTAssertEqual(sent.parts.map(\.contentID), ["sig-logo"])
        // About half as much again as the markup on the wire, far inside
        // Gmail's 35,882,577 bytes.
        XCTAssertLessThan(raw.count, markup.utf8.count * 8 / 5, "\(raw.count) bytes")
    }

    /// A megabyte, as measured for B-050. Seconds of work in the suite's
    /// debug build on a loaded host, so it runs only when
    /// `BLACKMAIL_LARGE_TESTS` is set.
    func testAMegabyteNewsletterIsBuiltInAFewSeconds() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BLACKMAIL_LARGE_TESTS"] != nil,
                          "set BLACKMAIL_LARGE_TESTS to build a megabyte newsletter")
        let (markup, stories) = newsletter(bytes: 1 << 20)
        let m = original(text: "The newsletter, as text.", html: markup, noParts: true)
        let started = Date()
        let raw = built(forward(m))
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertTrue(read(raw).html.hasSuffix("<p>Last story: \(stories)</p>"
                                               + "</div></blockquote></body></html>"))
        XCTAssertLessThan(raw.count, 1_600_000, "\(raw.count) bytes")
        XCTAssertLessThan(elapsed, 5, "\(elapsed) s to build")
    }

    func testMarkupPastTheCeilingGoesAsItsWordsWithTheirLinks() {
        let huge = "<p>Big: https://example.com/big</p>"
            + String(repeating: "<img src=\"data:image/png;base64,iVBORw0KGgo=\">",
                     count: AppleMailHTML.largestQuotedMarkup / 40)
        XCTAssertGreaterThan(huge.utf8.count, AppleMailHTML.largestQuotedMarkup)
        let m = original(text: "Big: https://example.com/big", html: huge, noParts: true)
        let raw = built(forward(m))
        let sent = read(raw)

        XCTAssertFalse(sent.html.contains("data:image"), "the markup is past the ceiling")
        XCTAssertTrue(quoted(sent.html).hasPrefix("Big: <a href=\"https://example.com/big\">"),
                      quoted(sent.html))
        XCTAssertLessThan(raw.count, 100_000)
    }

    // MARK: - Put down and picked up again, by value

    func testASentLetterCarriesNoMarkAndADraftDoes() {
        let sent = read(built(reply())).html
        let saved = read(built(reply(), forDraft: true)).html
        XCTAssertFalse(sent.contains("<!--"), sent)
        XCTAssertEqual(occurrences(of: "<!--bm-quote:", in: saved), 1)
        // The mark is all that differs.
        XCTAssertEqual(saved.replacingOccurrences(
            of: "<!--bm-quote:" + QuotedOriginal.fingerprint(reply().quote?.region ?? "") + "-->",
            with: ""), sent)
    }

    /// A saved draft as `loadMessage` hands it back.
    private func reopened(_ draft: Draft) -> Message {
        let raw = built(draft, forDraft: true)
        let decoded = MIMEDecoder.decodeMessage(raw)
        return Message(id: "600003/9", mailboxID: Server.drafts, sender: "Sam Example",
                       senderAddress: "sam@example.com", to: draft.to, cc: draft.cc,
                       subject: draft.subject, date: when, textBody: decoded.text,
                       htmlBody: decoded.html, attachments: decoded.attachments)
    }

    func testADraftComesBackWithItsQuote() throws {
        let m = reopened(reply())
        let draft = Draft.reopening(m, signatureImages: [logo])
        let quote = try XCTUnwrap(draft.quote)
        XCTAssertEqual(quote.kind, .reply)
        XCTAssertTrue(quote.isIntact(in: draft.body))
        XCTAssertTrue(quote.html?.contains("<b>garden</b>") == true)
        // A reply carried nothing of hers, so nothing of hers comes back.
        XCTAssertEqual(draft.attachments.map(\.filename), [])
        XCTAssertEqual(quote.pictures.map(\.filename), [])
    }

    func testAnEditedQuoteSavedAsADraftComesBackWithItsLinks() throws {
        // A quote he has changed goes as his words with their addresses
        // linked. The draft is marked so the same rendering is taken up
        // again when he reopens it, rather than plain text with none.
        var draft = reply()
        draft.body = draft.body.replacingOccurrences(of: "> Second paragraph he may cut.\n",
                                                     with: "")
        let back = Draft.reopening(reopened(draft), signatureImages: [logo])
        XCTAssertNotNil(back.quote)
        let html = try XCTUnwrap(AppleMailHTML.part(for: back, account: account))
        XCTAssertTrue(quoted(html).contains("<a href=\"https://example.com/tickets\">"
                                            + "https://example.com/tickets</a>"), html)
        XCTAssertFalse(html.contains("Second paragraph"), html)
        XCTAssertFalse(quoted(html).contains("<table"), html)
    }

    func testADraftWhoseTextWasChangedElsewhereComesBackPlain() {
        var m = reopened(reply())
        m = Message(id: m.id, mailboxID: m.mailboxID, sender: m.sender,
                    senderAddress: m.senderAddress, to: m.to, cc: m.cc, subject: m.subject,
                    date: m.date,
                    textBody: m.textBody?.replacingOccurrences(of: "> Second paragraph he may cut.\n",
                                                               with: ""),
                    htmlBody: m.htmlBody, attachments: m.attachments)
        let draft = Draft.reopening(m, signatureImages: [logo])
        XCTAssertNil(draft.quote)
        XCTAssertFalse(AppleMailHTML.part(for: draft, account: account)?
                        .contains("Second paragraph") ?? true)
    }
}

// MARK: - Over the scripted server

/// The same letters, sent and saved by the shipping repository.
final class RichQuoteRepositoryTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "RichQuoteRepositoryTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var submission: RichQuoteSubmissions!
    /// Moved only where a test needs the quiet before a write's probe.
    private var clock: ManualClock!

    private let signature = "Sam Example\n555-555-0142"
    private let signatureHTML = "<div dir=\"ltr\"><img src=\"cid:sig-logo\" width=\"35\"> "
        + "<b>Sam Example</b></div>"
    private let logoBytes = Data((0..<900).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) })
    private let gardenBytes = Data((0..<1200).map { UInt8(truncatingIfNeeded: $0 &* 11 &+ 5) })
    private let programmeBytes = Data("%PDF-1.4 the programme".utf8)

    private var logo: SignatureImages.InlineImage {
        SignatureImages.InlineImage(contentID: "sig-logo", filename: "logo.png",
                                    mimeType: "image/png",
                                    dataBase64: logoBytes.base64EncodedString())
    }

    private var account: MailAccount {
        MailAccount(address: server.username, imapPort: server.port,
                    username: server.username, displayName: "Sam Example",
                    signature: signature, signatureHTML: signatureHTML)
    }

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer(username: "sam@example.com")
        submission = RichQuoteSubmissions()
        clock = ManualClock()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        for outcome in ["ok", "fail"] {
            let transcript = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
            try? FileManager.default.removeItem(atPath: transcript)
        }
        server = nil
        submission = nil
        book = nil
        clock = nil
        super.tearDown()
    }

    private func makeRepository() -> IMAPMailRepository {
        let imap = server.transportFactory
        let submission = self.submission!
        let clock = self.clock!
        let logo = self.logo
        return IMAPMailRepository(
            account: account, password: server.password,
            transport: { host, port in port == 465 ? submission.next() : imap(host, port) },
            recipients: book,
            now: { clock.now() },
            signatureImages: { [logo] })
    }

    /// Jane's letter in the Inbox: a photograph shown by `cid:` and a PDF.
    private func delivered(_ repository: IMAPMailRepository) async throws -> Message {
        let uid = try XCTUnwrap(server.deliver(Server.Letter(
            from: Server.Address(name: "Jane Example", address: "jane@example.com"),
            to: [Server.sam], subject: "The garden", date: Server.newestDate,
            text: "Here is the garden in June.\r\n\r\nTickets: https://example.com/tickets\r\n"
                + "\r\nJane Example\r\n",
            html: "<table width=\"600\"><tr><td><p>Here is the <b>garden</b> in June.</p>"
                + "<img src=\"cid:ii_garden01\" width=\"400\" alt=\"The garden\">"
                + "<p><a href=\"https://example.com/tickets\">Tickets</a></p></td></tr></table>",
            messageID: "<garden-1@example.com>",
            files: [Server.File(name: "garden.jpg", type: "IMAGE", subtype: "JPEG",
                                bytes: gardenBytes, contentID: "ii_garden01"),
                    Server.File(name: "Programme.pdf", type: "APPLICATION", subtype: "PDF",
                                bytes: programmeBytes)]),
            to: [Server.inbox])[Server.inbox])
        let id = "\(server.uidValidity(of: Server.inbox))/\(uid)"
        return try await repository.loadMessage(id: id, mailboxID: Server.inbox)
    }

    /// Another letter read after hers, so hers is no longer the one the
    /// repository has to hand, as in the conversation view when he goes
    /// back to a letter already on screen.
    private func readAnother(_ repository: IMAPMailRepository) async throws {
        let uid = try XCTUnwrap(server.uids(in: Server.inbox).first)
        _ = try await repository.loadMessage(id: "\(server.uidValidity(of: Server.inbox))/\(uid)",
                                             mailboxID: Server.inbox)
    }

    private func uid(of m: Message) throws -> UInt32 {
        try XCTUnwrap(m.id.split(separator: "/").last.flatMap { UInt32($0) })
    }

    private func reply(to m: Message) -> Draft {
        Draft.replying(to: m, all: false, myAddress: server.username, signature: signature)
    }

    private struct Part: Equatable {
        let filename: String
        let contentID: String?
        let isInline: Bool
        let data: Data
    }

    private func read(_ raw: Data) -> (html: String, parts: [Part]) {
        let parsed = MIMEDecoder.parse(raw)
        let decoded = MIMEDecoder.decodeMessage(raw)
        return (decoded.html ?? "", decoded.attachments.map { a in
            let encoding = MIMEDecoder.part(at: a.id, in: parsed.structure)?.encoding ?? "7bit"
            return Part(filename: a.filename, contentID: a.contentID, isInline: a.isInline,
                        data: MIMEDecoder.decodeTransfer(parsed.bodies[a.id] ?? Data(),
                                                         encoding: encoding))
        })
    }

    func testASentReplyCarriesTheOriginalsMarkupAndAsksTheServerForNothing() async throws {
        let repository = makeRepository()
        let m = try await delivered(repository)
        server.clearLog()
        try await repository.send(reply(to: m))
        let letters = await submission.letters()
        let sent = read(try XCTUnwrap(letters.last))

        XCTAssertTrue(sent.html.contains("<p>Here is the <b>garden</b> in June.</p>"), sent.html)
        XCTAssertTrue(sent.html.contains("<a href=\"https://example.com/tickets\">Tickets</a>"))
        // Her photograph stays with her, and the <img> that showed it.
        XCTAssertFalse(sent.parts.contains { $0.data == gardenBytes })
        XCTAssertFalse(sent.html.contains("alt=\"The garden\""), sent.html)
        XCTAssertEqual(sent.parts.map(\.contentID), ["sig-logo"], "\(sent.parts.map(\.filename))")
        // Sent over SMTP alone, as a reply always was.
        XCTAssertEqual(server.log.map(\.command), [])
    }

    // MARK: - A reply never waits on the original

    func testAReplySendsOnceItsOriginalHasGone() async throws {
        let repository = makeRepository()
        let m = try await delivered(repository)
        let draft = reply(to: m)
        // Moved while he wrote, which leaves nothing of it to hand here.
        try await repository.move(m.id, from: Server.inbox, to: Server.allMail)

        try await repository.send(draft)
        let letters = await submission.letters()
        XCTAssertEqual(letters.count, 1)
        XCTAssertTrue(read(try XCTUnwrap(letters.last)).html.contains("<b>garden</b>"))
    }

    func testAReplySavesOnceItsOriginalHasBeenArchivedElsewhere() async throws {
        let repository = makeRepository()
        let m = try await delivered(repository)
        let draft = reply(to: m)
        try await readAnother(repository)
        // Archived on his phone while he wrote. The save's probe, after the
        // quiet, is what tells this connection it has gone.
        server.removeElsewhere(uid: try uid(of: m), from: Server.inbox)
        clock.advance(by: 120)
        let before = server.uids(in: Server.drafts).count

        // Saved from the Cancel sheet after it has closed, where a failure
        // would lose the letter without a word.
        let saved = try await repository.saveDraft(draft)
        XCTAssertNotNil(saved)
        XCTAssertEqual(server.uids(in: Server.drafts).count, before + 1)
    }

    func testAReplySentAfterTheSocketDiedGoesFirstTime() async throws {
        let repository = makeRepository()
        let m = try await delivered(repository)
        let draft = reply(to: m)
        try await readAnother(repository)
        await server.resetConnections()
        server.clearLog()

        try await repository.send(draft)
        let letters = await submission.letters()
        XCTAssertEqual(letters.count, 1)
        XCTAssertEqual(server.log.map(\.command), [], "nothing of the original is fetched")
    }

    // MARK: - A forward fetches its pictures, as it fetches its files

    func testAForwardSentAfterTheSocketDiedFetchesOnANewConnection() async throws {
        let repository = makeRepository()
        let m = try await delivered(repository)
        var draft = Draft.forwarding(m, signature: signature)
        draft.to = ["carlo@example.org"]
        try await readAnother(repository)
        await server.resetConnections()

        // A read, so it is tried once more on a new connection (B-023),
        // and the first Send after a quiet spell goes.
        try await repository.send(draft)
        let letters = await submission.letters()
        let sent = read(try XCTUnwrap(letters.last))
        XCTAssertEqual(sent.parts.filter { $0.data == gardenBytes }.map(\.isInline), [true])
        XCTAssertEqual(sent.parts.filter { !$0.isInline }.map(\.filename), ["Programme.pdf"])
    }

    func testAForwardWhosePictureCannotBeFetchedIsNotSentWithoutIt() async throws {
        let repository = makeRepository()
        let m = try await delivered(repository)
        var draft = Draft.forwarding(m, signature: signature)
        draft.to = ["carlo@example.org"]
        // Only the photograph is left, so its fetch is the only one.
        draft.attachments.removeAll { $0.filename == "Programme.pdf" }
        try await repository.move(m.id, from: Server.inbox, to: Server.allMail)

        // A letter whose markup shows a picture it does not carry arrives
        // with a broken box. It is one of the rows he can see, so the
        // failure names something he can take off.
        do {
            try await repository.send(draft)
            XCTFail("sent without the photograph its quote shows")
        } catch {
            XCTAssertEqual(error as? MailError, .attachmentFailed)
        }
        let letters = await submission.letters()
        XCTAssertEqual(letters.count, 0)
    }

    func testAnEditedReplyPutDownAndPickedUpStillLinksItsAddresses() async throws {
        let repository = makeRepository()
        let m = try await delivered(repository)
        var draft = reply(to: m)
        draft.body = draft.body.replacingOccurrences(of: "garden in June", with: "garden")
        let saved = try await repository.saveDraft(draft)
        let back = try await repository.loadDraft(id: try XCTUnwrap(saved),
                                                  mailboxID: Server.drafts)
        XCTAssertNotNil(back.quote, "the draft's mark brings the quote back")

        try await repository.send(back)
        let letters = await submission.letters()
        let html = read(try XCTUnwrap(letters.last)).html
        XCTAssertTrue(html.contains("<a href=\"https://example.com/tickets\">"
                                    + "https://example.com/tickets</a>"), html)
        XCTAssertFalse(html.contains("in June"), html)
        XCTAssertFalse(html.contains("<table"), html)
    }

    func testASentForwardCarriesThePictureInlineAndTheFileAsAFile() async throws {
        let repository = makeRepository()
        let m = try await delivered(repository)
        var draft = Draft.forwarding(m, signature: signature)
        draft.to = ["carlo@example.org"]
        try await repository.send(draft)
        let letters = await submission.letters()
        let sent = read(try XCTUnwrap(letters.last))

        XCTAssertEqual(sent.parts.filter { $0.data == gardenBytes }.map(\.isInline), [true])
        XCTAssertEqual(sent.parts.filter { !$0.isInline }.map(\.filename), ["Programme.pdf"])
        XCTAssertTrue(sent.html.contains("Begin forwarded message:"))
        XCTAssertTrue(sent.html.contains("<b>garden</b>"))
    }

    func testAReopenedDraftSendsTheSameLetterAsTheFreshOneWould() async throws {
        let repository = makeRepository()
        let m = try await delivered(repository)
        let fresh = Draft.replying(to: m, all: false, myAddress: server.username,
                                   signature: signature)
        try await repository.send(fresh)

        var draft = fresh
        for round in 1...3 {
            let saved = try await repository.saveDraft(draft)
            let id = try XCTUnwrap(saved, "round \(round)")
            draft = try await repository.loadDraft(id: id, mailboxID: Server.drafts)
            XCTAssertNotNil(draft.quote, "round \(round)")
            XCTAssertEqual(draft.attachments.map(\.filename), [], "round \(round): "
                           + "a reply brings nothing of hers back")
        }
        try await repository.send(draft)

        let letters = await submission.letters()
        XCTAssertEqual(letters.count, 2)
        guard letters.count == 2 else { return }
        let first = read(letters[0]), again = read(letters[1])
        XCTAssertEqual(again.html, first.html)
        XCTAssertEqual(again.parts, first.parts)
        XCTAssertTrue(first.html.contains("<b>garden</b>"), first.html)
    }

    func testAReopenedForwardKeepsItsRowsAndStillSendsThePictureInline() async throws {
        let repository = makeRepository()
        let m = try await delivered(repository)
        var draft = Draft.forwarding(m, signature: signature)
        draft.to = ["carlo@example.org"]
        let saved = try await repository.saveDraft(draft)
        let reopened = try await repository.loadDraft(id: try XCTUnwrap(saved),
                                                      mailboxID: Server.drafts)
        XCTAssertEqual(reopened.attachments.map(\.filename).sorted(),
                       ["Programme.pdf", "garden.jpg"])

        try await repository.send(reopened)
        let letters = await submission.letters()
        let sent = read(try XCTUnwrap(letters.last))
        XCTAssertEqual(sent.parts.filter { $0.data == gardenBytes }.map(\.isInline), [true])
        XCTAssertEqual(sent.parts.filter { !$0.isInline }.map(\.filename), ["Programme.pdf"])
        XCTAssertTrue(sent.html.contains("<b>garden</b>"))
    }
}

/// A submission server per connection, and every letter they were given,
/// dot-stuffing undone.
private final class RichQuoteSubmissions: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [ScriptedSubmission] = []

    func next() -> ScriptedSubmission {
        let server = ScriptedSubmission()
        lock.lock()
        made.append(server)
        lock.unlock()
        return server
    }

    private var servers: [ScriptedSubmission] {
        lock.lock()
        defer { lock.unlock() }
        return made
    }

    func letters() async -> [Data] {
        var all: [Data] = []
        for server in servers {
            for stuffed in await server.letters {
                var letter = String(decoding: stuffed, as: UTF8.self)
                    .replacingOccurrences(of: "\r\n..", with: "\r\n.")
                if letter.hasPrefix("..") { letter.removeFirst() }
                all.append(Data(letter.utf8))
            }
        }
        return all
    }
}
