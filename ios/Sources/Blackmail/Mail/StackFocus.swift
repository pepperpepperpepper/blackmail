import Foundation

/// Which letter of the conversation on screen the reading pane's header and
/// its toolbar are on, and when a letter takes them (B-129).
///
/// The header names one letter of the stack, and Reply, Flag, Move and
/// Delete act on it: the newest as the stack opens, then each letter he
/// opens by its line. A letter he opened used to take them only once its
/// body had come. For the fetch the header and the toolbar stayed on the
/// letter before, so a Flag or a Delete tapped then went to that one, and
/// a letter with a different number of files, or a Cc where the last had
/// none, moved the stack when it came. And a letter opened again, whose
/// body was in the stack already, took them at once, so a letter he had
/// opened before it and was still coming took them back when it landed:
/// the header named a letter he had left, and Reply answered it.
///
/// Now a letter takes them at the tap, as the single letter's pane has
/// since P1 (B-041): from its row, its sender, To, Cc, subject, date and
/// files, with Flag, Move and Delete on it and Reply held until its body
/// has come; whole at once if its body is in the stack already. A body
/// landing makes the header whole, and Reply live, for the letter he opened
/// last alone. The last letter he opened owns the header.
///
/// Out of the controller, which is UIKit and does not build on the host,
/// for the reason `PaneLoads` is: a rule that lived there could be undone
/// with every test green.
struct StackFocus: Equatable {

    /// The letter the header and the toolbar are on, by its id: the newest
    /// as the stack opens, then the one he opened last. Nil when the pane
    /// shows no conversation.
    private(set) var letter: String?

    /// What the header shows of a letter he has just opened by its line.
    enum Heading: Equatable {
        /// Its row's, Reply held, until its body lands.
        case row
        /// The letter itself, its body in the stack already.
        case letter
    }

    /// No conversation, or one opening on `newest`, whose row the header
    /// is drawn from until its body lands.
    init(opening newest: String? = nil) {
        letter = newest
    }

    /// He opened a letter by its line: it takes the header and the toolbar
    /// now, the letter itself if its body is in the stack already (`kept`),
    /// its row if not.
    mutating func opened(_ id: String, kept: Bool) -> Heading {
        letter = id
        return kept ? .letter : .row
    }

    /// A letter's body has landed: whether it makes the header whole and
    /// Reply its own. Only the letter he opened last: one opened before it,
    /// still coming when he opened another, lands in its section and leaves
    /// the header and the toolbar alone.
    func takes(_ id: String) -> Bool {
        letter == id
    }
}
