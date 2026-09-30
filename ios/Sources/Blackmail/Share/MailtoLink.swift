import Foundation

/// A `mailto:` link, read into the letter it asks for (RFC 6068).
///
/// Tapped in a letter, such a link used to ask "Open this link?" and then
/// hand him to Apple Mail, under Apple Mail's account, so the letter never
/// appeared in this app's Sent (B-036). Now it opens this app's composer.
///
/// Read by hand rather than through `URLComponents`, which decodes `+` in a
/// query as a space: RFC 6068 says `+` is a plus, and an address such as
/// `sam+news@example.com` must survive the trip.
enum MailtoLink {

    struct Fields: Equatable {
        var to: [String] = []
        var cc: [String] = []
        var bcc: [String] = []
        var subject = ""
        var body = ""
    }

    /// The link's fields, or nil when it is not a `mailto:` link.
    ///
    /// Addresses come from the part before `?` and from any `to=`, in that
    /// order, split on commas; `cc=` and `bcc=` the same, and a field named
    /// twice keeps both. Keys are compared without case. Everything is
    /// percent-decoded, and a malformed escape is kept as written rather
    /// than losing the field. The body's CRLFs become the composer's line
    /// breaks. Anything else a link carries (`in-reply-to=`, headers no
    /// composer shows) is ignored, as Mail ignores it.
    static func parse(_ link: String) -> Fields? {
        guard let colon = link.firstIndex(of: ":"),
              link[..<colon].lowercased() == "mailto" else { return nil }
        let rest = link[link.index(after: colon)...]
        let (path, query): (Substring, Substring?) = {
            guard let q = rest.firstIndex(of: "?") else { return (rest, nil) }
            return (rest[..<q], rest[rest.index(after: q)...])
        }()

        var fields = Fields()
        fields.to = addresses(path)
        for pair in (query ?? "").split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = decoded(parts[0]).lowercased()
            let value = parts.count > 1 ? parts[1] : ""
            switch key {
            case "to":      fields.to += addresses(value)
            case "cc":      fields.cc += addresses(value)
            case "bcc":     fields.bcc += addresses(value)
            case "subject": fields.subject = decoded(value)
            case "body":
                fields.body = decoded(value)
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
            default: continue
            }
        }
        return fields
    }

    /// The letter the composer opens with: the link's fields, and his
    /// signature under the body as a new letter has it.
    static func draft(from url: URL, signature: String) -> Draft? {
        guard let fields = parse(url.absoluteString) else { return nil }
        var draft = fields.body.isEmpty
            ? Draft.blank(signature: signature)
            : Draft(body: fields.body + Draft.signatureBlock(signature))
        draft.to = fields.to
        draft.cc = fields.cc
        draft.bcc = fields.bcc
        draft.subject = fields.subject
        return draft
    }

    /// Decoded before it is split, so a comma written `%2C` separates
    /// addresses as a bare one does.
    private static func addresses(_ raw: Substring) -> [String] {
        decoded(raw).split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func decoded(_ raw: Substring) -> String {
        String(raw).removingPercentEncoding ?? String(raw)
    }
}
