import Foundation

/// The HTML half of a letter, in Apple Mail's own shape.
///
/// Mail on iPad has no plain-text setting — the preference macOS has does not
/// exist on iOS — so it chooses the wire format from the content: rich
/// element present, and the letter goes out as HTML; nothing rich in it, and
/// it goes out as text. Blackmail composed plain text and only plain text,
/// which is why Sam's signature arrived as a flat transcription with the
/// photograph, the logo and the bold name gone, and why his replies handed
/// people's own words back as unformatted text.
///
/// What this is NOT is a rich-text editor. Across 715 of his sent messages
/// the region he actually typed contains only `div`, `br` and text: no bold,
/// no italic, no colour, no lists, no font sizes, not once in three years.
/// What pushes his mail into HTML is never his typing — it is his signature,
/// and the originals he quotes. So the gap was an envelope, not an editing
/// surface, and this file is the envelope.
///
/// Every string below was read off his own device's output rather than
/// guessed, including the two details that look like mistakes: the `<meta>`
/// is the only tag in the `<head>` and there is no DOCTYPE, and the first
/// line of typed text sits bare in the `<body>` while every later line is
/// wrapped in a `<div>`.
///
/// Pure, and out here rather than in the composer, so the test suite on
/// Linux can reach it.
enum AppleMailHTML {

    // MARK: - The fixed furniture

    /// Byte-exact, and the byte-exactness is the point. 458 of 499 of his
    /// HTML bodies open with precisely this; the remaining 40 open with
    /// `<html class="apple-mail-supports-explicit-dark-mode">`, which tracks
    /// the appearance setting at the moment of composing rather than an OS
    /// version, so both forms are live and either is honest.
    static let documentOpen = "<html><head><meta http-equiv=\"content-type\" "
        + "content=\"text/html; charset=utf-8\"></head><body dir=\"auto\">"
    static let documentClose = "</body></html>"

    /// What separates a letter from its signature. Mail marks the break with
    /// an id rather than a class or a comment, and some clients (Mail among
    /// them) use it to find the signature when trimming a reply.
    static let signatureAnchor = "<br id=\"lineBreakAtBeginningOfSignature\">"

    /// The signature travels on its own sheet of white paper.
    ///
    /// **What his signature actually declares**, read out of the stored
    /// markup rather than assumed: `background-color: rgba(255, 255, 255, 0)`
    /// — white at zero alpha, i.e. fully transparent — table borders in
    /// `rgb(255, 255, 255)`, and **no text colour at all**. (There is a
    /// `caret-color: rgb(0, 0, 0)` in there, which paints nothing and is
    /// easy to misread as a text colour. `#fff` appears zero times.)
    ///
    /// So every word of it is whatever colour the reading client happens to
    /// inherit. On a white page it is black on white and has always looked
    /// right. In a dark-mode client it comes out white-on-dark with the
    /// links left at their default dark blue — measured at roughly 2:1
    /// against a near-black background, which is below any legibility
    /// threshold — the organisation logo, a dark PNG on transparency, reduced to a
    /// black smudge, and the white borders turned into a bright grid around
    /// it. Dark mode is the default on a great many phones now. This is not
    /// a corner case, it is most of the people he writes to, and neither
    /// they nor he would ever think to mention it.
    ///
    /// Hence a white sheet, declared by us, that the block always sits on.
    static let signatureOpen = "<div class=\"bm-signature\" style=\""
        + "background-color: #ffffff; color: #000000; color-scheme: light;\">"
    static let signatureClose = "</div>"

    /// The declarations a `<table>` inside the signature needs of its own.
    ///
    /// The wrapper above is **not sufficient by itself**, and the reason is
    /// a twenty-year-old quirk rather than anything to do with mail. A
    /// document with no DOCTYPE renders in quirks mode, and in quirks mode a
    /// table does not inherit `color` from its ancestors — it falls back to
    /// the initial colour. Apple Mail's envelope, which this file reproduces
    /// byte for byte, has **no DOCTYPE**. His signature is a `<table>`. So
    /// the wrapper's `color: #000000` reaches the div around the table and
    /// stops dead at the first `<td>`, leaving white text on the white sheet
    /// we just laid down — a signature that is not merely hard to read but
    /// entirely gone.
    ///
    /// Verified by rendering the real signature four ways in Chromium: the
    /// wrapper alone works in standards mode and fails in quirks mode; the
    /// wrapper plus these table declarations works in both. A `<style>`
    /// block also works, and was rejected — scoping it to the signature
    /// needs `.bm-signature * { color: … !important }`, which flattens his
    /// links to black as well, and many clients strip `<style>` anyway.
    static let signatureTableStyle = "color: rgb(0, 0, 0); "
        + "background-color: rgb(255, 255, 255); "

