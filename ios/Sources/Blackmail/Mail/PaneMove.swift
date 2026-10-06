import Foundation

/// How the panes move when he changes what they show, as Mail's do
/// (B-066, B-077, D-015): where each picture of a pane starts and ends,
/// and on what clock.
///
/// Mail is built of UIKit's split view and its navigation controller, and
/// moves as they move; on 2026-10-06 the owner ruled "copy apple mail".
/// Two motions, measured on iPadOS 18.6:
///
/// - **The view button**, three panes and two, as the split view hides
///   and shows its sidebar: one motion of 0.5 s on UIKit's spring, every
///   column at once on the same curve, nothing up or down, no second
///   phase. The list keeps its width and slides over the folders with a
///   shadow on its leading edge; the folders go at half the list's speed
///   and darken as it covers them; the letter's left edge goes with the
///   list. Showing them is the exact reverse.
/// - **"< Mailboxes" and a folder tapped in two panes**, as the
///   navigation controller pops and pushes: the list slides in from the
///   column's right edge over the folders, with a shadow on its leading
///   edge, while they go 30% of the column to the left and darken; and
///   back. The same spring for the panes; the bar's titles and buttons
///   cross-fade and slide over 0.35 s on UIKit's bar curve. The letter
///   does not move.
///
/// Mail's motion and Blackmail's own widths: the three panes stay side by
/// side at every width, as D-015 has them, where Mail on an 11-inch iPad
/// pushes the letter partly off the screen. The list is 330 pt in three
/// panes and 375 in two on the 11-inch, where Mail's is 375 in both. So
/// the list's picture keeps the width it has at the end, and its right
/// edge rides the letter's left edge.
///
/// Pictures move, never the panes. At the tap the container takes still
/// pictures of the screen as it is, lays the real panes out anew at once
/// beneath, exactly as a change always has, and then takes pictures of the
/// panes as they are now laid out. What arrives or stays is pictured as
/// laid out anew, as UIKit lays its columns out before it moves them:
/// the list, and the folders coming back. What leaves or is cut off is
/// pictured as it was: the folders going, and their column drawing in.
/// The letter is pictured as it was: WebKit draws it in another process
/// and wraps it again in its own time, so no picture of it at its new
/// width can be had at the tap. Its words go with its left edge and land
/// where they now are; its lines wrap again at the end, as at a change
/// made at once. So nothing changes its look while it moves, and the last
/// frame of every pane but the letter is the screen beneath.
///
/// Out of the container, as `PaneArrangement` is, so the suite can check
/// on this host that the pictures fit together at every instant. Every
/// picture, line, shadow and darkening goes in a straight line from where
/// it is to where it ends, `progress(at:)` of the way, all on the one
/// clock, so a rule that holds at the start and at the end holds all the
/// way.
///
/// With m and l the Mailboxes and the list in three panes, c the two-pane
/// column, d a divider, and the letter at L3 = m + l + 2d in three and
/// L2 = c + d in two, the letter's edge travels T = L3 - L2 (1194 pt:
/// m 250, l 330, c 375, L3 581, L2 375.5, T 205.5):
///
/// - **Three to two, the list over the folders.** The list, as laid out
///   in two, slides left over the folders from where its right edge meets
///   the letter's to the screen's edge, T. The letter's edge comes left
///   with it. The folders go T/2 left and darken.
/// - **Two to three, the list off the folders.** The reverse: the list,
///   as laid out in three, slides right off the folders, which come back
///   from T/2 left, darkened, to where they are.
/// - **Two with the folders in front, to three, the middle opens.** Mail
///   has no such switch. The folders' column draws in from c to m, its
///   picture cut off rather than squeezed, the letter's edge goes right,
///   and the list is there between them, laid out and still.
/// - **A folder tapped in two panes, the list slides in**, from c to 0,
///   over the folders, which go 0.3c left and darken.
/// - **"< Mailboxes", the list slides off**, from 0 to c, and the folders
///   come back from 0.3c left.
///
/// **The letter goes with its left edge.** Its left edge moves and its
/// right edge is the screen's at both ends, so what is fastened to the
/// left, to the middle and to the right of the letter goes three
/// different distances: the whole of the edge's travel, half of it, and
/// none. One picture can go only one of them, and the letter's goes the
/// whole, since that is where its words are fastened. What the app knows
/// is fastened elsewhere is cut out of it and goes as it is fastened:
///
/// - The letter's actions, at the right of its bar, hold still
///   (`actionsPlateX`).
/// - "No message selected", in the middle of an empty pane, is painted
///   out of the letter's picture and given its own, which rides the
///   middle of the letter's column, half as far as the edge
///   (`placeholder`).
///
/// A conversation's dates, at the right end of its rows, and a sender's
/// markup laid out in the middle are drawn by WebKit into the same
/// picture as the words beside them, and cannot be cut out of it. They
/// ride with the letter and are put where they now are at the end, as a
/// wrapped line's words are (B-066, Not covered).
struct PaneMove: Equatable {

