import XCTest
@testable import Blackmail

/// What is on screen while something he asked for is on its way: the
/// list's status line during a jump or a Move, an alert held until the
/// sheet he chose from has gone, and a draft on its way to the composer.
/// The screens are UIKit; these are the rules they follow.
final class FeedbackTests: XCTestCase {

    private let day = Date(timeIntervalSince1970: 1_777_766_400)   // 3 May 2026

    // MARK: - The status line

    /// A jump says where it is going from the tap, and the line says where
    /// it landed once it has; a jump that fails goes back to what the line
    /// said before. Nothing used to be said until it was over.
    func testAJumpSaysWhereItIsGoingUntilItIsDone() {
        var line = StatusLine(resting: "Updated Just Now")
        XCTAssertEqual(line.text, "Updated Just Now")

        let going = line.start(StatusLine.goingTo(day))
        XCTAssertEqual(line.text, "Going to \(IMAPDate.spokenDay(day))…")
        // The day lands, and is said once the jump is done.
        line.rest("Showing \(IMAPDate.spokenDay(day))")
        XCTAssertEqual(line.text, "Going to \(IMAPDate.spokenDay(day))…")
        line.finish(going)
        XCTAssertEqual(line.text, "Showing \(IMAPDate.spokenDay(day))")

        // One that fails leaves the line as it was.
        let again = line.start(StatusLine.goingTo(day))
        line.finish(again)
        XCTAssertEqual(line.text, "Showing \(IMAPDate.spokenDay(day))")
    }

    /// A Move and a jump at once: the later is said while both are out, the
    /// other when it alone is; and a Refresh that overtook a jump has the
    /// last word once the jump lets go.
    func testOverlappingWorkAndARefreshThatOvertookIt() {
        var line = StatusLine(resting: "Updated Just Now")
        let going = line.start(StatusLine.goingTo(day))
        let moving = line.start(StatusLine.moving)
        XCTAssertEqual(line.text, "Moving…")
        line.finish(moving)
        XCTAssertEqual(line.text, StatusLine.goingTo(day))
        line.rest("Updated Just Now")
        line.finish(going)
        XCTAssertEqual(line.text, "Updated Just Now")
        line.finish(going)
        XCTAssertEqual(line.text, "Updated Just Now", "finishing twice changes nothing")
    }

    // MARK: - How fresh the list is (B-049)

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 21 September 2026, 14:13:20 UTC.
    private let checked = Date(timeIntervalSince1970: 1_790_000_000)

    private func said(_ line: UpdatedLine, after seconds: TimeInterval) -> String {
        line.text(now: checked.addingTimeInterval(seconds), calendar: Self.utc,
                  locale: Locale(identifier: "en_GB"))
    }

    /// "Updated Just Now" used to be said at every fetch and never again,
    /// whatever the time, so an hour-old list said it had just been fetched.
    /// It ages now, as Mail's does: just now for the first minute, then the
    /// minutes, then the time of day, then yesterday, then the date. A clock
    /// set back is not taken for just now.
    func testTheLineAgesAsMailsDoes() {
        var line = UpdatedLine()
        line.succeeded(at: checked)
        XCTAssertEqual(said(line, after: 0), "Updated Just Now")
        XCTAssertEqual(said(line, after: 59), "Updated Just Now")
        XCTAssertEqual(said(line, after: 60), "Updated 1 minute ago")
        XCTAssertEqual(said(line, after: 119), "Updated 1 minute ago")
        XCTAssertEqual(said(line, after: 120), "Updated 2 minutes ago")
        XCTAssertEqual(said(line, after: 59 * 60 + 59), "Updated 59 minutes ago")
        XCTAssertEqual(said(line, after: 3_600), "Updated at 14:13")
        XCTAssertEqual(said(line, after: 9 * 3_600), "Updated at 14:13")
        XCTAssertEqual(said(line, after: 10 * 3_600), "Updated Yesterday")
        XCTAssertEqual(said(line, after: 3 * 86_400), "Updated 21/09/2026")
        XCTAssertEqual(said(line, after: -600), "Updated at 14:13")
    }

    /// A check that failed says so under the age, as Mail puts an account's
    /// error under its "Updated" line, rather than the line going on saying
    /// the list is fresh. A check that works again takes it away.
    func testAFailedCheckIsSaidUnderTheAge() {
        var line = UpdatedLine()
        line.succeeded(at: checked)
        line.failed(.cannotConnect)
        XCTAssertEqual(said(line, after: 5 * 60), "Updated 5 minutes ago\nNo Connection")
        line.failed(.passwordNeedsUpdating)
        XCTAssertEqual(said(line, after: 5 * 60), "Updated 5 minutes ago\nPassword Needs Updating")
        line.reached()
        XCTAssertEqual(said(line, after: 6 * 60), "Updated 6 minutes ago")
        line.failed(.cannotConnect)
        line.succeeded(at: checked.addingTimeInterval(7 * 60))
        XCTAssertEqual(said(line, after: 7 * 60), "Updated Just Now")
    }

