import Foundation

/// The byte stream the mail protocols run over, as the two clients see it.
///
/// Exactly the surface `IMAPClient` and `SMTPClient` already used on
/// `TLSConnection`, and nothing more: open, close, write bytes or a line,
/// read a line or an exact count. Pulled out as a protocol so that everything
/// above the socket compiles on the Linux host too. On the device the only
/// conformer is `TLSConnection`, so the wire is byte-for-byte what it was; on
/// the host the tests hand the clients a scripted server instead, which is
/// how the real command layer and the real repository get exercised without a
/// device, a network or a mailbox.
///
/// Actor-constrained rather than a plain class protocol because both
/// conformers are actors and every call site already `await`s across an
/// isolation boundary. It also makes every transport `Sendable`, which the
/// factory below needs to hand one from the actor that makes it to the actor
/// that uses it.
///
/// Framing is deliberately the transport's job and not the caller's. IMAP's
/// `{n}` literals mean a reader has to switch between "up to the next CRLF"
/// and "exactly n bytes" on one shared buffer, and both clients depend on
/// those two reads never losing a byte between them.
protocol MailTransport: Actor {
    /// Connects and completes the TLS handshake. Calling it on a transport
    /// that is already open does nothing.
    func open() async throws

    /// Lets go of the socket. Never throws: closing is what every failure
    /// path does, and it must not be able to fail in turn.
    func close()

    /// Hands `data` to the stack a piece at a time, each piece allowed the
    /// transport's ordinary deadline. A large write that is still moving is
    /// never cut off for its size; one that has stopped is. See
    /// `TransportDeadline.writeChunkBytes`.
    ///
    /// `progress`, if given, hears after each piece how much of `data` the
    /// stack has taken so far. See `UploadProgress` for what that does and
    /// does not say.
    func write(_ data: Data, progress: UploadProgress?) async throws

    /// Hands `source` to the stack a piece at a time, as `write` hands its
    /// data, asking it for each piece only once the one before has gone: a
    /// letter made as it goes (`DataStream`, B-070). One write as far as the
    /// transcript and the progress are concerned, of `source.total` bytes.
    ///
    /// A `LetterSourceFailure` from `source` leaves the transport closed,
    /// so nothing more can be written, and is thrown as it is.
    func write(from source: WriteSource, progress: UploadProgress?) async throws

    /// `line` plus CRLF.
    func writeLine(_ line: String) async throws

    /// One CRLF-terminated line, without the terminator, decoded leniently.
    /// `wait` is how long the server may take to start answering.
    func readLine(_ wait: ReplyWait) async throws -> String

    /// Starts timing the reads afresh, on `clock`: from now on
    /// `longestQuiet` is the longest any one wait for bytes has lasted.
    /// Each such wait is what a read's bound is on, a silence, and not an
    /// answer as a whole. How `IMAPClient` tells how near a command's
    /// answer came to its bound.
    func startTimingQuiet(on clock: @escaping @Sendable () -> Date)

    /// The longest one wait for bytes has lasted since `startTimingQuiet`,
    /// in seconds on its clock. Nought if nothing has been waited for.
    var longestQuiet: TimeInterval { get }

    /// Exactly `count` bytes, CRLFs and all, for an IMAP literal.
    func read(exactly count: Int) async throws -> Data
}

extension MailTransport {

    /// `data`, with nobody told how it is getting on: a command line, or a
    /// draft going up.
    func write(_ data: Data) async throws {
        try await write(data, progress: nil)
    }

    /// A line of an ordinary reply.
    func readLine() async throws -> String {
        try await readLine(.ordinary)
    }
}

/// How long a read may wait for the server to start answering.
///
/// Chosen per call rather than per connection, because only the caller knows
/// what it has just sent. Every read, of whichever kind, is cut off if the
/// peer stays silent past its bound: the transport closes the connection
/// and the read fails with `MailTransportError.timedOut`.
enum ReplyWait: Sendable {
    /// The reply to a command line: a round trip and the server's own time.
    /// Silence past the transport's ordinary deadline is a dead peer.
    case ordinary

