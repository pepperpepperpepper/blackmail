import Foundation

/// A `MailTransport` over a network link, with everything but the link itself
/// written once, here, for the device and the host tests alike.
///
/// A conformer supplies only the link: start it, receive a chunk, send a
/// piece, let it go. On the device that is `TLSConnection` over
/// `NWConnection`; on the host it is the scripted server's transport. Every
/// decision above that is made in this file: the framing, which deadline a
/// read gets, what happens when one fires, what `close()` ends, and the
/// B-034 probes around a bulk write. It used to be written out twice, once
/// in `TLSConnection`, which never compiles on the host, and once in the
/// scripted transport, so the wire tests could only ever catch a mistake in
/// the copy. Now the lines they exercise are the lines the device runs.
///
/// The link's half has one rule that everything here leans on: a receive or
/// a send ends when bytes move or the link dies, never because the calling
/// task was cancelled, and `closeLink()` ends whatever is pending with an
/// error. That is `NWConnection`'s behaviour, and the scripted transport
/// copies it.
protocol LinkTransport: MailTransport {

    /// What the shared half keeps between calls. A conformer stores it and
    /// leaves it alone.
    var stream: LinkStream { get set }

    /// The bound on the connect as a whole, on each read of an ordinary
    /// reply, and on each piece of a write.
    var ordinaryDeadline: TimeInterval { get }

    /// The bound on a read of `ReplyWait.afterUpload`.
    var uploadReplyDeadline: TimeInterval { get }

    /// The bound on a read of `ReplyWait.serverWork`. Three ordinary
    /// deadlines unless the conformer says otherwise, as `TLSConnection`
    /// does with its ninety seconds.
    var serverWorkDeadline: TimeInterval { get }

    /// Starts connecting, and calls `report` with nil once the link is up or
    /// with the error once it has failed. `report` may be called any number
    /// of times, from any thread, or never: only the first call counts, and
    /// `close()` settles a connect that has not reported.
    func startLink(reporting report: @escaping @Sendable (Error?) -> Void)

    /// The next bytes to arrive, at least one.
    func receiveFromLink() async throws -> Data

    /// Returns once the link has taken `piece`, which is at most
    /// `TransportDeadline.writeChunkBytes`.
    func sendToLink(_ piece: Data) async throws

    /// Lets go of the link. A pending receive or send ends with an error.
    /// Called more than once for the same link, harmlessly.
    func closeLink()

    /// What a caller is told when a send fails. The link's own error is what
    /// the WIRE-ACK probe logs, so the transcript keeps the detail.
    static func transportError(_ sendError: Error) -> Error
}

/// The state `LinkTransport` keeps on a conformer.
struct LinkStream {
    /// Received and not yet read.
    fileprivate(set) var buffer = ReadBuffer()
    fileprivate(set) var isOpen = false
    /// A connect that has not finished, for `close()` to settle.
    fileprivate var opening: LinkOpening?
    /// What each wait for bytes is timed on, once `startTimingQuiet` has
    /// been asked, and the longest wait since.
    fileprivate var quietClock: (@Sendable () -> Date)?
    fileprivate(set) var longestQuiet: TimeInterval = 0
}

extension LinkTransport {

    static func transportError(_ sendError: Error) -> Error { sendError }

    var serverWorkDeadline: TimeInterval { 3 * ordinaryDeadline }

    // MARK: - Lifecycle

    /// Bounded as a whole, not only its TCP half: a peer that accepts the
    /// connection and then sits on the TLS handshake would otherwise hang
    /// `open()`, and the exchange gate held around it, for good. A connect
    /// that times out leaves the transport closed.
    func open() async throws {
        guard !stream.isOpen else { return }
        let opening = LinkOpening()
        stream.opening = opening
        do {
            try await TransportDeadline.race(within: ordinaryDeadline,
                                             onExpiry: { Task { await self.close() } }) {
                try await self.connect(opening)
            }
        } catch {
            if (error as? MailTransportError) == .timedOut {
                noteDeadline("connect", ordinaryDeadline)
                close()
            } else if stream.opening === opening {
                stream.opening = nil
            }
            throw error
        }
        // Closed while it was connecting. The link has been let go of, so
        // whatever it reported, there is nothing open to use.
        guard stream.opening === opening else { throw MailTransportError.closed }
        stream.opening = nil
        stream.isOpen = true
    }

