import XCTest
@testable import Blackmail

/// Tests for quoting and threading — the two things reply and forward have
/// to get right and both of which were silently broken.
///
/// Neither failure was visible on the sending device. A reply with no
/// `In-Reply-To` looks perfectly normal in the compose sheet and perfectly
/// normal in Sent Mail; it goes wrong only in the *recipient's* client,
/// which is the one place this project cannot look. That is exactly the
/// shape of bug a unit test is for.
final class ReplyForwardTests: XCTestCase {

    private func message(text: String? = nil, html: String? = nil,
                         messageID: String? = nil, references: String? = nil,
                         subject: String = "Lunch",
                         to: [String] = ["carlo@example.com"], cc: [String] = [],
                         attachments: [Attachment] = []) -> Message {
        Message(id: "1/9", mailboxID: "INBOX",
                sender: "Jane Smith <jane@example.com>", senderAddress: "jane@example.com",
                to: to, cc: cc, subject: subject,
                date: Date(timeIntervalSince1970: 1_700_000_000),
                textBody: text, htmlBody: html, attachments: attachments,
                messageID: messageID, references: references)
    }

    private func pdf(_ name: String, section: String) -> Attachment {
        Attachment(id: section, filename: name, mimeType: "application/pdf", size: 33_000)
    }

    // MARK: - Forward carries the files

    func testForwardCarriesEveryAttachment() {
        // The receipt that started this: two PDFs, both silently left behind.
        let m = message(text: "Your receipt is attached.",
                        attachments: [pdf("Invoice-QX7T2KDA-0001.pdf", section: "2"),
                                      pdf("Receipt-4417-2093-6621.pdf", section: "3")])
        let draft = Draft.forwarding(m)

        XCTAssertEqual(draft.attachments.map(\.filename),
                       ["Invoice-QX7T2KDA-0001.pdf", "Receipt-4417-2093-6621.pdf"])
        // Now that an attachment can also be a file on this device, a
        // forward has to still be the OTHER kind: a part named inside the
        // original message, fetched only when the letter is built.
        let sources: [(String, String, String)] = draft.attachments.compactMap {
            guard case let .messagePart(messageID, mailboxID, section, _) = $0.source
            else { return nil }
            return (messageID, mailboxID, section)
        }
        XCTAssertEqual(sources.count, 2, "both must still reference the message")
        XCTAssertEqual(sources.map(\.2), ["2", "3"],
                       "the MIME section path is what lets the bytes be fetched later")
        XCTAssertEqual(sources.map(\.0), ["1/9", "1/9"])
        XCTAssertEqual(sources.map(\.1), ["INBOX", "INBOX"],
                       "without the mailbox the fetch cannot SELECT the right folder")
    }

    func testReplyDoesNotPostSomebodysOwnFilesBackToThem() {
        let m = message(text: "Here is the photo.",
                        attachments: [pdf("holiday.pdf", section: "2")])
        XCTAssertTrue(Draft.replying(to: m, all: false, myAddress: "me@x.com").attachments.isEmpty)
    }

    func testForwardingAMessageWithNoFilesAttachesNothing() {
        XCTAssertTrue(Draft.forwarding(message(text: "just words")).attachments.isEmpty)
    }

    // MARK: - The bytes that actually get attached

