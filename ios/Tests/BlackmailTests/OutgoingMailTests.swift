import XCTest
@testable import Blackmail

/// Tests for composing outgoing mail, plus the round trip.
///
/// The round-trip test at the bottom is the strongest thing in this suite:
/// building a message and decoding it back exercises the builder and the
/// decoder against each other, so a shared misunderstanding of the format
/// shows up as a mismatch rather than as two modules agreeing on something
/// wrong.
final class OutgoingMailTests: XCTestCase {

    private let account = MailAccount(address: "him@example.com",
                                      username: "him@example.com",
                                      displayName: "Him Indoors")

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    // MARK: - Privacy

    /// The one that is a privacy failure rather than a formatting one. Bcc
    /// belongs only in the SMTP envelope; a Bcc header in the message body
    /// exposes every blind recipient to all the others.
    func testBccNeverAppearsInTheMessage() {
        var draft = Draft()
        draft.to = ["a@example.com"]
        draft.cc = ["b@example.com"]
        draft.bcc = ["secret@example.com"]
        draft.subject = "Subject"
        draft.body = "Body"

        let wire = text(RFC5322Builder.build(draft: draft, from: account))
        let headers = wire.components(separatedBy: "\r\n\r\n").first ?? wire

        XCTAssertFalse(headers.lowercased().contains("bcc:"))
        XCTAssertFalse(headers.contains("secret@example.com"),
                       "a blind recipient must not be visible to the others")
        XCTAssertTrue(headers.contains("b@example.com"), "Cc is visible and must stay")
    }

    // MARK: - Format

    func testLineEndingsAreCRLFThroughout() {
        var draft = Draft()
        draft.to = ["a@example.com"]
        draft.body = "one\ntwo\nthree"
        let wire = text(RFC5322Builder.build(draft: draft, from: account))

        // Every LF must be preceded by a CR. Strict servers reject bare LFs,
        // and the failure is a rejected message rather than a mangled one.
        let chars = Array(wire)
        for (i, c) in chars.enumerated() where c == "\n" {
            XCTAssertTrue(i > 0 && chars[i - 1] == "\r", "bare LF at offset \(i)")
        }
    }

    func testNonAsciiSubjectIsEncodedAndHeaderLinesStayShort() {
        var draft = Draft()
        draft.to = ["a@example.com"]
        draft.subject = "Café meeting about the año ahead — with a long tail to force folding"
        let wire = text(RFC5322Builder.build(draft: draft, from: account))
        let headers = wire.components(separatedBy: "\r\n\r\n").first ?? ""

        XCTAssertTrue(headers.contains("=?UTF-8?"), "non-ASCII must be RFC 2047 encoded")
        for line in headers.components(separatedBy: "\r\n") {
            XCTAssertLessThanOrEqual(line.count, 78, "header line too long: \(line)")
        }
    }

    func testDateUsesEnglishMonthNamesNotTheDeviceLocale() {
        var draft = Draft()
        draft.to = ["a@example.com"]
        let fixed = Date(timeIntervalSince1970: 1789719243)   // 18 Sep 2026
        let wire = text(RFC5322Builder.build(draft: draft, from: account, date: fixed))
        XCTAssertTrue(wire.contains("Sep 2026"),
                      "without en_US_POSIX this emits the device's language and servers reject it")
    }

    func testThreadingHeadersAreSetWhenReplying() {
        var draft = Draft()
        draft.to = ["a@example.com"]
        draft.subject = "Re: hello"
        let wire = text(RFC5322Builder.build(
            draft: draft, from: account,
            inReplyToHeaders: (messageID: "<orig@example.com>", references: nil)))

        XCTAssertTrue(wire.contains("In-Reply-To: <orig@example.com>"),
                      "without this a reply starts a new conversation in the recipient's client")
        XCTAssertTrue(wire.contains("References:"))
    }

    func testAttachmentProducesMultipartWithANonCollidingBoundary() {
        var draft = Draft()
        draft.to = ["a@example.com"]
        draft.body = "see attached"
        let payload = Data(repeating: 0xAB, count: 3000)
        let wire = text(RFC5322Builder.build(
            draft: draft, from: account,
            attachments: [(filename: "report.pdf", mimeType: "application/pdf", data: payload)]))

        XCTAssertTrue(wire.contains("multipart/mixed"))
        XCTAssertTrue(wire.contains("filename=\"report.pdf\""))

        // The boundary must not occur inside the content it delimits, or the
        // message truncates at the collision.
        guard let range = wire.range(of: "boundary=\"") else { return XCTFail("no boundary") }
        let rest = wire[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return XCTFail("unterminated boundary") }
        let boundary = String(rest[rest.startIndex..<end])
        let occurrences = wire.components(separatedBy: boundary).count - 1
        XCTAssertEqual(occurrences, 4,
                       "expected the declaration plus two part markers and the closer, got \(occurrences)")
    }