    enum Kind: Equatable {
        /// Three panes to two, the list in front: the view button.
        case listOverFolders
        /// Two panes with the list in front, to three: the view button.
        case listOffFolders
        /// Two panes with the Mailboxes in front, to three: the view button.
        case middleOpens
        /// Two panes, a folder tapped: its list comes in front.
        case listSlidesIn
        /// Two panes, "< Mailboxes": the folders come in front.
        case listSlidesOff

        /// Whether it is the view button's switch, which Mail makes as the
        /// split view hides and shows its sidebar. The other two are the
        /// navigation controller's push and pop.
        var isViewButtons: Bool {
            switch self {
            case .listOverFolders, .listOffFolders, .middleOpens: return true
            case .listSlidesIn, .listSlidesOff: return false
            }
        }
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

    /// When a pane's picture is cut.
    enum Taken: Equatable {
        /// At the tap, from the screen as it was, before anything is laid
        /// out anew.
        case before
        /// From the pane as it is laid out anew, beneath the pictures of
        /// the screen as it was, before anything moves.
        case after
    }

    /// How a move goes.
    enum Motion: Equatable {
        /// On UIKit's spring, every picture at once (`progress(at:)`).
        case spring
        /// The column as it was fades where it is over the column as it
        /// is, for `Theme.paneMoveDuration`, and nothing moves: "<
        /// Mailboxes" and a folder tap with Prefer Cross-Fade Transitions,
        /// as UIKit's navigation does then. Never the view button's
        /// switch, which Mail's split view slides whatever is set.
        case crossFade
    }

    /// One pane's picture, the whole height of the screen, or below its
    /// bar when the bar goes on its own (`underBar`). It moves only along
    /// x. Its width never changes; only how much of it shows, which is
    /// less only for the folders' column as the middle opens.
    struct Strip: Equatable {
        let pane: Pane
        let taken: Taken
        /// Its left edge at the start, and its width.
        let x, width: CGFloat
        /// Its left edge at the end, and how much of it shows.
        let toX, toShownWidth: CGFloat
        /// Whether the view button in its bar is painted over, so that no
        /// glyph but the one drawn still in the corner travels.
        let patchesViewButton: Bool
        /// Its content alone, under its bar; the bar goes in `bars`.
        let underBar: Bool
        /// Black over it, 0 to 1, at the start and at the end: a column
        /// going under another, or coming out from under it.
        let dim, toDim: CGFloat
        /// The shadow on its leading edge, 0 to 1, at the start and at the
        /// end: a column going over another.
        let shadow, toShadow: CGFloat

        /// Its left edge `p` of the way, 0 to 1.
        func left(at p: CGFloat) -> CGFloat { x + (toX - x) * p }
        func shownWidth(at p: CGFloat) -> CGFloat { width + (toShownWidth - width) * p }
        func dim(at p: CGFloat) -> CGFloat { dim + (toDim - dim) * p }
        func shadow(at p: CGFloat) -> CGFloat { shadow + (toShadow - shadow) * p }
    }

    /// A divider's stand-in, `Theme.paneDividerWidth` wide, the screen's
    /// height.
    struct Line: Equatable {
        let x, toX: CGFloat
        func left(at p: CGFloat) -> CGFloat { x + (toX - x) * p }
    }

    /// The middle of the letter's column, at the start and at the end,
    /// which the words of an empty pane are centred on.
    struct Middle: Equatable {
        let x, toX: CGFloat
        func at(_ p: CGFloat) -> CGFloat { x + (toX - x) * p }
    }

