// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

/// The permanent first pane: the folder list.
///
/// Always on screen in three panes, never pushed over and never returned
/// to, so there is no `< Mailboxes` button and no state in which the folder
/// you are reading is hidden from you. That is the whole argument for the
/// third pane: "which folder am I in" becomes a thing you look at rather
/// than remember. In two panes, his choice (D-015), it shares the left
/// column with the list, behind "< Mailboxes", 375 pt wide, with the open
/// folder still highlighted when he goes back to it.
///
/// The cost is width — 250 pt on an 1194 pt iPad against the 370 pt the
/// two-pane layout gave it — so a long subfolder name truncates sooner here
/// than it did. Selection stays visible (see `didSelectRowAt`) precisely
/// because a truncated name still needs to show which one is current.
final class MailboxListViewController: UITableViewController {

    var onSelectMailbox: ((Mailbox) -> Void)?

    private let repository: MailRepository
    private var mailboxes: [Mailbox] = []
    /// How many letters wait in the Outbox (B-052). Its row is listed only
    /// while there are any, as Mail's is.
    private var outboxCount = LocalDrafts.shared.outbox.count
    /// The folder the highlight is on, so a sweep's `reloadData`, which
    /// drops the selection, can put it back.
    private var highlightedID: String?
    /// The counts, one sweep at a time; see `SweepCoalescer`. That is also
    /// what keeps two sweeps from landing oldest-last and visibly reverting
    /// the counts, which a generation number used to guard here.
    ///
    /// Held from the start: at launch the Inbox's first page goes before
    /// any count. The container lets them go (`releaseSweeps`) once that
    /// page has been tried, and drops the launch's sweep if it failed.
    private lazy var sweeps = SweepCoalescer(held: true) { [weak self] quietly in
        await self?.sweepOnce(quietly: quietly)
    }

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
        NotificationCenter.default.addObserver(self, selector: #selector(outboxChanged),
                                               name: LocalDrafts.changed,
                                               object: LocalDrafts.shared)
        // The folders as the last sweep counted them, kept on the iPad
        // (D-016), in the first frame and with no connection. They stand
        // until a sweep lands; the names alone never go over them
        // (`showFolders`), and they are not counts the watch compares with
        // the server's (`inboxUnread`).
        if let kept = repository.shelf?.folders {
            mailboxes = kept
            // Loaded now, so the highlight the container puts on the Inbox
            // straight after has a row to go on.
            tableView.reloadData()
        }

