import Foundation

/// Rewriting a message's `cid:` references so something can answer them.
///
/// Pure, and separated from `InlineImageLoader` so the suite on Linux can
/// test it — the loader is WebKit and cannot exist on the test host.
enum InlineImageRewriter {

    /// The custom scheme the body is rewritten to point at.
    ///
    /// WebKit refuses to register a handler for a scheme it already knows —
    /// `http`, `data`, `file` and a dozen more raise an exception at
    /// registration — and `cid` is close enough to that family not to risk
    /// it. This is deliberately a name nothing else can claim.
    static let scheme = "bmcid"

    /// Points every `cid:` reference at the custom scheme.
    ///
    /// Only rewrites ids the message actually HAS. A reference to a part
    /// that is not there stays as `cid:`, where WebKit fails it quietly;
    /// sending it to the handler instead would mean a round trip per
    /// missing image, and messages forwarded through a list routinely
    /// reference images that were stripped on the way.
    static func rewrite(_ html: String, known: Set<String>) -> String {
        guard html.range(of: "cid:", options: .caseInsensitive) != nil else { return html }

        var out = ""
        // Scan for `cid:` and take the id up to the closing quote or the
        // first character that cannot be in one. A regex would do it too,
        // but this reads whatever a stranger sent without a catastrophic
        // backtracking case to worry about.
        var rest = Substring(html)
        while let found = rest.range(of: "cid:", options: .caseInsensitive) {
            out += rest[..<found.lowerBound]
            let after = rest[found.upperBound...]
            let id = after.prefix { ch in
                !(ch == "\"" || ch == "'" || ch == " " || ch == ">" || ch == ")"
                  || ch == "\n" || ch == "\r" || ch == "\t")
            }
            if known.contains(String(id)) {
                out += scheme + "://" + escapedHost(String(id))
            } else {
                out += "cid:" + id
            }
            rest = after[id.endIndex...]
        }
        return out + rest
    }

    /// A `Content-ID` is allowed characters a URL host is not, so it is
    /// percent-encoded on the way out and decoded again in the handler.
    static func escapedHost(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(
            CharacterSet(charactersIn: "-._~"))) ?? id
    }
}
