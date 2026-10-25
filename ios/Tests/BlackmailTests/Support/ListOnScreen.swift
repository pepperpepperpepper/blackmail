import Foundation
@testable import Blackmail

/// The message list on the iPad's screen, as near as the suite can lay it
/// out, drawn again for every change its letters tell (`ListLetters.changed`)
/// the way `MessageListViewController.regroup(for:)` draws it: the place
/// taken before, the rows rebuilt from `ListLetters.shown`, the list put
/// where `TakenRows` and `ListPlace` say, at the offset `scroll(to:in:)`
/// would set, and `TakenRows` told where it was left.
///
/// The iPad's layout as `ListPlaceTests` has it: the search band 43 points
/// on top of the rows, 74 points of status and navigation bar over the
/// table and 50 of toolbar under it, the table 810 tall, a row 96.
///
/// For the tests that run a Delete or a Move through the shipping
/// repository and the scripted server and look at what he would see
/// (B-132). The controller itself is UIKit and does not exist here; what
/// it reads of the table is taken as `ListPlaceTests` takes it.
@MainActor
final class ListOnScreen {
    static let row = 96.0
    static let band = 43.0
    static let barTop = 74.0
    static let barBottom = 50.0
    static let height = 810.0
    /// The offset of a list at its top.
    static let top = -barTop

    let letters: ListLetters
    private(set) var rows: [MessageThread]
    /// How far the table is scrolled: its `contentOffset.y`.
    private(set) var offset: Double
    private var taken = TakenRows()
    /// Every change drawn holding the rows he can see, with no place kept
    /// from before a take: a row put back went in by the rows in view then,
    /// as before B-093.
    private let byRowsInView: Bool

    init(_ letters: ListLetters, at offset: Double = ListOnScreen.top, byRowsInView: Bool = false) {
        self.letters = letters
        self.offset = offset
        self.byRowsInView = byRowsInView
        rows = MessageThread.rows(for: letters.shown, grouped: true)
        letters.changed = { [weak self] change in self?.draw(change) }
    }

    /// Scrolled by his finger.
    func scroll(to offset: Double) {
        self.offset = offset
    }

    /// `regroup(for:)`.
    private func draw(_ change: ListChange) {
        let here = place(rows, at: offset)
        let next = MessageThread.rows(for: letters.shown, grouped: true)
        let move: ListPlaces.Move = byRowsInView ? .stay : taken.move(for: change, here: here)
        var to = offset
        switch move {
        case .putBack(let before):
            to = landed(before, in: next) ?? landed(here, in: next) ?? offset
        default:
            to = landed(here, in: next) ?? offset
        }
        rows = next
        offset = to
        taken.drawn(change, from: here, to: place(rows, at: offset))
    }

    /// The offset `scroll(to:in:)` sets for `place` in `next`, from where the
    /// table is; nil when nothing of the place is there.
    private func landed(_ place: ListPlace, in next: [MessageThread]) -> Double? {
        guard let landing = place.landing(in: next) else { return nil }
        let content = Self.band + Double(next.count) * Self.row
        let range = Self.top...max(Self.top, content + Self.barBottom - Self.height)
        return ListPlace.contentOffset(rowTop: Self.rowTop(landing.row), offset: landing.offset,
                                       range: range, current: offset) ?? offset
    }

    /// The top of row `row` in the table, as `rectForRow` gives it.
    static func rowTop(_ row: Int) -> Double { band + Double(row) * Self.row }

    /// The place `MessageListViewController.place()` takes.
    private func place(_ rows: [MessageThread], at offset: Double) -> ListPlace {
        ListPlace(rows: rows, onScreen: Self.onScreen(rows.count, at: offset),
                  sight: Self.sight(rows.count, at: offset), selected: [])
    }

    private static func sight(_ count: Int, at offset: Double) -> TableSight {
        TableSight(offset: offset, height: height, barTop: barTop, barBottom: barBottom,
                   band: band, content: band + Double(count) * row)
    }

    private static func onScreen(_ count: Int, at offset: Double)
        -> [(row: Int, top: Double, bottom: Double)] {
        (0..<count).map { ($0, rowTop($0), rowTop($0) + row) }
            .filter { $0.2 > offset && $0.1 < offset + height }
    }

    /// Where the top of each row is, down from the top of the pane, by the
    /// letter heading it.
    var onPane: [String: Double] {
        Dictionary(uniqueKeysWithValues: rows.enumerated().map {
            ($0.element.id, Self.rowTop($0.offset) - offset)
        })
    }

    /// The rows he can see, by the letters heading them, top first.
    var inView: [String] {
        ListPlace.inSight(Self.onScreen(rows.count, at: offset), sight: Self.sight(rows.count, at: offset))
            .map { rows[$0.row].id }
    }

    /// Each row's letters, top first.
    var letterRows: [[String]] { rows.map { $0.messages.map(\.id) } }
}
