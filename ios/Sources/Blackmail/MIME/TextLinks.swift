import Foundation

/// The links a letter writes out as words, made into links the pane can
/// tap.
///
/// A plain-text letter reached the pane escaped and nothing more, and the
/// pane's WebKit has its data detectors off and runs no script of the
/// letter's, so an address such as `https://youtu.be/…` written in a letter
/// was words, not a link. About a third of the links he shares with himself
/// arrive that way. Mail makes them links, and so does this, while the page
/// is built, in Swift.
///
/// **What counts as a link**, as Mail finds them: `http://`, `https://`,
/// `www.` and `mailto:`, the first letter of each not run on from a letter
/// or a digit. It runs to the first space, line break, `"`, `<`, `>`,
/// backtick, `{`, `}`, `|`, `\`, `^`, or typographic quote, bracket or
/// ellipsis. Then, as Mail does, the punctuation that ends a sentence is
/// given back to the sentence: `.`, `,`, `;`, `:`, `!`, `?`, `'` and `*` at
/// the end, and a `)` or `]` at the end that nothing in the link opened, so
/// `(see https://example.com/a)` links `https://example.com/a` and a
/// Wikipedia address ending `_(film)` keeps its bracket. A `www.` address
/// needs a dot inside its host and goes to `http://`; a `mailto:` needs an
/// `@` with something after it.
///
/// **Safe.** In plain text the letter is cut into words and links before
/// anything is escaped, and every piece is then escaped: the words and the
/// link's text as the pane has always escaped them (`Escaping`), the address
/// as an attribute, so nothing of the sender's reaches the page as markup.
/// One pass from left to right takes each character into one link at most,
/// so nothing is linked twice. A letter with no link in it comes out byte
/// for byte as it did.
///
/// **HTML letters too, in their text only.** Mail makes a link of an
/// address written in the text of an HTML letter as well. Here that is done
/// only where it is certain to be text: outside every tag and attribute,
/// comment and declaration, never inside an `<a>` the sender wrote, nor in
/// `<script>`, `<style>`, `<textarea>`, `<title>` or a frame. A link there is
/// the text as it stands, character references and all, so it reads exactly
/// as it did; `&amp;` is taken into it as the `&` it means, and any other
/// reference ends it.
///
/// Where the markup stops being what this pass can follow, the rest of the
/// letter is left exactly as it came: a tag, a comment or an element's
/// content never closed; `<plaintext>`; and the places where HTML can
/// leave a sender's `<a>` open in ways a pass this simple cannot see,
/// `<svg>`, `<math>`, `<noscript>`, `<select>`, and a `<script>` with a
/// comment in it. And a sender's `<a>` that encloses a table, a cell or
/// the like is taken never to close, since HTML ignores an `</a>` that
/// would close it across one. Each of those makes no link where Mail might;
/// none can put a link inside the sender's.
///
/// Every step moves forward, so the work grows with the letter's length and
/// no letter can make it grow faster (`TextLinksTests`).
enum TextLinks {

    /// How a link was written, which decides where it goes.
    enum Kind: Equatable {
        /// `http://` or `https://`, as written.
        case web
        /// `www.`, to `http://` in front of it, as Mail sends it.
        case www
        /// `mailto:`, which the pane opens in this app's composer.
        case mailto
    }

    /// A link found, by the UTF-8 offsets of its first and past-its-last
    /// bytes in what was searched.
    struct Found: Equatable {
        let start: Int
        let end: Int
        let kind: Kind
    }

    /// What a page escapes in plain text, which each page has always done
    /// its own way, and still does, so a letter with no link in it comes
    /// out byte for byte as it did.
    enum Escaping {
        /// `&` and `<`: a letter's own page (`PanePage.letter`).
        case ampersandAndLessThan
        /// `&`, `<` and `>`: a letter in a conversation's stack, as
        /// `ConversationDocument.escape` does it.
        case ampersandAndBrackets
    }

