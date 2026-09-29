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

    /// `line` plus CRLF.
    func writeLine(_ line: String) async throws

    /// One CRLF-terminated line, without the terminator, decoded leniently.
    /// `wait` is how long the server may take to start answering.
    func readLine(_ wait: ReplyWait) async throws -> String

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
/// what it has just sent. Every read of either kind is cut off if the peer
/// stays silent past its bound: the transport closes the connection and the
/// read fails with `MailTransportError.timedOut`.
enum ReplyWait: Sendable {
    /// The reply to a command line: a round trip and the server's own time.
    /// Silence past the transport's ordinary deadline is a dead peer.
    case ordinary

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
