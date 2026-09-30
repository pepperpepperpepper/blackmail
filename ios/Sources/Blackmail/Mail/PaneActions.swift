import Foundation

/// A Delete, Move or Flag from the reading pane's toolbar.
enum PaneAction: Equatable {
    case delete
    case move(to: Mailbox)
    case flag(Bool)
}

/// The list beside the reading pane, as its Delete, Move and Flag edit it.
/// `ListLetters` is the one the app uses, the letters
/// `MessageListViewController` draws; the rules it applies are
/// `RemovedLetters`, `ReadBilling` and `ListEdit`.
@MainActor
protocol PaneActionList: AnyObject {
    /// The list's own copy of a letter, nil when it has none. It can know
    /// more than the pane's: a letter is marked read by the tap on its row,
    /// after the pane has been handed the row.
    func letter(_ id: String) -> MessageSummary?
    /// The reading pane has let the letter go, emptied at the tap of a
    /// Delete or a Move: its row, if it stays, is no longer the one open.
    func letGo(_ letter: MessageSummary)
    /// Takes the letter's row off the list, and, when the letter has left
    /// every folder, the rows that are the same letter under other ids.
    func take(_ letter: MessageSummary, fromEveryFolder: Bool)
    /// The write failed and the letter is still where it was.
    func putBack(_ letter: MessageSummary)
    /// The write landed. A letter that has left every folder while still
    /// unread comes off their counts, once.
    func removalLanded(_ letter: MessageSummary, fromEveryFolder: Bool)
    /// Takes the letter itself, not its id: the pane can still hold a
    /// search hit after the search has ended, and its copies in the folder
    /// underneath are found from the letter, not from a row that is gone.
    func setFlagged(_ flagged: Bool, on letter: MessageSummary)
    /// The server has answered the Flag set on `letter`: taken, or refused
    /// and put back as it was, on the copies that are still that letter.
    func flagAnswered(_ letter: MessageSummary, landed: Bool)
    /// A letter that stays on the list, now filed in `folder` as well, so
    /// reading it later takes one off there too.
    func addCountedFolder(_ folder: String, to id: String)
}

/// What a Delete, Move or Flag from the reading pane does besides its write.
///
/// All three used to reload the whole list and sweep every folder's count:
/// a LIST and a STATUS per folder, the Inbox's SEARCH ALL and page FETCH,
/// and every preview again. The previews blanked and refilled, a search or a
/// date jump he was in was thrown away with his place in the list, and the
/// binned row stayed on screen until all of that had landed. Now each edits
/// the rows it changed, the counts come from arithmetic where it is exact,
/// and a sweep is asked for only when a count may have moved and the
/// arithmetic cannot say by how much. Refresh is still the whole
/// reconciliation.
///
/// Out of `MessageDetailViewController` and `RootViewController` for the
/// reason `SearchAnswer` is: they are UIKit and do not exist on the machine
/// the suite runs on.
@MainActor
enum PaneActions {

    struct Effect: Equatable {
        /// The row leaves the list.
        var removesRow: Bool
        /// The letter has left every folder it was counted in: Trash and
        /// Spam are exclusive on Gmail. An unread one comes off their
        /// counts, and its rows under other mailboxes' ids go too.
        var leavesEveryFolder: Bool
        /// The row stays, and the letter is now filed here as well.
        var alsoFiledIn: String?
        /// Whether an unread letter changes a count the list cannot work
        /// out itself, the destination's, so the counts are swept.
        var sweepsIfUnread: Bool
    }

    /// `role` is that of the mailbox the letter was listed from, which for
    /// an All Mailboxes hit is not the list's.
    ///
    /// - Delete moves to Trash, and inside Trash sets `\Deleted`, which
    ///   takes it out of Trash too. Either way the row goes and the letter
    ///   has left everything. Inside Trash the one taken off Trash's count
    ///   is the whole change, so there is nothing to sweep for.
    /// - Move to Trash or Spam is a Delete by another name.
    /// - Move out of All Mail keeps the row: Gmail's All Mail is every
    ///   letter not in Trash or Spam, so filing one elsewhere leaves it
    ///   there.
    /// - Any other Move takes the row off and leaves the letter's other
    ///   labels alone, so nothing is taken off locally; the source loses an
    ///   unread letter and the destination gains it, and a sweep says so.
    /// - Flag keeps the row. An unread letter flagged or unflagged changes
    ///   Starred's count.
    ///
    /// A read letter changes no count, so none of them sweeps for one.
    nonisolated static func effect(of action: PaneAction,
                                   onLetterIn role: Mailbox.Role?) -> Effect {
        switch action {
        case .flag:
            return Effect(removesRow: false, leavesEveryFolder: false,
                          alsoFiledIn: nil, sweepsIfUnread: true)
        case .delete:
            return Effect(removesRow: true, leavesEveryFolder: true,
                          alsoFiledIn: nil, sweepsIfUnread: role != .trash)
        case .move(let destination) where destination.role == .trash || destination.role == .junk:
            return Effect(removesRow: true, leavesEveryFolder: true,
                          alsoFiledIn: nil, sweepsIfUnread: true)
        case .move(let destination) where role == .archive:
            return Effect(removesRow: false, leavesEveryFolder: false,
                          alsoFiledIn: destination.id, sweepsIfUnread: true)
        case .move:
            return Effect(removesRow: true, leavesEveryFolder: false,
                          alsoFiledIn: nil, sweepsIfUnread: true)
        }
    }

