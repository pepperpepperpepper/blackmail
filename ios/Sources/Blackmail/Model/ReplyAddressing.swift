import Foundation

/// Whom a Reply or a Reply All goes to, worked out as Apple Mail works it
/// out (B-061).
///
/// Three faults, found in the gap review of 2026-09-30, all in the few lines
/// this replaces, which addressed every reply to the letter's From:
///
/// - A letter with a Reply-To was answered to its From. A mailing list sets
///   Reply-To to the list, a shop to its service desk, a friend writing from
///   work to the address at home; Mail answers the Reply-To.
/// - A letter of his own, in Sent Mail, in the Inbox when he sent it to an
///   address that comes back to him, or in a conversation, was answered to
///   himself, its From. Mail answers it to whom it went.
/// - Reply All took his own address out only as the account spells it, so
///   the same mailbox written another way, `Owner_Example@Gmail.com`,
///   `o.wner_example@gmail.com`, `owner_example+lists@googlemail.com`, all
///   of which Gmail delivers to him, came back at him as a Cc. Reply All
///   also took the names off every recipient, and put everyone in Cc, where
///   Mail keeps the letter's To in To.
///
/// Wrongly addressed mail cannot be called back, so the rules are few, and
/// every one of them is pinned by `ReplyAddressingTests`:
///
/// 1. A letter with one of his addresses in its From is his own. Reply goes
///    to its To, or, with nobody in To, its Cc; Reply All to its To and its
///    Cc, in the same fields. Its Reply-To is not looked at: it says where
///    he wanted answers to him to go, and this answer is his.
/// 2. Any other letter: Reply goes to its Reply-To when it has one, and to
///    everyone in its From otherwise, as RFC 5322 §3.6.3 has it for a
///    letter written by several. Reply All goes to the same, and to the
///    letter's To, in To, and to its Cc, in Cc. The From is left out when
///    there is a Reply-To, as Mail leaves it out: the sender has asked for
///    answers to go there instead.
/// 3. Each address once, compared bare and without regard to case, To
///    before Cc, with its name: the first time it is named, or a later one
///    if the first had none. An entry with no address in it at all, such as
///    `undisclosed-recipients:;` or the stand-in for a letter with no From,
///    is not a recipient and is left out. Each entry is one line, a line
///    break in a name made a space (`MailFormat.recipient(name:address:)`),
///    so the address compared is the address it goes to.
/// 4. His own addresses come out of both fields, unless that would leave
///    the reply going to nobody: then it goes to him, as a letter he sent to
///    himself is answered to himself. Never a copy of his own reply to him
///    otherwise.
/// 5. With nobody left in To but someone in Cc, the Cc move up to To, so the
///    letter is not sent with no To at all.
///
/// Forward is not here: it goes to nobody until he says (`Draft.forwarding`).
struct ReplyAddressing: Equatable {
    var to: [String]
    var cc: [String]

