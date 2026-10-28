import Foundation

/// A link in a letter held (B-176): Mail's "Add to Reading List" second,
/// as Mail's menu has it, for a page Safari's Reading List can keep, and
/// WebKit's own menu, as it was, for everything else held.
///
/// Mail on the test iPad, iPadOS 16.5.1, held on a link in a letter: the
/// card "Tap to show preview", the link's site and its address, beside
/// Open Link, Add to Reading List, Copy Link, Share… (round r6-i-compare,
/// C-11e, 2026-10-27). Blackmail's, WebKit's own with no delegate to ask
/// (B-145): the same card above Open Link, Copy Link, Share…, with no Add
/// to Reading List. The pane is the web view's `WKUIDelegate` now, the
/// first it has. For a link Safari's Reading List says it can keep
/// (`answered`, `SSReadingList.supportsURL`), a page on the web, it
/// answers with a menu of its own: WebKit's suggested items, with the item
/// put in after Open Link where they lack it (`place`). For anything else
/// held, a `mailto:`, `tel:` or `javascript:` link, a picture with no
/// link, it answers nil, as WebKit is answered with no delegate, so WebKit
/// and DataDetectors draw their own menu as they did.
///
/// Not seen on the iPad: whether the card stays above a menu the pane
/// answers with. WebKit's public source says it does not (`WKContentView`'s
/// `continueContextMenuInteraction`): a delegate's configuration is used as
/// it is given, and the card is DataDetectors' preview, asked for only
/// when the delegate answers nil; with no preview of the pane's own,
/// UIKit lifts the link alone. The same source has WebKit's suggested
/// items for such a link already hold Add to Reading List, from
/// `SSReadingList`. The card going would be a change of look, and a
/// menu's look is layout, kept (the comparison plan's Q4): then this is
/// taken out, the pane no delegate again, and the item kept as a
/// difference (TODO, B-176's check, step 4).
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

    /// The link the pane answers WebKit's menu for with its own, `link`
    /// when Safari's Reading List can keep it (`supports`, which is
    /// `SSReadingList.supportsURL` on the iPad); nil for every other
    /// element held, a link it cannot keep or none, for which the pane
    /// answers nil and WebKit's menu is as it was with no delegate.
    static func answered(_ link: URL?, supports: (URL) -> Bool) -> URL? {
        guard let link, supports(link) else { return nil }
        return link
    }

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
