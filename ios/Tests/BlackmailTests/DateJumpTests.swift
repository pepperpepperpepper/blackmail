import XCTest
@testable import Blackmail

/// Tests for opening a folder at a day rather than at today.
///
/// This is the feature he most needed — getting back to a particular date
/// is the thing he could not do in Mail (D-012) — so the
/// cases here are the ones that would land him on the wrong letter or strand
/// him once he got there, rather than the happy path.
///
/// The view controller is UIKit-gated and absent on this host. What is
/// pinned is the arithmetic underneath it, which is where a jump goes wrong:
/// off by one at the anchor, or an end-of-mailbox flag that stops the list
/// scrolling in the direction he wants.
final class DateJumpTests: XCTestCase {

    /// A mailbox's UIDs as SEARCH ALL returns them: ascending, with gaps.
    private let ascending: [UInt32] = Array(1...200).map { UInt32($0 * 3) }

    // MARK: - Finding the day

    func testTheAnchorIsTheFIRSTLetterOfTheDayNotTheLast() {
        // SENTSINCE matches the chosen day AND everything after it, which
        // for a jump to June is most of the year. Taking the newest match
        // would land him on today's mail every single time — the feature
        // silently doing nothing.
        let matches: [UInt32] = [30, 33, 60, 600]
        XCTAssertEqual(PageWindow.anchor(forMatches: matches, in: ascending), 30)
    }

    func testNoMailThatRecentIsReportedRatherThanGuessed() {
        // The caller shows "no mail on or after that day". Returning the
        // newest message instead would look like a jump that went to the
        // wrong place.
        XCTAssertNil(PageWindow.anchor(forMatches: [], in: ascending))
    }

    func testAMatchMissingFromTheSnapshotSnapsToTheNextOneAlong() {
        // The SEARCH and the UID snapshot are two round trips. Mail
        // delivered between them is matched but absent; landing on nothing
        // would abandon the jump for a race that resolves itself.
        XCTAssertEqual(PageWindow.anchor(forMatches: [31], in: ascending), 33)
    }

    func testAMatchNewerThanEverythingInTheSnapshotYieldsNothing() {
        XCTAssertNil(PageWindow.anchor(forMatches: [99_999], in: ascending))
    }

    // MARK: - The window around it

    func testTheAnchorSitsBelowSomeNewerMailSoBothDirectionsAreVisible() {
        // Landing the chosen day hard against the top reads as "this is the
        // newest mail there is", which is the one conclusion he must not
        // draw — the whole point is that he can carry on upward.
        let w = PageWindow.window(around: 300, in: ascending, limit: 50)
        XCTAssertEqual(w.anchorIndex, PageWindow.newerRowsAboveAnchor)
        XCTAssertEqual(w.uids[w.anchorIndex], 300)
        XCTAssertEqual(w.uids.count, 50)
        XCTAssertFalse(w.reachedNewest)
        XCTAssertFalse(w.reachedOldest)
    }

    func testTheWindowIsNewestFirstLikeEveryOtherListInTheApp() {
        let w = PageWindow.window(around: 300, in: ascending, limit: 20)
        XCTAssertEqual(w.uids, w.uids.sorted(by: >))
    }

    func testMostOfThePageIsSpentOnOLDERMailBecauseThatIsTheWayHeIsLooking() {
        let w = PageWindow.window(around: 300, in: ascending, limit: 50)
        let older = w.uids.count - w.anchorIndex - 1
        XCTAssertGreaterThan(older, w.anchorIndex)
    }

    func testAJumpNearTheNewestMessageStillFillsAWholePage() {
        // The budget the top of the mailbox could not supply is spent
        // downward instead. Otherwise jumping to last week would show three
        // rows and look like an almost-empty folder.
        let w = PageWindow.window(around: 594, in: ascending, limit: 50)   // 2 newer
        XCTAssertEqual(w.uids.count, 50)
        XCTAssertEqual(w.anchorIndex, 2)
        XCTAssertTrue(w.reachedNewest, "nothing above it left to load")
        XCTAssertFalse(w.reachedOldest)
    }

    func testAJumpNearTheOLDESTMessageStillFillsAWholePage() {
        let w = PageWindow.window(around: 9, in: ascending, limit: 50)     // 2 older
        XCTAssertEqual(w.uids.count, 50)
        XCTAssertEqual(w.uids[w.anchorIndex], 9)
        XCTAssertTrue(w.reachedOldest)
        XCTAssertFalse(w.reachedNewest)
    }

