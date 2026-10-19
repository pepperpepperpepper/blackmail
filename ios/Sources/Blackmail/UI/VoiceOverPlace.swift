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
    /// its top (`TableSight`). `visibleCells` counts the rows under them
    /// too: the first of them, once the list is scrolled, is under the
    /// search field, and VoiceOver put on it would scroll the list to show
    /// it.
    func voiceOverPlace(at row: IndexPath?, orFirstRow: Bool) -> UIView {
        let sight = voiceOverSight
        if let row, holds(row), sight.showsPart(rectForRow(at: row).minY, rectForRow(at: row).maxY),
           let cell = cellForRow(at: row) { return cell }
        if orFirstRow,
           let first = (indexPathsForVisibleRows ?? []).sorted().first(where: { row in
               sight.showsWhole(rectForRow(at: row).minY, rectForRow(at: row).maxY)
           }),
           let cell = cellForRow(at: first) { return cell }
        return self
    }

    /// `row`, before VoiceOver is put on it, shown whole with the least
    /// scroll, if part of it is under the band or a bar (B-079). VoiceOver
    /// put on a row it cannot see whole scrolls the list itself, and on the
    /// iPad it put the row in the middle of the list, or took the list to
    /// its top, hundreds of points for a row 30 points under the search
    /// field. Nothing for a row wholly in sight, or with none of it in
    /// sight, which VoiceOver is not put on. Only while VoiceOver is
    /// running: with it off the list never moves for it.
    func showWhole(forVoiceOver row: IndexPath?) {
        guard UIAccessibility.isVoiceOverRunning, let row, holds(row) else { return }
        // Its rows as they are now, hidden or not: a reload only schedules
        // them.
        layoutIfNeeded()
        let rect = rectForRow(at: row)
        guard let offset = voiceOverSight.offset(showingWhole: rect.minY, rect.maxY) else { return }
        setContentOffset(CGPoint(x: contentOffset.x, y: offset), animated: false)
        layoutIfNeeded()
    }

    /// What of the table is in sight, for the sums in `TableSight`. The
    /// band is the first section's header, pinned at the top in the list;
    /// the folders have none.
    private var voiceOverSight: TableSight {
        TableSight(offset: contentOffset.y, height: bounds.height,
                   barTop: adjustedContentInset.top, barBottom: adjustedContentInset.bottom,
                   band: numberOfSections > 0 ? rectForHeader(inSection: 0).height : 0,
                   content: contentSize.height)
    }

    /// `row` is one of the table's rows as they are now.
    private func holds(_ row: IndexPath) -> Bool {
        row.section < numberOfSections && row.row < numberOfRows(inSection: row.section)
    }

    /// `row` is the table's last row, with no row after it in any section
    /// (`FoldersVoiceOver.isLast`). False for nil.
    func voiceOverIsLast(_ row: IndexPath?) -> Bool {
        guard let row else { return false }
        return FoldersVoiceOver.isLast(row.row, in: row.section,
                                       of: (0..<numberOfSections).map { numberOfRows(inSection: $0) })
    }

    /// The row of this table VoiceOver's `element` is: one of its cells,
    /// something inside one, or the element UIKit gives VoiceOver for a row,
    /// which is not a view and whose container is the table, found by where
    /// it is. Nil for anything else, the table itself too, and for UIKit's
    /// element in `band`, in the screen's points: the list's search field.
    func voiceOverRow(of element: Any, besides band: CGRect? = nil) -> IndexPath? {
        guard var view = UIView.voiceOverHolder(of: element) else { return nil }
        if view === self {
            // Found by where it is, among the rows, and not on the band.
            guard !(element is UIView), let frame = (element as? NSObject)?.accessibilityFrame else {
                return nil
            }
            let middle = CGPoint(x: frame.midX, y: frame.midY)
            if let band, band.contains(middle) { return nil }
            return (indexPathsForVisibleRows ?? []).first { row in
                UIAccessibility.convertToScreenCoordinates(rectForRow(at: row), in: self)
                    .contains(middle)
            }
        }
        while view !== self {
            if let cell = view as? UITableViewCell { return indexPath(for: cell) }
            guard let up = view.superview else { return nil }
            view = up
        }
        return nil
    }
}

extension UIView {

    /// The view VoiceOver's `element` is, or is in: itself, or the view its
    /// containers lead to. The element UIKit gives VoiceOver for a row is
    /// not a view, and its container is the table.
    static func voiceOverHolder(of element: Any) -> UIView? {
        var holder: Any? = element
        for _ in 0..<8 where !(holder is UIView) {
            holder = (holder as? UIAccessibilityElement)?.accessibilityContainer
        }
        return holder as? UIView
    }

    /// VoiceOver's `element` is this view or in it: the view it is or is in
    /// (`voiceOverHolder(of:)`) is this one or inside it. An element that
    /// leads to no view is found by where it is: the middle of its frame on
    /// this view's part of the screen, with nothing presented over the
    /// window. The letter's text is such an element (B-079): WebKit gives
    /// VoiceOver the page from its own process, and its elements are
    /// neither views nor UIKit's.
    func voiceOverHolds(_ element: Any) -> Bool {
        if let holder = UIView.voiceOverHolder(of: element) { return holder.isDescendant(of: self) }
        guard let window, window.rootViewController?.presentedViewController == nil,
              let frame = (element as? NSObject)?.accessibilityFrame else { return false }
        return UIAccessibility.convertToScreenCoordinates(bounds, in: self)
            .contains(CGPoint(x: frame.midX, y: frame.midY))
    }
}

#endif
