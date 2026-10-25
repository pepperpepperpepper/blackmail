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
/// Mail draws no such sheet. In Dark Mode its pane turns the lightness of
/// every colour in a letter that declares no colour scheme of its own, the
/// sheet's white and its words' black with the rest, and leaves pictures
/// alone (`-apple-color-filter: apple-invert-lightness()` on
/// `:root.apple-mail-implicit-dark-support`, iOS 18.6's MessageUI and
/// MobileMailUI): his signature black, its words white, the logo dark on
/// it, as this pane drew it alone. The sheet is this app's, from its first
/// version, kept so the logo can be seen.
enum SignatureSheet {

    /// The class the sheet carries, in `AppleMailHTML.signatureOpen`.
    static let className = "bm-signature"

    /// The pane's invert, which the sheet's own cancels.
    static let invert = "invert(1) hue-rotate(180deg)"

    /// The pictures inside the sheet left as they are drawn.
    static let pictures = ["img", "svg", "picture", "video"]

    /// The two rules, a line each, each selector under `scope`, the element
    /// a letter's HTML is drawn in.
    static func css(in scope: String) -> String {
        let sheet = scope + " ." + className
        return sheet + " { filter: \(invert); }\n"
            + pictures.map { sheet + " " + $0 }.joined(separator: ", ") + " { filter: none; }"
    }
}
