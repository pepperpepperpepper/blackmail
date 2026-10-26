import XCTest
@testable import Blackmail

/// B-152: the letter a reply answers, or a forward passes on, is marked on
/// Gmail once the reply or the forward has gone, as Mail marks it:
/// `\Answered` for a reply, `$Forwarded` for a forward, after the server's
/// 250 and never before, also for a letter that goes later from the Outbox,
/// after a relaunch. Nothing for a letter that did not go, nor for an
/// original gone by then; a mark that cannot be written is dropped, and the
/// letter has still gone. Once the server has it, the kept page has it and
/// the list's rows of that letter show the arrow (B-102).
///
/// These run the composer's own wiring (`ComposeActions(letter:…)`), the
/// shipping `LocalDrafts` over a directory of the test's own, the shipping
/// repository over the scripted IMAP server, and a scripted submission
/// server per connection.
@MainActor
final class SentMarkTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "SentMarkTests"

    private var server: ScriptedIMAPServer!
    private var line: MarkLine!
    private var submissions: MarkSubmissions!
    private var book: RecipientBook!
    private var root: URL!
    private var background = FakeBackground()
    private var passTime = FakeBackground()
    private var dismissals = 0
    private var queued = 0
    private var errors: [MailError] = []

    override func setUp() async throws {
        try await super.setUp()
        server = ScriptedIMAPServer(inboxCount: 12)
        line = MarkLine()
        submissions = MarkSubmissions()
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: UserDefaults(suiteName: Self.suite)!)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SentMarkTests-\(UUID().uuidString)", isDirectory: true)
        background = FakeBackground()
        passTime = FakeBackground()
        dismissals = 0
        queued = 0
        errors = []
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
        server = nil
        line = nil
        submissions = nil
        book = nil
        root = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeRepository() -> IMAPMailRepository {
        let imap = server.transportFactory
        let line = self.line!
        let submissions = self.submissions!
        return IMAPMailRepository(
            account: server.account, password: server.password,
            transport: { host, port in
                if port == 465 {
                    return line.isUp ? submissions.next() : ScriptedSubmission(failsToOpen: true)
                }
                return line.isUp && line.imapUp ? imap(host, port) : imap(host, 1)
            },
            recipients: book,
            signatureImages: { [] },
            shelf: keptShelf(for: server.account))
    }

    /// The app's `LocalDrafts` over this test's directory. A second one
    /// over the same directory is the app launched again.
    private func makeKept() -> LocalDrafts {
        LocalDrafts(store: LocalDraftStore(root: root), account: server.username,
                    background: passTime.time)
    }

    /// Send tapped in the composer on `draft`, kept as `key`. The send's
    /// task, not awaited.
    private func tapSend(_ draft: Draft, as key: String, kept: LocalDrafts,
                         repository: MailRepository) -> Task<Void, Never>? {
        kept.opened(key)
        let actions = ComposeActions(letter: key, repository: repository, kept: kept,
                                     dismiss: { [unowned self] in dismissals += 1 },
                                     showError: { [unowned self] in errors.append($0) },
                                     draw: { _ in },
                                     background: background.time,
                                     queued: { [unowned self] in queued += 1 })
        return actions.send({ draft }, then: nil)
    }

    private func send(_ draft: Draft, as key: String, kept: LocalDrafts,
                      repository: MailRepository) async {
        await tapSend(draft, as: key, kept: kept, repository: repository)?.value
    }

    /// The Inbox's eighth newest row, read, and the letter it stands for.
    private func original(_ repository: IMAPMailRepository) async throws
        -> (MessageSummary, Message) {
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let row = rows[7]
        XCTAssertTrue(row.isRead)
        XCTAssertNotNil(row.gmailMessageID)
        let letter = try await repository.loadMessage(id: row.id, gmailMessageID: row.gmailMessageID,
                                                      mailboxID: row.mailboxID)
        return (row, letter)
    }

    private func uid(_ row: MessageSummary) -> UInt32 {
        UInt32(row.id.split(separator: "/").last ?? "") ?? 0
    }

    private func reply(to m: Message) -> Draft {
        var draft = Draft.replying(to: m, all: false, mine: OwnAddresses([server.username]))
        draft.body = "Thank you." + draft.body
        return draft
    }

    private func stores() -> [String] {
        server.log.map(\.command).filter { $0.contains("UID STORE") }
    }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<2_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    // MARK: - The draft names its original

    /// Reply and Reply All name the letter they answer, Forward the letter
    /// it passes on, by Gmail's id and the folder it was opened in; a
    /// letter with no Gmail id names none, and a new letter none.
    func testAReplyAndAForwardNameTheirOriginal() {
        var m = Message(id: "1/9", mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                        senderAddress: "jane@example.com", to: ["owner@example.com"], cc: [],
                        subject: "Lunch", date: Date(timeIntervalSince1970: 1_700_000_000),
                        textBody: "Lunch at one?", htmlBody: nil, attachments: [],
                        messageID: "<lunch@example.com>")
        XCTAssertNil(Draft.replying(to: m, all: false, myAddress: "owner@example.com").original)
        XCTAssertNil(Draft.forwarding(m).original)
        m.gmailMessageID = 1_800_000_000_000_000_042
        XCTAssertEqual(Draft.replying(to: m, all: false, myAddress: "owner@example.com").original,
                       OriginalLetter(kind: .reply, letter: 1_800_000_000_000_000_042,
                                      mailboxID: "INBOX"))
        XCTAssertEqual(Draft.replying(to: m, all: true, myAddress: "owner@example.com").original?.kind,
                       .reply)
        XCTAssertEqual(Draft.forwarding(m).original,
                       OriginalLetter(kind: .forward, letter: 1_800_000_000_000_000_042,
                                      mailboxID: "INBOX"))
        XCTAssertNil(Draft.blank(signature: "Sam").original)
        XCTAssertEqual(OriginalLetter(kind: .reply, letter: 1, mailboxID: "INBOX").flag, "\\Answered")
        XCTAssertEqual(OriginalLetter(kind: .forward, letter: 1, mailboxID: "INBOX").flag, "$Forwarded")
    }

    // MARK: - After the 250

    /// The owner's case: a reply sent from the composer. Nothing is written
    /// on the original while the letter waits for its 250; once it has come
    /// and the sheet has closed, one `UID STORE +FLAGS.SILENT (\Answered)`
    /// on the original, which then has the flag on Gmail, its row the reply
    /// arrow at the next listing and on the kept page, and the list told.
    func testAReplyThatWentMarksItsOriginalAnswered() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let (row, m) = try await original(repository)
        let told = Told()
        XCTAssertFalse(server.flags(uid: uid(row), in: Server.inbox).contains("\\Answered"))
        let held = ScriptedSubmission(holdsLetterReply: true)
        submissions.then { held }

        let sending = tapSend(reply(to: m), as: "reply", kept: kept, repository: repository)
        try await until { await held.isHoldingLetterReply }
        XCTAssertEqual(stores(), [], "nothing written before the 250")
        await held.releaseLetterReply()
        await sending?.value
        await repository.marksWritten()

        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(errors, [])
        XCTAssertEqual(stores(), ["UID STORE \(uid(row)) +FLAGS.SILENT (\\Answered)"])
        let flags = server.flags(uid: uid(row), in: Server.inbox)
        XCTAssertTrue(flags.contains("\\Answered"))
        XCTAssertFalse(flags.contains("$Forwarded"))
        XCTAssertEqual(told.marks, [OriginalLetter(kind: .reply, letter: row.gmailMessageID!,
                                                   mailboxID: row.mailboxID)])

        let kept1 = try XCTUnwrap(repository.shelf?.page(of: "inbox")).rows
        XCTAssertEqual(kept1.first { $0.id == row.id }?.isAnswered, true, "the kept page")
        XCTAssertEqual(kept1.filter(\.isAnswered).count, 1)
        let listed = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let again = try XCTUnwrap(listed.first { $0.id == row.id })
        XCTAssertTrue(again.isAnswered)
        XCTAssertEqual(again.arrow, .replied)
    }

    /// A forward: `$Forwarded`, not `\Answered`.
    func testAForwardThatWentMarksItsOriginalForwarded() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let (row, m) = try await original(repository)
        var draft = Draft.forwarding(m, includingFiles: false)
        draft.to = ["carlo@example.org"]

        await send(draft, as: "forward", kept: kept, repository: repository)
        await repository.marksWritten()

        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(stores(), ["UID STORE \(uid(row)) +FLAGS.SILENT ($Forwarded)"])
        let flags = server.flags(uid: uid(row), in: Server.inbox)
        XCTAssertTrue(flags.contains("$Forwarded"))
        XCTAssertFalse(flags.contains("\\Answered"))
        let listed = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        XCTAssertEqual(listed.first { $0.id == row.id }?.arrow, .forwarded)
    }

    /// A reply the server refuses after its DATA does not go, and nothing
    /// is marked: the sheet stays with the reason.
    func testAReplyThatDidNotGoMarksNothing() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let (row, m) = try await original(repository)
        submissions.then { ScriptedSubmission(letterReply: "554 5.7.0 Message refused") }

        await send(reply(to: m), as: "refused", kept: kept, repository: repository)
        await repository.marksWritten()

        XCTAssertEqual(dismissals, 0)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(stores(), [])
        XCTAssertFalse(server.flags(uid: uid(row), in: Server.inbox).contains("\\Answered"))
    }

    // MARK: - From the Outbox

    /// Sent with no connection, the reply waits in the Outbox, and nothing
    /// is marked. The app ended and opened again, the line back: the pass
    /// sends it, and the original is marked then, named by the letter kept
    /// on the iPad.
    func testAReplyFromTheOutboxMarksItsOriginalWhenItGoes() async throws {
        let repository = makeRepository()
        let (row, m) = try await original(repository)
        line.isUp = false
        await send(reply(to: m), as: "waiting", kept: makeKept(), repository: repository)
        await repository.marksWritten()
        XCTAssertEqual(queued, 1)
        XCTAssertEqual(stores(), [])
        let waiting = try XCTUnwrap(makeKept().store.letter("waiting"))
        XCTAssertNotNil(waiting.outbox)
        XCTAssertEqual(waiting.draft.original,
                       OriginalLetter(kind: .reply, letter: row.gmailMessageID!, mailboxID: row.mailboxID))

        line.isUp = true
        let relaunched = makeRepository()
        let kept = makeKept()
        _ = try await relaunched.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        await kept.uploadWaiting(to: relaunched)?.value
        await relaunched.marksWritten()

        XCTAssertEqual(kept.outbox.count, 0, "it went")
        XCTAssertEqual(submissions.all.count, 1)
        XCTAssertEqual(stores(), ["UID STORE \(uid(row)) +FLAGS.SILENT (\\Answered)"])
        XCTAssertTrue(server.flags(uid: uid(row), in: Server.inbox).contains("\\Answered"))
    }

    /// Cut off after its DATA, the 250 never seen: the reply waits in the
    /// Outbox unsettled, and nothing is marked. Found in Sent Mail by the
    /// next pass, it went: it is not sent again, and the original is
    /// marked then, once.
    func testAReplyFoundInSentMailMarksItsOriginal() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let (row, m) = try await original(repository)
        submissions.then { ScriptedSubmission(hangsUpBeforeLetterReply: true) }

        await send(reply(to: m), as: "cut", kept: kept, repository: repository)
        await repository.marksWritten()
        XCTAssertEqual(queued, 1)
        XCTAssertEqual(stores(), [], "nothing marked with no 250")
        let waiting = try XCTUnwrap(kept.store.letter("cut"))
        let messageID = try XCTUnwrap(waiting.outbox)
        XCTAssertEqual(waiting.unsettled, [messageID])

        server.deliver(Server.Letter(
            from: Server.owner, to: [Server.Address(name: nil, address: m.senderAddress)],
            subject: "Re: \(m.subject)", date: Server.newestDate.addingTimeInterval(60),
            text: "Thank you.\r\n", flags: ["\\Seen"], messageID: messageID),
            to: [Server.sent, Server.allMail])
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        await kept.uploadWaiting(to: repository)?.value
        await repository.marksWritten()

        XCTAssertEqual(kept.outbox.count, 0, "it went")
        XCTAssertEqual(submissions.all.count, 1, "not sent again")
        XCTAssertEqual(stores(), ["UID STORE \(uid(row)) +FLAGS.SILENT (\\Answered)"])
        XCTAssertTrue(server.flags(uid: uid(row), in: Server.inbox).contains("\\Answered"))

        await kept.uploadWaiting(to: repository)?.value
        await repository.marksWritten()
        XCTAssertEqual(stores().count, 1, "once")
    }

    // MARK: - The original moved, or gone

    /// The original archived elsewhere while the reply was written, the
    /// Inbox still selected on the connection: not in the Inbox any more,
    /// it is marked in All Mail, where it is.
    func testAnOriginalArchivedMeanwhileIsMarkedInAllMail() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let (row, m) = try await original(repository)
        let key = try XCTUnwrap(server.gmailMessageID(uid: uid(row), in: Server.inbox))
        let inAllMail = try XCTUnwrap(server.uids(in: Server.allMail).first {
            server.gmailMessageID(uid: $0, in: Server.allMail) == key
        })
        server.removeElsewhere(uid: uid(row), from: Server.inbox)

        await send(reply(to: m), as: "archived", kept: kept, repository: repository)
        await repository.marksWritten()

        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(stores(), ["UID STORE \(inAllMail) +FLAGS.SILENT (\\Answered)"])
        XCTAssertTrue(server.flags(uid: inAllMail, in: Server.allMail).contains("\\Answered"))
    }

    /// The original deleted after the reply was begun, so in the Trash and
    /// nowhere else: the reply goes, nothing is written, and nothing is
    /// said.
    func testAnOriginalGoneByThenMarksNothingAndSaysNothing() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let (row, m) = try await original(repository)
        let told = Told()
        try await repository.delete(row.id, gmailMessageID: row.gmailMessageID, from: "inbox")
        server.clearLog()

        await send(reply(to: m), as: "gone", kept: kept, repository: repository)
        await repository.marksWritten()

        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(errors, [])
        XCTAssertEqual(submissions.all.count, 1)
        XCTAssertEqual(stores(), [])
        let searches = server.log.map(\.command).filter { $0.contains("X-GM-MSGID \(row.gmailMessageID!)") }
        XCTAssertEqual(searches.count, 2, "its folder, then All Mail")
        for trashed in server.uids(in: Server.trash) {
            XCTAssertFalse(server.flags(uid: trashed, in: Server.trash).contains("\\Answered"))
        }
        XCTAssertEqual(told.marks, [], "nothing told")
    }

    /// The submission server reached and the IMAP server not: the reply
    /// went, the mark is dropped, and the sheet closes with no error, as
    /// for any letter that went, the letter not left in the Outbox. The
    /// IMAP server back, nothing is tried again.
    func testAMarkThatCannotBeWrittenIsDropped() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        let (row, m) = try await original(repository)
        await server.resetConnections()
        line.imapUp = false

        await send(reply(to: m), as: "dropped", kept: kept, repository: repository)
        await repository.marksWritten()

        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(errors, [])
        XCTAssertEqual(queued, 0, "it went, and does not wait in the Outbox")
        XCTAssertEqual(kept.outbox.count, 0)
        XCTAssertEqual(submissions.all.count, 1)
        XCTAssertEqual(stores(), [])
        XCTAssertFalse(server.flags(uid: uid(row), in: Server.inbox).contains("\\Answered"))

        line.imapUp = true
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        await kept.uploadWaiting(to: repository)?.value
        await repository.marksWritten()
        XCTAssertEqual(stores(), [], "not tried again")
    }

    // MARK: - Kept on the iPad

    /// The original is kept with a letter on the iPad, and read back; a
    /// letter kept by a build before it, or with the field damaged, reads
    /// with none and is still there to go.
    func testTheOriginalIsKeptWithTheLetterAndOldRecordsStillRead() throws {
        let store = LocalDraftStore(root: root)
        var draft = Draft()
        draft.to = ["jane@example.com"]
        draft.subject = "Re: Lunch"
        draft.body = "Yes."
        let named = OriginalLetter(kind: .forward, letter: 1_800_000_000_000_000_007,
                                   mailboxID: "[Gmail]/All Mail")
        draft.original = named
        try store.keep(draft, as: "kept", unfinished: false, account: server.username)
        XCTAssertEqual(store.letter("kept")?.draft.original, named)

        let file = root.appendingPathComponent("kept", isDirectory: true)
            .appendingPathComponent("letter.json")
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertNotNil(json["original"])
        json["original"] = "not an original"
        try JSONSerialization.data(withJSONObject: json).write(to: file, options: .atomic)
        XCTAssertNil(store.letter("kept")?.draft.original, "damaged, read as none")
        XCTAssertEqual(store.letter("kept")?.draft.subject, "Re: Lunch")

        json["original"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: file, options: .atomic)
        XCTAssertNil(store.letter("kept")?.draft.original, "an older build's, none")
        XCTAssertEqual(store.letters().count, 1)
    }

    // MARK: - The list

    /// The list puts the arrow on its rows of the marked letter, by Gmail's
    /// id: the reply arrow for an answer, the forward arrow for a forward,
    /// on the row in a search's hits too, and on no other row. A list that
    /// holds no row of it changes nothing.
    func testTheListPutsTheArrowOnTheMarkedLettersRows() {
        func row(_ n: UInt64, read: Bool = true) -> MessageSummary {
            MessageSummary(id: "1/\(n)", mailboxID: "INBOX", sender: "Jane", subject: "Letter \(n)",
                           preview: "", date: Date(timeIntervalSince1970: 1_700_000_000 + Double(n)),
                           isRead: read, isFlagged: false, threadID: "t\(n)", gmailMessageID: 700 + n)
        }
        let list = ListLetters()
        var changes: [ListChange] = []
        list.changed = { changes.append($0) }
        _ = list.fetchedAfresh([row(3), row(2), row(1)])

        list.originalMarked(OriginalLetter(kind: .reply, letter: 702, mailboxID: "INBOX"))
        XCTAssertEqual(list.folder.map(\.isAnswered), [false, true, false])
        XCTAssertEqual(list.folder.map(\.arrow), [nil, .replied, nil])
        XCTAssertEqual(changes, [.marked])

        list.originalMarked(OriginalLetter(kind: .forward, letter: 703, mailboxID: "INBOX"))
        XCTAssertEqual(list.folder.map(\.arrow), [.forwarded, .replied, nil])
        XCTAssertEqual(list.folder.map(\.isForwarded), [true, false, false])

        _ = list.showResults([row(1)])
        list.originalMarked(OriginalLetter(kind: .reply, letter: 701, mailboxID: "[Gmail]/All Mail"))
        XCTAssertEqual(list.results?.map(\.isAnswered), [true])
        XCTAssertEqual(list.folder.map(\.isAnswered), [false, true, true])

        changes = []
        list.originalMarked(OriginalLetter(kind: .reply, letter: 999, mailboxID: "INBOX"))
        XCTAssertEqual(changes, [])
    }

    /// A letter moved away and brought back by an Undo (B-157) comes back
    /// from the row as it was at the tap; a reply's mark that landed while
    /// it was away, on the row the list still held hidden, comes back
    /// with it, as Gmail has the flag, and not only at the next listing.
    func testAMarkThatLandedWhileTheLetterWasAwayComesBackWithItsUndo() {
        func row(_ n: UInt64) -> MessageSummary {
            MessageSummary(id: "1/\(n)", mailboxID: "INBOX", sender: "Jane", subject: "Letter \(n)",
                           preview: "", date: Date(timeIntervalSince1970: 1_700_000_000 + Double(n)),
                           isRead: true, isFlagged: false, threadID: "t\(n)", gmailMessageID: 700 + n)
        }
        let list = ListLetters()
        _ = list.fetchedAfresh([row(3), row(2), row(1)])
        let atTheTap = row(2)
        list.take(atTheTap, fromEveryFolder: false)
        XCTAssertEqual(list.shown.map(\.id), ["1/3", "1/1"])

        list.originalMarked(OriginalLetter(kind: .reply, letter: 702, mailboxID: "[Gmail]/All Mail"))
        XCTAssertTrue(list.restore(atTheTap, as: "1/9"))
        XCTAssertEqual(list.shown.map(\.id), ["1/3", "1/9", "1/1"])
        XCTAssertEqual(list.shown.map(\.isAnswered), [false, true, false])
        XCTAssertEqual(list.shown.map(\.isForwarded), [false, false, false])
    }

    /// Read from the source: the list controller hears the mark and hands
    /// it to its letters.
    func testTheListControllerHearsTheMark() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/UI/MessageListViewController.swift"))
        XCTAssertTrue(source.contains("name: OriginalLetter.marked"))
        XCTAssertTrue(source.contains("letters.originalMarked(original)"))
    }
}

/// The marks the lists are told of (`OriginalLetter.marked`), for as long
/// as it is held.
private final class Told {
    private(set) var marks: [OriginalLetter] = []
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: OriginalLetter.marked, object: nil, queue: nil) { [weak self] note in
            if let mark = note.userInfo?[OriginalLetter.markedKey] as? OriginalLetter {
                self?.marks.append(mark)
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

/// Whether the line is up, and the IMAP server with it.
private final class MarkLine: @unchecked Sendable {
    private let lock = NSLock()
    private var up = true
    private var imap = true

    var isUp: Bool {
        get { lock.lock(); defer { lock.unlock() }; return up }
        set { lock.lock(); up = newValue; lock.unlock() }
    }

    var imapUp: Bool {
        get { lock.lock(); defer { lock.unlock() }; return imap }
        set { lock.lock(); imap = newValue; lock.unlock() }
    }
}

/// A submission server per connection: the ones a test lines up first,
/// then ones that take every letter.
private final class MarkSubmissions: @unchecked Sendable {
    private let lock = NSLock()
    private var servers: [ScriptedSubmission] = []
    private var script: [() -> ScriptedSubmission] = []

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
