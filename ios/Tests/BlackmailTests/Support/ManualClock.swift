import Foundation

/// A clock a test moves by hand, for what the repository and the client
/// time: ninety seconds of quiet before a write's probe, how long ago a
/// mailbox's news was asked for, the watch's half minute between checks.
/// Nothing moves it but `advance`, so the commands a test sends take no time
/// on it, and a sleep on it lasts exactly as long as the test says.
final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_790_000_000)
    private var sleepers: [(id: UInt64, until: Date, wake: CheckedContinuation<Void, Error>)] = []
    private var lastSleeper: UInt64 = 0

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Moves the clock, and wakes every sleep that has run its course.
    func advance(by seconds: TimeInterval) {
        lock.lock()
        current += seconds
        let due = sleepers.filter { $0.until <= current }
        sleepers.removeAll { $0.until <= current }
        lock.unlock()
        for sleeper in due { sleeper.wake.resume() }
    }

    /// How many sleeps are waiting on this clock. How a test knows the
    /// watch is between checks before it moves the clock.
    var sleeping: Int {
        lock.lock()
        defer { lock.unlock() }
        return sleepers.count
    }

    /// Returns once `advance` has moved the clock `seconds` on from now, or
    /// throws `CancellationError` as soon as the task is cancelled, as
    /// `Task.sleep` does.
    func sleep(for seconds: TimeInterval) async throws {
        lock.lock()
        lastSleeper += 1
        let id = lastSleeper
        lock.unlock()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (wake: CheckedContinuation<Void, Error>) in
                lock.lock()
                // Cancelled before it could be put to sleep: the handler
                // below found nothing to wake.
                guard !Task.isCancelled else {
                    lock.unlock()
                    wake.resume(throwing: CancellationError())
                    return
                }
                sleepers.append((id, current + seconds, wake))
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            let index = sleepers.firstIndex { $0.id == id }
            let sleeper = index.map { sleepers.remove(at: $0) }
            lock.unlock()
            sleeper?.wake.resume(throwing: CancellationError())
        }
    }
}
