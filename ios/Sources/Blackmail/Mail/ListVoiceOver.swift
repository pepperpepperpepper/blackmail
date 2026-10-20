import Foundation

/// VoiceOver's row in the message list, kept on its letter when the rows are
/// drawn again (B-079).
///
/// Every change to the list's letters rebuilds its rows and reloads the
/// table (`MessageListViewController.regroup`), and a reload hands the cells
/// out again: the cell VoiceOver is on can then show another letter, or
/// none. VoiceOver does not follow the letter. On the test iPad, in a folder
/// opened afresh, it read the second row's words in the first row's box, then
/// let go of the row and went to the view button in the corner. So the row
/// VoiceOver is on is taken before the reload, by the letters in it, and
/// after it VoiceOver is put on the cell that then shows the same letter.
///
/// The same for the row the container has just sent VoiceOver to (`send`),
/// before VoiceOver is there. On the iPad it got there about 1.1 to 1.4
/// seconds after it was sent, and a folder's fresh page, drawn over its kept
/// one, came 0.4 to 1.6 seconds after the tap. That row is held for `bound`.
/// If VoiceOver lands first on another row, or on the list's own bar or
/// table, as it went straight to the view button in Sent Mail and the Inbox,
/// it is put on the row, once. Not from the folders, the reading pane or a
/// sheet, where it may still be on its way, and never from the search field
/// while he types.
///
/// And held after VoiceOver has got there, for the same `bound`. Once in each
/// launch of the app, on the iPad, VoiceOver left the row by itself about
/// 0.9 seconds after it got there, with nothing in the app moving: to the
/// reading pane's Flag with a letter open, to the view button in the corner
/// with the pane empty. A move from the row to what he could not have
/// reached from it by a swipe, the reading pane or the list's bar, is put
/// back, once. A move to another row, the search field, the toolbar, a
/// sheet or the keys is his, and lets the row go.
///
/// Where VoiceOver is comes from VoiceOver itself, not from what its move
/// names (`FocusWatch`).
///
/// Out of `MessageListViewController` for the reason `ListPlace` is: the
/// controller is UIKit and the suite does not run it. The controller finds
/// the row VoiceOver is on, and names the cell this says.
struct ListVoiceOver {

    /// A row: where it was in the rows, and its letters, by which it is found
    /// again as `ListPlace` finds a row he could see: by its id, the letter
    /// listed first in it, else by any letter in it.
    struct Row: Equatable {
        let index: Int
        let place: ListPlace

        init?(_ index: Int, in rows: [MessageThread]) {
            guard rows.indices.contains(index) else { return nil }
            self.index = index
            place = ListPlace(rows: rows, visible: [(row: index, offset: 0)], selected: [])
        }
    }

    /// Where VoiceOver goes once the rows are drawn again.
    enum Step: Equatable {
        /// Nowhere: nothing is posted. VoiceOver is off, or on nothing of
        /// the list's rows and not on its way to one.
        case leave
        /// The row that now shows its letter.
        case same(Int)
        /// Its letter gone: the row now in its place, the one that came
        /// after it, or the last.
        case inPlace(Int)
        /// No rows at all: the list's table.
        case table
    }

    /// Where VoiceOver goes after the rows are drawn again, as `rows`, when
    /// it was on `held`, or nowhere for nil. The controller names the row's
    /// cell if any of it is in sight, else the first row wholly in sight,
    /// else the table, as after a move (`voiceOverPlace(at:orFirstRow:)`).
    static func step(after held: Row?, in rows: [MessageThread]) -> Step {
        guard let held else { return .leave }
        if let found = held.place.landing(in: rows) { return .same(found.row) }
        guard !rows.isEmpty else { return .table }
        return .inPlace(min(held.index, rows.count - 1))
    }

    /// How long a row VoiceOver has been sent to is held for it at most,
    /// from the send: more than twice the 1.3 seconds it took to get there
    /// on the iPad, and past the 2.0 to 2.75 seconds at which VoiceOver,
    /// there already, went off by itself.
    static let bound: TimeInterval = 3

