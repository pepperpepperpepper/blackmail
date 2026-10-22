import XCTest
@testable import Blackmail

/// The steps of a print (`PrintSteps`, B-110): from Print in the Reply
/// sheet, through the letter's page loading and drawn into a PDF, to
/// AirPrint's panel once nothing is over the pane, or an end with none,
/// logged. He is never given a blank page: a page that fails, or draws
/// nothing, is printed in words.
final class PrintStepsTests: XCTestCase {

    private typealias Steps = PrintSteps

    /// Steps taken through `events`, the answer to each.
    private func answers(_ events: [Steps.Event], from steps: inout Steps) -> [Steps.Answer] {
        events.map { steps.take($0) }
    }

    /// Steps drawn into a PDF of `pages` at `at`, from loading.
    private func ready(at: TimeInterval = 100) -> Steps {
        var steps = Steps()
        XCTAssertEqual(steps.take(.finished), .draw)
        XCTAssertEqual(steps.drawn(pages: 2, at: at), .look)
        XCTAssertEqual(steps.step, .ready)
        return steps
    }

    // MARK: - Loading

    func testItsPageFinishedIsDrawn() {
        var steps = Steps()
        XCTAssertEqual(steps.step, .loading)
        XCTAssertEqual(answers([.committed, .finished], from: &steps), [.wait, .draw])
        XCTAssertEqual(steps.step, .drawing)
    }

    /// A page that fails, or whose process ends, is printed in words.
    func testAFailureOrAnEndedProcessIsPrintedInWords() {
        for (event, why) in [(Steps.Event.failed, Steps.WordsWhy.failed), (.processEnded, .ended)] {
            var before = Steps()
            XCTAssertEqual(before.take(event), .drawWords(why))
            var after = Steps()
            XCTAssertEqual(answers([.committed, event], from: &after), [.wait, .drawWords(why)])
            XCTAssertEqual(after.step, .drawing)
        }
    }

    /// The time limit: what has come is drawn if the page has committed,
    /// and the words otherwise. Never the end.
    func testTheTimeLimitDrawsWhatHasCome() {
        var committed = Steps()
        XCTAssertEqual(answers([.committed, .late], from: &committed), [.wait, .draw])
        var not = Steps()
        XCTAssertEqual(not.take(.late), .drawWords(.late))
        XCTAssertEqual(not.step, .drawing)
    }

    /// The app gone to the background while it loads: the end, and no
    /// panel later.
    func testTheAppGoneWhileItLoadsEndsIt() {
        var steps = Steps()
        XCTAssertEqual(answers([.committed, .away], from: &steps), [.wait, .end(.away)])
        XCTAssertEqual(steps.step, .ended)
        XCTAssertEqual(answers([.finished, .late, .failed], from: &steps), [.wait, .wait, .wait])
        XCTAssertEqual(steps.drawn(pages: 3, at: 1), .wait)
        XCTAssertEqual(steps.look(covered: false, active: true, shown: true, at: 1), .wait)
    }

    /// Once drawing is asked for, nothing that happens after counts.
    func testOnceDrawingNothingElseCounts() {
        var steps = Steps()
        XCTAssertEqual(steps.take(.finished), .draw)
        for event: Steps.Event in [.committed, .finished, .failed, .processEnded, .late, .away] {
            XCTAssertEqual(steps.take(event), .wait, "\(event)")
        }
        XCTAssertEqual(steps.step, .drawing)
    }

    // MARK: - Drawn

    /// Pages: ready. None from the page: the words. None from the words:
    /// the end, with nothing to print.
    func testNoPagesFromThePageIsTheWordsAndFromTheWordsTheEnd() {
        var steps = Steps()
        XCTAssertEqual(steps.take(.finished), .draw)
        XCTAssertEqual(steps.drawn(pages: 0, at: 1), .drawWords(.blank))
        XCTAssertEqual(steps.step, .drawing)
        XCTAssertEqual(steps.drawn(pages: 1, at: 2), .look)
        XCTAssertEqual(steps.step, .ready)

        var blank = Steps()
        XCTAssertEqual(blank.take(.finished), .draw)
        XCTAssertEqual(blank.drawn(pages: 0, at: 1), .drawWords(.blank))
        XCTAssertEqual(blank.drawn(pages: 0, at: 2), .end(.empty))
        XCTAssertEqual(blank.step, .ended)

        var words = Steps()
        XCTAssertEqual(words.take(.failed), .drawWords(.failed))
        XCTAssertEqual(words.drawn(pages: 0, at: 1), .end(.empty))
    }

    // MARK: - Ready, and the look at the pane

