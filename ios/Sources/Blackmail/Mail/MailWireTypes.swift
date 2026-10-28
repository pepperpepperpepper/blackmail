import Foundation

/// The shared vocabulary between the transport, the parsers and the
/// repository. Pure data: nothing here does I/O, so all of it is testable
/// without a server, which matters because we have no simulator — every
/// on-device test costs a build, sign and deploy cycle.

// MARK: - IMAP wire responses

/// One complete IMAP response chunk: a line, plus any literals spliced into
/// it. A server sends `* 1 FETCH (BODY[] {2048}` then 2048 raw bytes then the
/// rest of the line, so a "line" is not a line.
struct IMAPResponseLine {
    /// The line with each literal replaced by a `\u{0}<index>\u{0}` marker, so
    /// the text stays parseable and the bytes stay exact.
    let text: String
    let literals: [Data]

    static let literalMarker: Character = "\u{0}"

    /// Substitutes literal N back in as a string, for the many cases where a
    /// literal is just a header value rather than binary.
    func literalString(at index: Int) -> String? {
        guard index >= 0, index < literals.count else { return nil }
        return MailText.decode(literals[index])
    }
}

/// The tagged result that ends every IMAP command.
enum IMAPStatus: String {
    case ok = "OK", no = "NO", bad = "BAD"
}

struct IMAPCommandResult {
    let status: IMAPStatus
    /// Human text after the status, e.g. "[AUTHENTICATIONFAILED] Invalid credentials".
    let detail: String
    /// Every untagged line received while the command was in flight.
    let untagged: [IMAPResponseLine]
}

/// What SELECT tells us about a mailbox. `uidValidity` is the one that matters
/// for correctness: if it changes, every cached UID for that mailbox is
/// meaningless and must be discarded, or the app will show the wrong messages.
struct IMAPMailboxState {
    let uidValidity: UInt32
    let uidNext: UInt32
    /// The only one that changes after the SELECT: every EXISTS and EXPUNGE
    /// the server sends while the mailbox is selected moves it.
    var exists: Int
    let flags: [String]
    let permanentFlags: [String]
    let readOnly: Bool
}

/// UIDs from a SEARCH, ascending, with the UIDVALIDITY they were issued
/// under.
///
/// Never one without the other. A UID names a letter only within one
/// numbering of one mailbox, and every command that later acts on these
/// hands the validity back so the client can refuse it if the mailbox has
/// been renumbered in between.
struct IMAPMailboxUIDs: Equatable {
    let validity: UInt32
    let uids: [UInt32]
}

/// One mailbox of a search run in several. See `IMAPClient.search(_:across:)`.
struct IMAPSearchTarget {
    let mailbox: String
    /// How many of the newest hits to fetch summaries for while the mailbox
    /// is selected. Zero for none.
    let summariesOfNewest: Int
}

/// What one mailbox of such a search came to.
struct IMAPMailboxSearch {
    let mailbox: String
    /// Nil when the server would not open the mailbox, or would not search it.
    let hits: IMAPMailboxUIDs?
    /// Summaries of the newest hits, newest first, as many as were asked for.
    let summaries: [IMAPFetchResult]
}

/// One row of a LIST response.
struct IMAPMailboxListing {
    let name: String
    let delimiter: String?
    let attributes: [String]

    /// Gmail marks its real folders with RFC 6154 special-use attributes
    /// (`\All`, `\Sent`, `\Trash`…), which is far more reliable than matching
    /// the localised display name — an account in another language has no
    /// folder called "Sent".
    var specialUse: Mailbox.Role? {
        for a in attributes {
            switch a.lowercased() {
            case "\\inbox":            return .inbox
            case "\\sent":             return .sent
            case "\\drafts":           return .drafts
            case "\\trash":            return .trash
            case "\\all", "\\archive": return .archive
            case "\\junk":             return .junk
            default:                   continue
            }
        }
        return name.uppercased() == "INBOX" ? .inbox : nil
    }

