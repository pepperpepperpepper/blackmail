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
/// letter's markup is not touched, but for one class on the line before a
/// quote since B-180 (`attributed`).
///
/// Until B-180 the colours for HTML were Mail's LIGHT ones, as they are: an
/// HTML letter is drawn on white and then inverted with its hue turned back
/// (`invert(1) hue-rotate(180deg)`): on the pane's black they come out
/// about rgb(152, 150, 255), rgb(0, 150, 180) and rgb(0, 163, 0). The
/// second and third are about Mail's dark teal and green, rgb(0, 200,
/// 250) and rgb(87, 217, 119), if darker; the first is bluer than Mail's
/// dark violet, rgb(191, 90, 242). A signature's white sheet is inverted
/// with the rest since B-146, and a quote inside it too.
///
/// Since B-169 only a letter Mail turns to the dark is inverted
/// (`LetterScheme`). A letter drawn light, on its own white, has the light
/// colours as they are, as Mail draws one, and as on paper: under `#bm`
/// on its page, `.bm-light` in the stack. A letter drawn in its own
/// colours, the dark among them, has the dark ones, as Mail's system
/// colours are in a page drawn dark: under `#bm`, `.bm-own` in the stack.
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
///
/// **Compared with Mail on 16.5.1, 2026-10-29 (B-180).** Mail's HTML
/// letter in Dark Mode has its quotes in the SAME colours as its plain
/// letter's, its dark ones, whatever its page's colour filter does to the
/// rest; the light colours under the pane's invert came out about the
/// rgb(152, 150, 255) above (round r6-n-compare, C-4b). By the owner's
/// ruling of that day, copy Apple Mail: a letter the pane inverts has
/// `inverted`, the light colours the invert turns into Mail's dark ones,
/// the first exactly, the second and third as near as the invert can come
/// (it clamps). And the line just before a quote, ending "wrote:", Mail
/// draws with the quote's first level, bar and colour, as it draws a plain
/// letter's (B-172): that line is given `attributionClass` as the page is
/// built (`attributed`), and its rule (`attributionCSS`), in each page's
/// palette. A letter with no such line is as it was.
///
/// **Fixed again after the test iPad, 2026-10-29 (round r6-p-copy).** In
/// a Gmail reply Mail draws the nested "wrote:" line, Gmail's
/// `div.gmail_attr` inside the first level before the second, as the
/// second level's: the first level's bar, a bar of its own and its words
/// in the second level's colour, at that level's x. Blackmail drew it as
/// the first level's words with one bar. Now a line before a quote is
/// marked at any depth, and its rule has a line a level, its colour the
/// level of the quote after it.
enum QuoteBars {

    /// Mail's colours for a quote one, two and three levels deep, and
    /// deeper: violet, teal, green.
    static let colours = ["rgb(88, 86, 214)", "rgb(0, 175, 205)", "rgb(18, 192, 14)"]

    /// The same in Mail's Dark Mode, from the same asset catalog: for a
    /// page that is not inverted, a plain letter's on the pane's black.
    static let dark = ["rgb(191, 90, 242)", "rgb(0, 200, 250)", "rgb(87, 217, 119)"]

    /// For a letter the pane inverts (`invert(1) hue-rotate(180deg)`,
    /// `SignatureSheet.invert`): the light colours the invert turns into
    /// `dark`, as Mail's HTML letter has them in Dark Mode (B-180). Solved
    /// with the filter's matrices in sRGB, clamped at the end, which is how
    /// the invert turned Mail's light violet into the measured rgb(152,
    /// 150, 255). The first comes out `dark`'s within a unit; the invert
    /// cannot reach the second and third, so they are the nearest it can:
    /// about rgb(16, 160, 246) for rgb(0, 200, 250), and rgb(93, 204, 118)
    /// for rgb(87, 217, 119).
    static let inverted = ["rgb(201, 100, 252)", "rgb(0, 144, 230)", "rgb(0, 111, 25)"]

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

    /// The class of the line just before a quote that Mail draws with the
    /// quote after it (B-180): the first level's at the top, the second's
    /// inside one quote, and so on.
    static let attributionClass = "bm-attribution"

    /// Its rules under `scope`, one line a level, as `css`'s: the bar and
    /// colour of the quote after the line, `palette`'s first at the top,
    /// its second inside one quote, its third inside two and deeper; each
    /// deeper selector names more quotes, so it weighs more. Its words 5 px
    /// from the bar as a quote's are, so they stand where the quote's words
    /// do, as Mail's do. The 6 px its words move are the bar's room, which
    /// the bar cannot be drawn without; its margins are its own, as they
    /// were. A line inside a quote keeps that quote's bar beside it, as
    /// Mail's nested line has two.
    static func attributionCSS(in scope: String, palette: [String] = colours) -> String {
        palette.indices.map { level in
            let selector = ([scope] + Array(repeating: quote, count: level) + [".\(attributionClass)"])
                .joined(separator: " ")
            let colour = palette[level]
            return selector + " { padding-left: 5px !important; "
                + "border-left: 1px solid \(colour) !important; color: \(colour) !important; }"
        }.joined(separator: "\n")
    }

    /// `html` with `attributionClass` on each element directly before a
    /// quote, at any depth, whose words end "wrote:", as Mail draws such a
    /// line (B-180): Mail's `<p>On Monday, Carlo wrote:</p>`, Gmail's
    /// `div.gmail_attr`, at the top and inside a quote, a `<p>` the quote
    /// closes. Only that line was seen in Mail, as in a plain letter
    /// (`PlainQuotes.isAttribution`, B-172): a line not ending "wrote:",
    /// one with anything but spaces between it and the quote, and words
    /// not in an element of their own are as they were. Its
    /// existing classes are kept, the new one added after them. A letter
    /// with no such line comes back as it came, byte for byte.
    static func attributed(_ html: String) -> String {
        guard html.contains("wrote:"), html.range(of: "blockquote", options: .caseInsensitive) != nil
        else { return html }
        let markup = LetterScheme.Markup(html)
        let edits = markup.attributions().map { markup.classAdded(attributionClass, toTagAt: $0) }
        guard !edits.isEmpty else { return html }
        var bytes = Array(html.utf8)
        for edit in edits.reversed() {
            bytes.replaceSubrange(edit.range, with: Array(edit.text.utf8))
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