    /// The column's bar in "< Mailboxes" and a folder tap, which does not
    /// travel with the panes: the bar going fades out and slides `travel`
    /// (left is less than nothing), and the bar coming fades in from as
    /// far the other way, over `Theme.paneBarDuration` on
    /// `Theme.paneBarCurve`, while an empty bar stays where it is beneath
    /// them. With a cross-fade nothing comes, and the bar going fades
    /// where it is.
    struct Bars: Equatable {
        /// Pictured as it was.
        let going: Pane
        /// Pictured as laid out anew.
        let coming: Pane?
        let travel: CGFloat
    }

    let kind: Kind
    let motion: Motion
    let screenWidth: CGFloat
    /// Back to front: where two overlap, the later one is on top.
    let strips: [Strip]
    /// For the view button: the Mailboxes' divider, riding the list's left
    /// edge or the folders' cut-off edge, then the list's, riding the
    /// letter's. None for "< Mailboxes" and a folder tap, whose dividers do
    /// not move.
    let lines: [Line]
    /// Where an empty bar and the canvas lie under everything, or nil.
    let backdrop: ClosedRange<CGFloat>?
    /// The column every picture is cut off at, from the screen's left
    /// edge, for "< Mailboxes" and a folder tap: nothing they move goes
    /// over the letter. Nil for the view button.
    let column: CGFloat?
    let bars: Bars?
    /// The left edge of the still picture of the letter's actions, which
    /// is the letter's edge in three panes; nil when the letter is not
    /// pictured. The letter's bar holds nothing but its actions, at its
    /// right end, in both arrangements, so that picture is right at the
    /// start and at the end and never moves.
    let actionsPlateX: CGFloat?
    /// Where "No message selected" is centred, when the pane is empty; nil
    /// when the pane holds words, which go with the letter's picture.
    let placeholder: Middle?
    /// The panes pictured, which the container looks at for a bounce
    /// before anything is touched: every one, hidden at the tap or not. A
    /// pane hidden a moment before by a change made at once, because it
    /// was bouncing, goes on springing back while hidden, and one pictured
    /// as laid out then would jump as the pictures go.
    let looked: [Pane]

