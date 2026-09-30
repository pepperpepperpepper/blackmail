import Foundation

/// The folder pane's sweep of the unread counts, run one at a time and
/// never queued up.
///
/// A sweep is LIST and a STATUS per folder, nine commands on his account,
/// and about eight things ask for one: a Delete, Move or Flag from the
/// reading pane, a delete or move of a selection, Refresh, a Settings save,
/// coming back after a while, launch. Nothing merged them, so a burst of
/// flags queued a whole sweep each, and every one of them ran, in the line
/// the previews and the next page wait in.
///
/// Now one runs at a time. A request while one is running is remembered and
/// exactly one more sweep runs after it, however many requests there were.
/// That one is not optional: the request can come after the running sweep
/// has already counted the folder that changed, as it does when he moves a
/// letter mid-sweep, and a count left like that is the device bug recorded
/// in `RootViewController.bindList`, Inbox reading 6 after an unread letter
/// had left it. The last change is always counted by a sweep that started
/// after it. There is no waiting window in front of a sweep for the same
/// reason: the counts after a Move must come right as soon as the
/// connection allows.
///
/// Held until let go, for launch. The Inbox's first page goes before any
/// count, and requests made meanwhile are one sweep once it has, or none if
/// it could not be fetched.
///
/// On the main actor, with the pane's counts, rather than an actor of its
/// own: `requestIfRunning()` has to know, at the moment a count is changed
/// on screen, whether a sweep's answer is still to land. Asked across a
/// hop, the question could arrive after a stale answer had landed over the
/// change, find nothing running, and ask for nothing.
///
/// Out of `MailboxListViewController` for the reason `SearchAnswer` is: the
/// controller is UIKit and does not exist on the machine the suite runs on.
///
/// A sweep is quiet when nobody but the watch asked for it (B-049): one that
/// fails then leaves the counts as they were rather than putting "Can't
/// connect" over the letter he is reading, since he did nothing. Merged with
/// one he did ask for, it is his, and says so when it fails, as every sweep
/// always has.
@MainActor
final class SweepCoalescer {

    /// One sweep, delivery included, so each is on screen before the next
    /// starts and a slower older one can never land over a newer one. Told
    /// whether it is quiet.
    private let sweep: @MainActor (_ quietly: Bool) async -> Void
    private var held: Bool
    /// From the moment a sweep is started until the last one has been
    /// delivered. Never false while an answer is still to land.
    private var running = false
    /// Asked for since the running sweep started, or since the last one
    /// ended.
    private var owed = false
    /// Some of what is owed was asked for by something other than the watch.
    private var owedLoudly = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(held: Bool = false, sweep: @escaping @MainActor (_ quietly: Bool) async -> Void) {
        self.held = held
        self.sweep = sweep
    }

    /// For a sweep that is the same whoever asked for it.
    convenience init(held: Bool = false, sweep: @escaping @MainActor () async -> Void) {
        self.init(held: held) { _ in await sweep() }
    }

    /// Asks for a sweep. Starts one if none is running and nothing is
    /// holding them; otherwise it is owed, and one more runs afterwards.
    /// `quietly` for the watch's.
    func request(quietly: Bool = false) {
        owed = true
        if !quietly { owedLoudly = true }
        startIfDue()
    }

    /// Asks for one more sweep if one is running, and does nothing if not.
    ///
    /// For a count changed on screen by arithmetic: a letter read, which
    /// takes one off its folders once the server has the flag. A sweep
    /// already running may have counted that folder before the flag went,
    /// and landing afterwards it would put the letter back. The sweep after
    /// it cannot have. With no sweep running the arithmetic stands on the
    /// last one's counts, and costs nothing on the connection.
    ///
    /// Not at launch: nothing can be read before the first page, and the
    /// sweep that follows that page is already owed.
    func requestIfRunning() {
        guard running else { return }
        owed = true
        owedLoudly = true
    }

    /// Lets the sweeps go. With `runningOwed`, a sweep asked for while they
    /// were held runs now; without it, it is dropped.
    ///
    /// At launch the counts are dropped when the Inbox's first page could
    /// not be fetched. The sweep would connect again straight after the
    /// connect that failed, and a refused password would be sent twice,
    /// the retry `IMAPMailRepository` refuses to make. An unreachable
    /// server would hold the connection for a second connect timeout. The
    /// next Refresh sweeps, which is him trying again.
    func release(runningOwed: Bool) {
        held = false
        if !runningOwed {
            owed = false
            owedLoudly = false
        }
        startIfDue()
    }

    /// Returns once no sweep is running or owed, or at once if they are
    /// held. How a test knows the sweeps are over without sleeping on it.
    func idle() async {
        guard running else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func startIfDue() {
        guard !held, !running, owed else { return }
        running = true
        Task { await self.drain() }
    }

    private func drain() async {
        while owed {
            let quietly = !owedLoudly
            owed = false
            owedLoudly = false
            await sweep(quietly)
        }
        running = false
        let waiters = idleWaiters
        idleWaiters = []
        for waiter in waiters { waiter.resume() }
    }
}
