import UIKit

final class MailboxListViewController: UITableViewController {
    private let repository: MailRepository
    private var mailboxes: [Mailbox] = []

    init(repository: MailRepository) {
        self.repository = repository
        super.init(style: .plain)
        title = "Mailboxes"
        navigationItem.largeTitleDisplayMode = .never
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Mailbox")
        tableView.rowHeight = 44
        Task { await reload() }
    }

    private func reload() async {
        do {
            mailboxes = try await repository.listMailboxes()
            await MainActor.run { tableView.reloadData() }
        } catch {
            // TODO: route to user-safe error presenter + admin diagnostics.
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { mailboxes.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Mailbox", for: indexPath)
        let mailbox = mailboxes[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = mailbox.name
        if mailbox.unreadCount > 0 { content.secondaryText = "\(mailbox.unreadCount)" }
        cell.contentConfiguration = content
        return cell
    }
}
