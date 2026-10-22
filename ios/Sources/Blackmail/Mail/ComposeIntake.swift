import Foundation

/// What the composer's Photo Library and Attach File bring into the letter
/// (B-108): each photo, video or file he chose read in through the share
/// sheet's own intake (`ShareItems.read`, `ShareItems.Staging`), onto the
/// disk and into the letter as a row, a row with its name and a spinner
/// while it comes, and what could not be attached said, in the share
/// sheet's words.
///
/// Out of `ComposeViewController` for the reason `ComposeActions` is: the
/// controller is UIKit, and the suite runs where there is none.
///
/// One at a time, every pick in one queue, as the share sheet reads what it
/// is offered. Each begins with the room the letter's rows leave of its
/// 25 MB, every row before it already in (`Staging.room(after:)`), so two
/// picks never make together a letter that could not go.
///
/// Never stuck: each is given `bound`, three minutes, from when it begins.
/// One not in by then is counted out, its row goes, the next begins, and it
/// is said with the rest of its pick; come after all, it is thrown away and
/// its file removed. A photo kept only in iCloud, with no connection, is
/// the case: the picker can wait for it for ever.
///
/// Nor is a Send or a Save Draft waiting for them: from the tap,
/// everything still coming or waiting its turn is given one `bound`
/// together (`hurry`), not one each after the one before, which for five
/// iCloud photos with no connection was a quarter of an hour of
/// "Sending…". At it, all of it is counted out at once and said in one
/// alert.
///
/// The bound runs only while the app is in front (`away`, `back`). Left
/// for longer than it while a video comes, it would have counted out on
/// his return a video that had come meanwhile, the bound and the video
/// each waiting for the app in no set order.
///
/// Never short: everything chosen counts in `ComposeActions` from the pick
/// until it is in, has failed or has been counted out (`itemComing`,
/// `itemLanded`), so Send and Save Draft wait for it. A pick that ends with
/// something missing says so as it ends, and tells `ComposeActions` it came
/// short: a Send waiting for it does not go (`itemLanded(cameShort:)`).
@MainActor
final class ComposeIntake {

    /// What one thing he chose is, as it is said when it could not be
    /// attached: a photo, a video, or any other file.
    enum Kind: Equatable {
        case picture, video, file
    }

    /// One thing he chose: the name its row shows while it comes, what it
    /// is, and how it is read in.
    struct Item {
        let name: String
        /// What the words call it should it be counted out before it has
        /// begun (`hurry`). Once begun, it is what its load counts it as,
        /// as the share sheet counts what it is offered.
        let kind: Kind
        /// Whether it is a file the document picker handed over, to be
        /// moved into the staging rather than copied (`AttachmentStore.move`).
        let moves: Bool
        /// Reads it in through `staging`, counted in `tally` as the share
        /// sheet counts what it is offered, and calls back once, from any
        /// thread, with what was staged, or nil.
        let load: (ShareItems.Staging, ShareItems.Tally, @escaping (SharedItem?) -> Void) -> Void

        /// `name` as the picker gives it; with none, "Photo" or "Video",
        /// so the row and VoiceOver have a word while it comes.
        init(name: String?, kind: Kind, moves: Bool = false,
             load: @escaping (ShareItems.Staging, ShareItems.Tally,
                              @escaping (SharedItem?) -> Void) -> Void) {
            self.name = ComposeIntake.shown(name, kind)
            self.kind = kind
            self.moves = moves
            self.load = load
        }
    }