    func testAFolderSmallerThanOnePageIsEntirelyInTheWindowAndBothEndsAreMarked() {
        let small: [UInt32] = [4, 8, 15, 16, 23, 42]
        let w = PageWindow.window(around: 15, in: small, limit: 50)
        XCTAssertEqual(w.uids, [42, 23, 16, 15, 8, 4])
        XCTAssertEqual(w.anchorIndex, 3)
        XCTAssertTrue(w.reachedNewest)
        XCTAssertTrue(w.reachedOldest)
    }

    func testASmallPageSpendsProportionallyLessOfItselfOnNewerMail() {
        // Ten rows above the anchor is room to scroll up into when the page
        // is fifty. Out of a page of five it would put the day he asked for
        // at the BOTTOM with nothing older loaded — the opposite of what
        // the jump is for. The share is capped at a fifth.
        let w = PageWindow.window(around: 300, in: ascending, limit: 5)
        XCTAssertEqual(w.anchorIndex, 1)
        XCTAssertEqual(w.uids.count, 5)
        XCTAssertGreaterThan(w.uids.count - w.anchorIndex - 1, w.anchorIndex,
                             "most of a small page must still be older mail")
    }

    func testALimitOfOneReturnsTheAnchorAloneRatherThanCrashing() {
        // Degenerate, but the arithmetic subtracts the anchor's own row
        // from the budget and a negative count would build a backwards
        // range — a crash, not a wrong answer.
        let w = PageWindow.window(around: 300, in: ascending, limit: 1)
        XCTAssertEqual(w.uids, [300])
        XCTAssertEqual(w.anchorIndex, 0)
    }

    func testAnAnchorTheSnapshotDoesNotContainYieldsAnEmptyWindow() {
        let w = PageWindow.window(around: 7, in: ascending, limit: 50)
        XCTAssertTrue(w.uids.isEmpty)
    }

    // MARK: - Walking upward from it

    func testTheNewerPageIsTheOneImmediatelyABOVETheCursorNotTheTop() {
        // The asymmetry that is easy to get wrong. Taking a prefix of
        // "everything newer" would jump him to today's mail and leave a
        // hole of four months between that and where he was reading.
        XCTAssertEqual(PageWindow.newer(than: 300, in: ascending, limit: 3),
                       [309, 306, 303])
    }

    func testTheNewerPageIsNewestFirstSoItCanBePrependedWhole() {
        let page = PageWindow.newer(than: 300, in: ascending, limit: 5)
        XCTAssertEqual(page, page.sorted(by: >))
    }

    func testWalkingUpwardReachesTheNewestMessageAndThenStops() {
        var cursor: UInt32 = 570
        var seen: [UInt32] = []
        while true {
            let page = PageWindow.newer(than: cursor, in: ascending, limit: 4)
            if page.isEmpty { break }
            seen.append(contentsOf: page)
            // Prepending, so the next cursor is the NEWEST of what we got.
            cursor = page.first!
        }
        XCTAssertEqual(seen.sorted(), Array(stride(from: 573, through: 600, by: 3)))
        XCTAssertEqual(Set(seen).count, seen.count, "a message was repeated")
    }

    func testAShortUpwardPageIsHowTheTopIsRecognised() {
        // Same rule as the downward walk: there is no count from the
        // server, so a short page is the only signal.
        XCTAssertEqual(PageWindow.newer(than: 594, in: ascending, limit: 50).count, 2)
        XCTAssertTrue(PageWindow.newer(than: 600, in: ascending, limit: 50).isEmpty)
    }

    func testTheTwoDirectionsNeverReturnTheSameMessage() {
        // A message appearing both above and below the anchor would be a
        // duplicated row, which is a letter that cannot be told from its
        // twin.
        let up = Set(PageWindow.newer(than: 300, in: ascending, limit: 10))
        let down = Set(PageWindow.older(than: 300, in: ascending, limit: 10))
        XCTAssertTrue(up.isDisjoint(with: down))
        XCTAssertFalse(up.contains(300))
        XCTAssertFalse(down.contains(300))
    }

