// Guarded so this file compiles away on a host without UIKit.
#if canImport(UIKit)

import UIKit

/// The view button's switch, moving (B-066). Where each picture goes is
/// `PaneMove`'s; this is the UIKit half, the only place in the app that
/// animates a view.
///
/// The motion is made of pictures and nothing else. At the tap `cut` takes
/// still pictures of the screen as it is, before anything is laid out
/// anew, and builds a cover of them off the screen. The container then
/// lays the real panes out in the new arrangement at once, as it always
/// has, and `play` puts the cover over them and slides its pictures. No
/// real view is ever moved, faded, hidden late or made to ignore a touch
/// by this: the real screen is final from the tap, and the cover only
/// hides it for 0.6 s. So ending the motion at any instant, for any
/// reason, is taking the cover away, and what is under it is right.
///
/// Plain views placed by their frames, no constraints, and block
/// animations only: nothing here can be left half done by a call made in
/// the wrong state, and nothing it builds outlives the cover.
@MainActor
final class PaneMotion {

    /// Whether the switch fades rather than slides: Reduce Motion or
    /// Prefer Cross-Fade Transitions, either of which he, or whoever helps
    /// him, can turn on at any time, so read at every tap. VoiceOver and
    /// Switch Control do not change the motion, as they do not in Apple's
    /// own apps.
    static var dissolving: Bool {
        UIAccessibility.isReduceMotionEnabled || UIAccessibility.prefersCrossFadeTransitions
    }

    /// What the pictures are cut from: the container's view, its three
    /// panes, the view button tapped, the list's twin of it, the letter's
    /// bar, whose bottom is where the bars end, and the words of an empty
    /// pane.
    struct Stage {
        let root: UIView
        let mailboxes: UIView
        let list: UIView
        let message: UIView
        /// The view button in the bar of the left column before the switch.
        let tapped: UIButton
        /// The view button in the list's bar in two panes.
        let listTwin: UIButton
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
    }

    /// A cover built at the tap and not yet on the screen.
    struct Cut {
        fileprivate let root: UIView
        fileprivate let cover: UIView
        /// Everything that shows, under the cover. The only thing that fades.
        fileprivate let pictures: UIView
        fileprivate let timeline: [PaneMove.Phase]
        /// Each strip's holder and each line, and the frame it slides to.
        /// Empty for a dissolve.
        fileprivate let arrivals: [(view: UIView, frame: CGRect)]
    }

    /// The cover on the screen, if a switch is moving.
    private var cover: UIView?

    // MARK: - At the tap