    private func connect(_ opening: LinkOpening) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            guard opening.wait(c) else { return }
            startLink(reporting: { opening.settle($0) })
        }
    }

    /// Also empties the buffer, so nothing already received can be read as
    /// the answer to a later command.
    ///
    /// And settles a connect still in progress, rather than leaving that to
    /// the link. A connect cut off at its deadline is still waiting on the
    /// link's report when the transport is closed, and nothing promises one
    /// will come: `NWConnection` reports `.cancelled` after
    /// `cancel()` only to a state handler it still has. Left waiting, the
    /// connect would hold its task, this transport and the connection for
    /// good, one more for every attempt on a network that swallows the
    /// handshake.
    func close() {
        stream.opening?.settle(MailTransportError.closed)
        stream.opening = nil
        stream.isOpen = false
        stream.buffer = ReadBuffer()
        closeLink()
    }

    // MARK: - Writing

    func write(_ data: Data, progress: UploadProgress?) async throws {
        try await writeThroughLink(data, progress: progress)
    }

    /// `write`, by a name a conformer that watches its writes can call from
    /// its own.
    ///
    /// A piece at a time, each with the ordinary deadline; see
    /// `TransportDeadline.writeChunkBytes`. A write that times out leaves
    /// the transport closed: how much of it reached the server is unknown.
    func writeThroughLink(_ data: Data, progress: UploadProgress? = nil) async throws {
        guard stream.isOpen else { throw MailTransportError.notConnected }
        // B-034 instrumentation. Length only, and only for bulk writes: every
        // command line goes through here too, including `AUTH PLAIN <secret>`,
        // and the length of that line is the length of the credential. A
        // 1 KB floor logs the DATA payload and nothing else.
        let watched = data.count > 1024
        if watched { Diagnostics.log(.note, "WIRE-OUT bytes=\(data.count)") }
        do {
            try await TransportDeadline.write(data, within: ordinaryDeadline,
                                              onExpiry: { Task { await self.close() } },
                                              progress: progress) {
                try await self.sendToLink($0)
            }
        } catch {
            let timedOut = (error as? MailTransportError) == .timedOut
            if timedOut { noteDeadline("write", ordinaryDeadline) }
            // The ACK is the half that matters for "the transport is lying to
            // its own log": a transcript showing the 250 that follows, with no
            // ACK before it, means this write never completed, a different
            // bug with a different next step. One line for the whole write,
            // however many pieces it went in, logged once the last one's
            // completion has come back.
            if watched { Diagnostics.log(.note, "WIRE-ACK err=\(String(describing: error))") }
            if timedOut { close() }
            throw Self.transportError(error)
        }
        if watched { Diagnostics.log(.note, "WIRE-ACK err=none") }
    }

    func writeLine(_ line: String) async throws {
        try await write(Data((line + "\r\n").utf8))
    }

    // MARK: - Reading

    /// Decoded leniently: a server may send a header in any charset, and
    /// throwing on invalid UTF-8 would turn one badly-encoded message into a
    /// dead mailbox. Anything that needs the raw bytes uses `read(exactly:)`.
    func readLine(_ wait: ReplyWait) async throws -> String {
        let bound = bound(for: wait)
        while true {
            if let line = stream.buffer.takeLine() { return MailText.decode(line) }
            try await fill(within: bound, for: wait)
        }
    }

    func startTimingQuiet(on clock: @escaping @Sendable () -> Date) {
        stream.quietClock = clock
        stream.longestQuiet = 0
    }

    var longestQuiet: TimeInterval { stream.longestQuiet }

    private func bound(for wait: ReplyWait) -> TimeInterval {
        switch wait {
        case .ordinary:    return ordinaryDeadline
        case .serverWork:  return serverWorkDeadline
        case .afterUpload: return uploadReplyDeadline
        }
    }

    /// The deadline is per chunk, so a large literal that keeps arriving is
    /// never cut off for its size, only for a silence.
    func read(exactly count: Int) async throws -> Data {
        while true {
            if let out = stream.buffer.take(exactly: count) { return out }
            try await fill(within: ordinaryDeadline, for: .ordinary)
        }
    }

    /// Pulls one chunk from the link into the buffer, or throws. The race is
    /// `ReadBuffer.receiveChunk`: a cancelled caller still gets its chunk,
    /// and a silent peer is cut off at `seconds`.
    ///
    /// A read that timed out leaves the transport closed. Where the reply
    /// had got to is unknown, so the only safe thing a later read on this
    /// transport can do is fail.
    ///
    /// The wait is timed for `longestQuiet`: from asking the link to the
    /// chunk, which is the silence `seconds` bounds.
    private func fill(within seconds: TimeInterval, for wait: ReplyWait) async throws {
        guard stream.isOpen else { throw MailTransportError.notConnected }
        let asked = stream.quietClock?()
        let chunk: Data
        do {
            chunk = try await ReadBuffer.receiveChunk(within: seconds,
                                                      onExpiry: { Task { await self.close() } }) {
                try await self.receiveFromLink()
            }
        } catch MailTransportError.timedOut {
            noteDeadline("read \(wait)", seconds)
            close()
            throw MailTransportError.timedOut
        }
        // Closed while the chunk was on its way: it belongs to nobody now.
        guard stream.isOpen else { throw MailTransportError.closed }
        if let asked, let clock = stream.quietClock {
            stream.longestQuiet = max(stream.longestQuiet, clock().timeIntervalSince(asked))
        }
        stream.buffer.append(chunk)
    }

    /// One transcript line for each deadline that fires, naming it, since
    /// what the user sees, "Can't connect", is the same for a peer that went
    /// quiet as for one that reset the connection. The bound only: nothing
    /// about what was being sent.
    private func noteDeadline(_ which: String, _ seconds: TimeInterval) {
        Diagnostics.log(.note, "DEADLINE \(which) bound=\(String(format: "%g", seconds))s")
    }
}

/// A connect under way: settled by the link's report, from whatever thread
/// it reports on, or by `close()`, whichever comes first. The other finds it
/// already settled. Resuming the continuation twice would be a crash, and
/// never resuming it strands the task waiting on it.
final class LinkOpening: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: CheckedContinuation<Void, Error>?
    private var outcome: Result<Void, Error>?

    /// Parks `c` until the connect is settled, and returns true. If it
    /// already has been, resumes `c` with the outcome at once and returns
    /// false, and the link is never started.
    func wait(_ c: CheckedContinuation<Void, Error>) -> Bool {
        lock.lock()
        guard let outcome else {
            waiting = c
            lock.unlock()
            return true
        }
        lock.unlock()
        c.resume(with: outcome)
        return false
    }

    /// Up if `error` is nil. Only the first call counts.
    func settle(_ error: Error?) {
        lock.lock()
        guard outcome == nil else {
            lock.unlock()
            return
        }
        let result: Result<Void, Error> = error.map { .failure($0) } ?? .success(())
        outcome = result
        let pending = waiting
        waiting = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
