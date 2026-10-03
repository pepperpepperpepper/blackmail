import Foundation
@testable import Blackmail

/// A Gmail-shaped IMAP server held in memory, and the transport the real
/// clients reach it through.
///
/// Built so that `IMAPClient` and `IMAPMailRepository` run on the host
/// exactly as they run on the iPad, with only the socket swapped: the
/// repository is handed `transportFactory` where the app hands it
/// `TLSConnection.factory`, and everything above that line is shipping code.
/// That is what lets a test say "this flow sends these commands, in this
/// mailbox" about the product rather than about a copy of it.
///
/// The replies are modelled on what `IMAPParser` and `IMAPClient` actually
/// read, and on what Gmail was measured to send: the greeting, both
/// capability lists, LIST with special-use attributes, SELECT's untagged
/// flood, FETCH items with UID always present, and literals for every body
/// and for any envelope string a quoted string cannot carry. Only as much
/// IMAP as the repository sends is here. Anything else is answered BAD, as
/// Gmail answers it, so a command the fake does not know fails loudly
/// instead of quietly passing.
///
/// Deterministic by default: a reply is ready the instant its command is
/// written, with no real delay. `holdReplies(to:)` keeps a reply back until
/// the test lets it go, for a test that needs one still in flight while
/// something else happens; `defaultDelay` and `delays` add a few milliseconds
/// of real delay where the only question is ordering.
///
/// It also watches the client. This client never has two commands in flight
/// on one connection, so a command written before the previous reply has
/// been read, or two reads waiting at once, means the exchange gate in
/// `IMAPClient` was not held. Either is recorded in `violations`, and the
/// second read fails at once rather than waiting for bytes that the first
/// will take.
///
/// Gmail's rules that the repository leans on are kept:
///
/// - UIDs are per mailbox and sparse, so a sequence number is never a valid
///   UID by accident, and the same letter has different UIDs in INBOX and
///   All Mail.
/// - Flags belong to the letter and show in every mailbox holding it;
///   `\Deleted` alone is per mailbox.
/// - X-GM-LABELS leaves out the mailbox it is fetched from.
/// - Trash and Spam are exclusive: moving a letter into either takes it out
///   of everything else. Moving out of All Mail keeps it in All Mail.
/// - A UID command with no mailbox selected on that connection is BAD.
/// - A connection's SEARCH and FETCH answer from what it has been told of
///   the mailbox it has selected. Mail that `arrive`s is not in them until
///   an EXISTS has announced it, on a NOOP or riding on a UID FETCH, and a
///   letter taken out elsewhere stays in them until a NOOP's EXPUNGE.
/// - Auto-Expunge is off, as in the test account's IMAP settings (B-062):
///   a STORE of `\Deleted` marks the letter and leaves it where it is,
///   listed, searched and fetched as before; UID EXPUNGE removes the
///   marked letters it names and no other; plain EXPUNGE removes every
///   marked letter in the mailbox. Expunged from Trash, Spam or Drafts a
///   letter is gone from Gmail altogether. `autoExpunge` turns it on,
///   Gmail's default, where the STORE removes the letter itself.
///
/// Not modelled: Starred follows `\Flagged` on Gmail, here it is fixed at
/// delivery; an APPENDed letter is described as one text part whatever its
/// Content-Type says.
final class ScriptedIMAPServer: @unchecked Sendable {

    // MARK: - The mailboxes

    static let inbox = "INBOX"
    static let allMail = "[Gmail]/All Mail"
    static let drafts = "[Gmail]/Drafts"
    static let sent = "[Gmail]/Sent Mail"
    static let spam = "[Gmail]/Spam"
    static let starred = "[Gmail]/Starred"
    static let trash = "[Gmail]/Trash"

    /// The seeded Inbox's newest letter is dated this. Fixed rather than
    /// "now", so a date-based test lands on the same letter wherever and
    /// whenever it runs.
    static let newestDate = Date(timeIntervalSince1970: 1_790_000_000)

    static let owner = Address(name: nil, address: "owner@example.com")
    static let sam = Address(name: "Sam Example", address: "sam@example.com")
    static let carlo = Address(name: "Carlo", address: "carlo@example.org")
    static let jane = Address(name: nil, address: "jane@example.com")

    struct Address: Equatable {
        var name: String?
        var address: String

        var formatted: String { name.map { "\($0) <\(address)>" } ?? address }
    }

    /// One letter as it is delivered. The server renders the raw message,
    /// the sections and the BODYSTRUCTURE from this, so all three agree.
    struct Letter: Equatable {
        var from: Address
        var to: [Address]
        var cc: [Address] = []
        /// Its Bcc, as a draft's carries one and Gmail's copy in Sent Mail
        /// may: in the ENVELOPE's sixth list and a `Bcc:` header.
        var bcc: [Address] = []
        var subject: String
        var date: Date
        /// The plain body. Nil makes an HTML-only letter.
        var text: String?
        /// An HTML body. Together with `text` it makes multipart/alternative.
        var html: String?
        var flags: Set<String> = []
        var messageID: String
        var inReplyTo: String?
        /// Its References header, written as given; none when nil, as
        /// every seeded letter has none.
        var references: String? = nil
        /// Files after the words, which make it multipart/mixed.
        var files: [File] = []
        /// The Message-ID of a letter already here whose conversation this
        /// one joins, as Gmail threads a reply: the two carry one
        /// X-GM-THRID. Nil for a conversation of its own, as every seeded
        /// letter is.
        var joins: String?
        /// When Gmail took it, its INTERNALDATE, which SINCE, BEFORE and ON
        /// search: nil for the moment its Date says, as every seeded letter
        /// arrives. Set apart for a letter delayed, or one dated wrong.
        var arrived: Date? = nil

        /// Its Reply-To header, an address each: none for a letter without
        /// one, whose ENVELOPE then carries the From in its place, as RFC
        /// 3501 has a server do.
        var replyTo: [Address] = []

        /// Its authors after `from`, for a letter written by several, whose
        /// From then names them all, `from` first, and so do its ENVELOPE's
        /// from, sender and, with no Reply-To, reply-to, as RFC 3501 has a
        /// server fill them for a letter with no Sender. None for nearly
        /// every letter.
        var alsoFrom: [Address] = []

        /// Everyone in its From.
        var authors: [Address] { [from] + alsoFrom }

        /// INTERNALDATE: when it arrived.
        var arrival: Date { arrived ?? date }
    }

    /// A file carried by a letter, base64 on the wire.
    struct File: Equatable {
        var name: String
        /// Upper case, as BODYSTRUCTURE spells them: "APPLICATION", "PDF".
        var type: String
        var subtype: String
        var bytes: Data
        /// A picture the body shows by `cid:`, sent inline under this id.
        /// Nil for a file sent as an attachment.
        var contentID: String?
    }

    /// One command as the server received it.
    struct LogEntry: Equatable, CustomStringConvertible {
        let connection: Int
        /// The mailbox selected on that connection when the command arrived,
        /// which for a SELECT is the one it is leaving.
        let selected: String?
        /// The command without its tag, e.g. `UID FETCH 1004 (UID BODY.PEEK[])`.
        let command: String
        /// The tagged answer, "OK", "NO" or "BAD"; nil if none was sent.
        var status: String?

        /// `SELECT`, `UID FETCH`, `LOGIN`: what `delays` is keyed by.
        var verb: String { ScriptedIMAPServer.verb(of: command) }
        var isUIDCommand: Bool { verb.hasPrefix("UID ") }

        var description: String {
            "c\(connection) [\(selected ?? "-")] \(command) -> \(status ?? "no answer")"
        }
    }

    /// Where LOGIN's success puts the post-login capability list.
    enum LoginCapabilities {
        /// `a002 OK [CAPABILITY …] … authenticated (Success)`, as Gmail does.
        case inTaggedOK
        /// A separate `* CAPABILITY …` line before a bare tagged OK.
        case untagged
        /// Nowhere; the client has to ask.
        case omitted
    }

    /// The first line on a new connection.
    enum Greeting {
        /// `* OK Gimap ready …`, as Gmail greets.
        case ready
        /// `* PREAUTH …`: logged in before any command, so LOGIN is refused.
        /// With `announcingCapabilities` the post-login list rides the
        /// greeting as a `[CAPABILITY …]` code; without it the client has to
        /// ask. Gmail never does this.
        case preauthenticated(announcingCapabilities: Bool)
    }

    let username: String
    /// The app password LOGIN takes; see `replacePassword`.
    var password: String { locked { $0.password } }
    /// The only port that accepts a connection. SMTP's 465 is refused, so a
    /// repository test that reaches `send` fails to connect rather than
    /// having an SMTP client read an IMAP greeting.
    let port: UInt16 = 993

    /// The account that logs in to this server.
    var account: MailAccount {
        MailAccount(address: username, imapPort: port, username: username)
    }

    /// Hand this to `IMAPClient` or `IMAPMailRepository` in place of
    /// `TLSConnection.factory`.
    var transportFactory: MailTransportFactory {
        { [self] _, port in
            let transport = ScriptedTransport(server: self, port: port)
            locked { s in
                s.transports[transport.connection] = WeakTransport(transport: transport)
                s.made.append(WeakTransport(transport: transport))
            }
            return transport
        }
    }

    private let lock = NSLock()
    private var state: State

    /// A Gmail account with `inboxCount` letters in the Inbox, one a day up
    /// to `newestDate`, plus a little Sent, Drafts, Trash, Spam and Starred.
    /// Every letter but Trash's and Spam's is in All Mail too.
    ///
    /// Inbox letter `i` (1 is the oldest) is "Letter i: <topic>", from Sam,
    /// Carlo or Jane in turn, about one of five topics. Every fifth is HTML
    /// only, every third of the rest also has an HTML alternative, every
    /// eleventh is flagged and starred, the newest six are unread, and the
    /// second newest has quotes in its subject so its envelope needs a
    /// literal.
    init(username: String = "owner@example.com", password: String = "app-password",
         inboxCount: Int = 120) {
        self.username = username
        state = State(username: username, password: password)
        locked { s in
            s.addFolder(Self.inbox, attributes: ["\\HasNoChildren"], label: "\\Inbox",
                        validity: 600_001, firstUID: 1_000)
            s.addFolder("[Gmail]", attributes: ["\\HasChildren", "\\Noselect"], label: nil,
                        validity: 0, firstUID: 1, selectable: false)
            s.addFolder(Self.allMail, attributes: ["\\All", "\\HasNoChildren"], label: nil,
                        validity: 600_002, firstUID: 5_000)
            s.addFolder(Self.drafts, attributes: ["\\Drafts", "\\HasNoChildren"], label: "\\Draft",
                        validity: 600_003, firstUID: 300)
            s.addFolder(Self.sent, attributes: ["\\HasNoChildren", "\\Sent"], label: "\\Sent",
                        validity: 600_004, firstUID: 700)
            s.addFolder(Self.spam, attributes: ["\\HasNoChildren", "\\Junk"], label: "\\Spam",
                        validity: 600_005, firstUID: 40)
            s.addFolder(Self.starred, attributes: ["\\Flagged", "\\HasNoChildren"], label: "\\Starred",
                        validity: 600_006, firstUID: 60)
            s.addFolder(Self.trash, attributes: ["\\HasNoChildren", "\\Trash"], label: "\\Trash",
                        validity: 600_007, firstUID: 80)
            // Delivered oldest first so every mailbox's UIDs rise with date,
            // and with a gap after each so UIDs are sparse.
            let seed = Self.seed(inboxCount: inboxCount).sorted { $0.0.date < $1.0.date }
            for (letter, mailboxes) in seed {
                let key = s.store(letter)
                for name in mailboxes { s.file(key, in: name, gap: 1) }
            }
        }
    }

    // MARK: - Fault injection

    /// Stops answering, greeting included. Commands still reach the log;
    /// no reply ever comes back. What a read then does is what the device's
    /// read does, see `timeout`.
    var isSilent: Bool {
        get { locked { $0.isSilent } }
        set { locked { $0.isSilent = newValue } }
    }

    /// Kills every connection open right now, the way a socket dies while
    /// the iPad sleeps: the next write on it appears to succeed and goes
    /// nowhere (see `lostWrites`), and every read fails with `error`, a read
    /// already waiting included, as an RST wakes a pending receive. Replies
    /// still on their way are lost with it. POSIX 54 is ECONNRESET;
    /// `.closed` is a peer that hung up cleanly.
    func resetConnections(with error: MailTransportError = .posix("POSIX 54")) async {
        let live: [ScriptedTransport] = locked { s in
            for id in s.sessions.keys { s.sessions[id]?.reset = error }
            return s.sessions.keys.sorted().compactMap { s.transports[$0]?.transport }
        }
        for transport in live { await transport.interrupt(with: error) }
    }

