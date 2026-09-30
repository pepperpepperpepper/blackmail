import Foundation

/// The seam between the interface and whatever is actually fetching mail.
///
/// Corrected from `spec/docs/ARCHITECTURE.md` in three ways, all of which
/// the spec's own text calls for elsewhere:
///
/// 1. `page: Int` is gone. Page indices shift the moment new mail arrives
///    mid-scroll, and the architecture doc contradicts itself four lines later
///    by saying to "reconcile by stable IMAP UID". Paging is by UID.
/// 2. `search`, `setFlagged` and `fetchAttachmentData` are added. All three are
///    required v1 features in `PRODUCT_SPEC.md` and none had a method.
/// 3. `Attachment` had no way to get its bytes, so "view/download/share" was
///    unimplementable as specified.
protocol MailRepository {
    /// Every folder with its unread count: LIST, and a STATUS per folder.
    /// The sidebar's sweep.
    func listMailboxes() async throws -> [Mailbox]

    /// The folders without their counts, from what the last LIST said, or
    /// from a LIST alone when nothing has been listed yet. Every count reads
    /// 0. For what shows names only, the Move sheet, and the folder pane
    /// while the first page of the Inbox is still on its way.
    func folders() async throws -> [Mailbox]

    /// Newest first. `beforeUID` nil means "from the top".
    ///
    /// Summaries come back with `preview` EMPTY. See `previews(for:in:)`.
    func listMessages(in mailboxID: String, beforeUID: String?, limit: Int) async throws -> [MessageSummary]

    /// The other direction: up to `limit` messages immediately NEWER than
    /// `afterUID`, still newest first.
    ///
    /// Exists only because of the date jump. A list anchored at the newest
    /// message can never need this — there is nothing above it — but one
    /// opened at the 20th of June has mail in both directions, and "work
    /// forwards from there" is the half that was missing.
    ///
    /// Adjacent to the cursor, not the top of the mailbox: this is the page
    /// that belongs immediately above what is on screen.
    func listMessages(in mailboxID: String, afterUID: String, limit: Int) async throws -> [MessageSummary]

    /// Opens the folder at a day instead of at the newest message.
    ///
    /// Lands on the FIRST letter sent on or after `date` and returns the
    /// mail either side of it, so he can read forwards into the days after
    /// or backwards into the days before without starting from today and
    /// scrolling. A `nil` result means the folder holds nothing that recent
    /// and the caller should stay where the newest mail is.
    func messages(around date: Date, in mailboxID: String, limit: Int) async throws -> MessageWindow?

    /// The two grey lines under the subject, for messages already listed.
    ///
    /// A fourth correction to the architecture doc, and the reason is cost
    /// rather than tidiness. Everything else a row shows comes from the
    /// ENVELOPE, which the server sends for a whole page in one reply;
    /// preview text is BODY, and a page of HTML mail is hundreds of kilobytes
    /// of it. Folding that into `listMessages` would turn a list that appears
    /// in about a second into one that appears in four, so the rows go up with
    /// the preview blank and this fills them in behind — which is what Mail
    /// itself does.
    ///
    /// Keyed by message id; an id missing from the result simply has no
    /// preview, which is not an error.
    func previews(for ids: [String], in mailboxID: String) async throws -> [String: String]

    /// The letter a row stands for. `gmailMessageID` is the row's own
    /// (`MessageSummary.gmailMessageID`), nil when it has none: nothing of
    /// the letter is shown unless the server has it under the row's UID
    /// (D-016), and `MailShelf.NotTheKeptLetter` is thrown otherwise.
    func loadMessage(id: String, gmailMessageID: UInt64?, mailboxID: String) async throws -> Message

    /// Every write on a row names the row's Gmail message id as
    /// `loadMessage` does, and goes onto that letter or not at all.
    func setRead(_ read: Bool, id: String, gmailMessageID: UInt64?, mailboxID: String) async throws
    func setFlagged(_ flagged: Bool, id: String, gmailMessageID: UInt64?, mailboxID: String) async throws

    func move(_ id: String, gmailMessageID: UInt64?, from sourceMailboxID: String,
              to destinationMailboxID: String) async throws
    func delete(_ id: String, gmailMessageID: UInt64?, from mailboxID: String) async throws

    /// Returns once the server has taken the letter, its 250 after DATA,
    /// and not after anything that follows it; see `SMTPClient.send`.
    /// `progress` hears how much of the built letter has been handed to the
    /// network, while it goes.
    func send(_ draft: Draft, progress: UploadProgress?) async throws

