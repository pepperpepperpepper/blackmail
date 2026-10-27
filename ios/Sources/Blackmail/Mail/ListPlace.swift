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
/// So both are held by letter now. A row is found again by its id, the
/// letter the list has first in it (`MessageThread.id`), which is what it
/// stays headed by unless newer mail joined it; and failing that by any
/// letter in it, for rows merged or split by the grouping switch.
///
/// And the row just above the first he can see is kept too, the one on
/// screen under the bars or the band: when that first row is taken out,
/// it is the one held, and the rows below close up into the gap, as in
/// Mail (`landing`, B-093).
struct ListPlace: Equatable {

    /// A row on screen: one he could see, at least partly below the bars
    /// and the band (`inSight`), or the one just above them (`above`).
    struct Seen: Equatable {
        /// The row's id: the letter the list has first in it
        /// (`MessageThread.id`).
        let id: String
        /// Every letter in the row.
        let letters: [String]
        /// How far the row's top is below the top of the pane, in points.
        /// Negative for a row partly scrolled off the top.
        let offset: Double
    }

    /// The rows he could see, top first.
    let seen: [Seen]
    /// The row on screen just above the first he could see, under the bars
    /// or the band, with less than a point of it in sight (`justAbove`):
    /// the row held when that first row is taken out (`landing`, B-093).
    /// Nil when the first row he could see was the first on screen, at the
    /// top of the list, and for a place taken by its rows alone.
    let above: Seen?
    /// The selected rows, by their ids: the letter open in the reading pane,
    /// or in Edit mode his ticks.
    let selected: [String]

    private init(seen: [Seen], above: Seen?, selected: [String]) {
        self.seen = seen
        self.above = above
        self.selected = selected
    }

    /// The same place, with the letter `old` named `new` wherever it was:
    /// a row put back by its Undo, under the new UID the move back gave it
    /// (B-157), held where it stood, at the same offsets.
    func renaming(_ old: String, to new: String) -> ListPlace {
        func renamed(_ id: String) -> String { id == old ? new : id }
        func renamed(_ row: Seen) -> Seen {
            Seen(id: renamed(row.id), letters: row.letters.map(renamed), offset: row.offset)
        }
        return ListPlace(seen: seen.map(renamed), above: above.map(renamed),
                         selected: selected.map(renamed))
    }

    /// Taken from the rows as they are BEFORE they are rebuilt, which is the
    /// whole point: `visible`, `above` and `selected` are row numbers in
    /// `rows`, and they mean nothing in the rows that replace them.
    init(rows: [MessageThread], visible: [(row: Int, offset: Double)],
         above: (row: Int, offset: Double)? = nil, selected: [Int]) {
        func seen(_ row: (row: Int, offset: Double)) -> Seen {
            Seen(id: rows[row.row].id, letters: rows[row.row].messages.map(\.id),
                 offset: row.offset)
        }
        self.seen = visible.filter { rows.indices.contains($0.row) }.map(seen)
        self.above = above.flatMap { rows.indices.contains($0.row) ? seen($0) : nil }
        self.selected = selected.filter(rows.indices.contains).map { rows[$0].id }
    }

    /// The same, from the rows the table has on screen, each by its top and
    /// bottom as `rectForRow` gives them, and what of the table is in
    /// sight: the rows he can see are the ones taken (`inSight`), and the
    /// row on screen just above them (`justAbove`).
    init(rows: [MessageThread], onScreen: [(row: Int, top: Double, bottom: Double)],
         sight: TableSight, selected: [Int]) {
        self.init(rows: rows, visible: Self.inSight(onScreen, sight: sight),
                  above: Self.justAbove(onScreen, sight: sight), selected: selected)
    }