    /// Keeps every reply to `verb` (`"UID SEARCH"`) from reaching the client
    /// until `releaseReplies(to:)`. The command is received, logged and
    /// carried out as usual; only its answer waits, which is a reply still
    /// in flight for exactly as long as the test wants and no longer.
    func holdReplies(to verb: String) {
        locked { s in _ = s.held.insert(verb) }
    }

    /// Stops holding replies to `verb` from now on, and leaves the ones
    /// already held where they are, for good: the connections they were
    /// sent on belong to a launch the test has let die mid-command, as a
    /// crash leaves it, and an answer reaching them would bring it back.
    func stopHolding(_ verb: String) {
        locked { s in _ = s.held.remove(verb) }
    }

    /// How many replies to `verb` are being held right now, across every
    /// connection: kept from their clients, not merely asked for. A command
    /// is in the log before its reply is held, and `stopHolding` in that gap
    /// lets the reply through.
    func heldReplies(to verb: String) async -> Int {
        let live: [ScriptedTransport] = locked { s in
            s.sessions.keys.sorted().compactMap { s.transports[$0]?.transport }
        }
        var count = 0
        for transport in live { count += await transport.parkedReplies(to: verb) }
        return count
    }

    /// How many connections have a read waiting on the link for bytes
    /// right now: a client that has read all it was sent and is in the
    /// silence before the next. How a test knows the read for the rest of
    /// a reply has begun before it moves a clock or lets the rest go.
    func readsWaiting() async -> Int {
        let live: [ScriptedTransport] = locked { s in
            s.sessions.keys.sorted().compactMap { s.transports[$0]?.transport }
        }
        var count = 0
        for transport in live {
            if await transport.isAwaitingBytes { count += 1 }
        }
        return count
    }

    /// Lets everything held for `verb` go, in the order it was sent, and
    /// stops holding.
    func releaseReplies(to verb: String) async {
        let live: [ScriptedTransport] = locked { s in
            s.held.remove(verb)
            return s.sessions.keys.sorted().compactMap { s.transports[$0]?.transport }
        }
        for transport in live { await transport.releaseParked() }
    }

    /// Renumbers a mailbox the way a server rebuilding it does: a new
    /// UIDVALIDITY, and every letter in it filed again from `firstUID` up,
    /// oldest first. A `firstUID` below the old numbers means an old UID
    /// now names a different letter, which is the case worth testing.
    func renumber(_ mailbox: String, validity: UInt32, firstUID: UInt32) {
        locked { s in
            let name = Self.canonical(mailbox)
            guard var folder = s.folders[name] else { return }
            let keys = folder.uids.compactMap { folder.keys[$0] }
            folder.uidValidity = validity
            folder.uids = []
            folder.keys = [:]
            folder.deleted = []
            folder.uidNext = firstUID
            for key in keys {
                let uid = folder.uidNext
                folder.uids.append(uid)
                folder.keys[uid] = key
                folder.uidNext += 2
            }
            s.folders[name] = folder
        }
    }

    /// Real delay before each reply, by verb (`"UID FETCH"`, `"SELECT"`).
    /// Replies on one connection still arrive in order: a reply waits for
    /// the one before it. Keep these to a few milliseconds.
    var delays: [String: Duration] {
        get { locked { $0.delays } }
        set { locked { $0.delays = newValue } }
    }

    /// The delay for any verb not in `delays`, and for the greeting.
    var defaultDelay: Duration {
        get { locked { $0.defaultDelay } }
        set { locked { $0.defaultDelay = newValue } }
    }

    var loginCapabilities: LoginCapabilities {
        get { locked { $0.loginCapabilities } }
        set { locked { $0.loginCapabilities = newValue } }
    }

    /// Applies to connections opened after it is set.
    var greeting: Greeting {
        get { locked { $0.greeting } }
        set { locked { $0.greeting = newValue } }
    }

    /// The account's app password revoked and a new one made, as at
    /// myaccount.google.com/apppasswords: every LOGIN from now on with the
    /// old one is refused as a wrong password, and `new` is taken.
    /// Connections already logged in carry on.
    func replacePassword(with new: String) {
        locked { $0.password = new }
    }

    /// Every LOGIN from now on is refused as a wrong password, the way
    /// Gmail refuses an app password revoked since the session began.
    /// Connections already logged in carry on.
    var passwordRevoked: Bool {
        get { locked { $0.passwordRevoked } }
        set { locked { $0.passwordRevoked = newValue } }
    }

    /// What a refused LOGIN says after its NO. Gmail's for a wrong password
    /// by default; Gmail also refuses with `[ALERT]` and `[UNAVAILABLE]`,
    /// which say nothing about the password.
    var loginRefusal: String {
        get { locked { $0.loginRefusal } }
        set { locked { $0.loginRefusal = newValue } }
    }

    /// Verbs answered NO on a connection that stays up, as Gmail answers a
    /// command now and then with `[UNAVAILABLE]`: `["UID SEARCH"]`.
    var refusedVerbs: Set<String> {
        get { locked { $0.refusedVerbs } }
        set { locked { $0.refusedVerbs = newValue } }
    }

    /// Gmail's IMAP setting "When I mark a message in IMAP as deleted":
    /// off by default here, "Wait for the client to update the server", as
    /// the test account has it. On, "Auto-Expunge on", Gmail's own default,
    /// a STORE that sets `\Deleted` removes each letter it marks as an
    /// EXPUNGE would, with an EXPUNGE for each in the STORE's own answer.
    /// What Gmail sends then was not measured: the test account has it off.
    var autoExpunge: Bool {
        get { locked { $0.autoExpunge } }
        set { locked { $0.autoExpunge = newValue } }
    }

    /// Mailboxes that LIST still names but that SELECT and EXAMINE answer
    /// NO, the way a folder deleted from another client looks until the next
    /// LIST. Canonical names, e.g. `ScriptedIMAPServer.trash`.
    var refusedMailboxes: Set<String> {
        get { locked { $0.refusedMailboxes } }
        set { locked { $0.refusedMailboxes = newValue } }
    }

    /// Mailboxes Gmail's "Show in IMAP" has been turned off for: LIST does
    /// not name them, and SELECT, EXAMINE and STATUS answer NO, as for a
    /// mailbox that does not exist. Canonical names.
    var unlistedMailboxes: Set<String> {
        get { locked { $0.unlistedMailboxes } }
        set { locked { $0.unlistedMailboxes = newValue } }
    }

    /// Search keys a UID SEARCH is answered BAD for, as by a server that
    /// does not know them: `["HEADER"]`. Upper case.
    var refusedSearchKeys: Set<String> {
        get { locked { $0.refusedSearchKeys } }
        set { locked { $0.refusedSearchKeys = newValue } }
    }

    /// A UID SEARCH with `RETURN (…)` answered NO, as by a server that
    /// advertises ESEARCH and will not do it now; the same SEARCH without
    /// RETURN is answered as ever.
    var refusesSearchReturn: Bool {
        get { locked { $0.refusesSearchReturn } }
        set { locked { $0.refusesSearchReturn = newValue } }
    }

    /// A UID SEARCH with `RETURN (…)` answered as if RETURN were not there,
    /// with a plain `* SEARCH` line of every UID matched, as by a server
    /// that advertises ESEARCH and takes no notice of it.
    var ignoresSearchReturn: Bool {
        get { locked { $0.ignoresSearchReturn } }
        set { locked { $0.ignoresSearchReturn = newValue } }
    }

    /// The result items an ESEARCH answer gives after `UID`, made from the
    /// UIDs matched, ascending, in place of the ones RETURN asked for:
    /// `{ "COUNT \($0.count)" }` for a server that answers the count when
    /// asked for the lowest. Nil answers as RFC 4731 has it.
    var esearchItems: (@Sendable ([UInt32]) -> String)? {
        get { locked { $0.esearchItems } }
        set { locked { $0.esearchItems = newValue } }
    }

    /// A UID SEARCH with `CHARSET` answered BAD, as by a server that will
    /// not take the argument; the same SEARCH without it is answered as
    /// ever.
    var refusesCharset: Bool {
        get { locked { $0.refusesCharset } }
        set { locked { $0.refusesCharset = newValue } }
    }

    /// Verbs whose replies come in two chunks: the untagged lines, and then
    /// the tagged line as a reply of its own, named `completion(of:)` for
    /// `holdReplies(to:)`, so a test can hold the answer's end apart from
    /// its start. A reply that is nothing but its tagged line is one chunk.
    var completesApart: Set<String> {
        get { locked { $0.completesApart } }
        set { locked { $0.completesApart = newValue } }
    }

    /// The name the tagged line of a reply to `verb` goes by, for
    /// `holdReplies(to:)`, when `completesApart` names the verb.
    static func completion(of verb: String) -> String { verb + " completion" }

    /// The transport's ordinary deadline, in place of `TLSConnection`'s 30
    /// seconds: for the connect, for each read of an ordinary reply, and for
    /// each piece of a write.
    ///
    /// Everything that decides what a deadline does is the device's own
    /// code, `LinkTransport`, so this deadline does exactly what the
    /// device's does and no more. A peer that says nothing for this long is
    /// cut off: the connection is closed, which fails the receive left
    /// waiting on it, and the read fails with `.timedOut`. A read made by a
    /// task that is then cancelled is not cut off; it gets its reply. Nothing
    /// here has its own opinion about either, so when that code changes
    /// these tests see the change.
    var timeout: Duration {
        get { locked { $0.timeout } }
        set { locked { $0.timeout = newValue } }
    }

    /// `timeout` for connection `id` alone, every other connection keeping
    /// the one they share: a socket that stalls cut off quickly, and the
    /// connection that replaces it given the usual deadline, however long
    /// the test then takes to let its replies go.
    func setTimeout(_ timeout: Duration, on id: Int) {
        locked { $0.timeouts[id] = timeout }
    }

    fileprivate func timeout(on id: Int) -> Duration {
        locked { $0.timeouts[id] ?? $0.timeout }
    }

    /// The deadline for the reply to an upload (`ReplyWait.afterUpload`), in
    /// place of `TLSConnection`'s ten minutes.
    var uploadReplyTimeout: Duration {
        get { locked { $0.uploadReplyTimeout } }
        set { locked { $0.uploadReplyTimeout = newValue } }
    }

    /// How long each `TransportDeadline.writeChunkBytes` of a write takes to
    /// leave: a slow uplink, or with a long enough value one that has
    /// stopped. Charged by size, so a write handed to the link in one lump
    /// takes as long as the pieces it should have gone in. A piece still
    /// going out when the connection is closed fails, as a pending send does
    /// when an `NWConnection` is cancelled.
    var uplinkDelay: Duration {
        get { locked { $0.uplinkDelay } }
        set { locked { $0.uplinkDelay = newValue } }
    }

    /// Connections opened after it is set never finish their TLS handshake,
    /// so `open()` ends only at its deadline. The handshake never reports
    /// anything afterwards either, closed or not: whatever ends it is the
    /// transport's own doing.
    var handshakeStalls: Bool {
        get { locked { $0.handshakeStalls } }
        set { locked { $0.handshakeStalls = newValue } }
    }

    /// Keeps the TLS handshake of every connection opened from now on from
    /// finishing until `releaseHandshakes()`: a connection still being
    /// made, for exactly as long as the test wants. The transport's own
    /// connect deadline still runs.
    func holdHandshakes() {
        locked { $0.handshakesHeld = true }
    }

    /// Lets every held handshake finish, greeting and all, and stops holding.
    func releaseHandshakes() async {
        let live: [ScriptedTransport] = locked { s in
            s.handshakesHeld = false
            return s.transports.keys.sorted().compactMap { s.transports[$0]?.transport }
        }
        for transport in live { await transport.finishHeldHandshake() }
    }

    /// Capabilities left out of the post-login list, for a server that has
    /// not got them: `["UIDPLUS"]` is one that can only EXPUNGE the lot.
    /// The commands themselves are still answered. Gmail's FETCH items are
    /// the exception: without `X-GM-EXT-1` a FETCH naming X-GM-LABELS,
    /// X-GM-THRID or X-GM-MSGID is BAD, as on a server that has never heard
    /// of them, so a client that asked for them ungated would lose the page.
    var withheldCapabilities: Set<String> {
        get { locked { $0.withheldCapabilities } }
        set { locked { $0.withheldCapabilities = newValue } }
    }

    // MARK: - Inspection

    /// Every command received, in order, across all connections.
    var log: [LogEntry] { locked { $0.log } }

    /// Commands written into a connection that `resetConnections` had
    /// already killed. They never reached the server and are not in `log`.
    var lostWrites: [LogEntry] { locked { $0.lostWrites } }

    /// Connections that got as far as `open()`, refused ones excluded.
    var connectionsOpened: Int { locked { $0.connectionsOpened } }

    /// Connections the client has asked `transportFactory` for, counted as
    /// it asks, so one whose handshake `holdHandshakes()` is holding counts
    /// too, as `connectionsOpened` does not.
    var connectionsBegun: Int { locked { $0.made.count } }

