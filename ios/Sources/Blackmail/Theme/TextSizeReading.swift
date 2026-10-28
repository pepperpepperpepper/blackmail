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
    /// is put up over them, a question, an action sheet, the bubble menu
    /// and the Share sheet, is held by its own presentation and view
    /// (`UIViewController.heldAtLarge`): the window's limits of Large
    /// (`AppDelegate`; the share sheet's in its `viewWillAppear`), which
    /// hold the setup form, the window's first screen with no parent to
    /// hold it, did not reach them on the test iPad. B-071 saw one thing the trait does not hold:
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

extension UIViewController {

    /// A question, an action sheet or the Share sheet the app puts up,
    /// held at Large (`UITraitCollection.heldTextSize`) as the app's sheets
    /// are (`UINavigationController.formSheet`): through its presentation,
    /// which on the iPad is an action sheet's popover, and its own view,
    /// and what is in it, limited to Large, the least and the most, should
    /// an alert's presentation not hand its trait on. The window's limits
    /// did not reach them: on the test iPad, 16.5.1, the bubble menu, the
    /// Reply sheet, the Flag popover and Add Another Email grew at the
    /// larger sizes while every screen under them stayed as at Large
    /// (B-166, found 2026-10-28). Called on every one the app makes, before
    /// or after its popover's place is set, the popover being the same one
    /// either way, as it is presented, or as its maker hands it back
    /// (`DiscardConfirmation`); at Large it changes nothing. It held their
    /// frames and not their words, which still grew at the larger sizes
    /// on 16.5.1 (round r6-k-fix, 2026-10-28), an alert's labels not
    /// following its traits or its view's limits. They are believed to
    /// follow the app's own size, not shown, which is answered Large at
    /// the app's root since (`BlackmailApplication`), and this stays
    /// beside it.
    /// Any trait UIKit put on the presentation itself is kept, the size
    /// alone laid over it.
    @discardableResult func heldAtLarge() -> Self {
        if let presentation = presentationController {
            presentation.overrideTraitCollection = UITraitCollection(
                traitsFrom: [presentation.overrideTraitCollection, .heldTextSize].compactMap { $0 })
        }
        view.minimumContentSizeCategory = .large
        view.maximumContentSizeCategory = .large
        return self
    }
}

extension TextSizes {

    /// The app's, made at launch before the first screen is (`AppDelegate`),
    /// which puts the size the app is drawn at in `Theme` there: Large,
    /// whatever size iOS hands the app, `preferredContentSizeCategory`,
    /// the one set for it alone in Per-App Settings or the iPad's
    /// (`TextSize.drawn`); and Bold Text. The app's own answers Large
    /// since round r6-k-fix (`BlackmailApplication`, B-166), so iOS's word
    /// that the size changed reads Large again and draws nothing; only
    /// Bold Text says `didChange`. Read again when iOS says either has changed, and as the app
    /// comes back to the front, should a word have been missed while it was
    /// away. Never in the share extension, a process of its own that may
    /// not ask `UIApplication.shared`, which reads its sheet's traits
    /// (`ShareViewController`).
    static let app = TextSizes(
        names: [UIContentSizeCategory.didChangeNotification,
                UIAccessibility.boldTextStatusDidChangeNotification,
                UIApplication.didBecomeActiveNotification],
        read: { TextSize(UIApplication.shared.preferredContentSizeCategory) },
        apply: { Theme.textSize = $0 })
}

#endif
