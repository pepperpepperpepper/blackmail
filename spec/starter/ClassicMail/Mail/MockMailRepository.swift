import Foundation

final class MockMailRepository: MailRepository {
    private let inbox = Mailbox(id: "inbox", name: "Inbox", unreadCount: 3, role: .inbox)

    func listMailboxes() async throws -> [Mailbox] {
        [
            inbox,
            Mailbox(id: "sent", name: "Sent", unreadCount: 0, role: .sent),
            Mailbox(id: "drafts", name: "Drafts", unreadCount: 0, role: .drafts),
            Mailbox(id: "trash", name: "Trash", unreadCount: 0, role: .trash)
        ]
    }

    func listMessages(in mailboxID: String, page: Int) async throws -> [MessageSummary] {
        guard mailboxID == "inbox" else { return [] }
        return (0..<20).map { index in
            MessageSummary(
                id: "msg-\(index)",
                mailboxID: mailboxID,
                sender: index % 2 == 0 ? "Jane Smith" : "Robert Miller",
                subject: index % 2 == 0 ? "Dinner on Thursday" : "Re: Photos",
                preview: "Here is a short preview of the message, in the compact style of classic Mail…",
                date: Date().addingTimeInterval(TimeInterval(-index * 3600)),
                isRead: index > 2,
                isFlagged: false
            )
        }
    }

    func loadMessage(id: String, mailboxID: String) async throws -> Message {
        Message(
            id: id,
            mailboxID: mailboxID,
            sender: "Jane Smith <jane@example.com>",
            to: ["friend@example.com"],
            cc: [],
            subject: "Dinner on Thursday",
            date: Date(),
            textBody: "Are we still on for dinner Thursday?\n\nJane",
            htmlBody: nil,
            attachments: []
        )
    }

    func markRead(_ id: String, mailboxID: String, read: Bool) async throws {}
    func move(_ id: String, from sourceMailboxID: String, to destinationMailboxID: String) async throws {}
    func delete(_ id: String, from mailboxID: String) async throws {}
    func send(_ draft: Draft) async throws {}
    func saveDraft(_ draft: Draft) async throws {}
}
