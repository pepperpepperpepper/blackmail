import UIKit
import WebKit

final class MessageViewController: UIViewController {
    private let repository: MailRepository
    private let webView = WKWebView(frame: .zero)

    init(repository: MailRepository) {
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
        navigationItem.largeTitleDisplayMode = .never
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        configureClassicActions()
    }

    private func configureClassicActions() {
        let move = UIBarButtonItem(image: UIImage(systemName: "folder"), style: .plain, target: self, action: #selector(moveMessage))
        let trash = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(deleteMessage))
        let reply = UIBarButtonItem(image: UIImage(systemName: "arrowshape.turn.up.left"), style: .plain, target: self, action: #selector(replyMessage))
        let compose = UIBarButtonItem(barButtonSystemItem: .compose, target: self, action: #selector(compose))
        navigationItem.rightBarButtonItems = [compose, reply, trash, move]
    }

    @objc private func moveMessage() {}
    @objc private func deleteMessage() {}
    @objc private func replyMessage() {}
    @objc private func compose() {}
}
