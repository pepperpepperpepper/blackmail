import Foundation

protocol MailRepository {
    func listMailboxes() async throws -> [Mailbox]
    func listMessages(in mailboxID: String, page: Int) async throws -> [MessageSummary]
    func loadMessage(id: String, mailboxID: String) async throws -> Message
    func markRead(_ id: String, mailboxID: String, read: Bool) async throws
    func move(_ id: String, from sourceMailboxID: String, to destinationMailboxID: String) async throws
    func delete(_ id: String, from mailboxID: String) async throws
    func send(_ draft: Draft) async throws
    func saveDraft(_ draft: Draft) async throws
}
