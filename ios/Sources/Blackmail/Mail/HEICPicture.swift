import Foundation

/// A HEIC picture among a letter's words, on an iPad whose WebKit cannot
/// draw one (B-171).
///
/// WebKit draws HEIC from iPadOS 17; on 16, which the app supports and the
/// test iPad runs, an `<img>` of one is a small box with WebKit's broken
/// picture in it: so it was on the test iPad (2026-10-27), for a photo an
/// iPhone put among a letter's words by `cid:`, its part `image/heic`. A
/// HEIC the letter does not show among its words is a tile (`BodyFiles`,
/// B-170), so this is only for one it shows. Below iPadOS 17 the loader
/// (`InlineImageLoader`) serves such a part as a JPEG made of it, at most
/// `maxPixels` on its longer side, so a 12-megapixel photo is never
/// decoded whole; from 17 as it came. The hold's menu, Quick Look and
/// Markup and Reply use the part as it came, which Quick Look draws.
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
