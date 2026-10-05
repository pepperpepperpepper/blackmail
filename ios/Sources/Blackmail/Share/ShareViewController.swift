// Guarded so this file compiles away on a host without UIKit. What the
// sheet does is `ShareSheet`, which the host suite runs; this is the glass.
#if canImport(UIKit)

import UIKit
import UniformTypeIdentifiers

/// The share extension (B-036): what Safari, YouTube or Photos show when
/// Blackmail is chosen in the share sheet.
///
/// Mail's share sheet is the model. A small composer comes up over the app
/// he is in, with the page's title as the subject and the link in the body
/// above his signature; he picks who it goes to and taps Send, and the
/// letter goes from here, by the app's own `Submission`, without the app
/// being opened. It is not a second copy of the app's composer: To, Cc/Bcc,
/// Subject, the body and what was shared, and nothing else.
///
/// The principal class named in ShareInfo.plist, hence `public` and the
/// fixed Objective-C name: the extension's executable is only an entry
/// point, and a Swift class without `@objc(...)` has a mangled name the
/// host cannot find.
@objc(ShareViewController)
public final class ShareViewController: UIViewController {

    private let nav = UINavigationController()
    private var form: ShareComposeViewController?

    public override func viewDidLoad() {
        super.viewDidLoad()
        // Dark, as the app always is (D-010), whatever the app it is shared
        // from looks like.
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = Theme.canvas
        styleBar(nav.navigationBar)
        addChild(nav)
        nav.view.frame = view.bounds
        nav.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(nav.view)
        nav.didMove(toParent: self)

        // Files a share staged last time live in this extension's own
        // temporary directory, which nothing else ever clears.
        AttachmentStore.purge()

        guard let shared = ShareMirror.device.load() else {
            nav.setViewControllers([ShareUnavailableViewController(
                words: "Open Blackmail once, then share this again.") { [weak self] in
                    self?.cancel()
                }], animated: false)
            return
        }
        let waiting = UIViewController()
        waiting.view.backgroundColor = Theme.canvas
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        waiting.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        waiting.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        nav.setViewControllers([waiting], animated: false)

        ShareItems.load(from: extensionContext) { [weak self] items, leftOut in
            self?.show(items, leftOut: leftOut, shared: shared)
        }
    }

    /// The letter, with a line over it for a picture that could not be
    /// attached; or, when nothing came of a share of pictures alone, the
    /// words and Cancel, and no letter to send without them
    /// (`ShareItems.leftOut`).
    private func show(_ items: [SharedItem], leftOut: ShareItems.LeftOut?,
                      shared: ShareMirror.Shared) {
        if case .instead(let words) = leftOut {
            nav.setViewControllers([ShareUnavailableViewController(words: words) { [weak self] in
                self?.cancel()
            }], animated: false)
            return
        }
        var line: String?
        if case .line(let words) = leftOut { line = words }
        let form = ShareComposeViewController(
            shared: shared, items: items, leftOut: line,
            finish: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            },
            cancel: { [weak self] in self?.cancel() })
        self.form = form
        nav.setViewControllers([form], animated: false)
    }

    @objc private func cancelTapped() { cancel() }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain,
                                                           code: NSUserCancelledError))
    }

    /// The app's bar, as `RootViewController` styles it, set on this one
    /// bar rather than through the appearance proxy.
    private func styleBar(_ bar: UINavigationBar) {
        let look = UINavigationBarAppearance()
        look.configureWithOpaqueBackground()
        look.backgroundColor = Theme.barFill
        look.shadowColor = Theme.separator
        look.titleTextAttributes = [.font: Theme.fontNavTitle, .foregroundColor: Theme.primaryText]
        bar.standardAppearance = look
        bar.scrollEdgeAppearance = look
        bar.compactAppearance = look
        bar.tintColor = Theme.tintBlue
        bar.prefersLargeTitles = false
    }
}

/// One sentence and a way out, where there is no letter to show: no account
/// to send as, none set up or the app not opened since the build that hands
/// one over; or nothing came of a share of pictures alone.
private final class ShareUnavailableViewController: UIViewController {
    private let words: String
    private let close: () -> Void

