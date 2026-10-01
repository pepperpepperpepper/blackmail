import Foundation

/// Somebody else's letter, made fit to go out inside one of his.
///
/// A reply or a forward carries the original's own markup inside Mail's
/// quote (`AppleMailHTML`), so that it arrives looking like the letter it
/// answers: its pictures, its links, its tables. That markup is whatever a
/// stranger sent, and it is about to leave under his name, so it passes
/// through here first.
///
/// **Kept:** text, links, pictures, tables, and the `style` written on any
/// element. **Dropped:** scripts, event handlers, forms, frames, embedded
/// objects, `<style>` and `<link>` sheets, `<meta>`, `<base>`, comments, and
/// any address whose scheme mail has no use for. A `<style>` block is not a
/// script, but it applies to the whole letter rather than to the part it
/// came in: a newsletter's `body { background: #000 }` or `p { font-size:
/// 9px }` would restyle his own words and his signature above the quote.
/// Senders who want their styling seen in Gmail already write it inline,
/// because Gmail drops `<style>` blocks too.
///
/// Not a parser. One pass over the bytes rebuilds every tag it keeps from
/// the attributes it read, so nothing reaches the output that was not
/// looked at: text between tags is copied as it came, less any `<` that
/// does not open a tag; an element not on the list below loses its tag and
/// keeps its content. What it cannot finish reading, such as a comment or a
/// tag cut off by a truncated fetch, ends the markup there. The sender's
/// document wrapper goes in the same pass, the doctype, `<html>`, `<head>`
/// with all it holds and `<body>`, which is what `DocumentWrapper` takes
/// off for the reading pane; its regular expressions cost more than the
/// whole pass.
///
/// Bytes throughout, attribute values included: every character that
/// matters to the syntax is ASCII, and in UTF-8 no byte of a multi-byte
/// character is, so the pass cannot split one. A megabyte newsletter takes
/// about 30 ms on this host in a release build. Checking each attribute
/// with Foundation's string calls took 0.4 s.
enum QuotedMarkup {

    /// `html` without its document wrapper and made safe, with every `cid:`
    /// it shows renamed by `pictures`.
    ///
    /// `pictures` maps a Content-ID as the original's markup writes it to
    /// the one the picture travels under in this letter. A picture shown by
    /// an id that is not in it is left out, `<img>` and all: its part is not
    /// coming, and the id could otherwise be one this letter uses for
    /// something else, such as the signature's logo.
    ///
    /// `shown` is which of the new ids the markup still shows, so the caller
    /// sends those pictures and no others: a part that nothing shows is a
    /// stray file to most readers.
    static func made(_ html: String,
                     pictures: [String: String] = [:]) -> (html: String, shown: Set<String>) {
        var pass = Pass(Array(html.utf8), pictures: pictures)
        let out = pass.run()
        return (out, pass.shown)
    }

    static func safe(_ html: String, pictures: [String: String] = [:]) -> String {
        made(html, pictures: pictures).html
    }

    /// Whether markup `made` returned shows anything: a character outside
    /// its tags that is not a space, or a picture.
    ///
    /// Read off `made`'s own output, in which every `<` opens a tag it wrote.
    static func showsAnything(_ html: String) -> Bool {
        let b = Array(html.utf8)
        let picture = Array("<img".utf8)
        var k = 0
        while k < b.count {
            if b[k] == lt {
                let after = k + picture.count
                if matches(picture, in: b, at: k, caseInsensitive: false), after < b.count,
                   b[after] == space || b[after] == gt {
                    return true
                }
                while k < b.count, b[k] != gt { k += 1 }
            } else if b[k] > 0x20 {
                return true
            }
            k += 1
        }
        return false
    }

    /// The Content-IDs `html` refers to by `cid:`, as it writes them.
    ///
    /// A plain scan, generous on purpose: it is used to pick the parts that
    /// might be pictures, and `made` decides which of those really are.
    static func contentIDs(shownBy html: String) -> Set<String> {
        let bytes = Array(html.utf8)
        var ids = Set<String>()
        var i = 0
        while let at = find(Array("cid:".utf8), in: bytes, from: i, caseInsensitive: true) {
            var j = at + 4
            while j < bytes.count, !Self.endsReference(bytes[j]) { j += 1 }
            if j > at + 4 { ids.insert(String(decoding: bytes[(at + 4)..<j], as: UTF8.self)) }
            i = j
        }
        return ids
    }

    private static func endsReference(_ b: UInt8) -> Bool {
        switch b {
        case 0x22, 0x27, 0x28, 0x29, 0x3B, 0x3C, 0x3E, 0x26: return true   // " ' ( ) ; < > &
        default: return b <= 0x20
        }
    }

    // MARK: - A plain line with its addresses made into links

    /// One line of plain text as HTML, with every web address in it a link.
    ///
    /// For a quote that is plain text, either because the original was or
    /// because he changed it and the original's markup no longer says what
    /// he left. About a third of the links in his own mail travel as bare
    /// text, and the whole point of quoting a link is that it can be followed.
    /// `http://`, `https://` and `www.` only: those are what a reader
    /// recognises as an address, and a plain `name.com` inside a sentence is
    /// more often a name than a link.
    ///
    /// One pass over the line, each character looked at a bounded number of
    /// times. It used to search the rest of the line afresh for each kind of
    /// address after every one it found, and a kind the line did not hold
    /// was searched for to its end every time: 12 s, in a release build, for
    /// a 200 kB line with an address every hundred bytes, on the actor that
    /// Send and Save Draft wait on.
    static func linked(_ line: String) -> String {
        guard line.range(of: "http", options: .caseInsensitive) != nil
                || line.range(of: "www.", options: .caseInsensitive) != nil else {
            return escaped(line)
        }
        let s = Array(line.unicodeScalars)
        var out = ""
        var written = 0
        var k = 0
        while k < s.count {
            guard let prefix = addressPrefix(in: s, at: k) else { k += 1; continue }
            guard startsWord(s, at: k) else { k += prefix; continue }
            let end = addressEnd(in: s, from: k, after: prefix)
            // "http://" and nothing after it is not an address.
            guard end > k + prefix else { k += prefix; continue }
            out += escaped(text(s[written..<k]))
            let address = text(s[k..<end])
            let href = address.lowercased().hasPrefix("www.") ? "http://" + address : address
            out += "<a href=\"" + attributeEscaped(href) + "\">" + escaped(address) + "</a>"
            written = end
            k = end
        }
        return out + escaped(text(s[written...]))
    }