    /// Of the rows on screen, top first, the ones he can see, with how far
    /// each one's top is below the top of the pane (B-093): every row with
    /// a point or more of it between the bars, below the search band
    /// pinned at the top (`TableSight.showsPart`).
    ///
    /// The table runs on under its bars, and the rows it has on screen are
    /// every row in its bounds: at the top, one or two under the status and
    /// navigation bars and the band, where he cannot see them. The first of
    /// those used to be the row held. A letter whose row was out of sight
    /// just above the top of the list, deleted from the reading pane, took
    /// its row out between the row held and the rows he could see, and
    /// every row in view moved up by one at once. Held by the first row he
    /// can see, a row taken out above it closes out of sight, and so does
    /// one that newer mail takes up the list, or one put back. The offsets
    /// are still from the top of the pane, the table's bounds, which is
    /// what `contentOffset` puts back.
    ///
    /// Every row on screen if none of them is in sight: a pane too short
    /// for a row below the band, or one not laid out. Holding them is no
    /// worse than holding nothing.
    static func inSight(_ onScreen: [(row: Int, top: Double, bottom: Double)],
                        sight: TableSight) -> [(row: Int, offset: Double)] {
        let seen = onScreen.filter { sight.showsPart(CGFloat($0.top), CGFloat($0.bottom)) }
        return (seen.isEmpty ? onScreen : seen).map { ($0.row, $0.top - Double(sight.offset)) }
    }

    /// The row on screen just above the first he can see (`inSight`), with
    /// how far its top is below the top of the pane: under the bars and the
    /// band, less than a point of it in sight. Nil when the first row he
    /// can see is the first on screen, and when none is in sight, since
    /// then every row on screen is taken.
    static func justAbove(_ onScreen: [(row: Int, top: Double, bottom: Double)],
                          sight: TableSight) -> (row: Int, offset: Double)? {
        guard let first = onScreen.firstIndex(where: {
            sight.showsPart(CGFloat($0.top), CGFloat($0.bottom))
        }), first > 0 else { return nil }
        let row = onScreen[first - 1]
        return (row.row, row.top - Double(sight.offset))
    }

    /// Where he was, in `rows`: the row to put back in place, and how far
    /// below the top of the pane its top goes. Nil when none of the rows he
    /// could see is in `rows` at all, nor, the first of them taken out, the
    /// row above it.
    ///
    /// The first row he could see that is still headed by the same letter
    /// stays exactly where it was on screen, and the rows around it with it.
    /// A row taken out above it, under the bars and the band, closes out of
    /// sight; one taken out below it, the rows below close up. A row newer
    /// mail has joined has moved up the list, to where that mail is, so it
    /// is passed over for the next one he could see: the rows he was
    /// reading stay put, and the one that moved is simply no longer among
    /// them. Only if every one of them has changed is a row found by any
    /// letter in it, which is what the grouping switch does to every row at
    /// once.
    ///
    /// When the first row he could see has itself gone from its place,
    /// taken out by a Delete or a Move, the rows below close up into it, as
    /// in Mail (`closingUp`, B-093). It used to be passed over like a row
    /// newer mail had joined: the rows below stayed, and the row above,
    /// out of sight under the search field, came down into its place. Which
    /// of the two he got turned on a point: with a point of the row above
    /// in sight, that row was the first he could see, and the rows below
    /// closed up. A point of the letter's own row still decides which row
    /// it is: with less than a point of it in sight, it is the row above
    /// the first he can see, and closes out of sight; with a point or more,
    /// it is the first, and the rows below close up into it, every row in
    /// view a row up.
    func landing(in rows: [MessageThread]) -> (row: Int, offset: Double)? {
        var headed: [String: Int] = [:]
        for (i, row) in rows.enumerated() { headed[row.id] = i }
        var holding: [String: Int] = [:]
        for (i, row) in rows.enumerated() {
            for letter in row.messages where holding[letter.id] == nil { holding[letter.id] = i }
        }
        if let closed = closingUp(in: rows, headed: headed, holding: holding) { return closed }
        for row in seen {
            if let i = headed[row.id] { return (i, row.offset) }
        }
        for row in seen {
            for letter in row.letters {
                if let i = holding[letter] { return (i, row.offset) }
            }
        }
        return nil
    }

