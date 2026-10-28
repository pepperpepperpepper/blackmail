import Foundation

/// Quick Look's bars over a picture, from iOS 18 (B-176, B-171).
///
/// iOS 18's Quick Look opens a picture with its bars hidden, the status
/// bar, Done and Markup with them, until a tap on it, in every app: Files
/// on the iOS 18.6 simulator did it too, and so did a test app of a plain
/// full-screen `QLPreviewController`. A PDF opens with its bars, and 16
/// and 17 open everything with them. Quick Look decides it once, as it is
/// presented, in its method of the name `decider`, which hides the bars
/// unless its flag of the name `flag` says it has decided already; the
/// names were read from QuickLook in the iOS 18.6 runtime. No public
/// setting reaches it.
///
/// So from iOS 18 the pane sets that flag before it presents Quick Look,
/// only where Quick Look has both the method and the flag, and Quick Look
/// opens with its bars as on 16 and 17; a tap still hides and shows them.
/// On 16 and 17 nothing is set.
///
/// Out of `MessageDetailViewController`, which is UIKit and does not build
/// on the host, for the reason `PaneCover` is.
enum QuickLookBars {

    /// Quick Look's method that hides them, run once as it is presented.
    static let decider = "_setDefaultFullscreenStateIfNeeded"
    /// Its flag that it has run, reached by key-value coding.
    static let flag = "_didSetDefaultFullscreenState"
}