    private static let addressPrefixes = ["https://", "http://", "www."].map { Array($0.utf8) }

    /// The length of the address prefix at `k`, in any case, or nil.
    private static func addressPrefix(in s: [Unicode.Scalar], at k: Int) -> Int? {
        search: for prefix in addressPrefixes where k + prefix.count <= s.count {
            for (n, c) in prefix.enumerated() {
                let v = s[k + n].value
                guard v < 0x80, lowered(UInt8(v)) == c else { continue search }
            }
            return prefix.count
        }
        return nil
    }

    /// Whether an address at `k` starts a word, so "catchwww.example" is
    /// left alone, and so is the "www." inside "jane@www.example.com".
    private static func startsWord(_ s: [Unicode.Scalar], at k: Int) -> Bool {
        var p = k - 1
        // An accent written after its letter belongs to the letter.
        while p >= 0, s[p].properties.isGraphemeExtend { p -= 1 }
        guard p >= 0 else { return true }
        let c = s[p]
        return !(c.properties.isAlphabetic || c.properties.numericType != nil
                 || c == "/" || c == "." || c == "@")
    }

    /// Where the address starting at `begin` ends.
    ///
    /// It runs to the next space or angle bracket, then gives back what a
    /// sentence puts after an address: a full stop, a comma, a closing
    /// quote, and a closing bracket that has no opening one inside it. That
    /// last is what keeps `https://en.wikipedia.org/wiki/Mercury_(planet)`
    /// whole, brackets and all, which is the shape of a good share of the
    /// links he sends. The brackets are counted once, on the way out, and
    /// taken off the counts as they are given back.
    private static func addressEnd(in s: [Unicode.Scalar], from begin: Int,
                                   after prefix: Int) -> Int {
        var end = begin
        var round = (open: 0, close: 0), square = (open: 0, close: 0)
        while end < s.count {
            let c = s[end]
            if c.properties.isWhitespace || c == "<" || c == ">" || c == "\"" { break }
            switch c {
            case "(": round.open += 1
            case ")": round.close += 1
            case "[": square.open += 1
            case "]": square.close += 1
            default: break
            }
            end += 1
        }
        while end > begin + prefix {
            let last = s[end - 1]
            if ".,;:!?'".unicodeScalars.contains(last) {
                end -= 1
            } else if last == ")", round.open < round.close {
                round.close -= 1
                end -= 1
            } else if last == "]", square.open < square.close {
                square.close -= 1
                end -= 1
            } else {
                break
            }
        }
        return end
    }

    private static func text(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        String(String.UnicodeScalarView(scalars))
    }

