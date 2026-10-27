import Foundation

/// How the dark pane draws a letter's HTML, decided as Mail decides it in
/// Dark Mode (B-169).
///
/// Mail's rule, read in iOS 18.6's MobileMailUI (`_styleForSystemAppearance`
/// and `_declaredColorSchemes`, its script run as each letter's page
/// loads) and MessageUI (the style sheet that goes with it):
///
/// - A letter that declares its colour schemes is drawn as it declares
///   them, and Mail's colour filter is off. The declaration is the
///   `color-scheme` its root computes to, from the letter's own style,
///   `supported-color-schemes` being WebKit's old name for it; or, with
///   none but `normal`, the last `<meta name="color-scheme">` of the
///   letter, whose content is split at its spaces. Declaring `light` or
///   `only` without `dark`, it is drawn light only (`light`); otherwise in
///   its own colours, the dark among them, its rules for the dark applying
///   (`own`). Mail's script looks for a `<meta
///   name="supported-color-schemes">` only when the search for
///   `color-scheme` returns none, which `querySelectorAll` never does, so
///   such a meta alone declares nothing, as here.
/// - A letter that declares none is drawn light (`apple-mail-light-only`)
///   when it has a picture from the web, an `<img>` whose address begins
///   `http` and that is more than 1 px wide or tall, but for Apple's rich
///   link's (`lp-rich-link`), or when its body has a background picture.
/// - Any other is turned to the dark by Mail's colour filter
///   (`apple-mail-implicit-dark-support`, `apple-invert-lightness()`),
///   which the pane does with its invert (`inverted`, D-010).
///
/// Mail asks WebKit, once the page has loaded; this reads the letter's
/// markup (`Markup`) and its style sheets (`LetterCSS`), so a few things
/// are judged rather than measured: see each piece. Each letter on its
/// own, as Mail draws each letter of a conversation in a page of its own.
/// Pure and Foundation-only, run where the pane's pages are built, off the
/// main thread (`PanePage`), so the suite on Linux can test it.
enum LetterScheme: Equatable, Sendable {
    /// Inverted by the pane, as Mail's colour filter turns it: a letter
    /// that declares no scheme, with no picture from the web and no
    /// background picture on its body. Every HTML letter was drawn so
    /// until B-169.
    case inverted
    /// Drawn light, as its sender made it, on its own white, the pane dark
    /// around it: a letter with a picture from the web or a background
    /// picture, or one that declares a light scheme only.
    case light
    /// Drawn in its own colours on the pane's black, its rules for the
    /// dark with it: a letter that declares a scheme other than light only.
    case own

    /// The class its body has in a conversation's stack
    /// (`ConversationDocument`), for an HTML letter.
    var stackClass: String {
        switch self {
        case .inverted: return "bm-html"
        case .light: return "bm-light"
        case .own: return "bm-own"
        }
    }

    // MARK: - Mail's rule

    /// How the pane draws `html`, a letter's HTML as it came, wrapper and
    /// all, as Mail reads a letter's whole document.
    static func of(html: String) -> LetterScheme {
        var markup = Markup(html)
        markup.read()
        // Only a sheet that names a colour scheme or a background can
        // decide anything here; the rest are not read.
        let rules = markup.styles
            .filter { LetterCSS.mentions($0, "color-scheme") || LetterCSS.mentions($0, "background") }
            .flatMap(LetterCSS.rules(in:))
        if let declared = declared(markup, rules) {
            return (declared.contains("light") || declared.contains("only")) && !declared.contains("dark")
                ? .light : .own
        }
        if markup.pictures.contains(where: { isFromTheWeb($0, base: markup.base) })
            || hasBackgroundPicture(markup, rules) {
            return .light
        }
        return .inverted
    }

