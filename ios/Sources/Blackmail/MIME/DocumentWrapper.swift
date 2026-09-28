import Foundation

/// A sender's own `<html>`/`<head>`/`<body>` wrapper, and taking it off.
///
/// Pure and Foundation-only, and separated from the reading pane that uses
/// it so the suite on Linux can test it — the pane is UIKit and WebKit and
/// cannot exist on the test host.
enum DocumentWrapper {

    /// The wrapper, piece by piece, applied in this order.
    ///
    /// The head pattern is the one that has to be careful. Its tag name must
    /// END where HTML ends a tag name, at white space, `/` or `>`. It used to
    /// be a bare `<head`, which also matched HTML5's `<header>`, the element
    /// newsletters put at the top of each article. From every `<header>` the
    /// lazy `[\s\S]*?</head>` then read on looking for a `</head>` that
    /// `</header>` does not supply. Usually it found none and gave up at the
    /// end of the letter, having scanned all of it: measured on a 193 KB body
    /// with thirty `<header>`s, about 100 ms of main-thread work against 7 ms
    /// for the whole strip done right. Where a later `</head>` did exist, as
    /// in a forwarded letter quoting a whole document of its own, the match
    /// succeeded and deleted everything from the first `<header>` to it,
    /// which is most of the letter.
    private static let patterns = [
        "<!DOCTYPE[^>]*>",
        "</?html[^>]*>",
        "<head(?=[\\s/>])[^>]*>[\\s\\S]*?</head>",
        "</?body[^>]*>",
    ]

    /// `html` without its wrapper.
    ///
    /// This is not tidiness, it is the fix for a real and near-universal bug.
    /// WebKit merges an inner `<body>`'s attributes onto the outer one, and an
    /// inline style beats a stylesheet — so a message whose body tag carries
    /// `style="padding: 0"` silently cancelled our padding and the letter
    /// rendered flush against the pane divider while the header above it stayed
    /// inset. Almost every real HTML email ships a styled body tag, so this was
    /// not an edge case. With the wrapper gone a sender cannot set the letter's
    /// margin or type size at all.
    static func stripped(from html: String) -> String {
        var s = html
        for pattern in patterns {
            s = s.replacingOccurrences(of: pattern, with: "",
                                       options: [.regularExpression, .caseInsensitive])
        }
        return s
    }
}
