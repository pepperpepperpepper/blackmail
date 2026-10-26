import Foundation

/// The parts of a message-list row its cell is drawn with, and which of
/// them the list draws at each moment it draws a cell (B-139, B-143).
///
/// Out of `MessageListViewController` for the reason `RowTopLine` is out of
/// the cell: the controller is UIKit and does not exist on the machine the
/// suite runs on. It draws every cell by these (`draw(_:at:_:)`), and the
/// suite runs them over a model of the table.
///
/// The list draws a cell at five moments. At two the cell is drawn whole
/// from its row as it is then: as the table makes it (`cellForRowAt`,
/// `made`) and as it comes into sight (`willDisplay`, `comingIntoSight`).
/// At the other three the cells of the rows in sight are patched where they
/// are, so that no row is loaded again: the previews landing (`apply`,
/// `previewsLanded`), the dates' form, zone or day changing
/// (`datesChanged`), a draft tapped or come (`showDraftSpinners`,
/// `draftSpinners`). Loading a row again (`reloadRows`) would deselect it,
/// and on the iPad the selected row is the letter open in the pane.
///
/// Those three name the rows of `indexPathsForVisibleRows`. Since iOS 15
/// the table makes the cell for the row just past the edge ahead of time
/// (cell prefetching, on by default) and shows it later without asking for
/// it again, and that row is not among them. So whatever a patch draws, a
/// cell coming into sight draws too, from its row as it is then: a cell
/// made before a patch comes in as the patch would have left it. On the
/// test iPad (B-143) a row made past the bottom before its preview landed
/// came into sight with its two grey lines empty, and stayed so, since
/// B-135 never asks again for a preview the list holds: the cell coming in
/// had its date written again and nothing else (B-139's `writeDate`).
struct RowParts: OptionSet, Sendable {
    let rawValue: Int

    /// The row's lines as the row gives them: the names, the subject, the
    /// two preview lines, the unread dot, the arrow, the paperclip, the
    /// flag and the mark of a conversation, and the date with them
    /// (`MessageCell.configure`).
    static let lines = RowParts(rawValue: 1 << 0)
    /// The date alone, written again from the cell's own
    /// (`MessageCell.drawDate`, B-139). Drawn with `lines` too.
    static let date = RowParts(rawValue: 1 << 1)
    /// The spinner of a draft on its way to the composer
    /// (`MessageCell.isBusy`).
    static let busy = RowParts(rawValue: 1 << 2)
    /// What VoiceOver reads of the row, its date among it.
    static let label = RowParts(rawValue: 1 << 3)

    /// Every part: the row as a cell made for it now shows it.
    static let whole: RowParts = [.lines, .date, .busy, .label]

    /// A cell the table makes for a row, in sight or ahead of it.
    static let made: RowParts = .whole
    /// A cell coming into sight, made just now or ahead of time, before a
    /// patch it was not among (B-143).
    static let comingIntoSight: RowParts = .whole
    /// The rows in sight as a group's previews land.
    static let previewsLanded: RowParts = .whole
    /// The rows in sight as the dates' form, zone or day changes: the date
    /// and VoiceOver's words, nothing else (B-139).
    static let datesChanged: RowParts = [.date, .label]
    /// The rows in sight as a draft is tapped or has come: the spinner.
    static let draftSpinners: RowParts = [.busy]

    /// The patches drawn into the rows in sight alone. Each is drawn as a
    /// row comes into sight too (`comingIntoSight`), so none needs to reach
    /// a cell made ahead.
    static let patchesInSight: [RowParts] = [previewsLanded, datesChanged, draftSpinners]
}
