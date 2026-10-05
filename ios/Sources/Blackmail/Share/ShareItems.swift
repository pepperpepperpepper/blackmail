import Foundation

/// What a share hands over, taken in: the deciding part, here where the
/// suite runs it. Reading the extension's item providers is
/// `ShareItems.load`, beside the sheet.
///
/// One thing at a time, and each file onto the disk as it arrives. A share
/// extension runs under a far smaller memory ceiling than the app, about
/// 120 MB. A photograph mostly goes as its own bytes, copied from file to
/// file and never decoded (`SharedPhoto.way`); one that is made a JPEG is
/// decoded at a half, a quarter or an eighth where it is larger
/// (`SharedPhoto.size`), or where the memory left asks it. That is still
/// 49 MB while it is made, for a photo from his iPad's camera decoded whole
/// and for a 48-megapixel one decoded at a half. Every photo at once, and
/// every JPEG kept until the last had landed, is how the extension is
/// killed before its sheet appears, with nothing said.
///
/// And at Send the whole letter is built in memory, about five times its
/// files, so a picture goes as itself only while the letter it makes fits
/// the memory left as well as the 25 MB (`SharedPhoto.sendRoom`). A file
/// that is not a picture is weighed against the 25 MB alone.
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

        /// The pictures staged with no name of their own, which numbers the
        /// next: "image0.jpeg", "image1.png" (`SharedPhoto.name`). One count
        /// for the share, as Mail counts in a letter, and only of those
        /// staged, so the names in the letter run on without a gap.
        private(set) var unnamed = 0

        /// What is left of `budget`.
        var room: Int64 { Self.budget - staged }
        private let write: (Data, String) throws -> URL
        private let copy: (URL, String) throws -> URL
        private let place: (String) throws -> URL
        private let discard: (URL) -> Void

        /// `write` puts bytes on the disk and `copy` a file the sharing app
        /// handed over, each under the name given, and says where. `place`
        /// says where a file of that name is to be written, for `written`,
        /// and `discard` takes one away again.
        init(write: @escaping (Data, String) throws -> URL = AttachmentStore.write,
             copy: @escaping (URL, String) throws -> URL = AttachmentStore.copy,
             place: @escaping (String) throws -> URL = AttachmentStore.place,
             discard: @escaping (URL) -> Void = { AttachmentStore.removeStaged($0) }) {
            self.write = write
            self.copy = copy
            self.place = place
            self.discard = discard
        }

        /// A photograph made a JPEG here, or a picture's bytes as they came
        /// (`SharedPhoto.way`). `unnamed` when its name is a number
        /// (`unnamed`).
        func photo(_ bytes: Data, named filename: String,
                   mimeType: String = "image/jpeg", unnamed: Bool = false) -> SharedItem? {
            stage(size: Int64(bytes.count), filename: filename, mimeType: mimeType,
                  unnamed: unnamed) {
                try write(bytes, filename)
            }
        }

        /// A file the sharing app handed over at `url`, `size` bytes by its
        /// own account: copied, never read, and not even copied when there
        /// is no room for it.
        func file(at url: URL, size: Int64, named filename: String,
                  mimeType: String, unnamed: Bool = false) -> SharedItem? {
            stage(size: size, filename: filename, mimeType: mimeType, unnamed: unnamed) {
                try copy(url, filename)
            }
        }

        /// A file `write` writes straight onto the disk, at the place it is
        /// handed, and nowhere in memory: a photo as its own bytes
        /// (`SharedPhoto.Way.own`). Room for `expected` bytes, the size of
        /// the file it is written from, is looked for before anything is
        /// written; the file as written is measured after, and is what the
        /// letter counts. Nil, with nothing left on the disk, when there is
        /// no room either time, `write` fails, or the file cannot be
        /// measured.
        func written(named filename: String, mimeType: String, expected: Int64,
                     unnamed: Bool = false, _ write: (URL) -> Bool) -> SharedItem? {
            guard staged + expected <= Self.budget, let url = try? place(filename) else { return nil }
            guard write(url), let size = Self.measured(url), size > 0,
                  staged + size <= Self.budget else {
                discard(url)
                return nil
            }
            return stage(size: size, filename: filename, mimeType: mimeType, unnamed: unnamed) {
                url
            }
        }

        /// The size of the file at `url`, as the disk has it.
        private static func measured(_ url: URL) -> Int64? {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes?[.size] as? NSNumber)?.int64Value
        }

        private func stage(size: Int64, filename: String, mimeType: String, unnamed: Bool,
                           _ put: () throws -> URL) -> SharedItem? {
            guard staged + size <= Self.budget, let url = try? put() else { return nil }
            staged += size
            if unnamed { self.unnamed += 1 }
            return .file(url, filename: filename, mimeType: mimeType, size: size)
        }
    }

    // MARK: - A picture left out

    /// What the sheet says when a picture he chose could not be attached.
    enum LeftOut: Equatable {
        /// A line over the letter, which has the rest of what he shared.
        case line(String)
        /// The words in place of the letter, and Cancel: a share of
        /// pictures alone of which none came. A letter without the photo he
        /// chose is not what he meant to send.
        case instead(String)
    }

    /// The rule: nil when every picture offered was attached. When none
    /// was, and nothing but pictures was offered, the words in place of the
    /// letter. Otherwise a line saying how many were left out. Never a
    /// letter that goes without the photo he chose, unsaid.
    static func leftOut(pictures: Int, attached: Int, others: Int) -> LeftOut? {
        let missing = pictures - attached
        guard missing > 0 else { return nil }
        if attached == 0, others == 0 {
            return .instead(pictures == 1 ? "The photo could not be attached."
                                          : "The photos could not be attached.")
        }
        return .line(missing == 1 ? "1 photo could not be attached."
                                  : "\(missing) photos could not be attached.")
    }

    /// What a share offered and what came of its pictures, counted as they
    /// are read, one at a time (`oneAtATime`).
    final class Tally {
        /// Everything offered, a picture or anything else.
        var offered = 0
        /// The pictures among them.
        var pictures = 0
        /// The pictures attached.
        var attached = 0

        init() {}

        var leftOut: LeftOut? {
            ShareItems.leftOut(pictures: pictures, attached: attached, others: offered - pictures)
        }
    }
}
