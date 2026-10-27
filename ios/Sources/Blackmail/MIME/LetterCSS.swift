import Foundation

/// A letter's own style sheets, read as far as the dark pane needs them
/// (B-169), and nothing else done with them.
///
/// Two things read them. Mail's rule for drawing a letter in Dark Mode
/// (`LetterScheme`) asks what colour scheme the letter gives its root and
/// whether its body has a background picture: `rules`, each with whether
/// the media it is under matches the pane (`mediaMatchesPane`), and
/// `declarations`. And a letter drawn in its own dark colours brings the
/// style sheets of its head, which taking off its wrapper takes off with
/// the head (`DocumentWrapper`), back into the pane, each rule made to
/// apply inside that letter alone (`scoped`): its rules for the dark are
/// in them.
///
/// Read as CSS's own syntax reads a sheet, as far as that goes: comments,
/// strings and escapes skipped, a block to its matching brace or the end,
/// a rule whose block never opens dropped. Not a CSS engine: no value is
/// computed. One pass over the bytes, so a letter of megabytes is read in
/// linear time. Pure and Foundation-only, so the suite on Linux can test
/// it.
enum LetterCSS {

    /// One style rule of a sheet.
    struct Rule: Equatable {
        /// Its selectors, comments taken out, each trimmed.
        let selectors: [String]
        let declarations: [Declaration]
        /// Whether every `@media` it is under matches the pane, a dark pane
        /// on a screen (`mediaMatchesPane`); under none, true.
        let matchesPane: Bool
    }

    /// One declaration of a block.
    struct Declaration: Equatable {
        /// The property's name, in lower case.
        let name: String
        /// Its value, comments taken out, trimmed, with no `!important`.
        let value: String
        let important: Bool
    }

    // MARK: - Reading

    /// Every style rule of `css`, in its order: those at the top, and those
    /// inside `@media`, `@supports` and `@layer`, `@supports` taken to
    /// hold. Rules inside any other at-rule, `@container` among them, are
    /// left out, as none of them can be known to apply.
    static func rules(in css: String) -> [Rule] {
        let b = Array(css.utf8)
        var out: [Rule] = []
        collect(b, 0..<b.count, matches: true, into: &out)
        return out
    }

    private static func collect(_ b: [UInt8], _ range: Range<Int>, matches: Bool, into out: inout [Rule]) {
        for item in Walk(b: b).items(in: range) {
            switch item {
            case let .rule(prelude, block):
                out.append(Rule(selectors: selectors(String(decoding: b[prelude], as: UTF8.self)),
                                declarations: declarations(in: String(decoding: b[block], as: UTF8.self)),
                                matchesPane: matches))
            case let .atRule(name, prelude, block):
                guard let block else { continue }
                switch name {
                case "media":
                    let query = String(decoding: b[prelude], as: UTF8.self)
                    collect(b, block, matches: matches && mediaMatchesPane(query), into: &out)
                case "supports", "layer":
                    collect(b, block, matches: matches, into: &out)
                default:
                    continue
                }
            }
        }
    }

    /// The selectors of a rule's prelude: split at its commas that are not
    /// inside brackets, parentheses or a string, comments out, each
    /// trimmed. A selector holding a brace or a semicolon, which no
    /// selector can, is kept as it is, and matches nothing here.
    static func selectors(_ prelude: String) -> [String] {
        let b = Array(withoutComments(prelude).utf8)
        var out: [String] = []
        var start = 0
        var depth = 0
        var i = 0
        while i < b.count {
            let c = b[i]
            if c == backslash { i += 2; continue }
            if c == quote || c == apostrophe { i = Walk(b: b).stringEnd(at: i); continue }
            if c == openParen || c == openBracket { depth += 1 }
            if (c == closeParen || c == closeBracket) && depth > 0 { depth -= 1 }
            if c == comma && depth == 0 {
                out.append(trimmed(b[start..<i]))
                start = i + 1
            }
            i += 1
        }
        out.append(trimmed(b[start..<min(i, b.count)]))
        return out
    }

