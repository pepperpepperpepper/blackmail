import Foundation

/// A HEIC picture among a letter's words, on an iPad whose WebKit cannot
/// draw one (B-171).
///
/// WebKit draws HEIC from iPadOS 17; on 16, which the app supports and the
/// test iPad runs, an `<img>` of one is a small box with WebKit's broken
/// picture in it: so it was on the test iPad (2026-10-27), for a photo an
/// iPhone put among a letter's words by `cid:`, its part `image/heic`. A
/// HEIC the letter does not show among its words, attached, was a tile
/// (`BodyFiles`, B-170), and is drawn as a photo since B-176, as Mail
/// draws it on 16.5.1, by the same loader. Below iPadOS 17 the loader
/// (`InlineImageLoader`) serves such a part as a JPEG made of it, drawn at
/// most `maxPixels` on its longer side by ImageIO's thumbnail, one at a
/// time (`turns`), and none for a request WebKit has stopped; from 17 as it
/// came. The hold's menu, Quick Look and Markup and Reply use the part as
/// it came, which Quick Look draws.
///
/// Pure, so the suite can run it; the making of the JPEG is ImageIO
/// (`jpeg`), handed in.
enum HEICPicture {

    /// The kinds served as a JPEG where WebKit draws no HEIC.
    static let kinds: Set<String> = ["image/heic", "image/heif", "image/heic-sequence", "image/heif-sequence"]

    /// The longer side of the JPEG, in pixels: as wide as a letter's
    /// column needs at twice the iPad's points, and then some.
    static let maxPixels = 2048

    /// Whether `mimeType`, as a part names its kind, any case, a parameter
    /// or none after it, is one of `kinds`.
    static func isHEIC(_ mimeType: String) -> Bool {
        let kind = mimeType.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        return kinds.contains(kind)
    }

    /// How many JPEGs are made at once: one, so a letter of many iPhone
    /// photos has them made one after another, each decoding alone, and
    /// not all together on the threads Swift's tasks share. How much of a
    /// 12-megapixel photo ImageIO holds while it makes one was not
    /// measured.
    static let atOnce = 1

    /// The loader's turns at making a JPEG, `atOnce` at a time.
    static let turns = Turns(limit: atOnce)

    /// Turns at something, at most `limit` taken at once: `take` waits for
    /// one, those waiting served in the order they came, and `give` hands
    /// it to the next waiting, or back. A turn taken is given back once,
    /// whatever came of it.
    actor Turns {
        nonisolated let limit: Int
        private var taken = 0
        private var waiting: [CheckedContinuation<Void, Never>] = []

        init(limit: Int) {
            self.limit = max(1, limit)
        }

        func take() async {
            guard taken >= limit else {
                taken += 1
                return
            }
            await withCheckedContinuation { waiting.append($0) }
        }

        func give() {
            if waiting.isEmpty {
                taken = max(0, taken - 1)
            } else {
                waiting.removeFirst().resume()
            }
        }
    }

    /// What the loader serves for a part of `data` and `mimeType`: on a
    /// system whose WebKit `drawsHEIC`, or for a part of any other kind,
    /// the part as it came; for a HEIC on one that draws none, the JPEG
    /// `jpeg` makes of it, as `image/jpeg`, or the part as it came where
    /// none can be made.
    static func served(_ data: Data, as mimeType: String, drawsHEIC: Bool,
                       jpeg: (Data) -> Data?) -> (data: Data, mimeType: String) {
        guard !drawsHEIC, isHEIC(mimeType), let made = jpeg(data), !made.isEmpty else { return (data, mimeType) }
        return (made, "image/jpeg")
    }
}
