import Foundation

/// The letters he opened, kept on the iPad (D-016, phase 2, B-111): the
/// last 300 whose bodies came whole while the reading pane still wanted
/// them, at most 64 MB, so that with no connection he can open any of them
/// again, its pictures and its files with it, as Mail opens what it has
/// downloaded, and with one it opens at once, with nothing fetched.
///
/// Each is the bytes of `BODY.PEEK[]` exactly as the FETCH returned them,
/// one file a letter in `letters/`, named by its folder, UIDVALIDITY, UID
/// and Gmail message id (X-GM-MSGID) and by nothing it says, with an index
/// beside them, `letters.json`, in the account's directory of `Kept/`.
/// A letter is read back only under all four: RFC 3501 has the bytes under
/// one folder, UIDVALIDITY and UID never change, and the Gmail id is what
/// tells two mailboxes apart where every Inbox reports UIDVALIDITY 1
/// (B-033). Every read checks the file's size and CRC-32 against the
/// index, and a letter that fails is dropped and fetched again.
///
/// Only ever what the server last said. Nothing kept is ever sent, written
/// back or put in a letter: the repository reads it for the reading pane
/// and for the pictures and files the pane asks for, and nowhere else
/// (`IMAPMailRepository.keptLetter`, `keptPart`). A forward's parts are
/// fetched from the server when it goes.
///
/// Its life is the shelf's. Every write, read and removal goes on the
/// shelf's disk queue (`MailShelf.disk`), in order with the shelf's wipe
/// and discard; the shelf's wipe takes it with the rest of `Kept/`, and its
/// discard takes it first (`forget`). It holds no reference to the shelf,
/// only a test of the shelf's generation, so a shelf retired at a password
/// save is freed with its letters.
///
/// Nothing is read until it is first used, at a letter opened, kept or
/// gone, never before a launch's first frame, and never from the main
/// thread: only the repository's actor calls it. Its state is behind a
/// lock that is never held while the disk is worked on.
final class KeptLetters: @unchecked Sendable {

    /// How much is kept. The app's are D-016's.
    struct Bounds: Sendable {
        /// The most letters kept.
        var letters = 300
        /// The most bytes kept, all the letters together.
        var bytes = 64 << 20
        /// The largest letter kept: the size above which the app opens a
        /// letter in parts (`IMAPMailRepository.largeLetterBytes`, B-054),
        /// so a kept letter is never more than a whole fetch decodes, and
        /// inside D-016's 8 MB.
        var letter = IMAPMailRepository.largeLetterBytes
        /// The most bytes of keeps waiting for the disk; one past it is
        /// dropped.
        var waiting = 16 << 20
        /// The free space the iPad keeps: a letter that would leave less
        /// is not kept, the kept letters all go, and nothing more is kept
        /// in that launch.
        var floor: Int64 = 512 << 20
        /// How long a reading of the free space answers for (B-136): read
        /// at the first keep of a launch, and again at the first keep after
        /// this long, after the clock has gone back past the reading, or
        /// after a write that failed.
        var freeAge: TimeInterval = 5 * 60
        /// The room above the floor a held reading must show, less every
        /// letter kept since it and the letter now, to answer for a keep
        /// (B-136). A write large beside the room the reading left reads
        /// again first, so near the floor every keep reads, as every keep
        /// did; with gigabytes free, no letter here is large.
        var freeRoom: Int64 = 1 << 30

        init() {}
    }

    /// What the shelf makes it with. The app's are the shelf's disk queue,
    /// D-016's bounds and the iPad's free space; a test hands in its own.
    struct Options: Sendable {
        var bounds = Bounds()
        /// The bytes free on the volume, nil where it cannot be read, which
        /// keeps. Nil here for the app's own reading of the iPad.
        var freeSpace: (@Sendable () -> Int64?)?
        /// Nil for the shelf's own.
        var disk: DispatchQueue?
        /// Called on the disk queue once a keep's two files are written and
        /// before its index goes into memory, for a test that has something
        /// come between the two.
        var afterFiles: (@Sendable () -> Void)?
        /// The time, for how old the free-space reading is. Nil for the
        /// clock.
        var now: (@Sendable () -> Date)?