    /// By when the container's screen change has landed, from the send:
    /// on the iPad it landed 1.1 to 1.6 seconds after the tap, in every
    /// step of three rounds. Until then it may still land, on the cell it
    /// named, which a reload may have handed out again since.
    static let screenChange: TimeInterval = 1.6

    /// What VoiceOver has gone to, or is on, as the list sees it.
    enum Landing: Equatable {
        /// The row it was sent to, as it is drawn now.
        case sentRow
        /// Another of the list's rows, or a cell drawn since for another
        /// letter.
        case otherRow
        /// The list's own column, but none of its rows and not its bar: the
        /// table itself, the search field while he is not typing in it, the
        /// toolbar. A swipe from the first row reaches the search field,
        /// and one from the last the toolbar.
        case listOwn
        /// The list's bar, with the view button in the corner and
        /// "< Mailboxes": a swipe from a row never reaches it, the search
        /// field being in between. In the Outbox, which has no search
        /// field, a swipe from the first row reaches the bar's end, Edit,
        /// and the next its title; those two are `listOwn` there. Its view
        /// button and "< Mailboxes", further on, are still the bar.
        case listBar
        /// The search field while he types in it, or a key.
        case typing
        /// The panes beside the list: the reading pane, and the folders.
        case beside
        /// Anything else: a sheet, an alert.
        case elsewhere
    }

    private struct Sent {
        var row: Row
        let at: Date
        /// VoiceOver has been on it.
        var there = false
        /// The list has posted VoiceOver there itself, after a reload,
        /// since it was sent.
        var posted = false
        /// VoiceOver got there through the list's own post, before the
        /// screen change could land.
        var early = false
    }

    private var sent: Sent?

    /// The container has sent VoiceOver to `row`, nil for the table. Held
    /// only for a row, and only with VoiceOver on: off, nothing is held and
    /// nothing posted.
    mutating func send(to row: Row?, running: Bool, at time: Date) {
        sent = running ? row.map { Sent(row: $0, at: time) } : nil
    }

    /// Nothing held: the list's column is out of sight, he has opened a
    /// row, or the panes have been switched.
    mutating func letGo() {
        sent = nil
    }

    /// The row VoiceOver has been sent to, while it is held for it.
    func sentRow(at time: Date) -> Row? {
        guard let sent, time.timeIntervalSince(sent.at) <= Self.bound else { return nil }
        return sent.row
    }

    /// The screen change may still land.
    private func waiting(_ sent: Sent, at time: Date) -> Bool {
        time.timeIntervalSince(sent.at) < Self.screenChange
    }

    /// The row to keep VoiceOver on, taken before the rows are drawn again.
    /// VoiceOver is on `row`, a row of the list, or on `landing`. The row
    /// it has been sent to, while it is held, else the row of the list it
    /// is on. Nil with VoiceOver off, and nil while he types. On the
    /// folders, the reading pane or a sheet, only while VoiceOver is still
    /// on its way, before the screen change has landed; after that it is
    /// his, and he is not taken off it by a reload.
    func held(running: Bool, on row: Row?, landing: Landing, at time: Date) -> Row? {
        guard running else { return nil }
        switch landing {
        case .typing:
            return nil
        case .beside, .elsewhere:
            guard let sent, !sent.there, waiting(sent, at: time) else { return nil }
            return sentRow(at: time)
        case .sentRow, .otherRow, .listOwn, .listBar:
            return sentRow(at: time) ?? row
        }
    }

    /// The rows have been drawn again, and VoiceOver put on `row`, nil for
    /// the table. A row held for it goes with it there, and stays held,
    /// VoiceOver there already or not. Let go when the table was named.
    mutating func redrawn(to row: Row?) {
        guard var held = sent else { return }
        guard let row else {
            sent = nil
            return
        }
        held.row = row
        held.posted = true
        sent = held
    }