    /// Edits `list` at once, sends the write, and then puts the list back if
    /// the server refused, or bills and sweeps if it took it. Returns
    /// whether it took it; the caller says so if not.
    ///
    /// One Flag at a time for a letter: the pane ignores a second tap on it
    /// while the first is on its way (`PaneWrites`). Two in flight, a double
    /// tap into a dead socket, both fail, and the second would put back the
    /// value the first had only asked for.
    ///
    /// Whether the letter was unread is read off the list's copy once the
    /// write has landed, not off the pane's: the pane was handed the row
    /// before the tap that opened it marked it read.
    static func run(_ action: PaneAction, on letter: MessageSummary,
                    inFolderWithRole role: Mailbox.Role?,
                    list: PaneActionList?, repository: MailRepository,
                    requestSweep: @MainActor () -> Void) async -> Bool {
        let effect = effect(of: action, onLetterIn: role)
        let before = list?.letter(letter.id) ?? letter

        switch action {
        case .flag(let flagged):
            list?.setFlagged(flagged, on: before)
        case .delete, .move:
            list?.letGo(before)
            if effect.removesRow { list?.take(before, fromEveryFolder: effect.leavesEveryFolder) }
        }

        do {
            switch action {
            case .delete:
                try await repository.delete(letter.id, from: letter.mailboxID)
            case .move(let destination):
                try await repository.move(letter.id, from: letter.mailboxID, to: destination.id)
            case .flag(let flagged):
                try await repository.setFlagged(flagged, id: letter.id, mailboxID: letter.mailboxID)
            }
        } catch {
            switch action {
            case .flag:
                list?.flagAnswered(before, landed: false)
            case .delete, .move:
                if effect.removesRow { list?.putBack(before) }
            }
            if error is MailShelf.NotTheKeptLetter { notTheKeptLetter(before, list: list) }
            return false
        }

        if case .flag = action { list?.flagAnswered(before, landed: true) }
        let landed = list?.letter(letter.id) ?? before
        if effect.removesRow {
            list?.removalLanded(landed, fromEveryFolder: effect.leavesEveryFolder)
        }
        if let folder = effect.alsoFiledIn { list?.addCountedFolder(folder, to: letter.id) }
        if effect.sweepsIfUnread && !landed.isRead { requestSweep() }
        return true
    }

    /// A row kept on the iPad that the server has said is not the letter it
    /// was kept as (`MailShelf.NotTheKeptLetter`), from a write or from the
    /// letter opened: nothing was sent and nothing of it shown, and it comes
    /// off the list until the list is next fetched afresh, which has the say
    /// (D-016). For the reading pane's Delete, Move and Flag, the read mark
    /// of a tap and of Edit mode's Mark, and the letter opened.
    ///
    /// Only while the list's row under that id is still the kept one, by
    /// its Gmail message id. The launch's listing can land while the server
    /// is being asked, and a fresh page that has taken the kept one's place
    /// has put the server's own letter under that id, which stays. Returns
    /// whether the row came off.
    @discardableResult
    static func notTheKeptLetter(_ letter: MessageSummary, list: PaneActionList?) -> Bool {
        guard let list, let row = list.letter(letter.id),
              row.gmailMessageID == letter.gmailMessageID else { return false }
        list.take(row, fromEveryFolder: false)
        list.removalLanded(row, fromEveryFolder: false)
        return true
    }
}

/// The reading pane's Delete and Flags on their way to the server, and so
/// what the next tap on either does.
///
/// Out of `MessageDetailViewController` for the reason `PaneLoads` is: the
/// controller is UIKit and does not exist on the machine the suite runs on.
struct PaneWrites {

    /// Letters with a Flag's STORE on its way.
    private var flagging: Set<String> = []

    /// A Delete on its way. Delete stays grey until it is answered, whatever
    /// the pane shows meanwhile, so a second tap cannot bin the next letter
    /// he opens before the first has gone. Greyed, so it is never a tap
    /// that silently does nothing.
    private(set) var deleting = false

    /// Whether a Flag tapped on the letter `id` goes. Not while that
    /// letter's last one is on its way: that is a double tap, and two
    /// STOREs in flight that both fail, as they do into a dead socket, would
    /// leave the flag the first one only asked for. Another letter's Flag
    /// goes, and the button is not greyed for it.
    ///
    /// Per letter, where it was once for the whole pane. A STORE can be on
    /// its way far longer than a double tap: behind a letter's download
    /// already on the wire, behind the probe in front of a write after
    /// ninety seconds of quiet and the reconnect it may make, or up to the
    /// read deadline on a half-open socket. A Flag on the next letter he
    /// opened in that time was dropped, with nothing on screen to say so.
    mutating func startFlag(_ id: String) -> Bool {
        flagging.insert(id).inserted
    }

    /// The server has answered the letter's Flag, either way.
    mutating func flagAnswered(_ id: String) {
        flagging.remove(id)
    }

    /// Whether a Delete tapped now goes.
    mutating func startDelete() -> Bool {
        guard !deleting else { return false }
        deleting = true
        return true
    }

    /// The server has answered the Delete, either way.
    mutating func deleteAnswered() {
        deleting = false
    }
}

extension Array where Element == Mailbox {

    /// The role of the folder a letter was listed from, by its id in either
    /// spelling (see `firstIndex(matchingMailboxID:)`), or from the id itself
    /// when it is a role word no folder here carries.
    func role(of mailboxID: String) -> Mailbox.Role? {
        if let i = firstIndex(matchingMailboxID: mailboxID) { return self[i].role }
        return Mailbox.Role(rawValue: mailboxID.lowercased())
    }
}
