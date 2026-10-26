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

    /// What names a share, the letter's subject: of what the sharing app
    /// hands the extension, the item's own title, else the words it came
    /// with; nil when neither has anything in it (B-125).
    ///
    /// Mail's subject for a share is the sharing app's answer to the share
    /// sheet's question `activityViewController(_:subjectForActivityType:)`,
    /// which iOS asks for Mail, Messages and AirDrop and never for a share
    /// extension, read from iOS 18.6's ShareSheet; and Mail fetches nothing
    /// for it. So this takes what an extension is given:
    ///
    /// - Safari's page title, which it hands over as the item's words
    ///   (`attributedContentText`), "Opera house - Wikipedia", the subject
    ///   Mail gives the same share; seen in the iPadOS 18.6 simulator, and
    ///   on the test iPad since 2026-09-30.
    /// - An app's own title for the item (`attributedTitle`), which an app
    ///   can give by handing over an extension item of its own.
    /// - The words an app shares beside a link, which iOS hands over as
    ///   the item's words as well as a text.
    ///
    /// The YouTube app hands over the link alone (seen 2026-10-04 and
    /// 2026-10-21), so its share has no name here, where Mail's has the
    /// video's. An app's subject and its LinkPresentation title for the
    /// share sheet's header both stop at the share sheet: seen in the
    /// simulator, an app offering both, and the extension had the link
    /// alone. Mail fetches nothing to fill a share's Subject; here, by the
    /// owner's ruling of 2026-10-25, a YouTube video's title is asked of
    /// YouTube as the sheet comes up (`VideoTitle`, B-126), and nothing
    /// else is fetched.
    static func name(title: String?, words: String?) -> String? {
        [title, words]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
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

        /// What the last file's copy measured on the disk (`file`), or the
        /// last file written there (`written`), staged or taken away again
        /// for want of room: the size that decided it, for the log. Nil
        /// when the last file was not copied or not written, or could not
        /// be measured.
        private(set) var lastMeasured: Int64?

        /// The pictures staged with no name of their own, which numbers the
        /// next: "image0.jpeg", "image1.png" (`SharedPhoto.name`). One count
        /// for the share, as Mail counts in a letter, and only of those
        /// staged, so the names in the letter run on without a gap.
        private(set) var unnamed = 0

        /// What this staging may take: `budget` for a share, which begins
        /// a letter; for the composer, what the letter's rows leave of it
        /// (`room(after:)`, B-108), so a file picked there never makes a
        /// letter that could not go.
        let limit: Int64

        /// What is left of `limit`.
        var room: Int64 { limit - staged }
        private let write: (Data, String) throws -> URL
        private let copy: (URL, String) throws -> URL
        private let place: (String) throws -> URL
        private let discard: (URL) -> Void

        /// `write` puts bytes on the disk and `copy` a file the sharing app
        /// handed over, each under the name given, and says where. `place`
        /// says where a file of that name is to be written, for `written`,
        /// and `discard` takes one away again. `room` is what the files may
        /// weigh together, never more than `budget`, and `unnamed` the
        /// pictures with no name already in the letter, which numbers the
        /// next (B-108): a share begins with all of the one and none of the
        /// other.
        init(room: Int64 = budget, unnamed: Int = 0,
             write: @escaping (Data, String) throws -> URL = AttachmentStore.write,
             copy: @escaping (URL, String) throws -> URL = AttachmentStore.copy,
             place: @escaping (String) throws -> URL = AttachmentStore.place,
             discard: @escaping (URL) -> Void = { AttachmentStore.removeStaged($0) }) {
            limit = max(0, min(room, Self.budget))
            self.unnamed = max(0, unnamed)
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
            guard staged + size <= limit, let copied = try? copy(url, filename) else {
                return nil
            }
            lastMeasured = Self.measured(copied)
            guard let measured = lastMeasured, staged + measured <= limit else {
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
        /// letter counts, and `lastMeasured`. Nil, with nothing left on the
        /// disk, when there is no room either time, `write` fails, or the
        /// file cannot be measured.
        func written(named filename: String, mimeType: String, expected: Int64,
                     unnamed: Bool = false, _ write: (URL) -> Bool) -> SharedItem? {
            lastMeasured = nil
            guard staged + expected <= limit, let url = try? place(filename) else { return nil }
            guard write(url) else {
                discard(url)
                return nil
            }
            lastMeasured = Self.measured(url)
            guard let size = lastMeasured, size > 0, staged + size <= limit else {
                discard(url)
                return nil
            }
            return stage(size: size, filename: filename, mimeType: mimeType, unnamed: unnamed) {
                url
            }
        }

        /// Where a file named `filename` may be written, in a directory of
        /// its own, as `written` places one: a video's H.264 copy, made
        /// after its original is staged (`ShareItems.compatible`, B-142).
        /// Nil when no place can be made.
        func placed(_ filename: String) -> URL? {
            try? place(filename)
        }

        /// A file written at a place this gave (`placed`) and not staged,
        /// taken away again.
        func remove(_ url: URL) {
            discard(url)
        }

        /// `item`, a file staged here, taken away again, and its room given
        /// back: a video whose conversion was called off (B-142).
        func unstage(_ item: SharedItem) {
            guard case let .file(url, _, _, size) = item else { return }
            discard(url)
            staged -= size
        }

        /// The file at `url`, written at a place this gave (`placed`),
        /// staged in place of `item`, a file staged here (B-142): measured,
        /// and staged when it fits the room `item` leaves, under `item`'s
        /// name and type, `item` then taken away. Otherwise it is taken
        /// away itself, and `item` stays. `lastMeasured` is what it
        /// measured, nil when it could not be. Nil when it does not take
        /// `item`'s place.
        func replace(_ item: SharedItem, with url: URL) -> SharedItem? {
            lastMeasured = nil
            guard case let .file(old, filename, mimeType, size) = item else {
                discard(url)
                return nil
            }
            lastMeasured = Self.measured(url)
            guard let measured = lastMeasured, measured > 0, staged - size + measured <= limit else {
                discard(url)
                return nil
            }
            discard(old)
            staged -= size
            return stage(size: measured, filename: filename, mimeType: mimeType, unnamed: false) {
                url
            }
        }

        /// What `rows`, a letter's files, leave of `budget` for more: the
        /// room the composer's picks begin with (B-108). A row whose size
        /// is not known counts as the whole of it, since what it weighs
        /// could be anything, and the letter with it might not go.
        static func room(after rows: [DraftAttachment]) -> Int64 {
            var left = budget
            for row in rows {
                guard let size = row.size else { return 0 }
                left -= max(0, size)
            }
            return max(0, left)
        }

        /// The size of the file at `url`, as the disk has it.
        private static func measured(_ url: URL) -> Int64? {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes?[.size] as? NSNumber)?.int64Value
        }

        private func stage(size: Int64, filename: String, mimeType: String, unnamed: Bool,
                           _ put: () throws -> URL) -> SharedItem? {
            guard staged + size <= limit, let url = try? put() else { return nil }
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
        /// No file, the read called off (`Loading`, B-142): as the app went
        /// into the background, set aside to be read again on his return,
        /// or once nothing would take it, counted out or the letter closed.
        /// The composer's own line says which (`ComposeIntake`).
        case calledOff
    }

    /// A file a provider handed over at `url`, `size` bytes by its account,
    /// read as `type`, and lasting only as long as the read's call back:
    /// copied into `staging` under `name` when it fits (`Staging.file`),
    /// and its line in the log (`fileNote`). A video staged, where
    /// `videos` is given, is then made H.264 in the app where it needs to
    /// be (`compatible`, B-142), from the copy, once the call back has
    /// returned and the provider's file, and Photos' claim on the app with
    /// it, have been let go; `done` has what goes then. A file that does
    /// not fit is left out at once, and nothing is made of it.
    static func stageRead(_ url: URL, size: Int64, type: String, suggested: Bool, name: String,
                          mimeType: String, videos: VideoConversion?, staging: Staging,
                          loading: Loading, done: @escaping (SharedItem?) -> Void) {
        let room = staging.room
        let item = staging.file(at: url, size: size, named: name, mimeType: mimeType)
        // What its copy measured, where it was copied, which is what
        // decided it; the sharing app's word where it was not.
        let bytes = staging.lastMeasured ?? size
        Diagnostics.log(.note, fileNote(read: type, suggested: suggested, name: name,
                                        mimeType: mimeType, bytes: bytes,
                                        went: fileWent(item, size: bytes, room: room)))
        guard let item, let videos else { return done(item) }
        compatible(item, staging: staging, loading: loading, conversion: videos, done: done)
    }

    // MARK: - A video made H.264 (B-142)

    /// What came of making a video H.264 (`VideoConversion`).
    enum Converted: Equatable {
        /// Its pictures are H.264 already, or it has none: nothing made.
        case notNeeded
        /// Written whole where it was asked to be.
        case made
        /// Called off (`Loading.cancel`).
        case cancelled
        /// Stopped as the app went into the background: AVFoundation's
        /// `operationInterrupted`, an encoder an app gives up there.
        case interrupted
        /// Failed for another reason, its error's code where it had one.
        case failed(code: Int?)
    }

    /// How a video is made H.264 in the app: `convert` writes an H.264
    /// copy of the video at its first URL to its second, as the file type
    /// its third names (`exportType`), and calls back once, from any
    /// thread; it returns what calls it off, which `Loading` keeps. The
    /// iPad's is AVFoundation's (`h264`, beside the sheet); the suite's,
    /// the test's own.
    struct VideoConversion {
        let convert: (_ from: URL, _ to: URL, _ fileType: String,
                      _ done: @escaping (Converted) -> Void) -> () -> Void

        init(convert: @escaping (_ from: URL, _ to: URL, _ fileType: String,
                                 _ done: @escaping (Converted) -> Void) -> () -> Void) {
            self.convert = convert
        }
    }

    /// The codecs of a picture every recipient can play: H.264, as
    /// `avc1` and as `avc3`, by their four letters.
    static let h264Codecs: Set<String> = ["avc1", "avc3"]

    /// Whether a video whose pictures are coded as `codecs`, by their four
    /// letters, one for each of its video tracks' formats, is made H.264:
    /// when any is not H.264 already, as Photos' compatible copy made an
    /// HEVC video H.264 and left an H.264 one as it was (B-108). HEVC,
    /// `hvc1` or `hev1`, is the case: an iPad or an iPhone films in it.
    /// Not one with no pictures at all.
    static func needsH264(codecs: [String]) -> Bool {
        codecs.contains { !h264Codecs.contains($0) }
    }

    /// A codec's four letters, from the number CoreMedia gives them as,
    /// its first letter in its highest byte: "hvc1", "avc1". A byte that
    /// is not a printable letter is a "?".
    static func fourCC(_ code: UInt32) -> String {
        String([24, 16, 8, 0].map { shift -> Character in
            let byte = UInt8((code >> UInt32(shift)) & 0xFF)
            return (0x20...0x7E).contains(byte) ? Character(UnicodeScalar(byte)) : "?"
        })
    }

    /// The file type a video's H.264 copy is written as, by its name's
    /// extension, so that its name and its MIME type stay those of the
    /// video he picked: MPEG-4 for ".mp4", M4V for ".m4v", and QuickTime,
    /// which is how Photos keeps a video, ".MOV", for anything else.
    /// AVFoundation's `AVFileType` by its identifier.
    static func exportType(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "mp4": return "public.mpeg-4"
        case "m4v": return "com.apple.m4v-video"
        default: return "com.apple.quicktime-movie"
        }
    }

    /// What became of a video staged as it came, for the log.
    enum VideoMade: Equatable {
        /// H.264 already, or with no pictures: it goes as it came.
        case asItCame
        /// Made H.264, `bytes` from the original's `from`, and that goes.
        case h264(bytes: Int64, from: Int64)
        /// Its H.264 copy, `bytes`, more than the room it had, `room`:
        /// the original goes.
        case h264NoRoom(bytes: Int64, room: Int64)
        /// Not made H.264, the conversion failed, its error's code where
        /// it had one, or its copy not placed or not measured: the
        /// original goes.
        case failed(code: Int?)
        /// Stopped as the app went into the background: the original
        /// handed back, and the read marked so (`Loading.wasInterrupted`).
        case interrupted
        /// Called off: nothing goes.
        case calledOff
    }

    /// The line the log gets for a video once its conversion has ended
    /// (`compatible`), after its `SHARE-FILE` line. Numbers only.
    static func videoNote(_ made: VideoMade) -> String {
        switch made {
        case .asItCame:
            return "SHARE-VIDEO goes as it came, H.264 already"
        case .h264(let bytes, let from):
            return "SHARE-VIDEO made H.264, bytes=\(bytes) from=\(from)"
        case .h264NoRoom(let bytes, let room):
            return "SHARE-VIDEO its H.264 copy bytes=\(bytes), more than the letter's room, "
                + "\(room / 1_000_000) MB left: the original goes"
        case .failed(let code):
            return "SHARE-VIDEO not made H.264, failed\(code.map { " code=\($0)" } ?? ""): "
                + "the original goes"
        case .interrupted:
            return "SHARE-VIDEO not made H.264, stopped as the app went"
        case .calledOff:
            return "SHARE-VIDEO called off"
        }
    }

    /// A video staged as it came (`original`, a file staged in `staging`),
    /// made H.264 in the app where it needs to be (B-142).
    ///
    /// The picker hands over the video Photos keeps, with no copy made
    /// (`.current`): its compatible copy was made under a file
    /// coordination claim on the app, which calling the read off did not
    /// end, and iOS ended the app half a minute after it left the front
    /// (the test iPad, 2026-10-26). So the H.264 copy B-108 sent is made
    /// here, from the staged original, where no claim is held:
    /// `conversion`'s, kept in `loading`, which calls it off with the
    /// rest of the read.
    ///
    /// What goes: the H.264 copy where one was made and fits the room the
    /// original leaves, in its place, under its name and type; otherwise
    /// the original, H.264 already, its copy larger than the room, or
    /// its conversion failed; a video that fits as itself is not left out
    /// for its copy. Stopped as the app went, the original too, and the
    /// read marked so: the composer sets it aside, to be read again on his
    /// return, while the app is away (`ComposeIntake`). Called off,
    /// nothing, the original and any copy taken away. One line in the log
    /// as it ends (`videoNote`); `done` once, from any thread.
    static func compatible(_ original: SharedItem, staging: Staging, loading: Loading,
                           conversion: VideoConversion, done: @escaping (SharedItem?) -> Void) {
        guard case let .file(url, filename, _, size) = original else { return done(original) }
        let room = staging.room + size
        func calledOff(_ copy: URL?) {
            if let copy { staging.remove(copy) }
            staging.unstage(original)
            Diagnostics.log(.note, videoNote(.calledOff))
            done(nil)
        }
        guard !loading.isCancelled else { return calledOff(nil) }
        guard let copy = staging.placed(filename) else {
            Diagnostics.log(.note, videoNote(.failed(code: nil)))
            return done(original)
        }
        let callOff = conversion.convert(url, copy, exportType(for: filename)) { converted in
            guard !loading.isCancelled else { return calledOff(copy) }
            switch converted {
            case .cancelled:
                calledOff(copy)
            case .notNeeded:
                staging.remove(copy)
                Diagnostics.log(.note, videoNote(.asItCame))
                done(original)
            case .made:
                if let made = staging.replace(original, with: copy),
                   case let .file(_, _, _, bytes) = made {
                    Diagnostics.log(.note, videoNote(.h264(bytes: bytes, from: size)))
                    return done(made)
                }
                Diagnostics.log(.note, videoNote(staging.lastMeasured.map {
                    .h264NoRoom(bytes: $0, room: room)
                } ?? .failed(code: nil)))
                done(original)
            case .failed(let code):
                staging.remove(copy)
                Diagnostics.log(.note, videoNote(.failed(code: code)))
                done(original)
            case .interrupted:
                staging.remove(copy)
                loading.interrupted()
                Diagnostics.log(.note, videoNote(.interrupted))
                done(original)
            }
        }
        loading.track(conversion: callOff)
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
        case .calledOff: words = "called off"
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

    /// What the transcript is tagged when something was left out:
    /// `blackmail-send-<time>-left-out.txt` (`keepLog`).
    static let leftOutTag = "left-out"

    /// The log written out when the sheet is to say a picture or a video
    /// could not be attached (B-090), as a send's end writes it
    /// (`CaptureProbe.dumpTranscript`), in the extension's own tmp and
    /// among the newest ten kept. A share of pictures alone of which none
    /// came has no letter and no Send, and the log was written only at a
    /// send's end, so the `SHARE-PICTURE` line that says why was never
    /// where a check could read it. Under its own time, not the send's
    /// session, which is the last letter's. Nothing when everything came.
    static func keepLog(for leftOut: LeftOut?,
                        session: String = String(Int(Date().timeIntervalSince1970))) {
        guard leftOut != nil else { return }
        CaptureProbe.dumpTranscript(leftOutTag, session: session)
    }

    /// A read begun from an item provider, which can be called off (B-142):
    /// the `Progress` of each load it has begun, a video's one or a
    /// picture's, each way after the one before it (`picture`). All of
    /// them are kept, and all called off: a picture's next load can be
    /// handed over from inside the last one's call back before that one's
    /// own `Progress` is, and calling off a load that has ended does
    /// nothing.
    ///
    /// Called off as the app goes into the background with a video still
    /// coming into the composer (`ComposeIntake.away`), and once nothing
    /// will take what it brings, counted out or the letter closed
    /// (`ComposeIntake.countOut`, `close`). While Photos makes
    /// its copy of a video, iOS holds a file coordination claim on the
    /// app; in the background it gives such a claim about 30 seconds, then
    /// ends the app, with no crash report and nothing said, and the letter
    /// with it (seen on the test iPad, 2026-10-25). The load's `Progress`
    /// is how a load is called off; it was thrown away.
    ///
    /// Calling a load off does not end Photos' copy, nor its claim: it
    /// only has the load call back at once with nothing, and the claim is
    /// held until Photos' copy is made (seen on the test iPad, 2026-10-26).
    /// So the picker asks for no copy (`.current`), and a video is made
    /// H.264 in the app, where it can be called off: the conversion is
    /// kept here too (`track(conversion:)`, `compatible`), and called off
    /// with the loads. A conversion stopped as the app went marks the read
    /// (`wasInterrupted`).
    ///
    /// Called off, a load begun after it is called off at once, and a
    /// picture's next way of being read is not begun (`isCancelled`).
    /// Any thread: the loads call back on threads of their own.
    final class Loading: @unchecked Sendable {
        private let lock = NSLock()
        private var callOffs: [() -> Void] = []
        private var cancelled = false
        private var stopped = false

        init() {}

        /// Whether it has been called off.
        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        /// Whether a video's conversion was stopped as the app went into
        /// the background (`compatible`): what it brings is its original,
        /// which the composer sets aside rather than takes, while the app
        /// is away (`ComposeIntake`).
        var wasInterrupted: Bool {
            lock.lock()
            defer { lock.unlock() }
            return stopped
        }

        /// A video's conversion was stopped as the app went.
        func interrupted() {
            lock.lock()
            stopped = true
            lock.unlock()
        }

        /// `progress` is a load it has begun. Called off already, it is
        /// called off at once.
        func track(_ progress: Progress) {
            track(callOff: { progress.cancel() })
        }

        /// `callOff` calls off a video's conversion it has begun
        /// (`compatible`): the iPad's cancels its `AVAssetExportSession`
        /// (`cancelExport`). Called off already, it is called at once.
        func track(conversion callOff: @escaping () -> Void) {
            track(callOff: callOff)
        }

        private func track(callOff: @escaping () -> Void) {
            lock.lock()
            let off = cancelled
            if !off { callOffs.append(callOff) }
            lock.unlock()
            if off { callOff() }
        }

        /// Calls off every load and conversion it has begun, and any begun
        /// after.
        func cancel() {
            lock.lock()
            cancelled = true
            let begun = callOffs
            callOffs = []
            lock.unlock()
            for callOff in begun { callOff() }
        }
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
