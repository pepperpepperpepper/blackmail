import XCTest
@testable import Blackmail

/// His Refresh sends what waits in the Outbox, as Mail's does (B-072): which
/// letters each kind of pass takes by their size, the Refresh's order, and
/// its wiring in the screens, read from their source as `SteadyChromeTests`
/// reads it. The passes themselves, over the scripted servers, are in
/// `OutboxTests`.
@MainActor
final class RefreshTapTests: XCTestCase {

    // MARK: - What each pass takes by size

    private func kept(outbox: Bool, files: [DraftAttachment], markup: Int = 0) -> LocalDraft {
        var draft = Draft()
        draft.to = ["carlo@example.org"]
        draft.subject = "Sunday"
        draft.attachments = files
        var letter = LocalDraft(key: "letter-1", draft: draft, version: "1", tried: [],
                                unfinished: false, keptAt: Date(), account: nil, gone: false,
                                outbox: outbox ? "<letter-1@example.com>" : nil)
        letter.markupBytes = markup
        return letter
    }

    /// A forward's file, fetched from Gmail before the letter is built.
    private func fromGmail(_ size: Int64?) -> DraftAttachment {
        DraftAttachment(source: .messagePart(messageID: "600001/1004", mailboxID: "INBOX",
                                             section: "2"),
                        filename: "Garden.mov", mimeType: "video/quicktime", size: size)
    }

    /// A photo on the iPad.
    private func onTheIPad(_ size: Int64) -> DraftAttachment {
        DraftAttachment(source: .localFile(URL(fileURLWithPath: "/nowhere/Garden.jpg")),
                        filename: "Garden.jpg", mimeType: "image/jpeg", size: size)
    }

    /// For each letter, whether a pass nobody asked for, his Refresh and
    /// his leaving take it. Only a large letter in the Outbox changes: his
    /// Refresh takes it now. A large draft still waits for him to leave.
    func testWhatEachPassTakesBySize() async {
        let cases: [(String, LocalDraft, [Bool])] = [
            ("Outbox, 2 MB from Gmail", kept(outbox: true, files: [fromGmail(2_000_000)]),
             [false, true, true]),
            ("Outbox, a file from Gmail of no known size", kept(outbox: true, files: [fromGmail(nil)]),
             [false, true, true]),
            ("Outbox, exactly a megabyte from Gmail",
             kept(outbox: true, files: [fromGmail(Int64(ComposeActions.countsFrom))]),
             [false, true, true]),
            ("Outbox, a byte under it", kept(outbox: true,
                                            files: [fromGmail(Int64(ComposeActions.countsFrom - 1))]),
             [true, true, true]),
            ("Outbox, 2 MB of photos on the iPad", kept(outbox: true, files: [onTheIPad(2_000_000)]),
             [true, true, true]),
            ("Outbox, nothing", kept(outbox: true, files: []), [true, true, true]),
            ("Draft, 2 MB of photos", kept(outbox: false, files: [onTheIPad(2_000_000)]),
             [false, false, true]),
            ("Draft, 2 MB from Gmail", kept(outbox: false, files: [fromGmail(2_000_000)]),
             [false, false, true]),
            ("Draft, a megabyte of quote", kept(outbox: false, files: [], markup: 1_000_000),
             [false, false, true]),
            ("Draft, nothing", kept(outbox: false, files: []), [true, true, true]),
        ]
        for (name, letter, expected) in cases {
            let taken = [LocalDrafts.Pass.unasked, .refresh, .leaving].map { letter.goes(by: $0) }
            XCTAssertEqual(taken, expected, name)
        }
    }

    // MARK: - The order

    /// What `RefreshTap.run` did, in order.
    private final class Said {
        var lines: [String] = []
    }

