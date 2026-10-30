import Foundation

/// A letter in the reading pane under the iPad's Smart Invert, as Mail's
/// comes out under it (B-179).
///
/// The comparison with Mail 16.5.1 on the test iPad of 2026-10-29 (round
/// r6-n-compare, C-1d and C-1e) found Mail's letter, under Smart Invert,
/// the system's plain inversion of its Dark Mode page, pictures and all,
/// for a letter Mail turns to the dark; and a light letter as on paper,
/// its page white, its words black and its link blue, its pictures
/// inverted. Blackmail's pane came out the system's inversion too, but its
/// photos in a letter it inverts hue-turned, their lightness kept, and a
/// light letter's page black with white words: the photos drawn with one
/// of the pane's two inverts where the page means two, and the light page
/// inverted by the system with nothing to undo it.
///
/// So under the switch, and only under it: a letter the pane inverts
/// keeps its invert, and its photos, `img` and `video`, have no filter
/// (`inverted`); a light
/// letter's markup and its white are inverted plainly, `invert(1)` with no
/// half turn of the hue, which the system's inversion undoes, so its page
/// is white, its words black and its link `#007AFF`, as Mail's; its
/// pictures have no filter of the pane's, and Mail's line over it, when
/// its pictures from the web are held back (B-168), is inverted back, so
/// it stays the pane's colour under the system's inversion (`light`). A
/// plain letter, a letter in its own colours, a notice, the printed page
/// and Quick Look are as they were.
///
/// The switch is iOS's (`UIAccessibility.isInvertColorsEnabled`), read by
/// the pane, which follows it while it is open
/// (`MessageDetailViewController`). Apple documents it as Classic
/// Invert's; whether it is true under Smart Invert on 16.5.1 and on 18 is
/// not known, so the pane writes what it read in its log (`note`) for the
/// device check to see. If it is false under Smart Invert, none of this
/// is drawn. Not WebKit's own `@media
/// (inverted-colors)`: the light letter's pictures, with no filter of the
/// app's on them, came out inverted, so WebKit's rule for that query does
/// not take in the pane's web view.
///
/// **Found on the test iPad, 2026-10-29 (r6-p-copy).** The switch is
/// true under Smart Invert on 16.5.1. The photos still came out
/// hue-turned, and a light letter's pictures natural: a filter of a
/// photo's own does not draw under the switch, so taking the pane's
/// second invert off them changed nothing, and the page's invert above
/// them still turns their hue. So, under the switch, a letter the pane
/// inverts is made dark by WebKit's colour filter instead, as Mail's is,
/// where the page says it takes it (`ColourFilter`): with the second class
/// on the root (`colourFilterClass`) and its rules in a sheet of their own
/// (`colourFilter(in:)`), no filter on the letter or its pictures, the
/// pictures drawn as they are and inverted by the system, as Mail's. Where
/// the page does not take it, the page is as before. A light letter's
/// photos are inverted by a filter of their own under the switch, a try:
/// if that filter does not draw either, they stay natural, as before.
///
/// **Found on the test iPad, 2026-10-30 (r6-q-copy).** The colour filter
/// took, the photos inverted as Mail's. The try did not: a light letter's
/// pictures stayed natural, so they are inverted by an element put round
/// each while the switch is on (`wrapperTag`). And with the switch turned
/// off under an open letter its photos stayed hue-turned until it was
/// opened again: a picture drawn while the switch was on goes on being
/// drawn without its own filter after the class comes off, so the script
/// has WebKit draw each such picture anew as the switch goes off
/// (`ConversationDocument.script`'s `bmRepaintPictures`), nothing moved.
///
/// Off, every page is byte for byte as it was. On, a page is built with
/// the class on its `<html>` and its rules in a sheet of their own in its
/// head (`root`, `sheet`); a change of the switch while a page is shown
/// puts the class on or takes it off by the pane's script, the sheet put
/// in if the page has none (`Toggle`), so nothing scrolls; going off, the
/// pictures the class took a filter off are drawn anew, and the elements
/// round a light letter's pictures go and come with the class.
///
/// Pure, so the suite on Linux tests it.
enum SmartInvert {

    /// The class the page's `<html>` has while Smart Invert is on.
    static let className = "bm-si"

    /// The id of the sheet in the page's head that holds the rules.
    static let sheetID = "bm-si"