    /// The To and Cc of a reply to `m`, Reply All when `all`, each entry in
    /// the form the composer's field keeps it (`MailFormat.recipientEntry`).
    static func reply(to m: Message, all: Bool, mine: OwnAddresses) -> ReplyAddressing {
        let from = author(of: m)
        let replyTo = m.replyTo.compactMap(MailFormat.recipient(in:))
        let to = m.to.compactMap(MailFormat.recipient(in:))
        let cc = m.cc.compactMap(MailFormat.recipient(in:))
        let his = from.contains { mine.contains($0.address) }

        var first: [MailFormat.Recipient]
        var second: [MailFormat.Recipient] = []
        if his {
            first = all || !to.isEmpty ? to : cc
            if all { second = cc }
        } else {
            first = replyTo.isEmpty ? from : replyTo
            if all {
                first += to
                second = cc
            }
        }
        // Once each across both fields, To first, so a name given only in
        // the Cc names the address in To too.
        let inTo = Set(first.map { $0.address.lowercased() })
        let once = unique(first + second)
        first = once.filter { inTo.contains($0.address.lowercased()) }
        second = once.filter { !inTo.contains($0.address.lowercased()) }

        let toOthers = first.filter { !mine.contains($0.address) }
        let ccOthers = second.filter { !mine.contains($0.address) }
        let addressed: ([MailFormat.Recipient], [MailFormat.Recipient])
        if toOthers.isEmpty && ccOthers.isEmpty {
            // Nobody but him. His own letter to nobody named, sent by Bcc
            // alone, is answered to him too: to his address in its From,
            // and not to anyone who wrote it with him.
            let him = first.isEmpty ? second : first
            let himInFrom = Array(from.filter { mine.contains($0.address) }.prefix(1))
            addressed = (him.isEmpty && his ? himInFrom : him, [])
        } else if toOthers.isEmpty {
            addressed = (ccOthers, [])
        } else {
            addressed = (toOthers, ccOthers)
        }
        return ReplyAddressing(to: addressed.0.map(\.entry), cc: addressed.1.map(\.entry))
    }

    /// Everyone in the letter's From, each with their name (`Message.from`).
    /// A From of several, `jane@example.com, sam@example.org`, was read as
    /// one entry, as `sender` holds it: one address that is nobody's, which
    /// the composer's field then split, so the reply went to them all by
    /// accident, or with names to the last alone, the others taken for its
    /// name; and a letter of his written with someone else was not his. The
    /// pane's stand-in for a letter with no From, "(unknown sender)", is
    /// nobody.
    private static func author(of m: Message) -> [MailFormat.Recipient] {
        let authors = (m.from.isEmpty ? [m.sender] : m.from).compactMap(MailFormat.recipient(in:))
        if !authors.isEmpty { return authors }
        guard m.senderAddress.contains("@") else { return [] }
        return [MailFormat.recipient(name: m.sender, address: m.senderAddress)]
    }

    private static func same(_ a: MailFormat.Recipient, _ b: MailFormat.Recipient) -> Bool {
        a.address.lowercased() == b.address.lowercased()
    }

    /// Each address once, in the order first met, with the first name it
    /// was given.
    private static func unique(_ list: [MailFormat.Recipient]) -> [MailFormat.Recipient] {
        var out: [MailFormat.Recipient] = []
        for r in list {
            if let i = out.firstIndex(where: { same($0, r) }) {
                if out[i].name == nil, r.name != nil { out[i].name = r.name }
            } else {
                out.append(r)
            }
        }
        return out
    }
}

/// His own addresses: what a reply leaves out, and what makes a letter his.
///
/// Compared as the mailbox they reach rather than as written (`key`): bare,
/// without regard to case, and, for Gmail's own domains, without the dots in
/// the name or anything after a `+`, and with googlemail.com the same as
/// gmail.com, because Gmail delivers every one of those to the same mailbox.
/// Only for Gmail's domains: another server may well give
/// `sam.example@example.org` and `samexample@example.org` to two people,
/// and taking a stranger for him would leave that stranger out of a Reply
/// All, unseen.
///
/// The app knows the account's address and its login. An address of his
/// on another domain that Gmail sends as and delivers to him, as his second
/// address is, is not his here until the owner says how the app is to know
/// it (B-061, decision left to the owner).
struct OwnAddresses {
    private let keys: Set<String>

    init(_ addresses: [String]) {
        keys = Set(addresses.compactMap(Self.key))
    }

    /// The account's address and its login, which is usually the same.
    init(account: MailAccount?) {
        self.init([account?.address, account?.username].compactMap { $0 })
    }

    func contains(_ address: String) -> Bool {
        Self.key(address).map(keys.contains) ?? false
    }