    /// Transports made by `transportFactory` that still exist. Once the
    /// client has let go of one, only something left waiting on it can be
    /// holding it.
    var transportsInMemory: Int { locked { $0.made.filter { $0.transport != nil }.count } }

    /// Every time the client used a connection in a way it never should:
    /// a command written while the reply to the one before was unread, or
    /// two reads waiting on one connection at once. Both mean two commands
    /// were in flight together, which is what the exchange gate exists to
    /// prevent. Empty after every test that runs over this server.
    var violations: [String] { locked { $0.violations } }

    func clearLog() {
        locked { s in
            s.log.removeAll()
            s.lostWrites.removeAll()
        }
    }

    /// Ascending.
    func uids(in mailbox: String) -> [UInt32] {
        locked { $0.folders[Self.canonical(mailbox)]?.uids ?? [] }
    }

    func uidValidity(of mailbox: String) -> UInt32 {
        locked { $0.folders[Self.canonical(mailbox)]?.uidValidity ?? 0 }
    }

    /// The letter at `uid`, with the flags it carries now.
    func letter(uid: UInt32, in mailbox: String) -> Letter? {
        locked { s in
            guard let key = s.folders[Self.canonical(mailbox)]?.keys[uid],
                  let stored = s.letters[key] else { return nil }
            var letter = stored.letter
            letter.flags = stored.flags
            return letter
        }
    }

    /// Gmail's id for the letter at `uid`, the X-GM-MSGID a FETCH in
    /// `mailbox` reports for it: the same from every folder the letter is
    /// in, and never its thread's.
    func gmailMessageID(uid: UInt32, in mailbox: String) -> UInt64? {
        locked { s in
            s.folders[Self.canonical(mailbox)]?.keys[uid].map { Self.gmailMessageID(key: $0) }
        }
    }

    /// Marks the letter at `uid` in `mailbox` `\Deleted` and leaves it there,
    /// as another mail program does with Auto-Expunge off, or as this app's
    /// Delete inside Trash did before it expunged (B-062).
    func markDeleted(uid: UInt32, in mailbox: String) {
        locked { s in
            let name = Self.canonical(mailbox)
            guard s.folders[name]?.keys[uid] != nil else { return }
            s.folders[name]?.deleted.insert(uid)
        }
    }

    /// The flags a FETCH in `mailbox` would report, `\Deleted` included.
    func flags(uid: UInt32, in mailbox: String) -> Set<String> {
        locked { s in
            let name = Self.canonical(mailbox)
            guard let folder = s.folders[name], let key = folder.keys[uid],
                  let stored = s.letters[key] else { return [] }
            return folder.deleted.contains(uid) ? stored.flags.union(["\\Deleted"]) : stored.flags
        }
    }

    /// Adds a letter to each of `mailboxes` and returns its UID in each.
    /// A name that is not a selectable mailbox here is left out.
    ///
    /// Seen at once by every connection, the ones with the mailbox already
    /// selected included, as if each had been told of it. For a letter that
    /// comes in the way Gmail tells of one, see `arrive`.
    @discardableResult
    func deliver(_ letter: Letter, to mailboxes: [String]) -> [String: UInt32] {
        locked { s in
            let key = s.store(letter)
            var out: [String: UInt32] = [:]
            for name in mailboxes.map(Self.canonical) {
                if let uid = s.file(key, in: name) { out[name] = uid }
            }
            return out
        }
    }

    /// Adds a letter made of the bytes given, to each of `mailboxes`, and
    /// returns its UID in each, as `deliver` does: `raw` is the whole
    /// letter, `sections` what `BODY[section]` answers ("HEADER", "1",
    /// "1.2"; "" is `raw`), and `structure` its BODYSTRUCTURE, wire text.
    /// The envelope, the flags and what a SEARCH matches are `letter`'s.
    ///
    /// For a shape `render` does not make, or a letter too large to render
    /// quickly: `render` reads every character of the words.
    @discardableResult
    func deliver(raw: Data, sections: [String: Data], structure: String, as letter: Letter,
                 to mailboxes: [String]) -> [String: UInt32] {
        locked { s in
            var bodies = sections
            bodies[""] = raw
            let key = s.store(Stored(letter: letter, flags: letter.flags, raw: raw,
                                     sections: bodies, structure: structure))
            var out: [String: UInt32] = [:]
            for name in mailboxes.map(Self.canonical) {
                if let uid = s.file(key, in: name) { out[name] = uid }
            }
            return out
        }
    }

    /// Adds a letter to each of `mailboxes`, as mail reaches Gmail from
    /// outside a session, and returns its UID in each.
    ///
    /// A connection that has one of them selected does not see it, in a
    /// SEARCH or a FETCH, until it has been told with an EXISTS. It is told
    /// where Gmail was seen to tell (B-045): in the answer to a NOOP, and at
    /// the end of the answer to a UID FETCH, but never in a SEARCH's. A
    /// connection that SELECTs the mailbox afterwards sees it at once, and
    /// STATUS counts it at once, as Gmail's did.
    @discardableResult
    func arrive(_ letter: Letter, in mailboxes: [String]) -> [String: UInt32] {
        locked { s in
            let key = s.store(letter)
            var out: [String: UInt32] = [:]
            for name in mailboxes.map(Self.canonical) {
                guard let uid = s.file(key, in: name) else { continue }
                out[name] = uid
                for id in s.sessions.keys where s.sessions[id]?.selected == name {
                    s.sessions[id]?.unannounced.insert(uid)
                }
            }
            return out
        }
    }

    /// Takes the letter at `uid` out of `mailbox`, as another client does
    /// when it archives or bins it.
    ///
    /// A connection that has the mailbox selected goes on seeing it, in a
    /// SEARCH and a FETCH, as it was, until it has been told with an
    /// EXPUNGE: RFC 3501 does not let a letter leave a session's view
    /// unannounced. It is told in the answer to a NOOP, the command RFC 3501
    /// gives a client to poll for exactly this, and nowhere else here. A
    /// connection that SELECTs the mailbox afterwards no longer sees it.
    func removeElsewhere(uid: UInt32, from mailbox: String) {
        locked { s in
            let name = Self.canonical(mailbox)
            guard let key = s.folders[name]?.keys[uid], var stored = s.letters[key] else { return }
            stored.mailboxes.remove(name)
            for id in s.sessions.keys where s.sessions[id]?.selected == name {
                s.sessions[id]?.unexpunged[uid] = (key, stored)
            }
            s.unfile(uid, from: name)
        }
    }

    // MARK: - What the transport calls

    fileprivate struct Reply: Sendable {
        let bytes: Data
        let delay: Duration
        /// What it answers, as `holdReplies(to:)` names it. Empty for the
        /// greeting.
        var verb = ""
        /// The server hangs up once this has been sent, as after LOGOUT.
        var closesAfter = false
    }

    fileprivate struct WeakTransport {
        weak var transport: ScriptedTransport?
    }

    fileprivate func isHeld(_ reply: Reply) -> Bool {
        locked { $0.held.contains(reply.verb) }
    }

    fileprivate var handshakesAreHeld: Bool { locked { $0.handshakesHeld } }

    fileprivate func noteViolation(_ text: String) {
        locked { $0.violations.append(text) }
    }

    fileprivate func newConnectionID() -> Int {
        locked { s in
            defer { s.nextConnection += 1 }
            return s.nextConnection
        }
    }

    /// Nil when the peer is silent, which is a greeting that never comes.
    fileprivate func accept(_ id: Int) -> Reply? {
        locked { s in
            s.connectionsOpened += 1
            s.sessions[id] = Session()
            guard !s.isSilent else { return nil }
            let line: String
            switch s.greeting {
            case .ready:
                line = "* OK Gimap ready for requests from 192.0.2.10 fake"
            case .preauthenticated(let announcing):
                s.sessions[id]?.authenticated = true
                line = announcing
                    ? "* PREAUTH [CAPABILITY \(s.advertisedAfterLogin)] Logged in as \(s.username)"
                    : "* PREAUTH Logged in as \(s.username)"
            }
            return Reply(bytes: Data((line + "\r\n").utf8), delay: s.defaultDelay)
        }
    }

    fileprivate func hangUp(_ id: Int) {
        locked { s in
            s.sessions[id] = nil
            s.transports[id] = nil
        }
    }

    fileprivate func resetError(for id: Int) -> MailTransportError? {
        locked { $0.sessions[id]?.reset }
    }

    fileprivate func receive(_ data: Data, on id: Int) -> [Reply] {
        locked { $0.receive(data, on: id) }
    }

    private func locked<T>(_ body: (inout State) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }

    // MARK: - Seed

    private static func seed(inboxCount n: Int) -> [(Letter, [String])] {
        let topics = ["garden", "invoice", "dinner", "tickets", "photos"]
        let senders = [sam, carlo, jane]
        let day: TimeInterval = 86_400
        var out: [(Letter, [String])] = []

        for i in stride(from: 1, through: n, by: 1) {
            let topic = topics[i % topics.count]
            let htmlOnly = i % 5 == 0
            let html = "<p>Letter \(i): a few words about the <b>\(topic)</b>.</p>"
            var letter = Letter(
                from: senders[i % senders.count], to: [owner],
                subject: i == n - 1 ? "Letter \(i): the \"\(topic)\" one" : "Letter \(i): \(topic)",
                date: newestDate.addingTimeInterval(-Double(n - i) * day),
                text: htmlOnly ? nil : "Letter \(i).\r\nA few words about the \(topic).\r\n",
                html: htmlOnly || i % 3 == 0 ? html : nil,
                flags: i <= n - 6 ? ["\\Seen"] : [],
                messageID: "<letter-\(i)@example.org>")
            var mailboxes = [inbox, allMail]
            if i % 11 == 0 {
                letter.flags.insert("\\Flagged")
                mailboxes.append(starred)
            }
            out.append((letter, mailboxes))
        }

        // Half a day off the Inbox's times, so no two letters share a date.
        for j in 1...8 {
            let topic = topics[j % topics.count]
            out.append((Letter(from: owner, to: [carlo], subject: "Re: the \(topic)",
                               date: newestDate.addingTimeInterval(-(Double(j) * 9 + 0.5) * day),
                               text: "Thanks for the note about the \(topic).\r\n",
                               flags: ["\\Seen"], messageID: "<sent-\(j)@example.com>",
                               inReplyTo: "<letter-\(max(1, n - j * 9))@example.org>"),
                        [sent, allMail]))
        }
        for j in 1...2 {
            out.append((Letter(from: owner, to: [sam], subject: "Unfinished \(j)",
                               date: newestDate.addingTimeInterval(-(Double(j) * 3 + 0.25) * day),
                               text: "Half a thought about the garden.\r\n",
                               flags: ["\\Draft", "\\Seen"], messageID: "<draft-\(j)@example.com>"),
                        [drafts, allMail]))
        }
        for j in 1...5 {
            let topic = topics[j % topics.count]
            out.append((Letter(from: senders[j % senders.count], to: [owner],
                               subject: "Binned: old \(topic)",
                               date: newestDate.addingTimeInterval(-(Double(j) * 13 + 0.75) * day),
                               text: "An old note about the \(topic).\r\n",
                               flags: ["\\Seen"], messageID: "<trash-\(j)@example.org>"),
                        [trash]))
        }
        for j in 1...3 {
            out.append((Letter(from: Address(name: "Prize Desk", address: "prizes@example.net"),
                               to: [owner], subject: "Win a garden makeover \(j)",
                               date: newestDate.addingTimeInterval(-(Double(j) * 17 + 0.125) * day),
                               text: "You have won a garden makeover.\r\n",
                               messageID: "<spam-\(j)@example.net>"),
                        [spam]))
        }
        return out
    }

    // MARK: - Shared helpers

    /// INBOX is case-insensitive; every other name is not.
    fileprivate static func canonical(_ mailbox: String) -> String {
        mailbox.uppercased() == inbox ? inbox : mailbox
    }

    fileprivate static func verb(of command: String) -> String {
        let words = command.split(separator: " ", maxSplits: 2).map { $0.uppercased() }
        guard let first = words.first else { return "" }
        if first == "UID", words.count > 1 { return "UID " + words[1] }
        return first
    }

    fileprivate static let preLoginCapabilities =
        "IMAP4rev1 UNSELECT IDLE NAMESPACE QUOTA ID XLIST CHILDREN X-GM-EXT-1 XYZZY SASL-IR "
        + "AUTH=XOAUTH2 AUTH=PLAIN AUTH=PLAIN-CLIENTTOKEN AUTH=OAUTHBEARER"

    fileprivate static let postLoginCapabilities =
        "IMAP4rev1 UNSELECT IDLE NAMESPACE QUOTA ID XLIST CHILDREN X-GM-EXT-1 UIDPLUS "
        + "COMPRESS=DEFLATE ENABLE MOVE CONDSTORE ESEARCH UTF8=ACCEPT LIST-EXTENDED "
        + "LIST-STATUS LITERAL- SPECIAL-USE APPENDLIMIT=35651584"
}

