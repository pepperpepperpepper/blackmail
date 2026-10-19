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
/// before VoiceOver is there. On the iPad it got there about 1.3 seconds
/// after it was sent, and a folder's fresh page, drawn over its kept one,
/// came 0.4 to 0.9 seconds after the tap. That row is held for it until it
/// has been on it through the folder's fresh page, or for `bound` at most.
/// If VoiceOver lands first on another row, or on the list's own bar or
/// table, as it went straight to the view button in Sent Mail and the Inbox,
/// it is put on the row, once. Never from the folders, the reading pane, a
/// sheet, or the search field while he types.
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

    /// How long a row VoiceOver has been sent to is held for it at most:
    /// more than twice the 1.3 seconds it took to get there on the iPad.
    static let bound: TimeInterval = 3

    /// By when the container's screen change has landed, from the send:
    /// on the iPad it landed 1.3 to 1.6 seconds after the tap, in every
    /// step of both rounds. Until then it may still land, on the cell it
    /// named, which a reload may have handed out again since.
    static let screenChange: TimeInterval = 1.6

    /// What VoiceOver has gone to, or is on, as the list sees it.
    enum Landing: Equatable {
        /// The row it was sent to, as it is drawn now.
        case sentRow
        /// Another of the list's rows, or a cell drawn since for another
        /// letter.
        case otherRow
        /// The list's own column, but none of its rows: its bar, with the
        /// view button and "< Mailboxes", the table itself, the search
        /// field while he is not typing in it, the toolbar.
        case listOwn
        /// The search field while he types in it, or a key.
        case typing
        /// Anything else: the folders, the reading pane, a sheet.
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

    /// Nothing held: the list's column is out of sight.
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
    /// his, and he is not taken off it.
    func held(running: Bool, on row: Row?, landing: Landing, at time: Date) -> Row? {
        guard running else { return nil }
        switch landing {
        case .typing:
            return nil
        case .elsewhere:
            guard let sent, !sent.there, waiting(sent, at: time) else { return nil }
            return sentRow(at: time)
        case .sentRow, .otherRow, .listOwn:
            return sentRow(at: time) ?? row
        }
    }

    /// The rows have been drawn again, and VoiceOver put on `row`, nil for
    /// the table. A row held for it goes with it there; `kept`, the rows are
    /// still the kept page. Let go when the table was named, and once
    /// VoiceOver has been on it and the rows are the fresh page, unless it
    /// got there early and the screen change may still land.
    mutating func redrawn(to row: Row?, kept: Bool, at time: Date) {
        guard var held = sent else { return }
        let early = held.early && waiting(held, at: time)
        guard let row, !(held.there && !kept && !early) else {
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
    /// own column: on the iPad the screen change landed on the view button
    /// itself. Let go when he types. On the folders, the reading pane or a
    /// sheet, still held while it is on its way, and let go once the screen
    /// change has landed.
    ///
    /// On the row: held while the rows are the kept page, until the fresh
    /// page. And held while the screen change may still land, if it got
    /// there through the list's own post: that screen change can land
    /// after it, on the cell it named, and is put back once. Any other move
    /// after it was there lets it go, a move of his own above all.
    mutating func moved(to landing: Landing, kept: Bool, at time: Date) -> Row? {
        guard var held = sent, let row = sentRow(at: time) else {
            sent = nil
            return nil
        }
        let waiting = waiting(held, at: time)
        if held.there {
            if landing == .sentRow { return nil }
            sent = nil
            let late = landing == .otherRow || landing == .listOwn
            return held.early && waiting && late ? row : nil
        }
        switch landing {
        case .sentRow:
            let early = held.posted && waiting
            guard kept || early else {
                sent = nil
                return nil
            }
            held.there = true
            held.early = early
            sent = held
            return nil
        case .otherRow, .listOwn:
            sent = nil
            return row
        case .typing:
            sent = nil
            return nil
        case .elsewhere:
            if !waiting { sent = nil }
            return nil
        }
    }
}
