import XCTest
@testable import Blackmail

/// The date a row of the list shows (B-178): when its letter arrived, the
/// date the list is in order of, as Mail's row shows it; its Date only
/// where the row does not say when it arrived.
///
/// Found on the test iPad on 2026-10-28 (round r6-j-act): Mail 16.5.1 read
/// "4:12 AM" on a letter dated 1 March 2024 that arrived that morning, and
/// "10/8/26" on one dated that morning that arrived twenty days before.
/// Blackmail had them in the same places, by arrival, but read "3/1/24"
/// and "3:00 AM", their Dates. The reading pane, a reply's quote, Print
/// and Forward keep the Date, which these tests hold too.
final class RowDateTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "RowDateTests"
    private static let day: TimeInterval = 86_400

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer(inboxCount: 30)
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        server = nil
        book = nil
        super.tearDown()
    }

    private func makeRepository(shelf: MailShelf? = nil) -> IMAPMailRepository {
        let clock = Server.newestDate.addingTimeInterval(Self.day)
        return IMAPMailRepository(account: server.account, password: server.password,
                                  transport: server.transportFactory, recipients: book,
                                  now: { clock }, shelf: shelf ?? keptShelf(for: server.account))
    }

    private static let inbox = Mailbox(id: "inbox", name: "Inbox", unreadCount: 0, role: .inbox)

    private func uid(_ id: String) -> UInt32 { UInt32(id.split(separator: "/")[1])! }

    /// A letter of the round's: from a made-up address, read, its Date and
    /// its arrival as given.
    private func letter(_ subject: String, dated: Date, arrived: Date,
                        joins: String? = nil) -> Server.Letter {
        var letter = Server.Letter(from: Server.sam, to: [Server.owner], subject: subject,
                                   date: dated, text: "A few words.\r\n", flags: ["\\Seen"],
                                   messageID: "<\(subject.split(separator: " ").joined())@example.com>",
                                   arrived: arrived)
        letter.joins = joins
        return letter
    }

    /// "dated old": arrived a moment ago, dated 1 March 2024.
    private var datedOld: Server.Letter {
        letter("R6 B-178 dated old", dated: Date(timeIntervalSince1970: 1_709_294_400),
               arrived: Server.newestDate.addingTimeInterval(600))
    }

    /// "came old": arrived twenty days back, dated a moment ago.
    private var cameOld: Server.Letter {
        letter("R6 B-178 came old", dated: Server.newestDate.addingTimeInterval(300),
               arrived: Server.newestDate.addingTimeInterval(-(20 * Self.day)))
    }

    /// The rows the list draws for `rows`, grouped as with Organize by
    /// Thread on, as the controller draws each (`displayRow(in:mine:)`).
    private func drawn(_ rows: [MessageSummary]) -> [MessageSummary] {
        MessageThread.rows(for: rows, grouped: true).map {
            $0.displayRow(in: Self.inbox, mine: OwnAddresses([]))
        }
    }

    /// The round's two letters: each row shows when its letter arrived,
    /// the date the list put it by, and VoiceOver reads the same; the
    /// letter keeps its Date for the reading pane, the quote and Forward.
    func testEachRowShowsWhenItsLetterArrived() async throws {
        let old = datedOld
        let came = cameOld
        let putOld = try XCTUnwrap(server.deliver(old, to: [Server.inbox])[Server.inbox])
        let putCame = try XCTUnwrap(server.deliver(came, to: [Server.inbox])[Server.inbox])
        let rows = try await makeRepository().listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let threads = MessageThread.rows(for: rows, grouped: true)
        let shown = drawn(rows)

        let atOld = try XCTUnwrap(shown.firstIndex { uid($0.id) == putOld })
        let atCame = try XCTUnwrap(shown.firstIndex { uid($0.id) == putCame })
        XCTAssertEqual(atOld, 0, "dated old arrived last")
        XCTAssertEqual(shown[atOld].listDate, old.arrival)
        XCTAssertEqual(shown[atCame].listDate, came.arrival)
        XCTAssertEqual(threads[atOld].listDate, old.arrival)
        let now = Server.newestDate.addingTimeInterval(3_600)
        XCTAssertTrue(threads[atCame].accessibilityLabel(in: Self.inbox, mine: OwnAddresses([]), now: now)
            .hasSuffix(MailFormat.listTimestamp(came.arrival, now: now)))
        XCTAssertNotEqual(MailFormat.listTimestamp(came.arrival, now: now),
                          MailFormat.listTimestamp(came.date, now: now))
        // The dates down the list go in step with it.
        XCTAssertEqual(shown.map(\.listDate), shown.map(\.listDate).sorted(by: >))
        // The letter's own Date is kept, for the pane, the quote and Forward.
        let letterOld = try XCTUnwrap(rows.first { uid($0.id) == putOld })
        XCTAssertEqual(letterOld.date, old.date)
        XCTAssertEqual(threads[atOld].date, old.date)
    }

    /// A conversation's row shows when its newest letter arrived: a reply
    /// that came today to a letter of twenty days back, the reply dated
    /// long before.
    func testAConversationsRowShowsWhenItsNewestLetterArrived() async throws {
        let first = cameOld
        server.deliver(first, to: [Server.inbox])
        let reply = letter("Re: R6 B-178 came old", dated: Date(timeIntervalSince1970: 1_709_294_400),
                           arrived: Server.newestDate.addingTimeInterval(900), joins: first.messageID)
        server.deliver(reply, to: [Server.inbox])
        let rows = try await makeRepository().listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let top = try XCTUnwrap(MessageThread.rows(for: rows, grouped: true).first)
        XCTAssertEqual(top.count, 2)
        XCTAssertEqual(top.displayRow(in: Self.inbox, mine: OwnAddresses([])).listDate, reply.arrival)
    }

    /// A row that does not say when it arrived, kept by a build before
    /// rows carried it, shows its Date, as it did.
    func testARowKeptWithNoArrivalShowsItsDate() {
        let dated = Date(timeIntervalSince1970: 1_709_294_400)
        let kept = MessageSummary(id: "1/7", mailboxID: "inbox", sender: "Sam", subject: "Old",
                                  preview: "", date: dated, isRead: true, isFlagged: false)
        XCTAssertNil(kept.arrived)
        XCTAssertEqual(kept.listDate, dated)
        XCTAssertEqual(drawn([kept]).first?.listDate, dated)
    }

    /// The kept page, drawn at the next launch before anything is sent,
    /// shows the same dates the list did.
    func testTheKeptRowsShowWhenTheirLettersArrived() async throws {
        let old = datedOld
        let came = cameOld
        server.deliver(old, to: [Server.inbox])
        server.deliver(came, to: [Server.inbox])
        let shelf = keptShelf(for: server.account)
        let rows = try await makeRepository(shelf: shelf).listMessages(in: "inbox", beforeUID: nil,
                                                                       limit: 50)
        shelf.flush()
        let kept = try XCTUnwrap(keptShelf(for: server.account).page(of: Server.inbox)).rows
        XCTAssertEqual(kept.map(\.id), rows.map(\.id))
        XCTAssertEqual(drawn(kept).map(\.listDate), drawn(rows).map(\.listDate))
        XCTAssertTrue(drawn(kept).contains { $0.listDate == old.arrival })
        XCTAssertTrue(drawn(kept).contains { $0.listDate == came.arrival })
    }

    /// Where a search's hits are merged, the Trash's and Spam's among the
    /// searched folder's with All Mailboxes, and the kept hits a search
    /// finds with no connection, they go newest first by the date their
    /// rows show: when each arrived. The searched folder's own hits keep
    /// the SEARCH's UID order, which this does not test.
    func testSearchHitsGoByTheDateTheirRowsShow() {
        func row(_ id: String, dated: TimeInterval, arrived: TimeInterval?) -> MessageSummary {
            MessageSummary(id: id, mailboxID: "inbox", sender: "Sam", subject: "Tickets",
                           preview: "", date: Date(timeIntervalSince1970: dated), isRead: true,
                           isFlagged: false, arrived: arrived.map { Date(timeIntervalSince1970: $0) })
        }
        let datedOld = row("1/30", dated: 1_000, arrived: 9_000)
        let cameOld = row("1/31", dated: 8_000, arrived: 2_000)
        let plain = row("1/5", dated: 5_000, arrived: 5_000)
        XCTAssertTrue(SearchMerge.isOrderedBefore(datedOld, cameOld))
        let merged = SearchMerge.take(3, from: [datedOld, plain], primaryExhausted: true,
                                      and: [cameOld])
        XCTAssertEqual(merged.taken.map(\.id), ["1/30", "1/5", "1/31"])
        let hits = KeptSearch.hits(for: "tickets", in: [cameOld, plain, datedOld]) { _ in nil }
        XCTAssertEqual(hits.map(\.id), ["1/30", "1/5", "1/31"])
    }

    /// The cell draws the row's `listDate`, not its Date.
    func testTheCellDrawsTheDateTheListGoesBy() throws {
        let cell = try source("Sources/Blackmail/UI/MessageCell.swift")
        XCTAssertTrue(cell.contains("date = m.listDate"))
        XCTAssertFalse(cell.contains("date = m.date"))
    }

    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent(file)
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }
}
