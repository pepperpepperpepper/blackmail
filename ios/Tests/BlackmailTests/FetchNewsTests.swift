import XCTest
@testable import Blackmail

/// The server's news of a mark set or taken off on another device, told
/// inside the answer to a UID FETCH of the app's own (B-112). RFC 3501
/// §7.4.2 lets a server send a FETCH at any time, and Gmail told the test
/// iPad of a mark set from another IMAP session inside a Refresh's listing:
/// the letter's whole line, with its old flags, and after it `* 68 FETCH
/// (UID 422 FLAGS (\Answered \Seen))`. Taken as a summary of its own, the
/// news line took the letter's place, and its row said "(unknown sender)",
/// "(no subject)" and 31/12/69, with no Gmail ids, out of its conversation.
///
/// Over the shipping repository and client and `ScriptedIMAPServer`, whose
/// `storeElsewhere` is another device's STORE and whose `flagNews` says
/// where in the next answer the connection is told of it: ahead of a
/// FETCH's own lines, straight after the letter's own line, at the end, or
/// on a NOOP. The connection log the app keeps beside the wire shows where
/// it was told, so each test shows the news came where it says.
final class FetchNewsTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "FetchNewsTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var clock: ManualClock!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        clock = ManualClock()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        Diagnostics.clear()
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        server = nil
        book = nil
        clock = nil
        super.tearDown()
    }

    private func makeRepository(shelf: MailShelf? = nil) -> IMAPMailRepository {
        let clock = self.clock!
        return IMAPMailRepository(account: server.account, password: server.password,
                                  transport: server.transportFactory, recipients: book,
                                  now: { clock.now() },
                                  shelf: shelf ?? keptShelf(for: server.account))
    }

    /// Logged in, the Inbox selected, the log cleared.
    private func connectedClient() async throws -> IMAPClient {
        let clock = self.clock!
        let client = IMAPClient(account: server.account, transport: server.transportFactory,
                                now: { clock.now() })
        try await client.connect(password: server.password)
        _ = try await client.searchAll(in: Server.inbox)
        server.clearLog()
        Diagnostics.clear()
        return client
    }

    private func uid(_ id: String) -> UInt32 { UInt32(id.split(separator: "/").last ?? "")! }

    private var verbs: [String] { server.log.map(\.verb) }

    private var inboxValidity: UInt32 { server.uidValidity(of: Server.inbox) }

    /// Inbox letter `i` of the seeded 120, 1 the oldest, and its UID.
    private func seeded(_ i: Int) throws -> (uid: UInt32, letter: Server.Letter) {
        let uid = server.uids(in: Server.inbox)[i - 1]
        return (uid, try XCTUnwrap(server.letter(uid: uid, in: Server.inbox)))
    }

    /// A conversation of two letters, newer than the rest of the Inbox and
    /// both unread, the second a reply Gmail threads with the first. Their
    /// UIDs, the first's first.
    private func conversation() throws -> (older: UInt32, newer: UInt32) {
        let first = Server.Letter(from: Server.jane, to: [Server.owner], subject: "The garden plan",
                                  date: Server.newestDate.addingTimeInterval(3_600),
                                  text: "Shall we plant in May?\r\n", messageID: "<plan@example.com>")
        let reply = Server.Letter(from: Server.carlo, to: [Server.owner],
                                  subject: "Re: The garden plan",
                                  date: Server.newestDate.addingTimeInterval(7_200),
                                  text: "May it is.\r\n", messageID: "<plan-re@example.org>",
                                  inReplyTo: "<plan@example.com>", references: "<plan@example.com>",
                                  joins: "<plan@example.com>")
        let older = try XCTUnwrap(server.deliver(first, to: [Server.inbox, Server.allMail])[Server.inbox])
        let newer = try XCTUnwrap(server.deliver(reply, to: [Server.inbox, Server.allMail])[Server.inbox])
        return (older, newer)
    }

    // MARK: - The wire, as the connection log has it

    /// The server's answer to each UID FETCH the connection log shows sent
    /// since it was cleared: its untagged lines in order, literals and the
    /// tagged line left out.
    private func fetchAnswers() -> [[String]] {
        var out: [[String]] = []
        var open: String?
        for entry in Diagnostics.entries {
            switch entry.direction {
            case .sent:
                let words = entry.text.split(separator: " ")
                open = nil
                if words.count > 2, words[1] == "UID", words[2] == "FETCH" {
                    open = String(words[0])
                    out.append([])
                }
            case .received:
                guard let tag = open else { continue }
                if entry.text.hasPrefix(tag + " ") {
                    open = nil
                } else if entry.text.hasPrefix("* ") {
                    out[out.count - 1].append(entry.text)
                }
            case .note:
                continue
            }
        }
        return out
    }

    /// The server's own line of news for `uid`: `* n FETCH (UID u FLAGS (…))`.
    private func isNews(_ line: String, of uid: UInt32) -> Bool {
        line.contains(" FETCH (UID \(uid) FLAGS (") && line.hasSuffix("))")
            && !line.contains("ENVELOPE") && !line.contains("X-GM-")
    }

    /// A summary FETCH's own line for `uid`.
    private func isSummary(_ line: String, of uid: UInt32) -> Bool {
        line.contains("FETCH (UID \(uid) ") && line.contains("ENVELOPE")
    }

    private var notes: [String] { Diagnostics.entries.filter { $0.direction == .note }.map(\.text) }

    // MARK: - Rows

    /// The row is the letter's, whole: its sender, subject and date, its
    /// conversation and Gmail's id for it.
    private func assertWhole(_ row: MessageSummary?, is letter: Server.Letter, uid: UInt32,
                             in mailbox: String = Server.inbox,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let row else { return XCTFail("no row", file: file, line: line) }
        XCTAssertEqual(self.uid(row.id), uid, file: file, line: line)
        XCTAssertTrue(row.sender.contains(letter.from.address), row.sender, file: file, line: line)
        XCTAssertEqual(row.subject, letter.subject, file: file, line: line)
        XCTAssertEqual(row.date, letter.date, file: file, line: line)
        XCTAssertNotNil(row.threadID, file: file, line: line)
        XCTAssertEqual(row.gmailMessageID, server.gmailMessageID(uid: uid, in: mailbox),
                       file: file, line: line)
    }

    /// No row is the blank one a news line made: every row has a sender, a
    /// subject, a date after 1970 and Gmail's ids.
    private func assertNoBlankRow(_ rows: [MessageSummary],
                                  file: StaticString = #filePath, line: UInt = #line) {
        for row in rows {
            XCTAssertNotEqual(row.sender, "(unknown sender)", row.id, file: file, line: line)
            XCTAssertFalse(row.subject.isEmpty, row.id, file: file, line: line)
            XCTAssertGreaterThan(row.date, Date(timeIntervalSince1970: 86_400), row.id,
                                 file: file, line: line)
            XCTAssertNotNil(row.threadID, row.id, file: file, line: line)
            XCTAssertNotNil(row.gmailMessageID, row.id, file: file, line: line)
        }
    }

    // MARK: - A Refresh

    /// What the test iPad did, three times in three: the newer letter of a
    /// conversation marked elsewhere, then Refresh. The NOOP is answered
    /// with no news, and Gmail tells of the mark inside the listing's FETCH,
    /// straight after the letter's whole line, which carries its old flags.
    /// The row is the letter's, whole and marked read, still in its
    /// conversation, its neighbour as it was, and the page kept on the iPad
    /// has it so, on disk too. The connection log's SESSION-IDENT names
    /// Gmail's id for the letter at the top, where the iPad's said `msgid=-`.
    func testAMarkMadeElsewhereToldInsideTheListingLeavesItsRowWholeAndMarked() async throws {
        let (older, newer) = try conversation()
        let reply = try XCTUnwrap(server.letter(uid: newer, in: Server.inbox))
        let shelf = keptShelf(for: server.account)
        let repository = makeRepository(shelf: shelf)
        let before = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(before.prefix(2).map { uid($0.id) }, [newer, older])
        XCTAssertEqual(before[0].threadID, before[1].threadID, "one conversation")

        server.flagNews = .insideFetch
        server.storeElsewhere(uid: newer, in: Server.inbox, adding: ["\\Seen"])
        clock.advance(by: 60)
        server.clearLog()
        Diagnostics.clear()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)

        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])
        let answer = try XCTUnwrap(fetchAnswers().first)
        let own = try XCTUnwrap(answer.firstIndex { isSummary($0, of: newer) })
        XCTAssertTrue(answer[own].contains("FLAGS ()"), "the whole line carries the old flags")
        XCTAssertEqual(answer.firstIndex { isNews($0, of: newer) }, own + 1, "told straight after it")
        XCTAssertTrue(answer[own + 1].hasSuffix("FETCH (UID \(newer) FLAGS (\\Seen))"))

        XCTAssertEqual(rows.map(\.id), before.map(\.id))
        assertWhole(rows.first, is: reply, uid: newer)
        XCTAssertEqual(rows.first?.isRead, true)
        XCTAssertEqual(rows.first?.threadID, before[0].threadID)
        XCTAssertEqual(rows[1].threadID, rows[0].threadID, "still one conversation")
        XCTAssertFalse(rows[1].isRead)
        assertNoBlankRow(rows)
        let letter = try XCTUnwrap(server.gmailMessageID(uid: newer, in: Server.inbox))
        XCTAssertTrue(notes.contains { $0.hasPrefix("SESSION-IDENT") && $0.hasSuffix("msgid=\(letter)") },
                      "\(notes)")

        for label in ["now", "on disk"] {
            var kept = shelf
            if label == "on disk" {
                shelf.flush()
                kept = keptShelf(for: server.account)
            }
            let page = try XCTUnwrap(kept.page(of: "inbox")?.rows, label)
            XCTAssertEqual(page.map(\.id), rows.map(\.id), label)
            assertWhole(page.first, is: reply, uid: newer)
            XCTAssertEqual(page.first?.isRead, true, label)
            assertNoBlankRow(page)
        }
    }

    /// The news told ahead of the listing's own lines, which then carry the
    /// new flags: the row is the letter's whole line, not the news before
    /// it, so a first-come summary would be the blank row.
    func testTheNewsToldAheadOfTheListingsOwnLinesLeavesTheRowWhole() async throws {
        let (_, newer) = try conversation()
        let reply = try XCTUnwrap(server.letter(uid: newer, in: Server.inbox))
        let repository = makeRepository()
        let before = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)

        server.flagNews = .beforeFetch
        server.storeElsewhere(uid: newer, in: Server.inbox, adding: ["\\Seen"])
        clock.advance(by: 60)
        Diagnostics.clear()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)

        let answer = try XCTUnwrap(fetchAnswers().first)
        XCTAssertTrue(isNews(answer[0], of: newer), answer[0])
        let own = try XCTUnwrap(answer.first { isSummary($0, of: newer) })
        XCTAssertTrue(own.contains("FLAGS (\\Seen)"), "the whole line carries the new flags")

        XCTAssertEqual(rows.map(\.id), before.map(\.id))
        assertWhole(rows.first, is: reply, uid: newer)
        XCTAssertEqual(rows.first?.isRead, true)
        XCTAssertEqual(rows[1].threadID, rows[0].threadID)
        assertNoBlankRow(rows)
    }

    /// The news at the end of the listing's answer, as Gmail told it a few
    /// seconds after the mark on the iPad, for a letter in the middle of the
    /// page, flagged elsewhere: its row whole and flagged, the news laid over
    /// the old flags its whole line carried, and no other row changed.
    func testTheNewsToldAtTheEndOfTheListingLeavesTheRowWholeWithTheNewMark() async throws {
        let repository = makeRepository()
        let before = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let (marked, letter) = try seeded(111)
        XCTAssertEqual(uid(before[9].id), marked)
        XCTAssertFalse(before[9].isFlagged)

        server.flagNews = .afterFetch
        server.storeElsewhere(uid: marked, in: Server.inbox, adding: ["\\Flagged"])
        clock.advance(by: 60)
        Diagnostics.clear()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)

        let answer = try XCTUnwrap(fetchAnswers().first)
        XCTAssertEqual(answer.count, 51)
        XCTAssertTrue(isNews(answer[50], of: marked), answer[50])
        XCTAssertTrue(answer.prefix(50).allSatisfy { $0.contains("ENVELOPE") })
        XCTAssertFalse(try XCTUnwrap(answer.first { isSummary($0, of: marked) }).contains("\\Flagged"))

        XCTAssertEqual(rows.map(\.id), before.map(\.id))
        assertWhole(rows[9], is: letter, uid: marked)
        XCTAssertTrue(rows[9].isFlagged)
        XCTAssertTrue(rows[9].isRead)
        XCTAssertEqual(rows.enumerated().filter { $0.offset != 9 }.map { $0.element.isFlagged },
                       before.enumerated().filter { $0.offset != 9 }.map { $0.element.isFlagged })
        assertNoBlankRow(rows)
    }

    /// Marks taken off elsewhere, told inside the listing: every mark of a
    /// letter that had only `\Seen`, whose news is `FLAGS ()`, and the read
    /// mark of a flagged letter in Starred, whose news is `FLAGS
    /// (\Flagged)`. An empty FLAGS that was sent takes every mark off; and
    /// a news line, carrying no X-GM-LABELS, leaves the labels of the
    /// letter's own line, so the flagged one is still counted in Starred.
    func testMarksTakenOffElsewhereToldInsideTheListingTakeOffWhatTheySay() async throws {
        let repository = makeRepository()
        let before = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let (plain, plainLetter) = try seeded(100)
        let (starred, starredLetter) = try seeded(110)
        XCTAssertEqual(server.flags(uid: plain, in: Server.inbox), ["\\Seen"])
        XCTAssertEqual(server.flags(uid: starred, in: Server.inbox), ["\\Seen", "\\Flagged"])
        XCTAssertTrue(before[10].countedFolderIDs.contains(Server.starred))

        server.flagNews = .insideFetch
        server.storeElsewhere(uid: plain, in: Server.inbox, removing: ["\\Seen"])
        server.storeElsewhere(uid: starred, in: Server.inbox, removing: ["\\Seen"])
        clock.advance(by: 60)
        Diagnostics.clear()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)

        let answer = try XCTUnwrap(fetchAnswers().first)
        XCTAssertTrue(answer.contains { $0.hasSuffix("FETCH (UID \(plain) FLAGS ())") }, "\(answer)")
        XCTAssertTrue(answer.contains { $0.hasSuffix("FETCH (UID \(starred) FLAGS (\\Flagged))") })

        XCTAssertEqual(rows.map(\.id), before.map(\.id))
        assertWhole(rows[20], is: plainLetter, uid: plain)
        XCTAssertFalse(rows[20].isRead, "FLAGS () takes the read mark off")
        XCTAssertFalse(rows[20].isFlagged)
        assertWhole(rows[10], is: starredLetter, uid: starred)
        XCTAssertFalse(rows[10].isRead)
        XCTAssertTrue(rows[10].isFlagged)
        XCTAssertEqual(rows[10].countedFolderIDs, before[10].countedFolderIDs)
        XCTAssertTrue(rows[10].countedFolderIDs.contains(Server.starred))
        assertNoBlankRow(rows)
    }

    /// News inside the listing of a letter it did not ask for, one below the
    /// first page, flagged elsewhere: told after the answer's first line,
    /// the page's oldest letter's, it changes no row and adds none. The page
    /// below, when he scrolls to it, has the letter flagged.
    func testTheNewsOfALetterTheListingDidNotAskForChangesNoRowOnIt() async throws {
        let repository = makeRepository()
        let before = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let (below, letter) = try seeded(60)
        let (oldest, _) = try seeded(71)
        XCTAssertEqual(uid(before[49].id), oldest)
        XCTAssertFalse(before[49].isFlagged)

        server.flagNews = .insideFetch
        server.storeElsewhere(uid: below, in: Server.inbox, adding: ["\\Flagged"])
        clock.advance(by: 60)
        Diagnostics.clear()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)

        let answer = try XCTUnwrap(fetchAnswers().first)
        XCTAssertTrue(isSummary(answer[0], of: oldest), answer[0])
        XCTAssertTrue(isNews(answer[1], of: below), answer[1])
        XCTAssertEqual(answer.count, 51)

        XCTAssertEqual(rows.map(\.id), before.map(\.id))
        XCTAssertEqual(rows.map(\.isFlagged), before.map(\.isFlagged))
        XCTAssertEqual(rows.map(\.isRead), before.map(\.isRead))
        XCTAssertFalse(rows.contains { uid($0.id) == below })
        assertNoBlankRow(rows)

        let next = try await repository.listMessages(in: "inbox", beforeUID: rows.last?.id, limit: 50)
        let row = try XCTUnwrap(next.first { uid($0.id) == below })
        assertWhole(row, is: letter, uid: below)
        XCTAssertTrue(row.isFlagged)
        assertNoBlankRow(next)
    }

    // MARK: - The watch and a search

    /// The watch's check finds a letter that has come, and it is marked
    /// read elsewhere between the check's SEARCH and the FETCH of its
    /// summary, the news told inside that FETCH: it goes on the list whole
    /// and read.
    func testTheWatchBringsALetterMarkedElsewhereDuringItsFetchWhole() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let come = Server.Letter(from: Server.sam, to: [Server.owner], subject: "Just come",
                                 date: Server.newestDate.addingTimeInterval(1_200),
                                 text: "Hello.\r\n", messageID: "<just@example.com>")
        let arrived = try XCTUnwrap(server.arrive(come, in: [Server.inbox, Server.allMail])[Server.inbox])
        server.flagNews = .insideFetch
        let scripted = self.server!
        scripted.change(after: { $0.verb == "UID SEARCH" }) {
            scripted.storeElsewhere(uid: arrived, in: Server.inbox, adding: ["\\Seen"])
        }
        clock.advance(by: 30)
        server.clearLog()
        Diagnostics.clear()

        let news = try await repository.news(in: "inbox", known: rows.map(\.id), searchingAnyway: false)

        XCTAssertEqual(verbs, ["NOOP", "UID SEARCH", "UID FETCH"])
        let answer = try XCTUnwrap(fetchAnswers().first)
        XCTAssertEqual(answer.count, 2)
        XCTAssertTrue(isSummary(answer[0], of: arrived) && answer[0].contains("FLAGS ()"), answer[0])
        XCTAssertTrue(isNews(answer[1], of: arrived), answer[1])
        XCTAssertEqual(news.arrived.count, 1)
        assertWhole(news.arrived.first, is: come, uid: arrived)
        XCTAssertEqual(news.arrived.first?.isRead, true)
        assertNoBlankRow(news.arrived)
    }

    /// An All Mailboxes search, a letter in the Trash flagged elsewhere
    /// between the Trash's SEARCH and the FETCH of its hits' summaries, the
    /// news told inside it: the binned hit is the letter's, whole and
    /// flagged.
    func testABinnedHitMarkedElsewhereDuringItsSummariesIsWhole() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let binned = server.uids(in: Server.trash)
        let marked = try XCTUnwrap(binned.last)
        let letter = try XCTUnwrap(server.letter(uid: marked, in: Server.trash))
        server.flagNews = .insideFetch
        let scripted = self.server!
        scripted.change(after: { $0.verb == "UID SEARCH" && $0.selected == Server.trash }) {
            scripted.storeElsewhere(uid: marked, in: Server.trash, adding: ["\\Flagged"])
        }
        Diagnostics.clear()

        let hits = try await repository.search(in: "inbox", query: "Binned", scope: .allMailboxes,
                                               beforeUID: nil, limit: 50)

        let answer = try XCTUnwrap(fetchAnswers().first { $0.contains { isNews($0, of: marked) } })
        let own = try XCTUnwrap(answer.firstIndex { isSummary($0, of: marked) })
        XCTAssertTrue(isNews(answer[own + 1], of: marked))
        let trash = hits.filter { $0.mailboxID == Server.trash }
        XCTAssertEqual(Set(trash.map { uid($0.id) }), Set(binned))
        let row = try XCTUnwrap(trash.first { uid($0.id) == marked })
        assertWhole(row, is: letter, uid: marked, in: Server.trash)
        XCTAssertTrue(row.isFlagged)
        assertNoBlankRow(hits)
    }

    // MARK: - A row kept from the launch before

    /// The launch before, as it leaves the iPad: the Inbox listed and kept.
    private func earlierLaunch() async throws -> [MessageSummary] {
        let shelf = keptShelf(for: server.account)
        let repository = makeRepository(shelf: shelf)
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        shelf.flush()
        return rows
    }

    /// A read mark on a kept row, the first thing this launch does in the
    /// Inbox, with the news of a mark set on the letter elsewhere told ahead
    /// of the FETCH that vouches for it (D-016): the FETCH names the row's
    /// letter, so the mark goes, and the row stays on the kept page. Read
    /// first-come, the news was what the FETCH found under the UID, with no
    /// Gmail id, and the row was taken for another letter's.
    func testAWriteOnAKeptRowGoesWithTheNewsToldAheadOfItsVouchingFetch() async throws {
        _ = try await earlierLaunch()
        let shelf = keptShelf(for: server.account)
        let repository = makeRepository(shelf: shelf)
        let kept = try XCTUnwrap(shelf.page(of: "inbox")).rows
        let row = kept[0]
        XCTAssertFalse(row.isRead)
        server.flagNews = .beforeFetch
        let scripted = self.server!
        let marked = uid(row.id)
        scripted.change(after: { $0.verb == "SELECT" }) {
            scripted.storeElsewhere(uid: marked, in: Server.inbox, adding: ["\\Flagged"])
        }
        server.clearLog()
        Diagnostics.clear()

        try await repository.setRead(true, on: row)

        XCTAssertEqual(Array(verbs.suffix(3)), ["SELECT", "UID FETCH", "UID STORE"])
        let answer = try XCTUnwrap(fetchAnswers().first)
        XCTAssertEqual(answer.count, 2)
        XCTAssertTrue(isNews(answer[0], of: marked), answer[0])
        XCTAssertTrue(server.flags(uid: marked, in: Server.inbox).contains("\\Seen"))
        XCTAssertEqual(shelf.page(of: "inbox")?.rows.map(\.id), kept.map(\.id), "kept")
    }

    /// A kept row's letter opened, with the news told ahead of the FETCH
    /// that brings it and names it: the letter, its words and all.
    func testAKeptRowsLetterOpensWithTheNewsToldAheadOfItsFetch() async throws {
        _ = try await earlierLaunch()
        let shelf = keptShelf(for: server.account)
        let repository = makeRepository(shelf: shelf)
        let row = try XCTUnwrap(shelf.page(of: "inbox")).rows[1]
        let marked = uid(row.id)
        let letter = try XCTUnwrap(server.letter(uid: marked, in: Server.inbox))
        server.flagNews = .beforeFetch
        let scripted = self.server!
        scripted.change(after: { $0.verb == "SELECT" }) {
            scripted.storeElsewhere(uid: marked, in: Server.inbox, adding: ["\\Flagged"])
        }
        Diagnostics.clear()

        let message = try await repository.open(row)

        let answer = try XCTUnwrap(fetchAnswers().last)
        XCTAssertTrue(isNews(answer[0], of: marked), answer[0])
        XCTAssertEqual(message.subject, letter.subject)
        XCTAssertEqual(message.textBody?.contains("Letter 119."), true, message.textBody ?? "none")
    }

    // MARK: - Every FETCH of one letter

    /// Each FETCH the client makes of one letter, with the news of a mark
    /// set or taken off it elsewhere told ahead of the letter's own line:
    /// each answers for the letter, its Gmail id, its bytes, its structure,
    /// its part and its summary, never for the bare news line before it.
    func testEveryFetchOfOneLetterAnswersForItWithTheNewsToldAheadOfItsLine() async throws {
        let file = Server.File(name: "plan.pdf", type: "APPLICATION", subtype: "PDF",
                               bytes: Data((0..<600).map { UInt8($0 % 251) }), contentID: nil)
        let sent = Server.Letter(from: Server.sam, to: [Server.owner], subject: "The plan",
                                 date: Server.newestDate.addingTimeInterval(600),
                                 text: "The plan is attached.\r\n", messageID: "<plan-file@example.com>",
                                 files: [file])
        let n = try XCTUnwrap(server.deliver(sent, to: [Server.inbox, Server.allMail])[Server.inbox])
        let letter = try XCTUnwrap(server.gmailMessageID(uid: n, in: Server.inbox))
        let raw = try XCTUnwrap(server.raw(uid: n, in: Server.inbox))
        let client = try await connectedClient()
        server.flagNews = .beforeFetch
        var flagged = false
        func markElsewhere() {
            flagged.toggle()
            server.storeElsewhere(uid: n, in: Server.inbox, adding: flagged ? ["\\Flagged"] : [],
                                  removing: flagged ? [] : ["\\Flagged"])
            Diagnostics.clear()
        }
        func toldAhead(_ what: String, file: StaticString = #filePath, line: UInt = #line) {
            let first = fetchAnswers().first?.first ?? "nothing"
            XCTAssertTrue(isNews(first, of: n), "\(what): \(first)", file: file, line: line)
        }

        markElsewhere()
        let named = try await client.gmailMessageID(uid: n, in: Server.inbox, validity: inboxValidity)
        toldAhead("X-GM-MSGID")
        XCTAssertEqual(named, letter)

        markElsewhere()
        let vouched = try await client.fetchBodyNamingLetter(uid: n, in: Server.inbox, validity: inboxValidity)
        toldAhead("the whole letter, named")
        XCTAssertEqual(vouched.letter, letter)
        XCTAssertEqual(vouched.raw, raw)

        markElsewhere()
        let asked = try await client.fetchBodyAskingLetter(uid: n, in: Server.inbox, validity: inboxValidity)
        toldAhead("the whole letter, asked")
        XCTAssertEqual(asked.letter, letter)
        XCTAssertEqual(asked.raw, raw)

        markElsewhere()
        let whole = try await client.fetchBody(uid: n, section: nil, in: Server.inbox, validity: inboxValidity)
        toldAhead("the whole letter")
        XCTAssertEqual(whole, raw)

        markElsewhere()
        let inPart = try await client.fetchLetterInPart(uid: n, in: Server.inbox, validity: inboxValidity,
                                                        question: .expecting(letter), sectionBytes: 64,
                                                        sections: { _ in ["1"] })
        toldAhead("the letter in parts")
        XCTAssertEqual(inPart.letter, letter)
        XCTAssertNotNil(inPart.structure)
        XCTAssertTrue(String(decoding: inPart.header, as: UTF8.self).contains("Subject: The plan"))
        XCTAssertEqual(inPart.sections["1"].map { String(decoding: $0, as: UTF8.self) },
                       "The plan is attached.\r\n")

        markElsewhere()
        let part = try await client.fetchPart(uid: n, section: "2", in: Server.inbox,
                                              validity: inboxValidity, naming: letter,
                                              describedBy: { MIMEDecoder.part(at: "2", in: $0) })
        toldAhead("a file")
        let fetched = try XCTUnwrap(part)
        XCTAssertEqual(MIMEDecoder.decodeTransfer(fetched.bytes, encoding: fetched.part.encoding), file.bytes)

        markElsewhere()
        let previews = try await client.fetchPartialBodies(uids: [n], section: "1", byteCount: 8,
                                                           in: Server.inbox, validity: inboxValidity)
        toldAhead("a preview")
        XCTAssertEqual(previews[n].map { String(decoding: $0, as: UTF8.self) }, "The plan")

        markElsewhere()
        let summaries = try await client.fetchSummaries(uids: [n], in: Server.inbox, validity: inboxValidity)
        toldAhead("a summary")
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.envelope?.subject, "The plan")
        XCTAssertEqual(summaries.first?.gmailMessageID, letter)
        XCTAssertEqual(summaries.first?.isFlagged, flagged)
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
    }

    /// A hollow MOVE filing a letter from All Mail in the Inbox, and the
    /// news of a mark set on it elsewhere told ahead of the FETCH of its
    /// labels (B-092): the labels are the letter's own line's, the Inbox's
    /// among them, so the move is done, with no second MOVE.
    func testTheLabelsOfAHollowMoveAreReadWithTheNewsToldAheadOfThem() async throws {
        let client = try await connectedClient()
        let validity = server.uidValidity(of: Server.allMail)
        _ = try await client.searchAll(in: Server.allMail)
        let inbox = Set(server.uids(in: Server.inbox).compactMap {
            server.gmailMessageID(uid: $0, in: Server.inbox)
        })
        let n = try XCTUnwrap(server.uids(in: Server.allMail).last {
            server.gmailMessageID(uid: $0, in: Server.allMail).map { !inbox.contains($0) } ?? false
        })
        server.hollowMoves = [.movedUntold]
        server.flagNews = .beforeFetch
        let scripted = self.server!
        scripted.change(after: { $0.verb == "UID MOVE" }) {
            scripted.storeElsewhere(uid: n, in: Server.allMail, adding: ["\\Flagged"])
        }
        server.clearLog()
        Diagnostics.clear()

        try await client.move(uid: n, from: Server.allMail, validity: validity, to: Server.inbox,
                              stayingLabelled: ["\\inbox"])

        XCTAssertEqual(verbs, ["UID MOVE", "UID FETCH"])
        XCTAssertEqual(server.log.last?.command, "UID FETCH \(n) (X-GM-LABELS)")
        let answer = try XCTUnwrap(fetchAnswers().first)
        XCTAssertTrue(isNews(answer[0], of: n), answer[0])
        XCTAssertTrue(notes.contains("MOVE-CHECKED folder=\(Server.allMail) uid=\(n) labelled"), "\(notes)")
    }

    // MARK: - Summaries in more than one FETCH

    /// An Inbox with more letters than one FETCH's UID set holds, so the
    /// summaries of all of them go in two.
    private func bigInbox() -> ScriptedIMAPServer { ScriptedIMAPServer(inboxCount: 1_500) }

    /// Every summary of an Inbox fetched in two FETCHes, a letter of the
    /// first marked elsewhere once the first is answered, the news told
    /// inside the second: its summary is its own line with the news laid
    /// over it, as for news in the same answer.
    func testTheNewsOfALetterInAnotherChunkIsLaidOverItsSummary() async throws {
        server = bigInbox()
        let client = try await connectedClient()
        let uids = server.uids(in: Server.inbox)
        let marked = uids[0]
        server.flagNews = .insideFetch
        let scripted = self.server!
        scripted.change(after: { $0.verb == "UID FETCH" }) {
            scripted.storeElsewhere(uid: marked, in: Server.inbox, adding: ["\\Flagged"])
        }

        let summaries = try await client.fetchSummaries(uids: uids.reversed(), in: Server.inbox,
                                                        validity: inboxValidity)

        XCTAssertEqual(verbs, ["UID FETCH", "UID FETCH"])
        XCTAssertFalse(server.log[1].command.contains("UID FETCH \(marked)"))
        XCTAssertEqual(summaries.map(\.uid), uids.reversed().map { Optional($0) })
        XCTAssertTrue(summaries.allSatisfy { $0.envelope != nil })
        let summary = try XCTUnwrap(summaries.last)
        XCTAssertEqual(summary.uid, marked)
        XCTAssertEqual(summary.envelope?.subject, server.letter(uid: marked, in: Server.inbox)?.subject)
        XCTAssertTrue(summary.isFlagged)
        XCTAssertTrue(summary.isSeen)
    }

    /// The news of a letter in the second FETCH told inside the first, and
    /// the second refused: the letter's own line never comes, so it has no
    /// summary, and is not made a blank one. The first FETCH's letters come
    /// back, and the log says what was left out.
    func testNewsOfALetterWhoseOwnLineNeverCameMakesNoSummary() async throws {
        server = bigInbox()
        let client = try await connectedClient()
        let uids = server.uids(in: Server.inbox)
        let marked = try XCTUnwrap(uids.last)
        server.flagNews = .insideFetch
        server.storeElsewhere(uid: marked, in: Server.inbox, adding: ["\\Flagged"])
        let scripted = self.server!
        scripted.change(after: { $0.verb == "UID FETCH" }) { scripted.refusedVerbs = ["UID FETCH"] }

        let summaries = try await client.fetchSummaries(uids: uids.reversed(), in: Server.inbox,
                                                        validity: inboxValidity)

        XCTAssertEqual(server.log.map(\.status), ["OK", "NO"])
        XCTAssertFalse(server.log[0].command.contains("\(marked)"))
        XCTAssertFalse(summaries.isEmpty)
        XCTAssertFalse(summaries.contains { $0.uid == marked })
        XCTAssertTrue(summaries.allSatisfy { $0.envelope != nil })
        XCTAssertEqual(Set(summaries.compactMap(\.uid)).count, summaries.count)
        XCTAssertTrue(notes.contains("FETCH-NO-ENVELOPE uid=\(marked) left-out"), "\(notes.suffix(5))")
    }
}