    init(words: String, close: @escaping () -> Void) {
        self.words = words
        self.close = close
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.canvas
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel", style: .plain, target: self, action: #selector(closeTapped))
        let label = UILabel()
        label.text = words
        label.font = .systemFont(ofSize: Theme.scaled(17))
        label.textColor = Theme.primaryText
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
        ])
    }

    @objc private func closeTapped() { close() }
}

/// The small composer. Cancel fixed left, Send fixed right, as in the app.
final class ShareComposeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private var draft: Draft
    private var sheet: ShareSheet!
    /// "1 photo could not be attached.", or nil (`ShareItems.leftOut`).
    private let leftOut: String?

    private let toField = UITextField()
    private let ccField = UITextField()
    private let bccField = UITextField()
    private let subjectField = UITextField()
    private let bodyView = UITextView()
    private let attachmentsStack = UIStackView()
    private var ccRow = UIView()
    private var bccRow = UIView()
    private let ccToggle = UIButton(type: .system)

    private let suggestionsView = UITableView(frame: .zero, style: .plain)
    private var suggestions: [KnownRecipient] = []
    private weak var activeAddressField: UITextField?

    private lazy var sendItem = UIBarButtonItem(
        title: "Send", style: .done, target: self, action: #selector(sendTapped))
    /// "Sending…" and a spinner where Send was, in the text's own colour,
    /// as the app's composer draws them.
    private lazy var sendingWordsItem: UIBarButtonItem = {
        let item = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
        item.isEnabled = false
        item.setTitleTextAttributes(
            [.font: UIFont.monospacedDigitSystemFont(ofSize: Theme.fontBarButton.pointSize,
                                                     weight: .regular),
             .foregroundColor: Theme.primaryText],
            for: .disabled)
        return item
    }()
    private let sendingSpinner = UIActivityIndicatorView(style: .medium)
    private lazy var sendingSpinnerItem = UIBarButtonItem(customView: sendingSpinner)

    init(shared: ShareMirror.Shared, items: [SharedItem], leftOut: String?,
         finish: @escaping () -> Void, cancel: @escaping () -> Void) {
        draft = Draft()
        self.leftOut = leftOut
        super.init(nibName: nil, bundle: nil)
        sheet = ShareSheet(
            shared: shared,
            transport: TLSConnection.factory,
            memory: { SharedPhoto.memory() },
            noteSent: { ShareMirror.device.noteSent($0) },
            finish: finish,
            cancel: cancel,
            showError: { [weak self] error in
                guard let self else { return }
                ErrorPresenter.show(error, on: self)
            },
            draw: { [weak self] look in self?.draw(look) },
            background: .extensionTime)
        draft = sheet.letter(from: items)
        title = draft.subject.isEmpty ? "New Message" : draft.subject
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.canvas
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = sendItem
        for item in [navigationItem.leftBarButtonItem, sendItem] {
            item?.setTitleTextAttributes([.font: Theme.fontBarButton], for: .normal)
        }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        stack.addArrangedSubview(row("To:", toField, draft.to.joined(separator: ", ")))
        // Straight into the stack as ARRANGED subviews, never wrapped: see
        // `ComposeViewController.ccRow` for what a wrapper did to Cc.
        ccRow = row("Cc:", ccField, draft.cc.joined(separator: ", "))
        bccRow = row("Bcc:", bccField, draft.bcc.joined(separator: ", "))
        ccRow.isHidden = !draft.showsCcAndBcc
        bccRow.isHidden = !draft.showsCcAndBcc
        stack.addArrangedSubview(ccRow)
        stack.addArrangedSubview(bccRow)

        ccToggle.setTitle("Cc/Bcc", for: .normal)
        ccToggle.titleLabel?.font = Theme.fontDetailMeta
        ccToggle.contentHorizontalAlignment = .left
        ccToggle.addTarget(self, action: #selector(toggleCc), for: .touchUpInside)
        ccToggle.translatesAutoresizingMaskIntoConstraints = false
        let toggleRow = UIView()
        toggleRow.addSubview(ccToggle)
        NSLayoutConstraint.activate([
            ccToggle.leadingAnchor.constraint(equalTo: toggleRow.leadingAnchor,
                                              constant: Theme.detailContentInsetLeft),
            ccToggle.topAnchor.constraint(equalTo: toggleRow.topAnchor),
            ccToggle.bottomAnchor.constraint(equalTo: toggleRow.bottomAnchor),
            ccToggle.heightAnchor.constraint(equalToConstant: Theme.minHitTarget),
        ])
        stack.addArrangedSubview(toggleRow)
        stack.addArrangedSubview(row("Subject:", subjectField, draft.subject))
        // Above what is attached, where he looks for the photo he chose.
        if let leftOut { stack.addArrangedSubview(note(leftOut)) }

        attachmentsStack.axis = .vertical
        // Zero height, preferred not required, for the reason the app's
        // composer gives (B-027): an empty stack has no height of its own.
        let flat = attachmentsStack.heightAnchor.constraint(equalToConstant: 0)
        flat.priority = .defaultLow
        flat.isActive = true
        stack.addArrangedSubview(attachmentsStack)
        rebuildAttachments()

        bodyView.font = .systemFont(ofSize: Theme.scaled(17))
        bodyView.text = draft.body
        bodyView.backgroundColor = Theme.canvas
        bodyView.textColor = Theme.primaryText
        bodyView.textContainerInset = UIEdgeInsets(top: 12, left: Theme.detailContentInsetLeft - 5,
                                                   bottom: 12, right: Theme.detailContentInsetLeft - 5)
        bodyView.smartDashesType = .no
        bodyView.smartQuotesType = .no
        bodyView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bodyView)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bodyView.topAnchor.constraint(equalTo: stack.bottomAnchor),
            bodyView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bodyView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        suggestionsView.dataSource = self
        suggestionsView.delegate = self
        suggestionsView.rowHeight = Theme.suggestionRowHeight
        suggestionsView.backgroundColor = Theme.barFill
        suggestionsView.separatorColor = Theme.separator
        suggestionsView.layer.borderWidth = 0.5
        suggestionsView.layer.borderColor = Theme.separator.cgColor
        suggestionsView.isHidden = true
        suggestionsView.register(UITableViewCell.self, forCellReuseIdentifier: "suggestion")
        view.addSubview(suggestionsView)
    }

    /// Straight to To, where the one thing he has to do is, with his most
    /// used addresses already offered under it.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if draft.to.isEmpty { toField.becomeFirstResponder() }
    }

    private func row(_ text: String, _ field: UITextField, _ value: String) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = text
        label.font = Theme.fontDetailMeta
        label.textColor = Theme.secondaryText
        field.text = value
        field.font = .systemFont(ofSize: Theme.scaled(17))
        field.textColor = Theme.primaryText
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        if field !== subjectField {
            // The email keyboard, with "@" on its first layer, for the
            // reason the app's composer gives.
            field.keyboardType = .emailAddress
            field.addTarget(self, action: #selector(addressEditing(_:)), for: .editingDidBegin)
            field.addTarget(self, action: #selector(addressEditing(_:)), for: .editingChanged)
            field.addTarget(self, action: #selector(addressEditingEnded(_:)), for: .editingDidEnd)
        }
        let rule = UIView()
        rule.backgroundColor = Theme.separator
        for v in [label, field, rule] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                           constant: Theme.detailContentInsetLeft),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 72),
            field.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                            constant: -Theme.detailContentInsetLeft),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: Theme.minHitTarget),
            rule.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                          constant: Theme.detailContentInsetLeft),
            rule.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        return container
    }

    // MARK: - What was shared

    /// A plain line in a row of its own, as a file's row is laid out
    /// without Remove, in the text's own colour.
    private func note(_ words: String) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = words
        label.font = Theme.fontDetailMeta
        label.textColor = Theme.primaryText
        let rule = UIView()
        rule.backgroundColor = Theme.separator
        for v in [label, rule] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                           constant: Theme.detailContentInsetLeft),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor,
                                            constant: -Theme.detailContentInsetLeft),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: Theme.minHitTarget),
            rule.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                          constant: Theme.detailContentInsetLeft),
            rule.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        return container
    }

    /// A row per file: its name, its weight, and Remove.
    private func rebuildAttachments() {
        for view in attachmentsStack.arrangedSubviews {
            attachmentsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, attachment) in draft.attachments.enumerated() {
            let container = UIView()
            let label = UILabel()
            label.font = Theme.fontDetailMeta
            label.textColor = Theme.secondaryText
            label.text = attachment.size.map {
                attachment.filename + "  —  "
                    + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
            } ?? attachment.filename
            let remove = UIButton(type: .system)
            remove.setTitle("Remove", for: .normal)
            remove.titleLabel?.font = Theme.fontDetailMeta
            remove.setTitleColor(Theme.destructive, for: .normal)
            remove.setTitleColor(Theme.secondaryText, for: .disabled)
            remove.tag = index
            remove.isEnabled = !sheet.isSending
            remove.addTarget(self, action: #selector(removeAttachment(_:)), for: .touchUpInside)
            let rule = UIView()
            rule.backgroundColor = Theme.separator
            for v in [label, remove, rule] {
                v.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(v)
            }
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                               constant: Theme.detailContentInsetLeft),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                remove.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor,
                                                constant: 8),
                remove.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                                 constant: -Theme.detailContentInsetLeft),
                remove.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                remove.widthAnchor.constraint(greaterThanOrEqualToConstant: Theme.minHitTarget),
                container.heightAnchor.constraint(equalToConstant: Theme.minHitTarget),
                rule.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                              constant: Theme.detailContentInsetLeft),
                rule.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                rule.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                rule.heightAnchor.constraint(equalToConstant: 0.5),
            ])
            attachmentsStack.addArrangedSubview(container)
        }
    }

    @objc private func removeAttachment(_ sender: UIButton) {
        guard !sheet.isSending, sender.tag < draft.attachments.count else { return }
        draft.attachments.remove(at: sender.tag)
        rebuildAttachments()
    }

    // MARK: - Addresses

    @objc private func addressEditing(_ field: UITextField) {
        activeAddressField = field
        suggestions = sheet.suggestions(for: field.text ?? "")
        suggestionsView.reloadData()
        if let row = field.superview, let frame = row.superview?.convert(row.frame, to: view) {
            suggestionsView.frame = CGRect(x: frame.minX, y: frame.maxY, width: frame.width,
                                           height: CGFloat(suggestions.count) * Theme.suggestionRowHeight)
        }
        view.bringSubviewToFront(suggestionsView)
        suggestionsView.isHidden = suggestions.isEmpty
    }

    /// Deferred a turn, so a tap on a suggestion lands before the list goes.
    @objc private func addressEditingEnded(_ field: UITextField) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !(self.activeAddressField?.isEditing ?? false) else { return }
            self.suggestionsView.isHidden = true
        }
    }

    func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { suggestions.count }

    func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = t.dequeueReusableCell(withIdentifier: "suggestion", for: ip)
        let entry = suggestions[ip.row]
        var config = cell.defaultContentConfiguration()
        config.text = entry.display
        config.textProperties.font = Theme.fontListSender
        config.textProperties.color = Theme.primaryText
        config.secondaryText = entry.display == entry.address ? nil : entry.address
        config.secondaryTextProperties.font = Theme.fontDetailMeta
        config.secondaryTextProperties.color = Theme.secondaryText
        cell.contentConfiguration = config
        cell.backgroundColor = Theme.barFill
        return cell
    }

    func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        guard let field = activeAddressField, ip.row < suggestions.count else { return }
        field.text = MailFormat.replacingRecipientToken(in: field.text ?? "",
                                                        with: suggestions[ip.row].address)
        t.deselectRow(at: ip, animated: false)
        addressEditing(field)
    }

    @objc private func toggleCc() {
        ccRow.isHidden.toggle()
        bccRow.isHidden = ccRow.isHidden
    }

    // MARK: - Send and Cancel

    /// No Save Draft: a shared link is shared again in two taps, and a
    /// draft would need the whole mailbox connection this sheet does not
    /// open. Nothing he has written is thrown away unasked, though
    /// (`ShareSheet.asksBeforeCancelling`).
    @objc private func cancelTapped() {
        guard !sheet.isSending else { return }
        collect()
        guard sheet.asksBeforeCancelling(draft) else { sheet.cancel(); return }
        let confirm = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        confirm.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
        confirm.addAction(UIAlertAction(title: "Delete Draft", style: .destructive) { [weak self] _ in
            self?.sheet.cancel()
        })
        confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(confirm, animated: true)
    }

    @objc private func sendTapped() {
        guard !sheet.isSending else { return }
        if let shown = presentedViewController, !shown.isBeingDismissed {
            shown.dismiss(animated: true)
        }
        view.endEditing(true)
        collect()
        sheet.send { [unowned self] in self.draft }
    }

    private func draw(_ look: ComposeActions.Look) {
        let sending: Bool
        switch look {
        case .writing:
            sending = false
            sendingSpinner.stopAnimating()
            navigationItem.rightBarButtonItems = [sendItem]
        case .sending(let words):
            sending = true
            sendingWordsItem.title = words
            if navigationItem.rightBarButtonItems?.first !== sendingWordsItem {
                sendingSpinner.startAnimating()
                navigationItem.rightBarButtonItems = [sendingWordsItem, sendingSpinnerItem]
            }
        }
        navigationItem.leftBarButtonItem?.isEnabled = !sending
        for row in attachmentsStack.arrangedSubviews {
            for case let remove as UIButton in row.subviews { remove.isEnabled = !sending }
        }
        isModalInPresentation = sending
        navigationController?.isModalInPresentation = sending
        navigationController?.parent?.isModalInPresentation = sending
    }

    private func collect() {
        draft.to = MailFormat.addresses(in: toField.text ?? "")
        draft.cc = MailFormat.addresses(in: ccField.text ?? "")
        draft.bcc = MailFormat.addresses(in: bccField.text ?? "")
        draft.subject = subjectField.text ?? ""
        draft.body = bodyView.text ?? ""
    }
}

