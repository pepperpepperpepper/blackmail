// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

/// The permanent first pane: the folder list.
///
/// Always on screen, never pushed over and never returned to, so there is no
/// `< Mailboxes` button and no state in which the folder you are reading is
/// hidden from you. That is the whole argument for the third pane: "which
/// folder am I in" becomes a thing you look at rather than remember.
///
/// The cost is width — 250 pt on an 1194 pt iPad against the 370 pt the
/// two-pane layout gave it — so a long subfolder name truncates sooner here
/// than it did. Selection stays visible (see `didSelectRowAt`) precisely
/// because a truncated name still needs to show which one is current.
final class MailboxListViewController: UITableViewController {

    var onSelectMailbox: ((Mailbox) -> Void)?

    private let repository: MailRepository
    private var mailboxes: [Mailbox] = []
    /// Bumped on every reload, so two overlapping server sweeps cannot land
    /// oldest-last and visibly revert the counts. The message list already
    /// guards the identical hazard with `previewGeneration`.
    private var reloadGeneration = 0

    init(repository: MailRepository) {
        self.repository = repository
        super.init(style: .plain)
        title = "Mailboxes"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Mailbox")
        tableView.rowHeight = Theme.mailboxRowHeightScaled
        tableView.backgroundColor = Theme.canvas
        tableView.separatorColor = Theme.separator
        tableView.separatorInset = UIEdgeInsets(top: 0, left: Theme.mailboxSeparatorInset,
                                                bottom: 0, right: 0)
        tableView.tableFooterView = UIView()

        // Refresh is NOT here. It used to be, and in a 250 pt pane it left only
        // 8.5 pt between "Mailboxes" and the button — measured on device. It
        // now lives in the message list's bottom bar, beside "Updated Just
        // Now", which is both roomier and more sensible: the label states the
        // freshness and the button next to it acts on exactly that. `PRODUCT_SPEC.md`'s
        // point stands either way — a visible labelled control, never
        // pull-to-refresh alone, because a gesture you have to know about is
        // not a control.
    }

