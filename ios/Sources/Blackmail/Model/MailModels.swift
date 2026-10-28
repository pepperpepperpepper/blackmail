import Foundation

/// Provider-neutral domain types, taken from `spec/starter` and corrected.
///
/// Nothing here knows what IMAP is. That separation is the spec's own
/// requirement and it is what lets the mock repository and a real one be
/// swapped without the interface noticing.

struct Mailbox: Identifiable, Hashable {
    let id: String
    var name: String
    var unreadCount: Int
    var role: Role?
    /// Nesting depth: how many steps in the row is drawn. Gmail's `[Gmail]/…`
    /// children sit at 1, inside "[Gmail]", which is not drawn. A label
    /// inside another sits one step further in than the label it is drawn
    /// under. Everything else sits at 0, a label inside folders none of
    /// which is drawn included, and a folder inside the Inbox, which is
    /// drawn among the labels (`FolderTree`, B-116). Drives the indent and
    /// the separator inset.
    var depth: Int = 0

    enum Role: String, Codable {
        case inbox, sent, drafts, trash, archive, junk
        /// The letters Send could not take to the server, kept on the iPad
        /// (`Outbox`, B-052). Never a folder on the server: nothing LIST
        /// says maps to it.
        case outbox
    }

    /// What the screens call the folder: its own name, except the inbox,
    /// which is "Inbox" whatever the server calls it, and the folders Gmail
    /// calls "Sent Mail" and "Spam", which are "Sent" and "Junk", Mail's
    /// words for them.
    ///
    /// IMAP spells the inbox "INBOX", and the sidebar and the list's title
    /// used to show it that way, while the list opened at launch, before
    /// the server has been heard from, said "Inbox" (B-047). Mail says
    /// "Inbox" everywhere, and he knows Mail. Keyed on the role rather than
    /// on the spelling, so it covers a server that writes it "Inbox" or
    /// "inbox" too. `id` and `name` stay the server's: `id` is what goes on
    /// the wire.
    ///
    /// Sent and Junk the same way (B-144): Mail on the iPad shows a Gmail
    /// account's Sent Mail as "Sent" and its Spam as "Junk". By the role
    /// LIST gives, never by the name, so a label of his called "Sent Mail"
    /// or "Spam" keeps its name. All Mail, Drafts and Trash keep Gmail's,
    /// which are Mail's too, as far as was found.
    var displayName: String {
        switch role {
        case .inbox: return "Inbox"
        case .sent: return "Sent"
        case .junk: return "Junk"
        default: return name
        }
    }

    /// What VoiceOver reads for the folder's row in the sidebar: the name
    /// the row shows, and the unread count the row shows beside it as a
    /// bare number. The Outbox's number is of letters waiting to go.
    var accessibilityLabel: String {
        if role == .outbox, let waiting = Outbox.unsent(unreadCount) {
            return "\(displayName), \(waiting)"
        }
        return unreadCount > 0 ? "\(displayName), \(unreadCount) unread" : displayName
    }

    /// The Inbox before LIST has named it: what the message list opens on
    /// at launch, and what opening the Inbox falls back to while the folder
    /// pane has nothing listed. Its id is the role word, which
    /// `IMAPMailRepository` resolves and `firstIndex(matchingMailboxID:)`
    /// matches against the real "INBOX".
    static let inboxBeforeListing = Mailbox(id: "inbox", name: "Inbox", unreadCount: 0,
                                            role: .inbox)
}

struct MessageSummary: Identifiable, Hashable {
    let id: String
    let mailboxID: String
    var sender: String
    var subject: String
    var preview: String
    var date: Date
    var isRead: Bool
    var isFlagged: Bool
    /// The letter has been answered (`\Answered`) or forwarded
    /// (`$Forwarded`), as the FLAGS the row is fetched with say: set only
    /// by a mail program on IMAP that writes the mark when its answer
    /// goes, as Apple Mail is taken to (B-102's device step 0). Gmail's own
    /// pages and its app write neither, so a letter answered there has no
    /// mark. The row shows Mail's grey arrow for it (`RowArrow`, B-102).
    /// False where it is not known: a row kept on the iPad by a build
    /// before rows carried it (`MailShelf`), a letter kept on the iPad,
    /// the Outbox's.
    var isAnswered: Bool = false
    var isForwarded: Bool = false
    var hasAttachment: Bool = false
    /// Gmail's thread id, when the server offered one. Messages sharing it
    /// are one conversation. Nil on a server without the extension, where
    /// the subject is the fallback — see `MessageThread`.
    var threadID: String?
    /// Gmail's own id for the letter (X-GM-MSGID), when the server offered
    /// one. Nil on a server without the extension.
    ///
    /// The letter's rather than the folder's: the same letter listed from
    /// the Inbox and from All Mail has two UIDs and this one id. The copy
    /// of his mail kept on the iPad is keyed on it (D-016), because every
    /// Gmail Inbox reports UIDVALIDITY 1 and a folder, a UIDVALIDITY and a
    /// UID alone cannot tell two mailboxes apart: `MailShelf` throws the
    /// copy away when a listing's rows carry other ids under the kept UIDs,
    /// and patches a read mark or a flag on every kept row of the letter;
    /// the repository vouches for a kept row by it before a write or the
    /// letter's FETCH; and the list carries a preview, a read mark or a
    /// flag across to a fetched row only when the ids do not disagree
    /// (`ListEdit.sameLetter`), and takes a row the server has disowned off
    /// only while it still carries the kept one (`PaneActions`).
    var gmailMessageID: UInt64? = nil
    /// Every folder whose unread count this message contributes to.
    ///
    /// More than one on Gmail, where a folder is a label and `\Seen` belongs
    /// to the message rather than to any one label: an inbox letter is
    /// normally counted in Inbox, All Mail and often Important. Reading it
    /// drops all of them on the server, so the sidebar has to drop all of
    /// them too.
    ///
    /// Empty when the server has no label extension, in which case the
    /// caller falls back to the folder the message was listed from — which
    /// is exactly right for a one-message-one-folder server.
    var countedFolderIDs: [String] = []
    /// The files the letter carries, as the reading pane draws them in its
    /// body, worked out from the BODYSTRUCTURE the row is fetched with, so
    /// before a byte of the letter is downloaded
    /// (`MIMEDecoder.listedAttachments(in:)`). Empty when it has none, or
    /// the server described no structure.
    ///
    /// Carried so the header could list them from the tap (B-042). It has
    /// listed none since B-170: every file is drawn in the letter's body,
    /// as Mail draws it, and the body comes with the letter.
    var attachments: [Attachment] = []
    /// Whom the letter was sent to, as the ENVELOPE the row is fetched with
    /// names them, `Name <address>` or the address alone, as `cc` is.
    /// Empty for a letter to nobody, as a draft begun and put aside is.
    ///
    /// Carried for the row's own top line in Sent Mail, Drafts and the
    /// Outbox, which names whom the letter is to, as Mail's does, and not
    /// him (`RowNames`, B-060). Every letter there is his, so his own name
    /// on every row said nothing; he could tell his letters apart only by
    /// their subjects. And for the reading pane's header, which has its To
    /// line from the tap since B-127, as it has its Cc
    /// (`Message.heading(for:)`).
    ///
    /// Nil where it is not known: a row kept on the iPad by a build before
    /// rows carried it (`MailShelf`), and a row the server gave no ENVELOPE
    /// for. Such a row names its sender, as every row did, until the folder
    /// is next listed, rather than say "No Recipients" of a letter that had
    /// some.
    var to: [String]? = nil
    /// Whom the letter was copied to, as the ENVELOPE the row is fetched
    /// with names them: `Name <address>`, or the address where there is no
    /// name, which the reading pane's header names as it names the Cc
    /// header's (`MailFormat.recipientName`). Empty when it has none.
    ///
    /// Carried so the header has its Cc line from the tap, for the reason
    /// `attachments` is: it used to gain it only when the letter came, and
    /// push a conversation's stack down a line under him (B-042, B-055).
    var cc: [String] = []
    /// Whom the letter was blind-copied to, from the same ENVELOPE. Only a
    /// letter of his own has any: a draft carries its Bcc (`RFC5322Builder`
    /// writes it there and nowhere else), and Gmail's copy in Sent Mail may
    /// (not yet seen); a letter he was sent never shows one. For the top
    /// line in Drafts and Sent Mail, so a letter to Bcc alone names the
    /// people it is to rather than nobody.
    var bcc: [String] = []
    /// When the server took the letter, its INTERNALDATE, which the row is
    /// fetched with already. Gmail keeps it through a MOVE: a letter put in
    /// Trash keeps the time it first came. Not the letter's Date, which
    /// its sender's clock wrote (`date`).
    ///
    /// Carried so a conversation's letters go in the order they came
    /// (`MessageThread.group`, B-084). The folder's UIDs are the order they
    /// were put in it, which is not that order for letters moved in out of
    /// turn: a conversation deleted a letter at a time, the newest first,
    /// as Edit mode's Delete used to, or a reply deleted before the letter
    /// it answers. Since B-178 the list itself goes by it
    /// (`ArrivalOrder`, `isListed(above:)`).
    ///
    /// Nil where it is not known: a row kept on the iPad by a build before
    /// rows carried it (`MailShelf`), a letter kept on the iPad, and a row
    /// the server gave no INTERNALDATE for. A conversation with such a row
    /// in it keeps the folder's order, as every conversation did.
    var arrived: Date? = nil

