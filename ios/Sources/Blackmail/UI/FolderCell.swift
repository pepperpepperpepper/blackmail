// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

/// A folder's row, in the Mailboxes and in the Move sheet (B-166).
///
/// At Large, the size an iPad comes with, every row is the 44 points it
/// always was, the table's `rowHeight`. At any other text size a row is
/// as tall as its name needs, never under the rows' height at that size
/// (`Theme.mailboxRowHeightScaled`): a name too long for the column goes
/// on to as many lines as it takes, the row growing with it, as Apple's
/// guidelines have a label do as the size grows ("Keep text truncation
/// to a minimum", Human Interface Guidelines, Typography, Supporting
/// Dynamic Type). Held at the rows' height, the larger icon and count
/// left a label's name too little of the column at the largest of the
/// seven sizes, and the Inbox's at the accessibility sizes in three
/// panes, and the second line had no room in the row: it was cut, or
/// drawn over the next row. Read in the code, not seen.
final class FolderCell: UITableViewCell {

    /// Sets `table`'s rows for the text size as it is now: at Large each
    /// `Theme.mailboxRowHeightScaled`, as they always were, the estimate
    /// UIKit's own; at any other size each as tall as its name, from an
    /// estimate of the rows' height.
    static func size(_ table: UITableView) {
        if Theme.textSize == .factory {
            table.rowHeight = Theme.mailboxRowHeightScaled
            table.estimatedRowHeight = UITableView.automaticDimension
        } else {
            table.rowHeight = UITableView.automaticDimension
            table.estimatedRowHeight = Theme.mailboxRowHeightScaled
        }
    }

    /// The row never under the rows' height while it is as tall as its
    /// name; off at Large, where the table's `rowHeight` is the row's.
    /// Just short of required, so that a row the table still has at its
    /// old height for a moment, as the size changes, is never a clash.
    private lazy var floor: NSLayoutConstraint = {
        let floor = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
        floor.priority = UILayoutPriority(999)
        return floor
    }()

    /// The floor at the text size as it is now: set as the row is filled.
    func holdFloor() {
        floor.constant = Theme.mailboxRowHeightScaled
        floor.isActive = Theme.textSize != .factory
    }
}

#endif
