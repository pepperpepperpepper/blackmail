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
/// Nor is anything read while the app is away (B-142). The read under way
/// as he locks the iPad or leaves the app is called off and set aside, its
/// row still turning and nothing counted out, and read again from the
/// start on his return, with three minutes of its own again; nothing else
/// is begun meanwhile. Left running, Photos' copy of a large video held a
/// file coordination claim on the app, which iOS gives a background app
/// about 30 seconds: then it ended the app, and the letter he was writing
/// went with it (seen on the test iPad, 2026-10-25). Calling the read off
/// did not end that copy, nor the claim (2026-10-26): so the picker asks
/// for none (`.current`), and a video is made H.264 in the app, which the
/// call-off does end (`ShareItems.compatible`). A read that cannot be
/// called off, a file Attach File handed over, which is read where it is
/// at once, goes on. With a Send or a Save Draft waiting for it, the read
/// under way is let run `grace`, 20 seconds, first, well inside those 30:
/// a photo that comes in a second or two still goes while he is away; a
/// video's conversion stopped there is set aside as well
/// (`interruptedAway`).
///
/// And no read is left running once nothing will take what it brings:
/// counted out at its bound or a wait's, or the sheet closed with no Send
/// or Save Draft waiting (`close`), it is called off there, as it is as
/// the app goes, a video's conversion with it. Left running after a
/// count-out, Photos' copy went on for over a minute more, its claim with
/// it, and leaving the app then got the app ended all the same.
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
        /// thread, with what was staged, or nil. Returns the read, which
        /// `away` calls off and sets aside (`ShareItems.Loading`, B-142);
        /// nil for a read that cannot be called off, which goes on.
        let load: (ShareItems.Staging, ShareItems.Tally,
                   @escaping (SharedItem?) -> Void) -> ShareItems.Loading?

        /// `name` as the picker gives it; with none, "Photo" or "Video",
        /// so the row and VoiceOver have a word while it comes.
        init(name: String?, kind: Kind, moves: Bool = false,
             load: @escaping (ShareItems.Staging, ShareItems.Tally,
                              @escaping (SharedItem?) -> Void) -> ShareItems.Loading?) {
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

    /// How long the read under way is let run on as the app goes, when a
    /// Send or a Save Draft waits for what is coming, before it is called
    /// off and set aside (`away`, B-142). iOS gave Photos' claim on the app
    /// 26 seconds in the background to its warning and 31 to the end, from
    /// the moment the app went (the test iPad, 2026-10-25): 20 leaves the
    /// call-off time to take.
    nonisolated static let grace: Duration = .seconds(20)

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
    /// while the app is away. `read` numbers this read of it, which its
    /// call back carries: one set aside (`away`) and begun again is
    /// another read of the same row, and the first one's call back is told
    /// from the second's. `loading` is the read, to call it off; nil where
    /// it cannot be. `grace` is the time it is let run on as the app goes,
    /// a Send or a Save Draft waiting (`ComposeIntake.grace`).
    private struct Current {
        let id: Int
        let read: Int
        let pick: Pick
        let item: Item
        let tally: ShareItems.Tally
        let staging: ShareItems.Staging
        var loading: ShareItems.Loading?
        var timer: Task<Void, Never>?
        var grace: Task<Void, Never>?

        /// Its bound and its grace stopped, and its read called off, a
        /// video's conversion with it (`ShareItems.Loading`, B-142).
        func callOff() {
            timer?.cancel()
            grace?.cancel()
            loading?.cancel()
        }
    }

    /// A read called off as the app went (`away`), its row back at the
    /// head of the queue. Its call back is still to come: the nothing of a
    /// read called off, or what it read should it have ended first.
    /// `loading` is the read, which says whether a video's conversion was
    /// stopped as the app went (B-142).
    private struct SetAside {
        let id: Int
        let pick: Pick
        let tally: ShareItems.Tally
        let staging: ShareItems.Staging
        let loading: ShareItems.Loading?
    }

    private var queue: [Queued] = []
    private var current: Current?
    private var setAside: [Int: SetAside] = [:]
    /// The rows counted out, at their own bound or a wait's: what a read of
    /// one set aside brings after is thrown away, and the log says why.
    private var countedOut: Set<Int> = []
    /// Reads let go before they called back, by number, with what let
    /// them go where it was not their bound: what each brings after is
    /// thrown away, and the log says why. The letter closed, or a read of
    /// the same row set aside before it bringing the row (`cameSetAside`).
    private var late: [Int: String] = [:]
    /// The sheet is done with what is coming (`close`): nothing more is
    /// begun.
    private var isClosed = false
    private var numbered = 0
    private var reads = 0
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
    private let graceLimit: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    /// `rows` are the letter's files now, which the room is measured from.
    /// `landed` puts one in: the staged file, and its row. `changed` is told
    /// when `coming` has changed; `tell` says what could not be attached.
    /// `staging` makes each one's staging, `discard` removes what one
    /// counted out staged after all, and `sleep` waits `bound` and `grace`:
    /// the test's own clock in a test.
    init(actions: ComposeActions,
         rows: @escaping () -> [DraftAttachment],
         landed: @escaping (URL, DraftAttachment) -> Void,
         changed: @escaping () -> Void,
         tell: @escaping (String) -> Void,
         staging: @escaping (Int64, Int, Bool) -> ShareItems.Staging = ComposeIntake.staging,
         discard: @escaping @Sendable (URL) -> Void = { AttachmentStore.removeStaged($0) },
         bound: Duration = ComposeIntake.bound,
         grace: Duration = ComposeIntake.grace,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.actions = actions
        self.rows = rows
        self.landed = landed
        self.changed = changed
        self.tell = tell
        self.staging = staging
        self.discard = discard
        self.limit = bound
        self.graceLimit = grace
        self.sleep = sleep
        actions.whenWaiting { [weak self] in self?.hurry() }
        actions.reading { [weak self] in self?.isReading ?? false }
        actions.whenClosed { [weak self] in self?.close() }
    }

    /// Whether something is being read in now: not waiting its turn, nor
    /// set aside as the app went (`away`). What `ComposeActions.putAside`
    /// waits for, as he leaves the app.
    var isReading: Bool { current != nil }

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

    /// The next in the queue begun, while nothing is and the app is in
    /// front: nothing is begun while it is away (B-142), nor once the sheet
    /// is done with what is coming (`close`). `ComposeActions` is told, so
    /// a Send or a Save Draft that gave its background time back while
    /// nothing was read asks for it again.
    private func startNext() {
        guard current == nil, !isAway, !isClosed, !queue.isEmpty else { return }
        defer { actions.readingChanged() }
        let next = queue.removeFirst()
        reads += 1
        let read = reads
        let staging = self.staging(ShareItems.Staging.room(after: rows()), unnamed, next.item.moves)
        let tally = ShareItems.Tally()
        current = Current(id: next.id, read: read, pick: next.pick, item: next.item, tally: tally,
                          staging: staging, loading: nil, timer: timer(for: read), grace: nil)
        let discard = self.discard
        let loading = next.item.load(staging, tally) { [weak self] item in
            Task { @MainActor [weak self] in
                guard let self else {
                    // The composer has gone: nothing is left to put it in.
                    if let url = Self.file(item) { discard(url) }
                    return
                }
                self.arrived(read, item)
            }
        }
        // Its call back comes on the main thread after this, whatever
        // thread the load calls it on.
        if current?.read == read { current?.loading = loading }
    }

    /// The bound of the read numbered `read`, from now. Cancelled, it
    /// counts nothing out, even when it has already run its time and waits
    /// only for its turn on the main thread.
    private func timer(for read: Int) -> Task<Void, Never> {
        let limit = self.limit
        let sleep = self.sleep
        return Task { [weak self] in
            do { try await sleep(limit) } catch { return }
            guard !Task.isCancelled else { return }
            self?.countOut(read)
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
    ///
    /// And the read under way is called off and set aside (B-142): its row
    /// back at the head of the queue, still turning, nothing counted out
    /// and nothing said, to be begun again on his return (`back`). Its
    /// call back changes nothing then, unless it brings what it read
    /// (`cameSetAside`). Photos' copy of a video holds a file coordination
    /// claim on the app while it is made, and iOS ends an app that holds
    /// one in the background for more than about 30 seconds. A read that
    /// cannot be called off goes on, and nothing after it is begun.
    ///
    /// With a Send or a Save Draft waiting (`hurry`), the read under way is
    /// first let run `grace`, and set aside only if it has not come by
    /// then: a photo a second or two from coming goes in, and the letter
    /// with it, while he is away, as before B-142, and a long video is
    /// still called off well inside iOS's 30 seconds. A video's conversion
    /// AVFoundation stops in that time is set aside then
    /// (`interruptedAway`).
    func away() {
        guard !isAway else { return }
        isAway = true
        hurryTimer?.cancel()
        hurryTimer = nil
        guard var now = current else { return }
        now.timer?.cancel()
        now.timer = nil
        current = now
        guard now.loading != nil else { return }
        guard hurried else { return putAsideCurrent("as the app went") }
        current?.grace = graceTimer(for: now.read)
        Diagnostics.log(.note, "COMPOSE-ITEM let run \(graceLimit.components.seconds) s as the app went, "
                        + "a Send or Save Draft waiting")
    }

    /// The read under way called off and set aside (`away`): its row back
    /// at the head of the queue, still turning, nothing counted out and
    /// nothing said, to be begun again on his return.
    private func putAsideCurrent(_ when: String) {
        guard let now = current, now.loading != nil else { return }
        now.callOff()
        current = nil
        setAside[now.read] = SetAside(id: now.id, pick: now.pick, tally: now.tally,
                                      staging: now.staging, loading: now.loading)
        queue.insert(Queued(id: now.id, pick: now.pick, item: now.item), at: 0)
        Diagnostics.log(.note, "COMPOSE-ITEM set aside \(when), called off")
        actions.readingChanged()
    }

    /// The `grace` of the read numbered `read`, from now: not come by its
    /// end, with the app still away, it is set aside.
    private func graceTimer(for read: Int) -> Task<Void, Never> {
        let grace = graceLimit
        let sleep = self.sleep
        return Task { [weak self] in
            do { try await sleep(grace) } catch { return }
            guard !Task.isCancelled, let self, self.isAway, self.current?.read == read else { return }
            self.putAsideCurrent("\(grace.components.seconds) s after the app went")
        }
    }

    /// The app is in front again: the one being read, and a wait already
    /// bounded, each have their bound again from now, one let run as the
    /// app went no longer set aside; and one set aside as the app went
    /// begun again, with a bound of its own from now (B-142).
    func back() {
        guard isAway else { return }
        isAway = false
        if var now = current {
            now.grace?.cancel()
            now.grace = nil
            if now.timer == nil { now.timer = timer(for: now.read) }
            current = now
        }
        if hurried, hurryTimer == nil { hurryTimer = hurryBound() }
        startNext()
    }

    /// The sheet is done with what is coming (`ComposeActions.whenClosed`):
    /// Delete Draft, a Cancel that asked nothing, the sheet put away, or a
    /// Send that has gone. The read under way is called off, a video's
    /// conversion with it (B-142), and nothing more is begun; nothing is
    /// said. A Save Draft is not this: it waits for what is coming after
    /// the sheet has gone.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        hurryTimer?.cancel()
        hurryTimer = nil
        queue = []
        guard let now = current else { return }
        now.callOff()
        current = nil
        late[now.read] = "the letter closed"
        if now.loading != nil {
            Diagnostics.log(.note, "COMPOSE-ITEM called off, the letter closed")
        }
    }

    /// The staged file of `item`, where it is one.
    nonisolated static func file(_ item: SharedItem?) -> URL? {
        guard case .file(let url, _, _, _)? = item else { return nil }
        return url
    }

    private func arrived(_ read: Int, _ item: SharedItem?) {
        if let aside = setAside.removeValue(forKey: read) { return cameSetAside(aside, item) }
        if isAway, let now = current, now.read == read, now.loading?.wasInterrupted == true {
            return interruptedAway(now, item)
        }
        guard let now = current, now.read == read else {
            // Counted out at its bound, and come after all, having ended
            // before it could be called off: not in the letter, which he
            // has been told, nor left on the disk. Or let go as the letter
            // closed, or as an earlier read of its row brought it.
            let after = late.removeValue(forKey: read) ?? "its bound"
            if let url = Self.file(item) {
                discard(url)
                Diagnostics.log(.note, "COMPOSE-ITEM came after \(after), thrown away")
            }
            return
        }
        now.timer?.cancel()
        now.grace?.cancel()
        current = nil
        unnamed = now.staging.unnamed
        var attached = false
        if case let .file(url, filename, mimeType, size)? = item {
            landed(url, DraftAttachment(source: .localFile(url), filename: filename,
                                        mimeType: mimeType, size: size))
            attached = true
        }
        count(now.tally, attached: attached, into: now.pick)
        settle([(now.id, now.pick)])
    }

    /// A video whose conversion stopped as the app went (B-142), with a
    /// Send or a Save Draft waiting, in its `grace`: an app gives up its
    /// encoder in the background, and AVFoundation stops the conversion
    /// (`ShareItems.compatible`). It is set aside as the grace would have
    /// set it aside, its row back at the head of the queue, still
    /// turning, nothing counted out and nothing said, and read again from
    /// the start on his return, made H.264 then; the original it brought
    /// is thrown away. In front, a conversion stopped goes as its original,
    /// as one that failed does, and is not read again.
    private func interruptedAway(_ now: Current, _ item: SharedItem?) {
        now.timer?.cancel()
        now.grace?.cancel()
        current = nil
        if let url = Self.file(item) { discard(url) }
        queue.insert(Queued(id: now.id, pick: now.pick, item: now.item), at: 0)
        Diagnostics.log(.note, "COMPOSE-ITEM set aside, its conversion stopped as the app went")
        actions.readingChanged()
    }

    /// The call back of a read set aside as the app went (`away`). With
    /// nothing, as a read called off calls back, nothing changes: its row
    /// waits at the head of the queue, still turning, and is read again on
    /// his return, or is being read again already; it did not come after
    /// a bound, and is not counted. With what it read, ended before it
    /// could be called off, that goes in as it would have, counted as this
    /// read counted it, and its row is done with: taken from the queue, or,
    /// being read again already, that read called off, since this brings
    /// the row, a read of which may not come again. A row done with
    /// meanwhile, counted out, ended by a later read or the letter closed,
    /// takes nothing more: this copy is thrown away, and the log says why.
    /// Nor does a video whose conversion stopped as the app went, which
    /// brings its original (B-142): thrown away, its row read again.
    private func cameSetAside(_ aside: SetAside, _ item: SharedItem?) {
        guard case let .file(url, filename, mimeType, size)? = item else {
            Diagnostics.log(.note, "COMPOSE-ITEM set aside, its read ended with nothing")
            return
        }
        // A video whose conversion stopped as the app went brings its
        // original, not what it was read for: thrown away, and its row,
        // waiting or read again already, made H.264 on his return (B-142).
        guard aside.loading?.wasInterrupted != true else {
            discard(url)
            Diagnostics.log(.note, "COMPOSE-ITEM set aside, its conversion stopped as the app went, "
                            + "thrown away")
            return
        }
        if let index = queue.firstIndex(where: { $0.id == aside.id }) {
            queue.remove(at: index)
            Diagnostics.log(.note, "COMPOSE-ITEM set aside and come all the same")
        } else if let now = current, now.id == aside.id {
            now.callOff()
            current = nil
            late[now.read] = "an earlier read of it came"
            Diagnostics.log(.note, "COMPOSE-ITEM set aside and come while it was read again, "
                            + "taken, the read again called off")
        } else {
            discard(url)
            let why = isClosed ? "the letter closed"
                : countedOut.contains(aside.id) ? "it was counted out"
                : "its row was done with"
            Diagnostics.log(.note, "COMPOSE-ITEM set aside and come after \(why), thrown away")
            return
        }
        unnamed = aside.staging.unnamed
        landed(url, DraftAttachment(source: .localFile(url), filename: filename,
                                    mimeType: mimeType, size: size))
        count(aside.tally, attached: true, into: aside.pick)
        settle([(aside.id, aside.pick)])
    }

    /// Not in at its bound: counted out, its read called off, a video's
    /// conversion with it (B-142), and the next begun.
    private func countOut(_ read: Int) {
        guard let now = current, now.read == read else { return }
        now.callOff()
        current = nil
        countedOut.insert(now.id)
        Diagnostics.log(.note, "COMPOSE-ITEM counted out after \(limit.components.seconds) s")
        count(now.tally, attached: false, into: now.pick)
        settle([(now.id, now.pick)])
    }

    /// A Send's or a Save Draft's bound has passed (`hurry`): the one being
    /// read, its read called off as at its own bound, and every one waiting
    /// its turn counted out at once, those not begun as what they are
    /// (`Item.kind`), and said together, once.
    private func countOutAll() {
        hurryTimer = nil
        var out: [(Int, Pick)] = []
        if let now = current {
            now.callOff()
            current = nil
            countedOut.insert(now.id)
            count(now.tally, attached: false, into: now.pick)
            out.append((now.id, now.pick))
        }
        for waiting in queue {
            countedOut.insert(waiting.id)
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
        // Read where it is, at once, and not called off: nil for its read
        // (`away`, B-142). Moved out of the Inbox, it could not be read
        // again.
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
            return nil
        }
    }
}
