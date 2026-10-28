import Foundation

/// The arithmetic that turns a mailbox's UID snapshot into the page the list
/// shows.
///
/// Extracted from `IMAPMailRepository` so it could be TESTED. The repository
/// was behind `#if canImport(Network)` and did not exist on the machine the
/// test suite runs on, which meant `PagingTests` had to re-implement the cursor
/// walk by hand and then assert against its own copy — green tests exercising
/// logic the product did not run. Now both call this.
///
/// Everything here works on a folder's letters the oldest first, as
/// `ascending` names them: the list's order turned over. Since B-178 that is
/// the order they arrived in (`ArrivalOrder.ascending`), not their UIDs, so
/// a place is found by where a UID stands in it, not by its value; a list of
/// UIDs ascending, as IMAP's `SEARCH ALL` gives them, is the same walk for a
/// folder whose letters came in the order of their UIDs. The list shows
/// them newest first, so almost every function reverses.
enum PageWindow {

    /// How many newer messages a date jump keeps above its anchor.
    ///
    /// Not zero. Landing the chosen day hard against the top of the list
    /// looks identical to "this is the newest mail there is" — the one
    /// reading he must not take away from a jump, since the whole point is
    /// that he can carry on upward into the days after it. Ten rows is more
    /// than a screenful, so scrolling up moves immediately and the next
    /// page is fetched before he reaches the top. A jump fetches the page
    /// above these with them (`jumpWindow`, B-117).
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
                // restarting at the top would loop forever. The list's own
                // pages go by `ArrivalOrder.older`, which places a cursor
                // gone by when it arrived.
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
    ///
    /// By the cursor's place in `ascending` (B-178); a cursor not in it, by
    /// value, as `older` falls back.
    static func newer(than cursor: UInt32, in ascending: [UInt32],
                      limit: Int) -> [UInt32] {
        guard limit > 0 else { return [] }
        let newer = newerAll(than: cursor, in: ascending)
        return Array(newer.prefix(limit).reversed())
    }

