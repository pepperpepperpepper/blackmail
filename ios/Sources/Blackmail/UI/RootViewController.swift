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
/// It moves as a push and a pop do, in pictures (`PaneMotion`, B-077).
final class RootViewController: UIViewController {

    /// Not private: a `mailto:` link opened from outside the app writes
    /// its letter on the same repository (`AppDelegate.application(_:open:)`).
    let repository: MailRepository

    private let mailboxNav: UINavigationController
    private let listNav: UINavigationController
    /// The reading pane's. Kept, for its bar, whose bottom is where the
    /// bars end in the pictures the view button's switch slides.
    private let detailNav: UINavigationController
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
    /// The panes moving, as Mail's do: the view button's switch (B-066),
    /// and "< Mailboxes" and a folder tap in two panes (B-077). Nothing
    /// else moves them.
    private let motion = PaneMotion()
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
    /// The open folder's row, held for VoiceOver after "< Mailboxes"
    /// (B-079). See `FoldersVoiceOver`.
    private var foldersVoiceOver = FoldersVoiceOver()
    /// VoiceOver asked where it is while that row is held, and the timer
    /// that asks (the fourth change). See `FocusWatch`.
    private var foldersWatch = FocusWatch()
    private var foldersTicks: Timer?

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

    /// Mail's Undo (B-157): each Trash or Move the server has taken, from a
    /// drag, Edit mode or the reading pane, one step (`UndoableMove`), and
    /// each Flag or Unflag from a drag, More or the pane (`UndoableFlag`).
    /// The screens' undo manager, on the responder chain, where a shake of
    /// the iPad (with Shake to Undo on, as it comes), iPadOS's three-finger
    /// gestures and Command-Z look for it; the text fields' typing goes on
    /// it as well, as on any app's. In memory alone: a relaunch, or a new
    /// password, which builds the screens again, starts with nothing to
    /// undo. Fifty steps, steps of typing among them: as many as is safe,
    /// since each letter is made sure of where it went before it is moved
    /// back (`MailRepository.moveBack`), and found by its Gmail id.
    private let undos: UndoManager = {
        let undos = UndoManager()
        undos.levelsOfUndo = 50
        return undos
    }()

    override var undoManager: UndoManager? { undos }

    /// The responder a shake and the three-finger gestures are sent to, when
    /// no text field has the keyboard: they look for the undo manager from
    /// the first responder. See `takeUndo`.
    override var canBecomeFirstResponder: Bool { true }

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
        self.detailNav = UINavigationController(rootViewController: detail)
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

        detailNav.setNavigationBarHidden(false, animated: false)

        // No pull on the list while the panes move (B-103): the list open
        // at the start and at the end of each motion.
        motion.onMoving = { [weak self] moving in self?.list.panesMoving = moving }

