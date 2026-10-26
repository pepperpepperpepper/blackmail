import Foundation

/// The cover over the reading pane's letter, from a tap on another letter
/// until WebKit has painted what goes in its place (B-149).
///
/// At a tap on a row the header is UIKit's and changes in the frame of the
/// tap; the web view under it goes on showing what it painted last until
/// WebKit has painted the new document, "Loading…" or a conversation's
/// lines, a frame or two later. On the test iPad that was the letter he had
/// left, under the new letter's header, in 3 taps of 7 (B-098). Mail covers
/// its letter while the next one loads, by the names in its code
/// (`MFMessageContentLoadingView`, `renderingProgressDidChange`); a
/// recording of Mail doing it has not been made.
///
/// So the pane puts a cover in its own colour over the web view at the tap
/// (`tapped`), in the frame the header changes, and lifts it once WebKit
/// says it has painted the document the pane gave it last (`rendered`),
/// and not one before it: its navigation committed (`committed`), and then
/// a painting milestone, which WebKit sends with the layers that hold it
/// (`painted`). And never later than `limit`, the app's own bound, so that a
/// letter is never left hidden under it if WebKit says nothing
/// (`limitPassed`); where WebKit has no such word at all, at the document's
/// end instead (`finished`). A letter opened by its line in a conversation
/// is put in the page already there, with no new document, and has no
/// cover; nor do a body put in, his letters from Sent Mail, a letter come
/// into the conversation, or a page drawn again after WebKit lost it.
///
/// Out of `MessageDetailViewController`, which is UIKit and does not build
/// on the host, for the reason `PaneLoads` is.
struct PaneCover: Equatable {

    /// The longest the cover stays up, in seconds: the app's own bound, not
    /// Mail's, which is not known. "Loading…" came 17 to 33 ms after the
    /// tap on the test iPad, and the letter 67 to 117 ms after that.
    static let limit: TimeInterval = 0.5

    /// WebKit's word that it has painted, private and reached by its name
    /// (`WKNavigationDelegatePrivate`, `_WKRenderingProgressEvents`), the
    /// word Mail's code names. Asked for by its setter, only where the web
    /// view has one (`setter`, `key`, the events in `painted`), and heard by
    /// the pane's method of this name.
    static let callback = "_webView:renderingProgressDidChange:"
    /// The setter of the events the web view tells its navigation delegate
    /// of, and the key that reaches it by key-value coding: `_set<Key>:`.
    static let setter = "_setObservedRenderingProgressEvents:"
    static let key = "observedRenderingProgressEvents"

    /// The milestones that say the document is on screen, each sent with
    /// the layers that show it: its first layout with something to see in
    /// it, which WebKit holds the painting back for; its first paint with a
    /// good part of the view painted; its first paint; and its first paint
    /// that means something. Any of them lifts the cover. The bits as
    /// WebKit's source has them, not read from the iPad's own WebKit.
    static let firstVisuallyNonEmptyLayout: UInt = 1 << 1
    static let firstPaintWithSignificantArea: UInt = 1 << 2
    static let firstPaint: UInt = 1 << 6
    static let firstMeaningfulPaint: UInt = 1 << 8
    static let painted: UInt = firstVisuallyNonEmptyLayout | firstPaintWithSignificantArea
        | firstPaint | firstMeaningfulPaint

    /// Whether the cover is up.
    private(set) var isUp = false
    /// The taps' count, so that the limit of an earlier tap lifts nothing.
    private(set) var tap = 0
    /// The document the pane gave the web view last while the cover is up,
    /// by its navigation; nil before one, or for one WebKit gave none.
    private var awaited: ObjectIdentifier?
    /// That document's navigation has committed: what WebKit paints from
    /// now on is it.
    private var isCommitted = false

    /// A tap on another letter: the cover up, and the number its limit
    /// goes by.
    mutating func tapped() -> Int {
        tap += 1
        isUp = true
        awaited = nil
        isCommitted = false
        return tap
    }

    /// The pane has given the web view a document, its navigation
    /// `navigation`: the one the cover waits for while it is up, in place
    /// of any it gave before, "Loading…" given the letter's page.
    mutating func loaded(_ navigation: ObjectIdentifier?) {
        guard isUp else { return }
        awaited = navigation
        isCommitted = false
    }

    /// WebKit has committed `navigation`.
    mutating func committed(_ navigation: ObjectIdentifier) {
        guard isUp, navigation == awaited else { return }
        isCommitted = true
    }

    /// WebKit has reached the milestones `events`: true when they lift the
    /// cover, a paint of the document awaited.
    mutating func rendered(_ events: UInt) -> Bool {
        guard isUp, isCommitted, events & Self.painted != 0 else { return false }
        lift()
        return true
    }

    /// `navigation` has finished loading: true when that lifts the cover,
    /// which it does only where WebKit tells the pane nothing of its paint
    /// (`painting` false), the document awaited. Where it does, the end of
    /// the load can come before the paint, and the old letter would show.
    mutating func finished(_ navigation: ObjectIdentifier, painting: Bool) -> Bool {
        guard isUp, !painting, navigation == awaited else { return false }
        lift()
        return true
    }

    /// `limit` has passed since the tap `n`: true when that lifts the cover,
    /// the tap the last.
    mutating func limitPassed(_ n: Int) -> Bool {
        guard isUp, n == tap else { return false }
        lift()
        return true
    }

    /// Down: painted, the limit passed, or the pane emptied.
    mutating func lift() {
        isUp = false
        awaited = nil
        isCommitted = false
    }
}