    /// The date the row shows and the list goes by: when the letter
    /// arrived (`arrived`), or, where that is not known, its Date (`date`),
    /// as a row kept by a build before rows carried it has.
    ///
    /// Mail's row shows the date received, the one its list is in order
    /// of. Seen on the test iPad, Mail 16.5.1, 2026-10-28 (B-178): a letter
    /// dated 1 March 2024 that arrived that morning read "4:12 AM" in Mail
    /// and "3/1/24" in Blackmail, and one dated that morning that arrived
    /// twenty days before read "10/8/26" in Mail and "3:00 AM" in
    /// Blackmail. A date jump goes by it too (`IMAPDate.jump`), so the row
    /// it lands on reads the day he picked. The reading pane's header and
    /// the stack's lines show it too, as Mail's header does
    /// (`Message.headerDate`, the second round), and Print, a reply's "On
    /// ... wrote:" and Forward go by it, as Mail's print and reply do
    /// (`Message.headerDate`, the third round). The letter's own Date
    /// (`date`) is kept, and they use it only where no arrival is known.
    var listDate: Date { arrived ?? date }

    /// Whether this row goes above `other` in a folder's list, which runs
    /// the newest first by when each letter arrived, its INTERNALDATE
    /// (`arrived`), as Mail's list does (`ArrivalOrder`, B-178): arrived
    /// later, or in the same second with the higher UID in the same folder.
    /// A row that does not say when it arrived goes by its `date`
    /// (`listDate`).
    func isListed(above other: MessageSummary) -> Bool {
        let mine = listDate
        let theirs = other.listDate
        if mine != theirs { return mine > theirs }
        let a = id.split(separator: "/", omittingEmptySubsequences: false)
        let b = other.id.split(separator: "/", omittingEmptySubsequences: false)
        guard a.count == 2, b.count == 2, a[0] == b[0], mailboxID == other.mailboxID,
              let x = UInt32(a[1]), let y = UInt32(b[1]) else { return false }
        return x > y
    }

    /// The same letter under another id in the same folder: one its Undo
    /// has moved back, which Gmail gives a new UID (B-157). Everything else
    /// as it was.
    func renamed(_ id: String) -> MessageSummary {
        MessageSummary(id: id, mailboxID: mailboxID, sender: sender, subject: subject,
                       preview: preview, date: date, isRead: isRead, isFlagged: isFlagged,
                       isAnswered: isAnswered, isForwarded: isForwarded,
                       hasAttachment: hasAttachment, threadID: threadID,
                       gmailMessageID: gmailMessageID, countedFolderIDs: countedFolderIDs,
                       attachments: attachments, to: to, cc: cc, bcc: bcc, arrived: arrived)
    }
}

struct Message: Identifiable {
    let id: String
    let mailboxID: String
    let sender: String
    let senderAddress: String
    let to: [String]
    let cc: [String]
    /// Only ever populated for a message read back out of DRAFTS. A Bcc
    /// header does not survive delivery, by definition, so it is empty on
    /// anything he has received.
    var bcc: [String] = []
    /// The letter's Reply-To, an entry per address as `to` and `cc` have
    /// them, empty when it has none: where its sender asks for answers to
    /// go, which is where Reply sends them (`ReplyAddressing`, B-061). From
    /// the letter's own header, as `to` and `cc` are, rather than the
    /// ENVELOPE's, which a server fills with the From when there is none
    /// and so cannot say whether the letter had one.
    var replyTo: [String] = []
    /// The letter's From, an entry per address as `to` and `cc` have them:
    /// one for nearly every letter, and one for each of its authors for a
    /// letter written by several, `jane@example.com, sam@example.org`, all
    /// of whom a Reply goes to (`ReplyAddressing`, B-061). `sender` is the
    /// whole header decoded, which the pane shows; it cannot be split
    /// again once decoded, since a name whose comma came out of an encoded
    /// word would split with it. Empty for a letter not read from a
    /// header, and Reply then takes `sender` as one.
    var from: [String] = []
    let subject: String
    let date: Date
    let textBody: String?
    let htmlBody: String?
    let attachments: [Attachment]

    /// The RFC 5322 `Message-ID` header, which is what a reply must quote to
    /// thread. Emphatically NOT `id` — that is this app's own
    /// "<uidvalidity>/<uid>" handle and means nothing to any other client.
    var messageID: String?
    /// The letter's own `In-Reply-To`, as the header has it: the
    /// Message-ID of the letter it answers. Read for a draft, whose
    /// In-Reply-To names the letter it is a reply to, so that a reply
    /// finished from Drafts answers that letter still (`Draft.reopening`,
    /// B-064). Raw, as `messageID` is.
    var inReplyTo: String?
    /// The parent's own `References`, so a reply extends the ancestry
    /// instead of starting it over from one hop. A draft's, read back from
    /// Drafts, is the ancestry its reply goes with, its parent last.
    var references: String?
    /// Gmail's id for the letter (X-GM-MSGID), when the server has named it
    /// in this launch: the row's own that it was opened by, once the server
    /// has said the UID holds that letter, or what the server named there.
    /// Nil on a server without Gmail's extension, and where nothing named
    /// it.
    ///
    /// What a forward, a reply or a reopened draft made from it carries
    /// beside every folder-and-UID it names (`DraftAttachment.Source`,
    /// `QuotedOriginal.Picture`, `Draft.savedLetter`). Kept on the iPad
    /// (B-051) until a later launch, those names can be another letter's:
    /// Gmail gives every Inbox UIDVALIDITY 1, and a password saved in
    /// Settings can open another mailbox under the same address (B-033).
    var gmailMessageID: UInt64? = nil
    /// True when the body the pane shows, `htmlBody` when there is one and
    /// `textBody` otherwise, is only the beginning of the letter's own: a
    /// letter too large to fetch whole, whose text or HTML is longer than
    /// the part of it fetched (`IMAPMailRepository.loadMessage`). The pane
    /// says so (`MailText.shortenedNotice`).
    var isShortened = false
    /// True when `textBody` is flowed text (RFC 3676, `format=flowed`), as
    /// Apple Mail sends plain text: every part of it says so
    /// (`MIMEDecoder.BodyPlan.textIsFlowed`). A plain letter's page counts
    /// how deep a line's quote is by it, as Mail does (`PlainQuotes`,
    /// B-147).
    var textIsFlowed = false
    /// True for a letter opened without its files, one too large to fetch
    /// whole (`IMAPMailRepository`'s `loadLetterInPartOnce`, B-054): each
    /// comes from the server alone, as the letter opens, its tile saying
    /// "Downloading", as Mail's does (`FilesAhead`, B-176), or, too large
    /// to come unasked, when he taps it, its tile saying "Tap to Download",
    /// as Mail's tile says of a file it has not downloaded (`BodyFiles`,
    /// B-170). A letter fetched whole has its files in hand, and its tiles
    /// say nothing of it.
    var filesLeftOnServer = false
    /// When the letter arrived, its INTERNALDATE, as its row in the list
    /// has it (`MessageSummary.arrived`), for the date the reading pane's
    /// header shows, a reply's "On ... wrote:", Forward's header and Print
    /// (`headerDate`, B-178). Given by the row (`Message.heading(for:)`,
    /// `arriving(as:)`), to every letter the pane holds and hands on; nil
    /// where the row does not say, a letter kept on the iPad with none,
    /// and on a letter as the server reads it until its row gives it.
    var arrived: Date? = nil
}

