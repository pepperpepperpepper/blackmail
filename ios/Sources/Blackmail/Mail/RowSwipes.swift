import Foundation

/// Mail's Swipe Options (B-156): what a drag on a row of the list offers,
/// in Settings > Apps > Mail > Swipe Options on his iPad, and where his
/// account puts what he discards, its Advanced page's Move Discarded
/// Messages Into. Set here, in one place, as `his`.
///
/// Mail's own values for Swipe Left and Swipe Right are None, Mark as Read,
/// Flag, Move Message and Archive; Swipe Left comes as Flag and Swipe
/// Right as Mark as Read. The Trash, or the Archive when the account
/// discards into it, is always the last button of a drag to the left and
/// what a full drag does, whatever Swipe Left says, and More is always
/// beside it (Apple's iPadOS 18 guide, "Manage an email with a swipe";
/// Apple's article 102428, "you might see Archive instead of Trash").
///
/// Built to Mail's factory values. His own are to be read off his iPad
/// before the last build (docs/TODO.md, "His iPad's own settings"), and
/// set in `his`: nothing else changes for any of them.
struct SwipeOptions: Equatable {

    /// What Swipe Left or Swipe Right can be set to.
    enum Choice: Equatable, CaseIterable {
        case none
        /// Mark as Read, or Mark as Unread on a row with no dot.
        case mark
        /// Flag, or Unflag on a flagged row.
        case flag
        /// Move Message: the folder sheet, as Edit mode's Move.
        case move
        /// Into Gmail's All Mail, out of the folder the row is in.
        case archive
    }

    /// Where the account puts what he discards.
    enum Discard: Equatable {
        /// Gmail's Trash, as Blackmail's Delete does.
        case trash
        /// The Archive mailbox, Gmail's All Mail.
        case archive
    }

    var swipeLeft: Choice
    var swipeRight: Choice
    var discardInto: Discard

    /// Mail as it comes, but for the discard target: the Trash, which is
    /// what Blackmail's Delete has always done. Mail's own for a Gmail
    /// account is said to be the Archive, and the numbers in his Trash
    /// suggest his is the Trash; it is to be read off his iPad.
    static let factory = SwipeOptions(swipeLeft: .flag, swipeRight: .mark, discardInto: .trash)

    /// His. Mail's factory values until his own have been read.
    static let his = factory
}

/// What a drag on a row of the message list offers (B-156), as iPadOS 18
/// Mail does with `SwipeOptions`: a slow drag to the left shows More, the
/// Swipe Left choice and the Trash, the Trash at the row's right edge, and
/// a full drag to the left does the Trash at once, with no question, as
/// Mail does whatever Ask Before Deleting says; a drag to the right shows
/// the Swipe Right choice, Mark as Read or Mark as Unread as the row is,
/// and a full drag does it.
///
/// Nothing in Edit mode, where a row is ticked, nor on a letter on this
/// iPad only, in Drafts or the Outbox, which is not on the server.
///
/// Inside Trash the Trash is Delete, which erases, and asks first as
/// Blackmail's Delete there always has (`EraseQuestion`), the full drag
/// too. What Mail shows and asks there is not known: its Select bar says
/// Delete inside Trash (item 7554), and a full drag there was not seen.
///
/// The actions go as Edit mode's go, on every letter of the row's
/// conversation (`MessageListViewController`).
///
/// Apart from the controller, which is UIKit and does not exist on the
/// machine the suite runs on, so what is offered, in what order and in what
/// words, is pinned on the host.
enum RowSwipes {

    enum Action: Equatable {
        /// To Gmail's Trash: Blackmail's Delete, as the Edit bar's.
        case trash
        /// Inside Trash, where Delete erases.
        case delete
        case archive
        case flag
        case unflag
        case markRead
        case markUnread
        case move
        case more

        /// Mail's words on the button.
        var title: String {
            switch self {
            case .trash: return "Trash"
            case .delete: return "Delete"
            case .archive: return "Archive"
            case .flag: return "Flag"
            case .unflag: return "Unflag"
            case .markRead: return "Read"
            case .markUnread: return "Unread"
            case .move: return "Move"
            case .more: return "More"
            }
        }

        /// The SF Symbol over the words, as Mail's buttons have one.
        var symbol: String {
            switch self {
            case .trash, .delete: return "trash.fill"
            case .archive: return "archivebox.fill"
            case .flag: return "flag.fill"
            case .unflag: return "flag.slash.fill"
            case .markRead: return "envelope.open.fill"
            case .markUnread: return "envelope.badge.fill"
            case .move: return "folder.fill"
            case .more: return "ellipsis.circle.fill"
            }
        }
    }

