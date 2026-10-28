import Foundation

/// A link in a letter held (B-176): WebKit's menu for it, with "Add to
/// Reading List" second, as Mail's has it.
///
/// Mail on the test iPad, iPadOS 16.5.1, held on a link in a letter: the
/// card "Tap to show preview", the link's site and its address, beside
/// Open Link, Add to Reading List, Copy Link, Share… (round r6-i-compare,
/// C-11e, 2026-10-27). Blackmail's, WebKit's own with no delegate to ask
/// (B-145): the same card above Open Link, Copy Link, Share…, with no Add
/// to Reading List. The pane is the web view's `WKUIDelegate` now, the
/// first it has, and gives WebKit's menu back as WebKit makes it
/// (`suggestedActions`), with the item put in after Open Link. Safari's
/// Reading List takes it (`SSReadingList`), for an address it says it
/// can keep, a page on the web; any other link, a `mailto:` say, has
/// WebKit's menu as it was. A menu that has the item already, as WebKit's
/// may on a later iPadOS, is left as it is.
///
/// Pure, so the suite can run it; the menu and the list are UIKit's and
/// SafariServices', in `MessageDetailViewController`.
enum LinkMenu {

    /// Mail's words for the item, as its menu showed them; WebKit's
    /// (`_WKElementActionTypeAddToReadingList`).
    static let addToReadingList = "Add to Reading List"

    /// The symbol on its right, the one on Mail's: a pair of glasses.
    static let symbol = "eyeglasses"

    /// The item WebKit puts first, after which it goes.
    static let openLink = "Open Link"

    /// Where the item goes among `titles`, WebKit's menu's items' titles in
    /// order, for `link`: after Open Link, or second where there is none,
    /// first in a menu of none; nil for no item, a menu that has it
    /// already or a link the Reading List cannot keep (`supports`, which
    /// is `SSReadingList.supportsURL` on the iPad), and for no link.
    static func place(among titles: [String], for link: URL?, supports: (URL) -> Bool) -> Int? {
        guard let link, supports(link), !titles.contains(addToReadingList) else { return nil }
        if let open = titles.firstIndex(of: openLink) { return open + 1 }
        return min(1, titles.count)
    }
}
