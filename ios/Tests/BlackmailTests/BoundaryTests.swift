import XCTest
@testable import Blackmail

/// The multipart boundaries: that none occurs in what it divides, and that
/// no longer scanning the base64 parts for one (P5b) changed nothing. From
/// the same randomness the builder picks the same boundaries it picked
/// before, so the letter is the same letter, byte for byte.
final class BoundaryTests: XCTestCase {

    private let account = MailAccount(address: "owner@example.com",
                                      username: "owner@example.com",
                                      displayName: "Owner Example")

    /// Randomness that can be replayed: 32 hex digits counting up from
    /// `start`, and how many have been drawn.
    private final class Tokens {
        private let start: Int
        private(set) var drawn = 0

        init(from start: Int = 0x51_0000) {
            self.start = start
        }

        func next() -> String {
            drawn += 1
            return Self.token(start + drawn)
        }

        static func token(_ n: Int) -> String {
            let hex = String(n, radix: 16, uppercase: true)
            return String(repeating: "0", count: 32 - hex.count) + hex
        }
    }

    /// `uniqueBoundary` as it was, kept as the reference: the same loop,
    /// handed what `build` used to hand it.
    private func previousBoundary(avoiding contents: [String], token: () -> String) -> String {
        var extra = 0
        while true {
            var candidate = "=_Blackmail_"
            for _ in 0...extra { candidate += token() }
            candidate += "_="
            if !contents.contains(where: { $0.contains(candidate) }) { return candidate }
            extra += 1
        }
    }

    /// What `build` used to scan for each boundary, every base64 payload
    /// included, in the order it scanned them. The names and types here are
    /// ones `build` does not alter, so they go in as they are.
    private func previousCandidates(body: String, html: String?,
                                    files: [(filename: String, mimeType: String, data: Data)],
                                    inline: [(contentID: String, filename: String,
                                              mimeType: String, data: Data)]) -> [String] {
        var candidates = [RFC5322Builder.quotedPrintable(body)]
        if let html { candidates.append(RFC5322Builder.quotedPrintable(html)) }
        for file in files {
            candidates += [RFC5322Builder.base64Wrapped(file.data), file.filename, file.mimeType]
        }
        for image in html == nil ? [] : inline {
            candidates += [RFC5322Builder.base64Wrapped(image.data), image.contentID,
                           image.filename, image.mimeType]
        }
        return candidates
    }

    /// The boundaries the old builder would have chosen, by the multipart
    /// they belong to, and how much randomness it would have drawn.
    private func previousChoice(body: String, html: String?,
                                files: [(filename: String, mimeType: String, data: Data)],
                                inline: [(contentID: String, filename: String,
                                          mimeType: String, data: Data)])
        -> (boundaries: [String: String], drawn: Int) {
        var candidates = previousCandidates(body: body, html: html, files: files, inline: inline)
        let tokens = Tokens()
        var chosen: [String: String] = [:]
        if html != nil {
            let alternative = previousBoundary(avoiding: candidates, token: tokens.next)
            chosen["alternative"] = alternative
            candidates.append(alternative)
            if !inline.isEmpty {
                let related = previousBoundary(avoiding: candidates, token: tokens.next)
                chosen["related"] = related
                candidates.append(related)
            }
        }
        if !files.isEmpty {
            chosen["mixed"] = previousBoundary(avoiding: candidates, token: tokens.next)
        }
        return (chosen, tokens.drawn)
    }