        init() {}
    }

    /// Bumped only for a change an older build could misread, apart from
    /// `MailShelf.format`. A file of any other format is thrown away.
    static let format = 1

    static let indexFile = "letters.json"
    static let filesDirectory = "letters"

    /// `Kept/`, the account's directory under it, and `letters/` under that.
    let root: URL
    let directory: URL
    let files: URL
    private var indexURL: URL { directory.appendingPathComponent(Self.indexFile) }

    private let disk: DispatchQueue
    private let alive: @Sendable () -> Bool
    private let bounds: Bounds
    private let freeSpace: @Sendable () -> Int64?
    private let afterFiles: (@Sendable () -> Void)?
    private let now: @Sendable () -> Date

    private let lock = NSLock()
    /// What is kept, as `letters.json` says, once it has been read.
    private var index: [Record] = []
    /// The next opening's number: bumped by each keep and each showing,
    /// never the clock, so a clock set back reorders nothing.
    private var next = 0
    private var loaded = false
    /// Bumped by `forget`, so a keep or a read on its way at that moment
    /// puts nothing back.
    private var epoch = 0
    /// The index has changed since it was last written.
    private var changed = false
    private var writeQueued = false
    /// Bytes of keeps waiting for the disk.
    private var waiting = 0
    /// The floor has been met in this launch: nothing more is kept.
    private var full = false
    /// The last reading of the free space (B-136): what it said, nil where
    /// it could not be read, when, and the bytes of letters written since.
    /// Read and written on the disk queue alone, by `store`, which lets it
    /// go when a write fails.
    private var reading: (free: Int64?, at: Date, since: Int64)?

    /// Made by the shelf over its own directory, touching nothing on disk.
    /// `alive` is the shelf's generation test, made from its root and
    /// generation alone.
    init(root: URL, directory: URL, disk: DispatchQueue,
         alive: @escaping @Sendable () -> Bool, options: Options = Options()) {
        self.root = root
        self.directory = directory
        files = directory.appendingPathComponent(Self.filesDirectory, isDirectory: true)
        self.disk = options.disk ?? disk
        self.alive = alive
        bounds = options.bounds
        freeSpace = options.freeSpace ?? Self.freeSpace(near: root)
        afterFiles = options.afterFiles
        now = options.now ?? { Date() }
    }

    // MARK: - Reading

    /// The letter kept under these four, checked, or nil. `touch` counts an
    /// opening, which makes it the newest. A letter whose file is missing,
    /// or whose size or CRC-32 is not its record's, goes, file and record,
    /// and nil is returned, so the opening goes to the server as it would
    /// have, and keeps it again.
    ///
    /// The lookup and the read are one block on the disk queue, so no keep
    /// or eviction comes between them.
    func letter(in folder: String, validity: UInt32, uid: UInt32, message: UInt64,
                touch: Bool) -> Data? {
        guard alive() else { return nil }
        return disk.sync { () -> Data? in
            guard alive() else { return nil }
            loadIfNeeded()
            let (found, epoch) = locked {
                (index.first { $0.matches(folder, validity, uid, message) }, self.epoch)
            }
            guard let found else { return nil }
            let raw = try? Data(contentsOf: files.appendingPathComponent(found.file))
            guard let raw, raw.count == found.bytes, Self.crc(raw) == found.crc else {
                drop([found], epoch: epoch)
                Diagnostics.log(.note, "KEPT-LETTER dropped reason=check")
                return nil
            }
            if touch {
                locked {
                    guard self.epoch == epoch,
                          let i = index.firstIndex(where: { $0.matches(folder, validity, uid, message) })
                    else { return }
                    index[i].opened = next
                    next += 1
                    changed = true
                    queueWrite()
                }
            }
            return raw
        }
    }

    // MARK: - Keeping

