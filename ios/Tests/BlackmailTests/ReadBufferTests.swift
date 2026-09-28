import XCTest
@testable import Blackmail

/// `ReadBuffer`, the read side `TLSConnection` runs on the device: the
/// framing both clients depend on, and the race that decides when a read
/// gives up.
final class ReadBufferTests: XCTestCase {

    private func text(_ data: Data?) -> String? {
        data.map { String(decoding: $0, as: UTF8.self) }
    }

    // MARK: - Framing

    func testLinesComeOutWholeHoweverTheChunksCutThem() {
        var buffer = ReadBuffer()
        buffer.append(Data("* 1 EXISTS\r".utf8))
        XCTAssertNil(buffer.takeLine(), "a CR alone does not end a line")
        buffer.append(Data("\n* 0 REC".utf8))
        XCTAssertEqual(text(buffer.takeLine()), "* 1 EXISTS")
        XCTAssertNil(buffer.takeLine())
        buffer.append(Data("ENT\r\na001 OK done\r\n".utf8))
        XCTAssertEqual(text(buffer.takeLine()), "* 0 RECENT")
        XCTAssertEqual(text(buffer.takeLine()), "a001 OK done")
        XCTAssertNil(buffer.takeLine())
        XCTAssertTrue(buffer.isEmpty)
    }

    func testALiteralIsTakenByCountWithItsLineBreaksAndTheLineCarriesOnAfterIt() {
        var buffer = ReadBuffer()
        buffer.append(Data("* 1 FETCH (BODY[] {8}\r\nab\r\n".utf8))
        XCTAssertEqual(text(buffer.takeLine()), "* 1 FETCH (BODY[] {8}")
        XCTAssertNil(buffer.take(exactly: 8), "only four of the eight bytes are here")
        buffer.append(Data("cd\r\n)\r\na002 OK\r\n".utf8))
        XCTAssertEqual(text(buffer.take(exactly: 8)), "ab\r\ncd\r\n")
        XCTAssertEqual(text(buffer.takeLine()), ")")
        XCTAssertEqual(text(buffer.takeLine()), "a002 OK")
        XCTAssertEqual(buffer.take(exactly: 0), Data())
    }

    func testReadingTheBufferToTheEndLetsGoOfWhatItHeld() {
        var buffer = ReadBuffer()
        let big = Data(repeating: 0x41, count: 1 << 20)

        // Removing bytes from the front of a `Data` does not free them. What
        // is left is a slice of the same allocation, and its indices still
        // start where the removed bytes ended; a fresh `Data` starts at zero.
        // So a buffer drained of a megabyte and still holding it shows here
        // as an empty buffer whose first index is about a million.
        buffer.append(Data("* 1 FETCH (BODY[] {\(big.count)}\r\n".utf8) + big)
        _ = buffer.takeLine()
        XCTAssertEqual(buffer.take(exactly: big.count)?.count, big.count)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.bytes.startIndex, 0,
                       "an empty buffer is still holding the megabyte it was drained of")

