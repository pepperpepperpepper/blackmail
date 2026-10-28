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
/// Mail 16.5.1 on the test iPad, with the setting on, asked only for the
/// reading pane's Trash: a slow drag's Trash, More's Trash and a full drag
/// each trashed at once (the side-by-side round r6-i-compare, comparison
/// C-08, B-175). So here: the reading pane's Delete and the Edit bar's
/// Trash ask; a button a slow drag on a row shows, Trash or Archive, the
/// same in More's sheet, and a full drag do not. The Edit bar's was not
/// compared, and asks as B-168 made it. Inside Trash, where Delete erases,
/// `EraseQuestion` is asked, as it always has been, setting or none, and
/// this is not asked as well. Off, as it comes (`MailOptions`), nothing
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
    /// when nothing is asked: Ask Before Deleting off (`asking`), or a drag
    /// on a row, its button tapped or done by a full drag, or More's item
    /// (B-175). A conversation's letters count each, as Edit mode takes
    /// them.
    static func before(_ verb: Verb, letters count: Int, from: From,
                       asking: Bool = MailOptions.askBeforeDeleting) -> DiscardQuestion? {
        guard asking, count > 0 else { return nil }
        let word = verb == .trash ? "Trash" : "Archive"
        switch from {
        case .fullDrag, .rowButton, .more:
            return nil
        case .editBar:
            return DiscardQuestion(button: "\(word) \(count) " + (count == 1 ? "Message" : "Messages"))
        case .pane:
            return DiscardQuestion(button: word + (count == 1 ? " Message" : " Messages"))
        }
    }

    /// Whether a drag's button was done by a full drag, not tapped. UIKit
    /// says the same to both, so it is read from the drag itself: its pan
    /// has just ended (`panEnded`, its state as the button is done, in the
    /// turn the finger lifts), or it lifted no more than `liftWindow`
    /// seconds ago (`sinceLift`, nil for none since the list was shown).
    /// A slow drag that leaves the buttons open does nothing as it lifts,
    /// and a button tapped after it comes with a tap, not the pan, so a
    /// tap still asks.
    ///
    /// It was told by the button's width, a full drag being taken for one
    /// whose button UIKit had stretched over three fifths of the row; on
    /// the test iPad (2026-10-27) UIKit moves the row about six tenths of
    /// the finger's way, and a full drag's Trash was 53 to 56 per cent of
    /// the row as it went, so every full drag asked.
    static func fullDrag(panEnded: Bool, sinceLift: Double?) -> Bool {
        panEnded || (sinceLift.map { $0 >= 0 && $0 < liftWindow } ?? false)
    }

    /// How soon after a drag's lift its button counts as done by it: a
    /// third of a second, more than UIKit takes to do a full drag's button
    /// and less than a finger takes to come down again on a button.
    static let liftWindow = 0.3
}
