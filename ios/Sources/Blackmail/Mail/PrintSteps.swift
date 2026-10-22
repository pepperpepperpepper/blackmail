import Foundation

/// The steps of one print of a letter (B-110), from Print in the Reply
/// sheet to AirPrint's panel: what each thing that happens on the way
/// means, and what is done next.
///
/// Out of `LetterPrint` for the reason `PaneLoads` and `PictureRequests`
/// are out of their UIKit and WebKit: `LetterPrint` does not exist on the
/// machine the suite runs on, so a rule that lived there could be undone
/// with every test green.
///
/// The letter is drawn into a PDF first, while the app is in front and the
/// page in its window, and the panel is given the PDF: plain bytes, which
/// nothing of WebKit or the pane is behind. So the steps are: its page
/// loading; drawing; the PDF ready, waiting for the pane to be clear for the
/// panel; the panel presented; and the end. He is never given nothing: a
/// page that fails, or draws no pages, is printed in words instead.
struct PrintSteps {

    enum Step: Equatable {
        case loading, drawing, ready, presented, ended
    }

    /// What happens to the job. `committed`, `finished` and `failed` are
    /// its own page's navigation's; another navigation that commits in the
    /// page is `failed`, as the page is no longer the job's, and another's
    /// failure is nothing. `processEnded` is WebKit's content process gone,
    /// `late` the time limit, `away` the app gone to the background.
    enum Event: Equatable {
        case committed, finished, failed, processEnded, late, away
    }

    /// Why the letter is printed in words, for the log.
    enum WordsWhy: String, Equatable {
        /// Its page failed to load, or another page took its place.
        case failed
        /// WebKit's content process ended.
        case ended
        /// The time limit came before the page had begun to draw.
        case late
        /// The page drew no pages.
        case blank
    }

    /// Why a job ends with no panel, for the log.
    enum EndWhy: String, Equatable {
        case away, moved, covered, refused, empty
    }

    enum Answer: Equatable {
        /// Nothing to do now.
        case wait
        /// Draw the page.
        case draw
        /// Draw the letter in words.
        case drawWords(WordsWhy)
        /// The PDF is made: look at the pane, now and every `coverRetry`.
        case look
        /// Show the panel.
        case present
        /// End, with no panel.
        case end(EndWhy)
    }

    /// How long the page has to load, from the tap: then it is drawn with
    /// what has come, or in words if nothing of it has.
    static let timeLimit: TimeInterval = 10
    /// How often the pane is looked at again while something is over it.
    static let coverRetry: TimeInterval = 0.5
    /// How long, from the PDF made, the panel waits for the pane to be
    /// clear before the job ends.
    static let coverLimit: TimeInterval = 10

    private(set) var step = Step.loading
    /// The page's navigation has committed: there is something to draw.
    private var committed = false
    /// The words were drawn, not the page.
    private var inWords = false
    /// When the PDF was made, for `coverLimit`.
    private var readyAt: TimeInterval = 0

    /// True from the tap until the panel is up or the job has ended: while
    /// Print in the Reply sheet is greyed.
    var isPreparing: Bool { step == .loading || step == .drawing || step == .ready }

    /// Something has happened to the job.
    mutating func take(_ event: Event) -> Answer {
        switch step {
        case .loading:
            switch event {
            case .committed:
                committed = true
                return .wait
            case .finished:
                return drawing(.draw)
            case .failed:
                return drawing(.drawWords(.failed))
            case .processEnded:
                return drawing(.drawWords(.ended))
            case .late:
                return drawing(committed ? .draw : .drawWords(.late))
            case .away:
                step = .ended
                return .end(.away)
            }
        case .ready:
            // The page is gone by now; only the app's going counts.
            guard event == .away else { return .wait }
            step = .ended
            return .end(.away)
        case .drawing, .presented, .ended:
            return .wait
        }
    }

    private mutating func drawing(_ answer: Answer) -> Answer {
        step = .drawing
        if case .drawWords = answer { inWords = true }
        return answer
    }

    /// The drawing has made `pages` pages, at `now`. Any pages: the PDF is
    /// ready. None from the page: the words are drawn instead. None from the
    /// words: the end, with nothing to print.
    mutating func drawn(pages: Int, at now: TimeInterval) -> Answer {
        guard step == .drawing else { return .wait }
        if pages > 0 {
            step = .ready
            readyAt = now
            return .look
        }
        if inWords {
            step = .ended
            return .end(.empty)
        }
        inWords = true
        return .drawWords(.blank)
    }

    /// A look at the pane with the PDF ready, at `now`: `covered` when
    /// something is presented over it, `active` when the app is in front
    /// and not interrupted, `shown` while it still shows the letter. Shown,
    /// clear and active: the panel. The pane moved on: the end. Otherwise
    /// it waits, looked at again every `coverRetry`, for `coverLimit` from
    /// the PDF made, and then ends. A moment's interruption, Control Center
    /// or an alert of the system's, waits; the app gone is `away`.
    mutating func look(covered: Bool, active: Bool, shown: Bool, at now: TimeInterval) -> Answer {
        guard step == .ready else { return .wait }
        guard shown else {
            step = .ended
            return .end(.moved)
        }
        if !covered && active { return .present }
        guard now - readyAt < Self.coverLimit else {
            step = .ended
            return .end(.covered)
        }
        return .wait
    }

    /// The panel was asked for: `shown` is UIKit's answer.
    mutating func presented(_ shown: Bool) -> Answer {
        guard step == .ready else { return .wait }
        guard shown else {
            step = .ended
            return .end(.refused)
        }
        step = .presented
        return .wait
    }

    /// The job has ended, whichever way.
    mutating func end() {
        step = .ended
    }
}