    /// Where he was, in `rows`, with the row that carries `letter` held
    /// where it is on screen, if he could see it: the letter heading the
    /// row a date jump opened on, while the pages above it come
    /// (`LandedLetter`, B-117). Otherwise, and with no letter, `landing(in:)`.
    ///
    /// Held while it is headed by the letter that headed it when he saw it,
    /// as every row is that newer mail has not joined: the row stays where
    /// it is on the pane, and the list with it, wherever the rows he could
    /// see above it go.
    ///
    /// Joined by newer mail on the page, the row goes up the list to where
    /// that mail is, dated by it, as Mail's list has it (B-118): the row
    /// now just above the first of the rows he could see under it that
    /// newer mail has not joined takes its place, and those rows close up
    /// under it. In a folder in date order that is the oldest row still
    /// dated on or after the day, the row the jump would open on now
    /// (`ListOpening.dayRow`). On the size test's 23 April 2019 the page
    /// asked for as the day lands answers 18944, the row opened on, on the
    /// 28th; Quinn Doe's 18945 of the 23rd comes into its place, over 18943
    /// of the 22nd. Held where it was, as B-117 had it, the row stayed on
    /// top, dated 28 April, over the rows of the 28th, "Showing April 23"
    /// under them. And where the row under it is answered on the page too,
    /// as on All Mail's 8 April 2021, the day's next row still comes into
    /// the top place, and the rows under it close up; by the rows he could
    /// see alone (`landing(in:)`), the first of them not joined would stay
    /// where it was, a row lower, and a newer row of the day come down on
    /// top. With none of them left, `landing(in:)`.
    func landing(in rows: [MessageThread], holding letter: String?) -> (row: Int, offset: Double)? {
        guard let letter, let at = seen.firstIndex(where: { $0.letters.contains(letter) }),
              let row = rows.firstIndex(where: { $0.messages.contains { $0.id == letter } }) else {
            return landing(in: rows)
        }
        let held = seen[at]
        if rows[row].id == held.id { return (row, held.offset) }
        var headed: [String: Int] = [:]
        for (i, row) in rows.enumerated() { headed[row.id] = i }
        for under in seen[(at + 1)...] {
            if let i = headed[under.id], i > 0 { return (i - 1, held.offset) }
        }
        return landing(in: rows)
    }

    /// Whether `letter` heads a row he could see: is the letter the list
    /// has first in it (`MessageThread.id`).
    func heads(_ letter: String) -> Bool {
        seen.contains { $0.id == letter }
    }

    /// Where a row he could see is in `rows`: headed by the same letter, or
    /// with that letter gone, as what is left of it, the row its other
    /// letters are in and one of them heads. Nil when it is gone, and when
    /// its letters are in a row another letter heads: newer mail has
    /// joined it and taken it up the list, or the grouping switch has
    /// merged it into another.
    private func stands(_ row: Seen, in rows: [MessageThread], headed: [String: Int],
                        holding: [String: Int]) -> Int? {
        if let i = headed[row.id] { return i }
        guard let i = row.letters.lazy.compactMap({ holding[$0] }).first else { return nil }
        return row.letters.contains(rows[i].id) ? i : nil
    }

    /// The first row he could see gone from its place, taken out, or gone
    /// down the list with its newest letter: the rows below close up into
    /// it, as in Mail (B-093). The row on screen just above it, under the
    /// bars or the band, stays where it was (`above`). With none, at the
    /// top of the list, or with that one taken out too, by an Edit-mode
    /// Delete of both, the first of the rows he could see as they stand
    /// now goes where the first was: what is left of it, or the next below.
    ///
    /// Nil, for `landing`'s rule, when the first row is still headed by
    /// the same letter, and when newer mail has joined it and taken it up
    /// the list, or the grouping switch has merged it: as before, the next
    /// row he could see stays where it was.
    private func closingUp(in rows: [MessageThread], headed: [String: Int],
                           holding: [String: Int]) -> (row: Int, offset: Double)? {
        guard let first = seen.first, headed[first.id] == nil else { return nil }
        let joined = first.letters.contains { letter in
            holding[letter].map { !first.letters.contains(rows[$0].id) } ?? false
        }
        guard !joined else { return nil }
        if let above, let i = headed[above.id] { return (i, above.offset) }
        let standing = seen.compactMap { stands($0, in: rows, headed: headed, holding: holding) }
        return standing.min().map { ($0, first.offset) }
    }

