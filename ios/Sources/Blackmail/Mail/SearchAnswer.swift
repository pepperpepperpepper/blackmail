import Foundation

/// What the message list does with a search's answer once it is back on the
/// main actor: draw the hits, say the search could not be run, or leave the
/// screen alone.
///
/// Out of `MessageListViewController` for the reason `PreviewPass` is: the
/// controller is UIKit and does not exist on the machine the suite runs on,
/// so a rule that lived there could be reverted with every test still green.
enum SearchAnswer: Equatable {
    case draw([MessageSummary])
    /// "Could not search", which is for a search that really failed.
    case failed
    /// A search that has been replaced, or a list that has moved on.
    case ignore

    /// `cancelled` is whether the search's task had been cancelled by the
    /// time its answer reached the main actor, and `current` whether the
    /// list is still the one the search was run for.
    ///
    /// A cancelled search is ignored whichever way it ended. The next
    /// keystroke cancels it, and the generation check does not cover the
    /// gap that follows: the replacement bumps the list's generation only
    /// when its own debounce runs out. So a search that failed in that gap
    /// used to empty the list and say "Could not search" while he was
    /// still typing. And one that succeeded, cancelled while its answer was
    /// hopping back to the main actor, drew hits for a query he had already
    /// typed past, until the next search replaced them. A
    /// `CancellationError` is ignored even with the task's own flag clear,
    /// because it can only mean a search was called off, never that one
    /// could not be run.
    static func settle(_ outcome: Result<[MessageSummary], Error>,
                       cancelled: Bool, current: Bool) -> SearchAnswer {
        guard !cancelled, current else { return .ignore }
        switch outcome {
        case .success(let hits):
            return .draw(hits)
        case .failure(let error):
            return error is CancellationError ? .ignore : .failed
        }
    }
}
