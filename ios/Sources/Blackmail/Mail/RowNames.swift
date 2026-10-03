import Foundation

/// Whom a row in the message list names on its top line: whom the letter is
/// from, except in Sent Mail, Drafts and the Outbox, where it names whom the
/// letter is to (B-060).
///
/// Mail does the same in those mailboxes, and for the reason this does: every
/// letter in them is his, so a row naming its sender says his own name on
/// every row. He sends some seventy letters a day and keeps nearly two
/// thousand drafts; with his name on all of them, the only way to find the
/// letter to Jane was to read the subjects.
///
/// Which folder a row was listed from decides it, not what the letter is: a
/// letter of his found by an All Mailboxes search is listed from All Mail,
/// as it is in All Mail itself, and is named by its sender, him, as Mail
/// names it in any mailbox that is not one of those three. In a list that
/// mixes his letters with other people's, his name is what tells them apart.
///
/// Out here rather than in the list's controller for the reason
/// `MessageThread.displayRow` is: the controller is UIKit and does not exist
/// on the machine the suite runs on. The controller only asks.
enum RowNames {

    /// What the top line says of a letter addressed to nobody yet, a draft
    /// begun and put aside: the words the Outbox's rows have used since
    /// B-052. Mail on the Mac marks such a draft "No Recipients"; what Mail
    /// on the iPad says was not found written down anywhere, so these are
    /// put to the owner (B-060).
    static let noRecipients = "No Recipients"

    /// One person a letter is to: as the row names them, and what tells two
    /// of them apart, which is the address, so the same person in To and in
    /// Cc, or written once with a name and once without, is named once.
    struct Recipient: Equatable {
        let key: String
        let name: String
    }

    /// Whether a row listed from `folderID`, in the list of `list`, names
    /// whom its letter is to: in Sent Mail, Drafts and the Outbox, for a row
    /// of that folder's own, its letters, its kept copy's, a search of it,
    /// the drafts kept on the iPad. Not for a row a search found elsewhere,
    /// as an All Mailboxes search finds in All Mail, Trash and Spam, which
    /// the list of Sent Mail shows when he searches all mailboxes from it.
    ///
    /// Every row of the folder's own carries the list's id exactly: the
    /// list asks the repository for its letters by it, the kept copy hands
    /// its rows back under it (`MailShelf.page(of:)`), and the drafts kept
    /// on the iPad and the Outbox's letters are listed under it.
    static func namesRecipients(listedFrom folderID: String, in list: Mailbox) -> Bool {
        switch list.role {
        case .sent?, .drafts?, .outbox?:
            return folderID == list.id
        default:
            return false
        }
    }

    /// Whom a row's letter is to: To first, then Cc, then Bcc, as the
    /// letter names them, each person once. Nil when the row does not know
    /// (`MessageSummary.to`), and the row names its sender as before.
    static func recipients(of row: MessageSummary) -> [Recipient]? {
        guard let to = row.to else { return nil }
        return recipients(to + row.cc + row.bcc)
    }

    /// `entries` as the people they name, in order, each once: the name,
    /// or the address where there is none, as the reading pane names them
    /// (`MailFormat.recipientName`). An entry left blank names nobody.
    static func recipients(_ entries: [String]) -> [Recipient] {
        var seen = Set<String>()
        var out: [Recipient] = []
        for entry in entries {
            let entry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.isEmpty else { continue }
            let key = MailFormat.bareAddress(entry).lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(Recipient(key: key, name: MailFormat.recipientName(entry)))
        }
        return out
    }

    /// The names as the top line has them, joined as Mail joins them,
    /// "Jane Example, sam@example.com", or "No Recipients" for none.
    static func line(_ names: [String]) -> String {
        names.isEmpty ? noRecipients : names.joined(separator: ", ")
    }
}