    /// Plain text as the pane writes it into a page: escaped as `escaping`
    /// says, and every link an `<a>`.
    ///
    /// Escaped here, a byte at a time, rather than by `replacingOccurrences`
    /// on each piece between the links, which costs a few microseconds a
    /// call however short the piece: a megabyte of nothing but links took
    /// over half a second that way in a release build on this host, and
    /// takes 22 ms this way.
    static func plain(_ text: Substring, escaping: Escaping) -> String {
        let bytes = Array(text.utf8)
        let links = found(in: bytes, markup: false)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + bytes.count / 8 + links.count * 32)
        func escaped(_ range: Range<Int>, attribute: Bool = false) {
            for c in bytes[range] {
                switch c {
                case Ascii.amp: out.append(contentsOf: "&amp;".utf8)
                case Ascii.lt: out.append(contentsOf: "&lt;".utf8)
                case Ascii.gt where attribute || escaping == .ampersandAndBrackets:
                    out.append(contentsOf: "&gt;".utf8)
                case Ascii.quote where attribute: out.append(contentsOf: "&quot;".utf8)
                default: out.append(c)
                }
            }
        }
        var at = 0
        for link in links {
            escaped(at..<link.start)
            out.append(contentsOf: "<a href=\"".utf8)
            if link.kind == .www { out.append(contentsOf: "http://".utf8) }
            escaped(link.start..<link.end, attribute: true)
            out.append(contentsOf: "\">".utf8)
            escaped(link.start..<link.end)
            out.append(contentsOf: "</a>".utf8)
            at = link.end
        }
        escaped(at..<bytes.count)
        return String(decoding: out, as: UTF8.self)
    }

    /// A sender's markup with the links written in its text made `<a>`s.
    /// With none, the markup as it came.
    static func html(_ markup: String) -> String {
        let bytes = Array(markup.utf8)
        let links = found(in: bytes, markup: true)
        guard !links.isEmpty else { return markup }
        var out = ""
        out.reserveCapacity(bytes.count + links.count * 32)
        var at = 0
        for link in links {
            out += String(decoding: bytes[at..<link.start], as: UTF8.self)
            // As it stands in the markup, references and all: it holds no
            // `"`, `<` or `>`, which end a link, so it is as safe inside the
            // attribute as it was in the text, and reads the same in both.
            let raw = String(decoding: bytes[link.start..<link.end], as: UTF8.self)
            out += "<a href=\"" + (link.kind == .www ? "http://" : "") + raw + "\">" + raw + "</a>"
            at = link.end
        }
        out += String(decoding: bytes[at...], as: UTF8.self)
        return out
    }

    /// The links in `bytes`, in order and never overlapping. `markup` says
    /// whether the bytes are HTML, whose text alone is searched.
    static func found(in bytes: [UInt8], markup: Bool) -> [Found] {
        var scan = Scan(bytes: bytes, markup: markup)
        return scan.run()
    }

    /// How many steps the pass takes over `bytes`: every byte looked at,
    /// by every loop of it. What `TextLinksTests` holds to
    /// the length of the letter, since a count does not flake as a timing
    /// can.
    static func steps(in bytes: [UInt8], markup: Bool) -> Int {
        var scan = Scan(bytes: bytes, markup: markup)
        _ = scan.run()
        return scan.steps
    }
}

// MARK: - The pass

private struct Scan {
    let b: [UInt8]
    let markup: Bool
    let n: Int
    /// Inside an `<a>` of the sender's, where nothing is linked.
    private var inAnchor = false
    /// The `<a>` encloses an element across which HTML ignores its `</a>`
    /// (`scopes`), so it is taken as open for the rest of the letter.
    private var anchorHeld = false
    /// Where the run of link characters measured last began and ended, so a
    /// second candidate inside the same run does not measure it again.
    private var runFrom = -1
    private var runStop = -1
    /// Bytes looked at so far, by every loop (`TextLinks.steps`).
    private(set) var steps = 0

    init(bytes: [UInt8], markup: Bool) {
        b = bytes
        self.markup = markup
        n = bytes.count
    }

    mutating func run() -> [TextLinks.Found] {
        var links: [TextLinks.Found] = []
        var i = 0
        while i < n {
            steps += 1
            if markup && b[i] == Ascii.lt {
                // Nil: markup this pass cannot follow. The rest is left as
                // it came.
                guard let next = skipMarkup(at: i) else { break }
                i = next
                continue
            }
            if !inAnchor, let (kind, body) = start(at: i) {
                switch link(from: i, kind: kind, body: body) {
                case .link(let found):
                    links.append(found)
                    i = found.end
                    continue
                case .skip(let to):
                    i = to
                    continue
                case .none:
                    break
                }
            }
            i += 1
        }
        return links
    }

    // MARK: Where a link can begin

