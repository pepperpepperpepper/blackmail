// Guarded so this file compiles away on a host without UIKit.
#if canImport(UIKit)

import UIKit

/// The one screen that is not mail: his signature, his name, and the
/// password when Google makes him change it.
///
/// It exists because the app already told him to come here. `MailError`
/// has said **"Password needs to be updated in Settings."** since the error
/// strings were written, and there was no Settings — an instruction
/// pointing at a screen that did not exist, which for this user is worse
/// than no instruction at all, because he would go looking.
///
/// Deliberately not styled like the mail interface, for the same reason
/// `AccountSetupViewController` is not: the mail screens are frozen to a
/// layout his hands know, and this one has no such history. It is a plain,
/// legible form.
///
/// The password is left BLANK on opening and only written if he types
/// something. Prefilling it would mean a stray keystroke could replace a
/// working credential with a broken one, and the failure would not show up
/// until the next time he tried to read his mail.
final class SettingsViewController: UIViewController, UITextViewDelegate {

    /// Called when something was saved, so the caller can rebuild anything
    /// holding the old account.
    var onSaved: ((MailAccount) -> Void)?
    /// Fired the moment the grouping switch moves. It acts immediately
    /// rather than waiting for Save, because it is a way of LOOKING at the
    /// mail rather than a fact about the account — and because leaving a
    /// switch visibly flipped with nothing behind it changing until another
    /// button is pressed is its own kind of trap.
    var onOrganizeByThreadChanged: (() -> Void)?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let nameField = UITextField()
    private let passwordField = UITextField()
    private let signatureView = UITextView()
    private let signatureHint = UILabel()
    private let plainOnlyButton = UIButton(type: .system)
    private let organizeSwitch = UISwitch()
    private let statusLabel = UILabel()

    private var account: MailAccount

