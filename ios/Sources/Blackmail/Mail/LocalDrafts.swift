import Foundation

/// A letter kept on the iPad: a draft he saved that the server has not yet
/// taken, or the letter he is writing as it stood a few seconds ago.
///
/// Save Draft used to go straight to the server after the sheet had closed,
/// and with no connection the letter was simply gone: the sheet had closed,
/// nothing said so, and nothing had been kept anywhere. Nor was a letter
/// being written kept anywhere until Save Draft or Send, so iOS ending the
/// app while he wrote lost all of it. Mail keeps a draft on the device and
/// puts it in Drafts when it can; this now does the same, and for the letter
/// being written as well (B-051).
///
/// Alongside D-016's copy of his mail, not inside it: its own directory,
/// which that copy's wipe and eviction never touch. That copy is only ever
/// what the server last said and can be thrown away; this is the one place
/// a letter exists before the server has it.
struct LocalDraft {
    /// Which letter this is, however many times it is kept. Made when the
    /// composer opens on a new letter or on a draft from the server, and
    /// carried by a letter reopened from here, so one letter is one entry.
    let key: String
    /// The letter. Its photos are files of this entry, never the composer's
    /// staged copies, which `AttachmentStore.purge` deletes at every launch.
    var draft: Draft
    /// This version of the letter, made afresh each time it is kept. It goes
    /// to the server under a Message-ID made from this (`DraftUpload`).
    var version: String
    /// The versions whose APPEND has gone, or was about to, and which may
    /// therefore be on the server already, from an upload cut off after the
    /// server had it. Written just before the APPEND, so an app ended
    /// mid-upload still knows to look.
    var tried: [String]
    /// Kept while he was still writing it, by autosave, rather than by Save
    /// Draft.
    var unfinished: Bool
    /// When it was last kept: the date its row in Drafts shows.
    var keptAt: Date
    /// The address of the account it was written in, nil if none was known.
    /// It goes to that account's Drafts and no other's.
    var account: String?
    /// Sent or deleted after an upload of it may have reached the server:
    /// its words and files have gone, and only `tried` is left, to find and
    /// remove the copies those uploads left in Drafts.
    var gone: Bool
    /// In the Outbox, to go under this Message-ID: Send could not reach the
    /// server (B-052). Nil for a draft, and for a letter taken back into the
    /// composer. Made when the letter enters the Outbox and handed to the
    /// builder at every attempt, so each is the same message.
    var outbox: String? = nil
    /// The Message-IDs of attempts whose DATA went and whose 250 never came
    /// back, which may therefore have reached Gmail. Written just before
    /// DATA, so an app ended mid-send still knows to look, and kept, whatever
    /// becomes of the letter, until Sent Mail has been asked
    /// (`LocalDrafts.send`). A letter with any is not taken to Drafts until
    /// then either (`LocalDrafts.upload`).
    var unsettled: [String] = []
    /// When the latest of those attempts was last known to be on its way:
    /// as its DATA was about to go, and again when it was cut off. Sent
    /// Mail's not having it counts only once `Outbox.settling` has passed
    /// since (`LocalDraftStore.isSettling`).
    var cutOff: Date? = nil
    /// The size of its quote's markup (B-050), which goes with it to
    /// Drafts, in bytes. Known from `letter.json` whether or not the markup
    /// itself was read (`LocalDraftStore.letters`).
    var markupBytes = 0
    /// How many times a password had been saved on the iPad, as the launch
    /// that last kept it found the count (`LocalDraftStore.passwordSaves`);
    /// 0 for a letter kept by a build before the count was kept. Fewer
    /// than now, and a password has been saved since it was kept: what it
    /// names on the server by folder and UID alone may be in another
    /// mailbox under the same address (B-033).
    var passwordSaves = 0
    /// The same count as the launch that wrote down the latest attempt
    /// found it (`LocalDraftStore.noteSending`); 0 for one written down by
    /// a build before this was kept. Fewer than now, and Sent Mail, asked
    /// whether an `unsettled` attempt reached Gmail, may be another
    /// mailbox's (`LocalDraftStore.unsettledBeforeASave`).
    var unsettledSaves = 0

    /// Where it stands in the Outbox: nil for a letter that is not there.
    var outboxState: OutboxState? {
        outbox.map { unsettled.contains($0) ? .beingSent : .waiting }
    }

    enum OutboxState: Equatable {
        /// Not yet sent as far as DATA: it goes as it is.
        case waiting
        /// Its DATA went and no 250 came back: Sent Mail is asked before it
        /// goes again.
        case beingSent
    }
}

extension LocalDraft {

    /// How a row in Drafts says which of its letters are kept here.
    private static let rowPrefix = "local:"

    /// The first line of such a row's preview. No mark of Mail's for a draft
    /// not yet on the server was found to copy, so this is a plain one, in
    /// words, where the preview's first line would be.
    static let mark = "On this iPad only"

    /// Its row in Drafts, above the drafts on the server. Its id and thread
    /// can never be a server letter's, so it is never grouped with one: a
    /// tap has to open this letter and not whichever was newest in a stack.
    ///
    /// `notice` is why the last try did not take it to the server, when it
    /// is one he can do something about (`LocalDrafts.whyNotSent`), under
    /// the mark: a file it carries from a letter that cannot be found.
    func row(in mailboxID: String, from sender: String,
             notice: MailError? = nil) -> MessageSummary {
        let text = PreviewText.fromPlainText(draft.body)
        let lines = [Self.mark, notice?.errorDescription, text.isEmpty ? nil : text]
        return row(Self.rowPrefix + key, in: mailboxID, from: sender,
                   preview: lines.compactMap { $0 }.joined(separator: "\n"))
    }

    /// The row of the copy it became on the server, `id`, drawn from the
    /// letter as it went until Drafts is next fetched: in place of its row
    /// here, without fetching the folder again for it. A thread of its own
    /// until then, as Gmail's is not known.
    func row(in mailboxID: String, from sender: String, onServerAs id: String) -> MessageSummary {
        row(id, in: mailboxID, from: sender, preview: PreviewText.fromPlainText(draft.body))
    }

    private func row(_ id: String, in mailboxID: String, from sender: String,
                     preview: String) -> MessageSummary {
        MessageSummary(id: id,
                       mailboxID: mailboxID,
                       sender: sender,
                       subject: draft.subject,
                       preview: preview,
                       date: keptAt,
                       isRead: true,
                       isFlagged: false,
                       hasAttachment: !draft.attachments.isEmpty,
                       threadID: id)
    }

    /// The letter a row in Drafts stands for, when it is one kept here.
    static func key(ofRow id: String) -> String? {
        guard id.hasPrefix(rowPrefix) else { return nil }
        return String(id.dropFirst(rowPrefix.count))
    }

    /// Big enough that an upload nobody asked for waits (`LocalDrafts.
    /// uploadWaiting`): files of a megabyte or more between them, the size
    /// from which a letter takes a while to go (`ComposeActions.countsFrom`),
    /// or a file whose size is not known. The quote's markup counts with
    /// them: it goes in the APPEND too, and a newsletter's is a megabyte.
    var isLarge: Bool {
        let markup = max(markupBytes, draft.quote?.html?.utf8.count ?? 0)
        return Self.isLarge(draft.attachments.map(\.size) + [Int64(markup)])
    }

    /// The same for a letter in the Outbox, which goes to the submission
    /// server over a connection of its own, so its own photos hold nothing
    /// he taps. What does is a forward's files, or a reopened draft's,
    /// fetched from Gmail over the one IMAP connection before the letter can
    /// be built: a megabyte or more of those, or one of unknown size, waits
    /// for him to leave the app, as a large draft does.
    ///
    /// Those rows are all it fetches. A forward's quoted pictures that go
    /// are only ones that are also its rows, each fetched once, in the
    /// quote rather than as a file (`AppleMailHTML.letter`); counted again
    /// beside the rows, a forward of 600 kB of photographs was held back
    /// as 1.2 MB, and one whose pictures he had taken off as more than it
    /// sent.
    var fetchesLarge: Bool {
        var sizes: [Int64?] = []
        for file in draft.attachments {
            if case .messagePart = file.source { sizes.append(file.size) }
        }
        return Self.isLarge(sizes)
    }

