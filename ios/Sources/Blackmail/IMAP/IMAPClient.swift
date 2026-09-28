import Foundation

/// The IMAP command layer: tags, literals, capabilities, and the dozen
/// commands this client actually issues.
///
/// Everything above this line is domain code that has never heard of IMAP;
/// everything below it is a `MailTransport` (`TLSConnection` on the device,
/// a scripted server in the host tests), which has never heard of anything
/// but bytes. This type owns the protocol and nothing else — it does not
/// interpret a response beyond routing it, because parsing lives in
/// `IMAPParser` where it can be tested without a server.
///
/// An actor for the same reason `TLSConnection` is one: IMAP is a single
/// full-duplex stream with tagged commands, and two commands in flight at once
/// on one socket is how you end up reading somebody else's response.
///
/// Actor isolation alone does *not* buy that, which is the trap this type most
/// has to survive: Swift actors are reentrant, so the instant a command
/// suspends on a socket write another task may enter and write its own. The
/// exchange gate below is what actually serialises a command with its reply.
///
/// Nothing here throws an error carrying protocol text. Every failure becomes
/// one of the four `MailError` cases, because `PRODUCT_SPEC.md` fixes the four
/// sentences the user is allowed to see and "BAD Command Argument Error. 11"
/// is not one of them.
actor IMAPClient {

    // MARK: - Limits

    /// A literal bigger than this is a broken or hostile server, not mail.
    /// Gmail caps a message at 25 MB and base64 inflates that to roughly 34 MB,
    /// so nothing legitimate comes close; without the cap, one mistyped
    /// `{999999999}` would have us buffer a gigabyte into the phone before
    /// anything failed.
    private static let maximumLiteralBytes = 64 * 1024 * 1024

    /// Keeps a `UID FETCH` command line well under the 8 KB a server is
    /// entitled to reject. A mailbox of 20,000 messages is one FETCH per
    /// several thousand UIDs once runs are collapsed into ranges, not one
    /// command per message.
    private static let maximumUIDSetLength = 7_000

    private static let baseSummaryItems = "UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODYSTRUCTURE"

    /// The FETCH items for a list row, plus Gmail's labels when the server
    /// admits to having them.
    ///
    /// Gated STRICTLY on the advertised capability, and deliberately NOT
    /// with the `capabilities.isEmpty || …` optimism that `move()` uses. The
    /// two cases are not alike: an unsupported MOVE is refused on its own and
    /// falls back, whereas an unrecognised item inside a FETCH makes the
    /// server reject the WHOLE command — which here would empty the message
    /// list rather than merely lose the labels.
    ///
    /// X-GM-LABELS rides the FETCH the list already issues, so knowing which
    /// folders a message belongs to costs no extra round trip.
    private var summaryItems: String {
        capabilities.contains("X-GM-EXT-1")
            ? "(\(Self.baseSummaryItems) X-GM-LABELS X-GM-THRID)"
            : "(\(Self.baseSummaryItems))"
    }

    // MARK: - State

    private let account: MailAccount
    /// Called once per connection, because a dropped socket is replaced
    /// rather than reopened.
    private let makeTransport: MailTransportFactory
    private var connection: (any MailTransport)?
    private var connected = false
    private var tagCounter = 0

    /// Capabilities as advertised *after* login. They change across
    /// authentication — a server may not mention MOVE or UIDPLUS until it
    /// knows who you are — so the post-LOGIN set is the one worth keeping.
    private var capabilities: Set<String> = []

    /// The last mailbox SELECTed and what the server said about it. Exposed
    /// read-only because `uidValidity` is the repository's cue to throw away
    /// every cached UID for that mailbox.
    private(set) var selectedMailbox: String?
    private(set) var mailboxState: IMAPMailboxState?

    /// True while one command owns the socket. See `beginExchange()`.
    private var exchangeInProgress = false
    private var exchangeWaiters: [CheckedContinuation<Void, Never>] = []

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

    var isConnected: Bool { connected }

    // MARK: - Session

    func connect(password: String) async throws {
        // Held across the whole handshake, not just each command. Opening the
        // socket suspends, so without this two tasks that both decide they are
        // disconnected would each open a connection and the second would
        // overwrite (and leak) the first.
        await beginExchange()
        defer { endExchange() }

        guard !connected else { return }

        let conn = makeTransport(account.imapHost, account.imapPort)
        do {
            try await conn.open()
        } catch {
            await conn.close()
            throw MailError.cannotConnect
        }
        connection = conn
        connected = true

        do {
            // The greeting is an unsolicited untagged line that arrives before
            // any tag exists, so it cannot go through the normal command loop.
            let greeting = try await readResponse()
            let upperGreeting = greeting.text.uppercased()
            if upperGreeting.hasPrefix("* BYE") {
                // A server that greets with BYE is refusing the connection
                // outright (blocked IP, maintenance). There is nothing to log
                // in to.
                throw MailError.cannotConnect
            }
            // PREAUTH means the transport already authenticated us. Gmail never
            // does this, but sending LOGIN to a pre-authenticated session is an
            // error, so honour it rather than assume.
            let preAuthenticated = upperGreeting.hasPrefix("* PREAUTH")

            // No CAPABILITY before LOGIN. It used to be asked for here, and
            // the answer was overwritten a few lines further down without
            // anything having read it: the pre-login list is the wrong one to
            // make MOVE and UIDPLUS decisions from, so it was a round trip on
            // every connect bought for nothing. The one thing a pre-login list
            // could be for is LOGINDISABLED, and this client has never
            // honoured it. Over implicit TLS a server has no reason to
            // advertise it, and one that did would refuse the LOGIN, which
            // ends in the same "Can't connect" a check here would have given.
            if preAuthenticated {
                // Already past login, so a list in the greeting is the
                // post-login one.
                let advertised = Self.capabilities(in: greeting)
                if advertised.isEmpty {
                    capabilities = try await requestCapabilities()
                } else {
                    capabilities = advertised
                }
            } else {
                // Both arguments are quoted. An app password is sixteen
                // lowercase letters today, but a password containing a quote or
                // a backslash sent unquoted fails in a way that is
                // indistinguishable from a wrong password, and the user would
                // be told to change a password that was correct all along.
                let result = try await performCommand(
                    "LOGIN \(Self.quoted(account.username)) \(Self.quoted(password))")

                guard result.status == .ok else {
                    let code = IMAPParser.responseCode(result.detail)?.uppercased()
                    if result.status == .no, code == "AUTHENTICATIONFAILED" {
                        throw MailError.passwordNeedsUpdating
                    }
                    throw MailError.cannotConnect
                }

                // Gmail returns the post-login capability list inside the
                // tagged OK, which saves a round trip. A server that sends it
                // as an untagged `* CAPABILITY` line ahead of the OK instead
                // saves the same round trip, so that is read too. Only a
                // server that does neither gets asked.
                // Spelled out rather than as a ternary: a `try` inside one
                // branch of `?:` covers only that branch, which the compiler
                // warns about and a reader has to stop and check.
                let advertised = Self.capabilities(in: result)
                if advertised.isEmpty {
                    capabilities = try await requestCapabilities()
                } else {
                    capabilities = advertised
                }
            }
        } catch {
            await teardown()
            throw Self.userFacing(error)
        }
    }

    func disconnect() async {
        await beginExchange()
        defer { endExchange() }

        if connected {
            // Best effort. A server that has already gone away does not get to
            // turn closing a connection into an error the user sees.
            _ = try? await performCommand("LOGOUT")
        }
        await teardown()
    }

    func noop() async throws {
        let result = try await sendCommand("NOOP")
        guard result.status == .ok else { throw MailError.cannotConnect }
    }

    // MARK: - Mailboxes

    func listMailboxes() async throws -> [IMAPMailboxListing] {
        // `LIST "" "*"` rather than `"%"`: Gmail's real folders are children of
        // "[Gmail]" and a single-level list would hide Sent, Trash and All Mail.
        let result = try await sendCommand("LIST \"\" \"*\"")
        guard result.status == .ok else { throw MailError.cannotConnect }
        return IMAPParser.parseList(result.untagged)
    }

    @discardableResult
    func select(_ mailbox: String, readOnly: Bool = false) async throws -> IMAPMailboxState {
        let verb = readOnly ? "EXAMINE" : "SELECT"
        let result = try await sendCommand("\(verb) \(Self.mailboxArgument(mailbox))")
        guard result.status == .ok else {
            selectedMailbox = nil
            mailboxState = nil
            throw MailError.cannotConnect
        }

        let parsed = IMAPParser.parseSelect(result.untagged)
        // READ-ONLY normally arrives as a response code on the *tagged* OK
        // ("a003 OK [READ-ONLY] EXAMINE completed"), which the untagged-only
        // parser never sees, so it is folded back in here.
        let taggedCode = IMAPParser.responseCode(result.detail)?.uppercased()
        let isReadOnly = readOnly || taggedCode == "READ-ONLY" || (parsed?.readOnly ?? false)

        // A SELECT that succeeded but did not parse still leaves the mailbox
        // selected on the server, so returning zeros is honest and lets the
        // caller carry on and FETCH. Throwing here would turn one unparseable
        // untagged line into an empty mailbox, which is the failure mode
        // this client most has to avoid.
        let state = IMAPMailboxState(uidValidity: parsed?.uidValidity ?? 0,
                                     uidNext: parsed?.uidNext ?? 0,
                                     exists: parsed?.exists ?? 0,
                                     flags: parsed?.flags ?? [],
                                     permanentFlags: parsed?.permanentFlags ?? [],
                                     readOnly: isReadOnly)
        selectedMailbox = mailbox
        mailboxState = state
        return state
    }

    /// STATUS on a mailbox that is not selected — the only way to get an unread
    /// count for the folder list without SELECTing every folder in turn, which
    /// would be a round trip each and would disturb the selected mailbox.
    ///
    /// Not part of the required API; added because a count that fails to arrive
    /// must not cost the user his folder list, hence the empty dictionary
    /// rather than a throw.
    func status(_ mailbox: String,
                items: [String] = ["MESSAGES", "UNSEEN", "UIDNEXT", "UIDVALIDITY"]) async throws -> [String: UInt32] {
        let cleaned = items.map { $0.filter { $0.isLetter } }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return [:] }
        let result = try await sendCommand(
            "STATUS \(Self.mailboxArgument(mailbox)) (\(cleaned.joined(separator: " ")))")
        guard result.status == .ok else { return [:] }
        return IMAPParser.parseStatus(result.untagged)
    }

    // MARK: - Searching

    func searchAll() async throws -> [UInt32] {
        try await search("ALL")
    }

    func search(_ criteria: String) async throws -> [UInt32] {
        let body = Self.sanitizedCommandText(criteria).trimmingCharacters(in: .whitespacesAndNewlines)
        let query = body.isEmpty ? "ALL" : body

        // A search string with non-ASCII in it needs a CHARSET, or the server
        // is entitled to answer BAD and the user's search for "Müller" simply
        // never works.
        let needsCharset = query.unicodeScalars.contains { $0.value > 127 }
        var result = try await sendCommand(needsCharset ? "UID SEARCH CHARSET UTF-8 \(query)"
                                                        : "UID SEARCH \(query)")
        if result.status != .ok, needsCharset {
            // Some servers reject the CHARSET argument itself rather than the
            // term. One retry costs a round trip and rescues the search.
            result = try await sendCommand("UID SEARCH \(query)")
        }

        // Deliberately a throw and not an empty array: an empty result is
        // indistinguishable in the interface from "this folder has no mail",
        // and quietly showing an empty inbox is worse than saying so.
        guard result.status == .ok else { throw MailError.cannotConnect }
        return IMAPParser.parseSearch(result.untagged)
    }

    // MARK: - Fetching

    func fetchSummaries(uids: [UInt32]) async throws -> [IMAPFetchResult] {
        guard !uids.isEmpty else { return [] }

        var byUID: [UInt32: IMAPFetchResult] = [:]
        var sawFailure = false

        for chunk in Self.uidSetChunks(uids) {
            let result = try await sendCommand("UID FETCH \(chunk) \(summaryItems)")
            guard result.status == .ok else {
                // One rejected chunk must not cost the other 4,900 messages.
                sawFailure = true
                continue
            }
            for fetched in IMAPParser.parseFetch(result.untagged) {
                // A result with no UID has no stable identity, so the
                // repository could neither open it nor reconcile it on the next
                // refresh. Dropping it is the only safe thing to do with it.
                if let uid = fetched.uid { byUID[uid] = fetched }
            }
        }

        // Returned in the order asked for rather than the order the server felt
        // like: the caller hands us UIDs newest-first and expects rows back in
        // that order, and servers answer in sequence order, which is the
        // reverse.
        var ordered: [IMAPFetchResult] = []
        ordered.reserveCapacity(byUID.count)
        var emitted = Set<UInt32>()
        for uid in uids where !emitted.contains(uid) {
            if let fetched = byUID[uid] {
                ordered.append(fetched)
                emitted.insert(uid)
            }
        }

        if ordered.isEmpty, sawFailure { throw MailError.cannotConnect }
        return ordered
    }

    func fetchStructure(uid: UInt32) async throws -> IMAPFetchResult? {
        let result = try await sendCommand("UID FETCH \(uid) \(summaryItems)")
        // A NO here usually means the message has been moved or expunged by
        // another client since the list was built. That is "there is nothing to
        // show", not "the connection is broken", so it is a nil and not a throw.
        guard result.status == .ok else { return nil }
        let parsed = IMAPParser.parseFetch(result.untagged)
        return parsed.first { $0.uid == uid } ?? parsed.first
    }

    /// The first `byteCount` bytes of ONE section, for many messages at once.
    ///
    /// This is what makes list previews affordable. `BODY.PEEK[1]<0.2048>`
    /// against a whole page of UIDs is a single command and a single reply,
    /// where fetching each message's body in turn would be fifty round trips
    /// and several megabytes for two lines of grey text per row.
    ///
    /// Every caller must already know the section it wants — they differ per
    /// message, so the repository groups its page by section and calls this
    /// once per group.
    ///
    /// Returns what arrived rather than throwing on a partial failure: a
    /// preview that does not turn up costs a blank line, and losing the other
    /// forty-nine to one server complaint would be a far worse trade.
    func fetchPartialBodies(uids: [UInt32], section: String,
                            byteCount: Int) async throws -> [UInt32: Data] {
        guard !uids.isEmpty, byteCount > 0 else { return [:] }
        let path = Self.sanitizedSection(section)

        var out: [UInt32: Data] = [:]
        for chunk in Self.uidSetChunks(uids) {
            // PEEK, like every other fetch here. A plain BODY[…] would set
            // \Seen, so merely scrolling a folder would mark the page read.
            let result = try await sendCommand(
                "UID FETCH \(chunk) (UID BODY.PEEK[\(path)]<0.\(byteCount)>)")
            guard result.status == .ok else { continue }
            for fetched in IMAPParser.parseFetch(result.untagged) {
                guard let uid = fetched.uid, let body = fetched.body else { continue }
                out[uid] = body
            }
        }
        return out
    }

    func fetchBody(uid: UInt32, section: String?) async throws -> Data {
        let path = section.map { Self.sanitizedSection($0) }
        // BODY.PEEK, never BODY: a plain BODY[] sets \Seen as a side effect, so
        // merely downloading a message in the background would mark it read
        // behind the user's back. Read state is changed only by `store`, when
        // he actually opens something.
        let item = "BODY.PEEK[\(path ?? "")]"
        let result = try await sendCommand("UID FETCH \(uid) (UID \(item))")

        guard result.status == .ok else {
            throw section == nil ? MailError.cannotConnect : MailError.attachmentFailed
        }

        let parsed = IMAPParser.parseFetch(result.untagged)
        if let data = parsed.first(where: { $0.uid == uid })?.body
            ?? parsed.compactMap({ $0.body }).first {
            return data
        }

        // Whole-message fetch that came back empty: hand back no bytes rather
        // than an error, so the reader still gets the header and an empty body
        // instead of an alert. A named section that produced nothing really has
        // failed, because the caller wanted an attachment and there isn't one.
        if section == nil { return Data() }
        throw MailError.attachmentFailed
    }

    // MARK: - Mutating

    func store(uid: UInt32, flag: String, set: Bool) async throws {
        let cleaned = Self.sanitizedFlag(flag)
        guard !cleaned.isEmpty else { return }
        // .SILENT suppresses the untagged FETCH echo we would only throw away.
        let op = set ? "+FLAGS.SILENT" : "-FLAGS.SILENT"
        let result = try await sendCommand("UID STORE \(uid) \(op) (\(cleaned))")
        guard result.status == .ok else { throw MailError.cannotConnect }
    }

    func move(uid: UInt32, to mailbox: String) async throws {
        // The gate is held for the whole copy/mark/expunge sequence, not per
        // command. All three steps act on "the selected mailbox", so a SELECT
        // from another task landing in the middle would point the \Deleted flag
        // and the EXPUNGE at a different folder entirely — and the last-resort
        // plain EXPUNGE there would take every \Deleted message in it. This is
        // the one sequence in the client that can destroy mail, so it is the
        // one that must be indivisible.
        await beginExchange()
        defer { endExchange() }

        let destination = Self.mailboxArgument(mailbox)

        // An empty capability set means the CAPABILITY response could not be
        // read, not that the server is feature-free, so try the good path
        // anyway and fall back if it is refused.
        if capabilities.isEmpty || capabilities.contains("MOVE") {
            let result = try await performCommand("UID MOVE \(uid) \(destination)")
            if result.status == .ok { return }
        }

        let copied = try await performCommand("UID COPY \(uid) \(destination)")
        // The order matters enormously: if the copy failed and we deleted
        // anyway, the message is simply gone. Nothing is marked \Deleted until
        // a copy is known to exist at the far end.
        guard copied.status == .ok else { throw MailError.cannotConnect }

        let flagged = try await performCommand("UID STORE \(uid) +FLAGS.SILENT (\\Deleted)")
        guard flagged.status == .ok else { throw MailError.cannotConnect }

        // UID EXPUNGE removes exactly this message. Plain EXPUNGE removes every
        // \Deleted message in the mailbox, which would collect anything another
        // client had marked and not yet expunged — so it is the last resort,
        // used only when the targeted form is refused.
        let expunged = try await performCommand("UID EXPUNGE \(uid)")
        if expunged.status != .ok {
            _ = try await performCommand("EXPUNGE")
        }
    }

    @discardableResult
    func append(_ raw: Data, to mailbox: String,
                flags: [String]) async throws -> (validity: UInt32, uid: UInt32)? {
        guard !raw.isEmpty else { throw MailError.notSent }

        let cleanFlags = flags.map(Self.sanitizedFlag).filter { !$0.isEmpty }
        let flagPart = cleanFlags.isEmpty ? "" : " (\(cleanFlags.joined(separator: " ")))"

        // The synchronising form: announce the length, wait for "+", then send
        // the bytes. LITERAL+ would let us stream it without waiting, but a
        // non-synchronising literal that the server does not support is
        // rejected *after* we have already written the message, which desyncs
        // the stream. One extra round trip is a fair price for that not
        // happening.
        let result = try await sendCommand(
            "APPEND \(Self.mailboxArgument(mailbox))\(flagPart) {\(raw.count)}",
            continuationPayload: raw)
        guard result.status == .ok else { throw MailError.notSent }
        return IMAPAppend.uid(in: result.detail)
    }

    /// Removes one message outright, rather than moving it to Trash.
    ///
    /// For DRAFTS only, and the distinction matters now that an "All
    /// Mailboxes" search reaches the Trash: a superseded draft binned rather
    /// than deleted would surface as a search hit for every half-finished
    /// sentence he ever saved.
    ///
    /// `UID EXPUNGE` when the server has UIDPLUS, which confines the removal
    /// to the message named. Plain EXPUNGE is the fallback and is a blunter
    /// instrument — it removes everything flagged `\Deleted` in the mailbox
    /// — which is tolerable here only because nothing else in this app sets
    /// that flag outside Trash.
    func expunge(uid: UInt32) async throws {
        try await store(uid: uid, flag: "\\Deleted", set: true)
        let command = capabilities.contains("UIDPLUS") ? "UID EXPUNGE \(uid)" : "EXPUNGE"
        let result = try await sendCommand(command)
        guard result.status == .ok else { throw MailError.cannotConnect }
    }

    // MARK: - Command plumbing

    private func nextTag() -> String {
        tagCounter += 1
        return String(format: "a%03d", tagCounter)
    }

    /// Waits until no other command owns the socket, then claims it.
    ///
    /// Being an actor is not enough. `await` on this actor is a suspension
    /// point, and an actor is *reentrant*: while one task is suspended writing
    /// `a007 UID FETCH …`, the tap that marks a message read is free to enter
    /// and write `a008 UID STORE …` before the first command has read a byte.
    /// Both then read the same stream, so whichever is resumed first swallows
    /// the other's tagged completion as an untagged line — the fetch either
    /// hangs until the 30 second read timeout and reports "Can't connect", or,
    /// when both commands are FETCHes, returns the *other* request's messages.
    /// Holding this gate for a whole command/response exchange is the only
    /// thing that makes one socket safe for the several overlapping `Task`s the
    /// interface starts.
    private func beginExchange() async {
        // A loop rather than an if: a waiter that is resumed can still lose the
        // gate to a task that arrived while it was being scheduled.
        while exchangeInProgress {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                exchangeWaiters.append(c)
            }
        }
        exchangeInProgress = true
    }

    private func endExchange() {
        exchangeInProgress = false
        if !exchangeWaiters.isEmpty { exchangeWaiters.removeFirst().resume() }
    }

    /// Writes one tagged command and reads until its tagged completion, taking
    /// the exchange gate for the duration.
    private func sendCommand(_ command: String,
                             continuationPayload: Data? = nil) async throws -> IMAPCommandResult {
        await beginExchange()
        defer { endExchange() }
        return try await performCommand(command, continuationPayload: continuationPayload)
    }

    /// The command itself. The caller must already hold the exchange gate,
    /// which is why `connect` and `disconnect` — sequences of commands that
    /// must not have another command spliced into them — call this instead of
    /// `sendCommand` and take the gate once around the whole sequence.
    ///
    /// Any transport-level failure is turned into a closed connection and a
    /// `MailError`: once a read has failed mid-response the stream position is
    /// unknown, and carrying on would read the tail of one response as the head
    /// of the next.
    private func performCommand(_ command: String,
                                continuationPayload: Data? = nil) async throws -> IMAPCommandResult {
        guard connected, let conn = connection else { throw MailError.cannotConnect }
        let tag = nextTag()
        do {
            // Redaction happens inside Diagnostics.log, not here, so a future
            // call site cannot forget it. LOGIN's password is stripped there.
            Diagnostics.log(.sent, "\(tag) \(command)")
            try await conn.writeLine("\(tag) \(command)")
            return try await awaitResult(tag: tag, continuationPayload: continuationPayload)
        } catch let error as MailError {
            throw error
        } catch {
            await teardown()
            throw MailError.cannotConnect
        }
    }

    private func awaitResult(tag: String, continuationPayload: Data?) async throws -> IMAPCommandResult {
        var untagged: [IMAPResponseLine] = []
        var pending = continuationPayload

        while true {
            let line = try await readResponse()
            let text = line.text

            if text.hasPrefix("+") {
                // The server is asking for the literal it was promised. If we
                // have nothing to give it — an unexpected continuation — we
                // cannot invent bytes, and writing filler would corrupt the
                // mailbox; the read timeout turns the resulting stall into a
                // clean "Can't connect" a few seconds later.
                if let payload = pending, let conn = connection {
                    pending = nil
                    try await conn.write(payload)
                    try await conn.write(Data("\r\n".utf8))
                }
                continue
            }

            if text.hasPrefix(tag + " ") || text == tag {
                let rest = String(text.dropFirst(tag.count)).trimmingCharacters(in: .whitespaces)
                let (word, detail) = Self.splitFirstWord(rest)
                // An unrecognised completion word is treated as BAD rather than
                // assumed to be OK: pretending an unknown outcome succeeded is
                // how a failed move turns into a lost message.
                let status = IMAPStatus(rawValue: word.uppercased()) ?? .bad
                return IMAPCommandResult(status: status, detail: detail, untagged: untagged)
            }

            // Untagged, or something unrecognised. Both are kept: the parser is
            // lenient and an unexpected line is more useful to it than to us.
            untagged.append(line)
        }
    }

    /// Reads one logical response, splicing in any literals.
    ///
    /// This is the part of IMAP that catches every implementation out. A "line"
    /// is not a line: `* 12 FETCH (BODY[] {2048}` is followed by exactly 2048
    /// raw bytes — which contain CRLFs of their own and must not be read as
    /// text — and then by the rest of the line, which may itself end in another
    /// literal. The loop below keeps consuming until a line ends without one,
    /// leaving the text with a `\u{0}<index>\u{0}` marker wherever a literal
    /// stood so the tokenizer can find the bytes again.
    private func readResponse() async throws -> IMAPResponseLine {
        guard connected, let conn = connection else { throw MailError.cannotConnect }

        var text = try await conn.readLine()
        var literals: [Data] = []

        while let length = Self.trailingLiteralLength(of: text) {
            guard length <= Self.maximumLiteralBytes else {
                // We cannot skip past a literal we refuse to read, so the
                // stream is finished. Close it rather than leave a poisoned
                // connection behind for the next command.
                await teardown()
                throw MailError.cannotConnect
            }
            let data = try await conn.read(exactly: length)
            // The bytes themselves are his correspondence and never go in the
            // transcript; only their size, which is what actually helps when
            // a fetch misbehaves.
            Diagnostics.log(.received, Diagnostics.describeLiteral(byteCount: data.count))
            literals.append(data)
            text = Self.replacingTrailingLiteral(in: text, withIndex: literals.count - 1)
            text += try await conn.readLine()
        }

        Diagnostics.log(.received, text)
        return IMAPResponseLine(text: text, literals: literals)
    }

    private func teardown() async {
        if let conn = connection { await conn.close() }
        connection = nil
        connected = false
        capabilities = []
        selectedMailbox = nil
        mailboxState = nil
        // tagCounter is deliberately not reset. Tags stay unique for the life
        // of the object, so a late response from a dead socket can never be
        // matched to a command issued after a reconnect.
    }

    /// Called only from `connect`, which already holds the exchange gate.
    private func requestCapabilities() async throws -> Set<String> {
        let result = try await performCommand("CAPABILITY")
        guard result.status == .ok else { return [] }
        return Self.capabilities(in: result)
    }
}