    init(account: MailAccount) {
        self.account = account
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.canvas
        title = "Settings"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Save", style: .done, target: self, action: #selector(saveTapped))
        for item in [navigationItem.leftBarButtonItem, navigationItem.rightBarButtonItem] {
            item?.setTitleTextAttributes([.font: Theme.fontBarButton], for: .normal)
        }

        let addressLabel = UILabel()
        addressLabel.text = account.address
        addressLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        addressLabel.textColor = Theme.primaryText

        stack.addArrangedSubview(addressLabel)
        stack.addArrangedSubview(caption("Your name, as recipients will see it"))
        configure(nameField, placeholder: "your name", secure: false)
        nameField.text = account.displayName
        stack.addArrangedSubview(nameField)

        stack.addArrangedSubview(caption("Signature — added to the bottom of everything you send"))
        signatureView.font = .systemFont(ofSize: 17)
        signatureView.textColor = Theme.primaryText
        signatureView.backgroundColor = Theme.barFill
        signatureView.layer.cornerRadius = 6
        signatureView.layer.borderWidth = 1
        signatureView.layer.borderColor = Theme.separator.cgColor
        signatureView.text = account.signature
        signatureView.delegate = self
        // Smart punctuation off, exactly as in the composer: a signature is
        // the one piece of text that gets sent thousands of times, and
        // having iOS turn his "--" into an em dash behind his back is not
        // help.
        signatureView.smartDashesType = .no
        signatureView.smartQuotesType = .no
        signatureView.autocorrectionType = .no
        signatureView.heightAnchor.constraint(equalToConstant: 140).isActive = true
        stack.addArrangedSubview(signatureView)

        signatureHint.numberOfLines = 0
        signatureHint.font = .systemFont(ofSize: 13)
        signatureHint.textColor = Theme.secondaryText
        stack.addArrangedSubview(signatureHint)

        // Only appears for an account that HAS a formatted signature, and
        // its whole job is to be the way out. The markup itself is not
        // editable here on purpose — it is five kilobytes of nested tables,
        // and a text field is a place to break it silently, since nothing on
        // this device could then show him that every letter he sends now
        // renders as raw HTML. Removing it is safe, so removing it is what
        // this offers.
        plainOnlyButton.setTitle("Send my signature as plain text instead", for: .normal)
        plainOnlyButton.setTitleColor(Theme.tintBlue, for: .normal)
        plainOnlyButton.titleLabel?.font = .systemFont(ofSize: 15)
        plainOnlyButton.contentHorizontalAlignment = .leading
        plainOnlyButton.addTarget(self, action: #selector(dropFormatting), for: .touchUpInside)
        plainOnlyButton.isHidden = account.signatureHTML.isEmpty
        stack.addArrangedSubview(plainOnlyButton)

        updateSignatureHint()

        stack.addArrangedSubview(caption("New app password — leave blank to keep the one you have"))
        // Masked only when the device can actually mask it. Same constraint
        // as the setup form, same reason: see D-011 and B-009.
        let masked = Self.deviceHasPasscode()
        configure(passwordField,
                  placeholder: masked ? "app password (16 letters)"
                                      : "app password (16 letters, shown as you type)",
                  secure: masked)
        stack.addArrangedSubview(passwordField)

        // Mail's own switch, and the off switch for conversation grouping.
        // Grouping stays the default — it is what Mail does, the rows
        // announce their own size ("Margaret, Carlo (3)"), and measurement
        // against his mail found it disturbs no date by even a week. But
        // three of twelve recent letters from him are about something
        // vanishing, and if he ever decides the merged rows are why, this
        // is here in plain words rather than a code change.
        let organizeRow = UIStackView(arrangedSubviews: [organizeLabel(), organizeSwitch])
        organizeRow.axis = .horizontal
        organizeRow.alignment = .center
        organizeRow.spacing = 12
        stack.addArrangedSubview(organizeRow)
        stack.addArrangedSubview(caption(
            "Group a conversation and its replies into one row. "
            + "Turn off to show every message separately."))
        organizeSwitch.isOn = ConversationSettings.organizeByThread
        organizeSwitch.addTarget(self, action: #selector(organizeToggled),
                                 for: .valueChanged)

        statusLabel.numberOfLines = 0
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textColor = Theme.secondaryText
        stack.addArrangedSubview(statusLabel)

        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .none
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        let content = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            stack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            // The content guide's WIDTH, which nothing else states.
            //
            // The stack is bounded by the content guide vertically but only
            // CENTRED on the frame guide horizontally, so the scroll view's
            // content width was never determined and the whole scroll view
            // came back `hasAmbiguousLayout` — found by the layout sweep,
            // not by looking, which is the point of the sweep. Tying the
            // content guide to the frame guide is the canonical way to say
            // "this scrolls vertically only".
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            stack.widthAnchor.constraint(equalToConstant: 520),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardChanged),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    private func caption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 14)
        label.textColor = Theme.secondaryText
        return label
    }

    private func configure(_ field: UITextField, placeholder: String, secure: Bool) {
        field.placeholder = placeholder
        field.isSecureTextEntry = secure
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 18)
        field.heightAnchor.constraint(equalToConstant: Theme.minHitTarget).isActive = true
    }

    /// See `AccountSetupViewController` — the same iOS constraint decides
    /// whether a secure field is usable at all.
    private static func deviceHasPasscode() -> Bool {
        AccountSetupViewController.deviceHasPasscode()
    }

    func textViewDidChange(_ textView: UITextView) { updateSignatureHint() }

    /// Shows what the signature will look like on the wire.
    ///
    /// It says whether a FORMATTED signature is in use because the box above
    /// cannot show one: the text there is the plain half, and a man editing
    /// it would otherwise have no way of knowing that what recipients
    /// actually see is a photograph and a two-column table. The line also
    /// says which parts of what he types will and will not reach them.
    private func updateSignatureHint() {
        let text = signatureView.text ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            signatureHint.text = "No signature. Nothing will be added to your messages."
            return
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        let counted = "\(lines) line\(lines == 1 ? "" : "s")"
        if account.signatureHTML.isEmpty {
            signatureHint.text = counted + ", added to the bottom of your messages."
        } else {
            // Deliberately does not describe what is IN the markup. An
            // earlier draft of this line promised a photograph, which had
            // been dropped from the stored signature for pointing at a URL
            // that no longer serves it — so the app was telling him his
            // letters carried something they did not.
            signatureHint.text = counted + ". Your messages carry a formatted version "
                + "of this as well, which is what most people will see. "
                + "Editing the text here changes what everyone else sees."
        }
    }

    /// The row's label, out here so the switch and it stay one control.
    private func organizeLabel() -> UILabel {
        let label = UILabel()
        label.text = "Organize by Thread"
        label.font = .systemFont(ofSize: 17)
        label.textColor = Theme.primaryText
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    @objc private func organizeToggled() {
        ConversationSettings.organizeByThread = organizeSwitch.isOn
        onOrganizeByThreadChanged?()
    }

    /// Throws the markup away and sends the text above instead.
    @objc private func dropFormatting() {
        account.signatureHTML = ""
        plainOnlyButton.isHidden = true
        updateSignatureHint()
    }

    // MARK: - Keyboard

    @objc private func keyboardChanged(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                as? CGRect else { return }
        let overlap = max(0, view.bounds.maxY - view.convert(frame, from: nil).minY)
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
    }

    // MARK: - Saving

    @objc private func cancelTapped() { dismiss(animated: true) }

    @objc private func saveTapped() {
        var updated = account
        updated.displayName = (nameField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // The signature keeps its internal line breaks and its leading
        // spaces — people indent signatures — and loses only the blank
        // lines at either end, which are supplied by the block builder.
        updated.signature = (signatureView.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let newPassword = (passwordField.text ?? "")
            .components(separatedBy: .whitespacesAndNewlines).joined()

        // A name or signature change touches nothing the server knows, so
        // it saves without a round trip. A PASSWORD is different: storing
        // one that does not work leaves him with a mailbox that stopped
        // loading and no way to tell whether he mistyped it. Same rule as
        // setup — prove it, then keep it.
        guard !newPassword.isEmpty else {
            save(updated, password: nil)
            return
        }

        statusLabel.text = "Checking the new password with Gmail…"
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task { @MainActor in
            defer { navigationItem.rightBarButtonItem?.isEnabled = true }
            do {
                let probe = IMAPClient(account: updated)
                try await probe.connect(password: newPassword)
                _ = try await probe.listMailboxes()
                await probe.disconnect()
                save(updated, password: newPassword)
            } catch MailError.passwordNeedsUpdating {
                statusLabel.text = "Google refused that password. Check it is an APP password."
            } catch {
                statusLabel.text = "Could not reach Gmail. Your old password is still in place."
            }
        }
    }

    private func save(_ updated: MailAccount, password: String?) {
        do {
            if let password {
                try CredentialStore.save(account: updated, password: password)
            } else {
                try CredentialStore.saveAccountOnly(updated)
            }
            onSaved?(updated)
            dismiss(animated: true)
        } catch {
            statusLabel.text = "Could not save. Nothing has been changed."
        }
    }
}

#endif
