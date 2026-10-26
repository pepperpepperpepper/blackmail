import Foundation

/// What the reading pane's Flag button offers (B-106): a small sheet, as
/// Mail's Flag button opened one in the toolbar era this app copies. Flag
/// or Unflag, then Mark as Unread or Mark as Read, and Cancel.
///
/// Mail's: in iOS 6 the Flag button's sheet held Mark as Unread beside the
/// flag, and iOS 7 kept "Flag/Unflag and Mark As Read/Unread" there
/// (Macworld's guide to iOS 7 Mail). iPadOS 18 has no Flag button by
/// default, and its More Actions sheet holds the same two items.
///
/// Flag takes two taps where it took one, as in both eras of Mail. He
/// flags a few letters a month.
///
/// Apart from `MessageDetailViewController`, which is UIKit and does not
/// exist on the machine the suite runs on, so the items, their order and
/// their words are pinned on the host.
enum FlagMenu {

    enum Item: Equatable {
        case flag
        case unflag
        case markAsUnread
        case markAsRead

        /// Mail's words, the ones Edit mode's Mark sheet already shows for
        /// the read mark.
        var title: String {
            switch self {
            case .flag: return "Flag"
            case .unflag: return "Unflag"
            case .markAsUnread: return "Mark as Unread"
            case .markAsRead: return "Mark as Read"
            }
        }
    }

    /// The sheet's last button, which changes nothing. On the iPad the
    /// sheet is a popover under the Flag button, and a tap outside it is
    /// its Cancel, as for Reply's.
    static let cancel = "Cancel"

    /// The items, in their order, for the letter the toolbar acts on:
    /// whether it is flagged, whether it is read, and whether it is a
    /// letter kept on the iPad (a draft in Drafts or a letter in the
    /// Outbox), which has no read mark on the server to change and gets
    /// Flag alone.
    ///
    /// `read` is the dot on the list's row where the list has the letter
    /// (`Dot`), and never the pane's own `summary.isRead`, which it was
    /// handed before the tap that opened the letter marked it read. Where
    /// the list has no row that is the letter, a hit after its search
    /// has ended, the pane's: read, since opening it marked it read,
    /// unless the pane marked it unread itself
    /// (`MessageDetailViewController.markedUnreadHere`).
    static func items(flagged: Bool, read: Bool, local: Bool) -> [Item] {
        let flag: Item = flagged ? .unflag : .flag
        guard !local else { return [flag] }
        return [flag, read ? .markAsUnread : .markAsRead]
    }

    /// The dot on the list's row for the letter the sheet is for
    /// (`ListLetters.dot(on:)`): which read item the sheet offers, and
    /// whether it is greyed.
    struct Dot: Equatable {
        /// No dot: the letter is read, and the sheet offers Mark as Unread.
        var read: Bool
        /// A read mark on the letter is on its way to the server, from the
        /// tap that opened it, say, its STORE still waiting on the wire. The
        /// sheet greys its read item meanwhile, as it does while its own is
        /// on its way: the list answers a read mark by the letter's id, and
        /// the answer to the first of two on their way at once would act on
        /// the second.
        var onItsWay: Bool
    }

    /// The flag on the list's row for the letter the sheet is for
    /// (`ListLetters.flag(on:)`): Flag or Unflag, and whether it is
    /// greyed. A drag's Flag on the row (B-156) leaves the pane as it was.
    struct Flag: Equatable {
        var flagged: Bool
        /// A Flag on the letter is on its way to the server, from a drag,
        /// More or the pane: one at a time, as the pane's own.
        var onItsWay: Bool
    }
}
