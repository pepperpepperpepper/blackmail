import Foundation

/// Where he is in the message list, taken before its rows are rebuilt and
/// put back after: the rows he can see, by the letters in them, how far
/// down the pane each one sits, and which rows are selected.
///
/// Out of `MessageListViewController` for the reason `SearchAnswer` is: the
/// controller is UIKit and does not exist on the machine the suite runs on.
/// The controller measures, and scrolls and selects as it is told.
///
/// Every change to the list's letters rebuilds its rows from scratch and
/// reloads the table (`MessageListViewController.regroup`), and a reloaded
/// table keeps its scroll offset and nothing else: not which letter is at
/// the top of the pane, and not which rows are highlighted. Both used to be
/// carried across by row NUMBER, which grouping makes wrong. A page of newer
/// mail loaded above, after a date jump, does not simply add rows over the
/// ones on screen: a newer letter in a conversation already listed takes
/// that conversation's row up to where its newest letter now is. The offset
/// was corrected by the change in the row count, so every such conversation
/// below the top of the pane slipped the list a row, and one above it did
/// not; measured on the host with the real grouping, 0 to 3 rows a page. And
/// the highlight was read back by index after the rows had been rebuilt, so
/// on every page that added rows it went to whatever row now had the old
/// row's number.
///
/// So both are held by letter now. A row is found again by the id of its
/// newest letter, which is what it stays headed by unless newer mail joined
/// it; and failing that by any letter in it, for rows merged or split by
/// the grouping switch.
struct ListPlace: Equatable {

    /// A row he could see.
    struct Seen: Equatable {
        /// The row's id: its newest letter's (`MessageThread.id`).
        let id: String
        /// Every letter in the row.
        let letters: [String]
        /// How far the row's top is below the top of the pane, in points.
        /// Negative for a row partly scrolled off the top.
        let offset: Double
    }

    /// The rows he could see, top first.
    let seen: [Seen]
    /// The selected rows, by their ids: the letter open in the reading pane,
    /// or in Edit mode his ticks.
    let selected: [String]

    /// Taken from the rows as they are BEFORE they are rebuilt, which is the
    /// whole point: `visible` and `selected` are row numbers in `rows`, and
    /// they mean nothing in the rows that replace them.
    init(rows: [MessageThread], visible: [(row: Int, offset: Double)], selected: [Int]) {
        seen = visible
            .filter { rows.indices.contains($0.row) }
            .map { Seen(id: rows[$0.row].id, letters: rows[$0.row].messages.map(\.id),
                        offset: $0.offset) }
        self.selected = selected.filter(rows.indices.contains).map { rows[$0].id }
    }

    /// Where he was, in `rows`: the row to put back in place, and how far
    /// below the top of the pane its top goes. Nil when none of the rows he
    /// could see is in `rows` at all.
    ///
    /// The first row he could see that is still headed by the same letter
    /// stays exactly where it was on screen, and the rows around it with it.
    /// A row newer mail has joined has moved up the list, to where that mail
    /// is, so it is passed over for the next one he could see: the rows he
    /// was reading stay put, and the one that moved is simply no longer
    /// among them. The same goes for a row taken off by a Delete. Only if
    /// every one of them has changed is a row found by any letter in it,
    /// which is what the grouping switch does to every row at once.
    func landing(in rows: [MessageThread]) -> (row: Int, offset: Double)? {
        var headed: [String: Int] = [:]
        for (i, row) in rows.enumerated() { headed[row.id] = i }
        for row in seen {
            if let i = headed[row.id] { return (i, row.offset) }
        }
        var holding: [String: Int] = [:]
        for (i, row) in rows.enumerated() {
            for letter in row.messages where holding[letter.id] == nil { holding[letter.id] = i }
        }
        for row in seen {
            for letter in row.letters {
                if let i = holding[letter] { return (i, row.offset) }
            }
        }
        return nil
    }

    /// The rows to select in `rows`, found by the letters they held
    /// (`ListEdit.selectedRows`).
    func selection(in rows: [MessageThread], opened: String?, editing: Bool) -> [Int] {
        ListEdit.selectedRows(in: rows, kept: selected, opened: opened, editing: editing)
    }

