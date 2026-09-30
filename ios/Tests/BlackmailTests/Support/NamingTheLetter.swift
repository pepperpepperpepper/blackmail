import Foundation
@testable import Blackmail

/// A write and a letter opened as the app makes them: naming the Gmail
/// message id of the row he acted on, and its mailbox as the row has it,
/// as the list, Edit mode, the reading pane, Drafts and `PaneActions` do
/// (D-016). For every suite that has a row at hand, so the wire it pins is
/// the wire the app sends for that row. A landed draft reopened by the id
/// its upload gave it is `NamingNoLetter`'s; a draft removed names none by
/// `deleteDraft`'s own signature.
extension MailRepository {

    func open(_ row: MessageSummary) async throws -> Message {
        try await loadMessage(id: row.id, gmailMessageID: row.gmailMessageID, mailboxID: row.mailboxID)
    }

    func reopen(_ row: MessageSummary) async throws -> Draft {
        try await loadDraft(id: row.id, gmailMessageID: row.gmailMessageID, mailboxID: row.mailboxID)
    }

    func setRead(_ read: Bool, on row: MessageSummary) async throws {
        try await setRead(read, id: row.id, gmailMessageID: row.gmailMessageID,
                          mailboxID: row.mailboxID)
    }

    func setFlagged(_ flagged: Bool, on row: MessageSummary) async throws {
        try await setFlagged(flagged, id: row.id, gmailMessageID: row.gmailMessageID,
                             mailboxID: row.mailboxID)
    }

    func move(_ row: MessageSummary, to destination: String) async throws {
        try await move(row.id, gmailMessageID: row.gmailMessageID, from: row.mailboxID,
                       to: destination)
    }

    func delete(_ row: MessageSummary) async throws {
        try await delete(row.id, gmailMessageID: row.gmailMessageID, from: row.mailboxID)
    }
}
