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
    /// Nesting depth. Gmail's `[Gmail]/…` children and any user folders sit at
    /// 1; everything else at 0. Drives the indent and the separator inset.
    var depth: Int = 0

    enum Role: String, Codable {
        case inbox, sent, drafts, trash, archive, junk
        /// The letters Send could not take to the server, kept on the iPad
        /// (`Outbox`, B-052). Never a folder on the server: nothing LIST
        /// says maps to it.
        case outbox
    }

    /// What the screens call the folder: its own name, except the inbox,
    /// which is "Inbox" whatever the server calls it.
    ///
    /// IMAP spells the inbox "INBOX", and the sidebar and the list's title
    /// used to show it that way, while the list opened at launch, before
    /// the server has been heard from, said "Inbox" (B-047). Mail says
    /// "Inbox" everywhere, and he knows Mail. Keyed on the role rather than
    /// on the spelling, so it covers a server that writes it "Inbox" or
    /// "inbox" too. `id` and `name` stay the server's: `id` is what goes on
    /// the wire.
    var displayName: String { role == .inbox ? "Inbox" : name }

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
    /// The files the letter carries, as the reading pane's header lists
    /// them, worked out from the BODYSTRUCTURE the row is fetched with, so
    /// before a byte of the letter is downloaded
    /// (`MIMEDecoder.listedAttachments(in:)`). Empty when it has none, or
    /// the server described no structure.
    ///
    /// Carried so the header can list them from the tap. It used to list
    /// them only once the letter had come, and grew by a row per file
    /// then, pushing a conversation's stack down under him as he began to
    /// read it.
    var attachments: [Attachment] = []
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
    let subject: String
    let date: Date
    let textBody: String?
    let htmlBody: String?
    let attachments: [Attachment]

    /// The RFC 5322 `Message-ID` header, which is what a reply must quote to
    /// thread. Emphatically NOT `id` — that is this app's own
    /// "<uidvalidity>/<uid>" handle and means nothing to any other client.
    var messageID: String?
    /// The parent's own `References`, so a reply extends the ancestry
    /// instead of starting it over from one hop.
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
}

extension Message {
    /// The files the header lists: every attachment but the pictures the
    /// body shows by `cid:`, which are not files to him. See
    /// `Attachment.isInline`.
    var listedAttachments: [Attachment] { attachments.filter { !$0.isInline } }

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

