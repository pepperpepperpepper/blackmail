import XCTest
@testable import Blackmail

/// The reading pane's downloads, without the web view: what is drawn before
/// a letter's body is asked for, which fetches are called off when he moves
/// on, and which answers may still be drawn. `PaneLoads` is what
/// `MessageDetailViewController` runs every letter and conversation through.
final class PaneLoadsTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "PaneLoadsTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        server = nil
        book = nil
        super.tearDown()
    }

    private func makeRepository() -> IMAPMailRepository {
        IMAPMailRepository(account: server.account, password: server.password,
                           transport: server.transportFactory, recipients: book)
    }

    /// Waits, a millisecond at a time and never for more than a second,
    /// until `condition` holds.
    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    private func uid(_ id: String) -> String { String(id.split(separator: "/").last ?? "") }

    // MARK: - P1: the letter he tapped, at the tap

    /// The stand-in, the row's sender, subject and date over "Loading…", is
    /// on screen before the body is asked for; the body replaces it when it
    /// comes. The pane used to be drawn only once the body had come, and
    /// until then held the previous letter.
    @MainActor
    func testTheLetterHeTappedIsDrawnBeforeItsBodyIsAskedFor() async throws {
        let loads = PaneLoads()
        let events = Events()
        loads.show(standIn: { events.add("stand-in") },
                   fetch: { events.add("fetch"); return "body" },
                   settle: { result in events.add("drawn \((try? result.get()) ?? "-")") })
        XCTAssertEqual(events.all, ["stand-in"])
        try await until { loads.inFlight == 0 }
        XCTAssertEqual(events.all, ["stand-in", "fetch", "drawn body"])
    }

    /// What the header says before the letter lands: the row's sender,
    /// subject and date, and the files the row lists, and nothing it does
    /// not know. The files are what the header is sized by; see
    /// `PaneDocumentTests.testTheHeaderListsTheLettersFilesFromItsRow`.
    func testTheStandInHeaderIsTheRowsSenderSubjectDateAndFiles() {
        var row = MessageSummary(id: "600001/1119", mailboxID: "inbox",
                                 sender: "Sam Example <sam@example.com>",
                                 subject: "Letter 119: garden", preview: "A few words",
                                 date: Server.newestDate, isRead: false, isFlagged: false,
                                 hasAttachment: true)
        let quote = Attachment(id: "2", filename: "Garden quote.pdf", mimeType: "application/pdf",
                               size: 3_000)
        row.attachments = [quote]
        let heading = Message.heading(for: row)
        XCTAssertEqual(heading.id, row.id)
        XCTAssertEqual(heading.mailboxID, row.mailboxID)
        XCTAssertEqual(heading.sender, row.sender)
        XCTAssertEqual(heading.senderAddress, "sam@example.com")
        XCTAssertEqual(heading.subject, row.subject)
        XCTAssertEqual(heading.date, row.date)
        XCTAssertEqual(heading.to, [])
        XCTAssertEqual(heading.cc, [])
        XCTAssertEqual(heading.attachments, [quote])
        XCTAssertNil(heading.textBody)
        XCTAssertNil(heading.htmlBody)
        // A conversation's header carries the thread's subject.
        XCTAssertEqual(Message.heading(for: row, subject: "The garden").subject, "The garden")
    }

    /// "Loading…" in the pane's grey, on its black; and with no words, the
    /// empty page the pane is cleared to, so that no letter is left behind
    /// in the web view for the next one to reveal.
    func testTheLoadingPageSaysSoAndTheEmptyPageSaysNothing() {
        let loading = PaneNotice.html([PaneNotice.loading])
        XCTAssertTrue(loading.contains("<p style=\"font-size:17px;\">Loading…</p>"), loading)
        XCTAssertTrue(loading.contains("background:#000;"))
        let empty = PaneNotice.html([])
        XCTAssertFalse(empty.contains("<p"), empty)
        XCTAssertTrue(empty.contains("background:#000;"))
        XCTAssertEqual(PaneNotice.html(["<b>&"]).contains("&lt;b&gt;&amp;"), true)
    }

    // MARK: - Moving on calls the last one off

    /// A fetch called off, or whose pane has moved on, draws nothing,
    /// whichever way it ended; a `CancellationError` never says the letter
    /// could not be downloaded; the current one is drawn, or says it failed.
    func testOnlyTheCurrentFetchIsDrawnAndACancelledOneNeverSaysItFailed() {
        let body: Result<String, Error> = .success("body")
        let failed: Result<String, Error> = .failure(MailError.cannotConnect)
        let cancelled: Result<String, Error> = .failure(CancellationError())

        XCTAssertTrue(PaneLoads.draws(body, cancelled: false, current: true))
        XCTAssertTrue(PaneLoads.draws(failed, cancelled: false, current: true))
        XCTAssertFalse(PaneLoads.draws(cancelled, cancelled: false, current: true))
        for outcome in [body, failed, cancelled] {
            XCTAssertFalse(PaneLoads.draws(outcome, cancelled: true, current: true))
            XCTAssertFalse(PaneLoads.draws(outcome, cancelled: false, current: false))
        }
    }

    /// A letter shown while the last one's body is still coming: the last
    /// fetch is cancelled, and when it answers anyway it draws nothing.
    /// Emptying the pane does the same.
    @MainActor
    func testShowingAnotherLetterOrEmptyingThePaneCallsOffTheFetchAndItDrawsNothing() async throws {
        let loads = PaneLoads()
        let events = Events()
        let gate = Gate()

        loads.show(standIn: {},
                   fetch: { () async throws -> String in
                       await gate.wait()
                       events.add(Task.isCancelled ? "first cancelled" : "first not cancelled")
                       return "first"
                   },
                   settle: { _ in events.add("first drawn") })
        loads.show(standIn: {}, fetch: { "second" },
                   settle: { result in events.add("drawn \((try? result.get()) ?? "-")") })
        try await until { loads.inFlight == 0 && gate.waiting }
        await gate.open()
        try await until { events.all.contains("first cancelled") || events.all.contains("first not cancelled") }
        await Task.yield()
        XCTAssertEqual(events.all, ["drawn second", "first cancelled"])

        let emptied = Events()
        loads.show(standIn: {}, fetch: { () async throws -> String in
                       try await Task.sleep(for: .milliseconds(5))
                       return "third"
                   },
                   settle: { _ in emptied.add("third drawn") })
        loads.supersede()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(emptied.all, [])
        XCTAssertEqual(loads.inFlight, 0)
    }

    // MARK: - The page made away from the main thread

    /// A letter's page is made while the main actor goes on, as the screen
    /// must: the preparation below holds until the main actor has run
    /// meanwhile, and for a second at most. It used to be made on the main
    /// thread as the letter came, where it would have held that second, and
    /// held the screen for as long as a big letter took.
    ///
    /// The preparation asks the main actor for a turn itself, with a task
    /// for the main actor, which starts there without a thread from the
    /// pool. A test polling on a timer instead needs one to wake, and the
    /// preparation holds one, which on a machine with one processor is the
    /// whole pool until the system adds another, about a second later.
    @MainActor
    func testThePageIsMadeWhileTheMainThreadGoesOn() async throws {
        let loads = PaneLoads()
        let events = Events()
        let mainWentOn = DispatchSemaphore(value: 0)
        loads.show(standIn: {},
                   fetch: { "letter" },
                   prepare: { letter -> String in
                       events.add(Thread.isMainThread ? "preparing on main" : "preparing")
                       Task { @MainActor in mainWentOn.signal() }
                       let free = mainWentOn.wait(timeout: .now() + 1) == .success
                       return free ? "page of \(letter)" : "main thread held"
                   },
                   settle: { result in events.add("drawn \((try? result.get()) ?? "-")") })
        try await until { loads.inFlight == 0 }
        XCTAssertEqual(events.all, ["preparing", "drawn page of letter"])
    }

    /// The settle rule holds across the preparation. A letter he leaves
    /// while its page is being made draws nothing, and the one he moved to
    /// is drawn; a letter he left before its body came is not prepared at
    /// all, which would be work for nothing. He moves on from inside the
    /// preparation, on the main actor, as in the test above.
    @MainActor
    func testALetterLeftBeforeOrWhileItsPageIsMadeDrawsNothing() async throws {
        let loads = PaneLoads()
        let events = Events()
        let release = DispatchSemaphore(value: 0)
        let drawn = { (result: Result<String, Error>) in
            events.add("drawn \((try? result.get()) ?? "-")")
        }
        let moveOn = {
            loads.show(standIn: {}, fetch: { "second" }, prepare: { "page of \($0)" }, settle: drawn)
            release.signal()
        }

        loads.show(standIn: {}, fetch: { "first" },
                   prepare: { letter -> String in
                       events.add("preparing \(letter)")
                       Task { @MainActor in moveOn() }
                       _ = release.wait(timeout: .now() + 1)
                       events.add("prepared \(letter)")
                       return "page of \(letter)"
                   },
                   settle: drawn)
        try await until { loads.inFlight == 0 && events.all.contains("prepared first") }
        try await Task.sleep(for: .milliseconds(10))
        // Second's page may be drawn either side of the first's being made.
        XCTAssertTrue(events.all.contains("drawn page of second"), "\(events.all)")
        XCTAssertFalse(events.all.contains("drawn page of first"), "\(events.all)")

        let left = Events()
        let gate = Gate()
        loads.show(standIn: {},
                   fetch: { () async throws -> String in
                       await gate.wait()
                       left.add("third came")
                       return "third"
                   },
                   prepare: { letter -> String in
                       left.add("preparing \(letter)")
                       return letter
                   },
                   settle: { _ in left.add("third drawn") })
        try await until { gate.waiting }
        loads.supersede()
        await gate.open()
        try await until { left.all.contains("third came") }
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(left.all, ["third came"])
    }

    // MARK: - The letter he opened last has the header

    /// Two letters opened one after the other in the conversation on
    /// screen, the first a large one whose page takes a while, the second a
    /// small one. The second's body comes after the first's, as it does
    /// down the one connection, and its page is ready while the first's is
    /// still being made. They settle first then second all the same, so the
    /// header, Reply, Delete and the pictures' loader end on the letter he
    /// opened last. Settled as each page was ready, the second took the
    /// header and then lost it to the first.
    @MainActor
    func testLettersOpenedOneAfterAnotherSettleInTheOrderTheyWereOpened() async throws {
        let loads = PaneLoads()
        let events = Events()
        let gate = Gate()
        let secondMade = DispatchSemaphore(value: 0)
        let focus = { (result: Result<String, Error>) in
            events.add("focus \((try? result.get()) ?? "-")")
        }

        loads.show(standIn: {},
                   fetch: { () async -> String in
                       await gate.open()
                       return "first"
                   },
                   prepare: { letter -> String in
                       // Still being made when the second's page is ready,
                       // and for a few milliseconds after, time enough for
                       // the second to settle if nothing held it back.
                       _ = secondMade.wait(timeout: .now() + .milliseconds(20))
                       usleep(5_000)
                       return letter
                   },
                   settle: focus)
        loads.start({ () async -> String in
                        await gate.wait()
                        return "second"
                    },
                    prepare: { letter -> String in
                        secondMade.signal()
                        return letter
                    },
                    settle: focus)
        try await until { loads.inFlight == 0 }
        XCTAssertEqual(events.all, ["focus first", "focus second"])

        // Moving on starts afresh: what is shown next waits for nothing left
        // from what was there, here a letter whose body never comes.
        let stuck = Gate()
        loads.start({ () async -> String in
                        await stuck.wait()
                        return "third"
                    },
                    settle: { _ in events.add("third drawn") })
        try await until { stuck.waiting }
        loads.show(standIn: {}, fetch: { "fourth" }, settle: focus)
        try await until { events.all.contains("focus fourth") }
        await stuck.open()
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(events.all, ["focus first", "focus second", "focus fourth"])
    }

    /// Four letters tapped in quick succession, the first one's body already
    /// on the wire. That one finishes its exchange, as a cancelled caller
    /// does, and draws nothing; the two he tapped past are called off while
    /// they wait for the connection and send nothing; the one he stopped on
    /// is fetched and drawn. Each used to be downloaded whole, in turn, and
    /// the last came last.
    ///
    /// The three unread ones are still marked read, each by its own STORE,
    /// which the pane does not cancel: a letter tapped and left counts as
    /// read, as in Mail (`MessageListViewController.markReadIfNeeded` says
    /// why). What that costs is here too: the body he stopped on waits for
    /// the STOREs of the two before it. The first letter is one he had read,
    /// so it has no STORE to race its own FETCH for the connection, which a
    /// tap's STORE can win, and the line can be counted.
    func testFourTapsInQuickSuccessionFetchOneBodyAfterTheOneOnTheWire() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let taps = [rows[6], rows[0], rows[1], rows[2]]
        XCTAssertEqual(taps.map(\.isRead), [true, false, false, false])
        server.clearLog()
        let loads = await PaneLoads()
        let drawn = Events()
        var reads: [Task<Void, Error>] = []

        func tap(_ letter: MessageSummary) async {
            await loads.show(
                standIn: {},
                fetch: { try await repository.loadMessage(id: letter.id, mailboxID: letter.mailboxID) },
                settle: { result in
                    drawn.add((try? result.get()).map { "\($0.subject)" } ?? "failed")
                })
            // The list's read mark, for a letter still unread, in a task of
            // its own on the main actor, started after the pane's.
            guard !letter.isRead else { return }
            reads.append(Task { @MainActor in
                try await repository.setRead(true, id: letter.id, mailboxID: letter.mailboxID)
            })
        }

        server.holdReplies(to: "UID FETCH")
        await tap(taps[0])
        try await until { self.server.log.contains { $0.verb == "UID FETCH" } }
        await tap(taps[1])
        try await until { await repository.waitingForExchange == 2 }
        // Each of the next two taps calls off the fetch before it, which
        // leaves the line, before its own joins. The pane does both in one
        // go; taken apart here so each step can be waited on.
        for letter in taps[2...] {
            let before = await repository.waitingForExchange
            await loads.supersede()
            try await until { await repository.waitingForExchange == before - 1 }
            await tap(letter)
            try await until { await repository.waitingForExchange == before + 1 }
        }
        await server.releaseReplies(to: "UID FETCH")
        for read in reads { try await finishing { try await read.value } }
        try await until { await loads.inFlight == 0 }

        let bodies = server.log.filter { $0.command.contains("BODY.PEEK[]") }
        XCTAssertEqual(bodies.map(\.command), ["UID FETCH \(uid(taps[0].id)) (UID BODY.PEEK[])",
                                               "UID FETCH \(uid(taps[3].id)) (UID BODY.PEEK[])"])
        XCTAssertEqual(drawn.all, [taps[3].subject])
        let stores = server.log.filter { $0.verb == "UID STORE" }
        XCTAssertEqual(stores.map(\.command),
                       taps.dropFirst().map { "UID STORE \(uid($0.id)) +FLAGS.SILENT (\\Seen)" })
        // The last body after the two STOREs queued before it; its own
        // STORE may go either side of it.
        let lastBody = try XCTUnwrap(server.log.lastIndex { $0.command == bodies.last?.command })
        let secondStore = try XCTUnwrap(server.log.firstIndex { $0.command == stores[1].command })
        XCTAssertGreaterThan(lastBody, secondStore)
        XCTAssertEqual(server.log.count, 5)
        for letter in taps {
            XCTAssertTrue(server.flags(uid: UInt32(uid(letter.id))!, in: Server.inbox)
                            .contains("\\Seen"), letter.subject)
        }
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        XCTAssertEqual(server.connectionsOpened, 1)
    }
}

/// What happened, in order, from whichever task it happened in.
private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    func add(_ event: String) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }
}

/// Holds a fetch until the test lets it go.
private actor Gate {
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    nonisolated var waiting: Bool { _waiting.isSet }
    private nonisolated let _waiting = Flag()

    func wait() async {
        guard !isOpen else { return }
        _waiting.set()
        await withCheckedContinuation { parked.append($0) }
    }

    func open() {
        isOpen = true
        for c in parked { c.resume() }
        parked = []
    }
}
