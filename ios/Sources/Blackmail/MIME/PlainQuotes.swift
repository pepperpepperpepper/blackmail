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
/// **Not a quote.** A line whose first character is not `>`, a space
/// before it included, is drawn as it came.
///
/// **`>From `** is a quote, as any line begun `>` is (B-172). A mail store
/// writes `>From ` for a line its sender began "From " (mbox), and until
/// B-172 such a line was drawn as it came, its mark and all, a choice of
/// the 26 Oct build plan's; Mail draws it as a quote of one level, its
/// mark not shown: "From the store's line." beside the bar, in the bar's
/// colour, seen on the test iPad, Mail 16.5.1, 2026-10-27 (round
/// r6-i-compare, C-11c), and on paper the same (C-17c).
///
/// **The line before a quote.** A line that is no quote and ends
/// "wrote:", directly above a quote, is drawn inside it, as its first
/// line at the first level (`isAttribution`, B-172): "On Monday, Carlo
/// wrote:" beside the bar of the quote under it, in its colour, as Mail
/// draws it (C-11c, C-17c). Until B-172 it was drawn outside, as the
/// letter's own words. Only such a line, as only that was seen: whether
/// Mail takes in any line above a quote, or one ending ":" alone, or
/// with a blank line between, was not seen, and they are as before.
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
    private static let tab: UInt8 = 0x09, cr: UInt8 = 0x0D
    private static let wrote = Array("wrote:".utf8)

    /// Whether the line from `start` of `bytes` to `end` ends "wrote:",
    /// spaces, tabs and a carriage return after it aside: the line Mail
    /// draws inside the quote directly under it (B-172), and leaves out of
    /// a row's preview with the quote (`PreviewText.fromPlainText`). Only
    /// for a line that is no quote; the caller asks that.
    static func isAttribution(_ bytes: [UInt8], from start: Int, to end: Int) -> Bool {
        var last = end
        while last > start, bytes[last - 1] == space || bytes[last - 1] == tab || bytes[last - 1] == cr {
            last -= 1
        }
        return last - start >= wrote.count && bytes[(last - wrote.count)..<last].elementsEqual(wrote)
    }

    /// The quote of the line from `start` of `bytes` to `end`, its break
    /// or the text's end: how deep it is, nought for a line that is no
    /// quote, and where its words begin, past its marks.
    static func quote(_ bytes: [UInt8], from start: Int, to end: Int,
                      flowed: Bool) -> (depth: Int, words: Int) {
        guard start < end, bytes[start] == gt else { return (0, start) }
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
        // and its break. A line ending "wrote:" directly above a quote
        // goes in at the quote's first level (B-172).
        var start = 0
        while start < bytes.count {
            var end = start
            while end < bytes.count, bytes[end] != lf { end += 1 }
            var line = quote(bytes, from: start, to: end, flowed: flowed)
            // The next line is a quote when its first character is a mark.
            if line.depth == 0, end + 1 < bytes.count, bytes[end + 1] == gt,
               isAttribution(bytes, from: start, to: end) {
                line.depth = 1
            }
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
