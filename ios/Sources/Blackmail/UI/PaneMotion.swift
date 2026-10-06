// Guarded so this file compiles away on a host without UIKit.
#if canImport(UIKit)

import UIKit

/// The panes moving, as Mail's do (B-066, B-077): the view button's switch,
/// and "< Mailboxes" and a folder tap in two panes. Where each picture goes
/// is `PaneMove`'s; this is the UIKit half, the only place in the app that
/// animates a view.
///
/// The motion is made of pictures and nothing else. At the tap `cut` takes
/// still pictures of the screen as it is, before anything is laid out
/// anew. The container then lays the real panes out in the new arrangement
/// at once, as it always has, and `play` puts a cover over them with the
/// whole screen as it was at the top of it, takes pictures of the panes
/// that go as they are now laid out, puts every picture where it starts,
/// takes the screen as it was away and moves them. No real view is ever
/// moved, faded, hidden late or made to ignore a touch by this: the real
/// screen is final from the tap, and the cover only hides it for half a
/// second. So ending the motion at any instant, for any reason, is taking
/// the cover away, and what is under it is right.
///
/// Plain views placed by their frames, no constraints, and Core
/// Animation's spring, the one UIKit moves its columns on, set on the
/// pictures alone: nothing here can be left half done by a call made in
/// the wrong state, and nothing it builds outlives the cover.
@MainActor
final class PaneMotion {

    /// Whether "< Mailboxes" and a folder tap fade rather than slide:
    /// Prefer Cross-Fade Transitions, which iOS reports only with Reduce
    /// Motion on as well, and which he, or whoever helps him, can turn on
    /// at any time, so read at every tap. Reduce Motion alone changes
    /// nothing, and the view button's switch slides whatever is set, as
    /// Mail's columns do (`PaneMove.motion`). VoiceOver and Switch Control
    /// do not change the motion, as they do not in Apple's own apps.
    static var crossFading: Bool {
        UIAccessibility.prefersCrossFadeTransitions
    }

    /// What the pictures are cut from: the container's view, its three
    /// panes, the view button in the corner and the two there can be,
    /// the letter's bar, whose bottom is where the bars end, and the words
    /// of an empty pane.
    struct Stage {
        let root: UIView
        let mailboxes: UIView
        let list: UIView
        let message: UIView
        /// The view button in the bar of the left column at the tap, whose
        /// glyph is drawn still in the corner.
        let corner: UIButton
        /// The view button in the Mailboxes' bar, and its twin in the
        /// list's bar in two panes.
        let mailboxesButton: UIButton
        let listButton: UIButton
        let letterBar: UINavigationBar
        /// "No message selected", or nil when the pane holds a letter.
        let placeholder: UIView?

        func view(for pane: PaneMove.Pane) -> UIView {
            switch pane {
            case .mailboxes: return mailboxes
            case .list: return list
            case .message: return message
            }
        }

        /// The view button in `pane`'s bar, if it is on the screen there.
        @MainActor
        func viewButton(in pane: PaneMove.Pane) -> UIButton? {
            let button: UIButton
            switch pane {
            case .mailboxes: button = mailboxesButton
            case .list: button = listButton
            case .message: return nil
            }
            return button.window != nil && button.isDescendant(of: view(for: pane)) ? button : nil
        }
    }

    /// The pictures cut at the tap, and what is needed to cut the rest.
    struct Cut {
        fileprivate let move: PaneMove
        fileprivate let stage: Stage
        fileprivate let barsBottom: CGFloat
        /// The whole screen as it was, over everything while the panes laid
        /// out anew are pictured; nil when none is.
        fileprivate let veil: UIView?
        /// Each pane pictured as it was, the size of its strip.
        fileprivate let before: [PaneMove.Pane: UIView]
        /// The bar going, pictured as it was.
        fileprivate let barGoing: UIView?
        /// "No message selected", its frame and its picture.
        fileprivate let label: (frame: CGRect, picture: UIView, middle: PaneMove.Middle)?
        fileprivate let actions: UIView?
        /// The view button's glyph, drawn afresh where it is.
        fileprivate let glyph: UIView?
    }

    /// The cover on the screen, if anything is moving.
    private var cover: UIView?

    // MARK: - At the tap