// MARK: - Server state

private extension ScriptedIMAPServer {

    struct Folder {
        let name: String
        let attributes: [String]
        /// The X-GM-LABELS token that means this mailbox. Nil for All Mail,
        /// which is not a label.
        let label: String?
        let selectable: Bool
        var uidValidity: UInt32
        var uidNext: UInt32
        /// Ascending, always: new letters get `uidNext`.
        var uids: [UInt32] = []
        var keys: [UInt32: Int] = [:]
        var deleted: Set<UInt32> = []

        func sequenceNumber(of uid: UInt32) -> Int? {
            uids.firstIndex(of: uid).map { $0 + 1 }
        }

        func highestUID() -> UInt32 { uids.last ?? 0 }
    }

    struct Stored {
        var letter: Letter
        var flags: Set<String>
        let raw: Data
        /// BODY[section] contents, keyed by the section as the client names
        /// it: "", "HEADER", "TEXT", "1", "2".
        let sections: [String: Data]
        /// The BODYSTRUCTURE value, wire text.
        let structure: String
        var mailboxes: Set<String> = []
    }

    struct Session {
        var authenticated = false
        var selected: String?
        var readOnly = false
        /// Letters `arrive` has filed in the selected mailbox that this
        /// connection has not been told of.
        var unannounced: Set<UInt32> = []
        /// Letters `removeElsewhere` has taken out of the selected mailbox
        /// that this connection has not been told of, as they were.
        var unexpunged: [UInt32: (key: Int, stored: Stored)] = [:]
        /// Bytes written but not yet a whole command.
        var inbound = Data()
        /// An APPEND waiting for the literal it announced.
        var literal: (command: String, count: Int)?
        var reset: MailTransportError?
    }

    struct State {
        let username: String
        var password: String
        var folders: [String: Folder] = [:]
        /// LIST order, which is Gmail's.
        var order: [String] = []
        var letters: [Int: Stored] = [:]
        var nextKey = 1
        var sessions: [Int: Session] = [:]
        var nextConnection = 1
        var connectionsOpened = 0
        var log: [LogEntry] = []
        var lostWrites: [LogEntry] = []
        var isSilent = false
        var delays: [String: Duration] = [:]
        var defaultDelay: Duration = .zero
        var loginCapabilities: LoginCapabilities = .inTaggedOK
        var greeting: Greeting = .ready
        var refusedMailboxes: Set<String> = []
        var unlistedMailboxes: Set<String> = []
        var refusedSearchKeys: Set<String> = []
        var refusesSearchReturn = false
        var ignoresSearchReturn = false
        var esearchItems: (@Sendable ([UInt32]) -> String)?
        var refusesCharset = false
        var completesApart: Set<String> = []
        var refusedVerbs: Set<String> = []
        var autoExpunge = false
        var passwordRevoked = false
        var loginRefusal = "[AUTHENTICATIONFAILED] Invalid credentials (Failure)"
        var timeout: Duration = .seconds(1)
        var timeouts: [Int: Duration] = [:]
        var uploadReplyTimeout: Duration = .seconds(5)
        var uplinkDelay: Duration = .zero
        var handshakeStalls = false
        var handshakesHeld = false
        var withheldCapabilities: Set<String> = []
        var held: Set<String> = []
        var transports: [Int: Server.WeakTransport] = [:]
        /// Every transport ever made, for `transportsInMemory` and
        /// `connectionsBegun`.
        var made: [Server.WeakTransport] = []
        var violations: [String] = []

        init(username: String, password: String) {
            self.username = username
            self.password = password
        }
    }
}

// MARK: - Mail storage

private extension ScriptedIMAPServer.State {

    typealias Server = ScriptedIMAPServer

    /// Gmail's post-login list, less `withheldCapabilities`.
    var advertisedAfterLogin: String {
        Server.postLoginCapabilities.split(separator: " ")
            .filter { !withheldCapabilities.contains(String($0)) }
            .joined(separator: " ")
    }

    mutating func addFolder(_ name: String, attributes: [String], label: String?,
                            validity: UInt32, firstUID: UInt32, selectable: Bool = true) {
        folders[name] = Server.Folder(name: name, attributes: attributes, label: label,
                                      selectable: selectable, uidValidity: validity,
                                      uidNext: firstUID)
        order.append(name)
    }

    mutating func store(_ letter: Server.Letter) -> Int {
        let rendered = Server.render(letter)
        return store(Server.Stored(letter: letter, flags: letter.flags, raw: rendered.raw,
                                   sections: rendered.sections, structure: rendered.structure))
    }

    mutating func store(_ stored: Server.Stored) -> Int {
        let key = nextKey
        nextKey += 1
        letters[key] = stored
        return key
    }

    @discardableResult
    mutating func file(_ key: Int, in name: String, gap: UInt32 = 0) -> UInt32? {
        guard var folder = folders[name], folder.selectable else { return nil }
        let uid = folder.uidNext
        folder.uids.append(uid)
        folder.keys[uid] = key
        folder.uidNext += 1 + gap
        folders[name] = folder
        letters[key]?.mailboxes.insert(name)
        return uid
    }

    mutating func unfile(_ uid: UInt32, from name: String) {
        guard var folder = folders[name], let key = folder.keys[uid] else { return }
        folder.uids.removeAll { $0 == uid }
        folder.keys[uid] = nil
        folder.deleted.remove(uid)
        folders[name] = folder
        letters[key]?.mailboxes.remove(name)
        if letters[key]?.mailboxes.isEmpty == true { letters[key] = nil }
    }

    /// The UIDs of `name` as connection `id` has been told of them,
    /// ascending: what `arrive` has filed there that it has not been told
    /// of left out, and what `removeElsewhere` has taken out that it has not
    /// been told of left in. Its sequence numbers count along this.
    func view(of name: String, on id: Int) -> [UInt32] {
        guard let folder = folders[name] else { return [] }
        guard let session = sessions[id], session.selected == name,
              !session.unannounced.isEmpty || !session.unexpunged.isEmpty else { return folder.uids }
        return (folder.uids.filter { !session.unannounced.contains($0) }
                + session.unexpunged.keys).sorted()
    }

    /// The letter at `uid` in `name` as connection `id` sees it, one taken
    /// out elsewhere included.
    func letter(_ uid: UInt32, in name: String, on id: Int) -> (key: Int, stored: Server.Stored)? {
        if let key = folders[name]?.keys[uid] { return letters[key].map { (key, $0) } }
        return sessions[id]?.unexpunged[uid]
    }

    /// Tells connection `id` what has changed in its mailbox since it was
    /// last told: an EXPUNGE for each letter taken out elsewhere, from the
    /// highest sequence number down so that each is still right when the
    /// client applies it, when `expunging`, and then one EXISTS for
    /// everything that has arrived.
    mutating func announce(on id: Int, expunging: Bool, into r: inout Server.Response) {
        guard var session = sessions[id], let name = session.selected,
              let folder = folders[name] else { return }
        if expunging, !session.unexpunged.isEmpty {
            var seen = view(of: name, on: id)
            for uid in session.unexpunged.keys.sorted(by: >) {
                guard let index = seen.firstIndex(of: uid) else { continue }
                r.untagged("\(index + 1) EXPUNGE")
                seen.remove(at: index)
            }
            session.unexpunged = [:]
        }
        if !session.unannounced.isEmpty {
            session.unannounced = []
            r.untagged("\(folder.uids.count + session.unexpunged.count) EXISTS")
        }
        sessions[id] = session
    }

    /// Gmail's thread id for a letter: its own, or that of the letter whose
    /// conversation it joins (`Letter.joins`).
    func thread(of key: Int) -> UInt64 {
        guard let joins = letters[key]?.letter.joins,
              let first = letters.first(where: { $0.value.letter.messageID == joins })?.key
        else { return Server.gmailThreadID(key: key) }
        return Server.gmailThreadID(key: first)
    }

    /// Gmail's labels for a letter seen from `selected`: every other mailbox
    /// holding it, All Mail excepted because it is not a label.
    func labels(of key: Int, seenFrom selected: String) -> [String] {
        guard let stored = letters[key] else { return [] }
        return order.compactMap { name in
            guard name != selected, stored.mailboxes.contains(name) else { return nil }
            return folders[name]?.label
        }
    }
}

// MARK: - Reading commands off the wire

private extension ScriptedIMAPServer.State {

    /// Assembles whole commands out of whatever the client wrote, answering
    /// each as it completes. A line ending in `{n}` is an APPEND announcing a
    /// synchronising literal: the server says "+" and waits for n bytes and
    /// the rest of the line before it has a command at all.
    mutating func receive(_ data: Data, on id: Int) -> [Server.Reply] {
        guard let opened = sessions[id] else { return [] }
        if opened.reset != nil {
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
            lostWrites.append(Server.LogEntry(connection: id, selected: opened.selected,
                                              command: Server.untagged(text)))
            return []
        }
        sessions[id]?.inbound.append(data)

        let crlf = Data("\r\n".utf8)
        var replies: [Server.Reply] = []
        while var session = sessions[id] {
            if let pending = session.literal {
                guard session.inbound.count >= pending.count else { break }
                let bytes = Data(session.inbound.prefix(pending.count))
                let rest = Data(session.inbound.dropFirst(pending.count))
                guard let end = rest.range(of: crlf) else { break }
                let tail = String(decoding: rest[..<end.lowerBound], as: UTF8.self)
                session.inbound = Data(rest[end.upperBound...])
                session.literal = nil
                sessions[id] = session
                replies += execute(pending.command + tail, literal: bytes, on: id)
                continue
            }
            guard let end = session.inbound.range(of: crlf) else { break }
            let line = String(decoding: session.inbound[..<end.lowerBound], as: UTF8.self)
            session.inbound = Data(session.inbound[end.upperBound...])
            if let count = Server.trailingLiteralLength(line) {
                session.literal = (line, count)
                sessions[id] = session
                // Not held with the command's own reply: `holdReplies(to:
                // "APPEND")` keeps back the tagged answer to a letter the
                // server has taken, not the "+" that lets it be sent.
                if !isSilent {
                    replies.append(Server.Reply(bytes: Data("+ go ahead\r\n".utf8), delay: .zero,
                                                verb: "+ " + Server.verb(of: Server.untagged(line))))
                }
                continue
            }
            sessions[id] = session
            replies += execute(line, literal: nil, on: id)
        }
        return replies
    }

    mutating func execute(_ line: String, literal: Data?, on id: Int) -> [Server.Reply] {
        let space = line.firstIndex(of: " ") ?? line.endIndex
        let tag = String(line[..<space])
        let command = Server.untagged(line)
        var entry = Server.LogEntry(connection: id, selected: sessions[id]?.selected, command: command)
        guard !isSilent else {
            log.append(entry)
            return []
        }

        var response = Server.Response(tag: tag)
        dispatch(Server.tokens(command), literal: literal, on: id, into: &response)
        entry.status = response.status
        log.append(entry)
        let bytes = response.wire.data
        let delay = delays[entry.verb] ?? defaultDelay
        if completesApart.contains(entry.verb), let tagged = response.taggedAt, tagged > 0 {
            let split = bytes.startIndex + tagged
            return [Server.Reply(bytes: Data(bytes[..<split]), delay: delay, verb: entry.verb),
                    Server.Reply(bytes: Data(bytes[split...]), delay: .zero,
                                 verb: Server.completion(of: entry.verb),
                                 closesAfter: response.hangsUp)]
        }
        return [Server.Reply(bytes: bytes, delay: delay, verb: entry.verb,
                             closesAfter: response.hangsUp)]
    }

    mutating func dispatch(_ tokens: [Server.Token], literal: Data?, on id: Int,
                           into r: inout Server.Response) {
        guard var verb = tokens.first?.text?.uppercased(), let session = sessions[id] else {
            r.bad("Could not parse command")
            return
        }
        var args = Array(tokens.dropFirst())
        if verb == "UID", let second = args.first?.text?.uppercased() {
            verb = "UID " + second
            args.removeFirst()
        }

        if refusedVerbs.contains(verb) {
            r.no("[UNAVAILABLE] Temporary System Problem. Try again later. (Failure)")
            return
        }
        switch verb {
        case "CAPABILITY":
            r.untagged("CAPABILITY " + (session.authenticated ? advertisedAfterLogin
                                                               : Server.preLoginCapabilities))
            r.ok("Thats all she wrote! (Success)")
        case "NOOP":
            announce(on: id, expunging: true, into: &r)
            r.ok("Success")
        case "LOGOUT":
            r.untagged("BYE LOGOUT Requested")
            r.ok("73 GOODBYE")
            r.hangsUp = true
        case "LOGIN" where session.authenticated:
            r.bad("Command received in Invalid state.")
        case "LOGIN":
            login(args, on: id, into: &r)
        case _ where !session.authenticated:
            r.bad("Command received in Invalid state.")
        case "LIST":
            list(args, into: &r)
        case "STATUS":
            status(args, into: &r)
        case "SELECT", "EXAMINE":
            select(args, readOnly: verb == "EXAMINE", on: id, into: &r)
        case "APPEND":
            append(args, literal: literal, into: &r)
        case "UID SEARCH", "UID FETCH", "UID STORE", "UID MOVE", "UID COPY", "UID EXPUNGE", "EXPUNGE":
            // Gmail's words, and the case the whole per-connection model is
            // for: a UID command only means something against the mailbox
            // SELECTed on this connection, and there is none.
            guard let selected = session.selected else {
                r.bad("Command received in Invalid state.")
                return
            }
            switch verb {
            case "UID SEARCH": search(args, in: selected, on: id, into: &r)
            case "UID FETCH":  fetch(args, in: selected, on: id, into: &r)
            case "UID STORE":  storeFlags(args, in: selected, readOnly: session.readOnly, into: &r)
            case "UID MOVE":   copy(args, from: selected, removing: true, into: &r)
            case "UID COPY":   copy(args, from: selected, removing: false, into: &r)
            default:           expunge(args, in: selected, into: &r)
            }
        default:
            r.bad("Could not parse command")
        }
    }
}

