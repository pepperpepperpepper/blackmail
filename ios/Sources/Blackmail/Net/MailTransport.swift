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

    func write(_ data: Data) async throws

    /// `line` plus CRLF.
    func writeLine(_ line: String) async throws

    /// One CRLF-terminated line, without the terminator, decoded leniently.
    func readLine() async throws -> String

    /// Exactly `count` bytes, CRLFs and all, for an IMAP literal.
    func read(exactly count: Int) async throws -> Data
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
