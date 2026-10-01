import Foundation

/// A start that leaves behind what earlier launches read, after launches in
/// a row that never finished (B-057).
///
/// Once on his iPad the app is never updated, so a crash at every launch
/// would end it for good. The only way out would be deleting it, which
/// takes the letters kept only on the iPad (B-051) with it and cannot be
/// undone on a sideload. What can crash every launch is what is read
/// before the first frame and in the seconds after it: the copy of his mail
/// (D-016), the view settings, and the letters kept on the iPad, which the
/// automatic pass takes about a second after the first page.
///
/// Every launch is counted in a file of its own, before anything kept is
/// read, and counted as finished in either of two ways: the app goes to the
/// background, or it is plainly working, half a minute after the first page
/// has been drawn and the first pass over the letters kept on the iPad has
/// ended (`firstPageTried`). He often opens the app, glances and leaves
/// within seconds, and that always sends it to the background, so it never
/// counts against the next launch. A crash, or iOS's watchdog ending an app
/// that does not answer, never does: the count is left standing.
///
/// What the next launch does is read from that count, the launches before
/// it in a row that never finished, and each step includes the ones before:
///
/// - 2: the copy of his mail is thrown away (`MailShelf.wipe`), as it can
///   be at any time, being only ever what the server last said (D-016), so
///   no kept page is drawn; and the view settings go back to their
///   defaults (`viewSettings`).
/// - 3: no automatic pass over the letters kept on the iPad in this launch.
///   His own Send and Save Draft go as ever.
/// - 5: the letters kept on the iPad are moved, folder and all, to a dated
///   folder beside it (`LocalDraftStore.setAside`), and the app starts with
///   none. Never deleted: it may be the only copy of what he wrote.
///
/// Each step is said in the connection log, with nothing of a letter, and
/// written down beside the count (`taken(in:)`), for a screen that can one
/// day show it. Every launch also removes the folders of letters whose first
/// keep never got as far as its `letter.json` (`LocalDraftStore.
/// removeLeftovers`).
///
/// A file and not `UserDefaults`: a write there reaches the preferences
/// daemon some time later, and a crash before it lands loses it, which here
/// is the very write that matters. Nothing here can itself stop a launch: a
/// count that cannot be read is no count, and one that cannot be written is
/// a launch the guard does not see.
@MainActor
final class SafeStart {

    /// What a launch does, from how many launches before it, in a row,
    /// never finished.
    struct Steps: Equatable {
        /// The copy of his mail thrown away and the view settings reset.
        var forgetsKeptState = false
        /// No automatic pass over the letters kept on the iPad.
        var holdsPasses = false
        /// The letters kept on the iPad moved aside.
        var setsLettersAside = false

        init(after unfinished: Int) {
            forgetsKeptState = unfinished >= SafeStart.forgetsKeptStateAfter
            holdsPasses = unfinished >= SafeStart.holdsPassesAfter
            setsLettersAside = unfinished >= SafeStart.setsLettersAsideAfter
        }
    }

    nonisolated static let forgetsKeptStateAfter = 2
    nonisolated static let holdsPassesAfter = 3
    nonisolated static let setsLettersAsideAfter = 5

    /// How long the app has to have been working, after its first page and
    /// first pass, for the launch to count as finished: long enough for a
    /// fault in what they drew or took to have shown itself, short enough
    /// that a launch he stays in has finished well before he leaves it.
    nonisolated static let healthyAfter: Duration = .seconds(30)

    /// A safe start, as the file beside the count keeps it.
    struct Taken: Codable, Equatable {
        /// When the launch took the steps.
        var at: Date
        /// The launches before it, in a row, that never finished.
        var unfinished: Int
        /// The steps, in order: `keptCopyWiped`, `viewSettingsReset`,
        /// `passesHeld`, `lettersSetAside`.
        var steps: [String]
        /// The name of the folder the letters were moved to, beside `Local
        /// Drafts` in Application Support, when they were.
        var setAside: String?
    }

