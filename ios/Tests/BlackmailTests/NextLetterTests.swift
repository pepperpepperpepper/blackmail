import XCTest
@testable import Blackmail

/// After a Delete or Move of the letter in the reading pane, the letter
/// after it opens there, highlighted and marked read, as Apple Mail's
/// factory "View Next Message" opens it (B-158); the pane used to empty
/// (B-041). The row that takes the gone row's place, the one below, or the
/// one above at the foot; a conversation that keeps other letters opens
/// again without it; in a search, the next result; never a draft, an Outbox
/// letter or a letter "On this iPad only". Under "Don't Select a Message"
/// the pane empties, as before. A Delete within half a second of the last
/// does nothing, and under View Next Message nothing greys Delete.
///
/// Which letter is `NextLetter.after`'s, run here, and over the list's own
/// letters (`ListLetters`) as `PaneActions.start` takes the row off. What
/// the controllers do with it is UIKit, which the suite cannot run, and is
/// read from the source at the foot.
final class NextLetterTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private var server: ScriptedIMAPServer?

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        server = nil
        UserDefaults.standard.removeObject(forKey: NextLetter.key)
        UserDefaults(suiteName: "NextLetterTests")?.removePersistentDomain(forName: "NextLetterTests")
        super.tearDown()
    }

    private func letter(_ uid: Int, thread: String, in mailbox: String = "INBOX",
                        id: String? = nil) -> MessageSummary {
        MessageSummary(id: id ?? "7/\(uid)", mailboxID: mailbox,
                       sender: "Sam Example <sam@example.com>", subject: "About \(thread)",
                       preview: "", date: Date(timeIntervalSince1970: 1_790_000_000 + Double(uid) * 3_600),
                       isRead: true, isFlagged: false, threadID: thread)
    }

    private func rows(_ letters: [MessageSummary], grouped: Bool = true) -> [MessageThread] {
        MessageThread.rows(for: letters, grouped: grouped)
    }

    private static let label = Mailbox(id: "Family", name: "Family", unreadCount: 0, role: nil)
    private static let trash = Mailbox(id: "[Gmail]/Trash", name: "Trash", unreadCount: 0, role: .trash)
    private static let junk = Mailbox(id: "[Gmail]/Spam", name: "Spam", unreadCount: 0, role: .junk)
    private static let inbox = Mailbox(id: "INBOX", name: "Inbox", unreadCount: 0, role: .inbox)

    private func after(_ letter: MessageSummary, _ action: PaneAction = .delete,
                       role: Mailbox.Role? = .inbox, in rows: [MessageThread],
                       listedIn list: Mailbox.Role? = .inbox) -> String? {
        NextLetter.after(letter, action, onLetterIn: role, in: rows, listedIn: list)
    }

    // MARK: - Which letter

    /// The row below the one that went, which takes its place; at the foot
    /// of the list, the one above; the list's only row, none. The same for
    /// a Move to a folder, to Trash or to Junk, and for a Delete inside
    /// Trash, which erases it.
    func testTheRowBelowOpensAndAtTheFootTheOneAbove() {
        let folder = [letter(150, thread: "A"), letter(149, thread: "B"), letter(148, thread: "C"),
                      letter(147, thread: "D")]
        let list = rows(folder)
        XCTAssertEqual(list.map(\.id), ["7/150", "7/149", "7/148", "7/147"])

        XCTAssertEqual(after(folder[0], in: list), "7/149", "the first: the one below")
        XCTAssertEqual(after(folder[2], in: list), "7/147", "the one below")
        XCTAssertEqual(after(folder[3], in: list), "7/148", "the last: the one above")
        XCTAssertNil(after(folder[0], in: rows([folder[0]])), "the only row: none")

        for action in [PaneAction.move(to: Self.label), .move(to: Self.trash), .move(to: Self.junk)] {
            XCTAssertEqual(after(folder[1], action, in: list), "7/148", "\(action)")
            XCTAssertEqual(after(folder[3], action, in: list), "7/148", "\(action) at the foot")
        }
        let binned = folder.map { letter(Int($0.id.dropFirst(2))!, thread: "T\($0.id)",
                                         in: "[Gmail]/Trash", id: "9/\($0.id.dropFirst(2))") }
        XCTAssertEqual(after(binned[1], role: .trash, in: rows(binned), listedIn: .trash), "9/148",
                       "erased inside Trash")
    }

    /// A conversation that keeps other letters keeps its row, and it is
    /// the row in the gone letter's place: it opens again without it, by a
    /// letter it still holds, whichever of its letters went. One of two
    /// leaves a row of one letter, which opens.
    func testAConversationThatKeepsOtherLettersOpensAgainWithoutIt() {
        let folder = [letter(150, thread: "A"), letter(149, thread: "B"), letter(148, thread: "A"),
                      letter(147, thread: "C"), letter(146, thread: "A")]
        let list = rows(folder)
        XCTAssertEqual(list.map(\.id), ["7/150", "7/149", "7/147"])
        XCTAssertEqual(list[0].count, 3)

        XCTAssertEqual(after(folder[0], in: list), "7/148", "its newest gone")
        XCTAssertEqual(after(folder[2], in: list), "7/150", "another of its letters gone")
        XCTAssertEqual(after(folder[4], .move(to: Self.label), in: list), "7/150", "moved")

        let two = rows([letter(150, thread: "A"), letter(148, thread: "A"), letter(147, thread: "C")])
        XCTAssertEqual(two.map(\.count), [2, 1])
        XCTAssertEqual(after(two[0].newest, in: two), "7/148")
    }

    /// Moved out of All Mail, a letter is still in All Mail and its row
    /// stays (`PaneActions.effect`): it is passed over, conversation or not,
    /// for the row below, or the one above at the foot. Binned from All
    /// Mail, it goes as anywhere else.
    func testALetterMovedOutOfAllMailStaysAndTheRowBelowOpens() {
        let all = "[Gmail]/All Mail"
        let folder = [letter(150, thread: "A", in: all), letter(149, thread: "B", in: all),
                      letter(148, thread: "A", in: all), letter(147, thread: "C", in: all)]
        let list = rows(folder)
        XCTAssertEqual(list.map(\.id), ["7/150", "7/149", "7/147"])

        XCTAssertEqual(after(folder[0], .move(to: Self.inbox), role: .archive, in: list,
                             listedIn: .archive), "7/149", "not its own conversation again")
        XCTAssertEqual(after(folder[3], .move(to: Self.label), role: .archive, in: list,
                             listedIn: .archive), "7/149", "at the foot")
        XCTAssertEqual(after(folder[0], .delete, role: .archive, in: list, listedIn: .archive),
                       "7/148", "binned: its conversation without it")
        XCTAssertEqual(after(folder[1], .move(to: Self.trash), role: .archive, in: list,
                             listedIn: .archive), "7/147")
    }

    /// In a search the rows are the hits, one letter each, a conversation's
    /// too: the next result opens, the one below, or the one above at the
    /// foot, whatever conversation it is of.
    func testInASearchTheNextResultOpens() {
        let hits = [letter(150, thread: "A"), letter(148, thread: "A"), letter(147, thread: "C")]
        let list = rows(hits, grouped: false)
        XCTAssertEqual(list.map(\.count), [1, 1, 1])
        XCTAssertEqual(after(hits[0], in: list), "7/148", "the next result, of its conversation")
        XCTAssertEqual(after(hits[2], in: list), "7/148", "the last result: the one above")
    }

    /// The letter never opens again under another mailbox's id, whatever
    /// happens to that copy: binned, it takes the copy with it
    /// (`ListLetters.take`); moved out of All Mail, it stays there and so
    /// does the copy; moved from the Inbox to a label, the copy in All Mail
    /// stays. Each time the copy is passed over for the row after it, or
    /// the one above at the foot. Rows no list of the app's holds today, an
    /// All Mailboxes search listing All Mail, Trash and Spam: the rule
    /// holds all the same.
    func testTheLetterNeverOpensAgainUnderAnotherId() {
        let all = "[Gmail]/All Mail"
        let hit = letter(150, thread: "A", in: all, id: "3/90")
        let copy = letter(150, thread: "A")
        let other = letter(147, thread: "C", in: all, id: "3/80")
        XCTAssertEqual(ListEdit.twins(of: hit, among: [copy, other]).map(\.id), ["7/150"])
        let mixed = rows([hit, copy, other], grouped: false)
        XCTAssertEqual(after(hit, .delete, role: .archive, in: mixed, listedIn: .inbox), "3/80",
                       "binned: its copy goes with it")
        XCTAssertEqual(after(hit, .move(to: Self.label), role: .archive, in: mixed,
                             listedIn: .inbox), "3/80",
                       "out of All Mail: the hit and its copy stay, and are passed over")
        XCTAssertEqual(after(copy, .move(to: Self.label), role: .inbox,
                             in: rows([copy, hit, other], grouped: false), listedIn: .inbox),
                       "3/80", "out of the Inbox: its copy in All Mail stays, and is passed over")
        let atTheFoot = rows([other, hit, copy], grouped: false)
        XCTAssertEqual(after(hit, .move(to: Self.label), role: .archive, in: atTheFoot,
                             listedIn: .inbox), "3/80", "at the foot: the one above the two")
        XCTAssertNil(after(hit, .move(to: Self.label), role: .archive,
                           in: rows([hit, copy], grouped: false), listedIn: .inbox),
                     "nothing else")
    }

    /// At the foot of the rows with older letters still to be paged in, or
    /// at the foot of a day's list after Go to Date, the letter Mail would
    /// open is not on the list yet, and the one above is newer: nothing
    /// opens. A row below, or a conversation that keeps its row, opens as
    /// anywhere; a row kept on the iPad below is passed over to nothing.
    /// With the oldest on the list, the one above, as before.
    func testAtTheFootWithOlderLettersToComeNothingOpens() {
        let folder = [letter(150, thread: "A"), letter(149, thread: "B"), letter(148, thread: "A"),
                      letter(147, thread: "C")]
        let list = rows(folder)
        XCTAssertEqual(list.map(\.id), ["7/150", "7/149", "7/147"])
        func next(_ gone: MessageSummary, _ action: PaneAction = .delete,
                  in rows: [MessageThread]) -> String? {
            NextLetter.after(gone, action, onLetterIn: .inbox, in: rows, listedIn: .inbox,
                             olderToCome: true)
        }

        XCTAssertNil(next(folder[3], in: list), "the last row loaded")
        XCTAssertNil(next(folder[3], .move(to: Self.label), in: list), "moved")
        XCTAssertEqual(after(folder[3], in: list), "7/149", "the oldest there is: the one above")
        XCTAssertEqual(next(folder[1], in: list), "7/147", "a row below")

        let footed = [letter(150, thread: "B"), letter(149, thread: "A"), letter(148, thread: "A")]
        let conversation = rows(footed)
        XCTAssertEqual(conversation.map(\.id), ["7/150", "7/149"])
        XCTAssertEqual(next(footed[1], in: conversation), "7/148",
                       "a conversation at the foot keeps its row")

        let kept = letter(140, thread: "K", id: "local:abc")
        let withKept = [MessageThread(messages: [folder[0]]), MessageThread(messages: [folder[1]]),
                        MessageThread(messages: [kept])]
        XCTAssertNil(next(folder[1], in: withKept), "a row kept on the iPad below")
        XCTAssertEqual(after(folder[1], in: withKept), "7/150", "the oldest there is: above")
    }

    /// Never a draft, an Outbox letter or a letter kept "On this iPad only":
    /// their rows open the composer. In Drafts and the Outbox nothing opens;
    /// a row kept on the iPad anywhere is passed over, below and above.
    func testNoDraftNoOutboxLetterAndNoLetterOnThisIPadOnly() {
        let folder = [letter(150, thread: "A"), letter(149, thread: "B"), letter(148, thread: "C")]
        let list = rows(folder)
        XCTAssertNil(after(folder[1], role: .drafts, in: list, listedIn: .drafts), "Drafts")
        XCTAssertNil(after(folder[1], role: .outbox, in: list, listedIn: .outbox), "the Outbox")
        XCTAssertEqual(after(folder[1], role: .drafts, in: list, listedIn: .inbox), "7/148",
                       "a letter of Drafts' among the Inbox's: by the list")

        let kept = letter(160, thread: "K", id: "local:abc")
        XCTAssertNotNil(LocalDraft.key(ofRow: kept.id))
        let withKept = [MessageThread(messages: [folder[0]]), MessageThread(messages: [kept]),
                        MessageThread(messages: [folder[2]])]
        XCTAssertEqual(after(folder[0], in: withKept), "7/148", "passed over below")
        XCTAssertEqual(after(folder[2], in: withKept), "7/150", "passed over above")
        XCTAssertNil(after(folder[0], in: Array(withKept.prefix(2))), "nothing else")
    }

    /// A Flag or a read mark leaves the letter where it is, and nothing
    /// opens; nor for a letter the list has no row for, a hit after its
    /// search has ended.
    func testAFlagAReadMarkOrALetterNotOnTheListOpensNothing() {
        let folder = [letter(150, thread: "A"), letter(149, thread: "B")]
        let list = rows(folder)
        for action in [PaneAction.flag(true), .flag(false), .read(true), .read(false)] {
            XCTAssertNil(after(folder[0], action, in: list), "\(action)")
        }
        XCTAssertNil(after(letter(140, thread: "Z"), in: list), "not on the list")
        XCTAssertNil(after(letter(150, thread: "A", in: "[Gmail]/All Mail", id: "3/150"), in: list),
                     "another mailbox's id")
    }

    /// Over the list's own letters, every row deleted in turn as the pane's
    /// Delete takes it (`PaneActions.start`): the letter chosen at the tap
    /// is in the list once the row is off, in the row in the gone row's
    /// place, or the one above it at the foot; or in the conversation's
    /// own row, wherever the list draws it now. A row goes by its newest
    /// letter, so a conversation whose newest has gone can be drawn lower,
    /// and its highlight goes with it.
    @MainActor
    func testTheLetterChosenIsInTheRowThatTookThePlaceOnceTheRowIsOff() {
        let folder = [letter(150, thread: "A"), letter(149, thread: "B"), letter(148, thread: "A"),
                      letter(147, thread: "C"), letter(146, thread: "D")]
        var places: [String: Int] = [:]
        for gone in folder {
            let list = ListLetters()
            _ = list.fetchedAfresh(folder)
            let before = rows(list.shown)
            let at = ListEdit.paneRow(in: before, showing: [gone.id])!
            let next = after(gone, in: before)
            _ = PaneActions.start(.delete, on: gone, inFolderWithRole: .inbox, list: list)
            let left = rows(list.shown)
            XCTAssertFalse(list.shown.contains { $0.id == gone.id })
            guard let chosen = next.flatMap({ ListEdit.paneRow(in: left, showing: [$0]) }) else {
                XCTFail("nothing found for \(gone.id)")
                continue
            }
            places[gone.id] = chosen
            if before[at].count > 1 {
                XCTAssertTrue(left[chosen].messages.allSatisfy { $0.threadID == gone.threadID },
                              gone.id)
            } else {
                XCTAssertEqual(chosen, at < left.count ? at : at - 1, gone.id)
            }
        }
        // The conversation's newest gone: its row drawn under B's now.
        XCTAssertEqual(places, ["7/150": 1, "7/149": 1, "7/148": 0, "7/147": 2, "7/146": 2])
    }

    // MARK: - The setting

    /// View Next Message from the factory, read from one place, for a
    /// Settings row to switch later; a value this build does not know is
    /// the factory default.
    func testViewNextMessageIsTheFactoryDefaultReadFromOnePlace() {
        XCTAssertEqual(NextLetter.key, "blackmail.deleteOrMoveMessageAction")
        UserDefaults.standard.removeObject(forKey: NextLetter.key)
        XCTAssertEqual(NextLetter.action, .viewNextMessage)
        NextLetter.action = .dontSelectAMessage
        XCTAssertEqual(UserDefaults.standard.string(forKey: NextLetter.key), "dontSelectAMessage")
        XCTAssertEqual(NextLetter.action, .dontSelectAMessage)
        NextLetter.action = .viewNextMessage
        XCTAssertEqual(NextLetter.action, .viewNextMessage)
        UserDefaults.standard.set("somethingLater", forKey: NextLetter.key)
        XCTAssertEqual(NextLetter.action, .viewNextMessage)
        XCTAssertEqual(NextLetter.doubleTap, 0.5)
    }

    // MARK: - The double tap

    /// Under View Next Message: Delete is never greyed for a Delete on its
    /// way, and a tap within half a second of the last does nothing, Trash's
    /// question asked of it or not; from half a second, the next goes, the
    /// first still unanswered. A tap that did nothing does not start the
    /// half second again.
    func testASecondDeleteWithinHalfASecondDoesNothingAndDeleteStaysLive() {
        var writes = PaneWrites()
        XCTAssertTrue(writes.deleteGoes(at: 100))
        XCTAssertTrue(writes.startDelete(at: 100, untilAnswered: false))
        XCTAssertFalse(writes.deleting, "not greyed")
        XCTAssertFalse(writes.deleteGoes(at: 100.1))
        XCTAssertFalse(writes.startDelete(at: 100.3, untilAnswered: false))
        XCTAssertFalse(writes.deleteGoes(at: 100.499))
        XCTAssertTrue(writes.deleteGoes(at: 100.5))
        XCTAssertTrue(writes.startDelete(at: 100.6, untilAnswered: false), "the first unanswered")
        XCTAssertFalse(writes.startDelete(at: 101.0, untilAnswered: false))
        writes.deleteAnswered()
        writes.deleteAnswered()
        XCTAssertTrue(writes.startDelete(at: 101.1, untilAnswered: false))
    }

    /// Under Don't Select a Message, as B-041 built it: Delete grey until
    /// the server has answered, however long, and the half second as well.
    func testUnderDontSelectAMessageDeleteStaysGreyUntilAnswered() {
        var writes = PaneWrites()
        XCTAssertTrue(writes.startDelete(at: 0, untilAnswered: true))
        XCTAssertTrue(writes.deleting)
        XCTAssertFalse(writes.deleteGoes(at: 60))
        XCTAssertFalse(writes.startDelete(at: 60, untilAnswered: true))
        writes.deleteAnswered()
        XCTAssertFalse(writes.deleting)
        XCTAssertTrue(writes.startDelete(at: 60.1, untilAnswered: true))
    }

    // MARK: - Opened once the row is off, before the write

    /// The pane's write over the scripted server: the next letter is opened
    /// once the row is off the list and before the MOVE is sent, once; and
    /// when the server refuses, the row comes back and the letter opened
    /// stays opened.
    @MainActor
    func testTheNextOpensOnceTheRowIsOffAndBeforeTheWriteGoes() async throws {
        let server = ScriptedIMAPServer()
        self.server = server
        let repository = makeRepository(server)
        let folder = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let gone = folder[3]
        let list = ListLetters()
        _ = list.fetchedAfresh(folder)
        server.clearLog()

        let seen = Seen()
        let refused = await PaneActions.refusal(
            running: .delete, on: gone, inFolderWithRole: .inbox, list: list,
            repository: repository, requestSweep: {},
            taken: {
                seen.shown.append(list.shown.map(\.id))
                seen.sent.append(server.log.map(\.verb))
            })
        XCTAssertNil(refused)
        XCTAssertEqual(seen.shown.count, 1, "once")
        XCTAssertEqual(seen.shown.first, folder.map(\.id).filter { $0 != gone.id }, "the row off")
        XCTAssertEqual(seen.sent.first, [], "nothing sent yet")
        XCTAssertEqual(server.log.map(\.verb), ["UID MOVE"])

        // Refused: the row back, after the next was opened.
        let second = folder[5]
        await server.resetConnections()
        let refusal = await PaneActions.refusal(
            running: .delete, on: second, inFolderWithRole: .inbox, list: list,
            repository: repository, requestSweep: {},
            taken: { seen.shown.append(list.shown.map(\.id)) })
        XCTAssertNotNil(refusal)
        XCTAssertEqual(seen.shown.count, 2)
        XCTAssertFalse(seen.shown.last?.contains(second.id) ?? true)
        XCTAssertTrue(list.shown.contains { $0.id == second.id }, "put back")
        XCTAssertEqual(server.lostWrites.map(\.verb), ["UID MOVE"])
    }

    /// A row kept on the iPad that a listing has since put another letter
    /// under (D-016): the list's row under the id is not the pane's letter,
    /// nothing is taken off, and `taken` is not run, so nothing opens.
    @MainActor
    func testNothingOpensWhenTheListsRowIsAnotherLetter() async {
        var listed = letter(150, thread: "A")
        listed.gmailMessageID = 1
        var kept = listed
        kept.gmailMessageID = 2
        let list = ListLetters()
        _ = list.fetchedAfresh([listed, letter(149, thread: "B")])
        let seen = Seen()
        _ = await PaneActions.refusal(running: .delete, on: kept, inFolderWithRole: .inbox,
                                      list: list, repository: MockMailRepository(),
                                      requestSweep: {},
                                      taken: { seen.shown.append(list.shown.map(\.id)) })
        XCTAssertEqual(seen.shown, [], "not run")
        XCTAssertEqual(list.shown.map(\.id), ["7/150", "7/149"], "the list's letter stays")
    }

    /// Under View Next Message a Delete can go while the last is on its
    /// way, Delete not being greyed for it: each takes its own row off at
    /// its tap, their MOVEs go one after the other on the one connection,
    /// and both land, with nothing put back.
    @MainActor
    func testTwoDeletesOnTheirWayAtOnceEachTakeTheirOwnRow() async throws {
        let server = ScriptedIMAPServer()
        self.server = server
        let repository = makeRepository(server)
        let folder = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let list = ListLetters()
        _ = list.fetchedAfresh(folder)
        server.clearLog()

        server.holdReplies(to: "UID MOVE")
        let first = Task { @MainActor in
            await PaneActions.refusal(running: .delete, on: folder[2], inFolderWithRole: .inbox,
                                      list: list, repository: repository, requestSweep: {})
        }
        try await until { server.log.contains { $0.verb == "UID MOVE" } }
        let second = Task { @MainActor in
            await PaneActions.refusal(running: .delete, on: folder[3], inFolderWithRole: .inbox,
                                      list: list, repository: repository, requestSweep: {})
        }
        try await until { @MainActor in !list.shown.contains { $0.id == folder[3].id } }
        XCTAssertFalse(list.shown.contains { $0.id == folder[2].id }, "the first's row still off")
        await server.releaseReplies(to: "UID MOVE")
        let answers = [await first.value, await second.value]
        XCTAssertEqual(answers, [nil, nil])
        XCTAssertEqual(server.log.map(\.verb), ["UID MOVE", "UID MOVE"])
        let gone = [folder[2].id, folder[3].id]
        XCTAssertEqual(list.shown.map(\.id), folder.map(\.id).filter { !gone.contains($0) })
    }

    private func makeRepository(_ server: ScriptedIMAPServer) -> IMAPMailRepository {
        let suite = "NextLetterTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return IMAPMailRepository(account: server.account, password: server.password,
                                  transport: server.transportFactory,
                                  recipients: RecipientBook(defaults: defaults),
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

    // MARK: - The controllers, read

    /// The container chooses the next letter at the tap, only into a pane
    /// the Delete or Move has emptied, and has the list open it once the row
    /// is off; the list chooses it only under View Next Message and out of
    /// Edit mode, and opens it as a tap opens a row, highlighted with no
    /// scroll. The pane's Delete goes by the half second, greys only under
    /// Don't Select a Message, and still empties at the tap, as Move does
    /// as he picks the folder. Edit mode's Delete and Move open nothing.
    func testTheWiringOpensTheNextIntoTheEmptiedPaneAsATapOpensARow() throws {
        let root = try source("UI/RootViewController.swift")
        for line in [
            "let role = folders.role(of: letter.mailboxID)",
            "let list = self.list let next = self.detail.lettersShown.isEmpty "
                + "? list.letterAfter(letter, action, onLetterIn: role) : nil "
                + "return await PaneActions.refusal( running: action, on: letter, "
                + "inFolderWithRole: role, list: list.letters, repository: self.repository, "
                + "requestSweep: { [weak self] in self?.refreshMailboxes() }, "
                + "taken: { if let next { list.openNext(next) } })",
            "list.onLettersLeaving = { [weak self] letters in "
                + "self?.detail.clearIfShowing(any: letters) }",
        ] {
            XCTAssertTrue(root.contains(line), line)
        }
        // Edit mode's Delete and Move open nothing: their rows leave by
        // `onLettersLeaving`, above, and `ListBatch`, below. Not a count of
        // the calls of `openNext`: a swipe on the open letter's row, wired
        // to it where the swipes are merged, is one more.

        let list = try source("UI/MessageListViewController.swift")
        for line in [
            "func letterAfter(_ letter: MessageSummary, _ action: PaneAction, "
                + "onLetterIn role: Mailbox.Role?) -> String? { "
                + "guard NextLetter.action == .viewNextMessage, !tableView.isEditing else "
                + "{ return nil } return NextLetter.after(letter, action, onLetterIn: role, "
                + "in: threads, listedIn: mailbox.role, olderToCome: !reachedOldestMessage) }",
            "func openNext(_ id: String) { guard !tableView.isEditing, "
                + "let row = rowIndex(showing: id) else { return } "
                + "let ip = IndexPath(row: row, section: 0) "
                + "tableView.selectRow(at: ip, animated: false, scrollPosition: .none) "
                + "switch rows[row] { case let .thread(thread) where thread.count > 1: "
                + "open(thread, at: ip) case let .thread(thread): open(thread.newest, at: ip) } }",
        ] {
            XCTAssertTrue(list.contains(line), line)
        }
        // A tap opens a row the same two ways, and marks it read there.
        XCTAssertTrue(list.contains("open(thread, at: ip) case let .thread(thread): "
                                    + "open(thread.newest, at: ip) } } override func "
                                    + "tableView(_ t: UITableView, didDeselectRowAt"))
        XCTAssertTrue(list.contains("onSelectMessage?(m) markReadIfNeeded(m) }"))
        XCTAssertFalse(try source("Mail/ListBatch.swift").contains("NextLetter"))

        let detail = try source("UI/MessageDetailViewController.swift")
        for line in [
            "@objc private func deleteTapped() { guard let s = summary, "
                + "writes.deleteGoes(at: ProcessInfo.processInfo.systemUptime) else { return }",
            "private func delete(_ s: MessageSummary) { guard writes.startDelete(at: "
                + "ProcessInfo.processInfo.systemUptime, untilAnswered: NextLetter.action == "
                + ".dontSelectAMessage) else { return } showEmpty()",
            "if self.summary?.id == s.id { self.showEmpty() }",
            "actionItems[.delete]?.isEnabled = enabled && !writes.deleting",
        ] {
            XCTAssertTrue(detail.contains(line), line)
        }

        let actions = try source("Mail/PaneActions.swift")
        XCTAssertTrue(actions.contains("let started = start(action, on: letter, "
                                       + "inFolderWithRole: role, list: shown) "
                                       + "if started.list != nil { taken() } do {"))
    }

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
}

/// What `taken` saw, each time it ran.
@MainActor
private final class Seen {
    var shown: [[String]] = []
    var sent: [[String]] = []
}