    /// The kind of link beginning at `i`, and where its body starts, after
    /// `https://`, `www.` or `mailto:`.
    private func start(at i: Int) -> (TextLinks.Kind, Int)? {
        let c = b[i] | 0x20
        guard c == Ascii.h || c == Ascii.w || c == Ascii.m else { return nil }
        let before: UInt8? = i > 0 ? b[i - 1] : nil
        // Not run on from a word: "xhttp://" is not a link. Anything past
        // ASCII is taken as a boundary, so a link inside typographic quotes
        // is found.
        if let before, Ascii.isAlnum(before) { return nil }
        switch c {
        case Ascii.h:
            if has("https://", at: i) { return (.web, i + 8) }
            if has("http://", at: i) { return (.web, i + 7) }
        case Ascii.m:
            if has("mailto:", at: i) { return (.mailto, i + 7) }
        default:
            // Nor the "www" of a host or path already under way: after a
            // dot, a hyphen, an `@`, a slash or the like it is part of
            // something else (`Ascii.continuesHost`).
            if let before, Ascii.continuesHost(before) { return nil }
            if has("www.", at: i) { return (.www, i + 4) }
        }
        return nil
    }

    /// Whether `prefix`, written in lower case, is at `i` in any case.
    private func has(_ prefix: StaticString, at i: Int) -> Bool {
        let count = prefix.utf8CodeUnitCount
        guard i + count <= n else { return false }
        let p = prefix.utf8Start
        for k in 0..<count where Ascii.lower(b[i + k]) != p[k] { return false }
        return true
    }

    // MARK: One link

    private enum Outcome {
        case link(TextLinks.Found)
        /// Not a link, nor anything else in the run it began in.
        case skip(to: Int)
        /// Not a link; the next byte may begin one.
        case none
    }

    private mutating func link(from start: Int, kind: TextLinks.Kind, body: Int) -> Outcome {
        // Checked before the run is measured, so a string of false starts
        // costs a byte or two each.
        guard body < n, unit(at: body) > 0 else { return .none }
        let first = b[body]
        switch kind {
        case .web:
            guard Ascii.isAlnum(first) || first >= 0x80 || first == Ascii.openSquare else { return .none }
        case .www:
            guard Ascii.isAlnum(first) || first >= 0x80 else { return .none }
        case .mailto:
            break
        }
        let stop = runEnd(from: body)
        if kind == .www && !hostHasDot(from: body, to: stop) { return .none }
        let end = trimmed(body: body, stop: stop)
        switch kind {
        case .web, .www:
            // The body's first byte is none of what trimming gives back.
            return .link(.init(start: start, end: end, kind: kind))
        case .mailto:
            var p = body
            while p < end, b[p] != Ascii.at {
                steps += 1
                p += 1
            }
            // No `@` with anything after it, and no later `mailto:` in the
            // same run can have one either: its `@`s are these.
            guard p + 1 < end else { return .skip(to: stop) }
            return .link(.init(start: start, end: end, kind: kind))
        }
    }

    /// Where the run of link characters from `from` stops.
    private mutating func runEnd(from: Int) -> Int {
        if from >= runFrom && from < runStop { return runStop }
        var p = from
        while p < n {
            steps += 1
            let step = unit(at: p)
            if step == 0 { break }
            p += step
        }
        runFrom = from
        runStop = p
        return p
    }

    /// How many bytes at `p` belong to a link: one for most ASCII, the
    /// scalar's length past ASCII, five for `&amp;` in markup, and 0 where
    /// a link stops.
    private func unit(at p: Int) -> Int {
        let c = b[p]
        if c < 0x80 {
            if c <= 0x20 || c == 0x7F { return 0 }
            switch c {
            case Ascii.quote, Ascii.lt, Ascii.gt, Ascii.backtick, Ascii.openBrace,
                 Ascii.closeBrace, Ascii.bar, Ascii.backslash, Ascii.caret:
                return 0
            case Ascii.amp where markup:
                return reference(at: p)
            default:
                return 1
            }
        }
        let length = c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : c >= 0xC0 ? 2 : 1
        guard length > 1, p + length <= n else { return 0 }
        var value = UInt32(c) & (length == 2 ? 0x1F : length == 3 ? 0x0F : 0x07)
        for k in 1..<length { value = value << 6 | UInt32(b[p + k] & 0x3F) }
        guard let scalar = Unicode.Scalar(value),
              !scalar.properties.isWhitespace, !Self.stops.contains(value) else { return 0 }
        return length
    }

