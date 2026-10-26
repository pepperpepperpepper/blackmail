import Foundation

/// How a folder's list gets its first rows: the newest page, or the day he
/// asked to jump to.
///
/// Out of `MessageListViewController` for the reason `SearchAnswer` is: the
/// controller is UIKit and does not exist on the machine the suite runs on,
/// so an order that lived there could be reverted with every test green.
enum ListOpening {

    /// How a jump to a day came out, as far as the list is concerned.
    enum Jump: Equatable {
        /// The mail around the day is on screen.
        case landed
        /// Nothing on or after the day in this folder.
        case nothingThatRecent
        /// The jump could not be run, and why, as the alert says it.
        case failed(MailError)
        /// The list was replaced while the jump was on its way, by a
        /// refresh or a search, and belongs to that now.
        case superseded
    }

    /// What a jump came to, from what fetching the day returned and whether
    /// the list it was fetched for is still the one on screen.
    ///
    /// A list that has moved on is `.superseded` whichever way the fetch
    /// ended, a failure included, as a stale search is ignored in
    /// `SearchAnswer.settle`. Reported as `.failed`, a list opened to jump
    /// would fall back to its newest page, which clears the search box: a
    /// search he typed while the jump was on its way would be thrown away,
    /// text and all, and an old list replaced by the folder he opened next
    /// would run a whole page of its own in the interactive line.
    static func settle(_ fetched: Result<MessageWindow?, Error>, current: Bool) -> Jump {
        guard current else { return .superseded }
        switch fetched {
        case .success(let window?) where !window.messages.isEmpty:
            return .landed
        case .success:
            return .nothingThatRecent
        case .failure(let error):
            return .failed((error as? MailError) ?? .cannotConnect)
        }
    }

    /// The folder's page kept on the iPad (D-016), for the list to draw as
    /// it opens, before anything has been sent: at launch the Inbox in the
    /// first frame, and every folder he has opened before at once, with a
    /// connection or without one. Nil for a list opened to jump to a day,
    /// which is not the newest page and does not draw it first; for the
    /// Outbox, whose letters are on the iPad already, in their own store;
    /// and for a folder with nothing kept, which opens empty as it always
    /// did.
    static func kept(for mailbox: Mailbox, jumpingTo day: Date?,
                     from shelf: MailShelf?) -> MailShelf.Page? {
        guard day == nil, mailbox.role != .outbox else { return nil }
        return shelf?.page(of: mailbox.id)
    }

    /// The kept rows below a fresh first page, `first`, as the folder's kept
    /// page has them once the page has been taken (`MailShelf.took(page:)`,
    /// B-160): the rows after it, which go on from it in the folder's order
    /// now. Empty when the kept rows do not begin with the page's.
    ///
    /// For the fresh page put in place of the kept rows he has scrolled
    /// down (`KeptSwap.holdingPlace`), or that a search is over: the rows he
    /// was reading below the page stay, and the list pages on from the last
    /// of them. At the top the page goes in alone, as it always did.
    static func keptTail(below first: [MessageSummary], in kept: [MessageSummary]) -> [MessageSummary] {
        guard !first.isEmpty, kept.count > first.count,
              zip(first, kept).allSatisfy({ $0.id == $1.id }) else { return [] }
        return Array(kept[first.count...])
    }

    /// The first rows of a list opened at `day`, or at its newest mail when
    /// there is no day.
    ///
    /// A list opened in order to jump, as an All Mailboxes jump opens All
    /// Mail, used to load its newest page first, draw today's mail, and
    /// then throw it away for the day he asked for: seven commands where
    /// the jump alone is four, and about twice as long before the day was
    /// on screen. The jump now runs instead of that page. The newest page
    /// still comes when the jump finds nothing on or after the day, or
    /// fails, so the pane is never left empty. The jump has the same read
    /// retry as the page.
    ///
    /// Returns what the jump came to when it fell back to the newest page,
    /// for the caller to say so over it, and nil otherwise.
    static func open(at day: Date?,
                     jump: (Date) async -> Jump,
                     newest: () async -> Void) async -> Jump? {
        guard let day else {
            await newest()
            return nil
        }
        let outcome = await jump(day)
        switch outcome {
        case .landed, .superseded:
            return nil
        case .nothingThatRecent, .failed:
            await newest()
            return outcome
        }
    }

