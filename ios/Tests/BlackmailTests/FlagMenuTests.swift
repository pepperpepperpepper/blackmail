import XCTest
@testable import Blackmail

/// The reading pane's Flag button opens a sheet, as Mail's did (B-106):
/// Flag or Unflag, then Mark as Unread or Mark as Read, and Cancel. What it
/// offers, what each read mark sends and does to the list and the folder
/// counts, over `ScriptedIMAPServer` through the shipping repository with
/// the list's own letters, and the controller's wiring, read from its
/// source.
final class FlagMenuTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "FlagMenuTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var root: URL!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("FlagMenuTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        if let root {
            MailShelf.wipe(root: kept)
            try? FileManager.default.removeItem(at: root)
        }
        server = nil
        book = nil
        root = nil
        super.tearDown()
    }

    // MARK: - What the sheet offers

    func testTheSheetOffersFlagOrUnflagThenMarkAsUnreadOrMarkAsRead() {
        XCTAssertEqual(FlagMenu.items(flagged: false, read: true, local: false), [.flag, .markAsUnread])
        XCTAssertEqual(FlagMenu.items(flagged: true, read: true, local: false), [.unflag, .markAsUnread])
        XCTAssertEqual(FlagMenu.items(flagged: false, read: false, local: false), [.flag, .markAsRead])
        XCTAssertEqual(FlagMenu.items(flagged: true, read: false, local: false), [.unflag, .markAsRead])
    }

    /// A draft kept on the iPad, or a letter in the Outbox, has no read mark
    /// on the server to change: Flag alone.
    func testALetterKeptOnTheIPadGetsFlagAlone() {
        for read in [true, false] {
            XCTAssertEqual(FlagMenu.items(flagged: false, read: read, local: true), [.flag])
            XCTAssertEqual(FlagMenu.items(flagged: true, read: read, local: true), [.unflag])
        }
    }

    /// Mail's words, and the ones Edit mode's Mark sheet already shows.
    func testTheWordsAreMails() {
        XCTAssertEqual(FlagMenu.Item.flag.title, "Flag")
        XCTAssertEqual(FlagMenu.Item.unflag.title, "Unflag")
        XCTAssertEqual(FlagMenu.Item.markAsUnread.title, "Mark as Unread")
        XCTAssertEqual(FlagMenu.Item.markAsRead.title, "Mark as Read")
        XCTAssertEqual(FlagMenu.cancel, "Cancel")
    }

    /// A read mark keeps the row, leaves no folder and sweeps nothing, from
    /// any folder.
    func testAReadMarkKeepsTheRowAndSweepsNothing() {
        let kept = PaneActions.Effect(removesRow: false, leavesEveryFolder: false, alsoFiledIn: nil,
                                      sweepsIfUnread: false)
        for read in [true, false] {
            for role: Mailbox.Role? in [.inbox, .archive, .sent, .trash, .junk, .drafts, nil] {
                XCTAssertEqual(PaneActions.effect(of: .read(read), onLetterIn: role), kept)
            }
        }
    }

    /// One read mark on a letter at a time: another on the same letter
    /// while the first is on its way goes nowhere, and the sheet greys it;
    /// another letter's goes. Apart from the Flags.
    func testAReadMarkOnALetterWhoseLastIsOnItsWayGoesNowhereAndIsGreyed() {
        var writes = PaneWrites()
        XCTAssertFalse(writes.readOnItsWay("1/1"))
        XCTAssertTrue(writes.startRead("1/1"))
        XCTAssertTrue(writes.readOnItsWay("1/1"))
        XCTAssertFalse(writes.startRead("1/1"))
        XCTAssertTrue(writes.startRead("1/2"))
        XCTAssertFalse(writes.flagOnItsWay("1/1"), "a read mark is not a Flag")
        XCTAssertTrue(writes.startFlag("1/1"))
        XCTAssertTrue(writes.flagOnItsWay("1/1"))
        writes.readAnswered("1/1")
        XCTAssertFalse(writes.readOnItsWay("1/1"))
        XCTAssertTrue(writes.startRead("1/1"))
        XCTAssertTrue(writes.flagOnItsWay("1/1"), "the Flag still on its way")
        writes.flagAnswered("1/1")
        XCTAssertFalse(writes.flagOnItsWay("1/1"))
    }

    // MARK: - Mark as Unread over the wire

    /// One vouched UID STORE of `-FLAGS.SILENT (\Seen)` and nothing else:
    /// the dot back on the row at the tap, before the server has answered,
    /// and one back on every folder the letter is counted in once it has,
    /// with nothing swept.
    func testMarkAsUnreadSendsOneStoreAndTheDotComesBackAtTheTap() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = rows[12]
        XCTAssertTrue(letter.isRead)
        XCTAssertFalse(letter.countedFolderIDs.isEmpty)
        let (list, counts) = await makeList(folder: rows)
        let sweeps = Counter()
        server.clearLog()

        server.holdReplies(to: "UID STORE")
        let marked = Task {
            await PaneActions.run(.read(false), on: letter, inFolderWithRole: .inbox, list: list,
                                  repository: repository, requestSweep: { sweeps.add() })
        }
        try await until { self.server.log.contains { $0.verb == "UID STORE" } }
        let atTheTap = await list.letter(letter.id)
        XCTAssertEqual(atTheTap?.isRead, false, "the dot at the tap")
        var restored = await counts.restored
        XCTAssertEqual(restored, [], "nothing counted before the server has it")
        await server.releaseReplies(to: "UID STORE")
        let done = try await finishing { await marked.value }

        XCTAssertTrue(done)
        XCTAssertEqual(server.log.map(\.command),
                       ["UID STORE \(uid(letter.id)) -FLAGS.SILENT (\\Seen)"])
        XCTAssertFalse(server.flags(uid: uid(letter.id), in: Server.inbox).contains("\\Seen"))
        restored = await counts.restored
        XCTAssertEqual(restored, [letter.countedFolderIDs], "one back on, once")
        let billed = await counts.billed
        XCTAssertEqual(billed, [])
        XCTAssertEqual(sweeps.value, 0)
        let after = await list.letter(letter.id)
        XCTAssertEqual(after?.isRead, false)
        XCTAssertEqual(after?.isFlagged, letter.isFlagged)
    }

    /// Marked unread from the pane and read again by a tap on its row, as
    /// the list marks it (`markReadIfNeeded`, `sendRead`): one back on, then
    /// one off, once, however often the read is billed. Mark as Read from
    /// the pane after the Mark as Unread takes it off once too, with
    /// `+FLAGS.SILENT`.
    func testReadAgainAfterMarkAsUnreadTakesTheOneOffOnce() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = rows[12]
        let folders = letter.countedFolderIDs
        let (list, counts) = await makeList(folder: rows)

        var done = await PaneActions.run(.read(false), on: letter, inFolderWithRole: .inbox,
                                         list: list, repository: repository, requestSweep: {})
        XCTAssertTrue(done)
        // The tap on its row.
        let listed = await list.letter(letter.id)
        let row = try XCTUnwrap(listed)
        XCTAssertFalse(row.isRead)
        await list.reading(row, read: true)
        try await repository.setRead(true, on: row)
        await list.readAnswered(row.id, landed: true)
        await list.read(row)
        await list.read(row)
        var billed = await counts.billed
        XCTAssertEqual(billed, [folders], "off once")
        var restored = await counts.restored
        XCTAssertEqual(restored, [folders])

        // Unread from the pane again, then read from the pane.
        var paneCopy = letter
        paneCopy.isRead = true
        done = await PaneActions.run(.read(false), on: paneCopy, inFolderWithRole: .inbox,
                                     list: list, repository: repository, requestSweep: {})
        XCTAssertTrue(done)
        paneCopy.isRead = false
        server.clearLog()
        done = await PaneActions.run(.read(true), on: paneCopy, inFolderWithRole: .inbox,
                                     list: list, repository: repository, requestSweep: {})
        XCTAssertTrue(done)
        XCTAssertEqual(server.log.map(\.command),
                       ["UID STORE \(uid(letter.id)) +FLAGS.SILENT (\\Seen)"])
        let after = await list.letter(letter.id)
        XCTAssertEqual(after?.isRead, true)
        billed = await counts.billed
        restored = await counts.restored
        XCTAssertEqual(restored, [folders, folders])
        XCTAssertEqual(billed, [folders, folders])
        XCTAssertTrue(server.flags(uid: uid(letter.id), in: Server.inbox).contains("\\Seen"))
    }

    /// Refused: the dot goes back, the counts are as they were, and the
    /// letter keeps `\Seen`.
    func testAMarkAsUnreadTheServerRefusesPutsTheDotBackAndLeavesTheCounts() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = rows[12]
        let (list, counts) = await makeList(folder: rows)
        await server.resetConnections()

        let done = await PaneActions.run(.read(false), on: letter, inFolderWithRole: .inbox,
                                         list: list, repository: repository, requestSweep: {})

        XCTAssertFalse(done)
        let after = await list.letter(letter.id)
        XCTAssertEqual(after?.isRead, true, "the dot put back")
        XCTAssertEqual(server.lostWrites.map(\.verb), ["UID STORE"])
        XCTAssertTrue(server.flags(uid: uid(letter.id), in: Server.inbox).contains("\\Seen"))
        let billed = await counts.billed
        let restored = await counts.restored
        XCTAssertEqual(billed, [])
        XCTAssertEqual(restored, [])
    }

    /// Opened, and the read mark of that tap refused, which put the dot
    /// back: the pane still has the letter as read, and offers Mark as
    /// Unread. Chosen, the STORE goes, and nothing goes on the counts: the
    /// letter was counted unread already. Edit mode's Mark is never asked
    /// that, as it marks only a row whose dot says otherwise.
    func testMarkAsUnreadOnALetterTheListHasUnreadAlreadyCountsNothing() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = rows[1]
        XCTAssertFalse(letter.isRead)
        let (list, counts) = await makeList(folder: rows)
        // The tap, and its read mark refused (`sendRead`).
        await list.reading(letter, read: true)
        await list.readAnswered(letter.id, landed: false)
        var paneCopy = letter
        paneCopy.isRead = true
        server.clearLog()

        let done = await PaneActions.run(.read(false), on: paneCopy, inFolderWithRole: .inbox,
                                         list: list, repository: repository, requestSweep: {})

        XCTAssertTrue(done)
        XCTAssertEqual(server.log.map(\.verb), ["UID STORE"])
        let after = await list.letter(letter.id)
        XCTAssertEqual(after?.isRead, false)
        let billed = await counts.billed
        let restored = await counts.restored
        XCTAssertEqual(billed, [])
        XCTAssertEqual(restored, [], "counted unread already")
    }

    /// Opened from an All Mailboxes hit after its search has ended, so the
    /// list has no row under its id: the pane hands it as read, and Mark as
    /// Unread puts the one back on its folders and the dot on the Inbox's
    /// copy, by Gmail's id, as for a tap's read mark (B-089). The hit is
    /// All Mail's row for the letter, as an All Mailboxes hit is.
    func testMarkAsUnreadOnAHitAfterItsSearchEndedReachesTheInboxCopy() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let inboxCopy = rows[12]
        let allMail = try await repository.listMessages(in: Server.allMail, beforeUID: nil, limit: 50)
        let hit = try XCTUnwrap(allMail.first { $0.gmailMessageID == inboxCopy.gmailMessageID })
        XCTAssertNotEqual(hit.id, inboxCopy.id)
        XCTAssertTrue(hit.isRead)
        let (list, counts) = await makeList(folder: rows)
        server.clearLog()

        let done = await PaneActions.run(.read(false), on: hit, inFolderWithRole: .archive,
                                         list: list, repository: repository, requestSweep: {})

        XCTAssertTrue(done)
        XCTAssertEqual(server.log.map(\.verb), ["UID STORE"])
        let inbox = await list.letter(inboxCopy.id)
        XCTAssertEqual(inbox?.isRead, false, "the Inbox's copy has its dot")
        let restored = await counts.restored
        XCTAssertEqual(restored, [ReadBilling.folders(of: hit)])
        XCTAssertFalse(server.flags(uid: uid(inboxCopy.id), in: Server.inbox).contains("\\Seen"))
    }

    /// A row kept on the iPad whose UID the server has for another letter
    /// now (D-016): the vouching FETCH says so, nothing is sent, the letter
    /// there keeps its flags, and the row comes off the list.
    func testAMarkOnAKeptRowThatIsAnotherLetterNowSendsNothingAndTheRowGoes() async throws {
        try await earlierLaunch()
        server.renumber(Server.inbox, validity: server.uidValidity(of: Server.inbox), firstUID: 1_002)
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let rows = try XCTUnwrap(shelf.page(of: "inbox")).rows
        let letter = try XCTUnwrap(rows.first { $0.isRead })
        let flagsBefore = server.flags(uid: uid(letter.id), in: Server.inbox)
        let list = await ListLetters()
        await list.showKept(rows)
        server.clearLog()

        let done = await PaneActions.run(.read(false), on: letter, inFolderWithRole: .inbox,
                                         list: list, repository: repository, requestSweep: {})

        XCTAssertFalse(done)
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN", "NOOP", "LIST", "SELECT", "UID FETCH"])
        XCTAssertEqual(server.flags(uid: uid(letter.id), in: Server.inbox), flagsBefore)
        let shown = await list.shown
        XCTAssertFalse(shown.contains { $0.id == letter.id })
        XCTAssertEqual(shown.count, rows.count - 1)
    }

    /// Marked unread, the letter stays unread: a listing of the Inbox asked
    /// before the STORE, the list fetched afresh after it, and new mail
    /// found by the watch's check, a NOOP answered with EXISTS, send no
    /// `+FLAGS (\Seen)`, and the row keeps its dot through all three.
    func testAfterMarkAsUnreadNoReloadOrNewMailMarksTheLetterReadAgain() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = rows[12]
        let (list, _) = await makeList(folder: rows)
        let before = await list.askingAfresh()
        server.clearLog()

        let done = await PaneActions.run(.read(false), on: letter, inFolderWithRole: .inbox,
                                         list: list, repository: repository, requestSweep: {})
        XCTAssertTrue(done)

        // A listing asked before the STORE, landing after it, with the
        // letter as the server had it then: read.
        _ = await list.fetchedAfresh(rows, asked: before)
        var row = await list.letter(letter.id)
        XCTAssertEqual(row?.isRead, false, "held over the listing asked before")

        // The list fetched afresh, as a Refresh fetches it.
        let asked = await list.askingAfresh()
        let fresh = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        _ = await list.fetchedAfresh(fresh, asked: asked)
        row = await list.letter(letter.id)
        XCTAssertEqual(row?.isRead, false)

        // New mail, found as the watch finds it.
        server.arrive(Server.Letter(from: Server.owner, to: [Server.owner], subject: "A new one",
                                    date: Server.newestDate.addingTimeInterval(3_600),
                                    text: "New.\r\n", messageID: "<b106-new@example.com>"),
                      in: [Server.inbox, Server.allMail])
        let watched = await list.watched
        let news = try await repository.news(in: "inbox", known: watched, searchingAnyway: false)
        XCTAssertEqual(news.arrived.count, 1)
        _ = await list.take(news, fromNewest: true)
        _ = await list.putNewsOn(atTop: true, searching: false, ticked: false, touching: false)
        row = await list.letter(letter.id)
        XCTAssertEqual(row?.isRead, false)

        XCTAssertTrue(server.log.contains { $0.verb == "NOOP" })
        XCTAssertFalse(server.log.contains { $0.command.contains("+FLAGS") },
                       server.log.map(\.command).joined(separator: "\n"))
        XCTAssertEqual(server.log.filter { $0.verb == "UID STORE" }.map(\.command),
                       ["UID STORE \(uid(letter.id)) -FLAGS.SILENT (\\Seen)"])
        XCTAssertFalse(server.flags(uid: uid(letter.id), in: Server.inbox).contains("\\Seen"))
    }

    // MARK: - Read from the source

    /// The Flag button presents an action sheet anchored on its own bar
    /// item, with `FlagMenu`'s items for the letter the toolbar acts on,
    /// read as the dot on the list's row says, and Cancel. An item does
    /// nothing once the pane has moved on, and is greyed while its write on
    /// the letter is on its way.
    func testTheFlagButtonOpensASheetAnchoredOnItsItem() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        let tapped = try section(of: code, from: "@objc private func flagTapped() {",
                                 to: "private func choose(")
        for wiring in [
            "guard let s = summary else { return }",
            "let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)",
            "sheet.popoverPresentationController?.barButtonItem = actionItems[.flag]",
            "let dot = dotOnList?(s)",
            "let items = FlagMenu.items(flagged: flag?.flagged ?? s.isFlagged, "
                + "read: dot?.read ?? (markedUnreadHere != s.id), "
                + "local: LocalDraft.key(ofRow: s.id) != nil, in: foldersForJunk?(s) ?? FlagMenu.Folders())",
            "let action = UIAlertAction(title: item.title, style: .default) { [weak self] _ in "
                + "guard let self, self.summary?.id == s.id else { return } self.choose(item) }",
            "case .flag, .unflag: action.isEnabled = !writes.flagOnItsWay(s.id)",
            "case .markAsUnread, .markAsRead: "
                + "action.isEnabled = !writes.readOnItsWay(s.id) && dot?.onItsWay != true",
            "sheet.addAction(UIAlertAction(title: FlagMenu.cancel, style: .cancel))",
            "present(sheet, animated: true)",
        ] {
            XCTAssertTrue(tapped.contains(wiring), wiring)
        }
        for never in ["startFlag", "startRead", "setFlag(", "setRead(", "setFlagged(", "markHere(",
                      "performed("] {
            XCTAssertFalse(tapped.contains(never), "nothing is written at the first tap: \(never)")
        }
        XCTAssertTrue(code.contains(".flag: (\"flag\", #selector(flagTapped)),"))

        let chosen = try section(of: code, from: "private func choose(", to: "private func setFlag(")
        for line in ["case .flag: setFlag(true)", "case .unflag: setFlag(false)",
                     "case .markAsUnread: setRead(false)", "case .markAsRead: setRead(true)"] {
            XCTAssertTrue(chosen.contains(line), line)
        }
    }

    /// Which read item the sheet offers is the list's to say, by the dot on
    /// its row, handed from the container, which holds the list, read at
    /// the tap; the pane's own mark only where the list has no row that is
    /// the letter, and never the pane's `summary.isRead`, which it was
    /// handed before the tap that opened the letter marked it read.
    func testTheReadItemFollowsTheDotOnTheListsRow() throws {
        let pane = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(pane.contains("var dotOnList: ((MessageSummary) -> FlagMenu.Dot?)?"))
        let tapped = try section(of: pane, from: "@objc private func flagTapped() {",
                                 to: "private func choose(")
        XCTAssertTrue(tapped.contains("read: dot?.read ?? (markedUnreadHere != s.id)"), tapped)
        XCTAssertFalse(tapped.contains("read: markedUnreadHere != s.id"))
        XCTAssertFalse(tapped.contains("s.isRead"))
        XCTAssertEqual(count("dotOnList", in: pane), 2, "declared, and asked in the sheet alone")

        let root = try source("UI/RootViewController.swift")
        XCTAssertTrue(root.contains(
            "detail.dotOnList = { [weak self] letter in self?.list.letters.dot(on: letter) }"))
    }

    /// Flag and Unflag are the Flag button's write as it was: set at once
    /// in the pane, sent once per letter at a time, put back and said if
    /// refused.
    func testFlagAndUnflagWriteAsTheButtonDid() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        let flag = try section(of: code, from: "private func setFlag(_ flagged: Bool) {",
                               to: "private func setRead(")
        XCTAssertTrue(flag.contains(
            "guard let s = summary, writes.startFlag(s.id) else { return } setFlagged(flagged, on: s.id) "
            + "Task { @MainActor in let refused = await self.performed(.flag(flagged), on: s) "
            + "self.writes.flagAnswered(s.id) guard let refused else { return } "
            + "self.setFlagged(s.isFlagged, on: s.id) ErrorPresenter.show(reaching: refused, on: self) } }"),
                      flag)
    }

    /// Mark as Unread and Mark as Read: once per letter at a time, the
    /// pane's own mark at the tap, the letter handed as the pane has it,
    /// put back and said if refused.
    func testAReadMarkFromThePaneIsSentAsThePaneHasTheLetter() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        let read = try section(of: code, from: "private func setRead(_ read: Bool) {",
                               to: "private func markHere(")
        XCTAssertTrue(read.contains(
            "guard let s = summary, writes.startRead(s.id) else { return } markHere(read, on: s.id) "
            + "var letter = s letter.isRead = !read Task { @MainActor in "
            + "let refused = await self.performed(.read(read), on: letter) "
            + "self.writes.readAnswered(s.id) guard let refused else { return } "
            + "self.markHere(!read, on: s.id) ErrorPresenter.show(reaching: refused, on: self) } }"),
                      read)
        let here = try section(of: code, from: "private func markHere(", to: "private func performed(")
        for line in ["if read { if markedUnreadHere == id { markedUnreadHere = nil } } "
                        + "else if summary?.id == id { markedUnreadHere = id }",
                     "if var row = threadSummaries[id] { row.isRead = read threadSummaries[id] = row }"] {
            XCTAssertTrue(here.contains(line), line)
        }
    }

    /// The pane's own read mark is forgotten whenever it shows anything
    /// else, and when the letter's line marks it read again.
    func testThePanesOwnMarkIsForgottenWhenItShowsAnotherLetter() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(code.contains("private var markedUnreadHere: String?"))
        for start in ["func showEmpty() {", "func show(summary: MessageSummary) {",
                      "func show(thread: MessageThread, completing: UInt64?) {"] {
            let whole = try section(of: code, from: start, to: "placeholder.")
            XCTAssertTrue(whole.contains("markedUnreadHere = nil"), start)
        }
        let tapped = try section(of: code, from: "func userContentController(",
                                 to: "private func markOpened(")
        XCTAssertTrue(tapped.contains(
            "document.setOpen(opened, id) guard opened else { return } loadBody(for: id, focus: true) "
            + "if markedUnreadHere == id { markedUnreadHere = nil } markOpened(id) }"), tapped)
        XCTAssertEqual(count("markedUnreadHere = ", in: code), 6,
                       "the three shows, the line, and the pane's own mark both ways")
    }

    /// No read STORE without a tap: the only ways to `setRead` are the tap
    /// on a row (`markReadIfNeeded`, through `sendRead`), the line opened in
    /// a stack (`markOpened`, through `markRead`), Edit mode's Mark
    /// (`applyRead`) and the Flag button's sheet (`PaneActions`). And each
    /// is reached from its tap alone: nothing in a redraw, a reload, a
    /// letter landing or new mail calls any of them.
    func testNoReadMarkIsSentWithoutATap() throws {
        var calls = 0
        for file in try sources() {
            calls += count("setRead(", in: try source(file)) - count("func setRead(", in: try source(file))
        }
        // The list's three; the sheet's two items, in the pane's `choose`;
        // `PaneActions.send`'s; and the list's own `setRead(_:on:)`, the dot
        // at the tap, called from `PaneActions.start`.
        XCTAssertEqual(calls, 7)
        let pane = try source("UI/MessageDetailViewController.swift")
        XCTAssertEqual(count("setRead(", in: pane), 3, "declared, and the sheet's two items")

        let list = try source("UI/MessageListViewController.swift")
        XCTAssertEqual(count("markReadIfNeeded(", in: list), 6,
                       "its two declarations, the overload, the two opens and markRead")
        XCTAssertEqual(count("sendRead(", in: list), 2)
        let root = try source("UI/RootViewController.swift")
        XCTAssertEqual(count("markRead(", in: root), 1)
        XCTAssertTrue(root.contains("detail.onLetterOpened = { [weak self] letter in self?.list.markRead(letter) }"))

        XCTAssertEqual(count("onLetterOpened?(", in: pane), 1)
        XCTAssertEqual(count("markOpened(", in: pane), 2, "declared, and called from the line's tap")
        let tapped = try section(of: pane, from: "func userContentController(",
                                 to: "private func markOpened(")
        XCTAssertTrue(tapped.contains("document.setOpen(opened, id) guard opened else { return } "
                                      + "loadBody(for: id, focus: true)"))
        XCTAssertTrue(tapped.contains("markOpened(id)"))
        for redraw in [("private func drawAgain() {", "@objc private func appBecameActive()"),
                       ("func takeArrivals(from threads: [MessageThread]) {", "private func renderLoadFailure()"),
                       ("private func settleBody(", "private func drawBody("),
                       ("private func focusLetter(", "private func keepPlace(")] {
            let code = try section(of: pane, from: redraw.0, to: redraw.1)
            for never in ["markOpened", "onLetterOpened", "setRead", ".read("] {
                XCTAssertFalse(code.contains(never), "\(redraw.0): \(never)")
            }
        }
    }

    /// Edit mode's Mark sheet is as it was, and its bookkeeping is the
    /// function the pane's Mark calls once the server has it.
    func testEditModesMarkSheetIsUnchanged() throws {
        let list = try source("UI/MessageListViewController.swift")
        let sheet = try section(of: list, from: "@objc private func markSelected() {",
                                to: "private func applyRead(")
        XCTAssertTrue(sheet.contains(
            "let chosen = onServer(selectedMessages) guard !chosen.isEmpty else { return } "
            + "let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet) "
            + "sheet.popoverPresentationController?.barButtonItem = markItem "
            + "sheet.addAction(UIAlertAction(title: \"Mark as Unread\", style: .default) { "
            + "[weak self] _ in self?.applyRead(false, to: chosen) }) "
            + "sheet.addAction(UIAlertAction(title: \"Mark as Read\", style: .default) { "
            + "[weak self] _ in self?.applyRead(true, to: chosen) }) "
            + "sheet.addAction(UIAlertAction(title: \"Cancel\", style: .cancel)) present(sheet, animated: true)"),
                      sheet)
        let apply = try section(of: list, from: "private func applyRead(", to: "@objc private func moveSelected()")
        XCTAssertTrue(apply.contains("for m in chosen where m.isRead != read {"))
        XCTAssertTrue(apply.contains("self.letters.reading(m, read: read) self.letters.readTaken(m, read: read) }"))
        XCTAssertFalse(apply.contains("self.letters.unread("))
        XCTAssertFalse(list.contains("FlagMenu"))
    }

    // MARK: - The bookkeeping, on the list alone

    /// What a read mark taken does to the counts, for Edit mode and the
    /// pane alike: one back on for a letter the list had as read, one off,
    /// once, for one it had unread, and nothing for one it had so already.
    @MainActor
    func testAReadMarkTakenIsBilledOnlyWhereTheListHadTheLetterOtherwise() {
        var read = summary(id: "1/1", counted: ["INBOX", "[Gmail]/All Mail"])
        read.isRead = true
        let unread = summary(id: "1/2", counted: ["INBOX"])
        let list = ListLetters()
        let counts = CountChanges()
        list.onUnreadCountChanged = { counts.record($0, $1) }
        _ = list.fetchedAfresh([read, unread])

        list.reading(read, read: false)
        list.readTaken(read, read: false)
        XCTAssertEqual(counts.restored, [["INBOX", "[Gmail]/All Mail"]])
        XCTAssertEqual(list.letter("1/1")?.isRead, false)

        list.reading(unread, read: true)
        list.readTaken(unread, read: true)
        list.readTaken(unread, read: true)
        XCTAssertEqual(counts.billed, [["INBOX"]], "off once")

        // Had so already: the STORE taken, nothing counted.
        let now = list.letter("1/2")!
        list.reading(now, read: true)
        list.readTaken(now, read: true)
        let unreadNow = list.letter("1/1")!
        list.reading(unreadNow, read: false)
        list.readTaken(unreadNow, read: false)
        XCTAssertEqual(counts.billed, [["INBOX"]])
        XCTAssertEqual(counts.restored, [["INBOX", "[Gmail]/All Mail"]])

        // Refused: the dot back, and nothing counted.
        let again = list.letter("1/1")!
        list.setRead(true, on: again)
        XCTAssertEqual(list.letter("1/1")?.isRead, true)
        list.readRefused(again)
        XCTAssertEqual(list.letter("1/1")?.isRead, false)
        XCTAssertEqual(counts.billed, [["INBOX"]])
    }

    /// The pane's marks redraw the rows at the tap and at a refusal, as a
    /// Flag does; a mark taken changes nothing on screen.
    @MainActor
    func testThePanesMarksRedrawTheRows() {
        var read = summary(id: "1/1")
        read.isRead = true
        let list = ListLetters()
        var changes: [ListChange] = []
        list.changed = { changes.append($0) }
        _ = list.fetchedAfresh([read])

        list.setRead(false, on: read)
        XCTAssertEqual(changes, [.marked])
        list.readRefused(read)
        XCTAssertEqual(changes, [.marked, .marked])
        list.setRead(false, on: read)
        list.readTaken(read, read: false)
        XCTAssertEqual(changes, [.marked, .marked, .marked])
    }

    // MARK: - Which read item, by the dot on the list's row

    /// The sheet offers Mark as Unread or Mark as Read as the dot on the
    /// list's row says, as Mail's item follows the letter, and not as the
    /// pane has it: the dot gone at the tap that opened the letter, while
    /// the pane's copy, handed before, still says unread; back when the
    /// server refuses that mark; back again at Edit mode's Mark as Unread
    /// on the letter open in the pane, which leaves the pane as it was; and
    /// gone at Edit mode's Mark as Read after the pane's own Mark as
    /// Unread. On its way while a read mark made on the letter, or on its
    /// copy under another mailbox's id, has not been answered.
    @MainActor
    func testTheSheetGoesByTheDotOnTheListsRow() {
        var opened = summary(id: "1/1", counted: ["INBOX"])
        opened.gmailMessageID = 11
        let (list, _) = makeList(folder: [opened])
        XCTAssertEqual(list.dot(on: opened), FlagMenu.Dot(read: false, onItsWay: false))

        // The tap that opened it, its STORE on the wire, then refused.
        list.reading(opened, read: true)
        XCTAssertEqual(list.dot(on: opened), FlagMenu.Dot(read: true, onItsWay: true))
        list.readAnswered(opened.id, landed: false)
        XCTAssertEqual(list.dot(on: opened), FlagMenu.Dot(read: false, onItsWay: false),
                       "refused: Mark as Read, though the pane opened it")
        // Opened again, and taken.
        list.reading(opened, read: true)
        list.readAnswered(opened.id, landed: true)
        XCTAssertEqual(list.dot(on: opened), FlagMenu.Dot(read: true, onItsWay: false))

        // Edit mode's Mark as Unread on it, made once its STORE has landed.
        let read = list.letter(opened.id)!
        list.reading(read, read: false)
        list.readTaken(read, read: false)
        XCTAssertEqual(list.dot(on: opened), FlagMenu.Dot(read: false, onItsWay: false),
                       "Edit mode's Mark as Unread: Mark as Read")

        // The pane's own Mark as Read, on its way, then taken.
        let started = PaneActions.start(.read(true), on: opened, inFolderWithRole: .inbox, list: list)
        XCTAssertEqual(list.dot(on: opened), FlagMenu.Dot(read: true, onItsWay: true))
        PaneActions.finish(started, failure: nil, requestSweep: {})
        XCTAssertEqual(list.dot(on: opened), FlagMenu.Dot(read: true, onItsWay: false))
        // Its Mark as Unread, then Edit mode's Mark as Read.
        PaneActions.finish(PaneActions.start(.read(false), on: opened, inFolderWithRole: .inbox,
                                             list: list),
                           failure: nil, requestSweep: {})
        XCTAssertEqual(list.dot(on: opened)?.read, false)
        let unread = list.letter(opened.id)!
        list.reading(unread, read: true)
        list.readTaken(unread, read: true)
        XCTAssertEqual(list.dot(on: opened), FlagMenu.Dot(read: true, onItsWay: false),
                       "Edit mode's Mark as Read: Mark as Unread")

        // Read from its All Mailboxes hit: the Inbox's row has the mark on
        // its way too, and the hit's search ended, the list has no row
        // that is the hit.
        var hit = MessageSummary(id: "9/40", mailboxID: "[Gmail]/All Mail", sender: opened.sender,
                                 subject: opened.subject, preview: "", date: opened.date,
                                 isRead: false, isFlagged: false, countedFolderIDs: ["INBOX"])
        hit.gmailMessageID = opened.gmailMessageID
        list.showResults([hit])
        list.reading(hit, read: true)
        XCTAssertEqual(list.dot(on: hit), FlagMenu.Dot(read: true, onItsWay: true))
        XCTAssertEqual(list.dot(on: opened)?.onItsWay, true, "made on its copy")
        list.readAnswered(hit.id, landed: true)
        XCTAssertEqual(list.dot(on: opened)?.onItsWay, false)
        list.endSearch()
        XCTAssertNil(list.dot(on: hit), "the pane's own, for a hit after its search")
    }

    /// Flag or Unflag as the flag on the list's row says, and greyed while
    /// a Flag on the letter is on its way, as the read item goes by the
    /// dot: a drag's Flag on the row of the letter open in the pane
    /// (B-156) changes the row and not the pane, which then offered Flag
    /// on a flagged letter, and its Flag went beside the drag's STORE.
    @MainActor
    func testTheFlagItemFollowsTheFlagOnTheListsRow() throws {
        var opened = summary(id: "1/1", counted: ["INBOX"])
        opened.gmailMessageID = 11
        let (list, _) = makeList(folder: [opened])
        XCTAssertEqual(list.flag(on: opened), FlagMenu.Flag(flagged: false, onItsWay: false))

        // A drag's Flag on its row, on its way, then taken.
        let started = PaneActions.start(.flag(true), on: opened, inFolderWithRole: .inbox,
                                        list: list)
        XCTAssertEqual(list.flag(on: opened), FlagMenu.Flag(flagged: true, onItsWay: true))
        PaneActions.finish(started, failure: nil, requestSweep: {})
        XCTAssertEqual(list.flag(on: opened), FlagMenu.Flag(flagged: true, onItsWay: false))
        XCTAssertFalse(opened.isFlagged, "the pane's copy, as it was")
        XCTAssertNil(list.flag(on: summary(id: "1/8")), "no row under its id: the pane's own")

        let pane = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(pane.contains("var flagOnList: ((MessageSummary) -> FlagMenu.Flag?)?"))
        let tapped = try section(of: pane, from: "@objc private func flagTapped() {",
                                 to: "private func choose(")
        for line in [
            "let flag = flagOnList?(s)",
            "FlagMenu.items(flagged: flag?.flagged ?? s.isFlagged, ",
            "case .flag, .unflag: action.isEnabled = !writes.flagOnItsWay(s.id) "
                + "&& flag?.onItsWay != true",
        ] {
            XCTAssertTrue(tapped.contains(line), line)
        }
        let root = try source("UI/RootViewController.swift")
        XCTAssertTrue(root.contains(
            "detail.flagOnList = { [weak self] letter in self?.list.letters.flag(on: letter) }"))
    }

    /// No dot where the row under the letter's id is another letter now:
    /// one kept on the iPad that a listing has put another letter under
    /// (`ListEdit.sameLetter`). The pane's own then, and not the other
    /// letter's.
    @MainActor
    func testNoDotFromARowThatIsAnotherLetter() {
        var keptRow = summary(id: "1/7")
        keptRow.gmailMessageID = 70
        keptRow.isRead = true
        var another = summary(id: "1/7")
        another.gmailMessageID = 71
        let (list, _) = makeList(folder: [another])
        XCTAssertNil(list.dot(on: keptRow))
        XCTAssertNil(list.dot(on: summary(id: "1/8")), "no row under its id")
        var noID = keptRow
        noID.gmailMessageID = nil
        XCTAssertEqual(list.dot(on: noID), FlagMenu.Dot(read: false, onItsWay: false),
                       "a row with no Gmail id is taken for the letter, as everywhere")
    }

    // MARK: - Helpers

    private var kept: URL { root.appendingPathComponent("Kept", isDirectory: true) }

    private func makeShelf() -> MailShelf {
        MailShelf(root: kept, address: server.username, host: server.account.imapHost)
    }

    private func makeRepository(shelf: MailShelf? = nil) -> IMAPMailRepository {
        IMAPMailRepository(account: server.account, password: server.password,
                           transport: server.transportFactory, recipients: book,
                           shelf: shelf ?? keptShelf(for: server.account))
    }

    /// The launch before: the Inbox listed and kept on the iPad.
    private func earlierLaunch() async throws {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.listMailboxes()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        shelf.flush()
    }

    @MainActor
    private func makeList(folder: [MessageSummary]) -> (ListLetters, CountChanges) {
        let list = ListLetters()
        let counts = CountChanges()
        list.onUnreadCountChanged = { counts.record($0, $1) }
        _ = list.fetchedAfresh(folder)
        return (list, counts)
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

    private func summary(id: String, counted: [String] = []) -> MessageSummary {
        MessageSummary(id: id, mailboxID: "inbox", sender: "Sam Example <sam@example.com>",
                       subject: "Letter", preview: "", date: Server.newestDate,
                       isRead: false, isFlagged: false, countedFolderIDs: counted)
    }

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources", isDirectory: true)
    }

    /// Every Swift file of the app's three targets, by its path under
    /// `Sources/`.
    private func sources() throws -> [String] {
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sourceRoot,
                                                                  includingPropertiesForKeys: nil))
        let base = sourceRoot.standardizedFileURL.path + "/"
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { String($0.standardizedFileURL.path.dropFirst(base.count)) }
            .sorted()
    }

    /// The file's code with its comment lines dropped and its spacing made
    /// single, so a line is found however it is wrapped. `path` is under
    /// `Sources/Blackmail/`, or under `Sources/` with its target.
    private func source(_ path: String) throws -> String {
        let direct = sourceRoot.appendingPathComponent(path)
        let url = FileManager.default.fileExists(atPath: direct.path)
            ? direct : sourceRoot.appendingPathComponent("Blackmail/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    private func section(of code: String, from start: String, to end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start), start)
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex), end)
        return String(code[from.lowerBound..<to.lowerBound])
    }

    private func count(_ needle: String, in code: String) -> Int {
        code.components(separatedBy: needle).count - 1
    }
}

/// What the list says to the folder counts, written down.
@MainActor
private final class CountChanges {
    /// The folders each letter billed as read came off, one entry per letter.
    private(set) var billed: [[String]] = []
    /// The folders each letter marked unread again went back on.
    private(set) var restored: [[String]] = []

    func record(_ folders: [String], _ delta: Int) {
        if delta < 0 { billed.append(folders) } else { restored.append(folders) }
    }
}