    /// Before the list's first page it is being checked for, as Mail says.
    /// A first page that could not be fetched says why the list is empty,
    /// and goes on saying it while only the Inbox's count can be checked:
    /// nothing has brought this list up to date.
    func testAListNeverFetchedSaysItIsBeingCheckedOrWhyNot() {
        var line = UpdatedLine()
        XCTAssertEqual(said(line, after: 0), "Checking for Mail…")
        line.failed(.cannotConnect)
        XCTAssertEqual(said(line, after: 0), "No Connection")
        line.reached()
        XCTAssertEqual(said(line, after: 30), "No Connection")
        line.succeeded(at: checked.addingTimeInterval(60))
        XCTAssertEqual(said(line, after: 60), "Updated Just Now")
    }

    /// The kept page on screen at launch (D-016): "Checking for Mail…"
    /// while the server is asked, as before any list has come, not the age
    /// of the kept rows, which would read as the check having been made.
    /// With no connection the rows stay and the line says how old they are,
    /// over what went wrong; once the fresh page lands, "Updated Just Now".
    func testOverTheKeptPageTheLineChecksAndThenSaysHowOldOrJustNow() {
        var line = UpdatedLine()
        line.showingKept(since: checked)
        XCTAssertEqual(said(line, after: 86_400), "Checking for Mail…")
        line.failed(.cannotConnect)
        XCTAssertEqual(said(line, after: 86_400), "Updated Yesterday\nNo Connection")
        XCTAssertEqual(said(line, after: 2 * 3_600), "Updated at 14:13\nNo Connection")
        line.succeeded(at: checked.addingTimeInterval(86_400))
        XCTAssertEqual(said(line, after: 86_400 + 5), "Updated Just Now")
        line.showingKept(since: checked)
        line.failed(.passwordNeedsUpdating)
        XCTAssertEqual(said(line, after: 3 * 86_400), "Updated 21/09/2026\nPassword Needs Updating")
    }

    /// A check of the Inbox's list brings that list up to date. The same
    /// check with another list in front, or one of the Inbox's count, says
    /// only that the server can be reached, and leaves the age of the list
    /// in front as it was. A check that failed says why, under the age.
    func testEachCheckSaysOnTheLineOnlyWhatItShowed() {
        let later = checked.addingTimeInterval(120)
        var inbox = UpdatedLine()
        inbox.succeeded(at: checked)
        inbox.failed(.cannotConnect)
        inbox.checked(.listed(mailboxID: "inbox", at: later), listing: "inbox")
        XCTAssertEqual(said(inbox, after: 150), "Updated Just Now")

        var sent = UpdatedLine()
        sent.succeeded(at: checked)
        sent.failed(.cannotConnect)
        sent.checked(.listed(mailboxID: "inbox", at: later), listing: "sent")
        XCTAssertEqual(said(sent, after: 150), "Updated 2 minutes ago")
        sent.checked(.failed(.passwordNeedsUpdating, at: later), listing: "sent")
        XCTAssertEqual(said(sent, after: 150), "Updated 2 minutes ago\nPassword Needs Updating")
        sent.checked(.reached(at: later), listing: "sent")
        XCTAssertEqual(said(sent, after: 150), "Updated 2 minutes ago")
    }

    // MARK: - Alerts over a sheet on its way out

    /// A jump or a Move now starts at the tap, and one that fails fast, with
    /// no connection at all, fails while its sheet is still sliding away,
    /// where UIKit would drop the alert. It is held until the sheet has
    /// gone, and shown once.
    func testAnAlertAskedForWhileTheSheetLeavesWaitsForItToGo() {
        var hold = AlertHold<String>()
        XCTAssertEqual(hold.show("Can't connect", at: day), ["Can't connect"], "no sheet: at once")

        let sheet = hold.sheetLeaving(at: day)
        XCTAssertEqual(hold.show("Can't connect", at: day + 0.1), [])
        XCTAssertEqual(hold.sheetGone(sheet, at: day + 0.35), ["Can't connect"])
        XCTAssertEqual(hold.sheetGone(sheet, at: day + 0.4), [], "shown once")
        XCTAssertEqual(hold.due(at: day + 2), [], "and not again at the bound")
        XCTAssertEqual(hold.show("Later", at: day + 3), ["Later"], "the sheet has gone: at once")
    }

