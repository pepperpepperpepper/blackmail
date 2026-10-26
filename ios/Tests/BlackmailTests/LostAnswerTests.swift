import XCTest
@testable import Blackmail

/// A Delete or Move whose MOVE went and whose answer was lost with the
/// connection (B-151): refused then as not moved, its row back with the
/// alert as before (B-092, B-132), and looked for once, by Gmail's id for
/// the letter, in the folder it was in, at the watch's next check that
/// reaches the server. Gone, Gmail did move it, and its row goes quietly;
/// there, it stays. Over `ScriptedIMAPServer`, whose `hangsUpAfterVerbs`
/// carries a MOVE out and hangs up before its answer, through the shipping
/// repository, the list's own letters, the kept copy and `MailWatch`.
final class LostAnswerTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "LostAnswerTests"
    private static let notes = "Notes"
    private static let family = Mailbox(id: "Family", name: "Family", unreadCount: 0)

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

    // MARK: - Gmail did move it

    /// A Delete from the reading pane in the label Notes, the letter unread:
    /// Gmail moves it to the Trash and hangs up before its answer. Refused
    /// as before, the row back and "Can't connect to mail server.", the
    /// kept copy keeping it, nothing billed. The watch's next check reaches
    /// the server on a new connection and looks once, `UID SEARCH
    /// X-GM-MSGID` in Notes, after the screens are told how the check went:
    /// not there, so the row goes with no alert, the list at its top, the
    /// letter comes off the counts once with one sweep, and the kept copy
    /// lets it go. A check after that looks no more.
    @MainActor
    func testADeleteGmailCarriedOutWhoseAnswerWasLostGoesQuietlyAtTheNextCheck() async throws {
        let (repository, rows) = try await notesListed()
        let letter = rows[1]
        XCTAssertFalse(letter.isRead)
        let (list, counts) = makeList(rows)
        let sweeps = Counter()
        server.hangsUpAfterVerbs = ["UID MOVE"]
        server.clearLog()

        let refused = await PaneActions.refusal(running: .delete, on: letter, inFolderWithRole: nil,
                                                list: list, repository: repository,
                                                requestSweep: { sweeps.add() })

        XCTAssertEqual(refused, .cannotConnect)
        XCTAssertEqual(MailAlert.reaching(try XCTUnwrap(refused)).message, "Can't connect to mail server.")
        XCTAssertEqual(server.log.map(\.command), [moveToTrash(letter)])
        XCTAssertFalse(inNotes(letter), "Gmail did move it")
        XCTAssertTrue(inTrash(letter))
        XCTAssertEqual(list.shown.map(\.id), rows.map(\.id), "the row back, as before")
        XCTAssertEqual(kept(letter), true)
        XCTAssertEqual(counts.billed, [])
        XCTAssertEqual(sweeps.value, 0)
        XCTAssertEqual(notes, ["LOST-ANSWER UID MOVE folder=\(Self.notes) uid=\(uid(letter.id))"])

        server.hangsUpAfterVerbs = []
        server.clearLog()
        let screen = Screen(list)
        let watch = MailWatch(repository: repository)
        watch.target = screen
        await watch.check()

        XCTAssertEqual(screen.outcomes.count, 1)
        guard case .reached = screen.outcomes.first else { return XCTFail("\(screen.outcomes)") }
        XCTAssertEqual(screen.told, ["checked", "moved"], "told of the check before the look")
        XCTAssertEqual(looks, [lookFor(letter)])
        XCTAssertEqual(server.log.first { $0.command == lookFor(letter) }?.selected, Self.notes)
        XCTAssertEqual(list.shown.map(\.id), rows.map(\.id).filter { $0 != letter.id })
        XCTAssertEqual(screen.gone.map(\.id), [letter.id])
        XCTAssertEqual(counts.billed.count, 1, "one off the counts, once")
        XCTAssertEqual(counts.billed.first?.contains(Self.notes), true, "\(counts.billed)")
        XCTAssertEqual(screen.sweeps, 1)
        XCTAssertEqual(kept(letter), false)
        XCTAssertEqual(notes.last, "LOST-ANSWER-LOOK folder=\(Self.notes) uid=\(uid(letter.id)) gone")

        server.clearLog()
        await watch.check()
        XCTAssertEqual(looks, [], "one look")
        XCTAssertEqual(counts.billed.count, 1)
        XCTAssertEqual(screen.sweeps, 1)
    }

    /// Edit mode's Delete of three rows in Notes, the second letter's MOVE
    /// carried out and its answer lost: the first went, the second and the
    /// third come back, the third never sent (B-062). At the next check the
    /// second alone is looked for, and its row goes; the third stays.
    @MainActor
    func testEditModesDeleteWhoseSecondAnswerWasLostLosesThatRowAtTheNextCheck() async throws {
        let (repository, rows) = try await notesListed()
        let (list, _) = makeList(rows)
        let chosen = Array(rows[2...4].reversed())
        let server = self.server!
        let first = moveToTrash(chosen[0])
        server.change(after: { $0.command == first }) { server.hangsUpAfterVerbs = ["UID MOVE"] }
        server.clearLog()

        let outcome = await ListBatch.run(.delete, on: chosen, role: { _ in nil }, list: list,
                                          repository: repository, requestSweep: {})

        XCTAssertEqual(outcome, ListBatch.Outcome(taken: [chosen[0].id],
                                                  notTaken: [chosen[1].id, chosen[2].id],
                                                  refusal: .cannotConnect))
        XCTAssertEqual(server.log.map(\.command), [first, moveToTrash(chosen[1])])
        XCTAssertTrue(inTrash(chosen[1]), "Gmail did move the second")
        XCTAssertTrue(inNotes(chosen[2]))
        XCTAssertTrue(list.shown.contains { $0.id == chosen[1].id })

        server.hangsUpAfterVerbs = []
        server.clearLog()
        let screen = Screen(list)
        let watch = MailWatch(repository: repository)
        watch.target = screen
        await watch.check()

        XCTAssertEqual(looks, [lookFor(chosen[1])])
        let shown = list.shown.map(\.id)
        XCTAssertFalse(shown.contains(chosen[0].id))
        XCTAssertFalse(shown.contains(chosen[1].id), "the lost answer's row gone")
        XCTAssertTrue(shown.contains(chosen[2].id), "the one never sent stays")
    }

    /// A MOVE answered with nothing to show (B-092), the letter moved and
    /// the connection not told, and the connection lost under the look into
    /// it: refused as not moved, as B-092 has it, and now looked for at the
    /// next check, found gone, and its row taken off.
    @MainActor
    func testAHollowAnswerWhoseCheckWasLostIsLookedForToo() async throws {
        let (repository, rows) = try await notesListed()
        let letter = rows[3]
        let (list, _) = makeList(rows)
        server.hollowMoves = [.movedUntold]
        server.holdReplies(to: "NOOP")
        server.clearLog()

        let deleted = Task { @MainActor in
            await PaneActions.refusal(running: .delete, on: letter, inFolderWithRole: nil,
                                      list: list, repository: repository, requestSweep: {})
        }
        try await until { self.server.log.contains { $0.verb == "NOOP" } }
        await server.resetConnections()
        let refused = try await finishing { await deleted.value }
        server.stopHolding("NOOP")

        XCTAssertEqual(refused, .cannotConnect)
        XCTAssertTrue(inTrash(letter))
        XCTAssertTrue(list.shown.contains { $0.id == letter.id })
        XCTAssertTrue(notes.contains("MOVE-CHECKED folder=\(Self.notes) uid=\(uid(letter.id)) lost not-moved"))

        server.clearLog()
        let screen = Screen(list)
        let watch = MailWatch(repository: repository)
        watch.target = screen
        await watch.check()

        XCTAssertEqual(looks, [lookFor(letter)])
        XCTAssertFalse(list.shown.contains { $0.id == letter.id })
    }

    // MARK: - Gmail did not move it

    /// A Move to a label answered with Gmail's `* BYE System Error`, the
    /// connection closed and nothing done (B-132): refused as before, the
    /// row back. The next check looks once, finds the letter still in
    /// Notes, and the row stays, nothing billed, nothing swept, the kept
    /// copy keeping it. A check after that looks no more.
    @MainActor
    func testAMoveGmailNeverCarriedOutLeavesItsRowAtTheNextCheck() async throws {
        server.addFolder(Self.family.id, attributes: ["\\HasNoChildren"], label: Self.family.id,
                         validity: 600_100, firstUID: 10)
        let (repository, rows) = try await notesListed()
        let letter = rows[1]
        let (list, counts) = makeList(rows)
        server.hangsUpOnVerbs = ["UID MOVE"]
        server.clearLog()

        let refused = await PaneActions.refusal(running: .move(to: Self.family), on: letter,
                                                inFolderWithRole: nil, list: list,
                                                repository: repository, requestSweep: {})

        XCTAssertEqual(refused, .cannotConnect)
        XCTAssertTrue(inNotes(letter))
        XCTAssertEqual(list.shown.map(\.id), rows.map(\.id))

        server.hangsUpOnVerbs = []
        server.clearLog()
        let screen = Screen(list)
        let watch = MailWatch(repository: repository)
        watch.target = screen
        await watch.check()

        XCTAssertEqual(looks, [lookFor(letter)])
        XCTAssertEqual(list.shown.map(\.id), rows.map(\.id), "the row stays")
        XCTAssertEqual(screen.gone, [])
        XCTAssertEqual(counts.billed, [])
        XCTAssertEqual(screen.sweeps, 0)
        XCTAssertEqual(kept(letter), true)
        XCTAssertEqual(notes.last, "LOST-ANSWER-LOOK folder=\(Self.notes) uid=\(uid(letter.id)) there")

        server.clearLog()
        await watch.check()
        XCTAssertEqual(looks, [], "one look")
    }

    /// A MOVE kept back before a byte of it was written, its path gone
    /// with the SELECT in front of it on the wire (B-091): refused as
    /// before, and nothing to look for, since nothing went.
    @MainActor
    func testAMoveNeverWrittenIsNotLookedFor() async throws {
        let (repository, rows) = try await notesListed()
        let letter = rows[2]
        let (list, _) = makeList(rows)
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 5)
        server.clearLog()
        Diagnostics.clear()

        server.holdReplies(to: "SELECT")
        let deleted = Task { @MainActor in
            await PaneActions.refusal(running: .delete, on: letter, inFolderWithRole: nil,
                                      list: list, repository: repository, requestSweep: {})
        }
        try await until { self.server.log.contains { $0.verb == "SELECT" } }
        server.losePathOfOpenLinks()
        await server.releaseReplies(to: "SELECT")
        let refused = try await finishing { await deleted.value }

        XCTAssertEqual(refused, .cannotConnect)
        XCTAssertTrue(Diagnostics.entries.contains { $0.text == "NO-PATH UID MOVE not-sent" },
                      "\(Diagnostics.entries.map(\.text))")
        XCTAssertFalse(server.log.contains { $0.verb == "UID MOVE" }, "\(server.log.map(\.command))")
        XCTAssertTrue(inNotes(letter))
        XCTAssertFalse(notes.contains { $0.hasPrefix("LOST-ANSWER") }, "\(notes)")

        server.clearLog()
        let screen = Screen(list)
        let watch = MailWatch(repository: repository)
        watch.target = screen
        await watch.check()
        XCTAssertEqual(looks, [])
        XCTAssertTrue(list.shown.contains { $0.id == letter.id })
    }

    // MARK: - The look itself

    /// The look's SEARCH lost with its connection, and with the new one
    /// it is retried on: it waits for the next check, which looks again and
    /// finds the letter gone.
    @MainActor
    func testALookWithNoConnectionToGoOnWaitsForTheNextCheck() async throws {
        let (repository, rows) = try await notesListed()
        let letter = rows[1]
        let (list, _) = makeList(rows)
        server.hangsUpAfterVerbs = ["UID MOVE"]
        _ = await PaneActions.refusal(running: .delete, on: letter, inFolderWithRole: nil,
                                      list: list, repository: repository, requestSweep: {})
        server.hangsUpAfterVerbs = []
        server.hangsUpOnVerbs = ["UID SEARCH"]
        server.clearLog()
        let screen = Screen(list)
        let watch = MailWatch(repository: repository)
        watch.target = screen
        await watch.check()

        XCTAssertEqual(looks.count, 2, "asked, and once more on a new connection")
        XCTAssertTrue(list.shown.contains { $0.id == letter.id })
        XCTAssertEqual(notes.last, "LOST-ANSWER-LOOK folder=\(Self.notes) uid=\(uid(letter.id)) not-asked")

        server.hangsUpOnVerbs = []
        server.clearLog()
        await watch.check()
        XCTAssertEqual(looks, [lookFor(letter)])
        XCTAssertFalse(list.shown.contains { $0.id == letter.id })
    }

    /// The look's SEARCH refused, on a connection still up: the server has
    /// not said where the letter is, so the row stays, and it is not
    /// looked for again.
    @MainActor
    func testALookTheServerRefusesLeavesTheRowAndIsNotMadeAgain() async throws {
        let (repository, rows) = try await notesListed()
        let letter = rows[1]
        let (list, _) = makeList(rows)
        server.hangsUpAfterVerbs = ["UID MOVE"]
        _ = await PaneActions.refusal(running: .delete, on: letter, inFolderWithRole: nil,
                                      list: list, repository: repository, requestSweep: {})
        server.hangsUpAfterVerbs = []
        server.refusedVerbs = ["UID SEARCH"]
        server.clearLog()
        let screen = Screen(list)
        let watch = MailWatch(repository: repository)
        watch.target = screen
        await watch.check()

        XCTAssertEqual(looks, [lookFor(letter)])
        XCTAssertTrue(list.shown.contains { $0.id == letter.id })
        XCTAssertEqual(notes.last, "LOST-ANSWER-LOOK folder=\(Self.notes) uid=\(uid(letter.id)) unanswered")

        server.refusedVerbs = []
        server.clearLog()
        await watch.check()
        XCTAssertEqual(looks, [])
    }

    /// Deleted again before the look, the second Delete has the say: its
    /// MOVE finds the letter gone (B-092's look), the row goes and is
    /// billed once, and there is nothing left to look for.
    @MainActor
    func testADeleteMadeAgainBeforeTheLookIsTheOneThatCounts() async throws {
        let (repository, rows) = try await notesListed()
        let letter = rows[1]
        let (list, counts) = makeList(rows)
        server.hangsUpAfterVerbs = ["UID MOVE"]
        _ = await PaneActions.refusal(running: .delete, on: letter, inFolderWithRole: nil,
                                      list: list, repository: repository, requestSweep: {})
        server.hangsUpAfterVerbs = []

        let again = await PaneActions.refusal(running: .delete, on: letter, inFolderWithRole: nil,
                                              list: list, repository: repository, requestSweep: {})
        XCTAssertNil(again)
        XCTAssertFalse(list.shown.contains { $0.id == letter.id })
        XCTAssertEqual(counts.billed.count, 1)

        server.clearLog()
        let screen = Screen(list)
        let watch = MailWatch(repository: repository)
        watch.target = screen
        await watch.check()
        XCTAssertEqual(looks, [])
        XCTAssertEqual(screen.gone, [])
        XCTAssertEqual(counts.billed.count, 1, "billed once")
    }

    /// Only a row the list still shows, from the same folder, as the same
    /// letter, goes: not one taken off by hand since, nor one the watch
    /// holds to go, nor a row under the same id from another folder or
    /// that is another letter now.
    @MainActor
    func testOnlyARowStillShownAsTheSameLetterGoes() {
        func row(_ uid: Int, in folder: String = Self.notes, letter: UInt64? = nil,
                 read: Bool = true) -> MessageSummary {
            MessageSummary(id: "600200/\(uid)", mailboxID: folder, sender: "Sam",
                           subject: "Letter \(uid)", preview: "",
                           date: Server.newestDate.addingTimeInterval(Double(-uid) * 60),
                           isRead: read, isFlagged: false,
                           gmailMessageID: letter ?? 1_000 + UInt64(uid))
        }
        let rows = (1...5).map { row($0, read: $0 != 2) }
        func moved(_ row: MessageSummary, in folder: String = Self.notes,
                   letter: UInt64? = nil) -> MovedAfterAll {
            MovedAfterAll(id: row.id, mailboxID: folder, gmailMessageID: letter ?? row.gmailMessageID!,
                          leftEveryFolder: true)
        }
        let list = ListLetters()
        _ = list.fetchedAfresh(rows)
        list.take(rows[0], fromEveryFolder: true)
        list.hold(FolderNews(gone: [rows[2].id]))
        var sweeps = 0

        let gone = PaneActions.movedAfterAll(
            [moved(rows[0]), moved(rows[2]), moved(rows[3], in: Server.inbox),
             moved(rows[4], letter: 99), moved(rows[1])],
            list: list, showsNews: true, requestSweep: { sweeps += 1 })

        XCTAssertEqual(gone.map(\.id), [rows[1].id])
        XCTAssertEqual(list.shown.map(\.id), [rows[2], rows[3], rows[4]].map(\.id))
        XCTAssertEqual(sweeps, 1, "the one that went was unread")
    }

    // MARK: - Where he is

    /// The same lost Delete, unread, with him scrolled down the list when
    /// the look finds the letter gone: nothing on the list changes, the row
    /// held with the watch's news (B-049), nothing billed, and the counts
    /// swept once, which has them from the server. Back at the top, the row
    /// goes, and is not billed then either.
    @MainActor
    func testScrolledDownTheRowWaitsForTheTop() async throws {
        let (repository, rows) = try await notesListed()
        let letter = rows[1]
        XCTAssertFalse(letter.isRead)
        let (list, counts) = makeList(rows)
        server.hangsUpAfterVerbs = ["UID MOVE"]
        _ = await PaneActions.refusal(running: .delete, on: letter, inFolderWithRole: nil,
                                      list: list, repository: repository, requestSweep: {})
        server.hangsUpAfterVerbs = []
        server.clearLog()
        let screen = Screen(list)
        screen.atTop = false
        let watch = MailWatch(repository: repository)
        watch.target = screen
        await watch.check()

        XCTAssertEqual(looks, [lookFor(letter)])
        XCTAssertEqual(notes.last, "LOST-ANSWER-LOOK folder=\(Self.notes) uid=\(uid(letter.id)) gone")
        XCTAssertEqual(list.shown.map(\.id), rows.map(\.id), "nothing moves under him")
        XCTAssertEqual(screen.gone, [])
        XCTAssertEqual(counts.billed, [])
        XCTAssertEqual(screen.sweeps, 1, "the counts from the server")
        XCTAssertFalse(list.shows(letter), "held to go")
        XCTAssertEqual(screen.showIfAtTop(), .wait)

        screen.atTop = true
        XCTAssertEqual(screen.showIfAtTop(), .shown([]))
        XCTAssertEqual(list.shown.map(\.id), rows.map(\.id).filter { $0 != letter.id })
        XCTAssertEqual(counts.billed, [], "the sweep has the counts")
        XCTAssertEqual(screen.sweeps, 1)

        server.clearLog()
        await watch.check()
        XCTAssertEqual(looks, [])
    }

    /// A row ticked in Edit mode, or a finger on the list, holds the row as
    /// being scrolled down does; each goes once he is at the top with
    /// nothing ticked and no finger down.
    @MainActor
    func testTickedOrTouchingTheRowWaitsToo() {
        let rows = (1...4).map { n in
            MessageSummary(id: "600200/\(n)", mailboxID: Self.notes, sender: "Sam",
                           subject: "Letter \(n)", preview: "",
                           date: Server.newestDate.addingTimeInterval(Double(-n) * 60),
                           isRead: n != 2, isFlagged: false, gmailMessageID: 1_000 + UInt64(n))
        }
        for (ticked, touching) in [(true, false), (false, true)] {
            let (list, counts) = makeList(rows)
            let screen = Screen(list)
            screen.ticked = ticked
            screen.touching = touching
            screen.movedAfterAll([MovedAfterAll(id: rows[1].id, mailboxID: Self.notes,
                                                gmailMessageID: rows[1].gmailMessageID!,
                                                leftEveryFolder: true)])

            let place = "ticked \(ticked), touching \(touching)"
            XCTAssertEqual(list.shown.map(\.id), rows.map(\.id), place)
            XCTAssertEqual(screen.gone, [], place)
            XCTAssertEqual(counts.billed, [], place)
            XCTAssertEqual(screen.sweeps, 1, place)
            XCTAssertEqual(screen.showIfAtTop(), .wait, place)

            screen.ticked = false
            screen.touching = false
            XCTAssertEqual(screen.showIfAtTop(), .shown([]), place)
            XCTAssertEqual(list.shown.map(\.id), [rows[0], rows[2], rows[3]].map(\.id), place)
        }
    }

    /// A Delete from an All Mailboxes hit, the letter also in the Inbox
    /// underneath, unread: the hit and the Inbox's row are one letter, and
    /// binned it has left both. Where the news goes on now, both rows go,
    /// and it comes off the counts once. A search showing is not such a
    /// place in the app, which holds the rows instead: the hit stays among
    /// the hits, nothing billed, one sweep, and the Inbox's row goes once
    /// the search has ended with the list at its top.
    @MainActor
    func testABinnedLettersRowUnderAnotherIdGoesWithIt() {
        func row(_ id: String, in folder: String, read: Bool = true, letter: UInt64,
                 subject: String) -> MessageSummary {
            MessageSummary(id: id, mailboxID: folder, sender: "Sam", subject: subject, preview: "",
                           date: Server.newestDate, isRead: read, isFlagged: false,
                           threadID: "thread-\(letter)", gmailMessageID: letter,
                           countedFolderIDs: read ? [] : ["inbox", Self.notes])
        }
        let inbox = [row("500/1", in: "inbox", letter: 1, subject: "One"),
                     row("500/2", in: "inbox", read: false, letter: 2, subject: "Two"),
                     row("500/3", in: "inbox", letter: 3, subject: "Three")]
        let hit = row("600200/27", in: Self.notes, read: false, letter: 2, subject: "Two")
        let moved = MovedAfterAll(id: hit.id, mailboxID: Self.notes, gmailMessageID: 2,
                                  leftEveryFolder: true)

        // Now.
        do {
            let (list, counts) = makeList(inbox)
            _ = list.showResults([hit])
            var sweeps = 0
            let gone = PaneActions.movedAfterAll([moved], list: list, showsNews: true,
                                                 requestSweep: { sweeps += 1 })
            XCTAssertEqual(gone, [moved])
            XCTAssertEqual(list.shown, [], "the hit gone")
            _ = list.endSearch()
            XCTAssertEqual(list.shown.map(\.id), ["500/1", "500/3"], "and the Inbox's row")
            XCTAssertEqual(counts.billed.count, 1, "one off the counts, once")
            XCTAssertEqual(sweeps, 1)
        }

        // Held, a search showing.
        do {
            let (list, counts) = makeList(inbox)
            _ = list.showResults([hit])
            let screen = Screen(list)
            screen.searching = true
            screen.movedAfterAll([moved])
            XCTAssertEqual(screen.gone, [])
            XCTAssertEqual(list.shown.map(\.id), [hit.id], "the hit stays among the hits")
            XCTAssertEqual(counts.billed, [])
            XCTAssertEqual(screen.sweeps, 1)

            _ = list.endSearch()
            XCTAssertEqual(list.shown.map(\.id), inbox.map(\.id), "held")
            screen.searching = false
            XCTAssertEqual(screen.showIfAtTop(), .shown([]))
            XCTAssertEqual(list.shown.map(\.id), ["500/1", "500/3"], "the Inbox's row goes")
            XCTAssertEqual(counts.billed, [])
        }
    }

    /// The pane empties only when the letter it opened is the one gone:
    /// the same row as the same letter, or, binned, the same letter under
    /// another id. Not for another letter of its conversation, nor for the
    /// same letter elsewhere after a Move to a label, which leaves it
    /// there.
    func testThePaneLetsGoOnlyOfTheLetterItOpened() {
        func letter(_ id: String, _ gmail: UInt64, in folder: String = Self.notes) -> MessageSummary {
            MessageSummary(id: id, mailboxID: folder, sender: "Sam", subject: "Garden", preview: "",
                           date: Server.newestDate, isRead: true, isFlagged: false,
                           threadID: "thread", gmailMessageID: gmail)
        }
        let binned = MovedAfterAll(id: "600200/27", mailboxID: Self.notes, gmailMessageID: 7,
                                   leftEveryFolder: true)
        var filed = binned
        filed.leftEveryFolder = false

        XCTAssertTrue(PaneActions.empties(paneOpenOn: letter("600200/27", 7), for: [binned]))
        XCTAssertTrue(PaneActions.empties(paneOpenOn: letter("600200/27", 7), for: [filed]))
        XCTAssertFalse(PaneActions.empties(paneOpenOn: letter("600200/26", 6), for: [binned]),
                       "another letter of the conversation")
        XCTAssertFalse(PaneActions.empties(paneOpenOn: letter("600200/27", 8), for: [binned]),
                       "another letter under that id")
        XCTAssertTrue(PaneActions.empties(paneOpenOn: letter("500/9", 7, in: "inbox"), for: [binned]),
                      "the binned letter opened from the Inbox")
        XCTAssertFalse(PaneActions.empties(paneOpenOn: letter("500/9", 7, in: "inbox"), for: [filed]),
                       "filed in a label, the Inbox's copy stays")
        XCTAssertFalse(PaneActions.empties(paneOpenOn: nil, for: [binned]))
    }

    // MARK: - Read from the source

    /// The app's target hands the rows to the list in front, which takes
    /// them off now or holds them by where he is, read off its table as the
    /// watch's news reads it; the pane lets go of the letter it opened, if
    /// it went now; the counts are swept quietly.
    func testTheRootTakesTheRowsOffQuietly() throws {
        let root = try source("UI/RootViewController.swift")
        XCTAssertTrue(root.contains(
            "func movedAfterAll(_ letters: [MovedAfterAll]) { let gone = list.movedAfterAll("
            + "letters, requestSweep: { [weak self] in self?.refreshMailboxes(quietly: true) }) "
            + "detail.clearIfOpened(any: gone) }"))
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains(
            "let here = isViewLoaded ? newsPlace : nil let showsNews = here.map { "
            + "ListPlaces.showsNews(atTop: $0.atTop, searching: $0.searching, ticked: $0.ticked, "
            + "touching: $0.touching) } ?? false return PaneActions.movedAfterAll(moved, "
            + "list: letters, showsNews: showsNews, requestSweep: requestSweep)"))
        XCTAssertTrue(list.contains(
            "let here = newsPlace switch letters.putNewsOn(atTop: here.atTop, "
            + "searching: here.searching, ticked: here.ticked, touching: here.touching)"),
            "the same place as the watch's news")
        XCTAssertTrue(list.contains(
            "if case .failed = outcome { return } fetchOverKeptQuietly() showNewsIfAtTop() }"),
            "what is held goes on at a check")
        let pane = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(pane.contains(
            "func clearIfOpened(any letters: [MovedAfterAll]) { guard PaneActions.empties("
            + "paneOpenOn: summary, for: letters) else { return } showEmpty() }"))
    }

    // MARK: - Helpers

    /// What the watch asks of the screens, over the list the test holds,
    /// with another folder than the Inbox in front: a check is the Inbox's
    /// count, and then the look. Where he is on the list, as the list in
    /// the app reads it off its table (`MessageListViewController.newsPlace`):
    /// at the top, nothing ticked, no finger, no search, unless a test says.
    @MainActor
    private final class Screen: MailWatchTarget {
        let list: ListLetters
        var atTop = true
        var searching = false
        var ticked = false
        var touching = false
        private(set) var outcomes: [MailWatch.Outcome] = []
        private(set) var gone: [MovedAfterAll] = []
        /// What the watch told the screens, in order: "checked" and "moved".
        private(set) var told: [String] = []
        /// Sweeps the rows that went asked for, apart from the ones the
        /// watch asks for itself when the Inbox's count is not the pane's.
        private(set) var sweeps = 0

        init(_ list: ListLetters) { self.list = list }

        var watchedInbox: (mailboxID: String, letters: [String])? { nil }
        var shownInboxUnread: Int? { nil }
        func found(_ news: FolderNews, in mailboxID: String) -> NewsTaken { .notTaken }
        func countsChanged() {}

        func checked(_ outcome: MailWatch.Outcome) {
            outcomes.append(outcome)
            told.append("checked")
        }

        func movedAfterAll(_ letters: [MovedAfterAll]) {
            told.append("moved")
            let went = PaneActions.movedAfterAll(
                letters, list: list,
                showsNews: ListPlaces.showsNews(atTop: atTop, searching: searching, ticked: ticked,
                                                touching: touching),
                requestSweep: { sweeps += 1 })
            gone += went
        }

        /// What the list does whenever he may be back at the top, and at
        /// every check: what it holds goes on, or waits.
        func showIfAtTop() -> ListLetters.NewsStep {
            list.putNewsOn(atTop: atTop, searching: searching, ticked: ticked, touching: touching)
        }
    }

    private func makeRepository() -> IMAPMailRepository {
        IMAPMailRepository(account: server.account, password: server.password,
                           transport: server.transportFactory, recipients: book, shelf: shelf)
    }

    /// Five letters in the label Notes, the second unread, newest first,
    /// listed and kept through the shipping repository; the server's log
    /// and the connection log cleared after.
    private func notesListed() async throws -> (IMAPMailRepository, [MessageSummary]) {
        server.addFolder(Self.notes, attributes: ["\\HasNoChildren"], label: Self.notes,
                         validity: 600_200, firstUID: 20)
        for n in 1...5 {
            server.deliver(Server.Letter(from: Server.carlo, to: [Server.owner],
                                         subject: "Notes letter \(n)",
                                         date: Server.newestDate.addingTimeInterval(Double(n - 6) * 3_600),
                                         text: "Letter \(n).\r\n",
                                         flags: n == 4 ? [] : ["\\Seen"],
                                         messageID: "<notes-\(n)@example.org>"),
                           to: [Self.notes, Server.allMail])
        }
        let repository = makeRepository()
        _ = try await repository.folders()
        let rows = try await repository.listMessages(in: Self.notes, beforeUID: nil, limit: 50)
        XCTAssertEqual(rows.map(\.subject), (1...5).reversed().map { "Notes letter \($0)" })
        XCTAssertEqual(kept(rows[0]), true)
        server.clearLog()
        Diagnostics.clear()
        return (repository, rows)
    }

    @MainActor
    private func makeList(_ rows: [MessageSummary]) -> (ListLetters, Billing) {
        let list = ListLetters()
        let counts = Billing()
        list.onUnreadCountChanged = { counts.record($0, $1) }
        _ = list.fetchedAfresh(rows)
        return (list, counts)
    }

    private func uid(_ id: String) -> UInt32 { UInt32(id.split(separator: "/").last ?? "")! }

    private func moveToTrash(_ row: MessageSummary) -> String {
        "UID MOVE \(uid(row.id)) \"\(Server.trash)\""
    }

    /// The look for the letter, as the server logs it.
    private func lookFor(_ row: MessageSummary) -> String {
        "UID SEARCH X-GM-MSGID \(row.gmailMessageID!)"
    }

    /// Every look the server has been sent since its log was cleared.
    private var looks: [String] {
        server.log.map(\.command).filter { $0.hasPrefix("UID SEARCH X-GM-MSGID") }
    }

    private func inNotes(_ row: MessageSummary) -> Bool { holds(Self.notes, row) }
    private func inTrash(_ row: MessageSummary) -> Bool { holds(Server.trash, row) }

    private func holds(_ mailbox: String, _ row: MessageSummary) -> Bool {
        server.uids(in: mailbox).contains { server.gmailMessageID(uid: $0, in: mailbox) == row.gmailMessageID }
    }

    /// Whether the kept page of Notes has the row.
    private func kept(_ row: MessageSummary) -> Bool? {
        shelf.page(of: Self.notes).map { page in page.rows.contains { $0.id == row.id } }
    }

    /// The connection log's notes about a lost answer and a MOVE's.
    private var notes: [String] {
        Diagnostics.entries.filter { $0.direction == .note }.map(\.text)
            .filter { $0.hasPrefix("LOST-ANSWER") || $0.hasPrefix("MOVE-") }
    }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail", isDirectory: true)
    }

    /// The file's code with its comment lines dropped and its spacing made
    /// single, so a line is found however it is wrapped.
    private func source(_ path: String) throws -> String {
        try String(contentsOf: sourceRoot.appendingPathComponent(path), encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
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