    /// The schemes the letter declares, as Mail's `_declaredColorSchemes`
    /// reads them; nil for none.
    ///
    /// First the `color-scheme` its root computes to: the declaration of
    /// it, or of `supported-color-schemes`, that wins at the root, from a
    /// rule whose selector is the root alone (`html`, `:root`) under media
    /// that match the pane, or from the `style` on its `<html>`, by
    /// `!important`, then the attribute over a sheet, then weight, then
    /// order. One CSS does not take, a value that cannot be the property's,
    /// is passed over, as CSS passes it over. `normal`, and the values
    /// `auto` and the keywords for all properties that come to it, declare
    /// nothing. Then the last `<meta name="color-scheme">`, the name as
    /// written, as Mail's selector matches it: its content in lower case,
    /// split at its spaces; none, or an empty content, declares nothing.
    static func declared(_ markup: Markup, _ rules: [LetterCSS.Rule]) -> [String]? {
        var best: (weight: Weight, value: [String])?
        func consider(_ declarations: [LetterCSS.Declaration], weight: (Bool) -> Weight) {
            for d in declarations where d.name == "color-scheme" || d.name == "supported-color-schemes" {
                guard let value = schemes(d.value) else { continue }
                let w = weight(d.important)
                if best.map({ w >= $0.weight }) ?? true { best = (w, value) }
            }
        }
        for (order, rule) in rules.enumerated() where rule.matchesPane {
            guard let weight = rule.selectors.compactMap(rootWeight).max(by: weighsLess) else { continue }
            consider(rule.declarations) { Weight(important: $0, inline: false, selector: weight, order: order) }
        }
        if let style = markup.htmlStyle {
            consider(LetterCSS.declarations(in: style)) {
                Weight(important: $0, inline: true, selector: [0, 0, 0], order: 0)
            }
        }
        if let value = best?.value, value != ["normal"], value != ["auto"] { return value }
        guard let content = markup.lastMeta, !content.isEmpty else { return nil }
        return content.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// A value of `color-scheme`, its words in lower case, `["normal"]` for
    /// one that comes to `normal`; nil for one that cannot be the
    /// property's: `normal`, or one or more names, none of them `normal`
    /// or a keyword for all properties, with `only` at most once, first or
    /// last, beside another. A value that asks a variable is nil too: what
    /// it comes to is not known here.
    static func schemes(_ value: String) -> [String]? {
        let words = value.utf8.split(whereSeparator: isSpace)
            .map { String(decoding: $0.map { ($0 >= 0x41 && $0 <= 0x5A) ? $0 + 0x20 : $0 }, as: UTF8.self) }
        guard !words.isEmpty, !value.contains("(") else { return nil }
        if words == ["normal"] || (words.count == 1 && everyProperty.contains(words[0])) { return ["normal"] }
        guard words.allSatisfy(isName),
              !words.contains(where: { $0 == "normal" || $0 == "default" || everyProperty.contains($0) }),
              words.filter({ $0 == "only" }).count <= 1,
              words.count > (words.contains("only") ? 1 : 0),
              !words.dropFirst().dropLast().contains("only") else { return nil }
        return words
    }

    /// CSS's keywords for every property.
    private static let everyProperty: Set<String> = ["inherit", "initial", "unset", "revert", "revert-layer"]

    /// Whether a picture of the letter is one Mail counts: its address
    /// begins `http` once WebKit has made it whole, against the letter's
    /// `<base>` when it has none of its own, and it is more than 1 px wide
    /// or tall, but for Apple's rich link's.
    ///
    /// Mail measures it as drawn, once the page has loaded. Here it is
    /// measured by the width and height its `style` gives it in px, or its
    /// attributes give it: one of them more than 1 counts it; given and
    /// none more than 1, a tracking pixel's, it is not counted; given
    /// neither, it is, as a picture from the web is all but always larger.
    /// A picture whose own size is 1 px with neither written is counted
    /// here and not by Mail. A percentage, or a size in other units, is
    /// taken for more than 1 px.
    static func isFromTheWeb(_ p: Markup.Picture, base: String?) -> Bool {
        guard !(p.className ?? "").contains("lp-rich-link"),
              let src = p.src.map(urlTrimmed), !src.isEmpty else { return false }
        if let scheme = scheme(of: src) {
            guard scheme.hasPrefix("http") else { return false }
        } else {
            guard let base = base.map(urlTrimmed), scheme(of: base)?.hasPrefix("http") == true else {
                return false
            }
        }
        let style = LetterCSS.declarations(in: p.style ?? "")
        let width = pixels(css: style.last(where: { $0.name == "width" })?.value) ?? pixels(attribute: p.width)
        let height = pixels(css: style.last(where: { $0.name == "height" })?.value) ?? pixels(attribute: p.height)
        if width == nil && height == nil { return true }
        return (width ?? 0) > 1 || (height ?? 0) > 1
    }

    /// Whether the letter's body has a background picture, as Mail asks
    /// WebKit of it: any picture, from the web or the letter's own, or a
    /// gradient. Its `background` attribute, the `background-image` or
    /// `background` that wins from a rule whose selector ends at the body
    /// with the root alone before it (`body`, `html body`, `:root > body`)
    /// under media that match the pane, or from its `style`; a
    /// `background` with no picture in it, a colour alone, takes the
    /// picture away. The attribute weighs least, then the sheets, then
    /// the `style`, and `!important` over all. A rule naming the body by a
    /// class, or `*`, is not read.
    static func hasBackgroundPicture(_ markup: Markup, _ rules: [LetterCSS.Rule]) -> Bool {
        var best: (weight: Weight, picture: Bool)?
        if let attribute = markup.bodyBackground?.trimmingCharacters(in: htmlSpaces), !attribute.isEmpty {
            best = (Weight(important: false, inline: false, selector: [-1, -1, -1], order: -1), true)
        }
        func consider(_ declarations: [LetterCSS.Declaration], weight: (Bool) -> Weight) {
            for d in declarations where d.name == "background-image" || d.name == "background" {
                guard !d.value.lowercased().contains("var(") else { continue }
                let w = weight(d.important)
                if best.map({ w >= $0.weight }) ?? true { best = (w, isPicture(d.value)) }
            }
        }
        for (order, rule) in rules.enumerated() where rule.matchesPane {
            guard let weight = rule.selectors.compactMap(bodyWeight).max(by: weighsLess) else { continue }
            consider(rule.declarations) { Weight(important: $0, inline: false, selector: weight, order: order) }
        }
        if let style = markup.bodyStyle {
            consider(LetterCSS.declarations(in: style)) {
                Weight(important: $0, inline: true, selector: [0, 0, 0], order: 0)
            }
        }
        return best?.picture ?? false
    }

    // MARK: - A letter in its own colours

    /// The style sheets in the letter's head, which `DocumentWrapper`
    /// takes off with it, in their order: each `<style>`'s text, none in a
    /// comment.
    static func headStyles(of html: String) -> [String] {
        DocumentWrapper.heads(in: html).flatMap { head -> [String] in
            var markup = Markup(head)
            markup.read()
            return markup.styles
        }
    }

    // MARK: - Pieces

    /// What a declaration weighs in the cascade, the larger winning:
    /// `!important`, then an element's own `style` over a sheet, then the
    /// selector's weight (ids, classes, types), then the later.
    struct Weight: Comparable {
        let important: Bool
        let inline: Bool
        let selector: [Int]
        let order: Int

        static func < (a: Weight, b: Weight) -> Bool {
            if a.important != b.important { return !a.important }
            if a.inline != b.inline { return !a.inline }
            if a.selector != b.selector { return a.selector.lexicographicallyPrecedes(b.selector) }
            return a.order < b.order
        }
    }

    /// Whether a selector's weight is less than another's, ids first.
    static func weighsLess(_ a: [Int], _ b: [Int]) -> Bool {
        a.lexicographicallyPrecedes(b)
    }

    /// The weight of a selector that is the root alone (`LetterCSS.root`),
    /// a class's for each `:root`, a type's for `html`; nil for any other.
    static func rootWeight(_ selector: String) -> [Int]? {
        LetterCSS.root(Array(selector.utf8)[...]).map { [0, $0.roots, $0.html ? 1 : 0] }
    }

    /// The weight of a selector that ends at the body with the root alone
    /// before it, by a space or `>`; nil for any other.
    static func bodyWeight(_ selector: String) -> [Int]? {
        let b = Array(selector.utf8)
        var compounds: [ArraySlice<UInt8>] = []
        var start = 0
        for i in 0...b.count where i == b.count || b[i] == UInt8(ascii: ">") || isSpace(b[i]) {
            if i > start { compounds.append(b[start..<i]) }
            start = i + 1
        }
        guard let last = compounds.last, LetterCSS.equalsLowered(last, "body") else { return nil }
        var weight = [0, 0, 1]
        for compound in compounds.dropLast() {
            guard let root = LetterCSS.root(compound) else { return nil }
            weight[1] += root.roots
            weight[2] += root.html ? 1 : 0
        }
        return weight
    }

    /// Whether a value of `background` or `background-image` holds a
    /// picture or a gradient.
    static func isPicture(_ value: String) -> Bool {
        let v = value.lowercased()
        return ["url(", "gradient(", "image(", "image-set(", "cross-fade(", "element(", "paint("]
            .contains(where: v.contains)
    }

    /// An address with what WebKit takes off it taken off: ASCII controls
    /// and spaces at either end, tabs and line breaks anywhere.
    static func urlTrimmed(_ address: String) -> String {
        var b = Array(address.utf8).filter { $0 != 0x09 && $0 != 0x0A && $0 != 0x0D }
        while let last = b.last, last <= 0x20 { b.removeLast() }
        let start = b.firstIndex(where: { $0 > 0x20 }) ?? b.count
        return String(decoding: b[start...], as: UTF8.self)
    }

    /// An address's scheme, in lower case: a letter, then letters, digits,
    /// `+`, `-` or `.`, to a colon; nil for an address with none, which is
    /// made whole against the page's base.
    static func scheme(of address: String) -> String? {
        var scheme: [UInt8] = []
        for c in address.utf8 {
            if c == UInt8(ascii: ":") { return scheme.isEmpty ? nil : String(decoding: scheme, as: UTF8.self) }
            let letter = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
            let other = (c >= 0x30 && c <= 0x39) || c == UInt8(ascii: "+") || c == UInt8(ascii: "-")
                || c == UInt8(ascii: ".")
            guard letter || (!scheme.isEmpty && other) else { return nil }
            scheme.append((c >= 0x41 && c <= 0x5A) ? c + 0x20 : c)
        }
        return nil
    }

    /// A width or height attribute as HTML reads one: a number at its
    /// start after spaces; a percentage taken for more than 1 px; nil for
    /// none.
    static func pixels(attribute: String?) -> Double? {
        guard let attribute else { return nil }
        let b = Array(attribute.utf8)
        var i = 0
        while i < b.count, isSpace(b[i]) { i += 1 }
        let (n, end) = number(b, from: i)
        guard let n else { return nil }
        return end < b.count && b[end] == UInt8(ascii: "%") ? max(n, 100) : n
    }

    /// A width or height in a `style`: a number in px, or with no unit; 0
    /// in any unit; any other unit taken for more than 1 px; nil for none,
    /// `auto` among them.
    static func pixels(css value: String?) -> Double? {
        guard let value else { return nil }
        let b = Array(value.utf8)
        var i = 0
        while i < b.count, isSpace(b[i]) { i += 1 }
        let (n, end) = number(b, from: i)
        guard let n else { return nil }
        var unitEnd = b.count
        while unitEnd > end, isSpace(b[unitEnd - 1]) { unitEnd -= 1 }
        let unit = b[end..<unitEnd]
        if n == 0 || unit.isEmpty || LetterCSS.equalsLowered(unit, "px") { return n }
        return 100
    }

    /// The digits and point at `start`, as a number, and where they end.
    private static func number(_ b: [UInt8], from start: Int) -> (Double?, Int) {
        var end = start
        while end < b.count, (b[end] >= 0x30 && b[end] <= 0x39) || b[end] == UInt8(ascii: ".") { end += 1 }
        return (Double(String(decoding: b[start..<end], as: UTF8.self)), end)
    }

    private static func isName(_ word: String) -> Bool {
        word.utf8.allSatisfy { ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D || $0 == 0x5F
            || $0 >= 0x80 }
            && !(word.utf8.first.map { $0 >= 0x30 && $0 <= 0x39 } ?? true)
    }

    /// HTML's spaces: tab, line feed, form feed, carriage return, space.
    static let htmlSpaces = CharacterSet(charactersIn: "\t\n\u{0C}\r ")

    // MARK: - The markup

    /// What Mail's rule reads of a letter's markup, read as HTML's
    /// tokenizer reads it, as far as that goes, in one pass: tags,
    /// attributes quoted or not, character references in the values;
    /// nothing in a comment; the text of `<style>`, `<script>`, `<title>`,
    /// `<textarea>` and the like read as text to their end tag, the text of
    /// `<style>` kept. A tag never closed ends the reading, as it ends
    /// HTML's.
    struct Markup {
        /// One `<img>`, or `<image>`, which HTML reads as one.
        struct Picture: Equatable {
            var src: String?
            var width: String?
            var height: String?
            var style: String?
            var className: String?
        }

        private let b: [UInt8]
        /// Each `<style>`'s text, in order.
        private(set) var styles: [String] = []
        /// The `style` of `<html>`; a later `<html>`'s where the first had
        /// none, as HTML adds a later tag's attributes the first lacks.
        private(set) var htmlStyle: String?
        /// The body's `background` and `style`, the same way.
        private(set) var bodyBackground: String?
        private(set) var bodyStyle: String?
        /// The content of the last `<meta name="color-scheme">`, nil when
        /// it has none or there is no such meta.
        private(set) var lastMeta: String?
        /// The `href` of the first `<base>` with one.
        private(set) var base: String?
        private(set) var pictures: [Picture] = []

        init(_ html: String) {
            b = Array(html.utf8)
        }

        /// Text read as text to its element's end tag.
        private static let rawText: Set<String> = [
            "style", "script", "title", "textarea", "xmp", "iframe", "noembed", "noframes",
        ]

        mutating func read() {
            var i = 0
            let n = b.count
            var htmlSeen: Set<String> = []
            var bodySeen: Set<String> = []
            while i < n {
                guard b[i] == lt, i + 1 < n else { i += 1; continue }
                let next = b[i + 1]
                if next == bang {
                    if starts("<!--", at: i) {
                        guard let end = commentEnd(from: i + 4) else { return }
                        i = end
                    } else {
                        guard let end = index(of: gt, from: i + 2) else { return }
                        i = end + 1
                    }
                    continue
                }
                if next == question {
                    guard let end = index(of: gt, from: i + 2) else { return }
                    i = end + 1
                    continue
                }
                if next == slash {
                    guard i + 2 < n, isLetter(b[i + 2]) else { i += 1; continue }
                    guard let end = tagEnd(from: i + 2) else { return }
                    i = end + 1
                    continue
                }
                guard isLetter(next) else { i += 1; continue }
                guard let tag = startTag(at: i) else { return }
                i = tag.end
                switch tag.name {
                case "html":
                    if !htmlSeen.contains("style"), let s = tag.attributes["style"] { htmlStyle = s }
                    htmlSeen.formUnion(tag.attributes.keys)
                case "body":
                    if !bodySeen.contains("style"), let s = tag.attributes["style"] { bodyStyle = s }
                    if !bodySeen.contains("background"), let s = tag.attributes["background"] {
                        bodyBackground = s
                    }
                    bodySeen.formUnion(tag.attributes.keys)
                case "meta":
                    if tag.attributes["name"] == "color-scheme" { lastMeta = tag.attributes["content"] }
                case "base":
                    if base == nil, let href = tag.attributes["href"] { base = href }
                case "img", "image":
                    pictures.append(Picture(src: tag.attributes["src"], width: tag.attributes["width"],
                                            height: tag.attributes["height"], style: tag.attributes["style"],
                                            className: tag.attributes["class"]))
                case "plaintext":
                    return
                default:
                    break
                }
                guard Self.rawText.contains(tag.name) else { continue }
                let close = rawTextEnd(of: tag.name, from: i)
                if tag.name == "style" {
                    styles.append(String(decoding: b[i..<(close ?? n)], as: UTF8.self))
                }
                guard let close, let end = tagEnd(from: close + 2) else { return }
                i = end + 1
            }
        }

        /// A start tag at `i`: its name in lower case, its attributes, the
        /// first of a name kept, their values with character references
        /// read, and where it ends, just past its `>`; nil for one never
        /// closed.
        private func startTag(at i: Int) -> (name: String, attributes: [String: String], end: Int)? {
            let n = b.count
            var j = i + 1
            let nameStart = j
            while j < n, !isSpace(b[j]), b[j] != slash, b[j] != gt { j += 1 }
            let name = lowercased(nameStart..<j)
            var attributes: [String: String] = [:]
            while true {
                while j < n, isSpace(b[j]) || b[j] == slash { j += 1 }
                guard j < n else { return nil }
                if b[j] == gt { return (name, attributes, j + 1) }
                let attributeStart = j
                j += 1
                while j < n, !isSpace(b[j]), b[j] != slash, b[j] != gt, b[j] != equals { j += 1 }
                let attribute = lowercased(attributeStart..<j)
                while j < n, isSpace(b[j]) { j += 1 }
                var value: Range<Int> = j..<j
                if j < n, b[j] == equals {
                    j += 1
                    while j < n, isSpace(b[j]) { j += 1 }
                    if j < n, b[j] == quote || b[j] == apostrophe {
                        guard let close = index(of: b[j], from: j + 1) else { return nil }
                        value = (j + 1)..<close
                        j = close + 1
                    } else {
                        let start = j
                        while j < n, !isSpace(b[j]), b[j] != gt { j += 1 }
                        value = start..<j
                    }
                }
                if attributes[attribute] == nil {
                    let text = String(decoding: b[value], as: UTF8.self)
                    attributes[attribute] = text.contains("&") ? HTMLText.decodingEntities(text) : text
                }
            }
        }

        /// The `<` of the end tag that ends raw text begun at `start`: `</`,
        /// the name in any case, then a space, `/` or `>`; nil for none.
        private func rawTextEnd(of name: String, from start: Int) -> Int? {
            let needle = Array(name.utf8)
            var j = start
            while let at = index(of: lt, from: j) {
                let after = at + 2 + needle.count
                if at + 1 < b.count, b[at + 1] == slash, after <= b.count,
                   (0..<needle.count).allSatisfy({ lowered(b[at + 2 + $0]) == needle[$0] }),
                   after == b.count || isSpace(b[after]) || b[after] == slash || b[after] == gt {
                    return at
                }
                j = at + 1
            }
            return nil
        }

        /// The `>` that ends a tag whose name begins at `start`, past any
        /// quoted value; nil for none.
        private func tagEnd(from start: Int) -> Int? {
            var j = start
            var inside: UInt8?
            while j < b.count {
                let c = b[j]
                if let q = inside {
                    if c == q { inside = nil }
                } else if c == gt {
                    return j
                } else if (c == quote || c == apostrophe), j > 0, b[j - 1] == equals || isSpace(b[j - 1]) {
                    inside = c
                }
                j += 1
            }
            return nil
        }

        /// Just past a comment whose text begins at `start`: `<!-->` and
        /// `<!--->` are comments of nothing; others end at `-->` or `--!>`.
        private func commentEnd(from start: Int) -> Int? {
            let n = b.count
            if start < n, b[start] == gt { return start + 1 }
            if start + 1 < n, b[start] == dash, b[start + 1] == gt { return start + 2 }
            var j = start
            while j + 2 < n {
                if b[j] == dash, b[j + 1] == dash {
                    if b[j + 2] == gt { return j + 3 }
                    if b[j + 2] == bang, j + 3 < n, b[j + 3] == gt { return j + 4 }
                }
                j += 1
            }
            return nil
        }

        private func index(of byte: UInt8, from start: Int) -> Int? {
            var j = start
            while j < b.count {
                if b[j] == byte { return j }
                j += 1
            }
            return nil
        }

        private func starts(_ s: StaticString, at i: Int) -> Bool {
            let n = s.utf8CodeUnitCount
            guard i + n <= b.count else { return false }
            return s.withUTF8Buffer { needle in (0..<n).allSatisfy { b[i + $0] == needle[$0] } }
        }

        private func lowercased(_ range: Range<Int>) -> String {
            String(decoding: b[range].map(lowered), as: UTF8.self)
        }
    }
}

private let lt = UInt8(ascii: "<")
private let gt = UInt8(ascii: ">")
private let bang = UInt8(ascii: "!")
private let question = UInt8(ascii: "?")
private let slash = UInt8(ascii: "/")
private let equals = UInt8(ascii: "=")
private let quote = UInt8(ascii: "\"")
private let apostrophe = UInt8(ascii: "'")
private let dash = UInt8(ascii: "-")

private func lowered(_ c: UInt8) -> UInt8 {
    (c >= 0x41 && c <= 0x5A) ? c + 0x20 : c
}

private func isLetter(_ c: UInt8) -> Bool {
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
}

private func isSpace(_ c: UInt8) -> Bool {
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D
}