    /// The move from `from` to `to`, with the reading pane holding
    /// `reading` and Prefer Cross-Fade Transitions `crossFading`; nil for
    /// a change that moves nothing: the same panes, a folder opened in
    /// three panes, or anything the buttons cannot do.
    static func switching(from: PaneArrangement, to: PaneArrangement, screenWidth w: CGFloat,
                          reading: Reading, crossFading: Bool) -> PaneMove? {
        let three = PaneArrangement.columns(.three, screenWidth: w)
        let two = PaneArrangement.columns(.two, screenWidth: w)
        let d = Theme.paneDividerWidth
        let m = three.mailboxes, l = three.list, c = two.list
        let letterInThree = m + d + l + d
        let letterInTwo = c + d
        // How far the letter's edge goes, and with it the list's right edge.
        let travel = letterInThree - letterInTwo
        let dark = Theme.paneCoveredDim
        // Halfway between the letter's left edge and the screen's right.
        func middle(from: CGFloat, to: CGFloat) -> Middle? {
            reading == .nothing ? Middle(x: (from + w) / 2, toX: (to + w) / 2) : nil
        }
        func looked(_ strips: [Strip]) -> [Pane] { strips.map(\.pane) }

        switch (from.panes, from.leftColumn, to.panes, to.leftColumn) {
        case (.three, _, .two, .list):
            let listFrom = m + d + l - c
            let strips = [
                Strip(pane: .mailboxes, taken: .before, x: 0, width: m,
                      toX: -travel * Theme.paneSidebarParallax, toShownWidth: m,
                      patchesViewButton: true, underBar: false,
                      dim: 0, toDim: dark, shadow: 0, toShadow: 0),
                Strip(pane: .list, taken: .after, x: listFrom, width: c, toX: 0, toShownWidth: c,
                      patchesViewButton: true, underBar: false,
                      dim: 0, toDim: 0, shadow: 0, toShadow: 1),
                Strip(pane: .message, taken: .before, x: letterInThree, width: w - letterInThree,
                      toX: letterInTwo, toShownWidth: w - letterInThree,
                      patchesViewButton: false, underBar: false,
                      dim: 0, toDim: 0, shadow: 0, toShadow: 0),
            ]
            return PaneMove(
                kind: .listOverFolders, motion: .spring, screenWidth: w, strips: strips,
                lines: [Line(x: listFrom - d, toX: -d), Line(x: m + d + l, toX: c)],
                backdrop: 0...w, column: nil, bars: nil,
                actionsPlateX: letterInThree,
                placeholder: middle(from: letterInThree, to: letterInTwo),
                looked: looked(strips))
        case (.two, .list, .three, _):
            let listFrom = c - l
            let strips = [
                Strip(pane: .mailboxes, taken: .after, x: -travel * Theme.paneSidebarParallax,
                      width: m, toX: 0, toShownWidth: m,
                      patchesViewButton: true, underBar: false,
                      dim: dark, toDim: 0, shadow: 0, toShadow: 0),
                Strip(pane: .list, taken: .after, x: listFrom, width: l, toX: m + d,
                      toShownWidth: l, patchesViewButton: false, underBar: false,
                      dim: 0, toDim: 0, shadow: 1, toShadow: 0),
                Strip(pane: .message, taken: .before, x: letterInTwo, width: w - letterInTwo,
                      toX: letterInThree, toShownWidth: w - letterInTwo,
                      patchesViewButton: false, underBar: false,
                      dim: 0, toDim: 0, shadow: 0, toShadow: 0),
            ]
            return PaneMove(
                kind: .listOffFolders, motion: .spring, screenWidth: w, strips: strips,
                lines: [Line(x: listFrom - d, toX: m), Line(x: c, toX: m + d + l)],
                backdrop: nil, column: nil, bars: nil,
                actionsPlateX: letterInThree,
                placeholder: middle(from: letterInTwo, to: letterInThree),
                looked: looked(strips))
        case (.two, .mailboxes, .three, _):
            let strips = [
                Strip(pane: .mailboxes, taken: .before, x: 0, width: c, toX: 0, toShownWidth: m,
                      patchesViewButton: true, underBar: false,
                      dim: 0, toDim: 0, shadow: 0, toShadow: 0),
                Strip(pane: .message, taken: .before, x: letterInTwo, width: w - letterInTwo,
                      toX: letterInThree, toShownWidth: w - letterInTwo,
                      patchesViewButton: false, underBar: false,
                      dim: 0, toDim: 0, shadow: 0, toShadow: 0),
            ]
            return PaneMove(
                kind: .middleOpens, motion: .spring, screenWidth: w, strips: strips,
                lines: [Line(x: c, toX: m), Line(x: c, toX: m + d + l)],
                backdrop: nil, column: nil, bars: nil,
                actionsPlateX: letterInThree,
                placeholder: middle(from: letterInTwo, to: letterInThree),
                looked: looked(strips))
        case (.two, .mailboxes, .two, .list):
            return stack(.listSlidesIn, column: c, screenWidth: w, crossFading: crossFading,
                         looking: looked)
        case (.two, .list, .two, .mailboxes):
            return stack(.listSlidesOff, column: c, screenWidth: w, crossFading: crossFading,
                         looking: looked)
        default:
            return nil
        }
    }

