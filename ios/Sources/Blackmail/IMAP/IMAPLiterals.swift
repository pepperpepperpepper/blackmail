import Foundation

/// How the server will take a literal from this client.
///
/// A literal is IMAP's way to send a string a quoted string cannot carry:
/// `{7}`, a line break, and the 7 bytes. RFC 3501 has the client wait for
/// the server's "+" before the bytes, a synchronising literal. RFC 7888's
/// LITERAL+ lets it send `{7+}` and the bytes straight on, any size, and
/// LITERAL- the same up to 4,096 bytes, a larger one synchronising as
/// before. Gmail advertises LITERAL-, after LOGIN.
enum IMAPLiteralForm: Equatable, Sendable {
    /// `{n+}`, of any size.
    case plus
    /// `{n+}` up to `minusLimit` bytes, `{n}` and the wait past it.
    case minus
    /// `{n}`, each sent after the server's "+": neither capability, or
    /// none known. RFC 3501's, which every server takes.
    case synchronising

    /// The largest literal LITERAL- lets a client send without the wait.
    static let minusLimit = 4_096

    /// From the capabilities the server advertised after LOGIN. An empty
    /// set, a CAPABILITY that could not be read, is the form every server
    /// takes.
    init(capabilities: Set<String>) {
        if capabilities.contains("LITERAL+") {
            self = .plus
        } else if capabilities.contains("LITERAL-") {
            self = .minus
        } else {
            self = .synchronising
        }
    }

    /// Whether a literal of `count` bytes goes without the wait.
    func sendsAtOnce(_ count: Int) -> Bool {
        switch self {
        case .plus:          return true
        case .minus:         return count <= Self.minusLimit
        case .synchronising: return false
        }
    }
}

/// A command whose 8-bit strings go as literals (B-105).
///
/// RFC 3501 keeps a quoted string to 7-bit text, and Gmail holds to it: a
/// SEARCH with `BODY "Müller"` in it was answered BAD, with CHARSET UTF-8
/// and without, and so was one with the curly ’ Smart Punctuation types in
/// "don’t" (measured read-only on the test account, 2026-10-22). As a
/// literal, `BODY {7+}`, a line break, and the 7 bytes of Müller, with
/// CHARSET UTF-8, it found the letter, and so did all five fields so, each
/// word of several so, beside the ASCII ones in their quoted strings.
///
/// So every quoted string with a scalar above 127 in it, read as the
/// quoted string it is, its `\\` and `\"` taken back to `\` and `"`, goes
/// as a literal of its UTF-8 bytes: `{n+}` where the server lets it go at
/// once (`IMAPLiteralForm`), or else `{n}`, with the rest of the command
/// after the server's "+". Everything else is sent as it was given, byte
/// for byte: a 7-bit quoted string stays the quoted string it was, so a
/// search of ASCII words goes exactly as it went before.
///
/// Made after `IMAPClient.sanitizedCommandText` has taken every line break
/// out of the text the words came in, so the only line breaks in the
/// command are the literals' own. A quoted string with no end is left as
/// it is, for the server to refuse, as it was.
struct IMAPWireCommand: Equatable, Sendable {
    /// The command as far as its first `{n}`, or the whole command when
    /// it has none: without the tag, and without the line break after it.
    /// A `{n+}` literal is inside it, its line break and its bytes with it.
    let line: String
    /// What goes after each "+" the server sends, in order: a `{n}`
    /// literal's bytes and the command after them, as far as the next
    /// `{n}` or to its end. Each is written with a line break after it.
    /// None when nothing waits for a "+".
    let continuations: [Data]
    /// The command for the connection log, on one line: each literal as
    /// its `{n+}` or `{n}`, a space, and its text, where the wire has a
    /// line break. The words are in the log as they were in their quoted
    /// strings, no more and no fewer: the log of a search has always had
    /// what he searched for in it (`Diagnostics`).
    let logged: String

    init(_ command: String, literals form: IMAPLiteralForm) {
        let scalars = Array(command.unicodeScalars)
        // The command as far as the next `{n}`, and the ones before it.
        var segment = String.UnicodeScalarView()
        var segments: [String] = []
        // Each `{n}` literal's bytes, which go after the server's "+".
        var waiting: [Data] = []
        var logged = String.UnicodeScalarView()

        var at = 0
        while at < scalars.count {
            guard scalars[at] == "\"" else {
                segment.append(scalars[at])
                logged.append(scalars[at])
                at += 1
                continue
            }
            // A quoted string: what it says, and where it ends.
            var value = String.UnicodeScalarView()
            var end = at + 1
            var closed = false
            while end < scalars.count {
                let scalar = scalars[end]
                if scalar == "\"" {
                    closed = true
                    break
                }
                if scalar == "\\", end + 1 < scalars.count {
                    end += 1
                }
                value.append(scalars[end])
                end += 1
            }
            let quoted = String(String.UnicodeScalarView(scalars[at..<min(end + 1, scalars.count)]))
            at = end + 1
            guard closed, value.contains(where: { $0.value > 127 }) else {
                segment.append(contentsOf: quoted.unicodeScalars)
                logged.append(contentsOf: quoted.unicodeScalars)
                continue
            }
            let text = String(value)
            let bytes = Data(text.utf8)
            if form.sendsAtOnce(bytes.count) {
                let announced = "{\(bytes.count)+}"
                segment.append(contentsOf: (announced + "\r\n").unicodeScalars)
                segment.append(contentsOf: value)
                logged.append(contentsOf: (announced + " ").unicodeScalars)
            } else {
                let announced = "{\(bytes.count)}"
                segment.append(contentsOf: announced.unicodeScalars)
                segments.append(String(segment))
                segment = String.UnicodeScalarView()
                waiting.append(bytes)
                logged.append(contentsOf: (announced + " ").unicodeScalars)
            }
            logged.append(contentsOf: value)
        }
        segments.append(String(segment))

        line = segments[0]
        continuations = zip(waiting, segments.dropFirst()).map { bytes, after in
            bytes + Data(after.utf8)
        }
        self.logged = String(logged)
    }
}
