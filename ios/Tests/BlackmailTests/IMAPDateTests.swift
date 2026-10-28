import XCTest
@testable import Blackmail

/// Tests for the date that goes on the wire, and the one that goes on screen.
///
/// Every failure mode here is silent. A wrong month abbreviation is a BAD
/// the app renders as "Can't connect to mail server."; a day lost to a
/// timezone is a jump that lands twenty-four hours from where he pointed.
/// Neither looks like a date bug from the outside.
final class IMAPDateTests: XCTestCase {

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    /// The iPad's clock in these tests: 3 October 2026, so a letter must
    /// have arrived before the 11th.
    private var now: Date { date("2026-10-03T12:00:00Z") }

    // MARK: - The wire

    func testTheFormatIsTheOneRFC3501Specifies() {
        let s = IMAPDate.criteriaValue(for: date("2026-06-20T12:00:00Z"),
                                       timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(s, "\"20-Jun-2026\"")
    }

    func testTheMonthIsEnglishWhateverTheDeviceLocaleIs() {
        // The device is in English today. That is not a reason to let the
        // locale pick: `MMM` on a French iPad renders "juin", and the
        // server answers BAD to a month it has never heard of.
        let s = IMAPDate.criteriaValue(for: date("2026-05-03T12:00:00Z"),
                                       timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(s, "\"03-May-2026\"")
        XCTAssertFalse(s.lowercased().contains("mai"))
    }

    func testEveryMonthAbbreviationIsTheThreeLetterFormTheProtocolWants() {
        let expected = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        for (i, abbreviation) in expected.enumerated() {
            let iso = String(format: "2026-%02d-15T12:00:00Z", i + 1)
            XCTAssertEqual(
                IMAPDate.criteriaValue(for: date(iso),
                                       timeZone: TimeZone(identifier: "UTC")!),
                "\"15-\(abbreviation)-2026\"")
        }
    }

    func testTheDayIsTheUsersDayNotUTCs() {
        // Half past eight on the evening of the 20th in New York is already
        // the 21st in UTC. Formatting in UTC would put the jump a day past
        // the mail he was pointing at.
        let evening = date("2026-06-21T00:30:00Z")
        XCTAssertEqual(
            IMAPDate.criteriaValue(for: evening,
                                   timeZone: TimeZone(identifier: "America/New_York")!),
            "\"20-Jun-2026\"")
    }

    func testTheCriteriaIsSINCEBecauseThatIsTheDateTheRowsShow() {
        // The list goes by when each letter arrived and its rows show it,
        // as Mail's do (B-178). SINCE tests INTERNALDATE, when the server
        // took delivery; SENTSINCE the Date header, which Gmail answers by
        // INTERNALDATE all the same (seen 2026-10-28). A letter dated one
        // day that arrived on another is found on the day its row shows.
        let s = IMAPDate.arrivedOnOrAfter(date("2026-06-20T12:00:00Z"), now: now,
                                          timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(s, "SINCE \"20-Jun-2026\" BEFORE \"11-Oct-2026\"")
        XCTAssertFalse(s.contains("SENT"))
    }

    /// The day asked for is his, by his calendar, across the turn of a
    /// month and of a year, and on his evening west of Greenwich, never
    /// the day after it in UTC; and nothing before it is asked: the week
    /// back B-058 asked for was for a letter dated a day it did not arrive
    /// on, and by arrival there is none.
    func testTheDayAskedIsHisAndNothingBeforeIt() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(IMAPDate.arrivedOnOrAfter(date("2026-01-03T12:00:00Z"), now: now, timeZone: utc),
                       "SINCE \"03-Jan-2026\" BEFORE \"11-Oct-2026\"")
        XCTAssertEqual(IMAPDate.arrivedOnOrAfter(date("2024-03-06T12:00:00Z"), now: now, timeZone: utc),
                       "SINCE \"06-Mar-2024\" BEFORE \"11-Oct-2026\"")
        // An evening in New York on the last of February is the first of
        // March in UTC.
        XCTAssertEqual(IMAPDate.arrivedOnOrAfter(date("2026-03-01T03:00:00Z"), now: now,
                                                 timeZone: TimeZone(identifier: "America/New_York")!),
                       "SINCE \"28-Feb-2026\" BEFORE \"11-Oct-2026\"")
    }

    /// A letter must have arrived before a week from today, counted in his
    /// days from the iPad's clock (B-058): one copied into Gmail saying it
    /// arrived in 2037 is left out while 2037 is ahead. Across the turn of
    /// a year, and on his evening that is the next day in UTC.
    func testTheArrivalMustBeBeforeAWeekFromToday() {
        XCTAssertEqual(IMAPDate.arrivalSlack, 7)
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertTrue(IMAPDate.arrivedOnOrAfter(date("2026-06-20T12:00:00Z"),
                                                now: date("2026-12-28T12:00:00Z"), timeZone: utc)
            .hasSuffix(" BEFORE \"05-Jan-2027\""))
        XCTAssertTrue(IMAPDate.arrivedOnOrAfter(date("2026-06-20T12:00:00Z"),
                                                now: date("2026-10-04T02:00:00Z"),
                                                timeZone: TimeZone(identifier: "America/New_York")!)
            .hasSuffix(" BEFORE \"11-Oct-2026\""))
    }

    /// The week ahead is eight of his days, not eight times 24 hours: half
    /// past eleven on the Saturday night before the clocks go forward in
    /// New York, eight days on is the next Sunday's half past eleven, the
    /// 15th, where 192 hours is the 16th.
    func testTheWeekAheadIsCountedInDaysAcrossAClockChange() {
        let newYork = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(IMAPDate.arrivedOnOrAfter(date("2026-03-01T12:00:00Z"),
                                                 now: date("2026-03-08T04:30:00Z"), timeZone: newYork),
                       "SINCE \"01-Mar-2026\" BEFORE \"15-Mar-2026\"")
    }

    // MARK: - A jump's SEARCHes (B-115)

    /// The `i`th of `searches`, or "" if there are not so many, so a short
    /// list fails the test rather than ending the run.
    private func at(_ searches: [String], _ i: Int) -> String {
        searches.indices.contains(i) ? searches[i] : ""
    }

    private func zone(_ identifier: String) -> TimeZone { TimeZone(identifier: identifier)! }

    /// His day's SEARCH is every letter that arrived on Gmail's days, from
    /// midnight UTC, that hold any of it: one day in UTC and in London in
    /// winter; in New York the day and the next; in London in summer and
    /// in Tokyo the day before and the day; across the turn of a year.
    func testHisDaysSearchIsGmailsDaysThatHoldAnyOfIt() {
        XCTAssertEqual(IMAPDate.arrivedOnHisDay(date("2014-03-10T12:00:00Z"), timeZone: zone("UTC")),
                       "SINCE \"10-Mar-2014\" BEFORE \"11-Mar-2014\"")
        XCTAssertEqual(IMAPDate.arrivedOnHisDay(date("2026-01-15T12:00:00Z"),
                                                timeZone: zone("Europe/London")),
                       "SINCE \"15-Jan-2026\" BEFORE \"16-Jan-2026\"")
        XCTAssertEqual(IMAPDate.arrivedOnHisDay(date("2014-03-10T16:00:00Z"),
                                                timeZone: zone("America/New_York")),
                       "SINCE \"10-Mar-2014\" BEFORE \"12-Mar-2014\"")
        XCTAssertEqual(IMAPDate.arrivedOnHisDay(date("2026-07-15T12:00:00Z"),
                                                timeZone: zone("Europe/London")),
                       "SINCE \"14-Jul-2026\" BEFORE \"16-Jul-2026\"")
        XCTAssertEqual(IMAPDate.arrivedOnHisDay(date("2019-06-19T23:00:00Z"), timeZone: zone("Asia/Tokyo")),
                       "SINCE \"19-Jun-2019\" BEFORE \"21-Jun-2019\"")
        XCTAssertEqual(IMAPDate.arrivedOnHisDay(date("2025-12-31T17:00:00Z"),
                                                timeZone: zone("America/New_York")),
                       "SINCE \"31-Dec-2025\" BEFORE \"02-Jan-2026\"")
    }

    /// A span after his day starts at Gmail's day his next midnight falls
    /// in and ends before the day `days` after his: in UTC and New York the
    /// next day, in Tokyo the day itself, as Gmail's day there begins at 9
    /// am; across the turn of a year; and with no end, the same start and
    /// no later than a week after today.
    func testTheSpansAfterHisDayStartAtGmailsDayOfHisNextMidnight() {
        XCTAssertEqual(IMAPDate.arrivedAfterHisDay(date("2014-03-15T12:00:00Z"), days: 2, now: now,
                                                   timeZone: zone("UTC")),
                       "SINCE \"16-Mar-2014\" BEFORE \"17-Mar-2014\"")
        XCTAssertEqual(IMAPDate.arrivedAfterHisDay(date("2014-03-15T16:00:00Z"), days: 4, now: now,
                                                   timeZone: zone("America/New_York")),
                       "SINCE \"16-Mar-2014\" BEFORE \"19-Mar-2014\"")
        XCTAssertEqual(IMAPDate.arrivedAfterHisDay(date("2019-06-20T03:00:00Z"), days: 2, now: now,
                                                   timeZone: zone("Asia/Tokyo")),
                       "SINCE \"20-Jun-2019\" BEFORE \"22-Jun-2019\"")
        XCTAssertEqual(IMAPDate.arrivedAfterHisDay(date("2025-12-30T12:00:00Z"), days: 4, now: now,
                                                   timeZone: zone("UTC")),
                       "SINCE \"31-Dec-2025\" BEFORE \"03-Jan-2026\"")
        XCTAssertEqual(IMAPDate.arrivedAfterHisDay(date("2026-10-01T16:00:00Z"), days: nil, now: now,
                                                   timeZone: zone("America/New_York")),
                       "SINCE \"02-Oct-2026\" BEFORE \"11-Oct-2026\"")
    }

    /// Counted in his days across a clock change: two days from half past
    /// eleven on the Saturday night before the clocks go forward in New
    /// York is the Monday, where 48 hours is the Tuesday; and his day is
    /// 23 hours that Sunday and 25 the Sunday they go back.
    func testHisDaysAreCountedAcrossAClockChange() {
        let newYork = zone("America/New_York")
        XCTAssertEqual(IMAPDate.arrivedAfterHisDay(date("2026-03-08T04:30:00Z"), days: 2, now: now,
                                                   timeZone: newYork),
                       "SINCE \"08-Mar-2026\" BEFORE \"09-Mar-2026\"")
        let forward = IMAPDate.jump(from: date("2026-03-08T16:00:00Z"), now: now, timeZone: newYork)
        XCTAssertEqual(forward.hisDay, date("2026-03-08T05:00:00Z")..<date("2026-03-09T04:00:00Z"))
        let back = IMAPDate.jump(from: date("2026-11-01T16:00:00Z"), now: now, timeZone: newYork)
        XCTAssertEqual(back.hisDay, date("2026-11-01T04:00:00Z")..<date("2026-11-02T05:00:00Z"))
    }

    /// His day first, its letters' dates to be fetched; then spans after
    /// it, two days, four and so on, doubling; and last the SEARCH with no
    /// end; none past the 11th, a week after today, by which every letter
    /// matched arrived.
    func testAJumpAsksHisDayThenSpansAfterItThenNoEnd() {
        let utc = zone("UTC")
        let day = date("2014-03-15T12:00:00Z")
        let jump = IMAPDate.jump(from: day, now: now, timeZone: utc)
        XCTAssertEqual(jump.day, IMAPDate.arrivedOnHisDay(day, timeZone: utc))
        XCTAssertEqual(jump.hisDay, date("2014-03-15T00:00:00Z")..<date("2014-03-16T00:00:00Z"))
        // 4,593 days to the 11th: his day, spans of 2 to 4,096 days, then
        // no end, fourteen in all.
        XCTAssertEqual(jump.wider.count, 13)
        XCTAssertEqual(Array(jump.wider.dropLast()), (1..<13).map {
            IMAPDate.arrivedAfterHisDay(day, days: 1 << $0, now: now, timeZone: utc)
        })
        XCTAssertEqual(jump.wider.last, IMAPDate.arrivedAfterHisDay(day, days: nil, now: now,
                                                                    timeZone: utc))
        XCTAssertEqual(at(jump.wider, 1), "SINCE \"16-Mar-2014\" BEFORE \"19-Mar-2014\"")
        XCTAssertTrue(at(jump.wider, 11).hasSuffix("BEFORE \"01-Jun-2025\""), at(jump.wider, 11))
        XCTAssertEqual(jump.pageSearch, .lowestDated(IMAPDate.arrivedOnHisDay(day, timeZone: utc),
                                                     within: jump.hisDay, wider: jump.wider))
    }

    /// Every SEARCH a jump asks is by when the letters arrived, `SINCE` and
    /// `BEFORE` once each, and none by the Date (B-178); only the one with
    /// no end, and the one for a day a week or more ahead, ends a week
    /// after today, the others before it.
    func testEveryJumpSearchIsByArrival() {
        for (iso, zoneName) in [("2014-03-15T12:00:00Z", "UTC"), ("2026-10-01T16:00:00Z", "America/New_York"),
                                ("2019-06-20T03:00:00Z", "Asia/Tokyo"), ("2026-10-11T12:00:00Z", "UTC")] {
            let jump = IMAPDate.jump(from: date(iso), now: now, timeZone: zone(zoneName))
            for search in [jump.day].compactMap({ $0 }) + jump.wider {
                XCTAssertFalse(search.contains("SENT"), search)
                XCTAssertEqual(search.components(separatedBy: "SINCE ").count, 2, search)
                XCTAssertEqual(search.components(separatedBy: "BEFORE ").count, 2, search)
            }
            XCTAssertTrue(jump.wider.last?.hasSuffix("BEFORE \"11-Oct-2026\"") == true, iso)
            XCTAssertFalse(jump.day?.contains("11-Oct-2026") == true, iso)
        }
    }

    /// Today: his day, two and four days, then no end, as eight would reach
    /// the 11th. Two days before today: his day, two to eight days. Two
    /// days before the 11th: his day and no end. A day after a week from
    /// today, which the picker does not offer, and the day before it: one
    /// SEARCH alone, every letter that arrived on or after the day.
    func testNearTodayTheSpansStopShortOfAWeekAhead() {
        let utc = zone("UTC")
        let today = IMAPDate.jump(from: now, now: now, timeZone: utc)
        XCTAssertNotNil(today.day)
        XCTAssertEqual(today.wider.count, 3)
        XCTAssertTrue(at(today.wider, 1).hasSuffix("BEFORE \"07-Oct-2026\""), at(today.wider, 1))
        XCTAssertEqual(today.wider.last, IMAPDate.arrivedAfterHisDay(now, days: nil, now: now, timeZone: utc))
        let before = IMAPDate.jump(from: date("2026-10-01T12:00:00Z"), now: now, timeZone: utc)
        XCTAssertNotNil(before.day)
        XCTAssertEqual(before.wider.count, 4)
        XCTAssertTrue(at(before.wider, 2).hasSuffix("BEFORE \"09-Oct-2026\""), at(before.wider, 2))
        let late = IMAPDate.jump(from: date("2026-10-09T12:00:00Z"), now: now, timeZone: utc)
        XCTAssertNotNil(late.day)
        XCTAssertEqual(late.wider.count, 1)
        for ymd in ["2026-10-10", "2026-10-11"] {
            let ahead = date("\(ymd)T12:00:00Z")
            let jump = IMAPDate.jump(from: ahead, now: now, timeZone: utc)
            XCTAssertNil(jump.day, ymd)
            XCTAssertEqual(jump.wider, [IMAPDate.arrivedOnOrAfter(ahead, now: now, timeZone: utc)], ymd)
            XCTAssertEqual(jump.pageSearch, .lowestOfFirst(jump.wider), ymd)
        }
    }

    /// Never more than fifteen before the one with no end, his day and
    /// spans to 16,384 days: sixteen for a day in 1900, and for one in the
    /// year 1.
    func testAJumpAsksSixteenAtMost() {
        let utc = zone("UTC")
        XCTAssertEqual(IMAPDate.spanSearches, 15)
        let day = date("1900-01-01T12:00:00Z")
        let early = IMAPDate.jump(from: day, now: now, timeZone: utc)
        XCTAssertNotNil(early.day)
        XCTAssertEqual(early.wider.count, 15)
        XCTAssertTrue(at(early.wider, 13).hasSuffix("BEFORE \"10-Nov-1944\""), at(early.wider, 13))
        XCTAssertEqual(at(early.wider, 14), IMAPDate.arrivedAfterHisDay(day, days: nil, now: now,
                                                                        timeZone: utc))
        let first = IMAPDate.jump(from: date("0001-06-01T12:00:00Z"), now: now, timeZone: utc)
        XCTAssertEqual(first.wider.count, 15)
    }

    /// In his calendar: his evening in New York that is the next day in
    /// UTC asks for his day, and his day is his midnight to his next.
    func testAJumpIsInHisCalendar() {
        let jump = IMAPDate.jump(from: date("2026-06-21T00:30:00Z"), now: now,
                                 timeZone: zone("America/New_York"))
        XCTAssertEqual(jump.day, "SINCE \"20-Jun-2026\" BEFORE \"22-Jun-2026\"")
        XCTAssertEqual(jump.hisDay, date("2026-06-20T04:00:00Z")..<date("2026-06-21T04:00:00Z"))
        XCTAssertEqual(at(jump.wider, 0), "SINCE \"21-Jun-2026\" BEFORE \"22-Jun-2026\"")
    }

    func testTheCriteriaCarriesNothingThatCouldBreakTheCommandLine() {
        // Unlike a search term this is machine-made, but it is still
        // concatenated into a command, and the client strips only
        // NUL/CR/LF.
        let s = IMAPDate.arrivedOnOrAfter(date("2026-06-20T12:00:00Z"), now: now)
        XCTAssertFalse(s.contains("\n"))
        XCTAssertFalse(s.contains("\r"))
        XCTAssertEqual(s.filter { $0 == "\"" }.count, 4)
    }

    // MARK: - The screen

    func testTheSpokenDayLeavesOffTheYearWhenItIsThisOne() {
        let d = date("2026-06-20T12:00:00Z")
        let spoken = IMAPDate.spokenDay(d, now: date("2026-09-20T12:00:00Z"))
        XCTAssertTrue(spoken.contains("20"), spoken)
        XCTAssertTrue(spoken.contains("June"), spoken)
        XCTAssertFalse(spoken.contains("2026"), spoken)
    }

    func testTheSpokenDayKeepsTheYearWhenItIsADifferentOne() {
        // Without it, "20 June" for a letter from 2019 is actively
        // misleading — and looking back years is exactly what this is for.
        let spoken = IMAPDate.spokenDay(date("2019-06-20T12:00:00Z"),
                                        now: date("2026-09-20T12:00:00Z"))
        XCTAssertTrue(spoken.contains("2019"), spoken)
    }

    func testTheSpokenDayIsWordsRatherThanDigits() {
        // "Showing 20/06" is a format he has to decode; two of the three
        // number orders in use worldwide would read it as a different day.
        let spoken = IMAPDate.spokenDay(date("2026-06-20T12:00:00Z"),
                                        now: date("2026-09-20T12:00:00Z"))
        XCTAssertFalse(spoken.contains("/"), spoken)
        XCTAssertTrue(spoken.rangeOfCharacter(from: .letters) != nil, spoken)
    }
}
