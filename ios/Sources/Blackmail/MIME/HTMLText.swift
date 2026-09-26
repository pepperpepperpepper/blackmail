import Foundation

/// Readable text out of an HTML mail body.
///
/// Two callers with different needs share this. `PreviewText` wants one
/// flattened line for a list row; reply and forward want the whole body with
/// its paragraphs intact, to quote underneath a letter. Both want the same
/// thing from the *parser*, so the scanner lives here once and each caller
/// finishes the job its own way.
///
/// Not a parser and not trying to be. It walks the fragment once, drops the
/// elements whose contents are machinery rather than words, turns the rest
/// into text with line breaks where the markup implied them, and decodes the
/// entities that actually turn up in mail.
///
/// Nothing here may throw and nothing may hang. The input is whatever a
/// stranger chose to send, sometimes truncated mid-tag by a byte-counted
/// fetch, and the worst acceptable outcome is less text than hoped for.
enum HTMLText {

    /// Elements whose contents are not text the reader would recognise. The
    /// first two matter most: an HTML mail's stylesheet routinely runs longer
    /// than the message, and without this every preview would read
    /// "td { padding:0 } .wrap { width:600px }".
    private static let droppedElements: Set<String> = ["head", "style", "script", "title"]

    /// Elements that end a line.
    private static let blockElements: Set<String> = [
        "p", "div", "br", "tr", "li", "table", "blockquote", "ul", "ol", "hr",
        "h1", "h2", "h3", "h4", "h5", "h6", "section", "article", "header",
        "footer", "pre", "figure", "dl", "dt", "dd", "body",
    ]

    /// Elements that separate words without ending the line: the cells of a
    /// row. `<td>Jan</td><td>Feb</td>` is two words and must not run together
    /// into "JanFeb", but the row it sits in is one line.
    ///
    /// This list used to be every non-block tag, which was wrong and was
    /// corrupting real mail. An inline element does NOT introduce white space
    /// — no browser renders `info<span>rmation</span>` as two words — so
    /// emitting a space at every `<span>`, `<b>` and `<font>` boundary broke
    /// words in half wherever a sender had styled part of one. Sam's own
    /// confidentiality notice came back from this quoted as "confidential
    /// and/or privileged info rmation", in every reply the app has ever sent.
    /// Only the cells genuinely need the separator.
    private static let separatingElements: Set<String> = ["td", "th"]

    /// The whole body as text, paragraphs preserved.
    ///
    /// Anything the scanner cannot finish reading ends the text there rather
    /// than guessing: a fragment that stopped inside `<style>` yields nothing
    /// at all, which is honest and no worse than the blank we would otherwise
    /// have shown.
    static func plainText(from html: String) -> String {
        tidyLines(decodingEntities(scan(html)))
    }

    // MARK: - The scan

    private static func scan(_ html: String) -> String {
        let chars = Array(html)
        let commentOpen = Array("<!--")
        let commentClose = Array("-->")

        var out = ""
        var skipping: String?
        var i = 0

        while i < chars.count {
            guard chars[i] == "<" else {
                if skipping == nil { out.append(chars[i]) }
                i += 1
                continue
            }

            if matches(chars, at: i, commentOpen) {
                // A conditional comment can hold a whole second stylesheet, so
                // its contents go whole. An unterminated one is the end.
                guard let end = index(of: commentClose, in: chars, from: i + commentOpen.count) else {
                    break
                }
                i = end + commentClose.count
                continue
            }

            // An unterminated tag means the fragment stopped inside one, so
            // there is no more readable text to be had.
            guard let close = indexOfTagEnd(chars, from: i) else { break }
            let tag = tagName(chars, open: i, close: close)

            if let open = skipping {
                if tag.isClosing, tag.name == open { skipping = nil }
            } else if !tag.isClosing, droppedElements.contains(tag.name) {
                skipping = tag.name
            }
            if skipping == nil {
                // A block tag separates lines, a cell separates words, and an
                // inline tag separates nothing at all.
                if blockElements.contains(tag.name) {
                    out.append("\n")
                } else if separatingElements.contains(tag.name) {
                    out.append(" ")
                }
            }
            i = close + 1
        }
        return out
    }

    // MARK: - Entities

