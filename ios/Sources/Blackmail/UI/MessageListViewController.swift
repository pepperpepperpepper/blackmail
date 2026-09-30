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
    /// shows the whole stack; see B-022.
    var onSelectThread: ((MessageThread) -> Void)?
    var onMessagesChanged: (() -> Void)?
    var onRefreshRequested: (() -> Void)?
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

    /// The letters kept on the iPad (B-051): listed at the top of Drafts,
    /// and taken to the server whenever a page here has come.
    private let kept = LocalDrafts.shared

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
    /// highlighted with it.
    ///
    /// Reload keeps the scroll offset and nothing else, and the rows under
    /// that offset can have moved: a page above, a row taken off by a
    /// Delete, the grouping switch. So the rows he can see are held by the
    /// letters in them and put back where they were on screen, and the
    /// selection by its letters too. Both are taken before the rows are
    /// rebuilt, since row numbers mean nothing after; see `ListPlace`.
    @MainActor
    private func regroup(highlighting opened: String? = nil, to move: ListPlaces.Move = .stay) {
        let before = place()
        rebuildRows()
        tableView.reloadData()
        let threads = self.threads
        for row in before.selection(in: threads, opened: opened, editing: tableView.isEditing) {
            tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false,
                                scrollPosition: .none)
        }
        switch move {
        case .top:
            scrollToTop()
        case .back(let folder):
            if !scroll(to: folder, in: threads) { scrollToTop() }
        case .stay:
            scroll(to: before, in: threads)
        }
    }

    /// Where he is now: the rows on screen and how far down the pane each
    /// sits, and the selected rows. See `ListPlace`.
    @MainActor
    private func place() -> ListPlace {
        let top = Double(tableView.contentOffset.y)
        let visible = (tableView.indexPathsForVisibleRows ?? [])
            .filter { $0.section == 0 && $0.row < rows.count }
            .sorted()
            .map { ($0.row, Double(tableView.rectForRow(at: $0).minY) - top) }
        let selected = (tableView.indexPathsForSelectedRows ?? []).map(\.row)
        return ListPlace(rows: threads, visible: visible, selected: selected)
    }

    /// Puts `place` back on screen, if any of it is in `threads`. Leaves the
    /// offset alone when it is already there, so a regroup that moved
    /// nothing, as a page appended below does, never touches a list he is
    /// flicking through.
    @MainActor
    @discardableResult
    private func scroll(to place: ListPlace, in threads: [MessageThread]) -> Bool {
        guard let landing = place.landing(in: threads) else { return false }
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
    @MainActor
    private func scrollToTop() {
        tableView.layoutIfNeeded()
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top),
                                   animated: false)
    }

    init(repository: MailRepository, mailbox: Mailbox) {
        self.repository = repository
        self.mailbox = mailbox
        super.init(style: .plain)
        title = mailbox.displayName
        letters.changed = { [weak self] in
            self?.regroup()
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
        // Nor was it ever doing what its old comment claimed. Swipe-to-delete
        // is banned by `PRODUCT_SPEC.md` and is genuinely absent, but that is because
        // neither `commit editingStyle:` nor
        // `trailingSwipeActionsConfigurationForRowAt` exists — not because of
        // this property, which has nothing to do with swiping.
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
        // The band grows when the scope buttons appear, and the table has to
        // be told to re-ask how tall its header is. `begin`/`endUpdates`
        // with no changes between them does exactly that and nothing else.
        searchBar.onHeightChanged = { [weak self] in
            guard let self, self.isViewLoaded else { return }
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
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
        let jump = UIBarButtonItem(image: UIImage(systemName: "calendar"),
                                   style: .plain, target: self,
                                   action: #selector(jumpToDateTapped))
        jump.accessibilityLabel = "Go to a date"
        jumpItem = jump
        placeLeadingItems()

        // The bottom bar from the reference. It looks decorative and is not:
        // "Updated Just Now" is the only thing on screen that answers "is this
        // actually my mail, or is it stale?" - a question that otherwise ends
        // in a phone call.
        statusLabel.font = Theme.fontToolbarStatus
        statusLabel.textColor = Theme.secondaryText
        statusLabel.textAlignment = .center
        // Two lines when the last try failed, as Mail's bar has them: how old
        // the list is over what went wrong (`UpdatedLine`).
        statusLabel.numberOfLines = 2
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

        if mailbox.role == .drafts {
            NotificationCenter.default.addObserver(self, selector: #selector(keptChanged(_:)),
                                                   name: LocalDrafts.changed, object: kept)
        }

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
                newest: { came = await self.reload() })
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
    /// at launch, at a Refresh, on opening a folder, on coming back.
    @MainActor
    @discardableResult
    func reload(keepingPlace: Bool = false, quietly: Bool = false) async -> Bool {
        listGeneration += 1
        let generation = listGeneration
        stopSearching()
        isLoadingPage = false
        isLoadingPrevious = false
        reachedOldestMessage = false
        // Back to the top, so there is nothing above us again. A reload
        // after a date jump must clear this or the list would keep trying
        // to load mail newer than the newest message there is.
        reachedNewestMessage = true
        do {
            let first = try await repository.listMessages(in: mailbox.id, beforeUID: nil,
                                                          limit: Self.pageSize)
            if quietly, generation != listGeneration || isSearchingOrTyping { return false }
            // Previews already on screen go across to the same letters, and
            // only the rest are fetched; see `ListLetters.fetchedAfresh`.
            let unpreviewed = letters.fetchedAfresh(first)
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
            loadPreviews(for: unpreviewed)
            kept.uploadWaiting(to: repository)
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
            if !quietly { ErrorPresenter.show(.cannotConnect, on: self) }
            return false
        }
    }

    // MARK: - Letters kept on the iPad

    /// Drafts' rows for the letters kept on the iPad, from what is kept
    /// now; in any other folder nothing.
    @MainActor
    private func listKept() {
        guard mailbox.role == .drafts else { return }
        let waiting = kept.waiting
        letters.keep(waiting.map { $0.row(in: mailbox.id, from: keptSender) },
                     replacing: Set(waiting.compactMap(\.draft.savedID)))
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
    }

    /// The line at rest said again as of now, if it is saying how fresh the
    /// list is: at each check, and as the app comes back to the front.
    @MainActor
    func showAge() {
        if showingAge { sayAge() }
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

    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        showNewsIfAtTop()
    }

    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { showNewsIfAtTop() }
    }

    override func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
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
        case .failed:
            ErrorPresenter.show(.cannotConnect, on: self)
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
        // conversations. Scroll to the ROW that carries that letter,
        // which for a message inside a collapsed thread is the
        // thread's own row.
        let anchorIndex = min(window.anchorIndex, window.messages.count - 1)
        let anchorID = window.messages[anchorIndex].id
        if let row = rowIndex(showing: anchorID) {
            tableView.scrollToRow(at: IndexPath(row: row, section: 0),
                                  at: .top, animated: false)
        }

        // The bottom bar stops reporting freshness and starts reporting
        // WHERE HE IS, which for a list that no longer starts at today
        // is the more urgent of the two. It goes back to "Updated Just
        // Now" on the next refresh.
        showingAge = false
        say("Showing \(IMAPDate.spokenDay(window.landedOn))")

        loadPreviews(for: window.messages)
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
        guard !isLoadingPage, !reachedOldestMessage,
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
            self.loadPreviews(for: fresh)
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

            if newer.count < Self.pageSize { self.reachedNewestMessage = true }

            let fresh = self.letters.prependPage(newer)
            guard !fresh.isEmpty else { return }

            // The rows he can see and the highlight are taken before the
            // rows are rebuilt and put back after, by their letters; see
            // `regroup`. No animation: an animated change ABOVE the viewport
            // animates the content out from under the reader, and the
            // offset fix would land a frame late and visibly jump.
            UIView.performWithoutAnimation { self.regroup() }
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
    /// for it live, and where they are tested.
    @MainActor
    private func loadPreviews(for rows: [MessageSummary]) {
        guard !rows.isEmpty else { return }
        let generation = listGeneration
        let groups = PreviewPass.groups(for: rows)
        let repository = self.repository
        Task { @MainActor [weak self] in
            await PreviewPass.run(
                groups,
                fetch: { ids, mailboxID in
                    try await repository.previews(for: ids, in: mailboxID)
                },
                isCurrent: { @MainActor in
                    generation == self?.listGeneration
                },
                apply: { @MainActor previews in
                    self?.apply(previews)
                })
        }
    }

    /// Patches the rows in place rather than calling `reloadRows`.
    ///
    /// `reloadRows` deselects what it reloads, and on the iPad the selected
    /// row is the message open in the pane to the right — so filling in a
    /// preview would visibly unhighlight the letter being read. Off-screen
    /// rows need no help: they pick the new text up from the model when they
    /// are next dequeued.
    @MainActor
    private func apply(_ previews: [String: String]) {
        letters.apply(previews: previews)

        // Regrouped first so the rows hold the new text; the row COUNT
        // cannot change, since a preview does not decide what threads
        // with what, so the cells can be patched in place.
        rebuildRows()
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            guard indexPath.row < rows.count,
                  let cell = tableView.cellForRow(at: indexPath) as? MessageCell else { continue }
            switch rows[indexPath.row] {
            case let .thread(t):
                cell.configure(with: t.displayRow())
            }
        }
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

    /// The line at rest says how fresh the list is, as of now.
    @MainActor
    private func sayAge() {
        say(updated.text(now: Date()))
    }

    /// Says `text` on the status line while something he asked for is on
    /// its way: a jump, or a Move from here or from the reading pane.
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
        statusLabel.sizeToFit()
    }

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
    @objc private func refreshTapped() {
        Task { @MainActor in
            await reload()
            onRefreshRequested?()
        }
    }

    /// Multi-select, which is what Edit is for. Deliberately the ONLY route to
    /// deleting more than one message - there is no swipe-to-delete anywhere,
    /// so nothing is ever binned by a stray thumb on a moving list.
    @objc private func editTapped() {
        let editing = !tableView.isEditing
        tableView.setEditing(editing, animated: true)
        navigationItem.rightBarButtonItem?.title = editing ? "Done" : "Edit"
        setToolbarItems(editing ? editItems : browseItems, animated: true)
        updateSelectAllTitle()
        // His ticks have gone with Edit mode: what the watch held can go on.
        if !editing { showNewsIfAtTop() }
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
    private var selectedMessages: [MessageSummary] {
        var seen = Set<String>()
        var out: [MessageSummary] = []
        for ip in tableView.indexPathsForSelectedRows ?? [] where ip.row < rows.count {
            switch rows[ip.row] {
            case let .thread(t):
                // Deduplicated even though a row can no longer be ticked
                // twice: two conversations that merge on the next page
                // would otherwise contribute the same letter to a delete.
                for m in t.messages where seen.insert(m.id).inserted { out.append(m) }
            }
        }
        return out
    }

    /// A letter kept on the iPad goes from the iPad, as Delete Draft in the
    /// composer takes it (`LocalDrafts.delete`). Handed to the repository
    /// with the rest, as it used to be, it was a write that could never
    /// land, spent a probe and failed on its id, silently, and the row came
    /// back with the reload.
    @objc private func deleteSelected() {
        let chosen = selectedMessages
        guard !chosen.isEmpty else { return }
        Task { @MainActor in
            for m in chosen {
                if let key = LocalDraft.key(ofRow: m.id) {
                    await kept.delete(key, from: repository)
                } else {
                    try? await repository.delete(m.id, from: m.mailboxID)
                }
            }
            editTapped()
            await reload(keepingPlace: true)
            onMessagesChanged?()
        }
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
                    try await self.repository.setRead(read, id: m.id, mailboxID: m.mailboxID)
                } catch {
                    continue          // leave this one as it was
                }
                self.letters.setRead(m.id, read: read)
                if read { self.letters.read(m) } else { self.letters.unread(m) }
            }
            if self.tableView.isEditing { self.editTapped() }
            self.regroup()
        }
    }

    /// Not the letters kept on the iPad: there is nothing on the server to
    /// move until they have gone to Drafts, and they stay in Drafts' list.
    @objc private func moveSelected() {
        let chosen = onServer(selectedMessages)
        guard !chosen.isEmpty else { return }
        let move = MoveMessageViewController(repository: repository,
                                             excluding: mailbox.id) { [weak self] destination in
            guard let self else { return }
            // At the tap, while the sheet slides away, and said on the
            // status line until the list has been fetched again.
            let moving = self.working(StatusLine.moving)
            Task { @MainActor in
                for m in chosen {
                    try? await self.repository.move(m.id, from: m.mailboxID, to: destination.id)
                }
                self.editTapped()
                await self.reload(keepingPlace: true)
                moving()
                self.onMessagesChanged?()
            }
        }
        let nav = UINavigationController(rootViewController: move)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    /// `letters` without the ones kept on the iPad.
    private func onServer(_ letters: [MessageSummary]) -> [MessageSummary] {
        letters.filter { LocalDraft.key(ofRow: $0.id) == nil }
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
            let draft = try? await self.repository.loadDraft(id: id,
                                                             mailboxID: summary.mailboxID)
            // Another draft tapped since is the one he wants now.
            guard self.drafts.landed(summary.id) else { return }
            self.showDraftSpinners()
            if let row = self.rowIndex(showing: summary.id) {
                self.tableView.deselectRow(at: IndexPath(row: row, section: 0), animated: false)
            }
            guard let draft else {
                ErrorPresenter.show(.cannotConnect, on: self)
                return
            }
            self.presentComposer(draft, key: nil, from: summary)
        }
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
    /// other. Cells scrolled in later ask `drafts` for themselves.
    @MainActor
    private func showDraftSpinners() {
        for ip in tableView.indexPathsForVisibleRows ?? [] where ip.row < rows.count {
            guard let cell = tableView.cellForRow(at: ip) as? MessageCell else { continue }
            switch rows[ip.row] {
            case let .thread(t):
                cell.isBusy = t.messages.contains { $0.id == drafts.loading }
            }
        }
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
        searchQuery = text
        searchDebounce?.cancel()

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
        // nothing about how much mail is left in the folder.
        reachedOldestMessage = letters.folder.count < Self.pageSize
        regroup(to: places.searchEnded(showingResults: showingResults))
        updateEmptyState()
        updatePageFooter()
        loadPreviews(for: unpreviewed)
        // Back in the folder, where he was: letters the watch found while
        // the search showed go on if that was the top.
        showNewsIfAtTop()
    }

    @objc private func cancelSearch() {
        searchQuery = ""
        showUnfilteredList()
    }

    @MainActor
    private func runSearch(_ text: String) async {
        listGeneration += 1
        let generation = listGeneration
        let scope = searchScope

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
            return
        case .draw(let found):
            hits = found
        }

        searchFailed = false
        let move = showingResults()
        letters.showResults(hits)
        reachedOldestMessage = hits.count < Self.pageSize
        regroup(to: move)
        updateEmptyState()
        updatePageFooter()
        loadPreviews(for: hits.filter { $0.preview.isEmpty })
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
        searchBar
    }

    override func tableView(_ t: UITableView, heightForHeaderInSection s: Int) -> CGFloat {
        // From the band's own idea of how tall it wants to be, NOT from its
        // frame: the table resets a section header's frame during layout,
        // so reading the frame back here returns the previous height and
        // the scope bar gets drawn over the first message instead of
        // pushing it down.
        searchBar.wantedHeight
    }

    /// Starts the next page while there is still a screenful to read.
    ///
    /// Ten rows of lead time rather than waiting for the last one, so the
    /// fetch is usually finished before he scrolls far enough to notice it
    /// happened. Loading only once he hits the bottom would stop the list
    /// dead every fifty messages.
    override func tableView(_ t: UITableView, willDisplay cell: UITableViewCell,
                            forRowAt ip: IndexPath) {
        // Upward first. After a date jump the list runs in both directions,
        // and the top of it is no longer the top of the folder.
        //
        // The threshold is the same share of the page the jump reserved
        // above the anchor, so landing on a date does not immediately
        // trigger the load of the page above it — he is inside the buffer,
        // not at the edge of it.
        if ip.row < max(1, Self.pageSize / 5) { loadPreviousPage() }
        guard ip.row >= rows.count - 10 else { return }
        loadNextPage()
    }

    @objc private func settingsTapped() {
        guard let account = CredentialStore.loadAccount() else { return }
        let settings = SettingsViewController(account: account)
        settings.onSaved = { [weak self] _ in
            // Nothing on this screen changes what is IN the mailbox, so the
            // list is not reloaded. The signature is read fresh every time a
            // compose window opens, so the next letter already has it.
            self?.onRefreshRequested?()
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
        switch rows[ip.row] {
        case let .thread(thread):
            cell.configure(with: thread.displayRow())
            cell.isBusy = thread.messages.contains { $0.id == drafts.loading }
            cell.accessibilityLabel = [
                LocalDraft.key(ofRow: thread.id) == nil ? nil : LocalDraft.mark,
                thread.isRead ? nil : "Unread",
                thread.participants.joined(separator: ", "),
                thread.count > 1 ? "\(thread.count) messages" : nil,
                thread.subject,
                MailFormat.listTimestamp(thread.date),
            ].compactMap { $0 }.joined(separator: ", ")
        }
        return cell
    }


    override func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        // In Edit mode a tap ticks a row rather than opening it, and the
        // Select All button has to keep up with what that leaves selected.
        guard !t.isEditing else { updateSelectAllTitle(); return }
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
        showNewsIfAtTop()
    }

    /// Opens a whole conversation in the reading pane.
    ///
    /// Only the letter the pane actually shows open is marked read — the
    /// newest — and the rest keep their unread dots until he expands them.
    /// Marking the lot read on one tap would empty his unread count for a
    /// thread he has read one line of, and the count is how he knows what
    /// is still waiting.
    @MainActor
    private func open(_ thread: MessageThread, at ip: IndexPath) {
        // Drafts never group into a stack: a tap there has to reopen the
        // composer, and there is no reading-pane form of that.
        if mailbox.role == .drafts {
            openDraft(thread.newest)
            return
        }

        onSelectThread?(thread)
        markReadIfNeeded(thread.newest)
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

        onSelectMessage?(m)
        markReadIfNeeded(m)
    }

    /// Marks one letter read locally, tells the server, and bills the
    /// folder counters — or puts everything back if the server refuses.
    ///
    /// Lifted out of `open` so the conversation path can use it for the one
    /// letter it actually shows open. Doing it twice in two places is how
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
        var m = summary
        guard !m.isRead else { return }
        m.isRead = true
        letters.setRead(m.id, read: true)
        // Regroup rather than reload the one row: the thread this letter
        // belongs to may have just lost its unread dot. Its row is
        // highlighted as the one open in the pane, except in Edit mode; see
        // `ListEdit.selectedRows`.
        regroup(highlighting: m.id)

        Task { @MainActor in
            do {
                try await repository.setRead(true, id: m.id, mailboxID: m.mailboxID)
            } catch {
                // Put the dot back. Before the sidebar counter existed a
                // failed STORE merely left the folder count stale HIGH,
                // which nags; decrementing anyway would leave it stale LOW,
                // and a count that is too low tells him there is no new mail
                // when there is. That is the failure this pane exists to
                // prevent, so the decrement is only ever committed after the
                // server has actually taken the flag.
                self.letters.setRead(m.id, read: false)
                self.regroup()
                return
            }
            // Once per message, ever. A reload can re-derive `isRead` from
            // server FLAGS that predate this STORE and put the unread dot
            // back, which re-arms the `guard !m.isRead` above — so the guard
            // alone would let one message be billed twice.
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
    @MainActor
    func markRead(_ letter: MessageSummary) {
        markReadIfNeeded(letters.letter(letter.id) ?? letter)
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
