import Foundation

/// The arithmetic that turns a mailbox's UID snapshot into the page the list
/// shows.
///
/// Extracted from `IMAPMailRepository` so it can be TESTED. The repository is
/// behind `#if canImport(Network)` and does not exist on the machine the test
/// suite runs on, which meant `PagingTests` had to re-implement the cursor
/// walk by hand and then assert against its own copy — green tests exercising
/// logic the product did not run. Now both call this.
///
/// Everything here works on the snapshot IMAP hands back from `SEARCH ALL`:
/// UIDs ASCENDING, with gaps where messages were expunged. The list shows
/// them newest first, so almost every function reverses.
enum PageWindow {

    /// How many newer messages a date jump keeps above its anchor.
    ///
    /// Not zero. Landing the chosen day hard against the top of the list
    /// looks identical to "this is the newest mail there is" — the one
    /// reading he must not take away from a jump, since the whole point is
    /// that he can carry on upward into the days after it. Ten rows is more
    /// than a screenful, so scrolling up moves immediately and the next
    /// page is fetched before he reaches the top.
    static let newerRowsAboveAnchor = 10

    /// A two-ended window: what to show, where the anchor landed in it, and
    /// whether either end of the mailbox is already included.
    struct Window: Equatable {
        /// Newest first, like every other list in the app.
        var uids: [UInt32]
        /// Index of the anchor within `uids`. The row to scroll to.
        var anchorIndex: Int
        /// The newest message in the mailbox is in `uids`, so there is
        /// nothing further to load upward.
        var reachedNewest: Bool
        /// Likewise the oldest, downward.
        var reachedOldest: Bool
    }

    /// One page of messages strictly OLDER than `cursor`, newest first.
    ///
    /// `cursor == nil` means "from the top", which is how the first page of
    /// every folder is fetched.
    static func older(than cursor: UInt32?, in ascending: [UInt32],
                      limit: Int) -> [UInt32] {
        var newestFirst = Array(ascending.reversed())
        if let cursor {
            if let idx = newestFirst.firstIndex(of: cursor) {
                newestFirst = Array(newestFirst.dropFirst(idx + 1))
            } else {
                // The cursor message was expunged by another client. Falling
                // back to "everything older by value" keeps the walk moving;
                // restarting at the top would loop forever.
                newestFirst = newestFirst.filter { $0 < cursor }
            }
        }
        return Array(newestFirst.prefix(max(0, limit)))
    }

    /// One page of messages strictly NEWER than `cursor`, newest first, and
    /// ADJACENT to it — the `limit` messages immediately above, not the
    /// newest in the mailbox.
    ///
    /// The direction that only exists because of the date jump. Without a
    /// jump the list is anchored at the newest message and this is never
    /// called; after one, it is what "work forwards from the 20th" means.
    ///
    /// The subtlety, and one a test caught rather than review: "newer than
    /// the cursor" is not "the newest". Taking the newest `limit` UIDs —
    /// the top of the mailbox — would prepend today's mail directly above
    /// the day he jumped to and leave a silent hole of everything between.
    /// The page he wants is the one ADJACENT to the cursor, which in an
    /// ascending list is the LOWEST of the ones above it.
    static func newer(than cursor: UInt32, in ascending: [UInt32],
                      limit: Int) -> [UInt32] {
        guard limit > 0 else { return [] }
        let newer = ascending.filter { $0 > cursor }
        return Array(newer.prefix(limit).reversed())
    }

    /// The window to show around a jump target.
    ///
    /// The anchor is placed `newerRowsAboveAnchor` rows down so there is
    /// visible room above it, and the rest of the budget is spent on older
    /// mail — he is looking back from that day, so most of the page should
    /// be the direction he is looking. Both counts shrink rather than
    /// overrun when the anchor is near either end of the mailbox.
    static func window(around anchor: UInt32, in ascending: [UInt32],
                       limit: Int) -> Window {
        guard limit > 0, let index = ascending.firstIndex(of: anchor) else {
            return Window(uids: [], anchorIndex: 0,
                          reachedNewest: true, reachedOldest: true)
        }

        let newerAvailable = ascending.count - index - 1
        let olderAvailable = index

        // Ask for the nominal share above, then hand whichever side the
        // mailbox could not supply to the other, so a jump near either end
        // still fills a whole page instead of a tenth of one. Every term is
        // clamped: `limit` of 1 must produce the anchor alone, not a
        // backwards range.
        // A fifth of the page at most, so the share stays sensible when the
        // page is small: ten rows above the anchor out of a page of fifty
        // is room to scroll up into, but ten out of a page of five would
        // put the day he asked for at the very BOTTOM with nothing older
        // loaded at all — the opposite of what the jump is for.
        let budget = limit - 1
        let nominalNewer = min(newerRowsAboveAnchor, max(1, limit / 5))
        var takeNewer = min(nominalNewer, newerAvailable, budget)
        let takeOlder = min(budget - takeNewer, olderAvailable)
        takeNewer = min(newerAvailable, budget - takeOlder)

        // Half-open on both sides: either slice must be able to be EMPTY,
        // and `a...a-1` is a crash rather than an empty range.
        let newerPart = Array(ascending[(index + 1)..<(index + 1 + takeNewer)].reversed())
        let olderPart = Array(ascending[(index - takeOlder)..<index].reversed())

        return Window(uids: newerPart + [anchor] + olderPart,
                      anchorIndex: takeNewer,
                      reachedNewest: takeNewer == newerAvailable,
                      reachedOldest: takeOlder == olderAvailable)
    }

    /// Which message a date lands on, given what the server's date SEARCH
    /// matched.
    ///
    /// `matches` is the UID set for "sent on or after that day". The one he
    /// wants is the OLDEST of them — the first letter of that day — not the
    /// newest, which would be today's mail.
    ///
    /// Returns nil only when the mailbox has nothing on or after the date,
    /// which the caller reads as "everything here is older than the day you
    /// asked for" and answers by going to the top.
    static func anchor(forMatches matches: [UInt32], in ascending: [UInt32]) -> UInt32? {
        guard let oldestMatch = matches.min() else { return nil }
        // The SEARCH and the snapshot are two round trips, so they can
        // disagree: mail delivered between them is matched but absent, and
        // a message expunged between them is the reverse. Snap to the
        // nearest UID the snapshot actually has, in the same direction.
        if ascending.contains(oldestMatch) { return oldestMatch }
        return ascending.first { $0 >= oldestMatch }
    }
}