    /// The mailbox `address` reaches, as far as can be told from the
    /// address: lower case, and Gmail's spellings of one mailbox made one.
    /// Nil for anything with no `@` in it.
    static func key(_ address: String) -> String? {
        let bare = MailFormat.bareAddress(address).lowercased()
        guard let at = bare.lastIndex(of: "@") else { return nil }
        var local = String(bare[..<at])
        var domain = String(bare[bare.index(after: at)...])
        guard !local.isEmpty, !domain.isEmpty else { return nil }
        if domain == "gmail.com" || domain == "googlemail.com" {
            var name = local
            if let plus = name.firstIndex(of: "+") { name = String(name[..<plus]) }
            name = name.replacingOccurrences(of: ".", with: "")
            // A name that is nothing but dots and a tag is no Gmail
            // mailbox: kept as written, so it matches only itself.
            if !name.isEmpty {
                local = name
                domain = "gmail.com"
            }
        }
        return local + "@" + domain
    }
}

extension MailFormat {

    /// One recipient: the address alone, and the name it was given, if any.
    struct Recipient: Equatable {
        var name: String?
        var address: String

        /// As the composer's field keeps it (`recipientEntry`).
        var entry: String { MailFormat.recipientEntry(name: name, address: address) }
    }

    /// The recipient in one entry of a To, Cc, Reply-To or From header, as
    /// the letter carries it once decoded: `Jane Example <jane@example.com>`,
    /// `"Example, Jane" <jane@example.com>`, `jane@example.com`,
    /// `jane@example.com (Jane Example)`, `Friends: jane@example.com`, or
    /// an entry whose comma came out of an encoded word,
    /// `Example, Jane <jane@example.com>`, which is one recipient because it
    /// is one entry. Nil for an entry with no address in it: an empty group,
    /// `undisclosed-recipients:;`, a bare name, or "(unknown sender)", none
    /// of which mail can be sent to.
    ///
    /// The recipient is on one line (`recipient(name:address:)`), whatever
    /// the letter's header held.
    static func recipient(in entry: String) -> Recipient? {
        var t = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        // A group, `Name: members;`. The colon only counts outside quotes
        // and before any address, so `"Re: Jane" <jane@example.com>` is not
        // one.
        if let colon = groupColon(in: t) {
            t = String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        while t.hasSuffix(";") { t = String(t.dropLast()).trimmingCharacters(in: .whitespaces) }

        var name: String?
        var address: String
        if let open = t.lastIndex(of: "<"), let close = t.lastIndex(of: ">"), open < close {
            address = String(t[t.index(after: open)..<close])
            name = unquoted(String(t[..<open]))
        } else if t.hasSuffix(")"), let open = t.firstIndex(of: "(") {
            // The old form: the address, then the name as a comment.
            address = String(t[..<open])
            name = unquoted(String(t[t.index(after: open)..<t.index(before: t.endIndex)]))
        } else {
            address = t
        }
        guard address.contains("@") else { return nil }
        return recipient(name: name, address: address)
    }

    /// A recipient from a name and an address as a letter gave them, each
    /// on one line: every line break and control character in the name made
    /// a space (`oneLine`), any in the address taken out, and the name
    /// dropped when it is empty or the address again.
    ///
    /// A letter's header can carry them in a name, in an encoded word,
    /// `=?UTF-8?Q?Jane=E2=80=A8Example?=`, and innocently: a Windows "…"
    /// sent as ISO-8859-1 is byte 0x85, U+0085, NEXT LINE, once decoded.
    /// Kept, a reply's entry was two lines, which the letter's two halves
    /// read differently: the envelope took the address from the entry's
    /// first line, and the header from all of it. A From named
    /// `Jane<U+2028>Example <jane@example.com>` was answered with
    /// `RCPT TO:<Jane>`, and a To named `<other@example.net><LF>Sam` with
    /// `sam@example.org` sent the reply to other@example.net with Sam in
    /// its header, an address never compared with his or anyone's. Both
    /// halves read the first line now (`RFC5322Builder.recipientLine`), and
    /// a reply's entry is all one line, so its last `<…>` is its address,
    /// the one compared, in the field, the header and the envelope alike.
    static func recipient(name: String?, address: String) -> Recipient {
        var kept = String.UnicodeScalarView()
        kept.append(contentsOf: address.unicodeScalars.filter { !breaksLine($0) })
        let address = String(kept).trimmingCharacters(in: .whitespaces)
        var name = name.map { oneLine($0).trimmingCharacters(in: .whitespaces) }
        if let n = name, n.isEmpty || n.caseInsensitiveCompare(address) == .orderedSame {
            name = nil
        }
        return Recipient(name: name, address: address)
    }

    /// `text` on one line: each line break or control character in it, or
    /// run of them, made one space (`breaksLine`).
    static func oneLine(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var gap = false
        for scalar in text.unicodeScalars {
            if breaksLine(scalar) {
                if !gap { out.append(" ") }
                gap = true
            } else {
                out.append(scalar)
                gap = false
            }
        }
        return String(out)
    }

    /// A line break or a control character: anything below U+0020, U+007F
    /// to U+009F, NEXT LINE among them, and LINE and PARAGRAPH SEPARATOR,
    /// U+2028 and U+2029. Every character Swift counts a line break
    /// (`Character.isNewline`) is one of these.
    private static func breaksLine(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value)
            || scalar.value == 0x2028 || scalar.value == 0x2029
    }

