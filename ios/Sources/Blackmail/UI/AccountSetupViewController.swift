// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit
import LocalAuthentication

/// The one screen the OWNER uses and the end user never should: entering the
/// account once, on setup day.
///
/// Deliberately not styled like the rest of the app. The mail interface is
/// frozen to a 2016 layout because his hands know it; this screen has no such
/// history and no such user, so it is a plain, legible form.
///
/// It **verifies before it saves**. Storing an unverified password and letting
/// the app fail later would put a 90-year-old in front of a broken mailbox
/// with no way to tell whether the password, the network or the app was at
/// fault — and no way to fix any of them.
final class AccountSetupViewController: UIViewController, UITextFieldDelegate {

    /// Called once credentials are stored and proven to work, with what the
    /// check had to say of them, if anything, for the screens it builds to
    /// put up (`SignInCheck.Outcome`).
    var onConnected: ((MailAccount, String, MailAlert?) -> Void)?

    private let stack = UIStackView()
    private let scrollView = UIScrollView()

    private let addressField = UITextField()
    private let passwordField = UITextField()
    private let nameField = UITextField()
    private let connectButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.canvas
        title = "Set up mail"

        let heading = UILabel()
        heading.text = "Blackmail"
        heading.font = .systemFont(ofSize: 34, weight: .bold)
        heading.textColor = Theme.primaryText

        let explain = UILabel()
        explain.numberOfLines = 0
        explain.font = .systemFont(ofSize: 15)
        explain.textColor = Theme.secondaryText
        // Naming the app-password requirement here, rather than letting the
        // owner discover it through a failed login: Google rejects the normal
        // account password for IMAP outright, and the error it returns looks
        // identical to simply mistyping it.
        explain.text = """
            Gmail address and a Google APP PASSWORD — not the normal account \
            password, which Google will refuse. Make one at \
            myaccount.google.com/apppasswords with 2-Step Verification on.

            This is checked against the server before it is saved.
            """

        configure(addressField, placeholder: "name@gmail.com",
                  keyboard: .emailAddress, secure: false)
        // MASKED ONLY IF THE DEVICE HAS A PASSCODE. This is the whole of
        // B-009, and it was never a gesture problem.
        //
        // A secure text field makes iOS treat the form as a login form and
        // offer Password AutoFill. That feature REQUIRES a device passcode.
        // With none set, iOS puts up "Set A Passcode — To use passwords,
        // you must first set a passcode on your device" over the app, and
        // dismisses the keyboard to do it. From inside the app the only
        // visible effect is focus reaching the password field and the
        // keyboard vanishing — exactly the symptom three rounds of
        // deploys spent chasing through tap recognisers, `keyboardDismissMode`
        // and stale binaries. Photographed on device 2026-09-20.
        //
        // It is NOT a synthetic-touch artefact. A finger raises the same
        // dialog. The variable is the passcode, and the recipient's iPad
        // very plausibly has none — setting one is exactly the sort of
        // thing a 90-year-old gets talked out of.
        //
        // Suppressing AutoFill with `textContentType = ""` was tried first
        // and does NOT work; the dialog still appears. The trigger is the
        // secure field itself, so the only lever is not having one.
        //
        // Hence: ask whether a passcode exists, and mask only then. On an
        // ordinary iPad nothing changes and the password is hidden as you
        // would expect. On a passcode-less one it is visible — which is a
        // real trade and the right way round. This is a single-purpose,
        // revocable, mail-only app password, typed once on setup day with
        // somebody helping; a field that cannot be typed into at all is
        // worse than a visible one for that minute. If the owner would
        // rather it were masked, the fix is to set a passcode on the iPad,
        // and then it is.
        let masked = Self.deviceHasPasscode()
        configure(passwordField, placeholder: masked ? "app password (16 letters)"
                                                     : "app password (16 letters, shown as you type)",
                  keyboard: .default, secure: masked)
        if !masked {
            Diagnostics.log(.note, "setup: no device passcode, password field left unmasked")
        }
        configure(nameField, placeholder: "your name, as recipients will see it",
                  keyboard: .default, secure: false)
        nameField.returnKeyType = .go     // the last field submits

