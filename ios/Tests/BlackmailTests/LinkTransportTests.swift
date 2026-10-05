import XCTest
@testable import Blackmail

/// `LinkTransport`, the half of a transport the device and the tests share:
/// what `close()` lets go of, the B-034 probes around a bulk write, and the
/// transcript line for each deadline that fires.
///
/// Driven through the scripted server's transport, whose own code is only the
/// link, so what these tests exercise above it is code `TLSConnection` runs.
final class LinkTransportTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private var server: ScriptedIMAPServer!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        Diagnostics.clear()
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        server = nil
        super.tearDown()
    }

    private func transport() -> any MailTransport {
        server.transportFactory("imap.example.com", server.port)
    }

    /// An open transport with the greeting read.
    private func greeted() async throws -> any MailTransport {
        let transport = transport()
        try await transport.open()
        let greeting = try await transport.readLine()
        XCTAssertTrue(greeting.hasPrefix("* OK"), greeting)
        return transport
    }

    private var notes: [String] {
        Diagnostics.entries.filter { $0.direction == .note }.map(\.text)
    }

    /// A letter of `pieces` whole pieces of body, and a header.
    private static func letter(pieces: Int) -> Data {
        let body = String(repeating: String(repeating: "x", count: 1_022) + "\r\n",
                          count: pieces * TransportDeadline.writeChunkBytes / 1_024)
        return Data(("From: owner@example.com\r\nTo: carlo@example.org\r\n"
                     + "Subject: Photos from Sunday\r\nMessage-ID: <photos@example.com>\r\n\r\n"
                     + body).utf8)
    }

    // MARK: - Closing

    /// A reply read halfway, then the transport closed. What was left of it
    /// is gone with the connection: a read on the closed transport fails
    /// rather than handing back the rest as if it answered something.
    func testClosingLetsGoOfWhatHasArrivedAndNotBeenRead() async throws {
        let transport = try await greeted()
        try await transport.writeLine("a001 CAPABILITY")
        let first = try await transport.readLine()
        XCTAssertTrue(first.hasPrefix("* CAPABILITY"), first)

        await transport.close()
        do {
            let line = try await transport.readLine()
            XCTFail("read \"\(line)\" from a closed transport")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .notConnected)
        }
    }

    /// Bytes that reach a read in the same moment the transport is closed
    /// under it belong to nobody. The read fails; it does not hand them on.
    func testBytesThatLandAsTheTransportClosesAreNotRead() async throws {
        let transport = try await greeted()
        let scripted = try XCTUnwrap(transport as? ScriptedTransport)
        let read = Task { try await transport.readLine() }
        for _ in 0..<1_000 {
            if await scripted.isAwaitingBytes { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let waiting = await scripted.isAwaitingBytes
        XCTAssertTrue(waiting, "the read never reached the link")

        await scripted.landAndClose(Data("* 3 EXISTS\r\n".utf8))
        do {
            let line = try await finishing { try await read.value }
            XCTFail("read \"\(line)\" after the transport was closed")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .closed)
        }
    }

    // MARK: - The B-034 probes

    /// A draft big enough to go in eleven pieces. The transcript has one
    /// WIRE-OUT with its length and one WIRE-ACK, both for the whole write,
    /// and the ACK before the server's answer. Nothing for the command lines
    /// around it, LOGIN's included: the length of a line is the length of
    /// whatever secret is on it.
    func testABulkWriteIsProbedOnceHoweverManyPiecesItGoesIn() async throws {
        let client = IMAPClient(account: server.account, transport: server.transportFactory)
        try await client.connect(password: server.password)
        let raw = Self.letter(pieces: 10)
        server.uplinkDelay = .milliseconds(1)

        let appended = try await finishing {
            try await client.append(raw, to: Server.drafts, flags: ["\\Draft", "\\Seen"])
        }
        XCTAssertNotNil(appended)

        XCTAssertEqual(notes.filter { $0.hasPrefix("WIRE-") },
                       ["WIRE-OUT bytes=\(raw.count)", "WIRE-ACK err=none"])
        XCTAssertEqual(notes.filter { $0.hasPrefix("DEADLINE") }, [])
        let entries = Diagnostics.entries
        let ack = try XCTUnwrap(entries.firstIndex { $0.text == "WIRE-ACK err=none" })
        let answer = try XCTUnwrap(entries.firstIndex {
            $0.direction == .received && $0.text.contains("APPENDUID")
        })
        XCTAssertLessThan(ack, answer)
    }

    /// A bulk write asked how it is getting on says so after each piece the
    /// link takes, the running total of the whole; the probes are still one
    /// WIRE-OUT and one WIRE-ACK for all of it.
    func testABulkWriteReportsEachPieceTheLinkTakes() async throws {
        let transport = try await greeted()
        server.uplinkDelay = .milliseconds(1)
        let piece = TransportDeadline.writeChunkBytes
        let data = Data(repeating: 0x41, count: 2 * piece + 100)
        let reports = Progress()

        try await finishing { try await transport.write(data, progress: { reports.add($0, $1) }) }

        XCTAssertEqual(reports.all.map(\.written), [piece, 2 * piece, 2 * piece + 100])
        XCTAssertEqual(Set(reports.all.map(\.total)), [data.count])
        XCTAssertEqual(notes.filter { $0.hasPrefix("WIRE-") },
                       ["WIRE-OUT bytes=\(data.count)", "WIRE-ACK err=none"])
    }

    /// The same through `LinkTransport`'s own `write`, which is what
    /// `TLSConnection` runs: the scripted transport has a `write` of its own
    /// that watches the client, so it would not notice this one dropping the
    /// progress on the floor.
    func testTheSharedWriteHandsTheProgressOn() async throws {
        let link = BareLink()
        try await link.open()
        let piece = TransportDeadline.writeChunkBytes
        let reports = Progress()
        try await link.write(Data(repeating: 0x42, count: piece + 1), progress: { reports.add($0, $1) })
        XCTAssertEqual(reports.all.map(\.written), [piece, piece + 1])
        let taken = await link.taken
        XCTAssertEqual(taken, piece + 1)
    }

    /// A bulk write whose uplink stops: one WIRE-ACK, carrying the timeout,
    /// after the line naming the deadline, and the transport closed.
    func testABulkWriteCutOffAtItsDeadlineSaysSoInItsProbe() async throws {
        server.timeout = .milliseconds(20)
        let transport = try await greeted()
        server.uplinkDelay = .seconds(30)
        let data = Data(repeating: 0x41, count: 3 * TransportDeadline.writeChunkBytes)

        do {
            try await finishing(within: 1) { try await transport.write(data) }
            XCTFail("a write that never left cannot have finished")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .timedOut)
        }
        XCTAssertEqual(notes, ["WIRE-OUT bytes=\(data.count)", "DEADLINE write bound=0.02s",
                               "WIRE-ACK err=timedOut"])
        do {
            try await transport.writeLine("a001 NOOP")
            XCTFail("wrote into a transport whose write had timed out")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .notConnected)
        }
    }

    // MARK: - A letter made as it goes (B-070)

    /// A letter made a piece at a time is one write: one WIRE-OUT for the
    /// whole of it and one WIRE-ACK, however many pieces; the progress after
    /// each, to the total; every byte to the link.
    func testAStreamedWriteIsProbedOnceAndReportsEachPiece() async throws {
        let link = BareLink()
        try await link.open()
        let piece = TransportDeadline.writeChunkBytes
        let stream = try DataStream(raw: Data(repeating: 0x41, count: 2 * piece + 100))
        let reports = Progress()

        try await link.write(from: stream, progress: { reports.add($0, $1) })

        XCTAssertEqual(reports.all.map(\.written), [piece, 2 * piece, stream.total])
        XCTAssertEqual(Set(reports.all.map(\.total)), [stream.total])
        let taken = await link.taken
        XCTAssertEqual(taken, stream.total)
        XCTAssertEqual(notes.filter { $0.hasPrefix("WIRE-") },
                       ["WIRE-OUT bytes=\(stream.total)", "WIRE-ACK err=none"])
    }

    /// A streamed write whose uplink stops: the deadline named, one
    /// WIRE-ACK with the timeout, and the transport closed.
    func testAStreamedWriteCutOffAtItsDeadlineClosesTheTransport() async throws {
        server.timeout = .milliseconds(20)
        let transport = try await greeted()
        server.uplinkDelay = .seconds(30)
        let stream = try DataStream(raw: Data(repeating: 0x41,
                                              count: 3 * TransportDeadline.writeChunkBytes))
        do {
            try await finishing(within: 1) { try await transport.write(from: stream, progress: nil) }
            XCTFail("a write that never left cannot have finished")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .timedOut)
        }
        XCTAssertEqual(notes, ["WIRE-OUT bytes=\(stream.total)", "DEADLINE write bound=0.02s",
                               "WIRE-ACK err=timedOut"])
        do {
            try await transport.writeLine("a001 NOOP")
            XCTFail("wrote into a transport whose write had timed out")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .notConnected)
        }
    }

    /// A letter whose write was cut off at its deadline, handed to a write
    /// again, as a retry that kept it would: refused before a byte is
    /// written, the transport closed, and so never the rest of the letter,
    /// headless, with a dot to end it.
    func testAStreamCutOffAtItsDeadlineIsNeverWrittenAgain() async throws {
        server.timeout = .milliseconds(20)
        let transport = try await greeted()
        server.uplinkDelay = .seconds(30)
        let stream = try DataStream(raw: Self.letter(pieces: 3))
        do {
            try await finishing(within: 1) { try await transport.write(from: stream, progress: nil) }
            XCTFail("a write that never left cannot have finished")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .timedOut)
        }

        Diagnostics.clear()
        let link = BareLink()
        try await link.open()
        do {
            try await link.write(from: stream, progress: nil)
            XCTFail("the rest of a letter cut off was written again")
        } catch {
            XCTAssertEqual(error as? LetterSourceFailure,
                           LetterSourceFailure(file: nil, reason: .countMismatch), "\(error)")
        }
        let taken = await link.taken
        XCTAssertEqual(taken, 0)
        XCTAssertEqual(notes, ["WIRE-OUT bytes=\(stream.total)",
                               "LETTER-LATCH withheld file=- reason=count mismatch",
                               "WIRE-ACK err=source"])
        do {
            try await link.writeLine("QUIT")
            XCTFail("QUIT written after the letter was refused")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .notConnected)
        }
    }

    /// A letter's file that fails part of the way: the transport is closed
    /// at once, so nothing more, a QUIT neither, can be written into the
    /// letter, and the failure comes out as it went in, never made a
    /// transport's error, even by a link that maps every error it sees.
    func testASourceThatFailsClosesTheTransportAndIsThrownAsItCame() async throws {
        let failure = LetterSourceFailure(file: 0, reason: .changedDuringSend)
        for link in [BareLink() as any LinkTransport, MappingLink()] {
            Diagnostics.clear()
            try await link.open()
            let source = MadeSource([Data(repeating: 0x42, count: TransportDeadline.writeChunkBytes)],
                                    total: 3 * TransportDeadline.writeChunkBytes,
                                    failingWith: failure)
            do {
                try await link.write(from: source, progress: nil)
                XCTFail("a letter whose file failed was written whole")
            } catch {
                XCTAssertEqual(error as? LetterSourceFailure, failure, "\(error)")
            }
            XCTAssertEqual(notes, ["WIRE-OUT bytes=\(source.total)", "WIRE-ACK err=source"])
            do {
                try await link.writeLine("QUIT")
                XCTFail("QUIT written after the letter's file failed")
            } catch {
                XCTAssertEqual(error as? MailTransportError, .notConnected)
            }
        }
    }

    /// Pieces that come to other than was said: logged, `WIRE-COUNT`, and
    /// not thrown. The last piece holds the letter's dot; thrown there, a
    /// letter the server has would be called not sent, and sent again.
    func testAStreamedWriteThatCountsWrongIsLoggedNotThrown() async throws {
        let link = BareLink()
        try await link.open()
        try await link.write(from: MadeSource([Data(repeating: 0x43, count: 1_500)], total: 2_000),
                             progress: nil)
        XCTAssertEqual(notes, ["WIRE-OUT bytes=2000", "WIRE-COUNT predicted=2000 actual=1500",
                               "WIRE-ACK err=none"])
    }

    // MARK: - Deadlines in the transcript

    /// A deadline that fires names itself and its bound, so a transcript
    /// tells a peer that went quiet from one that reset the connection, and
    /// shows which bound a read was given.
    func testEachDeadlineThatFiresIsNamedWithItsBound() async throws {
        server.timeout = .milliseconds(20)
        server.uploadReplyTimeout = .milliseconds(30)

        server.handshakeStalls = true
        let stalled = transport()
        do {
            try await finishing(within: 1) { try await stalled.open() }
            XCTFail("a handshake that never finished cannot have connected")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .timedOut)
        }
        server.handshakeStalls = false

        server.isSilent = true
        let silent = transport()
        try await silent.open()
        do {
            _ = try await finishing(within: 1) { try await silent.readLine() }
            XCTFail("a greeting that never came cannot have been read")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .timedOut)
        }
        server.isSilent = false

        let uploaded = try await greeted()
        do {
            _ = try await finishing(within: 1) { try await uploaded.readLine(.afterUpload) }
            XCTFail("an answer that never came cannot have been read")
        } catch {
            XCTAssertEqual(error as? MailTransportError, .timedOut)
        }

        XCTAssertEqual(notes, ["DEADLINE connect bound=0.02s",
                               "DEADLINE read ordinary bound=0.02s",
                               "DEADLINE read afterUpload bound=0.03s"])
    }
}