    /// The composition the repository performs to turn a stored MIME part
    /// back into a file: find the part, read its transfer encoding, decode.
    ///
    /// Pinned because skipping the last step shipped a base64 *transcript*
    /// of a PDF as the PDF — 44782 bytes beginning "JVBER" where the file
    /// begins "%PDF". It got all the way onto the wire before anyone looked,
    /// because nothing had ever consumed an attachment's bytes before.
    func testAnAttachmentDecodesToTheFileAndNotToItsBase64() {
        let pdfBytes = Data("%PDF-1.4\nsome binary\u{00}\u{01}\u{02} content".utf8)
        let raw = Data("""
            From: a@b.com\r
            Subject: Receipt\r
            MIME-Version: 1.0\r
            Content-Type: multipart/mixed; boundary="B"\r
            \r
            --B\r
            Content-Type: text/plain; charset=utf-8\r
            \r
            Your receipt is attached.\r
            --B\r
            Content-Type: application/pdf; name="receipt.pdf"\r
            Content-Transfer-Encoding: base64\r
            Content-Disposition: attachment; filename="receipt.pdf"\r
            \r
            \(pdfBytes.base64EncodedString())\r
            --B--\r
            """.utf8)

        let parsed = MIMEDecoder.parse(raw)
        guard let stored = parsed.bodies["2"],
              let part = MIMEDecoder.part(at: "2", in: parsed.structure) else {
            return XCTFail("section 2 not found in \(parsed.bodies.keys.sorted())")
        }

        XCTAssertEqual(part.encoding, "base64")
        XCTAssertTrue(stored.starts(with: Data("JVBER".utf8)),
                      "as stored, a part really is still base64 — that is the trap")

        let file = MIMEDecoder.decodeTransfer(stored, encoding: part.encoding)
        XCTAssertEqual(file, pdfBytes)
        XCTAssertTrue(file.starts(with: Data("%PDF".utf8)))
    }

