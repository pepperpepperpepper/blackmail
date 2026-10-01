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

    /// Runs the conversation up to the server's verdict on the letter, and
    /// returns with it.
    ///
    /// Throws `MailError.cannotConnect` if the socket never came up,
    /// `MailError.connectionLost` if it went, or stopped answering, before
    /// the server's verdict on the letter, `MailError.passwordNeedsUpdating`
    /// if the credentials were refused, `MailError.sendingSignInRefused` if
    /// the sign-in was refused for another reason, `MailError.messageTooLarge`
    /// for a letter over the server's size, `MailError.refusedForNow` for a 4yz
    /// reply, the server's "not now", and `MailError.notSent` for every
    /// other refusal the server made. Raw server text never escapes this
    /// file; a 90-year-old reading "550 5.7.1 Our system has detected an
    /// unusual rate of unsolicited mail" learns only that he has done
    /// something wrong, which he has not.
    ///
    /// The first two and "not now" say nothing against the letter going
    /// later as it is, and the rest say something about it or the account,
    /// which is what decides whether a letter from the composer waits in the
    /// Outbox or stays in the sheet (`Outbox.waits(after:)`). All three used
    /// to be `notSent`.
    ///
    /// Returns at the 250 after DATA, not after QUIT. That 250 is the server
    /// taking the letter over (RFC 5321 §6.1), and from then on nothing
    /// it says or fails to say can undo it. `send` used to go on to write
    /// QUIT, wait for the 221 and write the transcript file before
    /// returning, all while the composer sat there with the letter already
    /// gone: a round trip at least, and the whole read deadline on a line
    /// that died after the 250. The QUIT, the close and the transcript now
    /// follow on their own (`letGo`), and none of them can make a delivered
    /// letter an error. RFC 5321 §4.1.1.10 says a client SHOULD wait for the
    /// 221; this one does not, because the only thing the wait decides is
    /// how long he is kept looking at a letter that has already gone.
    ///
    /// `progress` hears how much of the letter itself has been handed to the
    /// network, from the DATA write; see `UploadProgress`.
    ///
    /// `beforeData` is called once the server has taken the envelope and
    /// before DATA is written, and the letter waits for it. Up to then
    /// nothing the server has can become a letter; from then on a
    /// connection that goes before the 250 leaves no way to tell from here
    /// whether it did. A letter in the Outbox is written down as on its way
    /// at this point, so that one cut off afterwards is looked for before it
    /// is sent again (`LocalDrafts.send`). If it throws, DATA is never
    /// written, the session is ended, and its error is what `send` throws.
    func send(_ raw: Data, from: String, to recipients: [String], password: String,
              progress: UploadProgress? = nil,
              beforeData: (@Sendable () async throws -> Void)? = nil) async throws {
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

        do {
            try await connection.open()
        } catch {
            // Closed even though it never opened. A failed `open()` leaves
            // the underlying NWConnection started and never cancelled - it
            // sits in .waiting retrying the route forever, holding its
            // handler and its queue - so a man tapping Send with no signal
            // would strand one of them per attempt.
            //
            // Nothing has been written yet, so this is the one failure that is
            // honestly "can't reach the server" rather than "your mail did not
            // go out".
            letGo(connection, quitting: false, transcript: nil)
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
                               capabilities: capabilities,
                               progress: progress,
                               beforeData: beforeData)
        } catch {
            // Best effort QUIT on the way out, and deliberately no read: if
            // the failure was the server going away, waiting for a reply that
            // is never coming would stall for the full read timeout before we
            // could show the error.
            letGo(connection, quitting: true, transcript: "fail")
            if let withheld = error as? Withheld { throw withheld.reason }
            throw Self.userFacing(error)
        }

        // Delivered. The 221 is not read: see above.
        letGo(connection, quitting: true, transcript: "ok")
    }

    /// Signs in and says goodbye, sending no letter: whether the submission
    /// server takes `password` for this account. Setup and Settings ask it
    /// after IMAP has taken the password, because IMAP alone cannot tell
    /// (B-033): Gmail's IMAP opens the mailbox an app password belongs to
    /// whatever account the LOGIN names, while SMTP holds the two together
    /// and refuses the pair. A password made while signed in to Google as
    /// someone else read that account's mail and failed every letter.
    ///
    /// Throws as `send` does, up to its AUTH: `MailError.cannotConnect` for a
    /// server not reached, `passwordNeedsUpdating` for 535,
    /// `sendingSignInRefused` for 534, and the rest as a letter's would be.
    /// EHLO, AUTH and QUIT are all that go: no MAIL FROM, so nothing is sent
    /// to anyone. No transcript file is written, as none is for a read.
    func checkSignIn(password: String) async throws {
        Diagnostics.log(.note, "SIGN-IN CHECK host=\(account.smtpHost):\(account.smtpPort)")
        let connection = makeTransport(account.smtpHost, account.smtpPort)
        do {
            try await connection.open()
        } catch {
            letGo(connection, quitting: false, transcript: nil)
            throw MailError.cannotConnect
        }
        do {
            let greeting = try await readReply(connection)
            guard greeting.code == 220 else {
                throw SMTPClientError.rejected(code: greeting.code, text: greeting.text)
            }
            let capabilities = try await handshake(connection)
            try await authenticate(connection, capabilities: capabilities, password: password)
        } catch {
            letGo(connection, quitting: true, transcript: nil)
            throw Self.userFacing(error)
        }
        letGo(connection, quitting: true, transcript: nil)
    }

    /// The last connection being let go of, for a test to wait on.
    private(set) var lettingGo: Task<Void, Never>?

    /// Ends the session without anyone waiting on it: QUIT, if there is a
    /// session to end, then the close, then the transcript (B-034).
    ///
    /// The transcript file is written on every exit that got past the
    /// connect, as it was, but after `send` has returned rather than on the
    /// way to returning: formatting the connection log and writing it out
    /// is work he used to wait for. A file named `-ok` now means the
    /// letter's 250 was read; the 221 is not in it.
    ///
    /// Unstructured, so the caller's cancellation does not reach it and a
    /// socket is let go of whichever way `send` ended; and not isolated to
    /// this actor, so a transcript being written does not hold up the next
    /// letter. Every step is allowed to fail. The QUIT is written before
    /// the close, not beside it, so that it goes at all; a close that came
    /// first would take it with the connection.
    private func letGo(_ connection: any MailTransport, quitting: Bool, transcript tag: String?) {
        let session = CaptureProbe.session
        lettingGo = Task.detached {
            if quitting { try? await connection.writeLine("QUIT") }
            await connection.close()
            if let tag { CaptureProbe.dumpTranscript(tag, session: session) }
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
                // refusal (504, 502, 538…) is worth retrying differently. A
                // 4yz is neither: the server said "not now", and would say
                // it to LOGIN too. Nor is a sign-in refused for the
                // account's sake, which LOGIN would be refused the same.
                if case .authRejected = error { throw error }
                if case .signInRefused = error { throw error }
                if case .rejected(let code, _) = error, Self.isTransient(code) { throw error }
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
                          capabilities: SMTPClientCapabilities,
                          progress: UploadProgress?,
                          beforeData: (@Sendable () async throws -> Void)?) async throws {
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
        var refusals: [Int] = []
        for recipient in recipients {
            Diagnostics.log(.sent, "RCPT TO:<\(recipient)>")
            try await connection.writeLine("RCPT TO:<\(recipient)>")
            let reply = try await readReply(connection)
            if reply.isPositive {
                accepted += 1
            } else {
                // 4xx here is "try later" and 5xx is "never", but the letter
                // goes once, to whoever was taken, so both mean the same
                // thing to this address: it does not get the message, and
                // the others still do. See `rejectedRecipients`.
                rejectedRecipients.append(recipient)
                refusals.append(reply.code)
            }
        }
        guard accepted > 0 else {
            // Every one of them "not now" is the letter's "not now": it can
            // go later, to all of them, from the Outbox.
            let code = refusals.allSatisfy(Self.isTransient) ? refusals.first ?? 0 : 0
            throw SMTPClientError.rejected(code: code, text: "every recipient refused")
        }

        do {
            try await beforeData?()
        } catch {
            throw Withheld(reason: error)
        }

        Diagnostics.log(.sent, "DATA")
        try await connection.writeLine("DATA")
        let dataReply = try await readReply(connection)
        guard dataReply.code == 354 else {
            throw SMTPClientError.rejected(code: dataReply.code, text: dataReply.text)
        }

        let payload = Self.dataPayload(raw)
        Diagnostics.log(.note, "WIRE-PAYLOAD bytes=\(payload.count) raw=\(raw.count)")
        try await connection.write(payload, progress: progress)

        // Waited for on the long bound: see `ReplyWait.afterUpload`. The
        // write returning means the stack has the bytes, not that Gmail does.
        let final = try await readReply(connection, .afterUpload)
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
    private func readReply(_ connection: any MailTransport,
                           _ wait: ReplyWait = .ordinary) async throws -> SMTPClientReply {
        var lines: [String] = []
        var code = 0
        var sawCode = false

        for _ in 0..<Self.maxReplyLines {
            let line = try await connection.readLine(wait)
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

    /// What goes after DATA's 354: the letter with its line endings made
    /// CRLF and a leading dot stuffed, then the terminator.
    ///
    /// Both halves of the stuffing matter. A line consisting of just "."
    /// ends the DATA phase, so an unstuffed message that happens to contain
    /// one is delivered truncated at that point and nothing anywhere reports
    /// an error - the recipient simply gets half a letter. And SMTP counts
    /// line ends as CRLF only, so a body built with bare newlines can leave
    /// the terminator unrecognised and hang the transaction until the server
    /// times out. The terminator is a bare "." on its own line, so the
    /// message must be sitting at the start of a line before it goes.
    ///
    /// Read through a raw buffer into a byte array, for the reason
    /// `MIMEDecoder.decodeBase64` gives. This used to walk the letter a byte
    /// at a time through `Data`, which has no `append` for one byte: each
    /// went through the generic `replaceSubrange`, an opaque call into
    /// Foundation per byte, and each read cost a call too. A five-photo
    /// letter spent about 3.5 s here before a byte of it was sent, most of
    /// the local work of a send. It now goes a line at a time: everything up
    /// to the next CR or LF is copied in one piece, and only the line breaks
    /// and a dot at the start of a line are looked at on their own, which on
    /// a letter of base64 lines is one step for every 76 bytes. The
    /// terminator goes into the same array, with room kept for it, because
    /// appending it to the finished `Data` copied the whole letter again.
    ///
    /// `Data(out)` at the end is one copy of the letter, and for that moment
    /// it is in memory three times. Building the `Data` itself a line at a
    /// time, to save the copy, was four times slower on a photo letter here
    /// and fourteen on the worst case, each append a call into Foundation.
    static func dataPayload(_ raw: Data) -> Data {
        let cr: UInt8 = 0x0D, lf: UInt8 = 0x0A, dot: UInt8 = 0x2E
        var out: [UInt8] = []
        out.reserveCapacity(raw.count + (raw.count / 64) + 16)

        raw.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let input = buffer.bindMemory(to: UInt8.self)
            let count = input.count
            // Always at the start of a line here.
            var start = 0
            while start < count {
                if input[start] == dot { out.append(dot) }
                var end = start
                while end < count, input[end] != cr, input[end] != lf { end += 1 }
                out.append(contentsOf: UnsafeBufferPointer(rebasing: input[start..<end]))
                guard end < count else { break }
                // Any line break, CR, LF or the pair, goes out as CRLF. The
                // pair is taken whole so it does not count as two line
                // breaks and double-space the whole message.
                out.append(cr)
                out.append(lf)
                let pair = input[end] == cr && end + 1 < count && input[end + 1] == lf
                start = end + (pair ? 2 : 1)
            }
        }

        let endsALine = out.count >= 2 && out[out.count - 2] == cr && out[out.count - 1] == lf
        if !endsALine { out += [cr, lf] }
        out += [dot, cr, lf]
        return Data(out)
    }

    /// 535 is "username and password not accepted": the password. 534 is
    /// Gmail's for a sign-in it wants made some other way first, "5.7.14
    /// Please log in via your web browser" or "5.7.9 Application-specific
    /// password required". It used to land on the password's message too,
    /// which sent a helper off to make app password after app password
    /// while Google waited for a sign-in on the web; it is a refused
    /// sign-in of its own now (`MailError.sendingSignInRefused`), which keeps
    /// every rule a refused password has against trying again.
    private static func authFailure(_ reply: SMTPClientReply) -> SMTPClientError {
        if reply.code == 535 { return .authRejected }
        if reply.code == 534 { return .signInRefused }
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
            case .signInRefused:
                // Its text stays here, as every reply's does: the
                // connection log has it.
                return .sendingSignInRefused
            case .tooLarge:
                return .messageTooLarge
            case .rejected(let code, _):
                // The server's own verdicts on size, for the cases the local
                // check cannot catch: a server that advertised no SIZE at
                // all, or one whose real limit is below what it advertised.
                // 552 is "message too large" and 523 its enhanced sibling;
                // 554 is generic, so it is NOT claimed here.
                if code == 552 || code == 523 { return .messageTooLarge }
                // RFC 5321's transient negative completion, at any step: a
                // greeting of 421, a 454 to AUTH, a 451 after DATA. The
                // server has said it did not take the letter and may later.
                if isTransient(code) { return .refusedForNow }
            default:
                break
            }
        }
        // A dropped socket mid-transaction or a read that timed out: the
        // server never gave its verdict, and the letter may go later as it
        // is. Said as "Message was not sent." all the same.
        if error is MailTransportError { return .connectionLost }
        // Everything else is a refusal with a code, or an answer that was
        // not SMTP: the server was reached and would not take this letter,
        // or would not take it from this account.
        return .notSent
    }

    /// A 4yz reply (RFC 5321 §4.2.1): the command was not accepted, and
    /// the same request may succeed later.
    private static func isTransient(_ code: Int) -> Bool {
        (400..<500).contains(code)
    }

    /// `beforeData` threw, and the letter was kept back: its error, as it
    /// was, for `send` to throw.
    private struct Withheld: Error {
        let reason: Error
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

    /// 2xx succeeded; anything else is a refusal, carried in
    /// `SMTPClientError.rejected` with its code, which is where a 4yz is
    /// told from a 5xx (`SMTPClient.isTransient`).
    var isPositive: Bool { (200..<300).contains(code) }

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
    /// 534: the sign-in refused for a reason that is not the password.
    case signInRefused
    /// The far end is not speaking SMTP.
    case malformedReply
    /// The message is larger than the server will accept.
    case tooLarge
}
