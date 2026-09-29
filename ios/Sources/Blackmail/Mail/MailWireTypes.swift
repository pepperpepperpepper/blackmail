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
    /// Gmail's X-GM-LABELS, when the server advertised X-GM-EXT-1.
    ///
    /// Note what is NOT in here: the label of the mailbox currently
    /// SELECTed. Measured against the live server — the same message reads
    /// `X-GM-LABELS ()` from INBOX and `("\\Inbox")` from All Mail. The
    /// selected folder is implicit and the caller has to add it back.
    var labels: [String] = []

    var isSeen: Bool    { flags.contains { $0.caseInsensitiveCompare("\\Seen") == .orderedSame } }
    var isFlagged: Bool { flags.contains { $0.caseInsensitiveCompare("\\Flagged") == .orderedSame } }
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
    var disposition: String?             // "inline" / "attachment", lowercased
    var dispositionParameters: [String: String] = [:]
    var children: [MIMEPart] = []

    /// IMAP section path, e.g. "1.2". Set while walking the BODYSTRUCTURE so a
    /// part can be fetched on its own with `BODY[1.2]` rather than pulling the
    /// whole message down to reach one attachment.
    var section: String = "1"

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
    /// the body flow. Listing them as well would put a "sig-logo.png" row
    /// and a paperclip on every letter the signature's images ship with,
    /// which Mail does not do either. (An earlier comment here said inline
    /// images count "because the spec wants them listed"; that was written
    /// before anything could resolve a `cid:`, when listing was the only
    /// way the picture was reachable at all.)
    var isAttachment: Bool {
        if disposition == "attachment" { return true }
        if disposition == "inline" { return false }
        return !isMultipart && type != "text" && filename != nil
    }
}

/// A fully decoded message body: the tree flattened into the two things the UI
/// actually asks for, plus the attachments it lists.
struct DecodedBody {
    var text: String?
    var html: String?
    var attachments: [Attachment] = []
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

    init(address: String, imapHost: String = "imap.gmail.com", imapPort: UInt16 = 993,
         smtpHost: String = "smtp.gmail.com", smtpPort: UInt16 = 465,
         username: String, displayName: String = "", signature: String = "",
         signatureHTML: String = "") {
        self.address = address
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.username = username
        self.displayName = displayName
        self.signature = signature
        self.signatureHTML = signatureHTML
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
    }
}
