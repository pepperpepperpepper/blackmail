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
/// The same trap one level up is why this type, and not the repository,
/// owns which mailbox is selected. A UID means nothing outside the mailbox
/// it was issued in, so every UID command names the mailbox it must run in
/// and goes out in the same hold of the gate as the SELECT that opens it.
/// See `inMailbox`.
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
    /// folders a message belongs to costs no extra round trip. X-GM-MSGID
    /// rides it the same way, a number per row, for the copy of his mail
    /// kept on the iPad to be keyed on (D-016).
    private var summaryItems: String {
        capabilities.contains("X-GM-EXT-1")
            ? "(\(Self.baseSummaryItems) X-GM-LABELS X-GM-THRID X-GM-MSGID)"
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

    /// The mailbox SELECTed on this connection, and what the server said
    /// about it. Nil on a new connection and after a refused SELECT, which
    /// leaves the server with nothing selected (RFC 3501 §6.3.1), not with
    /// the mailbox that was open before. Only ever changed by a holder of
    /// the gate, so a command that checks it and then runs in the same hold
    /// runs in the mailbox it checked.
    private(set) var selectedMailbox: String?
    private(set) var mailboxState: IMAPMailboxState?

    /// When the session last asked for the selected mailbox's news and was
    /// answered: its SELECT, or a NOOP since. Set by every SELECT, so it
    /// never outlives the selection it belongs to. See `catchUp`.
    private var newsAskedAt: Date?

    /// When the question went whose answer the searches he is typing in the
    /// selected mailbox go on: the one the first search of the burst sent,
    /// or found a moment old. Only a search sets it, and every SELECT clears
    /// it. See `Freshness.typing`.
    private var typingAskedAt: Date?

    /// Whether the selected mailbox may hold what the watch has not
    /// searched for since it last looked: set by every SELECT, whose answer
    /// is a view of the mailbox nobody has searched, and by every EXISTS or
    /// EXPUNGE that changes the session's view of it, on whatever answer it
    /// rides; cleared as the watch's SEARCH goes. See `askForNews`. What
    /// that SEARCH found and never reached the list is the watch's to ask
    /// for again (`MailWatch`), not this flag's.
    private var unsearchedNews = false

    /// The clock `newsAskedAt` is measured by. The app's is the real one; a
    /// test hands in one it can move.
    private let now: @Sendable () -> Date

    /// What the last SELECT of each mailbox reported, on this connection or
    /// an earlier one, with its message count kept as the EXISTS and EXPUNGE
    /// responses since have left it. UIDVALIDITY belongs to the mailbox
    /// rather than to the session, so this survives a reconnect, and it is
    /// how the repository learns that a mailbox has been renumbered and its
    /// remembered UIDs have gone stale.
    private var reportedStates: [String: IMAPMailboxState] = [:]

    /// How the last attempt to connect failed, nil if it did not, and how
    /// many attempts have failed. See `connect`. The count is also how the
    /// repository tells a read that failed on a connection still being
    /// made from one whose connection dropped
    /// (`IMAPMailRepository.retryingIfDisconnected`).
    private var connectFailure: MailError?
    private(set) var failedConnects = 0

    /// How many connections have been torn down: after a transport failure,
    /// a connect that failed after the socket opened, or a LOGOUT. How the
    /// repository tells a read whose connection died under it from one
    /// refused on a connection that is still up, whether or not another
    /// call has connected again since (`IMAPMailRepository.retryingIfDisconnected`).
    private(set) var connectionsLost = 0

    /// How the last LOGIN was refused, nil once a connection has been made
    /// since. Unlike `connectFailure` it outlives the next attempt that
    /// fails some other way, a network that is not there, so the watch,
    /// which never sends a password after a refusal, still knows there was
    /// one (`IMAPMailRepository.watchedConnection`). Any refusal, not only
    /// AUTHENTICATIONFAILED: a LOGIN answered NO for another reason and
    /// tried again every half minute is the same loop of failed logins.
    private(set) var loginRefusal: MailError?

    /// A write whose turn at the gate came with no connection: whatever held
    /// the connection ahead of it found the socket dead and tore it down, or
    /// the attempt to connect it queued behind failed. Not a byte of it was
    /// sent, so sending it on a new connection sends it once, where a write
    /// that failed on the wire may already have been carried out and is
    /// never sent again. `failure` is what the command would have thrown.
    /// Only the writes throw it, and only `IMAPMailRepository`'s write paths
    /// call them, which connect again or throw `failure` in its place
    /// (`IMAPMailRepository.sendingOnce`).
    struct Unsent: Error {
        let failure: MailError
    }

    /// True while one command owns the socket. See `beginExchange()`.
    private var exchangeInProgress = false
    /// Everyone waiting for the socket, in arrival order. Keyed so a waiter
    /// whose task is cancelled can be found and taken out of the line; see
    /// `Priority` for who goes next.
    private var exchangeWaiters: [(id: UInt64, turn: ExchangeTurn, priority: Priority)] = []
    private var lastWaiterID: UInt64 = 0

    /// Which line a command waits in while another has the socket.
    ///
    /// Two lines, each first come, first served, and the next holder is the
    /// first waiter in the interactive line if there is one. Priority only
    /// decides who goes NEXT: an exchange already under way is never
    /// interrupted, so the most a letter he opens waits for is that
    /// exchange, rather than one command for every screen with work queued.
    enum Priority {
        /// What he is waiting for with his eyes on the screen: the letter he
        /// opened, the attachment he tapped, and the first page of a folder
        /// he opened or refreshed, or of a day he jumped to (`fetchBody`,
        /// `fetchPart`, `page`). The page is a few commands, not one, but
        /// until it lands there is nothing on screen for him to open.
        ///
        /// And the writes, STORE, MOVE with its fallback, EXPUNGE, and the
        /// NOOP that probes before them. Each is something he has just done
        /// and is looking at the result of: the row a Delete took stays on
        /// screen until its MOVE lands. Each is one short exchange, so a
        /// letter he opens next waits a round trip for it at most. And all
        /// of them in one line keeps them in the order he made them: a flag
        /// set and then cleared has to reach the server in that order.
        ///
        /// APPEND is the exception and waits in the background line. It is
        /// the one write that can run for minutes, a draft with photos over
        /// his uplink, nothing on screen waits for it, and a letter he opens
        /// while it is still queued should not wait for the upload.
        case interactive
        /// Everything else: the pages after the first, previews, the STATUS
        /// sweep, and searches and their paging.
        case background
    }

    /// How a waiter is told its turn has come.
    private enum ExchangeTurn {
        /// A command, which leaves the line with `CancellationError` if its
        /// task is cancelled first.
        case command(CheckedContinuation<Void, Error>)
        /// Closing, which waits its turn whatever happens to its task, and
        /// so cannot be told anything but "go".
        case closing(CheckedContinuation<Void, Never>)
    }

    init(account: MailAccount, transport: @escaping MailTransportFactory,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.account = account
        self.makeTransport = transport
        self.now = now
    }

    #if canImport(Network)
    /// The app's own: the real TLS stack.
    init(account: MailAccount) {
        self.init(account: account, transport: TLSConnection.factory)
    }
    #endif

    var isConnected: Bool { connected }

    /// How many commands are waiting behind the one on the wire. How a test
    /// knows a command has joined the line without sleeping on it.
    var waitingForExchange: Int { exchangeWaiters.count }

    /// What the server last said of `mailbox`, nil if it has never been
    /// selected. See `reportedStates`.
    func lastReport(for mailbox: String) -> IMAPMailboxState? {
        reportedStates[mailbox]
    }

    // MARK: - Session

    func connect(password: String) async throws {
        // Held across the whole handshake, not just each command. Opening the
        // socket suspends, so without this two tasks that both decide they are
        // disconnected would each open a connection and the second would
        // overwrite (and leak) the first.
        //
        // In the interactive line: every command waiting in either line
        // needs the connection this makes.
        //
        // An attempt that fails is the answer for every call that was
        // already waiting for it, not only for the one that made it. A
        // refused password is the case that matters: each call that found
        // no connection used to make its own attempt once the one ahead of
        // it had failed, so with a revoked app password every screen that
        // wanted the connection at that moment sent the same wrong password
        // again. That is the retry `IMAPMailRepository` refuses to make,
        // made here instead. A call that comes along afterwards makes an
        // attempt of its own: that is him trying again, not us. The calls
        // that queued a command because the connection already reported
        // itself up, while the greeting and LOGIN were still on their way,
        // are given the same answer in `performCommand`.
        let failuresBefore = failedConnects
        try await beginExchange(.interactive)
        defer { endExchange() }

        guard !connected else { return }
        if failedConnects != failuresBefore, let connectFailure { throw connectFailure }
        connectFailure = nil
        // A new session has nothing selected, whatever the last one had.
        selectedMailbox = nil
        mailboxState = nil

        let conn = makeTransport(account.imapHost, account.imapPort)
        do {
            try await conn.open()
        } catch {
            await conn.close()
            connectFailure = .cannotConnect
            failedConnects += 1
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
                loginRefusal = nil
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
                    let refusal: MailError = result.status == .no && code == "AUTHENTICATIONFAILED"
                        ? .passwordNeedsUpdating : .cannotConnect
                    loginRefusal = refusal
                    throw refusal
                }
                loginRefusal = nil

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
            let failure = Self.userFacing(error)
            connectFailure = failure
            failedConnects += 1
            throw failure
        }
    }

    func disconnect() async {
        // Waits its turn even for a caller that has been cancelled. Closing is
        // what a caller does on its way out, and a started NWConnection that
        // is never cancelled is never let go of.
        await beginClosingExchange()
        defer { endExchange() }

        if connected {
            // Best effort. A server that has already gone away does not get to
            // turn closing a connection into an error the user sees.
            _ = try? await performCommand("LOGOUT")
        }
        await teardown()
    }

    /// In the interactive line by default, because the usual NOOP is the
    /// probe in front of a write and waits in the write's line. The one sent
    /// as the app comes back to the foreground waits in the background line:
    /// nothing is waiting for it, and a letter he taps while it is still
    /// waiting for the connection goes first. Once it is on the wire, the
    /// letter waits for its answer like anything else.
    ///
    /// Either one, answered, is also the selected mailbox's news asked for,
    /// so a listing of it straight after does not ask again (`catchUp`).
    func noop(_ priority: Priority = .interactive) async throws {
        try await beginExchange(priority)
        defer { endExchange() }
        guard try await performNOOP() else { throw MailError.cannotConnect }
    }

    /// A NOOP, true if it was answered OK. The caller holds the gate.
    private func performNOOP() async throws -> Bool {
        // When the question went, not when it was answered: mail that lands
        // while it is out may or may not be in the answer.
        let asked = now()
        let result = try await performCommand("NOOP")
        guard result.status == .ok else { return false }
        if selectedMailbox != nil { newsAskedAt = asked }
        return true
    }

    // MARK: - Mailboxes

    func listMailboxes() async throws -> [IMAPMailboxListing] {
        // `LIST "" "*"` rather than `"%"`: Gmail's real folders are children of
        // "[Gmail]" and a single-level list would hide Sent, Trash and All Mail.
        let result = try await sendCommand("LIST \"\" \"*\"")
        guard result.status == .ok else { throw MailError.cannotConnect }
        return IMAPParser.parseList(result.untagged)
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

    // MARK: - Selecting

    /// Runs `body` with `mailbox` selected, in ONE hold of the gate: the
    /// SELECT, when the connection does not already have that mailbox open,
    /// and then the command that depends on it.
    ///
    /// The two used to take the gate separately, with the repository's
    /// actor hops in between, and the repository skipped the SELECT on the
    /// strength of its own record of what was selected, kept outside the
    /// gate. Another screen's SELECT could land between them, so a FETCH, a
    /// STORE or a MOVE ran in the wrong mailbox, where the same UID can name
    /// a different letter (B-039). Nothing can come between them now, and
    /// only a holder of the gate changes what is selected.
    ///
    /// `validity` is the UIDVALIDITY the caller's UIDs were issued under;
    /// nil only for a command that names no UID it was handed, which is a
    /// SEARCH. When the mailbox's is different it has been renumbered since,
    /// and those UIDs name other letters or none, so the command is not sent
    /// and the call fails. The check is here, after the SELECT, because the
    /// SELECT is where a renumbering shows: it is the first thing sent after
    /// the reconnect that finds it. A refused SELECT sends nothing either,
    /// and leaves the connection up with nothing selected.
    ///
    /// `catchingUp` is for a command that lists what the mailbox holds, a
    /// SEARCH: the mailbox's news is asked for first, in the same hold,
    /// unless the session has it already. See `catchUp`.
    ///
    /// `writing` for a write, which is turned away with `Unsent` when its
    /// turn comes with no connection.
    private func inMailbox<T>(_ mailbox: String, validity: UInt32?, _ priority: Priority,
                              catchingUp freshness: Freshness? = nil, writing: Bool = false,
                              _ body: (IMAPMailboxState) async throws -> T) async throws -> T {
        try await beginExchange(priority)
        defer { endExchange() }
        if writing { try throwUnsentIfDisconnected() }
        let (state, selected) = try await select(mailbox)
        if let validity, state.uidValidity != validity {
            Diagnostics.log(.note, "UIDVALIDITY-CHANGED folder=\(mailbox) "
                            + "expected=\(validity) now=\(state.uidValidity) nothing-sent")
            throw MailError.cannotConnect
        }
        if let freshness { try await catchUp(freshness, selected: selected) }
        return try await body(state)
    }

    /// `mailbox`'s state, SELECTing it first unless it is already the one
    /// selected on this connection, and whether a SELECT went. The caller
    /// holds the gate.
    private func select(_ mailbox: String) async throws -> (state: IMAPMailboxState, selected: Bool) {
        if selectedMailbox == mailbox, let state = mailboxState { return (state, false) }

        // Nothing is selected from the moment the SELECT goes, as RFC 3501
        // §6.3.1 has it: a refused SELECT leaves the server with NOTHING
        // selected, not with the mailbox that was open before. Keeping the
        // old name skipped the SELECT the next time that mailbox was wanted,
        // and every UID command after it was answered BAD on a connection
        // that was still up, so no retry ever fired: one label deleted in
        // another client, tapped once, and the folder he came from said
        // "Can't connect" until the socket happened to drop. Cleared before
        // rather than after, the SELECT's own EXISTS is not taken for news
        // of the mailbox it leaves (`noteSizeChanges`).
        selectedMailbox = nil
        mailboxState = nil
        let asked = now()
        let result = try await performCommand("SELECT \(Self.mailboxArgument(mailbox))")
        guard result.status == .ok else { throw MailError.cannotConnect }

        let parsed = IMAPParser.parseSelect(result.untagged)
        // READ-ONLY normally arrives as a response code on the *tagged* OK
        // ("a003 OK [READ-ONLY] SELECT completed"), which the untagged-only
        // parser never sees, so it is folded back in here.
        let taggedCode = IMAPParser.responseCode(result.detail)?.uppercased()
        let isReadOnly = taggedCode == "READ-ONLY" || (parsed?.readOnly ?? false)

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
        reportedStates[mailbox] = state
        newsAskedAt = asked
        typingAskedAt = nil
        unsearchedNews = true
        return (state, true)
    }

    // MARK: - News of the selected mailbox

    /// How recently the session must have asked for the selected mailbox's
    /// news for a SEARCH in it to go without asking again. See `catchUp`.
    enum Freshness {
        /// A listing he asked for: Refresh, the folder opened again while it
        /// is open, a date jump, the reload after a Delete or a draft. The
        /// question has to have gone as he asked, so only one a moment old
        /// (`moment`) will do: the warm-up's NOOP as he picks the iPad up,
        /// before the Inbox is fetched again; a write's probe, before the
        /// list is fetched again after a Delete from Edit mode; the SELECT
        /// of a folder he opened and at once refreshed. Any longer and a
        /// second Refresh tapped while he waits for a letter would not ask,
        /// and would not show it.
        case asked
        /// A search as he types. The letter he is looking for came before he
        /// started typing, so the first search of a burst asks, as a listing
        /// does, and the rest ride on the answer it had while that is under
        /// `burst` old: at a key a second, a NOOP on every search would add
        /// a round trip to each. Only a search starts a burst. Measured from
        /// the Refresh or the folder's SELECT, a search five seconds after
        /// either would not ask, and would not find a letter that came in
        /// between. A letter that lands while he types is found by the first
        /// search once the burst's answer is ten seconds old, or by the next
        /// Refresh.
        case typing
        /// A search whose finding nothing is acted on as proof: the look in
        /// Sent Mail for a letter whose 250 never came (`searchNow`), where
        /// nothing found sends the letter again. The news is asked for
        /// whenever the SELECT did not go in this very hold, however
        /// recently it was asked: a letter Gmail filed a second after the
        /// last question is exactly the one looked for. And a NOOP refused
        /// fails the search rather than letting it answer from what the
        /// session knew.
        case now

        /// How old a question may be and still count as asked now.
        static let moment: TimeInterval = 2
        /// How long the searches of a burst go on its first one's answer.
        static let burst: TimeInterval = 10
    }

    /// Asks the server for the selected mailbox's news, with a NOOP, unless
    /// the session has asked within `freshness`. The caller holds the gate,
    /// has just selected the mailbox, and sends a SEARCH next; `selected`
    /// says a SELECT went for it in this hold.
    ///
    /// A SEARCH answers from the session's view of the mailbox, and that
    /// view takes in new mail only once the server has announced it to the
    /// session with EXISTS. Gmail, like most servers, announces it when it
    /// chooses: in the answer to a SELECT or a NOOP, or riding on some later
    /// command. A mailbox already selected is not SELECTed again, so nothing
    /// asked. On the iPad (B-045) a Refresh of the open Inbox SEARCHed and
    /// listed the seventeen letters the session knew of; Gmail announced the
    /// three that had arrived only during the page's FETCH, after the
    /// SEARCH, and the list showed them at the second Refresh. The NOOP has
    /// the server say what it has before the SEARCH, in the same hold, so no
    /// other command comes between them.
    ///
    /// The same answer carries EXPUNGE for a letter removed from another
    /// client, so the SEARCH stops listing that too.
    ///
    /// Not before every SEARCH. A SELECT in the same hold has asked, however
    /// long its answer took, and nothing can have come between it and the
    /// SEARCH; timed from when it went, a SELECT of All Mail answered slowly
    /// was followed by a NOOP it had made pointless. A NOOP a moment before
    /// has asked too: this one, the warm-up's or a write's probe
    /// (`performNOOP`). A NOOP refused leaves the SEARCH to go as it did
    /// before any of this, but for `.now`; a lost connection fails the call,
    /// as any command does, and a read's retry SELECTs the mailbox afresh.
    private func catchUp(_ freshness: Freshness, selected: Bool) async throws {
        let answered: Date?
        if selected {
            answered = newsAskedAt
        } else if case .typing = freshness, let burst = typingAskedAt,
                  isRecent(burst, within: Freshness.burst) {
            return
        } else if freshness != .now, let asked = newsAskedAt,
                  isRecent(asked, within: Freshness.moment) {
            answered = asked
        } else {
            let asked = now()
            let told = try await performNOOP()
            if !told, freshness == .now { throw MailError.cannotConnect }
            answered = told ? asked : nil
        }
        if case .typing = freshness { typingAskedAt = answered }
    }

    /// Whether `asked` was less than `seconds` ago. A time after now is not
    /// recent: the clock has been set back since, by the network's time
    /// after a flat battery or by hand, and taken as recent it would skip
    /// every question until the clock caught up, an hour of Refreshes that
    /// missed new mail for an hour's step.
    private func isRecent(_ asked: Date, within seconds: TimeInterval) -> Bool {
        let age = now().timeIntervalSince(asked)
        return age >= 0 && age < seconds
    }

    // MARK: - The watch

    /// The watch's question, every half minute while he has the Inbox's
    /// list in front of him (`MailWatch`): has `mailbox` changed since the
    /// watch last searched it? Returns the mailbox's UIDVALIDITY with the
    /// answer.
    ///
    /// ONE command in one hold of the gate, in the background line: a NOOP
    /// when the connection has the mailbox open, whose answer carries what
    /// has arrived and gone since the session was last told, or else its
    /// SELECT, whose answer is the mailbox as it is now. So a letter he taps
    /// while this waits for the connection goes first, and one he taps while
    /// it is on the wire waits for its answer, one round trip, and not for
    /// the SEARCH and FETCH that follow when something has changed: each is
    /// a hold of its own (`searchNews`, `fetchSummaries`).
    ///
    /// The answer is not only this NOOP's. EXISTS and EXPUNGE ride on any
    /// answer (`noteSizeChanges`), a preview's FETCH or a Delete's MOVE, and
    /// once told, the session is not told again; so what counts is whether
    /// anything has changed the session's view since the last `searchNews`.
    ///
    /// Answered, the NOOP is also the mailbox's news asked for (`catchUp`):
    /// a Refresh within a moment of it sends no NOOP of its own.
    func askForNews(of mailbox: String) async throws -> (validity: UInt32, changed: Bool) {
        try await beginExchange(.background)
        defer { endExchange() }
        let (state, selected) = try await select(mailbox)
        if !selected {
            guard try await performNOOP() else { throw MailError.cannotConnect }
        }
        return (state.uidValidity, unsearchedNews)
    }

    /// The UIDs `mailbox` holds from `lowest` up, the lowest letter the
    /// list holds, or all of them when it holds none: in one answer, the
    /// letters that have arrived above the list's newest and which of its
    /// own are still there. For the watch, once `askForNews` has said the
    /// mailbox changed. In the background line, in a hold of its own, with
    /// the SELECT when another command has left another mailbox open since.
    ///
    /// `n:*` and not SEARCH ALL: his Inbox goes back years, and SEARCH ALL
    /// would be tens of thousands of UIDs on every letter that arrives,
    /// where this is about as many as the list has loaded. RFC 3501 has `*`
    /// mean the highest UID in use, so `n:*` includes that one even when it
    /// is below `n`; the caller takes only what is above its newest as new.
    func searchNews(in mailbox: String, validity: UInt32,
                    from lowest: UInt32?) async throws -> [UInt32] {
        try await inMailbox(mailbox, validity: validity, .background) { _ in
            // Cleared as the SEARCH goes, not once it is answered: an EXISTS
            // riding on its own answer may be for a letter it did not list,
            // and has to be searched for next time. A SEARCH refused, or one
            // whose letters never reach the list, leaves the watch to search
            // again at its next check (`MailWatch`).
            self.unsearchedNews = false
            guard let uids = try await self.performSearch(lowest.map { "UID \($0):*" } ?? "ALL") else {
                throw MailError.cannotConnect
            }
            return uids
        }
    }

    /// Keeps the selected mailbox's message count as the server last left
    /// it. EXISTS and EXPUNGE can ride on any answer, a NOOP's above all,
    /// and the count is what the connection log's SESSION-IDENT line reports
    /// beside the listing's, which is how a listing that missed mail shows.
    ///
    /// A change is also news for the watch (`unsearchedNews`): a letter
    /// announced on the answer to a preview's FETCH is in the session's
    /// view from then on, and a NOOP after it says nothing more of it.
    private func noteSizeChanges(_ result: IMAPCommandResult) {
        guard let mailbox = selectedMailbox, var state = mailboxState,
              let change = IMAPParser.sizeChanges(after: result.untagged, from: state.exists) else { return }
        let count = change.count
        if change.expunged || count != state.exists { unsearchedNews = true }
        // Written back whole, not as `reportedStates[mailbox]?.exists = count`.
        // A change made in place inside a Dictionary compiles, with this
        // toolchain, to a coroutine that needs `swift_coroFrameAlloc`, which
        // the iOS 16 runtime does not have, and the device link fails.
        state.exists = count
        mailboxState = state
        reportedStates[mailbox] = state
    }

    // MARK: - Searching

    /// Every UID in `mailbox`, with the UIDVALIDITY that gives them meaning.
    func searchAll(in mailbox: String) async throws -> IMAPMailboxUIDs {
        try await search("ALL", in: mailbox)
    }

    /// A refusal is thrown, deliberately, and not returned as no hits: an
    /// empty result is indistinguishable in the interface from "this folder
    /// has no mail", and quietly showing an empty inbox is worse than
    /// saying so.
    ///
    /// Not behind a NOOP for the mailbox's news (`catchUp`). Its callers are
    /// a page whose snapshot has gone, cut strictly below a letter already
    /// on screen, where mail the NOOP would announce comes above that and a
    /// letter removed elsewhere is left to the next Refresh, as it is on a
    /// page walked from a snapshot; and the look in Drafts for a kept
    /// letter's earlier uploads, where a copy missed costs at worst a second
    /// copy in Drafts (`IMAPMailRepository.copies`). A search whose empty
    /// answer sends a letter is `searchNow`.
    func search(_ criteria: String, in mailbox: String) async throws -> IMAPMailboxUIDs {
        try await inMailbox(mailbox, validity: nil, .background) { state in
            guard let uids = try await self.performSearch(criteria) else {
                throw MailError.cannotConnect
            }
            return IMAPMailboxUIDs(validity: state.uidValidity, uids: uids)
        }
    }

    /// `search(_:in:)` over the mailbox as the server has it now: its news
    /// asked for first in the same hold, with a NOOP, unless a SELECT went
    /// in it (`Freshness.now`). For the look in Sent Mail for a letter whose
    /// 250 never came back (`IMAPMailRepository.sentMail`), where nothing
    /// found sends the letter again.
    ///
    /// A SEARCH in a mailbox already selected answers from the session's
    /// view of it, which takes in a letter only once the server has
    /// announced it (B-045). With Sent Mail left open on the connection, by
    /// a look before or by his own visit to it, a letter Gmail filed there
    /// after the session last heard would not be found, and would be sent a
    /// second time.
    func searchNow(_ criteria: String, in mailbox: String) async throws -> [UInt32] {
        try await inMailbox(mailbox, validity: nil, .background, catchingUp: .now) { _ in
            guard let uids = try await self.performSearch(criteria) else {
                throw MailError.cannotConnect
            }
            return uids
        }
    }

    /// One search run in several mailboxes back to back: for each, its
    /// SELECT, its SEARCH, and, where asked, the summaries of its newest
    /// hits, all in one hold of the gate.
    ///
    /// For the "All Mailboxes" search, which is Trash, Spam and All Mail
    /// every time he types. Taken a command at a time, as it used to be, each
    /// of its nine commands, the first page's FETCH included, queued behind a
    /// command from every other screen with work outstanding, and each of
    /// those that SELECTed somewhere else cost the search a SELECT to get
    /// back. In one hold the eight sent here go back to back; the page's
    /// FETCH is the repository's, a hold of its own. The summaries ride in
    /// the same hold because they need the mailbox selected: fetched after
    /// all three searches, they would cost a second SELECT of Trash and of
    /// Spam.
    ///
    /// Not pipelined: each command is written once the one before it has
    /// been answered. Writing the SEARCH straight behind its SELECT would
    /// save a round trip per mailbox, and it could be made safe against a
    /// refused SELECT by throwing the SEARCH's answer away. But Gmail's own
    /// time on each SEARCH, not the round trip, is most of what this search
    /// costs, and one command in flight at a time is the rule the host
    /// tests' scripted server holds every exchange to, which is how a
    /// broken gate gets caught.
    ///
    /// A mailbox the server will not open or will not search comes back
    /// with no hits rather than failing the rest: losing the Trash is a gap,
    /// losing the whole search is the feature not working. A lost connection
    /// fails the whole call, as it does any command.
    ///
    /// It gives way between mailboxes, never inside one, to anything waiting
    /// in the interactive line, which is a letter he tapped, or a folder he
    /// opened, while the search was running, and then takes the gate back
    /// ahead of the rest of the background line. So what he opens waits for
    /// the rest of the mailbox the search is in, its binned summaries
    /// included, and not for the whole search. And it stops between commands
    /// once its task is cancelled, with `CancellationError`, which is how the
    /// next keystroke ends it: never mid-command, so the stream stays in step
    /// and the connection stays up. Cancellation is reported whatever else
    /// went wrong on the way, a refusal or a lost connection included,
    /// because nobody is waiting to hear about either.
    ///
    /// A mailbox the connection already has open is asked for its news
    /// first, as a keystroke's search asks (`Freshness.typing`), so a letter
    /// that arrived after it was opened is found. That is the one mailbox of
    /// a Current Mailbox search, usually, and the Trash that an "All
    /// Mailboxes" search starts in when the Trash is the folder he has open;
    /// every other mailbox is SELECTed, which asks.
    func search(_ criteria: String, across targets: [IMAPSearchTarget]) async throws -> [IMAPMailboxSearch] {
        try await beginExchange(.background)
        var holding = true
        defer { if holding { endExchange() } }

        var out: [IMAPMailboxSearch] = []
        do {
            for target in targets {
                if !out.isEmpty, exchangeWaiters.contains(where: { $0.priority == .interactive }) {
                    // Cleared before the wait, not after it: a wait that
                    // ends in `CancellationError` returns without the gate,
                    // and the `defer` must not then hand on a gate that the
                    // command it gave way to is still using.
                    holding = false
                    endExchange()
                    try await beginExchange(.background, ahead: true)
                    holding = true
                }

                var hits: IMAPMailboxUIDs?
                do {
                    let (state, selected) = try await select(target.mailbox)
                    try Task.checkCancellation()
                    try await catchUp(.typing, selected: selected)
                    try Task.checkCancellation()
                    if let uids = try await performSearch(criteria) {
                        hits = IMAPMailboxUIDs(validity: state.uidValidity, uids: uids)
                    }
                } catch MailError.cannotConnect where connected {
                    // Refused, and the connection is still up: a transport
                    // failure would have torn it down. The next mailbox is
                    // still worth asking.
                }
                try Task.checkCancellation()

                var summaries: [IMAPFetchResult] = []
                if let hits, target.summariesOfNewest > 0, !hits.uids.isEmpty {
                    let newest = Array(hits.uids.suffix(target.summariesOfNewest).reversed())
                    var fetched: [IMAPFetchResult] = []
                    for chunk in Self.uidSetChunks(newest) {
                        fetched += try await performSummaryFetch(chunk) ?? []
                    }
                    summaries = Self.ordered(fetched, as: newest)
                    try Task.checkCancellation()
                }
                out.append(IMAPMailboxSearch(mailbox: target.mailbox, hits: hits, summaries: summaries))
            }
        } catch {
            try Task.checkCancellation()
            throw error
        }
        return out
    }

    /// One UID SEARCH in the selected mailbox, ascending, or nil if the
    /// server refused it. The caller holds the gate.
    private func performSearch(_ criteria: String) async throws -> [UInt32]? {
        let body = Self.sanitizedCommandText(criteria).trimmingCharacters(in: .whitespacesAndNewlines)
        let query = body.isEmpty ? "ALL" : body

        // A search string with non-ASCII in it needs a CHARSET, or the server
        // is entitled to answer BAD and the user's search for "Müller" simply
        // never works.
        let needsCharset = query.unicodeScalars.contains { $0.value > 127 }
        var result = try await performCommand(needsCharset ? "UID SEARCH CHARSET UTF-8 \(query)"
                                                           : "UID SEARCH \(query)")
        if result.status != .ok, needsCharset {
            // Some servers reject the CHARSET argument itself rather than the
            // term. One retry costs a round trip and rescues the search.
            result = try await performCommand("UID SEARCH \(query)")
        }
        guard result.status == .ok else { return nil }
        // Sorted, because the parser keeps the server's wire order and RFC
        // 3501 does not promise SEARCH results are ordered. Gmail happens to
        // answer ascending; every walk above this assumes it, and an unsorted
        // list would scramble the list on screen rather than fail.
        return IMAPParser.parseSearch(result.untagged).sorted()
    }

    // MARK: - Fetching

    /// The rows' summaries, in the order the UIDs are given.
    ///
    /// A hold per chunk rather than one for the lot, so a letter he opens
    /// waits for one chunk at most; each chunk selects the mailbox again if
    /// another screen had the socket in between.
    func fetchSummaries(uids: [UInt32], in mailbox: String,
                        validity: UInt32) async throws -> [IMAPFetchResult] {
        guard !uids.isEmpty else { return [] }

        var fetched: [IMAPFetchResult] = []
        var sawFailure = false
        for chunk in Self.uidSetChunks(uids) {
            let answer = try await inMailbox(mailbox, validity: validity, .background) { _ in
                try await self.performSummaryFetch(chunk)
            }
            guard let answer else {
                // One rejected chunk must not cost the other 4,900 messages.
                sawFailure = true
                continue
            }
            fetched += answer
        }

        let ordered = Self.ordered(fetched, as: uids)
        if ordered.isEmpty, sawFailure { throw MailError.cannotConnect }
        return ordered
    }

    /// A page he is waiting to see, the first of a folder he opened or the
    /// one a date jump lands on: the SEARCHes that decide which letters it
    /// holds, then their summaries, in one hold of the gate, in the
    /// interactive line.
    ///
    /// In the interactive line because until it lands the pane is empty,
    /// or still showing the folder he left. In one hold for the reason
    /// `fetchPart` is: taken as separate calls, the gate went to whatever
    /// was queued between them. An "All Mailboxes" search that was running
    /// took it back for its next mailbox, so the FETCH waited for that one
    /// too, and in the background line the page waited for the whole
    /// search. Now it goes, whole, at the next point the search gives way.
    ///
    /// `pick` chooses the UIDs to fetch from what the SEARCHes found, one
    /// list per criterion, in order. Every list comes out of the same
    /// SELECT, so they share its UIDVALIDITY, which is returned with each.
    /// The date jump finds its anchor from one list in the other, and in
    /// two holds a reconnect could have fallen between them and put them
    /// in different numberings.
    ///
    /// A refused SEARCH is thrown, as in `search(_:in:)`. A refused FETCH is
    /// thrown only if nothing at all came back, as in `fetchSummaries`.
    ///
    /// When the mailbox is already open on the connection, which is every
    /// Refresh, every reload from the top after a Delete, a Move or a
    /// draft, and a folder opened that other work left selected, the server
    /// is asked for its news first, in the same hold, or the SEARCHes would
    /// not see mail it had not yet announced (B-045, `catchUp`).
    func page(in mailbox: String, searching criteria: [String],
              picking pick: @Sendable ([[UInt32]]) -> [UInt32])
        async throws -> (found: [IMAPMailboxUIDs], summaries: [IMAPFetchResult]) {
        try await inMailbox(mailbox, validity: nil, .interactive, catchingUp: .asked) { state in
            // A listing from the top has searched everything the session
            // knows of the mailbox, and the list it becomes is the watch's to
            // check from, so the watch's next NOOP need not search again
            // unless something changes (`askForNews`). Cleared as the SEARCH
            // goes, as `searchNews` clears it, and set again if the listing
            // fails, when the list on screen stays the one it was. Not for a
            // date jump, which leaves that list on screen when it finds
            // nothing that recent.
            let fromTheTop = criteria == ["ALL"]
            if fromTheTop { self.unsearchedNews = false }
            do {
                var found: [IMAPMailboxUIDs] = []
                for criterion in criteria {
                    guard let uids = try await self.performSearch(criterion) else {
                        throw MailError.cannotConnect
                    }
                    found.append(IMAPMailboxUIDs(validity: state.uidValidity, uids: uids))
                }

                let wanted = pick(found.map(\.uids))
                var fetched: [IMAPFetchResult] = []
                var sawFailure = false
                for chunk in Self.uidSetChunks(wanted) {
                    guard let answer = try await self.performSummaryFetch(chunk) else {
                        sawFailure = true
                        continue
                    }
                    fetched += answer
                }
                let ordered = Self.ordered(fetched, as: wanted)
                if ordered.isEmpty, sawFailure { throw MailError.cannotConnect }
                return (found, ordered)
            } catch {
                if fromTheTop { self.unsearchedNews = true }
                throw error
            }
        }
    }

    /// One chunk of summaries from the selected mailbox, or nil if the
    /// server refused it. The caller holds the gate.
    private func performSummaryFetch(_ chunk: String) async throws -> [IMAPFetchResult]? {
        let result = try await performCommand("UID FETCH \(chunk) \(summaryItems)")
        guard result.status == .ok else { return nil }
        return IMAPParser.parseFetch(result.untagged)
    }

    /// One part of a letter, for the attachment he tapped: the letter's
    /// structure, which says how the part is wrapped, and then the part's
    /// bytes, as they sit in the message.
    ///
    /// Both in one hold of the gate, in the interactive line. Taken as two
    /// calls, the gate went to whatever background work was queued in the
    /// moment between them, and the attachment he was waiting for waited
    /// for it.
    ///
    /// `describe` finds the part in the letter's structure, and the part
    /// comes back with the bytes, since the structure is what says how they
    /// are wrapped.
    ///
    /// Nil when the server will not describe the letter, which usually
    /// means it has been moved or expunged by another client since the list
    /// was built, or when `describe` finds no such part in it. That is
    /// "there is nothing to show", not "the connection is broken", so it is
    /// a nil and not a throw, and the part's bytes are not asked for: they
    /// could be megabytes, fetched only to be refused.
    func fetchPart(uid: UInt32, section: String, in mailbox: String, validity: UInt32,
                   describedBy describe: @Sendable (MIMEPart) -> MIMEPart?)
        async throws -> (part: MIMEPart, bytes: Data)? {
        try await inMailbox(mailbox, validity: validity, .interactive) { _ in
            let described = try await self.performCommand("UID FETCH \(uid) \(self.summaryItems)")
            guard described.status == .ok else { return nil }
            let parsed = IMAPParser.parseFetch(described.untagged)
            guard let structure = (parsed.first { $0.uid == uid } ?? parsed.first)?.bodyStructure,
                  let part = describe(structure) else {
                return nil
            }
            return (part, try await self.performBodyFetch(uid: uid, section: section))
        }
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
    func fetchPartialBodies(uids: [UInt32], section: String, byteCount: Int,
                            in mailbox: String, validity: UInt32) async throws -> [UInt32: Data] {
        guard !uids.isEmpty, byteCount > 0 else { return [:] }
        let path = Self.sanitizedSection(section)

        var out: [UInt32: Data] = [:]
        for chunk in Self.uidSetChunks(uids) {
            // PEEK, like every other fetch here. A plain BODY[…] would set
            // \Seen, so merely scrolling a folder would mark the page read.
            let result = try await inMailbox(mailbox, validity: validity, .background) { _ in
                try await self.performCommand(
                    "UID FETCH \(chunk) (UID BODY.PEEK[\(path)]<0.\(byteCount)>)")
            }
            guard result.status == .ok else { continue }
            for fetched in IMAPParser.parseFetch(result.untagged) {
                guard let uid = fetched.uid, let body = fetched.body else { continue }
                out[uid] = body
            }
        }
        return out
    }

    /// In the interactive line: its caller is the letter he opened.
    func fetchBody(uid: UInt32, section: String?, in mailbox: String,
                   validity: UInt32) async throws -> Data {
        try await inMailbox(mailbox, validity: validity, .interactive) { _ in
            try await self.performBodyFetch(uid: uid, section: section)
        }
    }

    /// Gmail's id for the letter at `uid` now (X-GM-MSGID), or nil when the
    /// server names none: no letter at that UID any more, or no Gmail
    /// extension to ask. For a write on a row this launch has not had from
    /// the server, one kept on the iPad from an earlier launch (D-016): the
    /// row is the letter it names only if the ids agree, and nothing is
    /// written otherwise.
    ///
    /// In the interactive line, as the write it comes before is, and in one
    /// hold with the SELECT and the UIDVALIDITY check, as every UID command
    /// is (B-039). Not asked at all of a server without the extension: one
    /// Gmail item it does not know and it refuses the FETCH.
    func gmailMessageID(uid: UInt32, in mailbox: String, validity: UInt32) async throws -> UInt64? {
        try await inMailbox(mailbox, validity: validity, .interactive) { _ in
            guard try self.namesLetters() else { return nil }
            let result = try await self.performCommand("UID FETCH \(uid) (UID X-GM-MSGID)")
            guard result.status == .ok else { throw MailError.cannotConnect }
            return IMAPParser.parseFetch(result.untagged).first { $0.uid == uid }?.gmailMessageID
        }
    }

    /// The whole letter at `uid`, as `fetchBody` gives it, with Gmail's id
    /// for the letter asked in the same FETCH, X-GM-MSGID beside
    /// BODY.PEEK[]: for a letter opened from a row this launch has not had
    /// from the server, one kept on the iPad from an earlier launch
    /// (D-016). The one FETCH the letter costs anyway vouches for it, at no
    /// round trip more, and the caller shows nothing of it unless the id is
    /// the row's.
    ///
    /// `letter` is nil when the server names none: no letter at that UID
    /// any more, or no Gmail extension to ask, when nothing is fetched at
    /// all and there are no bytes, as `gmailMessageID` asks nothing. PEEK,
    /// as every body here is fetched, so the FETCH itself marks nothing
    /// read.
    func fetchBodyNamingLetter(uid: UInt32, in mailbox: String,
                               validity: UInt32) async throws -> (letter: UInt64?, raw: Data) {
        try await inMailbox(mailbox, validity: validity, .interactive) { _ in
            guard try self.namesLetters() else { return (nil, Data()) }
            let result = try await self.performCommand("UID FETCH \(uid) (UID X-GM-MSGID BODY.PEEK[])")
            guard result.status == .ok else { throw MailError.cannotConnect }
            let parsed = IMAPParser.parseFetch(result.untagged)
            let row = parsed.first { $0.uid == uid }
            // A whole-letter fetch that came back empty is the letter with
            // no body, as in `performBodyFetch`; the id says whose it is.
            return (row?.gmailMessageID, row?.body ?? Data())
        }
    }

    /// Whether the server can be asked for Gmail's id for a letter. Asked
    /// holding the gate, after the SELECT has shown the connection to be
    /// up: before it, a connection another holder's failed command had just
    /// torn down had no capabilities left, and read as a server with no
    /// extension, so a letter was taken for another one when the read
    /// should have gone again on a new connection. A set that could not be
    /// read at all is not a server without the extension either, and nothing
    /// is concluded from it.
    private func namesLetters() throws -> Bool {
        guard connected, !capabilities.isEmpty else { throw MailError.cannotConnect }
        return capabilities.contains("X-GM-EXT-1")
    }

    /// The whole message, or one section of it, from the selected mailbox.
    /// The caller holds the gate.
    private func performBodyFetch(uid: UInt32, section: String?) async throws -> Data {
        let path = section.map { Self.sanitizedSection($0) }
        // BODY.PEEK, never BODY: a plain BODY[] sets \Seen as a side effect, so
        // merely downloading a message in the background would mark it read
        // behind the user's back. Read state is changed only by `store`, when
        // he actually opens something.
        let item = "BODY.PEEK[\(path ?? "")]"
        let result = try await performCommand("UID FETCH \(uid) (UID \(item))")

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
    //
    // Every write names the UIDVALIDITY its UID came from and is refused,
    // with nothing sent, if the mailbox has been renumbered since. See
    // `inMailbox`.

    func store(uid: UInt32, flag: String, set: Bool, in mailbox: String,
               validity: UInt32) async throws {
        let cleaned = Self.sanitizedFlag(flag)
        guard !cleaned.isEmpty else { return }
        // .SILENT suppresses the untagged FETCH echo we would only throw away.
        let op = set ? "+FLAGS.SILENT" : "-FLAGS.SILENT"
        let result = try await inMailbox(mailbox, validity: validity, .interactive,
                                         writing: true) { _ in
            try await self.performCommand("UID STORE \(uid) \(op) (\(cleaned))")
        }
        guard result.status == .ok else { throw MailError.cannotConnect }
    }

    func move(uid: UInt32, from mailbox: String, validity: UInt32,
              to destination: String) async throws {
        // The gate is held for the SELECT and the whole copy/mark/expunge
        // sequence, not per command. Every step acts on "the selected
        // mailbox", so a SELECT from another task landing in the middle would
        // point the \Deleted flag and the EXPUNGE at a different folder
        // entirely — and the last-resort plain EXPUNGE there would take every
        // \Deleted message in it. This is the one sequence in the client that
        // can destroy mail, so it is the one that must be indivisible.
        // Cancelled while waiting for the gate, none of it is sent, unless
        // the cancel lands as the gate is handed over (see `beginExchange`);
        // cancelled once it has the gate, all of it is.
        try await inMailbox(mailbox, validity: validity, .interactive, writing: true) { _ in
            let target = Self.mailboxArgument(destination)

            // An empty capability set means the CAPABILITY response could not
            // be read, not that the server is feature-free, so try the good
            // path anyway and fall back if it is refused.
            if self.capabilities.isEmpty || self.capabilities.contains("MOVE") {
                let result = try await self.performCommand("UID MOVE \(uid) \(target)")
                if result.status == .ok { return }
            }

            let copied = try await self.performCommand("UID COPY \(uid) \(target)")
            // The order matters enormously: if the copy failed and we deleted
            // anyway, the message is simply gone. Nothing is marked \Deleted
            // until a copy is known to exist at the far end.
            guard copied.status == .ok else { throw MailError.cannotConnect }

            let flagged = try await self.performCommand("UID STORE \(uid) +FLAGS.SILENT (\\Deleted)")
            guard flagged.status == .ok else { throw MailError.cannotConnect }

            // UID EXPUNGE removes exactly this message. Plain EXPUNGE removes
            // every \Deleted message in the mailbox, which would collect
            // anything another client had marked and not yet expunged — so it
            // is the last resort, used only when the targeted form is refused.
            let expunged = try await self.performCommand("UID EXPUNGE \(uid)")
            if expunged.status != .ok {
                _ = try await self.performCommand("EXPUNGE")
            }
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
            continuationPayload: raw, writing: true)
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
    /// that flag outside Trash. Both steps go in one hold, as `move`'s do,
    /// and for the same reason: the flag and the EXPUNGE used to take the
    /// gate separately, so a SELECT in between could send that blunter
    /// instrument into another folder.
    func expunge(uid: UInt32, in mailbox: String, validity: UInt32) async throws {
        try await inMailbox(mailbox, validity: validity, .interactive, writing: true) { _ in
            let flagged = try await self.performCommand("UID STORE \(uid) +FLAGS.SILENT (\\Deleted)")
            guard flagged.status == .ok else { throw MailError.cannotConnect }
            let command = self.capabilities.contains("UIDPLUS") ? "UID EXPUNGE \(uid)" : "EXPUNGE"
            let result = try await self.performCommand(command)
            guard result.status == .ok else { throw MailError.cannotConnect }
        }
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
    ///
    /// It is also where a cancelled task stops sending. A task cancelled
    /// before it reaches the gate, or while it waits in line, throws
    /// `CancellationError` and writes nothing, and one cancelled after it has
    /// the gate finishes the exchange, reply and all. Nothing below this
    /// throws for cancellation, because the transport's reads do not, so a
    /// search that the next keystroke replaces mid-reply leaves the stream in
    /// step and the connection up, and learns it was cancelled when it comes
    /// back for its next command.
    ///
    /// The one overlap is a cancel that lands while the holder is finishing
    /// its exchange on this actor. The waiter's watcher reaches the actor only
    /// after that, by when the holder has handed the gate over, so it finds
    /// the waiter out of line and the command goes out. Nothing throws once
    /// the gate is held, so that command is sent and its reply read like any
    /// other, and the stream stays in step.
    ///
    /// The gate is handed from one holder straight to the next waiter rather
    /// than released for whoever gets there first, so each line is strictly
    /// first come, first served, the interactive line goes before the
    /// background one (see `Priority`), and each waiter is resumed exactly
    /// once: either with the gate or, if its task is cancelled first, with the
    /// error. That order holds by construction. No test can put a newcomer
    /// inside the hand-over, so none would notice if it were lost.
    ///
    /// `ahead` puts the waiter at the head of its line instead of the back.
    /// Only a holder that has just given the gate up for an interactive
    /// command uses it, to take it back before the background work that
    /// queued meanwhile; see `search(_:across:)`.
    private func beginExchange(_ priority: Priority, ahead: Bool = false) async throws {
        try Task.checkCancellation()
        guard exchangeInProgress else {
            exchangeInProgress = true
            return
        }
        lastWaiterID += 1
        let id = lastWaiterID
        // A child task that watches for the cancel, since a waiter parked on
        // a continuation cannot see it. Being a child, it is cancelled with
        // this task; it is also cancelled, and awaited, when this scope
        // exits, and by then the waiter has left the line one way or the
        // other, so its request finds nothing to do. It reaches the actor
        // only after the waiter is in line, however early the cancel came:
        // this actor is not free again until `waitInLine` has suspended.
        //
        // Not `withTaskCancellationHandler`. Every spelling of it in the iOS
        // 16.5 SDK is back-deployed, from 16.4, so on a 16.0 target a call
        // compiles to an OS version check, which needs compiler-rt's
        // `__isPlatformVersionAtLeast`, and this toolchain has no compiler-rt
        // for iOS: the device link fails.
        async let _: Void = leaveLineWhenCancelled(id)
        try await waitInLine(id, priority, ahead: ahead)
    }

    /// The gate for closing the connection, which has to happen whatever
    /// the caller's state: it waits its turn and cannot be turned away, so
    /// it returns only holding the gate.
    ///
    /// In the background line, so it overtakes nothing already waiting: a
    /// command asked for before the close still gets its answer.
    private func beginClosingExchange() async {
        guard exchangeInProgress else {
            exchangeInProgress = true
            return
        }
        lastWaiterID += 1
        let id = lastWaiterID
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            exchangeWaiters.append((id, .closing(c), .background))
        }
    }

    /// Returns holding the gate, or throws if `leaveLine` got there first.
    private func waitInLine(_ id: UInt64, _ priority: Priority, ahead: Bool) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            // The head of the whole array is the head of either line: the
            // next holder is picked by line first and by position second.
            if ahead {
                exchangeWaiters.insert((id, .command(c), priority), at: 0)
            } else {
                exchangeWaiters.append((id, .command(c), priority))
            }
        }
    }

    /// Sleeps until the task it runs in is cancelled, then takes waiter `id`
    /// out of line if it is still there.
    ///
    /// A second at a time rather than one long sleep, although only the
    /// cancel ever matters. A sleep cut short by a cancel leaves its timer
    /// with the runtime until the time it was set for, about half a kilobyte
    /// each, and every watcher is cut short, by its waiter's turn coming if
    /// not by a cancel. Timers set an hour ahead would hold on to every wait
    /// of the last hour; set a second ahead, only those of the last second.
    private nonisolated func leaveLineWhenCancelled(_ id: UInt64) async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        await leaveLine(id)
    }

    /// A waiter whose task was cancelled before its turn. If it is no longer
    /// in line it has already been given the gate, and an exchange that has
    /// begun is not interrupted.
    private func leaveLine(_ id: UInt64) {
        guard let index = exchangeWaiters.firstIndex(where: { $0.id == id }),
              case .command(let waiter) = exchangeWaiters[index].turn else { return }
        exchangeWaiters.remove(at: index)
        waiter.resume(throwing: CancellationError())
    }

    private func endExchange() {
        guard !exchangeWaiters.isEmpty else {
            exchangeInProgress = false
            return
        }
        // Still in progress: it now belongs to the waiter.
        let next = exchangeWaiters.firstIndex { $0.priority == .interactive } ?? 0
        switch exchangeWaiters.remove(at: next).turn {
        case .command(let waiter):  waiter.resume()
        case .closing(let waiter):  waiter.resume()
        }
    }

    /// Writes one tagged command and reads until its tagged completion, taking
    /// the exchange gate for the duration. For commands that need no mailbox
    /// selected; the rest go through `inMailbox`. `writing` as there.
    private func sendCommand(_ command: String, priority: Priority = .background,
                             continuationPayload: Data? = nil,
                             writing: Bool = false) async throws -> IMAPCommandResult {
        try await beginExchange(priority)
        defer { endExchange() }
        if writing { try throwUnsentIfDisconnected() }
        return try await performCommand(command, continuationPayload: continuationPayload)
    }

    /// For a write that has just been given the gate: `Unsent` if there is
    /// no connection to send it on. Asked before anything is written, the
    /// SELECT included, so what it says is certain: nothing of the write
    /// has gone. `performCommand` would throw the same failure a moment
    /// later, and as a plain `MailError` the repository could not tell it
    /// from a write that died on the wire.
    private func throwUnsentIfDisconnected() throws {
        guard connected, connection != nil else {
            throw Unsent(failure: connectFailure ?? .cannotConnect)
        }
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
    ///
    /// With no connection, a command fails the way the last attempt to make
    /// one did. The commands that reach here with none are the ones queued
    /// while an attempt was under way, and a refused password has to reach
    /// them as a refused password: as "Can't connect" it read to the
    /// repository as a dropped socket, and its read retry sent the password
    /// again (see `connect`).
    private func performCommand(_ command: String,
                                continuationPayload: Data? = nil) async throws -> IMAPCommandResult {
        guard connected, let conn = connection else { throw connectFailure ?? MailError.cannotConnect }
        let tag = nextTag()
        do {
            // Redaction happens inside Diagnostics.log, not here, so a future
            // call site cannot forget it. LOGIN's password is stripped there.
            Diagnostics.log(.sent, "\(tag) \(command)")
            try await conn.writeLine("\(tag) \(command)")
            let result = try await awaitResult(tag: tag, continuationPayload: continuationPayload)
            noteSizeChanges(result)
            return result
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
        var wait = ReplyWait.ordinary

        while true {
            let line = try await readResponse(wait)
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
                    // APPEND's answer comes only once the whole letter has
                    // crossed his uplink and Gmail has filed it.
                    wait = .afterUpload
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
    ///
    /// `wait` applies to the first line, the one the server may be slow to
    /// start; the rest of a response follows on its heels.
    private func readResponse(_ wait: ReplyWait = .ordinary) async throws -> IMAPResponseLine {
        guard connected, let conn = connection else { throw MailError.cannotConnect }

        var text = try await conn.readLine(wait)
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
        if let conn = connection {
            connectionsLost += 1
            await conn.close()
        }
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

    /// `fetched` in the order of `uids`, once each, leaving out what did not
    /// come back.
    ///
    /// The order asked for rather than the order the server felt like: the
    /// caller hands UIDs over newest first and expects rows back in that
    /// order, and servers answer in sequence order, which is the reverse. A
    /// result with no UID has no stable identity, so the repository could
    /// neither open it nor reconcile it on the next refresh; dropping it is
    /// the only safe thing to do with it.
    static func ordered(_ fetched: [IMAPFetchResult], as uids: [UInt32]) -> [IMAPFetchResult] {
        var byUID: [UInt32: IMAPFetchResult] = [:]
        for result in fetched {
            if let uid = result.uid { byUID[uid] = result }
        }
        var out: [IMAPFetchResult] = []
        out.reserveCapacity(byUID.count)
        var emitted = Set<UInt32>()
        for uid in uids where !emitted.contains(uid) {
            if let result = byUID[uid] {
                out.append(result)
                emitted.insert(uid)
            }
        }
        return out
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
