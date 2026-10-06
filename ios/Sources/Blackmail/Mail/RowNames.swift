import Foundation

/// Whom a row in the message list names on its top line: whom the letter is
/// from, except in Sent Mail, Drafts and the Outbox, where it names whom the
/// letter is to (B-060), as Mail on the iPad names them (B-075).
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

    /// What the top line says of a letter with nobody in its To: a draft
    /// begun and put aside, or a letter sent to Cc or Bcc alone. The words
    /// the Outbox's rows have used since B-052. Mail's own string table for
    /// its rows holds "No Recipient", one; these stayed (B-075).
    static let noRecipients = "No Recipients"

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

    /// The top line of a row that names whom its letter is to, from the
    /// entries of its To alone, as Mail on the iPad builds it (B-075):
    ///
    /// - Nobody in To: "No Recipients". Not the Cc, not the Bcc, so a
    ///   letter sent to Bcc alone says so too.
    /// - One: the name whole, "Jane Example", or the address where the
    ///   letter gives no name. A name that is only the address again is
    ///   no name.
    /// - Two or more: his own addresses taken out, but never the first
    ///   entry. Then each person once: an address met before is left
    ///   out, and so is a name met before, as one person written at two
    ///   addresses. If one is left, it is named whole. Otherwise each is
    ///   cut to a short name (`shortName`), joined "Jane & Sam", "Jane,
    ///   Sam & Bob".
    ///
    /// A name that is itself an address, other than the one it names, is
    /// shown with the real one after it, "jane@example.com
    /// <other@example.net>", whole or short, so it cannot pass for it.
    ///
    /// Nothing is ever said of how many are left out: the line is cut at
    /// its end, as every row's is, and Mail's rows have no "& 2 more".
    static func line(to entries: [String], mine: OwnAddresses) -> String {
        let people = entries.compactMap(person(in:))
        guard let first = people.first else { return noRecipients }
        guard people.count > 1 else { return fullName(first) }

        var seenAddresses = Set<String>()
        var seenNames = Set<String>()
        var kept: [MailFormat.Recipient] = []
        for (i, p) in people.enumerated() {
            if i > 0, mine.contains(p.address) { continue }
            guard seenAddresses.insert(p.address.lowercased()).inserted else { continue }
            if let name = p.name, !seenNames.insert(name).inserted { continue }
            kept.append(p)
        }
        guard kept.count > 1 else { return fullName(kept[0]) }
        return joined(kept.map(shortName))
    }

    /// One entry of a To as the row reads it: the name and address of
    /// `MailFormat.recipient(in:)`, or, for an entry it finds no address
    /// in, the entry as written, so a draft's half-typed "jan" is named as
    /// he left it. Nil for a blank entry, and for an entry that ends in ";"
    /// with no address in it, such as the empty group
    /// `undisclosed-recipients:;`, which names nobody.
    ///
    /// An entry that ends in ";" and holds an address is that person:
    /// "jane@example.com;", an address typed with a semicolon after it,
    /// and the last of a group's people. The composer splits a field at
    /// commas alone, so a draft or a letter in the Outbox keeps the
    /// semicolon in the entry.
    static func person(in entry: String) -> MailFormat.Recipient? {
        let entry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty else { return nil }
        if let p = MailFormat.recipient(in: entry) { return p }
        guard !entry.hasSuffix(";") else { return nil }
        return MailFormat.Recipient(name: nil, address: MailFormat.oneLine(entry))
    }

    /// A recipient named whole: the name, or the address where there is
    /// none.
    static func fullName(_ p: MailFormat.Recipient) -> String {
        guard let name = p.name else { return p.address }
        return name.contains("@") ? "\(name) <\(p.address)>" : name
    }

    /// A recipient named short, as Mail names each of two or more: the
    /// first word of the name, "Jane" for "Jane Example", or the word after
    /// the comma of a name written surname first, "Jane" for "Example,
    /// Jane"; the address before its "@" where there is no name, "sam" for
    /// sam@example.com.
    ///
    /// Mail takes each person's short name from Contacts, and builds one
    /// from the letter's name for a person not in them. How it does that
    /// was not read; this is the rule that gives "Jane" for the people a
    /// letter names, and is inferred.
    static func shortName(_ p: MailFormat.Recipient) -> String {
        guard let name = p.name else {
            guard let at = p.address.firstIndex(of: "@"), at > p.address.startIndex else {
                return p.address
            }
            return String(p.address[..<at])
        }
        if name.contains("@") { return fullName(p) }
        var given = Substring(name)
        if let comma = name.firstIndex(of: ","),
           name[..<comma].split(separator: " ").count == 1 {
            let after = name[name.index(after: comma)...]
            if !after.trimmingCharacters(in: .whitespaces).isEmpty { given = after }
        }
        return given.split(whereSeparator: { $0 == " " || $0 == "," }).first.map(String.init) ?? name
    }

    /// Names joined as Mail joins a list: "Jane", "Jane & Sam", "Jane, Sam
    /// & Bob".
    static func joined(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " & " + last
    }
}
