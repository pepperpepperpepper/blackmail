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
    private var submissions: RowSubmissions!
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
        submissions = RowSubmissions()
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
        submissions = nil
        clock = nil
        keptClock = nil
        root = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeRepository() -> IMAPMailRepository {
        let imap = server.transportFactory
        let line = self.line!
        let submissions = self.submissions!
        let clock = self.clock!
        return IMAPMailRepository(
            account: server.account, password: server.password,
            transport: { host, port in
                guard line.isUp else {
                    return port == 465 ? ScriptedSubmission(failsToOpen: true) : imap(host, 1)
                }
                return port == 465 ? submissions.next() : imap(host, port)
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

    /// Drafts' newest page, and `subject` on it reopened and changed, as a
    /// tap on its row and a word typed make it.
    private func reopened(_ repository: IMAPMailRepository, _ subject: String = "Unfinished 1")
        async throws -> (rows: [MessageSummary], copy: MessageSummary, draft: Draft) {
        let rows = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        let copy = try XCTUnwrap(rows.first { $0.subject == subject })
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

    /// The id of the copy in Drafts with `uid`, as its row has it.
    private func row(_ uid: UInt32) -> String {
        "\(server.uidValidity(of: Server.drafts))/\(uid)"
    }

    /// Save Draft on `draft` as `key`, its APPEND held, its row tapped while
    /// the save is out, and the save let land while the composer the tap
    /// opened has the letter. Returns that composer, what it opened with,
    /// and the row of the copy the save became. `meanwhile` is done after
    /// the tap and before the save lands.
    private func openedAsItsSaveLands(_ draft: Draft, as key: String = "letter-1",
                                      kept: LocalDrafts, repository: IMAPMailRepository,
                                      dismiss: @escaping () -> Void = {},
                                      meanwhile: () -> Void = {}) async throws
        -> (again: ComposeActions, opened: Draft, landed: String) {
        let appends = server.log.filter { $0.verb == "APPEND" }.count
        server.holdReplies(to: "APPEND")
        let saving = try XCTUnwrap(makeActions(key, kept: kept, repository: repository)
            .saveAndClose({ draft }, then: nil))
        try await until { server.log.filter { $0.verb == "APPEND" }.count > appends }
        let opened = try XCTUnwrap(kept.letter(key)).draft
        let again = makeActions(key, kept: kept, repository: repository, dismiss: dismiss)
        meanwhile()
        await server.releaseReplies(to: "APPEND")
        await saving.value
        let landed = try XCTUnwrap(copies(draft.subject).first)
        XCTAssertEqual(copies(draft.subject).count, 1)
        XCTAssertNotNil(kept.store.letter(key), "on the iPad while the composer has it")
        return (again, opened, row(landed))
    }

    /// How many rows each redraw had for the letter, of those that had
    /// other than one: none, when every redraw had one.
    private func notOneRow(_ drafts: DraftsOnScreen, others: [String]) -> [Int] {
        drafts.seen.map { $0.filter { !others.contains($0) }.count }.filter { $0 != 1 }
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

    /// Opened from its row while its save is out, and the save lands while
    /// the composer the tap opened has it: the copy it became is its row
    /// while that composer is open. Changed there and saved again, it is
    /// listed as that sheet goes in place of that copy, not beside it, and
    /// so while the second save is out, though the letter still names the
    /// copy it was first reopened from: that copy is the letter's own, put
    /// up by this launch, and its next upload replaces it (`LocalDrafts.landed`).
    /// Then the copy the second save became. One row for the letter at
    /// every redraw, and one copy of it on the server.
    func testSavedAgainFromItsRowAfterItsSaveLandedHasOneRowThroughout() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let (rows, copy, draft) = try await reopened(repository)
        let others = rows.map(\.id).filter { $0 != copy.id }
        let drafts = DraftsOnScreen(kept: kept, rows: rows)
        defer { drafts.stop() }

        var asItGoes: [String] = []
        let (again, opened, first) = try await openedAsItsSaveLands(
            draft, kept: kept, repository: repository, dismiss: { asItGoes = drafts.ids })
        XCTAssertEqual(drafts.ids, [first] + others, "its copy, while the composer has it")
        XCTAssertEqual(opened.savedID, copy.id, "it still names the copy it was reopened from")

        var changed = opened
        changed.body += "\nAnd a second line."
        server.holdReplies(to: "APPEND")
        let saving = try XCTUnwrap(again.saveAndClose({ changed }, then: nil))
        XCTAssertEqual(asItGoes, ["local:letter-1"] + others,
                       "its row in place of that copy as the sheet goes")
        try await until { server.log.filter { $0.verb == "APPEND" }.count == 2 }
        XCTAssertEqual(drafts.ids, ["local:letter-1"] + others, "while the second save is out")

        await server.releaseReplies(to: "APPEND")
        await saving.value
        let last = try XCTUnwrap(copies("Unfinished 1").first)
        XCTAssertEqual(copies("Unfinished 1").count, 1, "one copy on the server")
        XCTAssertNotEqual(row(last), first)
        XCTAssertEqual(drafts.ids, [row(last)] + others, "the copy it became")
        XCTAssertEqual(notOneRow(drafts, others: others), [],
                       "one row for the letter at every redraw: \(drafts.seen)")
        XCTAssertNil(kept.store.letter("letter-1"), "off the iPad")
    }

    /// The same with no connection for the second save: its row in place
    /// of the copy the first became, as the sheet goes and once the save
    /// has failed, until a pass takes it up and that copy is replaced.
    func testSavedAgainOfflineFromItsRowAfterItsSaveLandedHasOneRowUntilItGoes() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let (rows, copy, draft) = try await reopened(repository)
        let others = rows.map(\.id).filter { $0 != copy.id }
        let drafts = DraftsOnScreen(kept: kept, rows: rows)
        defer { drafts.stop() }

        var asItGoes: [String] = []
        let (again, opened, first) = try await openedAsItsSaveLands(
            draft, kept: kept, repository: repository, dismiss: { asItGoes = drafts.ids })
        var changed = opened
        changed.body += "\nWritten on the train."
        await takeLineDown()
        await again.saveAndClose({ changed }, then: nil)?.value
        XCTAssertEqual(asItGoes, ["local:letter-1"] + others, "as the sheet goes")
        XCTAssertEqual(drafts.ids, ["local:letter-1"] + others, "and once the save has failed")
        XCTAssertEqual(copies("Unfinished 1").map(row), [first], "that copy still on the server")
        XCTAssertEqual(kept.letter("letter-1")?.draft.body, changed.body)

        line.isUp = true
        _ = try await repository.listMessages(in: Server.inbox, beforeUID: nil, limit: 10)
        await kept.uploadWaiting(to: repository)?.value
        let last = try XCTUnwrap(copies("Unfinished 1").first)
        XCTAssertEqual(copies("Unfinished 1").count, 1, "that copy replaced")
        XCTAssertEqual(drafts.ids, [row(last)] + others)
        XCTAssertEqual(notOneRow(drafts, others: others), [],
                       "one row for the letter at every redraw: \(drafts.seen)")
    }

    /// Sent from the composer its row opened, after its save had landed
    /// there: as the sheet closes Drafts has no row for the letter just
    /// sent, the copy that save put up included, though Send names only
    /// the copy it was reopened from (`ComposeActions.send`'s `draftSent`).
    /// Tapped, that row would open the letter to be sent a second time.
    /// Then that copy is removed, and the letter has gone once.
    func testSentFromItsRowAfterItsSaveLandedLeavesNoRowAsTheSheetCloses() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let (rows, copy, draft) = try await reopened(repository)
        let others = rows.map(\.id).filter { $0 != copy.id }
        let drafts = DraftsOnScreen(kept: kept, rows: rows)
        defer { drafts.stop() }

        var asItCloses: [String] = []
        let (again, opened, first) = try await openedAsItsSaveLands(
            draft, kept: kept, repository: repository, dismiss: { asItCloses = drafts.ids })
        XCTAssertEqual(drafts.ids, [first] + others)

        var named: [String] = []
        var asItsCopyIsTakenOff: [String] = []
        await again.send({ opened }, then: nil, draftSent: { id in
            named.append(id)
            drafts.sent(id)
            asItsCopyIsTakenOff = drafts.ids
        })?.value
        XCTAssertEqual(named, [copy.id], "Send names the copy it was reopened from")
        XCTAssertEqual(asItCloses, others, "no row for the letter as the sheet closes")
        XCTAssertEqual(asItsCopyIsTakenOff, others)
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(copies("Unfinished 1"), [], "the copy its save put up removed")
        XCTAssertEqual(drafts.ids, others)
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// The same sent with no connection, so that it waits in the Outbox:
    /// as the sheet closes and while it waits, Drafts has no row for it,
    /// the copy its save put up included, though the letter in the Outbox
    /// names only the copy it was reopened from. Listed, that row would
    /// open the letter waiting in the Outbox, to be sent a second time.
    /// With the line back, the pass sends it once and removes that copy,
    /// and nothing is left on the iPad.
    func testSentOfflineFromItsRowAfterItsSaveLandedLeavesNoRowWhileItWaitsInTheOutbox()
        async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let (rows, copy, draft) = try await reopened(repository)
        let others = rows.map(\.id).filter { $0 != copy.id }
        let drafts = DraftsOnScreen(kept: kept, rows: rows)
        defer { drafts.stop() }

        var asItCloses: [String] = []
        let (again, opened, first) = try await openedAsItsSaveLands(
            draft, kept: kept, repository: repository, dismiss: { asItCloses = drafts.ids })
        XCTAssertEqual(drafts.ids, [first] + others)

        await takeLineDown()
        await again.send({ opened }, then: nil, draftSent: { drafts.sent($0) })?.value
        XCTAssertEqual(kept.outbox.map(\.key), ["letter-1"], "waiting in the Outbox")
        XCTAssertEqual(kept.landed["letter-1"], first, "the copy its save put up, still kept")
        XCTAssertEqual(copies("Unfinished 1").map(row), [first], "and still in Drafts")
        XCTAssertEqual(asItCloses, others, "no row for the letter as the sheet closes")
        XCTAssertEqual(drafts.ids, others, "nor while it waits")
        let none = await submissions.letters()
        XCTAssertEqual(none.count, 0)

        line.isUp = true
        _ = try await repository.listMessages(in: Server.inbox, beforeUID: nil, limit: 10)
        await kept.uploadWaiting(to: repository)?.value
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1, "sent once")
        XCTAssertEqual(copies("Unfinished 1"), [], "the copy its save put up removed")
        XCTAssertEqual(drafts.ids, others)
        XCTAssertEqual(kept.store.letters().count, 0, "nothing left on the iPad")
    }

    /// Opened from its row while a pass is taking it up, then changed and
    /// saved once the pass has landed it: its row in place of the copy the
    /// pass put up as the sheet goes, not beside it, then the copy the save
    /// became. One row for the letter at every redraw.
    func testOpenedWhileAPassTakesItUpThenSavedHasOneRowThroughout() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let (rows, copy, draft) = try await reopened(repository)
        let others = rows.map(\.id).filter { $0 != copy.id }
        let drafts = DraftsOnScreen(kept: kept, rows: rows)
        defer { drafts.stop() }
        await takeLineDown()
        await makeActions("letter-1", kept: kept, repository: repository)
            .saveAndClose({ draft }, then: nil)?.value
        XCTAssertEqual(drafts.ids, ["local:letter-1"] + others)

        line.isUp = true
        _ = try await repository.listMessages(in: Server.inbox, beforeUID: nil, limit: 10)
        server.holdReplies(to: "APPEND")
        let pass = try XCTUnwrap(kept.uploadWaiting(to: repository))
        try await until { server.log.contains { $0.verb == "APPEND" } }
        let opened = try XCTUnwrap(kept.letter("letter-1")).draft
        var asItGoes: [String] = []
        let again = makeActions("letter-1", kept: kept, repository: repository,
                                dismiss: { asItGoes = drafts.ids })
        await server.releaseReplies(to: "APPEND")
        await pass.value
        let first = try XCTUnwrap(copies("Unfinished 1").first)
        XCTAssertEqual(drafts.ids, [row(first)] + others, "the copy the pass put up")

        var changed = opened
        changed.body += "\nAnd a second line."
        await again.saveAndClose({ changed }, then: nil)?.value
        XCTAssertEqual(asItGoes, ["local:letter-1"] + others,
                       "its row in place of that copy as the sheet goes")
        let last = try XCTUnwrap(copies("Unfinished 1").first)
        XCTAssertEqual(copies("Unfinished 1").count, 1)
        XCTAssertEqual(drafts.ids, [row(last)] + others)
        XCTAssertEqual(notOneRow(drafts, others: others), [],
                       "one row for the letter at every redraw: \(drafts.seen)")
    }

    /// The copy a letter's upload put up stands for it only under the
    /// password that upload went with. With a password saved since, the
    /// same folder and UID may be another draft in another mailbox under
    /// the same address (B-033), and it is listed, as a copy the letter
    /// names by folder and UID alone is (`LocalDrafts.replacedInDrafts`):
    /// hidden, it could not be seen or opened for as long as the letter
    /// waited. So for a copy that landed before the save, and for one whose
    /// upload went before the save and landed after it.
    func testACopyThatLandedStandsForTheLetterOnlyUnderItsOwnPassword() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let first = try await reopened(repository, "Unfinished 1").draft
        let (sheet, opened, landed) = try await openedAsItsSaveLands(
            first, kept: kept, repository: repository)
        var changed = opened
        changed.body += "\nAnd a second line."
        sheet.edited { changed }
        sheet.sheetGone { changed }
        XCTAssertEqual(kept.waiting.map(\.key), ["letter-1"])
        XCTAssertTrue(kept.replacedInDrafts.keys.contains(landed), "its own, under this password")

        LocalDraftStore.notePasswordSaved(in: root)
        kept.passwordSaved()
        XCTAssertFalse(kept.replacedInDrafts.keys.contains(landed),
                       "landed before a password saved since")

        let second = try await reopened(repository, "Unfinished 2").draft
        let (other, otherOpened, after) = try await openedAsItsSaveLands(
            second, as: "letter-2", kept: kept, repository: repository, meanwhile: {
                LocalDraftStore.notePasswordSaved(in: root)
                kept.passwordSaved()
            })
        var otherChanged = otherOpened
        otherChanged.body += "\nAnd a second line."
        other.edited { otherChanged }
        other.sheetGone { otherChanged }
        XCTAssertEqual(Set(kept.waiting.map(\.key)), ["letter-1", "letter-2"])
        XCTAssertFalse(kept.replacedInDrafts.keys.contains(after),
                       "gone up before a password saved since, landed after it")
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

    /// The composer's `draftSent`, as the list takes it
    /// (`MessageListViewController.presentComposer`): the row of the copy
    /// named taken off, as a removal on its way.
    func sent(_ id: String) {
        guard let row = list.letter(id) else { return }
        list.take(row, fromEveryFolder: false)
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

/// The submission server, one made for every connection, each taking
/// whatever it is sent.
private final class RowSubmissions: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [ScriptedSubmission] = []

    func next() -> ScriptedSubmission {
        let server = ScriptedSubmission()
        lock.lock()
        made.append(server)
        lock.unlock()
        return server
    }

    /// Every letter sent, across them all.
    func letters() async -> [Data] {
        lock.lock()
        let servers = made
        lock.unlock()
        var out: [Data] = []
        for server in servers { out += await server.letters }
        return out
    }
}