// MARK: - Commands

private extension ScriptedIMAPServer.State {

    mutating func login(_ args: [Server.Token], on id: Int, into r: inout Server.Response) {
        guard args.count == 2, let user = args[0].text, let pass = args[1].text else {
            r.bad("Could not parse command")
            return
        }
        guard user == username, pass == password, !passwordRevoked else {
            r.no(loginRefusal)
            return
        }
        sessions[id]?.authenticated = true
        switch loginCapabilities {
        case .inTaggedOK:
            r.ok("[CAPABILITY \(advertisedAfterLogin)] \(user) authenticated (Success)")
        case .untagged:
            r.untagged("CAPABILITY \(advertisedAfterLogin)")
            r.ok("\(user) authenticated (Success)")
        case .omitted:
            r.ok("\(user) authenticated (Success)")
        }
    }

    func list(_ args: [Server.Token], into r: inout Server.Response) {
        guard args.count == 2, let pattern = args[1].text else {
            r.bad("Could not parse command")
            return
        }
        for name in order where !unlistedMailboxes.contains(name) {
            guard let folder = folders[name] else { continue }
            let matches = pattern == "*"
                || (pattern == "%" && !name.contains("/"))
                || Server.canonical(pattern) == name
            guard matches else { continue }
            let attributes = folder.attributes.joined(separator: " ")
            r.untagged("LIST (\(attributes)) \"/\" \(Server.quoted(name))")
        }
        r.ok("Success")
    }

    func status(_ args: [Server.Token], into r: inout Server.Response) {
        guard args.count == 2, let raw = args[0].text, let items = args[1].items else {
            r.bad("Could not parse command")
            return
        }
        let name = Server.canonical(raw)
        guard let folder = folders[name], folder.selectable, !unlistedMailboxes.contains(name) else {
            r.no("[NONEXISTENT] Unknown Mailbox: \(raw) (Failure)")
            return
        }
        var pairs: [String] = []
        for item in items.compactMap({ $0.text?.uppercased() }) {
            let value: String
            switch item {
            case "MESSAGES":    value = "\(folder.uids.count)"
            case "UNSEEN":      value = "\(folder.uids.filter { !isSeen(folder.keys[$0]) }.count)"
            case "UIDNEXT":     value = "\(folder.uidNext)"
            case "UIDVALIDITY": value = "\(folder.uidValidity)"
            case "RECENT":      value = "0"
            default:
                r.bad("Could not parse command")
                return
            }
            pairs.append("\(item) \(value)")
        }
        r.untagged("STATUS \(Server.quoted(name)) (\(pairs.joined(separator: " ")))")
        r.ok("Success")
    }

    mutating func select(_ args: [Server.Token], readOnly: Bool, on id: Int,
                         into r: inout Server.Response) {
        guard args.count == 1, let raw = args[0].text else {
            r.bad("Could not parse command")
            return
        }
        let name = Server.canonical(raw)
        // Whatever it was told of the mailbox it leaves goes with it, and
        // the one it opens it sees as it is.
        sessions[id]?.unannounced = []
        sessions[id]?.unexpunged = [:]
        guard let folder = folders[name], folder.selectable, !refusedMailboxes.contains(name),
              !unlistedMailboxes.contains(name) else {
            // RFC 3501: a failed SELECT leaves NO mailbox selected, not the
            // old one, which is exactly the state a stale cache gets wrong.
            sessions[id]?.selected = nil
            r.no("[NONEXISTENT] Unknown Mailbox: \(raw) (now in authenticated state) (Failure)")
            return
        }
        sessions[id]?.selected = name
        sessions[id]?.readOnly = readOnly
        let flags = "\\Answered \\Flagged \\Draft \\Deleted \\Seen $NotPhishing $Phishing"
        r.untagged("FLAGS (\(flags))")
        r.untagged("OK [PERMANENTFLAGS (\(readOnly ? "" : flags + " \\*"))] Flags permitted.")
        r.untagged("OK [UIDVALIDITY \(folder.uidValidity)] UIDs valid.")
        r.untagged("\(folder.uids.count) EXISTS")
        r.untagged("0 RECENT")
        r.untagged("OK [UIDNEXT \(folder.uidNext)] Predicted next UID.")
        r.untagged("OK [HIGHESTMODSEQ 4242]")
        r.ok("[\(readOnly ? "READ-ONLY" : "READ-WRITE")] \(name) selected. (Success)")
    }

    /// Over what the connection has been told of, and it is told nothing
    /// here: Gmail answered the SEARCH on the iPad with the letters it had
    /// announced and announced the rest on the FETCH after it (B-045).
    ///
    /// `RETURN (MIN)` and its neighbours are answered with ESEARCH (RFC
    /// 4731), as a server advertising it does: `* ESEARCH (TAG "a012") UID
    /// MIN 4231`, with no MIN when nothing matched. Refused NO with
    /// `refusesSearchReturn`, and BAD, as an unknown word, when ESEARCH is
    /// among `withheldCapabilities`; answered as a plain SEARCH with
    /// `ignoresSearchReturn`, and with other items with `esearchItems`.
    /// CHARSET is refused BAD with `refusesCharset`.
    func search(_ args: [Server.Token], in name: String, on id: Int, into r: inout Server.Response) {
        var keys = args[...]
        var returning: [String]?
        if keys.first?.text?.uppercased() == "RETURN" {
            guard !withheldCapabilities.contains("ESEARCH"), keys.count >= 2,
                  let options = keys.dropFirst().first?.items else {
                r.bad("Could not parse command")
                return
            }
            if refusesSearchReturn {
                r.no("[UNAVAILABLE] Temporary System Problem. Try again later. (Failure)")
                return
            }
            returning = options.compactMap { $0.text?.uppercased() }
            keys = keys.dropFirst(2)
        }
        if keys.first?.text?.uppercased() == "CHARSET" {
            if refusesCharset {
                r.bad("Could not parse command")
                return
            }
            keys = keys.dropFirst(2)
        }
        // Gmail's own key is unknown to a server without its extension.
        let refused = keys.contains {
            let word = $0.text?.uppercased() ?? ""
            return refusedSearchKeys.contains(word)
                || (word == "X-GM-MSGID" && withheldCapabilities.contains("X-GM-EXT-1"))
        }
        guard !refused, let folder = folders[name],
              let key = Server.SearchKey.parse(Array(keys)) else {
            r.bad("Could not parse command")
            return
        }
        let seen = view(of: name, on: id)
        let hits = seen.filter { uid in
            guard let found = letter(uid, in: name, on: id) else { return false }
            return key.matches(found.stored, key: found.key, uid: uid,
                               deleted: folder.deleted.contains(uid), highest: seen.last ?? 0)
        }
        if let returning, !ignoresSearchReturn {
            var answer = "ESEARCH (TAG \(Server.quoted(r.tag))) UID"
            if let esearchItems {
                let items = esearchItems(hits.sorted())
                if !items.isEmpty { answer += " " + items }
            } else {
                if returning.contains("MIN"), let lowest = hits.min() { answer += " MIN \(lowest)" }
                if returning.contains("MAX"), let highest = hits.max() { answer += " MAX \(highest)" }
                if returning.contains("COUNT") { answer += " COUNT \(hits.count)" }
            }
            r.untagged(answer)
        } else {
            r.untagged("SEARCH" + hits.map { " \($0)" }.joined())
        }
        r.ok("SEARCH completed (Success)")
    }

    /// Over what the connection has been told of, and then tells it of
    /// what has arrived, as Gmail did on the iPad (B-045).
    mutating func fetch(_ args: [Server.Token], in name: String, on id: Int,
                        into r: inout Server.Response) {
        guard args.count == 2, let setText = args[0].text, let folder = folders[name],
              let set = Server.UIDSet(setText) else {
            r.bad("Could not parse command")
            return
        }
        let requested = args[1].items?.compactMap(\.text) ?? args[1].text.map { [$0] } ?? []
        var items: [Server.FetchItem] = []
        for text in requested {
            // Gmail's own items are unknown to a server without its
            // extension, which refuses the whole FETCH over one of them.
            guard let item = Server.FetchItem(text),
                  !(item.isGmailExtension && withheldCapabilities.contains("X-GM-EXT-1")) else {
                r.bad("Could not parse command")
                return
            }
            items.append(item)
        }
        // UID FETCH always answers with the UID, asked for or not.
        if !items.contains(.uid) { items.insert(.uid, at: 0) }

        let seen = view(of: name, on: id)
        for (position, uid) in seen.enumerated() where set.contains(uid, highest: seen.last ?? 0) {
            guard let (key, found) = letter(uid, in: name, on: id) else { continue }
            var stored = found
            let seq = position + 1
            var wire = Server.Wire()
            wire.text("* \(seq) FETCH (")
            for (index, item) in items.enumerated() {
                if index > 0 { wire.text(" ") }
                switch item {
                case .uid:
                    wire.text("UID \(uid)")
                case .flags:
                    let flags = folder.deleted.contains(uid)
                        ? stored.flags.union(["\\Deleted"]) : stored.flags
                    wire.text("FLAGS (\(flags.sorted().joined(separator: " ")))")
                case .internalDate:
                    wire.text("INTERNALDATE \"\(Server.internalDate(stored.letter.arrival))\"")
                case .size:
                    wire.text("RFC822.SIZE \(stored.raw.count)")
                case .envelope:
                    wire.text("ENVELOPE ")
                    Server.envelope(stored.letter, into: &wire)
                case .bodyStructure:
                    wire.text("BODYSTRUCTURE \(stored.structure)")
                case .labels:
                    let labels = labels(of: key, seenFrom: name).map(Server.quoted)
                    wire.text("X-GM-LABELS (\(labels.joined(separator: " ")))")
                case .threadID:
                    wire.text("X-GM-THRID \(thread(of: key))")
                case .messageID:
                    wire.text("X-GM-MSGID \(Server.gmailMessageID(key: key))")
                case let .section(section, peek, partial):
                    // A plain BODY[] marks the letter read as a side effect,
                    // which is the reason the client only ever sends PEEK.
                    if !peek { stored.flags.insert("\\Seen") }
                    let origin = partial.map { "<\($0.start)>" } ?? ""
                    wire.text("BODY[\(section)]\(origin) ")
                    if var bytes = stored.sections[section] {
                        if let partial {
                            bytes = Data(bytes.dropFirst(partial.start).prefix(partial.count))
                        }
                        wire.literal(bytes)
                    } else {
                        wire.text("NIL")
                    }
                }
            }
            wire.text(")\r\n")
            // A letter taken out elsewhere is served as it was, and not
            // kept: it is no longer in this mailbox to be marked.
            if folder.keys[uid] != nil { letters[key] = stored }
            r.wire.data.append(wire.data)
        }
        announce(on: id, expunging: false, into: &r)
        r.ok("Success")
    }

