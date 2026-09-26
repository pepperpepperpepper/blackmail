import Foundation

/// Whether the message list groups a conversation and its replies into
/// one row — Mail's own "Organize by Thread" setting.
///
/// Measured against 600 of Sam's messages, grouping hides 11.5% of the
/// Inbox behind rows that announce their own size and disturbs no date by
/// even a week, so it stays ON by default — which is also Mail's default.
/// But three of twelve recent letters from him are about something
/// vanishing, and grouping is the one feature whose mechanic is showing
/// one row where there were several, so the off switch exists and is one
/// line away rather than a code change: `rows(for:grouped:)` reads this.
///
/// Foundation-only, so the default and the round trip are tested on the
/// Linux host like everything else that lives in Mail/.
enum ConversationSettings {

    private static let key = "blackmail.organizeByThread"

    /// Grouped unless he has said otherwise.
    ///
    /// `object(forKey:)` rather than `bool(forKey:)` for the read, because
    /// `bool(forKey:)` answers `false` for a missing key and the default
    /// here is `true` — an absent value and an explicit `false` must not
    /// mean the same thing, or the first launch of every update would
    /// silently ungroup his list.
    static var organizeByThread: Bool {
        get {
            UserDefaults.standard.object(forKey: key) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}
