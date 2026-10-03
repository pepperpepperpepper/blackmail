// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

/// The shell: Mailboxes | message list | message, or, if he has chosen two
/// panes, the Mailboxes and the list taking turns in one column beside the
/// message (D-015). The view button in the top-left corner switches.
///
/// Not a `UISplitViewController`. That class — and especially its
/// `.tripleColumn` style — *is* the iPadOS 14 sidebar redesign: adaptive by
/// construction, with column widths that are merely "preferred" and get
/// silently clamped, and a collapse behaviour that moves controls around based
/// on context. Every one of those is a thing this product exists to prevent.
/// A plain container with hard constraints does what it is told.
///
/// In three panes nothing here is a navigation stack, and that is the point
/// of three panes rather than two: there is no back button anywhere, because
/// nothing is ever covered up. The folder list is always on screen in the
/// same place, so "where am I" is answered by looking rather than by
/// remembering.
///
/// In two panes the left column works as a stack of two, as D-003 laid it
/// out: the Mailboxes at the root, a folder's list over them, "< Mailboxes"
/// to go back. It is not a `UINavigationController` push. The list stays in
/// its own navigation controller in both arrangements and the two
/// controllers take turns in the column, so a switch moves the list and
/// never takes its view out of the window. Moved into the Mailboxes' stack
/// it would leave the window at every switch, and the search field with it,
/// keyboard and all; and a pushed list's own back button always takes the
/// corner, which is where the view button has to be in both arrangements.
final class RootViewController: UIViewController {

    /// Not private: a `mailto:` link opened from outside the app writes
    /// its letter on the same repository (`AppDelegate.application(_:open:)`).
    let repository: MailRepository

    private let mailboxNav: UINavigationController
    private let listNav: UINavigationController
    private let detail: MessageDetailViewController

    private let mailboxList: MailboxListViewController
    private var list: MessageListViewController

    private let divider1 = UIView()
    private let divider2 = UIView()
    private var mailboxWidth: NSLayoutConstraint!
    private var listWidth: NSLayoutConstraint!
    /// The list's left edge: against the Mailboxes' divider in three panes,
    /// at the screen's edge in two, where it shares the column with them.
    private var listBesideMailboxes: NSLayoutConstraint!
    private var listInLeftColumn: NSLayoutConstraint!
    private var screenWidth: CGFloat = 0

    /// Two panes or three, which of the Mailboxes and the list is in front
    /// in two, and what each button and tap does to them; see `PaneShell`.
    /// Launched in what he chose last, and kept at every switch. Made once
    /// and never again: made afresh, by a return from a while away or
    /// anything else, it would undo his choice (B-037).
    private let shell = PaneShell(launching: PaneArrangement.saved)
    /// The arrangement last laid out, so the layout sweep runs each time
    /// what is on screen changes: at a switch, and in two panes at
    /// "< Mailboxes" and at a folder tapped there, whose new list it sees
    /// before any rows have come. Not when nothing has moved, as at a tap in
    /// three panes or a return to the list already in front.
    private var arranged: PaneArrangement?

    /// The view button in the Mailboxes' bar, and the one in the list's bar
    /// in two panes, with "< Mailboxes" beside it. Two view buttons because
    /// a bar item's view can be in only one bar, and both bars are there,
    /// one hidden, in two panes. Both sit first in a bar whose left edge is
    /// the screen's, so they are in the same place.
    private var mailboxesViewButton: UIButton!
    private var listViewButton: UIButton!
    private var listViewItem: UIBarButtonItem!
    private var backItem: UIBarButtonItem!

    /// New mail without a tap, while the app is in front (B-049). Started
    /// once the Inbox's first page has been tried, stopped as the app goes
    /// into the background and started again as it comes back.
    private lazy var watch: MailWatch = {
        let watch = MailWatch(repository: repository)
        watch.target = self
        return watch
    }()
    /// Whether the launch's first page has been tried, after which the
    /// watch starts, and starts again at every return to the app.
    private var firstPageTried = false
    /// Whether the watch's last check could not reach the server. See
    /// `checked`.
    private var lastCheckFailed = false

