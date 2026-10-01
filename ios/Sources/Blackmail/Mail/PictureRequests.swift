import Foundation

/// The pictures a page in the reading pane has asked `InlineImageLoader`
/// for and not yet been given: which may still be answered, and the fetch
/// under each, called off when WebKit stops asking.
///
/// Out of the loader for the reason `PaneLoads` is out of the controller:
/// the loader is WebKit and does not exist on the machine the suite runs
/// on, so a rule that lived there could be undone with every test green.
///
/// Two rules. A request is answered once, and never after WebKit has
/// stopped it: answering a `WKURLSchemeTask` WebKit has stopped raises an
/// Objective-C exception, which Swift cannot catch, and the app goes. And
/// a request stopped has its fetch called off. WebKit stops every picture
/// still coming when the page goes, as it goes the moment he taps another
/// letter. Each fetch waits its turn on the one connection, and they used
/// to go on waiting, and then go, every one, so the letter he had tapped
/// waited behind the pictures of the one he had left: for a large letter
/// of a few hundred, each a round trip, minutes. A fetch called off before
/// its turn leaves the line with nothing sent (`IMAPClient.beginExchange`);
/// one already on the wire finishes, so the stream stays in step.
///
/// Used on the main thread only, where WebKit calls the loader.
struct PictureRequests<Key: Hashable> {
    /// Every request neither answered nor stopped.
    private var live = Set<Key>()
    /// The fetch answering each of them that has one.
    private var fetches: [Key: Task<Void, Never>] = [:]

    /// How many are still to be answered.
    var count: Int { live.count }

    /// WebKit has asked for `key`.
    mutating func begin(_ key: Key) {
        live.insert(key)
    }

    /// `fetch` is what answers `key`: called off with it if WebKit stops
    /// asking first, and at once if it already has.
    mutating func answering(_ key: Key, with fetch: Task<Void, Never>) {
        guard live.contains(key) else {
            fetch.cancel()
            return
        }
        fetches[key] = fetch
    }

    /// WebKit no longer wants `key`: it is never answered, and its fetch is
    /// called off.
    mutating func stop(_ key: Key) {
        live.remove(key)
        fetches.removeValue(forKey: key)?.cancel()
    }

    /// Whether `key` may be answered now: true once for a request WebKit
    /// has made and not stopped, and false ever after.
    mutating func answer(_ key: Key) -> Bool {
        fetches.removeValue(forKey: key)
        return live.remove(key) != nil
    }
}