    private static func isLarge(_ sizes: [Int64?]) -> Bool {
        var total: Int64 = 0
        for size in sizes {
            guard let size else { return true }
            total += size
        }
        return total >= Int64(ComposeActions.countsFrom)
    }
}

extension Draft {

    /// No subject, no words and no files: nothing worth keeping. The
    /// signature alone is not nothing; a letter emptied by hand is.
    var isEmptyLetter: Bool {
        subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && attachments.isEmpty
    }

    /// Whether it names anything on the server by folder and UID alone,
    /// with no Gmail id to tell that it is still that letter: the copy it
    /// was reopened from, a forward's or a reopened draft's file, or a
    /// picture of its quote. So kept from a server without Gmail's
    /// extension, or by a build before the ids were kept.
    var namesByUIDAlone: Bool {
        (savedID != nil && savedLetter == nil)
            || attachments.contains { $0.isPartByUIDAlone }
            || (quote?.pictures.contains { $0.letter == nil } ?? false)
    }

    /// The letter without what it names by folder and UID alone
    /// (`namesByUIDAlone`), as a letter of another account opens
    /// (`LocalDrafts.letter`): no copy to replace, those files left out,
    /// and a quote with such a picture gone, as without the picture its
    /// markup would show a broken box.
    var forgettingWhatItNamesByUIDAlone: Draft {
        var draft = self
        if savedLetter == nil { draft.savedID = nil }
        draft.attachments.removeAll { $0.isPartByUIDAlone }
        if quote?.pictures.contains(where: { $0.letter == nil }) == true { draft.quote = nil }
        return draft
    }
}

extension DraftAttachment {

    /// A part of a letter on the server named with no Gmail id.
    var isPartByUIDAlone: Bool {
        if case .messagePart(_, _, _, nil) = source { return true }
        return false
    }
}

// MARK: - On disk

/// Where kept letters live: one directory per letter under `root`, holding
/// `letter.json`, the letter's photos, and the markup its quote carries,
/// `quote.html`.
///
/// JSON rather than a database, as D-016 chose for the copy of his mail and
/// for the same reasons: nothing here is queried, a letter is read whole and
/// replaced whole, and it runs in the host suite as it is. The JSON is
/// written atomically and after the files it names, so a letter on disk
/// never names a photo that is not there. One that cannot be read, cut off
/// or of a format this build does not know, is passed over, never deleted
/// and never allowed to stop a launch: it may be the only copy of a letter.
///
/// Used only on the main thread. A letter's JSON is a few kilobytes and its
/// photos are linked, not copied, so keeping one costs about what writing
/// the address book does. The quote's markup is a file of its own for the
/// same reason: a newsletter's is a megabyte, and inside the JSON it was
/// decoded and encoded again, 25 ms on the host, by every write of the
/// letter's state, the one between RCPT and DATA included, and decoded by
/// every list that counts the Outbox. It is written when the letter is
/// kept and read only when the letter is opened or goes (`letter(_:)`).
@MainActor
final class LocalDraftStore {

    let root: URL
    private let now: () -> Date
    private let files = FileManager.default

    /// The file in each letter's directory that says what the letter is.
    private static let letterFile = "letter.json"
    /// The quote's markup, beside it. A photo's file is named by a UUID, so
    /// never this.
    private static let markupFile = "quote.html"
    /// Bumped only for a change an older build could misread. A file of any
    /// other format is passed over.
    private static let format = 1
    /// How many times a password has been saved, beside the letters and
    /// never one of them: a name no letter's directory has.
    private nonisolated static let savesFile = "password-saves"

    /// How many times a password has been saved on this iPad, as the
    /// repository in use found it (`notePasswordSaved`). Every letter kept
    /// now is stamped with it (`LocalDraft.passwordSaves`). Read as the
    /// store is made, and again only as a new repository takes the place
    /// of the old one after a password saved in Settings
    /// (`LocalDrafts.passwordSaved`): a letter kept between the save and
    /// that moment names what it names in the old password's mailbox.
    private(set) var passwordSaves: Int

    init(root: URL, now: @escaping () -> Date = { Date() }) {
        self.root = root
        self.now = now
        passwordSaves = Self.passwordSaves(in: root)
    }