    /// Keeps `raw`, a letter fetched whole under these four, on the disk
    /// queue, a moment from now. Not when it is over `Bounds.letter`, when
    /// `Bounds.waiting` would be passed, or once the floor has been met in
    /// this launch. A letter kept already under the same four is only
    /// touched. The floor is met from the free space as last read, read
    /// again when that cannot answer (`spaceFree(before:)`, B-136).
    ///
    /// Its file is written, then the index with it and the letters it
    /// evicts, each atomically, and only then does memory take the index,
    /// unless the copy was thrown away meanwhile (`forget`); then the
    /// evicted files go. An index that cannot be written takes the new file
    /// back, so the index on disk names only files written whole.
    func keep(_ raw: Data, in folder: String, validity: UInt32, uid: UInt32, message: UInt64) {
        let count = raw.count
        guard alive(), count > 0, count <= bounds.letter else { return }
        enum Turn { case none, past, taken(epoch: Int) }
        let turn: Turn = locked {
            guard !full else { return .none }
            guard waiting + count <= bounds.waiting else { return .past }
            waiting += count
            return .taken(epoch: epoch)
        }
        guard case .taken(let epoch) = turn else {
            if case .past = turn { Diagnostics.log(.note, "KEPT-LETTER not-kept reason=waiting") }
            return
        }
        disk.async { [self] in
            defer { locked { waiting -= count } }
            store(raw, in: folder, validity: validity, uid: uid, message: message, epoch: epoch)
        }
    }

    /// On the disk queue.
    private func store(_ raw: Data, in folder: String, validity: UInt32, uid: UInt32,
                       message: UInt64, epoch: Int) {
        let started = DispatchTime.now().uptimeNanoseconds
        guard alive() else { return }
        loadIfNeeded()
        let now: (records: [Record], next: Int)? = locked {
            guard self.epoch == epoch, !full else { return nil }
            if let i = index.firstIndex(where: { $0.matches(folder, validity, uid, message) }) {
                index[i].opened = next
                next += 1
                changed = true
                queueWrite()
                return nil
            }
            return (index, next)
        }
        guard let now else { return }

        // The floor, before anything is written, from the free space as
        // last read (`spaceFree(before:)`, B-136). On the test iPad the
        // reading took 44 to 58 ms of each 62 to 85 ms keep, and on the
        // shared disk queue a page read from the main thread waits behind
        // it as well as behind the write; so it is timed on its own for the
        // note when it is taken, and taken only when the reading held
        // cannot answer.
        let size = Int64(raw.count)
        let (free, freeMS) = spaceFree(before: size)
        if let free, free - size < bounds.floor {
            clear(epoch: epoch)
            return
        }

        let record = Record(folder: folder, validity: validity, uid: uid, message: message,
                            bytes: raw.count, crc: Self.crc(raw), opened: now.next,
                            file: Self.fileName(folder, validity, uid, message))
        var records = now.records
        records.append(record)
        let evicted = Self.evict(&records, within: bounds)
        let written = Index(format: Self.format, next: now.next + 1, letters: records)

        let manager = FileManager.default
        let file = files.appendingPathComponent(record.file)
        do {
            try makeDirectories()
            try raw.write(to: file, options: .atomic)
        } catch {
            // A disk that is full: nothing kept, and the index as it was.
            // The reading held said there was room, and the disk says
            // otherwise: it is let go, so the next keep reads the free
            // space again and, if it is down to the floor, clears the
            // letters (B-136).
            reading = nil
            Diagnostics.log(.note, "KEPT-LETTER not-kept reason=disk")
            return
        }
        do {
            try JSONEncoder().encode(written).write(to: indexURL, options: .atomic)
        } catch {
            try? manager.removeItem(at: file)
            reading = nil
            Diagnostics.log(.note, "KEPT-LETTER not-kept reason=disk")
            return
        }
        reading?.since += size
        afterFiles?()
        // A discard may have come while the files were written; its removal
        // of the directory comes after this block, and takes them.
        let taken: Bool = locked {
            guard alive(), self.epoch == epoch else { return false }
            index = records
            next = now.next + 1
            changed = false
            return true
        }
        guard taken else { return }
        for gone in evicted {
            try? manager.removeItem(at: files.appendingPathComponent(gone.file))
        }
        let ms = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        Diagnostics.log(.note, "KEPT-LETTER kept bytes=\(raw.count) ms=\(ms)"
                        + (freeMS.map { " free-ms=\($0)" } ?? ""))
    }