    /// `send`, for a letter from the Outbox (`LocalDrafts.send`): it goes
    /// under `letter.messageID`, the same at every attempt, and
    /// `letter.beforeData` is called once the server has taken the envelope,
    /// before DATA (`SMTPClient.send`).
    func send(_ draft: Draft, as letter: OutgoingLetter, progress: UploadProgress?) async throws

    /// Which of `messageIDs` Sent Mail holds a letter under, asked with
    /// `UID SEARCH HEADER Message-ID`: whether an attempt at a letter whose
    /// DATA went, and whose 250 never came back, reached Gmail. Gmail files
    /// what it takes over SMTP in Sent Mail itself.
    ///
    /// Throws when it cannot be answered: no connection, a refused password,
    /// a search the server refuses, and `Outbox.NoSentMail` when the server
    /// lists no folder to ask. Never takes a refusal for "not there", as
    /// `deleteDrafts(uploadedAs:)` does: a second copy in Drafts can be
    /// removed, a letter sent twice cannot be taken back.
    func sentMail(holds messageIDs: [String]) async throws -> Set<String>

    /// Saves to the Drafts folder, REPLACING the copy named by
    /// `draft.savedID` if there is one, and returns the id of the copy now
    /// on the server so the next save replaces this one in turn.
    ///
    /// Returns nil only when the server accepted the new copy but would not
    /// say where it put it (no UIDPLUS). The save still happened; the
    /// caller simply cannot chain another replacement onto it.
    @discardableResult
    func saveDraft(_ draft: Draft) async throws -> String?

    /// `saveDraft`, for a letter kept on the iPad (`LocalDrafts`): it goes up
    /// under a Message-ID made from `upload.version`, and does not go up at
    /// all if Drafts already holds a copy under that Message-ID, left by an
    /// upload cut off after the server had it; that copy is taken as this
    /// save's. Copies of the `upload.earlier` versions are removed along
    /// with the copy named by `draft.savedID`, once this one is there.
    /// `upload.appending` is called once nothing is left to do but the
    /// APPEND, and the APPEND waits for it.
    @discardableResult
    func saveDraft(_ draft: Draft, as upload: DraftUpload) async throws -> DraftSaved

    /// Removes a saved draft outright rather than binning it.
    ///
    /// Never a row he tapped: the copy a draft was reopened from, or a copy
    /// put in Drafts or found there. `gmailMessageID` is Gmail's id for the
    /// letter the copy is (`Draft.savedLetter`), nil where none is known,
    /// and it goes by the rules the writes above go by: removed only if the
    /// server shows that UID to hold that letter, asked first if it has
    /// named nothing there in this launch, and nothing sent if it has named
    /// another, `MailShelf.NotTheKeptLetter` thrown. A letter kept in Local
    /// Drafts from an earlier launch names its copy by folder and UID, and
    /// after a password saved in Settings that opens another mailbox under
    /// the same address (B-033), or a Drafts renumbered under the same
    /// UIDVALIDITY, that UID can be another draft (B-051). Named by no
    /// letter, a copy found by its Message-ID or one from a server without
    /// Gmail's extension goes by the kept copy's own rule, as every copy
    /// did before its letter was named.
    func deleteDraft(_ id: String, gmailMessageID: UInt64?) async throws

    /// Removes the copies in Drafts of a letter kept on the iPad, found by
    /// the Message-IDs its `versions` went up under, and returns their ids.
    /// For a letter sent or deleted after an upload of it was cut off: the
    /// copy that upload left is known only by its Message-ID.
    @discardableResult
    func deleteDrafts(uploadedAs versions: [String]) async throws -> [String]

    /// Reopens a saved draft for editing, the row's Gmail message id named
    /// as `loadMessage` names it.
    func loadDraft(id: String, gmailMessageID: UInt64?, mailboxID: String) async throws -> Draft

    /// Newest first, and PAGED exactly like `listMessages` — `beforeUID` nil
    /// is the first page, a short page is the last one.
    ///
    /// The cursor is the whole point of this signature. Search used to
    /// return the newest hundred hits and stop, with no way to ask for the
    /// hundred-and-first and nothing on screen to say that a hundred was
    /// where it stopped. For a man who searches every day through years
    /// of mail, a silent ceiling is worse than a slow scroll: the
    /// letter he wants is simply not there and nothing says why.
    func search(in mailboxID: String, query: String, scope: MailSearchScope,
                beforeUID: String?, limit: Int) async throws -> [MessageSummary]

