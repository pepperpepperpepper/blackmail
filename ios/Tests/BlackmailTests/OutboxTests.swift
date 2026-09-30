import XCTest
@testable import Blackmail

/// The Outbox (B-052): Send that cannot reach the server leaves the letter
/// on the iPad and closes the sheet; the pass that takes kept drafts to
/// Gmail sends it later, once; an attempt whose DATA went and whose 250
/// never came back is looked for in Sent Mail before it goes again; a letter
/// the server refuses stays in the sheet, or, sent later, in the Outbox with
/// the reason, without holding back the others.
///
/// These run the composer's own wiring (`ComposeActions(letter:…)`), the
/// shipping `LocalDrafts` over a store in a directory of the test's own, the
/// shipping repository over the scripted IMAP server, and a scripted
/// submission server on port 465 per connection, as the SMTP client makes
/// one per letter. The line can be taken down: then every connection is
/// refused, as a connect with no route is.
@MainActor
final class OutboxTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "OutboxTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var line: OutboxLine!
    private var submissions: OutboxSubmissions!
    /// The repository's clock, which only a test moves, so a stalled host
    /// cannot add a probe to the traffic a test pins.
    private var clock: ManualClock!
    /// When each letter is kept: a second later every time.
    private var keptClock: ManualClock!
    private var root: URL!
    private var background = FakeBackground()
    private var passTime = FakeBackground()
    private var pauses = Held()
    private var dismissals = 0
    private var queued = 0
    private var errors: [MailError] = []
    private var draws: [ComposeActions.Look] = []

    override func setUp() async throws {
        try await super.setUp()
        server = ScriptedIMAPServer()
        line = OutboxLine()
        submissions = OutboxSubmissions()
        clock = ManualClock()
        keptClock = ManualClock()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("OutboxTests-\(UUID().uuidString)", isDirectory: true)
        background = FakeBackground()
        passTime = FakeBackground()
        pauses = Held()
        dismissals = 0
        queued = 0
        errors = []
        draws = []
    }

    override func tearDown() async throws {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        if let root { try? FileManager.default.removeItem(at: root) }
        for outcome in ["ok", "fail"] {
            let transcript = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
            try? FileManager.default.removeItem(atPath: transcript)
        }
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

    /// The app's `LocalDrafts` over this test's directory, for the account
    /// the scripted server logs in, or `account`. A second one over the same
    /// directory is the app launched again.
    private func makeKept(account: String? = nil) -> LocalDrafts {
        let clock = keptClock!
        let store = LocalDraftStore(root: root, now: {
            clock.advance(by: 1)
            return clock.now()
        })
        return LocalDrafts(store: store, account: account ?? server.username,
                           background: passTime.time)
    }

    /// The composer's actions for letter `key`, wired as the composer
    /// wires them.
    private func makeActions(_ key: String, kept: LocalDrafts,
                             repository: MailRepository) -> ComposeActions {
        kept.opened(key)
        return ComposeActions(letter: key, repository: repository, kept: kept,
                              dismiss: { [unowned self] in dismissals += 1 },
                              showError: { [unowned self] in errors.append($0) },
                              draw: { [unowned self] in draws.append($0) },
                              background: background.time,
                              queued: { [unowned self] in queued += 1 },
                              wait: { [pauses] _ in try await pauses.wait() })
    }

    private func letter(_ subject: String = "Sunday", to: String = "carlo@example.org",
                        body: String = "Lunch at one?") -> Draft {
        var draft = Draft()
        draft.to = [to]
        draft.subject = subject
        draft.body = body
        return draft
    }

    /// Send tapped in the composer on `draft`, kept as `key`, to the end.
    private func send(_ draft: Draft, as key: String = "letter-1", kept: LocalDrafts,
                      repository: IMAPMailRepository) async {
        await makeActions(key, kept: kept, repository: repository).send({ draft }, then: nil)?.value
    }

    /// Send tapped with the line down: the letter goes to the Outbox, and
    /// the line comes back.
    private func sentOffline(_ draft: Draft, as key: String = "letter-1", kept: LocalDrafts,
                             repository: IMAPMailRepository) async {
        line.isUp = false
        await send(draft, as: key, kept: kept, repository: repository)
        line.isUp = true
    }

    /// Send tapped on a submission server that hangs up as the letter's
    /// terminating dot arrives: DATA went, and no 250 came back.
    private func sentAndCutOff(_ draft: Draft, as key: String = "letter-1", kept: LocalDrafts,
                               repository: IMAPMailRepository) async {
        submissions.then { ScriptedSubmission(hangsUpBeforeLetterReply: true) }
        await send(draft, as: key, kept: kept, repository: repository)
    }

    /// A folder's newest page, fetched as the app fetches one, so the
    /// connection is up for a pass.
    private func page(_ repository: IMAPMailRepository) async throws {
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
    }

    /// A page, and the pass that follows it.
    private func afterAPage(_ kept: LocalDrafts, _ repository: IMAPMailRepository) async throws {
        try await page(repository)
        await kept.uploadWaiting(to: repository)?.value
    }

    /// What Gmail does with a letter it has taken: files a copy in Sent Mail
    /// under the Message-ID it came with.
    private func fileInSentMail(_ messageID: String) {
        server.deliver(Server.Letter(from: Server.owner, to: [Server.carlo], subject: "Sunday",
                                     date: Server.newestDate, text: "Lunch at one?\r\n",
                                     flags: ["\\Seen"], messageID: messageID),
                       to: [Server.sent, Server.allMail])
    }

    /// As long after the cut as Gmail is given to file what it took
    /// (`Outbox.settling`): Sent Mail's not having it counts from here.
    private func settle() {
        keptClock.advance(by: Outbox.settling)
    }

    /// A letter kept as a draft, as Save Draft with no connection leaves one.
    private func keptDraft(_ subject: String, as key: String, kept: LocalDrafts) {
        kept.keep(letter(subject), as: key, unfinished: false)
    }

    private var appends: [ScriptedIMAPServer.LogEntry] {
        server.log.filter { $0.verb == "APPEND" }
    }

    /// The looks in Sent Mail, and where each was made.
    private var looks: [ScriptedIMAPServer.LogEntry] {
        server.log.filter { $0.command.contains("HEADER Message-ID") }
    }

    private var searches: [String] { looks.map(\.command) }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    // MARK: - Send with no connection

    /// Send with no connection: the sheet closes, one notice says so, and
    /// the letter is in the Outbox, waiting, not in Drafts, and there after
    /// a relaunch. Before, the sheet stayed with "Can't connect to mail
    /// server." and the letter lasted only as long as the sheet did.
    func testSendWithNoConnectionPutsTheLetterInTheOutboxAndCloses() async throws {
        let kept = makeKept()
        await sentOffline(letter(), kept: kept, repository: makeRepository())

        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(queued, 1, "one notice")
        XCTAssertEqual(errors, [], "nothing is wrong with the letter")
        XCTAssertEqual(draws, [.sending("Sending…")], "nothing drawn after the sheet has gone")
        XCTAssertEqual(background.ended, [1], "the time given back once")
        XCTAssertEqual(kept.outbox.map(\.key), ["letter-1"])
        XCTAssertEqual(kept.outbox.first?.outboxState, .waiting)
        XCTAssertEqual(kept.waiting.count, 0, "not a draft")
        XCTAssertEqual(makeKept().outbox.map(\.draft.subject), ["Sunday"], "and after a relaunch")
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 0)
    }

    /// A later pass sends it once, however many ask at once, under the
    /// Message-ID it entered the Outbox with, and it leaves the Outbox and
    /// the iPad. Nothing is looked for in Sent Mail: it never reached DATA.
    func testALaterPassSendsItOnceAndItLeaves() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentOffline(letter(), kept: kept, repository: repository)
        let messageID = try XCTUnwrap(kept.store.letter("letter-1")?.outbox)

        try await page(repository)
        let first = kept.uploadWaiting(to: repository)
        XCTAssertNotNil(first)
        XCTAssertNil(kept.uploadWaiting(to: repository), "one pass at a time")
        await first?.value
        XCTAssertNil(kept.uploadWaiting(to: repository), "nothing left to send")

        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first.flatMap(OutboxSubmissions.messageID), messageID)
        XCTAssertEqual(searches, [], "it never reached DATA: nothing to look for")
        XCTAssertEqual(kept.outbox.count, 0)
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// Letters go from the Outbox in the order he sent them, oldest first,
    /// and before the drafts kept on the iPad, the newest of which was kept
    /// after them all.
    func testLettersGoInTheOrderHeSentThem() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentOffline(letter("First"), as: "first", kept: kept, repository: repository)
        await sentOffline(letter("Second"), as: "second", kept: kept, repository: repository)
        keptDraft("Draft", as: "draft", kept: kept)
        try await page(repository)
        server.holdReplies(to: "APPEND")
        let pass = try XCTUnwrap(kept.uploadWaiting(to: repository))
        try await until { !appends.isEmpty }
        var sent = await submissions.letters()
        XCTAssertEqual(sent.count, 2, "both letters went before the draft's APPEND")
        await server.releaseReplies(to: "APPEND")
        await pass.value
        sent = await submissions.letters()
        XCTAssertEqual(sent.map { $0.contains("Subject: First") }, [true, false])
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// A submission server that cannot be reached while the IMAP connection
    /// is up ends the Outbox's part of the pass: every letter after it would
    /// fail the same way, each costing a connect.
    /// The drafts still go up: Gmail's IMAP is working.
    func testASubmissionServerOutOfReachEndsTheOutboxsPartOfThePass() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentOffline(letter("First"), as: "first", kept: kept, repository: repository)
        await sentOffline(letter("Second"), as: "second", kept: kept, repository: repository)
        keptDraft("Draft", as: "draft", kept: kept)
        submissions.then { ScriptedSubmission(failsToOpen: true) }
        try await afterAPage(kept, repository)
        XCTAssertEqual(submissions.made, 1)
        XCTAssertEqual(kept.outbox.count, 2)
        XCTAssertNil(kept.whyNotSent("first"), "it waits, not refused")
        XCTAssertEqual(appends.count, 1, "the draft went up")
        XCTAssertEqual(kept.waiting.count, 0)

        try await afterAPage(kept, repository)
        XCTAssertEqual(kept.outbox.count, 0, "both go at the next pass")
    }

    /// With nowhere on the iPad to keep it, Send goes straight to the server
    /// as it did before the Outbox, and a failure is said in the sheet: the
    /// sheet is the only place the letter is.
    func testALetterTheIPadCannotKeepStaysInTheSheetWhenItCannotGo() async throws {
        try Data("not a directory".utf8).write(to: root)
        let kept = makeKept()
        await sentOffline(letter(), kept: kept, repository: makeRepository())
        XCTAssertEqual(errors, [.cannotConnect])
        XCTAssertEqual(dismissals, 0)
        XCTAssertEqual(queued, 0)

        errors = []
        await send(letter(), kept: kept, repository: makeRepository())
        XCTAssertEqual(errors, [])
        XCTAssertEqual(dismissals, 1)
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
    }

    /// A pass nobody asked for makes no connection: with the line down, or
    /// no IMAP connection up, nothing is sent, and the letter waits.
    func testAPassMakesNoConnectionOfItsOwn() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentOffline(letter(), kept: kept, repository: repository)
        await kept.uploadWaiting(to: repository)?.value
        XCTAssertEqual(submissions.made, 0)
        XCTAssertEqual(server.connectionsOpened, 0)
        XCTAssertEqual(kept.outbox.count, 1)
    }

    // MARK: - Never twice

    /// DATA went and the line died before the 250: the sheet closes, and
    /// the letter waits in the Outbox as being sent. Gmail had it. After a
    /// relaunch the pass asks Sent Mail for it by its Message-ID, finds it,
    /// sends nothing, and takes it out of the Outbox.
    func testADataCutOffBeforeThe250IsFoundInSentMailAndNotSentAgain() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentAndCutOff(letter(), kept: kept, repository: repository)
        XCTAssertEqual(queued, 1)
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(errors, [])
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        let messageID = try XCTUnwrap(sent.first.flatMap(OutboxSubmissions.messageID))
        fileInSentMail(messageID)

        let relaunched = makeKept()
        XCTAssertEqual(relaunched.outbox.first?.outboxState, .beingSent)
        try await afterAPage(relaunched, repository)
        XCTAssertEqual(searches.count, 1)
        XCTAssertTrue(searches.first?.contains("HEADER Message-ID \"\(messageID)\"") == true)
        XCTAssertEqual(looks.first?.selected, Server.sent)
        let after = await submissions.letters()
        XCTAssertEqual(after.count, 1, "not sent again")
        XCTAssertEqual(relaunched.outbox.count, 0, "it went")
        XCTAssertEqual(relaunched.store.letters().count, 0)
    }

    /// The same cut, where Gmail did not have it: Sent Mail is asked, has
    /// nothing, and the letter goes again, once, under the same Message-ID,
    /// so the two attempts are the same message.
    func testADataCutOffThatSentMailDoesNotHaveIsSentOnceMore() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentAndCutOff(letter(), kept: kept, repository: repository)
        let stored = try XCTUnwrap(kept.store.letter("letter-1")?.outbox)
        settle()

        try await afterAPage(kept, repository)
        await kept.uploadWaiting(to: repository)?.value
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 2, "the cut-off attempt and one more")
        XCTAssertEqual(searches.count, 1)
        let ids = sent.map(OutboxSubmissions.messageID)
        XCTAssertEqual(ids, [stored, stored], "the same Message-ID at every attempt")
        XCTAssertEqual(kept.outbox.count, 0)
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// A Sent Mail search the server refuses sends nothing: the letter
    /// waits, still being sent, and the next pass asks again. Taken as "not
    /// there", as a refused search in Drafts is, it could go twice.
    func testARefusedSentMailSearchDoesNotSendItAgain() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentAndCutOff(letter(), kept: kept, repository: repository)
        await sentOffline(letter("Another"), as: "another", kept: kept, repository: repository)
        server.refusedSearchKeys = ["HEADER"]

        try await afterAPage(kept, repository)
        var sent = await submissions.letters()
        XCTAssertEqual(sent.count, 2, "not sent blind; the letter after it went")
        XCTAssertTrue(sent.last?.contains("Subject: Another") == true)
        XCTAssertEqual(searches.count, 1)
        XCTAssertEqual(kept.outbox.map(\.key), ["letter-1"])
        XCTAssertEqual(kept.outbox.first?.outboxState, .beingSent)
        XCTAssertNil(kept.whyNotSent("letter-1"), "not refused: it waits")

        server.refusedSearchKeys = []
        settle()
        await kept.uploadWaiting(to: repository)?.value
        sent = await submissions.letters()
        XCTAssertEqual(sent.count, 3, "asked again, not there, sent")
        XCTAssertEqual(kept.outbox.count, 0)
    }

    /// Deleted from the Outbox while a pass is on its way with it, before
    /// its DATA: the DATA never goes. The attempt is written down just
    /// before DATA, and that write finds the letter gone.
    func testALetterDeletedBeforeItsDataNeverGoes() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentAndCutOff(letter(), kept: kept, repository: repository)
        settle()
        try await page(repository)
        server.holdReplies(to: "UID SEARCH")
        let pass = try XCTUnwrap(kept.uploadWaiting(to: repository))
        try await until { !looks.isEmpty }
        XCTAssertTrue(kept.isGoing("letter-1"))

        let deleting = Task { await kept.delete("letter-1", from: repository) }
        await server.releaseReplies(to: "UID SEARCH")
        await pass.value
        await deleting.value
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1, "only the attempt cut off before it")
        let commands = await submissions.commands()
        XCTAssertEqual(commands.filter { $0 == "DATA" }.count, 1)
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// Sent Mail open on the connection, as it is once he has looked there,
    /// when Gmail files the letter whose 250 was lost: the session has not
    /// been told of it, and a SEARCH answers from what the session knows
    /// (B-045). The look asks for the mailbox's news first, however recently
    /// the session asked, finds it, and sends nothing.
    func testALetterFiledInSentMailWhileItIsOpenIsFound() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentAndCutOff(letter(), kept: kept, repository: repository)
        let messageID = try XCTUnwrap(kept.store.letter("letter-1")?.outbox)
        _ = try await repository.listMessages(in: "sent", beforeUID: nil, limit: 10)
        server.arrive(Server.Letter(from: Server.owner, to: [Server.carlo], subject: "Sunday",
                                    date: Server.newestDate, text: "Lunch at one?\r\n",
                                    flags: ["\\Seen"], messageID: messageID),
                      in: [Server.sent, Server.allMail])
        settle()

        await kept.uploadWaiting(to: repository)?.value
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1, "Gmail had it: not sent again")
        XCTAssertEqual(looks.map(\.selected), [Server.sent])
        let log = server.log
        let look = try XCTUnwrap(log.lastIndex { $0.command.contains("HEADER Message-ID") })
        XCTAssertEqual(log[look - 1].verb, "NOOP", "its news asked for first")
        XCTAssertEqual(kept.outbox.count, 0)
    }

    /// Sent Mail asked a moment after the cut, before Gmail has filed what
    /// it took: nothing found then is not taken to mean it never went. The
    /// pass sends nothing, nor does his own Send from the composer, which
    /// closes the sheet with the notice, the letter still under the
    /// Message-ID it went under. Gmail files it; the next look finds it, and
    /// nothing more is sent.
    func testNothingInSentMailSoSoonAfterTheCutSendsNothing() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentAndCutOff(letter(), kept: kept, repository: repository)
        let messageID = try XCTUnwrap(kept.store.letter("letter-1")?.outbox)

        try await afterAPage(kept, repository)
        XCTAssertEqual(searches.count, 1)
        XCTAssertEqual(kept.outbox.first?.outboxState, .beingSent)

        queued = 0
        dismissals = 0
        let opened = try XCTUnwrap(kept.letter("letter-1")).draft
        await makeActions("letter-1", kept: kept, repository: repository)
            .send({ opened }, then: nil)?.value
        XCTAssertEqual(errors, [])
        XCTAssertEqual(queued, 1, "it waits")
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(searches.count, 2)
        XCTAssertEqual(kept.store.letter("letter-1")?.outbox, messageID, "the same message")

        fileInSentMail(messageID)
        await kept.uploadWaiting(to: repository)?.value
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1, "never twice")
        XCTAssertEqual(kept.outbox.count, 0, "found: it went")
    }

    /// A server that lists no Sent Mail, as with "Show in IMAP" off for it
    /// in Gmail's settings: the look is made in All Mail, which holds every
    /// letter Sent Mail does, and never in a folder whose name is guessed.
    func testWithNoSentMailListedTheLookIsMadeInAllMail() async throws {
        server.unlistedMailboxes = [Server.sent]
        let kept = makeKept()
        let repository = makeRepository()
        await sentAndCutOff(letter(), kept: kept, repository: repository)
        fileInSentMail(try XCTUnwrap(kept.store.letter("letter-1")?.outbox))
        settle()

        try await afterAPage(kept, repository)
        XCTAssertEqual(looks.map(\.selected), [Server.allMail])
        XCTAssertEqual(server.log.filter { $0.verb == "SELECT" && $0.status != "OK" }, [])
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1, "found in All Mail: not sent again")
        XCTAssertEqual(kept.outbox.count, 0)
    }

    /// With neither Sent Mail nor All Mail listed, whether the cut-off
    /// attempt went can never be asked. The letter is not sent blind: its
    /// row says it was not sent, the letters after it go, and his Send from
    /// the composer keeps the sheet with the same words. Guessing the
    /// folder's name, every look was refused, and the letter waited for
    /// good with nothing on its row.
    func testWithNeitherSentMailNorAllMailListedTheLetterIsNotSentBlind() async throws {
        server.unlistedMailboxes = [Server.sent, Server.allMail]
        let kept = makeKept()
        let repository = makeRepository()
        await sentAndCutOff(letter(), kept: kept, repository: repository)
        await sentOffline(letter("Another"), as: "another", kept: kept, repository: repository)
        settle()

        try await afterAPage(kept, repository)
        var sent = await submissions.letters()
        XCTAssertEqual(sent.count, 2, "not sent blind; the letter after it went")
        XCTAssertEqual(kept.outbox.map(\.key), ["letter-1"])
        XCTAssertEqual(kept.whyNotSent("letter-1"), .notSent)
        XCTAssertEqual(server.log.filter { $0.verb == "SELECT" && $0.status != "OK" }, [],
                       "no folder guessed")

        errors = []
        dismissals = 0
        let opened = try XCTUnwrap(kept.letter("letter-1")).draft
        await makeActions("letter-1", kept: kept, repository: repository)
            .send({ opened }, then: nil)?.value
        XCTAssertEqual(errors, [.notSent])
        XCTAssertEqual(dismissals, 0)
        sent = await submissions.letters()
        XCTAssertEqual(sent.count, 2)
    }

    /// The line dies under the look. It is a read, and goes once more on a
    /// new connection, as any read does (B-023), a pass's too: the pass
    /// began on a connection that was up, and the new one logs in as that
    /// one did. Found then, nothing is sent.
    func testALookCutOffGoesOnceMoreOnANewConnection() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentAndCutOff(letter(), kept: kept, repository: repository)
        fileInSentMail(try XCTUnwrap(kept.store.letter("letter-1")?.outbox))
        try await page(repository)
        server.holdReplies(to: "UID SEARCH")
        let pass = try XCTUnwrap(kept.uploadWaiting(to: repository))
        try await until { !looks.isEmpty }

        await server.resetConnections()
        await server.releaseReplies(to: "UID SEARCH")
        await pass.value
        XCTAssertEqual(looks.count, 2, "asked again")
        XCTAssertEqual(Set(looks.map(\.connection)).count, 2, "on a new connection")
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1, "found: not sent again")
        XCTAssertEqual(kept.outbox.count, 0)
    }

    /// His Send from the composer asks Sent Mail first, and Gmail refuses
    /// the password for the look: the sheet stays with "Password needs to
    /// be updated", as for a Send refused for it, and not the Outbox's
    /// notice; the password is not sent again, and the attempt is still to
    /// be looked for.
    func testALookRefusedForItsPasswordKeepsTheSheet() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentAndCutOff(letter(), kept: kept, repository: repository)
        let messageID = try XCTUnwrap(kept.store.letter("letter-1")?.outbox)
        server.passwordRevoked = true
        queued = 0
        dismissals = 0

        let opened = try XCTUnwrap(kept.letter("letter-1")).draft
        await makeActions("letter-1", kept: kept, repository: repository)
            .send({ opened }, then: nil)?.value
        XCTAssertEqual(errors, [.passwordNeedsUpdating])
        XCTAssertEqual(dismissals, 0)
        XCTAssertEqual(queued, 0)
        let back = try XCTUnwrap(kept.store.letter("letter-1"))
        XCTAssertNil(back.outbox, "back in the sheet")
        XCTAssertEqual(back.unsettled, [messageID], "still to be looked for")
        XCTAssertEqual(server.log.filter { $0.verb == "LOGIN" }.count, 1)
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
    }

    /// A letter cut off after its DATA, opened from the Outbox, changed and
    /// saved as a draft, keeps what may have gone. Gmail had it: it is not
    /// taken to Drafts, where sent later it would go with nothing looked
    /// for, but kept here, listed in Drafts, not asked about again by every
    /// pass, and his Send from there asks Sent Mail and sends nothing.
    func testAnOutboxLetterSavedAsADraftKeepsWhatMayHaveGone() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentAndCutOff(letter(), kept: kept, repository: repository)
        let messageID = try XCTUnwrap(kept.store.letter("letter-1")?.outbox)
        fileInSentMail(messageID)

        var changed = try XCTUnwrap(kept.letter("letter-1")).draft
        changed.body = "Lunch at two?"
        await makeActions("letter-1", kept: kept, repository: repository)
            .saveAndClose({ changed }, then: nil)?.value
        XCTAssertEqual(appends.count, 0, "not taken to Drafts")
        XCTAssertEqual(kept.waiting.map(\.key), ["letter-1"], "a draft on the iPad")
        XCTAssertEqual(kept.store.letter("letter-1")?.unsettled, [messageID])
        try await afterAPage(kept, repository)
        XCTAssertEqual(searches.count, 1, "not asked again unasked")

        dismissals = 0
        let opened = try XCTUnwrap(kept.letter("letter-1")).draft
        await makeActions("letter-1", kept: kept, repository: repository)
            .send({ opened }, then: nil)?.value
        XCTAssertEqual(errors, [])
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(searches.count, 2)
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1, "Gmail already had it: not sent twice")
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// The same, where Gmail did not have it: once Sent Mail has said so,
    /// long enough after the cut, the draft goes to Drafts as any draft,
    /// and nothing is left of it on the iPad.
    func testAnOutboxLetterSavedAsADraftGoesUpOnceSentMailHasNotGotIt() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentAndCutOff(letter(), kept: kept, repository: repository)
        settle()

        var changed = try XCTUnwrap(kept.letter("letter-1")).draft
        changed.body = "Lunch at two?"
        await makeActions("letter-1", kept: kept, repository: repository)
            .saveAndClose({ changed }, then: nil)?.value
        XCTAssertEqual(searches.count, 1)
        XCTAssertEqual(appends.count, 1)
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    // MARK: - The letter's own failures keep the sheet

    /// A recipient refused, a letter too big, a password refused: the sheet
    /// stays with the letter and the reason, as before, and the letter is
    /// not in the Outbox. The one refused after its DATA leaves nothing to
    /// look for: the server said it did not take it.
    func testALettersOwnFailureKeepsTheSheet() async throws {
        let cases: [(String, () -> ScriptedSubmission, MailError)] = [
            ("recipient", { ScriptedSubmission(refusedRecipients: ["carlo@example.org"]) }, .notSent),
            ("too big", { ScriptedSubmission(letterReply: "552 5.3.4 Message too big") },
             .messageTooLarge),
            ("password", { ScriptedSubmission(refusesPassword: true) }, .passwordNeedsUpdating),
        ]
        for (name, make, expected) in cases {
            try? FileManager.default.removeItem(at: root)
            errors = []
            dismissals = 0
            queued = 0
            let kept = makeKept()
            submissions.then(make)
            await send(letter(), kept: kept, repository: makeRepository())
            XCTAssertEqual(errors, [expected], name)
            XCTAssertEqual(dismissals, 0, name)
            XCTAssertEqual(queued, 0, name)
            XCTAssertEqual(kept.outbox.count, 0, name)
            let back = try XCTUnwrap(kept.store.letter("letter-1"), name)
            XCTAssertNil(back.outbox, "\(name): back in the sheet, not in the Outbox")
            XCTAssertEqual(back.unsettled, [], "\(name): nothing that may have gone")
        }
    }

    /// iOS takes back the time it gave while the letter's 250 is still out:
    /// the time is given back and nothing else happens, as before. When the
    /// read's deadline then passes, as it does on the device once the app
    /// is running again after a suspension that outlived it, the letter
    /// waits in the Outbox, being sent, and the sheet closes with the
    /// notice. The time is given back once.
    func testTheTimeTakenBackBeforeThe250LeavesTheLetterInTheOutbox() async throws {
        let kept = makeKept()
        submissions.then { ScriptedSubmission(holdsLetterReply: true) }
        let sending = try XCTUnwrap(makeActions("letter-1", kept: kept, repository: makeRepository())
            .send({ [unowned self] in letter() }, then: nil))
        try await until { [submissions] in await submissions!.first?.isHoldingLetterReply == true }

        background.expire(1)
        XCTAssertEqual(background.ended, [1])
        XCTAssertEqual(dismissals, 0, "the sheet stays while the letter may still go")
        XCTAssertEqual(errors, [])

        await submissions.first?.deadlinePasses()
        await sending.value
        XCTAssertEqual(queued, 1)
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(errors, [])
        XCTAssertEqual(background.ended, [1], "given back once")
        XCTAssertEqual(kept.outbox.first?.outboxState, .beingSent)
    }

    /// The time taken back, and then the 250 comes after all: the letter
    /// went, the sheet closes as for any letter sent, with no notice, and
    /// nothing of it is left in the Outbox or on the iPad.
    func testA250ThatComesAfterTheTimeWasTakenBackSendsTheLetter() async throws {
        let kept = makeKept()
        submissions.then { ScriptedSubmission(holdsLetterReply: true) }
        let sending = try XCTUnwrap(makeActions("letter-1", kept: kept, repository: makeRepository())
            .send({ [unowned self] in letter() }, then: nil))
        try await until { [submissions] in await submissions!.first?.isHoldingLetterReply == true }
        background.expire(1)

        await submissions.first?.releaseLetterReply()
        await sending.value
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(queued, 0, "no notice: it went")
        XCTAssertEqual(errors, [])
        XCTAssertEqual(kept.outbox.count, 0)
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    // MARK: - The pass

    /// The submission server refuses the password: the pass stops at the
    /// first letter, and no pass after it sends the password again, however
    /// often a page loads or he comes back. A Send of his own that goes
    /// lets the Outbox go again.
    func testARefusedPasswordStopsThePassAndIsNotSentAgain() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentOffline(letter("Older"), as: "older", kept: kept, repository: repository)
        await sentOffline(letter("Newer"), as: "newer", kept: kept, repository: repository)
        submissions.then { ScriptedSubmission(refusesPassword: true) }

        try await afterAPage(kept, repository)
        for _ in 0..<3 {
            clock.advance(by: 120)
            await repository.warmUp()
            await kept.uploadWaiting(to: repository)?.value
            try await afterAPage(kept, repository)
        }
        await kept.uploadWaiting(to: repository, largeToo: true)?.value
        let auths = await submissions.commands().filter { $0.hasPrefix("AUTH") }
        XCTAssertEqual(auths.count, 1, "the refused password went once")
        XCTAssertEqual(kept.outbox.count, 2)

        await send(letter("His own"), as: "own", kept: kept, repository: repository)
        await kept.uploadWaiting(to: repository)?.value
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(kept.outbox.count, 0)
    }

    /// A letter refused for its own reason, a recipient the server will
    /// not take, does not hold back the letters after it. It stays in the
    /// Outbox with the reason on its row, and is not tried again unasked
    /// until the app is launched again.
    func testOneStuckLetterDoesNotHoldBackTheOthers() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentOffline(letter("Stuck", to: "jane@example.com"), as: "stuck", kept: kept,
                          repository: repository)
        await sentOffline(letter("Fine"), as: "fine", kept: kept, repository: repository)
        submissions.refused = ["jane@example.com"]

        try await afterAPage(kept, repository)
        var sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1, "the one after it went")
        XCTAssertEqual(kept.outbox.map(\.key), ["stuck"])
        XCTAssertEqual(kept.whyNotSent("stuck"), .notSent)
        let row = try XCTUnwrap(kept.outbox.first)
            .outboxRow(sending: false, notSent: kept.whyNotSent("stuck"))
        XCTAssertTrue(row.preview.hasPrefix("Message was not sent."), row.preview)

        let before = submissions.made
        try await afterAPage(kept, repository)
        XCTAssertEqual(submissions.made, before, "not tried again unasked")

        let relaunched = makeKept()
        try await afterAPage(relaunched, repository)
        XCTAssertEqual(submissions.made, before + 1, "tried again after a launch")
        sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
    }

    /// A letter reopened from Drafts and sent with no connection: its copy
    /// in Drafts is not listed while it waits, since opened it would be
    /// sent a second time, and it is removed from Drafts once the letter
    /// has gone, as Send in the composer removes it.
    func testTheReopenedDraftsCopyIsRemovedAfterTheLetterGoes() async throws {
        let repository = makeRepository()
        let old = try XCTUnwrap(server.uids(in: Server.drafts).first)
        let oldID = "\(server.uidValidity(of: Server.drafts))/\(old)"
        var reopened = try await repository.loadDraft(id: oldID, mailboxID: Server.drafts)
        reopened.body = "Finished on the train."
        let kept = makeKept()
        await sentOffline(reopened, kept: kept, repository: repository)

        XCTAssertEqual(kept.outbox.first?.draft.savedID, oldID)
        XCTAssertEqual(kept.waiting.count, 0)
        XCTAssertEqual(Array(kept.replacedInDrafts.keys), [oldID],
                       "its old copy not listed in Drafts")
        XCTAssertTrue(server.uids(in: Server.drafts).contains(old), "not removed before it goes")

        try await afterAPage(kept, repository)
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertFalse(server.uids(in: Server.drafts).contains(old), "removed after it went")
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// Photos on the iPad do not hold a letter in the Outbox back: it goes
    /// over a connection of its own. A forward's files fetched from Gmail
    /// over the one IMAP connection do, a megabyte of them or more, until he
    /// leaves the app.
    func testOnlyWhatItFetchesFromGmailHoldsALetterBack() async throws {
        var photo = letter("Photo")
        let staged = try AttachmentStore.write(Data(repeating: 7, count: 2_000),
                                               named: "Garden.jpg")
        photo.attachments = [DraftAttachment(source: .localFile(staged), filename: "Garden.jpg",
                                             mimeType: "image/jpeg", size: 2_000_000)]
        let plans = Data(repeating: 9, count: 3_000)
        let original = try XCTUnwrap(server.deliver(Server.Letter(
            from: Server.sam, to: [Server.owner], subject: "Plans", date: Server.newestDate,
            text: "The plans.\r\n", messageID: "<plans@example.com>",
            files: [Server.File(name: "Plans.pdf", type: "APPLICATION", subtype: "PDF",
                                bytes: plans)]), to: [Server.inbox])[Server.inbox])
        var forward = letter("Forward")
        forward.attachments = [DraftAttachment(
            source: .messagePart(messageID: "\(server.uidValidity(of: Server.inbox))/\(original)",
                                 mailboxID: Server.inbox, section: "2"),
            filename: "Plans.pdf", mimeType: "application/pdf", size: 2_000_000)]
        XCTAssertFalse(LocalDraft(key: "p", draft: photo, version: "1", tried: [],
                                  unfinished: false, keptAt: Date(), account: nil,
                                  gone: false).fetchesLarge)
        XCTAssertTrue(LocalDraft(key: "f", draft: forward, version: "1", tried: [],
                                 unfinished: false, keptAt: Date(), account: nil,
                                 gone: false).fetchesLarge)
        // A forward's quoted picture that goes is also one of its rows, and
        // is fetched once: 600 kB, not 1.2 MB.
        var pictured = letter("Roof")
        let roof = QuotedOriginal.Picture(contentID: "roof", filename: "Roof.jpg",
                                          mimeType: "image/jpeg", size: 600_000,
                                          messageID: "600001/1000", mailboxID: Server.inbox,
                                          section: "2")
        pictured.quote = QuotedOriginal(kind: .forward, region: "Begin forwarded message:",
                                        html: "<img src=\"cid:roof\">", pictures: [roof])
        pictured.attachments = [DraftAttachment(
            source: .messagePart(messageID: "600001/1000", mailboxID: Server.inbox, section: "2"),
            filename: "Roof.jpg", mimeType: "image/jpeg", size: 600_000)]
        XCTAssertFalse(LocalDraft(key: "r", draft: pictured, version: "1", tried: [],
                                  unfinished: false, keptAt: Date(), account: nil,
                                  gone: false).fetchesLarge)

        let kept = makeKept()
        let repository = makeRepository()
        await sentOffline(photo, as: "photo", kept: kept, repository: repository)
        await sentOffline(forward, as: "forward", kept: kept, repository: repository)
        try await afterAPage(kept, repository)
        XCTAssertEqual(kept.outbox.map(\.key), ["forward"], "the photo letter went")
        await kept.uploadWaiting(to: repository, largeToo: true)?.value
        XCTAssertEqual(kept.outbox.map(\.key), [], "the forward as he leaves")
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 2)
        XCTAssertTrue(sent.last?.contains(String(plans.base64EncodedString().prefix(60))) == true)
    }

    /// A letter written in another account waits in the Outbox, listed,
    /// and is not sent from this one.
    func testALetterOfAnotherAccountIsNotSentByItself() async throws {
        let other = makeKept(account: "someone@example.net")
        let repository = makeRepository()
        await sentOffline(letter(), kept: other, repository: repository)

        let kept = makeKept()
        XCTAssertEqual(kept.outbox.count, 1)
        try await afterAPage(kept, repository)
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 0)
        XCTAssertEqual(kept.outbox.count, 1)

        // Opened here, it comes without what it quotes: the original's
        // pictures are named by folder and UID, which in this account can
        // be another letter's.
        var reply = letter("Re: Sunday")
        reply.quote = QuotedOriginal(kind: .reply, region: "On Sunday, Carlo wrote:\n> Hello",
                                     html: "<p>Hello</p>", pictures: [])
        other.keep(reply, as: "reply", unfinished: false)
        XCTAssertNotNil(other.letter("reply")?.draft.quote)
        XCTAssertNil(kept.letter("reply")?.draft.quote)
    }

    /// A letter a pass has sent leaves the Outbox at once, before its old
    /// copy in Drafts is removed, and the copy is told to a list as gone
    /// before that too. From its 250 the letter is no longer on its way, and
    /// while the removal took its round trips it was listed again, without
    /// "Sending…", to be opened in the composer: a Send there sent it a
    /// second time, and its entry went from under the open letter.
    func testALetterAPassHasSentLeavesTheOutboxAtOnce() async throws {
        let repository = makeRepository()
        let old = try XCTUnwrap(server.uids(in: Server.drafts).first)
        let oldID = "\(server.uidValidity(of: Server.drafts))/\(old)"
        var reopened = try await repository.loadDraft(id: oldID, mailboxID: Server.drafts)
        reopened.body = "Finished on the train."
        let kept = makeKept()
        await sentOffline(reopened, kept: kept, repository: repository)
        var gone: [String] = []
        // Filtered here rather than by `object:`, which this Foundation
        // does not match for a block observer.
        let watching = NotificationCenter.default.addObserver(
            forName: LocalDrafts.changed, object: nil, queue: nil) { note in
            MainActor.assumeIsolated {
                guard (note.object as AnyObject?) === kept,
                      let landing = note.userInfo?[LocalDrafts.landingKey] as? DraftLanding else {
                    return
                }
                gone += landing.replaced
            }
        }
        defer { NotificationCenter.default.removeObserver(watching) }

        try await page(repository)
        server.holdReplies(to: "UID STORE")
        let pass = try XCTUnwrap(kept.uploadWaiting(to: repository))
        try await until { server.log.contains { $0.verb == "UID STORE" } }
        var sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertFalse(kept.isGoing("letter-1"))
        XCTAssertEqual(kept.outbox.map(\.key), [], "not listed to be opened")
        XCTAssertNil(kept.letter("letter-1"), "nothing to open")
        XCTAssertEqual(gone, [oldID], "nor its copy in Drafts")

        await server.releaseReplies(to: "UID STORE")
        await pass.value
        sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertFalse(server.uids(in: Server.drafts).contains(old))
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// Opened in the composer just as a pass comes to it, while the pass
    /// asks whether the connection is up: the pass leaves it to him. Sent by
    /// the pass as well, his Send there sent it a second time, with nothing
    /// to look for.
    func testAPassLeavesALetterOpenedAsItsTurnComes() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentOffline(letter(), kept: kept, repository: repository)
        try await page(repository)
        let asked = HeldQuestion(repository)
        asked.holdNext()
        let pass = try XCTUnwrap(kept.uploadWaiting(to: asked))
        try await until { asked.isHolding }
        XCTAssertFalse(kept.isGoing("letter-1"))

        let opened = try XCTUnwrap(kept.letter("letter-1")).draft
        let actions = makeActions("letter-1", kept: kept, repository: repository)
        asked.release()
        await pass.value
        var sent = await submissions.letters()
        XCTAssertEqual(sent.count, 0, "the pass left the open letter alone")
        await actions.send({ opened }, then: nil)?.value
        sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// A forward whose original's folder has been renumbered since, so the
    /// file it carries can no longer be named, fails for its own sake with
    /// the connection up: it stays in the Outbox saying why, the letter
    /// after it goes, and sent from the composer the sheet stays with the
    /// reason. Taken for no connection, it waited for good, and as the
    /// oldest ended every pass before the letters after it.
    func testAForwardWhoseOriginalIsGoneDoesNotHoldBackTheOthers() async throws {
        let original = try XCTUnwrap(server.deliver(Server.Letter(
            from: Server.sam, to: [Server.owner], subject: "Plans", date: Server.newestDate,
            text: "The plans.\r\n", messageID: "<plans@example.com>",
            files: [Server.File(name: "Plans.pdf", type: "APPLICATION", subtype: "PDF",
                                bytes: Data(repeating: 9, count: 3_000))]),
            to: [Server.inbox])[Server.inbox])
        var forward = letter("Forward")
        forward.attachments = [DraftAttachment(
            source: .messagePart(messageID: "\(server.uidValidity(of: Server.inbox))/\(original)",
                                 mailboxID: Server.inbox, section: "2"),
            filename: "Plans.pdf", mimeType: "application/pdf", size: 3_000)]
        let kept = makeKept()
        let repository = makeRepository()
        await sentOffline(forward, as: "forward", kept: kept, repository: repository)
        await sentOffline(letter("Fine"), as: "fine", kept: kept, repository: repository)
        server.renumber(Server.inbox, validity: 777, firstUID: 1)

        try await afterAPage(kept, repository)
        var sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1, "the letter after it went")
        XCTAssertEqual(kept.outbox.map(\.key), ["forward"])
        XCTAssertEqual(kept.whyNotSent("forward"), .attachmentFailed)

        errors = []
        dismissals = 0
        queued = 0
        let opened = try XCTUnwrap(kept.letter("forward")).draft
        await makeActions("forward", kept: kept, repository: repository)
            .send({ opened }, then: nil)?.value
        XCTAssertEqual(errors, [.attachmentFailed])
        XCTAssertEqual(dismissals, 0)
        XCTAssertEqual(queued, 0)
        sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
    }

    /// His own Send refused for its password stops the Outbox as a pass's
    /// refusal does: the next page sends no password for the letters
    /// waiting.
    func testHisOwnSendRefusedForItsPasswordStopsThePass() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentOffline(letter("Waiting"), as: "waiting", kept: kept, repository: repository)
        submissions.then { ScriptedSubmission(refusesPassword: true) }
        await send(letter("His own"), as: "own", kept: kept, repository: repository)
        XCTAssertEqual(errors, [.passwordNeedsUpdating])

        try await afterAPage(kept, repository)
        let auths = await submissions.commands().filter { $0.hasPrefix("AUTH") }
        XCTAssertEqual(auths.count, 1, "the refused password went once")
        XCTAssertEqual(kept.outbox.map(\.key), ["waiting"])
    }

    // MARK: - The Outbox's list

    /// The Outbox's rows say whom each letter is to and its subject, newest
    /// first, and the count is how many wait. Opened in the composer a
    /// letter leaves the list; closed untouched it is back as it was;
    /// changed and swiped away it is a draft. Delete takes it off the iPad.
    func testTheOutboxListsCountsOpensAndDeletes() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentOffline(letter("First", to: "Carlo <carlo@example.org>"), as: "first",
                          kept: kept, repository: repository)
        await sentOffline(letter("Second", to: "jane@example.com"), as: "second",
                          kept: kept, repository: repository)

        let rows = kept.outbox.map { $0.outboxRow(sending: false, notSent: nil) }
        XCTAssertEqual(rows.map(\.subject), ["Second", "First"])
        XCTAssertEqual(rows.map(\.sender), ["jane@example.com", "Carlo"])
        XCTAssertEqual(rows.first?.preview, "Lunch at one?")
        XCTAssertEqual(rows.map(\.mailboxID), [Outbox.mailboxID, Outbox.mailboxID])
        let keys = rows.compactMap { LocalDraft.key(ofRow: $0.id) }
        XCTAssertEqual(keys, ["second", "first"])
        XCTAssertEqual(Outbox.mailbox(holding: kept.outbox.count).accessibilityLabel,
                       "Outbox, 2 Unsent Messages")
        XCTAssertEqual(Outbox.mailbox(holding: 1).name, "Outbox")

        let opened = try XCTUnwrap(kept.letter("first")).draft
        let actions = makeActions("first", kept: kept, repository: repository)
        XCTAssertEqual(kept.outbox.map(\.key), ["second"], "out of the Outbox while it is open")
        actions.sheetGone { opened }
        XCTAssertEqual(kept.outbox.map(\.key), ["second", "first"], "untouched, it is back")

        var changed = try XCTUnwrap(kept.letter("second")).draft
        let editing = makeActions("second", kept: kept, repository: repository)
        changed.body = "Lunch at two?"
        editing.edited { changed }
        editing.sheetGone { changed }
        XCTAssertEqual(kept.outbox.map(\.key), ["first"])
        XCTAssertEqual(kept.waiting.map(\.key), ["second"], "changed and swiped away, a draft")

        await kept.delete("first", from: repository)
        XCTAssertEqual(kept.outbox.count, 0)
        XCTAssertNil(kept.store.letter("first"))
    }

    /// Sent again from the composer after opening it from the Outbox, a
    /// letter whose earlier attempt was cut off after DATA is looked for in
    /// Sent Mail first: found, it went, the sheet closes as for a letter
    /// sent, and nothing more is sent.
    func testSentAgainFromTheComposerAnEarlierAttemptIsLookedForFirst() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await sentAndCutOff(letter(), kept: kept, repository: repository)
        let messageID = try XCTUnwrap(kept.store.letter("letter-1")?.outbox)
        fileInSentMail(messageID)
        dismissals = 0

        let opened = try XCTUnwrap(kept.letter("letter-1")).draft
        await makeActions("letter-1", kept: kept, repository: repository)
            .send({ opened }, then: nil)?.value
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(errors, [])
        XCTAssertEqual(searches.count, 1)
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1, "not sent a second time")
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// Once in the Outbox the sheet does nothing more: a second Send, a Save
    /// Draft or a Delete Draft from it sends and keeps nothing.
    func testTheSheetDoesNothingMoreOnceItsLetterIsInTheOutbox() async throws {
        let kept = makeKept()
        line.isUp = false
        let actions = makeActions("letter-1", kept: kept, repository: makeRepository())
        await actions.send({ [unowned self] in letter() }, then: nil)?.value
        XCTAssertNil(actions.send({ [unowned self] in letter() }, then: nil))
        XCTAssertNil(actions.saveAndClose({ [unowned self] in letter() }, then: nil))
        XCTAssertNil(actions.deleteAndClose(nil, letter: nil, then: nil))
        XCTAssertEqual(kept.outbox.count, 1)
        XCTAssertEqual(dismissals, 1)
    }

    // MARK: - What decides

    /// Which failures leave a letter waiting, and which keep the sheet.
    func testWhichFailuresWaitInTheOutbox() {
        XCTAssertTrue(Outbox.waits(after: MailError.cannotConnect))
        XCTAssertTrue(Outbox.waits(after: MailError.connectionLost))
        XCTAssertTrue(Outbox.waits(after: MailError.refusedForNow))
        XCTAssertTrue(Outbox.waits(after: Outbox.Unsettled()))
        XCTAssertFalse(Outbox.waits(after: Outbox.NoSentMail()))
        XCTAssertFalse(Outbox.waits(after: MailError.passwordNeedsUpdating))
        XCTAssertFalse(Outbox.waits(after: MailError.messageTooLarge))
        XCTAssertFalse(Outbox.waits(after: MailError.notSent))
        XCTAssertFalse(Outbox.waits(after: MailError.attachmentFailed))
        XCTAssertFalse(Outbox.waits(after: CocoaError(.fileNoSuchFile)))
    }

    /// The submission server's own answers: no route is "Can't connect", a
    /// line that dies before the verdict is a lost connection, and a refusal
    /// with a code is the letter's. Each used to be "not sent".
    func testTheSubmissionClientTellsALostLineFromARefusal() async throws {
        let account = server.account
        func failure(_ transport: ScriptedSubmission) async -> MailError? {
            do {
                try await SMTPClient(account: account, transport: { _, _ in transport })
                    .send(Data("Subject: x\r\n\r\nx\r\n".utf8), from: account.address,
                          to: ["carlo@example.org"], password: "app-password")
                return nil
            } catch {
                return error as? MailError
            }
        }
        let noRoute = await failure(ScriptedSubmission(failsToOpen: true))
        let cut = await failure(ScriptedSubmission(hangsUpBeforeLetterReply: true))
        // What the device's transport says when a deadline passes, and when
        // the link fails under it.
        let deadline = await failure(ScriptedSubmission(hangsUpBeforeLetterReply: true,
                                                        cutWith: .timedOut))
        let reset = await failure(ScriptedSubmission(hangsUpBeforeLetterReply: true,
                                                     cutWith: .posix("POSIX 54")))
        let refused = await failure(ScriptedSubmission(refusedRecipients: ["carlo@example.org"]))
        let rejected = await failure(ScriptedSubmission(letterReply: "554 5.7.0 Rejected"))
        XCTAssertEqual(noRoute, .cannotConnect)
        XCTAssertEqual(cut, .connectionLost)
        XCTAssertEqual(deadline, .connectionLost)
        XCTAssertEqual(reset, .connectionLost)
        XCTAssertEqual(refused, .notSent)
        XCTAssertEqual(rejected, .notSent)
        XCTAssertEqual(MailError.connectionLost.errorDescription, MailError.notSent.errorDescription,
                       "the same sentence as before")
    }

    /// A 4yz, the server's "not now", at the greeting, at AUTH and after
    /// DATA, is told from a refusal: the letter can go later as it is. AUTH
    /// LOGIN is not tried after a 4yz to AUTH PLAIN, which would only send
    /// the password again to hear the same. Each used to be "not sent".
    func testTheSubmissionServersNotNowIsToldFromARefusal() async throws {
        let account = server.account
        func failure(_ transport: ScriptedSubmission) async -> MailError? {
            do {
                try await SMTPClient(account: account, transport: { _, _ in transport })
                    .send(Data("Subject: x\r\n\r\nx\r\n".utf8), from: account.address,
                          to: ["carlo@example.org"], password: "app-password")
                return nil
            } catch {
                return error as? MailError
            }
        }
        let busy = ScriptedSubmission(greeting: "421 4.7.0 Try again later, closing connection")
        let login = ScriptedSubmission(authReply: "454 4.7.0 Cannot authenticate due to a temporary system problem")
        let afterData = ScriptedSubmission(letterReply: "451 4.3.0 Mail server temporarily rejected message")
        let greeting = await failure(busy)
        let auth = await failure(login)
        let letter = await failure(afterData)
        XCTAssertEqual(greeting, .refusedForNow)
        XCTAssertEqual(auth, .refusedForNow)
        XCTAssertEqual(letter, .refusedForNow)
        let commands = await login.commands
        XCTAssertFalse(commands.contains("AUTH LOGIN"), "the password sent once")
        XCTAssertEqual(MailError.refusedForNow.errorDescription, MailError.notSent.errorDescription)
    }

    /// "Not now" after the letter's DATA, from the composer: the sheet
    /// closes with the notice and the letter waits in the Outbox. The server
    /// said it did not take it, so the attempt is settled, and the next pass
    /// sends it with nothing looked for in Sent Mail. From a pass, a "not
    /// now" at the greeting leaves it waiting, not refused, and the pass
    /// after sends it.
    func testALetterTheServerSaysNotNowToWaitsInTheOutbox() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        submissions.then { ScriptedSubmission(letterReply: "451 4.3.0 Temporary System Problem") }
        await send(letter(), kept: kept, repository: repository)
        XCTAssertEqual(errors, [])
        XCTAssertEqual(queued, 1)
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(kept.outbox.first?.outboxState, .waiting, "settled: the server said no")

        submissions.then { ScriptedSubmission(greeting: "421 4.7.0 Try again later") }
        try await afterAPage(kept, repository)
        XCTAssertNil(kept.whyNotSent("letter-1"), "it waits, not refused")
        XCTAssertEqual(kept.outbox.count, 1)

        await kept.uploadWaiting(to: repository)?.value
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 2, "the one refused for now, and the one that went")
        XCTAssertEqual(searches, [], "nothing to look for")
        XCTAssertEqual(kept.outbox.count, 0)
    }

    /// The attempt is written down before DATA, and not before the server
    /// has taken the envelope: a letter refused at RCPT has nothing to be
    /// looked for.
    func testTheAttemptIsWrittenDownJustBeforeData() async throws {
        let account = server.account
        let transport = ScriptedSubmission()
        var seen: [String] = []
        let noted = Noted()
        try await SMTPClient(account: account, transport: { _, _ in transport })
            .send(Data("Subject: x\r\n\r\nx\r\n".utf8), from: account.address,
                  to: ["carlo@example.org"], password: "app-password",
                  beforeData: { noted.add(await transport.commands) })
        seen = await transport.commands
        XCTAssertEqual(noted.calls.count, 1, "once")
        XCTAssertTrue(noted.calls.first?.last?.hasPrefix("RCPT TO") == true,
                      "after the envelope: \(noted.calls)")
        XCTAssertFalse(noted.calls.first?.contains("DATA") ?? true)

        let refusing = ScriptedSubmission(refusedRecipients: ["carlo@example.org"])
        let never = Noted()
        _ = try? await SMTPClient(account: account, transport: { _, _ in refusing })
            .send(Data("Subject: x\r\n\r\nx\r\n".utf8), from: account.address,
                  to: ["carlo@example.org"], password: "app-password",
                  beforeData: { never.add([]) })
        XCTAssertEqual(never.calls.count, 0, "every recipient refused: nothing to write down")

        let withheld = ScriptedSubmission()
        do {
            try await SMTPClient(account: account, transport: { _, _ in withheld })
                .send(Data("Subject: x\r\n\r\nx\r\n".utf8), from: account.address,
                      to: ["carlo@example.org"], password: "app-password",
                      beforeData: { throw LocalDraftStore.NotKept() })
            XCTFail("sent")
        } catch is LocalDraftStore.NotKept {
        } catch {
            XCTFail("\(error)")
        }
        let commands = await withheld.commands
        XCTAssertFalse(commands.contains("DATA"), "DATA never goes")
        XCTAssertTrue(seen.contains("DATA"))
        let letters = await withheld.letters
        XCTAssertEqual(letters.count, 0)
    }

    /// A reply or forward kept on the iPad keeps what it quotes, so one sent
    /// later from the Outbox carries the original's look, as one sent at
    /// once does.
    func testAQuoteIsKeptWithTheLetter() throws {
        let store = LocalDraftStore(root: root)
        var draft = letter()
        draft.quote = QuotedOriginal(
            kind: .forward, region: "---------- Forwarded message ---------\nHello",
            html: "<p>Hello <img src=\"cid:roof\"></p>",
            pictures: [QuotedOriginal.Picture(contentID: "roof", filename: "Roof.jpg",
                                              mimeType: "image/jpeg", size: 40_000,
                                              messageID: "600001/1000", mailboxID: Server.inbox,
                                              section: "2")])
        try store.keep(draft, as: "letter-1", unfinished: false, account: server.username)
        let back = try XCTUnwrap(store.letter("letter-1")?.draft.quote)
        XCTAssertEqual(back.kind, .forward)
        XCTAssertEqual(back.region, draft.quote?.region)
        XCTAssertEqual(back.html, draft.quote?.html)
        XCTAssertEqual(back.pictures, draft.quote?.pictures)
    }

    /// A reply quoting a newsletter's megabyte of markup. The markup is a
    /// file of its own beside the letter, so the letter's own file, written
    /// at every change of its state, the one between RCPT and DATA among
    /// them, and read by every list that counts the Outbox, stays small; a
    /// list does not read the markup at all. It counts toward the size that
    /// holds an upload back, since it goes in the APPEND, and it comes back
    /// whole when the letter is opened.
    func testAQuotesMarkupIsKeptBesideTheLetter() throws {
        let store = LocalDraftStore(root: root)
        var draft = letter("Re: Sunday")
        let markup = "<p>" + String(repeating: "Lunch \"at\" one &amp; two.\n", count: 40_000) + "</p>"
        draft.quote = QuotedOriginal(kind: .reply, region: "On Sunday, Carlo wrote:\n> Lunch",
                                     html: markup, pictures: [])
        try store.keep(draft, as: "letter-1", unfinished: false, account: server.username)
        let messageID = try store.enterOutbox("letter-1")
        try store.noteSending("letter-1", messageID)

        let file = root.appendingPathComponent("letter-1/letter.json").path
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file)[.size] as? Int)
        XCTAssertLessThan(size, 10_000, "the letter's own file")
        let listed = try XCTUnwrap(store.letters().first)
        XCTAssertNil(listed.draft.quote?.html, "a list leaves the markup on disk")
        XCTAssertTrue(listed.isLarge)
        let opened = try XCTUnwrap(store.letter("letter-1"))
        XCTAssertEqual(opened.draft.quote?.html, markup)
        XCTAssertTrue(opened.isLarge)

        // Kept again as he writes, the markup, which has not changed, is
        // not written again.
        let quote = root.appendingPathComponent("letter-1/quote.html").path
        let before = try FileManager.default.attributesOfItem(atPath: quote)[.systemFileNumber]
        draft.body = "Lunch at two?"
        try store.keep(draft, as: "letter-1", unfinished: true, account: server.username)
        let after = try FileManager.default.attributesOfItem(atPath: quote)[.systemFileNumber]
        XCTAssertEqual(after as? Int, before as? Int, "the same file")
        XCTAssertEqual(store.letter("letter-1")?.draft.quote?.html, markup)
    }

    /// The notice promises nothing that cannot happen: no pass runs while
    /// the app is put away, so a Wi-Fi that comes back then sends nothing
    /// until he opens it again.
    func testTheNoticeSaysTheAppHasToBeOpen() {
        XCTAssertEqual(Outbox.notice, "Message is in the Outbox. It will be sent when the iPad is "
                       + "connected and Blackmail is open.")
    }

    /// The line under the list says how many letters wait, under the age
    /// and over a failure, in Mail's words.
    func testTheLineUnderTheListCountsWhatWaits() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var line = UpdatedLine()
        line.succeeded(at: now)
        XCTAssertEqual(line.text(now: now), "Updated Just Now")
        XCTAssertEqual(line.text(now: now, unsent: 1), "Updated Just Now\n1 Unsent Message")
        line.failed(.cannotConnect)
        XCTAssertEqual(line.text(now: now, unsent: 2),
                       "Updated Just Now\n2 Unsent Messages\nNo Connection")
        XCTAssertEqual(UpdatedLine().text(now: now, unsent: 1), "Checking for Mail…\n1 Unsent Message")
        XCTAssertNil(Outbox.unsent(0))
    }
}

