import Foundation

/// Mail's Block All Remote Content (B-168): with it on, a letter's
/// pictures from the web, and anything else it asks the web for, are not
/// loaded, in the reading pane, in a conversation's stack or on paper; the
/// letter says "Message contains unloaded images." over its words, with
/// "Load All Images", and a tap on that loads that letter's, and only
/// that letter's. Its own pictures, the parts it carries (`cid:`), are
/// drawn as ever. With it off, as it comes (`MessagesOptions`), nothing
/// here is used and every page is as it was.
///
/// Two things hold the web back, so that neither alone has to be whole:
///
/// - WebKit's own list (`ruleList`), on the pane's web view while no
///   letter of the page has been loaded, and on a print's, which blocks
///   every request to `http:` or `https:` the page makes, whatever asked
///   for it: a picture, a style sheet, a font, a picture inside either.
///   It does not see the pane's own pages (`about:blank`), nor the
///   letter's own pictures (`bmcid:`).
/// - The letter's markup, with each reference to the web it makes where a
///   page loads from (`references`) turned into one to a scheme nothing
///   answers (`blocked`). That is all that holds back a letter of a
///   conversation once another letter of it has been loaded: the list is
///   then off for the page, as one web view draws the whole stack and the
///   list cannot tell one letter's requests from another's. A reference it
///   does not see there, the scheme written with character references or
///   CSS escapes, goes out then; with the list on it is blocked.
///
/// The words are Mail's, from its strings (`REMOTE_IMAGES_BLOCKED_OTHER`,
/// `LOAD_REMOTE_IMAGES_OTHER`, iOS 18.6); how Mail lays the line out on an
/// iPad was not seen, and its look here is the pane's own.
///
/// Pure, out of the controllers, so the suite on Linux can test it.
enum RemoteContent {

    /// Mail's line over a letter whose pictures from the web are held back.
    static let unloaded = "Message contains unloaded images."
    /// Mail's button on it, which loads them.
    static let loadAll = "Load All Images"

    /// The scheme of the button's link, which never leaves the pane
    /// (`PaneNavigation`), as `BodyFiles.scheme` is a file's row's.
    static let scheme = "bmimages"

    /// What goes before `http:` or `https:` in a reference held back:
    /// `bmoffhttps:` is a scheme no handler answers and WebKit sends
    /// nowhere, and a URL of it holds no host WebKit could resolve a
    /// relative address against.
    static let inert = "bmoff"

    /// WebKit's list's name in its store, and the list: every request to
    /// the web blocked, of any kind. Its pattern is WebKit's own syntax,
    /// which has no `|`; WebKit has parsed every address before it is
    /// matched, so `https:host` is `https://host/` by then.
    static let ruleListID = "blackmail.blockAllRemoteContent"
    static let ruleList = #"[{"trigger":{"url-filter":"^https?:"},"action":{"type":"block"}}]"#

    // MARK: - The line

    /// The line over a letter whose pictures from the web are held back,
    /// its button a link naming `id`, the letter's on a page of its own,
    /// its entry's in a stack (`ConversationDocument.Entry.id`). Inside the
    /// letter's own block, which the pane inverts for an HTML letter, and
    /// only an HTML letter asks the web for anything: so in the light
    /// colours the invert turns dark, as the letter's links are (`#007AFF`)
    /// and the pane's own grey line over a shortened letter is
    /// (`PanePage.shortenedLine`). A rule under it, the colour of the
    /// stack's own between letters once inverted.
    static func line(for id: String) -> String {
        "<div style=\"display: flex; align-items: baseline; gap: 12px; margin: 0 0 1em 0; "
            + "padding: 0 0 10px 0; border-bottom: 0.5px solid #c7c7c5; white-space: normal;\">"
            + "<span style=\"flex: 1 1 auto; color: #8e8e93;\">" + unloaded + "</span>"
            + "<a href=\"" + link(for: id) + "\" style=\"flex: 0 0 auto; color: #007AFF; "
            + "text-decoration: none;\">" + loadAll + "</a></div>"
    }

    /// The button's link: `bmimages:?letter=<id>`, the id escaped as a
    /// query's value is.
    static func link(for id: String) -> String {
        var parts = URLComponents()
        parts.scheme = scheme
        parts.queryItems = [URLQueryItem(name: "letter", value: id)]
        return parts.string ?? scheme + ":"
    }

    /// The letter a tapped button's link names, nil for any other address.
    static func letter(of url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = parts.queryItems?.first(where: { $0.name == "letter" })?.value,
              !id.isEmpty
        else { return nil }
        return id
    }

