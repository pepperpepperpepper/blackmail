import Foundation
@testable import Blackmail

/// A write and a letter opened naming no Gmail message id, as the app makes
/// them only where it has none to name: a draft reopened by the id its
/// upload gave it, before Drafts is listed again. A draft removed names
/// none by its own signature (`deleteDraft`), and a row listed from a
/// server without Gmail's extension has no id, so `NamingTheLetter` names
/// none for it. Such calls go by the kept copy's own rule
/// (`MailShelf.unproven`), which `KeptCopyTests` pins with these on Gmail's
/// rows in one test, the write naming no letter's. Also for the few calls
/// with no row at hand at all, a letter taken by its UID straight from the
/// scripted server where nothing has listed it: nothing of it is kept, so
/// it sends what naming a row this launch has listed sends. Every call
/// with a row names it, as the app does (`NamingTheLetter`).
extension MailRepository {

    func loadMessage(id: String, mailboxID: String) async throws -> Message {
        try await loadMessage(id: id, gmailMessageID: nil, mailboxID: mailboxID)
    }

    func setRead(_ read: Bool, id: String, mailboxID: String) async throws {
        try await setRead(read, id: id, gmailMessageID: nil, mailboxID: mailboxID)
    }

    func setFlagged(_ flagged: Bool, id: String, mailboxID: String) async throws {
        try await setFlagged(flagged, id: id, gmailMessageID: nil, mailboxID: mailboxID)
    }

    func move(_ id: String, from sourceMailboxID: String,
              to destinationMailboxID: String) async throws {
        try await move(id, gmailMessageID: nil, from: sourceMailboxID, to: destinationMailboxID)
    }

    func delete(_ id: String, from mailboxID: String) async throws {
        try await delete(id, gmailMessageID: nil, from: mailboxID)
    }

    func loadDraft(id: String, mailboxID: String) async throws -> Draft {
        try await loadDraft(id: id, gmailMessageID: nil, mailboxID: mailboxID)
    }
}