// MARK: - Pure helpers

private extension IMAPClient {

    /// `MailError` straight through, everything else flattened to "Can't
    /// connect". A `MailTransportError` says "POSIX 54", which is true,
    /// unhelpful, and exactly the sort of thing `PRODUCT_SPEC.md` forbids
    /// reaching the user.
    static func userFacing(_ error: Error) -> MailError {
        (error as? MailError) ?? .cannotConnect
    }

    static func splitFirstWord(_ text: String) -> (String, String) {
        guard let space = text.firstIndex(of: " ") else { return (text, "") }
        let rest = text[text.index(after: space)...]
        return (String(text[..<space]), String(rest).trimmingCharacters(in: .whitespaces))
    }

    /// The `{n}` that says a literal follows, or nil.
    ///
    /// `{n+}` is a LITERAL+ non-synchronising literal, which is something a
    /// *client* sends; seeing one on the way in means we are looking at text
    /// that merely resembles a literal marker — a subject line ending in
    /// "{12+}", say — so it is left alone.
    static func trailingLiteralLength(of text: String) -> Int? {
        guard text.hasSuffix("}"), let open = text.lastIndex(of: "{") else { return nil }
        let closing = text.index(before: text.endIndex)
        guard open < closing else { return nil }
        let digits = text[text.index(after: open)..<closing]
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        // Int() rather than a manual accumulate so an absurdly long run of
        // digits overflows to nil instead of wrapping to a small count.
        return Int(digits)
    }

