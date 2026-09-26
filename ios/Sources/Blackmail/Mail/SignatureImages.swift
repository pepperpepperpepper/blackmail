import Foundation

/// The pictures a signature's markup refers to by `cid:`.
///
/// Both images in Sam's real signature point at Google URLs, and both are
/// dead for recipients today: the portrait 403s, and the logo URL serves a
/// PNG to `curl` but renders as a broken box in actual clients. The cure is
/// to send the bytes WITH the letter, as parts of a `multipart/related` set
/// — which is what Mail does for every image a composer inserts, and what
/// his correspondents' clients already know how to resolve.
///
/// The MARKUP carries the reference (`src="cid:sig-logo"`); this carries
/// the bytes. A `cid:` with no bytes here degrades to the picture simply
/// not appearing, which is no worse than the broken URL it replaces.
///
/// Its OWN defaults key rather than a field on `MailAccount`, deliberately:
/// the account is hand-decoded one field at a time because Swift's
/// synthesized decoder ignores defaults, and a nested array there is a
/// decoding hazard for every account already on disk. A standalone key
/// defaults to empty for free.
enum SignatureImages {

    struct InlineImage: Codable, Equatable {
        let contentID: String
        let filename: String
        let mimeType: String
        let dataBase64: String
    }

    private static let key = "blackmail.signatureInlineImages"

    static func load(defaults: UserDefaults = .standard) -> [InlineImage] {
        guard let data = defaults.data(forKey: key),
              let images = try? JSONDecoder().decode([InlineImage].self, from: data)
        else { return [] }
        return images
    }

    static func save(_ images: [InlineImage], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(images) else { return }
        defaults.set(data, forKey: key)
    }

    static func removeAll(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// As the builder's inline parts, base64 decoded.
    ///
    /// An entry whose bytes will not decode is DROPPED rather than sent:
    /// a part with garbage payload would arrive as a broken image, which
    /// is the thing this exists to replace.
    static func parts(defaults: UserDefaults = .standard)
        -> [(contentID: String, filename: String, mimeType: String, data: Data)] {
        load(defaults: defaults).compactMap { img in
            guard let data = Data(base64Encoded: img.dataBase64), !data.isEmpty else {
                return nil
            }
            return (img.contentID, img.filename, img.mimeType, data)
        }
    }
}