    /// The declarations of a block, or of an element's `style`: split at
    /// its semicolons outside brackets, parentheses, braces and strings,
    /// each `name: value`, `!important` taken off the value and said.
    /// A piece with no colon, or no name before it, is no declaration.
    static func declarations(in block: String) -> [Declaration] {
        let b = Array(withoutComments(block).utf8)
        var out: [Declaration] = []
        var start = 0
        var depth = 0
        var i = 0
        func take(_ piece: ArraySlice<UInt8>) {
            guard let colon = piece.firstIndex(of: UInt8(ascii: ":")) else { return }
            let name = trimmed(piece[piece.startIndex..<colon]).lowercased()
            guard !name.isEmpty, name.utf8.allSatisfy(isNameByte) else { return }
            var value = piece[(colon + 1)...]
            var important = false
            if let bang = value.lastIndex(of: UInt8(ascii: "!")) {
                var word = value[(bang + 1)...]
                while let c = word.first, isSpace(c) { word = word.dropFirst() }
                while let c = word.last, isSpace(c) { word = word.dropLast() }
                if equalsLowered(word, "important") {
                    important = true
                    value = value[..<bang]
                }
            }
            out.append(Declaration(name: name, value: trimmed(value), important: important))
        }
        while i < b.count {
            let c = b[i]
            if c == backslash { i += 2; continue }
            if c == quote || c == apostrophe { i = Walk(b: b).stringEnd(at: i); continue }
            if c == openParen || c == openBracket || c == openBrace { depth += 1 }
            if (c == closeParen || c == closeBracket || c == closeBrace) && depth > 0 { depth -= 1 }
            if c == semicolon && depth == 0 {
                take(b[start..<i])
                start = i + 1
            }
            i += 1
        }
        if start < b.count { take(b[start..<b.count]) }
        return out
    }

    /// Whether a media query list matches the pane: WebKit drawing a page
    /// on a screen, in the dark, which the pane always is (D-010). A query
    /// matches when its media type is none, `all` or `screen`, `only`
    /// before it or not, and each feature it tests is
    /// `prefers-color-scheme: dark`. Any other feature, a width, a
    /// `prefers-color-scheme: light`, a `not`, `print`, is taken not to
    /// match: what the pane's width is cannot be known from here. One
    /// query of the list matching is enough; an empty list matches.
    static func mediaMatchesPane(_ query: String) -> Bool {
        let list = withoutComments(query).lowercased()
        let queries = selectors(list)
        if queries.count == 1, queries[0].isEmpty { return true }
        return queries.contains { q in
            var words = ""
            var features: [String] = []
            var feature = ""
            var depth = 0
            for ch in q {
                if ch == "(" {
                    depth += 1
                    if depth == 1 { feature = ""; continue }
                }
                if ch == ")" && depth > 0 {
                    depth -= 1
                    if depth == 0 { features.append(feature); words += " "; continue }
                }
                if depth > 0 { feature.append(ch) } else { words.append(ch) }
            }
            guard depth == 0, !q.isEmpty else { return false }
            let allowed: Set<Substring> = ["only", "screen", "all", "and"]
            guard words.split(whereSeparator: { $0.isWhitespace }).allSatisfy(allowed.contains) else {
                return false
            }
            return features.allSatisfy {
                $0.filter { !$0.isWhitespace } == "prefers-color-scheme:dark"
            }
        }
    }

    // MARK: - Scoping

    /// `css` with each of its rules made to apply inside the element
    /// `scope` names, a selector such as `#bm-own-1_2`, and nowhere else.
    ///
    /// That element stands for the letter's root, a `div` of the class
    /// `rootClass`, and its child, a `div` of the class `bodyClass`, for its
    /// body, the letter's markup inside it (`PanePage.inOwnColours`). A
    /// selector that begins at the letter's root or body, `:root`, `html`,
    /// `body` or a run of them (`html body`, `html > body`), the body's
    /// compound with more in it too (`body.x`, `body:hover`), names those
    /// two in their place, each by a compound that weighs what it stood
    /// for: `div` for `html` and `body`, `.bm-own-root` for each `:root`,
    /// the box by `:where`, which adds nothing; so `body td` weighs two
    /// types, as in Mail. Written `#box td`, as it was, it weighed an id
    /// and beat the letter's own `.dark td`. Any other has `:where(scope)`
    /// before it, so it too weighs as in Mail against the letter's rules.
    /// Inside `@media`, `@supports`, `@layer`, `@container`,
    /// `@starting-style` and `@document` the same, the at-rule kept; the
    /// at-rules that name no element (`namesNoElement`), `@font-face`,
    /// `@keyframes`, `@page` among them, kept as they are; any other with a
    /// block, `@scope` among them, left out, as what it names could not be
    /// kept inside. `@import`, `@charset` and `@namespace` are left out: an
    /// imported sheet could not be scoped. A rule with a selector that
    /// cannot be one, a brace or a semicolon in it, is left out, as CSS
    /// drops it. Comments go. `</` is written `<\/`, which CSS reads as the
    /// same two characters, so the sheet can never end the `<style>` it
    /// goes in.
    static func scoped(_ css: String, in scope: String) -> String {
        let b = Array(css.utf8)
        var out = ""
        emit(b, 0..<b.count, scope: scope, into: &out)
        return out.contains("</") ? out.replacingOccurrences(of: "</", with: "<\\/") : out
    }

