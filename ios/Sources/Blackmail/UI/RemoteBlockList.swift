// Guarded so this file compiles away on a host without UIKit.
#if canImport(UIKit)

import Foundation
import WebKit

/// WebKit's list that blocks every request to the web (`RemoteContent.ruleList`,
/// B-168), on one web view's content controller or off it.
///
/// Made once by WebKit for the app, the first time one is wanted on, which
/// is never while Block All Remote Content is off, as it comes: nothing of
/// WebKit's changes then. WebKit makes it on its own time, a few
/// milliseconds; until it has, a letter held back is held back by its
/// markup alone (`RemoteContent.blocked`), and the list goes on as soon as
/// it is made. One WebKit could not make is asked for again once at the
/// next thing the pane shows, not before (`took`). A change goes on the
/// controller at once, before whatever the web view is given next: WebKit
/// applies it to the requests made after it, the page on screen's among
/// them.
@MainActor
final class RemoteBlockList {

    /// The list, once WebKit has made it.
    private static var made: WKContentRuleList?
    private static var making = false
    /// The holders waiting for it, weakly.
    private static var waiting: [Waiting] = []

    private struct Waiting {
        weak var list: RemoteBlockList?
    }

    private let controller: WKUserContentController
    private var added = false

    init(on controller: WKUserContentController) {
        self.controller = controller
    }

    /// Whether the list is to be on the controller's web views.
    var on = false {
        didSet { apply() }
    }

    /// The list made, or nil until it is: for a print's web view, built
    /// after the pane's has made it.
    static var list: WKContentRuleList? { made }

    private func apply() {
        guard let list = Self.made else {
            if on { Self.make(for: self) }
            return
        }
        if on, !added {
            controller.add(list)
            added = true
        } else if !on, added {
            controller.remove(list)
            added = false
        }
    }

    private static func make(for holder: RemoteBlockList) {
        waiting.append(Waiting(list: holder))
        guard !making, let store = WKContentRuleListStore.default() else { return }
        making = true
        store.compileContentRuleList(forIdentifier: RemoteContent.ruleListID,
                                     encodedContentRuleList: RemoteContent.ruleList) { list, error in
            Task { @MainActor in
                RemoteBlockList.took(list, error)
            }
        }
    }

    /// WebKit's answer. The list made, each holder waiting for it puts it
    /// on if it still wants it on. Not made, as when the iPad's storage is
    /// full, the holders are let go untold, their letters held back by
    /// their markup alone, and it is asked for again only when the pane
    /// next shows something (`holdBackTheWeb`): told, a holder still on
    /// would ask for it again at once, and again, for as long as WebKit
    /// could not make it, each time in the log.
    private static func took(_ list: WKContentRuleList?, _ error: Error?) {
        making = false
        let holders = waiting
        waiting = []
        guard let list else {
            Diagnostics.log(.note, "remote: list not made \((error as NSError?)?.code ?? 0)")
            return
        }
        made = list
        for holder in holders { holder.list?.apply() }
    }
}

#endif
