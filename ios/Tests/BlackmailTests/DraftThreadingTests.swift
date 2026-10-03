import XCTest
@testable import Blackmail

/// A reply put down in Drafts and finished later still answers its letter
/// (B-064). Seen on the iPad: a Reply All saved to Drafts had the letter
/// answered as its In-Reply-To, and the letter sent from it had none, so
/// Gmail began a conversation of its own with it. `Draft.reopening` left
/// the draft's In-Reply-To and References behind, and the letter the pane
/// reads did not carry an In-Reply-To at all.
///
/// These run the composer's own wiring (`ComposeActions(letter:…)`), the
/// shipping `LocalDrafts` over a store in a directory of the test's own, the
/// shipping repository over the scripted IMAP server, and a scripted
/// submission server on port 465 per connection. The line can be taken
/// down: then every connection is refused, as a connect with no route is.
/// What is checked is what went after DATA: one In-Reply-To naming the
/// letter answered, and one References, the letter's ancestry with the
/// letter answered last, each id once.
@MainActor
final class DraftThreadingTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "DraftThreadingTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var line: ThreadingLine!
    private var submissions: ThreadingSubmissions!
    private var clock: ManualClock!
    private var keptClock: ManualClock!
    private var root: URL!
    private var background = FakeBackground()
    private var passTime = FakeBackground()
    private var pauses = Held()
    private var errors: [MailError] = []
    private var queued = 0

    /// The letter answered, his own, in Sent Mail, itself a reply: as on
    /// the iPad, where it was a Reply All to a letter in Sent Mail.
    private static let parentID = "<parent@example.org>"
    private static let ancestry = "<root@example.org> <middle@example.org>"
    /// What the reply's References must be: the letter's own, then it.
    private static let replyReferences = "<root@example.org> <middle@example.org> <parent@example.org>"

    override func setUp() async throws {
        try await super.setUp()
        server = ScriptedIMAPServer()
        line = ThreadingLine()
        submissions = ThreadingSubmissions()
        clock = ManualClock()
        keptClock = ManualClock()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("DraftThreadingTests-\(UUID().uuidString)", isDirectory: true)
        background = FakeBackground()
        passTime = FakeBackground()
        pauses = Held()
        errors = []
        queued = 0
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

    /// The app's `LocalDrafts` over this test's directory. A second one over
    /// the same directory is the app launched again.
    private func makeKept() -> LocalDrafts {
        let clock = keptClock!
        let store = LocalDraftStore(root: root, now: {
            clock.advance(by: 1)
            return clock.now()
        })
        return LocalDrafts(store: store, account: server.username, background: passTime.time)
    }

    /// The composer's actions for letter `key`, wired as the composer
    /// wires them.
    private func makeActions(_ key: String, kept: LocalDrafts,
                             repository: MailRepository) -> ComposeActions {
        kept.opened(key)
        return ComposeActions(letter: key, repository: repository, kept: kept,
                              dismiss: {},
                              showError: { [unowned self] in errors.append($0) },
                              draw: { _ in },
                              background: background.time,
                              queued: { [unowned self] in queued += 1 },
                              wait: { [pauses] _ in try await pauses.wait() })
    }

    /// Cancel, Save Draft, in the composer on `draft`, kept as `key`.
    private func saveDraft(_ draft: Draft, as key: String, kept: LocalDrafts,
                           repository: IMAPMailRepository) async {
        await makeActions(key, kept: kept, repository: repository)
            .saveAndClose({ draft }, then: nil)?.value
    }

    /// Send, in the composer on `draft`, kept as `key`.
    private func send(_ draft: Draft, as key: String, kept: LocalDrafts,
                      repository: IMAPMailRepository) async {
        await makeActions(key, kept: kept, repository: repository).send({ draft }, then: nil)?.value
    }

    /// The network gone: every connection open now dies, and no new one
    /// can be made.
    private func takeLineDown() async {
        line.isUp = false
        await server.resetConnections()
    }

    /// A page, and the pass over the kept letters that follows it.
    private func afterAPage(_ kept: LocalDrafts, _ repository: IMAPMailRepository) async throws {
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        await kept.uploadWaiting(to: repository)?.value
    }

    /// His letter to Jane, copied to Sam, in Sent Mail and All Mail, opened
    /// as the pane opens it.
    private func parent(_ repository: IMAPMailRepository) async throws -> Message {
        let uids = server.deliver(Server.Letter(
            from: Server.owner, to: [Server.Address(name: "Jane Example", address: "jane@example.com")],
            cc: [Server.sam], subject: "Thursday", date: Server.newestDate, text: "Shall we?\r\n",
            flags: ["\\Seen"], messageID: Self.parentID, inReplyTo: "<middle@example.org>",
            references: Self.ancestry), to: [Server.sent, Server.allMail])
        let uid = try XCTUnwrap(uids[Server.sent])
        return try await repository.loadMessage(id: "\(server.uidValidity(of: Server.sent))/\(uid)",
                                                mailboxID: Server.sent)
    }

    /// Reply All to `m`, a word typed above the quote.
    private func reply(to m: Message) -> Draft {
        var draft = Draft.replying(to: m, all: true, mine: OwnAddresses(account: server.account))
        draft.body = "A word." + draft.body
        return draft
    }

    /// The newest copy in Drafts of the letter called `subject`, as its row
    /// names it: its id and Gmail's id for it.
    private func copy(_ subject: String) throws -> (id: String, letter: UInt64?) {
        let uid = try XCTUnwrap(server.uids(in: Server.drafts).last {
            server.letter(uid: $0, in: Server.drafts)?.subject == subject
        }, "no copy of \(subject) in Drafts")
        return ("\(server.uidValidity(of: Server.drafts))/\(uid)",
                server.gmailMessageID(uid: uid, in: Server.drafts))
    }

    /// The copy in Drafts of the letter called `subject`, reopened as a tap
    /// on its row reopens it.
    private func reopen(_ subject: String, _ repository: IMAPMailRepository) async throws -> Draft {
        let row = try copy(subject)
        return try await repository.loadDraft(id: row.id, gmailMessageID: row.letter,
                                              mailboxID: Server.drafts)
    }

    /// The values of every In-Reply-To and every References in the header
    /// of `letter` as it went, each unfolded, its white space single spaces.
    static func threading(of letter: Data) -> (inReplyTo: [String], references: [String]) {
        let headers = MIMEDecoder.parseHeaders(letter)
        func values(_ name: String) -> [String] {
            headers.filter { $0.name.trimmingCharacters(in: .whitespaces)
                .caseInsensitiveCompare(name) == .orderedSame }
                .map { $0.value.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        }
        return (values("In-Reply-To"), values("References"))
    }

    /// The one letter sent since `before`, and its threading headers.
    private func sent(after before: Int = 0, file: StaticString = #filePath, line: UInt = #line)
        async throws -> (letter: Data, inReplyTo: [String], references: [String]) {
        let letters = await submissions.letters()
        XCTAssertEqual(letters.count, before + 1, "one letter sent", file: file, line: line)
        let letter = try XCTUnwrap(letters.last, file: file, line: line)
        let threading = Self.threading(of: letter)
        return (letter, threading.inReplyTo, threading.references)
    }

    /// Asserts the letter sent answers the letter of `parent(_:)`: one
    /// In-Reply-To naming it, and one References, its ancestry and it,
    /// each id once.
    private func assertAnswersTheParent(after before: Int = 0, file: StaticString = #filePath,
                                        line: UInt = #line) async throws {
        let went = try await sent(after: before, file: file, line: line)
        XCTAssertEqual(went.inReplyTo, [Self.parentID], file: file, line: line)
        XCTAssertEqual(went.references, [Self.replyReferences], file: file, line: line)
        let ids = went.references.first?.split(separator: " ").map(String.init) ?? []
        XCTAssertEqual(ids.filter { $0 == Self.parentID }.count, 1,
                       "the letter answered once in References", file: file, line: line)
    }

    // MARK: - From Drafts

    /// As on the iPad: Reply All to his letter in Sent Mail, a word, Cancel,
    /// Save Draft, opened from Drafts, Send. The copy saved names the letter
    /// answered, the draft comes back answering it, and the letter sent
    /// answers it, the letter answered once in References, not twice.
    func testAReplyFinishedFromDraftsAnswersItsLetter() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let m = try await parent(repository)
        XCTAssertEqual(m.messageID, Self.parentID)
        XCTAssertEqual(m.inReplyTo, "<middle@example.org>")
        XCTAssertEqual(m.references, Self.ancestry)

        await saveDraft(reply(to: m), as: "reply", kept: kept, repository: repository)
        let saved = try XCTUnwrap(server.letter(uid: try XCTUnwrap(
            server.uids(in: Server.drafts).last), in: Server.drafts))
        XCTAssertEqual(saved.subject, "Re: Thursday")
        XCTAssertEqual(saved.inReplyTo, Self.parentID, "the copy saved answers the letter")
        XCTAssertEqual(saved.references, Self.replyReferences)

        let back = try await reopen("Re: Thursday", repository)
        XCTAssertEqual(back.inReplyTo, Self.parentID)
        XCTAssertEqual(back.references, Self.replyReferences)

        await send(back, as: "reopened", kept: kept, repository: repository)
        XCTAssertEqual(errors, [])
        try await assertAnswersTheParent()
    }

    /// A letter begun afresh, saved and finished from Drafts, answers
    /// nothing: no In-Reply-To and no References.
    func testALetterBegunAfreshAndFinishedFromDraftsAnswersNothing() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let draft = Draft(to: ["jane@example.com"], subject: "Sunday", body: "Lunch at one?")
        await saveDraft(draft, as: "fresh", kept: kept, repository: repository)

        let back = try await reopen("Sunday", repository)
        XCTAssertNil(back.inReplyTo)
        XCTAssertNil(back.references)
        await send(back, as: "reopened", kept: kept, repository: repository)
        let went = try await sent()
        XCTAssertEqual(went.inReplyTo, [])
        XCTAssertEqual(went.references, [])
    }

    /// A forward, saved and finished from Drafts, answers nothing, as a
    /// forward sent at once does not.
    func testAForwardFinishedFromDraftsAnswersNothing() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let m = try await parent(repository)
        var draft = Draft.forwarding(m)
        draft.to = ["carlo@example.org"]
        await saveDraft(draft, as: "forward", kept: kept, repository: repository)

        let back = try await reopen("Fwd: Thursday", repository)
        XCTAssertNil(back.inReplyTo)
        XCTAssertNil(back.references)
        await send(back, as: "reopened", kept: kept, repository: repository)
        let went = try await sent()
        XCTAssertEqual(went.inReplyTo, [])
        XCTAssertEqual(went.references, [])
    }

    /// A draft begun in another client, Gmail's web page say, with an
    /// In-Reply-To and no References, sends that In-Reply-To, and the
    /// letter it names as References.
    func testAnotherClientsDraftWithOnlyAnInReplyToAnswersItsLetter() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        server.deliver(Server.Letter(
            from: Server.owner, to: [Server.Address(name: "Jane Example", address: "jane@example.com")],
            subject: "Re: Thursday", date: Server.newestDate, text: "Begun elsewhere.\r\n",
            flags: ["\\Draft", "\\Seen"], messageID: "<elsewhere@example.com>",
            inReplyTo: Self.parentID), to: [Server.drafts, Server.allMail])

        let back = try await reopen("Re: Thursday", repository)
        XCTAssertEqual(back.inReplyTo, Self.parentID)
        XCTAssertNil(back.references)
        await send(back, as: "reopened", kept: kept, repository: repository)
        let went = try await sent()
        XCTAssertEqual(went.inReplyTo, [Self.parentID])
        XCTAssertEqual(went.references, [Self.parentID])
    }

    /// A draft of a reply found by a search of All Mailboxes, from Drafts,
    /// is reopened from All Mail, where the hit is, and answers its letter
    /// as one reopened from Drafts does.
    func testAReplyReopenedFromASearchInAllMailAnswersItsLetter() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let m = try await parent(repository)
        await saveDraft(reply(to: m), as: "reply", kept: kept, repository: repository)

        let hits = try await repository.search(in: Server.drafts, query: "Thursday",
                                               scope: .allMailboxes, beforeUID: nil, limit: 50)
        let hit = try XCTUnwrap(hits.first { $0.subject == "Re: Thursday" })
        XCTAssertEqual(hit.mailboxID, Server.allMail)
        let back = try await repository.loadDraft(id: hit.id, gmailMessageID: hit.gmailMessageID,
                                                  mailboxID: hit.mailboxID)
        XCTAssertEqual(back.inReplyTo, Self.parentID)
        XCTAssertEqual(back.references, Self.replyReferences)
        await send(back, as: "reopened", kept: kept, repository: repository)
        try await assertAnswersTheParent()
    }

    // MARK: - From the iPad and the Outbox

    /// Save Draft with no connection keeps the reply on the iPad. Opened
    /// there after a relaunch and sent, it answers its letter: the kept copy
    /// carries the draft's In-Reply-To and References as they were.
    func testAReplyKeptOnTheIPadAndFinishedThereAnswersItsLetter() async throws {
        let repository = makeRepository()
        let m = try await parent(repository)
        await takeLineDown()
        await saveDraft(reply(to: m), as: "reply", kept: makeKept(), repository: repository)
        line.isUp = true
        XCTAssertFalse(server.uids(in: Server.drafts).contains {
            server.letter(uid: $0, in: Server.drafts)?.subject == "Re: Thursday"
        }, "nothing reached Drafts")

        let relaunched = makeKept()
        let back = try XCTUnwrap(relaunched.letter("reply")?.draft)
        XCTAssertEqual(back.inReplyTo, Self.parentID)
        XCTAssertEqual(back.references, Self.ancestry, "as Reply made it: the builder adds the letter")
        await send(back, as: "reply", kept: relaunched, repository: makeRepository())
        XCTAssertEqual(errors, [])
        try await assertAnswersTheParent()
    }

    /// Kept on the iPad with no connection, taken to Drafts by the pass when
    /// the connection is back, then opened from Drafts and sent: it answers
    /// its letter.
    func testAReplyTakenToDraftsFromTheIPadAndFinishedThereAnswersItsLetter() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let m = try await parent(repository)
        await takeLineDown()
        await saveDraft(reply(to: m), as: "reply", kept: kept, repository: repository)
        line.isUp = true
        try await afterAPage(kept, repository)
        XCTAssertNil(kept.letter("reply"), "gone to Drafts, and off the iPad")
        let saved = try XCTUnwrap(server.letter(uid: try XCTUnwrap(
            server.uids(in: Server.drafts).last), in: Server.drafts))
        XCTAssertEqual(saved.inReplyTo, Self.parentID)
        XCTAssertEqual(saved.references, Self.replyReferences)

        let back = try await reopen("Re: Thursday", repository)
        await send(back, as: "reopened", kept: kept, repository: repository)
        try await assertAnswersTheParent()
    }

    /// Reopened from Drafts and sent with no connection, it waits in the
    /// Outbox, and the pass that sends it when the connection is back sends
    /// it answering its letter.
    func testAReplyFromDraftsThatWaitedInTheOutboxAnswersItsLetter() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let m = try await parent(repository)
        await saveDraft(reply(to: m), as: "reply", kept: kept, repository: repository)
        let back = try await reopen("Re: Thursday", repository)

        await takeLineDown()
        await send(back, as: "reopened", kept: kept, repository: repository)
        line.isUp = true
        XCTAssertEqual(queued, 1, "in the Outbox")
        XCTAssertEqual(kept.outbox.first?.draft.inReplyTo, Self.parentID)
        XCTAssertEqual(kept.outbox.first?.draft.references, Self.replyReferences)
        let none = await submissions.letters()
        XCTAssertEqual(none.count, 0)

        try await afterAPage(kept, repository)
        try await assertAnswersTheParent()
        XCTAssertEqual(kept.outbox.count, 0)
    }

    // MARK: - What a draft's In-Reply-To can hold

    /// The draft's In-Reply-To is read as its header has it, not decoded:
    /// an id has to match byte for byte to thread. A letter without one
    /// has none.
    func testALettersInReplyToIsReadAsItsHeaderHasIt() async throws {
        let repository = makeRepository()
        let raw = "<=?UTF-8?Q?parent?=@example.org>"
        let uids = server.deliver(Server.Letter(
            from: Server.sam, to: [Server.owner], subject: "Encoded", date: Server.newestDate,
            text: "Hello.\r\n", messageID: "<encoded@example.com>", inReplyTo: raw),
            to: [Server.inbox])
        let with = try await repository.loadMessage(
            id: "\(server.uidValidity(of: Server.inbox))/\(try XCTUnwrap(uids[Server.inbox]))",
            mailboxID: Server.inbox)
        XCTAssertEqual(with.inReplyTo, raw)
        let other = server.deliver(Server.Letter(
            from: Server.sam, to: [Server.owner], subject: "Plain", date: Server.newestDate,
            text: "Hello.\r\n", messageID: "<plain@example.com>"), to: [Server.inbox])
        let without = try await repository.loadMessage(
            id: "\(server.uidValidity(of: Server.inbox))/\(try XCTUnwrap(other[Server.inbox]))",
            mailboxID: Server.inbox)
        XCTAssertNil(without.inReplyTo)
    }

    /// A draft saved elsewhere whose In-Reply-To has a comment beside the
    /// id, a phrase in quotes, several ids, an id folded over lines or
    /// without its brackets, words and no id, or a line break followed by
    /// what reads as a header of its own: reopened and sent, the letter has
    /// at most one In-Reply-To, of the ids alone, a References of each id
    /// once, every header on lines of its own, no header that was not
    /// written, and goes to Jane alone.
    func testADraftsInReplyToInAnyShapeGoesAsItsIdsAlone() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let parent = Self.parentID
        let cases: [(inReplyTo: String, references: String?, sent: String?, ancestry: String?)] = [
            ("<parent@example.org> (Jane Example's letter of 1 October)", nil, parent, parent),
            ("\"Jane's letter\" <parent@example.org>", nil, parent, parent),
            ("<parent@example.org> <other@example.org>", "<root@example.org> <parent@example.org>",
             "<parent@example.org> <other@example.org>",
             "<root@example.org> <parent@example.org> <other@example.org>"),
            ("<parent@example.org> <parent@example.org>", nil, parent, parent),
            ("\r\n <parent@example.org>", nil, parent, parent),
            ("<parent@\r\n example.org>", nil, parent, parent),
            ("parent@example.org", nil, parent, parent),
            ("Your letter of Monday", nil, nil, nil),
            ("<parent@example.org>\rBcc: stranger@example.net", nil, parent, parent),
            ("<parent@example.org>\u{2028}Bcc: stranger@example.net", nil, parent, parent),
            ("<parent@example.org>\u{0085}To: stranger@example.net", nil, parent, parent),
            ("<parent@exam\rple.org>", Self.ancestry, parent, Self.replyReferences),
            ("<parent@example.org>", "<root@example.org>\rBcc: stranger@example.net", parent,
             "<root@example.org> <parent@example.org>"),
        ]
        for (n, shape) in cases.enumerated() {
            let what = "\(n): \(shape.inReplyTo.debugDescription)"
            let subject = "Re: Shape \(n)"
            var letter = Server.Letter(
                from: Server.owner, to: [Server.Address(name: nil, address: "jane@example.com")],
                subject: subject, date: Server.newestDate, text: "Begun elsewhere.\r\n",
                flags: ["\\Draft", "\\Seen"], messageID: "<shape-\(n)@example.com>",
                inReplyTo: shape.inReplyTo)
            letter.references = shape.references
            server.deliver(letter, to: [Server.drafts, Server.allMail])

            let back = try await reopen(subject, repository)
            await send(back, as: "shape-\(n)", kept: kept, repository: repository)
            XCTAssertEqual(errors, [], what)
            let went = try await sent(after: n)
            XCTAssertEqual(went.inReplyTo, shape.sent.map { [$0] } ?? [], what)
            XCTAssertEqual(went.references, shape.ancestry.map { [$0] } ?? [], what)

            // Every line of the header a header of its own or the fold of
            // one, none with a line break of any kind in it, and no header
            // that was not written.
            let text = String(decoding: went.letter, as: UTF8.self)
            let head = text.components(separatedBy: "\r\n\r\n").first ?? ""
            let lines = head.components(separatedBy: "\r\n")
            for line in lines {
                XCTAssertFalse(line.unicodeScalars.contains {
                    [0x0A, 0x0D, 0x85, 0x2028, 0x2029].contains($0.value)
                }, "\(what): \(line.debugDescription)")
            }
            let names = lines.compactMap { line -> String? in
                guard let first = line.first, first != " ", first != "\t" else { return nil }
                return line.split(separator: ":", maxSplits: 1).first.map(String.init)
            }
            XCTAssertEqual(names.filter { $0 == "To" }.count, 1, what)
            XCTAssertFalse(names.contains("Bcc"), what)
            let rcpt = await submissions.last()?.commands.filter { $0.hasPrefix("RCPT TO:") }
            XCTAssertEqual(rcpt, ["RCPT TO:<jane@example.com>"], what)
        }
    }

    // MARK: - The builder

    /// The builder adds the letter answered to References only when it is
    /// not there already: a reply reopened from Drafts brings References
    /// with it last, and it went twice.
    func testReferencesThatHaveTheLetterAnsweredDoNotGetItAgain() {
        var draft = Draft(to: ["jane@example.com"], subject: "Re: Thursday", body: "A word.")
        draft.inReplyTo = Self.parentID
        draft.references = Self.replyReferences
        let letter = RFC5322Builder.build(
            draft: draft, from: server.account,
            inReplyToHeaders: (messageID: Self.parentID, references: Self.replyReferences))
        let threading = Self.threading(of: letter)
        XCTAssertEqual(threading.inReplyTo, [Self.parentID])
        XCTAssertEqual(threading.references, [Self.replyReferences])
    }

    /// A draft from another client whose References names the letter
    /// answered before another id: it goes once, and last, where a reader
    /// looks for the letter a reply answers.
    func testTheLetterAnsweredGoesLastInReferencesWhereverTheDraftHadIt() {
        let other = "<other-1@example.com>"
        let first = "<first-1@example.com>"
        var draft = Draft(to: ["jane@example.com"], subject: "Re: Thursday", body: "A word.")
        draft.inReplyTo = Self.parentID
        draft.references = "\(first) \(Self.parentID) \(other)"
        let letter = RFC5322Builder.build(
            draft: draft, from: server.account,
            inReplyToHeaders: (messageID: Self.parentID, references: draft.references))
        let threading = Self.threading(of: letter)
        XCTAssertEqual(threading.inReplyTo, [Self.parentID])
        XCTAssertEqual(threading.references, ["\(first) \(other) \(Self.parentID)"])
    }
}

private final class ThreadingLine: @unchecked Sendable {
    private let lock = NSLock()
    private var up = true

    var isUp: Bool {
        get { lock.lock(); defer { lock.unlock() }; return up }
        set { lock.lock(); up = newValue; lock.unlock() }
    }
}

/// A submission server per connection, as the SMTP client makes one per
/// letter, and every letter any of them was given.
private final class ThreadingSubmissions: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [ScriptedSubmission] = []

    func next() -> ScriptedSubmission {
        let server = ScriptedSubmission()
        lock.lock()
        made.append(server)
        lock.unlock()
        return server
    }

    private func servers() -> [ScriptedSubmission] {
        lock.lock()
        defer { lock.unlock() }
        return made
    }

    /// The last connection that was given a letter.
    func last() async -> ScriptedSubmission? {
        for server in servers().reversed() where !(await server.letters.isEmpty) { return server }
        return nil
    }

    func letters() async -> [Data] {
        var all: [Data] = []
        for server in servers() { all += await server.letters }
        return all
    }
}
