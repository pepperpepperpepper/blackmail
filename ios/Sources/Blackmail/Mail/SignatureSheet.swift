import Foundation

/// The pane's invert, and what is left of a signature's white sheet in the
/// reading pane, which is dark (D-010).
///
/// Every HTML letter this app sends with a signature carries it in
/// `AppleMailHTML.signatureOpen`, a `<div class="bm-signature">` declaring
/// a white sheet with black words, his signature naming no colours of its
/// own. The pane draws a letter's HTML on white and then inverts it with its
/// hue turned back, so that sheet is black and its words white, like the
/// rest of the letter, and the logo, dark ink on transparency, is drawn as
/// it is, dark on the black.
///
/// That is as Mail draws it (B-146). Mail draws no sheet. Its style sheet,
/// read in MessageUI and MobileMailUI (`-apple-color-filter:
/// apple-invert-lightness()` on `:root.apple-mail-implicit-dark-support`),
/// turns the lightness of every colour in a letter that declares no colour
/// scheme of its own in Dark Mode, the sheet's white and its words' black
/// with the rest, and leaves pictures alone: his signature black, its words
/// white, the logo dark on it (medium: inferred from the rules, not
/// rendered). Until B-146 both pages inverted the sheet a second time,
/// which cancelled the first, so it was white with black words and its
/// logo as on paper: in a conversation's stack since the app's first
/// version, and in a letter on its own since B-130. Ruled 2026-10-26: copy
/// Mail. The printed page (`PrintPage`) never had the sheet's rules: it is
/// not inverted, and the sheet prints as written, black words on the
/// paper's white.
///
/// Since B-169 the pane inverts only the letters Mail turns to the dark,
/// those that declare no colour scheme and have no picture from the web
/// and no background picture (`LetterScheme`). His letters are such
/// letters, so his signature is as above. A letter of his with a picture
/// from the web in it, one he forwards or quotes, is drawn light, on its
/// own white, as Mail draws it, and the sheet in it as written, white with
/// black words, as on paper.
enum SignatureSheet {

    /// The pane's invert: the one string both pages invert a letter's HTML
    /// and its pictures by (`PanePage.letter`, `ConversationDocument.html`),
    /// so the two can never differ. Only a letter Mail would turn to the
    /// dark (`LetterScheme.inverted`, B-169).
    static let invert = "invert(1) hue-rotate(180deg)"
}