    /// The app's: Application Support, never Caches or tmp, which iOS may
    /// empty whenever it likes. Not under D-016's `Kept/` either, which is
    /// thrown away whenever a password is saved.
    nonisolated static var appRoot: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Local Drafts", isDirectory: true)
    }

    // MARK: A password saved

    /// A password has been saved, in setup or Settings
    /// (`CredentialStore.save`): the count goes up, and the letters kept
    /// before it are known for such once a repository signs in with it, at
    /// the next launch or at once after Settings (`savedSince`,
    /// `LocalDrafts.passwordSaved`). Nothing of the letters themselves is
    /// touched: they may be the only copy of what he wrote.
    ///
    /// Why a count and not the time of the save: a clock set back would
    /// make a letter kept before the save look kept after it. A count
    /// cannot run backwards, and a letter kept by a build before the count
    /// was kept reads as kept before any save.
    nonisolated static func notePasswordSaved(in root: URL) {
        let files = FileManager.default
        if !files.fileExists(atPath: root.path) {
            try? files.createDirectory(at: root, withIntermediateDirectories: true)
            excludeFromBackup(root)
        }
        let count = passwordSaves(in: root) + 1
        try? Data(String(count).utf8).write(to: root.appendingPathComponent(savesFile),
                                            options: .atomic)
    }

    /// The count `notePasswordSaved` keeps: 0 when no password has been
    /// saved since this build began keeping it. A file there that cannot be
    /// read is at least one save, since only a save writes it.
    nonisolated static func passwordSaves(in root: URL) -> Int {
        let url = root.appendingPathComponent(savesFile)
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        guard let data = try? Data(contentsOf: url),
              let count = Int(String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 else { return 1 }
        return count
    }

    /// The count of saves read again, as a new repository signs in with a
    /// password saved in Settings (`LocalDrafts.passwordSaved`).
    func readPasswordSaves() {
        passwordSaves = Self.passwordSaves(in: root)
    }

    /// Whether a password has been saved since `letter` was kept, so that
    /// what it names by folder and UID alone may be another mailbox's.
    func savedSince(_ letter: LocalDraft) -> Bool {
        letter.passwordSaves < passwordSaves
    }

    /// Whether an attempt at `letter` that may have reached Gmail, its DATA
    /// gone and no 250 back, was made before a password was saved since.
    /// Sent Mail, asked for it now, is the new password's, and that can be
    /// another mailbox under the same address (B-033): the attempt is not
    /// there to be found, is taken for one Gmail never had, and the letter
    /// goes again. By when the attempt was written down, not when the
    /// letter was kept: a letter sent offline before a save and cut off by
    /// the first pass after it was cut off under the new password.
    func unsettledBeforeASave(_ letter: LocalDraft) -> Bool {
        !letter.unsettled.isEmpty && letter.unsettledSaves < passwordSaves
    }

    // MARK: Reading

    /// Every letter that can be read, newest first, for a list: each
    /// without its quote's markup, which only `letter(_:)` reads. Nothing
    /// is kept or sent from one of these.
    func letters() -> [LocalDraft] {
        let keys = (try? files.contentsOfDirectory(atPath: root.path)) ?? []
        return keys.compactMap { key in
            stored(key).map { $0.letter(in: folder(for: key), markup: nil) }
        }.sorted { $0.keptAt > $1.keptAt }
    }

    /// The letter kept as `key`, whole, or nil when there is none, or none
    /// that can be read. A quote whose markup cannot be read goes without
    /// it, as the plain words he saw, rather than losing the letter.
    func letter(_ key: String) -> LocalDraft? {
        guard let stored = stored(key) else { return nil }
        let folder = folder(for: key)
        var markup: String?
        if stored.quote?.markup != nil,
           let data = try? Data(contentsOf: folder.appendingPathComponent(Self.markupFile)) {
            markup = String(decoding: data, as: UTF8.self)
        }
        return stored.letter(in: folder, markup: markup)
    }

    /// Whether the latest attempt at `letter` that was cut off after its
    /// DATA is too recent for Sent Mail's not having it to say that Gmail
    /// never took it (`Outbox.settling`). A time after now is not recent:
    /// the clock has been set back since, and how long ago the cut came is
    /// not known, and a letter held back until the clock caught up could
    /// wait a day.
    func isSettling(_ letter: LocalDraft) -> Bool {
        guard let cutOff = letter.cutOff else { return false }
        let age = now().timeIntervalSince(cutOff)
        return age >= 0 && age < Outbox.settling
    }

    // MARK: Writing

    /// Keeps `draft` as the letter `key`, written in `account`, in place of
    /// whatever version of it was kept before, as a new version. Its photos
    /// are linked into the letter's own directory, once each however often
    /// it is kept; the ones he has removed since go.
    ///
    /// A photo whose staged file has gone is left out rather than failing
    /// the whole letter. That cannot happen while the composer is open (the
    /// staging is emptied only at launch, and nothing takes a letter off the
    /// iPad while it is open), and if it ever did, the words matter more.
    @discardableResult
    func keep(_ draft: Draft, as key: String, unfinished: Bool,
              account: String?) throws -> LocalDraft {
        let folder = try makeFolder(for: key)
        let before = stored(key)
        var kept: [StoredFile] = []
        for attachment in draft.attachments {
            var file = StoredFile(filename: attachment.filename, mimeType: attachment.mimeType,
                                  size: attachment.size)
            switch attachment.source {
            case let .messagePart(messageID, mailboxID, section, original):
                file.messageID = messageID
                file.mailboxID = mailboxID
                file.section = section
                file.letter = original
            case let .localFile(url):
                guard let name = linked(url, into: folder, known: before?.files ?? []) else {
                    continue
                }
                file.name = name
                file.source = url.path
            }
            kept.append(file)
        }
        // Before the JSON that says it is there, as a photo is, and only
        // when it is not there already: a letter's quote is the same at
        // every autosave, and a megabyte written again at each pause cost it
        // several milliseconds for nothing.
        var names = kept.compactMap(\.name)
        if let markup = draft.quote?.html {
            let data = Data(markup.utf8)
            let file = folder.appendingPathComponent(Self.markupFile)
            if before?.quote?.markup != data.count || (try? Data(contentsOf: file)) != data {
                try data.write(to: file, options: .atomic)
            }
            names.append(Self.markupFile)
        }
        // Kept as a draft: out of the Outbox if it was there, which only a
        // composer that has it open can do. What may already have reached
        // Gmail is carried, to be looked for before it goes.
        var letter = Stored(format: Self.format, key: key,
                            version: UUID().uuidString.lowercased(),
                            tried: before?.tried ?? [], unfinished: unfinished, keptAt: now(),
                            account: account, draft: draft, files: kept)
        letter.unsettled = before?.unsettled
        letter.cutOff = before?.cutOff
        letter.unsettledSaves = before?.unsettledSaves
        letter.passwordSaves = passwordSaves
        try write(letter)
        removeFiles(in: folder, keeping: names)
        return letter.letter(in: folder, markup: draft.quote?.html)
    }

    /// Writes down that `version` of the letter is about to go to the
    /// server, before it can get there. Throws when the letter is no longer
    /// kept at all: sent or deleted meanwhile with no upload of it begun,
    /// so there is nothing to put in Drafts, and the upload must not go.
    func noteTried(_ key: String, _ version: String) throws {
        guard var letter = stored(key) else { throw NotKept() }
        guard !letter.tried.contains(version) else { return }
        letter.tried.append(version)
        try write(letter)
    }

    /// Puts the letter kept as `key` in the Outbox, under a Message-ID made
    /// now on its account's domain, as the builder makes one, and returns
    /// it. Throws when it is not kept.
    ///
    /// Sent again from the composer with an attempt still unsettled, it goes
    /// under that attempt's Message-ID rather than a new one. It is sent
    /// only once Sent Mail has been asked and has not got it; should that
    /// copy ever turn up after all, the two are then one message to every
    /// client that goes by Message-ID, Gmail's among them.
    func enterOutbox(_ key: String) throws -> String {
        guard var letter = stored(key), letter.gone != true else { throw NotKept() }
        let domain = letter.account?.split(separator: "@").last.map(String.init) ?? ""
        let messageID = letter.unsettled?.last
            ?? "<\(UUID().uuidString.lowercased())@\(domain.isEmpty ? "localhost" : domain)>"
        letter.outbox = messageID
        try write(letter)
        return messageID
    }

    /// Writes down that the attempt under `messageID` is about to send its
    /// DATA, before it can. Throws when the letter is no longer in the
    /// Outbox under it, deleted meanwhile, so the DATA must not go.
    func noteSending(_ key: String, _ messageID: String) throws {
        guard var letter = stored(key), letter.gone != true,
              letter.outbox == messageID else { throw NotKept() }
        // Which mailbox it goes to. Every earlier attempt has been found or
        // settled by now, since Sent Mail is asked before a letter goes
        // again (`LocalDrafts.deliver`), so this one is the only one.
        letter.unsettledSaves = passwordSaves
        if !(letter.unsettled ?? []).contains(messageID) {
            letter.unsettled = (letter.unsettled ?? []) + [messageID]
        }
        letter.cutOff = now()
        try write(letter)
    }

    /// The attempt on its way for the letter kept as `key` has been cut off
    /// before its 250: the time Sent Mail is given from (`isSettling`).
    func noteCutOff(_ key: String) {
        guard var letter = stored(key), !(letter.unsettled ?? []).isEmpty else { return }
        letter.cutOff = now()
        try? write(letter)
    }

    /// The attempts under `messageIDs` are known not to have reached Gmail:
    /// Sent Mail does not have them, or the server refused the letter.
    func settled(_ key: String, _ messageIDs: [String]) {
        guard var letter = stored(key), let before = letter.unsettled else { return }
        letter.unsettled = before.filter { !messageIDs.contains($0) }
        if letter.unsettled?.isEmpty == true { letter.cutOff = nil }
        try? write(letter)
    }

    /// Out of the Outbox and back to the composer, which has it open: its
    /// Send failed for a reason of its own, and the sheet stays with it.
    func takeBack(_ key: String) {
        guard var letter = stored(key), letter.outbox != nil else { return }
        letter.outbox = nil
        try? write(letter)
    }

    /// Sent or deleted with copies of it perhaps in Drafts: its words and
    /// files go, and what finds those copies stays (`LocalDraft.gone`).
    func markGone(_ key: String) throws {
        guard let before = stored(key) else { return }
        var gone = Stored(format: Self.format, key: key, version: before.version,
                          tried: before.tried, unfinished: false, keptAt: before.keptAt,
                          account: before.account, draft: Draft(), files: [])
        gone.gone = true
        try write(gone)
        removeFiles(in: folder(for: key), keeping: [])
    }

    /// Takes the letter off the iPad, files and all.
    func remove(_ key: String) {
        try? files.removeItem(at: folder(for: key))
    }

    /// Asked to note an upload of a letter that is no longer kept.
    struct NotKept: Error {}

    // MARK: Files

    private func folder(for key: String) -> URL {
        root.appendingPathComponent(key, isDirectory: true)
    }

    /// Everything in `folder` but the letter's file and `names`.
    private func removeFiles(in folder: URL, keeping names: [String]) {
        let wanted = Set(names + [Self.letterFile])
        for name in (try? files.contentsOfDirectory(atPath: folder.path)) ?? []
        where !wanted.contains(name) {
            try? files.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private func makeFolder(for key: String) throws -> URL {
        if !files.fileExists(atPath: root.path) {
            try files.createDirectory(at: root, withIntermediateDirectories: true)
            Self.excludeFromBackup(root)
        }
        let folder = folder(for: key)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Not in his iCloud backup, as D-016 has it for the copy of his mail:
    /// a restore should not bring back letters that went long ago.
    private nonisolated static func excludeFromBackup(_ url: URL) {
        #if os(iOS)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = url
        try? url.setResourceValues(values)
        #endif
    }

    /// The name, in `folder`, of the file at `url`: itself when it is one of
    /// this letter's already, the copy made of it before when there is one,
    /// or a new link to it. A hard link, so a photo of several megabytes
    /// costs nothing to keep, and survives the staged copy being deleted;
    /// copied if the two are ever on different volumes.
    private func linked(_ url: URL, into folder: URL, known: [StoredFile]) -> String? {
        if url.deletingLastPathComponent().standardizedFileURL.path
            == folder.standardizedFileURL.path {
            return files.fileExists(atPath: url.path) ? url.lastPathComponent : nil
        }
        if let name = known.first(where: { $0.source == url.path })?.name,
           files.fileExists(atPath: folder.appendingPathComponent(name).path) {
            return name
        }
        let name = UUID().uuidString.lowercased()
        let target = folder.appendingPathComponent(name)
        do {
            try files.linkItem(at: url, to: target)
        } catch {
            do { try files.copyItem(at: url, to: target) } catch { return nil }
        }
        return name
    }

    private func stored(_ key: String) -> Stored? {
        let url = folder(for: key).appendingPathComponent(Self.letterFile)
        guard let data = try? Data(contentsOf: url),
              let letter = try? JSONDecoder().decode(Stored.self, from: data),
              letter.format == Self.format, letter.key == key else { return nil }
        return letter
    }

    private func write(_ letter: Stored) throws {
        let data = try JSONEncoder().encode(letter)
        try data.write(to: folder(for: letter.key).appendingPathComponent(Self.letterFile),
                       options: .atomic)
    }

    // MARK: The format

    /// A letter as `letter.json` holds it. Spelled out field by field rather
    /// than by making `Draft` itself Codable, so the file's shape changes
    /// only when this does.
    private struct Stored: Codable {
        var format: Int
        var key: String
        var version: String
        var tried: [String]
        var unfinished: Bool
        var keptAt: Date
        var account: String?
        /// Only ever true, when present (`LocalDraft.gone`).
        var gone: Bool?
        /// `LocalDraft.outbox` and `unsettled`: absent from a letter kept
        /// before the Outbox, which reads as a draft with nothing to look
        /// for, so no new format.
        var outbox: String?
        var unsettled: [String]?
        /// `LocalDraft.cutOff`, absent when nothing is unsettled.
        var cutOff: Date?
        /// `LocalDraft.unsettledSaves`, absent until an attempt is written
        /// down, and from a letter whose attempts were written down before
        /// the count was, which reads as 0, so no new format.
        var unsettledSaves: Int?
        /// `LocalDraft.passwordSaves`, absent from a letter kept before the
        /// count was kept, which reads as 0, so no new format.
        var passwordSaves: Int?
        var to: [String]
        var cc: [String]
        var bcc: [String]
        var subject: String
        var body: String
        var inReplyTo: String?
        var references: String?
        var savedID: String?
        /// `Draft.savedLetter`: Gmail's id for the copy `savedID` names.
        /// Absent from a letter kept before the ids were, and from one whose
        /// server named none; so is `StoredFile.letter`, and
        /// `StoredPicture.letter`.
        var savedLetter: UInt64?
        /// The original a reply or forward quotes, so that one sent later
        /// from the Outbox, or taken to Drafts, carries its look as one
        /// sent at once does (B-050). Absent for a letter quoting nothing.
        /// Its markup is in `quote.html`.
        var quote: StoredQuote?
        var files: [StoredFile]

        init(format: Int, key: String, version: String, tried: [String], unfinished: Bool,
             keptAt: Date, account: String?, draft: Draft, files: [StoredFile]) {
            self.format = format
            self.key = key
            self.version = version
            self.tried = tried
            self.unfinished = unfinished
            self.keptAt = keptAt
            self.account = account
            to = draft.to
            cc = draft.cc
            bcc = draft.bcc
            subject = draft.subject
            body = draft.body
            inReplyTo = draft.inReplyTo
            references = draft.references
            savedID = draft.savedID
            savedLetter = draft.savedLetter
            quote = draft.quote.map(StoredQuote.init)
            self.files = files
        }

        /// The letter, its quote with `markup`, which is read from its own
        /// file by the caller that wants it.
        func letter(in folder: URL, markup: String?) -> LocalDraft {
            var draft = Draft()
            draft.to = to
            draft.cc = cc
            draft.bcc = bcc
            draft.subject = subject
            draft.body = body
            draft.inReplyTo = inReplyTo
            draft.references = references
            draft.savedID = savedID
            draft.savedLetter = savedLetter
            draft.quote = quote?.original(markup: markup)
            draft.attachments = files.compactMap { $0.attachment(in: folder) }
            return LocalDraft(key: key, draft: draft, version: version, tried: tried,
                              unfinished: unfinished, keptAt: keptAt, account: account,
                              gone: gone ?? false, outbox: outbox, unsettled: unsettled ?? [],
                              cutOff: cutOff, markupBytes: quote?.markup ?? 0,
                              passwordSaves: passwordSaves ?? 0,
                              unsettledSaves: unsettledSaves ?? 0)
        }
    }

    /// `QuotedOriginal`, field by field, for the reason `Stored` is, but
    /// for its markup, which is `quote.html` beside the letter.
    private struct StoredQuote: Codable {
        var forward: Bool
        var region: String
        /// The markup's size in bytes, nil when it has none.
        var markup: Int?
        var pictures: [StoredPicture]
        /// `QuotedOriginal.isShortened`. Only ever true, when present: absent
        /// from every other quote, and from one kept before it was, which
        /// reads as false, so no new format.
        var shortened: Bool?

        init(_ quote: QuotedOriginal) {
            forward = quote.kind == .forward
            region = quote.region
            markup = quote.html?.utf8.count
            pictures = quote.pictures.map(StoredPicture.init)
            shortened = quote.isShortened ? true : nil
        }

        func original(markup html: String?) -> QuotedOriginal {
            QuotedOriginal(kind: forward ? .forward : .reply, region: region, html: html,
                           pictures: pictures.map(\.picture), isShortened: shortened ?? false)
        }
    }

    private struct StoredPicture: Codable {
        var contentID: String
        var filename: String
        var mimeType: String
        var size: Int64?
        var messageID: String
        var mailboxID: String
        var section: String
        var letter: UInt64?

        init(_ picture: QuotedOriginal.Picture) {
            contentID = picture.contentID
            filename = picture.filename
            mimeType = picture.mimeType
            size = picture.size
            messageID = picture.messageID
            mailboxID = picture.mailboxID
            section = picture.section
            letter = picture.letter
        }

        var picture: QuotedOriginal.Picture {
            QuotedOriginal.Picture(contentID: contentID, filename: filename, mimeType: mimeType,
                                   size: size, messageID: messageID, mailboxID: mailboxID,
                                   section: section, letter: letter)
        }
    }

    /// One of a letter's files: a photo kept in its directory, or a part of
    /// a letter on the server, which a forward or a draft reopened from the
    /// server carries by name.
    private struct StoredFile: Codable {
        var filename: String
        var mimeType: String
        var size: Int64?
        /// Its name in the letter's directory.
        var name: String?
        /// Where it was linked from, so keeping the letter again does not
        /// link it again.
        var source: String?
        var messageID: String?
        var mailboxID: String?
        var section: String?
        var letter: UInt64?

        init(filename: String, mimeType: String, size: Int64?) {
            self.filename = filename
            self.mimeType = mimeType
            self.size = size
        }

        func attachment(in folder: URL) -> DraftAttachment? {
            let source: DraftAttachment.Source
            if let name {
                source = .localFile(folder.appendingPathComponent(name))
            } else if let messageID, let mailboxID, let section {
                source = .messagePart(messageID: messageID, mailboxID: mailboxID,
                                      section: section, letter: letter)
            } else {
                return nil
            }
            return DraftAttachment(source: source, filename: filename, mimeType: mimeType,
                                   size: size)
        }
    }
}

// MARK: - Keeping, and taking them to the server

/// The letters kept on the iPad, which of them the composer has open, and
/// taking the rest to the server: drafts to its Drafts, and the letters in
/// the Outbox to their recipients (B-052).
///
/// A letter goes up when he taps Save Draft, and one that could not go then
/// goes later, once, over a connection that is working: each time a
/// folder's newest page has just been fetched (at launch, at a Refresh, on
/// opening a folder, on coming back after a while), each time the app comes
/// back to the foreground, after each of the watch's checks that reaches
/// the server, and as he leaves it (`uploadWaiting`). One at a time, and
/// never one the composer has open, which is his to finish, nor one already
/// on its way. A letter whose Send could not reach the server waits in the
/// Outbox and goes by the same pass (`send`).
@MainActor
final class LocalDrafts {

    /// Posted on the main thread whenever the letters kept here change.
    /// With a `DraftLanding` in its user info, under `landingKey`, when
    /// something has just reached the server's Drafts or left it.
    static let changed = Notification.Name("LocalDrafts.changed")
    static let landingKey = "landing"

    let store: LocalDraftStore
    /// The address of the account the app is running as: the letters kept
    /// now are written in it, and only its own go to the server.
    let account: String?
    /// The time asked of iOS for a pass over the waiting letters.
    private let background: BackgroundTime

    /// Letters open in the composer, and whether each was kept here before
    /// it was opened.
    private var open: [String: Bool] = [:]
    /// Letters on their way to the server, or having their leftover copies
    /// removed, and what is waiting for each to be done.
    private var going: Set<String> = []
    private var waitingForGoing: [String: [CheckedContinuation<Void, Never>]] = [:]
    /// A pass over the waiting letters is running.
    private var passing = false
    /// Letters that reached the server while the composer had them open,
    /// by the version that did. See `closed`.
    private var landedOpen: [String: String] = [:]
    /// Letters a pass could not take to the server on a connection that
    /// was working, by the version that failed. Not tried again unasked
    /// until he changes them, the app is launched again, or a new password
    /// is saved (`passwordSaved`).
    private var refused: [String: String] = [:]
    /// Letters the server has taken since launch, and the id of the copy
    /// each became there, for a row in Drafts drawn before it went.
    private(set) var landed: [String: String] = [:]
    /// Why each letter in `refused` was not sent or taken to Drafts, where
    /// its row says so: the first line of its row in the Outbox, the line
    /// under the mark in Drafts. Set with `refused`, always (`refuse`).
    private var reasons: [String: MailError] = [:]
    /// A send met a refusal every letter would meet (`MailError.refusesSending`):
    /// the password, or the submission server's refused sign-in. Nothing
    /// more goes from the Outbox unasked until a Send of his own has gone,
    /// the app is launched again, or a new password is saved: each pass
    /// would send the refused sign-in again, as every page loads. Not for
    /// IMAP's LOGIN refused for another reason, which a letter waits out as
    /// it waits out no connection.
    private var sendingRefused = false

    init(store: LocalDraftStore, account: String?, background: BackgroundTime) {
        self.store = store
        self.account = account
        self.background = background
    }

    /// A new password has been saved in Settings and is signed in with now,
    /// by a new repository, rather than at the next launch
    /// (`PasswordChange`): what a launch would start afresh starts afresh.
    /// The count of saves is read again, so from here a letter kept before
    /// the save is known for such, as it would be after a relaunch
    /// (`LocalDraftStore.savedSince`), and the Outbox, stopped by the old
    /// password's refusal, and the letters refused since launch, are tried
    /// by the next pass. Nothing kept is touched, and a letter on its way,
    /// or open in the composer, stays so.
    func passwordSaved() {
        store.readPasswordSaves()
        sendingRefused = false
        refused = [:]
        reasons = [:]
        announce()
    }

    /// The letters Drafts lists above the server's: every one kept here but
    /// those open in the composer and those in the Outbox, newest first. A
    /// letter written in another account is listed with the rest, and goes
    /// nowhere until he opens it.
    var waiting: [LocalDraft] {
        store.letters().filter { open[$0.key] == nil && !$0.gone && $0.outbox == nil }
    }

    /// The letters in the Outbox, newest first, but the ones open in the
    /// composer: what the Outbox lists, and counts in the sidebar. One of
    /// another account is listed, and goes nowhere until he opens it and
    /// sends it.
    var outbox: [LocalDraft] {
        store.letters().filter { open[$0.key] == nil && !$0.gone && $0.outbox != nil }
    }

    /// The copies in Drafts that letters kept here stand in for, the drafts'
    /// and the Outbox's. A draft reopened from Drafts and sent with no
    /// connection is in the Outbox, and its old copy, still on the server,
    /// is not listed: tapped, it would open the letter to be sent a second
    /// time.
    ///
    /// Not a copy named by folder and UID alone across a password saved
    /// since the letter was kept (`LocalDraftStore.savedSince`): that UID
    /// may be another draft now, and the letter no longer names it.
    ///
    /// Each by its id, with Gmail's id for the letter the kept one names
    /// there (`Draft.savedLetter`), nil where it names none: a row the
    /// listing names another letter under is not its copy, and stays listed
    /// (`ListLetters.keep`). Kept from an earlier launch, the UID can hold
    /// another draft, in a Drafts renumbered under the same UIDVALIDITY or
    /// another mailbox under the same address, and hidden it could not be
    /// seen or opened for as long as the letter waited.
    var replacedInDrafts: [String: UInt64?] {
        var copies: [String: UInt64?] = [:]
        for letter in store.letters() where open[letter.key] == nil && !letter.gone {
            guard let id = letter.draft.savedID,
                  letter.draft.savedLetter != nil || !store.savedSince(letter) else { continue }
            copies.updateValue(letter.draft.savedLetter, forKey: id)
        }
        return copies
    }

    /// Drafts' rows for the letters kept here (`waiting`), each saying under
    /// its mark when the last try did not take it to the server because a
    /// file it carries from a letter cannot be found (`whyNotSent`), which
    /// he can take off. What the list draws, so the words a pass left are on
    /// the row he sees and not only in the model.
    ///
    /// That and nothing else. A letter a pass refused in the Outbox, taken
    /// back into the sheet by a Send that failed as it stood, and closed,
    /// is a draft still carrying the Outbox's refusal: its row said "This
    /// message is too big to send" under "On this iPad only", of a letter
    /// nobody was sending. The composer's Send keeps the letter as a new
    /// version first, which no pass has refused, so it stands as it stood
    /// only when that keep could not be written.
    func draftsRows(in mailboxID: String, from sender: String) -> [MessageSummary] {
        waiting.map {
            let missing = whyNotSent($0.key) == .attachmentsMissing
            return $0.row(in: mailboxID, from: sender, notice: missing ? .attachmentsMissing : nil)
        }
    }

    /// The Outbox's rows (`outbox`), each with "Sending…" while it goes, or
    /// why it has not gone: the reason a pass refused it for
    /// (`whyNotSent`), or, for a letter no pass takes because an attempt at
    /// it may have reached Gmail before a password was saved since
    /// (`LocalDraftStore.unsettledBeforeASave`), that it may already have
    /// gone. What the list draws.
    var outboxRows: [MessageSummary] {
        outbox.map {
            let reason = store.unsettledBeforeASave($0)
                ? Outbox.mayHaveGone : whyNotSent($0.key)?.errorDescription
            return $0.outboxRow(sending: isGoing($0.key), saying: reason)
        }
    }

    /// Whether the letter kept as `key` is on its way to the server now.
    /// A letter in the Outbox cannot be opened while it goes: sent while
    /// the composer had it, a Send there would send it again.
    func isGoing(_ key: String) -> Bool {
        going.contains(key)
    }

    /// Why the letter in the Outbox kept as `key` was not sent by the last
    /// pass that tried it, if it was refused for a reason of its own and is
    /// as it was then. Nil for one simply waiting. For a draft, only a file
    /// it carries from a letter that cannot be found
    /// (`MailError.attachmentsMissing`), which he can take off; its row
    /// says nothing of a draft's other refusals, as it never has.
    func whyNotSent(_ key: String) -> MailError? {
        guard let letter = store.letter(key), refused[key] == letter.version else { return nil }
        return reasons[key]
    }

    /// The letter kept as `key`, for the composer.
    ///
    /// One written in another account comes without the files it carries
    /// from letters on the server, a forward's or a reopened draft's. Those
    /// are named by folder and UID, which in this account can be another
    /// letter: Gmail gives every Inbox the same UIDVALIDITY (D-016).
    ///
    /// One of this account, kept before a password was saved since, comes
    /// without what it names by folder and UID alone, with no Gmail id to
    /// tell that it is still that letter (`Draft.namesByUIDAlone`): a new
    /// app password can open another mailbox under the same address
    /// (B-033), where those UIDs are other letters. What names its letter
    /// comes as it was; its id is what the repository goes by.
    func letter(_ key: String) -> LocalDraft? {
        guard var letter = store.letter(key), !letter.gone else { return nil }
        if !isMine(letter) {
            letter.draft.attachments.removeAll {
                if case .messagePart = $0.source { return true }
                return false
            }
            // The quote's pictures are named the same way. Without them its
            // markup would show broken boxes, so the letter goes plain.
            letter.draft.quote = nil
        } else if store.savedSince(letter) {
            letter.draft = letter.draft.forgettingWhatItNamesByUIDAlone
        }
        return letter
    }

    private func isMine(_ letter: LocalDraft) -> Bool {
        guard let theirs = letter.account, let account else { return false }
        return theirs.caseInsensitiveCompare(account) == .orderedSame
    }

    /// Whether a pass may take `letter` to the server as it is kept: a
    /// letter of this account that names nothing by folder and UID alone
    /// across a password saved since it was kept. One that does is another
    /// account's as far as those names go, and waits, listed, for him to
    /// open it, as another account's letter does: sent or taken to Drafts
    /// with them left out, a forward would go without its file and nothing
    /// would say so.
    private func goesFromHere(_ letter: LocalDraft) -> Bool {
        isMine(letter) && !(store.savedSince(letter) && letter.draft.namesByUIDAlone)
    }

    // MARK: The composer

    /// The composer has opened on letter `key`.
    func opened(_ key: String) {
        open[key] = store.letter(key) != nil
    }

    /// The composer on letter `key` has done with it. One that reached the
    /// server while it was open, and was not changed after, is on the
    /// server as it stands, and leaves the iPad now.
    func closed(_ key: String) {
        open[key] = nil
        if let version = landedOpen.removeValue(forKey: key), let letter = store.letter(key),
           !letter.gone, letter.version == version {
            store.remove(key)
        }
        announce()
    }

    /// What the composer on letter `key` keeps here and takes away, and
    /// where its leftover copies are removed from.
    func keeping(_ key: String, in repository: MailRepository) -> DraftKeeping {
        DraftKeeping(
            keep: { [self] draft, finished in keep(draft, as: key, unfinished: !finished) },
            forget: { [self] in
                discard(key)
                closed(key)
            },
            abandon: { [self] in
                // What this sheet put here goes; a letter that was here
                // before it opened stays as it was last kept.
                if open[key] == false { store.remove(key) }
                closed(key)
            },
            letGo: { [self] in closed(key) },
            tidy: { [self] in await tidy(key, in: repository) })
    }

    /// Keeps the letter. Returns false when it could not be written, which
    /// is said in the connection log and nowhere else: there is nothing he
    /// could do about a full disk from the composer.
    @discardableResult
    func keep(_ draft: Draft, as key: String, unfinished: Bool) -> Bool {
        do {
            try store.keep(draft, as: key, unfinished: unfinished, account: account)
        } catch {
            Diagnostics.log(.note, "DRAFT-KEPT failed error=\(type(of: error))")
            return false
        }
        announce()
        return true
    }

    /// Delete in Drafts' Edit mode, on a letter kept here: what Delete
    /// Draft in the composer does. Off the iPad, and any copy an upload of
    /// it left in Drafts removed.
    func delete(_ key: String, from repository: MailRepository) async {
        discard(key)
        announce()
        await tidy(key, in: repository)
    }

    /// Sent, or deleted: off the iPad. A letter an upload of which has
    /// begun may have a copy in Drafts that nothing else knows of, left by
    /// that upload cut off after the server had it, or still on its way:
    /// it stays as a record of the versions tried (`LocalDraft.gone`) until
    /// those copies have been removed (`tidy`). Without it, a letter sent
    /// or deleted could stay in Drafts for good, and a sent one there reads
    /// as a letter still owed.
    private func discard(_ key: String) {
        guard let letter = store.letter(key) else { return }
        guard !letter.tried.isEmpty else {
            store.remove(key)
            return
        }
        do { try store.markGone(key) } catch { store.remove(key) }
    }

    /// Removes the copies in Drafts that the uploads of a letter sent or
    /// deleted left, and then its record. Waits for an upload of it still
    /// on its way, whose copy is one of them. One that fails leaves the
    /// record for the next pass.
    func tidy(_ key: String, in repository: MailRepository) async {
        await whileGoing(key)
        guard let letter = store.letter(key), letter.gone else { return }
        going.insert(key)
        defer { done(key) }
        guard let removed = try? await repository.deleteDrafts(uploadedAs: letter.tried) else {
            return
        }
        store.remove(key)
        announce(DraftLanding(letter: nil, id: nil, replaced: removed))
    }

    // MARK: To the server

    /// Save Draft's: the letter kept here, then taken to the server. If the
    /// server does not take it, it stays here, in Drafts, and goes later
    /// (`uploadWaiting`). A letter that cannot even be written here goes to
    /// the server straight away, as every draft did before.
    func save(_ draft: Draft, as key: String, to repository: MailRepository) async throws {
        guard keep(draft, as: key, unfinished: false) else {
            try await repository.saveDraft(draft)
            return
        }
        try await upload(key, to: repository)
    }

    /// Takes the letter kept as `key` to the server's Drafts, in place of
    /// the copy it was reopened from, and once the server has it, off the
    /// iPad. An upload of it already on its way is let finish first.
    ///
    /// The server never gets two copies of it, even from an upload cut off
    /// after the server had the letter and before it said so. The version
    /// going is written down as tried just before the APPEND, and goes
    /// under a Message-ID of its own; the next upload of the letter first
    /// asks Drafts for the versions tried before it, takes a copy of this
    /// very version as its own instead of sending it again, and removes the
    /// rest (`MailRepository.saveDraft(_:as:)`).
    ///
    /// Kept again while it went, the newer version stays here to go next
    /// time. Opened in the composer while it went, it stays here until the
    /// composer is done with it: its photos are files of this entry, the
    /// composer's copy of the letter still names the copy the upload has
    /// just replaced, and the versions tried are how whatever the composer
    /// does next finds the copy that landed. Taken off here then, the
    /// photos went from under the open letter, and its next save put a
    /// second copy in Drafts.
    ///
    /// A letter he sent whose attempt was cut off after its DATA, then
    /// kept as a draft, goes up only once Sent Mail has said it does not
    /// have that attempt (`wentEarlier`). Taken to Drafts before, it left
    /// the iPad, and the record that it may have gone with it: sent later
    /// from Drafts, it went again with nothing looked for. Found there, or
    /// not yet answered, it stays here, listed at the top of Drafts, and a
    /// Send from it asks first and sends nothing if it went. Found, no pass
    /// asks again until he changes it or the app is launched again.
    func upload(_ key: String, to repository: MailRepository) async throws {
        await whileGoing(key)
        guard let letter = store.letter(key), !letter.gone else { return }
        going.insert(key)
        defer { done(key) }
        let version = letter.version
        if !letter.unsettled.isEmpty {
            do {
                if try await wentEarlier(letter, via: repository) {
                    refuse(key, at: version)
                    return
                }
            } catch {
                if MailError.refusesSignIn(error) || error is CancellationError {
                    throw error
                }
                if error is Outbox.NoSentMail { refuse(key, at: version) }
                return
            }
        }
        let store = self.store
        let saved: DraftSaved
        do {
            saved = try await repository.saveDraft(letter.draft, as: DraftUpload(
                version: version, earlier: letter.tried,
                appending: { try await store.noteTried(key, version) }))
        } catch MailError.attachmentsMissing {
            // A file it carries from a letter that cannot be found: it stays,
            // its row saying so, and is not tried again until he changes it.
            refuse(key, at: version, saying: .attachmentsMissing)
            announce()
            throw MailError.attachmentsMissing
        }
        if let now = store.letter(key), !now.gone, now.version == version {
            if open[key] == nil {
                store.remove(key)
            } else {
                landedOpen[key] = version
            }
        }
        if let id = saved.id { landed[key] = id }
        announce(DraftLanding(letter: letter, id: saved.id, replaced: saved.replaced))
    }

    // MARK: The Outbox

    /// Send's, from the composer: the letter into the Outbox on the iPad,
    /// then to the server. Returns once it has gone.
    ///
    /// Into the Outbox first, before a byte goes, under a Message-ID made
    /// now (`LocalDraftStore.enterOutbox`), so a Send cut off anywhere, by a
    /// dropped line or by iOS ending the app, finds the letter in the
    /// Outbox and not lost, and every later attempt at it is the same
    /// message. The composer keeps the letter just before this.
    ///
    /// When the server cannot be reached, or the connection goes before its
    /// verdict, the letter stays in the Outbox and this throws
    /// `Outbox.Waiting`: the sheet closes, and the letter goes with the next
    /// pass (`uploadWaiting`). When the server refuses the letter or the
    /// password it is taken back out of the Outbox, and the error is thrown
    /// as it came: the sheet stays with the letter, as it always did
    /// (`Outbox.waits(after:)`). A letter the iPad cannot keep goes straight
    /// to the server, as every letter did before the Outbox, and a failure
    /// stays in the sheet.
    func send(_ draft: Draft, as key: String, to repository: MailRepository,
              progress: UploadProgress?) async throws {
        if store.letter(key) == nil { keep(draft, as: key, unfinished: true) }
        guard (try? store.enterOutbox(key)) != nil else {
            try await repository.send(draft, progress: progress)
            sendingRefused = false
            return
        }
        do {
            try await deliver(key, draft, via: repository, progress: progress)
            sendingRefused = false
        } catch {
            if MailError.refusesSending(error) { sendingRefused = true }
            guard Outbox.waits(after: error) else {
                store.takeBack(key)
                throw error
            }
            Diagnostics.log(.note, "OUTBOX-WAITING error=\(error)")
            throw Outbox.Waiting()
        }
    }

    /// One attempt at the letter in the Outbox kept as `key`, as `draft` if
    /// given, as kept if not. Returns once it has gone, by this attempt or
    /// an earlier one.
    ///
    /// Never twice. An attempt whose DATA went and whose 250 never came
    /// back may have reached Gmail, and nothing on the iPad can tell; sent
    /// again blind, the letter would reach him twice, and everyone it was
    /// addressed to. Such an attempt is written down just before its DATA
    /// (`LocalDraftStore.noteSending`), and before the letter goes again
    /// Sent Mail is asked for it (`wentEarlier`). Found, the letter went,
    /// and nothing is sent. Not found, it goes again, under the same
    /// Message-ID. A letter whose attempts never reached DATA is simply
    /// sent.
    ///
    /// A verdict from the server after DATA, a refusal or "not now",
    /// settles that attempt: nothing was delivered. Only a cut before the
    /// verdict leaves it unsettled, with the time of the cut.
    ///
    /// A pass's, with no `draft`, never takes a letter the composer has
    /// open: looked at here, after any wait for another attempt at it, with
    /// nothing awaited between the look and its going, and once it is going
    /// it cannot be opened (`isGoing`). The pass used to look only before it
    /// asked the repository whether the connection was up, and a tap in that
    /// hop opened the letter: sent by the pass as well, a Send in the
    /// composer sent it again with nothing to look for.
    private func deliver(_ key: String, _ draft: Draft?, via repository: MailRepository,
                         progress: UploadProgress?) async throws {
        await whileGoing(key)
        guard let letter = store.letter(key), !letter.gone, let messageID = letter.outbox,
              draft != nil || open[key] == nil else {
            throw LocalDraftStore.NotKept()
        }
        going.insert(key)
        announce()
        defer {
            done(key)
            announce()
        }
        if try await wentEarlier(letter, via: repository) { return }
        let store = self.store
        do {
            try await repository.send(draft ?? letter.draft, as: OutgoingLetter(
                messageID: messageID,
                beforeData: { try await store.noteSending(key, messageID) }),
                progress: progress)
        } catch {
            if (error as? MailError) == .connectionLost {
                store.noteCutOff(key)
            } else {
                store.settled(key, [messageID])
            }
            throw error
        }
    }

    /// Whether an earlier attempt at `letter`, one whose DATA went and
    /// whose 250 never came back, reached Gmail: Sent Mail asked for it by
    /// its Message-ID (`MailRepository.sentMail(holds:)`), since Gmail files
    /// there what it takes over SMTP. False at once for a letter with no
    /// such attempt. False, with its attempts settled, when Sent Mail has
    /// none of them and the latest was cut off long enough ago for that to
    /// mean Gmail never took it (`Outbox.settling`).
    ///
    /// Throws `Outbox.Unsettled` when it cannot say: a search the server
    /// refuses or that cannot run, or nothing found too soon after the cut.
    /// Taken as "not there", as a refused search is for Drafts, a letter
    /// could go twice, which cannot be undone; waiting costs a pass. A
    /// refused sign-in, cancellation and `Outbox.NoSentMail` are thrown as
    /// they came.
    private func wentEarlier(_ letter: LocalDraft, via repository: MailRepository)
        async throws -> Bool {
        guard !letter.unsettled.isEmpty else { return false }
        let found: Set<String>
        do {
            found = try await repository.sentMail(holds: letter.unsettled)
        } catch {
            if MailError.refusesSignIn(error) || error is CancellationError
                || error is Outbox.NoSentMail {
                throw error
            }
            Diagnostics.log(.note, "OUTBOX-UNSETTLED error=\(type(of: error))")
            throw Outbox.Unsettled()
        }
        guard found.isEmpty else {
            Diagnostics.log(.note, "OUTBOX-FOUND in Sent Mail, not sent again")
            return true
        }
        guard !store.isSettling(letter) else {
            Diagnostics.log(.note, "OUTBOX-UNSETTLED not in Sent Mail yet")
            throw Outbox.Unsettled()
        }
        store.settled(letter.key, letter.unsettled)
        return false
    }

    /// A pass's attempt at the letter in the Outbox kept as `key`, and what
    /// follows it. Returns whether the pass goes on with the Outbox.
    ///
    /// Gone, it leaves the Outbox, and as for Send in the composer the copy
    /// in Drafts it was reopened from is removed after it, and any copy an
    /// upload of it from the iPad left (B-051). It leaves before either is
    /// awaited: from the 250 it is no longer going, and while the removal
    /// took its round trips its row was back in the Outbox without
    /// "Sending…", to be opened in the composer, where a Send sent it a
    /// second time and its photos went from under the open letter.
    ///
    /// A letter refused for a reason of its own, too big, a recipient
    /// refused, a file of a forward gone from Gmail, stays in the Outbox
    /// with the reason on its row, and is not tried again unasked until he
    /// changes it or the app is launched again; the letters after it go. A
    /// refused password, or a sign-in the submission server refused, ends
    /// the pass, and nothing goes from the Outbox unasked after it
    /// (`sendingRefused`). A submission server that cannot be reached, or
    /// that says "not now", or IMAP's LOGIN refused for another reason, ends
    /// the Outbox's part of the pass, which would only fail the same way for
    /// every letter; one whose Sent Mail cannot be asked waits for the next
    /// pass and lets the others go.
    private func sendWaiting(_ key: String, via repository: MailRepository) async -> Bool {
        let version = store.letter(key)?.version
        do {
            try await deliver(key, nil, via: repository, progress: nil)
        } catch {
            if error is CancellationError { return false }
            if MailError.refusesSending(error) {
                sendingRefused = true
                return false
            }
            if error is Outbox.Unsettled || error is LocalDraftStore.NotKept { return true }
            if Outbox.waits(after: error) { return false }
            refuse(key, at: version, saying: error as? MailError ?? .notSent)
            Diagnostics.log(.note, "OUTBOX-SEND refused error=\(type(of: error))")
            announce()
            return true
        }
        // Told to a list as gone before its removal, as the composer tells
        // it (`ComposeActions.send`'s `draftSent`), so the copy is never
        // listed to be opened and sent again. Removed only if the server
        // shows it to be the letter it names (`Draft.savedLetter`).
        let sent = store.letter(key)?.draft
        let saved = sent?.savedID
        discard(key)
        announce(saved.map { DraftLanding(letter: nil, id: nil, replaced: [$0]) })
        if let saved,
           (try? await repository.deleteDraft(saved, gmailMessageID: sent?.savedLetter)) == nil {
            // Left in Drafts, as a Send from the composer leaves it when the
            // line goes after the 250.
            Diagnostics.log(.note, "OUTBOX-SENT draft copy left")
        }
        await tidy(key, in: repository)
        return true
    }

    /// Takes every letter waiting here to the server, one at a time, and
    /// removes the copies a letter sent or deleted left. Returns the pass,
    /// or nil when there is nothing to take or a pass is already running,
    /// so however many ask at once each letter goes once.
    ///
    /// The Outbox's letters go first, oldest first, in the order he sent
    /// them, then the drafts, newest first. A letter in the Outbox goes to
    /// the submission server over a connection of its own, made for a
    /// letter he asked to send; the pass still goes only while the IMAP
    /// connection is up, which says the network works and the password was
    /// taken, and which asking Sent Mail needs.
    ///
    /// Nobody asked for it, so it never makes a connection: it goes only
    /// while one is up, and stops once none is. After a launch that could
    /// not connect, or a password refused, making one is his to do, and a
    /// pass that did would send a refused password again each time he came
    /// back to the app.
    ///
    /// A letter that fails with the connection still up failed for its own
    /// sake: a forward whose original has been deleted from Gmail, an
    /// APPEND the server refuses. The pass goes on to the next, and does not
    /// try that one again until he changes it or the app is launched again.
    /// Stopping there instead held back every older letter behind it for
    /// good, and trying it after every page cost its round trips each time.
    ///
    /// A large letter (`LocalDraft.isLarge`) goes only with `largeToo`, as
    /// he leaves the app. An APPEND holds the one connection from the
    /// command to the server's answer, and nothing he taps can go first:
    /// a letter with photos taken up unasked after the launch page made
    /// the first letter he opened wait for the whole upload. A small one is
    /// a round trip or two, which is what any of his own writes costs.
    ///
    /// Inside background time, asked for at the start and given back at
    /// the end, so that locking the iPad does not stop a letter halfway,
    /// as it does not for Save Draft (B-044).
    @discardableResult
    func uploadWaiting(to repository: MailRepository, largeToo: Bool = false) -> Task<Void, Never>? {
        guard !passing else { return nil }
        let kept = store.letters()
        let due = (kept.filter { $0.outbox != nil }.reversed() + kept.filter { $0.outbox == nil })
            .filter { isDue($0, largeToo: largeToo) }.map(\.key)
        guard !due.isEmpty else { return nil }
        passing = true
        let time = BackgroundStretch("Upload Drafts", from: background)
        return Task {
            defer {
                passing = false
                time.end()
            }
            var sending = true
            // Each looked at again at its turn: it may have been opened,
            // changed or sent since the pass began. After the question to
            // the repository, which is a hop to it, so nothing is awaited
            // between the look and the letter's going.
            for key in due {
                guard await repository.isConnected else { return }
                guard let letter = store.letter(key), isDue(letter, largeToo: largeToo) else {
                    continue
                }
                if letter.gone {
                    await tidy(key, in: repository)
                    continue
                }
                if letter.outbox != nil {
                    if sending { sending = await sendWaiting(key, via: repository) }
                    if sendingRefused { return }
                    continue
                }
                do {
                    try await upload(key, to: repository)
                } catch {
                    if error is CancellationError
                        || MailError.refusesSignIn(error) { return }
                    guard await repository.isConnected else { return }
                    let missing = (error as? MailError) == .attachmentsMissing
                    refuse(key, at: letter.version, saying: missing ? .attachmentsMissing : nil)
                    Diagnostics.log(.note, "DRAFT-UPLOAD refused error=\(type(of: error))")
                }
            }
        }
    }

    /// Whether a pass takes `letter`: not while the composer has it open,
    /// and, but for the leftovers of one sent or deleted, only a letter of
    /// this account that names nothing by folder and UID alone across a
    /// password saved since (`goesFromHere`), with no attempt that may have
    /// reached Gmail from before one either, not refused since launch as
    /// it stands, and small unless `largeToo`. A letter in the Outbox not
    /// after a refusal every letter would meet (`sendingRefused`), and
    /// small by what it has to fetch from Gmail
    /// (`LocalDraft.fetchesLarge`).
    ///
    /// Such an attempt is looked for in Sent Mail before the letter goes
    /// again, and after a save Sent Mail can be another mailbox's, where it
    /// is not found (`LocalDraftStore.unsettledBeforeASave`): the pass
    /// would settle it and send the letter a second time. It waits, listed
    /// in the Outbox as one that may have gone (`outboxRows`), for him to
    /// open it and send it, which asks Sent Mail as ever and is his to
    /// choose; a draft, for him to send or save it.
    private func isDue(_ letter: LocalDraft, largeToo: Bool) -> Bool {
        guard open[letter.key] == nil else { return false }
        guard !letter.gone else { return true }
        guard goesFromHere(letter), !store.unsettledBeforeASave(letter),
              refused[letter.key] != letter.version else { return false }
        if letter.outbox != nil {
            return !sendingRefused && (largeToo || !letter.fetchesLarge)
        }
        return largeToo || !letter.isLarge
    }

    /// The letter kept as `key` is not tried again unasked as it stands at
    /// `version`, and its row says `reason`, or nothing: never what an
    /// earlier refusal of it said. Changed since, or moved between the
    /// Outbox and Drafts, a letter refused again for a reason its row does
    /// not give would otherwise go on showing the old one.
    private func refuse(_ key: String, at version: String?, saying reason: MailError? = nil) {
        refused[key] = version
        reasons[key] = reason
    }

    /// Returns once nothing is on its way for `key`.
    private func whileGoing(_ key: String) async {
        while going.contains(key) {
            await withCheckedContinuation { waitingForGoing[key, default: []].append($0) }
        }
    }

    private func done(_ key: String) {
        going.remove(key)
        for waiter in waitingForGoing.removeValue(forKey: key) ?? [] { waiter.resume() }
    }

    private func announce(_ landing: DraftLanding? = nil) {
        NotificationCenter.default.post(name: Self.changed, object: self,
                                        userInfo: landing.map { [Self.landingKey: $0] })
    }
}

/// What has just reached the server's Drafts, or left it, for a list that
/// shows Drafts: a letter taken there from the iPad, and the copy it
/// became, or the copies a letter sent or deleted had left there.
struct DraftLanding {
    /// The letter as it went; nil for the leftovers of one sent or deleted.
    let letter: LocalDraft?
    /// Its copy in Drafts, nil when the server did not say where it is.
    let id: String?
    /// The copies in Drafts that have gone: those it replaced, or the
    /// leftovers.
    let replaced: [String]
}

/// What the composer does with the letter on the iPad, handed to
/// `ComposeActions`: kept as he writes it and at Save Draft, taken off when
/// it has been sent or deleted.
struct DraftKeeping {
    /// Keeps the letter as it stands; `finished` at Save Draft, not while he
    /// is still writing it.
    let keep: @MainActor (_ letter: Draft, _ finished: Bool) -> Void
    /// Takes it off the iPad, and lets it go.
    let forget: @MainActor () -> Void
    /// The sheet has closed with nothing in the letter to keep: what the
    /// sheet kept goes, and the letter is let go.
    let abandon: @MainActor () -> Void
    /// The sheet has done with the letter: from now on it can go to the
    /// server with the rest.
    let letGo: @MainActor () -> Void
    /// After `forget`, once the letter has been sent or its copy deleted:
    /// removes any copy an upload of it left in Drafts.
    var tidy: @MainActor () async -> Void = {}
    /// How long after the last change the letter is kept.
    var pause: Duration = .seconds(3)
    /// Waits `pause`. A test hands in one it lets go by hand.
    var wait: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    /// Keeps nothing.
    static let nowhere = DraftKeeping(keep: { _, _ in }, forget: {}, abandon: {}, letGo: {})
}

extension ComposeActions {

    /// The composer's, for letter `key`: Send and Save Draft go to
    /// `repository`, and the letter is kept on the iPad in `kept` from his
    /// first change until it has been sent, deleted, or taken by the server.
    /// A Send that cannot reach the server leaves it in the Outbox, and
    /// `queued` is told as the sheet closes (`LocalDrafts.send`). `wait`
    /// stands in for the pause before an autosave, for a test.
    convenience init(letter key: String, repository: MailRepository, kept: LocalDrafts,
                     dismiss: @escaping () -> Void,
                     showError: @escaping (MailError) -> Void,
                     draw: @escaping (Look) -> Void,
                     background: BackgroundTime,
                     queued: @escaping () -> Void = {},
                     wait: (@Sendable (Duration) async throws -> Void)? = nil) {
        var keeping = kept.keeping(key, in: repository)
        if let wait { keeping.wait = wait }
        self.init(
            sendLetter: { draft, progress in
                try await kept.send(draft, as: key, to: repository, progress: progress)
            },
            saveDraft: { draft in try await kept.save(draft, as: key, to: repository) },
            deleteDraft: { id, letter in
                try await repository.deleteDraft(id, gmailMessageID: letter)
            },
            dismiss: dismiss, showError: showError, draw: draw, background: background,
            keeping: keeping, queued: queued)
    }
}
