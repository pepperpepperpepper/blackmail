import Foundation

/// His own letters in an Inbox conversation, brought in from Sent Mail, as
/// Mail's Complete Threads brings them (B-104).
///
/// Mail's Threading settings have a switch, Complete Threads, on from the
/// factory, whose words are Apple's: "Show all the messages in a thread,
/// even if some have been moved to other mailboxes." With it on, his replies
/// sit in an Inbox conversation among the letters they answer, each marked
/// with the mailbox it was found in. Here a conversation used to hold the
/// letters of the folder it is listed in and no others, so a conversation
/// in the Inbox showed the letters to him and none of his answers.
///
/// Read only, and only in the Inbox. His letters are looked for in Sent Mail
/// by Gmail's own thread id, X-GM-THRID, when a conversation of more than
/// one letter opens there; they go into the reading pane's stack closed,
/// by date, and are never part of the list: not its rows, its counts, Edit
/// mode, the read marks or the pane's Delete, Move, Flag and Reply, which
/// stay on the Inbox letter he opened last. Nothing of them is kept on the
/// iPad (`MailShelf`, `LocalDrafts`): the pane holds them while it shows
/// the conversation, and the repository its answer for `remembered`.
///
/// What decides whether a conversation is looked up, and which of what is
/// found are shown, is here, out of the controllers, so the suite on Linux
/// can test it.
enum CompleteThreads {

    /// The most of his letters one conversation brings in: the newest, by
    /// when Gmail took them.
    static let mostLetters = 20

    /// How long the answer for a conversation is used again without asking
    /// Sent Mail, in seconds: a conversation opened, left and opened again
    /// within it sends nothing. A letter sent, a Refresh and a password
    /// saved forget it sooner (`RelatedMemo`).
    static let remembered: TimeInterval = 10 * 60

    /// Gmail's thread id as the number `UID SEARCH X-GM-THRID` takes, nil
    /// when it is not all digits or does not fit 64 bits. Nothing else is
    /// ever put into the search.
    static func threadNumber(_ threadID: String?) -> UInt64? {
        guard let threadID, !threadID.isEmpty,
              threadID.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return UInt64(threadID)
    }

    /// The conversation to look up his letters for, as its thread number,
    /// or nil to show it as before: only a conversation of more than one
    /// letter, listed grouped in the Inbox, never a search's, with Gmail's
    /// thread id, and the switch on. A single letter, a search, every
    /// other folder and the switch off are left exactly as they were.
    /// Whether the server has Gmail's extension is the repository's to
    /// see, which sends nothing without it.
    static func thread(toComplete thread: MessageThread, listedIn role: Mailbox.Role?,
                       searching: Bool, switchedOn: Bool) -> UInt64? {
        guard switchedOn, role == .inbox, !searching, thread.count > 1 else { return nil }
        return threadNumber(thread.newest.threadID)
    }

    /// Of Sent Mail's hits, as its FETCH gives them, the ones that are his
    /// letters only there: each with Gmail's id for the letter, which
    /// opening it checks (D-016), and none that is in the Inbox too, which
    /// the conversation's Inbox letters have already, as a letter he sent
    /// himself is. X-GM-LABELS leaves out the folder it is asked from, so
    /// from Sent Mail a letter in the Inbox as well lists `\Inbox`.
    static func onlyInSentMail(_ fetched: [IMAPFetchResult]) -> [IMAPFetchResult] {
        fetched.filter { hit in
            hit.gmailMessageID != nil
                && !hit.labels.contains { $0.caseInsensitiveCompare("\\Inbox") == .orderedSame }
        }
    }