    /// Whether the list shows what it showed at `other`: the same rows in
    /// sight, by their ids, each where it was on the pane to half a point,
    /// as `contentOffset` compares. Not the row out of sight above them, nor
    /// which rows are selected, which move nothing he sees.
    func showsTheSame(as other: ListPlace) -> Bool {
        seen.count == other.seen.count && zip(seen, other.seen).allSatisfy {
            $0.id == $1.id && abs($0.offset - $1.offset) < 0.5
        }
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
        /// A row put back, to where he was before it was taken out
        /// (`TakenRows`); where he is, as for `stay`, if nothing of that
        /// place is left.
        case putBack(ListPlace)
        /// Where he is: the rows he can see stay where they are.
        case stay
        /// Where he is, with the row that carries this letter, the one
        /// heading the row a date jump opened on, held where it is on
        /// screen; as for `stay` if he cannot see it, and its place to the
        /// day's next row if newer mail joins it
        /// (`ListPlace.landing(in:holding:)`, B-117, B-118).
        case holding(String)
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

    /// Whether the list, sent to its top, has its offset set there (B-103).
    /// `moving` is a finger on the list, or the list coasting or springing
    /// back. At its top, within half a point, there is nothing to set. Past
    /// it and moving, it is left where it is: under the finger the rows
    /// would jump, and springing back it gets to the top by itself, where
    /// the offset set as it sprang back stopped it at the spinner's rest,
    /// seen on the iPad on 2026-10-22. Past it at rest, as a spinner put
    /// away while the list sprang back left it, and anywhere below it, set,
    /// as it always was: a band left above the first row goes then, at the
    /// next page, mail put on at the top, or a return to the newest.
    static func setsTop(offset: Double, topInset: Double, moving: Bool) -> Bool {
        let top = -topInset
        guard abs(offset - top) > 0.5 else { return false }
        return offset > top || !moving
    }

    /// The list fetched afresh after an edit of his own: a Delete or a Move
    /// from Edit mode, or a draft saved, sent or deleted in Drafts. He was
    /// working where he was, and the rows he could see stay there, `here`,
    /// if the newest page has them; to the top if he was further down than
    /// it reaches. But for one edge: with the first row he could see just
    /// past the end of the page, and the row on screen above it the page's
    /// last, that row is held (`ListPlace.closingUp`), and the list goes to
    /// the end of the page, its last row above the toolbar, rather than to
    /// the top. From a search's results, the folder comes back in their
    /// place, and where he was in it, as when the search is cancelled.
    mutating func refetched(here: ListPlace) -> Move {
        defer { folder = nil }
        return .back(folder ?? here)
    }
}

/// The letter heading the row a date jump opened on, held where he sees it
/// as the pages above it come, until he moves the list himself (B-117).
///
/// A jump opens on the row Mail's list shows the day at, the oldest dated
/// on or after it, a conversation dated by its newest letter
/// (`ListOpening.dayRow`, B-118); before B-118, on the row that carried the
/// day's first letter, its conversation's if it was in one. The page above
/// is asked for as the day lands (B-094), and so can the one above that.
/// Held, the row stays where it is on the pane, and the list with it. A
/// reply on such a page to a letter in the row joins it and takes it up
/// the list, dated as the reply, as Mail's list has it, and the day's next
/// row comes into its place (`ListPlace.landing(in:holding:)`, B-118): on
/// B-117 it stayed where it was, dated days after the day, over the rows of
/// the reply's day.
///
/// Held for the pages above only, and only while he has not moved the list:
/// a drag, a tap on another row or the status bar, Edit, a search, Refresh
/// or anything else that fetches the list afresh, another day, the panes
/// moving or changing size, each lets it go (`letGo`), and so does a page
/// that comes with the letter out of his sight or no longer heading a row
/// he can see, answered on a page before. From then on a page above
/// keeps the rows he can see where they are, a row newer mail joins passed
/// over, as before (B-042). Nothing else holds it: a letter taken out or
/// put back (B-093), the grouping switch, the watch's letters at the top,
/// a page below, each draws the list as it did.
struct LandedLetter: Equatable {

    /// The letter, while it is held.
    private(set) var letter: String?

    /// A jump has opened on the row `id` heads; nil when it found no row.
    mutating func landed(on id: String?) {
        letter = id
    }

    /// He has moved the list, or it has been replaced: nothing is held.
    mutating func letGo() {
        letter = nil
    }

    /// He has tapped `row`: the letter is let go unless the row carries it.
    /// A tap on the row he landed on opens it where it is, and it stays
    /// held there, open in the reading pane; a tap on another row is his
    /// to keep where it is.
    mutating func tapped(_ row: MessageThread) {
        guard let letter, !row.messages.contains(where: { $0.id == letter }) else { return }
        letGo()
    }

