import Foundation

/// What goes after DATA's 354 for one letter, made from its plan and its
/// open files as the connection takes it (B-070). Never the whole letter in
/// memory, and never on the disk.
///
/// The letter is made twice, by the same code (`LetterBytes`, then
/// `DataStuffer`):
///
/// 1. **The rehearsal**, in `init`, before anything is said to a server.
///    Every file is read and every byte made and stuffed, into a count.
///    That gives the letter's exact size, for SIZE; the exact size of what
///    goes after DATA, for the progress; and each file's count and CRC-32.
///    A file that cannot be read, or is shorter or longer than its size,
///    fails here, with nothing on the wire.
/// 2. **The wire**, in `next()`, after the 354: the same bytes, in pieces
///    of exactly 64 KiB but the last, through a stuffer that carries its
///    state from one piece to the next.
///
/// The terminating dot is made only after **the latch**: each file read
/// again gave the rehearsal's count and CRC, and ended at its size; and the
/// letter's counts are the rehearsal's. Otherwise the dot is withheld, and
/// what was made is thrown away. A server throws away a DATA that never
/// ended (RFC 5321 §4.1.1.4), so nothing is delivered, and the transport,
/// which is closed with no QUIT (`LinkTransport`, `SMTPClient`), says the
/// letter was not sent. So whatever went before the dot is the letter the
/// rehearsal made.
///
/// One pass, claimed by the write that takes it (`begin`). A second claim
/// fails, before the first piece or part of the way through, and every
/// piece asked for after it; so does a piece asked for with no claim. The
/// rest of a letter cut off part of the way never goes as a letter of its
/// own, headless with a dot. Held by `Submission` and handed to one
/// transport, whose write claims it and calls `next()` one piece after
/// another.
final class DataStream: WriteSource, @unchecked Sendable {

    /// What the rehearsal found.
    struct Rehearsal {
        /// The letter's bytes: SIZE's count, and what `build` makes.
        let rawCount: Int
        /// What goes after DATA, the terminator's included.
        let payloadCount: Int
        /// Each file's bytes and their CRC-32.
        let files: [(bytes: Int, crc: UInt32)]
        /// How long the rehearsal took, in milliseconds.
        let ms: Int
    }

    /// The pieces handed out, but the last: the transport's own
    /// (`TransportDeadline.writeChunkBytes`), so the progress is reported
    /// in the steps it always was.
    static let pieceBytes = TransportDeadline.writeChunkBytes

    let rehearsal: Rehearsal
    var rawCount: Int { rehearsal.rawCount }
    var total: Int { rehearsal.payloadCount }

    private let plan: LetterPlan
    private let files: LetterFiles

    private enum State {
        case ready
        case going(LetterBytes)
        case done
        case failed(LetterSourceFailure)
    }

    private let lock = NSLock()
    private var state = State.ready
    private var stuffer = DataStuffer()
    /// Made and not yet handed out.
    private var pending: [UInt8] = []
    /// Handed out.
    private var handed = 0
    /// The plan has given its last byte, and the latch has held.
    private var latched = false
    /// A write has claimed the pass (`begin`).
    private var begun = false

    /// Rehearses the letter: throws `LetterSourceFailure` for a file that
    /// cannot go, or for a letter not the length its plan says.
    init(plan: LetterPlan, files: LetterFiles) throws {
        let started = DispatchTime.now().uptimeNanoseconds
        var bytes = LetterBytes(plan: plan, files: files, mode: .rehearsal)
        var stuffer = DataStuffer()
        var counted = StuffedCount()
        while let chunk = try bytes.next() {
            stuffer.stuff(chunk, into: &counted)
        }
        stuffer.finish(into: &counted)
        guard bytes.count == plan.length(sizes: files.sizes) else {
            throw LetterSourceFailure(file: nil, reason: .countMismatch)
        }
        let ms = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
        self.plan = plan
        self.files = files
        rehearsal = Rehearsal(rawCount: bytes.count, payloadCount: counted.count,
                              files: bytes.digests, ms: ms)
        pending.reserveCapacity(4 * Self.pieceBytes)
    }

    /// A letter made already, one piece of text: how
    /// `SMTPClient.send(_ raw: Data, …)` sends, through this all the same.
    convenience init(raw: Data) throws {
        try self.init(plan: LetterPlan(pieces: [.text(raw)]), files: LetterFiles(holding: []))
    }

    /// Claims the wire pass for one write, before its first piece. Throws
    /// `LetterSourceFailure` where a write has claimed it already, and the
    /// dot is then never made: a write cut off part of the way, by a
    /// deadline, leaves the rest of the letter here, and the rest is not a
    /// letter.
    func begin() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !begun, case .ready = state else {
            throw withheld(LetterSourceFailure(file: nil, reason: .countMismatch))
        }
        begun = true
    }

    /// The next piece of the wire pass, nil after the last, which ends in
    /// the terminator. Throws `LetterSourceFailure` where the latch does
    /// not hold, a file fails, the pass was not claimed (`begin`), or this
    /// has been used before; the dot is then never made.
    func next() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        var bytes: LetterBytes
        switch state {
        case .ready:
            guard begun else {
                throw withheld(LetterSourceFailure(file: nil, reason: .countMismatch))
            }
            bytes = LetterBytes(plan: plan, files: files, mode: .wire(rehearsal.files))
        case .going(let going):
            bytes = going
        case .done:
            // A second pass would be more bytes than were counted.
            throw withheld(LetterSourceFailure(file: nil, reason: .countMismatch))
        case .failed(let failure):
            throw failure
        }
        do {
            while pending.count < Self.pieceBytes, !latched {
                if let chunk = try bytes.next() {
                    stuffer.stuff(chunk, into: &pending)
                } else {
                    try latch(bytes)
                    stuffer.finish(into: &pending)
                }
            }
        } catch {
            throw withheld(error as? LetterSourceFailure
                           ?? LetterSourceFailure(file: nil, reason: .countMismatch))
        }
        guard !pending.isEmpty else {
            state = .done
            return nil
        }
        state = .going(bytes)
        let length = min(Self.pieceBytes, pending.count)
        let piece = Data(pending[0..<length])
        pending.removeFirst(length)
        handed += length
        return piece
    }

    /// The whole plan made: its count, and what has been stuffed with the
    /// terminator still to come, must be the rehearsal's.
    private func latch(_ bytes: LetterBytes) throws {
        guard bytes.count == rehearsal.rawCount,
              handed + pending.count + stuffer.finishCount == rehearsal.payloadCount else {
            throw LetterSourceFailure(file: nil, reason: .countMismatch)
        }
        latched = true
        Diagnostics.log(.note, "LETTER-LATCH ok raw=\(bytes.count) payload=\(rehearsal.payloadCount)")
    }

    /// The dot withheld for `failure`, said once, and everything made let go.
    private func withheld(_ failure: LetterSourceFailure) -> LetterSourceFailure {
        if case .failed = state { return failure }
        state = .failed(failure)
        pending = []
        Diagnostics.log(.note,
            "LETTER-LATCH withheld file=\(failure.fileNumber) reason=\(failure.words)")
        return failure
    }
}
