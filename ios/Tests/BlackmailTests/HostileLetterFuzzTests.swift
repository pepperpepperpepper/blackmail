import XCTest
@testable import Blackmail

/// Letters a stranger could send, made by mutating ordinary mail, and
/// everything that reads one: the MIME decoder, the text taken out of HTML,
/// the sanitiser a reply or a forward quotes through, the reading pane's
/// wrapper, picture rewrite and page, and the list's preview.
///
/// Seeded and repeatable: a failure names its case, and the same seed and
/// case make the same letter on any host. A few hundred cases run with the
/// suite. `BLACKMAIL_FUZZ_CASES` runs as many as it says, a million in a
/// night, and `BLACKMAIL_FUZZ_SEED` starts from another seed.
///
/// Each case must not crash, must finish well inside a bound no linear
/// pass comes near, and must give back output no larger than its input
/// allows. The sanitiser's output is held to what it promises as well: only
/// tags it keeps, no attribute that acts, no address on a scheme mail has no
/// use for, no closing tag for anything it did not open, and nothing nested
/// deeper than its limit.
final class HostileLetterFuzzTests: XCTestCase {

    private var cases: Int {
        ProcessInfo.processInfo.environment["BLACKMAIL_FUZZ_CASES"].flatMap { Int($0) } ?? 150
    }

    private var seed: UInt64 {
        ProcessInfo.processInfo.environment["BLACKMAIL_FUZZ_SEED"].flatMap { UInt64($0) }
            ?? 0x6875_7274_6C65
    }

    /// Far past what any case takes here in the debug build, a few
    /// milliseconds, and far below what a pass growing with the square of
    /// its input took on inputs this size.
    private static let perCase: TimeInterval = 2

    /// The largest input made. Past this a case is cut down.
    private static let largest = 96 * 1_024

    // MARK: - Making hostile input

    /// Pieces a stranger would reach for: the syntax every pass keys on,
    /// unfinished and repeated.
    private static let pieces = [
        "<", ">", "</", "/>", "<!--", "-->", "<!", "<?", "<!DOCTYPE", "<html", "</html>", "<head>",
        "<head ", "</head>", "<header>", "<body", "</body>", "<div>", "</div>", "</x>", "<p>",
        "<li>", "<td>", "<tr>", "<table>", "<script>", "</script", "<style>", "</style>",
        "<title>", "<svg>", "<svg/>", "<math>", "<select>", "<object>", "<iframe src=x>",
        "<template>", "<plaintext>", "<xmp>", "<b>", "</b>", "<a href=\"", "<img src=\"cid:",
        "<img src=cid:ii_garden01>", "\"", "'", "=", " ", "\t", "\r\n", "\n", "\r", "\0",
        "cid:", "CID:", "url(", "url(cid:", ")", " style=\"", "background:url(cid:ii_garden01)",
        "position:fixed", "expression(", "java\tscript:", "jav&#x61;script:", "&#", "&#x",
        "&amp;", "&colon;", "&", ";", "onclick=", " onerror=\"x\"", "srcdoc=", "http://",
        "https://", "www.", "data:image/png;base64,", "data:text/html,", "=?", "?=",
        "=?utf-8?q?", "=?utf-8?b?", "=?x?Q?", "--", "--B", "--B--", "\r\n\r\n",
        "Content-Type: multipart/mixed; boundary=\"B\"\r\n",
        "Content-Type: text/html; charset=utf-16\r\n", "Content-Transfer-Encoding: base64\r\n",
        "Content-Transfer-Encoding: quoted-printable\r\n", "Content-Type: message/rfc822\r\n",
        "filename*0*=utf-8''%E2", "filename*1=x", "\u{301}", "é", "\u{FEFF}", "\u{202E}",
        "\u{1F339}", "\u{FFFF}", "=\r\n", "=4", "==", "=?utf-8?Q?=E2=80?=",
    ]

    private typealias Numbers = OrdinaryMail.Numbers

