import Foundation

/// The previews a search's hits have drawn, carried to the same letters in
/// the next answer as he types (B-135), as a Refresh carries a folder's
/// (`ListEdit.carryingPreviews`).
///
/// Each pause in his typing brings a new answer, its rows with no previews,
/// and the list's pass used to ask for every one of them again, though
/// "Marga" finds mostly the letters "Marg" found a moment before and drew.
/// A letter's words never change: IMAP gives a UID to one message for the
/// life of its UIDVALIDITY, and Gmail's id (X-GM-MSGID) is the message's
/// own. So a hit takes the preview already drawn for its letter, and only
/// the rest are asked for.
///
/// The same letter is told as a Refresh tells it: the same folder and the
/// same id, which carries the folder's UIDVALIDITY and the UID, and Gmail's
/// id for the letter the same on both rows. Stricter than a Refresh in one
/// way: a row with Gmail's id takes nothing from one without, nor the other
/// way, so a row kept on the iPad from an earlier launch under the same
/// folder and UID, which can be another mailbox's (D-016), or the row a
/// draft kept here drew from its own words (`LocalDrafts`), gives a hit
/// nothing. A letter saved again, as a draft is, is a new UID and so a new
/// id, and takes nothing from the letter it replaced. Not by Gmail's id
/// across folders: an All Mailboxes hit, under All Mail's id, does not take
/// the preview the Inbox's row of its letter drew, so nothing here rests on
/// Gmail never giving a changed letter its old id. Only the preview goes
/// across: the read mark, the flag and everything else a hit shows are the
/// new answer's, and those can have changed.
///
/// Bounded: the last 300 drawn, the one drawn longest ago going first. A
/// preview is at most 240 characters (`PreviewText.maximumCharacters`), so
/// this is at most a few hundred kilobytes, and a few dozen as a rule.
/// Held by the list, it goes with the list: another folder or another
/// account is another list.
struct SearchPreviews {

    /// The most kept: six pages of hits.
    static let most = 300

    private var texts: [String: String] = [:]
    /// The keys, the one drawn longest ago first.
    private var order: [String] = []

    var count: Int { texts.count }

    /// What tells a letter: its folder, its id and Gmail's id for it, or
    /// nothing in the last place where it has none.
    static func key(_ row: MessageSummary) -> String {
        "\(row.mailboxID)\u{0}\(row.id)\u{0}\(row.gmailMessageID.map { String($0) } ?? "")"
    }

    /// Keeps the previews `rows` have drawn, the newest last; those with
    /// none are passed over.
    mutating func note(_ rows: [MessageSummary]) {
        for row in rows where !row.preview.isEmpty {
            let key = Self.key(row)
            if texts.updateValue(row.preview, forKey: key) != nil,
               let at = order.firstIndex(of: key) {
                order.remove(at: at)
            }
            order.append(key)
        }
        let over = order.count - Self.most
        guard over > 0 else { return }
        for key in order.prefix(over) { texts[key] = nil }
        order.removeFirst(over)
    }

    /// `hits` with a preview put in where they have none: that of the same
    /// letter among `rows`, the list's own, or failing that among those
    /// kept here. Nothing else of a hit is touched.
    func carrying(into hits: [MessageSummary], from rows: [MessageSummary]) -> [MessageSummary] {
        guard hits.contains(where: { $0.preview.isEmpty }) else { return hits }
        var known: [String: String] = [:]
        for row in rows where !row.preview.isEmpty { known[Self.key(row)] = row.preview }
        guard !known.isEmpty || !texts.isEmpty else { return hits }
        return hits.map { hit in
            guard hit.preview.isEmpty else { return hit }
            let key = Self.key(hit)
            guard let text = known[key] ?? texts[key] else { return hit }
            var carried = hit
            carried.preview = text
            return carried
        }
    }
}
