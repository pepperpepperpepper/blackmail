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

    /// How many bytes at the front of `bytes` a line search has already
    /// looked through and found no CRLF starting in, but for the last of
    /// them, a CR whose LF may be the first byte of the next chunk. The
    /// next search starts at that last byte rather than at the front.
    ///
    /// A count from the front, used only as an offset into the bytes
    /// themselves (`lineEnd`), never as an index of the `Data`: removing
    /// from the front of a `Data` leaves its indices where they were, and
    /// an index made from a count then points past a CRLF and desyncs the
    /// stream. Back to nought whenever bytes leave the front, by a line,
    /// by a literal, or by the buffer being let go of, so it can never
    /// count bytes that are no longer there.
    private var scanned = 0

    /// Bytes looked at by every line search so far, for a test to hold the
    /// search to about once a byte however the chunks cut a line.
    private(set) var examined = 0

    var isEmpty: Bool { bytes.isEmpty }

    mutating func append(_ chunk: Data) {
        bytes.append(chunk)
    }

    /// The next line without its CRLF, or nil until a whole one is here.
    ///
    /// Searched from where the last search left off. A line comes in chunks
    /// of a few kilobytes and this is asked after each, so searching from
    /// the front every time went over a long line once for every chunk of
    /// it: a SEARCH answer of his All Mail, about 3 MB, in 16 KB chunks is
    /// near 300 MB of searching, where this looks at each byte once.
    ///
    /// `startIndex` rather than 0 for the slices, because removing from the
    /// front of a `Data` leaves its indices where they were: after
    /// `removeFirst(100)` the first byte is at index 100.
    mutating func takeLine() -> Data? {
        let from = max(0, scanned - 1)
        guard let end = Self.lineEnd(in: bytes, from: from) else {
            examined += bytes.count - from
            scanned = bytes.count
            return nil
        }
        examined += end + 2 - from
        let start = bytes.startIndex
        let line = bytes.subdata(in: start..<(start + end))
        bytes.removeSubrange(start..<(start + end + 2))
        scanned = 0
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
        scanned = 0
        releaseIfDrained()
        return Data(out)
    }

    /// Where the first CR followed by LF is in `data`, counted from its
    /// first byte, looking no earlier than `start`; nil if there is none.
    /// A CR that is the last byte is not a line end yet.
    private static func lineEnd(in data: Data, from start: Int) -> Int? {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int? in
            guard let base = raw.baseAddress else { return nil }
            let count = raw.count
            var at = start
            while at < count - 1 {
                guard let found = memchr(base + at, 0x0D, count - at) else { return nil }
                let cr = base.distance(to: UnsafeRawPointer(found))
                guard cr < count - 1 else { return nil }
                if raw[cr + 1] == 0x0A { return cr }
                at = cr + 1
            }
            return nil
        }
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
