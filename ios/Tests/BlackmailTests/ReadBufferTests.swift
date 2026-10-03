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

    // MARK: - A long line in chunks (B-063)

    /// What `LinkTransport.readLine` does: a chunk in, a look for a line,
    /// and again, until the line is whole. Returns every line taken, in
    /// order.
    private func feed(_ stream: Data, inChunksOf size: Int,
                      into buffer: inout ReadBuffer) -> [String] {
        var lines: [String] = []
        var at = stream.startIndex
        while at < stream.endIndex {
            let end = min(at + size, stream.endIndex)
            buffer.append(stream.subdata(in: at..<end))
            at = end
            while let line = buffer.takeLine() { lines.append(text(line)!) }
        }
        return lines
    }

    /// A SEARCH answer long enough to come in many chunks, cut every way:
    /// a byte at a time, two, three, seven, a kilobyte. The line comes out
    /// whole, once, and the tagged line after it as itself; and the search
    /// looks at each byte about once, not once a chunk, which is what the
    /// search from the front did.
    func testALongLineInChunksOfAnySizeComesOutWholeAndIsSearchedOnce() {
        let numbers = (0..<3_000).map { String(4_000_000 + $0 * 7) }.joined(separator: " ")
        let long = "* SEARCH " + numbers
        let stream = Data((long + "\r\na007 OK SEARCH completed (Success)\r\n").utf8)
        for size in [1, 2, 3, 7, 1_024] {
            var buffer = ReadBuffer()
            let lines = feed(stream, inChunksOf: size, into: &buffer)
            XCTAssertEqual(lines.count, 2, "chunks of \(size)")
            XCTAssertEqual(lines.first, long, "chunks of \(size)")
            XCTAssertEqual(lines.last, "a007 OK SEARCH completed (Success)", "chunks of \(size)")
            XCTAssertTrue(buffer.isEmpty)
            // Each byte once, and the byte before each chunk once more,
            // since a CR there may have its LF in the chunk after it.
            let chunks = (stream.count + size - 1) / size
            XCTAssertLessThanOrEqual(buffer.examined, stream.count + chunks,
                                     "chunks of \(size): searched from the front again")
        }
    }

    /// The CR the last byte of one chunk and its LF the first of the next:
    /// the search after the second chunk starts one byte back, at the CR.
    func testACRLFSplitAcrossTwoChunksEndsTheLine() {
        var buffer = ReadBuffer()
        buffer.append(Data("* 3 EXISTS\r".utf8))
        XCTAssertNil(buffer.takeLine())
        buffer.append(Data("\na008 OK".utf8))
        XCTAssertEqual(text(buffer.takeLine()), "* 3 EXISTS")
        XCTAssertNil(buffer.takeLine())
        buffer.append(Data("\r".utf8))
        XCTAssertNil(buffer.takeLine())
        buffer.append(Data("\n".utf8))
        XCTAssertEqual(text(buffer.takeLine()), "a008 OK")
        XCTAssertTrue(buffer.isEmpty)
    }

    /// A CR at the end of a chunk followed by more of the line and no LF:
    /// a CR alone ends nothing, and the line ends at the CRLF that comes.
    func testACRAtTheEndOfAChunkWithNoLFAfterItEndsNothing() {
        var buffer = ReadBuffer()
        buffer.append(Data("* 1 FETCH (X\r".utf8))
        XCTAssertNil(buffer.takeLine())
        buffer.append(Data("Y\rZ".utf8))
        XCTAssertNil(buffer.takeLine())
        buffer.append(Data(")\r\n".utf8))
        XCTAssertEqual(text(buffer.takeLine()), "* 1 FETCH (X\rY\rZ)")
        XCTAssertTrue(buffer.isEmpty)
    }

    /// The search after a fruitless one starts where that one stopped, in
    /// bytes from the front. A literal taken from the front in between
    /// moves every byte, so the place is forgotten, and the line after the
    /// literal is found from its own first byte. Were the old place kept,
    /// the search would start past the CRLF that ends the next line, and
    /// the stream would be read out of step.
    func testALiteralTakenAfterAFruitlessSearchLeavesTheNextLineWhole() {
        var buffer = ReadBuffer()
        buffer.append(Data("* 2 FETCH (BODY[] {12}\r\n".utf8))
        XCTAssertEqual(text(buffer.takeLine()), "* 2 FETCH (BODY[] {12}")
        buffer.append(Data("abcdefghijkl)".utf8))
        XCTAssertNil(buffer.takeLine(), "no line has ended yet")
        XCTAssertEqual(text(buffer.take(exactly: 12)), "abcdefghijkl")
        buffer.append(Data("\r\na010 OK\r\n".utf8))
        XCTAssertEqual(text(buffer.takeLine()), ")")
        XCTAssertEqual(text(buffer.takeLine()), "a010 OK")
        XCTAssertTrue(buffer.isEmpty)

        // The same with the literal's last byte a CR the search stopped on.
        var second = ReadBuffer()
        second.append(Data("* 3 FETCH (BODY[] {6}\r\n".utf8))
        XCTAssertEqual(text(second.takeLine()), "* 3 FETCH (BODY[] {6}")
        second.append(Data("12345\r".utf8))
        XCTAssertNil(second.takeLine())
        XCTAssertEqual(text(second.take(exactly: 6)), "12345\r")
        second.append(Data("\n)\r\na011 OK\r\n".utf8))
        XCTAssertEqual(text(second.takeLine()), "\n)")
        XCTAssertEqual(text(second.takeLine()), "a011 OK")
        XCTAssertTrue(second.isEmpty)
    }

    /// Empty lines are lines, one after another and after a fruitless look.
    func testEmptyLinesComeOutOneAtATime() {
        var buffer = ReadBuffer()
        buffer.append(Data("\r\n\r".utf8))
        XCTAssertEqual(buffer.takeLine(), Data())
        XCTAssertNil(buffer.takeLine())
        buffer.append(Data("\n\r\nx\r\n".utf8))
        XCTAssertEqual(buffer.takeLine(), Data())
        XCTAssertEqual(buffer.takeLine(), Data())
        XCTAssertEqual(text(buffer.takeLine()), "x")
        XCTAssertNil(buffer.takeLine())
        XCTAssertTrue(buffer.isEmpty)
    }

    /// Lines and literals of every length, in chunks of every size, read
    /// as a client reads them: a line, and where it ends in `{n}`, n bytes
    /// and the rest of the line. Whatever the chunks, what comes out is
    /// what went in.
    func testAnyStreamInAnyChunksIsReadAsItWasSent() {
        var random = SplitMix(seed: 0x0B5E55ED)
        for round in 0..<40 {
            // What the server sends, and what a reader should get from it.
            var stream = Data()
            var expected: [String] = []
            for _ in 0..<(1 + Int(random.next() % 12)) {
                let words = (0..<Int(random.next() % 40)).map { _ in String(random.next() % 9_999) }
                let line = "* " + words.joined(separator: " ")
                if random.next() % 3 == 0 {
                    let count = Int(random.next() % 50)
                    let bytes = (0..<count).map { _ -> UInt8 in
                        [0x0D, 0x0A, 0x41, 0x7B, 0x7D][Int(random.next() % 5)]
                    }
                    stream.append(Data("\(line) {\(count)}\r\n".utf8))
                    stream.append(Data(bytes))
                    stream.append(Data(")\r\n".utf8))
                    expected.append("\(line) {\(count)}")
                    expected.append("literal:" + bytes.map(String.init).joined(separator: ","))
                    expected.append(")")
                } else {
                    stream.append(Data((line + "\r\n").utf8))
                    expected.append(line)
                }
            }

            var buffer = ReadBuffer()
            var read: [String] = []
            var pendingLiteral: Int?
            var at = stream.startIndex
            func drain() {
                while true {
                    if let count = pendingLiteral {
                        guard let bytes = buffer.take(exactly: count) else { return }
                        read.append("literal:" + bytes.map(String.init).joined(separator: ","))
                        pendingLiteral = nil
                        continue
                    }
                    guard let line = buffer.takeLine().map({ text($0)! }) else { return }
                    read.append(line)
                    if line.hasSuffix("}"), let open = line.lastIndex(of: "{"),
                       let count = Int(line[line.index(after: open)..<line.index(before: line.endIndex)]) {
                        pendingLiteral = count
                    }
                }
            }
            while at < stream.endIndex {
                let size = 1 + Int(random.next() % 23)
                let end = min(at + size, stream.endIndex)
                buffer.append(stream.subdata(in: at..<end))
                at = end
                drain()
            }
            XCTAssertEqual(read, expected, "round \(round)")
            XCTAssertTrue(buffer.isEmpty, "round \(round)")
        }
    }

    /// A SEARCH answer the size of his All Mail's, about 3 MB, in the 16 KB
    /// chunks a socket hands over: found in one pass, quickly. Searched
    /// from the front after every chunk it was about 300 MB of looking.
    func testAThreeMegabyteLineIn16KChunksIsFoundInOnePass() {
        var bytes = [UInt8]("* SEARCH".utf8)
        bytes.reserveCapacity(3_200_000)
        var uid = 1_000_000
        while bytes.count < 3_000_000 {
            bytes.append(0x20)
            bytes.append(contentsOf: String(uid).utf8)
            uid += 3
        }
        let line = bytes.count
        bytes.append(contentsOf: Array("\r\na012 OK\r\n".utf8))
        let stream = Data(bytes)

        let started = ContinuousClock.now
        var buffer = ReadBuffer()
        var lines: [Data] = []
        var at = 0
        while at < stream.count {
            let end = min(at + 16 * 1_024, stream.count)
            buffer.append(stream.subdata(in: at..<end))
            at = end
            while let found = buffer.takeLine() { lines.append(found) }
        }
        let took = ContinuousClock.now - started

        XCTAssertEqual(lines.map(\.count), [line, 7])
        XCTAssertEqual(lines.first, stream.prefix(line))
        let chunks = (stream.count + 16 * 1_024 - 1) / (16 * 1_024)
        XCTAssertLessThanOrEqual(buffer.examined, stream.count + chunks)
        XCTAssertLessThan(took, .seconds(1), "\(took)")
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

/// A small seeded generator, so a run that fails fails the same way again.
private struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
