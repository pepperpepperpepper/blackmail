// Guarded so this file compiles away on a host without UIKit. What the
// sheet does is `ShareSheet`, which the host suite runs; this is the glass.
#if canImport(UIKit)

import UIKit
import UniformTypeIdentifiers
import AudioToolbox
import Intents

/// The share extension (B-036): what Safari, YouTube or Photos show when
/// Blackmail is chosen in the share sheet.
///
/// Mail's share sheet is the model. A small composer comes up over the app
/// he is in, with the page's title as the subject where the sharing app
/// hands one over (`ShareItems.name`, B-125), or a YouTube video's title
/// asked of YouTube where it hands over the link alone (`VideoTitle`,
/// B-126), and the link in the body
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
public final class ShareViewController: UIViewController,
                                        UIAdaptivePresentationControllerDelegate {

    private let nav = UINavigationController()
    private var form: ShareComposeViewController?
    /// The sheet's text size and Bold Text, in `Theme` before the form is
    /// made and again when either changes (B-166): the size Large whatever
    /// iOS hands the sheet (`TextSize.drawn`, Changed 2026-10-27), Bold
    /// Text as iOS has it. The extension has no `UIApplication` of its own
    /// to ask, as the app does (`TextSizes.app`): it reads its own traits,
    /// again as they change (`traitCollectionDidChange`) and as the sheet
    /// appears.
    private lazy var sizes = TextSizes(
        names: [UIContentSizeCategory.didChangeNotification,
                UIAccessibility.boldTextStatusDidChangeNotification],
        read: { [weak self] in TextSize(self?.traitCollection.preferredContentSizeCategory ?? .unspecified) },
        apply: { Theme.textSize = $0 })

    public override func viewDidLoad() {
        super.viewDidLoad()
        // The text size in `Theme` before anything of the sheet is made.
        _ = sizes
        // Dark, as the app always is (D-010), whatever the app it is shared
        // from looks like.
        overrideUserInterfaceStyle = .dark
        // Held, as the app's composer is: a swipe asks what Cancel asks
        // (`presentationControllerDidAttemptToDismiss`). A tap outside the
        // sheet is the sharing app's to answer, not this one's: it puts the
        // share away whatever this says, as seen on the simulator (B-069).
        isModalInPresentation = true
        view.backgroundColor = Theme.canvas
        styleBar(nav.navigationBar)
        // Cancel, Send and the rest keep their colour while a bubble's menu
        // or Cancel's question is up, as they do in the app's composer
        // (B-134). UIKit greys what lies under a popover only where the
        // view controller putting it up is the window's own, as this one
        // is in the extension; the app's composer is a sheet over the app,
        // as Mail's is, and UIKit leaves a sheet's colours as they are
        // (iOS 18.6, `-[UIPresentationController _enableOcclusion:]`). Set
        // on the bar as well, should UIKit ever take the navigation
        // controller for the one putting it up.
        nav.view.tintAdjustmentMode = .normal
        nav.navigationBar.tintAdjustmentMode = .normal
        addChild(nav)
        // The form laid out at Large, as the app's sheets are, whatever the
        // text size the sharing app hands it (B-166, Changed 2026-10-27).
        setOverrideTraitCollection(.heldTextSize, forChild: nav)
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
            shared: shared, items: items, leftOut: line, to: circle(),
            finish: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            },
            cancel: { [weak self] in self?.cancel() })
        self.form = form
        nav.setViewControllers([form], animated: false)
    }

    /// To, for a share opened from a circle at the top of the share sheet:
    /// the people iOS hands back with it, as Blackmail told it of them
    /// (`SentConversation`, B-163); nobody for a share opened from
    /// Blackmail's icon, which hands back nothing. The log says how many,
    /// and no address.
    private func circle() -> [String] {
        guard let intent = extensionContext?.intent as? INSendMessageIntent else { return [] }
        let people = (intent.recipients ?? []).compactMap { person -> MailFormat.Recipient? in
            guard let address = person.personHandle?.value else { return nil }
            let name = person.displayName == address ? nil : person.displayName
            return MailFormat.Recipient(name: name, address: address)
        }
        let to = SentConversation.to(people: people, identifier: intent.conversationIdentifier)
        Diagnostics.log(.note, "SHARE-SUGGESTION opened people=\(to.count)")
        return to
    }

    /// The window as well as this controller is dark, so what is put up
    /// over the sheet is dark too: Cancel's question, as a popover, drew
    /// light on the dark sheet with only this controller's style to go by.
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.window?.overrideUserInterfaceStyle = .dark
        presentationController?.delegate = self
        // Its traits are the sheet's by now (B-166).
        sizes.look()
    }

    /// A swipe at the sheet, which is held: the letter's Cancel, which asks
    /// only about words of his; the share put away while there is no letter.
    public func presentationControllerDidAttemptToDismiss(
        _ presentationController: UIPresentationController) {
        if let form { form.cancelTapped() } else { cancel() }
    }

    @objc private func cancelTapped() { cancel() }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain,
                                                           code: NSUserCancelledError))
    }

    /// The sheet's text size may have changed: read again, and the form
    /// drawn at it if it has (B-166).
    public override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            sizes.look()
        }
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
final class ShareComposeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
                                        UITextFieldDelegate, UITextViewDelegate {

    private var draft: Draft
    /// The body the share began as, which the sheet shows under an empty
    /// first line (`ShareLetter.shown`).
    private var began = ""
    private var sheet: ShareSheet!
    /// "1 photo could not be attached.", or nil (`ShareItems.leftOut`).
    private let leftOut: String?

    /// To, Cc and Bcc, a bubble for each recipient, as in the app's
    /// composer (B-076).
    private let toField = RecipientField()
    private let ccField = RecipientField()
    private let bccField = RecipientField()
    private let subjectField = UITextField()
    private let bodyView = UITextView()
    /// The fields and the body, scrolled as one, as in the app's composer.
    /// Its bottom is the keyboard's top.
    private let scroller = UIScrollView()
    /// How much of the sheet showed at the last layout, to tell when the
    /// keyboard has just come up over it.
    private var shownHeight: CGFloat = 0
    /// Whether the sheet's one chance to be made ready to type has come
    /// and gone (`readyToType`).
    private var readied = false
    /// Where `readyToType` put the caret, nil until it has: Subject, for a
    /// share from a circle whose YouTube title had not come yet, is left
    /// for the body once it does (`ShareSheet.bodyOnceNamed`, B-163).
    private var readiedInto: ComposeForm.FirstField?
    /// The YouTube video whose title is asked for the subject, nil when
    /// nothing is asked (`ShareSheet.videoToName`, B-126).
    private var video: URL?
    /// He has typed in Subject, so YouTube's title never goes there.
    private var subjectTyped = false
    private let attachmentsStack = UIStackView()
    private var ccRow = UIView()
    private var bccRow = UIView()
    private let ccToggle = UIButton(type: .system)
    /// The "Cc/Bcc" row, hidden while Cc and Bcc stand open, as in the
    /// app's composer and Mail (B-134).
    private let ccToggleRow = UIView()

    private let suggestionsView = UITableView(frame: .zero, style: .plain)
    private var suggestions: [KnownRecipient] = []
    private weak var activeAddressField: RecipientField?
    /// The type and the lines set from the text size, set again when it
    /// changes while the sheet is up, as in the app's composer (B-166).
    private let restyles = Restyles()

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

    /// `to` is who To begins with: the people of the circle the share was
    /// opened from, or nobody (B-163).
    init(shared: ShareMirror.Shared, items: [SharedItem], leftOut: String?, to: [String],
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
            // Mail's sent sound, as the app's composer plays it (B-100).
            sent: { AudioServicesPlaySystemSound(ComposeViewController.sentMailSound) },
            showError: { [weak self] error in
                guard let self else { return }
                ErrorPresenter.show(error, on: self)
            },
            draw: { [weak self] look in self?.draw(look) },
            background: .extensionTime,
            // A share with no files and no connection waits in the app's
            // Outbox, while the app opens (B-153).
            wait: { ShareMirror.device.wait($0) },
            appStops: { AppExpiry.containingApp.stops },
            // The circle the share was opened from, its people in To, and
            // his circles at the top of the share sheet, as the app's
            // letters make them too (B-163).
            circle: to,
            donate: SentConversation.donate)
        draft = sheet.letter(from: items)
        began = draft.body
        title = ComposeForm.title(subject: draft.subject)
        video = sheet.videoToName(in: items)
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
            item?.setTitleTextAttributes([.font: Theme.fontBarButton], for: .disabled)
        }

        scroller.translatesAutoresizingMaskIntoConstraints = false
        scroller.alwaysBounceVertical = true
        scroller.contentInsetAdjustmentBehavior = .never
        scroller.delegate = self
        view.addSubview(scroller)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(stack)

        stack.addArrangedSubview(addressRow("To:", toField, draft.to))
        // Straight into the stack as ARRANGED subviews, never wrapped: see
        // `ComposeViewController.ccRow` for what a wrapper did to Cc.
        ccRow = addressRow("Cc:", ccField, draft.cc)
        bccRow = addressRow("Bcc:", bccField, draft.bcc)
        ccRow.isHidden = !draft.showsCcAndBcc
        bccRow.isHidden = !draft.showsCcAndBcc
        stack.addArrangedSubview(ccRow)
        stack.addArrangedSubview(bccRow)

        // The app composer's "Cc/Bcc", as Mail's (B-134): it opens Cc and
        // Bcc with the caret in Cc and goes while they show.
        ccToggle.setTitle("Cc/Bcc", for: .normal)
        ccToggle.titleLabel?.font = Theme.fontDetailMeta
        ccToggle.contentHorizontalAlignment = .left
        ccToggle.addTarget(self, action: #selector(openCcAndBcc), for: .touchUpInside)
        ccToggle.translatesAutoresizingMaskIntoConstraints = false
        let toggleRow = ccToggleRow
        toggleRow.isHidden = draft.showsCcAndBcc
        toggleRow.addSubview(ccToggle)
        let toggleHeight = ccToggle.heightAnchor.constraint(equalToConstant: Theme.lineHeight)
        NSLayoutConstraint.activate([
            ccToggle.leadingAnchor.constraint(equalTo: toggleRow.leadingAnchor,
                                              constant: Theme.detailContentInsetLeft),
            ccToggle.topAnchor.constraint(equalTo: toggleRow.topAnchor),
            ccToggle.bottomAnchor.constraint(equalTo: toggleRow.bottomAnchor),
            toggleHeight,
        ])
        restyles.keep { [ccToggle] in
            ccToggle.titleLabel?.font = Theme.fontDetailMeta
            toggleHeight.constant = Theme.lineHeight
        }
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

        restyles.keep { [bodyView] in bodyView.font = .systemFont(ofSize: Theme.scaled(17)) }
        // What was shared under an empty first line, as Mail shows it.
        bodyView.text = ShareLetter.shown(draft.body)
        // The caret starts on that line, at the top, where Tab and Return
        // from Subject put it in Mail; set nowhere, it was at the end,
        // under the link and his signature.
        bodyView.selectedRange = NSRange(location: 0, length: 0)
        bodyView.backgroundColor = Theme.canvas
        bodyView.textColor = Theme.primaryText
        bodyView.accessibilityLabel = "Message"
        bodyView.textContainerInset = UIEdgeInsets(top: 12, left: Theme.detailContentInsetLeft - 5,
                                                   bottom: 12, right: Theme.detailContentInsetLeft - 5)
        // Smart Punctuation as Settings has it, as in the app's composer
        // and Mail's (B-121).
        bodyView.smartDashesType = .default
        bodyView.smartQuotesType = .default
        bodyView.translatesAutoresizingMaskIntoConstraints = false
        // As tall as its words, scrolled with the fields, as in the app's
        // composer.
        bodyView.isScrollEnabled = false
        bodyView.delegate = self
        scroller.addSubview(bodyView)

        let content = scroller.contentLayoutGuide
        let shown = scroller.frameLayoutGuide
        NSLayoutConstraint.activate([
            scroller.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroller.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroller.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Above the keyboard, as in the app's composer.
            scroller.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: shown.widthAnchor),
            bodyView.topAnchor.constraint(equalTo: stack.bottomAnchor),
            bodyView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bodyView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.heightAnchor.constraint(greaterThanOrEqualTo: shown.heightAnchor),
        ])

        suggestionsView.dataSource = self
        suggestionsView.delegate = self
        suggestionsView.rowHeight = Theme.scaled(Theme.suggestionRowHeight)
        suggestionsView.backgroundColor = Theme.barFill
        suggestionsView.separatorColor = Theme.separator
        suggestionsView.layer.borderWidth = 0.5
        suggestionsView.layer.borderColor = Theme.separator.cgColor
        suggestionsView.isHidden = true
        suggestionsView.register(UITableViewCell.self, forCellReuseIdentifier: "suggestion")
        view.addSubview(suggestionsView)
        // The sheet at its text size, again when it changes while it is up
        // (B-166).
        NotificationCenter.default.addObserver(self, selector: #selector(textSizeChanged),
                                               name: TextSizes.didChange, object: nil)

        subjectField.delegate = self
        subjectField.addTarget(self, action: #selector(subjectChanged), for: .editingChanged)
        updateSend()
        askForTheTitle()
    }

    /// The text size or Bold Text has changed while the sheet is up
    /// (`TextSizes`, B-166): as in the app's composer, every caption, field,
    /// line and the body at the new size, the files' rows made again, and
    /// the addresses offered at their new height. Cancel and Send keep
    /// theirs, as a bar's do.
    @objc private func textSizeChanged() {
        restyles.again()
        rebuildAttachments()
        suggestionsView.rowHeight = Theme.scaled(Theme.suggestionRowHeight)
        suggestionsView.reloadData()
        if let field = activeAddressField { place(under: field) }
        view.setNeedsLayout()
    }

    /// A YouTube video shared with nothing naming it: its title asked of
    /// YouTube, and put in Subject when it comes, as Mail has it from the
    /// YouTube app, if he has typed nothing there and Send has not been
    /// tapped (`ShareSheet.named`, B-126); and the caret the sheet put in
    /// Subject for it, To being filled from a circle, goes to the body
    /// (`ShareSheet.bodyOnceNamed`, B-163). Nothing waits for it; with no
    /// answer Subject stays empty. The log says how long it took and
    /// whether it was used, in numbers alone.
    private func askForTheTitle() {
        guard let video else { return }
        let asked = Date()
        Diagnostics.log(.note, "SHARE-TITLE asked")
        VideoTitle.ask(for: video, through: VideoTitle.web) { [weak self] subject in
            guard let self else { return }
            let named = self.sheet.named(subject, now: self.subjectField.text ?? "",
                                         typed: self.subjectTyped)
            if let named {
                self.subjectField.text = named
                self.title = ComposeForm.title(subject: named)
            }
            // And the caret the sheet put in Subject for it on to the body,
            // where Mail's sheet opens with the title there (B-163).
            if named != nil, ShareSheet.bodyOnceNamed(
                readiedInto: self.readiedInto,
                inSubject: self.subjectField.isFirstResponder && self.presentedViewController == nil) {
                self.bodyView.becomeFirstResponder()
                self.bodyView.selectedRange = NSRange(location: 0, length: 0)
                self.keepCaretInView()
            }
            let ms = Int(Date().timeIntervalSince(asked) * 1000)
            Diagnostics.log(.note, "SHARE-TITLE answered=\(subject == nil ? 0 : 1) "
                + "chars=\(subject?.count ?? 0) ms=\(ms) filled=\(named == nil ? 0 : 1)")
        }
    }

    /// The keyboard has come up over the sheet: the caret is brought into
    /// the part still showing, once the layout has settled.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let height = scroller.bounds.height
        defer { shownHeight = height }
        guard height < shownHeight, bodyView.isFirstResponder else { return }
        DispatchQueue.main.async { [weak self] in self?.keepCaretInView() }
    }

    /// The line he is on, in sight, the fields going up out of the way
    /// when there is too little room under them, as in the app's composer.
    private func keepCaretInView() {
        guard bodyView.isFirstResponder, let end = bodyView.selectedTextRange?.end else { return }
        view.layoutIfNeeded()
        let caret = bodyView.caretRect(for: end)
        guard !caret.isNull, !caret.isInfinite else { return }
        let line = bodyView.convert(caret, to: scroller)
            .insetBy(dx: 0, dy: -bodyView.textContainerInset.bottom)
        scroller.scrollRectToVisible(line, animated: false)
    }

    func textViewDidChange(_ textView: UITextView) {
        keepCaretInView()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        keepCaretInView()
    }

    /// The caret into the body: Cc and Bcc fold back if nobody is in them
    /// (`caretWentInto`, B-134).
    func textViewDidBeginEditing(_ textView: UITextView) {
        caretWentInto(ccOrBcc: false)
    }

    /// The caret into Subject: the same.
    func textFieldDidBeginEditing(_ textField: UITextField) {
        caretWentInto(ccOrBcc: false)
    }

    /// The list under an address field goes with the field.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === scroller, !suggestionsView.isHidden,
              let field = activeAddressField else { return }
        place(under: field)
    }

    /// The title follows the subject as he types it, as Mail's does.
    @objc private func subjectChanged() {
        subjectTyped = true
        title = ComposeForm.title(subject: subjectField.text ?? "")
    }

    /// Send is grey until To, Cc or Bcc holds an address, as in Mail.
    private func updateSend() {
        sendItem.isEnabled = ComposeForm.canSend(to: toField.recipients,
                                                 cc: ccField.recipients,
                                                 bcc: bccField.recipients)
    }

    /// Return in Subject goes to the body, the caret at its top, as in Mail.
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard textField === subjectField else { return true }
        bodyView.becomeFirstResponder()
        bodyView.selectedRange = NSRange(location: 0, length: 0)
        keepCaretInView()
        return false
    }

    /// Straight to To, where the one thing he has to do is. Nothing is
    /// offered under it until he types, as in Mail (B-073).
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        readyToType()
    }

    /// Ready to type by the rule of the app's composer, which is Mail's
    /// composer's, its share sheet's too (`ComposeForm.firstField`, B-120):
    /// a share from Blackmail's icon has nobody in To, so To; one from a
    /// circle has its people there (B-163), so Subject while it is empty,
    /// else the body. Once, the first time the sheet appears, never over
    /// Cancel's question and never once he is in a field himself
    /// (`ComposeForm.readiesOnAppearing`).
    private func readyToType() {
        let fields: [UIView] = [toField, ccField, bccField, subjectField, bodyView]
        let inAField = fields.contains { $0.isFirstResponder }
        defer { readied = true }
        guard ComposeForm.readiesOnAppearing(done: readied, covered: presentedViewController != nil,
                                             inAField: inAField) else { return }
        // Where the caret goes, kept for YouTube's title (`askForTheTitle`).
        readiedInto = ComposeForm.firstField(to: toField.recipients, subject: subjectField.text ?? "")
        switch ComposeForm.firstField(to: toField.recipients, subject: subjectField.text ?? "") {
        case .to:
            toField.becomeFirstResponder()
        case .subject:
            subjectField.becomeFirstResponder()
        case .body:
            bodyView.becomeFirstResponder()
            bodyView.selectedRange = NSRange(location: 0, length: 0)
            keepCaretInView()
        }
    }

    private func row(_ text: String, _ field: UITextField, _ value: String) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = text
        label.textColor = Theme.secondaryText
        field.text = value
        field.textColor = Theme.primaryText
        // "To", not "To:": the caption is a label of its own.
        field.accessibilityLabel = text.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        // Subject alone: it types as Mail's and the app's composer's do, a
        // capital to begin, corrections and Smart Punctuation, the system's
        // own (B-121). To, Cc and Bcc keep `RecipientField`'s.
        field.autocapitalizationType = .sentences
        field.autocorrectionType = .default
        field.smartDashesType = .default
        field.smartQuotesType = .default
        let rule = UIView()
        rule.backgroundColor = Theme.separator
        for v in [label, field, rule] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        let captionWidth = label.widthAnchor.constraint(equalToConstant: Theme.scaled(72))
        let height = container.heightAnchor.constraint(equalToConstant: Theme.lineHeight)
        // As in the app's composer (B-166).
        restyles.keep {
            label.font = Theme.fontDetailMeta
            field.font = .systemFont(ofSize: Theme.scaled(17))
            captionWidth.constant = Theme.scaled(72)
            height.constant = Theme.lineHeight
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                           constant: Theme.detailContentInsetLeft),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            captionWidth,
            field.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                            constant: -Theme.detailContentInsetLeft),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            height,
            rule.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                          constant: Theme.detailContentInsetLeft),
            rule.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        return container
    }

    /// To, Cc or Bcc: the caption, then the field of bubbles, a line of
    /// `lineHeight` for each line of them, as in the app's composer.
    private func addressRow(_ text: String, _ field: RecipientField, _ entries: [String]) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = text
        label.textColor = Theme.secondaryText
        field.show(entries)
        field.textColor = Theme.primaryText
        // "To", not "To:": the caption is a label of its own.
        field.accessibilityLabel = text.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        // The email keyboard is the field's own (`RecipientField`).
        field.addTarget(self, action: #selector(addressEntered(_:)), for: .editingDidBegin)
        field.addTarget(self, action: #selector(addressTyped(_:)), for: .editingChanged)
        field.addTarget(self, action: #selector(addressEditingEnded(_:)), for: .editingDidEnd)
        field.addTarget(self, action: #selector(addressBubbleTapped(_:)), for: .valueChanged)
        let rule = UIView()
        rule.backgroundColor = Theme.separator
        for v in [label, field, rule] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        let captionY = label.centerYAnchor.constraint(equalTo: container.topAnchor,
                                                      constant: Theme.lineHeight / 2)
        let captionWidth = label.widthAnchor.constraint(equalToConstant: Theme.scaled(72))
        restyles.keep {
            label.font = Theme.fontDetailMeta
            field.font = .systemFont(ofSize: Theme.scaled(17))
            captionY.constant = Theme.lineHeight / 2
            captionWidth.constant = Theme.scaled(72)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                           constant: Theme.detailContentInsetLeft),
            captionY,
            captionWidth,
            field.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                            constant: -Theme.detailContentInsetLeft),
            field.topAnchor.constraint(equalTo: container.topAnchor),
            field.bottomAnchor.constraint(equalTo: container.bottomAnchor),
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
        label.textColor = Theme.primaryText
        let rule = UIView()
        rule.backgroundColor = Theme.separator
        for v in [label, rule] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        let height = container.heightAnchor.constraint(equalToConstant: Theme.lineHeight)
        restyles.keep {
            label.font = Theme.fontDetailMeta
            height.constant = Theme.lineHeight
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                           constant: Theme.detailContentInsetLeft),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor,
                                            constant: -Theme.detailContentInsetLeft),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            height,
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
                container.heightAnchor.constraint(equalToConstant: Theme.lineHeight),
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

    /// Going in offers nothing, as in Mail (B-073), and closes a list left
    /// open under another field. Cc and Bcc fold back as the caret goes
    /// into To with nobody in them (`caretWentInto`, B-134).
    @objc private func addressEntered(_ field: RecipientField) {
        offer(field, after: .entered)
        caretWentInto(ccOrBcc: field === ccField || field === bccField)
    }

    /// A bubble tapped, its menu about to go up: the list closes and the
    /// caret goes into its field while a field has it, as in the app's
    /// composer, which says why (B-134).
    @objc private func addressBubbleTapped(_ field: RecipientField) {
        let fields: [UIView] = [toField, ccField, bccField, subjectField, bodyView]
        if !field.isFirstResponder, fields.contains(where: { $0.isFirstResponder }) {
            field.becomeFirstResponder()
        }
        offer(field, after: .bubbleTapped)
    }

    @objc private func addressTyped(_ field: RecipientField) {
        offer(field, after: .typed)
        updateSend()
    }

    /// What the field offers after `event` (`ShareSheet.suggestions`):
    /// matches only while he types; nothing as he goes in (B-073), and
    /// nothing after a pick until he types again.
    private func offer(_ field: RecipientField, after event: ComposeForm.FieldEvent) {
        activeAddressField = field
        suggestions = sheet.suggestions(in: field.bubbles, after: event)
        suggestionsView.reloadData()
        place(under: field)
        suggestionsView.isHidden = suggestions.isEmpty
    }

    /// The list just under the field's row, wherever the sheet has
    /// scrolled it.
    private func place(under field: RecipientField) {
        if let row = field.superview, let frame = row.superview?.convert(row.frame, to: view) {
            suggestionsView.frame = CGRect(x: frame.minX, y: frame.maxY, width: frame.width,
                                           height: CGFloat(suggestions.count)
                                               * Theme.scaled(Theme.suggestionRowHeight))
        }
        view.bringSubviewToFront(suggestionsView)
    }

    /// Deferred a turn, so a tap on a suggestion lands before the list goes.
    @objc private func addressEditingEnded(_ field: RecipientField) {
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
        // A bubble with its name, as in the app's composer (B-076).
        let picked = suggestions[ip.row]
        field.pick(MailFormat.recipient(name: picked.name, address: picked.address).entry)
        t.deselectRow(at: ip, animated: false)
        // Closed until he types again, as in Mail.
        offer(field, after: .picked)
        updateSend()
    }

    /// "Cc/Bcc": Cc and Bcc open, the row gone, the caret in Cc, as in the
    /// app's composer and Mail (B-134). It was a switch.
    @objc private func openCcAndBcc() {
        showCcAndBcc(true)
        ccField.becomeFirstResponder()
    }

    /// Cc and Bcc stand open while the caret is in one of them or either
    /// holds someone, and fold back into the "Cc/Bcc" row otherwise, by
    /// Mail's rule (`ComposeForm.showsCcAndBcc`).
    private func caretWentInto(ccOrBcc: Bool) {
        showCcAndBcc(ComposeForm.showsCcAndBcc(inCcOrBcc: ccOrBcc, cc: ccField.recipients,
                                               bcc: bccField.recipients))
    }

    /// Cc and Bcc shown, and the "Cc/Bcc" row hidden, or the other way.
    private func showCcAndBcc(_ open: Bool) {
        guard open == ccRow.isHidden else { return }
        ccRow.isHidden = !open
        bccRow.isHidden = !open
        ccToggleRow.isHidden = open
    }

    // MARK: - Send and Cancel

    /// No Save Draft: a shared link is shared again in two taps, and a
    /// draft would need the whole mailbox connection this sheet does not
    /// open. Nothing he has written is thrown away unasked, though
    /// (`ShareSheet.asksBeforeCancelling`). A swipe at the sheet comes
    /// here too (`ShareViewController`); while a letter goes, and while
    /// the question is up, it does nothing.
    @objc func cancelTapped() {
        guard !sheet.isSending, presentedViewController == nil else { return }
        collect()
        guard sheet.asksBeforeCancelling(draft) else { sheet.cancel(); return }
        let confirm = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        // Dark on the dark sheet (D-010). It drew light.
        confirm.overrideUserInterfaceStyle = .dark
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
        // The sheet is held throughout (`ShareViewController.viewDidLoad`),
        // and a swipe while a letter goes asks nothing (`cancelTapped`).
    }

    private func collect() {
        // A recipient for each bubble, as the app's composer reads them.
        draft.to = toField.recipients
        draft.cc = ccField.recipients
        draft.bcc = bccField.recipients
        draft.subject = subjectField.text ?? ""
        draft.body = ShareLetter.written(bodyView.text ?? "", began: began)
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
            // What names the share, its subject: the item's title, or
            // failing that its words, where Safari puts the page's title
            // (`ShareItems.name`, B-125). A YouTube link that comes with
            // neither has its title asked of YouTube as the sheet comes up
            // (`VideoTitle`, B-126).
            let title = ShareItems.name(title: item.attributedTitle?.string,
                                        words: item.attributedContentText?.string)
            for provider in item.attachments ?? [] {
                tally.offered += 1
                loads.append { done in
                    // A video as the sharing app hands it over, and nothing
                    // made of it here (`videos: nil`): Photos hands the sheet
                    // its own H.264 copy of an HEVC video (B-070).
                    read(provider, title: title, staging: staging, tally: tally, videos: nil,
                         done: done)
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
            // The lines that say why, where a check can read them, as a
            // send's end writes them (B-090); after the sheet is told, so
            // it does not wait for the file.
            keepLog(for: leftOut)
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
    /// `UIImage` could read, which is what decided it before. It is read
    /// as that type, then as any other picture type it offers, then as the
    /// `UIImage` it gives (`picture`, B-090). Each picture is counted, and
    /// each one attached (`Tally`).
    ///
    /// The composer's Photo Library reads what he picks here too, through a
    /// `Staging` of its own (`ComposeIntake`, B-108), so a photo or a video
    /// goes from the app as it goes from the share sheet.
    ///
    /// Returns the read, which the composer calls off as the app goes into
    /// the background, a picture's or a video's load under way, to read it
    /// again on his return (`Loading`, `ComposeIntake.away`, B-142). A
    /// video called off says so in its line, and calls back with nothing.
    ///
    /// A video staged is made H.264 by `videos`, where it is given and the
    /// video needs it, once the load's call back has returned
    /// (`stageRead`, `compatible`, B-142): the composer's, since its picker
    /// hands over the video Photos keeps. The share sheet gives none.
    @discardableResult
    static func read(_ provider: NSItemProvider, title: String?, staging: Staging,
                     tally: Tally, videos: VideoConversion?,
                     done: @escaping (SharedItem?) -> Void) -> Loading {
        let loading = Loading()
        if let type = SharedPhoto.fileType(offered: provider.registeredTypeIdentifiers)
            ?? (provider.canLoadObject(ofClass: UIImage.self) ? UTType.image.identifier : nil) {
            tally.pictures += 1
            picture(provider, type: type, staging: staging, loading: loading) { item in
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
            // make larger than the letter's room. A video staged is made
            // H.264 after, from the staged copy (`stageRead`, B-142).
            let progress = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                guard let url,
                      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                else {
                    Diagnostics.log(.note, fileNote(read: type, suggested: false, name: "",
                                                    mimeType: "-", bytes: 0,
                                                    went: loading.isCancelled ? .calledOff : .notGiven))
                    return done(nil)
                }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                let name = filename(suggested: provider.suggestedName, for: url)
                stageRead(url, size: Int64(size), type: type,
                          suggested: !(provider.suggestedName ?? "").isEmpty, name: name,
                          mimeType: mime, videos: movie != nil ? videos : nil, staging: staging,
                          loading: loading) { item in
                    if item != nil, movie != nil { tally.videosAttached += 1 }
                    done(item)
                }
            }
            // Photos' copy of a video is made while this load is under
            // way, minutes for a large one, and iOS holds a file
            // coordination claim on the app all that time, which calling
            // the load off does not end (B-142): hence `.current` in the
            // composer's picker, and no copy made.
            loading.track(progress)
        } else {
            done(nil)
        }
        return loading
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
