import Foundation

/// His Refresh, in its order (B-072): the folder's newest page, then the
/// folder counts, and once both have come, the pass over the letters kept
/// on the iPad that sends every letter waiting in the Outbox, a large one
/// too (`LocalDrafts.Pass.refresh`).
///
/// The owner's rule, to match Mail: Refresh sends what waits in the
/// Outbox. A letter in the Outbox whose files come from Gmail first, a
/// forward of a video, fetches them over the one IMAP connection, and an
/// exchange on the wire is never cut short (`IMAPClient.Priority`). That
/// fetch waits in the line his taps wait in, ahead of the previews and the
/// counts, so it is asked for only once they have come: what he asked to
/// see is not held behind it.
///
/// A page that could not be fetched sets no pass off, as before: there is
/// no connection for one. The counts are asked for whether or not it came,
/// as Refresh has always asked for them.
///
/// Out of `MessageListViewController` for the reason `SearchAnswer` is: the
/// controller is UIKit and does not exist on the machine the suite runs on.
enum RefreshTap {

    /// `page` fetches the folder's newest page, with no pass of its own, and
    /// says whether it came; `counts` asks for the folder counts; `shown`
    /// returns once the page's previews and the counts have come; `pass`
    /// sets the Refresh's pass off.
    @MainActor
    static func run(page: @MainActor () async -> Bool,
                    counts: @MainActor () -> Void,
                    shown: @MainActor () async -> Void,
                    pass: @MainActor () -> Void) async {
        let came = await page()
        counts()
        guard came else { return }
        await shown()
        pass()
    }
}
