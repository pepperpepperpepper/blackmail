import Foundation

/// The message list's Edit mode in Mail's words (B-144): the button that
/// begins it and ends it, and the third button of the bar it brings, Mark,
/// Move and this one.
///
/// Out of `MessageListViewController` for the reason `EraseQuestion` is: the
/// controller is UIKit, and the suite runs where there is none.
///
/// Mail, US English, iPadOS 18: the bar says "Trash" in every mailbox but
/// the Trash, where the same button erases and says "Delete". In the
/// bar's own colour, as Mark and Move are; here it was "Delete" in red
/// everywhere. Mail ends its Edit mode with "Cancel", the guides to it say;
/// here it was "Done" (B-133). Mail's "Archive" in the Trash's place, on an
/// account whose Move Discarded Messages Into says Archive Mailbox, since
/// B-167: a move into All Mail, as a drag's Archive (`discarding`).
enum EditBar {
    /// The button that begins Edit mode, D-008's word, kept.
    static let edit = "Edit"
    /// The same button while Edit mode is on, which ends it, his ticks let
    /// go and nothing done, as Done did.
    static let cancel = "Cancel"

    /// The third button in a list of the folder with `role`: "Delete" in
    /// the Trash, where it erases the letters, after `EraseQuestion`'s
    /// question, and "Trash" anywhere else, the ruling's word. By the
    /// list's folder, as Mail's bar is: an All Mailboxes search keeps its
    /// folder's word, and `EraseQuestion` says which of its hits would be
    /// erased.
    ///
    /// "Trash" is not always where the tap puts them. In the Outbox, and
    /// for the letters kept on the iPad at the top of Drafts, it takes
    /// them off the iPad (`LocalDrafts.delete`), with nothing asked and no
    /// copy in the Trash, where the word was "Delete" in red. Left to the
    /// owner (TODO, "Blocked on the owner").
    ///
    /// "Archive" where the account discards into the Archive and the
    /// folder's letters can be archived, `canArchive`: there is an All Mail
    /// and the list is not it; never in Drafts or the Outbox (B-167). By
    /// the rule a drag on a row goes by
    /// (`SwipeOptions.discard(fromFolderWithRole:canArchive:)`), so the bar
    /// and a drag on a row of the same list say the same.
    static func deleteTitle(inFolderWithRole role: Mailbox.Role?, canArchive: Bool = false,
                            options: SwipeOptions = .his) -> String {
        options.discard(fromFolderWithRole: role, canArchive: canArchive).title
    }

    /// What the third button's tap does to each of `letters` (B-167): those
    /// it archives, moved into `allMail`, and the rest, which go by Delete,
    /// to the Trash, or erased inside it after `EraseQuestion`'s question.
    /// Each by the folder it was listed from (`role`), as a drag on its row
    /// would discard it: in an All Mailboxes search, under the list's
    /// "Archive", a hit from All Mail goes to the Trash, as its row's drag
    /// does, and one from Trash is erased. With the factory's Deleted
    /// Mailbox, or no All Mail, every letter goes by Delete, as before.
    static func discarding(_ letters: [MessageSummary], role: (String) -> Mailbox.Role?,
                           allMail: Mailbox?, options: SwipeOptions = .his)
        -> (archived: [MessageSummary], deleted: [MessageSummary]) {
        var archived: [MessageSummary] = []
        var deleted: [MessageSummary] = []
        for letter in letters {
            if options.archive(fromFolderWithRole: role(letter.mailboxID), into: allMail) != nil {
                archived.append(letter)
            } else {
                deleted.append(letter)
            }
        }
        return (archived, deleted)
    }

    /// What the third button asks before its tap, if it erases any of
    /// `letters` (`EraseQuestion`), of the letters it deletes alone: those
    /// it archives (`discarding`) are neither counted nor called deleted.
    /// Under "Archive" in an All Mailboxes search whose ticked hits include
    /// one from Trash, the question counts the letters going to the Trash
    /// or erased, not the ones going to All Mail. With the factory's
    /// Deleted Mailbox, or no All Mail, every letter, as before.
    static func question(before letters: [MessageSummary], role: (String) -> Mailbox.Role?,
                         allMail: Mailbox?, options: SwipeOptions = .his) -> EraseQuestion? {
        EraseQuestion.before(deleting: discarding(letters, role: role, allMail: allMail,
                                                  options: options).deleted,
                             role: role)
    }

    /// What Ask Before Deleting's sheet says the third button does
    /// (`DiscardQuestion`, B-168), by what its tap does to the letters
    /// (`discarding`), not by its word: "Archive 3 Messages" where it
    /// archives every one, as Mail asks before an Archive with its own
    /// words (`ARCHIVE_FORMAT`), and "Trash 3 Messages" where any goes to
    /// the Trash. Under "Archive", an All Mailboxes search's hits from All
    /// Mail go to the Trash (`archive(fromFolderWithRole: .archive)` is
    /// none), and the sheet said "Archive 2 Messages" before it trashed
    /// them (int19).
    static func discardVerb(for split: (archived: [MessageSummary], deleted: [MessageSummary]))
        -> DiscardQuestion.Verb {
        split.deleted.isEmpty && !split.archived.isEmpty ? .archive : .trash
    }

    /// The two words, here and nowhere else: the bar's, a drag's button on
    /// a row (`RowSwipes`) and the name of the step Undo takes back
    /// (`UndoableMove`) say them from here. The third, "Archive", is a
    /// drag's (`RowSwipes.Action.archive`).
    static let trash = "Trash"
    static let delete = "Delete"

    // MARK: - As the ticks go (B-174)

    /// The list's title in Edit mode with `ticked` rows ticked, as Mail's
    /// (`MESSAGES_SELECTED_FORMAT`, "%1$lu Selected", one form for every
    /// count): "1 Selected", "3 Selected"; with none ticked, and out of
    /// Edit mode, the folder's name, `folder`. In the title's place: in
    /// two panes UIKit cuts it to "1 Sel…" beside Cancel, as Mail's was
    /// seen. Counted by the rows ticked, a conversation's row once; what
    /// Mail counts for a conversation was not seen.
    static func title(ticked: Int, folder: String) -> String {
        ticked > 0 ? "\(ticked) Selected" : folder
    }

    /// Whether Mark, Move and the third button can be tapped: with a row
    /// ticked, as Mail's, which are grey with none (r6 comparison C-03,
    /// rgb(65,65,65)) and blue from the first tick. Select All always can.
    static func acts(ticked: Int) -> Bool { ticked > 0 }

    /// Whether Edit can be tapped: not in a folder with no rows, as Mail's
    /// Edit is grey in an empty Junk (C-03); Cancel always.
    static func canEdit(rows: Int, editing: Bool) -> Bool { editing || rows > 0 }

    /// Whether Edit mode ends by itself, as Cancel ends it: its last row
    /// has gone from the list.
    static func ends(rows: Int, editing: Bool) -> Bool { editing && rows == 0 }

    /// Whether the reading pane is dimmed: in Edit mode with nothing ticked,
    /// as Mail greys the letter it shows and the buttons above it (C-03).
    /// With a row ticked its letter is in the pane, in full colour
    /// (`EditPane`).
    static func dimsPane(editing: Bool, ticked: Int) -> Bool { editing && ticked == 0 }
}
