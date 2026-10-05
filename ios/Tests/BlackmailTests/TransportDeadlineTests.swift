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

    /// After each piece is taken, the running total of the whole, counted
    /// from the write's own start when it is a slice of something larger;
    /// and nothing for a piece that was never taken.
    func testEachPieceTakenReportsTheRunningTotal() async throws {
        let data = Data(repeating: 0x43, count: 2 * piece + 10)
        let reports = Reports()
        try await TransportDeadline.write(data, within: 5, onExpiry: {},
                                          progress: { reports.add($0, $1) }) { _ in }
        XCTAssertEqual(reports.all.map(\.written), [piece, 2 * piece, 2 * piece + 10])
        XCTAssertEqual(Set(reports.all.map(\.total)), [data.count])

        let larger = Data(repeating: 0x44, count: piece + 100)
        let slice = Reports()
        try await TransportDeadline.write(larger[50...], within: 5, onExpiry: {},
                                          progress: { slice.add($0, $1) }) { _ in }
        XCTAssertEqual(slice.all.map(\.written), [piece, piece + 50])
        XCTAssertEqual(Set(slice.all.map(\.total)), [piece + 50])

        let line = StalledLine(stallingAt: 2)
        let stalled = Reports()
        do {
            try await finishing(within: 1) {
                try await TransportDeadline.write(Data(repeating: 0x45, count: 3 * self.piece),
                                                  within: 0.02, onExpiry: { line.cancel() },
                                                  progress: { stalled.add($0, $1) }) {
                    try await line.send($0)
                }
            }
            XCTFail("a write that stopped moving cannot have finished")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .timedOut)
        }
        XCTAssertEqual(stalled.all.map(\.written), [piece], "only the piece that was taken")
        try await line.untilStalledSendEnded()
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

    // MARK: - A letter made as it goes (B-070)

    /// A piece of nothing is passed over, with nothing reported for it; one
    /// larger than a piece is cut as `write` cuts; the running total of the
    /// whole after each.
    func testAStreamPassesOverEmptyPiecesAndCutsOversizedOnes() async throws {
        let source = MadeSource([Data(), Data(repeating: 1, count: 10), Data(),
                                 Data(repeating: 2, count: 2 * piece + 5), Data()])
        let sent = Pieces()
        let reports = Reports()
        try await TransportDeadline.write(from: source, within: 5, onExpiry: {},
                                          progress: { reports.add($0, $1) }) { sent.append($0) }
        XCTAssertEqual(sent.all.map(\.count), [10, piece, piece, 5])
        XCTAssertEqual(reports.all.map(\.written), [10, 10 + piece, 10 + 2 * piece, 15 + 2 * piece])
        XCTAssertEqual(Set(reports.all.map(\.total)), [15 + 2 * piece])
    }

    /// Making a piece is this device's time, not the network's: a source
    /// that takes longer than the deadline to make each piece is not cut
    /// off, since only the sends are raced.
    func testAPieceIsMadeOutsideTheDeadline() async throws {
        let source = MadeSource((0..<3).map { Data(repeating: UInt8($0), count: 100) },
                                pausing: 0.05)
        let expired = Counter()
        let sent = Pieces()
        try await finishing {
            try await TransportDeadline.write(from: source, within: 0.02,
                                              onExpiry: { expired.add() }) { sent.append($0) }
        }
        XCTAssertEqual(expired.value, 0)
        XCTAssertEqual(sent.all.count, 3)
    }

    /// A total that comes out other than said is logged, never thrown: the
    /// last piece of a letter carries its dot, and the letter may be the
    /// server's by then.
    func testATotalOtherThanSaidIsLoggedNotThrown() async throws {
        Diagnostics.clear()
        let source = MadeSource([Data(repeating: 3, count: 1_500)], total: 2_000)
        try await TransportDeadline.write(from: source, within: 5, onExpiry: {}) { _ in }
        XCTAssertEqual(Diagnostics.entries.map(\.text), ["WIRE-COUNT predicted=2000 actual=1500"])
    }
}

/// Progress reports, in order, from any thread.
private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var reports: [(written: Int, total: Int)] = []

    var all: [(written: Int, total: Int)] {
        lock.lock()
        defer { lock.unlock() }
        return reports
    }

    func add(_ written: Int, _ total: Int) {
        lock.lock()
        reports.append((written, total))
        lock.unlock()
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
