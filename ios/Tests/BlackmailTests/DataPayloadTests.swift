import XCTest
@testable import Blackmail

/// What `SMTPClient` writes after DATA's 354: the letter dot-stuffed, with
/// every line break made CRLF, and the terminator. Held byte for byte to what
/// it wrote before the stuffing moved from `Data` to a byte array (P5a).
final class DataPayloadTests: XCTestCase {

    private let account = MailAccount(address: "owner@example.com",
                                      username: "owner@example.com",
                                      displayName: "Owner Example")

    /// The payload as `transmit` made it before, kept as the reference the
    /// new one has to agree with: `dotStuffed` as it was, a byte at a time
    /// through `Data`, and the terminator appended after it.
    private func previousPayload(_ raw: Data) -> Data {
        let cr: UInt8 = 0x0D, lf: UInt8 = 0x0A, dot: UInt8 = 0x2E
        var out = Data()
        out.reserveCapacity(raw.count + (raw.count / 64) + 16)

        var atLineStart = true
        var index = raw.startIndex
        while index < raw.endIndex {
            let byte = raw[index]
            if byte == cr || byte == lf {
                out.append(cr)
                out.append(lf)
                let next = raw.index(after: index)
                if byte == cr, next < raw.endIndex, raw[next] == lf {
                    index = next
                }
                atLineStart = true
            } else {
                if atLineStart && byte == dot { out.append(dot) }
                out.append(byte)
                atLineStart = false
            }
            index = raw.index(after: index)
        }

        if !(out.count >= 2 && out.suffix(2) == Data([0x0D, 0x0A])) {
            out.append(contentsOf: [0x0D, 0x0A])
        }
        out.append(contentsOf: [0x2E, 0x0D, 0x0A])
        return out
    }

    private func assertAsBefore(_ raw: Data, _ label: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let now = SMTPClient.dataPayload(raw)
        let before = previousPayload(raw)
        guard now != before else { return }
        let at = zip(now, before).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            ?? min(now.count, before.count)
        XCTFail("\(label): \(now.count) bytes against \(before.count), first difference at \(at)",
                file: file, line: line)
    }

    // MARK: - What it does

    /// The rules themselves, spelled out, so the comparison below is not
    /// the only thing standing between a change and a truncated letter.
    func testALeadingDotIsDoubledAndEveryLineBreakBecomesCRLF() {
        func payload(_ text: String) -> String {
            String(decoding: SMTPClient.dataPayload(Data(text.utf8)), as: UTF8.self)
        }
        XCTAssertEqual(payload("Hello\r\n.\r\nstill here\r\n"), "Hello\r\n..\r\nstill here\r\n.\r\n")
        XCTAssertEqual(payload(".start"), "..start\r\n.\r\n")
        XCTAssertEqual(payload("one\ntwo\rthree\r\n"), "one\r\ntwo\r\nthree\r\n.\r\n")
        XCTAssertEqual(payload("a\n.b"), "a\r\n..b\r\n.\r\n")
        XCTAssertEqual(payload("end."), "end.\r\n.\r\n")
        // Nothing at all still gets a line of its own for the terminator.
        XCTAssertEqual(payload(""), "\r\n.\r\n")
    }

    // MARK: - As it was