    /// Text as HTML: the three markup characters, `&` first so the others'
    /// ampersands are not escaped twice.
    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Text as the value of a double-quoted attribute.
    static func attributeEscaped(_ text: String) -> String {
        escaped(text).replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - What is kept

    /// Elements whose tags go through. Text, layout, tables, lists, links
    /// and pictures: what a letter is made of. Everything else loses its tag
    /// and keeps what is inside it, unless it is below.
    private static let keptElements: Set<String> = [
        "a", "abbr", "acronym", "address", "area", "article", "aside", "b", "bdi",
        "bdo", "big", "blockquote", "br", "caption", "center", "cite", "code", "col",
        "colgroup", "dd", "del", "details", "dfn", "dir", "div", "dl", "dt", "em",
        "fieldset", "figcaption", "figure", "font", "footer", "h1", "h2", "h3", "h4",
        "h5", "h6", "header", "hgroup", "hr", "i", "img", "ins", "kbd", "label",
        "legend", "li", "main", "map", "mark", "menu", "nav", "nobr", "ol", "p",
        "picture", "pre", "q", "rp", "rt", "ruby", "s", "samp", "section", "small",
        "source", "span", "strike", "strong", "sub", "summary", "sup", "table",
        "tbody", "td", "tfoot", "th", "thead", "time", "tr", "tt", "u", "ul", "var",
        "wbr",
    ]

    /// Elements that go with everything inside them.
    ///
    /// Scripts and the other executable containers, obviously. Also the
    /// ones whose content is not prose: a `<style>` sheet, a `<title>`, the
    /// options of a `<select>`, a `<head>` inside a letter that quotes a
    /// whole document of its own. And `svg` and `math`, whose content
    /// follows other parsing rules altogether and can carry its own scripts.
    private static let droppedWhole: Set<String> = [
        "script", "style", "template", "iframe", "noscript", "noembed", "noframes",
        "textarea", "title", "xmp", "plaintext", "head", "object", "applet", "svg",
        "math", "select", "datalist", "frameset", "canvas",
    ]

    /// Of those, the ones whose content is text to the browser rather than
    /// markup: they end at their own closing tag and nothing else.
    private static let rawText: Set<String> = [
        "script", "style", "iframe", "noscript", "noembed", "noframes", "textarea",
        "title", "xmp",
    ]

    /// What a browser keeps inside a `<head>`. Anything else, text included,
    /// ends a head its sender never closed.
    private static let headContent: Set<String> = [
        "base", "basefont", "bgsound", "link", "meta", "title", "style", "script", "noscript",
        "noframes", "template", "head", "html",
    ]

    /// Elements with no content and no closing tag.
    private static let voidElements: Set<String> = [
        "area", "base", "basefont", "bgsound", "br", "col", "embed", "frame", "hr",
        "img", "input", "keygen", "link", "meta", "param", "source", "track", "wbr",
    ]

    /// Elements a browser closes by itself, and which are therefore not
    /// closed at the end: an extra `</p>` where the browser has already
    /// closed one is read as an empty paragraph, a blank line in the quote.
    private static let closeThemselves: Set<String> = [
        "p", "li", "dt", "dd", "tr", "td", "th", "tbody", "thead", "tfoot",
        "colgroup", "rt", "rp",
    ]

    /// Elements whose start closes an open paragraph, as a browser does.
    private static let closesParagraph: Set<String> = [
        "address", "article", "aside", "blockquote", "center", "details", "dir",
        "div", "dl", "fieldset", "figcaption", "figure", "footer", "h1", "h2", "h3",
        "h4", "h5", "h6", "header", "hgroup", "hr", "main", "menu", "nav", "ol", "p",
        "pre", "section", "summary", "table", "ul",
    ]

    /// Attributes that hold an address, checked as one.
    private static let addressAttributes: Set<String> = [
        "href", "src", "background", "poster", "cite", "longdesc", "lowsrc", "dynsrc",
        "action", "codebase",
    ]

    /// Attributes that act rather than describe. Event handlers go by their
    /// `on` prefix; these are the rest.
    private static let droppedAttributes: Set<String> = [
        "srcdoc", "formaction", "action", "ping", "http-equiv",
    ]

    // MARK: - The pass

    /// The elements the markup has opened and not closed, innermost last,
    /// with how many of each name are among them.
    ///
    /// Bounded, and counted, because a closing tag is looked for among
    /// them. Unbounded and searched, `<div>` written a hundred thousand times
    /// and then `</x>` as often read the whole list for every `</x>`: 180 KB
    /// took 4.9 s, a megabyte would have taken minutes, on the actor that
    /// Send and Save Draft wait on, and again at every launch for a letter
    /// waiting in the Outbox. Now a name that is not open is refused at
    /// once, and one that is is looked for among at most `limit`.
    struct OpenElements {
        /// How deep the kept markup nests. An element opened inside `limit`
        /// others loses its tag and keeps what is inside it. WebKit builds
        /// no deeper than 512 either: past it, a page's elements go in
        /// beside one another rather than inside.
        static let limit = 512

        private(set) var names: [String] = []
        private var counts: [String: Int] = [:]

        var last: String? { names.last }
        var isFull: Bool { names.count >= Self.limit }

        mutating func push(_ name: String) {
            names.append(name)
            counts[name, default: 0] += 1
        }

        mutating func removeLast() {
            forget(names.removeLast())
        }

        /// Closes the innermost `name` and everything opened inside it;
        /// false, and nothing closed, when no `name` is open.
        mutating func close(_ name: String) -> Bool {
            guard counts[name, default: 0] > 0, let at = names.lastIndex(of: name) else {
                return false
            }
            for closed in names[at...] { forget(closed) }
            names.removeSubrange(at...)
            return true
        }

        private mutating func forget(_ name: String) {
            let left = counts[name, default: 1] - 1
            counts[name] = left > 0 ? left : nil
        }
    }

    private struct Pass {
        let b: [UInt8]
        let pictures: [String: String]
        var i = 0
        var out: [UInt8] = []
        /// The elements this markup has opened and not closed. A closing tag
        /// is let through only when it closes one of them, so nothing in the
        /// original can close Mail's quote around it early and leave the rest
        /// of the original below the bar, as if he had written it.
        var open = OpenElements()
        var shown = Set<String>()
        /// One tag as it is written out, kept until it is known to stay.
        var tag: [UInt8] = []
        /// Set once a `<head>` has been read to the end of the markup without
        /// closing. Every later one is then ended where a browser ends a
        /// head it was never told the end of (`skipUnclosedHead`), without
        /// reading to the end again. A letter of `<head>x` repeated read to
        /// the end once per head, and so in time that grew with the square
        /// of its size. A browser has one head and ignores any other.
        var headsNeverClose = false
        /// `pictures` by their ids in one case (`QuotedMarkup.folded`), for
        /// a reference written in another case than its Content-ID. Made
        /// the first time one is not found as it is written, and only then.
        var picturesInOneCase: [String: String]?

        init(_ bytes: [UInt8], pictures: [String: String]) {
            b = bytes
            self.pictures = pictures
        }

        mutating func run() -> String {
            out.reserveCapacity(b.count)
            let n = b.count
            scan: while i < n {
                guard b[i] == lt else {
                    var j = i
                    while j < n, b[j] != lt { j += 1 }
                    out.append(contentsOf: b[i..<j])
                    i = j
                    continue
                }
                let next = i + 1 < n ? b[i + 1] : 0
                if next == bang {
                    if QuotedMarkup.matches(commentOpen, in: b, at: i, caseInsensitive: false) {
                        // From just after `<!`, so that `<!-->` is the empty
                        // comment it is to a browser.
                        guard let end = QuotedMarkup.find(commentClose, in: b, from: i + 2)
                        else { break scan }
                        i = end + 3
                    } else {
                        // A doctype, CDATA, or a conditional comment's shell.
                        guard let end = index(of: gt, from: i + 2) else { break scan }
                        i = end + 1
                    }
                    continue
                }
                if next == question {
                    guard let end = index(of: gt, from: i + 2) else { break scan }
                    i = end + 1
                    continue
                }
                if next == slash, i + 2 < n, isLetter(b[i + 2]) {
                    guard endTag() else { break scan }
                    continue
                }
                if isLetter(next) {
                    guard startTag() else { break scan }
                    continue
                }
                // A `<` that opens nothing, as in "a < b" or "<3".
                out.append(contentsOf: ampLt)
                i += 1
            }
            for name in open.names.reversed() where !closeThemselves.contains(name) {
                out.append(contentsOf: [lt, slash])
                out.append(contentsOf: name.utf8)
                out.append(gt)
            }
            open = OpenElements()
            return String(decoding: out, as: UTF8.self)
        }

        // MARK: Tags

        /// Reads `<name attr=value …>` at `i`. False when the markup ends
        /// inside it.
        mutating func startTag() -> Bool {
            var j = i + 1
            let nameStart = j
            while j < b.count, isNameByte(b[j]) { j += 1 }
            let name = lowercased(nameStart..<j)

            var attributes: [(name: String, value: Range<Int>?)] = []
            var selfClosing = false
            while true {
                while j < b.count, isSpace(b[j]) || b[j] == slash {
                    selfClosing = b[j] == slash
                    j += 1
                }
                guard j < b.count else { return false }
                if b[j] == gt { j += 1; break }
                selfClosing = false
                let attrStart = j
                while j < b.count, !isSpace(b[j]), b[j] != slash, b[j] != gt, b[j] != equals {
                    j += 1
                }
                let attrName = attrStart..<j
                while j < b.count, isSpace(b[j]) { j += 1 }
                var value: Range<Int>?
                if j < b.count, b[j] == equals {
                    j += 1
                    while j < b.count, isSpace(b[j]) { j += 1 }
                    guard j < b.count else { return false }
                    if b[j] == quote || b[j] == apostrophe {
                        guard let close = index(of: b[j], from: j + 1) else { return false }
                        value = (j + 1)..<close
                        j = close + 1
                    } else {
                        let valueStart = j
                        while j < b.count, !isSpace(b[j]), b[j] != gt { j += 1 }
                        value = valueStart..<j
                    }
                }
                if !attrName.isEmpty { attributes.append((lowercased(attrName), value)) }
            }
            i = j

            if droppedWhole.contains(name) {
                // Foreign content honours `/>`; HTML's elements do not.
                if selfClosing, name == "svg" || name == "math" { return true }
                skipContent(of: name)
                return true
            }
            guard keptElements.contains(name) else { return true }

            if name == "li", open.last == "li" { open.removeLast() }
            if name == "dt" || name == "dd", let last = open.last, last == "dt" || last == "dd" {
                open.removeLast()
            }
            if name == "td" || name == "th", let last = open.last, last == "td" || last == "th" {
                open.removeLast()
            }
            if name == "tr" {
                if let last = open.last, last == "td" || last == "th" { open.removeLast() }
                if open.last == "tr" { open.removeLast() }
            }
            if closesParagraph.contains(name), open.last == "p" { open.removeLast() }
            // Nested past the limit: the element loses its tag and keeps
            // what is inside it, as one not on the list does.
            if !voidElements.contains(name), open.isFull { return true }

            tag.removeAll(keepingCapacity: true)
            tag.append(lt)
            tag.append(contentsOf: name.utf8)
            guard writeAttributes(attributes, of: name) else { return true }
            tag.append(gt)
            out.append(contentsOf: tag)
            if !voidElements.contains(name) { open.push(name) }
            return true
        }

        /// Reads `</name …>` at `i`, and lets it through only if it closes
        /// something this markup opened.
        mutating func endTag() -> Bool {
            var j = i + 2
            let nameStart = j
            while j < b.count, isNameByte(b[j]) { j += 1 }
            let name = lowercased(nameStart..<j)
            guard let end = tagEnd(from: j) else { return false }
            i = end + 1
            guard open.close(name) else { return true }
            out.append(contentsOf: [lt, slash])
            out.append(contentsOf: name.utf8)
            out.append(gt)
            return true
        }

        /// Moves `i` past the content of a dropped element and its closing
        /// tag, or to the end if it never closes.
        mutating func skipContent(of name: String) {
            let closing = Array(("</" + name).utf8)
            if name == "plaintext" { i = b.count; return }
            if name == "head", headsNeverClose { skipUnclosedHead(); return }
            if rawText.contains(name) {
                var from = i
                while let at = QuotedMarkup.find(closing, in: b, from: from, caseInsensitive: true) {
                    let after = at + closing.count
                    if after >= b.count || isSpace(b[after]) || b[after] == slash || b[after] == gt {
                        i = tagEnd(from: after).map { $0 + 1 } ?? b.count
                        return
                    }
                    from = after
                }
                i = b.count
                return
            }
            // Ordinary content: count this element's own tags, so a nested
            // one does not end it early.
            let opening = Array(("<" + name).utf8)
            var depth = 1
            var j = i
            while j < b.count {
                guard b[j] == lt else { j += 1; continue }
                // A `<body>` ends a head wherever its `</head>` is, as it
                // does in a browser: what follows is the letter.
                if name == "head",
                   QuotedMarkup.matches(bodyOpen, in: b, at: j, caseInsensitive: true),
                   j + bodyOpen.count >= b.count || !isNameByte(b[j + bodyOpen.count]) {
                    i = j
                    return
                }
                if QuotedMarkup.matches(closing, in: b, at: j, caseInsensitive: true),
                   j + closing.count >= b.count || !isNameByte(b[j + closing.count]) {
                    depth -= 1
                    guard let end = tagEnd(from: j + closing.count) else { i = b.count; return }
                    j = end + 1
                    if depth == 0 { i = j; return }
                    continue
                }
                if QuotedMarkup.matches(opening, in: b, at: j, caseInsensitive: true),
                   j + opening.count >= b.count || !isNameByte(b[j + opening.count]) {
                    guard let end = tagEnd(from: j + opening.count) else { i = b.count; return }
                    if b[end - 1] != slash { depth += 1 }
                    j = end + 1
                    continue
                }
                j += 1
            }
            if name == "head" {
                headsNeverClose = true
                skipUnclosedHead()
                return
            }
            i = b.count
        }

        /// Moves `i` past a head that is never closed, to where a browser
        /// ends it: the first text, or the first tag that is not one of a
        /// head's own (`<title>`, `<style>`, `<meta>` and the like). That is
        /// usually a `<body>`: HTML lets a sender leave `</head>` out, and
        /// taking the head to the end of the markup took the whole letter
        /// with it.
        mutating func skipUnclosedHead() {
            while i < b.count {
                if isSpace(b[i]) { i += 1; continue }
                guard b[i] == lt, i + 1 < b.count else { return }
                let next = b[i + 1]
                if next == bang || next == question {
                    // A comment, or a doctype: nothing a browser shows.
                    let comment = QuotedMarkup.matches(commentOpen, in: b, at: i,
                                                       caseInsensitive: false)
                    let end = comment
                        ? QuotedMarkup.find(commentClose, in: b, from: i + 2).map { $0 + 3 }
                        : index(of: gt, from: i + 2).map { $0 + 1 }
                    guard let end else { i = b.count; return }
                    i = end
                    continue
                }
                let closing = next == slash
                var j = i + (closing ? 2 : 1)
                let nameStart = j
                while j < b.count, isNameByte(b[j]) { j += 1 }
                let element = lowercased(nameStart..<j)
                // `</body>`, `</html>` and `</br>` end a head as well; a
                // browser ignores any other closing tag inside one.
                if closing ? ["body", "html", "br"].contains(element)
                           : !headContent.contains(element) {
                    return
                }
                guard let end = tagEnd(from: j) else { i = b.count; return }
                i = end + 1
                if !closing, element != "head", droppedWhole.contains(element) {
                    skipContent(of: element)
                }
            }
        }

        // MARK: Attributes

        /// Writes the attributes worth keeping into `tag`, afresh. False when
        /// the element itself has to go: a picture whose source is not one
        /// this letter carries.
        mutating func writeAttributes(_ attributes: [(name: String, value: Range<Int>?)],
                                      of element: String) -> Bool {
            var seen = Set<String>()
            for (name, range) in attributes {
                // The first of a repeated attribute is the one a browser uses.
                // A set, where it was a list searched for each one: a tag of
                // ten thousand attributes was a hundred million comparisons.
                guard !seen.contains(name), isAttributeName(name) else { continue }
                seen.insert(name)
                if name.hasPrefix("on") || droppedAttributes.contains(name) { continue }
                guard let range else {
                    tag.append(space)
                    tag.append(contentsOf: name.utf8)
                    continue
                }
                let value: [UInt8]
                if name == "style" {
                    guard let style = safeStyle(b[range]) else { continue }
                    value = style
                } else if addressAttributes.contains(name) || name.hasSuffix(":href")
                            || name.hasSuffix(":src") {
                    guard let address = safeAddress(b[range],
                                                    picture: element == "img" && name == "src")
                    else {
                        if element == "img", name == "src" { return false }
                        continue
                    }
                    value = address
                } else if name == "srcset" {
                    guard let set = safeSourceSet(b[range]) else { continue }
                    value = set
                } else {
                    // Descriptive: width, alt, class, colour. Written as it
                    // came, so a title's entities still read as the sender
                    // meant; only a double quote could end the value early.
                    tag.append(space)
                    tag.append(contentsOf: name.utf8)
                    tag.append(contentsOf: equalsQuote)
                    for c in b[range] {
                        if c == quote { tag.append(contentsOf: ampQuot) } else { tag.append(c) }
                    }
                    tag.append(quote)
                    continue
                }
                // Checked values are written as they were checked: decoded,
                // then escaped again, so what a browser reads is exactly
                // what was looked at.
                tag.append(space)
                tag.append(contentsOf: name.utf8)
                tag.append(contentsOf: equalsQuote)
                QuotedMarkup.appendEscaped(value, to: &tag)
                tag.append(quote)
            }
            return true
        }

        /// An address as it may go out, or nil when it may not.
        ///
        /// Checked after the entities a browser would decode are decoded and
        /// the spaces and control characters a browser ignores are gone,
        /// because `jav&#x61;script:` and `java\tscript:` are both
        /// `javascript:` to a browser. A value with an entity this cannot
        /// read is refused rather than guessed at.
        mutating func safeAddress(_ raw: ArraySlice<UInt8>, picture: Bool) -> [UInt8]? {
            guard var address = QuotedMarkup.decoded(raw) else { return nil }
            address = QuotedMarkup.trimmed(address).filter { $0 != 0x09 && $0 != 0x0A && $0 != 0x0D }
            guard let (scheme, colon) = QuotedMarkup.scheme(of: address) else { return address }
            switch scheme {
            case "http", "https", "mailto", "tel", "sms":
                return address
            case "cid":
                guard let new = renamed(address[(colon + 1)...]) else { return nil }
                return Array("cid:".utf8) + new
            case "data":
                return picture && QuotedMarkup.isPictureData(address) ? address : nil
            default:
                return nil
            }
        }

        /// A `srcset` whose every address is on the web, or nil.
        func safeSourceSet(_ raw: ArraySlice<UInt8>) -> [UInt8]? {
            guard let decoded = QuotedMarkup.decoded(raw) else { return nil }
            for candidate in decoded.split(separator: UInt8(ascii: ",")) {
                let address = QuotedMarkup.trimmed(Array(candidate))
                    .split(whereSeparator: { $0 <= 0x20 }).first.map(Array.init) ?? []
                guard let (scheme, _) = QuotedMarkup.scheme(of: address) else { continue }
                guard scheme == "http" || scheme == "https" else { return nil }
            }
            return decoded
        }

        /// A `style` as it may go out, with its pictures renamed, or nil.
        ///
        /// Refused whole rather than edited: a declaration that can run code
        /// (`expression()`, `-moz-binding`, `behavior`), one that can draw
        /// the element over the letter around it (`displaces`), a `url()`
        /// that is not a picture on the web or in the letter, an `@import`,
        /// or a backslash, which is how CSS spells a character in hex and how
        /// each of the others can be hidden.
        mutating func safeStyle(_ raw: ArraySlice<UInt8>) -> [UInt8]? {
            guard let decoded = QuotedMarkup.decoded(raw), !decoded.contains(backslash) else {
                return nil
            }
            let compact = QuotedMarkup.compactCSS(decoded)
            for bad in dangerousCSS where QuotedMarkup.find(bad, in: compact, from: 0) != nil {
                return nil
            }
            guard !QuotedMarkup.displaces(compact),
                  let style = QuotedMarkup.picturesRenamed(in: decoded, compact: compact,
                                                           { renamed($0) })
            else { return nil }
            // Every reference left is one this letter carries, or the style
            // goes: one the steps above did not rename would show the
            // original's id, which can be one of this letter's own.
            let ids = QuotedMarkup.contentIDs(shownBy: String(decoding: style, as: UTF8.self))
            guard ids.allSatisfy(shown.contains) else { return nil }
            return style
        }

        /// The id a picture of the original goes under here, or nil when the
        /// letter does not carry it.
        mutating func renamed(_ id: ArraySlice<UInt8>) -> [UInt8]? {
            var bare = Substring(String(decoding: id, as: UTF8.self))
            while let c = bare.first, c == "<" || c == " " { bare.removeFirst() }
            while let c = bare.last, c == ">" || c == " " { bare.removeLast() }
            let key = String(bare)
            let new = pictures[key]
                ?? key.removingPercentEncoding.flatMap { pictures[$0] }
                ?? inOneCase()[QuotedMarkup.folded(key)]
            guard let new else { return nil }
            shown.insert(new)
            return Array(new.utf8)
        }

        /// `pictures` by their ids in one case, as `caseInsensitiveCompare`
        /// matches them.
        ///
        /// A table, where each reference not found as written used to be
        /// compared with every picture in turn: a forward carries up to 500,
        /// so a letter of 500 pictures whose references were written in
        /// another case, or named none of them, took 7.3 s for 1.1 MB in a
        /// release build, on the actor Send and Save Draft wait on, and
        /// again at every launch while the forward waited in the Outbox.
        /// Where two ids differ only in case, the first in order is the one
        /// found, so the same letter is quoted the same way every time; the
        /// comparison took whichever the dictionary happened to hold first.
        mutating func inOneCase() -> [String: String] {
            if let made = picturesInOneCase { return made }
            var made: [String: String] = [:]
            for key in pictures.keys.sorted() {
                let folded = QuotedMarkup.folded(key)
                if made[folded] == nil { made[folded] = pictures[key] }
            }
            picturesInOneCase = made
            return made
        }

        // MARK: Scanning

        func index(of byte: UInt8, from start: Int) -> Int? {
            var j = start
            while j < b.count {
                if b[j] == byte { return j }
                j += 1
            }
            return nil
        }

        /// The `>` that ends the tag whose body starts at `start`, past any
        /// quoted value that holds one.
        func tagEnd(from start: Int) -> Int? {
            var j = start
            var mark: UInt8?
            while j < b.count {
                let c = b[j]
                if let m = mark {
                    if c == m { mark = nil }
                } else if c == quote || c == apostrophe {
                    mark = c
                } else if c == gt {
                    return j
                }
                j += 1
            }
            return nil
        }

        /// A tag or attribute name, lowercased: ASCII only, which is all a
        /// name that means anything is made of.
        func lowercased(_ range: Range<Int>) -> String {
            String(unsafeUninitializedCapacity: range.count) { buffer in
                for (k, c) in b[range].enumerated() { buffer[k] = lowered(c) }
                return range.count
            }
        }
    }

    // MARK: - Checking values

    /// The scheme of an address, lowercased, and where its colon is; nil when
    /// it has none and is relative. The rules are the URL standard's: a
    /// letter, then letters, digits, `+`, `-` and `.`, then a colon; anything
    /// else first means there is no scheme. Spaces and control characters
    /// are skipped while reading it, so `java script:` is read as the
    /// `javascript:` it would be if a browser or relay closed the gap.
    static func scheme(of address: [UInt8]) -> (String, Int)? {
        var name: [UInt8] = []
        for (k, c) in address.enumerated() {
            if c <= 0x20 { continue }
            if c == UInt8(ascii: ":") {
                guard let first = name.first, isLetter(first) else { return nil }
                return (String(decoding: name, as: UTF8.self), k)
            }
            guard isLetter(c) || (c >= 0x30 && c <= 0x39) || c == 0x2B || c == 0x2D || c == 0x2E
            else { return nil }
            name.append(lowered(c))
        }
        return nil
    }

    /// A `data:` address holding a picture a browser draws without running
    /// anything. Not SVG, which is a document and can hold a script.
    static func isPictureData(_ address: [UInt8]) -> Bool {
        let head = String(decoding: address.lazy.filter { $0 > 0x20 }.prefix(16).map(lowered),
                          as: UTF8.self)
        return ["data:image/png", "data:image/jpeg", "data:image/jpg", "data:image/gif",
                "data:image/webp", "data:image/bmp"].contains { head.hasPrefix($0) }
    }

    /// The value a browser sees, entities decoded, or nil when it holds a
    /// named entity this does not know. Numeric ones decode with or without
    /// their semicolon, as a browser decodes them.
    static func decoded(_ raw: ArraySlice<UInt8>) -> [UInt8]? {
        guard raw.contains(amp) else { return Array(raw) }
        var out: [UInt8] = []
        out.reserveCapacity(raw.count)
        let s = Array(raw)
        var k = 0
        while k < s.count {
            guard s[k] == amp else { out.append(s[k]); k += 1; continue }
            var j = k + 1
            if j < s.count, s[j] == UInt8(ascii: "#") {
                j += 1
                var hex = false
                if j < s.count, s[j] == UInt8(ascii: "x") || s[j] == UInt8(ascii: "X") {
                    hex = true
                    j += 1
                }
                let digitsStart = j
                while j < s.count, hex ? isHexDigit(s[j]) : (s[j] >= 0x30 && s[j] <= 0x39) {
                    j += 1
                }
                guard j > digitsStart else { out.append(amp); k += 1; continue }
                let digits = String(decoding: s[digitsStart..<j], as: UTF8.self).drop { $0 == "0" }
                if j < s.count, s[j] == UInt8(ascii: ";") { j += 1 }
                // Zero, out of range or a surrogate: a browser draws U+FFFD.
                let value = digits.count > 8 ? nil : UInt32(digits, radix: hex ? 16 : 10)
                let scalar = value.flatMap { $0 == 0 ? nil : Unicode.Scalar($0) } ?? "\u{FFFD}"
                out.append(contentsOf: String(scalar).utf8)
                k = j
                continue
            }
            let nameStart = j
            while j < s.count, isLetter(s[j]) || (s[j] >= 0x30 && s[j] <= 0x39) { j += 1 }
            guard j > nameStart, j < s.count, s[j] == UInt8(ascii: ";") else {
                // A bare ampersand, or a legacy name with no semicolon:
                // neither can spell a colon or a letter.
                out.append(amp)
                k += 1
                continue
            }
            let name = String(decoding: s[nameStart..<j], as: UTF8.self)
            guard let value = namedEntities[name] ?? namedEntities[name.lowercased()] else {
                return nil
            }
            out.append(contentsOf: value.utf8)
            k = j + 1
        }
        return out
    }

    /// The named entities that turn up in addresses and styles, including
    /// every one that spells a character with meaning in a URL or in CSS,
    /// so that `javascript&colon;` is read as what it is.
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "colon": ":", "Tab": "\t", "NewLine": "\n", "sol": "/", "bsol": "\\",
        "lpar": "(", "rpar": ")", "period": ".", "comma": ",", "semi": ";",
        "equals": "=", "num": "#", "excl": "!", "quest": "?", "commat": "@",
        "lowbar": "_", "dollar": "$", "percnt": "%", "plus": "+", "ast": "*",
        "lsqb": "[", "rsqb": "]", "lbrack": "[", "rbrack": "]", "lcub": "{",
        "rcub": "}", "lbrace": "{", "rbrace": "}", "grave": "`", "hat": "^",
        "verbar": "|", "vert": "|", "hyphen": "\u{2010}", "dash": "\u{2010}",
        "mdash": "\u{2014}", "ndash": "\u{2013}", "hellip": "\u{2026}",
        "copy": "\u{00A9}", "reg": "\u{00AE}", "trade": "\u{2122}", "shy": "\u{00AD}",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
    ]