    /// VoiceOver has moved, to `landing`. Returns the row to put it on,
    /// once, and lets the row go.
    ///
    /// Before it has been on the row: put back from another of the list's
    /// rows, or a cell drawn since for another letter, and from the list's
    /// own column and bar: on the iPad the screen change landed on the view
    /// button itself. Let go when he types. On the folders, the reading
    /// pane or a sheet, still held while it is on its way, and let go once
    /// the screen change has landed.
    ///
    /// On the row: held, through the folder's fresh page or any other
    /// reload. A move to the reading pane or the list's bar is put back:
    /// he could not have swiped there from a row, and VoiceOver went there
    /// by itself on the iPad. If it got there through the list's own post,
    /// sooner than the screen change could land, a move to another row or
    /// the list's own column while it may still land is put back too: that
    /// screen change can land after it, on the cell it named. Any other move
    /// lets the row go, a move of his own above all: another row, the
    /// search field, the toolbar, a sheet, the keys.
    mutating func moved(to landing: Landing, at time: Date) -> Row? {
        guard var held = sent, let row = sentRow(at: time) else {
            sent = nil
            return nil
        }
        let waiting = waiting(held, at: time)
        if held.there {
            if landing == .sentRow { return nil }
            sent = nil
            switch landing {
            case .beside, .listBar:
                return row
            case .otherRow, .listOwn:
                return held.early && waiting ? row : nil
            case .sentRow, .typing, .elsewhere:
                return nil
            }
        }
        switch landing {
        case .sentRow:
            held.there = true
            held.early = held.posted && waiting
            sent = held
            return nil
        case .otherRow, .listOwn, .listBar:
            sent = nil
            return row
        case .typing:
            sent = nil
            return nil
        case .beside, .elsewhere:
            if !waiting { sent = nil }
            return nil
        }
    }
}

/// VoiceOver held on the open folder's row after "< Mailboxes" (B-079), as
/// the list holds its row after a folder tap (`ListVoiceOver`).
///
/// The container names the row, and on the iPad VoiceOver got there each
/// time, 1.1 to 1.4 seconds after the tap. But once in a launch it then
/// left the row by itself, 0.9 seconds later, for the reading pane's Flag.
/// So once VoiceOver has been on the row, a move from it to what he could
/// not have reached by a swipe is put back, once, within
/// `ListVoiceOver.bound` of the tap. That is the view button in the corner,
/// and the reading pane but from the last folder: the folders' toolbar is
/// hidden, and so is the list's column, so a swipe from the last folder
/// goes straight into the reading pane. The rest of the folders' bar is a
/// swipe from the first folder, and a move there is his, as a move to
/// another folder is. Before VoiceOver has got there nothing is put back:
/// the move then is VoiceOver on its way.
///
/// Out of `RootViewController`, which the suite does not run.
struct FoldersVoiceOver {

    /// What VoiceOver has gone to, as the container sees it.
    enum Landing: Equatable {
        /// The open folder's row, the one it was sent to.
        case sentRow
        /// The view button in the corner: a swipe from a folder never
        /// reaches it, the rest of the folders' bar being in between.
        case corner
        /// The reading pane. A swipe from the last folder reaches it,
        /// nothing being between them; from any other folder it does not.
        case pane
        /// Anything else: another folder, the rest of the folders' bar, a
        /// sheet.
        case other
    }

    private struct Sent {
        let at: Date
        /// The row is the folders' last.
        let last: Bool
        /// VoiceOver has been on the row.
        var there = false
    }

    private var sent: Sent?

    /// The container has named the open folder's row, `row` true, or the
    /// folders' table, false, which is not held. `last`, the row is the
    /// folders' last (`isLast`). Only with VoiceOver on.
    mutating func send(toRow row: Bool, last: Bool, running: Bool, at time: Date) {
        sent = row && running ? Sent(at: time, last: last) : nil
    }

    /// Nothing held: a folder tapped, or the panes switched.
    mutating func letGo() {
        sent = nil
    }

    /// The row is held, within the bound from the send.
    func holding(at time: Date) -> Bool {
        guard let sent else { return false }
        return time.timeIntervalSince(sent.at) <= ListVoiceOver.bound
    }