    // MARK: - The markup

    /// Whether `html`, the sender's markup as the page draws it, asks the
    /// web for anything where a page loads from: whether the line is to go
    /// over it.
    static func asksTheWeb(_ html: String) -> Bool {
        !references(in: html, stoppingAtFirst: true).isEmpty
    }

    /// `html` with each reference to the web in it held back: `inert`
    /// written before its `http:` or `https:`. Nothing else changes; a
    /// letter that asks the web for nothing comes back as it was. Twice is
    /// once: `bmoffhttps:` is no reference.
    static func blocked(_ html: String) -> String {
        let marks = references(in: html, stoppingAtFirst: false)
        guard !marks.isEmpty else { return html }
        let bytes = Array(html.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + marks.count * inert.utf8.count)
        var at = 0
        for mark in marks {
            out.append(contentsOf: bytes[at..<mark])
            out.append(contentsOf: inert.utf8)
            at = mark
        }
        out.append(contentsOf: bytes[at...])
        return String(decoding: out, as: UTF8.self)
    }

    /// Where each reference to the web in `html` begins, in its UTF-8: the
    /// `h` of an `http:` or `https:`, in any case, that no letter, digit,
    /// `+`, `-` or `.` comes right before, so it is the whole of a scheme,
    /// slashes or none (`https:host` loads as `https://host/`), a tab or a
    /// line break among its letters or none (the URL parser drops them,
    /// so `ht<LF>tp:` loads as `http:`), in a place a page loads from:
    ///
    /// - the value of an attribute that names something to load: `src`,
    ///   `srcset`, `background`, `poster`, `lowsrc`, `dynsrc`, `data`,
    ///   `codebase`, `archive`, `code`, `icon`, `manifest`, `imagesrcset`;
    ///   `href` and `xlink:href` on anything but a link (`<a>`, `<area>`),
    ///   so a `<link>` style sheet, a `<base>` that would point relative
    ///   addresses at the web, and SVG's `<image>`, `<use>` and the rest;
    ///   `style`, and SVG's attributes that take a `url()`;
    /// - a `<style>` element's text, all of it CSS.
    ///
    /// Not a link's address, which a tap opens in Safari as ever, nor the
    /// letter's words, nor a comment (Outlook's `<!--[if mso]>` among
    /// them), ended where HTML ends it: at `-->` or `--!>`, or at once by
    /// `<!-->` or `<!--->`; nor the text of `<script>`, `<textarea>`,
    /// `<title>`, `<iframe>` and the other elements whose text is not
    /// markup. A `<meta>` refresh or a frame's `src` is a navigation, which
    /// the pane cancels whatever it names (`PaneNavigation`), and is not
    /// counted.
    ///
    /// One pass over the bytes, as `InlineImageRewriter.rewrite`.
    static func references(in html: String, stoppingAtFirst: Bool = false) -> [Int] {
        var contiguous = html
        return contiguous.withUTF8 { bytes -> [Int] in
            var scan = Scan(bytes, first: stoppingAtFirst)
            scan.run()
            return scan.marks
        }
    }

    /// The attributes whose value names something a page loads, by name in
    /// lower case; `href` and `xlink:href` apart, by the element.
    private static let loading: Set<[UInt8]> = Set([
        "src", "srcset", "background", "poster", "lowsrc", "dynsrc", "data", "codebase",
        "archive", "code", "icon", "manifest", "imagesrcset", "style",
        "fill", "stroke", "filter", "mask", "clip-path", "marker-start", "marker-mid",
        "marker-end", "cursor",
    ].map { Array($0.utf8) })

    /// The elements whose text is not markup and loads nothing, skipped to
    /// their end tag.
    private static let rawText: Set<[UInt8]> = Set([
        "script", "textarea", "title", "xmp", "iframe", "noembed", "noframes",
    ].map { Array($0.utf8) })

    private struct Scan {
        let b: UnsafeBufferPointer<UInt8>
        let first: Bool
        var marks: [Int] = []

        init(_ bytes: UnsafeBufferPointer<UInt8>, first: Bool) {
            b = bytes
            self.first = first
        }

        var done: Bool { first && !marks.isEmpty }