    /// The pictures for `move`, cut from the screen as it is now, before the
    /// container lays anything out. Nil, with a line in the connection log,
    /// when they cannot be trusted to match the screen, and the switch is
    /// then made at once, as it always was.
    ///
    /// `afterScreenUpdates: false` throughout: what is on the glass now,
    /// not what the next frame will draw. The panes are laid out anew in
    /// this same turn of the run loop, under the cover, and the screen
    /// without the cover is never drawn.
    func cut(_ move: PaneMove, stage: Stage, dissolving: Bool) -> Cut? {
        let root = stage.root
        guard root.window != nil else { return refused("not in a window") }
        let bounds = root.bounds
        let timeline = PaneMove.timeline(dissolving: dissolving)

        let cover = UIView(frame: bounds)
        cover.backgroundColor = .clear
        // A shield: every touch lands here while the switch moves, so a
        // second tap of a trembling finger is not a second switch, and a
        // row tapped in flight is not opened under the picture of another.
        // Its own alpha is never animated: at nothing, a view takes no
        // touches.
        cover.isUserInteractionEnabled = true
        // VoiceOver reads the real panes beneath, which are final already.
        cover.accessibilityElementsHidden = true
        cover.autoresizingMask = []
        let pictures = UIView(frame: cover.bounds)
        pictures.autoresizingMask = []
        cover.addSubview(pictures)

        if dissolving {
            guard let screen = still(of: bounds, in: root) else {
                return refused("no picture of the screen")
            }
            pictures.addSubview(screen)
            return Cut(root: root, cover: cover, pictures: pictures, timeline: timeline,
                       arrivals: [])
        }

        // Each pane where the model says it is, or the pictures would be
        // cut in the wrong places and the strips would not meet.
        for strip in move.strips {
            let pane = stage.view(for: strip.pane)
            let frame = pane.convert(pane.bounds, to: root)
            guard abs(frame.minX - strip.x) <= 0.5, abs(frame.width - strip.width) <= 0.5 else {
                return refused("\(strip.pane) at \(frame.minX), \(frame.width) wide, "
                               + "not \(strip.x), \(strip.width)")
            }
        }
        guard stage.tapped.window != nil, let glyph = stage.tapped.imageView else {
            return refused("no glyph in the corner")
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
        let height = bounds.height
        let barsBottom = stage.letterBar.convert(stage.letterBar.bounds, to: root).maxY
        var arrivals: [(view: UIView, frame: CGRect)] = []

        // Bottom to top. First what shows where a moving column has not yet
        // come: an empty bar with its hairline, and the canvas.
        if let from = move.backdropFrom {
            let scale = max(root.traitCollection.displayScale, 1)
            pictures.addSubview(backdrop(CGRect(x: from, y: 0, width: move.screenWidth - from,
                                                height: height),
                                         barsBottom: barsBottom, hairline: 1 / scale))
        }

        // The panes, each a whole column with its bar and its toolbar, in a
        // holder that cuts it off at its edge. The picture keeps its width
        // and its place in the holder whatever the holder's width does: it
        // is never squeezed.
        for strip in move.strips {
            let span = CGRect(x: strip.x, y: 0, width: strip.width, height: height)
            guard let picture = still(of: span, in: root) else {
                return refused("no picture of the \(strip.pane)")
            }
            let holder = UIView(frame: span)
            holder.clipsToBounds = true
            holder.autoresizingMask = []
            picture.frame = CGRect(origin: .zero, size: span.size)
            picture.autoresizingMask = []
            holder.addSubview(picture)
            if strip.patchesViewButton {
                // The twin stays in the corner, as the glyph on the corner
                // plate; its picture would otherwise ride away with the list.
                guard stage.listTwin.window != nil else { return refused("no twin to cover") }
                let twin = stage.listTwin.convert(stage.listTwin.bounds, to: root)
                let patch = UIView(frame: twin.offsetBy(dx: -strip.x, dy: 0))
                patch.backgroundColor = Theme.barFill
                patch.autoresizingMask = []
                holder.addSubview(patch)
            }
            if strip.pane == .message, let label {
                // The words of an empty pane go half as far as the letter's
                // edge, in a picture of their own; in the letter's they
                // would go the whole way and land beside where they are.
                let patch = UIView(frame: label.frame.offsetBy(dx: -strip.x, dy: 0))
                patch.backgroundColor = Theme.canvas
                patch.autoresizingMask = []
                holder.addSubview(patch)
            }
            pictures.addSubview(holder)
            arrivals.append((holder, CGRect(x: strip.toX, y: 0, width: strip.toShownWidth,
                                            height: height)))
        }

        // "No message selected", riding the middle of the letter's column,
        // over the letter's picture and inside it all the way.
        if let label {
            label.picture.frame = label.frame
            label.picture.autoresizingMask = []
            pictures.addSubview(label.picture)
            arrivals.append((label.picture,
                             label.frame.offsetBy(dx: label.middle.toX - label.middle.x, dy: 0)))
        }

        // The dividers, riding the moving edges.
        for line in move.lines {
            let divider = UIView(frame: CGRect(x: line.x, y: 0, width: Theme.paneDividerWidth,
                                               height: height))
            divider.backgroundColor = Theme.paneDivider
            divider.autoresizingMask = []
            pictures.addSubview(divider)
            arrivals.append((divider, CGRect(x: line.toX, y: 0, width: Theme.paneDividerWidth,
                                             height: height)))
        }

        // The letter's actions, Flag to Compose, still: the letter's bar
        // is the same at both ends, so they never move or blink.
        let actionsSpan = CGRect(x: move.actionsPlateX, y: 0,
                                 width: move.screenWidth - move.actionsPlateX, height: barsBottom)
        guard let actions = still(of: actionsSpan, in: root) else {
            return refused("no picture of the letter's actions")
        }
        actions.frame = actionsSpan
        actions.autoresizingMask = []
        pictures.addSubview(actions)

        // The corner, still: the view button's glyph where it is at both
        // ends. Drawn afresh rather than cut, since the button tapped is
        // dimmed as it is let go, and a picture would hold it dimmed.
        let button = stage.tapped.convert(stage.tapped.bounds, to: root)
        let corner = UIView(frame: CGRect(x: 0, y: 0, width: button.maxX, height: button.maxY))
        corner.backgroundColor = Theme.barFill
        corner.autoresizingMask = []
        let fresh = UIImageView(image: stage.tapped.currentImage)
        fresh.tintColor = Theme.tintBlue
        fresh.contentMode = glyph.contentMode
        fresh.frame = glyph.convert(glyph.bounds, to: root)
        fresh.autoresizingMask = []
        corner.addSubview(fresh)
        pictures.addSubview(corner)

        return Cut(root: root, cover: cover, pictures: pictures, timeline: timeline,
                   arrivals: arrivals)
    }

    /// The cover over the panes, once they are laid out and the layout
    /// sweep has looked at them, and the motion started: the slide, then
    /// the settle, or the dissolve alone. Taken away at the end, or at the
    /// deadline if an end never comes.
    func play(_ cut: Cut) {
        finish()
        cut.root.addSubview(cut.cover)
        self.cover = cut.cover
        let cover = cut.cover
        let pictures = cut.pictures

        var slide: TimeInterval = 0, settle: TimeInterval = 0, dissolve: TimeInterval = 0
        for phase in cut.timeline {
            switch phase {
            case .slide(let t): slide = t
            case .settle(let t): settle = t
            case .dissolve(let t): dissolve = t
            }
        }

        // Should no end come, a second after the motion was due to end.
        // Over the window's speed, so a build slowed down to look at the
        // motion frame by frame is not cut short.
        let total = cut.timeline.map(\.duration).reduce(0, +)
        let speed = max(Double(cut.root.window?.layer.speed ?? 1), 0.05)
        DispatchQueue.main.asyncAfter(deadline: .now() + total / speed + 1.0) { [weak self] in
            guard let self, cover === self.cover else { return }
            Diagnostics.log(.note, "pane motion: deadline")
            self.finish()
        }

        if dissolve > 0 {
            fade(pictures, for: dissolve, under: cover)
            return
        }
        UIView.animate(withDuration: slide, delay: 0, options: [.curveEaseInOut], animations: {
            for arrival in cut.arrivals { arrival.view.frame = arrival.frame }
        }, completion: { [weak self] finished in
            guard let self, cover === self.cover else { return }
            // Cut short by something else: the screen beneath is final,
            // and the pictures go now.
            guard finished else { self.finish(); return }
            self.fade(pictures, for: settle, under: cover)
        })
    }

    /// The pictures fading where they are, and the cover gone once they
    /// have: the settle after the slide, or the whole of a dissolve.
    private func fade(_ pictures: UIView, for duration: TimeInterval, under cover: UIView) {
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut],
                       animations: { pictures.alpha = 0 },
                       completion: { [weak self] _ in
            guard let self, cover === self.cover else { return }
            self.finish()
        })
    }

    // MARK: - Ending it

    /// Takes the cover away, if one is up, and says whether it did. The
    /// screen beneath is final already, so this is the whole of ending the
    /// motion, at any instant. Called by every completion, and by the
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
    /// flick or a pull. The container then makes the switch at once and
    /// leaves the bounce alone: its last frame drawn, which a picture would
    /// show, is not where it comes to rest. Read only; nothing is done to it.
    static func isBouncing(_ scroll: UIScrollView) -> Bool {
        !rest(of: scroll).holds(scroll.contentOffset)
    }

    /// A list or a letter still coasting from a flick, inside its ends,
    /// stopped where it is before the pictures are cut, or its rows would
    /// jump to wherever the coasting had taken them when the pictures fade.
    /// Nothing done to one that is not moving, nor to one bouncing past an
    /// end, which the container has turned the motion down for already.
    static func holdStill(_ scroll: UIScrollView) {
        let rest = rest(of: scroll)
        guard scroll.isDecelerating, rest.holds(scroll.contentOffset) else { return }
        scroll.setContentOffset(rest.clamped(scroll.contentOffset), animated: false)
    }

    // MARK: - Pieces

    /// A still picture of `span` of the screen as it is on the glass now.
    private func still(of span: CGRect, in root: UIView) -> UIView? {
        root.resizableSnapshotView(from: span, afterScreenUpdates: false, withCapInsets: .zero)
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

    private func refused(_ why: String) -> Cut? {
        Diagnostics.log(.note, "pane motion: \(why); switched at once")
        return nil
    }
}

#endif
