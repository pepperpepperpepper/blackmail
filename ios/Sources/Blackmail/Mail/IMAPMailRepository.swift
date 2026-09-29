import Foundation

/// The real `MailRepository`: the seam where the hand-rolled IMAP/SMTP engine
/// meets the interface.
///
/// An actor — but note carefully what that does and does not buy, because the
/// first version of this comment got it wrong in exactly the way that bites.
///
/// Swift actors are REENTRANT. Isolation guarantees no two tasks run actor
/// code at the same instant; it does NOT hold the actor across an `await`. So
/// a SELECT sent from here followed by a fetch sent from here was never
/// indivisible, however close together the two lines sat: another screen
/// could enter between them and re-SELECT a different folder, and the fetch
/// then read from the wrong mailbox. The same mistake in `IMAPClient` let a
/// `UID STORE` eat a `UID FETCH`'s tagged reply — reachable from this app's
/// own UI, where tapping a message fires setRead and loadMessage together.
///
/// What actually serialises the wire is `IMAPClient`'s exchange gate, and the
/// client is also what keeps each UID command in its mailbox: it owns the
/// selection, and every UID command goes out in one hold of the gate with the
/// SELECT it needs, and with a check that the mailbox still has the
/// UIDVALIDITY the UIDs came from (B-039). This actor keeps no record of what
/// is selected, because a record kept on this side of the gate is exactly
/// what went stale. Its job is narrower: turning ids into UIDVALIDITY and UID
/// and back, and the snapshots and search sessions that paging walks.
actor IMAPMailRepository: MailRepository {

    private let account: MailAccount
    private let password: String
    private let imap: IMAPClient
    private let smtp: SMTPClient
    /// Where the addresses walking past in envelopes are remembered. The
    /// app's one shared book; the host tests hand in a throwaway one so a
    /// test run neither reads nor writes the defaults of the machine it
    /// runs on.
    private let recipients: RecipientBook

    /// Role → real IMAP name, learned from LIST's special-use attributes.
    /// Never hard-code "Trash": Gmail calls it "[Gmail]/Trash", and on an
    /// account in another language it is not an English word at all.
    private var roleNames: [Mailbox.Role: String] = [:]
    /// The last whole message downloaded, kept so opening an attachment does
    /// not re-fetch the entire message it came from.
    private var lastBody: (messageID: String, raw: Data)?
    /// Which body part each listed message's preview should come from,
    /// remembered from the BODYSTRUCTURE the list fetch already paid for.
    /// Without it, `previews` would have to re-fetch every structure it was
    /// just handed.
    private var previewParts: [String: MIMEPart] = [:]
    /// LIST attribute (lowercased) → real folder name, learned alongside
    /// `roleNames`. Needed because Gmail's Important and Starred carry
    /// attributes RFC 6154 never defined, so they have no `Mailbox.Role` and
    /// cannot be found through `roleNames` at all.
    private var folderForAttribute: [String: String] = [:]
    /// What LIST said last, nil until it has been asked. The two tables
    /// above are learned from it, `folders()` answers from it, and every
    /// sweep of the counts lists again and replaces it. See `knownListing`.
    private var listed: [IMAPMailboxListing]?
    /// The LIST on the wire, for anyone else who wants one to share rather
    /// than send a second. See `freshListing`.
    private var listing: Task<[IMAPMailboxListing], Error>?
    /// The ascending UID list per mailbox, and its UIDVALIDITY, as of the
    /// last time the list was started from the top. Paging walks this rather
    /// than re-issuing SEARCH ALL for every page. See `listMessages`, and
    /// `snapshot(of:client:)` for when it is thrown away.
    private var uidListing: [String: IMAPMailboxUIDs] = [:]

    /// One factory for both protocols: it is told the host and port, which
    /// is all that tells an IMAP connection from an SMTP one.
    ///
    /// `now` is the clock the write probe measures quiet by, and the client
    /// how long ago it asked for a mailbox's news (`IMAPClient.catchUp`).
    /// The app's is the real one; a test hands in one it can move, because
    /// the probe only happens after ninety seconds of it.
    init(account: MailAccount, password: String,
         transport: @escaping MailTransportFactory,
         recipients: RecipientBook = .shared,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.account = account
        self.password = password
        self.imap = IMAPClient(account: account, transport: transport, now: now)
        self.smtp = SMTPClient(account: account, transport: transport)
        self.recipients = recipients
        self.now = now
        // His own address, always offered, from the very first launch.
        // He writes to himself constantly and it is the one address the
        // book cannot learn by watching his mail go past — a letter to
        // himself only teaches it after he has already typed it once.
        recipients.note(address: account.address, name: account.displayName)
    }

    #if canImport(Network)
    /// The app's own: the real TLS stack.
    init(account: MailAccount, password: String) {
        self.init(account: account, password: password, transport: TLSConnection.factory)
    }
    #endif

    #if canImport(Network) && canImport(Security)
    /// Builds from stored credentials, or nil on first launch before the
    /// account has been set up. Guarded twice: the credentials live in the
    /// keychain, and the connection they open is the real one.
    static func fromStoredCredentials() -> IMAPMailRepository? {
        guard let account = CredentialStore.loadAccount(),
              let password = CredentialStore.loadPassword(for: account) else { return nil }
        return IMAPMailRepository(account: account, password: password)
    }
    #endif

    // MARK: - Identity

    /// `MessageSummary.id` is "<uidvalidity>/<uid>", not a bare UID.
    ///
    /// A UID is only meaningful together with the UIDVALIDITY of the mailbox
    /// it came from. If the server renumbers a mailbox — rare, but it happens
    /// on restore, and Gmail does it — every UID the app is holding now points
    /// at a different message. Carrying the validity in the id means a stale
    /// one is *detected* rather than acted on, so the worst case is a refresh
    /// instead of flagging or deleting a message the user never chose.
    private static func makeID(validity: UInt32, uid: UInt32) -> String {
        "\(validity)/\(uid)"
    }

    /// Both halves, because every command that acts on the UID hands the
    /// validity to the client with it. If the mailbox has been renumbered
    /// under us the client refuses rather than guesses, with nothing sent;
    /// the caller's next reload will rebuild with fresh ids.
    private static func parseID(_ id: String) throws -> (validity: UInt32, uid: UInt32) {
        let parts = id.split(separator: "/", maxSplits: 1)
        guard parts.count == 2,
              let validity = UInt32(parts[0]), let uid = UInt32(parts[1]) else {
            throw MailError.cannotConnect
        }
        return (validity, uid)
    }

    // MARK: - Connection

    /// Runs a READ, and if the connection turned out to be dead, reconnects
    /// and runs it once more.
    ///
    /// Gmail closes an IMAP connection that has been idle for a while and
    /// this app does not notice until it next tries to use it. The failure
    /// is not random: `teardown()` clears `connected`, so the FIRST command
    /// after the drop fails and the SECOND reconnects and works. That is a
    /// very specific and very bad shape for this product — a man who picks
    /// the iPad up three times a day would find the first thing he tapped
    /// each time failed, and the retry that fixes it is one he has to know
    /// to perform.
    ///
    /// Observed rather than theorised: opening a reply gave "Can't connect
    /// to mail server", and tapping the identical row again loaded it.
    ///
    /// Only retried when a connection that was up when the read began has
    /// since been torn down, which is the dropped socket this exists for. A
    /// UIDVALIDITY mismatch and a server NO throw too, and repeating those
    /// just fails twice as slowly. READS only — a STORE or a MOVE may have
    /// been carried out before the socket died, and doing it again is not
    /// free of consequences.
    ///
    /// Not when the read had to connect first and the connect failed. A
    /// refused LOGIN is the case that matters: retrying it sends the same
    /// wrong password a second time, so with a revoked app password every
    /// search he typed cost two failed logins, and Gmail throttles an account
    /// that keeps failing to authenticate. A server that could not be
    /// reached a moment ago will not be reached by asking again at once
    /// either, and on the device each attempt can take the whole connect
    /// timeout. `passwordNeedsUpdating` is never retried, however it arose.
    ///
    /// Nor for a caller that has been cancelled. Only a search is ever
    /// cancelled, by the next keystroke, and cancelling one no longer costs
    /// the connection: the command it had on the wire finishes and the next
    /// is refused at the client's exchange gate. What reaches here from a
    /// cancelled caller is that refusal, or a real failure nobody is waiting
    /// to hear about, and neither is worth a fresh connection.
    private func retryingIfDisconnected<T>(
        _ body: () async throws -> T) async throws -> T {
        let wasConnected = await imap.isConnected
        do {
            return try await body()
        } catch {
            guard wasConnected, !Task.isCancelled,
                  (error as? MailError) != .passwordNeedsUpdating,
                  await imap.isConnected == false else { throw error }
            return try await body()
        }
    }

    /// How long the connection may sit quiet before a WRITE probes it.
    ///
    /// Short enough that picking the iPad up after lunch always probes,
    /// long enough that a burst of flagging does not pay a round trip per
    /// tap.
    private static let quietBeforeProbe: TimeInterval = 90

    /// When an operation last started. Not "last succeeded" — the point is
    /// to measure how long the socket has been unused.
    private var lastContact = Date.distantPast

    private let now: @Sendable () -> Date

    /// How many calls are waiting for the connection behind the one using
    /// it. How a test knows a call has joined the line without sleeping on it.
    var waitingForExchange: Int {
        get async { await imap.waitingForExchange }
    }

    private func connected() async throws -> IMAPClient {
        lastContact = now()
        if await imap.isConnected { return imap }
        // The warm-up has sent the password a moment ago, since he picked
        // the iPad up, and Gmail refused it. See `warmUp`.
        if let refused = refusedAtWarmUp {
            guard now().timeIntervalSince(refused) >= Self.refusalStands else {
                throw MailError.passwordNeedsUpdating
            }
            refusedAtWarmUp = nil
        }
        // A new session starts with nothing selected. The client clears its
        // own selection as it connects; there used to be a copy of it here,
        // cleared only once this returned, and a tap in between, with the
        // client already reporting connected, skipped its SELECT and was
        // answered BAD.
        try await imap.connect(password: password)
        return imap
    }

    /// When the connection `warmUp` made in place of a dead one had its
    /// password refused, nil if it has not been. For `refusalStands` after
    /// that no call connects; the next `warmUp` clears it.
    private var refusedAtWarmUp: Date?

    /// How long a password refused at the warm-up is the answer to every
    /// call without being sent again: long enough to cover the tap he makes
    /// once he has found the letter he wants, short enough that anything
    /// after it is him trying again. That is `IMAPClient.connect`'s rule,
    /// and Gmail refuses a correct app password now and then, so a latch
    /// that held until he next came back left a Refresh an hour later
    /// failing without an attempt, with nothing on screen to say that
    /// locking and unlocking the iPad was the way out.
    private static let refusalStands: TimeInterval = 60

    /// Probes the connection as the app comes back to the foreground, and
    /// replaces it if it has died, so that the first thing he taps does not
    /// find out for him.
    ///
    /// A socket left while the iPad sleeps is usually dead by the time he
    /// picks it up, and nothing finds that out until a command is written
    /// into it: then his first tap paid a failed command, the teardown, and a
    /// whole reconnect, 0.6 to 1.1 s on the first letter he opened, and a
    /// date jump or a search in one folder could fail outright. Now a NOOP
    /// goes as he comes back, and a dead socket is replaced while he is
    /// still finding the letter he wants.
    ///
    /// The same ninety seconds as the probe in front of a write
    /// (`quietBeforeProbe`), measured the same way, from the last command
    /// rather than from when he left: the socket's own quiet is what Gmail
    /// and the network drop it for. So a return after a short interruption
    /// sends nothing, and one after a long spell sends one NOOP. It waits in
    /// the background line, so what he taps while it is still waiting for
    /// the connection goes first. Priority only decides who goes next,
    /// though, and at the return the connection is usually free, so the
    /// NOOP is on the wire at once, and a letter tapped then waits for its
    /// answer: a round trip, or on a half-open socket the whole read
    /// deadline, which is what the letter's own command would have waited
    /// without the probe. A connection is made only in place of one that
    /// the NOOP found dead, never where there was none: that is a launch
    /// that could not connect, or a refused password, and neither is this
    /// call's to try again.
    ///
    /// `lastContact` is stamped only once the connection has been proven,
    /// by the NOOP's answer or by the new connection, and not as the NOOP
    /// goes. Stamped as it went, a write he made while it was out took the
    /// connection for proven, skipped its own probe (`readyForWrite`) and
    /// queued behind the NOOP; when the NOOP found the socket dead, the
    /// write reached a connection already torn down, and a write is never
    /// retried, so a Delete or a Flag failed on the one connection B-024
    /// exists to prove first. Unstamped, the write probes for itself: its
    /// NOOP fails with this one, reconnects, and the write goes once, on the
    /// new connection.
    ///
    /// A replacement's password refused stands as the answer to every call
    /// for `refusalStands`, rather than being sent again by the first thing
    /// he taps a moment later. Without the probe his first tap sent it;
    /// with it and no latch, the probe sent it and then his first tap sent
    /// it again, seconds apart. Calls queued behind a refused LOGIN already
    /// share its answer (`IMAPClient.connect`), but a tap comes after the
    /// probe has finished, and is two calls, the letter and its read mark.
    /// The password cannot change under a running repository in any case;
    /// Settings reaches it at the next launch.
    ///
    /// Nothing is sent as the app goes into the background. A LOGOUT there
    /// would cost a whole reconnect on every return, however short.
    func warmUp() async {
        refusedAtWarmUp = nil
        guard now().timeIntervalSince(lastContact) > Self.quietBeforeProbe,
              await imap.isConnected else { return }
        do {
            try await imap.noop(.background)
            lastContact = now()
            return
        } catch {
            // Answered NO on a connection still up is not a dead socket.
            guard await imap.isConnected == false else { return }
        }
        do {
            try await imap.connect(password: password)
            lastContact = now()
        } catch MailError.passwordNeedsUpdating {
            refusedAtWarmUp = now()
        } catch {
            // Unreachable, most likely. The next call tries for itself.
        }
    }

    /// Makes sure the connection is alive BEFORE doing something that must
    /// happen exactly once.
    ///
    /// Reads solve the idle-disconnect problem by retrying (see
    /// `retryingIfDisconnected`); writes cannot, because a MOVE or an
    /// APPEND may have reached the server before the socket died and
    /// repeating it is a different outcome rather than the same one twice.
    ///
    /// So the order is inverted: send a NOOP first, which IS idempotent
    /// and therefore safe to retry into a reconnect, and only then send
    /// the write — exactly once, down a connection just proven to work.
    /// The common case this fixes is the cleanly-closed socket Gmail
    /// leaves behind after an idle spell, where the probe fails
    /// immediately and the reconnect costs one round trip.
    ///
    /// Not free of gaps. A HALF-OPEN socket can still stall the probe for
    /// the read timeout, and a command whose reply is lost in flight is
    /// still ambiguous. But the flags are idempotent, and a UID is never
    /// reused within a UIDVALIDITY, so a repeated MOVE or EXPUNGE either
    /// does the same thing or fails to find the message. APPEND is the one
    /// that could genuinely duplicate, and a second draft is the mildest
    /// of the outcomes available.
    ///
    /// Sending is not on this path at all: `SMTPClient` opens a fresh
    /// connection per letter, so it was never exposed to this.
    private func readyForWrite() async throws {
        guard now().timeIntervalSince(lastContact) > Self.quietBeforeProbe else { return }
        try await retryingIfDisconnected {
            let client = try await self.connected()
            try await client.noop()
        }
    }

    /// Turns an interface-level id into a real IMAP mailbox name.
    ///
    /// The rest of the app speaks in role words — `RootViewController` opens
    /// `Mailbox(id: "inbox")` on launch — while IMAP wants "INBOX" or
    /// "[Gmail]/Sent Mail". Anything that is not a known role is passed
    /// through untouched, so a real folder name works too.
    ///
    /// The roles come from LIST alone, asked once. This used to run the
    /// whole sweep, a STATUS for every folder, and throw the counts away
    /// for the one name it wanted; at launch that put the Inbox's SELECT
    /// eighteen or so commands deep, behind eight unread counts, with the
    /// folder pane's own sweep interleaved on top. The LIST cannot be
    /// skipped for the Inbox, though "INBOX" is its name everywhere: without
    /// the roles, the rows of the first page would be drawn without All Mail
    /// among the folders they count in (`countedFolders`), and reading one
    /// would leave All Mail's count high.
    private func resolve(_ id: String) async throws -> String {
        if let role = Mailbox.Role(rawValue: id.lowercased()) {
            _ = try await knownListing()
            if let name = roleNames[role] { return name }
            if role == .inbox { return "INBOX" }
        }
        if id.caseInsensitiveCompare("inbox") == .orderedSame { return "INBOX" }
        return id
    }

    // MARK: - Mailboxes

    /// The folders as LIST last gave them, asking only if it never has.
    private func knownListing() async throws -> [IMAPMailboxListing] {
        if let listed { return listed }
        return try await freshListing()
    }

    /// LIST, now, and what it says learned: the roles, the attribute table
    /// and `listed`.
    ///
    /// A LIST already on the wire is joined rather than sent again. At
    /// launch the folder pane wants the names and the Inbox wants its role
    /// at the same moment, and two callers each finding nothing known used
    /// to send one each.
    ///
    /// Its own task, so the LIST is not the property of whichever caller
    /// happened to start it: a search cancelled by the next keystroke does
    /// not take the others' answer with it. Retried like any read, because
    /// a write that has to find a role's name comes through here without a
    /// retry of its own.
    private func freshListing() async throws -> [IMAPMailboxListing] {
        if let listing { return try await listing.value }
        let asked = Task { () async throws -> [IMAPMailboxListing] in
            try await self.retryingIfDisconnected {
                let found = try await self.connected().listMailboxes()
                self.learn(found)
                return found
            }
        }
        listing = asked
        defer { listing = nil }
        return try await asked.value
    }

    /// Names, no counts: the folders from the last LIST, or from a LIST
    /// alone if there has never been one.
    ///
    /// For what only needs the names. The Move sheet used to run the whole
    /// sweep, a STATUS per folder it does not show, and opened empty until
    /// it was done; from the reading pane a Move then ran a second sweep for
    /// the sidebar. At launch the folder pane draws these while the Inbox
    /// opens and asks for the counts after.
    ///
    /// A folder made in another client since the last sweep is missing
    /// until the next one. Every Refresh sweeps.
    func folders() async throws -> [Mailbox] {
        Self.mailboxes(from: try await knownListing(), unread: [:])
    }

    /// The sweep: LIST, and the unread count of every folder in it.
    ///
    /// No read retry of its own. The LIST is retried in `freshListing`, and
    /// a STATUS that fails leaves its folder at 0 rather than failing the
    /// sweep, so a retry here could only repeat a LIST that had already
    /// been retried, and would connect again doing it. When the socket has
    /// died and the reconnect fails, the inner retry leaves the client
    /// disconnected, which a retry at this level takes for a dropped
    /// socket: the connect `retryingIfDisconnected` refuses to repeat would
    /// be made twice, and a LOGIN refused without [AUTHENTICATIONFAILED]
    /// sent twice.
    func listMailboxes() async throws -> [Mailbox] {
        let listings = try await freshListing()
        let client = try await connected()

        // Unread count is a STATUS per folder, so this is N round trips.
        // Acceptable for the handful of folders one person has, and the
        // count is not decoration: it is what tells him there is something
        // new without opening anything.
        var unread: [String: Int] = [:]
        for l in listings where Self.isSelectable(l) {
            if let counts = try? await client.status(l.name, items: ["UNSEEN"]),
               let n = counts["UNSEEN"] {
                unread[l.name] = Int(n)
            }
        }
        return Self.mailboxes(from: listings, unread: unread)
    }

    /// The roles and the attribute table, from one LIST.
    private func learn(_ listings: [IMAPMailboxListing]) {
        var found: [Mailbox.Role: String] = [:]
        var byAttribute: [String: String] = [:]
        for l in listings {
            if let role = l.specialUse, found[role] == nil {
                // First wins: Gmail reports "[Gmail]/All Mail" as \All and we
                // map that to .archive, but if a real Archive folder also
                // exists we keep whichever LIST named first rather than
                // flip-flopping.
                found[role] = l.name
            }
            // Every attribute, not just the ones with a Role. Measured
            // against Gmail, LIST gives \All, \Drafts, \Important, \Sent,
            // \Junk, \Flagged (which is Starred) and \Trash — and INBOX with
            // no attribute at all beyond \HasNoChildren. That table is what
            // turns an X-GM-LABELS token back into a folder this app shows.
            for attribute in l.attributes {
                let key = attribute.lowercased()
                if byAttribute[key] == nil { byAttribute[key] = l.name }
            }
        }
        roleNames = found
        folderForAttribute = byAttribute
        listed = listings
    }

    /// \Noselect marks a container that holds folders but no mail —
    /// "[Gmail]" itself is one. Tapping it would be an error, so it is not
    /// offered, and it has no count to ask for.
    private static func isSelectable(_ listing: IMAPMailboxListing) -> Bool {
        !listing.attributes.contains { $0.caseInsensitiveCompare("\\Noselect") == .orderedSame }
    }

    /// The folder list the app shows, from LIST and whatever counts there
    /// are. A folder with no count reads 0.
    private static func mailboxes(from listings: [IMAPMailboxListing],
                                  unread: [String: Int]) -> [Mailbox] {
        var out: [Mailbox] = []
        for l in listings where isSelectable(l) {
            let delimiter = l.delimiter ?? "/"
            let components = delimiter.isEmpty ? [l.name] : l.name.components(separatedBy: delimiter)
            let depth = max(0, components.count - 1)
            let display = components.last ?? l.name
            out.append(Mailbox(id: l.name, name: display,
                               unreadCount: unread[l.name] ?? 0, role: l.specialUse, depth: depth))
        }

        // Inbox first, then the other well-known roles in a fixed order, then
        // everything else alphabetically. A folder list whose order changes
        // between launches is exactly what this product exists to prevent.
        let rank: [Mailbox.Role: Int] = [.inbox: 0, .drafts: 1, .sent: 2,
                                         .junk: 3, .trash: 4, .archive: 5]
        out.sort { a, b in
            let ra = a.role.flatMap { rank[$0] } ?? 100
            let rb = b.role.flatMap { rank[$0] } ?? 100
            if ra != rb { return ra < rb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return out
    }

    // MARK: - Listing messages

    func listMessages(in mailboxID: String, beforeUID: String?, limit: Int) async throws -> [MessageSummary] {
        try await retryingIfDisconnected {
            try await self.listMessagesOnce(in: mailboxID, beforeUID: beforeUID, limit: limit)
        }
    }

    private func listMessagesOnce(in mailboxID: String, beforeUID: String?, limit: Int) async throws -> [MessageSummary] {
        let client = try await connected()
        let name = try await resolve(mailboxID)
        // Parsed before anything is sent, and thrown rather than dropped: a
        // cursor from before a renumbering used to become nil, and nil
        // means "from the top", so the next page was the first page again,
        // cut from the new numbers.
        let cursor = try beforeUID.map(Self.parseID)

        // SEARCH ALL returns every UID ascending. One round trip, and it is
        // the only way to page by UID rather than by sequence number —
        // sequence numbers shift the moment anything is delivered or expunged,
        // which is precisely the bug that makes a list jump under a reader.
        //
        // Issued ONCE per listing, not once per page. `beforeUID == nil` is
        // "start again from the top" and is the only thing that re-reads it;
        // every page after that walks the same snapshot. Without this a
        // 20,000-message mailbox would re-download 20,000 UIDs for each
        // fifty it displayed, which is quadratic in the length of the
        // mailbox and paid entirely by the person scrolling.
        //
        // Reusing the snapshot also keeps the list STILL. Mail arriving
        // while he is reading back through last year must not renumber what
        // is under his thumb; it appears at the next refresh, which is when
        // he asked for it.
        let listing: IMAPMailboxUIDs
        let summaries: [MessageSummary]
        if let cursor {
            if let cached = await snapshot(of: name, client: client) {
                listing = cached
            } else {
                // Paging without a snapshot — only reachable if it was
                // dropped underneath us. Re-reading is correct and merely
                // costs the round trip the snapshot exists to avoid.
                listing = try await client.searchAll(in: name)
                uidListing[name] = listing
            }
            // A cursor from another numbering than the snapshot's names some
            // other letter in it, or none, so the page is refused rather than
            // cut from it.
            guard cursor.validity == listing.validity else { throw MailError.cannotConnect }

            summaries = try await page(olderThan: cursor.uid, in: listing, limit: limit,
                                       mailboxID: mailboxID, name: name, client: client)
        } else {
            // From the top: a folder he has just opened, or refreshed, with
            // nothing on screen until this lands. The SEARCH and the page's
            // FETCH go in one hold of the connection, ahead of work he did
            // not ask for, with a NOOP before them when the folder was
            // already open, so the SEARCH sees mail that has arrived since
            // (B-045); see `IMAPClient.page`.
            let opened = try await client.page(in: name, searching: ["ALL"]) { found in
                PageWindow.older(than: nil, in: found[0], limit: limit)
            }
            listing = opened.found[0]
            uidListing[name] = listing
            summaries = rows(from: opened.summaries, in: mailboxID, name: name,
                             validity: listing.validity)
        }
        // B-033: the session's identity, pinned with numbers rather than
        // read off glass. The SELECTed folder, its UIDVALIDITY, how many
        // messages the server says exist, and the Message-ID of the newest
        // row this listing drew — enough to match this session against one
        // real mailbox, server-side, beyond argument.
        let exists = await client.lastReport(for: name)?.exists ?? -1
        let newestID = summaries.first?.threadID ?? summaries.first?.id ?? "-"
        Diagnostics.log(.note, "SESSION-IDENT folder=\(name) "
                        + "uidv=\(listing.validity) "
                        + "exists=\(exists) "
                        + "uids=\(listing.uids.count) "
                        + "first-row=\(newestID) "
                        + "sender=\(summaries.first?.sender ?? "?")")
        return summaries
    }

    /// The snapshot a listing of `name` is paging through, unless the
    /// mailbox has been renumbered since it was taken.
    ///
    /// Renumbered, every UID remembered for it now names a different letter,
    /// or none, so the snapshot goes, and a page asked for from an old cursor
    /// is refused rather than cut from numbers that no longer mean what they
    /// did. The client's SELECTs are where a renumbering shows (see
    /// `IMAPClient.lastReport`); this used to be done by this actor's own
    /// SELECT, which the client now sends.
    private func snapshot(of name: String, client: IMAPClient) async -> IMAPMailboxUIDs? {
        let now = await client.lastReport(for: name)?.uidValidity
        // Read after the await, not before: another listing may have
        // replaced the snapshot meanwhile, and that one is not stale.
        guard let listing = uidListing[name] else { return nil }
        if let now, now != listing.validity {
            uidListing[name] = nil
            return nil
        }
        return listing
    }

    /// The upward half of the walk. See `PageWindow.newer`.
    func listMessages(in mailboxID: String, afterUID: String,
                      limit: Int) async throws -> [MessageSummary] {
        try await retryingIfDisconnected {
            try await self.listMessagesOnce(in: mailboxID, afterUID: afterUID, limit: limit)
        }
    }

    private func listMessagesOnce(in mailboxID: String, afterUID: String,
                                  limit: Int) async throws -> [MessageSummary] {
        let client = try await connected()
        let name = try await resolve(mailboxID)

        // Never re-reads the snapshot. Loading upward only ever happens
        // after a jump, which built the snapshot on its way in; re-reading
        // here would pick up mail that has arrived since and insert it above
        // him mid-scroll, which is the jumping-list bug the cache exists to
        // prevent.
        guard let listing = await snapshot(of: name, client: client),
              let cursor = try? Self.parseID(afterUID),
              cursor.validity == listing.validity else { return [] }

        do {
            return try await page(newerThan: cursor.uid, in: listing, limit: limit,
                                  mailboxID: mailboxID, name: name, client: client)
        } catch {
            // The fetch's own SELECT can be what finds the renumbering, when
            // it is the first thing sent after a reconnect. Then there is no
            // more to load above him, as when it was known beforehand, and
            // the list stops asking. Only then: anything else, a lost
            // connection above all, is thrown for the read retry to act on.
            guard let now = await client.lastReport(for: name)?.uidValidity,
                  now != listing.validity else { throw error }
            return []
        }
    }

    /// The `limit` letters of the snapshot below `cursor`, or every one left
    /// when there are fewer: a short page still means the oldest has been
    /// reached, and nothing else does.
    ///
    /// Some of the snapshot's UIDs may name nothing by now. It is taken when
    /// the list starts from the top, and a letter can leave the folder after
    /// that: binned or moved from the reading pane as a search hit below the
    /// pages loaded so far, as an All Mailboxes hit whose Inbox copy is down
    /// there, or by another client. The FETCH answers nothing for such a
    /// UID, and the page used to come back that much short, which the list
    /// takes for the end of the folder, so everything older was out of reach
    /// until the next Refresh. Now a page that comes back short asks for the
    /// UIDs after it, the shortfall at a time, until it is whole or the
    /// snapshot has run out, the way a search's page already does
    /// (`nextMergedPage`). The extra FETCH is paid only when a UID has gone.
    private func page(olderThan cursor: UInt32, in listing: IMAPMailboxUIDs, limit: Int,
                      mailboxID: String, name: String,
                      client: IMAPClient) async throws -> [MessageSummary] {
        var page: [MessageSummary] = []
        var below = cursor
        while page.count < limit {
            let uids = PageWindow.older(than: below, in: listing.uids, limit: limit - page.count)
            guard let oldest = uids.last else { break }
            page += try await summaries(for: uids, in: mailboxID, name: name,
                                        validity: listing.validity, client: client)
            below = oldest
        }
        return page
    }

    /// The same upward, after a date jump: a short page there means the
    /// newest has been reached, and the list stops asking.
    private func page(newerThan cursor: UInt32, in listing: IMAPMailboxUIDs, limit: Int,
                      mailboxID: String, name: String,
                      client: IMAPClient) async throws -> [MessageSummary] {
        var page: [MessageSummary] = []
        var above = cursor
        while page.count < limit {
            let uids = PageWindow.newer(than: above, in: listing.uids, limit: limit - page.count)
            guard let newest = uids.first else { break }
            page = try await summaries(for: uids, in: mailboxID, name: name,
                                       validity: listing.validity, client: client) + page
            above = newest
        }
        return page
    }

    /// One page of UIDs turned into rows.
    private func summaries(for uids: [UInt32], in mailboxID: String, name: String,
                           validity: UInt32,
                           client: IMAPClient) async throws -> [MessageSummary] {
        guard !uids.isEmpty else { return [] }
        let fetched = try await client.fetchSummaries(uids: uids, in: name, validity: validity)
        return rows(from: fetched, in: mailboxID, name: name, validity: validity)
    }

    /// Fetched summaries turned into rows, in the order they are given.
    ///
    /// Factored out of `listMessages` when the upward direction, the date
    /// jump and paged search all needed the identical twenty lines, and
    /// shared again by the binned half of a search, whose summaries arrive
    /// with its SEARCH. Sharing it is not tidiness: `rememberPreviewPart` and
    /// `countedFolders` are both easy to leave out of a copy, and leaving
    /// either out fails invisibly — blank previews, or a sidebar count that
    /// drifts.
    ///
    /// The addresses it notes are written out once, when the page is done,
    /// and not once per address. See `RecipientBook.note`.
    private func rows(from fetched: [IMAPFetchResult], in mailboxID: String, name: String,
                      validity: UInt32) -> [MessageSummary] {
        defer { recipients.flush() }
        return fetched.compactMap { r -> MessageSummary? in
            guard let uid = r.uid else { return nil }
            let env = r.envelope
            // Harvested here because it is FREE here. The list already asks
            // for ENVELOPE to draw a row, so every address he corresponds
            // with walks past this line anyway; the composer's autocomplete
            // is built out of it without a single extra round trip. See
            // `RecipientBook` for why this rather than the Contacts
            // framework.
            if let env {
                for a in env.from + env.to + env.cc {
                    recipients.note(address: a.address, name: a.name)
                }
            }
            let from = env?.from.first
            // B-033: the raw pairing, uid->sender, straight off the parsed
            // FETCH response — before threading, caching or display.
            if uid >= 15 {
                Diagnostics.log(.note, "PAIR uid=\(uid) sender=\(from?.formatted ?? "?") "
                                + "subject=\(env?.subject ?? "?")")
            }
            let id = Self.makeID(validity: validity, uid: uid)
            rememberPreviewPart(r.bodyStructure, for: id)
            return MessageSummary(
                id: id,
                mailboxID: mailboxID,
                sender: from?.formatted ?? "(unknown sender)",
                subject: env?.subject ?? "",
                preview: "",
                date: env?.date ?? r.internalDate ?? Date(timeIntervalSince1970: 0),
                isRead: r.isSeen,
                isFlagged: r.isFlagged,
                hasAttachment: r.bodyStructure.map(Self.hasAttachment) ?? false,
                threadID: r.threadID,
                countedFolderIDs: countedFolders(labels: r.labels, selected: name),
                attachments: r.bodyStructure.map(MIMEDecoder.listedAttachments(in:)) ?? [])
        }
    }

    // MARK: - Opening the folder at a day

    func messages(around date: Date, in mailboxID: String,
                  limit: Int) async throws -> MessageWindow? {
        try await retryingIfDisconnected {
            try await self.messagesOnce(around: date, in: mailboxID, limit: limit)
        }
    }

    private func messagesOnce(around date: Date, in mailboxID: String,
                              limit: Int) async throws -> MessageWindow? {
        let client = try await connected()
        let name = try await resolve(mailboxID)

        // Both SEARCHes and the window's FETCH go in one hold of the
        // connection, ahead of work he did not ask for (see
        // `IMAPClient.page`), and the snapshot is refreshed rather than
        // reused: a jump is him asking to be moved, so this is exactly the
        // moment it is safe to pick up mail that has arrived. Every page
        // loaded afterwards walks THIS snapshot. One hold is also what puts
        // the matches and the snapshot in one numbering: in two, a
        // reconnect could fall between them onto a renumbered folder, and
        // the anchor would be some other letter.
        let opened = try await client.page(in: name, searching: [IMAPDate.sentOnOrAfter(date), "ALL"]) {
            found in
            guard let anchor = PageWindow.anchor(forMatches: found[0], in: found[1]) else { return [] }
            return PageWindow.window(around: anchor, in: found[1], limit: limit).uids
        }
        let listing = opened.found[1]
        uidListing[name] = listing
        let validity = listing.validity

        // Worked out again from the same two lists, which is cheap and
        // cannot come out differently.
        guard let anchor = PageWindow.anchor(forMatches: opened.found[0].uids, in: listing.uids) else {
            return nil
        }
        let window = PageWindow.window(around: anchor, in: listing.uids, limit: limit)
        let rows = self.rows(from: opened.summaries, in: mailboxID, name: name, validity: validity)

        // The anchor can be dropped by `summaries` if the server declines to
        // FETCH it, which would silently scroll him to the wrong letter.
        let anchorID = Self.makeID(validity: validity, uid: anchor)
        let landedIndex = rows.firstIndex { $0.id == anchorID } ?? 0
        guard !rows.isEmpty else { return nil }

        return MessageWindow(messages: rows,
                             anchorIndex: landedIndex,
                             reachedNewest: window.reachedNewest,
                             reachedOldest: window.reachedOldest,
                             landedOn: rows[landedIndex].date)
    }

    /// Walks a BODYSTRUCTURE looking for anything the reader would call an
    /// attachment, so the paperclip can be shown without downloading a byte.
    private static func hasAttachment(_ part: MIMEPart) -> Bool {
        if part.isAttachment { return true }
        return part.children.contains(where: hasAttachment)
    }

    // MARK: - Which folders a message is counted in

    /// An X-GM-LABELS token, as the LIST attribute naming the same folder.
    ///
    /// Two of these are NOT the identity mapping and both were measured
    /// rather than assumed: Starred's folder is advertised as `\Flagged`,
    /// and Draft's as the plural `\Drafts`.
    private static let attributeForLabel: [String: String] = [
        "\\sent": "\\sent",
        "\\draft": "\\drafts",
        "\\starred": "\\flagged",
        "\\important": "\\important",
        "\\trash": "\\trash",
        "\\junk": "\\junk",
        "\\spam": "\\junk",
    ]

    /// Every folder whose unread count this message contributes to.
    ///
    /// The point of the whole exercise. In Gmail a folder is a LABEL and
    /// `\Seen` is a property of the MESSAGE, so reading one letter changes
    /// the unread count of every folder carrying it — typically Inbox,
    /// All Mail and Important at once. A counter that decremented only the
    /// folder on screen would leave the others permanently high, and since
    /// all eight rows are visible at all times it would produce states the
    /// server cannot even represent, like All Mail reading fewer unread than
    /// Inbox.
    ///
    /// Three rules, each measured against the live account:
    ///
    /// - The SELECTed folder's own label is absent from X-GM-LABELS, so it
    ///   has to be added back. The same message reads `()` from INBOX and
    ///   `("\Inbox")` from All Mail.
    /// - All Mail is not a label and never appears; every message is in it
    ///   implicitly.
    /// - Except that Trash and Spam are EXCLUSIVE. A message there is in no
    ///   other folder whatever its labels claim — verified with a trashed
    ///   message that still carried `\Starred` while Starred's STATUS
    ///   reported zero messages.
    private func countedFolders(labels: [String], selected: String) -> [String] {
        var out = [selected]

        let trash = roleNames[.trash]
        let junk = roleNames[.junk]
        if selected == trash || selected == junk { return out }

        for label in labels {
            let lower = label.lowercased()
            let name: String?
            if lower == "\\inbox" {
                name = roleNames[.inbox] ?? "INBOX"
            } else if let attribute = Self.attributeForLabel[lower] {
                name = folderForAttribute[attribute]
            } else if lower.hasPrefix("\\") {
                // A system label this build has never heard of. Skipping it
                // leaves one folder stale until the next refresh, which is
                // exactly where it was before any of this.
                name = nil
            } else {
                // A user label. Gmail names the folder after the label.
                name = label
            }
            if let name, !out.contains(name) { out.append(name) }
        }

        if let all = roleNames[.archive], !out.contains(all) { out.append(all) }
        return out
    }

    // MARK: - Previews

    /// How much of a plain-text body to pull for two lines of preview.
    ///
    /// Two lines is about 120 characters, but the fetch is counted in bytes
    /// *before* decoding: base64 inflates by a third, and real mail opens with
    /// blank lines, a "View this in your browser" line and a row of dashes
    /// before it says anything. 2 KB clears all of that with room to spare.
    private static let plainPreviewBytes = 2048

    /// And how much of an HTML one — four times as much, which is the honest
    /// price of this feature.
    ///
    /// The readable text of an HTML mail begins only after the doctype, the
    /// head and a stylesheet, and template stylesheets alone routinely run
    /// past 4 KB. A smaller window does not produce a shorter preview, it
    /// produces an empty one. At 8 KB a page of fifty HTML-only messages is
    /// 400 KB, which is why previews are a second pass behind the list rather
    /// than part of it, and why the plain alternative is always preferred when
    /// the sender sent one.
    private static let htmlPreviewBytes = 8192

    /// Bound on the remembered structures. Not a cache policy: the list asks
    /// for previews immediately after it lists, so anything dropped here is
    /// something nobody was going to ask for. Letting it grow instead would
    /// keep a MIME tree per message for the life of the session.
    private static let maximumRememberedParts = 500

    /// Insertion order, so the bound above can EVICT rather than empty.
    private var previewPartOrder: [String] = []

    private func rememberPreviewPart(_ structure: MIMEPart?, for id: String) {
        guard let structure, let part = MIMEDecoder.previewPart(structure) else { return }
        if previewParts[id] == nil { previewPartOrder.append(id) }
        previewParts[id] = part
        // Was `previewParts.removeAll()` — a total flush, not an eviction.
        // Tolerable while a folder was one page of fifty; not once a search
        // pages past its first hundred, because crossing the bound threw
        // away the parts for rows still ON SCREEN and blanked previews he
        // was reading. Drop the oldest instead: they are the ones furthest
        // from the window, and nobody is going to ask for them.
        while previewPartOrder.count > Self.maximumRememberedParts {
            previewParts.removeValue(forKey: previewPartOrder.removeFirst())
        }
    }

    /// One fetch per distinct section, not one per message.
    ///
    /// The section a preview lives in differs between messages — "1" for a
    /// plain letter, "1.1" for the usual plain/HTML pair — and a FETCH applies
    /// the same item to every UID in its set. So the page is grouped by the
    /// section (and window) it needs, which in practice is two or three
    /// commands for fifty messages rather than fifty.
    func previews(for ids: [String], in mailboxID: String) async throws -> [String: String] {
        try await retryingIfDisconnected {
            try await self.previewsOnce(for: ids, in: mailboxID)
        }
    }

    private func previewsOnce(for ids: [String], in mailboxID: String) async throws -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        let client = try await connected()
        let name = try await resolve(mailboxID)
        let known = await client.lastReport(for: name)?.uidValidity

        struct Request: Hashable {
            let validity: UInt32
            let section: String
            let byteCount: Int
        }

        var parts: [String: MIMEPart] = [:]
        var grouped: [Request: [UInt32]] = [:]

        for id in ids {
            // A message listed before the last refresh, or one whose mailbox
            // has been renumbered under us, simply has no preview. Both are
            // ordinary, so neither is an error. A renumbering nobody has seen
            // yet is found by the fetch's own SELECT, and the client sends
            // nothing for those.
            guard let part = previewParts[id], let message = try? Self.parseID(id),
                  known == nil || known == message.validity else { continue }
            if part.size == 0 { continue }
            parts[id] = part
            let isHTML = part.subtype == "html"
            grouped[Request(validity: message.validity, section: part.section,
                            byteCount: isHTML ? Self.htmlPreviewBytes : Self.plainPreviewBytes),
                    default: []].append(message.uid)
        }

        var out: [String: String] = [:]
        for (request, uids) in grouped {
            let bodies = try await client.fetchPartialBodies(
                uids: uids, section: request.section, byteCount: request.byteCount,
                in: name, validity: request.validity)
            for (uid, raw) in bodies {
                let id = Self.makeID(validity: request.validity, uid: uid)
                guard let part = parts[id] else { continue }
                let text = Self.preview(from: raw, part: part)
                if !text.isEmpty { out[id] = text }
            }
        }
        return out
    }

    /// Transfer-decode, charset-decode, then flatten to one line of words.
    ///
    /// The split-character trim has to happen between the first two steps: the
    /// fetch cut the body at a byte, so the *decoded* bytes are what ends
    /// mid-character, and handing that straight to the charset decoder makes
    /// the whole fragment fail UTF-8 and come back as mojibake.
    private static func preview(from raw: Data, part: MIMEPart) -> String {
        let bytes = PreviewText.trimmingSplitCharacter(
            MIMEDecoder.decodeTransfer(raw, encoding: part.encoding))
        // "8bit" because the transfer encoding has already been undone above.
        let text = MIMEDecoder.decodeText(bytes, encoding: "8bit",
                                          charset: MIMEDecoder.parameter("charset", in: part.parameters))
        return part.subtype == "html" ? PreviewText.fromHTML(text) : PreviewText.fromPlainText(text)
    }

    // MARK: - One message

    func loadMessage(id: String, mailboxID: String) async throws -> Message {
        try await retryingIfDisconnected {
            try await self.loadMessageOnce(id: id, mailboxID: mailboxID)
        }
    }

    private func loadMessageOnce(id: String, mailboxID: String) async throws -> Message {
        let client = try await connected()
        let name = try await resolve(mailboxID)
        let message = try Self.parseID(id)

        let raw = try await client.fetchBody(uid: message.uid, section: nil,
                                             in: name, validity: message.validity)
        lastBody = (id, raw)

        let decoded = MIMEDecoder.decodeMessage(raw)
        let headers = MIMEDecoder.parseHeaders(raw)
        func header(_ n: String) -> String? {
            MIMEDecoder.headerValue(n, in: headers).map(MIMEDecoder.decodeWord)
        }
        func addresses(_ n: String) -> [String] {
            (header(n) ?? "")
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        let fromHeader = header("From") ?? "(unknown sender)"
        return Message(
            id: id,
            mailboxID: mailboxID,
            sender: fromHeader,
            senderAddress: MailFormat.bareAddress(fromHeader),
            to: addresses("To"),
            cc: addresses("Cc"),
            bcc: addresses("Bcc"),
            subject: header("Subject") ?? "",
            date: Self.parseDate(header("Date")) ?? Date(),
            textBody: decoded.text,
            htmlBody: decoded.html,
            attachments: decoded.attachments,
            // Raw, not `decodeWord`ed: a Message-ID is an addr-spec, never an
            // encoded word, and running it through the decoder could only
            // corrupt an id that has to match byte for byte to thread.
            messageID: MIMEDecoder.headerValue("Message-ID", in: headers)?
                .trimmingCharacters(in: .whitespaces),
            references: MIMEDecoder.headerValue("References", in: headers)?
                .trimmingCharacters(in: .whitespaces))
    }

    private static let rfc2822: DateFormatter = {
        let f = DateFormatter()
        // en_US_POSIX or the month names are parsed in the device's language
        // and every date in the app silently becomes "now".
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return f
    }()

    private static let rfc2822NoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy HH:mm:ss Z"
        return f
    }()

    static func parseDate(_ text: String?) -> Date? {
        guard var s = text?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }
        // Strip a trailing "(GMT)"-style comment, which is legal and which
        // DateFormatter will not accept.
        if let paren = s.firstIndex(of: "(") { s = String(s[s.startIndex..<paren]) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return rfc2822.date(from: s) ?? rfc2822NoDay.date(from: s)
    }

    // MARK: - Flags

    func setRead(_ read: Bool, id: String, mailboxID: String) async throws {
        try await readyForWrite()
        let client = try await connected()
        let name = try await resolve(mailboxID)
        let message = try Self.parseID(id)
        try await client.store(uid: message.uid, flag: "\\Seen", set: read,
                               in: name, validity: message.validity)
    }

    func setFlagged(_ flagged: Bool, id: String, mailboxID: String) async throws {
        try await readyForWrite()
        let client = try await connected()
        let name = try await resolve(mailboxID)
        let message = try Self.parseID(id)
        try await client.store(uid: message.uid, flag: "\\Flagged", set: flagged,
                               in: name, validity: message.validity)
    }

    // MARK: - Moving and deleting

    func move(_ id: String, from sourceMailboxID: String, to destinationMailboxID: String) async throws {
        try await readyForWrite()
        let client = try await connected()
        let source = try await resolve(sourceMailboxID)
        let destination = try await resolve(destinationMailboxID)
        guard source != destination else { return }
        let message = try Self.parseID(id)
        try await client.move(uid: message.uid, from: source, validity: message.validity,
                              to: destination)
        // The message no longer exists at the old UID, so anything cached
        // against it is stale.
        if lastBody?.messageID == id { lastBody = nil }
    }

    /// Delete means "move to Trash" — except in Trash, where it means gone.
    ///
    /// The mock got this wrong in a way worth recording: it moved to the
    /// literal string "trash" unconditionally, so deleting something already
    /// in Trash moved it to Trash again and it reappeared at the top of the
    /// list. Here the destination is resolved from the \Trash special-use
    /// attribute, and deleting inside Trash marks \Deleted instead.
    func delete(_ id: String, from mailboxID: String) async throws {
        try await readyForWrite()
        let client = try await connected()
        let source = try await resolve(mailboxID)
        // Not `?? try await …` — `??`'s right side is an autoclosure, which
        // cannot be async or throwing.
        let trash: String
        if let known = roleNames[.trash] { trash = known }
        else { trash = try await resolve("trash") }

        if source == trash {
            let message = try Self.parseID(id)
            try await client.store(uid: message.uid, flag: "\\Deleted", set: true,
                                   in: source, validity: message.validity)
            return
        }
        try await move(id, from: mailboxID, to: trash)
    }

    // MARK: - Sending

    func send(_ draft: Draft) async throws {
        let recipients = (draft.to + draft.cc + draft.bcc)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !recipients.isEmpty else { throw MailError.notSent }

        // The threading headers, which used to be dropped on the floor.
        // `Draft.inReplyTo` was set faithfully by the compose screen and read
        // by nobody, so every reply this app sent went out with no
        // In-Reply-To and no References — verified on the wire. It appeared
        // to thread in Gmail only because Gmail falls back to matching
        // subject lines; Apple Mail, Outlook and Thunderbird thread on
        // References and would have started a new conversation every time.
        let raw = RFC5322Builder.build(draft: draft, from: account,
                                       inReplyToHeaders: Self.threadHeaders(for: draft),
                                       attachments: try await loadAttachments(for: draft),
                                       htmlBody: AppleMailHTML.part(for: draft, account: account),
                                       inlineImages: SignatureImages.parts())
        try await smtp.send(raw, from: account.address, to: recipients, password: password)
        // Only after the server took it. Ranking an address he tried and
        // failed to reach above one that works would put a bad address at
        // the top of the list.
        for address in draft.to + draft.cc + draft.bcc {
            self.recipients.used(address: MailFormat.bareAddress(address))
        }

        // No APPEND to Sent. Gmail files SMTP-sent mail into Sent itself, and
        // appending as well produces two copies of every letter he sends —
        // which looks exactly like the app sending twice.
    }

    /// Pulls the bytes for everything the draft is carrying.
    ///
    /// Throws rather than skipping a file it cannot fetch, and that is the
    /// whole point of the method. Sending the letter anyway would deliver a
    /// message whose text says "here is the receipt" with no receipt on it,
    /// and neither the sender nor the recipient would be told — the sender
    /// would see Send succeed. A failed send he can retry is strictly better
    /// than a successful send that quietly lost the enclosure.
    ///
    /// Usually free: the source message is still in `lastBody` from being
    /// displayed a moment ago, so `fetchAttachmentData` decodes it locally
    /// instead of going back to the server.
    private func loadAttachments(for draft: Draft) async throws
        -> [(filename: String, mimeType: String, data: Data)] {
        var loaded: [(filename: String, mimeType: String, data: Data)] = []
        loaded.reserveCapacity(draft.attachments.count)
        for attachment in draft.attachments {
            let data: Data
            switch attachment.source {
            case let .messagePart(messageID, mailboxID, section):
                data = try await fetchAttachmentData(section, of: messageID,
                                                     mailboxID: mailboxID)
            case let .localFile(url):
                // A photo he chose. Read at BUILD time rather than held in
                // the draft, so a composer left open for an hour is not
                // also holding several megabytes of image in memory.
                data = try Data(contentsOf: url)
            }
            loaded.append((filename: attachment.filename,
                           mimeType: attachment.mimeType,
                           data: data))
        }
        return loaded
    }

    /// `nil` for a fresh letter, so no In-Reply-To is written at all — a new
    /// message must not claim an ancestor.
    private static func threadHeaders(for draft: Draft) -> (messageID: String, references: String?)? {
        guard let parent = draft.inReplyTo?.trimmingCharacters(in: .whitespaces),
              !parent.isEmpty else { return nil }
        return (messageID: parent, references: draft.references)
    }

    @discardableResult
    func saveDraft(_ draft: Draft) async throws -> String? {
        try await readyForWrite()
        let client = try await connected()
        let drafts = try await draftsFolder()

        // Attachments are resolved for a saved draft too, so reopening one
        // from another client shows the files rather than a bare note
        // referring to them.
        //
        // Resolved BEFORE the old copy is removed, because a draft reopened
        // from the server carries attachments that live inside that very
        // copy: delete it first and the files it is carrying go with it.
        let loaded = try await loadAttachments(for: draft)
        let raw = RFC5322Builder.build(draft: draft, from: account,
                                       inReplyToHeaders: Self.threadHeaders(for: draft),
                                       attachments: loaded,
                                       includeBcc: true,
                                       // A draft is stored as the message it
                                       // will become, markup and all, so what
                                       // he sees on reopening is what will go.
                                       htmlBody: AppleMailHTML.part(for: draft, account: account),
                                       // The signature's pictures go with the
                                       // draft too: a draft is reopened by
                                       // parsing it back, and the parts are
                                       // what make its markup's cid: resolve.
                                       inlineImages: SignatureImages.parts())
        let appended = try await client.append(raw, to: drafts,
                                               flags: ["\\Draft", "\\Seen"])

        // Only once the replacement is safely on the server. The other
        // order risks deleting the only copy of a letter and then failing
        // to append, which loses work he cannot get back.
        if let old = draft.savedID {
            try? await deleteDraft(old)
        }
        guard let appended else { return nil }
        return Self.makeID(validity: appended.validity, uid: appended.uid)
    }

    func deleteDraft(_ id: String) async throws {
        try await readyForWrite()
        let client = try await connected()
        let name = try await resolve(try await draftsFolder())
        let draft = try Self.parseID(id)
        // Expunged, not moved to Trash. Now that an "All Mailboxes" search
        // reaches the Trash, a superseded draft binned rather than removed
        // would come back as a hit for every half-finished sentence he ever
        // saved.
        try await client.expunge(uid: draft.uid, in: name, validity: draft.validity)
        // The snapshot still lists the UID we just removed.
        uidListing[name] = nil
    }

    func loadDraft(id: String, mailboxID: String) async throws -> Draft {
        let message = try await loadMessage(id: id, mailboxID: mailboxID)
        return Draft(to: message.to,
                     cc: message.cc,
                     bcc: message.bcc,
                     subject: message.subject,
                     // `quotableText` rather than `textBody`, so a draft
                     // written in another client as HTML reopens with its
                     // words in it instead of empty.
                     body: message.textBody ?? message.quotableText,
                     attachments: message.attachments.map {
                         DraftAttachment(source: .messagePart(messageID: id,
                                                             mailboxID: mailboxID,
                                                             section: $0.id),
                                         filename: $0.filename,
                                         mimeType: $0.mimeType,
                                         size: $0.size)
                     },
                     savedID: id)
    }

    private func draftsFolder() async throws -> String {
        // Not `?? try await …` — `??`'s right side is an autoclosure, which
        // cannot be async or throwing.
        if let known = roleNames[.drafts] { return known }
        return try await resolve("drafts")
    }

    // MARK: - Search

    /// How much of Trash and Spam a single search will pull in eagerly.
    ///
    /// These two are fetched WHOLE at the start of a search rather than
    /// paged, because they cannot be paged alongside All Mail — their UIDs
    /// are not comparable with its. In a personal account a given term
    /// matches a handful of binned messages, so this bound is generous;
    /// past it, the oldest binned matches are dropped rather than the
    /// search becoming slow. Recorded in B-011.
    private static let maximumBinnedHits = 200

    /// Everything one in-progress search needs to answer "give me the next
    /// page" without going back to the server for what it already knows.
    ///
    /// Held rather than recomputed because an "All Mailboxes" search is
    /// THREE searches, and a merged stream has no cursor a caller could
    /// hand back: `beforeUID` names a message in one mailbox, and the next
    /// page may begin in a different one.
    private struct SearchSession {
        /// Mailbox name + criteria. A change to either is a new search.
        let key: String
        /// The folder All Mail hits are paged out of, and its UIDVALIDITY.
        let primaryID: String
        let primaryName: String
        let primaryValidity: UInt32
        /// Hits in the paged folder, ascending, walked by `PageWindow`.
        var primaryUIDs: [UInt32]
        /// The last paged-folder UID whose summary has been FETCHED.
        var primaryCursor: UInt32?
        /// Fetched from the paged folder but not yet emitted, because
        /// binned results were newer and took their place in the page.
        var buffered: [MessageSummary] = []
        /// Trash and Spam hits, fetched once, date-descending.
        var binned: [MessageSummary] = []
        /// Everything handed out so far, so re-asking for a page already
        /// given costs nothing and cannot double-advance the streams.
        var emitted: [MessageSummary] = []
        var primaryExhausted = false
    }

    private var searchSession: SearchSession?

    func search(in mailboxID: String, query: String, scope: MailSearchScope,
                beforeUID: String?, limit: Int) async throws -> [MessageSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try await listMessages(in: mailboxID, beforeUID: beforeUID, limit: limit)
        }
        // See `SearchCriteria` for which fields, and why TO and CC are
        // among them. Server-side rather than filtering the page already on
        // screen: searching only the visible 50 would quietly fail to find
        // the letter he is after.
        guard let criteria = SearchCriteria.imap(for: trimmed) else { return [] }

        // Safe to run twice: the session is written back only once a step
        // has fully succeeded, so a run cut short by a dead socket leaves
        // nothing half-advanced for the second one to trip over.
        //
        // A search cancelled by the next keystroke finishes the command it
        // had on the wire, then stops at the next cancellation check, in the
        // steps below or at the client's exchange gate, and throws
        // `CancellationError`. That includes a search whose last command
        // came back after the cancel: the list only discards a superseded
        // search's results once the replacement's debounce has run, so
        // results handed back in that gap would be drawn, and the session
        // they would have written is not his current search's either.
        return try await retryingIfDisconnected {
            try await self.searchOnce(in: mailboxID, criteria: criteria, scope: scope,
                                      beforeUID: beforeUID, limit: limit)
        }
    }

    private func searchOnce(in mailboxID: String, criteria: String, scope: MailSearchScope,
                            beforeUID: String?, limit: Int) async throws -> [MessageSummary] {
        // The paged folder. For "all mailboxes" that is Gmail's All Mail,
        // which holds everything except Trash and Spam; those two are
        // searched separately below because their UIDs cannot be compared
        // with its.
        let primaryID = (scope == .allMailboxes ? folderForAttribute["\\all"] : nil) ?? mailboxID
        let key = "\(primaryID)\u{0}\(scope.rawValue)\u{0}\(criteria)"

        if beforeUID == nil || searchSession?.key != key {
            let started = try await startSearch(key: key, primaryID: primaryID,
                                                criteria: criteria, scope: scope)
            try Task.checkCancellation()
            searchSession = started
        }
        guard searchSession != nil else { return [] }

        // Already answered. A re-ask for a page we have handed out must
        // replay it rather than advance the streams, or the page after it
        // would skip whatever the second call consumed.
        if let beforeUID, let known = replayEmitted(after: beforeUID, limit: limit) {
            return known
        }
        return try await nextMergedPage(limit: limit)
    }

    /// Runs the search in every mailbox the scope covers.
    ///
    /// All of them in one call to the client, which takes the gate once for
    /// the lot, so the search's commands go back to back instead of each
    /// queueing behind every other screen's (see `IMAPClient.search(_:across:)`).
    /// Trash and Spam FIRST, their summaries fetched while each is still
    /// selected, and the paged folder last, so that it is the one left
    /// selected for every page after this one.
    ///
    /// The summaries of the binned hits are fetched whole here, as B-011
    /// decided, not a page at a time as they are shown. Which binned hits a
    /// page shows depends on their dates, and a date comes only with the
    /// summary: ENVELOPE's, which is the merge key, falling back to
    /// INTERNALDATE. Fetching dates first and summaries later would mean a
    /// second source for that key that has to agree with the first to the
    /// second, or the merge reorders or repeats hits across a page boundary,
    /// plus a SELECT of Trash or Spam and back in the middle of paging All
    /// Mail. For the handful of binned hits a term finds in a personal
    /// account that is more round trips, not fewer.
    ///
    /// A Trash that will not open is swallowed on purpose: it must not cost
    /// him the All Mail results as well. Losing the binned half of a search
    /// is a gap, losing all of it is the feature not working. The client
    /// hands such a mailbox back with no hits.
    ///
    /// A dead connection and a cancelled search are not swallowed. Both
    /// used to be, and each did its own damage. After a dropped socket the
    /// Trash hits vanished without a word while the Spam search quietly
    /// reconnected, so the first search after picking the iPad up could
    /// simply not find a letter he had binned. And a search cancelled by
    /// the next keystroke carried on into Spam and All Mail, reconnecting
    /// for each. Thrown, the first is repeated whole by the read retry
    /// around `search`, and the second stops where it is.
    ///
    /// A cancelled search is reported as cancelled whatever else went wrong
    /// on the way, a Trash refused or the connection lost while the cancel
    /// landed included. Nobody is waiting to hear about either, and
    /// `CancellationError` is the one answer the list knows to leave the
    /// screen alone for.
    private func startSearch(key: String, primaryID: String, criteria: String,
                             scope: MailSearchScope) async throws -> SearchSession? {
        let client = try await connected()
        let primary = try await resolve(primaryID)

        var targets: [IMAPSearchTarget] = []
        if scope == .allMailboxes {
            for attribute in ["\\trash", "\\junk"] {
                guard let folder = folderForAttribute[attribute] else { continue }
                targets.append(IMAPSearchTarget(mailbox: folder,
                                                summariesOfNewest: Self.maximumBinnedHits))
            }
        }
        targets.append(IMAPSearchTarget(mailbox: primary, summariesOfNewest: 0))

        let searched = try await client.search(criteria, across: targets)
        try Task.checkCancellation()
        // The paged folder refusing is the search failing, not a gap in it.
        guard let found = searched.last?.hits else { throw MailError.cannotConnect }

        var binned: [MessageSummary] = []
        for folder in searched.dropLast() {
            guard let hits = folder.hits else { continue }
            binned += rows(from: folder.summaries, in: folder.mailbox, name: folder.mailbox,
                           validity: hits.validity)
        }
        binned.sort(by: SearchMerge.isOrderedBefore)

        return SearchSession(key: key, primaryID: primaryID, primaryName: primary,
                             primaryValidity: found.validity,
                             primaryUIDs: found.uids, primaryCursor: nil,
                             binned: binned, primaryExhausted: found.uids.isEmpty)
    }

    /// Replays a page already handed out, if `beforeUID` names something
    /// other than the last thing emitted.
    private func replayEmitted(after beforeUID: String, limit: Int) -> [MessageSummary]? {
        guard let session = searchSession,
              let index = session.emitted.firstIndex(where: { $0.id == beforeUID }),
              index + 1 < session.emitted.count else { return nil }
        return Array(session.emitted[(index + 1)...].prefix(limit))
    }

    /// The next page of the merged stream, fetching from the paged folder
    /// only when the merge actually runs out of it.
    private func nextMergedPage(limit: Int) async throws -> [MessageSummary] {
        guard var session = searchSession else { return [] }
        var page: [MessageSummary] = []

        while page.count < limit {
            if session.buffered.isEmpty && !session.primaryExhausted {
                let next = PageWindow.older(than: session.primaryCursor,
                                            in: session.primaryUIDs, limit: limit)
                if next.isEmpty {
                    session.primaryExhausted = true
                } else {
                    let client = try await connected()
                    // The session's UIDs are in the numbering it started
                    // with. If the folder has been renumbered since, a
                    // reconnect's SELECT is where that shows, and fetching
                    // the old numbers would drop hits or return other
                    // letters. The client refuses with nothing sent; a new
                    // search starts clean.
                    session.buffered = try await summaries(
                        for: next, in: session.primaryID, name: session.primaryName,
                        validity: session.primaryValidity, client: client)
                    try Task.checkCancellation()
                    session.primaryCursor = next.last
                    // A short walk means the UID list is spent, but the
                    // rows it produced still have to be merged out.
                    if next.count < limit { session.primaryExhausted = true }
                    if session.buffered.isEmpty { continue }
                }
            }

            let merged = SearchMerge.take(limit - page.count,
                                          from: session.buffered,
                                          primaryExhausted: session.primaryExhausted,
                                          and: session.binned)
            session.buffered = merged.primary
            session.binned = merged.secondary
            page += merged.taken
            if merged.taken.isEmpty { break }
        }

        session.emitted += page
        // Also reachable with no await at all, when the page is merged from
        // what earlier pages fetched, so checked here and not only above.
        try Task.checkCancellation()
        searchSession = session
        return page
    }

    // MARK: - Attachments

    /// The attachment as a FILE — transfer-decoded, ready to write to disk or
    /// hang off an outgoing message.
    ///
    /// The decoding step is the whole point and it used to be missing. A MIME
    /// part is stored base64- or quoted-printable-encoded, and both the
    /// cached path and `BODY[2]` hand back the bytes exactly as they sit in
    /// the message. This method had no callers until forwarding became one,
    /// so nothing had ever noticed: the first forward of a receipt attached a
    /// base64 *transcript* of a PDF, wrapped in a second layer of base64 by
    /// the builder. It arrived at 44782 bytes beginning "JVBER" where a PDF
    /// begins "%PDF", and no reader on earth would open it.
    ///
    /// `Attachment.id` is the MIME section path, so a part can still be
    /// pulled on its own rather than by re-downloading the message it is in.
    func fetchAttachmentData(_ attachmentID: String, of messageID: String, mailboxID: String) async throws -> Data {
        if let cached = lastBody, cached.messageID == messageID {
            let parsed = MIMEDecoder.parse(cached.raw)
            if let bytes = parsed.bodies[attachmentID],
               let part = MIMEDecoder.part(at: attachmentID, in: parsed.structure) {
                return MIMEDecoder.decodeTransfer(bytes, encoding: part.encoding)
            }
        }

        let client = try await connected()
        let name = try await resolve(mailboxID)
        let message = try Self.parseID(messageID)

        // The structure first, because a section fetch returns bytes with no
        // hint of how they are wrapped. Refusing when it cannot be read is
        // deliberate: guessing base64 would shred a 7bit text part, and
        // guessing 7bit is exactly the bug above. A failure the user can
        // retry beats a file that silently is not the file. The client
        // refuses before it asks for the bytes.
        guard let fetched = try await client.fetchPart(
            uid: message.uid, section: attachmentID, in: name, validity: message.validity,
            describedBy: { MIMEDecoder.part(at: attachmentID, in: $0) }) else {
            throw MailError.attachmentFailed
        }

        let part = fetched.part
        let raw = fetched.bytes
        guard !raw.isEmpty else { throw MailError.attachmentFailed }
        let decoded = MIMEDecoder.decodeTransfer(raw, encoding: part.encoding)
        guard !decoded.isEmpty else { throw MailError.attachmentFailed }
        return decoded
    }
}
