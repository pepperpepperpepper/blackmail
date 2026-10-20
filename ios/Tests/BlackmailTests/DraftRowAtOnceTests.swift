import XCTest
@testable import Blackmail

/// Save Draft's row in Drafts comes as the sheet goes (B-087), as Mail's
/// Drafts shows a draft saved at once: in place of the copy the letter was
/// reopened from, with a connection or without, and without waiting for the
/// save to be answered. Once the save has landed the list has one row for
/// the letter, its copy on the server, and never two on the way.
///
/// It used to come only once the sheet let go of the letter, after the save
/// had been answered: with no connection, the seconds the connect took to
/// fail, with the old copy's row in its place meanwhile, and for a new
/// letter no row at all.
///
/// These run the composer's own wiring (`ComposeActions(letter:…)`), the
/// shipping `LocalDrafts` over a store in a directory of the test's own,
/// and the shipping repository over the scripted server. Drafts is drawn
/// as the list draws it from what `LocalDrafts` posts (`DraftsOnScreen`).
@MainActor
final class DraftRowAtOnceTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "DraftRowAtOnceTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var line: RowLine!
    private var clock: ManualClock!
    private var keptClock: ManualClock!
    private var root: URL!
    private var background = FakeBackground()
    private var passTime = FakeBackground()
    private var pauses = Held()

    override func setUp() async throws {
        try await super.setUp()
        server = ScriptedIMAPServer()
        line = RowLine()
        clock = ManualClock()
        keptClock = ManualClock()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("DraftRowAtOnceTests-\(UUID().uuidString)", isDirectory: true)
        background = FakeBackground()
        passTime = FakeBackground()
        pauses = Held()
    }

    override func tearDown() async throws {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        if let root { try? FileManager.default.removeItem(at: root) }
        pauses.release()
        server = nil
        book = nil
        line = nil
        clock = nil
        keptClock = nil
        root = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeRepository() -> IMAPMailRepository {
        let imap = server.transportFactory
        let line = self.line!
        let clock = self.clock!
        return IMAPMailRepository(
            account: server.account, password: server.password,
            transport: { host, port in
                guard line.isUp else {
                    return port == 465 ? ScriptedSubmission(failsToOpen: true) : imap(host, 1)
                }
                return port == 465 ? ScriptedSubmission(failsToOpen: true) : imap(host, port)
            },
            recipients: book,
            now: { clock.now() },
            signatureImages: { [] },
            shelf: keptShelf(for: server.account))
    }

    private func makeKept() -> LocalDrafts {
        let clock = keptClock!
        let store = LocalDraftStore(root: root, now: {
            clock.advance(by: 1)
            return clock.now()
        })
        return LocalDrafts(store: store, account: server.username, background: passTime.time)
    }

    /// The composer's actions for letter `key`, wired as the composer wires
    /// them; `dismiss` is what the sheet's closing does.
    private func makeActions(_ key: String, kept: LocalDrafts, repository: MailRepository,
                             dismiss: @escaping () -> Void = {}) -> ComposeActions {
        kept.opened(key)
        return ComposeActions(letter: key, repository: repository, kept: kept,
                              dismiss: dismiss,
                              showError: { _ in },
                              draw: { _ in },
                              background: background.time,
                              wait: { [pauses] _ in try await pauses.wait() })
    }

    private func newLetter() -> Draft {
        var draft = Draft()
        draft.to = ["carlo@example.org"]
        draft.subject = "Sunday"
        draft.body = "Lunch at one?"
        return draft
    }

    /// Drafts' newest page, and "Unfinished 1" on it reopened and changed,
    /// as a tap on its row and a word typed make it.
    private func reopened(_ repository: IMAPMailRepository) async throws
        -> (rows: [MessageSummary], copy: MessageSummary, draft: Draft) {
        let rows = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        let copy = try XCTUnwrap(rows.first { $0.subject == "Unfinished 1" })
        var draft = try await repository.reopen(copy)
        draft.body = "Finished on the sofa."
        return (rows, copy, draft)
    }

    private func takeLineDown() async {
        line.isUp = false
        await server.resetConnections()
    }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    private func copies(_ subject: String) -> [UInt32] {
        server.uids(in: Server.drafts).filter {
            server.letter(uid: $0, in: Server.drafts)?.subject == subject
        }
    }

    // MARK: - As the sheet goes

    /// The iPad's case: Save Draft on a draft reopened from Drafts, with no
    /// connection. As the sheet goes its row is there, "On this iPad only",
    /// in place of the copy's, and stays once the save has failed: one row
    /// for the letter throughout. A new letter's row is there as its sheet
    /// goes too, above the rest.
    func testSaveDraftWithNoConnectionShowsItsRowAsTheSheetGoes() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let (rows, copy, draft) = try await reopened(repository)
        let drafts = DraftsOnScreen(kept: kept, rows: rows)
        defer { drafts.stop() }
        await takeLineDown()

        var asItGoes: [String] = []
        await makeActions("letter-1", kept: kept, repository: repository,
                          dismiss: { asItGoes = drafts.ids })
            .saveAndClose({ draft }, then: nil)?.value

        let others = rows.map(\.id).filter { $0 != copy.id }
        XCTAssertEqual(asItGoes, ["local:letter-1"] + others,
                       "its row in place of the copy's as the sheet goes")
        XCTAssertEqual(drafts.ids, ["local:letter-1"] + others, "and after the save has failed")
        XCTAssertTrue(drafts.list.shown.first?.preview.hasPrefix(LocalDraft.mark) ?? false)
        XCTAssertEqual(drafts.seen.map { $0.filter { !others.contains($0) }.count }.filter { $0 != 1 },
                       [], "one row for the letter at every redraw: \(drafts.seen)")
        XCTAssertEqual(kept.waiting.map(\.key), ["letter-1"], "nothing lost")

        var asTheNewOneGoes: [String] = []
        await makeActions("letter-2", kept: kept, repository: repository,
                          dismiss: { asTheNewOneGoes = drafts.ids })
            .saveAndClose({ [unowned self] in newLetter() }, then: nil)?.value
        XCTAssertEqual(asTheNewOneGoes, ["local:letter-2", "local:letter-1"] + others,
                       "a new letter's row as its sheet goes")
        XCTAssertEqual(copies("Sunday"), [])
    }

    /// With a connection: the row as the sheet goes, while the save is out,
    /// and once it lands the copy it became in its place, the old copy gone.
    /// One row for the letter at every redraw on the way, never two, and
    /// one copy of it on the server. No pass takes it meanwhile.
    func testASaveThatLandsGoesFromItsRowToItsCopyWithOneRowThroughout() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let (rows, copy, draft) = try await reopened(repository)
        let others = rows.map(\.id).filter { $0 != copy.id }
        let drafts = DraftsOnScreen(kept: kept, rows: rows)
        defer { drafts.stop() }

        server.holdReplies(to: "APPEND")
        var asItGoes: [String] = []
        let saving = try XCTUnwrap(makeActions("letter-1", kept: kept, repository: repository,
                                               dismiss: { asItGoes = drafts.ids })
            .saveAndClose({ draft }, then: nil))
        XCTAssertEqual(asItGoes, ["local:letter-1"] + others, "its row as the sheet goes")
        try await until { server.log.contains { $0.verb == "APPEND" } }
        XCTAssertEqual(drafts.ids, ["local:letter-1"] + others, "while the save is out")
        XCTAssertNil(kept.uploadWaiting(to: repository), "no pass takes it meanwhile")

        await server.releaseReplies(to: "APPEND")
        await saving.value
        let landed = try XCTUnwrap(copies("Unfinished 1").first)
        XCTAssertEqual(copies("Unfinished 1").count, 1)
        XCTAssertFalse(server.uids(in: Server.drafts).contains(UInt32(copy.id.split(separator: "/")[1])!),
                       "the old copy has gone")
        let landedID = "\(server.uidValidity(of: Server.drafts))/\(landed)"
        XCTAssertEqual(drafts.ids, [landedID] + others, "its copy in its place")
        XCTAssertFalse(drafts.list.shown.first?.preview.hasPrefix(LocalDraft.mark) ?? true)
        XCTAssertEqual(drafts.seen.map { $0.filter { !others.contains($0) }.count }.filter { $0 != 1 },
                       [], "one row for the letter at every redraw: \(drafts.seen)")
        XCTAssertEqual(kept.waiting.count, 0)
        XCTAssertNil(kept.store.letter("letter-1"), "off the iPad")
        XCTAssertEqual(server.log.filter { $0.verb == "APPEND" }.count, 1)
    }

    /// Listed as the sheet goes, it can be opened from its row while the
    /// save is still out. Then it is that composer's: the first sheet's
    /// save, answered, lets go of nothing that composer holds. Not listed
    /// while it is open, and no pass takes it, until that composer is done;
    /// then it is listed again, and goes up once.
    func testOpenedFromItsRowWhileTheSaveIsOutItStaysTheNewComposers() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let (rows, copy, draft) = try await reopened(repository)
        let others = rows.map(\.id).filter { $0 != copy.id }
        let drafts = DraftsOnScreen(kept: kept, rows: rows)
        defer { drafts.stop() }

        server.holdReplies(to: "APPEND")
        let saving = try XCTUnwrap(makeActions("letter-1", kept: kept, repository: repository)
            .saveAndClose({ draft }, then: nil))
        try await until { server.log.contains { $0.verb == "APPEND" } }
        XCTAssertEqual(drafts.ids, ["local:letter-1"] + others)

        // A tap on its row opens it again, and the line goes before the
        // save is answered.
        let opened = try XCTUnwrap(kept.letter("letter-1")).draft
        XCTAssertEqual(opened.body, "Finished on the sofa.")
        let again = makeActions("letter-1", kept: kept, repository: repository)
        server.stopHolding("APPEND")
        await takeLineDown()
        await saving.value
        XCTAssertNotNil(kept.store.letter("letter-1"), "the save failed: still on the iPad")

        XCTAssertEqual(kept.waiting.map(\.key), [], "open in the composer, so not listed")
        line.isUp = true
        _ = try await repository.listMessages(in: Server.inbox, beforeUID: nil, limit: 10)
        XCTAssertNil(kept.uploadWaiting(to: repository), "not while it is open in the composer")
        XCTAssertNil(kept.uploadWaiting(to: repository, for: .refresh))

        again.closeWithoutAsking { opened }
        XCTAssertEqual(kept.waiting.map(\.key), ["letter-1"], "listed again once he is done")
        await kept.uploadWaiting(to: repository)?.value
        XCTAssertEqual(copies("Unfinished 1").count, 1, "one copy: the cut-off one, taken as its own")
        XCTAssertEqual(kept.waiting.count, 0)
    }

    /// Put away, the letter is listed, and no pass takes it to the server
    /// until its save has been answered and the sheet lets go: the pass and
    /// the save would each take a version of it up. Then the next pass does.
    func testNoPassTakesALetterPutAwayUntilTheSheetLetsGo() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        _ = try await repository.listMessages(in: Server.inbox, beforeUID: nil, limit: 10)
        kept.opened("letter-1")
        let keeping = kept.keeping("letter-1", in: repository)
        keeping.keep(newLetter(), true)
        XCTAssertEqual(kept.waiting.map(\.key), [], "open in the sheet")
        keeping.putAway()
        XCTAssertEqual(kept.waiting.map(\.key), ["letter-1"], "listed as the sheet goes")
        XCTAssertNil(kept.uploadWaiting(to: repository), "held for the save")
        XCTAssertNil(kept.uploadWaiting(to: repository, for: .leaving))

        keeping.letGo()
        XCTAssertEqual(kept.waiting.map(\.key), ["letter-1"])
        await kept.uploadWaiting(to: repository)?.value
        XCTAssertEqual(copies("Sunday").count, 1)
        XCTAssertEqual(kept.waiting.count, 0)
    }
}

