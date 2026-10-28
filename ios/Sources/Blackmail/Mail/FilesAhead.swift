import Foundation

/// A large letter's files fetched as it opens, as Mail fetches them
/// (B-176).
///
/// Mail on the test iPad, iPadOS 16.5.1, opening a letter of about 7 MB
/// with two photos and a PDF (round r6-i-compare, C-13e, 2026-10-27):
/// it fetched the files by itself, no tap; while a file came its tile had
/// a ring and said "Downloading" (Mail's `DOWNLOADING_STATUS`), and then
/// the file was drawn. No "Tap to Download" was seen. Blackmail opens a
/// letter above `IMAPMailRepository.largeLetterBytes` without its files
/// (B-054), and its tiles said "Tap to Download" until he tapped one
/// (`Message.filesLeftOnServer`, B-170); its pictures already came as the
/// page asked for them (`InlineImageLoader`).
///
/// Now, as such a letter's page or its body in a stack has loaded, the pane
/// fetches each of its files that is drawn as a tile (`planned`), one at a
/// time, by its section, as a tap fetches it. Its tile says "Downloading"
/// with a ring where its icon is from the start (`BodyFiles.tile`), and
/// once it has come its icon is back and its last line says nothing, as a
/// letter's tile does whose files came with it (`BodyFiles.Landed`); or,
/// where it could not be fetched, "Tap to Download", and a tap fetches it.
/// What came is written to the iPad, out of memory, and a tap opens it from
/// there at once. All of it stops, and what came is removed, when the pane
/// is given anything else (`PaneLoads.supersede`).
///
/// Mail's own limit for this was not found. A file larger than a letter
/// the app fetches whole (`most`) still waits for a tap and says "Tap to
/// Download": no file comes unasked that a letter that size would not
/// have brought. The 3.5 MB photo and the 309 KB PDF Mail fetched
/// unasked are both under it.
///
/// Pure, so the suite can run it; the fetching and the page are the
/// pane's (`MessageDetailViewController`).
struct FilesAhead: Equatable {

    /// The largest file fetched unasked: a letter's size the app fetches
    /// whole (`IMAPMailRepository.largeLetterBytes`, B-054), by the size
    /// the server gives for the part.
    static let most = Int64(IMAPMailRepository.largeLetterBytes)

    /// Whether `file` of `m` is fetched as the letter opens: a file of a
    /// letter opened without its files, drawn as a tile, no picture, which
    /// comes as the page asks for it, of a size the server gave and no
    /// larger than `most`.
    static func fetches(_ file: Attachment, of m: Message) -> Bool {
        guard m.filesLeftOnServer, !BodyFiles.isPicture(file), let size = file.size else { return false }
        return size >= 0 && size <= most
    }

    /// The files of `m` fetched as it opens, in the letter's order: those
    /// its page draws as tiles (`BodyFiles.drawn`'s, every file of a body
    /// shown whole and those it lists of one shown in part) that
    /// `fetches` takes.
    static func planned(_ m: Message) -> [Attachment] {
        guard m.filesLeftOnServer else { return [] }
        let drawn = m.isShortened ? m.listedAttachments : m.attachments
        var seen = Set<String>()
        return drawn.filter { fetches($0, of: m) && seen.insert($0.id).inserted }
    }

    /// A file by its letter and its part.
    struct Key: Hashable {
        let letter: String
        let part: String
    }

    /// Where a file planned stands.
    enum State: Equatable {
        /// Its turn not come.
        case waiting
        /// On its way, fetched as the letter opened or for a tap.
        case coming
        /// Come, and written to the iPad at `URL`.
        case landed(URL)
        /// Not fetched: its tile says "Tap to Download".
        case failed
    }

    private(set) var states: [Key: State] = [:]

    /// What the pane does for a file planned as its body has been drawn,
    /// again or for the first time.
    enum Drawn: Equatable {
        /// Fetch it, in its turn.
        case fetch
        /// Its tile as it has come, or as it could not be: what was drawn
        /// says "Downloading", which is no longer so.
        case show(inHand: Bool)
        /// Nothing: it is on its way, and its tile says so.
        case nothing
    }

    /// `key`'s body drawn: a file never asked for is fetched in its turn.
    mutating func drawn(_ key: Key) -> Drawn {
        switch states[key] {
        case nil:
            states[key] = .waiting
            return .fetch
        case .waiting?, .coming?:
            return .nothing
        case .landed?:
            return .show(inHand: true)
        case .failed?:
            return .show(inHand: false)
        }
    }

    /// `key`'s turn has come: true to fetch it now, false when a tap has
    /// taken it, or the pane has let it go.
    mutating func turn(_ key: Key) -> Bool {
        guard states[key] == .waiting else { return false }
        states[key] = .coming
        return true
    }

    /// What a tap on `key` does with it.
    enum Taking: Equatable {
        /// Opens what came, at `URL`.
        case read(URL)
        /// Waits for it, coming as the letter opened.
        case wait
        /// Fetches it, and keeps what comes as having come when it is a
        /// file planned (`lands`), as if it had come in its turn.
        case fetch(lands: Bool)
    }

    /// A tap on `key`: a file come is read, one on its way waited for, one
    /// whose turn has not come or that could not be fetched is fetched now
    /// and kept as come, and any other file fetched as ever.
    mutating func taking(_ key: Key) -> Taking {
        switch states[key] {
        case let .landed(url)?:
            return .read(url)
        case .coming?:
            return .wait
        case .waiting?, .failed?:
            states[key] = .coming
            return .fetch(lands: true)
        case nil:
            return .fetch(lands: false)
        }
    }

    /// `key` has come and been written at `url`, or nil where it could not
    /// be written: failed. False for a file forgotten meanwhile, whose
    /// copy is then to be removed.
    mutating func landed(_ key: Key, at url: URL?) -> Bool {
        guard states[key] != nil else { return false }
        states[key] = url.map(State.landed) ?? .failed
        return true
    }

    /// `key` could not be fetched.
    mutating func failed(_ key: Key) {
        guard states[key] != nil else { return }
        states[key] = .failed
    }

    /// The pane given something else: everything forgotten, and the files
    /// that came handed back to be removed.
    mutating func forget() -> [URL] {
        let urls = states.values.compactMap { state -> URL? in
            if case let .landed(url) = state { return url }
            return nil
        }
        states = [:]
        return urls.sorted { $0.path < $1.path }
    }
}
