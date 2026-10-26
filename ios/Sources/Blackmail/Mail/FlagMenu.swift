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
/// Last, Move to Junk, as iOS 7 put it there and iPadOS 18's More Actions
/// has it, or Move to Inbox inside Junk, as Mail offers there: ruled
/// 2026-10-26, copying Mail. Mail's words, the folder named by its role, as
/// Mail shows Gmail's Spam as Junk; both titles are in `Item.title` and
/// nowhere else. Never in Edit mode's Mark sheet (D-022), where Select All
/// is the 30,000-letter accident and there is no Undo here.
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
        /// To the folder LIST names `\Junk`, Gmail's Spam.
        case moveToJunk(Mailbox)
        /// Out of Junk, to the Inbox LIST names.
        case moveToInbox(Mailbox)

        /// Mail's words, the ones Edit mode's Mark sheet already shows for
        /// the read mark.
        var title: String {
            switch self {
            case .flag: return "Flag"
            case .unflag: return "Unflag"
            case .markAsUnread: return "Mark as Unread"
            case .markAsRead: return "Mark as Read"
            case .moveToJunk: return "Move to Junk"
            case .moveToInbox: return "Move to Inbox"
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
    ///
    /// Then, by `role`, that of the folder the letter was listed from, and
    /// the folders LIST named (`Folders`): Move to Junk for a letter
    /// anywhere but Junk, when a folder with the `\Junk` role is listed;
    /// Move to Inbox for one in Junk, when the Inbox is listed. Neither for
    /// a letter kept on the iPad, nor without the folder: Gmail lists Spam
    /// only while its "Show in IMAP" is on, and no name is ever guessed.
    static func items(flagged: Bool, read: Bool, local: Bool,
                      in folders: Folders = Folders()) -> [Item] {
        let flag: Item = flagged ? .unflag : .flag
        guard !local else { return [flag] }
        var items = [flag, read ? .markAsUnread : .markAsRead]
        if folders.role != .junk, let junk = folders.junk {
            items.append(.moveToJunk(junk))
        } else if folders.role == .junk, let inbox = folders.inbox {
            items.append(.moveToInbox(inbox))
        }
        return items
    }

    /// Where the letter is, and where Move to Junk and Move to Inbox go:
    /// the role of the folder the letter was listed from, which for an All
    /// Mailboxes hit is not the list's, and the folders LIST named with the
    /// `\Junk` role and the Inbox's, nil where there is none.
    struct Folders: Equatable {
        var role: Mailbox.Role?
        var junk: Mailbox?
        var inbox: Mailbox?
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
}
