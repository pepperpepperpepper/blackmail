import Foundation

/// What the reading pane lets a page do: the answer to WebKit's
/// `decidePolicyFor` for every navigation in its web view, out of
/// `MessageDetailViewController` so the suite can test it, as `PaneDocument`
/// is.
///
/// The pane shows a stranger's HTML, on a WebKit that may never be updated
/// again, so it goes nowhere on its own. The only document it loads is the
/// one the pane hands it, with `loadHTMLString` and no base URL, which WebKit
/// loads as `about:blank` in the main frame, as a navigation of type
/// "other". Everything else is cancelled: another page in the main frame,
/// whether a `<meta http-equiv="refresh">` asked for it or anything else
/// did; every frame inside the letter, `<iframe>` or `<object>`; every form
/// sent, or sent again; back, forward and reload. The pane used to allow all
/// of it but a tapped link, so a letter could turn the pane into a web page
/// of its own choosing, with no address bar, such as a false Google sign-in,
/// or send a form he had filled in.
///
/// A tapped link does what it always did (`follow`): cancelled in the pane,
/// and then a `mailto:` opens this app's composer and anything else asks
/// "Open this link?" before Safari. That includes a link whose target is a
/// new window or a frame: none opens here.
///
/// A file's row among a letter's words (`BodyFiles`, B-113) is a link of the
/// pane's own, `bmfile:`, and a tap on it opens the file, as a tap on its row
/// in the header does: no "Open this link?", nothing in Safari.
///
/// Pictures are not navigations, and this does not touch them: a letter's
/// remote pictures still load, as they always have. Whether they should is
/// the owner's to decide. Nor is a tap on a picture of the letter's own,
/// which opens it as a file's row does: the pane's script, in the app's
/// content world, tells the pane of it (`PanePictures`, B-122). A picture
/// inside a link is the link's, and comes here as any tapped link does.
enum PaneNavigation {

    /// `WKNavigationType`, with a case for any kind a later WebKit adds.
    enum Kind: Equatable {
        case linkActivated, formSubmitted, backForward, reload, formResubmitted, other
        case unknown
    }

    enum Decision: Equatable {
        case allow
        case cancel
        /// Cancelled in the pane, and taken where a tapped link goes.
        case follow(URL)
        /// Cancelled in the pane, and the file at `section` of the letter
        /// `letter` opened, as its row in the header opens it.
        case openFile(letter: String, section: String)
    }

    /// The URL `loadHTMLString` with no base URL loads under.
    static let ownDocument = "about:blank"

    /// The decision for a navigation of `kind` to `url`. `mainFrame` is its
    /// target frame's: true for the pane's own frame, false for a frame
    /// inside the letter, and nil for a new window.
    static func decide(_ kind: Kind, mainFrame: Bool?, url: URL?) -> Decision {
        if kind == .linkActivated {
            guard let url else { return .cancel }
            if url.scheme?.lowercased() == BodyFiles.scheme {
                return BodyFiles.opening(url).map { .openFile(letter: $0.letter, section: $0.section) }
                    ?? .cancel
            }
            return .follow(url)
        }
        if kind == .other, mainFrame == true, url?.absoluteString == ownDocument { return .allow }
        return .cancel
    }
}