    /// True when the part is marked `Content-Disposition: inline` — a
    /// picture the BODY references by `cid:` rather than a file stapled
    /// under the letter. It stays in this array (the reading pane needs it
    /// to resolve the reference) but the header must not offer it as a row.
    ///
    /// Declared after `contentID` so the memberwise initializer keeps the
    /// argument order every existing call site uses.
    var isInline: Bool = false
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
    var inReplyTo: String?
    /// The parent's `References` header, carried so the reply extends the
    /// chain rather than restarting it.
    var references: String?
    /// Files travelling with this message. Only forwards set these.
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
    func firstIndex(matchingMailboxID id: String) -> Int? {
        if let exact = firstIndex(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) {
            return exact
        }
        // A role word against a LIST name. Matching on the ROLE rather than
        // on spelling is what makes this work for "[Gmail]/Sent Mail" and
        // for an account whose folders are not in English.
        guard let role = Mailbox.Role(rawValue: id.lowercased()) else { return nil }
        return firstIndex { $0.role == role }
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
    /// behind the Cc/Bcc toggle, and an address in a hidden row still gets
    /// the letter.
    var showsCcAndBcc: Bool {
        (cc + bcc).contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The draft a Reply or Reply All starts from.
    ///
    /// Pure, and living here rather than in the view controller it is called
    /// from, because three separate bugs have now been found in these few
    /// lines — a Reply All that CC'd the sender himself, a quote that came
    /// out empty for HTML-only mail, and threading headers that were built
    /// and then thrown away. None of them were visible on the sending
    /// screen. Code with that history belongs somewhere a test can reach it.
    ///
    /// `myAddress` is passed in rather than read from the credential store
    /// so this stays a function of its arguments.
    static func replying(to m: Message, all: Bool, myAddress: String?,
                         signature: String = "") -> Draft {
        var draft = Draft()
        draft.subject = m.subject.hasPrefix("Re:") ? m.subject : "Re: \(m.subject)"
        draft.to = [m.senderAddress]
        draft.inReplyTo = m.messageID
        draft.references = m.references

        if all {
            // Everyone except him, so Reply All never mails him a copy of
            // his own reply. This once compared against a hardcoded
            // "me@example.com", which on a real account matches nothing.
            // Compared on the bare address and case-insensitively, because a
            // header carries "Name <ADDR@x>" and the domain is not case
            // sensitive.
            let mine = myAddress?.lowercased()
            let sender = m.senderAddress.lowercased()
            draft.cc = (m.to + m.cc)
                .map(MailFormat.bareAddress)
                .filter { candidate in
                    let c = candidate.lowercased()
                    return !c.isEmpty && c != mine && c != sender
                }
        }

        // Signature ABOVE the quoted text, which is where Mail puts it and
        // where a reader looks for it. Below the quote it is buried under
        // however much of the original he kept.
        let region = MailFormat.quoteAttribution(m.date, sender: m.sender)
            + "\n> "
            + m.quotableText.replacingOccurrences(of: "\n", with: "\n> ")
        draft.body = signatureBlock(signature) + "\n\n" + region
        draft.quote = QuotedOriginal(quoting: m, as: .reply, region: region)

        // Deliberately NO attachments. Quoting somebody's text back is
        // normal; posting their files back to them is not, and doing it by
        // default would make every reply to a photograph re-upload the
        // photograph.
        return draft
    }

    /// The draft a Forward starts from.
    static func forwarding(_ m: Message, signature: String = "") -> Draft {
        var draft = Draft()
        draft.subject = m.subject.hasPrefix("Fwd:") ? m.subject : "Fwd: \(m.subject)"
        // Apple's header block, not Gmail's. The old one read
        // "---------- Forwarded message ----------" with only From and
        // Subject under it, which is Gmail's wording and drops the two
        // fields a forward is usually sent to establish: WHEN it arrived and
        // WHO else already had it. Field order is the iPad's own: From,
        // Date, To, Subject, as his forwards show, with Cc after To when the
        // original had one (B-050 says where that placement comes from).
        // Mail on the Mac writes Subject second instead.
        var region = "Begin forwarded message:\n\n"
            + "From: \(MailFormat.addressForQuoting(m.sender))\n"
            + "Date: \(MailFormat.forwardedDate(m.date))\n"
            + "To: \(m.to.map(MailFormat.addressForQuoting).joined(separator: ", "))\n"
        if !m.cc.isEmpty {
            region += "Cc: \(m.cc.map(MailFormat.addressForQuoting).joined(separator: ", "))\n"
        }
        region += "Subject: \(m.subject)\n\n" + m.quotableText
        draft.body = signatureBlock(signature) + "\n\n" + region
        draft.quote = QuotedOriginal(quoting: m, as: .forward, region: region)
        // The files come too. Forwarding a receipt and leaving its two PDFs
        // behind sends a letter about nothing, and does it silently — which
        // is the part that matters, because nothing on the sending screen
        // said they had been dropped.
        //
        // Every part is a row, the pictures the original shows in its body
        // included, so he can see what the forward weighs and take any of
        // it off. At Send the pictures its quote still shows go in the quote
        // rather than as files (`AppleMailHTML.letter`); if he has changed
        // the quote, they go as files, as they always did.
        //
        // Each names the original by Gmail's id as well as by folder and
        // UID, so a forward kept on the iPad and sent in a later launch
        // carries its own files or none (`Message.gmailMessageID`).
        draft.attachments = m.attachments.map {
            DraftAttachment(source: .messagePart(messageID: m.id,
                                                 mailboxID: m.mailboxID,
                                                 section: $0.id,
                                                 letter: m.gmailMessageID),
                            filename: $0.filename,
                            mimeType: $0.mimeType, size: $0.size)
        }
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
    /// nowhere in the body to keep it; as a file it still goes with the
    /// letter, and he can see it and remove it. Dropping it would send a
    /// letter that says "here is the photo" without the photo, and nothing
    /// on the sending screen would say so.
    ///
    /// A draft of a reply or forward this app saved comes back with its
    /// quote (`QuotedOriginal.recovered`), so the letter sent from it is the
    /// one he would have sent before putting it down: the original as it
    /// looked, if he has still not touched the quote. A forward's pictures
    /// are rows, as they were when he began it; a reply has none to bring
    /// back, as it carries none of the original's parts.
    static func reopening(_ m: Message,
                          signatureImages: [SignatureImages.InlineImage]) -> Draft {
        // `quotableText` rather than `textBody`, so a draft written in
        // another client as HTML reopens with its words in it instead of
        // empty.
        let body = m.textBody ?? m.quotableText
        return Draft(to: m.to,
                     cc: m.cc,
                     bcc: m.bcc,
                     subject: m.subject,
                     body: body,
                     attachments: m.attachments
                         .filter { !SignatureImages.contains($0, in: signatureImages) }
                         .map {
                             DraftAttachment(source: .messagePart(messageID: m.id,
                                                                  mailboxID: m.mailboxID,
                                                                  section: $0.id,
                                                                  letter: m.gmailMessageID),
                                             filename: $0.filename,
                                             mimeType: $0.mimeType,
                                             size: $0.size)
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
struct DraftAttachment {

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
    enum Source {
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
}

// MARK: - Formatting

enum MailFormat {

    /// The addresses in a recipient field as he left it: split on the
    /// commas the suggestions put between them, blanks dropped.
    static func addresses(in field: String) -> [String] {
        field.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The address currently being typed in a recipient field —
    /// everything after the last comma, since a field can hold several.
    static func currentRecipientToken(in text: String) -> String {
        guard let last = text.split(separator: ",", omittingEmptySubsequences: false).last
        else { return "" }
        return last.trimmingCharacters(in: .whitespaces)
    }

    /// Swaps the half-typed address for a chosen one and leaves a
    /// separator ready for the next.
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

    /// The list timestamp. iPad Mail shows a time for today, a weekday inside
    /// the last week, and a date beyond that — never a relative string like
    /// "2 hours ago", which forces a reader to do arithmetic.
    ///
    /// Today and yesterday are `now`'s, which is the clock unless a test
    /// hands in another; the formatters are kept (`DisplayDates`), the day
    /// never is. `locale` and `timeZone` are the iPad's unless a test hands
    /// in others.
    static func listTimestamp(_ date: Date, now: Date = Date(),
                              locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let dates = DisplayDates.shared
        let format: String
        switch dates.day(of: date, now: now, locale: locale, timeZone: timeZone) {
        case .today:     format = "h:mm a"
        case .yesterday: return "Yesterday"
        case .thisWeek:  format = "EEEE"
        case .earlier:   format = "dd/MM/yy"
        }
        return dates.string(from: date, format: format, locale: locale, timeZone: timeZone)
    }

    /// `"Jane Smith" <jane@example.com>` → `jane@example.com`. Replying needs
    /// the bare address; sending to the display-name form bounces.
    ///
    /// Lives here rather than on the repository because `Draft.replying` uses
    /// it and must stay Foundation-only — the repository was behind
    /// `#if canImport(Network)` and did not exist on the test host.
    static func bareAddress(_ header: String) -> String {
        if let open = header.lastIndex(of: "<"), let close = header.lastIndex(of: ">"),
           open < close {
            return String(header[header.index(after: open)..<close])
                .trimmingCharacters(in: .whitespaces)
        }
        return header.trimmingCharacters(in: .whitespaces)
    }

    /// The space Apple puts between the time and AM/PM.
    ///
    /// U+202F NARROW NO-BREAK SPACE, not an ordinary space. Modern Apple
    /// platforms emit it from every date formatter, and it is what turns up
    /// in Sam's own sent mail: `at 5:40 PM` is really `5:40\u{202F}PM`.
    /// Written as a literal rather than taken from a formatter deliberately —
    /// the Linux test host and the iPad ship different ICU versions and
    /// disagree about this character, so a formatter here would mean a test
    /// that passes on one and fails on the other.
    static let narrowNoBreakSpace = "\u{202F}"

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
    /// Apple Mail's attribution, to the character. This app used to write
    /// `Today at 8:12 PM, Jane Smith wrote:` — relative, no leading "On", no
    /// address — which is nobody's format: the relative day is meaningless by
    /// the time the recipient reads it, and a thread quoting itself down four
    /// replies ends up with a column of "Today"s that were four different
    /// days.
    ///
    /// `en_US_POSIX` for the same reason `rfc5322Date` uses it, plus one more
    /// here: the suite runs on Linux and the product runs on iOS, and a
    /// locale-dependent format would make this untestable.
    static func quoteAttribution(_ date: Date, sender: String,
                                 timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        // The comma after the year is Apple's, and is not there in the
        // longer forwarded-message form below.
        f.dateFormat = "MMM d, yyyy, 'at' h:mm"
        let a = DateFormatter()
        a.locale = f.locale
        a.timeZone = timeZone
        a.dateFormat = "a"
        return "On \(f.string(from: date))\(narrowNoBreakSpace)\(a.string(from: date)), "
            + "\(addressForQuoting(sender)) wrote:"
    }

    /// `September 20, 2026 at 8:12:03 PM EDT` — the longer form Apple uses in
    /// the header block of a forwarded message, where there is no surrounding
    /// sentence to keep it short.
    static func forwardedDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "MMMM d, yyyy 'at' h:mm:ss"
        let a = DateFormatter()
        a.locale = f.locale
        a.timeZone = timeZone
        a.dateFormat = "a zzz"
        return "\(f.string(from: date))\(narrowNoBreakSpace)\(a.string(from: date))"
    }

    /// "Today at 9:14 AM" / "Yesterday at 6:43 PM" / "18 September 2026 at 6:43 PM".
    /// The reference uses the relative day for recent mail, which is both
    /// shorter and easier than parsing a date to work out whether it is new.
    /// `now`, `locale` and `timeZone` as for `listTimestamp`.
    static func detailTimestamp(_ date: Date, now: Date = Date(),
                                locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let dates = DisplayDates.shared
        let time = { dates.string(from: date, format: "h:mm a", locale: locale, timeZone: timeZone) }
        switch dates.day(of: date, now: now, locale: locale, timeZone: timeZone) {
        case .today:     return "Today at " + time()
        case .yesterday: return "Yesterday at " + time()
        case .thisWeek, .earlier:
            return dates.string(from: date, format: "d MMMM yyyy 'at' h:mm a",
                                locale: locale, timeZone: timeZone)
        }
    }

    /// "Jane Smith <jane@example.com>" -> "Jane Smith". Falls back to the whole
    /// string, so a malformed header degrades to something readable rather than
    /// to nothing.
    static func displayName(_ sender: String) -> String {
        guard let angle = sender.firstIndex(of: "<") else { return sender }
        let name = sender[..<angle].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? sender : name.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}

/// The list's and the reading pane's date formatters, built once and kept.
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

    static let shared = DisplayDates()

    private let lock = NSLock()
    private let notifications: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    /// The locale and zone the calendar and formatters below were made for;
    /// nil when there are none, or iOS has said either has changed.
    private var madeFor: (locale: String, zone: String)?
    private var calendar = Calendar.current
    private var formatters: [String: DateFormatter] = [:]
    private var builds = 0

    /// `notifications` is where iOS says the locale or the time zone has
    /// changed; a test hands in a centre of its own.
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

    func string(from date: Date, format: String, locale: Locale, timeZone: TimeZone) -> String {
        lock.lock()
        defer { lock.unlock() }
        make(locale, timeZone)
        if let kept = formatters[format] { return kept.string(from: date) }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        formatters[format] = formatter
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

    private func forget() {
        lock.lock()
        madeFor = nil
        formatters = [:]
        lock.unlock()
    }
}
