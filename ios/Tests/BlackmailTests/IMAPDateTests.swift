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
        let s = IMAPDate.sentOnOrAfter(date("2026-06-20T12:00:00Z"),
                                       timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(s, "SENTSINCE \"20-Jun-2026\" SINCE \"13-Jun-2026\"")
        XCTAssertFalse(s.hasPrefix("SINCE"))
    }

    /// The arrival bound (B-058) is a week before the day, by his calendar:
    /// across the turn of a month and of a year, and on the day he picked
    /// west of Greenwich, never the day after it in UTC.
    func testTheArrivalBoundIsAWeekBeforeTheDayHePicked() {
        XCTAssertEqual(IMAPDate.arrivalSlack, 7)
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(IMAPDate.sentOnOrAfter(date("2026-01-03T12:00:00Z"), timeZone: utc),
                       "SENTSINCE \"03-Jan-2026\" SINCE \"27-Dec-2025\"")
        XCTAssertEqual(IMAPDate.sentOnOrAfter(date("2024-03-06T12:00:00Z"), timeZone: utc),
                       "SENTSINCE \"06-Mar-2024\" SINCE \"28-Feb-2024\"")
        // An evening in New York on the last of February is the first of
        // March in UTC.
        XCTAssertEqual(IMAPDate.sentOnOrAfter(date("2026-03-01T03:00:00Z"),
                                              timeZone: TimeZone(identifier: "America/New_York")!),
                       "SENTSINCE \"28-Feb-2026\" SINCE \"21-Feb-2026\"")
    }

    /// The week back is seven of his days, not seven times 24 hours: half
    /// past midnight two days after the clocks went forward in New York is
    /// still the third a week before, not the second.
    func testTheWeekBackIsCountedInDaysAcrossAClockChange() {
        let newYork = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(IMAPDate.sentOnOrAfter(date("2026-03-10T04:30:00Z"), timeZone: newYork),
                       "SENTSINCE \"10-Mar-2026\" SINCE \"03-Mar-2026\"")
    }

    func testTheCriteriaCarriesNothingThatCouldBreakTheCommandLine() {
        // Unlike a search term this is machine-made, but it is still
        // concatenated into a command, and the client strips only
        // NUL/CR/LF.
        let s = IMAPDate.sentOnOrAfter(date("2026-06-20T12:00:00Z"))
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