    func fetchAttachmentData(_ attachmentID: String, of messageID: String, mailboxID: String) async throws -> Data

    /// Called as the app comes back to the foreground. Finds out whether a
    /// connection quiet for long enough to have died still works, and
    /// replaces it if not, before he taps anything. Never fails: nobody is
    /// waiting for it.
    func warmUp() async

    /// Whether there is a connection up now. What work nobody asked for
    /// looks at before it sends anything, so that it never makes a
    /// connection of its own: where there is none, a launch could not
    /// connect or a password was refused, and trying again is his to do.
    var isConnected: Bool { get async }

    /// What has come into a folder, and gone from it, since its list was
    /// fetched, for `MailWatch`. `known` is every letter the list holds from
    /// the folder, the ones it has not drawn yet included. The new letters
    /// come as rows, newest first, with `preview` empty as `listMessages`
    /// gives them; the ones gone as ids. `searchingAnyway` when what the
    /// last call found never reached the list, which the server, having
    /// told the session of it, will not tell again.
    func news(in mailboxID: String, known: [String],
              searchingAnyway: Bool) async throws -> FolderNews

    /// The Inbox's unread count as the server has it now, nil if it will not
    /// say. For `MailWatch` while another folder is in front of him.
    func inboxUnread() async throws -> Int?

    /// The copy of his mail kept on the iPad (D-016), which the screens draw
    /// before anything has been sent, and which this repository keeps as it
    /// lists and writes. Nil where nothing is kept.
    var shelf: MailShelf? { get }
}

/// Where a search looks — the two scopes Mail itself offers.
///
/// `PRODUCT_SPEC.md` line 67 requires only "search current mailbox", and
/// that stays the letter of it: `.currentMailbox` is exactly that method.
/// `.allMailboxes` is added because the requirement is that search work as
/// Mail's does, where searching from the Inbox finds a letter he has since
/// filed. It is NOT the "unified inbox" the spec excludes at line 73 —
/// that is several ACCOUNTS merged into one list, and there is one account.
enum MailSearchScope: String, CaseIterable {
    case currentMailbox
    case allMailboxes

    /// What the control says. Mail's own words.
    var title: String {
        switch self {
        case .currentMailbox: return "Current Mailbox"
        case .allMailboxes:   return "All Mailboxes"
        }
    }
}

/// A letter kept on the iPad on its way to Drafts: the version going, and
/// the versions of it whose upload began before and which may be there
/// already (`LocalDraft.tried`).
///
/// Why a Message-ID per version and a look before sending again, rather
/// than simply trying again: an APPEND whose answer is lost, to a dropped
/// line or iOS suspending the app, may or may not have reached the server,
/// and nothing on this side can tell which. Sent again blind, the letter
/// could be in Drafts twice; not sent again, it could be nowhere. Asking
/// Drafts for the Message-ID settles it. A new one for each version, not one
/// for the letter's whole life, so a copy found is known to be this very
/// text and not an older one, and so the server is never handed two
/// different letters under one Message-ID, which Gmail may take for the
/// same message.
///
/// A version is written down as tried (`appending`) only once nothing is
/// left but the APPEND: after the connection, the look in Drafts and the
/// files, any of which can fail with nothing sent. Written down before
/// that, a letter that never reached the server was looked for in Drafts at
/// every later upload, and a forward whose original has gone, which fails
/// at its files every time, cost a search each time as well.
struct DraftUpload: Sendable {
    let version: String
    let earlier: [String]
    /// Writes `version` down as tried. The APPEND waits for it, and does
    /// not go if it throws.
    var appending: @Sendable () async throws -> Void = {}
}

/// A letter from the Outbox on its way to the server (`LocalDrafts.send`).
struct OutgoingLetter: Sendable {
    /// Fixed when the letter entered the Outbox, and the same at every
    /// attempt, so an attempt cut off after the server had it can be looked
    /// for in Sent Mail.
    let messageID: String
    /// Writes the attempt down as on its way. DATA waits for it, and is not
    /// sent if it throws.
    var beforeData: @Sendable () async throws -> Void = {}
}

