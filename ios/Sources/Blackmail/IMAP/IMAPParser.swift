import Foundation

/// The IMAP response parser. Pure data in, pure data out: no sockets, no
/// state, nothing async. Everything here can be exercised from a unit test
/// with a string literal, which matters more than usual on this project —
/// there is no simulator, so anything that can only be tested against a live
/// server costs a full build/sign/deploy cycle to check.
///
/// The parser is deliberately forgiving. A 90-year-old man is reading his real
/// mail on this, and the failure mode of a strict parser is an empty mailbox:
/// one message with a field the RFC does not quite allow takes out the whole
/// screen. So every function here returns what it managed to understand and
/// silently drops what it did not. Nothing throws, nothing traps, and no loop
/// can fail to terminate on malformed input.

/// One lexical unit of an IMAP response.
///
/// `Equatable` is synthesised purely so tests can compare an expected token
/// tree against a parsed one; no production code depends on it.
indirect enum IMAPToken: Equatable {
    case atom(String)
    case quoted(String)
    /// An index into `IMAPResponseLine.literals`, not a length. The transport
    /// has already read the bytes off the socket by the time we see the line.
    case literal(Int)
    case list([IMAPToken])
    case nilValue
}

enum IMAPParser {

    /// How deeply a response may nest before the tokenizer stops nesting. Real
    /// mail does not come close: `MIMEDecoder` caps a MIME tree at 20 levels,
    /// and each of those costs about two here.
    private static let maxNesting = 100

    /// How deeply a BODYSTRUCTURE may nest before the walker stops descending,
    /// matching `MIMEDecoder.maxDepth` so a message fetched whole and the same
    /// message described by the server truncate at the same place.
    private static let maxBodyDepth = 20

    // MARK: - Tokenizer

    /// Splits one response line into tokens.
    ///
    /// IMAP's grammar is parenthesised lists of atoms, quoted strings, `NIL`
    /// and literals, nested to any depth. Two traps are worth naming:
    ///
    /// 1. A literal is not in the text. `TLSConnection` has already consumed
    ///    the raw bytes and left a `\u{0}<index>\u{0}` marker behind, so this
    ///    emits `.literal(index)` and the caller resolves the bytes through
    ///    `IMAPResponseLine.literals`. That is the only way a body containing
    ///    CRLFs or NULs can survive being treated as "a line".
    /// 2. A bracketed suffix is part of the atom, not a list. `BODY[HEADER.FIELDS
    ///    (DATE FROM)]<0>` is *one* FETCH item name even though it contains
    ///    spaces and parentheses; splitting it would silently misalign every
    ///    key/value pair that follows it.
    ///
    /// Unbalanced parentheses cannot fail: a stray `)` is dropped and an
    /// unclosed `(` is closed at end of line, so a truncated response still
    /// yields whatever prefix of it was intelligible.
    ///
    /// Nesting past `maxNesting` is flattened into the deepest list still
    /// allowed rather than nested further. The tokenizer itself is iterative
    /// and could take any depth, but the tree it builds is an *indirect* enum,
    /// and releasing one a hundred thousand levels deep recurses in the runtime
    /// and overflows the stack before any parser has looked at it.
    static func tokenize(_ line: IMAPResponseLine) -> [IMAPToken] {
        let chars = Array(line.text)
        // A stack of open lists; index 0 is the top level and is never popped.
        var stack: [[IMAPToken]] = [[]]
        // Opens refused by the depth cap, so their closing ')' is swallowed
        // instead of popping a list it never opened.
        var suppressedOpens = 0
        var i = 0

        while i < chars.count {
            let c = chars[i]

            if c == " " || c == "\t" || c == "\r" || c == "\n" {
                i += 1
                continue
            }

            switch c {
            case "(":
                if stack.count > Self.maxNesting {
                    suppressedOpens += 1
                } else {
                    stack.append([])
                }
                i += 1

            case ")":
                i += 1
                if suppressedOpens > 0 {
                    suppressedOpens -= 1
                    continue
                }
                // A ')' with nothing open means the line is malformed. Dropping
                // it keeps the tokens we already have, which is always better
                // than discarding the response.
                guard stack.count > 1 else { continue }
                let finished = stack.removeLast()
                stack[stack.count - 1].append(.list(finished))

            case "\"":
                let (text, next) = scanQuoted(chars, from: i)
                stack[stack.count - 1].append(.quoted(text))
                i = next

            case IMAPResponseLine.literalMarker:
                if let (index, next) = scanLiteralMarker(chars, from: i) {
                    stack[stack.count - 1].append(.literal(index))
                    i = next
                } else {
                    i += 1   // A NUL that is not a well-formed marker: drop it.
                }

            default:
                let (text, next) = scanAtom(chars, from: i)
                if text.isEmpty {
                    i += 1   // Belt and braces: the cursor must always advance.
                } else {
                    // NIL is a value, not an atom called "NIL". A mailbox
                    // genuinely named NIL arrives quoted, so this cannot eat it.
                    stack[stack.count - 1].append(
                        text.caseInsensitiveCompare("NIL") == .orderedSame ? .nilValue : .atom(text))
                    i = next
                }
            }
        }

        // Close anything the server left open.
        while stack.count > 1 {
            let finished = stack.removeLast()
            stack[stack.count - 1].append(.list(finished))
        }
        return stack[0]
    }

