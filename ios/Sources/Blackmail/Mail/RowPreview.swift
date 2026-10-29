import Foundation

/// The words of a message-list row that Mail writes in place of what the
/// letter lacks (B-182): "No Subject" for a letter with no subject, and
/// "Attachment: " and a file's name under it for a letter drawn with no
/// words that carries files.
///
/// Out of `MessageCell` and the list's controller for the reason `RowArrow`
/// is: both are UIKit and do not exist on the machine the suite runs on.
///
/// Seen in the comparison with Mail of 2026-10-29 (round r6-n-compare,
/// Mail 16.5.1 on the test iPad). C-3a: Mail's rows of the two letters
/// that are only a picture, one inline by `cid:` and one attached, said
/// "Attachment: h-photo.jpg" and "Attachment: IMG_0131.jpg" in the
/// preview's place, under the subject line; Blackmail's said nothing. C-5a, in passing: Mail's rows
/// with no subject said "No Subject" in its grey, rgb(143, 143, 150);
/// Blackmail's "(no subject)" in white.
enum RowPreview {

    /// Mail's words for a row whose letter has no subject.
    static let noSubject = "No Subject"

    /// What a row's subject line says of `subject`: the subject, or
    /// "No Subject" where it has none.
    static func subject(_ subject: String) -> String {
        subject.isEmpty ? noSubject : subject
    }

    /// Whether the subject line is drawn in the row's grey, as Mail draws
    /// its "No Subject": where the letter has none. A subject is white.
    static func subjectIsGrey(_ subject: String) -> Bool { subject.isEmpty }

    /// What a row's two grey lines say of `letter`, the one whose preview
    /// the row shows (`MessageThread.newest`): its preview where it has
    /// words; where it was drawn with no words (`drawnWithNoWords`,
    /// `ListLetters.drawnWithNoWords`) and carries a file with a name,
    /// "Attachment: " and the first such file's name, the files in the
    /// order the letter's structure lists them, a picture its body shows
    /// by `cid:` among them (`MessageSummary.firstFileName`, or, for a row
    /// not listed from the server, its `attachments`); nothing otherwise.
    /// A row whose preview has not come yet shows nothing, as it did: its
    /// letter may yet have words.
    ///
    /// Mail was seen with one file to a letter; a letter of two or more,
    /// named by its first here, was not seen.
    static func preview(of letter: MessageSummary, drawnWithNoWords: Bool) -> String {
        guard letter.preview.isEmpty, drawnWithNoWords,
              let name = letter.firstFileName
                ?? letter.attachments.first(where: { !$0.filename.isEmpty })?.filename
        else { return letter.preview }
        return "Attachment: \(name)"
    }
}
