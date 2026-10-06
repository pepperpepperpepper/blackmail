import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// An address field as Mail's has it: each recipient a bubble with the
/// person's name on it, and after them what he is still typing (B-076).
///
/// Underneath, each bubble is one recipient as the composer keeps it
/// (`MailFormat.recipientEntry`), and what he is typing after them is split
/// as the field's text always was (`recipients`). Send, Cancel, the
/// suggestions, the autosave, a draft and the letter read that. They used to
/// read the field written out as text, every bubble and a comma after it,
/// and split it again; one bubble with a quote never closed in it then split
/// every bubble at its commas, and the letter went to people the field did
/// not show (B-076).
///
/// Mail's ways, each here: a pick, or an address he ends with a comma,
/// Return or by leaving the field, becomes a bubble; backspace with nothing
/// typed picks out the last bubble, and a second takes it off; a bubble
/// tapped is picked out, and shows its address.
struct RecipientBubbles: Equatable {

    /// One per bubble, each as the field keeps it.
    private(set) var entries: [String] = []
    /// What he is typing after the bubbles, not yet one.
    private(set) var typed = ""
    /// The bubble picked out, by a backspace or a tap: the next backspace
    /// takes it off.
    private(set) var selected: Int?
    /// How many bubbles leaving the field made of what he typed, which a
    /// pick still in flight takes the place of (`pick`).
    private var leftWith = 0

    init() {}

    /// The field as a letter's To, Cc or Bcc has it: a bubble each. Each
    /// entry split on its own, as the field's text always was
    /// (`MailFormat.addresses(in:)`), so an entry holding several is a
    /// bubble for each, and one with a quote never closed in it cannot
    /// change how the others are split.
    init(entries: [String]) {
        self.entries = entries.flatMap { MailFormat.addresses(in: $0) }
    }

    /// Whom the field sends to: a recipient for each bubble, as it is, then
    /// what he is typing after them, split as the field's text always was.
    /// What Send, Cancel, the suggestions, a draft and the letter read, so
    /// the letter goes to the people the bubbles show.
    var recipients: [String] {
        entries + MailFormat.addresses(in: typed)
    }

    // MARK: - What a bubble says

    /// The words on a bubble: the person's name, or the address where the
    /// letter gives none or the name is the address again
    /// (`MailFormat.recipient(name:address:)`). An entry with no address in
    /// it shows as it is, for him to see and mend.
    ///
    /// Read from the entry's first line (`RFC5322Builder.recipientLine`),
    /// as the letter's header and its envelope read it (B-061), so the
    /// bubble names whom the letter goes to. Read from all of it, a
    /// `mailto:` link's `sam@example.org%0A%3Cother@example.net%3E` showed
    /// other@example.net under a letter sent to sam@example.org.
    static func words(for entry: String) -> String {
        let line = RFC5322Builder.recipientLine(entry)
        guard let r = MailFormat.recipient(in: line) else {
            return MailFormat.oneLine(line).trimmingCharacters(in: .whitespaces)
        }
        return r.name ?? r.address
    }

    /// The address under a bubble, shown when it is tapped and given to
    /// VoiceOver; nil when the entry holds none. From the entry's first
    /// line, as `words(for:)`, the header and the envelope read it.
    static func address(for entry: String) -> String? {
        MailFormat.recipient(in: RFC5322Builder.recipientLine(entry))?.address
    }

    // MARK: - Where a bubble is drawn

    /// Where a bubble drawn in `pill` takes a tap: the pill, grown evenly
    /// to `side` each way where it is smaller, so a bubble drawn shorter
    /// than its line takes a tap anywhere on the line's height. `side` is
    /// `Theme.minHitTarget`, binding for every tappable control (D-007).
    static func touchArea(of pill: CGRect, atLeast side: CGFloat) -> CGRect {
        pill.insetBy(dx: min(0, (pill.width - side) / 2), dy: min(0, (pill.height - side) / 2))
    }

