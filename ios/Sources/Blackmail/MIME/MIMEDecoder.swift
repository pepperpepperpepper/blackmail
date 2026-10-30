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

    /// And on the files listed for one letter, wherever its parts are:
    /// five hundred to a multipart, nested, is a quarter of a million, each
    /// a row in the reading pane's header and on the page kept on the iPad
    /// (D-016), where a stranger's letter is read back at every launch.
    static let maxAttachments = 500

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
    ///
    /// The output is a plain array and the input is read through a raw
    /// buffer, for the reason `decodeQuotedPrintable` below gives. `Data` has
    /// no `append` for one byte: each one went through the generic
    /// `replaceSubrange`, an opaque call into Foundation per output byte, and
    /// reading `Data` byte by byte costs a call each too. A 5 MB attachment
    /// took about 625 ms to open, and a letter with a few inline pictures
    /// spent most of its decode here.
    private static func decodeBase64(_ data: Data) -> Data {
        var out: [UInt8] = []
        out.reserveCapacity(data.count * 3 / 4 + 3)
        var accumulator: UInt32 = 0
        var bits = 0
        data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            for byte in input {
                let value: UInt32
                switch byte {
                case 0x41...0x5A: value = UInt32(byte - 0x41)          // A-Z
                case 0x61...0x7A: value = UInt32(byte - 0x61) + 26     // a-z
                case 0x30...0x39: value = UInt32(byte - 0x30) + 52     // 0-9
                case 0x2B, 0x2D:  value = 62                           // '+', and base64url '-'
                case 0x2F, 0x5F:  value = 63                           // '/', and base64url '_'
                case 0x3D:
                    // '=' ends a quantum. Resetting rather than ignoring is
                    // what makes a message whose body is several separately
                    // padded base64 blocks glued together decode correctly
                    // instead of sliding six bits out of alignment at the join.
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
        }
        return Data(out)
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

    /// Every CRLF and every lone CR made a LF, in one pass over the UTF-8.
    ///
    /// It was two of Foundation's replacements, CRLF and then CR, which on
    /// this host took a second for every two megabytes of line breaks, and
    /// half a gigabyte for 25 MB of them. The one difference is where a
    /// combining mark follows a line break, which no mail writes: those
    /// replacements took the mark as part of the break's character and
    /// left the pair alone, or made it two breaks.
    private static func normalizeNewlines(_ text: String) -> String {
        guard text.utf8.contains(0x0D) else { return text }
        var out: [UInt8] = []
        out.reserveCapacity(text.utf8.count)
        var afterCR = false
        for byte in text.utf8 {
            if byte == 0x0A, afterCR {
                afterCR = false
                continue
            }
            afterCR = byte == 0x0D
            out.append(afterCR ? 0x0A : byte)
        }
        return String(decoding: out, as: UTF8.self)
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
    ///
    /// Only the header block is copied out of `data` to be read: a whole
    /// letter used to be, a second copy of however many megabytes it was,
    /// for the few kilobytes of it that are its header.
    static func parseHeaders(_ data: Data) -> [(name: String, value: String)] {
        let bytes = [UInt8](data.prefix(headerBlockLength(of: data)))
        let split = splitHeaderBody(bytes, 0..<bytes.count)
        return parseHeaderBlock(bytes, split.headers)
    }

    /// How much of `data` `splitHeaderBody` reads for its header: through
    /// the line break that ends the first blank line, or all of it when
    /// there is none. Read in place.
    private static func headerBlockLength(of data: Data) -> Int {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            var start = 0
            for i in 0..<raw.count where raw[i] == 0x0A {
                var end = i
                if end > start, raw[end - 1] == 0x0D { end -= 1 }
                if end == start { return i + 1 }
                start = i + 1
            }
            return raw.count
        }
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

        for line in Lines(bytes, range) {
            let text = decodeBytes(bytes, line.content)
            if text.isEmpty { break }

            if let first = text.first, first == " " || first == "\t" {
                // Unfolding is "delete the CRLF", not "delete the CRLF and the
                // indent": RFC 2047 adjacency is defined in terms of the white
                // space that is left, so keeping it is what lets a subject
                // folded mid-word rejoin correctly.
                //
                // Appended in place. Copied out, added to and put back, the
                // value was copied whole for every line folded onto it: a
                // header folded onto twenty thousand lines, 2 MB, took 4.7 s
                // in the suite's debug build.
                current?.value += text
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
        let structure = parseNode(bytes, 0..<bytes.count, section: rootSection, depth: 0,
                                  undone: false, bodies: &bodies)
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

    /// `undone` is true inside a forwarded letter whose transfer encoding
    /// has been undone to read it, below.
    private static func parseNode(_ bytes: [UInt8],
                                  _ range: Range<Int>,
                                  section: String,
                                  depth: Int,
                                  undone: Bool,
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
                                          undone: undone,
                                          bodies: &bodies))
            }
            part.children = children
            return part
        }

        let whole = Data(bytes[bodyRange])
        bodies[section] = whole

        if part.type == "message", part.subtype == "rfc822",
           depth < maxDepth, !bodyRange.isEmpty {
            // An encapsulated message restarts the numbering inside itself: if
            // part 2 is a message/rfc822 whose body is multipart, its children
            // are 2.1 and 2.2; if that body is a single part, the body is 2.1.
            //
            // One sent base64 or quoted-printable, against RFC 2046 but sent
            // all the same, is read with its encoding undone: read as it
            // came, its encoded lines were drawn as the forwarded letter's
            // words (B-114). Undone once on the way down, so the copy is the
            // letter's size at most: one encoded inside one undone is read
            // as it came. Its own bytes stay as they came, for a tap on its
            // row when it is a file, which undoes the encoding as for any.
            var inner: MIMEPart
            if !undone, part.encoding == "base64" || part.encoding == "quoted-printable" {
                let plain = [UInt8](decodeTransfer(whole, encoding: part.encoding))
                let all = 0..<plain.count
                let innerSection = peekIsMultipart(plain, all) ? section : section + ".1"
                inner = parseNode(plain, all, section: innerSection, depth: depth + 1, undone: true,
                                  bodies: &bodies)
            } else {
                let innerSection = peekIsMultipart(bytes, bodyRange) ? section : section + ".1"
                inner = parseNode(bytes, bodyRange, section: innerSection, depth: depth + 1,
                                  undone: undone, bodies: &bodies)
            }
            // A multipart inside that was read as one part of words, its
            // boundary never there or the nesting at the cap (`demote`), is
            // numbered as one part is, 2.1. Under the letter's own 2 its
            // words took the place of the letter's bytes, which the
            // forwarded letter's header lines are read from
            // (`forwardedFields`), and which a tap on its row opens (B-114).
            if inner.section == section, !inner.isMultipart {
                inner.section = section + ".1"
                bodies[inner.section] = bodies[section]
                bodies[section] = whole
            }
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

        for line in Lines(bytes, range) {
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

    /// The lines of `range`, each without its line break and with where
    /// the next begins, found as they are asked for.
    ///
    /// It used to be a list of every line made first. At 24 bytes a line
    /// that was twenty-four times the size of a part of bare line breaks:
    /// a letter of 35 MB of them came to 1.66 GB, which is the app killed
    /// for its memory the moment he opened it.
    private struct Lines: Sequence, IteratorProtocol {
        let bytes: [UInt8]
        var start: Int
        let end: Int

        init(_ bytes: [UInt8], _ range: Range<Int>) {
            self.bytes = bytes
            start = range.lowerBound
            end = range.upperBound
        }

        mutating func next() -> (content: Range<Int>, next: Int)? {
            guard start < end else { return nil }
            var i = start
            while i < end, bytes[i] != 0x0A { i += 1 }
            let next = i < end ? i + 1 : end
            var stop = i
            if stop > start, bytes[stop - 1] == 0x0D { stop -= 1 }
            defer { start = next }
            return (start..<stop, next)
        }
    }

    // MARK: - Flattening

    /// Turns a tree into the two bodies and the attachment list the UI asks
    /// for. `bodyFor` supplies the raw, still transfer-encoded bytes of a leaf;
    /// returning nil for a part simply means that body stays nil, which is how
    /// the repository can flatten a BODYSTRUCTURE it has not downloaded yet.
    ///
    /// Each body is every part that makes it, in order (`bodyPlan(of:)`),
    /// joined (`joined`): a body of one part, as nearly every letter's is,
    /// is that part's words exactly as they came. It was one part each,
    /// the first a mixed held, until B-113 and B-114: the words after a
    /// file Mail puts among them, and a letter forwarded inline after a
    /// note, were nowhere.
    static func flatten(_ part: MIMEPart, bodyFor: (MIMEPart) -> Data?) -> DecodedBody {
        let plan = bodyPlan(of: part)
        func words(_ piece: MIMEPart) -> (text: String, cut: Bool)? {
            bodyFor(piece).map {
                (decodeText($0, encoding: piece.encoding,
                            charset: parameter("charset", in: piece.parameters)), false)
            }
        }
        // A forwarded letter sent base64 or quoted-printable, against RFC
        // 2046, has its header under the encoding too (`parseNode`).
        func fields(_ letter: MIMEPart) -> ForwardedFields? {
            forwardedFields(of: letter,
                            header: bodyFor(letter).map { decodeTransfer($0, encoding: letter.encoding) })
        }
        // Where each plain part begins, for the paper alone (B-185).
        var textParts: [Message.TextPart] = []
        var body = DecodedBody(text: joined(plan.text, asHTML: false, goesOn: plan.textGoesOn,
                                            words: words, fields: fields,
                                            partStarts: { textParts.append(.init(section: $0, start: $1)) }),
                               html: joined(plan.html, asHTML: true, goesOn: plan.htmlGoesOn,
                                            words: words, fields: fields),
                               attachments: [])
        // By the body the pane shows, the HTML whenever there is any.
        body.isShortened = body.html != nil ? plan.htmlGoesOn : plan.textGoesOn
        body.textIsFlowed = plan.textIsFlowed
        if body.text != nil, textParts.count > 1 { body.textParts = textParts }
        var attachments: [Attachment] = []
        collectAttachments(part, skipping: plan.sections, depth: 0, into: &attachments)
        body.attachments = attachments
        return body
    }

    /// The files a letter carries, as the reading pane draws them in its
    /// body (`BodyFiles`), from its structure alone: what `flatten` finds
    /// with no bodies to hand, less the pictures the body shows by `cid:`
    /// (`Attachment.isShownInBody`, the rule `Message.listedAttachments`
    /// keeps too). Worked out from the BODYSTRUCTURE a list row is fetched
    /// with, the same files the letter lists once it has been downloaded:
    /// the downloaded letter goes through `flatten` too, and IMAP numbers
    /// the parts as `parse` does.
    static func listedAttachments(in structure: MIMEPart) -> [Attachment] {
        flatten(structure) { _ in nil }.attachments.filter { !$0.isShownInBody }
    }

    /// The names of the files `structure` carries that have one, in the
    /// order `flatten` finds them, the pictures the body shows by `cid:`
    /// among them, which `listedAttachments(in:)` leaves out: what a list
    /// row of a letter with no words names, as Mail's does (`RowPreview`,
    /// B-182), every one since Mail's row of two files was seen. Empty for
    /// a letter with no file named.
    static func fileNames(in structure: MIMEPart) -> [String] {
        flatten(structure) { _ in nil }.attachments.map(\.filename).filter { !$0.isEmpty }
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

    /// The single part a list-row preview should be built from: the first
    /// of the plain words (`bodyPlan(of:)`), which is where the letter
    /// begins. Walked only as far as that part (`Walk`).
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
        var walk = Walk(words: 1)
        walk.walk(structure, .text, depth: 0)
        return walk.text.pieces.lazy.compactMap(\.words).first
    }

    // MARK: - The body, part by part

    /// The parts of words one body holds, at most (B-113). Every part is
    /// drawn in its turn, as Mail draws them, and a stranger can send a
    /// quarter of a million tiny ones: a letter too large to fetch whole
    /// made a FETCH for each, and every letter held a copy of each part
    /// for each body. Mail on an iPad splits a letter's HTML into one part
    /// more than the files put among its words, so 64 parts is a letter
    /// with 63 files among them. A body with more is drawn to the last part
    /// it holds and nothing after it, and the pane says it is only the
    /// beginning (`DecodedBody.isShortened`, `Message.isShortened`), as it
    /// says of a letter its fetch cut short.
    static let maxBodyWords = 64

    /// And the pieces of a body of every kind, the files among its words
    /// and the forwarded letters' header lines with them: four times as
    /// many. Each piece is a copy of its part, so a body holds no more
    /// than these, whatever the letter has.
    static let maxBodyPieces = 4 * maxBodyWords

    /// One thing a letter shows as its body, in the order it is drawn.
    enum BodyPiece {
        /// A text part read as words: text/html as markup, any other text
        /// as text.
        case words(MIMEPart)
        /// A file among the words. Drawn in an HTML letter where it sits,
        /// with words after it, as the tile or the picture the pane makes
        /// of its mark (`BodyFiles`); nothing in the plain words, where the
        /// pane draws it after them.
        case file(MIMEPart)
        /// A letter forwarded inline as message/rfc822, the part itself:
        /// the header lines drawn above its words, in Mail's form, when
        /// there are words outside it (`ForwardedFields`).
        case forwarded(MIMEPart)

        /// The part, for words.
        var words: MIMEPart? {
            if case .words(let part) = self { return part }
            return nil
        }
    }

    /// What a letter shows as its body, from its structure alone: the parts
    /// its HTML is made of, and those its plain words are, each in order.
    /// The pane draws the HTML when there is any (`PanePage`); a reply
    /// quotes the plain words, or the HTML's text when there are none
    /// (`Message.quotableText`).
    struct BodyPlan {
        var html: [BodyPiece] = []
        var text: [BodyPiece] = []
        /// Whether the HTML, and the plain words, go on past the pieces
        /// here: more parts of words than a body holds (`maxBodyWords`).
        /// Each is drawn to its last piece and no further (`joined`).
        var htmlGoesOn = false
        var textGoesOn = false

        /// Every part either body shows as words: what the pane draws no
        /// file for (`collectAttachments`), and a paperclip leaves out
        /// (`IMAPMailRepository.hasAttachment`), and what a letter too large
        /// to fetch whole fetches of itself (`Allowance`).
        var sections: Set<String> {
            Set((html + text).compactMap { $0.words?.section })
        }

        /// Whether the plain words are flowed text (RFC 3676): every part
        /// of them text/plain with `format=flowed`, as Apple Mail and
        /// Thunderbird send plain text, and at least one. How deep a line's
        /// quote is depends on it (`PlainQuotes`, B-147). Nothing else
        /// reads it: the lines are drawn as they came.
        var textIsFlowed: Bool {
            let parts = text.compactMap(\.words)
            return !parts.isEmpty && parts.allSatisfy { part in
                part.type == "text" && part.subtype == "plain"
                    && MIMEDecoder.parameter("format", in: part.parameters)?.lowercased() == "flowed"
            }
        }
    }

    static func bodyPlan(of structure: MIMEPart) -> BodyPlan {
        var walk = Walk(words: maxBodyWords)
        walk.walk(structure, [.html, .text], depth: 0)
        return BodyPlan(html: walk.html.pieces, text: walk.text.pieces,
                        htmlGoesOn: walk.html.goesOn, textGoesOn: walk.text.goesOn)
    }

    /// One body's pieces, in the order they are drawn, and no more than it
    /// holds (`maxBodyWords`, `maxBodyPieces`).
    private struct Body {
        private(set) var pieces: [BodyPiece] = []
        /// More parts of words came after the last one here.
        private(set) var goesOn = false
        private var words = 0
        let most: Int

        init(most: Int) { self.most = most }

        /// `piece`, unless the body holds no more, which a part of words
        /// past the last it holds, or any piece past the last of all, says.
        mutating func put(_ piece: BodyPiece) {
            guard !goesOn else { return }
            guard pieces.count < MIMEDecoder.maxBodyPieces else {
                goesOn = true
                return
            }
            if piece.words != nil {
                guard words < most else {
                    goesOn = true
                    return
                }
                words += 1
            }
            pieces.append(piece)
        }
    }

    /// The two bodies of a letter, walked from its structure in one pass,
    /// each into one list in the order it is drawn, and only as far as it
    /// holds.
    ///
    /// It was a list for each part, both bodies, made of copies of its
    /// children's and copied again into its parent's: for a letter of
    /// 250,000 tiny parts, 2.6 s and 300 MB more than the letter itself in
    /// a release build, against 0.19 s and nothing before every part was
    /// drawn (B-113). Now a choice that needs to know what a part holds,
    /// an alternative's or a related's, asks it (`Holds`), which makes
    /// nothing, and only the parts a body draws are walked, until it holds
    /// no more (`BoundedLetterTests`).
    ///
    /// The walk stops one level *deeper* than the parser does, because the
    /// parser's last act at the cap is to salvage the remaining bytes as a
    /// text leaf; refusing to look at that leaf would throw away the one
    /// thing it went to the trouble of rescuing.
    private struct Walk {
        var html: Body
        var text: Body

        init(words most: Int) {
            html = Body(most: most)
            text = Body(most: most)
        }

        /// Which body a part is walked for, and how: the HTML; the plain
        /// words; or the plain words of an alternative with none, which are
        /// its HTML's, walked as the HTML is.
        struct Into: OptionSet {
            let rawValue: UInt8
            static let html = Into(rawValue: 1)
            static let text = Into(rawValue: 2)
            static let textAsHTML = Into(rawValue: 4)
            static let anyText: Into = [.text, .textAsHTML]
        }

        private mutating func put(_ piece: BodyPiece, _ into: Into) {
            if into.contains(.html) { html.put(piece) }
            if !into.isDisjoint(with: .anyText) { text.put(piece) }
        }

        /// `into`, less a body that holds no more.
        private func live(_ into: Into) -> Into {
            var live = into
            if html.goesOn { live.remove(.html) }
            if text.goesOn { live.subtract(.anyText) }
            return live
        }

        mutating func walk(_ part: MIMEPart, _ asked: Into, depth: Int) {
            let into = live(asked)
            guard depth <= MIMEDecoder.maxDepth, !into.isEmpty else { return }

            if !part.isMultipart {
                if part.type == "message", part.subtype == "rfc822", !part.isAttachment {
                    // A letter forwarded inline: its own body, by the rules
                    // any letter's goes by, under its header lines.
                    guard let inner = part.children.first else { return }
                    put(.forwarded(part), into)
                    walk(inner, into, depth: depth + 1)
                    return
                }
                // A part the sender marked as an attachment is a file,
                // however text-like it is: a 4 MB log.txt must not become the
                // message body. Anything else under text/* (plain, enriched,
                // calendar) reads as the text body. Showing an invite's raw
                // ICS beats showing nothing.
                put(part.type == "text" && part.disposition != "attachment" ? .words(part) : .file(part),
                    into)
                return
            }

            let children = part.children
            switch part.subtype {
            case "alternative":
                // RFC 2046: the alternatives are ordered worst to best, so
                // the last one that we understand wins: for the HTML the
                // last with HTML in it, for the plain words the last with
                // plain words, each as it always was, and for the plain
                // words of a letter with none, its HTML.
                let holds = children.map { Holds.of($0, depth: depth + 1) }
                let forHTML = holds.lastIndex { $0.html.hasHTML } ?? holds.lastIndex { $0.html.hasWords }
                let forText = holds.lastIndex { $0.text.hasPlain }
                var each: [(child: Int, into: Into)] = []
                func ask(_ child: Int?, _ target: Into) {
                    guard let child else { return }
                    if let i = each.firstIndex(where: { $0.child == child }) {
                        each[i].into.formUnion(target)
                    } else {
                        each.append((child, target))
                    }
                }
                if into.contains(.html) { ask(forHTML, .html) }
                if into.contains(.textAsHTML) { ask(forHTML, .textAsHTML) }
                if into.contains(.text) {
                    if let forText { ask(forText, .text) } else { ask(forHTML, .textAsHTML) }
                }
                for (child, target) in each.sorted(by: { $0.child < $1.child }) {
                    walk(children[child], target, depth: depth + 1)
                }
            case "related", "signed", "encrypted", "report":
                // The first part with words is the letter; the rest are the
                // pictures it shows, its signature, or, in a report, the
                // status and the letter it is about. As it always was.
                if let letter = children.first(where: { Holds.of($0, depth: depth + 1).hasWords }) {
                    walk(letter, into, depth: depth + 1)
                }
            default:
                sequence(children, into, depth: depth + 1)
            }
        }

        /// A mixed, and any multipart not named above, which RFC 2046 has
        /// read as one: every part in its turn, as Mail draws them. The
        /// words, a file, and the words after it (B-113); a note, and the
        /// letter it forwards inline (B-114).
        ///
        /// But for the text parts that are words only when there are no
        /// others (`isSecondaryText`): one with a name, which the header
        /// lists as a file (B-101), and one neither plain nor HTML, an
        /// invitation's raw ICS, say. With other words beside them they are
        /// what they always were then, the named ones files and the rest
        /// nothing; with none, the first of them is the letter's words, as
        /// it was. Whether there are others is asked only of a multipart
        /// with such a part in it, once.
        private mutating func sequence(_ children: [MIMEPart], _ into: Into, depth: Int) {
            var others: Bool?
            var tookOne = false
            for child in children {
                guard !live(into).isEmpty else { return }
                if MIMEDecoder.isSecondaryText(child) {
                    let hasOthers = others ?? children.contains {
                        !MIMEDecoder.isSecondaryText($0) && Holds.of($0, depth: depth).hasWords
                    }
                    others = hasOthers
                    if hasOthers || tookOne {
                        if MIMEDecoder.decodedFilename(child) != nil { put(.file(child), into) }
                        continue
                    }
                    tookOne = true
                }
                walk(child, into, depth: depth)
            }
        }
    }

    /// What a part's HTML and its plain words hold, by the rules `Walk`
    /// walks them by, without making either: for the choices an
    /// alternative, a related and a mixed make between their parts.
    private struct Holds {
        struct List {
            /// A part of HTML.
            var hasHTML = false
            /// A part of words that is not HTML.
            var hasPlain = false
            /// Any words, a forwarded letter's header lines among them.
            var hasWords = false

            mutating func add(_ other: List) {
                hasHTML = hasHTML || other.hasHTML
                hasPlain = hasPlain || other.hasPlain
                hasWords = hasWords || other.hasWords
            }
        }

        var html = List()
        var text = List()

        var hasWords: Bool { html.hasWords || text.hasWords }

        static func of(_ part: MIMEPart, depth: Int) -> Holds {
            guard depth <= MIMEDecoder.maxDepth else { return Holds() }

            if !part.isMultipart {
                if part.type == "message", part.subtype == "rfc822", !part.isAttachment {
                    guard let inner = part.children.first else { return Holds() }
                    var held = of(inner, depth: depth + 1)
                    held.html.hasWords = true
                    held.text.hasWords = true
                    return held
                }
                guard part.type == "text", part.disposition != "attachment" else { return Holds() }
                let isHTML = part.subtype == "html"
                let list = List(hasHTML: isHTML, hasPlain: !isHTML, hasWords: true)
                return Holds(html: list, text: list)
            }

            let children = part.children
            switch part.subtype {
            case "alternative":
                let holds = children.map { of($0, depth: depth + 1) }
                let html = (holds.last { $0.html.hasHTML } ?? holds.last { $0.html.hasWords })?.html
                    ?? List()
                return Holds(html: html, text: holds.last { $0.text.hasPlain }?.text ?? html)
            case "related", "signed", "encrypted", "report":
                for child in children {
                    let held = of(child, depth: depth + 1)
                    if held.hasWords { return held }
                }
                return Holds()
            default:
                // Every part's, unless one is a text part that is words only
                // when there are no others: then those beside other words
                // are left out, and of those beside none, the first is in.
                var out = Holds()
                var holds: [Holds] = []
                holds.reserveCapacity(children.count)
                var anySecondary = false
                for child in children {
                    let held = of(child, depth: depth + 1)
                    holds.append(held)
                    out.html.add(held.html)
                    out.text.add(held.text)
                    if !anySecondary, MIMEDecoder.isSecondaryText(child) { anySecondary = true }
                }
                guard anySecondary else { return out }
                let secondary = children.map(MIMEDecoder.isSecondaryText)
                let hasOthers = holds.indices.contains { !secondary[$0] && holds[$0].hasWords }
                out = Holds()
                var tookOne = false
                for i in children.indices {
                    if secondary[i] {
                        // A file, or nothing: neither holds words.
                        if hasOthers || tookOne { continue }
                        tookOne = true
                    }
                    out.html.add(holds[i].html)
                    out.text.add(holds[i].text)
                }
                return out
            }
        }
    }

    /// A text part that is the letter's words only when it has no others.
    private static func isSecondaryText(_ part: MIMEPart) -> Bool {
        guard !part.isMultipart, part.type == "text", part.disposition != "attachment" else {
            return false
        }
        if part.subtype != "plain" && part.subtype != "html" { return true }
        // A part with no parameters has no name: asked first, as nearly
        // every part has none of either.
        if part.parameters.isEmpty && part.dispositionParameters.isEmpty { return false }
        return decodedFilename(part) != nil
    }

    private static func isWords(_ piece: BodyPiece) -> Bool {
        if case .file = piece { return false }
        return true
    }

    private static func isHTML(_ piece: BodyPiece) -> Bool {
        piece.words?.subtype == "html"
    }

    private static func isPlain(_ piece: BodyPiece) -> Bool {
        piece.words.map { $0.subtype != "html" } ?? false
    }

    /// One body, its pieces joined in order, or nil when it has none of its
    /// own kind: no HTML part for the HTML, no plain part for the plain
    /// words, as before. A body of one part is that part's words exactly as
    /// they came, so a letter of one is as it always was. `words` gives a
    /// part's words, and whether they are only its beginning, nil when it
    /// has none to hand, and `fields` a forwarded letter's header lines.
    ///
    /// Joined, an HTML part goes in without its wrapper (`DocumentWrapper`,
    /// which the pane takes off anyway), plain words as escaped text that
    /// keeps its lines, a file among the words as a mark the pane draws it
    /// at (`BodyFiles`), and a forwarded letter's header lines in Mail's
    /// form (`ForwardedFields`). In the plain words an HTML part is its text
    /// (`HTMLText`), as a reply would quote it, a file is nothing, and each
    /// part begins a line of its own.
    ///
    /// The body ends at the first part whose words are not to hand, or come
    /// only in part, and after the last part it holds when it `goesOn`
    /// past them (`BodyPlan`): a letter too large to fetch whole is shown up
    /// to where its fetch stopped, as one of one part always was, and
    /// nothing is drawn after words cut short, inside whatever tag the cut
    /// fell in. So a file's mark and a forwarded letter's header lines wait
    /// for the words after them, and go with them; at the end of a body
    /// that came whole, the lines of a letter that forwards no words go in
    /// all the same.
    ///
    /// `partStarts` is told each part of words that goes in, by its
    /// section, and the byte of the body's UTF-8 its words begin at, the
    /// line and any forwarded letter's header lines before them with them;
    /// not for a body of one part, which is that part (`Message.textParts`,
    /// B-185).
    static func joined(_ pieces: [BodyPiece], asHTML: Bool, goesOn: Bool = false,
                       words: (MIMEPart) -> (text: String, cut: Bool)?,
                       fields: (MIMEPart) -> ForwardedFields?,
                       partStarts: ((_ section: String, _ start: Int) -> Void)? = nil) -> String? {
        let drawn = drawnPieces(pieces, asHTML: asHTML)
        guard drawn.contains(where: asHTML ? isHTML : isPlain) else { return nil }
        if drawn.count == 1, let only = drawn[0].words { return words(only)?.text }

        var out = ""
        var any = false
        var waiting: [(section: String, header: ForwardedFields?)] = []
        func startLine() {
            if !out.isEmpty, !out.hasSuffix("\n") { out += "\n" }
        }
        func putWaiting() {
            for (section, header) in waiting {
                guard let header else {
                    out += BodyFiles.mark(section)
                    continue
                }
                if asHTML {
                    out += header.html
                } else {
                    startLine()
                    if !out.isEmpty { out += "\n" }
                    out += header.text
                }
            }
            waiting = []
        }
        var whole = !goesOn
        walk: for piece in drawn {
            switch piece {
            case .words(let part):
                guard let got = words(part) else {
                    whole = false
                    break walk
                }
                partStarts?(part.section, out.utf8.count)
                any = true
                putWaiting()
                let isHTMLPart = part.subtype == "html"
                if asHTML {
                    out += isHTMLPart
                        ? DocumentWrapper.stripped(from: got.text)
                        : "<div style=\"white-space: pre-wrap;\">" + QuotedMarkup.escaped(got.text) + "</div>"
                } else {
                    startLine()
                    out += isHTMLPart ? HTMLText.plainText(from: got.text) : got.text
                }
                if got.cut {
                    whole = false
                    break walk
                }
            case .file(let part):
                waiting.append((part.section, nil))
            case .forwarded(let letter):
                guard let header = fields(letter), !header.lines.isEmpty else { continue }
                waiting.append((letter.section, header))
            }
        }
        if whole { putWaiting() }
        return any ? out : nil
    }

    /// The pieces a body draws: every part of words; a file only in the
    /// HTML, and only with words after it, where Mail draws it among them
    /// or above them, a file after all of them drawn by the pane after the
    /// words (`BodyFiles`, B-170); and a forwarded letter's header lines
    /// only when there are words outside it, so a letter that is nothing
    /// but the one it forwards reads as it always did.
    private static func drawnPieces(_ pieces: [BodyPiece], asHTML: Bool) -> [BodyPiece] {
        let last = pieces.lastIndex(where: isWords)
        let allWords = pieces.reduce(0) { $0 + ($1.words == nil ? 0 : 1) }
        var out: [BodyPiece] = []
        for (i, piece) in pieces.enumerated() {
            switch piece {
            case .words:
                out.append(piece)
            case .file:
                guard asHTML, let last, i < last else { continue }
                out.append(piece)
            case .forwarded(let letter):
                // Its own pieces come straight after it, every one a part
                // inside it: counted by walking them, once each.
                let inside = letter.section + "."
                var held = 0
                var j = i + 1
                while j < pieces.count, section(of: pieces[j]).hasPrefix(inside) {
                    if pieces[j].words != nil { held += 1 }
                    j += 1
                }
                if allWords > held { out.append(piece) }
            }
        }
        return out
    }

    private static func section(of piece: BodyPiece) -> String {
        switch piece {
        case .words(let part), .file(let part), .forwarded(let part): return part.section
        }
    }

    /// A forwarded letter's header lines: from its own header, in the
    /// part's bytes, for a letter downloaded; from the envelope its
    /// BODYSTRUCTURE carries (`MIMEPart.envelope`), for one shown from its
    /// structure; nil with neither.
    static func forwardedFields(of letter: MIMEPart, header: Data?) -> ForwardedFields? {
        if let header {
            let headers = parseHeaders(header)
            func addresses(_ name: String) -> [String] {
                MailFormat.addressList(headerValue(name, in: headers) ?? "")
                    .map { decodeWord($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
            return ForwardedFields(from: addresses("From"),
                                   date: headerValue("Date", in: headers).flatMap(IMAPParser.parseHeaderDate),
                                   to: addresses("To"), cc: addresses("Cc"),
                                   subject: headerValue("Subject", in: headers).map(decodeWord))
        }
        guard let envelope = letter.envelope?.value else { return nil }
        return ForwardedFields(from: envelope.from.map(\.formatted), date: envelope.date,
                               to: envelope.to.map(\.formatted), cc: envelope.cc.map(\.formatted),
                               subject: envelope.subject)
    }

    /// How much of each part of words a letter too large to fetch whole
    /// fetches (`IMAPMailRepository.loadMessage`): each body's parts share
    /// the limit in turn, each given what the ones before it left, so the
    /// HTML and the plain words are each no more than the limit, as each
    /// was when each was one part, and a body of one part is fetched as it
    /// always was.
    struct Allowance {
        /// Each part's bytes in the HTML and in the plain words, by section.
        var html: [String: Int] = [:]
        var text: [String: Int] = [:]
        /// What to fetch: each part with the more of its two, the plain
        /// words' first, and none given nothing. Each by the name it is
        /// asked for by on the wire (`MIMEPart.fetchSection`), which its
        /// bytes come back under (`IMAPClient.LetterInPart.sections`):
        /// "2.TEXT" for the words numbered 2.1 of a letter forwarded as 2,
        /// taken from the part the plan holds, so no structure is searched
        /// for it (B-114).
        var fetches: [(section: String, bytes: Int)] = []

        init(_ plan: BodyPlan, limit: Int) {
            let text = Self.shares(plan.text, limit: limit)
            let html = Self.shares(plan.html, limit: limit)
            self.text = Dictionary(text.map { ($0.part.section, $0.bytes) },
                                   uniquingKeysWith: { first, _ in first })
            self.html = Dictionary(html.map { ($0.part.section, $0.bytes) },
                                   uniquingKeysWith: { first, _ in first })
            var listed = Set<String>()
            for (part, _) in text + html where listed.insert(part.section).inserted {
                let bytes = max(self.text[part.section] ?? 0, self.html[part.section] ?? 0)
                if bytes > 0 { fetches.append((part.fetchSection, bytes)) }
            }
        }

        private static func shares(_ pieces: [BodyPiece],
                                   limit: Int) -> [(part: MIMEPart, bytes: Int)] {
            var left = limit
            var out: [(part: MIMEPart, bytes: Int)] = []
            for part in pieces.compactMap(\.words) {
                out.append((part, left))
                left -= min(part.size ?? left, left)
            }
            return out
        }
    }

    private static func collectAttachments(_ part: MIMEPart,
                                           skipping: Set<String>,
                                           depth: Int,
                                           into list: inout [Attachment]) {
        guard depth <= maxDepth, list.count < maxAttachments else { return }

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
        // One among a letter's words is in `skipping` (B-113); one neither
        // plain nor HTML beside other words, a calendar's ICS, is neither.
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
    ///
    /// Also whether a text part sent inline is named, for its paperclip
    /// (`MIMEPart.isListedFile`), so that the paperclip and the file drawn
    /// in the body ask the same question of it.
    static func decodedFilename(_ part: MIMEPart) -> String? {
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
