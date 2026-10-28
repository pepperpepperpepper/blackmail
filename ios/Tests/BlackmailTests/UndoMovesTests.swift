import XCTest
@testable import Blackmail

/// Mail's Undo of a Trash or a Move (B-157): where the MOVE's answer says
/// the letter went, what is a step of Undo and what is not, the letter moved
/// back by the one write a move is, made sure of first, and its row back on
/// the list where it stood, the counts with it. Over `ScriptedIMAPServer`
/// through the shipping repository, with the list's own letters,
/// `ListLetters`, as `ListBatchTests` runs Edit mode's batch. What the
/// screens do with it, the undo manager, the first responder and the
/// alert's words, is read from their source at the foot.
final class UndoMovesTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "UndoMovesTests"

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

    private func uid(_ id: String) -> UInt32 { UInt32(id.split(separator: "/").last ?? "")! }

    /// `XCTUnwrap` of what an `await` gave, which its autoclosure cannot.
    private func unwrapped<T>(_ value: T?, file: StaticString = #filePath,
                              line: UInt = #line) throws -> T {
        try XCTUnwrap(value, file: file, line: line)
    }

    private let folders = [
        Mailbox(id: "inbox", name: "Inbox", unreadCount: 0, role: .inbox),
        Mailbox(id: Server.inbox, name: "INBOX", unreadCount: 0, role: .inbox),
        Mailbox(id: Server.allMail, name: "All Mail", unreadCount: 0, role: .archive),
        Mailbox(id: Server.trash, name: "Trash", unreadCount: 0, role: .trash),
        Mailbox(id: Server.spam, name: "Spam", unreadCount: 0, role: .junk),
        Mailbox(id: Server.sent, name: "Sent Mail", unreadCount: 0, role: .sent),
        Mailbox(id: Server.drafts, name: "Drafts", unreadCount: 0, role: .drafts),
    ]

    /// The list's letters as `MessageListViewController` holds them.
    @MainActor
    private func makeList(folder: [MessageSummary],
                          results: [MessageSummary]? = nil) -> (ListLetters, Counts) {
        let list = ListLetters()
        let counts = Counts()
        list.onUnreadCountChanged = { counts.record($0, $1) }
        _ = list.fetchedAfresh(folder)
        if let results { list.showResults(results) }
        return (list, counts)
    }

    /// Edit mode's batch, or a drag's, as the list runs it, and the step of
    /// Undo it makes (`MessageListViewController.runBatch`).
    @MainActor
    private func remove(_ action: PaneAction, _ chosen: [MessageSummary], list: ListLetters,
                        repository: IMAPMailRepository) async -> (ListBatch.Outcome, UndoableMove?) {
        let folders = self.folders
        var landings: [String: MoveLanding] = [:]
        let outcome = await ListBatch.run(action, on: chosen, role: { folders.role(of: $0) },
                                          list: list, repository: repository,
                                          requestSweep: {},
                                          landed: { landings[$0.id] = $1 })
        let took = chosen.filter { outcome.taken.contains($0.id) }
        return (outcome, UndoableMove.after(action, took: took, landings: landings,
                                            role: { folders.role(of: $0) }))
    }

    // MARK: - Where the answer says the letter went

    private func landing(_ detail: String, _ untagged: [String] = [],
                         uid: UInt32) -> IMAPMoveLanding? {
        IMAPMoveAnswer.landing(in: IMAPCommandResult(
            status: .ok, detail: detail,
            untagged: untagged.map { IMAPResponseLine(text: $0, literals: []) }), uid: uid)
    }

    /// The COPYUID that names the letter gives the destination's
    /// UIDVALIDITY and the letter's UID there, at its place in the source
    /// set, on the tagged OK as Gmail puts it or an untagged one as RFC 6851
    /// has it; any other answer gives none: no COPYUID, a 0 as Gmail's on
    /// the iPad (B-092), another letter's, or one that cannot be read.
    func testTheMovesAnswerSaysWhereTheLetterWent() {
        XCTAssertEqual(landing("[COPYUID 2 344 288] (Success)", ["* 68 EXPUNGE"], uid: 344),
                       IMAPMoveLanding(validity: 2, uid: 288))
        XCTAssertEqual(landing("Done", ["* OK [COPYUID 432432 42 1202] (Success)", "* 22 EXPUNGE"],
                               uid: 42),
                       IMAPMoveLanding(validity: 432432, uid: 1202))
        XCTAssertEqual(landing("[COPYUID 7 340:345 1200:1205] (Success)", uid: 343),
                       IMAPMoveLanding(validity: 7, uid: 1203))
        XCTAssertEqual(landing("[COPYUID 7 340,343,350:351 20:21,30:31] (Success)", uid: 350),
                       IMAPMoveLanding(validity: 7, uid: 30))
        XCTAssertEqual(landing("[COPYUID 7 340,343 1200,1201] (Success)", uid: 343),
                       IMAPMoveLanding(validity: 7, uid: 1201))
        XCTAssertNil(landing("[COPYUID 2 343 0] (Success)", uid: 343), "Gmail's 0 on the iPad")
        XCTAssertNil(landing("Success", ["* 68 EXPUNGE"], uid: 343), "no COPYUID")
        XCTAssertNil(landing("[COPYUID 2 344 288] (Success)", uid: 343), "another letter's")
        XCTAssertNil(landing("[COPYUID 2 340:345 1200:1204] (Success)", uid: 343), "a short set")
        XCTAssertNil(landing("[COPYUID x 343 290] (Success)", uid: 343))
    }

    // MARK: - The letter moved back

    /// A Delete says where the letter went, the Trash and its UID there from
    /// the MOVE's COPYUID, and its Gmail id; its Undo asks that UID for its
    /// Gmail id and then sends the one write, a MOVE back to the Inbox, and
    /// nothing else: no STORE, no APPEND, no COPY. The letter is in the Inbox
    /// again under a new UID, the one its answer names, and not in the Trash.
    func testADeleteSaysWhereTheLetterWentAndItsUndoMovesItBack() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = rows[2]
        let gmail = try XCTUnwrap(letter.gmailMessageID)
        let landing = try unwrapped(await repository.deleteLanding(letter.id, gmailMessageID: gmail,
                                                                   from: letter.mailboxID))
        let inTrash = try XCTUnwrap(server.uids(in: Server.trash).first {
            server.gmailMessageID(uid: $0, in: Server.trash) == gmail
        })
        XCTAssertEqual(landing, MoveLanding(
            folder: Server.trash, id: "\(server.uidValidity(of: Server.trash))/\(inTrash)",
            letter: gmail))
        XCTAssertFalse(server.uids(in: Server.inbox).contains(uid(letter.id)))
        server.clearLog()

        let back = try unwrapped(await repository.moveBack(landing, to: letter.mailboxID))

        XCTAssertEqual(server.log.filter(\.isUIDCommand).map(\.command), [
            "UID FETCH \(inTrash) (UID X-GM-MSGID)",
            "UID MOVE \(inTrash) \"\(Server.inbox)\"",
        ])
        XCTAssertFalse(server.log.contains { ["APPEND", "UID STORE", "UID COPY", "UID EXPUNGE",
                                             "STORE", "EXPUNGE"].contains($0.verb) })
        let now = uid(back)
        XCTAssertEqual(back, "\(server.uidValidity(of: Server.inbox))/\(now)")
        XCTAssertEqual(server.gmailMessageID(uid: now, in: Server.inbox), gmail)
        XCTAssertGreaterThan(now, uid(rows[0].id), "a new UID, after every other in the Inbox")
        XCTAssertFalse(server.uids(in: Server.trash).contains(inTrash))
    }

    /// With no UID from the answer, the letter is found in the Trash by its
    /// Gmail id, `UID SEARCH X-GM-MSGID`, and moved back from there; and so
    /// when the UID it was given holds another letter now, or the Trash has
    /// been renumbered since.
    func testWithNoUIDTheUndoFindsTheLetterByItsGmailID() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        var landings: [MoveLanding] = []
        for letter in [rows[1], rows[3], rows[5]] {
            landings.append(try unwrapped(await repository.deleteLanding(
                letter.id, gmailMessageID: letter.gmailMessageID, from: letter.mailboxID)))
        }
        let unnamed = MoveLanding(folder: landings[0].folder, id: nil, letter: landings[0].letter)
        let elsewhere = MoveLanding(folder: landings[1].folder, id: landings[2].id,
                                    letter: landings[1].letter)
        for (landing, letter) in [(unnamed, rows[1]), (elsewhere, rows[3])] {
            server.clearLog()
            let back = try unwrapped(await repository.moveBack(landing, to: "inbox"))
            let verbs = server.log.filter(\.isUIDCommand).map(\.verb)
            XCTAssertEqual(verbs.filter { $0 != "UID FETCH" }, ["UID SEARCH", "UID MOVE"])
            XCTAssertTrue(server.log.contains { $0.command.hasPrefix("UID SEARCH X-GM-MSGID ") })
            XCTAssertEqual(server.gmailMessageID(uid: uid(back), in: Server.inbox),
                           letter.gmailMessageID)
        }

        let renumbered = try XCTUnwrap(landings[2].id)
        server.renumber(Server.trash, validity: 99, firstUID: 500)
        server.clearLog()
        let back = try unwrapped(await repository.moveBack(landings[2], to: "inbox"))
        XCTAssertNotEqual(renumbered.split(separator: "/").first, "99")
        XCTAssertEqual(server.log.filter(\.isUIDCommand).map(\.verb).filter { $0 != "UID FETCH" },
                       ["UID SEARCH", "UID MOVE"])
        XCTAssertEqual(server.gmailMessageID(uid: uid(back), in: Server.inbox),
                       rows[5].gmailMessageID)
    }

    /// A letter no longer where it went, taken out of the Trash by another
    /// mail program or by Gmail since, is not moved back and nothing is
    /// written: Gmail answers a MOVE of a UID the folder does not hold with
    /// OK and nothing moved (B-039), which B-092's look in the source would
    /// take for a move done. Nor is a letter with no Gmail id, which cannot
    /// be made sure of.
    func testALetterNoLongerWhereItWentIsLeftAndNothingIsWritten() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let landing = try unwrapped(await repository.deleteLanding(
            rows[4].id, gmailMessageID: rows[4].gmailMessageID, from: rows[4].mailboxID))
        server.removeElsewhere(uid: uid(try XCTUnwrap(landing.id)), from: Server.trash)
        server.clearLog()

        do {
            _ = try await repository.moveBack(landing, to: "inbox")
            XCTFail("moved back a letter that has gone")
        } catch {
            XCTAssertTrue(error is MoveLanding.Gone, "\(error)")
        }
        XCTAssertFalse(server.log.contains { $0.verb == "UID MOVE" || $0.verb == "UID COPY" })

        server.clearLog()
        do {
            _ = try await repository.moveBack(MoveLanding(folder: Server.trash, id: landing.id,
                                                          letter: nil), to: "inbox")
            XCTFail("moved back a letter it could not make sure of")
        } catch {
            XCTAssertTrue(error is MoveLanding.Gone, "\(error)")
        }
        XCTAssertEqual(server.log.filter(\.isUIDCommand).count, 0)
    }

    /// Found twice in the Trash by its Gmail id, with no UID from the
    /// answer to go by, the letter is not moved back: which of the two to
    /// move cannot be told, and nothing is written.
    func testALetterFoundTwiceIsLeftAndNothingIsWritten() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let landing = try unwrapped(await repository.deleteLanding(
            rows[2].id, gmailMessageID: rows[2].gmailMessageID, from: rows[2].mailboxID))
        let again = try XCTUnwrap(server.fileAgain(uid: uid(try XCTUnwrap(landing.id)),
                                                   in: Server.trash))
        XCTAssertEqual(server.gmailMessageID(uid: again, in: Server.trash), landing.letter)
        server.clearLog()

        do {
            _ = try await repository.moveBack(MoveLanding(folder: landing.folder, id: nil,
                                                          letter: landing.letter), to: "inbox")
            XCTFail("moved back a letter found twice")
        } catch {
            XCTAssertTrue(error is MoveLanding.Gone, "\(error)")
        }
        XCTAssertTrue(server.log.contains { $0.command.hasPrefix("UID SEARCH X-GM-MSGID ") })
        XCTAssertFalse(server.log.contains { $0.verb == "UID MOVE" || $0.verb == "UID COPY" })
    }

    /// A Delete inside Trash erases, and says nowhere: nothing brings it
    /// back. A Move says where, as a Delete does.
    func testAnEraseSaysNowhereAndAMoveSaysWhere() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let binned = try unwrapped(await repository.deleteLanding(
            rows[0].id, gmailMessageID: rows[0].gmailMessageID, from: rows[0].mailboxID))
        let erased = try await repository.deleteLanding(
            try XCTUnwrap(binned.id), gmailMessageID: rows[0].gmailMessageID, from: Server.trash)
        XCTAssertNil(erased)

        let moved = try unwrapped(await repository.moveLanding(
            rows[1].id, gmailMessageID: rows[1].gmailMessageID, from: rows[1].mailboxID,
            to: Server.spam))
        XCTAssertEqual(moved.folder, Server.spam)
        XCTAssertEqual(server.gmailMessageID(uid: uid(try XCTUnwrap(moved.id)), in: Server.spam),
                       rows[1].gmailMessageID)
    }

    // MARK: - What is a step of Undo

    /// A Delete is "Undo Trash", a Move "Undo Move", the letters the server
    /// took in the order they went; nothing for a Flag or a read mark, a
    /// letter erased (no landing), one of Drafts, one kept on the iPad, a
    /// Move that leaves the row, from All Mail into a folder, or a letter
    /// with no Gmail id; and nothing at all when none is left.
    func testWhatIsAStepOfUndoAndWhatIsNot() {
        let folders = self.folders
        let role: (String) -> Mailbox.Role? = { folders.role(of: $0) }
        func row(_ id: String, in folder: String = Server.inbox, gmail: UInt64? = 7) -> MessageSummary {
            MessageSummary(id: id, mailboxID: folder, sender: "Sam", subject: "Hello",
                           preview: "", date: Server.newestDate, isRead: true, isFlagged: false,
                           gmailMessageID: gmail)
        }
        func landed(_ row: MessageSummary) -> MoveLanding {
            MoveLanding(folder: Server.trash, id: "3/9\(row.id.count)", letter: row.gmailMessageID)
        }
        let inbox = [row("1/10"), row("1/11")]
        let landings = Dictionary(uniqueKeysWithValues: inbox.map { ($0.id, landed($0)) })

        let trash = UndoableMove.after(.delete, took: inbox, landings: landings, role: role)
        XCTAssertEqual(trash?.kind, .trash)
        XCTAssertEqual(trash?.actionName, "Trash")
        XCTAssertEqual(trash?.letters.map(\.row.id), ["1/10", "1/11"])
        let notes = Mailbox(id: "Notes", name: "Notes", unreadCount: 0, role: nil)
        let move = UndoableMove.after(.move(to: notes), took: inbox, landings: landings, role: role)
        XCTAssertEqual(move?.actionName, "Move")
        XCTAssertEqual(move?.kind, .move)

        XCTAssertNil(UndoableMove.after(.flag(true), took: inbox, landings: landings, role: role))
        XCTAssertNil(UndoableMove.after(.read(false), took: inbox, landings: landings, role: role))
        XCTAssertNil(UndoableMove.after(.delete, took: inbox, landings: [:], role: role),
                     "erased inside Trash: no landing")
        let draft = row("2/5", in: Server.drafts)
        XCTAssertNil(UndoableMove.after(.delete, took: [draft], landings: [draft.id: landed(draft)],
                                        role: role))
        let kept = row("local:abc", in: Server.drafts)
        XCTAssertNil(UndoableMove.after(.delete, took: [kept], landings: [kept.id: landed(kept)],
                                        role: { _ in .inbox }))
        let archived = row("4/8", in: Server.allMail)
        XCTAssertNil(UndoableMove.after(.move(to: notes), took: [archived],
                                        landings: [archived.id: landed(archived)], role: role),
                     "filed from All Mail, it stays there")
        XCTAssertEqual(UndoableMove.after(.delete, took: [archived],
                                          landings: [archived.id: landed(archived)],
                                          role: role)?.letters.count, 1)
        let nameless = row("1/12", gmail: nil)
        let mixed = UndoableMove.after(.delete, took: [nameless] + inbox,
                                       landings: landings.merging([nameless.id: landed(nameless)])
                                           { a, _ in a },
                                       role: role)
        XCTAssertEqual(mixed?.letters.map(\.row.id), ["1/10", "1/11"])
    }

    // MARK: - The rows come back

    /// Two letters of the Inbox deleted together, one of them unread, then
    /// undone: both are in the Inbox again, and their rows back where they
    /// stood, under their new ids, the list in the order it had, in one step
    /// called "Trash". The unread one's leaving took one off the Inbox and
    /// All Mail, and its coming back puts it on again, once, and the counts
    /// are swept; reading it again takes one off again.
    @MainActor
    func testTheUndoPutsTheRowsBackWhereTheyStoodAndTheCountsRight() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let (list, counts) = makeList(folder: rows)
        let unread = try XCTUnwrap(rows.firstIndex { !$0.isRead })
        let read = try XCTUnwrap(rows.indices.first { $0 > unread + 1 && rows[$0].isRead })
        let chosen = ListBatch.letters(ticked: [unread, read],
                                       in: rows.map { MessageThread(messages: [$0]) })
        let (outcome, made) = await remove(.delete, chosen, list: list, repository: repository)
        XCTAssertEqual(outcome.taken, chosen.map(\.id))
        let step = try XCTUnwrap(made)
        XCTAssertEqual(step.actionName, "Trash")
        XCTAssertEqual(step.letters.map(\.row.id), [rows[read].id, rows[unread].id],
                       "the oldest first, as sent")
        XCTAssertEqual(list.shown.count, rows.count - 2)
        XCTAssertEqual(counts.off, [[Server.inbox, Server.allMail]])
        let sweeps = Counter()
        server.clearLog()

        let undone = await UndoMoves.run(step, repository: repository, list: list,
                                         requestSweep: { sweeps.add() })

        XCTAssertEqual(undone.back, chosen.map(\.id))
        XCTAssertEqual(undone.unplaced, [])
        XCTAssertEqual(undone.gone, [])
        XCTAssertNil(undone.left)
        XCTAssertNil(undone.refusal)
        XCTAssertEqual(server.log.filter(\.isUIDCommand).map(\.verb),
                       ["UID FETCH", "UID MOVE", "UID FETCH", "UID MOVE"])
        XCTAssertEqual(list.shown.map(\.subject), rows.map(\.subject), "every row where it stood")
        XCTAssertEqual(list.shown.map(\.gmailMessageID), rows.map(\.gmailMessageID))
        for (i, row) in rows.enumerated() where chosen.contains(where: { $0.id == row.id }) {
            let now = list.shown[i]
            XCTAssertNotEqual(now.id, row.id, "under its new id")
            XCTAssertEqual(server.gmailMessageID(uid: uid(now.id), in: Server.inbox),
                           row.gmailMessageID)
            XCTAssertEqual(now.isRead, row.isRead)
        }
        XCTAssertEqual(counts.on, [[Server.inbox, Server.allMail]], "one back on, once")
        XCTAssertEqual(sweeps.value, 1)
        XCTAssertEqual(list.cursor, rows.last?.id, "paging goes on from where it had got to")

        let back = try XCTUnwrap(list.shown.first { $0.gmailMessageID == rows[unread].gmailMessageID })
        list.read(back)
        XCTAssertEqual(counts.off, [[Server.inbox, Server.allMail], [Server.inbox, Server.allMail]],
                       "read again, one off again")
    }

    /// The list at its top, its first row trashed and undone, a drag's or
    /// the pane's Delete: the row back first, in sight, the list still at
    /// its top, as Mail puts it back. Found on the test iPad, 2026-10-27:
    /// it came back one row above the top of the pane, out of sight, the
    /// row below it first, since the list held its place by the row's old
    /// id, which no row has once it is back under its new UID.
    @MainActor
    func testTheFirstRowUndoneAtTheTopComesBackInSight() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let (list, _) = makeList(folder: rows)
        let screen = ListOnScreen(list)
        XCTAssertEqual(screen.inView.first, rows[0].id)

        let (_, made) = await remove(.delete, [rows[0]], list: list, repository: repository)
        XCTAssertEqual(screen.inView.first, rows[1].id, "the rows below closed up")
        XCTAssertEqual(screen.offset, ListOnScreen.top)
        let undone = await UndoMoves.run(try XCTUnwrap(made), repository: repository, list: list,
                                         requestSweep: {})
        XCTAssertEqual(undone.unplaced, [])
        let back = try XCTUnwrap(list.shown.first)
        XCTAssertEqual(back.gmailMessageID, rows[0].gmailMessageID)
        XCTAssertNotEqual(back.id, rows[0].id, "under its new id")
        XCTAssertEqual(screen.offset, ListOnScreen.top, "the list at its top")
        XCTAssertEqual(screen.inView.prefix(2), [back.id, rows[1].id], "back first, in sight")
        XCTAssertEqual(screen.onPane[back.id], ListOnScreen.band + ListOnScreen.barTop)
    }

    /// The list at its top, its first row trashed; scrolled down, another
    /// row trashed there; back at the top, both undone, the last first: the
    /// first row back first, in sight, the list at its top. The place from
    /// before the first Trash was dropped at the second, so the first comes
    /// back by the list at its top (`TakenRows.move(for:here:atItsTop:)`),
    /// not by the row first in sight, which put it above the top of the
    /// pane, out of sight, as on the test iPad, 2026-10-27.
    @MainActor
    func testTheFirstRowUndoneAtTheTopAfterTheListHasChangedComesBackInSight() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let (list, _) = makeList(folder: rows)
        let screen = ListOnScreen(list)

        let (_, first) = await remove(.delete, [rows[0]], list: list, repository: repository)
        screen.scroll(to: 400)
        XCTAssertTrue(screen.inView.contains(rows[9].id))
        let (_, second) = await remove(.delete, [rows[9]], list: list, repository: repository)
        screen.scroll(to: ListOnScreen.top)
        XCTAssertEqual(screen.inView.first, rows[1].id)

        for made in [second, first] {
            let undone = await UndoMoves.run(try XCTUnwrap(made), repository: repository, list: list,
                                             requestSweep: {})
            XCTAssertEqual(undone.unplaced, [])
        }
        let back = try XCTUnwrap(list.shown.first)
        XCTAssertEqual(back.gmailMessageID, rows[0].gmailMessageID)
        XCTAssertEqual(screen.offset, ListOnScreen.top, "the list at its top")
        XCTAssertEqual(screen.inView.prefix(2), [back.id, rows[1].id], "back first, in sight")
    }

    /// Among a search's hits, a hit deleted and undone comes back where it
    /// stood among them. A list fetched afresh since the Delete no longer
    /// holds the row: the letter is moved back all the same, and is left to
    /// the next listing, where it is at the top of the Inbox (B-084).
    @MainActor
    func testAHitComesBackAmongTheHitsAndAListFetchedAfreshWaitsForTheNext() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let hits = [rows[6], rows[2], rows[9]]
        let (list, _) = makeList(folder: rows, results: hits)
        let (_, made) = await remove(.delete, [rows[2]], list: list, repository: repository)
        XCTAssertEqual(list.shown.map(\.id), [rows[6].id, rows[9].id])
        let undone = await UndoMoves.run(try XCTUnwrap(made), repository: repository, list: list,
                                         requestSweep: {})
        XCTAssertEqual(undone.unplaced, [])
        XCTAssertEqual(list.shown.map(\.subject), hits.map(\.subject))

        let (_, again) = await remove(.delete, [rows[7]], list: list, repository: repository)
        list.endSearch()
        let fresh = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        _ = list.fetchedAfresh(fresh)
        let late = await UndoMoves.run(try XCTUnwrap(again), repository: repository, list: list,
                                       requestSweep: {})
        XCTAssertEqual(late.back, [rows[7].id])
        XCTAssertEqual(late.unplaced, [rows[7].id])
        XCTAssertFalse(list.shown.contains { $0.gmailMessageID == rows[7].gmailMessageID })
        let next = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(next.first?.gmailMessageID, rows[7].gmailMessageID)
    }

    /// An Undo that fails, the connection gone at its MOVE, says so, puts
    /// back no row, leaves the letters in the Trash, and is one step of Undo
    /// again, the letter that failed first; a letter gone from the Trash
    /// meanwhile is passed over, nothing said of it, and the rest go back.
    @MainActor
    func testAFailedUndoSaysSoAndCanBeTriedAgain() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let (list, _) = makeList(folder: rows)
        let chosen = ListBatch.letters(ticked: [0, 4], in: rows.map { MessageThread(messages: [$0]) })
        let (_, made) = await remove(.delete, chosen, list: list, repository: repository)
        let step = try XCTUnwrap(made)
        server.hangsUpOnVerbs = ["UID MOVE"]

        let failed = await UndoMoves.run(step, repository: repository, list: list,
                                         requestSweep: {})
        XCTAssertEqual(failed.refusal, .cannotConnect)
        XCTAssertEqual(failed.left, step)
        XCTAssertEqual(failed.back, [])
        XCTAssertEqual(list.shown.count, rows.count - 2)
        for letter in step.letters {
            XCTAssertTrue(server.uids(in: Server.trash).contains {
                server.gmailMessageID(uid: $0, in: Server.trash) == letter.row.gmailMessageID
            })
        }

        server.hangsUpOnVerbs = []
        server.removeElsewhere(uid: uid(try XCTUnwrap(step.letters[0].landing.id)),
                               from: Server.trash)
        let again = await UndoMoves.run(try XCTUnwrap(failed.left), repository: repository,
                                        list: list, requestSweep: {})
        XCTAssertNil(again.refusal)
        XCTAssertNil(again.left)
        XCTAssertEqual(again.gone, [step.letters[0].row.id])
        XCTAssertEqual(again.back, [step.letters[1].row.id])
        XCTAssertEqual(list.shown.count, rows.count - 1)
    }

    /// The pane's Delete of a letter he has just opened, then its Undo. The
    /// pane was handed the row before the tap that opened it marked it
    /// read, so the pane's copy says unread; the list's copy at the tap,
    /// which took the row off, says read, and is what the step is made
    /// from (`PaneActions.refusal`'s `landed`). The row comes back read,
    /// nothing goes back on the counts, and reading it again bills
    /// nothing, as Gmail has it read. Made from the pane's copy, it came
    /// back with a dot, one back on its folders, and reading it took that
    /// one off a second time.
    @MainActor
    func testThePanesUndoPutsTheRowBackAsTheListHadIt() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let (list, counts) = makeList(folder: rows)
        let folders = self.folders
        let pane = try XCTUnwrap(rows.first { !$0.isRead })
        // The tap on its row, as `MessageListViewController.markReadIfNeeded`
        // and `sendRead` make it, after the pane has been handed the row.
        list.reading(pane, read: true)
        try await repository.setRead(true, id: pane.id, gmailMessageID: pane.gmailMessageID,
                                     mailboxID: pane.mailboxID)
        list.readAnswered(pane.id, landed: true)
        var read = pane
        read.isRead = true
        list.read(read)
        XCTAssertEqual(list.letter(pane.id)?.isRead, true)
        XCTAssertEqual(counts.off.count, 1)

        var made: UndoableMove?
        let refused = await PaneActions.refusal(
            running: .delete, on: pane, inFolderWithRole: .inbox, list: list,
            repository: repository, requestSweep: {},
            landed: { landing, before in
                // As the container makes the step (`RootViewController`).
                guard let landing else { return }
                made = UndoableMove.after(.delete, took: [before],
                                          landings: [before.id: landing],
                                          role: { folders.role(of: $0) })
            })
        XCTAssertNil(refused)
        let step = try XCTUnwrap(made)
        XCTAssertEqual(step.letters.map(\.row.isRead), [true])

        let undone = await UndoMoves.run(step, repository: repository, list: list,
                                         requestSweep: {})
        XCTAssertEqual(undone.back, [pane.id])
        let back = try XCTUnwrap(list.shown.first { $0.gmailMessageID == pane.gmailMessageID })
        XCTAssertNotEqual(back.id, pane.id)
        XCTAssertTrue(back.isRead, "no dot on a letter Gmail has read")
        XCTAssertEqual(counts.on, [], "nothing back on the counts")
        list.read(back)
        XCTAssertEqual(counts.off.count, 1, "read again, nothing billed")
    }

    // MARK: - Undo Flag

    /// A Flag or an Unflag is a step of its own, "Undo Flag" or "Undo
    /// Unflag", of the letters the server took it on; a Delete, a letter
    /// kept on the iPad and nothing taken are not, and a read mark is a
    /// step of another kind, "Undo Read" or "Undo Unread" (B-175).
    func testAFlagIsAStepOfUndoAndAReadMarkAStepOfItsOwn() throws {
        let row = MessageSummary(id: "1/10", mailboxID: Server.inbox, sender: "Sam",
                                 subject: "Hello", preview: "", date: Server.newestDate,
                                 isRead: true, isFlagged: false, gmailMessageID: 7)
        let flag = UndoableFlag.after(.flag(true), took: [row])
        XCTAssertEqual(flag, UndoableFlag(flagged: true, letters: [row]))
        XCTAssertEqual(flag?.actionName, "Flag")
        XCTAssertEqual(UndoableFlag.after(.flag(false), took: [row])?.actionName, "Unflag")
        XCTAssertNil(UndoableFlag.after(.read(true), took: [row]))
        XCTAssertNil(UndoableFlag.after(.read(false), took: [row]))
        XCTAssertNil(UndoableFlag.after(.delete, took: [row]))
        XCTAssertNil(UndoableFlag.after(.flag(true), took: []))
        let kept = MessageSummary(id: "local:abc", mailboxID: Server.drafts, sender: "Sam",
                                  subject: "Hello", preview: "", date: Server.newestDate,
                                  isRead: true, isFlagged: false)
        XCTAssertNil(UndoableFlag.after(.flag(true), took: [kept]))
        XCTAssertEqual(Undoable.flag(try XCTUnwrap(flag)).actionName, "Flag")
        let trash = UndoableMove(kind: .trash, letters: [])
        XCTAssertEqual(Undoable.move(trash).actionName, "Trash")
        XCTAssertEqual(UndoableRead.after(.read(false), took: [row])?.actionName, "Unread")
        XCTAssertEqual(UndoableRead.after(.read(true), took: [row])?.actionName, "Read")
        XCTAssertNil(UndoableRead.after(.flag(true), took: [row]))
    }

    /// A drag's Flag on two letters of a conversation, then its Undo: the
    /// flag off both again, at once on the rows, a STORE each and nothing
    /// else, and Gmail has them unflagged. An Undo that fails says so,
    /// puts the flags back as they were, and is a step again. One of them
    /// with a Flag on its way: nothing sent, the step left for the next
    /// shake.
    @MainActor
    func testAnUndoFlagSetsTheFlagBack() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let (list, _) = makeList(folder: rows)
        let chosen = [rows[4], rows[1]]
        XCTAssertEqual(chosen.map(\.isFlagged), [false, false])
        let flagged = await ListBatch.run(.flag(true), on: chosen, role: { _ in .inbox },
                                          list: list, repository: repository, requestSweep: {})
        let step = try XCTUnwrap(UndoableFlag.after(
            .flag(true), took: chosen.filter { flagged.taken.contains($0.id) }))
        XCTAssertEqual(step.letters.map(\.id), chosen.map(\.id))
        for m in chosen {
            XCTAssertTrue(server.flags(uid: uid(m.id), in: Server.inbox).contains("\\Flagged"))
        }

        server.hangsUpOnVerbs = ["UID STORE"]
        let failed = await UndoMoves.run(step, repository: repository, list: list,
                                         requestSweep: {})
        XCTAssertEqual(failed.refusal, .cannotConnect)
        XCTAssertEqual(failed.back, [])
        XCTAssertEqual(failed.left?.letters.map(\.id), chosen.map(\.id))
        XCTAssertEqual(failed.left?.flagged, true)
        XCTAssertEqual(chosen.map { list.letter($0.id)?.isFlagged }, [true, true],
                       "put back as they were")

        server.hangsUpOnVerbs = []
        server.clearLog()
        let undone = await UndoMoves.run(try XCTUnwrap(failed.left), repository: repository,
                                         list: list, requestSweep: {})
        XCTAssertNil(undone.refusal)
        XCTAssertNil(undone.left)
        XCTAssertEqual(undone.back, chosen.map(\.id))
        XCTAssertEqual(server.log.filter(\.isUIDCommand).map(\.verb).filter { $0 != "UID FETCH" },
                       ["UID STORE", "UID STORE"])
        XCTAssertFalse(server.log.contains { ["UID MOVE", "UID COPY", "APPEND", "UID EXPUNGE",
                                             "EXPUNGE"].contains($0.verb) })
        for m in chosen {
            XCTAssertFalse(server.flags(uid: uid(m.id), in: Server.inbox).contains("\\Flagged"))
            XCTAssertEqual(list.letter(m.id)?.isFlagged, false)
        }

        list.setFlagged(true, on: rows[4])
        server.clearLog()
        let waiting = await UndoMoves.run(step, repository: repository, list: list,
                                          requestSweep: {})
        XCTAssertEqual(waiting, UndoMoves.FlagOutcome(left: step))
        XCTAssertEqual(server.log.filter(\.isUIDCommand).count, 0)
        list.flagAnswered(rows[4], landed: false)
    }

    /// A letter flagged, then trashed, and the Trash undone, is back under
    /// a new id; the Flag's Undo after it finds the letter there by its
    /// Gmail id, and takes the flag off it, not off the id it had.
    @MainActor
    func testAnUndoFlagFindsALetterBroughtBackUnderANewID() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let (list, _) = makeList(folder: rows)
        let letter = try XCTUnwrap(rows.first { !$0.isFlagged })
        let flagged = await ListBatch.run(.flag(true), on: [letter], role: { _ in .inbox },
                                          list: list, repository: repository, requestSweep: {})
        let flag = try XCTUnwrap(UndoableFlag.after(
            .flag(true), took: [letter].filter { flagged.taken.contains($0.id) }))
        let (_, made) = await remove(.delete, [try XCTUnwrap(list.letter(letter.id))], list: list,
                                     repository: repository)
        _ = await UndoMoves.run(try XCTUnwrap(made), repository: repository, list: list,
                                requestSweep: {})
        let back = try XCTUnwrap(list.shown.first { $0.gmailMessageID == letter.gmailMessageID })
        XCTAssertNotEqual(back.id, letter.id)
        XCTAssertTrue(back.isFlagged)
        XCTAssertTrue(server.flags(uid: uid(back.id), in: Server.inbox).contains("\\Flagged"))

        let undone = await UndoMoves.run(flag, repository: repository, list: list,
                                         requestSweep: {})
        XCTAssertNil(undone.refusal)
        XCTAssertEqual(undone.back, [back.id])
        XCTAssertFalse(server.flags(uid: uid(back.id), in: Server.inbox).contains("\\Flagged"))
        XCTAssertEqual(list.shownRow(of: letter)?.isFlagged, false)
    }

    /// A full drag's Unread on a read letter, then its Undo (B-175): the
    /// letter read again on the server, not only on its row, as Mail's own
    /// Undo left it (r6 comparison C-07b); one STORE and nothing else; the
    /// one the Unread put on the counts taken off again, once. A failed
    /// Undo says so, puts the dot back as it was and is a step again. A
    /// read mark on its way: nothing sent, the step left. With the list
    /// gone, nothing to bill, the counts are swept.
    @MainActor
    func testAnUndoReadMarkSetsTheMarkBackOnTheServer() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let (list, counts) = makeList(folder: rows)
        let letter = try XCTUnwrap(rows.first { $0.isRead })
        let marked = await ListBatch.run(.read(false), on: [letter], role: { _ in .inbox },
                                         list: list, repository: repository, requestSweep: {})
        let step = try XCTUnwrap(UndoableRead.after(
            .read(false), took: [letter].filter { marked.taken.contains($0.id) }))
        XCTAssertEqual(step.actionName, "Unread")
        XCTAssertEqual(Undoable.read(step).actionName, "Unread")
        XCTAssertFalse(server.flags(uid: uid(letter.id), in: Server.inbox).contains("\\Seen"))
        XCTAssertEqual(counts.on.count, 1)

        server.hangsUpOnVerbs = ["UID STORE"]
        let failed = await UndoMoves.run(step, repository: repository, list: list,
                                         requestSweep: {})
        XCTAssertEqual(failed.refusal, .cannotConnect)
        XCTAssertEqual(failed.back, [])
        XCTAssertEqual(failed.left?.letters.map(\.id), [letter.id])
        XCTAssertEqual(failed.left?.read, false)
        XCTAssertEqual(list.letter(letter.id)?.isRead, false, "put back as it was")

        server.hangsUpOnVerbs = []
        server.clearLog()
        let undone = await UndoMoves.run(try XCTUnwrap(failed.left), repository: repository,
                                         list: list, requestSweep: {})
        XCTAssertNil(undone.refusal)
        XCTAssertNil(undone.left)
        XCTAssertEqual(undone.back, [letter.id])
        XCTAssertEqual(server.log.filter(\.isUIDCommand).map(\.verb).filter { $0 != "UID FETCH" },
                       ["UID STORE"])
        XCTAssertTrue(server.flags(uid: uid(letter.id), in: Server.inbox).contains("\\Seen"))
        XCTAssertEqual(list.letter(letter.id)?.isRead, true)
        XCTAssertEqual(counts.off.count, 1, "the one taken off again, once")

        let row = try XCTUnwrap(list.letter(letter.id))
        list.setRead(false, on: row)
        server.clearLog()
        let waiting = await UndoMoves.run(step, repository: repository, list: list,
                                          requestSweep: {})
        XCTAssertEqual(waiting, UndoMoves.ReadOutcome(left: step))
        XCTAssertEqual(server.log.filter(\.isUIDCommand).count, 0)
        list.readRefused(row)

        var swept = 0
        let gone = await UndoMoves.run(step, repository: repository, list: nil,
                                       requestSweep: { swept += 1 })
        XCTAssertEqual(gone.back, [letter.id])
        XCTAssertEqual(swept, 1, "no list to bill: the counts swept")
    }

    /// The reading pane's Delete and Move hear where the letter went once
    /// the server has taken it, and nothing for a Flag or a read mark, nor
    /// for a refusal.
    @MainActor
    func testThePaneHearsWhereItsLetterWent() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let (list, _) = makeList(folder: rows)
        let folders = self.folders
        var heard: [MoveLanding?] = []
        for action: PaneAction in [.flag(true), .read(false), .delete] {
            let refused = await PaneActions.refusal(
                running: action, on: rows[3], inFolderWithRole: .inbox, list: list,
                repository: repository, requestSweep: {}, landed: { landing, _ in heard.append(landing) })
            XCTAssertNil(refused)
        }
        XCTAssertEqual(heard.count, 1)
        XCTAssertEqual(heard.first??.folder, Server.trash)
        XCTAssertEqual(heard.first??.letter, rows[3].gmailMessageID)

        server.hangsUpOnVerbs = ["UID MOVE"]
        let refused = await PaneActions.refusal(
            running: .move(to: try XCTUnwrap(folders.first { $0.role == .junk })), on: rows[5],
            inFolderWithRole: .inbox, list: list, repository: repository, requestSweep: {},
            landed: { landing, _ in heard.append(landing) })
        XCTAssertNotNil(refused)
        XCTAssertEqual(heard.count, 1)
    }

    // MARK: - The screens, read

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

    /// The screens own the undo manager, on the responder chain where a
    /// shake, three fingers and Command-Z look for it, and take the first
    /// responder when nothing else has it; each Trash or Move the server
    /// took, from a drag, Edit mode or the pane, is one step under Mail's
    /// name for it; Undo runs `UndoMoves`, says "Moving…" while it goes,
    /// fetches afresh a list that lost the rows, and puts what failed back
    /// as a step. Nothing of it is kept anywhere: a relaunch has nothing to
    /// undo.
    func testTheScreensKeepTheUndoAndOnlyInMemory() throws {
        let root = try source("UI/RootViewController.swift")
        for line in [
            "private let undos: UndoManager = { let undos = UndoManager() "
                + "undos.levelsOfUndo = 50 return undos }()",
            "override var undoManager: UndoManager? { undos }",
            "override var canBecomeFirstResponder: Bool { true }",
            "super.viewDidAppear(animated) takeUndo()",
            "guard !isFirstResponder, view.window != nil, presentedViewController == nil, "
                + "!list.isTyping else { return } becomeFirstResponder()",
            "undos.registerUndo(withTarget: self, selector: #selector(undoStep(_:)), "
                + "object: UndoStep(step, from: letters)) undos.setActionName(step.actionName) "
                + "takeUndo()",
            "let done = list.working(StatusLine.moving)",
            "let outcome = await UndoMoves.run(step, repository: self.repository, list: letters,",
            "if folders.contains(self.list.mailboxID) { await self.list.reload(keepingPlace: "
                + "true, quietly: true) } if let left = outcome.left { self.canUndo(.move(left), "
                + "from: letters) } if let refusal = outcome.refusal { "
                + "ErrorPresenter.show(reaching: refusal, on: self) }",
            "super.dismiss(animated: flag) { [weak self] in completion?() self?.takeUndo() }",
            "for name in [UITextField.textDidEndEditingNotification, "
                + "UITextView.textDidEndEditingNotification] {",
            "list.onUndoable = { [weak self] step, letters in self?.canUndo(step, from: letters) }",
            // The pane's Delete or Move as the list's copy had the letter at
            // the tap, not the pane's (`testThePanesUndoPutsTheRowBackAsTheListHadIt`).
            "landed: { [weak self, weak letters] landing, before in guard let landing, let step = "
                + "UndoableMove.after( action, took: [before], landings: [before.id: landing], "
                + "role: { folders.role(of: $0) }) else { return } self?.canUndo(.move(step), "
                + "from: letters) },",
            "self.returnedFromAway() self.takeUndo()",
        ] {
            XCTAssertTrue(root.contains(line), line)
        }
        XCTAssertEqual(count("canUndo(", in: root), 7,
                       "the pane's Move and Flag, the list's, a step left of each of the three, "
                       + "and itself")
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains(
            "let took = chosen.filter { outcome.taken.contains($0.id) } if let step = "
                + "UndoableMove.after(action, took: took, landings: landings, role: { "
                + "self.role(of: $0) }) { self.onUndoable?(.move(step), self.letters) }"))
        XCTAssertTrue(list.contains("landed: { letter, landing in landings[letter.id] = landing },"))
        let steps = try source("Mail/UndoMoves.swift")
        for kept in ["UserDefaults", "FileManager", "write(to", "MailShelf", "Codable"] {
            XCTAssertFalse(steps.contains(kept), kept)
        }
        XCTAssertEqual(count("undos.", in: root), 3, "made, added to, and named; never written down")

        // A Flag or an Unflag from the pane, a drag or More is a step of
        // its own, undone by `UndoMoves`; a read mark is one only from a
        // full drag (B-175, `DragsLikeMailTests`).
        for line in [
            "if refused == nil, let step = UndoableFlag.after(action, took: [letter]) { "
                + "self.canUndo(.flag(step), from: letters) } return refused",
            "case .move(let move): undo(move, into: letters) case .flag(let flag): undo(flag, "
                + "into: letters) case .read(let read): undo(read, into: letters)",
            "let outcome = await UndoMoves.run(step, repository: self.repository, list: letters, "
                + "requestSweep: { [weak self] in self?.refreshMailboxes() }) if let left = "
                + "outcome.left { self.canUndo(.flag(left), from: letters) }",
        ] {
            XCTAssertTrue(root.contains(line), line)
        }
        XCTAssertTrue(list.contains(
            "let took = changing.filter { outcome.taken.contains($0.id) } "
                + "if let step = UndoableFlag.after(action, took: took) { "
                + "self.onUndoable?(.flag(step), self.letters) }"))
        XCTAssertTrue(list.contains("var onUndoable: ((Undoable, ListLetters) -> Void)?"))
    }
}

/// What the list says to the folder counts, written down.
@MainActor
private final class Counts {
    /// The folders each letter came off, one entry per letter.
    private(set) var off: [[String]] = []
    /// The folders each letter went back on.
    private(set) var on: [[String]] = []

    func record(_ folders: [String], _ delta: Int) {
        if delta < 0 { off.append(folders) } else { on.append(folders) }
    }
}