    /// How many bubbles at the start, and then at the end, are the same
    /// people as before the field changed from `old` to `new`. Those keep
    /// their buttons, so a bubble made after the others, or one taken off
    /// between them, leaves every other one where it was, the one a menu
    /// hangs from among them; only the rest are made again.
    static func unchanged(from old: [String], to new: [String]) -> (head: Int, tail: Int) {
        var head = 0
        while head < old.count, head < new.count, old[head] == new[head] { head += 1 }
        var tail = 0
        while tail < old.count - head, tail < new.count - head,
              old[old.count - 1 - tail] == new[new.count - 1 - tail] { tail += 1 }
        return (head, tail)
    }

    // MARK: - What he does

    /// He has typed, or taken out, after the bubbles, which now reads
    /// `now`. Each recipient he has ended with a comma becomes a bubble. A
    /// comma inside quotes, `<…>` or a comment ends nothing: `"Example,
    /// Jane" <jane@example.com>` is one recipient as he types it.
    mutating func type(_ now: String) {
        selected = nil
        leftWith = 0
        let (done, rest) = Self.ended(now)
        entries += done
        typed = rest
    }

    /// Return, or leaving the field: what he typed becomes a bubble, unless
    /// it is blank. Split as the field's text is split for the letter
    /// (`MailFormat.addresses(in:)`), so the bubbles are what it would have
    /// gone to.
    mutating func finish(leaving: Bool = false) {
        selected = nil
        let done = MailFormat.addresses(in: typed)
        entries += done
        typed = ""
        leftWith = leaving ? done.count : 0
    }

    /// A suggestion picked: a bubble in place of what he typed. Should
    /// leaving the field have made a bubble of that a moment before, as a
    /// tap on the list can, the pick takes its place too, so a name half
    /// typed is not left behind as a recipient.
    mutating func pick(_ entry: String) {
        selected = nil
        if typed.isEmpty, leftWith > 0, leftWith <= entries.count {
            entries.removeLast(leftWith)
        }
        leftWith = 0
        entries.append(entry)
        typed = ""
    }

    /// Backspace with nothing typed after the bubbles, as Mail has it: the
    /// first picks out the last bubble, the next takes it off. With a bubble
    /// already picked out, by a tap or a backspace, that one goes. False
    /// when there was nothing to pick out or take off.
    @discardableResult
    mutating func backspace() -> Bool {
        leftWith = 0
        if let i = selected, entries.indices.contains(i) {
            entries.remove(at: i)
            selected = nil
            return true
        }
        guard !entries.isEmpty else { return false }
        selected = entries.count - 1
        return true
    }

    /// A bubble tapped is picked out; nil puts it back.
    mutating func select(_ index: Int?) {
        selected = index.flatMap { entries.indices.contains($0) ? $0 : nil }
    }

    /// The bubble's Remove.
    mutating func remove(at index: Int) {
        guard entries.indices.contains(index) else { return }
        entries.remove(at: index)
        selected = nil
        leftWith = 0
    }

    /// The recipients `typed` has ended with a comma, each trimmed, blanks
    /// left out, and what is left after the last of them, its leading
    /// spaces taken off. Only a comma outside quotes, `<…>` and a comment
    /// ends one, as `MailFormat.addressList` reads a header; a quote or a
    /// bracket still open is a recipient still being typed, not a broken
    /// header, so nothing after it is ended.
    static func ended(_ typed: String) -> (entries: [String], rest: String) {
        var done: [String] = []
        var entry = ""
        var quoted = false, escaped = false, bracketed = false
        var comments = 0
        for c in typed {
            if escaped {
                escaped = false
                entry.append(c)
                continue
            }
            switch c {
            case "\\" where quoted || comments > 0: escaped = true
            case "\"" where !bracketed && comments == 0: quoted.toggle()
            case "<" where !quoted && comments == 0: bracketed = true
            case ">" where !quoted && comments == 0: bracketed = false
            case "(" where !quoted && !bracketed: comments += 1
            case ")" where !quoted && !bracketed && comments > 0: comments -= 1
            case "," where !quoted && !bracketed && comments == 0:
                let t = entry.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { done.append(t) }
                entry = ""
                continue
            default: break
            }
            entry.append(c)
        }
        let rest = String(entry.drop { $0.isWhitespace || $0.isNewline })
        return (done, rest)
    }
}