    /// The scroll offset that puts a row whose top is at `rowTop` in the
    /// content `offset` points below the top of the pane, kept within
    /// `range`, the offsets the table can scroll to. Near the end of a short
    /// list there is not always room below to put it that high, and the
    /// list stops at its end.
    ///
    /// Nil when the row is there already at `current`, the offset the table
    /// has: then nothing is touched. Compared before it is kept in range,
    /// because a list bouncing past either end is outside it, and a regroup
    /// that moved nothing, a page appended below or a letter marked read,
    /// would otherwise snap it back under his finger.
    static func contentOffset(rowTop: Double, offset: Double, range: ClosedRange<Double>,
                              current: Double) -> Double? {
        let y = rowTop - offset
        guard abs(y - current) >= 0.5 else { return nil }
        let kept = min(max(y, range.lowerBound), range.upperBound)
        return abs(kept - current) >= 0.5 ? kept : nil
    }
}

/// Where the list goes when what it shows is replaced, and where the
/// folder's letters were while a search showed in their place.
///
/// The rows used to be replaced under whatever scroll offset the last ones
/// had. A search, a Refresh or a cancelled search started from far down a
/// folder left the newest hits above the top of the pane, or showed a stretch
/// of empty pane below the end of a short result set, with "No results" or
/// "Could not search" somewhere up out of sight: it read as the search not
/// having found the letter. And cancelling a search put the folder back at
/// whatever depth the results had been scrolled to.
struct ListPlaces {

    enum Move: Equatable {
        /// To the top: a list that has been replaced starts at its first
        /// row, the newest.
        case top
        /// Back to a place he left.
        case back(ListPlace)
        /// Where he is: the rows he can see stay where they are.
        case stay
    }

    /// Where he was in the folder's letters when a search's results took
    /// their place.
    private(set) var folder: ListPlace?

    /// A search's results, or a search that could not be run, in place of
    /// what was showing: to the top, where the first hits are. When they
    /// replace the folder's letters, `here` is where he was in them, kept
    /// for when the search ends. Results replacing results keep the
    /// folder's place as it was.
    mutating func resultsShown(overFolder: Bool, here: ListPlace?) -> Move {
        if overFolder { folder = here }
        return .top
    }

    /// The folder's letters back, without a round trip: to where he was in
    /// them when the search began, by the letters he could see, not by the
    /// offset, since the rows can have changed under the search. To the top
    /// if nothing of that is left. With no results showing, nothing on
    /// screen was replaced, and nothing moves.
    mutating func searchEnded(showingResults: Bool) -> Move {
        defer { folder = nil }
        guard showingResults else { return .stay }
        return folder.map(Move.back) ?? .top
    }

    /// The list fetched afresh from the top, by a Refresh or on opening it,
    /// or opened at a day: whatever place was kept belongs to rows that are
    /// gone.
    mutating func replaced() -> Move {
        folder = nil
        return .top
    }

    /// Whether letters the watch has found go on the list now, at the top,
    /// or are held (`ListLetters.hold`, B-049).
    ///
    /// Now only when he is at the very top of the folder's letters, with no
    /// search showing, nothing ticked in Edit mode, and no finger on the
    /// list. Then they go on as they do in Mail: the new rows at the top,
    /// the rows below moved down by as many, and the list left at the top,
    /// where he sees them come. The letter open in the reading pane stays
    /// open and its row highlighted, wherever it now is; that is his
    /// selection, and it is found again by its letter (`ListPlace`).
    ///
    /// Anywhere else nothing on the list changes at all, not a row, not a
    /// tick, not the highlight: scrolled down, a row joined by a newer letter
    /// would move up out from under him, and a row taken out elsewhere would
    /// close the gap under his thumb. The letters wait, and go on the moment
    /// he is back at the top: scrolled there, the search ended with the
    /// folder at its top, out of Edit mode or the last tick taken off, the
    /// finger lifted from a drag; a finger lifted from a tap, which tells
    /// the list nothing, at the next check. A Refresh, or anything else that
    /// fetches the list afresh, lists them with the rest.
    static func showsNews(atTop: Bool, searching: Bool, ticked: Bool, touching: Bool) -> Bool {
        atTop && !searching && !ticked && !touching
    }

    /// Whether a table scrolled to `offset` is at its top, the first row's
    /// top against the top of the pane: `topInset` is the table's top
    /// content inset, which the offset is measured from. Within half a
    /// point, as `ListPlace.contentOffset` compares.
    static func isAtTop(offset: Double, topInset: Double) -> Bool {
        offset <= -topInset + 0.5
    }

    /// The list fetched afresh after an edit of his own: a Delete or a Move
    /// from Edit mode, or a draft saved, sent or deleted in Drafts. He was
    /// working where he was, and the rows he could see stay there, `here`,
    /// if the newest page has them; to the top if he was further down than
    /// it reaches. From a search's results, the folder comes back in their
    /// place, and where he was in it, as when the search is cancelled.
    mutating func refetched(here: ListPlace) -> Move {
        defer { folder = nil }
        return .back(folder ?? here)
    }
}
