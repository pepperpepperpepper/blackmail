import Foundation

/// What is asked before a Trash or an Archive under Mail's Ask Before
/// Deleting (B-168), and when.
///
/// Mail, with the setting on, asks before it trashes or archives a letter:
/// a sheet at the button tapped, with one red button saying what it does,
/// and Cancel, which on the iPad is a tap outside it. Its words are its
/// strings (iOS 18.6): "Trash Message" and "Archive Message" for a letter
/// (`TRASH_EMAIL`, `ARCHIVE_EMAIL`), "Trash Messages" and "Archive
/// Messages" for a conversation of more (`_PLURAL`), and "Trash 3
/// Messages", counted, for a selection (`TRASH_FORMAT`, `ARCHIVE_FORMAT`).
/// Which is put up where is read from their names, not seen. A full drag
/// on a row does not ask, whatever the setting says (Apple's guides, and
/// the users who write about it): it goes at once, as it does with the
/// setting off (`RowSwipes`).
///
/// So here: the reading pane's Delete, the Edit bar's Trash, a button a
/// slow drag on a row shows, Trash or Archive, and the same in More's
/// sheet ask; a full drag does not. Inside Trash, where Delete erases,
/// `EraseQuestion` is asked, as it always has been, setting or none, and
/// this is not asked as well. Off, as it comes (`MessagesOptions`), nothing
/// is asked but that.
///
/// Out of the controllers, which are UIKit and do not exist on the machine
/// the suite runs on, so the words and the rule are pinned on the host;
/// `DiscardConfirmation` puts it up.
struct DiscardQuestion: Equatable {
    /// The red button, which does it.
    let button: String

    /// The other, which leaves everything as it was; on the iPad, a tap
    /// outside the sheet.
    static let cancel = "Cancel"

    /// What the tap does to the letters.
    enum Verb: Equatable {
        /// To Gmail's Trash.
        case trash
        /// Into the Archive, Gmail's All Mail.
        case archive
    }

    /// Where it was asked for.
    enum From: Equatable {
        /// The reading pane's Delete, on the letter it shows.
        case pane
        /// The Edit bar's Trash, on the letters ticked.
        case editBar
        /// A button a slow drag on a row shows, tapped.
        case rowButton
        /// More's sheet, from a slow drag on a row.
        case more
        /// A full drag on a row, which does its first button at once.
        case fullDrag
    }

    /// The question before `verb` of `count` letters from `from`, or nil
    /// when nothing is asked: Ask Before Deleting off (`asking`), or a full
    /// drag. A conversation's letters count each, as Edit mode takes them.
    static func before(_ verb: Verb, letters count: Int, from: From,
                       asking: Bool = MessagesOptions.askBeforeDeleting) -> DiscardQuestion? {
        guard asking, count > 0 else { return nil }
        let word = verb == .trash ? "Trash" : "Archive"
        switch from {
        case .fullDrag:
            return nil
        case .editBar:
            return DiscardQuestion(button: "\(word) \(count) " + (count == 1 ? "Message" : "Messages"))
        case .pane, .rowButton, .more:
            return DiscardQuestion(button: word + (count == 1 ? " Message" : " Messages"))
        }
    }

    /// Whether a drag's button was done by a full drag, not tapped: UIKit
    /// says the same to both, with the button's view, which a full drag
    /// has stretched across the row (`button` and `row`, the two widths).
    /// Taken as a tap unless it spans more than three fifths of the row, so
    /// a tap is never taken for a full drag; if UIKit has not stretched it
    /// by then, a full drag asks, which errs toward the question.
    static func fullDrag(button: Double, row: Double) -> Bool {
        row > 0 && button > row * 0.6
    }
}