    /// CSS as it is checked: lowercased, with its `/* … */` comments, which
    /// is where a word such as `expression` can be split in two, and every
    /// space and control character taken out.
    static func compactCSS(_ css: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(css.count)
        var k = 0
        while k < css.count {
            if css[k] == slash, k + 1 < css.count, css[k + 1] == UInt8(ascii: "*") {
                guard let close = find(Array("*/".utf8), in: css, from: k + 2) else { break }
                k = close + 2
                continue
            }
            if css[k] > 0x20 { out.append(lowered(css[k])) }
            k += 1
        }
        return out
    }

    /// Whether a style can draw its element out of the flow of the letter
    /// or over what is around it: a `position` other than `static` or
    /// `relative`, an offset, a `z-index`, a transform, or a negative margin.
    ///
    /// The quote sits below his words and his signature, and a reader such
    /// as Mail draws a `position: fixed` box, or one pulled up by a negative
    /// margin or moved by a transform, over them, where a stranger's words
    /// would pass as his. Read from `compactCSS`'s copy, split at every `;`,
    /// `{` and `}`. That splits it wherever a browser begins a declaration,
    /// so none can hide inside another; a split a browser would not make
    /// only refuses more.
    static func displaces(_ compact: [UInt8]) -> Bool {
        let separators: Set<UInt8> = [UInt8(ascii: ";"), UInt8(ascii: "{"), UInt8(ascii: "}")]
        for declaration in compact.split(whereSeparator: separators.contains) {
            guard let colon = declaration.firstIndex(of: UInt8(ascii: ":")) else { continue }
            var name = declaration[..<colon]
            // `-webkit-transform` is `transform` to the reader it is for.
            let dash = UInt8(ascii: "-")
            if name.first == dash, name.dropFirst().first != dash,
               let second = name.dropFirst().firstIndex(of: dash) {
                name = name[(second + 1)...]
            }
            let property = String(decoding: name, as: UTF8.self)
            let value = declaration[(colon + 1)...]
            switch property {
            case "position":
                let kept = value.prefix { $0 != UInt8(ascii: "!") }
                if !kept.elementsEqual("static".utf8), !kept.elementsEqual("relative".utf8) {
                    return true
                }
            case "top", "right", "bottom", "left", "z-index", "translate", "rotate", "scale":
                return true
            default:
                if property.hasPrefix("inset") || property.hasPrefix("transform")
                    || property.hasPrefix("offset") { return true }
                if property.hasPrefix("margin"), value.contains(dash) { return true }
            }
        }
        return false
    }