    /// Nothing held: the sheet's going says nothing, as with its Cancel. Two
    /// sheets going at once: the alert waits for both.
    func testASheetGoingWithNothingHeldAndTwoSheetsGoing() {
        var hold = AlertHold<String>()
        let cancelled = hold.sheetLeaving(at: day)
        XCTAssertEqual(hold.sheetGone(cancelled, at: day + 0.3), [], "Cancel: nothing was asked of it")
        XCTAssertEqual(hold.show("At once", at: day + 0.4), ["At once"])

        let first = hold.sheetLeaving(at: day + 1)
        let second = hold.sheetLeaving(at: day + 1.1)
        XCTAssertEqual(hold.show("Held", at: day + 1.2), [])
        XCTAssertEqual(hold.sheetGone(first, at: day + 1.3), [])
        XCTAssertEqual(hold.sheetGone(second, at: day + 1.4), ["Held"])
    }

    /// A dismissal UIKit ignores, as one asked for in the middle of a swipe
    /// down, never reports that the sheet has gone. The hold ends at its
    /// bound anyway, with the alert it held, and alerts go at once after
    /// it. It used to end only at the report, so one that never came held
    /// every alert in the app from then on, and dropped all but the first.
    func testASheetThatNeverReportsGoingIsWaitedForOnlySoLong() {
        var hold = AlertHold<String>()
        let sheet = hold.sheetLeaving(at: day)
        XCTAssertEqual(hold.show("Can't connect", at: day + 0.2), [])
        XCTAssertEqual(hold.due(at: day + AlertHold<String>.bound - 0.1), [], "still sliding")
        XCTAssertEqual(hold.due(at: day + AlertHold<String>.bound), ["Can't connect"])
        XCTAssertEqual(hold.show("Can't connect", at: day + 5), ["Can't connect"], "no longer held")
        XCTAssertEqual(hold.sheetGone(sheet, at: day + 6), [], "a report that comes late changes nothing")

        // A late report ends only its own sheet's wait, not another's.
        let late = hold.sheetLeaving(at: day + 10)
        let next = hold.sheetLeaving(at: day + 12)
        XCTAssertEqual(hold.show("Held", at: day + 12.1), [])
        XCTAssertEqual(hold.sheetGone(late, at: day + 12.2), [], "the next sheet is still going")
        XCTAssertEqual(hold.sheetGone(next, at: day + 12.3), ["Held"])
    }

    /// Two alerts while the sheet goes: both are kept, and tried latest
    /// first. The first can be for a list a jump into All Mail has replaced
    /// during the slide, with nothing left to show it over, and the second
    /// used to be dropped for being second, so neither was seen.
    func testEveryAlertHeldIsTriedLatestFirst() {
        var hold = AlertHold<String>()
        let sheet = hold.sheetLeaving(at: day)
        XCTAssertEqual(hold.show("For the list replaced", at: day + 0.1), [])
        XCTAssertEqual(hold.show("For the list now", at: day + 0.2), [])
        XCTAssertEqual(hold.sheetGone(sheet, at: day + 0.35),
                       ["For the list now", "For the list replaced"])
        XCTAssertEqual(hold.due(at: day + 2), [], "tried once")
    }

    // MARK: - A draft on its way to the composer

    /// A second tap on a draft being downloaded does nothing: it used to
    /// download it again. Once it has come, a tap opens it again.
    func testASecondTapOnTheDraftBeingFetchedDoesNothing() {
        var drafts = DraftOpening()
        XCTAssertTrue(drafts.tap("5/12"))
        XCTAssertEqual(drafts.loading, "5/12")
        XCTAssertFalse(drafts.tap("5/12"))
        XCTAssertTrue(drafts.landed("5/12"))
        XCTAssertNil(drafts.loading)
        XCTAssertTrue(drafts.tap("5/12"), "after it has come, or failed, a tap tries again")
    }

    /// Another draft tapped meanwhile is the one he wants: the first is
    /// neither opened nor said to have failed when it comes back.
    func testAnotherDraftTappedMeanwhileWins() {
        var drafts = DraftOpening()
        XCTAssertTrue(drafts.tap("5/12"))
        XCTAssertTrue(drafts.tap("5/13"))
        XCTAssertFalse(drafts.landed("5/12"))
        XCTAssertEqual(drafts.loading, "5/13")
        XCTAssertTrue(drafts.landed("5/13"))
    }
}