    /// \Noselect marks a container that holds folders but no mail —
    /// "[Gmail]" itself is one. Tapping it would be an error, so it is not
    /// offered, and it has no count to ask for.
    var isSelectable: Bool {
        !attributes.contains { $0.caseInsensitiveCompare("\\Noselect") == .orderedSame }
    }

    /// Whether LIST flags this folder as one of the server's own: RFC 6154's
    /// special-use attributes, and `\Important` (RFC 8457), which Gmail
    /// gives its Important. Important and Starred (`\Flagged`) carry one
    /// and have no role in this app; a label never carries one, whatever it
    /// is called. What tells the folder that holds the server's own
    /// folders, `[Gmail]`, from a label (`FolderTree`, B-116).
    var isServersOwn: Bool {
        attributes.contains { Self.serversOwn.contains($0.lowercased()) }
    }

    private static let serversOwn: Set<String> = ["\\all", "\\archive", "\\drafts", "\\flagged",
                                                  "\\junk", "\\sent", "\\trash", "\\important"]
}

/// A parsed FETCH result for one message. Everything is optional because a
/// FETCH asks for exactly the parts it needs and servers omit what they like.
struct IMAPFetchResult {
    var uid: UInt32?
    var flags: [String] = []
    var internalDate: Date?
    var size: Int?
    var envelope: IMAPEnvelope?
    var bodyStructure: MIMEPart?
    /// Raw bytes of whatever BODY[...] section was requested.
    var body: Data?
    /// The same, by the section each came under, for a FETCH asking for
    /// several at once (`IMAPClient.fetchLetterInPart`): `BODY[2.1]<0>`
    /// under "2.1". `body` keeps the last of them, as it always did.
    var sections: [String: Data] = [:]
    /// Gmail's own thread id, when the server advertised X-GM-EXT-1.
    ///
    /// A 64-bit number, kept as a STRING because it does not fit a UInt32
    /// and nothing here does arithmetic on it.
    ///
    /// Worth having rather than threading by hand: every heuristic for
    /// grouping a conversation — matching References chains, stripping
    /// "Re:" and comparing subjects — is an approximation of what the
    /// server already decided, and Gmail's answer is the one that agrees
    /// with what he sees in Gmail everywhere else.
    var threadID: String?
    /// Gmail's own id for the letter, X-GM-MSGID, when the server advertised
    /// X-GM-EXT-1.
    ///
    /// A number, where the thread id is kept as text, because it is to be a
    /// key (see `MessageSummary.gmailMessageID`): read as a number, a value
    /// that is not one is absent rather than a key that matches nothing.
    /// Gmail documents it as an unsigned 64-bit number, which neither
    /// UInt32 nor Int holds in full.
    var gmailMessageID: UInt64?
    /// Gmail's X-GM-LABELS, when the server advertised X-GM-EXT-1.
    ///
    /// Note what is NOT in here: the label of the mailbox currently
    /// SELECTed. Measured against the live server — the same message reads
    /// `X-GM-LABELS ()` from INBOX and `("\\Inbox")` from All Mail. The
    /// selected folder is implicit and the caller has to add it back.
    var labels: [String] = []
    /// Whether the line carried FLAGS at all, and X-GM-LABELS at all. A
    /// line's `FLAGS ()` is every mark taken off, which `flags` alone cannot
    /// tell from a line that said nothing of them (`laying`, B-112).
    var flagsSent = false
    var labelsSent = false

