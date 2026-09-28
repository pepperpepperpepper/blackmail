import Foundation

/// Submission over implicit TLS on port 465, which is all this app ever needs
/// to do: hand one finished message to Gmail and stop.
///
/// There is deliberately no long-lived session. SMTP has no useful state to
/// keep warm between messages, and a socket held open across a network change
/// - the phone moving from wifi to cellular, or simply sleeping - fails later
/// in ways that look like "the mail vanished" rather than like a dropped
/// connection. One `send` is one connection, opened, used and closed.
///
/// The caller supplies the message already serialised: this type does not
/// build MIME, does not add headers and does not know what a `Draft` is. It
/// owns exactly the conversation.
actor SMTPClient {

    private let account: MailAccount
    private let makeTransport: MailTransportFactory

    /// Recipients this server refused while it accepted others.
    ///
    /// Partial delivery is a real state and the interface does not yet
    /// represent it: if three people are addressed and one address is
    /// mistyped, the mail genuinely goes to the other two and `send` returns
    /// normally, because throwing would tell the user his message failed when
    /// it did not. The rejected list is recorded here so that whoever builds
    /// the "sent to 2 of 3" banner has the data waiting, instead of it being
    /// swallowed at the socket.
    private(set) var rejectedRecipients: [String] = []

    /// A reply that runs longer than this is a server that has lost the plot.
    /// The cap is what stops a stream of unterminated continuation lines
    /// reading forever.
    private static let maxReplyLines = 256

    init(account: MailAccount, transport: @escaping MailTransportFactory) {
        self.account = account
        self.makeTransport = transport
    }

    #if canImport(Network)
    /// The app's own: the real TLS stack.
    init(account: MailAccount) {
        self.init(account: account, transport: TLSConnection.factory)
    }
    #endif

    // MARK: - The one public operation

    /// Runs the whole conversation and closes the connection.
    ///
    /// Throws `MailError.cannotConnect` if the socket never came up,
    /// `MailError.passwordNeedsUpdating` if the credentials were refused, and
    /// `MailError.notSent` for everything else. Raw server text never escapes
    /// this file; a 90-year-old reading "550 5.7.1 Our system has detected an
    /// unusual rate of unsolicited mail" learns only that he has done
    /// something wrong, which he has not.
    func send(_ raw: Data, from: String, to recipients: [String], password: String) async throws {
        rejectedRecipients = []

        let envelopeFrom = Self.envelopeAddress(from)
        let envelopeTo = recipients.map(Self.envelopeAddress).filter { !$0.isEmpty }
        // Nobody to send to is a failure we can report without touching the
        // network: MAIL FROM with no RCPT is a syntax error at the server and
        // a confusing one to map back.
        guard !envelopeTo.isEmpty else { throw MailError.notSent }

        CaptureProbe.beginSession()
        Diagnostics.log(.note,
            "ENVELOPE from=\(envelopeFrom) rcpt=\(envelopeTo.count) "
            + "host=\(account.smtpHost):\(account.smtpPort)")

        let connection = makeTransport(account.smtpHost, account.smtpPort)
        // `close()` is isolated to the connection actor and `defer` cannot
        // await, so the unstructured task is how every exit path - return,
        // throw, or cancellation - still lets go of the socket.
        //
        // This is armed *before* the connect attempt, not after it. A failed
        // `open()` leaves the underlying NWConnection started and never
        // cancelled - it sits in .waiting retrying the route forever, holding
        // its handler and its queue - so a man tapping Send with no signal
        // would strand one of them per attempt.
        defer { Task { await connection.close() } }

        do {
            try await connection.open()
        } catch {
            // Nothing has been written yet, so this is the one failure that is
            // honestly "can't reach the server" rather than "your mail did not
            // go out".
            throw MailError.cannotConnect
        }

        do {
            let greeting = try await readReply(connection)
            // 220 and nothing else. A 554 greeting means the server has
            // already decided not to talk to us.
            guard greeting.code == 220 else {
                throw SMTPClientError.rejected(code: greeting.code, text: greeting.text)
            }

            let capabilities = try await handshake(connection)
            try await authenticate(connection, capabilities: capabilities, password: password)
            try await transmit(connection,
                               raw: raw,
                               from: envelopeFrom,
                               to: envelopeTo,
                               capabilities: capabilities)

            // Polite shutdown. The 221 is read so the server sees a clean end
            // to the session, but its content cannot change what already
            // happened, so a failure here is not the user's problem.
            try? await connection.writeLine("QUIT")
            _ = try? await readReply(connection)
            CaptureProbe.dumpTranscript("ok")     // B-034 instrumentation
        } catch {
            CaptureProbe.dumpTranscript("fail")   // B-034 instrumentation
            // Best effort QUIT on the way out, and deliberately no read: if
            // the failure was the server going away, waiting for a reply that
            // is never coming would stall for the full read timeout before we
            // could show the error.
            try? await connection.writeLine("QUIT")
            throw Self.userFacing(error)
        }
    }

    // MARK: - Conversation steps

    /// EHLO, with the multiline reply parsed into the extensions we care
    /// about.
    private func handshake(_ connection: any MailTransport) async throws -> SMTPClientCapabilities {
        let name = Self.ehloName(for: account)
        Diagnostics.log(.sent, "EHLO \(name)")
        try await connection.writeLine("EHLO \(name)")
        let reply = try await readReply(connection)
        if reply.isPositive { return SMTPClientCapabilities(ehlo: reply) }

        // A server that refuses EHLO is either pre-ESMTP or badly proxied.
        // HELO keeps the mail moving; it only costs us the extension list,
        // and the AUTH code below already copes with not being told anything.
        Diagnostics.log(.sent, "HELO \(name)")
        try await connection.writeLine("HELO \(name)")
        let fallback = try await readReply(connection)
        guard fallback.isPositive else {
            throw SMTPClientError.rejected(code: fallback.code, text: fallback.text)
        }
        return SMTPClientCapabilities()
    }

    private func authenticate(_ connection: any MailTransport,
                              capabilities: SMTPClientCapabilities,
                              password: String) async throws {
        let mechanisms = capabilities.authMechanisms
        // An empty advertised list is a hint we failed to read, not proof that
        // authentication is unavailable - the HELO path above produces one
        // every time. Trying anyway costs one round trip; refusing to try
        // guarantees the mail does not go.
        let plainAllowed = mechanisms.isEmpty || mechanisms.contains("PLAIN")
        let loginAllowed = mechanisms.isEmpty || mechanisms.contains("LOGIN")

        if plainAllowed {
            do {
                try await authenticatePlain(connection, password: password)
                return
            } catch let error as SMTPClientError {
                // A refused password is final. AUTH LOGIN would send the same
                // secret and get the same answer, and a second wrong attempt
                // counts against Google's lockout. Only a mechanism-level
                // refusal (504, 502, 538…) is worth retrying differently.
                if case .authRejected = error { throw error }
                guard loginAllowed else { throw error }
            }
        }

        guard loginAllowed else {
            throw SMTPClientError.rejected(code: 0, text: "no usable AUTH mechanism advertised")
        }
        try await authenticateLogin(connection, password: password)
    }

    /// One base64 blob of `\0user\0pass`, sent with the command.
    private func authenticatePlain(_ connection: any MailTransport, password: String) async throws {
        var credential = Data([0])
        credential.append(contentsOf: Array(account.username.utf8))
        credential.append(0)
        credential.append(contentsOf: Array(password.utf8))
        let encoded = credential.base64EncodedString()

        Diagnostics.log(.sent, "AUTH PLAIN <credential withheld>")
        try await connection.writeLine("AUTH PLAIN \(encoded)")
        var reply = try await readReply(connection)
        // Some servers ignore the initial-response form and challenge anyway.
        // A 334 here means "send it again on its own line", not a refusal.
        if reply.code == 334 {
            Diagnostics.log(.sent, "<credential withheld>")
            try await connection.writeLine(encoded)
            reply = try await readReply(connection)
        }
        guard reply.isPositive else { throw Self.authFailure(reply) }
    }

    /// Username then password, each base64, each after its own 334 challenge.
    private func authenticateLogin(_ connection: any MailTransport, password: String) async throws {
        Diagnostics.log(.sent, "AUTH LOGIN")
        try await connection.writeLine("AUTH LOGIN")
        var reply = try await readReply(connection)
        guard reply.code == 334 else { throw Self.authFailure(reply) }

        Diagnostics.log(.sent, "<username, base64>")
        try await connection.writeLine(Data(account.username.utf8).base64EncodedString())
        reply = try await readReply(connection)
        guard reply.code == 334 else { throw Self.authFailure(reply) }

        Diagnostics.log(.sent, "<credential withheld>")
        try await connection.writeLine(Data(password.utf8).base64EncodedString())
        reply = try await readReply(connection)
        guard reply.isPositive else { throw Self.authFailure(reply) }
    }

    /// MAIL FROM / RCPT TO / DATA, and the message itself.
    private func transmit(_ connection: any MailTransport,
                          raw: Data,
                          from: String,
                          to recipients: [String],
                          capabilities: SMTPClientCapabilities) async throws {
        // BODY=8BITMIME only when the server said it could take it. The
        // composer is responsible for encoding a body that needs it
        // (quoted-printable or base64); nothing here re-encodes the bytes it
        // was handed, because silently rewriting a message is how signatures
        // and attachments get corrupted.
        // Refuse here rather than after the upload. Without this the bytes
        // go up the wire in full — a minute or more on a domestic connection
        // — before the server answers 552, so the failure costs the wait
        // twice: once to discover it and once on the retry it invites.
        if let limit = capabilities.maximumMessageBytes, raw.count > limit {
            Diagnostics.log(.note,
                "refusing locally: \(raw.count) bytes exceeds the server's SIZE \(limit)")
            throw SMTPClientError.tooLarge
        }

        var mailFrom = "MAIL FROM:<\(from)>"
        if capabilities.supports8BitMIME { mailFrom += " BODY=8BITMIME" }
        // Declaring the size lets a server that advertised no SIZE, or one
        // whose real limit is lower than advertised, refuse before DATA
        // rather than after. Costs nothing when it is accepted.
        if capabilities.maximumMessageBytes != nil { mailFrom += " SIZE=\(raw.count)" }
        Diagnostics.log(.sent, mailFrom)
        try await connection.writeLine(mailFrom)
        let fromReply = try await readReply(connection)
        guard fromReply.isPositive else {
            throw SMTPClientError.rejected(code: fromReply.code, text: fromReply.text)
        }

        var accepted = 0
        for recipient in recipients {
            Diagnostics.log(.sent, "RCPT TO:<\(recipient)>")
            try await connection.writeLine("RCPT TO:<\(recipient)>")
            let reply = try await readReply(connection)
            if reply.isPositive {
                accepted += 1
            } else {
                // 4xx here is "try later" and 5xx is "never", but the app has
                // no retry queue, so both mean the same thing to this address
                // right now: it does not get the message, and the others still
                // do. See `rejectedRecipients`.
                rejectedRecipients.append(recipient)
            }
        }
        guard accepted > 0 else {
            throw SMTPClientError.rejected(code: 0, text: "every recipient refused")
        }

        Diagnostics.log(.sent, "DATA")
        try await connection.writeLine("DATA")
        let dataReply = try await readReply(connection)
        guard dataReply.code == 354 else {
            throw SMTPClientError.rejected(code: dataReply.code, text: dataReply.text)
        }

        var payload = Self.dotStuffed(raw)
        // The terminator is a bare "." on its own line, so the message must be
        // sitting at the start of a line before we write it.
        if !payload.hasCRLFSuffix { payload.append(contentsOf: [0x0D, 0x0A]) }
        payload.append(contentsOf: [0x2E, 0x0D, 0x0A])
        Diagnostics.log(.note, "WIRE-PAYLOAD bytes=\(payload.count) raw=\(raw.count)")
        try await connection.write(payload)

        let final = try await readReply(connection)
        // The reply code as a bare number: reading protocol replies out of
        // screenshots is testimony, not evidence (B-033).
        Diagnostics.log(.note, "DATA-REPLY-CODE \(final.code)")
        guard final.isPositive else {
            // The server took every recipient and then threw the message away
            // - size, spam scoring, a rejected header. Nothing was delivered.
            throw SMTPClientError.rejected(code: final.code, text: final.text)
        }
    }

    // MARK: - Reading replies

    /// One complete reply, however many lines it spans.
    ///
    /// The continuation rule is the whole trick: `250-SIZE` has more coming,
    /// `250 SIZE` is the last line. Reading a multiline reply as if it were
    /// single-line leaves the leftovers in the buffer and every subsequent
    /// command reads the previous command's answer, which presents as the
    /// session mysteriously succeeding one step behind itself.
    private func readReply(_ connection: any MailTransport) async throws -> SMTPClientReply {
        var lines: [String] = []
        var code = 0
        var sawCode = false

        for _ in 0..<Self.maxReplyLines {
            let line = try await connection.readLine()
            Diagnostics.log(.received, line)
            let parsed = SMTPClientReply.parse(line)
            if let parsedCode = parsed.code {
                code = parsedCode
                sawCode = true
            } else if !sawCode {
                // A first line with no status code at all is not SMTP. Give up
                // rather than guess, so the caller reports a clean failure.
                throw SMTPClientError.malformedReply
            }
            lines.append(parsed.text)
            if !parsed.isContinuation {
                return SMTPClientReply(code: code, lines: lines)
            }
        }
        throw SMTPClientError.malformedReply
    }

    // MARK: - Helpers

    /// What we call ourselves in EHLO.
    ///
    /// The sender's own domain is used because it is a real resolvable name we
    /// are associated with; some MTAs reject an obviously invented one. Gmail
    /// does not care either way, and "localhost" is the honest fallback when
    /// the address is malformed enough to have no domain.
    private static func ehloName(for account: MailAccount) -> String {
        let domain = account.address
            .split(separator: "@", omittingEmptySubsequences: true)
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let usable = domain.contains(".")
            && !domain.contains(" ")
            && domain.unicodeScalars.allSatisfy { $0.isASCII && $0.value > 0x20 }
        return usable ? domain : "localhost"
    }

    /// Reduces `Jane Smith <jane@example.com>` to `jane@example.com`, and
    /// strips anything that could break out of the command line.
    ///
    /// Dropping control characters is not tidiness. A recipient carrying a
    /// newline would let whatever produced it inject its own SMTP commands
    /// into this session, and recipients arrive from a text field the user
    /// typed into.
    ///
    /// The order of the two steps matters and is not obvious. Cutting at the
    /// first line break has to happen *before* the angle brackets are
    /// unwrapped: `you@here\r\nRCPT TO:<them@there>` is one recipient with
    /// rubbish stapled to it, and unwrapping first would find the last pair of
    /// brackets and quietly send the mail to `them@there` instead. Stripping
    /// the newline alone stops the injection; taking the first line is what
    /// keeps the address the one that was meant.
    private static func envelopeAddress(_ value: String) -> String {
        let firstLine = value.prefix { !$0.isNewline }
        var address = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = address.lastIndex(of: "<"),
           let close = address.lastIndex(of: ">"),
           open < close {
            address = String(address[address.index(after: open)..<close])
        }
        address = address.trimmingCharacters(in: .whitespacesAndNewlines)

        var scalars = String.UnicodeScalarView()
        for scalar in address.unicodeScalars
        where scalar.value > 0x20 && scalar.value != 0x7F && scalar != "<" && scalar != ">" {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// Normalises line endings to CRLF and stuffs a leading dot.
    ///
    /// Both halves matter. A line consisting of just "." ends the DATA phase,
    /// so an unstuffed message that happens to contain one is delivered
    /// truncated at that point and nothing anywhere reports an error - the
    /// recipient simply gets half a letter. And SMTP counts line ends as CRLF
    /// only, so a body built with bare newlines can leave the terminator
    /// unrecognised and hang the transaction until the server times out.
    private static func dotStuffed(_ raw: Data) -> Data {
        let cr: UInt8 = 0x0D, lf: UInt8 = 0x0A, dot: UInt8 = 0x2E
        var out = Data()
        out.reserveCapacity(raw.count + (raw.count / 64) + 16)

        var atLineStart = true
        var index = raw.startIndex
        while index < raw.endIndex {
            let byte = raw[index]
            if byte == cr || byte == lf {
                out.append(cr)
                out.append(lf)
                // Swallow the LF of a CRLF pair so the pair does not count as
                // two line breaks and double-space the whole message.
                let next = raw.index(after: index)
                if byte == cr, next < raw.endIndex, raw[next] == lf {
                    index = next
                }
                atLineStart = true
            } else {
                if atLineStart && byte == dot { out.append(dot) }
                out.append(byte)
                atLineStart = false
            }
            index = raw.index(after: index)
        }
        return out
    }

    /// 535 is "username and password not accepted". 534 is Gmail's
    /// "application-specific password required", which is the same instruction
    /// to the user in different words, so both land on the message that tells
    /// him to fix the password in Settings rather than on a generic failure he
    /// can do nothing about.
    private static func authFailure(_ reply: SMTPClientReply) -> SMTPClientError {
        if reply.code == 535 || reply.code == 534 { return .authRejected }
        return .rejected(code: reply.code, text: reply.text)
    }

    /// The single point where protocol detail is discarded and the user gets
    /// one of the sentences the product spec allows.
    private static func userFacing(_ error: Error) -> MailError {
        if let mailError = error as? MailError { return mailError }
        if let wire = error as? SMTPClientError {
            switch wire {
            case .authRejected:
                return .passwordNeedsUpdating
            case .tooLarge:
                return .messageTooLarge
            case .rejected(let code, _):
                // The server's own verdicts on size, for the cases the local
                // check cannot catch: a server that advertised no SIZE at
                // all, or one whose real limit is below what it advertised.
                // 552 is "message too large" and 523 its enhanced sibling;
                // 554 is generic, so it is NOT claimed here.
                if code == 552 || code == 523 { return .messageTooLarge }
            default:
                break
            }
        }
        // Everything else - a refused code, a dropped socket mid-transaction,
        // a read timeout - reduces to the same fact for him: the message did
        // not go.
        return .notSent
    }
}

// MARK: - Wire types

/// One reply, already reassembled from however many lines it arrived on.
///
/// Named with the full `SMTPClient` prefix, and fileprivate, so it cannot
/// collide with anything another part of the mail stack defines.
fileprivate struct SMTPClientReply {
    let code: Int
    /// The text of each line with its code and separator removed, kept for a
    /// diagnostics log. It is never shown to the user.
    let lines: [String]

    var text: String { lines.joined(separator: " ") }

    /// 2xx succeeded, 4xx is temporary, 5xx is permanent. This client has no
    /// retry queue, so only success is acted on; the distinction survives in
    /// the code for whoever adds one.
    var isPositive: Bool { (200..<300).contains(code) }
    var isTemporary: Bool { (400..<500).contains(code) }
    var isPermanent: Bool { code >= 500 }

    /// Splits `250-AUTH PLAIN LOGIN` into its code, its "more to come" flag
    /// and its text. A line that does not begin with three digits yields a nil
    /// code, which the reader treats as a continuation of the reply in
    /// progress rather than as a hard error - a server padding its banner is
    /// not a reason to refuse to send mail.
    static func parse(_ line: String) -> (code: Int?, isContinuation: Bool, text: String) {
        let characters = Array(line)
        guard characters.count >= 3,
              let code = Int(String(characters[0..<3])),
              characters[0..<3].allSatisfy({ $0.isASCII && $0.isNumber })
        else {
            return (nil, true, line)
        }
        guard characters.count > 3 else { return (code, false, "") }
        let separator = characters[3]
        let text = characters.count > 4 ? String(characters[4...]) : ""
        return (code, separator == "-", text)
    }
}

/// What EHLO told us. Only the two extensions this client can act on are kept.
fileprivate struct SMTPClientCapabilities {
    var authMechanisms: Set<String> = []
    var supports8BitMIME = false
    /// RFC 1870 SIZE: the largest message the server will accept, in bytes,
    /// or nil when it did not say.
    ///
    /// Worth reading rather than hardcoding "25 MB". Gmail advertises
    /// `SIZE 35882577` — 34.2 MiB, which is the 25 MB attachment limit after
    /// base64 inflates it by a third — and that is the number that actually
    /// governs. Reading it also means the app is right on a server that is
    /// not Gmail, and stays right if Google changes it.
    var maximumMessageBytes: Int?

    init() {}

    init(ehlo reply: SMTPClientReply) {
        // The first line of an EHLO reply is the server's own greeting, not an
        // extension; a server called "AUTHORITY.example.com" would otherwise
        // read as advertising AUTH.
        for line in reply.lines.dropFirst() {
            // `AUTH=LOGIN PLAIN` is the old Exchange spelling of
            // `AUTH LOGIN PLAIN`, and there are still proxies that emit it.
            let fields = line
                .replacingOccurrences(of: "=", with: " ")
                .split(separator: " ")
                .map { $0.uppercased() }
            guard let keyword = fields.first else { continue }
            switch keyword {
            case "AUTH":     authMechanisms.formUnion(fields.dropFirst())
            case "8BITMIME": supports8BitMIME = true
            case "SIZE":
                // `SIZE 0` means "no stated limit", per RFC 1870, and must
                // not be read as "refuse everything".
                if let value = fields.dropFirst().first.flatMap({ Int($0) }), value > 0 {
                    maximumMessageBytes = value
                }
            default:         continue
            }
        }
    }
}

fileprivate enum SMTPClientError: Error {
    /// A reply we cannot proceed from. The text is carried for diagnostics and
    /// is dropped before anything reaches the interface.
    case rejected(code: Int, text: String)
    /// Credentials refused; the one failure with its own user-facing sentence.
    case authRejected
    /// The far end is not speaking SMTP.
    case malformedReply
    /// The message is larger than the server will accept.
    case tooLarge
}

fileprivate extension Data {
    /// Whether the buffer already ends at a line boundary, which decides
    /// whether the DATA terminator needs its own CRLF in front of it.
    var hasCRLFSuffix: Bool {
        count >= 2 && suffix(2) == Data([0x0D, 0x0A])
    }
}