    /// `name` without the quotes around it, and a quoted pair inside as the
    /// character it stands for; nil when nothing is left.
    private static func unquoted(_ name: String) -> String? {
        var n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.count >= 2, n.hasPrefix("\""), n.hasSuffix("\"") {
            var out = ""
            var escaped = false
            for c in n.dropFirst().dropLast() {
                if escaped || c != "\\" {
                    out.append(c)
                    escaped = false
                } else {
                    escaped = true
                }
            }
            n = out
        } else if n.count >= 2, n.hasPrefix("'"), n.hasSuffix("'") {
            n = String(n.dropFirst().dropLast())
        }
        n = n.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? nil : n
    }

    /// Where a group's name ends: the first colon outside quotes, with no
    /// `@` or `<` before it.
    private static func groupColon(in entry: String) -> String.Index? {
        var quoted = false
        var escaped = false
        for i in entry.indices {
            let c = entry[i]
            if escaped { escaped = false; continue }
            switch c {
            case "\\" where quoted: escaped = true
            case "\"": quoted.toggle()
            case "@" where !quoted, "<" where !quoted: return nil
            case ":" where !quoted: return i
            default: break
            }
        }
        return nil
    }

    /// One recipient as the composer's field keeps it, and as it goes in
    /// the letter's header: `Jane Example <jane@example.com>`, the address
    /// alone where there is no name, and the name in quotes where it holds
    /// anything the field or the header would read as more than a name, a
    /// comma above all. `"Example, Jane" <jane@example.com>` is one
    /// recipient in the field (`addresses(in:)`); unquoted, the comma would
    /// make it two, the first of them `Example`, which mail cannot be sent
    /// to.
    static func recipientEntry(name: String?, address: String) -> String {
        guard let name, !name.isEmpty, name != address else { return address }
        let specials = "()<>@,;:\\\".[]"
        guard name.contains(where: { specials.contains($0) }) else {
            return "\(name) <\(address)>"
        }
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\" <\(address)>"
    }

    /// An entry of a letter's To, Cc or Bcc as the composer's field keeps
    /// it (`recipientEntry`), or as it came when there is no address in it
    /// to keep: that is his to see and mend, not this to drop. On one line
    /// either way (`recipient(name:address:)`, `oneLine`), so that what a
    /// draft reopened from Drafts sends to is what its field shows.
    static func fieldEntry(_ entry: String) -> String {
        recipient(in: entry)?.entry ?? oneLine(entry).trimmingCharacters(in: .whitespaces)
    }
}