        for child in [mailboxNav, listNav, detailNav] {
            addChild(child)
            child.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child.view)
            child.didMove(toParent: self)
        }
        // The folders and the list laid out as at the iPad's default text
        // size, whatever it is set to (B-071), as D-007 has the type. Their
        // words are in fixed fonts, but UIKit sizes some of what it draws
        // beside them by the text size. A folder's icon and its room grew
        // at the larger sizes and moved the names right; at the
        // accessibility sizes the icons shrank to the name's height and
        // each name began where its own icon ended, so a block's names were
        // no longer on one line. A fixed symbol size and a fixed room did
        // not hold there: that layout is UIKit's own. In Edit mode the
        // circle he ticks grew from 26 pt to 49 at the largest size and
        // pushed every row's words 25 pt right; it takes no size at all.
        // Not the reading pane: once its symbols had a size of their own
        // (`Theme.symbolSize`) nothing in it moved with the text size. Nor
        // what these panes put up, since a sheet or an alert is presented
        // over the whole screen and follows the iPad's setting as before.
        for nav in [mailboxNav, listNav] {
            setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .large),
                                       forChild: nav)
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
        // Letters shared with no connection since the app was last open,
        // into the Outbox before the launch's first pass (B-153).
        takeWaitingShares()
        // Where VoiceOver goes after "< Mailboxes", for the folder's row it
        // was sent to (B-079).
        NotificationCenter.default.addObserver(self, selector: #selector(voiceOverMoved(_:)),
                                               name: UIAccessibility.elementFocusedNotification,
                                               object: nil)
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
        //
        // Then the folder that is open is highlighted: the Inbox, unless he
        // has tapped another while the folders were coming. LOGIN and LIST
        // took from half a second to six on the iPad, and a folder tapped in
        // that time lost its highlight to the Inbox here while its letters
        // stayed in the list (B-086). `list` is read after the wait, so it is
        // the list open now.
        Task { @MainActor in
            await mailboxList.showFolders()
            mailboxList.select(mailboxID: list.mailboxID)
        }
        // Asked for now, sent once the Inbox's first page has come: the
        // folder pane holds its sweeps until it is told to let them go. If
        // the page could not be fetched the counts are not asked for at
        // all, since they would connect again straight after the connect
        // that failed, and send a refused password a second time.
        mailboxList.refreshCounts()
        list.onFirstLoadFinished = { [weak self] came in
            self?.mailboxList.releaseSweeps(firstPageCame: came)
            // The page's own alert, if it could not be fetched, is up by
            // now, or held for his finger to let go of the list: either
            // way the warning waits for it, until a check of the watch
            // finds nothing over the mail and no finger on the list (B-137).
            self?.warnOfExpiryIfDue()
            // Once the first page has been tried, so a check never goes
            // beside it: the first is half a minute on, after the counts.
            // Started whether or not the page came, so that with no
            // connection at launch the counts come of themselves once there
            // is one. It sends no password that has been refused.
            self?.firstPageTried = true
            // The address book filled from his Sent Mail, once for this
            // account, in the background line behind the counts and ahead
            // of the watch's first check (B-155). Nothing waits for it, and
            // with no connection up it sends nothing, to be tried again at
            // the next launch.
            if let repository = self?.repository {
                Task { _ = await repository.fillBookFromSent() }
            }
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
        takeUndo()
        guard let notice else { return }
        self.notice = nil
        ErrorPresenter.say(notice, on: self)
    }

    // MARK: - Before the app stops opening

    /// The warning that the app will stop opening, in its last thirty days
    /// and once a day (`ExpiryWarning`, D-004, B-137), put up only when
    /// nothing is over the mail: not over a letter he is writing, Settings,
    /// another alert or any sheet; not while his finger is on the list, it
    /// is still moving, or a page's alert waits for the finger to let go
    /// (B-103); not while a letter is being printed, nor while a draft he
    /// tapped in Drafts or a file he tapped in the pane is on its way, whose
    /// composer or preview UIKit would refuse with the warning up; and not
    /// while the app is in the background, where nobody would see it. Asked
    /// once the launch's first page has been tried, and at every check of
    /// the watch, half a minute apart while the app is in front: so it
    /// comes about half a minute after he is back on a new day, and within
    /// half a minute of a letter's sheet going, an alert's OK, the list
    /// coming to rest or what he tapped opening. The day is taken as said
    /// once the alert is up, and again when he taps OK, so a warning left
    /// up past midnight is not said again on the day he reads it.
    private func warnOfExpiryIfDue() {
        guard view.window != nil, presentedViewController == nil,
              UIApplication.shared.applicationState != .background,
              !list.isInHand, !list.isOpeningDraft,
              !detail.isPrinting, !detail.isOpeningFile else { return }
        let warning = ExpiryWarning.app
        let now = Date()
        guard let words = warning.words(at: now) else { return }
        ErrorPresenter.warn(words, over: self, shown: {
            warning.shown(at: now)
            Diagnostics.log(.note, "EXPIRY-WARNING shown")
        }, dismissed: {
            warning.shown(at: Date())
        })
    }

    // MARK: - Mail's Undo (B-157)

    /// The screens take the first responder, so that a shake or three
    /// fingers find the undo manager (`undos`): when they appear, as a step
    /// is added, as the search field lets the keyboard go, as a sheet over
    /// them closes, and as the app comes back. Not while a sheet is over
    /// them, whose own fields answer for themselves, nor while the search
    /// field has the keyboard, which it would lose.
    ///
    /// UIKit asks the first responder's undo manager at a shake; with no
    /// first responder, as after the search field has let the keyboard go,
    /// there is none to ask. Apple's own sample code for shake to undo makes
    /// its controller the first responder from `viewDidAppear` for this.
    /// Not seen on the iPad: whether UIKit gives the first responder back
    /// by itself as a sheet closes.
    private func takeUndo() {
        guard !isFirstResponder, view.window != nil, presentedViewController == nil,
              !list.isTyping else { return }
        becomeFirstResponder()
    }

    /// A Trash, a Move, a Flag or an Unflag the server has taken, one step
    /// of Undo, under Mail's name for it, "Trash", "Move" or "Flag": "Undo
    /// Trash" in UIKit's alert at a shake. `letters`, the list's letters it
    /// was taken from, weakly: gone with that list when another folder
    /// replaces it.
    ///
    /// By a selector and the step in a box (`UndoStep`), where the step's
    /// own closure would be called outside the main actor as far as the
    /// compiler is told.
    private func canUndo(_ step: Undoable, from letters: ListLetters?) {
        undos.registerUndo(withTarget: self, selector: #selector(undoStep(_:)),
                           object: UndoStep(step, from: letters))
        undos.setActionName(step.actionName)
        takeUndo()
    }

    /// Undo tapped in UIKit's alert, or three fingers swiped left.
    @objc private func undoStep(_ box: Any?) {
        guard let box = box as? UndoStep else { return }
        undo(box.step, into: box.letters)
    }

    /// Undo of the step on top, whichever it is.
    private func undo(_ step: Undoable, into letters: ListLetters?) {
        switch step {
        case .move(let move): undo(move, into: letters)
        case .flag(let flag): undo(flag, into: letters)
        }
    }

    /// Undo: the letters moved back where they were, a letter at a time,
    /// "Moving…" on the line under the list meanwhile, and their rows back
    /// where they stood if the list they were taken from is still on the
    /// screen (`UndoMoves`). Rows that list no longer holds, fetched afresh
    /// since, come with the list fetched afresh where he is, if it is their
    /// folder's. A failure is said as a Move's, and what was not moved back
    /// is one step of Undo again; a letter no longer where it went is left
    /// as it is, and nothing is said. No Redo: Mail's is not known, and
    /// nothing is offered after an Undo.
    private func undo(_ step: UndoableMove, into letters: ListLetters?) {
        let done = list.working(StatusLine.moving)
        Task { @MainActor [weak self] in
            guard let self else { return done() }
            let outcome = await UndoMoves.run(step, repository: self.repository, list: letters,
                                              requestSweep: { [weak self] in
                                                  self?.refreshMailboxes()
                                              })
            done()
            let folders = Set(step.letters.filter { outcome.unplaced.contains($0.row.id) }
                                  .map(\.row.mailboxID))
            if folders.contains(self.list.mailboxID) {
                await self.list.reload(keepingPlace: true, quietly: true)
            }
            if let left = outcome.left { self.canUndo(.move(left), from: letters) }
            if let refusal = outcome.refusal { ErrorPresenter.show(reaching: refusal, on: self) }
        }
    }

    /// Undo of a Flag or an Unflag: the other set back on the letters it
    /// changed, the rows' flag at once (`UndoMoves`). A failure is said as
    /// a Flag's is, and what was not put back is one step of Undo again.
    private func undo(_ step: UndoableFlag, into letters: ListLetters?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await UndoMoves.run(step, repository: self.repository, list: letters,
                                              requestSweep: { [weak self] in
                                                  self?.refreshMailboxes()
                                              })
            if let left = outcome.left { self.canUndo(.flag(left), from: letters) }
            if let refusal = outcome.refusal { ErrorPresenter.show(reaching: refusal, on: self) }
        }
    }

    /// A sheet over the screens has closed: the first responder back, for
    /// Undo. Every sheet and alert the screens put up is put up over them,
    /// as the list and the pane do not define where theirs go.
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag) { [weak self] in
            completion?()
            self?.takeUndo()
        }
    }

    /// The search field, or a field of a sheet, has let the keyboard go:
    /// the first responder back, once whatever takes it next has, so that
    /// a field the keyboard moves on to keeps it.
    @objc private func fieldLetGo(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in self?.takeUndo() }
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
        centre.addObserver(self, selector: #selector(lookingAway),
                           name: UIApplication.willResignActiveNotification, object: nil)
        for name in [UITextField.textDidEndEditingNotification,
                     UITextView.textDidEndEditingNotification] {
            centre.addObserver(self, selector: #selector(fieldLetGo(_:)), name: name, object: nil)
        }
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
                // Letters shared with no connection while the app was away,
                // into the Outbox before the pass below (B-153).
                self.takeWaitingShares()
                Task { @MainActor in
                    await repository.warmUp()
                    LocalDrafts.shared.uploadWaiting(to: repository)
                }
                self.returnedFromAway()
                self.takeUndo()
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

    /// The letters the share extension could not send, from the shared
    /// Keychain group into the Outbox (`LocalDrafts.takeShares`, B-153):
    /// they go by the pass that follows, as a letter his own Send left
    /// there does. Nothing in a build without the extension.
    private func takeWaitingShares() {
        guard let mirror = ShareMirror.app else { return }
        LocalDrafts.shared.takeShares(from: mirror)
    }

    /// The letters kept on the iPad go as he leaves the app, large ones as
    /// well, inside background time: nothing he taps is waiting for the
    /// connection then (`LocalDrafts.uploadWaiting`). A large draft goes
    /// only then; a large letter in the Outbox goes at his Refresh too
    /// (B-072). Asked for here, on the main thread as the notification is
    /// posted, so the time is asked for before iOS can suspend the app.
    /// With a pass on its way, his Refresh's taking a video perhaps, the
    /// time is asked for here all the same, and the leaving pass goes once
    /// that one has ended (`LocalDrafts.afterThisPass`, B-072).
    ///
    /// The tries on their way are taken back first, and these are not
    /// counted: iOS may end the app before they are done, which says
    /// nothing about the letters (B-057, `LocalDrafts.wentToBackground`).
    @objc private func leavingTheApp() {
        LocalDrafts.shared.wentToBackground()
        LocalDrafts.shared.uploadWaiting(to: repository, for: .leaving)
    }

    /// Control Centre pulled down, the Home gesture, a call: a change still
    /// moving ends now, where it was going, and is not left on its way for
    /// him to come back to. Its pictures can go blank while the app is not
    /// in front, and the screen under them is final already (B-066). On
    /// the main thread as the notification is posted, before iOS takes
    /// the picture of the app it shows in the app switcher.
    @objc private func lookingAway() {
        motion.finish()
    }

    /// B-003: after a while away, back to the Inbox, at the top. See
    /// `Sitting`, which decides. The warning before the app stops opening
    /// is not a sheet (`OverTheMail.holdsTheReturn`): left up overnight,
    /// the Inbox comes back under it, unless an alert waits behind it, as
    /// one for the list the Inbox would replace can.
    @MainActor
    private func returnedFromAway() {
        guard let away = wentAwayAt else { return }
        wentAwayAt = nil
        switch Sitting.onReturn(after: Date().timeIntervalSince(away),
                                showingInbox: list.shownMailbox.role == .inbox,
                                sheetOpen: ErrorPresenter.over(self).holdsTheReturn) {
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
        // A change still moving ends first: its pictures are of the screen
        // the iPad is turning away from.
        motion.finish()
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
    /// After the view button, "< Mailboxes" and a folder tapped in two
    /// panes, and only then, the change is seen to move, as Mail's does
    /// (B-066, B-077). Pictures of the screen as it was are cut first, the
    /// panes are laid out anew beneath them exactly as they always were,
    /// and then pictures of the panes that go as they are now laid out;
    /// the pictures move as whole columns on UIKit's spring to where the
    /// panes now are, and are taken away. The rows wrap to their new
    /// widths once, at the tap, and are seen in their new places from the
    /// first frame that moves; the letter goes as it was and wraps again
    /// at the end, as WebKit has it by then. Nothing changes its look while
    /// it moves. Nothing moves up or down: the rows are a fixed height, the
    /// list keeps its scroll offset and the pictures move only sideways,
    /// so the rows he was looking at stay where his eyes are, a pane
    /// further left or right. The launch, a turn of the iPad, a return and
    /// a folder opened another way lay out with nothing moving, as before.
    ///
    /// Everything else a change does is done here at the tap and is final
    /// under the pictures: the choice kept, the bars dressed, the layout
    /// sweep run. A change still moving when anything lays the panes out
    /// again is ended first, which is only taking its pictures away, and
    /// the new layout is then made at once, so no tap can leave the panes
    /// half one way.
    ///
    /// Hidden, never zero wide: a view with children and no width is the
    /// B-027 shape `LayoutAudit` hunts. The sweep runs before the pictures
    /// go over the panes, so it sees the real ones only.
    private func arrange(_ panes: PaneArrangement, switchedFrom from: PaneArrangement? = nil) {
        let wasMoving = motion.finish()
        let cut = wasMoving ? nil : from.flatMap { pictures(from: $0, to: panes) }
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
        if let cut { motion.play(cut) }
    }

    /// The pictures of the screen as it is, cut before anything is laid out
    /// anew (B-066, B-077). Nil when nothing moves, or when the screen is
    /// not as the arrangement before the change has it, and the change is
    /// then made at once, as it always was.
    private func pictures(from: PaneArrangement, to panes: PaneArrangement) -> PaneMotion.Cut? {
        let emptyLabel = detail.emptyLabel
        guard let move = PaneMove.switching(from: from, to: panes, screenWidth: screenWidth,
                                            reading: emptyLabel == nil ? .words : .nothing,
                                            crossFading: PaneMotion.crossFading) else {
            return nil
        }
        guard arranged == from else {
            Diagnostics.log(.note, "pane motion: not as laid out; switched at once")
            return nil
        }
        // Before anything is touched: a list, the folders or the letter in
        // the pictures that is bouncing past an end is left to spring back,
        // and the change is made at once. Its picture would be of its last
        // frame drawn, past the end, and its rows would jump to the end as
        // the pictures go. Hidden ones too: one hidden by a change made at
        // once a moment before still springs back while hidden.
        let scrolls = move.looked.compactMap { scrolling(in: $0) }
        guard !scrolls.contains(where: { PaneMotion.isBouncing($0) }) else {
            Diagnostics.log(.note, "pane motion: bouncing; switched at once")
            return nil
        }
        // One still coasting from a flick, inside its ends, is stopped where
        // it is before the pictures are cut, or its rows would jump, as the
        // pictures go, to wherever the coasting had taken them.
        for scroll in scrolls { PaneMotion.holdStill(scroll) }
        let stage = PaneMotion.Stage(
            root: view, mailboxes: mailboxNav.view, list: listNav.view, message: detailNav.view,
            corner: from.leftColumn == .list ? listViewButton : mailboxesViewButton,
            mailboxesButton: mailboxesViewButton, listButton: listViewButton,
            letterBar: detailNav.navigationBar, placeholder: emptyLabel)
        return motion.cut(move, stage: stage)
    }

    /// What scrolls in a pane's picture: the Mailboxes, the list, or the
    /// letter, which has none when the pane is empty.
    private func scrolling(in pane: PaneMove.Pane) -> UIScrollView? {
        switch pane {
        case .mailboxes: return mailboxList.tableView
        case .list: return list.tableView
        case .message: return detail.letterScroll
        }
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
        // is in the same corner, and says the other thing. No row held for
        // VoiceOver after a move takes it from there (B-079).
        letGoOfFoldersRow()
        list.letGoOfVoiceOver()
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
        // With VoiceOver on, the open folder's row shown whole, if part of
        // it is under a bar, while the folders are still hidden: VoiceOver
        // put on a row it cannot see whole scrolls it to the middle itself
        // (B-079). The motion's pictures are cut after this.
        mailboxList.tableView.showWhole(forVoiceOver: mailboxList.tableView.indexPathForSelectedRow)
        shell.back()
        // As UIKit's pop does, VoiceOver goes back to the row that pushed:
        // the open folder's, just highlighted (B-079). The row is held for
        // it: once there, VoiceOver left it by itself for the reading pane,
        // once in a launch, and is put back. Not from the reading pane if
        // the row is the folders' last, a swipe from which goes there.
        let place = mailboxList.tableView.voiceOverPlace(orFirstRow: false)
        UIAccessibility.post(notification: .screenChanged, argument: place)
        foldersVoiceOver.send(toRow: place is UITableViewCell,
                              last: mailboxList.tableView.voiceOverIsLast(
                                  mailboxList.tableView.indexPathForSelectedRow),
                              running: UIAccessibility.isVoiceOverRunning, at: Date())
        watchFoldersRow()
    }

    /// VoiceOver asked where it is every tenth of a second while the
    /// folder's row is held (`FocusWatch`): from now, from nothing seen. No
    /// ticks with nothing held.
    private func watchFoldersRow() {
        foldersTicks?.invalidate()
        foldersTicks = foldersWatch.start(holding: foldersVoiceOver.holding(at: Date()))
            ? Timer.voiceOverTicks(self, #selector(foldersTick)) : nil
    }

    /// The folder's row let go, and no more ticks: a folder tapped, the
    /// panes switched, the folders or the row out of sight.
    private func letGoOfFoldersRow() {
        foldersVoiceOver.letGo()
        stopWatchingFoldersRow()
    }

    private func stopWatchingFoldersRow() {
        foldersWatch.stop()
        foldersTicks?.invalidate()
        foldersTicks = nil
    }

    /// VoiceOver has moved. While the folder's row is held, VoiceOver is
    /// asked where it is on the next turn, after its own move. Not from
    /// the element this names, which on the iPad the list could not find
    /// (`FocusWatch`).
    @objc private func voiceOverMoved(_ note: Notification) {
        guard foldersVoiceOver.holding(at: Date()) else { return }
        DispatchQueue.main.async { [weak self] in self?.lookAtFoldersRow(onlyIfMoved: false) }
    }

    /// A tick while the folder's row is held.
    @objc private func foldersTick() {
        lookAtFoldersRow(onlyIfMoved: true)
    }

    /// Where VoiceOver is, from VoiceOver itself, told apart for the
    /// folder's row. At a tick, `onlyIfMoved`, only when it is on another
    /// object than the one last seen. If it has been on the open folder's
    /// row since "< Mailboxes", and has gone by itself to the view button
    /// in the corner, or to the reading pane from any folder but the last,
    /// it is put back on the row, once (`FoldersVoiceOver`). The ticks stop
    /// with nothing held, at the bound, and once the row is put back or let
    /// go. The folders out of sight, or the row with them, the row is let
    /// go. VoiceOver on nothing is passed over, and the row stays held.
    private func lookAtFoldersRow(onlyIfMoved: Bool) {
        let now = Date()
        guard foldersWatch.goesOn(holding: UIAccessibility.isVoiceOverRunning
                                      && foldersVoiceOver.holding(at: now)) else {
            stopWatchingFoldersRow()
            return
        }
        let place = mailboxList.tableView.voiceOverPlace(orFirstRow: false)
        guard !mailboxNav.view.isHidden, place is UITableViewCell else {
            letGoOfFoldersRow()
            return
        }
        guard let element = UIAccessibility.focusedElement(using: .notificationVoiceOver) else { return }
        let changed = foldersWatch.changed(to: element as AnyObject)
        guard changed || !onlyIfMoved else { return }
        let put = foldersVoiceOver.moved(to: foldersLanding(on: element), at: now)
        if !foldersVoiceOver.holding(at: now) { stopWatchingFoldersRow() }
        guard put else { return }
        mailboxList.tableView.showWhole(forVoiceOver: mailboxList.tableView.indexPathForSelectedRow)
        UIAccessibility.post(notification: .layoutChanged, argument: place)
    }

    /// What VoiceOver is on, `element`, as the folders' hold sees it: the
    /// open folder's row; the view button in the corner; the reading pane;
    /// else anything else. The reading pane by the view the element is in,
    /// or by where it is for one in no view, as WebKit's in the letter's
    /// text (`voiceOverHolds`).
    private func foldersLanding(on element: Any?) -> FoldersVoiceOver.Landing {
        guard let element else { return .other }
        let folders: UITableView = mailboxList.tableView
        if let row = folders.voiceOverRow(of: element) {
            return row == folders.indexPathForSelectedRow ? .sentRow : .other
        }
        if mailboxesViewButton.voiceOverHolds(element) { return .corner }
        return detailNav.view.voiceOverHolds(element) ? .pane : .other
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
        shell.layOut = { [weak self] panes, from in self?.arrange(panes, switchedFrom: from) }
        mailboxList.onSelectMailbox = { [weak self] mailbox in
            guard let self else { return }
            // A folder tapped: the folders' row is no longer held (B-079).
            self.letGoOfFoldersRow()
            // The open folder's list put back in front in two panes: its
            // highlighted row shown whole while the list is still hidden,
            // with VoiceOver on, before the panes move (B-079).
            if self.shell.arrangement.panes == .two,
               PaneArrangement.isShowing(mailbox, in: self.list.shownMailbox) {
                self.list.showHighlightedRowWhole()
            }
            self.shell.tapped(mailbox, showing: self.list.shownMailbox)
            // In two panes the folders VoiceOver was reading have gone
            // behind the list, as after a push. VoiceOver goes to the list:
            // the row of the letter being read, else the first row, else,
            // for a folder whose rows have not come, the list itself
            // (B-079). The list holds the row for it, before it is there and
            // after: in case its rows are drawn again, as a folder's fresh
            // page is drawn over its kept one, and in case VoiceOver leaves
            // it by itself. `self.list` is read again now, since a folder
            // opened has a new one.
            if self.shell.arrangement.panes == .two {
                UIAccessibility.post(notification: .screenChanged,
                                     argument: self.list.placeVoiceOver())
            }
        }
        // Delete, Move and Flag from the reading pane, and the read marks
        // of its Flag button's sheet (B-106), edit the list on screen in
        // place, and ask for the folder counts only when one may have
        // changed; see `PaneActions`. They used to reload the whole
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
            // What the server took is a step of Mail's Undo (B-157), with
            // the list it was taken from: a Delete or a Move as the list's
            // copy of the letter was at the tap, which its row comes back
            // as; a Flag on the letter.
            let letters = self.list.letters
            let refused = await PaneActions.refusal(
                running: action, on: letter, inFolderWithRole: folders.role(of: letter.mailboxID),
                list: letters, repository: self.repository,
                requestSweep: { [weak self] in self?.refreshMailboxes() },
                landed: { [weak self, weak letters] landing, before in
                    guard let landing, let step = UndoableMove.after(
                        action, took: [before], landings: [before.id: landing],
                        role: { folders.role(of: $0) }) else { return }
                    self?.canUndo(.move(step), from: letters)
                })
            if refused == nil, let step = UndoableFlag.after(action, took: [letter]) {
                self.canUndo(.flag(step), from: letters)
            }
            return refused
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
        // The Flag button's sheet offers Mark as Unread or Mark as Read by
        // the dot on the list's row (B-106), which Edit mode's Mark and a
        // refused read mark change without the pane. `self.list` is read
        // at the tap, since a folder opened has a new one.
        detail.dotOnList = { [weak self] letter in
            self?.list.letters.dot(on: letter)
        }
        // And Flag or Unflag by the flag on the row, which a drag's Flag
        // changes without the pane (B-156).
        detail.flagOnList = { [weak self] letter in
            self?.list.letters.flag(on: letter)
        }
        // Move to Junk and Move to Inbox from the Flag button's sheet
        // (B-106): to the folders LIST named with the `\Junk` role, Gmail's
        // Spam, and the Inbox's, never a name guessed, and by the role of
        // the letter's own folder.
        detail.foldersForJunk = { [weak self] letter in
            guard let self else { return FlagMenu.Folders() }
            let folders = [self.list.shownMailbox] + self.mailboxList.folders
            return FlagMenu.Folders(role: folders.role(of: letter.mailboxID),
                                    junk: self.mailboxList.mailbox(for: .junk),
                                    inbox: self.mailboxList.mailbox(for: .inbox))
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
        list.onSelectThread = { [weak self] thread, completing in
            self?.detail.show(thread: thread, completing: completing)
        }
        // Letters that came into the conversation in the reading pane go
        // in at the bottom of its stack (B-074).
        list.onRegrouped = { [weak self] in
            guard let self else { return }
            self.detail.takeArrivals(from: self.list.conversations)
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
        // Quietly after his Refresh's page did not come: the page's alert
        // says what failed, and in three panes a second from the Mailboxes
        // came up under a pull's finger (`RefreshTap.run`, B-103).
        list.onRefreshRequested = { [weak self] quietly in
            self?.refreshMailboxes(quietly: quietly)
        }
        // His Refresh's pass over the Outbox waits for the counts it asked
        // for (`RefreshTap`, B-072).
        list.countsCame = { [weak self] in
            await self?.mailboxList.countsSwept()
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
        // A Delete or Move the server took from Edit mode or a drag, or a
        // Flag from a drag or More: a step of Mail's Undo (B-157).
        list.onUndoable = { [weak self] step, letters in
            self?.canUndo(step, from: letters)
        }
        // More's Reply, Reply All and Forward on a row: made by the pane, as
        // its Reply button's are (B-156).
        list.onAnswer = { [weak self] letter, all, forward, row in
            self?.detail.answer(letter, all: all, forward: forward, over: row)
        }
        // The row of the letter in the reading pane highlighted again at
        // Edit mode's Cancel and on a day's list (B-133).
        list.lettersInPane = { [weak self] in
            self?.detail.lettersShown ?? []
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
    /// the watch's, and his Refresh's after a page that did not come, which
    /// put up no alert if they fail.
    private func refreshMailboxes(quietly: Bool = false) {
        mailboxList.select(mailboxID: list.mailboxID)
        mailboxList.refreshCounts(quietly: quietly)
    }

    /// Swaps the list's contents, in the middle in three panes and in the
    /// left column in two. Deliberately `setViewControllers` rather than a
    /// push: the stack stays exactly one deep, so UIKit's back button never
    /// appears and UIKit slides nothing. In two panes the container's
    /// pictures slide as a push would (B-077).
    ///
    /// The list's half of opening a folder, and called only as
    /// `shell.openList`: `PaneShell.open` then puts the new list in front
    /// and lays the panes out, which dresses its bar.
    private func openMailbox(_ mailbox: Mailbox) {
        // The list going away may still be searching. Nothing will draw
        // what it finds, and until it stops it is ahead of the new folder's
        // later pages and previews.
        list.stopSearching()
        // Nor is its pull's spinner left turning (B-103).
        list.endPull()
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

    /// A Delete or Move whose answer was lost, its letter found gone on a
    /// later connection (B-151): the row goes from the list in front, with
    /// no alert, now if he is where the watch's news goes on and when he is
    /// back at the top otherwise; the pane lets go of the letter if it is
    /// the one it opened; and the counts are swept quietly, as above.
    func movedAfterAll(_ letters: [MovedAfterAll]) {
        let gone = list.movedAfterAll(letters, requestSweep: { [weak self] in
            self?.refreshMailboxes(quietly: true)
        })
        detail.clearIfOpened(any: gone)
    }

    func checked(_ outcome: MailWatch.Outcome) {
        list.checked(outcome)
        // Reached or not: the warning is about the app, not the mail.
        warnOfExpiryIfDue()
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

/// One step of Undo as the undo manager holds it (B-157): the step, and
/// the list's letters it was taken from, weakly, gone with that list.
private final class UndoStep: NSObject {
    let step: Undoable
    weak var letters: ListLetters?

    init(_ step: Undoable, from letters: ListLetters?) {
        self.step = step
        self.letters = letters
    }
}

#endif
