import XCTest
@testable import Blackmail

/// Letters kept on the iPad (B-051): Save Draft with no connection or a
/// server that refuses, the upload once the connection works, an upload cut
/// off after the server had the letter, a letter opened while it goes up,
/// one sent or deleted after an upload of it was cut off, autosave, a
/// relaunch, and a store with a damaged file in it.
///
/// These run the composer's own wiring (`ComposeActions(letter:…)`), the
/// shipping `LocalDrafts` over a store in a directory of the test's own, and
/// the shipping repository over the scripted server, with a submission
/// server on port 465 for Send. The line can be taken down: with it down,
/// every connection is refused, as a connect with no route is.
@MainActor
final class LocalDraftsTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    /// The recipient book's own store, so a run neither reads nor writes
    /// this machine's standard defaults.
    private static let suite = "LocalDraftsTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var line: Line!
    private var submissions: Submissions!
    /// The repository's clock, which only a test moves, so a stalled host
    /// cannot add a probe to the traffic a test pins.
    private var clock: ManualClock!
    /// When each letter is kept: a second later every time, so the newest
    /// is the one kept last.
    private var keptClock: ManualClock!
    /// Where the letters are kept, a directory of this test's own.
    private var root: URL!
    /// The composer's background time, and the passes'.
    private var background = FakeBackground()
    private var passTime = FakeBackground()
    /// The pauses before an autosave, let go by hand.
    private var pauses = Held()
    private var dismissals = 0
    private var errors: [MailError] = []

    private let photoBytes = Data((0..<3000).map { UInt8(truncatingIfNeeded: $0 &* 29 &+ 7) })

    override func setUp() async throws {
        try await super.setUp()
        server = ScriptedIMAPServer()
        line = Line()
        submissions = Submissions()
        clock = ManualClock()
        keptClock = ManualClock()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LocalDraftsTests-\(UUID().uuidString)", isDirectory: true)
        background = FakeBackground()
        passTime = FakeBackground()
        pauses = Held()
        dismissals = 0
        errors = []
    }

    override func tearDown() async throws {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        if let root { try? FileManager.default.removeItem(at: root) }
        // The transcript `send` leaves in the temporary directory, as it
        // does on the device.
        for outcome in ["ok", "fail"] {
            let transcript = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
            try? FileManager.default.removeItem(atPath: transcript)
        }
        // An autosave's pause a test left waiting ends with it.
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

    /// The app's `LocalDrafts`, over this test's directory, for the account
    /// the scripted server logs in, or for `account`. A second one over the
    /// same directory is the app launched again.
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
                              draw: { _ in },
                              background: background.time,
                              wait: { [pauses] _ in try await pauses.wait() })
    }

    private func letter(_ subject: String = "Sunday", body: String = "Lunch at one?") -> Draft {
        var draft = Draft()
        draft.to = ["carlo@example.org"]
        draft.subject = subject
        draft.body = body
        return draft
    }

    /// A letter with a photo of `photoBytes` staged as the composer stages
    /// one, `size` saying how big it is.
    private func photoLetter(size: Int64? = nil) throws -> Draft {
        let staged = try AttachmentStore.write(photoBytes, named: "Garden.jpg")
        var draft = letter()
        draft.attachments = [DraftAttachment(source: .localFile(staged), filename: "Garden.jpg",
                                             mimeType: "image/jpeg",
                                             size: size ?? Int64(photoBytes.count))]
        return draft
    }

    /// The copies of the letter called `subject` in Drafts.
    private func copies(_ subject: String) -> [UInt32] {
        server.uids(in: Server.drafts).filter {
            server.letter(uid: $0, in: Server.drafts)?.subject == subject
        }
    }

    private func text(of uid: UInt32?) -> String {
        uid.flatMap { server.letter(uid: $0, in: Server.drafts)?.text } ?? ""
    }

    private var appends: Int { server.log.filter { $0.verb == "APPEND" }.count }
    private var logins: Int { server.log.filter { $0.verb == "LOGIN" }.count }

    /// The network gone: every connection open now dies, and no new one
    /// can be made.
    private func takeLineDown() async {
        line.isUp = false
        await server.resetConnections()
    }

    /// A folder's newest page, fetched as the app fetches one at launch, at
    /// a Refresh or on opening a folder.
    private func page(_ repository: IMAPMailRepository) async throws {
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
    }

    /// A page, and the pass over the kept letters that follows it.
    private func afterAPage(_ kept: LocalDrafts, _ repository: IMAPMailRepository) async throws {
        try await page(repository)
        await kept.uploadWaiting(to: repository)?.value
    }

    /// Save Draft with the line down: the letter kept as `key`, and the
    /// line up again.
    private func savedOffline(_ draft: Draft, as key: String = "letter-1", kept: LocalDrafts,
                              repository: IMAPMailRepository) async {
        line.isUp = false
        await makeActions(key, kept: kept, repository: repository)
            .saveAndClose({ draft }, then: nil)?.value
        line.isUp = true
    }

    /// Save Draft whose APPEND reaches the server and whose answer is lost
    /// with the line: the server has the letter, and the iPad does not know.
    private func savedAndCutOff(_ draft: Draft, kept: LocalDrafts,
                                repository: IMAPMailRepository) async throws {
        server.holdReplies(to: "APPEND")
        let saving = try XCTUnwrap(makeActions("letter-1", kept: kept, repository: repository)
            .saveAndClose({ draft }, then: nil))
        try await until { server.log.contains { $0.verb == "APPEND" } }
        await server.resetConnections()
        await saving.value
        await server.releaseReplies(to: "APPEND")
    }

    /// Kept offline, then taken up by a pass whose APPEND is held while the
    /// composer opens the letter, as a tap on its row in Drafts does; then
    /// the APPEND lands. Returns the composer's actions and its letter.
    private func openedWhileItGoesUp(
        _ draft: Draft, kept: LocalDrafts, repository: IMAPMailRepository
    ) async throws -> (actions: ComposeActions, letter: Draft) {
        await savedOffline(draft, kept: kept, repository: repository)
        try await page(repository)
        server.holdReplies(to: "APPEND")
        let pass = try XCTUnwrap(kept.uploadWaiting(to: repository))
        try await until { server.log.contains { $0.verb == "APPEND" } }
        let opened = try XCTUnwrap(kept.letter("letter-1")).draft
        let actions = makeActions("letter-1", kept: kept, repository: repository)
        await server.releaseReplies(to: "APPEND")
        await pass.value
        XCTAssertEqual(copies(draft.subject).count, 1, "it has landed")
        return (actions, opened)
    }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    // MARK: - Save Draft with no connection

    /// Save Draft with no connection: the sheet goes, nothing is said, and
    /// the letter is on the iPad, in Drafts' list, and there after a
    /// relaunch. It used to be thrown away.
    func testSaveDraftWithNoConnectionKeepsTheLetterOnTheIPad() async throws {
        line.isUp = false
        let kept = makeKept()
        let actions = makeActions("letter-1", kept: kept, repository: makeRepository())
        var changed = 0
        await actions.saveAndClose({ [unowned self] in letter() }, then: { changed += 1 })?.value

        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(errors, [], "nothing is said: nothing has been lost")
        XCTAssertEqual(changed, 1)
        XCTAssertEqual(kept.waiting.map(\.key), ["letter-1"])
        XCTAssertEqual(kept.waiting.first?.draft.subject, "Sunday")
        XCTAssertEqual(kept.waiting.first?.draft.body, "Lunch at one?")
        XCTAssertEqual(kept.waiting.first?.draft.to, ["carlo@example.org"])
        XCTAssertEqual(kept.waiting.first?.unfinished, false)
        XCTAssertEqual(kept.waiting.first?.tried, [], "nothing went, so nothing is looked for")
        XCTAssertEqual(copies("Sunday"), [])
        XCTAssertEqual(makeKept().waiting.map(\.draft.subject), ["Sunday"], "and after a relaunch")
        XCTAssertEqual(background.ended, [1])
    }

    /// The same with the server refusing: the password Gmail no longer
    /// takes. Sent once, not again.
    func testSaveDraftTheServerRefusesKeepsTheLetterOnTheIPad() async throws {
        server.passwordRevoked = true
        let kept = makeKept()
        let actions = makeActions("letter-1", kept: kept, repository: makeRepository())
        await actions.saveAndClose({ [unowned self] in letter() }, then: nil)?.value

        XCTAssertEqual(kept.waiting.map(\.draft.subject), ["Sunday"])
        XCTAssertEqual(copies("Sunday"), [])
        XCTAssertEqual(logins, 1)
    }

    /// Save Draft when the iPad cannot keep the letter, a full disk or a
    /// directory that cannot be made: it goes straight to the server, as
    /// every draft did before, rather than nowhere.
    func testSaveDraftTheIPadCannotKeepGoesStraightToTheServer() async throws {
        try Data("not a directory".utf8).write(to: root)
        let kept = makeKept()
        await makeActions("letter-1", kept: kept, repository: makeRepository())
            .saveAndClose({ [unowned self] in letter() }, then: nil)?.value

        XCTAssertEqual(copies("Sunday").count, 1)
        XCTAssertEqual(kept.waiting.count, 0)
    }

    // MARK: - With a connection, what it always was

    /// A first Save Draft sends what Save Draft always sent: the APPEND, and
    /// for a draft reopened from Drafts the old copy's removal after it.
    /// Nothing is looked for in Drafts; only a letter an upload of which
    /// has begun before is.
    func testAFirstSaveDraftSendsNothingItDidNotSendBefore() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        await makeActions("letter-1", kept: kept, repository: repository)
            .saveAndClose({ [unowned self] in letter() }, then: nil)?.value
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN", "NOOP", "LIST", "APPEND"])

        let old = try XCTUnwrap(server.uids(in: Server.drafts).first)
        var reopened = try await repository.loadDraft(
            id: "\(server.uidValidity(of: Server.drafts))/\(old)", mailboxID: Server.drafts)
        reopened.body = "Changed at the kitchen table."
        server.clearLog()
        await makeActions("letter-2", kept: kept, repository: repository)
            .saveAndClose({ reopened }, then: nil)?.value
        XCTAssertEqual(server.log.map(\.verb), ["APPEND", "UID STORE", "UID EXPUNGE"])
        XCTAssertFalse(server.uids(in: Server.drafts).contains(old))
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    // MARK: - Up later, once

    /// Once the connection works, the letter goes up once, however many
    /// ask at the same moment, and leaves the iPad. Not while the composer
    /// has it open: that one is his to finish.
    func testTheLetterGoesUpOnceWhenTheConnectionWorksAndLeavesTheIPad() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await savedOffline(letter(), kept: kept, repository: repository)
        XCTAssertEqual(kept.waiting.count, 1)

        try await page(repository)
        kept.opened("letter-1")
        XCTAssertNil(kept.uploadWaiting(to: repository), "not while it is open in the composer")
        XCTAssertEqual(appends, 0)
        kept.closed("letter-1")

        let first = kept.uploadWaiting(to: repository)
        let second = kept.uploadWaiting(to: repository)
        XCTAssertNotNil(first)
        XCTAssertNil(second, "one pass at a time")
        await first?.value
        await kept.uploadWaiting(to: repository)?.value

        XCTAssertEqual(appends, 1)
        XCTAssertEqual(copies("Sunday").count, 1)
        XCTAssertEqual(kept.waiting.map(\.key), [])
        XCTAssertNil(kept.store.letter("letter-1"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("letter-1").path))
        XCTAssertEqual(kept.landed["letter-1"],
                       copies("Sunday").first.map { "\(server.uidValidity(of: Server.drafts))/\($0)" })
    }

    /// A draft reopened from the server, changed and saved with no
    /// connection: listed in place of the server's copy, and once it goes
    /// up, that copy is removed after it, as Save Draft always did.
    func testALetterReopenedFromDraftsReplacesItsCopyWhenItGoesUp() async throws {
        let repository = makeRepository()
        let old = try XCTUnwrap(server.uids(in: Server.drafts).first)
        let oldID = "\(server.uidValidity(of: Server.drafts))/\(old)"
        var reopened = try await repository.loadDraft(id: oldID, mailboxID: Server.drafts)
        reopened.subject = "Changed on the train"

        await takeLineDown()
        let kept = makeKept()
        await makeActions("letter-1", kept: kept, repository: repository)
            .saveAndClose({ reopened }, then: nil)?.value
        XCTAssertEqual(kept.waiting.first?.draft.savedID, oldID)
        XCTAssertTrue(server.uids(in: Server.drafts).contains(old))

        line.isUp = true
        try await afterAPage(kept, repository)
        XCTAssertFalse(server.uids(in: Server.drafts).contains(old), "the old copy goes after it")
        XCTAssertEqual(copies("Changed on the train").count, 1)
        XCTAssertEqual(kept.waiting.count, 0)
    }

    /// A pass nobody asked for never makes a connection. With the password
    /// refused at Save Draft there is none, and coming back to the app,
    /// again and again, sends the refused password no more: the warm-up
    /// makes no connection where there was none, and the pass after it
    /// looks for one and finds none. It used to send the password at every
    /// return while a letter was kept.
    func testComingBackAfterARefusedPasswordSendsItNoMore() async throws {
        server.passwordRevoked = true
        let kept = makeKept()
        let repository = makeRepository()
        await makeActions("letter-1", kept: kept, repository: repository)
            .saveAndClose({ [unowned self] in letter() }, then: nil)?.value
        XCTAssertEqual(logins, 1)
        XCTAssertEqual(kept.waiting.count, 1)

        for _ in 0..<3 {
            // What coming back to the foreground runs.
            clock.advance(by: 120)
            await repository.warmUp()
            await kept.uploadWaiting(to: repository)?.value
        }
        await kept.uploadWaiting(to: repository, largeToo: true)?.value
        XCTAssertEqual(logins, 1, "coming back is not him trying again")
        XCTAssertEqual(kept.waiting.count, 1)
    }

    /// A letter that fails for its own sake on a working connection, a
    /// forward whose original has gone from Gmail, does not hold back the
    /// letters kept before it, and is not tried again by every pass after
    /// it until he changes it. Nor is it looked for in Drafts: nothing of
    /// it was sent. The pass used to stop at it, and it was the newest, so
    /// nothing older went up again.
    func testALetterThatCannotGoDoesNotHoldBackTheOthers() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        kept.keep(letter("Older"), as: "older", unfinished: false)
        var stuck = letter("Stuck")
        stuck.attachments = [DraftAttachment(
            source: .messagePart(messageID: "\(server.uidValidity(of: Server.inbox))/99999",
                                 mailboxID: Server.inbox, section: "2"),
            filename: "Receipt.pdf", mimeType: "application/pdf", size: 4_000)]
        kept.keep(stuck, as: "stuck", unfinished: false)
        XCTAssertEqual(kept.waiting.map(\.key), ["stuck", "older"])

        try await afterAPage(kept, repository)
        XCTAssertEqual(copies("Older").count, 1, "the older letter goes up")
        XCTAssertEqual(copies("Stuck").count, 0)
        XCTAssertEqual(kept.waiting.map(\.key), ["stuck"])
        XCTAssertEqual(kept.store.letter("stuck")?.tried, [])
        XCTAssertEqual(logins, 1)

        try await page(repository)
        server.clearLog()
        await kept.uploadWaiting(to: repository)?.value
        XCTAssertEqual(server.log.map(\.verb), [], "not tried again unasked")

        kept.keep(stuck, as: "stuck", unfinished: false)
        await kept.uploadWaiting(to: repository)?.value
        XCTAssertTrue(server.log.contains { $0.verb == "UID FETCH" }, "changed, it is tried again")
        XCTAssertFalse(server.log.contains { $0.verb == "UID SEARCH" })
    }

    // MARK: - Large letters

    /// A letter with a megabyte or more of photos is not taken up by a pass
    /// he did not ask for while he is using the app: its APPEND would hold
    /// the connection for the whole upload, and the letter he taps next
    /// would wait for all of it. It goes as he leaves the app, inside
    /// background time, and a small one goes at once.
    func testALargeLetterWaitsForHimToLeaveTheApp() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        kept.keep(try photoLetter(size: 2_000_000), as: "large", unfinished: false)
        kept.keep(letter("Small"), as: "small", unfinished: false)
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)

        await kept.uploadWaiting(to: repository)?.value
        XCTAssertEqual(copies("Small").count, 1)
        XCTAssertEqual(kept.waiting.map(\.key), ["large"])
        XCTAssertEqual(appends, 1)

        // With its APPEND unanswered, as a slow uplink leaves one for as
        // long as the photos take, the letter he taps would wait behind it.
        server.holdReplies(to: "APPEND")
        await kept.uploadWaiting(to: repository)?.value
        let tapped = rows[0]
        let opened = try await finishing(within: 2) {
            try await repository.open(tapped)
        }
        XCTAssertEqual(opened.subject, rows[0].subject, "his tap is answered at once")
        XCTAssertEqual(appends, 1, "nothing large went while he was here")
        await server.releaseReplies(to: "APPEND")

        passTime.begun = []
        await kept.uploadWaiting(to: repository, largeToo: true)?.value
        XCTAssertEqual(copies("Sunday").count, 1, "it goes as he leaves")
        XCTAssertTrue(text(of: copies("Sunday").first)
                        .contains(String(photoBytes.base64EncodedString().prefix(60))))
        XCTAssertEqual(kept.waiting.count, 0)
        XCTAssertEqual(passTime.begun, ["Upload Drafts"])
    }

    /// A pass holds background time from its start to its end, given back
    /// once, and when iOS wants it back first it gets it then and the
    /// letter still goes. With nothing waiting nothing is asked for.
    func testAPassHoldsBackgroundTimeWhileItGoes() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        try await page(repository)
        XCTAssertNil(kept.uploadWaiting(to: repository))
        XCTAssertEqual(passTime.begun, [], "nothing waiting, nothing asked for")

        kept.keep(letter(), as: "letter-1", unfinished: false)
        await kept.uploadWaiting(to: repository)?.value
        XCTAssertEqual(passTime.begun, ["Upload Drafts"])
        XCTAssertEqual(passTime.ended, [1])

        kept.keep(letter("Monday"), as: "letter-2", unfinished: false)
        server.holdReplies(to: "APPEND")
        let pass = try XCTUnwrap(kept.uploadWaiting(to: repository))
        try await until { server.log.filter { $0.verb == "APPEND" }.count == 2 }
        passTime.expire(2)
        XCTAssertEqual(passTime.ended, [1, 2])
        await server.releaseReplies(to: "APPEND")
        await pass.value
        XCTAssertEqual(passTime.ended, [1, 2], "given back once")
        XCTAssertEqual(copies("Monday").count, 1)
    }

    // MARK: - Another account

    /// A letter kept while the app ran as another account goes to no
    /// account's Drafts by itself. It is listed with the rest, and opened
    /// it comes without the files it named on the server, which in this
    /// account could be a part of another letter; saved from the composer
    /// it is this account's.
    func testALetterWrittenInAnotherAccountIsNotUploadedByItself() async throws {
        let other = makeKept(account: "someone-else@example.net")
        var draft = letter()
        draft.attachments = [DraftAttachment(
            source: .messagePart(messageID: "\(server.uidValidity(of: Server.inbox))/1004",
                                 mailboxID: Server.inbox, section: "2"),
            filename: "Receipt.pdf", mimeType: "application/pdf", size: 4_000)]
        other.keep(draft, as: "letter-1", unfinished: false)

        let kept = makeKept()
        let repository = makeRepository()
        try await afterAPage(kept, repository)
        await kept.uploadWaiting(to: repository, largeToo: true)?.value
        XCTAssertEqual(appends, 0)
        XCTAssertEqual(kept.waiting.map(\.key), ["letter-1"], "listed all the same")

        let opened = try XCTUnwrap(kept.letter("letter-1")).draft
        XCTAssertEqual(opened.attachments.count, 0)
        XCTAssertEqual(opened.body, "Lunch at one?")
        await makeActions("letter-1", kept: kept, repository: repository)
            .saveAndClose({ opened }, then: nil)?.value
        XCTAssertEqual(copies("Sunday").count, 1)
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    // MARK: - Cut off after the server had it

    /// The APPEND reaches Gmail and the line dies before the answer: the
    /// server has the letter and the iPad cannot know it, so it stays kept.
    /// The next upload asks Drafts for it first, finds it, and takes it as
    /// its own: one copy, never two.
    func testAnUploadCutOffAfterTheServerHadItIsNotSentAgain() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        try await savedAndCutOff(letter(), kept: kept, repository: repository)
        XCTAssertEqual(copies("Sunday").count, 1, "the server took it")
        XCTAssertEqual(kept.waiting.map(\.key), ["letter-1"], "and never said so")

        try await afterAPage(kept, repository)
        XCTAssertEqual(appends, 1, "not sent again")
        XCTAssertEqual(copies("Sunday").count, 1)
        XCTAssertTrue(server.log.contains {
            $0.verb == "UID SEARCH" && $0.command.contains("HEADER Message-ID")
        })
        XCTAssertEqual(kept.waiting.count, 0)
    }

    /// Cut off the same way, then reopened from the iPad and changed: the
    /// new version goes up, and the copy the cut-off upload left is
    /// removed. One copy, the newer.
    func testANewerVersionReplacesTheCopyACutOffUploadLeft() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        try await savedAndCutOff(letter(), kept: kept, repository: repository)
        XCTAssertEqual(copies("Sunday").count, 1)

        var reopened = try XCTUnwrap(kept.letter("letter-1")).draft
        reopened.body = "Lunch at two, not one."
        await makeActions("letter-1", kept: kept, repository: repository)
            .saveAndClose({ reopened }, then: nil)?.value

        let left = copies("Sunday")
        XCTAssertEqual(left.count, 1)
        XCTAssertTrue(text(of: left.first).contains("Lunch at two"))
        XCTAssertEqual(kept.waiting.count, 0)
    }

    /// A draft reopened from Drafts and saved, its upload cut off after the
    /// server had it: the next upload takes the copy that landed as its
    /// own, sends nothing again, and removes the copy it was reopened from.
    func testAReopenedDraftCutOffReplacesItsCopyOnce() async throws {
        let repository = makeRepository()
        let old = try XCTUnwrap(server.uids(in: Server.drafts).first)
        var reopened = try await repository.loadDraft(
            id: "\(server.uidValidity(of: Server.drafts))/\(old)", mailboxID: Server.drafts)
        reopened.subject = "Changed on the train"
        let kept = makeKept()
        try await savedAndCutOff(reopened, kept: kept, repository: repository)
        XCTAssertTrue(server.uids(in: Server.drafts).contains(old), "not before it is answered")

        try await afterAPage(kept, repository)
        XCTAssertEqual(appends, 1)
        XCTAssertFalse(server.uids(in: Server.drafts).contains(old), "the old copy goes")
        XCTAssertEqual(copies("Changed on the train").count, 1)
        XCTAssertEqual(kept.waiting.count, 0)
    }

    /// A server that will not answer the search for the copy a cut-off
    /// upload left is taken as having none: the letter goes up again and
    /// leaves the iPad, twice in Drafts at worst, rather than never going.
    func testASearchTheServerRefusesDoesNotKeepTheLetterFromGoing() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        try await savedAndCutOff(letter(), kept: kept, repository: repository)
        server.refusedSearchKeys = ["HEADER"]

        try await afterAPage(kept, repository)
        XCTAssertEqual(server.log.filter { $0.command.contains("HEADER Message-ID") }.map(\.status),
                       ["BAD"])
        XCTAssertEqual(appends, 2)
        XCTAssertEqual(copies("Sunday").count, 2)
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    // MARK: - Sent or deleted after a cut-off upload

    /// Sent, or deleted, after an upload of it was cut off: the copy that
    /// upload left goes from Drafts too. It is known only by the Message-ID
    /// of the version that went, and throwing that record away with the
    /// letter left a sent letter in Drafts for good, where it reads as one
    /// still owed.
    func testSendOrDeleteAfterACutOffUploadLeavesNothingInDrafts() async throws {
        for ending in ["send", "delete"] {
            server = ScriptedIMAPServer()
            try? FileManager.default.removeItem(at: root)
            let kept = makeKept()
            let repository = makeRepository()
            try await savedAndCutOff(letter(), kept: kept, repository: repository)
            XCTAssertEqual(copies("Sunday").count, 1, ending)

            let reopened = try XCTUnwrap(kept.letter("letter-1")).draft
            let actions = makeActions("letter-1", kept: kept, repository: repository)
            if ending == "send" {
                await actions.send({ reopened }, then: nil)?.value
            } else {
                await actions.deleteAndClose(reopened.savedID, letter: reopened.savedLetter,
                                             then: nil)?.value
            }
            XCTAssertEqual(errors, [], ending)
            XCTAssertEqual(copies("Sunday").count, 0, "\(ending): nothing of it left in Drafts")
            XCTAssertEqual(kept.store.letters().count, 0, ending)
        }
        let sent = await submissions.count()
        XCTAssertEqual(sent, 1)
    }

    /// Sent from the Outbox by a pass after an upload of it was cut off: the
    /// copy that upload left goes from Drafts too, and nothing of the letter
    /// is left on the iPad, as for one sent from the composer (B-052).
    func testALetterSentByAPassAfterACutOffUploadLeavesNothingInDrafts() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        try await savedAndCutOff(letter(), kept: kept, repository: repository)
        XCTAssertEqual(copies("Sunday").count, 1)

        let reopened = try XCTUnwrap(kept.letter("letter-1")).draft
        line.isUp = false
        await makeActions("letter-1", kept: kept, repository: repository)
            .send({ reopened }, then: nil)?.value
        line.isUp = true
        XCTAssertEqual(kept.outbox.map(\.key), ["letter-1"], "waiting in the Outbox")

        try await afterAPage(kept, repository)
        let sent = await submissions.count()
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(copies("Sunday").count, 0, "nothing of it left in Drafts")
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// Deleted with no connection after a cut-off upload: off the iPad at
    /// once, never listed again, and the copy goes with the next pass.
    func testADeleteThatCannotReachDraftsIsFinishedByTheNextPass() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        try await savedAndCutOff(letter(), kept: kept, repository: repository)
        await takeLineDown()
        await makeActions("letter-1", kept: kept, repository: repository)
            .deleteAndClose(nil, letter: nil, then: nil)?.value
        XCTAssertEqual(kept.waiting.count, 0, "not listed")
        XCTAssertNil(kept.letter("letter-1"))
        XCTAssertEqual(kept.store.letter("letter-1")?.gone, true)

        line.isUp = true
        try await afterAPage(makeKept(), repository)
        XCTAssertEqual(copies("Sunday").count, 0)
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// Deleted while a pass is taking it up but before its APPEND has gone:
    /// the APPEND never goes. Nothing of it was on the server, so nothing
    /// was left to find, and a letter that went up after it had been
    /// deleted would be in Drafts for good.
    func testALetterDeletedBeforeItsUploadReachesTheServerNeverGetsThere() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await savedOffline(letter(), kept: kept, repository: repository)
        try await page(repository)
        clock.advance(by: 91)
        server.holdReplies(to: "NOOP")
        let pass = try XCTUnwrap(kept.uploadWaiting(to: repository))
        try await until { server.log.contains { $0.verb == "NOOP" } }

        let deleting = makeActions("letter-1", kept: kept, repository: repository)
            .deleteAndClose(nil, letter: nil, then: nil)
        await server.releaseReplies(to: "NOOP")
        await pass.value
        await deleting?.value
        XCTAssertEqual(appends, 0)
        XCTAssertEqual(copies("Sunday").count, 0)
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// Delete in Drafts' Edit mode on a letter kept here: off the iPad, the
    /// copy a cut-off upload left removed, and nothing handed to the server
    /// under the row's own id, which no server letter has.
    func testDeleteInEditModeTakesAKeptLetterAndItsCopy() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        try await savedAndCutOff(letter(), kept: kept, repository: repository)
        let row = try XCTUnwrap(kept.waiting.first).row(in: Server.drafts, from: "Owner")
        let key = try XCTUnwrap(LocalDraft.key(ofRow: row.id))

        await kept.delete(key, from: repository)
        XCTAssertEqual(copies("Sunday").count, 0)
        XCTAssertEqual(kept.store.letters().count, 0)
        XCTAssertFalse(server.log.contains { $0.command.contains("local:") })
    }

    // MARK: - Opened while it goes up

    /// Opened from its row while a pass takes it up, changed and saved:
    /// one copy, the newer. The pass used to take it off the iPad as it
    /// landed, and the save then put a second copy beside the first.
    func testALetterOpenedWhileItGoesUpAndSavedIsOneCopy() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        let (actions, opened) = try await openedWhileItGoesUp(letter(), kept: kept,
                                                               repository: repository)
        var changed = opened
        changed.body = "Lunch at two, not one."
        await actions.saveAndClose({ changed }, then: nil)?.value

        let left = copies("Sunday")
        XCTAssertEqual(left.count, 1, "one letter, one copy")
        XCTAssertTrue(text(of: left.first).contains("Lunch at two"))
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// The same, saved while the pass's APPEND is still unanswered: the
    /// save waits for it, then goes. One copy, the newer.
    func testALetterSavedWhileItGoesUpWaitsForItAndIsOneCopy() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await savedOffline(letter(), kept: kept, repository: repository)
        try await page(repository)
        server.holdReplies(to: "APPEND")
        let pass = try XCTUnwrap(kept.uploadWaiting(to: repository))
        try await until { server.log.contains { $0.verb == "APPEND" } }
        var changed = try XCTUnwrap(kept.letter("letter-1")).draft
        changed.body = "Lunch at two, not one."
        let saving = makeActions("letter-1", kept: kept, repository: repository)
            .saveAndClose({ changed }, then: nil)
        await server.releaseReplies(to: "APPEND")
        await pass.value
        await saving?.value

        let left = copies("Sunday")
        XCTAssertEqual(left.count, 1)
        XCTAssertTrue(text(of: left.first).contains("Lunch at two"))
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// Opened while it goes up and then deleted: nothing left in Drafts,
    /// the copy that landed included.
    func testALetterOpenedWhileItGoesUpAndDeletedLeavesNothing() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        let (actions, opened) = try await openedWhileItGoesUp(letter(), kept: kept,
                                                               repository: repository)
        await actions.deleteAndClose(opened.savedID, letter: opened.savedLetter, then: nil)?.value
        XCTAssertEqual(copies("Sunday").count, 0)
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// Opened while it goes up and closed untouched: it is on the server as
    /// it stands, and leaves the iPad as the sheet goes, rather than being
    /// listed beside its own copy until the next pass.
    func testALetterOpenedWhileItGoesUpAndLeftAloneLeavesTheIPad() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        let (actions, opened) = try await openedWhileItGoesUp(letter(), kept: kept,
                                                               repository: repository)
        XCTAssertNotNil(kept.store.letter("letter-1"), "kept while it is open")
        actions.sheetGone { opened }
        XCTAssertEqual(kept.store.letters().count, 0)
        XCTAssertEqual(copies("Sunday").count, 1)
    }

    /// A letter with a photo, opened while it goes up: its photo is still
    /// there after the upload lands, so Send sends it, and Save Draft keeps
    /// it in the copy that goes up. Taken off the iPad as it landed, the
    /// photo went from under the open letter: Send failed, and Save Draft
    /// dropped it without a word.
    func testAPhotoLetterOpenedWhileItGoesUpKeepsItsPhoto() async throws {
        for ending in ["send", "save"] {
            server = ScriptedIMAPServer()
            try? FileManager.default.removeItem(at: root)
            let kept = makeKept()
            let repository = makeRepository()
            let (actions, opened) = try await openedWhileItGoesUp(try photoLetter(), kept: kept,
                                                                   repository: repository)
            guard case .localFile(let url)? = opened.attachments.first?.source else {
                return XCTFail("the photo should be a file of the kept letter")
            }
            XCTAssertEqual(try Data(contentsOf: url), photoBytes, ending)

            if ending == "send" {
                await actions.send({ opened }, then: nil)?.value
                XCTAssertEqual(errors, [], "sent")
                XCTAssertEqual(copies("Sunday").count, 0, "and not left in Drafts")
            } else {
                await actions.saveAndClose({ opened }, then: nil)?.value
                let left = copies("Sunday")
                XCTAssertEqual(left.count, 1)
                XCTAssertTrue(text(of: left.first)
                                .contains(String(photoBytes.base64EncodedString().prefix(60))),
                              "the photo went up with it")
            }
            XCTAssertEqual(kept.store.letters().count, 0, ending)
        }
        let sent = await submissions.count()
        XCTAssertEqual(sent, 1)
    }

    /// Kept again while its upload is on the wire, the newer text stays on
    /// the iPad to go next time, and then replaces the copy that landed.
    func testALetterKeptAgainWhileItGoesUpStaysToGoNextTime() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await savedOffline(letter(), kept: kept, repository: repository)
        try await page(repository)
        server.holdReplies(to: "APPEND")
        let pass = try XCTUnwrap(kept.uploadWaiting(to: repository))
        try await until { server.log.contains { $0.verb == "APPEND" } }
        kept.keep(letter(body: "Lunch at two, not one."), as: "letter-1", unfinished: false)
        await server.releaseReplies(to: "APPEND")
        await pass.value
        XCTAssertEqual(kept.letter("letter-1")?.draft.body, "Lunch at two, not one.")

        await kept.uploadWaiting(to: repository)?.value
        let left = copies("Sunday")
        XCTAssertEqual(left.count, 1)
        XCTAssertTrue(text(of: left.first).contains("Lunch at two"))
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    // MARK: - Photos

    /// A kept letter's photos are its own files, not the composer's staged
    /// ones, which every launch deletes: after the purge and a relaunch the
    /// photo is still there, byte for byte, and goes up with the letter.
    func testThePhotosOfAKeptLetterSurviveTheLaunchPurge() async throws {
        let draft = try photoLetter()
        guard case .localFile(let staged)? = draft.attachments.first?.source else {
            return XCTFail("staged")
        }
        let kept = makeKept()
        let repository = makeRepository()
        await savedOffline(draft, kept: kept, repository: repository)

        AttachmentStore.purge()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))

        let relaunched = makeKept()
        let back = try XCTUnwrap(relaunched.letter("letter-1"))
        XCTAssertEqual(back.draft.attachments.map(\.filename), ["Garden.jpg"])
        guard case .localFile(let url)? = back.draft.attachments.first?.source else {
            return XCTFail("the photo should be a file of the kept letter")
        }
        XCTAssertEqual(try Data(contentsOf: url), photoBytes)

        try await afterAPage(relaunched, repository)
        let copy = try XCTUnwrap(copies("Sunday").first)
        XCTAssertTrue(text(of: copy).contains(String(photoBytes.base64EncodedString().prefix(60))))
        XCTAssertEqual(relaunched.waiting.count, 0)
    }

    /// A photo he removes goes from the letter's directory as well.
    func testAPhotoRemovedFromAKeptLetterLeavesItsDirectory() throws {
        let store = LocalDraftStore(root: root)
        var draft = try photoLetter()
        let second = try AttachmentStore.write(Data(photoBytes.reversed()), named: "Roof.jpg")
        draft.attachments.append(DraftAttachment(source: .localFile(second), filename: "Roof.jpg",
                                                 mimeType: "image/jpeg",
                                                 size: Int64(photoBytes.count)))
        try store.keep(draft, as: "letter-1", unfinished: true, account: server.username)
        let folder = root.appendingPathComponent("letter-1")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 3)

        draft = try XCTUnwrap(store.letter("letter-1")).draft
        draft.attachments.removeLast()
        try store.keep(draft, as: "letter-1", unfinished: true, account: server.username)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 2,
                       "the letter and its one photo")
        XCTAssertEqual(store.letter("letter-1")?.draft.attachments.map(\.filename), ["Garden.jpg"])
    }

    // MARK: - Autosave, and a relaunch

    /// Kept a pause after he stops typing, and at once when he leaves the
    /// app, inside background time given back once. Not listed in Drafts
    /// while the composer has it open.
    func testAutosaveKeepsTheLetterAfterAPauseAndOnLeavingTheApp() async throws {
        let kept = makeKept()
        let actions = makeActions("letter-1", kept: kept, repository: makeRepository())
        var draft = letter(body: "Dear Carlo,")
        actions.edited { draft }
        try await until { pauses.waiting == 1 }
        XCTAssertNil(kept.letter("letter-1"), "nothing kept while he types")

        pauses.release()
        try await until { kept.letter("letter-1") != nil }
        XCTAssertEqual(kept.letter("letter-1")?.draft.body, "Dear Carlo,")
        XCTAssertEqual(kept.letter("letter-1")?.unfinished, true)
        XCTAssertEqual(kept.waiting.count, 0, "not listed while it is open")

        draft.body = "Dear Carlo, the roof"
        actions.edited { draft }
        actions.putAside { draft }
        XCTAssertEqual(kept.letter("letter-1")?.draft.body, "Dear Carlo, the roof", "at once")
        XCTAssertEqual(background.begun, ["Keep Draft"])
        XCTAssertEqual(background.ended, [1])
        pauses.release()
    }

    /// iOS ends the app with a letter half written: the next launch lists
    /// it in Drafts, marked as on the iPad, with every word, and takes it
    /// to the server's Drafts at the first chance.
    func testARelaunchFindsTheUnfinishedLetter() async throws {
        let kept = makeKept()
        let actions = makeActions("letter-1", kept: kept, repository: makeRepository())
        let draft = letter(body: "Dear Carlo, about the roof and the gutter")
        actions.edited { draft }
        actions.putAside { draft }
        // Ended here: nothing more runs.

        let relaunched = makeKept()
        let found = try XCTUnwrap(relaunched.waiting.first)
        XCTAssertEqual(relaunched.waiting.count, 1)
        XCTAssertEqual(found.draft.body, "Dear Carlo, about the roof and the gutter")
        XCTAssertEqual(found.draft.subject, "Sunday")
        XCTAssertTrue(found.unfinished)
        let row = found.row(in: Server.drafts, from: "Owner")
        XCTAssertTrue(row.preview.hasPrefix(LocalDraft.mark))
        XCTAssertEqual(LocalDraft.key(ofRow: row.id), "letter-1")

        try await afterAPage(relaunched, makeRepository())
        XCTAssertEqual(copies("Sunday").count, 1)
        XCTAssertEqual(relaunched.waiting.count, 0)
    }

    /// Kept letters are listed, and taken up, newest first.
    func testKeptLettersAreListedNewestFirst() {
        let kept = makeKept()
        kept.keep(letter("First"), as: "first", unfinished: false)
        kept.keep(letter("Second"), as: "second", unfinished: true)
        kept.keep(letter("Third"), as: "third", unfinished: false)
        kept.keep(letter("First, again"), as: "first", unfinished: false)
        XCTAssertEqual(makeKept().waiting.map(\.key), ["first", "third", "second"])
    }

    // MARK: - A sheet closed without Send, Save or Delete

    /// A letter reopened from the iPad and closed untouched stays kept, as
    /// it was: it was here before the sheet opened. A new letter the
    /// autosave kept, then emptied and swiped away, leaves nothing.
    func testASheetClosedUntouchedLeavesAKeptLetterAndANewOneEmptiedGoes() async throws {
        let kept = makeKept()
        let repository = makeRepository()
        await savedOffline(letter(), kept: kept, repository: repository)
        let reopened = try XCTUnwrap(kept.letter("letter-1")).draft
        makeActions("letter-1", kept: kept, repository: repository).sheetGone { reopened }
        XCTAssertEqual(kept.waiting.map(\.key), ["letter-1"], "untouched, it stays kept")
        XCTAssertEqual(kept.waiting.first?.draft.body, "Lunch at one?")

        let actions = makeActions("letter-2", kept: kept, repository: repository)
        actions.edited { [unowned self] in letter("Monday") }
        try await until { pauses.waiting == 1 }
        pauses.release()
        try await until { kept.store.letter("letter-2") != nil }
        actions.edited { Draft() }
        actions.sheetGone { Draft() }
        XCTAssertNil(kept.store.letter("letter-2"), "emptied and swiped away, nothing is left")
        XCTAssertEqual(kept.waiting.map(\.key), ["letter-1"])
    }

    // MARK: - Nothing left behind

    /// A letter sent, saved or deleted leaves nothing on the iPad, not even
    /// an autosave that was waiting for him to stop.
    func testSendSaveAndDeleteLeaveNothingBehind() async throws {
        for ending in ["send", "save", "delete"] {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let kept = makeKept()
            let actions = makeActions(ending, kept: kept, repository: makeRepository())
            let draft = letter(ending)
            actions.edited { draft }
            try await until { pauses.waiting == 1 }
            pauses.release()
            try await until { kept.letter(ending) != nil }
            actions.edited { draft }
            try await until { pauses.waiting == 1 }

            switch ending {
            case "send": await actions.send({ draft }, then: nil)?.value
            case "save": await actions.saveAndClose({ draft }, then: nil)?.value
            default: await actions.deleteAndClose(nil, letter: nil, then: nil)?.value
            }
            pauses.release()
            for _ in 0..<5 { await Task.yield() }

            XCTAssertEqual(errors, [], ending)
            XCTAssertNil(kept.letter(ending), ending)
            XCTAssertEqual(kept.store.letters().count, 0, ending)
            XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [],
                           [], ending)
        }
        XCTAssertEqual(copies("save").count, 1)
        let sent = await submissions.count()
        XCTAssertEqual(sent, 1)
    }

    // MARK: - A damaged store

    /// A letter's file cut off halfway, one that is not JSON at all, a
    /// directory with no letter in it, a stray file, and a letter of a
    /// format this build does not know: each is passed over, left where it
    /// is, and the rest are listed and go up as usual.
    func testAStoreWithADamagedFileIgnoresThatLetterAndCarriesOn() async throws {
        let store = LocalDraftStore(root: root)
        let account = server.username
        try store.keep(letter("Good"), as: "good", unfinished: false, account: account)
        try store.keep(letter("Cut"), as: "cut", unfinished: false, account: account)
        try store.keep(letter("Future"), as: "future", unfinished: false, account: account)

        let files = FileManager.default
        let cut = root.appendingPathComponent("cut/letter.json")
        let whole = try Data(contentsOf: cut)
        try whole.prefix(whole.count / 2).write(to: cut)
        try files.createDirectory(at: root.appendingPathComponent("garbage"),
                                  withIntermediateDirectories: true)
        try Data("not a letter".utf8).write(to: root.appendingPathComponent("garbage/letter.json"))
        try files.createDirectory(at: root.appendingPathComponent("empty"),
                                  withIntermediateDirectories: true)
        try Data("stray".utf8).write(to: root.appendingPathComponent("stray.txt"))
        let future = root.appendingPathComponent("future/letter.json")
        let newer = String(decoding: try Data(contentsOf: future), as: UTF8.self)
            .replacingOccurrences(of: "\"format\":1", with: "\"format\":2")
        try Data(newer.utf8).write(to: future)

        XCTAssertEqual(store.letters().map(\.key), ["good"])
        XCTAssertNil(store.letter("cut"))
        XCTAssertNil(store.letter("garbage"))
        XCTAssertNil(store.letter("future"))
        XCTAssertTrue(files.fileExists(atPath: cut.path), "never deleted: it may be all there is")

        let kept = makeKept()
        XCTAssertEqual(kept.waiting.map(\.key), ["good"])
        try await afterAPage(kept, makeRepository())
        XCTAssertEqual(copies("Good").count, 1)
        XCTAssertEqual(kept.waiting.count, 0)
        XCTAssertTrue(files.fileExists(atPath: cut.path))
    }

    // MARK: - In Drafts

    /// The kept letters go above Drafts' own, in place of the copies they
    /// will replace, and nothing else in the list moves: the folder's
    /// letters keep their order, paging walks on from the same letter, and
    /// a search shows only its hits.
    func testKeptLettersAreListedAboveDraftsAndMoveNothingElse() {
        let list = ListLetters()
        _ = list.fetchedAfresh([row("1/9", "Roof"), row("1/8", "Sunday"), row("1/7", "Gutter")])
        var kept = letter()
        kept.savedID = "1/8"
        let local = LocalDraft(key: "letter-1", draft: kept, version: "v", tried: [],
                               unfinished: false, keptAt: Date(timeIntervalSince1970: 60),
                               account: server.username, gone: false)
            .row(in: Server.drafts, from: "Owner")

        list.keep([local], replacing: ["1/8": nil])
        XCTAssertEqual(list.shown.map(\.id), [local.id, "1/9", "1/7"])
        XCTAssertEqual(list.cursor, "1/7")
        XCTAssertEqual(MessageThread.rows(for: list.shown, grouped: true).map(\.id),
                       [local.id, "1/9", "1/7"],
                       "never grouped with a letter of the same subject")

        list.showResults([row("1/9", "Roof")])
        XCTAssertEqual(list.shown.map(\.id), ["1/9"])
        list.endSearch()
        XCTAssertEqual(list.shown.map(\.id), [local.id, "1/9", "1/7"])

        list.keep([], replacing: [:])
        XCTAssertEqual(list.shown.map(\.id), ["1/9", "1/8", "1/7"])
    }

    /// A letter that has reached the server is drawn as its copy there in
    /// place of the copies that went, without a fetch: at the top of the
    /// folder when the list starts at the top, where the one it replaced
    /// stood among a search's hits, and taken off both; paging walks on
    /// from the same letter. It used to fetch the newest page again, which
    /// ended a search, left the removed copy among the hits of one it could
    /// not end, and took him back to the top.
    func testALetterThatLandsIsDrawnAsItsCopyWithoutAFetch() {
        let list = ListLetters()
        _ = list.fetchedAfresh([row("1/9", "Roof"), row("1/8", "Sunday"), row("1/7", "Gutter")])
        list.showResults([row("1/9", "Roof"), row("1/8", "Sunday")])
        var draft = letter()
        draft.savedID = "1/8"
        let copy = LocalDraft(key: "letter-1", draft: draft, version: "v", tried: [],
                              unfinished: false, keptAt: Date(timeIntervalSince1970: 60),
                              account: server.username, gone: false)
            .row(in: Server.drafts, from: "Owner", onServerAs: "1/10")
        XCTAssertFalse(copy.preview.hasPrefix(LocalDraft.mark))

        list.landed(copy, replacing: ["1/8"], atTop: true)
        XCTAssertEqual(list.shown.map(\.id), ["1/9", "1/10"], "in the hits, where it was")
        list.endSearch()
        XCTAssertEqual(list.shown.map(\.id), ["1/10", "1/9", "1/7"])
        XCTAssertEqual(list.cursor, "1/7")

        // A list opened at a day starts below the newest letter: the copy
        // is not put at its top, and the removed copy still goes.
        let window = ListLetters()
        window.showWindow([row("1/5", "Old"), row("1/4", "Older")])
        window.landed(copy, replacing: ["1/4"], atTop: false)
        XCTAssertEqual(window.shown.map(\.id), ["1/5"])
        // Leftovers of a letter sent or deleted: taken off, nothing drawn.
        window.landed(nil, replacing: ["1/5"], atTop: false)
        XCTAssertEqual(window.shown.map(\.id), [])
    }

    private func row(_ id: String, _ subject: String) -> MessageSummary {
        MessageSummary(id: id, mailboxID: Server.drafts, sender: "Owner", subject: subject,
                       preview: "", date: Date(timeIntervalSince1970: 0), isRead: true,
                       isFlagged: false, threadID: "t-" + id)
    }
}

/// Whether the network is there. With it down every connection is refused.
private final class Line: @unchecked Sendable {
    private let lock = NSLock()
    private var up = true

    var isUp: Bool {
        get { lock.lock(); defer { lock.unlock() }; return up }
        set { lock.lock(); up = newValue; lock.unlock() }
    }
}

/// A submission server per connection, as the SMTP client makes one per
/// letter, and every letter any of them was given.
private final class Submissions: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [ScriptedSubmission] = []

    func next() -> ScriptedSubmission {
        let server = ScriptedSubmission()
        lock.lock()
        made.append(server)
        lock.unlock()
        return server
    }

    func count() async -> Int {
        lock.lock()
        let servers = made
        lock.unlock()
        var total = 0
        for server in servers { total += await server.letters.count }
        return total
    }
}
