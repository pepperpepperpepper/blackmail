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
/// A launch that ended during a try of the automatic pass at a letter is
/// charged to the letter and not to the count. The pass marks the try on
/// its way beside the count (`markTry`), and the letter has counted it
/// already (`LocalDraft.autoAttempts`): at three the pass passes it over.
/// Counted here as well, a letter that crashed the pass at every launch
/// took the launches to their second stage, the copy of his mail and the
/// view settings gone, before its own third try held it. The mark names
/// the letter and does nothing else, and the launch reads the count and the
/// mark and nothing more before it takes its steps. A crash elsewhere while
/// a try is on its way is charged to the letter too, and each letter
/// waiting can put the stages off by its three tries, no more: a letter
/// held is never tried, so never marked.
///
/// Letters set aside come back only when he asks, in Settings
/// (`bringBack`), and go by the pass as any other.
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
        /// The steps, in order: `chargedToLetter`, `keptCopyWiped`,
        /// `viewSettingsReset`, `passesHeld`, `lettersSetAside`; or
        /// `lettersBroughtBack` alone, for letters brought back in Settings.
        var steps: [String]
        /// The name of the folder the letters were moved to, beside `Local
        /// Drafts` in Application Support, when they were.
        var setAside: String?
        /// How many letters were brought back, when they were. Absent from
        /// every other start, so no new format.
        var broughtBack: Int? = nil
    }

    nonisolated static let chargedToLetter = "charged-to-letter"
    nonisolated static let keptCopyWiped = "kept-copy-wiped"
    nonisolated static let viewSettingsReset = "view-settings-reset"
    nonisolated static let passesHeld = "passes-held"
    nonisolated static let lettersSetAside = "letters-set-aside"
    nonisolated static let lettersBroughtBack = "letters-brought-back"

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
    /// The try of the automatic pass on its way, beside it: the key of the
    /// letter, and nothing else (`markTry`).
    nonisolated static let tryFile = "trying"

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
    /// The launches before this one, in a row, that never finished, as
    /// `launch` counted them.
    private var unfinishedBefore = 0
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
        // The count and the mark are all that is read before the steps:
        // nothing a letter holds, and nothing else beside them.
        var unfinished = Self.unfinished(in: directory)
        // The last launch that never finished ended during a try of the
        // pass at a letter, whose own count has it: not counted here too.
        // The mark is taken away before the count is written, so a launch
        // ended between the two counts the try against both, never against
        // neither. With no launch unfinished, the end came after the launch
        // had finished, which counts against no launch anyway.
        let charged = Self.takeTry(in: directory) && unfinished > 0
        if charged { unfinished -= 1 }
        count = unfinished + 1
        write(count)
        let steps = Steps(after: unfinished)
        self.steps = steps
        unfinishedBefore = unfinished

        var taken: [String] = []
        if charged {
            log("SAFE-START charged-to-letter")
            taken.append(Self.chargedToLetter)
        }
        if unfinished > 0 { log("SAFE-START unfinished=\(unfinished)") }
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

    // MARK: - Letters set aside

    /// How many letters a safe start has set aside beside the store, there
    /// to be brought back: what Settings' Bring Back Set-Aside Letters is
    /// shown for. Only the folders are looked at, never what is in a letter.
    var lettersSetAside: Int {
        LocalDraftStore.lettersSetAside(beside: letters)
    }

    /// Every letter set aside back in the store, in Drafts and the Outbox
    /// as it was, once he has asked in Settings (`LocalDraftStore.
    /// bringBack`); returns how many came back. Said in the connection log
    /// and written down beside the count, as a step is. It takes no step
    /// and leaves the count as it is: a letter brought back that crashes
    /// the pass is held by its own tries, and a launch that crashes on one
    /// is counted, as any is, until five set them aside again.
    @discardableResult
    func bringBack() -> Int {
        let brought = LocalDraftStore.bringBack(into: letters)
        log("SAFE-START brought-back=\(brought)")
        record(Taken(at: now(), unfinished: unfinishedBefore, steps: [Self.lettersBroughtBack],
                     setAside: nil, broughtBack: brought))
        return brought
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

    /// The try of the automatic pass at the letter kept as `key` is on its
    /// way: marked in `directory`, `Application Support/Launches`, written
    /// whole or not at all, just after the letter's own count has gone up
    /// (`LocalDrafts.countTry`), and taken away as the try ends or is taken
    /// back (`unmarkTry`). A launch that ends with it there is charged to
    /// the letter and not counted (`launch`). Returns whether it is on
    /// disk; one that is not leaves the launch counted as well, as before
    /// there was a mark.
    @discardableResult
    nonisolated static func markTry(_ key: String, in directory: URL) -> Bool {
        writeWhole(Data(key.utf8), to: tryFile, in: directory)
    }

    /// The try marked in `directory` has ended, or been taken back.
    nonisolated static func unmarkTry(in directory: URL) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(tryFile))
    }

    /// The key the mark in `directory` names: nil when there is none, and
    /// when what is there is not a key a try could have written, empty,
    /// garbled, a path, or a directory in its place.
    nonisolated static func markedTry(in directory: URL) -> String? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(tryFile)),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A key as the app makes one, a UUID, or as the tests name one:
        // letters, digits and hyphens.
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        guard (1...100).contains(key.count), key.allSatisfy(allowed.contains) else { return nil }
        return key
    }

    /// Whether a try was marked in `directory` as the last launch ended,
    /// taking the mark away, whatever is there. Only the mark is read,
    /// never the letter it names: nothing a letter holds is read before
    /// the steps are taken. A mark that cannot be taken away is not taken:
    /// left, every launch after would be charged to it, and the guard
    /// would see none.
    nonisolated static func takeTry(in directory: URL) -> Bool {
        let url = directory.appendingPathComponent(tryFile)
        let files = FileManager.default
        guard files.fileExists(atPath: url.path) else { return false }
        let marked = markedTry(in: directory) != nil
        return (try? files.removeItem(at: url)) != nil && marked
    }

    /// Written whole or not at all. Returns whether it was.
    @discardableResult
    private func write(_ count: Int) -> Bool {
        Self.writeWhole(Data(String(count).utf8), to: Self.countFile, in: directory)
    }

    /// `data` as the file `name` in `directory`, made if need be and out
    /// of his backup, written whole or not at all. Returns whether it was.
    private nonisolated static func writeWhole(_ data: Data, to name: String,
                                               in directory: URL) -> Bool {
        let url = directory.appendingPathComponent(name)
        let files = FileManager.default
        if !files.fileExists(atPath: directory.path) {
            try? files.createDirectory(at: directory, withIntermediateDirectories: true)
            excludeFromBackup(directory)
        }
        if (try? data.write(to: url, options: .atomic)) != nil { return true }
        // Something that cannot be written over is in the file's place,
        // a directory left by a fault: it goes, once, and the file is
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
