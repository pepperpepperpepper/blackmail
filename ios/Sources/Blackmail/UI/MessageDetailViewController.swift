// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit
import WebKit
import QuickLook

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

    /// Runs a Delete, Move or Flag and edits the list beside the pane to
    /// match (`PaneActions`). Returns nil once the server has taken it, and
    /// why not if it has not, for the alert to say.
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

    private let repository: MailRepository
    private var summary: MessageSummary?
    private var message: Message?
    /// The loaded letters of that conversation, by id, so the toolbar can
    /// act on whichever one he last opened.
    private var loaded: [String: Message] = [:]
    /// Which letter the toolbar's Reply and Flag apply to: the one most
    /// recently expanded. Nil when the pane holds a single message, where
    /// `message` is the answer.
    private var focused: String?
    /// The list rows of the conversation on screen, by id, so the toolbar
    /// can be pointed at whichever letter he last opened.
    private var threadSummaries: [String: MessageSummary] = [:]
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

    private let header = MessageHeaderView()
    private let webView: WKWebView
    private let placeholder = UILabel()
    private var actionItems: [Theme.ToolbarAction: UIBarButtonItem] = [:]
    /// Answers the `cid:` images inside whatever message is on screen.
    private let inlineImages = InlineImageLoader()
    /// The body fetches for what the pane shows, called off when it shows
    /// something else. See `PaneLoads`.
    private let loads = PaneLoads()
    /// The Delete and the Flags on their way to the server, which decide
    /// what the next tap on either does. See `PaneWrites`.
    private var writes = PaneWrites()
    /// What the web view holds, which emptying the pane has to clear and
    /// which is drawn again if WebKit loses it, and the conversation's
    /// bodies waiting for its document to load. Nothing until the first
    /// letter, so launch does not start WebKit's content process for an
    /// empty page. See `PaneDocument`.
    private var document = PaneDocument()

    init(repository: MailRepository) {
        self.repository = repository

        let config = WKWebViewConfiguration()
        // Remote content is NOT blocked: a letter's pictures from the web
        // load as they always have, and a tracking pixel among them tells
        // its sender the letter was opened. Blocking them is the owner's
        // decision, still open. What is locked down is below.
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
        // frame. On a letter or a notice it finds no stack and wires nothing.
        config.userContentController.addUserScript(
            WKUserScript(source: ConversationDocument.script, injectionTime: .atDocumentEnd,
                         forMainFrameOnly: true, in: .defaultClient))
        self.webView = WKWebView(frame: .zero, configuration: config)

        super.init(nibName: nil, bundle: nil)

        // Added after `super.init` because it captures self. This is how a
        // tap on a collapsed letter reaches Swift. In the app's content world
        // only, where the stack's script runs: a letter's markup, in the
        // page's world, has no `bmLetter` to post to.
        config.userContentController.add(self, contentWorld: .defaultClient, name: "bmLetter")
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

        view.addSubview(header)
        view.addSubview(webView)
        view.addSubview(placeholder)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            webView.topAnchor.constraint(equalTo: header.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            placeholder.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        showEmpty()

        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        drawAgain()
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
            let item = UIBarButtonItem(image: UIImage(systemName: name),
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
        summary = nil
        message = nil
        loaded = [:]
        threadSummaries = [:]
        focused = nil
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
        self.summary = summary
        message = nil
        loaded = [:]
        threadSummaries = [:]
        focused = nil
        placeholder.isHidden = true
        header.isHidden = false
        webView.isHidden = false
        setActionsEnabled(true)

        let repository = self.repository
        loads.show(
            standIn: {
                // The letter he tapped, from the row, before its body is
                // asked for, and "Loading…" in place of the body. This pane
                // used to be drawn only once the body had come, and for the
                // whole fetch it held the previous letter, header and body,
                // beside a selection that had already moved on: a plausible
                // letter that was not the one he tapped. The header is sized
                // before the document goes in, as the conversation's is; see
                // `show(thread:)`, and carries the letter's files, from its
                // row, so it does not grow when the letter lands. Loading any
                // document also starts WebKit's content process while the
                // body is on its way.
                header.configure(with: .heading(for: summary))
                header.onSelectAttachment = nil
                view.layoutIfNeeded()
                renderNotice(PaneNotice.loading)
            },
            fetch: {
                try await repository.loadMessage(id: summary.id, gmailMessageID: summary.gmailMessageID,
                                                 mailboxID: summary.mailboxID)
            },
            // The page is built away from the main thread, and drawn only
            // if he is still on this letter when it is ready; see
            // `PaneLoads`.
            prepare: { [style = pageStyle] m in (m, PanePage.letter(m, style: style)) },
            settle: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let (m, page)):
                    self.message = m
                    self.header.configure(with: m)
                    self.header.onSelectAttachment = { [weak self] in self?.openAttachment($0) }
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

    /// Shows a thread as a stack of letters, newest open, the rest
    /// collapsed to a line he can tap.
    ///
    /// The stack is drawn IMMEDIATELY from the summaries the list already
    /// holds, and the bodies are fetched afterwards and dropped in. The
    /// alternative — wait for every letter, then draw — leaves the pane
    /// blank for as many round trips as the thread is long, and a blank
    /// pane is indistinguishable from an empty letter.
    func show(thread: MessageThread) {
        summary = thread.newest
        message = nil
        loaded = [:]
        focused = thread.newest.id
        threadSummaries = Dictionary(uniqueKeysWithValues:
            thread.messages.map { ($0.id, $0) })

        placeholder.isHidden = true
        header.isHidden = false
        webView.isHidden = false
        setActionsEnabled(true)

        let entries = thread.messages.map { m in
            ConversationDocument.Entry(
                id: m.id, sender: m.sender, date: m.date, body: nil,
                // Newest open, everything else collapsed. Mail's own
                // choice, and the right one: the latest reply is what he
                // opened the conversation to read.
                isExpanded: m.id == thread.newest.id,
                preview: m.preview)
        }

        // Only the letter that is actually open is fetched. Fetching all of
        // them would be a round trip each for text he cannot see, down one
        // IMAP connection that everything else in the app is queuing on.
        let newest = thread.newest
        let repository = self.repository
        loads.show(
            standIn: {
                // The header is given its content BEFORE the stack is
                // rendered, the same order the single-message path uses. It
                // is not cosmetic: the header's height is content-driven and
                // the web view is pinned to the bottom of it, so loading a
                // document into a pane whose header has not been sized yet
                // gives the web view nothing to occupy.
                //
                // Sized for the newest letter's files too, from its row. The
                // header used to gain a row per file only when the letter
                // came, 44 pt or more each, and push the whole stack down
                // under him as he began to read it.
                header.configure(with: .heading(for: newest, subject: thread.subject))
                header.onSelectAttachment = nil
                view.layoutIfNeeded()
                renderConversation(entries)
            },
            fetch: {
                try await repository.loadMessage(id: newest.id, gmailMessageID: newest.gmailMessageID,
                                                 mailboxID: newest.mailboxID)
            },
            prepare: { m in (m, PanePage.stackBody(m)) },
            settle: { [weak self] result in
                self?.settleBody(result, for: newest.id, focus: true)
            })
    }

    /// The pane's measurements, for the pages built away from the main
    /// thread, which cannot read `Theme` there.
    private var pageStyle: PanePage.Style {
        .init(inset: Int(Theme.detailContentInsetLeft), bodyPointSize: Int(Theme.scaled(17)),
              lineHeight: Theme.detailBodyLineHeight)
    }

    /// The stack itself, drawn at the tap as the stand-in, on the main
    /// thread: it holds no body, only a line per letter, and waiting for it
    /// would leave the previous letter on screen in the meantime.
    private func renderConversation(_ entries: [ConversationDocument.Entry]) {
        let style = pageStyle
        load(ConversationDocument.html(entries: entries, inset: style.inset,
                                       bodyPointSize: style.bodyPointSize,
                                       lineHeight: style.lineHeight),
             as: .conversation(entries))
    }

    /// Gives the web view a document, and `document` what it holds.
    private func load(_ html: String, as content: PaneDocument.Content) {
        let navigation = webView.loadHTMLString(html, baseURL: nil)
        document.loaded(content, navigation: navigation.map(ObjectIdentifier.init))
    }

    /// Fetches one letter of the conversation and puts it in its section.
    /// Called off with the rest if the pane moves on first; see `PaneLoads`.
    @MainActor
    private func loadBody(for id: String, focus: Bool) {
        guard let row = threadSummaries[id] else { return }
        // Opened before, and its body is in its section: put back as it
        // went in, with nothing to build again.
        if let already = loaded[id], let body = document.body(of: id) {
            drawBody(already, body, focus: focus)
            return
        }
        let repository = self.repository
        loads.start({ try await repository.loadMessage(id: id, gmailMessageID: row.gmailMessageID,
                                                       mailboxID: row.mailboxID) },
                    prepare: { m in (m, PanePage.stackBody(m)) },
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
            fill(id, .init(html: "<span class=\"bm-waiting\">This message could not "
                           + "be downloaded. Tap the line above twice to try again.</span>",
                           isHTML: false))
        }
    }

    /// Puts a letter's body, built by `PanePage.stackBody`, in its section,
    /// with the loader pointed at the letter's pictures.
    private func drawBody(_ m: Message, _ body: ConversationDocument.Entry.Rendered, focus: Bool) {
        prepareInlineImages(for: [m])
        fill(m.id, body)
        if focus { focusLetter(m) }
    }

    /// Points the header and the toolbar at one letter of the stack.
    private func focusLetter(_ m: Message) {
        focused = m.id
        message = m
        summary = threadSummaries[m.id] ?? summary
        header.configure(with: m)
        header.onSelectAttachment = { [weak self] in self?.openAttachment($0) }
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

    /// A letter in the stack was opened or closed.
    func userContentController(_ controller: WKUserContentController,
                               didReceive scriptMessage: WKScriptMessage) {
        guard scriptMessage.name == "bmLetter",
              let payload = scriptMessage.body as? [String: Any],
              let sectionID = payload["id"] as? String,
              let opened = payload["open"] as? Bool,
              // Back from the section id to the message id. Matched rather
              // than unescaped, because the mapping loses which underscores
              // were slashes.
              let id = threadSummaries.keys.first(where: {
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
        // and by the list, which clears the dot, sends the STORE and takes
        // the one off the folder counts, once (`ReadBilling`). This used to
        // send the STORE from here once the body had come, and then reload
        // the whole list and sweep every folder's count to show it.
        //
        // Read back, mutated, written back, rather than
        // `threadSummaries[id]?.isRead = true`. The optional-chained
        // subscript compiles to a `_modify` coroutine accessor, and
        // this toolchain's iOS 16.5 runtime has no
        // `swift_coroFrameAlloc` to link it against — the same wall
        // that makes debug builds of this app unlinkable.
        if let row = threadSummaries[id], !row.isRead {
            var read = row
            read.isRead = true
            threadSummaries[id] = read
            onLetterOpened?(row)
        }
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
    private func openAttachment(_ attachment: Attachment) {
        guard let m = message else { return }
        header.setAttachment(attachment.id, busy: true)

        Task { @MainActor in
            // Only while the header still shows the letter the file came
            // from. Another letter's header can list a file under the same
            // part, "2" as often as not, and would be told it is no longer
            // busy while its own download runs, or before its letter has
            // come and its rows can be opened.
            defer {
                if message?.id == m.id { header.setAttachment(attachment.id, busy: false) }
            }
            do {
                let data = try await repository.fetchAttachmentData(
                    attachment.id, of: m.id, mailboxID: m.mailboxID)
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
                previewURL = try AttachmentStore.write(data, named: attachment.filename)

                let preview = QLPreviewController()
                preview.dataSource = self
                // Full screen, not a sheet. A scanned letter or a receipt is
                // the thing he is trying to read, and the whole point of the
                // iPad is that it can be as large as the glass.
                preview.modalPresentationStyle = .fullScreen
                present(preview, animated: true)
            } catch {
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
    /// Several letters at once only for a conversation drawn again after
    /// WebKit lost it, when every picture in it is asked for anew. Where two
    /// use the same id, the later letter's is served.
    private func prepareInlineImages(for letters: [Message]) {
        var parts: [String: (letter: Message, section: String, mimeType: String)] = [:]
        for m in letters {
            for attachment in m.attachments {
                guard let cid = attachment.contentID else { continue }
                parts[cid] = (m, attachment.id, attachment.mimeType)
            }
        }

        inlineImages.fetch = { [weak self] contentID in
            // Never surfaced to him: the loader turns a throw into an empty
            // 404 so the picture is simply absent rather than an alert.
            guard let self, let part = parts[contentID] else {
                throw MailError.attachmentFailed
            }
            let data = try await self.repository.fetchAttachmentData(
                part.section, of: part.letter.id, mailboxID: part.letter.mailboxID)
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

    /// A document has finished loading: the conversation's bodies that came
    /// before it had, go in now. See `PaneDocument`.
    func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {
        guard let navigation else { return }
        for fill in document.didFinish(ObjectIdentifier(navigation)) { run(fill) }
    }

    /// WebKit's content process has ended, as iOS ends it for memory while
    /// he is in another app, and the page went with it: the pane came back
    /// black, or a conversation stuck on "Loading…", under a header still
    /// saying which letter it was. What the pane showed is drawn again from
    /// what it holds, the letter, the stack with the bodies that had come
    /// and the letters he had open, or the grey words, once he can see it;
    /// see `drawAgain`. A body still on its way goes in when it comes, as
    /// ever. The place he had scrolled to in the letter is not kept: the
    /// page starts at the top.
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
            // ids; see `prepareInlineImages`.
            let drawn = entries.compactMap { loaded[$0.id] }
            prepareInlineImages(for: drawn.filter { $0.id != focused }
                                    + drawn.filter { $0.id == focused })
            // The stack as it was first drawn, and the bodies put back into
            // it by script once it has loaded, as they first went in; see
            // `PaneDocument`.
            renderConversation(entries)
            for (id, body) in redraw.bodies { fill(id, body) }
        }
    }

    @objc private func appBecameActive() { drawAgain() }

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
        }
    }

    /// Links open in Safari after a confirmation, and never navigate the pane
    /// itself. A message view that silently turns into a web page is how
    /// someone ends up lost with no way back.
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
            let nav = UINavigationController(rootViewController: compose)
            nav.modalPresentationStyle = .formSheet
            present(nav, animated: true)
            return
        }
        let alert = UIAlertController(title: "Open this link?",
                                      message: url.host ?? url.absoluteString,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open", style: .default) { _ in
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }

    // MARK: - Actions

    /// Flags the letter at once, in the pane and in the list, and puts the
    /// flag back and says so if the server refuses. It used to be sent
    /// with `try?`, so a refused STORE left a flag on screen that Gmail did
    /// not have, and nothing said so until the next Refresh.
    ///
    /// A second tap on the same letter while its STORE is on its way is a
    /// double tap, and ignored; another letter's Flag goes. See `PaneWrites`.
    @objc private func flagTapped() {
        guard let s = summary, writes.startFlag(s.id) else { return }
        let flagged = !s.isFlagged
        setFlagged(flagged, on: s.id)
        Task { @MainActor in
            let refused = await self.performed(.flag(flagged), on: s)
            self.writes.flagAnswered(s.id)
            guard let refused else { return }
            self.setFlagged(s.isFlagged, on: s.id)
            ErrorPresenter.show(reaching: refused, on: self)
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
            guard let self else { return }
            // Emptied as he chooses the folder, as a Delete empties it at
            // the tap, rather than once the server has answered.
            if self.summary?.id == s.id { self.showEmpty() }
            Task { @MainActor in
                if let refused = await self.performed(.move(to: destination), on: s) {
                    ErrorPresenter.show(reaching: refused, on: self)
                }
            }
        }
        let nav = UINavigationController(rootViewController: move)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
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
    @objc private func deleteTapped() {
        guard let s = summary, !writes.deleting else { return }
        guard let question = questionBeforeDeleting?(s) else {
            delete(s)
            return
        }
        EraseConfirmation.ask(question, on: self) { [weak self] in
            // The letter he was asked about, while it is still the one in
            // the pane.
            guard let self, self.summary?.id == s.id else { return }
            self.delete(s)
        }
    }

    private func delete(_ s: MessageSummary) {
        guard writes.startDelete() else { return }
        showEmpty()
        Task { @MainActor in
            let refused = await self.performed(.delete, on: s)
            self.writes.deleteAnswered()
            self.setActionsEnabled(self.summary != nil)
            if let refused { ErrorPresenter.show(reaching: refused, on: self) }
        }
    }

    /// Reply / Reply All / Forward as a three-item sheet, which is what old
    /// Mail did. Three labelled choices beats one button that guesses.
    @objc private func replyTapped() {
        guard let m = message else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.popoverPresentationController?.barButtonItem = actionItems[.reply]

        sheet.addAction(UIAlertAction(title: "Reply", style: .default) { [weak self] _ in
            self?.openCompose(replyTo: m, all: false, forward: false)
        })
        sheet.addAction(UIAlertAction(title: "Reply All", style: .default) { [weak self] _ in
            self?.openCompose(replyTo: m, all: true, forward: false)
        })
        sheet.addAction(UIAlertAction(title: "Forward", style: .default) { [weak self] _ in
            self?.openCompose(replyTo: m, all: false, forward: true)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func composeTapped() { openCompose(replyTo: nil, all: false, forward: false) }

    /// Presents the composer. The DRAFT itself is built by `Draft.replying`
    /// and `Draft.forwarding`, which are pure and live in the model layer —
    /// three separate bugs have been found in that logic and none of them
    /// were visible on this screen, so it belongs where a test can reach it.
    ///
    /// `m` is the letter the pane shows, which in a conversation is the one
    /// opened last (`focusLetter`): a Reply answers that letter, to its
    /// Reply-To, or to whom it went when it is his own (`ReplyAddressing`).
    /// Every address of his the app knows is handed in, the login as well
    /// as the address, so that none of them is sent a copy of his reply.
    private func openCompose(replyTo m: Message?, all: Bool, forward: Bool) {
        let account = CredentialStore.loadAccount()
        let signature = account?.signature ?? ""
        var draft = Draft.blank(signature: signature)
        if let m {
            draft = forward
                ? .forwarding(m, signature: signature)
                : .replying(to: m, all: all, mine: OwnAddresses(account: account),
                            signature: signature)
        }
        let compose = ComposeViewController(repository: repository, draft: draft)
        let nav = UINavigationController(rootViewController: compose)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }
}

private extension PaneNavigation.Kind {
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

#endif
