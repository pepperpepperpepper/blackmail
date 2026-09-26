import UIKit

final class RootSplitViewController: UISplitViewController {
    private let repository: MailRepository

    init(repository: MailRepository) {
        self.repository = repository
        super.init(style: .tripleColumn)
        preferredDisplayMode = .oneBesideSecondary
        presentsWithGesture = false
        primaryBackgroundStyle = .sidebar
        configureColumns()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureColumns() {
        let mailboxes = UINavigationController(rootViewController: MailboxListViewController(repository: repository))
        let messages = UINavigationController(rootViewController: MessageListViewController(repository: repository))
        let detail = UINavigationController(rootViewController: MessageViewController(repository: repository))

        setViewController(mailboxes, for: .primary)
        setViewController(messages, for: .supplementary)
        setViewController(detail, for: .secondary)

        // TODO: tune these after matching the reference screenshot on the actual target iPad.
        preferredPrimaryColumnWidthFraction = 0.23
        preferredSupplementaryColumnWidthFraction = 0.30
    }
}