    /// On the disk queue: the bytes free before a letter of `size` is
    /// written, and the ms the reading took, nil when none was taken
    /// (B-136).
    ///
    /// The reading held answers, less every letter written since it, when
    /// it is under `Bounds.freeAge` old, the clock has not gone back past
    /// it, and it shows at least `Bounds.freeRoom` above the floor after
    /// this letter; a reading that could not be read answers as it did, by
    /// keeping, for as long. Otherwise the free space is read now, and
    /// that reading is held. So it is read at the first keep of a launch,
    /// at the first after five minutes, and before every keep near the
    /// floor, as it was before every keep. A held reading answers only
    /// with a gigabyte to spare above the floor, and for five minutes at
    /// most, so for a keep to land under the floor the iPad's other apps
    /// would have to take that gigabyte within those minutes, and the
    /// letters could then go under it by no more than the store can still
    /// grow, at most its 64 MB. A disk they fill makes the write fail,
    /// keeping nothing, and the reading goes with it (`store`): the next
    /// keep reads the free space and, under the floor, clears the letters,
    /// where before the keep that met the full disk had read it first and
    /// cleared them itself.
    private func spaceFree(before size: Int64) -> (free: Int64?, ms: UInt64?) {
        let time = now()
        if let held = reading, held.at <= time, time.timeIntervalSince(held.at) < bounds.freeAge {
            guard let free = held.free else { return (nil, nil) }
            let left = free - held.since
            if left - size >= bounds.floor + bounds.freeRoom { return (left, nil) }
        }
        let started = DispatchTime.now().uptimeNanoseconds
        let free = freeSpace()
        let ms = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        reading = (free, time, 0)
        return (free, ms)
    }

    /// The least recently opened, out of `records`, until there are at most
    /// `bounds.letters` and `bounds.bytes` with the newest, which stays.
    private static func evict(_ records: inout [Record], within bounds: Bounds) -> [Record] {
        records.sort { $0.opened < $1.opened }
        var total = records.reduce(0) { $0 + $1.bytes }
        var evicted: [Record] = []
        while records.count > 1, records.count > bounds.letters || total > bounds.bytes {
            let oldest = records.removeFirst()
            total -= oldest.bytes
            evicted.append(oldest)
        }
        return evicted
    }

    /// Below the floor: every letter goes, giving the iPad back up to 64 MB,
    /// said once, and nothing more is kept in this launch, so a store near
    /// the floor is not filled and emptied again at every letter.
    private func clear(epoch: Int) {
        let manager = FileManager.default
        let cleared: Bool = locked {
            full = true
            guard self.epoch == epoch else { return false }
            index = []
            changed = false
            return true
        }
        guard cleared else { return }
        try? manager.removeItem(at: files)
        try? manager.removeItem(at: indexURL)
        Diagnostics.log(.note, "KEPT-LETTER cleared reason=space")
    }

    // MARK: - What the server has taken away

    /// The server has taken the letter under `uid` out of `folder`, whatever
    /// Gmail id it was kept with.
    func gone(uid: UInt32, validity: UInt32, in folder: String) {
        remove { $0.folder == folder && $0.validity == validity && $0.uid == uid }
    }

    /// The letter Gmail knows as `message` has left every folder but
    /// `destination`: binned, or marked as spam.
    func gone(message: UInt64, everyFolderBut destination: String) {
        remove { $0.message == message && $0.folder != destination }
    }

    /// The server has said the UID is not the letter `message` (`MailShelf.refuse`).
    func refused(uid: UInt32, validity: UInt32, in folder: String, message: UInt64) {
        remove { $0.matches(folder, validity, uid, message) }
    }

