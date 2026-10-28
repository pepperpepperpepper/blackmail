// Guarded so this file compiles away on a host without UIKit.
#if canImport(UIKit)

import UIKit

/// The app itself, its principal class (`main.swift`), for one answer: the
/// text size the app is drawn at, Large, whatever the iPad's text size or
/// a size set for Blackmail alone in Per-App Settings (B-166, D-025).
///
/// iOS hands an app its text size as `preferredContentSizeCategory`, and
/// UIKit reads it there for what it draws by that size and not by the
/// traits of the screen it is on. On the test iPad, 16.5.1, on 2026-10-28
/// (round r6-k-fix) the app's questions, action sheets and the bubble's
/// menu kept their frames at Large under a trait of Large and views
/// limited to Large (`UIViewController.heldAtLarge`), and their words still
/// grew at the larger sizes: a `UIAlertController`'s labels follow the
/// app's size. Answered Large here, at the app's root, they have nothing
/// larger to follow. The traits of Large on the panes and the sheets, the
/// window's limits (`AppDelegate`) and `heldAtLarge` stay, each holding
/// what it held. At Large it is the answer iOS gives: nothing changes.
///
/// Bold Text is not a text size and is not touched: iOS's own switch,
/// followed as before (`TextSize.drawn`). The size the app reads for its
/// own type, `TextSizes.app`, reads this answer. The share extension runs
/// inside the app that shares, whose application it cannot replace: it
/// holds its form by its own traits and window, as before
/// (`ShareViewController`).
public final class BlackmailApplication: UIApplication {

    public override var preferredContentSizeCategory: UIContentSizeCategory { .large }
}

#endif
