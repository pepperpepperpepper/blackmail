import XCTest
@testable import Blackmail

/// Go to Date by when the letters arrived (B-178), the order the list goes
/// in and the date its rows show, over the shipping repository and client
/// against the scripted server, which answers SINCE, BEFORE and the SENT*
/// keys by when a letter arrived, as Gmail does.
///
/// Found on the test iPad on 2026-10-28 (round r6-j-act): in Notes, with a
/// letter dated 1 March 2024 that arrived that morning at the top and one
/// dated that morning that arrived on 8 October, Go to Date to the 28th,
/// and to the 8th, said "No mail on or after" and did not move. Gmail's
/// `SENTSINCE` had found each letter by its arrival; the jump threw it
/// away for its Date.
///
/// The folder here is a label's: its UIDs go by when each letter was put
/// in it, not by when it arrived. Thirty-four letters of its own of 2025
/// and 2026,
/// then "Early UID", which arrived on 10 October, "came old", dated the
/// 28th at 3 am, which arrived on the 8th, "labelled late", which arrived
/// on the 9th, and "dated old", dated 1 March 2024, which arrived on the
/// 28th at 4.12 am. The iPad is in New York, its clock 9.30 am on 28
/// October 2026.
final class GoToDateByArrivalTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "GoToDateByArrivalTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer(inboxCount: 0)
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        // Thirty of the label's own first, a day apart from 1 January 2025,
        // so a jump's window has pages above and below it.
        for i in 0..<30 {
            let sent = instant("2025-01-01T14:00:00Z").addingTimeInterval(Double(i) * 86_400)
            server.deliver(Server.Letter(from: Server.carlo, to: [Server.owner], subject: "Own \(i)",
                                         date: sent, text: "A few words.\r\n", flags: ["\\Seen"],
                                         messageID: "<own-\(i)@example.org>"),
                           to: [Server.inbox])
        }
        for (subject, sent, arrived) in [
            ("Own May 2025", "2025-05-09T14:00:00Z", nil),
            ("Own July 2025", "2025-07-17T14:00:00Z", nil),
            ("Own April 2026", "2026-04-30T14:00:00Z", nil),
            ("Own June 2026", "2026-06-11T14:00:00Z", nil),
            ("Early UID", "2026-10-10T15:00:00Z", nil),
            ("came old", "2026-10-28T07:00:00Z", "2026-10-08T16:00:00Z"),
            ("labelled late", "2026-10-09T15:00:00Z", nil),
            ("dated old", "2024-03-01T17:00:00Z", "2026-10-28T08:12:00Z"),
        ] as [(String, String, String?)] {
            server.deliver(letter(subject, sent: sent, arrived: arrived), to: [Server.inbox])
        }
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        server = nil
        book = nil
        super.tearDown()
    }

    private func instant(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    private func letter(_ subject: String, sent: String, arrived: String?) -> Server.Letter {
        Server.Letter(from: Server.carlo, to: [Server.owner], subject: subject,
                      date: instant(sent), text: "A few words.\r\n", flags: ["\\Seen"],
                      messageID: "<\(subject.replacingOccurrences(of: " ", with: "-"))@example.org>",
                      arrived: arrived.map(instant))
    }

    private static let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func makeRepository() -> IMAPMailRepository {
        let now = instant("2026-10-28T13:30:00Z")
        return IMAPMailRepository(account: server.account, password: server.password,
                                  transport: server.transportFactory, recipients: book,
                                  now: { now }, calendar: Self.newYork,
                                  shelf: keptShelf(for: server.account))
    }

    /// Noon on `ymd` in New York, as the picker hands the day.
    private func picked(_ ymd: String) -> Date {
        let parts = ymd.split(separator: "-").map { Int($0)! }
        return Self.newYork.date(from: DateComponents(year: parts[0], month: parts[1],
                                                      day: parts[2], hour: 12))!
    }

    private func day(_ date: Date) -> Int { Self.newYork.component(.day, from: date) }

    /// Today: the letter that arrived this morning, dated 2024, at the top,
    /// "Showing October 28"; the list opens on its row, which shows its
    /// arrival. It said "No mail on or after October 28" and did not move.
    func testTodayLandsOnTheLetterThatArrivedTodayWhateverItsDate() async throws {
        let found = try await makeRepository().messages(around: picked("2026-10-28"), in: "inbox",
                                                        limit: 10)
        let window = try XCTUnwrap(found, "No mail on or after October 28")
        let landed = window.messages[window.anchorIndex]
        XCTAssertEqual(landed.subject, "dated old")
        XCTAssertEqual(window.anchorIndex, 0)
        XCTAssertTrue(window.reachedNewest)
        XCTAssertEqual(window.landedOn, instant("2026-10-28T08:12:00Z"))
        let rows = MessageThread.rows(for: window.messages, grouped: true)
        let opened = try XCTUnwrap(ListOpening.dayRow(in: rows, for: window))
        XCTAssertEqual(rows[opened.row].subject, "dated old")
        XCTAssertEqual(day(opened.shown), 28)
        XCTAssertEqual(rows[opened.row].displayRow().listDate, opened.shown)
    }

    /// The day a letter arrived lands on it though its Date is another
    /// day: "came old" on the 8th, which said "No mail on or after October
    /// 8". The day its Date says lands on the first letter to arrive on or
    /// after it, not on it.
    func testADayLandsOnTheLettersThatArrivedOnItNotThoseDatedIt() async throws {
        let repository = makeRepository()
        let eighth = try await repository.messages(around: picked("2026-10-08"), in: "inbox", limit: 10)
        let came = try XCTUnwrap(eighth, "No mail on or after October 8")
        XCTAssertEqual(came.messages[came.anchorIndex].subject, "came old")
        XCTAssertEqual(day(came.landedOn), 8)
        // "Showing October 8": the row opened on goes by its arrival too.
        let rows = MessageThread.rows(for: came.messages, grouped: true)
        let opened = try XCTUnwrap(ListOpening.dayRow(in: rows, for: came))
        XCTAssertEqual(rows[opened.row].subject, "came old")
        XCTAssertEqual(day(opened.shown), 8)

        let march = try await repository.messages(around: picked("2024-03-01"), in: "inbox", limit: 10)
        let dated = try XCTUnwrap(march)
        XCTAssertEqual(dated.messages[dated.anchorIndex].subject, "Own 0")
        XCTAssertEqual(dated.landedOn, instant("2025-01-01T14:00:00Z"))
    }

    /// A day with no mail: the first letter to arrive after it, "came old"
    /// on the 8th, though the span that finds it has "Early UID", which
    /// arrived on the 10th, as its lowest UID; the landing goes down from
    /// it past "labelled late" of the 9th. Then a page above and a page
    /// below, every letter once, in the order they arrived.
    func testADayWithNoMailLandsOnTheFirstToArriveAfterIt() async throws {
        let repository = makeRepository()
        let found = try await repository.messages(around: picked("2026-10-03"), in: "inbox", limit: 5)
        let window = try XCTUnwrap(found)
        XCTAssertEqual(window.messages[window.anchorIndex].subject, "came old")
        XCTAssertEqual(day(window.landedOn), 8)
        let above = try await repository.listMessages(in: "inbox", afterUID: window.messages.first!.id,
                                                      limit: 50)
        let below = try await repository.listMessages(in: "inbox", beforeUID: window.messages.last!.id,
                                                      limit: 50)
        XCTAssertFalse(below.isEmpty)
        let all = above + window.messages + below
        XCTAssertEqual(Array(all.prefix(8).map(\.subject)),
                       ["dated old", "Early UID", "labelled late", "came old",
                        "Own June 2026", "Own April 2026", "Own July 2025", "Own May 2025"])
        XCTAssertEqual(all.count, 38)
        XCTAssertEqual(Set(all.map(\.id)).count, 38)
        XCTAssertEqual(all.map(\.listDate), all.map(\.listDate).sorted(by: >))
    }

    /// On the wire, his day by arrival: `SINCE` and `BEFORE`, Gmail's 28th
    /// and 29th, which hold his 28th, and nothing by the Date; one SEARCH
    /// and one FETCH of its letter's dates.
    func testHisDayIsAskedByArrival() async throws {
        _ = try await makeRepository().messages(around: picked("2026-10-28"), in: "inbox", limit: 10)
        let searches = server.log.filter { $0.verb == "UID SEARCH" }.map(\.command)
        XCTAssertEqual(searches, ["UID SEARCH SINCE \"28-Oct-2026\" BEFORE \"30-Oct-2026\"",
                                  "UID SEARCH ALL"])
        XCTAssertEqual(server.log.filter { $0.command.hasSuffix("(UID INTERNALDATE ENVELOPE)") }.count, 1)
    }
}