    nonisolated static let keptCopyWiped = "kept-copy-wiped"
    nonisolated static let viewSettingsReset = "view-settings-reset"
    nonisolated static let passesHeld = "passes-held"
    nonisolated static let lettersSetAside = "letters-set-aside"

    /// The view settings read before the first frame, by their keys in
    /// `UserDefaults`: two panes or three (D-015), Organize by Thread, Go to
    /// Date's last scope and day, and the layout sweep, which runs at
    /// launch when on. The last three are written by screens that do not
    /// exist on the host; the suite holds these to the keys in their source.
    ///
    /// Not the account, the address book or the signature's pictures, which
    /// are his and are handed to the share extension: those are nothing a
    /// layout can trip on, and none of them can be had back once gone.
    nonisolated static let viewSettings = [
        PaneArrangement.key,
        ConversationSettings.key,
        "blackmail.lastJumpScope",
        "blackmail.lastJumpDate",
        "blackmail.layoutAudit",
    ]

    /// The app's: `Application Support/Launches/`, beside the copy of his
    /// mail and the letters kept on the iPad, over the same `UserDefaults`
    /// the screens read.
    static let app = SafeStart(directory: appDirectory, kept: MailShelf.appRoot,
                               letters: LocalDraftStore.appRoot, defaults: .standard)