        mutating func run() {
            let n = b.count
            var i = 0
            while i < n, !done {
                guard b[i] == lt, i + 1 < n else {
                    i += 1
                    continue
                }
                if matches(commentOpen, at: i) {
                    i = commentEnd(from: i + 4)
                    continue
                }
                let c = b[i + 1]
                if c == slash || c == bang || c == question {
                    var k = i + 2
                    while k < n, b[k] != gt { k += 1 }
                    i = min(k + 1, n)
                    continue
                }
                guard isLetter(c) else {
                    i += 1
                    continue
                }
                var j = i + 1
                while j < n, !isSpace(b[j]), b[j] != slash, b[j] != gt { j += 1 }
                let name = lowered(i + 1, j)
                j = attributes(of: name, from: j)
                if name == style {
                    let end = closing(style, from: j)
                    mark(from: j, to: end)
                    i = end
                } else if RemoteContent.rawText.contains(name) {
                    i = closing(name, from: j)
                } else {
                    i = j
                }
            }
        }

        /// Reads a start tag's attributes from `j`, just after its name,
        /// marking the values that load; returns where the tag ends, after
        /// its `>`, or the end of the markup.
        mutating func attributes(of tag: [UInt8], from start: Int) -> Int {
            let n = b.count
            var j = start
            while j < n {
                while j < n, isSpace(b[j]) || b[j] == slash { j += 1 }
                guard j < n else { return n }
                if b[j] == gt { return j + 1 }
                let nameStart = j
                j += 1
                while j < n, !isSpace(b[j]), b[j] != slash, b[j] != gt, b[j] != equals { j += 1 }
                let attribute = lowered(nameStart, j)
                while j < n, isSpace(b[j]) { j += 1 }
                guard j < n, b[j] == equals else { continue }
                j += 1
                while j < n, isSpace(b[j]) { j += 1 }
                guard j < n else { return n }
                let value: Range<Int>
                if b[j] == quote || b[j] == apostrophe {
                    let close = b[j]
                    var k = j + 1
                    while k < n, b[k] != close { k += 1 }
                    value = (j + 1)..<k
                    j = min(k + 1, n)
                } else {
                    var k = j
                    while k < n, !isSpace(b[k]), b[k] != gt { k += 1 }
                    value = j..<k
                    j = k
                }
                if loads(attribute, on: tag) { mark(from: value.lowerBound, to: value.upperBound) }
                if done { return j }
            }
            return n
        }

        func loads(_ attribute: [UInt8], on tag: [UInt8]) -> Bool {
            if attribute == href || attribute == xlinkHref {
                return tag != a && tag != area
            }
            if attribute == src, tag == iframe || tag == frame { return false }
            return RemoteContent.loading.contains(attribute)
        }

        /// Every reference to the web from `start` up to `end`.
        mutating func mark(from start: Int, to end: Int) {
            var k = start
            while k < end, !done {
                defer { k += 1 }
                guard (b[k] | 0x20) == 0x68,                                        // h
                      let ends = colon(after: k, before: end) else { continue }
                if k > 0, partOfScheme(b[k - 1]) { continue }
                marks.append(k)
                k = ends
            }
        }

        /// The colon of the `http:` or `https:`, in any case, whose `h` is
        /// at `h`, before `end`; nil if the letters there are not one. A tab
        /// or a line break among them, or before the colon, is passed over,
        /// as the URL parser drops them: `ht<LF>tps:` loads as `https:`.
        func colon(after h: Int, before end: Int) -> Int? {
            var k = h + 1
            func skipDropped() {
                while k < end, b[k] == 0x09 || b[k] == 0x0A || b[k] == 0x0D { k += 1 }
            }
            for letter: UInt8 in [0x74, 0x74, 0x70] {                            // t t p
                skipDropped()
                guard k < end, (b[k] | 0x20) == letter else { return nil }
                k += 1
            }
            skipDropped()
            if k < end, (b[k] | 0x20) == 0x73 {                                  // s
                k += 1
                skipDropped()
            }
            return k < end && b[k] == 0x3A ? k : nil                              // :
        }

        /// Where a comment ends, after its `>`, its `<!--` ending just
        /// before `start`: where HTML ends it, at once for `<!-->` and
        /// `<!--->`, or else at the first `-->` or `--!>`; the end of the
        /// markup if it is never closed.
        func commentEnd(from start: Int) -> Int {
            let n = b.count
            if start < n, b[start] == gt { return start + 1 }
            if start + 1 < n, b[start] == dash, b[start + 1] == gt { return start + 2 }
            var k = start
            while k + 2 < n {
                if b[k] == dash, b[k + 1] == dash {
                    if b[k + 2] == gt { return k + 3 }
                    if b[k + 2] == bang, k + 3 < n, b[k + 3] == gt { return k + 4 }
                }
                k += 1
            }
            return n
        }

