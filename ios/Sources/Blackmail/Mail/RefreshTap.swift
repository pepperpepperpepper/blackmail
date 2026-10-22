import Foundation

/// His Refresh, in its order (B-072): the folder's newest page, then the
/// folder counts, and once both have come, the pass over the letters kept
/// on the iPad that sends every letter waiting in the Outbox, a large one
/// too (`LocalDrafts.Pass.refresh`).
///
/// The owner's rule, to match Mail: Refresh sends what waits in the
/// Outbox. A letter in the Outbox whose files come from Gmail first, a
/// forward of a video, fetches them over the one IMAP connection, and an
/// exchange on the wire is never cut short (`IMAPClient.Priority`). That
/// fetch waits in the line his taps wait in, ahead of the previews and the
/// counts, so it is asked for only once they have come: what he asked to
/// see is not held behind it.
///
/// A page that could not be fetched sets no pass off, as before: there is
/// no connection for one. The counts are asked for whether or not it came,
/// as Refresh has always asked for them.
///
/// The Refresh button and the pull down past the top of the list are the
/// same Refresh (B-103), one page of it out at a time (`Gate`, `start`).
///
/// Out of `MessageListViewController` for the reason `SearchAnswer` is: the
/// controller is UIKit and does not exist on the machine the suite runs on.
enum RefreshTap {

    /// `page` fetches the folder's newest page, with no pass of its own, and
    /// says whether it came; one that throws has not. `answered` is called
    /// once, as soon as the page has come, failed or been put aside for
    /// another list, before anything else: the pull's spinner ends there,
    /// and does not wait for the counts or a large letter in the Outbox.
    /// `counts` asks for the folder counts; `shown` returns once the page's
    /// previews and the counts have come; `pass` sets the Refresh's pass
    /// off.
    @MainActor
    static func run(page: @MainActor () async throws -> Bool,
                    answered: @MainActor () -> Void,
                    counts: @MainActor () -> Void,
                    shown: @MainActor () async -> Void,
                    pass: @MainActor () -> Void) async {
        let came = (try? await page()) ?? false
        answered()
        counts()
        guard came else { return }
        await shown()
        pass()
    }

    /// One page of a Refresh out at a time, the button's or the pull's
    /// (B-103). The Refresh button started a run at every tap, with nothing
    /// to stop a second page going beside the first; a pull that comes
    /// again while the list springs back would do the same.
    ///
    /// Held around the page alone, never the counts or the pass: a run
    /// whose counts or Outbox letter take long leaves Refresh free once its
    /// page has come, as a second tap was before, and the pass keeps itself
    /// to one at a time (`LocalDrafts.uploadWaiting`). The page has the
    /// connection's own deadline, so it always answers, one way or another.
    ///
    /// Each run lets go of its own hold only: a run's end that comes after
    /// the next run has taken the gate leaves that run's hold alone.
    @MainActor
    final class Gate {
        /// The run whose page is out, if one is.
        private var holder: Int?
        private var runs = 0

        /// Whether a page is out.
        var held: Bool { holder != nil }

        /// A new run's number, or nil while a page is out.
        func take() -> Int? {
            guard holder == nil else { return nil }
            runs += 1
            holder = runs
            return runs
        }

        /// `run`'s page has answered, or `run` has ended.
        func release(_ run: Int) {
            if holder == run { holder = nil }
        }
    }

    /// A Refresh, unless a page is out: then nothing is started, and the
    /// page that is out answers for this one too. Returns the run, nil when
    /// none was started.
    ///
    /// The gate is let go as the page answers, and again as the run ends
    /// however it ends, so no way out of a run can leave it held.
    @MainActor
    @discardableResult
    static func start(gate: Gate,
                      page: @escaping @MainActor () async throws -> Bool,
                      answered: @escaping @MainActor () -> Void,
                      counts: @escaping @MainActor () -> Void,
                      shown: @escaping @MainActor () async -> Void,
                      pass: @escaping @MainActor () -> Void) -> Task<Void, Never>? {
        guard let run = gate.take() else { return nil }
        return Task { @MainActor in
            defer { gate.release(run) }
            await Self.run(page: page,
                           answered: {
                               gate.release(run)
                               answered()
                           },
                           counts: counts, shown: shown, pass: pass)
        }
    }
}

/// Where the pull down past the top of the list checks for mail (B-103):
/// only where a fetch of the newest page can neither move him nor wipe
/// anything. Not in Edit mode, where it would drop his ticks; not while a
/// search is typed or shows, or the search field has the keyboard, which
/// the page clears; not on a list opened at a day, whose top is not the
/// folder's and where scrolling up fetches the newer pages; and not while
/// the panes move. The Outbox has it, where Refresh sends. The Refresh
/// button is not asked: it is a tap he means, wherever he is.
enum PullRefresh {

    static func allowed(editing: Bool, searching: Bool, fromNewest: Bool, moving: Bool) -> Bool {
        !editing && !searching && fromNewest && !moving
    }
}
