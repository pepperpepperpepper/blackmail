import Foundation

/// One thing handed to the share extension, as it arrived.
enum SharedItem: Equatable {
    /// A page or a video: its address, and the title the sharing app gave
    /// it, which Safari and YouTube both give.
    case link(URL, title: String?)
    /// Words, from Notes or a selection.
    case text(String)
    /// A photograph or a document, already staged on this device
    /// (`ShareItems.Staging`), so what the letter carries is a pointer and
    /// the bytes are read only at Send. A photograph arrives here as Apple
    /// Mail sends it: a JPEG as its own bytes under its file's name, its
    /// metadata replaced; a GIF or PNG as the file it is; any other, or one
    /// too large for the letter, made a JPEG of at most 4096 px
    /// (`SharedPhoto.way`).
    case file(URL, filename: String, mimeType: String, size: Int64)
}

/// The letter a share starts as, in the shape Mail's share sheet gives it.
///
/// Read off his own mail rather than guessed: about half of everything he
/// sends is a YouTube or Wikipedia link shared this way, to a second
/// address of his own. Mail makes the page's title the subject and puts the
/// address alone in the body, above his signature, with nothing typed.
///
/// One deliberate difference. Mail writes the address into its HTML as
/// bare text, so a reader that does not find links for itself shows it as
/// words that cannot be tapped, and this app's own reading pane is such a
/// reader. Here the HTML twin carries it as a real link (`html`).
enum ShareLetter {

    /// The letter for `items`, with `signature` under it as the app adds it
    /// to a new letter, and each file attached where it was staged.
    ///
    /// The subject is the first title offered, on one line. A text that is
    /// only a link's address again, which some apps send beside the link,
    /// is not written twice, and a link whose address is already in a text
    /// is not added again.
    static func draft(from items: [SharedItem], signature: String) -> Draft {
        var draft = Draft()
        var lines: [String] = []
        let linkAddresses = Set(items.compactMap { item -> String? in
            if case let .link(url, _) = item { return url.absoluteString } else { return nil }
        })
        // The texts that will be written, which is every one but a bare
        // repeat of a link's address.
        let texts = items.compactMap { item -> String? in
            guard case let .text(t) = item else { return nil }
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || linkAddresses.contains(trimmed) ? nil : trimmed
        }

        for item in items {
            switch item {
            case let .link(url, title):
                if draft.subject.isEmpty, let title = oneLine(title), title != url.absoluteString {
                    draft.subject = title
                }
                let address = url.absoluteString
                guard !lines.contains(address),
                      !texts.contains(where: { $0.contains(address) }) else { continue }
                lines.append(address)
            case let .text(text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard texts.contains(trimmed), !lines.contains(trimmed) else { continue }
                lines.append(trimmed)
            case let .file(url, filename, mimeType, size):
                draft.attachments.append(DraftAttachment(source: .localFile(url),
                                                         filename: filename,
                                                         mimeType: mimeType,
                                                         size: size))
            }
        }

        let typed = lines.joined(separator: "\n")
        draft.body = typed.isEmpty
            ? Draft.blank(signature: signature).body
            : typed + Draft.signatureBlock(signature)
        return draft
    }

    // MARK: - The sheet's body

    /// The body as the share sheet shows it: an empty first line above
    /// what was shared, where the caret starts and his words go, as in
    /// Mail's share sheet (B-069). With the caret at the top of a body that
    /// began with the link, what he typed ran into the address on its
    /// line: "Have a lookhttps://…". A body that already begins with an
    /// empty line, the blank letter a photo comes in, is shown as it is.
    static func shown(_ body: String) -> String {
        body.hasPrefix("\n") ? body : "\n" + body
    }

    /// The letter's body from what the sheet shows, `began` being the body
    /// the share began as: the empty first line `shown` put there goes if
    /// he left it empty, so a share sent as it began goes as Mail sends it,
    /// the address alone above his signature, and Cancel asks nothing of
    /// it. Words he wrote on that line stay, on a line of their own above
    /// what was shared.
    static func written(_ shown: String, began: String) -> String {
        guard !began.hasPrefix("\n"), shown.hasPrefix("\n") else { return shown }
        return String(shown.dropFirst())
    }

    /// The HTML twin: Mail's envelope around the letter as the app would
    /// send it (`AppleMailHTML`), with every web address he has in the
    /// typed part made a link. Always present when there is one, since a
    /// link is exactly the rich element Mail sends HTML for; otherwise
    /// whatever the app would send for the same letter.
    static func html(for draft: Draft, account: MailAccount) -> String? {
        let layout = AppleMailHTML.layout(of: draft.body, signature: account.signature)
        guard firstLink(in: layout.typed) != nil else {
            return AppleMailHTML.part(for: draft, account: account)
        }
        let document = AppleMailHTML.document(body: draft.body, signature: account.signature,
                                              signatureHTML: account.signatureHTML)
        // Only the part he typed, which the envelope writes first: a link in
        // the signature's own markup is his signature's business.
        let end = document.range(of: AppleMailHTML.signatureAnchor)?.lowerBound
            ?? document.endIndex
        return linked(String(document[..<end])) + document[end...]
    }

    /// `html`'s escaped text with each web address wrapped in an anchor.
    ///
    /// The addresses are found in the escaped text, where `&` is already
    /// `&amp;` and so already right for the `href`. A link ends at a space,
    /// a tag, a quote or any other entity: the `&lt;` and `&gt;` of an
    /// address written in angle brackets, the usual way in plain text, and
    /// the `&nbsp;` the envelope writes for a trailing space. A full stop,
    /// comma or closing bracket after it belongs to the sentence, as every
    /// linkifier treats them.
    static func linked(_ escaped: String) -> String {
        guard let pattern = try? NSRegularExpression(
            pattern: #"https?://(?:&amp;|[^\s<>"&])+"#, options: [.caseInsensitive])
        else { return escaped }
        let whole = NSRange(escaped.startIndex..., in: escaped)
        var out = ""
        var last = escaped.startIndex
        for match in pattern.matches(in: escaped, range: whole) {
            guard let range = Range(match.range, in: escaped) else { continue }
            var link = escaped[range]
            // A closing bracket is kept when the link opened one, as
            // Wikipedia's do: `…/wiki/Mercury_(planet)`. An address that
            // ends in `&` keeps the whole of its `&amp;`.
            while let c = link.last, !link.hasSuffix("&amp;") {
                let unopened = c == ")"
                    && link.filter { $0 == ")" }.count > link.filter { $0 == "(" }.count
                guard ".,;:!?".contains(c) || unopened else { break }
                link = link.dropLast()
            }
            out += escaped[last..<range.lowerBound]
            out += "<a href=\"\(link)\">\(link)</a>"
            last = link.endIndex
        }
        return out + escaped[last...]
    }

    private static func firstLink(in text: String) -> Range<String.Index>? {
        text.range(of: #"https?://\S"#, options: [.regularExpression, .caseInsensitive])
    }

    /// A title on one line, or nil when there is nothing in it.
    private static func oneLine(_ title: String?) -> String? {
        guard let title else { return nil }
        let line = title.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return line.isEmpty ? nil : line
    }
}
