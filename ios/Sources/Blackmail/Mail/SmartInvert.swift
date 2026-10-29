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
/// Off, every page is byte for byte as it was. On, a page is built with
/// the class on its `<html>` and its rules in a sheet of their own in its
/// head (`root`, `sheet`); a change of the switch while a page is shown
/// puts the class on or takes it off by the pane's script, the sheet put
/// in if the page has none (`Toggle`), so nothing is drawn again and
/// nothing scrolls.
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
    /// inverted back, so it is the pane's colour as before.
    static func light(in scope: String) -> String {
        "html.\(className) \(scope) { filter: invert(1); }\n"
            + "html.\(className) \(scope) .\(RemoteContent.lineClass) { filter: invert(1); }"
    }

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
    /// the page has rules, as it always was otherwise.
    static func root(on: Bool, rules: String) -> String {
        on && !rules.isEmpty ? "<html class=\"\(className)\">" : "<html>"
    }

    /// The sheet of `rules` for the page's head while the switch is on; ""
    /// otherwise.
    static func sheet(on: Bool, rules: String) -> String {
        on && !rules.isEmpty ? "<style id=\"\(sheetID)\">\n" + rules + "\n</style>" : ""
    }

    /// The pane's log line for the switch as iOS answered it (B-179's
    /// check): `built`, as a page with rules for it was built; otherwise
    /// when the answer changed. What the check reads to know whether the
    /// switch took under Smart Invert, before it reads the photos.
    static func note(on: Bool, built: Bool) -> String {
        "pane: isInvertColorsEnabled \(on)" + (built ? ", page built" : ", changed")
    }

    /// The start of every page the pane builds, to the end of its `<html>`
    /// tag, with the class.
    static let onStart = "<!DOCTYPE html><html class=\"\(className)\">"

    /// Whether `page` was built with the switch on.
    static func isOn(inPage page: String) -> Bool { page.hasPrefix(onStart) }

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

    /// What the pane tells the page's script when the switch changes, or
    /// when a page built before the change has loaded: the class on or
    /// off, and the page's rules, put in its head if it has no sheet of
    /// them. Run by `callAsyncJavaScript` in the app's content world, where
    /// `ConversationDocument.script` defined `bmSmartInvert`; the page's
    /// `<html>` is the same element in every world.
    struct Toggle: Equatable {
        let on: Bool
        let rules: String

        static let script = "bmSmartInvert(on, rules)"

        var arguments: [String: Any] { ["on": on, "rules": rules] }
    }
}