    @MainActor
    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        do {
            let fresh = try await repository.listMailboxes()
            // A newer sweep started while this one was in flight. Its
            // snapshot is closer to the truth, so this one is discarded
            // rather than allowed to overwrite it — LIST plus one STATUS per
            // folder is nine round trips, and completion order is not
            // submission order.
            guard generation == reloadGeneration else { return }
            mailboxes = fresh
            tableView.reloadData()
        } catch {
            ErrorPresenter.show(.cannotConnect, on: self)
        }
    }

    /// Applies a local change to one or more folders' unread counts.
    ///
    /// The alternative was `RootViewController.refreshMailboxes()`, which
    /// issues a LIST plus a STATUS per folder — nine round trips on this
    /// account. Correct, and indefensible on every message tap.
    ///
    /// Note what this does NOT call: `reloadRows`. That deselects the row it
    /// reloads, and the row being adjusted is nearly always the folder
    /// currently open, so the persistent highlight this pane exists to
    /// provide would vanish the instant the first message in a folder was
    /// read. The visible cell is patched directly instead, exactly as
    /// `MessageListViewController.apply(_:)` does for the same reason.
    @MainActor
    func adjustUnreadCounts(_ mailboxIDs: [String], by delta: Int) {
        for id in mailboxIDs {
            guard let i = mailboxes.firstIndex(matchingMailboxID: id) else { continue }
            let updated = max(0, mailboxes[i].unreadCount + delta)
            guard updated != mailboxes[i].unreadCount else { continue }
            mailboxes[i].unreadCount = updated
            let path = IndexPath(row: i, section: 0)
            if let cell = tableView.cellForRow(at: path) {
                configure(cell, with: mailboxes[i])
            }
        }
    }

    /// The Inbox, then everything else — the two blocks classic Mail
    /// separates, and the gap `Theme.mailboxSectionGap` provides.
    ///
    /// It is a grouping and not a sort: `mailboxes` already arrives in the
    /// order the repository ranked it, and the folders block keeps that
    /// order exactly. Empty blocks are dropped so an account with nothing
    /// but an Inbox does not show a gap under it and nothing after.
    private var groups: [[Mailbox]] {
        let inbox = mailboxes.filter { $0.role == .inbox }
        let rest = mailboxes.filter { $0.role != .inbox }
        return [inbox, rest].filter { !$0.isEmpty }
    }

    /// The folder playing a given role, for callers that need to open one
    /// without the user having picked it — the date jump asking for "all
    /// mailboxes", which on Gmail means All Mail.
    func mailbox(for role: Mailbox.Role) -> Mailbox? {
        mailboxes.first { $0.role == role }
    }

    override func numberOfSections(in t: UITableView) -> Int { groups.count }

    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int {
        groups[s].count
    }

    override func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = t.dequeueReusableCell(withIdentifier: "Mailbox", for: ip)
        configure(cell, with: groups[ip.section][ip.row])
        return cell
    }

    /// The gap itself. A footer under every block but the last, so the
    /// space sits BETWEEN the two and not below the folders as well.
    override func tableView(_ t: UITableView, heightForFooterInSection s: Int) -> CGFloat {
        s < groups.count - 1 ? Theme.mailboxSectionGap : 0
    }

    override func tableView(_ t: UITableView, viewForFooterInSection s: Int) -> UIView? {
        guard s < groups.count - 1 else { return nil }
        let spacer = UIView()
        spacer.backgroundColor = Theme.canvas
        return spacer
    }

    /// Fills a cell. Factored out of `cellForRowAt` so a count change can
    /// repaint a cell in place without going through a reload.
    private func configure(_ cell: UITableViewCell, with mailbox: Mailbox) {
        var content = cell.defaultContentConfiguration()
        content.text = mailbox.name
        content.textProperties.font = Theme.fontMailboxName
        content.textProperties.color = Theme.primaryText
        content.image = UIImage(systemName: icon(for: mailbox.role))
        content.imageProperties.tintColor = Theme.tintBlue
        content.directionalLayoutMargins.leading =
            Theme.mailboxIconCenterX - 11 + CGFloat(mailbox.depth) * Theme.mailboxIndentStep
        cell.contentConfiguration = content

        // Unread count on the right, as a plain label. Not a badge: a grey
        // number is quieter and reads the same at any size.
        if mailbox.unreadCount > 0 {
            let label = UILabel()
            label.text = "\(mailbox.unreadCount)"
            label.font = Theme.fontMailboxCount
            label.textColor = Theme.mailboxCountText
            label.sizeToFit()
            cell.accessoryView = label
        } else {
            cell.accessoryView = nil
        }

        let selected = UIView()
        selected.backgroundColor = Theme.selection
        cell.selectedBackgroundView = selected

        cell.accessibilityLabel = mailbox.unreadCount > 0
            ? "\(mailbox.name), \(mailbox.unreadCount) unread"
            : mailbox.name
    }

    /// The selected folder STAYS selected. In the reference "Junk" is still
    /// highlighted in this pane while its messages fill the next one, and that
    /// persistent highlight is the answer to "which folder am I in" — the
    /// question the third pane exists to make answerable by looking. Flashing
    /// the row and clearing it, which is right for a pane that gets pushed
    /// away, would throw that away.
    override func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        onSelectMailbox?(groups[ip.section][ip.row])
    }

    /// Restores the highlight after a reload, since `reloadData` drops it.
    @MainActor
    func select(mailboxID: String) {
        // Matching, not `==`. The caller passes whatever the message pane is
        // holding, which at launch is the role word "inbox" while this array
        // holds the LIST name "INBOX" — so this silently did nothing and the
        // Inbox row was never highlighted. Measured on device before the fix:
        // background 12.8 for the supposedly-selected row against 51.1 for a
        // genuinely selected one.
        // Across both blocks now, not just the first.
        let blocks = groups
        for (section, block) in blocks.enumerated() {
            guard let row = block.firstIndex(matchingMailboxID: mailboxID) else { continue }
            tableView.selectRow(at: IndexPath(row: row, section: section),
                                animated: false, scrollPosition: .none)
            return
        }
    }

    private func icon(for role: Mailbox.Role?) -> String {
        switch role {
        case .inbox:   return "tray"
        case .sent:    return "paperplane"
        case .drafts:  return "doc"
        case .trash:   return "trash"
        case .archive: return "archivebox"
        case .junk:    return "xmark.bin"
        case nil:      return "folder"
        }
    }
}

#endif
