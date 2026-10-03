import Foundation

/// The protocol transcript, for the person supporting this over the phone.
///
/// Deliberately Foundation-only and unguarded, so `redact` is covered by the
/// host test suite. That matters more than it looks: IMAP `LOGIN` sends the
/// password as a plain argument inside the TLS session, and SMTP `AUTH` sends
/// it base64'd, so a transcript that is not redacted IS the password. This
/// file is the one place that can leak it, and a leak here would be into
/// something explicitly designed to be copied and sent to someone else.
///
/// Two rules, both enforced below rather than by convention:
///
/// 1. **No credentials.** Call sites log a placeholder, and `redact` catches
///    them if they forget. Belt and braces, because one missed call site is a
///    published password.
/// 2. **No message content.** Literals are logged as `{N bytes}`. His
///    correspondence is not diagnostic data, and a support transcript should
///    not contain a word of it. The exception is the wire itself, logged
///    as it went: a FETCH's ENVELOPE carries subjects, names and addresses
///    as quoted strings, RCPT TO the recipients' addresses, and a SEARCH
///    the words he searched for. Nothing written beside the wire may add
///    to that; a note says what happened in numbers and ids, never who
///    wrote or what about (D-016). That last part is held by a test, not
///    by anything below, and only for a listing (`KeptCopyTests`); a note
///    on any other path is kept to it by convention.
enum Diagnostics {

    enum Direction: String {
        case sent = "→", received = "←", note = "·"
    }

    struct Entry {
        let at: Date
        let direction: Direction
        let text: String
    }

    /// Ring buffer. 500 lines is a few minutes of traffic — enough to see what
    /// went wrong, bounded so a long session cannot grow without limit.
    private static let limit = 500
    private static var buffer: [Entry] = []
    private static let lock = NSLock()

    static func log(_ direction: Direction, _ text: String) {
        let entry = Entry(at: Date(), direction: direction, text: redact(text))
        lock.lock()
        defer { lock.unlock() }
        buffer.append(entry)
        if buffer.count > limit { buffer.removeFirst(buffer.count - limit) }
    }

    static var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }

    // MARK: - The app going away and coming back

    /// How many times since launch the app has gone to the background or
    /// come back to the front (`AppDelegate`). Not cleared with the log.
    ///
    /// A time measured across a change in it is not the server's: iOS
    /// suspends the app in the background, for hours if he leaves it there,
    /// and an answer that came meanwhile is read only once he is back. So
    /// `IMAPClient` writes no SLOW note for a command it changed under.
    static var awayOrBack: Int {
        presenceLock.lock()
        defer { presenceLock.unlock() }
        return presenceChanges
    }

    /// The app has gone to the background, or come back to the front.
    static func wentAwayOrCameBack() {
        presenceLock.lock()
        defer { presenceLock.unlock() }
        presenceChanges += 1
    }

    private static var presenceChanges = 0
    private static let presenceLock = NSLock()

    /// The whole transcript as text, for copying out to whoever is helping.
    static func transcript() -> String {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "HH:mm:ss.SSS"
        return entries
            .map { "\(stamp.string(from: $0.at)) \($0.direction.rawValue) \($0.text)" }
            .joined(separator: "\n")
    }

    // MARK: - Redaction

    /// Strips anything that could be a credential.
    ///
    /// This is the safety net, not the primary defence — call sites are
    /// expected to log a placeholder in the first place. It is written to
    /// over-redact: losing a diagnostic detail costs a support call, and
    /// leaking a password costs the account.
    static func redact(_ line: String) -> String {
        var out = line

        // IMAP: `a003 LOGIN user@example.com "secret"`. Keep the tag, the verb
        // and the username — all useful and none secret — and drop the rest of
        // the line, because everything after the username is the password.
        if let range = out.range(of: #"(?i)\bLOGIN\s+(\S+)\s+\S.*$"#,
                                 options: .regularExpression) {
            let matched = String(out[range])
            if let user = matched.split(separator: " ").dropFirst().first {
                out.replaceSubrange(range, with: "LOGIN \(user) <redacted>")
            } else {
                out.replaceSubrange(range, with: "LOGIN <redacted>")
            }
        }

        // SMTP: `AUTH PLAIN <base64>` / `AUTH LOGIN <base64>`.
        if let range = out.range(of: #"(?i)\bAUTH\s+(PLAIN|LOGIN)\s+\S+"#,
                                 options: .regularExpression) {
            let mechanism = out[range].contains("PLAIN") || out[range].contains("plain")
                ? "PLAIN" : "LOGIN"
            out.replaceSubrange(range, with: "AUTH \(mechanism) <redacted>")
        }

        // The AUTH LOGIN dialogue sends the username and then the password as
        // bare base64 lines with no keyword to match on. Nothing in this app's
        // normal traffic is a long bare base64 token on its own line, so
        // anything that looks like one is redacted on suspicion.
        if isBareBase64(out) { return "<redacted>" }

        return out
    }

    /// A whole line that is nothing but a long base64 token. Deliberately
    /// narrow — an IMAP response like `* OK [UIDVALIDITY 1] x` has spaces and
    /// punctuation and will not match.
    private static func isBareBase64(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count >= 16 else { return false }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        return t.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Describes a literal without reproducing it. Message bodies are his
    /// private correspondence and have no place in a support transcript.
    static func describeLiteral(byteCount: Int) -> String { "{\(byteCount) bytes}" }

    /// `* SEARCH {N uids}` for an untagged SEARCH answer, and the same for
    /// SORT, which has its shape; nil for any other line.
    ///
    /// The answer is one line with a number for every letter found: at his
    /// size, by estimate, 0.4 MB for the Inbox and one or two megabytes for
    /// Sent Mail, All Mail or a search for a common word. Kept whole, one
    /// such line was most of the 500 in the log, the connection log's
    /// screen, the one read out over the phone to whoever is helping, drew
    /// it all on the main thread, and each send's transcript carried it too.
    /// How many letters it found is what helps. What they were,
    /// `SESSION-IDENT` and the FETCHes after it say.
    ///
    /// Counted as `IMAPParser.parseSearch` reads the line: the numbers after
    /// the keyword, less a trailer such as CONDSTORE's `(MODSEQ 123)`.
    static func describeSearch(_ line: String) -> String? {
        let bytes = line.utf8
        var cursor = bytes.startIndex
        for expected in "* ".utf8 {
            guard cursor != bytes.endIndex, bytes[cursor] == expected else { return nil }
            cursor = bytes.index(after: cursor)
        }
        var keyword: [UInt8] = []
        while cursor != bytes.endIndex, bytes[cursor] != 0x20, keyword.count < 7 {
            keyword.append(bytes[cursor] & 0xDF)   // ASCII upper case
            cursor = bytes.index(after: cursor)
        }
        let name = String(decoding: keyword, as: UTF8.self)
        guard name == "SEARCH" || name == "SORT",
              cursor == bytes.endIndex || bytes[cursor] == 0x20 else { return nil }
        var count = 0
        var digits = 0
        var bracketed = 0
        func endWord() {
            if digits > 0, bracketed == 0 { count += 1 }
            digits = 0
        }
        while cursor != bytes.endIndex {
            let c = bytes[cursor]
            switch c {
            case 0x30...0x39:
                if digits >= 0 { digits += 1 }
            case 0x20:
                endWord()
            case 0x28:
                bracketed += 1
                digits = -1
            case 0x29:
                bracketed = max(0, bracketed - 1)
                digits = -1
            default:
                digits = -1
            }
            cursor = bytes.index(after: cursor)
        }
        endWord()
        return "* \(name) {\(count) uids}"
    }
}