    /// Where `reference` stands in `style` from `start` as a whole reference,
    /// ended by a bracket, a quote, a space or the end, in any case.
    ///
    /// One pass, whatever the reference: the sender writes it, and it can be
    /// as long as the style. Looking for it afresh at each place it might
    /// start, and again one byte on from each place it was found without
    /// its end, read a style of `cid:` written over and over, with the
    /// reference made of the same, once per byte. This is Knuth, Morris and
    /// Pratt's search, which carries over from each byte how much of the
    /// reference the bytes before it already are.
    static func reference(_ reference: [UInt8], in style: [UInt8], from start: Int) -> Int? {
        let needle = reference.map(lowered)
        guard !needle.isEmpty, start >= 0 else { return nil }
        // For each length matched, the longest shorter start of the
        // reference that also ends it: where to carry on from after a
        // byte that does not continue the match.
        var fallback = [Int](repeating: 0, count: needle.count)
        var k = 0
        for q in needle.indices.dropFirst() {
            while k > 0, needle[q] != needle[k] { k = fallback[k - 1] }
            if needle[q] == needle[k] { k += 1 }
            fallback[q] = k
        }
        var matched = 0
        var j = start
        while j < style.count {
            let c = lowered(style[j])
            while matched > 0, c != needle[matched] { matched = fallback[matched - 1] }
            if c == needle[matched] { matched += 1 }
            j += 1
            guard matched == needle.count else { continue }
            if j == style.count || style[j] <= 0x20 || style[j] == UInt8(ascii: ")")
                || style[j] == quote || style[j] == apostrophe {
                return j - needle.count
            }
            matched = fallback[matched - 1]
        }
        return nil
    }