    /// Every letter of `ascending` newer than `cursor`, the oldest first.
    private static func newerAll(than cursor: UInt32, in ascending: [UInt32]) -> ArraySlice<UInt32> {
        if let at = ascending.firstIndex(of: cursor) { return ascending[(at + 1)...] }
        return ArraySlice(ascending.filter { $0 > cursor })
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

    /// What a date jump fetches and shows: the window around the anchor
    /// (`window(around:in:limit:)`), and over it the page above it, the
    /// `limit` letters next newer, all in the window's one FETCH (B-117).
    ///
    /// The page above used to be asked for on its own as the day landed
    /// (B-094), and with Organize by Thread on it took the letter the jump
    /// had landed on out of sight: a reply to that letter among the next
    /// fifty newer joins its row, and the row goes up the list to where the
    /// reply is, dated the day of the reply (`MessageThread`). Seen on the
    /// iPad on 2026-10-23: 1 June 2012's first letter, UID 762, landed on
    /// and drawn, and 0.14 s later gone, its reply 773 the eleventh newer
    /// letter, one past the ten the window keeps above it. Fetched with the
    /// window, the page above is in the list as it is first drawn, so the
    /// row that carries the letter is its conversation's from the first
    /// frame, dated as its reply, up the list where Mail's list has it, and
    /// the jump opens on the oldest row dated on or after the day
    /// (`ListOpening.dayRow`, B-118): 763, the day's next letter. A reply
    /// further up still joins the row opened on later and takes it up the
    /// list, and the day's next row comes into its place
    /// (`ListPlace.landing(in:holding:)`).
    ///
    /// No round trip more: the same FETCH, fifty rows longer. With none
    /// newer than the window, the window alone.
    static func jumpWindow(around anchor: UInt32, in ascending: [UInt32],
                           limit: Int) -> Window {
        let around = window(around: anchor, in: ascending, limit: limit)
        guard !around.reachedNewest, let newest = around.uids.first else { return around }
        let above = newer(than: newest, in: ascending, limit: limit)
        let newerAvailable = newerAll(than: newest, in: ascending).count
        return Window(uids: above + around.uids,
                      anchorIndex: around.anchorIndex + above.count,
                      reachedNewest: above.count == newerAvailable,
                      reachedOldest: around.reachedOldest)
    }

    /// Which message a date's window is fetched around, given what the
    /// server's date SEARCH matched; where in it the jump lands is
    /// `landing`, by his calendar.
    ///
    /// `matches` is what the jump's SEARCHes found (`IMAPDate.jump`,
    /// B-115), all by when the letters arrived (B-178): the first to arrive
    /// of that day's, in his calendar; or if it has none, the letters of
    /// the first span after it that has any; or if none has, every letter
    /// that arrived after it, no later than a week after today (B-058). Of
    /// them it is the LOWEST UID, the first to have come into the folder,
    /// not the newest, which would be the span's last letter or today's
    /// mail. On a day with mail that is the first of his day to arrive
    /// whatever order the folder's UIDs are in, never one of his evening
    /// before that Gmail, counting from midnight UTC, takes for the day.
    /// From a span it is the first to arrive while the folder's UIDs follow
    /// its arrivals, and `landing` goes down to it where they do not.
    ///
    /// Returns nil only when the mailbox has nothing so matched, which the
    /// caller reads as "everything here is older than the day you asked
    /// for" and answers by going to the top: nothing arrived on or after
    /// the day, or only a letter that says it arrived more than a week
    /// after today, copied in dated wrong.
    static func anchor(forMatches matches: [UInt32], in ascending: [UInt32]) -> UInt32? {
        guard let oldestMatch = matches.min() else { return nil }
        // The SEARCH and the snapshot are two round trips, so they can
        // disagree: mail delivered between them is matched but absent, and
        // a message expunged between them is the reverse. Snap to the
        // nearest UID the snapshot actually has, in the same direction.
        if ascending.contains(oldestMatch) { return oldestMatch }
        return ascending.first { $0 >= oldestMatch }
    }

    /// How many times a jump moves its anchor down a window towards the
    /// first letter to arrive on or after the day (`anchor(below:in:limit:
    /// arrival:dayStart:notAfter:)`): at a page of fifty, thirty-nine rows
    /// a time, so as far as 780 rows below the letter the SEARCH found,
    /// each move widening the order as a page below does, in the jump's
    /// hold.
    static let lowerAnchorsAtMost = 20

    /// Where a jump's window is cut from in place of `anchor`, the letter
    /// its SEARCH found, in `ascending`, the order the letters arrived in
    /// (B-178): the lowest row of the window around `anchor`, when it and
    /// `anchor` arrived on or after his midnight, `dayStart`, and no later
    /// than `notAfter`, a week after today. In that order every row between
    /// the two arrived on or after his day as well, and the first of them
    /// to arrive, where `landing` goes down to, can be further down than
    /// the window goes. A span's lowest UID can be that far above it in a
    /// label, its UIDs going by when the label was put on: the landing
    /// stopped at the window's last row, and "Showing" named a later day.
    /// Nil where the window holds a row below `anchor` that arrived before
    /// his day, which is the first to arrive's, or no row below it.
    static func anchor(below anchor: UInt32, in ascending: [UInt32], limit: Int,
                       arrival: (UInt32) -> Date?, dayStart: Date,
                       notAfter: Date) -> UInt32? {
        func onOrAfterHisDay(_ uid: UInt32) -> Bool {
            guard let arrived = arrival(uid) else { return false }
            return arrived >= dayStart && arrived <= notAfter
        }
        let around = window(around: anchor, in: ascending, limit: limit)
        guard let lowest = around.uids.last, lowest != anchor,
              onOrAfterHisDay(anchor), onOrAfterHisDay(lowest) else { return nil }
        return lowest
    }

    /// Where the anchor is among the rows the jump's FETCH brought, `fetched`
    /// their UIDs, newest first as the window has them: the anchor's own
    /// row, or with the server having left it out of the FETCH, the nearest
    /// row older than it, from which `landing` moves up to the nearest
    /// dated on or after his day. With no older row, the last, the nearest
    /// newer. Nil with no rows.
    ///
    /// It was the first row, the top of the window. That was ten letters
    /// newer than the anchor at most, and with the page above in the window
    /// (`jumpWindow`, B-117) sixty, near enough a whole day at his volume.
    static func anchorRow(_ anchor: UInt32, fetched: [UInt32]) -> Int? {
        guard !fetched.isEmpty else { return nil }
        return fetched.firstIndex { $0 <= anchor } ?? fetched.count - 1
    }

    /// The same by place in `window`, whose letters go as the list's do,
    /// the order they arrived in (B-178): the anchor's own row, or the
    /// nearest row the window has below it; with none, the last.
    static func anchorRow(fetched: [UInt32], in window: Window) -> Int? {
        guard !fetched.isEmpty else { return nil }
        var place: [UInt32: Int] = [:]
        for (i, uid) in window.uids.enumerated() where place[uid] == nil { place[uid] = i }
        return fetched.firstIndex { (place[$0] ?? -1) >= window.anchorIndex } ?? fetched.count - 1
    }

    /// The row a jump lands on in its window, by his calendar: `dates` the
    /// window's rows' dates, newest first, each when its letter arrived as
    /// the list goes and shows it (`MessageSummary.listDate`, B-178),
    /// `anchor` the row the SEARCH landed on (`anchor(forMatches:in:)`),
    /// `dayStart` midnight of the day he asked for where he is, and
    /// `notAfter` a week after today.
    ///
    /// The oldest row that arrived on or after his day: in a list in the
    /// order the letters arrived, every row above it arrived after it and
    /// every row below it before his day. From the anchor, down over the
    /// rows below it that arrived on or after his midnight, each no later
    /// than the row above it: a row out of that order, as a row kept with
    /// no arrival can be, ends the walk, as the account's own letters of
    /// 2026 at the foot of a folder by UID ended none before. Of his day's
    /// letters the anchor is the first to arrive (`IMAPDate.jump`), and
    /// none is below it. Of a span's after it, the anchor is the lowest UID
    /// matched, which in a label or a folder with letters moved in can have
    /// arrived after others the span matched, which are below it in the
    /// list: the landing goes down to the first of them to arrive, the
    /// window having been cut lower where that is further down than the
    /// window around the anchor went (`anchor(below:in:limit:arrival:
    /// dayStart:notAfter:)`), as far as `lowerAnchorsAtMost` windows
    /// down. It went down only over his first hours east of Greenwich
    /// while a jump went by the Date, a row below dated later being one
    /// dated wrong; by arrival a row is where it arrived.
    ///
    /// Gmail counts a day from midnight UTC, not from his midnight (B-058,
    /// seen on the iPad). An anchor that arrived before his day, which the
    /// day's SEARCH no longer gives, moves up to the nearest newer row that
    /// arrived on or after it. A row that says it arrived after `notAfter`,
    /// more than a week ahead, was copied in dated wrong and is never
    /// landed on by this; a landing that is one moves up as one before his
    /// day does. With no such row above it, the landing stays where the
    /// SEARCH put it, and the repository finds nothing that recent.
    static func landing(dates: [Date], anchor: Int, dayStart: Date, notAfter: Date) -> Int {
        guard dates.indices.contains(anchor) else { return anchor }
        func onOrAfterHisDay(_ i: Int) -> Bool { dates[i] >= dayStart && dates[i] <= notAfter }
        if !onOrAfterHisDay(anchor) {
            for i in stride(from: anchor - 1, through: 0, by: -1) where onOrAfterHisDay(i) {
                return i
            }
            return anchor
        }
        var landed = anchor
        while landed + 1 < dates.count, onOrAfterHisDay(landed + 1),
              dates[landed + 1] <= dates[landed] {
            landed += 1
        }
        return landed
    }
}