    func testAQuotedPrintableAttachmentDecodesToo() {
        // Not every attachment is base64; a .txt or .ics often is not.
        let raw = Data("""
            Content-Type: multipart/mixed; boundary="B"\r
            \r
            --B\r
            Content-Type: text/plain\r
            \r
            body\r
            --B\r
            Content-Type: text/calendar; name="invite.ics"\r
            Content-Transfer-Encoding: quoted-printable\r
            Content-Disposition: attachment; filename="invite.ics"\r
            \r
            SUMMARY:Caf=C3=A9 meeting\r
            --B--\r
            """.utf8)

        let parsed = MIMEDecoder.parse(raw)
        let part = MIMEDecoder.part(at: "2", in: parsed.structure)
        XCTAssertEqual(part?.encoding, "quoted-printable")
        let file = MIMEDecoder.decodeTransfer(parsed.bodies["2"] ?? Data(),
                                              encoding: part?.encoding ?? "7bit")
        XCTAssertEqual(String(decoding: file, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                       "SUMMARY:Café meeting")
    }

    func testFindingAPartByAnUnknownSectionReturnsNil() {
        let parsed = MIMEDecoder.parse(Data("Content-Type: text/plain\r\n\r\nhi".utf8))
        XCTAssertNil(MIMEDecoder.part(at: "7.2", in: parsed.structure))
    }

    // MARK: - Subjects

    func testSubjectPrefixesAreNotDoubled() {
        XCTAssertEqual(Draft.forwarding(message(subject: "Fwd: Notice")).subject, "Fwd: Notice")
        XCTAssertEqual(Draft.replying(to: message(subject: "Re: Notice"), all: false,
                                      myAddress: nil).subject, "Re: Notice")
        XCTAssertEqual(Draft.forwarding(message(subject: "Notice")).subject, "Fwd: Notice")
        XCTAssertEqual(Draft.replying(to: message(subject: "Notice"), all: false,
                                      myAddress: nil).subject, "Re: Notice")
    }

    // MARK: - Reply All

    func testReplyAllNeverCCsTheSenderOfTheReply() {
        // The bug this pins CC'd him on every reply he sent, because the
        // comparison was against a hardcoded "me@example.com".
        let m = message(text: "hi",
                        to: ["Carlo <CARLO@Example.com>", "bob@example.com"],
                        cc: ["jane@example.com"])
        let draft = Draft.replying(to: m, all: true, myAddress: "carlo@example.com")

        XCTAssertFalse(draft.cc.contains { $0.lowercased().contains("carlo") },
                       "his own address, in any casing, must not come back at him")
        XCTAssertFalse(draft.cc.contains("jane@example.com"),
                       "the sender is already on the To line")
        XCTAssertEqual(draft.cc, ["bob@example.com"])
    }

    func testReplyAllStripsDisplayNamesFromTheCCList() {
        let m = message(text: "hi", to: ["\"Smith, Bob\" <bob@example.com>"])
        XCTAssertEqual(Draft.replying(to: m, all: true, myAddress: "me@x.com").cc,
                       ["bob@example.com"])
    }

    func testPlainReplyCCsNobody() {
        let m = message(text: "hi", to: ["a@x.com"], cc: ["b@x.com"])
        XCTAssertTrue(Draft.replying(to: m, all: false, myAddress: "me@x.com").cc.isEmpty)
    }

    // MARK: - Threading carried onto the draft

    func testReplyCarriesTheParentsRealMessageIDNotTheInternalOne() {
        // `Message.id` here is "1/9". If that ever reaches the draft, the
        // wire gets `In-Reply-To: <1/9>`, which means nothing to anyone.
        let m = message(text: "hi", messageID: "<parent@example.com>",
                        references: "<older@example.com>")
        let draft = Draft.replying(to: m, all: false, myAddress: nil)

        XCTAssertEqual(draft.inReplyTo, "<parent@example.com>")
        XCTAssertEqual(draft.references, "<older@example.com>")
        XCTAssertNotEqual(draft.inReplyTo, m.id)
    }

    func testForwardClaimsNoAncestor() {
        let m = message(text: "hi", messageID: "<parent@example.com>")
        let draft = Draft.forwarding(m)
        XCTAssertNil(draft.inReplyTo,
                     "a forward starts a new conversation with a new recipient")
        XCTAssertNil(draft.references)
    }

    // MARK: - Apple's quote furniture

    /// The reference date, fixed to a zone, so these can pin exact strings.
    /// 1_700_000_000 is 2023-11-14 22:13:20 UTC.
    private let eastern = TimeZone(identifier: "America/New_York")!

    func testTheAttributionIsApplesToTheCharacter() {
        // This app used to write "Today at 5:13 PM, Jane Smith wrote:" —
        // relative, no leading "On", no address. Three replies deep a thread
        // ends up with a column of "Today"s that were three different days.
        XCTAssertEqual(
            MailFormat.quoteAttribution(Date(timeIntervalSince1970: 1_700_000_000),
                                        sender: "Jane Smith <jane@example.com>",
                                        timeZone: eastern),
            "On Nov 14, 2023, at 5:13\u{202F}PM, Jane Smith <jane@example.com> wrote:")
    }

    func testTheSpaceBeforeAMPMIsTheNarrowNoBreakOne() {
        // U+202F, which is what Apple's formatters emit and what turns up in
        // Sam's own sent mail. Pinned separately because the Linux test host
        // and the iPad ship different ICU versions: anything that took this
        // character from a live formatter would pass here and differ there.
        let line = MailFormat.quoteAttribution(Date(timeIntervalSince1970: 1_700_000_000),
                                               sender: "a@b.com", timeZone: eastern)
        XCTAssertTrue(line.contains("5:13\u{202F}PM"), line)
        XCTAssertFalse(line.contains("5:13 PM"), "an ordinary space is not what Mail sends")
    }

    func testACorrespondentWithNoDisplayNameIsQuotedAsABareAddress() {
        // Apple writes "Name <addr>" when there is a name and just the
        // address when there is not — never "<addr>" on its own.
        XCTAssertEqual(MailFormat.addressForQuoting("jane@example.com"), "jane@example.com")
        XCTAssertEqual(MailFormat.addressForQuoting("Jane Smith <jane@example.com>"),
                       "Jane Smith <jane@example.com>")
    }

    func testTheReplyBodyCarriesThatAttributionAboveTheQuote() {
        let body = Draft.replying(to: message(text: "hi"), all: false, myAddress: nil).body
        XCTAssertTrue(body.contains("On "), body)
        XCTAssertTrue(body.contains("Jane Smith <jane@example.com> wrote:"), body)
        XCTAssertFalse(body.contains("Today at"), "the relative form is gone")
    }

    func testTheForwardHeaderIsApplesAndNotGmails() {
        // Gmail's "---------- Forwarded message ----------" carried only
        // From and Subject, dropping the two fields a forward is usually
        // sent to establish: when it arrived, and who else already had it.
        let m = message(text: "hi", to: ["carlo@example.com", "sam@example.com"])
        let body = Draft.forwarding(m).body

        XCTAssertTrue(body.contains("Begin forwarded message:"), body)
        XCTAssertFalse(body.contains("----------"))
        XCTAssertTrue(body.contains("From: Jane Smith <jane@example.com>"), body)
        XCTAssertTrue(body.contains("Subject: Lunch"), body)
        XCTAssertTrue(body.contains("To: carlo@example.com, sam@example.com"), body)
        XCTAssertTrue(body.contains("\nDate: "), "a forward without a date loses the point")
    }

    func testTheForwardFieldsAreInApplesOrder() {
        // From, Date, To, Subject — as observed in Sam's own forwards.
        let body = Draft.forwarding(message(text: "hi")).body
        let order = ["From:", "Date:", "To:", "Subject:"].compactMap {
            body.range(of: $0)?.lowerBound
        }
        XCTAssertEqual(order.count, 4, body)
        XCTAssertEqual(order, order.sorted(), "the header block is out of order")
    }

    func testTheForwardedDateIsTheLongFormWithAZone() {
        XCTAssertEqual(
            MailFormat.forwardedDate(Date(timeIntervalSince1970: 1_700_000_000),
                                     timeZone: eastern),
            "November 14, 2023 at 5:13:20\u{202F}PM EST")
    }

    // MARK: - Quoting

    func testAnHTMLOnlyMessageStillHasSomethingToQuote() {
        // The defect this pins: `textBody` is nil for an HTML-only message,
        // so forwarding one produced a letter containing nothing but the
        // "Forwarded message" header. Most transactional mail is HTML-only.
        let m = message(html: """
            <html><head><style>p { margin: 0 }</style></head><body>
            <p>Thanks for your order, Carlo</p>
            <p>Your payment method will be charged.</p>
            </body></html>
            """)
        let quoted = m.quotableText
        XCTAssertTrue(quoted.contains("Thanks for your order, Carlo"))
        XCTAssertTrue(quoted.contains("Your payment method will be charged."))
        XCTAssertFalse(quoted.contains("margin"), "the stylesheet is not the message")
        XCTAssertFalse(quoted.contains("<p>"), "tags are not the message")
    }

    func testPlainTextIsPreferredAndKeptVerbatim() {
        let m = message(text: "Line one\nLine two", html: "<p>ignored</p>")
        XCTAssertEqual(m.quotableText, "Line one\nLine two")
    }

    func testAnEmptyTextPartFallsThroughToTheHTML() {
        // Senders really do ship a plain part containing one newline.
        let m = message(text: "\n  \n", html: "<p>The actual message</p>")
        XCTAssertEqual(m.quotableText, "The actual message")
    }

    func testParagraphsSurviveQuotingSoAReplyIsReadable() {
        // Flattening to one line is right for a list row and wrong here: a
        // quoted body with no line breaks is a wall of text under the reply.
        let text = HTMLText.plainText(from: "<p>First para</p><p>Second para</p>")
        XCTAssertEqual(text, "First para\n\nSecond para")
    }

    func testInlineMarkupDoesNotShatterASentence() {
        // <b> and <a> are mid-sentence; turning them into breaks would put
        // every linked word on a line of its own.
        XCTAssertEqual(
            HTMLText.plainText(from: "<p>Please <b>confirm</b> at <a href=\"x\">this link</a> today</p>"),
            "Please confirm at this link today")
    }

    func testInlineMarkupInsideAWordDoesNotBreakTheWord() {
        // The one that was corrupting real mail. Every inline tag used to
        // emit a space, so a sender who styled part of a word got it back
        // sawn in half. Sam's own confidentiality notice came out of this as
        // "privileged info rmation" in every reply the app had ever sent,
        // and it is HIS words being handed back broken to HIS correspondents.
        XCTAssertEqual(
            HTMLText.plainText(from: "<p>privileged info<span>rmation</span> follows</p>"),
            "privileged information follows")
        XCTAssertEqual(
            HTMLText.plainText(from: "<div>un<b>der</b>stood</div>"),
            "understood")
        XCTAssertEqual(
            HTMLText.plainText(from: "<div>re<font face=\"x\">ceipt</font></div>"),
            "receipt")
    }

    func testTableCellsStillSeparateTheirWords() {
        // The reason the blanket space existed in the first place, and the
        // case the narrower rule has to keep: cells are not inline.
        XCTAssertEqual(
            HTMLText.plainText(from: "<table><tr><td>Jan</td><td>Feb</td></tr></table>"),
            "Jan Feb")
    }

    func testATwoColumnSignatureTableStillReadsInOrder() {
        // Sam's signature is exactly this shape: a two-column table with the
        // text in one cell and a photograph in the other.
        let html = """
            <table><tbody><tr>
            <td><b>Sam Example</b><br>Example Organisation<br>555-555-0142</td>
            <td><img src="https://example.com/portrait.jpg"></td>
            </tr></tbody></table>
            """
        XCTAssertEqual(HTMLText.plainText(from: html),
                       "Sam Example\nExample Organisation\n555-555-0142")
    }

    func testTemplateIndentationAndBlankRunsAreSqueezed() {
        let html = "<div>\n\n\n      Hello   there\n\n\n</div><div>\n   Second\n</div>"
        XCTAssertEqual(HTMLText.plainText(from: html), "Hello there\n\nSecond")
    }

    func testNoBodyAtAllQuotesNothingRatherThanCrashing() {
        XCTAssertEqual(message().quotableText, "")
    }

    // MARK: - Threading

    func testAReplyCarriesInReplyToAndReferences() {
        var draft = Draft()
        draft.to = ["jane@example.com"]
        draft.subject = "Re: Lunch"
        draft.body = "Yes please"
        draft.inReplyTo = "<parent@example.com>"

        let raw = String(decoding: RFC5322Builder.build(
            draft: draft, from: MailAccount(address: "me@x.com", username: "me@x.com"),
            inReplyToHeaders: (messageID: "<parent@example.com>", references: nil)),
                         as: UTF8.self)

        XCTAssertTrue(raw.contains("In-Reply-To: <parent@example.com>"), raw)
        XCTAssertTrue(raw.contains("References: <parent@example.com>"), raw)
    }

    func testReferencesExtendsTheAncestryRatherThanReplacingIt() {
        // In-Reply-To alone links one hop and loses the thread as soon as a
        // middle message is missing from the recipient's mailbox.
        let raw = String(decoding: RFC5322Builder.build(
            draft: Draft(to: ["a@b.com"], subject: "Re: x", body: "hi"),
            from: MailAccount(address: "me@x.com", username: "me@x.com"),
            inReplyToHeaders: (messageID: "<third@x>",
                               references: "<first@x> <second@x>")),
                         as: UTF8.self)

        XCTAssertTrue(raw.contains("References: <first@x> <second@x> <third@x>"), raw)
    }

    func testAFreshLetterClaimsNoAncestor() {
        let raw = String(decoding: RFC5322Builder.build(
            draft: Draft(to: ["a@b.com"], subject: "Hello", body: "hi"),
            from: MailAccount(address: "me@x.com", username: "me@x.com")),
                         as: UTF8.self)

        XCTAssertFalse(raw.contains("In-Reply-To"))
        XCTAssertFalse(raw.contains("References"))
    }

    func testAParentMessageIDWithoutAnglesIsBracketed() {
        // Servers hand back the header value as written, and not every
        // sender brackets it.
        let raw = String(decoding: RFC5322Builder.build(
            draft: Draft(to: ["a@b.com"], subject: "Re: x", body: "hi"),
            from: MailAccount(address: "me@x.com", username: "me@x.com"),
            inReplyToHeaders: (messageID: "bare@example.com", references: nil)),
                         as: UTF8.self)

        XCTAssertTrue(raw.contains("In-Reply-To: <bare@example.com>"), raw)
    }
}