    /// `style` with the id in each of its `url(cid:…)` references renamed
    /// by `renamed`, or nil when one is not a picture the letter carries,
    /// or a `url()` is not a picture at all, on the web or in the letter.
    /// `compact` is `style` as `compactCSS` makes it, where the `url(`s are
    /// looked for.
    ///
    /// Every id is found first and all are put in together, in one copy.
    /// Each used to be put in as it was found, which moved the rest of the
    /// style along each time a new name was longer than the old, and a new
    /// name is always longer: 180,000 references in a style of 4 MB took
    /// 8 s in a release build, on the actor that Send waits on, and again at
    /// every launch for a forward waiting in the Outbox.
    static func picturesRenamed(in style: [UInt8], compact: [UInt8],
                                _ renamed: (ArraySlice<UInt8>) -> [UInt8]?) -> [UInt8]? {
        var from = 0
        // Where in `style` the next reference is looked for: past the last
        // one found, so that a second `url(cid:p)` finds its own `cid:p`
        // and not the first one's again.
        var renamedUpTo = 0
        var renames: [(range: Range<Int>, to: [UInt8])] = []
        while let at = QuotedMarkup.find(urlOpen, in: compact, from: from) {
            var end = at + urlOpen.count
            while end < compact.count, compact[end] != UInt8(ascii: ")") { end += 1 }
            let inside = Array(compact[(at + urlOpen.count)..<end])
                .filter { $0 != quote && $0 != apostrophe }
            from = end
            guard let (scheme, colon) = QuotedMarkup.scheme(of: inside) else { continue }
            switch scheme {
            case "http", "https":
                continue
            case "data" where QuotedMarkup.isPictureData(inside):
                continue
            case "cid":
                // Found in the lowercased copy; renamed in the real one.
                let reference = Array("cid:".utf8) + inside[(colon + 1)...]
                guard let at = QuotedMarkup.reference(reference, in: style, from: renamedUpTo),
                      let new = renamed(style[(at + 4)..<(at + reference.count)])
                else { return nil }
                renames.append(((at + 4)..<(at + reference.count), new))
                renamedUpTo = at + reference.count
            default:
                return nil
            }
        }
        guard !renames.isEmpty else { return style }
        var out: [UInt8] = []
        out.reserveCapacity(style.count + style.count / 2)
        var copied = 0
        for (range, new) in renames {
            out.append(contentsOf: style[copied..<range.lowerBound])
            out.append(contentsOf: new)
            copied = range.upperBound
        }
        out.append(contentsOf: style[copied...])
        return out
    }

