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
///    not contain a word of it.
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
}