    /// `&amp;` and friends, including numeric references — a template that
    /// writes `&#8217;` for an apostrophe is not unusual.
    static func decodingEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let chars = Array(text)
        var out = ""
        var i = 0
        while i < chars.count {
            guard chars[i] == "&" else {
                out.append(chars[i])
                i += 1
                continue
            }
            var j = i + 1
            var body = ""
            while j < chars.count, chars[j] != ";", !chars[j].isWhitespace, body.count < 12 {
                body.append(chars[j])
                j += 1
            }
            // A bare ampersand in running text ("Marks & Spencer") is left
            // exactly as it is rather than eaten as a malformed entity.
            guard j < chars.count, chars[j] == ";", let replacement = entity(body) else {
                out.append("&")
                i += 1
                continue
            }
            out += replacement
            i = j + 1
        }
        return out
    }

    private static func entity(_ body: String) -> String? {
        guard !body.isEmpty else { return nil }
        guard body.hasPrefix("#") else { return namedEntities[body.lowercased()] }

        let digits = body.dropFirst()
        let value: UInt32?
        if digits.hasPrefix("x") || digits.hasPrefix("X") {
            value = UInt32(digits.dropFirst(), radix: 16)
        } else {
            value = UInt32(digits)
        }
        // Unicode.Scalar rejects surrogates and out-of-range values, so a
        // nonsense reference stays literal text rather than crashing.
        guard let value, let scalar = Unicode.Scalar(value) else { return nil }
        return String(Character(scalar))
    }

    /// Only the entities that turn up in mail. A full table would be five
    /// hundred lines to make a quote marginally prettier, and anything
    /// missing survives as its own literal text, which is legible.
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "zwnj": "\u{200C}", "shy": "",
        "mdash": "\u{2014}", "ndash": "\u{2013}", "hellip": "\u{2026}",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "sbquo": "\u{201A}",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "bdquo": "\u{201E}",
        "copy": "\u{00A9}", "reg": "\u{00AE}", "trade": "\u{2122}",
        "euro": "\u{20AC}", "pound": "\u{00A3}", "cent": "\u{00A2}", "yen": "\u{00A5}",
        "bull": "\u{2022}", "middot": "\u{00B7}", "deg": "\u{00B0}",
        "laquo": "\u{00AB}", "raquo": "\u{00BB}", "times": "\u{00D7}",
    ]

    // MARK: - Tidying

    /// Squeezes each line's internal white space, drops blank lines beyond
    /// one, and trims the ends.
    ///
    /// Necessary because the markup carries its own indentation: a template
    /// nests tables eight deep and every line arrives with a fistful of
    /// leading spaces and a dozen blank lines between paragraphs. Quoting
    /// that verbatim produces a reply nobody can read.
    private static func tidyLines(_ text: String) -> String {
        var lines: [String] = []
        var blankRun = 0

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = squeezeSpaces(String(rawLine))
            if line.isEmpty {
                blankRun += 1
                // One blank line between paragraphs, never eight.
                if blankRun == 1, !lines.isEmpty { lines.append("") }
                continue
            }
            blankRun = 0
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    private static func squeezeSpaces(_ line: String) -> String {
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        var started = false

        for scalar in line.unicodeScalars {
            // Scalars, not Characters. A zero-width joiner is a format
            // character, so Swift folds it into the grapheme cluster in front
            // of it and iterating Characters can never see it on its own.
            if isZeroWidth(scalar) { continue }
            if scalar.properties.isWhitespace {
                pendingSpace = started
                continue
            }
            if pendingSpace {
                out.append(" ")
                pendingSpace = false
            }
            out.append(scalar)
            started = true
        }
        return String(out)
    }

    static func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200B...0x200F,      // zero-width space/joiner, direction marks
             0x00AD,               // soft hyphen
             0x2060, 0xFEFF:       // word joiner, BOM
            return true
        default:
            return false
        }
    }

    // MARK: - Scanning primitives

    /// The `>` that ends a tag, respecting quotes — an attribute may contain
    /// one, and `<img alt="a > b">` cut at the first `>` spills `b">` into the
    /// text.
    private static func indexOfTagEnd(_ chars: [Character], from open: Int) -> Int? {
        var quote: Character?
        var i = open + 1
        while i < chars.count {
            let c = chars[i]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == ">" {
                return i
            }
            i += 1
        }
        return nil
    }

    private static func tagName(_ chars: [Character], open: Int, close: Int) -> (name: String, isClosing: Bool) {
        var i = open + 1
        var isClosing = false
        if i < close, chars[i] == "/" {
            isClosing = true
            i += 1
        }
        var name = ""
        while i < close, name.count <= 16 {
            let c = chars[i]
            if c == "/" || c.isWhitespace { break }
            name.append(c)
            i += 1
        }
        return (name.lowercased(), isClosing)
    }

    private static func matches(_ chars: [Character], at index: Int, _ needle: [Character]) -> Bool {
        guard index >= 0, index + needle.count <= chars.count else { return false }
        for k in 0..<needle.count where chars[index + k] != needle[k] { return false }
        return true
    }

    private static func index(of needle: [Character], in chars: [Character], from start: Int) -> Int? {
        guard !needle.isEmpty, start >= 0 else { return nil }
        var i = start
        while i + needle.count <= chars.count {
            if matches(chars, at: i, needle) { return i }
            i += 1
        }
        return nil
    }
}