/// What a share hands over, read out of the extension's input items in the
/// order they came, one at a time (`ShareItems`).
extension ShareItems {

    /// `completion` has what came, and what the sheet says of a picture
    /// that did not (`leftOut`).
    static func load(from context: NSExtensionContext?,
                     completion: @escaping @MainActor ([SharedItem], LeftOut?) -> Void) {
        let inputs = (context?.inputItems as? [NSExtensionItem]) ?? []
        let staging = Staging()
        let tally = Tally()
        var loads: [(@escaping (SharedItem?) -> Void) -> Void] = []

        for item in inputs {
            // The subject a sharing app offers, as Mail takes it: the
            // item's title, or failing that the words it came with.
            let title = [item.attributedTitle?.string, item.attributedContentText?.string]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            for provider in item.attachments ?? [] {
                tally.offered += 1
                loads.append { done in
                    read(provider, title: title, staging: staging, tally: tally, done: done)
                }
            }
        }
        // Where this share's lines begin. iOS may keep the extension
        // running from one share to the next, and the log is not cleared
        // between them: a send's transcript can hold the share before too.
        Diagnostics.log(.note, "SHARE-BEGIN offered=\(loads.count)")
        oneAtATime(loads) { items in
            let leftOut = tally.leftOut
            Task { @MainActor in completion(items, leftOut) }
        }
    }