    /// The page first, its answer, then the counts, and once the page's
    /// previews and the counts have come, the pass.
    func testThePageAndTheCountsGoBeforeThePass() async {
        let said = Said()
        await RefreshTap.run(page: { said.lines.append("page"); return true },
                             answered: { said.lines.append("answered") },
                             counts: { said.lines.append($0 ? "counts quietly" : "counts") },
                             shown: { said.lines.append("shown") },
                             pass: { said.lines.append("pass") })
        XCTAssertEqual(said.lines, ["page", "answered", "counts", "shown", "pass"])
    }

    /// A page that did not come sets no pass off, as before: there is no
    /// connection for one. The counts are asked for all the same, quietly
    /// (B-103).
    func testAPageThatDidNotComeSetsNoPassOff() async {
        let said = Said()
        await RefreshTap.run(page: { said.lines.append("page"); return false },
                             answered: { said.lines.append("answered") },
                             counts: { said.lines.append($0 ? "counts quietly" : "counts") },
                             shown: { said.lines.append("shown") },
                             pass: { said.lines.append("pass") })
        XCTAssertEqual(said.lines, ["page", "answered", "counts quietly"])
    }

    private struct Refused: Error {}

    /// The page's answer is told once, as soon as the page has answered,
    /// before the counts and the pass, whether it came, did not come or was
    /// put aside for another list, which the page says as not come, or threw
    /// (B-103). The pull's spinner ends there.
    func testThePageIsAnsweredOnceBeforeTheCountsAndThePass() async {
        let outcomes: [(String, () throws -> Bool, [String])] = [
            ("came", { true }, ["page", "answered", "counts", "shown", "pass"]),
            ("did not come, or put aside", { false }, ["page", "answered", "counts quietly"]),
            ("threw", { throw Refused() }, ["page", "answered", "counts quietly"]),
        ]
        for (name, outcome, expected) in outcomes {
            let said = Said()
            await RefreshTap.run(page: { said.lines.append("page"); return try outcome() },
                                 answered: { said.lines.append("answered") },
                                 counts: { said.lines.append($0 ? "counts quietly" : "counts") },
                                 shown: { said.lines.append("shown") },
                                 pass: { said.lines.append("pass") })
            XCTAssertEqual(said.lines, expected, name)
        }
    }

    /// The answer does not wait for the counts or the pass: it is told while
    /// the page's previews and the counts are still on their way, and a large
    /// letter in the Outbox after them.
    func testTheAnswerDoesNotWaitForTheCountsOrThePass() async throws {
        let said = Said()
        let shown = Held()
        let run = Task { @MainActor in
            await RefreshTap.run(page: { true },
                                 answered: { said.lines.append("answered") },
                                 counts: { said.lines.append($0 ? "counts quietly" : "counts") },
                                 shown: { try? await shown.wait() },
                                 pass: { said.lines.append("pass") })
        }
        try await until { shown.waiting == 1 }
        XCTAssertEqual(said.lines, ["answered", "counts"])
        shown.release()
        await run.value
        XCTAssertEqual(said.lines, ["answered", "counts", "pass"])
    }