    /// "< Mailboxes" and a folder tap, in the left column `c` wide, as
    /// UIKit's navigation controller pops and pushes: on the spring, or
    /// faded with Prefer Cross-Fade Transitions.
    private static func stack(_ kind: Kind, column c: CGFloat, screenWidth w: CGFloat,
                              crossFading: Bool, looking: ([Strip]) -> [Pane]) -> PaneMove {
        let comingIn = kind == .listSlidesIn
        let going: Pane = comingIn ? .mailboxes : .list
        if motion(for: kind, crossFading: crossFading) == .crossFade {
            let strips = [Strip(pane: going, taken: .before, x: 0, width: c, toX: 0, toShownWidth: c,
                                patchesViewButton: false, underBar: true,
                                dim: 0, toDim: 0, shadow: 0, toShadow: 0)]
            return PaneMove(kind: kind, motion: .crossFade, screenWidth: w, strips: strips,
                            lines: [], backdrop: nil, column: c,
                            bars: Bars(going: going, coming: nil, travel: 0),
                            actionsPlateX: nil, placeholder: nil, looked: looking(strips))
        }
        let dark = Theme.paneCoveredDim
        let aside = -c * Theme.paneStackParallax
        // The folders, beneath; the list over them.
        let folders = Strip(pane: .mailboxes, taken: comingIn ? .before : .after,
                            x: comingIn ? 0 : aside, width: c,
                            toX: comingIn ? aside : 0, toShownWidth: c,
                            patchesViewButton: false, underBar: true,
                            dim: comingIn ? 0 : dark, toDim: comingIn ? dark : 0,
                            shadow: 0, toShadow: 0)
        let list = Strip(pane: .list, taken: comingIn ? .after : .before,
                         x: comingIn ? c : 0, width: c, toX: comingIn ? 0 : c, toShownWidth: c,
                         patchesViewButton: false, underBar: true,
                         dim: 0, toDim: 0, shadow: 1, toShadow: comingIn ? 1 : 0)
        let half = c * Theme.paneBarTravel
        return PaneMove(kind: kind, motion: .spring, screenWidth: w, strips: [folders, list],
                        lines: [], backdrop: 0...c, column: c,
                        bars: Bars(going: going, coming: comingIn ? .list : .mailboxes,
                                   travel: comingIn ? -half : half),
                        actionsPlateX: nil, placeholder: nil, looked: looking([folders, list]))
    }

    /// Where the real screen is let through the pictures: the list between
    /// the folders and the letter as the middle opens, and beside the
    /// column, the divider and the letter, in "< Mailboxes" and a folder
    /// tap. Nil when the pictures cover it all.
    var revealed: ClosedRange<CGFloat>? {
        let d = Theme.paneDividerWidth
        switch kind {
        case .listOverFolders, .listOffFolders: return nil
        case .middleOpens: return (lines[0].toX + d)...lines[1].toX
        case .listSlidesIn, .listSlidesOff: return column.map { $0...screenWidth }
        }
    }

    /// The stretches of the screen's width no strip, line or backdrop
    /// covers, `p` of the way: what of the real screen shows through the
    /// pictures then. A strip is cut off at `column`.
    func uncovered(at p: CGFloat) -> [ClosedRange<CGFloat>] {
        let d = Theme.paneDividerWidth
        let edge = column ?? screenWidth
        var covered = strips.map {
            (max($0.left(at: p), 0), min($0.left(at: p) + $0.shownWidth(at: p), edge))
        }.filter { $0.0 < $0.1 }
            + lines.map { ($0.left(at: p), $0.left(at: p) + d) }
        if let backdrop { covered.append((backdrop.lowerBound, backdrop.upperBound)) }
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
    /// rows under it would jump up or down to the end as the pictures go;
    /// the container can neither stop it there, which would strand it,
    /// nor bring it back before the picture is cut, which shows only what
    /// was last drawn. So a change made while any pane in the pictures is
    /// bouncing, on the screen or hidden by the change before, is made at
    /// once, as it was before B-066, and the bounce is left to finish. One
    /// coasting inside its ends is stopped where it is, and its picture is
    /// where it stays.
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

    /// How far along UIKit's spring a move is, 0 to 1, `t` seconds after
    /// the tap: 1 - (1 + wt)e^(-wt), w the square root of `Theme`'s
    /// stiffness over its mass, 18.26 a second, as a spring critically
    /// damped goes. Half the way by 0.09 s, 90% by 0.21 s, 99% by 0.36 s;
    /// ended at `Theme.paneMoveDuration`, 99.9% of the way, where the
    /// pictures are put at the end and taken away.
    static func progress(at t: TimeInterval) -> CGFloat {
        guard t > 0 else { return 0 }
        guard t < Theme.paneMoveDuration else { return 1 }
        let w = (Theme.paneSpringStiffness / Theme.paneSpringMass).squareRoot()
        return CGFloat(1 - (1 + w * t) * exp(-w * t))
    }

    /// How a move goes: the view button's switch on the spring always, as
    /// Mail's split view moves its columns whatever is set, Reduce Motion
    /// and Prefer Cross-Fade Transitions included; "< Mailboxes" and a
    /// folder tap on the spring, or faded with Prefer Cross-Fade
    /// Transitions, as UIKit's navigation goes. Reduce Motion alone
    /// changes neither.
    static func motion(for kind: Kind, crossFading: Bool) -> Motion {
        kind.isViewButtons || !crossFading ? .spring : .crossFade
    }
}