    /// Adds `signatureTableStyle` to every `<table>` in the signature,
    /// touching nothing else.
    ///
    /// Additive by construction: it prepends to an existing `style` or adds
    /// one, and never removes or rewrites a declaration he already has —
    /// later declarations in the same attribute win, so anything his markup
    /// sets for itself still does. Rewriting somebody's signature is how the
    /// logo and the confidentiality notice get quietly mangled, and this is
    /// as small an intervention as the quirk allows.
    static func onWhitePaper(_ html: String) -> String {
        var out = ""
        var rest = Substring(html)
        while let open = rest.range(of: "<table", options: .caseInsensitive) {
            guard let close = rest.range(of: ">", range: open.upperBound..<rest.endIndex) else {
                break
            }
            let tag = rest[open.lowerBound..<close.upperBound]
            out += rest[rest.startIndex..<open.lowerBound]
            if let style = tag.range(of: "style=\"", options: .caseInsensitive) {
                out += tag[tag.startIndex..<style.upperBound]
                    + signatureTableStyle
                    + tag[style.upperBound..<tag.endIndex]
            } else {
                out += tag[tag.startIndex..<tag.index(before: tag.endIndex)]
                    + " style=\"" + signatureTableStyle + "\">"
            }
            rest = rest[close.upperBound...]
        }
        return out + rest
    }

    // MARK: - Whether a letter needs one at all

    /// True when Mail would send this as HTML.
    ///
    /// Keyed on any rich element being present, NOT on the signature alone.
    /// That distinction was checked and it matters: a signature always
    /// forces HTML, but 19 of his 331 HTML messages carry no signature, and
    /// 18 of those are replies and forwards. Keying on the signature would
    /// drop the HTML from exactly the letters where the quoted original is
    /// the thing that needed it.
    ///
    /// The letters with nothing rich in them stay text/plain, which is a
    /// quarter of his traffic and is also what Mail does. Sending HTML for
    /// a one-line note would be a deviation in the other direction.
    static func isNeeded(body: String, signature: String, signatureHTML: String) -> Bool {
        let layout = layout(of: body, signature: signature)
        if layout.quote != nil { return true }
        return !signatureHTML.isEmpty && !layout.signature.isEmpty
    }

    /// The HTML part for a letter, or nil when it should go out as text.
    static func part(for draft: Draft, account: MailAccount) -> String? {
        guard isNeeded(body: draft.body, signature: account.signature,
                       signatureHTML: account.signatureHTML) else { return nil }
        return document(body: draft.body, signature: account.signature,
                        signatureHTML: account.signatureHTML)
    }

    // MARK: - Reading the plain body back

    /// The three regions of a letter: what he typed, his signature, and
    /// whatever he is quoting.
    struct Layout: Equatable {
        var typed: String = ""
        var signature: String = ""
        var quote: Quote?
    }

    enum Quote: Equatable {
        /// A reply: one attribution line, then the original.
        case reply(attribution: String, body: String)
        /// A forward: the `From:`/`Date:`/`To:`/`Subject:` block, then the
        /// original. Held as pairs so the labels can be bolded the way Mail
        /// bolds them.
        case forward(fields: [(String, String)], body: String)

        static func == (a: Quote, b: Quote) -> Bool {
            switch (a, b) {
            case let (.reply(x, p), .reply(y, q)): return x == y && p == q
            case let (.forward(f, p), .forward(g, q)):
                return p == q && f.count == g.count
                    && zip(f, g).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
            default: return false
            }
        }
    }

    /// Splits the composed plain text back into its parts.
    ///
    /// Reading the finished body rather than carrying the structure on the
    /// `Draft` is deliberate, and it is what keeps drafts safe. A draft is
    /// saved to the server as a real message and reopened by parsing that
    /// message, so any structure held beside the text would survive the
    /// first save and be gone from the second — the letter would quietly
    /// change shape the first time he was interrupted and came back to it.
    /// Deriving it from the text means a reopened draft and a fresh one go
    /// through exactly the same path.
    ///
    /// Safe on text this app did not write. Nothing here can fail; the worst
    /// case is that a marker is missing and the whole body is treated as
    /// typed text, which still produces a correct letter.
    static func layout(of body: String, signature: String) -> Layout {
        let lines = body.components(separatedBy: "\n")

        var quote: Quote?
        var headEnd = lines.count

        if let start = forwardStart(lines) {
            quote = parseForward(lines, from: start)
            headEnd = start
        } else if let start = replyStart(lines) {
            let attribution = lines[start]
            let quoted = lines[(start + 1)...].map { line -> String in
                // "> " on an empty quoted line is written as "> " with the
                // space, but a relay may strip the trailing space, so both
                // spellings have to unwrap.
                if line.hasPrefix("> ") { return String(line.dropFirst(2)) }
                if line == ">" { return "" }
                return line
            }
            quote = .reply(attribution: attribution, body: quoted.joined(separator: "\n"))
            headEnd = start
        }

        var head = lines[..<headEnd].joined(separator: "\n")
        var found = ""
        let trimmedSignature = signature.trimmingCharacters(in: .whitespacesAndNewlines)
        // The LAST occurrence: if he has quoted a letter of his own, his
        // signature appears inside the quote too, and the one that belongs
        // to this letter is the one nearest the bottom of the head region.
        if !trimmedSignature.isEmpty, let at = head.range(of: trimmedSignature,
                                                          options: .backwards) {
            found = trimmedSignature
            head = String(head[..<at.lowerBound])
        }

        return Layout(typed: trimmedTrailingBlankLines(head),
                      signature: found, quote: quote)
    }