    /// What the sign-in check had to say of the password these screens
    /// were built for, put up once they are on the screen and then
    /// forgotten: Gmail taking it for reading but not, for now, for
    /// sending (`SignInCheck.Outcome`). Nil at every launch.
    private var notice: MailAlert?

    init(repository: MailRepository, saying notice: MailAlert? = nil) {
        self.repository = repository
        self.notice = notice
        self.mailboxList = MailboxListViewController(repository: repository)
        self.mailboxNav = UINavigationController(rootViewController: mailboxList)
        // The list pane opens on Inbox, as `PRODUCT_SPEC.md` requires, and is replaced
        // wholesale when another folder is chosen.
        self.list = MessageListViewController(
            repository: repository,
            mailbox: .inboxBeforeListing)
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

        // Sized by `sizeColumns`, for the arrangement he chose.
        screenWidth = UIScreen.main.bounds.width
        mailboxWidth = mailboxNav.view.widthAnchor.constraint(equalToConstant: 0)
        listWidth = listNav.view.widthAnchor.constraint(equalToConstant: 0)
        listBesideMailboxes = listNav.view.leadingAnchor.constraint(
            equalTo: divider1.trailingAnchor)
        listInLeftColumn = listNav.view.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        sizeColumns(shell.arrangement.panes)

        // Every view keeps a full set of constraints in both arrangements;
        // only the list's left edge changes. A view with some of its
        // constraints taken away is ambiguous, which `LayoutAudit` reports
        // whether or not the view is hidden.
        var constraints: [NSLayoutConstraint] = [
            mailboxNav.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mailboxWidth,
            divider1.leadingAnchor.constraint(equalTo: mailboxNav.view.trailingAnchor),
            divider1.widthAnchor.constraint(equalToConstant: Theme.paneDividerWidth),
            shell.arrangement.listAtScreenEdge ? listInLeftColumn : listBesideMailboxes,
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

        mailboxesViewButton = makeViewButton()
        mailboxList.navigationItem.leftBarButtonItem =
            UIBarButtonItem(customView: mailboxesViewButton)
        listViewButton = makeViewButton()
        listViewItem = UIBarButtonItem(customView: listViewButton)
        backItem = UIBarButtonItem(customView: makeBackButton())

        wireNavigation()
        arrange(shell.arrangement)
        watchForReturn()
        // A refused password's alert opens Settings at the password, from
        // whichever pane it was put over. A turn later, once the alert has
        // gone.
        ErrorPresenter.openSettings = { [weak self] in
            DispatchQueue.main.async { self?.list.showSettings(focusingPassword: true) }
        }

        // The Inbox highlighted among the folders kept on the iPad, in the
        // first frame, beside its kept list (D-016); with nothing kept this
        // only remembers it for the rows to come.
        mailboxList.select(mailboxID: "inbox")

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
            // Once the first page has been tried, so a check never goes
            // beside it: the first is half a minute on, after the counts.
            // Started whether or not the page came, so that with no
            // connection at launch the counts come of themselves once there
            // is one. It sends no password that has been refused.
            self?.firstPageTried = true
            self?.watch.start()
            // The first page is drawn, as fetched, as kept, or as nothing
            // to draw, and the pass it set off over the letters kept on the
            // iPad is on its way if there was one: half a minute after that
            // pass, the launch has finished (B-057).
            SafeStart.app.firstPageTried(passEnded: { await LocalDrafts.shared.passEnded() })
        }
    }

