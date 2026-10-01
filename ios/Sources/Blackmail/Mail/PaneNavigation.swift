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
/// Pictures are not navigations, and this does not touch them: a letter's
/// remote pictures still load, as they always have. Whether they should is
/// the owner's to decide.
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
    }

    /// The URL `loadHTMLString` with no base URL loads under.
    static let ownDocument = "about:blank"

    /// The decision for a navigation of `kind` to `url`. `mainFrame` is its
    /// target frame's: true for the pane's own frame, false for a frame
    /// inside the letter, and nil for a new window.
    static func decide(_ kind: Kind, mainFrame: Bool?, url: URL?) -> Decision {
        if kind == .linkActivated { return url.map(Decision.follow) ?? .cancel }
        if kind == .other, mainFrame == true, url?.absoluteString == ownDocument { return .allow }
        return .cancel
    }
}