extension Message {
    /// The date the reading pane's header shows: when the letter arrived,
    /// or its Date where that is not known, as a letter kept on the iPad
    /// with no arrival has (B-178, the second round). Mail 16.5.1's
    /// header shows the arrival: on the test iPad on 2026-10-28 (round
    /// r6-k-fix) a letter dated 1 March 2024 that arrived that morning read
    /// "10:23 AM" there and "March 1, 2024 at 12:00 PM" in Blackmail, and
    /// one dated that morning that arrived on 8 October "10/8/26" there
    /// and "Today at 9:00 AM" here. Blackmail's words for it and their
    /// place under the subject are its own and are kept
    /// (`MailFormat.detailTimestamp`, D-008, D-025); only which date.
    ///
    /// A reply's "On ... wrote:" and Print go by it too, as Mail 16.5.1's
    /// do (B-178, the third round): on the test iPad on 2026-10-28 (round
    /// r6-l-fix) Mail printed "Date: Oct 28, 2026 at 2:15:14 PM" and
    /// wrote "On Oct 28, 2026, at 2:15 PM, ... wrote:" for the letter
    /// dated 1 March 2024 that arrived at 2:15 PM, and "Oct 8, 2026" for
    /// the one that arrived on 8 October. Forward's header goes by it as
    /// well, by the same rule: Mail's Forward was not looked at.
    var headerDate: Date { arrived ?? date }

    /// This letter with the arrival of `row`, its row in the list, for the
    /// header, Print, a reply and Forward (`headerDate`): the letter as the
    /// server reads it does not say when it arrived, and its row does. Unchanged when `row` is
    /// another letter's, or nil.
    func arriving(as row: MessageSummary?) -> Message {
        guard let row, row.id == id else { return self }
        var m = self
        m.arrived = row.arrived
        return m
    }

    /// The letter's files: every attachment but the pictures the body
    /// shows by `cid:`, which are not files to him. See
    /// `Attachment.isShownInBody`. The pane draws each in the letter's body
    /// (`BodyFiles`, B-170), where the header listed them until then, and
    /// a picture sent to be shown by `cid:` that the body shown does not
    /// show as well.
    var listedAttachments: [Attachment] { attachments.filter { !$0.isShownInBody } }

    /// The body to quote underneath a reply or forward.
    ///
    /// Falls back to a plain-text rendering of the HTML, because an
    /// HTML-only message has NO `textBody` at all. Without this, forwarding
    /// one produced a letter containing nothing but the "Forwarded message"
    /// header — verified on device, where a real receipt forwarded as an
    /// empty message while the same mail rendered perfectly in the pane
    /// behind the compose sheet. HTML-only is not an edge case; it is most
    /// transactional mail.
    var quotableText: String {
        if let textBody, !textBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return textBody
        }
        if let htmlBody { return HTMLText.plainText(from: htmlBody) }
        return ""
    }

    /// `quotableText`, an HTML letter's made from no more of its markup
    /// than it takes to have `limit` characters of words
    /// (`HTMLText.plainText(from:limit:)`, B-140), and whether more was
    /// left unread, when the text ends wherever the words passed `limit`.
    /// A text part is taken as it is, whatever its size. `read` is how
    /// many characters of the markup were read, nought for a text part:
    /// for a test, that Reply and Forward stop where the words they keep
    /// end.
    func quotableText(within limit: Int) -> (text: String, isCut: Bool, read: Int) {
        if let textBody, !textBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (textBody, false, 0)
        }
        guard let htmlBody else { return ("", false, 0) }
        let made = HTMLText.plainText(from: htmlBody, limit: limit)
        return (made.text, made.isCut, made.read)
    }

    /// What a reply or a forward quotes, as the composer is given it: the
    /// lines of `quotableText` that fit in `QuotedOriginal.largestWords`
    /// and `largestLines`, each after `prefix`, "> " for a reply; and under
    /// them, for a letter shown only in part (`isShortened`) or one whose
    /// words did not all fit (`isCut`), a blank line and the line the pane
    /// shows above a letter shown in part
    /// (`QuotedOriginal.shortenedEnding`), each after the prefix too.
    /// Whoever the quote goes to would otherwise take the beginning of the
    /// letter for the whole of it, and a forward would pass it on as such. Nothing more of the letter is fetched for it.
    ///
    /// At the end of the quote rather than above it, where the pane has it:
    /// these are words, not the sender's markup cut wherever the fetch
    /// stopped, and the line closes the quote as the letter's own last line
    /// would. The HTML twin draws it grey (`AppleMailHTML.letter`).
    ///
    /// Bounded since B-140. A Reply to a letter whose 2 MB HTML part was
    /// nearly all words put about 1.7 MB of them into the composer, whose
    /// body is a text view as tall as its words: the sheet never came, and
    /// the app took no touch for ten minutes until it was ended. No more
    /// of the markup is read than the words that fit need.
    ///
    /// `read`, how many characters of the markup were read for it, is for
    /// a test (`quotableText(within:)`).
    func quoted(eachLineAfter prefix: String = "")
        -> (text: String, isShortened: Bool, isCut: Bool, read: Int) {
        let limit = QuotedOriginal.largestWords
        let made = quotableText(within: limit)
        let cut = QuotedOriginal.cut(made.text, within: limit, lines: QuotedOriginal.largestLines,
                                     prefix: prefix.utf8.count, more: made.isCut)
        let shortened = isShortened || cut != nil
        let words = (cut ?? made.text) + (shortened ? QuotedOriginal.shortenedEnding : "")
        let text = prefix.isEmpty
            ? words : prefix + words.replacingOccurrences(of: "\n", with: "\n" + prefix)
        return (text, shortened, cut != nil, made.read)
    }
}

struct Attachment: Identifiable, Hashable {
    let id: String
    let filename: String
    let mimeType: String
    let size: Int64?

    /// The part's `Content-ID`, brackets stripped, when it has one.
    ///
    /// This is how an `<img src="cid:…">` in the body finds its bytes, and
    /// without it every inline image in every message rendered as a broken
    /// picture. Not a rare shape: 23 of 30 recent attachment-bearing
    /// messages in his own mailbox reference `cid:` from their HTML —
    /// screenshots, photographs, and the signature blocks of everyone who
    /// writes to him from Apple Mail.
    var contentID: String?

    /// True when the part is marked `Content-Disposition: inline`, and
    /// nothing more: the sender's word, kept as it came, on the iPad too
    /// (`MailShelf`). Most such parts are pictures the BODY references by
    /// `cid:`, but not all: Apple Mail on an iPhone or an iPad sends a PDF
    /// inline as well, with no `Content-ID` and no mention in its HTML. What
    /// the header leaves out is `isShownInBody`.
    ///
    /// Declared after `contentID` so the memberwise initializer keeps the
    /// argument order every existing call site uses.
    var isInline: Bool = false

    /// True for a picture the body shows by `cid:`: a part sent inline, a
    /// picture, with a `Content-ID`. It stays among the letter's parts (the
    /// reading pane needs it to resolve the reference) but the pane does
    /// not draw it as a file, which would put the signature's logo on
    /// every letter twice, as Mail does not; unless the body shown does not
    /// show it, a plain letter's say, when the pane draws it after the
    /// words, as Mail draws a picture its page does not name (`BodyFiles`,
    /// B-170).
    ///
    /// Every other part is a file, inline or not, and is drawn in the body
    /// (B-101, `BodyFiles` since B-170).
    /// It was `isInline` alone until 2026-10-22, which left out the PDFs
    /// Apple Mail sends inline: no row, and nothing that could open them,
    /// as the body does not show them. Mail lists them.
    var isShownInBody: Bool {
        isInline && mimeType.lowercased().hasPrefix("image/") && contentID != nil
    }
}

struct Draft {
    var to: [String] = []
    var cc: [String] = []
    var bcc: [String] = []
    var subject: String = ""
    var body: String = ""
    /// The parent's RFC 5322 `Message-ID`, set when this draft is a reply.
    ///
    /// This used to be handed `Message.id` — the internal
    /// "<uidvalidity>/<uid>" — which would have emitted
    /// `In-Reply-To: <1/9>`, a malformed header meaning nothing to anyone.
    /// It never got that far, because `send` did not read the field at all.
    ///
    /// A reply reopened from Drafts has the draft's own In-Reply-To here,
    /// which names the same parent (`reopening`, B-064).
    var inReplyTo: String?
    /// The parent's `References` header, carried so the reply extends the
    /// chain rather than restarting it. A reply reopened from Drafts has
    /// the draft's own, which ends with the parent already.
    var references: String?
    /// Files travelling with this message: the photos he attached, a
    /// forward's parts of its original, a reopened draft's own, and a
    /// reply's parts of its original once it goes to someone the original
    /// did not (`ReplyFiles`, B-107).
    var attachments: [DraftAttachment] = []

