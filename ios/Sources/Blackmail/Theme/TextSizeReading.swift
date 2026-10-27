// Guarded so this file compiles away on a host without UIKit. What the
// size does is `TextSize`, `RowLines` and `TextSizes`, which the host
// suite runs; this is where the iPad's is read.
#if canImport(UIKit)

import UIKit

extension TextSize.Step {

    /// UIKit's name for a text size. An unspecified one, which a view not
    /// yet on the screen can have, is taken as Large, the factory size.
    init(_ category: UIContentSizeCategory) {
        switch category {
        case .extraSmall: self = .extraSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .extraLarge: self = .extraLarge
        case .extraExtraLarge: self = .extraExtraLarge
        case .extraExtraExtraLarge: self = .extraExtraExtraLarge
        case .accessibilityMedium: self = .accessibilityMedium
        case .accessibilityLarge: self = .accessibilityLarge
        case .accessibilityExtraLarge: self = .accessibilityExtraLarge
        case .accessibilityExtraExtraLarge: self = .accessibilityExtraExtraLarge
        case .accessibilityExtraExtraExtraLarge: self = .accessibilityExtraExtraExtraLarge
        default: self = .large
        }
    }
}

extension TextSize {

    /// What the app is drawn at when iOS hands it `category`: Large, the
    /// factory size, whatever `category` is (`drawn(at:bold:)`, the owner's
    /// ruling of 2026-10-27), with Bold Text as iOS has it for the app now,
    /// which is the whole iPad's switch, or the one in Per-App Settings set
    /// for the app alone.
    init(_ category: UIContentSizeCategory) {
        self = .drawn(at: Step(category), bold: UIAccessibility.isBoldTextEnabled)
    }
}

extension UITraitCollection {

    /// Large, the text size an iPad comes with, for what UIKit draws in the
    /// app's screens by itself: a list configuration's room for its icon
    /// and the gaps beside its words, Edit mode's circles, a calendar, any
    /// type of UIKit's own. Put on the panes (`RootViewController`), the
    /// app's sheets (`UINavigationController.formSheet`) and the share
    /// sheet's form, so that none of it grows or moves with the iPad's text
    /// size either, as B-071 held the folders and the list (B-166, Changed
    /// 2026-10-27). Bold Text is not held: it is a trait of its own. What
    /// is put up over them, a question, an action sheet, a menu, and the
    /// setup form, which has no parent to hold it, are held by the
    /// window's limits of Large (`AppDelegate`; the share sheet's in its
    /// `viewWillAppear`). B-071 saw one thing the trait does not hold:
    /// Edit mode's circles, their size held, sit lower in their rows at
    /// the larger sizes, 12.5 points at the largest.
    static let heldTextSize = UITraitCollection(preferredContentSizeCategory: .large)
}

extension UINavigationController {

    /// One of the app's sheets: `root` in a navigation controller, shown as
    /// a form sheet, held at Large (`UITraitCollection.heldTextSize`). A
    /// sheet is presented over the whole screen and takes the iPad's text
    /// size from it, not the panes' held one, so it is held on its own,
    /// through its presentation, with everything pushed on it.
    static func formSheet(_ root: UIViewController) -> UINavigationController {
        let nav = UINavigationController(rootViewController: root)
        nav.modalPresentationStyle = .formSheet
        nav.presentationController?.overrideTraitCollection = .heldTextSize
        return nav
    }
}

extension TextSizes {

    /// The app's, made at launch before the first screen is (`AppDelegate`),
    /// which puts the size the app is drawn at in `Theme` there: Large,
    /// whatever size iOS hands the app, `preferredContentSizeCategory`,
    /// the one set for it alone in Per-App Settings or the iPad's
    /// (`TextSize.drawn`); and Bold Text. Read again when iOS says either has changed, and as the app
    /// comes back to the front, should a word have been missed while it was
    /// away. Never in the share extension, which has no `UIApplication` of
    /// its own and reads its sheet's traits (`ShareViewController`).
    static let app = TextSizes(
        names: [UIContentSizeCategory.didChangeNotification,
                UIAccessibility.boldTextStatusDidChangeNotification,
                UIApplication.didBecomeActiveNotification],
        read: { TextSize(UIApplication.shared.preferredContentSizeCategory) },
        apply: { Theme.textSize = $0 })
}

#endif
