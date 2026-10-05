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
/// At Send the letter is made from the staged files as it goes, a block at
/// a time, and never held whole (B-070). So a picture goes as itself, and a
/// video or any other file goes, whenever it fits the letter's 25 MB: the
/// memory at Send does not grow with them.
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
        /// adds. Past it the letter could not go whatever else happened. The
        /// one bound on what is staged: Send makes the letter from the files
        /// as it goes, in memory that does not grow with them (B-070).
        static let budget: Int64 = 25_000_000

        private(set) var staged: Int64 = 0

        /// What the last file's copy measured on the disk (`file`), staged
        /// or taken away again for want of room: the size that decided it,
        /// for the log. Nil when the last file was not copied, or its copy
        /// could not be measured.
        private(set) var lastMeasured: Int64?

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
        ///
        /// The copy is measured once it is made, and the letter counts what
        /// the disk has, not what the sharing app said (B-070): it is the
        /// size Send checks the file against before the letter goes
        /// (`LetterFiles`), and any other is a file that changed. A copy
        /// larger than the room, or that cannot be measured, is taken away
        /// again and left out. What the copy measured is `lastMeasured`.
        func file(at url: URL, size: Int64, named filename: String,
                  mimeType: String, unnamed: Bool = false) -> SharedItem? {
            lastMeasured = nil
            guard staged + size <= Self.budget, let copied = try? copy(url, filename) else {
                return nil
            }
            lastMeasured = Self.measured(copied)
            guard let measured = lastMeasured, staged + measured <= Self.budget else {
                discard(copied)
                return nil
            }
            return stage(size: measured, filename: filename, mimeType: mimeType,
                         unnamed: unnamed) {
                copied
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
            // Readable while the iPad is locked, as a letter that takes
            // minutes to go must be (`AttachmentStore.readableWhileLocked`):
            // a picture written straight onto the disk by ImageIO too.
            AttachmentStore.readableWhileLocked(url)
            staged += size
            if unnamed { self.unnamed += 1 }
            return .file(url, filename: filename, mimeType: mimeType, size: size)
        }
    }

    // MARK: - A video

    /// A video's types, the one taken first where several are offered:
    /// QuickTime, which is how Photos keeps a video, so the original
    /// ".MOV" goes; then MPEG-4; then Apple's M4V.
    static let movieTypes = ["com.apple.quicktime-movie", "public.mpeg-4", "com.apple.m4v-video"]

    /// The type a video is read as, from what the provider `offered`: the
    /// first of `movieTypes` it offers, whatever its order, then the first
    /// it offers that `isMovie` says is a video. Nil for what is not a
    /// video.
    static func movieType(offered: [String], isMovie: (String) -> Bool) -> String? {
        movieTypes.first(where: offered.contains) ?? offered.first(where: isMovie)
    }

    /// What became of a file that is not a picture, for the log.
    enum FileWent: Equatable {
        case staged
        /// Larger than what was left of the letter's 25 MB, `left` bytes.
        case noRoom(left: Int64)
        /// Not copied onto the disk, or the copy not measured.
        case notCopied
        /// The sharing app handed over no file.
        case notGiven
    }

    /// What became of a file of `size` bytes, `item` what staging made of
    /// it with `room` left before it. `size` is what its copy measured
    /// (`Staging.lastMeasured`) where it was copied, so a copy larger than
    /// the room is said to be; the sharing app's account of it where it
    /// was not.
    static func fileWent(_ item: SharedItem?, size: Int64, room: Int64) -> FileWent {
        if item != nil { return .staged }
        return size > room ? .noRoom(left: room) : .notCopied
    }

    /// The line the log gets for each file shared that is not a picture
    /// (B-070), a video most of all: the type it was read as, where its
    /// name came from and the name as `SharedPhoto.Report.logged` has it,
    /// its MIME type, its bytes and what became of it. Numbers and types:
    /// a name is given only when a device made it.
    static func fileNote(read type: String, suggested: Bool, name: String, mimeType: String,
                         bytes: Int64, went: FileWent) -> String {
        let source = name.isEmpty ? "none" : suggested ? "suggested" : "file"
        let words: String
        switch went {
        case .staged: words = "staged"
        case .noRoom(let left):
            words = "left out, more than the letter's room, \(left / 1_000_000) MB left"
        case .notCopied: words = "left out, not copied"
        case .notGiven: words = "left out, not given"
        }
        return "SHARE-FILE read=\(type) name=\(source) \"\(SharedPhoto.Report.logged(name))\""
            + " mime=\(mimeType) bytes=\(bytes) went=\(words)"
    }

    // MARK: - A picture or a video left out

    /// What the sheet says when a picture or a video he chose could not be
    /// attached.
    enum LeftOut: Equatable {
        /// A line over the letter, which has the rest of what he shared.
        case line(String)
        /// The words in place of the letter, and Cancel: a share of
        /// pictures or videos alone of which none came. A letter without
        /// the photo he chose is not what he meant to send.
        case instead(String)
    }

    /// The rule: nil when every picture and every video offered was
    /// attached. When none was, and nothing but pictures and videos was
    /// offered, the words in place of the letter. Otherwise a line saying
    /// how many were left out. Never a letter that goes without the photo
    /// or the video he chose, unsaid.
    ///
    /// A video's words are a photo's (B-070): "The video could not be
    /// attached.", "1 video could not be attached.". One photo or one
    /// video among them is said as one: "The photo and the video could
    /// not be attached.". The owner approved them, 2026-10-05.
    static func leftOut(pictures: Int, attached: Int, videos: Int = 0, videosAttached: Int = 0,
                        others: Int) -> LeftOut? {
        let photosMissing = pictures - attached
        let videosMissing = videos - videosAttached
        guard photosMissing > 0 || videosMissing > 0 else { return nil }
        if attached == 0, videosAttached == 0, others == 0 {
            if videos == 0 {
                return .instead(pictures == 1 ? "The photo could not be attached."
                                              : "The photos could not be attached.")
            }
            if pictures == 0 {
                return .instead(videos == 1 ? "The video could not be attached."
                                            : "The videos could not be attached.")
            }
            if pictures > 1, videos > 1 {
                return .instead("The photos and videos could not be attached.")
            }
            let photo = pictures == 1 ? "The photo" : "The photos"
            let video = videos == 1 ? "the video" : "the videos"
            return .instead("\(photo) and \(video) could not be attached.")
        }
        func counted(_ count: Int, _ one: String, _ many: String) -> String {
            count == 1 ? "1 \(one)" : "\(count) \(many)"
        }
        let photos = counted(photosMissing, "photo", "photos")
        let videoWords = counted(videosMissing, "video", "videos")
        if videosMissing <= 0 { return .line(photos + " could not be attached.") }
        if photosMissing <= 0 { return .line(videoWords + " could not be attached.") }
        return .line(photos + " and " + videoWords + " could not be attached.")
    }

    /// What a share offered and what came of its pictures and videos,
    /// counted as they are read, one at a time (`oneAtATime`).
    final class Tally {
        /// Everything offered, a picture, a video or anything else.
        var offered = 0
        /// The pictures among them.
        var pictures = 0
        /// The pictures attached.
        var attached = 0
        /// The videos among them.
        var videos = 0
        /// The videos attached.
        var videosAttached = 0

        init() {}

        var leftOut: LeftOut? {
            ShareItems.leftOut(pictures: pictures, attached: attached, videos: videos,
                               videosAttached: videosAttached,
                               others: offered - pictures - videos)
        }
    }
}
