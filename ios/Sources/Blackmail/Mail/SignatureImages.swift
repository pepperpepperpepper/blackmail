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
        parts(of: load(defaults: defaults))
    }

    static func parts(of images: [InlineImage])
        -> [(contentID: String, filename: String, mimeType: String, data: Data)] {
        images.compactMap { img in
            guard let data = Data(base64Encoded: img.dataBase64), !data.isEmpty else {
                return nil
            }
            return (img.contentID, img.filename, img.mimeType, data)
        }
    }

    /// Their Content-IDs as a letter's markup writes them, so nothing else
    /// in the letter is given one of them (`AppleMailHTML.letter`).
    static func contentIDs(of images: [InlineImage]) -> Set<String> {
        Set(images.map { MIMEDecoder.strippedContentID($0.contentID) ?? $0.contentID })
    }

    /// Whether a part read back out of a letter is one of these pictures.
    ///
    /// By `Content-ID`, which is the identity the builder writes them under
    /// and the one thing a part keeps whatever it is called: the file name
    /// is shared with any photo called "logo.png", and the bytes are not
    /// to hand until the part is fetched. Compared as the reading side
    /// spells it, brackets and a `cid:` prefix stripped.
    static func contains(_ attachment: Attachment, in images: [InlineImage]) -> Bool {
        guard let id = attachment.contentID else { return false }
        return images.contains { MIMEDecoder.strippedContentID($0.contentID) == id }
    }
}