    /// The photos of a letter inside `scope`, under the class: `img` and
    /// `video` alone of what the pane's invert names as pictures
    /// (`PanePage.letter`, `ConversationDocument.html`). The round measured
    /// an `img` photo, drawn with one of the page's two inverts under
    /// Smart Invert; the PDF tile's `svg` sheet came out with both, black on
    /// the light tile as Mail's page is the inversion, and would go white
    /// on white with no filter. So `svg`, `picture` and an element with a
    /// `background-image`, the busy ring among them, keep the pane's own
    /// rule, as with the switch off.
    static func pictures(in scope: String) -> String {
        ["img", "video"]
            .map { "html.\(className) \(scope) \($0)" }.joined(separator: ", ")
    }

    /// The rule for a letter the pane inverts inside `scope`, `#bm` on its
    /// page or `.bm-html` in a stack: its photos with no filter. The page
    /// keeps its invert.
    static func inverted(in scope: String) -> String {
        pictures(in: scope) + " { filter: none; }"
    }

    /// The rules for a light letter, `scope` the element that holds its
    /// markup and its white, `#bm` on its page or `.bm-light` in a stack:
    /// inverted plainly, and Mail's line in it (`RemoteContent.line`)
    /// inverted back, so it is the pane's colour as before. Its pictures,
    /// `img` and `video`, inverted once more by the element the pane's
    /// script puts round each while the switch is on (`wrapper(in:)`), so
    /// that with the system's inversion they come out inverted, as Mail's.
    static func light(in scope: String) -> String {
        "html.\(className) \(scope) { filter: invert(1); }\n"
            + "html.\(className) \(scope) .\(RemoteContent.lineClass) { filter: invert(1); }\n"
            + wrapper(in: scope)
    }

    /// The element the pane's script puts round each picture of a light
    /// letter while the switch is on, and takes off as it goes off
    /// (`ConversationDocument.script`'s `bmWrapPictures`).
    ///
    /// **Found on the test iPad, 2026-10-30 (r6-q-copy).** A light
    /// letter's pictures stayed natural under the switch with a filter of
    /// their own, `invert(1)` on `img` and `video`, where Mail's come out
    /// inverted: a picture's own filter does not draw under it, while the
    /// page's filter on a picture's ancestors does. So the invert is on
    /// an element round the picture: inline, or a block round a picture
    /// drawn as a block, as the picture is; every property its parent's
    /// or as from the factory (`all: unset`), so it has no box of its own
    /// to draw and the picture keeps its size, its place and its
    /// baseline; and the script puts a picture back where anything of it
    /// or what holds it moved. A tag no letter uses, so no sender's rule
    /// names it.
    static let wrapperTag = "bm-si-picture"

    /// The rule for the element round a light letter's picture inside
    /// `scope`, under the class: its own properties its parent's, and the
    /// invert. The script puts the element round a picture only where the
    /// page's sheet for the switch has this rule.
    static func wrapper(in scope: String) -> String {
        "html.\(className) \(scope) \(wrapperTag) { all: unset; filter: invert(1); }"
    }

    /// The second class the page's `<html>` has, with `className`, while
    /// a letter it inverts is made dark by WebKit's colour filter
    /// (`ColourFilter`), and the id of the sheet of its rules.
    static let colourFilterClass = "bm-cf"
    static let colourFilterSheetID = "bm-cf"

    /// What the colour filter's rules take off a letter's pictures: every
    /// kind the pane's invert names (`PanePage.letter`,
    /// `ConversationDocument.html`).
    static let allPictures = ["img", "video", "picture", "svg", "[style*=\"background-image\"]"]

    /// The rules for a letter the pane inverts inside `scope`, `#bm` on its
    /// page or `.bm-html` in a stack, made dark by WebKit's colour filter
    /// as Mail's is, under both classes alone (r6-p-copy, 2026-10-29):
    /// - the letter: no filter, no white of its own, so the pane's black
    ///   is behind it, and the colour filter, whose white is rgb(51, 51,
    ///   51), not black;
    /// - its pictures, every kind: no filter, drawn as they are, so the
    ///   system's inversion inverts them, as Mail's;
    /// - Mail's quote bars and the line before a quote: Mail's dark
    ///   colours as they are, out of the colour filter, which cannot reach
    ///   them, as Mail's are in its Dark Mode; and inside them, whatever
    ///   carries a colour of its own, back in the colour filter
    ///   (`quotedOwnColours`);
    /// - Mail's line over held-back pictures: Mail's own colours, out of
    ///   the colour filter;
    /// - his signature's sheet: its white as written, which the colour
    ///   filter makes Mail's grey, rgb(51, 51, 51), by itself.
    /// Links and the sender's own colours are left to the colour filter,
    /// as Mail's are.
    static func colourFilter(in scope: String) -> String {
        let s = "html.\(className).\(colourFilterClass) \(scope)"
        return [
            "\(s) { filter: none; background: transparent; \(ColourFilter.property): \(ColourFilter.value); }",
            allPictures.map { "\(s) \($0)" }.joined(separator: ", ") + " { filter: none; }",
            QuoteBars.css(in: s, palette: QuoteBars.dark),
            QuoteBars.attributionCSS(in: s, palette: QuoteBars.dark),
            "\(s) \(QuoteBars.quote), \(s) .\(QuoteBars.attributionClass), "
                + "\(s) .\(RemoteContent.lineClass) { \(ColourFilter.property): none; }",
            quotedOwnColours(in: s),
            RemoteContent.colourRule(in: s, inverted: false),
            SignatureSheet.css(in: s, colour: SignatureSheet.white),
        ].joined(separator: "\n")
    }

