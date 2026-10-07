// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

extension UITableView {

    /// Where VoiceOver goes after "< Mailboxes" or a folder tap in two
    /// panes (B-079): the table's highlighted row if any of it is in sight;
    /// else, with `orFirstRow`, its first row wholly in sight, below the
    /// search band; else the table, whose first element VoiceOver then
    /// takes. Never nil. Left to choose, VoiceOver on iPadOS 16 went to the
    /// reading pane's Flag when a letter was open, and to the corner's view
    /// button when not.
    ///
    /// The table's column is shown and laid out by the time this is asked:
    /// the shell lays the panes out before it returns, hiding and showing
    /// them at once. The cover over them while they move is hidden from
    /// VoiceOver, and they are not inside it.
    func voiceOverPlace(orFirstRow: Bool) -> UIView {
        voiceOverPlace(at: indexPathForSelectedRow, orFirstRow: orFirstRow)
    }

    /// `row` if any of it is in sight; else, with `orFirstRow`, the first
    /// row wholly in sight; else the table. Also where VoiceOver goes in the
    /// list after its rows are drawn again under it (`ListVoiceOver`).
    ///
    /// In sight means between the table's bars and below the band pinned at
    /// its top. `visibleCells` counts the rows under them too: the first of
    /// them, once the list is scrolled, is under the search field, and
    /// VoiceOver put on it would scroll the list to show it.
    func voiceOverPlace(at row: IndexPath?, orFirstRow: Bool) -> UIView {
        let band = numberOfSections > 0 ? rectForHeader(inSection: 0).height : 0
        let top = bounds.minY + adjustedContentInset.top + band
        let bottom = bounds.maxY - adjustedContentInset.bottom
        if let row, row.section < numberOfSections, row.row < numberOfRows(inSection: row.section),
           rectForRow(at: row).maxY >= top + 1,
           rectForRow(at: row).minY <= bottom - 1,
           let cell = cellForRow(at: row) { return cell }
        if orFirstRow,
           let first = (indexPathsForVisibleRows ?? []).sorted().first(where: { row in
               let rect = rectForRow(at: row)
               return rect.minY >= top - 0.5 && rect.maxY <= bottom + 0.5
           }),
           let cell = cellForRow(at: first) { return cell }
        return self
    }
}

#endif