    /// The copy of this letter already saved in the Drafts folder, as
    /// "<uidvalidity>/<uid>", or nil for one that has never been saved.
    ///
    /// Without it a draft was a dead end. Saving appended a SECOND copy
    /// rather than replacing the first, nothing could reopen one to finish
    /// it, and sending left the half-written original sitting in Drafts
    /// forever. For a man of ninety whose main correspondence runs through
    /// this app, being interrupted mid-letter is not an edge case, and an
    /// unfinishable letter is a failure of the thing he mostly does here.
    var savedID: String?
    /// Gmail's id for the letter `savedID` names (X-GM-MSGID), nil when the
    /// server named none. The copy is removed only if the server shows that
    /// UID to hold this letter (`MailRepository.deleteDraft`): a letter
    /// kept on the iPad from an earlier launch names its copy by folder and
    /// UID, and in another mailbox under the same address, or a Drafts
    /// renumbered under the same UIDVALIDITY, that UID is another draft.
    var savedLetter: UInt64?
    /// The letter a reply or forward quotes, as it arrived, so the HTML
    /// twin can show it as it looked while he edits it as plain text. Nil
    /// for a new letter. See `QuotedOriginal` for when it is used.
    var quote: QuotedOriginal?
    /// The letter a reply answers or a forward passes on, marked on the
    /// server once this one has gone (`OriginalLetter`, B-152). Nil for a
    /// new letter, for a draft reopened from the server, and for an
    /// original the server named no Gmail id for.
    var original: OriginalLetter?
}

extension Array where Element == Mailbox {

    /// Finds a folder by an id that may be in either of the two spellings
    /// this app uses for the same thing.
    ///
    /// The folder pane holds real IMAP LIST names — "INBOX",
    /// "[Gmail]/Sent Mail". The message pane is opened at launch, before the
    /// server has been heard from, with the lowercase role word "inbox". An
    /// exact `==` between the two never matches.
    ///
    /// That is not hypothetical. `select(mailboxID:)` has been doing exactly
    /// that compare since the three-pane layout landed, so the Inbox row has
    /// never been highlighted at launch — measured on device, where the row
    /// background reads 12.8 against 51.1 for a genuinely selected row. The
    /// one question the third pane exists to answer by looking has been
    /// unanswered on the app's primary folder for the whole session, every
    /// session. It is invisible under `MockMailRepository`, whose ids are
    /// role words on both sides.
    ///
    /// In this order (B-116): the folder of exactly that name; then, for one
    /// of the app's own role words (`Mailbox.Role(word:)`), the folder
    /// playing the role; then a folder of that name in another case. The
    /// app's word "drafts" is Gmail's Drafts even beside a label "Drafts",
    /// as the repository resolves it; and a label "Drafts" not in this list
    /// is in no folder of it, never in Gmail's Drafts by its name.
    func firstIndex(matchingMailboxID id: String) -> Int? {
        if let exact = firstIndex(where: { $0.id == id }) { return exact }
        // A role word against a LIST name. Matching on the ROLE rather than
        // on spelling is what makes this work for "[Gmail]/Sent Mail" and
        // for an account whose folders are not in English.
        if let role = Mailbox.Role(word: id), let playing = firstIndex(where: { $0.role == role }) {
            return playing
        }
        return firstIndex { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }
}

extension Mailbox.Role {

    /// The role an id names by itself: one of this app's own role words,
    /// spelt as it spells them, in lowercase ("inbox", "drafts"), or INBOX
    /// in any spelling, the one name IMAP gives a role (RFC 3501). Never a
    /// folder's name from LIST: a label called "Drafts" is a label, and so
    /// is one spelt as the app's word wherever LIST names it
    /// (`IMAPMailRepository.serverName`). Roles come from LIST's flags
    /// (`IMAPMailboxListing.specialUse`, B-116).
    init?(word id: String) {
        if id.caseInsensitiveCompare("inbox") == .orderedSame {
            self = .inbox
        } else if let role = Mailbox.Role(rawValue: id) {
            self = role
        } else {
            return nil
        }
    }
}

extension Draft {

    /// The signature, as it appears at the top of a fresh compose window.
    ///
    /// Leading blank lines put the cursor above it, so he types his letter
    /// where he expects to and the sign-off is already waiting underneath.
    ///
    /// No `-- ` delimiter, deliberately, and this was a reversal.
    ///
    /// RFC 3676's sigdash is the textbook answer and it is not what Apple
    /// Mail does: Mail has never emitted one, on any platform, and Sam's own
    /// signature arrives with no delimiter above it in all 715 of his sent
    /// messages. Copying the textbook made every letter he sent open with a
    /// `--` line he had never typed and that appears in none of his mail.
    ///
    /// It is also not free. Some clients treat everything below a sigdash as
    /// hideable, so a signature as long as his — which carries the organisation's
    /// confidentiality notice inside it — can arrive collapsed to nothing.
    /// A signature the recipient cannot see is worse than one their client
    /// declines to trim from a reply.
    ///
    /// A signature the owner has pasted in WITH its own delimiter keeps it;
    /// that is his text and not ours to edit.
    static func signatureBlock(_ signature: String) -> String {
        let trimmed = signature.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "\n\n" + trimmed
    }

    /// A blank letter, with his sign-off already in it.
    static func blank(signature: String) -> Draft {
        var draft = Draft()
        draft.body = "\n" + signatureBlock(signature)
        return draft
    }

