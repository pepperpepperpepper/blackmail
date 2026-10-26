// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit
import PhotosUI
import UniformTypeIdentifiers
import AudioToolbox

/// The classic modal composer. Cancel fixed left, Send fixed right, always.
final class ComposeViewController: UIViewController,
                                  UITableViewDataSource, UITableViewDelegate,
                                  UITextFieldDelegate, UITextViewDelegate,
                                  UIAdaptivePresentationControllerDelegate,
                                  PHPickerViewControllerDelegate,
                                  UIDocumentPickerDelegate {

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
    /// Whether Cc and Bcc stand open (`showCcAndBcc`).
    private var ccVisible = false
    /// The Cc row itself, hidden until "Cc/Bcc" is tapped, unless the
    /// letter arrives with a Cc or a Bcc (`Draft.showsCcAndBcc`), and
    /// hidden again as the caret leaves Cc and Bcc with nobody in them
    /// (B-134).
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
    /// The "Cc/Bcc" row, hidden while Cc and Bcc stand open, as Mail hides
    /// its "Cc/Bcc, From:" row while its fields show (B-134). It stayed,
    /// under Bcc, and a second tap on it hid Cc and Bcc again.
    private let ccToggleRow = UIView()

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
    /// What last happened in an address field, for the list to be offered
    /// again as it was when his Contacts come in at his yes (B-162).
    private var lastAddressEvent: ComposeForm.FieldEvent = .entered
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
        queued: { [weak self] in self?.queuedOnClose = true },
        sent: { AudioServicesPlaySystemSound(ComposeViewController.sentMailSound) })

    /// Mail's sent sound, its Swoosh, played once as the sheet closes on a
    /// letter that went or was put in the Outbox, as Mail's composer plays
    /// it (B-100). The share sheet plays the same.
    ///
    /// mail-sent.caf, 1001 in AudioToolbox's built-in table of system
    /// sounds, next to new-mail.caf at 1000. Apple does not document the
    /// number: it was read from iOS 18.6's AudioToolbox, and lists of the
    /// system sounds have given it since iPhone OS 2. Played at the
    /// system's volume, with no volume of the app's own. The tone chosen in
    /// Settings, Sounds, Sent Mail is not read, so this is Swoosh, the
    /// factory one, whatever is chosen there.
    static let sentMailSound: SystemSoundID = 1001

    /// Whether the sheet's one chance to be made ready to type, the first
    /// time it appears, has come and gone (`readyToType`).
    private var readied = false

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
    /// Photo Library and Attach File, held while a letter goes, with the
    /// Remove buttons.
    private weak var photoButton: UIButton?
    private weak var fileButton: UIButton?
    /// Mail's paperclip in the keyboard's shortcut bar while he types in
    /// the letter (B-154), held with the two buttons.
    private var paperclipItem: UIBarButtonItem?

    /// Every file the intake staged in `tmp/Attachments` and put in the
    /// letter, removed when this controller goes (B-063). They used to stay
    /// until the next launch, which iOS can put off for days: five
    /// full-size photographs a letter.
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

    /// What Photo Library and Attach File bring in, one at a time, through
    /// the share sheet's own intake (`ComposeIntake`, B-108): each counted
    /// in `actions` until it is in, so Send and Save Draft wait for it; a
    /// row with a spinner while it comes; what could not be attached said.
    private lazy var intake = ComposeIntake(
        actions: actions,
        rows: { [weak self] in self?.draft.attachments ?? [] },
        landed: { [weak self] url, row in self?.landed(url, row) },
        changed: { [weak self] in self?.rebuildAttachments() },
        tell: { [weak self] alert in self?.say(alert) })

    /// A reply's files (`ReplyFiles`, B-107): the original's parts, put in
    /// as rows once the reply goes to someone the original did not go to,
    /// and taken out again when no one new is left, until he takes one off
    /// himself. Made by the pane's Reply and Reply All alone; nil for a
    /// forward, a new letter and a letter reopened from Drafts, the iPad or
    /// the Outbox, which keep the rows they were saved with.
    private var replyFiles: ReplyFiles?

    /// `key` is the letter's on the iPad when it was reopened from there;
    /// any other letter is given a new one. `replyFiles` is a Reply's or a
    /// Reply All's, nil for every other letter.
    ///
    /// The letter's body is bounded here, whoever opened the sheet on it
    /// (`ComposeForm.bounded`, B-140): the text view it goes into is as
    /// tall as its words and drawn whole as the sheet comes up, and given
    /// about 1.7 MB of a letter the sheet never came.
    init(repository: MailRepository, draft: Draft, key: String? = nil,
         replyFiles: ReplyFiles? = nil) {
        self.repository = repository
        self.draft = ComposeForm.bounded(draft)
        self.replyFiles = replyFiles
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

        // Cc/Bcc folded into one labelled row rather than always present:
        // two fewer boxes on screen for someone who will never use them,
        // and still one tap away with a word on it. Mail's way since B-134:
        // the tap opens Cc and Bcc with the caret in Cc and the row goes
        // while they show; they fold back as the caret goes elsewhere with
        // nobody in them (`caretWentInto`).
        ccToggle.setTitle("Cc/Bcc", for: .normal)
        ccToggle.titleLabel?.font = Theme.fontDetailMeta
        ccToggle.addTarget(self, action: #selector(openCcAndBcc), for: .touchUpInside)
        ccToggle.contentHorizontalAlignment = .left
        let toggleRow = ccToggleRow
        ccToggle.translatesAutoresizingMaskIntoConstraints = false
        toggleRow.addSubview(ccToggle)
        NSLayoutConstraint.activate([
            ccToggle.leadingAnchor.constraint(equalTo: toggleRow.leadingAnchor, constant: Theme.detailContentInsetLeft),
            ccToggle.topAnchor.constraint(equalTo: toggleRow.topAnchor),
            ccToggle.bottomAnchor.constraint(equalTo: toggleRow.bottomAnchor),
            ccToggle.heightAnchor.constraint(equalToConstant: Theme.minHitTarget),
        ])
        stack.addArrangedSubview(toggleRow)
        toggleRow.isHidden = ccVisible
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
        // Mail. Set nowhere, it was at the end, under all of them. A reply
        // opens with it there and the keyboard up (`readyToType`, B-120).
        bodyView.selectedRange = NSRange(location: 0, length: 0)
        // The app's black and white (D-010), as the share sheet has it.
        // Left to the system, the body was its dark grey on the black sheet.
        bodyView.backgroundColor = Theme.canvas
        bodyView.textColor = Theme.primaryText
        bodyView.accessibilityLabel = "Message"
        bodyView.textContainerInset = UIEdgeInsets(top: 12, left: Theme.detailContentInsetLeft - 5,
                                                   bottom: 12, right: Theme.detailContentInsetLeft - 5)
        // The keyboard's Smart Punctuation, as Mail's body has it (B-121):
        // "--" a dash and his apostrophes and quotes curly, as Settings
        // says, which his own letters show. It was off, by a comment
        // calling it no help, and every apostrophe he typed went straight.
        // Capitals and corrections are the text view's own, as before.
        bodyView.smartDashesType = .default
        bodyView.smartQuotesType = .default
        bodyView.translatesAutoresizingMaskIntoConstraints = false
        // As tall as its words, and scrolled with the fields over it, as
        // Mail's letter is. With a scroller of its own under fields that
        // never moved, the keyboard left it a line or two in landscape,
        // and nothing under a Reply All's Cc and Bcc or a forward's files.
        bodyView.isScrollEnabled = false
        bodyView.delegate = self
        scroller.addSubview(bodyView)
        // Mail's paperclip in the body's shortcut bar, before the body can
        // take the caret (B-154).
        paperclipInTheShortcutBar()

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
        // The fields as shown: a reply's files as its first recipients have
        // it, before the letter is taken as it opened.
        followRecipients()
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
        centre.addObserver(self, selector: #selector(backInTheApp),
                           name: UIApplication.willEnterForegroundNotification, object: nil)
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
        // No bound on what is coming in runs while the app is away, and
        // the photo or video being read in is called off and set aside,
        // a video's conversion with it, before the letter is kept: Photos'
        // copy of a large video, left running, got the app ended within a
        // minute, the letter with it (`ComposeIntake.away`, B-142). So the
        // keep waits for nothing set aside, and gives its background time
        // back at once. With a Send or a Save Draft waiting for it, the
        // read has 20 seconds first.
        intake.away()
        actions.putAside { self.currentLetter() }
    }

    @objc private func backInTheApp() {
        // What was set aside is read again, with three minutes from now.
        intake.back()
    }

    /// The presented navigation controller is the sheet, and it is its
    /// modality and its presentation that count.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isModalInPresentation = true
        navigationController?.presentationController?.delegate = self
    }

    /// The letter opens ready to type, as Mail's does (B-120).
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        readyToType()
    }

    /// The keyboard up and the caret where Mail's composer puts it
    /// (`ComposeForm.firstField`): in To for a new letter and a forward, at
    /// the top of the body, above his signature and the quote, for a reply
    /// and a draft reopened from Drafts, in Subject for a letter to someone
    /// with none. It gave focus to nothing, and his tap put the caret
    /// wherever his finger landed, often in the quote.
    ///
    /// The first time the sheet appears and never again, so a caret he has
    /// put somewhere stays there; not with anything put up over the sheet,
    /// nor once he is in a field himself (`ComposeForm.readiesOnAppearing`).
    private func readyToType() {
        let fields: [UIView] = [toField, ccField, bccField, subjectField, bodyView]
        let inAField = fields.contains { $0.isFirstResponder }
        defer { readied = true }
        guard ComposeForm.readiesOnAppearing(done: readied, covered: presentedViewController != nil,
                                             inAField: inAField) else { return }
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

    /// The caret into the body: Cc and Bcc fold back if nobody is in them
    /// (`caretWentInto`, B-134).
    func textViewDidBeginEditing(_ textView: UITextView) {
        caretWentInto(ccOrBcc: false)
    }

    /// The caret into Subject: the same.
    func textFieldDidBeginEditing(_ textField: UITextField) {
        caretWentInto(ccOrBcc: false)
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

    /// The permanent "Photo Library" and "Attach File" controls, side by
    /// side under the files, with Mail's names for the two it offers
    /// (B-108).
    ///
    /// Labelled buttons as well as Mail's paperclip, which hangs at the
    /// right of the keyboard's shortcut bar and comes and goes with the
    /// keyboard (`paperclipInTheShortcutBar`, B-154), and rather than the
    /// callout menu Mail of this era used, because `BRIEF.md`'s promise is
    /// that nothing needs a gesture beyond tap and ordinary scrolling — and
    /// "press and hold in the body until a menu appears" is exactly the
    /// kind of thing that promise exists to rule out. Always visible, so
    /// they never move.
    private func attachRow() -> UIView {
        let container = UIView()
        let photos = attachButton(.photoLibrary, action: #selector(photoLibraryTapped))
        let files = attachButton(.attachFile, action: #selector(attachFileTapped))
        photoButton = photos
        fileButton = files

        let rule = UIView()
        rule.backgroundColor = Theme.separator
        for v in [photos, files, rule] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        NSLayoutConstraint.activate([
            photos.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            photos.topAnchor.constraint(equalTo: container.topAnchor),
            photos.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            files.leadingAnchor.constraint(equalTo: photos.trailingAnchor),
            files.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            files.topAnchor.constraint(equalTo: container.topAnchor),
            files.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: Theme.minHitTarget),
            rule.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                          constant: Theme.detailContentInsetLeft),
            rule.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        return container
    }

    /// One of the two: its symbol and its words, as tall as the row.
    private func attachButton(_ choice: ComposeForm.Attach, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: choice.symbol)
        // The size of the words beside it, fixed (D-007). Left to the
        // button, the symbol grew with the iPad's text size and the words
        // did not.
        config.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(font: Theme.fontDetailMeta)
        config.imagePadding = 6
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Theme.detailContentInsetLeft, bottom: 0, trailing: 0)
        var title = AttributedString(choice.words)
        title.font = Theme.fontDetailMeta
        config.attributedTitle = title
        button.configuration = config
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
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
        // What he chose and is still coming in, after them, in the order
        // he chose it (B-108).
        for coming in intake.coming {
            attachmentsStack.addArrangedSubview(comingRow(coming))
        }
    }

    /// Something on its way in: its name, and a spinner where its Remove
    /// will be once it is in (B-108). No Remove meanwhile: it is taken off
    /// once it has come.
    private func comingRow(_ coming: ComposeIntake.Coming) -> UIView {
        let container = UIView()
        let icon = UIImageView(image: UIImage(systemName: "paperclip"))
        icon.tintColor = Theme.secondaryText
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.font = Theme.fontDetailMeta
        label.textColor = Theme.secondaryText
        label.numberOfLines = 1
        label.text = coming.name

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()

        let rule = UIView()
        rule.backgroundColor = Theme.separator

        for v in [icon, label, spinner, rule] {
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
            spinner.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor,
                                             constant: 8),
            spinner.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                              constant: -Theme.detailContentInsetLeft),
            spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: Theme.minHitTarget),
            rule.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                          constant: Theme.detailContentInsetLeft),
            rule.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        return container
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
        // A photo or a file that lands while a letter goes rebuilds the
        // rows; its Remove is held with the rest.
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
        let removed = draft.attachments.remove(at: sender.tag)
        // One of a reply's files taken off is his choice: what is left stays.
        replyFiles?.removed(removed)
        rebuildAttachments()
        letterEdited()
    }

    /// A reply's files as its recipients now have it (`ReplyFiles`,
    /// B-107): put in after any of his own when someone is new, taken out
    /// when no one new is left. By default the bubbles, never what he is
    /// still typing, so the rows do not come and go as he spells an
    /// address; Send hands in everyone the letter would go to, what he is
    /// still typing too. Run as the fields are
    /// first shown, when the bubbles change under his hand, when he leaves
    /// a field, which makes a bubble of what he typed, and after a pick.
    ///
    /// Only while the sheet is his to change (`ComposeActions.isWriting`):
    /// nothing changes once a letter is on its way, or once Save Draft or
    /// Delete Draft has put the sheet away. Returns where the first row
    /// put in is, nil when none was.
    ///
    /// Rows a bubble puts in are told to VoiceOver, their words read after
    /// what it is saying, and it is left in the field he is in; a Send that
    /// puts them in takes it to them instead (`showRow`). Told nothing, a
    /// VoiceOver user's next Send carried files he had not heard of.
    @discardableResult
    private func followRecipients(to: [String]? = nil, cc: [String]? = nil,
                                  bcc: [String]? = nil) -> Int? {
        guard actions.isWriting, var files = replyFiles,
              let rows = files.recipientsChanged(to: to ?? toField.bubbles.entries,
                                                 cc: cc ?? ccField.bubbles.entries,
                                                 bcc: bcc ?? bccField.bubbles.entries,
                                                 in: draft.attachments) else { return nil }
        replyFiles = files
        let first = rows.count > draft.attachments.count ? draft.attachments.count : nil
        draft.attachments = rows
        rebuildAttachments()
        letterEdited()
        if let first, to == nil {
            let words = (first..<rows.count).compactMap { (attachmentWords(at: $0) as? UILabel)?.text }
            UIAccessibility.post(notification: .announcement, argument: NSAttributedString(
                string: words.joined(separator: ", "),
                attributes: [.accessibilitySpeechQueueAnnouncement: true]))
        }
        return first
    }

    /// The row at `index` brought into the part of the sheet showing, and
    /// VoiceOver taken to it: what a Send that put a reply's files in shows
    /// in place of sending. The rows are under To, Cc, Bcc and Subject, and
    /// with a Reply All's Cc of several lines and the keyboard up, the first
    /// of them could be below what showed: he saw a Send that did nothing,
    /// and his next tap sent files he had not seen.
    private func showRow(at index: Int) {
        view.layoutIfNeeded()
        let rows = attachmentsStack.arrangedSubviews
        if rows.indices.contains(index) {
            let row = rows[index]
            scroller.scrollRectToVisible(row.convert(row.bounds, to: scroller), animated: true)
        }
        UIAccessibility.post(notification: .layoutChanged, argument: attachmentWords(at: index))
    }

    /// The words of the row at `index`, which VoiceOver is moved to.
    private func attachmentWords(at index: Int) -> UIView? {
        let rows = attachmentsStack.arrangedSubviews
        guard rows.indices.contains(index) else { return nil }
        return rows[index].subviews.first { $0 is UILabel }
    }

    // MARK: - Photo Library and Attach File (B-108)

    /// Mail's paperclip at the right of the keyboard's shortcut bar while
    /// he types in the letter (B-154): a menu of Attach File and Photo
    /// Library, each opening the picker its button under the files opens.
    /// The buttons stay, always in sight, and the paperclip comes and goes
    /// with the keyboard, as Mail's does.
    ///
    /// The body's own bar alone (`inputAssistantItem`), so it is not there
    /// in To, Cc, Bcc or Subject, nor in the share sheet. After whatever the
    /// system puts at the right of the bar; the left of it, Undo, Redo and
    /// Paste, is left as it is. At the bottom of the screen, above the
    /// keyboard or, with a keyboard of keys, in the bar the system shows
    /// for it, so it is never over Send, which is in the sheet's bar at
    /// the top. The menu opens at a tap, as a bar button's with no action
    /// of its own does.
    private func paperclipInTheShortcutBar() {
        let menu = UIMenu(children: ComposeForm.Attach.paperclip.map { choice in
            UIAction(title: choice.words, image: UIImage(systemName: choice.symbol)) { [weak self] _ in
                switch choice {
                case .attachFile:   self?.attachFileTapped()
                case .photoLibrary: self?.photoLibraryTapped()
                }
            }
        })
        let paperclip = UIBarButtonItem(image: UIImage(systemName: ComposeForm.Attach.paperclipSymbol),
                                        menu: menu)
        paperclip.accessibilityLabel = ComposeForm.Attach.paperclipName
        paperclipItem = paperclip
        let bar = bodyView.inputAssistantItem
        bar.trailingBarButtonGroups = bar.trailingBarButtonGroups
            + [UIBarButtonItemGroup(barButtonItems: [paperclip], representativeItem: nil)]
    }

    @objc private func photoLibraryTapped() {
        // PHPicker, not the old image picker, and the difference is a
        // permission prompt. PHPicker runs out of process and hands back
        // only what he chose, so it needs no photo-library access at all —
        // which matters because a "Don't Allow" tapped once by a
        // 90-year-old is invisible, permanent, and looks like the button
        // being broken.
        var config = PHPickerConfiguration()
        // Photos and videos, as Mail's Photo Library offers both.
        config.filter = .any(of: [.images, .videos])
        config.selectionLimit = 5
        // What Photos keeps, with no copy made (B-142). Photos' compatible
        // copy of a video was made under a file coordination claim on the
        // app, which calling the read off did not end, and iOS ended the
        // app half a minute after he left it, his letter with it (the test
        // iPad, 2026-10-26). A HEIC photo is made a JPEG by the share
        // sheet's intake (`SharedPhoto.way`), at its own size where it fits
        // (`ComposeIntake.staging`), as Photos' JPEG of it went. A video is
        // made H.264 here (`VideoConversion.h264`), at its own size, or at
        // 720p where only that fits the letter, and is left out where
        // neither does, as a compatible copy over the room was: what goes
        // is H.264, which every recipient can open, never the HEVC original.
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    /// What he chose, read in as the share sheet reads what it is shared
    /// (`ShareItems.read`): a photo as Apple Mail sends it, its own bytes
    /// under its own name, its metadata replaced and no place in it, made
    /// a JPEG only when it has to be, as a HEIC is, at its own size where
    /// it fits; a video as the file Photos hands over where it is H.264
    /// already, and otherwise as an H.264 copy of it that fits, or not at
    /// all (`ShareItems.compatible`, B-142). One at a time, onto the
    /// disk, each counted until it is in so
    /// that a Send or a Save Draft tapped meanwhile waits for it, rather
    /// than going without it (`ComposeIntake`).
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        intake.take(results.map { result in
            let provider = result.itemProvider
            // What it is, by the types it offers, for the words should it
            // be counted out before it begins; with no name, the row says
            // "Photo" or "Video" (`ComposeIntake.Item`).
            let kind = ComposeIntake.kind(offered: provider.registeredTypeIdentifiers,
                                          isMovie: { UTType($0)?.conforms(to: .movie) == true })
            return ComposeIntake.Item(name: provider.suggestedName, kind: kind) { staging, tally, done in
                ShareItems.read(provider, title: nil, staging: staging, tally: tally, videos: .h264,
                                done: done)
            }
        })
    }

    @objc private func attachFileTapped() {
        // Any file, as Mail's Attach File offers, each picked one copied by
        // the picker into the app's Inbox, which is the app's own to read:
        // no permission, no security-scoped access, no Info.plist key. A
        // folder or a package is not a file it offers.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.data],
                                                    asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    /// Each moved out of the Inbox into the letter's staging, measured and
    /// refused past the letter's room, its type from its extension
    /// (`ComposeIntake.file`).
    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        intake.take(urls.map { url in
            ComposeIntake.file(at: url, mimeType: { UTType(filenameExtension: $0)?.preferredMIMEType })
        })
    }

    /// Something he chose, in the letter. Staged on disk rather than held
    /// in the draft: a composer left open for an hour should not also be
    /// holding several megabytes of image in memory. Safe against the
    /// launch-time purge because a SAVED draft embeds its bytes on the
    /// server and reopens as a message part, and a letter kept on the iPad
    /// links its files into its own directory (`LocalDraftStore.keep`), so
    /// nothing in the staging has to outlive this composer, which removes
    /// what it staged as it goes (`staged`).
    private func landed(_ url: URL, _ row: DraftAttachment) {
        staged.record(url)
        draft.attachments.append(row)
        rebuildAttachments()
        letterEdited()
    }

    /// What could not be attached, said over the sheet in an alert, once
    /// nothing else is up over it: the picker sliding away, or a notice
    /// already up, which UIKit would not put another over. Nothing once
    /// the sheet has gone. With its title, where it has one: Mail's
    /// "Unable to Attach" for a file (B-144).
    private func say(_ alert: MailAlert) {
        guard viewIfLoaded?.window != nil else { return }
        guard presentedViewController == nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.say(alert)
            }
            return
        }
        ErrorPresenter.say(alert, on: self)
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
        // Subject alone since B-076: To, Cc and Bcc are `addressRow`'s, and
        // keep `RecipientField`'s email keyboard, no capitals, no
        // corrections and straight quotes. Subject types as Mail's does
        // (B-121): a capital to begin, corrections, and Smart Punctuation
        // as Settings has it. Mail's composer sets none of these on its
        // Subject, so the system's own are its. They were off, left from
        // when this row served the address fields too, and his subjects
        // began in lower case.
        field.autocapitalizationType = .sentences
        field.autocorrectionType = .default
        field.smartDashesType = .default
        field.smartQuotesType = .default
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
        field.addTarget(self, action: #selector(addressBubbleTapped(_:)), for: .valueChanged)

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
    /// open under another field. Cc and Bcc stay open with the caret in
    /// one of them, and fold back as it goes into To with nobody in them
    /// (`caretWentInto`, B-134).
    @objc private func addressEditingBegan(_ field: RecipientField) {
        activeAddressField = field
        refreshSuggestions(after: .entered)
        caretWentInto(ccOrBcc: field === ccField || field === bccField)
    }

    /// A bubble tapped, its menu about to go up (B-134). The list closes,
    /// so the menu never stands over it, as Mail never has a person's card
    /// and its list up at once. The caret goes into the bubble's field, as
    /// Mail's tap puts it there, so letters typed next take the bubble's
    /// place (`RecipientBubbles.typingTakesThePicked`) rather than going
    /// into another field under the menu. Only while a field has it: with
    /// the keyboard put away it stays away, since the sheet rising under
    /// the menu as it opens is what put the menu beside its bubble on the
    /// iPad (B-078).
    @objc private func addressBubbleTapped(_ field: RecipientField) {
        let fields: [UIView] = [toField, ccField, bccField, subjectField, bodyView]
        if !field.isFirstResponder, fields.contains(where: { $0.isFirstResponder }) {
            field.becomeFirstResponder()
        }
        activeAddressField = field
        refreshSuggestions(after: .bubbleTapped)
    }

    @objc private func addressEditingChanged(_ field: RecipientField) {
        activeAddressField = field
        refreshSuggestions(after: .typed)
        updateSend()
        followRecipients()
        // iOS's question for his Contacts, the first time he ever types in
        // an address field, and never again once answered (B-162).
        AddressContacts.shared.heTyped { [weak self] in self?.contactsCameIn() }
    }

    /// His Contacts read at his yes (B-162): the list offered again, with
    /// them, for what the field holds, while he is still in it. What last
    /// happened there decides, so a list a pick had closed stays closed.
    private func contactsCameIn() {
        guard let field = activeAddressField, field.isEditing else { return }
        refreshSuggestions(after: lastAddressEvent)
    }

    /// Leaving the field, which has made a bubble of what he typed and
    /// sends this alone, no change of its own (`RecipientField.ended`).
    @objc private func addressEditingEnded(_ field: RecipientField) {
        followRecipients()
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
    /// nothing once he has picked one, until he types again. From the book
    /// and from his Contacts, as Mail offers them (B-162).
    private func refreshSuggestions(after event: ComposeForm.FieldEvent) {
        guard let field = activeAddressField else { return }
        lastAddressEvent = event
        suggestions = ComposeForm.suggestions(RecipientBook.shared.snapshot(),
                                              contacts: AddressContacts.shared.snapshot(),
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
        // again at once with his most used over Cc, Subject and the
        // buttons for files.
        refreshSuggestions(after: .picked)
        updateSend()
        // Set by hand, the field sends no change of its own.
        letterEdited()
        followRecipients()
    }

    /// "Cc/Bcc": Cc and Bcc open, the row gone, the caret in Cc, as Mail's
    /// "Cc/Bcc, From:" does (B-134). It was a switch: a second tap hid them
    /// again, people in them or not.
    @objc private func openCcAndBcc() {
        showCcAndBcc(true)
        ccField.becomeFirstResponder()
    }

    /// The caret has gone into a field: Cc and Bcc stand open while it is
    /// in one of them or either holds someone, and fold back into the
    /// "Cc/Bcc" row otherwise, by Mail's rule (`ComposeForm.showsCcAndBcc`).
    private func caretWentInto(ccOrBcc: Bool) {
        showCcAndBcc(ComposeForm.showsCcAndBcc(inCcOrBcc: ccOrBcc, cc: ccField.recipients,
                                               bcc: bccField.recipients))
    }

    /// Cc and Bcc shown, and the "Cc/Bcc" row hidden, or the other way.
    private func showCcAndBcc(_ open: Bool) {
        guard open != ccVisible else { return }
        ccVisible = open
        ccRow.isHidden = !open
        bccRow.isHidden = !open
        ccToggleRow.isHidden = open
    }

    @objc private func cancelTapped() {
        // Nothing while a letter goes, when a swipe still lands here, nor
        // with the question already up.
        guard !actions.isSending, presentedViewController == nil else { return }
        // Asked only about a letter he has changed, as Mail asks
        // (`ComposeForm.asksBeforeClosing`). A new letter opens with his
        // signature in it, and asking whenever the body had anything in it
        // asked every time. A photo or a file still coming in is a change,
        // and so is a Send the server refused (`ComposeActions.asksAnyway`).
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
            // A reply to someone he typed and never made a bubble (B-107):
            // the rows go into the draft he saves, as Send would put them
            // in, nothing being sent. Reopened from Drafts or the iPad,
            // where no rule follows it, it would otherwise go to that
            // person without the files, unseen.
            let collected = self.draft
            if self.replyFiles?.wouldAdd(to: collected.to, cc: collected.cc,
                                         bcc: collected.bcc) == true {
                self.followRecipients(to: collected.to, cc: collected.cc, bcc: collected.bcc)
            }
            // The order, the background time around the save, and the wait
            // for photos and files still on their way in are
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
        // from a bar button is said to leave its bar live; this one does
        // not. On the iPad the action sheet's popover takes any tap outside
        // it, Send's bar included, and closes on it, and that tap never
        // reaches here; a second tap, the sheet gone, sends. The owner's
        // ruling, 2026-10-21: left as it is, as Mail has it (B-044). So a
        // tap does not reach what follows with that sheet up. It stays for
        // anything up here that a tap on Send does get past, which the iPad
        // has not shown, and puts it away first unless it is going
        // already: a Cancel sheet's Save Draft and Delete Draft would do
        // nothing now, and a failure has to be said over this sheet, which
        // cannot put up an alert while it has something else up.
        if let shown = presentedViewController, !shown.isBeingDismissed {
            shown.dismiss(animated: true)
        }
        // The fields as they are at the tap; the letter itself is taken
        // once any photo or file still on its way in has landed in it.
        collect()
        // A reply to someone new carries the original's files (B-107). An
        // address he typed and never made a bubble, which reaches the
        // letter with no change sent, can call for them only now: then
        // they go in, VoiceOver is taken to the first, and nothing is sent.
        // His next tap sends. A reply never goes without the files the rule
        // calls for, nor with files he has not seen.
        if replyFiles?.wouldAdd(to: draft.to, cc: draft.cc, bcc: draft.bcc) == true {
            if let first = followRecipients(to: draft.to, cc: draft.cc, bcc: draft.bcc) {
                showRow(at: first)
            }
            return
        }
        actions.send({ self.draft }, then: onDraftsChanged, draftSent: onDraftSent)
    }

    /// Puts the sheet away, with whatever it has up over itself.
    ///
    /// Told to whatever presented the sheet, not to the sheet. A view
    /// controller told to dismiss while it is presenting something
    /// dismisses that instead and stays. With an alert over the sheet when
    /// the letter went, about a file that could not be attached, or the
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
    /// the spinner and its words where Send was, and Cancel, Photo Library,
    /// Attach File, the paperclip and every Remove held, since the one
    /// thing that must not happen then is the letter being lost or sent
    /// twice. After a failure everything is live again. The sheet is never
    /// let go by a swipe (`viewDidLoad`), and a swipe while a letter goes
    /// asks nothing (`cancelTapped`).
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
        photoButton?.isEnabled = !sending
        fileButton?.isEnabled = !sending
        paperclipItem?.isEnabled = !sending
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
