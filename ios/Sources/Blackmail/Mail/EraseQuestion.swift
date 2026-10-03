import Foundation

/// What is asked before a Delete that cannot be taken back: one inside
/// Trash, from the reading pane or from Edit mode (B-062).
///
/// Delete everywhere else moves the letter to Trash, where he can find it
/// again for thirty days. Inside Trash it erases the letter at once, a
/// `\Deleted` and an EXPUNGE of it (`IMAPMailRepository.delete`). The
/// reading pane's Delete and Edit mode's both did that at the first tap,
/// with nothing asked, and `PRODUCT_SPEC.md`'s safeguards ask for
/// "Confirmation before permanently deleting from Trash."
///
/// Mail on the iPad asks before its Delete All in Trash and Junk, with the
/// same words in red; for a letter or a selection deleted there, nothing
/// found that describes it mentions a question. The spec asks for every
/// one, and this asks for every one, as Mail asks: Cancel, and the verb he
/// tapped in red. The sentence is Apple's own for a delete that skips the
/// bin, the Finder's "This item will be deleted immediately. You can't
/// undo this action." (as its users quote it, Apple Community thread
/// 251725582), with "message", Mail's word on screen, for "item".
///
/// Not in Spam. Delete there moves the letter to Trash, as Mail's does
/// from Junk, so it can be got back, and the spec asks only for Trash.
///
/// Apart from the controllers, which are UIKit and do not exist on the
/// machine the suite runs on, so the words and the rule are pinned on the
/// host; `EraseConfirmation` puts it up.
struct EraseQuestion: Equatable {
    let title: String
    let message: String

    /// The red button, which deletes.
    static let delete = "Delete"
    /// The other, which leaves everything as it was.
    static let cancel = "Cancel"

    /// Whether a Delete of a letter listed from a folder with `role` erases
    /// it rather than moving it to Trash: only inside Trash. The role is
    /// that of the letter's own folder, which for an All Mailboxes hit is
    /// not the list's: a hit from Trash is erased as a letter in Trash is.
    static func erases(fromFolderWithRole role: Mailbox.Role?) -> Bool {
        role == .trash
    }

    /// The question for a Delete of `letters`, each by the role of the
    /// folder it was listed from (`role`), or nil when none of them would
    /// be erased, which asks nothing, as before.
    ///
    /// The title counts every letter the Delete takes, a conversation's
    /// letters each, since that is what goes; the sentence says which of
    /// them cannot be got back, all of them unless an All Mailboxes search
    /// has mixed letters from Trash with others, which go to Trash.
    static func before(deleting letters: [MessageSummary],
                       role: (String) -> Mailbox.Role?) -> EraseQuestion? {
        let erased = letters.filter { erases(fromFolderWithRole: role($0.mailboxID)) }.count
        guard erased > 0 else { return nil }
        let title = letters.count == 1 ? "Delete Message?" : "Delete \(letters.count) Messages?"
        let which: String
        if erased == letters.count {
            which = letters.count == 1 ? "This message" : "These messages"
        } else {
            which = erased == 1 ? "1 of them is in the Trash and"
                                : "\(erased) of them are in the Trash and"
        }
        return EraseQuestion(title: title,
                             message: which + " will be deleted immediately. "
                                 + "You can't undo this action.")
    }
}
