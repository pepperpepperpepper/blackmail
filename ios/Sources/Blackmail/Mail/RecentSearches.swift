import Foundation

/// Mail's recent searches (B-105): "Before you begin typing, you may see
/// suggested recent searches", Apple's guide says, and Mail keeps the last
/// three he used, each for a week from its last use (`MUISearchRecentSuggester`
/// in iOS 18.6's MailUI: three at most, newest first, 604,800 seconds,
/// excluded from backup). Shown under the search field while it is focused
/// and empty (`SearchHeaderView`); a tap searches again.
///
/// A search is kept when he taps Search on the keyboard with words in the
/// field, and when he opens a letter from its results: what Mail itself
/// keeps one at could not be read, and those are the two that say he meant
/// it. Never at each keystroke.
///
/// A file of its own in Application Support, `Recent Searches.json`,
/// written whole or not at all, out of backup, and read leniently: a file
/// that cannot be read is no recent searches, never a fault. It goes with
/// the copy of his mail kept on the iPad, when a password is saved or the
/// account taken out (`CredentialStore`), and at a safe start's second
/// stage (`SafeStart`).
///
/// Nothing here touches the network or a letter, and none of it is shown
/// until he puts a finger in the field.
enum RecentSearches {

    /// One search, as kept.
    struct Entry: Codable, Equatable {
        var text: String
        var lastUsed: Date
    }

    /// Mail's `maxRecentCount`.
    static let most = 3

    /// Mail's week, from the last use (604,800 s). An entry is shown up to
    /// that age, and not after it.
    static let keptFor: TimeInterval = 7 * 24 * 60 * 60

    /// A search longer than this is not kept: a pasted paragraph, which a
    /// row could not show and he would not search again, and cutting it
    /// would keep a search he never made.
    static let longest = 200

    /// The words over the rows, Mail's.
    static let heading = "Recent Searches"

    /// What VoiceOver says for a row, a button.
    static func spoken(_ text: String) -> String { "Recent search, \(text)" }

    /// The app's: `Application Support/Recent Searches.json`.
    static var appFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Recent Searches.json")
    }

    // MARK: - The list

    /// A search's text as kept: trimmed, its runs of white space one space
    /// each, so a row is one line. The same words are searched either way
    /// (`SearchCriteria.words`).
    static func cleaned(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// `entries` as they stand at `now`: newest first, at most `most`, each
    /// once ignoring case, none older than `keptFor`, none empty or over
    /// `longest`.
    ///
    /// Newest is first in the list, as each use puts it there, and not by
    /// the date kept beside it: a clock moved back would otherwise put the
    /// search he has just made under older ones, and off the end of three.
    /// An entry the clock now puts in the future is kept, and goes a week
    /// after the clock passes it, or as three newer push it off. A clock
    /// moved back only keeps entries longer.
    static func current(_ entries: [Entry], at now: Date) -> [Entry] {
        var seen = Set<String>()
        var out: [Entry] = []
        for entry in entries where out.count < most {
            let text = cleaned(entry.text)
            guard !text.isEmpty, text.count <= longest,
                  now.timeIntervalSince(entry.lastUsed) <= keptFor,
                  seen.insert(text.lowercased()).inserted else { continue }
            out.append(Entry(text: text, lastUsed: entry.lastUsed))
        }
        return out
    }

    /// `entries` once `text` has been searched at `now`: it first, and the
    /// same words in any case further down gone, as `current` keeps the
    /// first of them. Blank, or over `longest`, it is not kept.
    static func noting(_ text: String, at now: Date, in entries: [Entry]) -> [Entry] {
        current([Entry(text: text, lastUsed: now)] + entries, at: now)
    }

    // MARK: - The file

    /// One read, write or wipe at a time, from any thread.
    private static let lock = NSLock()

    /// The recent searches kept in `file`, as they stand at `now`. None
    /// when there is no file, or one that cannot be read.
    static func load(from file: URL, at now: Date) -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return current(read(file), at: now)
    }

    /// Keeps `text` in `file` as the newest search, at `now`. Blank text,
    /// or text over `longest`, changes nothing. A write that fails, a full
    /// disk, loses the note and nothing else.
    static func note(_ text: String, at now: Date, in file: URL) {
        let text = cleaned(text)
        guard !text.isEmpty, text.count <= longest else { return }
        lock.lock()
        defer { lock.unlock() }
        let after = noting(text, at: now, in: read(file))
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(after).write(to: file, options: .atomic)
            excludeFromBackup(file)
        } catch {
            // Not kept; the searches before it stand.
        }
    }

    /// Takes the recent searches in `file` away.
    static func wipe(_ file: URL) {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: file)
    }

    private static func read(_ file: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: file),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    /// Set on the file after every write: an atomic write is a new file,
    /// and the old one's flag goes with it.
    private static func excludeFromBackup(_ url: URL) {
        #if os(iOS)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = url
        try? url.setResourceValues(values)
        #endif
    }
}
