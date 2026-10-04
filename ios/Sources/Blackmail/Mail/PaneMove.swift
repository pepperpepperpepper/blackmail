import Foundation

/// The view button's switch as it moves: where each picture of a pane
/// starts and ends, and how long it takes (B-066, D-015).
///
/// At the tap the container takes still pictures of the screen as it is,
/// lays the real panes out in the new arrangement at once beneath them,
/// exactly as a switch always has, and then slides the pictures sideways
/// as whole columns, bars and all. When they have arrived they fade where
/// they are, over the real panes, which by then have wrapped their text
/// to their new widths. So nothing changes its look while it moves, and
/// nothing moves while it changes. Nothing moves up or down and nothing
/// grows or shrinks: a row he was looking at is at the same height in
/// every frame.
///
/// Out of the container, as `PaneArrangement` is, so the suite can check
/// on this host that the pictures fit together at every instant. Each
/// strip and each line goes in a straight line from where it is to where
/// it ends, all of them on the same clock, so a rule that holds at the
/// start and at the end holds all the way.
///
/// Three moves, one for each way the view button can switch. With m and l
/// the Mailboxes and the list in three panes, c the two-pane column, d a
/// divider, and the letter at L3 = m + l + 2d in three and L2 = c + d in
/// two (1194 pt: m 250, l 330, c 375, L3 581, L2 375.5):
///
/// - **Three to two, the list over the folders.** The list slides left
///   from beside the folders to the screen's edge, over them, and the
///   letter's left edge comes left with it by L3 - L2. The folders stay.
/// - **Two to three, the list off the folders.** The list slides right
///   from the screen's edge to beside the folders, uncovering them where
///   they already are, and the letter's edge goes right.
/// - **Two with the folders in front, to three, the middle opens.** The
///   folders' column draws in from c to m, its picture cut off rather
///   than squeezed, the letter's edge goes right, and the list is there
///   between them, already laid out and still.
///
/// A divider line rides each moving edge, so every column has its edge
/// in every frame. Behind the strips, where a moving column leaves room
/// it has not yet filled, an empty bar and the canvas.
///
/// **The letter goes with its left edge.** Its left edge moves and its
/// right edge is the screen's at both ends, so what is fastened to the
/// left, to the middle and to the right of the letter goes three
/// different distances: the whole of the edge's travel, half of it, and
/// none. One picture can go only one of them, and the letter's goes the
/// whole, since that is where its words are fastened: the header the app
/// draws, a plain letter's lines, the grey notices, a conversation's names
/// and its letters, and a sender's HTML as most people's mail is written.
/// They land where they now are, and their lines are wrapped again at
/// the settle with nothing moving. Held still instead, as if fastened to
/// the right, the letter would stop every word he reads a whole edge's
/// travel from where it belongs, and carried half as far, half of one.
/// What the app knows is fastened elsewhere is cut out of it and goes as
/// it is fastened:
///
/// - The letter's actions, at the right of its bar, hold still
///   (`actionsPlateX`).
/// - "No message selected", in the middle of an empty pane, is painted
///   out of the letter's picture and given its own, which rides the
///   middle of the letter's column, half as far as the edge
///   (`placeholder`), as a label laid out in a moving column would.
///
/// A conversation's dates, at the right end of its rows, and a sender's
/// markup laid out in the middle are drawn by WebKit into the same picture
/// as the words beside them, and cannot be cut out of it. They ride with
/// the letter and are put where they now are at the settle, as a wrapped
/// line's words are (B-066, Not covered).
struct PaneMove: Equatable {

    enum Kind: Equatable {
        /// Three panes to two, the list in front.
        case listOverFolders
        /// Two panes with the list in front, to three.
        case listOffFolders
        /// Two panes with the Mailboxes in front, to three.
        case middleOpens
    }

    enum Pane: Equatable {
        case mailboxes, list, message
    }

    /// What the reading pane holds at the tap, as far as the motion needs
    /// to know: where its words are fastened.
    enum Reading: Equatable {
        /// A letter, a conversation, "Loading…" or why there is no letter:
        /// words fastened to the pane's left edge, which go with it.
        case words
        /// Nothing, and "No message selected" in the middle of the pane.
        case nothing
    }

    /// One pane's picture, the whole height of the screen, bars included.
    /// It moves only along x. Its width never changes; only how much of it
    /// shows, which is less only for the folders' column in `middleOpens`.
    struct Strip: Equatable {
        let pane: Pane
        /// Its left edge at the tap, and its width: where the pane is.
        let x, width: CGFloat
        /// Its left edge at the end of the slide, and how much of it shows.
        let toX, toShownWidth: CGFloat
        /// Whether the twin view button in its bar is painted over, so that
        /// a second glyph does not travel away from the corner.
        let patchesViewButton: Bool