    /// Whether the composer opens with its Cc and Bcc rows showing: when
    /// the letter arrives with anyone in either. Those rows are otherwise
    /// folded into the "Cc/Bcc" row, and an address in a hidden row still
    /// gets the letter.
    var showsCcAndBcc: Bool {
        (cc + bcc).contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The draft a Reply or Reply All starts from, with only `myAddress`
    /// known to be his. The app's own Reply knows his login as well
    /// (`OwnAddresses(account:)`).
    static func replying(to m: Message, all: Bool, myAddress: String?,
                         signature: String = "") -> Draft {
        replying(to: m, all: all, mine: OwnAddresses([myAddress].compactMap { $0 }),
                 signature: signature)
    }

    /// The draft a Reply or Reply All starts from.
    ///
    /// Pure, and living here rather than in the view controller it is called
    /// from, because three separate bugs have now been found in these few
    /// lines — a Reply All that CC'd the sender himself, a quote that came
    /// out empty for HTML-only mail, and threading headers that were built
    /// and then thrown away. None of them were visible on the sending
    /// screen. Code with that history belongs somewhere a test can reach it.
    /// Whom it goes to is `ReplyAddressing`'s, for the same reason, after
    /// three more (B-061).
    ///
    /// `mine` is passed in rather than read from the credential store so
    /// this stays a function of its arguments.
    static func replying(to m: Message, all: Bool, mine: OwnAddresses,
                         signature: String = "") -> Draft {
        var draft = Draft()
        draft.subject = m.subject.hasPrefix("Re:") ? m.subject : "Re: \(m.subject)"
        let addressed = ReplyAddressing.reply(to: m, all: all, mine: mine)
        draft.to = addressed.to
        draft.cc = addressed.cc
        draft.inReplyTo = m.messageID
        draft.references = m.references

        // Signature ABOVE the quoted text, which is where Mail puts it and
        // where a reader looks for it. Below the quote it is buried under
        // however much of the original he kept.
        let quoted = m.quoted(eachLineAfter: "> ")
        // When the letter arrived, as Mail's "On ... wrote:" has it
        // (`headerDate`, B-178); its Date where that is not known.
        let region = MailFormat.quoteAttribution(m.headerDate, sender: m.sender) + "\n" + quoted.text
        draft.body = signatureBlock(signature) + "\n\n" + region
        draft.quote = QuotedOriginal(quoting: m, as: .reply, region: region, cut: quoted.isCut)
        // Marked answered once the reply has gone (B-152).
        draft.original = OriginalLetter(m, as: .reply)

        // No attachments here. Quoting somebody's text back is normal;
        // posting their files back to them is not, and doing it with every
        // reply would make each reply to a photograph upload the photograph
        // again. A reply carries them only once it goes to someone the
        // original did not, as Mail's does, and then as rows he sees before
        // it can go: the composer's `ReplyFiles` (B-107), which the pane
        // hands it with this draft.
        return draft
    }

    /// The draft a Forward starts from.
    ///
    /// `includingFiles` is his answer to Mail's question, "Include
    /// attachments from original message?", which Forward asks of a letter
    /// with files the header lists (`ReplyFiles.forwardAsks`, B-107):
    /// Include, or no question, carries every part, as a forward always
    /// has; Don’t Include only the pictures the original shows in its body,
    /// which its quote shows too (`DraftAttachment.carried(from:)`), and
    /// none when its quote is cut to what fits, which shows none (B-140).
    static func forwarding(_ m: Message, signature: String = "",
                           includingFiles: Bool = true) -> Draft {
        var draft = Draft()
        draft.subject = m.subject.hasPrefix("Fwd:") ? m.subject : "Fwd: \(m.subject)"
        // Apple's header block, not Gmail's. The old one read
        // "---------- Forwarded message ----------" with only From and
        // Subject under it, which is Gmail's wording and drops the two
        // fields a forward is usually sent to establish: WHEN it arrived and
        // WHO else already had it. Field order is the iPad's own: From,
        // Date, To, Subject, as his forwards show, with Cc after To when the
        // original had one (B-050 says where that placement comes from).
        // Mail on the Mac writes Subject second instead. The date is when
        // the letter arrived, as a reply's and Print's are (`headerDate`,
        // B-178), its Date where that is not known: Mail's own Forward was
        // not looked at, its reply and its print were.
        var region = "Begin forwarded message:\n\n"
            + "From: \(MailFormat.addressForQuoting(m.sender))\n"
            + "Date: \(MailFormat.forwardedDate(m.headerDate))\n"
            + "To: \(m.to.map(MailFormat.addressForQuoting).joined(separator: ", "))\n"
        if !m.cc.isEmpty {
            region += "Cc: \(m.cc.map(MailFormat.addressForQuoting).joined(separator: ", "))\n"
        }
        let quoted = m.quoted()
        region += "Subject: \(m.subject)\n\n" + quoted.text
        draft.body = signatureBlock(signature) + "\n\n" + region
        draft.quote = QuotedOriginal(quoting: m, as: .forward, region: region, cut: quoted.isCut)
        // Marked forwarded once the forward has gone (B-152).
        draft.original = OriginalLetter(m, as: .forward)
        // The files come too. Forwarding a receipt and leaving its two PDFs
        // behind sends a letter about nothing, and does it silently — which
        // is the part that matters, because nothing on the sending screen
        // said they had been dropped. They are left only when he answers
        // Don’t Include to the question Forward asks first.
        //
        // Every part is a row, the pictures the original shows in its body
        // included, so he can see what the forward weighs and take any of
        // it off. At Send the pictures its quote still shows go in the quote
        // rather than as files (`AppleMailHTML.letter`); if he has changed
        // the quote, they go as files, as they always did.
        //
        // Made by the mapper a reply's files are made by
        // (`DraftAttachment.carried(from:)`), so the two name every part
        // the same way.
        //
        // A quote cut to what fits (B-140) quotes the words alone, without
        // the original's pictures, so Don’t Include carries none: the
        // pictures it would carry are the ones the quote shows, and here
        // it shows none. They went as files.
        draft.attachments = quoted.isCut && !includingFiles
            ? [] : DraftAttachment.carried(from: m, filesToo: includingFiles)
        // No threading headers on a forward: it starts a new conversation
        // with a new recipient, and claiming the original as its parent
        // would file it into a thread they have never seen.
        return draft
    }

    /// A saved draft, read back out of Drafts, as the composer takes it up
    /// again.
    ///
    /// Every part the letter carries comes back as a file row EXCEPT the
    /// signature's own pictures (B-046). Those are not files he attached:
    /// saving and sending both add them afresh, inline, from
    /// `SignatureImages`, so the copy stored with the draft is only there
    /// to make the stored markup's `cid:` resolve. Taken up as an
    /// attachment it showed as a "logo.png" row he had never added, went
    /// out as a second, stapled-on copy of the logo, and was saved again
    /// with every save, one more copy each time the draft was put down and
    /// picked up.
    ///
    /// Any OTHER inline picture, such as a photograph placed in the body of
    /// a draft begun in another client, stays a file row. The composer is
    /// plain text with an HTML twin built at send (D-013), so there is
    /// nowhere in the text to keep it; as a row it still goes with the
    /// letter, and he can see it and remove it. Dropping it would send a
    /// letter that says "here is the photo" without the photo, and nothing
    /// on the sending screen would say so. Where it goes in the letter is
    /// `inBody`'s, below.
    ///
    /// A draft of a reply or forward this app saved comes back with its
    /// quote (`QuotedOriginal.recovered`), so the letter sent from it is the
    /// one he would have sent before putting it down: the original as it
    /// looked, if he has still not touched the quote. A forward's pictures
    /// are rows, as they were when he began it, and so are a reply's when
    /// it was carrying the original's parts (B-107); a reply that carried
    /// none has none to bring back.
    ///
    /// A reply comes back still answering its letter: the draft's
    /// In-Reply-To, which names it, and its References, which already end
    /// with it (B-064). Left behind, as they were, the reply finished from
    /// Drafts went with neither, and began a conversation of its own, in
    /// Gmail and at everyone it went to. The builder reads the ids out of
    /// them and does not add the letter answered to References a second
    /// time (`RFC5322Builder.messageIDs`). A forward this app saved has
    /// neither, and a letter begun afresh, so they come back with none.
    ///
    /// A part its saved markup shows among his words, before his signature
    /// and any quote, is one of his photos in the letter: its row comes back
    /// marked so (`DraftAttachment.inBody`), and it goes in the letter again
    /// (B-109). That covers a draft begun in Mail on another device, which
    /// places its photos there too. Every other part is a row as before.
    static func reopening(_ m: Message,
                          signatureImages: [SignatureImages.InlineImage]) -> Draft {
        // `quotableText` rather than `textBody`, so a draft written in
        // another client as HTML reopens with its words in it instead of
        // empty. Made from no more of its markup than the composer is
        // given (`ComposeForm.largestBody`, B-140), and ended with the line
        // that says so when there was more. A text part comes whole, and
        // the composer bounds it as it opens (`ComposeForm.bounded`).
        let body: String
        if let text = m.textBody {
            body = text
        } else {
            let made = m.quotableText(within: ComposeForm.largestBody)
            body = made.isCut ? ComposeForm.bounded(body: made.text, more: true) : made.text
        }
        let amongHisWords = m.htmlBody.map(AppleMailHTML.contentIDsAmongHisWords) ?? []
        // Each recipient as the composer's field keeps it, so that a name
        // whose comma came out of an encoded word, `Example, Jane
        // <jane@example.com>` once decoded, is still one recipient when the
        // field is read back, and not two, the first of them `Example`.
        // A reply keeps its recipients' names since B-061, so its drafts
        // carry them.
        return Draft(to: m.to.map(MailFormat.fieldEntry),
                     cc: m.cc.map(MailFormat.fieldEntry),
                     bcc: m.bcc.map(MailFormat.fieldEntry),
                     subject: m.subject,
                     body: body,
                     inReplyTo: m.inReplyTo,
                     references: m.references,
                     attachments: m.attachments
                         .filter { !SignatureImages.contains($0, in: signatureImages) }
                         .map {
                             DraftAttachment(source: .messagePart(messageID: m.id,
                                                                  mailboxID: m.mailboxID,
                                                                  section: $0.id,
                                                                  letter: m.gmailMessageID),
                                             filename: $0.filename,
                                             mimeType: $0.mimeType,
                                             size: $0.size,
                                             inBody: $0.contentID.map(amongHisWords.contains)
                                                 ?? false)
                         },
                     savedID: m.id,
                     savedLetter: m.gmailMessageID,
                     quote: QuotedOriginal.recovered(from: m, body: body))
    }
}

/// A file being carried into a new message, held as a POINTER rather than as
/// bytes.
///
/// The obvious design — load the data when the compose screen opens — was
/// rejected twice over. It would stall the sheet behind a download of
/// unknown size with nothing on screen to say why, and it would then hold
/// those megabytes in memory for as long as someone takes to write a letter,
/// which for this user is not a short time. Resolving the bytes at Send
/// instead puts the wait where a wait is already expected, and usually costs
/// nothing at all: the repository still has the whole source message cached
/// from displaying it a moment earlier.
struct DraftAttachment: Equatable {

    /// Where the bytes come from when the letter is finally built.
    ///
    /// Two genuinely different things, and the second one is new. A
    /// forward carries PARTS OF A MESSAGE already on the server, named
    /// rather than copied, so nothing is downloaded until send. A photo he
    /// chose is a FILE on this device. Both end up as the same MIME part
    /// on the wire; only the fetch differs.
    ///
    /// A part names its letter by folder and UID, `messageID` and
    /// `mailboxID`, and by Gmail's id for it, `letter` (X-GM-MSGID), nil
    /// where the server named none: on a server without Gmail's extension,
    /// and in a letter kept on the iPad by a build before the id was kept.
    /// The folder and UID are how it is fetched; the id is how the bytes
    /// are known to be that letter's once the letter has waited on the iPad
    /// into a later launch (`IMAPMailRepository.fetchCarried`).
    enum Source: Equatable {
        case messagePart(messageID: String, mailboxID: String, section: String,
                         letter: UInt64? = nil)
        case localFile(URL)
    }