    /// An id in one case: two ids are the same to `caseInsensitiveCompare`
    /// when their folded forms are equal, ß and SS included.
    static func folded(_ id: String) -> String {
        id.folding(options: .caseInsensitive, locale: nil)
    }

    /// Leading and trailing spaces and control characters off, as a browser
    /// takes them off an address.
    static func trimmed(_ bytes: [UInt8]) -> [UInt8] {
        guard let first = bytes.firstIndex(where: { $0 > 0x20 }),
              let last = bytes.lastIndex(where: { $0 > 0x20 }) else { return [] }
        return Array(bytes[first...last])
    }

    /// `bytes` as the value of a double-quoted attribute.
    static func appendEscaped(_ bytes: [UInt8], to out: inout [UInt8]) {
        for c in bytes {
            switch c {
            case amp: out.append(contentsOf: ampAmp)
            case quote: out.append(contentsOf: ampQuot)
            case lt: out.append(contentsOf: ampLt)
            case gt: out.append(contentsOf: ampGt)
            default: out.append(c)
            }
        }
    }

    // MARK: - Bytes

    static func find(_ needle: [UInt8], in bytes: [UInt8], from start: Int,
                     caseInsensitive: Bool = false) -> Int? {
        guard !needle.isEmpty, start >= 0, bytes.count >= needle.count else { return nil }
        var j = start
        let first = needle[0]
        let lowFirst = lowered(first)
        let last = bytes.count - needle.count
        while j <= last {
            let c = bytes[j]
            if c == first || (caseInsensitive && lowered(c) == lowFirst),
               matches(needle, in: bytes, at: j, caseInsensitive: caseInsensitive) {
                return j
            }
            j += 1
        }
        return nil
    }