    /// Which of `found` go into the stack: none whose Gmail id is one of
    /// the stack's own, `besides`, and none whose id is one of its ids,
    /// `apartFrom`, since each folder has a UIDVALIDITY of its own and
    /// nothing says a Sent Mail id can never be an Inbox one. None without
    /// a Gmail id. The newest `mostLetters`, by when Gmail took them, and
    /// by their dates where it took two at once; the oldest first.
    static func shown(_ found: [MessageSummary], besides: Set<UInt64>,
                      apartFrom ids: Set<String> = []) -> [MessageSummary] {
        let kept = found.filter { letter in
            guard let gmail = letter.gmailMessageID else { return false }
            return !besides.contains(gmail) && !ids.contains(letter.id)
        }
        let newestFirst = kept.sorted { isLater($0, than: $1) }
        return Array(newestFirst.prefix(mostLetters).reversed())
    }

    /// Whether `a` came after `b`: by when Gmail took it, the letter's Date
    /// where that is not known or is the same. The order of a stack.
    static func isLater(_ a: MessageSummary, than b: MessageSummary) -> Bool {
        let took = (a.arrived ?? a.date, b.arrived ?? b.date)
        return took.0 != took.1 ? took.0 > took.1 : a.date > b.date
    }

    /// What his letter says above its body once opened: where it was found,
    /// by the folder's name as the Mailboxes pane shows it, "Sent" on Gmail,
    /// Mail's word for Gmail's Sent Mail (B-144). Mail's short form, "Found
    /// in %@", which Mail fills with a name of its own.
    static func foundIn(_ folderName: String) -> String {
        "Found in " + folderName
    }
}

/// His letters of one conversation found in Sent Mail, and that folder's
/// name as the Mailboxes pane shows it, for the label over each
/// (`CompleteThreads.foundIn`).
struct RelatedLetters: Equatable {
    var folderName: String
    var letters: [MessageSummary]

    /// Nothing found, or nothing asked.
    static let none = RelatedLetters(folderName: "", letters: [])
}

/// What the repository found in Sent Mail for each conversation, for
/// `CompleteThreads.remembered`, in memory alone. Read without waiting for
/// the repository's actor, so a conversation opened again draws his letters
/// in its first frame; locked, since the actor writes it.
///
/// Forgotten whole when a letter he sends has gone, when the Outbox finds
/// in Sent Mail a letter whose sending it could not be sure of, at a
/// Refresh and when a new password is saved, so a reply just sent is looked
/// for again. A lookup still out when it is forgotten has its answer shown,
/// and not kept (`generation`): asked before the reply was there, it would
/// otherwise be served without it for ten minutes.
final class RelatedMemo: @unchecked Sendable {

    private let lock = NSLock()
    private let now: @Sendable () -> Date
    private var threads: [UInt64: (found: RelatedLetters, at: Date)] = [:]
    private var forgotten = 0

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// The letters found for `thread`, if they were found less than
    /// `CompleteThreads.remembered` ago. A time after now is not recent:
    /// the clock has been set back.
    func letters(inThread thread: UInt64) -> RelatedLetters? {
        lock.lock()
        defer { lock.unlock() }
        guard let kept = threads[thread] else { return nil }
        let age = now().timeIntervalSince(kept.at)
        guard age >= 0, age < CompleteThreads.remembered else { return nil }
        return kept.found
    }

    /// How many times the memo has been forgotten. A lookup takes it before
    /// it asks Sent Mail, and hands it to `keep` with what it found.
    var generation: Int {
        lock.lock()
        defer { lock.unlock() }
        return forgotten
    }

    /// What was found for `thread`, now, by a lookup that took `generation`
    /// before it asked; nothing kept if the memo has been forgotten since.
    /// Answers past their time go as another comes in, so the memo never
    /// holds more than ten minutes'.
    func keep(_ found: RelatedLetters, inThread thread: UInt64, asOf generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == forgotten else { return }
        let at = now()
        var kept = threads.filter { _, entry in
            let age = at.timeIntervalSince(entry.at)
            return age >= 0 && age < CompleteThreads.remembered
        }
        kept[thread] = (found, at)
        threads = kept
    }

    func forget() {
        lock.lock()
        defer { lock.unlock() }
        forgotten &+= 1
        threads = [:]
    }
}
