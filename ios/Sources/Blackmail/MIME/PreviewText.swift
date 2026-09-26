import Foundation

/// The two grey lines under the subject in a list row.
///
/// A preview is built from the *first few kilobytes* of a body rather than
/// from the whole thing, so everything here has to survive a fragment that
/// stops mid-character, mid-tag or mid-stylesheet. Nothing may throw and
/// nothing may hang: a preview is decoration, and the cost of failing to
/// build one must never be more than a blank line where it would have gone.
///
/// The HTML walk itself lives in `HTMLText`, which reply and forward also
/// use to quote a body. The only difference here is the finish: a row has two
/// lines and no use for the sender's paragraphs, so the text is flattened.
enum PreviewText {

    /// Enough for two lines at every type size the app offers, plus slack for
    /// the truncation the label does itself. Keeping more would mean holding
    /// a page of body text alive per visible row for nothing.
    static let maximumCharacters = 240

    // MARK: - Partial fetches

    /// Drops the incomplete character a byte-counted fetch leaves at the end.
    ///
    /// `BODY[1]<0.2048>` cuts at a byte, not at a character, so a body ending
    /// in an accent or an emoji arrives with two of its three bytes. That one
    /// broken sequence makes `String(data:encoding:.utf8)` return nil for the
    /// *whole* buffer, and the Latin-1 fallback then renders every accented
    /// character in the preview as mojibake — so a single split character at
    /// the end corrupts everything before it.
    ///
    /// The guard is deliberately narrow: bytes are only dropped when the
    /// whole buffer fails as UTF-8 *and* dropping a byte or three fixes it.
    /// Genuine Latin-1 text has high bytes throughout, so trimming its tail
    /// never makes it decode and it is returned untouched.
    static func trimmingSplitCharacter(_ data: Data) -> Data {
        // A UTF-8 sequence is at most four bytes, so three is the most that
        // can be left dangling.
        guard data.count > 4, String(data: data, encoding: .utf8) == nil else { return data }
        for drop in 1...3 {
            let shortened = data.prefix(data.count - drop)
            if String(data: shortened, encoding: .utf8) != nil { return Data(shortened) }
        }
        return data
    }

    // MARK: - Building a preview

    /// Line breaks and runs of spaces become single spaces, because the row
    /// has two lines of its own and the body's own wrapping has nothing to do
    /// with them.
    static func fromPlainText(_ text: String) -> String {
        condense(text)
    }

    /// The same, from HTML.
    static func fromHTML(_ html: String) -> String {
        condense(HTMLText.plainText(from: html))
    }

    // MARK: - Whitespace

    /// Every run of white space becomes one space, and the result is cut to
    /// `maximumCharacters`.
    ///
    /// Zero-width characters are deleted rather than treated as space. That
    /// is not a nicety: a marketing template pads its preheader with hundreds
    /// of `&zwnj;&nbsp;` pairs precisely so that the *rest* of the mail does
    /// not show up in a preview, and without this every such message would
    /// preview as an empty row.
    ///
    /// Walks SCALARS, not Characters, and that distinction is load-bearing. A
    /// zero-width joiner is a format character, so Swift folds it into the
    /// grapheme cluster in front of it: iterating Characters yields one
    /// `"y\u{200C}"` that is not zero-width by any test, and the padding
    /// survives into the preview invisibly.
    private static func condense(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        var count = 0

        for scalar in text.unicodeScalars {
            if HTMLText.isZeroWidth(scalar) { continue }
            // Covers NBSP, which is White_Space in Unicode.
            if scalar.properties.isWhitespace {
                pendingSpace = count > 0
                continue
            }
            // Checked BEFORE each append, not after: appending a separator
            // and then the character that needed it can cross the bound twice
            // in one turn of the loop.
            if pendingSpace {
                if count >= maximumCharacters { break }
                out.append(" ")
                count += 1
                pendingSpace = false
            }
            if count >= maximumCharacters { break }
            out.append(scalar)
            count += 1
        }
        return String(out)
    }
}
