import Foundation

/// The message list edited in place, rather than fetched again, after
/// something he did from the reading pane: a letter binned or moved away, a
/// flag set, a page of the same folder fetched afresh.
///
/// Out of `MessageListViewController` for the reason `SearchAnswer` is: the
/// controller is UIKit and does not exist on the machine the suite runs on.
/// What the controller does with these is regroup and redraw.
enum ListEdit {

    /// The same letter under another mailbox's ids: an All Mailboxes hit
    /// from All Mail, and the Inbox row it also is.
    ///
    /// Gmail numbers each mailbox on its own, so one letter has an id per
    /// mailbox that holds it, and a list can show two of them at once: its
    /// folder's rows under a search's. Binned from one, it has gone from
    /// the other too, and left there it is a row that opens empty, because
    /// the folder no longer holds that UID.
    ///
    /// Matched on what the two copies share byte for byte, since both come
    /// from the one message: Gmail's thread id, the envelope's date, sender
    /// and subject. Only across mailboxes, never within one, where two rows
    /// are always two letters; and only with a thread id, which a server
    /// without Gmail's extension does not give and has no All Mail to make
    /// a second copy in anyway. Two different letters would have to share
    /// all four to be taken for one, sent in the same second by the same
    /// sender under the same subject in the same conversation, and the cost
    /// if they did is one row gone until the next Refresh.
    static func twins(of letter: MessageSummary,
                      among letters: [MessageSummary]) -> [MessageSummary] {
        guard let thread = letter.threadID, !thread.isEmpty else { return [] }
        var seen = Set<String>()
        return letters.filter { other in
            other.mailboxID.caseInsensitiveCompare(letter.mailboxID) != .orderedSame
                && other.threadID == thread
                && other.date == letter.date
                && other.sender == letter.sender
                && other.subject == letter.subject
                && seen.insert(other.id).inserted
        }
    }

    /// A page fetched afresh, with the previews already fetched for any of
    /// its letters put back.
    ///
    /// A letter's text never changes under its id: the id carries the
    /// mailbox's UIDVALIDITY, and a UID is never reused within one. So a
    /// preview already on screen is the preview, and fetching it again only
    /// blanks the row for as long as that takes. Refreshing a list used to
    /// do exactly that to every row.
    ///
    /// And not when both rows carry a Gmail message id and the ids differ.
    /// Within a launch they always agree; a row kept on the iPad from an
    /// earlier one (D-016) can be another mailbox's under the same id,
    /// since every Gmail Inbox reports UIDVALIDITY 1, and its preview is
    /// not this letter's. A row with no id carries: the server's copy of a
    /// letter kept in Drafts is drawn from the letter (`LocalDrafts`), with
    /// none, and refusing it blanked the preview of every draft that had
    /// just reached the server and fetched it again at the next listing.
    static func carryingPreviews(from shown: [MessageSummary],
                                 into fetched: [MessageSummary]) -> [MessageSummary] {
        var known: [String: MessageSummary] = [:]
        for letter in shown where !letter.preview.isEmpty { known[letter.id] = letter }
        guard !known.isEmpty else { return fetched }
        return fetched.map { letter in
            guard letter.preview.isEmpty, let was = known[letter.id],
                  sameLetter(was, letter) else { return letter }
            var carried = letter
            carried.preview = was.preview
            return carried
        }
    }

    /// Whether two rows under one id are the same letter, as far as their
    /// Gmail message ids say: unless both have one and they differ. What a
    /// preview, a read mark and a flag go across by, from a row kept on the
    /// iPad (D-016) or one on screen, to a row a listing brings.
    static func sameLetter(_ one: MessageSummary, _ other: MessageSummary) -> Bool {
        sameLetter(one.gmailMessageID, other.gmailMessageID)
    }

    static func sameLetter(_ one: UInt64?, _ other: UInt64?) -> Bool {
        guard let one, let other else { return true }
        return one == other
    }

    /// `letters` with the previews of their copies under other mailboxes'
    /// ids put in where they have none: an All Mailboxes hit's, fetched from
    /// All Mail, for its Inbox row. The same letter has the same text, so
    /// its preview is the same, and asking the Inbox for it again would
    /// only leave the row blank for as long as that takes.
    static func carryingPreviews(fromTwins others: [MessageSummary],
                                 into letters: [MessageSummary]) -> [MessageSummary] {
        let previewed = others.filter { !$0.preview.isEmpty }
        guard !previewed.isEmpty else { return letters }
        return letters.map { letter in
            guard letter.preview.isEmpty,
                  let twin = twins(of: letter, among: previewed).first else { return letter }
            var carried = letter
            carried.preview = twin.preview
            return carried
        }
    }

    /// Changes the letter with `id` in `letters`, if it is there.
    static func change(_ letters: inout [MessageSummary], id: String,
                       _ edit: (inout MessageSummary) -> Void) {
        guard let i = letters.firstIndex(where: { $0.id == id }) else { return }
        edit(&letters[i])
    }