    /// The name a row shows while it comes: its own, or with none, what it
    /// is.
    nonisolated static func shown(_ name: String?, _ kind: Kind) -> String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return kind == .video ? "Video" : "Photo"
    }

    /// What Photo Library hands over is, by the types it offers, as
    /// `ShareItems.read` will take it: a picture first, by its type
    /// (`SharedPhoto.fileType`), then a video (`ShareItems.movieType`).
    /// Anything else is a picture, since Photo Library offers no other
    /// (`ComposeViewController`).
    nonisolated static func kind(offered: [String], isMovie: (String) -> Bool) -> Kind {
        if SharedPhoto.fileType(offered: offered) != nil { return .picture }
        if ShareItems.movieType(offered: offered, isMovie: isMovie) != nil { return .video }
        return .picture
    }

    /// Something on its way in: its row's name, shown with a spinner.
    struct Coming: Equatable {
        let id: Int
        let name: String
    }

    /// How long each thing he chose is given to come in.
    nonisolated static let bound: Duration = .seconds(180)

    /// Everything chosen and not yet in, failed or counted out, in the
    /// order he chose it: the rows with a spinner.
    private(set) var coming: [Coming] = []

    /// One pick, Photo Library's or Attach File's: what came of it, counted
    /// as the share sheet counts a share, and how many of it are still to
    /// come.
    private final class Pick {
        let tally = ShareItems.Tally()
        var files = 0
        var filesAttached = 0
        var left: Int
        init(left: Int) { self.left = left }
    }

    private struct Queued {
        let id: Int
        let pick: Pick
        let item: Item
    }

    /// The one being read in: its own tally and staging, so one counted out
    /// and come after all touches nothing of the next, and its bound, none
    /// while the app is away.
    private struct Current {
        let id: Int
        let pick: Pick
        let tally: ShareItems.Tally
        let staging: ShareItems.Staging
        var timer: Task<Void, Never>?
    }

    private var queue: [Queued] = []
    private var current: Current?
    private var numbered = 0
    /// A Send or a Save Draft is waiting for what is still coming, which
    /// has one bound for all of it from the tap (`hurry`), and its timer,
    /// none while the app is away.
    private var hurried = false
    private var hurryTimer: Task<Void, Never>?
    /// The app is not in front: no bound runs (`away`, `back`).
    private var isAway = false
    /// The pictures with no name put in the letter so far, which numbers
    /// the next: "image0.jpeg", "image1.jpeg" (`SharedPhoto.name`).
    private var unnamed = 0

    private let actions: ComposeActions
    private let rows: () -> [DraftAttachment]
    private let landed: (URL, DraftAttachment) -> Void
    private let changed: () -> Void
    private let tell: (String) -> Void
    private let staging: (_ room: Int64, _ unnamed: Int, _ moves: Bool) -> ShareItems.Staging
    private let discard: @Sendable (URL) -> Void
    private let limit: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    /// `rows` are the letter's files now, which the room is measured from.
    /// `landed` puts one in: the staged file, and its row. `changed` is told
    /// when `coming` has changed; `tell` says what could not be attached.
    /// `staging` makes each one's staging, `discard` removes what one
    /// counted out staged after all, and `sleep` waits `bound`: the test's
    /// own clock in a test.
    init(actions: ComposeActions,
         rows: @escaping () -> [DraftAttachment],
         landed: @escaping (URL, DraftAttachment) -> Void,
         changed: @escaping () -> Void,
         tell: @escaping (String) -> Void,
         staging: @escaping (Int64, Int, Bool) -> ShareItems.Staging = ComposeIntake.staging,
         discard: @escaping @Sendable (URL) -> Void = { AttachmentStore.removeStaged($0) },
         bound: Duration = ComposeIntake.bound,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.actions = actions
        self.rows = rows
        self.landed = landed
        self.changed = changed
        self.tell = tell
        self.staging = staging
        self.discard = discard
        self.limit = bound
        self.sleep = sleep
        actions.whenWaiting { [weak self] in self?.hurry() }
    }

    /// The app's staging: in `tmp/Attachments`, as the share sheet's, a
    /// document picker's file moved there and anything else copied.
    nonisolated static func staging(room: Int64, unnamed: Int, moves: Bool) -> ShareItems.Staging {
        ShareItems.Staging(room: room, unnamed: unnamed,
                           copy: moves ? AttachmentStore.move : AttachmentStore.copy)
    }

    /// One pick: counted at once, each with a row and a spinner, and read
    /// in after anything already coming.
    func take(_ items: [Item]) {
        guard !items.isEmpty else { return }
        let pick = Pick(left: items.count)
        for item in items {
            numbered += 1
            queue.append(Queued(id: numbered, pick: pick, item: item))
            coming.append(Coming(id: numbered, name: item.name))
            actions.itemComing()
        }
        Diagnostics.log(.note, "COMPOSE-PICK offered=\(items.count) moves=\(items.first?.moves == true)")
        changed()
        startNext()
    }

    private func startNext() {
        guard current == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        let id = next.id
        let staging = self.staging(ShareItems.Staging.room(after: rows()), unnamed, next.item.moves)
        let tally = ShareItems.Tally()
        current = Current(id: id, pick: next.pick, tally: tally, staging: staging,
                          timer: isAway ? nil : timer(for: id))
        let discard = self.discard
        next.item.load(staging, tally) { [weak self] item in
            Task { @MainActor [weak self] in
                guard let self else {
                    // The composer has gone: nothing is left to put it in.
                    if let url = Self.file(item) { discard(url) }
                    return
                }
                self.arrived(id, item)
            }
        }
    }

    /// The bound of the one numbered `id`, from now. Cancelled, it counts
    /// nothing out, even when it has already run its time and waits only
    /// for its turn on the main thread.
    private func timer(for id: Int) -> Task<Void, Never> {
        let limit = self.limit
        let sleep = self.sleep
        return Task { [weak self] in
            do { try await sleep(limit) } catch { return }
            guard !Task.isCancelled else { return }
            self?.countOut(id)
        }
    }

    /// Send or Save Draft has begun to wait for what is still coming
    /// (`ComposeActions.whenWaiting`): from now, all of it, the one being
    /// read and every one waiting its turn, is given one `bound` together.
    /// The one being read keeps its own bound if that ends first. Nothing
    /// when nothing is coming, or when a wait is bounded already.
    func hurry() {
        guard !coming.isEmpty, !hurried else { return }
        hurried = true
        if !isAway { hurryTimer = hurryBound() }
        Diagnostics.log(.note, "COMPOSE-WAIT coming=\(coming.count)")
    }

    private func hurryBound() -> Task<Void, Never> {
        let limit = self.limit
        let sleep = self.sleep
        return Task { [weak self] in
            do { try await sleep(limit) } catch { return }
            guard !Task.isCancelled else { return }
            self?.countOutAll()
        }
    }

    /// The app has gone into the background: no bound runs until it is
    /// back. iOS suspends the app soon after, with the clock still going,
    /// and on its return a bound that had run out and a load that had come
    /// would each wait for the main thread in no set order.
    func away() {
        isAway = true
        current?.timer?.cancel()
        current?.timer = nil
        hurryTimer?.cancel()
        hurryTimer = nil
    }

    /// The app is in front again: the one being read, and a wait already
    /// bounded, each have their bound again from now.
    func back() {
        guard isAway else { return }
        isAway = false
        if let id = current?.id, current?.timer == nil { current?.timer = timer(for: id) }
        if hurried, hurryTimer == nil { hurryTimer = hurryBound() }
    }

    /// The staged file of `item`, where it is one.
    nonisolated static func file(_ item: SharedItem?) -> URL? {
        guard case .file(let url, _, _, _)? = item else { return nil }
        return url
    }

    private func arrived(_ id: Int, _ item: SharedItem?) {
        guard let now = current, now.id == id else {
            // Counted out at its bound, and come after all: not in the
            // letter, which he has been told, nor left on the disk.
            if let url = Self.file(item) {
                discard(url)
                Diagnostics.log(.note, "COMPOSE-ITEM came after its bound, thrown away")
            }
            return
        }
        now.timer?.cancel()
        current = nil
        unnamed = now.staging.unnamed
        var attached = false
        if case let .file(url, filename, mimeType, size)? = item {
            landed(url, DraftAttachment(source: .localFile(url), filename: filename,
                                        mimeType: mimeType, size: size))
            attached = true
        }
        count(now.tally, attached: attached, into: now.pick)
        settle([(id, now.pick)])
    }

    /// Not in at its bound: counted out, and the next begun.
    private func countOut(_ id: Int) {
        guard let now = current, now.id == id else { return }
        current = nil
        Diagnostics.log(.note, "COMPOSE-ITEM counted out after \(limit.components.seconds) s")
        count(now.tally, attached: false, into: now.pick)
        settle([(id, now.pick)])
    }

    /// A Send's or a Save Draft's bound has passed (`hurry`): the one being
    /// read and every one waiting its turn counted out at once, those not
    /// begun as what they are (`Item.kind`), and said together, once.
    private func countOutAll() {
        hurryTimer = nil
        var out: [(Int, Pick)] = []
        if let now = current {
            now.timer?.cancel()
            current = nil
            count(now.tally, attached: false, into: now.pick)
            out.append((now.id, now.pick))
        }
        for waiting in queue {
            count(waiting.item.kind, into: waiting.pick)
            out.append((waiting.id, waiting.pick))
        }
        queue = []
        guard !out.isEmpty else { return }
        Diagnostics.log(.note, "COMPOSE-WAIT counted out \(out.count) after \(limit.components.seconds) s")
        settle(out)
    }

    /// One counted out before it began, by what it is.
    private func count(_ kind: Kind, into pick: Pick) {
        pick.tally.offered += 1
        switch kind {
        case .picture: pick.tally.pictures += 1
        case .video: pick.tally.videos += 1
        case .file: pick.files += 1
        }
    }

    /// What came of one, added to its pick's count. A picture or a video
    /// as the share sheet counted it, from its tally; anything else a file.
    /// Read only for what came: one counted out may still be counting on
    /// another thread, but what it is was counted as it began.
    private func count(_ tally: ShareItems.Tally, attached: Bool, into pick: Pick) {
        let isFile = tally.pictures == 0 && tally.videos == 0
        pick.tally.offered += 1
        pick.tally.pictures += tally.pictures
        pick.tally.videos += tally.videos
        if isFile { pick.files += 1 }
        guard attached else { return }
        if isFile {
            pick.filesAttached += 1
        } else {
            pick.tally.attached += tally.attached
            pick.tally.videosAttached += tally.videosAttached
        }
    }

    /// Those done with, one or, at a wait's bound, all: their rows gone,
    /// the picks they end said together, once, `ComposeActions` told of
    /// each, and the next begun. A wait's bound lets go once nothing is
    /// coming.
    private func settle(_ done: [(Int, Pick)]) {
        var ended: [Pick] = []
        for (id, pick) in done {
            coming.removeAll { $0.id == id }
            pick.left -= 1
            if pick.left == 0 { ended.append(pick) }
        }
        let words = ended.isEmpty ? nil : Self.words(for: ended)
        if coming.isEmpty {
            hurried = false
            hurryTimer?.cancel()
            hurryTimer = nil
        }
        changed()
        for _ in done { actions.itemLanded(cameShort: words != nil) }
        if let words {
            Diagnostics.log(.note, "COMPOSE-PICK left out: \(words)")
            tell(words)
        }
        startNext()
    }

    /// What is said of `picks` ended together, counted as one.
    private static func words(for picks: [Pick]) -> String? {
        var pictures = 0, attached = 0, videos = 0, videosAttached = 0, files = 0, filesAttached = 0
        for pick in picks {
            pictures += pick.tally.pictures
            attached += pick.tally.attached
            videos += pick.tally.videos
            videosAttached += pick.tally.videosAttached
            files += pick.files
            filesAttached += pick.filesAttached
        }
        return words(pictures: pictures, attached: attached, videos: videos,
                     videosAttached: videosAttached, files: files, filesAttached: filesAttached)
    }

    /// What is said when something he picked could not be attached: the
    /// share sheet's words for photos and videos (`ShareItems.leftOut`),
    /// and for any other file "The file could not be attached." when it
    /// was the one thing picked, "1 file could not be attached." or "N
    /// files could not be attached." otherwise. Nil when everything came.
    nonisolated static func words(pictures: Int, attached: Int, videos: Int, videosAttached: Int,
                                  files: Int, filesAttached: Int) -> String? {
        let photosMissing = max(0, pictures - attached)
        let videosMissing = max(0, videos - videosAttached)
        let filesMissing = max(0, files - filesAttached)
        guard filesMissing > 0 else {
            switch ShareItems.leftOut(pictures: pictures, attached: attached, videos: videos,
                                      videosAttached: videosAttached, others: files) {
            case .line(let words)?, .instead(let words)?: return words
            case nil: return nil
            }
        }
        func counted(_ count: Int, _ one: String, _ many: String) -> String {
            count == 1 ? "1 \(one)" : "\(count) \(many)"
        }
        if photosMissing == 0, videosMissing == 0 {
            if files == 1, pictures == 0, videos == 0 { return "The file could not be attached." }
            return counted(filesMissing, "file", "files") + " could not be attached."
        }
        var parts: [String] = []
        if photosMissing > 0 { parts.append(counted(photosMissing, "photo", "photos")) }
        if videosMissing > 0 { parts.append(counted(videosMissing, "video", "videos")) }
        parts.append(counted(filesMissing, "file", "files"))
        let last = parts.removeLast()
        return parts.joined(separator: ", ") + " and " + last + " could not be attached."
    }

    /// A file Attach File handed over at `url`, the document picker's copy
    /// in the app's Inbox (B-108): moved into the staging, measured, and
    /// left out past the room, as the share sheet copies a file in; named
    /// by its own name, made safe (`AttachmentStore.safeFilename`), its type
    /// from its extension (`AttachmentStore.mimeType`). What did not go in
    /// is removed from the Inbox. One that is not in the Inbox is copied,
    /// and left where it is.
    nonisolated static func file(at url: URL, inbox: URL? = AttachmentStore.inbox(),
                                 mimeType lookup: @escaping (String) -> String?) -> Item {
        let name = AttachmentStore.safeFilename(url.lastPathComponent)
        let moves = AttachmentStore.isInInbox(url, inbox: inbox)
        return Item(name: name, kind: .file, moves: moves) { staging, _, done in
            let mime = AttachmentStore.mimeType(of: name, lookup: lookup)
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            var item: SharedItem?
            var size: Int64 = 0
            let room = staging.room
            if values?.isRegularFile == true, let bytes = values?.fileSize {
                size = Int64(bytes)
                item = staging.file(at: url, size: size, named: name, mimeType: mime)
            }
            if item == nil, moves { AttachmentStore.removeFromInbox(url, inbox: inbox) }
            let measured = staging.lastMeasured ?? size
            Diagnostics.log(.note, ShareItems.fileNote(
                read: "document", suggested: false, name: name, mimeType: mime, bytes: measured,
                went: values?.isRegularFile == true
                    ? ShareItems.fileWent(item, size: measured, room: room) : .notGiven))
            done(item)
        }
    }
}
