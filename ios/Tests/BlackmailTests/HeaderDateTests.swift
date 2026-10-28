import XCTest
@testable import Blackmail

/// The date the reading pane's header shows (B-178, the second round): when
/// the letter arrived, as Mail's header shows it; its Date only where that
/// is not known, a letter kept on the iPad with no arrival.
///
/// Found on the test iPad on 2026-10-28 (round r6-k-fix): Mail 16.5.1's
/// header read "10:23 AM" on a letter dated 1 March 2024 that arrived that
/// morning, and "10/8/26" on one dated that morning that arrived on 8
/// October; Blackmail's read "March 1, 2024 at 12:00 PM" and "Today at 9:00
/// AM", their Dates. Blackmail's words for the date and their place are
/// its own, kept (D-008, D-025); only which date. A conversation's lines in
/// the stack go by it too. A reply's "On ... wrote:", Forward and Print
/// keep the Date, which these tests hold as well.
final class HeaderDateTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "HeaderDateTests"
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

    private func makeRepository() -> IMAPMailRepository {
        let clock = Server.newestDate.addingTimeInterval(Self.day)
        return IMAPMailRepository(account: server.account, password: server.password,
                                  transport: server.transportFactory, recipients: book,
                                  now: { clock }, shelf: keptShelf(for: server.account))
    }

    private func uid(_ id: String) -> UInt32 { UInt32(id.split(separator: "/")[1])! }

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

    /// The round's two letters: the header drawn from the row at the tap
    /// and the header of the letter once it has come both show when it
    /// arrived, in the header's own words; the letter itself keeps its
    /// Date, which a reply's "On ... wrote:" and Print write.
    func testTheHeaderShowsWhenTheLetterArrived() async throws {
        let old = datedOld
        let came = cameOld
        let putOld = try XCTUnwrap(server.deliver(old, to: [Server.inbox])[Server.inbox])
        let putCame = try XCTUnwrap(server.deliver(came, to: [Server.inbox])[Server.inbox])
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let now = Server.newestDate.addingTimeInterval(3_600)
        for (put, sent) in [(putOld, old), (putCame, came)] {
            let row = try XCTUnwrap(rows.first { uid($0.id) == put })
            XCTAssertEqual(row.arrived, sent.arrival)
            // At the tap, from the row.
            let standIn = Message.heading(for: row)
            XCTAssertEqual(standIn.headerDate, sent.arrival, sent.subject)
            XCTAssertEqual(Message.heading(for: row, subject: "A conversation").headerDate, sent.arrival)
            // The letter come, given its row's arrival.
            let m = try await repository.openLetter(row)
            XCTAssertEqual(m.date, sent.date, "the letter keeps its Date")
            let shown = m.arriving(as: row)
            XCTAssertEqual(shown.headerDate, sent.arrival, sent.subject)
            XCTAssertEqual(shown.date, sent.date)
            XCTAssertNotEqual(MailFormat.detailTimestamp(shown.headerDate, now: now),
                              MailFormat.detailTimestamp(sent.date, now: now), sent.subject)
            // A reply's "On ... wrote:" and Print go by the Date still.
            let reply = Draft.replying(to: shown, all: false, mine: OwnAddresses([]))
            XCTAssertTrue(reply.body.contains(MailFormat.quoteAttribution(sent.date, sender: m.sender)))
            XCTAssertEqual(PrintPage.head(shown, size: { "\($0)" }).date,
                           MailFormat.printedTimestamp(sent.date))
        }
        // Another letter's row gives nothing.
        let oldRow = try XCTUnwrap(rows.first { uid($0.id) == putOld })
        let cameRow = try XCTUnwrap(rows.first { uid($0.id) == putCame })
        let cameLetter = try await repository.openLetter(cameRow)
        XCTAssertNil(cameLetter.arriving(as: oldRow).arrived)
        XCTAssertEqual(cameLetter.arriving(as: oldRow).headerDate, came.date)
        XCTAssertEqual(cameLetter.arriving(as: nil).headerDate, came.date)
    }

    /// A letter whose row does not say when it arrived, kept by a build
    /// before rows carried it, has its Date in the header, as before.
    func testAKeptLetterWithNoArrivalKeepsItsDate() {
        let dated = Date(timeIntervalSince1970: 1_709_294_400)
        let kept = MessageSummary(id: "1/7", mailboxID: "inbox", sender: "Sam", subject: "Old",
                                  preview: "", date: dated, isRead: true, isFlagged: false)
        XCTAssertNil(kept.arrived)
        XCTAssertEqual(Message.heading(for: kept).headerDate, dated)
        let letter = Message(id: "1/7", mailboxID: "inbox", sender: "Sam", senderAddress: "sam@example.com",
                             to: [], cc: [], subject: "Old", date: dated, textBody: "Hello",
                             htmlBody: nil, attachments: [])
        XCTAssertEqual(letter.arriving(as: kept).headerDate, dated)
        XCTAssertEqual(ConversationDocument.entry(for: kept, open: true).date, dated)
    }

    /// Each letter's line in a conversation's stack has when it arrived,
    /// his own letters from Sent Mail among them.
    func testTheStackShowsWhenEachLetterArrived() async throws {
        let first = cameOld
        server.deliver(first, to: [Server.inbox])
        let reply = letter("Re: R6 B-178 came old", dated: Date(timeIntervalSince1970: 1_709_294_400),
                           arrived: Server.newestDate.addingTimeInterval(900), joins: first.messageID)
        server.deliver(reply, to: [Server.inbox])
        let rows = try await makeRepository().listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let thread = try XCTUnwrap(MessageThread.rows(for: rows, grouped: true).first)
        XCTAssertEqual(thread.count, 2)
        let stack = ConversationDocument.stack(of: thread)
        XCTAssertEqual(stack.map(\.date), [first.arrival, reply.arrival])
        XCTAssertEqual(stack.map(\.date), thread.messages.reversed().map(\.listDate))
        XCTAssertNotEqual(stack.map(\.date), thread.messages.reversed().map(\.date))
        let his = MessageSummary(id: "9/4", mailboxID: "sent", sender: "Me", subject: "Re: R6 B-178 came old",
                                 preview: "", date: Date(timeIntervalSince1970: 1_000), isRead: true,
                                 isFlagged: false, arrived: Date(timeIntervalSince1970: 9_000))
        XCTAssertEqual(ConversationDocument.entry(forHis: his, foundIn: "Sent Mail").date,
                       Date(timeIntervalSince1970: 9_000))
    }

    /// The header draws `headerDate`, and every letter it is given has its
    /// row's arrival: drawn from the row (`heading(for:)`) or given it as
    /// it comes (`arriving(as:)`), in the single letter's pane and in the
    /// stack.
    func testTheHeaderIsGivenTheArrivalWhereverItIsDrawn() throws {
        let header = try source("Sources/Blackmail/UI/MessageHeaderView.swift")
        XCTAssertTrue(header.contains("date = m.headerDate"))
        XCTAssertFalse(header.contains("date = m.date"))
        let pane = try source("Sources/Blackmail/UI/MessageDetailViewController.swift")
        let given = pane.components(separatedBy: "header.configure(with: ").dropFirst()
            .map { String($0.prefix(while: { $0 != "\n" })) }
        XCTAssertEqual(given, [
            ".heading(for: summary))",
            "m.arriving(as: summary))",
            ".heading(for: newest, subject: thread.subject))",
            ".heading(for: row))",
            "m.arriving(as: summary))",
        ])
        let loads = try source("Sources/Blackmail/Mail/PaneLoads.swift")
        XCTAssertTrue(loads.contains("attachments: row.attachments, arrived: row.arrived)"))
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
