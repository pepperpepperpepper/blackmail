import XCTest
@testable import Blackmail

/// Tests for the decoder that will handle a stranger's real correspondence.
///
/// Weighted towards the things that actually go wrong in mail rather than
/// towards coverage: encodings servers emit but specs discourage, headers
/// built by twenty-year-old mailers, and input shaped to hang a parser. Four
/// of these cases are regressions for defects found by review — each is
/// labelled, because a test whose purpose is forgotten gets deleted the first
/// time it is inconvenient.
final class MIMEDecoderTests: XCTestCase {

    // MARK: - Transfer encodings

    func testBase64IgnoresWhitespaceAndMissingPadding() {
        // Real mailers wrap base64 at 76 columns, and some omit the padding.
        let padded = MIMEDecoder.decodeTransfer(Data("aGVsbG8gd29ybGQ=".utf8), encoding: "base64")
        XCTAssertEqual(String(decoding: padded, as: UTF8.self), "hello world")

        let wrapped = MIMEDecoder.decodeTransfer(Data("aGVsbG8g\r\nd29ybGQ=".utf8), encoding: "base64")
        XCTAssertEqual(String(decoding: wrapped, as: UTF8.self), "hello world")

        let unpadded = MIMEDecoder.decodeTransfer(Data("aGVsbG8gd29ybGQ".utf8), encoding: "base64")
        XCTAssertEqual(String(decoding: unpadded, as: UTF8.self), "hello world")
    }