    /// Past ASCII, what ends a link besides white space: the invisible
    /// spaces, typographic quotes and brackets, the full-width punctuation
    /// of Chinese and Japanese text, and the ellipsis.
    private static let stops: Set<UInt32> = [
        0x200B, 0x2060, 0xFEFF,
        0x2018, 0x2019, 0x201A, 0x201B, 0x201C, 0x201D, 0x201E, 0x201F,
        0x00AB, 0x00BB, 0x2039, 0x203A,
        0x3008, 0x3009, 0x300A, 0x300B, 0x300C, 0x300D, 0x300E, 0x300F, 0x3010, 0x3011,
        0x3001, 0x3002, 0xFF08, 0xFF09, 0xFF0C, 0xFF1A, 0xFF1B, 0xFF01, 0xFF1F,
        0x2026,
    ]

    /// A `&` in markup's text: `&amp;` is the `&` it means, and part of the
    /// link. Any other reference ends the link, since it may stand for a
    /// space, a quote or a bracket; so does one without its `;` that the
    /// parser reads as `<`, `>`, `"` or a no-break space. A bare `&`, as in
    /// `?a=1&b=2`, is part of it.
    private func reference(at p: Int) -> Int {
        if has("&amp;", at: p) { return 5 }
        let q = p + 1
        guard q < n else { return 1 }
        if b[q] == Ascii.hash { return 0 }
        var e = q
        while e < n, e - q < 32, Ascii.isAlnum(b[e]) { e += 1 }
        guard e > q else { return 1 }
        if e < n && b[e] == Ascii.semicolon { return 0 }
        for name: StaticString in ["lt", "gt", "quot", "nbsp"] where has(name, at: q) { return 0 }
        return 1
    }

    /// Whether the host of a `www.` link, up to its path, query, fragment
    /// or port, has a dot with a label after it: `www.example.com`, not
    /// `www.example`.
    private mutating func hostHasDot(from body: Int, to stop: Int) -> Bool {
        var p = body
        while p + 1 < stop {
            steps += 1
            let c = b[p]
            if c == Ascii.slash || c == Ascii.question || c == Ascii.hash || c == Ascii.colon {
                return false
            }
            if c == Ascii.dot && (Ascii.isAlnum(b[p + 1]) || b[p + 1] >= 0x80) { return true }
            p += 1
        }
        return false
    }

    /// The end of a link running to `stop`, with the punctuation that ends
    /// a sentence given back: see `TextLinks`. A `;` that closes `&amp;` in
    /// markup is the `&`, and stays.
    private mutating func trimmed(body: Int, stop: Int) -> Int {
        var opens = 0, closes = 0, squareOpens = 0, squareCloses = 0
        for p in body..<stop {
            steps += 1
            switch b[p] {
            case Ascii.openParen: opens += 1
            case Ascii.closeParen: closes += 1
            case Ascii.openSquare: squareOpens += 1
            case Ascii.closeSquare: squareCloses += 1
            default: break
            }
        }
        var end = stop
        trimming: while end > body {
            steps += 1
            switch b[end - 1] {
            case Ascii.semicolon where markup && end - 5 >= body && has("&amp;", at: end - 5):
                break trimming
            case Ascii.dot, Ascii.comma, Ascii.semicolon, Ascii.colon, Ascii.bang,
                 Ascii.question, Ascii.apostrophe, Ascii.star:
                end -= 1
            case Ascii.closeParen where closes > opens:
                closes -= 1
                end -= 1
            case Ascii.closeSquare where squareCloses > squareOpens:
                squareCloses -= 1
                end -= 1
            default:
                break trimming
            }
        }
        return end
    }

    // MARK: Markup

    /// Elements whose content is not markup's text, and holds no link of
    /// the letter's: skipped to their end tag, which nothing inside them
    /// can stand in for.
    private static let skipped: Set<String> = [
        "script", "style", "textarea", "title", "xmp", "iframe", "noembed", "noframes",
    ]

    /// Elements the pass does not go past. `<plaintext>` makes the rest of
    /// the letter text. In `<svg>` and `<math>` a tag such as `<p>` or `<b>`
    /// breaks back out into HTML, where an `<a>` then opens that a skip to
    /// the end tag would miss; `<noscript>` is markup or text depending on
    /// how WebKit parses it; and `<select>` is closed early by a table's
    /// tags. Any of them could hide a sender's `<a>` still open after it.
    private static let unfollowed: Set<String> = ["plaintext", "svg", "math", "noscript", "select"]