    mutating func storeFlags(_ args: [Server.Token], in name: String, readOnly: Bool,
                             into r: inout Server.Response) {
        guard args.count == 3, let setText = args[0].text, let set = Server.UIDSet(setText),
              var op = args[1].text?.uppercased(), let folder = folders[name] else {
            r.bad("Could not parse command")
            return
        }
        guard !readOnly else {
            r.no("STORE attempt on READ-ONLY folder (Failure)")
            return
        }
        let silent = op.hasSuffix(".SILENT")
        if silent { op = String(op.dropLast(".SILENT".count)) }
        guard ["FLAGS", "+FLAGS", "-FLAGS"].contains(op) else {
            r.bad("Could not parse command")
            return
        }
        let given = Set(args[2].items?.compactMap(\.text) ?? args[2].text.map { [$0] } ?? [])
        // \Deleted belongs to this mailbox; every other flag to the letter.
        let isDeletedFlag = { (flag: String) in
            flag.caseInsensitiveCompare("\\Deleted") == .orderedSame
        }
        let touchesDeleted = given.contains(where: isDeletedFlag)
        let letterFlags = given.filter { !isDeletedFlag($0) }

        for uid in folder.uids where set.contains(uid, highest: folder.highestUID()) {
            guard let key = folder.keys[uid], var stored = letters[key] else { continue }
            var deleted = folder.deleted.contains(uid)
            switch op {
            case "+FLAGS":
                stored.flags.formUnion(letterFlags)
                if touchesDeleted { deleted = true }
            case "-FLAGS":
                stored.flags.subtract(letterFlags)
                if touchesDeleted { deleted = false }
            default:
                stored.flags = letterFlags
                deleted = touchesDeleted
            }
            letters[key] = stored
            if deleted {
                folders[name]?.deleted.insert(uid)
            } else {
                folders[name]?.deleted.remove(uid)
            }
            if !silent, let seq = folder.sequenceNumber(of: uid) {
                let shown = deleted ? stored.flags.union(["\\Deleted"]) : stored.flags
                r.untagged("\(seq) FETCH (UID \(uid) FLAGS (\(shown.sorted().joined(separator: " "))))")
            }
        }
        if autoExpunge, touchesDeleted, op != "-FLAGS" {
            let marked = (folders[name]?.deleted ?? []).filter {
                set.contains($0, highest: folder.highestUID())
            }
            remove(Set(marked), from: name, into: &r)
        }
        r.ok("Success")
    }

    /// UID MOVE and UID COPY, with Gmail's label semantics for a move.
    mutating func copy(_ args: [Server.Token], from source: String, removing: Bool,
                       into r: inout Server.Response) {
        guard args.count == 2, let setText = args[0].text, let set = Server.UIDSet(setText),
              let rawDestination = args[1].text, let from = folders[source] else {
            r.bad("Could not parse command")
            return
        }
        let destination = Server.canonical(rawDestination)
        guard let target = folders[destination], target.selectable else {
            r.no("[TRYCREATE] No folder \(rawDestination) (Failure)")
            return
        }
        let exclusive = [Server.trash, Server.spam]
        var sourceUIDs: [UInt32] = []
        var targetUIDs: [UInt32] = []
        var expunged: [Int] = []
        for uid in from.uids where set.contains(uid, highest: from.highestUID()) {
            guard let key = from.keys[uid] else { continue }
            let seq = folders[source]?.sequenceNumber(of: uid)
            sourceUIDs.append(uid)
            if exclusive.contains(destination), removing {
                // Binned or marked as spam: in nothing else any more.
                for other in letters[key]?.mailboxes ?? [] where other != source {
                    if let otherUID = folders[other]?.keys.first(where: { $0.value == key })?.key {
                        unfile(otherUID, from: other)
                    }
                }
            }
            if letters[key]?.mailboxes.contains(destination) == false,
               let filed = file(key, in: destination) {
                targetUIDs.append(filed)
            }
            if exclusive.contains(source), !exclusive.contains(destination),
               letters[key]?.mailboxes.contains(Server.allMail) == false {
                file(key, in: Server.allMail)
            }
            // Moving out of All Mail only adds a label and the letter stays,
            // unless it went to Trash or Spam, which take it out of All Mail.
            if removing, source != Server.allMail || exclusive.contains(destination), let seq {
                unfile(uid, from: source)
                expunged.append(seq)
            }
        }
        let copyUID = sourceUIDs.isEmpty ? "" :
            "[COPYUID \(target.uidValidity) \(sourceUIDs.map(String.init).joined(separator: ",")) "
            + "\(targetUIDs.map(String.init).joined(separator: ","))] "
        if removing {
            if !copyUID.isEmpty { r.untagged("OK \(copyUID)(Success)") }
            // Each number was taken after the removals before it, which is
            // how a client applies a run of EXPUNGEs.
            for seq in expunged { r.untagged("\(seq) EXPUNGE") }
            r.ok("Success")
        } else {
            r.ok("\(copyUID)(Success)")
        }
    }

    /// UID EXPUNGE with a set, or plain EXPUNGE: the marked letters it
    /// names, or every marked letter in the mailbox. A UID named that is not
    /// marked, or not there at all, is passed over, as RFC 4315 has it.
    mutating func expunge(_ args: [Server.Token], in name: String, into r: inout Server.Response) {
        guard let folder = folders[name] else {
            r.no("[NONEXISTENT] Unknown Mailbox (Failure)")
            return
        }
        var targets = folder.deleted
        if let setText = args.first?.text {
            guard let set = Server.UIDSet(setText) else {
                r.bad("Could not parse command")
                return
            }
            targets = targets.filter { set.contains($0, highest: folder.highestUID()) }
        }
        remove(targets, from: name, into: &r)
        r.ok("Success")
    }

    /// Takes `uids` out of `name`, with an EXPUNGE for each, from the
    /// highest down so that each number is still right when the client
    /// applies it. Gone from this mailbox; and from everywhere when that
    /// mailbox is Trash, Spam or Drafts, which is where Gmail deletes rather
    /// than unlabels.
    mutating func remove(_ uids: Set<UInt32>, from name: String, into r: inout Server.Response) {
        guard let folder = folders[name] else { return }
        let everywhere = [Server.trash, Server.spam, Server.drafts].contains(name)
        for uid in uids.sorted(by: >) {
            guard let seq = folders[name]?.sequenceNumber(of: uid),
                  let key = folder.keys[uid] else { continue }
            for other in letters[key]?.mailboxes ?? [] where everywhere && other != name {
                if let otherUID = folders[other]?.keys.first(where: { $0.value == key })?.key {
                    unfile(otherUID, from: other)
                }
            }
            unfile(uid, from: name)
            r.untagged("\(seq) EXPUNGE")
        }
    }

    mutating func append(_ args: [Server.Token], literal: Data?, into r: inout Server.Response) {
        guard let raw = literal, let rawName = args.first?.text else {
            r.bad("Could not parse command")
            return
        }
        let name = Server.canonical(rawName)
        guard let folder = folders[name], folder.selectable else {
            r.no("[TRYCREATE] Folder doesn't exist. (Failure)")
            return
        }
        let flags = Set(args.dropFirst().first?.items?.compactMap(\.text) ?? [])
        let key = nextKey
        nextKey += 1
        letters[key] = Server.parse(raw, flags: flags)
        let uid = file(key, in: name) ?? 0
        if ![Server.trash, Server.spam, Server.allMail].contains(name) {
            file(key, in: Server.allMail)
        }
        r.ok("[APPENDUID \(folder.uidValidity) \(uid)] (Success)")
    }

    func isSeen(_ key: Int?) -> Bool {
        key.flatMap { letters[$0] }?.flags.contains("\\Seen") ?? false
    }
}

// MARK: - Replies

private extension ScriptedIMAPServer {

    /// Bytes for the wire: text, and literals, which are a `{n}` at the end
    /// of a line followed by exactly n raw bytes.
    struct Wire {
        var data = Data()

        mutating func text(_ text: String) { data.append(contentsOf: Array(text.utf8)) }

        mutating func literal(_ bytes: Data) {
            text("{\(bytes.count)}\r\n")
            data.append(bytes)
        }

        /// An nstring as a server sends one: quoted when a quoted string can
        /// carry it, a literal when it cannot. Quotes, backslashes, line
        /// breaks and 8-bit text all go as literals, so the parser's literal
        /// path is exercised by ordinary-looking mail.
        mutating func string(_ value: String?) {
            guard let value else {
                text("NIL")
                return
            }
            let quotable = value.unicodeScalars.allSatisfy {
                $0.value >= 0x20 && $0.value < 0x7F && $0 != "\"" && $0 != "\\"
            }
            if quotable { text("\"\(value)\"") } else { literal(Data(value.utf8)) }
        }
    }

    struct Response {
        let tag: String
        var wire = Wire()
        var status: String?
        var hangsUp = false
        /// Where the tagged line starts in `wire`, once it is there.
        private(set) var taggedAt: Int?

        mutating func untagged(_ line: String) { wire.text("* \(line)\r\n") }

        mutating func ok(_ text: String) { finish("OK", text) }
        mutating func no(_ text: String) { finish("NO", text) }
        mutating func bad(_ text: String) { finish("BAD", text) }

        private mutating func finish(_ word: String, _ text: String) {
            status = word
            taggedAt = wire.data.count
            wire.text("\(tag) \(word) \(text)\r\n")
        }
    }

    /// X-GM-THRID and X-GM-MSGID, from the letter's key. Every letter here
    /// is a conversation of its own, unless it was delivered into another's
    /// (`Letter.joins`), so the two numbers are drawn from
    /// ranges that never meet: a client that took the one for the other is
    /// left holding a number this server never gave that letter as its id.
    static func gmailThreadID(key: Int) -> UInt64 { 1_700_000_000_000_000_000 + UInt64(key) }
    static func gmailMessageID(key: Int) -> UInt64 { 1_800_000_000_000_000_000 + UInt64(key) }

    static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func envelope(_ letter: Letter, into wire: inout Wire) {
        func addresses(_ list: [Address]) {
            guard !list.isEmpty else {
                wire.text("NIL")
                return
            }
            wire.text("(")
            for address in list {
                let parts = address.address.split(separator: "@", maxSplits: 1).map(String.init)
                wire.text("(")
                wire.string(address.name)
                wire.text(" NIL ")
                wire.string(parts.first ?? "")
                wire.text(" ")
                wire.string(parts.count > 1 ? parts[1] : "")
                wire.text(")")
            }
            wire.text(")")
        }
        wire.text("(")
        wire.string(headerDate(letter.date))
        wire.text(" ")
        wire.string(letter.subject)
        for list in [letter.authors, letter.authors, letter.replyTo.isEmpty ? letter.authors : letter.replyTo,
                     letter.to, letter.cc, letter.bcc] {
            wire.text(" ")
            addresses(list)
        }
        wire.text(" ")
        wire.string(letter.inReplyTo)
        wire.text(" ")
        wire.string(letter.messageID)
        wire.text(")")
    }

    // MARK: Rendering a letter

    static func render(_ letter: Letter) -> (raw: Data, sections: [String: Data], structure: String) {
        var header = "From: \(letter.authors.map(\.formatted).joined(separator: ", "))\r\n"
        header += "To: \(letter.to.map(\.formatted).joined(separator: ", "))\r\n"
        if !letter.cc.isEmpty {
            header += "Cc: \(letter.cc.map(\.formatted).joined(separator: ", "))\r\n"
        }
        if !letter.replyTo.isEmpty {
            header += "Reply-To: \(letter.replyTo.map(\.formatted).joined(separator: ", "))\r\n"
        }
        if !letter.bcc.isEmpty {
            header += "Bcc: \(letter.bcc.map(\.formatted).joined(separator: ", "))\r\n"
        }
        header += "Subject: \(letter.subject)\r\n"
        header += "Date: \(headerDate(letter.date))\r\n"
        header += "Message-ID: \(letter.messageID)\r\n"
        if let parent = letter.inReplyTo { header += "In-Reply-To: \(parent)\r\n" }
        if let ancestry = letter.references { header += "References: \(ancestry)\r\n" }
        header += "MIME-Version: 1.0\r\n"

        func leaf(_ subtype: String, _ body: String) -> (headers: String, structure: String) {
            let ascii = body.unicodeScalars.allSatisfy(\.isASCII)
            let encoding = ascii ? "7BIT" : "8BIT"
            let lines = body.filter { $0 == "\n" || $0 == "\r\n" }.count
            return ("Content-Type: text/\(subtype.lowercased()); charset=utf-8\r\n"
                        + "Content-Transfer-Encoding: \(encoding.lowercased())\r\n",
                    "(\"TEXT\" \"\(subtype)\" (\"CHARSET\" \"UTF-8\") NIL NIL \"\(encoding)\" "
                        + "\(body.utf8.count) \(lines) NIL NIL NIL NIL)")
        }

        // The words: one text part, or plain and HTML as alternatives, which
        // are parts 1 and 2 of the letter, or 1.1 and 1.2 under files.
        var sections: [String: Data] = [:]
        let words: (headers: String, body: String, structure: String)
        let prefix = letter.files.isEmpty ? "" : "1."
        switch (letter.text, letter.html) {
        case let (text?, html?):
            let boundary = "=_part_" + letter.messageID.filter { $0.isLetter || $0.isNumber }
            let plain = leaf("PLAIN", text)
            let rich = leaf("HTML", html)
            words = ("Content-Type: multipart/alternative; boundary=\"\(boundary)\"\r\n",
                     "--\(boundary)\r\n\(plain.headers)\r\n\(text)\r\n"
                        + "--\(boundary)\r\n\(rich.headers)\r\n\(html)\r\n"
                        + "--\(boundary)--\r\n",
                     "(\(plain.structure)\(rich.structure) \"ALTERNATIVE\" "
                        + "(\"BOUNDARY\" \"\(boundary)\") NIL NIL NIL)")
            sections[prefix + "1"] = Data(text.utf8)
            sections[prefix + "2"] = Data(html.utf8)
        case let (text, html):
            let content = text ?? html ?? ""
            let only = leaf(text == nil ? "HTML" : "PLAIN", content)
            words = (only.headers, content, only.structure)
            sections["1"] = Data(content.utf8)
        }

        let body: String
        let structure: String
        if letter.files.isEmpty {
            header += words.headers
            body = words.body
            structure = words.structure
        } else {
            // multipart/mixed: the words, then each file as a part of its
            // own, numbered 2, 3, …
            let boundary = "=_mixed_" + letter.messageID.filter { $0.isLetter || $0.isNumber }
            header += "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n"
            var text = "--\(boundary)\r\n\(words.headers)\r\n\(words.body)\r\n"
            var parts = words.structure
            for (i, file) in letter.files.enumerated() {
                let encoded = file.bytes.base64EncodedString(
                    options: [.lineLength76Characters, .endLineWithCarriageReturn,
                              .endLineWithLineFeed])
                let disposition = file.contentID == nil ? "attachment" : "inline"
                var headers = "Content-Type: \(file.type.lowercased())/\(file.subtype.lowercased());"
                    + " name=\"\(file.name)\"\r\n"
                    + "Content-Disposition: \(disposition); filename=\"\(file.name)\"\r\n"
                    + "Content-Transfer-Encoding: base64\r\n"
                if let id = file.contentID { headers += "Content-ID: <\(id)>\r\n" }
                text += "--\(boundary)\r\n\(headers)\r\n\(encoded)\r\n"
                parts += "(\"\(file.type)\" \"\(file.subtype)\" (\"NAME\" \"\(file.name)\") "
                    + (file.contentID.map { "\"<\($0)>\"" } ?? "NIL")
                    + " NIL \"BASE64\" \(encoded.utf8.count) "
                    // A text part's size is followed by its line count.
                    // Counted on the bytes: "\r\n" is one Character to a
                    // String, and splitting that on "\n" never splits.
                    + (file.type == "TEXT"
                       ? "\(encoded.utf8.split(separator: UInt8(ascii: "\n")).count) " : "")
                    + "NIL "
                    + "(\"\(disposition.uppercased())\" (\"FILENAME\" \"\(file.name)\")) NIL NIL)"
                sections["\(i + 2)"] = Data(encoded.utf8)
            }
            body = text + "--\(boundary)--\r\n"
            structure = "(\(parts) \"MIXED\" (\"BOUNDARY\" \"\(boundary)\") NIL NIL NIL)"
        }
        header += "\r\n"
        sections["HEADER"] = Data(header.utf8)
        sections["TEXT"] = Data(body.utf8)
        let raw = Data((header + body).utf8)
        sections[""] = raw
        return (raw, sections, structure)
    }

