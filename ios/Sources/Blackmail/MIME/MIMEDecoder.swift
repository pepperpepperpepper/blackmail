import Foundation

/// MIME, decoded: bytes in, structure and readable text out.
///
/// Every function here is pure, so all of it can be exercised from a unit test
/// with a literal `Data` and no server — which matters, because there is no
/// simulator and every on-device check costs a build, sign and deploy cycle.
///
/// The governing rule for the whole file is that nothing may fail. Real mail
/// is full of encoders that truncate base64, omit a boundary, label UTF-8 as
/// us-ascii, or fold a header in the middle of a multi-byte character. A
/// parser that threw on any of those would turn one bad message into an empty
/// mailbox, and the man reading this screen would conclude his mail is gone.
/// So every path here ends in *something*: an undecodable charset falls back
/// to Latin-1, which is defined for all 256 byte values and therefore cannot
/// fail; an unterminated multipart yields the parts that did arrive; a
/// multipart with no boundary is shown as plain text rather than as nothing.
enum MIMEDecoder {

    /// How deep we will walk a nested message. Twenty is far past anything a
    /// real mailer produces (three or four is typical: mixed → alternative →
    /// related), and the cap is what stops a deliberately self-nesting message
    /// from exhausting the stack.
    private static let maxDepth = 20

    /// And a ceiling on siblings, for the same reason: a body consisting of
    /// nothing but ten thousand boundary lines should cost us one bounded walk,
    /// not ten thousand `MIMEPart`s.
    private static let maxPartsPerMultipart = 500

    // MARK: - Content-Transfer-Encoding

    /// Undoes the transfer encoding and nothing else. "7bit", "8bit", "binary"
    /// and anything unrecognised pass through untouched, which is the lenient
    /// choice: handing back the raw bytes shows mojibake at worst, whereas
    /// returning empty data shows nothing at all.
    static func decodeTransfer(_ data: Data, encoding: String) -> Data {
        switch normalizedToken(encoding) {
        case "base64":           return decodeBase64(data)
        case "quoted-printable": return decodeQuotedPrintable(data)
        default:                 return data
        }
    }