    /// The elements that bound an `<a>`'s scope in HTML: an `</a>` inside
    /// one cannot close an `<a>` opened outside it, and is ignored.
    private static let scopes: Set<String> = [
        "applet", "caption", "marquee", "object", "table", "td", "th", "template",
    ]

    /// Past the `<` at `i` and whatever it opens: a tag with its
    /// attributes, an element whose content is skipped, a comment, a
    /// declaration. A `<` that opens nothing is text, and the pass moves one
    /// byte on. Nil where the markup does not go on in a way this pass can
    /// follow.
    private mutating func skipMarkup(at i: Int) -> Int? {
        guard i + 1 < n else { return i + 1 }
        let c = b[i + 1]
        if Ascii.isAlpha(c) {
            let (name, afterName) = tagName(from: i + 1)
            guard let end = tagEnd(from: afterName) else { return nil }
            if Self.unfollowed.contains(name) { return nil }
            if name == "a" {
                inAnchor = true
            } else if inAnchor && Self.scopes.contains(name) {
                anchorHeld = true
            }
            if Self.skipped.contains(name) {
                guard let close = endTag(name, from: end) else { return nil }
                // `<!--` in a script can hide its first `</script>`.
                if name == "script" && contains("<!--", from: end, to: close) { return nil }
                return close
            }
            return end
        }
        switch c {
        case Ascii.slash:
            guard i + 2 < n else { return nil }
            let d = b[i + 2]
            if Ascii.isAlpha(d) {
                let (name, afterName) = tagName(from: i + 2)
                guard let end = tagEnd(from: afterName) else { return nil }
                if name == "a" && !anchorHeld { inAnchor = false }
                return end
            }
            if d == Ascii.gt { return i + 3 }
            return past(Ascii.gt, from: i + 2)
        case Ascii.bang:
            if has("<!--", at: i) { return commentEnd(from: i + 4) }
            // A doctype, or `<![CDATA[`, which outside SVG and MathML is a
            // comment to the first `>`.
            return past(Ascii.gt, from: i + 2)
        case Ascii.question:
            return past(Ascii.gt, from: i + 2)
        default:
            return i + 1
        }
    }

    /// A tag's name from `from`, lower-cased, and where it ends: at white
    /// space, `/` or `>`, as HTML ends one. A name longer than any this pass
    /// looks for comes back empty, which spares making a string of it.
    private mutating func tagName(from: Int) -> (String, Int) {
        var p = from
        while p < n, !Ascii.isSpace(b[p]), b[p] != Ascii.slash, b[p] != Ascii.gt {
            steps += 1
            p += 1
        }
        guard p - from <= 9 else { return ("", p) }
        return (String(decoding: b[from..<p], as: UTF8.self).lowercased(), p)
    }

    /// Past the `>` that ends a tag whose name ends at `from`, reading its
    /// attributes as HTML does, so a `>` inside a quoted value does not end
    /// it and a quote that is not a value's does not open one.
    private mutating func tagEnd(from: Int) -> Int? {
        enum State { case beforeName, name, afterName, beforeValue }
        var state = State.beforeName
        var p = from
        while p < n {
            steps += 1
            let c = b[p]
            switch state {
            case .beforeName:
                if c == Ascii.gt { return p + 1 }
                if !Ascii.isSpace(c) && c != Ascii.slash { state = .name }
                p += 1
            case .name:
                if c == Ascii.gt { return p + 1 }
                if Ascii.isSpace(c) { state = .afterName }
                else if c == Ascii.slash { state = .beforeName }
                else if c == Ascii.equals { state = .beforeValue }
                p += 1
            case .afterName:
                if c == Ascii.gt { return p + 1 }
                if c == Ascii.slash { state = .beforeName }
                else if c == Ascii.equals { state = .beforeValue }
                else if !Ascii.isSpace(c) { state = .name }
                p += 1
            case .beforeValue:
                if c == Ascii.gt { return p + 1 }
                if c == Ascii.quote || c == Ascii.apostrophe {
                    guard let close = past(c, from: p + 1) else { return nil }
                    p = close
                    state = .beforeName
                } else if Ascii.isSpace(c) {
                    p += 1
                } else {
                    while p < n, !Ascii.isSpace(b[p]), b[p] != Ascii.gt {
                        steps += 1
                        p += 1
                    }
                    state = .beforeName
                }
            }
        }
        return nil
    }

