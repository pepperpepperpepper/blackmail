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
/// A tapped link (`follow`) is cancelled in the pane, and then a `mailto:`
/// opens this app's composer and anything else opens at once, in Safari or
/// the app that claims it, as Mail opens it (B-145): it used to ask "Open
/// this link?" first. That includes a link whose target is a new window or
/// a frame: none opens here.
///
/// A file's tile in a letter's body (`BodyFiles`, B-113, B-170) is a link of
/// the pane's own, `bmfile:`, and a tap on it opens the file in Quick Look:
/// nothing in Safari.
///
/// "Load All Images" on the line over a letter whose pictures from the web
/// are held back (B-168) is a link of the pane's own too, `bmimages:`, and a
/// tap on it loads that letter's pictures (`RemoteContent.letter(of:)`).
///
/// Pictures are not navigations, and this does not touch them: a letter's
/// pictures from the web load as they always have, unless Block All Remote
/// Content holds them back (`RemoteContent`, B-168). Nor is a tap on a
/// picture of the letter's own, which opens it as a file's tile does: the
/// pane's script, in the app's
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
        /// `letter` opened, as a tap on its tile in the body opens it.
        case openFile(letter: String, section: String)
        /// Cancelled in the pane, and the pictures from the web of the
        /// letter `letter` loaded, by its id on a page of its own and its
        /// entry's in a stack (B-168).
        case loadImages(letter: String)
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
            if url.scheme?.lowercased() == RemoteContent.scheme {
                return RemoteContent.letter(of: url).map { .loadImages(letter: $0) } ?? .cancel
            }
            return .follow(url)
        }
        if kind == .other, mainFrame == true, url?.absoluteString == ownDocument { return .allow }
        return .cancel
    }
}
