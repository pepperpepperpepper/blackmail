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
        Task { @MainActor in
            await mailboxList.reload()
            mailboxList.select(mailboxID: "inbox")   // opens into Inbox, and shows that it did
        }
    }

    // MARK: - Coming back to it

    /// How long away counts as a NEW SITTING rather than an interruption.
    ///
    /// B-003. A judgement call, because it turns on his habit, not on
    /// anything in the code. `PRODUCT_SPEC.md` calls for two things that
    /// disagree — "the app opens into Inbox" and "preserve scroll position
    /// where practical" — and the answer is that both are right at
    /// different timescales.
    ///
    /// Fifteen minutes, erring SHORT on purpose. The two failures are not
    /// equal. Resetting too eagerly loses his place, which is a nuisance
    /// and now a cheap one to undo: the calendar button and search both
    /// exist to get back. Resetting too rarely means picking the iPad up
    /// the next morning and finding himself somewhere in last June with no
    /// idea how he got there or how to leave — which does not read as a
    /// preserved position, it reads as the app having lost his mail.
    private static let awayBeforeReturningToInbox: TimeInterval = 15 * 60

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
            Task { @MainActor in self?.returnedFromAway() }
        }
    }

    @MainActor
    private func returnedFromAway() {
        guard let away = wentAwayAt else { return }
        wentAwayAt = nil
        guard Date().timeIntervalSince(away) > Self.awayBeforeReturningToInbox else {
            // A short interruption. He is still doing the same thing, so
            // leave him where he was.
            return
        }
        // NOT while something is open over the top. A half-written letter
        // is the one piece of state in this app he cannot get back, and
        // pulling the folder out from under a compose sheet to be tidy
        // would be the worst trade in the product.
        guard presentedViewController == nil else { return }

        let inbox = mailboxList.mailbox(for: .inbox)
            ?? Mailbox(id: "inbox", name: "Inbox", unreadCount: 0, role: .inbox)
        openMailbox(inbox)
        Task { @MainActor in
            await mailboxList.reload()
            mailboxList.select(mailboxID: inbox.id)
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
        detail.onNeedsListRefresh = { [weak self] in
            guard let self else { return }
            Task { await self.list.reload() }
            // The folder counts too. This was missing, and it was a live bug
            // rather than an oversight introduced here: moving or deleting a
            // message from the DETAIL pane's toolbar changes two folders'
            // unread counts and never touched the sidebar at all. It also
            // matters more now, because this is one of the few remaining
            // events that reconciles the local counter against the server.
            self.refreshMailboxes()
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
    /// is reading.
    private func refreshMailboxes() {
        let current = list.mailboxID
        Task { @MainActor in
            await mailboxList.reload()
            mailboxList.select(mailboxID: current)
        }
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
