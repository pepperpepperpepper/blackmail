import Foundation

/// What of a table is in sight, for VoiceOver's rows (B-079) and for the
/// rows the list holds its place by (`ListPlace.inSight`, B-093): between
/// its bars and below the band pinned at its top, the list's search field.
/// In the table's own points, down from the top of its rows, as
/// `rectForRow` gives a row.
///
/// Out of `UITableView` so the suite can run the sums: the table hands these
/// over (`sight`), and the sums of what is in sight and of the least scroll
/// are here, in one place.
struct TableSight: Equatable {
    /// How far the table is scrolled: its `contentOffset.y`.
    var offset: CGFloat
    /// The table's height.
    var height: CGFloat
    /// What its bars cover at the top and at the bottom: its
    /// `adjustedContentInset`.
    var barTop: CGFloat
    var barBottom: CGFloat
    /// The band pinned at the top, under the bar: the list's search field.
    /// None in the folders.
    var band: CGFloat
    /// How tall all its rows are: its `contentSize.height`.
    var content: CGFloat

    /// The top of what is in sight, below the bar and the band.
    var top: CGFloat { offset + barTop + band }
    /// The bottom of what is in sight, above the bar under the table.
    var bottom: CGFloat { offset + height - barBottom }

    /// How far above the bar under the table a row has to end for
    /// VoiceOver to take it as wholly in sight (the fourth change): a third
    /// of the list's 96-point row. On the iPad, on iPadOS 16.5.1, VoiceOver
    /// put in the middle of the list a row it landed on that ended 0, 4, 9,
    /// 25 or 26.5 points above the toolbar, and left one 29, 32.5 or 42.5
    /// points above it. A row just below the search band it left alone, so
    /// the top has none.
    static let voiceOverBottomClearance: CGFloat = 32
    /// The bottom of what VoiceOver takes as in sight: that far above the
    /// bar under the table.
    var voiceOverBottom: CGFloat { bottom - Self.voiceOverBottomClearance }

    /// Some of a row from `minY` to `maxY` is in sight: a point or more.
    func showsPart(_ minY: CGFloat, _ maxY: CGFloat) -> Bool {
        maxY >= top + 1 && minY <= bottom - 1
    }

    /// All of it is in sight, to half a point, as VoiceOver takes it: below
    /// the band, and ending the clearance above the bar under the table.
    func showsWhole(_ minY: CGFloat, _ maxY: CGFloat) -> Bool {
        minY >= top - 0.5 && maxY <= voiceOverBottom + 0.5
    }

    /// The offset at which a row from `minY` to `maxY` is wholly in sight,
    /// moved as little as can be: down by the part of it under the band, or
    /// up until it ends the clearance above the bar below, never so far
    /// that its top goes under the band. Never past either end of the
    /// table, and never back from beyond one. Nil for a row in sight whole
    /// already, for one with none of it in sight, which VoiceOver is not
    /// put on, and when the table cannot move.
    func offset(showingWhole minY: CGFloat, _ maxY: CGFloat) -> CGFloat? {
        guard showsPart(minY, maxY), !showsWhole(minY, maxY) else { return nil }
        let move = minY < top ? minY - top : min(maxY - voiceOverBottom, minY - top)
        let first = -barTop
        let last = max(first, content + barBottom - height)
        let moved = min(max(offset + move, min(first, offset)), max(last, offset))
        return abs(moved - offset) < 0.5 ? nil : moved
    }
}
