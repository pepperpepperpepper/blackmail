import Foundation

/// A plain letter's quotes drawn as Mail draws them (B-147): each run of
/// lines begun with `>` a quote, Mail's `<blockquote type="cite">`, one
/// inside another for each `>` more, and the marks themselves not shown,
/// so the pane's bars (`QuoteBars`) are beside them, as beside an HTML
/// letter's.
///
/// What Mail does, read from iOS 18.6's Message framework (its code, not
/// seen on a screen): it makes a plain letter HTML before it draws it
/// (`mf_convertFromFlowedText`), each level of `>` a `BLOCKQUOTE` of
/// `type=cite`, which its style sheet gives its bar and colour, the marks
/// taken out. Until B-147 the pane drew the lines as they came, marks and
/// all, with no bar (B-101: "plain quotes have no bar").
///
/// **How deep.** In flowed text (RFC 3676, `Message.textIsFlowed`), the
/// unbroken run of `>` the line begins with: `>> ` is two, and `> > ` one,
/// its words `> …`. In any other, the marks may have spaces between them,
/// as a client that puts "> " before a line already quoted writes them:
/// `> > ` is two, as `>> ` is. One space after the last mark goes with the
/// marks; any more are the words'.
///
/// **Not a quote.** A line begun `>From `, which is how a mail store keeps
/// a line its sender began "From " (mbox), is drawn as it came, as before,
/// its mark and all. So is a line whose first character is not `>`, a
/// space before it included.
///
/// **As it was.** The words are escaped as the page has always escaped
/// them, and links are made where they were made (`TextLinks`), on a
/// quoted line too: a quote's markup goes in at the start of a line, where
/// no link can be. A letter with no quote comes out byte for byte as it
/// did. The lines keep their breaks, which the page keeps (`white-space:
/// pre-wrap`): a quote begins at the start of its first line and ends after
/// the break of its last.
///
/// **Bounded.** A quote deeper than `deepest` is drawn that deep, the
/// marks past it shown as words. A letter whose quotes would add more
/// markup than `markupAllowed` gives it is drawn as before, its marks as
/// they came: a stranger's letter of nothing but `>` lines going in and
/// out could otherwise make a page many times its own size.
enum PlainQuotes {

    /// The deepest quote drawn, a bar for each level, 6 px in each.
    static let deepest = 32

    /// A quote, as Mail makes one of a plain letter's, which the pane's
    /// rules find as they find Mail's in an HTML letter (`QuoteBars.quote`).
    static let open = "<blockquote type=\"cite\">"
    static let close = "</blockquote>"

    /// The most markup the quotes of a letter of `size` bytes may add: as
    /// much again as the letter, or 64 KiB for a short one.
    static func markupAllowed(_ size: Int) -> Int {
        max(size, 64 * 1_024)
    }

    private static let gt: UInt8 = 0x3E, space: UInt8 = 0x20, lf: UInt8 = 0x0A
    private static let mbox = Array(">From ".utf8)

    /// The quote of the line from `start` of `bytes` to `end`, its break
    /// or the text's end: how deep it is, nought for a line that is no
    /// quote, and where its words begin, past its marks.
    static func quote(_ bytes: [UInt8], from start: Int, to end: Int,
                      flowed: Bool) -> (depth: Int, words: Int) {
        guard start < end, bytes[start] == gt,
              !(end - start >= mbox.count && bytes[start..<start + mbox.count].elementsEqual(mbox))
        else { return (0, start) }
        var depth = 0
        var p = start
        while p < end, bytes[p] == gt, depth < deepest {
            depth += 1
            p += 1
            if flowed { continue }
            // Spaces, then another mark: the same run.
            var q = p
            while q < end, bytes[q] == space { q += 1 }
            guard q < end, bytes[q] == gt, depth < deepest else { break }
            p = q
        }
        if p < end, bytes[p] == space { p += 1 }
        return (depth, p)
    }

    /// `text` written into a page as `TextLinks.plain` writes it, escaped
    /// as `escaping` says and its links made, with each quote a
    /// blockquote and its marks taken out; as `TextLinks.plain` alone
    /// writes it when it has no quote, or when its quotes would add more
    /// than `markupAllowed`.
    static func html(_ text: Substring, flowed: Bool, escaping: TextLinks.Escaping) -> String {
        let bytes = Array(text.utf8)
        let allowed = markupAllowed(bytes.count)
        var words: [UInt8] = []
        words.reserveCapacity(bytes.count)
        var tags: [TextLinks.Tag] = []
        var markup = 0
        var depth = 0
        // The quotes opened or closed from `depth` to `level`, before the
        // words that come next.
        func moveTo(_ level: Int) {
            guard level != depth else { return }
            let html = level > depth
                ? String(repeating: open, count: level - depth)
                : String(repeating: close, count: depth - level)
            markup += html.utf8.count
            tags.append(.init(at: words.count, html: html))
            depth = level
        }
        // One line at a time: its quote, then its words past its marks,
        // and its break.
        var start = 0
        while start < bytes.count {
            var end = start
            while end < bytes.count, bytes[end] != lf { end += 1 }
            let line = quote(bytes, from: start, to: end, flowed: flowed)
            moveTo(line.depth)
            guard markup <= allowed else { return TextLinks.plain(text, escaping: escaping) }
            let next = min(end + 1, bytes.count)
            words.append(contentsOf: bytes[line.words..<next])
            start = next
        }
        moveTo(0)
        guard !tags.isEmpty, markup <= allowed else { return TextLinks.plain(text, escaping: escaping) }
        return TextLinks.plain(words, escaping: escaping, tags: tags)
    }
}