        /// Its left edge `p` of the way through the slide, 0 to 1.
        func left(at p: CGFloat) -> CGFloat { x + (toX - x) * p }
        func shownWidth(at p: CGFloat) -> CGFloat { width + (toShownWidth - width) * p }
    }

    /// A divider's stand-in, `Theme.paneDividerWidth` wide, the screen's
    /// height.
    struct Line: Equatable {
        let x, toX: CGFloat
        func left(at p: CGFloat) -> CGFloat { x + (toX - x) * p }
    }

    /// The middle of the letter's column, at the tap and at the end of the
    /// slide, which the words of an empty pane are centred on. The picture
    /// of the words goes from the one to the other, and is in the middle of
    /// the column at every instant between.
    struct Middle: Equatable {
        let x, toX: CGFloat
        func at(_ p: CGFloat) -> CGFloat { x + (toX - x) * p }
    }

    let kind: Kind
    let screenWidth: CGFloat
    /// Back to front: where two overlap, the later one is on top. The
    /// letter is always last.
    let strips: [Strip]
    /// The Mailboxes' divider, then the list's.
    let lines: [Line]
    /// Where the empty bar and canvas begin, to the screen's right edge, or
    /// nil for none.
    let backdropFrom: CGFloat?
    /// The left edge of the still picture of the letter's actions, which
    /// is the letter's edge in three panes. The letter's bar holds nothing
    /// but its actions, at its right end, in both arrangements, so that
    /// picture is right at the start and at the end and never moves.
    let actionsPlateX: CGFloat
    /// Where "No message selected" is centred, when the pane is empty: cut
    /// out of the letter's picture, which is painted over where it was,
    /// and carried on its own. Nil when the pane holds words, which go
    /// with the letter's picture.
    let placeholder: Middle?

    /// The move for the view button's switch from `from` to `to`, with the
    /// reading pane holding `reading`; nil when they show the same number
    /// of panes (a "< Mailboxes" or a folder tapped in two panes, which
    /// stay instant) or for a switch the button cannot make.
    static func switching(from: PaneArrangement, to: PaneArrangement,
                          screenWidth w: CGFloat, reading: Reading) -> PaneMove? {
        guard from.panes != to.panes else { return nil }
        let three = PaneArrangement.columns(.three, screenWidth: w)
        let two = PaneArrangement.columns(.two, screenWidth: w)
        let d = Theme.paneDividerWidth
        let m = three.mailboxes, l = three.list, c = two.list
        let letterInThree = m + d + l + d
        let letterInTwo = c + d
        // Halfway between the letter's left edge and the screen's right.
        func middle(from: CGFloat, to: CGFloat) -> Middle? {
            reading == .nothing ? Middle(x: (from + w) / 2, toX: (to + w) / 2) : nil
        }

        switch (from.panes, from.leftColumn) {
        case (.three, _):
            // A switch to two always lands on the list.
            guard to.leftColumn == .list else { return nil }
            return PaneMove(
                kind: .listOverFolders, screenWidth: w,
                strips: [
                    Strip(pane: .mailboxes, x: 0, width: m, toX: 0, toShownWidth: m,
                          patchesViewButton: false),
                    Strip(pane: .list, x: m + d, width: l, toX: 0, toShownWidth: l,
                          patchesViewButton: false),
                    Strip(pane: .message, x: letterInThree, width: w - letterInThree,
                          toX: letterInTwo, toShownWidth: w - letterInThree,
                          patchesViewButton: false),
                ],
                lines: [Line(x: m, toX: -d), Line(x: m + d + l, toX: c)],
                backdropFrom: 0,
                actionsPlateX: letterInThree,
                placeholder: middle(from: letterInThree, to: letterInTwo))
        case (.two, .list):
            return PaneMove(
                kind: .listOffFolders, screenWidth: w,
                strips: [
                    Strip(pane: .list, x: 0, width: c, toX: m + d, toShownWidth: c,
                          patchesViewButton: true),
                    Strip(pane: .message, x: letterInTwo, width: w - letterInTwo,
                          toX: letterInThree, toShownWidth: w - letterInTwo,
                          patchesViewButton: false),
                ],
                lines: [Line(x: -d, toX: m), Line(x: c, toX: m + d + l)],
                backdropFrom: m + d,
                actionsPlateX: letterInThree,
                placeholder: middle(from: letterInTwo, to: letterInThree))
        case (.two, .mailboxes):
            return PaneMove(
                kind: .middleOpens, screenWidth: w,
                strips: [
                    Strip(pane: .mailboxes, x: 0, width: c, toX: 0, toShownWidth: m,
                          patchesViewButton: false),
                    Strip(pane: .message, x: letterInTwo, width: w - letterInTwo,
                          toX: letterInThree, toShownWidth: w - letterInTwo,
                          patchesViewButton: false),
                ],
                lines: [Line(x: c, toX: m), Line(x: c, toX: m + d + l)],
                backdropFrom: nil,
                actionsPlateX: letterInThree,
                placeholder: middle(from: letterInTwo, to: letterInThree))
        }
    }

