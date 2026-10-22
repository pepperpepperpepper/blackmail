import Foundation

/// When the pull's spinner is put away once its page has answered (B-103).
///
/// Seen on the test iPad on 2026-10-22: a page that answered after the
/// finger had lifted, while the list sprang back to the spinner's rest,
/// left the list resting 60 pt below its top with no spinner, until it was
/// touched. UIKit's refresh control told to end while the list springs back
/// takes its room away above the first row and leaves the list where the
/// spring-back was going. Told to end under the finger, it ends as the
/// finger lets go, and told to end with the list at rest, it takes the list
/// back to its top itself: both were seen clean on the iPad.
///
/// So the end is put away at once under a finger on the list or with the
/// list still, and otherwise held until the list has come to rest or a
/// finger takes it. A held end that UIKit never reports the rest for is
/// put away all the same after `bound`, so no way through can leave the
/// spinner turning. Put away at once, and nothing left held, as the list
/// leaves the screen, as the app goes to the background, at another folder,
/// and wherever the pull is taken off the list: Edit mode, a search, a
/// day's list and the panes' motion (`MessageListViewController`).
///
/// Out of `MessageListViewController` for the reason `RefreshTap` is: the
/// controller is UIKit and does not exist on the machine the suite runs on.
struct PullEnd {

    /// How long a held end waits for the list to come to rest, in seconds:
    /// a few times the spring-back, which took about half a second on the
    /// iPad.
    static var bound: TimeInterval { 2 }

    /// Whether a list with no finger on it is still moving: coasting or
    /// springing back, or past its top, where it is about to spring back.
    /// `topInset` is the room the list keeps above its first row, the
    /// spinner's included while it turns; half a point of it is the top.
    static func moving(decelerating: Bool, offset: Double, topInset: Double) -> Bool {
        decelerating || offset < -topInset - 0.5
    }

    /// What to do with the spinner as the page answers.
    enum Answer: Equatable {
        /// Put it away now.
        case now
        /// Put it away once the list is at rest, or once `bound` has gone
        /// by: the number is what `due` is handed then.
        case held(Int)
    }

    /// The end waiting for the list to come to rest, if one is.
    private(set) var holding: Int?
    private var holds = 0

    /// The page has answered. `spinning` is whether the spinner turns;
    /// `fingerDown` whether a finger is on the list; `moving` as `moving`
    /// reckons it. Now when it does not turn, under a finger, or with the
    /// list still; held only while the list moves with no finger on it.
    mutating func answered(spinning: Bool, fingerDown: Bool, moving: Bool) -> Answer {
        guard spinning, !fingerDown, moving else {
            holding = nil
            return .now
        }
        holds += 1
        holding = holds
        return .held(holds)
    }

    /// The list has come to rest, or a finger has taken it: whether an end
    /// held for that is due now. Once.
    mutating func settled() -> Bool {
        guard holding != nil else { return false }
        holding = nil
        return true
    }

    /// The bound for the hold `hold` has gone by: whether it is still held.
    /// Once; never for a hold put away since, or one a later answer took
    /// the place of.
    mutating func due(_ hold: Int) -> Bool {
        guard holding == hold else { return false }
        holding = nil
        return true
    }

    /// The spinner put away at once: nothing is held.
    mutating func putAway() {
        holding = nil
    }
}

/// An alert from a page that fails while his finger is on the list, held
/// until the finger has let go (B-103).
///
/// Seen on the test iPad on 2026-10-22: with no connection, a quick pull's
/// page failed while the finger was still down, and "Can't connect to mail
/// server." was put up as the finger lifted. UIKit takes in no touches while
/// an alert comes on, so the list never had the end of its drag: after OK
/// it stayed pulled down with the spinner turning until it was touched.
/// Put up as the drag ends, the alert comes on while the list springs back,
/// which was seen clean there.
///
/// A finger that only rests on the list, and never drags, tells it nothing
/// as it lifts, so the list looks every so often for it to have lifted, as
/// the kept page does (`KeptSwap`). One alert at a time: a later one in
/// the place of one held. Dropped as the list leaves the screen, when there
/// is nothing to put it over; the line under the list says what failed.
struct LetGoHold<Alert> {

    /// The alert waiting for the finger to let go, if one is.
    private(set) var held: Alert?

    /// `alert` to put up now, or nil while it waits: while a finger is on
    /// the list.
    mutating func show(_ alert: Alert, fingerDown: Bool) -> Alert? {
        guard fingerDown else {
            held = nil
            return alert
        }
        held = alert
        return nil
    }

    /// The finger has let go: the alert held for it, once.
    mutating func letGo() -> Alert? {
        defer { held = nil }
        return held
    }

    /// The list has left the screen: nothing to put the alert over.
    mutating func drop() {
        held = nil
    }
}