    /// The line where a reply's quote begins.
    ///
    /// An attribution line ALONE is not enough to go on — he could type
    /// "On Tuesday she wrote:" in a letter of his own — so the following
    /// line has to actually be quoted for this to fire. Guessing wrong here
    /// would put his own sentence inside a quote block.
    private static func replyStart(_ lines: [String]) -> Int? {
        for (i, line) in lines.enumerated()
        where line.hasPrefix("On ") && line.hasSuffix("wrote:") {
            let next = i + 1 < lines.count ? lines[i + 1] : ""
            if next.hasPrefix(">") { return i }
        }
        return nil
    }

    private static func forwardStart(_ lines: [String]) -> Int? {
        lines.firstIndex(of: "Begin forwarded message:")
    }

    private static func parseForward(_ lines: [String], from start: Int) -> Quote {
        let labels = ["From:", "Date:", "To:", "Subject:"]
        var fields: [(String, String)] = []
        var i = start + 1

        while i < lines.count {
            let line = lines[i]
            if line.isEmpty, fields.isEmpty { i += 1; continue }
            guard let label = labels.first(where: { line.hasPrefix($0) }) else { break }
            fields.append((label, String(line.dropFirst(label.count))
                                    .trimmingCharacters(in: .whitespaces)))
            i += 1
        }
        // One blank line separates the header block from the message.
        if i < lines.count, lines[i].isEmpty { i += 1 }
        return .forward(fields: fields, body: lines[i...].joined(separator: "\n"))
    }

    private static func trimmedTrailingBlankLines(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Writing it out

    /// The whole document.
    static func document(body: String, signature: String, signatureHTML: String) -> String {
        let layout = layout(of: body, signature: signature)
        var out = documentOpen

        out += paragraphs(layout.typed, firstLineBare: true)

        if !layout.signature.isEmpty {
            out += signatureAnchor
            // Both branches get the white sheet, not just the rich one. A
            // signature typed as plain text has no colours of its own at
            // all, so it inherits whatever the reading client decided — the
            // same disappearing act by a different route.
            out += signatureOpen
            if signatureHTML.isEmpty {
                out += "<div dir=\"ltr\">" + paragraphs(layout.signature,
                                                        firstLineBare: true) + "</div>"
            } else {
                out += onWhitePaper(signatureHTML)
            }
            out += signatureClose
        }

        switch layout.quote {
        case let .reply(attribution, quoted):
            // Two blockquotes, siblings, the attribution in its own — which
            // looks wrong written down and is exactly what his device
            // produces. Reproduced rather than tidied, because his
            // correspondents' clients already collapse this shape.
            out += "<div dir=\"ltr\"><br><blockquote type=\"cite\">"
                + escape(attribution) + "<br><br></blockquote></div>"
            out += "<blockquote type=\"cite\"><div dir=\"ltr\">"
                + paragraphs(quoted, firstLineBare: true) + "</div></blockquote>"

        case let .forward(fields, quoted):
            out += "<div dir=\"ltr\"><br><br><br>Begin forwarded message:<br><br></div>"
            out += "<blockquote type=\"cite\"><div dir=\"ltr\">"
            for (label, value) in fields {
                // Mail bolds the label, and bolds the subject's VALUE too.
                let shown = label == "Subject:"
                    ? "<b>" + escape(value) + "</b>" : escape(value)
                out += "<b>" + label + "</b> " + shown + "<br>"
            }
            out += "<br></div></blockquote>"
            out += "<blockquote type=\"cite\"><div dir=\"ltr\">"
                + paragraphs(quoted, firstLineBare: true) + "</div></blockquote>"

        case nil:
            break
        }

        return out + documentClose
    }

    /// Plain lines as Mail lays them out: the first bare, the rest each in a
    /// `<div>`, and an empty line as a `<div><br></div>`.
    static func paragraphs(_ text: String, firstLineBare: Bool) -> String {
        guard !text.isEmpty else { return "" }
        var out = ""
        for (i, line) in text.components(separatedBy: "\n").enumerated() {
            let content = line.isEmpty ? "<br>" : escape(line)
            if i == 0 && firstLineBare {
                out += content
            } else {
                out += "<div>" + content + "</div>"
            }
        }
        return out
    }

    /// The three characters that would otherwise be markup, plus the trailing
    /// space that HTML would collapse away.
    ///
    /// `&` first, or the ampersands introduced by the other two get escaped
    /// a second time and the reader sees `&amp;lt;`.
    static func escape(_ text: String) -> String {
        var out = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        // A run of spaces collapses to one in HTML and a trailing one
        // vanishes, so the deliberate space at the end of a line — which is
        // how people separate a sign-off from what follows — has to be
        // written as a non-breaking one. Mail does the same.
        if out.hasSuffix(" ") {
            out = String(out.dropLast()) + "&nbsp;"
        }
        return out
    }
}