    /// Byte for byte what went before, on everything that can go wrong at a
    /// line's edge: a line that is only a dot, a dot at the very start and
    /// the very end, after a bare LF and after a bare CR, CRLF.CRLF, lines of
    /// dots, CR and LF in every order, a letter not ending in CRLF, and one
    /// ending in half of one; then noise made of nothing but dots and line
    /// breaks and a letter; and slices of a larger buffer, which do not
    /// start at index zero.
    func testAwkwardLettersGoOutAsTheyDidBefore() {
        let texts = [
            "", ".", "..", "\r\n", "\n", "\r", ".\r\n", "\r\n.\r\n", "\r\n.", ".\r\n.",
            "a\r\n.\r\nb", ".start", "end.", "end\r\n.", "a\n.b", "a\r.b", "a\r\n.\r\nb\r\n",
            ".\n.\r.\r\n.", "...\r\n....\r\n.....", "\n\n\r\r\r\n\n\r", "\r\n\r\n.\r\n\r\n",
            "\n\r.", "\r\r\n.", "no line break at the end", "ends in a lone LF\n",
            "ends in a lone CR\r", "ends in LF CR\n\r", String(repeating: ".\r\n", count: 50),
        ]
        for text in texts { assertAsBefore(Data(text.utf8), text.debugDescription) }

        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func random() -> UInt64 {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return seed
        }
        let alphabet: [UInt8] = [0x2E, 0x0D, 0x0A, 0x61, 0x2E, 0x0D]
        for length in [1, 2, 3, 7, 64, 1_000, 20_000] {
            let noise = Data((0..<length).map { _ in alphabet[Int(random() % 6)] })
            assertAsBefore(noise, "noise of \(length)")
        }

        let larger = Data((0..<4_096).map { _ in alphabet[Int(random() % 6)] })
        assertAsBefore(larger[1...], "a slice from 1")
        assertAsBefore(larger[1_001..<3_003], "a slice from 1001")
    }

    /// Letters as the app builds them: plain, with the HTML twin, with the
    /// twin and a signature picture, and with a 1 MB photograph. The
    /// builder's own output already ends every line in CRLF and escapes a
    /// leading dot, so here the stuffing should change nothing and only the
    /// terminator be added; the comparison is what says so.
    func testLettersTheAppBuildsGoOutAsTheyDidBefore() {
        for (label, raw) in letters(photo: 1_000_000) {
            assertAsBefore(raw, label)
        }
    }

    /// The same at 5 and 20 MB, the sizes PERFORMANCE.md #4a was measured
    /// at. The old code takes seconds at 20 MB in the suite's debug build,
    /// so these run only when `BLACKMAIL_LARGE_TESTS` is set. The release
    /// comparison of both sizes, and the timings, are in PERFORMANCE.md.
    func testLargeLettersGoOutAsTheyDidBefore() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BLACKMAIL_LARGE_TESTS"] != nil,
                          "set BLACKMAIL_LARGE_TESTS to compare 5 and 20 MB letters")
        for size in [5_000_000, 20_000_000] {
            for (label, raw) in letters(photo: size) where label.contains("photo") {
                assertAsBefore(raw, label)
            }
        }
    }

    /// A draft with a leading dot and a bare line break in it, built the
    /// four ways the app builds one.
    private func letters(photo size: Int) -> [(String, Data)] {
        var draft = Draft()
        draft.to = ["Carlo <carlo@example.org>"]
        draft.subject = "Sunday"
        draft.body = "Dear Carlo,\n\nSee you on Sunday at one.\n.\n..and a line of dots\r\nOwner"
        let html = "<div dir=\"ltr\">Dear Carlo,<br>.<br>See you on Sunday.</div>"
            + "<div><img src=\"cid:sig-logo\"></div>"
        // 64 KB of noise, repeated: as good as a photograph to base64, and
        // quick to make in a debug build.
        var seed: UInt64 = 0x2545_F491_4F6C_DD1D
        let noise = Data((0..<65_536).map { _ in
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return UInt8(truncatingIfNeeded: seed)
        })
        var picture = Data(capacity: size + noise.count)
        while picture.count < size { picture.append(noise) }
        let logo = (contentID: "sig-logo", filename: "logo.png", mimeType: "image/png",
                    data: noise.prefix(4_000))
        let photo = (filename: "Photo.jpg", mimeType: "image/jpeg", data: picture.prefix(size))
        return [
            ("plain", RFC5322Builder.build(draft: draft, from: account)),
            ("html twin", RFC5322Builder.build(draft: draft, from: account, htmlBody: html)),
            ("html twin and logo", RFC5322Builder.build(draft: draft, from: account,
                                                        htmlBody: html, inlineImages: [logo])),
            ("\(size / 1_000_000) MB photo", RFC5322Builder.build(draft: draft, from: account,
                                                                  attachments: [photo])),
        ]
    }
}
