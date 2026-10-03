import XCTest
@testable import Blackmail

/// Edit mode's Delete and Move of the letters he ticked (B-062): every row
/// off at the tap, a letter at a time to the server, a refused letter back
/// on the list with the rest unsent and the refusal for the alert, and the
/// counts right for the letters that went. Over `ScriptedIMAPServer`
/// through the shipping repository, with the list's own letters,
/// `ListLetters`, as `PaneActionsTests` runs the pane's.
///
/// Both used to send each write with `try?` and fetch the list again after
/// all of them: a refusal said nothing, and Delete said nothing while it
/// worked. What the controller does with the outcome is read from its
/// source at the foot.
final class ListBatchTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "ListBatchTests"

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
                           transport: server.transportFactory, recipients: book,
                           shelf: keptShelf(for: server.account))
    }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    private func uid(_ id: String) -> UInt32 { UInt32(id.split(separator: "/").last ?? "")! }

    private let folders = [
        Mailbox(id: "inbox", name: "Inbox", unreadCount: 0, role: .inbox),
        Mailbox(id: Server.inbox, name: "INBOX", unreadCount: 0, role: .inbox),
        Mailbox(id: Server.allMail, name: "All Mail", unreadCount: 0, role: .archive),
        Mailbox(id: Server.trash, name: "Trash", unreadCount: 0, role: .trash),
        Mailbox(id: Server.spam, name: "Spam", unreadCount: 0, role: .junk),
        Mailbox(id: Server.sent, name: "Sent Mail", unreadCount: 0, role: .sent),
    ]

    /// The list's letters as `MessageListViewController` holds them.
    @MainActor
    private func makeList(folder: [MessageSummary],
                          results: [MessageSummary]? = nil) -> (ListLetters, Billing) {
        let list = ListLetters()
        let counts = Billing()
        list.onUnreadCountChanged = { counts.record($0, $1) }
        _ = list.fetchedAfresh(folder)
        if let results { list.showResults(results) }
        return (list, counts)
    }

    @MainActor
    private func run(_ action: PaneAction, on letters: [MessageSummary], list: ListLetters,
                     repository: IMAPMailRepository, sweeps: Counter) async -> ListBatch.Outcome {
        let folders = self.folders
        return await ListBatch.run(action, on: letters, role: { folders.role(of: $0) },
                                   list: list, repository: repository,
                                   requestSweep: { sweeps.add() })
    }

    // MARK: - Every letter goes

    /// Four letters ticked, two of them unread: all four rows go at the tap,
    /// before the server has answered any of them, one UID MOVE each and
    /// nothing else, no fetch of the list again, each unread one billed
    /// once, and one sweep asked for at the end for Trash's count, not one
    /// for each.
    func testEveryRowGoesAtTheTapAndEachLetterIsMovedToTrashInTurn() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let chosen = [rows[0], rows[1], rows[10], rows[20]]
        XCTAssertEqual(chosen.map(\.isRead), [false, false, true, true])
        let (list, counts) = await makeList(folder: rows)
        let sweeps = Counter()
        server.clearLog()

        server.holdReplies(to: "UID MOVE")
        let batch = Task {
            await self.run(.delete, on: chosen, list: list, repository: repository, sweeps: sweeps)
        }
        try await until { self.server.log.contains { $0.verb == "UID MOVE" } }
        let atTheTap = await list.shown.map(\.id)
        XCTAssertEqual(atTheTap, rows.map(\.id).filter { id in !chosen.contains { $0.id == id } })
        await server.releaseReplies(to: "UID MOVE")
        let outcome = try await finishing { await batch.value }

        XCTAssertEqual(outcome, ListBatch.Outcome(taken: chosen.map(\.id), notTaken: [],
                                                  refusal: nil))
        XCTAssertEqual(server.log.map(\.command),
                       chosen.map { "UID MOVE \(uid($0.id)) \"\(Server.trash)\"" })
        let after = await list.shown.map(\.id)
        XCTAssertEqual(after, atTheTap)
        let billed = await counts.billed
        XCTAssertEqual(billed, [[Server.inbox, Server.allMail], [Server.inbox, Server.allMail]])
        XCTAssertEqual(sweeps.value, 1)
        for letter in chosen { XCTAssertFalse(server.uids(in: Server.inbox).contains(uid(letter.id))) }
    }

    /// Inside Trash each letter is erased, `\Deleted` and a UID EXPUNGE of
    /// it, and the one off Trash's count for an unread one is the whole
    /// change: nothing is swept. From an All Mailboxes search that mixes
    /// Trash with All Mail, each letter goes by its own folder: the hit
    /// from Trash erased, gone from the server with Auto-Expunge off, and
    /// the other binned, in Trash.
    func testEachLetterGoesByItsOwnFolderInsideTrashAndOut() async throws {
        let erased = server.deliver(Server.Letter(from: Server.carlo, to: [Server.owner],
                                                  subject: "Binned unread",
                                                  date: Server.newestDate,
                                                  text: "Never read.\r\n",
                                                  messageID: "<binned-unread@example.org>"),
                                    to: [Server.trash])
        let repository = makeRepository()
        _ = try await repository.folders()
        let trash = try await repository.listMessages(in: Server.trash, beforeUID: nil, limit: 50)
        let binned = try XCTUnwrap(trash.first { $0.subject == "Binned unread" })
        XCTAssertFalse(binned.isRead)
        let (list, counts) = await makeList(folder: trash)
        let sweeps = Counter()
        server.clearLog()

        let inTrash = await run(.delete, on: [binned], list: list, repository: repository,
                                sweeps: sweeps)
        XCTAssertEqual(inTrash, ListBatch.Outcome(taken: [binned.id], notTaken: [], refusal: nil))
        let erasedUID = try XCTUnwrap(erased[Server.trash])
        XCTAssertEqual(server.log.map(\.command),
                       ["UID STORE \(erasedUID) +FLAGS.SILENT (\\Deleted)", "UID EXPUNGE \(erasedUID)"])
        XCTAssertFalse(server.uids(in: Server.trash).contains(erasedUID))
        XCTAssertEqual(sweeps.value, 0)
        let billed = await counts.billed
        XCTAssertEqual(billed, [[Server.trash]])

        let other = server.deliver(Server.Letter(from: Server.jane, to: [Server.owner],
                                                 subject: "Binned again",
                                                 date: Server.newestDate.addingTimeInterval(60),
                                                 text: "Still in the bin.\r\n",
                                                 messageID: "<binned-again@example.com>"),
                                   to: [Server.trash])
        // The hits an All Mailboxes search would show, each under its own
        // folder's id, as `IMAPMailRepository.search` gives them.
        let inbox = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let trashed = try await repository.listMessages(in: Server.trash, beforeUID: nil, limit: 50)
        let fromTrash = try XCTUnwrap(trashed.first { $0.subject == "Binned again" })
        let allMail = try await repository.listMessages(in: Server.allMail, beforeUID: nil,
                                                        limit: 50)
        let fromAllMail = try XCTUnwrap(allMail.first { $0.isRead })
        let (mixed, _) = await makeList(folder: inbox, results: [fromTrash, fromAllMail])
        server.clearLog()

        let both = await run(.delete, on: [fromAllMail, fromTrash], list: mixed,
                             repository: repository, sweeps: sweeps)
        XCTAssertEqual(both.taken, [fromAllMail.id, fromTrash.id])
        let otherUID = try XCTUnwrap(other[Server.trash])
        XCTAssertEqual(server.log.filter { $0.isUIDCommand }.map(\.command), [
            "UID MOVE \(uid(fromAllMail.id)) \"\(Server.trash)\"",
            "UID STORE \(otherUID) +FLAGS.SILENT (\\Deleted)",
            "UID EXPUNGE \(otherUID)",
        ])
        XCTAssertFalse(server.uids(in: Server.trash).contains(otherUID))
        XCTAssertTrue(server.uids(in: Server.trash).contains {
            server.gmailMessageID(uid: $0, in: Server.trash) == fromAllMail.gmailMessageID
        })
        // The hit from Trash was unread, and ticked after one from All Mail:
        // inside Trash nothing is swept for it, whatever went before it.
        XCTAssertFalse(fromTrash.isRead)
        XCTAssertTrue(fromAllMail.isRead)
        XCTAssertEqual(sweeps.value, 0)
    }

    // MARK: - Erased inside Trash, whatever Auto-Expunge says

    /// Edit mode in Trash, two letters ticked, with a third there marked
    /// `\Deleted` by another mail program: each of the two is erased in
    /// turn, its STORE and a UID EXPUNGE naming it alone, and both are gone
    /// from the server with Auto-Expunge off. The third, which neither
    /// EXPUNGE named, is still there and still marked. Nothing is swept.
    func testEditModesDeleteInTrashErasesEachLetterAndNoOther() async throws {
        XCTAssertFalse(server.autoExpunge)
        let repository = makeRepository()
        _ = try await repository.folders()
        let trash = try await repository.listMessages(in: Server.trash, beforeUID: nil, limit: 50)
        let chosen = [trash[0], trash[2]]
        let marked = uid(trash[3].id)
        server.markDeleted(uid: marked, in: Server.trash)
        let (list, _) = await makeList(folder: trash)
        let sweeps = Counter()
        let before = server.uids(in: Server.trash)
        server.clearLog()

        let outcome = await run(.delete, on: chosen, list: list, repository: repository,
                                sweeps: sweeps)

        XCTAssertEqual(outcome, ListBatch.Outcome(taken: chosen.map(\.id), notTaken: [],
                                                  refusal: nil))
        XCTAssertEqual(server.log.map(\.command), chosen.flatMap {
            ["UID STORE \(uid($0.id)) +FLAGS.SILENT (\\Deleted)", "UID EXPUNGE \(uid($0.id))"]
        })
        XCTAssertEqual(server.uids(in: Server.trash),
                       before.filter { id in !chosen.contains { uid($0.id) == id } })
        XCTAssertTrue(server.uids(in: Server.trash).contains(marked))
        XCTAssertTrue(server.flags(uid: marked, in: Server.trash).contains("\\Deleted"))
        let shown = await list.shown.map(\.id)
        XCTAssertEqual(shown, trash.map(\.id).filter { id in !chosen.contains { $0.id == id } })
        XCTAssertEqual(sweeps.value, 0)
    }

    /// On a server without UIDPLUS the EXPUNGE is the plain one. It takes
    /// his letter, and with it every other letter in Trash already marked
    /// `\Deleted`, which some mail program has asked to be erased; no
    /// letter in Trash that is not marked. Gmail has UIDPLUS. The flag
    /// alone, here, would have left his letter in Trash.
    func testWithoutUIDPLUSThePlainExpungeTakesOnlyWhatIsMarkedInTrash() async throws {
        server.withheldCapabilities = ["UIDPLUS"]
        let repository = makeRepository()
        _ = try await repository.folders()
        let trash = try await repository.listMessages(in: Server.trash, beforeUID: nil, limit: 50)
        let chosen = trash[1]
        let marked = uid(trash[4].id)
        server.markDeleted(uid: marked, in: Server.trash)
        let before = server.uids(in: Server.trash)
        let (list, _) = await makeList(folder: trash)
        let sweeps = Counter()
        server.clearLog()

        let outcome = await run(.delete, on: [chosen], list: list, repository: repository,
                                sweeps: sweeps)

        XCTAssertEqual(outcome.taken, [chosen.id])
        XCTAssertEqual(server.log.map(\.command),
                       ["UID STORE \(uid(chosen.id)) +FLAGS.SILENT (\\Deleted)", "EXPUNGE"])
        XCTAssertEqual(server.log.map(\.selected), [Server.trash, Server.trash])
        XCTAssertEqual(server.uids(in: Server.trash),
                       before.filter { $0 != uid(chosen.id) && $0 != marked })
    }

    /// The UID EXPUNGE refused, the connection up: the first letter's row
    /// comes back and the second's with it, unsent, the refusal for the
    /// alert, and nothing billed. The first is still in Trash, marked; a
    /// Delete of both again, once Gmail takes it, erases both.
    func testARefusedExpungeIsSaidAndItsRowComesBack() async throws {
        let repository = makeRepository()
        _ = try await repository.folders()
        let trash = try await repository.listMessages(in: Server.trash, beforeUID: nil, limit: 50)
        let chosen = [trash[0], trash[1]]
        let (list, counts) = await makeList(folder: trash)
        let sweeps = Counter()
        server.refusedVerbs = ["UID EXPUNGE"]
        server.clearLog()

        let outcome = await run(.delete, on: chosen, list: list, repository: repository,
                                sweeps: sweeps)

        XCTAssertEqual(outcome, ListBatch.Outcome(taken: [], notTaken: chosen.map(\.id),
                                                  refusal: .cannotConnect))
        XCTAssertEqual(MailAlert.reaching(try XCTUnwrap(outcome.refusal)).message,
                       "Can't connect to mail server.")
        XCTAssertEqual(server.log.map(\.command),
                       ["UID STORE \(uid(chosen[0].id)) +FLAGS.SILENT (\\Deleted)",
                        "UID EXPUNGE \(uid(chosen[0].id))"])
        let shown = await list.shown.map(\.id)
        XCTAssertEqual(shown, trash.map(\.id))
        let billed = await counts.billed
        XCTAssertEqual(billed, [])
        XCTAssertEqual(sweeps.value, 0)
        for letter in chosen { XCTAssertTrue(server.uids(in: Server.trash).contains(uid(letter.id))) }
        XCTAssertTrue(server.flags(uid: uid(chosen[0].id), in: Server.trash).contains("\\Deleted"))
        XCTAssertFalse(server.flags(uid: uid(chosen[1].id), in: Server.trash).contains("\\Deleted"))

        server.refusedVerbs = []
        let again = await run(.delete, on: chosen, list: list, repository: repository,
                              sweeps: sweeps)
        XCTAssertEqual(again.taken, chosen.map(\.id))
        for letter in chosen { XCTAssertFalse(server.uids(in: Server.trash).contains(uid(letter.id))) }
    }

    /// Moved, the rows go at once and each letter is filed in turn; an
    /// unread one changes the destination's count, which the list cannot
    /// work out, so the counts are swept, once.
    func testAMoveOfSeveralLettersFilesEachAndSweepsOnce() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let chosen = [rows[0], rows[1], rows[12]]
        let (list, counts) = await makeList(folder: rows)
        let sweeps = Counter()
        let sent = Mailbox(id: Server.sent, name: "Sent Mail", unreadCount: 0, role: .sent)
        let inboxBefore = server.uids(in: Server.inbox).count
        let sentBefore = server.uids(in: Server.sent).count
        server.clearLog()

        let outcome = await run(.move(to: sent), on: chosen, list: list, repository: repository,
                                sweeps: sweeps)

        XCTAssertEqual(outcome, ListBatch.Outcome(taken: chosen.map(\.id), notTaken: [],
                                                  refusal: nil))
        XCTAssertEqual(server.log.map(\.verb), ["UID MOVE", "UID MOVE", "UID MOVE"])
        let shown = await list.shown.map(\.id)
        XCTAssertEqual(shown.count, rows.count - 3)
        let billed = await counts.billed
        XCTAssertEqual(billed, [])
        XCTAssertEqual(sweeps.value, 1)
        XCTAssertEqual(server.uids(in: Server.inbox).count, inboxBefore - 3)
        XCTAssertEqual(server.uids(in: Server.sent).count, sentBefore + 3)
        for letter in chosen { XCTAssertFalse(server.uids(in: Server.inbox).contains(uid(letter.id))) }
    }

    // MARK: - A letter the server does not take

    /// The second of four letters is refused, the connection staying up as
    /// Gmail's does for "[UNAVAILABLE]": the first has gone, and is off the
    /// list and billed; the second is back on the list where it stood, and
    /// so are the third and fourth, which were never sent. The refusal is
    /// what the alert says. Nothing claims the letters that stayed have gone.
    func testARefusalPutsItsLetterBackAndTheRestAreNotSent() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let chosen = [rows[0], rows[1], rows[2], rows[3]]
        XCTAssertEqual(chosen.map(\.isRead), [false, false, false, false])
        let (list, counts) = await makeList(folder: rows)
        let sweeps = Counter()
        server.clearLog()

        server.holdReplies(to: "UID MOVE")
        let batch = Task {
            await self.run(.delete, on: chosen, list: list, repository: repository, sweeps: sweeps)
        }
        try await until { self.server.log.contains { $0.verb == "UID MOVE" } }
        server.refusedVerbs = ["UID MOVE", "UID COPY"]
        await server.releaseReplies(to: "UID MOVE")
        let outcome = try await finishing { await batch.value }

        XCTAssertEqual(outcome, ListBatch.Outcome(taken: [rows[0].id],
                                                  notTaken: chosen.dropFirst().map(\.id),
                                                  refusal: .cannotConnect))
        XCTAssertEqual(server.log.filter { $0.isUIDCommand }.map(\.command), [
            "UID MOVE \(uid(rows[0].id)) \"\(Server.trash)\"",
            "UID MOVE \(uid(rows[1].id)) \"\(Server.trash)\"",
            "UID COPY \(uid(rows[1].id)) \"\(Server.trash)\"",
        ])
        let shown = await list.shown.map(\.id)
        XCTAssertEqual(shown, rows.dropFirst().map(\.id))
        let billed = await counts.billed
        XCTAssertEqual(billed, [[Server.inbox, Server.allMail]])
        XCTAssertEqual(sweeps.value, 1)
        let inbox = server.uids(in: Server.inbox)
        XCTAssertFalse(inbox.contains(uid(rows[0].id)))
        for letter in chosen.dropFirst() { XCTAssertTrue(inbox.contains(uid(letter.id))) }
    }

    /// A password refused at the first letter is said as Mail says it, and
    /// is not sent again for every other letter: one LOGIN, and every row
    /// back. Google counts each refused sign-in against the account.
    func testARefusedPasswordStopsTheRestAndIsSentOnce() async throws {
        let rows = try await makeRepository().listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let chosen = Array(rows.prefix(5))
        let (list, counts) = await makeList(folder: rows)
        let sweeps = Counter()
        server.passwordRevoked = true
        let repository = makeRepository()
        server.clearLog()

        let outcome = await run(.delete, on: chosen, list: list, repository: repository,
                                sweeps: sweeps)

        XCTAssertEqual(outcome, ListBatch.Outcome(taken: [], notTaken: chosen.map(\.id),
                                                  refusal: .passwordNeedsUpdating))
        XCTAssertEqual(MailAlert.reaching(try XCTUnwrap(outcome.refusal)).title, "Cannot Get Mail")
        XCTAssertEqual(server.log.filter { $0.verb == "LOGIN" }.count, 1)
        XCTAssertFalse(server.log.contains { $0.isUIDCommand })
        let shown = await list.shown.map(\.id)
        XCTAssertEqual(shown, rows.map(\.id))
        let billed = await counts.billed
        XCTAssertEqual(billed, [])
        XCTAssertEqual(sweeps.value, 0)
    }

    /// A row kept on the iPad that the server says is another letter now
    /// (D-016) sends nothing and says nothing of the others: it comes off,
    /// as it does from the pane, the letters after it still go, and the
    /// alert says what the pane's says for it.
    func testARowThatIsNotTheKeptLetterDoesNotStopTheRest() async throws {
        let repository = makeRepository()
        var rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let real = rows[11]
        rows[11].gmailMessageID = (real.gmailMessageID ?? 0) + 1_000_000
        let stale = rows[11]
        let chosen = [rows[10], stale, rows[12]]
        let (list, _) = await makeList(folder: rows)
        let sweeps = Counter()
        server.clearLog()

        let outcome = await run(.delete, on: chosen, list: list, repository: repository,
                                sweeps: sweeps)

        XCTAssertEqual(outcome, ListBatch.Outcome(taken: [rows[10].id, rows[12].id],
                                                  notTaken: [stale.id], refusal: .cannotConnect))
        XCTAssertEqual(server.log.map(\.command), [
            "UID MOVE \(uid(rows[10].id)) \"\(Server.trash)\"",
            "UID MOVE \(uid(rows[12].id)) \"\(Server.trash)\"",
        ])
        let shown = await list.shown.map(\.id)
        XCTAssertFalse(shown.contains(stale.id))
        XCTAssertTrue(server.uids(in: Server.inbox).contains(uid(real.id)))
    }

    // MARK: - In list order

    /// The rows he ticked go in list order, whatever order he ticked them
    /// in, which is the order UIKit gives them: the rows from the top down,
    /// a conversation's letters together as it holds them, each letter
    /// once, and a row past the end of the list, which a regroup can leave
    /// ticked, nothing. Taken in the order ticked, the third row's letter
    /// went before the first's.
    func testTickedRowsGoInListOrderWhateverOrderHeTickedThem() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        // The fifth row a conversation that holds the third's letter too,
        // as two conversations merged by a page can.
        let threads = [
            MessageThread(messages: [rows[0]]),
            MessageThread(messages: [rows[1]]),
            MessageThread(messages: [rows[2], rows[6]]),
            MessageThread(messages: [rows[3]]),
            MessageThread(messages: [rows[4], rows[2]]),
        ]
        let inListOrder = [rows[0], rows[2], rows[6], rows[4]]
        let chosen = await ListBatch.letters(ticked: [4, 0, 2, 0, 9], in: threads)
        XCTAssertEqual(chosen.map(\.id), inListOrder.map(\.id))

        let (list, _) = await makeList(folder: rows)
        let sweeps = Counter()
        server.clearLog()
        let outcome = await run(.delete, on: chosen, list: list, repository: repository,
                                sweeps: sweeps)

        XCTAssertEqual(outcome.taken, inListOrder.map(\.id))
        XCTAssertEqual(server.log.map(\.command),
                       inListOrder.map { "UID MOVE \(uid($0.id)) \"\(Server.trash)\"" })
    }

    // MARK: - The reading pane

    /// An All Mailboxes hit from All Mail deleted in Edit mode while the
    /// pane shows the same letter opened from the Inbox empties the pane,
    /// and so does the Inbox row deleted while the pane shows the hit: one
    /// letter under two mailboxes' ids. Matched on ids alone, the pane kept
    /// the binned letter with Reply, Move and Delete live. Each sign of the
    /// same letter does on its own: a twin's thread, date, sender and
    /// subject, and the Gmail message id. A letter he did not tick, in the
    /// same conversation or not, leaves the pane as it is.
    func testThePaneEmptiesForTheSameLetterUnderAnotherMailboxsID() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let hits = try await repository.search(in: "inbox", query: "Letter 118",
                                               scope: .allMailboxes, beforeUID: nil, limit: 50)
        let hit = try XCTUnwrap(hits.first { $0.mailboxID == Server.allMail })
        let inboxCopy = try XCTUnwrap(rows.first { $0.subject == hit.subject })
        XCTAssertNotEqual(hit.id, inboxCopy.id)
        XCTAssertNotNil(hit.gmailMessageID)
        XCTAssertEqual(hit.gmailMessageID, inboxCopy.gmailMessageID)
        var other = try XCTUnwrap(rows.first { $0.subject != hit.subject })

        // The hit deleted while the pane shows the Inbox's copy, and the
        // Inbox's row deleted while it shows the hit.
        XCTAssertTrue(ListEdit.going([inboxCopy], with: [hit]))
        XCTAssertTrue(ListEdit.going([hit], with: [inboxCopy]))
        // A twin with no Gmail message id, both ways.
        var bareHit = hit, bareCopy = inboxCopy
        bareHit.gmailMessageID = nil
        bareCopy.gmailMessageID = nil
        XCTAssertTrue(ListEdit.going([bareCopy], with: [bareHit]))
        XCTAssertTrue(ListEdit.going([bareHit], with: [bareCopy]))
        // The Gmail message id with no thread to make a twin, both ways.
        var threadlessHit = hit, threadlessCopy = inboxCopy
        threadlessHit.threadID = nil
        threadlessCopy.threadID = nil
        XCTAssertTrue(ListEdit.going([threadlessCopy], with: [threadlessHit]))
        XCTAssertTrue(ListEdit.going([threadlessHit], with: [threadlessCopy]))
        // Its own id, as before, and a letter of the conversation shown.
        XCTAssertTrue(ListEdit.going([inboxCopy], with: [inboxCopy]))
        XCTAssertTrue(ListEdit.going([other, inboxCopy], with: [hit]))
        // Not ticked, even in the same conversation: left as it is.
        other.threadID = inboxCopy.threadID
        XCTAssertFalse(ListEdit.going([other], with: [hit, inboxCopy]))
        XCTAssertFalse(ListEdit.going([], with: [hit]))
    }

    // MARK: - The controller

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

    /// Edit mode's Delete and Move both go through `ListBatch`: Edit mode
    /// ends and the rows go at the tap, the status line says "Deleting…" or
    /// "Moving…" until every letter has been answered for, the reading pane
    /// empties only if it shows one of them, under its own id or another
    /// mailbox's, and a refusal is put up as the pane's is, over what is in
    /// front if he has opened another folder meanwhile. The letters kept on
    /// the iPad go from it, each on its own. The ticked rows are taken in
    /// list order. No write is sent with `try?`, and the list is not
    /// fetched again.
    func testEditModeSaysWhatIsUnderWayAndWhatWasRefused() throws {
        XCTAssertEqual(StatusLine.deleting, "Deleting…")
        XCTAssertEqual(StatusLine.moving, "Moving…")
        let list = try source("UI/MessageListViewController.swift")
        for line in [
            "private var selectedMessages: [MessageSummary] { ListBatch.letters(ticked: "
                + "(tableView.indexPathsForSelectedRows ?? []).map(\\.row), in: threads) }",
            "private func delete(_ chosen: [MessageSummary]) { if tableView.isEditing { "
                + "editTapped() } let kept = self.kept let repository = self.repository "
                + "for m in chosen { guard let key = LocalDraft.key(ofRow: m.id) else { "
                + "continue } Task { @MainActor in await kept.delete(key, from: repository) "
                + "} } runBatch(.delete, on: onServer(chosen), saying: StatusLine.deleting) }",
            "guard !chosen.isEmpty else { return } let done = working(words) "
                + "onLettersLeaving?(chosen) Task { @MainActor [weak window = view.window] in "
                + "let outcome = await ListBatch.run( action, on: chosen, role: { "
                + "self.role(of: $0) }, list: self.letters, repository: self.repository, "
                + "requestSweep: { [weak self] in self?.requestSweep?() }) done() if let "
                + "refusal = outcome.refusal { ErrorPresenter.show(reaching: refusal, on: "
                + "self.alertHost(in: window)) } } }",
            "private func alertHost(in window: UIWindow?) -> UIViewController { guard "
                + "viewIfLoaded?.window == nil, var front = window?.rootViewController else { "
                + "return self } while let next = front.presentedViewController, "
                + "!next.isBeingDismissed { front = next } return front }",
            "if self.tableView.isEditing { self.editTapped() } self.runBatch(.move(to: "
                + "destination), on: chosen, saying: StatusLine.moving) }",
        ] {
            XCTAssertTrue(list.contains(line), line)
        }
        XCTAssertFalse(list.contains("try? await repository.delete"))
        XCTAssertFalse(list.contains("try? await self.repository.move"))
        XCTAssertFalse(list.contains("await self.reload(keepingPlace: true)"))
        XCTAssertFalse(list.contains("await reload(keepingPlace: true)"))

        let root = try source("UI/RootViewController.swift")
        for line in [
            "list.onLettersLeaving = { [weak self] letters in "
                + "self?.detail.clearIfShowing(any: letters) }",
            "list.requestSweep = { [weak self] in self?.refreshMailboxes() }",
        ] {
            XCTAssertTrue(root.contains(line), line)
        }
        let pane = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(pane.contains(
            "func clearIfShowing(any letters: [MessageSummary]) { let shown = "
            + "[summary].compactMap { $0 } + Array(threadSummaries.values) guard "
            + "ListEdit.going(shown, with: letters) else { return } showEmpty() }"))
    }
}

/// What the list says to the folder counts, written down.
@MainActor
private final class Billing {
    /// The folders each letter billed as gone unread came off, one entry
    /// per letter.
    private(set) var billed: [[String]] = []

    func record(_ folders: [String], _ delta: Int) {
        if delta < 0 { billed.append(folders) }
    }
}