    /// VoiceOver has moved, to `landing`. True to put it back on the row,
    /// which lets it go: once, and only from the view button, or the
    /// reading pane from any folder but the last, after VoiceOver has been
    /// on the row. Any other move after it has been there lets it go with
    /// nothing posted.
    mutating func moved(to landing: Landing, at time: Date) -> Bool {
        guard holding(at: time), var held = sent else {
            sent = nil
            return false
        }
        guard held.there else {
            if landing == .sentRow {
                held.there = true
                sent = held
            }
            return false
        }
        guard landing != .sentRow else { return false }
        sent = nil
        return landing == .corner || (landing == .pane && !held.last)
    }

    /// Row `row` of section `section` is the last of a table whose sections
    /// have `counts` rows: the last of its own, with no rows in any section
    /// after it. False for a row the table does not have.
    static func isLast(_ row: Int, in section: Int, of counts: [Int]) -> Bool {
        guard counts.indices.contains(section), row >= 0, row == counts[section] - 1 else { return false }
        return counts[(section + 1)...].allSatisfy { $0 == 0 }
    }
}

/// Where VoiceOver is, asked of VoiceOver itself while a row is held for it
/// (B-079, the fourth change): the list's row after a folder tap
/// (`ListVoiceOver`), the folder's row after "< Mailboxes"
/// (`FoldersVoiceOver`).
///
/// On the iPad the app never learned where VoiceOver went. Once in each
/// launch with VoiceOver on at the launch, iPadOS posted a screen change of
/// its own, naming nothing, about 0.8 seconds after the app's. VoiceOver
/// got to the row, then took the app's first element: the reading pane's
/// Flag, or the view button in the corner. The element named with each of
/// VoiceOver's moves was nothing the app could find, so the landing on the
/// row and the leave were both taken as elsewhere, and the row was let go
/// with nothing put back. Asked later in such a launch, VoiceOver itself
/// named the row it was on (`UIAccessibility.focusedElement`).
///
/// So at each of VoiceOver's moves the controller asks VoiceOver where it
/// is, on the next turn, after VoiceOver's own move. And in case no move
/// is told at all, it asks every tenth of a second while a row is held,
/// from the send to `ListVoiceOver.bound`. A tick tells the element apart
/// only when it is another object than the one last seen: VoiceOver kept on
/// one element is looked at once. VoiceOver on nothing, as it may be for
/// a moment as it moves, is passed over: the row stays held, and what was
/// seen last is kept. The ticks stop at the bound, when the row is let go,
/// and when it is put back. None run with VoiceOver off, and none with
/// nothing held.
///
/// Out of the controllers, which the suite does not run. They keep the
/// timer, started and stopped as this says.
struct FocusWatch {

    /// How often VoiceOver is asked while a row is held: a tenth of a
    /// second, so a leave is put back at once.
    static let every: TimeInterval = 0.1

    /// The ticks are to run.
    private(set) var ticking = false
    /// What VoiceOver was on at the last look, if it has been looked at
    /// since the ticks started.
    private var seen: AnyObject?
    private var looked = false

    /// A row has just been sent to: the ticks run if it is held,
    /// `holding`, from nothing seen, so the first tick looks. No ticks with
    /// nothing held: VoiceOver off, or the table named. True to start them.
    mutating func start(holding: Bool) -> Bool {
        stop()
        ticking = holding
        return ticking
    }

    /// The row let go or put back: no ticks, and nothing seen.
    mutating func stop() {
        ticking = false
        seen = nil
        looked = false
    }

    /// At a tick, or a look after one of VoiceOver's moves: the ticks go on
    /// while the row is held, `holding`, and stop for good once it is not:
    /// past the bound, let go, or put back.
    mutating func goesOn(holding: Bool) -> Bool {
        if !holding { stop() }
        return ticking
    }

    /// VoiceOver is on `element` now. True when a tick is to tell it apart:
    /// the first look since the start, or another object than the one last
    /// seen. It is the one seen after this. False with the ticks stopped.
    /// The controllers never ask it of nothing: a read of nothing is passed
    /// over, and the row stays held.
    mutating func changed(to element: AnyObject?) -> Bool {
        guard ticking else { return false }
        defer {
            seen = element
            looked = true
        }
        return !looked || element !== seen
    }
}
