import XCTest
@testable import Blackmail

/// B-092: a MOVE answered OK counts as done only if the answer shows it.
/// Seen once on the test iPad on 2026-10-21: Edit > Delete of three Inbox
/// rows, and Gmail answered the first `UID MOVE 343 "[Gmail]/Trash"` with
/// `OK [COPYUID 2 343 0] (Success)`, a destination UID of 0 and no EXPUNGE,
/// and nothing had moved. The app took the OK for a move done: the row
/// stayed off, the kept copy let the letter go, and it came back only at a
/// Refresh more than two minutes later.
///
/// The answer's reading (`IMAPMoveAnswer`) on strings as Gmail sent them,
/// and the rest over the shipping repository and client, the list's own
/// letters (`ListLetters`), the kept copy and `ScriptedIMAPServer`, whose
/// `hollowMoves` answer the next MOVEs as Gmail answered that one, with
/// nothing moved or with the letter moved and the connection not told, and
/// whose `hollowCopies` answer a COPY so.
final class HollowMoveTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "HollowMoveTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var shelf: MailShelf!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        shelf = keptShelf(for: server.account)
        Diagnostics.clear()
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        server = nil
        book = nil
        shelf = nil
        super.tearDown()
    }

    private func makeRepository() -> IMAPMailRepository {
        IMAPMailRepository(account: server.account, password: server.password,
                           transport: server.transportFactory, recipients: book, shelf: shelf)
    }

    /// A repository with the Inbox's first page listed and kept, and the
    /// server's log and the connection log cleared after it.
    private func listed() async throws -> (IMAPMailRepository, [MessageSummary]) {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(kept(rows[0]), true)
        server.clearLog()
        Diagnostics.clear()
        return (repository, rows)
    }

    private func uid(_ id: String) -> UInt32 { UInt32(id.split(separator: "/").last ?? "")! }

    /// The letter's Message-ID as the server has it in the Inbox now.
    private func messageID(of row: MessageSummary) -> String {
        server.letter(uid: uid(row.id), in: Server.inbox)!.messageID
    }

    /// How many letters with `messageID` `mailbox` holds.
    private func copies(of messageID: String, in mailbox: String) -> Int {
        server.uids(in: mailbox).filter { server.letter(uid: $0, in: mailbox)?.messageID == messageID }.count
    }

    /// Whether the kept Inbox has the row.
    private func kept(_ row: MessageSummary) -> Bool? {
        shelf.page(of: "inbox").map { page in page.rows.contains { $0.id == row.id } }
    }

    /// The connection log's lines about a MOVE's answer, and nothing else.
    private var moveNotes: [String] {
        Diagnostics.entries.filter { $0.direction == .note }.map(\.text)
            .filter { $0.hasPrefix("MOVE-") }
    }

    private func moveToTrash(_ row: MessageSummary) -> String {
        "UID MOVE \(uid(row.id)) \"\(Server.trash)\""
    }

    private func search(_ row: MessageSummary) -> String { "UID SEARCH UID \(uid(row.id))" }

    private let folders = [
        Mailbox(id: "inbox", name: "Inbox", unreadCount: 0, role: .inbox),
        Mailbox(id: Server.inbox, name: "INBOX", unreadCount: 0, role: .inbox),
        Mailbox(id: Server.allMail, name: "All Mail", unreadCount: 0, role: .archive),
        Mailbox(id: Server.trash, name: "Trash", unreadCount: 0, role: .trash),
        Mailbox(id: Server.spam, name: "Spam", unreadCount: 0, role: .junk),
        Mailbox(id: Server.sent, name: "Sent Mail", unreadCount: 0, role: .sent),
    ]

    @MainActor
    private func makeList(_ rows: [MessageSummary]) -> ListLetters {
        let list = ListLetters()
        _ = list.fetchedAfresh(rows)
        return list
    }

    // MARK: - The answer, read for the letter

    private func answer(_ detail: String, _ untagged: [String] = [],
                        uid: UInt32) -> IMAPMoveAnswer {
        IMAPMoveAnswer(IMAPCommandResult(status: .ok, detail: detail,
                                         untagged: untagged.map { IMAPResponseLine(text: $0, literals: []) }),
                       uid: uid)
    }

    /// Gmail's answers as the connection logs have them: a MOVE done, an
    /// EXPUNGE and the tagged OK's COPYUID with a UID in it, shows it; the
    /// iPad's, a COPYUID with 0 for the destination and no EXPUNGE, does
    /// not, nor does the `OK Success` with no COPYUID of a MOVE sent in the
    /// wrong mailbox on 2026-09-28. RFC 6851's untagged COPYUID is read as
    /// well as the tagged one, and either a COPYUID naming the letter or an
    /// EXPUNGE is enough.
    func testAMovesAnswerShowsItOnlyWithACopyUIDNamingTheLetterOrAnExpunge() {
        let done = answer("[COPYUID 2 344 288] (Success)", ["* 68 EXPUNGE", "* 68 EXISTS"], uid: 344)
        XCTAssertEqual(done, IMAPMoveAnswer(copyUID: .names, expunged: true))
        XCTAssertTrue(done.showsMove)

        let hollow = answer("[COPYUID 2 343 0] (Success)", uid: 343)
        XCTAssertEqual(hollow, IMAPMoveAnswer(copyUID: .zero, expunged: false))
        XCTAssertFalse(hollow.showsMove)
        XCTAssertEqual(hollow.described, "copyuid=dest-0 no-expunge")

        let wrongMailbox = answer("Success", uid: 16)
        XCTAssertEqual(wrongMailbox, IMAPMoveAnswer(copyUID: .none, expunged: false))
        XCTAssertFalse(wrongMailbox.showsMove)
        XCTAssertEqual(wrongMailbox.described, "copyuid=none no-expunge")

        let rfc = answer("Done", ["* OK [COPYUID 432432 42 1202] (Success)", "* 22 EXPUNGE"], uid: 42)
        XCTAssertEqual(rfc, IMAPMoveAnswer(copyUID: .names, expunged: true))

        XCTAssertTrue(answer("[COPYUID 2 344 288] (Success)", uid: 344).showsMove, "the COPYUID alone")
        XCTAssertTrue(answer("Success", ["* 68 EXPUNGE"], uid: 344).showsMove, "the EXPUNGE alone")
        XCTAssertTrue(answer("[COPYUID 2 343 0] (Success)", ["* 68 EXPUNGE"], uid: 343).showsMove,
                      "an EXPUNGE is taken for the letter's")
        XCTAssertFalse(answer("Success", ["* 68 EXISTS"], uid: 344).showsMove, "an EXISTS is not")
    }

    /// A COPYUID is read for the letter named: one for another letter, or
    /// with fewer UIDs in the destination than the source, or that cannot
    /// be read, names nothing; a range holds every UID in it, either way
    /// round, and a 0 anywhere among the destinations is a 0. A COPYUID on
    /// an untagged NO is not one.
    func testACopyUIDIsReadForTheLetterItNames() {
        func copyUID(_ code: String, _ uid: UInt32 = 343) -> IMAPMoveAnswer.CopyUID {
            answer("[\(code)] (Success)", uid: uid).copyUID
        }
        XCTAssertEqual(copyUID("COPYUID 2 343 290"), .names)
        XCTAssertEqual(copyUID("copyuid 2 343 290"), .names)
        XCTAssertEqual(copyUID("COPYUID 2 344 288"), .other)
        XCTAssertEqual(copyUID("COPYUID 2 340:345 1200:1205"), .names)
        XCTAssertEqual(copyUID("COPYUID 2 345:340 1205:1200"), .names)
        XCTAssertEqual(copyUID("COPYUID 2 340,343 1200,1201"), .names)
        XCTAssertEqual(copyUID("COPYUID 2 340:345 1200:1204"), .other)
        XCTAssertEqual(copyUID("COPYUID 2 340:345 0:5"), .zero)
        XCTAssertEqual(copyUID("COPYUID 2 340,343 1200,0"), .zero)
        XCTAssertEqual(copyUID("COPYUID 2 343"), .other)
        XCTAssertEqual(copyUID("COPYUID 2 * 290"), .other)
        XCTAssertEqual(copyUID("COPYUID 2 343 290 291"), .other)
        XCTAssertEqual(copyUID("COPYUID x 343 290"), .other)
        XCTAssertEqual(copyUID("COPYUID 2 343: 290"), .other)
        XCTAssertEqual(copyUID("COPYUID 2 99999999999 290"), .other)
        XCTAssertEqual(copyUID("APPENDUID 2 343"), .none)
        XCTAssertEqual(answer("Success", ["* NO [COPYUID 2 343 290] (Failure)"], uid: 343).copyUID,
                       .none)
        XCTAssertEqual(answer("[COPYUID 2 343 0] (Success)",
                              ["* OK [COPYUID 2 343 290] (Success)"], uid: 343).copyUID,
                       .names, "of two, the one naming the letter")
    }

    /// A COPY takes nothing out, so its answer is read for its COPYUID
    /// alone: one naming the letter, or none at all from a server that
    /// gives none, has nothing against it; a 0, or another letter's, has.
    func testACopysAnswerIsReadForItsCopyUIDAlone() {
        XCTAssertTrue(answer("[COPYUID 2 343 290] (Success)", uid: 343).showsCopy)
        XCTAssertTrue(answer("Success", uid: 343).showsCopy)
        XCTAssertFalse(answer("[COPYUID 2 343 0] (Success)", uid: 343).showsCopy)
        XCTAssertFalse(answer("[COPYUID 2 344 290] (Success)", uid: 343).showsCopy)
    }

    // MARK: - Once: the MOVE sent again lands

    /// The iPad's answer, with the letter still in the Inbox: the Inbox is
    /// asked, a NOOP and `UID SEARCH UID n`, in the same hold, and the same
    /// MOVE goes once more, never a COPY. Its answer shows the move: done,
    /// one copy in the Trash, none in the Inbox, and the kept copy lets the
    /// letter go. The log names it.
    func testAHollowMoveWithTheLetterStillThereIsSentOnceMoreAndLands() async throws {
        let (repository, rows) = try await listed()
        let row = rows[4]
        let id = messageID(of: row)
        server.hollowMoves = [.nothingMoved]

        try await finishing { try await repository.delete(row) }

        XCTAssertEqual(server.log.map(\.command), [moveToTrash(row), "NOOP", search(row), moveToTrash(row)])
        XCTAssertEqual(Set(server.log.map(\.connection)), [1])
        XCTAssertEqual(copies(of: id, in: Server.inbox), 0)
        XCTAssertEqual(copies(of: id, in: Server.trash), 1)
        XCTAssertEqual(kept(row), false)
        let n = uid(row.id)
        XCTAssertEqual(moveNotes, [
            "MOVE-HOLLOW folder=INBOX uid=\(n) copyuid=dest-0 no-expunge",
            "MOVE-CHECKED folder=INBOX uid=\(n) there sending-again",
            "MOVE-CHECKED folder=INBOX uid=\(n) moved",
        ])
    }

    /// A Move to a folder from the reading pane goes the same way: the row
    /// off at the tap, the MOVE sent once more, and the row stays off.
    func testAHollowMoveFromThePaneIsSentOnceMoreAndTheRowStaysOff() async throws {
        let (repository, rows) = try await listed()
        let row = rows[20]
        let id = messageID(of: row)
        let list = await makeList(rows)
        let sent = Mailbox(id: Server.sent, name: "Sent Mail", unreadCount: 0, role: .sent)
        server.hollowMoves = [.nothingMoved]

        let refusal = try await finishing {
            await PaneActions.refusal(running: .move(to: sent), on: row, inFolderWithRole: .inbox,
                                      list: list, repository: repository, requestSweep: {})
        }

        XCTAssertNil(refusal)
        XCTAssertEqual(server.log.map(\.verb), ["UID MOVE", "NOOP", "UID SEARCH", "UID MOVE"])
        let shown = await list.shown.map(\.id)
        XCTAssertEqual(shown, rows.map(\.id).filter { $0 != row.id })
        XCTAssertEqual(copies(of: id, in: Server.inbox), 0)
        XCTAssertEqual(copies(of: id, in: Server.sent), 1)
        XCTAssertEqual(kept(row), false)
    }

    // MARK: - Twice: refused, the row back

    /// Answered so twice, with the letter still there after each: refused,
    /// "Can't connect to mail server.", the row back on the list where it
    /// stood, the kept copy keeping it, and the letter in the Inbox,
    /// unmarked and not in the Trash. Two MOVEs and two questions, and no
    /// COPY, STORE or EXPUNGE: nothing he did not ask for is taken out.
    func testAMoveHollowTwiceWithTheLetterStillThereIsRefusedAndTheRowComesBack() async throws {
        let (repository, rows) = try await listed()
        let row = rows[4]
        let id = messageID(of: row)
        let list = await makeList(rows)
        server.hollowMoves = [.nothingMoved, .nothingMoved]

        let refusal = try await finishing {
            await PaneActions.refusal(running: .delete, on: row, inFolderWithRole: .inbox,
                                      list: list, repository: repository, requestSweep: {})
        }

        XCTAssertEqual(refusal, .cannotConnect)
        XCTAssertEqual(MailAlert.reaching(try XCTUnwrap(refusal)).message, "Can't connect to mail server.")
        XCTAssertEqual(server.log.map(\.command), [moveToTrash(row), "NOOP", search(row),
                                                   moveToTrash(row), "NOOP", search(row)])
        let shown = await list.shown.map(\.id)
        XCTAssertEqual(shown, rows.map(\.id))
        XCTAssertEqual(kept(row), true)
        XCTAssertEqual(copies(of: id, in: Server.inbox), 1)
        XCTAssertEqual(copies(of: id, in: Server.trash), 0)
        XCTAssertFalse(server.flags(uid: uid(row.id), in: Server.inbox).contains("\\Deleted"))
        let n = uid(row.id)
        XCTAssertEqual(moveNotes, [
            "MOVE-HOLLOW folder=INBOX uid=\(n) copyuid=dest-0 no-expunge",
            "MOVE-CHECKED folder=INBOX uid=\(n) there sending-again",
            "MOVE-HOLLOW folder=INBOX uid=\(n) copyuid=dest-0 no-expunge",
            "MOVE-CHECKED folder=INBOX uid=\(n) there not-moved",
        ])
    }

    /// The second MOVE refused: no COPY in its place, which would be a
    /// second letter in the Trash wherever the first did land. Refused, the
    /// letter where it was.
    func testASecondMoveRefusedIsNotFollowedByACopy() async throws {
        let (repository, rows) = try await listed()
        let row = rows[4]
        let id = messageID(of: row)
        server.hollowMoves = [.nothingMoved]
        let server = self.server!
        server.change(after: { $0.verb == "UID MOVE" }) { server.refusedVerbs = ["UID MOVE", "UID COPY"] }

        do {
            try await finishing { try await repository.delete(row) }
            XCTFail("taken for moved")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }

        XCTAssertEqual(server.log.map(\.command), [moveToTrash(row), "NOOP", search(row), moveToTrash(row)])
        XCTAssertEqual(server.log.last?.status, "NO")
        XCTAssertEqual(copies(of: id, in: Server.inbox), 1)
        XCTAssertEqual(copies(of: id, in: Server.trash), 0)
        XCTAssertEqual(kept(row), true)
        XCTAssertEqual(moveNotes.last, "MOVE-CHECKED folder=INBOX uid=\(uid(row.id)) refused not-moved")
    }

    /// The question unanswered, its SEARCH refused: nothing is sent again,
    /// and the move is refused, since nothing says it went.
    func testAHollowMoveWhoseQuestionIsRefusedIsRefused() async throws {
        let (repository, rows) = try await listed()
        let row = rows[4]
        server.hollowMoves = [.nothingMoved]
        let server = self.server!
        server.change(after: { $0.verb == "UID MOVE" }) { server.refusedVerbs = ["UID SEARCH"] }

        do {
            try await finishing { try await repository.delete(row) }
            XCTFail("taken for moved")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }

        XCTAssertEqual(server.log.map(\.command), [moveToTrash(row), "NOOP", search(row)])
        XCTAssertEqual(kept(row), true)
        XCTAssertEqual(moveNotes.last, "MOVE-CHECKED folder=INBOX uid=\(uid(row.id)) unanswered not-moved")
    }

    // MARK: - The letter did go

    /// The same answer with the letter moved all the same, the connection not
    /// told: the NOOP brings the EXPUNGE, the SEARCH finds nothing, and the
    /// move is done with nothing sent again. One copy in the Trash.
    func testAHollowMoveWhoseLetterDidGoIsDoneWithNothingSentAgain() async throws {
        let (repository, rows) = try await listed()
        let row = rows[4]
        let id = messageID(of: row)
        server.hollowMoves = [.movedUntold]

        try await finishing { try await repository.delete(row) }

        XCTAssertEqual(server.log.map(\.command), [moveToTrash(row), "NOOP", search(row)])
        XCTAssertEqual(copies(of: id, in: Server.inbox), 0)
        XCTAssertEqual(copies(of: id, in: Server.trash), 1)
        XCTAssertEqual(kept(row), false)
        let n = uid(row.id)
        XCTAssertEqual(moveNotes, [
            "MOVE-HOLLOW folder=INBOX uid=\(n) copyuid=dest-0 no-expunge",
            "MOVE-CHECKED folder=INBOX uid=\(n) gone",
        ])
    }

    /// Answered hollow twice, the second time with the letter moved: the
    /// second question finds it gone, and the move is done, one copy in
    /// the Trash, the row off.
    func testASecondHollowMoveWhoseLetterDidGoIsDone() async throws {
        let (repository, rows) = try await listed()
        let row = rows[4]
        let id = messageID(of: row)
        server.hollowMoves = [.nothingMoved, .movedUntold]

        try await finishing { try await repository.delete(row) }

        XCTAssertEqual(server.log.map(\.command), [moveToTrash(row), "NOOP", search(row),
                                                   moveToTrash(row), "NOOP", search(row)])
        XCTAssertEqual(copies(of: id, in: Server.inbox), 0)
        XCTAssertEqual(copies(of: id, in: Server.trash), 1)
        XCTAssertEqual(kept(row), false)
        XCTAssertEqual(moveNotes.last, "MOVE-CHECKED folder=INBOX uid=\(uid(row.id)) gone")
    }

    // MARK: - A normal OK, as before

    /// A MOVE whose answer shows it, to the Trash or to a folder, from the
    /// Inbox or from All Mail, is its one command, as before, and the log
    /// says nothing of it.
    func testANormalMoveIsItsOneCommandAndNothingIsNoted() async throws {
        let (repository, rows) = try await listed()
        try await finishing { try await repository.delete(rows[3]) }
        try await finishing { try await repository.move(rows[5], to: Server.sent) }
        XCTAssertEqual(server.log.map(\.command), [moveToTrash(rows[3]),
                                                   "UID MOVE \(uid(rows[5].id)) \"\(Server.sent)\""])

        let row = try await archivedRow(by: repository)
        server.clearLog()
        try await finishing { try await repository.move(row, to: Server.inbox) }
        XCTAssertEqual(server.log.map(\.verb), ["UID MOVE"])
        XCTAssertEqual(copies(of: "<archived@example.com>", in: Server.inbox), 1)
        XCTAssertEqual(moveNotes, [])
    }

    /// A letter in All Mail and nowhere else, listed there.
    private func archivedRow(by repository: IMAPMailRepository) async throws -> MessageSummary {
        server.deliver(Server.Letter(from: Server.jane, to: [Server.owner], subject: "Archived",
                                     date: Server.newestDate.addingTimeInterval(60),
                                     text: "Filed without reading.\r\n",
                                     messageID: "<archived@example.com>"),
                       to: [Server.allMail])
        _ = try await repository.folders()
        let rows = try await repository.listMessages(in: Server.allMail, beforeUID: nil, limit: 50)
        return try XCTUnwrap(rows.first { $0.subject == "Archived" })
    }

    /// Filed from All Mail in a label, the letter stays in All Mail, so a
    /// hollow answer cannot be looked into there: it is noted and taken as
    /// before, one command, and the row stays on the list either way.
    func testAHollowMoveOutOfAllMailIsNotedAndNotLookedFor() async throws {
        let repository = makeRepository()
        let row = try await archivedRow(by: repository)
        server.clearLog()
        Diagnostics.clear()
        server.hollowMoves = [.nothingMoved]

        try await finishing { try await repository.move(row, to: Server.inbox) }

        XCTAssertEqual(server.log.map(\.verb), ["UID MOVE"])
        let n = uid(row.id)
        XCTAssertEqual(moveNotes, [
            "MOVE-HOLLOW folder=\(Server.allMail) uid=\(n) copyuid=dest-0 no-expunge",
            "MOVE-CHECKED folder=\(Server.allMail) uid=\(n) stays-in-folder not-asked",
        ])
    }

    /// Delete inside the Trash is no MOVE: `\Deleted` and a UID EXPUNGE of
    /// the letter, as before, and a hollow MOVE waiting is not met.
    func testDeleteInsideTheTrashIsNoMoveAndIsAsBefore() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        try await repository.delete(rows[2])
        _ = try await repository.folders()
        let binned = try await repository.listMessages(in: Server.trash, beforeUID: nil, limit: 50)
        let row = try XCTUnwrap(binned.first)
        server.clearLog()
        server.hollowMoves = [.nothingMoved]

        try await finishing { try await repository.delete(row) }

        XCTAssertEqual(server.log.map(\.command), [
            "UID STORE \(uid(row.id)) +FLAGS.SILENT (\\Deleted)", "UID EXPUNGE \(uid(row.id))",
        ])
        XCTAssertEqual(server.hollowMoves, [.nothingMoved])
    }

    // MARK: - A server without MOVE

    /// Without MOVE, the COPY, `\Deleted` and the UID EXPUNGE, as before,
    /// when the COPY's answer names the letter.
    func testWithoutMoveTheCopyMarkAndExpungeGoAsBefore() async throws {
        server.withheldCapabilities = ["MOVE"]
        let (repository, rows) = try await listed()
        let row = rows[4]
        let id = messageID(of: row)

        try await finishing { try await repository.delete(row) }

        let n = uid(row.id)
        XCTAssertEqual(server.log.map(\.command), [
            "UID COPY \(n) \"\(Server.trash)\"", "UID STORE \(n) +FLAGS.SILENT (\\Deleted)",
            "UID EXPUNGE \(n)",
        ])
        XCTAssertEqual(copies(of: id, in: Server.inbox), 0)
        XCTAssertEqual(copies(of: id, in: Server.trash), 1)
        XCTAssertEqual(moveNotes, [])
    }

    /// A COPY answered as the MOVE was, with 0 for the letter's UID in the
    /// Trash: nothing is marked or expunged, which would leave it nowhere,
    /// and the COPY is not sent again, which would be a second copy where
    /// the first did land. Refused, the letter in the Inbox, unmarked, and
    /// the kept copy keeping it.
    func testWithoutMoveAHollowCopyMarksNothingAndIsRefused() async throws {
        server.withheldCapabilities = ["MOVE"]
        let (repository, rows) = try await listed()
        let row = rows[4]
        let id = messageID(of: row)
        server.hollowCopies = 1

        do {
            try await finishing { try await repository.delete(row) }
            XCTFail("taken for moved")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }

        let n = uid(row.id)
        XCTAssertEqual(server.log.map(\.command), ["UID COPY \(n) \"\(Server.trash)\""])
        XCTAssertEqual(copies(of: id, in: Server.inbox), 1)
        XCTAssertEqual(copies(of: id, in: Server.trash), 0)
        XCTAssertFalse(server.flags(uid: n, in: Server.inbox).contains("\\Deleted"))
        XCTAssertEqual(kept(row), true)
        XCTAssertEqual(moveNotes, [
            "MOVE-HOLLOW folder=INBOX uid=\(n) UID COPY copyuid=dest-0",
            "MOVE-CHECKED folder=INBOX uid=\(n) nothing-marked not-moved",
        ])
    }

    // MARK: - Edit mode's several moves

    /// Three rows ticked and deleted, as on the iPad, the second sent
    /// answered hollow with the letter still there. It goes once more and
    /// lands; the other two are their one MOVE each; every row stays off,
    /// each letter once in the Trash, and none on the kept Inbox.
    func testEditModesDeleteWithOneHollowMoveAmongThemTakesEveryLetter() async throws {
        let (repository, rows) = try await listed()
        let chosen = await ListBatch.letters(ticked: [0, 1, 2], in: rows.map { MessageThread(messages: [$0]) })
        let ids = chosen.map(messageID(of:))
        let list = await makeList(rows)
        let server = self.server!
        server.change(after: { $0.verb == "UID MOVE" }) { server.hollowMoves = [.nothingMoved] }

        let folders = self.folders
        let outcome = try await finishing {
            await ListBatch.run(.delete, on: chosen, role: { folders.role(of: $0) }, list: list,
                                repository: repository, requestSweep: {})
        }

        XCTAssertEqual(outcome, ListBatch.Outcome(taken: chosen.map(\.id), notTaken: [], refusal: nil))
        XCTAssertEqual(server.log.map(\.command), [
            moveToTrash(chosen[0]),
            moveToTrash(chosen[1]), "NOOP", search(chosen[1]), moveToTrash(chosen[1]),
            moveToTrash(chosen[2]),
        ])
        let shown = await list.shown.map(\.id)
        XCTAssertEqual(shown, Array(rows.dropFirst(3)).map(\.id))
        for id in ids {
            XCTAssertEqual(copies(of: id, in: Server.inbox), 0)
            XCTAssertEqual(copies(of: id, in: Server.trash), 1)
        }
        for letter in chosen { XCTAssertEqual(kept(letter), false) }
    }

    /// The first sent answered hollow twice, the iPad's first answered so
    /// once: it is refused, its row back where it stood, and, by Edit
    /// mode's rule that the first refusal stops the rest, the other two are
    /// not sent and are back too. The alert is the refusal; every letter
    /// is in the Inbox still, and on the kept Inbox.
    func testEditModesDeleteWithAMoveHollowTwiceIsRefusedAndTheRowsComeBack() async throws {
        let (repository, rows) = try await listed()
        let chosen = await ListBatch.letters(ticked: [0, 1, 2], in: rows.map { MessageThread(messages: [$0]) })
        let ids = chosen.map(messageID(of:))
        let list = await makeList(rows)
        server.hollowMoves = [.nothingMoved, .nothingMoved]

        let folders = self.folders
        let outcome = try await finishing {
            await ListBatch.run(.delete, on: chosen, role: { folders.role(of: $0) }, list: list,
                                repository: repository, requestSweep: {})
        }

        XCTAssertEqual(outcome, ListBatch.Outcome(taken: [], notTaken: chosen.map(\.id),
                                                  refusal: .cannotConnect))
        XCTAssertEqual(server.log.map(\.command), [
            moveToTrash(chosen[0]), "NOOP", search(chosen[0]),
            moveToTrash(chosen[0]), "NOOP", search(chosen[0]),
        ])
        let shown = await list.shown.map(\.id)
        XCTAssertEqual(shown, rows.map(\.id))
        for id in ids {
            XCTAssertEqual(copies(of: id, in: Server.inbox), 1)
            XCTAssertEqual(copies(of: id, in: Server.trash), 0)
        }
        for letter in chosen { XCTAssertEqual(kept(letter), true) }
    }
}
