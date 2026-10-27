import Foundation

/// The letter the reading pane opens after a Delete or Move of the letter it
/// shows, as Apple Mail opens it (B-158).
///
/// Mail's setting, Settings > Apps > Mail > Message List > Delete or Move
/// Message Action, since iOS 18.4: View Next Message, its factory default,
/// opens the next letter in the list, marked read as any letter opened is;
/// Don't Select a Message opens none. Before 18.4 there was no setting, and
/// the next letter opened. What his iPad says cannot be read from here, so
/// Mail's factory default is built (the owner's ruling of 2026-10-26), and
/// `action` is the one place the app reads it. Its row is in Blackmail's
/// Settings, under Message List as in Mail's (`MailOptions`, B-167).
///
/// The pane used to empty after every Delete and Move, so that a second tap
/// on Delete could not bin a letter opened by itself (B-041). Mail has no
/// such guard; its Undo is the safety. What is kept of it is invisible: a
/// Delete within half a second of the last does nothing (`doubleTap`,
/// `PaneWrites`).
///
/// Out of `MessageListViewController` for the reason `ListEdit` is: the
/// controller is UIKit and does not exist on the machine the suite runs on.
enum NextLetter {

    /// Mail's two answers, by their words in its Settings, in their order
    /// there (`word`).
    enum Action: String, CaseIterable {
        /// "View Next Message": the next letter opens. Mail's factory
        /// default.
        case viewNextMessage
        /// "Don't Select a Message": the pane empties, as B-041 built it,
        /// and Delete stays grey until the server has the first one.
        case dontSelectAMessage
    }

    /// Not private, for the suite to hold it to its spelling.
    static let key = MailOptions.Option.deleteOrMoveMessageAction.key

    /// What his Delete or Move does to the pane. View Next Message unless
    /// it has been set otherwise; kept by `MailOptions`, read with
    /// `string(forKey:)`, so a key never written, or one written by a later
    /// build with a value this one does not know, is the factory default.
    static var action: Action {
        get { MailOptions.deleteOrMoveMessageAction }
        set { MailOptions.deleteOrMoveMessageAction = newValue }
    }

    /// Seconds after a Delete in which another tap on Delete does nothing,
    /// so a double tap does not bin the letter it has just opened. Not
    /// Mail's: Mail has none, nor any grey.
    static let doubleTap = 0.5

    /// The letter whose row opens once `letter`'s Delete or Move has taken
    /// its row off, chosen from `rows`, the list's rows as they stand at
    /// the tap, before it is taken off: the id of a letter that row still
    /// holds after, for the list to find the row by then; nil to leave the
    /// pane empty. `role` is that of the folder the letter was listed from
    /// (`PaneActions.effect`), `listedIn` the list's; `olderToCome`, that
    /// the list has older letters to page in below its rows.
    ///
    /// - The row that takes its place: the one below it. At the foot of the
    ///   list, the one above. Mail does not say which way; below is what
    ///   the gap audit found most likely, and an iPad on iOS 5 was once
    ///   seen opening the one above. Not at the foot of the pages loaded so
    ///   far, `olderToCome`, with older letters still on the server, or at
    ///   the foot of a day's list after Go to Date: the letter Mail would
    ///   open is not on the list yet, and the one above is a newer letter
    ///   it would not, so nothing opens.
    /// - A conversation that keeps other letters keeps its row: it opens
    ///   again without the letter, highlighted where the list draws it, as
    ///   Mail leaves a conversation on screen when one of its letters is
    ///   binned by that letter's own button. A row goes by its newest
    ///   letter, so one whose newest has gone can be drawn lower down. The
    ///   pane's Delete and Move act on the letter he opened last, not the
    ///   whole conversation (B-129).
    /// - A letter that stays on the list, moved out of All Mail, is passed
    ///   over: the row below it, or above at the foot.
    /// - The letter never opens again under another mailbox's id, a copy of
    ///   it (`ListEdit.twins`), whether its take hides the copy, as when it
    ///   leaves every folder, or leaves it, as when it is moved: it is the
    ///   letter he has just put away. No list of the app's holds both ids
    ///   today; an All Mailboxes search lists All Mail, Trash and Spam.
    /// - In a search, the next result: the rows are the hits, one letter
    ///   each.
    /// - Never a draft, an Outbox letter or a letter "On this iPad only":
    ///   their rows open the composer, not the pane. In Drafts and the
    ///   Outbox nothing opens; a row kept on the iPad is passed over.
    /// - A Flag or a read mark leaves the letter where it is, and nothing
    ///   opens for it; nor for a letter the list has no row for, a hit
    ///   after its search has ended.
    static func after(_ letter: MessageSummary, _ action: PaneAction,
                      onLetterIn role: Mailbox.Role?, in rows: [MessageThread],
                      listedIn list: Mailbox.Role?, olderToCome: Bool = false) -> String? {
        after([letter], action, onLetterIn: role, in: rows, listedIn: list,
              olderToCome: olderToCome)
    }

    /// `after`, for the letters of a row a drag on it, or More, has put away
    /// (B-156): every letter of the conversation, which takes the whole row,
    /// so the row below opens, or above at the foot, by the same rules. The
    /// row is the first letter's.
    static func after(_ letters: [MessageSummary], _ action: PaneAction,
                      onLetterIn role: Mailbox.Role?, in rows: [MessageThread],
                      listedIn list: Mailbox.Role?, olderToCome: Bool = false) -> String? {
        switch action {
        case .flag, .read: return nil
        case .delete, .move: break
        }
        guard list != .drafts, list != .outbox, let first = letters.first,
              let at = rows.firstIndex(where: { $0.messages.contains { $0.id == first.id } })
        else { return nil }
        let effect = PaneActions.effect(of: action, onLetterIn: role)
        // The letters, under any of their ids: what their take hides
        // (`ListLetters.take`), the letter and, when it leaves every folder,
        // its copies; and a copy it leaves, which is the same letter.
        func itself(_ m: MessageSummary) -> Bool {
            letters.contains { $0.id == m.id || !ListEdit.twins(of: $0, among: [m]).isEmpty }
        }
        // A letter of `row` that is still there after the take, and opens
        // in the pane; nil for a row that goes, holds only the letter, or
        // holds a letter kept on the iPad.
        func staying(_ row: MessageThread) -> MessageSummary? {
            guard !row.messages.contains(where: { LocalDraft.key(ofRow: $0.id) != nil }) else {
                return nil
            }
            return row.messages.first { !itself($0) }
        }
        if effect.removesRow, let rest = staying(rows[at]) { return rest.id }
        if let below = rows[(at + 1)...].lazy.compactMap(staying).first { return below.id }
        guard !olderToCome else { return nil }
        return rows[..<at].reversed().lazy.compactMap(staying).first?.id
    }
}
