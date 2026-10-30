import Foundation

/// Where the Connection log's view is scrolled to so its newest line is in
/// sight (B-186), out of `DiagnosticsViewController` for the reason
/// `RowArrow` is: that is UIKit and does not exist on the machine the suite
/// runs on.
///
/// The view asked its text view to scroll to the log's end as it loaded,
/// before the text view had a size, so nothing moved and the log opened at
/// its oldest line (round r6-p-copy, 2026-10-29: three flings from the top
/// did not reach the line wanted). Now it scrolls once it has been laid
/// out, and after Clear and the Layout button, to this offset. Not Mail's:
/// Mail has no such screen.
enum LogEnd {

    /// The content offset's y that puts the end of `contentHeight` of text
    /// at the foot of a view `viewHeight` high, with its insets as the
    /// scroll view adjusts them: the top, `-insetTop`, for a log shorter
    /// than the view, as a scroll view at rest is.
    static func offset(contentHeight: CGFloat, viewHeight: CGFloat,
                       insetTop: CGFloat, insetBottom: CGFloat) -> CGFloat {
        max(-insetTop, contentHeight - viewHeight + insetBottom)
    }
}