    /// What carries a colour of its own inside a quote or a "wrote:"
    /// line: a style that names a colour, a ground or a border's among
    /// them, a `<font color>`, a `bgcolor`, and a link.
    static let ownColours = ":is([style*=\"color\" i], font[color], [bgcolor], a)"

    /// The colour filter put back, under `s`, on what carries a colour of
    /// its own (`ownColours`) inside a quote or a "wrote:" line, but never
    /// on a quote, such a line or Mail's line itself. WebKit's
    /// `-apple-color-filter` is inherited (its `CSSProperties.json`), so the
    /// quote's `none` reaches everything in it: a sender's own black in a
    /// quote, Apple Mail's forwarded labels or Outlook's `color:black`,
    /// was drawn as written on the pane's black, and so white on white on
    /// screen. With this it is turned as out of a quote, as before at
    /// 7803dbb: light in the render, dark on screen. A quote inside one is
    /// `none` again by its own rule, so its bar and colour stay Mail's.
    static func quotedOwnColours(in s: String) -> String {
        let quoted = ":is(\(QuoteBars.quote), .\(QuoteBars.attributionClass))"
        let notMails = ":not(\(QuoteBars.quote)):not(.\(QuoteBars.attributionClass))"
            + ":not(.\(RemoteContent.lineClass))"
        return "\(s) \(quoted) \(ownColours)\(notMails) "
            + "{ \(ColourFilter.property): \(ColourFilter.value); }"
    }

    /// The colour filter's rules for a letter's own page drawn `scheme`:
    /// a letter inverted alone has them.
    static func colourFilter(for scheme: LetterScheme?) -> String {
        scheme == .inverted ? colourFilter(in: "#bm") : ""
    }

    /// The same for a conversation's stack: its HTML letters inverted.
    static let stackColourFilter = colourFilter(in: ".bm-html")

    /// The rules for a letter's own page drawn `scheme`: "" for a letter in
    /// its own colours and a plain one (`nil`), whose pages are as they
    /// were.
    static func rules(for scheme: LetterScheme?) -> String {
        switch scheme {
        case .inverted?: return inverted(in: "#bm")
        case .light?: return light(in: "#bm")
        case .own?, nil: return ""
        }
    }

    /// The rules for a conversation's stack, for each kind of body in it.
    static let stack = inverted(in: ".bm-html") + "\n" + light(in: ".bm-light")

    /// The page's `<html>` tag: with the class while the switch is on and
    /// the page has rules, as it always was otherwise; and with the colour
    /// filter's class too when it is given the colour filter's rules,
    /// `colourFilter`, which the pane gives only once the page has said it
    /// takes them.
    static func root(on: Bool, rules: String, colourFilter: String = "") -> String {
        guard on && !rules.isEmpty else { return "<html>" }
        return colourFilter.isEmpty
            ? "<html class=\"\(className)\">" : "<html class=\"\(className) \(colourFilterClass)\">"
    }

    /// The sheet of `rules` for the page's head while the switch is on, and
    /// after it the colour filter's, when given; "" otherwise.
    static func sheet(on: Bool, rules: String, colourFilter: String = "") -> String {
        guard on && !rules.isEmpty else { return "" }
        return "<style id=\"\(sheetID)\">\n" + rules + "\n</style>"
            + (colourFilter.isEmpty
                ? "" : "<style id=\"\(colourFilterSheetID)\">\n" + colourFilter + "\n</style>")
    }

    /// The pane's log line for the switch as iOS answered it (B-179's
    /// check): `built`, as a page with rules for it was built; otherwise
    /// when the answer changed. What the check reads to know whether the
    /// switch took under Smart Invert, before it reads the photos.
    static func note(on: Bool, built: Bool) -> String {
        "pane: isInvertColorsEnabled \(on)" + (built ? ", page built" : ", changed")
    }

