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

    var onNeedsListRefresh: (() -> Void)?

    private let repository: MailRepository
    private var summary: MessageSummary?
    private var message: Message?
    /// The conversation on screen, when the pane is showing a stack rather
    /// than one letter. Empty otherwise.
    private var entries: [ConversationDocument.Entry] = []
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
    private var previewURL: URL?

    private let header = MessageHeaderView()
    private let webView: WKWebView
    private let placeholder = UILabel()
    private var actionItems: [Theme.ToolbarAction: UIBarButtonItem] = [:]
    /// Answers the `cid:` images inside whatever message is on screen.
    private let inlineImages = InlineImageLoader()

    init(repository: MailRepository) {
        self.repository = repository

        let config = WKWebViewConfiguration()
        // Remote content blocked by default: a tracking pixel should not phone
        // home just because he opened a letter, and on a slow connection a
        // half-loaded remote image looks like a broken message.
        config.suppressesIncrementalRendering = false
        // Registered here because a scheme handler can only be attached to a
        // configuration BEFORE the web view is built; there is no adding one
        // later.
        config.setURLSchemeHandler(inlineImages, forURLScheme: InlineImageRewriter.scheme)
        self.webView = WKWebView(frame: .zero, configuration: config)

        super.init(nibName: nil, bundle: nil)

        // Added after `super.init` because it captures self. This is how a
        // tap on a collapsed letter reaches Swift.
        config.userContentController.add(self, name: "bmLetter")
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
        actionItems[.compose]?.isEnabled = true   // compose never depends on a selection
    }

    // MARK: - Content

    func showEmpty() {
        summary = nil
        message = nil
        entries = []
        loaded = [:]
        threadSummaries = [:]
        focused = nil
        title = ""
        header.isHidden = true
        webView.isHidden = true
        placeholder.isHidden = false
        setActionsEnabled(false)
    }

    func clearIfShowingDeletedMessage() { showEmpty() }

    func show(summary: MessageSummary) {
        self.summary = summary
        placeholder.isHidden = true
        header.isHidden = false
        webView.isHidden = false
        setActionsEnabled(true)

        Task { @MainActor in
            do {
                let m = try await repository.loadMessage(id: summary.id, mailboxID: summary.mailboxID)
                guard self.summary?.id == summary.id else { return }   // user moved on
                self.message = m
                header.configure(with: m)
                header.onSelectAttachment = { [weak self] in self?.openAttachment($0) }
                render(m)
            } catch {
                guard self.summary?.id == summary.id else { return }
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
                ErrorPresenter.show(.cannotConnect, on: self)
            }
        }
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

        // The header is given its content BEFORE the stack is rendered, the
        // same order the single-message path uses. It is not cosmetic: the
        // header's height is content-driven and the web view is pinned to
        // the bottom of it, so loading a document into a pane whose header
        // has not been sized yet gives the web view nothing to occupy.
        header.configure(with: Message(
            id: thread.newest.id, mailboxID: thread.newest.mailboxID,
            sender: thread.newest.sender,
            senderAddress: MailFormat.bareAddress(thread.newest.sender),
            to: [], cc: [], subject: thread.subject, date: thread.newest.date,
            textBody: nil, htmlBody: nil, attachments: []))
        view.layoutIfNeeded()

        entries = thread.messages.map { m in
            ConversationDocument.Entry(
                id: m.id, sender: m.sender, date: m.date, body: nil,
                // Newest open, everything else collapsed. Mail's own
                // choice, and the right one: the latest reply is what he
                // opened the conversation to read.
                isExpanded: m.id == thread.newest.id,
                preview: m.preview)
        }
        renderConversation()

        // Only the letter that is actually open is fetched. Fetching all of
        // them would be a round trip each for text he cannot see, down one
        // IMAP connection that everything else in the app is queuing on.
        Task { @MainActor in await self.loadBody(for: thread.newest.id, focus: true) }
    }

    private func renderConversation() {
        webView.loadHTMLString(
            ConversationDocument.html(entries: entries,
                                      inset: Int(Theme.detailContentInsetLeft),
                                      bodyPointSize: Int(Theme.scaled(17)),
                                      lineHeight: Theme.detailBodyLineHeight),
            baseURL: nil)
    }

    /// Fetches one letter of the conversation and puts it in its section.
    @MainActor
    private func loadBody(for id: String, focus: Bool) async {
        guard let row = threadSummaries[id] else { return }

        let m: Message
        if let already = loaded[id] {
            m = already
        } else {
            do {
                m = try await repository.loadMessage(id: id, mailboxID: row.mailboxID)
            } catch {
                // Said in the section rather than only in an alert, for the
                // same reason as the single-message path: a letter that
                // silently stays empty looks like a letter with nothing in
                // it. See B-026.
                fill(id: id, html: "<span class=\"bm-waiting\">This message could not "
                     + "be downloaded. Tap the line above twice to try again.</span>",
                     isHTML: false)
                return
            }
            // Still the same conversation? He may have moved on while this
            // was in flight.
            guard threadSummaries[id] != nil else { return }
            loaded[id] = m
        }

        let known = prepareInlineImages(for: m)
        let isHTML = m.htmlBody != nil
        let empty = MailText.hasNoVisibleContent(text: m.textBody, html: m.htmlBody)
        let content = empty
            ? "<span class=\"bm-waiting\">\(MailText.emptyBodyNotice)</span>"
            : (isHTML
               ? InlineImageRewriter.rewrite(stripDocumentWrapper(m.htmlBody!), known: known)
               : ConversationDocument.escape(leadingBlankLinesTrimmed(m.textBody ?? "")))
        fill(id: id, html: content, isHTML: isHTML && !empty)

        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].body = .init(html: content, isHTML: isHTML)
        }
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

    private func fill(id: String, html: String, isHTML: Bool) {
        webView.evaluateJavaScript(
            ConversationDocument.javascriptFill(
                sectionID: ConversationDocument.sectionID(for: id),
                html: html, isHTML: isHTML))
    }

    /// A letter in the stack was opened or closed.
    func userContentController(_ controller: WKUserContentController,
                               didReceive scriptMessage: WKScriptMessage) {
        guard scriptMessage.name == "bmLetter",
              let payload = scriptMessage.body as? [String: Any],
              let sectionID = payload["id"] as? String,
              let opened = payload["open"] as? Bool, opened,
              // Back from the section id to the message id. Matched rather
              // than unescaped, because the mapping loses which underscores
              // were slashes.
              let id = threadSummaries.keys.first(where: {
                  ConversationDocument.sectionID(for: $0) == sectionID
              })
        else { return }

        Task { @MainActor in
            await self.loadBody(for: id, focus: true)
            // Reading a letter marks THAT letter read, not the thread. The
            // unread count is how he knows what is still waiting, and
            // emptying it for a conversation he has read one line of would
            // take that away.
            // Read back, mutated, written back, rather than
            // `threadSummaries[id]?.isRead = true`. The optional-chained
            // subscript compiles to a `_modify` coroutine accessor, and
            // this toolchain's iOS 16.5 runtime has no
            // `swift_coroFrameAlloc` to link it against — the same wall
            // that makes debug builds of this app unlinkable.
            if var row = self.threadSummaries[id], !row.isRead {
                row.isRead = true
                self.threadSummaries[id] = row
                try? await self.repository.setRead(true, id: id,
                                                   mailboxID: row.mailboxID)
                self.onNeedsListRefresh?()
            }
        }
    }

    /// Leading blank lines dropped, as the single-message path does — this
    /// app's own replies open with two newlines so there is room to type
    /// above the quote, and they are really sent.
    private func leadingBlankLinesTrimmed(_ text: String) -> String {
        String(text.drop(while: { $0 == "\n" || $0 == "\r" }))
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
        let paragraphs = lines
            .map { "<p style=\"font-size:17px;\">\(ConversationDocument.escape($0))</p>" }
            .joined()
        let html = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="margin:0;background:#000;">
        <div style="font:-apple-system-body;color:#8e8e8e;padding:24px;">
        \(paragraphs)
        </div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
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
            defer { header.setAttachment(attachment.id, busy: false) }
            do {
                let data = try await repository.fetchAttachmentData(
                    attachment.id, of: m.id, mailboxID: m.mailboxID)
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

    /// Strips a sender's own `<html>`/`<head>`/`<body>` wrapper.
    ///
    /// This is not tidiness, it is the fix for a real and near-universal bug.
    /// WebKit merges an inner `<body>`'s attributes onto the outer one, and an
    /// inline style beats a stylesheet — so a message whose body tag carries
    /// `style="padding: 0"` silently cancelled our padding and the letter
    /// rendered flush against the pane divider while the header above it stayed
    /// inset. Almost every real HTML email ships a styled body tag, so this was
    /// not an edge case. With the wrapper gone a sender cannot set the letter's
    /// margin or type size at all.
    private func stripDocumentWrapper(_ html: String) -> String {
        var s = html
        for pattern in ["<!DOCTYPE[^>]*>", "</?html[^>]*>", "<head[^>]*>[\\s\\S]*?</head>",
                        "</?body[^>]*>"] {
            s = s.replacingOccurrences(of: pattern, with: "",
                                       options: [.regularExpression, .caseInsensitive])
        }
        return s
    }

    /// Points the loader at this message's parts, and returns the ids it can
    /// actually serve.
    ///
    /// Re-pointed per message rather than held once, because a `Content-ID`
    /// only means anything inside the message that declared it — two letters
    /// can both contain `cid:image001.png` and mean different pictures.
    private func prepareInlineImages(for m: Message) -> Set<String> {
        var sections: [String: (section: String, mimeType: String)] = [:]
        for attachment in m.attachments {
            guard let cid = attachment.contentID else { continue }
            sections[cid] = (attachment.id, attachment.mimeType)
        }

        inlineImages.fetch = { [weak self] contentID in
            // Never surfaced to him: the loader turns a throw into an empty
            // 404 so the picture is simply absent rather than an alert.
            guard let self, let part = sections[contentID] else {
                throw MailError.attachmentFailed
            }
            let data = try await self.repository.fetchAttachmentData(
                part.section, of: m.id, mailboxID: m.mailboxID)
            return (data, part.mimeType)
        }
        return Set(sections.keys)
    }

    private func render(_ m: Message) {
        let isHTML = m.htmlBody != nil
        // Leading blank lines are dropped from PLAIN TEXT before rendering.
        //
        // Not cosmetic tidying — it is this app's own doing coming back.
        // `Draft.replying` and `Draft.forwarding` both open a letter with
        // two newlines so there is room to type ABOVE the quoted part, and
        // those newlines are really sent. Reading such a letter back
        // therefore started it about eighty points down an otherwise empty
        // pane, which on the screen where he actually reads is the most
        // expensive space in the product. Measured against a forward whose
        // header block ended at y 355 and whose first words began at 470.
        //
        // Nothing is lost: blank lines before the first word carry no
        // meaning. HTML is left exactly alone, because whitespace there is
        // not reliably whitespace and the document may open with a layout
        // table.
        let known = prepareInlineImages(for: m)
        // Said out loud, so that a pane with nothing in it can only ever
        // mean a bug. See MailText.hasNoVisibleContent and B-026.
        guard !MailText.hasNoVisibleContent(text: m.textBody, html: m.htmlBody) else {
            renderNotice(MailText.emptyBodyNotice)
            return
        }
        let content = isHTML
            ? InlineImageRewriter.rewrite(stripDocumentWrapper(m.htmlBody!), known: known)
            : (m.textBody ?? "")
                .drop(while: { $0 == "\n" || $0 == "\r" })
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")

        // Every property lives on #bm, a container the inner document cannot
        // reach, rather than on `body` where a sender's inline style outranks
        // it. The viewport rule is what stops a desktop-width newsletter from
        // needing horizontal scrolling, which `ACCEPTANCE_TESTS.md` calls out by name.
        // Dark body. Plain text is simply light-on-black, but an HTML message
        // carries its OWN colours — almost always dark text assuming a white
        // page — so forcing a black background behind it would give unreadable
        // black-on-black, or white islands if the sender sets their own.
        //
        // So HTML gets inverted the way Smart Invert was doing it, in CSS:
        // invert the lot, then hue-rotate to put the colours back the right way
        // round, then invert images and video AGAIN to cancel it for them. That
        // is exactly the trick that keeps a photograph looking like a
        // photograph while the text around it goes light-on-dark.
        let smartInvert = isHTML
            ? """
              #bm { filter: invert(1) hue-rotate(180deg); background: #fff; }
              #bm img, #bm video, #bm svg, #bm picture, #bm [style*="background-image"] {
                  filter: invert(1) hue-rotate(180deg); }
              """
            : ""
        let wrapped = """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html { -webkit-text-size-adjust: 100%; }
          html, body { margin: 0; padding: 0; background: #000; }
          #bm { padding: \(Int(Theme.detailContentInsetLeft))px;
                font: \(Int(Theme.scaled(17)))px -apple-system, sans-serif;
                line-height: \(Theme.detailBodyLineHeight);
                color: \(isHTML ? "#000" : "#fff"); word-wrap: break-word;\
        \(isHTML ? "" : " white-space: pre-wrap;") }
          img, table { max-width: 100% !important; height: auto; }
          a { color: \(isHTML ? "#007AFF" : "#0A84FF"); }
          \(smartInvert)
        </style></head><body><div id="bm">\(content)</div></body></html>
        """
        webView.loadHTMLString(wrapped, baseURL: nil)
    }

    func webView(_ w: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        Diagnostics.log(.note, "webview: load failed \((error as NSError).code)")
    }

    /// Links open in Safari after a confirmation, and never navigate the pane
    /// itself. A message view that silently turns into a web page is how
    /// someone ends up lost with no way back.
    func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let url = action.request.url else {
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
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

    @objc private func flagTapped() {
        guard var s = summary else { return }
        s.isFlagged.toggle()
        summary = s
        Task { try? await repository.setFlagged(s.isFlagged, id: s.id, mailboxID: s.mailboxID) }
        onNeedsListRefresh?()
    }

    @objc private func moveTapped() {
        guard let s = summary else { return }
        let move = MoveMessageViewController(repository: repository,
                                             excluding: s.mailboxID) { [weak self] destination in
            guard let self else { return }
            Task { @MainActor in
                do {
                    try await self.repository.move(s.id, from: s.mailboxID, to: destination.id)
                    self.showEmpty()
                    self.onNeedsListRefresh?()
                } catch {
                    ErrorPresenter.show(.cannotConnect, on: self)
                }
            }
        }
        let nav = UINavigationController(rootViewController: move)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    @objc private func deleteTapped() {
        guard let s = summary else { return }
        Task { @MainActor in
            do {
                try await repository.delete(s.id, from: s.mailboxID)
                showEmpty()
                onNeedsListRefresh?()
            } catch {
                ErrorPresenter.show(.cannotConnect, on: self)
            }
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
    private func openCompose(replyTo m: Message?, all: Bool, forward: Bool) {
        let account = CredentialStore.loadAccount()
        let signature = account?.signature ?? ""
        var draft = Draft.blank(signature: signature)
        if let m {
            draft = forward
                ? .forwarding(m, signature: signature)
                : .replying(to: m, all: all, myAddress: account?.address,
                            signature: signature)
        }
        let compose = ComposeViewController(repository: repository, draft: draft)
        let nav = UINavigationController(rootViewController: compose)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
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
        // `NSURL` conforms to QLPreviewItem already. Force-unwrapping is safe
        // against the count above, which is 0 whenever this is nil.
        previewURL! as NSURL
    }
}

#endif
