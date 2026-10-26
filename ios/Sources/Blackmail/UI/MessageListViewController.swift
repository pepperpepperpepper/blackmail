// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

/// The middle pane: the messages in one folder. In two panes (D-015), the
/// left column's, in turn with the folder list.
///
/// Swapped wholesale by `RootViewController` when a folder is chosen, never
/// pushed, so its navigation stack is always exactly one deep and UIKit's
/// back button never appears. In three panes the folder list it came from is
/// still on screen to its left; in two the container puts its own
/// "< Mailboxes" in front of the calendar (`itemsBeforeCalendar`).
final class MessageListViewController: UITableViewController {

    var onSelectMessage: ((MessageSummary) -> Void)?
    /// A conversation of more than one letter was chosen. The reading pane
    /// shows the whole stack; see B-022. With its Gmail thread number when
    /// his own letters of it are to be brought in from Sent Mail, nil
    /// otherwise (`CompleteThreads`, B-104).
    var onSelectThread: ((MessageThread, UInt64?) -> Void)?
    /// The rows have been drawn again from the letters: a letter come or
    /// gone, a page, a read mark. The reading pane puts letters that came
    /// into its conversation at the bottom of its stack (B-074).
    var onRegrouped: (() -> Void)?
    var onMessagesChanged: (() -> Void)?
    /// The folder counts, for his Refresh, which says so when they cannot
    /// be fetched, but for `quietly`, after a page that did not come, whose
    /// own alert says what failed (`RefreshTap.run`, B-103). His alone: a
    /// Save in Settings asks for none (B-085).
    var onRefreshRequested: ((_ quietly: Bool) -> Void)?
    /// Returns once the folder counts asked for have come, and at once when
    /// none is on its way (`MailboxListViewController.countsSwept`): his
    /// Refresh's pass waits for them (`RefreshTap`, B-072).
    var countsCame: () async -> Void = {}
    /// A new password was checked and saved in Settings, and Settings has
    /// gone: the screens are to be built again over a repository that signs
    /// in with it (`PasswordChange`), and to put up what the check had to
    /// say of it, if anything.
    var onPasswordSaved: ((MailAccount, String, MailAlert?) -> Void)?
    /// He asked to jump across ALL mailboxes from a pane showing one.
    ///
    /// Handed up rather than handled here, because a list IS a folder: its
    /// title, its unread count and every page it fetches are that folder's.
    /// Quietly filling an "Inbox" pane with All Mail would make the title a
    /// lie and the next page fetch walk the wrong mailbox. The container
    /// opens All Mail properly and jumps there.
    var onJumpAcrossMailboxes: ((Date) -> Void)?
    /// Fired when reading a message has changed the unread count of one or
    /// more folders. Several, on Gmail, where one message wears many labels.
    var onUnreadCountChanged: (([String], Int) -> Void)?
    /// Edit mode's Delete or Move, or a drag's (B-156), has taken these
    /// letters off the list, at the tap: the reading pane empties if it
    /// shows one of them.
    var onLettersLeaving: (([MessageSummary]) -> Void)?
    /// A Delete or Move from Edit mode or a drag that the server has taken,
    /// for Mail's Undo (B-157), with the list's letters it was taken from,
    /// which its rows go back to.
    var onUndoable: ((UndoableMove, ListLetters) -> Void)?
    /// More's Reply, Reply All or Forward on a row (B-156): the letter
    /// answered, whether to all, whether a forward, and where the row is,
    /// for Mail's question about its files. The reading pane makes the
    /// letter, as its Reply button's sheet does.
    var onAnswer: ((MessageSummary, Bool, Bool, (view: UIView, rect: CGRect)) -> Void)?
    /// The letters the reading pane shows, the one it opened first
    /// (`MessageDetailViewController.lettersShown`): the row that holds one
    /// is highlighted again where the table has dropped the highlight with
    /// the letter still open (`highlightLetterInPane`, B-133).
    var lettersInPane: () -> [String] = { [] }
    /// A letter Edit mode moved changed a count the list cannot work out
    /// itself, and the folder counts are to be swept (`ListBatch`), as for
    /// the reading pane's Move.
    var requestSweep: (() -> Void)?
    /// The folders the container has listed, for the role of the folder a
    /// letter was listed from (`role(of:)`). The list knows only its own,
    /// and an All Mailboxes hit can be from Trash or Spam.
    var folders: () -> [Mailbox] = { [] }

    /// The folder's letters and a search's hits, the ones taken off by a
    /// Delete or Move from the reading pane, and the reads billed to the
    /// folder counts. Scoped to this controller, which is rebuilt whenever
    /// the folder changes. The reading pane edits it directly (`PaneActions`).
    let letters = ListLetters()

    /// Lets the container restore the folder highlight after a reload.
    var mailboxID: String { mailbox.id }

    /// The folder this list is, for the container: whether it is the Inbox
    /// already, and the role of a letter listed from it.
    var shownMailbox: Mailbox { mailbox }

    private let repository: MailRepository
    private let mailbox: Mailbox
    /// His own addresses, which a row naming whom its letters are to leaves
    /// out of two or more (`RowNames.line`, B-075). Read once: a new
    /// account builds the screens again, and Settings' Save hands the list
    /// its account as saved, so an address added there leaves the rows at
    /// once (`showSettings`, found on the iPadOS 18 simulator, B-076).
    private lazy var mine = OwnAddresses(account: CredentialStore.loadAccount())
    private var searchBar: SearchHeaderView!
    private let emptyLabel = UILabel()
    private let statusLabel = UILabel()
    private var deleteItem: UIBarButtonItem!
    private var moveItem: UIBarButtonItem!
    private var markItem: UIBarButtonItem!
    private var selectAllItem: UIBarButtonItem!
    private var browseItems: [UIBarButtonItem] = []
    private var editItems: [UIBarButtonItem] = []
    private var jumpItem: UIBarButtonItem?

    /// What the container puts in the leading slot in front of the
    /// calendar: in two panes the view button and "< Mailboxes", in three
    /// nothing. The calendar stays the last of them, beside the title, and
    /// is never replaced.
    var itemsBeforeCalendar: [UIBarButtonItem] = [] {
        didSet {
            guard itemsBeforeCalendar != oldValue else { return }
            placeLeadingItems()
        }
    }

    private func placeLeadingItems() {
        navigationItem.setLeftBarButtonItems(itemsBeforeCalendar + [jumpItem].compactMap { $0 },
                                             animated: false)
    }

    /// Bumped when the list is REPLACED — a reload, or a search changing
    /// what is on screen. Deliberately NOT bumped when a page is appended:
    /// appending leaves every existing row exactly where it was, so a
    /// preview fetch already in flight for those rows is still valid and
    /// cancelling it would blank the page he is looking at to fill in the
    /// one below it.
    private var listGeneration = 0

    /// How many messages a page is. Fifty is what the list opens with and
    /// what each scroll-triggered load adds.
    private static let pageSize = 50

    /// One page fetch at a time. `willDisplay` fires for every row that
    /// scrolls into view, so without this a flick would start a dozen.
    private var isLoadingPage = false
    /// The same, for the upward direction. Separate rather than shared: a
    /// list opened at a date can be near both ends at once on a short
    /// folder, and one flag would let whichever direction started first
    /// block the other permanently.
    private var isLoadingPrevious = false
    /// Set when the server returns a short page, which is how "there is no
    /// more" is spelled. Stops an endless walk off the bottom of a folder.
    private var reachedOldestMessage = false
    /// The other end, and normally TRUE: a list that opens at the newest
    /// message has nothing above it, and until the date jump existed there
    /// was no way for that to be false.
    private var reachedNewestMessage = true
    /// The footer that says what paging is doing.
    private let pageFooter = UIButton(type: .system)

    /// Where search is looking, and what it is looking for. Held here as
    /// well as in the band because a scope change has to re-run the search
    /// the field already contains.
    private var searchQuery = ""
    private var searchScope: MailSearchScope = .allMailboxes
    /// Cancels the previous keystroke's pending search. See `runSearch`.
    private var searchDebounce: Task<Void, Never>?
    /// The words whose results the list shows, which a letter opened from
    /// them keeps among his recent searches (B-105). Not `searchQuery`,
    /// which is ahead of them while more typing waits for its search.
    private var searchShown = ""

    /// Where the folder's letters were while a search shows in their place,
    /// and where a replaced list goes. See `ListPlaces`.
    private var places = ListPlaces()

    /// What the line under the list says. See `StatusLine`.
    private var status = StatusLine(resting: UpdatedLine().text(now: Date()))

    /// When this list was last brought up to date, and whether the last try
    /// failed: what the line says at rest while it says how fresh the list
    /// is (`showingAge`). See `UpdatedLine`.
    private var updated = UpdatedLine()
    /// Whether the line at rest says how fresh the list is, rather than
    /// where he is in it: not after a jump to a day, until the next Refresh.
    private var showingAge = true

    /// The draft on its way to the composer. See `DraftOpening`.
    private var drafts = DraftOpening()

    /// A draft tapped in Drafts is being downloaded for the composer, from
    /// the tap until the composer is put up or the failure said
    /// (`DraftOpening`). The warning before the app stops opening waits for
    /// it, as for a print (B-137): put up meanwhile, it took the composer's
    /// place, UIKit refused the composer, and after its OK nothing opened.
    var isOpeningDraft: Bool { drafts.loading != nil }

    /// The letters kept on the iPad (B-051): listed at the top of Drafts,
    /// and taken to the server whenever a page here has come, and at his
    /// Refresh once its counts have come too (B-072). The Outbox's are
    /// among them (B-052): its list is these alone.
    private let kept = LocalDrafts.shared

    /// The previews of the newest page `reload` last fetched, while they
    /// come: his Refresh's pass waits for them (`RefreshTap`, B-072).
    private var pagePreviews: Task<Void, Never>?

    /// The Outbox, which is on the iPad and not on the server: its rows are
    /// the letters waiting there, it has no search, no day to jump to and
    /// no pages, and a tap opens the letter in the composer.
    private var isOutbox: Bool { mailbox.role == .outbox }

    private var visible: [MessageSummary] { letters.visible }

    /// What a row actually is, now that the list groups.
    ///
    /// One case, and that is the point. A row USED to be either a
    /// conversation or one letter inside an opened-out conversation,
    /// because a tap expanded a thread in place. Mail does not do that —
    /// it opens the conversation in the reading pane as a stack — and B-022
    /// recorded the deviation until the decision was made to follow Mail. With the
    /// expansion gone, the list is one row per conversation, always.
    private enum Row {
        case thread(MessageThread)
    }

    private var rows: [Row] = []

    /// Rebuilds the visible rows from the flat message list.
    ///
    /// The flat arrays stay the source of truth and paging still walks
    /// them by UID; grouping is a view over the top. That matters because
    /// a thread is not a thing the server pages — asking for "the next
    /// fifty conversations" is not an IMAP operation.
    private func rebuildRows() {
        // Grouped when browsing a folder; NOT grouped when these are
        // search results. See MessageThread.rows(for:grouped:) — a grouped
        // result set shows the newest letter of each thread rather than
        // the one that actually matched.
        //
        // `organizeByThread` is Mail's own switch and defaults ON; turning
        // it off gives every letter its own row without a code change.
        rows = MessageThread.rows(
            for: letters.shown,
            grouped: !letters.isSearching && ConversationSettings.organizeByThread
        ).map(Row.thread)
    }

    /// The row a given message is VISIBLE in — the conversation row that
    /// stands for it, since a letter has no row of its own.
    private func rowIndex(showing id: String) -> Int? {
        for (i, row) in rows.enumerated() {
            switch row {
            case let .thread(t) where t.messages.contains(where: { $0.id == id }):
                return i
            default:
                continue
            }
        }
        return nil
    }

    /// The rows as conversations, for the reading pane's stack (B-074).
    var conversations: [MessageThread] { threads }

    /// The rows as conversations, for the helpers that work on them.
    private var threads: [MessageThread] {
        rows.map { row -> MessageThread in
            switch row {
            case let .thread(t): return t
            }
        }
    }

