import XCTest
@testable import Blackmail

/// The safe start (B-057): every launch counted in a file before anything
/// kept is read, and counted as finished when the app goes to the
/// background or half a minute after its first page and pass; after
/// launches in a row that never finished, what they read left behind, step
/// by step, the copy of his mail and the view settings at 2, the automatic
/// pass at 3, the letters kept on the iPad moved aside, never deleted, at 5;
/// and at every launch, the folders a failed first keep leaves.
///
/// Over an Application Support of the test's own, `Launches/`, `Kept/` and
/// `Local Drafts/` in a directory made for each test, `UserDefaults` of a
/// suite of its own, a clock the test moves, and the connection log's notes
/// written down here rather than into the app's. Each launch is a new
/// `SafeStart` over the same directories, as each launch of the app is.
/// The pass held at 3, and his Send then, run over the scripted servers in
/// `OutboxTests`.
@MainActor
final class SafeStartTests: XCTestCase {

    private static let suite = "SafeStartTests"

    private var base: URL!
    private var defaults: UserDefaults!
    private var clock: ManualClock!
    private var notes: [String] = []
    /// The count as its file read at each note, as the note was written:
    /// what a launch that crashed in that step would have left behind.
    private var countAtNotes: [String?] = []

    override func setUp() async throws {
        try await super.setUp()
        base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SafeStartTests-\(UUID().uuidString)", isDirectory: true)
        defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        clock = ManualClock()
        notes = []
        countAtNotes = []
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        if let base {
            MailShelf.wipe(root: keptRoot)
            try? FileManager.default.removeItem(at: base)
        }
        AttachmentStore.purge()
        base = nil
        defaults = nil
        clock = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private var support: URL {
        base.appendingPathComponent("Application Support", isDirectory: true)
    }
    private var launches: URL { support.appendingPathComponent("Launches", isDirectory: true) }
    private var keptRoot: URL { support.appendingPathComponent("Kept", isDirectory: true) }
    private var letters: URL { support.appendingPathComponent("Local Drafts", isDirectory: true) }
    private var countFile: URL { launches.appendingPathComponent(SafeStart.countFile) }

    private let account = "owner@example.com"
    private let host = "imap.gmail.com"

    /// A launch of the app over this test's Application Support: what
    /// `SafeStart.app` is in the app, its half minute on the test's clock.
    private func makeStart() -> SafeStart {
        let clock = self.clock!
        return SafeStart(directory: launches, kept: keptRoot, letters: letters, defaults: defaults,
                         now: { clock.now() }, timeZone: TimeZone(identifier: "UTC")!,
                         log: { [unowned self] in
                             notes.append($0)
                             countAtNotes.append(count)
                         },
                         wait: { try await clock.sleep(for: Double($0.components.seconds)) })
    }

    /// The count as it stands in its file, as `cat unfinished` reads it.
    private var count: String? {
        (try? Data(contentsOf: countFile)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The count written by hand, as on the iPad with the app ended.
    private func writeCount(_ text: String) throws {
        try FileManager.default.createDirectory(at: launches, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: countFile)
    }

    /// The view settings, each set as he could have set it, and what is his
    /// beside them in the same defaults: the account, the address book and
    /// the signature's pictures, which the share extension is handed.
    private func setEverything() {
        defaults.set("two", forKey: PaneArrangement.key)
        defaults.set(false, forKey: ConversationSettings.key)
        defaults.set("allMailboxes", forKey: "blackmail.lastJumpScope")
        defaults.set(Date(timeIntervalSince1970: 1_600_000_000), forKey: "blackmail.lastJumpDate")
        defaults.set(true, forKey: "blackmail.layoutAudit")
        defaults.set(Data("{\"address\":\"owner@example.com\"}".utf8),
                     forKey: "wtf.uhoh.blackmail.account.v1")
        defaults.set(Data("[{\"address\":\"friend@example.org\"}]".utf8),
                     forKey: "blackmail.recipients")
        defaults.set(Data("[]".utf8), forKey: "blackmail.signatureInlineImages")
    }

    private var hisOwn: [String: Data?] {
        Dictionary(uniqueKeysWithValues: ["wtf.uhoh.blackmail.account.v1", "blackmail.recipients",
                                          "blackmail.signatureInlineImages"]
            .map { ($0, defaults.data(forKey: $0)) })
    }

    /// The Inbox's page and the folder list kept, as a launch with a
    /// connection leaves them.
    private func keepAnInboxPage() {
        let shelf = MailShelf(root: keptRoot, address: account, host: host)
        shelf.took(folders: [Mailbox(id: "INBOX", name: "INBOX", unreadCount: 1, role: .inbox)])
        var row = MessageSummary(id: "1/9000", mailboxID: "INBOX",
                                 sender: "A Friend <friend@example.org>", subject: "Sunday",
                                 preview: "Lunch at one?",
                                 date: Date(timeIntervalSince1970: 1_789_990_000),
                                 isRead: false, isFlagged: false)
        row.gmailMessageID = 1_800_000_000_000_000_000
        shelf.took(page: [row], of: "INBOX", validity: 1)
        shelf.flush()
    }

    /// What the next launch's shelf would draw in its first frame.
    private var keptInbox: MailShelf.Page? {
        MailShelf(root: keptRoot, address: account, host: host).page(of: "inbox")
    }

    private func draft(_ subject: String) -> Draft {
        var draft = Draft()
        draft.to = ["friend@example.org"]
        draft.subject = subject
        draft.body = "Lunch at one?"
        return draft
    }

    /// Every file under `root` by its path inside it, with its bytes.
    private func files(under root: URL) -> [String: Data] {
        var out: [String: Data] = [:]
        let files = FileManager.default
        guard let walk = files.enumerator(atPath: root.path) else { return out }
        for case let path as String in walk {
            var isFolder: ObjCBool = false
            let url = root.appendingPathComponent(path)
            if files.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue {
                out[path] = try? Data(contentsOf: url)
            }
        }
        return out
    }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    /// The UIKit side is read from its source, as `SignInTests` reads it:
    /// comments out, every run of spaces one space.
    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    // MARK: - Counted, and finished

    /// Every launch is counted before anything else, and a launch that goes
    /// to the background has finished, however soon: he opens the app,
    /// glances and leaves within seconds, many times a day, and none of it
    /// may ever count against the next launch. Ten such looks in a row, no
    /// page drawn in any, and the eleventh launch does nothing.
    func testAQuickLookThenLeavingCountsAsFinished() async throws {
        for _ in 0..<10 {
            let start = makeStart()
            start.launch()
            XCTAssertEqual(count, "1", "counted as it starts")
            // `applicationDidEnterBackground`, seconds later.
            start.finished()
            XCTAssertEqual(count, "0")
        }
        keepAnInboxPage()
        setEverything()
        let steps = makeStart().launch()
        XCTAssertEqual(steps, SafeStart.Steps(after: 0))
        XCTAssertNotNil(keptInbox, "the kept Inbox is drawn as ever")
        XCTAssertEqual(defaults.string(forKey: PaneArrangement.key), "two")
        XCTAssertEqual(notes, [], "nothing to say")
    }

    /// A launch that crashes, or that iOS's watchdog ends, goes neither to
    /// the background nor as far as the healthy point: its count stands,
    /// and the next launch counts on from it. One of a page drawn and its
    /// pass ended that dies inside the half minute counts the same.
    func testALaunchThatNeverFinishesCounts() async throws {
        makeStart().launch()
        XCTAssertEqual(count, "1")
        let second = makeStart()
        second.launch()
        XCTAssertEqual(count, "2", "the first never finished")
        XCTAssertEqual(notes, ["SAFE-START unfinished=1"])
        second.firstPageTried(passEnded: {})
        try await until { clock.sleeping == 1 }
        clock.advance(by: 29)
        // The wait is woken, or not, as the clock moves: still asleep is
        // the half minute not yet run, whatever has yet to run after it.
        XCTAssertEqual(clock.sleeping, 1, "still waiting at twenty-nine seconds")
        XCTAssertEqual(count, "2", "ended inside the half minute")

        notes = []
        let third = makeStart().launch()
        XCTAssertEqual(count, "3")
        XCTAssertTrue(third.forgetsKeptState, "two in a row")
        XCTAssertFalse(third.holdsPasses)
        XCTAssertEqual(notes.first, "SAFE-START unfinished=2")
    }

    /// The healthy point: half a minute after the first page has been drawn
    /// AND the first pass has ended, not before either. A pass still on its
    /// way at the half minute holds the launch open until it ends, and the
    /// half minute runs from there.
    func testHealthyAfterTheFirstPageAndThePassCountsAsFinished() async throws {
        let start = makeStart()
        start.launch()
        let pass = Held()
        start.firstPageTried(passEnded: { try? await pass.wait() })
        try await until { pass.waiting == 1 }
        clock.advance(by: 120)
        XCTAssertEqual(count, "1", "the pass has not ended")

        pass.release()
        try await until { clock.sleeping == 1 }
        clock.advance(by: 29)
        XCTAssertEqual(clock.sleeping, 1, "still waiting at twenty-nine seconds")
        XCTAssertEqual(count, "1", "not yet half a minute after the pass")
        clock.advance(by: 1)
        XCTAssertEqual(clock.sleeping, 0)
        try await until { count == "0" }

        // The screens built again after a password saved in Settings say
        // so again: nothing more is waited for, however long it is given.
        start.firstPageTried(passEnded: {})
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(clock.sleeping, 0)
        XCTAssertEqual(makeStart().launch(), SafeStart.Steps(after: 0))
    }

    /// A count that cannot be read is none, and the launch writes its own
    /// over it: never a reason for a launch not to start. A file cut short
    /// or garbled, a word, a count no launch writes, one that would
    /// overflow if counted on, and a directory where the file should be.
    func testADamagedCounterReadsAsNoneAndIsWrittenAgain() async throws {
        let damaged: [Data] = [Data(), Data([0xFF, 0xFE, 0x00]), Data("two".utf8), Data("-3".utf8),
                               Data("4000".utf8), Data(String(Int.max).utf8),
                               Data("99999999999999999999999".utf8), Data("2.5".utf8)]
        keepAnInboxPage()
        setEverything()
        for bytes in damaged {
            try FileManager.default.createDirectory(at: launches, withIntermediateDirectories: true)
            try bytes.write(to: countFile)
            XCTAssertEqual(makeStart().launch(), SafeStart.Steps(after: 0), "\(Array(bytes))")
            XCTAssertEqual(count, "1", "written again")
        }
        try FileManager.default.removeItem(at: countFile)
        try FileManager.default.createDirectory(
            at: countFile.appendingPathComponent("inside"), withIntermediateDirectories: true)
        XCTAssertEqual(makeStart().launch(), SafeStart.Steps(after: 0))
        XCTAssertEqual(count, "1", "the directory gone, the count in its place")

        // Nowhere to write it at all: the launch starts, and only the guard
        // is lost.
        try FileManager.default.removeItem(at: launches)
        try Data("not a directory".utf8).write(to: launches)
        XCTAssertEqual(makeStart().launch(), SafeStart.Steps(after: 0))
        XCTAssertNotNil(keptInbox)
        XCTAssertEqual(defaults.string(forKey: PaneArrangement.key), "two")
    }

    // MARK: - Each stage at its count

    /// One launch that never finished changes nothing: a single crash can
    /// be anything, and the kept Inbox in the first frame is what D-016 is
    /// for.
    func testOneUnfinishedLaunchChangesNothing() async throws {
        keepAnInboxPage()
        setEverything()
        let store = LocalDraftStore(root: letters)
        try store.keep(draft("Sunday"), as: "letter-1", unfinished: false, account: account)
        try writeCount("1")

        let steps = makeStart().launch()
        XCTAssertEqual(steps, SafeStart.Steps(after: 1))
        XCTAssertFalse(steps.forgetsKeptState || steps.holdsPasses || steps.setsLettersAside)
        XCTAssertEqual(keptInbox?.rows.map(\.subject), ["Sunday"])
        XCTAssertEqual(defaults.string(forKey: PaneArrangement.key), "two")
        XCTAssertEqual(defaults.object(forKey: ConversationSettings.key) as? Bool, false)
        XCTAssertEqual(LocalDraftStore(root: letters).letters().map(\.key), ["letter-1"])
        XCTAssertEqual(SafeStart.taken(in: launches), [])
        XCTAssertEqual(notes, ["SAFE-START unfinished=1"])
    }

    /// Two in a row: the copy of his mail goes, so no kept page is drawn
    /// and no kept folder list, and the view settings are back to their
    /// defaults, three panes, grouped, Go to Date in the folder at today,
    /// the layout sweep off. His account, his book and the signature's
    /// pictures stay, and so does every letter kept on the iPad.
    func testTwoUnfinishedLaunchesStartWithoutTheKeptCopyOrTheViewSettings() async throws {
        keepAnInboxPage()
        setEverything()
        let before = hisOwn
        let store = LocalDraftStore(root: letters)
        try store.keep(draft("Sunday"), as: "letter-1", unfinished: false, account: account)
        let kept = files(under: letters)
        XCTAssertNotNil(keptInbox)
        try writeCount("2")

        let steps = makeStart().launch()
        XCTAssertTrue(steps.forgetsKeptState)
        XCTAssertFalse(steps.holdsPasses)
        XCTAssertFalse(steps.setsLettersAside)
        XCTAssertFalse(FileManager.default.fileExists(atPath: keptRoot.path), "Kept/ gone")
        let shelf = MailShelf(root: keptRoot, address: account, host: host)
        XCTAssertNil(shelf.page(of: "inbox"), "no kept page drawn")
        XCTAssertNil(shelf.folders, "nor the kept folder list")
        for key in SafeStart.viewSettings {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
        XCTAssertEqual(hisOwn, before, "his account, book and pictures stay")
        XCTAssertEqual(files(under: letters), kept, "the letters kept on the iPad stay")
        XCTAssertEqual(count, "3")
        XCTAssertEqual(notes, ["SAFE-START unfinished=2", "SAFE-START kept-copy=wiped",
                               "SAFE-START view-settings=reset"])
        // Counted before any step was taken: a launch that crashes in its
        // own steps is counted, and the next goes a stage further.
        XCTAssertEqual(countAtNotes, ["3", "3", "3"])
        XCTAssertEqual(SafeStart.taken(in: launches).map(\.steps),
                       [[SafeStart.keptCopyWiped, SafeStart.viewSettingsReset]])
    }

    /// Three in a row: all of that, and no automatic pass in this launch
    /// (`LocalDrafts.holdsPasses`; the pass itself is held in
    /// `OutboxTests`). The letters stay where they are. Four the same.
    func testThreeHoldTheAutomaticPassAsWell() async throws {
        for unfinished in [3, 4] {
            keepAnInboxPage()
            setEverything()
            let store = LocalDraftStore(root: letters)
            try store.keep(draft("Sunday"), as: "letter-1", unfinished: false, account: account)
            let kept = files(under: letters)
            try writeCount(String(unfinished))
            notes = []

            let steps = makeStart().launch()
            XCTAssertTrue(steps.forgetsKeptState)
            XCTAssertTrue(steps.holdsPasses)
            XCTAssertFalse(steps.setsLettersAside)
            XCTAssertNil(keptInbox)
            XCTAssertNil(defaults.object(forKey: PaneArrangement.key))
            XCTAssertEqual(files(under: letters), kept)
            XCTAssertEqual(notes, ["SAFE-START unfinished=\(unfinished)",
                                   "SAFE-START kept-copy=wiped", "SAFE-START view-settings=reset",
                                   "SAFE-START automatic-pass=held"])
            XCTAssertEqual(SafeStart.taken(in: launches).last?.steps,
                           [SafeStart.keptCopyWiped, SafeStart.viewSettingsReset,
                            SafeStart.passesHeld])
        }
    }

    /// Five in a row: all of that, and the letters kept on the iPad moved,
    /// folder and all, to "Local Drafts set aside <date>" beside it. Every
    /// file is there, byte for byte, a damaged letter's and the count of
    /// passwords saved included; the app starts with no letters and the
    /// count carried over; the folder set aside reads as the store it was.
    /// Nothing is deleted. Set aside twice in a second, the second has a
    /// name of its own; with no letter to set aside, nothing is moved.
    func testFiveSetTheLettersAsideAndNothingIsDeleted() async throws {
        let staged = try AttachmentStore.write(Data((0..<3000).map { UInt8($0 % 251) }),
                                               named: "Garden.jpg")
        var photo = draft("Garden")
        photo.attachments = [DraftAttachment(source: .localFile(staged), filename: "Garden.jpg",
                                             mimeType: "image/jpeg", size: 3000)]
        let store = LocalDraftStore(root: letters)
        try store.keep(photo, as: "photo", unfinished: false, account: account)
        try store.keep(draft("Sunday"), as: "sunday", unfinished: true, account: account)
        _ = try store.enterOutbox("sunday")
        LocalDraftStore.notePasswordSaved(in: letters)
        LocalDraftStore.notePasswordSaved(in: letters)
        try FileManager.default.createDirectory(at: letters.appendingPathComponent("damaged"),
                                                withIntermediateDirectories: true)
        try Data("{\"format\":1,\"key\":".utf8)
            .write(to: letters.appendingPathComponent("damaged/letter.json"))
        let before = files(under: letters)
        XCTAssertEqual(before.count, 5, "two letters, a photo, a damaged letter and the count")
        try writeCount("5")

        let steps = makeStart().launch()
        XCTAssertTrue(steps.setsLettersAside)
        XCTAssertTrue(steps.holdsPasses)
        XCTAssertTrue(steps.forgetsKeptState)
        let name = "Local Drafts set aside 2026-09-21 14.13.20"
        let aside = support.appendingPathComponent(name, isDirectory: true)
        XCTAssertEqual(files(under: aside), before, "every file, byte for byte")
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: support.path)),
                       ["Launches", "Local Drafts", name], "beside it, and nothing else made")

        let fresh = LocalDraftStore(root: letters)
        XCTAssertEqual(fresh.letters().count, 0, "the app starts with none")
        XCTAssertEqual(fresh.passwordSaves, 2, "the count of passwords saved goes on")
        let old = LocalDraftStore(root: aside)
        XCTAssertEqual(old.letters().map(\.draft.subject).sorted(), ["Garden", "Sunday"])
        XCTAssertEqual(old.letter("sunday")?.outbox != nil, true)
        XCTAssertEqual(old.passwordSaves, 2)

        XCTAssertEqual(notes.last, "SAFE-START local-drafts=set-aside folder=\"\(name)\"")
        XCTAssertEqual(countAtNotes, Array(repeating: "6", count: notes.count),
                       "counted before the letters were moved")
        let taken = try XCTUnwrap(SafeStart.taken(in: launches).last)
        XCTAssertEqual(taken, SafeStart.Taken(at: clock.now(), unfinished: 5,
                                              steps: [SafeStart.keptCopyWiped,
                                                      SafeStart.viewSettingsReset,
                                                      SafeStart.passesHeld,
                                                      SafeStart.lettersSetAside],
                                              setAside: name))

        // The next launch, in the same second, never finished either, and
        // a letter was written in it: set aside too, under a name of its own.
        try fresh.keep(draft("Monday"), as: "monday", unfinished: true, account: account)
        makeStart().launch()
        XCTAssertEqual(LocalDraftStore(root: support.appendingPathComponent("\(name) 2"))
                        .letters().map(\.draft.subject), ["Monday"])
        XCTAssertEqual(files(under: aside), before, "the first left as it was")

        // And the one after, with nothing in the store: nothing moved.
        notes = []
        makeStart().launch()
        XCTAssertFalse(notes.contains { $0.contains("set-aside") })
        let third = support.appendingPathComponent("\(name) 3")
        XCTAssertFalse(FileManager.default.fileExists(atPath: third.path))
        let last = SafeStart.taken(in: launches).last?.steps ?? []
        XCTAssertFalse(last.contains(SafeStart.lettersSetAside))
    }

    /// The steps are written down beside the count, for a screen that can
    /// one day show them: the last twenty, oldest first, readable as text.
    /// A record that cannot be read is begun afresh.
    func testTheStepsAreWrittenDownBesideTheCount() async throws {
        try FileManager.default.createDirectory(at: launches, withIntermediateDirectories: true)
        try Data("{\"format\":1,\"starts\":[{".utf8)
            .write(to: launches.appendingPathComponent(SafeStart.takenFile))
        try writeCount("2")
        makeStart().launch()
        XCTAssertEqual(SafeStart.taken(in: launches),
                       [SafeStart.Taken(at: clock.now(), unfinished: 2,
                                        steps: [SafeStart.keptCopyWiped,
                                                SafeStart.viewSettingsReset],
                                        setAside: nil)], "the damaged record begun afresh")
        let text = String(decoding: try Data(contentsOf: launches
            .appendingPathComponent(SafeStart.takenFile)), as: UTF8.self)
        XCTAssertTrue(text.contains("2026-09-21T14:13:20Z"), text)

        for _ in 0..<25 {
            clock.advance(by: 60)
            makeStart().launch()
        }
        let taken = SafeStart.taken(in: launches)
        XCTAssertEqual(taken.count, 20)
        XCTAssertEqual(taken.last?.unfinished, 27)
        XCTAssertEqual(taken.last?.at, clock.now())
        XCTAssertEqual(taken.first?.unfinished, 8)
    }

    // MARK: - What a failed first keep leaves

    /// Every launch removes a letter's folder with no `letter.json`: what a
    /// first keep leaves when its JSON could not be written on a full disk,
    /// the photo linked into a folder no list reads, and after the launch's
    /// purge the only link left to it. A folder with a `letter.json` stays
    /// whatever else is in it and however it reads: one cut short, one of
    /// another format, one with a stray file, and the count of passwords
    /// saved and a stray file beside them.
    func testAFolderWithNoLetterIsRemovedAndNoOtherIs() async throws {
        let staged = try AttachmentStore.write(Data((0..<3000).map { UInt8($0 % 241) }),
                                               named: "Garden.jpg")
        var photo = draft("Garden")
        photo.attachments = [DraftAttachment(source: .localFile(staged), filename: "Garden.jpg",
                                             mimeType: "image/jpeg", size: 3000)]
        let store = LocalDraftStore(root: letters)
        try store.keep(photo, as: "good", unfinished: false, account: account)
        // The failed first keep: its photo linked, its JSON never written.
        try store.keep(photo, as: "failed", unfinished: true, account: account)
        try FileManager.default.removeItem(at: letters.appendingPathComponent("failed/letter.json"))
        AttachmentStore.purge()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(
            atPath: letters.appendingPathComponent("failed").path).count, 1, "the photo alone")

        let files = FileManager.default
        try files.createDirectory(at: letters.appendingPathComponent("empty"),
                                  withIntermediateDirectories: true)
        try store.keep(draft("Cut"), as: "cut", unfinished: false, account: account)
        let cut = letters.appendingPathComponent("cut/letter.json")
        try Data(try Data(contentsOf: cut).prefix(20)).write(to: cut)
        try store.keep(draft("Future"), as: "future", unfinished: false, account: account)
        let future = letters.appendingPathComponent("future/letter.json")
        try Data(String(decoding: try Data(contentsOf: future), as: UTF8.self)
            .replacingOccurrences(of: "\"format\":1", with: "\"format\":2").utf8).write(to: future)
        try Data("stray".utf8).write(to: letters.appendingPathComponent("future/stray"))
        try Data("stray".utf8).write(to: letters.appendingPathComponent("stray.txt"))
        LocalDraftStore.notePasswordSaved(in: letters)
        var spared = self.files(under: letters)
        spared = spared.filter { !$0.key.hasPrefix("failed/") }

        let start = makeStart()
        start.launch()
        XCTAssertFalse(files.fileExists(atPath: letters.appendingPathComponent("failed").path))
        XCTAssertFalse(files.fileExists(atPath: letters.appendingPathComponent("empty").path))
        XCTAssertEqual(self.files(under: letters), spared, "every other file, byte for byte")
        XCTAssertEqual(LocalDraftStore(root: letters).letters().map(\.key), ["good"])
        XCTAssertEqual(notes, ["DRAFTS-LEFTOVERS removed=2"])
        XCTAssertEqual(countAtNotes, ["1"], "counted before anything was removed")

        start.finished()
        notes = []
        makeStart().launch()
        XCTAssertEqual(notes, [], "nothing left to remove, nothing said")
    }