    func testTheWindowJoinsUpWithWhatPagingWouldFetchNextInEitherDirection() {
        // The seam that matters on device: no gap and no overlap between
        // the jump's window and the pages loaded by scrolling away from it.
        let w = PageWindow.window(around: 300, in: ascending, limit: 20)
        let below = PageWindow.older(than: w.uids.last!, in: ascending, limit: 5)
        let above = PageWindow.newer(than: w.uids.first!, in: ascending, limit: 5)

        XCTAssertEqual(above.last! - w.uids.first!, 3, "a message is missing above")
        XCTAssertEqual(w.uids.last! - below.first!, 3, "a message is missing below")
        let all = Set(above) .union(w.uids) .union(below)
        XCTAssertEqual(all.count, above.count + w.uids.count + below.count)
    }

    // MARK: - Landing on his day (B-058)

    /// Hours from midnight of his day: the window's rows' dates, newest
    /// first, as `PageWindow.landing` is given them.
    private func hours(_ list: [Double]) -> [Date] {
        list.map { Date(timeIntervalSince1970: 1_000_000 + $0 * 3_600) }
    }
    private var midnight: Date { Date(timeIntervalSince1970: 1_000_000) }
    /// Midnight UTC of his date, from which Gmail's SEARCH counted: four
    /// hours before his midnight in Boston, nine after it in Tokyo.
    private var boston: Date { midnight.addingTimeInterval(-4 * 3_600) }
    private var tokyo: Date { midnight.addingTimeInterval(9 * 3_600) }
    /// A week after today, past which a row is dated wrong.
    private var notAfter: Date { midnight.addingTimeInterval(30 * 86_400) }

    private func land(_ list: [Double], _ anchor: Int, from searchedFrom: Date) -> Int {
        PageWindow.landing(dates: hours(list), anchor: anchor, dayStart: midnight,
                           searchedFrom: searchedFrom, notAfter: notAfter)
    }

    /// The SEARCH landed on 9.30 pm the evening before: up to the nearest
    /// newer row on or after his day, past newer rows of that evening too.
    /// On a day with no mail of its own, that is the next day's first.
    func testALandingTheEveningBeforeMovesUpToHisDay() {
        XCTAssertEqual(land([30, 9, -1, -2.5, -30], 3, from: boston), 1)
        XCTAssertEqual(land([50, -1, -2], 1, from: boston), 0)
    }

    /// East of Greenwich the SEARCH landed on his day after its first
    /// hours: down over the older rows of those hours, and no further, not
    /// past a row of the day before to one of his day beyond it.
    func testALandingOnHisDayMovesDownOverItsFirstHoursAlone() {
        XCTAssertEqual(land([20, 10, 2, 1, -5], 1, from: tokyo), 3)
        XCTAssertEqual(land([20, 10, -5], 1, from: tokyo), 1)
        XCTAssertEqual(land([20, 10, -5, 3], 1, from: tokyo), 1)
    }

    /// West of Greenwich there are no such hours: a row below the landing
    /// dated on or after his day is one the SEARCH left out, dated wrong
    /// (it arrived long before), and is not moved onto.
    func testWestOfGreenwichALandingNeverMovesDown() {
        XCTAssertEqual(land([20, 10, 2, 1, -5], 1, from: boston), 1)
        XCTAssertEqual(land([20, 10, 24.0 * 5], 1, from: boston), 1)
    }

    /// A letter stamped at his midnight is on his day: landed on from the
    /// evening before, and not moved up from.
    func testHisMidnightIsHisDay() {
        XCTAssertEqual(land([5, 0, -1], 2, from: boston), 1)
        XCTAssertEqual(land([5, 0, -1], 1, from: boston), 1)
    }

    /// A row dated more than a week ahead is dated wrong and never landed
    /// on, above or below; a landing that is one moves up as one dated
    /// before his day does; with no row on or after his day above it, the
    /// landing stays where the SEARCH put it.
    func testARowDatedWrongIsNeverLandedOnAndNoneOfHisDayStays() {
        let wrong = 24.0 * 365 * 10
        XCTAssertEqual(land([wrong, -1, -3], 1, from: boston), 1)
        XCTAssertEqual(land([5, 3, wrong, -4], 1, from: tokyo), 1)
        XCTAssertEqual(land([5, wrong, -1], 1, from: boston), 0)
        XCTAssertEqual(land([-1, -2], 1, from: boston), 1)
        XCTAssertEqual(PageWindow.landing(dates: [], anchor: 0, dayStart: midnight,
                                          searchedFrom: boston, notAfter: notAfter), 0)
    }
}
