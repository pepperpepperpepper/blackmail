import XCTest
@testable import Blackmail

/// Go to Date in a folder whose UIDs do not follow its dates (B-115), over
/// the shipping repository and client against the scripted server, which
/// searches SENTSINCE and SENTBEFORE by a letter's Date and SINCE and
/// BEFORE by when it arrived, each by the day in UTC, as Gmail counts them
/// (B-058).
///
/// The Inbox here is the size test's of 2026-10-23 made small: the
/// account's own four letters first, the lowest UIDs, dated 25 August, 10
/// September and twice 28 September 2026; then old mail copied in after
/// them, each letter arriving, as Gmail says, when its Date says, in the
/// order written, from 4 January 2012 to 14 August 2026. No mail on the weekend
/// of 15 and 16 March 2014. The same letters are in All Mail, in the same
/// order, above the account's own sent letters and drafts, dated July to
/// September 2026; and in Sent Mail two of his own copied in after those.
/// The iPad's clock reads 3 October 2026, so a letter must have arrived
/// before the 11th.
///
/// Before B-115 every jump below but the newest day's landed on the
/// account's first letter at the foot of the folder, "Showing August 25"
/// in the Inbox, as on the test iPad.
final class GoToDateOrderTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "GoToDateOrderTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer(inboxCount: 0)
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)

        let own = [("Own 25 Aug", "2026-08-25T14:00:00Z"),
                   ("Own 10 Sep", "2026-09-10T14:00:00Z"),
                   ("Own 28 Sep", "2026-09-28T14:00:00Z"),
                   ("Own 28 Sep later", "2026-09-28T18:00:00Z")]
        let copiedIn = [("4 Jan 2012", "2012-01-04T09:08:00Z"),
                        ("20 Feb 2012", "2012-02-20T10:00:00Z"),
                        ("8 Mar 2014", "2014-03-08T15:51:00Z"),
                        ("10 Mar 2014 first", "2014-03-10T07:43:00Z"),
                        ("10 Mar 2014 second", "2014-03-10T12:00:00Z"),
                        ("10 Mar 2014 last", "2014-03-10T22:14:00Z"),
                        ("11 Mar 2014", "2014-03-11T09:00:00Z"),
                        ("14 Mar 2014", "2014-03-14T16:00:00Z"),
                        ("17 Mar 2014 first", "2014-03-17T08:00:00Z"),
                        ("17 Mar 2014 second", "2014-03-17T15:00:00Z"),
                        ("18 Mar 2014", "2014-03-18T11:00:00Z"),
                        ("15 May 2019", "2019-05-15T13:00:00Z"),
                        ("14 Aug 2026 first", "2026-08-14T13:00:00Z"),
                        ("14 Aug 2026 last", "2026-08-14T21:00:00Z")]
        for (subject, iso) in own + copiedIn {
            server.deliver(letter(subject, at: iso), to: [Server.inbox, Server.allMail])
        }
        for (subject, iso) in [("Sent 10 Mar 2014", "2014-03-10T20:00:00Z"),
                               ("Sent 15 May 2019", "2019-05-15T18:00:00Z")] {
            server.deliver(letter(subject, at: iso), to: [Server.sent])
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

    /// A letter sent, and arrived, at `iso`.
    private func letter(_ subject: String, at iso: String) -> Server.Letter {
        Server.Letter(from: Server.carlo, to: [Server.owner], subject: subject,
                      date: instant(iso), text: "A few words.\r\n",
                      messageID: "<\(subject.replacingOccurrences(of: " ", with: "-"))@example.org>")
    }

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    /// What a jump came to: the subject it landed on and the day it says,
    /// or nil for nothing that recent; the dated SEARCHes it asked, in
    /// order; and every command from its SELECT on.
    private struct Jump {
        var landed: String?
        var day: String?
        var dated: [String]
        var steps: [String]
        var connections: Int
    }

    /// A jump to `ymd`, picked at noon in `zone`, on a repository of its
    /// own, its clock at noon UTC on 3 October 2026.
    private func jump(_ ymd: String, in mailbox: String = "inbox",
                      zone: String = "UTC") async throws -> Jump {
        let zoned = calendar(zone)
        let now = instant("2026-10-03T12:00:00Z")
        let repository = IMAPMailRepository(account: server.account, password: server.password,
                                            transport: server.transportFactory, recipients: book,
                                            now: { now }, calendar: zoned,
                                            shelf: keptShelf(for: server.account))
        let parts = ymd.split(separator: "-").map { Int($0)! }
        let picked = zoned.date(from: DateComponents(year: parts[0], month: parts[1],
                                                     day: parts[2], hour: 12))!
        server.clearLog()
        let window = try await repository.messages(around: picked, in: mailbox, limit: 10)
        let said = DateFormatter()
        said.locale = Locale(identifier: "en_US_POSIX")
        said.timeZone = zoned.timeZone
        said.dateFormat = "d MMM yyyy"
        let log = server.log
        let opened = log.firstIndex { $0.verb == "SELECT" } ?? log.endIndex
        return Jump(landed: window.map { $0.messages[$0.anchorIndex].subject },
                    day: window.map { said.string(from: $0.landedOn) },
                    dated: log.filter { $0.command.contains("SENTSINCE") }.map(\.command),
                    steps: log[opened...].map(\.verb),
                    connections: Set(log.map(\.connection)).count)
    }

    /// The SEARCHes after the SELECT, `dated` of them and the listing, then
    /// the window's FETCH: one hold, nothing between them.
    private func inOneHold(_ dated: Int) -> [String] {
        ["SELECT"] + Array(repeating: "UID SEARCH", count: dated + 1) + ["UID FETCH"]
    }

    /// A day with mail: its first letter, though four letters of the
    /// account's own, the lowest UIDs, are dated after it; one SEARCH, the
    /// day itself, with the arrival bounds of B-058. Before, the jump
    /// landed on "Own 25 Aug".
    func testADayWithMailLandsOnItsFirstLetterWithOneSearch() async throws {
        let jumped = try await jump("2014-03-10")
        XCTAssertEqual(jumped.landed, "10 Mar 2014 first")
        XCTAssertEqual(jumped.day, "10 Mar 2014")
        XCTAssertEqual(jumped.dated, ["UID SEARCH RETURN (MIN) SENTSINCE \"10-Mar-2014\" "
                                        + "SENTBEFORE \"11-Mar-2014\" SINCE \"03-Mar-2014\" "
                                        + "BEFORE \"11-Oct-2026\""])
        XCTAssertEqual(jumped.steps, inOneHold(1))
        XCTAssertEqual(jumped.connections, 1)
    }

    /// The same in New York, where the iPad is: the first letter of his
    /// 10th, at 3.43 am there, and the day said is his.
    func testADayWithMailLandsTheSameInNewYork() async throws {
        let jumped = try await jump("2014-03-10", zone: "America/New_York")
        XCTAssertEqual(jumped.landed, "10 Mar 2014 first")
        XCTAssertEqual(jumped.day, "10 Mar 2014")
        XCTAssertEqual(jumped.dated.count, 1)
    }

    /// A weekend with no mail: the first letter of the Monday after it, two
    /// spans wider than the Saturday, three SEARCHes, the day, two days and
    /// four days from it.
    func testAWeekendWithNoMailLandsOnTheMondayAfterIt() async throws {
        let jumped = try await jump("2014-03-15")
        XCTAssertEqual(jumped.landed, "17 Mar 2014 first")
        XCTAssertEqual(jumped.day, "17 Mar 2014")
        XCTAssertEqual(jumped.dated.map(sentBefore), ["16-Mar-2014", "17-Mar-2014", "19-Mar-2014"])
        XCTAssertTrue(jumped.dated.allSatisfy {
            $0.hasPrefix("UID SEARCH RETURN (MIN) SENTSINCE \"15-Mar-2014\" SENTBEFORE ")
                && $0.hasSuffix(" SINCE \"08-Mar-2014\" BEFORE \"11-Oct-2026\"")
        }, "\(jumped.dated)")
        XCTAssertEqual(jumped.steps, inOneHold(3))
    }

    /// A day before the oldest letter: the oldest letter, "4 January 2012",
    /// at the tenth span, 512 days, as on the test account; the nine before
    /// it found nothing.
    func testADayBeforeTheOldestLetterLandsOnTheOldest() async throws {
        let jumped = try await jump("2011-01-01")
        XCTAssertEqual(jumped.landed, "4 Jan 2012")
        XCTAssertEqual(jumped.day, "4 Jan 2012")
        XCTAssertEqual(jumped.dated.count, 10)
        XCTAssertEqual(jumped.dated.last.flatMap(sentBefore), "27-May-2012")
        XCTAssertEqual(jumped.steps, inOneHold(10))
    }

    /// Long before it, within the widest span: still the oldest, at the
    /// fourteenth span, 8,192 days.
    func testADayLongBeforeTheOldestLetterStillLandsOnTheOldest() async throws {
        let jumped = try await jump("1990-06-01")
        XCTAssertEqual(jumped.landed, "4 Jan 2012")
        XCTAssertEqual(jumped.dated.count, 14)
        XCTAssertEqual(jumped.dated.last.flatMap(sentBefore), "04-Nov-2012")
    }

    /// The top of the folder by UID, the newest of the mail copied in: its
    /// first letter of that day, one SEARCH. Before, "Own 25 Aug", at the
    /// foot.
    func testTheNewestDayOfTheMailCopiedInLandsOnIt() async throws {
        let jumped = try await jump("2026-08-14")
        XCTAssertEqual(jumped.landed, "14 Aug 2026 first")
        XCTAssertEqual(jumped.day, "14 Aug 2026")
        XCTAssertEqual(jumped.dated.count, 1)
    }

    /// The folder's newest day by date, the account's own two letters of
    /// it: the first of them, at the foot of the list where its UID is, one
    /// SEARCH.
    func testTheNewestDayLandsOnItsLetterWhereverItsUIDIs() async throws {
        let jumped = try await jump("2026-09-28")
        XCTAssertEqual(jumped.landed, "Own 28 Sep")
        XCTAssertEqual(jumped.day, "28 Sep 2026")
        XCTAssertEqual(jumped.dated.count, 1)
    }

    /// A day after the newest letter: nothing that recent, as before, after
    /// the spans of one, two, four and eight days, which reach no further
    /// than the 11th, and then the one SEARCH a jump always asked, every
    /// letter dated on or after the day.
    func testADayAfterTheNewestIsNothingThatRecentAsBefore() async throws {
        let jumped = try await jump("2026-10-01")
        XCTAssertNil(jumped.landed)
        XCTAssertEqual(jumped.dated.map(sentBefore), ["02-Oct-2026", "03-Oct-2026",
                                                      "05-Oct-2026", "09-Oct-2026", nil])
        XCTAssertEqual(jumped.dated.last, "UID SEARCH RETURN (MIN) SENTSINCE \"01-Oct-2026\" "
                                            + "SINCE \"24-Sep-2026\" BEFORE \"11-Oct-2026\"")
        // Nothing found, nothing fetched.
        XCTAssertEqual(jumped.steps, inOneHold(5).dropLast())
    }

    /// Bounded: a day more than 44 years before any mail asks fifteen spans,
    /// one day to 16,384, and then the SEARCH with no end, sixteen in all,
    /// and no more.
    func testNoJumpAsksMoreThanSixteenDatedSearches() async throws {
        let jumped = try await jump("1900-01-01")
        XCTAssertEqual(jumped.dated.count, IMAPDate.spanSearches + 1)
        XCTAssertEqual(jumped.dated.count, 16)
        XCTAssertEqual(jumped.dated.dropLast().last.flatMap(sentBefore), "10-Nov-1944")
        XCTAssertEqual(jumped.dated.last, "UID SEARCH RETURN (MIN) SENTSINCE \"01-Jan-1900\" "
                                            + "SINCE \"25-Dec-1899\" BEFORE \"11-Oct-2026\"")
        XCTAssertEqual(jumped.steps, inOneHold(16))
    }

    /// Sent Mail, his own letters copied in after the account's: the day's
    /// letter, one SEARCH, where before the jump landed at the foot on the
    /// account's "Re: the tickets", dated 11 July 2026, as on the test
    /// iPad on its own sent letter of September.
    func testSentMailLandsOnTheDaysLetter() async throws {
        let jumped = try await jump("2019-05-15", in: Server.sent)
        XCTAssertEqual(jumped.landed, "Sent 15 May 2019")
        XCTAssertEqual(jumped.day, "15 May 2019")
        XCTAssertEqual(jumped.dated.count, 1)
        let before = try await jump("2014-03-10", in: Server.sent)
        XCTAssertEqual(before.landed, "Sent 10 Mar 2014")
    }

    /// All Mailboxes jumps in All Mail, where the same letters are in the
    /// same order, above the account's own: the same landings and the same
    /// SEARCHes.
    func testAllMailLandsAsTheInboxDoes() async throws {
        for day in ["2014-03-10", "2014-03-15", "2011-01-01", "2026-08-14", "2026-10-01"] {
            let inbox = try await jump(day)
            let allMail = try await jump(day, in: Server.allMail)
            XCTAssertEqual(allMail.landed, inbox.landed, day)
            XCTAssertEqual(allMail.day, inbox.day, day)
            XCTAssertEqual(allMail.dated, inbox.dated, day)
        }
    }

    /// Without ESEARCH each SEARCH is a plain one, and the jumps land as
    /// with it, after as many.
    func testWithoutESEARCHTheJumpsLandTheSame() async throws {
        let days = ["2014-03-10", "2014-03-15", "2011-01-01", "2026-08-14", "2026-10-01"]
        var withIt: [Jump] = []
        for day in days { withIt.append(try await jump(day)) }
        server.withheldCapabilities = ["ESEARCH"]
        for (day, with) in zip(days, withIt) {
            let without = try await jump(day)
            XCTAssertEqual(without.landed, with.landed, day)
            XCTAssertEqual(without.dated, with.dated.map {
                $0.replacingOccurrences(of: "RETURN (MIN) ", with: "")
            }, day)
        }
    }

    /// The `SENTBEFORE` date of a dated SEARCH, nil for one with none.
    private func sentBefore(_ command: String) -> String? {
        guard let range = command.range(of: "SENTBEFORE \"") else { return nil }
        let rest = command[range.upperBound...]
        return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
    }
}