    /// Memory first, then the files, then the index behind them: a crash
    /// between leaves an index naming a file that is not there, which the
    /// next launch's first use drops.
    private func remove(_ which: @escaping @Sendable (Record) -> Bool) {
        guard alive() else { return }
        let epoch = locked { self.epoch }
        disk.async { [self] in
            guard alive() else { return }
            loadIfNeeded()
            let gone: [Record] = locked {
                guard self.epoch == epoch else { return [] }
                let out = index.filter(which)
                guard !out.isEmpty else { return [] }
                index.removeAll(where: which)
                changed = true
                queueWrite()
                return out
            }
            for record in gone {
                try? FileManager.default.removeItem(at: files.appendingPathComponent(record.file))
            }
        }
    }

    /// On the disk queue: `records` out of memory and off the disk.
    private func drop(_ records: [Record], epoch: Int) {
        let dropped: Bool = locked {
            guard self.epoch == epoch else { return false }
            let files = Set(records.map(\.file))
            index.removeAll { files.contains($0.file) }
            changed = true
            queueWrite()
            return true
        }
        guard dropped else { return }
        for record in records {
            try? FileManager.default.removeItem(at: files.appendingPathComponent(record.file))
        }
    }

    // MARK: - The whole store

    /// The copy was not this mailbox's (`MailShelf.discardEverything`):
    /// nothing is kept in memory from now, and a keep or a read on its way
    /// puts nothing back. The shelf removes the directory after this, on
    /// the disk queue.
    func forget() {
        locked {
            epoch += 1
            index = []
            loaded = true
            changed = false
        }
    }

    /// Writes the index now, if it has changed: as the app goes into the
    /// background (`MailShelf.flush`).
    func flush() {
        disk.sync { writeIndex() }
    }

    /// A write a moment from now, unless one is waiting. Called with the
    /// lock held.
    private func queueWrite() {
        guard !writeQueued else { return }
        writeQueued = true
        disk.async { [self] in writeIndex() }
    }

    /// On the disk queue.
    private func writeIndex() {
        let (snapshot, epoch): (Index?, Int) = locked {
            writeQueued = false
            guard changed else { return (nil, self.epoch) }
            changed = false
            return (Index(format: Self.format, next: next, letters: index), self.epoch)
        }
        guard let snapshot, alive() else { return }
        do {
            try makeDirectories()
            try JSONEncoder().encode(snapshot).write(to: indexURL, options: .atomic)
        } catch {
            // The last index written whole stays; the next change, or the
            // next flush, writes it again.
            locked { if self.epoch == epoch { changed = true } }
        }
    }

    /// On the disk queue, at the first use in a launch: the index read,
    /// every file in `letters/` no record names removed (a crash between a
    /// letter's file and its record, an atomic write's leftover, an
    /// eviction cut short), and every record whose file is missing dropped.
    /// An index of another format, or one that cannot be read, is nothing
    /// kept, and goes with every letter.
    private func loadIfNeeded() {
        let (done, epoch) = locked { (loaded, self.epoch) }
        guard !done, alive() else { return }
        let manager = FileManager.default
        var records: [Record] = []
        var next = 0
        var dirty = false
        if manager.fileExists(atPath: indexURL.path) {
            if let data = try? Data(contentsOf: indexURL), let read = Self.decode(data) {
                records = read.letters
                next = read.next
            } else {
                try? manager.removeItem(at: indexURL)
                try? manager.removeItem(at: files)
            }
        }
        // Within the rules: each file named as its keys name it, so a record
        // can reach no file but its own; one record for one letter.
        var seen: Set<String> = []
        let before = records.count
        records = records.sorted { $0.opened > $1.opened }.filter { record in
            guard record.bytes > 0, record.bytes <= bounds.letter,
                  record.file == Self.fileName(record.folder, record.validity, record.uid,
                                               record.message),
                  seen.insert(record.file).inserted else { return false }
            return true
        }
        let present = Set((try? manager.contentsOfDirectory(atPath: files.path)) ?? [])
        records = records.filter { present.contains($0.file) }
        // Within the bounds, which a file put there by hand can be past;
        // what goes is swept with the files no record names.
        _ = Self.evict(&records, within: bounds)
        if records.count != before { dirty = true }
        let named = Set(records.map(\.file))
        for name in present where !named.contains(name) {
            try? manager.removeItem(at: files.appendingPathComponent(name))
        }
        next = max(next, (records.map(\.opened).max() ?? -1) + 1)
        locked {
            guard self.epoch == epoch, !loaded else { return }
            index = records
            self.next = next
            loaded = true
            if dirty {
                changed = true
                queueWrite()
            }
        }
    }

