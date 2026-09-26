import Foundation

/// What "search" means, as an IMAP SEARCH key.
///
/// Pulled out of `IMAPMailRepository` so it can be tested. The repository is
/// behind `#if canImport(Network)`, and this is the one string in the app
/// that is BOTH assembled from user input AND concatenated into a protocol
/// command — `IMAPClient.sanitizedCommandText` strips only NUL/CR/LF and
/// deliberately leaves the caller's quoting alone, so the escaping here is
/// the only thing between a typed apostrophe and a malformed command.
enum SearchCriteria {

    /// The fields a search looks at.
    ///
    /// **TO and CC are in this list, and their absence was a real hole.**
    /// Search used to match FROM, SUBJECT and BODY only, which means
    /// searching a friend's name found every letter that person SENT him
    /// and none of the ones he sent them — half of a correspondence,
    /// missing, with nothing to indicate it. For someone who searches daily
    /// to find "the letters between me and X", that is the common case
    /// rather than an edge one. Mail matches addressees too.
    ///
    /// Ordered cheapest first only for readability; the server decides how
    /// to evaluate it.
    static let fields = ["FROM", "TO", "CC", "SUBJECT", "BODY"]

    /// IMAP quoted-string escaping: backslash first, then quote.
    ///
    /// Order matters and is the classic way to get this wrong. Escaping the
    /// quote first would leave the backslash it just inserted to be escaped
    /// again by the second pass, doubling it.
    static func escape(_ term: String) -> String {
        term.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// `OR OR OR OR FROM "x" TO "x" CC "x" SUBJECT "x" BODY "x"`.
    ///
    /// RFC 3501's OR is strictly binary and written in prefix form, so N
    /// fields need N-1 leading ORs. Built by folding rather than by hand:
    /// the hand-written version had the right number of ORs for three
    /// fields and would have been silently wrong the moment a fourth was
    /// added — an unbalanced key is a BAD, which this app renders as
    /// "Can't connect to mail server."
    static func imap(for query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let escaped = escape(trimmed)

        let terms = fields.map { "\($0) \"\(escaped)\"" }
        guard var key = terms.first else { return nil }
        for term in terms.dropFirst() {
            key = "OR \(key) \(term)"
        }
        return key
    }
}