    /// The reply to a command the server has to work through his mailbox to
    /// answer before it can say anything: SEARCH, SELECT and STATUS.
    ///
    /// Gmail answers each of these only once it has the whole answer, and
    /// the time that takes grows with the mailbox: a SEARCH of his All Mail
    /// is over 250,000 letters and grows by about 45,000 a year. How long
    /// Gmail takes at his size has never been measured. On the ordinary
    /// bound, one that took it longer than 30 seconds would fail every
    /// time: the read retry's reconnect would ask it again and fail again,
    /// and the folder would say "Can't connect" for good, with nothing on
    /// the iPad able to change it. Every other reply keeps the ordinary
    /// bound, so a dead line is still found in half a minute everywhere but
    /// here.
    ///
    /// For each line of the answer up to its tagged line, not only the
    /// first: Gmail may say a line at once, an EXISTS it owes the session
    /// or SELECT's FLAGS, and work through the mailbox after it.
    case serverWork

    /// The reply to a large upload: SMTP's after DATA's terminating dot, and
    /// IMAP's tagged reply after an APPEND literal.
    ///
    /// A write returns once the stack has taken the bytes, and the stack can
    /// still be holding a lot of them that a slow uplink has not carried yet.
    /// The server answers only once all of it has arrived and been dealt
    /// with, so the ordinary bound would fire on a letter that is going out
    /// perfectly well. That is the worst timeout to get wrong: the letter
    /// arrives, he is told it did not, and he sends it again.
    case afterUpload
}

/// How much of a write the stack has taken, `written` of `total` bytes,
/// told once for each piece of it (`TransportDeadline.writeChunkBytes`) as
/// the stack takes it. Called from whatever thread the write resumes on
/// after the piece, not on the transport's actor: `TransportDeadline.write`
/// is not isolated to it. A listener with state of its own hops to its own
/// actor, as the composer does to the main one.
///
/// Taken, not delivered. The stack holds what it has taken until the far end
/// acknowledges it, and on a slow uplink that can be the last few hundred
/// kilobytes of a letter, so the count runs ahead of the line by about that
/// much and reaches the total before the server has the letter. What it
/// measures is the part that takes the time on a photo letter, the upload
/// itself, and it costs nothing: the pieces already exist for the deadline.
typealias UploadProgress = @Sendable (_ written: Int, _ total: Int) -> Void

/// Bytes for one write, made a piece at a time as the write asks for them
/// (`MailTransport.write(from:progress:)`), `total` of them in all. Asked
/// by one write at a time, never two, and never from inside a deadline:
/// making a piece is not the network's time (`TransportDeadline`).
protocol WriteSource: AnyObject, Sendable {
    /// What the pieces come to.
    var total: Int { get }
    /// Claims the source for one write, before its first piece is asked
    /// for. Throws for a source a write has claimed already: the rest of a
    /// letter must never go as a letter of its own.
    func begin() throws
    /// The next piece, nil after the last.
    func next() throws -> Data?
}

/// Makes an UNOPENED transport to one host and port.
///
/// A factory rather than a transport because a client needs a fresh one for
/// every connection: `IMAPClient` reconnects after a dropped socket, and
/// `SMTPClient` opens one per letter.
typealias MailTransportFactory = @Sendable (_ host: String, _ port: UInt16) -> any MailTransport

/// How a transport fails.
///
/// Lives here rather than inside `TLSConnection`, which is behind
/// `#if canImport(Network)`, so that code compiled on every platform can name
/// the cases and a fake transport can fail the same ways the real one does.
/// None of this text reaches the user: the clients flatten every one of these
/// to a `MailError`.
enum MailTransportError: Error, Equatable {
    case notConnected
    case closed
    case timedOut
    case tls(String)
    case posix(String)
}