    /// Past the end tag of `name`, from `from`: `</name` followed by white
    /// space, `/` or `>`, in any case, and its own `>`.
    private mutating func endTag(_ name: String, from: Int) -> Int? {
        let wanted = Array(name.utf8)
        var p = from
        while p + 2 + wanted.count < n {
            steps += 1
            if b[p] == Ascii.lt && b[p + 1] == Ascii.slash {
                var k = 0
                while k < wanted.count, Ascii.lower(b[p + 2 + k]) == wanted[k] {
                    steps += 1
                    k += 1
                }
                let after = p + 2 + wanted.count
                if k == wanted.count,
                   Ascii.isSpace(b[after]) || b[after] == Ascii.slash || b[after] == Ascii.gt {
                    return tagEnd(from: after)
                }
            }
            p += 1
        }
        return nil
    }

    /// Past a comment's end, from just after its `<!--`: `-->`, or `--!>`,
    /// or at once for `<!-->` and `<!--->`, as HTML ends one.
    private mutating func commentEnd(from: Int) -> Int? {
        if from < n && b[from] == Ascii.gt { return from + 1 }
        if from + 1 < n && b[from] == Ascii.dash && b[from + 1] == Ascii.gt { return from + 2 }
        var p = from
        while p + 2 < n {
            steps += 1
            if b[p] == Ascii.dash && b[p + 1] == Ascii.dash {
                if b[p + 2] == Ascii.gt { return p + 3 }
                if b[p + 2] == Ascii.bang && p + 3 < n && b[p + 3] == Ascii.gt { return p + 4 }
            }
            p += 1
        }
        return nil
    }

    /// Whether `text` is anywhere in `from..<to`.
    private mutating func contains(_ text: StaticString, from: Int, to: Int) -> Bool {
        var p = from
        while p + text.utf8CodeUnitCount <= to {
            steps += 1
            if has(text, at: p) { return true }
            p += 1
        }
        return false
    }

    /// Past the first `byte` from `from`.
    private mutating func past(_ byte: UInt8, from: Int) -> Int? {
        var p = from
        while p < n {
            steps += 1
            if b[p] == byte { return p + 1 }
            p += 1
        }
        return nil
    }
}

/// The bytes the pass looks at, by name.
private enum Ascii {
    static let h: UInt8 = 0x68, w: UInt8 = 0x77, m: UInt8 = 0x6D
    static let quote: UInt8 = 0x22, hash: UInt8 = 0x23, amp: UInt8 = 0x26, apostrophe: UInt8 = 0x27
    static let openParen: UInt8 = 0x28, closeParen: UInt8 = 0x29, star: UInt8 = 0x2A
    static let comma: UInt8 = 0x2C, dash: UInt8 = 0x2D, dot: UInt8 = 0x2E, slash: UInt8 = 0x2F
    static let colon: UInt8 = 0x3A, semicolon: UInt8 = 0x3B, lt: UInt8 = 0x3C, equals: UInt8 = 0x3D
    static let gt: UInt8 = 0x3E, question: UInt8 = 0x3F, at: UInt8 = 0x40, bang: UInt8 = 0x21
    static let openSquare: UInt8 = 0x5B, backslash: UInt8 = 0x5C, closeSquare: UInt8 = 0x5D
    static let caret: UInt8 = 0x5E, underscore: UInt8 = 0x5F, backtick: UInt8 = 0x60
    static let openBrace: UInt8 = 0x7B, bar: UInt8 = 0x7C, closeBrace: UInt8 = 0x7D
    static let percent: UInt8 = 0x25, plus: UInt8 = 0x2B, tilde: UInt8 = 0x7E

    static func isAlpha(_ c: UInt8) -> Bool { (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7A }
    /// An ASCII capital as its small letter; every other byte as it is.
    static func lower(_ c: UInt8) -> UInt8 { c >= 0x41 && c <= 0x5A ? c | 0x20 : c }
    static func isAlnum(_ c: UInt8) -> Bool { isAlpha(c) || (c >= 0x30 && c <= 0x39) }
    /// HTML's white space: tab, line feed, form feed, carriage return, space.
    static func isSpace(_ c: UInt8) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D
    }
    /// What, before a `www`, makes it part of a host or path already
    /// under way.
    static func continuesHost(_ c: UInt8) -> Bool {
        c == dot || c == dash || c == underscore || c == at || c == slash || c == colon
            || c == percent || c == plus || c == tilde || c == equals
    }
}