    var isSeen: Bool    { flags.contains { $0.caseInsensitiveCompare("\\Seen") == .orderedSame } }
    var isFlagged: Bool { flags.contains { $0.caseInsensitiveCompare("\\Flagged") == .orderedSame } }
    /// A reply to the letter has gone: `\Answered`, the flag RFC 3501
    /// (§2.3.2) has for it, which Apple Mail sets once a reply is sent and
    /// shows as a grey arrow on the row (`RowArrow`, B-102). Gmail keeps it
    /// with every row's FLAGS, which the list fetches already.
    var isAnswered: Bool { flags.contains { $0.caseInsensitiveCompare("\\Answered") == .orderedSame } }
    /// The letter has been forwarded: the keyword `$Forwarded` (RFC 5550,
    /// IANA's registry of IMAP keywords), or `Forwarded`, the same mark
    /// without the dollar, which iOS's Mail knows too. Never a system flag,
    /// so no backslash. Any case: a keyword is matched without it.
    var isForwarded: Bool {
        flags.contains { flag in
            flag.caseInsensitiveCompare("$Forwarded") == .orderedSame
                || flag.caseInsensitiveCompare("Forwarded") == .orderedSame
        }
    }

    /// This result with `later` laid over it, a later FETCH line for the
    /// same UID: every item `later` carried in place of this one's, every
    /// item it did not carry kept. FLAGS and X-GM-LABELS go by whether the
    /// line carried them, so a later `FLAGS ()` takes every mark off and a
    /// line without FLAGS takes none.
    ///
    /// For the server's news. RFC 3501 §7.4.2 lets it send a FETCH at any
    /// time, and Gmail tells a mark set on another device so, unasked,
    /// inside the answer to a UID FETCH of its own, as `* 68 FETCH (UID 422
    /// FLAGS (\Answered \Seen))` after the letter's whole line (B-112). On
    /// the test iPad the whole line carried the letter's old flags and the
    /// news after it the new, so the later line has the say. The rest of a
    /// letter does not change, and a news line carries none of it.
    func laying(_ later: IMAPFetchResult) -> IMAPFetchResult {
        var out = self
        if later.flagsSent {
            out.flags = later.flags
            out.flagsSent = true
        }
        if later.labelsSent {
            out.labels = later.labels
            out.labelsSent = true
        }
        out.internalDate = later.internalDate ?? internalDate
        out.size = later.size ?? size
        out.envelope = later.envelope ?? envelope
        out.bodyStructure = later.bodyStructure ?? bodyStructure
        out.body = later.body ?? body
        // Each section by its own name: a later line's bytes for a section
        // in place of this one's, the others kept (B-113's several to a
        // FETCH, B-112's news among them).
        out.sections = sections.merging(later.sections) { _, newer in newer }
        out.threadID = later.threadID ?? threadID
        out.gmailMessageID = later.gmailMessageID ?? gmailMessageID
        return out
    }

    /// One result per UID, in the order each UID first came, each later
    /// line for it laid over what came before (`laying`). A result with no
    /// UID is kept as it is, where it is: nothing says which letter it is.
    ///
    /// Every answer `IMAPParser.parseFetch` reads goes through this, and the
    /// summaries of several FETCHes gathered for one list go through it
    /// again (`IMAPClient.ordered`), so the news riding on one chunk's
    /// answer about a letter of another's is laid over that letter too.
    static func mergedByUID(_ results: [IMAPFetchResult]) -> [IMAPFetchResult] {
        var out: [IMAPFetchResult] = []
        out.reserveCapacity(results.count)
        var at: [UInt32: Int] = [:]
        for result in results {
            guard let uid = result.uid else {
                out.append(result)
                continue
            }
            if let index = at[uid] {
                // Written back whole: see `IMAPClient.noteSizeChanges`.
                out[index] = out[index].laying(result)
            } else {
                at[uid] = out.count
                out.append(result)
            }
        }
        return out
    }
}

/// RFC 3501 ENVELOPE. Enough to build a list row without downloading bodies,
/// which is the whole point — a mailbox of 5,000 messages must not mean 5,000
/// body fetches.
struct IMAPEnvelope {
    var date: Date?
    var subject: String?
    var from: [MailAddress] = []
    var sender: [MailAddress] = []
    var replyTo: [MailAddress] = []
    var to: [MailAddress] = []
    var cc: [MailAddress] = []
    var bcc: [MailAddress] = []
    var inReplyTo: String?
    var messageID: String?
}