    /// The row, as what it offers depends on it.
    struct Row: Equatable {
        /// No dot: every letter of the conversation read.
        var read: Bool
        /// Any letter of it flagged, as the row's flag says.
        var flagged: Bool
        /// The role of the folder its letters are listed from: an All
        /// Mailboxes hit's own folder, not the list's.
        var role: Mailbox.Role?
        /// A letter kept on this iPad, in Drafts or the Outbox.
        var onThisIPadOnly: Bool
        /// There is an All Mail to file it in, and it is not listed from it.
        var canArchive: Bool
    }

    /// What each side shows, the button at the row's edge first, which is
    /// the one a full drag does, as UIKit takes them.
    struct Sides: Equatable {
        /// A drag to the left, the buttons at the row's right edge.
        var left: [Action]
        /// A drag to the right, at its left edge.
        var right: [Action]

        static let none = Sides(left: [], right: [])
    }

    static func sides(for row: Row, editing: Bool, options: SwipeOptions = .his) -> Sides {
        guard !editing, !row.onThisIPadOnly, row.role != .outbox else { return .none }
        let discard = self.discard(for: row, options: options)
        var left = [discard]
        if let chosen = action(for: options.swipeLeft, on: row), chosen != discard {
            left.append(chosen)
        }
        left.append(.more)
        return Sides(left: left, right: action(for: options.swipeRight, on: row).map { [$0] } ?? [])
    }

    /// What discards the row, at the edge of a drag to the left and in
    /// More's sheet: Delete inside Trash, where it erases; the Archive where
    /// the account discards into it and there is an All Mail to archive
    /// into; the Trash otherwise.
    static func discard(for row: Row, options: SwipeOptions = .his) -> Action {
        if row.role == .trash { return .delete }
        if options.discardInto == .archive, row.canArchive { return .archive }
        return .trash
    }

    /// A Swipe Left or Swipe Right choice, as the row is; nil for None, and
    /// for Archive where there is nothing to archive into.
    static func action(for choice: SwipeOptions.Choice, on row: Row) -> Action? {
        switch choice {
        case .none: return nil
        case .mark: return row.read ? .markUnread : .markRead
        case .flag: return row.flagged ? .unflag : .flag
        case .move: return .move
        case .archive: return row.canArchive ? .archive : nil
        }
    }
}

/// The sheet More opens from a drag on a row (B-156): Mail's sheet for the
/// letter, with the actions Blackmail has. Reply, Reply All and Forward
/// answer the conversation's newest letter, as the reading pane's Reply
/// answers the letter it shows; Trash Message, or Archive Message where
/// the account discards into the Archive, is the drag's own Trash, and
/// inside Trash Delete Message, which asks first; Flag or Unflag, and Mark
/// as Unread or Mark as Read, as the row is, and Move Message, go on every
/// letter of the conversation, as Edit mode's do. In the order of Mail's
/// sheet and of its Reply menu: Reply, Reply All, Forward, Trash, Flag,
/// Mark, Move (Gadget Hacks, 2019; the popover of INVESTIGATIONS' ban 5).
///
/// Mail's sheet has more besides: its Junk item, which comes with the
/// branch that builds it (B-106) and is added here when that is merged;
/// and Mute, Notify Me and Print, which Blackmail does not have from the
/// list. Its word inside Trash was not found.
enum RowMore {

    enum Item: Equatable {
        case reply
        case replyAll
        case forward
        case trashMessage
        case archiveMessage
        /// Inside Trash, where it erases.
        case deleteMessage
        case flag
        case unflag
        case markAsUnread
        case markAsRead
        case moveMessage

        var title: String {
            switch self {
            case .reply: return "Reply"
            case .replyAll: return "Reply All"
            case .forward: return "Forward"
            case .trashMessage: return "Trash Message"
            case .archiveMessage: return "Archive Message"
            case .deleteMessage: return "Delete Message"
            case .flag: return FlagMenu.Item.flag.title
            case .unflag: return FlagMenu.Item.unflag.title
            case .markAsUnread: return FlagMenu.Item.markAsUnread.title
            case .markAsRead: return FlagMenu.Item.markAsRead.title
            case .moveMessage: return "Move Message"
            }
        }
    }

    /// The sheet's last button, which changes nothing; on the iPad a tap
    /// outside the popover is its Cancel.
    static let cancel = "Cancel"

    static func items(for row: RowSwipes.Row, options: SwipeOptions = .his) -> [Item] {
        let discard: Item
        switch RowSwipes.discard(for: row, options: options) {
        case .delete: discard = .deleteMessage
        case .archive: discard = .archiveMessage
        default: discard = .trashMessage
        }
        return [.reply, .replyAll, .forward, discard, row.flagged ? .unflag : .flag,
                row.read ? .markAsUnread : .markAsRead, .moveMessage]
    }
}