    /// Each multipart's boundary as the message declares it, whether the
    /// header was folded or not.
    private func declaredBoundaries(_ message: Data) throws -> [String: String] {
        let text = String(decoding: message, as: UTF8.self)
        let pattern = try NSRegularExpression(pattern: "multipart/(\\w+);\\s+boundary=\"([^\"]+)\"")
        var found: [String: String] = [:]
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let kind = String(text[Range(match.range(at: 1), in: text)!])
            let boundary = String(text[Range(match.range(at: 2), in: text)!])
            if let earlier = found[kind] { XCTAssertEqual(earlier, boundary, kind) }
            found[kind] = boundary
        }
        return found
    }

    private func picture(_ size: Int) -> Data {
        var seed: UInt64 = 0x2545_F491_4F6C_DD1D
        let noise = Data((0..<65_536).map { _ in
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return UInt8(truncatingIfNeeded: seed)
        })
        var out = Data(capacity: size + noise.count)
        while out.count < size { out.append(noise) }
        return out.prefix(size)
    }

    /// Builds the letter with replayable randomness and holds its
    /// boundaries, and the randomness it drew, to the old builder's.
    private func assertSameBoundaries(html: String?,
                                      files: [(filename: String, mimeType: String, data: Data)],
                                      inline: [(contentID: String, filename: String,
                                                mimeType: String, data: Data)] = [],
                                      _ label: String,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        var draft = Draft()
        draft.to = ["Carlo <carlo@example.org>"]
        draft.subject = "Sunday"
        draft.body = "Dear Carlo,\n\nSee you on Sunday at one.\n.\nOwner"

        let tokens = Tokens()
        let message = RFC5322Builder.build(draft: draft, from: account, attachments: files,
                                           htmlBody: html, inlineImages: inline,
                                           boundaryToken: tokens.next)
        let before = previousChoice(body: draft.body, html: html, files: files, inline: inline)

        XCTAssertEqual(try declaredBoundaries(message), before.boundaries, label,
                       file: file, line: line)
        XCTAssertEqual(tokens.drawn, before.drawn, "\(label): randomness drawn",
                       file: file, line: line)
    }

    // MARK: - The same boundaries as before

    /// Plain, the HTML twin, the twin with a signature picture, and each of
    /// those with a 1 MB photograph and with three files: every shape the
    /// app builds, and every multipart.
    func testTheSameRandomnessPicksTheSameBoundariesAsBefore() throws {
        let html = "<div dir=\"ltr\">Dear Carlo,<br>See you on Sunday.</div>"
            + "<div><img src=\"cid:sig-logo\"></div>"
        let logo = [(contentID: "sig-logo", filename: "logo.png", mimeType: "image/png",
                     data: picture(4_000))]
        let photo = [(filename: "Photo.jpg", mimeType: "image/jpeg", data: picture(1_000_000))]
        let three = [(filename: "Garden.jpg", mimeType: "image/jpeg", data: picture(30_000)),
                     (filename: "Quote.pdf", mimeType: "application/pdf", data: picture(20_000)),
                     (filename: "Notes.txt", mimeType: "text/plain", data: Data("notes".utf8))]

        try assertSameBoundaries(html: nil, files: [], "plain")
        try assertSameBoundaries(html: html, files: [], "html twin")
        try assertSameBoundaries(html: html, files: [], inline: logo, "html twin and logo")
        try assertSameBoundaries(html: nil, files: photo, "1 MB photo")
        try assertSameBoundaries(html: html, files: photo, "html twin and a 1 MB photo")
        try assertSameBoundaries(html: html, files: photo + three, inline: logo,
                                 "everything, four files")
    }

    /// A file whose name is the first boundary the randomness would make,
    /// and a picture whose id is the second; then a file whose type is the
    /// first and a picture whose name is the second. All four are still
    /// scanned, so each forces the boundary to grow, the same way and by
    /// the same draws as before, and neither boundary occurs in the name it
    /// avoided.
    func testANameThatHoldsTheNextBoundaryStillMakesItGrow() throws {
        let html = "<div>See the picture.</div><img src=\"cid:x\">"
        let first = "=_Blackmail_" + Tokens.token(0x51_0001) + "_="
        let second = "=_Blackmail_" + Tokens.token(0x51_0002) + Tokens.token(0x51_0003) + "_="
        let files = [(filename: "copy of \(first).pdf", mimeType: "application/pdf",
                      data: picture(10_000))]
        let inline = [(contentID: "img" + second, filename: "logo.png", mimeType: "image/png",
                       data: picture(2_000))]
        let typed = [(filename: "Quote.pdf", mimeType: "application/x-" + first,
                      data: picture(10_000))]
        let named = [(contentID: "logo", filename: "logo \(second).png", mimeType: "image/png",
                      data: picture(2_000))]

        try assertSameBoundaries(html: nil, files: files, "a colliding file name")
        try assertSameBoundaries(html: html, files: files, inline: inline,
                                 "a colliding name and a colliding id")
        try assertSameBoundaries(html: html, files: typed, inline: named,
                                 "a colliding file type and a colliding picture name")

        let tokens = Tokens()
        var draft = Draft()
        draft.to = ["carlo@example.org"]
        draft.body = "Here."
        let message = RFC5322Builder.build(draft: draft, from: account, attachments: files,
                                           boundaryToken: tokens.next)
        let mixed = try XCTUnwrap(try declaredBoundaries(message)["mixed"])
        XCTAssertNotEqual(mixed, first)
        XCTAssertFalse(files[0].filename.contains(mixed))
        XCTAssertEqual(tokens.drawn, 3, "one candidate refused, then one of two tokens")
    }

    /// The reason the base64 parts need no scan, held as a test: base64 as
    /// the builder writes it is letters, digits, `+`, `/`, `=` and CRLF, and
    /// every boundary has a `_`, which is none of those. If either ever
    /// stops being true, the parts have to be scanned again.
    func testNoBoundaryCanOccurInBase64() {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=\r\n".utf8)
        let everyByte = Data((0..<3 * 256).map { UInt8($0 % 256) })
        for payload in [everyByte, picture(100_000), Data([0xFB, 0xFF]), Data([0xFF])] {
            let encoded = RFC5322Builder.base64Wrapped(payload)
            XCTAssertTrue(encoded.utf8.allSatisfy(allowed.contains))
        }
        for _ in 0..<20 {
            let boundary = RFC5322Builder.uniqueBoundary(avoiding: [])
            XCTAssertTrue(boundary.utf8.contains { !allowed.contains($0) }, boundary)
        }
    }

    /// 5 and 20 MB, as measured in PERFORMANCE.md #4b. The old scan takes
    /// seconds at these sizes in the suite's debug build, so they run only
    /// when `BLACKMAIL_LARGE_TESTS` is set.
    func testLargeLettersPickTheSameBoundariesAsBefore() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BLACKMAIL_LARGE_TESTS"] != nil,
                          "set BLACKMAIL_LARGE_TESTS to compare 5 and 20 MB letters")
        let html = "<div>Photos from Sunday.</div>"
        for size in [5_000_000, 20_000_000] {
            let photo = [(filename: "Photo.jpg", mimeType: "image/jpeg", data: picture(size))]
            try assertSameBoundaries(html: html, files: photo, "\(size / 1_000_000) MB photo")
        }
    }
}
