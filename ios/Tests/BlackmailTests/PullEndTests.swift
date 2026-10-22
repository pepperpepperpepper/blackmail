import XCTest
@testable import Blackmail

/// When the pull's spinner goes once its page has answered, and when a
/// page's alert goes up (B-103), as `PullEnd` and `LetGoHold` decide. Seen
/// on the test iPad on 2026-10-22: put away as the list sprang back, the
/// spinner left the list 60 pt below its top; put up under a pull still
/// held, the alert took the end of the drag and left the list pulled down
/// with the spinner turning. Their wiring in the list is `PullRefreshTests`'.
final class PullEndTests: XCTestCase {

    // MARK: - The spinner

    /// Every one of the eight: held only while the spinner turns and the
    /// list moves with no finger on it. Under a finger UIKit ends it as the
    /// finger lets go, and with the list still it takes the list to its top
    /// itself; with no spinner there is nothing to wait for.
    func testTheSpinnerIsHeldOnlyWhileTheListMovesWithNoFingerOnIt() {
        for spinning in [false, true] {
            for fingerDown in [false, true] {
                for moving in [false, true] {
                    var end = PullEnd()
                    let answer = end.answered(spinning: spinning, fingerDown: fingerDown,
                                              moving: moving)
                    let held = spinning && !fingerDown && moving
                    XCTAssertEqual(answer, held ? .held(1) : .now,
                                   "spinning \(spinning), finger \(fingerDown), moving \(moving)")
                    XCTAssertEqual(end.holding, held ? 1 : nil)
                }
            }
        }
    }

    /// A held end goes as the list comes to rest, or a finger takes it, and
    /// once: the bound then finds nothing left to put away.
    func testAHeldEndGoesOnceAsTheListComesToRest() {
        var end = PullEnd()
        XCTAssertFalse(end.settled(), "nothing held, nothing to put away")
        XCTAssertEqual(end.answered(spinning: true, fingerDown: false, moving: true), .held(1))
        XCTAssertTrue(end.settled())
        XCTAssertNil(end.holding)
        XCTAssertFalse(end.settled(), "once")
        XCTAssertFalse(end.due(1), "the bound after the rest puts nothing away")
    }

    /// One UIKit never says has come to rest goes when the bound has gone
    /// by, and once: no way through leaves the spinner turning.
    func testAHeldEndGoesAtTheBoundWhenNoRestIsReported() {
        var end = PullEnd()
        XCTAssertEqual(end.answered(spinning: true, fingerDown: false, moving: true), .held(1))
        XCTAssertTrue(end.due(1))
        XCTAssertNil(end.holding)
        XCTAssertFalse(end.due(1), "once")
        XCTAssertFalse(end.settled(), "the rest after the bound puts nothing away")
    }

    /// Put away at once, as the list leaves the screen or the pull goes off
    /// it: nothing is left held, for the rest or the bound to put away.
    func testAnEndPutAwayAtOnceLeavesNothingHeld() {
        var end = PullEnd()
        XCTAssertEqual(end.answered(spinning: true, fingerDown: false, moving: true), .held(1))
        end.putAway()
        XCTAssertNil(end.holding)
        XCTAssertFalse(end.settled())
        XCTAssertFalse(end.due(1))
    }

    /// The bound of a hold since put away, or one a later answer has taken
    /// the place of, puts nothing away: only the hold now waiting is due.
    /// A later answer that goes at once leaves no hold for an earlier bound.
    func testOnlyTheHoldNowWaitingIsDue() {
        var end = PullEnd()
        XCTAssertEqual(end.answered(spinning: true, fingerDown: false, moving: true), .held(1))
        XCTAssertEqual(end.answered(spinning: true, fingerDown: false, moving: true), .held(2))
        XCTAssertFalse(end.due(1))
        XCTAssertEqual(end.holding, 2)
        XCTAssertTrue(end.due(2))

        XCTAssertEqual(end.answered(spinning: true, fingerDown: false, moving: true), .held(3))
        XCTAssertEqual(end.answered(spinning: true, fingerDown: true, moving: true), .now)
        XCTAssertNil(end.holding)
        XCTAssertFalse(end.due(3))
        XCTAssertFalse(end.settled())
    }