    /// `start`, mutated from one to eight times.
    private func mutated(_ start: [UInt8], _ n: inout Numbers, among others: [[UInt8]]) -> [UInt8] {
        var b = start
        for _ in 0..<(1 + n.below(8)) {
            let at = b.isEmpty ? 0 : n.below(b.count + 1)
            switch n.below(8) {
            case 0:
                b.insert(contentsOf: Array(n.pick(Self.pieces).utf8), at: at)
            case 1:
                let piece = Array(n.pick(Self.pieces).utf8)
                let times = 1 + n.below(n.chance(20) ? 4_000 : 40)
                b.insert(contentsOf: Array([[UInt8]](repeating: piece, count: times).joined()),
                         at: at)
            case 2:
                guard !b.isEmpty else { continue }
                let end = min(b.count, at + 1 + n.below(200))
                b.removeSubrange(min(at, end)..<end)
            case 3:
                guard !b.isEmpty else { continue }
                let from = n.below(b.count)
                let slice = Array(b[from..<min(b.count, from + 1 + n.below(300))])
                let times = 1 + n.below(n.chance(20) ? 300 : 8)
                b.insert(contentsOf: Array([[UInt8]](repeating: slice, count: times).joined()),
                         at: at)
            case 4:
                b.removeSubrange(min(at, b.count)...)
            case 5:
                for _ in 0..<(1 + n.below(16)) where !b.isEmpty {
                    b[n.below(b.count)] = UInt8(truncatingIfNeeded: n.next())
                }
            case 6:
                let other = n.pick(others)
                guard !other.isEmpty else { continue }
                let from = n.below(other.count)
                b.insert(contentsOf: other[from..<min(other.count, from + n.below(2_000))], at: at)
            default:
                b.insert(contentsOf: (0..<(1 + n.below(64))).map { _ in
                    UInt8(truncatingIfNeeded: n.next())
                }, at: at)
            }
            if b.count > Self.largest { b.removeSubrange(Self.largest...) }
        }
        return b
    }

