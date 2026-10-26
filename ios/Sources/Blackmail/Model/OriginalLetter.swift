import Foundation

/// The letter a reply answers or a forward passes on, named as Gmail knows
/// it, so that once the reply or the forward has gone the original can be
/// marked on the server as Mail marks it (B-152): `\Answered` for a reply,
/// `$Forwarded` for a forward, after the server's 250 for the letter, and
/// for a letter that goes later from the Outbox once it goes.
///
/// By Gmail's id for it (X-GM-MSGID) and the folder it was opened in, not by
/// folder and UID: a letter in the Outbox can wait days, the original moved
/// or filed meanwhile, and Gmail's id is the letter's wherever it is. Kept
/// with the letter on the iPad (`LocalDraftStore`), so a reply sent from the
/// Outbox after a relaunch still names it.
///
/// This is the one change made on the server for him after a send, and it
/// is the narrow exception to D-016's "no queue of offline changes" that
/// the owner allowed on 2026-10-26: it is never kept apart from the letter
/// it belongs to, it is written once, when that letter goes, and a write
/// that fails is dropped, never tried again.
struct OriginalLetter: Equatable, Sendable {

    enum Kind: Equatable, Sendable {
        case reply, forward
    }

    var kind: Kind
    /// Gmail's id for the original (X-GM-MSGID).
    var letter: UInt64
    /// The folder the original was opened in, as the pane named it: looked
    /// in first, then All Mail.
    var mailboxID: String

    /// For a reply or a forward made from `m`; nil when the server named no
    /// Gmail id for it, and then nothing is marked.
    init?(_ m: Message, as kind: Kind) {
        guard let letter = m.gmailMessageID else { return nil }
        self.init(kind: kind, letter: letter, mailboxID: m.mailboxID)
    }

    init(kind: Kind, letter: UInt64, mailboxID: String) {
        self.kind = kind
        self.letter = letter
        self.mailboxID = mailboxID
    }

    /// The flag Mail writes. `$Forwarded` is the keyword iOS 18.6's Mail
    /// knows beside `Forwarded` (B-102); which of the two it writes on
    /// Gmail has not been seen. The row reads both.
    var flag: String {
        switch kind {
        case .reply: return "\\Answered"
        case .forward: return "$Forwarded"
        }
    }

    /// Posted on the main thread once the server has taken the mark, with
    /// the original under `markedKey`: the list puts the arrow on its rows
    /// of that letter (`ListLetters.originalMarked`), as the next listing
    /// would from the server's flags.
    static let marked = Notification.Name("OriginalLetter.marked")
    static let markedKey = "original"
}

extension MessageSummary {

    /// The row as it is once `original` has been marked: answered or
    /// forwarded, when it is that letter.
    func marking(_ original: OriginalLetter) -> MessageSummary {
        guard gmailMessageID == original.letter else { return self }
        var row = self
        switch original.kind {
        case .reply: row.isAnswered = true
        case .forward: row.isForwarded = true
        }
        return row
    }
}
