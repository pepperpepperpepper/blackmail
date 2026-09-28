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
    }
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
        draft.body = signatureBlock(signature)
            + "\n\n" + MailFormat.quoteAttribution(m.date, sender: m.sender)
            + "\n> "
            + m.quotableText.replacingOccurrences(of: "\n", with: "\n> ")

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
        // WHO else already had it. Field order is Apple's own.
        draft.body = signatureBlock(signature)
            + "\n\nBegin forwarded message:\n\n"
            + "From: \(MailFormat.addressForQuoting(m.sender))\n"
            + "Date: \(MailFormat.forwardedDate(m.date))\n"
            + "To: \(m.to.map(MailFormat.addressForQuoting).joined(separator: ", "))\n"
            + "Subject: \(m.subject)\n\n"
            + m.quotableText
        // The files come too. Forwarding a receipt and leaving its two PDFs
        // behind sends a letter about nothing, and does it silently — which
        // is the part that matters, because nothing on the sending screen
        // said they had been dropped.
        draft.attachments = m.attachments.map {
            DraftAttachment(source: .messagePart(messageID: m.id,
                                                 mailboxID: m.mailboxID,
                                                 section: $0.id),
                            filename: $0.filename,
                            mimeType: $0.mimeType, size: $0.size)
        }
        // No threading headers on a forward: it starts a new conversation
        // with a new recipient, and claiming the original as its parent
        // would file it into a thread they have never seen.
        return draft
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
    enum Source {
        case messagePart(messageID: String, mailboxID: String, section: String)
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

    /// The list timestamp. iPad Mail shows a time for today, a weekday inside
    /// the last week, and a date beyond that — never a relative string like
    /// "2 hours ago", which forces a reader to do arithmetic.
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

    static func listTimestamp(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "h:mm a"
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        } else if let week = cal.date(byAdding: .day, value: -6, to: now), date > week {
            f.dateFormat = "EEEE"
        } else {
            f.dateFormat = "dd/MM/yy"
        }
        return f.string(from: date)
    }

    /// "Today at 9:14 AM" / "Yesterday at 6:43 PM" / "18 September 2026 at 6:43 PM".
    /// The reference uses the relative day for recent mail, which is both
    /// shorter and easier than parsing a date to work out whether it is new.
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

    static func detailTimestamp(_ date: Date) -> String {
        let cal = Calendar.current
        let time = DateFormatter()
        time.dateFormat = "h:mm a"
        if cal.isDateInToday(date) {
            return "Today at " + time.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday at " + time.string(from: date)
        }
        let full = DateFormatter()
        full.dateFormat = "d MMMM yyyy 'at' h:mm a"
        return full.string(from: date)
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
