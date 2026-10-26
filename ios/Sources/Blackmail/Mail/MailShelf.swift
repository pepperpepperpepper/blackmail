import Foundation

/// The copy of his mail kept on the iPad (D-016, phase 1): the folder list
/// with its last counts, and the newest page of each folder as the last
/// listing from the top gave it, previews and all. What a launch draws in
/// its first frame, before anything has been sent, and what stays on screen
/// when there is no connection. And, in the same directory, the last 300
/// letters he opened, whole (`letters`, D-016's phase 2, B-111), which the
/// reading pane shows from here with a connection or without. And his own
/// letters from Sent Mail in the Inbox's conversations, as the last lookup
/// of each found them, kept with the conversation (`lettersOfHis`, B-159).
///
/// Only ever what the server last said. A page is replaced whole by each
/// listing of its folder from the top (`took(page:of:validity:)`), and
/// changed in between only by his own reads, flags, moves and deletes once
/// the server has taken them. Pages further down, a day jumped to and a
/// search's hits are not kept, nor are letters he never opened, and nor are
/// the letters kept on the iPad by `LocalDrafts`, which have a store of
/// their own beside this one that nothing here touches.
///
/// Never the wrong mailbox. The files are under a directory named for the
/// account's address and server, and every other account's is removed as
/// the shelf is made, at launch. A folder listed from the top under another
/// UIDVALIDITY than its kept page, or whose rows carry another Gmail message
/// id (X-GM-MSGID) than the kept rows with the same UID, throws away the
/// whole copy: every Gmail Inbox reports UIDVALIDITY 1, and the app-password
/// trap (B-033) can open another mailbox under his address, so the message
/// id is what tells two of them apart. A write on a kept row, or a letter
/// opened from one, names the row's Gmail message id, and the repository
/// asks the server for it under the UID unless this launch has had that
/// letter or another from the server there (`IMAPMailRepository.seen`);
/// a call that names no id, a draft removed whose draft names no letter
/// or a landed draft reopened, goes by `unproven`. Saving a password
/// throws the whole of `Kept/` away (`wipe`).
///
/// JSON files, one for the folders and one per page, read whole and
/// written whole, atomically, as D-016 chose: nothing kept is ever queried,
/// and JSON runs in the host suite as it is. The records are this file's
/// own, spelled out field by field, so a change to `MessageSummary` cannot
/// change what is on disk. A file of another format, or one that cannot be
/// read, is nothing kept, is deleted, and costs one launch like one with no
/// copy at all; it never stops a launch.
///
/// A page is read from disk the first time it is asked for and kept in
/// memory after. Changes are written behind, on a queue of their own, a
/// moment after they are made, and at once by `flush`, which the app calls
/// as it goes into the background. Nothing here is ever written to the
/// connection log.
///
/// Used from the main thread, for what the screens draw, and from the
/// repository's actor, for what it lists and writes, so its state is behind
/// a lock. The lock is never held while the disk is worked on.
final class MailShelf: @unchecked Sendable {

