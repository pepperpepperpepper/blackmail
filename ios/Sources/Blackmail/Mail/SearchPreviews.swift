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
/// A letter drawn with no words, as a draft begun and put aside has none,
/// is kept as drawn too, with an empty preview, and is not asked for again
/// (B-135's check, on the test iPad 2026-10-25). A row shows no preview the
/// same whether its letter was drawn with none or never drawn, and only
/// rows with a preview used to be kept, so each pause in his typing asked
/// again for the empty drafts among the hits, and each answer was nothing
/// again. For the same reason the folder's own rows drawn with none are
/// kept here, where a Refresh, a cancelled search and a page look
/// (`ListLetters.toDraw`): the folder's rows hold their words themselves,
/// but not that they have none. Words kept here are a hit's to take, not a
/// folder row's, so a folder row with none whose letter is kept with words
/// is asked for (`hasDrawn`).
///
/// Bounded: the last 300 drawn, the one drawn longest ago going first. A
/// preview is at most 240 characters (`PreviewText.maximumCharacters`), so
/// this is at most a few hundred kilobytes, and a few dozen as a rule.
/// Held by the list, it goes with the list: another folder or another
/// account is another list.
struct SearchPreviews {

    /// The most kept: six pages of hits.
    static let most = 300

    /// Each letter drawn, its preview: empty for one drawn with no words.
    /// A letter not here has not been drawn, or was drawn longest ago.
    private var texts: [String: String] = [:]
    /// The keys, the one drawn longest ago first.
    private var order: [String] = []

    var count: Int { texts.count }

    /// Whether `row`'s preview has been drawn: it has one, or its letter is
    /// kept here as drawn with no words. What the list's pass is not to ask
    /// for.
    ///
    /// A row with none whose letter is kept with words is not drawn: only a
    /// hit takes the words kept here (`carrying(into:from:)`), and a row of
    /// the folder never does. Its answer came after the list was replaced
    /// (`ListLetters.previewsCameLate`), as when he starts typing before the
    /// Inbox's previews land, or its letter was drawn as a hit before the
    /// folder's page that holds it was loaded. Said drawn, it would be left
    /// two grey lines and never asked for, after a cancelled search, every
    /// Refresh and on its page, until 300 others were drawn.
    func hasDrawn(_ row: MessageSummary) -> Bool {
        !row.preview.isEmpty || texts[Self.key(row)]?.isEmpty == true
    }

    /// What tells a letter: its folder, its id and Gmail's id for it, or
    /// nothing in the last place where it has none.
    static func key(_ row: MessageSummary) -> String {
        "\(row.mailboxID)\u{0}\(row.id)\u{0}\(row.gmailMessageID.map { String($0) } ?? "")"
    }

    /// Keeps what `rows` have drawn, the newest last: each row's preview,
    /// and a row with none as a letter drawn with no words. Every row
    /// handed in is drawn: one an answer drew, with words or with none
    /// (`ListLetters.apply(previews:in:)`, `previewsCameLate`), or one that
    /// has its preview, took it, or whose letter is kept as drawn with none
    /// (`hasDrawn`). A row not drawn is never handed in, or its letter would
    /// not be asked for again.
    mutating func note(_ rows: [MessageSummary]) {
        for row in rows {
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
    /// kept here. Nothing else of a hit is touched. A hit whose letter is
    /// kept as drawn with no words stays with none, and `hasDrawn` says it
    /// is drawn.
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
