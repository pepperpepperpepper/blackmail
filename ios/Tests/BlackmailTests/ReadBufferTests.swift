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

    // MARK: - The read deadline, as it behaves today

    func testAChunkThatArrivesInTimeIsReturned() async throws {
        let chunk = try await ReadBuffer.receiveChunk(within: 5) { Data("* OK\r\n".utf8) }
        XCTAssertEqual(text(chunk), "* OK\r\n")
    }

    func testAFailedReceiveFailsTheRead() async {
        do {
            _ = try await ReadBuffer.receiveChunk(within: 5) { throw MailTransportError.closed }
            XCTFail("a receive that failed cannot produce a chunk")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .closed)
        }
    }

    /// What the device does today, not what it should. The deadline throws
    /// on time, but the task group then waits for the receive, which does
    /// not answer cancellation; on a peer that never answers at all, that is
    /// a read with no end. When the deadline is made to end the read on its
    /// own, this turns round: the read should fail at about the deadline,
    /// long before the receive answers.
    func testTheDeadlineDoesNotEndAReadUntilTheReceiveAnswers() async throws {
        let gate = Gate()
        let finished = Flag()
        let read = Task {
            defer { finished.set() }
            return try await ReadBuffer.receiveChunk(within: 0.002) {
                await gate.wait()
                return Data("late\r\n".utf8)
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(finished.isSet, "the read ended at its deadline, which it does not do yet")

        gate.open()
        do {
            _ = try await finishing { try await read.value }
            XCTFail("a chunk that came after the deadline is not returned")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .timedOut)
        }
    }

    /// Also today's behaviour. A read made by a task that is then cancelled
    /// (a search the next keystroke replaced) waits for the chunk it was
    /// after, drops it, and throws; `IMAPClient` then has to tear the
    /// connection down, because that reply is gone from the stream.
    func testACancelledReadWaitsForItsChunkAndThenDropsIt() async throws {
        let gate = Gate()
        let finished = Flag()
        let read = Task {
            defer { finished.set() }
            return try await ReadBuffer.receiveChunk(within: 5) {
                await gate.wait()
                return Data("a004 OK\r\n".utf8)
            }
        }
        try await gate.untilWaiting()
        read.cancel()
        try await Task.sleep(for: .milliseconds(5))
        XCTAssertFalse(finished.isSet, "the read ended before its chunk arrived")

        gate.open()
        do {
            _ = try await finishing { try await read.value }
            XCTFail("a cancelled read does not hand its chunk back")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
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
