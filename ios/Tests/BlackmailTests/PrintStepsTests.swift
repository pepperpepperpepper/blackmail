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

    /// Steps with the page and its words made, and the page loading.
    private func loaded() -> Steps {
        var steps = Steps()
        XCTAssertEqual(steps.take(.built), .load)
        XCTAssertEqual(steps.step, .loading)
        return steps
    }

    /// Steps drawn into a PDF of `pages` at `at`, from loading.
    private func ready(at: TimeInterval = 100) -> Steps {
        var steps = loaded()
        XCTAssertEqual(steps.take(.finished), .draw)
        XCTAssertEqual(steps.drawn(pages: 2, at: at), .look)
        XCTAssertEqual(steps.step, .ready)
        return steps
    }

    // MARK: - Made, and loading

    /// The page is loaded once it and its words are made, and nothing of
    /// its navigation counts before: nothing is drawn before the words are
    /// there to fall back on.
    func testThePageIsLoadedOnceItAndItsWordsAreMade() {
        var steps = Steps()
        XCTAssertEqual(steps.step, .loading)
        XCTAssertTrue(steps.isPreparing)
        XCTAssertEqual(answers([.committed, .finished, .failed, .processEnded], from: &steps),
                       [.wait, .wait, .wait, .wait])
        XCTAssertEqual(steps.step, .loading)
        XCTAssertEqual(steps.take(.built), .load)
        XCTAssertEqual(steps.step, .loading)
        XCTAssertEqual(steps.take(.built), .wait, "made once")
        XCTAssertEqual(steps.take(.finished), .draw, "the navigation before the page counted for nothing")
        XCTAssertFalse(steps.inWords)

        var early = Steps()
        XCTAssertEqual(answers([.committed, .built, .late], from: &early), [.wait, .load, .drawWords(.late)],
                       "a commit before the page is not its page's")
    }

    /// The time limit before the page is made: the words, as soon as they
    /// are, and never a job left waiting. Until then the app's going and
    /// the pane's moving on end it as in loading.
    func testTheTimeLimitBeforeThePageIsMadeDrawsTheWordsOnceTheyAre() {
        var steps = Steps()
        XCTAssertEqual(steps.take(.late), .wait)
        XCTAssertEqual(steps.step, .loading)
        XCTAssertTrue(steps.isPreparing)
        XCTAssertEqual(steps.take(.built), .drawWords(.late), "the words, not the page loaded")
        XCTAssertEqual(steps.step, .drawing)
        XCTAssertTrue(steps.inWords)
        XCTAssertEqual(steps.drawn(pages: 2, at: 1), .look)
        XCTAssertEqual(steps.step, .ready)

        var none = Steps()
        XCTAssertEqual(answers([.late, .built], from: &none), [.wait, .drawWords(.late)])
        XCTAssertEqual(none.drawn(pages: 0, at: 1), .end(.empty))

        var away = Steps()
        XCTAssertEqual(answers([.late, .away, .built], from: &away), [.wait, .end(.away), .wait])
        XCTAssertEqual(away.step, .ended)

        var moved = Steps()
        XCTAssertEqual(moved.take(.late), .wait)
        XCTAssertEqual(moved.look(covered: false, active: true, shown: false, at: 1), .end(.moved))
        XCTAssertEqual(moved.take(.built), .wait)
        XCTAssertEqual(moved.step, .ended)
    }

    func testItsPageFinishedIsDrawn() {
        var steps = loaded()
        XCTAssertEqual(answers([.committed, .finished], from: &steps), [.wait, .draw])
        XCTAssertEqual(steps.step, .drawing)
        XCTAssertFalse(steps.inWords)
    }

    /// A page that fails, or whose process ends, is printed in words.
    func testAFailureOrAnEndedProcessIsPrintedInWords() {
        for (event, why) in [(Steps.Event.failed, Steps.WordsWhy.failed), (.processEnded, .ended)] {
            var before = loaded()
            XCTAssertEqual(before.take(event), .drawWords(why))
            XCTAssertTrue(before.inWords)
            var after = loaded()
            XCTAssertEqual(answers([.committed, event], from: &after), [.wait, .drawWords(why)])
            XCTAssertEqual(after.step, .drawing)
            XCTAssertTrue(after.inWords)
        }
    }

    /// The time limit: what has come is drawn if the page has committed,
    /// and the words otherwise. Never the end.
    func testTheTimeLimitDrawsWhatHasCome() {
        var committed = loaded()
        XCTAssertEqual(answers([.committed, .late], from: &committed), [.wait, .draw])
        XCTAssertFalse(committed.inWords)
        var not = loaded()
        XCTAssertEqual(not.take(.late), .drawWords(.late))
        XCTAssertEqual(not.step, .drawing)
        XCTAssertTrue(not.inWords)
    }

    /// The app gone to the background while it loads: the end, and no
    /// panel later.
    func testTheAppGoneWhileItLoadsEndsIt() {
        var steps = loaded()
        XCTAssertEqual(answers([.committed, .away], from: &steps), [.wait, .end(.away)])
        XCTAssertEqual(steps.step, .ended)
        XCTAssertEqual(answers([.finished, .late, .failed, .built], from: &steps), [.wait, .wait, .wait, .wait])
        XCTAssertEqual(steps.drawn(pages: 3, at: 1), .wait)
        XCTAssertEqual(steps.look(covered: false, active: true, shown: true, at: 1), .wait)

        var unmade = Steps()
        XCTAssertEqual(answers([.away, .built], from: &unmade), [.end(.away), .wait])
    }

    /// The pane moved on, another letter tapped or the pane emptied, while
    /// the page is made or loads: the end at that look, not at the drawing,
    /// so its pictures are not asked for ahead of the letter he went to.
    /// Shown, nothing else counts while it loads: no panel before the PDF,
    /// covered or not, active or not.
    func testThePaneMovedOnWhileItLoadsEndsIt() {
        for made in [false, true] {
            var steps = made ? loaded() : Steps()
            for (covered, active) in [(false, true), (true, true), (false, false), (true, false)] {
                XCTAssertEqual(steps.look(covered: covered, active: active, shown: true, at: 1_000), .wait)
            }
            XCTAssertEqual(steps.step, .loading)
            XCTAssertEqual(steps.look(covered: false, active: true, shown: false, at: 1_001), .end(.moved))
            XCTAssertEqual(steps.step, .ended)
            XCTAssertFalse(steps.isPreparing)
            XCTAssertEqual(answers([.built, .committed, .finished, .late], from: &steps),
                           [.wait, .wait, .wait, .wait])
        }
    }

    /// Once drawing is asked for, nothing that happens after counts.
    func testOnceDrawingNothingElseCounts() {
        var steps = loaded()
        XCTAssertEqual(steps.take(.finished), .draw)
        for event: Steps.Event in [.built, .committed, .finished, .failed, .processEnded, .late, .away] {
            XCTAssertEqual(steps.take(event), .wait, "\(event)")
        }
        XCTAssertEqual(steps.look(covered: false, active: true, shown: false, at: 1), .wait)
        XCTAssertEqual(steps.step, .drawing)
        XCTAssertFalse(steps.inWords)
    }

    // MARK: - Drawn

    /// Pages: ready. None from the page: the words. None from the words:
    /// the end, with nothing to print.
    func testNoPagesFromThePageIsTheWordsAndFromTheWordsTheEnd() {
        var steps = loaded()
        XCTAssertEqual(steps.take(.finished), .draw)
        XCTAssertFalse(steps.inWords)
        XCTAssertEqual(steps.drawn(pages: 0, at: 1), .drawWords(.blank))
        XCTAssertEqual(steps.step, .drawing)
        XCTAssertTrue(steps.inWords, "drawn again in words, never from the page again")
        XCTAssertEqual(steps.drawn(pages: 1, at: 2), .look)
        XCTAssertEqual(steps.step, .ready)

        var blank = loaded()
        XCTAssertEqual(blank.take(.finished), .draw)
        XCTAssertEqual(blank.drawn(pages: 0, at: 1), .drawWords(.blank))
        XCTAssertEqual(blank.drawn(pages: 0, at: 2), .end(.empty))
        XCTAssertEqual(blank.step, .ended)

        var words = loaded()
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
        for event: Steps.Event in [.built, .committed, .finished, .failed, .processEnded, .late] {
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
        for event: Steps.Event in [.built, .committed, .finished, .failed, .processEnded, .late, .away] {
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
        _ = steps.take(.built)
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
        // A letter's PDFs have 4 s to come and their pages 7 s to be
        // drawn, from the tap, so the page has the rest to load (B-185).
        XCTAssertEqual(Steps.pdfFetchLimit, 4)
        XCTAssertEqual(Steps.pdfDrawLimit, 7)
        XCTAssertLessThan(Steps.pdfFetchLimit, Steps.pdfDrawLimit)
        XCTAssertLessThan(Steps.pdfDrawLimit, Steps.timeLimit)
        XCTAssertEqual(Steps.coverRetry, 0.5)
        XCTAssertEqual(Steps.coverLimit, 10)
    }
}
