// Guarded so this file compiles away on a host without UIKit.
#if canImport(UIKit)

import UIKit

/// The app itself, its principal class (`main.swift`), for one answer: the
/// text size the app is drawn at, Large, whatever the iPad's text size or
/// a size set for Blackmail alone in Per-App Settings (B-166, D-025).
///
/// iOS hands an app its text size as `preferredContentSizeCategory`, a
/// read-only property, which this override answers for whatever asks it.
/// On the test iPad, 16.5.1, on 2026-10-28 (round r6-k-fix) the app's
/// questions, action sheets and the bubble's menu kept their frames at
/// Large under a trait of Large and views limited to Large
/// (`UIViewController.heldAtLarge`), and their words still grew at the
/// larger sizes: a `UIAlertController`'s labels did not follow its own
/// traits or its view's limits. They are believed to follow the app's own
/// size, asked here, and that is not shown: they could as well follow the
/// window scene's or the screen's traits, UIKit's private state or the
/// new size iOS's notification of a change carries, which this does not
/// reach. Should they still grow on the iPad, this does not reach them
/// (KNOWN_ISSUES B-166, the second round; TODO B-166, steps 2, 3 and 9).
/// The traits of Large on the panes and the sheets, the window's limits
/// (`AppDelegate`) and `heldAtLarge` stay, each holding what it held. At
/// Large it is the answer iOS gives: nothing changes.
///
/// Bold Text is not a text size and is not touched: iOS's own switch,
/// followed as before (`TextSize.drawn`). The size the app reads for its
/// own type, `TextSizes.app`, reads this answer. The share extension runs
/// in a process of its own, its form hosted in the sharing app's sheet;
/// UIKit makes that process's application, and Blackmail names no
/// principal class there: its form is held by its own traits and window,
/// as before (`ShareViewController`).
public final class BlackmailApplication: UIApplication {

    public override var preferredContentSizeCategory: UIContentSizeCategory { .large }
}

#endif