    let source: Source
    let filename: String
    let mimeType: String
    /// The size the reader would recognise, from the source message's
    /// BODYSTRUCTURE. An estimate — it scales base64 back by three quarters
    /// and does not subtract the line breaks, so it runs a couple of per
    /// cent high — which is fine for showing him what a forward weighs, and
    /// is NOT what the send-time limit check uses. That one counts the real
    /// built message.
    let size: Int64?
    /// A part of a draft reopened from Drafts that its saved letter showed
    /// among his words, before his signature and any quote: one of his
    /// photos in the letter, which goes there again (`isBodyPicture`,
    /// B-109). False for every other row, a photo on the iPad included,
    /// which is one by what it is.
    ///
    /// Declared last so the memberwise initializer keeps the argument order
    /// every existing call site uses.
    var inBody: Bool = false

    /// The kinds of picture that go in the letter, under his words: the
    /// three his Apple Mail letters' pictures were, and that every mail
    /// program shows (B-109).
    static let bodyPictureTypes: Set<String> = ["image/jpeg", "image/png", "image/gif"]

    /// True for a photo of his that goes in the letter, after his last
    /// typed line and above his signature, as every one of his Apple Mail
    /// letters with a picture had it (B-109), rather than as a file under
    /// it: a JPEG, PNG or GIF he attached himself, a file on this iPad from
    /// Photo Library, Attach File or the share sheet, or a part of a
    /// reopened draft that was in the letter (`inBody`).
    ///
    /// Never a part of a letter on the server otherwise: a forward's
    /// files, a reply's (B-107) and a quote's pictures go as they did. Nor
    /// a video, a PDF or any other kind, nor the signature's pictures,
    /// which are no row. It is still his row, with its weight and its
    /// Remove; only where it goes in the letter is decided here
    /// (`AppleMailHTML.letter`).
    var isBodyPicture: Bool {
        let type = mimeType.trimmingCharacters(in: .whitespaces).lowercased()
        guard Self.bodyPictureTypes.contains(type) else { return false }
        if case .localFile = source { return true }
        return inBody
    }

    /// The parts of `m` as a letter made from it carries them, a row each,
    /// with its weight and a Remove: every part, the pictures its body
    /// shows by `cid:` among them, or with `filesToo` false those pictures
    /// alone (`Attachment.isShownInBody`). In the letter's order.
    ///
    /// What a forward carries (`Draft.forwarding`) and what a reply carries
    /// once it goes to someone the original did not (`ReplyFiles`, B-107):
    /// one mapper, so the two make the same rows, byte for byte. The
    /// pictures are rows too, so he sees what they weigh and can take any
    /// off; at Send the ones the quote still shows go in the quote, and the
    /// rest as files (`AppleMailHTML.letter`).
    ///
    /// Each names the original by Gmail's id as well as by folder and UID,
    /// so a letter kept on the iPad and sent in a later launch carries its
    /// own files or none (`Message.gmailMessageID`).
    static func carried(from m: Message, filesToo: Bool = true) -> [DraftAttachment] {
        m.attachments.filter { filesToo || $0.isShownInBody }.map {
            DraftAttachment(source: .messagePart(messageID: m.id,
                                                 mailboxID: m.mailboxID,
                                                 section: $0.id,
                                                 letter: m.gmailMessageID),
                            filename: $0.filename,
                            mimeType: $0.mimeType, size: $0.size)
        }
    }
}

// MARK: - Formatting

enum MailFormat {

    /// The addresses in a recipient field as he left it: split on the
    /// commas the suggestions put between them, and on a ";", blanks
    /// dropped.
    ///
    /// Not on a comma inside a quoted name, `<…>` or a comment: a reply
    /// keeps its recipients' names since B-061, and `"Example, Jane"
    /// <jane@example.com>` split at every comma was two recipients, the
    /// first of them `"Example`, which mail cannot be sent to. A quote
    /// never closed is split at every comma and ";", as before at every
    /// comma.
    ///
    /// A ";" separates addresses as a "," does, as Mail takes it (B-081):
    /// "jane@example.com;" is Jane, and a ";" at the end, alone, or beside
    /// a "," is nothing. Split at commas alone, the field kept the ";" in
    /// the address, the letter went `RCPT TO:<jane@example.com;>`, Gmail
    /// answered 553 5.1.3, "not a valid RFC 5321 address", and he saw
    /// "Message was not sent." A group, `Friends: …;`, is a header's, not
    /// his typing's: here its ";" separates too. An empty group,
    /// `undisclosed-recipients:;`, which a draft written in another client
    /// can have, is the one exception: it stays one entry, its ";" with it,
    /// as before. Split there, the bubble read "undisclosed-recipients:",
    /// and the header went out "To: undisclosed-recipients:", a group
    /// begun and never ended.
    static func addresses(in field: String) -> [String] {
        entries(of: field, groups: false)
    }

    /// An empty group, `undisclosed-recipients:;`: a name for nobody, the
    /// one entry `addresses(in:)` leaves ending in ";", and no address. It
    /// stays in the field and the header; the envelope leaves it out
    /// (`Submission.recipients`, B-081).
    static func isEmptyGroup(_ entry: String) -> Bool {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix(";") && trimmed.contains(":") && recipient(in: trimmed) == nil
    }

    /// The address currently being typed in a recipient field —
    /// everything after the last comma, since a field can hold several.
    static func currentRecipientToken(in text: String) -> String {
        guard let last = text.split(separator: ",", omittingEmptySubsequences: false).last
        else { return "" }
        return last.trimmingCharacters(in: .whitespaces)
    }

    /// Swaps the half-typed address for a chosen one and leaves a
    /// separator ready for the next. The composers' fields are bubbles
    /// since B-076, and a pick is `RecipientBubbles.pick` there; this is
    /// the same pick on the field's text.
    ///
    /// The trailing ", " is doing real work rather than tidying: the email
    /// keyboard has no comma key, and `ComposeViewController` splits
    /// recipients on commas, so without this he could not address a second
    /// person at all. Choosing from the suggestion list is the only way a
    /// comma gets into that field.
    static func replacingRecipientToken(in text: String, with address: String) -> String {
        var parts = text.split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        if parts.isEmpty { parts = [""] }
        parts[parts.count - 1] = " " + address
        return parts.joined(separator: ",").trimmingCharacters(in: .whitespaces) + ", "
    }

    /// The list timestamp. iPad Mail shows a time for today, "Yesterday",
    /// a weekday inside the last week, and the short date beyond that,
    /// never a relative string like "2 hours ago", which forces a reader to
    /// do arithmetic.
    ///
    /// The time and the date are written the iPad's way, as Mail writes
    /// them (B-119): the locale's short styles, so its region decides the
    /// order of day and month, the clock and the year. With his US region a
    /// letter of 3 October 2026 older than a week reads "10/3/26"; with a
    /// British one "03/10/2026". It read "03/10/26" for every region, which
    /// he reads as March 10.
    ///
    /// Today and yesterday are `now`'s, which is the clock unless a test
    /// hands in another; the formatters are kept (`DisplayDates`), the day
    /// never is. `locale` and `timeZone` are the iPad's unless a test hands
    /// in others.
    static func listTimestamp(_ date: Date, now: Date = Date(),
                              locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let dates = DisplayDates.shared
        let form: DisplayDates.Form
        switch dates.day(of: date, now: now, locale: locale, timeZone: timeZone) {
        case .today:     form = .time
        case .yesterday: return "Yesterday"
        case .thisWeek:  form = .weekday
        case .earlier:   form = .shortDate
        }
        return dates.string(from: date, form, locale: locale, timeZone: timeZone)
    }

    /// `"Jane Smith" <jane@example.com>` → `jane@example.com`: what two
    /// spellings of one recipient are compared by. A reply used to be
    /// addressed to this alone, and lost every name; it keeps them since
    /// B-061, and `SMTPClient` takes the address out of each for RCPT TO.
    ///
    /// Lives here rather than on the repository because a reply's
    /// addressing (`OwnAddresses`) uses it and must stay Foundation-only —
    /// the repository was behind `#if canImport(Network)` and did not exist
    /// on the test host.
    static func bareAddress(_ header: String) -> String {
        if let open = header.lastIndex(of: "<"), let close = header.lastIndex(of: ">"),
           open < close {
            return String(header[header.index(after: open)..<close])
                .trimmingCharacters(in: .whitespaces)
        }
        return header.trimmingCharacters(in: .whitespaces)
    }

    /// `Jane Smith <jane@example.com>`, or the bare address when there is no
    /// display name — which is how Apple writes a correspondent in both the
    /// reply attribution and the forwarded-message header.
    static func addressForQuoting(_ header: String) -> String {
        let address = bareAddress(header)
        let name = displayName(header)
        if name.isEmpty || name == address { return address }
        return "\(name) <\(address)>"
    }

