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
        XCTAssertEqual(end.due(1, round: 1, fingerDown: false, moving: false), .gone,
                       "the bound after the rest puts nothing away")
    }

    /// One UIKit never says has come to rest goes when the bound has gone
    /// by with the list still, and once: no way through leaves the spinner
    /// turning.
    func testAHeldEndGoesAtTheBoundWhenNoRestIsReported() {
        var end = PullEnd()
        XCTAssertEqual(end.answered(spinning: true, fingerDown: false, moving: true), .held(1))
        XCTAssertEqual(end.due(1, round: 1, fingerDown: false, moving: false), .now)
        XCTAssertNil(end.holding)
        XCTAssertEqual(end.due(1, round: 1, fingerDown: false, moving: false), .gone, "once")
        XCTAssertFalse(end.settled(), "the rest after the bound puts nothing away")
    }

    /// At the bound, a list still moving with no finger on it is waited for
    /// once more, as after a long flick that ends bouncing off the top: put
    /// away then, it would end mid-spring-back, which left the band on the
    /// iPad. Under a finger, or with the list still, it goes, as at the
    /// answer. After the last round it goes whatever the list does, so the
    /// spinner cannot turn for ever.
    func testAtTheBoundAMovingListIsWaitedForOnceMore() {
        for fingerDown in [false, true] {
            for moving in [false, true] {
                var end = PullEnd()
                XCTAssertEqual(end.answered(spinning: true, fingerDown: false, moving: true),
                               .held(1))
                let waits = !fingerDown && moving
                XCTAssertEqual(end.due(1, round: 1, fingerDown: fingerDown, moving: moving),
                               waits ? .again : .now, "finger \(fingerDown), moving \(moving)")
                XCTAssertEqual(end.holding, waits ? 1 : nil)
            }
        }

        var end = PullEnd()
        XCTAssertEqual(end.answered(spinning: true, fingerDown: false, moving: true), .held(1))
        XCTAssertEqual(end.due(1, round: 1, fingerDown: false, moving: true), .again)
        XCTAssertEqual(end.due(1, round: PullEnd.rounds, fingerDown: false, moving: true), .now,
                       "the last round, still moving")
        XCTAssertNil(end.holding)

        // Waited for again, it still goes at the rest, and the bound after
        // finds it gone.
        var rested = PullEnd()
        XCTAssertEqual(rested.answered(spinning: true, fingerDown: false, moving: true), .held(1))
        XCTAssertEqual(rested.due(1, round: 1, fingerDown: false, moving: true), .again)
        XCTAssertTrue(rested.settled())
        XCTAssertEqual(rested.due(1, round: 2, fingerDown: false, moving: true), .gone)
    }

    /// Put away at once, as the list leaves the screen or the pull goes off
    /// it: nothing is left held, for the rest or the bound to put away.
    func testAnEndPutAwayAtOnceLeavesNothingHeld() {
        var end = PullEnd()
        XCTAssertEqual(end.answered(spinning: true, fingerDown: false, moving: true), .held(1))
        end.putAway()
        XCTAssertNil(end.holding)
        XCTAssertFalse(end.settled())
        XCTAssertEqual(end.due(1, round: 1, fingerDown: false, moving: true), .gone)
    }

    /// The bound of a hold since put away, or one a later answer has taken
    /// the place of, puts nothing away: only the hold now waiting is due.
    /// A later answer that goes at once leaves no hold for an earlier bound.
    func testOnlyTheHoldNowWaitingIsDue() {
        var end = PullEnd()
        XCTAssertEqual(end.answered(spinning: true, fingerDown: false, moving: true), .held(1))
        XCTAssertEqual(end.answered(spinning: true, fingerDown: false, moving: true), .held(2))
        XCTAssertEqual(end.due(1, round: 1, fingerDown: false, moving: false), .gone)
        XCTAssertEqual(end.due(1, round: 1, fingerDown: false, moving: true), .gone)
        XCTAssertEqual(end.holding, 2)
        XCTAssertEqual(end.due(2, round: 1, fingerDown: false, moving: false), .now)

        XCTAssertEqual(end.answered(spinning: true, fingerDown: false, moving: true), .held(3))
        XCTAssertEqual(end.answered(spinning: true, fingerDown: true, moving: true), .now)
        XCTAssertNil(end.holding)
        XCTAssertEqual(end.due(3, round: 1, fingerDown: false, moving: true), .gone)
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
        XCTAssertEqual(PullEnd.rounds, 2, "4 s at most, the spinner turning")
    }

    // MARK: - A band left above the first row

    /// A list come to rest past its top, by more than half a point, with no
    /// spinner turning and no finger on it, is the band the iPad showed:
    /// 60 pt with the spinner put away. Not while the spinner turns, its
    /// room counted in the top, nor under a finger, nor at the top or below
    /// it. The numbers are the iPad's three panes: 74 pt of bars, 60 of
    /// spinner.
    func testABandLeftAboveTheFirstRowIsClosedUp() {
        let bars = 74.0, spinner = 60.0
        XCTAssertTrue(PullEnd.leftPastTop(spinning: false, fingerDown: false,
                                          offset: -(bars + spinner), topInset: bars), "the band")
        XCTAssertTrue(PullEnd.leftPastTop(spinning: false, fingerDown: false,
                                          offset: -bars - 0.6, topInset: bars))
        XCTAssertFalse(PullEnd.leftPastTop(spinning: false, fingerDown: false,
                                           offset: -bars - 0.5, topInset: bars), "the top")
        XCTAssertFalse(PullEnd.leftPastTop(spinning: false, fingerDown: false,
                                           offset: -bars, topInset: bars))
        XCTAssertFalse(PullEnd.leftPastTop(spinning: false, fingerDown: false,
                                           offset: 400, topInset: bars), "far down")
        // The spinner turning at its rest: its room is in the top.
        XCTAssertFalse(PullEnd.leftPastTop(spinning: true, fingerDown: false,
                                           offset: -(bars + spinner), topInset: bars + spinner))
        // Every one of the four past the top: only with no spinner and no
        // finger.
        for spinning in [false, true] {
            for fingerDown in [false, true] {
                XCTAssertEqual(PullEnd.leftPastTop(spinning: spinning, fingerDown: fingerDown,
                                                   offset: -(bars + spinner), topInset: bars),
                               !spinning && !fingerDown,
                               "spinning \(spinning), finger \(fingerDown)")
            }
        }
    }

    // MARK: - The top set

    /// The list sent to its top has its offset set there only where that
    /// moves nothing under him and stops nothing (`ListPlaces.setsTop`):
    /// below the top, as always, moving or not; past it only at rest, the
    /// band left by a spinner put away as the list sprang back; never at
    /// the top, within half a point, where there is nothing to set; and
    /// never past it while a finger holds it or it springs back, where the
    /// offset set stopped the spring-back at the spinner's rest on the iPad.
    func testTheTopIsSetOnlyWhereItStopsNothing() {
        let bars = 74.0, spinner = 60.0
        for moving in [false, true] {
            XCTAssertTrue(ListPlaces.setsTop(offset: 400, topInset: bars, moving: moving),
                          "far down, moving \(moving)")
            XCTAssertTrue(ListPlaces.setsTop(offset: -bars + 0.6, topInset: bars, moving: moving))
            XCTAssertFalse(ListPlaces.setsTop(offset: -bars, topInset: bars, moving: moving),
                           "at the top, moving \(moving)")
            XCTAssertFalse(ListPlaces.setsTop(offset: -bars + 0.5, topInset: bars, moving: moving))
            XCTAssertFalse(ListPlaces.setsTop(offset: -bars - 0.5, topInset: bars, moving: moving))
            // The spinner at its rest: at the top, its room counted.
            XCTAssertFalse(ListPlaces.setsTop(offset: -(bars + spinner), topInset: bars + spinner,
                                              moving: moving))
        }
        // Past the top: springing back to the spinner's rest, held under a
        // finger, left alone; the band at rest, set.
        XCTAssertFalse(ListPlaces.setsTop(offset: -(bars + 150), topInset: bars + spinner,
                                          moving: true))
        XCTAssertFalse(ListPlaces.setsTop(offset: -(bars + spinner), topInset: bars, moving: true))
        XCTAssertTrue(ListPlaces.setsTop(offset: -(bars + spinner), topInset: bars, moving: false),
                      "the band at rest")
        XCTAssertTrue(ListPlaces.setsTop(offset: -bars - 0.6, topInset: bars, moving: false))
        XCTAssertFalse(ListPlaces.setsTop(offset: -bars - 0.6, topInset: bars, moving: true))
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
