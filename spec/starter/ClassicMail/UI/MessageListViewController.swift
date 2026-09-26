import UIKit

final class MessageListViewController: UITableViewController {
    private let repository: MailRepository
    private var messages: [MessageSummary] = []

    init(repository: MailRepository) {
        self.repository = repository
        super.init(style: .plain)
        title = "Inbox"
        navigationItem.largeTitleDisplayMode = .never
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Message")
        tableView.rowHeight = 74
        configureClassicToolbar()
        Task { await reloadInbox() }
    }

    private func configureClassicToolbar() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .compose, target: self, action: #selector(compose))
        ]
    }

    @objc private func compose() {
        // TODO: present ComposeViewController modally in classic form-sheet/full-screen style.
    }

    private func reloadInbox() async {
        do {
            messages = try await repository.listMessages(in: "inbox", page: 0)
            await MainActor.run { tableView.reloadData() }
        } catch {}
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { messages.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Message", for: indexPath)
        let message = messages[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = message.sender
        content.secondaryText = "\(message.subject)\n\(message.preview)"
        content.secondaryTextProperties.numberOfLines = 2
        content.textProperties.font = message.isRead ? .systemFont(ofSize: 16) : .boldSystemFont(ofSize: 16)
        cell.contentConfiguration = content
        cell.accessoryType = .none
        return cell
    }
}
