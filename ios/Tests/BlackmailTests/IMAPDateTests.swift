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

    func testTheCriteriaIsSENTSINCEBecauseThatIsTheDateTheRowsShow() {
        // The list shows the envelope Date — what the sender's clock said.
        // SINCE tests INTERNALDATE, when the server took delivery. Mail
        // delayed overnight has two different dates, and jumping on the
        // wrong one lands on a row whose visible date is not the one he
        // asked for.
        let s = IMAPDate.sentOnOrAfter(date("2026-06-20T12:00:00Z"), now: now,
                                       timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(s, "SENTSINCE \"20-Jun-2026\" SINCE \"13-Jun-2026\" BEFORE \"11-Oct-2026\"")
        XCTAssertFalse(s.hasPrefix("SINCE"))
    }

    /// The arrival bound (B-058) is a week before the day, by his calendar:
    /// across the turn of a month and of a year, and on the day he picked
    /// west of Greenwich, never the day after it in UTC.
    func testTheArrivalBoundIsAWeekBeforeTheDayHePicked() {
        XCTAssertEqual(IMAPDate.arrivalSlack, 7)
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(IMAPDate.sentOnOrAfter(date("2026-01-03T12:00:00Z"), now: now, timeZone: utc),
                       "SENTSINCE \"03-Jan-2026\" SINCE \"27-Dec-2025\" BEFORE \"11-Oct-2026\"")
        XCTAssertEqual(IMAPDate.sentOnOrAfter(date("2024-03-06T12:00:00Z"), now: now, timeZone: utc),
                       "SENTSINCE \"06-Mar-2024\" SINCE \"28-Feb-2024\" BEFORE \"11-Oct-2026\"")
        // An evening in New York on the last of February is the first of
        // March in UTC.
        XCTAssertEqual(IMAPDate.sentOnOrAfter(date("2026-03-01T03:00:00Z"), now: now,
                                              timeZone: TimeZone(identifier: "America/New_York")!),
                       "SENTSINCE \"28-Feb-2026\" SINCE \"21-Feb-2026\" BEFORE \"11-Oct-2026\"")
    }

    /// A letter must have arrived before a week from today, counted in his
    /// days from the iPad's clock (B-058): one copied into Gmail saying it
    /// arrived in 2037 is left out while 2037 is ahead. Across the turn of
    /// a year, and on his evening that is the next day in UTC.
    func testTheArrivalMustBeBeforeAWeekFromToday() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertTrue(IMAPDate.sentOnOrAfter(date("2026-06-20T12:00:00Z"),
                                             now: date("2026-12-28T12:00:00Z"), timeZone: utc)
            .hasSuffix(" BEFORE \"05-Jan-2027\""))
        XCTAssertTrue(IMAPDate.sentOnOrAfter(date("2026-06-20T12:00:00Z"),
                                             now: date("2026-10-04T02:00:00Z"),
                                             timeZone: TimeZone(identifier: "America/New_York")!)
            .hasSuffix(" BEFORE \"11-Oct-2026\""))
    }

    /// The week back is seven of his days, not seven times 24 hours: half
    /// past midnight two days after the clocks went forward in New York is
    /// still the third a week before, not the second.
    func testTheWeekBackIsCountedInDaysAcrossAClockChange() {
        let newYork = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(IMAPDate.sentOnOrAfter(date("2026-03-10T04:30:00Z"), now: now, timeZone: newYork),
                       "SENTSINCE \"10-Mar-2026\" SINCE \"03-Mar-2026\" BEFORE \"11-Oct-2026\"")
    }

    // MARK: - A jump's spans (B-115)

    /// The `i`th of `searches`, or "" if there are not so many, so a short
    /// list fails the test rather than ending the run.
    private func at(_ searches: [String], _ i: Int) -> String {
        searches.indices.contains(i) ? searches[i] : ""
    }

    /// A span is the letters dated from the day, before the day `days`
    /// after it, with the same arrival bounds as the search with no end:
    /// across the turn of a month and of a year, and on his evening in New
    /// York that is the next day in UTC.
    func testASpanIsTheDaysFromTheDayWithTheArrivalBounds() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(IMAPDate.sentWithin(date("2014-03-10T12:00:00Z"), days: 1, now: now,
                                           timeZone: utc),
                       "SENTSINCE \"10-Mar-2014\" SENTBEFORE \"11-Mar-2014\" "
                        + "SINCE \"03-Mar-2014\" BEFORE \"11-Oct-2026\"")
        XCTAssertEqual(IMAPDate.sentWithin(date("2026-02-27T12:00:00Z"), days: 4, now: now,
                                           timeZone: utc),
                       "SENTSINCE \"27-Feb-2026\" SENTBEFORE \"03-Mar-2026\" "
                        + "SINCE \"20-Feb-2026\" BEFORE \"11-Oct-2026\"")
        XCTAssertEqual(IMAPDate.sentWithin(date("2025-12-30T12:00:00Z"), days: 2, now: now,
                                           timeZone: utc),
                       "SENTSINCE \"30-Dec-2025\" SENTBEFORE \"01-Jan-2026\" "
                        + "SINCE \"23-Dec-2025\" BEFORE \"11-Oct-2026\"")
        XCTAssertEqual(IMAPDate.sentWithin(date("2026-03-01T03:00:00Z"), days: 1, now: now,
                                           timeZone: TimeZone(identifier: "America/New_York")!),
                       "SENTSINCE \"28-Feb-2026\" SENTBEFORE \"01-Mar-2026\" "
                        + "SINCE \"21-Feb-2026\" BEFORE \"11-Oct-2026\"")
    }

    /// Counted in his days across a clock change: two days from half past
    /// eleven on the Saturday night before the clocks go forward in New
    /// York is the Monday, where 48 hours is the Tuesday.
    func testASpanIsCountedInDaysAcrossAClockChange() {
        let newYork = TimeZone(identifier: "America/New_York")!
        XCTAssertTrue(IMAPDate.sentWithin(date("2026-03-08T04:30:00Z"), days: 2, now: now,
                                          timeZone: newYork)
            .hasPrefix("SENTSINCE \"07-Mar-2026\" SENTBEFORE \"09-Mar-2026\" "))
    }

    /// The day first, then spans doubling from it, each from the day, and
    /// last the search with no end; none past the 11th, a week after
    /// today, by which every letter matched arrived.
    func testAJumpAsksForTheDayThenDoublesThenTheSearchWithNoEnd() {
        let utc = TimeZone(identifier: "UTC")!
        let day = date("2014-03-15T12:00:00Z")
        let searches = IMAPDate.jumpSearches(from: day, now: now, timeZone: utc)
        // 4,593 days to the 11th: spans of 1 to 4,096 days, then no end.
        XCTAssertEqual(searches.count, 14)
        XCTAssertEqual(Array(searches.dropLast()),
                       (0..<13).map { IMAPDate.sentWithin(day, days: 1 << $0, now: now, timeZone: utc) })
        XCTAssertEqual(searches.last, IMAPDate.sentOnOrAfter(day, now: now, timeZone: utc))
        XCTAssertTrue(at(searches, 2).hasPrefix("SENTSINCE \"15-Mar-2014\" SENTBEFORE \"19-Mar-2014\" "))
        XCTAssertTrue(at(searches, 12).contains("SENTBEFORE \"01-Jun-2025\""), at(searches, 12))
    }

    /// Today: one, two and four days, then no end, as eight would reach
    /// the 11th. Two days before today: one to eight days. A day after a
    /// week from today, which the picker does not offer: no end alone.
    func testNearTodayTheSpansStopShortOfAWeekAhead() {
        let utc = TimeZone(identifier: "UTC")!
        let today = IMAPDate.jumpSearches(from: now, now: now, timeZone: utc)
        XCTAssertEqual(today.count, 4)
        XCTAssertTrue(at(today, 2).contains("SENTBEFORE \"07-Oct-2026\""), at(today, 2))
        XCTAssertEqual(today.last, IMAPDate.sentOnOrAfter(now, now: now, timeZone: utc))
        let before = IMAPDate.jumpSearches(from: date("2026-10-01T12:00:00Z"), now: now, timeZone: utc)
        XCTAssertEqual(before.count, 5)
        XCTAssertTrue(at(before, 3).contains("SENTBEFORE \"09-Oct-2026\""), at(before, 3))
        let ahead = date("2026-10-11T12:00:00Z")
        XCTAssertEqual(IMAPDate.jumpSearches(from: ahead, now: now, timeZone: utc),
                       [IMAPDate.sentOnOrAfter(ahead, now: now, timeZone: utc)])
    }

    /// Never more than fifteen spans, the widest 16,384 days, and then no
    /// end: sixteen for a day in 1900, and for one in the year 1.
    func testAJumpAsksSixteenAtMost() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(IMAPDate.spanSearches, 15)
        let day = date("1900-01-01T12:00:00Z")
        let early = IMAPDate.jumpSearches(from: day, now: now, timeZone: utc)
        XCTAssertEqual(early.count, 16)
        XCTAssertTrue(at(early, 14).contains("SENTBEFORE \"10-Nov-1944\""), at(early, 14))
        XCTAssertEqual(at(early, 15), IMAPDate.sentOnOrAfter(day, now: now, timeZone: utc))
        let first = IMAPDate.jumpSearches(from: date("0001-06-01T12:00:00Z"), now: now, timeZone: utc)
        XCTAssertEqual(first.count, 16)
    }

    /// In his calendar: his evening in New York that is the next day in
    /// UTC asks for his day.
    func testAJumpsSpansAreInHisCalendar() {
        let searches = IMAPDate.jumpSearches(from: date("2026-06-21T00:30:00Z"), now: now,
                                             timeZone: TimeZone(identifier: "America/New_York")!)
        XCTAssertTrue(at(searches, 0).hasPrefix("SENTSINCE \"20-Jun-2026\" SENTBEFORE \"21-Jun-2026\" "),
                      at(searches, 0))
    }

    func testTheCriteriaCarriesNothingThatCouldBreakTheCommandLine() {
        // Unlike a search term this is machine-made, but it is still
        // concatenated into a command, and the client strips only
        // NUL/CR/LF.
        let s = IMAPDate.sentOnOrAfter(date("2026-06-20T12:00:00Z"), now: now)
        XCTAssertFalse(s.contains("\n"))
        XCTAssertFalse(s.contains("\r"))
        XCTAssertEqual(s.filter { $0 == "\"" }.count, 6)
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
