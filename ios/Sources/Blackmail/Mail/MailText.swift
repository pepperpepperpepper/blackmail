import Foundation

/// Lenient bytes-to-text, in a Foundation-only home.
///
/// This used to live on `TLSConnection`, which imports `Network` and is
/// therefore Apple-only. That single reference was the one thing stopping the
/// parsers — the largest and most bug-prone code in the project — from being
/// compiled and tested on this Linux box without a device. Moving four lines
/// buys a test suite that runs in two seconds instead of a build, sign, deploy
/// and screenshot cycle.
enum MailText {

    /// UTF-8 if it decodes, Latin-1 otherwise.
    ///
    /// Latin-1 is the deliberate fallback because it is total: every byte
    /// sequence maps to *some* string, so it cannot fail. A mail client that
    /// throws on a badly encoded header turns one malformed message into a
    /// dead mailbox, and the person reading it cannot tell the difference
    /// between "this letter is broken" and "the app is broken". Mojibake in
    /// one subject line is a far better outcome.
    static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    /// What the reading pane should say when a letter has nothing in it.
    static let emptyBodyNotice = "This message has no text."

    /// What the reading pane says above a letter it shows only the
    /// beginning of (`Message.isShortened`).
    static let shortenedNotice = "Only the beginning of this message is shown."

    /// True when there is genuinely nothing to draw.
    ///
    /// The point is not politeness to the sender of an empty letter — it is
    /// that **a blank reading pane should only ever mean a bug**. B-026 was
    /// a message that arrived with a filled-in header and nothing beneath
    /// it, and the reason it took three experiments to chase is that a
    /// blank pane is exactly what an empty letter looks like. Saying so
    /// out loud costs one line and makes the symptom diagnostic: after
    /// this, a pane with nothing in it cannot be explained away.
    ///
    /// A message whose only content is a PICTURE is not empty. Nor is one
    /// whose only content is the sender's signature — which is most of
    /// what a subject-only letter from an Apple Mail user contains, and
    /// why this fires far less often than it first appears it should.
    static func hasNoVisibleContent(text: String?, html: String?) -> Bool {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        guard let html, !html.isEmpty else { return true }
        // An image with no words around it is a letter, and a common one:
        // people send a photograph and say nothing.
        if html.range(of: "<img", options: .caseInsensitive) != nil { return false }
        return HTMLText.plainText(from: html)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
