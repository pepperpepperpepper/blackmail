import Foundation

/// Which letters are fetched ahead for reading with no connection (B-160):
/// the newest unread letters of the Inbox, as its kept page lists them,
/// newest first. Mail downloads mail ahead of his opening it; here the cost
/// is bounded, the newest `IMAPMailRepository.mostAhead` unread letters or
/// `mostAheadBytes`, whichever comes first, and only unread ones, which he
/// has not read anywhere and is likeliest to open.
///
/// Out of the repository for the reason `PageWindow` is: so the suite can
/// run the rule apart from the wire.
enum FetchAhead {

    /// The unread rows of `rows`, newest first as given, with a Gmail id,
    /// the first `most`.
    static func letters(on rows: [MessageSummary], most: Int) -> [MessageSummary] {
        Array(rows.filter { !$0.isRead && $0.gmailMessageID != nil }.prefix(most))
    }
}