    static func matches(_ needle: [UInt8], in bytes: [UInt8], at index: Int,
                        caseInsensitive: Bool) -> Bool {
        guard index >= 0, index + needle.count <= bytes.count else { return false }
        for k in 0..<needle.count {
            let a = bytes[index + k], n = needle[k]
            if a == n { continue }
            if caseInsensitive, lowered(a) == lowered(n) { continue }
            return false
        }
        return true
    }
}

private let lt = UInt8(ascii: "<")
private let gt = UInt8(ascii: ">")
private let bang = UInt8(ascii: "!")
private let question = UInt8(ascii: "?")
private let slash = UInt8(ascii: "/")
private let backslash = UInt8(ascii: "\\")
private let equals = UInt8(ascii: "=")
private let quote = UInt8(ascii: "\"")
private let apostrophe = UInt8(ascii: "'")
private let amp = UInt8(ascii: "&")
private let space = UInt8(ascii: " ")

private let ampAmp = Array("&amp;".utf8)
private let ampQuot = Array("&quot;".utf8)
private let ampLt = Array("&lt;".utf8)
private let ampGt = Array("&gt;".utf8)
private let equalsQuote = Array("=\"".utf8)
private let commentOpen = Array("<!--".utf8)
private let commentClose = Array("-->".utf8)
private let urlOpen = Array("url(".utf8)
private let bodyOpen = Array("<body".utf8)
private let dangerousCSS = ["expression(", "javascript:", "vbscript:", "-moz-binding", "behavior:",
                            "behaviour:", "@import", "</"].map { Array($0.utf8) }

private func lowered(_ c: UInt8) -> UInt8 {
    (c >= 0x41 && c <= 0x5A) ? c + 0x20 : c
}

private func isLetter(_ c: UInt8) -> Bool {
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
}

private func isHexDigit(_ c: UInt8) -> Bool {
    (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66)
}

private func isSpace(_ c: UInt8) -> Bool {
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D
}

/// What a tag's name is made of, `o:p` and `my-widget` included.
private func isNameByte(_ c: UInt8) -> Bool {
    isLetter(c) || (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x3A || c == 0x5F || c == 0x2E
}

/// An attribute name worth writing out: `data-x`, `xml:lang`, `width`.
private func isAttributeName(_ name: String) -> Bool {
    guard let first = name.utf8.first, isLetter(first) || first == 0x5F else { return false }
    return name.utf8.allSatisfy { isNameByte($0) }
}
