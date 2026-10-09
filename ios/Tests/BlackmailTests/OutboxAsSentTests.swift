import XCTest
@testable import Blackmail

/// The Outbox as Mail's (B-083): a letter goes as it was when he tapped
/// Send. The name in its From, its Date and its signature are kept with it
/// as it enters the Outbox (`LocalDraft.atSend`), and every attempt at it is
/// made with them, whatever is saved in Settings meanwhile. Opened from the
/// Outbox and sent again, it keeps its name and its signature and takes the
/// time of the new Send. A letter put in the Outbox by a build before this,
/// or one whose fields cannot be read, goes as it went before: from the
/// account as saved, at the attempt's time.
///
/// These run the composer's own wiring (`ComposeActions(letter:…)`), the
/// shipping `LocalDrafts` over a directory of the test's own, the shipping
/// repository over the scripted IMAP server, and a scripted submission
/// server per connection. Settings' Save is the account handed to the
/// repository as `CredentialStore` would hand it (B-082).
@MainActor
final class OutboxAsSentTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "OutboxAsSentTests"
    private static let newName = "Carlo Renamed Example"

    private var server: ScriptedIMAPServer!
    private var saved: AccountSaved!
    private var line: LineState!
    private var submissions: SubmissionServers!
    private var book: RecipientBook!
    /// The store's clock: a second later at every reading.
    private var keptClock: ManualClock!
    private var root: URL!
    private var background = FakeBackground()
    private var passTime = FakeBackground()
    private var pauses = Held()
    private var dismissals = 0
    private var queued = 0
    private var errors: [MailError] = []

    override func setUp() async throws {
        try await super.setUp()
        server = ScriptedIMAPServer()
        saved = AccountSaved(nil)
        saved.account = launched
        line = LineState()
        submissions = SubmissionServers()
        keptClock = ManualClock()
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: UserDefaults(suiteName: Self.suite)!)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("OutboxAsSentTests-\(UUID().uuidString)", isDirectory: true)
        background = FakeBackground()
        passTime = FakeBackground()
        pauses = Held()
        dismissals = 0
        queued = 0
        errors = []
    }

    override func tearDown() async throws {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        if let root {
            // The letters, and any folder they were set aside in beside them.
            let parent = root.deletingLastPathComponent()
            for name in (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
            where name.hasPrefix(root.lastPathComponent) {
                try? FileManager.default.removeItem(at: parent.appendingPathComponent(name))
            }
        }
        for outcome in ["ok", "fail"] {
            let transcript = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
            try? FileManager.default.removeItem(atPath: transcript)
        }
        pauses.release()
        server = nil
        saved = nil
        line = nil
        submissions = nil
        book = nil
        keptClock = nil
        root = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// The account as the app launched with it: named, with a signature
    /// and its formatted twin.
    private var launched: MailAccount {
        var account = server.account
        account.displayName = "Carlo"
        account.signature = "Carlo\n1 Example Street"
        account.signatureHTML = "<table><tr><td><b>Carlo</b></td></tr></table>"
        return account
    }

    /// The app's repository over the scripted servers, made at launch with
    /// `account`, `launched` if none, reading what Settings saved.
    private func makeRepository(launchedAs account: MailAccount? = nil) -> IMAPMailRepository {
        let imap = server.transportFactory
        let line = self.line!
        let saved = self.saved!
        let submissions = self.submissions!
        return IMAPMailRepository(
            account: account ?? launched, password: server.password,
            transport: { host, port in
                guard line.isUp else {
                    return port == 465 ? ScriptedSubmission(failsToOpen: true) : imap(host, 1)
                }
                return port == 465 ? submissions.next() : imap(host, port)
            },
            saved: { saved.account },
            recipients: book,
            signatureImages: { [] },
            shelf: keptShelf(for: server.account))
    }

    /// The app's `LocalDrafts` over this test's directory. A second one
    /// over the same directory is the app launched again.
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
                              queued: { [unowned self] in queued += 1 },
                              wait: { [pauses] _ in try await pauses.wait() })
    }

    /// A new letter, signed as the composer signs one with the signature
    /// saved now.
    private func letter(_ subject: String) -> Draft {
        var draft = Draft.blank(signature: saved.account?.signature ?? "")
        draft.to = ["jane@example.com"]
        draft.subject = subject
        draft.body = "Lunch at one?" + draft.body
        return draft
    }

    /// Send tapped in the composer on `draft`, kept as `key`, to the end.
    private func send(_ draft: Draft, as key: String, kept: LocalDrafts,
                      repository: IMAPMailRepository) async {
        await makeActions(key, kept: kept, repository: repository).send({ draft }, then: nil)?.value
    }

    /// Send tapped with the line down: the letter goes to the Outbox, and
    /// the line comes back.
    private func sentOffline(_ draft: Draft, as key: String, kept: LocalDrafts,
                             repository: IMAPMailRepository) async {
        line.isUp = false
        await send(draft, as: key, kept: kept, repository: repository)
        line.isUp = true
    }

    /// A folder's newest page, so the connection is up for a pass, and the
    /// pass `kind`.
    private func pass(_ kept: LocalDrafts, _ repository: IMAPMailRepository,
                      _ kind: LocalDrafts.Pass = .unasked) async throws {
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        await kept.uploadWaiting(to: repository, for: kind)?.value
    }

    /// Save in Settings, as `CredentialStore.saveAccountOnly` stores it.
    private func save(_ change: (inout MailAccount) -> Void) {
        var account = saved.account ?? launched
        change(&account)
        saved.account = account
    }

    private func rename(_ name: String) {
        save { $0.displayName = name }
    }

    /// Every letter the submission servers were handed, in order.
    private func letters() async -> [Data] {
        var out: [Data] = []
        for server in submissions.all { out += await server.letters }
        return out
    }

    private func lastLetter() async throws -> Data {
        let all = await letters()
        return try XCTUnwrap(all.last)
    }

    private func header(_ name: String, _ raw: Data) -> String? {
        MIMEDecoder.headerValue(name, in: MIMEDecoder.parseHeaders(raw)).map(MIMEDecoder.decodeWord)
    }

    private func from(_ raw: Data) -> String? { header("From", raw) }

    /// The letter's Date header, read back to the second.
    private func date(_ raw: Data) -> Date? {
        guard let value = header("Date", raw) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return f.date(from: value)
    }

    /// The Date header a letter made at `time` carries.
    private func dated(_ time: Date) -> String {
        RFC5322Builder.rfc5322Date(time)
    }

    /// The letter kept as `key` in the Outbox, and what it went in with.
    private func waiting(_ key: String, in kept: LocalDrafts) throws -> (LocalDraft, Date) {
        let letter = try XCTUnwrap(kept.store.letter(key))
        XCTAssertNotNil(letter.outbox, "in the Outbox")
        return (letter, try XCTUnwrap(letter.atSend.date))
    }

    /// `letter.json` of the letter kept as `key`, changed by hand, as an
    /// older build, or a damaged file, would leave it.
    private func editStored(_ key: String, _ change: (inout [String: Any]) -> Void) throws {
        let url = root.appendingPathComponent(key, isDirectory: true)
            .appendingPathComponent("letter.json")
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)) as? [String: Any])
        change(&json)
        try JSONSerialization.data(withJSONObject: json).write(to: url, options: .atomic)
    }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    /// Opened from the Outbox in the composer and changed, kept by the
    /// autosave, which takes it out of the Outbox while the composer has it.
    private func openedAndChanged(_ key: String, kept: LocalDrafts,
                                  repository: IMAPMailRepository) async throws
        -> (ComposeActions, Draft) {
        var typed = try XCTUnwrap(kept.letter(key)).draft
        let actions = makeActions(key, kept: kept, repository: repository)
        typed.body = "Or at two." + typed.body
        actions.edited { typed }
        try await until { pauses.waiting > 0 }
        pauses.release()
        try await until { kept.store.letter(key)?.outbox == nil }
        return (actions, typed)
    }

    // MARK: - Sent with the line down, then the name changed

    /// The owner's case: sent with no connection, the name changed in
    /// Settings, then the line back. It goes From the name it was sent
    /// with, dated when Send was tapped, under the Message-ID it went into
    /// the Outbox with. A letter written after the change goes From the new
    /// name, dated as it goes.
    func testALetterQueuedGoesWithTheNameAndTheTimeOfItsSend() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        await sentOffline(letter("B-083 queued"), as: "queued", kept: kept, repository: repository)
        XCTAssertEqual(queued, 1)
        let (waitingLetter, sentAt) = try waiting("queued", in: kept)
        XCTAssertEqual(waitingLetter.atSend.name, "Carlo")
        XCTAssertEqual(kept.outboxRows.count, 1)

        rename(Self.newName)
        keptClock.advance(by: 3_600)
        try await pass(kept, repository)
        XCTAssertEqual(kept.outbox.count, 0)
        let sent = await letters()
        XCTAssertEqual(sent.count, 1)
        let raw = try XCTUnwrap(sent.first)
        XCTAssertEqual(from(raw), "Carlo <\(server.username)>")
        XCTAssertEqual(header("Date", raw), dated(sentAt), "the time of his Send")
        XCTAssertEqual(header("Message-ID", raw), waitingLetter.outbox)

        let before = Date(timeIntervalSinceNow: -1)
        try await repository.send(letter("B-083 after"))
        let after = try await lastLetter()
        XCTAssertEqual(from(after), "\(Self.newName) <\(server.username)>", "the next letter")
        let afterDate = try XCTUnwrap(date(after))
        XCTAssertGreaterThanOrEqual(afterDate, before.addingTimeInterval(-1))
        XCTAssertLessThanOrEqual(afterDate, Date().addingTimeInterval(1))
    }

    /// A first attempt cut off after its DATA, the line then back: Sent
    /// Mail is asked, and the second attempt is the same letter, its From,
    /// its Date and its Message-ID those of the first, made at his Send,
    /// though the name was changed between the two.
    func testASecondAttemptIsTheLetterOfTheFirst() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        submissions.then { ScriptedSubmission(hangsUpBeforeLetterReply: true) }
        await send(letter("B-083 cut off"), as: "cut", kept: kept, repository: repository)
        XCTAssertEqual(queued, 1, "in the Outbox after a first attempt")
        let (waitingLetter, sentAt) = try waiting("cut", in: kept)
        XCTAssertEqual(waitingLetter.outboxState, .beingSent)

        rename(Self.newName)
        keptClock.advance(by: Outbox.settling)
        try await pass(kept, repository)
        let looks = server.log.filter { $0.command.contains("HEADER Message-ID") }
        XCTAssertEqual(looks.count, 1, "Sent Mail asked first")
        let sent = await letters()
        XCTAssertEqual(sent.count, 2)
        for raw in sent {
            XCTAssertEqual(from(raw), "Carlo <\(server.username)>")
            XCTAssertEqual(header("Date", raw), dated(sentAt))
            XCTAssertEqual(header("Message-ID", raw), waitingLetter.outbox)
        }
        XCTAssertEqual(kept.outbox.count, 0)
    }

    /// His Refresh, his leaving the app, a page or the watch, and the next
    /// launch: every pass makes the letter as it was sent. A new name is
    /// saved after each Send, so each letter's own name is the one before.
    func testEveryPassMakesItAsItWasSent() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let passes: [(String, LocalDrafts.Pass)] = [("refresh", .refresh), ("leaving", .leaving),
                                                    ("unasked", .unasked)]
        for (n, (key, kind)) in passes.enumerated() {
            let name = saved.account?.displayName
            await sentOffline(letter("B-083 \(key)"), as: key, kept: kept, repository: repository)
            let (_, sentAt) = try waiting(key, in: kept)
            rename("\(Self.newName) \(n + 1)")
            try await pass(kept, repository, kind)
            let raw = try await lastLetter()
            XCTAssertEqual(header("Subject", raw), "B-083 \(key)")
            XCTAssertEqual(from(raw), "\(name ?? "") <\(server.username)>", key)
            XCTAssertEqual(header("Date", raw), dated(sentAt), key)
        }

        // The next launch: the repository is made with the account as it
        // is saved now, and a new store reads the letter from its file.
        let name = try XCTUnwrap(saved.account?.displayName)
        await sentOffline(letter("B-083 relaunch"), as: "relaunch", kept: kept,
                          repository: repository)
        let (_, sentAt) = try waiting("relaunch", in: kept)
        rename(Self.newName)
        let relaunchedRepository = makeRepository(launchedAs: saved.account)
        try await pass(makeKept(), relaunchedRepository)
        let raw = try await lastLetter()
        XCTAssertEqual(header("Subject", raw), "B-083 relaunch")
        XCTAssertEqual(from(raw), "\(name) <\(server.username)>")
        XCTAssertEqual(header("Date", raw), dated(sentAt))
        let sent = await letters()
        XCTAssertEqual(sent.count, 4, "each once")
        await relaunchedRepository.retire()
    }

    // MARK: - Letters kept by a build before this

    /// A letter in the Outbox with none of the four fields, as a build
    /// before B-083 kept it, goes as it did then: From the name saved when
    /// it goes, dated as it goes, under the Message-ID it was given.
    func testALetterFromABuildBeforeThisGoesAsItDid() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        await sentOffline(letter("B-083 older"), as: "older", kept: kept, repository: repository)
        try editStored("older") { json in
            for key in ["sentName", "sentAt", "sentSignature", "sentSignatureHTML"] {
                XCTAssertNotNil(json.removeValue(forKey: key), key)
            }
        }
        let older = try XCTUnwrap(kept.store.letter("older"))
        XCTAssertEqual(older.atSend, AtSend())
        XCTAssertEqual(kept.outboxRows.count, 1)

        rename(Self.newName)
        let before = Date()
        try await pass(kept, repository)
        let raw = try await lastLetter()
        XCTAssertEqual(from(raw), "\(Self.newName) <\(server.username)>")
        let sentDate = try XCTUnwrap(date(raw))
        XCTAssertGreaterThanOrEqual(sentDate, before.addingTimeInterval(-1), "dated as it goes")
        XCTAssertLessThanOrEqual(sentDate, Date().addingTimeInterval(1))
        XCTAssertEqual(header("Message-ID", raw), older.outbox)
        XCTAssertEqual(kept.outbox.count, 0)
    }

    /// A field that cannot be read is as one not there: the letter is
    /// still listed, not held, and goes once, with what can be read. A Date
    /// that cannot be read leaves the name; a name, or a formatted twin,
    /// that cannot be read leaves the Date.
    func testAFieldThatCannotBeReadDoesNotStopTheLetter() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        await sentOffline(letter("B-083 bad date"), as: "a", kept: kept, repository: repository)
        await sentOffline(letter("B-083 bad name"), as: "b", kept: kept, repository: repository)
        let (_, sentAtB) = try waiting("b", in: kept)
        try editStored("a") { $0["sentAt"] = "yesterday" }
        try editStored("b") { json in
            json["sentName"] = 42
            json["sentSignatureHTML"] = ["<b>"]
        }
        let a = try XCTUnwrap(kept.store.letter("a"))
        XCTAssertEqual(a.atSend.name, "Carlo")
        XCTAssertNil(a.atSend.date)
        let b = try XCTUnwrap(kept.store.letter("b"))
        XCTAssertNil(b.atSend.name)
        XCTAssertNil(b.atSend.signature, "a signature with no twin is none")
        XCTAssertEqual(b.atSend.date, sentAtB)
        XCTAssertEqual(kept.outboxRows.count, 2)
        XCTAssertFalse(kept.outbox.contains { kept.isHeld($0) })

        rename(Self.newName)
        let before = Date()
        try await pass(kept, repository)
        let sent = await letters()
        XCTAssertEqual(sent.count, 2, "each once")
        let rawA = try XCTUnwrap(sent.first { header("Subject", $0) == "B-083 bad date" })
        XCTAssertEqual(from(rawA), "Carlo <\(server.username)>")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(date(rawA)), before.addingTimeInterval(-1))
        let rawB = try XCTUnwrap(sent.first { header("Subject", $0) == "B-083 bad name" })
        XCTAssertEqual(from(rawB), "\(Self.newName) <\(server.username)>")
        XCTAssertEqual(header("Date", rawB), dated(sentAtB))
        XCTAssertEqual(kept.outbox.count, 0)
    }

    // MARK: - On the iPad

    /// What a letter went into the Outbox with is in its `letter.json`,
    /// written with it, and read back the same by the next launch; the
    /// writes of each attempt keep it. Taken back into the composer, or
    /// kept by the composer, the letter is out of the Outbox, and it goes
    /// with it. An empty name stays empty: the address alone.
    func testWhatItWentInWithIsKeptWithTheLetter() throws {
        let store = LocalDraftStore(root: root)
        var draft = letter("B-083 kept")
        draft.body = "Lunch at one?"
        try store.keep(draft, as: "k", unfinished: true, account: server.username)
        XCTAssertEqual(store.letter("k")?.atSend, AtSend(), "a draft has none")
        let atSend = AtSend(name: "", date: Date(timeIntervalSince1970: 1_790_000_123),
                            signature: AtSend.Signature(text: "Carlo", html: ""))
        let messageID = try store.enterOutbox("k", as: atSend)
        XCTAssertEqual(store.letter("k")?.atSend, atSend)

        let url = root.appendingPathComponent("k").appendingPathComponent("letter.json")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(json["sentName"] as? String, "")
        XCTAssertNotNil(json["sentAt"] as? Double)
        XCTAssertEqual(json["sentSignature"] as? String, "Carlo")
        XCTAssertEqual(json["sentSignatureHTML"] as? String, "")
        XCTAssertEqual(json["outbox"] as? String, messageID)

        try store.noteSending("k", messageID)
        store.noteCutOff("k")
        store.settled("k", [messageID])
        XCTAssertTrue(store.noteTries("k", 1))
        XCTAssertEqual(store.letter("k")?.atSend, atSend, "the attempt's writes keep it")
        XCTAssertEqual(LocalDraftStore(root: root).letter("k")?.atSend, atSend, "the next launch")
        XCTAssertEqual(LocalDraftStore(root: root).letters().first?.atSend, atSend)

        store.takeBack("k")
        XCTAssertNil(store.letter("k")?.outbox)
        XCTAssertEqual(store.letter("k")?.atSend, AtSend(), "taken back")

        _ = try store.enterOutbox("k", as: atSend)
        try store.keep(draft, as: "k", unfinished: true, account: server.username)
        XCTAssertNil(store.letter("k")?.outbox)
        XCTAssertEqual(store.letter("k")?.atSend, AtSend(), "kept by the composer")
    }

    // MARK: - Opened from the Outbox

    /// Opened from the Outbox, changed and sent again: it keeps the name it
    /// went into the Outbox with and is dated at the new Send, under a new
    /// Message-ID, as no attempt at it may have reached Gmail.
    func testOpenedAndSentAgainItKeepsItsNameAndTakesANewDate() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        await sentOffline(letter("B-083 reopen"), as: "reopen", kept: kept, repository: repository)
        let (first, sentAt) = try waiting("reopen", in: kept)
        rename(Self.newName)
        dismissals = 0

        let (actions, typed) = try await openedAndChanged("reopen", kept: kept,
                                                          repository: repository)
        await actions.send({ typed }, then: nil)?.value
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(errors, [])
        let sent = await letters()
        XCTAssertEqual(sent.count, 1)
        let raw = try XCTUnwrap(sent.first)
        XCTAssertEqual(from(raw), "Carlo <\(server.username)>", "the name it was sent with")
        let resent = try XCTUnwrap(date(raw))
        XCTAssertGreaterThan(resent, sentAt, "a new Date")
        XCTAssertLessThanOrEqual(resent, keptClock.now(), "the time of the new Send")
        XCTAssertNotEqual(header("Message-ID", raw), first.outbox)
        XCTAssertTrue(raw.range(of: Data("Or at two.".utf8)) != nil, "as changed")
        XCTAssertNil(kept.store.letter("reopen"))
    }

    /// Opened from the Outbox after an attempt cut off after its DATA, and
    /// sent again: Sent Mail is asked first, and it goes under that
    /// attempt's Message-ID, as before (B-052, B-070), with the name it was
    /// sent with and the Date of the new Send.
    func testSentAgainAfterACutItKeepsTheMessageIDOfTheCut() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        submissions.then { ScriptedSubmission(hangsUpBeforeLetterReply: true) }
        await send(letter("B-083 cut, then reopened"), as: "cut", kept: kept,
                   repository: repository)
        let (first, sentAt) = try waiting("cut", in: kept)
        rename(Self.newName)
        keptClock.advance(by: Outbox.settling)
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)

        let (actions, typed) = try await openedAndChanged("cut", kept: kept, repository: repository)
        await actions.send({ typed }, then: nil)?.value
        XCTAssertEqual(errors, [])
        let looks = server.log.filter { $0.command.contains("HEADER Message-ID") }
        XCTAssertEqual(looks.count, 1, "Sent Mail asked first")
        let sent = await letters()
        XCTAssertEqual(sent.count, 2)
        let raw = try XCTUnwrap(sent.last)
        XCTAssertEqual(from(raw), "Carlo <\(server.username)>")
        XCTAssertEqual(header("Message-ID", raw), first.outbox)
        XCTAssertGreaterThan(try XCTUnwrap(date(raw)), sentAt)
    }

    /// Opened from the Outbox and closed as it opened: back in the Outbox
    /// as it was, with the name and the time of its Send. He has not sent
    /// it again.
    func testPutBackItKeepsWhatItWentInWith() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        await sentOffline(letter("B-083 put back"), as: "back", kept: kept, repository: repository)
        let (first, sentAt) = try waiting("back", in: kept)
        rename(Self.newName)

        let opened = try XCTUnwrap(kept.letter("back")).draft
        let (actions, _) = try await openedAndChanged("back", kept: kept, repository: repository)
        actions.closeWithoutAsking { opened }
        let back = try XCTUnwrap(kept.store.letter("back"))
        XCTAssertNotNil(back.outbox)
        XCTAssertEqual(back.atSend, first.atSend)

        try await pass(kept, repository)
        let raw = try await lastLetter()
        XCTAssertEqual(from(raw), "Carlo <\(server.username)>")
        XCTAssertEqual(header("Date", raw), dated(sentAt))
        XCTAssertEqual(kept.outbox.count, 0)
    }

    /// Opened from the Outbox and kept as a draft is a draft: it keeps
    /// nothing of its Send, and goes as a draft goes, From the name saved
    /// when it is sent (B-082).
    func testKeptAsADraftItGoesAsADraft() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        await sentOffline(letter("B-083 to Drafts"), as: "draft", kept: kept,
                          repository: repository)
        rename(Self.newName)

        let (actions, typed) = try await openedAndChanged("draft", kept: kept,
                                                          repository: repository)
        line.isUp = false
        await actions.saveAndClose({ typed }, then: nil)?.value
        line.isUp = true
        XCTAssertEqual(kept.waiting.map(\.key), ["draft"])
        XCTAssertEqual(kept.store.letter("draft")?.atSend, AtSend())

        let reopened = try XCTUnwrap(kept.letter("draft")).draft
        await send(reopened, as: "draft", kept: kept, repository: repository)
        let raw = try await lastLetter()
        XCTAssertEqual(from(raw), "\(Self.newName) <\(server.username)>")
    }

    /// A letter set aside by a safe start and brought back is held (B-057)
    /// and goes only by his Send, from the composer: with the name it was
    /// sent with, dated at that Send.
    func testALetterBroughtBackKeepsItsNameAndTakesTheTimeOfHisSend() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        await sentOffline(letter("B-083 set aside"), as: "aside", kept: kept,
                          repository: repository)
        let (first, sentAt) = try waiting("aside", in: kept)
        XCTAssertNotNil(LocalDraftStore.setAside(root, at: Date(),
                                                 in: TimeZone(identifier: "UTC")!))
        XCTAssertEqual(LocalDraftStore.bringBack(into: root), 1)
        let back = makeKept()
        let brought = try XCTUnwrap(back.store.letter("aside"))
        XCTAssertTrue(back.isHeld(brought))
        XCTAssertEqual(brought.atSend, first.atSend, "brought back with it")

        rename(Self.newName)
        try await pass(back, repository)
        var sent = await letters()
        XCTAssertEqual(sent.count, 0, "held")
        let draft = try XCTUnwrap(back.letter("aside")).draft
        await send(draft, as: "aside", kept: back, repository: repository)
        sent = await letters()
        XCTAssertEqual(sent.count, 1)
        let raw = try XCTUnwrap(sent.first)
        XCTAssertEqual(from(raw), "Carlo <\(server.username)>")
        XCTAssertGreaterThan(try XCTUnwrap(date(raw)), sentAt)
    }

    /// A letter written in another account, opened from the Outbox and
    /// sent, goes from this account's address and so under this account's
    /// name, not the one it was kept with.
    func testALetterOfAnotherAccountTakesThisAccountsName() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        await sentOffline(letter("B-083 other"), as: "other", kept: kept, repository: repository)
        try editStored("other") { json in
            json["account"] = "someone@example.net"
            json["sentName"] = "Someone Else"
        }
        rename(Self.newName)
        try await pass(kept, repository)
        var sent = await letters()
        XCTAssertEqual(sent.count, 0, "not sent by a pass")

        let draft = try XCTUnwrap(kept.letter("other")).draft
        await send(draft, as: "other", kept: kept, repository: repository)
        sent = await letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(from(try XCTUnwrap(sent.first)), "\(Self.newName) <\(server.username)>")
    }

    // MARK: - The name and the signature

    /// No name at Send, the address alone, stays so: a name saved after it
    /// does not reach the letter.
    func testNoNameAtSendGoesWithTheAddressAlone() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        rename("")
        await sentOffline(letter("B-083 bare"), as: "bare", kept: kept, repository: repository)
        XCTAssertEqual(kept.store.letter("bare")?.atSend.name, "")
        rename("Sam Example")
        try await pass(kept, repository)
        let raw = try await lastLetter()
        XCTAssertEqual(from(raw), server.username)
    }

    /// A kept name with a line break in it, from a damaged file, cannot
    /// start a header of its own: From is one line, and nobody is added to
    /// the letter.
    func testAKeptNameCannotStartAHeader() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        await sentOffline(letter("B-083 one line"), as: "line", kept: kept, repository: repository)
        try editStored("line") { $0["sentName"] = "Carlo\r\nBcc: sam@example.com" }
        try await pass(kept, repository)
        let raw = try await lastLetter()
        let text = String(decoding: raw, as: UTF8.self)
        let head = text.components(separatedBy: "\r\n\r\n").first ?? ""
        let lines = head.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.filter { $0.hasPrefix("From:") },
                       ["From: \"Carlo  Bcc: sam@example.com\" <\(server.username)>"])
        XCTAssertFalse(lines.contains { $0.lowercased().hasPrefix("bcc:") })
        let commands = try await XCTUnwrap(submissions.all.last).commands
        XCTAssertFalse(commands.contains { $0.lowercased().contains("sam@example.com") })
    }

    /// The signature goes as it was at Send: its formatted twin, though
    /// "Send my signature as plain text instead" and new words were saved
    /// while the letter waited. The next letter goes with what was saved.
    func testTheSignatureGoesAsItWasAtSend() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        await sentOffline(letter("B-083 signed"), as: "signed", kept: kept, repository: repository)
        save {
            $0.signature = "Carlo W. Example"
            $0.signatureHTML = ""
        }
        try await pass(kept, repository)
        let waited = MIMEDecoder.decodeMessage(try await lastLetter())
        XCTAssertTrue(waited.text?.contains("1 Example Street") == true)
        let html = try XCTUnwrap(waited.html, "the twin of its Send")
        XCTAssertTrue(html.contains("<b>Carlo</b>"), html)

        try await repository.send(letter("B-083 signed after"))
        let next = MIMEDecoder.decodeMessage(try await lastLetter())
        XCTAssertTrue(next.text?.contains("Carlo W. Example") == true)
        XCTAssertNil(next.html, "plain text, as saved")
    }

    // MARK: - The share sheet

    /// The share sheet has no Outbox: a Send that cannot reach the server
    /// keeps the sheet with the reason, and nothing waits anywhere. The
    /// Send that goes makes the letter then, From the name of the account
    /// the sheet was handed, dated as it goes.
    func testAShareIsMadeAtItsSendAndWaitsNowhere() async throws {
        let offline = ScriptedSubmission(failsToOpen: true)
        let online = ScriptedSubmission()
        let servers = SubmissionServers()
        servers.then { offline }
        servers.then { online }
        var finished = 0
        var shareErrors: [MailError] = []
        let sheet = ShareSheet(
            shared: ShareMirror.Shared(account: launched, password: "app-password",
                                       signatureImages: [], recipients: []),
            transport: { _, _ in servers.next() },
            noteSent: { _ in }, finish: { finished += 1 }, cancel: {},
            showError: { shareErrors.append($0) },
            draw: { _ in },
            background: BackgroundTime(begin: { _, _ in nil }, end: { _ in }))
        var draft = sheet.letter(from: [.link(URL(string: "https://example.com/garden")!,
                                              title: "B-083 shared")])
        draft.to = ["jane@example.com"]
        await sheet.send { draft }?.value
        XCTAssertEqual(shareErrors.count, 1)
        XCTAssertEqual(finished, 0, "the sheet stays")
        let none = await offline.letters
        XCTAssertEqual(none.count, 0)

        let before = Date()
        await sheet.send { draft }?.value
        XCTAssertEqual(finished, 1)
        let sent = await online.letters
        XCTAssertEqual(sent.count, 1)
        let raw = try XCTUnwrap(sent.first)
        XCTAssertEqual(from(raw), "Carlo <\(launched.address)>")
        let sentDate = try XCTUnwrap(date(raw))
        XCTAssertGreaterThanOrEqual(sentDate, before.addingTimeInterval(-1))
        XCTAssertLessThanOrEqual(sentDate, Date().addingTimeInterval(1))
    }
}