        buffer.append(big + Data("\r\n".utf8))
        XCTAssertEqual(buffer.takeLine()?.count, big.count)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.bytes.startIndex, 0)

        // Not while anything is left in it.
        buffer.append(Data("a003 OK\r\n* 4 EXISTS".utf8))
        _ = buffer.takeLine()
        XCTAssertEqual(text(buffer.bytes), "* 4 EXISTS")
    }

    // MARK: - The read deadline

    func testAChunkThatArrivesInTimeIsReturned() async throws {
        let expired = Counter()
        let chunk = try await ReadBuffer.receiveChunk(within: 5, onExpiry: { expired.add() }) {
            Data("* OK\r\n".utf8)
        }
        XCTAssertEqual(text(chunk), "* OK\r\n")
        XCTAssertEqual(expired.value, 0)
    }

    func testAFailedReceiveFailsTheRead() async {
        do {
            _ = try await ReadBuffer.receiveChunk(within: 5, onExpiry: {}) {
                throw MailTransportError.closed
            }
            XCTFail("a receive that failed cannot produce a chunk")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .closed)
        }
    }

    /// A peer that has gone quiet. The receive, like `NWConnection`'s, ends
    /// only when bytes come or the connection is cancelled, and nothing is
    /// coming. The deadline has to end the read on its own, and it does it
    /// by closing the connection, which ends the receive too: nothing is
    /// left waiting on a socket nobody will read again.
    func testASilentPeerIsCutOffAtTheDeadlineAndItsReceiveIsEnded() async throws {
        let socket = SilentSocket()
        let started = ContinuousClock.now
        do {
            _ = try await finishing(within: 1) {
                try await ReadBuffer.receiveChunk(within: 0.02, onExpiry: { socket.cancel() }) {
                    try await socket.receive()
                }
            }
            XCTFail("nothing was sent, so nothing can have been read")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .timedOut)
        }
        let elapsed = ContinuousClock.now - started
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(20), "cut off before its deadline")
        XCTAssertEqual(socket.cancels, 1)
        try await socket.untilReceiveEnded()
    }

    /// A read made by a task that is then cancelled: a search the next
    /// keystroke replaced. It is not cut short. It waits for its chunk and
    /// hands it back, so the reply it belongs to is read whole and the next
    /// command on the connection reads its own. It used to throw once the
    /// chunk came and drop it, and `IMAPClient` then had to tear the
    /// connection down, because that reply was gone from the stream.
    func testACancelledReadStillGetsItsChunk() async throws {
        let gate = Gate()
        let finished = Flag()
        let read = Task {
            defer { finished.set() }
            return try await ReadBuffer.receiveChunk(within: 5, onExpiry: {}) {
                await gate.wait()
                return Data("a004 OK\r\n".utf8)
            }
        }
        try await gate.untilWaiting()
        read.cancel()
        try await Task.sleep(for: .milliseconds(5))
        XCTAssertFalse(finished.isSet, "the read ended before its chunk arrived")

        gate.open()
        let chunk = try await finishing { try await read.value }
        XCTAssertEqual(text(chunk), "a004 OK\r\n")
    }

    /// The chunk and the deadline landing together, many times over, on the
    /// two different threads they come from. Each read ends exactly once,
    /// one way or the other: a checked continuation resumed twice kills the
    /// process. And the connection is closed exactly when the read was told
    /// it timed out, never when it got its chunk.
    func testAChunkAndADeadlineThatLandTogetherEndTheReadOnce() async throws {
        for _ in 0..<100 {
            let expired = Counter()
            do {
                let chunk = try await finishing {
                    try await ReadBuffer.receiveChunk(within: 0.001, onExpiry: { expired.add() }) {
                        try await Task.sleep(for: .microseconds(1_000))
                        return Data("a005 OK\r\n".utf8)
                    }
                }
                XCTAssertEqual(text(chunk), "a005 OK\r\n")
                XCTAssertEqual(expired.value, 0, "closed a connection whose read succeeded")
            } catch {
                XCTAssertEqual(error as? MailTransportError, .timedOut)
                XCTAssertEqual(expired.value, 1)
            }
        }
    }
}

/// A receive on a connection that the peer has stopped talking on: it ends
/// only when the connection is cancelled, and then with an error, as a
/// pending `NWConnection.receive` does.
private final class SilentSocket: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = 0
    private var ended = false
    private let gate = Gate()

    var cancels: Int { locked { cancelled } }

    func receive() async throws -> Data {
        defer { locked { ended = true } }
        await gate.wait()
        throw MailTransportError.posix("POSIX 89")
    }

    func cancel() {
        locked { cancelled += 1 }
        gate.open()
    }

    /// A second at most.
    func untilReceiveEnded() async throws {
        for _ in 0..<1_000 {
            if locked({ ended }) { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("the receive was left waiting on a closed connection")
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Something a receive can wait on until the test says go, standing in for
/// bytes that have not arrived yet.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if isOpen {
                lock.unlock()
                c.resume()
            } else {
                waiting.append(c)
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let resumed = waiting
        waiting = []
        lock.unlock()
        for c in resumed { c.resume() }
    }

    /// Returns once something is waiting, so the test knows the receive has
    /// started. A second at most.
    func untilWaiting() async throws {
        for _ in 0..<1_000 {
            if hasWaiter { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("nothing ever waited")
    }

    private var hasWaiter: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !waiting.isEmpty
    }
}
