import XCTest
@testable import Blackmail

/// The top line of a row in Sent Mail, Drafts and the Outbox names whom the
/// letter is to, as Mail's does, and not him (B-060). Every row there named
/// him: he sends some seventy letters a day and keeps nearly two thousand
/// drafts, and could tell them apart only by their subjects.
///
/// The names are the reading pane's (`MailFormat.recipientName`), To, Cc
/// and Bcc in that order, each person once, "No Recipients" for a draft to
/// nobody. Which folder a row was listed from decides it, so a letter of his
/// found in All Mail by an All Mailboxes search still names him, as it does
/// in All Mail. A row kept by a build before rows carried their To names its
/// sender, as every row did, until the folder is listed again.
final class SentRowNamesTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let sent = Mailbox(id: "[Gmail]/Sent Mail", name: "Sent Mail",
                                      unreadCount: 0, role: .sent, depth: 1)
    private static let drafts = Mailbox(id: "[Gmail]/Drafts", name: "Drafts",
                                        unreadCount: 0, role: .drafts, depth: 1)
    private static let inbox = Mailbox(id: "INBOX", name: "INBOX", unreadCount: 0, role: .inbox)
    private static let allMail = Mailbox(id: "[Gmail]/All Mail", name: "All Mail",
                                         unreadCount: 0, role: .archive, depth: 1)
    private static let trash = Mailbox(id: "[Gmail]/Trash", name: "Trash",
                                       unreadCount: 0, role: .trash, depth: 1)
    private static let family = Mailbox(id: "Family", name: "Family", unreadCount: 0)
    private static let outbox = Outbox.mailbox(holding: 1)

    private static let me = "Owner Example <owner@example.com>"
    private static let jane = "Jane Example <jane@example.com>"
    private static let sam = "Sam Example <sam@example.com>"
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// A letter of his, listed from `folder`.
    private func letter(_ id: String, in folder: Mailbox, to: [String]?, cc: [String] = [],
                        bcc: [String] = [], thread: String? = nil,
                        subject: String = "Lunch on Sunday", hoursAgo: Double = 0,
                        read: Bool = true) -> MessageSummary {
        MessageSummary(id: id, mailboxID: folder.id, sender: Self.me, subject: subject,
                       preview: "Shall we say one o'clock?",
                       date: Self.now.addingTimeInterval(-hoursAgo * 3_600),
                       isRead: read, isFlagged: false, threadID: thread ?? id,
                       to: to, cc: cc, bcc: bcc)
    }

    private func row(_ letters: [MessageSummary]) -> MessageThread {
        MessageThread(messages: letters)
    }

    // MARK: - The names

    /// To, then Cc, then Bcc, each as the reading pane names them: the name,
    /// or the address where there is none. A person named twice, once with
    /// a name and once without, or in To and again in Bcc, is named once,
    /// as the first naming has them; a blank entry names nobody.
    func testWhomALetterIsToIsNamedOnceEachAsThePaneNamesThem() {
        let letter = letter("1/9", in: Self.sent,
                            to: [Self.jane, "sam@example.com", "<lee@example.com>"],
                            cc: ["\"Example, Pat\" <pat@example.com>", "JANE@example.com"],
                            bcc: [Self.sam, " ", "carlo@example.org"])
        XCTAssertEqual(RowNames.recipients(of: letter)?.map(\.name),
                       ["Jane Example", "sam@example.com", "lee@example.com", "Example, Pat",
                        "carlo@example.org"])
        XCTAssertEqual(row([letter]).displayRow(in: Self.sent).sender,
                       "Jane Example, sam@example.com, lee@example.com, Example, Pat, carlo@example.org")
    }

    /// Sent Mail, Drafts and the Outbox name whom the letter is to; every
    /// other list names who it is from, his own letters included, as in All
    /// Mail, the Inbox (a letter he sent himself), Trash and a folder of his.
    func testSentDraftsAndTheOutboxNameWhomTheLetterIsToAndNoOtherListDoes() {
        for list in [Self.sent, Self.drafts, Self.outbox] {
            let shown = row([letter("1/9", in: list, to: [Self.jane])]).displayRow(in: list)
            XCTAssertEqual(shown.sender, "Jane Example", list.name)
        }
        for list in [Self.inbox, Self.allMail, Self.trash, Self.family] {
            let shown = row([letter("1/9", in: list, to: [Self.jane])]).displayRow(in: list)
            XCTAssertEqual(shown.sender, "Owner Example", list.name)
        }
    }

    /// A row the list of Sent Mail shows from another folder, an All
    /// Mailboxes search's hit from All Mail, names who it is from, as that
    /// letter is named in All Mail: among other people's letters, his name
    /// is what tells his own apart. A search of Sent Mail alone finds its
    /// rows in Sent Mail, and they name whom they are to.
    func testAHitFromAnotherFolderIsNamedByItsSender() {
        let hit = letter("2/90", in: Self.allMail, to: [Self.jane])
        XCTAssertEqual(row([hit]).displayRow(in: Self.sent).sender, "Owner Example")
        let own = letter("1/9", in: Self.sent, to: [Self.jane])
        XCTAssertEqual(MessageThread.rows(for: [own], grouped: false)[0]
                        .displayRow(in: Self.sent).sender, "Jane Example")
    }

    /// A draft begun and put aside, addressed to nobody: "No Recipients",
    /// with the count when a conversation's letters are all so, and the
    /// people a letter in it is to when one is. A letter to Bcc alone names
    /// the Bcc.
    func testALetterToNobodySaysNoRecipients() {
        let nobody = letter("1/9", in: Self.drafts, to: [])
        XCTAssertEqual(row([nobody]).displayRow(in: Self.drafts).sender, "No Recipients")
        XCTAssertEqual(row([nobody]).displayRow(in: Self.drafts).sender, RowNames.noRecipients)
        XCTAssertEqual(row([nobody, letter("1/8", in: Self.drafts, to: [], hoursAgo: 1)])
                        .displayRow(in: Self.drafts).sender, "No Recipients (2)")
        XCTAssertEqual(row([nobody, letter("1/8", in: Self.drafts, to: [Self.jane], hoursAgo: 1)])
                        .displayRow(in: Self.drafts).sender, "Jane Example (2)")
        XCTAssertEqual(row([letter("1/7", in: Self.drafts, to: [], bcc: ["lee@example.com"])])
                        .displayRow(in: Self.drafts).sender, "lee@example.com")
    }

    /// A conversation in Sent Mail names everyone he wrote to in it, the
    /// newest letter's first, each once, with the count, as the Inbox names
    /// everyone who wrote.
    func testAConversationInSentNamesEveryoneHeWroteTo() {
        let conversation = row([
            letter("1/9", in: Self.sent, to: [Self.sam], cc: [Self.jane], thread: "t"),
            letter("1/8", in: Self.sent, to: [Self.jane], thread: "t", hoursAgo: 2),
            letter("1/7", in: Self.sent, to: ["Carlo <carlo@example.org>"], thread: "t", hoursAgo: 4),
        ])
        XCTAssertEqual(conversation.displayRow(in: Self.sent).sender,
                       "Sam Example, Jane Example, Carlo (3)")
    }

    /// A row that does not know whom its letter is to, kept on the iPad by
    /// a build before rows carried it, names its sender as it did, not "No
    /// Recipients"; one beside it that knows names its recipients.
    func testARowThatDoesNotKnowWhomItIsToNamesItsSender() {
        let kept = letter("1/8", in: Self.sent, to: nil, thread: "t", hoursAgo: 2)
        XCTAssertEqual(row([kept]).displayRow(in: Self.sent).sender, "Owner Example")
        XCTAssertEqual(row([letter("1/9", in: Self.sent, to: [Self.jane], thread: "t"), kept])
                        .displayRow(in: Self.sent).sender, "Jane Example, Owner Example (2)")
    }

    /// The name is all that changes: the row's letter, subject, preview,
    /// date, marks and conversation are the ones the sender's row has, the
    /// letters' own senders are left as they came, and the rows stay in the
    /// folder's order, newest first, nothing sorting or grouping by name.
    func testNamingWhomTheLetterIsToChangesTheNameAlone() {
        var letters = [
            letter("1/9", in: Self.sent, to: ["zoe@example.com"], thread: "a", read: false),
            letter("1/8", in: Self.sent, to: [Self.jane], thread: "b", hoursAgo: 1),
            letter("1/7", in: Self.sent, to: ["anna@example.com"], thread: "a", hoursAgo: 2),
        ]
        letters[1].isFlagged = true
        letters[1].hasAttachment = true
        let rows = MessageThread.rows(for: letters, grouped: true)
        XCTAssertEqual(rows.map(\.id), ["1/9", "1/8"])
        for thread in rows {
            let named = thread.displayRow(in: Self.sent)
            let plain = thread.displayRow()
            XCTAssertNotEqual(named.sender, plain.sender)
            XCTAssertEqual([named.id, named.mailboxID, named.subject, named.preview,
                            named.threadID ?? ""],
                           [plain.id, plain.mailboxID, plain.subject, plain.preview,
                            plain.threadID ?? ""])
            XCTAssertEqual([named.isRead, named.isFlagged, named.hasAttachment],
                           [plain.isRead, plain.isFlagged, plain.hasAttachment])
            XCTAssertEqual(named.date, plain.date)
        }
        XCTAssertEqual(rows[0].displayRow(in: Self.sent).sender, "zoe@example.com, anna@example.com (2)")
        XCTAssertEqual(rows.flatMap(\.messages).map(\.sender), Array(repeating: Self.me, count: 3))
    }

    // MARK: - VoiceOver

    /// VoiceOver reads the names the row shows, without the count, which it
    /// reads in words, then the subject and the time: whom the letters are
    /// to in Sent Mail, "No Recipients" and the mark of a draft kept on the
    /// iPad in Drafts, and who wrote everywhere else.
    func testVoiceOverReadsTheNamesTheRowShows() {
        let stamp = MailFormat.listTimestamp(Self.now, now: Self.now)
        let conversation = row([
            letter("1/9", in: Self.sent, to: [Self.sam], cc: [Self.jane], thread: "t", read: false),
            letter("1/8", in: Self.sent, to: [Self.jane], thread: "t", hoursAgo: 2),
        ])
        XCTAssertEqual(conversation.accessibilityLabel(in: Self.sent, now: Self.now),
                       "Unread, Sam Example, Jane Example, 2 messages, Lunch on Sunday, \(stamp)")

        var unaddressed = Draft()
        unaddressed.subject = "Half a letter"
        let kept = LocalDraft(key: "letter-1", draft: unaddressed, version: "v", tried: [],
                              unfinished: false, keptAt: Self.now, account: "owner@example.com",
                              gone: false)
            .row(in: Self.drafts.id, from: "Owner Example")
        XCTAssertEqual(row([kept]).accessibilityLabel(in: Self.drafts, now: Self.now),
                       "On this iPad only, No Recipients, Half a letter, \(stamp)")

        var received = letter("1/9", in: Self.inbox, to: [Self.me])
        received.sender = Self.jane
        XCTAssertEqual(row([received]).accessibilityLabel(in: Self.inbox, now: Self.now),
                       "Jane Example, Lunch on Sunday, \(stamp)")
    }

    // MARK: - Letters on the iPad

    /// A draft kept on the iPad names whom it is to in Drafts, under "On
    /// this iPad only" and as the copy it became on the server, and "No
    /// Recipients" before he has addressed it; the Outbox's rows name them
    /// by the same rule, as they always did, each person once.
    func testLettersKeptOnTheIPadNameWhomTheyAreTo() {
        func kept(_ draft: Draft) -> LocalDraft {
            LocalDraft(key: "letter-1", draft: draft, version: "v", tried: [], unfinished: false,
                       keptAt: Self.now, account: "owner@example.com", gone: false)
        }
        var addressed = Draft(to: [Self.jane], cc: ["sam@example.com"], subject: "Lunch")
        addressed.bcc = ["jane@example.com", "Lee Example <lee@example.com>"]
        let local = kept(addressed).row(in: Self.drafts.id, from: "Owner Example")
        XCTAssertEqual(row([local]).displayRow(in: Self.drafts).sender,
                       "Jane Example, sam@example.com, Lee Example")
        let landed = kept(addressed).row(in: Self.drafts.id, from: "Owner Example",
                                         onServerAs: "1/10")
        XCTAssertEqual(row([landed]).displayRow(in: Self.drafts).sender,
                       "Jane Example, sam@example.com, Lee Example")
        XCTAssertEqual(row([kept(Draft()).row(in: Self.drafts.id, from: "Owner Example")])
                        .displayRow(in: Self.drafts).sender, "No Recipients")

        let waiting = kept(addressed).outboxRow(sending: false, saying: nil)
        XCTAssertEqual(row([waiting]).displayRow(in: Self.outbox).sender,
                       "Jane Example, sam@example.com, Lee Example")
        XCTAssertEqual(Outbox.addressees(of: addressed), "Jane Example, sam@example.com, Lee Example")
        XCTAssertEqual(Outbox.addressees(of: Draft()), "No Recipients")
    }

    // MARK: - The server's rows

    /// Over the shipping repository and client: Sent Mail's rows name whom
    /// each letter is to from the ENVELOPE the list fetches already, To, Cc
    /// and Bcc, and never him; Drafts' name a draft to nobody "No
    /// Recipients" and one saved with a Bcc alone by its Bcc; a search of
    /// Sent Mail names them too, and an All Mailboxes search from it names
    /// the same letter found in All Mail by its sender. The page kept on
    /// the iPad names them as the listing did, so the next launch draws
    /// them in its first frame. The list's FETCH is what it was.
    func testTheServersRowsNameWhomTheLettersAreTo() async throws {
        let server = ScriptedIMAPServer()
        defer { XCTAssertEqual(server.violations, []) }
        let suite = "SentRowNamesTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let shelf = keptShelf(for: server.account)
        let repository = IMAPMailRepository(account: server.account, password: server.password,
                                            transport: server.transportFactory,
                                            recipients: RecipientBook(defaults: defaults),
                                            shelf: shelf)
        let me = Server.Address(name: "Owner Example", address: "owner@example.com")
        server.deliver(Server.Letter(
            from: me, to: [Server.Address(name: "Jane Example", address: "jane@example.com"), Server.sam],
            cc: [Server.Address(name: "Pat Example", address: "pat@example.com")],
            bcc: [Server.Address(name: nil, address: "lee@example.com")],
            subject: "Lunch on Sunday", date: Server.newestDate, text: "One o'clock?\r\n",
            flags: ["\\Seen"], messageID: "<lunch@example.com>"), to: [Server.sent, Server.allMail])
        server.deliver(Server.Letter(
            from: me, to: [], subject: "Half a letter", date: Server.newestDate,
            text: "Dear\r\n", flags: ["\\Seen", "\\Draft"], messageID: "<half@example.com>"),
                       to: [Server.drafts, Server.allMail])
        var blind = Draft(subject: "For Lee alone", body: "Quietly.")
        blind.bcc = ["Lee Example <lee@example.com>"]
        _ = try await repository.saveDraft(blind)

        let folders = try await repository.listMailboxes()
        let sent = try XCTUnwrap(folders.first { $0.role == .sent })
        let drafts = try XCTUnwrap(folders.first { $0.role == .drafts })

        let sentRows = try await repository.listMessages(in: sent.id, beforeUID: nil, limit: 20)
        let sentNames = MessageThread.rows(for: sentRows, grouped: true)
            .map { $0.displayRow(in: sent).sender }
        XCTAssertEqual(sentNames.first, "Jane Example, Sam Example, Pat Example, lee@example.com")
        XCTAssertEqual(Array(sentNames.dropFirst()), Array(repeating: "Carlo", count: 8),
                       "the seeded letters, each to Carlo")
        for fetch in server.log.filter({ $0.verb == "UID FETCH" }).map(\.command) {
            XCTAssertTrue(fetch.hasSuffix(" (UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE "
                                          + "BODYSTRUCTURE X-GM-LABELS X-GM-THRID X-GM-MSGID)"),
                          fetch)
        }

        let draftRows = try await repository.listMessages(in: drafts.id, beforeUID: nil, limit: 20)
        let draftNames = MessageThread.rows(for: draftRows, grouped: true)
            .map { $0.displayRow(in: drafts).sender }
        XCTAssertEqual(Set(draftNames), ["Lee Example", "No Recipients", "Sam Example"])
        XCTAssertEqual(draftNames.filter { $0 == "Sam Example" }.count, 2, "the seeded drafts")

        let inSent = try await repository.search(in: sent.id, query: "Lunch on Sunday",
                                                 scope: .currentMailbox, beforeUID: nil, limit: 20)
        XCTAssertEqual(MessageThread.rows(for: inSent, grouped: false)
                        .map { $0.displayRow(in: sent).sender },
                       ["Jane Example, Sam Example, Pat Example, lee@example.com"])
        let everywhere = try await repository.search(in: sent.id, query: "Lunch on Sunday",
                                                     scope: .allMailboxes, beforeUID: nil, limit: 20)
        XCTAssertEqual(everywhere.map(\.mailboxID), [Server.allMail])
        XCTAssertEqual(MessageThread.rows(for: everywhere, grouped: false)
                        .map { $0.displayRow(in: sent).sender }, ["Owner Example"])

        shelf.flush()
        let keptRows = try XCTUnwrap(keptShelf(for: server.account).page(of: sent.id)).rows
        XCTAssertEqual(MessageThread.rows(for: keptRows, grouped: true)
                        .map { $0.displayRow(in: sent).sender }, sentNames)
        let keptDrafts = try XCTUnwrap(keptShelf(for: server.account).page(of: drafts.id)).rows
        XCTAssertEqual(MessageThread.rows(for: keptDrafts, grouped: true)
                        .map { $0.displayRow(in: drafts).sender }, draftNames)
    }

    // MARK: - The copy kept on the iPad

    /// Whom a row is to, and its Bcc, are kept with it and read back, an
    /// empty To as empty, so a draft to nobody still says "No Recipients"
    /// at the next launch. A page kept before rows carried a To reads, its
    /// rows not knowing, and they name their sender as they did until the
    /// folder is listed: no new format, and no "No Recipients" over every
    /// kept row in Sent Mail on the first launch of this build.
    func testWhomARowIsToIsKeptAndAPageKeptWithoutItNamesItsSender() throws {
        let account = MailAccount(address: "owner@example.com", username: "owner@example.com")
        let rows = [
            letter("1/9", in: Self.sent, to: [Self.jane], bcc: ["lee@example.com"]),
            letter("1/8", in: Self.sent, to: [], hoursAgo: 1),
            letter("1/7", in: Self.sent, to: [Self.sam], cc: [Self.jane], hoursAgo: 2),
        ]
        let writing = keptShelf(for: account)
        writing.took(page: rows, of: Self.sent.id, validity: 4)
        writing.flush()
        let back = try XCTUnwrap(keptShelf(for: account).page(of: Self.sent.id)).rows
        XCTAssertEqual(back.map(\.to), rows.map(\.to))
        XCTAssertEqual(back.map(\.bcc), rows.map(\.bcc))
        XCTAssertEqual(MessageThread.rows(for: back, grouped: true).map { $0.displayRow(in: Self.sent).sender },
                       ["Jane Example, lee@example.com", "No Recipients", "Sam Example, Jane Example"])

        // The page as a build before the To wrote it.
        let file = try pageFile(of: Self.sent.id, under: writing.directory)
        var page = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file))
                                    as? [String: Any])
        var records = try XCTUnwrap(page["rows"] as? [[String: Any]])
        XCTAssertEqual(records.filter { $0["to"] != nil }.count, 3, "an empty To is written too")
        XCTAssertEqual(records.filter { $0["bcc"] != nil }.count, 1, "only the row with a Bcc")
        for i in records.indices {
            records[i]["to"] = nil
            records[i]["bcc"] = nil
        }
        page["rows"] = records
        try JSONSerialization.data(withJSONObject: page).write(to: file)

        let old = try XCTUnwrap(keptShelf(for: account).page(of: Self.sent.id)).rows
        XCTAssertEqual(old.map(\.id), rows.map(\.id))
        XCTAssertEqual(old.map(\.to), [nil, nil, nil])
        XCTAssertEqual(old.map(\.cc), rows.map(\.cc))
        XCTAssertEqual(MessageThread.rows(for: old, grouped: true).map { $0.displayRow(in: Self.sent).sender },
                       Array(repeating: "Owner Example", count: 3))
    }

    /// The file a page is kept in, found by what it says it is.
    private func pageFile(of folder: String, under directory: URL) throws -> URL {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        for name in names where name.hasPrefix("page-") {
            let url = directory.appendingPathComponent(name)
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            if (object as? [String: Any])?["folder"] as? String == folder { return url }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    // MARK: - The list's wiring

    /// `MessageListViewController` is UIKit and never builds on this host,
    /// so its wiring is read from its source: every row it draws, at first
    /// and when previews come, by `displayRow(in:)` with the list's folder,
    /// and labelled for VoiceOver by `accessibilityLabel(in:)`, never by
    /// the senders alone.
    func testTheListDrawsAndLabelsEveryRowByItsFolder() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/UI/MessageListViewController.swift")
        let code = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
        for wiring in [
            "case let .thread(t): cell.configure(with: t.displayRow(in: mailbox))",
            "case let .thread(thread): cell.configure(with: thread.displayRow(in: mailbox))",
            "cell.accessibilityLabel = thread.accessibilityLabel(in: mailbox)",
        ] {
            XCTAssertTrue(code.contains(wiring), wiring)
        }
        XCTAssertFalse(code.contains("displayRow()"))
        XCTAssertFalse(code.contains(".participants"))
    }
}
