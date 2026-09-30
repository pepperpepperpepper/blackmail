import Foundation

/// Something asked for that waits until the test answers it.
@MainActor
final class Held {
    private var parked: [CheckedContinuation<Void, Error>] = []

    var waiting: Int { parked.count }

    func wait() async throws {
        try await withCheckedThrowingContinuation { parked.append($0) }
    }

    func release(_ outcome: Result<Void, Error> = .success(())) {
        let waiting = parked
        parked = []
        for continuation in waiting { continuation.resume(with: outcome) }
    }
}
