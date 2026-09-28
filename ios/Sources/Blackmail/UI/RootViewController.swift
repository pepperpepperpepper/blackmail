// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

/// The three-pane shell: Mailboxes | message list | message.
///
/// Not a `UISplitViewController`. That class — and especially its
/// `.tripleColumn` style — *is* the iPadOS 14 sidebar redesign: adaptive by
/// construction, with column widths that are merely "preferred" and get
/// silently clamped, and a collapse behaviour that moves controls around based
/// on context. Every one of those is a thing this product exists to prevent.
/// A plain container with hard constraints does what it is told.
///
/// Nothing here is a navigation stack, and that is the point of three panes
/// rather than two: there is no back button anywhere, because nothing is ever
/// covered up. The folder list is always on screen in the same place, so
/// "where am I" is answered by looking rather than by remembering.
final class RootViewController: UIViewController {

    private let repository: MailRepository

    private let mailboxNav: UINavigationController
    private let listNav: UINavigationController
    private let detail: MessageDetailViewController

    private let mailboxList: MailboxListViewController
    private var list: MessageListViewController

    private let divider1 = UIView()
    private let divider2 = UIView()
    private var mailboxWidth: NSLayoutConstraint!
    private var listWidth: NSLayoutConstraint!

    init(repository: MailRepository) {
        self.repository = repository
        self.mailboxList = MailboxListViewController(repository: repository)
        self.mailboxNav = UINavigationController(rootViewController: mailboxList)
        // The list pane opens on Inbox, as `PRODUCT_SPEC.md` requires, and is replaced
        // wholesale when another folder is chosen.
        self.list = MessageListViewController(
            repository: repository,
            mailbox: Mailbox(id: "inbox", name: "Inbox", unreadCount: 0, role: .inbox))
        self.listNav = UINavigationController(rootViewController: list)
        self.detail = MessageDetailViewController(repository: repository)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.canvas

        // Chrome is styled once, here, rather than per screen. Compact titles,
        // opaque bars, no large-title behaviour: large titles arrived in iOS 11
        // and move the title between scroll positions, which is exactly the
        // kind of motion this app is built to avoid.
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = Theme.barFill
        // Set explicitly, or each bar falls through to its own default and the
        // hairline under the top chrome is several different greys meeting at
        // the pane dividers — a 1194 pt line with visible steps in it.
        bar.shadowColor = Theme.separator
        bar.titleTextAttributes = [.font: Theme.fontNavTitle, .foregroundColor: Theme.primaryText]
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
        UINavigationBar.appearance().tintColor = Theme.tintBlue
        UINavigationBar.appearance().prefersLargeTitles = false

        let toolbar = UIToolbarAppearance()
        toolbar.configureWithOpaqueBackground()
        toolbar.backgroundColor = Theme.barFill
        toolbar.shadowColor = Theme.separator
        UIToolbar.appearance().standardAppearance = toolbar
        UIToolbar.appearance().compactAppearance = toolbar
        UIToolbar.appearance().scrollEdgeAppearance = toolbar

        // The bottom bar belongs to the MESSAGE LIST, not the folder list. In
        // the reference "Updated Just Now / 0 Unread" sits under the middle
        // column, which is the one whose freshness it describes.
        listNav.setToolbarHidden(false, animated: false)
        mailboxNav.setToolbarHidden(true, animated: false)
        // "Edit" otherwise keeps UIKit's 20 pt bar margin and sits 21.5 pt from
        // the divider while the row timestamps sit at 15, so the column's
        // right edge is not a straight line.
        for nav in [mailboxNav, listNav] {
            nav.navigationBar.directionalLayoutMargins.trailing = Theme.rowTextRightInset
        }

        let detailNav = UINavigationController(rootViewController: detail)
        detailNav.setNavigationBarHidden(false, animated: false)

        for child in [mailboxNav, listNav, detailNav] {
            addChild(child)
            child.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child.view)
            child.didMove(toParent: self)
        }
        for d in [divider1, divider2] {
            d.backgroundColor = Theme.paneDivider
            d.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(d)
        }

        let w = UIScreen.main.bounds.width
        mailboxWidth = mailboxNav.view.widthAnchor.constraint(
            equalToConstant: Theme.mailboxColumnWidth(forScreenWidth: w))
        listWidth = listNav.view.widthAnchor.constraint(
            equalToConstant: Theme.listColumnWidth(forScreenWidth: w))