struct MailAddress: Hashable {
    var name: String?
    var mailbox: String       // local part
    var host: String

    var address: String { "\(mailbox)@\(host)" }

    /// `"Jane Smith" <jane@example.com>` when there is a name, bare address
    /// otherwise. Matches what `MailFormat.displayName` expects to unpick.
    var formatted: String {
        guard let name, !name.isEmpty else { return address }
        return "\(name) <\(address)>"
    }
}

// MARK: - MIME

/// One node of a MIME tree. A non-multipart message is a single part; a
/// multipart one has children.
struct MIMEPart {
    var type: String = "text"            // lowercased
    var subtype: String = "plain"        // lowercased
    var parameters: [String: String] = [:]
    var id: String?
    var description: String?
    var encoding: String = "7bit"        // lowercased
    var size: Int?
    var lines: Int?
    /// Whether this part is the body of a message/rfc822 part, a letter
    /// forwarded inline or as a file, when that body is one part and not
    /// a multipart: its `section` is "2.1" under the letter's 2, and on
    /// the wire it is asked for as "2.TEXT" (`fetchSection`). Set by
    /// `IMAPParser` from a BODYSTRUCTURE. A part read from a letter's own
    /// bytes is never fetched by its section, and leaves it false (B-114).
    var isMessageText = false
    var disposition: String?             // "inline" / "attachment", lowercased
    var dispositionParameters: [String: String] = [:]
    var children: [MIMEPart] = []

    /// IMAP section path, e.g. "1.2". Set while walking the BODYSTRUCTURE so a
    /// part can be fetched on its own with `BODY[1.2]` rather than pulling the
    /// whole message down to reach one attachment.
    var section: String = "1"

    /// The name this part's bytes are asked for by, `BODY.PEEK[<name>]`:
    /// its `section`, but for the one-part body of a message/rfc822
    /// (`isMessageText`) the letter's TEXT, "2.TEXT" for the body numbered
    /// 2.1.
    ///
    /// RFC 3501 gives that body both names, and Gmail serves only the
    /// second: a FETCH asking BODY[2.1] there is answered "NO Some
    /// messages could not be FETCHed", with nothing of the other parts it
    /// asks for, and BODY[2.TEXT] with the same bytes. Seen on the test
    /// iPad on 2026-10-22: a letter too large to fetch whole that forwards
    /// a plain letter inline could not be opened at all, and the rows whose
    /// previews were asked for with a lone forward's had none. Everything
    /// else goes by `section`, the app's own numbering, which a letter
    /// fetched whole and decoded on the iPad numbers the same: reply,
    /// forward, a file's tile and a part a kept copy names (B-114).
    var fetchSection: String {
        guard isMessageText else { return section }
        guard let dot = section.lastIndex(of: ".") else { return "TEXT" }
        return String(section[..<dot]) + ".TEXT"
    }

    /// The ENVELOPE of the letter a message/rfc822 part holds, as its
    /// BODYSTRUCTURE carries it: the header lines of a letter forwarded
    /// inline, for one shown from its structure (B-114,
    /// `MIMEDecoder.forwardedFields`). Nil for every other part, and for
    /// one parsed from a letter's bytes, whose own header has them.
    ///
    /// Boxed: inline, an ENVELOPE made every part of every tree 112 bytes
    /// larger, 280 where it was 168, for the one part in thousands that
    /// has one.
    var envelope: Envelope?

    /// An ENVELOPE, held by reference (`envelope`).
    final class Envelope {
        let value: IMAPEnvelope
        init(_ value: IMAPEnvelope) { self.value = value }
    }

    var mimeType: String { "\(type)/\(subtype)" }
    var isMultipart: Bool { type == "multipart" }

