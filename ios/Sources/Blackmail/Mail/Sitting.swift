import Foundation

/// Coming back to the app, and what that does to the lists. B-003.
///
/// Out of `RootViewController` for the reason `SearchAnswer` is: the
/// controller is UIKit and does not exist on the machine the suite runs on.
enum Sitting {

    /// How long away counts as a NEW SITTING rather than an interruption.
    ///
    /// A judgement call, because it turns on his habit, not on anything in
    /// the code. `PRODUCT_SPEC.md` calls for two things that disagree — "the
    /// app opens into Inbox" and "preserve scroll position where
    /// practical" — and the answer is that both are right at different
    /// timescales.
    ///
    /// Fifteen minutes, erring SHORT on purpose. The two failures are not
    /// equal. Resetting too eagerly loses his place, which is a nuisance
    /// and now a cheap one to undo: the calendar button and search both
    /// exist to get back. Resetting too rarely means picking the iPad up
    /// the next morning and finding himself somewhere in last June with no
    /// idea how he got there or how to leave — which does not read as a
    /// preserved position, it reads as the app having lost his mail.
    static let awayBeforeReturningToInbox: TimeInterval = 15 * 60

    enum Return: Equatable {
        /// A short interruption. He is still doing the same thing, so he is
        /// left where he was.
        case stay
        /// A new sitting, with the Inbox already on screen: its newest mail
        /// is fetched into the list that is there, from the top.
        case refreshInbox
        /// A new sitting in another folder: the Inbox replaces it.
        case openInbox
    }

    /// What coming back after `away` seconds does.
    ///
    /// NOT while something is open over the top. A half-written letter is
    /// the one piece of state in this app he cannot get back, and pulling
    /// the folder out from under a compose sheet to be tidy would be the
    /// worst trade in the product.
    ///
    /// With the Inbox already showing, it used to be replaced all the same,
    /// by a new list with no rows in it: a black pane under "Updated Just
    /// Now" for a second or two, and the letter he had been reading gone
    /// from the pane to the right, to land him in the Inbox he was already
    /// in. The list on screen is kept now, and fetched again from the top.
    static func onReturn(after away: TimeInterval, showingInbox: Bool,
                         sheetOpen: Bool) -> Return {
        guard away > awayBeforeReturningToInbox, !sheetOpen else { return .stay }
        return showingInbox ? .refreshInbox : .openInbox
    }

    /// The Inbox's newest page, and then the folder counts, only once the
    /// page has come: launch's order (`SweepCoalescer`), for the same
    /// reasons. The counts used to be asked for at the same moment, and the
    /// sweep's nine commands took turns with the page's on the one
    /// connection. And a page that could not be fetched asks for no counts:
    /// they would connect again straight after the failure, and a refused
    /// password would go twice.
    ///
    /// On the main actor, closures and all, because both drive the screen:
    /// the list the page is drawn into, and the folder pane that asks for
    /// the counts.
    @MainActor
    static func refresh(newest: @MainActor () async -> Bool,
                        counts: @MainActor () -> Void) async {
        afterNewest(came: await newest(), counts: counts)
    }

    /// The counts, once the Inbox's newest page has come, and none if it
    /// could not be fetched. `refresh`'s rule, on its own for a return to
    /// another folder, where the Inbox is a new list that fetches its first
    /// page itself and says afterwards whether it came.
    @MainActor
    static func afterNewest(came: Bool, counts: @MainActor () -> Void) {
        if came { counts() }
    }
}
