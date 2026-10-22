import Foundation

/// A reply's files, as Apple Mail carries them (B-107): the original's
/// parts, as rows, once the reply goes to someone the original did not go
/// to.
///
/// Mail takes it from Settings, Apps, Mail, Composing, Include Attachments
/// with Replies: Never, When Adding Recipients, Ask or Always. When Adding
/// Recipients is its factory default, and what his own Sent Mail shows: 35
/// of the 41 replies there that carried files had added someone, and none
/// of 36 sampled carried files without. A reply under it carries the files
/// only when it goes to someone the original did not; otherwise Mail's
/// quote shows a picture as a placeholder, and here, as before, the quote
/// leaves it out with its `<img>`. What his iPad says is not yet read, so
/// this is built to the factory default (`mode`).
///
/// The rule, a letter at a time:
///
/// - The original's people are everyone in its From, Reply-To, To, Cc and
///   Bcc, each address compared bare and in lower case, a name or another
///   case making no difference. His own addresses are not taken out: a
///   reply to a letter sent to his first address that he copies to his
///   second is to someone new.
/// - When anyone the reply is to is not among them, the rows go in, after
///   any of his own. When no one new is left, the rows the rule put in go
///   again, those and no others.
/// - A Remove on one of them is his choice, and the rule stops for that
///   letter: what is left stays, whoever the letter goes to.
/// - It follows the bubbles, not what he is still typing, so the rows do
///   not come and go as he spells an address. At Send, `wouldAdd` asks of
///   what he typed too, and a Send that would put the rows in shows them
///   instead of sending; his next tap sends.
///
/// The rows are a forward's (`DraftAttachment.carried(from:)`): every part,
/// the pictures the original shows by `cid:` among them, each with its
/// weight and a Remove. A picture is a row because that is the only way it
/// can go: the quote carries a picture of the original only when one of
/// the letter's rows is that part (`AppleMailHTML.letter`), which is also
/// what lets him see it is going and what it weighs, since the composer
/// shows the quote as words. At Send the pictures the quote still shows go
/// in it, under ids of the letter's own, and the rest as files, fetched as
/// a forward's are.
///
/// When the files appear in Mail's own composer, and whether they go again
/// when the person added is taken out, has not been seen (low confidence):
/// here they appear as the bubble is made, and go with it.
struct ReplyFiles: Equatable {

    /// Mail's four answers to Include Attachments with Replies.
    enum Mode: Equatable {
        /// No reply carries them.
        case never
        /// A reply carries them when it goes to someone the original did
        /// not go to. Mail's factory default.
        case whenAddingRecipients
        /// Reply and Reply All ask Mail's question first, as Forward does,
        /// when the original has files the header lists.
        case ask
        /// Every reply carries them.
        case always
    }

    /// What his iPad's Mail does. Not read there yet, so Mail's factory
    /// default; the one line to change if it says another.
    static let mode = Mode.whenAddingRecipients

    /// Mail's question, which Forward asks of a letter with files, and Reply
    /// and Reply All under `ask`, and its two answers. Mail's words, held
    /// from his iPad until he has approved them.
    static let question = "Include attachments from original message?"
    static let include = "Include"
    static let dontInclude = "Don't Include"

    /// Where the rule is for a letter.
    enum State: Equatable {
        /// The rows are not in: no one new yet, or no longer.
        case notCarried
        /// The rows are in because someone is new, and he has taken none
        /// of them off.
        case carriedAuto
        /// He took one of them off. What is left is his, and the rule has
        /// stopped.
        case hisChoice
    }

    /// The rows the rule puts in.
    let rows: [DraftAttachment]
    /// Everyone the original names, each address bare and in lower case.
    let people: Set<String>
    private(set) var state = State.notCarried

    /// The rule for a reply to `m`; nil for an original with no parts,
    /// where there is nothing to carry.
    init?(replyingTo m: Message) {
        let rows = DraftAttachment.carried(from: m)
        guard !rows.isEmpty else { return nil }
        self.rows = rows
        people = Self.people(of: m)
    }

