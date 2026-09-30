import XCTest
@testable import Blackmail

/// The quoted-printable encoder, written into bytes (B-050), against the
/// encoder as it was.
///
/// It had built its output a `String` at a time, which cost nothing for a
/// letter he types and a third of a second on this host for the megabyte of
/// markup a forwarded newsletter now carries. The rewrite must write the
/// same bytes for every input, because those bytes are the letter: the soft
/// breaks, the escaped trailing space, the escaped dot at the start of a
/// line (B-044's dot-stuffing leans on it) and the CRLFs all land where they
/// landed before.
final class QuotedPrintableTests: XCTestCase {

    /// `quotedPrintable` as it was, kept as the reference.
    private func previous(_ text: String) -> String {
        RFC5322Builder.normalisedLineEndings(text)
            .components(separatedBy: "\r\n")
            .map { previousLine(Array($0.utf8)) }
            .joined(separator: "\r\n")
    }

    private func previousLine(_ bytes: [UInt8]) -> String {
        var out = ""
        var length = 0
        for (index, byte) in bytes.enumerated() {
            let isBlank = byte == 0x20 || byte == 0x09
            var atom: String
            if byte == 0x3D || byte > 126 || (byte < 32 && !isBlank) {
                atom = escaped(byte)
            } else if isBlank && index == bytes.count - 1 {
                atom = escaped(byte)
            } else {
                atom = String(Character(UnicodeScalar(byte)))
            }
            if length + atom.count > 73 {
                if let last = out.last, last == " " || last == "\t" {
                    out.removeLast()
                    out += last == " " ? "=20" : "=09"
                    length += 2
                }
                out += "=\r\n"
                length = 0
            }
            if length == 0 && byte == 0x2E && atom.count == 1 {
                atom = escaped(byte)
            }
            out += atom
            length += atom.count
        }
        return out
    }

    private func escaped(_ byte: UInt8) -> String {
        let hex = Array("0123456789ABCDEF")
        return "=" + String(hex[Int(byte >> 4)]) + String(hex[Int(byte & 0x0F)])
    }

    private func assertSame(_ text: String, _ label: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let now = RFC5322Builder.quotedPrintable(text)
        let then = previous(text)
        XCTAssertEqual(now, then, label, file: file, line: line)
    }

    func testTheShapesThatDecideWhereBytesGo() {
        let cases: [String] = [
            "", "a", " ", "\t", ".", "=", "\n", "\r", "\r\n", "\r\r\n", "\n\r", "a\n", "a \n",
            "a\t\r\nb", ".hidden\n.also", "é and 😀 and \u{202F}PM", "a=b\u{7F}\u{01}c",
            String(repeating: "x", count: 72) + " y",
            String(repeating: "x", count: 73) + ".",
            String(repeating: "x", count: 72) + "=",
            String(repeating: "x", count: 71) + " \t" + String(repeating: "y", count: 10),
            String(repeating: "word ", count: 40),
            String(repeating: "x", count: 73) + "\n.dot after a break",
            String(repeating: "é", count: 60),
            "<html><head><meta http-equiv=\"content-type\" content=\"text/html; charset=utf-8\">",
        ]
        for (n, text) in cases.enumerated() { assertSame(text, "case \(n): \(text.debugDescription)") }
    }

    func testEveryWrapPointAgainstEveryAwkwardByte() {
        // Each awkward byte at every position around the 73-byte budget, so
        // every soft break lands on it, before it and after it.
        for awkward in [" ", "\t", ".", "=", "é", "\u{2014}", "\r\n", "\n", "\r"] {
            for lead in 60...80 {
                let text = String(repeating: "a", count: lead) + awkward
                    + String(repeating: "b", count: 90) + awkward + " "
                assertSame(text, "\(awkward.debugDescription) after \(lead)")
            }
        }
    }

    func testRandomTextOfEveryKind() {
        // A fixed generator, so a failure here is the same failure every run.
        var state: UInt64 = 0x5EED_B1AC_4A11
        func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }
        let alphabet: [String] = ["a", "b", " ", " ", "\t", ".", "=", "\n", "\r", "\r\n",
                                  "é", "😀", "\u{202F}", "<", ">", "\"", "\u{01}", "0"]
        for round in 0..<150 {
            var text = ""
            for _ in 0..<Int(next() % 400) { text += alphabet[Int(next() % UInt64(alphabet.count))] }
            assertSame(text, "round \(round)")
        }
    }

    private func markup(bytes: Int) -> String {
        var html = ""
        var n = 0
        while html.utf8.count < bytes {
            n += 1
            html += "<tr><td style=\"padding: 12px; color: #222;\"><a href=\"https://news.example.com/"
                + "s/\(n)?utm_source=mail&amp;id=\(n)\">Story \(n) — read more</a>. </td></tr>\n"
        }
        return html
    }

    func testANewslettersMarkupComesOutTheSame() {
        let html = markup(bytes: 100_000)
        XCTAssertEqual(RFC5322Builder.quotedPrintable(html), previous(html))
    }

    /// The old encoder took 0.35 s for this in a release build on this
    /// host, and about 0.9 s in the debug build the suite runs. A bound on
    /// the wall clock, so it runs only when `BLACKMAIL_LARGE_TESTS` is set;
    /// the bytes are held to the old encoder's above either way.
    func testAMegabyteOfMarkupIsEncodedQuickly() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BLACKMAIL_LARGE_TESTS"] != nil,
                          "set BLACKMAIL_LARGE_TESTS to time a megabyte")
        let html = markup(bytes: 1 << 20)
        let started = Date()
        let encoded = RFC5322Builder.quotedPrintable(html)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertGreaterThan(encoded.utf8.count, html.utf8.count)
        XCTAssertLessThan(elapsed, 0.5, "\(elapsed) s for a megabyte")
    }
}
