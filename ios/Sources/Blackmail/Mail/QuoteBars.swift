import Foundation

/// Mail's bars beside quoted text (B-101), in an HTML letter and, since
/// B-147, in a plain one.
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
/// The colours for HTML are Mail's LIGHT ones, as they are, because an
/// HTML letter is drawn on white and then inverted with its hue turned back
/// (`invert(1) hue-rotate(180deg)`): on the pane's black they come out
/// about rgb(152, 150, 255), rgb(0, 150, 180) and rgb(0, 163, 0). The
/// second and third are about Mail's dark teal and green, rgb(0, 200,
/// 250) and rgb(87, 217, 119), if darker; the first is bluer than Mail's
/// dark violet, rgb(191, 90, 242). A signature's white sheet is inverted
/// with the rest since B-146, and a quote inside it too.
///
/// A plain letter's quotes, its lines begun with `>`, are made Mail's
/// blockquotes as its page is built (`PlainQuotes`, B-147), and take the
/// same rules, under its own scope: `#bm` on its page, `.bm-text` in the
/// stack. A plain letter is not inverted, its words white on the black, so
/// there the colours are Mail's DARK ones, as Mail draws a plain letter in
/// Dark Mode, its words light on its dark page (`dark`). On paper
/// (`PrintPage`), which is white and not inverted, both kinds of letter
/// have the light ones, as Mail prints them.
///
/// A sender's own important rule, written on the quote itself, still wins,
/// as it does in Mail.
enum QuoteBars {

    /// Mail's colours for a quote one, two and three levels deep, and
    /// deeper: violet, teal, green.
    static let colours = ["rgb(88, 86, 214)", "rgb(0, 175, 205)", "rgb(18, 192, 14)"]

    /// The same in Mail's Dark Mode, from the same asset catalog: for a
    /// page that is not inverted, a plain letter's on the pane's black.
    static let dark = ["rgb(191, 90, 242)", "rgb(0, 200, 250)", "rgb(87, 217, 119)"]

    /// One quote, as Mail's style sheet finds one: Mail's `type=cite`,
    /// matched whatever its case, and Gmail's class matched as a word, so
    /// the bar stays if Gmail gives the quote a second class. Either kind
    /// inside either counts as a level.
    static let quote = ":is(blockquote[type=cite i], blockquote[class~=gmail_quote])"

    /// The rules, one line a level, each selector under `scope`, the
    /// element the letter's markup is drawn in, in `palette`: Mail's light
    /// colours unless it says otherwise.
    static func css(in scope: String, palette: [String] = colours) -> String {
        palette.indices.map { level in
            let selector = ([scope] + Array(repeating: quote, count: level + 1))
                .joined(separator: " ")
            let colour = palette[level]
            return selector + " { padding-left: 5px !important; margin: 0 !important; "
                + "border-left: 1px solid \(colour) !important; color: \(colour) !important; }"
        }.joined(separator: "\n")
    }
}
