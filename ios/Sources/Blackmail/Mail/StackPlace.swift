import Foundation

/// A conversation's stack when the header above it changes height (B-074,
/// B-128).
///
/// The reading pane's header names one letter of the stack: the newest as
/// it opens, then each letter he opens by its line
/// (`MessageDetailViewController.focusLetter`). Letters of one conversation
/// differ in their recipients and files, a Cc line or a 44 pt row each, so
/// the header can grow or shrink as he opens one, and the stack is pinned
/// under it.
///
/// The stack hangs from the header: its scroll offset stays what it was, so
/// what was at the top of the pane stays at the top, wholly under the
/// header, and the stack moves down on the glass as the header grows and
/// up as it shrinks, by as much. Nothing of it goes under the header.
///
/// B-074 had scrolled the stack the other way, by as much as the header
/// grew or shrank, so the line he tapped stayed where it was on the glass.
/// That took the top of the pane under the header: a stack opened with a
/// letter's line at the top of the pane, as it opens (`opensAt`), and that
/// line tapped, had half of it under a header that gained a Cc line, and
/// the stack scrolled to its very top lost its first line the same way,
/// until he scrolled (B-128). A header that shrank showed a sliver of the
/// line above at the top. The line he taps now moves with the stack, by the
/// header's change.
///
/// Out of the controller, which is UIKit, so the rule is tested on the
/// host.
enum StackPlace {

    /// The stack's scroll offset once the header above it has grown by
    /// `grown` points (shrunk, when negative): the one it had, `current`,
    /// kept within `range`, what the stack can be scrolled to now. Nil when
    /// nothing is to change: the header the same height, and every other
    /// time but where a header that shrank leaves a stack scrolled to its
    /// end past what it can scroll to now. It is then put at its end, which
    /// moves it down, never up under the header.
    static func offset(from current: Double, headerGrewBy grown: Double,
                       range: ClosedRange<Double>) -> Double? {
        guard grown != 0 else { return nil }
        let kept = min(max(current, range.lowerBound), range.upperBound)
        return kept == current ? nil : kept
    }
}