        var constraints: [NSLayoutConstraint] = [
            mailboxNav.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mailboxWidth,
            divider1.leadingAnchor.constraint(equalTo: mailboxNav.view.trailingAnchor),
            divider1.widthAnchor.constraint(equalToConstant: Theme.paneDividerWidth),
            listNav.view.leadingAnchor.constraint(equalTo: divider1.trailingAnchor),
            listWidth,
            divider2.leadingAnchor.constraint(equalTo: listNav.view.trailingAnchor),
            divider2.widthAnchor.constraint(equalToConstant: Theme.paneDividerWidth),
            detailNav.view.leadingAnchor.constraint(equalTo: divider2.trailingAnchor),
            detailNav.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ]
        for v in [mailboxNav.view, listNav.view, detailNav.view, divider1, divider2] {
            guard let v else { continue }
            constraints.append(v.topAnchor.constraint(equalTo: view.topAnchor))
            constraints.append(v.bottomAnchor.constraint(equalTo: view.bottomAnchor))
        }
        NSLayoutConstraint.activate(constraints)

        wireNavigation()
        watchForReturn()

        // The folder list only. The Inbox loads itself: the list controller
        // starts its own reload from its `viewDidLoad`, as it does for every
        // folder opened, and `select(mailboxID:)` only highlights, so it
        // opens nothing. A second `list.reload()` here used to fetch
        // the whole first page again, blank the previews that had already
        // landed, and clear a search typed in the first seconds after
        // launch, keyboard and all.
        //
        // In this order on the wire: LOGIN, the one LIST the folder names
        // and the Inbox's role share, the Inbox's first page, and only then
        // the unread counts, a STATUS per folder. The counts used to go
        // first, the Inbox's SELECT eighteen or so commands deep.
        Task { @MainActor in
            await mailboxList.showFolders()
            mailboxList.select(mailboxID: "inbox")   // opens into Inbox, and shows that it did
        }
        // Asked for now, sent once the Inbox's first page has come: the
        // folder pane holds its sweeps until it is told to let them go. If
        // the page could not be fetched the counts are not asked for at
        // all, since they would connect again straight after the connect
        // that failed, and send a refused password a second time.
        mailboxList.refreshCounts()
        list.onFirstLoadFinished = { [weak self] came in
            self?.mailboxList.releaseSweeps(firstPageCame: came)
        }
    }

    // MARK: - Coming back to it

    private var wentAwayAt: Date?

    private func watchForReturn() {
        let centre = NotificationCenter.default
        centre.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.wentAwayAt = Date()
        }
        centre.addObserver(forName: UIApplication.willEnterForegroundNotification,
                           object: nil, queue: .main) { [weak self] _ in
            // The queue is `.main`, but that is not the same promise as
            // MainActor isolation as far as the compiler is concerned.
            Task { @MainActor [weak self] in
                guard let self else { return }
                // A connection quiet long enough to have died while the iPad
                // slept is probed now, and replaced if it has, rather than by
                // the first thing he taps. Nothing waits for it.
                let repository = self.repository
                Task { await repository.warmUp() }
                self.returnedFromAway()
            }
        }
    }

    /// B-003: after a while away, back to the Inbox, at the top. See
    /// `Sitting`, which decides.
    @MainActor
    private func returnedFromAway() {
        guard let away = wentAwayAt else { return }
        wentAwayAt = nil
        switch Sitting.onReturn(after: Date().timeIntervalSince(away),
                                showingInbox: list.shownMailbox.role == .inbox,
                                sheetOpen: presentedViewController != nil) {
        case .stay:
            return
        case .refreshInbox:
            // The list on screen, fetched again from the top, and the letter
            // in the reading pane left where it is. This used to build a
            // new, empty list and empty the pane, to land him in the Inbox
            // he was already in.
            mailboxList.select(mailboxID: list.mailboxID)
            let list = self.list
            Task { @MainActor in
                await Sitting.refresh(newest: { await list.returnToNewest() },
                                      counts: { [weak self] in self?.mailboxList.refreshCounts() })
            }
        case .openInbox:
            let inbox = mailboxList.mailbox(for: .inbox)
                ?? Mailbox(id: "inbox", name: "Inbox", unreadCount: 0, role: .inbox)
            openMailbox(inbox)
            mailboxList.select(mailboxID: inbox.id)
            // The counts once the Inbox's first page has come, and not at
            // all if it could not be fetched: the rule `Sitting.refresh`
            // follows, for a page this list fetches itself.
            list.onFirstLoadFinished = { [weak self] came in
                Sitting.afterNewest(came: came, counts: { self?.mailboxList.refreshCounts() })
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with c: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: c)
        // Widths follow the screen; order and content never do.
        mailboxWidth.constant = Theme.mailboxColumnWidth(forScreenWidth: size.width)
        listWidth.constant = Theme.listColumnWidth(forScreenWidth: size.width)
    }

    // MARK: - Wiring

    /// The only object that connects the panes. The table controllers stay
    /// ignorant of each other, so a change here cannot ripple into them.
    private func wireNavigation() {
        mailboxList.onSelectMailbox = { [weak self] mailbox in
            self?.openMailbox(mailbox)
        }
        // Delete, Move and Flag from the reading pane edit the list on
        // screen in place, and ask for the folder counts only when one may
        // have changed; see `PaneActions`. They used to reload the whole
        // list and sweep every count, which blanked the previews and threw
        // away a search, a date jump and his place in the list. The counts
        // were missing from this path once, a live bug: moving an unread
        // letter from the pane changes two folders' counts.
        detail.perform = { [weak self] action, letter in
            guard let self else { return false }
            let folders = [self.list.shownMailbox] + self.mailboxList.folders
            // A Move is asked for at the tap on its folder, while the sheet
            // slides away, and the list says so until the server answers.
            // The letter itself has gone from the pane and the list by then.
            var moving: (() -> Void)?
            if case .move = action { moving = self.list.working(StatusLine.moving) }
            defer { moving?() }
            return await PaneActions.run(
                action, on: letter, inFolderWithRole: folders.role(of: letter.mailboxID),
                list: self.list.letters, repository: self.repository,
                requestSweep: { [weak self] in self?.refreshMailboxes() })
        }
        detail.onLetterOpened = { [weak self] letter in
            self?.list.markRead(letter)
        }
        bindList()
    }

    /// Opens All Mail and lands it on a date.
    ///
    /// Gmail's All Mail is what "all mailboxes" means here, exactly as it
    /// does for search — everything except Trash and Spam. The pane really
    /// becomes that folder, so the title, the count and the paging all
    /// agree with what is on screen.
    private func jumpAcrossMailboxes(to date: Date) {
        guard let all = mailboxList.mailbox(for: .archive) else { return }
        openMailbox(all)
        list.pendingJump = date
        mailboxList.select(mailboxID: all.id)
    }

    private func bindList() {
        list.onJumpAcrossMailboxes = { [weak self] date in
            self?.jumpAcrossMailboxes(to: date)
        }
        list.onSelectMessage = { [weak self] summary in
            self?.detail.show(summary: summary)
        }
        list.onSelectThread = { [weak self] thread in
            self?.detail.show(thread: thread)
        }
        list.onMessagesChanged = { [weak self] in
            guard let self else { return }
            self.detail.clearIfShowingDeletedMessage()
            // Moving or binning a letter changes the unread count of TWO
            // folders, and the numbers beside the folder names are the only
            // thing on screen that says there is something new. Leaving them
            // stale until he happens to press Refresh means the folder list
            // lies about his mail — found on device: after moving an unread
            // message out of the Inbox, Inbox still read 6 and the
            // destination still read 1 while plainly holding two.
            self.refreshMailboxes()
        }
        list.onRefreshRequested = { [weak self] in
            self?.refreshMailboxes()
        }
        // Local arithmetic, no network. Reading is the most frequent thing
        // anyone does with mail, and a full sweep per tap is a LIST plus a
        // STATUS per folder.
        list.onUnreadCountChanged = { [weak self] mailboxIDs, delta in
            self?.mailboxList.adjustUnreadCounts(mailboxIDs, by: delta)
        }
    }

    /// Rebuilds the folder list and puts the highlight back.
    ///
    /// The re-select is not optional: `reloadData` drops the selection, so
    /// without it the folder he is reading stops looking like the folder he
    /// is reading. The folder pane puts it back after each sweep.
    ///
    /// Requests that overlap are merged into at most one more sweep, which
    /// starts after the latest of them; see `SweepCoalescer`.
    private func refreshMailboxes() {
        mailboxList.select(mailboxID: list.mailboxID)
        mailboxList.refreshCounts()
    }

    /// Swaps the middle pane's contents. Deliberately `setViewControllers`
    /// rather than a push: the stack stays exactly one deep, so no back button
    /// ever appears and the folder list never slides away.
    private func openMailbox(_ mailbox: Mailbox) {
        // The list going away may still be searching. Nothing will draw
        // what it finds, and until it stops it is ahead of the new folder's
        // later pages and previews.
        list.stopSearching()
        list = MessageListViewController(repository: repository, mailbox: mailbox)
        bindList()
        listNav.setViewControllers([list], animated: false)
        detail.showEmpty()
    }
}

#endif
