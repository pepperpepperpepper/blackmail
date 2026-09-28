import Foundation
import XCTest

/// Runs `body` and hands back what it returns, failing the test instead of
/// hanging the suite if it has not finished within `seconds`.
///
/// XCTest has no default timeout, so a test that awaits something which is
/// never resumed never ends, and takes the rest of the run with it. Work
/// that overlaps on one connection is where that happens: break the exchange
/// gate, or leak a continuation, and the symptom is a wait with no end
/// rather than a wrong answer. Tests that start such work finish it through
/// this. On a timeout the work is cancelled and left behind; the test has
/// already failed.
func finishing<T>(within seconds: Double = 5,
                  file: StaticString = #filePath, line: UInt = #line,
                  _ body: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
        let once = ResumeOnce(continuation)
        let timer = Task {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if once.resume(with: .failure(StillRunning(seconds: seconds))) {
                XCTFail("still running after \(seconds) s", file: file, line: line)
            }
        }
        Task {
            do {
                once.resume(with: .success(try await body()))
            } catch {
                once.resume(with: .failure(error))
            }
            timer.cancel()
        }
    }
}

struct StillRunning: Error {
    let seconds: Double
}

/// A continuation that the first of two racers resumes and the second
/// leaves alone.
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    /// True if this call was the one that resumed it.
    @discardableResult
    func resume(with result: Result<T, Error>) -> Bool {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return false }
        pending.resume(with: result)
        return true
    }
}

/// A flag one task sets and another reads, for "has it finished yet?".
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
