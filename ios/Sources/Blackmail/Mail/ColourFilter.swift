import Foundation

/// WebKit's colour filter, the way Mail makes an HTML letter dark, used by
/// the reading pane under the iPad's Smart Invert alone (B-179).
///
/// Mail's Dark Mode for an HTML letter is `-apple-color-filter:
/// apple-invert-lightness()`: it turns the colours named in the letter's
/// style, its words, its grounds and its borders, and never a picture's
/// pixels. Under Smart Invert, which inverts what the app draws plainly,
/// Mail's photos come out inverted with the rest of its page. The pane's
/// own invert is a CSS filter, `invert(1) hue-rotate(180deg)`, on the
/// letter and so above its photos, and a filter of a photo's own does not
/// draw under the switch (round r6-p-copy, 2026-10-29: four cases
/// measured), so its photos came out hue-turned whatever the pane did to
/// them. Under the switch, and where the page says it works, the pane
/// makes a letter it inverts dark with the colour filter instead, no
/// filter above its photos (`SmartInvert.colourFilter`).
///
/// The filter is behind a setting of WebKit's own, off by default, which
/// Mail turns on: private, `WKPreferences`' `_setColorFilterEnabled:`
/// (`WKPreferencesPrivate.h`, since iOS 12), reached by key-value coding
/// with `key`, only where the preferences have the setter and the getter,
/// as `PaneCover` reaches its private setter. Whether CSS takes the
/// property is asked of the page itself (`question`), as a renamed key or
/// property would leave the setting a no-op: the pane uses the filter only
/// on that answer, and with none the page is as it was.
///
/// Pure, so the suite on Linux pins the names.
enum ColourFilter {

    /// The setting's setter and getter, by their names, which the
    /// preferences are asked about before `key` is used.
    static let setter = "_setColorFilterEnabled:"
    static let getter = "_colorFilterEnabled"
    /// The key that reaches them by key-value coding: `_set<Key>:` and
    /// `_<key>`.
    static let key = "colorFilterEnabled"

    /// The property and the value Mail's style sheet gives a letter.
    static let property = "-apple-color-filter"
    static let value = "apple-invert-lightness()"

    /// What the page is asked, by `callAsyncJavaScript` in the app's
    /// content world, once per web view, when the setting reads back on:
    /// whether its CSS takes the property and the value.
    static let test = "CSS.supports('\(property)', '\(value)')"
    static let question = "return \(test);"

    /// What the page answered, or that there was no setting to ask with.
    enum Answer: String {
        case supported = "true"
        case unsupported = "false"
        /// The preferences have no setter or no getter, or the setting did
        /// not read back on: nothing was asked.
        case absent
    }

    /// The pane's log line for the answer, once per web view, for the
    /// device check to read before the photos.
    static func note(_ answer: Answer) -> String {
        "pane: colour filter supported \(answer.rawValue)"
    }
}