    var filename: String? {
        dispositionParameters["filename"] ?? parameters["name"]
    }

    /// An attachment is anything explicitly marked as one, or any non-text
    /// leaf with a filename and no disposition saying otherwise.
    ///
    /// `inline` is deliberately NOT an attachment — that is the shape of a
    /// picture the body references by `cid:`, and this app renders those in
    /// the body flow. Listing them as well would put a "sig-logo.png" file
    /// on every letter the signature's images ship with, which Mail does
    /// not do either. It does put its paperclip on such a letter's row,
    /// which this comment said it did not until B-172: seen on the test
    /// iPad, Mail 16.5.1, 2026-10-27; the row's paperclip counts a
    /// picture of multipart/related for it, named or not (2026-10-28)
    /// (`IMAPMailRepository.hasAttachment`), and this is unchanged. (An
    /// earlier comment here said inline images count "because the spec
    /// wants them listed"; that was written
    /// before anything could resolve a `cid:`, when listing was the only
    /// way the picture was reachable at all.)
    ///
    /// What the body is made of goes by this (`MIMEDecoder.bodyPlan(of:)`,
    /// and what `collectAttachments` walks into): a forwarded letter sent
    /// inline as message/rfc822 is words in the body, under its header lines
    /// when there are words outside it (B-114), not a file. The paperclip on
    /// a list row goes by `isListedFile`.
    var isAttachment: Bool {
        if disposition == "attachment" { return true }
        if disposition == "inline" { return false }
        return !isMultipart && type != "text" && filename != nil
    }

    /// Whether this part is a file of the letter's, one the reading pane
    /// draws in the body as a file (B-170), for the paperclip on the list's
    /// row (`IMAPMailRepository.hasAttachment`), from the BODYSTRUCTURE
    /// alone (B-101); the paperclip counts a picture the body shows by
    /// `cid:` as well, named or not, which this leaves out (B-172).
    ///
    /// `isAttachment` with one change: a part sent inline is a file too,
    /// unless it is a picture the body shows by `cid:`, or the words of a
    /// text part with no name. That is the PDF Apple Mail on an iPhone or
    /// an iPad sends, inline, with no `Content-ID`: it had a row in neither
    /// the header nor the list, and Mail lists it. The same parts as
    /// `MIMEDecoder.listedAttachments(in:)`: a picture with
    /// a `Content-ID` as `Attachment.isShownInBody` has one, and a text
    /// part named as `collectAttachments` names it.
    ///
    /// A message/rfc822 part answers as `isAttachment` does, whatever its
    /// disposition: sent inline, it is a forwarded letter whose words are
    /// the body, never a file; its own parts are looked at in their turn.
    var isListedFile: Bool {
        if disposition == "attachment" { return true }
        if type == "message", subtype == "rfc822" { return isAttachment }
        if disposition == "inline" {
            if isMultipart { return false }
            if type == "image", MIMEDecoder.strippedContentID(id) != nil { return false }
            if type == "text", MIMEDecoder.decodedFilename(self) == nil { return false }
            return true
        }
        return isAttachment
    }
}

/// A fully decoded message body: the tree flattened into the two things the UI
/// actually asks for, plus the attachments it lists.
struct DecodedBody {
    var text: String?
    var html: String?
    var attachments: [Attachment] = []
    /// True when the body the pane shows, `html` when there is one and
    /// `text` otherwise, has more parts of words than a body holds
    /// (`MIMEDecoder.maxBodyWords`): shown up to there, and said to be only
    /// the beginning (`Message.isShortened`).
    var isShortened = false
    /// True when `text` is flowed text (`MIMEDecoder.BodyPlan.textIsFlowed`,
    /// `Message.textIsFlowed`).
    var textIsFlowed = false
}

