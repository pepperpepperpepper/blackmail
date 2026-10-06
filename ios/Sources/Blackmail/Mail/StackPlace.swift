import Foundation

/// His place in a conversation's stack when the header above it changes
/// height (B-074).
///
/// The reading pane's header names one letter of the stack: the newest as
/// it opens, then each letter he opens once its body has come
/// (`MessageDetailViewController.focusLetter`). Letters of one conversation
/// differ in their recipients and files, a line or a 44 pt row each, so
/// the header can grow or shrink as he opens one, and the stack, pinned
/// under it, moved down or up on the glass by as much. Now the stack is
/// scrolled by as much the other way, as far as it can scroll, so the line
/// he tapped stays under his finger.
///
/// Out of the controller, which is UIKit, so the arithmetic is tested on
/// the host.
enum StackPlace {

    /// The stack's scroll offset that leaves what he sees where it was on
    /// the glass, once the header above it has grown by `grown` points
    /// (shrunk, when negative), kept within `range`, what the stack can be
    /// scrolled to now. Nil when nothing is to change.
    ///
    /// At the top of a stack shorter than the pane nothing can be done, and
    /// it moves as it did: there is nothing above to scroll to.
    static func offset(from current: Double, headerGrewBy grown: Double,
                       range: ClosedRange<Double>) -> Double? {
        guard grown != 0 else { return nil }
        let kept = min(max(current + grown, range.lowerBound), range.upperBound)
        return kept == current ? nil : kept
    }
}