    /// The pictures of the screen as it is now, before the container lays
    /// anything out. Nil, with a line in the connection log, when they
    /// cannot be trusted to match the screen, and the change is then made
    /// at once, as it always was.
    ///
    /// `afterScreenUpdates: false` here: what is on the glass now, not
    /// what the next frame will draw. The panes are laid out anew in this
    /// same turn of the run loop, and the screen without the cover over
    /// them is never drawn.
    func cut(_ move: PaneMove, stage: Stage) -> Cut? {
        let root = stage.root
        guard root.window != nil else { return refused("not in a window") }
        let bounds = root.bounds
        let height = bounds.height
        let barsBottom = stage.letterBar.convert(stage.letterBar.bounds, to: root).maxY
        let edge = move.column ?? move.screenWidth

        // Each pane where the model says it is, or the pictures would be
        // cut in the wrong places and would not meet.
        for strip in move.strips where strip.taken == .before {
            if let wrong = misplaced(strip.pane, x: strip.x, width: strip.width, stage: stage) {
                return refused(wrong)
            }
        }
        let anew = move.strips.contains { $0.taken == .after } || move.bars?.coming != nil
        var veil: UIView?
        if anew {
            guard let screen = still(of: bounds, in: root) else {
                return refused("no picture of the screen")
            }
            veil = screen
        }

        // The words of an empty pane, centred where the model says, and
        // their picture, cut before anything is put over them.
        var label: (frame: CGRect, picture: UIView, middle: PaneMove.Middle)?
        if let middle = move.placeholder {
            guard let placeholder = stage.placeholder, placeholder.window != nil else {
                return refused("no placeholder")
            }
            let frame = placeholder.convert(placeholder.bounds, to: root)
            guard abs(frame.midX - middle.x) <= 0.5 else {
                return refused("placeholder centred at \(frame.midX), not \(middle.x)")
            }
            guard let picture = still(of: frame, in: root) else {
                return refused("no picture of the placeholder")
            }
            label = (frame, picture, middle)
        }

        // Each pane as it was, its bar and its toolbar with it or its
        // content alone, the width of its strip.
        var before: [PaneMove.Pane: UIView] = [:]
        for strip in move.strips where strip.taken == .before {
            let top = strip.underBar ? barsBottom : 0
            let span = CGRect(x: strip.x, y: top, width: strip.width, height: height - top)
            guard let picture = still(of: span, in: root) else {
                return refused("no picture of the \(strip.pane)")
            }
            var patches: [(CGRect, UIColor)] = []
            if strip.patchesViewButton, let button = stage.viewButton(in: strip.pane) {
                patches.append((button.convert(button.bounds, to: root), Theme.barFill))
            }
            if strip.pane == .message, let label {
                // The words of an empty pane go half as far as the letter's
                // edge, in a picture of their own; in the letter's they
                // would go the whole way and land beside where they are.
                patches.append((label.frame, Theme.canvas))
            }
            before[strip.pane] = piece(picture, size: span.size,
                                       patches: patches.map { ($0.0.offsetBy(dx: -span.minX,
                                                                              dy: -span.minY), $0.1) })
        }

        var barGoing: UIView?
        if let bars = move.bars {
            let span = CGRect(x: 0, y: 0, width: edge, height: barsBottom)
            guard let picture = still(of: span, in: root) else {
                return refused("no picture of the bar")
            }
            let button = move.motion == .spring ? stage.viewButton(in: bars.going) : nil
            barGoing = piece(picture, size: span.size,
                             patches: button.map { [($0.convert($0.bounds, to: root), Theme.barFill)] } ?? [])
        }

        // The letter's actions, Flag to Compose, still: the letter's bar
        // is the same at both ends, so they never move or blink.
        var actions: UIView?
        if let plateX = move.actionsPlateX {
            let span = CGRect(x: plateX, y: 0, width: move.screenWidth - plateX, height: barsBottom)
            guard let picture = still(of: span, in: root) else {
                return refused("no picture of the letter's actions")
            }
            picture.frame = span
            picture.autoresizingMask = []
            actions = picture
        }

        // The corner, still: the view button's glyph where it is at both
        // ends, the buttons in the pictures painted over. Drawn afresh
        // rather than cut, since the button tapped is dimmed as it is let
        // go, and a picture would hold it dimmed.
        var glyph: UIView?
        if move.motion == .spring {
            guard stage.corner.window != nil, let image = stage.corner.imageView else {
                return refused("no glyph in the corner")
            }
            let fresh = UIImageView(image: stage.corner.currentImage)
            fresh.tintColor = Theme.tintBlue
            fresh.contentMode = image.contentMode
            fresh.frame = image.convert(image.bounds, to: root)
            fresh.autoresizingMask = []
            glyph = fresh
        }

        return Cut(move: move, stage: stage, barsBottom: barsBottom, veil: veil, before: before,
                   barGoing: barGoing, label: label, actions: actions, glyph: glyph)
    }