    /// Seconds for `work`, held to `perCase`.
    private func timed<T>(_ label: String, _ number: Int, _ work: () -> T) -> T {
        let started = Date()
        let out = work()
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, Self.perCase, "\(label), case \(number): \(elapsed) s")
        return out
    }

    // MARK: - Markup

    func testMarkupFromAStrangerIsReadInBoundedTimeAndSize() {
        let documents = OrdinaryMail.documents(generated: 20).map { Array($0.utf8) }
        let known = Set(OrdinaryMail.pictures)
        let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)
        var n = Numbers(seed: seed)
        for number in 0..<cases {
            let start = n.chance(15) ? [] : n.pick(documents)
            let bytes = mutated(start, &n, among: documents)
            let html = String(decoding: bytes, as: UTF8.self)
            let size = html.utf8.count

            let stripped = timed("wrapper", number) { DocumentWrapper.stripped(from: html) }
            XCTAssertLessThanOrEqual(stripped.utf8.count, size, "wrapper, case \(number)")

            let rewritten = timed("pictures", number) {
                InlineImageRewriter.rewrite(stripped, known: known)
            }
            XCTAssertLessThanOrEqual(rewritten.utf8.count, 3 * size + 16, "pictures, case \(number)")

            let made = timed("quote", number) {
                QuotedMarkup.made(html, pictures: OrdinaryMail.quotePictures)
            }
            XCTAssertLessThanOrEqual(made.html.utf8.count, 30 * size + 8_192, "quote, case \(number)")
            XCTAssertTrue(made.shown.isSubset(of: Set(OrdinaryMail.quotePictures.values)))
            checkSafe(made.html, case: number)

            let text = timed("text", number) { HTMLText.plainText(from: html) }
            XCTAssertLessThanOrEqual(text.utf8.count, size, "text, case \(number)")

            let preview = timed("preview", number) { PreviewText.fromHTML(html) }
            XCTAssertLessThanOrEqual(preview.unicodeScalars.count, PreviewText.maximumCharacters)

            let parts = OrdinaryMail.pictures.enumerated().map { i, id in
                Attachment(id: "\(i + 2)", filename: "p\(i).png", mimeType: "image/png",
                           size: 100, contentID: id, isInline: true)
            }
            var m = Message(id: "600001/2", mailboxID: "INBOX", sender: "Stranger <s@example.com>",
                            senderAddress: "s@example.com", to: [], cc: [], subject: "x",
                            date: Date(timeIntervalSince1970: 1_790_000_000),
                            textBody: n.chance(30) ? html : nil,
                            htmlBody: n.chance(70) ? html : nil, attachments: parts)
            m.isShortened = n.chance(20)
            let page = timed("page", number) { PanePage.letter(m, style: style) }
            XCTAssertLessThanOrEqual(page?.utf8.count ?? 0, 5 * size + 4_096, "page, case \(number)")
            let stack = timed("stack", number) { PanePage.stackBody(m) }
            XCTAssertLessThanOrEqual(stack.html.utf8.count, 5 * size + 1_024, "stack, case \(number)")
        }
    }

    /// Every tag in the sanitiser's output is one it keeps, with no
    /// attribute that acts and no address it would not let out; every
    /// closing tag closes something it opened; nothing is nested deeper
    /// than its limit.
    private func checkSafe(_ html: String, case number: Int) {
        let refused: Set<String> = [
            "script", "style", "iframe", "frame", "frameset", "object", "embed", "applet", "form",
            "input", "button", "textarea", "select", "option", "link", "meta", "base", "svg",
            "math", "template", "noscript", "canvas", "html", "head", "body", "title", "xmp",
            "plaintext", "noembed", "noframes", "param",
        ]
        let void: Set<String> = [
            "area", "base", "basefont", "bgsound", "br", "col", "embed", "frame", "hr", "img",
            "input", "keygen", "link", "meta", "param", "source", "track", "wbr",
        ]
        // What the pass closes by itself, as a browser does, where a start
        // tag says so: a paragraph at the start of a block, a list item at
        // the next, a cell at the next cell or row.
        let closesParagraph: Set<String> = [
            "address", "article", "aside", "blockquote", "center", "details", "dir", "div", "dl",
            "fieldset", "figcaption", "figure", "footer", "h1", "h2", "h3", "h4", "h5", "h6",
            "header", "hgroup", "hr", "main", "menu", "nav", "ol", "p", "pre", "section",
            "summary", "table", "ul",
        ]
        let schemes: Set<String> = ["http", "https", "mailto", "tel", "sms", "cid", "data"]
        let b = Array(html.utf8)
        var open: [String] = []
        var deepest = 0
        var i = 0
        func fail(_ what: String) { XCTFail("quote, case \(number): \(what)") }
        while i < b.count {
            guard b[i] == UInt8(ascii: "<") else { i += 1; continue }
            var j = i + 1
            let closing = j < b.count && b[j] == UInt8(ascii: "/")
            if closing { j += 1 }
            let nameStart = j
            while j < b.count, b[j] != 0x20, b[j] != UInt8(ascii: ">") { j += 1 }
            let name = String(decoding: b[nameStart..<j], as: UTF8.self).lowercased()
            if refused.contains(name) { fail("<\(name)> written") }
            // Attributes, as the pass writes them: ` name` or ` name="value"`.
            while j < b.count, b[j] == 0x20 {
                j += 1
                let attributeStart = j
                while j < b.count, b[j] != UInt8(ascii: "="), b[j] != 0x20,
                      b[j] != UInt8(ascii: ">") { j += 1 }
                let attribute = String(decoding: b[attributeStart..<j], as: UTF8.self).lowercased()
                if attribute.hasPrefix("on") || ["srcdoc", "formaction", "action", "ping",
                                                 "http-equiv"].contains(attribute) {
                    fail("\(attribute)= written")
                }
                guard j < b.count, b[j] == UInt8(ascii: "=") else { continue }
                j += 2   // `="`
                let valueStart = j
                while j < b.count, b[j] != UInt8(ascii: "\"") { j += 1 }
                let value = String(decoding: b[min(valueStart, j)..<j], as: UTF8.self)
                j += 1
                if ["href", "src", "background", "poster", "cite", "longdesc", "lowsrc",
                    "dynsrc", "codebase"].contains(attribute),
                   let colon = value.firstIndex(of: ":"),
                   !value[..<colon].contains(where: { "/?#".contains($0) }) {
                    // Spaces and controls are skipped reading a scheme, as the
                    // pass reads one, and anything but the URL standard's
                    // letters, digits, `+`, `-` and `.` makes it no scheme at
                    // all but a relative address, to the pass and to a browser.
                    let scheme = String(value[..<colon].lowercased().unicodeScalars
                        .filter { $0.value > 0x20 })
                    let letters = Array(scheme.unicodeScalars)
                    let isScheme = letters.first.map { $0 >= "a" && $0 <= "z" } == true
                        && letters.allSatisfy { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9")
                            || $0 == "+" || $0 == "-" || $0 == "." }
                    if isScheme, !schemes.contains(scheme) {
                        fail("\(attribute)=\"\(scheme):…\" written")
                    }
                    if scheme == "data", !value.lowercased().hasPrefix("data:image/") {
                        fail("\(attribute)=\"\(value.prefix(20))…\" written")
                    }
                }
            }
            guard j < b.count, b[j] == UInt8(ascii: ">") else {
                fail("a tag not ended: \(String(decoding: b[i..<min(b.count, i + 40)], as: UTF8.self))")
                return
            }
            if closing {
                guard let at = open.lastIndex(of: name) else {
                    fail("</\(name)> closes nothing it opened")
                    return
                }
                open.removeSubrange(at...)
            } else {
                if name == "li", open.last == "li" { open.removeLast() }
                if ["dt", "dd"].contains(name), let last = open.last, ["dt", "dd"].contains(last) {
                    open.removeLast()
                }
                if ["td", "th"].contains(name), let last = open.last, ["td", "th"].contains(last) {
                    open.removeLast()
                }
                if name == "tr" {
                    if let last = open.last, ["td", "th"].contains(last) { open.removeLast() }
                    if open.last == "tr" { open.removeLast() }
                }
                if closesParagraph.contains(name), open.last == "p" { open.removeLast() }
                if !void.contains(name) {
                    open.append(name)
                    deepest = max(deepest, open.count)
                }
            }
            i = j + 1
        }
        XCTAssertLessThanOrEqual(deepest, QuotedMarkup.OpenElements.limit, "quote, case \(number)")
    }

    // MARK: - Letters

    func testALetterFromAStrangerIsDecodedInBoundedTimeAndSize() {
        let letters = OrdinaryMail.letters(count: 20).map { [UInt8]($0) }
        var n = Numbers(seed: seed ^ 0x6C65_7474_6572)
        for number in 0..<cases {
            let start = n.chance(10) ? [] : n.pick(letters)
            let raw = Data(mutated(start, &n, among: letters))

            let decoded = timed("decode", number) { MIMEDecoder.decodeMessage(raw) }
            let shown = (decoded.text?.utf8.count ?? 0) + (decoded.html?.utf8.count ?? 0)
            XCTAssertLessThanOrEqual(shown, 4 * raw.count + 64, "decode, case \(number)")
            XCTAssertLessThanOrEqual(decoded.attachments.count, MIMEDecoder.maxAttachments)

            let parsed = timed("parse", number) { MIMEDecoder.parse(raw) }
            XCTAssertLessThanOrEqual(parsed.bodies.values.map(\.count).max() ?? 0, raw.count)
            let listed = timed("listed", number) {
                MIMEDecoder.listedAttachments(in: parsed.structure)
            }
            XCTAssertLessThanOrEqual(listed.count, MIMEDecoder.maxAttachments)

            let headers = timed("headers", number) { MIMEDecoder.parseHeaders(raw) }
            let headerBytes = headers.map { $0.name.utf8.count + $0.value.utf8.count }.reduce(0, +)
            XCTAssertLessThanOrEqual(headerBytes, 2 * raw.count, "headers, case \(number)")
            for header in headers.prefix(20) {
                let word = timed("words", number) { MIMEDecoder.decodeWord(header.value) }
                XCTAssertLessThanOrEqual(word.utf8.count, 4 * header.value.utf8.count + 64,
                                         "words, case \(number)")
            }
        }
    }
}
