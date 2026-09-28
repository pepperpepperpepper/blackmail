import XCTest
@testable import Blackmail

/// `TransportDeadline.write`: how `TLSConnection` hands a write to the stack,
/// a piece at a time, with the deadline measuring progress rather than size.
final class TransportDeadlineTests: XCTestCase {

    private let piece = TransportDeadline.writeChunkBytes

    /// Eight pieces, each well inside the deadline, the whole write well
    /// outside it: a five-photo letter going up a slow line. A flat deadline
    /// on the write would cut it off while every piece was still moving.
    func testAWriteThatKeepsMovingIsNotCutOffForItsSize() async throws {
        // Each piece filled with its own number, so one out of place shows.
        let data = (0..<8).reduce(into: Data()) { $0.append(Data(repeating: UInt8($1), count: piece)) }
        let sent = Pieces()
        let expired = Counter()
        let started = ContinuousClock.now

        try await finishing {
            try await TransportDeadline.write(data, within: 0.015, onExpiry: { expired.add() }) {
                try await Task.sleep(for: .milliseconds(3))
                sent.append($0)
            }
        }

        XCTAssertGreaterThan(ContinuousClock.now - started, .milliseconds(15),
                             "the write as a whole should outlast one deadline")
        XCTAssertEqual(expired.value, 0)
        XCTAssertEqual(sent.all.map(\.count), Array(repeating: piece, count: 8))
        XCTAssertEqual(sent.all.reduce(Data(), +), data)
    }

    func testTheLastPieceIsWhateverIsLeft() async throws {
        let data = Data(repeating: 0x2E, count: piece + 10)
        let sent = Pieces()
        try await TransportDeadline.write(data, within: 5, onExpiry: {}) { sent.append($0) }
        XCTAssertEqual(sent.all.map(\.count), [piece, 10])

        let small = Pieces()
        try await TransportDeadline.write(Data("a001 NOOP\r\n".utf8), within: 5, onExpiry: {}) {
            small.append($0)
        }
        XCTAssertEqual(small.all, [Data("a001 NOOP\r\n".utf8)])
    }

    /// A line that has stopped: the second piece is never taken. The write
    /// fails at the deadline, the connection is closed, which ends the send
    /// that was left waiting, and nothing after it is handed over.
    func testAWriteThatStopsMovingIsCutOffAtTheDeadline() async throws {
        let data = Data(repeating: 0x41, count: 3 * piece)
        let line = StalledLine(stallingAt: 2)
        do {
            try await finishing(within: 1) {
                try await TransportDeadline.write(data, within: 0.02, onExpiry: { line.cancel() }) {
                    try await line.send($0)
                }
            }
            XCTFail("a write that stopped moving cannot have finished")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .timedOut)
        }
        XCTAssertEqual(line.cancels, 1)
        XCTAssertEqual(line.attempts, 2, "a piece after the stalled one was handed over")
        try await line.untilStalledSendEnded()
    }

    /// A write made by a task that is then cancelled goes out whole. Half a
    /// command, or half a letter, is worse than either all of it or none.
    func testACancelledWriterStillHandsOverEveryPiece() async throws {
        let data = Data(repeating: 0x42, count: 4 * piece)
        let sent = Pieces()
        let writer = Task {
            try await TransportDeadline.write(data, within: 5, onExpiry: {}) {
                try? await Task.sleep(for: .milliseconds(2))
                sent.append($0)
            }
        }
        writer.cancel()
        try await finishing { try await writer.value }
        XCTAssertEqual(sent.all.reduce(Data(), +), data)
    }
}

/// What a send was handed, in order, from any thread.
private final class Pieces: @unchecked Sendable {
    private let lock = NSLock()
    private var pieces: [Data] = []

    var all: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return pieces
    }

    func append(_ piece: Data) {
        lock.lock()
        pieces.append(Data(piece))
        lock.unlock()
    }
}

/// An uplink that takes pieces until the `n`th, which it never finishes:
/// that send ends only when the connection is cancelled, and then with an
/// error, as a pending `NWConnection.send` does.
private final class StalledLine: @unchecked Sendable {
    private let lock = NSLock()
    private let stallAt: Int
    private var sends = 0
    private var cancelled = 0
    private var stalledEnded = false
    private var stalled: CheckedContinuation<Void, Error>?

    init(stallingAt n: Int) {
        stallAt = n
    }

    var attempts: Int { locked { sends } }
    var cancels: Int { locked { cancelled } }

    func send(_ piece: Data) async throws {
        let number: Int = locked {
            sends += 1
            return sends
        }
        guard number == stallAt else { return }
        defer { locked { stalledEnded = true } }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            let alreadyCancelled: Bool = locked {
                if cancelled > 0 { return true }
                stalled = c
                return false
            }
            if alreadyCancelled { c.resume(throwing: MailTransportError.closed) }
        }
    }

    func cancel() {
        let pending: CheckedContinuation<Void, Error>? = locked {
            cancelled += 1
            defer { stalled = nil }
            return stalled
        }
        pending?.resume(throwing: MailTransportError.closed)
    }

    /// A second at most.
    func untilStalledSendEnded() async throws {
        for _ in 0..<1_000 {
            if locked({ stalledEnded }) { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("the stalled send was left waiting on a closed connection")
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