/// The shipping repository, but that the next question of whether the
/// connection is up can be held until the test lets it go: the hop a pass
/// makes to the repository at each letter's turn, held open for exactly as
/// long as the test wants.
private final class HeldQuestion: MailRepository, @unchecked Sendable {
    private let base: IMAPMailRepository
    private let lock = NSLock()
    private var holding = false
    private var waiting: CheckedContinuation<Void, Never>?

    init(_ base: IMAPMailRepository) { self.base = base }

    /// The next `isConnected` waits for `release()`.
    func holdNext() {
        lock.lock()
        holding = true
        lock.unlock()
    }

    /// A question is being held.
    var isHolding: Bool {
        lock.lock()
        defer { lock.unlock() }
        return waiting != nil
    }

    func release() {
        lock.lock()
        let waiter = waiting
        waiting = nil
        holding = false
        lock.unlock()
        waiter?.resume()
    }

    var isConnected: Bool {
        get async {
            await withCheckedContinuation { (asked: CheckedContinuation<Void, Never>) in
                lock.lock()
                guard holding else {
                    lock.unlock()
                    asked.resume()
                    return
                }
                holding = false
                waiting = asked
                lock.unlock()
            }
            return await base.isConnected
        }
    }

    func listMailboxes() async throws -> [Mailbox] { try await base.listMailboxes() }
    func folders() async throws -> [Mailbox] { try await base.folders() }
    func listMessages(in mailboxID: String, beforeUID: String?,
                      limit: Int) async throws -> [MessageSummary] {
        try await base.listMessages(in: mailboxID, beforeUID: beforeUID, limit: limit)
    }
    func listMessages(in mailboxID: String, afterUID: String,
                      limit: Int) async throws -> [MessageSummary] {
        try await base.listMessages(in: mailboxID, afterUID: afterUID, limit: limit)
    }
    func messages(around date: Date, in mailboxID: String,
                  limit: Int) async throws -> MessageWindow? {
        try await base.messages(around: date, in: mailboxID, limit: limit)
    }
    func previews(for ids: [String], in mailboxID: String) async throws -> [String: String] {
        try await base.previews(for: ids, in: mailboxID)
    }
    func loadMessage(id: String, gmailMessageID: UInt64?, mailboxID: String) async throws -> Message {
        try await base.loadMessage(id: id, gmailMessageID: gmailMessageID, mailboxID: mailboxID)
    }
    func setRead(_ read: Bool, id: String, gmailMessageID: UInt64?,
                 mailboxID: String) async throws {
        try await base.setRead(read, id: id, gmailMessageID: gmailMessageID, mailboxID: mailboxID)
    }
    func setFlagged(_ flagged: Bool, id: String, gmailMessageID: UInt64?,
                    mailboxID: String) async throws {
        try await base.setFlagged(flagged, id: id, gmailMessageID: gmailMessageID,
                                  mailboxID: mailboxID)
    }
    func move(_ id: String, gmailMessageID: UInt64?, from sourceMailboxID: String,
              to destinationMailboxID: String) async throws {
        try await base.move(id, gmailMessageID: gmailMessageID, from: sourceMailboxID,
                            to: destinationMailboxID)
    }
    func delete(_ id: String, gmailMessageID: UInt64?, from mailboxID: String) async throws {
        try await base.delete(id, gmailMessageID: gmailMessageID, from: mailboxID)
    }
    func send(_ draft: Draft, progress: UploadProgress?) async throws {
        try await base.send(draft, progress: progress)
    }
    func send(_ draft: Draft, as letter: OutgoingLetter, progress: UploadProgress?) async throws {
        try await base.send(draft, as: letter, progress: progress)
    }
    func sentMail(holds messageIDs: [String]) async throws -> Set<String> {
        try await base.sentMail(holds: messageIDs)
    }
    func saveDraft(_ draft: Draft) async throws -> String? { try await base.saveDraft(draft) }
    func saveDraft(_ draft: Draft, as upload: DraftUpload) async throws -> DraftSaved {
        try await base.saveDraft(draft, as: upload)
    }
    func deleteDraft(_ id: String, gmailMessageID: UInt64?) async throws {
        try await base.deleteDraft(id, gmailMessageID: gmailMessageID)
    }
    func deleteDrafts(uploadedAs versions: [String]) async throws -> [String] {
        try await base.deleteDrafts(uploadedAs: versions)
    }
    func loadDraft(id: String, gmailMessageID: UInt64?, mailboxID: String) async throws -> Draft {
        try await base.loadDraft(id: id, gmailMessageID: gmailMessageID, mailboxID: mailboxID)
    }
    func search(in mailboxID: String, query: String, scope: MailSearchScope,
                beforeUID: String?, limit: Int) async throws -> [MessageSummary] {
        try await base.search(in: mailboxID, query: query, scope: scope,
                              beforeUID: beforeUID, limit: limit)
    }
    func fetchAttachmentData(_ attachmentID: String, of messageID: String,
                             mailboxID: String) async throws -> Data {
        try await base.fetchAttachmentData(attachmentID, of: messageID, mailboxID: mailboxID)
    }
    func warmUp() async { await base.warmUp() }
    func news(in mailboxID: String, known: [String],
              searchingAnyway: Bool) async throws -> FolderNews {
        try await base.news(in: mailboxID, known: known, searchingAnyway: searchingAnyway)
    }
    func inboxUnread() async throws -> Int? { try await base.inboxUnread() }
}

