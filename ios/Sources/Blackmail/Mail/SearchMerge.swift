import Foundation

/// Interleaving two date-ordered streams of results into one.
///
/// Exists because "All Mailboxes" cannot be one mailbox. Gmail's All Mail
/// holds everything EXCEPT Trash and Spam — the exclusivity this codebase
/// already relies on in `countedFolders` — so a search that stops at All
/// Mail can never find a letter he binned. Reaching those two means
/// searching three mailboxes and merging the results.
///
/// And the merge has to be by DATE, which is the whole difficulty. A UID is
/// only meaningful inside the mailbox that issued it: UID 900 in Trash and
/// UID 900 in All Mail are unrelated messages, so the `beforeUID` cursor
/// that pages every other list in this app cannot span them, and neither
/// can a numeric sort.
///
/// Pure, and therefore tested. The failure modes are a message appearing on
/// two consecutive pages, or falling between them and never being seen at
/// all — both invisible in a screenshot and both fatal to "search finds the
/// letter", which is the one thing this feature is for.
enum SearchMerge {

    struct Merged: Equatable {
        /// The page, date-descending.
        var taken: [MessageSummary]
        /// What is left of each stream, in order, for the next page.
        var primary: [MessageSummary]
        var secondary: [MessageSummary]
    }

    /// Orders two results the way the list does: newest first, ties broken
    /// by id.
    ///
    /// The tie-break is not cosmetic. Two messages sharing a timestamp to
    /// the second is ordinary — a mailing list, or anything sent by a
    /// machine — and without a TOTAL order the comparison is ambiguous,
    /// which across a page boundary means one of them can be emitted twice
    /// or skipped.
    static func isOrderedBefore(_ a: MessageSummary, _ b: MessageSummary) -> Bool {
        if a.date != b.date { return a.date > b.date }
        return a.id < b.id
    }

    /// Takes up to `limit`, newest first, from two already-ordered streams.
    ///
    /// `primaryExhausted` is load-bearing and is the subtle part. When the
    /// primary stream runs dry but the server has more to give, the merge
    /// MUST stop rather than fall through to the secondary: emitting a
    /// trashed message from last March just because the current chunk of
    /// All Mail happened to end would put it above hundreds of newer
    /// letters not yet fetched. So an empty-but-not-finished primary ends
    /// the page, and the caller refills and calls again.
    static func take(_ limit: Int,
                     from primary: [MessageSummary], primaryExhausted: Bool,
                     and secondary: [MessageSummary]) -> Merged {
        var left = primary
        var right = secondary
        var out: [MessageSummary] = []

        while out.count < limit {
            if left.isEmpty && !primaryExhausted { break }
            if left.isEmpty && right.isEmpty { break }

            if left.isEmpty {
                out.append(right.removeFirst())
            } else if right.isEmpty {
                out.append(left.removeFirst())
            } else if isOrderedBefore(left[0], right[0]) {
                out.append(left.removeFirst())
            } else {
                out.append(right.removeFirst())
            }
        }
        return Merged(taken: out, primary: left, secondary: right)
    }
}
