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
/// The stack is held only at its top, never at its end. The pane works the
/// offset out as soon as the header is laid out, before WebKit has laid the
/// page out again for the web view's new height, so the end the scroll view
/// gives then is the old page's. The stack's last letter is at least as
/// tall as the pane (`min-height: 100vh`), so the page grows as the pane
/// does, and the offset it had is still one it can scroll to. Held to the
/// old end, a stack opened with its newest letter short, the line above it
/// at the top of the pane some 45 pt from the end, was pulled down to that
/// end by a header that shrank by more than 45 pt, a Cc line and a file's
/// row, and part of the line above showed at the top and stayed.
///
/// Out of the controller, which is UIKit, so the rule is tested on the
/// host.
enum StackPlace {

    /// The stack's scroll offset once the header above it has grown by
    /// `grown` points (shrunk, when negative): the one it had, `current`,
    /// and not below `lowest`, the offset at the stack's top. Nil when
    /// nothing is to change: the header the same height, and every other
    /// time but a stack pulled down past its top as the header changes,
    /// which is put at its top, as before. Never held to the end of the
    /// stack; see above.
    static func offset(from current: Double, headerGrewBy grown: Double, lowest: Double) -> Double? {
        guard grown != 0, current < lowest else { return nil }
        return lowest
    }
}
