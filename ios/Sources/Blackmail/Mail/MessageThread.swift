import Foundation

/// One conversation: the messages of a back-and-forth, shown as a single
/// row the way Mail shows them.
///
/// Mail has grouped by thread, by default, since long before the iPad this
/// build is modelled on. Without it a correspondence of eight replies is
/// eight rows all called "Re: the roof", and for someone who answers his
/// mail — which is most of what this reader does — the list fills with
/// near-identical lines and the newest one is not obviously the newest.
struct MessageThread {

    /// Newest first, like every list in this app: in a folder's list, by
    /// when the server took each letter (`group`, B-084).
    let messages: [MessageSummary]

    /// Stable across regroupings, so a row does not change identity when a
    /// page is appended. It is the id of the letter the list has FIRST in
    /// the conversation, the last the folder took, rather than the thread
    /// key, because the thread key is absent on a server without Gmail's
    /// extension.
    ///
    /// Not the newest's (`newest`) since B-084. The newest is now the last
    /// to come, which a page further down can change: a reply deleted
    /// before the letter it answers is lower in Trash than that letter.
    /// A page appended below brings letters the folder took earlier, never
    /// one it took later, so the letter listed first stays first. The two
    /// are the same letter but for a conversation put in its folder out of
    /// turn.
    let id: String

    /// A conversation of `messages`, in the order given, newest first, and
    /// known by the first of them. `group` gives the id of the letter
    /// listed first when it puts the letters in the order they came.
    init(messages: [MessageSummary], id: String? = nil) {
        self.messages = messages
        self.id = id ?? messages.first?.id ?? ""
    }

    var newest: MessageSummary { messages[0] }
    var count: Int { messages.count }

    /// A thread is unread if ANY message in it is, which is what the blue
    /// dot has to mean: the alternative is a conversation with an unread
    /// reply in it looking answered.
    var isRead: Bool { messages.allSatisfy(\.isRead) }
    var isFlagged: Bool { messages.contains(where: \.isFlagged) }
    var hasAttachment: Bool { messages.contains(where: \.hasAttachment) }

    /// What the row says. The newest message's subject, because a thread's
    /// subject can drift ("Re: the roof" → "Re: the roof and the gutter")
    /// and the latest wording is the one he was last reading.
    var subject: String { newest.subject }
    var date: Date { newest.date }
    var preview: String { newest.preview }

