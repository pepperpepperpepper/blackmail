import XCTest
@testable import Blackmail

/// Go to Date bounded by when a letter arrived as well as by its Date
/// (B-058), over the shipping repository and client against the scripted
/// server, which searches SENTSINCE by a letter's Date and SINCE by its
/// INTERNALDATE, as RFC 3501 has it (on Gmail, see B-058).
///
/// The Inbox here holds a letter that arrived in 2014 dated 2037, the first
/// to arrive and so the lowest UID, and then two letters a year from 2015
/// to 2020, each arriving the moment it was sent; one delayed three days on
/// its way; and one from a sender whose clock ran two days fast.
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

        var letters: [Server.Letter] = [
            letter("Dated wrong", sent: "2037-01-01", arrived: "2014-03-01"),
            letter("Delayed", sent: "2019-06-19", arrived: "2019-06-22"),
            letter("Clock fast", sent: "2019-08-03", arrived: "2019-08-01"),
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
        let id = subject.replacingOccurrences(of: " ", with: "-")
        return Server.Letter(from: Server.carlo, to: [Server.owner], subject: subject,
                             date: day(sent), text: "A few words.\r\n",
                             messageID: "<\(id)@example.org>", arrived: arrived.map(day))
    }

    private func makeRepository() -> IMAPMailRepository {
        IMAPMailRepository(account: server.account, password: server.password,
                           transport: server.transportFactory, recipients: book,
                           shelf: keptShelf(for: server.account))
    }

    /// Where a jump to `ymd` lands: the subject of the row it scrolls to.
    private func landing(_ repository: IMAPMailRepository, _ ymd: String) async throws -> String? {
        let window = try await repository.messages(around: picked(ymd), in: "inbox", limit: 10)
        return window.map { $0.messages[$0.anchorIndex].subject }
    }

    /// The letter dated 2037 that arrived in 2014 captures no jump: each
    /// lands on the first letter on or after the day asked for, as it
    /// would with that letter gone. Before the bound every jump below landed on it.
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

    /// The letter dated wrong is still in the Inbox, at the foot of the
    /// list where it arrived; the bound hides it from jumps, nothing more.
    func testTheLetterDatedWrongIsStillListed() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(rows.last?.subject, "Dated wrong")
        XCTAssertEqual(rows.count, 15)
    }

    /// On the wire, one SEARCH carries both: the Date on or after the day
    /// and the arrival on or after a week before it, in his calendar.
    func testOneSearchCarriesBothDates() async throws {
        let repository = makeRepository()
        _ = try await repository.messages(around: picked("2019-06-19"), in: "inbox", limit: 10)
        let searches = server.log.filter { $0.verb == "UID SEARCH" }.map(\.command)
        let dated = searches.filter { $0.contains("SENTSINCE") }
        let only = try XCTUnwrap(dated.first)
        XCTAssertEqual(dated.count, 1)
        XCTAssertTrue(only.hasSuffix("SENTSINCE \"19-Jun-2019\" SINCE \"12-Jun-2019\""), only)
    }
}
