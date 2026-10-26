import Foundation

/// Mail's bars beside quoted text, in an HTML letter (B-101).
///
/// Mail draws them; a letter does not send them. Its reading pane loads a
/// style sheet of its own over every letter, and in it each quote, Mail's
/// `<blockquote type="cite">` and Gmail's `<blockquote
/// class="gmail_quote">`, has a bar of 1 px down its left, 5 px from its
/// words, no margin, and its words in the bar's colour, all important, at
/// one, two and three levels: violet, teal, then green for the third and
/// deeper. Read from iOS 18.6's own MessageUI, its style sheet and its
/// asset catalog. This app's pane had no such rule, so Mail's bare quote
/// was WebKit's 40 px indent with no bar, and Gmail's own grey bar, 1 px of
/// `#ccc`, all but vanished under the pane's invert (B-050).
///
/// The same rules here, in both of the pane's pages: the page of a letter
/// on its own (`PanePage`), inside `#bm`, and a conversation's stack
/// (`ConversationDocument`), inside `.bm-html`. Only rules are added: the
/// letter's markup is not touched.
///
/// The colours are Mail's LIGHT ones, as they are, because an HTML letter
/// is drawn on white and then inverted with its hue turned back
/// (`invert(1) hue-rotate(180deg)`): on the pane's black they come out
/// about rgb(152, 150, 255), rgb(0, 150, 180) and rgb(0, 163, 0). The
/// second and third are about Mail's dark teal and green, rgb(0, 200,
/// 250) and rgb(87, 217, 119), if darker; the first is bluer than Mail's
/// dark violet, rgb(191, 90, 242). A signature's white sheet is inverted
/// with the rest since B-146, and a quote inside it too.
///
/// A sender's own important rule, written on the quote itself, still wins,
/// as it does in Mail. Plain text quoted with `>` has no bar here; Mail
/// draws one for it too, and that is left to the owner.
enum QuoteBars {

    /// Mail's colours for a quote one, two and three levels deep, and
    /// deeper: violet, teal, green.
    static let colours = ["rgb(88, 86, 214)", "rgb(0, 175, 205)", "rgb(18, 192, 14)"]

    /// One quote, as Mail's style sheet finds one: Mail's `type=cite`,
    /// matched whatever its case, and Gmail's class matched as a word, so
    /// the bar stays if Gmail gives the quote a second class. Either kind
    /// inside either counts as a level.
    static let quote = ":is(blockquote[type=cite i], blockquote[class~=gmail_quote])"

    /// The rules, one line a level, each selector under `scope`, the
    /// element the letter's markup is drawn in.
    static func css(in scope: String) -> String {
        colours.indices.map { level in
            let selector = ([scope] + Array(repeating: quote, count: level + 1))
                .joined(separator: " ")
            let colour = colours[level]
            return selector + " { padding-left: 5px !important; margin: 0 !important; "
                + "border-left: 1px solid \(colour) !important; color: \(colour) !important; }"
        }.joined(separator: "\n")
    }
}
