import Foundation

/// A message-list row's colours as it is selected, pressed or ticked, as
/// Mail's (B-174, B-181).
///
/// Out of `MessageCell` for the reason `RowArrow` is: the cell is UIKit and
/// does not exist on the machine the suite runs on. The cell asks this at
/// every change of the three and draws what it says.
///
/// Mail's row of the letter in the reading pane is its tint, rgb(10, 132,
/// 255), with white words, as its ticked row in Edit mode is; Blackmail's
/// was the dark grey of a press, `Theme.selection`, rgb(38, 38, 38). Seen
/// in the comparison with Mail of 2026-10-29 (round r6-n-compare, C-1b, in
/// passing: Mail's open row orange under Smart Invert, its blue inverted,
/// and Blackmail's light grey). So the open row is drawn as a ticked one:
/// the blue ground, the names and the subject white as always, the grey
/// lines, the paperclip and the arrow in Mail's see-through grey, and the
/// unread dot and the conversation's mark white. A finger's press on a row
/// that is not selected keeps the dark grey: Mail's press was not seen.
/// Colours only: Mail's selection is a rounded tile set in from the
/// edges, Blackmail's runs edge to edge, and that is layout.
struct RowShade: Equatable {

    /// The ground UIKit shows under a selected or pressed row.
    enum Ground: Equatable {
        /// Mail's tint, `Theme.tintBlue`.
        case blue
        /// The grey of a press, `Theme.selection`.
        case grey
    }

    /// The ground to draw now, or nil to leave it as it is: neither
    /// selected nor pressed, a row whose ground UIKit is fading out after
    /// the selection has moved on, which is to fade in the colour it had,
    /// not turn grey first.
    let ground: Ground?
    /// The row's lines are drawn as on the blue: the see-through grey, the
    /// dot and the mark white. On every selected row, the letter in the
    /// pane out of Edit mode and a tick in it.
    let onBlue: Bool
    /// The row's own tick shows (`MessageCell.placeTick`): in Edit mode,
    /// on a ticked row and while a finger is down on one, which UIKit's
    /// edit control draws ticked as the row is pressed (B-174).
    let tick: Bool

    /// `selected`: the row is selected, the letter in the pane out of Edit
    /// mode and a tick in it. `pressed`: a finger is down on it. `ticks`:
    /// the list is in Edit mode.
    ///
    /// In Edit mode the ground is blue for a press too, as it has been
    /// since B-174: the press is a tick coming.
    init(selected: Bool, pressed: Bool, ticks: Bool) {
        if selected || (pressed && ticks) {
            ground = .blue
        } else if pressed {
            ground = .grey
        } else {
            ground = nil
        }
        onBlue = selected
        tick = ticks && (selected || pressed)
    }
}