/// Drafts as the list draws it (`MessageListViewController.keptChanged`):
/// at every change posted, a letter that has landed drawn as its copy in
/// place of the copies that went, then the letters kept on the iPad above
/// the folder's, in place of the copies they stand for. `seen` is the rows
/// after each change, in order.
@MainActor
private final class DraftsOnScreen {

    let list = ListLetters()
    private(set) var seen: [[String]] = []
    private let kept: LocalDrafts
    private var watching: NSObjectProtocol?

    init(kept: LocalDrafts, rows: [MessageSummary]) {
        self.kept = kept
        _ = list.fetchedAfresh(rows)
        listKept()
        // Filtered here rather than by `object:`, which this Foundation does
        // not match for a block observer.
        watching = NotificationCenter.default.addObserver(
            forName: LocalDrafts.changed, object: nil, queue: nil) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, (note.object as AnyObject?) === self.kept else { return }
                self.changed(note)
            }
        }
    }

    /// The rows, top to bottom.
    var ids: [String] { list.shown.map(\.id) }

    func stop() {
        if let watching { NotificationCenter.default.removeObserver(watching) }
        watching = nil
    }

    private func changed(_ note: Notification) {
        if let landing = note.userInfo?[LocalDrafts.landingKey] as? DraftLanding {
            var copy: MessageSummary?
            if let letter = landing.letter, let id = landing.id {
                copy = letter.row(in: ScriptedIMAPServer.drafts, from: "Owner", onServerAs: id)
            }
            list.landed(copy, replacing: landing.replaced, atTop: true)
        }
        listKept()
        seen.append(ids)
    }

    private func listKept() {
        list.keep(kept.draftsRows(in: ScriptedIMAPServer.drafts, from: "Owner"),
                  replacing: kept.replacedInDrafts)
    }
}

/// Whether the network is there. With it down every connection is refused.
private final class RowLine: @unchecked Sendable {
    private let lock = NSLock()
    private var up = true

    var isUp: Bool {
        get { lock.lock(); defer { lock.unlock() }; return up }
        set { lock.lock(); up = newValue; lock.unlock() }
    }
}