    /// `On Sep 20, 2026, at 8:12 PM, Jane Smith <jane@example.com> wrote:`
    ///
    /// Apple Mail's attribution. This app used to write `Today at 8:12 PM,
    /// Jane Smith wrote:`, relative, no leading "On", no address, which is
    /// nobody's format: the relative day is meaningless by the time the
    /// recipient reads it, and a thread quoting itself down four replies
    /// ends up with a column of "Today"s that were four different days.
    ///
    /// The date and the time are the iPad's, as Mail writes them (B-119):
    /// the locale's medium date and short time, each from the system's
    /// formatter. With his US region that is `Sep 20, 2026` and `8:12 PM`,
    /// as every Apple Mail attribution in his replies reads; with a British
    /// one `On 3 Oct 2026, at 09:14, …`, as a British Mail writes it. The
    /// space before AM or PM is whatever the iPad's formatter puts there:
    /// U+202F NARROW NO-BREAK SPACE on iPadOS 17 and later, as in his own
    /// sent mail, an ordinary one before. It was written in `en_US_POSIX`
    /// for every region, so the date was month-first where the rows were
    /// day-first. The words around them stay Mail's English ones;
    /// `AppleMailHTML` finds a reply's quote by its "On " and "wrote:".
    ///
    /// `locale` and `timeZone` are the iPad's unless a test hands in others.
    static func quoteAttribution(_ date: Date, sender: String, locale: Locale = .current,
                                 timeZone: TimeZone = .current) -> String {
        let day = DisplayDates.formatter(.mediumDate, locale: locale, timeZone: timeZone)
        let time = DisplayDates.formatter(.time, locale: locale, timeZone: timeZone)
        // The commas after the date and the time are Apple's, and are not
        // there in the longer forwarded-message form below.
        return "On \(day.string(from: date)), at \(time.string(from: date)), "
            + "\(addressForQuoting(sender)) wrote:"
    }

    /// `September 20, 2026 at 8:12:03 PM EDT`: the longer form Apple uses in
    /// the header block of a forwarded message, where there is no surrounding
    /// sentence to keep it short. The locale's long date and long time, the
    /// iPad's way as for `quoteAttribution` (B-119); with a British region
    /// `20 September 2026 at 20:12:03 BST`.
    static func forwardedDate(_ date: Date, locale: Locale = .current,
                              timeZone: TimeZone = .current) -> String {
        DisplayDates.formatter(.longDateAndLongTime, locale: locale, timeZone: timeZone)
            .string(from: date)
    }

    /// "Today at 9:14 AM" / "Yesterday at 6:43 PM" / "September 18, 2026 at
    /// 6:43 PM". The reference uses the relative day for recent mail, which
    /// is both shorter and easier than parsing a date to work out whether it
    /// is new. The time and the date the iPad's way (B-119), as for
    /// `listTimestamp`: with a British region "Today at 09:14" and "18
    /// September 2026 at 18:43". `now`, `locale` and `timeZone` as for
    /// `listTimestamp`.
    static func detailTimestamp(_ date: Date, now: Date = Date(),
                                locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let dates = DisplayDates.shared
        let time = { dates.string(from: date, .time, locale: locale, timeZone: timeZone) }
        switch dates.day(of: date, now: now, locale: locale, timeZone: timeZone) {
        case .today:     return "Today at " + time()
        case .yesterday: return "Yesterday at " + time()
        case .thisWeek, .earlier:
            return fullTimestamp(date, locale: locale, timeZone: timeZone)
        }
    }

    /// "October 22, 2026 at 9:14 AM", whatever day it is: the date the
    /// reading pane gives a letter older than yesterday. It was written out
    /// for every letter on paper too (B-110), until the paper took Mail's
    /// own form (`printedTimestamp`, B-172). The locale's long date and
    /// short time, joined as the iPad's formatter joins them (B-119): with
    /// his US region month first, as Mail's header; with a British one "22
    /// October 2026 at 09:14". It was "22 October 2026 at 9:14 AM" for every
    /// region. `locale` and `timeZone` as for `listTimestamp`.
    static func fullTimestamp(_ date: Date, locale: Locale = .current,
                              timeZone: TimeZone = .current) -> String {
        DisplayDates.shared.string(from: date, .longDateAndTime, locale: locale, timeZone: timeZone)
    }

    /// "Oct 27, 2026 at 1:25:45 PM", whatever day it is: the date on a
    /// printed letter, as Mail prints it (B-172), its "Date:" line. Seen on
    /// the test iPad, Mail 16.5.1, 2026-10-27 (round r6-i-compare, C-17b):
    /// "Date: Oct 27, 2026 at 1:25:45 PM" in the print's preview, where
    /// Blackmail printed the pane's "October 27, 2026 at 1:25 PM"
    /// (`fullTimestamp`, B-110). The locale's medium date and medium time,
    /// joined as the iPad's formatter joins them, as every date here is
    /// (B-119). The pane's dates are not changed. `locale` and `timeZone`
    /// as for `listTimestamp`.
    static func printedTimestamp(_ date: Date, locale: Locale = .current,
                                 timeZone: TimeZone = .current) -> String {
        DisplayDates.shared.string(from: date, .mediumDateAndMediumTime, locale: locale, timeZone: timeZone)
    }