    /// `Kept/`, the account's directory and `letters/`, each made where it
    /// is not there and marked out of backup as it is made, by the helper
    /// the shelf's own writes use: `letters.json`, in the account's
    /// directory, is never in a backup whichever store wrote first, nor
    /// after a discard or a wipe has just removed the directories.
    private func makeDirectories() throws {
        let manager = FileManager.default
        for url in [root, directory, files] where !manager.fileExists(atPath: url.path) {
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
            MailShelf.excludeFromBackup(url)
        }
    }

    // MARK: - For the suite

    /// What is kept, oldest opened first, as the next read would find it.
    var records: [Record] {
        disk.sync {
            loadIfNeeded()
            return locked { index.sorted { $0.opened < $1.opened } }
        }
    }

    /// Bytes of keeps waiting for the disk.
    var waitingBytes: Int { locked { waiting } }

    /// How many times the copy has been thrown away.
    var epochNow: Int { locked { epoch } }

    // MARK: - Names and checks

    /// "<hash of the folder>-<validity>-<uid>-<message>.eml": ASCII, one a
    /// letter, and saying nothing of it.
    static func fileName(_ folder: String, _ validity: UInt32, _ uid: UInt32,
                         _ message: UInt64) -> String {
        "\(MailShelf.hash(folder))-\(validity)-\(uid)-\(message).eml"
    }

    static func crc(_ data: Data) -> UInt32 {
        var crc = CRC32()
        crc.update(data)
        return crc.value
    }

    private static func decode(_ data: Data) -> Index? {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data), header.format == format,
              let index = try? decoder.decode(Index.self, from: data) else { return nil }
        return index
    }

    /// The bytes free for what the app keeps, on the volume `Kept/` is on,
    /// as iOS reckons them for what can wait; nil where that cannot be
    /// read, and off iOS.
    ///
    /// Each reading makes its URLs afresh from the path. A URL keeps the
    /// resource values it has read until its thread's run loop turns, and
    /// the disk queue has none, so one URL held from reading to reading
    /// could give the first reading again for the rest of the launch.
    static func freeSpace(near root: URL) -> @Sendable () -> Int64? {
        #if os(iOS)
        let path = root.path
        return {
            let kept = URL(fileURLWithPath: path, isDirectory: true)
            for url in [kept, kept.deletingLastPathComponent(),
                        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)] {
                if let values = try? url.resourceValues(
                    forKeys: [.volumeAvailableCapacityForOpportunisticUsageKey]),
                   let free = values.volumeAvailableCapacityForOpportunisticUsage {
                    return free
                }
            }
            return nil
        }
        #else
        return { nil }
        #endif
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: - The format

    private struct Header: Decodable {
        let format: Int
    }

    private struct Index: Codable {
        var format: Int
        var next: Int
        var letters: [Record]
    }

    /// One letter, field by field: the file's shape changes only when this
    /// does.
    struct Record: Codable, Equatable, Sendable {
        var folder: String
        var validity: UInt32
        var uid: UInt32
        var message: UInt64
        var bytes: Int
        var crc: UInt32
        var opened: Int
        var file: String

        func matches(_ folder: String, _ validity: UInt32, _ uid: UInt32, _ message: UInt64) -> Bool {
            self.folder == folder && self.validity == validity && self.uid == uid
                && self.message == message
        }
    }
}
