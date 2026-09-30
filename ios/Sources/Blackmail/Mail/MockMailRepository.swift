import Foundation

/// Deterministic fixtures for the Phase 1 prototype.
///
/// Deliberately not cheerful sample data. `BRIEF.md`'s quality bar names the
/// cases that break mail clients, so the fixtures include them: an empty
/// folder, a subject long enough to truncate, an HTML-only body, a message with
/// an attachment, and a spread of dates that exercises every branch of the
/// timestamp formatter. If the prototype looks right against this, it is
/// because it handles the awkward cases, not because the data was flattering.
final class MockMailRepository: MailRepository {

    private let mailboxes: [Mailbox] = [
        Mailbox(id: "inbox",   name: "Inbox",   unreadCount: 9, role: .inbox),
        Mailbox(id: "drafts",  name: "Drafts",  unreadCount: 0, role: .drafts),
        Mailbox(id: "sent",    name: "Sent",    unreadCount: 0, role: .sent),
        Mailbox(id: "junk",    name: "Junk",    unreadCount: 0, role: .junk),
        Mailbox(id: "trash",   name: "Trash",   unreadCount: 0, role: .trash),
        Mailbox(id: "archive", name: "Archive", unreadCount: 0, role: .archive),
        // A custom folder, and an empty one. The empty one is the point.
        Mailbox(id: "family",  name: "Family",  unreadCount: 2, role: nil),
        Mailbox(id: "bank",    name: "Bank",    unreadCount: 0, role: nil),
    ]

    private var messages: [String: [MessageSummary]] = [:]
    private var bodies: [String: Message] = [:]

    init() { buildFixtures() }

    // MARK: - MailRepository

    func listMailboxes() async throws -> [Mailbox] { mailboxes }

    func folders() async throws -> [Mailbox] {
        mailboxes.map { var m = $0; m.unreadCount = 0; return m }
    }

    func listMessages(in mailboxID: String, beforeUID: String?, limit: Int) async throws -> [MessageSummary] {
        let all = messages[mailboxID] ?? []
        guard let beforeUID, let idx = all.firstIndex(where: { $0.id == beforeUID }) else {
            return Array(all.prefix(limit))
        }
        return Array(all[(idx + 1)...].prefix(limit))
    }

    func listMessages(in mailboxID: String, afterUID: String,
                      limit: Int) async throws -> [MessageSummary] {
        let all = messages[mailboxID] ?? []
        guard let idx = all.firstIndex(where: { $0.id == afterUID }) else { return [] }
        // The rows immediately ABOVE the cursor, newest first — a suffix of
        // what is newer, not a prefix of the mailbox.
        return Array(all[..<idx].suffix(limit))
    }

    func messages(around date: Date, in mailboxID: String,
                  limit: Int) async throws -> MessageWindow? {
        let all = messages[mailboxID] ?? []
        // Newest first, so the FIRST letter on or after the date is the LAST
        // matching row.
        guard let idx = all.lastIndex(where: { $0.date >= date }) else { return nil }
        let takeNewer = min(PageWindow.newerRowsAboveAnchor, idx)
        let start = idx - takeNewer
        let end = min(all.count, start + limit)
        return MessageWindow(messages: Array(all[start..<end]),
                             anchorIndex: takeNewer,
                             reachedNewest: start == 0,
                             reachedOldest: end == all.count,
                             landedOn: all[idx].date)
    }

    /// The fixtures carry their preview text already, so this just hands it
    /// back — the second pass exists for the cost of a real BODY fetch, and
    /// there is no such cost here.
    func previews(for ids: [String], in mailboxID: String) async throws -> [String: String] {
        let wanted = Set(ids)
        var out: [String: String] = [:]
        for m in messages[mailboxID] ?? [] where wanted.contains(m.id) && !m.preview.isEmpty {
            out[m.id] = m.preview
        }
        return out
    }

    func loadMessage(id: String, mailboxID: String) async throws -> Message {
        if let m = bodies[id] { return m }
        let s = (messages[mailboxID] ?? []).first { $0.id == id }
        return Message(id: id, mailboxID: mailboxID,
                       sender: s?.sender ?? "Unknown",
                       senderAddress: "someone@example.com",
                       to: ["me@example.com"], cc: [],
                       subject: s?.subject ?? "",
                       date: s?.date ?? Date(),
                       textBody: s?.preview ?? "", htmlBody: nil, attachments: [])
    }