    /// The app's: Application Support, never Caches, which iOS may empty
    /// whenever it likes. Beside `LocalDraftStore.appRoot`, and never over
    /// it: `wipe` removes this directory and nothing else.
    static var appRoot: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Kept", isDirectory: true)
    }

    /// `Kept/`, which holds one account's directory.
    let root: URL
    /// This account's, under `root`.
    let directory: URL

    /// The letters he opened, kept in `directory` beside the pages, and
    /// thrown away with them (`KeptLetters`).
    let letters: KeptLetters

    private let now: @Sendable () -> Date
    private let lock = NSLock()

    /// What has been read from disk or kept since: pages by folder name,
    /// and the folders known to have none.
    private var pages: [String: PageRecord] = [:]
    private var absent: Set<String> = []
    /// Every page on disk is in `pages`: after `loadEverything`, and after
    /// the copy has been thrown away, when there is nothing left to read.
    private var everythingRead = false
    private var folderList: FoldersRecord?
    private var foldersRead = false
    /// His own letters from Sent Mail in the Inbox's conversations, as the
    /// last lookup of each found them (B-159), once read from disk.
    private var related: RelatedRecord?
    private var relatedRead = false

    /// What has changed since the last write.
    private var changedPages: Set<String> = []
    private var foldersChanged = false
    private var relatedChanged = false
    private var writeQueued = false

    /// Bumped each time the copy is thrown away, so a read from disk that
    /// was on its way at that moment is not put back.
    private var epoch = 0

    /// Folders listed from the top in this launch, whose pages are the
    /// server's word of today, and kept rows vouched for one at a time.
    private var listed: Set<String> = []
    private var vouched: Set<String> = []
    /// Kept rows the server has said are not the letters they were kept
    /// as, with the Gmail message id each was kept with: off the page, and
    /// still asked about, not taken as unkept (`unproven`).
    private var refused: [String: UInt64] = [:]
    /// A listing from the top in this launch has found rows of its kept
    /// page under the same UIDs with the same Gmail message ids: this is
    /// the mailbox the copy was kept from, and a UID kept for any folder
    /// names the letter it did or none, since the write names the
    /// UIDVALIDITY it came from. Nothing that names no letter is vouched
    /// for after that (`unproven`). A write, or a letter opened, that names
    /// its row's letter goes by what the server has named under the UID in
    /// this launch (`IMAPMailRepository.question`), and a kept row it has
    /// named nothing under is asked about, this mailbox or not.
    private var sameMailbox = false

    /// `wipe`'s count for `root` when this shelf was made. Once it moves on
    /// the shelf is done: it reads nothing and keeps nothing more, until a
    /// repository signing in with the password saved since makes another,
    /// at the next launch or at once after Settings (`PasswordChange`).
    private let generation: Int

    /// The folder list's file. Each page's is named for its folder
    /// (`pageFileName`).
    private static let foldersFile = "folders.json"
    /// His letters of the Inbox's conversations, all in one (B-159).
    private static let relatedFile = "related.json"

    /// The most conversations whose letters of his are kept (B-159), the
    /// least recently looked up going first: no more than the Inbox's kept
    /// rows can hold.
    static let mostConversations = 500

    /// Bumped only for a change an older build could misread. A file of
    /// any other format is thrown away.
    static let format = 1

    /// `address` and `host` are the account's, as it signs in: the copy is
    /// its own, under a directory named for both, and any other account's
    /// is removed now.
    ///
    /// `letters` is how the letters are kept: the app's are D-016's bounds
    /// on this shelf's disk queue; a test hands in its own.
    init(root: URL, address: String, host: String,
         now: @escaping @Sendable () -> Date = { Date() },
         letters options: KeptLetters.Options = KeptLetters.Options()) {
        self.root = root
        self.now = now
        let account = [address, host]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "\u{0}")
        directory = root.appendingPathComponent(Self.hash(account), isDirectory: true)
        let generation = Self.generation(of: root)
        self.generation = generation
        // The shelf's life, from its root and generation alone: no
        // reference to the shelf, so a shelf retired at a password save is
        // freed with its letters.
        letters = KeptLetters(root: root, directory: directory, disk: Self.disk,
                              alive: { [root] in Self.generation(of: root) == generation },
                              options: options)
        let mine = directory.lastPathComponent
        let root = self.root
        Self.disk.sync {
            let files = FileManager.default
            for name in (try? files.contentsOfDirectory(atPath: root.path)) ?? [] where name != mine {
                try? files.removeItem(at: root.appendingPathComponent(name))
            }
        }
    }

    // MARK: - What the screens draw

    /// A folder's kept page, as the list draws it.
    struct Page {
        /// Newest first, `mailboxID` the list's own.
        let rows: [MessageSummary]
        /// When the listing it came from was made: what the line under the
        /// list says the age of, when there is no connection.
        let keptAt: Date
    }

    /// The folders with the counts the last sweep gave them, nil when none
    /// has been kept.
    var folders: [Mailbox]? {
        guard isAlive else { return nil }
        readFolders()
        return locked { folderList?.folders.map(\.mailbox) }
    }

    /// The kept page of the folder a list is for, nil when there is none.
    /// `mailboxID` in either of the spellings the app uses, the role word
    /// "inbox" at launch or the name LIST gave, and the rows come back
    /// under it, as a listing of that id gives them.
    func page(of mailboxID: String) -> Page? {
        guard isAlive, let record = record(of: folderName(for: mailboxID)) else { return nil }
        return Page(rows: record.rows.map { $0.summary(in: mailboxID) }, keptAt: record.keptAt)
    }

    /// The folder name a list's id stands for, from the kept folder list
    /// when it has one, as the repository resolves it from LIST.
    func folderName(for mailboxID: String) -> String {
        if let kept = folders, let i = kept.firstIndex(matchingMailboxID: mailboxID) {
            return kept[i].id
        }
        return mailboxID.caseInsensitiveCompare("inbox") == .orderedSame ? "INBOX" : mailboxID
    }

    // MARK: - What the repository has from the server

    /// Why a listing threw the whole copy away.
    enum Discard: Equatable {
        /// The folder has another UIDVALIDITY than its kept page: every
        /// UID kept for it now names another letter, or none.
        case renumbered
        /// A row carries another Gmail message id than the kept row with
        /// the same UID: another mailbox, or a mailbox made again.
        case anotherLetter
    }

    /// The folder list from a sweep, counts and all, in place of the last.
    func took(folders: [Mailbox]) {
        guard isAlive else { return }
        locked {
            folderList = FoldersRecord(format: Self.format, keptAt: now(),
                                       folders: folders.map(FolderRecord.init))
            foldersRead = true
            foldersChanged = true
            queueWrite()
        }
    }

    /// The newest page of `folder`, listed from the top under `validity`,
    /// in place of the one kept. The whole copy goes first, and is returned
    /// why, when the listing says the kept one was not this mailbox's.
    ///
    /// The previews of the kept rows go across to the same letters, since
    /// the rows come from the server with none and only the rest are
    /// fetched; never after a discard.
    ///
    /// `sizes` are the sizes on the server of the rows the repository
    /// opens without their files (`IMAPMailRepository.largeLetterBytes`),
    /// kept with those rows and read back by `size(of:in:)`.
    @discardableResult
    func took(page rows: [MessageSummary], of folder: String, validity: UInt32,
              sizes: [String: Int] = [:]) -> Discard? {
        guard isAlive else { return nil }
        let kept = record(of: folder)
        var discard: Discard?
        var previews: [String: String] = [:]
        var matched = false
        if let kept {
            var letters: [String: RowRecord] = [:]
            for row in kept.rows { letters[row.id] = row }
            if kept.validity != validity {
                discard = .renumbered
            } else if rows.contains(where: { row in
                guard let now = row.gmailMessageID, let was = letters[row.id]?.message else { return false }
                return now != was
            }) {
                discard = .anotherLetter
            } else {
                for row in rows {
                    guard let was = letters[row.id], was.message == row.gmailMessageID else { continue }
                    if was.message != nil { matched = true }
                    if !was.preview.isEmpty { previews[row.id] = was.preview }
                }
            }
        }
        if discard != nil { discardEverything() }
        let page = PageRecord(format: Self.format, folder: folder, validity: validity, keptAt: now(),
                              rows: rows.map { row in
                                  RowRecord(row, preview: row.preview.isEmpty
                                            ? previews[row.id] ?? "" : row.preview,
                                            size: sizes[row.id])
                              })
        locked {
            pages[folder] = page
            absent.remove(folder)
            changedPages.insert(folder)
            listed.insert(folder)
            if matched { sameMailbox = true }
            queueWrite()
        }
        keepingLettersOfHis(after: page)
        return discard
    }

    /// The size the kept row `id` of `folder` was kept with, nil when it
    /// has none or is not kept: for a letter opened from the kept page
    /// before its folder's first page has come in this launch, which may
    /// be too large to fetch whole (`IMAPMailRepository.loadMessage`).
    func size(of id: String, in folder: String) -> Int? {
        guard isAlive else { return nil }
        return record(of: folder)?.rows.first { $0.id == id }?.size
    }

    /// Previews fetched for rows of `folder`, put on its kept page where
    /// the rows are on it: the page as he saw it.
    func previews(_ previews: [String: String], in folder: String) {
        guard !previews.isEmpty else { return }
        change(folder) { page in
            var changed = false
            for i in page.rows.indices {
                if let text = previews[page.rows[i].id], text != page.rows[i].preview {
                    page.rows[i].preview = text
                    changed = true
                }
            }
            return changed
        }
    }

    /// The server has taken his read mark: the row, and the same letter on
    /// every other kept page, by its Gmail message id, since `\Seen` is the
    /// letter's on Gmail and not the folder's. `letter` is the id the write
    /// named (`MessageSummary.gmailMessageID`); see `changeLetter`.
    func read(_ read: Bool, id: String, letter: UInt64?, in folder: String) {
        changeLetter(id, letter: letter, in: folder) { $0.read = read }
    }

    /// One off, or one back on, the kept counts of `mailboxIDs`, as the
    /// folder pane has just done to its own for his read or unread mark, or
    /// an unread letter binned (`MailboxListViewController.adjustUnreadCounts`),
    /// so a launch draws the counts he last saw. Left to the sweeps alone,
    /// the counts stood at the last one's until the next: a letter marked
    /// unread was kept off the Inbox's count, the next launch said 1 where
    /// the pane had said 2, and reading that letter at once took it to none.
    func counted(_ mailboxIDs: [String], by delta: Int) {
        guard isAlive else { return }
        readFolders()
        locked {
            guard var list = folderList else { return }
            let mailboxes = list.folders.map(\.mailbox)
            var changed = false
            for id in mailboxIDs {
                guard let i = mailboxes.firstIndex(matchingMailboxID: id) else { continue }
                let updated = max(0, list.folders[i].unread + delta)
                guard updated != list.folders[i].unread else { continue }
                list.folders[i].unread = updated
                changed = true
            }
            guard changed else { return }
            folderList = list
            foldersChanged = true
            queueWrite()
        }
    }

    /// The server has taken his flag, on the letter wherever it is kept.
    func flagged(_ flagged: Bool, id: String, letter: UInt64?, in folder: String) {
        changeLetter(id, letter: letter, in: folder) { $0.flagged = flagged }
    }

    /// The server has the letter as answered (`\Answered`), on the letter
    /// wherever it is kept, as a flag is: Gmail's flags are the letter's.
    /// Written only as true; false is written as nothing, as a page kept
    /// before the rows carried it reads (B-102).
    func answered(_ answered: Bool, id: String, letter: UInt64?, in folder: String) {
        changeLetter(id, letter: letter, in: folder) { $0.answered = answered ? true : nil }
    }

    /// The server has the letter as forwarded (`$Forwarded`), the same way.
    func forwarded(_ forwarded: Bool, id: String, letter: UInt64?, in folder: String) {
        changeLetter(id, letter: letter, in: folder) { $0.forwarded = forwarded ? true : nil }
    }

    /// The server has taken the letter out of `folder`: moved, deleted, or
    /// a draft removed. With `andEveryFolderBut`, out of every folder but
    /// that one, as a letter binned or marked as spam leaves every label
    /// on Gmail, and is kept nowhere until the Trash is listed again.
    ///
    /// The letter is found as a read mark's is (`changeLetter`): from its
    /// row on `folder`'s kept page, or, when `folder` has none under `id`,
    /// from the Gmail message id the write named (`letter`). Binned from an
    /// All Mailboxes hit with All Mail never opened, so with no kept page
    /// to find it on, the letter stayed on the Inbox's kept page, and a
    /// launch drew it there until the first page came (B-089).
    ///
    /// The letter kept whole under `id` in `folder` goes too, and, binned
    /// or marked as spam, every letter kept with its Gmail id in any folder
    /// but `destination` (`KeptLetters.gone`), whether or not a page holds
    /// its row.
    func gone(_ id: String, letter named: UInt64? = nil, from folder: String,
              andEveryFolderBut destination: String? = nil) {
        guard isAlive else { return }
        let row = record(of: folder)?.rows.first { $0.id == id }
        let message = destination == nil ? nil : row == nil ? named : row?.message
        if let at = Self.parse(id) {
            letters.gone(uid: at.uid, validity: at.validity, in: folder)
        }
        if let destination, let letter = named ?? row?.message {
            letters.gone(message: letter, everyFolderBut: destination)
        }
        // His letters kept with the Inbox's conversations (B-159): the row
        // itself, and the letter binned or marked as spam.
        let binned = destination == nil ? nil : named ?? row?.message
        dropLettersOfHis { sent, kept in
            (sent == folder && kept.id == id)
                || (binned != nil && sent != destination && kept.message == binned)
        }
        guard row != nil || message != nil else { return }
        if message != nil { loadEverything() }
        locked {
            for (name, var kept) in pages {
                let before = kept.rows.count
                kept.rows.removeAll { row in
                    (name == folder && row.id == id)
                        || (message != nil && name != destination && row.message == message)
                }
                guard kept.rows.count != before else { continue }
                pages[name] = kept
                changedPages.insert(name)
            }
            queueWrite()
        }
    }

    // MARK: - Vouching for a kept row

    /// A write on a kept row, or a letter opened from one, that the server
    /// did not vouch for: nothing was written and nothing of the letter is
    /// to be shown, and the row has left the kept page (D-016).
    struct NotTheKeptLetter: Error, Equatable {}

    /// The Gmail message id the row `id` of `folder` was kept with, when a
    /// write on it that names no letter has to be vouched for before it is
    /// sent, or the letter before it is shown: the row is on the page kept
    /// from an earlier launch, and nothing in this one has shown the server
    /// to be the mailbox it was kept from, neither a listing of the folder
    /// from the top nor one of any folder that found its kept rows under
    /// the same ids (`sameMailbox`).
    /// Nil for anything else, and for a row kept without an id, from a
    /// server without Gmail's extension, where the UIDVALIDITY the write is
    /// sent under is what tells.
    ///
    /// Only for a write or an opening that names no Gmail message id: a
    /// draft removed that was found by its Message-ID or whose draft names
    /// no letter, the copy of a letter that has just gone up, a row from a
    /// server without the extension. The rest name the row's own,
    /// and the repository decides them by what this launch has had from
    /// the server under the UID (`IMAPMailRepository.question`), which a
    /// listing from the top does not settle for a kept row still drawn
    /// after the listing has thrown the copy away, nor, in the copy's own
    /// mailbox, for a kept row the fresh page lacks.
    ///
    /// Still the id it was kept with for a row the server has already said
    /// is another letter (`refuse`), though it is off the page: a second
    /// call on it that names no letter, a landed draft's copy removed after
    /// its reopening was refused, would otherwise find the row unkept and
    /// go unasked, the EXPUNGE onto the other draft. A call that names its
    /// letter, a tap's read mark and FETCH among them, does not come here:
    /// the server's answer is what this launch has seen under the UID
    /// (`IMAPMailRepository.seen`), so the next is refused with nothing
    /// sent, or asked again when the server named no letter there.
    func unproven(_ id: String, in folder: String) -> UInt64? {
        let key = Self.key(id, folder)
        guard isAlive else { return nil }
        let (proven, refusedAs) = locked {
            (sameMailbox || listed.contains(folder) || vouched.contains(key), refused[key])
        }
        guard !proven else { return nil }
        return record(of: folder)?.rows.first { $0.id == id }?.message ?? refusedAs
    }

    /// The server has said the row is the letter it was kept as.
    func vouched(_ id: String, in folder: String) {
        locked { _ = vouched.insert(Self.key(id, folder)) }
    }

    /// The server has said the row `id`, kept as the letter `message`, is
    /// not that letter: off the kept page, so it is not drawn again, and
    /// remembered, so nothing more is sent or shown on it unasked.
    ///
    /// Only the row that is still the one kept. The listing the launch had
    /// on the wire can land while the question is out, throw the copy away
    /// (`took(page:of:validity:)`) and keep the server's page in its place,
    /// and the row under that id is then the server's own letter, which
    /// stays.
    ///
    /// The letter kept whole under that UID as that letter goes too.
    func refuse(_ id: String, in folder: String, keptAs message: UInt64) {
        locked { refused[Self.key(id, folder)] = message }
        if let at = Self.parse(id) {
            letters.refused(uid: at.uid, validity: at.validity, in: folder, message: message)
        }
        dropLettersOfHis { sent, kept in sent == folder && kept.id == id && kept.message == message }
        change(folder) { page in
            let before = page.rows.count
            page.rows.removeAll { $0.id == id && $0.message == message }
            return page.rows.count != before
        }
    }

    // MARK: - His letters in a conversation (B-159)

    /// His own letters of the Inbox conversation `thread` from Sent Mail, as
    /// the last lookup found them (`took(lettersOfHis:)`), with that
    /// folder's name as the Mailboxes pane shows it; nil when none is kept.
    /// For a conversation opened after a relaunch with no connection, as
    /// Mail shows his replies from the mail it has downloaded, and for the
    /// stack's first frame until the lookup has answered. The rows are the
    /// server's last word on them, as a kept page's are: opening one is
    /// vouched for as opening a kept row is (`IMAPMailRepository.question`).
    func lettersOfHis(inThread thread: UInt64) -> RelatedLetters? {
        guard isAlive else { return nil }
        readRelated()
        let found: (folder: String, kept: ThreadRecord)? = locked {
            guard let record = related,
                  let kept = record.threads.first(where: { $0.thread == thread }) else { return nil }
            return (record.folder, kept)
        }
        guard let found else { return nil }
        let name = folders?.first { $0.id == found.folder }?.displayName ?? found.kept.name
        return RelatedLetters(folderName: name,
                              letters: found.kept.rows.map { $0.summary(in: found.folder) })
    }

    /// What a lookup in Sent Mail, `folder` under `validity`, found for the
    /// Inbox conversation `thread`, in place of what was kept for it, and
    /// nothing kept for it when it found none. A Sent Mail under another
    /// UIDVALIDITY than the one kept throws away every conversation's: their
    /// ids name other letters there, or none. The conversation looked up is
    /// the newest kept, and past `mostConversations` conversations, or
    /// `mostLettersOfHis` letters, the one looked up longest ago goes.
    func took(lettersOfHis found: RelatedLetters, inThread thread: UInt64,
              folder: String, validity: UInt32) {
        guard isAlive else { return }
        readRelated()
        let rows = found.letters.prefix(CompleteThreads.mostLetters)
            .map { RowRecord($0, preview: $0.preview) }
        locked {
            var record = related.flatMap { $0.folder == folder && $0.validity == validity ? $0 : nil }
                ?? RelatedRecord(format: Self.format, folder: folder, validity: validity, threads: [])
            record.threads.removeAll { $0.thread == thread }
            if !rows.isEmpty {
                record.threads.append(ThreadRecord(thread: thread, keptAt: now(),
                                                   name: found.folderName, rows: Array(rows)))
            }
            var total = record.threads.reduce(0) { $0 + $1.rows.count }
            while record.threads.count > Self.mostConversations || total > Self.mostLettersOfHis {
                total -= record.threads.removeFirst().rows.count
            }
            related = record.threads.isEmpty ? nil : record
            relatedChanged = true
            queueWrite()
        }
    }

    /// The most of his letters kept across every conversation (B-159),
    /// about a megabyte at most, a row being some 600 bytes.
    static let mostLettersOfHis = 2_000

    /// A page listed from the top: Sent Mail under another UIDVALIDITY than
    /// the one his kept letters were found under takes them all; the
    /// Inbox's takes those of the conversations it no longer holds, as they
    /// are kept with the conversation and no longer.
    private func keepingLettersOfHis(after page: PageRecord) {
        let inbox = folderName(for: "inbox")
        readRelated()
        locked {
            guard var record = related else { return }
            if record.folder == page.folder, record.validity != page.validity {
                related = nil
            } else if page.folder == inbox {
                let threads = Set(page.rows.compactMap { CompleteThreads.threadNumber($0.thread) })
                let before = record.threads.count
                record.threads.removeAll { !threads.contains($0.thread) }
                guard record.threads.count != before else { return }
                related = record.threads.isEmpty ? nil : record
            } else {
                return
            }
            relatedChanged = true
            queueWrite()
        }
    }

    /// Takes out of his kept letters every row `which` names, given Sent
    /// Mail's name: the server has taken it away, or said it is another
    /// letter.
    private func dropLettersOfHis(_ which: (_ folder: String, _ row: RowRecord) -> Bool) {
        guard isAlive else { return }
        readRelated()
        locked {
            guard var record = related else { return }
            let folder = record.folder
            var changed = false
            for i in record.threads.indices {
                let before = record.threads[i].rows.count
                record.threads[i].rows.removeAll { which(folder, $0) }
                if record.threads[i].rows.count != before { changed = true }
            }
            guard changed else { return }
            record.threads.removeAll { $0.rows.isEmpty }
            related = record.threads.isEmpty ? nil : record
            relatedChanged = true
            queueWrite()
        }
    }

    // MARK: - Writing

    /// Writes whatever has changed, now, the letters' index included. As
    /// the app goes into the background, where it may be ended without
    /// being told.
    func flush() {
        Self.disk.sync { self.writeChanges() }
        letters.flush()
    }

    /// Throws away the whole of `root`, every account's copy, and ends
    /// every shelf made over it: a password has been saved, which may open
    /// another mailbox under the same address (B-033), or the account has
    /// been taken out. Nothing else under Application Support is touched,
    /// the letters kept by `LocalDrafts` above all.
    static func wipe(root: URL) {
        disk.sync {
            wipesLock.lock()
            wipes[root.standardizedFileURL.path, default: 0] += 1
            wipesLock.unlock()
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// Every write and every read of a file, for every shelf, one at a
    /// time, in order, so a wipe and a discard land after whatever was
    /// written before them and before whatever comes after.
    /// The letters' too (`KeptLetters`).
    static let disk = DispatchQueue(label: "wtf.uhoh.blackmail.kept", qos: .utility)

    /// How many times each root has been wiped, by path.
    private static var wipes: [String: Int] = [:]
    private static let wipesLock = NSLock()

    static func generation(of root: URL) -> Int {
        wipesLock.lock()
        defer { wipesLock.unlock() }
        return wipes[root.standardizedFileURL.path, default: 0]
    }

    private var isAlive: Bool { Self.generation(of: root) == generation }

    /// A write, a moment from now on the disk queue, unless one is waiting
    /// there already. Called with the lock held.
    private func queueWrite() {
        guard !writeQueued else { return }
        writeQueued = true
        Self.disk.async { self.writeChanges() }
    }

    /// On the disk queue.
    private func writeChanges() {
        let (folders, changed, related): (FoldersRecord?, [PageRecord], RelatedRecord??) = locked {
            writeQueued = false
            defer {
                foldersChanged = false
                changedPages = []
                relatedChanged = false
            }
            return (foldersChanged ? folderList : nil, changedPages.compactMap { pages[$0] },
                    relatedChanged ? .some(self.related) : nil)
        }
        guard isAlive, folders != nil || !changed.isEmpty || related != nil else { return }
        let files = FileManager.default
        do {
            if !files.fileExists(atPath: directory.path) {
                try files.createDirectory(at: directory, withIntermediateDirectories: true)
                Self.excludeFromBackup(root)
                Self.excludeFromBackup(directory)
            }
            let encoder = JSONEncoder()
            if let folders {
                try encoder.encode(folders).write(to: directory.appendingPathComponent(Self.foldersFile),
                                                  options: .atomic)
            }
            for page in changed {
                try encoder.encode(page).write(to: pageFile(page.folder), options: .atomic)
            }
            if let related {
                let file = directory.appendingPathComponent(Self.relatedFile)
                if let record = related {
                    try encoder.encode(record).write(to: file, options: .atomic)
                } else {
                    try? files.removeItem(at: file)
                }
            }
        } catch {
            // A disk that is full: each file stays as it was, the last copy
            // written whole, and a page is written again at its next change.
        }
    }

    /// Not in his iCloud backup: a restore onto another iPad should not
    /// bring back a list of letters from whenever the backup was made. For
    /// every directory the shelf or its letters make.
    static func excludeFromBackup(_ url: URL) {
        #if os(iOS)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = url
        try? url.setResourceValues(values)
        #endif
    }

    // MARK: - Reading

    /// `folder`'s page, read from disk the first time it is asked for.
    private func record(of folder: String) -> PageRecord? {
        let (known, epoch): (PageRecord??, Int) = locked {
            if let page = pages[folder] { return (.some(page), self.epoch) }
            if everythingRead || absent.contains(folder) { return (.some(nil), self.epoch) }
            return (nil, self.epoch)
        }
        if let known { return known }
        let file = pageFile(folder)
        let read = Self.disk.sync { Self.read(PageRecord.self, at: file) }
        return locked {
            if let page = pages[folder] { return page }
            guard self.epoch == epoch else { return nil }
            if let read, read.folder == folder {
                pages[folder] = read
                return read
            }
            absent.insert(folder)
            return nil
        }
    }

    private func readFolders() {
        let (read, epoch) = locked { (foldersRead, self.epoch) }
        guard !read else { return }
        let file = directory.appendingPathComponent(Self.foldersFile)
        let found = Self.disk.sync { Self.read(FoldersRecord.self, at: file) }
        locked {
            guard !foldersRead, self.epoch == epoch else { return }
            folderList = found
            foldersRead = true
        }
    }

    /// His letters of the Inbox's conversations (B-159), read from disk the
    /// first time they are asked for.
    private func readRelated() {
        let (read, epoch) = locked { (relatedRead, self.epoch) }
        guard !read else { return }
        let file = directory.appendingPathComponent(Self.relatedFile)
        let found = Self.disk.sync { Self.read(RelatedRecord.self, at: file) }
        locked {
            guard !relatedRead, self.epoch == epoch else { return }
            related = found
            relatedRead = true
        }
    }

    /// Every page on disk, for a change to a letter wherever it is kept.
    private func loadEverything() {
        let (done, epoch) = locked { (everythingRead, self.epoch) }
        guard !done else { return }
        let directory = self.directory
        let found: [(file: String, page: PageRecord)] = Self.disk.sync {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            return names.filter { $0.hasPrefix("page-") }.compactMap { name in
                Self.read(PageRecord.self, at: directory.appendingPathComponent(name))
                    .map { (name, $0) }
            }
        }
        locked {
            guard self.epoch == epoch else { return }
            for (file, page) in found where pages[page.folder] == nil
                && file == Self.pageFileName(page.folder) {
                pages[page.folder] = page
                absent.remove(page.folder)
            }
            everythingRead = true
        }
    }

    /// A record, or nil for a file that is not there, cannot be decoded, or
    /// is of another format, which is deleted: nothing kept, as D-016 has
    /// it, for one launch.
    private static func read<Record: Decodable>(_ type: Record.Type, at url: URL) -> Record? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data), header.format == format,
              let record = try? decoder.decode(Record.self, from: data) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return record
    }

    // MARK: - Changing

    private func change(_ folder: String, _ edit: (inout PageRecord) -> Bool) {
        guard isAlive, record(of: folder) != nil else { return }
        locked {
            guard var page = pages[folder], edit(&page) else { return }
            pages[folder] = page
            changedPages.insert(folder)
            queueWrite()
        }
    }

    /// The row `id` of `folder`, and every kept row of the same letter.
    ///
    /// The letter is the one its row on `folder`'s kept page was kept as,
    /// or, when `folder` has no kept row under `id`, the one the write
    /// named (`letter`). A read mark or a flag on an All Mailboxes hit names
    /// a row of All Mail, whose page is kept only once All Mail has been
    /// opened, and reaches only its newest letters; found by that row
    /// alone, the hit changed nothing, and the Inbox's kept row for the
    /// same letter kept its dot or its flag until the Inbox was next listed
    /// from the top, so a launch drew it so (B-089).
    private func changeLetter(_ id: String, letter named: UInt64?, in folder: String,
                              _ edit: (inout RowRecord) -> Void) {
        guard isAlive else { return }
        let row = record(of: folder)?.rows.first { $0.id == id }
        let message = row == nil ? named : row?.message
        guard row != nil || message != nil else { return }
        if message != nil { loadEverything() }
        locked {
            for (name, var kept) in pages {
                var changed = false
                for i in kept.rows.indices
                where (name == folder && kept.rows[i].id == id)
                    || (message != nil && kept.rows[i].message == message) {
                    edit(&kept.rows[i])
                    changed = true
                }
                guard changed else { continue }
                pages[name] = kept
                changedPages.insert(name)
            }
            queueWrite()
        }
    }

    /// Everything, in memory and on disk: the copy was not this mailbox's.
    ///
    /// Off the disk before this returns, so that the page kept next is
    /// written after the removal: a write already waiting on the queue
    /// finds nothing changed in memory, and one queued from now on comes
    /// after it.
    private func discardEverything() {
        // The letters first, so a keep or a read of one on its way puts
        // nothing back; their files go with the directory.
        letters.forget()
        locked {
            pages = [:]
            absent = []
            everythingRead = true
            folderList = nil
            foldersRead = true
            related = nil
            relatedRead = true
            changedPages = []
            foldersChanged = false
            relatedChanged = false
            listed = []
            vouched = []
            refused = [:]
            sameMailbox = false
            epoch += 1
        }
        let directory = self.directory
        Self.disk.sync { try? FileManager.default.removeItem(at: directory) }
    }

    // MARK: - Names

    private func pageFile(_ folder: String) -> URL {
        directory.appendingPathComponent(Self.pageFileName(folder))
    }

    /// Made from the folder's name, which can hold any character; the file
    /// says whose it is, and a page read back for another folder is none.
    private static func pageFileName(_ folder: String) -> String {
        "page-\(hash(folder)).json"
    }

    private static func key(_ id: String, _ folder: String) -> String { "\(folder)\u{0}\(id)" }

    /// A row's id, "<uidvalidity>/<uid>", in its two halves.
    private static func parse(_ id: String) -> (validity: UInt32, uid: UInt32)? {
        let parts = id.split(separator: "/", maxSplits: 1)
        guard parts.count == 2, let validity = UInt32(parts[0]), let uid = UInt32(parts[1]) else {
            return nil
        }
        return (validity, uid)
    }

    /// 64-bit FNV-1a, in hex: a name for a directory or a file, not a secret.
    static func hash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: - The format

    /// What every file starts by saying, read before the rest.
    private struct Header: Decodable {
        let format: Int
    }

    private struct FoldersRecord: Codable {
        var format: Int
        var keptAt: Date
        var folders: [FolderRecord]
    }

    private struct FolderRecord: Codable {
        var id: String
        var name: String
        var unread: Int
        var role: String?
        var depth: Int

        init(_ mailbox: Mailbox) {
            id = mailbox.id
            name = mailbox.name
            unread = mailbox.unreadCount
            role = mailbox.role?.rawValue
            depth = mailbox.depth
        }

        var mailbox: Mailbox {
            Mailbox(id: id, name: name, unreadCount: unread,
                    role: role.flatMap(Mailbox.Role.init(rawValue:)), depth: depth)
        }
    }

    private struct PageRecord: Codable {
        var format: Int
        var folder: String
        var validity: UInt32
        var keptAt: Date
        var rows: [RowRecord]
    }

    /// His letters of the Inbox's conversations, from Sent Mail (B-159):
    /// that folder's name and the UIDVALIDITY the rows' ids are under, and
    /// each conversation's letters, the one looked up longest ago first.
    private struct RelatedRecord: Codable {
        var format: Int
        var folder: String
        var validity: UInt32
        var threads: [ThreadRecord]
    }

    /// One conversation's: its Gmail thread number, when it was looked up,
    /// the folder's name as the Mailboxes pane showed it then, and his
    /// letters as the lookup had them, the oldest first.
    private struct ThreadRecord: Codable {
        var thread: UInt64
        var keptAt: Date
        var name: String
        var rows: [RowRecord]
    }

    /// A row as the list drew it, field by field, for the reason
    /// `LocalDraftStore.Stored` is: the file's shape changes only when this
    /// does.
    private struct RowRecord: Codable {
        var id: String
        var sender: String
        var subject: String
        var preview: String
        var date: Date
        var read: Bool
        var flagged: Bool
        var attachment: Bool
        var thread: String?
        var message: UInt64?
        var counted: [String]
        var files: [FileRecord]
        /// The letter's size on the server, for one the repository opens
        /// without its files; absent for every other, and in a page kept
        /// before sizes were.
        var size: Int?
        /// `MessageSummary.cc`: absent for a letter with none, and in a page
        /// kept before the rows carried it, which reads as none, so no new
        /// format. A row kept so has its Cc line when the letter lands, as
        /// every row did.
        var cc: [String]?
        /// `MessageSummary.to`, written whenever the row knows it, as an
        /// empty list for a letter to nobody; absent in a page kept before
        /// the rows carried it, which reads as not known, so such a row
        /// names its sender until the folder is listed again, rather than
        /// "No Recipients" over every kept row in Sent Mail. No new format.
        var to: [String]?
        /// `MessageSummary.bcc`: absent for a letter with none, and in a
        /// page kept before the rows carried it, which reads as none.
        var bcc: [String]?
        /// `MessageSummary.arrived`, when the server took the letter: absent
        /// in a page kept before the rows carried it, which reads as not
        /// known, so that row's conversation keeps the folder's order until
        /// the folder is listed again (B-084). No new format.
        var arrived: Date?
        /// `MessageSummary.isAnswered` and `isForwarded`, for the row's grey
        /// arrow (B-102): written only for a letter that has the mark, and
        /// absent for every other and in a page kept before the rows
        /// carried them, which reads as no mark. No new format: a page
        /// kept so draws no arrow until the folder is listed again.
        var answered: Bool?
        var forwarded: Bool?

        init(_ row: MessageSummary, preview: String, size: Int? = nil) {
            id = row.id
            sender = row.sender
            subject = row.subject
            self.preview = preview
            date = row.date
            read = row.isRead
            flagged = row.isFlagged
            attachment = row.hasAttachment
            thread = row.threadID
            message = row.gmailMessageID
            counted = row.countedFolderIDs
            files = row.attachments.map(FileRecord.init)
            self.size = size
            cc = row.cc.isEmpty ? nil : row.cc
            to = row.to
            bcc = row.bcc.isEmpty ? nil : row.bcc
            arrived = row.arrived
            answered = row.isAnswered ? true : nil
            forwarded = row.isForwarded ? true : nil
        }

        func summary(in mailboxID: String) -> MessageSummary {
            MessageSummary(id: id, mailboxID: mailboxID, sender: sender, subject: subject,
                           preview: preview, date: date, isRead: read, isFlagged: flagged,
                           isAnswered: answered ?? false, isForwarded: forwarded ?? false,
                           hasAttachment: attachment, threadID: thread, gmailMessageID: message,
                           countedFolderIDs: counted, attachments: files.map(\.attachment),
                           to: to, cc: cc ?? [], bcc: bcc ?? [], arrived: arrived)
        }
    }

    private struct FileRecord: Codable {
        var id: String
        var filename: String
        var mimeType: String
        var size: Int64?
        var contentID: String?
        var inline: Bool

        init(_ attachment: Attachment) {
            id = attachment.id
            filename = attachment.filename
            mimeType = attachment.mimeType
            size = attachment.size
            contentID = attachment.contentID
            inline = attachment.isInline
        }

        var attachment: Attachment {
            Attachment(id: id, filename: filename, mimeType: mimeType, size: size,
                       contentID: contentID, isInline: inline)
        }
    }
}
