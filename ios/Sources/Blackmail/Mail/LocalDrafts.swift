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
    func row(in mailboxID: String, from sender: String) -> MessageSummary {
        let text = PreviewText.fromPlainText(draft.body)
        return row(Self.rowPrefix + key, in: mailboxID, from: sender,
                   preview: text.isEmpty ? Self.mark : Self.mark + "\n" + text)
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
    /// or a file whose size is not known.
    var isLarge: Bool {
        var total: Int64 = 0
        for file in draft.attachments {
            guard let size = file.size else { return true }
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
}

// MARK: - On disk

/// Where kept letters live: one directory per letter under `root`, holding
/// `letter.json` and the letter's photos.
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
/// the address book does.
@MainActor
final class LocalDraftStore {

    let root: URL
    private let now: () -> Date
    private let files = FileManager.default

    /// The file in each letter's directory that says what the letter is.
    private static let letterFile = "letter.json"
    /// Bumped only for a change an older build could misread. A file of any
    /// other format is passed over.
    private static let format = 1

    init(root: URL, now: @escaping () -> Date = { Date() }) {
        self.root = root
        self.now = now
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

    // MARK: Reading

    /// Every letter that can be read, newest first.
    func letters() -> [LocalDraft] {
        let keys = (try? files.contentsOfDirectory(atPath: root.path)) ?? []
        return keys.compactMap(letter).sorted { $0.keptAt > $1.keptAt }
    }

    /// The letter kept as `key`, or nil when there is none, or none that
    /// can be read.
    func letter(_ key: String) -> LocalDraft? {
        stored(key).map { $0.letter(in: folder(for: key)) }
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
            case let .messagePart(messageID, mailboxID, section):
                file.messageID = messageID
                file.mailboxID = mailboxID
                file.section = section
            case let .localFile(url):
                guard let name = linked(url, into: folder, known: before?.files ?? []) else {
                    continue
                }
                file.name = name
                file.source = url.path
            }
            kept.append(file)
        }
        let letter = Stored(format: Self.format, key: key,
                            version: UUID().uuidString.lowercased(),
                            tried: before?.tried ?? [], unfinished: unfinished, keptAt: now(),
                            account: account, draft: draft, files: kept)
        try write(letter)
        removeFiles(in: folder, keeping: kept.compactMap(\.name))
        return letter.letter(in: folder)
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
            excludeFromBackup(root)
        }
        let folder = folder(for: key)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Not in his iCloud backup, as D-016 has it for the copy of his mail:
    /// a restore should not bring back letters that went long ago.
    private func excludeFromBackup(_ url: URL) {
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
        var to: [String]
        var cc: [String]
        var bcc: [String]
        var subject: String
        var body: String
        var inReplyTo: String?
        var references: String?
        var savedID: String?
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
            self.files = files
        }

        func letter(in folder: URL) -> LocalDraft {
            var draft = Draft()
            draft.to = to
            draft.cc = cc
            draft.bcc = bcc
            draft.subject = subject
            draft.body = body
            draft.inReplyTo = inReplyTo
            draft.references = references
            draft.savedID = savedID
            draft.attachments = files.compactMap { $0.attachment(in: folder) }
            return LocalDraft(key: key, draft: draft, version: version, tried: tried,
                              unfinished: unfinished, keptAt: keptAt, account: account,
                              gone: gone ?? false)
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
                                      section: section)
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
/// taking the rest to the server's Drafts.
///
/// A letter goes up when he taps Save Draft, and one that could not go then
/// goes later, once, over a connection that is working: each time a
/// folder's newest page has just been fetched (at launch, at a Refresh, on
/// opening a folder, on coming back after a while), each time the app comes
/// back to the foreground, and as he leaves it (`uploadWaiting`). One at a
/// time, and never one the composer has open, which is his to finish, nor
/// one already on its way.
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
    /// until he changes them, or the app is launched again.
    private var refused: [String: String] = [:]
    /// Letters the server has taken since launch, and the id of the copy
    /// each became there, for a row in Drafts drawn before it went.
    private(set) var landed: [String: String] = [:]

    init(store: LocalDraftStore, account: String?, background: BackgroundTime) {
        self.store = store
        self.account = account
        self.background = background
    }

    /// The letters Drafts lists above the server's: every one kept here but
    /// those open in the composer, newest first. A letter written in another
    /// account is listed with the rest, and goes nowhere until he opens it.
    var waiting: [LocalDraft] {
        store.letters().filter { open[$0.key] == nil && !$0.gone }
    }

    /// The letter kept as `key`, for the composer.
    ///
    /// One written in another account comes without the files it carries
    /// from letters on the server, a forward's or a reopened draft's. Those
    /// are named by folder and UID, which in this account can be another
    /// letter: Gmail gives every Inbox the same UIDVALIDITY (D-016).
    func letter(_ key: String) -> LocalDraft? {
        guard var letter = store.letter(key), !letter.gone else { return nil }
        if !isMine(letter) {
            letter.draft.attachments.removeAll {
                if case .messagePart = $0.source { return true }
                return false
            }
        }
        return letter
    }

    private func isMine(_ letter: LocalDraft) -> Bool {
        guard let theirs = letter.account, let account else { return false }
        return theirs.caseInsensitiveCompare(account) == .orderedSame
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
    func upload(_ key: String, to repository: MailRepository) async throws {
        await whileGoing(key)
        guard let letter = store.letter(key), !letter.gone else { return }
        going.insert(key)
        defer { done(key) }
        let version = letter.version
        let store = self.store
        let saved = try await repository.saveDraft(letter.draft, as: DraftUpload(
            version: version, earlier: letter.tried,
            appending: { try await store.noteTried(key, version) }))
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

    /// Takes every letter waiting here to the server, one at a time, and
    /// removes the copies a letter sent or deleted left. Returns the pass,
    /// or nil when there is nothing to take or a pass is already running,
    /// so however many ask at once each letter goes once.
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
        let due = store.letters().filter { isDue($0, largeToo: largeToo) }.map(\.key)
        guard !due.isEmpty else { return nil }
        passing = true
        let time = BackgroundStretch("Upload Drafts", from: background)
        return Task {
            defer {
                passing = false
                time.end()
            }
            // Each looked at again at its turn: it may have been opened,
            // changed or sent since the pass began.
            for key in due {
                guard let letter = store.letter(key), isDue(letter, largeToo: largeToo) else {
                    continue
                }
                guard await repository.isConnected else { return }
                if letter.gone {
                    await tidy(key, in: repository)
                    continue
                }
                do {
                    try await upload(key, to: repository)
                } catch {
                    if error is CancellationError
                        || (error as? MailError) == .passwordNeedsUpdating { return }
                    guard await repository.isConnected else { return }
                    refused[key] = letter.version
                    Diagnostics.log(.note, "DRAFT-UPLOAD refused error=\(type(of: error))")
                }
            }
        }
    }

    /// Whether a pass takes `letter`: not while the composer has it open,
    /// and, but for the leftovers of one sent or deleted, only a letter of
    /// this account, not refused since launch as it stands, and small
    /// unless `largeToo`.
    private func isDue(_ letter: LocalDraft, largeToo: Bool) -> Bool {
        guard open[letter.key] == nil else { return false }
        guard !letter.gone else { return true }
        return isMine(letter) && refused[letter.key] != letter.version
            && (largeToo || !letter.isLarge)
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
    /// `wait` stands in for the pause before an autosave, for a test.
    convenience init(letter key: String, repository: MailRepository, kept: LocalDrafts,
                     dismiss: @escaping () -> Void,
                     showError: @escaping (MailError) -> Void,
                     draw: @escaping (Look) -> Void,
                     background: BackgroundTime,
                     wait: (@Sendable (Duration) async throws -> Void)? = nil) {
        var keeping = kept.keeping(key, in: repository)
        if let wait { keeping.wait = wait }
        self.init(
            sendLetter: { draft, progress in try await repository.send(draft, progress: progress) },
            saveDraft: { draft in try await kept.save(draft, as: key, to: repository) },
            deleteDraft: { id in try await repository.deleteDraft(id) },
            dismiss: dismiss, showError: showError, draw: draw, background: background,
            keeping: keeping)
    }
}