        // Refresh is NOT here. It used to be, and in a 250 pt pane it left only
        // 8.5 pt between "Mailboxes" and the button — measured on device. It
        // now lives in the message list's bottom bar, beside "Updated Just
        // Now", which is both roomier and more sensible: the label states the
        // freshness and the button next to it acts on exactly that. `PRODUCT_SPEC.md`'s
        // point stands either way — a visible labelled control, never
        // pull-to-refresh alone, because a gesture you have to know about is
        // not a control.
    }

    /// The folders' names from LIST alone, drawn while the counts wait.
    ///
    /// At launch the pane was empty until every folder's STATUS had come
    /// back, and those went before the Inbox. The names cost nothing extra
    /// now: the Inbox needs the same LIST to find its role, and shares it.
    /// Never over a sweep that has landed, which has the counts as well.
    @MainActor
    func showFolders() async {
        guard let names = try? await repository.folders(), mailboxes.isEmpty else { return }
        show(names)
    }

    /// Asks for the unread counts: LIST and a STATUS per folder. Merged with
    /// a sweep already running, and with every other request made while it
    /// runs, into at most one more. `quietly` for a sweep he did not ask
    /// for, the watch's, whose failure puts up no alert; see
    /// `SweepCoalescer.request(quietly:)`.
    @MainActor
    func refreshCounts(quietly: Bool = false) {
        sweeps.request(quietly: quietly)
    }

    /// Lets the counts go at launch, once the Inbox's first page has been
    /// tried. A request made before this waits for it, and is dropped if
    /// the page could not be fetched: the sweep would only connect again
    /// straight after the connect that failed. See
    /// `SweepCoalescer.release(runningOwed:)`.
    @MainActor
    func releaseSweeps(firstPageCame: Bool) {
        sweeps.release(runningOwed: firstPageCame)
    }

    @MainActor
    private func sweepOnce(quietly: Bool) async {
        do {
            show(try await repository.listMailboxes())
            counted = true
        } catch {
            if !quietly { ErrorPresenter.show(reaching: error, on: self) }
        }
    }

    @MainActor
    private func show(_ fresh: [Mailbox]) {
        mailboxes = fresh
        tableView.reloadData()
        if let highlightedID { select(mailboxID: highlightedID) }
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
    ///
    /// A sweep still on its way may have counted these folders before the
    /// change reached the server, and would put the old count back when it
    /// lands; so one more is asked for, whether or not the arithmetic
    /// changed anything here. At launch it often does not: the letter he
    /// reads first is read while the pane still has names and no counts.
    @MainActor
    func adjustUnreadCounts(_ mailboxIDs: [String], by delta: Int) {
        sweeps.requestIfRunning()
        // The kept counts too, so the next launch draws these (D-016).
        repository.shelf?.counted(mailboxIDs, by: delta)
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
    ///
    /// The Outbox, while letters wait in it, is a block of its own after
    /// the folders, so that coming and going it moves nothing above it.
    /// Where Mail puts it among its mailboxes was not checked.
    private var groups: [[Mailbox]] {
        let inbox = mailboxes.filter { $0.role == .inbox }
        let rest = mailboxes.filter { $0.role != .inbox }
        // Even with no folders listed, as after a launch with no
        // connection, when it is the one thing here worth seeing.
        let outbox = outboxCount > 0 ? [Outbox.mailbox(holding: outboxCount)] : []
        return [inbox, rest, outbox].filter { !$0.isEmpty }
    }

    /// The letters kept on the iPad have changed: the Outbox's row comes,
    /// goes or counts again. Drawn again only when its count has changed,
    /// with the highlight put back as a sweep puts it back.
    @objc private func outboxChanged() {
        let count = LocalDrafts.shared.outbox.count
        guard count != outboxCount else { return }
        outboxCount = count
        tableView.reloadData()
        if let highlightedID { select(mailboxID: highlightedID) }
    }

    /// The folder playing a given role, for callers that need to open one
    /// without the user having picked it — the date jump asking for "all
    /// mailboxes", which on Gmail means All Mail.
    func mailbox(for role: Mailbox.Role) -> Mailbox? {
        mailboxes.first { $0.role == role }
    }

    /// Every folder the pane last listed, for finding which one a letter
    /// was listed from.
    var folders: [Mailbox] { mailboxes }

    /// Whether a sweep has landed, so the numbers beside the folders are
    /// counts and not the zeros of names drawn without them.
    private var counted = false

    /// The Inbox's unread count as the pane shows it, nil until a sweep has
    /// given it one. What the watch compares the server's with while
    /// another folder is in front (`MailWatch.check`).
    var inboxUnread: Int? {
        counted ? mailbox(for: .inbox)?.unreadCount : nil
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
        content.text = mailbox.displayName
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

        cell.accessibilityLabel = mailbox.accessibilityLabel
    }

    /// The selected folder STAYS selected. In the reference "Junk" is still
    /// highlighted in this pane while its messages fill the next one, and that
    /// persistent highlight is the answer to "which folder am I in" — the
    /// question the third pane exists to make answerable by looking. Flashing
    /// the row and clearing it, which is right for a pane that gets pushed
    /// away, would throw that away.
    override func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        let chosen = groups[ip.section][ip.row]
        highlightedID = chosen.id
        onSelectMailbox?(chosen)
    }

    /// Moves the highlight to a folder, and keeps it there across the
    /// reloads that follow, since `reloadData` drops it. Remembered even
    /// when the folder is not on screen yet, as at launch before the first
    /// LIST, so the first reload puts it on.
    @MainActor
    func select(mailboxID: String) {
        highlightedID = mailboxID
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
        case .outbox:  return "tray.and.arrow.up"
        case nil:      return "folder"
        }
    }
}

#endif
