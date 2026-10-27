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

    /// `category`, with Bold Text as iOS has it for the app now, which is
    /// the whole iPad's switch, or the one in Per-App Settings set for the
    /// app alone.
    init(_ category: UIContentSizeCategory) {
        self.init(step: Step(category), bold: UIAccessibility.isBoldTextEnabled)
    }
}

extension TextSizes {

    /// The app's, made at launch before the first screen is (`AppDelegate`),
    /// which puts the iPad's size in `Theme` there: the size iOS hands the
    /// app, `preferredContentSizeCategory`, which is the one set for it
    /// alone in Per-App Settings when there is one, or the iPad's; and Bold
    /// Text. Read again when iOS says either has changed, and as the app
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
