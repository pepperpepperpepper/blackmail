import Foundation

/// What a share hands over, taken in: the deciding part, here where the
/// suite runs it. Reading the extension's item providers is
/// `ShareItems.load`, beside the sheet.
///
/// One thing at a time, and each file onto the disk as it arrives. A share
/// extension runs under a far smaller memory ceiling than the app, and a
/// photograph is decoded to a full bitmap to be re-encoded as JPEG, about
/// 48 MB for a 12-megapixel one. Every photo decoding at once, and every
/// JPEG kept until the last had landed, is how the extension is killed
/// before its sheet appears, with nothing said.
enum ShareItems {

    /// Runs `loads` one after another, each begun only once the one before
    /// it has called back, and hands `done` what they found, in their
    /// order, without the ones that found nothing.
    static func oneAtATime<Item>(_ loads: [(@escaping (Item?) -> Void) -> Void],
                                 done: @escaping ([Item]) -> Void) {
        var found: [Item] = []
        func next(_ index: Int) {
            guard index < loads.count else { return done(found) }
            let load = loads[index]
            load { item in
                if let item { found.append(item) }
                next(index + 1)
            }
        }
        next(0)
    }

    /// Words shared as words, unless they are only a web address: some
    /// apps share a link that way, and it is still a link, with the title
    /// offered as its subject.
    static func item(fromText text: String, title: String?) -> SharedItem {
        let bare = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bare.contains(where: \.isWhitespace), let url = URL(string: bare),
           ["http", "https"].contains(url.scheme?.lowercased()) {
            return .link(url, title: title)
        }
        return .text(text)
    }

    /// The name a shared file goes by: the sharing app's suggestion, with
    /// the file's own extension put back when the suggestion lacks it,
    /// since that is what tells a reader's client how to open it; failing
    /// a suggestion, the file's own name.
    static func filename(suggested: String?, for file: URL) -> String {
        guard let suggested, !suggested.isEmpty else { return file.lastPathComponent }
        let ext = file.pathExtension
        guard !ext.isEmpty, !suggested.lowercased().hasSuffix("." + ext.lowercased()) else {
            return suggested
        }
        return suggested + "." + ext
    }

    /// Puts each shared file on the disk as it arrives, while the share's
    /// files still fit in a letter that could go. A file that does not fit,
    /// or cannot be written, is left out and the rest go: the sheet lists
    /// what is attached, so nothing is missing unseen.
    ///
    /// Used by one load at a time (`oneAtATime`), never two at once.
    final class Staging {

        /// What a share's files may weigh together: the 25 MB Gmail takes,
        /// which is the SIZE it advertises (`SMTPClient`) less what base64
        /// adds. Past it the letter could not go whatever else happened, and
        /// a file that size read into the extension, or built into a letter
        /// there, is the extension killed.
        static let budget: Int64 = 25_000_000

        private(set) var staged: Int64 = 0
        private let write: (Data, String) throws -> URL
        private let copy: (URL, String) throws -> URL

        /// `write` puts bytes on the disk and `copy` a file the sharing app
        /// handed over, each under the name given, and says where.
        init(write: @escaping (Data, String) throws -> URL = AttachmentStore.write,
             copy: @escaping (URL, String) throws -> URL = AttachmentStore.copy) {
            self.write = write
            self.copy = copy
        }

        /// A photograph, already a JPEG.
        func photo(_ jpeg: Data, named filename: String) -> SharedItem? {
            stage(size: Int64(jpeg.count), filename: filename, mimeType: "image/jpeg") {
                try write(jpeg, filename)
            }
        }

        /// A file the sharing app handed over at `url`, `size` bytes by its
        /// own account: copied, never read, and not even copied when there
        /// is no room for it.
        func file(at url: URL, size: Int64, named filename: String,
                  mimeType: String) -> SharedItem? {
            stage(size: size, filename: filename, mimeType: mimeType) { try copy(url, filename) }
        }

        private func stage(size: Int64, filename: String, mimeType: String,
                           _ put: () throws -> URL) -> SharedItem? {
            guard staged + size <= Self.budget, let url = try? put() else { return nil }
            staged += size
            return .file(url, filename: filename, mimeType: mimeType, size: size)
        }
    }
}
