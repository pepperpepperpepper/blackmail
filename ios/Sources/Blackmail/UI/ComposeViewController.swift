// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit
import PhotosUI

/// The classic modal composer. Cancel fixed left, Send fixed right, always.
final class ComposeViewController: UIViewController,
                                  UITableViewDataSource, UITableViewDelegate,
                                  UITextFieldDelegate, UITextViewDelegate,
                                  UIAdaptivePresentationControllerDelegate,
                                  PHPickerViewControllerDelegate {

    private let repository: MailRepository
    private var draft: Draft
    /// Which letter this is on the iPad, kept there as he writes it
    /// (`LocalDrafts`): a new one for a new letter or a draft from the
    /// server, the kept one's own for a letter reopened from the iPad.
    private let key: String
    private let kept: LocalDrafts

    /// Fired when the Drafts folder has changed underneath, so whatever is
    /// showing it can catch up.
    var onDraftsChanged: (() -> Void)?

    /// Fired as the sheet closes on a letter reopened from Drafts and sent,
    /// with the id of its copy there, before that copy has been removed.
    /// See `ComposeActions.send`.
    var onDraftSent: ((String) -> Void)?

    /// To, Cc and Bcc, each recipient a bubble with the name on it, as
    /// Mail's (B-076). Send, Cancel, the suggestions and the letter read
    /// each a recipient at a time (`RecipientField.recipients`), so they
    /// read the people the bubbles show.
    private let toField = RecipientField()
    private let ccField = RecipientField()
    private let bccField = RecipientField()
    /// One row per attached file, rebuilt whenever the list changes.
    private let attachmentsStack = UIStackView()
    private let subjectField = UITextField()
    private let bodyView = UITextView()
    /// The letter as the sheet opened on it, read back off the form, which
    /// Cancel measures it against (`ComposeForm.asksBeforeClosing`).
    private var opened = Draft()
    /// The fields and the body under them, scrolled as one, as Mail's are
    /// (B-069). Its bottom is the keyboard's top.
    private let scroller = UIScrollView()
    /// How much of the sheet showed at the last layout, to tell when the
    /// keyboard has just come up over it.
    private var shownHeight: CGFloat = 0
    private var ccVisible = false
    /// The Cc row itself, hidden until the toggle is pressed, unless the
    /// letter arrives with a Cc or a Bcc (`Draft.showsCcAndBcc`).
    ///
    /// Assigned rather than constructed here because it must be the view
    /// `row()` returns and go STRAIGHT into the stack. It used to be an
    /// empty wrapper with the row dropped inside it by `addSubview`, and
    /// that wrapper made Cc unusable: a plain `addSubview` leaves
    /// `translatesAutoresizingMaskIntoConstraints` true on the row, so the
    /// 44 pt height constraint `row()` installs fought the autoresizing
    /// frame and lost, and nothing ever gave the wrapper a size. The label
    /// still drew, which is why it looked fine — but the field had no
    /// tappable area at all, so pressing Cc quietly did nothing and the
    /// next thing typed went into whichever field still had focus.
    ///
    /// Found by driving the form to send one test letter. A stack's
    /// ARRANGED subviews get their autoresizing turned off for them; a
    /// plain subview does not.
    private var ccRow = UIView()
    /// Built and added exactly like `ccRow`, and for the reason recorded
    /// there: straight into the stack as an ARRANGED subview, never
    /// `addSubview`d into a wrapper.
    private var bccRow = UIView()
    private let ccToggle = UIButton(type: .system)

    /// Addresses offered under the field he is typing in.
    ///
    /// The whole feature turns on one fact: he sends mail
    /// to himself constantly, and he is ninety. Every address was
    /// typed out in full on glass. It also quietly unlocks something
    /// that was impossible before — the email keyboard has no comma, and
    /// `collect()` splits recipients on commas, so a SECOND recipient
    /// could not be typed at all. Choosing from this list inserts the
    /// separator for him.
    private let suggestionsView = UITableView(frame: .zero, style: .plain)
    private var suggestions: [KnownRecipient] = []
    private weak var activeAddressField: RecipientField?
    private static let suggestionRowHeight: CGFloat = Theme.suggestionRowHeight

    /// Send and Save Draft, in the order each has to happen, what the sheet
    /// shows while a letter goes, and the letter kept on the iPad meanwhile.
    /// See `ComposeActions`.
    private lazy var actions = ComposeActions(
        letter: key, repository: repository, kept: kept,
        dismiss: { [weak self] in self?.close() },
        showError: { [weak self] error in
            guard let self else { return }
            ErrorPresenter.show(error, on: self)
        },
        draw: { [weak self] look in self?.draw(look) },
        background: .app,
        queued: { [weak self] in self?.queuedOnClose = true })

    /// Send could not reach the server and the letter waits in the Outbox:
    /// the sheet closes with one notice over what it came from
    /// (`Outbox.notice`), as Mail says its letter "has been placed in your
    /// Outbox", or, for a letter held, that it will not go by itself
    /// (`LocalDrafts.waitingNotice`).
    private var queuedOnClose = false

    private lazy var sendItem = UIBarButtonItem(
        title: "Send", style: .done, target: self, action: #selector(sendTapped))
    /// What stands where Send was while the letter goes: its words, not a
    /// button, and a spinner beside them. Two ordinary bar items, so the bar
    /// sizes them the way it sizes Send, and the words can change in place
    /// as the letter goes.
    ///
    /// In the text's own white, not the grey a disabled item draws in. The
    /// grey read on the iPad as faint, the one thing on the sheet saying the
    /// tap had taken; white is not blue, so it does not look like a button
    /// either.
    private lazy var sendingWordsItem: UIBarButtonItem = {
        let item = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
        item.isEnabled = false
        // Figures of one width, so "Sending… 40%" does not shuffle sideways
        // as the number changes.
        item.setTitleTextAttributes(
            [.font: UIFont.monospacedDigitSystemFont(ofSize: Theme.fontBarButton.pointSize,
                                                     weight: .regular),
             .foregroundColor: Theme.primaryText],
            for: .disabled)
        return item
    }()
    private let sendingSpinner = UIActivityIndicatorView(style: .medium)
    private lazy var sendingSpinnerItem = UIBarButtonItem(customView: sendingSpinner)
    /// Held while a letter goes, with the Remove buttons.
    private weak var attachButton: UIButton?

    /// Every photo `attach` staged in `tmp/Attachments`, removed when this
    /// controller goes (B-063). They used to stay until the next launch,
    /// which iOS can put off for days: five full-size photographs a letter.
    ///
    /// At `deinit` and no sooner, because that is when nothing can still
    /// read them. Send and Save Draft hand `ComposeActions` a closure that
    /// holds this controller (`{ self.draft }`), as do the autosave and the
    /// keep as he leaves the app, and each task holds that closure until it
    /// has finished, the send's upload and the save's keep and APPEND
    /// included. A letter kept on the iPad has its photos linked into its
    /// own directory by then, which outlive the staged copies; its files
    /// are never recorded here, nor removed (`AttachmentStore.removeStaged`).
    private let staged = StagedFiles()

    /// `key` is the letter's on the iPad when it was reopened from there;
    /// any other letter is given a new one.
    init(repository: MailRepository, draft: Draft, key: String? = nil) {
        self.repository = repository
        self.draft = draft
        self.key = key ?? UUID().uuidString.lowercased()
        self.kept = .shared
        super.init(nibName: nil, bundle: nil)
        title = ComposeForm.title(subject: draft.subject)
        // Nothing else takes it to the server while it is open here.
        kept.opened(self.key)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        staged.removeAll()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.canvas

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = sendItem
        for item in [navigationItem.leftBarButtonItem, navigationItem.rightBarButtonItem] {
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
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(stack)

        stack.addArrangedSubview(addressRow(label: "To:", field: toField, entries: draft.to))
        // Open when the letter arrives with someone in them: a Reply All,
        // a reopened draft, or a `mailto:` link in a letter, which is a
        // stranger's to fill. A Bcc he cannot see is a copy going somewhere
        // he never agreed to.
        ccVisible = draft.showsCcAndBcc
        ccRow = addressRow(label: "Cc:", field: ccField, entries: draft.cc)
        stack.addArrangedSubview(ccRow)
        ccRow.isHidden = !ccVisible

        // A real field, not a rename. The button has said "Cc/Bcc" since
        // the composer was written and only ever revealed Cc — the app
        // naming something that was not there, the same defect as telling
        // him to go to a Settings screen that did not exist.
        bccRow = addressRow(label: "Bcc:", field: bccField, entries: draft.bcc)
        stack.addArrangedSubview(bccRow)
        bccRow.isHidden = !ccVisible

        // Cc/Bcc hidden behind an explicit labelled toggle rather than always
        // present: two fewer boxes on screen for someone who will never use
        // them, and still one tap away with a word on it.
        ccToggle.setTitle("Cc/Bcc", for: .normal)
        ccToggle.titleLabel?.font = Theme.fontDetailMeta
        ccToggle.addTarget(self, action: #selector(toggleCc), for: .touchUpInside)
        ccToggle.contentHorizontalAlignment = .left
        let toggleRow = UIView()
        ccToggle.translatesAutoresizingMaskIntoConstraints = false
        toggleRow.addSubview(ccToggle)
        NSLayoutConstraint.activate([
            ccToggle.leadingAnchor.constraint(equalTo: toggleRow.leadingAnchor, constant: Theme.detailContentInsetLeft),
            ccToggle.topAnchor.constraint(equalTo: toggleRow.topAnchor),
            ccToggle.bottomAnchor.constraint(equalTo: toggleRow.bottomAnchor),
            ccToggle.heightAnchor.constraint(equalToConstant: Theme.minHitTarget),
        ])
        stack.addArrangedSubview(toggleRow)
        stack.addArrangedSubview(row(label: "Subject:", field: subjectField, text: draft.subject))
        attachmentsStack.axis = .vertical
        attachmentsStack.spacing = 0
        // Zero height, preferred not required — the same guard as
        // `MessageHeaderView`, and for the same reason (B-027). An empty
        // `UIStackView` has no intrinsic height, and this one sits in the
        // chain that gives the header block its height, which is what
        // `bodyView` is pinned beneath. With no photographs attached, which
        // is nearly every letter, nothing decided how tall this was, and
        // Auto Layout was free to hand the writing area 0 points the way it
        // did to the reading pane's web view.
        let flatAttachments = attachmentsStack.heightAnchor.constraint(equalToConstant: 0)
        flatAttachments.priority = .defaultLow
        flatAttachments.isActive = true
        stack.addArrangedSubview(attachmentsStack)
        stack.addArrangedSubview(attachRow())
        rebuildAttachments()

        bodyView.font = .systemFont(ofSize: Theme.scaled(17))
        bodyView.text = draft.body
        // The caret starts at the top, above his signature and above a
        // quoted original, where Tab and Return from Subject put it in
        // Mail. Set nowhere, it was at the end, under all of them.
        bodyView.selectedRange = NSRange(location: 0, length: 0)
        // The app's black and white (D-010), as the share sheet has it.
        // Left to the system, the body was its dark grey on the black sheet.
        bodyView.backgroundColor = Theme.canvas
        bodyView.textColor = Theme.primaryText
        bodyView.accessibilityLabel = "Message"
        bodyView.textContainerInset = UIEdgeInsets(top: 12, left: Theme.detailContentInsetLeft - 5,
                                                   bottom: 12, right: Theme.detailContentInsetLeft - 5)
        // Smart punctuation off. It turns "--" into an em dash and straight
        // quotes into curly ones behind his back, which is not help.
        bodyView.smartDashesType = .no
        bodyView.smartQuotesType = .no
        bodyView.translatesAutoresizingMaskIntoConstraints = false
        // As tall as its words, and scrolled with the fields over it, as
        // Mail's letter is. With a scroller of its own under fields that
        // never moved, the keyboard left it a line or two in landscape,
        // and nothing under a Reply All's Cc and Bcc or a forward's files.
        bodyView.isScrollEnabled = false
        bodyView.delegate = self
        scroller.addSubview(bodyView)

        let content = scroller.contentLayoutGuide
        let shown = scroller.frameLayoutGuide
        NSLayoutConstraint.activate([
            scroller.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroller.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroller.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Above the keyboard, so the line he types on is never under
            // it. Pinned to the safe area, the body ran on under the
            // on-screen keyboard and the caret went with it. With no
            // keyboard up, or a hardware keyboard's bar alone, the guide's
            // top is the safe area's bottom.
            scroller.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: shown.widthAnchor),
            bodyView.topAnchor.constraint(equalTo: stack.bottomAnchor),
            bodyView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bodyView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            // At least as tall as the sheet, so the body reaches its
            // bottom, and a tap under the words is still in the letter.
            content.heightAnchor.constraint(greaterThanOrEqualTo: shown.heightAnchor),
        ])

        // Last, so it sits above the body it overlaps.
        configureSuggestions()

        subjectField.delegate = self
        subjectField.addTarget(self, action: #selector(subjectChanged), for: .editingChanged)
        opened = currentLetter()
        updateSend()
        // A tap outside the sheet does nothing, and a swipe down asks what
        // Cancel asks (`presentationControllerDidAttemptToDismiss`), as in
        // Mail. Either used to close the sheet at once, the letter put in
        // Drafts with nothing asked.
        isModalInPresentation = true

        // Kept on the iPad a few seconds after he stops, and at once when
        // he leaves the app. See `ComposeActions.edited` and `putAside`.
        let centre = NotificationCenter.default
        centre.addObserver(self, selector: #selector(letterEdited),
                           name: UITextView.textDidChangeNotification, object: bodyView)
        centre.addObserver(self, selector: #selector(leavingTheApp),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    /// The letter as the fields have it now, for what keeps it.
    private func currentLetter() -> Draft {
        collect()
        return draft
    }

    @objc private func letterEdited() {
        actions.edited { self.currentLetter() }
    }

    @objc private func leavingTheApp() {
        actions.putAside { self.currentLetter() }
    }

    /// The presented navigation controller is the sheet, and it is its
    /// modality and its presentation that count.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isModalInPresentation = true
        navigationController?.presentationController?.delegate = self
    }

    /// A swipe at the sheet, which is held: Cancel's question, or for a
    /// letter as it opened, the sheet closed (`cancelTapped`).
    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        cancelTapped()
    }

    /// The keyboard has come up over the sheet, which now ends above it:
    /// the caret is brought into the part still showing, once the layout
    /// has settled.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let height = scroller.bounds.height
        defer { shownHeight = height }
        guard height < shownHeight, bodyView.isFirstResponder else { return }
        DispatchQueue.main.async { [weak self] in self?.keepCaretInView() }
    }

    /// The line he is on, brought into the part of the sheet showing, with
    /// the body's margin round it. The fields go up out of the way when
    /// the keyboard leaves too little room under them, as Mail's do.
    private func keepCaretInView() {
        guard bodyView.isFirstResponder, let end = bodyView.selectedTextRange?.end else { return }
        view.layoutIfNeeded()
        let caret = bodyView.caretRect(for: end)
        guard !caret.isNull, !caret.isInfinite else { return }
        let line = bodyView.convert(caret, to: scroller)
            .insetBy(dx: 0, dy: -bodyView.textContainerInset.bottom)
        scroller.scrollRectToVisible(line, animated: false)
    }

    /// He has typed in the body, or moved the caret: it stays in sight.
    func textViewDidChange(_ textView: UITextView) {
        keepCaretInView()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        keepCaretInView()
    }

    /// The list under an address field goes with the field as the sheet
    /// scrolls.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === scroller, !suggestionsView.isHidden,
              let field = activeAddressField else { return }
        layoutSuggestions(under: field)
    }

    /// The title follows the subject as he types it, as Mail's does.
    @objc private func subjectChanged() {
        title = ComposeForm.title(subject: subjectField.text ?? "")
    }

    /// Send is grey until To, Cc or Bcc holds an address, as in Mail.
    private func updateSend() {
        sendItem.isEnabled = ComposeForm.canSend(to: toField.recipients,
                                                 cc: ccField.recipients,
                                                 bcc: bccField.recipients)
    }

    /// Return in Subject goes to the body, the caret at its top, above his
    /// signature and any quoted original, as in Mail. It did nothing.
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard textField === subjectField else { return true }
        bodyView.becomeFirstResponder()
        bodyView.selectedRange = NSRange(location: 0, length: 0)
        keepCaretInView()
        return false
    }

    /// Put away by anything but Send, Save Draft, Delete Draft or Cancel:
    /// the letter he changed stays on the iPad, in Drafts, rather than
    /// going with the sheet. A swipe no longer puts it away (B-069), so
    /// this is what is left if something else ever does. After any of
    /// those four this does nothing.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard navigationController?.isBeingDismissed ?? isBeingDismissed else { return }
        actions.sheetGone { currentLetter() }
    }

    /// The permanent "Attach Photo" control.
    ///
    /// A labelled button rather than the callout menu Mail of this era
    /// used, because `BRIEF.md`'s promise is that nothing needs a gesture
    /// beyond tap and ordinary scrolling — and "press and hold in the body
    /// until a menu appears" is exactly the kind of thing that promise
    /// exists to rule out. Always visible, so it never moves.
    private func attachRow() -> UIView {
        let container = UIView()
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "paperclip")
        // The size of the words beside it, fixed (D-007). Left to the
        // button, the symbol grew with the iPad's text size and the words
        // did not.
        config.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(font: Theme.fontDetailMeta)
        config.imagePadding = 6
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Theme.detailContentInsetLeft, bottom: 0, trailing: 0)
        var title = AttributedString("Attach Photo")
        title.font = Theme.fontDetailMeta
        config.attributedTitle = title
        button.configuration = config
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: #selector(attachTapped), for: .touchUpInside)
        attachButton = button

        let rule = UIView()
        rule.backgroundColor = Theme.separator
        for v in [button, rule] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: Theme.minHitTarget),
            rule.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                          constant: Theme.detailContentInsetLeft),
            rule.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        return container
    }

    /// One row per attached file: what it is, what it weighs, and a way to
    /// take it off again.
    ///
    /// Removal exists now and did not before, and the reason is simply
    /// that attaching does. A list you can add to and not subtract from
    /// turns one mis-tap in a photo library into a letter he cannot send
    /// without starting it over.
    private func rebuildAttachments() {
        for view in attachmentsStack.arrangedSubviews {
            attachmentsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, attachment) in draft.attachments.enumerated() {
            attachmentsStack.addArrangedSubview(attachmentRow(attachment, at: index))
        }
    }

    private func attachmentRow(_ attachment: DraftAttachment, at index: Int) -> UIView {
        let container = UIView()
        let icon = UIImageView(image: UIImage(systemName: "paperclip"))
        icon.tintColor = Theme.secondaryText
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.font = Theme.fontDetailMeta
        label.textColor = Theme.secondaryText
        label.numberOfLines = 1
        // The weight, not just the name. A refusal at Send is the right
        // backstop but a poor first warning — by then he has written the
        // letter. Saying what it weighs while he attaches it is the cheap
        // half of the same job.
        label.text = attachment.size.map {
            attachment.filename + "  —  "
                + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        } ?? attachment.filename

        let remove = UIButton(type: .system)
        remove.setTitle("Remove", for: .normal)
        remove.titleLabel?.font = Theme.fontDetailMeta
        remove.setTitleColor(Theme.destructive, for: .normal)
        // Grey while a letter goes, when it is held: a system button with
        // its own colour for .normal keeps that colour when disabled, and on
        // the iPad the held Removes still looked live in red.
        remove.setTitleColor(Theme.secondaryText, for: .disabled)
        remove.tag = index
        remove.addTarget(self, action: #selector(removeAttachment(_:)), for: .touchUpInside)
        // A photo that lands from the picker while a letter goes rebuilds
        // the rows; its Remove is held with the rest.
        remove.isEnabled = !actions.isSending

        let rule = UIView()
        rule.backgroundColor = Theme.separator

        for v in [icon, label, remove, rule] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                          constant: Theme.detailContentInsetLeft),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
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
        return container
    }

    @objc private func removeAttachment(_ sender: UIButton) {
        guard sender.tag < draft.attachments.count else { return }
        draft.attachments.remove(at: sender.tag)
        rebuildAttachments()
        letterEdited()
    }

    // MARK: - Choosing a photo

    @objc private func attachTapped() {
        // PHPicker, not the old image picker, and the difference is a
        // permission prompt. PHPicker runs out of process and hands back
        // only what he chose, so it needs no photo-library access at all —
        // which matters because a "Don't Allow" tapped once by a
        // 90-year-old is invisible, permanent, and looks like the button
        // being broken.
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 5
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        for result in results {
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
            let suggested = provider.suggestedName ?? "Photo"
            // Counted until it is in the letter or has failed, so that a
            // Send or a Save Draft tapped meanwhile waits for it rather than
            // going without it. See `ComposeActions.photosLanded`.
            actions.photoComing()
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                // Re-encoded as JPEG rather than passed through. iPads
                // store photos as HEIC, which a good many recipients
                // cannot open at all — a letter whose attachment will not
                // display is worse than one with no attachment, because
                // neither end knows. Full resolution is kept: the size
                // ceiling is already refused loudly at send (B-007), so
                // there is no need to quietly shrink what he chose.
                let data = (object as? UIImage)?.jpegData(compressionQuality: 0.85)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let data { self.attach(data, named: suggested + ".jpg") }
                    self.actions.photoLanded()
                }
            }
        }
    }

    @MainActor
    private func attach(_ data: Data, named filename: String) {
        // Staged on disk rather than held in the draft: a composer left
        // open for an hour should not also be holding several megabytes of
        // image in memory. Safe against the launch-time purge because a
        // SAVED draft embeds its bytes on the server and reopens as a
        // message part, and a letter kept on the iPad links its photos
        // into its own directory (`LocalDraftStore.keep`), so nothing in
        // the staging has to outlive this composer, which removes what it
        // staged as it goes (`staged`).
        guard let url = try? AttachmentStore.write(data, named: filename) else {
            ErrorPresenter.show(.attachmentFailed, on: self)
            return
        }
        staged.record(url)
        draft.attachments.append(DraftAttachment(source: .localFile(url),
                                                 filename: filename,
                                                 mimeType: "image/jpeg",
                                                 size: Int64(data.count)))
        rebuildAttachments()
        letterEdited()
    }

    private func row(label text: String, field: UITextField, text value: String) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = text
        label.font = Theme.fontDetailMeta
        label.textColor = Theme.secondaryText
        field.text = value
        field.font = .systemFont(ofSize: Theme.scaled(17))
        field.textColor = Theme.primaryText
        // The caption is a label of its own, which VoiceOver does not read
        // with the field: "To", not "To:".
        field.accessibilityLabel = text.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        // Subject alone since B-076: To, Cc and Bcc are `addressRow`'s.
        field.addTarget(self, action: #selector(letterEdited), for: .editingChanged)

        let rule = UIView()
        rule.backgroundColor = Theme.separator
        for v in [label, field, rule] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Theme.detailContentInsetLeft),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 72),
            field.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Theme.detailContentInsetLeft),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: Theme.minHitTarget),
            rule.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Theme.detailContentInsetLeft),
            rule.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        return container
    }

    /// To, Cc or Bcc: the caption, then the field of bubbles, one line of
    /// `minHitTarget` for each line of them, as Mail's field grows with a
    /// Reply All's people (B-076). The caption stays by the first line.
    private func addressRow(label text: String, field: RecipientField, entries: [String]) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = text
        label.font = Theme.fontDetailMeta
        label.textColor = Theme.secondaryText
        field.show(entries)
        field.font = .systemFont(ofSize: Theme.scaled(17))
        field.textColor = Theme.primaryText
        // The caption is a label of its own, which VoiceOver does not read
        // with the field: "To", not "To:".
        field.accessibilityLabel = text.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        // The email keyboard is the field's own (`RecipientField`).
        field.addTarget(self, action: #selector(letterEdited), for: .editingChanged)
        field.addTarget(self, action: #selector(addressEditingChanged(_:)), for: .editingChanged)
        field.addTarget(self, action: #selector(addressEditingBegan(_:)), for: .editingDidBegin)
        field.addTarget(self, action: #selector(addressEditingEnded(_:)), for: .editingDidEnd)

        let rule = UIView()
        rule.backgroundColor = Theme.separator
        for v in [label, field, rule] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Theme.detailContentInsetLeft),
            label.centerYAnchor.constraint(equalTo: container.topAnchor, constant: Theme.minHitTarget / 2),
            label.widthAnchor.constraint(equalToConstant: 72),
            field.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Theme.detailContentInsetLeft),
            field.topAnchor.constraint(equalTo: container.topAnchor),
            field.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rule.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Theme.detailContentInsetLeft),
            rule.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        return container
    }

    // MARK: - Recipient suggestions

    private func configureSuggestions() {
        suggestionsView.dataSource = self
        suggestionsView.delegate = self
        suggestionsView.rowHeight = Self.suggestionRowHeight
        suggestionsView.backgroundColor = Theme.barFill
        suggestionsView.separatorColor = Theme.separator
        suggestionsView.isHidden = true
        suggestionsView.layer.borderWidth = 0.5
        suggestionsView.layer.borderColor = Theme.separator.cgColor
        suggestionsView.register(UITableViewCell.self, forCellReuseIdentifier: "suggestion")
        view.addSubview(suggestionsView)
    }

    /// Going in offers nothing, as in Mail (B-073), and closes a list left
    /// open under another field.
    @objc private func addressEditingBegan(_ field: RecipientField) {
        activeAddressField = field
        refreshSuggestions(after: .entered)
    }

    @objc private func addressEditingChanged(_ field: RecipientField) {
        activeAddressField = field
        refreshSuggestions(after: .typed)
        updateSend()
    }

    @objc private func addressEditingEnded(_ field: RecipientField) {
        // Deferred by one runloop turn: a TAP on a suggestion ends editing
        // before the table sees the touch, so hiding immediately would
        // dismiss the row out from under his finger and nothing would be
        // chosen.
        DispatchQueue.main.async { [weak self] in
            guard let self, !(self.activeAddressField?.isEditing ?? false) else { return }
            self.suggestionsView.isHidden = true
        }
    }

    /// What the field offers after `event` (`ComposeForm.suggestions`):
    /// matches only while he types; nothing as he goes in (B-073), and
    /// nothing once he has picked one, until he types again.
    private func refreshSuggestions(after event: ComposeForm.FieldEvent) {
        guard let field = activeAddressField else { return }
        suggestions = ComposeForm.suggestions(RecipientBook.shared.snapshot(),
                                              in: field.bubbles, after: event)
        suggestionsView.reloadData()
        layoutSuggestions(under: field)
        suggestionsView.isHidden = suggestions.isEmpty
    }

    private func layoutSuggestions(under field: RecipientField) {
        guard let row = field.superview,
              let frame = row.superview?.convert(row.frame, to: view) else { return }
        let height = CGFloat(suggestions.count) * Self.suggestionRowHeight
        suggestionsView.frame = CGRect(x: frame.minX, y: frame.maxY,
                                       width: frame.width, height: height)
        view.bringSubviewToFront(suggestionsView)
    }

    func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int {
        suggestions.count
    }

    func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = t.dequeueReusableCell(withIdentifier: "suggestion", for: ip)
        let entry = suggestions[ip.row]
        var config = cell.defaultContentConfiguration()
        config.text = entry.display
        config.textProperties.font = Theme.fontListSender
        config.textProperties.color = Theme.primaryText
        // The address under the name, because two people can share a name
        // and he needs to see which one he is about to write to.
        config.secondaryText = entry.display == entry.address ? nil : entry.address
        config.secondaryTextProperties.font = Theme.fontDetailMeta
        config.secondaryTextProperties.color = Theme.secondaryText
        cell.contentConfiguration = config
        cell.backgroundColor = Theme.barFill
        return cell
    }

    func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        guard let field = activeAddressField, ip.row < suggestions.count else { return }
        // A bubble with the name the book has for it, in place of what he
        // typed, as Mail's pick is (B-076). It used to be the address
        // alone, typed into the field after a comma.
        let picked = suggestions[ip.row]
        field.pick(MailFormat.recipient(name: picked.name, address: picked.address).entry)
        t.deselectRow(at: ip, animated: false)
        // Closed, as Mail's closes, until he types again. It used to open
        // again at once with his most used over Cc, Subject and Attach
        // Photo.
        refreshSuggestions(after: .picked)
        updateSend()
        // Set by hand, the field sends no change of its own.
        letterEdited()
    }

    @objc private func toggleCc() {
        ccVisible.toggle()
        ccRow.isHidden = !ccVisible
        bccRow.isHidden = !ccVisible
    }

    @objc private func cancelTapped() {
        // Nothing while a letter goes, when a swipe still lands here, nor
        // with the question already up.
        guard !actions.isSending, presentedViewController == nil else { return }
        // Asked only about a letter he has changed, as Mail asks
        // (`ComposeForm.asksBeforeClosing`). A new letter opens with his
        // signature in it, and asking whenever the body had anything in it
        // asked every time. A photo still coming in is a change, and so is
        // a Send the server refused (`ComposeActions.asksAnyway`).
        let letter = currentLetter()
        guard actions.asksAnyway
                || ComposeForm.asksBeforeClosing(letter, opened: opened) else {
            actions.closeWithoutAsking { letter }
            return
        }

        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
        sheet.addAction(UIAlertAction(title: "Save Draft", style: .default) { [weak self] _ in
            guard let self else { return }
            self.collect()
            // The order, the background time around the save, and the wait
            // for photos still on their way in are
            // `ComposeActions.saveAndClose`, which also refuses once a
            // letter is on its way. The draft is asked for after the sheet
            // has gone, so the save keeps this controller until it has it.
            // Drafts catches up from `LocalDrafts.changed`, as the letter
            // is kept and again once the server has it, rather than from
            // here, which would fetch it a second time.
            self.actions.saveAndClose({ self.draft }, then: nil)
        })
        sheet.addAction(UIAlertAction(title: "Delete Draft", style: .destructive) { [weak self] _ in
            guard let self else { return }
            // `ComposeActions.deleteAndClose`, which also refuses once a
            // letter is on its way.
            self.actions.deleteAndClose(self.draft.savedID, letter: self.draft.savedLetter,
                                        then: self.onDraftsChanged)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func sendTapped() {
        // A second tap, or one while the letter is on its way, sends
        // nothing; Send has already given way to the spinner, and this is
        // for a tap that got in first.
        guard !actions.isSending else { return }
        // The Cancel sheet hangs from the bar Send is on, and a popover
        // from a bar button leaves its bar live, so Send can be tapped with
        // that sheet still open. It goes first. Its Save Draft and Delete
        // Draft would do nothing now, and a failure has to be said over
        // this sheet, which cannot put up an alert while it has something
        // else up.
        if let shown = presentedViewController, !shown.isBeingDismissed {
            shown.dismiss(animated: true)
        }
        // The fields as they are at the tap; the letter itself is taken
        // once any photo still on its way in has landed in it.
        collect()
        actions.send({ self.draft }, then: onDraftsChanged, draftSent: onDraftSent)
    }

    /// Puts the sheet away, with whatever it has up over itself.
    ///
    /// Told to whatever presented the sheet, not to the sheet. A view
    /// controller told to dismiss while it is presenting something
    /// dismisses that instead and stays. With an alert over the sheet when
    /// the letter went, about a photo that could not be staged, or the
    /// Share or Look Up the text menu offers, that was all that closed, and
    /// the sheet stayed with Send gone, Cancel held and the swipe refused,
    /// which only quitting the app undid. Told to the presenter, UIKit takes
    /// the sheet and everything over it.
    ///
    /// For a letter left in the Outbox the notice is put over the presenter,
    /// held until the sheet has gone (`ErrorPresenter.sheetLeaving`): UIKit
    /// drops an alert asked for over a sheet on its way out.
    private func close() {
        let presenter = presentingViewController ?? self
        guard queuedOnClose, presentingViewController != nil else {
            presenter.dismiss(animated: true)
            return
        }
        let gone = ErrorPresenter.sheetLeaving()
        presenter.dismiss(animated: true, completion: gone)
        ErrorPresenter.tell(kept.waitingNotice(key), on: presenter)
    }

    /// The sheet as `ComposeActions` says it should be. While a letter goes:
    /// the spinner and its words where Send was, and Cancel, Attach Photo
    /// and every Remove held, since the one thing that must not happen then
    /// is the letter being lost or sent twice. After a failure everything
    /// is live again. The sheet is never let go by a swipe (`viewDidLoad`),
    /// and a swipe while a letter goes asks nothing (`cancelTapped`).
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
                // The first is the one at the edge, where Send was.
                navigationItem.rightBarButtonItems = [sendingWordsItem, sendingSpinnerItem]
            }
        }
        navigationItem.leftBarButtonItem?.isEnabled = !sending
        attachButton?.isEnabled = !sending
        for row in attachmentsStack.arrangedSubviews {
            for case let remove as UIButton in row.subviews { remove.isEnabled = !sending }
        }
    }

    private func collect() {
        // `savedID` is deliberately untouched here: `collect` rebuilds the
        // draft from the form, and the form has no field for which copy on
        // the server this is.
        // A recipient for each bubble, as the field shows them, then any
        // he is still typing (B-076).
        draft.to = toField.recipients
        draft.cc = ccField.recipients
        draft.bcc = bccField.recipients
        draft.subject = subjectField.text ?? ""
        draft.body = bodyView.text ?? ""
    }
}

extension LocalDrafts {

    /// The app's own: in Application Support, for the account set up on
    /// this iPad, inside `UIApplication`'s background time, and with no
    /// pass in a launch the safe start holds them in (B-057). Made after
    /// the safe start has run, by the first screen that lists letters. Its
    /// tries are marked beside the safe start's count, so a launch one of
    /// them ends is charged to the letter.
    static let shared = LocalDrafts(store: LocalDraftStore(root: LocalDraftStore.appRoot),
                                    account: CredentialStore.loadAccount()?.address,
                                    background: .app,
                                    holdsPasses: SafeStart.app.steps.holdsPasses,
                                    launches: SafeStart.appDirectory)
}

extension BackgroundTime {

    /// The app's own: `UIApplication`'s background tasks. The handler is
    /// called on the main thread and gives the time back before returning,
    /// which is what iOS requires of it.
    static let app = BackgroundTime(
        begin: { name, expired in
            let id = UIApplication.shared.beginBackgroundTask(withName: name) { expired() }
            return id == .invalid ? nil : id.rawValue
        },
        end: { id in
            UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: id))
        })
}

#endif