    /// Regroups and redraws, putting the selection back where it was, and
    /// the list where `move` says: by default where he is.
    ///
    /// `reloadData` rather than `insertRows`, and this is the cost of
    /// grouping: a page appended to the bottom can MERGE into a
    /// conversation already on screen instead of adding rows after it, so
    /// "the new rows are the last N" stopped being true. Reload drops the
    /// selection, and the selected row is the letter open in the pane to
    /// the right, or in Edit mode every row he has ticked, so it is
    /// restored by id, all of it (`ListEdit.selectedRows`). `opened` is a
    /// letter just marked read as the one open in the pane, whose row is
    /// highlighted with it. With nothing to restore, out of Edit mode, the
    /// row of the letter the pane shows is highlighted if the rows have it
    /// (`ListEdit.paneRow`, B-133): a page that brings it after a day
    /// jumped to without it, or a search's Cancel whose results did not
    /// have it, as Mail keeps the open message's row selected.
    ///
    /// Reload keeps the scroll offset and nothing else, and the rows under
    /// that offset can have moved: a page above, a row taken off by a
    /// Delete, the grouping switch. So the rows he can see are held by the
    /// letters in them and put back where they were on screen, and the
    /// selection by its letters too. Both are taken before the rows are
    /// rebuilt, since row numbers mean nothing after; see `ListPlace`.
    /// So is the row VoiceOver is on, which is put back on its letter at
    /// the end, once the list is where it goes (`keepVoiceOver`, B-079).
    @MainActor
    private func regroup(highlighting opened: String? = nil, to move: ListPlaces.Move = .stay) {
        let before = place()
        let voiceOverOn = voiceOverHeld()
        defer { keepVoiceOver(voiceOverOn) }
        rebuildRows()
        tableView.reloadData()
        let threads = self.threads
        var selection = before.selection(in: threads, opened: opened, editing: tableView.isEditing)
        if selection.isEmpty, !tableView.isEditing,
           let row = ListEdit.paneRow(in: threads, showing: lettersInPane()) {
            selection = [row]
        }
        for row in selection {
            tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false,
                                scrollPosition: .none)
        }
        switch move {
        case .top:
            scrollToTop()
        case .back(let folder):
            if !scroll(to: folder, in: threads) { scrollToTop() }
        case .putBack(let taken):
            if !scroll(to: taken, in: threads) { scroll(to: before, in: threads) }
        case .holding(let letter):
            scroll(to: before, in: threads, holding: letter)
        case .stay:
            scroll(to: before, in: threads)
        }
        onRegrouped?()
    }

    /// Where the list was before the rows still out were taken out, for a
    /// row put back. See `TakenRows`.
    private var taken = TakenRows()

    /// The letter heading the row the last date jump opened on, that row
    /// held where he sees it as the pages above come, until he moves the
    /// list. See `LandedLetter` (B-117, B-118).
    private var landed = LandedLetter()

    /// Regroups for a letter the reading pane or Edit mode changed, took
    /// out or put back (B-093): a row put back with the list as its take
    /// left it goes back where it stood, the rows below it down a row, as
    /// before the tap; otherwise the rows he can see stay where they are.
    /// The place the list is left in is taken once it is laid out there,
    /// since `scroll(to:)` has only set the offset.
    @MainActor
    private func regroup(for change: ListChange) {
        let here = place()
        regroup(to: taken.move(for: change, here: here))
        tableView.layoutIfNeeded()
        taken.drawn(change, from: here, to: place())
    }

    /// Where he is now: the rows he can see and how far down the pane each
    /// sits, and the selected rows. See `ListPlace`.
    ///
    /// The rows he can see, not every row the table has on screen, which
    /// counts the ones under the bars and the search band (B-093): the row
    /// held is the first he can see, at least partly below them
    /// (`ListPlace.inSight`), for every move that keeps his place, a regroup,
    /// a search's Cancel, a page put on above, the newest page fetched
    /// afresh after an edit of his own.
    @MainActor
    private func place() -> ListPlace {
        let onScreen = (tableView.indexPathsForVisibleRows ?? [])
            .filter { $0.section == 0 && $0.row < rows.count }
            .sorted()
            .map { ip -> (row: Int, top: Double, bottom: Double) in
                let rect = tableView.rectForRow(at: ip)
                return (ip.row, Double(rect.minY), Double(rect.maxY))
            }
        let selected = (tableView.indexPathsForSelectedRows ?? []).map(\.row)
        return ListPlace(rows: threads, onScreen: onScreen, sight: tableView.sight,
                         selected: selected)
    }

    /// Puts `place` back on screen, if any of it is in `threads`. Leaves the
    /// offset alone when it is already there, so a regroup that moved
    /// nothing, as a page appended below does, never touches a list he is
    /// flicking through.
    ///
    /// With `letter`, the row that carries it is the one put back where it
    /// was, if he could see it, or joined by newer mail, the day's next row
    /// in its place (`ListPlace.landing(in:holding:)`, B-117, B-118).
    @MainActor
    @discardableResult
    private func scroll(to place: ListPlace, in threads: [MessageThread],
                        holding letter: String? = nil) -> Bool {
        guard let landing = place.landing(in: threads, holding: letter) else { return false }
        // Laid out first: `reloadData` has only scheduled it, and the row
        // positions and content height are those of the old rows until it
        // runs. See `show(_ window:)`.
        tableView.layoutIfNeeded()
        let lowest = -Double(tableView.adjustedContentInset.top)
        let highest = max(lowest, Double(tableView.contentSize.height
                                         + tableView.adjustedContentInset.bottom
                                         - tableView.bounds.height))
        let rowTop = tableView.rectForRow(at: IndexPath(row: landing.row, section: 0)).minY
        if let y = ListPlace.contentOffset(rowTop: Double(rowTop), offset: landing.offset,
                                           range: lowest...highest,
                                           current: Double(tableView.contentOffset.y)) {
            tableView.contentOffset.y = CGFloat(y)
        }
        return true
    }

    /// To the first row, the newest.
    ///
    /// Laid out first, for the same reason as `scroll(to:)`: this runs
    /// straight after `reloadData`, which has only scheduled the layout, and
    /// an offset set before it runs is overridden by it. Seen on the iPad:
    /// searching from part-way down the Inbox put the results under the old
    /// offset, with the first hits scrolled out of sight above the search
    /// field.
    ///
    /// A list pulled down past its top is left where it is while a finger
    /// is on it or it springs back (`ListPlaces.setsTop`, B-103): under the
    /// finger, the rows would jump as the newest page lands during a pull
    /// still held; let go, it springs back to the top by itself. Set to the
    /// top as it sprang back, the offset stopped the spring-back at the
    /// spinner's rest, and the spinner put away there left the list 60 pt
    /// below its top, seen on the iPad on 2026-10-22. One left at rest past
    /// its top is set to the top, as from anywhere below it. At the top
    /// already, there is nothing to set.
    @MainActor
    private func scrollToTop() {
        tableView.layoutIfNeeded()
        guard ListPlaces.setsTop(offset: Double(tableView.contentOffset.y),
                                 topInset: Double(tableView.adjustedContentInset.top),
                                 moving: tableView.isTracking || tableView.isDecelerating) else {
            return
        }
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top),
                                   animated: false)
    }

    init(repository: MailRepository, mailbox: Mailbox) {
        self.repository = repository
        self.mailbox = mailbox
        super.init(style: .plain)
        title = mailbox.displayName
        // The highlight stays on the letter in the reading pane when the
        // list comes back into view (B-071). A `UITableViewController`
        // clears it by default whenever its view is about to appear, and a
        // file's preview, which covers the whole screen, makes it appear
        // again when it closes: the row lost its highlight while its letter
        // stayed open. The rows that are let go on purpose are let go where
        // that is decided (`letGo`, `openDraft`, `openWaiting`).
        clearsSelectionOnViewWillAppear = false
        letters.changed = { [weak self] change in
            self?.regroup(for: change)
            self?.updateEmptyState()
        }
        letters.onLetGo = { [weak self] letter in self?.letGo(letter) }
        letters.onUnreadCountChanged = { [weak self] folders, delta in
            self?.onUnreadCountChanged?(folders, delta)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseID)
        tableView.rowHeight = Theme.messageRowHeightScaled
        tableView.backgroundColor = Theme.canvas
        tableView.separatorColor = Theme.separator
        tableView.separatorInset = UIEdgeInsets(top: 0, left: Theme.messageSeparatorInset,
                                                bottom: 0, right: 0)
        tableView.tableFooterView = UIView()
        // Set ONCE, here, and true. It only has an effect while editing, and
        // toggling it in `editTapped` was a bug: it was assigned *after*
        // `setEditing(true)`, so the rows were configured while it was still
        // false and came up with the `.delete` editing style — a red minus
        // badge on every row. That is not cosmetic. It says "delete" beside
        // every letter when the control means "choose", and tapping one
        // reveals a Delete button that does nothing, because no
        // `commit editingStyle` is implemented.
        //
        // Nor was it ever doing what its old comment claimed, that it kept
        // swipes away. It has nothing to do with swiping. The drags a row
        // has are Mail's, since the owner withdrew the brief's no-swipe
        // rule on 2026-10-26, and come from the swipe configurations below
        // (B-156); still no `commit editingStyle:`, so no red minus either.
        tableView.allowsMultipleSelectionDuringEditing = true

        searchBar = SearchHeaderView(width: view.bounds.width)
        searchBar.onQueryChanged = { [weak self] text in self?.queryChanged(text) }
        searchBar.onScopeChanged = { [weak self] scope in
            guard let self else { return }
            self.searchScope = scope
            // Re-run what is already typed. Changing where to look is not a
            // new question, so it must not wait for him to retype the old
            // one — and it goes through the debounced path so a double-tap
            // on the two buttons costs one search, not two.
            self.queryChanged(self.searchQuery)
        }
        searchBar.onCancel = { [weak self] in self?.cancelSearch() }
        // Mail's recent searches (B-105): read as the field is focused
        // empty, kept at Search on the keyboard and when a letter is opened
        // from the results, and a tap on one searches at once.
        searchBar.recentSearches = {
            RecentSearches.load(from: RecentSearches.appFile, at: Date()).map(\.text)
        }
        searchBar.onSearchKey = { [weak self] text in self?.keepSearch(text) }
        searchBar.onRecentChosen = { [weak self] text in self?.recentChosen(text) }
        // The band grows when the scope buttons appear, and the table has to
        // be told to re-ask how tall its header is. `begin`/`endUpdates`
        // with no changes between them does exactly that and nothing else.
        searchBar.onHeightChanged = { [weak self] in
            guard let self, self.isViewLoaded else { return }
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
            // The band grows as the field takes the keyboard and shrinks as
            // it is cleared: no pull while it is in use (B-103).
            self.placePull()
        }
        searchScope = searchBar.scope

        // A SECTION header, not `tableView.tableHeaderView`.
        //
        // The difference is the whole point: a table header view scrolls
        // away with the mail, and a plain-style section header stays put at
        // the top of the pane. It was a table header view, so the search
        // field scrolled out of sight as soon as he moved down the list —
        // which contradicted the measured reference ("pinned 43 pt search
        // bar"), contradicted D-012's own promise that "the search field
        // itself never moves", and mattered more than either, because the
        // one habit known about him is that he searches all the
        // time. A search field you have to scroll back to the top to reach
        // is a search field with a scroll in front of it.
        tableView.sectionHeaderTopPadding = 0
        // Zero ESTIMATE, so the table asks `heightForHeaderInSection` for
        // the real number instead of guessing and correcting later. The
        // band changes height when the scope bar appears, and an estimated
        // header is exactly where a stale height comes from.
        tableView.estimatedSectionHeaderHeight = 0

        emptyLabel.text = "No messages"
        emptyLabel.font = Theme.fontListSubject
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            // Near the top rather than dead centre, because the commonest
            // time this label has something to say is now "No results" —
            // and while he is typing a search the keyboard covers the
            // bottom two thirds of the pane, so a centred label was behind
            // it. Seen on device: a search with no hits showed an empty
            // black rectangle and no explanation at all.
            emptyLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 140),
        ])

        // "Edit", as in the reference. Compose is NOT duplicated here - it
        // lives once, in the detail pane's toolbar, so there is exactly one
        // place to start a letter.
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Edit", style: .plain, target: self, action: #selector(editTapped))
        navigationItem.rightBarButtonItem?.setTitleTextAttributes(
            [.font: Theme.fontBarButton], for: .normal)

        // The calendar, and the most important button in the app.
        //
        // Not in the reference and not in Mail — Mail has never had one,
        // which is precisely the problem it is here to fix. What actually
        // goes wrong for him is that he cannot get back to a particular day, and Mail's only answer to
        // that is to scroll, which does not work when the day is four
        // months and two thousand letters up.
        //
        // The nav bar's leading slot because it is the one permanently
        // empty, permanently visible place in this pane: UIKit's back button
        // never appears here, so nothing can displace it and it is never one
        // tap deep in anything. "Easy to access" is the requirement,
        // and this is the whole of it. In two panes (D-015) the view button
        // and "< Mailboxes" come before it in the same slot, and it stays
        // the one beside the title.
        // At a fixed size, as the type is (B-071).
        let jump = UIBarButtonItem(image: Theme.symbol("calendar"),
                                   style: .plain, target: self,
                                   action: #selector(jumpToDateTapped))
        jump.accessibilityLabel = "Go to a date"
        // Not in the Outbox, which holds a handful of letters from today.
        jumpItem = isOutbox ? nil : jump
        placeLeadingItems()

        // The bottom bar from the reference. It looks decorative and is not:
        // "Updated Just Now" is the only thing on screen that answers "is this
        // actually my mail, or is it stale?" - a question that otherwise ends
        // in a phone call.
        statusLabel.font = Theme.fontToolbarStatus
        statusLabel.textColor = Theme.secondaryText
        statusLabel.textAlignment = .center
        // Up to three lines, as Mail's bar has them: how old the list is,
        // the letters waiting in the Outbox, and what went wrong
        // (`UpdatedLine`).
        statusLabel.numberOfLines = 3
        showStatus()
        // Five taps here opens the connection log. Hidden on purpose:
        // `PRODUCT_SPEC.md` forbids showing protocol text to him, but whoever is helping
        // over the phone needs to see what the server actually said, and
        // "tap the grey words five times" is a thing that can be said down a
        // telephone to someone who cannot navigate a settings screen.
        DiagnosticsViewController.attachOpener(to: statusLabel) { [weak self] in self }
        // The footer is a real labelled control, not just a status line.
        // Automatic loading covers the ordinary case, but a gesture you have
        // to know about is not a control — and if a load has failed, the one
        // thing he needs is something that says what it does and can be
        // pressed again.
        pageFooter.addTarget(self, action: #selector(loadMoreTapped), for: .touchUpInside)
        buildBottomBar()
        // The pull down past the top of the list, which checks for mail as
        // the Refresh button does (B-103), beside it and never in its place
        // (D-009). Grey, as the line under the list, and with no words.
        // Offered only where it moves nothing (`placePull`).
        pull.tintColor = Theme.secondaryText
        pull.addTarget(self, action: #selector(pulled), for: .valueChanged)
        placePull()
        NotificationCenter.default.addObserver(self, selector: #selector(wentToBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)

        // Every list: Drafts and the Outbox list what is kept, and the line
        // under each counts the letters waiting in the Outbox.
        NotificationCenter.default.addObserver(self, selector: #selector(keptChanged(_:)),
                                               name: LocalDrafts.changed, object: kept)
        // Where VoiceOver goes, for a row it has been sent to (B-079).
        NotificationCenter.default.addObserver(self, selector: #selector(voiceOverMoved(_:)),
                                               name: UIAccessibility.elementFocusedNotification,
                                               object: nil)
        // The rows' dates written again where they are when the iPad's form
        // or day changes (B-139).
        for name in [DisplayDates.didChange, UIApplication.significantTimeChangeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(datesChanged),
                                                   name: name, object: nil)
        }

        // The folder's page kept on the iPad, before anything is sent
        // (D-016): at launch the Inbox is in the first frame, and so is
        // every folder he has opened before, with a connection or without.
        showKeptPage()

        Task { @MainActor in
            // A jump asked for before this pane existed — the container
            // opened All Mail in order to serve it — runs INSTEAD of the
            // newest page, which it used to follow and throw away. The
            // newest page comes only if the jump finds nothing or fails;
            // see `ListOpening`.
            let day = self.pendingJump
            self.pendingJump = nil
            // False only when the newest page was asked for and could not
            // be fetched. A jump that landed, or one another action took
            // over, leaves nothing to say about the connection.
            var came = true
            // Said from the start: this list was opened to jump, and has
            // no rows until the day comes.
            let going = day.map { self.working(StatusLine.goingTo($0)) }
            let fellBack = await ListOpening.open(
                at: day,
                jump: { date in
                    await self.landWindow(around: date, generation: self.startReplacingList())
                },
                newest: {
                    // Over the kept page, by `KeptSwap`'s rules rather than
                    // a Refresh's: he did not ask, and may be reading it.
                    came = self.letters.fromShelf
                        ? await self.fetchOverKept(quietly: false) : await self.reload()
                })
            if let day, let fellBack { self.report(fellBack, jumpingTo: day) }
            going?()
            self.onFirstLoadFinished?(came)
            self.onFirstLoadFinished = nil
        }
    }

    /// Set by the container when it opens this folder purely in order to
    /// jump in it.
    var pendingJump: Date?

    /// Called once, when this list's first rows have been fetched or have
    /// failed to be, with false for the second. At launch the folder counts
    /// wait for it, and are not asked for after a failure.
    var onFirstLoadFinished: ((Bool) -> Void)?

    /// Returns whether the page came. At the top, unless `keepingPlace`,
    /// for an edit of his own; see `ListPlaces.refetched`. `quietly` when he
    /// did not ask for it, which puts up no alert if it fails, and whose
    /// page is dropped if he has started a search while it was on its way,
    /// or anything else has replaced the list: landing, it would clear the
    /// field and the results under his fingers. The list stays owed its
    /// fetch afresh, which goes again when he is next at the top.
    ///
    /// A page that came means the connection works, so the letters waiting
    /// on the iPad go to the server after it (`LocalDrafts.uploadWaiting`):
    /// at launch, on opening a folder, on coming back, the small ones. Not
    /// with `passing` false, for his Refresh, whose own pass goes once the
    /// counts have come as well and sends the Outbox's large letters too
    /// (`refreshTapped`, B-072).
    @MainActor
    @discardableResult
    func reload(keepingPlace: Bool = false, quietly: Bool = false,
                passing: Bool = true) async -> Bool {
        // Nothing to fetch: what is on the iPad, and a pass over the
        // connection if one is up, as after a page.
        if isOutbox {
            listOutbox()
            if passing { kept.uploadWaiting(to: repository) }
            return true
        }
        listGeneration += 1
        let generation = listGeneration
        // Fetched afresh, at the top or where he was after an edit of his
        // own: no day is held now (B-117).
        landed.letGo()
        stopSearching()
        isLoadingPage = false
        isLoadingPrevious = false
        reachedOldestMessage = false
        // Back to the top, so there is nothing above us again. A reload
        // after a date jump must clear this or the list would keep trying
        // to load mail newer than the newest message there is.
        reachedNewestMessage = true
        placePull()
        let asked = letters.askingAfresh()
        do {
            let first = try await repository.listMessages(in: mailbox.id, beforeUID: nil,
                                                          limit: Self.pageSize)
            if quietly, generation != listGeneration || isSearchingOrTyping { return false }
            // Previews already on screen go across to the same letters, and
            // only the rest are fetched, and his read marks and flags the
            // server had not taken when this was asked for stay on; see
            // `ListLetters.fetchedAfresh`.
            let unpreviewed = letters.fetchedAfresh(first, asked: asked)
            // A short first page means the whole folder fits in one, so no
            // footer and no scroll trigger.
            reachedOldestMessage = first.count < Self.pageSize
            searchQuery = ""
            searchBar.clear()
            listKept()
            updated.succeeded(at: Date())
            showingAge = true
            sayAge()
            // Regrouped, which puts the highlight back on the letter open in
            // the reading pane if its row is still here. At the top: this is
            // the newest page, and a Refresh from far down a folder used to
            // leave it under the offset the old rows had. After a Delete or
            // a Move from Edit mode, or a draft saved, where he is, if the
            // newest page reaches that far.
            regroup(to: keepingPlace ? places.refetched(here: place()) : places.replaced())
            updateEmptyState()
            updatePageFooter()
            pagePreviews = loadPreviews(for: unpreviewed)
            placePull()
            if passing { kept.uploadWaiting(to: repository) }
            return true
        } catch {
            // The letters kept on the iPad are listed all the same: with no
            // connection they are exactly the ones he needs to see.
            if mailbox.role == .drafts {
                listKept()
                regroup()
                updateEmptyState()
            }
            // The line says so too, and goes on saying so under the age of
            // what is on screen until something brings it up to date.
            updated.failed((error as? MailError) ?? .cannotConnect)
            if showingAge { sayAge() }
            // Once his finger is off the list: a pull's page fails while the
            // finger is still down (B-103).
            if !quietly { showWhenLetGo(error) }
            return false
        }
    }

    // MARK: - VoiceOver's row (B-079)

    /// The row VoiceOver is on, or has been sent to, kept on its letter when
    /// the rows are drawn again. See `ListVoiceOver`.
    private var voiceOver = ListVoiceOver()
    /// VoiceOver asked where it is while a row is held, and the timer that
    /// asks (the fourth change). See `FocusWatch`.
    private var focusWatch = FocusWatch()
    private var voiceOverTicks: Timer?

    /// Where VoiceOver goes as this list comes in front in two panes: the
    /// highlighted row if any of it is in sight, else the first row wholly
    /// in sight, else the table (`voiceOverPlace(orFirstRow:)`). A row is
    /// held for VoiceOver for a while, before it is there and after: if the
    /// rows are drawn again, it goes to the cell that then shows the same
    /// letter, and if it leaves the row by itself, it is put back once. The
    /// container posts what this returns.
    @MainActor
    func placeVoiceOver() -> UIView {
        let place = tableView.voiceOverPlace(orFirstRow: true)
        voiceOver.send(to: voiceOverRow(of: place), running: UIAccessibility.isVoiceOverRunning,
                       at: Date())
        watchVoiceOver()
        return place
    }

    /// The highlighted row, if part of it is under the search band or a
    /// bar, shown whole with the least scroll, while VoiceOver is running.
    /// For the folder tap in two panes that puts this list back in front,
    /// before the panes move: the list is hidden then, and the motion's
    /// pictures are cut where it now is, so it does not jump as they go.
    /// VoiceOver, put on the row, then has nothing to scroll (B-079).
    @MainActor
    func showHighlightedRowWhole() {
        tableView.showWhole(forVoiceOver: tableView.indexPathForSelectedRow)
    }

    /// The row held for VoiceOver let go, and VoiceOver no longer asked
    /// where it is: the panes have been switched, and the view button names
    /// its twin in the corner; he has opened or ticked a row; the list's
    /// column is out of sight.
    @MainActor
    func letGoOfVoiceOver() {
        voiceOver.letGo()
        stopWatchingVoiceOver()
    }

    /// VoiceOver asked where it is every tenth of a second while the row
    /// just sent to is held (`FocusWatch`): from now, from nothing seen. No
    /// ticks with nothing held.
    @MainActor
    private func watchVoiceOver() {
        voiceOverTicks?.invalidate()
        voiceOverTicks = focusWatch.start(holding: voiceOver.sentRow(at: Date()) != nil)
            ? Timer.voiceOverTicks(self, #selector(voiceOverTick)) : nil
    }

    /// No more ticks.
    @MainActor
    private func stopWatchingVoiceOver() {
        focusWatch.stop()
        voiceOverTicks?.invalidate()
        voiceOverTicks = nil
    }

    /// The row at `index` in the rows as they are now.
    private func voiceOverRow(at index: Int?) -> ListVoiceOver.Row? {
        index.flatMap { ListVoiceOver.Row($0, in: threads) }
    }

    /// The row whose cell `place` is, nil for the table.
    private func voiceOverRow(of place: UIView) -> ListVoiceOver.Row? {
        voiceOverRow(at: (place as? UITableViewCell).flatMap { tableView.indexPath(for: $0) }?.row)
    }

    /// The row of this list `element` is: one of its cells, something
    /// inside one, or the element UIKit gives VoiceOver for a row, which is
    /// not a view and whose container is the table, found by where it is,
    /// off the search band. Nil for anything else: the search field and its
    /// band, the bars, the table itself, the folders, the reading pane, a
    /// sheet.
    @MainActor
    private func listRow(of element: Any) -> Int? {
        let band = isOutbox
            ? nil : UIAccessibility.convertToScreenCoordinates(searchBar.bounds, in: searchBar)
        return tableView.voiceOverRow(of: element, besides: band)?.row
    }

    /// The list's column is in the window and shown. Not after "< Mailboxes"
    /// in two panes, which hides it, and not for a list a folder opened has
    /// put out of the window.
    @MainActor
    private var listInSight: Bool {
        var shown: UIView? = tableView
        while let view = shown {
            if view.isHidden { return false }
            shown = view.superview
        }
        return tableView.window != nil
    }

    /// What VoiceOver is on, `element`, as this list sees it, and the row if
    /// it is one of the list's. `place`, the cell the row VoiceOver was
    /// sent to is drawn in now, if any. A row of the list first: the row
    /// sent to if it is that cell's row, by its place in the list alone.
    /// `place` is worked out for the row's letter at each look, and
    /// UIKit's element for a row need not have the cell's words, so its
    /// words are not compared (the fourth change). Then his
    /// typing: a key, or the search field while he types in it. Then the
    /// list's own column: its bar with the view button and "< Mailboxes",
    /// apart, but in the Outbox, which has no search band, only those two,
    /// its title and Edit being a swipe from the first row; the table
    /// itself, the search band, the toolbar. Then the panes beside it in
    /// the container, the reading pane and the folders. Else elsewhere: a
    /// sheet. Each by the view the element is in, or by where it is for an
    /// element in no view, as WebKit's in the letter's text
    /// (`voiceOverHolds`).
    @MainActor
    private func voiceOverLanding(on element: Any?, sentTo place: UIView?)
        -> (landing: ListVoiceOver.Landing, row: Int?) {
        guard let element else { return (.elsewhere, nil) }
        if let on = listRow(of: element) {
            guard let place else { return (.otherRow, on) }
            return (on == voiceOverRow(of: place)?.index ? .sentRow : .otherRow, on)
        }
        if (element as? NSObject)?.accessibilityTraits.contains(.keyboardKey) == true
            || (!isOutbox && searchBar.isTyping) { return (.typing, nil) }
        if let column = navigationController?.view ?? view, column.voiceOverHolds(element) {
            if let bar = navigationController?.navigationBar, bar.voiceOverHolds(element),
               !isOutbox || itemsBeforeCalendar.contains(where: { item in
                   item.customView?.voiceOverHolds(element) == true }) { return (.listBar, nil) }
            return (.listOwn, nil)
        }
        if let panes = navigationController?.parent?.view, panes.voiceOverHolds(element) {
            return (.beside, nil)
        }
        return (.elsewhere, nil)
    }

    /// The row to keep VoiceOver on, taken before the rows are drawn again:
    /// the one it has been sent to, while it is held, else the row of this
    /// list it is on. Nil with VoiceOver off, while he types, with the
    /// list's column out of sight, or on anything else (`ListVoiceOver.held`).
    @MainActor
    private func voiceOverHeld() -> ListVoiceOver.Row? {
        guard listInSight else {
            letGoOfVoiceOver()
            return nil
        }
        let running = UIAccessibility.isVoiceOverRunning
        let on = voiceOverLanding(
            on: running ? UIAccessibility.focusedElement(using: .notificationVoiceOver) : nil,
            sentTo: nil)
        return voiceOver.held(running: running, on: voiceOverRow(at: on.row), landing: on.landing,
                              at: Date())
    }

    /// Where VoiceOver goes for `held` in the rows as they are now: the cell
    /// that shows its letter, or the one now in its place, if any of it is
    /// in sight; else the first row wholly in sight; else the table. Nil
    /// for nothing held.
    @MainActor
    private func voiceOverPlace(keeping held: ListVoiceOver.Row?) -> UIView? {
        switch ListVoiceOver.step(after: held, in: threads) {
        case .leave:
            return nil
        case .table:
            return tableView
        case .same(let row), .inPlace(let row):
            // The cells for the rows as they are now: `reloadData` has only
            // scheduled them.
            tableView.layoutIfNeeded()
            return tableView.voiceOverPlace(at: IndexPath(row: row, section: 0), orFirstRow: true)
        }
    }

    /// After the rows are drawn again, with the list where it goes: VoiceOver
    /// put on the cell that now shows the letter it was on, or sent to.
    /// Nothing when it was on nothing of the list's rows, or is off.
    @MainActor
    private func keepVoiceOver(_ held: ListVoiceOver.Row?) {
        guard let place = voiceOverPlace(keeping: held) else { return }
        voiceOver.redrawn(to: voiceOverRow(of: place))
        putVoiceOver(on: place)
    }

    /// VoiceOver put on `place`, with a layout change: a row shown whole
    /// first, with the least scroll, if part of it is under the search band
    /// or a bar, so that VoiceOver has nothing to scroll (B-079).
    @MainActor
    private func putVoiceOver(on place: UIView) {
        tableView.showWhole(forVoiceOver:
            (place as? UITableViewCell).flatMap { tableView.indexPath(for: $0) })
        UIAccessibility.post(notification: .layoutChanged, argument: place)
    }

    /// VoiceOver has moved. While a row is held, VoiceOver is asked where
    /// it is on the next turn, after its own move. Not from the element
    /// this names: on the iPad that was nothing the list could find, at
    /// the landing on the row and at the leave (`FocusWatch`).
    @objc private func voiceOverMoved(_ note: Notification) {
        guard isViewLoaded, voiceOver.sentRow(at: Date()) != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.lookAtVoiceOver(onlyIfMoved: false) }
    }

    /// A tick while a row is held: VoiceOver asked where it is, in case its
    /// move was not told.
    @objc private func voiceOverTick() {
        lookAtVoiceOver(onlyIfMoved: true)
    }

    /// Where VoiceOver is, from VoiceOver itself, told apart for the row
    /// held. At a tick, `onlyIfMoved`, only when it is on another object
    /// than the one last seen. If it has just been sent to the row and has
    /// gone to another of the list's rows, to a cell drawn since for
    /// another letter, or to the list's own bar or table, it is put on the
    /// one it was sent to, once; and if it has been there and has gone by
    /// itself to the reading pane or the list's bar (`ListVoiceOver.moved`).
    /// The ticks stop with nothing held, at the bound, and once the row is
    /// put back or let go. The list's column out of sight, the row is let
    /// go. VoiceOver on nothing, as it may be for a moment as it moves, is
    /// passed over: the row stays held, and the next look tells apart
    /// where it went.
    @MainActor
    private func lookAtVoiceOver(onlyIfMoved: Bool) {
        let now = Date()
        guard focusWatch.goesOn(holding: isViewLoaded && UIAccessibility.isVoiceOverRunning
                                    && voiceOver.sentRow(at: now) != nil) else {
            stopWatchingVoiceOver()
            return
        }
        guard listInSight else {
            letGoOfVoiceOver()
            return
        }
        guard let element = UIAccessibility.focusedElement(using: .notificationVoiceOver) else { return }
        let changed = focusWatch.changed(to: element as AnyObject)
        guard changed || !onlyIfMoved, let sent = voiceOver.sentRow(at: now),
              let place = voiceOverPlace(keeping: sent) else { return }
        let landing = voiceOverLanding(on: element, sentTo: place).landing
        let put = voiceOver.moved(to: landing, at: now)
        if voiceOver.sentRow(at: now) == nil { stopWatchingVoiceOver() }
        guard put != nil else { return }
        putVoiceOver(on: place)
    }

    // MARK: - The copy of his mail kept on the iPad (D-016)

    /// The fetch of the folder's fresh first page over the kept one, one at
    /// a time, and the page once it has come, while it waits for a finger
    /// to lift or his ticks to go. See `OverKept` and `KeptSwap`.
    private var overKept = OverKept()
    /// Looks every so often for the finger to have lifted, while a fresh
    /// page waits for it: a finger lifted from a tap, which never dragged,
    /// tells the list nothing.
    private var liftWatch: Task<Void, Never>?
    private static let liftCheck = Duration.milliseconds(250)

    /// Draws the folder's page kept on the iPad, if there is one and the
    /// list is not opened to jump to a day (`ListOpening.kept`), and says
    /// "Checking for Mail…" under it until the server has answered. No
    /// paging below it until then: the pages below are not kept, and the
    /// kept rows are an earlier launch's.
    @MainActor
    private func showKeptPage() {
        guard let page = ListOpening.kept(for: mailbox, jumpingTo: pendingJump,
                                          from: repository.shelf) else { return }
        let voiceOverOn = voiceOverHeld()
        defer { keepVoiceOver(voiceOverOn) }
        letters.showKept(page.rows)
        listKept()
        updated.showingKept(since: page.keptAt)
        reachedOldestMessage = true
        rebuildRows()
        tableView.reloadData()
        updateEmptyState()
        updatePageFooter()
        sayAge()
    }

    /// The folder's newest page, fetched over the kept one on screen, and
    /// put in its place by `KeptSwap`: at the top in place, scrolled with
    /// the rows he can see held, under a search left alone, and not while a
    /// finger is on the list. At launch and on opening a folder, and
    /// `quietly` when the watch has found the connection working again
    /// after a launch without one, which puts up no alert if it fails.
    /// Returns whether the page came. One at a time, the folder's own and
    /// the watch's (`OverKept`): not while another is out or a page waits.
    ///
    /// Nothing else on the list is touched meanwhile, a search above all:
    /// unlike `reload`, which is a Refresh he asked for, this neither
    /// clears the field nor calls off a search on its way.
    @MainActor
    @discardableResult
    private func fetchOverKept(quietly: Bool) async -> Bool {
        guard overKept.fetch(showingKept: letters.fromShelf, quietly: quietly) else { return false }
        let asked = letters.askingAfresh()
        do {
            let first = try await repository.listMessages(in: mailbox.id, beforeUID: nil,
                                                          limit: Self.pageSize)
            overKept.came(first, asked: asked)
            landFreshPage()
            kept.uploadWaiting(to: repository)
            return true
        } catch {
            overKept.failed()
            // Something he asked for has replaced the kept rows meanwhile,
            // and said how it went.
            guard letters.fromShelf else { return false }
            if mailbox.role == .drafts {
                listKept()
                regroup()
                updateEmptyState()
            }
            // The kept rows stay, and the line says how old they are, with
            // what went wrong under it.
            updated.failed((error as? MailError) ?? .cannotConnect)
            if showingAge { sayAge() }
            if !quietly { ErrorPresenter.show(reaching: error, on: self) }
            return false
        }
    }

    /// Puts the fresh page in place of the kept one, where `KeptSwap` says,
    /// or leaves it waiting for a finger to lift or his ticks to go. Called
    /// as it comes, and again whenever the finger may have lifted, and at
    /// Done and the last tick taken off.
    @MainActor
    private func landFreshPage() {
        guard overKept.waiting != nil, isViewLoaded else { return }
        let touching = tableView.isTracking || tableView.isDragging || tableView.isDecelerating
        let ticked = tableView.isEditing && !(tableView.indexPathsForSelectedRows ?? []).isEmpty
        let atTop = ListPlaces.isAtTop(offset: Double(tableView.contentOffset.y),
                                       topInset: Double(tableView.adjustedContentInset.top))
        let swap = KeptSwap.swap(atTop: atTop, searching: isSearchingOrTyping, ticked: ticked,
                                 touching: touching)
        // Replaced meanwhile by something he asked for, a Refresh or a day,
        // the page is dropped: that list has the say.
        guard let fresh = overKept.landing(showingKept: letters.fromShelf, swap) else {
            // A finger lifted from a tap tells the list nothing, so it is
            // looked for; Done and the last tick taken off call this again.
            if swap == .waitForLift, overKept.waiting != nil { waitForLift() } else { stopWaitingForLift() }
            return
        }
        stopWaitingForLift()
        let first = fresh.page
        let unpreviewed: [MessageSummary]
        switch swap {
        case .waitForLift, .waitForTicks:
            return
        case .top:
            unpreviewed = letters.fetchedAfresh(first, asked: fresh.asked)
            listKept()
            regroup(to: places.replaced())
        case .holdingPlace:
            let here = place()
            unpreviewed = letters.fetchedAfresh(first, asked: fresh.asked)
            listKept()
            regroup(to: places.refetched(here: here))
        case .underSearch:
            let showingResults = letters.isSearching
            let here = place()
            unpreviewed = letters.fetchedUnderSearch(first, asked: fresh.asked)
            listKept()
            // Typed and not yet run, the rows on screen are the folder's.
            if !showingResults { regroup(to: .back(here)) }
        }
        // Paging below the fresh page, as below any; a search showing has
        // its own paging, and the folder's comes back with it.
        if !letters.isSearching { reachedOldestMessage = first.count < Self.pageSize }
        updated.succeeded(at: Date())
        showingAge = true
        sayAge()
        updateEmptyState()
        updatePageFooter()
        updateSelectAllTitle()
        loadPreviews(for: unpreviewed)
    }

    @MainActor
    private func waitForLift() {
        guard liftWatch == nil else { return }
        liftWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.liftCheck)
                guard let self, !Task.isCancelled, self.overKept.waiting != nil else { return }
                self.landFreshPage()
            }
        }
    }

    @MainActor
    private func stopWaitingForLift() {
        liftWatch?.cancel()
        liftWatch = nil
    }

    /// The watch has reached the server while the kept page is still on
    /// screen, a launch that could not connect having left it there: the
    /// page is fetched afresh now, quietly, rather than waiting for a
    /// Refresh, and a letter that came while there was no connection is
    /// on it. Not while the folder's own fetch is out, or has brought a
    /// page that waits (`OverKept`).
    @MainActor
    private func fetchOverKeptQuietly() {
        guard letters.fromShelf else { return }
        Task { @MainActor [weak self] in
            await self?.fetchOverKept(quietly: true)
        }
    }

    // MARK: - Letters kept on the iPad

    /// Drafts' rows for the letters kept on the iPad, from what is kept
    /// now; in any other folder nothing.
    @MainActor
    private func listKept() {
        guard mailbox.role == .drafts else { return }
        letters.keep(kept.draftsRows(in: mailbox.id, from: keptSender),
                     replacing: kept.replacedInDrafts)
    }

    /// The Outbox's rows: the letters waiting there, newest first, each
    /// with "Sending…" while it goes or why it has not gone.
    @MainActor
    private func listOutbox() {
        _ = letters.fetchedAfresh([])
        letters.keep(kept.outboxRows, replacing: [:])
        reachedOldestMessage = true
        regroup()
        updateEmptyState()
        updatePageFooter()
        sayAge()
    }

    /// Who a letter kept on the iPad is from, as its row says it.
    private var keptSender: String {
        let account = CredentialStore.loadAccount()
        return account.map { $0.displayName.isEmpty ? $0.address : $0.displayName } ?? ""
    }

    /// A letter kept on the iPad has changed: its row, where he is. One
    /// that has just reached the server is drawn as the copy it became
    /// there, in place of the copies that went (`ListLetters.landed`),
    /// without fetching the folder again, so a search, his ticks, the
    /// pages he has scrolled through and where he is in them all stay.
    @objc private func keptChanged(_ note: Notification) {
        if isOutbox {
            listOutbox()
            return
        }
        // How many letters wait in the Outbox, under the age.
        if showingAge { sayAge() }
        guard mailbox.role == .drafts else { return }
        if let landing = note.userInfo?[LocalDrafts.landingKey] as? DraftLanding {
            var copy: MessageSummary?
            if let letter = landing.letter, let id = landing.id {
                copy = letter.row(in: mailbox.id, from: keptSender, onServerAs: id)
            }
            letters.landed(copy, replacing: landing.replaced, atTop: reachedNewestMessage)
        }
        listKept()
        regroup()
        updateEmptyState()
    }

    /// Back to the newest mail after a while away, in this list rather than
    /// a new one (`Sitting.onReturn`): out of Edit, to the top at once over
    /// the rows already here, and those rows kept, previews and all, until
    /// the new page replaces them. Returns whether it came.
    @MainActor
    func returnToNewest() async -> Bool {
        if tableView.isEditing { editTapped() }
        scrollToTop()
        return await reload()
    }

    // MARK: - New mail, without a tap (B-049)

    /// Every letter this list holds from its folder, for the watch to check
    /// the folder against (`MailWatch`), or nil when it is to check only the
    /// Inbox's count: a day jumped to, a search showing, a list whose first
    /// page never came. See `ListLetters.toWatch`.
    var lettersToWatch: [String]? {
        letters.toWatch(fromNewest: reachedNewestMessage, fetched: updated.updated != nil)
    }

    /// News of this folder from the watch, at every check of it, none
    /// included: on the list now if he is at the top of it, with what was
    /// held before; held until he is otherwise (`ListPlaces.showsNews`); and
    /// not taken by a day jumped to since the check began, whose top is not
    /// the folder's (`ListLetters.take`).
    @MainActor
    func newsFound(_ news: FolderNews) -> NewsTaken {
        let taken = letters.take(news, fromNewest: reachedNewestMessage)
        showNewsIfAtTop()
        return taken
    }

    /// How the watch's last check went, for the line under the list
    /// (`UpdatedLine.checked`).
    @MainActor
    func checked(_ outcome: MailWatch.Outcome) {
        updated.checked(outcome, listing: mailboxID)
        showAge()
        // Over the kept page, the connection working again is the moment
        // to fetch it afresh (D-016).
        if case .failed = outcome { return }
        fetchOverKeptQuietly()
    }

    /// The line at rest said again as of now, if it is saying how fresh the
    /// list is: at each check, and as the app comes back to the front.
    @MainActor
    func showAge() {
        if showingAge { sayAge() }
    }

    /// The iPad's 24-Hour Time switch, its time zone or its region has
    /// changed, and the kept formatters have been let go
    /// (`DisplayDates.didChange`), or the day has turned over, at midnight
    /// or with the clock set (`significantTimeChangeNotification`): the
    /// dates on the rows in sight are written again where they are, as
    /// Mail's are taken to be, and a letter of late last evening reads
    /// "Yesterday" once midnight has passed (B-139). They kept the words
    /// they were drawn with: after 24-Hour Time was switched on, the status
    /// bar read 14:41 and the open letter's row "12:39 PM", until a scroll
    /// drew it anew. The line under the list says its age again, its
    /// "Updated at" a time too.
    ///
    /// Only the rows in sight are named here (`drawRowsInSight`); a row out
    /// of sight has its date written as it comes into it, with the rest of
    /// the row (`willDisplay`, B-143). Since iOS 15 the table prepares the
    /// cell for the row just past the edge ahead of time (cell prefetching,
    /// on by default) and shows it later without asking for it again. That
    /// row is not among `indexPathsForVisibleRows`, so a cell prepared
    /// before the change would come in with the old words, "9:14 PM" after
    /// 24-Hour Time, "11:50 PM" after midnight. From the SDK's header, not
    /// seen.
    ///
    /// The words alone (`RowParts.datesChanged`), the cells patched in place
    /// as for the previews (`apply`): no row is loaded again, so the list
    /// does not move, the selection, the letter open in the pane, stays
    /// highlighted, and Edit mode keeps its ticks; nothing is fetched.
    @objc private func datesChanged() {
        drawRowsInSight(.datesChanged)
        showAge()
    }

    /// One row's cell drawn from the row as it is now, the parts named
    /// (`RowParts`): whole as the table makes it and as it comes into sight
    /// (`cellForRowAt`, `willDisplay`), and as the previews land (`apply`);
    /// the date and VoiceOver's words as the dates change
    /// (`datesChanged`, B-139); the spinner as a draft is tapped or comes
    /// (`showDraftSpinners`). The one writer of a row's cell, so a cell
    /// coming into sight is drawn as a cell made for it now would be.
    ///
    /// Nothing but the cell's own views and words: no row is loaded again,
    /// nothing is selected, deselected or scrolled, and nothing is fetched.
    /// A part already right is set to what it shows, which draws nothing
    /// new; the spinner is started or stopped only when it changes
    /// (`MessageCell.isBusy`).
    private func draw(_ cell: MessageCell, at ip: IndexPath, _ parts: RowParts) {
        guard ip.row < rows.count else { return }
        switch rows[ip.row] {
        case let .thread(thread):
            // In Sent Mail, Drafts and the Outbox the top line names whom
            // the letters are to (`RowNames`, B-060, B-075). In every
            // folder a conversation is marked after the date, with no
            // count, and VoiceOver reads what it names and how many
            // (B-080).
            if parts.contains(.lines) {
                cell.configure(with: thread.displayRow(in: mailbox, mine: mine),
                               marked: thread.marksConversation(in: mailbox))
            } else if parts.contains(.date) {
                cell.drawDate()
            }
            if parts.contains(.busy) {
                cell.isBusy = thread.messages.contains { $0.id == drafts.loading }
            }
            if parts.contains(.label) {
                cell.accessibilityLabel = thread.accessibilityLabel(in: mailbox, mine: mine)
            }
        }
    }

    /// The cells of the rows in sight drawn where they are with `parts`:
    /// the patches (`RowParts.patchesInSight`), so that no row is loaded
    /// again. A cell the table has prepared for a row past the edge is not
    /// among them; it is drawn whole as it comes into sight (`willDisplay`,
    /// B-143), which draws every part a patch draws.
    private func drawRowsInSight(_ parts: RowParts) {
        for ip in tableView.indexPathsForVisibleRows ?? [] {
            guard let cell = tableView.cellForRow(at: ip) as? MessageCell else { continue }
            draw(cell, at: ip, parts)
        }
    }

    /// Puts what the watch has found on the list, if he is where that moves
    /// nothing under him: at the top, with no search, no ticks, and no
    /// finger on the list (`ListLetters.putNewsOn`). Called at every check,
    /// and whenever one of those may have just become true. A list owed a
    /// fetch afresh, since renumbered or since more came than one check puts
    /// on, is fetched then, quietly: he did not ask, so a failure is said on
    /// the line and not in an alert. One such fetch at a time; one that
    /// fails, or is dropped for a search he has started, leaves it owed.
    @MainActor
    private func showNewsIfAtTop() {
        // Asked first: `tableView` loads the view.
        guard letters.holdsNews, isViewLoaded else { return }
        let ticked = tableView.isEditing && !(tableView.indexPathsForSelectedRows ?? []).isEmpty
        let touching = tableView.isTracking || tableView.isDragging || tableView.isDecelerating
        let atTop = ListPlaces.isAtTop(offset: Double(tableView.contentOffset.y),
                                       topInset: Double(tableView.adjustedContentInset.top))
        switch letters.putNewsOn(atTop: atTop, searching: isSearchingOrTyping, ticked: ticked,
                                 touching: touching) {
        case .wait:
            return
        case .refetch:
            guard !refetchingQuietly else { return }
            refetchingQuietly = true
            Task { @MainActor [weak self] in
                await self?.reload(quietly: true)
                self?.refetchingQuietly = false
            }
        case .shown(let added):
            // At the top, where the new rows are: regrouped at the offset he
            // had, the rows he could see would be kept in place and the new
            // ones left above the top of the pane. The selection goes with
            // its letters.
            regroup(to: .top)
            updateEmptyState()
            updateSelectAllTitle()
            loadPreviews(for: added)
        }
    }

    /// A quiet fetch afresh for the watch's news is on its way.
    private var refetchingQuietly = false

    /// A search showing, or one typed and not yet run: either way a fetch
    /// afresh would clear the field under his fingers.
    private var isSearchingOrTyping: Bool {
        letters.isSearching || !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// At rest: a list left past its top closes up to it, and the pull's
    /// spinner held for the rest goes (`PullEnd`, B-103).
    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        closeUpPastTop()
        pullSettled()
        showHeldAlert()
        landFreshPage()
        showNewsIfAtTop()
    }

    /// An animated scroll has ended, at rest: as at the end of a coasting
    /// (B-103). The list's own is only `closeUpPastTop`'s; VoiceOver's
    /// three-finger scroll down to the spinner may end here too, not yet
    /// seen.
    override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        closeUpPastTop()
        pullSettled()
    }

    /// The finger has let go: a page's alert held for it goes up now, as
    /// the list springs back (B-103). The spinner waits for the list to be
    /// at rest, which it is here only with no deceleration to come.
    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        showHeldAlert()
        guard !decelerate else { return }
        pullSettled()
        landFreshPage()
        showNewsIfAtTop()
    }

    /// A finger has taken the list: a spinner held for its rest goes under
    /// the finger, which UIKit ends as it lets go (B-103).
    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // He has moved the list: from here a page above keeps the rows he
        // can see where they are (B-042), the day's row no longer held
        // (`LandedLetter`, B-117).
        landed.letGo()
        pullSettled()
    }

    /// The status bar tapped: the list goes to its top, and the day landed
    /// on is let go as it starts (B-117).
    override func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        landed.letGo()
        return true
    }

    override func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        pullSettled()
        showHeldAlert()
        landFreshPage()
        showNewsIfAtTop()
    }

    // MARK: - Opening the folder at a day

    @objc private func jumpToDateTapped() {
        let picker = JumpToDateViewController()
        picker.onPick = { [weak self] date, scope in
            guard let self else { return }
            // Already looking at everything? Then "all mailboxes" is what
            // this pane is, and there is nothing to switch to.
            if scope == .allMailboxes && self.mailbox.role != .archive {
                self.onJumpAcrossMailboxes?(date)
            } else {
                self.jump(to: date)
            }
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    /// Opens this folder at a day, with mail on both sides of it.
    ///
    /// Replaces the list rather than scrolling the one on screen, because
    /// the message he wants is almost never in it — that is the entire
    /// problem. `listGeneration` is bumped for the same reason `reload`
    /// bumps it: every preview and page fetch in flight belongs to a list
    /// that no longer exists.
    ///
    /// Asked for at the tap on Go, while the sheet is still sliding away,
    /// and said on the status line from then until it has landed or failed.
    @MainActor
    func jump(to date: Date) {
        let generation = startReplacingList()
        let going = working(StatusLine.goingTo(date))
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.landWindow(around: date, generation: generation)
            self.report(outcome, jumpingTo: date)
            going()
        }
    }

    /// Everything in flight belongs to the list about to be replaced.
    /// Returns the new list's generation.
    @MainActor
    private func startReplacingList() -> Int {
        listGeneration += 1
        // Another day: the one held was the last jump's (B-117).
        landed.letGo()
        stopSearching()
        isLoadingPage = false
        isLoadingPrevious = false
        return listGeneration
    }

    /// What he is told about a jump that did not land. Nothing that recent
    /// is said on the status line rather than leaving the list where it
    /// was, which reads as the button having done nothing at all.
    @MainActor
    private func report(_ outcome: ListOpening.Jump, jumpingTo date: Date) {
        switch outcome {
        case .failed(let error):
            ErrorPresenter.show(reaching: error, on: self)
        case .nothingThatRecent:
            showingAge = false
            say("No mail on or after \(IMAPDate.spokenDay(date))")
        case .landed, .superseded:
            break
        }
    }

    /// Fetches the mail around `date` and puts it on screen, unless the list
    /// has been replaced since `generation` was taken. See
    /// `ListOpening.settle`, which decides, and why a failure is no
    /// different there.
    @MainActor
    private func landWindow(around date: Date, generation: Int) async -> ListOpening.Jump {
        let fetched: Result<MessageWindow?, Error>
        do {
            fetched = .success(try await repository.messages(around: date, in: mailbox.id,
                                                             limit: Self.pageSize))
        } catch {
            fetched = .failure(error)
        }
        let outcome = ListOpening.settle(fetched, current: generation == listGeneration)
        if outcome == .landed, let window = try? fetched.get() { show(window) }
        return outcome
    }

    /// Replaces the list with the mail around a day, scrolled to the day.
    @MainActor
    private func show(_ window: MessageWindow) {
        let voiceOverOn = voiceOverHeld()
        defer { keepVoiceOver(voiceOverOn) }
        // Leaving search on would hide the window we just fetched
        // behind the previous result set.
        letters.showWindow(window.messages)
        searchQuery = ""
        searchBar.clear()

        reachedNewestMessage = window.reachedNewest
        reachedOldestMessage = window.reachedOldest
        // Scrolled to the day below, which is the place this list has now.
        _ = places.replaced()
        rebuildRows()
        tableView.reloadData()
        // The letter he was reading is still open in the pane: its row
        // highlighted if the day's list has it, where it is (B-133).
        highlightLetterInPane()
        updateEmptyState()
        updatePageFooter()

        // `.top` and not `.middle`: the day he asked for should be the
        // first line he reads, with the days after it above, which is
        // how a page of a diary opens.
        //
        // `layoutIfNeeded` first, because `scrollToRow` computes its
        // offset from the CURRENT content size and `reloadData` has only
        // scheduled the layout, not performed it. Without it the scroll
        // is computed against the previous list's height.
        //
        // A short folder cannot always honour it — if there is less
        // than a screenful below the anchor the table clamps to its
        // last row, which is correct: there is nowhere further to go.
        tableView.layoutIfNeeded()
        // The anchor is an index into the flat window; the list shows
        // conversations. Scroll to the ROW Mail's list shows the day at:
        // the oldest dated on or after it, a conversation dated by its
        // newest letter (`ListOpening.dayRow`, B-118). With Organize by
        // Thread off, the letter's own row. It was the row that carries
        // the letter, which for one answered in the days after is its
        // conversation's, dated as the reply, up the list.
        let anchorIndex = min(window.anchorIndex, window.messages.count - 1)
        let day = ListOpening.dayRow(in: threads, for: window)
        let landedRow = day?.row
        if let row = landedRow {
            tableView.scrollToRow(at: IndexPath(row: row, section: 0),
                                  at: .top, animated: false)
        }
        // And kept there as the pages above come, the first asked for as
        // it lands (B-094), by the letter that heads it (`LandedLetter`,
        // B-117). A reply on one of them takes the row up the list, dated
        // as the reply, and the day's next row comes into its place
        // (B-118). The window brings the page above it, so a reply among
        // the next fifty is in its row from the first frame
        // (`PageWindow.jumpWindow`).
        landed.landed(on: landedRow.map { threads[$0].id })

        // The bottom bar stops reporting freshness and starts reporting
        // WHERE HE IS, which for a list that no longer starts at today
        // is the more urgent of the two. It goes back to "Updated Just
        // Now" on the next refresh. The day of the row on top: the day
        // asked for, or with every letter of it answered later, the day of
        // the row opened on, as for a day with no mail (B-118).
        showingAge = false
        say("Showing \(IMAPDate.spokenDay(day?.shown ?? window.landedOn))")
        // No pull on a day's list, whose top is not the folder's (B-103).
        placePull()

        // The rows he sees first, from the row landed on down, then the
        // page above them (`PreviewPass.groups(for:from:)`, B-117).
        let seenFrom = landedRow.flatMap { row in
            window.messages.firstIndex { $0.id == threads[row].id }
        } ?? anchorIndex
        loadPreviews(for: window.messages, from: seenFrom)
    }

    // MARK: - Paging

    /// Fetches the next fifty and appends them.
    ///
    /// Appending, never replacing: the rows already on screen keep their
    /// index paths, so nothing under his thumb moves while he is reading.
    /// That is the whole reason paging is by UID rather than by page number
    /// — a page index shifts the instant mail is delivered, and the row he
    /// was about to tap becomes a different letter.
    @MainActor
    private func loadNextPage() {
        // Not below the kept page (D-016): nothing under it is kept, and its
        // rows are an earlier launch's until the fresh page has landed.
        guard !isLoadingPage, !reachedOldestMessage, letters.isSearching || !letters.fromShelf,
              let cursor = visible.last?.id else { return }

        isLoadingPage = true
        updatePageFooter()
        let generation = listGeneration
        // Captured now, because both can change while the fetch is in
        // flight and the page that comes back must be filed against the
        // question that was asked.
        let searching = letters.isSearching
        let query = searchQuery
        let scope = searchScope

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isLoadingPage = false
                self.updatePageFooter()
            }
            let older: [MessageSummary]
            do {
                // Search pages exactly like the folder does. It used to
                // stop dead at the newest hundred hits with nothing on
                // screen to say so — for a man searching years of
                // mail, a silent ceiling is the letter simply not being
                // there.
                older = searching
                    ? try await self.repository.search(in: self.mailbox.id, query: query,
                                                       scope: scope, beforeUID: cursor,
                                                       limit: Self.pageSize)
                    : try await self.repository.listMessages(in: self.mailbox.id,
                                                             beforeUID: cursor,
                                                             limit: Self.pageSize)
            } catch {
                // No alert. He did not ask for this — he scrolled — so an
                // error box over the letters would be the app interrupting
                // him about work he never requested. The footer becomes a
                // labelled retry instead.
                self.loadFailed = true
                return
            }
            // The folder was reloaded or the search changed while this was
            // in flight; these rows belong to a list that is gone.
            guard generation == self.listGeneration else { return }

            self.loadFailed = false
            if older.count < Self.pageSize { self.reachedOldestMessage = true }

            // Deduped by id. The snapshot this page was cut from is stable,
            // but a message MOVED into this folder by another client can
            // still appear twice across two pages, and a duplicated row is
            // a letter that cannot be told from its twin.
            let fresh = self.letters.appendPage(older, toResults: searching)
            guard !fresh.isEmpty else { return }

            // Regroup rather than insert at the tail. A message in this
            // page can belong to a conversation already on screen, in
            // which case it does not add a row at the bottom at all — it
            // joins one further up and changes its count. "The new rows
            // are the last N" stopped being true the moment the list
            // grouped. `regroup` puts the selection back by id.
            self.regroup()
            // A page of hits comes with the previews already drawn, and
            // neither page asks for a letter drawn with no words (B-135).
            self.loadPreviews(for: self.letters.toDraw(fresh))
        }
    }

    /// Fetches the fifty messages immediately NEWER and puts them on top.
    ///
    /// The direction that only exists after a date jump. Prepending is the
    /// hard one: every row already on screen changes index, so the scroll
    /// position has to be corrected by hand or the list lurches downward by
    /// a page and he loses the letter he was reading.
    ///
    /// Corrected by remembering the rows he can see and putting them back
    /// where they were (`regroup`, `ListPlace`), not by the rows added. It
    /// used to add the change in the row count times the fixed row height,
    /// which is exact only if the new rows all go above the old ones. They
    /// do not: a newer letter in a conversation already listed takes that
    /// conversation's row up to the new page, so one below the top of the
    /// pane slipped the list by a row, and the highlight, read back by row
    /// number after the rows were rebuilt, landed on another letter.
    @MainActor
    private func loadPreviousPage() {
        guard !isLoadingPrevious, !reachedNewestMessage, !letters.isSearching,
              let cursor = letters.folder.first?.id else { return }

        isLoadingPrevious = true
        let generation = listGeneration

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isLoadingPrevious = false }

            let newer: [MessageSummary]
            do {
                newer = try await self.repository.listMessages(in: self.mailbox.id,
                                                               afterUID: cursor,
                                                               limit: Self.pageSize)
            } catch {
                // Silent, like the downward direction: he scrolled, he did
                // not ask. Refresh is the way back to the top if it keeps
                // failing.
                return
            }
            guard generation == self.listGeneration else { return }

            if newer.count < Self.pageSize {
                self.reachedNewestMessage = true
                // At the folder's top again: the pull with it (B-103).
                self.placePull()
            }

            let fresh = self.letters.prependPage(newer)
            guard !fresh.isEmpty else { return }

            // The rows he can see and the highlight are taken before the
            // rows are rebuilt and put back after, by their letters; see
            // `regroup`. No animation: an animated change ABOVE the viewport
            // animates the content out from under the reader, and the
            // offset fix would land a frame late and visibly jump.
            //
            // The row a jump opened on, while he has not moved the list, is
            // the row held, by its letter; a reply on this page joins it and
            // takes it up the list, and the day's next row comes into its
            // place (`LandedLetter`, B-117, B-118).
            let move = self.landed.move(forPageAboveFrom: self.place())
            UIView.performWithoutAnimation { self.regroup(to: move) }
            self.loadPreviews(for: fresh)
        }
    }

    /// Whether the last page attempt failed, which turns the footer into a
    /// labelled retry rather than leaving him to guess.
    private var loadFailed = false

    @MainActor
    private func updatePageFooter() {
        // Nothing to say once the oldest message is on screen. Search
        // results now DO get a footer: they page like everything else, and
        // the old "no cursor to page from" is no longer true.
        guard !reachedOldestMessage else {
            tableView.tableFooterView = UIView()
            return
        }

        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = Theme.secondaryText
        if isLoadingPage {
            var title = AttributedString("Loading more messages…")
            title.font = Theme.fontToolbarStatus
            config.attributedTitle = title
        } else if loadFailed {
            var title = AttributedString("Load More Messages")
            title.font = Theme.fontBarButton
            config.attributedTitle = title
            config.baseForegroundColor = Theme.tintBlue
        } else {
            var title = AttributedString("Load More Messages")
            title.font = Theme.fontToolbarStatus
            config.attributedTitle = title
        }
        pageFooter.configuration = config
        pageFooter.isEnabled = !isLoadingPage
        pageFooter.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 56)
        tableView.tableFooterView = pageFooter
    }

    // MARK: - Previews

    /// Fills in the two grey lines under each subject, after the rows are up.
    ///
    /// Deliberately a second pass. The rest of a row comes from the ENVELOPE,
    /// which arrives for the whole page in one reply; the preview is body
    /// text, and a page of HTML mail is several hundred kilobytes of it.
    /// Waiting for that before showing anything would turn a list that appears
    /// in about a second into one that appears in four — so the rows go up
    /// blank there and fill in behind, which is what Mail itself does.
    ///
    /// Nothing moves when they arrive: the row height is fixed and the space
    /// is already reserved, so this is text appearing in a gap rather than the
    /// list reflowing under a reader's eye.
    /// Takes the ROWS, not their ids, because a row no longer necessarily
    /// belongs to the folder on screen.
    ///
    /// An "All Mailboxes" search runs against Gmail's All Mail and its hits
    /// carry All Mail's UIDs. Asking the Inbox for them fetches whatever
    /// happens to wear those numbers there, or nothing — which is what the
    /// first device run showed: every search result came up with two blank
    /// grey lines under it.
    ///
    /// One mailbox at a time, in ONE task, stopping as soon as the list has
    /// been replaced: `PreviewPass`, which is where the order and the reasons
    /// for it live, and where they are tested. Returns that task, nil when
    /// there is nothing to fetch.
    ///
    /// `from`: the row of `rows` to begin at, the rest after, from the top
    /// (`PreviewPass.groups(for:from:)`).
    @MainActor
    @discardableResult
    private func loadPreviews(for rows: [MessageSummary], from start: Int = 0) -> Task<Void, Never>? {
        guard !rows.isEmpty else { return nil }
        let generation = listGeneration
        let groups = PreviewPass.groups(for: rows, from: start)
        let repository = self.repository
        return Task { @MainActor [weak self] in
            await PreviewPass.run(
                groups,
                fetch: { ids, mailboxID in
                    try await repository.previews(for: ids, in: mailboxID)
                },
                isCurrent: { @MainActor in
                    generation == self?.listGeneration
                },
                apply: { @MainActor previews, group in
                    self?.apply(previews, in: group.mailboxID)
                },
                aside: { @MainActor previews, group in
                    self?.letters.previewsCameLate(previews, in: group.mailboxID, for: rows)
                })
        }
    }

    /// Patches the rows in place rather than calling `reloadRows`.
    ///
    /// `reloadRows` deselects what it reloads, and on the iPad the selected
    /// row is the message open in the pane to the right — so filling in a
    /// preview would visibly unhighlight the letter being read. A row out
    /// of sight picks the new text up from the model as it comes into
    /// sight: drawn whole then (`willDisplay`), the cell the table made
    /// ahead of time for the row just past the edge too, which is not among
    /// the rows in sight. That one used to come in with its two grey lines
    /// empty, its preview held and never asked for again (B-143).
    ///
    /// Into the rows of the folder the previews were asked of alone
    /// (`ListLetters.apply(previews:in:)`).
    @MainActor
    private func apply(_ previews: [String: String], in mailboxID: String) {
        letters.apply(previews: previews, in: mailboxID)

        // Regrouped first so the rows hold the new text; the row COUNT
        // cannot change, since a preview does not decide what threads
        // with what, so the cells can be patched in place.
        rebuildRows()
        drawRowsInSight(.previewsLanded)
    }

    private func updateEmptyState() {
        // An empty folder must say so. A blank white rectangle is how an app
        // looks broken, and this user cannot tell the two apart.
        emptyLabel.isHidden = !rows.isEmpty
        if !letters.isSearching {
            emptyLabel.text = "No messages"
        } else if searchFailed {
            emptyLabel.text = "Could not search. Check the connection."
        } else {
            emptyLabel.text = "No results"
        }
    }

    // MARK: - The status line

    /// Something for the status line to say for good: how fresh the list
    /// is, or where he is in it. See `StatusLine`.
    @MainActor
    private func say(_ text: String) {
        status.rest(text)
        showStatus()
    }

    /// The line at rest says how fresh the list is, as of now, and how many
    /// letters wait in the Outbox. The Outbox's own says only that.
    @MainActor
    private func sayAge() {
        let unsent = kept.outbox.count
        say(isOutbox ? Outbox.unsent(unsent) ?? "" : updated.text(now: Date(), unsent: unsent))
    }

    /// Says `text` on the status line while something he asked for is on
    /// its way: a jump, a Move from here or from the reading pane, or Edit
    /// mode's Delete.
    /// Returns what to call when it is done, whichever way it went.
    @MainActor
    func working(_ text: String) -> () -> Void {
        let id = status.start(text)
        showStatus()
        return { [weak self] in
            self?.status.finish(id)
            self?.showStatus()
        }
    }

    private func showStatus() {
        statusLabel.text = status.text
        // Measured against a fixed width, not `sizeToFit()`: a label of more
        // than one line fits itself to the width it already has, so after a
        // short line such as "No Connection" it never grew back, and
        // "Updated Just Now" came out on three lines and "1 Unsent Message"
        // cut short (seen on the iPad). The width is what the bar leaves
        // between Refresh and Settings in the narrowest list, three panes on
        // an 11-inch iPad.
        let fit = statusLabel.sizeThatFits(CGSize(width: Self.statusWidth,
                                                  height: .greatestFiniteMagnitude))
        statusLabel.frame.size = CGSize(width: ceil(min(fit.width, Self.statusWidth)),
                                        height: ceil(fit.height))
    }

    /// The widest the status line may be; see `showStatus`.
    private static let statusWidth: CGFloat = 150

    /// The bottom bar uses the navigation controller's own toolbar rather than
    /// a subview. In a UITableViewController `self.view` IS the table view, so
    /// a "pinned" subview scrolls away with the content - which is exactly what
    /// happened on the first build: "Updated Just Now" slid off the bottom.
    private func buildBottomBar() {
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let status = UIBarButtonItem(customView: statusLabel)
        // Bottom-left, the slot the reference uses for the filter control, and
        // deliberately beside the freshness label rather than in the folder
        // pane: "Updated Just Now" says how stale this is, and the button
        // immediately left of it is what fixes that.
        let refresh = UIBarButtonItem(title: "Refresh", style: .plain,
                                      target: self, action: #selector(refreshTapped))
        refresh.setTitleTextAttributes([.font: Theme.fontBarButton], for: .normal)
        refresh.width = Theme.toolbarLeadingSlot
        // Settings occupies what used to be dead space of the same width,
        // kept there so the status label still centres in the PANE rather
        // than in whatever Refresh left over. Putting it here rather than in
        // the folder pane is forced: that pane is 250 pt wide and a button
        // beside "Mailboxes" left 8.5 pt between them, measured on device.
        //
        // It has to exist somewhere visible, because `MailError` has been
        // telling him "Password needs to be updated in Settings." since the
        // error strings were written, and until now there was no Settings —
        // an instruction pointing at a screen that did not exist.
        let settings = UIBarButtonItem(title: "Settings", style: .plain,
                                       target: self, action: #selector(settingsTapped))
        settings.setTitleTextAttributes([.font: Theme.fontBarButton], for: .normal)
        settings.width = Theme.toolbarLeadingSlot
        let mirror = settings
        // Mark / Move / Trash is Mail's own edit-mode bar, in that order.
        //
        // Leaving something unread is how a great many people say "come
        // back to this", and until now the app could set `\Seen` but never
        // clear it — the repository had the call and nothing reached it.
        // Putting it here rather than behind a swipe or a long press keeps
        // the promise that nothing needs a gesture beyond tap and scroll.
        markItem = UIBarButtonItem(title: "Mark", style: .plain,
                                   target: self, action: #selector(markSelected))
        moveItem = UIBarButtonItem(title: "Move", style: .plain,
                                   target: self, action: #selector(moveSelected))
        deleteItem = UIBarButtonItem(title: "Delete", style: .plain,
                                     target: self, action: #selector(deleteSelected))
        deleteItem.tintColor = Theme.destructive
        // Mark All as Read, as Mail actually offers it.
        //
        // Mail has no button by that name. What it has is Select All in
        // edit mode, which composes with the Mark sheet already here — so
        // "mark everything read" is Edit, Select All, Mark, Mark as Read.
        // Building a dedicated one-tap button instead would have been a
        // new, irreversible-looking control that Mail does not have, and it
        // would not have given him Select All + Move or Select All +
        // Delete, which come free this way.
        selectAllItem = UIBarButtonItem(title: "Select All", style: .plain,
                                        target: self, action: #selector(selectAllTapped))
        for item in [markItem, moveItem, deleteItem, selectAllItem] {
            item?.setTitleTextAttributes([.font: Theme.fontBarButton], for: .normal)
        }
        browseItems = [refresh, flex, status, flex, mirror]
        editItems = [selectAllItem, flex, markItem, flex, moveItem, flex, deleteItem]
        toolbarItems = browseItems
    }

    /// Refreshes the folders too, via the container — a person who taps
    /// Refresh means "get my mail", not "get my mail but leave the unread
    /// counts beside the folder names stale".
    ///
    /// And sends what waits in the Outbox, large letters too, the owner's
    /// rule to match Mail, in any folder, the Outbox included: once the
    /// page, its previews and the counts have come, so a forward's files
    /// fetched from Gmail do not hold them up (`RefreshTap`, B-072). The page
    /// sets off no pass of its own. A page that did not come sets off none,
    /// as before.
    ///
    /// The pull down past the top of the list is the same Refresh (B-103):
    /// both come here. One page out at a time: a tap or a pull while one is
    /// out starts nothing, and that page's answer ends the pull's spinner,
    /// once the list is at rest (`endPullAtRest`).
    /// "Checking for Mail…" is on the line under the list while the page
    /// is out, and once it has come the age the page has set, "Updated Just
    /// Now". Not in the Outbox, which is on the iPad and has no mail to
    /// check for: its line says what waits there.
    @objc private func refreshTapped() {
        refresh(fromPull: false)
    }

    /// The pull, let go of past the top of the list (B-103).
    @objc private func pulled() {
        refresh(fromPull: true)
    }

    @MainActor
    private func refresh(fromPull: Bool) {
        // A pull where none is offered now: its spinner put away, and
        // nothing fetched.
        if fromPull, !pullAllowed {
            putPullAway()
            return
        }
        RefreshTap.start(
            gate: refreshes,
            page: {
                let checking = self.isOutbox ? nil : self.working(StatusLine.checking)
                defer { checking?() }
                // His letters of each conversation looked for afresh in
                // Sent Mail at the next one opened (B-104).
                await self.repository.forgetLettersOfHis()
                return await self.reload(passing: false)
            },
            answered: { self.endPullAtRest() },
            counts: { quietly in self.onRefreshRequested?(quietly) },
            shown: {
                await self.pagePreviews?.value
                await self.countsCame()
            },
            pass: { _ = self.kept.uploadWaiting(to: self.repository, for: .refresh) })
    }

    // MARK: - The pull (B-103)

    /// Pulled down past the top of the list and let go, it checks for mail
    /// as Mail's list does: `refresh`.
    private let pull = UIRefreshControl()

    /// One page of his Refresh out at a time, the button's or the pull's.
    private let refreshes = RefreshTap.Gate()

    /// The panes are moving (`PaneMotion`): no pull meanwhile. Set by the
    /// container as the motion starts and ends.
    var panesMoving = false {
        didSet {
            guard panesMoving != oldValue else { return }
            // The panes moving let the day landed on go (B-117).
            if panesMoving { landed.letGo() }
            placePull()
        }
    }

    /// Whether the pull is offered for the list as it is now; see
    /// `PullRefresh`. A search counts from the field taking the keyboard,
    /// which grows the band, to Cancel.
    @MainActor
    private var pullAllowed: Bool {
        PullRefresh.allowed(editing: tableView.isEditing,
                            searching: isSearchingOrTyping || searchBar.isExpanded,
                            fromNewest: reachedNewestMessage,
                            moving: panesMoving)
    }

    /// The pull put on the list, or taken off it, as `pullAllowed` says:
    /// called whenever one of the things it asks may have changed. Its
    /// spinner is put away before it is taken off, an end held for the list
    /// to come to rest with it, so a spinner can never be left on a list
    /// that no longer has the pull: Edit mode, a search, a day's list and
    /// the panes' motion. A page it set off goes on, as a tap's does.
    @MainActor
    private func placePull() {
        // Asked first: `tableView` loads the view.
        guard isViewLoaded else { return }
        let offered: UIRefreshControl? = pullAllowed ? pull : nil
        guard tableView.refreshControl !== offered else { return }
        if offered == nil { putPullAway() }
        tableView.refreshControl = offered
    }

    /// When the spinner goes once its page has answered (`PullEnd`).
    private var pullEnd = PullEnd()

    /// The page has answered, come, failed or put aside (`RefreshTap`): the
    /// spinner put away now under a finger on the list, which UIKit ends as
    /// the finger lets go, or with the list still; held while the list
    /// springs back or coasts with no finger on it, until it comes to rest
    /// (`pullSettled`), and put away at the bound if UIKit never says so
    /// (`putAwayAtBound`). Put away as it sprang back, the spinner left the
    /// list 60 pt below its top, seen on the iPad on 2026-10-22 (B-103).
    @MainActor
    private func endPullAtRest() {
        switch pullEnd.answered(spinning: pull.isRefreshing, fingerDown: tableView.isTracking,
                                moving: listMoving) {
        case .now:
            pull.endRefreshing()
        case .held(let hold):
            putAwayAtBound(hold, round: 1)
        }
    }

    /// A held end put away once `PullEnd.bound` has gone by, if UIKit has
    /// not said meanwhile that the list is at rest: at once with a finger
    /// on it or the list still, and with it still moving waited for one
    /// more bound, and then put away whatever it does (`PullEnd.rounds`).
    @MainActor
    private func putAwayAtBound(_ hold: Int, round: Int) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(PullEnd.bound))
            guard let self else { return }
            switch self.pullEnd.due(hold, round: round, fingerDown: self.tableView.isTracking,
                                    moving: self.listMoving) {
            case .gone:
                return
            case .now:
                self.pull.endRefreshing()
            case .again:
                self.putAwayAtBound(hold, round: round + 1)
            }
        }
    }

    /// Whether the list, with no finger on it, still moves: coasting or
    /// springing back, or past its top, the spinner's room counted
    /// (`PullEnd.moving`).
    @MainActor
    private var listMoving: Bool {
        PullEnd.moving(decelerating: tableView.isDecelerating,
                       offset: Double(tableView.contentOffset.y),
                       topInset: Double(tableView.adjustedContentInset.top))
    }

    /// A list come to rest past its top, with no spinner turning and no
    /// finger on it, taken up to its top, as the spring-back would have
    /// taken it (`PullEnd.leftPastTop`, B-103). Seen on the iPad on
    /// 2026-10-22: the spinner put away as the list sprang back left it
    /// resting 60 pt below its top until it was touched, and while it rested
    /// there `PaneMotion.isBouncing` had every switch made with no motion.
    /// The answer's end waits for the rest now, but the spinner put away at
    /// once can still end mid-spring-back: Edit, the search field, Home or
    /// the list leaving the screen just then, or a bound gone by. At the end
    /// of a coasting or spring-back, and of an animated scroll, before a
    /// spinner held for the rest is put away, which UIKit takes to the top
    /// itself.
    @MainActor
    private func closeUpPastTop() {
        guard PullEnd.leftPastTop(spinning: pull.isRefreshing, fingerDown: tableView.isTracking,
                                  offset: Double(tableView.contentOffset.y),
                                  topInset: Double(tableView.adjustedContentInset.top)) else {
            return
        }
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top),
                                   animated: true)
    }

    /// The list has come to rest, or a finger has taken it: a spinner held
    /// for that put away now.
    @MainActor
    private func pullSettled() {
        guard pullEnd.settled() else { return }
        pull.endRefreshing()
    }

    /// The spinner put away at once, and nothing left held for the list's
    /// rest: wherever the pull goes off the list or the list leaves the
    /// screen.
    @MainActor
    private func putPullAway() {
        pullEnd.putAway()
        pull.endRefreshing()
    }

    /// The pull's spinner put away, the page it set off going on: this list
    /// is leaving the screen for another folder's (`RootViewController`).
    @MainActor
    func endPull() {
        putPullAway()
    }

    /// Out of sight: the spinner put away, and a page's alert waiting for
    /// the finger dropped, with nothing left to put it over.
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        putPullAway()
        dropHeldAlert()
    }

    /// The list's size as it was last laid out.
    private var laidOutSize = CGSize.zero

    /// Laid out at another size: the panes have moved, two to three or
    /// back, at once or with the motion, or the iPad has turned. The day a
    /// jump landed on is let go (B-117).
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.size != laidOutSize else { return }
        laidOutSize = view.bounds.size
        landed.letGo()
    }

    /// Home, or another app: the spinner is not left turning for him to
    /// come back to. The line under the list says the page is out until it
    /// has come.
    @objc private func wentToBackground() {
        putPullAway()
    }

    // MARK: - A page's alert, once the finger has let go (B-103)

    /// A page's alert waiting for his finger to let go of the list
    /// (`LetGoHold`), and what looks for a finger that never dragged to
    /// have lifted.
    private var afterLetGo = LetGoHold<Error>()
    private var letGoWatch: Task<Void, Never>?

    /// The search field has the keyboard: the screens leave it there,
    /// rather than take back the place where shake and three-finger undo
    /// are asked for (`RootViewController.takeUndo`, B-157).
    var isTyping: Bool { isViewLoaded && searchBar.isTyping }

    /// His finger is on the list, or the list is still moving from one, or
    /// a page's alert waits for the finger to let go: an alert he did not
    /// ask for is not put up now, since one put up under a held pull takes
    /// the end of the drag (B-103). "Touching" as `landFreshPage` and
    /// `showNewsIfAtTop` have it. Asked by the warning before the app stops
    /// opening, which tries again at the next check (B-137).
    var isInHand: Bool {
        guard isViewLoaded else { return false }
        return tableView.isTracking || tableView.isDragging || tableView.isDecelerating
            || afterLetGo.held != nil
    }

    /// A page he asked for has failed: its alert put up now, or, while his
    /// finger is on the list, as it lets go. Put up under a pull still held,
    /// it took the end of the drag, and the list stayed pulled down with the
    /// spinner turning after OK, seen on the iPad on 2026-10-22.
    @MainActor
    private func showWhenLetGo(_ error: Error) {
        guard let now = afterLetGo.show(error, fingerDown: tableView.isTracking) else {
            watchForLetGo()
            return
        }
        ErrorPresenter.show(reaching: now, on: self)
    }

    /// The finger has let go: the alert held for it, if one is, put up.
    @MainActor
    private func showHeldAlert() {
        stopWatchingForLetGo()
        guard let held = afterLetGo.letGo() else { return }
        ErrorPresenter.show(reaching: held, on: self)
    }

    /// The list has left the screen: the alert held is not put up.
    @MainActor
    private func dropHeldAlert() {
        stopWatchingForLetGo()
        afterLetGo.drop()
    }

    /// A finger that only rested on the list tells it nothing as it lifts:
    /// looked for every `liftCheck`, as for the kept page.
    @MainActor
    private func watchForLetGo() {
        guard letGoWatch == nil else { return }
        letGoWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.liftCheck)
                guard let self, !Task.isCancelled else { return }
                if !self.tableView.isTracking {
                    self.showHeldAlert()
                    return
                }
            }
        }
    }

    @MainActor
    private func stopWatchingForLetGo() {
        letGoWatch?.cancel()
        letGoWatch = nil
    }

    /// Multi-select, which is what Edit is for: the one route to deleting
    /// more than one conversation at a time. A drag on a row deletes that
    /// row's, as Mail's does (B-156), and is the thing Mail's Undo is for
    /// (B-157).
    @objc private func editTapped() {
        // His ticks are his to keep where they are (B-117).
        landed.letGo()
        let editing = !tableView.isEditing
        tableView.setEditing(editing, animated: true)
        // No pull in Edit mode, where the page would drop his ticks (B-103).
        placePull()
        navigationItem.rightBarButtonItem?.title = editing ? "Done" : "Edit"
        setToolbarItems(editing ? editItems : browseItems, animated: true)
        updateSelectAllTitle()
        // His ticks have gone with Edit mode: what the watch held can go on,
        // and a fresh page that waited over the kept one (D-016). The
        // letter still open in the pane has its row highlighted again,
        // which Edit mode took away (B-133).
        if !editing {
            highlightLetterInPane()
            landFreshPage()
            showNewsIfAtTop()
        }
    }

    /// Highlights the row of the letter the reading pane shows, if the list
    /// has it (`ListEdit.paneRow`), where the table has dropped the
    /// highlight with the letter still open: at Done, Edit mode having
    /// cleared the selection as it began, and on a day's list, whose rows
    /// replace the list's (B-133). Mail keeps the open message's row
    /// selected. Not scrolled to, and nothing opened: `selectRow` tells the
    /// delegate nothing, so there is no tap, no read mark and no download.
    /// Never in Edit mode, where a selected row is a tick.
    @MainActor
    private func highlightLetterInPane() {
        guard !tableView.isEditing,
              let row = ListEdit.paneRow(in: threads, showing: lettersInPane()) else { return }
        tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false,
                            scrollPosition: .none)
    }

    /// Ticks, or unticks, every conversation in the list.
    ///
    /// The scope is what is LOADED, which is the same scope Mail's own
    /// Select All has and the only honest one available: a folder is paged
    /// fifty at a time and "all" cannot mean the thousands of letters in
    /// All Mail that this device has never seen. The title says which state
    /// the next tap produces, so it is never a guess.
    @objc private func selectAllTapped() {
        let alreadyAll = (tableView.indexPathsForSelectedRows?.count ?? 0) == rows.count
        for row in 0..<rows.count {
            let ip = IndexPath(row: row, section: 0)
            if alreadyAll {
                tableView.deselectRow(at: ip, animated: false)
            } else {
                tableView.selectRow(at: ip, animated: false, scrollPosition: .none)
            }
        }
        updateSelectAllTitle()
        // Deselect All is the last tick taken off too.
        landFreshPage()
        showNewsIfAtTop()
    }

    private func updateSelectAllTitle() {
        guard let selectAllItem else { return }
        let all = rows.count > 0 && (tableView.indexPathsForSelectedRows?.count ?? 0) == rows.count
        selectAllItem.title = all ? "Deselect All" : "Select All"
        selectAllItem.isEnabled = rows.count > 0
    }

    /// Ticking a conversation acts on ALL of it, which is what Mail does
    /// and what the row means: he chose the thread, not a letter inside it.
    /// In the list's order turned over, the oldest first, not the order he
    /// ticked the rows in (B-062, B-084).
    private var selectedMessages: [MessageSummary] {
        ListBatch.letters(ticked: (tableView.indexPathsForSelectedRows ?? []).map(\.row),
                          in: threads)
    }

    /// Every letter he ticked comes off at the tap and Edit mode ends, as
    /// in Mail; "Deleting…" is on the status line until the server has
    /// answered for each, and a letter it did not take comes back, and he
    /// is told why (`ListBatch`, B-062). Each write used to go with `try?`
    /// and the list was fetched again after all of them: a refusal said
    /// nothing, and nothing said Delete was working. Inside Trash, where
    /// Delete erases, he is asked first (`EraseQuestion`), and Cancel leaves
    /// his ticks as they were.
    ///
    /// A letter kept on the iPad goes from the iPad, as Delete Draft in the
    /// composer takes it (`LocalDrafts.delete`). Handed to the repository
    /// with the rest, as it used to be, it was a write that could never
    /// land, spent a probe and failed on its id, silently, and the row came
    /// back with the reload.
    @objc private func deleteSelected() {
        let chosen = selectedMessages
        guard !chosen.isEmpty else { return }
        guard let question = EraseQuestion.before(deleting: chosen,
                                                  role: { self.role(of: $0) }) else {
            delete(chosen)
            return
        }
        EraseConfirmation.ask(question, on: self) { [weak self] in self?.delete(chosen) }
    }

    /// Edit mode's Delete, asked or not. The letters kept on the iPad go
    /// from it at once, each on its own: putting one away can wait for an
    /// upload of it still on its way (`LocalDrafts.tidy`), and the letters
    /// on the server do not wait for that.
    @MainActor
    private func delete(_ chosen: [MessageSummary]) {
        if tableView.isEditing { editTapped() }
        let kept = self.kept
        let repository = self.repository
        for m in chosen {
            guard let key = LocalDraft.key(ofRow: m.id) else { continue }
            Task { @MainActor in await kept.delete(key, from: repository) }
        }
        runBatch(.delete, on: onServer(chosen), saying: StatusLine.deleting)
    }

    /// Edit mode's Delete or Move of `chosen`, whose rows go as this is
    /// called: `words` on the status line until the server has answered for
    /// every one, the reading pane emptied if it shows one of them, and
    /// the refusal, if there was one, said as the reading pane says it.
    /// The letters it did not take are back on the list where they stood,
    /// not ticked, since Edit mode ended at the tap. See `ListBatch`.
    ///
    /// The window is kept, weakly, for the refusal: if he has opened
    /// another folder by the time it comes, this list has left the screen,
    /// and the alert goes over what is in front instead (`alertHost`).
    ///
    /// What the server took is one step of Mail's Undo (B-157), handed up
    /// once the batch has ended (`onUndoable`): a refusal stops the rest,
    /// and the letters that went are the step.
    @MainActor
    private func runBatch(_ action: PaneAction, on chosen: [MessageSummary],
                          saying words: String) {
        guard !chosen.isEmpty else { return }
        let done = working(words)
        onLettersLeaving?(chosen)
        Task { @MainActor [weak window = view.window] in
            var landings: [String: MoveLanding] = [:]
            let outcome = await ListBatch.run(
                action, on: chosen, role: { self.role(of: $0) },
                list: self.letters, repository: self.repository,
                requestSweep: { [weak self] in self?.requestSweep?() },
                landed: { letter, landing in landings[letter.id] = landing })
            done()
            let took = chosen.filter { outcome.taken.contains($0.id) }
            if let step = UndoableMove.after(action, took: took, landings: landings,
                                             role: { self.role(of: $0) }) {
                self.onUndoable?(step, self.letters)
            }
            if let refusal = outcome.refusal {
                ErrorPresenter.show(reaching: refusal, on: self.alertHost(in: window))
            }
        }
    }

    /// What a batch's refusal is put over: this list while it is in the
    /// window, and once it has left it, as it does when he opens another
    /// folder while the batch is out, whatever is in front in `window`, the
    /// one it was in when the batch began: the reading pane, which stays,
    /// or a sheet over it. Put over the list that had gone, the alert was
    /// dropped (`ErrorPresenter`), and nothing told him that the letters
    /// back on the folder he had left were still there. Never the warning
    /// before the app stops opening (`OverTheMail.front`): the refusal waits
    /// for its OK, and put over the warning it went with it, unseen.
    private func alertHost(in window: UIWindow?) -> UIViewController {
        guard viewIfLoaded?.window == nil, let root = window?.rootViewController else {
            return self
        }
        return ErrorPresenter.over(root).front(root: root)
    }

    /// The role of the folder a letter was listed from: this list's, or for
    /// an All Mailboxes hit one of the folders the container has listed.
    private func role(of mailboxID: String) -> Mailbox.Role? {
        ([mailbox] + folders()).role(of: mailboxID)
    }

    /// Not the letters kept on the iPad, which are not on the server to be
    /// marked, and are always read.
    @objc private func markSelected() {
        let chosen = onServer(selectedMessages)
        guard !chosen.isEmpty else { return }

        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.popoverPresentationController?.barButtonItem = markItem
        sheet.addAction(UIAlertAction(title: "Mark as Unread", style: .default) {
            [weak self] _ in self?.applyRead(false, to: chosen)
        })
        sheet.addAction(UIAlertAction(title: "Mark as Read", style: .default) {
            [weak self] _ in self?.applyRead(true, to: chosen)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    /// Sets or clears `\Seen` on a selection, and keeps the folder counters
    /// honest about it.
    ///
    /// The counter arithmetic is the fiddly half. `ListLetters` remembers
    /// which messages this screen has already billed as a -1, so that a
    /// reload deriving `isRead` from pre-STORE server flags cannot bill the
    /// same letter twice. Marking something unread has to UNDO that
    /// bookkeeping as well as adding one back, or reading it again later
    /// would be free and the count would drift low — and a count that is
    /// too low says "no new mail" when there is some, which is the failure
    /// the sidebar exists to prevent.
    @MainActor
    private func applyRead(_ read: Bool, to chosen: [MessageSummary]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for m in chosen where m.isRead != read {
                do {
                    try await self.repository.setRead(read, id: m.id, gmailMessageID: m.gmailMessageID,
                                                      mailboxID: m.mailboxID)
                } catch is MailShelf.NotTheKeptLetter {
                    // A kept row the server says is another letter: off the
                    // list, if it is still that row, and nothing sent (D-016).
                    PaneActions.notTheKeptLetter(m, list: self.letters)
                    continue
                } catch {
                    continue          // leave this one as it was
                }
                // Taken: held over a listing asked before now, whose flags
                // are from before this STORE, and billed, as the reading
                // pane's Mark is (`ListLetters.readTaken`).
                self.letters.reading(m, read: read)
                self.letters.readTaken(m, read: read)
            }
            if self.tableView.isEditing { self.editTapped() }
            self.regroup()
        }
    }

    /// Not the letters kept on the iPad: there is nothing on the server to
    /// move until they have gone to Drafts, and they stay in Drafts' list.
    /// Moved as Delete is, by `runBatch`.
    @objc private func moveSelected() {
        let chosen = onServer(selectedMessages)
        guard !chosen.isEmpty else { return }
        let move = MoveMessageViewController(repository: repository,
                                             excluding: mailbox.id) { [weak self] destination in
            guard let self else { return }
            // At the tap, while the sheet slides away: the rows go and Edit
            // mode ends, and "Moving…" is on the status line until the
            // server has answered for each letter. One it did not take
            // comes back, and he is told, as for Delete (B-062).
            if self.tableView.isEditing { self.editTapped() }
            self.runBatch(.move(to: destination), on: chosen, saying: StatusLine.moving)
        }
        let nav = UINavigationController(rootViewController: move)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    /// `letters` without the ones kept on the iPad.
    private func onServer(_ letters: [MessageSummary]) -> [MessageSummary] {
        letters.filter { LocalDraft.key(ofRow: $0.id) == nil }
    }

    // MARK: - Mail's drags on a row (B-156)

    /// A drag to the left: More, Flag and Trash, the Trash at the edge and
    /// what a full drag does (`RowSwipes`).
    override func tableView(_ t: UITableView,
                            trailingSwipeActionsConfigurationForRowAt ip: IndexPath)
        -> UISwipeActionsConfiguration? {
        swipes(at: ip, \.left)
    }

    /// A drag to the right: Mark as Read or Mark as Unread, as the row is.
    override func tableView(_ t: UITableView,
                            leadingSwipeActionsConfigurationForRowAt ip: IndexPath)
        -> UISwipeActionsConfiguration? {
        swipes(at: ip, \.right)
    }

    /// The buttons a drag on the row at `ip` shows on one side, as
    /// `RowSwipes` has them for it now; none in Edit mode, in the Outbox,
    /// or on a letter on this iPad only. An empty configuration, never
    /// nil: nil is UIKit's default, which goes by the row's editing style.
    ///
    /// Each button `.normal`, in Mail's colour, not `.destructive`: a
    /// destructive one completed has the table take the row out itself,
    /// and the rows here are drawn again from the letters (`regroup`),
    /// which take the row off at the tap as Edit mode's Delete does.
    private func swipes(at ip: IndexPath,
                        _ side: KeyPath<RowSwipes.Sides, [RowSwipes.Action]>)
        -> UISwipeActionsConfiguration {
        guard threads.indices.contains(ip.row) else { return UISwipeActionsConfiguration(actions: []) }
        let thread = threads[ip.row]
        let sides = RowSwipes.sides(for: swipeRow(thread), editing: tableView.isEditing)
        let actions = sides[keyPath: side].map { action -> UIContextualAction in
            let button = UIContextualAction(style: .normal, title: action.title) {
                [weak self] _, _, done in
                done(self?.swiped(action, on: RowKey(thread)) ?? false)
            }
            // At a fixed size, as every symbol here is (B-071).
            button.image = Theme.symbol(action.symbol)
            button.backgroundColor = Self.colour(of: action)
            return button
        }
        let configuration = UISwipeActionsConfiguration(actions: actions)
        configuration.performsFirstActionWithFullSwipe = true
        return configuration
    }

    /// Mail's colours: the Trash red, the flag orange, the read mark blue,
    /// More grey.
    private static func colour(of action: RowSwipes.Action) -> UIColor {
        switch action {
        case .trash, .delete: return Theme.destructive
        case .flag, .unflag: return Theme.flagTint
        case .markRead, .markUnread: return Theme.tintBlue
        case .archive, .move: return Theme.swipeArchive
        case .more: return Theme.swipeMore
        }
    }

    /// The row as `RowSwipes` reads it.
    private func swipeRow(_ thread: MessageThread) -> RowSwipes.Row {
        RowSwipes.Row(read: thread.isRead, flagged: thread.isFlagged,
                      role: role(of: thread.newest.mailboxID),
                      onThisIPadOnly: isOutbox
                          || thread.messages.contains { LocalDraft.key(ofRow: $0.id) != nil },
                      canArchive: archive(for: thread) != nil)
    }

    /// Gmail's All Mail, for an Archive, unless the row is listed from it.
    private func archive(for thread: MessageThread) -> Mailbox? {
        guard role(of: thread.newest.mailboxID) != .archive else { return nil }
        return ([mailbox] + folders()).first { $0.role == .archive }
    }

    /// A row, by its conversation's id and the folder its letters are
    /// listed from: an All Mailboxes search can list letters of two
    /// folders under the same "<uidvalidity>/<uid>".
    private struct RowKey: Equatable {
        let id: String
        let folder: String

        init(_ thread: MessageThread) {
            id = thread.id
            folder = thread.newest.mailboxID
        }
    }

    /// The row `key`'s letters as the list has them now, in the order Edit
    /// mode sends them, the oldest first (`ListBatch.letters`): what a drag
    /// or More acts on, every letter of the row, as a tick in Edit mode
    /// takes the row whole. Nil when the row has gone since the drag began.
    private func lettersOfRow(_ key: RowKey) -> (thread: MessageThread, letters: [MessageSummary])? {
        guard let row = threads.firstIndex(where: { RowKey($0) == key }) else { return nil }
        return (threads[row], onServer(ListBatch.letters(ticked: [row], in: threads)))
    }

    /// A button of a drag on the row `key`, tapped, or a
    /// full drag. Returns whether it went ahead, for UIKit to close the row
    /// or let it slide back.
    ///
    /// The Trash at once, with no question, as Mail's full drag; the rows
    /// go at the tap, the reading pane empties if it shows one of the
    /// letters, and a letter Gmail did not take comes back where it stood
    /// with the alert, as Edit mode's Delete (`runBatch`, B-041, B-092).
    /// Inside Trash, Delete erases, and asks first as Edit mode's does; the
    /// row slides back while he is asked, and goes if he says Delete.
    /// Flag and the read mark change the row at the tap and go back if
    /// refused (`ListBatch`, `PaneActions`); not while one is on its way
    /// on any of the row's letters, as the pane waits for its own.
    private func swiped(_ action: RowSwipes.Action, on key: RowKey) -> Bool {
        guard !tableView.isEditing, let row = lettersOfRow(key), !row.letters.isEmpty else {
            return false
        }
        let chosen = row.letters
        switch action {
        case .trash:
            runBatch(.delete, on: chosen, saying: StatusLine.deleting)
            return true
        case .delete:
            guard let question = EraseQuestion.before(deleting: chosen,
                                                      role: { self.role(of: $0) }) else {
                runBatch(.delete, on: chosen, saying: StatusLine.deleting)
                return true
            }
            EraseConfirmation.ask(question, on: self) { [weak self] in
                self?.runBatch(.delete, on: chosen, saying: StatusLine.deleting)
            }
            return false
        case .archive:
            guard let all = archive(for: row.thread) else { return false }
            runBatch(.move(to: all), on: chosen, saying: StatusLine.moving)
            return true
        case .move:
            moveRow(key)
            return true
        case .flag, .unflag:
            return mark(.flag(action == .flag), on: key)
        case .markRead, .markUnread:
            return mark(.read(action == .markRead), on: key)
        case .more:
            showMore(for: key)
            return true
        }
    }

    /// A Flag or a read mark on every letter of the row that it changes, as
    /// Edit mode's Mark takes a ticked row: Flag flags them all, as Mail is
    /// said to flag every letter of a conversation, Unflag takes it off
    /// every one; Mark as Read every unread one, Mark as Unread every read
    /// one. The row changes at the tap, the server is told a letter at a
    /// time, and a refusal puts back what it did not take and says why.
    private func mark(_ action: PaneAction, on key: RowKey) -> Bool {
        guard let row = lettersOfRow(key) else { return false }
        let changing = row.letters.filter { letter in
            switch action {
            case .flag(let flagged): return letter.isFlagged != flagged
            case .read(let read): return letter.isRead != read
            case .delete, .move: return false
            }
        }
        guard !changing.isEmpty,
              !changing.contains(where: { letters.flagOnItsWay($0.id)
                                          || letters.dot(on: $0)?.onItsWay == true })
        else { return false }
        Task { @MainActor [weak window = view.window] in
            let outcome = await ListBatch.run(
                action, on: changing, role: { self.role(of: $0) },
                list: self.letters, repository: self.repository,
                requestSweep: { [weak self] in self?.requestSweep?() })
            if let refusal = outcome.refusal {
                ErrorPresenter.show(reaching: refusal, on: self.alertHost(in: window))
            }
        }
        return true
    }

    /// Move Message, from a drag or More: the folder sheet, as Edit mode's
    /// Move, for every letter of the row.
    private func moveRow(_ key: RowKey) {
        guard let row = lettersOfRow(key) else { return }
        let move = MoveMessageViewController(repository: repository,
                                             excluding: row.thread.newest.mailboxID) {
            [weak self] destination in
            guard let self, let row = self.lettersOfRow(key), !row.letters.isEmpty else { return }
            self.runBatch(.move(to: destination), on: row.letters, saying: StatusLine.moving)
        }
        let nav = UINavigationController(rootViewController: move)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    /// Where the row `key` is, for a popover over it: its right part, where
    /// More was.
    private func placeOfRow(_ key: RowKey) -> (view: UIView, rect: CGRect)? {
        guard let row = threads.firstIndex(where: { RowKey($0) == key }) else { return nil }
        let rect = tableView.rectForRow(at: IndexPath(row: row, section: 0))
        let width = min(rect.width, Theme.minHitTarget * 2)
        return (tableView, CGRect(x: rect.maxX - width, y: rect.minY, width: width,
                                  height: rect.height))
    }

    /// More's sheet (`RowMore`), over the row, as Mail's: Reply, Reply All
    /// and Forward of the conversation's newest letter, made by the reading
    /// pane (`onAnswer`); Flag or Unflag, Mark as Unread or Mark as Read,
    /// and Move Message, on every letter of the row. Each item acts on the
    /// row as it is when tapped.
    private func showMore(for key: RowKey) {
        guard let row = lettersOfRow(key), let place = placeOfRow(key) else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.popoverPresentationController?.sourceView = place.view
        sheet.popoverPresentationController?.sourceRect = place.rect
        for item in RowMore.items(read: row.thread.isRead, flagged: row.thread.isFlagged) {
            sheet.addAction(UIAlertAction(title: item.title, style: .default) { [weak self] _ in
                self?.chose(item, on: key)
            })
        }
        sheet.addAction(UIAlertAction(title: RowMore.cancel, style: .cancel))
        present(sheet, animated: true)
    }

    private func chose(_ item: RowMore.Item, on key: RowKey) {
        guard !tableView.isEditing, let row = lettersOfRow(key) else { return }
        switch item {
        case .reply, .replyAll, .forward:
            guard let place = placeOfRow(key) else { return }
            onAnswer?(row.thread.newest, item == .replyAll, item == .forward, place)
        case .flag: _ = mark(.flag(true), on: key)
        case .unflag: _ = mark(.flag(false), on: key)
        case .markAsRead: _ = mark(.read(true), on: key)
        case .markAsUnread: _ = mark(.read(false), on: key)
        case .moveMessage: moveRow(key)
        }
    }

    /// Reopens a saved draft in the composer.
    ///
    /// The draft has to be downloaded first. Its row stays highlighted,
    /// with a spinner, until the composer opens, and a second tap on it
    /// meanwhile does nothing; see `DraftOpening`. The highlight used to go
    /// at the tap, with nothing on screen until the sheet came up.
    ///
    /// A letter kept on the iPad opens at once, with nothing to download,
    /// even while it is on its way to the server: it stays on the iPad
    /// until the composer is done with it (`LocalDrafts.upload`). One that
    /// has gone to the server since its row was drawn opens as the copy it
    /// became there.
    @MainActor
    private func openDraft(_ summary: MessageSummary) {
        var id = summary.id
        if let key = LocalDraft.key(ofRow: summary.id) {
            if let letter = kept.letter(key) {
                if let row = rowIndex(showing: summary.id) {
                    tableView.deselectRow(at: IndexPath(row: row, section: 0), animated: false)
                }
                presentComposer(letter.draft, key: key, from: summary)
                return
            }
            guard let landed = kept.landed[key] else { return }
            id = landed
        }
        guard drafts.tap(summary.id) else { return }
        showDraftSpinners()
        Task { @MainActor [weak self] in
            guard let self else { return }
            var draft: Draft?
            var failure: Error = MailError.cannotConnect
            var notKept = false
            do {
                // Named by the row's Gmail message id. A letter kept on the
                // iPad that has gone up since its row was drawn has none,
                // and its copy is one this launch put in Drafts.
                draft = try await self.repository.loadDraft(id: id,
                                                            gmailMessageID: summary.gmailMessageID,
                                                            mailboxID: summary.mailboxID)
            } catch {
                failure = error
                notKept = error is MailShelf.NotTheKeptLetter
            }
            // Another draft tapped since is the one he wants now.
            guard self.drafts.landed(summary.id) else { return }
            self.showDraftSpinners()
            if let row = self.rowIndex(showing: summary.id) {
                self.tableView.deselectRow(at: IndexPath(row: row, section: 0), animated: false)
            }
            // A row kept on the iPad that the server says is another letter
            // (D-016): nothing of it is opened, and the row comes off, as a
            // letter opened in the reading pane does.
            if notKept {
                PaneActions.notTheKeptLetter(summary, list: self.letters)
                return
            }
            guard let draft else {
                ErrorPresenter.show(reaching: failure, on: self)
                return
            }
            self.presentComposer(draft, key: nil, from: summary)
        }
    }

    /// A letter in the Outbox, opened in the composer to be changed or sent
    /// again. Out of the Outbox while the composer has it: Send puts it
    /// back if it cannot go, closed untouched it is back as it was, and
    /// saved it is a draft. Not while it is on its way, its row saying
    /// "Sending…": gone while the composer had it, a Send there would send
    /// it a second time.
    @MainActor
    private func openWaiting(_ summary: MessageSummary) {
        if let row = rowIndex(showing: summary.id) {
            tableView.deselectRow(at: IndexPath(row: row, section: 0), animated: false)
        }
        guard let key = LocalDraft.key(ofRow: summary.id), !kept.isGoing(key),
              let letter = kept.letter(key) else { return }
        presentComposer(letter.draft, key: key, from: summary)
    }

    /// The composer on a draft from this folder, `summary` the row tapped.
    @MainActor
    private func presentComposer(_ draft: Draft, key: String?, from summary: MessageSummary) {
        let compose = ComposeViewController(repository: repository, draft: draft, key: key)
        // Sent, the draft's row goes as the sheet closes, before its
        // copy has been removed from the server: a tap on it meanwhile
        // reopened the letter just sent, to be sent again. Taken off as
        // a removal on its way, like a Delete from the reading pane. The
        // copy is found by its id: for a letter reopened from the iPad it
        // is not the row he tapped, which has gone with the letter kept.
        var taken = summary
        compose.onDraftSent = { [weak self] id in
            guard let self else { return }
            taken = self.letters.letter(id) ?? summary
            self.letters.take(taken, fromEveryFolder: false)
        }
        // Sending or deleting changes what is in this very folder, so the
        // list behind has to be rebuilt. A sent draft's row stays off only
        // until then: the folder fetched afresh has the say, without it if
        // the cleanup removed it, with it if not. A saved one is shown by
        // `keptChanged`, as it is kept and again once the server has it.
        compose.onDraftsChanged = { [weak self] in
            Task { @MainActor in
                self?.letters.removalLanded(taken, fromEveryFolder: false)
                await self?.reload(keepingPlace: true)
            }
        }
        let nav = UINavigationController(rootViewController: compose)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    /// The spinner on the row of the draft being downloaded, and on no
    /// other, in the rows in sight. Cells coming into sight later ask
    /// `drafts` for themselves (`willDisplay`), the one the table made
    /// ahead of time for the row past the edge too (B-143).
    @MainActor
    private func showDraftSpinners() {
        drawRowsInSight(.draftSpinners)
    }

    @objc private func composeTapped() {
        let signature = CredentialStore.loadAccount()?.signature ?? ""
        let compose = ComposeViewController(repository: repository,
                                            draft: .blank(signature: signature))
        let nav = UINavigationController(rootViewController: compose)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    // MARK: - Search

    /// How long to sit on a keystroke before asking the server.
    ///
    /// Search is live as he types, which is Mail's behaviour and worth
    /// keeping. What is not worth keeping is what that used to cost: one
    /// full IMAP round trip PER KEYSTROKE, so typing a six-letter name
    /// fired six searches over a domestic connection and the answer he saw
    /// was whichever came back last, not necessarily the one for what was
    /// in the field. A third of a second is longer than the gap between two
    /// keystrokes and shorter than a pause for thought.
    private static let searchDelay = Duration.milliseconds(350)

    private func queryChanged(_ text: String) {
        // A search: what it puts back when it ends is where he was (B-117).
        landed.letGo()
        searchQuery = text
        searchDebounce?.cancel()
        // No pull while words are typed (B-103).
        placePull()

        // Clearing the field is not a search and must not wait: he is
        // asking for his mail back.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showUnfilteredList()
            return
        }

        searchDebounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.searchDelay)
            guard !Task.isCancelled else { return }
            await self?.runSearch(text)
        }
    }

    /// Calls off a search still running, whose results nothing would draw:
    /// the list has moved on, to a refresh or a date here, or to another
    /// folder that replaces it. A search takes the connection for a
    /// mailbox at a time (see `IMAPClient.search(_:across:)`), so one left
    /// running holds up whatever is next in line until it is done; cancelled,
    /// it stops after the command it has on the wire.
    @MainActor
    func stopSearching() {
        searchDebounce?.cancel()
    }

    /// Leaves search behind and puts the folder back, without a round trip:
    /// where he was in it, and with the previews its own pass had not
    /// fetched when the search replaced it (`ListLetters.endSearch`), which
    /// used to stay blank until the next Refresh.
    @MainActor
    private func showUnfilteredList() {
        searchDebounce?.cancel()
        listGeneration += 1
        let showingResults = letters.isSearching
        let unpreviewed = letters.endSearch()
        // The folder's own end state comes back with it. Search may have
        // set `reachedOldestMessage` from a short page of HITS, which says
        // nothing about how much mail is left in the folder. Still the kept
        // page, nothing below it (D-016).
        reachedOldestMessage = letters.fromShelf || letters.folder.count < Self.pageSize
        regroup(to: places.searchEnded(showingResults: showingResults))
        updateEmptyState()
        updatePageFooter()
        loadPreviews(for: unpreviewed)
        // Back in the folder, where he was: letters the watch found while
        // the search showed go on if that was the top.
        showNewsIfAtTop()
        placePull()
    }

    @objc private func cancelSearch() {
        searchQuery = ""
        showUnfilteredList()
    }

    /// A recent search tapped (B-105): searched at once, in the scope the
    /// band shows, with no wait for more typing, as nothing more is coming;
    /// and it is the newest of his recent searches again. Through
    /// `searchDebounce`, so a keystroke or Cancel after it calls it off as
    /// it would a typed search.
    private func recentChosen(_ text: String) {
        searchQuery = text
        searchDebounce?.cancel()
        keepSearch(text)
        searchDebounce = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            await self?.runSearch(text)
        }
    }

    /// Keeps `text` as his newest recent search (B-105), at Search on the
    /// keyboard, a recent search tapped, and a letter opened from the
    /// results. Text that asks for nothing, blank or quote marks alone, is
    /// not kept (`RecentSearches.keeps`).
    private func keepSearch(_ text: String) {
        RecentSearches.note(text, at: Date(), in: RecentSearches.appFile)
    }

    @MainActor
    private func runSearch(_ text: String) async {
        listGeneration += 1
        let generation = listGeneration
        let scope = searchScope
        // A search, typed or a recent one tapped, lets the day landed on go:
        // the folder comes back where he was when it ends (B-117).
        landed.letGo()

        let outcome: Result<[MessageSummary], Error>
        do {
            outcome = .success(try await repository.search(
                in: mailbox.id, query: text, scope: scope, beforeUID: nil, limit: Self.pageSize))
        } catch {
            outcome = .failure(error)
        }

        // A search the next keystroke cancelled has not failed and has not
        // found anything: it has been replaced, and it has no business
        // changing the screen, whichever way it ended. See `SearchAnswer`.
        let hits: [MessageSummary]
        switch SearchAnswer.settle(outcome, cancelled: Task.isCancelled,
                                   current: generation == listGeneration) {
        case .ignore:
            return
        case .failed:
            // This used to be `try?`, which turned every failure into an
            // empty array and rendered it as "No results" — so a dropped
            // connection told him the letter did not exist. It does exist;
            // we could not look.
            let move = showingResults()
            letters.showResults([])
            searchFailed = true
            regroup(to: move)
            updateEmptyState()
            updatePageFooter()
            placePull()
            return
        case .draw(let found):
            hits = found
        }

        searchFailed = false
        searchShown = text
        let move = showingResults()
        // With the previews already drawn for the same letters (B-135).
        let unpreviewed = letters.showResults(hits)
        reachedOldestMessage = hits.count < Self.pageSize
        regroup(to: move)
        updateEmptyState()
        updatePageFooter()
        // Results showing: no pull (B-103).
        placePull()
        loadPreviews(for: unpreviewed)
    }

    /// Whether the last search could not be run, as opposed to finding
    /// nothing. Two different sentences.
    private var searchFailed = false

    /// A search's answer is about to replace the rows: where the list goes,
    /// the top, and where he was in the folder's letters if it is those it
    /// replaces. Asked before the letters change, while the rows on screen
    /// are still the ones he was reading. See `ListPlaces`.
    @MainActor
    private func showingResults() -> ListPlaces.Move {
        let overFolder = !letters.isSearching
        return places.resultsShown(overFolder: overFolder, here: overFolder ? place() : nil)
    }

    // MARK: - Table

    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { rows.count }

    /// The search band, pinned. See `viewDidLoad`.
    override func tableView(_ t: UITableView, viewForHeaderInSection s: Int) -> UIView? {
        isOutbox ? nil : searchBar
    }

    override func tableView(_ t: UITableView, heightForHeaderInSection s: Int) -> CGFloat {
        // From the band's own idea of how tall it wants to be, NOT from its
        // frame: the table resets a section header's frame during layout,
        // so reading the frame back here returns the previous height and
        // the scope bar gets drawn over the first message instead of
        // pushing it down. None in the Outbox, whose letters are not on the
        // server to be searched.
        isOutbox ? 0 : searchBar.wantedHeight
    }

    /// Draws the row whole as it comes into sight (B-143), and starts the
    /// next page while there is still a screenful to read.
    ///
    /// Ten rows of lead time rather than waiting for the last one, so the
    /// fetch is usually finished before he scrolls far enough to notice it
    /// happened. Loading only once he hits the bottom would stop the list
    /// dead every fifty messages.
    override func tableView(_ t: UITableView, willDisplay cell: UITableViewCell,
                            forRowAt ip: IndexPath) {
        // The row drawn whole from what it is now as it comes into sight
        // (B-143): its preview, its spinner, its date and VoiceOver's words.
        // The table may have prepared this cell ahead, for the row past the
        // edge, before a preview landed, a draft was tapped, or 24-Hour
        // Time, the zone or the day changed (B-139), and shows it now
        // without asking for it again; those patches name the rows in sight
        // alone (`drawRowsInSight`). A cell made just now is drawn again as
        // it was: the same words, nothing moved or fetched.
        if let cell = cell as? MessageCell { draw(cell, at: ip, .comingIntoSight) }

        // Upward first. After a date jump the list runs in both directions,
        // and the top of it is no longer the top of the folder.
        //
        // The threshold is the same share of the page the jump reserved
        // above the anchor, so landing on a date does not immediately
        // trigger the load of the page above it — he is inside the buffer,
        // not at the edge of it. It does all the same, as the day lands
        // (B-094); and a jump's window has the page above it in it now,
        // fifty rows more of buffer (`PageWindow.jumpWindow`, B-117).
        if ip.row < max(1, Self.pageSize / 5) { loadPreviousPage() }
        guard ip.row >= rows.count - 10 else { return }
        loadNextPage()
    }

    @objc private func settingsTapped() {
        showSettings()
    }

    /// Settings, over the list; with `focusingPassword`, the keyboard up in
    /// the password field, as the Settings button of a refused password's
    /// alert opens it (`ErrorPresenter.openSettings`). Not while anything
    /// else is over the list: a sheet can only be put over the screens.
    func showSettings(focusingPassword: Bool = false) {
        guard presentedViewController == nil,
              let account = CredentialStore.loadAccount() else { return }
        let settings = SettingsViewController(account: account, focusingPassword: focusingPassword)
        settings.onSaved = { [weak self] saved in
            // Nothing on this screen changes what is IN the mailbox, so the
            // list is not reloaded. The signature is read fresh every time a
            // compose window opens, so the next letter already has it, and
            // the repository reads the name and the signature as each letter
            // is made, so the next one goes as saved (B-082). Nothing is
            // built again for it. His addresses are what the rows leave out
            // (B-075, B-076): the list takes them as saved and draws its rows
            // again, in place.
            //
            // Nothing is asked of the server either (B-085). No count
            // changes with what is saved here. The counts used to be swept
            // all the same, from when a new password was saved this way
            // too; it goes by `onPasswordSaved` now, which builds the
            // screens again over a repository that signs in with it. With
            // no connection that sweep put "Can't connect to mail server."
            // over a save that had worked.
            guard let self else { return }
            self.mine = OwnAddresses(account: saved)
            self.regroup()
        }
        settings.onPasswordSaved = { [weak self] account, password, notice in
            self?.onPasswordSaved?(account, password, notice)
        }
        // The grouping switch acts immediately, so the list behind the
        // sheet has to hear about it the moment it flips.
        settings.onOrganizeByThreadChanged = { [weak self] in self?.regroup() }
        let nav = UINavigationController(rootViewController: settings)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    @objc private func loadMoreTapped() {
        loadFailed = false
        loadNextPage()
    }

    override func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = t.dequeueReusableCell(withIdentifier: MessageCell.reuseID, for: ip) as! MessageCell
        // A letter inside an opened conversation sits on a slightly
        // different ground, so the group reads as a block rather than as
        // more top-level rows. The cell lays itself out by measured frames
        // against the reference, so indenting it would mean touching a
        // frozen layout; a background is the cue that costs nothing.
        cell.backgroundColor = Theme.canvas
        cell.indent = 0
        cell.separatorInset = UIEdgeInsets(top: 0, left: Theme.messageSeparatorInset,
                                           bottom: 0, right: 0)
        draw(cell, at: ip, .made)
        return cell
    }


    override func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        // A row he has opened or ticked: where VoiceOver goes next is his,
        // and a row held for it is let go (B-079).
        letGoOfVoiceOver()
        // In Edit mode a tap ticks a row rather than opening it, and the
        // Select All button has to keep up with what that leaves selected.
        guard !t.isEditing else { updateSelectAllTitle(); return }
        // A letter opened from the results: the search found what he was
        // after, and is kept among his recent ones (B-105).
        if letters.isSearching { keepSearch(searchShown) }
        // A tap on another row than the one a jump landed on: that row is
        // let go, and the one he tapped stays where it is (B-117). In Edit
        // mode none is held (`editTapped`).
        landed.tapped(threads[ip.row])
        switch rows[ip.row] {
        case let .thread(thread) where thread.count > 1:
            // The conversation opens in the READING PANE, as a stack of its
            // letters, which is what Mail does. It used to open OUT in the
            // list instead — B-022 — on the reasoning that the pane should
            // always hold exactly one letter. The requirement is that
            // the app work the way the one he knows works, and his
            // hands know Mail.
            open(thread, at: ip)
        case let .thread(thread):
            open(thread.newest, at: ip)
        }
    }

    override func tableView(_ t: UITableView, didDeselectRowAt ip: IndexPath) {
        guard t.isEditing else { return }
        updateSelectAllTitle()
        // The last tick taken off.
        landFreshPage()
        showNewsIfAtTop()
    }

    /// Opens a whole conversation in the reading pane.
    ///
    /// Only the letters the pane shows open are marked read: the newest,
    /// and the unread ones it opens with it, as Mail shows them in full
    /// (B-074). The pane opens at the oldest of those, so each starts at
    /// or below the top of the pane, none of them above it, out of sight
    /// (`ConversationDocument.opensAt`). The letters closed to their lines
    /// are ones he has read. Marking the lot read on one tap would empty
    /// his unread count for letters he has not seen, and the count is how
    /// he knows what is still waiting.
    ///
    /// All of them here, at once: one redraw of the rows, and a STORE each
    /// (`ConversationDocument.readAtTheTap`). The pane used to mark the
    /// unread ones one at a time, through `markRead`, and each was a
    /// redraw of the list inside the tap.
    @MainActor
    private func open(_ thread: MessageThread, at ip: IndexPath) {
        // Drafts never group into a stack: a tap there has to reopen the
        // composer, and there is no reading-pane form of that.
        if mailbox.role == .drafts {
            openDraft(thread.newest)
            return
        }
        if isOutbox {
            openWaiting(thread.newest)
            return
        }

        // His own letters of it from Sent Mail, in an Inbox conversation
        // listed grouped, with the switch on (B-104). Never in the list:
        // only the pane's stack has them.
        onSelectThread?(thread, CompleteThreads.thread(
            toComplete: thread, listedIn: mailbox.role, searching: letters.isSearching,
            switchedOn: ConversationSettings.completeThreads))
        markReadIfNeeded(ConversationDocument.readAtTheTap(thread))
    }

    /// Opens one letter in the reading pane and marks it read.
    @MainActor
    private func open(_ summary: MessageSummary, at ip: IndexPath) {
        let m = summary

        // In Drafts a tap REOPENS the letter for writing. Everywhere else it
        // opens it for reading. Mail behaves the same way, and the previous
        // behaviour here made a saved draft a dead end: it opened read-only
        // in the pane to the right, with no route back into the composer, so
        // a letter he had been interrupted writing could never be finished.
        if mailbox.role == .drafts {
            openDraft(m)
            return
        }
        if isOutbox {
            openWaiting(m)
            return
        }

        onSelectMessage?(m)
        markReadIfNeeded(m)
    }

    /// Marks one letter read locally, tells the server, and bills the
    /// folder counters — or puts everything back if the server refuses.
    ///
    /// Lifted out of `open` so the conversation path can use it for the
    /// letters it actually shows open. Doing it twice in two places is how
    /// the counter arithmetic drifts.
    ///
    /// At the tap, and a letter tapped and left at once counts as read. The
    /// reading pane calls off the body of a letter he taps past
    /// (`PaneLoads`), but not this: it is the letter's own task, and nothing
    /// cancels it. Mail marks a letter read when it is selected, however
    /// briefly, and his hands know Mail. The dot has gone at the tap, and
    /// putting it back as he moves on would change a row he has just left.
    /// The pane showed its sender, subject and date from the tap. And the
    /// STORE is one short exchange, where the body is the download worth
    /// calling off. What it costs: a letter he stops on after tapping past
    /// three unread ones waits for their three STOREs, which went into the
    /// line before its body did.
    @MainActor
    private func markReadIfNeeded(_ summary: MessageSummary) {
        markReadIfNeeded([summary])
    }

    /// Several letters marked read at one tap: a conversation's newest and
    /// the unread letters its stack opens with it (B-074). Each as one is
    /// marked, but the rows redrawn once for the lot, highlighting the
    /// first one's. The STOREs go in the line one after another, and
    /// nothing calls them off, as for rows he taps past.
    @MainActor
    private func markReadIfNeeded(_ summaries: [MessageSummary]) {
        let marked = summaries.filter { !$0.isRead }
        guard let first = marked.first else { return }
        // Held over a listing already on its way, whose flags are from
        // before this STORE: at launch, the first page, when the tap is on a
        // row kept on the iPad (D-016). See `ListLetters.reading`.
        for m in marked { letters.reading(m, read: true) }
        // Regroup rather than reload the one row: the thread this letter
        // belongs to may have just lost its unread dot. Its row is
        // highlighted as the one open in the pane, except in Edit mode; see
        // `ListEdit.selectedRows`.
        regroup(highlighting: first.id)
        for m in marked { sendRead(m) }
    }

    /// The STORE of one read mark made here, and what its answer does to
    /// the dot and the folder counts.
    @MainActor
    private func sendRead(_ summary: MessageSummary) {
        var m = summary
        m.isRead = true
        Task { @MainActor in
            do {
                try await repository.setRead(true, id: m.id, gmailMessageID: m.gmailMessageID,
                                             mailboxID: m.mailboxID)
            } catch is MailShelf.NotTheKeptLetter {
                // A row kept on the iPad that the server says is another
                // letter now: nothing was sent, and it comes off the list if
                // it is still that row, and the pane that was showing it
                // empties (D-016).
                self.letters.readAnswered(m.id, landed: false)
                PaneActions.notTheKeptLetter(m, list: self.letters)
                self.onMessagesChanged?()
                return
            } catch {
                // Put the dot back. Before the sidebar counter existed a
                // failed STORE merely left the folder count stale HIGH,
                // which nags; decrementing anyway would leave it stale LOW,
                // and a count that is too low tells him there is no new mail
                // when there is. That is the failure this pane exists to
                // prevent, so the decrement is only ever committed after the
                // server has actually taken the flag.
                self.letters.readAnswered(m.id, landed: false)
                self.regroup()
                return
            }
            self.letters.readAnswered(m.id, landed: true)
            // Once per message, ever. A reload can re-derive `isRead` from
            // server FLAGS that predate this STORE and put the unread dot
            // back, which re-arms the `!$0.isRead` in `markReadIfNeeded` —
            // so that alone would let one message be billed twice.
            self.letters.read(m)
        }
    }

    /// A letter read in the reading pane without a tap on its row: one he
    /// opened inside a conversation. It goes the way a tap on its row goes,
    /// so the dot, the STORE and the folder counts are dealt with here and
    /// once. Asked with the pane's copy, which may be older than this
    /// list's: the conversation was handed its rows before the tap that
    /// opened it marked the newest read.
    ///
    /// The pane can do this while the list is in Edit mode, which leaves
    /// the pane as it was: a row tap never could, since in Edit mode a tap
    /// ticks. So it must leave his ticks as they are.
    ///
    /// The list's copy only while it is the letter he opened, by its Gmail
    /// message id. A conversation drawn from rows kept on the iPad (D-016)
    /// can outlast the list's swap to the fresh page, which may have put
    /// another letter under the same id: marked from the list's copy, the
    /// STORE named that letter and went onto it. Now the read mark names
    /// the letter he opened, and the repository refuses it or sends it by
    /// that id; the list's row is another letter's, and is left as it is,
    /// dot and counts, as the letter's own FETCH decides what the pane shows.
    @MainActor
    func markRead(_ letter: MessageSummary) {
        let listed = letters.letter(letter.id)
        guard let another = listed, !ListEdit.sameLetter(another, letter) else {
            markReadIfNeeded(listed ?? letter)
            return
        }
        guard !letter.isRead else { return }
        let repository = self.repository
        Task {
            try? await repository.setRead(true, id: letter.id, gmailMessageID: letter.gmailMessageID,
                                          mailboxID: letter.mailboxID)
        }
    }

    /// The pane was emptied at the tap of a Delete or a Move, and a
    /// highlighted row beside an empty pane says he is reading a letter he
    /// is not. The row may stay: a conversation that has lost one letter,
    /// or a letter moved out of All Mail, which is still in All Mail. Not
    /// in Edit mode, where a selected row is a tick of his and not the
    /// letter in the pane.
    @MainActor
    private func letGo(_ letter: MessageSummary) {
        guard !tableView.isEditing, let row = rowIndex(showing: letter.id) else { return }
        tableView.deselectRow(at: IndexPath(row: row, section: 0), animated: false)
    }
}

#endif
