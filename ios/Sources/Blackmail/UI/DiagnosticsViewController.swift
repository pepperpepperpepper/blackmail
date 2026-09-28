// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

/// The protocol transcript, for whoever is supporting this over the phone.
///
/// Deliberately hard to reach. `PRODUCT_SPEC.md` forbids showing raw protocol
/// text to the user, and it is right to: "BAD Command Argument Error. 11"
/// teaches a 90-year-old only that he has broken something, which he has not.
/// So there is no button — it opens on a five-tap on the status label in the
/// message list, a gesture nobody arrives at by accident.
///
/// Everything here has already been redacted on the way into the store, so
/// this screen cannot leak a credential even if the transcript is copied out
/// and emailed to someone. See `Diagnostics.redact`.
final class DiagnosticsViewController: UIViewController {

    private let textView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.canvas
        title = "Connection log"

        // Monospaced, because a protocol transcript is columns of tags and
        // codes and proportional type makes them unreadable.
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = Theme.primaryText
        textView.backgroundColor = Theme.canvas
        textView.isEditable = false
        textView.alwaysBounceVertical = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Done", style: .done, target: self, action: #selector(done))
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(share)),
            UIBarButtonItem(title: "Clear", style: .plain, target: self, action: #selector(clear)),
            layoutAuditButton,
        ]
        updateLayoutAuditButton()

        reload()
    }

    /// The one writer of `LayoutAudit.enabledKey`. The audit is off for him
    /// and costs main-thread time while it runs, so whoever is developing
    /// turns it on here, on the one screen he never sees. See
    /// `LayoutAudit.enabledKey`.
    private lazy var layoutAuditButton = UIBarButtonItem(
        title: nil, style: .plain, target: self, action: #selector(toggleLayoutAudit))

    private func updateLayoutAuditButton() {
        layoutAuditButton.title = LayoutAudit.isEnabled ? "Layout: On" : "Layout: Off"
    }

    @objc private func toggleLayoutAudit() {
        if LayoutAudit.isEnabled {
            UserDefaults.standard.removeObject(forKey: LayoutAudit.enabledKey)
            LayoutAudit.stopSweeping()
            Diagnostics.log(.note, "layout: audit switched off")
        } else {
            UserDefaults.standard.set(true, forKey: LayoutAudit.enabledKey)
            let found = LayoutAudit.sweepNow()
            Diagnostics.log(.note, "layout: audit switched on, \(found) new finding(s) "
                            + "on this screen; sweeping for three minutes, and at every "
                            + "launch until it is switched off")
            LayoutAudit.beginSweeping()
        }
        updateLayoutAuditButton()
        reload()
    }

    private func reload() {
        let text = Diagnostics.transcript()
        textView.text = text.isEmpty
            ? "Nothing logged yet.\n\nConnect or refresh, then come back."
            : text
        // Scroll to the bottom: the interesting end of a transcript is always
        // the most recent line, which is the one before it broke.
        guard !text.isEmpty else { return }
        let end = NSRange(location: (textView.text as NSString).length - 1, length: 1)
        textView.scrollRangeToVisible(end)
    }

    @objc private func done() { dismiss(animated: true) }

    @objc private func clear() {
        Diagnostics.clear()
        reload()
    }

    @objc private func share(_ sender: UIBarButtonItem) {
        let sheet = UIActivityViewController(activityItems: [Diagnostics.transcript()],
                                             applicationActivities: nil)
        // Required on iPad or presenting the sheet is a crash, not a no-op.
        sheet.popoverPresentationController?.barButtonItem = sender
        present(sheet, animated: true)
    }

    /// Attaches the hidden opening gesture to any view.
    ///
    /// Five taps rather than a long press: a long press is something a shaky
    /// hand produces by accident, and landing in a screen full of protocol
    /// text with no idea how you got there is exactly the disorientation this
    /// product exists to avoid.
    static func attachOpener(to view: UIView, presenter: @escaping () -> UIViewController?) {
        let tap = FiveTapGesture(presenter: presenter)
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tap.recognizer)
        objc_setAssociatedObject(view, &FiveTapGesture.key, tap, .OBJC_ASSOCIATION_RETAIN)
    }
}

/// Holds the target for the hidden gesture, since a `UIGestureRecognizer`
/// does not retain its target and nothing else here would keep it alive.
private final class FiveTapGesture: NSObject {
    static var key: UInt8 = 0
    private let presenter: () -> UIViewController?
    lazy var recognizer: UITapGestureRecognizer = {
        let r = UITapGestureRecognizer(target: self, action: #selector(fired))
        r.numberOfTapsRequired = 5
        return r
    }()

    init(presenter: @escaping () -> UIViewController?) {
        self.presenter = presenter
    }

    @objc private func fired() {
        guard let host = presenter() else { return }
        let nav = UINavigationController(rootViewController: DiagnosticsViewController())
        nav.modalPresentationStyle = .formSheet
        host.present(nav, animated: true)
    }
}

#endif