    /// Who is in the conversation, newest speaker first, each named once.
    ///
    /// Mail shows the participants rather than only the last sender,
    /// because "Margaret, Carlo" tells him it is a back-and-forth and one
    /// name does not.
    var participants: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for m in messages {
            let name = MailFormat.displayName(m.sender)
            if seen.insert(name).inserted { out.append(name) }
        }
        return out
    }

    /// The row's top line without its count: its senders (`participants`)
    /// joined, or, `namingRecipients`, whom its letters are to, as a row
    /// names them in Sent Mail, Drafts and the Outbox (`RowNames.line`):
    /// the To of every letter in it, the newest letter's first, named as
    /// Mail names a letter's To. His own addresses are known by `mine`.
    ///
    /// A conversation in Sent Mail of a letter to Jane and a later one to
    /// Sam names "Sam & Jane": everyone he wrote to in it, as the senders'
    /// names tell him who wrote in the Inbox (B-060). A letter whose row
    /// does not know whom it is to, kept by a build before rows carried it,
    /// adds nobody; when none of them knows, the row names their senders,
    /// as it always did, until the folder is next listed.
    func nameLine(namingRecipients: Bool, mine: OwnAddresses) -> String {
        guard namingRecipients, messages.contains(where: { $0.to != nil }) else {
            return participants.joined(separator: ", ")
        }
        return RowNames.line(to: messages.flatMap { $0.to ?? [] }, mine: mine)
    }

    /// Whether this row, in the list of `list`, names whom its letters are
    /// to: by the folder its letters were listed from, which is the same
    /// for all of them (`RowNames.namesRecipients`).
    func namesRecipients(in list: Mailbox) -> Bool {
        RowNames.namesRecipients(listedFrom: newest.mailboxID, in: list)
    }

    /// Whether the row, in the list of `list`, ends its top line with the
    /// mark of a conversation, the blue circled chevron after the date: a
    /// row of more than one letter, in every folder, as Mail marks one
    /// everywhere. Sent Mail, Drafts and the Outbox since B-075, every
    /// other folder since B-080. No row has a count after its names. The
    /// mark sits apart from the names, so however many there are it is
    /// never cut off with them.
    ///
    /// Only a list that gathers its letters into conversations has rows of
    /// more than one: a folder, with Organize by Thread on. A search's rows
    /// are one letter each (`rows(for:grouped:)`), so none is marked.
    func marksConversation(in list: Mailbox) -> Bool {
        count > 1
    }

    /// The row the list of `list` draws: in Sent Mail, Drafts and the
    /// Outbox naming whom the letters are to, everywhere else who they are
    /// from, never with a count. What the list's controller draws every
    /// row with, beside `marksConversation(in:)`.
    func displayRow(in list: Mailbox, mine: OwnAddresses) -> MessageSummary {
        displayRow(namingRecipients: namesRecipients(in: list), mine: mine)
    }

    /// What VoiceOver reads for the row in the list of `list`: "On this
    /// iPad only" for a draft kept on the iPad, "Unread", the names as the
    /// top line has them, how many letters when more than one, the subject
    /// and the time as the row shows it. The count, which the row no
    /// longer shows, is read as "3 messages" where the row marks the
    /// conversation after its date, in every folder (B-075, B-080). No
    /// "To" is read before the names where the row names whom the letters
    /// are to, as none is shown: the folder says so, as it does on the
    /// screen.
    ///
    /// Out of the controller, which used to put it together itself, so the
    /// names it reads are the names the row shows, and tested.
    func accessibilityLabel(in list: Mailbox, mine: OwnAddresses, now: Date = Date()) -> String {
        [
            list.role == .drafts && LocalDraft.key(ofRow: id) != nil ? LocalDraft.mark : nil,
            isRead ? nil : "Unread",
            nameLine(namingRecipients: namesRecipients(in: list), mine: mine),
            count > 1 ? "\(count) messages" : nil,
            subject,
            MailFormat.listTimestamp(date, now: now),
        ].compactMap { $0 }.joined(separator: ", ")
    }

    /// The conversation as the single row the list draws.
    ///
    /// Out here rather than in the view controller so it can be TESTED —
    /// the controller is behind `#if canImport(UIKit)` and does not exist
    /// on the machine the suite runs on, the same reason `PageWindow` and
    /// `SearchCriteria` were pulled out.
    ///
    /// Deliberately reuses `MessageSummary` and therefore the row that
    /// draws a single letter. A second cell type would mean two copies of
    /// a geometry measured against the reference to the half point, and
    /// two places to keep it true. Its `sender` is the top line, whoever
    /// that names (`nameLine(namingRecipients:mine:)`); the letters' own
    /// senders are left alone, so nothing that goes by them, matching a
    /// letter's twin in another mailbox (`ListEdit.twins`) or the reading
    /// pane's From, changes with the folder.
    func displayRow(namingRecipients: Bool = false,
                    mine: OwnAddresses = OwnAddresses([])) -> MessageSummary {
        // The names alone, "Carlo, Margaret", with no count after them.
        // The count used to ride on this line, "Carlo, Margaret (3)", and
        // went off its end with a long list of who wrote. Mail has none on
        // any row: the cell marks a conversation after its date instead
        // (`marksConversation(in:)`), in every folder (B-075, B-080), and
        // VoiceOver says how many (`accessibilityLabel(in:mine:now:)`).
        let sender = nameLine(namingRecipients: namingRecipients, mine: mine)
        return MessageSummary(
            id: id,
            mailboxID: newest.mailboxID,
            sender: sender,
            subject: subject,
            preview: preview,
            date: date,
            isRead: isRead,
            isFlagged: isFlagged,
            hasAttachment: hasAttachment,
            threadID: newest.threadID,
            countedFolderIDs: newest.countedFolderIDs)
    }

    // MARK: - Grouping

    /// Groups a flat, newest-first list into conversations, preserving the
    /// order the list was already in.
    ///
    /// Order is preserved deliberately: a thread takes the position of the
    /// letter the list has first in it, which is where he last saw that
    /// conversation. Any re-sort would move rows under a reader's thumb,
    /// and the flat list this replaces was already in the order the server
    /// gave.
    ///
    /// Inside a conversation the letters go in the order the server took
    /// them (`byArrival`, B-084), so the row and the stack stand for the
    /// newest whichever order they were put in the folder. The row keeps
    /// the id of the letter listed first (`id`).
    static func group(_ messages: [MessageSummary]) -> [MessageThread] {
        var order: [String] = []
        var buckets: [String: [MessageSummary]] = [:]

        for message in messages {
            let key = key(for: message)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(message)
        }
        return order.compactMap { key in
            guard let listed = buckets[key], let first = listed.first else { return nil }
            return MessageThread(messages: byArrival(listed), id: first.id)
        }
    }

    /// A conversation's letters, `listed` in the list's order, put in the
    /// order the server took them: by INTERNALDATE (`arrived`), the newest
    /// first, and by UID where two came in the same second, the higher
    /// first (B-084).
    ///
    /// The list's order is the folder's, by UID: the order the letters were
    /// put in it. For letters moved in, that is the order they were moved.
    /// Edit mode's Delete used to move a conversation the newest letter
    /// first, so in Trash the newest had the lowest UID, and the row named
    /// the oldest letter, its time, its subject and its sender first, and
    /// the stack ran upside down. Gmail keeps INTERNALDATE through a MOVE.
    ///
    /// Not by the letter's Date (`date`), which its sender's clock wrote: a
    /// letter dated wrong keeps the place its arrival gives it (B-074).
    ///
    /// As listed when any letter's arrival is not known, a row kept by a
    /// build before rows carried it (`MailShelf`), or a letter kept on the
    /// iPad: then the folder's order, as before. The UID breaks a tie only
    /// when every letter is from one folder under one UIDVALIDITY, as a
    /// folder's list is; otherwise the list's order does.
    static func byArrival(_ listed: [MessageSummary]) -> [MessageSummary] {
        let arrivals = listed.compactMap(\.arrived)
        guard listed.count > 1, arrivals.count == listed.count else { return listed }
        let uids = listed.compactMap { uid(of: $0, as: listed[0]) }
        // The higher, the later: the UID, or failing that the list's order
        // turned over.
        let later: [Int64] = uids.count == listed.count
            ? uids.map(Int64.init)
            : listed.indices.map { -Int64($0) }
        return listed.indices.sorted { a, b in
            arrivals[a] != arrivals[b] ? arrivals[a] > arrivals[b] : later[a] > later[b]
        }.map { listed[$0] }
    }

    /// The UID of `letter`, from its id, `"<uidvalidity>/<uid>"`, when it is
    /// listed from the folder `like` is, under the same UIDVALIDITY.
    private static func uid(of letter: MessageSummary, as like: MessageSummary) -> UInt32? {
        let parts = letter.id.split(separator: "/", omittingEmptySubsequences: false)
        let theirs = like.id.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, theirs.count == 2, parts[0] == theirs[0],
              letter.mailboxID == like.mailboxID else { return nil }
        return UInt32(parts[1])
    }

    /// The rows a list should show — grouped when browsing a folder, NOT
    /// grouped when showing search results.
    ///
    /// Search is the exception and it is not a small one. A conversation
    /// row stands for its NEWEST letter: that is the sender it names, the
    /// subject it prints and the preview it shows. Group the results of a
    /// search and a hit that is not the newest in its thread is displayed
    /// as a completely different message — he searches for a phrase and
    /// gets back a row that does not contain it, with somebody else's
    /// subject on it. The letter he asked for is one tap inside, which is
    /// no help at all when the row gives him no reason to tap.
    ///
    /// It is not rare either: across 600 of his own messages in All Mail,
    /// 26.5% are not the newest in their thread, so roughly a quarter of
    /// any result set would be misrepresented this way. And search is the
    /// thing he does all the time.
    ///
    /// Each result becomes a conversation of one, so the row draws exactly
    /// as a single letter does — no mark, no participants list — and
    /// everything downstream keeps working on one type.
    static func rows(for messages: [MessageSummary], grouped: Bool) -> [MessageThread] {
        grouped ? group(messages) : messages.map { MessageThread(messages: [$0]) }
    }

    /// What makes two messages the same conversation.
    ///
    /// Gmail's own thread id when the server gave one, because it is the
    /// answer that agrees with what he sees in Gmail everywhere else, and
    /// because every alternative is a guess. Falling back to the subject is
    /// that guess, and it is confined to servers with no extension.
    ///
    /// The fallback is the subject ALONE, and deliberately so even though
    /// that can collide: two unrelated letters both called "Hello" would
    /// be grouped.
    ///
    /// Folding the sender in to prevent that is the obvious next thought
    /// and it is wrong. A conversation is precisely the case where the
    /// sender CHANGES — Carlo at one domain and Margaret at another,
    /// answering each other about the roof — so keying on the sender
    /// would split every real thread in half to avoid an occasional
    /// spurious merge. Splitting a live correspondence is much the worse
    /// failure, and Gmail never reaches this path anyway.
    static func key(for message: MessageSummary) -> String {
        if let threadID = message.threadID, !threadID.isEmpty {
            return "t:" + threadID
        }
        let subject = normalisedSubject(message.subject)
        // A message with no subject at all threads with nothing — grouping
        // every blank-subject letter into one conversation would hide
        // them behind each other.
        guard !subject.isEmpty else { return "u:" + message.id }
        return "s:" + subject
    }

    /// Strips the reply and forward prefixes a subject accumulates.
    ///
    /// Handles the pile-up — "Re: Fwd: Re: the roof" — and the localised
    /// forms that arrive from correspondents on other clients, because a
    /// thread broken in half by one "AW:" is a conversation he has to read
    /// in two places.
    static func normalisedSubject(_ subject: String) -> String {
        var text = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["re:", "re :", "fwd:", "fw:", "aw:", "wg:", "sv:",
                        "vs:", "rif:", "res:", "enc:", "tr:"]
        var stripped = true
        while stripped {
            stripped = false
            let lower = text.lowercased()
            for prefix in prefixes where lower.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                stripped = true
                break
            }
        }
        return text.lowercased()
    }
}