    /// An APPENDed message: kept byte for byte, headers read back for the
    /// envelope, and described as one text part.
    static func parse(_ raw: Data, flags: Set<String>) -> Stored {
        let separator = Data("\r\n\r\n".utf8)
        let split = raw.range(of: separator)
        let headerBytes = split.map { raw[..<$0.upperBound] } ?? raw[...]
        let body = split.map { Data(raw[$0.upperBound...]) } ?? Data()

        var fields: [String: String] = [:]
        var last: String?
        for line in String(decoding: headerBytes, as: UTF8.self).components(separatedBy: "\r\n") {
            if line.first == " " || line.first == "\t", let last {
                fields[last, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                let name = line[..<colon].lowercased()
                fields[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                last = name
            }
        }
        func address(_ text: String) -> Address {
            let formatted = text.trimmingCharacters(in: .whitespaces)
            guard let open = formatted.lastIndex(of: "<"), let close = formatted.lastIndex(of: ">"),
                  open < close else { return Address(name: nil, address: formatted) }
            let name = formatted[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            return Address(name: name.isEmpty ? nil : name,
                           address: String(formatted[formatted.index(after: open)..<close]))
        }

        // A field's addresses, split on its commas, as a draft's are
        // written here: none with a comma in its name.
        func addresses(_ field: String) -> [Address] {
            (fields[field] ?? "").split(separator: ",")
                .map { address(String($0)) }.filter { !$0.address.isEmpty }
        }

        let text = String(decoding: body, as: UTF8.self)
        let letter = Letter(from: address(fields["from"] ?? ""),
                            to: addresses("to"), cc: addresses("cc"), bcc: addresses("bcc"),
                            subject: fields["subject"] ?? "",
                            date: fields["date"].flatMap(headerFormatter.date(from:)) ?? newestDate,
                            text: text, flags: flags,
                            messageID: fields["message-id"] ?? "<appended@example.com>",
                            inReplyTo: fields["in-reply-to"],
                            references: fields["references"])
        let lines = text.filter { $0 == "\n" || $0 == "\r\n" }.count
        return Stored(letter: letter, flags: flags, raw: raw,
                      sections: ["": raw, "HEADER": Data(headerBytes), "TEXT": body, "1": body],
                      structure: "(\"TEXT\" \"PLAIN\" (\"CHARSET\" \"UTF-8\") NIL NIL \"8BIT\" "
                          + "\(body.count) \(lines) NIL NIL NIL NIL)")
    }

    static let headerFormatter = formatter("EEE, d MMM yyyy HH:mm:ss Z")
    static let internalFormatter = formatter("dd-MMM-yyyy HH:mm:ss Z")
    static let searchFormatter = formatter("d-MMM-yyyy")

    static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f
    }

    static func headerDate(_ date: Date) -> String { headerFormatter.string(from: date) }
    static func internalDate(_ date: Date) -> String { internalFormatter.string(from: date) }

    static func untagged(_ line: String) -> String {
        guard let space = line.firstIndex(of: " ") else { return "" }
        return String(line[line.index(after: space)...])
    }

    static func trailingLiteralLength(_ line: String) -> Int? {
        guard line.hasSuffix("}"), let open = line.lastIndex(of: "{") else { return nil }
        var digits = line[line.index(after: open)..<line.index(before: line.endIndex)]
        if digits.hasSuffix("+") { digits = digits.dropLast() }
        return Int(digits)
    }
}

// MARK: - Parsing commands

private extension ScriptedIMAPServer {

    /// A command argument. Written separately from `IMAPParser.tokenize`
    /// on purpose: a fake that read commands with the product's own
    /// tokenizer would agree with any bug in it.
    indirect enum Token: Equatable {
        case atom(String)
        case string(String)
        case list([Token])

        var text: String? {
            switch self {
            case .atom(let value), .string(let value): return value
            case .list: return nil
            }
        }

        var items: [Token]? {
            if case .list(let items) = self { return items }
            return nil
        }
    }

    static func tokens(_ text: String) -> [Token] {
        let chars = Array(text)
        var stack: [[Token]] = [[]]
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case " ":
                i += 1
            case "(":
                stack.append([])
                i += 1
            case ")":
                if stack.count > 1 {
                    let done = stack.removeLast()
                    stack[stack.count - 1].append(.list(done))
                }
                i += 1
            case "\"":
                var value = ""
                i += 1
                while i < chars.count, chars[i] != "\"" {
                    if chars[i] == "\\", i + 1 < chars.count { i += 1 }
                    value.append(chars[i])
                    i += 1
                }
                i += 1
                stack[stack.count - 1].append(.string(value))
            default:
                // Brackets hold spaces and parentheses inside one atom:
                // `BODY.PEEK[HEADER.FIELDS (FROM)]` is a single item.
                var value = ""
                var depth = 0
                while i < chars.count {
                    let d = chars[i]
                    if d == "[" { depth += 1 } else if d == "]" { depth -= 1 }
                    if depth == 0, d == " " || d == "(" || d == ")" { break }
                    value.append(d)
                    i += 1
                }
                stack[stack.count - 1].append(.atom(value))
            }
        }
        while stack.count > 1 {
            let done = stack.removeLast()
            stack[stack.count - 1].append(.list(done))
        }
        return stack[0]
    }

    /// `1004:1010,1012,1020:*`.
    struct UIDSet {
        private let ranges: [(low: UInt32?, high: UInt32?)]   // nil is `*`

        init?(_ text: String) {
            var ranges: [(low: UInt32?, high: UInt32?)] = []
            for piece in text.split(separator: ",") {
                let bounds = piece.split(separator: ":", maxSplits: 1).map(String.init)
                func value(_ s: String) -> UInt32?? {
                    s == "*" ? .some(nil) : UInt32(s).map { .some($0) }
                }
                guard let low = value(bounds[0]) else { return nil }
                let upper: UInt32?? = bounds.count > 1 ? value(bounds[1]) : .some(low)
                guard let high = upper else { return nil }
                ranges.append((low, high))
            }
            guard !ranges.isEmpty else { return nil }
            self.ranges = ranges
        }

        func contains(_ uid: UInt32, highest: UInt32) -> Bool {
            ranges.contains { range in
                let a = range.low ?? highest
                let b = range.high ?? highest
                return (min(a, b)...max(a, b)).contains(uid)
            }
        }
    }

    enum FetchItem: Equatable {
        case uid, flags, internalDate, size, envelope, bodyStructure, labels, threadID, messageID
        case section(String, peek: Bool, partial: Partial?)

        struct Partial: Equatable {
            let start: Int
            let count: Int
        }

        /// Asked for only behind X-GM-EXT-1.
        var isGmailExtension: Bool {
            switch self {
            case .labels, .threadID, .messageID: return true
            default: return false
            }
        }

        init?(_ text: String) {
            let upper = text.uppercased()
            switch upper {
            case "UID":           self = .uid
            case "FLAGS":         self = .flags
            case "INTERNALDATE":  self = .internalDate
            case "RFC822.SIZE":   self = .size
            case "ENVELOPE":      self = .envelope
            case "BODYSTRUCTURE", "BODY": self = .bodyStructure
            case "X-GM-LABELS":   self = .labels
            case "X-GM-THRID":    self = .threadID
            case "X-GM-MSGID":    self = .messageID
            default:
                let peek = upper.hasPrefix("BODY.PEEK[")
                guard peek || upper.hasPrefix("BODY["),
                      let open = upper.firstIndex(of: "["), let close = upper.firstIndex(of: "]")
                else { return nil }
                let section = String(upper[upper.index(after: open)..<close])
                let rest = upper[upper.index(after: close)...]
                var partial: Partial?
                if !rest.isEmpty {
                    let numbers = rest.dropFirst().dropLast().split(separator: ".")
                        .compactMap { Int($0) }
                    guard rest.hasPrefix("<"), rest.hasSuffix(">"), numbers.count == 2 else {
                        return nil
                    }
                    partial = Partial(start: numbers[0], count: numbers[1])
                }
                self = .section(section, peek: peek, partial: partial)
            }
        }
    }

