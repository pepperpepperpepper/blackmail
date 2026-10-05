import Foundation

/// SMTP's dot-stuffing over a letter that comes in pieces, cut anywhere
/// (B-070): what goes after DATA's 354, the same bytes whether the letter
/// is stuffed whole (`SMTPClient.dataPayload`) or a piece at a time as it
/// goes (`DataStream`).
///
/// Two rules, and the terminator. A line that begins with a dot gets a
/// second one, since a line of a lone dot ends DATA and the rest of the
/// letter would be lost with nothing said. Any line break, CR, LF or the
/// pair, goes out as CRLF, the pair as one break even where a piece ends
/// between its CR and its LF. Then `finish` writes the terminator, a dot
/// on a line of its own.
///
/// Every byte goes through it, base64 included. The builder's letters need
/// no stuffing (`LetterPlanTests`), but this takes nothing on faith.
///
/// The state is three flags, carried from one piece to the next.
struct DataStuffer {

    private static let cr: UInt8 = 0x0D, lf: UInt8 = 0x0A, dot: UInt8 = 0x2E

    /// What comes next begins a line.
    private(set) var atLineStart = true
    /// The last piece ended in a CR, already written as CRLF: an LF that
    /// begins the next is its pair, and is not written again.
    private var afterCR = false
    /// Anything has been written.
    private(set) var consumed = false

    init() {}

    /// `input`, stuffed, onto the end of `out`.
    ///
    /// A run at a time: everything up to the next CR or LF is written in
    /// one piece, and only the line breaks and a dot at the start of a line
    /// are looked at on their own. On a letter of base64 lines that is one
    /// step for every 76 bytes.
    mutating func stuff<Sink: StuffedSink>(_ input: UnsafeRawBufferPointer, into out: inout Sink) {
        let bytes = input.bindMemory(to: UInt8.self)
        let count = bytes.count
        guard count > 0 else { return }
        let cr = Self.cr, lf = Self.lf, dot = Self.dot
        var start = 0
        if afterCR {
            afterCR = false
            if bytes[0] == lf { start = 1 }
        }
        while start < count {
            if atLineStart, bytes[start] == dot { out.put(dot) }
            var end = start
            while end < count, bytes[end] != cr, bytes[end] != lf { end += 1 }
            if end > start {
                out.put(UnsafeBufferPointer(rebasing: bytes[start..<end]))
                atLineStart = false
                consumed = true
            }
            guard end < count else { break }
            out.put(cr)
            out.put(lf)
            atLineStart = true
            consumed = true
            if bytes[end] == cr {
                if end + 1 < count {
                    start = end + (bytes[end + 1] == lf ? 2 : 1)
                } else {
                    afterCR = true
                    start = count
                }
            } else {
                start = end + 1
            }
        }
    }

    /// How many bytes `finish` will write: a CRLF unless what went before
    /// ended a line, then the dot and its CRLF.
    var finishCount: Int { consumed && atLineStart ? 3 : 5 }

    /// The terminator onto the end of `out`.
    mutating func finish<Sink: StuffedSink>(into out: inout Sink) {
        if !(consumed && atLineStart) {
            out.put(Self.cr)
            out.put(Self.lf)
        }
        out.put(Self.dot)
        out.put(Self.cr)
        out.put(Self.lf)
        atLineStart = true
        consumed = true
    }
}

/// Where stuffed bytes go: a byte array for the wire, or a count for the
/// rehearsal, which keeps none of them.
protocol StuffedSink {
    mutating func put(_ byte: UInt8)
    mutating func put(_ run: UnsafeBufferPointer<UInt8>)
}

extension Array: StuffedSink where Element == UInt8 {
    mutating func put(_ byte: UInt8) { append(byte) }
    mutating func put(_ run: UnsafeBufferPointer<UInt8>) { append(contentsOf: run) }
}

/// Counts what it is given and keeps nothing.
struct StuffedCount: StuffedSink {
    private(set) var count = 0
    mutating func put(_ byte: UInt8) { count += 1 }
    mutating func put(_ run: UnsafeBufferPointer<UInt8>) { count += run.count }
}
