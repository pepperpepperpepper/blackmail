import Foundation

/// The bytes a transport has received and not yet handed on, framed the two
/// ways the mail protocols read them: up to the next CRLF, or exactly n
/// bytes for an IMAP literal.
///
/// Out here, Foundation-only, rather than inside `TLSConnection`, which is
/// behind `#if canImport(Network)` and never runs on the host. The scripted
/// transport the wire tests run through uses this same type, so the framing
/// those tests exercise is the framing the device runs, not a copy of it
/// that could drift, and `ReadBufferTests` can test it directly.
struct ReadBuffer {

    /// Received and not yet read. Readable from outside only so a test can
    /// see what the buffer is holding on to.
    private(set) var bytes = Data()

    var isEmpty: Bool { bytes.isEmpty }

    mutating func append(_ chunk: Data) {
        bytes.append(chunk)
    }

    /// The next line without its CRLF, or nil until a whole one is here.
    ///
    /// `startIndex` everywhere rather than 0, because removing from the
    /// front of a `Data` leaves its indices where they were: after
    /// `removeFirst(100)` the first byte is at index 100.
    mutating func takeLine() -> Data? {
        guard let range = bytes.range(of: Data([0x0D, 0x0A])) else { return nil }
        let line = bytes.subdata(in: bytes.startIndex..<range.lowerBound)
        bytes.removeSubrange(bytes.startIndex..<range.upperBound)
        releaseIfDrained()
        return line
    }

    /// Exactly `count` bytes, CRLFs and all, or nil until that many are here.
    /// A literal's length comes from the `{n}` the server just sent, so this
    /// must not stop at a CRLF: a message body is full of them.
    mutating func take(exactly count: Int) -> Data? {
        guard bytes.count >= count else { return nil }
        let out = bytes.prefix(count)
        bytes.removeFirst(count)
        releaseIfDrained()
        return Data(out)
    }

    /// Lets go of the storage once every byte in it has been read.
    ///
    /// Removing bytes from a `Data` never shrinks its allocation, so after a
    /// 25 MB literal the buffer went on holding 25 MB with a count of zero,
    /// for as long as the socket lived, which through a suspension is the
    /// whole time he is away. Across a few large letters that ratcheted past
    /// 50 MB on a device where memory is what decides whether the app is
    /// still there when he comes back. A fresh `Data` costs nothing; the next
    /// chunk allocates what it needs.
    ///
    /// Called after a line as well as after a literal, and the line is the
    /// one that matters: a literal is always followed by at least `)` and
    /// the tagged line, so the buffer is practically never empty straight
    /// after one. It is empty once that tagged line has been read, which is
    /// where almost every exchange ends.
    private mutating func releaseIfDrained() {
        if bytes.isEmpty { bytes = Data() }
    }
}

extension ReadBuffer {

    /// One chunk from `receive`, raced against a read deadline: the half of
    /// `LinkTransport`'s read that decides when it gives up.
    ///
    /// Both transports read through it, the scripted one with a receive that
    /// ignores cancellation the way `NWConnection.receive` does and that
    /// fails once the connection is closed, so a wire test sees what the
    /// device does when a caller is cancelled or a peer goes quiet.
    ///
    /// A cancelled caller still gets its chunk: the reply it was reading
    /// stays whole and the next command reads its own. A peer that says
    /// nothing is cut off at `timeout`: `expire` closes the connection, which
    /// ends the receive, and the read fails with `.timedOut`. See
    /// `TransportDeadline` for why neither of those is a task group.
    static func receiveChunk(within timeout: TimeInterval,
                             onExpiry expire: @escaping @Sendable () -> Void,
                             from receive: @escaping @Sendable () async throws -> Data)
        async throws -> Data {
        try await TransportDeadline.race(within: timeout, onExpiry: expire, receive)
    }
}