        /// Where the text of an element named `name` ends: the `<` of its
        /// end tag, or the end of the markup.
        func closing(_ name: [UInt8], from start: Int) -> Int {
            let n = b.count
            var k = start
            while k + 1 < n {
                if b[k] == lt, b[k + 1] == slash, k + 2 + name.count <= n {
                    var same = true
                    for m in 0..<name.count where (b[k + 2 + m] | 0x20) != name[m] {
                        same = false
                        break
                    }
                    if same, k + 2 + name.count == n || !isNameByte(b[k + 2 + name.count]) {
                        return k
                    }
                }
                k += 1
            }
            return n
        }

        func matches(_ needle: [UInt8], at index: Int) -> Bool {
            guard index + needle.count <= b.count else { return false }
            for m in 0..<needle.count where b[index + m] != needle[m] { return false }
            return true
        }

        func lowered(_ from: Int, _ to: Int) -> [UInt8] {
            (from..<to).map { c in
                let byte = b[c]
                return byte >= 0x41 && byte <= 0x5A ? byte | 0x20 : byte
            }
        }

        func isLetter(_ c: UInt8) -> Bool { (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7A }
        func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D }
        func isNameByte(_ c: UInt8) -> Bool { isLetter(c) || (c >= 0x30 && c <= 0x39) || c == 0x2D }
        func partOfScheme(_ c: UInt8) -> Bool {
            isLetter(c) || (c >= 0x30 && c <= 0x39) || c == 0x2B || c == 0x2D || c == 0x2E   // + - .
        }

        let lt: UInt8 = 0x3C, gt: UInt8 = 0x3E, slash: UInt8 = 0x2F, bang: UInt8 = 0x21
        let question: UInt8 = 0x3F, equals: UInt8 = 0x3D, quote: UInt8 = 0x22, apostrophe: UInt8 = 0x27
        let dash: UInt8 = 0x2D, commentOpen = Array("<!--".utf8)
        let style = Array("style".utf8), href = Array("href".utf8), xlinkHref = Array("xlink:href".utf8)
        let a = Array("a".utf8), area = Array("area".utf8)
        let iframe = Array("iframe".utf8), frame = Array("frame".utf8), src = Array("src".utf8)
    }
}

/// Which letters of what the pane shows have had their pictures from the
/// web loaded, by "Load All Images" on their line (B-168), by the letter's
/// id on a page of its own and its entry's in a stack. For as long as the
/// pane shows that letter or that conversation: the next thing it shows
/// begins with none, as nothing found says Mail keeps it longer. Drawn
/// again after WebKit lost the page, it is as it was.
///
/// Out of `MessageDetailViewController` so the suite can run it.
struct RemotePictures: Equatable {

    private(set) var loaded: Set<String> = []
    /// The letters whose page or body has been built held back (`hold`),
    /// Mail's line over each that asks the web for anything.
    private(set) var held: Set<String> = []

    /// Whether the letter `id` has its pictures from the web held back:
    /// under Block All Remote Content (`blocking`), until its line's button
    /// has been tapped.
    func holdsBack(_ id: String, blocking: Bool = MessagesOptions.blockAllRemoteContent) -> Bool {
        blocking && !loaded.contains(id)
    }

    /// `holdsBack`, for a page or a body about to be built with it, and the
    /// letter kept among those `held` if so, for its line's button.
    mutating func hold(_ id: String, blocking: Bool = MessagesOptions.blockAllRemoteContent) -> Bool {
        let holding = holdsBack(id, blocking: blocking)
        if holding { held.insert(id) }
        return holding
    }

    /// Whether the button on the letter `id`'s line is to load it: by what
    /// its page or body was built with, held back and not loaded since,
    /// not by the setting now. Turned off in Settings while the letter is
    /// on screen, its line still loads it; turned on, a letter drawn
    /// before has no line, and a link of the scheme in its markup loads
    /// nothing.
    func waits(_ id: String) -> Bool {
        held.contains(id) && !loaded.contains(id)
    }

    /// Whether WebKit's list is to be on the pane's web view: under Block
    /// All Remote Content, while no letter of what it shows has been
    /// loaded. Once one has, it is off, or that letter's pictures could not
    /// come, and the other letters of a conversation are held back by
    /// their markup alone (`RemoteContent.blocked`).
    func listOn(blocking: Bool = MessagesOptions.blockAllRemoteContent) -> Bool {
        blocking && loaded.isEmpty
    }

    /// "Load All Images" on the letter `id`'s line.
    mutating func load(_ id: String) {
        loaded.insert(id)
    }
}
