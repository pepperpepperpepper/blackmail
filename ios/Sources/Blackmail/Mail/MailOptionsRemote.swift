import Foundation

/// Two of Mail's options under Messages in Settings > Apps > Mail on his
/// iPad that the app did not have (B-168): Privacy Protection's Block All
/// Remote Content, and Ask Before Deleting. No app can read either off his
/// iPad, so each is stored here, at Mail's factory value, and matched in
/// Blackmail's Settings on the day (B-167's rows; TODO, "On the day"),
/// with no build; the owner's ruling of 2026-10-26.
///
/// What each does is elsewhere: `RemoteContent` and `RemotePictures` for
/// the pictures from the web, `DiscardQuestion` for the question before a
/// Trash or an Archive. Here is only what he has chosen, read from one
/// place. Blackmail's own Settings shows the two rows (B-167); there is no
/// row in this file's change.
///
/// Each under its own key in `UserDefaults`, read with `object(forKey:)`,
/// as `ConversationSettings` reads its switches: a key never written, or one
/// written as something else, is Mail's factory value. Not in `SafeStart`'s
/// view settings: they are his, as `NextLetter.action` is, and a safe start
/// does not take them back.
///
/// Foundation-only, so the factory values and the round trip are tested on
/// the Linux host.
enum MessagesOptions {

    /// Not private, for the suite to hold it to its spelling.
    static let blockAllRemoteContentKey = "blackmail.blockAllRemoteContent"

    /// Mail's Block All Remote Content, under Privacy Protection: pictures
    /// and the rest of a letter's content from the web not loaded, the line
    /// "Message contains unloaded images." over the letter, and "Load All
    /// Images" on it (`RemoteContent`). Off unless set otherwise, as Mail's
    /// first launch leaves it for "Protect Mail activity" and for "Don't
    /// protect Mail activity" alike: the switch is shown only with Protect
    /// Mail Activity off, and is off there until it is turned on. Under
    /// every other choice his pictures load in Mail with no line, as
    /// Blackmail's do, by Apple's relay or directly: the same on his
    /// screen.
    static var blockAllRemoteContent: Bool {
        get {
            UserDefaults.standard.object(forKey: blockAllRemoteContentKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: blockAllRemoteContentKey)
        }
    }

    /// Not private, for the reason the other key is not.
    static let askBeforeDeletingKey = "blackmail.askBeforeDeleting"

    /// Mail's Ask Before Deleting: a Trash or an Archive of a letter asks
    /// first, with Mail's words, but for a full drag on a row, which goes
    /// at once (`DiscardQuestion`). Off unless set otherwise, as it comes
    /// from the factory by third-party guides; Apple's own guide, telling
    /// how to turn it off, reads as if it were on, and his is matched on
    /// the day whichever it is. The question before an erase inside Trash
    /// (`EraseQuestion`) is asked whatever this says, as it always was.
    static var askBeforeDeleting: Bool {
        get {
            UserDefaults.standard.object(forKey: askBeforeDeletingKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: askBeforeDeletingKey)
        }
    }
}