/// What `CredentialStore` keeps, as Settings saves it.
private final class AccountSaved: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: MailAccount?

    init(_ account: MailAccount?) { stored = account }

    var account: MailAccount? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// Whether the line is up: down, every connection is refused.
private final class LineState: @unchecked Sendable {
    private let lock = NSLock()
    private var up = true

    var isUp: Bool {
        get { lock.lock(); defer { lock.unlock() }; return up }
        set { lock.lock(); up = newValue; lock.unlock() }
    }
}

/// A submission server per connection, as the SMTP client makes one per
/// letter: the ones a test lines up first, then ones that take every letter.
private final class SubmissionServers: @unchecked Sendable {
    private let lock = NSLock()
    private var servers: [ScriptedSubmission] = []
    private var script: [() -> ScriptedSubmission] = []

    /// The next connection is made by `make`.
    func then(_ make: @escaping () -> ScriptedSubmission) {
        lock.lock()
        script.append(make)
        lock.unlock()
    }

    func next() -> ScriptedSubmission {
        lock.lock()
        defer { lock.unlock() }
        let server = script.isEmpty ? ScriptedSubmission() : script.removeFirst()()
        servers.append(server)
        return server
    }

    var all: [ScriptedSubmission] {
        lock.lock()
        defer { lock.unlock() }
        return servers
    }
}