    static func replacingTrailingLiteral(in text: String, withIndex index: Int) -> String {
        guard let open = text.lastIndex(of: "{") else { return text }
        var head = String(text[text.startIndex..<open])
        // RFC 3516 spells a binary literal `~{n}`. We never ask for one, but if
        // a server volunteers it the stray tilde would tokenize as an atom and
        // confuse the parser, so it goes with the brace.
        if head.hasSuffix("~") { head.removeLast() }
        let marker = String(IMAPResponseLine.literalMarker)
        return head + marker + String(index) + marker
    }

    /// Capability atoms from one response line. Brackets are flattened first so
    /// that both `* CAPABILITY IMAP4rev1 MOVE` and the `[CAPABILITY …]` code
    /// inside a tagged OK go down the same path.
    static func capabilities(in line: IMAPResponseLine) -> Set<String> {
        capabilities(inText: line.text)
    }

    /// Everything one command's response said about capabilities, whether
    /// in untagged lines or in a code on its tagged completion. Empty when
    /// it said nothing, which is the caller's cue to ask.
    static func capabilities(in result: IMAPCommandResult) -> Set<String> {
        var caps = Set<String>()
        for line in result.untagged {
            caps.formUnion(capabilities(in: line))
        }
        caps.formUnion(capabilities(inText: result.detail))
        return caps
    }