/// The `[APPENDUID <uidvalidity> <uid>]` a server volunteers on a
/// successful APPEND, when it supports UIDPLUS.
///
/// Out here rather than on `IMAPClient` so it could be TESTED: the client
/// was behind `#if canImport(Network)` and did not exist on the machine the
/// suite runs on.
///
/// Without this response code the only way to learn where a message just
/// landed is to re-SELECT and guess at the highest UID, which is a race
/// against anything else delivering. Saving a draft twice has to REPLACE
/// the first copy, and replacing it means knowing precisely which message
/// that is.
enum IMAPAppend {

    /// Returns nil rather than guessing when the server says nothing. The
    /// APPEND still succeeded; the caller degrades to leaving the older
    /// copy in place, which is a duplicate draft — annoying, and far better
    /// than deleting a message chosen at random.
    static func uid(in detail: String) -> (validity: UInt32, uid: UInt32)? {
        guard let open = detail.range(of: "[APPENDUID ", options: .caseInsensitive),
              let close = detail.range(of: "]", range: open.upperBound..<detail.endIndex)
        else { return nil }
        let parts = detail[open.upperBound..<close.lowerBound]
            .split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2,
              let validity = UInt32(parts[0]), let uid = UInt32(parts[1]) else { return nil }
        return (validity, uid)
    }
}

// MARK: - Account

/// Everything needed to reach one account. The password is an app-specific
/// password, never the Google account password, and never an OAuth token:
/// OAuth needs a registered client and a redirect, which a privately
/// sideloaded app with no server has nowhere to put.
struct MailAccount: Codable, Equatable {
    var address: String
    var imapHost: String = "imap.gmail.com"
    var imapPort: UInt16 = 993
    var smtpHost: String = "smtp.gmail.com"
    var smtpPort: UInt16 = 465
    /// Login name, usually the address itself.
    var username: String
    var displayName: String = ""
    /// The sign-off appended to everything he sends.
    ///
    /// Stored with the account rather than built from `displayName`,
    /// because a signature is his words — several lines of them, often a
    /// telephone number or an address — and not a formatting of his name.
    /// Empty means no signature and no separator line, which is the right
    /// default for an account that has not been asked yet.
    var signature: String = ""

    /// The same signature as markup, when there is one.
    ///
    /// His real signature is a two-column table with a photograph, the organisation
    /// logo and his name in bold — 5 kB of it — and none of that survives
    /// the plain transcription above. This field carries the original so
    /// that letters leave here looking like the letters he has been sending
    /// for years. `signature` stays the authority for the plain part and
    /// for what the composer shows him; this is only ever the HTML twin.
    ///
    /// Deliberately not editable in Settings. It is markup, not prose, and a
    /// text field is no place to edit 5 kB of nested tables — one stray
    /// character produces a signature that renders as raw HTML in every
    /// letter, with nothing on this device able to show him that it had.
    /// Settings reports whether one is present and can clear it; setting it
    /// is part of account setup. Empty means the plain signature is
    /// rendered instead, which is correct and safe.
    var signatureHTML: String = ""

    /// His other addresses, as Mail's account lists them under Email after
    /// its own: each added in Settings with "Add Another Email…", by him or
    /// whoever sets up his iPad, in the order added (B-076). Never filled by
    /// the app, as Mail fills nothing. Letters still go from `address`.
    var otherAddresses: [String] = []

    init(address: String, imapHost: String = "imap.gmail.com", imapPort: UInt16 = 993,
         smtpHost: String = "smtp.gmail.com", smtpPort: UInt16 = 465,
         username: String, displayName: String = "", signature: String = "",
         signatureHTML: String = "", otherAddresses: [String] = []) {
        self.address = address
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.username = username
        self.displayName = displayName
        self.signature = signature
        self.signatureHTML = signatureHTML
        self.otherAddresses = otherAddresses
    }