    private static func emit(_ b: [UInt8], _ range: Range<Int>, scope: String, into out: inout String) {
        for item in Walk(b: b).items(in: range) {
            switch item {
            case let .rule(prelude, block):
                let list = selectors(String(decoding: b[prelude], as: UTF8.self))
                guard !list.contains(where: { $0.isEmpty || !isSelector($0) }) else { continue }
                out += list.map { scoped(selector: $0, in: scope) }.joined(separator: ", ")
                out += " {" + withoutComments(String(decoding: b[block], as: UTF8.self)) + "}\n"
            case let .atRule(name, prelude, block):
                let words = withoutComments(String(decoding: b[prelude], as: UTF8.self))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let head = "@" + name + (words.isEmpty ? "" : " " + words)
                guard let block else {
                    if !["import", "charset", "namespace"].contains(name) { out += head + ";\n" }
                    continue
                }
                switch name {
                case "media", "supports", "layer", "container", "starting-style", "document", "-moz-document":
                    out += head + " {\n"
                    emit(b, block, scope: scope, into: &out)
                    out += "}\n"
                case _ where namesNoElement.contains(name):
                    out += head + " {" + withoutComments(String(decoding: b[block], as: UTF8.self)) + "}\n"
                default:
                    continue
                }
            }
        }
    }

    /// The at-rules with a block that name no element, kept as they are
    /// (`scoped`): fonts, animations, the printed page, properties,
    /// counters.
    static let namesNoElement: Set<String> = [
        "font-face", "keyframes", "-webkit-keyframes", "-moz-keyframes", "-o-keyframes", "page",
        "property", "counter-style", "font-feature-values", "font-palette-values",
    ]

    /// The class of the `div` that stands for a letter's root in its box
    /// (`scoped`), the box itself, which `:root` names.
    static let rootClass = "bm-own-root"
    /// The class of the `div` that stands for its body, the box's child.
    static let bodyClass = "bm-own-body"

    /// One selector made to apply inside `scope` (`scoped`).
    static func scoped(selector: String, in scope: String) -> String {
        let b = Array(selector.utf8)
        var i = 0
        var out = ""
        var joint = ""
        while i < b.count {
            var j = i
            while j < b.count, !isSpace(b[j]), b[j] != greater { j += 1 }
            if let root = root(b[i..<j]) {
                out += joint + (root.html ? "div" : "") + String(repeating: "." + rootClass, count: root.roots)
                    + ":where(\(scope))"
            } else if let rest = afterBody(b[i..<j]) {
                out += joint + "div:where(\(scope) > .\(bodyClass))" + String(decoding: rest, as: UTF8.self)
            } else {
                break
            }
            i = j
            while i < b.count, isSpace(b[i]) { i += 1 }
            joint = " "
            if i < b.count, b[i] == greater {
                joint = " > "
                i += 1
                while i < b.count, isSpace(b[i]) { i += 1 }
            }
        }
        guard !out.isEmpty else { return ":where(\(scope)) " + selector }
        return i == b.count ? out : out + joint + String(decoding: b[i...], as: UTF8.self)
    }