    /// Base64 that never rejects its input.
    ///
    /// `Data(base64Encoded:)` is not usable here: even with
    /// `.ignoreUnknownCharacters` it returns nil when the surviving character
    /// count is not a multiple of four, and truncated-without-padding base64 is
    /// something senders really do emit. Decoding a bit at a time means a
    /// damaged tail costs the last character rather than the whole attachment.
    private static func decodeBase64(_ data: Data) -> Data {
        var out = Data()
        out.reserveCapacity(data.count * 3 / 4 + 3)
        var accumulator: UInt32 = 0
        var bits = 0
        for byte in data {
            let value: UInt32
            switch byte {
            case 0x41...0x5A: value = UInt32(byte - 0x41)          // A-Z
            case 0x61...0x7A: value = UInt32(byte - 0x61) + 26     // a-z
            case 0x30...0x39: value = UInt32(byte - 0x30) + 52     // 0-9
            case 0x2B, 0x2D:  value = 62                           // '+', and base64url '-'
            case 0x2F, 0x5F:  value = 63                           // '/', and base64url '_'
            case 0x3D:
                // '=' ends a quantum. Resetting rather than ignoring is what
                // makes a message whose body is several separately padded
                // base64 blocks glued together decode correctly instead of
                // sliding six bits out of alignment at the join.
                accumulator = 0
                bits = 0
                continue
            default:
                continue                                           // white space, CRLF, junk
            }
            accumulator = ((accumulator << 6) | value) & 0xFFFF
            bits += 6
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((accumulator >> UInt32(bits)) & 0xFF))
            }
        }
        return out
    }

    private static func decodeQuotedPrintable(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        // The accumulator is a plain array and not `Data` because this loop
        // pops bytes back off the end. `Data.removeLast()` has no override and
        // falls through to `replaceSubrange`, which costs O(n) every call, so a
        // body whose lines end in white space — which is most of them — decoded
        // in quadratic time: five megabytes took twenty-two seconds on the main
        // thread before a single word of it reached the screen.
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        // Everything below this mark came out of an explicit `=XX` escape and
        // is therefore the sender's own byte. RFC 2045 says to delete trailing
        // white space because a *transport* may have added it; a `=20` written
        // at the end of a line is the opposite, the sender insisting that this
        // particular space is real, and deleting it corrupts the text.
        var protected = 0
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]

            if byte == 0x3D {                                      // '='
                // Soft line break: an '=' with nothing after it on the line.
                // Both CRLF and a bare LF appear in the wild.
                if i + 2 < bytes.count, bytes[i + 1] == 0x0D, bytes[i + 2] == 0x0A { i += 3; continue }
                if i + 1 < bytes.count, bytes[i + 1] == 0x0A { i += 2; continue }
                if i + 1 < bytes.count, bytes[i + 1] == 0x0D, i + 2 == bytes.count { i += 2; continue }
                if i + 1 == bytes.count { i += 1; continue }
                if i + 2 < bytes.count,
                   let high = hexValue(bytes[i + 1]), let low = hexValue(bytes[i + 2]) {
                    out.append((high << 4) | low)
                    protected = out.count
                    i += 3
                    continue
                }
                // Not a valid escape, so it is a literal '=' the sender never
                // encoded. Keeping it is what stops "Cost = 5" losing its sign.
                out.append(byte)
                i += 1
                continue
            }

            if byte == 0x0A {
                // RFC 2045 says white space before a hard line break is
                // transport padding and must be dropped; leaving it in makes
                // quoted text look ragged when it is re-wrapped.
                var hadCR = false
                if out.count > protected, out.last == 0x0D { out.removeLast(); hadCR = true }
                while out.count > protected, let last = out.last, last == 0x20 || last == 0x09 {
                    out.removeLast()
                }
                if hadCR { out.append(0x0D) }
                out.append(0x0A)
                i += 1
                continue
            }

            out.append(byte)
            i += 1
        }
        return Data(out)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: return byte - 0x30            // 0-9
        case 0x41...0x46: return byte - 0x41 + 10       // A-F
        case 0x61...0x66: return byte - 0x61 + 10       // a-f, which the RFC forbids and senders use anyway
        default:          return nil
        }
    }

    // MARK: - Text

    /// Transfer-decode, then charset-decode, then normalise line endings to
    /// plain `\n` so the UI does not have to think about CRLF.
    static func decodeText(_ data: Data, encoding: String, charset: String?) -> String {
        string(from: decodeTransfer(data, encoding: encoding), charset: charset)
    }

    /// Bytes to text, with the declared charset as a hint rather than as law.
    ///
    /// The last resort is Latin-1 because it is total: every byte sequence is a
    /// valid Latin-1 string, so this function has no failure mode.
    private static func string(from data: Data, charset: String?) -> String {
        guard !data.isEmpty else { return "" }
        let name = normalizedToken(charset ?? "")
        var decoded: String?

        if let declared = encoding(for: name) {
            // A Western single-byte label is the one claim worth second-guessing.
            // "us-ascii" or "iso-8859-1" on bytes that are valid UTF-8 with at
            // least one multi-byte sequence is a mislabelled UTF-8 message —
            // common from web forms — and trusting the label would show "Ã©"
            // where the sender wrote "é". Latin-1 text that happens to be valid
            // UTF-8 by accident is vanishingly rare, so the trade favours UTF-8.
            if isWesternSingleByte(name), looksLikeUTF8(data) {
                decoded = String(data: data, encoding: .utf8)
            }
            if decoded == nil { decoded = String(data: data, encoding: declared) }
        }
        if decoded == nil { decoded = String(data: data, encoding: .utf8) }
        let text = decoded ?? String(data: data, encoding: .isoLatin1) ?? ""
        return normalizeNewlines(stripBOM(text))
    }

    private static func looksLikeUTF8(_ data: Data) -> Bool {
        guard data.contains(where: { $0 >= 0x80 }) else { return false }
        return String(data: data, encoding: .utf8) != nil
    }

    private static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    private static func normalizeNewlines(_ text: String) -> String {
        guard text.contains("\r") else { return text }
        return text.replacingOccurrences(of: "\r\n", with: "\n")
                   .replacingOccurrences(of: "\r", with: "\n")
    }

    /// An `NSStringEncoding` for a charset that Cocoa never gave a constant.
    ///
    /// Cocoa numbers those as the CoreFoundation encoding with the high bit
    /// set, so `kCFStringEncodingBig5` (0x0A03) is `0x80000A03`. The literals
    /// are written out rather than obtained from `CFStringConvertEncoding…`
    /// so that this file needs nothing but Foundation, and because the failure
    /// mode is harmless either way: a value this SDK does not recognise makes
    /// `String(data:encoding:)` return nil, and we fall through to Latin-1.
    private static func cfEncoding(_ value: UInt32) -> String.Encoding {
        String.Encoding(rawValue: UInt(0x8000_0000 | value))
    }

    private static func encoding(for name: String) -> String.Encoding? {
        switch name {
        case "utf-8", "utf8", "unicode-1-1-utf-8", "x-unicode-2-0-utf-8":
            return .utf8
        case "us-ascii", "ascii", "iso-ir-6", "ansi_x3.4-1968", "iso646-us", "us", "646":
            return .ascii
        case "iso-8859-1", "iso8859-1", "iso_8859-1", "8859-1", "latin1", "l1", "cp819", "iso-ir-100":
            return .isoLatin1
        case "iso-8859-2", "iso8859-2", "iso_8859-2", "latin2", "l2":
            return .isoLatin2
        case "iso-8859-15", "iso8859-15", "iso_8859-15", "latin9", "l9":
            return cfEncoding(0x020F)                 // kCFStringEncodingISOLatin9
        case "iso-8859-5", "iso8859-5", "cyrillic":
            return cfEncoding(0x0205)                 // kCFStringEncodingISOLatinCyrillic
        case "iso-8859-7", "iso8859-7", "greek", "greek8":
            return cfEncoding(0x0207)                 // kCFStringEncodingISOLatinGreek
        case "iso-8859-9", "iso8859-9", "latin5", "l5":
            return cfEncoding(0x0209)                 // kCFStringEncodingISOLatin5
        case "windows-1250", "cp1250", "x-cp1250":
            return .windowsCP1250
        case "windows-1251", "cp1251", "x-cp1251":
            return .windowsCP1251
        case "windows-1252", "cp1252", "x-cp1252", "ansi":
            return .windowsCP1252
        case "windows-1253", "cp1253":
            return .windowsCP1253
        case "windows-1254", "cp1254":
            return .windowsCP1254
        case "windows-1255", "cp1255":
            return cfEncoding(0x0505)                 // kCFStringEncodingWindowsHebrew
        case "windows-1256", "cp1256":
            return cfEncoding(0x0506)                 // kCFStringEncodingWindowsArabic
        case "windows-1257", "cp1257":
            return cfEncoding(0x0507)                 // kCFStringEncodingWindowsBalticRim
        case "windows-1258", "cp1258":
            return cfEncoding(0x0508)                 // kCFStringEncodingWindowsVietnamese
        case "koi8-r", "koi8_r", "koi8":
            return cfEncoding(0x0A02)                 // kCFStringEncodingKOI8_R
        case "koi8-u", "koi8_u":
            return cfEncoding(0x0A0C)                 // kCFStringEncodingKOI8_U
        case "shift_jis", "shift-jis", "sjis", "x-sjis", "ms_kanji", "cp932", "windows-31j":
            return .shiftJIS
        case "euc-jp", "eucjp", "euc_jp", "x-euc-jp", "extended_unix_code_packed_format_for_japanese":
            return .japaneseEUC
        case "iso-2022-jp", "iso2022jp", "csiso2022jp", "iso-2022-jp-2":
            return .iso2022JP
        case "gb2312", "gb_2312-80", "gbk", "gb18030", "cp936", "ms936", "x-gbk", "euc-cn", "csgb2312":
            // GB18030 is a strict superset of GBK, which is a strict superset
            // of GB2312, so one decoder reads all three labels correctly and
            // the two older ones do not need their own (less available) id.
            return cfEncoding(0x0632)                 // kCFStringEncodingGB_18030_2000
        case "big5", "big-5", "big5-eten", "cn-big5", "csbig5", "cp950":
            return cfEncoding(0x0A03)                 // kCFStringEncodingBig5
        case "big5-hkscs", "big5hkscs":
            return cfEncoding(0x0A06)                 // kCFStringEncodingBig5_HKSCS_1999
        case "euc-kr", "euckr", "ks_c_5601-1987", "ks_c_5601-1989", "korean", "cp949":
            return cfEncoding(0x0940)                 // kCFStringEncodingEUC_KR
        case "macintosh", "mac", "x-mac-roman":
            return .macOSRoman
        case "utf-16", "utf16", "unicode":
            return .utf16                             // honours a BOM, unlike the explicit-endian pair
        case "utf-16be", "utf16be":
            return .utf16BigEndian
        case "utf-16le", "utf16le":
            return .utf16LittleEndian
        case "utf-32", "utf32":
            return .utf32
        case "utf-32be", "utf32be":
            return .utf32BigEndian
        case "utf-32le", "utf32le":
            return .utf32LittleEndian
        default:
            return nil
        }
    }

    /// The labels whose bytes are worth sniffing for UTF-8 first. Deliberately
    /// only the Western single-byte sets: a KOI8-R or Shift_JIS label is nearly
    /// always deliberate, and second-guessing it would do harm.
    private static func isWesternSingleByte(_ name: String) -> Bool {
        switch name {
        case "us-ascii", "ascii", "iso-ir-6", "ansi_x3.4-1968", "iso646-us", "us", "646",
             "iso-8859-1", "iso8859-1", "iso_8859-1", "8859-1", "latin1", "l1", "cp819", "iso-ir-100",
             "iso-8859-15", "iso8859-15", "iso_8859-15", "latin9", "l9",
             "windows-1252", "cp1252", "x-cp1252", "ansi":
            return true
        default:
            return false
        }
    }

    // MARK: - RFC 2047 encoded words

    private enum Token2047 {
        case literal(String)
        case word(charset: String, encoding: Character, payload: String)
    }

    /// Decodes `=?utf-8?B?…?=` / `=?iso-8859-1?Q?…?=` runs inside a header
    /// value, leaving everything around them alone.
    ///
    /// Two rules here are easy to miss and both show up in ordinary Gmail
    /// traffic. White space *between* two encoded words is not part of the
    /// text and disappears (RFC 2047 §6.2), which is how a long subject folds
    /// without gaining spaces. And adjacent words in the same charset must have
    /// their *bytes* joined before decoding, not their strings: Gmail splits a
    /// subject at 75 characters with no regard for where a UTF-8 sequence ends,
    /// so decoding each word alone would drop the character straddling the cut.
    static func decodeWord(_ text: String) -> String {
        guard text.contains("=?") else { return text }

        var out = ""
        var pendingCharset: String?
        var pendingBytes = Data()

        func flush() {
            guard let charset = pendingCharset else { return }
            out += string(from: pendingBytes, charset: charset)
            pendingCharset = nil
            pendingBytes = Data()
        }

        let tokens = tokenize2047(text)
        for (index, token) in tokens.enumerated() {
            switch token {
            case .literal(let literal):
                let isGap = !literal.isEmpty && literal.allSatisfy {
                    $0 == " " || $0 == "\t" || $0 == "\r" || $0 == "\n"
                }
                // `pendingCharset != nil` is exactly "the previous token was an
                // encoded word", so this drops the separator only between two
                // of them and never at the edges of the header.
                if isGap, pendingCharset != nil, index + 1 < tokens.count,
                   case .word = tokens[index + 1] {
                    continue
                }
                flush()
                out += literal

            case .word(let charset, let wordEncoding, let payload):
                let bytes: Data
                if wordEncoding == "b" {
                    bytes = decodeBase64(Data(payload.utf8))
                } else {
                    bytes = decodeQ(payload, charset: charset)
                }
                if pendingCharset == charset {
                    pendingBytes.append(bytes)
                } else {
                    flush()
                    pendingCharset = charset
                    pendingBytes = bytes
                }
            }
        }
        flush()
        return out
    }

    private static func tokenize2047(_ text: String) -> [Token2047] {
        let chars = Array(text)
        // Where the next "?=" and the next line break sit, from every position.
        // Precomputing them is what keeps this linear: a header full of "=?"
        // openings that never close made each one rescan the whole rest of the
        // string, and 112 KB of `=?a?Q?x` took fifty-five seconds — a message
        // anyone can send, hanging the app on the main thread.
        let terminator = nextPairTable(chars, first: "?", second: "=")
        let lineBreak = nextBreakTable(chars)
        var tokens: [Token2047] = []
        var literal = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "=", i + 1 < chars.count, chars[i + 1] == "?",
               let scanned = scanWord2047(chars, from: i, terminator: terminator, lineBreak: lineBreak) {
                if !literal.isEmpty {
                    tokens.append(.literal(literal))
                    literal = ""
                }
                tokens.append(scanned.token)
                i = scanned.next
                continue
            }
            literal.append(chars[i])
            i += 1
        }
        if !literal.isEmpty { tokens.append(.literal(literal)) }
        return tokens
    }

    /// `table[i]` is the index of the first `first`+`second` pair at or after
    /// `i`, or `chars.count` when there is none. One backwards pass, so the
    /// scanner can find a closing "?=" in constant time instead of walking.
    private static func nextPairTable(_ chars: [Character], first: Character, second: Character) -> [Int] {
        var table = [Int](repeating: chars.count, count: chars.count + 1)
        guard chars.count >= 2 else { return table }
        for i in stride(from: chars.count - 2, through: 0, by: -1) {
            table[i] = (chars[i] == first && chars[i + 1] == second) ? i : table[i + 1]
        }
        return table
    }

    private static func nextBreakTable(_ chars: [Character]) -> [Int] {
        var table = [Int](repeating: chars.count, count: chars.count + 1)
        for i in stride(from: chars.count - 1, through: 0, by: -1) {
            table[i] = (chars[i] == "\n" || chars[i] == "\r") ? i : table[i + 1]
        }
        return table
    }

    /// Reads one encoded word starting at `start`, or returns nil if what is
    /// there only looks like one. Returning nil is the lenient outcome: the
    /// text is then emitted verbatim, so a subject that genuinely contains
    /// "=?" survives instead of eating the rest of the line.
    private static func scanWord2047(_ chars: [Character],
                                     from start: Int,
                                     terminator: [Int],
                                     lineBreak: [Int]) -> (token: Token2047, next: Int)? {
        var i = start + 2
        var charset = ""
        while i < chars.count, chars[i] != "?" {
            // An encoded word never spans a fold, so a line break means this is
            // not one.
            if chars[i] == "\n" || chars[i] == "\r" { return nil }
            charset.append(chars[i])
            i += 1
        }
        guard i < chars.count else { return nil }
        i += 1

        guard i < chars.count else { return nil }
        let wordEncoding = Character(String(chars[i]).lowercased())
        guard wordEncoding == "b" || wordEncoding == "q" else { return nil }
        i += 1
        guard i < chars.count, chars[i] == "?" else { return nil }
        i += 1

        // Same two refusals as the charset scan, read off the tables: no
        // closing "?=" at all, or a fold before it, means this is not a word.
        let end = terminator[i]
        guard end < chars.count, lineBreak[i] >= end else { return nil }
        let payload = String(chars[i..<end])
        i = end

        // The charset may carry an RFC 2231 language tag, as in "=?utf-8*en?Q?…?=".
        let name = charset.split(separator: "*", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? charset
        guard !name.isEmpty else { return nil }
        return (.word(charset: normalizedToken(name), encoding: wordEncoding, payload: payload), i + 2)
    }

    /// The Q form: like quoted-printable, except that '_' is a space. Forget
    /// that one rule and every encoded subject reads "Re:_your_appointment".
    private static func decodeQ(_ payload: String, charset: String) -> Data {
        let target = encoding(for: charset)
        let chars = Array(payload)
        var out = Data()
        var i = 0
        while i < chars.count {
            let char = chars[i]
            if char == "_" {
                out.append(0x20)
                i += 1
                continue
            }
            if char == "=", i + 2 < chars.count,
               let high = hexValue(asciiByte(chars[i + 1])), let low = hexValue(asciiByte(chars[i + 2])) {
                out.append((high << 4) | low)
                i += 3
                continue
            }
            // A raw byte the sender should have escaped. Re-encode it in the
            // word's own charset so the round trip through String is lossless.
            let piece = String(char)
            out.append(target.flatMap { piece.data(using: $0) } ?? Data(piece.utf8))
            i += 1
        }
        return out
    }

    private static func asciiByte(_ char: Character) -> UInt8 {
        guard let scalar = char.unicodeScalars.first, char.unicodeScalars.count == 1,
              scalar.value < 128 else { return 0xFF }
        return UInt8(scalar.value)
    }

    // MARK: - Headers

    /// Header name/value pairs, unfolded, in the order they appeared.
    ///
    /// Values come back *raw*: still RFC 2047 encoded, still carrying their
    /// parameters. Callers decide what to do with them, because "Subject" wants
    /// `decodeWord` and "Content-Type" does not.
    static func parseHeaders(_ data: Data) -> [(name: String, value: String)] {
        let bytes = [UInt8](data)
        let split = splitHeaderBody(bytes, 0..<bytes.count)
        return parseHeaderBlock(bytes, split.headers)
    }

    /// First matching header, compared without case as RFC 5322 requires.
    static func headerValue(_ name: String, in headers: [(name: String, value: String)]) -> String? {
        let wanted = name.lowercased()
        for header in headers where header.name.lowercased() == wanted {
            return header.value
        }
        return nil
    }

    private static func parseHeaderBlock(_ bytes: [UInt8], _ range: Range<Int>) -> [(name: String, value: String)] {
        var headers: [(name: String, value: String)] = []
        var current: (name: String, value: String)?

        for line in lineRanges(in: bytes, range) {
            let text = decodeBytes(bytes, line.content)
            if text.isEmpty { break }

            if let first = text.first, first == " " || first == "\t" {
                // Unfolding is "delete the CRLF", not "delete the CRLF and the
                // indent": RFC 2047 adjacency is defined in terms of the white
                // space that is left, so keeping it is what lets a subject
                // folded mid-word rejoin correctly.
                if var open = current {
                    open.value += text
                    current = open
                }
                continue
            }

            guard let colon = text.firstIndex(of: ":") else {
                // No colon and no indent: an mbox "From " line, or body text in
                // a message with no blank line before it. Neither is a header.
                continue
            }
            if let open = current { headers.append(open) }
            let name = String(text[text.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            current = name.isEmpty ? nil : (name, value)
        }
        if let open = current { headers.append(open) }
        return headers
    }

    /// Splits a message or a part at its first blank line.
    private static func splitHeaderBody(_ bytes: [UInt8], _ range: Range<Int>) -> (headers: Range<Int>, body: Range<Int>) {
        guard !range.isEmpty else { return (range, range) }

        // A body fragment handed to us with no header block at all — which is
        // what a broken part looks like — must not have its first line eaten as
        // a header.
        if !looksLikeHeaderStart(bytes, range) {
            return (range.lowerBound..<range.lowerBound, range)
        }

        var start = range.lowerBound
        var i = range.lowerBound
        while i < range.upperBound {
            if bytes[i] == 0x0A {
                var end = i
                if end > start, bytes[end - 1] == 0x0D { end -= 1 }
                if end == start {
                    return (range.lowerBound..<start, (i + 1)..<range.upperBound)
                }
                start = i + 1
            }
            i += 1
        }
        // Headers all the way to the end and no body: legal, if odd.
        return (range, range.upperBound..<range.upperBound)
    }

    private static func looksLikeHeaderStart(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        var i = range.lowerBound
        var nameLength = 0
        while i < range.upperBound {
            let byte = bytes[i]
            if byte == 0x0A || byte == 0x0D {
                // An empty first line means "no headers, body starts after it",
                // which the caller's scan already handles correctly.
                return nameLength == 0
            }
            if byte == 0x3A { return nameLength > 0 }               // ':'
            if byte <= 0x20 || byte >= 0x7F { return false }        // not a field name character
            nameLength += 1
            i += 1
        }
        return false
    }

    /// Lenient bytes-to-text for one header line. UTF-8 first because a raw
    /// (unencoded) 8-bit subject is nearly always UTF-8 these days, Latin-1
    /// after, because it cannot fail.
    private static func decodeBytes(_ bytes: [UInt8], _ range: Range<Int>) -> String {
        guard !range.isEmpty else { return "" }
        let data = Data(bytes[range])
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    // MARK: - Parameters

    /// Case-insensitive parameter lookup. Worth the loop: a `MIMEPart` built
    /// from an IMAP BODYSTRUCTURE carries the server's own casing ("CHARSET"),
    /// while one built here is lowercased.
    static func parameter(_ name: String, in parameters: [String: String]) -> String? {
        if let direct = parameters[name] { return direct }
        let wanted = name.lowercased()
        for (key, value) in parameters where key.lowercased() == wanted {
            return value
        }
        return nil
    }

    private static func parseParameters(_ text: String) -> [String: String] {
        var raw: [(key: String, value: String)] = []
        for segment in splitSemicolons(text) {
            guard let equals = segment.firstIndex(of: "=") else { continue }
            let key = String(segment[..<equals]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = unquote(String(segment[segment.index(after: equals)...])
                .trimmingCharacters(in: .whitespaces))
            if !key.isEmpty { raw.append((key, value)) }
        }
        return assembleParameters(raw)
    }

    /// Reassembles RFC 2231 split and extended parameters — `filename*0`,
    /// `filename*1`, `filename*=utf-8''…` — which is how every non-ASCII
    /// attachment name from a standards-following mailer arrives.
    private static func assembleParameters(_ raw: [(key: String, value: String)]) -> [String: String] {
        var simple: [String: String] = [:]
        var continued: [String: [(index: Int, value: String, extended: Bool)]] = [:]

        for item in raw {
            var key = item.key
            var extended = false
            if key.hasSuffix("*") {
                extended = true
                key.removeLast()
            }
            var index: Int?
            if let star = key.lastIndex(of: "*") {
                if let parsed = Int(String(key[key.index(after: star)...])) {
                    index = parsed
                    key = String(key[..<star])
                }
            }
            guard !key.isEmpty else { continue }

            if extended || index != nil {
                continued[key, default: []].append((index ?? 0, item.value, extended))
            } else if simple[key] == nil {
                simple[key] = item.value
            }
        }

        for (key, segments) in continued {
            let ordered = segments.sorted { $0.index < $1.index }
            let joined = ordered.map { $0.value }.joined()
            let isExtended = ordered.contains { $0.extended }
            // The extended form wins over a plain duplicate, per RFC 2231 §4.
            simple[key] = isExtended ? decodeExtendedParameter(joined) : joined
        }
        return simple
    }

    /// `utf-8''%E2%82%AC` → "€". A value with no charset prefix is treated as
    /// percent-encoded UTF-8, which is what the mailers that get this wrong do.
    private static func decodeExtendedParameter(_ text: String) -> String {
        var charset: String?
        var encoded = text
        let pieces = text.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
        if pieces.count == 3 {
            charset = String(pieces[0])
            encoded = String(pieces[2])
        }
        var bytes = Data()
        let chars = Array(encoded)
        var i = 0
        while i < chars.count {
            if chars[i] == "%", i + 2 < chars.count,
               let high = hexValue(asciiByte(chars[i + 1])), let low = hexValue(asciiByte(chars[i + 2])) {
                bytes.append((high << 4) | low)
                i += 3
                continue
            }
            bytes.append(Data(String(chars[i]).utf8))
            i += 1
        }
        return string(from: bytes, charset: charset)
    }

    /// Splits on ';' while respecting quoted strings, because a filename is
    /// allowed to contain a semicolon and splitting naively renames the file.
    private static func splitSemicolons(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        for char in text {
            if escaped {
                current.append(char)
                escaped = false
                continue
            }
            switch char {
            case "\\" where inQuotes:
                current.append(char)
                escaped = true
            case "\"":
                inQuotes.toggle()
                current.append(char)
            case ";" where !inQuotes:
                out.append(current)
                current = ""
            default:
                current.append(char)
            }
        }
        out.append(current)
        return out.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else {
            return text.trimmingCharacters(in: .whitespaces)
        }
        let inner = text.dropFirst().dropLast()
        var out = ""
        var escaped = false
        for char in inner {
            if escaped {
                out.append(char)
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else {
                out.append(char)
            }
        }
        return out
    }

    private static func normalizedToken(_ text: String) -> String {
        var token = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let semicolon = token.firstIndex(of: ";") { token = String(token[..<semicolon]) }
        return token.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t"))
    }

    // MARK: - Structure

    /// Parses raw RFC 822 bytes into a MIME tree with IMAP section paths.
    ///
    /// Use `parse(_:)` instead when you also need the bytes: this throws the
    /// part bodies away, and `flatten` cannot invent them.
    static func parseStructure(_ raw: Data) -> MIMEPart {
        parse(raw).structure
    }

    /// The tree plus every leaf's raw (still transfer-encoded) bytes, keyed by
    /// section path — exactly the shape `flatten(_:bodyFor:)` wants, so a
    /// message fetched whole decodes with
    /// `let (tree, bodies) = parse(raw); flatten(tree) { bodies[$0.section] }`.
    static func parse(_ raw: Data) -> (structure: MIMEPart, bodies: [String: Data]) {
        let bytes = [UInt8](raw)
        var bodies: [String: Data] = [:]
        // A multipart root owns no section of its own: IMAP calls the whole
        // message BODY[] and numbers the children 1, 2, 3. A single-part
        // message is the other way round — its one body is BODY[1].
        let rootSection = peekIsMultipart(bytes, 0..<bytes.count) ? "" : "1"
        let structure = parseNode(bytes, 0..<bytes.count, section: rootSection, depth: 0, bodies: &bodies)
        return (structure, bodies)
    }

    /// Everything `parse` does, in one call, for the common case of holding the
    /// whole message already.
    static func decodeMessage(_ raw: Data) -> DecodedBody {
        let parsed = parse(raw)
        return flatten(parsed.structure) { parsed.bodies[$0.section] }
    }

    private static func peekIsMultipart(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        let split = splitHeaderBody(bytes, range)
        let headers = parseHeaderBlock(bytes, split.headers)
        let content = parseContentType(headerValue("content-type", in: headers) ?? "")
        guard content.type == "multipart" else { return false }
        guard let boundary = parameter("boundary", in: content.parameters), !boundary.isEmpty else {
            // No boundary means we cannot walk it and will show it as text, so
            // for numbering purposes it is a single part.
            return false
        }
        return true
    }

    private static func parseNode(_ bytes: [UInt8],
                                  _ range: Range<Int>,
                                  section: String,
                                  depth: Int,
                                  bodies: inout [String: Data]) -> MIMEPart {
        let split = splitHeaderBody(bytes, range)
        let headers = parseHeaderBlock(bytes, split.headers)
        let bodyRange = split.body
        var part = makePart(headers: headers, section: section)
        part.size = bodyRange.count
        if part.type == "text" { part.lines = countLines(bytes, bodyRange) }

        if part.isMultipart {
            let boundary = parameter("boundary", in: part.parameters) ?? ""
            let chunks = depth < maxDepth && !boundary.isEmpty
                ? splitParts(bytes, bodyRange, boundary: boundary)
                : []
            if chunks.isEmpty {
                // Declared multipart, but there is nothing to walk: no boundary
                // parameter, a boundary that never appears, or nesting past the
                // cap. Showing the raw body as text is ugly; showing an empty
                // message because we refused to guess is worse.
                return demote(part, bytes: bytes, bodyRange: bodyRange, bodies: &bodies)
            }
            let prefix = section.isEmpty ? "" : section + "."
            var children: [MIMEPart] = []
            for (offset, chunk) in Array(chunks.prefix(maxPartsPerMultipart)).enumerated() {
                children.append(parseNode(bytes, chunk,
                                          section: prefix + String(offset + 1),
                                          depth: depth + 1,
                                          bodies: &bodies))
            }
            part.children = children
            return part
        }

        bodies[section] = Data(bytes[bodyRange])

        if part.type == "message", part.subtype == "rfc822",
           depth < maxDepth, !bodyRange.isEmpty {
            // An encapsulated message restarts the numbering inside itself: if
            // part 2 is a message/rfc822 whose body is multipart, its children
            // are 2.1 and 2.2; if that body is a single part, the body is 2.1.
            let innerSection = peekIsMultipart(bytes, bodyRange) ? section : section + ".1"
            let inner = parseNode(bytes, bodyRange, section: innerSection, depth: depth + 1, bodies: &bodies)
            part.children = [inner]
        }
        return part
    }

    private static func demote(_ part: MIMEPart,
                               bytes: [UInt8],
                               bodyRange: Range<Int>,
                               bodies: inout [String: Data]) -> MIMEPart {
        var leaf = part
        leaf.type = "text"
        leaf.subtype = "plain"
        leaf.children = []
        // The root of a single-part message is section 1, and after this
        // demotion that is what it has become.
        if leaf.section.isEmpty { leaf.section = "1" }
        bodies[leaf.section] = Data(bytes[bodyRange])
        return leaf
    }

    private static func makePart(headers: [(name: String, value: String)], section: String) -> MIMEPart {
        var part = MIMEPart()
        part.section = section

        let content = parseContentType(headerValue("content-type", in: headers) ?? "")
        part.type = content.type
        part.subtype = content.subtype
        part.parameters = content.parameters

        let transfer = normalizedToken(headerValue("content-transfer-encoding", in: headers) ?? "")
        part.encoding = transfer.isEmpty ? "7bit" : transfer

        part.id = headerValue("content-id", in: headers)?.trimmingCharacters(in: .whitespaces)
        if let description = headerValue("content-description", in: headers) {
            part.description = decodeWord(description)
        }

        if let disposition = headerValue("content-disposition", in: headers) {
            let value = normalizedToken(disposition)
            part.disposition = value.isEmpty ? nil : value
            if let semicolon = disposition.firstIndex(of: ";") {
                part.dispositionParameters = parseParameters(String(disposition[disposition.index(after: semicolon)...]))
            }
        }
        return part
    }

    /// A missing or unparseable Content-Type is text/plain, which is what RFC
    /// 2045 says to assume and also the only assumption that shows the reader
    /// anything.
    private static func parseContentType(_ value: String) -> (type: String, subtype: String, parameters: [String: String]) {
        var media = value
        var parameters: [String: String] = [:]
        if let semicolon = value.firstIndex(of: ";") {
            media = String(value[..<semicolon])
            parameters = parseParameters(String(value[value.index(after: semicolon)...]))
        }
        let cleaned = media.trimmingCharacters(in: CharacterSet(charactersIn: "\" \t\r\n")).lowercased()
        guard !cleaned.isEmpty else { return ("text", "plain", parameters) }

        let pieces = cleaned.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let type = String(pieces[0]).trimmingCharacters(in: .whitespaces)
        guard !type.isEmpty else { return ("text", "plain", parameters) }
        if pieces.count < 2 {
            return (type, type == "text" ? "plain" : "octet-stream", parameters)
        }
        let subtype = String(pieces[1]).trimmingCharacters(in: .whitespaces)
        return (type, subtype.isEmpty ? "plain" : subtype, parameters)
    }

    private static func countLines(_ bytes: [UInt8], _ range: Range<Int>) -> Int {
        guard !range.isEmpty else { return 0 }
        var count = 0
        for i in range where bytes[i] == 0x0A { count += 1 }
        if bytes[range.upperBound - 1] != 0x0A { count += 1 }
        return count
    }

    // MARK: - Multipart boundaries

    private static func splitParts(_ bytes: [UInt8], _ range: Range<Int>, boundary: String) -> [Range<Int>] {
        let marker = [UInt8]("--\(boundary)".utf8)
        guard marker.count > 2, !range.isEmpty else { return [] }

        var chunks: [Range<Int>] = []
        var openStart: Int?

        for line in lineRanges(in: bytes, range) {
            let match = matchBoundary(bytes, line.content, marker)
            guard match.isDelimiter else { continue }
            if let start = openStart {
                // The CRLF in front of a delimiter belongs to the delimiter, not
                // to the part; keeping it would add a blank line to every part.
                chunks.append(trimTrailingBreak(bytes, start..<line.content.lowerBound))
            }
            if match.isClosing { return chunks }        // the epilogue is not a part
            openStart = line.next
            if chunks.count >= maxPartsPerMultipart { return chunks }
        }

        // No closing delimiter ever arrived — a truncated or hand-built message.
        // Everything after the last opening delimiter is still a part worth
        // showing.
        if let start = openStart, start < range.upperBound {
            chunks.append(trimTrailingBreak(bytes, start..<range.upperBound))
        }
        return chunks
    }

    private static func matchBoundary(_ bytes: [UInt8], _ content: Range<Int>, _ marker: [UInt8]) -> (isDelimiter: Bool, isClosing: Bool) {
        guard content.count >= marker.count else { return (false, false) }
        for offset in 0..<marker.count where bytes[content.lowerBound + offset] != marker[offset] {
            return (false, false)
        }
        var i = content.lowerBound + marker.count
        var closing = false
        if i + 1 < content.upperBound, bytes[i] == 0x2D, bytes[i + 1] == 0x2D {
            closing = true
            i += 2
        }
        // Trailing white space on a delimiter line is legal, and some mailers
        // pad it. Anything else after the boundary means this line is body text
        // that merely starts the same way.
        while i < content.upperBound, bytes[i] == 0x20 || bytes[i] == 0x09 { i += 1 }
        return (i == content.upperBound, closing)
    }

    private static func trimTrailingBreak(_ bytes: [UInt8], _ range: Range<Int>) -> Range<Int> {
        var end = range.upperBound
        if end > range.lowerBound, bytes[end - 1] == 0x0A {
            end -= 1
            if end > range.lowerBound, bytes[end - 1] == 0x0D { end -= 1 }
        }
        return range.lowerBound..<end
    }

    private static func lineRanges(in bytes: [UInt8], _ range: Range<Int>) -> [(content: Range<Int>, next: Int)] {
        var result: [(content: Range<Int>, next: Int)] = []
        var start = range.lowerBound
        var i = range.lowerBound
        while i < range.upperBound {
            if bytes[i] == 0x0A {
                var end = i
                if end > start, bytes[end - 1] == 0x0D { end -= 1 }
                result.append((start..<end, i + 1))
                start = i + 1
            }
            i += 1
        }
        if start < range.upperBound {
            var end = range.upperBound
            if end > start, bytes[end - 1] == 0x0D { end -= 1 }
            result.append((start..<end, range.upperBound))
        }
        return result
    }

    // MARK: - Flattening

    /// Turns a tree into the two bodies and the attachment list the UI asks
    /// for. `bodyFor` supplies the raw, still transfer-encoded bytes of a leaf;
    /// returning nil for a part simply means that body stays nil, which is how
    /// the repository can flatten a BODYSTRUCTURE it has not downloaded yet.
    static func flatten(_ part: MIMEPart, bodyFor: (MIMEPart) -> Data?) -> DecodedBody {
        var body = DecodedBody(text: nil, html: nil, attachments: [])
        let chosen = chooseBodies(part, depth: 0)

        if let textPart = chosen.text, let data = bodyFor(textPart) {
            body.text = decodeText(data,
                                   encoding: textPart.encoding,
                                   charset: parameter("charset", in: textPart.parameters))
        }
        if let htmlPart = chosen.html, let data = bodyFor(htmlPart) {
            body.html = decodeText(data,
                                   encoding: htmlPart.encoding,
                                   charset: parameter("charset", in: htmlPart.parameters))
        }

        var skip = Set<String>()
        if let textPart = chosen.text { skip.insert(textPart.section) }
        if let htmlPart = chosen.html { skip.insert(htmlPart.section) }

        var attachments: [Attachment] = []
        collectAttachments(part, skipping: skip, depth: 0, into: &attachments)
        body.attachments = attachments
        return body
    }

    /// The files a letter carries, as the reading pane's header lists them,
    /// from its structure alone: what `flatten` finds with no bodies to
    /// hand, less the pictures the body shows by `cid:`. Worked out from the
    /// BODYSTRUCTURE a list row is fetched with, so the header can list the
    /// files before the letter is downloaded, the same ones it will list
    /// once it has been: the downloaded letter goes through `flatten` too,
    /// and IMAP numbers the parts as `parse` does.
    static func listedAttachments(in structure: MIMEPart) -> [Attachment] {
        flatten(structure) { _ in nil }.attachments.filter { !$0.isInline }
    }

    /// Finds a part by its IMAP section path ("2", "1.3").
    ///
    /// The counterpart to `parse`'s `bodies` dictionary: that gives the
    /// bytes, this gives the part they belong to — and the part is what
    /// carries the transfer encoding needed to turn those bytes back into a
    /// file.
    static func part(at section: String, in root: MIMEPart) -> MIMEPart? {
        if root.section == section { return root }
        for child in root.children {
            if let found = part(at: section, in: child) { return found }
        }
        return nil
    }

    /// The single part a list-row preview should be built from.
    ///
    /// Plain text wins whenever the sender provided it, and not only because
    /// it needs no stripping: the plain alternative of an HTML mail is a
    /// fraction of its size, so preferring it is what keeps a page of previews
    /// to a few kilobytes instead of a few hundred.
    ///
    /// Takes a BODYSTRUCTURE rather than a downloaded message on purpose —
    /// the caller has the structure already and uses this to decide which
    /// single section is worth fetching.
    static func previewPart(_ structure: MIMEPart) -> MIMEPart? {
        let chosen = chooseBodies(structure, depth: 0)
        return chosen.text ?? chosen.html
    }

    /// The walk stops one level *deeper* than the parser does, because the
    /// parser's last act at the cap is to salvage the remaining bytes as a text
    /// leaf; refusing to look at that leaf would throw away the one thing it
    /// went to the trouble of rescuing.
    private static func chooseBodies(_ part: MIMEPart, depth: Int) -> (text: MIMEPart?, html: MIMEPart?) {
        guard depth <= maxDepth else { return (nil, nil) }

        if !part.isMultipart {
            if part.type == "message", part.subtype == "rfc822", !part.isAttachment,
               let inner = part.children.first {
                return chooseBodies(inner, depth: depth + 1)
            }
            // A part the sender marked as an attachment is a file, however
            // text-like it is: a 4 MB log.txt must not become the message body.
            guard part.type == "text", part.disposition != "attachment" else { return (nil, nil) }
            if part.subtype == "html" { return (nil, part) }
            // Anything else under text/* (plain, enriched, calendar) reads as
            // the text body. Showing an invite's raw ICS beats showing nothing.
            return (part, nil)
        }

        // RFC 2046: the alternatives are ordered worst to best, so the last one
        // that we understand wins. Every other multipart (mixed, related,
        // signed, report) is a sequence, where the first body found is the
        // message and anything later is an enclosure or a signature.
        let preferLast = part.subtype == "alternative"
        var text: MIMEPart?
        var html: MIMEPart?
        for child in part.children {
            let found = chooseBodies(child, depth: depth + 1)
            if let candidate = found.text, preferLast || text == nil { text = candidate }
            if let candidate = found.html, preferLast || html == nil { html = candidate }
        }
        return (text, html)
    }

    private static func collectAttachments(_ part: MIMEPart,
                                           skipping: Set<String>,
                                           depth: Int,
                                           into list: inout [Attachment]) {
        guard depth <= maxDepth else { return }

        if part.isMultipart {
            for child in part.children {
                collectAttachments(child, skipping: skipping, depth: depth + 1, into: &list)
            }
            return
        }
        if part.type == "message", part.subtype == "rfc822", !part.isAttachment {
            for child in part.children {
                collectAttachments(child, skipping: skipping, depth: depth + 1, into: &list)
            }
            return
        }
        if skipping.contains(part.section) { return }

        let named = decodedFilename(part)
        // A text part with no name and no attachment disposition is the
        // alternative we did not pick, not a file. Listing it would put a
        // phantom "part-1.txt" under every message with both plain and HTML.
        if part.type == "text", named == nil, part.disposition != "attachment" { return }

        list.append(Attachment(id: part.section,
                               filename: named ?? fallbackFilename(part),
                               mimeType: part.mimeType,
                               size: estimatedSize(part),
                               contentID: strippedContentID(part.id),
                               isInline: part.disposition == "inline"))
    }

    /// A `Content-ID` as the body will refer to it.
    ///
    /// The header carries it in angle brackets — `<ii_1a0b5a437217d709>` —
    /// and the body writes `src="cid:ii_1a0b5a437217d709"` without them, so
    /// one side has to agree with the other or nothing ever matches. Also
    /// drops a `cid:` prefix, which a few senders put in the header itself.
    static func strippedContentID(_ raw: String?) -> String? {
        guard var id = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty else { return nil }
        if id.hasPrefix("<") { id.removeFirst() }
        if id.hasSuffix(">") { id.removeLast() }
        if id.lowercased().hasPrefix("cid:") { id = String(id.dropFirst(4)) }
        id = id.trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? nil : id
    }

    /// The name as the sender meant it: RFC 2047 decoded (mailers put encoded
    /// words in `filename=` even though the RFC says to use RFC 2231 instead),
    /// stripped of any path, and of control characters that would make a mess
    /// of a share sheet.
    private static func decodedFilename(_ part: MIMEPart) -> String? {
        let raw = parameter("filename", in: part.dispositionParameters)
            ?? parameter("name", in: part.parameters)
        guard let raw, !raw.isEmpty else { return nil }

        var name = decodeWord(raw)
        if let slash = name.lastIndex(where: { $0 == "/" || $0 == "\\" }) {
            name = String(name[name.index(after: slash)...])
        }
        name = String(name.filter { character in
            guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
                return true
            }
            return scalar.value >= 0x20 && scalar.value != 0x7F
        }).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private static func fallbackFilename(_ part: MIMEPart) -> String {
        let stem = "attachment-" + part.section.replacingOccurrences(of: ".", with: "-")
        return stem + "." + fileExtension(for: part)
    }

    private static func fileExtension(for part: MIMEPart) -> String {
        switch part.mimeType {
        case "text/plain":               return "txt"
        case "text/html":                return "html"
        case "text/calendar":            return "ics"
        case "image/jpeg":               return "jpg"
        case "image/png":                return "png"
        case "image/gif":                return "gif"
        case "image/heic":               return "heic"
        case "application/pdf":          return "pdf"
        case "application/zip":          return "zip"
        case "application/msword":       return "doc"
        case "message/rfc822":           return "eml"
        default:
            let cleaned = part.subtype.filter { $0.isLetter || $0.isNumber }
            return cleaned.isEmpty || cleaned.count > 8 ? "dat" : cleaned
        }
    }

    /// The size a user would recognise, so base64 is scaled back to what the
    /// file will actually weigh once saved. `nil` when the structure did not
    /// carry a size at all, which the UI already has to handle.
    private static func estimatedSize(_ part: MIMEPart) -> Int64? {
        guard let size = part.size else { return nil }
        if part.encoding == "base64" { return Int64(size) / 4 * 3 }
        return Int64(size)
    }
}