    /// A picture first, as Apple Mail sends it: a JPEG as its own bytes,
    /// under its file's name, its metadata replaced; a GIF or PNG whole; any
    /// other made a JPEG of at most 4096 px, since an iPad keeps photos as
    /// HEIC, which many recipients cannot open (`picture`). Then a web
    /// address, then words, then any other file as it is. A file is staged
    /// before this calls back, so the next one is not begun while this
    /// one's bytes are still held.
    ///
    /// A picture is what the provider offers as one by its type
    /// (`SharedPhoto.fileType`), or, failing a type this knows, what
    /// `UIImage` could read, which is what decided it before. Each picture
    /// is counted, and each one attached (`Tally`).
    private static func read(_ provider: NSItemProvider, title: String?, staging: Staging,
                             tally: Tally, done: @escaping (SharedItem?) -> Void) {
        if let type = SharedPhoto.fileType(offered: provider.registeredTypeIdentifiers)
            ?? (provider.canLoadObject(ofClass: UIImage.self) ? UTType.image.identifier : nil) {
            tally.pictures += 1
            picture(provider, type: type, staging: staging) { item in
                if item != nil { tally.attached += 1 }
                done(item)
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                  !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { object, _ in
                let url = (object as? URL) ?? (object as? NSURL).map { $0 as URL }
                done(url.map { .link($0, title: title) })
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { object, _ in
                guard let text = (object as? String) ?? (object as? NSAttributedString)?.string
                else { return done(nil) }
                done(item(fromText: text, title: title))
            }
        } else if let first = provider.registeredTypeIdentifiers.first {
            // A video as QuickTime where it is offered, so the original
            // ".MOV" goes; counted, and said when it is left out (B-070).
            let movie = movieType(offered: provider.registeredTypeIdentifiers,
                                  isMovie: { UTType($0)?.conforms(to: .movie) == true })
            let type = movie ?? first
            if movie != nil { tally.videos += 1 }
            // The copy iOS hands over lasts only as long as this callback,
            // so it is staged here; by its size first, which a video can
            // make larger than the letter's room.
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                guard let url,
                      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                else {
                    Diagnostics.log(.note, fileNote(read: type, suggested: false, name: "",
                                                    mimeType: "-", bytes: 0, went: .notGiven))
                    return done(nil)
                }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                let name = filename(suggested: provider.suggestedName, for: url)
                let room = staging.room
                let item = staging.file(at: url, size: Int64(size), named: name, mimeType: mime)
                if item != nil, movie != nil { tally.videosAttached += 1 }
                // What its copy measured, where it was copied, which is what
                // decided it; the sharing app's word where it was not.
                let bytes = staging.lastMeasured ?? Int64(size)
                Diagnostics.log(.note, fileNote(
                    read: type, suggested: !(provider.suggestedName ?? "").isEmpty, name: name,
                    mimeType: mime, bytes: bytes,
                    went: fileWent(item, size: bytes, room: room)))
                done(item)
            }
        } else {
            done(nil)
        }
    }
}

extension BackgroundTime {

    /// An extension's: it has no `UIApplication` to ask, so it asks
    /// `ProcessInfo` for an expiring activity, the extension's way of
    /// keeping iOS from suspending it while a letter goes. The activity's
    /// block is held open on its own queue until the time is given back,
    /// and iOS saying it wants it back reaches `expired` on the main
    /// thread, which gives it back.
    static let extensionTime: BackgroundTime = {
        let activities = ExpiringActivities()
        return BackgroundTime(begin: { name, expired in activities.begin(name, expired) },
                              end: { id in activities.end(id) })
    }()
}

@MainActor
private final class ExpiringActivities {
    private var next = 0
    private var open: [Int: DispatchSemaphore] = [:]

    nonisolated init() {}

    func begin(_ name: String, _ expired: @escaping @MainActor () -> Void) -> Int? {
        next += 1
        let id = next
        let done = DispatchSemaphore(value: 0)
        open[id] = done
        ProcessInfo.processInfo.performExpiringActivity(withReason: name) { expiring in
            if expiring {
                done.signal()
                Task { @MainActor in expired() }
            } else {
                done.wait()
            }
        }
        return id
    }

    func end(_ id: Int) {
        open.removeValue(forKey: id)?.signal()
    }
}

#endif