    func testAClearPaneHasThePanelAtOnce() {
        var steps = ready()
        XCTAssertEqual(steps.look(covered: false, active: true, shown: true, at: 100), .present)
        XCTAssertEqual(steps.presented(true), .wait)
        XCTAssertEqual(steps.step, .presented)
    }

    /// A sheet over the pane for 9.5 s, looked at every half second, and
    /// then gone: the panel. Over it for 10 s: the end.
    func testThePanelWaitsForThePaneToBeClearForTenSeconds() {
        var steps = ready(at: 100)
        var t = 100.0
        while t < 100 + 9.5 {
            XCTAssertEqual(steps.look(covered: true, active: true, shown: true, at: t), .wait, "\(t)")
            t += Steps.coverRetry
        }
        XCTAssertEqual(steps.look(covered: false, active: true, shown: true, at: 109.5), .present)

        var covered = ready(at: 100)
        XCTAssertEqual(covered.look(covered: true, active: true, shown: true, at: 109.9), .wait)
        XCTAssertEqual(covered.look(covered: true, active: true, shown: true, at: 110), .end(.covered))
        XCTAssertEqual(covered.step, .ended)
        XCTAssertEqual(covered.look(covered: false, active: true, shown: true, at: 110.5), .wait)
    }

    /// The app interrupted for a moment, Control Center or an alert of the
    /// system's, waits, as a sheet does; the app gone ends it.
    func testAnInactiveAppWaitsAndOneGoneEndsIt() {
        var steps = ready(at: 100)
        XCTAssertEqual(steps.look(covered: false, active: false, shown: true, at: 101), .wait)
        XCTAssertEqual(steps.look(covered: false, active: true, shown: true, at: 102), .present)

        var inactive = ready(at: 100)
        XCTAssertEqual(inactive.look(covered: false, active: false, shown: true, at: 110), .end(.covered))

        var away = ready(at: 100)
        XCTAssertEqual(away.look(covered: true, active: true, shown: true, at: 101), .wait)
        XCTAssertEqual(away.take(.away), .end(.away))
        XCTAssertEqual(away.step, .ended)
    }

    /// The pane moved on to another letter, or emptied: the end, covered
    /// or not.
    func testThePaneMovedOnEndsIt() {
        for covered in [false, true] {
            var steps = ready()
            XCTAssertEqual(steps.look(covered: covered, active: true, shown: false, at: 100), .end(.moved))
            XCTAssertEqual(steps.step, .ended)
        }
    }

    /// In ready the page is gone: only the app's going counts.
    func testInReadyOnlyTheAppsGoingCounts() {
        var steps = ready()
        for event: Steps.Event in [.committed, .finished, .failed, .processEnded, .late] {
            XCTAssertEqual(steps.take(event), .wait, "\(event)")
        }
        XCTAssertEqual(steps.step, .ready)
    }

    // MARK: - Presented

    /// The panel refused: the end. Up: nothing after counts.
    func testThePanelRefusedEndsItAndUpNothingCounts() {
        var refused = ready()
        XCTAssertEqual(refused.presented(false), .end(.refused))
        XCTAssertEqual(refused.step, .ended)

        var up = ready()
        XCTAssertEqual(up.presented(true), .wait)
        for event: Steps.Event in [.committed, .finished, .failed, .processEnded, .late, .away] {
            XCTAssertEqual(up.take(event), .wait, "\(event)")
        }
        XCTAssertEqual(up.look(covered: false, active: true, shown: false, at: 200), .wait)
        XCTAssertEqual(up.drawn(pages: 1, at: 200), .wait)
        XCTAssertEqual(up.step, .presented)
        up.end()
        XCTAssertEqual(up.step, .ended)
    }

    /// Print is greyed while a print is made ready: loading, drawing and
    /// ready; never while its panel is up, or after it has ended.
    func testItIsPreparingOnlyUntilThePanel() {
        var steps = Steps()
        XCTAssertTrue(steps.isPreparing)
        _ = steps.take(.finished)
        XCTAssertTrue(steps.isPreparing)
        _ = steps.drawn(pages: 1, at: 0)
        XCTAssertTrue(steps.isPreparing)
        _ = steps.presented(true)
        XCTAssertFalse(steps.isPreparing)
        steps.end()
        XCTAssertFalse(steps.isPreparing)

        var ended = Steps()
        _ = ended.take(.away)
        XCTAssertFalse(ended.isPreparing)
    }

    func testTheTimes() {
        XCTAssertEqual(Steps.timeLimit, 10)
        XCTAssertEqual(Steps.coverRetry, 0.5)
        XCTAssertEqual(Steps.coverLimit, 10)
    }
}