    func setRead(_ read: Bool, id: String, mailboxID: String) async throws {
        guard var list = messages[mailboxID], let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].isRead = read
        messages[mailboxID] = list
    }

    func setFlagged(_ flagged: Bool, id: String, mailboxID: String) async throws {
        guard var list = messages[mailboxID], let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].isFlagged = flagged
        messages[mailboxID] = list
    }

    func move(_ id: String, from source: String, to destination: String) async throws {
        guard var from = messages[source], let i = from.firstIndex(where: { $0.id == id }) else { return }
        let m = from.remove(at: i)
        messages[source] = from
        messages[destination, default: []].insert(m, at: 0)
    }

    func delete(_ id: String, from mailboxID: String) async throws {
        try await move(id, from: mailboxID, to: "trash")
    }

    func send(_ draft: Draft, progress: UploadProgress?) async throws {}

    /// Keyed by the id handed back, so the fixture replaces rather than
    /// accumulates, like the real one.
    private(set) var savedDrafts: [String: Draft] = [:]
    private var nextDraftUID = 1

    @discardableResult
    func saveDraft(_ draft: Draft) async throws -> String? {
        if let old = draft.savedID { savedDrafts[old] = nil }
        let id = "1/\(nextDraftUID)"
        nextDraftUID += 1
        var stored = draft
        stored.savedID = id
        savedDrafts[id] = stored
        return id
    }

    /// Nothing is ever cut off here, so an earlier version is never found.
    @discardableResult
    func saveDraft(_ draft: Draft, as upload: DraftUpload) async throws -> DraftSaved {
        let replaced = draft.savedID.map { [$0] } ?? []
        try await upload.appending()
        return DraftSaved(id: try await saveDraft(draft), replaced: replaced)
    }

    func deleteDraft(_ id: String) async throws { savedDrafts[id] = nil }

    /// Nothing is ever cut off here, so there is never such a copy.
    @discardableResult
    func deleteDrafts(uploadedAs versions: [String]) async throws -> [String] { [] }

    func loadDraft(id: String, mailboxID: String) async throws -> Draft {
        guard let draft = savedDrafts[id] else { throw MailError.cannotConnect }
        return draft
    }

    func search(in mailboxID: String, query: String, scope: MailSearchScope,
                beforeUID: String?, limit: Int) async throws -> [MessageSummary] {
        let q = query.lowercased()
        guard !q.isEmpty else {
            return try await listMessages(in: mailboxID, beforeUID: beforeUID, limit: limit)
        }
        // `.allMailboxes` looks in every fixture folder; the real one leans
        // on Gmail's All Mail for the same answer in one round trip.
        let pool: [MessageSummary]
        switch scope {
        case .currentMailbox:
            pool = messages[mailboxID] ?? []
        case .allMailboxes:
            pool = messages.values.flatMap { $0 }.sorted { $0.date > $1.date }
        }
        let hits = pool.filter {
            $0.sender.lowercased().contains(q)
                || $0.subject.lowercased().contains(q)
                || $0.preview.lowercased().contains(q)
        }
        guard let beforeUID, let idx = hits.firstIndex(where: { $0.id == beforeUID }) else {
            return Array(hits.prefix(limit))
        }
        return Array(hits[(idx + 1)...].prefix(limit))
    }

    func fetchAttachmentData(_ attachmentID: String, of messageID: String, mailboxID: String) async throws -> Data {
        Data("mock attachment".utf8)
    }

    /// No connection to keep alive.
    func warmUp() async {}

    /// Always there.
    var isConnected: Bool { get async { true } }

    /// Nothing ever arrives in fixtures.
    func news(in mailboxID: String, known: [String],
              searchingAnyway: Bool) async throws -> FolderNews { FolderNews() }

    func inboxUnread() async throws -> Int? {
        mailboxes.first { $0.role == .inbox }?.unreadCount
    }

    // MARK: - Fixtures

    private func buildFixtures() {
        let now = Date()
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

        // Explicitly typed. Left to inference, the tuple array plus index
        // arithmetic plus string interpolation below blows the type-checker's
        // budget and the build fails with "unable to type-check in reasonable
        // time" - which points at the map, not at the real cause.
        let people: [(name: String, address: String)] = [
            ("Margaret Hale", "margaret@example.com"),
            ("Dr. Aziz", "surgery@example.com"),
            ("Thornton & Sons", "accounts@example.com"),
            ("David Hale", "david@example.com"),
            ("Bessy Higgins", "bessy@example.com"),
            ("The Library", "notices@example.com"),
        ]
        let subjects = [
            "Lunch on Thursday",
            "Your appointment on the 24th",
            "Statement for September",
            "Photos from the garden",
            "Re: the boiler man",
            "Your books are due back",
            "A rather long subject line that will certainly need to wrap onto a second line in the message list",
        ]
        let previews = [
            "I thought we might try the new place on the corner, they do a very good soup and it is not too far to walk.",
            "This is a reminder that you have an appointment with the practice nurse. Please bring your repeat prescription list.",
            "Your statement is ready to view. There is nothing that needs your attention this month.",
            "I took these on Sunday when the light was good. The roses have come back better than last year.",
            "He says he can come Tuesday morning, any time after nine. Shall I tell him yes?",
            "The following items are due for return. You can renew them by replying to this message.",
        ]

        var inbox: [MessageSummary] = []
        for i in 0..<30 {
            let name: String = people[i % people.count].name
            inbox.append(MessageSummary(
                id: "inbox-\(i)",
                mailboxID: "inbox",
                sender: name,
                subject: i == 4 ? subjects[6] : subjects[i % 6],
                preview: previews[i % previews.count],
                // First few today, then yesterday, then this week, then older —
                // so every branch of the timestamp formatter is on screen.
                date: ago(Double(i) * 7.5),
                isRead: i >= 9,                    // 9 unread
                isFlagged: i == 2 || i == 11,
                hasAttachment: i == 3 || i == 17
            ))
        }
        messages["inbox"] = inbox

        var family: [MessageSummary] = []
        for i in 0..<4 {
            let name: String = people[(i + 3) % people.count].name
            let when: Date = ago(Double(i) * 40 + 30)
            family.append(MessageSummary(id: "family-\(i)", mailboxID: "family",
                                         sender: name,
                                         subject: subjects[(i + 2) % 6],
                                         preview: previews[(i + 1) % previews.count],
                                         date: when,
                                         isRead: i >= 2, isFlagged: false))
        }
        messages["family"] = family

        var sent: [MessageSummary] = []
        for i in 0..<6 {
            let name: String = people[i % people.count].name
            let when: Date = ago(Double(i) * 26 + 5)
            sent.append(MessageSummary(id: "sent-\(i)", mailboxID: "sent",
                                       sender: "To: " + name,
                                       subject: subjects[(i + 1) % 6],
                                       preview: "Thank you, that suits me very well.",
                                       date: when,
                                       isRead: true, isFlagged: false))
        }
        messages["sent"] = sent

        var archive: [MessageSummary] = []
        for i in 0..<12 {
            let name: String = people[(i + 1) % people.count].name
            let when: Date = ago(Double(i) * 200 + 400)
            archive.append(MessageSummary(id: "archive-\(i)", mailboxID: "archive",
                                          sender: name,
                                          subject: subjects[i % 6],
                                          preview: previews[(i + 2) % previews.count],
                                          date: when,
                                          isRead: true, isFlagged: false))
        }
        messages["archive"] = archive
        // Deliberately empty. `BRIEF.md`'s quality bar names empty folders, and
        // an empty table with no explanation is how apps look broken.
        messages["drafts"] = []
        messages["junk"] = []
        messages["trash"] = []
        messages["bank"] = []

        // A plain-text body, an HTML-only body, and one with an attachment.
        bodies["inbox-0"] = Message(
            id: "inbox-0", mailboxID: "inbox",
            sender: "Margaret Hale", senderAddress: "margaret@example.com",
            to: ["me@example.com"], cc: [],
            subject: subjects[0], date: ago(0),
            textBody: """
            I thought we might try the new place on the corner, they do a very \
            good soup and it is not too far to walk.

            Thursday at one, if that suits. Let me know either way and I will \
            telephone them.

            Margaret
            """,
            htmlBody: nil, attachments: [])

        bodies["inbox-1"] = Message(
            id: "inbox-1", mailboxID: "inbox",
            sender: "Dr. Aziz", senderAddress: "surgery@example.com",
            to: ["me@example.com"], cc: [],
            subject: subjects[1], date: ago(7.5),
            textBody: nil,
            htmlBody: """
            <html><body style="font: -apple-system-body; padding: 0">
            <h2>Appointment reminder</h2>
            <p>This is a reminder that you have an appointment with the practice
            nurse on <b>the 24th at 10:15</b>.</p>
            <p>Please bring your repeat prescription list.</p>
            <table border="1" cellpadding="6"><tr><th>Date</th><th>Time</th><th>With</th></tr>
            <tr><td>24 September</td><td>10:15</td><td>Practice nurse</td></tr></table>
            <p><a href="https://example.com/cancel">Cancel this appointment</a></p>
            </body></html>
            """,
            attachments: [])

        bodies["inbox-3"] = Message(
            id: "inbox-3", mailboxID: "inbox",
            sender: "David Hale", senderAddress: "david@example.com",
            to: ["me@example.com"], cc: ["margaret@example.com"],
            subject: subjects[3], date: ago(22.5),
            textBody: "I took these on Sunday when the light was good.\n\nDavid",
            htmlBody: nil,
            attachments: [Attachment(id: "a1", filename: "garden.jpg",
                                     mimeType: "image/jpeg", size: 2_411_233)])
    }
}