    /// "Jane Smith <jane@example.com>" -> "Jane Smith". Falls back to the whole
    /// string, so a malformed header degrades to something readable rather than
    /// to nothing.
    static func displayName(_ sender: String) -> String {
        guard let angle = sender.firstIndex(of: "<") else { return sender }
        let name = sender[..<angle].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? sender : name.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    /// The entries of an address list, a To or Cc header as it came: split
    /// on the commas between addresses, and not on a comma inside a quoted
    /// name, `<…>` or a comment. `"Example, Jane" <jane@example.com>, Sam
    /// Example <sam@example.com>` is two entries, where splitting on every
    /// comma made three, the first of them `"Example`, which the reading
    /// pane showed as a name and Reply All tried to send to.
    ///
    /// A ";" between addresses separates them as a comma does (B-081):
    /// `Jane <jane@example.com>; Sam <sam@example.com>`, as some clients
    /// write a header, and as this app wrote one with a ";" he typed, is
    /// two entries. Read as one, Reply All named Sam alone, with Jane in his
    /// name, and could not leave his own address out of it. A ";" that ends
    /// a group (RFC 5322), `Friends: jane@example.com, sam@example.com;` or
    /// the empty `undisclosed-recipients:;`, stays with the group's last
    /// entry, as before, so an empty group is still nobody
    /// (`MailFormat.recipient(in:)`, `RowNames.person(in:)`).
    ///
    /// A quote, bracket or comment never closed is a broken header, and it
    /// is split on every comma, as every header used to be, rather than
    /// have one stray quote take every address after it into one entry.
    static func addressList(_ field: String) -> [String] {
        entries(of: field, groups: true)
    }

    /// The entries of a header's address list, or of a recipient field,
    /// split on the commas and the ";"s between them, outside quotes, `<…>`
    /// and comments; trimmed, blanks dropped. A group is opened by a colon
    /// outside quotes with no "@" or "<" before it in its entry. With
    /// `groups`, the ";" that ends a group is kept as the end of its last
    /// entry; without, every ";" separates, but for the ";" of an empty
    /// group, nothing but spaces or a comment after its colon, which is
    /// kept with it in both. A quote, bracket or comment never closed
    /// splits the field at every comma, and, without `groups`, at every ";"
    /// too.
    private static func entries(of field: String, groups: Bool) -> [String] {
        var entries: [String] = []
        var entry = ""
        var quoted = false, escaped = false, bracketed = false
        var comments = 0
        var inGroup = false
        // The group opened has nothing in it yet, `undisclosed-recipients:`.
        var groupEmpty = false
        for c in field {
            if escaped {
                escaped = false
                entry.append(c)
                continue
            }
            let inComment = comments > 0
            switch c {
            case "\\" where quoted || comments > 0: escaped = true
            case "\"" where !bracketed && comments == 0: quoted.toggle()
            case "<" where !quoted && comments == 0: bracketed = true
            case ">" where !quoted && comments == 0: bracketed = false
            case "(" where !quoted && !bracketed: comments += 1
            case ")" where !quoted && !bracketed && comments > 0: comments -= 1
            case ":" where !inGroup && !quoted && !bracketed && comments == 0
                        && !entry.contains(where: { $0 == "@" || $0 == "<" }):
                inGroup = true
                groupEmpty = true
                entry.append(c)
                continue
            case "," where !quoted && !bracketed && comments == 0:
                entries.append(entry)
                entry = ""
                groupEmpty = false
                continue
            case ";" where !quoted && !bracketed && comments == 0:
                if inGroup && (groups || groupEmpty) {
                    // The group's end, kept with its last entry.
                    entry.append(c)
                }
                inGroup = false
                groupEmpty = false
                entries.append(entry)
                entry = ""
                continue
            default: break
            }
            // Anything but a space or a comment puts something in the group.
            if !c.isWhitespace, !inComment, comments == 0 { groupEmpty = false }
            entry.append(c)
        }
        entries.append(entry)
        if quoted || escaped || bracketed || comments > 0 {
            entries = groups ? field.components(separatedBy: ",")
                             : field.components(separatedBy: CharacterSet(charactersIn: ",;"))
        }
        return entries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// How the reading pane names a recipient, as Mail does: the name, or
    /// the address where there is no name. "Jane Example" for `Jane Example
    /// <jane@example.com>` and `"Jane Example" <…>`; `jane@example.com` for
    /// that address alone, `<jane@example.com>`, or `"" <jane@example.com>`,
    /// which used to show as the brackets and address, and as nothing.
    static func recipientName(_ entry: String) -> String {
        let entry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard entry.contains("<") else { return entry }
        let name = displayName(entry)
        return name.isEmpty || name == entry ? bareAddress(entry) : name
    }

    /// A line of the reading pane's header naming `entries`, the To or Cc
    /// header's: "Cc: Jane Example, sam@example.com". Nil when there are
    /// none, and the header has no such line.
    static func recipientsLine(_ field: String, _ entries: [String]) -> String? {
        guard !entries.isEmpty else { return nil }
        return field + ": " + entries.map(recipientName).joined(separator: ", ")
    }
}

/// The list's and the reading pane's date formatters, built once and kept.
///
/// Every date and time shown to him is one of the forms below, each the
/// locale's own style or template (B-119), never a fixed pattern: the
/// iPad's region decides the order of day and month, the clock and the
/// words, as it does for Mail. A fixed "dd/MM/yy" wrote 3 October as
/// "03/10/26" for every region, which with his US region he reads as
/// March 10.
///
/// A `DateFormatter` costs over a hundred microseconds to build, and these
/// were built on every call: twice for each row the list draws and once for
/// each letter in a conversation's stack. `IMAPParserDates` keeps its
/// formatters for the same reason.
///
/// The parser's are pinned to `en_US_POSIX` and UTC; these follow the iPad's
/// language, region and time zone, and a kept formatter keeps whatever it was
/// built with. So they are built again when asked for a locale or zone other
/// than the one they were made for, which is what a trip abroad or a change
/// in Settings looks like here, and thrown away when iOS says either has
/// changed. The notification covers what the identifiers do not show, such
/// as the 24-hour clock, which changes the locale's preferences and not its
/// name.
///
/// Which day it is is never kept. Today, yesterday and the last week are
/// worked out from `now` on every call, so a list drawn after midnight does
/// not go on giving yesterday's letters a time of day.
///
/// What is already on the screen is another matter: a label keeps the words
/// it was given. So once the kept formatters have been let go, this says so
/// (`didChange`), and the list's rows, the reading pane's header and a
/// conversation's lines write their dates again (B-139). Until then a switch
/// to 24-Hour Time left "12:39 PM" on the open letter while the status bar
/// read 14:41, until a scroll or opening the letter again drew it anew.
///
/// One lock around all of it, formatting included: the notifications arrive
/// on whichever thread posted them, and a kept formatter is shared by every
/// caller.
final class DisplayDates: @unchecked Sendable {

    /// Where a date falls, seen from `now`.
    enum Day {
        case today, yesterday
        /// Within the six days before today.
        case thisWeek
        case earlier
    }

    /// What a formatter writes, each in the locale's own way. Shown here
    /// with a US region, and a British one after.
    enum Form: Hashable {
        /// The short time: "9:14 AM"; "09:14". The 24-hour switch in
        /// Settings changes it, as it changes Mail's.
        case time
        /// The weekday's name: "Saturday".
        case weekday
        /// The short date: "10/3/26"; "03/10/2026".
        case shortDate
        /// The medium date: "Oct 3, 2026"; "3 Oct 2026".
        case mediumDate
        /// The long date: "October 3, 2026"; "3 October 2026". The day
        /// the app stops opening (`ExpiryWarning`, B-137).
        case longDate
        /// The long date and the short time, joined as the locale joins
        /// them: "October 3, 2026 at 9:14 AM"; "3 October 2026 at 09:14".
        case longDateAndTime
        /// The long date and the long time, with its zone: "October 3, 2026
        /// at 9:14:03 AM EDT"; "3 October 2026 at 09:14:03 BST".
        case longDateAndLongTime
        /// The medium date and the medium time, with its seconds, joined as
        /// the locale joins them: "Oct 3, 2026 at 9:14:03 AM"; "3 Oct 2026
        /// at 09:14:03". The date Mail prints (`MailFormat.printedTimestamp`,
        /// B-172).
        case mediumDateAndMediumTime
    }

    /// A formatter for `form` in `locale` and `timeZone`, built afresh: from
    /// the locale's styles and templates alone, never a pattern of its own.
    static func formatter(_ form: Form, locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        switch form {
        case .time:
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        case .weekday:
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
        case .shortDate:
            formatter.dateStyle = .short
            formatter.timeStyle = .none
        case .mediumDate:
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        case .longDate:
            formatter.dateStyle = .long
            formatter.timeStyle = .none
        case .longDateAndTime:
            formatter.dateStyle = .long
            formatter.timeStyle = .short
        case .longDateAndLongTime:
            formatter.dateStyle = .long
            formatter.timeStyle = .long
        case .mediumDateAndMediumTime:
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
        }
        return formatter
    }

    static let shared = DisplayDates()

    private let lock = NSLock()
    private let notifications: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    /// The locale and zone the calendar and formatters below were made for;
    /// nil when there are none, or iOS has said either has changed.
    private var madeFor: (locale: String, zone: String)?
    private var calendar = Calendar.current
    private var formatters: [Form: DateFormatter] = [:]
    private var builds = 0
    /// `didChange` is on its way to the main queue and has not gone yet.
    private var saying = false

    /// Said on the main queue, in the centre iOS said it in, once the kept
    /// formatters have been let go for a change of locale or time zone: the
    /// dates on the screen are to be written again (B-139). After, never
    /// beside: the screen's own observers of iOS's notifications could be
    /// called before `forget` and write the old form again with a formatter
    /// still kept, and a switch to 24-Hour Time leaves the locale's name as
    /// it was, "en_US", so nothing but `forget` makes it build anew. Said
    /// once for changes that come together, as a new zone and its locale.
    static let didChange = Notification.Name("BlackmailDisplayDatesDidChange")

    /// `notifications` is where iOS says the locale or the time zone has
    /// changed, and where `didChange` is said; a test hands in a centre of
    /// its own.
    init(notifications: NotificationCenter = .default) {
        self.notifications = notifications
        for name in [NSLocale.currentLocaleDidChangeNotification, .NSSystemTimeZoneDidChange] {
            observers.append(notifications.addObserver(forName: name, object: nil, queue: nil) {
                [weak self] _ in self?.forget()
            })
        }
    }

    deinit {
        for observer in observers { notifications.removeObserver(observer) }
    }

    /// How many formatters have been built. How a test tells a kept one
    /// from a new one.
    var built: Int {
        lock.lock()
        defer { lock.unlock() }
        return builds
    }

    func day(of date: Date, now: Date, locale: Locale, timeZone: TimeZone) -> Day {
        lock.lock()
        defer { lock.unlock() }
        make(locale, timeZone)
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return .yesterday }
        if let week = calendar.date(byAdding: .day, value: -6, to: now), date > week {
            return .thisWeek
        }
        return .earlier
    }

    /// `date` written in `form`, by the formatter kept for it.
    func string(from date: Date, _ form: Form, locale: Locale, timeZone: TimeZone) -> String {
        lock.lock()
        defer { lock.unlock() }
        make(locale, timeZone)
        if let kept = formatters[form] { return kept.string(from: date) }
        let formatter = Self.formatter(form, locale: locale, timeZone: timeZone)
        formatters[form] = formatter
        builds += 1
        return formatter.string(from: date)
    }

    /// Starts afresh for `locale` and `zone` unless everything kept was made
    /// for them. Called with the lock held.
    private func make(_ locale: Locale, _ zone: TimeZone) {
        if let made = madeFor, made.locale == locale.identifier, made.zone == zone.identifier {
            return
        }
        madeFor = (locale.identifier, zone.identifier)
        var fresh = Calendar.current
        fresh.timeZone = zone
        calendar = fresh
        formatters = [:]
    }

    /// Lets the kept formatters go, and then says so on the main queue
    /// (`didChange`), unless it is already on its way: then that one says
    /// it, going after this.
    private func forget() {
        lock.lock()
        madeFor = nil
        formatters = [:]
        let say = !saying
        saying = true
        lock.unlock()
        guard say else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.saying = false
            self.lock.unlock()
            self.notifications.post(name: Self.didChange, object: self)
        }
    }
}