    /// The start of every page the pane builds, to the end of its `<html>`
    /// tag, with the class; and with the colour filter's too.
    static let onStart = "<!DOCTYPE html><html class=\"\(className)\">"
    static let onStartColourFilter = "<!DOCTYPE html><html class=\"\(className) \(colourFilterClass)\">"

    /// Whether `page` was built with the switch on, with the colour filter
    /// or without.
    static func isOn(inPage page: String) -> Bool {
        page.hasPrefix(onStart) || page.hasPrefix(onStartColourFilter)
    }

    /// Whether `page` was built with the colour filter's class on.
    static func hasColourFilter(inPage page: String) -> Bool { page.hasPrefix(onStartColourFilter) }

    /// `page` with the colour filter's class taken off its root and its
    /// sheet out of its head: for a page built with it that the pane gives
    /// WebKit when the setting no longer reads on, so its letter is never
    /// drawn with its white taken off and no colour filter to make its
    /// words light. The sheet goes too: WebKit, reading it with the setting
    /// off, would keep its `filter: none` and `background: transparent`
    /// and drop every colour filter of it, and the script, finding a sheet
    /// there when the switch came back on, would put the class on over
    /// that, the letter's black words on the pane's black (B-179). The
    /// page is then the page built without the filter, byte for byte.
    static func withoutColourFilter(_ page: String) -> String {
        guard hasColourFilter(inPage: page) else { return page }
        let rest = page.dropFirst(onStartColourFilter.count)
        let start = rest.prefix(65_536)
        let head = start.range(of: "</head>").map { start[..<$0.lowerBound] } ?? start
        guard let open = head.range(of: "<style id=\"\(colourFilterSheetID)\">"),
              let close = head.range(of: "</style>", range: open.upperBound..<head.endIndex)
        else { return onStart + rest }
        return onStart + rest[..<open.lowerBound] + rest[close.upperBound...]
    }

    /// The rules for `page`, a page the pane built, read off its head,
    /// which is the app's alone: a letter's page inverted or light, or a
    /// stack; "" for any other, a plain letter's, one in its own colours,
    /// a notice. For a change of the switch while the page is shown. Read
    /// in its first 64 K characters, which hold the app's head with room
    /// to spare, so a letter of a megabyte is not searched through on the
    /// main thread.
    static func rules(ofPage page: String) -> String {
        let start = page.prefix(65_536)
        let head = start.range(of: "</head>").map { start[..<$0.lowerBound] } ?? start
        if head.contains(PanePage.invertedRule) { return rules(for: .inverted) }
        if head.contains(PanePage.lightRule) { return rules(for: .light) }
        if head.contains(ConversationDocument.invertedRule) { return stack }
        return ""
    }

    /// The colour filter's rules for `page`, read off its head as `rules`
    /// are: a letter's page inverted, a stack; "" for any other.
    static func colourFilter(ofPage page: String) -> String {
        let start = page.prefix(65_536)
        let head = start.range(of: "</head>").map { start[..<$0.lowerBound] } ?? start
        if head.contains(PanePage.invertedRule) { return colourFilter(for: .inverted) }
        if head.contains(ConversationDocument.invertedRule) { return stackColourFilter }
        return ""
    }

    /// What the pane tells the page's script when the switch changes, or
    /// when a page built before the change has loaded: the class on or
    /// off, and the page's rules, put in its head if it has no sheet of
    /// them. Run by `callAsyncJavaScript` in the app's content world, where
    /// `ConversationDocument.script` defined `bmSmartInvert`; the page's
    /// `<html>` is the same element in every world.
    ///
    /// `colourFilter` is the page's colour filter rules, given only while
    /// the switch is on and the page has said it takes the filter, ""
    /// otherwise: the script asks the page again
    /// (`ColourFilter.test`), puts them in a sheet of their own, in place
    /// of any the head has, so WebKit reads them with the setting as it is
    /// now, and puts the colour filter's class on only if it answers yes;
    /// it takes the class off with the switch, or when not given them.
    ///
    /// With the class it puts the element round a light letter's pictures
    /// (`wrapperTag`), and takes it off; and going off, it has WebKit draw
    /// anew each picture left with a filter of its own (r6-q-copy).
    struct Toggle: Equatable {
        let on: Bool
        let rules: String
        var colourFilter: String = ""

        static let script = "bmSmartInvert(on, rules, colourFilter)"

        var arguments: [String: Any] { ["on": on, "rules": rules, "colourFilter": colourFilter] }
    }
}
