import Foundation

/// Where a row of the message list puts the three things on its top line,
/// across: the names, the date, and, on a row that has one, the mark of a
/// conversation, Mail's circled chevron after the date (B-075).
///
/// Out of `MessageCell` for the reason `PaneArrangement` is out of the
/// container: the cell is UIKit and does not exist on the machine the suite
/// runs on, and what this says is the part of a frozen row a mark could
/// move. The cell places each label by it, and its baseline as before.
///
/// The names get the left of the line and the date its right, as they
/// always have: up to 110 points for the date, less in a narrow list, and 8
/// between them. A mark changes the date's label and nothing else. It ends
/// at the text's right edge, as Mail's does, and the date ends `gap` before
/// it, inside the room the date always had, so the names are cut where they
/// always were, and can never push the mark off the line.
struct RowTopLine: Equatable {

    /// The names' label: its left edge and width.
    let namesX: CGFloat
    let namesWidth: CGFloat
    /// The date's label, whose text is set to its right end.
    let dateX: CGFloat
    let dateWidth: CGFloat
    /// The mark's left edge, or nil on a row without one.
    let markX: CGFloat?

    /// The line between the text's `left` and `right` edges, with a mark
    /// `mark` points wide, or none, set `gap` after the date.
    init(left: CGFloat, right: CGFloat, mark: CGFloat?, gap: CGFloat) {
        let textWidth = right - left
        let stampWidth = min(110, textWidth * 0.45)
        namesX = left
        namesWidth = textWidth - stampWidth - 8
        dateX = right - stampWidth
        if let mark {
            markX = right - mark
            dateWidth = stampWidth - mark - gap
        } else {
            markX = nil
            dateWidth = stampWidth
        }
    }
}
