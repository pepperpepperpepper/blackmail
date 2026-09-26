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
    func listMailboxes() async throws -> [Mailbox]

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

    func loadMessage(id: String, mailboxID: String) async throws -> Message

    func setRead(_ read: Bool, id: String, mailboxID: String) async throws
    func setFlagged(_ flagged: Bool, id: String, mailboxID: String) async throws

    func move(_ id: String, from sourceMailboxID: String, to destinationMailboxID: String) async throws
    func delete(_ id: String, from mailboxID: String) async throws

    func send(_ draft: Draft) async throws

    /// Saves to the Drafts folder, REPLACING the copy named by
    /// `draft.savedID` if there is one, and returns the id of the copy now
    /// on the server so the next save replaces this one in turn.
    ///
    /// Returns nil only when the server accepted the new copy but would not
    /// say where it put it (no UIDPLUS). The save still happened; the
    /// caller simply cannot chain another replacement onto it.
    @discardableResult
    func saveDraft(_ draft: Draft) async throws -> String?

    /// Removes a saved draft outright rather than binning it.
    func deleteDraft(_ id: String) async throws

    /// Reopens a saved draft for editing.
    func loadDraft(id: String, mailboxID: String) async throws -> Draft

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

    var errorDescription: String? {
        switch self {
        case .cannotConnect:        return "Can't connect to mail server."
        case .notSent:              return "Message was not sent."
        case .attachmentFailed:     return "Attachment could not be downloaded."
        case .passwordNeedsUpdating: return "Password needs to be updated in Settings."
        case .messageTooLarge:      return "This message is too big to send. Try sending fewer attachments."
        }
    }
}
