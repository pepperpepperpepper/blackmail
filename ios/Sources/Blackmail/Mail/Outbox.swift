import Foundation

/// The Outbox (B-052): letters he sent that have not reached the server,
/// kept on the iPad with the drafts (`LocalDrafts`), listed in a mailbox of
/// their own while there are any, and sent by themselves once the server
/// can be reached.
///
/// Mail's, as Apple documents it: a letter that could not be sent "goes to
/// your Outbox", which he finds in the list of mailboxes, and "If you don't
/// see an Outbox, then your email was sent" (Apple Support, "If you can't
/// send email on your iPhone or iPad"). Mail sends it by itself once there
/// is a connection, usually (OS X Daily, "How to View and Re-Send an
/// 'Unsent Message' in Mail for iOS").
///
/// What this file holds is what can be said without UIKit: which failures
/// put a letter in the Outbox, the words he reads, and the Outbox's rows.
enum Outbox {

    /// Thrown by the composer's send (`LocalDrafts.send`) when the letter
    /// did not go and waits in the Outbox: the sheet closes and says so.
    struct Waiting: Error {}

    /// Sent Mail could not say whether an earlier attempt at the letter
    /// reached Gmail: the server refused the search, the connection went
    /// while it ran, or it found nothing too soon after the attempt was cut
    /// off to count (`settling`). Nothing is sent, and the letter waits for
    /// the next pass to ask again (`LocalDrafts.deliver`).
    struct Unsettled: Error {}

    /// The server lists neither Sent Mail nor All Mail, so whether an
    /// earlier attempt reached Gmail can never be asked: "Show in IMAP" off
    /// for both in Gmail's settings. The letter's own failure, said on its
    /// row and in the sheet as "Message was not sent.", and never sent
    /// blind (`MailRepository.sentMail(holds:)`).
    struct NoSentMail: Error {}

    /// How long after an attempt was cut off, its DATA gone and no 250 back,
    /// Sent Mail's not having it is not yet taken to mean Gmail never had
    /// it: ten minutes. A server may take that long over a letter after its
    /// terminating dot (RFC 5321 §4.5.3.2.6, which is why the wait for the
    /// 250 itself is as long, `TLSConnection`), and Gmail files a letter in
    /// Sent Mail only once it has taken it. A pass that ran a moment after
    /// the cut, on the connection coming back or the Outbox opened, found
    /// nothing, and sent it again. Found, it went, whenever it is asked.
    static let settling: TimeInterval = 10 * 60

    /// Whether a Send that failed with `error` leaves the letter waiting in
    /// the Outbox rather than in the sheet with the reason.
    ///
    /// Waits, since nothing was said about the letter and it may go later
    /// as it is:
    /// - `MailError.cannotConnect`: no connection, the submission server not
    ///   reached; also a forward's files or the Sent Mail search failing for
    ///   want of the IMAP connection.
    /// - `MailError.connectionLost`: the connection went, or stopped
    ///   answering, before the server's verdict on the letter, including
    ///   when iOS has taken back the time it gave and suspended the app mid
    ///   send, which a write or a read deadline then ends as he comes back.
    /// - `MailError.refusedForNow`: the server said "not now", a 4yz reply
    ///   at any step, and nothing was delivered.
    /// - `MailError.signInRefused`: IMAP's LOGIN refused for a reason that
    ///   is not the password, "[UNAVAILABLE]" or too many connections, as a
    ///   forward's files or the Sent Mail search wanted the connection. It
    ///   read as no connection until 2026-09-30, and waits as one still:
    ///   it says nothing about the submission server, and Google lets go of
    ///   it by itself.
    /// - `Unsettled`: an earlier attempt may have gone, and could not be
    ///   looked for.
    ///
    /// Stays in the sheet, as every failure did before (B-044), since
    /// sending it again as it is would fail again:
    /// - `MailError.passwordNeedsUpdating`: the account. The same password
    ///   would be refused at every pass, and each refusal counts toward
    ///   Google's lockout; Settings is where it is mended.
    /// - `MailError.sendingSignInRefused`: the account too, the submission
    ///   server's 534, a sign-in on the web wanted first. The same, as it
    ///   was when it counted as the password's (`MailError.refusesSending`).
    /// - `MailError.messageTooLarge`: the letter itself; something has to
    ///   come off it.
    /// - `MailError.notSent`: every other refusal the server made with a
    ///   code, a 5yz, which is about this letter or this sender: every
    ///   recipient refused, the letter refused after DATA, a sender refused,
    ///   a letter addressed to nobody. The server was reached and said
    ///   never.
    /// - `MailError.attachmentFailed`: a forward's file gone from Gmail, or
    ///   one that could not be read, or its folder renumbered or gone since.
    ///   He can take it off the letter.
    /// - `MailError.attachmentsMissing`: a file or quoted picture that names
    ///   its original by Gmail's id, and that letter is neither where it
    ///   was named nor in All Mail. The same.
    /// - `NoSentMail`, and anything else, a photo's file that could not be
    ///   read: shown as "Message was not sent." as it always was.
    static func waits(after error: Error) -> Bool {
        if error is Unsettled { return true }
        switch error as? MailError {
        case .cannotConnect?, .connectionLost?, .refusedForNow?, .signInRefused?:
            return true
        case .passwordNeedsUpdating?, .sendingSignInRefused?, .messageTooLarge?, .notSent?,
             .attachmentFailed?, .attachmentsMissing?, nil:
            return false
        }
    }