    func testBodyLinesAreWrappedForQuotedPrintable() {
        var draft = Draft()
        draft.to = ["a@example.com"]
        draft.body = String(repeating: "abcdefghij ", count: 60)
        let wire = text(RFC5322Builder.build(draft: draft, from: account))
        for line in wire.components(separatedBy: "\r\n") {
            XCTAssertLessThanOrEqual(line.count, 78, "body line too long for QP: \(line.count)")
        }
    }

    // MARK: - Round trip

    /// Build a message, then decode it with the module that will decode real
    /// mail. Anything the two disagree about surfaces here rather than in his
    /// inbox.
    func testRoundTripThroughTheDecoder() {
        var draft = Draft()
        draft.to = ["a@example.com"]
        draft.subject = "Café meeting"
        draft.body = "Dear friend,\r\n\r\nLunch on Thursday? It is  spaced  oddly.\r\n\r\nHim"

        let wire = RFC5322Builder.build(draft: draft, from: account)
        let decoded = MIMEDecoder.decodeMessage(wire)
        let headers = MIMEDecoder.parseHeaders(wire)

        let subject = MIMEDecoder.headerValue("Subject", in: headers).map(MIMEDecoder.decodeWord)
        XCTAssertEqual(subject, "Café meeting", "subject did not survive encode then decode")

        let body = (decoded.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(body.contains("Lunch on Thursday?"))
        XCTAssertTrue(body.contains("It is  spaced  oddly."),
                      "internal runs of spaces must survive quoted-printable")
        XCTAssertTrue(body.hasSuffix("Him"))
    }

    func testRoundTripWithAttachmentPreservesBytesExactly() {
        var draft = Draft()
        draft.to = ["a@example.com"]
        draft.body = "attached"
        // Every byte value, so a charset or encoding slip shows up.
        let payload = Data((0...255).map { UInt8($0) })

        let wire = RFC5322Builder.build(
            draft: draft, from: account,
            attachments: [(filename: "bytes.bin", mimeType: "application/octet-stream", data: payload)])

        let parsed = MIMEDecoder.parse(wire)
        let attachmentBytes = parsed.bodies
            .filter { $0.key != "1" }
            .map { MIMEDecoder.decodeTransfer($0.value, encoding: "base64") }
            .first { $0.count == payload.count }

        XCTAssertEqual(attachmentBytes, payload, "attachment bytes must round-trip unchanged")
    }

    // MARK: - The HTML twin

    private func alternativeMessage(attachments: [(filename: String, mimeType: String,
                                                   data: Data)] = []) -> String {
        text(RFC5322Builder.build(
            draft: Draft(to: ["a@b.com"], subject: "Lunch", body: "plain words"),
            from: account,
            attachments: attachments,
            htmlBody: "<html><body dir=\"auto\">plain words</body></html>"))
    }

    func testNoHTMLMeansTheMessageIsExactlyWhatItAlwaysWas() {
        // Every letter with nothing rich in it — a quarter of his traffic —
        // has to keep going out as a bare text/plain part. This is the
        // regression guard for the 265 tests that were green before the
        // alternative branch existed.
        let raw = text(RFC5322Builder.build(
            draft: Draft(to: ["a@b.com"], subject: "x", body: "hi"), from: account))
        XCTAssertTrue(raw.contains("Content-Type: text/plain; charset=utf-8"), raw)
        XCTAssertFalse(raw.contains("multipart"))
    }

    func testTheTwoRenderingsTravelAsMultipartAlternative() {
        let raw = alternativeMessage()
        XCTAssertTrue(raw.contains("Content-Type: multipart/alternative;"), raw)
        XCTAssertTrue(raw.contains("Content-Type: text/plain; charset=utf-8"), raw)
        XCTAssertTrue(raw.contains("Content-Type: text/html; charset=utf-8"), raw)
    }

    func testThePLAINPartComesFIRSTAndTheMARKUPLast() {
        // RFC 2046 §5.1.4: the richest alternative goes last and a client
        // renders the last one it understands. Reversed, every recipient
        // capable of HTML would be shown the plain text instead — the exact
        // bug this work exists to fix, silently reintroduced.
        let raw = alternativeMessage()
        guard let plain = raw.range(of: "Content-Type: text/plain"),
              let html = raw.range(of: "Content-Type: text/html") else {
            return XCTFail(raw)
        }
        XCTAssertLessThan(plain.lowerBound, html.lowerBound, raw)
    }

    func testBothPartsAreQuotedPrintable() {
        // The markup carries U+202F in every attribution, and one <div>
        // holding a long paragraph runs past RFC 5322's 998-octet ceiling,
        // where a strict relay may wrap it through the middle of a tag.
        let raw = alternativeMessage()
        XCTAssertEqual(raw.components(separatedBy:
            "Content-Transfer-Encoding: quoted-printable").count - 1, 2, raw)
        for line in raw.components(separatedBy: "\r\n") {
            XCTAssertLessThanOrEqual(line.utf8.count, 998, "over the line limit: \(line)")
        }
    }

    func testWithFilesTheAlternativeNestsINSIDETheMixed() {
        // The alternatives must be siblings of each other and not of the
        // photograph. Flattened into one multipart/mixed, a reader is
        // entitled to treat the photograph as another rendering of the
        // letter and show only that.
        let raw = alternativeMessage(attachments: [
            (filename: "P.jpg", mimeType: "image/jpeg", data: Data(repeating: 0xAB, count: 64))])

        guard let mixed = raw.range(of: "multipart/mixed"),
              let alternative = raw.range(of: "multipart/alternative"),
              let attachment = raw.range(of: "Content-Disposition: attachment") else {
            return XCTFail(raw)
        }
        XCTAssertLessThan(mixed.lowerBound, alternative.lowerBound, "mixed is the outer one")
        XCTAssertLessThan(alternative.lowerBound, attachment.lowerBound,
                          "the letter comes before the files")
    }

    func testTheTwoBOUNDARIESAreDifferentFromEachOther() {
        // One boundary used for both levels closes the inner multipart and
        // the outer one at the same line, and everything after it is lost.
        let raw = alternativeMessage(attachments: [
            (filename: "P.jpg", mimeType: "image/jpeg", data: Data(repeating: 0xAB, count: 64))])
        let boundaries = Set(raw.components(separatedBy: "boundary=\"")
            .dropFirst()
            .compactMap { $0.components(separatedBy: "\"").first })
        XCTAssertEqual(boundaries.count, 2, "\(boundaries)")
    }

    func testEveryPartIsClosedByItsOwnTerminator() {
        let raw = alternativeMessage(attachments: [
            (filename: "P.jpg", mimeType: "image/jpeg", data: Data(repeating: 0xAB, count: 64))])
        let boundaries = raw.components(separatedBy: "boundary=\"")
            .dropFirst()
            .compactMap { $0.components(separatedBy: "\"").first }
        for b in boundaries {
            XCTAssertTrue(raw.contains("--" + b + "--\r\n"),
                          "unterminated multipart: \(b)")
        }
    }

    func testTheFullLetterStillDecodesBackToItsPlainText() {
        // The strongest check available without a client: build it, decode
        // it, and see the words come back.
        let wire = RFC5322Builder.build(
            draft: Draft(to: ["a@b.com"], subject: "Lunch", body: "plain words"),
            from: account,
            htmlBody: "<html><body dir=\"auto\">plain words</body></html>")
        let decoded = MIMEDecoder.decodeMessage(wire)

        XCTAssertEqual(decoded.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                       "plain words")
        XCTAssertTrue(decoded.html?.contains("body dir=\"auto\"") == true,
                      String(describing: decoded.html))
    }


    // MARK: - Inline images and the related set

    private func logoLetter(fileToo: Bool = false) -> String {
        var attachments: [(filename: String, mimeType: String, data: Data)] = []
        if fileToo {
            attachments.append((filename: "P.jpg", mimeType: "image/jpeg",
                                 data: Data(repeating: 0xAB, count: 64)))
        }
        return text(RFC5322Builder.build(
            draft: Draft(to: ["a@b.com"], subject: "Lunch", body: "plain words"),
            from: account,
            attachments: attachments,
            htmlBody: "<html><body dir=\"auto\">plain words "
                + "<img src=\"cid:sig-logo\"></body></html>",
            inlineImages: [(contentID: "sig-logo", filename: "sig-logo.png",
                            mimeType: "image/png",
                            data: Data(repeating: 0x89, count: 48))]))
    }

    func testInlineImagesTravelInsideARelatedSet() {
        let raw = logoLetter()
        XCTAssertTrue(raw.contains("Content-Type: multipart/related;"), raw)
        XCTAssertTrue(raw.contains("type=\"multipart/alternative\""),
                      "the root must be named so a reader prefers the letter")
        XCTAssertTrue(raw.contains("Content-ID: <sig-logo>"), raw)
        XCTAssertTrue(raw.contains("Content-Disposition: inline"), raw)
    }

    func testTheAlternativesAreTheROOTAndTheImageComesAfter() {
        // Inside related, the markup part comes first and the pictures it
        // names follow — a reader walks the set from the root.
        //
        // Searched by part rather than by header string because `headerLine`
        // folds long values: `multipart/alternative; boundary=…` does not
        // exist as one substring anywhere in the built message.
        let raw = logoLetter()
        guard let plain = raw.range(of: "text/plain; charset=utf-8"),
              let html = raw.range(of: "text/html; charset=utf-8"),
              let cid = raw.range(of: "Content-ID: <sig-logo>")
        else { return XCTFail(raw) }
        XCTAssertLessThan(plain.lowerBound, html.lowerBound,
                          "plain before markup, per RFC 2046")
        XCTAssertLessThan(html.lowerBound, cid.lowerBound,
                          "the root's pictures follow the root")
    }

    func testWithFilesTooThereAreTHREEBoundariesAndTheTreeIsMixed() {
        let raw = logoLetter(fileToo: true)
        guard let mixed = raw.range(of: "multipart/mixed;"),
              let related = raw.range(of: "multipart/related;"),
              let file = raw.range(of: "Content-Disposition: attachment")
        else { return XCTFail(raw) }
        XCTAssertLessThan(mixed.lowerBound, related.lowerBound)
        XCTAssertLessThan(related.lowerBound, file.lowerBound)

        let boundaries = Set(raw.components(separatedBy: "boundary=\"").dropFirst()
            .compactMap { $0.components(separatedBy: "\"").first })
        XCTAssertEqual(boundaries.count, 3, "\(boundaries)")
        for b in boundaries {
            XCTAssertTrue(raw.contains("--" + b + "--\r\n"),
                          "unterminated multipart: \(b)")
        }
    }

    func testInlineImagesWithoutHTMLAreDroppedRatherThanSentAsOrphans() {
        // A cid: reference only means anything inside markup; with no HTML
        // twin there is nowhere for the image to be referred from.
        let raw = text(RFC5322Builder.build(
            draft: Draft(to: ["a@b.com"], subject: "x", body: "hi"),
            from: account,
            inlineImages: [(contentID: "sig-logo", filename: "sig-logo.png",
                            mimeType: "image/png", Data(repeating: 1, count: 8))]))
        XCTAssertTrue(raw.contains("Content-Type: text/plain; charset=utf-8"), raw)
        XCTAssertFalse(raw.contains("sig-logo"))
        XCTAssertFalse(raw.contains("multipart"))
    }

    func testTheLogoLetterDecodesBackWithItsPictureResolvable() {
        let payload = Data(repeating: 0x89, count: 48)
        let wire = RFC5322Builder.build(
            draft: Draft(to: ["a@b.com"], subject: "Lunch", body: "plain words"),
            from: account,
            htmlBody: "<html><body>plain words <img src=\"cid:sig-logo\"></body></html>",
            inlineImages: [(contentID: "sig-logo", filename: "sig-logo.png",
                            mimeType: "image/png", data: payload)])
        let decoded = MIMEDecoder.decodeMessage(wire)

        XCTAssertEqual(decoded.text, "plain words")
        XCTAssertTrue(decoded.html?.contains("cid:sig-logo") == true)
        let logo = decoded.attachments.first { $0.contentID == "sig-logo" }
        XCTAssertNotNil(logo, "the reading pane needs the part to resolve the cid:")
        XCTAssertEqual(logo?.isInline, true)
        XCTAssertEqual(logo?.filename, "sig-logo.png")
        XCTAssertFalse(MIMEPart(type: "image", subtype: "png",
                                disposition: "inline",
                                dispositionParameters: ["filename": "x.png"]).isAttachment,
                       "an inline picture must not raise the paperclip")
    }

    func testAPlainLetterWithAFileKeepsItsPartHeadersOutOfTheBody() {
        // Regression for a blank separator line that made the text part's
        // own Content-Type land after an empty header block — turning the
        // part's headers into body text for any strict reader.
        let wire = RFC5322Builder.build(
            draft: Draft(to: ["a@b.com"], subject: "x", body: "just words"),
            from: account,
            attachments: [(filename: "P.jpg", mimeType: "image/jpeg",
                           data: Data(repeating: 0xAB, count: 64))])
        let decoded = MIMEDecoder.decodeMessage(wire)
        XCTAssertEqual(decoded.text, "just words")
        XCTAssertFalse((decoded.text ?? "").contains("Content-Type"),
                       "the part's headers leaked into its body")
    }

}
