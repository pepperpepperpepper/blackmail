import Foundation

/// A clock a test moves by hand, for what the repository and the client
/// time: ninety seconds of quiet before a write's probe, how long ago a
/// mailbox's news was asked for. Nothing moves it but `advance`, so the
/// commands a test sends take no time on it.
final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_790_000_000)

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current += seconds
        lock.unlock()
    }
}