    /// The pass waits for the previews and the counts however long they
    /// take, and goes once they have come.
    func testThePassWaitsForWhatHeAskedToSee() async throws {
        let said = Said()
        let shown = Held()
        let tap = Task { @MainActor in
            await RefreshTap.run(page: { true },
                                 answered: {},
                                 counts: { said.lines.append($0 ? "counts quietly" : "counts") },
                                 shown: {
                                     try? await shown.wait()
                                     said.lines.append("shown")
                                 },
                                 pass: { said.lines.append("pass") })
        }
        for _ in 0..<1_000 where shown.waiting == 0 {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(shown.waiting, 1)
        XCTAssertEqual(said.lines, ["counts"], "no pass while they come")
        shown.release()
        await tap.value
        XCTAssertEqual(said.lines, ["counts", "shown", "pass"])
    }

    // MARK: - One page at a time (B-103)

    /// Polls, a millisecond at a time for up to a second, until `done`.
    private func until(_ done: () -> Bool,
                       file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<1_000 where !done() {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(done(), "never", file: file, line: line)
    }

    /// What the runs did: pages asked for, how many were out at once at
    /// most, and each run's answer, counts and pass.
    private final class Runs {
        var pages = 0
        var out = 0
        var mostOut = 0
        var answered = 0
        var counts = 0
        var quietCounts = 0
        var passes = 0
    }

    /// A Refresh started through `gate`, its page `page`, its previews and
    /// counts `shown`, everything it does counted in `runs`.
    @discardableResult
    private func start(_ gate: RefreshTap.Gate, _ runs: Runs,
                       page: @escaping @MainActor () async throws -> Bool = { true },
                       shown: @escaping @MainActor () async -> Void = {}) -> Task<Void, Never>? {
        RefreshTap.start(gate: gate,
                         page: {
                             runs.pages += 1
                             runs.out += 1
                             runs.mostOut = max(runs.mostOut, runs.out)
                             defer { runs.out -= 1 }
                             return try await page()
                         },
                         answered: { runs.answered += 1 },
                         counts: { quietly in
                             runs.counts += 1
                             if quietly { runs.quietCounts += 1 }
                         },
                         shown: shown,
                         pass: { runs.passes += 1 })
    }

    /// A page that does not answer, and a second tap or pull meanwhile: no
    /// second page. Once it answers, Refresh is free again.
    func testASecondRefreshWhileThePageIsOutStartsNothing() async throws {
        let gate = RefreshTap.Gate()
        let runs = Runs()
        let page = Held()
        let first = try XCTUnwrap(start(gate, runs, page: { try await page.wait(); return true }))
        try await until { page.waiting == 1 }
        XCTAssertTrue(gate.held)
        XCTAssertNil(start(gate, runs), "a second while the page is out")
        XCTAssertNil(start(gate, runs), "and a third")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(runs.pages, 1)
        XCTAssertEqual(runs.answered, 0)

        page.release()
        await first.value
        XCTAssertFalse(gate.held)
        XCTAssertEqual(runs.answered, 1)
        let next = try XCTUnwrap(start(gate, runs), "free once the page has answered")
        await next.value
        XCTAssertEqual(runs.pages, 2)
    }

    /// The gate is held around the page alone: once it has answered, a tap
    /// or a pull starts a new page while the first run still waits for its
    /// previews and its counts, as a second tap did before.
    func testOnceThePageHasAnsweredANewRefreshStartsWhileTheFirstWaits() async throws {
        let gate = RefreshTap.Gate()
        let runs = Runs()
        let shown = Held()
        let first = try XCTUnwrap(start(gate, runs, shown: { try? await shown.wait() }))
        try await until { shown.waiting == 1 }
        XCTAssertFalse(gate.held, "let go at the answer")
        XCTAssertEqual(runs.answered, 1)
        XCTAssertEqual(runs.passes, 0)

        let second = try XCTUnwrap(start(gate, runs, shown: { try? await shown.wait() }))
        try await until { shown.waiting == 2 }
        XCTAssertEqual(runs.pages, 2)
        XCTAssertEqual(runs.answered, 2)
        shown.release()
        await first.value
        await second.value
        XCTAssertEqual(runs.passes, 2)
        XCTAssertFalse(gate.held)
    }

    /// A run whose page throws lets go of the gate, and so does one whose
    /// task is cancelled while its page is out. Each is answered once.
    func testARunThatThrowsOrIsCancelledLetsGo() async throws {
        let gate = RefreshTap.Gate()
        let runs = Runs()
        let threw = try XCTUnwrap(start(gate, runs, page: { throw Refused() }))
        await threw.value
        XCTAssertFalse(gate.held, "thrown")
        XCTAssertEqual(runs.answered, 1)
        XCTAssertEqual(runs.passes, 0)

        let cancelled = try XCTUnwrap(start(gate, runs, page: {
            try await Task.sleep(for: .seconds(3_600))
            return true
        }))
        try await until { runs.out == 1 }
        XCTAssertTrue(gate.held)
        cancelled.cancel()
        await cancelled.value
        XCTAssertFalse(gate.held, "cancelled")
        XCTAssertEqual(runs.answered, 2)
        XCTAssertEqual(runs.passes, 0)

        let next = try XCTUnwrap(start(gate, runs))
        await next.value
        XCTAssertEqual(runs.pages, 3)
        XCTAssertEqual(runs.passes, 1)
    }

    /// His Refresh's counts are asked for quietly after a page that did not
    /// come, thrown or not, and as before after one that came (B-103). With
    /// no connection the sweep failed at once, and in three panes its own
    /// "Can't connect to mail server." came up from the Mailboxes under the
    /// pull's finger, while the page's waited for the finger to let go: the
    /// list would lose the end of its drag, as it did on the iPad on
    /// 2026-10-22, and stay pulled down with the spinner turning. The
    /// page's alert says what failed. Through `start`, the one way in.
    func testAPageThatDidNotComeAsksForTheCountsQuietly() async throws {
        let outcomes: [(String, @MainActor () async throws -> Bool, Bool)] = [
            ("came", { true }, false),
            ("did not come", { false }, true),
            ("threw", { throw Refused() }, true),
        ]
        for (name, page, quiet) in outcomes {
            let gate = RefreshTap.Gate()
            let runs = Runs()
            let run = try XCTUnwrap(start(gate, runs, page: page), name)
            await run.value
            XCTAssertEqual(runs.counts, 1, name)
            XCTAssertEqual(runs.quietCounts, quiet ? 1 : 0, name)
        }

        // The list hands it on, and the container asks the folder pane for
        // the counts as it is told: quietly, the sweep puts up no alert.
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains("counts: { quietly in self.onRefreshRequested?(quietly) },"))
        XCTAssertTrue(list.contains("var onRefreshRequested: ((_ quietly: Bool) -> Void)?"))
        XCTAssertEqual(count("onRefreshRequested?(", in: list), 1)
        let root = try source("UI/RootViewController.swift")
        XCTAssertTrue(root.contains("list.onRefreshRequested = { [weak self] quietly in "
                                    + "self?.refreshMailboxes(quietly: quietly) }"))
        XCTAssertTrue(root.contains("private func refreshMailboxes(quietly: Bool = false) { "
                                    + "mailboxList.select(mailboxID: list.mailboxID) "
                                    + "mailboxList.refreshCounts(quietly: quietly) }"))
        let folders = try source("UI/MailboxListViewController.swift")
        XCTAssertTrue(folders.contains(
            "} catch { if !quietly { ErrorPresenter.show(reaching: error, on: self) } } }"))
    }

    /// A run lets go of its own hold only. The first run ends, its previews
    /// and counts come, while a second run's page is out: the gate stays the
    /// second's, and a third Refresh meanwhile starts nothing.
    func testARunEndingLetsGoOfItsOwnHoldOnly() async throws {
        let gate = RefreshTap.Gate()
        let runs = Runs()
        let shown = Held()
        let page = Held()
        let first = try XCTUnwrap(start(gate, runs, shown: { try? await shown.wait() }))
        try await until { shown.waiting == 1 }
        let second = try XCTUnwrap(start(gate, runs, page: { try await page.wait(); return true }))
        try await until { page.waiting == 1 }

        shown.release()
        await first.value
        XCTAssertEqual(runs.passes, 1)
        XCTAssertTrue(gate.held, "still the second run's")
        XCTAssertNil(start(gate, runs))
        XCTAssertEqual(runs.pages, 2)

        page.release()
        await second.value
        XCTAssertFalse(gate.held)
    }

    /// Thirty in a row, each tapped twice while its page is out, and each
    /// run's previews and counts left waiting: thirty pages, never two out
    /// at once, and Refresh free after them.
    func testThirtyInARowAreThirtyPagesNeverTwoAtOnce() async throws {
        let gate = RefreshTap.Gate()
        let runs = Runs()
        let page = Held()
        let shown = Held()
        var started: [Task<Void, Never>] = []
        for round in 1...30 {
            let run = try XCTUnwrap(start(gate, runs, page: { try await page.wait(); return true },
                                          shown: { try? await shown.wait() }), "round \(round)")
            started.append(run)
            try await until { page.waiting == 1 }
            XCTAssertNil(start(gate, runs), "round \(round)")
            page.release()
            try await until { shown.waiting == round }
        }
        XCTAssertEqual(runs.pages, 30)
        XCTAssertEqual(runs.mostOut, 1)
        XCTAssertEqual(runs.answered, 30)
        XCTAssertEqual(runs.counts, 30)
        XCTAssertEqual(runs.passes, 0)
        shown.release()
        for run in started { await run.value }
        XCTAssertEqual(runs.passes, 30)

        let after = try XCTUnwrap(start(gate, runs))
        await after.value
        XCTAssertEqual(runs.pages, 31)
        XCTAssertFalse(gate.held)
    }

    // MARK: - The wiring, read from the source

    /// A file of the app's sources, comment lines dropped and whitespace
    /// run together, as `SteadyChromeTests` reads them.
    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    private func count(_ text: String, in code: String) -> Int {
        code.components(separatedBy: text).count - 1
    }

    /// Refresh fetches the page with no pass of its own, asks for the
    /// counts, waits for the page's previews and the counts, and then asks
    /// for the pass with the Refresh's kind. The page's pass goes as before
    /// for every other page, and the previews it waits for are the page's.
    func testRefreshAsksForItsPassAfterThePageAndTheCounts() async throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains(
            "RefreshTap.start( gate: refreshes, "
            + "page: { let checking = self.isOutbox ? nil : self.working(StatusLine.checking) "
            + "defer { checking?() } await self.repository.forgetLettersOfHis() "
            + "return await self.reload(passing: false) }, "
            + "answered: { self.endPullAtRest() }, "
            + "counts: { quietly in self.onRefreshRequested?(quietly) }, "
            + "shown: { await self.pagePreviews?.value await self.countsCame() }, "
            + "pass: { _ = self.kept.uploadWaiting(to: self.repository, for: .refresh) }) }"))
        XCTAssertTrue(list.contains("func reload(keepingPlace: Bool = false, quietly: Bool = false, "
                                    + "passing: Bool = true) async -> Bool"))
        XCTAssertEqual(count("if passing { kept.uploadWaiting(to: repository) }", in: list), 2,
                       "the Outbox's and the page's, each only when it is not his Refresh")
        XCTAssertEqual(count("kept.uploadWaiting(to: repository)", in: list), 3,
                       "those two and the kept page's, all nobody's")
        XCTAssertTrue(list.contains("pagePreviews = loadPreviews(for: unpreviewed)"))
    }

    /// The container hands the list the counts to wait for, and every other
    /// pass keeps its kind: coming back and the watch's check nobody's, and
    /// leaving the app's own. Refresh is the one pass of its kind.
    func testEveryOtherPassKeepsItsKind() async throws {
        let root = try source("UI/RootViewController.swift")
        XCTAssertTrue(root.contains("list.countsCame = { [weak self] in "
                                    + "await self?.mailboxList.countsSwept() }"))
        XCTAssertEqual(count("LocalDrafts.shared.uploadWaiting(to: repository)", in: root), 2,
                       "coming back and the watch's check")
        XCTAssertEqual(count("LocalDrafts.shared.uploadWaiting(to: repository, for: .leaving)",
                             in: root), 1)

        let folders = try source("UI/MailboxListViewController.swift")
        XCTAssertTrue(folders.contains("func countsSwept() async { await sweeps.idle() }"))

        var refreshes = 0
        for folder in ["UI", "App", "Share"] {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/Blackmail/\(folder)")
            for name in try FileManager.default.contentsOfDirectory(atPath: url.path)
            where name.hasSuffix(".swift") {
                refreshes += count("for: .refresh", in: try source("\(folder)/\(name)"))
            }
        }
        XCTAssertEqual(refreshes, 1, "his Refresh's alone")
    }
}