    // MARK: - Where it is wired, and what it leaves alone

    /// The keys taken back to their defaults are the ones the screens read
    /// and write. Three of those screens are UIKit, so their keys are read
    /// from their source.
    func testTheViewSettingsAreTheKeysTheScreensUse() async throws {
        XCTAssertEqual(SafeStart.viewSettings, [PaneArrangement.key, ConversationSettings.key,
                                                "blackmail.lastJumpScope", "blackmail.lastJumpDate",
                                                "blackmail.layoutAudit"])
        let jump = try source("Blackmail/UI/JumpToDateViewController.swift")
        XCTAssertTrue(jump.contains(
            "private static let lastScopeKey = \"blackmail.lastJumpScope\""))
        XCTAssertTrue(jump.contains(
            "private static let lastPickedKey = \"blackmail.lastJumpDate\""))
        let audit = try source("Blackmail/UI/LayoutAudit.swift")
        XCTAssertTrue(audit.contains("static let enabledKey = \"blackmail.layoutAudit\""))
        XCTAssertEqual(PaneArrangement.key, "blackmail.panes")
        XCTAssertEqual(ConversationSettings.key, "blackmail.organizeByThread")

        // And over the defaults the screens read.
        let app = try source("Blackmail/Mail/SafeStart.swift")
        XCTAssertTrue(app.contains("static let app = SafeStart(directory: appDirectory, "
                                   + "kept: MailShelf.appRoot, letters: LocalDraftStore.appRoot, "
                                   + "defaults: .standard)"))
    }