    /// What follows the type in a compound selector that names the body by
    /// it, `body` in any case: nothing, or its classes, attributes and
    /// pseudo-classes (`.x`, `[a]`, `:hover`, `#id`); nil for any other
    /// compound.
    static func afterBody(_ b: ArraySlice<UInt8>) -> ArraySlice<UInt8>? {
        guard startsLowered(b, at: b.startIndex, "body") else { return nil }
        let rest = b[(b.startIndex + 4)...]
        guard let c = rest.first else { return rest }
        return [UInt8(ascii: "."), UInt8(ascii: "#"), UInt8(ascii: "["), UInt8(ascii: ":")].contains(c) ? rest : nil
    }

    /// Whether `selector` can be one: no brace or semicolon in it outside
    /// a string, as a stray `}` before a rule leaves in its prelude.
    static func isSelector(_ selector: String) -> Bool {
        let b = Array(selector.utf8)
        var i = 0
        while i < b.count {
            let c = b[i]
            if c == backslash { i += 2; continue }
            if c == quote || c == apostrophe { i = Walk(b: b).stringEnd(at: i); continue }
            if c == openBrace || c == closeBrace || c == semicolon { return false }
            i += 1
        }
        return true
    }

    /// Whether a compound selector is the root alone: `html`, `:root`, or
    /// both, `html:root`, and nothing else.
    static func isRoot<S: StringProtocol>(_ compound: S) -> Bool {
        root(Array(compound.utf8)[...]) != nil
    }

    /// A compound selector that is the root alone, as its count of
    /// `:root` and whether it names `html`, in any case; nil for any other.
    static func root(_ b: ArraySlice<UInt8>) -> (roots: Int, html: Bool)? {
        var i = b.startIndex
        let html = startsLowered(b, at: i, "html")
        if html { i += 4 } else if b.isEmpty { return nil }
        var roots = 0
        while startsLowered(b, at: i, ":root") {
            i += 5
            roots += 1
        }
        return i == b.endIndex ? (roots, html) : nil
    }

    /// Whether `b` is `word`, a word in lower case, in any case.
    static func equalsLowered(_ b: ArraySlice<UInt8>, _ word: StaticString) -> Bool {
        b.count == word.utf8CodeUnitCount && startsLowered(b, at: b.startIndex, word)
    }

    /// Whether `b` has `word`, in lower case, at `i`, in any case.
    static func startsLowered(_ b: ArraySlice<UInt8>, at i: Int, _ word: StaticString) -> Bool {
        let n = word.utf8CodeUnitCount
        guard i + n <= b.endIndex else { return false }
        let w = word.utf8Start
        for k in 0..<n where lowered(b[i + k]) != w[k] { return false }
        return true
    }

    // MARK: - HTML's colours