    static func capabilities(inText text: String) -> Set<String> {
        guard text.uppercased().contains("CAPABILITY") else { return [] }
        let flattened = text
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
        var found = Set<String>()
        var reachedKeyword = false
        for token in IMAPParser.tokenize(IMAPResponseLine(text: flattened, literals: [])) {
            guard case .atom(let atom) = token else { continue }
            let upper = atom.uppercased()
            if !reachedKeyword {
                reachedKeyword = (upper == "CAPABILITY")
                continue
            }
            found.insert(upper)
        }
        return found
    }

    /// Collapses a UID list into `1:50,52,60:70` and splits it into command
    /// lines no server can reasonably refuse. Duplicates and ordering in the
    /// input do not matter; an IMAP sequence set is a set.
    static func uidSetChunks(_ uids: [UInt32]) -> [String] {
        let sorted = Array(Set(uids)).sorted()
        guard !sorted.isEmpty else { return [] }

        var pieces: [String] = []
        var runStart = sorted[0]
        var runEnd = sorted[0]
        for uid in sorted.dropFirst() {
            // The `runEnd < .max` guard is not paranoia: UID 4294967295 is
            // legal, and `runEnd + 1` on it traps.
            if runEnd < UInt32.max, uid == runEnd + 1 {
                runEnd = uid
                continue
            }
            pieces.append(runStart == runEnd ? "\(runStart)" : "\(runStart):\(runEnd)")
            runStart = uid
            runEnd = uid
        }
        pieces.append(runStart == runEnd ? "\(runStart)" : "\(runStart):\(runEnd)")

        var chunks: [String] = []
        var current = ""
        for piece in pieces {
            if current.isEmpty {
                current = piece
            } else if current.count + 1 + piece.count <= maximumUIDSetLength {
                current += "," + piece
            } else {
                chunks.append(current)
                current = piece
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    // MARK: Argument quoting

    /// An IMAP quoted string. Backslash and double quote are escaped; CR, LF
    /// and other control characters are dropped, because a quoted string cannot
    /// contain them at all and a name (or a password) carrying a CRLF would
    /// otherwise inject a second command into the session.
    static func quoted(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count + 2)
        for scalar in value.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F { continue }
            if scalar == "\"" || scalar == "\\" { out.append("\\") }
            out.unicodeScalars.append(scalar)
        }
        return "\"" + out + "\""
    }

    /// A mailbox name ready to go on the wire: modified UTF-7 encoded, then
    /// quoted. Gmail's own folders are `[Gmail]/Sent Mail` — a space and two
    /// brackets — so quoting is not optional even for the built-in ones.
    static func mailboxArgument(_ name: String) -> String {
        quoted(encodeMailboxName(name))
    }

    /// RFC 3501 §5.1.3 modified UTF-7. The parser hands mailbox names back
    /// decoded, so a folder the user sees as "Wichtig" or "重要" has to be
    /// re-encoded before it can be SELECTed; sending the decoded form gets a
    /// "no such mailbox" that looks like the folder vanished.
    static func encodeMailboxName(_ name: String) -> String {
        var out = ""
        var pending: [UInt16] = []

        func flushPending() {
            guard !pending.isEmpty else { return }
            var bytes: [UInt8] = []
            bytes.reserveCapacity(pending.count * 2)
            for unit in pending {
                bytes.append(UInt8(truncatingIfNeeded: unit >> 8))
                bytes.append(UInt8(truncatingIfNeeded: unit))
            }
            // Modified BASE64: '/' becomes ',' and the padding is dropped.
            var encoded = Data(bytes).base64EncodedString()
            while encoded.hasSuffix("=") { encoded.removeLast() }
            out += "&" + encoded.replacingOccurrences(of: "/", with: ",") + "-"
            pending.removeAll(keepingCapacity: true)
        }

        for scalar in name.unicodeScalars {
            if scalar == "&" {
                flushPending()
                out += "&-"
            } else if scalar.value >= 0x20, scalar.value <= 0x7E {
                flushPending()
                out.unicodeScalars.append(scalar)
            } else {
                pending.append(contentsOf: Array(String(scalar).utf16))
            }
        }
        flushPending()
        return out
    }

    /// Strips what cannot appear in a flag. A flag is an atom, so anything with
    /// a space, a bracket or a quote in it would break the parenthesised list
    /// and take the rest of the command with it.
    static func sanitizedFlag(_ flag: String) -> String {
        String(flag.unicodeScalars.filter { scalar in
            let c = Character(scalar)
            return c.isLetter || c.isNumber || c == "\\" || c == "-" || c == "_" || c == "$" || c == "*"
        }.map(Character.init))
    }

    /// A BODY[…] section path. It comes from a server-supplied BODYSTRUCTURE,
    /// so it is not trusted: only the characters IMAP section specifiers
    /// actually use survive, which keeps a hostile structure from smuggling a
    /// `]` and a second command into the FETCH.
    static func sanitizedSection(_ section: String) -> String {
        String(section.unicodeScalars.filter { scalar in
            let c = Character(scalar)
            return c.isLetter || c.isNumber || c == "." || c == "<" || c == ">"
        }.map(Character.init))
    }

    /// Removes the line terminators (and NUL, which is our literal marker) from
    /// free text that is about to be pasted into a command. Everything else,
    /// including the caller's own quoting, is left alone — search criteria are
    /// a small language and the caller composes it.
    static func sanitizedCommandText(_ text: String) -> String {
        String(text.unicodeScalars.filter { $0.value != 0x00 && $0.value != 0x0A && $0.value != 0x0D }
            .map(Character.init))
    }
}
