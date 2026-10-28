import Foundation

/// The pane's invert, and a signature's white sheet in the reading pane,
/// which is dark (D-010): Mail's grey sheet under his signature (B-173).
///
/// Every HTML letter this app sends with a signature carries it in
/// `AppleMailHTML.signatureOpen`, a `<div class="bm-signature">` declaring
/// a white sheet with black words, his signature naming no colours of its
/// own. The pane draws a letter's HTML on white and then inverts it with its
/// hue turned back, so from B-146 until B-173 that sheet was black and its
/// words white, like the rest of the letter, and the logo, dark ink on
/// transparency, drawn as it is, dark on the black, hard to see.
///
/// That was B-146's reading of Mail, which drew no sheet. Its style sheet,
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
/// letters, so his signature is as below. A letter of his with a picture
/// from the web in it, one he forwards or quotes, is drawn light, on its
/// own white, as Mail draws it, and the sheet in it as written, white with
/// black words, as on paper.
///
/// Mail was seen at last on the test iPad (iPadOS 16.5.1, 2026-10-27), and
/// it keeps the sheet (B-173): his signature in Dark Mode is on a grey
/// sheet, rgb(51, 51, 51), as wide as the letter's column, on Mail's dark
/// card, its words light, its links blue, and the black logo shows on the
/// grey. So the sheet, and the tables in it this app gives the same white
/// (`AppleMailHTML.signatureTableStyle`), have a grey under the invert,
/// `underInvert`, which the invert turns to Mail's: on a letter the pane
/// inverts, alone and in a conversation's stack (`css(in:)`). The logo,
/// a picture, is inverted back as every picture is, so it is drawn as it
/// is, dark on the grey. A letter drawn light or in its own colours has
/// its sheet as written, and the printed page has no rule for it.
/// Nothing moves: a colour under what was there.
///
/// His signature's cells have borders, declared white too
/// (`border: 0.99609pt solid rgb(255, 255, 255)`), which Mail turns to
/// the same grey as the sheet: its shots show one plain grey sheet, no
/// lines in it. The invert alone would make them black lines on the
/// grey, a grid Mail does not draw (until B-173 black on black, and
/// before B-146 white on white: never seen). So a border declared white
/// in the sheet has the same grey under the invert (`borderWhite`): its
/// colour only, its width as it was.
///
/// Each rule is keyed on the white it stands for, as Mail turns only a
/// colour that is declared: the sheet where it declares its white
/// (`sheetWhites`, as this app writes it, or as WebKit writes a white
/// over again), a table whose style begins with the white this app gives
/// it, a border written white. A sheet that has lost its style has no
/// grey, as Mail draws none; a table in it with no white of this app's
/// keeps its own colours, inverted with the rest.
enum SignatureSheet {

    /// The pane's invert: the one string both pages invert a letter's HTML
    /// and its pictures by (`PanePage.letter`, `ConversationDocument.html`),
    /// so the two can never differ. Only a letter Mail would turn to the
    /// dark (`LetterScheme.inverted`, B-169).
    static let invert = "invert(1) hue-rotate(180deg)"

    /// The class of his signature's sheet (`AppleMailHTML.signatureOpen`).
    static let className = "bm-signature"

    /// The sheet's colour under the invert: the invert turns a grey of 204
    /// to Mail's rgb(51, 51, 51), and hue-rotate leaves a grey alone.
    static let underInvert = "rgb(204, 204, 204)"

    /// The white the sheet declares: as this app writes it
    /// (`AppleMailHTML.signatureOpen`), and as WebKit writes a white when
    /// it writes a style over again, as it writes his tables' and cells'.
    static let sheetWhites = ["background-color: #ffffff", "background-color: rgb(255, 255, 255)"]

    /// A border declared white, as his signature's cells write theirs:
    /// `border: 0.99609pt solid rgb(255, 255, 255)`.
    static let borderWhite = "solid rgb(255, 255, 255)"

    /// The rule for the sheet in a letter the pane inverts inside `scope`,
    /// the page's `#bm` or the stack's `.bm-html`: the sheet, where it
    /// declares its white, and its tables, where they begin with the white
    /// this app gives them (`AppleMailHTML.signatureTableStyle`), grey
    /// under the invert, over the white written on them; and the borders
    /// written white in it the same grey, so they are lost in the sheet as
    /// Mail's are (B-173).
    static func css(in scope: String) -> String {
        sheetWhites.map { "\(scope) .\(className)[style*=\"\($0)\"], " }.joined()
            + "\(scope) .\(className) table[style^=\"\(AppleMailHTML.signatureTableStyle)\"] "
            + "{ background-color: \(underInvert) !important; } "
            + "\(scope) .\(className) [style*=\"\(borderWhite)\"] { border-color: \(underInvert) !important; }"
    }
}