    /// The sign-in check's word on the password these screens were built
    /// for, once: put up when they are on the screen, since an alert asked
    /// for any sooner has no window to go in and is dropped.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let notice else { return }
        self.notice = nil
        ErrorPresenter.say(notice, on: self)
    }

    // MARK: - Coming back to it

    private var wentAwayAt: Date?

    private func watchForReturn() {
        let centre = NotificationCenter.default
        centre.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.wentAwayAt = Date()
            // Nothing is checked while the app is away. A check on the wire
            // is answered and nothing after it is sent.
            Task { @MainActor [weak self] in _ = self?.watch.stop() }
        }
        centre.addObserver(self, selector: #selector(leavingTheApp),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
        centre.addObserver(forName: UIApplication.willEnterForegroundNotification,
                           object: nil, queue: .main) { [weak self] _ in
            // The queue is `.main`, but that is not the same promise as
            // MainActor isolation as far as the compiler is concerned.
            Task { @MainActor [weak self] in
                guard let self else { return }
                // In front of him again: the pass's tries count again, from
                // the one this return sets off (B-057).
                LocalDrafts.shared.cameToForeground()
                // A connection quiet long enough to have died while the iPad
                // slept is probed now, and replaced if it has, rather than by
                // the first thing he taps. Nothing waits for it. Then the
                // letters kept on the iPad that could not go before (B-051),
                // over the connection the warm-up has proven or made, and
                // not at all if it has none; with none waiting, nothing is
                // sent.
                let repository = self.repository
                Task { @MainActor in
                    await repository.warmUp()
                    LocalDrafts.shared.uploadWaiting(to: repository)
                }
                self.returnedFromAway()
                // How long ago the list was brought up to date, as of now,
                // and the checks again from half a minute on, the warm-up and
                // a return to the Inbox having gone first. Not if he is back
                // before the launch's first page has been tried: that starts
                // them, and a check started now could go beside the page.
                self.list.showAge()
                if self.firstPageTried { self.watch.start() }
            }
        }
    }

    /// The letters kept on the iPad go as he leaves the app, large ones as
    /// well, inside background time: nothing he taps is waiting for the
    /// connection then (`LocalDrafts.uploadWaiting`). Asked for here, on
    /// the main thread as the notification is posted, so the time is asked
    /// for before iOS can suspend the app.
    ///
    /// The tries on their way are taken back first, and these are not
    /// counted: iOS may end the app before they are done, which says
    /// nothing about the letters (B-057, `LocalDrafts.wentToBackground`).
    @objc private func leavingTheApp() {
        LocalDrafts.shared.wentToBackground()
        LocalDrafts.shared.uploadWaiting(to: repository, largeToo: true)
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
            // In front, in two panes: he is back in the Inbox, not in the
            // folders. Two panes stay two.
            shell.showList()
            let list = self.list
            Task { @MainActor in
                await Sitting.refresh(newest: { await list.returnToNewest() },
                                      counts: { [weak self] in self?.mailboxList.refreshCounts() })
            }
        case .openInbox:
            let inbox = mailboxList.mailbox(for: .inbox)
                ?? .inboxBeforeListing
            shell.open(inbox)
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
        screenWidth = size.width
        sizeColumns(shell.arrangement.panes)
    }

    // MARK: - Two panes or three

    private func sizeColumns(_ panes: PaneArrangement.Panes) {
        let columns = PaneArrangement.columns(panes, screenWidth: screenWidth)
        mailboxWidth.constant = columns.mailboxes
        listWidth.constant = columns.list
    }

    /// Lays the panes out as `panes` says, at once: what `PaneShell` hands
    /// over after each thing he does.
    ///
    /// No animation, deliberately. Animated, the switch would slide the list
    /// sideways and reflow the letter and every row's text through a quarter
    /// of a second, all of it moving at once; as it is, there is one step
    /// and then stillness. Nothing moves up or down either way: the rows are
    /// a fixed height and the list keeps its scroll offset, so the rows he
    /// was looking at are the rows he is looking at, a pane further left or
    /// right.
    ///
    /// Hidden, never zero wide: a view with children and no width is the
    /// B-027 shape `LayoutAudit` hunts.
    private func arrange(_ panes: PaneArrangement) {
        sizeColumns(panes.panes)
        let edge = panes.listAtScreenEdge
        // Off before on, or for a moment the list would have two left edges.
        NSLayoutConstraint.deactivate([edge ? listBesideMailboxes : listInLeftColumn])
        NSLayoutConstraint.activate([edge ? listInLeftColumn : listBesideMailboxes])
        mailboxNav.view.isHidden = !panes.mailboxesOnScreen
        listNav.view.isHidden = !panes.listOnScreen
        divider1.isHidden = !panes.mailboxDividerOnScreen
        for button in [mailboxesViewButton, listViewButton] {
            button?.accessibilityLabel = panes.viewButtonLabel
        }
        dressList(panes)
        defer { arranged = panes }
        guard view.window != nil else { return }
        UIView.performWithoutAnimation { view.layoutIfNeeded() }
        if let arranged, arranged != panes { LayoutAudit.panesChanged(to: describe(panes)) }
    }

    /// The controls `itemsBeforeCalendar` names, in front of the list's
    /// calendar: in two panes the view button and "< Mailboxes"; in three
    /// nothing, since the list is in the middle and the corner belongs to
    /// the Mailboxes' bar. The calendar keeps the list's leading slot in
    /// both and is never replaced, and Edit and the title are the list's own
    /// and not touched.
    private func dressList(_ panes: PaneArrangement) {
        list.itemsBeforeCalendar = panes.itemsBeforeCalendar.map { item -> UIBarButtonItem in
            switch item {
            case .viewButton: return listViewItem
            case .back: return backItem
            }
        }
    }

    /// The view button (D-015), two panes or three. `sidebar.left`, the
    /// symbol later iPadOS draws for the same control; which glyph iOS 10
    /// drew is not known here.
    private func makeViewButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "sidebar.left",
                                withConfiguration: UIImage.SymbolConfiguration(
                                    font: Theme.fontBarButton, scale: .large)),
                        for: .normal)
        button.tintColor = Theme.tintBlue
        // The glyph at the bar's margin, where UIKit puts a leading glyph of
        // its own, and the rest of the target to the right of it.
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: #selector(viewButtonTapped), for: .touchUpInside)
        // Taken only while nothing else is being touched. The switch moves
        // the list and the letter sideways, and a finger already down on
        // either would have it moved out from under it.
        button.isExclusiveTouch = true
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Theme.minHitTarget),
            button.heightAnchor.constraint(equalToConstant: Theme.minHitTarget),
        ])
        return button
    }

    /// "< Mailboxes", in the list's bar in two panes. Made here, because a
    /// list that is not pushed gets no back button from UIKit, and UIKit's
    /// own shortens itself to "Back", or to the chevron alone, when the bar
    /// is full. The word is the point of it (D-003), so this one keeps its
    /// width and the title gives way.
    private func makeBackButton() -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "chevron.backward",
                               withConfiguration: UIImage.SymbolConfiguration(
                                   font: Theme.fontBarButton, scale: .large)
                                   .applying(UIImage.SymbolConfiguration(weight: .semibold)))
        config.imagePadding = 5
        config.baseForegroundColor = Theme.tintBlue
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        var title = AttributedString("Mailboxes")
        title.font = Theme.fontBarButton
        config.attributedTitle = title
        button.configuration = config
        // Not "Mailboxes" alone, beside a view button that says "Show
        // Mailboxes".
        button.accessibilityLabel = "Back to Mailboxes"
        button.addTarget(self, action: #selector(backToMailboxes), for: .touchUpInside)
        button.isExclusiveTouch = true
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: Theme.minHitTarget),
            button.heightAnchor.constraint(equalToConstant: Theme.minHitTarget),
        ])
        return button
    }

    /// Two panes or three. Nothing is fetched and nothing is closed: the
    /// folder, its list with its search and Edit mode, the letter in the
    /// pane and any sheet over them are the same objects afterwards, moved
    /// or hidden. The choice is kept for the next launch.
    @objc private func viewButtonTapped() {
        // In three panes the folders are back, and the open one says so.
        mailboxList.select(mailboxID: list.mailboxID)
        shell.switchPanes()
        // The button VoiceOver was on may now be in a hidden bar. Its twin
        // is in the same corner, and says the other thing.
        UIAccessibility.post(notification: .layoutChanged,
                             argument: shell.arrangement.leftColumn == .list
                                ? listViewButton : mailboxesViewButton)
    }

    /// The folders, in front of the list. The keyboard goes with the list,
    /// as it would with a pushed one; the search stays in it, and is there
    /// when he taps the same folder to go back.
    @objc private func backToMailboxes() {
        list.view.endEditing(true)
        mailboxList.select(mailboxID: list.mailboxID)
        shell.back()
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    private func describe(_ panes: PaneArrangement) -> String {
        switch (panes.panes, panes.leftColumn) {
        case (.three, _): return "three panes"
        case (.two, .mailboxes): return "two panes, the Mailboxes in front"
        case (.two, .list): return "two panes, the list in front"
        }
    }

    // MARK: - Wiring

    /// The only object that connects the panes. The table controllers stay
    /// ignorant of each other, so a change here cannot ripple into them.
    private func wireNavigation() {
        // What `PaneShell` cannot do on the host: a new list for a folder,
        // and the panes laid out. Everything that opens a folder or moves
        // the panes goes through it, and it calls these.
        shell.openList = { [weak self] mailbox in self?.openMailbox(mailbox) }
        shell.layOut = { [weak self] panes in self?.arrange(panes) }
        mailboxList.onSelectMailbox = { [weak self] mailbox in
            guard let self else { return }
            self.shell.tapped(mailbox, showing: self.list.shownMailbox)
            // In two panes the folders VoiceOver was reading have gone
            // behind the list, as after a push.
            if self.shell.arrangement.panes == .two {
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }
        // Delete, Move and Flag from the reading pane edit the list on
        // screen in place, and ask for the folder counts only when one may
        // have changed; see `PaneActions`. They used to reload the whole
        // list and sweep every count, which blanked the previews and threw
        // away a search, a date jump and his place in the list. The counts
        // were missing from this path once, a live bug: moving an unread
        // letter from the pane changes two folders' counts.
        detail.perform = { [weak self] action, letter in
            guard let self else { return .cannotConnect }
            let folders = [self.list.shownMailbox] + self.mailboxList.folders
            // A Move is asked for at the tap on its folder, while the sheet
            // slides away, and the list says so until the server answers.
            // The letter itself has gone from the pane and the list by then.
            var moving: (() -> Void)?
            if case .move = action { moving = self.list.working(StatusLine.moving) }
            defer { moving?() }
            return await PaneActions.refusal(
                running: action, on: letter, inFolderWithRole: folders.role(of: letter.mailboxID),
                list: self.list.letters, repository: self.repository,
                requestSweep: { [weak self] in self?.refreshMailboxes() })
        }
        // Delete inside Trash erases the letter, and asks first; anywhere
        // else it moves the letter to Trash and asks nothing (B-062). By
        // the role of the letter's own folder, which for an All Mailboxes
        // hit from Trash is Trash whatever the list is.
        detail.questionBeforeDeleting = { [weak self] letter in
            guard let self else { return nil }
            let folders = [self.list.shownMailbox] + self.mailboxList.folders
            return EraseQuestion.before(deleting: [letter], role: { folders.role(of: $0) })
        }
        detail.onLetterOpened = { [weak self] letter in
            self?.list.markRead(letter)
        }
        // A letter opened from a row kept on the iPad that the server says
        // is another letter now (D-016): off the list, if it is still that
        // row there.
        detail.onNotTheKeptLetter = { [weak self] letter in
            guard let self else { return }
            PaneActions.notTheKeptLetter(letter, list: self.list.letters)
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
        shell.open(all)
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
        // Edit mode's Delete and Move edit the list in place, as the
        // pane's do, and ask for the counts only when one may have changed
        // that the list cannot work out (`ListBatch`, B-062). They used to
        // fetch the list again and sweep every count, through
        // `onMessagesChanged`, which also emptied the pane whatever it
        // showed.
        list.onLettersLeaving = { [weak self] letters in
            self?.detail.clearIfShowing(any: letters)
        }
        list.requestSweep = { [weak self] in
            self?.refreshMailboxes()
        }
        list.folders = { [weak self] in
            self?.mailboxList.folders ?? []
        }
        list.onPasswordSaved = { [weak self] account, password, notice in
            self?.signIn(as: account, password: password, saying: notice)
        }
        // Local arithmetic, no network. Reading is the most frequent thing
        // anyone does with mail, and a full sweep per tap is a LIST plus a
        // STATUS per folder.
        list.onUnreadCountChanged = { [weak self] mailboxIDs, delta in
            self?.mailboxList.adjustUnreadCounts(mailboxIDs, by: delta)
        }
    }

    /// A new password has been checked and saved in Settings: the screens
    /// are built again over a repository that signs in with it, now, as
    /// setup's are once it has an account (`AppDelegate.makeRoot`), and
    /// this one is retired (`PasswordChange`). The watch stops first, so no
    /// check goes on the old repository meanwhile. Settings has gone by
    /// then, and nothing else can be over the screens: it opens only when
    /// nothing is. `notice`, what the check had to say of the password, is
    /// put up over the new screens.
    private func signIn(as account: MailAccount, password: String, saying notice: MailAlert?) {
        guard let window = view.window else { return }
        _ = watch.stop()
        let old = repository
        Task { @MainActor in
            let fresh = await PasswordChange.handOver(from: old, drafts: LocalDrafts.shared) {
                IMAPMailRepository(account: account, password: password)
            }
            Diagnostics.log(.note, "PASSWORD-SAVED signed in afresh")
            window.rootViewController = RootViewController(repository: fresh, saying: notice)
        }
    }

    /// Rebuilds the folder list and puts the highlight back.
    ///
    /// The re-select is not optional: `reloadData` drops the selection, so
    /// without it the folder he is reading stops looking like the folder he
    /// is reading. The folder pane puts it back after each sweep.
    ///
    /// Requests that overlap are merged into at most one more sweep, which
    /// starts after the latest of them; see `SweepCoalescer`. `quietly` for
    /// the watch's, which puts up no alert if it fails.
    private func refreshMailboxes(quietly: Bool = false) {
        mailboxList.select(mailboxID: list.mailboxID)
        mailboxList.refreshCounts(quietly: quietly)
    }

    /// Swaps the list's contents, in the middle in three panes and in the
    /// left column in two. Deliberately `setViewControllers` rather than a
    /// push: the stack stays exactly one deep, so UIKit's back button never
    /// appears and the folder list never slides away.
    ///
    /// The list's half of opening a folder, and called only as
    /// `shell.openList`: `PaneShell.open` then puts the new list in front
    /// and lays the panes out, which dresses its bar.
    private func openMailbox(_ mailbox: Mailbox) {
        // The list going away may still be searching. Nothing will draw
        // what it finds, and until it stops it is ahead of the new folder's
        // later pages and previews.
        list.stopSearching()
        // The view button and "< Mailboxes" go across to the new list.
        list.itemsBeforeCalendar = []
        list = MessageListViewController(repository: repository, mailbox: mailbox)
        bindList()
        listNav.setViewControllers([list], animated: false)
        detail.showEmpty()
    }
}

// MARK: - The watch

/// What `MailWatch` asks of the screens: the list in front of him if it is
/// the Inbox's, the folder pane's count, and where what it finds goes.
extension RootViewController: MailWatchTarget {

    var watchedInbox: (mailboxID: String, letters: [String])? {
        guard list.shownMailbox.role == .inbox, let letters = list.lettersToWatch else { return nil }
        return (list.mailboxID, letters)
    }

    var shownInboxUnread: Int? { mailboxList.inboxUnread }

    func found(_ news: FolderNews, in mailboxID: String) -> NewsTaken {
        // Another folder opened while the check was out: the news is for a
        // list that has gone, and the counts still have to follow it.
        guard list.shownMailbox.role == .inbox, list.mailboxID == mailboxID else { return .notTaken }
        return list.newsFound(news)
    }

    /// A sweep he did not ask for: a failure leaves the counts as they were,
    /// with no alert over the letter he is reading. The line under the list
    /// already says when the connection has gone.
    func countsChanged() {
        refreshMailboxes(quietly: true)
    }

    func checked(_ outcome: MailWatch.Outcome) {
        list.checked(outcome)
        if case .failed = outcome {
            lastCheckFailed = true
            return
        }
        // The first check to reach the server after one that could not:
        // the connection has come back, and what waits on the iPad, the
        // Outbox first, goes over it now, as Mail's Outbox does, rather than
        // at the next page he opens or the next return to the app. Only
        // then: a pass after every check would try a letter the server will
        // not take for its own reasons every half minute.
        guard lastCheckFailed else { return }
        lastCheckFailed = false
        LocalDrafts.shared.uploadWaiting(to: repository)
    }
}

#endif