    /// Where the list goes as a page above is drawn, from `here`: the
    /// letter's row held, while he can see it headed by the letter; with
    /// none held, or the letter out of his sight or in a row newer mail has
    /// joined, where he is, and nothing held from then on.
    mutating func move(forPageAboveFrom here: ListPlace) -> ListPlaces.Move {
        guard let letter, here.heads(letter) else {
            letGo()
            return .stay
        }
        return .holding(letter)
    }
}

/// Where the list was before the rows still out were taken out, so that a
/// row put back goes back where it stood, and every row in view with it
/// (B-093).
///
/// A Delete or a Move takes its letter's row out at the tap, and when the
/// server does not take it, offline or with the letter still in the folder
/// (B-062, B-092), the row is put back. Both draw the list again holding
/// his place by the rows he can see (`ListPlace.landing`). For a row out of
/// sight above the list that puts it back out of sight, as it went, and for
/// one below the first he can see, back where it was. But the first row he
/// could see, taken out, had the rows below close up into its place, and
/// put back by the row first in sight then, it went in above that row, out
/// of sight under the search field: the reading pane emptied at the tap, an
/// alert saying why the letter had not gone, and no letter, every row in
/// view one up from where it had been.
///
/// So the place from before the take is kept, and a row put back while the
/// list shows what the take left (`ListPlace.showsTheSame`) is put back by
/// that place: the row where it was, the rows below it down a row, as
/// before the tap. A page put on above meanwhile moves nothing he sees,
/// and the row still goes back where it was. Once what he sees has moved,
/// the list scrolled or a row in view joined by newer mail, the rows he
/// can see then are held instead, as for any other redraw, and the place
/// is dropped.
///
/// Edit mode's Delete or Move takes its rows out one after another at the
/// tap and puts the refused ones back one after another (`ListBatch`): one
/// place for all of them, the one before the first was taken, kept until
/// the last is back.
///
/// Out of `MessageListViewController`, which takes the places, for the
/// reason `SearchAnswer` is.
struct TakenRows {
    /// Where he was before the first of the rows still out was taken out.
    private var before: ListPlace?
    /// Where the last take or put back left the list.
    private var left: ListPlace?
    /// The letters whose rows have been taken out since `before`, and not
    /// put back.
    private var out: Set<String> = []

    /// Where the list goes as `change` is drawn, `here` where it is now: for
    /// one of the rows still out put back, with the list as the last take or
    /// put back left it, to where he was before they were taken out;
    /// otherwise where he is.
    ///
    /// A row put back by its Undo has a new id (`ListChange.restored`): the
    /// place is taken with it renamed, so the row is found where it stood.
    func move(for change: ListChange, here: ListPlace) -> ListPlaces.Move {
        guard let (id, now) = Self.back(change), out.contains(id), let before, let left,
              here.showsTheSame(as: left) else { return .stay }
        return .putBack(now.map { before.renaming(id, to: $0) } ?? before)
    }

    /// The row a change puts back, by the id it was taken under, and its
    /// id now if that is another; nil for any other change.
    private static func back(_ change: ListChange) -> (String, String?)? {
        switch change {
        case .putBack(let id): return (id, nil)
        case .restored(let id, let now): return (id, now)
        case .taken, .marked: return nil
        }
    }