    /// A colour attribute of HTML's, the body's `bgcolor` or `text`, as a
    /// CSS colour, read as WebKit reads a legacy colour value: nil for
    /// none, an empty one or `transparent`; a name, letters that are not
    /// all hex digits, in lower case, for CSS to read; `#rgb` doubled; any
    /// other, after a `#`, its first 128 characters, each that is not a hex
    /// digit a `0`, made three equal parts, each cut to its last eight, the
    /// zeros all three begin with dropped down to two, then cut to two
    /// (`fff` is `#0f0f0f`, `#ffffff;` is `#ffff00`, white space alone
    /// black), as `HTMLElement::parseLegacyColorValue` in WebKit's source
    /// reads it. Letters that name no colour are dropped by CSS, where
    /// WebKit would make a colour of them.
    static func legacyColour(_ value: String) -> String? {
        guard !value.isEmpty else { return nil }
        var u = Array(value.utf16)
        while let c = u.first, c < 0x80, isSpace(UInt8(c)) { u.removeFirst() }
        while let c = u.last, c < 0x80, isSpace(UInt8(c)) { u.removeLast() }
        let hex: (UInt16) -> Bool = { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x46) || ($0 >= 0x61 && $0 <= 0x66) }
        let letter: (UInt16) -> Bool = { ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) }
        // Only ever given an ASCII letter or digit.
        let low: (UInt16) -> UInt8 = { lowered(UInt8($0)) }
        if !u.isEmpty, u.allSatisfy(letter) {
            let name = String(decoding: u.map(low), as: UTF8.self)
            if name == "transparent" { return nil }
            if !u.allSatisfy(hex) { return name }
        }
        if u.count == 4, u[0] == 0x23, u.dropFirst().allSatisfy(hex) {
            return "#" + String(decoding: u.dropFirst().flatMap { [low($0), low($0)] }, as: UTF8.self)
        }
        var digits: [UInt8] = []
        var i = u.first == 0x23 ? 1 : 0
        while i < u.count, digits.count < 128 {
            digits.append(hex(u[i]) ? low(u[i]) : UInt8(ascii: "0"))
            i += 1
        }
        while digits.isEmpty || digits.count % 3 != 0 { digits.append(UInt8(ascii: "0")) }
        let third = digits.count / 3
        var parts = (0..<3).map { digits[($0 * third)..<(($0 + 1) * third)].suffix(8) }
        while parts[0].count > 2, parts.allSatisfy({ $0.first == UInt8(ascii: "0") }) {
            parts = parts.map { $0.dropFirst() }
        }
        return "#" + parts.map { part -> String in
            let n = String(Int(String(decoding: part.prefix(2), as: UTF8.self), radix: 16) ?? 0, radix: 16)
            return n.count == 1 ? "0" + n : n
        }.joined()
    }

    // MARK: - Pieces

    /// `css` with its comments taken out, each a space, outside strings.
    static func withoutComments(_ css: String) -> String {
        guard css.contains("/*") else { return css }
        let b = Array(css.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(b.count)
        var i = 0
        let walk = Walk(b: b)
        while i < b.count {
            let c = b[i]
            if c == backslash {
                out.append(contentsOf: b[i..<min(i + 2, b.count)])
                i += 2
                continue
            }
            if c == quote || c == apostrophe {
                let end = walk.stringEnd(at: i)
                out.append(contentsOf: b[i..<end])
                i = end
                continue
            }
            if c == slash, i + 1 < b.count, b[i + 1] == star {
                i = walk.commentEnd(at: i)
                out.append(space)
                continue
            }
            out.append(c)
            i += 1
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// The bytes as a string without CSS's white space at either end.
    private static func trimmed(_ bytes: ArraySlice<UInt8>) -> String {
        var start = bytes.startIndex
        var end = bytes.endIndex
        while start < end, isSpace(bytes[start]) { start += 1 }
        while end > start, isSpace(bytes[end - 1]) { end -= 1 }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    /// Whether `text` holds `word`, a word in lower case, in any case:
    /// what a sheet is looked through for before it is read.
    static func mentions(_ text: String, _ word: String) -> Bool {
        let needle = Array(word.utf8)
        guard let first = needle.first else { return true }
        var contiguous = text
        return contiguous.withUTF8 { b in
            guard b.count >= needle.count else { return false }
            for i in 0...(b.count - needle.count) where lowered(b[i]) == first {
                var k = 1
                while k < needle.count, lowered(b[i + k]) == needle[k] { k += 1 }
                if k == needle.count { return true }
            }
            return false
        }
    }

    private static func isNameByte(_ c: UInt8) -> Bool {
        (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x5F || c >= 0x80
    }

    /// What a sheet is made of, at one level: its rules and its at-rules,
    /// as the bytes' ranges, a block's without its braces.
    private enum Item {
        case rule(prelude: Range<Int>, block: Range<Int>)
        /// `name` in lower case, `prelude` after it; `block` nil for one
        /// ended by a semicolon.
        case atRule(name: String, prelude: Range<Int>, block: Range<Int>?)
    }

    /// One level of a sheet, read in a single pass.
    private struct Walk {
        let b: [UInt8]

        func items(in range: Range<Int>) -> [Item] {
            var out: [Item] = []
            var i = range.lowerBound
            let end = range.upperBound
            while i < end {
                let c = b[i]
                if isSpace(c) { i += 1; continue }
                if c == slash, i + 1 < end, b[i + 1] == star { i = min(commentEnd(at: i), end); continue }
                if starts("<!--", at: i, end: end) { i += 4; continue }
                if starts("-->", at: i, end: end) { i += 3; continue }
                if c == at {
                    var j = i + 1
                    while j < end, LetterCSS.isNameByte(lowered(b[j])) { j += 1 }
                    let name = String(decoding: b[(i + 1)..<j].map(lowered), as: UTF8.self)
                    let stop = preludeEnd(from: j, end: end, semicolon: true)
                    guard stop < end else {
                        out.append(.atRule(name: name, prelude: j..<end, block: nil))
                        return out
                    }
                    if b[stop] == semicolon {
                        out.append(.atRule(name: name, prelude: j..<stop, block: nil))
                        i = stop + 1
                    } else {
                        let close = blockEnd(from: stop + 1, end: end)
                        out.append(.atRule(name: name, prelude: j..<stop, block: (stop + 1)..<close))
                        i = close + 1
                    }
                    continue
                }
                let stop = preludeEnd(from: i, end: end, semicolon: false)
                guard stop < end else { return out }
                let close = blockEnd(from: stop + 1, end: end)
                out.append(.rule(prelude: i..<stop, block: (stop + 1)..<close))
                i = close + 1
            }
            return out
        }

        /// Where a prelude from `start` ends: its `{`, or, for an at-rule,
        /// a `;` first, outside brackets, parentheses, strings and
        /// comments; `end` for neither.
        func preludeEnd(from start: Int, end: Int, semicolon: Bool) -> Int {
            var depth = 0
            var i = start
            while i < end {
                let c = b[i]
                if c == backslash { i += 2; continue }
                if c == quote || c == apostrophe { i = stringEnd(at: i); continue }
                if c == slash, i + 1 < end, b[i + 1] == star { i = commentEnd(at: i); continue }
                if c == openParen || c == openBracket { depth += 1 }
                if (c == closeParen || c == closeBracket) && depth > 0 { depth -= 1 }
                if depth == 0 && (c == openBrace || (semicolon && c == UInt8(ascii: ";"))) { return i }
                i += 1
            }
            return end
        }

        /// The `}` that closes a block whose contents begin at `start`, or
        /// `end` for a block never closed, which CSS closes at the end.
        func blockEnd(from start: Int, end: Int) -> Int {
            var depth = 0
            var i = start
            while i < end {
                let c = b[i]
                if c == backslash { i += 2; continue }
                if c == quote || c == apostrophe { i = stringEnd(at: i); continue }
                if c == slash, i + 1 < end, b[i + 1] == star { i = commentEnd(at: i); continue }
                if c == openBrace { depth += 1 }
                if c == closeBrace {
                    if depth == 0 { return i }
                    depth -= 1
                }
                i += 1
            }
            return end
        }

        /// Just past a string opened at `i`: its closing quote, a line
        /// break, which ends a string CSS will not read, or the end.
        func stringEnd(at i: Int) -> Int {
            let q = b[i]
            var j = i + 1
            while j < b.count {
                if b[j] == backslash { j += 2; continue }
                if b[j] == q { return j + 1 }
                if b[j] == 0x0A || b[j] == 0x0C || b[j] == 0x0D { return j }
                j += 1
            }
            return b.count
        }

        /// Just past a comment opened at `i`, or the end.
        func commentEnd(at i: Int) -> Int {
            var j = i + 2
            while j + 1 < b.count {
                if b[j] == star, b[j + 1] == slash { return j + 2 }
                j += 1
            }
            return b.count
        }

        func starts(_ s: StaticString, at i: Int, end: Int) -> Bool {
            let n = s.utf8CodeUnitCount
            guard i + n <= end else { return false }
            return s.withUTF8Buffer { needle in
                (0..<n).allSatisfy { b[i + $0] == needle[$0] }
            }
        }
    }
}

private let backslash = UInt8(ascii: "\\")
private let quote = UInt8(ascii: "\"")
private let apostrophe = UInt8(ascii: "'")
private let openParen = UInt8(ascii: "(")
private let closeParen = UInt8(ascii: ")")
private let openBracket = UInt8(ascii: "[")
private let closeBracket = UInt8(ascii: "]")
private let openBrace = UInt8(ascii: "{")
private let closeBrace = UInt8(ascii: "}")
private let comma = UInt8(ascii: ",")
private let semicolon = UInt8(ascii: ";")
private let slash = UInt8(ascii: "/")
private let star = UInt8(ascii: "*")
private let at = UInt8(ascii: "@")
private let space = UInt8(ascii: " ")
private let greater = UInt8(ascii: ">")

private func lowered(_ c: UInt8) -> UInt8 {
    (c >= 0x41 && c <= 0x5A) ? c + 0x20 : c
}

private func isSpace(_ c: UInt8) -> Bool {
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D
}
