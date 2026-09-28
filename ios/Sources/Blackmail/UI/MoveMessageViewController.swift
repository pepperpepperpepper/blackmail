// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

/// "Move to which folder?" — a plain list, one tap, done.
final class MoveMessageViewController: UITableViewController {

    private let repository: MailRepository
    private let excluding: String
    private let onPick: (Mailbox) -> Void
    private var mailboxes: [Mailbox] = []

    /// `excluding` is the folder the messages are already in. Offering it is
    /// a dead end: `move()` correctly does nothing when source and
    /// destination match, so the sheet closes and the mail stays put — which
    /// to the person who tapped it reads as the app ignoring him.
    init(repository: MailRepository, excluding: String, onPick: @escaping (Mailbox) -> Void) {
        self.repository = repository
        self.excluding = excluding
        self.onPick = onPick
        super.init(style: .plain)
        title = "Move to…"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Mailbox")
        tableView.rowHeight = Theme.mailboxRowHeightScaled
        tableView.separatorColor = Theme.separator
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel", style: .plain, target: self, action: #selector(cancel))
        navigationItem.leftBarButtonItem?.setTitleTextAttributes(
            [.font: Theme.fontBarButton], for: .normal)
        Task { @MainActor in
            // Names only, which is all a sheet of folder names needs: the
            // folders the pane last listed, or a LIST alone if it never has.
            // This used to be the whole sweep, a STATUS for every folder
            // whose count the sheet does not show, and the sheet sat empty
            // until it was done.
            let all = (try? await repository.folders()) ?? []
            // Case-insensitive, because the two sides genuinely disagree on
            // spelling: the list pane opens on the role word "inbox" at
            // launch, while LIST names the same folder "INBOX". An exact
            // compare would leave Inbox in its own picker on the one screen
            // the app always starts on.
            mailboxes = all.filter {
                $0.id.caseInsensitiveCompare(excluding) != .orderedSame
            }
            tableView.reloadData()
        }
    }

    @objc private func cancel() { dismiss(animated: true) }

    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { mailboxes.count }

    override func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = t.dequeueReusableCell(withIdentifier: "Mailbox", for: ip)
        var content = cell.defaultContentConfiguration()
        content.text = mailboxes[ip.row].name
        content.textProperties.font = Theme.fontMailboxName
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        let destination = mailboxes[ip.row]
        dismiss(animated: true) { [onPick] in onPick(destination) }
    }
}

#endif