        connectButton.setTitle("Connect", for: .normal)
        connectButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .semibold)
        connectButton.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)
        connectButton.heightAnchor.constraint(equalToConstant: Theme.minHitTarget).isActive = true

        statusLabel.numberOfLines = 0
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textColor = Theme.secondaryText
        statusLabel.textAlignment = .center
        // The connection log is reachable from HERE too, not only from the
        // message list. This screen is where first contact fails, so it is
        // exactly where "could not reach Gmail" most needs to be turned into
        // what the server actually said — and if setup never succeeds, the
        // message list the other opener lives on is unreachable.
        DiagnosticsViewController.attachOpener(to: statusLabel) { [weak self] in self }

        for v in [heading, explain, addressField, passwordField, nameField,
                  connectButton, spinner, statusLabel] as [UIView] {
            stack.addArrangedSubview(v)
        }
        stack.axis = .vertical
        stack.spacing = 18
        stack.setCustomSpacing(30, after: explain)
        // A scroll view, not a centred stack that shuffles out of the
        // keyboard's way. Two attempts at shuffling were tried on device and
        // both failed: lifting by half the overlap slid the heading up under
        // the navigation title, and clamping the lift to the available
        // headroom put the last field and the Connect button back underneath
        // the keyboard. In landscape the keyboard takes half the screen and
        // this content simply does not fit beside it, so the honest answer is
        // that it scrolls.
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        // .none, NOT .interactive. Interactive dismissal closes the keyboard
        // as soon as the scroll view sees a downward drag, and a tap that
        // carries even a pixel of movement counts — so tapping from one field
        // to the next dismissed the keyboard instead of moving focus, and the
        // second field never became first responder. The keyboard's own hide
        // key and the Return key both still work.
        scrollView.keyboardDismissMode = .none
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        let content = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -32),
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

        // Without this the keyboard covers the password and name fields
        // entirely — verified on device, where the only way to reach the
        // password was to dismiss the keyboard first, with nothing on screen
        // to suggest that. A form you cannot fill in is not a form.
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardChanged),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardHidden),
            name: UIResponder.keyboardWillHideNotification, object: nil)

        // NO tap-to-dismiss gesture here, deliberately, and this is the
        // second attempt at it. A UITapGestureRecognizer on the root view
        // with cancelsTouchesInView = false ALSO fires for taps that land on
        // the text fields, and since such a tap both focuses the field and
        // calls endEditing, moving from one field to the next merely closed
        // the keyboard. On device it looked exactly like the taps were
        // missing. Restricting it with `touch.view is UIControl` does not fix
        // it either: the touch lands on a private content view INSIDE the
        // text field, which is not a UIControl.
        //
        // The scroll view's `keyboardDismissMode = .interactive` already
        // gives drag-to-dismiss, and the keyboard has its own hide key, so
        // the gesture bought nothing and cost the form.

        // Prefill from a previous setup, so fixing a password is not a retype
        // of everything. The password itself is never prefilled.
        if let existing = CredentialStore.loadAccount() {
            addressField.text = existing.address
            nameField.text = existing.displayName
        }
    }

    // MARK: - Keyboard

    @objc private func keyboardChanged(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                as? CGRect else { return }
        let overlap = view.bounds.maxY - view.convert(frame, from: nil).minY
        guard overlap > 0 else { return keyboardHidden() }
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
        // Bring whatever is being typed into into view, which is the whole
        // point: the field must never be the thing hidden by the keyboard
        // that appeared because you tapped it.
        if let focused = [addressField, passwordField, nameField].first(where: { $0.isFirstResponder }) {
            reveal(focused)
        }
    }

    @objc private func keyboardHidden() {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }



    /// Scrolls a field into view.
    ///
    /// The conversion matters and was wrong first time: the fields live
    /// inside the stack, so `field.frame` is in the STACK's coordinates, and
    /// handing that straight to `scrollRectToVisible` scrolls to the wrong
    /// place — on device, to nowhere at all. The 60 pt inset leaves the field
    /// clear of the keyboard's top edge rather than flush against it.
    private func reveal(_ field: UITextField) {
        // Deferred a runloop turn. Called inline from `textFieldShouldReturn`
        // the scroll silently did nothing on device: the keyboard inset and
        // the new first responder have not been applied yet, so UIKit still
        // reckons the field is visible and there is nothing to do.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let rect = self.scrollView.convert(field.bounds, from: field)
                .insetBy(dx: 0, dy: -12)

            // `scrollRectToVisible` is NOT used here, and that is the whole
            // fix for B-008. It measures against the scroll view's `bounds`,
            // and `bounds` extend underneath the keyboard — the keyboard is
            // accounted for by `contentInset`, not by shrinking the view. So
            // a field completely hidden behind the keyboard is "already
            // visible" as far as that method is concerned and it does
            // nothing at all, silently. Three attempts failed on device
            // against that one wrong assumption.
            //
            // The visible window is bounds MINUS the adjusted inset. Compute
            // the offset against that and set it directly.
            let inset = self.scrollView.adjustedContentInset
            let visibleHeight = self.scrollView.bounds.height - inset.top - inset.bottom
            guard visibleHeight > 0 else { return }

            let visibleTop = self.scrollView.contentOffset.y + inset.top
            let visibleBottom = visibleTop + visibleHeight

            var targetY = self.scrollView.contentOffset.y
            if rect.maxY > visibleBottom {
                targetY += rect.maxY - visibleBottom
            } else if rect.minY < visibleTop {
                targetY -= visibleTop - rect.minY
            } else {
                return                      // genuinely visible; leave it alone
            }

            // Clamped, or focusing the last field scrolls past the end and
            // rubber-bands back, which looks like a glitch rather than a
            // scroll.
            let lowest = -inset.top
            let highest = max(lowest,
                              self.scrollView.contentSize.height + inset.bottom
                                  - self.scrollView.bounds.height)
            targetY = min(max(targetY, lowest), highest)
            self.scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: true)
        }
    }

    // MARK: - Focus, and why it is logged

    /// Whether the iPad has a passcode, which is what decides if iOS's
    /// Password AutoFill is usable at all.
    ///
    /// `.deviceOwnerAuthentication` covers passcode, Touch ID and Face ID,
    /// and `canEvaluatePolicy` returns false with
    /// `LAError.passcodeNotSet` when there is no passcode — which is the
    /// exact condition that makes a secure field unusable here.
    static func deviceHasPasscode() -> Bool {
        var error: NSError?
        let can = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        if !can {
            Diagnostics.log(.note, "setup: no passcode (LAError \(error?.code ?? -1))")
        }
        return can
    }

    /// Which field this is, for the log. Never its contents.
    private func label(_ field: UITextField) -> String {
        switch field {
        case addressField:  return "address"
        case passwordField: return "password"
        case nameField:     return "name"
        default:            return "?"
        }
    }

    /// B-009 has survived three debugging attempts undiagnosed, and every round of it
    /// was spent guessing at causes — a dismiss gesture, the keyboard
    /// dismiss mode, a stale binary — and ruling them out one deploy at a
    /// time. What was never established is the single fact that splits the
    /// problem in half: whether the second field is *refused* focus, or
    /// whether it is granted focus and then loses it.
    ///
    /// These log lines settle that. Names only, never text, so this is safe
    /// in a transcript meant to be copied to somebody helping by telephone.
    func textFieldDidBeginEditing(_ field: UITextField) {
        Diagnostics.log(.note, "focus: \(label(field)) began editing")
    }

    func textFieldDidEndEditing(_ field: UITextField) {
        Diagnostics.log(.note, "focus: \(label(field)) ended editing")
    }

    /// Return moves to the next field, and submits from the last one, so the
    /// whole form can be filled without ever reaching for the screen.
    func textFieldShouldReturn(_ field: UITextField) -> Bool {
        Diagnostics.log(.note, "focus: return pressed in \(label(field))")
        switch field {
        case addressField:
            // The RESULT is logged. `becomeFirstResponder()` returning false
            // means UIKit declined — a different failure from it succeeding
            // and something resigning it a moment later, and the two have
            // never been told apart here.
            let accepted = passwordField.becomeFirstResponder()
            Diagnostics.log(.note, "focus: password becomeFirstResponder -> \(accepted)")
            reveal(passwordField)
        case passwordField:
            let accepted = nameField.becomeFirstResponder()
            Diagnostics.log(.note, "focus: name becomeFirstResponder -> \(accepted)")
            reveal(nameField)
        default:
            field.resignFirstResponder()
            connectTapped()
        }
        return false
    }

    private func configure(_ field: UITextField, placeholder: String,
                           keyboard: UIKeyboardType, secure: Bool) {
        field.delegate = self
        field.returnKeyType = .next
        field.placeholder = placeholder
        field.keyboardType = keyboard
        field.isSecureTextEntry = secure
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 18)
        field.heightAnchor.constraint(equalToConstant: Theme.minHitTarget).isActive = true
    }

    // MARK: - Connecting

    @objc private func connectTapped() {
        let address = (addressField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Google shows app passwords as "abcd efgh ijkl mnop". The spaces are
        // presentation only and a pasted password keeps them, so strip them
        // rather than reject a password the owner copied correctly.
        let password = (passwordField.text ?? "")
            .components(separatedBy: .whitespacesAndNewlines).joined()

        guard address.contains("@"), !password.isEmpty else {
            show("Enter the address and the app password.")
            return
        }

        // The account stored already, where it is this address's: setup is
        // shown again whenever the password cannot be read at launch, and
        // an account made afresh here saved over his signature.
        let account = MailAccount.settingUp(
            address, name: (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            over: CredentialStore.loadAccount())

        setBusy(true)
        Task { @MainActor in
            defer { setBusy(false) }
            // Prove both halves before saving. A password that reads mail
            // but cannot send is a state the owner should find out about
            // now, not the first time the end user replies to someone: it is
            // Gmail's wrong-account trap (B-033).
            let verdict = await SignInCheck.run(account: account, password: password,
                                                transport: TLSConnection.factory)
            let notice: MailAlert?
            switch SignInCheck.outcome(of: verdict, address: account.address, in: .setup) {
            case .keep(let said):
                notice = said
            case .refuse(let sentence):
                show(sentence)
                return
            }
            do {
                try CredentialStore.save(account: account, password: password)
                onConnected?(account, password, notice)
            } catch {
                show((error as? LocalizedError)?.errorDescription
                     ?? "Password could not be saved.")
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        connectButton.isEnabled = !busy
        addressField.isEnabled = !busy
        passwordField.isEnabled = !busy
        busy ? spinner.startAnimating() : spinner.stopAnimating()
        if busy { statusLabel.text = "Checking with Gmail…" }
    }

    private func show(_ text: String) {
        statusLabel.text = text
    }
}

#endif