    /// The SEARCH keys the repository uses, and a few neighbours.
    indirect enum SearchKey {
        case all
        case and([SearchKey])
        case or(SearchKey, SearchKey)
        case not(SearchKey)
        case field(String, String)
        /// `HEADER name value`: a header of that name holding the value.
        case header(String, String)
        case sent(Comparison, Date)
        case received(Comparison, Date)
        case flag(String, present: Bool)
        case deleted(Bool)
        case uids(UIDSet)
        /// Gmail's `X-GM-MSGID n`: the letter Gmail knows by that id.
        case gmailMessage(UInt64)

        enum Comparison { case since, before, on }

        static func parse(_ tokens: [Token]) -> SearchKey? {
            guard !tokens.isEmpty else { return nil }
            var index = 0
            var keys: [SearchKey] = []
            while index < tokens.count {
                guard let key = parseOne(tokens, &index) else { return nil }
                keys.append(key)
            }
            return keys.count == 1 ? keys[0] : .and(keys)
        }

        private static func parseOne(_ tokens: [Token], _ index: inout Int) -> SearchKey? {
            guard index < tokens.count else { return nil }
            let token = tokens[index]
            index += 1
            if let inner = token.items { return parse(inner) }
            guard let word = token.text?.uppercased() else { return nil }

            func argument() -> String? {
                guard index < tokens.count, let value = tokens[index].text else { return nil }
                index += 1
                return value
            }
            func day() -> Date? {
                argument().flatMap(ScriptedIMAPServer.searchFormatter.date(from:))
            }

            switch word {
            case "ALL": return .all
            case "OR":
                guard let a = parseOne(tokens, &index), let b = parseOne(tokens, &index) else {
                    return nil
                }
                return .or(a, b)
            case "NOT":
                return parseOne(tokens, &index).map { .not($0) }
            case "FROM", "TO", "CC", "BCC", "SUBJECT", "BODY", "TEXT":
                return argument().map { .field(word, $0) }
            case "HEADER":
                guard let name = argument(), let value = argument() else { return nil }
                return .header(name, value)
            case "SENTSINCE":  return day().map { .sent(.since, $0) }
            case "SENTBEFORE": return day().map { .sent(.before, $0) }
            case "SENTON":     return day().map { .sent(.on, $0) }
            case "SINCE":      return day().map { .received(.since, $0) }
            case "BEFORE":     return day().map { .received(.before, $0) }
            case "ON":         return day().map { .received(.on, $0) }
            case "SEEN", "UNSEEN":         return .flag("\\Seen", present: word == "SEEN")
            case "FLAGGED", "UNFLAGGED":   return .flag("\\Flagged", present: word == "FLAGGED")
            case "ANSWERED", "UNANSWERED": return .flag("\\Answered", present: word == "ANSWERED")
            case "DRAFT", "UNDRAFT":       return .flag("\\Draft", present: word == "DRAFT")
            case "DELETED", "UNDELETED":   return .deleted(word == "DELETED")
            case "UID":        return argument().flatMap(UIDSet.init).map { .uids($0) }
            case "X-GM-MSGID": return argument().flatMap { UInt64($0) }.map { .gmailMessage($0) }
            default:           return nil
            }
        }

        func matches(_ stored: Stored, key: Int, uid: UInt32, deleted: Bool,
                     highest: UInt32) -> Bool {
            let letter = stored.letter
            switch self {
            case .all:
                return true
            case .and(let keys):
                return keys.allSatisfy {
                    $0.matches(stored, key: key, uid: uid, deleted: deleted, highest: highest)
                }
            case let .or(a, b):
                return a.matches(stored, key: key, uid: uid, deleted: deleted, highest: highest)
                    || b.matches(stored, key: key, uid: uid, deleted: deleted, highest: highest)
            case .not(let inner):
                return !inner.matches(stored, key: key, uid: uid, deleted: deleted,
                                      highest: highest)
            case let .field(name, needle):
                let haystack: String
                switch name {
                case "FROM":    haystack = letter.from.formatted
                case "TO":      haystack = letter.to.map(\.formatted).joined(separator: ", ")
                case "CC":      haystack = letter.cc.map(\.formatted).joined(separator: ", ")
                case "BCC":     haystack = ""
                case "SUBJECT": haystack = letter.subject
                case "BODY":
                    haystack = String(decoding: stored.sections["TEXT"] ?? Data(), as: UTF8.self)
                default:        haystack = String(decoding: stored.raw, as: UTF8.self)
                }
                return haystack.range(of: needle, options: .caseInsensitive) != nil
            case let .header(name, needle):
                // RFC 3501: the field's text after the colon contains the
                // string, compared without regard to case. Folded lines are
                // not unfolded; nothing the repository searches for folds.
                let header = String(decoding: stored.sections["HEADER"] ?? Data(), as: UTF8.self)
                return header.components(separatedBy: "\r\n").contains { line in
                    guard let colon = line.firstIndex(of: ":"),
                          line[..<colon].caseInsensitiveCompare(name) == .orderedSame else {
                        return false
                    }
                    return line[line.index(after: colon)...]
                        .range(of: needle, options: .caseInsensitive) != nil
                }
            case let .sent(comparison, day), let .received(comparison, day):
                // Both by the day in UTC, which is the zone every seeded
                // Date header is written in: SENT* by its Date, the rest by
                // when it arrived.
                let calendar = Self.utc
                let when: Date
                if case .sent = self { when = letter.date } else { when = letter.arrival }
                let letterDay = calendar.startOfDay(for: when)
                let asked = calendar.startOfDay(for: day)
                switch comparison {
                case .since:  return letterDay >= asked
                case .before: return letterDay < asked
                case .on:     return letterDay == asked
                }
            case let .flag(flag, present):
                return stored.flags.contains(flag) == present
            case .deleted(let wanted):
                return deleted == wanted
            case .uids(let set):
                return set.contains(uid, highest: highest)
            case .gmailMessage(let id):
                return ScriptedIMAPServer.gmailMessageID(key: key) == id
            }
        }

        private static let utc: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            return calendar
        }()
    }
}

// MARK: - The transport

/// One connection to a `ScriptedIMAPServer`, standing where `TLSConnection`
/// stands on the device.
///
/// Only the link is this type's. Everything above it, the framing, the
/// deadlines and what each does when it fires, what `close()` ends and the
/// B-034 probes, is `LinkTransport`'s, the same code `TLSConnection` runs,
/// so a wire test that exercises it exercises the device's. The link behaves
/// as `NWConnection` does: a receive ends when bytes arrive or the link
/// dies, and a send when its piece has gone or the link dies; cancellation
/// ends neither, and letting go of the link ends both with an error. A
/// handshake that `handshakeStalls` holds up never reports at all, not even
/// once the link has been let go of, which is the most `NWConnection`
/// promises about a connect whose state handler has been cleared. Each
/// server reply is one chunk.
///
/// It also watches its writes, which is the one thing it does above the
/// link: see `write(_:progress:)`.
actor ScriptedTransport: LinkTransport {

    nonisolated let connection: Int
    private let server: ScriptedIMAPServer
    private let port: UInt16
    var stream = LinkStream()
    /// The handshake has finished and the link has not been let go of.
    private var linkUp = false
    /// How to report a handshake `holdHandshakes()` is holding, once it is
    /// let go.
    private var heldHandshake: (@Sendable (Error?) -> Void)?

    private enum Arrival: Sendable {
        case bytes(Data)
        case failed(MailTransportError)
    }

    /// What has arrived and that no receive has taken yet.
    private var arrived: [Arrival] = []
    /// The receive waiting for the next arrival. Never more than one: see
    /// `nextArrival`.
    private var waiter: CheckedContinuation<Arrival, Never>?
    /// Delayed replies still on their way, and the last of them, so the next
    /// one can queue behind it.
    private var inFlight = 0
    private var lastInFlight: Task<Void, Never>?
    /// Replies held by `holdReplies(to:)`, and anything sent after them,
    /// which has to stay behind them.
    private var parked: [ScriptedIMAPServer.Reply] = []
    /// A write is being handed over. A second one starting meanwhile is two
    /// commands in flight.
    private var isWriting = false
    /// The piece of a write still going out over `uplinkDelay`, and the
    /// timer that lets it go.
    private var sending: CheckedContinuation<Void, Error>?
    private var sendTimer: Task<Void, Never>?

    fileprivate init(server: ScriptedIMAPServer, port: UInt16) {
        self.server = server
        self.port = port
        self.connection = server.newConnectionID()
    }

    var ordinaryDeadline: TimeInterval { server.timeout(on: connection).timeInterval }
    var uploadReplyDeadline: TimeInterval { server.uploadReplyTimeout.timeInterval }

    /// `LinkTransport`'s write, watched. A write while the reply to the
    /// command before it is still unread, or while another write is being
    /// handed over, is two commands in flight, and is recorded. The server
    /// takes the bytes once the last piece has gone: a command, or a
    /// literal, means nothing to it until its last byte anyway.
    func write(_ data: Data, progress: UploadProgress?) async throws {
        if stream.isOpen, isWriting || !stream.buffer.isEmpty || !arrived.isEmpty || inFlight > 0
            || !parked.isEmpty || waiter != nil {
            let text = String(decoding: data.prefix(60), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            server.noteViolation("c\(connection): \"\(text)\" was written before "
                                 + "the reply to the command before it had been read")
        }
        isWriting = true
        defer { isWriting = false }
        try await writeThroughLink(data, progress: progress)
        for reply in server.receive(data, on: connection) { deliver(reply) }
    }

    // MARK: - The link

    /// Refused for anything but the IMAP port, as ECONNREFUSED. Accepted,
    /// the server greets at once, unless it is silent.
    func startLink(reporting report: @escaping @Sendable (Error?) -> Void) {
        guard port == server.port else {
            report(MailTransportError.posix("POSIX 61"))
            return
        }
        guard !server.handshakeStalls else { return }
        guard !server.handshakesAreHeld else {
            heldHandshake = report
            return
        }
        linkUp = true
        report(nil)
        if let greeting = server.accept(connection) { deliver(greeting) }
    }

    /// Finishes a handshake `holdHandshakes()` held, as `startLink` would
    /// have.
    fileprivate func finishHeldHandshake() {
        guard let report = heldHandshake else { return }
        heldHandshake = nil
        linkUp = true
        report(nil)
        if let greeting = server.accept(connection) { deliver(greeting) }
    }

    /// `NWConnection.receive`'s part: the next reply, or the reason there
    /// will not be one. Cancellation does not end it.
    func receiveFromLink() async throws -> Data {
        guard linkUp else { throw MailTransportError.closed }
        if let reset = server.resetError(for: connection) { throw reset }
        switch await nextArrival() {
        case .bytes(let data):     return data
        case .failed(let error):   throw error
        }
    }

    /// `NWConnection.send`'s part: one piece, taken after `uplinkDelay` for
    /// every `TransportDeadline.writeChunkBytes` of it, so a write handed
    /// over in one lump takes as long as the pieces it should have gone in.
    /// Cancellation does not end it; letting go of the link does.
    func sendToLink(_ piece: Data) async throws {
        guard linkUp else { throw MailTransportError.closed }
        let chunks = (piece.count + TransportDeadline.writeChunkBytes - 1)
            / TransportDeadline.writeChunkBytes
        let delay = server.uplinkDelay * max(1, chunks)
        guard delay > .zero else { return }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            sending = c
            sendTimer = Task.detached { [weak self] in
                try? await Task.sleep(for: delay)
                await self?.finishSending(failing: nil)
            }
        }
    }

    /// As `NWConnection.cancel()`: a piece of a write or a receive still
    /// pending ends now, with an error, and the server hears the hang-up.
    func closeLink() {
        finishSending(failing: .closed)
        heldHandshake = nil
        guard linkUp else { return }
        linkUp = false
        arrived.removeAll()
        parked.removeAll()
        wake(with: .failed(.closed))
        server.hangUp(connection)
    }

    private func finishSending(failing error: MailTransportError?) {
        guard let pending = sending else { return }
        sending = nil
        sendTimer?.cancel()
        sendTimer = nil
        if let error { pending.resume(throwing: error) } else { pending.resume() }
    }

    /// One waiter at most. A second read while one is already waiting means
    /// two commands are in flight on this connection; a lone slot would have
    /// the second read silently replace the first, which then never
    /// resumes and hangs the test instead of failing it. So the second read
    /// is recorded and fails at once.
    private func nextArrival() async -> Arrival {
        if !arrived.isEmpty { return arrived.removeFirst() }
        if waiter != nil {
            server.noteViolation("c\(connection): a second read started while one was "
                                 + "already waiting")
            return .failed(.posix("two reads at once"))
        }
        return await withCheckedContinuation { waiter = $0 }
    }

    /// The connection was reset under a read that is waiting: it fails now,
    /// as a pending receive does on an RST, and whatever had arrived or was
    /// still on its way is gone. So does a piece of a write still going out.
    fileprivate func interrupt(with error: MailTransportError) {
        arrived.removeAll()
        parked.removeAll()
        finishSending(failing: error)
        wake(with: .failed(error))
    }

    /// A read is waiting on the link for bytes.
    var isAwaitingBytes: Bool { waiter != nil }

    /// Bytes that land in the same moment the transport is closed: the
    /// receive waiting on the link has them, and the transport is closed
    /// before that receive can hand them on. That is another task closing
    /// the transport under a read, which the exchange gate keeps the clients
    /// from doing, and which the transport has to come through anyway.
    func landAndClose(_ bytes: Data) {
        arrive(.bytes(bytes))
        close()
    }

    fileprivate func parkedReplies(to verb: String) -> Int {
        parked.filter { $0.verb == verb }.count
    }

    fileprivate func releaseParked() {
        let replies = parked
        parked = []
        for reply in replies { deliver(reply) }
    }

    private func deliver(_ reply: ScriptedIMAPServer.Reply) {
        if !parked.isEmpty || server.isHeld(reply) {
            parked.append(reply)
            return
        }
        guard reply.delay > .zero || inFlight > 0 else {
            land(reply)
            return
        }
        inFlight += 1
        let previous = lastInFlight
        lastInFlight = Task.detached { [weak self] in
            await previous?.value
            try? await Task.sleep(for: reply.delay)
            await self?.landDelayed(reply)
        }
    }

    private func landDelayed(_ reply: ScriptedIMAPServer.Reply) {
        inFlight -= 1
        land(reply)
    }

    private func land(_ reply: ScriptedIMAPServer.Reply) {
        arrive(.bytes(reply.bytes))
        if reply.closesAfter { arrive(.failed(.closed)) }
    }

    private func arrive(_ arrival: Arrival) {
        // Nothing reaches a link that has been let go of or reset.
        guard linkUp, server.resetError(for: connection) == nil else { return }
        if waiter != nil {
            wake(with: arrival)
        } else {
            arrived.append(arrival)
        }
    }

    private func wake(with arrival: Arrival) {
        guard let waiter else { return }
        self.waiter = nil
        waiter.resume(returning: arrival)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