    /// The base64 decoder as it was before it moved from `Data` to a byte
    /// array (P8), kept as the reference the new one has to agree with.
    private func previousBase64(_ data: Data) -> Data {
        var out = Data()
        out.reserveCapacity(data.count * 3 / 4 + 3)
        var accumulator: UInt32 = 0
        var bits = 0
        for byte in data {
            let value: UInt32
            switch byte {
            case 0x41...0x5A: value = UInt32(byte - 0x41)
            case 0x61...0x7A: value = UInt32(byte - 0x61) + 26
            case 0x30...0x39: value = UInt32(byte - 0x30) + 52
            case 0x2B, 0x2D:  value = 62
            case 0x2F, 0x5F:  value = 63
            case 0x3D:
                accumulator = 0
                bits = 0
                continue
            default:
                continue
            }
            accumulator = ((accumulator << 6) | value) & 0xFFFF
            bits += 6
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((accumulator >> UInt32(bits)) & 0xFF))
            }
        }
        return out
    }

    /// Byte for byte what it decoded before, on everything a sender sends:
    /// clean, wrapped at 76 with CRLF or LF, unpadded, truncated mid-quantum,
    /// separately padded blocks glued together, base64url, stray `=`, junk
    /// and high bytes, NUL, and a slice of a larger buffer, which does not
    /// start at index zero. The sizes here are small because the suite runs
    /// a debug build; 1, 5 and 25 MB were compared in a release build and
    /// are in PERFORMANCE.md #5.
    func testBase64DecodesByteForByteAsItDidBefore() {
        var seed: UInt64 = 0x2545_F491_4F6C_DD1D
        func random() -> UInt8 {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return UInt8(truncatingIfNeeded: seed)
        }
        func encoded(_ count: Int) -> String {
            Data((0..<count).map { _ in random() }).base64EncodedString()
        }
        func wrapped(_ text: String, every width: Int, with eol: String) -> String {
            var lines: [Substring] = []
            var rest = Substring(text)
            while !rest.isEmpty {
                lines.append(rest.prefix(width))
                rest = rest.dropFirst(width)
            }
            return lines.joined(separator: eol)
        }

        let body = encoded(6_000)
        var inputs: [Data] = [
            Data(), Data("=".utf8), Data("====".utf8), Data("Q".utf8), Data("QQ".utf8),
            Data("QUJDR".utf8), Data("QQ==QQ==".utf8), Data("QUJD\r\n=\r\nREVG".utf8),
            Data(body.utf8),
            Data(wrapped(body, every: 76, with: "\r\n").utf8),
            Data(wrapped(body, every: 76, with: "\n").utf8),
            Data(body.replacingOccurrences(of: "=", with: "").utf8),
            Data(body.dropLast(3).utf8),
            Data((encoded(100) + encoded(101) + encoded(102)).utf8),
            Data(body.replacingOccurrences(of: "+", with: "-")
                     .replacingOccurrences(of: "/", with: "_").utf8),
            Data((0..<4_096).map { _ in random() }),
            Data([0x00, 0x51, 0x00, 0x51, 0xFF, 0x3D, 0x51, 0x51, 0x80, 0x0D]),
        ]
        let larger = Data(("!!!!" + wrapped(encoded(3_000), every: 76, with: "\r\n")).utf8)
        inputs.append(larger[4...])
        inputs.append(larger[1_001..<2_002])

        for (i, input) in inputs.enumerated() {
            XCTAssertEqual(MIMEDecoder.decodeTransfer(input, encoding: "base64"),
                           previousBase64(input), "input \(i), \(input.count) bytes")
        }
    }

    func testQuotedPrintableSoftBreaksAndLowercaseHex() {
        let soft = MIMEDecoder.decodeTransfer(Data("Hello=\r\n world".utf8), encoding: "quoted-printable")
        XCTAssertEqual(String(decoding: soft, as: UTF8.self), "Hello world")

        // Lowercase hex is out of spec and common.
        let lower = MIMEDecoder.decodeTransfer(Data("caf=e9".utf8), encoding: "quoted-printable")
        XCTAssertEqual(lower.last, 0xE9)
    }

    /// REGRESSION. `=20` at end of line was being deleted along with genuine
    /// trailing whitespace. A sender writes `=20` precisely to say the space
    /// is real and must survive; only *literal* trailing whitespace is
    /// transport padding.
    func testQuotedPrintableKeepsEscapedTrailingSpaceButDropsLiteralPadding() {
        let escaped = MIMEDecoder.decodeTransfer(Data("Hello=20\r\nthere".utf8),
                                                 encoding: "quoted-printable")
        XCTAssertEqual(String(decoding: escaped, as: UTF8.self), "Hello \r\nthere",
                       "an escaped =20 is intentional content, not padding")

        let padding = MIMEDecoder.decodeTransfer(Data("Hello  \t\r\nthere".utf8),
                                                 encoding: "quoted-printable")
        XCTAssertEqual(String(decoding: padding, as: UTF8.self), "Hello\r\nthere",
                       "literal trailing whitespace is transport padding and goes")
    }

    func testUnknownEncodingPassesThroughRatherThanLosingTheMessage() {
        let raw = Data("plain text".utf8)
        XCTAssertEqual(MIMEDecoder.decodeTransfer(raw, encoding: "7bit"), raw)
        XCTAssertEqual(MIMEDecoder.decodeTransfer(raw, encoding: "x-nonsense"), raw)
    }

    // MARK: - RFC 2047 headers

    func testEncodedWordsBothForms() {
        XCTAssertEqual(MIMEDecoder.decodeWord("=?UTF-8?B?SGVsbG8gd29ybGQ=?="), "Hello world")
        XCTAssertEqual(MIMEDecoder.decodeWord("=?UTF-8?Q?Hello_world?="), "Hello world",
                       "underscore means space in the Q form, it is not a literal underscore")
    }

    func testAdjacentEncodedWordsDropTheWhitespaceBetweenThem() {
        // RFC 2047: whitespace separating two encoded-words is not content. A
        // decoder that keeps it splits words in the middle of a subject, which
        // Gmail triggers routinely by chunking long non-ASCII subjects.
        let joined = MIMEDecoder.decodeWord("=?UTF-8?Q?Hello?= =?UTF-8?Q?World?=")
        XCTAssertEqual(joined, "HelloWorld")

        // But whitespace between an encoded word and plain text IS content.
        let mixed = MIMEDecoder.decodeWord("=?UTF-8?Q?Hello?= world")
        XCTAssertEqual(mixed, "Hello world")
    }

    func testUndecodableCharsetDegradesInsteadOfFailing() {
        // Latin-1 is total, so this must produce something rather than nothing:
        // one bad header must never take out the whole mailbox.
        let out = MIMEDecoder.decodeWord("=?x-not-a-charset?B?SGVsbG8=?=")
        XCTAssertFalse(out.isEmpty)
    }

    /// REGRESSION, and the sharpest one here. `decodeWord` was quadratic: a
    /// header of repeated `=?a?Q?x` with no closing `?=` made every scan run
    /// to the end of the string. Measured before the fix: 112 KB took 54.6 s,
    /// on whatever thread is decoding a Subject. Any sender can put that in a
    /// Subject line, so it was a remote hang with no user recourse.
    func testHostileHeaderDoesNotHang() {
        let hostile = String(repeating: "=?a?Q?x", count: 16_000)
        let started = Date()
        _ = MIMEDecoder.decodeWord(hostile)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 2.0,
                          "decodeWord regressed to super-linear; this was 54.6s before the fix")
    }

    /// REGRESSION. `Data.removeLast()` is O(n) here, so stripping trailing
    /// whitespace once per line made quoted-printable decoding quadratic:
    /// 5.2 MB took 22.6 s. Large QP bodies are ordinary, not hostile.
    func testLargeQuotedPrintableBodyIsLinear() {
        let line = "Some ordinary text with trailing spaces   \r\n"
        let big = Data(String(repeating: line, count: 40_000).utf8)
        let started = Date()
        _ = MIMEDecoder.decodeTransfer(big, encoding: "quoted-printable")
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 2.0, "quoted-printable regressed to quadratic")
    }

    // MARK: - Structure

    func testHeaderUnfoldingAndBodySplit() {
        let raw = Data("Subject: one\r\n  continued\r\nFrom: a@b.c\r\n\r\nbody here".utf8)
        let headers = MIMEDecoder.parseHeaders(raw)
        // TWO spaces, not one. RFC 5322 §2.2.3 unfolding removes the CRLF and
        // keeps the leading whitespace, so the continuation's indent is part
        // of the value. This assertion originally demanded one space and the
        // decoder was right — worth keeping as a note, because collapsing the
        // run here would silently reformat every folded header in the app.
        XCTAssertEqual(MIMEDecoder.headerValue("Subject", in: headers), "one  continued")
        XCTAssertEqual(MIMEDecoder.headerValue("from", in: headers), "a@b.c",
                       "header lookup must be case-insensitive")
    }

    func testMultipartAlternativePrefersHtmlAndNumbersSectionsLikeIMAP() {
        let raw = Data("""
        Content-Type: multipart/alternative; boundary="B"\r
        \r
        --B\r
        Content-Type: text/plain; charset=utf-8\r
        \r
        plain version\r
        --B\r
        Content-Type: text/html; charset=utf-8\r
        \r
        <p>rich version</p>\r
        --B--\r
        """.utf8)

        let decoded = MIMEDecoder.decodeMessage(raw)
        XCTAssertEqual(decoded.text?.trimmingCharacters(in: .whitespacesAndNewlines), "plain version")
        XCTAssertTrue(decoded.html?.contains("rich version") == true)
    }

    func testAttachmentIsListedWithItsImapSectionAsIdentifier() {
        // The section path is what `fetchAttachmentData` passes to BODY[...],
        // so if this drifts the attachment silently fetches the wrong part.
        let raw = Data("""
        Content-Type: multipart/mixed; boundary="X"\r
        \r
        --X\r
        Content-Type: text/plain\r
        \r
        see attached\r
        --X\r
        Content-Type: application/pdf; name="report.pdf"\r
        Content-Disposition: attachment; filename="report.pdf"\r
        Content-Transfer-Encoding: base64\r
        \r
        aGVsbG8=\r
        --X--\r
        """.utf8)

        let decoded = MIMEDecoder.decodeMessage(raw)
        XCTAssertEqual(decoded.attachments.count, 1)
        guard let a = decoded.attachments.first else { return XCTFail("no attachment") }
        XCTAssertEqual(a.filename, "report.pdf")
        XCTAssertEqual(a.mimeType, "application/pdf")
        XCTAssertEqual(a.id, "2", "second child of a multipart root is IMAP section 2")
    }

    func testRFC2047FilenameIsDecoded() {
        let raw = Data("""
        Content-Type: multipart/mixed; boundary="X"\r
        \r
        --X\r
        Content-Type: application/pdf\r
        Content-Disposition: attachment; filename="=?UTF-8?Q?r=C3=A9sum=C3=A9.pdf?="\r
        \r
        data\r
        --X--\r
        """.utf8)
        let decoded = MIMEDecoder.decodeMessage(raw)
        XCTAssertEqual(decoded.attachments.first?.filename, "résumé.pdf")
    }

    // MARK: - Files sent inline (B-101)

    /// One shape of letter, and what the pane makes of it.
    private struct Shape {
        let name: String
        let raw: String
        /// The part the shape is about.
        let part: String
        /// The names the header lists, from the structure and from the
        /// downloaded letter alike.
        let listed: [String]
        /// Every part `collectAttachments` keeps, the pictures the body
        /// shows included: as before B-101.
        let kept: [String]
        /// The paperclip on the list's row.
        let clip: Bool
        /// The letter's plain words, as the body has them.
        let words: String?
        /// `part`'s `isAttachment`, as before B-101, and its `isListedFile`.
        let isAttachment: Bool
        let isListedFile: Bool
    }

    private static func mixed(_ parts: [String], boundary: String = "B") -> String {
        "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n\r\n"
            + parts.map { "--\(boundary)\r\n\($0)\r\n" }.joined() + "--\(boundary)--\r\n"
    }

    private static let header = "From: Sam Example <sam@example.com>\r\nTo: me@example.com\r\n"
        + "Subject: The garden\r\nMIME-Version: 1.0\r\n"
    private static let words = "Content-Type: text/plain; charset=utf-8\r\n\r\nHere it is."
    private static let pdf = "Content-Type: application/pdf; name=\"Programme.pdf\"\r\n"
        + "Content-Transfer-Encoding: base64\r\n"
    private static let pdfBytes = "\r\nJVBERi0xLjQK"

    /// Every shape a file is sent in, inline or not: the header's rows, from
    /// the BODYSTRUCTURE and from the downloaded letter, the paperclip from
    /// the same structure, and the body's words. A file sent inline is
    /// listed unless it is a picture the body shows by `cid:`, or a text
    /// part with no name, or the letter's own words; a multipart sent
    /// inline is not a file, what it holds is; a forwarded letter
    /// sent inline is words in the body, its own files listed, never a
    /// file itself. And `isAttachment` answers as it did, so the body and
    /// the parts kept are as they were.
    private var shapes: [Shape] {
        let words = Self.words
        return [
            Shape(name: "application/pdf, inline, no Content-ID, as Apple Mail sends one",
                  raw: Self.header + Self.mixed([
                    words,
                    Self.pdf + "Content-Disposition: inline; filename=\"Programme.pdf\"\r\n" + Self.pdfBytes,
                  ], boundary: "B"),
                  part: "2", listed: ["Programme.pdf"], kept: ["Programme.pdf"], clip: true,
                  words: "Here it is.", isAttachment: false, isListedFile: true),
            Shape(name: "application/pdf, inline, with a Content-ID",
                  raw: Self.header + Self.mixed([
                    words,
                    Self.pdf + "Content-ID: <programme@example.com>\r\n"
                        + "Content-Disposition: inline; filename=\"Programme.pdf\"\r\n" + Self.pdfBytes,
                  ], boundary: "B"),
                  part: "2", listed: ["Programme.pdf"], kept: ["Programme.pdf"], clip: true,
                  words: "Here it is.", isAttachment: false, isListedFile: true),
            Shape(name: "image/png, inline, with a Content-ID: a signature's logo",
                  raw: Self.header + Self.mixed([
                    "Content-Type: text/html; charset=utf-8\r\n\r\n<p>Sam</p><img src=\"cid:logo@example.com\">",
                    "Content-Type: image/png; name=\"logo.png\"\r\nContent-Transfer-Encoding: base64\r\n"
                        + "Content-ID: <logo@example.com>\r\nContent-Disposition: inline; filename=\"logo.png\"\r\n"
                        + "\r\niVBORw0K",
                  ], boundary: "B"),
                  part: "2", listed: [], kept: ["logo.png"], clip: false,
                  words: nil, isAttachment: false, isListedFile: false),
            Shape(name: "image/jpeg, inline, no Content-ID",
                  raw: Self.header + Self.mixed([
                    words,
                    "Content-Type: image/jpeg; name=\"photo.jpg\"\r\nContent-Transfer-Encoding: base64\r\n"
                        + "Content-Disposition: inline; filename=\"photo.jpg\"\r\n\r\n/9j/4AAQ",
                  ], boundary: "B"),
                  part: "2", listed: ["photo.jpg"], kept: ["photo.jpg"], clip: true,
                  words: "Here it is.", isAttachment: false, isListedFile: true),
            Shape(name: "image/png, attachment, with a Content-ID",
                  raw: Self.header + Self.mixed([
                    words,
                    "Content-Type: image/png; name=\"chart.png\"\r\nContent-Transfer-Encoding: base64\r\n"
                        + "Content-ID: <chart@example.com>\r\nContent-Disposition: attachment; filename=\"chart.png\"\r\n"
                        + "\r\niVBORw0K",
                  ], boundary: "B"),
                  part: "2", listed: ["chart.png"], kept: ["chart.png"], clip: true,
                  words: "Here it is.", isAttachment: true, isListedFile: true),
            // Its words are the letter's, after the first part's, as Mail
            // draws them; they were nowhere until B-113.
            Shape(name: "text/plain, inline, with no name",
                  raw: Self.header + Self.mixed([
                    words,
                    "Content-Type: text/plain; charset=utf-8\r\nContent-Disposition: inline\r\n\r\nMore words.",
                  ], boundary: "B"),
                  part: "2", listed: [], kept: [], clip: false,
                  words: "Here it is.\nMore words.", isAttachment: false, isListedFile: false),
            Shape(name: "text/plain, inline, named notes.txt",
                  raw: Self.header + Self.mixed([
                    words,
                    "Content-Type: text/plain; charset=utf-8; name=\"notes.txt\"\r\n"
                        + "Content-Disposition: inline; filename=\"notes.txt\"\r\n\r\nGutters first.",
                  ], boundary: "B"),
                  part: "2", listed: ["notes.txt"], kept: ["notes.txt"], clip: true,
                  words: "Here it is.", isAttachment: false, isListedFile: true),
            Shape(name: "text/plain, inline, named notes.txt, the letter's only words",
                  raw: Self.header + "Content-Type: text/plain; charset=utf-8; name=\"notes.txt\"\r\n"
                    + "Content-Disposition: inline; filename=\"notes.txt\"\r\n\r\nGutters first.\r\n",
                  part: "1", listed: [], kept: [], clip: false,
                  words: "Gutters first.", isAttachment: false, isListedFile: true),
            Shape(name: "message/rfc822, inline, unnamed, a letter of words and a PDF",
                  raw: Self.header + Self.mixed([
                    "Content-Type: message/rfc822\r\nContent-Disposition: inline\r\n\r\n"
                        + "Subject: Earlier\r\n" + Self.mixed([
                            "Content-Type: text/plain; charset=utf-8\r\n\r\nThe earlier words.",
                            Self.pdf + "Content-Disposition: attachment; filename=\"Programme.pdf\"\r\n"
                                + Self.pdfBytes,
                        ], boundary: "I"),
                  ], boundary: "B"),
                  part: "1", listed: ["Programme.pdf"], kept: ["Programme.pdf"], clip: true,
                  words: "The earlier words.", isAttachment: false, isListedFile: false),
            Shape(name: "message/rfc822, inline, unnamed, a letter of words alone",
                  raw: Self.header + Self.mixed([
                    "Content-Type: message/rfc822\r\nContent-Disposition: inline\r\n\r\n"
                        + "Subject: Earlier\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n"
                        + "The earlier words.",
                  ], boundary: "B"),
                  part: "1", listed: [], kept: [], clip: false,
                  words: "The earlier words.", isAttachment: false, isListedFile: false),
            Shape(name: "message/rfc822, attachment, named forwarded.eml",
                  raw: Self.header + Self.mixed([
                    words,
                    "Content-Type: message/rfc822; name=\"forwarded.eml\"\r\n"
                        + "Content-Disposition: attachment; filename=\"forwarded.eml\"\r\n\r\n"
                        + "Subject: Earlier\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n"
                        + "The earlier words.",
                  ], boundary: "B"),
                  part: "2", listed: ["forwarded.eml"], kept: ["forwarded.eml"], clip: true,
                  words: "Here it is.", isAttachment: true, isListedFile: true),
            // A multipart sent inline is not a file: what it holds is
            // looked at in its turn, here the HTML and the logo it shows.
            Shape(name: "multipart/related, inline, the HTML and a logo with a Content-ID",
                  raw: Self.header + "Content-Type: multipart/alternative; boundary=\"A\"\r\n\r\n"
                    + "--A\r\n" + words + "\r\n"
                    + "--A\r\nContent-Type: multipart/related; boundary=\"R\"\r\n"
                    + "Content-Disposition: inline\r\n\r\n"
                    + "--R\r\nContent-Type: text/html; charset=utf-8\r\n\r\n"
                    + "<p>Here it is.</p><img src=\"cid:logo@example.com\">\r\n"
                    + "--R\r\nContent-Type: image/png; name=\"logo.png\"\r\nContent-Transfer-Encoding: base64\r\n"
                    + "Content-ID: <logo@example.com>\r\nContent-Disposition: inline; filename=\"logo.png\"\r\n"
                    + "\r\niVBORw0K\r\n"
                    + "--R--\r\n--A--\r\n",
                  part: "2", listed: [], kept: ["logo.png"], clip: false,
                  words: "Here it is.", isAttachment: false, isListedFile: false),
            // Apple Mail's own shape for a PDF put among the words: the
            // plain words whole, and the HTML split around the file.
            Shape(name: "Apple Mail's letter with a PDF among its words",
                  raw: Self.header + "Content-Type: multipart/alternative; boundary=\"A\"\r\n\r\n"
                    + "--A\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nBefore.\r\n\r\nAfter.\r\n"
                    + "--A\r\n" + Self.mixed([
                        "Content-Type: text/html; charset=utf-8\r\n\r\n<div>Before.</div>",
                        Self.pdf + "Content-Disposition: inline; filename=\"Programme.pdf\"\r\n"
                            + Self.pdfBytes,
                        "Content-Type: text/html; charset=utf-8\r\n\r\n<div>After.</div>",
                    ], boundary: "M") + "--A--\r\n",
                  part: "2.2", listed: ["Programme.pdf"], kept: ["Programme.pdf"], clip: true,
                  words: "Before.\n\nAfter.", isAttachment: false, isListedFile: true),
        ]
    }

    func testAFileSentInlineIsListedWithItsPaperclipUnlessTheBodyShowsIt() throws {
        for shape in shapes {
            let raw = Data(shape.raw.utf8)
            let structure = MIMEDecoder.parseStructure(raw)
            let decoded = MIMEDecoder.decodeMessage(raw)
            let letter = Message(id: "7/3", mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                                 senderAddress: "sam@example.com", to: [], cc: [], subject: "The garden",
                                 date: Date(timeIntervalSince1970: 1_790_000_000),
                                 textBody: decoded.text, htmlBody: decoded.html,
                                 attachments: decoded.attachments)

            let fromStructure = MIMEDecoder.listedAttachments(in: structure)
            XCTAssertEqual(fromStructure.map(\.filename), shape.listed, shape.name)
            XCTAssertEqual(letter.listedAttachments.map(\.filename), shape.listed, shape.name)
            XCTAssertEqual(letter.listedAttachments.map(\.id), fromStructure.map(\.id), shape.name)
            XCTAssertEqual(decoded.attachments.map(\.filename), shape.kept, shape.name)
            XCTAssertEqual(IMAPMailRepository.hasAttachment(structure), shape.clip, shape.name)
            XCTAssertEqual(decoded.text?.trimmingCharacters(in: .whitespacesAndNewlines), shape.words,
                           shape.name)

            let part = try XCTUnwrap(MIMEDecoder.part(at: shape.part, in: structure), shape.name)
            XCTAssertEqual(part.isAttachment, shape.isAttachment, "isAttachment: " + shape.name)
            XCTAssertEqual(part.isListedFile, shape.isListedFile, "isListedFile: " + shape.name)
        }
    }

    /// What the header leaves out is a picture sent inline with a
    /// `Content-ID`, and only that: a PDF or a text part sent inline with
    /// one is a file, as is a picture with none, or one sent as an
    /// attachment.
    func testOnlyAPictureSentInlineWithAContentIDIsShownInTheBody() {
        func part(_ mimeType: String, inline: Bool, contentID: String?) -> Attachment {
            Attachment(id: "2", filename: "Programme", mimeType: mimeType, size: 1_024,
                       contentID: contentID, isInline: inline)
        }
        XCTAssertTrue(part("image/png", inline: true, contentID: "logo@example.com").isShownInBody)
        XCTAssertFalse(part("application/pdf", inline: true, contentID: "programme@example.com").isShownInBody,
                       "a PDF sent inline with a Content-ID is a file")
        XCTAssertFalse(part("text/plain", inline: true, contentID: "notes@example.com").isShownInBody,
                       "a text part sent inline with a Content-ID is a file")
        XCTAssertFalse(part("image/jpeg", inline: true, contentID: nil).isShownInBody,
                       "a picture sent inline with no Content-ID is a file")
        XCTAssertFalse(part("image/png", inline: false, contentID: "chart@example.com").isShownInBody,
                       "a picture sent as an attachment is a file")
    }

    /// The HTML of the shapes that have one: the logo's letter's HTML is
    /// the part it was before, and Apple Mail's letter with a PDF among its
    /// words is both of the parts it splits its HTML into, the PDF marked
    /// where it sat (B-113). Until B-113 it was the first part alone, and
    /// this test held that: the words after the file were not shown (B-101's
    /// Not covered).
    func testTheBodyOfALetterWithAFileSentInlineHasEveryPart() {
        let byName = Dictionary(uniqueKeysWithValues: shapes.map { ($0.name, $0) })
        let logo = MIMEDecoder.decodeMessage(Data(byName["image/png, inline, with a Content-ID: a signature's logo"]!.raw.utf8))
        XCTAssertEqual(logo.html, "<p>Sam</p><img src=\"cid:logo@example.com\">")
        let apple = MIMEDecoder.decodeMessage(Data(byName["Apple Mail's letter with a PDF among its words"]!.raw.utf8))
        XCTAssertEqual(apple.html, "<div>Before.</div><!--bm-file:2.2--><div>After.</div>")
    }

    // MARK: - Hostile input

    func testUnclosedBoundaryDoesNotHangOrLoseEverything() {
        let raw = Data("""
        Content-Type: multipart/mixed; boundary="NEVERCLOSED"\r
        \r
        --NEVERCLOSED\r
        Content-Type: text/plain\r
        \r
        the only content there is\r
        """.utf8)
        let decoded = MIMEDecoder.decodeMessage(raw)
        XCTAssertTrue(decoded.text?.contains("only content") == true,
                      "a truncated message must still show what it has")
    }

    func testDeeplyNestedMultipartIsCappedRatherThanRecursingForever() {
        var raw = ""
        for i in 0..<300 {
            raw += "Content-Type: multipart/mixed; boundary=\"B\(i)\"\r\n\r\n--B\(i)\r\n"
        }
        raw += "Content-Type: text/plain\r\n\r\ndeep\r\n"
        let started = Date()
        _ = MIMEDecoder.decodeMessage(Data(raw.utf8))
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.0)
    }

    func testEmptyAndGarbageInputAreSurvivable() {
        _ = MIMEDecoder.decodeMessage(Data())
        _ = MIMEDecoder.decodeMessage(Data([0xFF, 0xFE, 0x00, 0x01]))
        _ = MIMEDecoder.decodeWord("=?")
        _ = MIMEDecoder.decodeTransfer(Data("=".utf8), encoding: "quoted-printable")
    }
}
