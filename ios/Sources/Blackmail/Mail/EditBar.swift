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
/// here it was "Done" (B-133). Not copied: Mail's "Archive" in the Trash's
/// place, on an account whose Move Discarded Messages Into says Archive.
/// A Delete here always goes to the Trash, and his iPad's setting has not
/// been read.
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
    static func deleteTitle(inFolderWithRole role: Mailbox.Role?) -> String {
        EraseQuestion.erases(fromFolderWithRole: role) ? "Delete" : "Trash"
    }
}