/// What a letter kept on the iPad became in Drafts.
struct DraftSaved: Equatable, Sendable {
    /// Its copy there, or nil when the server took it without saying where
    /// (no UIDPLUS).
    let id: String?
    /// The copies it took the place of that were removed: the one it was
    /// reopened from, and any an earlier upload of it left.
    let replaced: [String]
}

/// A list opened somewhere other than the top.
struct MessageWindow {
    /// Newest first.
    var messages: [MessageSummary]
    /// Which row is the day he asked for, so the list can scroll to it.
    var anchorIndex: Int
    /// There is no more mail newer than `messages.first` — the list is
    /// against the top of the folder and must stop trying to load upward.
    var reachedNewest: Bool
    /// Likewise downward.
    var reachedOldest: Bool
    /// The day the anchor actually landed on, which is not always the day
    /// asked for: pick a Sunday he had no mail and the anchor is Monday.
    /// Reporting the real one is the difference between a jump that looks
    /// broken and one that looks careful.
    var landedOn: Date
}

/// What the user is allowed to see when something breaks.
///
/// `PRODUCT_SPEC.md` fixes these four strings. Raw IMAP protocol text goes to
/// the admin diagnostics log and never to him — a 90-year-old reading
/// "BAD Command Argument Error. 11" learns only that he has done something
/// wrong, which he has not.
enum MailError: LocalizedError {
    case cannotConnect
    case notSent
    case attachmentFailed
    case passwordNeedsUpdating
    /// A FIFTH string, and a deliberate deviation from the four the spec
    /// fixes. Recorded rather than slipped in.
    ///
    /// The rule those four exist to enforce is that raw protocol text never
    /// reaches him — "552 5.2.3 Your message exceeded Google's message size
    /// limits" teaches a 90-year-old nothing. That rule is kept here. What
    /// is not kept is the pretence that "Message was not sent." covers this
    /// case: it is true, it is useless, and it arrives after a minute of
    /// uploading. He would try again, wait again, and fail again, because
    /// nothing told him the letter itself is the problem or that removing
    /// something would fix it.
    case messageTooLarge
    /// The connection to the submission server went, or stopped answering,
    /// before the server had said whether it took the letter. Not a new
    /// sentence: he reads "Message was not sent." as before. What is new is
    /// that the app can tell it from a letter the server refused, since this
    /// one may go later as it is, and the composer puts it in the Outbox
    /// rather than keeping the sheet (`Outbox.waits(after:)`, B-052).
    case connectionLost
    /// The submission server said "not now": a 4yz reply, RFC 5321's
    /// transient negative completion, such as Gmail's "421 4.7.0 Try again
    /// later" or "451 4.3.0" after DATA. Nothing was delivered, and the same
    /// letter may go later as it is, so it waits in the Outbox as for a lost
    /// connection. Read out as "Message was not sent.", as before.
    case refusedForNow
    /// A letter kept on the iPad carries a file, or a picture in its quote,
    /// from a letter on Gmail that is no longer where it named it, and not
    /// in All Mail either: after a password saved that opens another
    /// mailbox under the same address (B-033), or the original deleted.
    /// The letter does not go, rather than go with another letter's file
    /// under its file's name, or without the file.
    ///
    /// A SIXTH string, recorded as `messageTooLarge` is. Mail's own, as its
    /// users quote the alert iOS Mail puts up when a forward's attachments
    /// cannot be had ("Unable to Attach", "One or more attachments failed
    /// to load.", Apple's forums, thread 254851082, iOS 16.4.1). Mail offers
    /// Continue Anyway there; nothing here sends a letter short of a file.
    /// It is the first line of the letter's row in the Outbox or Drafts,
    /// and what the sheet says if he sends it.
    case attachmentsMissing

    var errorDescription: String? {
        switch self {
        case .cannotConnect:        return "Can't connect to mail server."
        case .notSent, .connectionLost, .refusedForNow: return "Message was not sent."
        case .attachmentFailed:     return "Attachment could not be downloaded."
        case .attachmentsMissing:   return "One or more attachments failed to load."
        case .passwordNeedsUpdating: return "Password needs to be updated in Settings."
        case .messageTooLarge:      return "This message is too big to send. Try sending fewer attachments."
        }
    }
}

extension MailRepository {

    /// Nothing kept, unless the repository keeps it.
    var shelf: MailShelf? { nil }

    /// `send`, with nobody told how the upload is getting on.
    func send(_ draft: Draft) async throws {
        try await send(draft, progress: nil)
    }
}
