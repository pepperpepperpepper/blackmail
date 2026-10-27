// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit
import WebKit
import QuickLook
import Photos
import UniformTypeIdentifiers

/// The right column. Never navigates — it only ever swaps content, so nothing
/// in it moves between one message and the next.
///
/// The toolbar is the heart of the product: Flag, Move, Delete, Reply, Compose,
/// in that order, in that place, always. Confirmed against the reference
/// pixels. It does not change with the message, the folder, the orientation, or
/// whether anything is selected — when there is no message the buttons are
/// disabled, not removed, because a control that vanishes is a control you have
/// to re-find.
final class MessageDetailViewController: UIViewController, WKNavigationDelegate,
                                          WKScriptMessageHandler {

    /// Runs a Delete, Move, Flag or read mark and edits the list beside the
    /// pane to match (`PaneActions`). Returns nil once the server has taken
    /// it, and why not if it has not, for the alert to say.
    var perform: ((PaneAction, MessageSummary) async -> MailError?)?
    /// A letter opened inside a conversation, to be marked read the way a
    /// tap on its row marks it.
    var onLetterOpened: ((MessageSummary) -> Void)?
    /// A letter opened from a row kept on the iPad that the server says is
    /// another letter now (D-016): the pane has emptied, and the list is to
    /// take the row off (`PaneActions.notTheKeptLetter`).
    var onNotTheKeptLetter: ((MessageSummary) -> Void)?
    /// What Delete asks before it goes, nil when it asks nothing: a letter
    /// in Trash, which Delete erases (`EraseQuestion`, B-062). From the
    /// container, which knows every folder's role.
    var questionBeforeDeleting: ((MessageSummary) -> EraseQuestion?)?
    /// The dot on the list's row for a letter the pane shows, which the
    /// Flag button's sheet offers Mark as Unread or Mark as Read by
    /// (B-106); nil where the list has no row that is the letter
    /// (`ListLetters.dot(on:)`). From the container, which holds the list.
    var dotOnList: ((MessageSummary) -> FlagMenu.Dot?)?
    /// The role of the letter's own folder and the folders LIST named with
    /// the `\Junk` role and the Inbox's, for the Flag button's Move to Junk
    /// and Move to Inbox
    /// (`FlagMenu.Folders`). From the container, which lists the folders;
    /// nil, or none listed, and neither item is offered.
    var foldersForJunk: ((MessageSummary) -> FlagMenu.Folders)?
    /// The flag on the list's row for a letter the pane shows, which the
    /// sheet offers Flag or Unflag by, as the dot for the read item: a
    /// drag's Flag on the row (B-156) changes the row and not the pane.
    /// Nil where the list has no row that is the letter
    /// (`ListLetters.flag(on:)`).
    var flagOnList: ((MessageSummary) -> FlagMenu.Flag?)?
    /// Gmail's All Mail where Delete archives the letter, Mail's Archive in
    /// the Trash's place on an account whose Move Discarded Messages Into
    /// says Archive Mailbox (B-167); nil where it trashes or erases it. For
    /// an empty pane, by the list's folder. From the container, which lists
    /// the folders (`SwipeOptions.archive(fromFolderWithRole:into:)`).
    var archiveTarget: ((MessageSummary?) -> Mailbox?)?
    /// Whether Delete's button is drawn as Archive now: false as
    /// `buildToolbar` draws it, the bin (`drawDiscardButton`).
    private var discardArchives = false

    private let repository: MailRepository
    /// The letter the toolbar acts on. Delete's button is drawn again for
    /// each, an archive box where it archives (B-167).
    private var summary: MessageSummary? {
        didSet { drawDiscardButton() }
    }
    private var message: Message?
    /// The loaded letters of that conversation, by id, so the toolbar can
    /// act on whichever one he last opened.
    private var loaded: [String: Message] = [:]
    /// Which letter of the conversation the header and the toolbar are on:
    /// the newest as it opens, then the one he opened last, from the tap
    /// (`StackFocus`, B-129). None when the pane holds a single message,
    /// where `message` is the answer.
    private var stackFocus = StackFocus()
    /// The list rows of the conversation on screen, by id, so the toolbar
    /// can be pointed at whichever letter he last opened.
    private var threadSummaries: [String: MessageSummary] = [:]
    /// The same rows in the stack's order, the oldest first, as they were
    /// when the stack was drawn or a letter came into it: what the list's
    /// conversation is matched against for letters to put at the bottom
    /// (`takeArrivals`). Empty when the pane shows no conversation.
    private var stackLetters: [MessageSummary] = []
    /// His own letters from Sent Mail in the conversation on screen
    /// (B-104). Apart from everything above on purpose: none of them is
    /// ever in `threadSummaries`, `stackLetters` or `loaded`, or the letter
    /// the header, the toolbar or the list's read marks act on. Read only;
    /// the pane holds them while it shows the conversation, and no longer.
    private var related = PaneRelated()
    /// The file QuickLook is currently showing. Held because
    /// `QLPreviewController.dataSource` is a WEAK reference and asks for its
    /// item after presentation, by which point a local would be gone.
    ///
    /// The only copy of an opened file on disk (B-063): removed as the next
    /// file he opens is written, and at launch. Each used to stay in
    /// `tmp/Attachments` until the next launch, which iOS can put off for
    /// days, a scan or a PDF for every tap. Not removed as the preview
    /// closes: Print reads the file after its panel has closed, and a copy
    /// taken from under it then could print blank.
    private var previewURL: URL?
    /// The one print of a letter (B-110), from Print in the Reply sheet
    /// until its panel has closed or it has ended without one. Another
    /// Print replaces it once its panel is up, when it holds nothing of
    /// WebKit's and no bytes; while it is made ready, Print is greyed.
    private var printing: LetterPrint?
    /// The files and pictures tapped whose downloads have not yet ended,
    /// each counted from the tap until its preview is put up, its failure
    /// said or it is let go (`openAttachment`).
    private var filesOpening = 0
    /// Which file or picture tapped opens as it lands: the last one tapped,
    /// while no other letter of the conversation has been opened by its
    /// line since, and which are coming (`FileTaps`, B-141).
    private var fileTaps = FileTaps()
    /// Where the finger was held on a picture, in the web view, for the
    /// share sheet its menu's Share puts up there (B-150).
    private var pictureSpot = CGRect.zero
    /// Markup and Reply (B-171): where the picture's marking up stands, the
    /// copy of what he drew among it and the Quick Look it is drawn in
    /// (`MarkupReply`), and the letter and the picture of it being marked
    /// up, the letter the reply answers. The last picture opened for
    /// Markup, until its reply has opened or its copy has been let go
    /// (`replyWithMarkup`).
    private var markup = MarkupReply()
    private var marking: (letter: Message, picture: Attachment)?

    private let header = MessageHeaderView()
    private let webView: WKWebView
    /// Over the web view, in the pane's own colour, from a tap on another
    /// letter until WebKit has painted what goes in its place, half a
    /// second at most (`PaneCover`, B-149): no frame of the letter he left
    /// under the new letter's header.
    private let cover = UIView()
    private var paneCover = PaneCover()
    /// Whether WebKit tells the pane what it has painted (`PaneCover`):
    /// asked for by its private setter, where the web view has it.
    private let painting: Bool
    private let placeholder = UILabel()
    private var actionItems: [Theme.ToolbarAction: UIBarButtonItem] = [:]
    /// Answers the `cid:` images inside whatever message is on screen.
    private let inlineImages = InlineImageLoader()
    /// WebKit's list that blocks every request to the web, on the web view
    /// while Block All Remote Content holds back the pictures of what the
    /// pane shows and none of its letters has been loaded (B-168).
    private let remoteList: RemoteBlockList
    /// The letters of what the pane shows built held back, and those whose
    /// pictures from the web "Load All Images" has loaded; none as it shows
    /// something else (`RemotePictures`, B-168).
    private var remote = RemotePictures()
    /// The body fetches for what the pane shows, called off when it shows
    /// something else. See `PaneLoads`.
    private let loads = PaneLoads()
    /// What the loader answers from (`prepareInlineImages`): in a stack,
    /// the pictures of every body gone into it since the conversation was
    /// shown (B-170).
    private var pictureMap: [String: PanePage.Picture] = [:]
    /// The Delete, the Flags and the read marks on their way to the server,
    /// which decide what the next tap on any of them does. See `PaneWrites`.
    private var writes = PaneWrites()
    /// The letter the pane marked unread itself, from the Flag button's
    /// sheet (B-106), by its id; nil when it marked none, or the pane has
    /// shown another letter since, or his tap on the letter's line in the
    /// stack has marked it read again. The sheet goes by the dot on the
    /// list's row (`dotOnList`), and by this only where the list has no
    /// row that is the letter, a hit after its search has ended: any
    /// other letter the pane shows is then read, since opening it marked
    /// it read. Never by `summary.isRead`, which the pane was handed
    /// before the tap that opened the letter marked it read.
    private var markedUnreadHere: String?
    /// What the web view holds, which emptying the pane has to clear and
    /// which is drawn again if WebKit loses it, and the conversation's
    /// bodies waiting for its document to load. Nothing until the first
    /// letter, so launch does not start WebKit's content process for an
    /// empty page. See `PaneDocument`.
    private var document = PaneDocument()
    /// The text size changed while the pane could not be seen, or the app
    /// was not in front: the letter is drawn at the new size once they are
    /// (`restyleOwed`, B-166).
    private var restyleOwed = false

    init(repository: MailRepository) {
        self.repository = repository

        let config = WKWebViewConfiguration()
        // A letter's pictures from the web load as they always have, as
        // Mail's do under every Privacy Protection choice but one, and a
        // tracking pixel among them tells its sender the letter was
        // opened. Under that one, Block All Remote Content, they are held
        // back until "Load All Images" (`RemoteContent`, B-168): WebKit's
        // list on this configuration's controller (`remoteList`), and the
        // letter's markup. What is locked down besides is below.
        config.suppressesIncrementalRendering = false
        // The letter is a stranger's HTML, and WebKit here may never be
        // updated again, so none of its script runs: not a `<script>`, not
        // an `onerror=`, not a `javascript:` link. The pane's own script
        // still does, as a user script in the app's content world, which
        // this setting leaves alone (`ConversationDocument.script`), and so
        // does `callAsyncJavaScript` there. Where the page goes is
        // `PaneNavigation`'s, below.
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        // Nothing of WebKit's kept on the iPad: no cookies, no HTTP cache,
        // no site data from the pictures letters load, which the app would
        // otherwise hold in its container for good with nothing to bound
        // it. Held in memory for as long as the web view lives.
        config.websiteDataStore = .nonPersistent()
        // Registered here because a scheme handler can only be attached to a
        // configuration BEFORE the web view is built; there is no adding one
        // later.
        config.setURLSchemeHandler(inlineImages, forURLScheme: InlineImageRewriter.scheme)
        // Every document the pane loads gets it, once parsed, in the main
        // frame. On a letter or a notice it finds no stack and wires no
        // line; on any page it wires the letter's own pictures (B-122).
        config.userContentController.addUserScript(
            WKUserScript(source: ConversationDocument.script, injectionTime: .atDocumentEnd,
                         forMainFrameOnly: true, in: .defaultClient))
        self.webView = WKWebView(frame: .zero, configuration: config)
        // Off until the pane shows something under Block All Remote
        // Content (`holdBackTheWeb`).
        self.remoteList = RemoteBlockList(on: config.userContentController)
        // What WebKit has painted, told to `renderingProgressDidChange`,
        // for the cover at a tap (B-149). Private, by its name, and only
        // where the web view has the setter; with none, the cover lifts at
        // the document's end, or at its limit.
        let painting = webView.responds(to: NSSelectorFromString(PaneCover.setter))
        if painting { webView.setValue(NSNumber(value: PaneCover.painted), forKey: PaneCover.key) }
        self.painting = painting

        super.init(nibName: nil, bundle: nil)

        // Added after `super.init` because it captures self. This is how a
        // tap on a collapsed letter reaches Swift. In the app's content world
        // only, where the stack's script runs: a letter's markup, in the
        // page's world, has no `bmLetter` to post to.
        config.userContentController.add(self, contentWorld: .defaultClient, name: "bmLetter")
        // And how a tap on a picture of the letter's own reaches it (B-122),
        // in the same world alone, for the same reason.
        config.userContentController.add(self, contentWorld: .defaultClient, name: PanePictures.handler)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.canvas
        buildToolbar()

        header.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.scrollView.backgroundColor = Theme.canvas
        webView.backgroundColor = Theme.canvas
        webView.isOpaque = false

        placeholder.text = "No message selected"
        placeholder.font = Theme.fontDetailMeta
        placeholder.textColor = Theme.secondaryText
        placeholder.textAlignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        // The pane's own colour, as the web view's is; taking the touches
        // that land on it, so nothing of the letter hidden under it is
        // tapped.
        cover.backgroundColor = Theme.canvas
        cover.isHidden = true
        cover.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(header)
        view.addSubview(webView)
        view.addSubview(cover)
        view.addSubview(placeholder)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            webView.topAnchor.constraint(equalTo: header.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cover.topAnchor.constraint(equalTo: webView.topAnchor),
            cover.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            cover.bottomAnchor.constraint(equalTo: webView.bottomAnchor),

            placeholder.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        showEmpty()

        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        // The header's date and the stack's written again where they are
        // when the iPad's form or day changes (B-139).
        for name in [DisplayDates.didChange, UIApplication.significantTimeChangeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(datesChanged),
                                                   name: name, object: nil)
        }
        // The header and the letter at the iPad's text size, again when it
        // changes (B-166).
        NotificationCenter.default.addObserver(self, selector: #selector(textSizeChanged),
                                               name: TextSizes.didChange, object: nil)
        // Delete's button drawn again when Settings changes where the
        // account discards (B-167), with Settings still over the pane.
        NotificationCenter.default.addObserver(self, selector: #selector(drawDiscardButton),
                                               name: MailOptions.changed, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        drawAgain()
        restyleIfOwed()
    }

    /// The iPad's text size or Bold Text has changed (`TextSizes`, B-166;
    /// since 2026-10-27 only Bold Text, the size being Large whatever the
    /// iPad's, `TextSize.drawn`), and the pane follows it while it is open,
    /// as Mail's does: the header's type at once, and the letter, or the
    /// conversation, drawn again at the new size, from what the pane holds,
    /// with nothing fetched (`PaneDocument.restyled`). Drawn again, it starts
    /// where a letter starts as it opens, at its top, or a conversation at
    /// its first open letter (B-074), as after WebKit lost it: the place he
    /// had scrolled to is not kept. While the pane cannot be seen, or the app
    /// is not in front, the letter waits to be drawn until they are, as
    /// `drawAgain` waits.
    @objc private func textSizeChanged() {
        header.restyle()
        placeholder.font = Theme.fontDetailMeta
        restyleOwed = true
        restyleIfOwed()
    }

    private func restyleIfOwed() {
        guard restyleOwed, UIApplication.shared.applicationState == .active,
              viewIfLoaded?.window != nil else { return }
        restyleOwed = false
        guard let again = document.restyled() else { return }
        switch again.content {
        case .nothing, .blank:
            break
        case .notice(let lines):
            renderNotice(lines)
        case .letter(let m, _):
            // Built again at the size now: the page kept was built at the
            // size before. Away from the main thread, as `loadImages` builds
            // it, for the page is no longer cheap string work (B-169's
            // reading of the letter's own style, B-170's files, B-168's
            // hold), and drawn only if the pane still shows the letter.
            // Held back as it was built (`RemotePictures.waits`), so Mail's
            // line and its hold stay after he changes the size, and a letter
            // he loaded stays loaded (B-168; int19).
            let style = pageStyle, held = remote.waits(m.id)
            loads.start({ m }, prepare: { m in (m, PanePage.letter(m, style: style, heldBack: held)) },
                        settle: { [weak self] result in
                            guard let self, case .success(let (m, page)) = result,
                                  self.message?.id == m.id else { return }
                            self.draw(m, page: page)
                        })
        case .conversation(let entries):
            // As `drawAgain` draws it: the stack, then its bodies put in by
            // script once it has loaded, the letter in the header's
            // pictures last, added to the stack's map, which has his
            // letters' from Sent Mail as well (B-170; int19).
            let drawn = entries.compactMap { loaded[$0.id] }
            prepareInlineImages(for: drawn.filter { $0.id != stackFocus.letter }
                                    + drawn.filter { $0.id == stackFocus.letter }, inStack: true)
            renderConversation(entries)
            for (id, body) in again.bodies { fill(id, body) }
        }
    }

    /// The iPad's 24-Hour Time switch, its time zone or its region has
    /// changed, and the kept formatters have been let go
    /// (`DisplayDates.didChange`), or the day has turned over, at midnight
    /// or with the clock set (`significantTimeChangeNotification`): the
    /// header's date and the dates on the stack's lines are written again
    /// where they are, as Mail's are taken to be, and "Today at" turns to
    /// "Yesterday at" at midnight (B-139). They kept the words they were drawn with:
    /// after 24-Hour Time was switched on, the status bar read 14:41 and the
    /// header "Today at 12:39 PM", until the letter was opened again.
    ///
    /// The words alone: nothing is fetched or drawn again, the stack does
    /// not move, no letter opens or closes, and the header keeps its height
    /// and its letter. A stack still loading has its dates written once it
    /// has loaded (`PaneDocument.dates`).
    @objc private func datesChanged() {
        header.drawDate()
        if let dates = document.dates() { run(dates) }
    }

    /// The stack's dates written again by script, in the app's content
    /// world (`ConversationDocument.Dates`).
    private func run(_ dates: ConversationDocument.Dates) {
        webView.callAsyncJavaScript(ConversationDocument.Dates.script, arguments: dates.arguments,
                                    in: nil, in: .defaultClient)
    }

    /// A file's tile in the body shown coming, or as it was, by script, in
    /// the app's content world (`BodyFiles.Busy`, B-148, B-170).
    private func run(_ busy: BodyFiles.Busy) {
        webView.callAsyncJavaScript(BodyFiles.Busy.script, arguments: busy.arguments,
                                    in: nil, in: .defaultClient)
    }

    // MARK: - Toolbar

    private func buildToolbar() {
        // Order is Theme.ToolbarAction's declaration order, so the sequence
        // lives in one place and cannot drift between screens.
        let spec: [Theme.ToolbarAction: (String, Selector)] = [
            .flag:    ("flag",                   #selector(flagTapped)),
            .move:    ("folder",                 #selector(moveTapped)),
            .delete:  ("trash",                  #selector(deleteTapped)),
            .reply:   ("arrowshape.turn.up.left", #selector(replyTapped)),
            .compose: ("square.and.pencil",      #selector(composeTapped)),
        ]
        var items: [UIBarButtonItem] = []
        for action in Theme.ToolbarAction.allCases {
            guard let (name, sel) = spec[action] else { continue }
            // At a fixed size, as the bar's type is, so the buttons keep
            // their places at any text size (B-071, B-166).
            let item = UIBarButtonItem(image: Theme.barSymbol(name),
                                       style: .plain, target: self, action: sel)
            item.tintColor = Theme.tintBlue
            item.width = Theme.minHitTarget      // 44 pt even where the glyph is smaller
            item.accessibilityLabel = String(describing: action).capitalized
            actionItems[action] = item
            items.append(item)
        }
        // Rendered right-to-left by UIKit, so reverse to get the visual order.
        navigationItem.rightBarButtonItems = items.reversed()
    }

    /// Delete's button as Mail's: an archive box called Archive where the
    /// letter, or with none the list's folder, discards into All Mail
    /// (`archiveTarget`, B-167), the bin called Delete otherwise. Its place
    /// in the bar and its tap are the same. Drawn only when that changes
    /// (`discardArchives`): the bar keeps the bin `buildToolbar` gave it
    /// from letter to letter, as before B-167, while nothing archives.
    @objc private func drawDiscardButton() {
        guard let item = actionItems[.delete] else { return }
        let archives = archiveTarget?(summary) != nil
        guard archives != discardArchives else { return }
        discardArchives = archives
        item.image = Theme.barSymbol(archives ? "archivebox" : "trash")
        item.accessibilityLabel = archives ? RowSwipes.Action.archive.title : "Delete"
    }

    private func setActionsEnabled(_ enabled: Bool) {
        // Disabled, never hidden. A greyed button still teaches where it is.
        for item in actionItems.values { item.isEnabled = enabled }
        actionItems[.delete]?.isEnabled = enabled && !writes.deleting
        actionItems[.compose]?.isEnabled = true   // compose never depends on a selection
    }

    /// What the view button's switch reads of the pane before it takes its
    /// picture (B-066). The letter's scroll view, to see whether it is
    /// bouncing and to stop it if it is coasting; nil when the pane shows
    /// no letter. Nothing is loaded or drawn again.
    var letterScroll: UIScrollView? { webView.isHidden ? nil : webView.scrollView }
    /// "No message selected", whose picture rides the middle of the pane;
    /// nil when the pane holds a letter.
    var emptyLabel: UIView? { placeholder.isHidden ? nil : placeholder }

    // MARK: - Content

    func showEmpty() {
        loads.supersede()
        liftCover()
        holdBackTheWeb()
        summary = nil
        message = nil
        loaded = [:]
        threadSummaries = [:]
        stackLetters = []
        related.clear()
        markedUnreadHere = nil
        stackFocus = StackFocus()
        title = ""
        header.isHidden = true
        webView.isHidden = true
        // Emptied as well as hidden. Hidden only, the web view kept the
        // letter, and the next letter's pane unhid it: after a Delete, the
        // letter just binned was back on screen under the next one's header
        // until that one's body came.
        if document.holdsLetter { load(PaneNotice.html([]), as: .blank) }
        placeholder.isHidden = false
        setActionsEnabled(false)
    }

    func clearIfShowingDeletedMessage() { showEmpty() }

    /// The letters the pane shows, by id, for the list to highlight the row
    /// that holds one where the table has dropped the highlight with the
    /// letter still open (B-133): the letter opened, or its conversation's
    /// newest, first, and then the rest of the conversation, the newest
    /// first. None when the pane is empty.
    var lettersShown: [String] {
        guard let summary else { return [] }
        return [summary.id] + stackLetters.reversed().map(\.id).filter { $0 != summary.id }
    }

    /// Edit mode's Delete or Move has taken `letters` off the list: empty
    /// if the pane shows one of them, the letter or any in its
    /// conversation, under its own id or another mailbox's
    /// (`ListEdit.going`), and left as it is otherwise, since a letter he
    /// is reading and did not tick is still there. Emptied whatever it
    /// showed, as it was, the letter he was reading went from the pane when
    /// he deleted others.
    func clearIfShowing(any letters: [MessageSummary]) {
        let shown = [summary].compactMap { $0 } + Array(threadSummaries.values)
        guard ListEdit.going(shown, with: letters) else { return }
        showEmpty()
    }

    /// A lost answer's look has taken `letters` off the list (B-151): empty
    /// only if the letter the pane opened is one of them, and left as it
    /// is for another letter of its conversation, which he may be reading
    /// and did not ask about (`PaneActions.empties`).
    func clearIfOpened(any letters: [MovedAfterAll]) {
        guard PaneActions.empties(paneOpenOn: summary, for: letters) else { return }
        showEmpty()
    }

    /// A letter opened from a row kept on the iPad, before this launch has
    /// shown the server to be the mailbox the copy was kept from, and the
    /// FETCH that brought it has said the UID names another letter now
    /// (D-016): nothing of it is shown, not its body under the kept row's
    /// header, and the pane empties, as the read mark of the same tap
    /// empties it. The list takes the row off. No alert: nothing he asked
    /// for failed, the row was not his letter.
    private func notTheKeptLetter(_ row: MessageSummary) {
        showEmpty()
        onNotTheKeptLetter?(row)
    }

    func show(summary: MessageSummary) {
        coverPane()
        holdBackTheWeb()
        self.summary = summary
        message = nil
        loaded = [:]
        threadSummaries = [:]
        stackLetters = []
        related.clear()
        markedUnreadHere = nil
        stackFocus = StackFocus()
        placeholder.isHidden = true
        header.isHidden = false
        webView.isHidden = false
        setActionsEnabled(true)

        let repository = self.repository
        let held = remote.hold(summary.id)
        loads.show(
            standIn: {
                // The letter he tapped, from the row, before its body is
                // asked for, and "Loading…" in place of the body. This pane
                // used to be drawn only once the body had come, and for the
                // whole fetch it held the previous letter, header and body,
                // beside a selection that had already moved on: a plausible
                // letter that was not the one he tapped. The header is sized
                // before the document goes in, as the conversation's is; see
                // `show(thread:)`, and carries the letter's To and Cc, from
                // its row, so it is whole from the tap (B-127) and does not
                // grow when the letter lands; its files are in its body
                // (B-170). Loading any document also starts WebKit's content
                // process while the body is on its way.
                header.configure(with: .heading(for: summary))
                view.layoutIfNeeded()
                renderNotice(PaneNotice.loading)
            },
            fetch: {
                try await repository.openLetter(summary)
            },
            // The page is built away from the main thread, and drawn only
            // if he is still on this letter when it is ready; see
            // `PaneLoads`.
            prepare: { [style = pageStyle] m in (m, PanePage.letter(m, style: style, heldBack: held)) },
            settle: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let (m, page)):
                    self.message = m
                    self.header.configure(with: m)
                    self.draw(m, page: page)
                case .failure(let error) where error is MailShelf.NotTheKeptLetter:
                    self.notTheKeptLetter(summary)
                case .failure(let error):
                    // Say so IN THE PANE, not only in an alert.
                    //
                    // The header is drawn from the summary before the body is
                    // fetched, so a failed load used to leave a letter with a
                    // sender, a subject, a date and nothing under them — which
                    // does not look like an error, it looks like an empty
                    // letter. Measured on device: a reply whose body was four
                    // paragraphs of quoted text appeared blank, and the only
                    // way to tell the difference was to tap it again.
                    //
                    // The alert stays as well, because it is dismissible and
                    // this is not: he may well tap OK before reading it.
                    self.message = nil
                    self.renderLoadFailure()
                    ErrorPresenter.show(reaching: error, on: self)
                }
            })
    }

    // MARK: - A whole conversation

    /// Shows a thread as a stack of letters in Mail's order, the oldest at
    /// the top and the newest at the bottom, open, with every letter he has
    /// not read, and the rest closed to a line he can tap
    /// (`ConversationDocument.stack`, B-074). The stack opens at the oldest
    /// letter he has not read, or at the newest when he has read the rest
    /// (`ConversationDocument.opensAt`).
    ///
    /// The stack is drawn IMMEDIATELY from the summaries the list already
    /// holds, and the bodies are fetched afterwards and dropped in. The
    /// alternative — wait for every letter, then draw — leaves the pane
    /// blank for as many round trips as the thread is long, and a blank
    /// pane is indistinguishable from an empty letter.
    ///
    /// `completing` is the conversation's Gmail thread number when his own
    /// letters of it are to be brought in from Sent Mail, as Mail's
    /// Complete Threads brings them (B-104), nil otherwise: the list's to
    /// say (`CompleteThreads.thread(toComplete:)`). They go in closed, by
    /// date, and the letter the stack opens at is the one it would have
    /// opened at without them, one line below the top of the pane.
    func show(thread: MessageThread, completing: UInt64?) {
        coverPane()
        holdBackTheWeb()
        summary = thread.newest
        message = nil
        loaded = [:]
        pictureMap = [:]
        markedUnreadHere = nil
        stackFocus = StackFocus(opening: thread.newest.id)
        threadSummaries = Dictionary(uniqueKeysWithValues:
            thread.messages.map { ($0.id, $0) })
        stackLetters = thread.messages.reversed()

        placeholder.isHidden = true
        header.isHidden = false
        webView.isHidden = false
        setActionsEnabled(true)

        // His letters of it, in the first frame when the repository found
        // them in the last ten minutes; otherwise looked for once the
        // newest letter has come, below, and meanwhile as the copy kept on
        // the iPad has them from the last lookup, with a connection or
        // without (B-159).
        let besides = Set(thread.messages.compactMap(\.gmailMessageID))
        let remembered = related.show(stackLetters, completing: completing, remembered: completing.flatMap {
            self.repository.rememberedLettersOfHis(inThread: $0, besides: besides)
        }, kept: completing.flatMap {
            self.repository.lettersOfHisKept(inThread: $0, besides: besides)
        })

        // The oldest at the top, the newest at the bottom, open, with the
        // ones he has not read; the rest closed. His letters among them,
        // closed.
        let entries = ConversationDocument.stack(of: thread, related: remembered)

        // Only the letters that are open are fetched, the newest first.
        // Fetching all of them would be a round trip each for text he
        // cannot see, down one IMAP connection that everything else in the
        // app is queuing on.
        let newest = thread.newest
        let repository = self.repository
        let newestHeld = remote.hold(newest.id) ? newest.id : nil
        loads.show(
            standIn: {
                // The header is given its content BEFORE the stack is
                // rendered, the same order the single-message path uses. It
                // is not cosmetic: the header's height is content-driven and
                // the web view is pinned to the bottom of it, so loading a
                // document into a pane whose header has not been sized yet
                // gives the web view nothing to occupy.
                //
                // The header used to gain a row per file only when the
                // letter came, 44 pt or more each, and push the whole stack
                // down under him as he began to read it; then it had them
                // from the row; and since B-170 it has none, each letter's
                // files being in its own body.
                header.configure(with: .heading(for: newest, subject: thread.subject))
                view.layoutIfNeeded()
                renderConversation(entries)
            },
            fetch: {
                try await repository.openLetter(newest)
            },
            prepare: { m in (m, PanePage.stackBody(m, heldBack: newestHeld)) },
            settle: { [weak self] result in
                self?.settleBody(result, for: newest.id, focus: true)
                self?.lookForHis(afterTheNewestCame: (try? result.get()) != nil, besides: besides)
            })

        // The unread letters open with it, as Mail opens them: each fetched
        // after the newest, which keeps the header. The list marks them
        // read at the tap, with the newest, all at once
        // (`ConversationDocument.readAtTheTap`); the pane opens at the
        // oldest of them, so none is above him out of sight. The rows
        // here say so, as a tap on a line has them say.
        for letter in ConversationDocument.openedWithTheNewest(thread) {
            loadBody(for: letter.id, focus: false)
            var read = letter
            read.isRead = true
            threadSummaries[letter.id] = read
        }
    }

    /// His letters looked for in Sent Mail once the newest letter of the
    /// conversation has come, if they are to be and nothing was remembered
    /// (`PaneRelated.lookUp`), in the background, and put in as they come;
    /// called off if the pane moves on first (`PaneLoads.aside`).
    private func lookForHis(afterTheNewestCame came: Bool, besides: Set<UInt64>) {
        guard let thread = related.lookUp(afterTheNewestCame: came) else { return }
        let repository = self.repository
        loads.aside({ await repository.lettersOfHis(inThread: thread, besides: besides) },
                    settle: { [weak self] found in self?.takeRelated(found) })
    }

    /// His letters of the conversation on screen have come from Sent Mail
    /// (B-104): each goes into the stack closed, before the first letter
    /// of it that came after it, or at the bottom, and the letter he is
    /// reading stays where it is (`ConversationDocument.Insert`). Nothing
    /// else changes: the header, the toolbar and the list stay on the
    /// conversation's letters.
    private func takeRelated(_ found: RelatedLetters) {
        for place in related.take(found, stack: stackLetters) {
            guard let insert = document.insert(place.entries, before: place.before) else { continue }
            run(insert)
        }
    }

    /// Fetches his letter from Sent Mail, opened by its line, and puts it in
    /// its section (B-104), from that folder, by its id and Gmail's id for
    /// it, which the fetch checks (D-016) (`PaneRelated.load`). Opened as a
    /// row is (`openLetter`): from the copy kept on the iPad when it is
    /// there, with a connection or without, and kept there once its body
    /// has come (B-159). Only that: the header and the toolbar stay on the
    /// conversation's letter he opened last, whenever the header follows a
    /// letter he opens, and nothing is marked read. Called off with the
    /// rest if the pane moves on first.
    private func loadRelated(_ entryID: String) {
        guard let load = related.load(for: entryID) else { return }
        let repository = self.repository
        let held = remote.hold(load.entryID) ? load.entryID : nil
        loads.start({ try await repository.openLetter(load.row) },
                    prepare: { m in (m, PanePage.stackBody(m, heldBack: held)) },
                    settle: { [weak self] result in self?.settleRelated(result, for: load) })
    }

    /// His letter's body in its own section, with the loader pointed at its
    /// pictures; or the words a letter of the conversation says when it
    /// could not be downloaded. Nothing kept of the letter but its body in
    /// the stack, and the letter for a picture tapped in it (B-122), in
    /// `related`, which lets it go with the conversation.
    private func settleRelated(_ result: Result<(Message, ConversationDocument.Entry.Rendered), Error>,
                               for load: PaneRelated.Load) {
        switch result {
        case .success(let (m, body)):
            prepareInlineImages(for: [m], inStack: true)
            related.keep(m, for: load)
            fill(related.bodyCame(for: load), body)
        case .failure:
            fill(load.entryID, Self.couldNotDownload)
        }
    }

    /// What a letter of the stack says in its section when its body could
    /// not be downloaded (B-026).
    private static let couldNotDownload = ConversationDocument.Entry.Rendered(
        html: "<span class=\"bm-waiting\">This message could not "
            + "be downloaded. Tap the line above twice to try again.</span>",
        isHTML: false)

    /// The pane's measurements, for the pages built away from the main
    /// thread, which cannot read `Theme` there.
    private var pageStyle: PanePage.Style {
        .init(inset: Int(Theme.detailContentInsetLeft), bodyPointSize: Int(Theme.scaled(17)),
              lineHeight: Theme.detailBodyLineHeight)
    }

    /// The stack itself, drawn at the tap as the stand-in, on the main
    /// thread: it holds no body, only a line per letter, and waiting for it
    /// would leave the previous letter on screen in the meantime. At the
    /// accessibility sizes each part of a letter's line has a line of its
    /// own, as a row's date has (B-166).
    private func renderConversation(_ entries: [ConversationDocument.Entry]) {
        let style = pageStyle
        load(ConversationDocument.html(entries: entries, inset: style.inset,
                                       bodyPointSize: style.bodyPointSize,
                                       lineHeight: style.lineHeight,
                                       stacked: Theme.textSize.stacksRowDate),
             as: .conversation(entries))
    }

    /// Gives the web view a document, and `document` what it holds; and,
    /// while the cover is up, the cover the document to wait for.
    private func load(_ html: String, as content: PaneDocument.Content) {
        let navigation = webView.loadHTMLString(html, baseURL: nil)
        document.loaded(content, navigation: navigation.map(ObjectIdentifier.init))
        paneCover.loaded(navigation.map(ObjectIdentifier.init))
    }

    /// A tap on another letter (B-149): the cover up over the web view in
    /// the frame the header changes, until WebKit has painted the document
    /// the pane gives it now, "Loading…" or the conversation's lines, or
    /// the letter itself if it comes first, and at most `PaneCover.limit`,
    /// so a letter is never left hidden. Called first in `show`, before the
    /// header is given the letter; never for a letter opened by its line in
    /// a conversation, which goes into the page already there. Lifted by
    /// its limit, it says so in the connection log, as WebKit's word of its
    /// paint should have lifted it first.
    private func coverPane() {
        let tap = paneCover.tapped()
        cover.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + PaneCover.limit) { [weak self] in
            guard let self, self.paneCover.limitPassed(tap) else { return }
            self.cover.isHidden = true
            Diagnostics.log(.note, "pane: cover lifted by its limit")
        }
    }

    private func liftCover() {
        paneCover.lift()
        cover.isHidden = true
    }

    /// WebKit has committed a document: the one the cover waits for, if it
    /// is the one the pane gave it last.
    func webView(_ w: WKWebView, didCommit navigation: WKNavigation!) {
        guard let navigation else { return }
        paneCover.committed(ObjectIdentifier(navigation))
    }

    /// WebKit's word of what it has painted (`PaneCover.callback`), private
    /// and asked for in `init`: the cover lifts at the first paint of the
    /// document it waits for.
    @objc(_webView:renderingProgressDidChange:)
    func webView(_ w: WKWebView, renderingProgressDidChange events: UInt) {
        if paneCover.rendered(events) { cover.isHidden = true }
    }

    /// Fetches one letter of the conversation and puts it in its section.
    /// Called off with the rest if the pane moves on first; see `PaneLoads`.
    /// `focus` when he opened it by its line: the header and the toolbar go
    /// to it at the tap (B-129).
    @MainActor
    private func loadBody(for id: String, focus: Bool) {
        guard let row = threadSummaries[id] else { return }
        let already = loaded[id]
        let body = document.body(of: id)
        // Opened by its line: the header and the toolbar are its from the
        // tap, as the single letter's are, whole if its body is in the
        // stack already, below, and from its row until it lands if not,
        // Reply held. They used to stay on the letter before until its body
        // came, and a letter reopened whose body was kept took them at once,
        // to lose them to one opened before it that landed after.
        let headerWasOn = stackFocus.letter
        if focus, stackFocus.opened(id, kept: already != nil && body != nil) == .row {
            focusRow(row)
        }
        // A file tapped in the letter he has left is let go as it lands
        // (B-141): it would open over this letter's header. The line of
        // the letter the header is on already, closed and opened again,
        // lets nothing go.
        if focus { fileTaps.lineOpened(id, headerWasOn: headerWasOn) }
        // Opened before, and its body is in its section: put back as it
        // went in, with nothing to build again.
        if let already, let body {
            drawBody(already, body, focus: focus)
            return
        }
        let repository = self.repository
        let held = remote.hold(id) ? id : nil
        loads.start({ try await repository.openLetter(row) },
                    prepare: { m in (m, PanePage.stackBody(m, heldBack: held)) },
                    settle: { [weak self] result in
                        self?.settleBody(result, for: id, focus: focus)
                    })
    }

    private func settleBody(_ result: Result<(Message, ConversationDocument.Entry.Rendered), Error>,
                            for id: String, focus: Bool) {
        switch result {
        case .success(let (m, body)):
            loaded[id] = m
            drawBody(m, body, focus: focus)
        case .failure(let error) where error is MailShelf.NotTheKeptLetter:
            if let row = threadSummaries[id] { notTheKeptLetter(row) }
        case .failure:
            // Said in the section rather than only in an alert, for the
            // same reason as the single-message path: a letter that
            // silently stays empty looks like a letter with nothing in
            // it. See B-026.
            fill(id, Self.couldNotDownload)
        }
    }

    /// Puts a letter's body, built by `PanePage.stackBody`, in its section,
    /// with the loader pointed at the letter's pictures.
    private func drawBody(_ m: Message, _ body: ConversationDocument.Entry.Rendered, focus: Bool) {
        prepareInlineImages(for: [m], inStack: true)
        fill(m.id, body)
        if focus { focusLetter(m) }
    }

    /// Points the header and the toolbar at a letter of the stack he has
    /// just opened by its line, before its body has come (B-129): the
    /// header drawn from its row, as the single letter's is at the tap
    /// (`Message.heading(for:)`); Flag, Move and Delete on
    /// it (`summary`); Reply held, `message` nil, until its body lands.
    /// The stack hangs from the header if it changes height (`keepPlace`,
    /// B-128).
    private func focusRow(_ row: MessageSummary) {
        message = nil
        summary = row
        let before = header.frame.height
        header.configure(with: .heading(for: row))
        keepPlace(headerWas: before)
    }

    /// The header and the toolbar made whole for a letter of the stack
    /// whose body has come, if he has not opened another since
    /// (`StackFocus.takes`, B-129): its own To and Cc, and Reply its own.
    /// The stack hangs from the header if it changes height with it
    /// (`StackPlace`, B-128).
    private func focusLetter(_ m: Message) {
        guard stackFocus.takes(m.id) else { return }
        message = m
        summary = threadSummaries[m.id] ?? summary
        let before = header.frame.height
        header.configure(with: m)
        keepPlace(headerWas: before)
    }

    /// The header has been given another letter: laid out now, and the
    /// stack left at the offset it had, so what was at the top of the pane
    /// stays at the top, wholly under the header, which pushes it down as
    /// it grows and draws it up as it shrinks (B-128). Held at its top
    /// alone, not at its end, which the scroll view has from the page as
    /// it was before WebKit lays it out for the new height (`StackPlace`).
    /// It used to be scrolled by as much as the header grew or shrank, so
    /// the line he tapped stayed where it was on the glass, and the top of
    /// the pane went under the header: half the line at the top, the line
    /// he had just tapped as often as not, until he scrolled.
    ///
    /// The whole stack moves on the glass then, by the header's change, a Cc
    /// line about 20 pt (a file's row 44 pt until B-170), and a second tap made
    /// at once where the first was lands that far off the line it was meant
    /// for, on the line above or below. So the stack's script is told, and a
    /// line pressed in the second after does nothing
    /// (`ConversationDocument.Shift`). The page cannot see the move itself:
    /// the web view moves on the glass, and nothing in the page does.
    private func keepPlace(headerWas before: CGFloat) {
        view.layoutIfNeeded()
        let grown = Double(header.frame.height - before)
        guard grown != 0 else { return }
        webView.callAsyncJavaScript(ConversationDocument.Shift.script, arguments: [:],
                                    in: nil, in: .defaultClient)
        let scroll = webView.scrollView
        guard let y = StackPlace.offset(from: Double(scroll.contentOffset.y), headerGrewBy: grown,
                                        lowest: -Double(scroll.adjustedContentInset.top))
        else { return }
        scroll.contentOffset.y = CGFloat(y)
    }

    /// Puts a body in its letter's section of the stack: now, or once the
    /// stack's document has finished loading, since run before that it
    /// would find no section and be lost. Kept in the stack as well, so a
    /// redraw has it. See `PaneDocument`.
    private func fill(_ id: String, _ body: ConversationDocument.Entry.Rendered) {
        guard let fill = document.fill(id, with: body) else { return }
        run(fill)
    }

    /// Calls the stack's `bmFill` with the body as an argument, which needs
    /// no escaping; see `ConversationDocument.Fill`. In the app's content
    /// world, where the stack's user script defined `bmFill`
    /// (`ConversationDocument.script`).
    private func run(_ fill: ConversationDocument.Fill) {
        webView.callAsyncJavaScript(ConversationDocument.Fill.script, arguments: fill.arguments,
                                    in: nil, in: .defaultClient)
    }

    /// Calls the stack's `bmInsert` with his letters' sections as arguments
    /// (B-104), in the app's content world, as `run(_ fill:)` does, with
    /// whether the scroll view is moving the stack as they go; and while it
    /// is, tells the script again every tenth of a second until it is still
    /// (`ConversationDocument.Motion`), so the script holds them until then.
    private func run(_ insert: ConversationDocument.Insert) {
        let moving = stackMoving
        webView.callAsyncJavaScript(ConversationDocument.Insert.script,
                                    arguments: insert.arguments(moving: moving), in: nil, in: .defaultClient)
        if moving { watchTheStack() }
    }

    /// Whether UIKit's scroll view is moving the stack: a finger on it,
    /// dragging it, or the stack coasting or bouncing back after one
    /// (B-104). Read here rather than heard by the page, which hears no
    /// touch of a finger that landed on the page before it.
    private var stackMoving: Bool {
        let scroll = webView.scrollView
        return ConversationDocument.Motion.stack(tracking: scroll.isTracking, dragging: scroll.isDragging,
                                                 decelerating: scroll.isDecelerating)
    }

    /// The pane's word to the stack's script, every tenth of a second, from
    /// his letters sent while the scroll view moved the stack until the
    /// word it is still (`motionTick`); nil while none goes. On the main run
    /// loop in its common modes, which a drag does not hold up. To the page
    /// on screen, whatever it is: on a page holding nothing it holds
    /// nothing, and a new page starts holding nothing.
    private var motionTicks: Timer?

    private func watchTheStack() {
        guard motionTicks == nil else { return }
        let ticks = Timer(timeInterval: ConversationDocument.Motion.every, target: self,
                          selector: #selector(motionTick), userInfo: nil, repeats: true)
        RunLoop.main.add(ticks, forMode: .common)
        motionTicks = ticks
    }

    /// Says whether the scroll view still moves the stack, and stops once it
    /// has said it is still, which UIKit always comes to.
    @objc private func motionTick() {
        let moving = stackMoving
        webView.callAsyncJavaScript(ConversationDocument.Motion.script,
                                    arguments: ConversationDocument.Motion.arguments(moving),
                                    in: nil, in: .defaultClient)
        guard !moving else { return }
        motionTicks?.invalidate()
        motionTicks = nil
    }

    /// A letter in the stack was opened or closed; or a picture of a
    /// letter's own was tapped (B-122), or a finger held on it (B-150) or
    /// on a file's tile (B-170).
    func userContentController(_ controller: WKUserContentController,
                               didReceive scriptMessage: WKScriptMessage) {
        if scriptMessage.name == PanePictures.handler {
            if let tap = PanePictures.Tap(scriptMessage.body) {
                if tap.isHold { holdPicture(tap) } else { openPicture(tap) }
            } else if let hold = BodyFiles.Hold(scriptMessage.body) {
                holdFile(hold)
            }
            return
        }
        guard scriptMessage.name == "bmLetter",
              let payload = scriptMessage.body as? [String: Any],
              let sectionID = payload["id"] as? String,
              let opened = payload["open"] as? Bool
        else { return }

        // His letter from Sent Mail (B-104), first: opened or closed, kept
        // so, and its body fetched, and nothing else. Not marked read, and
        // not focused: the header and the toolbar stay on the conversation's
        // letter, so Delete, Move, Flag and Reply never act on it.
        if let his = related.entryID(forSection: sectionID) {
            document.setOpen(opened, his)
            if opened { loadRelated(his) }
            return
        }

        // Back from the section id to the message id. Matched rather
        // than unescaped, because the mapping loses which underscores
        // were slashes.
        guard let id = threadSummaries.keys.first(where: {
                  ConversationDocument.sectionID(for: $0) == sectionID
              })
        else { return }

        // Open or closed, kept, so a redraw opens the same letters.
        document.setOpen(opened, id)
        guard opened else { return }
        loadBody(for: id, focus: true)
        // Reading a letter marks THAT letter read, not the thread. The
        // unread count is how he knows what is still waiting, and
        // emptying it for a conversation he has read one line of would
        // take that away.
        //
        // At the tap that opens it, the way a tap on a row marks its letter,
        // and by the list: the dot goes at the tap and the STORE with it,
        // and the one comes off the folder counts once the server has taken
        // the flag, once (`ReadBilling`, `sendRead`), so a refused STORE
        // never leaves a count too low. This used to send the STORE from
        // here once the body had come, and then reload the whole list and
        // sweep every folder's count to show it.
        //
        // A letter the Flag button's sheet marked unread is marked read
        // again by this tap, as in Mail, and the sheet offers Mark as
        // Unread for it again (B-106).
        if markedUnreadHere == id { markedUnreadHere = nil }
        markOpened(id)
    }

    /// Marks one letter of the stack read, through the list, which clears
    /// the dot at once, sends the STORE and, when the server has taken the
    /// flag, takes the one off the folder counts, once (`ReadBilling`): a
    /// letter he opened by its line. The ones the stack opens with the
    /// newest the list marks at the tap.
    ///
    /// Read back, mutated, written back, rather than
    /// `threadSummaries[id]?.isRead = true`. The optional-chained
    /// subscript compiles to a `_modify` coroutine accessor, and
    /// this toolchain's iOS 16.5 runtime has no
    /// `swift_coroFrameAlloc` to link it against — the same wall
    /// that makes debug builds of this app unlinkable.
    private func markOpened(_ id: String) {
        if let row = threadSummaries[id], !row.isRead {
            var read = row
            read.isRead = true
            threadSummaries[id] = read
            onLetterOpened?(row)
        }
    }

    /// The list has changed: letters that have come into the conversation
    /// on screen go in at the bottom of its stack, where Mail puts them
    /// (B-074). Nothing above them moves, so he is not moved.
    ///
    /// Each is drawn as the stack draws its letters: open if he has not read
    /// it, its body fetched, but not marked read, since he did not open it
    /// and may not have seen it come. Its row keeps its dot, and the
    /// conversation opened again marks it. The header and the toolbar stay
    /// on the letter he had.
    ///
    /// Nothing while the stack's page is still loading or lost to WebKit:
    /// the list offers them again as it next changes, and the conversation
    /// opened again has them. See `ConversationDocument.arrivals`.
    func takeArrivals(from threads: [MessageThread]) {
        guard !stackLetters.isEmpty else { return }
        let more = ConversationDocument.arrivals(after: stackLetters, in: threads)
        guard !more.isEmpty,
              let append = document.append(more.map {
                  ConversationDocument.entry(for: $0, open: !$0.isRead)
              })
        else { return }
        stackLetters += more
        for letter in more { threadSummaries[letter.id] = letter }
        webView.callAsyncJavaScript(ConversationDocument.Append.script, arguments: append.arguments,
                                    in: nil, in: .defaultClient)
        for letter in more where !letter.isRead { loadBody(for: letter.id, focus: false) }
    }

    /// Fills the reading pane with the reason there is nothing in it.
    private func renderLoadFailure() {
        renderNotice("This message could not be downloaded.",
                     "Check the connection and tap it again.")
    }

    /// Grey text in the pane, for the two cases where there is no letter to
    /// draw: it failed, or there was never anything in it. Deliberately the
    /// same presentation for both, because the difference that matters is
    /// in the WORDS — and the words are the whole point.
    private func renderNotice(_ lines: String...) {
        renderNotice(lines)
    }

    private func renderNotice(_ lines: [String]) {
        load(PaneNotice.html(lines), as: .notice(lines))
    }

    // MARK: - Attachments

    /// Downloads a file and shows it.
    ///
    /// QuickLook rather than anything hand-rolled, and that is a decision
    /// about scope as much as effort: it renders PDFs, photographs, Word and
    /// Pages documents natively, and it arrives with a Done button and a
    /// share button already on it. The share sheet is what makes "save"
    /// work — "Save to Files", "Print", "Copy to Photos" — without this app
    /// growing a file manager of its own.
    ///
    /// `letter` is the letter the file is of, when it is not `message`: a
    /// tile in the body of another letter of the conversation, or a
    /// picture tapped in one, or in his from Sent Mail (B-122). Its tile,
    /// if it has one, shows it coming, whichever letter it is of
    /// (`BodyFiles.Busy`, B-148, B-170): the header has had no file rows
    /// since B-170, nor their spinners.
    ///
    /// Shown only if the pane still shows what it was opened from when the
    /// file has come (`PaneLoads.stillShows`): a file, or a picture, whose
    /// letter he has tapped past, emptied or moved on from meanwhile is
    /// neither shown over the letter he stopped on nor said to have failed,
    /// as a letter's body is not (`PaneLoads.draws`). Its download is not
    /// called off; it ends, and is let go (B-122). And only if the last
    /// tap was on it, and no other letter of the conversation has been
    /// opened by its line since (`FileTaps`, B-141): one tapped before
    /// another opened over the letter he had moved to, and the one he
    /// tapped last, landing under it, was let go without a word. An
    /// earlier one is let go as it lands, its spinner cleared by the
    /// `defer`, and the last one keeps its spinner until it opens. A file
    /// tapped again while it is still coming starts no second download:
    /// the one running opens it as it lands.
    ///
    /// `item` is what it is opened for: Quick Look, or an item of the menu
    /// of a picture held (`holdPicture`, B-150), Markup and Reply (B-171),
    /// Save Image, Save to Files, Share or Copy, each done with the bytes
    /// as they land by the same rules, and what the last tap on it asked
    /// for wins.
    private func openAttachment(_ attachment: Attachment, of letter: Message? = nil,
                                for item: PanePictures.Item = .quickLook) {
        guard let m = letter ?? message else { return }
        // Its tile in the body, every file's only one since B-170.
        run(BodyFiles.Busy(attachment.id, of: m.id, busy: true))
        let shown = loads.shown
        let file = FileTaps.File(letter: m.id, part: attachment.id, shown: shown)
        // Already coming: this tap makes it the last again, and its
        // download, running, opens it (B-141), for what this tap asked
        // (B-150). A second behind it on the one connection made him wait
        // for both.
        guard fileTaps.tapped(file, for: item) else { return }
        // Counted at the tap, not once the task runs, so that no check of
        // the watch comes between (`isOpeningFile`). A file let go for a
        // later one is still counted until its download ends: the warning
        // waits for it as for the one that opens.
        filesOpening += 1

        Task { @MainActor in
            defer {
                filesOpening -= 1
                fileTaps.ended(file)
                // Only on the page it was shown coming on: on a page given
                // since, the same tile can be coming for a tap of its own.
                if loads.stillShows(shown) { run(BodyFiles.Busy(attachment.id, of: m.id, busy: false)) }
            }
            do {
                let data = try await repository.fetchAttachmentData(
                    attachment.id, of: m.id, mailboxID: m.mailboxID)
                // The pane has moved on since the tap: nothing is shown.
                guard loads.stillShows(shown) else { return }
                // Another file tapped since, or another letter opened by
                // its line: that is what he wants now (B-141).
                guard fileTaps.opens(file) else { return }
                // What the last tap on it asked for (B-150). Save Image and
                // Copy put nothing over the pane, and need no file.
                let use = fileTaps.item(of: file) ?? item
                if !use.presents {
                    keep(data, of: attachment, by: use)
                    return
                }
                // A file that comes while a preview, or anything else, is up
                // over the pane could not be shown: UIKit presents nothing
                // over a controller already presenting. It is not written
                // either, and the preview up keeps its file.
                guard presentedViewController == nil else { return }
                // One copy on disk at most: the last file he opened goes
                // as the next is written, and not before. Its preview has
                // closed, since nothing is presented, but a print of it
                // may have been reading it until a moment ago.
                if let shown = previewURL { AttachmentStore.removeStaged(shown) }
                previewURL = nil
                // Written before presenting, not after: QuickLook reads the
                // URL synchronously the moment it appears, and handing it one
                // that is not on disk yet shows "No preview available"
                // permanently rather than retrying.
                let url = try AttachmentStore.write(data, named: attachment.filename)
                previewURL = url

                switch use {
                case .saveToFiles:
                    // Files' own sheet, which copies it where he picks.
                    present(UIDocumentPickerViewController(forExporting: [url], asCopy: true), animated: true)
                case .share:
                    let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    share.popoverPresentationController?.sourceView = webView
                    share.popoverPresentationController?.sourceRect = pictureSpot
                    present(share, animated: true)
                case .markupAndReply:
                    // iOS's own Markup on it, in Quick Look, full screen as
                    // a tap opens it, a copy made of what he draws and the
                    // picture left as it came (B-171). The one preview with
                    // the pane as its delegate (`QLPreviewControllerDelegate`
                    // below): a tap's Quick Look has no Markup, as before.
                    let preview = QLPreviewController()
                    preview.dataSource = self
                    preview.delegate = self
                    preview.modalPresentationStyle = .fullScreen
                    MarkupReply.letGo(markup.begin(ObjectIdentifier(preview)))
                    marking = (m, attachment)
                    present(preview, animated: true)
                case .quickLook, .saveImage, .copy:
                    let preview = QLPreviewController()
                    preview.dataSource = self
                    // Full screen, not a sheet. A scanned letter or a receipt is
                    // the thing he is trying to read, and the whole point of the
                    // iPad is that it can be as large as the glass.
                    preview.modalPresentationStyle = .fullScreen
                    present(preview, animated: true)
                }
            } catch {
                // Nor is a failure said over another letter, or for a file
                // he has tapped past.
                guard loads.stillShows(shown), fileTaps.opens(file) else { return }
                ErrorPresenter.show(.attachmentFailed, on: self)
            }
        }
    }

    /// Points the loader at this message's parts. The page was pointed at
    /// the same ones when it was built (`PanePage.contentIDs`).
    ///
    /// Re-pointed per message rather than held once, because a `Content-ID`
    /// only means anything inside the message that declared it — two letters
    /// can both contain `cid:image001.png` and mean different pictures.
    ///
    /// `inStack` for a body put into a conversation's stack, or the stack
    /// drawn again: the letters' parts are added to those of the bodies gone
    /// in before them, which the page can still ask for, and asks for all
    /// together when they went in before it had loaded (B-170). Several
    /// letters at once only for a conversation drawn again after WebKit lost
    /// it, when every picture in it is asked for anew. Where two use the
    /// same id, the later letter's is served.
    private func prepareInlineImages(for letters: [Message], inStack: Bool = false) {
        // The map a printed letter's loader reads too (`LetterPrint`).
        let parts = inStack ? PanePage.pictures(of: letters, adding: pictureMap) : PanePage.pictures(of: letters)
        pictureMap = parts

        inlineImages.fetch = { [weak self] contentID in
            // Never surfaced to him: the loader turns a throw into an empty
            // 404 so the picture is simply absent rather than an alert.
            guard let self, let part = parts[contentID] else {
                throw MailError.attachmentFailed
            }
            let data = try await self.repository.fetchAttachmentData(
                part.section, of: part.messageID, mailboxID: part.mailboxID)
            return (data, part.mimeType)
        }
    }

    /// Draws a letter from its page, built by `PanePage.letter` away from
    /// the main thread, with the loader pointed at its pictures; or says in
    /// the pane that there is nothing in it, so that a pane with nothing in
    /// it can only ever mean a bug. See `MailText.hasNoVisibleContent` and
    /// B-026.
    private func draw(_ m: Message, page: String?) {
        prepareInlineImages(for: [m])
        guard let page else {
            renderNotice(MailText.emptyBodyNotice)
            return
        }
        load(page, as: .letter(m, page: page))
    }

    /// A document has finished loading: his letters from Sent Mail and the
    /// conversation's bodies that came before it had, go in now. See
    /// `PaneDocument`. And the cover lifts, if it waits for this one and
    /// WebKit tells nothing of its paint (`PaneCover.finished`, B-149).
    func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {
        guard let navigation else { return }
        if paneCover.finished(ObjectIdentifier(navigation), painting: painting) { cover.isHidden = true }
        let finished = document.didFinish(ObjectIdentifier(navigation))
        for insert in finished.inserts { run(insert) }
        for fill in finished.fills { run(fill) }
        if let dates = finished.dates { run(dates) }
    }

    /// WebKit's content process has ended, as iOS ends it for memory while
    /// he is in another app, and the page went with it: the pane came back
    /// black, or a conversation stuck on "Loading…", under a header still
    /// saying which letter it was. What the pane showed is drawn again from
    /// what it holds, the letter, the stack with the bodies that had come
    /// and the letters he had open, or the grey words, once he can see it;
    /// see `drawAgain`. A body still on its way goes in when it comes, as
    /// ever. The place he had scrolled to in the letter is not kept: a
    /// letter starts at the top, a conversation at its first open letter,
    /// as it opens (B-074).
    func webViewWebContentProcessDidTerminate(_ w: WKWebView) {
        Diagnostics.log(.note, "webview: content process ended")
        document.contentProcessEnded()
        drawAgain()
    }

    /// Draws again what WebKit lost, if the app is in front and the pane on
    /// screen, and otherwise leaves it for when they are: iOS ends the
    /// process mostly while he is in another app, and a document drawn
    /// there would take back the memory it was ended for. Called again when
    /// the app becomes active and when the pane appears. See `PaneDocument`.
    ///
    /// No letter is fetched again. The pictures in a conversation's letters
    /// are asked for anew, since the page that had them has gone, and those
    /// of any letter but the last one downloaded come from the server.
    private func drawAgain() {
        guard UIApplication.shared.applicationState == .active, viewIfLoaded?.window != nil,
              let redraw = document.redraw() else { return }
        switch redraw.content {
        case .nothing, .blank:
            break
        case .notice(let lines):
            renderNotice(lines)
        case .letter(let m, let page):
            draw(m, page: page)
        case .conversation(let entries):
            // The letter in the header last, so its pictures win a clash of
            // ids; see `prepareInlineImages`. Added to the stack's map, which
            // has his letters' from Sent Mail as well (B-170).
            let drawn = entries.compactMap { loaded[$0.id] }
            prepareInlineImages(for: drawn.filter { $0.id != stackFocus.letter }
                                    + drawn.filter { $0.id == stackFocus.letter }, inStack: true)
            // The stack as it was first drawn, and the bodies put back into
            // it by script once it has loaded, as they first went in; see
            // `PaneDocument`.
            renderConversation(entries)
            for (id, body) in redraw.bodies { fill(id, body) }
        }
    }

    @objc private func appBecameActive() {
        drawAgain()
        restyleIfOwed()
    }

    func webView(_ w: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        // Not a failure: the pane's "Loading…" is replaced by the letter as
        // soon as the letter comes, and tapping on before that replaces it
        // again, so a document is often cancelled before it has finished.
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        Diagnostics.log(.note, "webview: load failed \((error as NSError).code)")
    }

    /// The pane loads its own documents and nothing else: no other page,
    /// no frame inside a letter, no form sent. See `PaneNavigation`.
    func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        switch PaneNavigation.decide(PaneNavigation.Kind(action.navigationType),
                                     mainFrame: action.targetFrame?.isMainFrame,
                                     url: action.request.url) {
        case .allow:
            decisionHandler(.allow)
        case .cancel:
            decisionHandler(.cancel)
        case .follow(let url):
            decisionHandler(.cancel)
            follow(url)
        case .openFile(let letter, let section):
            decisionHandler(.cancel)
            openFile(section, of: letter)
        case .loadImages(let letter):
            decisionHandler(.cancel)
            loadImages(of: letter)
        }
    }

    /// What the pane shows next begins with no letter's pictures from the
    /// web loaded, and WebKit's list on its web view if Block All Remote
    /// Content is, before anything of it is given to the web view
    /// (`RemotePictures`, B-168). Off, it stays off, and nothing changes.
    private func holdBackTheWeb() {
        remote = RemotePictures()
        remoteList.on = remote.listOn()
    }

    /// "Load All Images" on a letter's line (B-168): that letter's pictures
    /// from the web, and nothing of any other letter's. The letter on its
    /// own, its page drawn again without the line or anything held back,
    /// from the top; in a conversation, its body put in its section again
    /// so, where he is, the letters around it as they were, his from Sent
    /// Mail among them. WebKit's list comes off the web view first, for
    /// the requests the new markup makes, and stays off while the pane
    /// shows this; a letter of the stack still held back is held back by
    /// its markup alone (`RemoteContent.blocked`). The page or the body is
    /// built away from the main thread, as at the tap, and drawn only if
    /// the pane still shows the letter.
    ///
    /// Nothing for a letter whose page or body was not built held back, or
    /// one not shown here: a link of the scheme in a letter's own markup
    /// does no more than its own line. Decided by what the page was built
    /// with (`RemotePictures.waits`), not by the setting now, so a line
    /// still on screen after Block All Remote Content is turned off loads
    /// its letter.
    private func loadImages(of id: String) {
        guard remote.waits(id) else { return }
        if threadSummaries.isEmpty {
            guard let m = message, m.id == id else { return }
            remote.load(id)
            remoteList.on = remote.listOn()
            let style = pageStyle
            loads.start({ m }, prepare: { m in (m, PanePage.letter(m, style: style)) },
                        settle: { [weak self] result in
                            guard let self, case .success(let (m, page)) = result,
                                  self.message?.id == m.id else { return }
                            self.draw(m, page: page)
                        })
            return
        }
        guard let m = loaded[id] ?? related.letter(inSection: ConversationDocument.sectionID(for: id))
        else { return }
        remote.load(id)
        remoteList.on = remote.listOn()
        loads.start({ m }, prepare: { m in PanePage.stackBody(m) },
                    settle: { [weak self] result in
                        guard let self, case .success(let body) = result else { return }
                        // The loader pointed at this letter's own pictures,
                        // for the body put back asks for them again, as
                        // `drawBody` points it, added to the stack's map
                        // so the other letters' pictures still come
                        // (B-170; int19).
                        self.prepareInlineImages(for: [m], inStack: true)
                        self.fill(id, body)
                    })
    }

    /// A file's tile in a letter's body, tapped (`BodyFiles`, B-113,
    /// B-170): the file opened in Quick Look. The letter is the one on its
    /// own in the pane, or one of the conversation's, opened or not the
    /// last, or his from Sent Mail once it has come (`related`, B-104); a
    /// file it does not list opens nothing.
    private func openFile(_ section: String, of letter: String) {
        guard let (m, file) = self.file(section, of: letter) else { return }
        openAttachment(file, of: m)
    }

    /// The letter `letter` the pane holds and its file at `section`, as a
    /// tile names them; nil for a letter it does not hold or a part the
    /// letter does not have. A file it lists, or a picture sent to be shown
    /// by `cid:` that its body does not show, which is drawn as a file
    /// (`BodyFiles.drawn`).
    private func file(_ section: String, of letter: String) -> (Message, Attachment)? {
        let shown = message?.id == letter ? message : (loaded[letter] ?? related.letter(withID: letter))
        guard let m = shown, let file = m.attachments.first(where: { $0.id == section }) else {
            return nil
        }
        return (m, file)
    }

    /// A picture of a letter's own, tapped (B-122): opened full screen as a
    /// file's tile in the body opens a file, by `openAttachment`, from the
    /// letter whose section it is in, the one on its own in the pane, one
    /// of the conversation's that has come, or his from Sent Mail; nothing
    /// for a picture too small, or one no letter the pane holds has
    /// (`PanePictures`), nor for one that comes once the pane has moved on
    /// (`openAttachment`). Mail's own: Quick Look, whose share button has
    /// Save Image and Save to Files.
    private func openPicture(_ tap: PanePictures.Tap) {
        guard let opening = PanePictures.opening(tap, inStack: !threadSummaries.isEmpty, alone: message,
                                                 stack: loaded, his: { related.letter(inSection: $0) })
        else { return }
        openAttachment(opening.part, of: opening.letter)
    }

    /// A finger held on a picture of a letter's own (B-150): Mail's menu
    /// for a file of the letter's, Quick Look, Markup and Reply (B-171),
    /// Save Image, Save to Files, Share and Copy (`PanePictures.menu`), as
    /// a sheet at the finger, as the Flag and Reply buttons have theirs,
    /// where WebKit's own menu was, with Save to Photos and no Save to
    /// Files. The picture is the one a tap would open, any size; each item
    /// downloads it as a tap does (`openAttachment`), unless the pane has
    /// been given something else meanwhile, and does with it what it says.
    /// A tap outside closes it with nothing done.
    private func holdPicture(_ tap: PanePictures.Tap) {
        guard presentedViewController == nil,
              let opening = PanePictures.opening(tap, inStack: !threadSummaries.isEmpty, alone: message,
                                                 stack: loaded, his: { related.letter(inSection: $0) })
        else { return }
        hold(PanePictures.menu, opening.part, of: opening.letter, x: tap.x, y: tap.y)
    }

    /// A finger held on a file's tile in a letter's body (B-170): the menu
    /// a held photo gives, less Save Image for a file that is no picture
    /// (`PanePictures.menu(for:)`), at the finger, for the file a tap on
    /// the tile opens.
    private func holdFile(_ held: BodyFiles.Hold) {
        guard presentedViewController == nil, let (m, file) = self.file(held.section, of: held.letter) else {
            return
        }
        hold(PanePictures.menu(for: file), file, of: m, x: held.x, y: held.y)
    }

    /// `items` as a sheet at `x`, `y` in the web view, each downloading
    /// `part` of `letter` as a tap does (`openAttachment`), for what it
    /// says, unless the pane has been given something else meanwhile.
    private func hold(_ items: [PanePictures.Item], _ part: Attachment, of letter: Message,
                      x: Double, y: Double) {
        let bounds = webView.bounds
        let spot = CGRect(x: min(max(CGFloat(x), 0), bounds.width) - 1,
                          y: min(max(CGFloat(y), 0), bounds.height) - 1, width: 2, height: 2)
        let shown = loads.shown
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.popoverPresentationController?.sourceView = webView
        sheet.popoverPresentationController?.sourceRect = spot
        for item in items {
            sheet.addAction(UIAlertAction(title: item.title, style: .default) { [weak self] _ in
                guard let self, self.loads.stillShows(shown) else { return }
                self.pictureSpot = spot
                self.openAttachment(part, of: letter, for: item)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    /// Save Image and Copy, with the picture's bytes (B-150). Into Photos
    /// as they came, as Mail's Save Image keeps a picture as it is, asking
    /// to add to Photos alone (`NSPhotoLibraryAddUsageDescription`, which
    /// iOS asks him for once, B-067), and as a picture made from them where
    /// Photos will not take them as they are. Onto the pasteboard as the
    /// kind of picture they are, or as a picture made from them where the
    /// kind is not known. Nothing is said: the save is iOS's own, and a
    /// save he has not allowed is noted in the log alone. A file held on
    /// its tile (B-170) is copied as the kind of file it is, by its type or
    /// else by the end of its name, a PDF as a PDF.
    private func keep(_ data: Data, of picture: Attachment, by use: PanePictures.Item) {
        switch use {
        case .copy:
            let named = UTType(filenameExtension: (picture.filename as NSString).pathExtension)
            if let kind = UTType(mimeType: picture.mimeType), kind.conforms(to: .image) {
                UIPasteboard.general.setData(data, forPasteboardType: kind.identifier)
            } else if let image = UIImage(data: data) {
                UIPasteboard.general.image = image
            } else if let kind = [UTType(mimeType: picture.mimeType), named].compactMap({ $0 })
                        .first(where: { !$0.isDynamic && $0 != .data }) {
                UIPasteboard.general.setData(data, forPasteboardType: kind.identifier)
            }
        case .saveImage:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { allowed in
                guard allowed == .authorized else {
                    Diagnostics.log(.note, "photos: save not allowed \(allowed.rawValue)")
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }) { saved, _ in
                    guard !saved, let image = UIImage(data: data) else { return }
                    PHPhotoLibrary.shared().performChanges({
                        _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }) { saved, _ in
                        if !saved { Diagnostics.log(.note, "photos: save failed") }
                    }
                }
            }
        case .quickLook, .markupAndReply, .saveToFiles, .share:
            break
        }
    }

    /// Markup and Reply's Reply (B-171): the app's own Reply to the letter
    /// whose picture he marked up, as the Reply button's sheet opens it
    /// (`openCompose`), whom it goes to, its subject, its quote and his
    /// signature, with his copy landing in it as a photo he picks lands:
    /// in the letter under his words, a row of his with its Remove. Mail's
    /// question about the original's files is not asked; it is asked only
    /// under Ask (`ReplyFiles.asks`), which his Mail is not taken to be,
    /// and the reply carries none of them then, as Don’t Include. Nothing
    /// goes unless he taps Send.
    ///
    /// Opened once Quick Look has gone from over the pane, which can still
    /// be there as it says it has closed: looked for again a tenth of a
    /// second later, ten times at most. Anything else over the pane, and the
    /// copy is let go, said in the log alone. Until the composer has opened
    /// or the copy has been let go, the pane counts as opening a file
    /// (`MarkupReply.ended`, `isOpeningFile`), so that the warning before
    /// the app stops opening is not what covers it.
    private func replyWithMarkup(_ copy: DraftAttachment, tries: Int = 0) {
        guard let letter = marking?.letter else {
            markup.ended()
            return MarkupReply.letGo(copy)
        }
        if let over = presentedViewController {
            guard over is QLPreviewController, tries < 10 else {
                marking = nil
                markup.ended()
                MarkupReply.letGo(copy)
                Diagnostics.log(.note, "markup: reply not opened, the pane covered")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.replyWithMarkup(copy, tries: tries + 1)
            }
            return
        }
        marking = nil
        openCompose(replyTo: letter, all: false, forward: false, landing: [copy])
        markup.ended()
    }

    /// A tapped link opens at once, in Safari or the app that claims it, as
    /// Mail opens one (B-145), and never navigates the pane itself. A
    /// message view that silently turns into a web page is how someone ends
    /// up lost with no way back. It used to ask "Open this link?" first
    /// (B-055), a question Mail never asks.
    ///
    /// A `mailto:` link is the exception, and writes the letter here, as
    /// Mail's own do. It used to go through the same confirmation to Apple
    /// Mail, and the letter went from there, missing from this app's Sent
    /// (B-036).
    private func follow(_ url: URL) {
        if url.scheme?.lowercased() == "mailto",
           let draft = MailtoLink.draft(from: url,
                                        signature: CredentialStore.loadAccount()?.signature ?? "") {
            let compose = ComposeViewController(repository: repository, draft: draft)
            let nav = UINavigationController.formSheet(compose)
            present(nav, animated: true)
            return
        }
        UIApplication.shared.open(url)
    }

    // MARK: - Actions

    /// The Flag button's sheet (B-106), as Mail's Flag button opened one:
    /// Flag or Unflag, then Mark as Unread or Mark as Read, and Cancel
    /// (`FlagMenu`). A popover under the Flag button on the iPad, which a
    /// tap outside closes with nothing done, as Reply's sheet is. It used
    /// to flag the letter at the first tap, and nothing in the pane could
    /// mark a letter unread.
    ///
    /// For the letter the toolbar acts on, in a conversation the one he
    /// opened last, and for that letter only: an item chosen after the
    /// pane has moved on does nothing. An item whose write on the letter
    /// is still on its way as the sheet opens is greyed, the pane's own or
    /// the list's.
    ///
    /// Mark as Unread or Mark as Read as the dot on the list's row says,
    /// as Mail's item follows the letter (`dotOnList`). The pane's own idea
    /// of it went wrong whenever the dot changed without it: Edit mode's
    /// Mark on the letter open here, which leaves the pane as it was, or
    /// the read mark of the tap that opened it refused and put back. The
    /// sheet then offered the item that changed nothing. The pane's own
    /// (`markedUnreadHere`) only where the list has no row that is the
    /// letter. Flag or Unflag as the flag on the row says (`flagOnList`),
    /// for the same reason: a drag's Flag on the row (B-156) leaves the
    /// pane as it was.
    @objc private func flagTapped() {
        guard let s = summary else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.popoverPresentationController?.barButtonItem = actionItems[.flag]
        let dot = dotOnList?(s)
        let flag = flagOnList?(s)
        let items = FlagMenu.items(flagged: flag?.flagged ?? s.isFlagged,
                                   read: dot?.read ?? (markedUnreadHere != s.id),
                                   local: LocalDraft.key(ofRow: s.id) != nil,
                                   in: foldersForJunk?(s) ?? FlagMenu.Folders())
        for item in items {
            let action = UIAlertAction(title: item.title, style: .default) { [weak self] _ in
                guard let self, self.summary?.id == s.id else { return }
                self.choose(item)
            }
            switch item {
            case .flag, .unflag:
                action.isEnabled = !writes.flagOnItsWay(s.id) && flag?.onItsWay != true
            case .markAsUnread, .markAsRead:
                action.isEnabled = !writes.readOnItsWay(s.id) && dot?.onItsWay != true
            case .moveToJunk, .moveToInbox: break
            }
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: FlagMenu.cancel, style: .cancel))
        present(sheet, animated: true)
    }

    private func choose(_ item: FlagMenu.Item) {
        switch item {
        case .flag: setFlag(true)
        case .unflag: setFlag(false)
        case .markAsUnread: setRead(false)
        case .markAsRead: setRead(true)
        case .moveToJunk(let folder), .moveToInbox(let folder):
            guard let s = summary else { return }
            move(s, to: folder)
        }
    }

    /// Flags the letter at once, in the pane and in the list, and puts the
    /// flag back and says so if the server refuses. It used to be sent
    /// with `try?`, so a refused STORE left a flag on screen that Gmail did
    /// not have, and nothing said so until the next Refresh.
    ///
    /// A second Flag on the same letter while its STORE is on its way is
    /// ignored; another letter's Flag goes. See `PaneWrites`.
    private func setFlag(_ flagged: Bool) {
        guard let s = summary, writes.startFlag(s.id) else { return }
        setFlagged(flagged, on: s.id)
        Task { @MainActor in
            let refused = await self.performed(.flag(flagged), on: s)
            self.writes.flagAnswered(s.id)
            guard let refused else { return }
            self.setFlagged(s.isFlagged, on: s.id)
            ErrorPresenter.show(reaching: refused, on: self)
        }
    }

    /// Mark as Unread or Mark as Read from the Flag button's sheet (B-106):
    /// the dot on the list's row changes at the tap, the letter stays in
    /// the pane, and the sheet offers the other next time. Marked unread, a
    /// tap on its line in the stack marks it read again, as a tap on its
    /// row does, and nothing else does: no redraw, reload or new mail.
    /// Refused, all of it is put back and he is told, as for a Flag.
    /// Nothing is queued while there is no connection (D-016).
    ///
    /// Handed to `perform` with the read mark the sheet had it with, the
    /// one the item changes: the list bills the change from its own copy
    /// where it has one, and from this where it has not, a letter opened
    /// from a search since ended.
    private func setRead(_ read: Bool) {
        guard let s = summary, writes.startRead(s.id) else { return }
        markHere(read, on: s.id)
        var letter = s
        letter.isRead = !read
        Task { @MainActor in
            let refused = await self.performed(.read(read), on: letter)
            self.writes.readAnswered(s.id)
            guard let refused else { return }
            self.markHere(!read, on: s.id)
            ErrorPresenter.show(reaching: refused, on: self)
        }
    }

    /// The pane's own copies of a letter's read mark: what the sheet
    /// offers where the list has no row that is the letter, and its row in
    /// the conversation if the pane is showing one, so a tap on its line
    /// marks it read again. Marked unread only while the toolbar still
    /// acts on it; nothing is kept for a letter the pane has let go.
    private func markHere(_ read: Bool, on id: String) {
        if read {
            if markedUnreadHere == id { markedUnreadHere = nil }
        } else if summary?.id == id {
            markedUnreadHere = id
        }
        // Read back, mutated, written back; see `userContentController`.
        if var row = threadSummaries[id] {
            row.isRead = read
            threadSummaries[id] = row
        }
    }

    /// `perform`'s answer, or the connection's failure where nothing is
    /// wired to run it, as it was.
    private func performed(_ action: PaneAction, on letter: MessageSummary) async -> MailError? {
        guard let perform else { return .cannotConnect }
        return await perform(action, letter)
    }

    /// The pane's own copies of a letter's flag: the letter on screen, and
    /// its row in the conversation if the pane is showing one.
    private func setFlagged(_ flagged: Bool, on id: String) {
        if var s = summary, s.id == id {
            s.isFlagged = flagged
            summary = s
        }
        // Read back, mutated, written back; see `userContentController`.
        if var row = threadSummaries[id] {
            row.isFlagged = flagged
            threadSummaries[id] = row
        }
    }

    @objc private func moveTapped() {
        guard let s = summary else { return }
        let move = MoveMessageViewController(repository: repository,
                                             excluding: s.mailboxID) { [weak self] destination in
            self?.move(s, to: destination)
        }
        let nav = UINavigationController.formSheet(move)
        present(nav, animated: true)
    }

    /// Moves the letter: from the Move sheet's folder, or the Flag
    /// button's Move to Junk or Move to Inbox (B-106). One letter, the one
    /// the toolbar acts on, never a selection. The row leaves the list and
    /// the status line says "Moving…" until the server has answered
    /// (`perform`); refused, the row comes back and he is told.
    private func move(_ s: MessageSummary, to destination: Mailbox) {
        // Emptied as he chooses the folder, as a Delete empties it at
        // the tap, rather than once the server has answered; the letter
        // after it opens in it once the row is off (`NextLetter`, B-158).
        if summary?.id == s.id { showEmpty() }
        Task { @MainActor in
            if let refused = await self.performed(.move(to: destination), on: s) {
                ErrorPresenter.show(reaching: refused, on: self)
            }
        }
    }

    /// Empties the pane at the tap, and the row leaves the list at the same
    /// moment (`PaneActions`). Both used to wait for the MOVE, and then for
    /// a reload of the whole list, with the letter still on screen and
    /// Delete still live, so a second tap sent a second MOVE after the
    /// first. If the server refuses, the row comes back and he is told.
    ///
    /// Inside Trash, where Delete erases the letter, he is asked first
    /// (`questionBeforeDeleting`, B-062), and the pane empties only once he
    /// has said Delete; Cancel leaves the letter in the pane and on the
    /// list. It went at the first tap, with nothing asked.
    ///
    /// The letter after it then opens, as Mail's View Next Message opens it
    /// (`NextLetter`, B-158), from the container once the row is off. A tap
    /// within half a second of the last Delete does nothing, so a double tap
    /// does not bin the letter the first one opened (`PaneWrites`).
    ///
    /// Anywhere else, under Ask Before Deleting, Mail's sheet from the
    /// button first, "Trash Message" (`DiscardQuestion`, B-168), and the
    /// pane empties only once he has tapped it; a tap outside leaves the
    /// letter in the pane and on the list. Off, as it comes, nothing is
    /// asked there.
    @objc private func deleteTapped() {
        guard let s = summary, writes.deleteGoes(at: ProcessInfo.processInfo.systemUptime) else {
            return
        }
        guard let question = questionBeforeDeleting?(s) else {
            // "Archive Message" where the button archives (B-167), as Mail
            // asks before an Archive too.
            let verb: DiscardQuestion.Verb = archiveTarget?(s) == nil ? .trash : .archive
            guard let asked = DiscardQuestion.before(verb, letters: 1, from: .pane) else {
                delete(s)
                return
            }
            DiscardConfirmation.ask(asked, on: self, from: actionItems[.delete]) { [weak self] in
                // The letter he was asked about, while it is still the one
                // in the pane, as below.
                guard let self, self.summary?.id == s.id else { return }
                self.delete(s)
            }
            return
        }
        EraseConfirmation.ask(question, on: self) { [weak self] in
            // The letter he was asked about, while it is still the one in
            // the pane.
            guard let self, self.summary?.id == s.id else { return }
            self.delete(s)
        }
    }

    /// Where the account discards into the Archive, Mail's Archive in the
    /// Trash's place: a Move into All Mail (`archiveTarget`, B-167), with
    /// Delete's guards and the next letter after it, as a Move from the
    /// pane has.
    private func delete(_ s: MessageSummary) {
        guard writes.startDelete(at: ProcessInfo.processInfo.systemUptime,
                                 untilAnswered: NextLetter.action == .dontSelectAMessage) else {
            return
        }
        let action = archiveTarget?(s).map { PaneAction.move(to: $0) } ?? .delete
        showEmpty()
        Task { @MainActor in
            let refused = await self.performed(action, on: s)
            self.writes.deleteAnswered()
            self.setActionsEnabled(self.summary != nil)
            if let refused { ErrorPresenter.show(reaching: refused, on: self) }
        }
    }

    /// Reply / Reply All / Forward / Print as a sheet, which is what old
    /// Mail did. Labelled choices beat one button that guesses.
    ///
    /// Forward of a letter with files (`Message.listedAttachments`) asks Mail's
    /// question first (B-107). So do Reply and Reply All, only if his iPad's
    /// Mail is set to Ask (`ReplyFiles.mode`), which it is not taken to be.
    ///
    /// Print is the fourth, as Mail's Reply button had it from iOS 4.2 to
    /// 12 (B-110): the letter the header shows, the one Reply answers,
    /// printed light, through AirPrint's panel from this button. Greyed
    /// while a print is being made ready, a second or a few.
    @objc private func replyTapped() {
        guard let m = message else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.popoverPresentationController?.barButtonItem = actionItems[.reply]

        sheet.addAction(UIAlertAction(title: "Reply", style: .default) { [weak self] _ in
            guard let self else { return }
            guard ReplyFiles.asks(m) else {
                return self.openCompose(replyTo: m, all: false, forward: false)
            }
            self.askAboutFiles { [weak self] in
                self?.openCompose(replyTo: m, all: false, forward: false, included: $0)
            }
        })
        sheet.addAction(UIAlertAction(title: "Reply All", style: .default) { [weak self] _ in
            guard let self else { return }
            guard ReplyFiles.asks(m) else {
                return self.openCompose(replyTo: m, all: true, forward: false)
            }
            self.askAboutFiles { [weak self] in
                self?.openCompose(replyTo: m, all: true, forward: false, included: $0)
            }
        })
        sheet.addAction(UIAlertAction(title: "Forward", style: .default) { [weak self] _ in
            guard let self else { return }
            guard ReplyFiles.forwardAsks(m) else {
                return self.openCompose(replyTo: m, all: false, forward: true)
            }
            self.askAboutFiles { [weak self] in
                self?.openCompose(replyTo: m, all: false, forward: true, included: $0)
            }
        })
        let printRow = UIAlertAction(title: "Print", style: .default) { [weak self] _ in
            self?.printLetter(m)
        }
        printRow.isEnabled = printing?.isPreparing != true
        sheet.addAction(printRow)
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    /// A print of a letter on its way, from Print to its panel closed or
    /// the job ended: the warning before the app stops opening waits for
    /// it, since put up while the PDF is made it would cover the pane and
    /// end the print with no panel (`PrintSteps.coverLimit`, B-137).
    var isPrinting: Bool { printing != nil }

    /// A file or a picture tapped is being downloaded for Quick Look, from
    /// the tap until its preview is up or its download has ended: the
    /// warning waits for it too (B-137). Put up meanwhile, it was taken by
    /// `openAttachment` for something already over the pane, and the
    /// preview was let go without a word; after OK nothing opened.
    /// And so does a picture being marked up for Markup and Reply, until
    /// its reply has opened or its copy has been let go
    /// (`MarkupReply.isBusy`, B-171).
    var isOpeningFile: Bool { filesOpening > 0 || markup.isBusy(at: Date()) }

    /// Prints `m`, the letter the sheet was opened for (B-110). Nothing
    /// while a print is being made ready; a print whose panel is up holds
    /// only its bytes, and is replaced. Named so as not to hide Swift's
    /// `print`.
    private func printLetter(_ m: Message) {
        guard printing?.isPreparing != true else { return }
        let job = LetterPrint(
            letter: m, heldBack: remote.holdsBack(m.id), repository: repository, style: printStyle,
            pane: self,
            anchor: actionItems[.reply],
            // The same letter: its id and its folder, since two folders can
            // hold the same "<uidvalidity>/<uid>".
            stillShown: { [weak self] in
                guard let shown = self?.message else { return false }
                return shown.id == m.id && shown.mailboxID == m.mailboxID
            },
            ended: { [weak self] job in
                guard let self, self.printing === job else { return }
                self.printing = nil
            })
        printing = job
        job.start()
    }

    /// The header's and the body's sizes, for a printed letter, which is
    /// built away from the main thread and cannot read `Theme` there.
    private var printStyle: PrintPage.Style {
        .init(senderPointSize: Int(Theme.fontDetailSender.pointSize),
              metaPointSize: Int(Theme.fontDetailMeta.pointSize),
              subjectPointSize: Int(Theme.fontDetailSubject.pointSize),
              bodyPointSize: Int(Theme.scaled(17)), lineHeight: Theme.detailBodyLineHeight)
    }

    /// Mail's question about the original's files (B-107), as an action
    /// sheet at the Reply button, where the choice was made: Include, Don’t
    /// Include, and Cancel, which on the iPad is a tap outside it, and
    /// begins no letter. `answer` hears true for Include. Over `row`, where
    /// the choice was made on a row of the list, from More (B-156).
    private func askAboutFiles(over row: (view: UIView, rect: CGRect)? = nil,
                               _ answer: @escaping (Bool) -> Void) {
        let sheet = UIAlertController(title: ReplyFiles.question, message: nil,
                                      preferredStyle: .actionSheet)
        if let row {
            sheet.popoverPresentationController?.sourceView = row.view
            sheet.popoverPresentationController?.sourceRect = row.rect
        } else {
            sheet.popoverPresentationController?.barButtonItem = actionItems[.reply]
        }
        sheet.addAction(UIAlertAction(title: ReplyFiles.include, style: .default) { _ in
            answer(true)
        })
        sheet.addAction(UIAlertAction(title: ReplyFiles.dontInclude, style: .default) { _ in
            answer(false)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func composeTapped() { openCompose(replyTo: nil, all: false, forward: false) }

    /// The letter whose More's Reply, Reply All or Forward is being made
    /// ready, by its id, from the tap until the composer or the failure:
    /// one at a time, so a second tap meanwhile makes no second letter.
    private var answering: String?

    /// More's Reply, Reply All or Forward on a row of the list (B-156), as
    /// Mail's sheet answers a letter without opening it: the letter fetched
    /// as the pane opens one (`openLetter`), from the copy kept on the iPad
    /// when it is there, and shown nowhere; then the composer, as the Reply
    /// button's sheet opens it, Mail's question about the files asked first
    /// where that sheet would ask it, over the row (`row`). Nothing in the
    /// pane changes, and the letter is not marked read.
    ///
    /// A failure is said as a letter that could not be opened is. A row
    /// kept on the iPad that the server says is another letter now is
    /// taken off the list, as when it is opened (D-016).
    func answer(_ letter: MessageSummary, all: Bool, forward: Bool,
                over row: (view: UIView, rect: CGRect)) {
        guard answering == nil else { return }
        answering = letter.id
        let repository = self.repository
        Task { @MainActor in
            defer { self.answering = nil }
            let m: Message
            do {
                m = try await repository.openLetter(letter)
            } catch is MailShelf.NotTheKeptLetter {
                self.onNotTheKeptLetter?(letter)
                return
            } catch {
                ErrorPresenter.show(reaching: error, on: self)
                return
            }
            guard forward ? ReplyFiles.forwardAsks(m) : ReplyFiles.asks(m) else {
                return self.openCompose(replyTo: m, all: all, forward: forward)
            }
            self.askAboutFiles(over: row) { [weak self] in
                self?.openCompose(replyTo: m, all: all, forward: forward, included: $0)
            }
        }
    }

    /// Presents the composer. The DRAFT itself is built by `Draft.replying`
    /// and `Draft.forwarding`, which are pure and live in the model layer —
    /// three separate bugs have been found in that logic and none of them
    /// were visible on this screen, so it belongs where a test can reach it.
    ///
    /// `m` is the letter the pane shows, which in a conversation is the one
    /// opened last, once its body has come (`focusLetter`; until then
    /// Reply does nothing, B-129): a Reply answers that letter, to its
    /// Reply-To, or to whom it went when it is his own (`ReplyAddressing`).
    /// Every address of his the app knows is handed in, the login as well
    /// as the address, so that none of them is sent a copy of his reply.
    ///
    /// A Reply or Reply All hands the composer its files' rule
    /// (`ReplyFiles`, B-107), and nothing else does. `included` is his
    /// answer to Mail's question, nil where none was asked. `landing` lands
    /// in the letter once the sheet has opened, as a photo he picks lands
    /// (`ComposeViewController.landing`): the copy Markup and Reply made
    /// (B-171), and nothing for any other letter.
    private func openCompose(replyTo m: Message?, all: Bool, forward: Bool,
                             included: Bool? = nil, landing: [DraftAttachment] = []) {
        let account = CredentialStore.loadAccount()
        let signature = account?.signature ?? ""
        var draft = Draft.blank(signature: signature)
        var replyFiles: ReplyFiles?
        if let m {
            if forward {
                draft = .forwarding(m, signature: signature, includingFiles: included ?? true)
            } else {
                draft = .replying(to: m, all: all, mine: OwnAddresses(account: account),
                                  signature: signature)
                let opening = ReplyFiles.opening(m, included: included)
                draft.attachments = opening.rows
                replyFiles = opening.rule
            }
        }
        let compose = ComposeViewController(repository: repository, draft: draft,
                                            replyFiles: replyFiles)
        compose.landing = landing
        let nav = UINavigationController.formSheet(compose)
        present(nav, animated: true)
    }
}

/// WebKit's kind of navigation, for `PaneNavigation`: the pane's and a
/// printed letter's (`LetterPrint`).
extension PaneNavigation.Kind {
    init(_ type: WKNavigationType) {
        switch type {
        case .linkActivated: self = .linkActivated
        case .formSubmitted: self = .formSubmitted
        case .backForward: self = .backForward
        case .reload: self = .reload
        case .formResubmitted: self = .formResubmitted
        case .other: self = .other
        @unknown default: self = .unknown
        }
    }
}

/// QuickLook asks for its items through a data source rather than taking
/// them at init. One item at a time here, deliberately: the reader tapped a
/// particular file, and paging him sideways into the other attachments on
/// the message is not what he asked for.
extension MessageDetailViewController: QLPreviewControllerDataSource {

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewController(_ controller: QLPreviewController,
                           previewItemAt index: Int) -> QLPreviewItem {
        // `NSURL` conforms to QLPreviewItem already. Never nil while a
        // preview is up: it is set before one is presented and cleared only
        // while none is. Not force-unwrapped all the same: asked with none,
        // QuickLook is handed the empty store, where there is nothing to
        // show, rather than the app ending.
        (previewURL ?? AttachmentStore.root) as NSURL
    }
}

/// Markup and Reply's preview's delegate (B-171), and no other preview's:
/// the pane is the delegate of the one Quick Look it opens for Markup and
/// Reply alone (`openAttachment`). What he draws is saved as a copy, the
/// picture itself left as it came, and the copy goes in the reply as Quick
/// Look closes (`MarkupReply`). Nothing here touches the file Quick Look
/// shows (`previewURL`), which goes only as the next file is written
/// (B-063).
extension MessageDetailViewController: QLPreviewControllerDelegate {

    /// Markup on, a copy made of what he draws: Quick Look's Markup button,
    /// as Mail's composer has Quick Look's for a file.
    func previewController(_ controller: QLPreviewController,
                           editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode {
        .createCopy
    }

    /// A copy of what he drew, staged at once, since the file Quick Look
    /// hands over is its own and temporary: kept for the reply while the
    /// preview is up, the copy before it let go, or put in the reply now if
    /// the preview has closed already. One that cannot be staged is said
    /// in the log alone. One from a Quick Look before the picture last
    /// opened for Markup is let go (`MarkupReply.saved`).
    func previewController(_ controller: QLPreviewController, didSaveEditedCopyOf previewItem: QLPreviewItem,
                           at modifiedContentsURL: URL) {
        guard let picture = marking?.picture else { return }
        let made = MarkupReply.picture(original: picture.filename, originalType: picture.mimeType,
                                       copy: modifiedContentsURL,
                                       lookup: { UTType(filenameExtension: $0)?.preferredMIMEType })
        let copy: DraftAttachment
        do {
            copy = try MarkupReply.stage(modifiedContentsURL, as: made, jpeg: {
                UIImage(contentsOfFile: $0.path)?.jpegData(compressionQuality: SharedPhoto.quality)
            })
        } catch {
            Diagnostics.log(.note, "markup: copy not staged")
            return
        }
        let saved = markup.saved(copy, from: ObjectIdentifier(controller), at: Date())
        MarkupReply.letGo(saved.unused)
        if let reply = saved.reply { replyWithMarkup(reply) }
    }

    /// Quick Look closed: the reply, with the last copy saved; with none,
    /// nothing drawn, he is back at the letter with nothing made.
    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        if let copy = markup.closed(ObjectIdentifier(controller), at: Date()) { replyWithMarkup(copy) }
    }
}

#endif