    /// His addresses, as Mail's account lists them under Email: the
    /// account's own first, then each other he has added, each once,
    /// compared without regard to case, blanks left out.
    ///
    /// What the app asks wherever it needs to know whether an address is
    /// his (`OwnAddresses(account:)`): Reply All leaves every one of them
    /// out, and a letter from any of them is his own.
    var ownAddresses: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for a in [address] + otherAddresses {
            let t = a.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seen.insert(t.lowercased()).inserted else { continue }
            out.append(t)
        }
        return out
    }

    /// Why an address cannot be added to his list (`adding`).
    enum AddressRefusal: Error, Equatable {
        /// No `@`, nothing on one side of it, or a space or a comma in it.
        case notAnAddress
        /// Already in the list, in any letter case.
        case alreadyListed
    }

    /// The account with `typed` added to his other addresses, trimmed, as
    /// "Add Another Email…" adds it; or why it cannot be.
    func adding(_ typed: String) -> Result<MailAccount, AddressRefusal> {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = t.lastIndex(of: "@"), at != t.startIndex, t.index(after: at) != t.endIndex,
              !t.contains(where: { $0.isWhitespace || ",;<>()\"".contains($0) }) else {
            return .failure(.notAnAddress)
        }
        guard !ownAddresses.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else {
            return .failure(.alreadyListed)
        }
        var out = self
        out.otherAddresses = Array(ownAddresses.dropFirst()) + [t]
        return .success(out)
    }

    /// The account without `other`, one of his added addresses. The
    /// account's own cannot be taken off: it is the account.
    func removing(_ other: String) -> MailAccount {
        var out = self
        out.otherAddresses = otherAddresses.filter {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(other.trimmingCharacters(in: .whitespacesAndNewlines))
                != .orderedSame
        }
        return out
    }

    /// This account with what Settings saves taken from `saved`: the name,
    /// the signature and its formatted twin, and his other addresses
    /// (B-082). Where it connects, and as whom it signs in, stay this
    /// account's. A `saved` of another address, or none, changes nothing.
    func withSettings(of saved: MailAccount?) -> MailAccount {
        func key(_ address: String) -> String {
            address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard let saved, key(saved.address) == key(address) else { return self }
        var out = self
        out.displayName = saved.displayName
        out.signature = saved.signature
        out.signatureHTML = saved.signatureHTML
        out.otherAddresses = saved.otherAddresses
        return out
    }

    /// Decodes an account stored by an OLDER build, one field at a time.
    ///
    /// Written by hand because **Swift's synthesized `Decodable` does not
    /// use a property's default value** — a missing key throws
    /// `keyNotFound`, defaulted or not. Adding `signature` to this struct
    /// therefore made every account already on disk fail to decode, which
    /// meant `CredentialStore.loadAccount()` returned nil, which meant the
    /// app showed the SETUP FORM to a man who was already set up. With the
    /// bootstrap import gone (B-010) the only way back would have been
    /// retyping the app password.
    ///
    /// Caught by a test before it ever reached the device. Every field that
    /// carries a default is now optional on the way in, so the next one
    /// added cannot do this again.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = try c.decode(String.self, forKey: .address)
        // Username falls back to the address: they are the same thing on
        // every account this app has ever seen, and an account that decodes
        // without one is still usable.
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? address
        imapHost = try c.decodeIfPresent(String.self, forKey: .imapHost) ?? "imap.gmail.com"
        imapPort = try c.decodeIfPresent(UInt16.self, forKey: .imapPort) ?? 993
        smtpHost = try c.decodeIfPresent(String.self, forKey: .smtpHost) ?? "smtp.gmail.com"
        smtpPort = try c.decodeIfPresent(UInt16.self, forKey: .smtpPort) ?? 465
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        signature = try c.decodeIfPresent(String.self, forKey: .signature) ?? ""
        signatureHTML = try c.decodeIfPresent(String.self, forKey: .signatureHTML) ?? ""
        otherAddresses = try c.decodeIfPresent([String].self, forKey: .otherAddresses) ?? []
    }
}