    /// The cover over the panes, once they are laid out and the layout
    /// sweep has looked at them: the panes laid out anew pictured under the
    /// screen as it was, every picture put where it starts, and the motion
    /// started. Taken away at the end, or at the deadline if an end never
    /// comes.
    ///
    /// `afterScreenUpdates: true` here, and from each pane's own view, not
    /// the screen's: the pane as it is now laid out, with the screen as it
    /// was over it on the glass meanwhile.
    func play(_ cut: Cut) {
        finish()
        let move = cut.move, stage = cut.stage, root = stage.root
        let bounds = root.bounds
        let height = bounds.height
        let barsBottom = cut.barsBottom
        let edge = move.column ?? move.screenWidth

        let cover = UIView(frame: bounds)
        cover.backgroundColor = .clear
        // A shield: every touch lands here while the panes move, so a
        // second tap of a trembling finger is not a second change, and a
        // row tapped in flight is not opened under the picture of another.
        // Its own alpha is never animated: at nothing, a view takes no
        // touches.
        cover.isUserInteractionEnabled = true
        // VoiceOver reads the real panes beneath, which are final already.
        cover.accessibilityElementsHidden = true
        cover.autoresizingMask = []
        if let veil = cut.veil {
            veil.frame = bounds
            veil.autoresizingMask = []
            cover.addSubview(veil)
        }
        root.addSubview(cover)
        self.cover = cover

        // The panes that go as they are now laid out.
        var after: [PaneMove.Pane: UIView] = [:]
        for strip in move.strips where strip.taken == .after {
            if let wrong = misplaced(strip.pane, x: strip.toX, width: strip.toShownWidth,
                                     stage: stage) {
                refused(wrong)
                finish()
                return
            }
            let pane = stage.view(for: strip.pane)
            let top = strip.underBar ? barsBottom : 0
            let span = CGRect(x: 0, y: top, width: strip.width, height: height - top)
            guard let picture = laidOut(span, of: pane) else {
                refused("no picture of the \(strip.pane) laid out")
                finish()
                return
            }
            let button = strip.patchesViewButton ? stage.viewButton(in: strip.pane) : nil
            after[strip.pane] = piece(picture, size: span.size, patches: button.map {
                [($0.convert($0.bounds, to: pane).offsetBy(dx: 0, dy: -top), Theme.barFill)]
            } ?? [])
        }
        var barComing: UIView?
        if let coming = move.bars?.coming {
            let pane = stage.view(for: coming)
            let span = CGRect(x: 0, y: 0, width: edge, height: barsBottom)
            guard !pane.isHidden, let picture = laidOut(span, of: pane) else {
                refused("no picture of the bar laid out")
                finish()
                return
            }
            let button = stage.viewButton(in: coming)
            barComing = piece(picture, size: span.size, patches: button.map {
                [($0.convert($0.bounds, to: pane), Theme.barFill)]
            } ?? [])
        }

        // Back to front, in a stage the size of the screen, or of the
        // column and cut off at its edge.
        let pictures = UIView(frame: CGRect(x: 0, y: 0, width: edge, height: height))
        pictures.clipsToBounds = move.column != nil
        pictures.autoresizingMask = []
        var changes: [Change] = []

        // First what shows where a moving column has not yet come: an empty
        // bar with its hairline, and the canvas.
        if let backdrop = move.backdrop {
            let scale = max(root.traitCollection.displayScale, 1)
            pictures.addSubview(self.backdrop(CGRect(x: backdrop.lowerBound, y: 0,
                                                     width: backdrop.upperBound - backdrop.lowerBound,
                                                     height: height),
                                              barsBottom: barsBottom, hairline: 1 / scale))
        }

        // The panes, each in a holder that cuts it off at its edge. The
        // picture keeps its width and its place in the holder whatever the
        // holder's width does: it is never squeezed.
        for strip in move.strips {
            guard let piece = (strip.taken == .before ? cut.before : after)[strip.pane] else { continue }
            let top = strip.underBar ? barsBottom : 0
            let tall = height - top
            if strip.shadow > 0 || strip.toShadow > 0 {
                let width = Theme.paneEdgeShadowWidth
                let shadow = EdgeShadow(frame: CGRect(x: strip.x - width, y: top, width: width,
                                                      height: tall))
                shadow.alpha = strip.shadow
                pictures.addSubview(shadow)
                changes.append(.frame(shadow, to: CGRect(x: strip.toX - width, y: top,
                                                         width: width, height: tall)))
                changes.append(.alpha(shadow, to: strip.toShadow))
            }
            let holder = UIView(frame: CGRect(x: strip.x, y: top, width: strip.width, height: tall))
            holder.clipsToBounds = true
            holder.autoresizingMask = []
            holder.addSubview(piece)
            if strip.dim > 0 || strip.toDim > 0 {
                let dim = UIView(frame: holder.bounds)
                dim.backgroundColor = .black
                dim.alpha = strip.dim
                dim.autoresizingMask = []
                holder.addSubview(dim)
                changes.append(.alpha(dim, to: strip.toDim))
            }
            pictures.addSubview(holder)
            switch move.motion {
            case .spring:
                changes.append(.frame(holder, to: CGRect(x: strip.toX, y: top,
                                                         width: strip.toShownWidth, height: tall)))
            case .crossFade:
                changes.append(.fade(holder, curve: Theme.paneCrossFadeCurve))
            }
        }

        // "No message selected", riding the middle of the letter's column,
        // over the letter's picture and inside it all the way.
        if let label = cut.label {
            label.picture.frame = label.frame
            label.picture.autoresizingMask = []
            pictures.addSubview(label.picture)
            changes.append(.frame(label.picture,
                                  to: label.frame.offsetBy(dx: label.middle.toX - label.middle.x, dy: 0)))
        }

        // The dividers, riding the moving edges.
        for line in move.lines {
            let divider = UIView(frame: CGRect(x: line.x, y: 0, width: Theme.paneDividerWidth,
                                               height: height))
            divider.backgroundColor = Theme.paneDivider
            divider.autoresizingMask = []
            pictures.addSubview(divider)
            changes.append(.frame(divider, to: CGRect(x: line.toX, y: 0,
                                                      width: Theme.paneDividerWidth, height: height)))
        }

        if let actions = cut.actions { pictures.addSubview(actions) }

        // The column's bar: the bar going fades out where the list goes,
        // the bar coming fades in from the other side, over an empty bar.
        if let bars = move.bars {
            for (bar, coming) in [(cut.barGoing, false), (barComing, true)] {
                guard let bar else { continue }
                let frame = CGRect(x: 0, y: 0, width: edge, height: barsBottom)
                bar.frame = coming ? frame.offsetBy(dx: -bars.travel, dy: 0) : frame
                bar.alpha = coming ? 0 : 1
                pictures.addSubview(bar)
                switch move.motion {
                case .spring:
                    changes.append(.bar(bar, to: coming ? frame : frame.offsetBy(dx: bars.travel, dy: 0),
                                        alpha: coming ? 1 : 0))
                case .crossFade:
                    changes.append(.fade(bar, curve: Theme.paneBarCurve))
                }
            }
        }

        if let glyph = cut.glyph { pictures.addSubview(glyph) }

        cover.insertSubview(pictures, at: 0)
        // The screen as it was has served: the pictures are where it was.
        cut.veil?.removeFromSuperview()

        // Should no end come, a second after the motion was due to end.
        // Over the window's speed, so a build slowed down to look at the
        // motion frame by frame is not cut short.
        let total = max(Theme.paneMoveDuration, Theme.paneBarDuration)
        let speed = max(Double(root.window?.layer.speed ?? 1), 0.05)
        DispatchQueue.main.asyncAfter(deadline: .now() + total / speed + 1.0) { [weak self] in
            guard let self, cover === self.cover else { return }
            Diagnostics.log(.note, "pane motion: deadline")
            self.finish()
        }

        CATransaction.begin()
        // Every animation ended, or cut short by the cover going: the
        // screen beneath is final, and the pictures go now.
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, cover === self.cover else { return }
            self.finish()
        }
        for change in changes { apply(change) }
        CATransaction.commit()
    }

    // MARK: - Ending it

    /// Takes the cover away, if one is up, and says whether it did. The
    /// screen beneath is final already, so this is the whole of ending the
    /// motion, at any instant. Called by the end of the motion, and by the
    /// container before anything else lays the panes out, as the iPad
    /// turns, and as the app stops being in front.
    @discardableResult
    func finish() -> Bool {
        guard let cover else { return false }
        self.cover = nil
        cover.removeFromSuperview()
        return true
    }

    // MARK: - Holding still

    /// Where `scroll` comes to rest, as `PaneMove.Rest` reckons it.
    private static func rest(of scroll: UIScrollView) -> PaneMove.Rest {
        let inset = scroll.adjustedContentInset
        return PaneMove.Rest(contentSize: scroll.contentSize, viewSize: scroll.bounds.size,
                             insetTop: inset.top, insetLeft: inset.left,
                             insetBottom: inset.bottom, insetRight: inset.right)
    }

    /// Whether a list or a letter is past either end, bouncing back from a
    /// flick or a pull. The container then makes the change at once and
    /// leaves the bounce alone: its last frame drawn, which a picture would
    /// show, is not where it comes to rest. Read only; nothing is done to it.
    static func isBouncing(_ scroll: UIScrollView) -> Bool {
        !rest(of: scroll).holds(scroll.contentOffset)
    }

    /// A list or a letter still coasting from a flick, inside its ends,
    /// stopped where it is before the pictures are cut, or its rows would
    /// jump to wherever the coasting had taken them when the pictures go.
    /// Nothing done to one that is not moving, nor to one bouncing past an
    /// end, which the container has turned the motion down for already.
    static func holdStill(_ scroll: UIScrollView) {
        let rest = rest(of: scroll)
        guard scroll.isDecelerating, rest.holds(scroll.contentOffset) else { return }
        scroll.setContentOffset(rest.clamped(scroll.contentOffset), animated: false)
    }

    // MARK: - Moving

    /// One thing a picture does between the start and the end. The model
    /// value is set to the end, and Core Animation carries it there from
    /// where it is.
    private enum Change {
        /// To another frame, sideways or narrower, on the spring.
        case frame(UIView, to: CGRect)
        /// Lighter or darker, on the spring.
        case alpha(UIView, to: CGFloat)
        /// A bar sliding and fading, on the bar's own clock.
        case bar(UIView, to: CGRect, alpha: CGFloat)
        /// Faded out where it is, for the motion's duration, on `curve`.
        case fade(UIView, curve: [Float])
    }

    private func apply(_ change: Change) {
        switch change {
        case .frame(let view, let frame):
            let layer = view.layer
            let position = layer.position, size = layer.bounds
            view.frame = frame
            animate(layer, "position", from: NSValue(cgPoint: position),
                    to: NSValue(cgPoint: layer.position), clock: .spring)
            if size != layer.bounds {
                animate(layer, "bounds", from: NSValue(cgRect: size),
                        to: NSValue(cgRect: layer.bounds), clock: .spring)
            }
        case .alpha(let view, let alpha):
            let was = view.layer.opacity
            view.alpha = alpha
            animate(view.layer, "opacity", from: was, to: view.layer.opacity, clock: .spring)
        case .bar(let view, let frame, let alpha):
            let layer = view.layer
            let position = layer.position, was = layer.opacity
            view.frame = frame
            view.alpha = alpha
            animate(layer, "position", from: NSValue(cgPoint: position),
                    to: NSValue(cgPoint: layer.position), clock: .bars)
            animate(layer, "opacity", from: was, to: layer.opacity, clock: .bars)
        case .fade(let view, let curve):
            let was = view.layer.opacity
            view.alpha = 0
            animate(view.layer, "opacity", from: was, to: view.layer.opacity, clock: .fade(curve))
        }
    }

    private enum Clock {
        /// UIKit's spring, critically damped, for `Theme.paneMoveDuration`.
        case spring
        /// The bar's titles and buttons, `Theme.paneBarDuration` on
        /// `Theme.paneBarCurve`.
        case bars
        /// A cross-fade, `Theme.paneMoveDuration` on the curve given.
        case fade([Float])
    }

    private func animate(_ layer: CALayer, _ keyPath: String, from: Any, to: Any, clock: Clock) {
        let animation: CABasicAnimation
        switch clock {
        case .spring:
            let spring = CASpringAnimation(keyPath: keyPath)
            spring.mass = CGFloat(Theme.paneSpringMass)
            spring.stiffness = CGFloat(Theme.paneSpringStiffness)
            spring.damping = CGFloat(Theme.paneSpringDamping)
            spring.initialVelocity = 0
            spring.duration = Theme.paneMoveDuration
            animation = spring
        case .bars:
            animation = CABasicAnimation(keyPath: keyPath)
            animation.duration = Theme.paneBarDuration
            animation.timingFunction = curve(Theme.paneBarCurve)
        case .fade(let points):
            animation = CABasicAnimation(keyPath: keyPath)
            animation.duration = Theme.paneMoveDuration
            animation.timingFunction = curve(points)
        }
        animation.fromValue = from
        animation.toValue = to
        layer.add(animation, forKey: keyPath)
    }

    private func curve(_ points: [Float]) -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: points[0], points[1], points[2], points[3])
    }

    // MARK: - Pieces

    /// Why `pane` is not where the model says, `x` and `width` wide, or nil
    /// when it is.
    private func misplaced(_ pane: PaneMove.Pane, x: CGFloat, width: CGFloat,
                           stage: Stage) -> String? {
        let view = stage.view(for: pane)
        let frame = view.convert(view.bounds, to: stage.root)
        guard view.window != nil, !view.isHidden,
              abs(frame.minX - x) <= 0.5, abs(frame.width - width) <= 0.5 else {
            return "\(pane) at \(frame.minX), \(frame.width) wide, not \(x), \(width)"
        }
        return nil
    }

    /// A still picture of `span` of the screen as it is on the glass now.
    private func still(of span: CGRect, in root: UIView) -> UIView? {
        root.resizableSnapshotView(from: span, afterScreenUpdates: false, withCapInsets: .zero)
    }

    /// A still picture of `span` of `pane` as it is now laid out, drawn
    /// before the picture is taken.
    private func laidOut(_ span: CGRect, of pane: UIView) -> UIView? {
        pane.resizableSnapshotView(from: span, afterScreenUpdates: true, withCapInsets: .zero)
    }

    /// `picture` at the top left of a view of `size`, with each patch
    /// painted over it in its colour: a view button, or the words of an
    /// empty pane.
    private func piece(_ picture: UIView, size: CGSize, patches: [(CGRect, UIColor)]) -> UIView {
        let piece = UIView(frame: CGRect(origin: .zero, size: size))
        piece.autoresizingMask = []
        picture.frame = piece.bounds
        picture.autoresizingMask = []
        piece.addSubview(picture)
        for (frame, colour) in patches {
            let patch = UIView(frame: frame)
            patch.backgroundColor = colour
            patch.autoresizingMask = []
            piece.addSubview(patch)
        }
        return piece
    }

    /// An empty bar, its hairline and the canvas, as a pane with nothing in
    /// it would draw them.
    private func backdrop(_ frame: CGRect, barsBottom: CGFloat, hairline: CGFloat) -> UIView {
        let backdrop = UIView(frame: frame)
        backdrop.backgroundColor = Theme.canvas
        backdrop.autoresizingMask = []
        let band = UIView(frame: CGRect(x: 0, y: 0, width: frame.width, height: barsBottom))
        band.backgroundColor = Theme.barFill
        let rule = UIView(frame: CGRect(x: 0, y: barsBottom, width: frame.width, height: hairline))
        rule.backgroundColor = Theme.separator
        for piece in [band, rule] {
            piece.autoresizingMask = []
            backdrop.addSubview(piece)
        }
        return backdrop
    }

    @discardableResult
    private func refused(_ why: String) -> Cut? {
        Diagnostics.log(.note, "pane motion: \(why); switched at once")
        return nil
    }
}

/// The shadow on a column's leading edge as it goes over another: black at
/// `Theme.paneEdgeShadowOpacity` at its right side, against the edge, and
/// at nothing at its left.
private final class EdgeShadow: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        autoresizingMask = []
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.colors = [UIColor.black.withAlphaComponent(0).cgColor,
                           UIColor.black.withAlphaComponent(CGFloat(Theme.paneEdgeShadowOpacity)).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

#endif