    /// What a Reply or Reply All of `m` opens with under `mode`: the rows
    /// it opens with, and the rule that follows its recipients, nil where
    /// none does. `included` is his answer to Mail's question under `ask`,
    /// nil where none was asked (`asks`), which carries nothing.
    static func opening(_ m: Message, mode: Mode = ReplyFiles.mode,
                        included: Bool? = nil) -> (rows: [DraftAttachment], rule: ReplyFiles?) {
        switch mode {
        case .never: return ([], nil)
        case .whenAddingRecipients: return ([], ReplyFiles(replyingTo: m))
        case .ask: return (included == true ? DraftAttachment.carried(from: m) : [], nil)
        case .always: return (DraftAttachment.carried(from: m), nil)
        }
    }

    /// Whether a Reply or Reply All of `m` asks Mail's question first: only
    /// under `ask`, and only as Forward asks it.
    static func asks(_ m: Message, mode: Mode = ReplyFiles.mode) -> Bool {
        mode == .ask && forwardAsks(m)
    }

    /// Whether Forward asks Mail's question: when the original has a file
    /// the header lists (`Message.listedAttachments`). A signature's logo,
    /// or any picture the body shows, alone asks nothing.
    static func forwardAsks(_ m: Message) -> Bool {
        !m.listedAttachments.isEmpty
    }

    // MARK: - Following his recipients

    /// The letter's rows, `attachments`, once it is to `to`, `cc` and
    /// `bcc`, each entry as the fields keep it: the rule's rows put in after
    /// them when someone is new and they are not in, the rule's rows taken
    /// out again when no one new is left, and nil when nothing changes.
    mutating func recipientsChanged(to: [String], cc: [String], bcc: [String],
                                    in attachments: [DraftAttachment]) -> [DraftAttachment]? {
        let someoneNew = isNew(to + cc + bcc)
        switch (state, someoneNew) {
        case (.notCarried, true):
            state = .carriedAuto
            return attachments + rows
        case (.carriedAuto, false):
            state = .notCarried
            return attachments.filter { !rows.contains($0) }
        default:
            return nil
        }
    }

    /// Whether `recipientsChanged` would put the rows in now, with these
    /// recipients, changing nothing: what Send asks of everyone the letter
    /// would go to, what he is still typing included.
    func wouldAdd(to: [String], cc: [String], bcc: [String]) -> Bool {
        state == .notCarried && isNew(to + cc + bcc)
    }

    /// His Remove took `row` off. One of the rule's while it carries them,
    /// and the rule stops for the letter; any other changes nothing.
    mutating func removed(_ row: DraftAttachment) {
        guard state == .carriedAuto, rows.contains(row) else { return }
        state = .hisChoice
    }

    /// Whether anyone in `entries` is not among the original's people. Each
    /// split as the letter's envelope splits it (`Submission.recipients`),
    /// an empty group and an entry with no address in it no one.
    func isNew(_ entries: [String]) -> Bool {
        entries.flatMap(MailFormat.addresses(in:)).contains { entry in
            guard !MailFormat.isEmptyGroup(entry), let key = Self.key(entry) else { return false }
            return !people.contains(key)
        }
    }

    /// Everyone `m` names in its From, Reply-To, To, Cc and Bcc.
    static func people(of m: Message) -> Set<String> {
        let named = (m.from.isEmpty ? [m.sender] : m.from) + [m.senderAddress]
            + m.replyTo + m.to + m.cc + m.bcc
        return Set(named.flatMap(MailFormat.addresses(in:)).compactMap(key))
    }

    /// The address in `entry`, bare and in lower case, as compared: read
    /// from its first line, where the letter's envelope reads it
    /// (`RFC5322Builder.recipientLine`). Nil for an entry with no address.
    static func key(_ entry: String) -> String? {
        let line = RFC5322Builder.recipientLine(entry)
        if let recipient = MailFormat.recipient(in: line) { return recipient.address.lowercased() }
        return OwnAddresses.key(line)
    }
}
