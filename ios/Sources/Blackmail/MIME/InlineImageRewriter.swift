import Foundation

/// Rewriting a message's `cid:` references so something can answer them.
///
/// Pure, and separated from `InlineImageLoader` so the suite on Linux can
/// test it — the loader is WebKit and cannot exist on the test host.
enum InlineImageRewriter {

    /// The custom scheme the body is rewritten to point at.
    ///
    /// WebKit refuses to register a handler for a scheme it already knows —
    /// `http`, `data`, `file` and a dozen more raise an exception at
    /// registration — and `cid` is close enough to that family not to risk
    /// it. This is deliberately a name nothing else can claim.
    static let scheme = "bmcid"

    /// Points every `cid:` reference at the custom scheme.
    ///
    /// Only rewrites ids the message actually HAS. A reference to a part
    /// that is not there stays as `cid:`, where WebKit fails it quietly;
    /// sending it to the handler instead would mean a round trip per
    /// missing image, and messages forwarded through a list routinely
    /// reference images that were stripped on the way. `cid:` is matched in
    /// any case and written back in lower case either way.
    ///
    /// One pass over the bytes. The id runs to the closing quote or the
    /// first character that cannot be in one, all of them ASCII, so the pass
    /// cannot split a character. It used to find each `cid:` with
    /// Foundation's search on the rest of the body, which copied that rest
    /// before searching it, so the time grew with the square of the letter:
    /// 621 pictures in 200 KB took 179 ms on the development computer, and
    /// 3,169 in a megabyte 4.5 s. One difference, on no letter the decoder
    /// hands over: a carriage return now ends an id as a line feed does,
    /// where one written just before a line feed did not, and the decoder
    /// has made every line end in a line feed alone by the time a body gets
    /// here.
    static func rewrite(_ html: String, known: Set<String>) -> String {
        var contiguous = html
        let out = contiguous.withUTF8 { bytes -> [UInt8]? in
            guard let b = bytes.baseAddress else { return nil }
            var out: [UInt8] = []
            var copied = 0
            var i = 0
            let n = bytes.count
            while i + 4 <= n {
                // `| 0x20` lowers an ASCII letter, and no other byte lowers
                // to one of these.
                guard (b[i] | 0x20) == 0x63, (b[i + 1] | 0x20) == 0x69,       // c i
                      (b[i + 2] | 0x20) == 0x64, b[i + 3] == 0x3A else {       // d :
                    i += 1
                    continue
                }
                var end = i + 4
                while end < n, !endsID(b[end]) { end += 1 }
                let id = String(decoding: UnsafeBufferPointer(rebasing: bytes[(i + 4)..<end]),
                                as: UTF8.self)
                if out.isEmpty { out.reserveCapacity(n + n / 8) }
                out.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[copied..<i]))
                if known.contains(id) {
                    out.append(contentsOf: (scheme + "://" + escapedHost(id)).utf8)
                } else {
                    out.append(contentsOf: "cid:".utf8)
                    out.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[(i + 4)..<end]))
                }
                copied = end
                i = end
            }
            guard copied > 0 else { return nil }
            out.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[copied..<n]))
            return out
        }
        return out.map { String(decoding: $0, as: UTF8.self) } ?? html
    }

    /// The characters that end a `cid:` id.
    private static func endsID(_ c: UInt8) -> Bool {
        switch c {
        case 0x22, 0x27, 0x20, 0x3E, 0x29, 0x0A, 0x0D, 0x09: return true   // " ' space > ) LF CR tab
        default: return false
        }
    }

    /// A `Content-ID` is allowed characters a URL host is not, so it is
    /// percent-encoded on the way out and decoded again in the handler.
    static func escapedHost(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: hostCharacters) ?? id
    }

    private static let hostCharacters = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "-._~"))
}
