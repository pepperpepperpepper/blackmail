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