/// Progress reports, from any thread.
private final class Progress: @unchecked Sendable {
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

/// A link with nothing above it but `LinkTransport`: it comes up at once,
/// takes every piece at once, and never has anything to say.
private actor BareLink: LinkTransport {
    var stream = LinkStream()
    let ordinaryDeadline: TimeInterval = 5
    let uploadReplyDeadline: TimeInterval = 5
    private(set) var taken = 0

    func startLink(reporting report: @escaping @Sendable (Error?) -> Void) { report(nil) }
    func receiveFromLink() async throws -> Data { throw MailTransportError.closed }
    func sendToLink(_ piece: Data) async throws { taken += piece.count }
    func closeLink() {}
}

/// A bare link that maps every error its sends meet, as `TLSConnection`
/// maps `NWError`: what it must never do to a letter's own failure.
private actor MappingLink: LinkTransport {
    var stream = LinkStream()
    let ordinaryDeadline: TimeInterval = 5
    let uploadReplyDeadline: TimeInterval = 5

    func startLink(reporting report: @escaping @Sendable (Error?) -> Void) { report(nil) }
    func receiveFromLink() async throws -> Data { throw MailTransportError.closed }
    func sendToLink(_ piece: Data) async throws {}
    func closeLink() {}
    static func transportError(_ sendError: Error) -> Error { MailTransportError.posix("mapped") }
}
