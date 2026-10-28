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
/// in the Inbox, as on the test iPad. The last five tests have folders of
/// their own, with a letter of the evening before his day, as Gmail counts
/// it from midnight UTC, or of his next morning, at a lower UID.
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
    /// order; the FETCHes of his day's letters' dates; every command from
    /// its SELECT on; and how many connections it used.
    private struct Jump {
        var landed: String?
        var day: String?
        var dated: [String]
        var dateFetches: [String]
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
                    dateFetches: log.filter { $0.command.hasSuffix(Self.dates) }.map(\.command),
                    steps: log[opened...].map(\.verb),
                    connections: Set(log.map(\.connection)).count)
    }

    /// What the FETCH of his day's letters asks for (B-115).
    private static let dates = "(UID INTERNALDATE ENVELOPE)"

    /// Every command after the SELECT: his day's SEARCH, the FETCH of its
    /// letters' dates if it matched any, the rest of the `dated` SEARCHes
    /// and the listing, then the window's FETCH if it landed: one hold,
    /// nothing between them.
    private func inOneHold(_ dated: Int, datesFetched: Bool, landed: Bool = true) -> [String] {
        // Landed, the folder's letters' arrivals for the list's order
        // (B-178), then the window.
        ["SELECT", "UID SEARCH"] + (datesFetched ? ["UID FETCH"] : [])
            + Array(repeating: "UID SEARCH", count: dated)
            + (landed ? ["UID FETCH", "UID FETCH"] : [])
    }

    /// A jump's commands, as `inOneHold`, on one connection.
    private func assertOneHold(_ jumped: Jump, datesFetched: Bool, landed: Bool = true,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(jumped.steps, inOneHold(jumped.dated.count, datesFetched: datesFetched,
                                               landed: landed), file: file, line: line)
        XCTAssertEqual(jumped.dateFetches.count, datesFetched ? 1 : 0, file: file, line: line)
        XCTAssertEqual(jumped.connections, 1, file: file, line: line)
    }

    /// A day with mail: its first letter, though four letters of the
    /// account's own, the lowest UIDs, are dated after it; one SEARCH, the
    /// day itself, with the arrival bounds of B-058, asked whole, and one
    /// FETCH of its three letters' dates. Before, the jump landed on "Own
    /// 25 Aug".
    func testADayWithMailLandsOnItsFirstLetterWithOneSearch() async throws {
        let jumped = try await jump("2014-03-10")
        XCTAssertEqual(jumped.landed, "10 Mar 2014 first")
        XCTAssertEqual(jumped.day, "10 Mar 2014")
        XCTAssertEqual(jumped.dated, ["UID SEARCH SENTSINCE \"10-Mar-2014\" "
                                        + "SENTBEFORE \"11-Mar-2014\" SINCE \"03-Mar-2014\" "
                                        + "BEFORE \"11-Oct-2026\""])
        XCTAssertEqual(jumped.dateFetches, ["UID FETCH 1007:1009 \(Self.dates)"])
        assertOneHold(jumped, datesFetched: true)
    }

    /// The same in New York, where the iPad is: Gmail's 10th and 11th, which
    /// hold his 10th, and of their letters the first of his 10th, at 3.43
    /// am there, not the 11th's at 5 am; the day said is his.
    func testADayWithMailLandsTheSameInNewYork() async throws {
        let jumped = try await jump("2014-03-10", zone: "America/New_York")
        XCTAssertEqual(jumped.landed, "10 Mar 2014 first")
        XCTAssertEqual(jumped.day, "10 Mar 2014")
        XCTAssertEqual(jumped.dated.count, 1)
        XCTAssertTrue(jumped.dated.first?.hasPrefix(
            "UID SEARCH SENTSINCE \"10-Mar-2014\" SENTBEFORE \"12-Mar-2014\" ") == true,
                      "\(jumped.dated)")
        XCTAssertEqual(jumped.dateFetches, ["UID FETCH 1007:1010 \(Self.dates)"])
        assertOneHold(jumped, datesFetched: true)
    }

    /// A weekend with no mail: the first letter of the Monday after it,
    /// three SEARCHes, the Saturday, then the two days and the four days
    /// from it, each from the Sunday; no dates fetched, the Saturday having
    /// no letters.
    func testAWeekendWithNoMailLandsOnTheMondayAfterIt() async throws {
        let jumped = try await jump("2014-03-15")
        XCTAssertEqual(jumped.landed, "17 Mar 2014 first")
        XCTAssertEqual(jumped.day, "17 Mar 2014")
        XCTAssertEqual(jumped.dated.map(sentBefore), ["16-Mar-2014", "17-Mar-2014", "19-Mar-2014"])
        XCTAssertTrue(jumped.dated.first?.hasPrefix("UID SEARCH SENTSINCE \"15-Mar-2014\" ") == true,
                      "\(jumped.dated)")
        XCTAssertTrue(jumped.dated.dropFirst().allSatisfy {
            $0.hasPrefix("UID SEARCH RETURN (MIN) SENTSINCE \"16-Mar-2014\" SENTBEFORE ")
        }, "\(jumped.dated)")
        XCTAssertTrue(jumped.dated.allSatisfy {
            $0.hasSuffix(" SINCE \"08-Mar-2014\" BEFORE \"11-Oct-2026\"")
        }, "\(jumped.dated)")
        assertOneHold(jumped, datesFetched: false)
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
        assertOneHold(jumped, datesFetched: false)
    }

    /// Long before it, within the widest span: still the oldest, at the
    /// fourteenth span, 8,192 days.
    func testADayLongBeforeTheOldestLetterStillLandsOnTheOldest() async throws {
        let jumped = try await jump("1990-06-01")
        XCTAssertEqual(jumped.landed, "4 Jan 2012")
        XCTAssertEqual(jumped.dated.count, 14)
        XCTAssertEqual(jumped.dated.last.flatMap(sentBefore), "04-Nov-2012")
        assertOneHold(jumped, datesFetched: false)
    }

    /// The top of the folder by UID, the newest of the mail copied in: its
    /// first letter of that day, one SEARCH. Before, "Own 25 Aug", at the
    /// foot.
    func testTheNewestDayOfTheMailCopiedInLandsOnIt() async throws {
        let jumped = try await jump("2026-08-14")
        XCTAssertEqual(jumped.landed, "14 Aug 2026 first")
        XCTAssertEqual(jumped.day, "14 Aug 2026")
        XCTAssertEqual(jumped.dated.count, 1)
        assertOneHold(jumped, datesFetched: true)
    }

    /// The folder's newest day by date, the account's own two letters of
    /// it: the first of them, at the foot of the list where its UID is, one
    /// SEARCH.
    func testTheNewestDayLandsOnItsLetterWhereverItsUIDIs() async throws {
        let jumped = try await jump("2026-09-28")
        XCTAssertEqual(jumped.landed, "Own 28 Sep")
        XCTAssertEqual(jumped.day, "28 Sep 2026")
        XCTAssertEqual(jumped.dated.count, 1)
        assertOneHold(jumped, datesFetched: true)
    }

    /// A day after the newest letter: nothing that recent, as before, after
    /// the day and the spans of two, four and eight days, which reach no
    /// further than the 11th, and then the SEARCH with no end, every letter
    /// dated after the day.
    func testADayAfterTheNewestIsNothingThatRecentAsBefore() async throws {
        let jumped = try await jump("2026-10-01")
        XCTAssertNil(jumped.landed)
        XCTAssertEqual(jumped.dated.map(sentBefore), ["02-Oct-2026", "03-Oct-2026",
                                                      "05-Oct-2026", "09-Oct-2026", nil])
        XCTAssertEqual(jumped.dated.last, "UID SEARCH RETURN (MIN) SENTSINCE \"02-Oct-2026\" "
                                            + "SINCE \"24-Sep-2026\" BEFORE \"11-Oct-2026\"")
        // Nothing found, nothing fetched.
        assertOneHold(jumped, datesFetched: false, landed: false)
    }

    /// Bounded: a day more than 44 years before any mail asks the day and
    /// fourteen spans, two days to 16,384, and then the SEARCH with no end,
    /// sixteen in all, and no more.
    func testNoJumpAsksMoreThanSixteenDatedSearches() async throws {
        let jumped = try await jump("1900-01-01")
        XCTAssertEqual(jumped.dated.count, IMAPDate.spanSearches + 1)
        XCTAssertEqual(jumped.dated.count, 16)
        XCTAssertEqual(jumped.dated.dropLast().last.flatMap(sentBefore), "10-Nov-1944")
        XCTAssertEqual(jumped.dated.last, "UID SEARCH RETURN (MIN) SENTSINCE \"02-Jan-1900\" "
                                            + "SINCE \"25-Dec-1899\" BEFORE \"11-Oct-2026\"")
        assertOneHold(jumped, datesFetched: false)
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
        assertOneHold(jumped, datesFetched: true)
        let before = try await jump("2014-03-10", in: Server.sent)
        XCTAssertEqual(before.landed, "Sent 10 Mar 2014")
        assertOneHold(before, datesFetched: true)
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
            XCTAssertEqual(allMail.steps, inbox.steps, day)
            XCTAssertEqual(allMail.connections, 1, day)
        }
    }

    /// Without ESEARCH each SEARCH is a plain one, and the jumps land as
    /// with it, after as many, in the same hold.
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
            XCTAssertEqual(without.steps, with.steps, day)
            XCTAssertEqual(without.connections, 1, day)
        }
    }

    // MARK: - His evening before and his next morning (B-115)

    /// A folder of its own, these letters in it in this order, each sent,
    /// and arrived, at its time.
    private func folder(_ letters: [(String, String)]) {
        server = ScriptedIMAPServer(inboxCount: 0)
        for (subject, iso) in letters {
            server.deliver(letter(subject, at: iso), to: [Server.inbox])
        }
    }

    /// In New York a day with mail, a letter of 9.30 pm the evening before
    /// at the lowest UID, Gmail's day by UTC, and one of 2020 after it: his
    /// day's letter, its date fetched with the evening's, one SEARCH.
    /// Taken as the lowest of Gmail's day, the landing went up from the
    /// evening to the letter of 2020, "Showing January 1, 2020".
    func testADayWithMailLandsOnItWhateverTheEveningBefore() async throws {
        folder([("9 Mar evening", "2014-03-10T01:30:00Z"),
                ("1 Jan 2020", "2020-01-01T15:00:00Z"),
                ("10 Mar letter", "2014-03-10T15:00:00Z")])
        let jumped = try await jump("2014-03-10", zone: "America/New_York")
        XCTAssertEqual(jumped.landed, "10 Mar letter")
        XCTAssertEqual(jumped.day, "10 Mar 2014")
        XCTAssertEqual(jumped.dated.count, 1)
        XCTAssertEqual(jumped.dateFetches, ["UID FETCH 1000,1002 \(Self.dates)"])
        assertOneHold(jumped, datesFetched: true)
    }

    /// In New York a Saturday with no mail, the Friday's 9.30 pm letter,
    /// Gmail's Saturday, at the lowest UID, one of 2020 after it, and the
    /// Monday's: the Monday's, as the Saturday's only letter is his Friday
    /// and the spans begin at Gmail's Sunday, three SEARCHes. Taken as the
    /// lowest of a span from Gmail's Saturday, the landing went up to the
    /// letter of 2020.
    func testAWeekendLandsOnTheMondayWhateverTheFridayEvening() async throws {
        folder([("Fri evening", "2014-03-15T01:30:00Z"),
                ("1 Jan 2020", "2020-01-01T15:00:00Z"),
                ("Mon 17 Mar", "2014-03-17T14:00:00Z")])
        let jumped = try await jump("2014-03-15", zone: "America/New_York")
        XCTAssertEqual(jumped.landed, "Mon 17 Mar")
        XCTAssertEqual(jumped.day, "17 Mar 2014")
        XCTAssertEqual(jumped.dated.map(sentBefore), ["17-Mar-2014", "17-Mar-2014", "19-Mar-2014"])
        XCTAssertTrue(jumped.dated.dropFirst().allSatisfy {
            $0.hasPrefix("UID SEARCH RETURN (MIN) SENTSINCE \"16-Mar-2014\" ")
        }, "\(jumped.dated)")
        XCTAssertEqual(jumped.dateFetches, ["UID FETCH 1000 \(Self.dates)"])
        assertOneHold(jumped, datesFetched: true)
    }

    /// In New York a day whose one letter is of 9 pm, Gmail's next day, a
    /// letter of that next day at a lower UID: his day's letter, Gmail's
    /// next day being asked with his, one SEARCH.
    func testADayWhoseOnlyLetterIsOfItsEveningLandsOnIt() async throws {
        folder([("11 Mar morning", "2014-03-11T14:00:00Z"),
                ("10 Mar evening", "2014-03-11T01:00:00Z")])
        let jumped = try await jump("2014-03-10", zone: "America/New_York")
        XCTAssertEqual(jumped.landed, "10 Mar evening")
        XCTAssertEqual(jumped.day, "10 Mar 2014")
        XCTAssertEqual(jumped.dated.count, 1)
        assertOneHold(jumped, datesFetched: true)
    }

    /// East of Greenwich, in Tokyo, his next morning's letter of 1 am, in
    /// Gmail's day, at the lowest UID, one of 2020 after it, and his day's
    /// at 2 pm: his day's, one SEARCH. Taken as the lowest of Gmail's day,
    /// the jump landed on the next morning and said the 11th.
    func testEastOfGreenwichADayLandsOnItWhateverTheNextMorning() async throws {
        folder([("11 Mar 1 am", "2014-03-10T16:00:00Z"),
                ("1 Jan 2020", "2020-01-01T15:00:00Z"),
                ("10 Mar 2 pm", "2014-03-10T05:00:00Z")])
        let jumped = try await jump("2014-03-10", zone: "Asia/Tokyo")
        XCTAssertEqual(jumped.landed, "10 Mar 2 pm")
        XCTAssertEqual(jumped.day, "10 Mar 2014")
        XCTAssertEqual(jumped.dated.count, 1)
        XCTAssertTrue(jumped.dated.first?.hasPrefix(
            "UID SEARCH SENTSINCE \"09-Mar-2014\" SENTBEFORE \"11-Mar-2014\" ") == true,
                      "\(jumped.dated)")
        assertOneHold(jumped, datesFetched: true)
    }

    /// In Tokyo a day whose one letter is of 3 am, Gmail's day before, at
    /// the lowest UID, one of 2020 after it and the next day's: his day's
    /// letter, one SEARCH. Gmail's day alone missed it, and the next day's
    /// letter, with the one of 2020 below it, was landed on.
    func testEastOfGreenwichADayWhoseOnlyLetterIsOfItsFirstHoursLandsOnIt() async throws {
        folder([("10 Mar 3 am", "2014-03-09T18:00:00Z"),
                ("1 Jan 2020", "2020-01-01T15:00:00Z"),
                ("11 Mar noon", "2014-03-11T03:00:00Z")])
        let jumped = try await jump("2014-03-10", zone: "Asia/Tokyo")
        XCTAssertEqual(jumped.landed, "10 Mar 3 am")
        XCTAssertEqual(jumped.day, "10 Mar 2014")
        XCTAssertEqual(jumped.dated.count, 1)
        assertOneHold(jumped, datesFetched: true)
    }

    /// The `SENTBEFORE` date of a dated SEARCH, nil for one with none.
    private func sentBefore(_ command: String) -> String? {
        guard let range = command.range(of: "SENTBEFORE \"") else { return nil }
        let rest = command[range.upperBound...]
        return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
    }
}