    /// Where a jump opens: the row put at the top of the pane, and the day
    /// "Showing" names (B-118).
    struct DayRow: Equatable {
        /// In the list's rows.
        let row: Int
        /// The row's date, or the letter landed on's when no row is dated
        /// within the day's bounds.
        let shown: Date
    }

    /// The row of `rows`, the list's rows as it draws them from `window`'s
    /// letters, that a jump opens on, as Mail's list shows the day (B-118):
    /// the oldest row dated on or after it, a row dated by its newest letter
    /// (`MessageThread.date`), the rows dated after it above and those dated
    /// before it below.
    ///
    /// Asked for by the owner on 2026-10-23: "Copy how Apple Mail works in
    /// terms of the date." With Organize by Thread on, Mail dates a
    /// conversation's row by its newest letter and orders the rows by that
    /// date. The jump used to open on the row that carries the letter landed
    /// on, the day's first, and when that letter was answered in the days
    /// after it that row is its conversation's, up the list where its reply
    /// puts it: on the iPad 1 June 2012 opened on "Re: Watch and winter
    /// evening weather lunch", dated 5 June, with the rows of 4 to 1 June
    /// under it and the day's next letter, 763, the eleventh row; it opens on
    /// 763 now, with 30 May under it.
    ///
    /// Found from the letter landed on (`window.anchorIndex`), upward: the
    /// first of its letters, from that one up, that heads a row, the row's
    /// id, whose row is dated from `window.dayStart`, his midnight, to
    /// `window.notAfter`, a week after today. A row takes the place of the
    /// letter it is headed by (`MessageThread.group`), so that is the lowest
    /// row at or above the letter's place dated on or after the day: in a
    /// folder in date order the oldest row so dated, and nothing below it is
    /// of the day. A letter of the day answered later is in its
    /// conversation's row, up where the reply puts it; if every letter of the
    /// day is, the row opened on is the oldest dated after it, and "Showing"
    /// names its day, as for a day with no mail of its own. With Organize by
    /// Thread off every letter is a row of its own and this is the letter
    /// landed on's row, as before. Only the rows' letters date them: his
    /// letters from Sent Mail in an Inbox conversation's stack (Complete
    /// Threads, B-104) are not in the list.
    ///
    /// Not by date alone over every row: in a folder whose letters did not
    /// come in the order they were written, a row dated on or after the day
    /// can be anywhere, as the account's own letters at the foot of the size
    /// test's Inbox are, and the landing does not go there either (B-115).
    ///
    /// With no row so dated at or above the letter, the row that carries
    /// the letter, and the day it was landed on (`window.landedOn`), as
    /// before. Nil when no row carries it, as when it has been taken off by
    /// hand, and with no letters.
    static func dayRow(in rows: [MessageThread], for window: MessageWindow) -> DayRow? {
        let letters = window.messages
        guard !letters.isEmpty else { return nil }
        let landed = min(max(window.anchorIndex, 0), letters.count - 1)
        let landedID = letters[landed].id
        guard let carrying = rows.firstIndex(where: { row in
            row.messages.contains { $0.id == landedID }
        }) else { return nil }
        var heading: [String: Int] = [:]
        for (i, row) in rows.enumerated() where heading[row.id] == nil { heading[row.id] = i }
        for i in stride(from: landed, through: 0, by: -1) {
            guard let row = heading[letters[i].id] else { continue }
            let date = rows[row].date
            if date >= window.dayStart && date <= window.notAfter {
                return DayRow(row: row, shown: date)
            }
        }
        return DayRow(row: carrying, shown: window.landedOn)
    }
}