    /// `change` drawn, the list taken from `here` to `now`. A take with the
    /// list as the last one left it is one more row out since the same
    /// place; any other starts again from `here`. A row put back by that
    /// place leaves it kept for the rest; one put back by the rows he can
    /// see drops it, since the list has moved.
    mutating func drawn(_ change: ListChange, from here: ListPlace, to now: ListPlace) {
        switch change {
        case .taken(let id):
            if before == nil || !(left.map(here.showsTheSame(as:)) ?? false) {
                before = here
                out = []
            }
            out.insert(id)
            left = now
        case .putBack(let id), .restored(let id, _):
            guard move(for: change, here: here) != .stay else {
                self = TakenRows()
                return
            }
            out.remove(id)
            if case .restored(_, let new) = change { before = before?.renaming(id, to: new) }
            if out.isEmpty { self = TakenRows() } else { left = now }
        case .marked:
            break
        }
    }
}

/// Where the folder's fresh first page goes when it lands over the page
/// kept on the iPad (D-016), which the list drew before anything had been
/// sent. By `ListPlaces`' rules, since it is the list replaced under him,
/// whatever he has done in the second or two it took.
enum KeptSwap: Equatable {
    /// A finger on the list: nothing yet. The page waits until it lifts, as
    /// the watch's letters do, since a row that moves under a finger is a
    /// tap on the neighbouring letter.
    case waitForLift
    /// Rows ticked in Edit mode: nothing until Cancel, or the last tick taken
    /// off, as the watch's letters wait (B-049). Rows moved under his ticks
    /// are a Delete or a Move of letters he did not choose, and a ticked
    /// kept row the fresh page does not have would lose its tick without a
    /// word.
    case waitForTicks
    /// At the top: replaced in place, and the list stays at the top, where
    /// new mail comes in as he watches.
    case top
    /// Scrolled down the kept rows: replaced, and the rows he can see stay
    /// where they are on screen, found again by their letters (B-042).
    case holdingPlace
    /// A search showing, or typed and not yet run: left alone. The folder's
    /// letters under it are replaced, and come back as the fresh page when
    /// it ends (`ListLetters.fetchedUnderSearch`).
    case underSearch

    /// `ticked` as the watch's letters take it: in Edit mode with at least
    /// one row ticked.
    static func swap(atTop: Bool, searching: Bool, ticked: Bool, touching: Bool) -> KeptSwap {
        if touching { return .waitForLift }
        if ticked { return .waitForTicks }
        if searching { return .underSearch }
        return atTop ? .top : .holdingPlace
    }

    /// Whether the page waits, for a finger or for his ticks.
    var waits: Bool { self == .waitForLift || self == .waitForTicks }
}

/// The folder's fresh first page, fetched over the page kept on the iPad
/// (D-016): the fetch, one at a time, and the page, once it has come, held
/// until `KeptSwap` lets it go on. The list's, as `MessageListViewController`
/// drives it, out of the controller for the reason `SearchAnswer` is.
///
/// One fetch at a time. The folder's own goes as the list opens; the watch
/// starts one when a check reaches the server with the kept rows still up,
/// after a launch that could not connect (`checked`). The watch runs from
/// the launch's first page onwards, so a folder with a page kept, opened
/// while a check was out, used to send its SEARCH and page FETCH twice,
/// the second answer thrown away. The watch's goes only once the folder's
/// own has been tried and has failed, and never while one is out or a
/// page has come and waits.
struct OverKept {

    /// A fetch over the kept page is out.
    private(set) var fetching = false
    /// The folder's own fetch has gone, as the list opened.
    private(set) var opened = false
    /// The page, come while it had to wait, and the listing it came from
    /// (`ListLetters.askingAfresh`).
    private(set) var waiting: Fresh?

    struct Fresh: Equatable {
        let page: [MessageSummary]
        let asked: Int
    }

    /// Whether a fetch over the kept page goes now, and it is out from now
    /// if so: only over kept rows still on the list (`showingKept`), not
    /// while one is out or a page waits, and the watch's (`quietly`) only
    /// once the folder's own has gone.
    mutating func fetch(showingKept: Bool, quietly: Bool) -> Bool {
        guard showingKept, !fetching, waiting == nil, opened || !quietly else { return false }
        fetching = true
        opened = true
        return true
    }

    /// The fetch has brought the folder's first page, from listing `asked`.
    mutating func came(_ page: [MessageSummary], asked: Int) {
        fetching = false
        waiting = Fresh(page: page, asked: asked)
    }

    /// The fetch failed, and the kept rows stay.
    mutating func failed() {
        fetching = false
    }

    /// The page to put on the list now, by `swap`, and nothing waiting
    /// after it; nil while it is to wait, and when nothing waits. A page
    /// whose kept rows he has replaced meanwhile, with a Refresh or a day,
    /// is dropped: that list has the say.
    mutating func landing(showingKept: Bool, _ swap: KeptSwap) -> Fresh? {
        guard let fresh = waiting else { return nil }
        guard showingKept else {
            waiting = nil
            return nil
        }
        guard !swap.waits else { return nil }
        waiting = nil
        return fresh
    }
}
