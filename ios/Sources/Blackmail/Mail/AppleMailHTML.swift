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
        letter(for: draft, account: account).html
    }

    // MARK: - The whole letter, quote and all

    /// What a letter sends besides its plain text. Worked out together,
    /// because each depends on the others: which of the original's pictures
    /// go is decided by what the quote's markup still shows, and a forward's
    /// picture that goes in the quote no longer goes as a file.
    struct Letter {
        /// The HTML part, or nil when the letter goes as text.
        var html: String?
        /// The quoted original's pictures the HTML shows, each under the
        /// Content-ID it shows it by. A forward's only: a reply sends none.
        var pictures: [(contentID: String, picture: QuotedOriginal.Picture)] = []
        /// The files: the draft's own, less any that now go in the quote.
        var files: [DraftAttachment] = []
    }

    /// The most of an original's markup a quote carries: 4 MB.
    ///
    /// A newsletter is 50 to 200 kB of markup and a large one a megabyte;
    /// its pictures are on the web and stay there, so its markup is nearly
    /// all a forward of it adds, and quoted-printable adds about a tenth to
    /// that on the wire. What runs to several megabytes is markup with
    /// pictures pasted into it as `data:` addresses. Past this, the quote is
    /// the plain rendering of its words with the addresses linked, as when
    /// he has changed it, and the pasted pictures, which are by then most of
    /// the weight, stay behind. Chosen well under Gmail's 35 MB so that the
    /// original's own look is never what makes a letter too big to send.
    static let largestQuotedMarkup = 4 << 20

    /// The letter `draft` makes: its HTML, the original's pictures that the
    /// HTML shows, and the files.
    ///
    /// `taken` are Content-IDs the letter already uses, the signature's
    /// pictures', so none of the original's is renamed onto one of them.
    /// `forDraft` marks where the quote begins, with its fingerprint, for
    /// `QuotedOriginal.recovered` to find when the draft is reopened; a
    /// letter that is sent carries no such mark.
    static func letter(for draft: Draft, account: MailAccount,
                       reserving taken: Set<String> = [], forDraft: Bool = false) -> Letter {
        guard let quote = draft.quote, quote.isIntact(in: draft.body),
              let quoted = layout(of: quote.region, signature: "").quote else {
            return changedLetter(draft, account: account, forDraft: forDraft)
        }

        // Everything above the quote, less the line break that ends it,
        // which is where `layout` would have divided the body too.
        let cut = quote.region.utf8.count
            + (draft.body.utf8.count > quote.region.utf8.count ? 1 : 0)
        let above = layout(of: String(decoding: draft.body.utf8.dropLast(cut), as: UTF8.self),
                           signature: account.signature)
        let fingerprint = QuotedOriginal.fingerprint(quote.region)

        // A forward's pictures are file rows he can see and take off; one he
        // took off does not go, in the quote or anywhere.
        //
        // A reply carries none of them, as a reply has never carried the
        // original's parts (INVESTIGATIONS, "Forwarding now carries the
        // files"): every reply to a letter of photographs would send the
        // photographs back, with no row to show they were going or what
        // they weighed, and Send and Save Draft would each have to fetch
        // them first, which fails once the original has been archived
        // elsewhere and there is nothing on screen he could take off. The
        // `<img>` that showed one goes with it (`QuotedMarkup.made`); the
        // original's words, links, tables and pictures on the web stay.
        let candidates = quote.kind == .forward
            ? quote.pictures.filter { picture in draft.attachments.contains(where: picture.isSource) }
            : []
        var names: [String: String] = [:]
        var used = taken
        var renamed: [(contentID: String, picture: QuotedOriginal.Picture)] = []
        for (n, picture) in candidates.enumerated() {
            var id = "bmquote\(n + 1).\(fingerprint.prefix(12))"
            while used.contains(id) { id += "x" }
            used.insert(id)
            names[picture.contentID] = id
            renamed.append((id, picture))
        }

        var inner = ""
        var shown = Set<String>()
        if let markup = quote.html, markup.utf8.count <= largestQuotedMarkup {
            (inner, shown) = QuotedMarkup.made(markup, pictures: names)
        }
        // The words he saw, their addresses linked, when there is no markup
        // to carry, when it is past the ceiling, or when nothing of it shows
        // once it is safe: a text/html part with nothing in it, or one made
        // of nothing the pass keeps. An empty quote under the attribution,
        // where the composer showed him words, would not be what he saw.
        if !QuotedMarkup.showsAnything(inner) {
            inner = paragraphs(quoted.body, firstLineBare: true, linked: true)
            shown = []
        }
        let pictures = renamed.filter { shown.contains($0.contentID) }
        let files = draft.attachments.filter { row in
            !pictures.contains { $0.picture.isSource(of: row) }
        }

        var out = documentOpen + head(above, signatureHTML: account.signatureHTML)
        if let own = above.quote {
            out += quoteBlock(own, inner: paragraphs(own.body, firstLineBare: true), marker: nil)
        }
        out += quoteBlock(quoted, inner: inner, marker: forDraft ? fingerprint : nil)
        return Letter(html: out + documentClose, pictures: pictures, files: files)
    }

    /// The letter when he has changed the quote, or there is none to keep.
    ///
    /// Exactly the HTML this app made before the original's markup was
    /// carried, from the body as it stands, so the HTML holds only what the
    /// plain text holds. For a letter that did quote something, its
    /// addresses are made links, and a draft is marked so the same rendering
    /// is taken up again when it is reopened. The files go as files.
    private static func changedLetter(_ draft: Draft, account: MailAccount,
                                      forDraft: Bool) -> Letter {
        guard isNeeded(body: draft.body, signature: account.signature,
                       signatureHTML: account.signatureHTML) else {
            return Letter(html: nil, files: draft.attachments)
        }
        let layout = layout(of: draft.body, signature: account.signature)
        let quoting = draft.quote != nil
        var out = documentOpen + head(layout, signatureHTML: account.signatureHTML)
        if let quote = layout.quote {
            let marker = forDraft && quoting
                ? quoteRegion(of: draft.body).map { QuotedOriginal.fingerprint($0.region) }
                : nil
            out += quoteBlock(quote, inner: paragraphs(quote.body, firstLineBare: true,
                                                       linked: quoting),
                              marker: marker)
        }
        return Letter(html: out + documentClose, files: draft.attachments)
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
        /// A forward: the `From:`/`Date:`/`To:`/`Cc:`/`Subject:` block, then
        /// the original. Held as pairs so the labels can be bolded the way
        /// Mail bolds them.
        case forward(fields: [(String, String)], body: String)

        /// The original's words, without the attribution or header block.
        var body: String {
            switch self {
            case let .reply(_, body), let .forward(_, body): return body
            }
        }

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

    /// Where the quote begins in a body and everything from there on, found
    /// as `layout` finds it; nil when there is none.
    static func quoteRegion(of body: String) -> (kind: QuotedOriginal.Kind, region: String)? {
        let lines = body.components(separatedBy: "\n")
        if let start = forwardStart(lines) {
            return (.forward, lines[start...].joined(separator: "\n"))
        }
        if let start = replyStart(lines) {
            return (.reply, lines[start...].joined(separator: "\n"))
        }
        return nil
    }

    private static func parseForward(_ lines: [String], from start: Int) -> Quote {
        let labels = ["From:", "Date:", "To:", "Cc:", "Subject:"]
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
        var out = documentOpen + head(layout, signatureHTML: signatureHTML)
        if let quote = layout.quote {
            out += quoteBlock(quote, inner: paragraphs(quote.body, firstLineBare: true),
                              marker: nil)
        }
        return out + documentClose
    }

    /// What he typed, then his signature.
    private static func head(_ layout: Layout, signatureHTML: String) -> String {
        var out = paragraphs(layout.typed, firstLineBare: true)

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
        return out
    }

    /// The quote: the attribution or the forwarded-message header, then
    /// `inner`, the original, in Mail's cite blockquote.
    ///
    /// The blockquotes are bare, as his device writes them. The blue bar a
    /// reader of Mail sees is drawn by Mail for `type="cite"`, not sent: no
    /// style is written on them, so each reader's client draws its own
    /// quote, as it does for his letters from Mail.
    ///
    /// `marker`, in a saved draft only, is the fingerprint of the plain
    /// quote this was made for, written as a comment just before the
    /// original. A comment, because it is the one thing no reader shows and
    /// `QuotedMarkup` takes out of any original, so the mark can only ever
    /// be this app's own and only this one.
    private static func quoteBlock(_ quote: Quote, inner: String, marker: String?) -> String {
        var out = ""
        switch quote {
        case let .reply(attribution, _):
            // Two blockquotes, siblings, the attribution in its own — which
            // looks wrong written down and is exactly what his device
            // produces. Reproduced rather than tidied, because his
            // correspondents' clients already collapse this shape.
            out += "<div dir=\"ltr\"><br><blockquote type=\"cite\">"
                + escape(attribution) + "<br><br></blockquote></div>"

        case let .forward(fields, _):
            out += "<div dir=\"ltr\"><br><br><br>Begin forwarded message:<br><br></div>"
            out += "<blockquote type=\"cite\"><div dir=\"ltr\">"
            for (label, value) in fields {
                // Mail bolds the label, and bolds the subject's VALUE too.
                let shown = label == "Subject:"
                    ? "<b>" + escape(value) + "</b>" : escape(value)
                out += "<b>" + label + "</b> " + shown + "<br>"
            }
            out += "<br></div></blockquote>"
        }
        if let marker { out += quoteMarkOpen + marker + "-->" }
        return out + quoteOpen + inner + quoteClose
    }

    private static let quoteOpen = "<blockquote type=\"cite\"><div dir=\"ltr\">"
    private static let quoteClose = "</div></blockquote>"
    private static let quoteMarkOpen = "<!--bm-quote:"

    /// The quote a saved draft's HTML carries: the fingerprint it was
    /// marked with and the original's markup as stored. Nil unless the HTML
    /// is this app's own, marked, and ends with the quote as this app ends
    /// it.
    static func savedQuote(in html: String) -> (fingerprint: String, markup: String)? {
        guard let mark = html.range(of: quoteMarkOpen, options: .backwards) else { return nil }
        let after = html[mark.upperBound...]
        guard let close = after.range(of: "-->") else { return nil }
        let fingerprint = String(after[after.startIndex..<close.lowerBound])
        let rest = after[close.upperBound...].utf8
        let open = quoteOpen.utf8
        let end = (quoteClose + documentClose).utf8
        guard rest.starts(with: open), rest.count >= open.count + end.count,
              rest.suffix(end.count).elementsEqual(end) else { return nil }
        let markup = String(decoding: rest.dropFirst(open.count).dropLast(end.count),
                            as: UTF8.self)
        return (fingerprint, markup)
    }

    /// Plain lines as Mail lays them out: the first bare, the rest each in a
    /// `<div>`, and an empty line as a `<div><br></div>`. `linked` makes the
    /// web addresses in them links (`QuotedMarkup.linked`).
    static func paragraphs(_ text: String, firstLineBare: Bool, linked: Bool = false) -> String {
        guard !text.isEmpty else { return "" }
        var out = ""
        for (i, line) in text.components(separatedBy: "\n").enumerated() {
            let content = line.isEmpty ? "<br>" : (linked ? escapeLinking(line) : escape(line))
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
        keepingTrailingSpace(text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;"))
    }

    /// `escape`, with the web addresses in the line made links.
    static func escapeLinking(_ text: String) -> String {
        keepingTrailingSpace(QuotedMarkup.linked(text))
    }

    /// A run of spaces collapses to one in HTML and a trailing one vanishes,
    /// so the deliberate space at the end of a line — which is how people
    /// separate a sign-off from what follows — has to be written as a
    /// non-breaking one. Mail does the same.
    private static func keepingTrailingSpace(_ html: String) -> String {
        html.hasSuffix(" ") ? String(html.dropLast()) + "&nbsp;" : html
    }
}