/// What each call to a `beforeData` saw of the conversation, from any
/// thread.
private final class Noted: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [[String]] = []

    func add(_ commands: [String]) {
        lock.lock()
        seen.append(commands)
        lock.unlock()
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }
}

/// The network, up or down, from any thread.
private final class OutboxLine: @unchecked Sendable {
    private let lock = NSLock()
    private var up = true

    var isUp: Bool {
        get { lock.lock(); defer { lock.unlock() }; return up }
        set { lock.lock(); up = newValue; lock.unlock() }
    }
}

/// A submission server per connection, as the SMTP client makes one per
/// letter: the ones a test lines up first, then ones that take every
/// letter, refusing the addresses in `refused`.
private final class OutboxSubmissions: @unchecked Sendable {
    private let lock = NSLock()
    private var servers: [ScriptedSubmission] = []
    private var script: [() -> ScriptedSubmission] = []
    private var refusing: Set<String> = []

    var refused: Set<String> {
        get { lock.lock(); defer { lock.unlock() }; return refusing }
        set { lock.lock(); refusing = newValue; lock.unlock() }
    }

    /// The next connection is made by `make`.
    func then(_ make: @escaping () -> ScriptedSubmission) {
        lock.lock()
        script.append(make)
        lock.unlock()
    }

    func next() -> ScriptedSubmission {
        lock.lock()
        defer { lock.unlock() }
        let server = script.isEmpty ? ScriptedSubmission(refusedRecipients: refusing)
                                    : script.removeFirst()()
        servers.append(server)
        return server
    }

    /// How many connections were made.
    var made: Int {
        lock.lock()
        defer { lock.unlock() }
        return servers.count
    }

    var first: ScriptedSubmission? {
        lock.lock()
        defer { lock.unlock() }
        return servers.first
    }

    private var all: [ScriptedSubmission] {
        lock.lock()
        defer { lock.unlock() }
        return servers
    }

    /// Every letter any of them was handed, whole, as text.
    func letters() async -> [String] {
        var out: [String] = []
        for server in all { out += await server.letters.map { String(decoding: $0, as: UTF8.self) } }
        return out
    }

    /// Every command any of them was sent, in order.
    func commands() async -> [String] {
        var out: [String] = []
        for server in all { out += await server.commands }
        return out
    }

    /// The Message-ID a letter went under.
    static func messageID(_ letter: String) -> String? {
        letter.components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("message-id:") }
            .map { $0.dropFirst("message-id:".count).trimmingCharacters(in: .whitespaces) }
    }
}