    /// The launch is counted before anything kept is read, first thing in
    /// `didFinishLaunching`; the background finishes it, first thing in
    /// `applicationDidEnterBackground`, and so does an end while it runs,
    /// `applicationWillTerminate`, which takes back the tries on their way
    /// as leaving does, since a swipe in the app switcher may come there
    /// without the background first; the setup form's launch finishes
    /// half a minute in, and the mail's after its first page and pass;
    /// `LocalDrafts.shared` holds its passes when the launch says so, and
    /// hears of the background before the pass that leaving sets off, and
    /// of the return before the pass coming back does.
    func testTheLaunchIsCountedFirstAndFinishedWhereItSays() async throws {
        let delegate = try source("Blackmail/App/AppDelegate.swift")
        XCTAssertTrue(delegate.contains("didFinishLaunchingWithOptions launchOptions: "
                                        + "[UIApplication.LaunchOptionsKey: Any]?) -> Bool { "
                                        + "SafeStart.app.launch() AttachmentStore.purge()"))
        let launch = try XCTUnwrap(delegate.range(of: "SafeStart.app.launch()"))
        for later in ["AttachmentStore.purge()", "Self.makeRoot()", "LayoutAudit.beginSweeping()",
                      "Self.syncShareMirror()"] {
            let at = try XCTUnwrap(delegate.range(of: later), later)
            XCTAssertLessThan(launch.lowerBound, at.lowerBound, later)
        }
        XCTAssertTrue(delegate.contains("public func applicationDidEnterBackground(_ application: "
                                        + "UIApplication) { SafeStart.app.finished() "))
        XCTAssertTrue(delegate.contains("public func applicationWillTerminate(_ application: "
                                        + "UIApplication) { SafeStart.app.finished() "
                                        + "if window?.rootViewController is RootViewController { "
                                        + "LocalDrafts.shared.wentToBackground() } }"),
                      "an end while it runs takes the tries on their way back, as leaving does")
        XCTAssertTrue(delegate.contains("if !(window.rootViewController is RootViewController) { "
                                        + "SafeStart.app.firstPageTried(passEnded: {}) }"))

        let root = try source("Blackmail/UI/RootViewController.swift")
        XCTAssertTrue(root.contains("self?.watch.start() SafeStart.app.firstPageTried(passEnded: "
                                    + "{ await LocalDrafts.shared.passEnded() }) }"))
        XCTAssertTrue(root.contains("@objc private func leavingTheApp() { "
                                    + "LocalDrafts.shared.wentToBackground() "
                                    + "LocalDrafts.shared.uploadWaiting(to: repository, "
                                    + "largeToo: true) }"))
        XCTAssertTrue(root.contains("guard let self else { return } "
                                    + "LocalDrafts.shared.cameToForeground() "
                                    + "let repository = self.repository"))

        let composer = try source("Blackmail/UI/ComposeViewController.swift")
        XCTAssertTrue(composer.contains(
            "background: .app, holdsPasses: SafeStart.app.steps.holdsPasses)"))
    }

    /// The share extension sends a letter at its Send, from a process of its
    /// own with no store of letters: it never counts a launch or a try, and
    /// is never held. What the app hands it, the account, the address book
    /// and the signature's pictures, stays through every step.
    func testTheShareExtensionsLettersAreLeftAsTheyWere() async throws {
        let folders = ["Blackmail/Share", "BlackmailShare"]
        for folder in folders {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/\(folder)")
            for name in try FileManager.default.contentsOfDirectory(atPath: url.path) {
                let code = try source("\(folder)/\(name)")
                for word in ["SafeStart", "LocalDrafts", "LocalDraftStore", "autoAttempts",
                             "noteTries"] {
                    XCTAssertFalse(code.contains(word), "\(folder)/\(name): \(word)")
                }
            }
        }
        setEverything()
        let before = hisOwn
        try writeCount("9")
        let steps = makeStart().launch()
        XCTAssertTrue(steps.setsLettersAside)
        XCTAssertEqual(hisOwn, before)
    }
}