    /// The rows to select once the list has been regrouped: the row of
    /// each id that was selected before (`kept`), and the row of a letter
    /// just marked read as the one open in the reading pane (`opened`).
    /// A conversation's row stands for every letter in it, so an id finds
    /// the row of the conversation it is in. Each row once, in list order.
    ///
    /// Every row that was selected, not only the first. Out of Edit mode
    /// there is one, the letter open in the pane; in Edit mode they are his
    /// ticks, and a regroup used to keep only one of them. It did not
    /// matter while nothing regrouped the list in Edit mode but a page
    /// loaded as he scrolled, but the reading pane now marks a letter read
    /// and flags, bins and moves in the list beside it whatever mode the
    /// list is in, and a Delete of his ticks would then have binned one
    /// conversation and left the rest.
    ///
    /// Out of Edit mode the row of `opened` is the one selected, when it
    /// has one: the table selects one row at a time, and the letter just
    /// opened is the one in the pane. In Edit mode `opened` is not selected
    /// at all, since a selected row is a tick there: opening a letter inside
    /// the conversation in the pane would have ticked that conversation for
    /// him, and a bulk Delete taken it with the rest.
    static func selectedRows(in threads: [MessageThread], kept: [String],
                             opened: String?, editing: Bool) -> [Int] {
        func rows(of ids: Set<String>) -> [Int] {
            guard !ids.isEmpty else { return [] }
            return threads.indices.filter { i in
                ids.contains(threads[i].id) || threads[i].messages.contains { ids.contains($0.id) }
            }
        }
        if !editing, let opened, let row = rows(of: [opened]).first { return [row] }
        return rows(of: Set(kept))
    }
}

/// Letters taken off the list by a Delete or Move from the reading pane.
///
/// Hidden rather than cut out of the list's arrays, because the arrays are
/// also what paging reads. The next page is asked for from the last letter
/// the last page gave, and a letter binned from the bottom of the list would
/// move that cursor up to a letter already paged past. In a search the page
/// would then be replayed from the one before, binned letter and all; in a
/// folder it would ask the server again for the binned letter's old UID, and
/// the repository would have to make up the page with a second FETCH
/// (`IMAPMailRepository.page(olderThan:)`). Kept in the arrays, the letter
/// still marks where paging has got to, and a page that brings it again is
/// known and dropped.
///
/// Taken off at the tap, so the row goes when he asks rather than when the
/// server answers, and put back if the server refuses. The same letter under
/// another mailbox's ids goes with it when it has left every folder.
struct RemovedLetters {

    /// Removals the server has not answered yet, by the letter the write is
    /// for, with every id hidden for it: its own, and its twins'.
    private var pending: [String: Set<String>] = [:]
    /// Removals the server has made.
    private var landed: Set<String> = []

    /// `letters` without the ones taken off.
    func remaining(_ letters: [MessageSummary]) -> [MessageSummary] {
        let hidden = hiddenIDs
        guard !hidden.isEmpty else { return letters }
        return letters.filter { !hidden.contains($0.id) }
    }

    func hides(_ id: String) -> Bool { hiddenIDs.contains(id) }

    private var hiddenIDs: Set<String> {
        pending.values.reduce(landed) { $0.union($1) }
    }

    /// Off the list while the write that removes it is on its way.
    mutating func take(_ id: String, with twins: [String] = []) {
        var ids = pending[id] ?? []
        ids.insert(id)
        ids.formUnion(twins)
        pending[id] = ids
    }

    /// The write failed and the letter is still where it was.
    mutating func putBack(_ id: String) {
        pending.removeValue(forKey: id)
    }

    /// The write landed. Hidden until the list is next fetched afresh.
    mutating func land(_ id: String) {
        guard let ids = pending.removeValue(forKey: id) else { return }
        landed.formUnion(ids)
    }

    /// The list has been fetched afresh from the top. What the server has
    /// removed is not in it, and what it still has is: Refresh is the one
    /// thing that reconciles the list with the server, whatever was done to
    /// it locally, so nothing landed stays hidden. A removal still on its
    /// way does, or the letter would come back for as long as its write takes.
    mutating func listReplaced() {
        landed = []
    }
}

/// The folder counts this list has taken one off for letters read, once
/// per letter.
///
/// Never cleared. It is scoped to one list, and the list is rebuilt
/// whenever the folder changes, so it cannot outgrow a page of mail. A full
/// sweep of the counts installs the server's numbers regardless of what is
/// in here, so keeping an id forever costs nothing, and dropping one risks
/// billing the same letter twice.
///
/// Once is the whole rule. The list clears a letter's unread dot at the tap,
/// and takes the one off only after the server has the flag; a fetch of the
/// list made before the flag landed can bring the dot back and re-arm the
/// tap. Without this a letter could be billed on each.
struct ReadBilling {

    private(set) var counted: Set<String> = []

    /// A letter the server now has as read: the folders to take one off,
    /// or nil when it has been taken off already.
    mutating func read(_ letter: MessageSummary) -> [String]? {
        guard counted.insert(letter.id).inserted else { return nil }
        return Self.folders(of: letter)
    }

    /// A letter marked unread again: the folders to add one back to. The
    /// billing is forgotten, so reading it again takes the one off again;
    /// kept, a letter read, marked unread and read again would be free the
    /// second time and the count would drift low, which says "no new mail"
    /// when there is some.
    mutating func unread(_ letter: MessageSummary) -> [String] {
        counted.remove(letter.id)
        return Self.folders(of: letter)
    }

    /// A letter that has left every folder it was counted in: binned, or
    /// moved to Spam, which on Gmail take it out of everything else. Its
    /// unread one comes off those folders if it was still unread and nothing
    /// has taken it off already, neither reading it nor reading the same
    /// letter under another mailbox's id (`twins`), which is one message
    /// and one count on the server. Nil when there is nothing to take off.
    mutating func left(_ letter: MessageSummary, twins: [MessageSummary] = []) -> [String]? {
        guard !letter.isRead,
              !twins.contains(where: { $0.isRead || counted.contains($0.id) }) else { return nil }
        return read(letter)
    }

    /// Every folder the letter is counted in; with no labels to say, the
    /// one it was listed from, which is right for a server where a letter
    /// is in one folder only.
    static func folders(of letter: MessageSummary) -> [String] {
        letter.countedFolderIDs.isEmpty ? [letter.mailboxID] : letter.countedFolderIDs
    }
}
