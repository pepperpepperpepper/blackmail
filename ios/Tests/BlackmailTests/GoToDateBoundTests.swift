import XCTest
@testable import Blackmail

/// Go to Date bounded by when a letter arrived as well as by its Date
/// (B-058), over the shipping repository and client against the scripted
/// server, which searches SENTSINCE by a letter's Date and SINCE by its
/// INTERNALDATE, as RFC 3501 has it (on Gmail, see B-058).
///
/// The Inbox here holds a letter copied in first, with an arrival of 2037
/// as well as a Date of 2037, so the lowest UID; a letter that arrived in
/// 2014 dated 2037; then two letters a year from 2015 to 2020, each
/// arriving the moment it was sent; one delayed three days on its way; one
/// from a sender whose clock ran two days fast; four, two either side of
/// midnight UTC on 20 September 2019, which is 8 pm the day before in New
/// York and 9 am in Tokyo; and one at 10 pm on the 20th in New York. The
/// iPad's clock reads 3 October 2026.
final class GoToDateBoundTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "GoToDateBoundTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer(inboxCount: 0)
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)

        // Copied in before everything else, its arrival set from its Date.
        server.deliver(letter("Copied in wrong", sent: "2037-01-01", arrived: "2037-01-01"),
                       to: [Server.inbox, Server.allMail])
        var letters: [Server.Letter] = [
            letter("Dated wrong", sent: "2037-01-01", arrived: "2014-03-01"),
            letter("Delayed", sent: "2019-06-19", arrived: "2019-06-22"),
            letter("Clock fast", sent: "2019-08-03", arrived: "2019-08-01"),
            letter("19th 16:00 UTC", at: "2019-09-19T16:00:00Z"),
            letter("19th 18:00 UTC", at: "2019-09-19T18:00:00Z"),
            letter("20th 01:30 UTC", at: "2019-09-20T01:30:00Z"),
            letter("20th 12:30 UTC", at: "2019-09-20T12:30:00Z"),
            letter("21st 02:00 UTC", at: "2019-09-21T02:00:00Z"),
        ]
        for year in 2015...2020 {
            letters.append(letter("\(year) winter", sent: "\(year)-01-01"))
            letters.append(letter("\(year) summer", sent: "\(year)-07-01"))
        }
        // In the order Gmail took them, so UIDs rise with arrival.
        for letter in letters.sorted(by: { $0.arrival < $1.arrival }) {
            server.deliver(letter, to: [Server.inbox, Server.allMail])
        }
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        server = nil
        book = nil
        super.tearDown()
    }

    /// Noon UTC on `ymd`: when a letter here was sent, or arrived.
    private func day(_ ymd: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: "\(ymd)T12:00:00Z")!
    }

    /// Noon on `ymd` in the calendar of the machine the tests run on, as
    /// the picker hands the repository a day in the iPad's: that day
    /// whatever the machine's zone.
    private func picked(_ ymd: String) -> Date {
        let parts = ymd.split(separator: "-").map { Int($0)! }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1],
                                                          day: parts[2], hour: 12))!
    }

    private func letter(_ subject: String, sent: String, arrived: String? = nil) -> Server.Letter {
        letter(subject, date: day(sent), arrived: arrived.map(day))
    }

    /// A letter sent and arrived at `iso`, to the minute.
    private func letter(_ subject: String, at iso: String) -> Server.Letter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return letter(subject, date: f.date(from: iso)!, arrived: nil)
    }

    private func letter(_ subject: String, date: Date, arrived: Date?) -> Server.Letter {
        let id = subject.replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ":", with: "")
        return Server.Letter(from: Server.carlo, to: [Server.owner], subject: subject,
                             date: date, text: "A few words.\r\n",
                             messageID: "<\(id)@example.org>", arrived: arrived)
    }

    /// The repository, its clock at noon UTC on 3 October 2026, counting
    /// days in `calendar`: the test machine's unless given.
    private func makeRepository(calendar: Calendar = .current) -> IMAPMailRepository {
        let now = day("2026-10-03")
        return IMAPMailRepository(account: server.account, password: server.password,
                                  transport: server.transportFactory, recipients: book,
                                  now: { now }, calendar: calendar,
                                  shelf: keptShelf(for: server.account))
    }

    /// The subject of the row just below where the jump landed, if any.
    private func below(_ window: MessageWindow) -> String? {
        let next = window.anchorIndex + 1
        return window.messages.indices.contains(next) ? window.messages[next].subject : nil
    }

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    /// Where a jump to `ymd` lands: the subject of the row it scrolls to.
    private func landing(_ repository: IMAPMailRepository, _ ymd: String) async throws -> String? {
        let window = try await repository.messages(around: picked(ymd), in: "inbox", limit: 10)
        return window.map { $0.messages[$0.anchorIndex].subject }
    }

    /// Neither the letter dated 2037 that arrived in 2014, nor the one
    /// copied in saying it arrived in 2037, captures a jump: each lands on
    /// the first letter on or after the day asked for, as it would with
    /// them gone. Before the bound every jump below landed on one of them.
    func testALetterDatedWrongIntoTheFutureCapturesNoJump() async throws {
        let repository = makeRepository()
        let first = try await landing(repository, "2015-01-01")
        XCTAssertEqual(first, "2015 winter")
        let middle = try await landing(repository, "2018-03-15")
        XCTAssertEqual(middle, "2018 summer")
        let last = try await landing(repository, "2020-07-01")
        XCTAssertEqual(last, "2020 summer")
    }

    /// After the newest letter rightly dated, and before 2037, there is
    /// nothing that recent: not the letter dated wrong, which arrived years
    /// before.
    func testAfterTheNewestLetterThereIsNothingThatRecent() async throws {
        let repository = makeRepository()
        let window = try await repository.messages(around: picked("2021-01-01"), in: "inbox",
                                                   limit: 10)
        XCTAssertNil(window)
    }

    /// A letter delayed on its way is found by its Date however late it
    /// arrived, and one from a clock a few days fast by its Date as well:
    /// it arrived within the week before.
    func testLettersDelayedOrFromAFastClockAreStillFound() async throws {
        let repository = makeRepository()
        let delayed = try await landing(repository, "2019-06-19")
        XCTAssertEqual(delayed, "Delayed")
        let fast = try await landing(repository, "2019-08-02")
        XCTAssertEqual(fast, "Clock fast")
    }

    /// The letters dated wrong are still in the Inbox, at the foot of the
    /// list where they arrived; the bound hides them from jumps, nothing
    /// more.
    func testTheLettersDatedWrongAreStillListed() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(rows.suffix(2).map(\.subject), ["Dated wrong", "Copied in wrong"])
        XCTAssertEqual(rows.count, 21)
    }

    // MARK: - His day, not Gmail's

    /// In New York, the 20th asked for: the SEARCH, by the day in UTC as
    /// Gmail's is, matches the letter of 9.30 pm on the 19th, and the jump
    /// lands on the first letter of his 20th instead, and says that day.
    func testWestOfGreenwichTheJumpLandsOnHisDayNotTheEveningBefore() async throws {
        let newYork = calendar("America/New_York")
        let repository = makeRepository(calendar: newYork)
        let picked = newYork.date(from: DateComponents(year: 2019, month: 9, day: 20, hour: 12))!
        let found = try await repository.messages(around: picked, in: "inbox", limit: 20)
        let window = try XCTUnwrap(found)
        XCTAssertEqual(window.messages[window.anchorIndex].subject, "20th 12:30 UTC")
        XCTAssertEqual(newYork.component(.day, from: window.landedOn), 20)
        // The evening before is still there, just below it.
        XCTAssertEqual(below(window), "20th 01:30 UTC")
    }

    /// In Tokyo, the 20th asked for: the SEARCH misses his first hours of
    /// it, before 9 am, which were the 19th in UTC, and the jump lands on
    /// the first letter of them.
    func testEastOfGreenwichTheJumpLandsOnTheFirstHoursOfHisDay() async throws {
        let tokyo = calendar("Asia/Tokyo")
        let repository = makeRepository(calendar: tokyo)
        let picked = tokyo.date(from: DateComponents(year: 2019, month: 9, day: 20, hour: 12))!
        let found = try await repository.messages(around: picked, in: "inbox", limit: 20)
        let window = try XCTUnwrap(found)
        XCTAssertEqual(window.messages[window.anchorIndex].subject, "19th 16:00 UTC")
        XCTAssertEqual(tokyo.component(.day, from: window.landedOn), 20)
        XCTAssertEqual(below(window), "Clock fast")
    }

    /// On the wire, one SEARCH carries all three: the Date on or after the
    /// day, the arrival on or after a week before it, and no later than a
    /// week after today, in his calendar, here New York's.
    func testOneSearchCarriesAllThreeDates() async throws {
        let newYork = calendar("America/New_York")
        let repository = makeRepository(calendar: newYork)
        let picked = newYork.date(from: DateComponents(year: 2019, month: 6, day: 19, hour: 12))!
        _ = try await repository.messages(around: picked, in: "inbox", limit: 10)
        let searches = server.log.filter { $0.verb == "UID SEARCH" }.map(\.command)
        let dated = searches.filter { $0.contains("SENTSINCE") }
        let only = try XCTUnwrap(dated.first)
        XCTAssertEqual(dated.count, 1)
        XCTAssertTrue(only.hasSuffix(
            "SENTSINCE \"19-Jun-2019\" SINCE \"12-Jun-2019\" BEFORE \"11-Oct-2026\""), only)
    }

    /// The SEARCH asks for his date, in his calendar, whatever day it is in
    /// UTC: 8 am on the 20th in Tokyo is the 19th in UTC.
    func testTheSearchAsksForHisDateInHisCalendar() async throws {
        let tokyo = calendar("Asia/Tokyo")
        let repository = makeRepository(calendar: tokyo)
        let picked = tokyo.date(from: DateComponents(year: 2019, month: 6, day: 20, hour: 8))!
        _ = try await repository.messages(around: picked, in: "inbox", limit: 10)
        let dated = server.log.filter { $0.verb == "UID SEARCH" }.map(\.command)
            .filter { $0.contains("SENTSINCE") }
        let only = try XCTUnwrap(dated.first)
        XCTAssertTrue(only.hasSuffix(
            "SENTSINCE \"20-Jun-2019\" SINCE \"13-Jun-2019\" BEFORE \"11-Oct-2026\""), only)
    }

    /// The 21st asked for in New York, a day with no mail of its own: the
    /// SEARCH lands on 10 pm on the 20th, and the jump goes on up to the
    /// next letter, in January, as it would to the next day's first; the
    /// week ahead is counted from today, not from the day asked for.
    func testADayWithNoMailOfItsOwnLandsOnTheNextLetterNotTheEveningBefore() async throws {
        let newYork = calendar("America/New_York")
        let repository = makeRepository(calendar: newYork)
        let picked = newYork.date(from: DateComponents(year: 2019, month: 9, day: 21, hour: 12))!
        let found = try await repository.messages(around: picked, in: "inbox", limit: 20)
        let window = try XCTUnwrap(found)
        XCTAssertEqual(window.messages[window.anchorIndex].subject, "2020 winter")
    }

    /// A folder whose newest letter came in at 9.30 pm yesterday, and today
    /// asked for in New York: Gmail's day matches that letter, but nothing
    /// is on or after his today, so there is nothing that recent, as the
    /// app says, rather than "Showing" yesterday.
    func testTodayWithOnlyLastEveningsMailIsNothingThatRecent() async throws {
        server = ScriptedIMAPServer(inboxCount: 0)
        server.deliver(letter("Morning", at: "2026-10-02T12:30:00Z"), to: [Server.inbox])
        server.deliver(letter("Evening", at: "2026-10-03T01:30:00Z"), to: [Server.inbox])
        let newYork = calendar("America/New_York")
        let repository = makeRepository(calendar: newYork)
        let today = newYork.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 10))!
        let window = try await repository.messages(around: today, in: "inbox", limit: 20)
        XCTAssertNil(window)
    }

    /// West of Greenwich the jump never moves down onto a letter below the
    /// SEARCH's, which it left out: here one that arrived on the 5th dated
    /// the 25th, just below the first letter of the 20th.
    func testWestOfGreenwichALetterLeftOutBelowIsNeverLandedOn() async throws {
        server = ScriptedIMAPServer(inboxCount: 0)
        for letter in [letter("Early", sent: "2019-09-01"),
                       letter("Wrong", sent: "2019-09-25", arrived: "2019-09-05"),
                       letter("First of the 20th", at: "2019-09-20T12:30:00Z"),
                       letter("Later", sent: "2019-10-01")] {
            server.deliver(letter, to: [Server.inbox])
        }
        let newYork = calendar("America/New_York")
        let repository = makeRepository(calendar: newYork)
        let picked = newYork.date(from: DateComponents(year: 2019, month: 9, day: 20, hour: 12))!
        let found = try await repository.messages(around: picked, in: "inbox", limit: 20)
        let window = try XCTUnwrap(found)
        XCTAssertEqual(window.messages[window.anchorIndex].subject, "First of the 20th")
        XCTAssertEqual(newYork.component(.day, from: window.landedOn), 20)
    }
}
