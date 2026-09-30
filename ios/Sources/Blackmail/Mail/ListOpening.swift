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
        /// The jump could not be run.
        case failed
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
        case .failure:
            return .failed
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
}
