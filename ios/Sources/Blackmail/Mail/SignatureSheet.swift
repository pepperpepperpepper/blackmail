import Foundation

/// A signature's white sheet in the reading pane, which is dark (D-010).
///
/// Every HTML letter this app sends with a signature carries it in
/// `AppleMailHTML.signatureOpen`, a `<div class="bm-signature">` declaring
/// a white sheet with black words, his signature naming no colours of its
/// own. The pane draws a letter's HTML on white and then inverts it with its
/// hue turned back, which would make that sheet black and its words white,
/// and leave the logo, dark ink on transparency, a dark box hardly to be
/// seen on the black. So the sheet is inverted a second time, which cancels
/// the first, and is drawn as it was written: white, its words black, its
/// logo as on paper. Its pictures are not inverted a third time, or the
/// logo would come out negative: the second rule outranks the pane's rule
/// for pictures by one class.
///
/// The same rules in both of the pane's pages: a conversation's stack
/// (`ConversationDocument`), inside `.bm-html`, and a letter on its own
/// (`PanePage`), inside `#bm`, which until B-130 had none, so the same
/// letter's signature was a white sheet in a stack and white words on the
/// black alone. Rules only: the letter's markup is not touched, and they
/// reach any element of the class, in his letters, in letters quoting them
/// and in anyone else's. Never in the printed page (`PrintPage`), which is
/// not inverted: there the sheet prints as written, black words on the
/// paper's white.
///
/// The sheet's white and black are its own, written in its markup, which
/// outranks a style sheet. The first rule says them again, under that: a
/// sheet whose markup has lost them, from a client that keeps a class and
/// drops a style, would have no background, and its words, inverted
/// twice, would be black on the pane's black. With them it is white with
/// black words.
///
/// As read, not seen, Mail draws no such sheet. Its style sheet, read in
/// MessageUI and MobileMailUI (`-apple-color-filter:
/// apple-invert-lightness()` on `:root.apple-mail-implicit-dark-support`),
/// turns the lightness of every colour in a letter that declares no colour
/// scheme of its own in Dark Mode, the sheet's white and its words' black
/// with the rest, and leaves pictures alone: his signature would be black,
/// its words white, the logo dark on it, as this pane drew it alone
/// (medium: inferred from the rules, not rendered). The sheet is this
/// app's, from its first version, kept so the logo can be seen; whether to
/// keep it is put to the owner (TODO, "Blocked on the owner").
enum SignatureSheet {

    /// The class the sheet carries, in `AppleMailHTML.signatureOpen`.
    static let className = "bm-signature"

    /// The pane's invert, which the sheet's own cancels: the one string
    /// both pages invert a letter's HTML and its pictures by
    /// (`PanePage.letter`, `ConversationDocument.html`), so the sheet's can
    /// never differ from theirs.
    static let invert = "invert(1) hue-rotate(180deg)"

    /// The pictures inside the sheet left as they are drawn.
    static let pictures = ["img", "svg", "picture", "video"]

    /// The sheet's white and its words' black, as its markup declares them
    /// (`AppleMailHTML.signatureOpen`), for a sheet that has lost them; not
    /// important, so the markup's own still win.
    static let colours = "background-color: #fff; color: #000;"

    /// The two rules, a line each, each selector under `scope`, the element
    /// a letter's HTML is drawn in.
    static func css(in scope: String) -> String {
        let sheet = scope + " ." + className
        return sheet + " { filter: \(invert); \(colours) }\n"
            + pictures.map { sheet + " " + $0 }.joined(separator: ", ") + " { filter: none; }"
    }
}