    /// Moving: coasting or springing back, or past the top by more than
    /// half a point, the spinner's room counted in the top. At the top, or
    /// within half a point of it, or anywhere below it, still. The numbers
    /// are the iPad's three panes: 74 pt of bars, 60 of spinner.
    func testWhatCountsAsMoving() {
        let bars = 74.0, spinner = 60.0
        // Springing back with the spinner turning: its room is in the inset.
        XCTAssertTrue(PullEnd.moving(decelerating: true, offset: -(bars + spinner),
                                     topInset: bars + spinner))
        XCTAssertTrue(PullEnd.moving(decelerating: true, offset: 400, topInset: bars),
                      "coasting far down the list")
        // At the spinner's rest, and at the top with no spinner.
        XCTAssertFalse(PullEnd.moving(decelerating: false, offset: -(bars + spinner),
                                      topInset: bars + spinner))
        XCTAssertFalse(PullEnd.moving(decelerating: false, offset: -bars, topInset: bars))
        XCTAssertFalse(PullEnd.moving(decelerating: false, offset: -bars - 0.5, topInset: bars))
        XCTAssertFalse(PullEnd.moving(decelerating: false, offset: 400, topInset: bars))
        // Past the top: the 60 pt the iPad showed, and 168 pt pulled down.
        XCTAssertTrue(PullEnd.moving(decelerating: false, offset: -bars - 0.6, topInset: bars))
        XCTAssertTrue(PullEnd.moving(decelerating: false, offset: -(bars + spinner), topInset: bars))
        XCTAssertTrue(PullEnd.moving(decelerating: false, offset: -(bars + 168),
                                     topInset: bars + spinner))
    }

    /// The bound is a few times the spring-back, which took about half a
    /// second: long enough never to cut one short, short enough that a
    /// spinner nobody reports the rest for goes soon after.
    func testTheBoundIsAFewTimesTheSpringBack() {
        XCTAssertEqual(PullEnd.bound, 2)
    }

    // MARK: - The alert

    /// With his finger on the list the alert waits, and goes up as it lets
    /// go, once.
    func testAnAlertWaitsForTheFingerToLetGo() {
        var hold = LetGoHold<String>()
        XCTAssertNil(hold.show("Can't connect", fingerDown: true))
        XCTAssertEqual(hold.held, "Can't connect")
        XCTAssertEqual(hold.letGo(), "Can't connect")
        XCTAssertNil(hold.held)
        XCTAssertNil(hold.letGo(), "once")
    }

    /// With no finger on the list it goes up at once, as it always did, and
    /// one held before it is not put up after it: one alert at a time.
    func testAnAlertWithNoFingerOnTheListGoesUpAtOnce() {
        var hold = LetGoHold<String>()
        XCTAssertEqual(hold.show("Can't connect", fingerDown: false), "Can't connect")
        XCTAssertNil(hold.held)
        XCTAssertNil(hold.letGo())

        XCTAssertNil(hold.show("first", fingerDown: true))
        XCTAssertNil(hold.show("second", fingerDown: true), "the later in the first's place")
        XCTAssertEqual(hold.held, "second")
        XCTAssertEqual(hold.show("third", fingerDown: false), "third")
        XCTAssertNil(hold.letGo(), "nothing held left to follow it")
    }

    /// The list gone from the screen: the alert held is not put up later.
    func testAHeldAlertIsDroppedAsTheListLeaves() {
        var hold = LetGoHold<String>()
        XCTAssertNil(hold.show("Can't connect", fingerDown: true))
        hold.drop()
        XCTAssertNil(hold.held)
        XCTAssertNil(hold.letGo())
    }
}
