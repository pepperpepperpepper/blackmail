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

    /// Newest first, like every list in this app.
    let messages: [MessageSummary]

    /// Stable across regroupings, so a row does not change identity when a
    /// page is appended. It is the id of the NEWEST message rather than the
    /// thread key, because the thread key is absent on a server without
    /// Gmail's extension.
    var id: String { newest.id }

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
    /// mark of a conversation, the blue circled chevron after the date, in
    /// place of the count after the names: a row of more than one letter
    /// that names whom they are to, in Sent Mail, Drafts and the Outbox, as
    /// Mail marks one there (B-075). The mark sits apart from the names,
    /// so however many there are it is never cut off with them. Every
    /// other list keeps its count, "(2)", on the names.
    func marksConversation(in list: Mailbox) -> Bool {
        count > 1 && namesRecipients(in: list)
    }

    /// The row the list of `list` draws: in Sent Mail, Drafts and the
    /// Outbox naming whom the letters are to, with no count, everywhere
    /// else who they are from, with it. What the list's controller draws
    /// every row with, beside `marksConversation(in:)`.
    func displayRow(in list: Mailbox, mine: OwnAddresses) -> MessageSummary {
        displayRow(namingRecipients: namesRecipients(in: list), mine: mine)
    }

    /// What VoiceOver reads for the row in the list of `list`: "On this
    /// iPad only" for a draft kept on the iPad, "Unread", the names as the
    /// top line has them, how many letters when more than one, the subject
    /// and the time as the row shows it. The count is read as "3 messages",
    /// whether the row shows it as "(3)" or marks the conversation after
    /// its date. No "To" is read before the names where the row names whom
    /// the letters are to, as none is shown: the folder says so, as it does
    /// on the screen.
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
        let who = nameLine(namingRecipients: namingRecipients, mine: mine)
        // The count rides on the sender line — "Margaret, Carlo (3)" —
        // rather than in a badge, which would need a new view in a layout
        // that is frozen. A row naming whom has none: the cell marks it
        // after the date (`marksConversation(in:)`), as Mail does.
        let sender = count > 1 && !namingRecipients ? "\(who) (\(count))" : who
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
    /// Order is preserved deliberately: a thread takes the position of its
    /// NEWEST message, which is where he last saw that conversation. Any
    /// re-sort would move rows under a reader's thumb, and the flat list
    /// this replaces was already in the order the server gave.
    static func group(_ messages: [MessageSummary]) -> [MessageThread] {
        var order: [String] = []
        var buckets: [String: [MessageSummary]] = [:]

        for message in messages {
            let key = key(for: message)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(message)
        }
        return order.map { MessageThread(messages: buckets[$0] ?? []) }
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
    /// as a single letter does — no count, no participants list — and
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