    /// What he reads as the sheet closes on a letter that waits.
    ///
    /// Mail says "A copy has been placed in your Outbox." over the reason
    /// the connection failed, under the title "Cannot Send Mail", as its
    /// users quote it; that is the one wording of Mail's found for this.
    /// Its "a copy" and the server's name would tell him nothing, so this is
    /// the app's own: where the letter is, and what will happen to it.
    ///
    /// "and Blackmail is open", because nothing sends it while the app is
    /// not in front: every pass is the app's own doing, at a page, on coming
    /// back, as he leaves, at the watch's check (`LocalDrafts.uploadWaiting`),
    /// and there is no background task. Said as "when the iPad is
    /// connected", a Wi-Fi that came back while the app was put away left
    /// the letter unsent for as long as it stayed put away, with nothing he
    /// had been told to do about it.
    static let notice = "Message is in the Outbox. It will be sent when the iPad is connected "
        + "and Blackmail is open."

    /// The first line of the row of a letter no pass will send: an attempt
    /// at it was cut off after its DATA before a password was saved, so
    /// Gmail may have it, and Sent Mail, which would say, may now be
    /// another mailbox's (`LocalDraftStore.unsettledBeforeASave`); or one
    /// with such an attempt that the pass has given up on (B-057,
    /// `LocalDrafts.outboxRows`). Not "Message was not sent.", which may be
    /// untrue, and would have him send it again for that reason. What he
    /// does about it is his: tapped and sent, it goes.
    static let mayHaveGone = "May already have been sent."

    /// The first line of the row of a letter the pass has given up on, after
    /// tries at it that the app never lived through (B-057,
    /// `LocalDrafts.unfinishedTries`): it goes only when he sends it. What
    /// is wrong with it cannot be known on the iPad, so this says what will
    /// not happen and what to do, in two plain sentences. The app's own:
    /// Mail has no such state to copy the words of. Never for one with an
    /// attempt whose DATA went, which may have been delivered and says so
    /// (`mayHaveGone`).
    static let notSentByItself = "Not sent automatically. Open it and tap Send."

    /// The line under a list while letters wait: Mail's "1 Unsent Message",
    /// as its status bar is quoted and pictured (OS X Daily, 2014 and 2016).
    /// The plural is guessed. Nil when nothing waits.
    static func unsent(_ count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case 1: return "1 Unsent Message"
        default: return "\(count) Unsent Messages"
        }
    }

    /// The mailbox the sidebar lists while letters wait, with how many as
    /// its count. Its id is no IMAP name the app would ever be handed, so
    /// a folder of his own called "Outbox" is never taken for it.
    static func mailbox(holding count: Int) -> Mailbox {
        Mailbox(id: mailboxID, name: "Outbox", unreadCount: count, role: .outbox)
    }

    static let mailboxID = "blackmail:outbox"

    /// Whom a letter in the Outbox is to, as its row says it: each
    /// recipient's name where he gave one, or the address, To first.
    static func addressees(of draft: Draft) -> String {
        let names = Submission.recipients(of: draft).map { recipient -> String in
            let bare = MailFormat.bareAddress(recipient)
            guard let open = recipient.lastIndex(of: "<") else { return bare }
            let name = recipient[..<open]
                .trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            return name.isEmpty ? bare : name
        }
        return names.isEmpty ? "No Recipients" : names.joined(separator: ", ")
    }
}

extension LocalDraft {

    /// Its row in the Outbox: whom it is to and its subject, and under them,
    /// while it goes, "Sending…", or `reason`, why it has not gone
    /// (`LocalDrafts.outboxRows`), then its words. Its id is the one a row
    /// in Drafts gives a kept letter, so opening and deleting it go by
    /// `LocalDraft.key(ofRow:)` as there.
    func outboxRow(sending: Bool, saying reason: String?) -> MessageSummary {
        let text = PreviewText.fromPlainText(draft.body)
        let first = sending ? "Sending…" : reason
        let preview = [first, text.isEmpty ? nil : text].compactMap { $0 }.joined(separator: "\n")
        let row = self.row(in: Outbox.mailboxID, from: "")
        return MessageSummary(id: row.id, mailboxID: Outbox.mailboxID,
                              sender: Outbox.addressees(of: draft),
                              subject: draft.subject, preview: preview, date: keptAt,
                              isRead: true, isFlagged: false,
                              hasAttachment: !draft.attachments.isEmpty, threadID: row.id)
    }
}
