import Foundation
@testable import Blackmail

/// A `WriteSource` of pieces made in advance (B-070): handed out in order,
/// each after `pausing` seconds of this thread's time, then nil, or then
/// `failure` thrown, as a letter's file that changed is. `total` is what it
/// says the pieces come to, their own count unless told otherwise.
final class MadeSource: WriteSource, @unchecked Sendable {
    let total: Int
    private let lock = NSLock()
    private var pieces: [Data]
    private let failure: Error?
    private let pausing: TimeInterval

    init(_ pieces: [Data], total: Int? = nil, failingWith failure: Error? = nil,
         pausing: TimeInterval = 0) {
        self.pieces = pieces
        self.total = total ?? pieces.reduce(0) { $0 + $1.count }
        self.failure = failure
        self.pausing = pausing
    }

    func begin() throws {}

    func next() throws -> Data? {
        if pausing > 0 { Thread.sleep(forTimeInterval: pausing) }
        lock.lock()
        defer { lock.unlock() }
        if !pieces.isEmpty { return pieces.removeFirst() }
        if let failure { throw failure }
        return nil
    }
}