    /// Reads a quoted string starting at the opening quote. Returns the
    /// unescaped contents and the index just past the closing quote.
    private static func scanQuoted(_ chars: [Character], from start: Int) -> (String, Int) {
        var out = ""
        var i = start + 1
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count {
                // RFC 3501 only defines \" and \\, but a server that escapes
                // something else means the character, not the backslash.
                out.append(chars[i + 1])
                i += 2
                continue
            }
            if c == "\"" { return (out, i + 1) }
            out.append(c)
            i += 1
        }
        return (out, i)   // Unterminated: take what there was.
    }

    /// Reads a `\u{0}<index>\u{0}` literal marker, or returns nil if the NUL is
    /// not actually the start of one.
    private static func scanLiteralMarker(_ chars: [Character], from start: Int) -> (Int, Int)? {
        var i = start + 1
        var digits = ""
        while i < chars.count, chars[i].isASCII, chars[i].isNumber {
            digits.append(chars[i])
            i += 1
        }
        guard i < chars.count, chars[i] == IMAPResponseLine.literalMarker,
              let index = Int(digits) else { return nil }
        return (index, i + 1)
    }

    /// Reads a bare atom. Inside `[...]` nothing terminates the atom except a
    /// literal marker, which is what keeps `BODY[HEADER.FIELDS (TO)]` whole.
    private static func scanAtom(_ chars: [Character], from start: Int) -> (String, Int) {
        var out = ""
        var i = start
        var bracketDepth = 0
        while i < chars.count {
            let c = chars[i]
            if c == IMAPResponseLine.literalMarker { break }
            if c == "[" {
                bracketDepth += 1
            } else if c == "]", bracketDepth > 0 {
                bracketDepth -= 1
            } else if bracketDepth == 0 {
                if c == " " || c == "\t" || c == "\r" || c == "\n" { break }
                if c == "(" || c == ")" || c == "\"" { break }
            }
            out.append(c)
            i += 1
        }
        return (out, i)
    }

    // MARK: - Response codes

    /// `"[AUTHENTICATIONFAILED] Invalid credentials"` -> `"AUTHENTICATIONFAILED"`.
    ///
    /// Uppercased on the way out so a caller can compare against a literal
    /// without worrying about a server that shouts quietly.
    static func responseCode(_ detail: String) -> String? {
        bracketedCode(detail)?.name
    }

    /// The text of an `[ALERT]` or `[WEBALERT …]` code, from the tagged
    /// answer `detail` or from any untagged status line of the same command,
    /// or nil if there is none. `"[ALERT] Please log in via your web browser
    /// (Failure)"` -> `"Please log in via your web browser (Failure)"`.
    ///
    /// RFC 3501 §7.1 says an ALERT's text MUST be shown to the user, and it
    /// is where Gmail says why it refused a sign-in that was not the
    /// password: an app password required, a sign-in on the web required, an
    /// account not enabled for IMAP. WEBALERT is Gmail's own, and its
    /// argument, a sign-in address for the account, is left out: it is a
    /// link into his Google account, not a sentence, and the connection log
    /// has the whole line. One line of printable characters, and no more
    /// than `alertLength` of them, since it goes into an alert.
    static func alert(in detail: String, untagged: [IMAPResponseLine] = []) -> String? {
        let statusWords: Set<String> = ["OK", "NO", "BAD", "BYE"]
        let lines = [detail] + untagged.compactMap { line -> String? in
            let words = line.text.split(separator: " ", maxSplits: 2)
            guard words.count == 3, words[0] == "*",
                  statusWords.contains(words[1].uppercased()) else { return nil }
            return String(words[2])
        }
        for line in lines {
            guard let code = bracketedCode(line), code.name == "ALERT" || code.name == "WEBALERT",
                  let close = line.firstIndex(of: "]") else { continue }
            let printable = line[line.index(after: close)...].unicodeScalars.map { scalar -> Character in
                scalar.properties.generalCategory == .control ? " " : Character(scalar)
            }
            let text = String(printable).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !text.isEmpty else { continue }
            return text.count > alertLength ? String(text.prefix(alertLength)) + "…" : text
        }
        return nil
    }

    /// Longer than any refusal Gmail is known to give, a sentence and a help
    /// page's address; short enough for an alert on a screen he can read.
    static let alertLength = 300

    /// Splits a leading `[NAME argument]` into its two halves. The argument is
    /// returned raw, because `[PERMANENTFLAGS (\Seen \*)]` needs re-tokenizing
    /// while `[UIDNEXT 42]` just needs an integer.
    private static func bracketedCode(_ text: String) -> (name: String, argument: String?)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") else { return nil }
        let inner = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            .trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty else { return nil }
        guard let space = inner.firstIndex(of: " ") else { return (inner.uppercased(), nil) }
        let argument = String(inner[inner.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        return (String(inner[..<space]).uppercased(), argument.isEmpty ? nil : argument)
    }

    // MARK: - SELECT

    /// Reads the untagged flood a SELECT (or EXAMINE) produces.
    ///
    /// Note that `[READ-ONLY]` normally rides on the *tagged* completion line,
    /// which is not an untagged response and so is not in this array. A session
    /// that cares whether the mailbox is writable should append the tagged
    /// detail as one more `IMAPResponseLine` before calling; this scans every
    /// line it is given for the code, so that just works.
    ///
    /// Returns nil only when nothing in the input resembled a SELECT response
    /// at all, so the caller can tell "mailbox with no messages" (a state with
    /// `exists == 0`) apart from "the SELECT never happened".
    static func parseSelect(_ untagged: [IMAPResponseLine]) -> IMAPMailboxState? {
        var uidValidity: UInt32 = 0
        var uidNext: UInt32 = 0
        var exists = 0
        var flags: [String] = []
        var permanentFlags: [String] = []
        var readOnly = false
        var recognisedSomething = false

        for line in untagged {
            let tokens = tokenize(line)
            for (index, token) in tokens.enumerated() {
                guard let atom = token.atomText else { continue }
                let upper = atom.uppercased()

                if upper == "EXISTS", index > 0, let count = tokens[index - 1].int(line) {
                    exists = count
                    recognisedSomething = true
                    continue
                }
                if upper == "FLAGS", index + 1 < tokens.count,
                   let list = tokens[index + 1].listItems {
                    flags = list.compactMap { $0.text(line) }
                    recognisedSomething = true
                    continue
                }
                guard atom.hasPrefix("["), let code = bracketedCode(atom) else { continue }
                switch code.name {
                case "UIDVALIDITY":
                    if let value = code.argument.flatMap({ UInt32($0) }) {
                        uidValidity = value
                        recognisedSomething = true
                    }
                case "UIDNEXT":
                    if let value = code.argument.flatMap({ UInt32($0) }) {
                        uidNext = value
                        recognisedSomething = true
                    }
                case "PERMANENTFLAGS":
                    if let argument = code.argument {
                        // The argument is still wire text, so run it back
                        // through the tokenizer rather than splitting strings.
                        let inner = tokenize(IMAPResponseLine(text: argument, literals: line.literals))
                        permanentFlags = inner.compactMap { $0.listItems }.first?
                            .compactMap { $0.text(line) } ?? []
                        recognisedSomething = true
                    }
                case "READ-ONLY":
                    readOnly = true
                    recognisedSomething = true
                case "READ-WRITE":
                    readOnly = false
                    recognisedSomething = true
                default:
                    continue
                }
            }
        }

        guard recognisedSomething else { return nil }
        return IMAPMailboxState(uidValidity: uidValidity,
                                uidNext: uidNext,
                                exists: exists,
                                flags: flags,
                                permanentFlags: permanentFlags,
                                readOnly: readOnly)
    }

    // MARK: - LIST

    /// Reads `* LIST (\HasNoChildren \Sent) "/" "[Gmail]/Sent Mail"` rows.
    /// LSUB and Gmail's legacy XLIST have the same shape and are accepted too.
    static func parseList(_ untagged: [IMAPResponseLine]) -> [IMAPMailboxListing] {
        var out: [IMAPMailboxListing] = []

        for line in untagged {
            let tokens = tokenize(line)
            // The keyword is at index 1 of "* LIST ...". Searching only the
            // head of the line stops a *mailbox* called "LIST" from being
            // mistaken for the keyword.
            guard let keyword = Array(tokens.prefix(3)).firstIndex(where: {
                guard let atom = $0.atomText?.uppercased() else { return false }
                return atom == "LIST" || atom == "LSUB" || atom == "XLIST"
            }) else { continue }

            var index = keyword + 1
            var attributes: [String] = []
            if index < tokens.count, let list = tokens[index].listItems {
                attributes = list.compactMap { $0.text(line) }
                index += 1
            }

            var delimiter: String?
            if index < tokens.count {
                // NIL means a flat namespace, which is a real answer and not a
                // missing one, so it stays nil rather than defaulting to "/".
                delimiter = tokens[index].isNil ? nil : tokens[index].text(line)
                index += 1
            }

            guard index < tokens.count else { continue }
            var name: String
            if let first = tokens[index].atomText {
                // A bare atom cannot legally contain a space, yet servers do
                // send unquoted names with spaces. Gluing the trailing atoms
                // back on recovers those; it stops at the first parenthesised
                // group so RFC 5258 extended LIST data is not swallowed.
                var parts = [first]
                var next = index + 1
                while next < tokens.count, let more = tokens[next].atomText {
                    parts.append(more)
                    next += 1
                }
                name = parts.joined(separator: " ")
            } else {
                name = tokens[index].text(line) ?? ""
            }

            name = decodeModifiedUTF7(name)
            guard !name.isEmpty else { continue }
            out.append(IMAPMailboxListing(name: name, delimiter: delimiter, attributes: attributes))
        }
        return out
    }

    /// Decodes RFC 3501 §5.1.3 modified UTF-7, the encoding Gmail uses for any
    /// non-ASCII folder name. Without this a German user's "Wichtig" is fine
    /// but "Gelöscht" arrives as "Gel&APY-scht", and a Japanese folder name is
    /// unreadable entirely.
    ///
    /// Internal rather than private: the inverse operation is needed to SELECT
    /// such a folder, and whoever writes it will want this one beside it.
    static func decodeModifiedUTF7(_ raw: String) -> String {
        guard raw.contains("&") else { return raw }
        let chars = Array(raw)
        var out = ""
        var i = 0

        while i < chars.count {
            guard chars[i] == "&" else {
                out.append(chars[i])
                i += 1
                continue
            }
            if i + 1 < chars.count, chars[i + 1] == "-" {   // "&-" is a literal ampersand
                out.append("&")
                i += 2
                continue
            }
            var j = i + 1
            var encoded = ""
            while j < chars.count, isModifiedBase64(chars[j]) {
                encoded.append(chars[j])
                j += 1
            }
            // The shifted run ends at '-', which is absorbed, or at any
            // character outside the alphabet, which is not.
            if j < chars.count, chars[j] == "-" { j += 1 }

            if let decoded = decodeModifiedBase64(encoded) {
                out += decoded
                i = j
            } else {
                // Undecodable. Emitting the '&' verbatim leaves a slightly ugly
                // folder name; dropping the run would lose it altogether.
                out.append("&")
                i += 1
            }
        }
        return out
    }

    private static func isModifiedBase64(_ c: Character) -> Bool {
        guard c.isASCII else { return false }
        return (c >= "A" && c <= "Z") || (c >= "a" && c <= "z")
            || (c >= "0" && c <= "9") || c == "+" || c == ","
    }

    private static func decodeModifiedBase64(_ encoded: String) -> String? {
        guard !encoded.isEmpty else { return nil }
        // Modified BASE64 spells '/' as ',' so the delimiter stays usable in a
        // mailbox path, and drops the '=' padding.
        var b64 = encoded.replacingOccurrences(of: ",", with: "/")
        let remainder = b64.count % 4
        if remainder == 1 { return nil }
        if remainder > 0 { b64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: b64), data.count >= 2 else { return nil }

        let bytes = [UInt8](data)
        var units: [UInt16] = []
        units.reserveCapacity(bytes.count / 2)
        var i = 0
        while i + 1 < bytes.count {
            units.append(UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1]))
            i += 2
        }
        // The payload is UTF-16BE; this joins surrogate pairs and substitutes
        // U+FFFD for a broken one rather than failing.
        return String(decoding: units, as: UTF16.self)
    }

    // MARK: - SEARCH and STATUS

    /// `* SEARCH 1 2 3` -> `[1, 2, 3]`. SORT has the same shape and is accepted.
    /// Non-numeric trailers (CONDSTORE's `(MODSEQ 123)`) are ignored.
    ///
    /// A line that is nothing but the keyword and plain numbers, which is
    /// every answer Gmail gives a SEARCH, is read off its bytes in one pass
    /// (`plainSearchNumbers`); anything else goes through the tokenizer as
    /// it always did. His All Mail is 250,000 to 400,000 letters, and its
    /// `UID SEARCH ALL` one line of that many numbers, about 3 MB: the
    /// tokenizer made a `Character` array of it and a `String` of every
    /// number, about 90 ms for 60,000 UIDs in a release build here and
    /// 0.64 s for 400,000, on every listing of it from the top and every
    /// date jump in it; read off its bytes, 400,000 take about 6 ms.
    static func parseSearch(_ untagged: [IMAPResponseLine]) -> [UInt32] {
        var out: [UInt32] = []
        for line in untagged {
            if line.literals.isEmpty, let numbers = plainSearchNumbers(line.text) {
                out += numbers
                continue
            }
            out += tokenizedSearchNumbers(line)
        }
        return out
    }

    /// The numbers of `* SEARCH n n n` or `* SORT n n n`, the keyword in
    /// either case, read off the line's bytes once; nil for a line of any
    /// other shape, which the caller then gives the tokenizer.
    ///
    /// Only what the tokenizer would read the same way is taken, so for a
    /// line taken here the two give the same numbers by construction:
    /// exactly `* `, the keyword, then nothing, or one space and numbers
    /// each separated from the next by one space. A second space, a space
    /// at the end, a tab, a range (`1:5`), a trailer (`(MODSEQ 7)`), a
    /// letter, a number of eleven digits or one past `UInt32` and the line
    /// goes to the tokenizer, which has its own rule for each. So does
    /// `* SEARCH1` or `* SEARCHES`, and `* ESEARCH`, which is not a
    /// SEARCH answer at all.
    static func plainSearchNumbers(_ text: String) -> [UInt32]? {
        var text = text
        return text.withUTF8 { b -> [UInt32]? in
            let n = b.count
            guard n >= 2, b[0] == 0x2A, b[1] == 0x20 else { return nil }   // "* "
            // The keyword, compared without regard to case: a byte OR'd
            // with 0x20 equals a lower-case letter only when it is that
            // letter in either case.
            func keyword(_ word: [UInt8]) -> Bool {
                guard n >= 2 + word.count else { return false }
                for (k, letter) in word.enumerated() where b[2 + k] | 0x20 != letter {
                    return false
                }
                return true
            }
            var i: Int
            if keyword(Self.searchWord) {
                i = 2 + Self.searchWord.count
            } else if keyword(Self.sortWord) {
                i = 2 + Self.sortWord.count
            } else {
                return nil
            }
            if i == n { return [] }                 // "* SEARCH": nothing found
            guard b[i] == 0x20 else { return nil }  // "* SEARCH1", "* SEARCHES"
            i += 1

            // A number takes at least two bytes with its space, and the
            // UIDs of a large mailbox six or seven.
            var out: [UInt32] = []
            out.reserveCapacity((n - i) / 7 + 1)
            while true {
                var value: UInt32 = 0
                var digits = 0
                while i < n, b[i] >= 0x30, b[i] <= 0x39 {
                    digits += 1
                    guard digits <= 10 else { return nil }
                    let (tens, over) = value.multipliedReportingOverflow(by: 10)
                    let (sum, past) = tens.addingReportingOverflow(UInt32(b[i] &- 0x30))
                    guard !over, !past else { return nil }
                    value = sum
                    i += 1
                }
                // No digit: a second space, a space at the end, or
                // something other than a number.
                guard digits > 0 else { return nil }
                out.append(value)
                if i == n { return out }
                guard b[i] == 0x20 else { return nil }
                i += 1
            }
        }
    }

    private static let searchWord = Array("search".utf8)
    private static let sortWord = Array("sort".utf8)

    /// One untagged line's SEARCH or SORT numbers as the tokenizer reads
    /// them: the keyword among the first three tokens, every number after
    /// it, a range expanded, anything else passed over. The whole of
    /// `parseSearch` before the byte path, and still what any line not
    /// taken there goes through.
    static func tokenizedSearchNumbers(_ line: IMAPResponseLine) -> [UInt32] {
        let tokens = tokenize(line)
        guard let keyword = Array(tokens.prefix(3)).firstIndex(where: {
            guard let atom = $0.atomText?.uppercased() else { return false }
            return atom == "SEARCH" || atom == "SORT"
        }) else { return [] }

        var out: [UInt32] = []
        for token in tokens.dropFirst(keyword + 1) {
            guard let atom = token.atomText else { continue }
            if let single = UInt32(atom) {
                out.append(single)
                continue
            }
            // Plain SEARCH never sends a range, but a caller that feeds us
            // a set from elsewhere should not silently lose it. Bounded,
            // because "1:4294967295" would otherwise allocate 16 GB.
            let bounds = atom.split(separator: ":", maxSplits: 1)
            if bounds.count == 2, let low = UInt32(bounds[0]), let high = UInt32(bounds[1]),
               low <= high, high - low < 50_000 {
                out.append(contentsOf: low...high)
            }
        }
        return out
    }

    /// The numbers of the plain `* SEARCH` lines among `untagged`, as
    /// `parseSearch` reads them, or nil when there is no such line: how a
    /// SEARCH that found nothing, `* SEARCH` alone, is told from an answer
    /// with no SEARCH line in it at all. For a server that answers `UID
    /// SEARCH RETURN (MIN)` as if RETURN were not there.
    ///
    /// A line is looked at no further than its first nine characters
    /// before `parseSearch` has it, so his All Mail's 3 MB answer is read
    /// once, off its bytes, as any SEARCH answer is.
    static func plainSearchAnswer(_ untagged: [IMAPResponseLine]) -> [UInt32]? {
        let lines = untagged.filter { line in
            let head = line.text.prefix(9).uppercased()
            return head == "* SEARCH" || head == "* SEARCH "
        }
        return lines.isEmpty ? nil : parseSearch(lines)
    }

    /// What an ESEARCH answer (RFC 4731) to `UID SEARCH RETURN (MIN)` says
    /// of the lowest UID matched: `[n]`, `[]` when nothing matched, or nil
    /// when it does not say. Nil is never read as nothing found: the caller
    /// asks again with a plain SEARCH.
    ///
    /// The answer's result items, after `UID`, are read in pairs, a name
    /// and its value:
    ///
    /// - `MIN n`: `[n]`, whatever is beside it.
    /// - `ALL 3:9,12` and no MIN: the lowest of the set, `[3]`.
    /// - No items at all, `* ESEARCH (TAG "a012") UID`: `[]`. A server
    ///   leaves MIN out when nothing matched, and says nothing else it was
    ///   not asked for. So is `COUNT 0` with no MIN: none matched.
    /// - Anything else is nil. Items that say something, but not the
    ///   lowest, `COUNT 37` or `COUNT 12 MAX 900`, as from a server that
    ///   answered other than it was asked. A malformed one: a name with no
    ///   value (`UID MIN`), a MIN or a COUNT that is not a number, a MIN of
    ///   0, which no UID is, a set that is not one or has a `*` in it.
    ///
    /// Nil too when no line among `untagged` is an ESEARCH answer, or one
    /// is but does not say UID, when its numbers would be message sequence
    /// numbers rather than UIDs. The first ESEARCH line is the answer.
    ///
    /// The correlator is not compared with the command's tag: one command
    /// is on the connection at a time (`IMAPClient`'s gate), so an ESEARCH
    /// line among its untagged answers is its own.
    static func parseSearchMinimum(_ untagged: [IMAPResponseLine]) -> [UInt32]? {
        for line in untagged {
            let tokens = tokenize(line)
            guard tokens.count >= 2, tokens[0].atomText == "*",
                  tokens[1].atomText?.uppercased() == "ESEARCH" else { continue }
            var rest = tokens.dropFirst(2)
            if rest.first?.isList == true { rest = rest.dropFirst() }
            guard rest.first?.atomText?.uppercased() == "UID" else { return nil }
            return lowestAnswered(Array(rest.dropFirst()))
        }
        return nil
    }

    /// An ESEARCH answer's result items read for the lowest UID, as
    /// `parseSearchMinimum` says.
    private static func lowestAnswered(_ items: [IMAPToken]) -> [UInt32]? {
        if items.isEmpty { return [] }
        guard items.count % 2 == 0 else { return nil }
        var minimum: UInt32?
        var lowestOfAll: UInt32?
        var count: UInt32?
        for at in stride(from: 0, to: items.count, by: 2) {
            guard let name = items[at].atomText?.uppercased() else { return nil }
            let value = items[at + 1].atomText
            switch name {
            case "MIN":
                guard let uid = value.flatMap(Self.uid) else { return nil }
                minimum = uid
            case "ALL":
                guard let uid = value.flatMap(Self.lowestInSet) else { return nil }
                lowestOfAll = uid
            case "COUNT":
                guard let number = value.flatMap(Self.digits) else { return nil }
                count = number
            default:
                // MAX, or an extension's item: nothing about the lowest.
                continue
            }
        }
        if let minimum { return [minimum] }
        if let lowestOfAll { return [lowestOfAll] }
        if count == 0 { return [] }
        return nil
    }

    /// `text` as a number if it is nothing but ASCII digits, and fits.
    private static func digits(_ text: String) -> UInt32? {
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        return UInt32(text)
    }

    /// `text` as a UID: digits, and not 0.
    private static func uid(_ text: String) -> UInt32? {
        digits(text).flatMap { $0 > 0 ? $0 : nil }
    }

    /// The lowest UID in a sequence set, `3:9,12` → 3, either way round a
    /// range goes (`9:3` is the same range); nil for anything that is not
    /// a set of UIDs, `*` included, which an answer has no business giving.
    private static func lowestInSet(_ text: String) -> UInt32? {
        var lowest: UInt32?
        for part in text.split(separator: ",", omittingEmptySubsequences: false) {
            let ends = part.split(separator: ":", omittingEmptySubsequences: false)
            guard ends.count == 1 || ends.count == 2 else { return nil }
            for end in ends {
                guard let number = uid(String(end)) else { return nil }
                lowest = min(lowest ?? number, number)
            }
        }
        return lowest
    }

    /// The selected mailbox's message count once the `* 20 EXISTS` and
    /// `* 3 EXPUNGE` lines among `untagged` have been applied to `count`, in
    /// the order they came, or nil if there are none.
    ///
    /// Either can ride on the answer to any command, so this sees every
    /// answer, and most of what it sees is FETCH lines that can run to
    /// kilobytes. So nothing is tokenized: a line long enough to be anything
    /// else is passed over on its length, which is free, and only a short
    /// one is split into words.
    static func messageCount(after untagged: [IMAPResponseLine], from count: Int) -> Int? {
        sizeChanges(after: untagged, from: count)?.count
    }

    /// `messageCount`, and whether any of the lines was an EXPUNGE. The
    /// count alone cannot say a mailbox changed: a letter taken out
    /// elsewhere and one arriving in the same answer leave it where it was.
    static func sizeChanges(after untagged: [IMAPResponseLine],
                            from count: Int) -> (count: Int, expunged: Bool)? {
        var current: Int?
        var expunged = false
        for line in untagged {
            // "* 4294967295 EXPUNGE" is 20 bytes.
            guard line.text.utf8.count <= 32 else { continue }
            let words = line.text.split(separator: " ")
            guard words.count == 3, words[0] == "*", let number = Int(words[1]) else { continue }
            switch words[2].uppercased() {
            case "EXISTS":
                current = number
            case "EXPUNGE":
                current = max(0, (current ?? count) - 1)
                expunged = true
            default:
                continue
            }
        }
        return current.map { ($0, expunged) }
    }

    /// `* STATUS "INBOX" (MESSAGES 231 UNSEEN 3)` -> `["MESSAGES": 231, "UNSEEN": 3]`.
    /// Keys are uppercased. A 64-bit HIGHESTMODSEQ does not fit `UInt32` and is
    /// dropped rather than truncated to a wrong number.
    static func parseStatus(_ untagged: [IMAPResponseLine]) -> [String: UInt32] {
        var out: [String: UInt32] = [:]
        for line in untagged {
            let tokens = tokenize(line)
            guard let keyword = Array(tokens.prefix(3)).firstIndex(where: {
                $0.atomText?.uppercased() == "STATUS"
            }) else { continue }
            guard let items = tokens.dropFirst(keyword + 1).first(where: { $0.isList })?.listItems
            else { continue }

            var i = 0
            while i + 1 < items.count {
                if let key = items[i].text(line), let value = items[i + 1].uint32(line) {
                    out[key.uppercased()] = value
                }
                i += 2
            }
        }
        return out
    }

    // MARK: - FETCH

    /// Reads `* 12 FETCH (UID 345 FLAGS (\Seen) ... BODY[] {1234})`.
    ///
    /// The items are key/value pairs in whatever order the server likes, so
    /// this walks pairwise rather than by position. An unrecognised item is
    /// skipped along with its value: a server extension we have never heard of
    /// must not cost the user the message.
    static func parseFetch(_ untagged: [IMAPResponseLine]) -> [IMAPFetchResult] {
        var out: [IMAPFetchResult] = []

        for line in untagged {
            let tokens = tokenize(line)
            guard let keyword = Array(tokens.prefix(3)).firstIndex(where: {
                $0.atomText?.uppercased() == "FETCH"
            }) else { continue }
            guard let items = tokens.dropFirst(keyword + 1).first(where: { $0.isList })?.listItems
            else { continue }

            var result = IMAPFetchResult()
            var i = 0
            while i < items.count {
                guard let key = items[i].atomText?.uppercased() else {
                    i += 1
                    continue
                }
                let value: IMAPToken? = i + 1 < items.count ? items[i + 1] : nil

                switch key {
                case "UID":
                    result.uid = value?.uint32(line) ?? result.uid
                case "FLAGS":
                    if let list = value?.listItems { result.flags = list.compactMap { $0.text(line) } }
                case "INTERNALDATE":
                    if let text = value?.text(line) { result.internalDate = parseInternalDate(text) }
                case "RFC822.SIZE":
                    result.size = value?.int(line) ?? result.size
                case "ENVELOPE":
                    if let list = value?.listItems { result.envelope = parseEnvelope(list, line) }
                case "X-GM-THRID":
                    result.threadID = value?.text(line)
                case "X-GM-MSGID":
                    result.gmailMessageID = value?.uint64(line)
                case "X-GM-LABELS":
                    // Folder names inside a label list are modified UTF-7,
                    // exactly as in LIST, so a German "Gelöscht" label needs
                    // the same decode a folder name does.
                    if let list = value?.listItems {
                        result.labels = list.compactMap { $0.text(line) }
                            .map(decodeModifiedUTF7)
                    }
                case "BODYSTRUCTURE", "BODY", "BODY.PEEK":
                    // A bare BODY with a list value is the non-extensible form
                    // of BODYSTRUCTURE; BODY[...] is a section fetch and lands
                    // in the default branch below, brackets and all.
                    if let list = value?.listItems { result.bodyStructure = parseTopLevelBody(list, line) }
                default:
                    if key.hasPrefix("BODY[") || key.hasPrefix("BODY.PEEK[") || key.hasPrefix("BINARY[")
                        || key == "RFC822" || key == "RFC822.TEXT" || key == "RFC822.HEADER" {
                        // One slot for the bytes: a fetch asking for two
                        // sections at once keeps the last. Ask for one.
                        if let data = value?.data(line) { result.body = data }
                    }
                }
                i += 2
            }

            // A FETCH that yielded nothing at all is noise, and returning it
            // would put a blank row in the message list.
            let empty = result.uid == nil && result.flags.isEmpty && result.internalDate == nil
                && result.size == nil && result.envelope == nil && result.bodyStructure == nil
                && result.body == nil
            if !empty { out.append(result) }
        }
        return out
    }

    // MARK: - ENVELOPE

    /// The ENVELOPE is a fixed 10-element list. Reading it by index with a
    /// bounds-checked accessor means a server that sends nine does not crash
    /// us; it just loses the last field.
    private static func parseEnvelope(_ items: [IMAPToken], _ line: IMAPResponseLine) -> IMAPEnvelope {
        func at(_ index: Int) -> IMAPToken? { index < items.count ? items[index] : nil }

        var envelope = IMAPEnvelope()
        if let raw = at(0)?.text(line) { envelope.date = parseHeaderDate(raw) }
        if let raw = at(1)?.text(line) { envelope.subject = decodeHeaderText(raw) }
        envelope.from    = parseAddresses(at(2), line)
        envelope.sender  = parseAddresses(at(3), line)
        envelope.replyTo = parseAddresses(at(4), line)
        envelope.to      = parseAddresses(at(5), line)
        envelope.cc      = parseAddresses(at(6), line)
        envelope.bcc     = parseAddresses(at(7), line)
        // Both message ids keep their angle brackets, which is the form the
        // wire uses and the form a References header has to be rebuilt in.
        if let raw = at(8)?.text(line)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            envelope.inReplyTo = raw
        }
        if let raw = at(9)?.text(line)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            envelope.messageID = raw
        }
        return envelope
    }

    /// An address list is a list of 4-element lists: name, source route,
    /// mailbox, host.
    private static func parseAddresses(_ token: IMAPToken?, _ line: IMAPResponseLine) -> [MailAddress] {
        guard let entries = token?.listItems else { return [] }
        var out: [MailAddress] = []

        for entry in entries {
            guard let fields = entry.listItems, fields.count >= 4 else { continue }
            // Field 1 is the obsolete RFC 822 source route. Nothing sends it
            // and nothing would know what to do with it.
            guard let mailbox = fields[2].text(line), let host = fields[3].text(line),
                  !mailbox.isEmpty, !host.isEmpty else {
                // A NIL host marks the start of an RFC 2822 group ("friends:")
                // and an all-NIL entry marks its end. Neither is deliverable.
                continue
            }
            var name = fields[0].text(line).map { decodeHeaderText($0) }
            if name?.isEmpty == true { name = nil }
            out.append(MailAddress(name: name, mailbox: mailbox, host: host))
        }
        return out
    }

    /// Every RFC 2047 decode in this file funnels through here, so if
    /// `MIMEDecoder.decodeWord` turns out to take or return something else
    /// there is exactly one line to fix.
    private static func decodeHeaderText(_ raw: String) -> String {
        // A long subject arrives as a literal complete with its folding CRLFs.
        // Flattening them first lets the decoder see two adjacent encoded words
        // instead of one word and a line break.
        let unfolded = raw
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return MIMEDecoder.decodeWord(unfolded)
    }

    // MARK: - Dates

    /// INTERNALDATE: `"19-Sep-2026 10:11:12 +0100"`, with the day space-padded
    /// to two characters when it is a single digit.
    static func parseInternalDate(_ raw: String) -> Date? {
        parseDate(raw, formatters: IMAPParserDates.internalDate + IMAPParserDates.headerDate)
    }

    /// The ENVELOPE date is an RFC 2822 header value, and headers in the wild
    /// are inventive. Try the shapes that actually occur, then give up and
    /// return nil — a message with an unparseable date must still be listed.
    static func parseHeaderDate(_ raw: String) -> Date? {
        parseDate(raw, formatters: IMAPParserDates.headerDate + IMAPParserDates.internalDate)
    }

    private static func parseDate(_ raw: String, formatters: [DateFormatter]) -> Date? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // "Fri, 19 Sep 2026 10:11:12 +0100 (BST)" — the trailing comment is
        // legal RFC 2822 and defeats every format string.
        if text.hasSuffix(")"), let open = text.lastIndex(of: "(") {
            text = String(text[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Collapse runs of whitespace: "Mon,  1 Jan" is common and DateFormatter
        // will not match a doubled space.
        text = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")

        for formatter in formatters {
            if let date = formatter.date(from: text) { return repairTwoDigitYear(date) }
        }
        return nil
    }

    /// RFC 2822 §4.3 says a two-digit year of 50 and up means 19xx and
    /// anything below it means 20xx. This has to be applied after parsing
    /// rather than by finding the year in the string, because `DateFormatter`
    /// matches "99" against a "yyyy" pattern without complaint and hands back
    /// the year 99 — old mail would then sort below everything and display as
    /// being from antiquity.
    private static func repairTwoDigitYear(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let year = calendar.component(.year, from: date)
        guard year < 100 else { return date }
        return calendar.date(byAdding: .year, value: year >= 50 ? 1900 : 2000, to: date) ?? date
    }

    // MARK: - BODYSTRUCTURE

    /// Entry point for a whole message's body structure.
    private static func parseTopLevelBody(_ items: [IMAPToken], _ line: IMAPResponseLine) -> MIMEPart {
        // A top-level multipart is not addressable in its own right: giving it
        // an empty path means a caller that fetches `BODY[\(part.section)]`
        // asks for `BODY[]`, the entire message, which is exactly right. Its
        // children then number from 1 with no prefix.
        let multipart = items.first?.isList == true
        return parseBodyStructure(items, line, path: multipart ? "" : "1")
    }

    /// Recursively turns one body list into a `MIMEPart`, numbering sections
    /// the way IMAP does so any part can later be fetched on its own.
    ///
    /// The two shapes are told apart by the first element: a multipart begins
    /// with its children, a single part begins with its type string.
    ///
    /// `depth` is a hard stop, not a nicety. One message built with a couple of
    /// thousand nested multiparts is enough to run this off the end of the
    /// stack, and because a mailbox listing fetches BODYSTRUCTURE for every
    /// message, a single such message would crash the app on every refresh
    /// until someone else deleted it.
    private static func parseBodyStructure(_ items: [IMAPToken],
                                           _ line: IMAPResponseLine,
                                           path: String,
                                           depth: Int = 0) -> MIMEPart {
        func at(_ index: Int) -> IMAPToken? { index >= 0 && index < items.count ? items[index] : nil }

        var part = MIMEPart()
        part.section = path

        if items.first?.isList == true {
            part.type = "multipart"
            var index = 0
            var childNumber = 1
            while index < items.count, let child = items[index].listItems {
                // Past the cap the children are skipped but still counted, so
                // the subtype and disposition that follow them are read from
                // the right slots and the part is still shown.
                if depth < Self.maxBodyDepth {
                    let childPath = path.isEmpty ? "\(childNumber)" : "\(path).\(childNumber)"
                    part.children.append(parseBodyStructure(child, line, path: childPath,
                                                            depth: depth + 1))
                }
                childNumber += 1
                index += 1
            }
            // Children first, then the subtype, then (BODYSTRUCTURE only) the
            // parameter list and disposition.
            part.subtype = at(index)?.text(line)?.lowercased() ?? "mixed"
            index += 1
            // A server that omits the multipart parameter list would otherwise
            // have its disposition read as parameters and thrown away.
            if index < items.count, looksLikeDisposition(items[index], line, requireKeyword: true) {
                applyExtensionDisposition(items, from: index, line, to: &part)
            } else {
                part.parameters = parseParameters(at(index), line)
                applyExtensionDisposition(items, from: index + 1, line, to: &part)
            }
            return part
        }

        // The struct's own defaults are text/plain, and that is the right guess
        // for a truncated part: the reader sees something rather than an
        // undownloadable binary blob.
        part.type = at(0)?.text(line)?.lowercased() ?? "text"
        part.subtype = at(1)?.text(line)?.lowercased() ?? "plain"
        part.parameters = parseParameters(at(2), line)
        part.id = at(3)?.text(line)
        part.description = at(4)?.text(line).map { decodeHeaderText($0) }
        part.encoding = at(5)?.text(line)?.lowercased() ?? "7bit"
        part.size = at(6)?.int(line)

        var next = 7
        if part.type == "text" {
            part.lines = at(next)?.int(line)
            next += 1
        } else if part.type == "message", part.subtype == "rfc822" {
            next += 1   // The embedded message's ENVELOPE; the tree does not carry it.
            if let inner = at(next)?.listItems, depth < Self.maxBodyDepth {
                // An embedded message's parts hang off this one's number: part
                // 3 being a message/rfc822 makes its first part 3.1.
                let innerIsMultipart = inner.first?.isList == true
                let innerPath = innerIsMultipart ? path : (path.isEmpty ? "1" : "\(path).1")
                part.children.append(parseBodyStructure(inner, line, path: innerPath,
                                                        depth: depth + 1))
            }
            next += 1
            part.lines = at(next)?.int(line)
            next += 1
        }

        // Extension data, sent for BODYSTRUCTURE and absent for BODY. Reading
        // past the end is harmless: the scan simply finds nothing.
        applyExtensionDisposition(items, from: next + 1, line, to: &part)   // next is the MD5 slot
        return part
    }

    /// Finds the content-disposition among a part's trailing extension fields.
    ///
    /// Its position is fixed by the grammar, but servers genuinely do add and
    /// omit trailing fields, and a disposition read one slot out is how an
    /// attachment loses its filename and stops being offered to the user. So
    /// the canonical slot is tried first and then the rest of the tail is
    /// searched for something that is unmistakably a disposition. Demanding
    /// the keyword during that search is what stops a `("en" "de")` language
    /// list being adopted as a disposition called "en".
    private static func applyExtensionDisposition(_ items: [IMAPToken],
                                                  from start: Int,
                                                  _ line: IMAPResponseLine,
                                                  to part: inout MIMEPart) {
        guard start >= 0 else { return }
        if start < items.count, looksLikeDisposition(items[start], line, requireKeyword: false) {
            applyDisposition(items[start], line, to: &part)
            return
        }
        var index = start + 1
        while index < items.count {
            if looksLikeDisposition(items[index], line, requireKeyword: true) {
                applyDisposition(items[index], line, to: &part)
                return
            }
            index += 1
        }
    }

    /// `("attachment" ("filename" "invoice.pdf"))` or `("inline" NIL)`. Away
    /// from the canonical slot only the three dispositions that actually occur
    /// are believed; at it, the shape is enough.
    private static func looksLikeDisposition(_ token: IMAPToken,
                                             _ line: IMAPResponseLine,
                                             requireKeyword: Bool) -> Bool {
        guard let fields = token.listItems, let head = fields.first?.text(line), !head.isEmpty
        else { return false }
        switch head.lowercased() {
        case "inline", "attachment", "form-data": return true
        default: break
        }
        guard !requireKeyword else { return false }
        return fields.count == 2 && (fields[1].isList || fields[1].isNil)
    }

    private static func applyDisposition(_ token: IMAPToken,
                                         _ line: IMAPResponseLine,
                                         to part: inout MIMEPart) {
        guard let fields = token.listItems, let name = fields.first?.text(line), !name.isEmpty
        else { return }
        part.disposition = name.lowercased()
        if fields.count > 1 {
            part.dispositionParameters = parseParameters(fields[1], line)
        }
    }

    /// A flat key/value list: `("charset" "utf-8" "name" "x.pdf")`. Keys are
    /// lowercased because `CHARSET`, `charset` and `Charset` are all in use.
    private static func parseParameters(_ token: IMAPToken?,
                                        _ line: IMAPResponseLine) -> [String: String] {
        guard let items = token?.listItems else { return [:] }
        var pairs: [(String, String)] = []
        var i = 0
        while i + 1 < items.count {
            // A non-string in either slot means this was not a parameter list
            // (a language list, say). Skipping the pair beats inventing one.
            if let key = items[i].text(line), let value = items[i + 1].text(line) {
                pairs.append((key.lowercased(), value))
            }
            i += 2
        }
        return normalizeParameters(pairs)
    }

    /// Folds RFC 2231 split and extended parameters back into plain values, so
    /// a long attachment name sent as `filename*0*`/`filename*1` shows up as a
    /// filename instead of three unusable keys.
    ///
    /// Knowingly simplified: the segments are joined and then decoded once,
    /// rather than decoded per-segment. Mixing encoded and unencoded segments
    /// under one name is legal and essentially never happens; doing it this way
    /// keeps the code short enough to be obviously correct.
    private static func normalizeParameters(_ pairs: [(String, String)]) -> [String: String] {
        var simple: [String: String] = [:]
        var segments: [String: [(index: Int, value: String)]] = [:]
        var wasEncoded: Set<String> = []

        for (key, value) in pairs {
            guard let star = key.firstIndex(of: "*") else {
                simple[key] = maybeDecodeWord(value)
                continue
            }
            let base = String(key[..<star])
            guard !base.isEmpty else { continue }
            let suffix = String(key[key.index(after: star)...])

            if suffix.isEmpty || suffix == "*" {
                // "filename*": a single extended value, charset and all.
                segments[base, default: []].append((0, value))
                wasEncoded.insert(base)
            } else {
                let encoded = suffix.hasSuffix("*")
                let number = Int(encoded ? String(suffix.dropLast()) : suffix) ?? 0
                segments[base, default: []].append((number, value))
                if encoded { wasEncoded.insert(base) }
            }
        }

        for (base, parts) in segments {
            let joined = parts.sorted { $0.index < $1.index }.map(\.value).joined()
            // An explicit plain value wins over a reconstructed one.
            guard simple[base] == nil else { continue }
            simple[base] = wasEncoded.contains(base) ? decodeRFC2231(joined) : maybeDecodeWord(joined)
        }
        return simple
    }

    /// `utf-8''Rechnung%20M%C3%A4rz.pdf` -> `Rechnung März.pdf`.
    private static func decodeRFC2231(_ value: String) -> String {
        var charset = ""
        var encoded = value
        let parts = value.components(separatedBy: "'")
        if parts.count >= 3 {
            charset = parts[0]
            encoded = parts.dropFirst(2).joined(separator: "'")
        }

        let source = Array(encoded.utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(source.count)
        var i = 0
        while i < source.count {
            if source[i] == 0x25, i + 2 < source.count,
               let high = hexDigit(source[i + 1]), let low = hexDigit(source[i + 2]) {
                bytes.append(high << 4 | low)
                i += 3
            } else {
                bytes.append(source[i])
                i += 1
            }
        }

        let data = Data(bytes)
        let encoding: String.Encoding
        switch charset.lowercased() {
        case "utf-8", "utf8":                       encoding = .utf8
        case "iso-8859-1", "latin1", "iso8859-1":   encoding = .isoLatin1
        case "us-ascii", "ascii":                   encoding = .ascii
        case "windows-1252", "cp1252":              encoding = .windowsCP1252
        default:                                    encoding = .utf8
        }
        // Latin-1 as the fallback because it cannot fail, so a mislabelled
        // charset yields mojibake rather than an empty filename.
        return String(data: data, encoding: encoding)
            ?? String(data: data, encoding: .isoLatin1)
            ?? encoded
    }

    private static func hexDigit(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: return byte - 0x30            // 0-9
        case 0x41...0x46: return byte - 0x41 + 10       // A-F
        case 0x61...0x66: return byte - 0x61 + 10       // a-f
        default:          return nil
        }
    }

    /// Filenames are supposed to use RFC 2231, but plenty of mailers put an
    /// RFC 2047 encoded word in the parameter instead. Only strings that look
    /// like one are touched, so a plain value is returned byte for byte.
    private static func maybeDecodeWord(_ value: String) -> String {
        guard value.contains("=?"), value.contains("?=") else { return value }
        return MIMEDecoder.decodeWord(value)
    }
}

// MARK: - Token accessors

private extension IMAPToken {

    var atomText: String? {
        if case .atom(let text) = self { return text }
        return nil
    }

    var listItems: [IMAPToken]? {
        if case .list(let items) = self { return items }
        return nil
    }

    var isList: Bool { listItems != nil }

    var isNil: Bool {
        if case .nilValue = self { return true }
        return false
    }

    /// Atoms, quoted strings and literals all flatten to text; lists and NIL
    /// have none, which is how "absent" stays distinguishable from "empty".
    func text(_ line: IMAPResponseLine) -> String? {
        switch self {
        case .atom(let value), .quoted(let value): return value
        case .literal(let index):                  return line.literalString(at: index)
        case .list, .nilValue:                     return nil
        }
    }

    /// Raw bytes, for a BODY[...] that is not text at all.
    func data(_ line: IMAPResponseLine) -> Data? {
        switch self {
        case .literal(let index):
            guard index >= 0, index < line.literals.count else { return nil }
            return line.literals[index]
        case .atom(let value), .quoted(let value):
            return Data(value.utf8)
        case .list, .nilValue:
            return nil
        }
    }

    func int(_ line: IMAPResponseLine) -> Int? {
        text(line).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    func uint32(_ line: IMAPResponseLine) -> UInt32? {
        text(line).flatMap { UInt32($0.trimmingCharacters(in: .whitespaces)) }
    }

    func uint64(_ line: IMAPResponseLine) -> UInt64? {
        text(line).flatMap { UInt64($0.trimmingCharacters(in: .whitespaces)) }
    }
}

// MARK: - Date formatters

/// Built once and reused. A `DateFormatter` costs roughly a hundred
/// microseconds to construct, which is invisible for one message and very
/// visible when a mailbox of five thousand arrives at once.
fileprivate enum IMAPParserDates {

    /// `en_US_POSIX` is not optional decoration. With the device locale, "Sep"
    /// does not match on a phone set to German and every date silently becomes
    /// nil; with a non-Gregorian calendar the year is wrong instead.
    private static func make(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        // Only used when the string carries no zone of its own.
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    /// RFC 3501 date-time. The single-digit variant is there because the day is
    /// space-padded on the wire and we trim before parsing.
    static let internalDate: [DateFormatter] = [
        make("dd-MMM-yyyy HH:mm:ss Z"),
        make("d-MMM-yyyy HH:mm:ss Z"),
        make("d-MMM-yyyy HH:mm:ss"),
        make("d-MMM-yyyy"),
    ]

    /// RFC 2822 and its obsolete forms: optional weekday, optional seconds,
    /// numeric or named zone, two-digit years from very old mail.
    static let headerDate: [DateFormatter] = [
        make("EEE, d MMM yyyy HH:mm:ss Z"),
        make("d MMM yyyy HH:mm:ss Z"),
        make("EEE, d MMM yyyy HH:mm Z"),
        make("d MMM yyyy HH:mm Z"),
        make("EEE, d MMM yyyy HH:mm:ss zzz"),
        make("d MMM yyyy HH:mm:ss zzz"),
        make("EEE, d MMM yy HH:mm:ss Z"),
        make("d MMM yy HH:mm:ss Z"),
        make("yyyy-MM-dd'T'HH:mm:ssZ"),
    ]
}