    nonisolated static var appDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Launches", isDirectory: true)
    }

    /// The count's file, in `directory`: the launches in a row that never
    /// finished, the one running now among them, in decimal.
    nonisolated static let countFile = "unfinished"
    /// The steps taken, beside it.
    nonisolated static let takenFile = "safe-starts.json"

    /// No more than this many safe starts are kept in `takenFile`.
    private nonisolated static let takenKept = 20
    /// A count above this was never written by a launch: read as none.
    private nonisolated static let mostUnfinished = 1_000

    let directory: URL
    private let kept: URL
    private let letters: URL
    private let defaults: UserDefaults
    private let now: () -> Date
    private let timeZone: TimeZone
    private let log: (String) -> Void
    private let wait: @Sendable (Duration) async throws -> Void

    /// What this launch did, as `launch` decided. Nothing until then.
    private(set) var steps = Steps(after: 0)
    /// The count as this launch last wrote it.
    private var count = 0
    /// Waits for the healthy point, once the first page has been tried.
    private var watching: Task<Void, Never>?

    /// `kept` is the copy of his mail, `Kept/`, and `letters` the store of
    /// letters kept on the iPad, `Local Drafts/`; the dated folder goes
    /// beside it, named in `timeZone`. `wait` stands in for the half minute
    /// to the healthy point, for a test.
    init(directory: URL, kept: URL, letters: URL, defaults: UserDefaults,
         now: @escaping () -> Date = { Date() },
         timeZone: TimeZone = .current,
         log: @escaping (String) -> Void = { Diagnostics.log(.note, $0) },
         wait: @escaping @Sendable (Duration) async throws -> Void
            = { try await Task.sleep(for: $0) }) {
        self.directory = directory
        self.kept = kept
        self.letters = letters
        self.defaults = defaults
        self.now = now
        self.timeZone = timeZone
        self.log = log
        self.wait = wait
    }

    // MARK: - At launch

    /// Counts this launch and takes the steps the launches before it call
    /// for. First thing in `didFinishLaunching`, before anything kept is read.
    @discardableResult
    func launch() -> Steps {
        let unfinished = Self.unfinished(in: directory)
        count = unfinished + 1
        write(count)
        let steps = Steps(after: unfinished)
        self.steps = steps
        if unfinished > 0 { log("SAFE-START unfinished=\(unfinished)") }

        var taken: [String] = []
        var setAside: String?
        if steps.forgetsKeptState {
            MailShelf.wipe(root: kept)
            log("SAFE-START kept-copy=wiped")
            taken.append(Self.keptCopyWiped)
            for key in Self.viewSettings { defaults.removeObject(forKey: key) }
            log("SAFE-START view-settings=reset")
            taken.append(Self.viewSettingsReset)
        }
        if steps.holdsPasses {
            log("SAFE-START automatic-pass=held")
            taken.append(Self.passesHeld)
        }
        if steps.setsLettersAside,
           let moved = LocalDraftStore.setAside(letters, at: now(), in: timeZone) {
            setAside = moved.lastPathComponent
            log("SAFE-START local-drafts=set-aside folder=\"\(moved.lastPathComponent)\"")
            taken.append(Self.lettersSetAside)
        }
        let removed = LocalDraftStore.removeLeftovers(in: letters)
        if removed > 0 { log("DRAFTS-LEFTOVERS removed=\(removed)") }

        if !taken.isEmpty {
            record(Taken(at: now(), unfinished: unfinished, steps: taken, setAside: setAside))
        }
        return steps
    }

    // MARK: - Finished

    /// The launch's first page has been drawn, as fetched or as kept, or
    /// could not be fetched; `passEnded` returns once the pass that page
    /// set off over the letters kept on the iPad has ended, at once when
    /// none is running. Half a minute after both, the launch has finished.
    /// Once a launch: the screens built again after a password saved in
    /// Settings tell it again, and it has been told.
    func firstPageTried(passEnded: @escaping @MainActor () async -> Void) {
        guard watching == nil else { return }
        let wait = self.wait
        watching = Task { [weak self] in
            await passEnded()
            do { try await wait(Self.healthyAfter) } catch { return }
            self?.finished()
        }
    }

    /// The launch has finished: the app has gone to the background, been
    /// ended while running, or been working for half a minute after its
    /// first page and pass. The count goes back to none.
    func finished() {
        guard count != 0, write(0) else { return }
        count = 0
    }

    // MARK: - The files

    /// The count in `directory`: none when there is no file, and when what
    /// is there is not a count a launch could have written, a file cut
    /// short or garbled or a directory in its place, which the launch
    /// reading it writes over.
    nonisolated static func unfinished(in directory: URL) -> Int {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(countFile)),
              let count = Int(String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)),
              (0...mostUnfinished).contains(count) else { return 0 }
        return count
    }

    /// The safe starts written down in `directory`, oldest first; none when
    /// the file is not there or cannot be read, and the next safe start
    /// writes it afresh.
    nonisolated static func taken(in directory: URL) -> [Taken] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(takenFile)),
              let file = try? decoder.decode(TakenFile.self, from: data),
              file.format == TakenFile.format else { return [] }
        return file.starts
    }

    /// Written whole or not at all. Returns whether it was.
    @discardableResult
    private func write(_ count: Int) -> Bool {
        let data = Data(String(count).utf8)
        let url = directory.appendingPathComponent(Self.countFile)
        let files = FileManager.default
        if !files.fileExists(atPath: directory.path) {
            try? files.createDirectory(at: directory, withIntermediateDirectories: true)
            Self.excludeFromBackup(directory)
        }
        if (try? data.write(to: url, options: .atomic)) != nil { return true }
        // Something that cannot be written over is in the file's place,
        // a directory left by a fault: it goes, once, and the count is
        // written again. Otherwise every launch after would read none.
        try? files.removeItem(at: url)
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    private func record(_ taken: Taken) {
        let starts = Array((Self.taken(in: directory) + [taken]).suffix(Self.takenKept))
        guard let data = try? Self.encoder.encode(TakenFile(format: TakenFile.format,
                                                            starts: starts)) else { return }
        try? data.write(to: directory.appendingPathComponent(Self.takenFile), options: .atomic)
    }

    private struct TakenFile: Codable {
        static let format = 1
        var format: Int
        var starts: [Taken]
    }

    /// Dates as text, so the file reads as it stands to whoever opens it.
    private nonisolated static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private nonisolated static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Not in his iCloud backup: a count restored onto another iPad, or
    /// onto this one later, would be a launch that never happened there.
    private nonisolated static func excludeFromBackup(_ url: URL) {
        #if os(iOS)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = url
        try? url.setResourceValues(values)
        #endif
    }
}