    /// Where the real screen is let through, by the end of the slide: the
    /// folders uncovered where they already are, or the list between the
    /// folders and the letter. Nil when the pictures cover it all.
    var revealed: ClosedRange<CGFloat>? {
        let d = Theme.paneDividerWidth
        switch kind {
        case .listOverFolders: return nil
        case .listOffFolders: return 0...lines[0].toX
        case .middleOpens: return (lines[0].toX + d)...lines[1].toX
        }
    }

    /// The stretches of the screen's width no strip, line or backdrop
    /// covers, `p` of the way through the slide: what of the real screen
    /// shows through the pictures then.
    func uncovered(at p: CGFloat) -> [ClosedRange<CGFloat>] {
        let d = Theme.paneDividerWidth
        var covered = strips.map { ($0.left(at: p), $0.left(at: p) + $0.shownWidth(at: p)) }
            + lines.map { ($0.left(at: p), $0.left(at: p) + d) }
        if let backdropFrom { covered.append((backdropFrom, screenWidth)) }
        covered.sort { $0.0 < $1.0 }
        // Edges that meet are worked out in floating point, so a gap is
        // one wider than rounding.
        let rounding: CGFloat = 0.000_1
        var gaps: [ClosedRange<CGFloat>] = []
        var reached: CGFloat = 0
        for (start, end) in covered {
            if start - reached > rounding { gaps.append(reached...start) }
            reached = max(reached, end)
        }
        if screenWidth - reached > rounding { gaps.append(reached...screenWidth) }
        return gaps
    }

    // MARK: - Holding still

    /// Where a list, the Mailboxes or a letter comes to rest: its offset
    /// anywhere from its top end to its bottom end, and from its left end
    /// to its right, as UIKit reckons them from its content, its size and
    /// its insets.
    ///
    /// Past either end it is bouncing, and springs back on its own. A
    /// picture cut then is of the last frame drawn, past the end, and the
    /// rows under it would jump up or down to the end at the settle; the
    /// container can neither stop it there, which would strand it, nor
    /// bring it back before the picture is cut, which shows only what was
    /// last drawn. So a switch tapped while any pane in the pictures is
    /// bouncing is made at once, as it was before B-066, and the bounce
    /// is left to finish. One coasting inside its ends is stopped where it
    /// is, and its picture is the screen.
    struct Rest: Equatable {
        let top, bottom, left, right: CGFloat

        init(contentSize: CGSize, viewSize: CGSize,
             insetTop: CGFloat, insetLeft: CGFloat, insetBottom: CGFloat, insetRight: CGFloat) {
            top = -insetTop
            bottom = max(top, contentSize.height - viewSize.height + insetBottom)
            left = -insetLeft
            right = max(left, contentSize.width - viewSize.width + insetRight)
        }

        /// How far past an end an offset can be and still be taken as at
        /// it: half a point, a pixel on his iPad. An end is worked out in
        /// floating point here and in UIKit, and UIKit puts an offset at
        /// rest on a pixel, so one resting at its end can be a fraction
        /// past the end as reckoned here.
        static let slack: CGFloat = 0.5

        /// Whether `offset` is inside the ends, to within `slack`: not
        /// bouncing.
        func holds(_ offset: CGPoint) -> Bool {
            offset.y >= top - Self.slack && offset.y <= bottom + Self.slack
                && offset.x >= left - Self.slack && offset.x <= right + Self.slack
        }

        /// `offset` brought inside the ends: itself when it is inside, and
        /// moved by no more than `slack` when `holds` takes it.
        func clamped(_ offset: CGPoint) -> CGPoint {
            CGPoint(x: min(max(offset.x, left), right), y: min(max(offset.y, top), bottom))
        }
    }

    // MARK: - Time

    /// One stretch of the motion, and how long it lasts.
    enum Phase: Equatable {
        /// The pictures travel to where the panes now are.
        case slide(TimeInterval)
        /// The pictures fade where they are, over the panes.
        case settle(TimeInterval)
        /// With Reduce Motion or Prefer Cross-Fade Transitions: one
        /// picture of the whole screen fades, and nothing travels.
        case dissolve(TimeInterval)

        var duration: TimeInterval {
            switch self {
            case .slide(let t), .settle(let t), .dissolve(let t): return t
            }
        }
    }

    /// The motion's stretches in order, from `Theme`'s durations. The only
    /// place the container's motion takes a duration from.
    static func timeline(dissolving: Bool) -> [Phase] {
        dissolving
            ? [.dissolve(Theme.paneDissolveDuration)]
            : [.slide(Theme.paneSlideDuration), .settle(Theme.paneSettleDuration)]
    }
}
