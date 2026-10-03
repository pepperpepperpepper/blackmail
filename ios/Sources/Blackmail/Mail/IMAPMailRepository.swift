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
/// and back, the snapshots and search sessions that paging walks, and which
/// letter the server has named under each UID in this launch (`seen`).
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
    /// The signature's pictures, read at each use as account setup left
    /// them. The app's come from the standard defaults; the host tests hand
    /// in their own, for the same reason as the recipient book's.
    private let signatureImages: @Sendable () -> [SignatureImages.InlineImage]

    /// Role → real IMAP name, learned from LIST's special-use attributes.
    /// Never hard-code "Trash": Gmail calls it "[Gmail]/Trash", and on an
    /// account in another language it is not an English word at all.
    private var roleNames: [Mailbox.Role: String] = [:]
    /// The last whole message downloaded, kept so opening an attachment does
    /// not re-fetch the entire message it came from, with Gmail's id for
    /// the letter it is when the server has named it
    /// (`Message.gmailMessageID`): a part a letter being built names by
    /// that id is taken from here only when it is the same letter
    /// (`carriedPart`).
    private var lastBody: (messageID: String, letter: UInt64?, raw: Data)?
    /// The structure of the last letter opened without its files
    /// (`loadLetterInPartOnce`), as `lastBody` is the last opened whole. A
    /// part of it, a picture the pane asks for or a file he taps, is then
    /// one FETCH of its section, where a part of a letter no longer to hand
    /// is two, the first describing the whole letter again
    /// (`fetchAttachmentData`). Not for a forward's parts that name their
    /// letter, which the FETCH that describes it vouches for (`carriedPart`).
    private var lastStructure: (messageID: String, structure: MIMEPart)?
    /// The copies this launch has put in Drafts itself, by folder name and
    /// id, as APPENDUID gave them, or as the search by its version's
    /// Message-ID found one a cut-off upload left (`saveDraft`). One
    /// reopened is fetched with Gmail's id for it asked in the same FETCH
    /// (`loadMessageOnce`), so the draft made from it names its copy, and
    /// the files and pictures it carries in that copy, by the id as a draft
    /// reopened from a listed row does.
    private var appendedHere: Set<String> = []
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

    /// Gmail's id for the letter under each UID of each folder, as the
    /// server has named it in this launch: in every row it has sent, from
    /// whichever listing, page, day, search or check for news (`rows`), in
    /// every answer to a question about a row it had not sent (`settle`),
    /// in a copy this launch put in Drafts, reopened (`loadMessageOnce`),
    /// and in the FETCH that describes a letter a part is carried from
    /// (`carriedPart`). By folder name, under the UIDVALIDITY it was named
    /// in; a new one forgets the folder's (`saw`).
    ///
    /// What a write, or a letter opened, that names its row's Gmail message
    /// id is decided by (`question`): where the server has named that
    /// letter under the row's UID in this launch it goes as it always did,
    /// where it has named another it goes nowhere, and where it has named
    /// none yet the server is asked. It used to be decided by whether the
    /// folder had been listed, which is not the same. The folder's page kept
    /// on the iPad (D-016) is still drawn after a listing has thrown it
    /// away, while the fresh page waits for a finger to lift or for his
    /// ticks to go (`KeptSwap`), and in the moment before the swap reaches
    /// the screen, and a write on one of those rows went unasked, onto
    /// whatever letter this mailbox has under that UID.
    private var seen: [String: SeenLetters] = [:]

    /// One folder's part of `seen`.
    private struct SeenLetters {
        let validity: UInt32
        var letters: [UInt32: UInt64] = [:]
    }

    /// The copy of his mail kept on the iPad (D-016): each folder's newest
    /// page as a listing from the top gives it, the folder list from every
    /// sweep, and his writes once the server has taken them. Nil in a test
    /// that does not look at it. Read by the screens as well, for what they
    /// draw before anything has been sent.
    nonisolated let shelf: MailShelf?

    /// One factory for both protocols: it is told the host and port, which
    /// is all that tells an IMAP connection from an SMTP one.
    ///
    /// `now` is the clock the write probe measures quiet by, and the client
    /// how long ago it asked for a mailbox's news (`IMAPClient.catchUp`).
    /// The app's is the real one; a test hands in one it can move, because
    /// the probe only happens after ninety seconds of it. `calendar` is his,
    /// the days a jump to a date counts in (`messages(around:)`); the app's
    /// follows the iPad's zone as it changes, and a test's is the one it
    /// sets.
    init(account: MailAccount, password: String,
         transport: @escaping MailTransportFactory,
         recipients: RecipientBook = .shared,
         now: @escaping @Sendable () -> Date = { Date() },
         calendar: Calendar = .autoupdatingCurrent,
         signatureImages: @escaping @Sendable () -> [SignatureImages.InlineImage]
            = { SignatureImages.load() },
         shelf: MailShelf? = nil,
         largeLetterBytes: Int = IMAPMailRepository.largeLetterBytes,
         largeLetterSectionBytes: Int = IMAPMailRepository.largeLetterSectionBytes) {
        self.account = account
        self.password = password
        self.largeAbove = largeLetterBytes
        self.largeSection = largeLetterSectionBytes
        self.imap = IMAPClient(account: account, transport: transport, now: now)
        self.smtp = SMTPClient(account: account, transport: transport)
        self.recipients = recipients
        self.now = now
        self.calendar = calendar
        self.signatureImages = signatureImages
        self.shelf = shelf
        // His own address, always offered, from the very first launch.
        // He writes to himself constantly and it is the one address the
        // book cannot learn by watching his mail go past — a letter to
        // himself only teaches it after he has already typed it once.
        recipients.note(address: account.address, name: account.displayName)
    }

    #if canImport(Network)
    /// The app's own: the real TLS stack, and the copy of his mail kept in
    /// Application Support, which is this account's alone. Made at launch,
    /// so another account's copy goes then.
    init(account: MailAccount, password: String) {
        self.init(account: account, password: password, transport: TLSConnection.factory,
                  shelf: MailShelf(root: MailShelf.appRoot, address: account.address,
                                   host: account.imapHost))
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
    /// free of consequences. A write goes again only when nothing of it was
    /// sent at all (`sendingOnce`).
    ///
    /// Not when the read had to connect first and the connect failed. A
    /// refused LOGIN is the case that matters: retrying it sends the same
    /// wrong password a second time, so with a revoked app password every
    /// search he typed cost two failed logins, and Gmail throttles an account
    /// that keeps failing to authenticate. A server that could not be
    /// reached a moment ago will not be reached by asking again at once
    /// either, and on the device each attempt can take the whole connect
    /// timeout. A refused sign-in, the password's or another, is never
    /// retried, however it arose.
    ///
    /// Nor when an attempt to connect failed while the read waited, whoever
    /// made it. The client calls itself connected from the moment the socket
    /// is up, before the greeting and the LOGIN, so a read that began in that
    /// window found a connection that was up and queued behind the rest of
    /// its making. When that failed, a greeting that never came or a socket
    /// that died during the LOGIN, the read took it for a dropped socket and
    /// connected again: at launch, against a server that accepts and then
    /// says nothing, a second connect timeout, the one the attempt's own
    /// answer exists to spare (`IMAPClient.connect`). Whether the read began
    /// in that window or just before it was the order two tasks happened to
    /// run in, so the suite caught it now and then.
    ///
    /// Nor for a caller that has been cancelled. Only a search is ever
    /// cancelled, by the next keystroke, and cancelling one no longer costs
    /// the connection: the command it had on the wire finishes and the next
    /// is refused at the client's exchange gate. What reaches here from a
    /// cancelled caller is that refusal, or a real failure nobody is waiting
    /// to hear about, and neither is worth a fresh connection.
    ///
    /// Torn down, not "not connected now". Asked that way, a call whose
    /// connection had died found another call's reconnect already up, took
    /// its own failure for a refusal, and did not go again: a Delete made
    /// while the warm-up's NOOP, or the watch's, was out on a dead socket
    /// probed, found the socket dead with it, and failed if the warm-up had
    /// reconnected first, which it did in 7 of 320 runs with eight copies of
    /// the suite's test running at once. A write is never retried, so the
    /// letter stayed where it was. The watch sends such a NOOP every half
    /// minute (`MailWatch`), so what was a return to the app is any moment.
    private func retryingIfDisconnected<T>(
        _ body: () async throws -> T) async throws -> T {
        let before = Self.Attempt(connected: await imap.isConnected,
                                  lost: await imap.connectionsLost,
                                  failedConnects: await imap.failedConnects)
        do {
            return try await body()
        } catch {
            guard !Task.isCancelled,
                  Self.retries(error, began: before,
                               after: Self.Attempt(connected: await imap.isConnected,
                                                   lost: await imap.connectionsLost,
                                                   failedConnects: await imap.failedConnects))
            else { throw error }
            return try await body()
        }
    }

    /// The connection as a call found it, before it began and after it
    /// failed: up or not, and how many connections had been torn down and
    /// attempts to make one had failed by then.
    struct Attempt: Equatable {
        var connected: Bool
        var lost: Int
        var failedConnects: Int
    }

    /// Whether a read that failed with `error` goes again, by the rules
    /// above: only when a connection it began on has been torn down since,
    /// whether or not another call has connected again by the time it
    /// looks, and no attempt to connect has failed meanwhile; never for a
    /// refused sign-in. Apart from the connection so the suite can put it
    /// in each state it can be found in, which the calls themselves reach
    /// only in orders two tasks happen to run in (the stress tests of the
    /// Delete made while a NOOP is out, which pass without the rule on most
    /// runs).
    static func retries(_ error: Error, began before: Attempt, after: Attempt) -> Bool {
        before.connected
            && !MailError.refusesSignIn(error)
            && after.lost != before.lost
            && after.failedConnects == before.failedConnects
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
    private let calendar: Calendar

    /// How many calls are waiting for the connection behind the one using
    /// it. How a test knows a call has joined the line without sleeping on it.
    var waitingForExchange: Int {
        get async { await imap.waitingForExchange }
    }

    /// Never for a retired repository, whose connection is on its way to
    /// its LOGOUT: work nobody asked for goes on the new one (`retire`).
    var isConnected: Bool {
        get async {
            guard !retired else { return false }
            return await imap.isConnected
        }
    }

    private func connected() async throws -> IMAPClient {
        guard !retired else { throw MailError.cannotConnect }
        lastContact = now()
        if await imap.isConnected { return imap }
        // The warm-up or the watch has sent the password a moment ago, and
        // Gmail refused it. See `warmUp`.
        if let refused = refusedUnasked {
            guard now().timeIntervalSince(refused) >= Self.refusalStands else {
                throw MailError.passwordNeedsUpdating
            }
            refusedUnasked = nil
        }
        // A new session starts with nothing selected. The client clears its
        // own selection as it connects; there used to be a copy of it here,
        // cleared only once this returned, and a tap in between, with the
        // client already reporting connected, skipped its SELECT and was
        // answered BAD.
        try await imap.connect(password: password)
        return imap
    }

    /// When a connection made for work he did not ask for had its password
    /// refused, nil if it has not been: the one `warmUp` made in place of a
    /// dead one, or the watch's (`watchedConnection`). For `refusalStands`
    /// after that no call connects; the next `warmUp` clears it.
    private var refusedUnasked: Date?

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
    /// The password cannot change under a running repository in any case:
    /// one saved in Settings is signed in with at once, by a new repository
    /// in this one's place (`PasswordChange`).
    ///
    /// Nothing is sent as the app goes into the background. A LOGOUT there
    /// would cost a whole reconnect on every return, however short.
    func warmUp() async {
        guard !retired else { return }
        refusedUnasked = nil
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
            refusedUnasked = now()
        } catch {
            // Unreachable, most likely. The next call tries for itself.
        }
    }

    /// Set by `retire`: this repository sends nothing more.
    private var retired = false

    /// A new password has been saved in Settings, and a new repository signs
    /// in with it in this one's place (`PasswordChange`). The connection is
    /// closed and no other is made (`IMAPClient.retire`), and no letter goes
    /// through here from now on, so whatever still holds this one, the
    /// screens it was drawn on until they go, a pass over the Outbox under
    /// way, sends the old password nowhere and reaches the mailbox it opened
    /// no more, which after the app-password trap (B-033) may be another's.
    /// Nothing more goes on the old connection either, while its LOGOUT
    /// waits for the command already on the wire: no call gets it, and a
    /// pass finds it down. A letter from the Outbox refused here waits for
    /// the next pass, which is the new repository's: nothing of it was
    /// sent. Returns at once.
    func retire() async {
        retired = true
        await imap.retire()
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

    /// Sends a WRITE once: again, on a new connection, only when its turn at
    /// the connection came with none there, and nothing of it had gone
    /// (`IMAPClient.Unsent`).
    ///
    /// The probe covers a write made after ninety seconds of quiet. It does
    /// not cover one made while something else holds the connection and
    /// finds the socket dead: the watch's NOOP every half minute (`MailWatch`),
    /// or a preview's FETCH, with the connection proven a moment before so
    /// no probe went. The write waited behind that command, and when the
    /// command tore the connection down it met none, and failed with not a
    /// byte of it sent. On a half-open socket that was every write made in
    /// the thirty seconds the command waited for its answer. A write is
    /// never sent twice, so the letter he binned stayed in the Inbox, and a
    /// read mark came back off.
    ///
    /// Once more, by the rules a read's retry keeps: not for a refused
    /// password, not when an attempt to connect failed while the write
    /// waited, whoever made it, and not for a caller that has been
    /// cancelled. The connection is made by `connected()`, which honours a
    /// refusal the warm-up or the watch has just been given.
    private func sendingOnce<T>(_ write: () async throws -> T) async throws -> T {
        let failuresBefore = await imap.failedConnects
        do {
            return try await write()
        } catch let unsent as IMAPClient.Unsent {
            guard !Task.isCancelled, !unsent.failure.refusesSignIn,
                  await imap.failedConnects == failuresBefore else { throw unsent.failure }
            _ = try await connected()
            do {
                return try await write()
            } catch let again as IMAPClient.Unsent {
                throw again.failure
            }
        }
    }

    // MARK: - The watch

    /// How long after a sign-in refused for a reason that is not the
    /// password the watch tries again (`watchedConnection`): every tenth
    /// check, twelve LOGINs an hour while the app is in front, against the
    /// hundred and twenty a check every half minute would send. Google
    /// counts failed sign-ins against an account; a refusal like these is
    /// not the password failing, and a helper who has done what Google
    /// asked sees the mail come back within five minutes without touching
    /// the iPad.
    static let refusedSignInWaits: TimeInterval = 5 * 60

    /// The most new letters one check puts on the list. More than a page
    /// comes in between two checks only when the list has been held back
    /// for hours, or the folder has been filled from elsewhere, and the
    /// newest fifty of them on top of the list would leave a gap under them
    /// that paging never fills; so the list is fetched afresh instead
    /// (`FolderNews.refetch`).
    static let mostNews = 50

    /// What has come into the folder, and gone from it, since its list was
    /// fetched: for `MailWatch`, every half minute while the Inbox's list is
    /// in front of him (B-049).
    ///
    /// When nothing has changed, and that is nearly every time, this is one
    /// NOOP (`IMAPClient.askForNews`). When something has, one SEARCH from
    /// the lowest letter the list holds, which says both what has arrived
    /// above its newest and which of its letters have gone, and a FETCH of
    /// the new letters' summaries alone. Previews are the list's to ask for
    /// once it shows them, within the usual byte caps. Each is a hold of the
    /// connection of its own in the background line, so what he taps
    /// meanwhile waits for one exchange at most. Nothing is listed afresh:
    /// no SEARCH ALL and no page is fetched again.
    ///
    /// `searchingAnyway` when the last check's news never reached the list:
    /// the session has been told of it, and says nothing has changed.
    ///
    /// A read, retried once into a new connection when its NOOP finds the
    /// socket dead, which a check in the quiet is the likeliest thing to
    /// find; the reconnect's SELECT then serves as the question. It connects
    /// by the rules for work he did not ask for, `watchedConnection`.
    func news(in mailboxID: String, known: [String],
              searchingAnyway: Bool) async throws -> FolderNews {
        try await retryingIfDisconnected {
            try await self.newsOnce(in: mailboxID, known: known, searchingAnyway: searchingAnyway)
        }
    }

    private func newsOnce(in mailboxID: String, known: [String],
                          searchingAnyway: Bool) async throws -> FolderNews {
        let client = try await watchedConnection()
        let name = try await resolve(mailboxID)
        let asked = try await client.askForNews(of: name)
        // Proven by the answer, as the warm-up's NOOP proves it: a write in
        // the next ninety seconds goes without a probe of its own (B-024).
        lastContact = now()

        let listed = known.compactMap { try? Self.parseID($0) }
        // Renumbered since the list was fetched: every id on it names
        // another letter now, or none.
        if let validity = listed.first?.validity, validity != asked.validity {
            return FolderNews(refetch: true)
        }
        guard asked.changed || searchingAnyway else { return FolderNews() }

        let uids = listed.map(\.uid)
        let present = try await client.searchNews(in: name, validity: asked.validity, from: uids.min())
        let still = Set(present)
        let gone = uids.filter { !still.contains($0) }
            .map { Self.makeID(validity: asked.validity, uid: $0) }
        let newest = uids.max()
        let arriving = present.filter { uid in newest.map { uid > $0 } ?? true }
        guard arriving.count <= Self.mostNews else {
            Diagnostics.log(.note, "NEWS folder=\(name) arrived=\(arriving.count) refetch")
            return FolderNews(gone: gone, refetch: true)
        }
        let arrived = try await summaries(for: arriving.reversed(), in: mailboxID, name: name,
                                          validity: asked.validity, client: client)
        Diagnostics.log(.note, "NEWS folder=\(name) arrived=\(arrived.count) gone=\(gone.count)")
        return FolderNews(arrived: arrived, gone: gone)
    }

    /// The Inbox's unread count as the server has it now, one STATUS, or
    /// nil if the server will not say. For the watch while another folder
    /// is in front of him: the Inbox's count beside its name follows new
    /// mail, and nothing else about the Inbox is fetched until he opens it.
    /// A read, retried and connected as `news` is.
    func inboxUnread() async throws -> Int? {
        try await retryingIfDisconnected {
            let client = try await self.watchedConnection()
            let name = try await self.resolve("inbox")
            let counts = try await client.status(name, items: ["UNSEEN"])
            self.lastContact = self.now()
            return counts["UNSEEN"].map { Int($0) }
        }
    }

    /// The connection for the watch, made or not by the rules for work he
    /// did not ask for.
    ///
    /// Not `connected()`, which stamps `lastContact` as the call starts. The
    /// watch's NOOP is a probe, as the warm-up's is, and a write he makes
    /// while it is out must not take the connection for proven before it
    /// has been (see `warmUp`): the caller stamps it once an answer comes.
    ///
    /// It makes a connection where there is none, since new mail cannot be
    /// found without one. After a socket that died and could not be
    /// replaced at once, Wi-Fi off and on again, the next check reconnects
    /// by itself. With no network at all each attempt fails at once, before
    /// any TLS, since the transport takes `.waiting` for a failure.
    ///
    /// Never after the password was refused, until a connection has been
    /// made since. Every half minute that would be a loop of failed logins,
    /// and Gmail locks out an account that keeps failing to authenticate.
    /// Only what he does sends a password again: his next tap once
    /// `refusalStands` has passed, or a new one saved in Settings, which a
    /// new repository signs in with; if that is accepted the watch carries
    /// on. A refusal of the watch's
    /// own stands for every call for `refusalStands`, as the warm-up's does,
    /// so the letter he taps a moment later does not send the same password
    /// straight after it.
    ///
    /// A sign-in refused for another reason is tried again, once
    /// `refusedSignInWaits` has passed since the last refusal. What Google
    /// refuses that way it lets go of without anything done on the iPad: a
    /// sign-in on the web made by a helper, a limit on connections or
    /// bandwidth that runs out. Never tried again, the list said so, and no
    /// new mail came, until he happened to tap something.
    ///
    /// The client's `loginRefusal` is the whole rule here, and
    /// `refusedUnasked` is not asked. Every refusal that sets the one sets
    /// the other, and the client's lasts until a LOGIN is accepted, longer
    /// than the minute; so `refusedUnasked` without it is a refusal a LOGIN
    /// has been accepted since, and a password that works now.
    private func watchedConnection() async throws -> IMAPClient {
        guard !retired else { throw MailError.cannotConnect }
        if await imap.isConnected { return imap }
        if let refusal = await imap.loginRefusal,
           refusal.failure == .passwordNeedsUpdating
            || now().timeIntervalSince(refusal.at) < Self.refusedSignInWaits {
            throw refusal.failure
        }
        do {
            try await imap.connect(password: password)
        } catch MailError.passwordNeedsUpdating {
            refusedUnasked = now()
            throw MailError.passwordNeedsUpdating
        }
        lastContact = now()
        return imap
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
        let folders = Self.mailboxes(from: listings, unread: unread)
        // What the folder pane draws at the next launch before it has asked
        // anything (D-016).
        shelf?.took(folders: folders)
        return folders
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
            //
            // After the LIST, whatever the folder. The roles and the
            // attribute table say which folders a row is counted in
            // (`countedFolders`), and a folder tapped in the folder pane
            // drawn from the copy kept on the iPad (D-016) can be listed
            // before the launch's LIST has landed: its rows were drawn, and
            // kept, without All Mail or Important among them, so reading
            // one left those counts high until the next sweep, at every
            // launch after until the folder was listed again. Nothing is
            // sent once the LIST is known, a LIST on the wire is joined, and
            // at launch the Inbox's own name has asked for it already.
            _ = try await knownListing()
            let opened = try await client.page(in: name, searching: ["ALL"]) { found in
                PageWindow.older(than: nil, in: found[0], limit: limit)
            }
            listing = opened.found[0]
            uidListing[name] = listing
            summaries = rows(from: opened.summaries, in: mailboxID, name: name,
                             validity: listing.validity)
            // The folder's page kept on the iPad, replaced whole by this one
            // (D-016), unless this listing says the kept one was not this
            // mailbox's, when the whole copy goes first. Numbers and a
            // reason only: nothing kept is ever written to this log.
            let sizes = summaries.reduce(into: [String: Int]()) { sizes, row in
                sizes[row.id] = largeLetters[Self.key(row.id, in: name)]
            }
            if let discard = shelf?.took(page: summaries, of: name, validity: listing.validity,
                                         sizes: sizes) {
                Diagnostics.log(.note, "KEPT-DISCARDED folder=\(name) "
                                + "reason=\(discard == .renumbered ? "uidvalidity" : "msgid")")
            }
        }
        // B-033: the session's identity, pinned with numbers rather than
        // read off glass. The SELECTed folder, its UIDVALIDITY, how many
        // messages the server says exist, and the ids of the newest row this
        // listing drew — enough to match this session against one real
        // mailbox, server-side, beyond argument.
        //
        // Numbers only. It named the first row's sender too until D-016,
        // which is what told apart which letter of a conversation headed
        // the list: on Gmail first-row is the thread id, which every letter
        // of the conversation shares. msgid, Gmail's id for the letter
        // itself, pins that without naming anyone; a sender is his
        // correspondence, in a log made to be copied out to whoever is
        // helping.
        let exists = await client.lastReport(for: name)?.exists ?? -1
        let newestID = summaries.first?.threadID ?? summaries.first?.id ?? "-"
        let newestLetter = summaries.first?.gmailMessageID.map(String.init) ?? "-"
        Diagnostics.log(.note, "SESSION-IDENT folder=\(name) "
                        + "uidv=\(listing.validity) "
                        + "exists=\(exists) "
                        + "uids=\(listing.uids.count) "
                        + "first-row=\(newestID) "
                        + "msgid=\(newestLetter)")
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
    ///
    /// Every row on its way to the screen passes here, and the Gmail id
    /// each carries is what this launch has seen under its UID (`seen`), so
    /// a write on it, or its letter opened, goes as it always did.
    private func rows(from fetched: [IMAPFetchResult], in mailboxID: String, name: String,
                      validity: UInt32) -> [MessageSummary] {
        defer { recipients.flush() }
        var named: [UInt32: UInt64] = [:]
        defer { saw(named, validity: validity, in: name) }
        return fetched.compactMap { r -> MessageSummary? in
            guard let uid = r.uid else { return nil }
            if let letter = r.gmailMessageID { named[uid] = letter }
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
            let id = Self.makeID(validity: validity, uid: uid)
            rememberPreviewPart(r.bodyStructure, for: id)
            if let size = r.size, size > largeAbove {
                rememberLarge(id, in: name, size: size)
            }
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
                gmailMessageID: r.gmailMessageID,
                countedFolderIDs: countedFolders(labels: r.labels, selected: name),
                attachments: r.bodyStructure.map(MIMEDecoder.listedAttachments(in:)) ?? [],
                // Whom it is to, for the row's top line in Sent Mail and
                // Drafts (`RowNames`, B-060). Nil with no ENVELOPE, which
                // names the sender as before rather than say a letter had
                // no recipients.
                to: env.map { $0.to.map(\.formatted) },
                // From the ENVELOPE the row is fetched with already, so the
                // header has its Cc line from the tap; nothing more is asked.
                cc: env?.cc.map(\.formatted) ?? [],
                bcc: env?.bcc.map(\.formatted) ?? [])
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
        let dated = IMAPDate.sentOnOrAfter(date, now: now(), timeZone: calendar.timeZone)
        let opened = try await client.page(in: name, searching: [dated, "ALL"]) {
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
        guard !rows.isEmpty else { return nil }
        // Gmail's day runs from midnight UTC, his from his own midnight:
        // landed on the first letter of his day (`PageWindow.landing`).
        let dayStart = calendar.startOfDay(for: date)
        let notAfter = calendar.date(byAdding: .day, value: IMAPDate.arrivalSlack + 1,
                                     to: now()) ?? now()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let searchedFrom = utc.date(from: calendar.dateComponents([.year, .month, .day],
                                                                  from: date)) ?? dayStart
        let landedIndex = PageWindow.landing(
            dates: rows.map(\.date), anchor: rows.firstIndex { $0.id == anchorID } ?? 0,
            dayStart: dayStart, searchedFrom: searchedFrom, notAfter: notAfter)
        // Landed before his day, or on a letter dated wrong, with every newer
        // letter in the window: none is on or after his day, only the evening
        // before it as Gmail counts, so there is nothing that recent.
        let landedDate = rows[landedIndex].date
        if window.reachedNewest, landedDate < dayStart || landedDate > notAfter {
            return nil
        }

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

    /// Above this, a letter is opened without its files
    /// (`loadLetterInPartOnce`). Photographs from Mail or an iPhone are
    /// two to four megabytes each on the wire, so it is a letter of two or
    /// more.
    static let largeLetterBytes = 5 << 20

    /// How much of a large letter's text, and of its HTML, is fetched.
    /// Ample for any letter written by a person: a newsletter is 50 to 200
    /// KB.
    static let largeLetterSectionBytes = 2 << 20

    /// The two above, as this repository was made with them. The app's are
    /// always those; a test's can be small, so a letter of a few kilobytes
    /// stands for one of megabytes.
    private let largeAbove: Int
    private let largeSection: Int

    /// The size of every letter above `largeAbove` the server has
    /// listed in this launch, by folder and id (`key`), from the
    /// RFC822.SIZE its row is fetched with. Only those: a letter not here
    /// is opened whole, as every letter was.
    private var largeLetters: [String: Int] = [:]

    /// Insertion order, so `largeLetters` can drop its oldest past
    /// `maximumRememberedLarge`. One dropped is looked for on the kept
    /// page, and opened whole if it is not there.
    private var largeLetterOrder: [String] = []
    private static let maximumRememberedLarge = 2_000

    private func rememberLarge(_ id: String, in name: String, size: Int) {
        let key = Self.key(id, in: name)
        if largeLetters.updateValue(size, forKey: key) == nil { largeLetterOrder.append(key) }
        while largeLetterOrder.count > Self.maximumRememberedLarge {
            largeLetters.removeValue(forKey: largeLetterOrder.removeFirst())
        }
    }

    /// The size of the letter `id` in `name` when it is above
    /// `largeAbove`: as this launch listed it, or as the page kept on
    /// the iPad has it, for a row drawn from there before its folder's
    /// first page has come (D-016). Nil otherwise.
    private func largeLetterSize(_ id: String, in name: String) -> Int? {
        largeLetters[Self.key(id, in: name)] ?? shelf?.size(of: id, in: name)
    }

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
        // On the kept page too, for the rows that are on it, so the next
        // launch draws them as he saw them (D-016).
        shelf?.previews(out, in: name)
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

    /// A letter above `largeAbove` comes without its files, which
    /// are fetched when he taps one or a forward of it is sent
    /// (`loadLetterInPartOnce`); any other comes whole.
    func loadMessage(id: String, gmailMessageID: UInt64?, mailboxID: String) async throws -> Message {
        try await retryingIfDisconnected {
            try await self.loadMessageOnce(id: id, letter: gmailMessageID, mailboxID: mailboxID,
                                           whole: false)
        }
    }

    /// `whole` fetches the letter whole whatever its size: a draft of his,
    /// which he may change and save again, and whose text must then all be
    /// there, and whose files go again from the copy this fetches.
    private func loadMessageOnce(id: String, letter: UInt64?, mailboxID: String,
                                 whole: Bool) async throws -> Message {
        let client = try await connected()
        let name = try await resolve(mailboxID)
        let message = try Self.parseID(id)
        if !whole, let size = largeLetterSize(id, in: name), size > largeAbove {
            return try await loadLetterInPartOnce(id: id, letter: letter, mailboxID: mailboxID,
                                                  name: name, uid: message.uid,
                                                  validity: message.validity, client: client)
        }

        let raw: Data
        // Which letter it is, for what a Forward, a reply or a reopened
        // draft made from it names beside its folder and UID.
        var named = letter ?? seenLetter(message.uid, validity: message.validity, in: name)
        if let asked = try question(about: id, named: letter, uid: message.uid,
                                    validity: message.validity, in: name, sayingSo: "nothing-shown") {
            // A row this launch has not had from the server, a row kept on
            // the iPad above all: the FETCH that brings the letter asks for
            // its Gmail message id as well, and nothing of it is shown, or
            // kept for a Forward, unless the id is the row's (D-016). Every
            // other letter's FETCH is as it always was.
            let answer = try await client.fetchBodyNamingLetter(uid: message.uid, in: name,
                                                                validity: message.validity)
            try settle(answer.letter, askedOf: id, uid: message.uid, validity: message.validity,
                       as: asked, in: name, sayingSo: "nothing-shown")
            raw = answer.raw
            named = asked
        } else if named == nil, appendedHere.contains(Self.key(id, in: name)) {
            // A copy this launch put in Drafts, reopened from the row its
            // upload drew, which names no letter: Gmail's id for it asked in
            // the same FETCH, at no round trip more.
            let answer = try await client.fetchBodyAskingLetter(uid: message.uid, in: name,
                                                                validity: message.validity)
            if let found = answer.letter {
                saw([message.uid: found], validity: message.validity, in: name)
            }
            raw = answer.raw
            named = answer.letter
        } else {
            raw = try await client.fetchBody(uid: message.uid, section: nil,
                                             in: name, validity: message.validity)
        }
        lastBody = (id, named, raw)

        return Self.letter(id, in: mailboxID, headers: MIMEDecoder.parseHeaders(raw),
                           decoded: MIMEDecoder.decodeMessage(raw), named: named)
    }

    /// A letter above `largeAbove`, as the reading pane shows it: its
    /// header, the first `largeSection` bytes of its text and of its
    /// HTML, and its files listed from its structure and left on the server
    /// (`IMAPClient.fetchLetterInPart`). A file comes when he taps it, and a
    /// picture the HTML shows as the pane asks for it, each by its section
    /// alone while this is the letter last opened so, its structure kept
    /// (`lastStructure`, `fetchAttachmentData`); a forward's files and
    /// pictures come when it is sent, as any part not in `lastBody` does
    /// (`carriedPart`).
    ///
    /// Whole, a crafted letter of 35 MB of line breaks came to 1.66 GB in a
    /// release build on this host, and one of 25 MB of CRLF took 14 s on
    /// this actor; even an ordinary letter of photographs held the one
    /// connection for all its megabytes before a word of it showed.
    ///
    /// The same questions the whole letter's FETCH asks, in the same
    /// cases: Gmail's id for it beside the first FETCH, compared before
    /// anything more is asked for or anything shown, for a row this launch
    /// has not had from the server (D-016); asked, and nothing compared,
    /// for a copy this launch put in Drafts itself.
    private func loadLetterInPartOnce(id: String, letter: UInt64?, mailboxID: String,
                                      name: String, uid: UInt32, validity: UInt32,
                                      client: IMAPClient) async throws -> Message {
        var named = letter ?? seenLetter(uid, validity: validity, in: name)
        let asked = try question(about: id, named: letter, uid: uid, validity: validity,
                                 in: name, sayingSo: "nothing-shown")
        let question: IMAPClient.LetterQuestion = asked.map { .expecting($0) }
            ?? (named == nil && appendedHere.contains(Self.key(id, in: name)) ? .ifNamed : .none)
        let limit = largeSection
        let fetched = try await client.fetchLetterInPart(
            uid: uid, in: name, validity: validity, question: question, sectionBytes: limit
        ) { structure in
            let chosen = MIMEDecoder.bodyParts(of: structure)
            return [chosen.text, chosen.html].compactMap { $0?.section }
        }
        if let asked {
            try settle(fetched.letter, askedOf: id, uid: uid, validity: validity, as: asked,
                       in: name, sayingSo: "nothing-shown")
            named = asked
        } else if question == .ifNamed {
            if let found = fetched.letter { saw([uid: found], validity: validity, in: name) }
            named = fetched.letter
        }

        var decoded = DecodedBody(text: nil, html: nil)
        var shortened = false
        if let structure = fetched.structure {
            // The files, less the two parts shown, as `flatten` lists them
            // for a letter fetched whole.
            decoded = MIMEDecoder.flatten(structure) { _ in nil }
            let chosen = MIMEDecoder.bodyParts(of: structure)
            let text = Self.text(of: chosen.text, fetched: fetched.sections, limit: limit)
            let html = Self.text(of: chosen.html, fetched: fetched.sections, limit: limit)
            decoded.text = text.text
            decoded.html = html.text
            // By the part the pane shows, which is the HTML whenever there
            // is any (`PanePage`): a text alternative cut short under HTML
            // that came whole is not what he reads.
            shortened = html.text != nil ? html.cut : text.cut
            lastStructure = (id, structure)
        }
        return Self.letter(id, in: mailboxID, headers: MIMEDecoder.parseHeaders(fetched.header),
                           decoded: decoded, named: named, shortened: shortened)
    }

    /// The text of `part` from its section in `fetched`, and whether that
    /// is only its first `limit` bytes. A section cut short can end inside
    /// a character, which would make the whole of it fail as UTF-8 and read
    /// as Latin-1, so what is left of that character is dropped between the
    /// two decodings, as a preview drops it.
    private static func text(of part: MIMEPart?, fetched: [String: Data],
                             limit: Int) -> (text: String?, cut: Bool) {
        guard let part, let data = fetched[part.section] else { return (nil, false) }
        let charset = MIMEDecoder.parameter("charset", in: part.parameters)
        let cut = part.size.map { $0 > limit } ?? (data.count >= limit)
        guard cut else {
            return (MIMEDecoder.decodeText(data, encoding: part.encoding, charset: charset), false)
        }
        let bytes = PreviewText.trimmingSplitCharacter(
            MIMEDecoder.decodeTransfer(data, encoding: part.encoding))
        // "8bit" because the transfer encoding has already been undone above.
        return (MIMEDecoder.decodeText(bytes, encoding: "8bit", charset: charset), true)
    }

    /// The letter the pane shows, from its header and its decoded parts.
    private static func letter(_ id: String, in mailboxID: String,
                               headers: [(name: String, value: String)], decoded: DecodedBody,
                               named: UInt64?, shortened: Bool = false) -> Message {
        func header(_ n: String) -> String? {
            MIMEDecoder.headerValue(n, in: headers).map(MIMEDecoder.decodeWord)
        }
        // Split between addresses before the encoded words are decoded: a
        // name encoded as `=?UTF-8?Q?Example=2C_Jane?=` holds a comma once
        // decoded, and is one address.
        func addresses(_ n: String) -> [String] {
            MailFormat.addressList(MIMEDecoder.headerValue(n, in: headers) ?? "")
                .map { MIMEDecoder.decodeWord($0).trimmingCharacters(in: .whitespacesAndNewlines) }
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
            replyTo: addresses("Reply-To"),
            from: addresses("From"),
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
                .trimmingCharacters(in: .whitespaces),
            gmailMessageID: named,
            isShortened: shortened)
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

    // MARK: - Vouching for a row

    /// Before a write on a row: the Gmail message id it names, `letter`,
    /// held against what the server has named under its UID in this launch
    /// (`question`). The same letter, and the write goes as it always did;
    /// another, and neither the write nor a question goes (only what the
    /// write's caller sent ahead of it: a NOOP after a quiet spell, B-024,
    /// or the LOGIN a connection needs). Nothing named there yet, and one
    /// `UID FETCH` of the id there goes first (D-016), in the same hold as
    /// its SELECT and UIDVALIDITY check (B-039): the row's own, and the
    /// write goes; any other, or none, and it is not sent. Refused, the row
    /// leaves the kept page, and the caller is told
    /// (`MailShelf.NotTheKeptLetter`), so the list takes it off too
    /// (`PaneActions.notTheKeptLetter`).
    ///
    /// A row this launch has not had is one kept on the iPad from an
    /// earlier launch, the server's word of then, and a UID means nothing
    /// without the mailbox it came from: Gmail gives every Inbox UIDVALIDITY
    /// 1, and the app-password trap (B-033) can open another mailbox under
    /// his address, where the same UID is another letter. In practice it is
    /// a tap in the first second of a folder opened, before its first page
    /// has landed; one on a kept row still drawn after that page has thrown
    /// the copy away (`seen`); and, in the copy's own mailbox, one on a kept
    /// row the page lacks, pushed off it by new mail, made while the swap
    /// waits for his ticks or a lifted finger, or from a conversation opened
    /// from the kept page at launch. The Inbox's listing, which shows the
    /// copy to be this mailbox's, used to let that last go unasked; asking
    /// is the safer, and costs one round trip a row, once.
    ///
    /// A read, retried into a new connection as reads are; the write's own
    /// rules are untouched. A letter opened is vouched for by the FETCH that
    /// brings it (`loadMessageOnce`), by the same rules.
    private func vouch(for id: String, named letter: UInt64?, uid: UInt32, validity: UInt32,
                       in name: String) async throws {
        guard let asked = try question(about: id, named: letter, uid: uid, validity: validity,
                                       in: name, sayingSo: "nothing-sent") else { return }
        let found = try await retryingIfDisconnected {
            try await self.connected().gmailMessageID(uid: uid, in: name, validity: validity)
        }
        try settle(found, askedOf: id, uid: uid, validity: validity, as: asked, in: name,
                   sayingSo: "nothing-sent")
    }

    /// The Gmail message id the server is to be asked for under the row
    /// `id` before a write on it goes, or its letter is shown: nil when
    /// nothing is to be asked. Throws `MailShelf.NotTheKeptLetter`, with
    /// nothing sent, when this launch has had another letter from the
    /// server under its UID.
    ///
    /// `letter` is the Gmail message id of the row he acted on
    /// (`MessageSummary.gmailMessageID`), and decides it exactly, whatever
    /// has landed and whatever has not yet reached the screen: the server
    /// has named that letter under the UID in this launch, and nothing is
    /// asked; it has named another, and the row is not that letter; it has
    /// named none, and it is asked, for `letter`. A call naming no letter,
    /// for a row from a server without Gmail's extension, a draft drawn
    /// from what went up, or a draft removed that was found by its
    /// Message-ID or whose draft names no letter, goes by the kept copy's
    /// own rule (`MailShelf.unproven`), as every call did before they named
    /// their letters.
    private func question(about id: String, named letter: UInt64?, uid: UInt32, validity: UInt32,
                          in name: String, sayingSo note: String) throws -> UInt64? {
        guard let letter else { return shelf?.unproven(id, in: name) }
        guard let known = seen[name], known.validity == validity,
              let there = known.letters[uid] else { return letter }
        guard there == letter else { throw disowned(id, as: letter, in: name, sayingSo: note) }
        return nil
    }

    /// What the server has said the row `id` is, `found`, against the Gmail
    /// message id it was asked for as, `asked`. The same, and the row is
    /// vouched for and not asked about again. Another, or none, and the
    /// caller is told (`MailShelf.NotTheKeptLetter`) and goes no further.
    /// Either way what the server named is what this launch has seen under
    /// the UID (`seen`).
    ///
    /// Whatever has landed while the question was out. The launch's
    /// listing can come meanwhile and throw the copy away, the row under
    /// that id is then the server's own letter, and it stays
    /// (`MailShelf.refuse`); but the write, or the opening, was made on the
    /// kept row, and the server has just said the UID names another letter.
    private func settle(_ found: UInt64?, askedOf id: String, uid: UInt32, validity: UInt32,
                        as asked: UInt64, in name: String, sayingSo note: String) throws {
        if let found { saw([uid: found], validity: validity, in: name) }
        guard found == asked else { throw disowned(id, as: asked, in: name, sayingSo: note) }
        shelf?.vouched(id, in: name)
    }

    /// The row `id`, drawn as the letter `letter`, is not that letter: it
    /// leaves the kept page if it is still there as that letter, and the
    /// connection log says so in the folder's name and `note` alone.
    private func disowned(_ id: String, as letter: UInt64, in name: String,
                          sayingSo note: String) -> MailShelf.NotTheKeptLetter {
        shelf?.refuse(id, in: name, keptAs: letter)
        Diagnostics.log(.note, "KEPT-UNVOUCHED folder=\(name) \(note)")
        return MailShelf.NotTheKeptLetter()
    }

    /// The server has named these letters under these UIDs of `name`, in
    /// its `validity`. A new UIDVALIDITY forgets what was seen under the
    /// last: every UID then names another letter now, or none.
    private func saw(_ letters: [UInt32: UInt64], validity: UInt32, in name: String) {
        var folder = seen[name] ?? SeenLetters(validity: validity)
        if folder.validity != validity { folder = SeenLetters(validity: validity) }
        folder.letters.merge(letters) { _, now in now }
        seen[name] = folder
    }

    /// The letter the server has named under `uid` of `name`, in its
    /// `validity`, in this launch, nil if none.
    private func seenLetter(_ uid: UInt32, validity: UInt32, in name: String) -> UInt64? {
        guard let folder = seen[name], folder.validity == validity else { return nil }
        return folder.letters[uid]
    }

    /// A row's id in a folder, as one string, for `appendedHere`.
    private static func key(_ id: String, in name: String) -> String {
        name + "\n" + id
    }

    // MARK: - Flags

    /// Kept on the iPad once the server has it, on the letter wherever it
    /// is kept (`MailShelf.read`); not if the server refuses.
    func setRead(_ read: Bool, id: String, gmailMessageID: UInt64?,
                 mailboxID: String) async throws {
        try await readyForWrite()
        let client = try await connected()
        let name = try await resolve(mailboxID)
        let message = try Self.parseID(id)
        try await vouch(for: id, named: gmailMessageID, uid: message.uid,
                        validity: message.validity, in: name)
        try await sendingOnce {
            try await client.store(uid: message.uid, flag: "\\Seen", set: read,
                                   in: name, validity: message.validity)
        }
        shelf?.read(read, id: id, in: name)
    }

    func setFlagged(_ flagged: Bool, id: String, gmailMessageID: UInt64?,
                    mailboxID: String) async throws {
        try await readyForWrite()
        let client = try await connected()
        let name = try await resolve(mailboxID)
        let message = try Self.parseID(id)
        try await vouch(for: id, named: gmailMessageID, uid: message.uid,
                        validity: message.validity, in: name)
        try await sendingOnce {
            try await client.store(uid: message.uid, flag: "\\Flagged", set: flagged,
                                   in: name, validity: message.validity)
        }
        shelf?.flagged(flagged, id: id, in: name)
    }

    // MARK: - Moving and deleting

    func move(_ id: String, gmailMessageID: UInt64?, from sourceMailboxID: String,
              to destinationMailboxID: String) async throws {
        try await readyForWrite()
        let client = try await connected()
        let source = try await resolve(sourceMailboxID)
        let destination = try await resolve(destinationMailboxID)
        guard source != destination else { return }
        let message = try Self.parseID(id)
        try await vouch(for: id, named: gmailMessageID, uid: message.uid,
                        validity: message.validity, in: source)
        try await sendingOnce {
            try await client.move(uid: message.uid, from: source, validity: message.validity,
                                  to: destination)
        }
        // The message no longer exists at the old UID, so anything cached
        // against it is stale.
        if lastBody?.messageID == id { lastBody = nil }
        if lastStructure?.messageID == id { lastStructure = nil }
        // Off the kept pages as Gmail takes it off its folders (D-016): out
        // of every one but the Trash or Spam it went to, which are
        // exclusive; out of none when it leaves All Mail for a label, since
        // All Mail is every letter not binned; out of its own otherwise.
        if destination == roleNames[.trash] || destination == roleNames[.junk] {
            shelf?.gone(id, from: source, andEveryFolderBut: destination)
        } else if source != folderForAttribute["\\all"] {
            shelf?.gone(id, from: source)
        }
    }

    /// Delete means "move to Trash" — except in Trash, where it means gone.
    ///
    /// The mock got this wrong in a way worth recording: it moved to the
    /// literal string "trash" unconditionally, so deleting something already
    /// in Trash moved it to Trash again and it reappeared at the top of the
    /// list. Here the destination is resolved from the \Trash special-use
    /// attribute, and deleting inside Trash marks \Deleted instead.
    func delete(_ id: String, gmailMessageID: UInt64?, from mailboxID: String) async throws {
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
            try await vouch(for: id, named: gmailMessageID, uid: message.uid,
                            validity: message.validity, in: source)
            try await sendingOnce {
                try await client.store(uid: message.uid, flag: "\\Deleted", set: true,
                                       in: source, validity: message.validity)
            }
            shelf?.gone(id, from: source)
            return
        }
        try await move(id, gmailMessageID: gmailMessageID, from: mailboxID, to: trash)
    }

    // MARK: - Sending

    func send(_ draft: Draft, progress: UploadProgress?) async throws {
        try await send(draft, messageID: nil, beforeData: nil, progress: progress)
    }

    func send(_ draft: Draft, as letter: OutgoingLetter, progress: UploadProgress?) async throws {
        try await send(draft, messageID: letter.messageID, beforeData: letter.beforeData,
                       progress: progress)
    }

    private func send(_ draft: Draft, messageID: String?,
                      beforeData: (@Sendable () async throws -> Void)?,
                      progress: UploadProgress?) async throws {
        guard !retired else { throw MailError.cannotConnect }
        // The threading headers, which used to be dropped on the floor.
        // `Draft.inReplyTo` was set faithfully by the compose screen and read
        // by nobody, so every reply this app sent went out with no
        // In-Reply-To and no References — verified on the wire. It appeared
        // to thread in Gmail only because Gmail falls back to matching
        // subject lines; Apple Mail, Outlook and Thunderbird thread on
        // References and would have started a new conversation every time.
        //
        // Built and sent by `Submission`, which the share extension sends
        // through too. The HTML twin and which of the original's parts go
        // are the quote's (`AppleMailHTML.letter`, B-050). A forward's
        // quoted pictures are fetched only once the letter is known to be
        // going somewhere, as its files are.
        let images = signatureImages()
        let letter = AppleMailHTML.letter(for: draft, account: account,
                                          reserving: SignatureImages.contentIDs(of: images))
        guard !Submission.recipients(of: draft).isEmpty else { throw MailError.notSent }
        let pictures = try await loadPictures(letter.pictures)
        try await Submission.send(draft, from: account, password: password, through: smtp,
                                  threadHeaders: Self.threadHeaders(for: draft),
                                  attachments: { try await self.loadAttachments(letter.files) },
                                  htmlBody: letter.html,
                                  inlineImages: SignatureImages.parts(of: images) + pictures,
                                  messageID: messageID,
                                  beforeData: beforeData,
                                  progress: progress)
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

    func sentMail(holds messageIDs: [String]) async throws -> Set<String> {
        guard !messageIDs.isEmpty else { return [] }
        // A read, retried once on a socket that died under it, as every
        // read is (B-023), a pass's included: the pass began on a connection
        // that was up, and the retry's LOGIN is the one that connection's
        // was. Never for a refusal: a search refused, on a connection still
        // up, is thrown as it is, and the letter waits (`LocalDrafts.send`).
        //
        // Each search asks for the mailbox's news first (`searchNow`): Sent
        // Mail may be open on the connection from before, and a SEARCH
        // there answers from what the session was last told.
        return try await retryingIfDisconnected {
            let client = try await self.connected()
            let sent = try await self.sentMailFolder()
            var found: Set<String> = []
            for id in messageIDs {
                let criteria = "HEADER Message-ID \"\(SearchCriteria.escape(id))\""
                if !(try await client.searchNow(criteria, in: sent)).isEmpty {
                    found.insert(id)
                }
            }
            return found
        }
    }

    /// Where Gmail files what it takes over SMTP: Sent Mail, by the role
    /// LIST gives it, or All Mail, which holds every letter Sent Mail does,
    /// when LIST names no Sent Mail, as when "Show in IMAP" is off for it in
    /// Gmail's settings. Never a name guessed: a SELECT of one is refused,
    /// and every look would fail the same way for good, with nothing on the
    /// letter's row to say why. Throws `Outbox.NoSentMail` when LIST names
    /// neither.
    private func sentMailFolder() async throws -> String {
        _ = try await knownListing()
        if let sent = roleNames[.sent] ?? folderForAttribute["\\all"] { return sent }
        throw Outbox.NoSentMail()
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
    private func loadAttachments(_ attachments: [DraftAttachment]) async throws
        -> [(filename: String, mimeType: String, data: Data)] {
        var loaded: [(filename: String, mimeType: String, data: Data)] = []
        loaded.reserveCapacity(attachments.count)
        for attachment in attachments {
            let data: Data
            switch attachment.source {
            case let .messagePart(messageID, mailboxID, section, letter):
                data = try await fetchCarried(section, of: messageID, mailboxID: mailboxID,
                                              letter: letter)
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

    /// The bytes of the quoted original's pictures, as inline parts under
    /// the names the letter's markup shows them by. A forward's only: a
    /// reply carries none (`AppleMailHTML.letter`), so it never waits on
    /// the original or fails for want of it.
    ///
    /// Throws as `loadAttachments` does, for the same reason: a letter sent
    /// without a picture its markup shows arrives with a broken box where
    /// the picture was. Each is one of the forward's rows, so the failure
    /// names something he can take off. Usually free, as there: the
    /// original is still in `lastBody`.
    private func loadPictures(_ pictures: [(contentID: String, picture: QuotedOriginal.Picture)])
        async throws -> [(contentID: String, filename: String, mimeType: String, data: Data)] {
        var loaded: [(contentID: String, filename: String, mimeType: String, data: Data)] = []
        loaded.reserveCapacity(pictures.count)
        for (contentID, picture) in pictures {
            let data = try await fetchCarried(picture.section, of: picture.messageID,
                                              mailboxID: picture.mailboxID, letter: picture.letter)
            loaded.append((contentID: contentID, filename: picture.filename,
                           mimeType: picture.mimeType, data: data))
        }
        return loaded
    }

    /// A part of a letter on the server that a letter being built carries,
    /// a forward's file or picture or a reopened draft's.
    ///
    /// Refused with the connection still up, the part is the letter's own
    /// failure, `MailError.attachmentFailed`, and not the connection's: the
    /// original's folder renumbered since, so its UIDVALIDITY no longer
    /// matches, or deleted or renamed in another client, so its SELECT is
    /// refused. The client says `cannotConnect` for both, which for a
    /// letter in the Outbox means "wait for the connection": a forward like
    /// that waited for good, and, as the oldest, ended every pass before the
    /// letters after it (B-052). A connection that is down stays
    /// `cannotConnect`.
    ///
    /// `letter` is Gmail's id for the original (X-GM-MSGID), which a part
    /// carries when the server named one (`DraftAttachment.Source`). A
    /// letter kept on the iPad from an earlier launch names its parts by
    /// folder and UID, and Gmail gives every Inbox UIDVALIDITY 1: after a
    /// password saved that opens another mailbox under the same address
    /// (B-033), or a folder renumbered under the same UIDVALIDITY, that UID
    /// is another letter, and its file went out under the forward's file's
    /// name. So a part that names its letter is fetched only from that
    /// letter (`carriedPart`). Not there, whether another letter is under
    /// the UID, none is, or its folder is gone or renumbered, and the
    /// letter is looked for by its id in All Mail, and the same part
    /// fetched from it there (`carriedPartElsewhere`). Not found there
    /// either, and nothing of the letter goes:
    /// `MailError.attachmentsMissing`, the letter's own failure, so it
    /// stays in the Outbox or in Drafts saying so, and the letters after it
    /// go.
    ///
    /// A part that names no letter, from a server without Gmail's
    /// extension or kept by a build before the id was kept, is fetched by
    /// folder and UID as it always was.
    private func fetchCarried(_ section: String, of messageID: String,
                              mailboxID: String, letter: UInt64?) async throws -> Data {
        guard let letter else {
            do {
                return try await fetchAttachmentData(section, of: messageID, mailboxID: mailboxID)
            } catch MailError.cannotConnect {
                guard await imap.isConnected else { throw MailError.cannotConnect }
                throw MailError.attachmentFailed
            }
        }
        let name = try await resolve(mailboxID)
        let reason: String
        do {
            return try await carriedPart(section, of: messageID, in: name, letter: letter)
        } catch let other as IMAPClient.NotTheLetter {
            reason = other.named == nil ? "gone" : "another-letter"
            if let named = other.named, let at = try? Self.parseID(messageID) {
                saw([at.uid: named], validity: at.validity, in: name)
            }
        } catch MailError.cannotConnect {
            // Refused with the connection still up: its folder renumbered,
            // deleted or renamed since.
            guard await imap.isConnected else { throw MailError.cannotConnect }
            reason = "folder"
        }
        Diagnostics.log(.note, "CARRIED-PART folder=\(name) reason=\(reason)")
        if let found = try await carriedPartElsewhere(section, letter: letter) {
            Diagnostics.log(.note, "CARRIED-PART found folder=\(found.folder)")
            return found.data
        }
        Diagnostics.log(.note, "CARRIED-PART not-found nothing-sent")
        throw MailError.attachmentsMissing
    }

    /// The part `section` of `letter`, from the letter at `id` in `name`
    /// only if it is that letter. From the letter the reading pane last
    /// fetched when that is it, as a forward made and sent in one launch
    /// always was. Refused at once, with nothing sent, when this launch
    /// has had another letter from the server under the UID (`seen`).
    /// Otherwise fetched as ever, the FETCH that describes the letter
    /// comparing the id it names before the part's bytes are asked for
    /// (`IMAPClient.fetchPart`), at no round trip more.
    private func carriedPart(_ section: String, of id: String, in name: String,
                             letter: UInt64) async throws -> Data {
        if let cached = lastBody, cached.messageID == id, cached.letter == letter,
           let data = Self.part(section, of: cached.raw) {
            return data
        }
        let at = try Self.parseID(id)
        if let there = seenLetter(at.uid, validity: at.validity, in: name), there != letter {
            throw IMAPClient.NotTheLetter(named: there)
        }
        let data = try await retryingIfDisconnected {
            try await self.fetchAttachmentDataOnce(section, of: id, mailboxID: name, letter: letter)
        }
        saw([at.uid: letter], validity: at.validity, in: name)
        return data
    }

    /// The part `section` of the letter Gmail knows as `letter`, from
    /// wherever it is in All Mail: `UID SEARCH X-GM-MSGID`, then the part
    /// fetched as `carriedPart` fetches one, its FETCH naming the letter
    /// too. Nil when All Mail is not listed, the letter is not in it, or
    /// the server cannot be asked; a connection that goes is thrown, and
    /// the letter waits for it.
    ///
    /// All Mail, because it holds every letter that is not binned, which
    /// is where an original forwarded from the Inbox is once it has been
    /// archived, and where one is under a new UID in a folder renumbered.
    private func carriedPartElsewhere(_ section: String, letter: UInt64)
        async throws -> (data: Data, folder: String)? {
        _ = try await knownListing()
        guard let allMail = folderForAttribute["\\all"] else { return nil }
        do {
            let found = try await retryingIfDisconnected {
                try await self.connected().findLetter(letter, in: allMail)
            }
            guard let found, let uid = found.uids.last else { return nil }
            let data = try await retryingIfDisconnected {
                try await self.fetchAttachmentDataOnce(
                    section, of: Self.makeID(validity: found.validity, uid: uid),
                    mailboxID: allMail, letter: letter)
            }
            saw([uid: letter], validity: found.validity, in: allMail)
            return (data, allMail)
        } catch is IMAPClient.NotTheLetter {
            return nil
        } catch MailError.cannotConnect {
            guard await imap.isConnected else { throw MailError.cannotConnect }
            return nil
        }
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
        try await saveDraft(draft, upload: nil).id
    }

    @discardableResult
    func saveDraft(_ draft: Draft, as upload: DraftUpload) async throws -> DraftSaved {
        try await saveDraft(draft, upload: upload)
    }

    private func saveDraft(_ draft: Draft, upload: DraftUpload?) async throws -> DraftSaved {
        try await readyForWrite()
        let client = try await connected()
        let drafts = try await draftsFolder()

        // A letter kept on the iPad whose upload began before: what that
        // left in Drafts. Only then, so a first save costs what it always
        // did.
        let earlier = try await copies(of: upload?.earlier ?? [], in: drafts, client: client)
        let already = upload.flatMap { earlier[$0.version]?.last }

        let saved: String?
        if let already {
            // The server has this very version already, from an upload cut
            // off after it had it. Sending it again would be a second copy.
            // Found a moment ago by the Message-ID only this version goes up
            // under, it is this launch's own as surely as an APPENDUID's, and
            // is reopened naming its letter as one of those is.
            saved = already
            appendedHere.insert(Self.key(already, in: drafts))
        } else {
            saved = try await append(draft, as: upload.map { draftMessageID($0.version) },
                                     noting: upload?.appending, to: drafts, client: client)
        }

        // The copy he reopened, and whatever earlier uploads of this letter
        // left but this version's newest copy, and only once the
        // replacement is safely on the server. The other order risks
        // deleting the only copy of a letter and then failing to append,
        // which loses work he cannot get back. The ones that went are
        // handed back, for a list still showing them.
        //
        // The copy he reopened goes only if the server shows its UID to
        // hold the letter the draft names (`Draft.savedLetter`). Kept on
        // the iPad from an earlier launch, the draft's folder and UID can
        // name another draft: in another mailbox under the same address, or
        // a Drafts renumbered under the same UIDVALIDITY. That one stays,
        // and the new version is in Drafts all the same. The earlier
        // uploads' copies were found by their Message-IDs a moment ago.
        var superseded: [(id: String, letter: UInt64?)] =
            draft.savedID.map { [($0, draft.savedLetter)] } ?? []
        superseded += (upload?.earlier ?? []).flatMap { earlier[$0] ?? [] }.map { ($0, nil) }
        var removed: [String] = []
        for old in superseded where old.id != saved && !removed.contains(old.id) {
            do {
                try await deleteDraft(old.id, gmailMessageID: old.letter)
                removed.append(old.id)
            } catch is MailShelf.NotTheKeptLetter {
                Diagnostics.log(.note, "DRAFT-SUPERSEDED folder=\(drafts) not-that-letter left")
            } catch {
                // Left, as a copy the server will not remove always was.
            }
        }
        return DraftSaved(id: saved, replaced: removed)
    }

    @discardableResult
    func deleteDrafts(uploadedAs versions: [String]) async throws -> [String] {
        guard !versions.isEmpty else { return [] }
        try await readyForWrite()
        let client = try await connected()
        let drafts = try await draftsFolder()
        let found = try await copies(of: versions, in: drafts, client: client)
        // A copy the server will not remove, on a connection still up, is
        // left, as a superseded copy is at a save; a lost connection fails
        // the lot, so the letter's record stays to try again.
        var removed: [String] = []
        for id in versions.flatMap({ found[$0] ?? [] }) where !removed.contains(id) {
            do {
                try await deleteDraft(id, gmailMessageID: nil)
                removed.append(id)
            } catch {
                guard await imap.isConnected else { throw error }
            }
        }
        return removed
    }

    /// The copies in Drafts of each of `versions`, by version, as ids,
    /// oldest first.
    ///
    /// A search the server refuses, on a connection still up, is taken as
    /// finding nothing: then the letter goes up again, and at worst Drafts
    /// has it twice, which is better than a letter that can never go
    /// because the server will not answer the question. A lost connection
    /// fails the call, and what is kept on the iPad stays for the next time.
    private func copies(of versions: [String], in drafts: String,
                        client: IMAPClient) async throws -> [String: [String]] {
        var found: [String: [String]] = [:]
        for version in versions where found[version] == nil {
            let criteria = "HEADER Message-ID \"\(SearchCriteria.escape(draftMessageID(version)))\""
            do {
                let hits = try await client.search(criteria, in: drafts)
                found[version] = hits.uids.map { Self.makeID(validity: hits.validity, uid: $0) }
            } catch {
                guard await imap.isConnected, !(error is CancellationError) else { throw error }
                found[version] = []
            }
        }
        return found
    }

    /// The Message-ID a kept letter's version goes up under, on the sender's
    /// domain as every other this app makes (`RFC5322Builder`).
    private func draftMessageID(_ version: String) -> String {
        let domain = account.address.split(separator: "@").last.map(String.init) ?? ""
        return "<\(version)@\(domain.isEmpty ? "localhost" : domain)>"
    }

    /// Builds the draft and APPENDs it to Drafts. Returns its id there, or
    /// nil when the server took it without saying where (no UIDPLUS).
    /// `noting` goes last before the APPEND, once the files are in.
    private func append(_ draft: Draft, as messageID: String?,
                        noting: (@Sendable () async throws -> Void)?, to drafts: String,
                        client: IMAPClient) async throws -> String? {
        // Attachments are resolved for a saved draft too, so reopening one
        // from another client shows the files rather than a bare note
        // referring to them.
        //
        // Resolved BEFORE the old copy is removed, because a draft reopened
        // from the server carries attachments that live inside that very
        // copy: delete it first and the files it is carrying go with it.
        let images = signatureImages()
        // Marked where the quote begins, so reopening can take the quote up
        // again (`QuotedOriginal.recovered`).
        let letter = AppleMailHTML.letter(for: draft, account: account,
                                          reserving: SignatureImages.contentIDs(of: images),
                                          forDraft: true)
        let loaded = try await loadAttachments(letter.files)
        // The quote's pictures too, and for the same reason: a reopened
        // draft's live in the copy about to be replaced.
        let pictures = try await loadPictures(letter.pictures)
        let raw = RFC5322Builder.build(draft: draft, from: account,
                                       messageID: messageID,
                                       inReplyToHeaders: Self.threadHeaders(for: draft),
                                       attachments: loaded,
                                       includeBcc: true,
                                       // A draft is stored as the message it
                                       // will become, markup and all, so what
                                       // he sees on reopening is what will go.
                                       htmlBody: letter.html,
                                       // The signature's pictures go with the
                                       // draft too: a draft is reopened by
                                       // parsing it back, and the parts are
                                       // what make its markup's cid: resolve.
                                       inlineImages: SignatureImages.parts(of: images) + pictures)
        try await noting?()
        // One send, on a new connection if its turn came after a check had
        // found the socket dead (`sendingOnce`, B-049).
        let appended = try await sendingOnce {
            try await client.append(raw, to: drafts, flags: ["\\Draft", "\\Seen"])
        }
        guard let appended else { return nil }
        let id = Self.makeID(validity: appended.validity, uid: appended.uid)
        appendedHere.insert(Self.key(id, in: drafts))
        return id
    }

    func deleteDraft(_ id: String, gmailMessageID: UInt64?) async throws {
        try await readyForWrite()
        let client = try await connected()
        let name = try await resolve(try await draftsFolder())
        let draft = try Self.parseID(id)
        // The copy a draft was reopened from names its letter where the
        // draft knows it (`Draft.savedLetter`), and goes by the rules every
        // write naming its letter goes by (`question`): the same letter
        // named under the UID in this launch, and the EXPUNGE goes as it
        // always did; another, and nothing is sent; none yet, and the
        // server is asked first. A letter kept in Local Drafts from an
        // earlier launch names its copy by folder and UID, which after a
        // password saved that opens another mailbox under the same address
        // (B-033), or a Drafts renumbered under the same UIDVALIDITY, can
        // be another draft (B-051). A copy named by no letter, one found by
        // its Message-ID or one from a server without Gmail's extension,
        // goes by the kept copy's own rule.
        try await vouch(for: id, named: gmailMessageID, uid: draft.uid, validity: draft.validity,
                        in: name)
        // Expunged, not moved to Trash. Now that an "All Mailboxes" search
        // reaches the Trash, a superseded draft binned rather than removed
        // would come back as a hit for every half-finished sentence he ever
        // saved.
        try await sendingOnce {
            try await client.expunge(uid: draft.uid, in: name, validity: draft.validity)
        }
        // The snapshot still lists the UID we just removed.
        uidListing[name] = nil
        shelf?.gone(id, from: name)
    }

    /// Without the signature's pictures among its files: `saveDraft` stored
    /// them only so the markup resolves, and saving or sending adds them
    /// again. See `Draft.reopening` (B-046).
    ///
    /// Fetched whole, however large: it is his own letter, only a draft of
    /// his is opened here, and he may change it and save or send it again,
    /// which a text cut short would send cut short.
    func loadDraft(id: String, gmailMessageID: UInt64?, mailboxID: String) async throws -> Draft {
        let message = try await retryingIfDisconnected {
            try await self.loadMessageOnce(id: id, letter: gmailMessageID, mailboxID: mailboxID,
                                           whole: true)
        }
        return Draft.reopening(message, signatureImages: signatureImages())
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
    ///
    /// A part of the letter last opened without its files is its section's
    /// FETCH alone, the structure already known (`lastStructure`). The pane
    /// asks for each picture such a letter shows this way, one after
    /// another on the one connection. Described again first, as a part of a
    /// letter no longer to hand is, each picture was two FETCHes, one of
    /// them the whole structure, which grows with the pictures: a letter of
    /// 300 took 603 FETCHes to open and show, and one of 500 would read a
    /// structure of 54 KB 500 times.
    func fetchAttachmentData(_ attachmentID: String, of messageID: String, mailboxID: String) async throws -> Data {
        if let cached = lastBody, cached.messageID == messageID,
           let data = Self.part(attachmentID, of: cached.raw) {
            return data
        }
        // A read, so a socket that died while he wrote costs a reconnect
        // rather than the Send (B-023): a forward fetches its files here
        // when the letter on screen is no longer the one it forwards.
        if let known = lastStructure, known.messageID == messageID,
           let part = MIMEDecoder.part(at: attachmentID, in: known.structure) {
            return try await retryingIfDisconnected {
                try await self.fetchKnownPartOnce(attachmentID, part, of: messageID,
                                                  mailboxID: mailboxID)
            }
        }
        return try await retryingIfDisconnected {
            try await self.fetchAttachmentDataOnce(attachmentID, of: messageID,
                                                   mailboxID: mailboxID)
        }
    }

    /// The part at `section` of the letter `messageID`, described by `part`
    /// from a structure already fetched: `UID FETCH <uid> (UID
    /// BODY.PEEK[<section>])`, in one hold with its SELECT and UIDVALIDITY
    /// check (B-039), and decoded as `part` says it is wrapped.
    private func fetchKnownPartOnce(_ section: String, _ part: MIMEPart, of messageID: String,
                                    mailboxID: String) async throws -> Data {
        let client = try await connected()
        let name = try await resolve(mailboxID)
        let message = try Self.parseID(messageID)
        let raw = try await client.fetchBody(uid: message.uid, section: section, in: name,
                                             validity: message.validity)
        guard !raw.isEmpty else { throw MailError.attachmentFailed }
        let decoded = MIMEDecoder.decodeTransfer(raw, encoding: part.encoding)
        guard !decoded.isEmpty else { throw MailError.attachmentFailed }
        return decoded
    }

    /// The part `section` of a whole letter already downloaded, decoded,
    /// or nil when it has no such part.
    private static func part(_ section: String, of raw: Data) -> Data? {
        let parsed = MIMEDecoder.parse(raw)
        guard let bytes = parsed.bodies[section],
              let part = MIMEDecoder.part(at: section, in: parsed.structure) else { return nil }
        return MIMEDecoder.decodeTransfer(bytes, encoding: part.encoding)
    }

    /// `letter`, when given, is Gmail's id for the letter the part is
    /// wanted from, compared before the part's bytes are asked for
    /// (`IMAPClient.fetchPart`).
    private func fetchAttachmentDataOnce(_ attachmentID: String, of messageID: String,
                                         mailboxID: String,
                                         letter: UInt64? = nil) async throws -> Data {
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
            naming: letter, describedBy: { MIMEDecoder.part(at: attachmentID, in: $0) }) else {
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
