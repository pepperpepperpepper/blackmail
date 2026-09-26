#if canImport(UIKit)
import UIKit

/// SPIKE ONLY — does this Xcode-less toolchain produce a loadable `.appex`?
///
/// It answers one question and nothing else: can SwiftPM on Linux, with
/// xtool's linker and zsign, emit an app extension that SpringBoard will
/// register and show in the share sheet. Everything about what the extension
/// should DO is deliberately absent until that is known (B-036).
@objc(ShareViewController)
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "Blackmail share extension loaded."
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 0

        let done = UIButton(type: .system)
        done.setTitle("Done", for: .normal)
        done.addTarget(self, action: #selector(finish), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, done])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
        ])
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
#endif
