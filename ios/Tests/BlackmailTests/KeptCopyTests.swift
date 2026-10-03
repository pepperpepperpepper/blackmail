import XCTest
@testable import Blackmail

/// D-016: a copy of his mail is kept on the iPad. Phase 0, what it rests
/// on: nothing of his mail is written into the connection log beside the
/// wire, and every row carries the Gmail message id a kept row is keyed
/// on, from the FETCH the list already sends. Phase 1, the kept folders and
/// first pages (`MailShelf`), over the shipping repository and client and a
/// shelf in a directory of the test's own: what a launch draws before it has
/// sent anything, with a connection and without; which listings replace a
/// kept page and which writes patch it; the copy thrown away when it is not
/// this mailbox's; a write on a kept row vouched for first; every write and
/// every letter opened naming its row's letter, so that a kept row still
/// drawn after the copy is thrown away writes and shows nothing, one the
/// fresh page lacks is asked about once, and a row this launch has brought
/// goes as it always did; a launch that sends what it always did; and
/// nothing kept in the log.
///
/// The screens are UIKit and not on the host. What they do with the shelf
/// is `ListOpening.kept`, `ListLetters`, `KeptSwap` and `UpdatedLine`, as
/// the message list calls them.
final class KeptCopyTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "KeptCopyTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var clock: ManualClock!
    /// A directory of this test's own, holding `Kept/` as Application
    /// Support holds it in the app.
    private var root: URL!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        clock = ManualClock()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("KeptCopyTests-\(UUID().uuidString)", isDirectory: true)
        Diagnostics.clear()
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        // Every shelf over it ends, so a write still queued lands nowhere.
        if let root {
            MailShelf.wipe(root: kept)
            try? FileManager.default.removeItem(at: root)
        }
        server = nil
        book = nil
        clock = nil
        root = nil
        super.tearDown()
    }

    private var kept: URL { root.appendingPathComponent("Kept", isDirectory: true) }

    /// The shelf a launch makes, over whatever earlier ones left.
    private func makeShelf() -> MailShelf {
        let clock = self.clock!
        return MailShelf(root: kept, address: server.username, host: server.account.imapHost,
                         now: { clock.now() })
    }

    private func makeRepository(shelf: MailShelf? = nil,
                                account: MailAccount? = nil) -> IMAPMailRepository {
        let clock = self.clock!
        return IMAPMailRepository(account: account ?? server.account, password: server.password,
                                  transport: server.transportFactory, recipients: book,
                                  now: { clock.now() }, shelf: shelf)
    }

    private var verbs: [String] { server.log.map(\.verb) }

    /// The `index`th command logged, or "none".
    private func command(_ index: Int) -> String {
        index < server.log.count ? server.log[index].command : "none"
    }

    /// An earlier launch, as it leaves the iPad: the folders swept, the
    /// Inbox listed from the top and its previews fetched, and each of
    /// `others` listed from the top, then everything written, as going into
    /// the background writes it. The Inbox's rows as he saw them.
    @discardableResult
    private func earlierLaunch(listing others: [String] = []) async throws -> [MessageSummary] {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.listMailboxes()
        var inbox = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let previews = try await repository.previews(for: inbox.map(\.id), in: "inbox")
        for i in inbox.indices { inbox[i].preview = previews[inbox[i].id] ?? "" }
        for folder in others {
            _ = try await repository.listMessages(in: folder, beforeUID: nil, limit: 50)
        }
        shelf.flush()
        return inbox
    }

    /// Times said in UTC, as `FeedbackTests` says them.
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func said(_ line: UpdatedLine, at now: Date) -> String {
        line.text(now: now, calendar: Self.utc, locale: Locale(identifier: "en_GB"))
    }

    private func uid(_ id: String) -> UInt32 { UInt32(id.split(separator: "/").last ?? "")! }

    /// Waits, a millisecond at a time and never for more than a second,
    /// until `condition` holds.
    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    /// What `body` threw, failing the test if it threw nothing.
    private func refusal(file: StaticString = #filePath, line: UInt = #line,
                         _ body: () async throws -> Void) async -> Error? {
        do {
            try await body()
            XCTFail("it went", file: file, line: line)
            return nil
        } catch {
            return error
        }
    }

    private static let notKept = MailShelf.NotTheKeptLetter()

    // MARK: - The connection log

    /// A listing leaves no subject and no correspondent of any letter in
    /// the folder in the connection log, from the top or a page down,
    /// except in the server's own answers, whose ENVELOPEs carry them and
    /// which are what the log is for. The log is made to be copied out to
    /// whoever is helping, and every send writes it to a file. The session
    /// is still pinned in numbers by SESSION-IDENT, which is what the
    /// device checks of B-045 read, and the listing costs the commands it
    /// did.
    func testAListingLeavesNoSubjectOrCorrespondentInTheLogBesideTheWire() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        server.clearLog()

        let top = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(verbs, ["SELECT", "UID SEARCH", "UID FETCH"])
        server.clearLog()
        let next = try await repository.listMessages(in: "inbox", beforeUID: top.last?.id, limit: 50)
        XCTAssertEqual(verbs, ["UID FETCH"])
        XCTAssertEqual(top.count + next.count, 100)

        // His correspondence: every subject, and every name and address on
        // a letter but his own, which is the account's and is on LOGIN.
        let letters = server.uids(in: Server.inbox).compactMap {
            server.letter(uid: $0, in: Server.inbox)
        }
        XCTAssertEqual(letters.count, 120)
        var correspondence: Set<String> = []
        for letter in letters {
            correspondence.insert(letter.subject)
            for person in [letter.from] + letter.to + letter.cc where person != Server.owner {
                correspondence.insert(person.address)
                if let name = person.name { correspondence.insert(name) }
            }
        }

        let entries = Diagnostics.entries
        let beside = entries.filter { $0.direction != .received }
        XCTAssertFalse(beside.isEmpty)
        let leaks = beside.filter { entry in correspondence.contains { entry.text.contains($0) } }
        XCTAssertEqual(leaks.count, 0, leaks.prefix(3).map(\.text).joined(separator: "\n"))

        // Not vacuous: the server's answers are in the same log, and they
        // do carry the letters, as the wire log is meant to.
        XCTAssertTrue(entries.contains {
            $0.direction == .received && $0.text.contains(top[0].subject)
        })

        // One a page, each naming the page's first row: its conversation,
        // and the letter itself by the id the server gave it.
        let ident = beside.filter { $0.text.hasPrefix("SESSION-IDENT") }.map(\.text)
        let validity = server.uidValidity(of: Server.inbox)
        XCTAssertEqual(ident, try [top, next].map { page in
            let first = try XCTUnwrap(page.first)
            let thread = try XCTUnwrap(first.threadID)
            let letter = try XCTUnwrap(server.gmailMessageID(uid: uid(first.id), in: Server.inbox))
            return "SESSION-IDENT folder=INBOX uidv=\(validity) exists=120 uids=120 "
                + "first-row=\(thread) msgid=\(letter)"
        })
    }

    // MARK: - What a kept letter is keyed on

    /// Every row carries Gmail's id for the letter, from the summary FETCH
    /// the list already sends, and the listing costs no more commands for
    /// it. The id is the letter's and not the folder's: the Inbox and All
    /// Mail give one letter two UIDs, and this one id.
    func testEveryRowCarriesGmailsMessageIDTheSameFromEveryFolder() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        server.clearLog()

        let inbox = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(verbs, ["SELECT", "UID SEARCH", "UID FETCH"])
        let fetch = try XCTUnwrap(server.log.last?.command)
        XCTAssertTrue(fetch.hasSuffix(" (UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODYSTRUCTURE "
                                      + "X-GM-LABELS X-GM-THRID X-GM-MSGID)"), fetch)
        let ids = inbox.compactMap(\.gmailMessageID)
        XCTAssertEqual(ids.count, 50)
        XCTAssertEqual(Set(ids).count, 50)
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        // The number the server gave the letter, and not its thread's.
        // Every letter here is a conversation of its own, so a thread id
        // would pass for a letter's on uniqueness alone; on Gmail every
        // reply in a conversation shares one, and a copy keyed on it would
        // keep one letter of each.
        for row in inbox {
            XCTAssertEqual(row.gmailMessageID, server.gmailMessageID(uid: uid(row.id), in: Server.inbox),
                           row.subject)
        }

        server.clearLog()
        let allMail = try await repository.listMessages(in: Server.allMail, beforeUID: nil, limit: 50)
        XCTAssertEqual(verbs, ["SELECT", "UID SEARCH", "UID FETCH"])
        // The Inbox's subjects are one to a letter.
        let there = Dictionary(allMail.map { ($0.subject, $0) }, uniquingKeysWith: { first, _ in first })
        var both = 0
        for row in inbox {
            guard let same = there[row.subject] else { continue }
            both += 1
            XCTAssertNotEqual(same.id, row.id, row.subject)
            XCTAssertEqual(same.gmailMessageID, row.gmailMessageID, row.subject)
        }
        XCTAssertGreaterThan(both, 40)
    }

    /// A server without Gmail's extension is not asked for the id, as it
    /// is not asked for the labels or the thread: one item it does not
    /// know and it refuses the whole FETCH, and the page with it. Its rows
    /// have no id.
    func testAServerWithoutGmailsExtensionIsNotAskedForTheIDAndItsRowsHaveNone() async throws {
        server.withheldCapabilities = ["X-GM-EXT-1"]
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        server.clearLog()

        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(rows.count, 50)
        XCTAssertEqual(verbs, ["SELECT", "UID SEARCH", "UID FETCH"])
        let fetch = try XCTUnwrap(server.log.last?.command)
        XCTAssertTrue(fetch.hasSuffix(" (UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODYSTRUCTURE)"),
                      fetch)
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        XCTAssertEqual(rows.compactMap(\.gmailMessageID), [])
        XCTAssertEqual(rows.compactMap(\.threadID), [])
    }

    // MARK: - Phase 1: what a launch draws

    /// A launch after an earlier one: the Inbox kept then, previews and all,
    /// is what the list draws before anything has been sent, not a
    /// connection begun, under "Checking for Mail…". The first page lands
    /// in its place, with a letter that came while the app was closed on
    /// top, and only that letter's preview is still to fetch; the line says
    /// "Updated Just Now". A list opened to jump to a day, and the Outbox,
    /// draw nothing kept.
    @MainActor
    func testALaunchDrawsTheKeptInboxBeforeAnythingIsSentAndTheFirstPageReplacesIt() async throws {
        let before = try await earlierLaunch()
        let arrived = try XCTUnwrap(server.arrive(
            Server.Letter(from: Server.sam, to: [Server.owner], subject: "While the iPad slept",
                          date: Server.newestDate.addingTimeInterval(3_600),
                          text: "Came in overnight.\r\n", messageID: "<overnight@example.org>"),
            in: [Server.inbox, Server.allMail])[Server.inbox])
        let sent = server.log.count
        let connections = server.connectionsBegun
        clock.advance(by: 86_400)

        let repository = makeRepository(shelf: makeShelf())
        let list = ListLetters()
        var line = UpdatedLine()
        let page = try XCTUnwrap(ListOpening.kept(for: .inboxBeforeListing, jumpingTo: nil,
                                                  from: repository.shelf))
        list.showKept(page.rows)
        line.showingKept(since: page.keptAt)

        XCTAssertEqual(server.log.count, sent, "nothing sent to draw it")
        XCTAssertEqual(server.connectionsBegun, connections, "nor a connection begun")
        XCTAssertEqual(list.shown.map(\.id), before.map(\.id))
        XCTAssertEqual(list.shown.map(\.preview), before.map(\.preview))
        XCTAssertTrue(list.shown.allSatisfy { !$0.preview.isEmpty })
        XCTAssertEqual(list.shown.map(\.mailboxID), Array(repeating: "inbox", count: 50))
        XCTAssertEqual(said(line, at: clock.now()), "Checking for Mail…")
        XCTAssertNil(ListOpening.kept(for: .inboxBeforeListing, jumpingTo: Server.newestDate,
                                      from: repository.shelf), "a jump draws its day")
        XCTAssertNil(ListOpening.kept(for: Outbox.mailbox(holding: 1), jumpingTo: nil,
                                      from: repository.shelf), "the Outbox is its own")

        let first = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(KeptSwap.swap(atTop: true, searching: false, ticked: false, touching: false), .top)
        let unpreviewed = list.fetchedAfresh(first)
        line.succeeded(at: clock.now())

        XCTAssertFalse(list.fromShelf)
        XCTAssertEqual(list.shown.first.map { uid($0.id) }, arrived)
        XCTAssertEqual(list.shown.map(\.id), first.map(\.id))
        XCTAssertEqual(unpreviewed.map { uid($0.id) }, [arrived], "only the new letter's preview")
        XCTAssertEqual(said(line, at: clock.now()), "Updated Just Now")
    }

    /// No connection at launch: the kept Inbox and every folder opened
    /// before draw their kept pages, a folder never opened draws nothing,
    /// the folder pane has the counts the last sweep gave, and once the
    /// first page has failed the line says how old the kept rows are, with
    /// "No Connection" under it. The rows stay.
    @MainActor
    func testWithNoConnectionAtLaunchTheKeptPagesStayAndTheLineSaysHowOld() async throws {
        let before = try await earlierLaunch(listing: [Server.sent])
        let keptAt = clock.now()
        clock.advance(by: 86_400)

        // Refused at the socket, as with no network: nothing to reach.
        var unreachable = server.account
        unreachable.imapPort = 465
        let repository = makeRepository(shelf: makeShelf(), account: unreachable)
        let shelf = try XCTUnwrap(repository.shelf)

        let folders = try XCTUnwrap(shelf.folders)
        XCTAssertEqual(folders.first { $0.role == .inbox }?.unreadCount, 6)
        XCTAssertEqual(folders.map(\.id).filter { $0 == Server.sent }, [Server.sent])

        let list = ListLetters()
        var line = UpdatedLine()
        let page = try XCTUnwrap(ListOpening.kept(for: .inboxBeforeListing, jumpingTo: nil, from: shelf))
        list.showKept(page.rows)
        line.showingKept(since: page.keptAt)
        XCTAssertEqual(page.keptAt, keptAt)
        do {
            _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
            XCTFail("there is no connection")
        } catch {
            line.failed((error as? MailError) ?? .cannotConnect)
        }
        XCTAssertEqual(server.connectionsOpened, 1, "the earlier launch's alone")
        XCTAssertTrue(list.fromShelf)
        XCTAssertEqual(list.shown.map(\.id), before.map(\.id))
        XCTAssertEqual(said(line, at: clock.now()), "Updated Yesterday\nNo Connection")
        XCTAssertEqual(said(line, at: keptAt.addingTimeInterval(2 * 3_600)),
                       "Updated at 14:13\nNo Connection")

        let sentFolder = try XCTUnwrap(folders.first { $0.id == Server.sent })
        let sentPage = try XCTUnwrap(ListOpening.kept(for: sentFolder, jumpingTo: nil, from: shelf))
        XCTAssertEqual(sentPage.rows.count, server.uids(in: Server.sent).count)
        XCTAssertEqual(Set(sentPage.rows.map(\.mailboxID)), [Server.sent])
        let trash = try XCTUnwrap(folders.first { $0.role == .trash })
        XCTAssertNil(ListOpening.kept(for: trash, jumpingTo: nil, from: shelf), "never opened")
    }

    // MARK: - Phase 1: which listings replace a kept page

    /// A listing from the top keeps the folder's page, and the next one
    /// replaces it whole: a letter that came is on it and a letter taken out
    /// elsewhere is not. A page further down, a day jumped to and a search
    /// keep nothing.
    func testOnlyAListingFromTheTopReplacesTheKeptPageAndItReplacesItWhole() async throws {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.folders()
        let top = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        func keptIDs(_ shelf: MailShelf) -> [String]? { shelf.page(of: "inbox")?.rows.map(\.id) }
        XCTAssertEqual(keptIDs(shelf), top.map(\.id))

        let below = try await repository.listMessages(in: "inbox", beforeUID: top.last?.id, limit: 50)
        XCTAssertEqual(below.count, 50)
        let day = try XCTUnwrap(below.last?.date)
        let window = try await repository.messages(around: day, in: "inbox", limit: 50)
        XCTAssertNotNil(window)
        let hits = try await repository.search(in: "inbox", query: "garden", scope: .currentMailbox,
                                               beforeUID: nil, limit: 50)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(keptIDs(shelf), top.map(\.id), "nothing but the top")
        shelf.flush()
        XCTAssertEqual(keptIDs(makeShelf()), top.map(\.id), "and that is what is on disk")

        let arrived = try XCTUnwrap(server.arrive(
            Server.Letter(from: Server.jane, to: [Server.owner], subject: "Arrived since",
                          date: Server.newestDate.addingTimeInterval(600), text: "Hello.\r\n",
                          messageID: "<since@example.com>"),
            in: [Server.inbox, Server.allMail])[Server.inbox])
        server.removeElsewhere(uid: uid(top[2].id), from: Server.inbox)
        clock.advance(by: 3)
        let fresh = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(fresh.first.map { uid($0.id) }, arrived)
        XCTAssertFalse(fresh.contains { $0.id == top[2].id })
        XCTAssertEqual(keptIDs(shelf), fresh.map(\.id))
        shelf.flush()
        XCTAssertEqual(keptIDs(makeShelf()), fresh.map(\.id))
    }

    // MARK: - Phase 1: his writes

    /// His read mark, flag, move and delete, once the server has taken
    /// each, change the kept pages as the server changed the letter: the
    /// read mark and the flag on the letter wherever it is kept, Gmail's
    /// flags being the letter's; a move to another folder off its own page
    /// and not All Mail's; a delete off every page, the Trash being
    /// exclusive. A write the server refuses changes nothing.
    func testHisWritesChangeTheKeptPagesOnceTheServerHasThemAndARefusedOneDoesNot() async throws {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.folders()
        let inbox = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        _ = try await repository.listMessages(in: Server.allMail, beforeUID: nil, limit: 50)
        func row(_ letter: MessageSummary) -> MessageSummary? {
            shelf.page(of: "inbox")?.rows.first { $0.id == letter.id }
        }
        func inAllMail(_ letter: MessageSummary) -> MessageSummary? {
            shelf.page(of: Server.allMail)?.rows.first { $0.gmailMessageID == letter.gmailMessageID }
        }
        let (unread, plain, other, moving, binned) = (inbox[0], inbox[1], inbox[2], inbox[3], inbox[4])
        XCTAssertFalse(unread.isRead)
        XCTAssertFalse(plain.isFlagged)
        XCTAssertFalse(other.isFlagged)
        for letter in [unread, plain, moving, binned] { XCTAssertNotNil(inAllMail(letter)) }

        server.refusedVerbs = ["UID STORE", "UID MOVE", "UID COPY"]
        _ = try? await repository.setRead(true, on: unread)
        _ = try? await repository.setFlagged(true, on: other)
        _ = try? await repository.move(moving, to: Server.starred)
        _ = try? await repository.delete(binned)
        // The move and the delete's move are each refused twice, MOVE and
        // the COPY it falls back to.
        XCTAssertEqual(server.log.filter { $0.status == "NO" }.count, 6)
        XCTAssertEqual(row(unread)?.isRead, false)
        XCTAssertEqual(row(other)?.isFlagged, false)
        XCTAssertNotNil(row(moving))
        XCTAssertNotNil(row(binned))
        XCTAssertEqual(shelf.page(of: "inbox")?.rows.map(\.id), inbox.map(\.id))

        server.refusedVerbs = []
        try await repository.setRead(true, on: unread)
        try await repository.setFlagged(true, on: plain)
        try await repository.move(moving, to: Server.starred)
        try await repository.delete(binned)

        XCTAssertEqual(row(unread)?.isRead, true)
        XCTAssertEqual(inAllMail(unread)?.isRead, true)
        XCTAssertEqual(row(plain)?.isFlagged, true)
        XCTAssertEqual(inAllMail(plain)?.isFlagged, true)
        XCTAssertNil(row(moving))
        XCTAssertNotNil(inAllMail(moving), "All Mail keeps a letter filed elsewhere")
        XCTAssertNil(row(binned))
        XCTAssertNil(inAllMail(binned), "binned, it has left All Mail")
        XCTAssertEqual(shelf.page(of: "inbox")?.rows.count, 48)

        shelf.flush()
        let relaunched = makeShelf()
        XCTAssertEqual(relaunched.page(of: "inbox")?.rows.map(\.id),
                       shelf.page(of: "inbox")?.rows.map(\.id))
        XCTAssertEqual(relaunched.page(of: "inbox")?.rows.first?.isRead, true)
    }

    // MARK: - Phase 1: never the wrong mailbox

    /// The Inbox renumbered since the copy was kept, or another mailbox
    /// under the same numbers, as the app-password trap can open: the first
    /// listing from the top throws the whole copy away, the other folders'
    /// pages and the folder list with it, keeps its own page afresh, and
    /// carries no preview across from the rows it threw away; the list
    /// does not either. The connection log says so, in numbers. The same
    /// mailbox, unchanged, keeps the rest, and its previews.
    @MainActor
    func testARenumberedInboxOrAnotherLetterUnderAKeptUIDThrowsAwayTheWholeCopy() async throws {
        let cases: [(label: String, validity: UInt32?, firstUID: UInt32, reason: String?)] = [
            ("the same mailbox", nil, 1_000, nil),
            ("renumbered", 700_001, 1_000, "uidvalidity"),
            ("another mailbox under the same numbers", 600_001, 1_002, "msgid"),
        ]
        for (label, validity, firstUID, reason) in cases {
            server = ScriptedIMAPServer()
            MailShelf.wipe(root: kept)
            Diagnostics.clear()
            let before = try await earlierLaunch(listing: [Server.sent])
            if let validity { server.renumber(Server.inbox, validity: validity, firstUID: firstUID) }

            let shelf = makeShelf()
            let repository = makeRepository(shelf: shelf)
            let list = ListLetters()
            list.showKept(try XCTUnwrap(shelf.page(of: "inbox"), label).rows)
            XCTAssertNotNil(shelf.page(of: Server.sent), label)
            XCTAssertNotNil(shelf.folders, label)

            let first = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
            let discarded = reason != nil
            XCTAssertEqual(shelf.page(of: Server.sent) == nil, discarded, label)
            XCTAssertEqual(shelf.folders == nil, discarded, label)
            let keptNow = try XCTUnwrap(shelf.page(of: "inbox"), label)
            XCTAssertEqual(keptNow.rows.map(\.id), first.map(\.id), label)
            XCTAssertEqual(keptNow.rows.allSatisfy { $0.preview.isEmpty }, discarded, label)
            _ = list.fetchedAfresh(first)
            XCTAssertEqual(list.shown.allSatisfy { $0.preview.isEmpty }, discarded, label)
            if !discarded {
                XCTAssertEqual(list.shown.map(\.preview), before.map(\.preview), label)
            }
            let notes = Diagnostics.entries.map(\.text).filter { $0.hasPrefix("KEPT-") }
            XCTAssertEqual(notes, reason.map { ["KEPT-DISCARDED folder=INBOX reason=\($0)"] } ?? [],
                           label)

            shelf.flush()
            let relaunched = makeShelf()
            XCTAssertEqual(relaunched.page(of: "inbox")?.rows.map(\.id), first.map(\.id), label)
            XCTAssertEqual(relaunched.page(of: Server.sent) == nil, discarded, label)
            // Each pass has a server of its own; `tearDown` sees the last.
            XCTAssertEqual(server.violations, [], label)
        }
    }

    // MARK: - Phase 1: a write on a kept row

    /// A tap on a kept row before the Inbox's first page has come: its read
    /// mark, naming the row's letter as every write does, goes after one
    /// `UID FETCH` of the row's Gmail message id, which matches, and nothing
    /// more is asked of that row. Another kept row is asked for in turn.
    /// Once the Inbox has been listed from the top, a write on a row it
    /// brought goes as it always did. A row kept for All Mail, which nothing
    /// in this launch has brought, is asked about once like any other kept
    /// row, though the Inbox's listing has shown the copy to be this
    /// mailbox's: what decides is whether the server has named the row's
    /// letter under its UID in this launch.
    func testAnEarlyWriteOnAKeptRowIsVouchedForOnceBeforeItGoes() async throws {
        try await earlierLaunch(listing: [Server.allMail])
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let rows = try XCTUnwrap(shelf.page(of: "inbox")).rows
        let allMail = try XCTUnwrap(shelf.page(of: Server.allMail)).rows
        server.clearLog()

        try await repository.setRead(true, on: rows[0])
        XCTAssertEqual(verbs, ["LOGIN", "NOOP", "LIST", "SELECT", "UID FETCH", "UID STORE"])
        XCTAssertEqual(command(4), "UID FETCH \(uid(rows[0].id)) (UID X-GM-MSGID)")
        XCTAssertTrue(server.flags(uid: uid(rows[0].id), in: Server.inbox).contains("\\Seen"))

        server.clearLog()
        try await repository.setFlagged(true, on: rows[0])
        XCTAssertEqual(verbs, ["UID STORE"], "vouched for once")
        server.clearLog()
        try await repository.setFlagged(true, on: rows[1])
        XCTAssertEqual(verbs, ["UID FETCH", "UID STORE"])

        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        try await repository.setFlagged(true, on: rows[2])
        try await repository.delete(rows[3])
        XCTAssertEqual(verbs, ["UID STORE", "UID MOVE"], "the Inbox is listed: nothing to vouch for")
        server.clearLog()
        try await repository.setFlagged(true, on: allMail[5])
        XCTAssertEqual(verbs, ["SELECT", "UID FETCH", "UID STORE"], "All Mail's, not yet brought")
        XCTAssertEqual(command(1), "UID FETCH \(uid(allMail[5].id)) (UID X-GM-MSGID)")
        server.clearLog()
        try await repository.setFlagged(false, on: allMail[5])
        XCTAssertEqual(verbs, ["UID STORE"], "and asked once")
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
    }

    /// The same tap when the kept row's UID names another letter now, as in
    /// another mailbox under the same numbers: the `UID FETCH` says so, and
    /// nothing is written, not the flag from the reading pane, not a read
    /// mark and not a delete. Each row comes off the kept page, and the
    /// pane's list takes the flagged one off and keeps it off.
    @MainActor
    func testAWriteOnAKeptRowThatIsAnotherLetterNowSendsNothingAndTheRowGoes() async throws {
        try await earlierLaunch()
        server.renumber(Server.inbox, validity: server.uidValidity(of: Server.inbox), firstUID: 1_002)
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let rows = try XCTUnwrap(shelf.page(of: "inbox")).rows
        let (flagged, read, deleted) = (rows[1], rows[2], rows[3])
        let flagsBefore = [flagged, read, deleted].map { server.flags(uid: uid($0.id), in: Server.inbox) }
        let trashBefore = server.uids(in: Server.trash)
        let list = ListLetters()
        list.showKept(rows)
        server.clearLog()

        let done = await PaneActions.run(.flag(true), on: flagged, inFolderWithRole: .inbox,
                                         list: list, repository: repository, requestSweep: {})
        XCTAssertFalse(done)
        XCTAssertEqual(verbs, ["LOGIN", "NOOP", "LIST", "SELECT", "UID FETCH"])
        XCTAssertFalse(list.shown.contains { $0.id == flagged.id })
        XCTAssertEqual(list.shown.count, 49)

        server.clearLog()
        for write in [{ try await repository.setRead(true, on: read) },
                      { try await repository.delete(deleted) }] {
            do {
                try await write()
                XCTFail("sent")
            } catch {
                XCTAssertEqual(error as? MailShelf.NotTheKeptLetter, MailShelf.NotTheKeptLetter())
            }
        }
        XCTAssertEqual(verbs, ["UID FETCH", "UID FETCH"])
        XCTAssertEqual([flagged, read, deleted].map { server.flags(uid: uid($0.id), in: Server.inbox) },
                       flagsBefore)
        XCTAssertEqual(server.uids(in: Server.trash), trashBefore)
        let left = try XCTUnwrap(shelf.page(of: "inbox")).rows.map(\.id)
        XCTAssertEqual(left, rows.map(\.id).filter { ![flagged.id, read.id, deleted.id].contains($0) })
        XCTAssertEqual(Diagnostics.entries.filter { $0.text.hasPrefix("KEPT-UNVOUCHED") }.count, 3)

        // Off until the list is fetched afresh, which has the say: then the
        // letter the server has under that UID is on it, under that id.
        let fresh = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let there = try XCTUnwrap(fresh.first { $0.id == flagged.id })
        XCTAssertNotEqual(there.gmailMessageID, flagged.gmailMessageID)
        _ = list.fetchedAfresh(fresh)
        XCTAssertEqual(list.shown.first { $0.id == flagged.id }?.gmailMessageID, there.gmailMessageID,
                       "the server's letter at that UID")
        XCTAssertEqual(list.shown.map(\.id), fresh.map(\.id))
    }

    /// The Trash's Delete, which sets `\\Deleted` and takes the letter out
    /// for good, and a draft removed, which is expunged, on a kept row whose
    /// UID names another letter now: the `UID FETCH` says so, and neither
    /// is sent. The letter the server has under that UID keeps its flags,
    /// and the one draft there is not expunged.
    func testATrashDeleteOrADraftRemovedOnAKeptRowThatIsAnotherLetterDestroysNothing() async throws {
        try await earlierLaunch(listing: [Server.trash, Server.drafts])
        for folder in [Server.trash, Server.drafts] {
            let first = try XCTUnwrap(server.uids(in: folder).first)
            server.renumber(folder, validity: server.uidValidity(of: folder), firstUID: first + 2)
        }
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let binned = try XCTUnwrap(shelf.page(of: Server.trash)).rows[0]
        let draft = try XCTUnwrap(shelf.page(of: Server.drafts)).rows[0]
        let trash = server.uids(in: Server.trash)
        let trashFlags = trash.map { server.flags(uid: $0, in: Server.trash) }
        let drafts = server.uids(in: Server.drafts)
        XCTAssertTrue(trash.contains(uid(binned.id)), "another letter under the kept UID")
        XCTAssertTrue(drafts.contains(uid(draft.id)), "another draft under the kept UID")
        server.clearLog()

        let deleted = await refusal { try await repository.delete(binned) }
        XCTAssertEqual(deleted as? MailShelf.NotTheKeptLetter, Self.notKept)
        let removed = await refusal { try await repository.deleteDraft(draft.id) }
        XCTAssertEqual(removed as? MailShelf.NotTheKeptLetter, Self.notKept)

        XCTAssertEqual(server.log.filter { $0.verb == "UID FETCH" }.map(\.command),
                       ["UID FETCH \(uid(binned.id)) (UID X-GM-MSGID)",
                        "UID FETCH \(uid(draft.id)) (UID X-GM-MSGID)"])
        XCTAssertEqual(server.log.filter {
            ["UID STORE", "UID EXPUNGE", "EXPUNGE", "UID MOVE", "UID COPY"].contains($0.verb)
        }, [])
        XCTAssertEqual(server.uids(in: Server.trash), trash)
        XCTAssertEqual(trash.map { server.flags(uid: $0, in: Server.trash) }, trashFlags)
        XCTAssertEqual(server.uids(in: Server.drafts), drafts)
    }

    /// A landed draft reopened by its copy's folder and UID alone, naming
    /// no letter (`openDraft`), on a kept Drafts row whose UID names
    /// another draft now: refused, and the row leaves the kept page. The
    /// copy removed after that names no letter either, and has no row left
    /// on the page to be asked about by: it is asked about again as the
    /// letter it was kept as (`MailShelf.unproven`), refused, and the draft
    /// the server has under that UID is not expunged.
    func testACopyRefusedOnReopeningIsAskedAboutAgainWhenRemovedAndNothingIsExpunged() async throws {
        try await earlierLaunch(listing: [Server.drafts])
        let first = try XCTUnwrap(server.uids(in: Server.drafts).first)
        server.renumber(Server.drafts, validity: server.uidValidity(of: Server.drafts), firstUID: first + 2)
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let draft = try XCTUnwrap(shelf.page(of: Server.drafts)).rows[0]
        let drafts = server.uids(in: Server.drafts)
        XCTAssertTrue(drafts.contains(uid(draft.id)), "another draft under the kept UID")
        server.clearLog()

        let reopened = await refusal { _ = try await repository.loadDraft(id: draft.id, mailboxID: Server.drafts) }
        XCTAssertEqual(reopened as? MailShelf.NotTheKeptLetter, Self.notKept)
        XCTAssertFalse(try XCTUnwrap(shelf.page(of: Server.drafts)).rows.contains { $0.id == draft.id })
        let removed = await refusal { try await repository.deleteDraft(draft.id) }
        XCTAssertEqual(removed as? MailShelf.NotTheKeptLetter, Self.notKept)

        XCTAssertEqual(server.log.filter(\.isUIDCommand).map(\.command),
                       ["UID FETCH \(uid(draft.id)) (UID X-GM-MSGID BODY.PEEK[])",
                        "UID FETCH \(uid(draft.id)) (UID X-GM-MSGID)"])
        XCTAssertFalse(server.log.contains { $0.verb == "EXPUNGE" })
        XCTAssertEqual(server.uids(in: Server.drafts), drafts)
        XCTAssertEqual(keptNotes, ["KEPT-UNVOUCHED folder=\(Server.drafts) nothing-shown",
                                   "KEPT-UNVOUCHED folder=\(Server.drafts) nothing-sent"])
    }

    /// A launch with nothing kept, the first, and the first after a
    /// password is saved: the Inbox's listing from the top keeps its page
    /// and proves it, so a write on one of its rows sends the write alone,
    /// and a letter opened from one the FETCH it always did. Nothing is
    /// vouched for that this launch has listed.
    func testWithNothingKeptAListingProvesItsOwnRowsAndAWriteSendsOnlyTheWrite() async throws {
        let shelf = makeShelf()
        XCTAssertNil(shelf.page(of: "inbox"))
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.folders()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(shelf.page(of: "inbox")?.rows.map(\.id), rows.map(\.id), "kept now")
        server.clearLog()

        try await repository.setFlagged(true, on: rows[0])
        _ = try await repository.open(rows[1])
        XCTAssertEqual(server.log.map(\.command),
                       ["UID STORE \(uid(rows[0].id)) +FLAGS.SILENT (\\Flagged)",
                        "UID FETCH \(uid(rows[1].id)) (UID BODY.PEEK[])"])
    }

    /// The four changes his writes make to the kept pages that the read
    /// mark, the flag, the move and the Delete from the Inbox above do not
    /// show, once the server has each: deleted for good in Trash, off
    /// Trash's page; a draft removed, off Drafts'; marked as spam from the
    /// Inbox, off every kept page but Spam's, All Mail's with it, since
    /// Spam is exclusive; and filed from All Mail under a label, left on
    /// All Mail's, which is every letter not binned. The same after a
    /// relaunch.
    func testTrashDraftsSpamAndAllMailChangeTheKeptPagesAsGmailChangesTheLetter() async throws {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.folders()
        let inbox = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let allMail = try await repository.listMessages(in: Server.allMail, beforeUID: nil, limit: 50)
        let trash = try await repository.listMessages(in: Server.trash, beforeUID: nil, limit: 50)
        let drafts = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 50)
        let spammed = inbox[2]
        let filed = try XCTUnwrap(allMail.first { $0.gmailMessageID != spammed.gmailMessageID })
        XCTAssertTrue(allMail.contains { $0.gmailMessageID == spammed.gmailMessageID })

        try await repository.delete(trash[0])
        try await repository.deleteDraft(drafts[0].id)
        try await repository.move(spammed, to: Server.spam)
        try await repository.move(filed, to: Server.starred)
        shelf.flush()

        for (label, kept) in [("now", shelf), ("relaunched", makeShelf())] {
            func rows(_ folder: String) -> [MessageSummary] { kept.page(of: folder)?.rows ?? [] }
            XCTAssertEqual(rows(Server.trash).map(\.id), trash.dropFirst().map(\.id), label)
            XCTAssertEqual(rows(Server.drafts).map(\.id), drafts.dropFirst().map(\.id), label)
            XCTAssertFalse(rows("inbox").contains { $0.id == spammed.id }, label)
            XCTAssertFalse(rows(Server.allMail).contains { $0.gmailMessageID == spammed.gmailMessageID },
                           "marked as spam, it has left All Mail: \(label)")
            XCTAssertTrue(rows(Server.allMail).contains { $0.id == filed.id },
                          "filed under a label, it is still in All Mail: \(label)")
            XCTAssertEqual(rows(Server.allMail).count, allMail.count - 1, label)
        }
    }

    /// The vouching FETCH is a read, and goes again on a new connection
    /// when the socket it went down has died, as every read does: the
    /// write on the kept row is not lost to a dead socket, and goes once.
    func testTheVouchingFetchGoesAgainOnANewConnectionWhenTheSocketHasDied() async throws {
        try await earlierLaunch()
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let row = try XCTUnwrap(shelf.page(of: "inbox")).rows[3]
        _ = try await repository.folders()
        let opened = server.connectionsOpened
        await server.resetConnections()
        server.clearLog()

        try await repository.setFlagged(true, on: row)
        XCTAssertEqual(server.connectionsOpened, opened + 1, "one new connection")
        XCTAssertEqual(server.log.filter { $0.verb == "UID STORE" }.count, 1)
        XCTAssertEqual(server.log.filter { $0.verb == "UID FETCH" }.last?.command,
                       "UID FETCH \(uid(row.id)) (UID X-GM-MSGID)")
        XCTAssertTrue(server.flags(uid: uid(row.id), in: Server.inbox).contains("\\Flagged"))
    }

    /// Gmail's id for a letter is asked for only on a connection shown to
    /// be up, holding the gate. Asked of one that another command had just
    /// torn down, which has no capabilities left, it used to answer that
    /// there was no letter, and a kept row was taken for another letter,
    /// dropped and its write refused, where a read goes again on a new
    /// connection. The same for the letter's own FETCH.
    func testGmailsIDForALetterIsNotReadOffAConnectionThatHasBeenTornDown() async throws {
        let client = IMAPClient(account: server.account, transport: server.transportFactory)
        try await client.connect(password: server.password)
        let validity = server.uidValidity(of: Server.inbox)
        let newest = try XCTUnwrap(server.uids(in: Server.inbox).last)
        let named = try await client.gmailMessageID(uid: newest, in: Server.inbox, validity: validity)
        XCTAssertEqual(named, server.gmailMessageID(uid: newest, in: Server.inbox))

        await server.resetConnections()
        try? await client.noop()
        let up = await client.isConnected
        XCTAssertFalse(up)
        let asked = await refusal {
            _ = try await client.gmailMessageID(uid: newest, in: Server.inbox, validity: validity)
        }
        XCTAssertNotNil(asked as? MailError)
        let fetched = await refusal {
            _ = try await client.fetchBodyNamingLetter(uid: newest, in: Server.inbox, validity: validity)
        }
        XCTAssertNotNil(fetched as? MailError)
    }

    /// He taps a kept row as the launch's first page is on the wire, and
    /// the Inbox is another mailbox's under the same numbers: the question
    /// about his row waits behind the listing, the listing lands first and
    /// throws the copy away, and then the answer comes. Nothing is written,
    /// and the letter the server really has under that UID, on the fresh
    /// page, stays on the kept page and on the list.
    @MainActor
    func testAVouchThatLosesTheRaceToTheFirstPageLeavesTheServersLetterUnderThatUID() async throws {
        try await earlierLaunch()
        server.renumber(Server.inbox, validity: server.uidValidity(of: Server.inbox), firstUID: 1_002)
        // A round trip's worth, so the answer comes after the listing has
        // been taken, as it does over a network.
        server.delays = ["UID FETCH": .milliseconds(5)]
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let rows = try XCTUnwrap(shelf.page(of: "inbox")).rows
        let tapped = rows[1]
        let list = ListLetters()
        list.showKept(rows)

        server.holdReplies(to: "UID SEARCH")
        let listing = Task { try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50) }
        try await until { self.server.log.contains { $0.verb == "UID SEARCH" } }
        let flagging = Task { @MainActor in
            await PaneActions.run(.flag(true), on: tapped, inFolderWithRole: .inbox, list: list,
                                  repository: repository, requestSweep: {})
        }
        try await until { await repository.waitingForExchange == 1 }
        await server.releaseReplies(to: "UID SEARCH")
        let first = try await finishing { try await listing.value }
        _ = list.fetchedAfresh(first)
        let done = try await finishing { await flagging.value }

        XCTAssertFalse(done)
        let theirs = try XCTUnwrap(first.first { $0.id == tapped.id })
        XCTAssertNotEqual(theirs.gmailMessageID, tapped.gmailMessageID)
        XCTAssertEqual(shelf.page(of: "inbox")?.rows.map(\.id), first.map(\.id),
                       "the kept page is the server's, whole")
        XCTAssertEqual(list.shown.first { $0.id == tapped.id }?.gmailMessageID, theirs.gmailMessageID)
        XCTAssertEqual(list.shown.first { $0.id == tapped.id }?.isFlagged, theirs.isFlagged)
        XCTAssertFalse(server.log.contains { $0.verb == "UID STORE" })
        XCTAssertFalse(server.flags(uid: uid(tapped.id), in: Server.inbox).contains("\\Flagged"))
    }

    // MARK: - Phase 1: a letter opened from a kept row

    /// A kept row opened before anything in this launch has brought it
    /// from the server, naming the row's letter as the reading pane does:
    /// the FETCH that brings the letter asks for its Gmail message id beside
    /// the body, one round trip as ever, and the letter is shown as the id
    /// matches. PEEK: the FETCH marks nothing read. Vouched for, the row is
    /// not asked about again, opened or written.
    func testALetterOpenedFromAKeptRowIsVouchedForByTheFetchThatBringsIt() async throws {
        try await earlierLaunch()
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let tapped = try XCTUnwrap(shelf.page(of: "inbox")).rows[0]
        XCTAssertFalse(tapped.isRead)
        server.clearLog()

        let letter = try await repository.open(tapped)
        XCTAssertEqual(verbs, ["LOGIN", "LIST", "SELECT", "UID FETCH"])
        XCTAssertEqual(command(3), "UID FETCH \(uid(tapped.id)) (UID X-GM-MSGID BODY.PEEK[])")
        XCTAssertEqual(letter.subject, tapped.subject)
        XCTAssertFalse((letter.textBody ?? letter.htmlBody ?? "").isEmpty)
        XCTAssertFalse(server.flags(uid: uid(tapped.id), in: Server.inbox).contains("\\Seen"),
                       "PEEK: the FETCH marks nothing read")

        server.clearLog()
        _ = try await repository.open(tapped)
        try await repository.setRead(true, on: tapped)
        XCTAssertEqual(server.log.map(\.command),
                       ["UID FETCH \(uid(tapped.id)) (UID BODY.PEEK[])",
                        "UID STORE \(uid(tapped.id)) +FLAGS.SILENT (\\Seen)"])
        XCTAssertEqual(Diagnostics.entries.filter { $0.text.hasPrefix("KEPT-") }.map(\.text), [])
    }

    /// A kept row the Inbox's listing has brought again, the same letter
    /// under the same UID: a letter opened from it after the listing is
    /// fetched byte for byte as every letter is, and so is one opened with
    /// no copy kept at all, from a row that launch's own listing brought.
    /// The wire does not change for a row the server has named in this
    /// launch.
    func testALetterFromAProvenRowIsFetchedAsItAlwaysWas() async throws {
        try await earlierLaunch()
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let kept = try XCTUnwrap(shelf.page(of: "inbox")).rows
        let first = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(first.first { $0.id == kept[4].id }?.gmailMessageID, kept[4].gmailMessageID)
        let plain = makeRepository()
        let listed = try await plain.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()

        _ = try await repository.open(kept[4])
        _ = try await plain.open(listed[5])
        XCTAssertEqual(server.log.filter { $0.verb == "UID FETCH" }.map(\.command),
                       ["UID FETCH \(uid(kept[4].id)) (UID BODY.PEEK[])",
                        "UID FETCH \(uid(listed[5].id)) (UID BODY.PEEK[])"])
    }

    /// Kept rows whose UIDs name other letters now, as in another mailbox
    /// under the same numbers. Opened, the FETCH says so and nothing of the
    /// letter comes back, and the tap's read mark after it is refused with
    /// nothing sent, the server having named another letter under that
    /// UID. The other way round, the read mark asked about first and
    /// refused, the letter is refused too, and nothing of it is fetched:
    /// a row the server has disowned is never taken for one that was never
    /// kept, and is not asked about again.
    func testALetterOpenedFromAKeptRowThatIsAnotherLetterShowsNothingAndNothingIsWritten() async throws {
        try await earlierLaunch()
        server.renumber(Server.inbox, validity: server.uidValidity(of: Server.inbox), firstUID: 1_002)
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let rows = try XCTUnwrap(shelf.page(of: "inbox")).rows
        let (opened, readFirst) = (rows[1], rows[2])
        let flags = [opened, readFirst].map { server.flags(uid: uid($0.id), in: Server.inbox) }
        server.clearLog()

        let open = await refusal { _ = try await repository.open(opened) }
        XCTAssertEqual(open as? MailShelf.NotTheKeptLetter, Self.notKept)
        let mark = await refusal { try await repository.setRead(true, on: opened) }
        XCTAssertEqual(mark as? MailShelf.NotTheKeptLetter, Self.notKept)

        let first = await refusal { try await repository.setRead(true, on: readFirst) }
        XCTAssertEqual(first as? MailShelf.NotTheKeptLetter, Self.notKept)
        let then = await refusal { _ = try await repository.open(readFirst) }
        XCTAssertEqual(then as? MailShelf.NotTheKeptLetter, Self.notKept)

        XCTAssertEqual(server.log.filter(\.isUIDCommand).map(\.command),
                       ["UID FETCH \(uid(opened.id)) (UID X-GM-MSGID BODY.PEEK[])",
                        "UID FETCH \(uid(readFirst.id)) (UID X-GM-MSGID)"])
        XCTAssertFalse(server.log.contains { $0.verb == "UID STORE" })
        XCTAssertEqual([opened, readFirst].map { server.flags(uid: uid($0.id), in: Server.inbox) }, flags)
        XCTAssertEqual(Diagnostics.entries.map(\.text).filter { $0.hasPrefix("KEPT-") },
                       ["KEPT-UNVOUCHED folder=INBOX nothing-shown",
                        "KEPT-UNVOUCHED folder=INBOX nothing-sent",
                        "KEPT-UNVOUCHED folder=INBOX nothing-sent",
                        "KEPT-UNVOUCHED folder=INBOX nothing-shown"])
        let left = try XCTUnwrap(shelf.page(of: "inbox")).rows.map(\.id)
        XCTAssertEqual(left, rows.map(\.id).filter { ![opened.id, readFirst.id].contains($0) })
    }

    /// The copy kept from Gmail, and the server now without Gmail's
    /// extension to ask: a kept row names the letter it was kept as, as the
    /// app's calls do, and the server can name none under its UID, so a
    /// letter opened from it shows nothing and a write on it goes nowhere,
    /// as the write's vouching does, and nothing is fetched to find out.
    func testAKeptRowOnAServerWithoutGmailsExtensionIsNeitherOpenedNorWritten() async throws {
        try await earlierLaunch()
        server.withheldCapabilities = ["X-GM-EXT-1"]
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let rows = try XCTUnwrap(shelf.page(of: "inbox")).rows
        XCTAssertNotNil(rows[0].gmailMessageID)
        XCTAssertNotNil(rows[1].gmailMessageID)
        server.clearLog()

        let open = await refusal { _ = try await repository.open(rows[0]) }
        XCTAssertEqual(open as? MailShelf.NotTheKeptLetter, Self.notKept)
        let flag = await refusal { try await repository.setFlagged(true, on: rows[1]) }
        XCTAssertEqual(flag as? MailShelf.NotTheKeptLetter, Self.notKept)
        XCTAssertEqual(verbs.filter { $0.hasPrefix("UID") }, [])
    }

    // MARK: - Phase 1: every write and every open names its letter

    /// The kept Inbox, as an earlier launch left it, and a server that has
    /// another mailbox under the same numbers, as the app-password trap can
    /// open: every kept UID names the letter before its own now, and the
    /// oldest kept UID is below the fresh page.
    private func anotherMailboxUnderTheKeptNumbers(
        listing others: [String] = []) async throws -> (MailShelf, IMAPMailRepository, [MessageSummary]) {
        try await earlierLaunch(listing: others)
        server.renumber(Server.inbox, validity: server.uidValidity(of: Server.inbox), firstUID: 1_002)
        let shelf = makeShelf()
        return (shelf, makeRepository(shelf: shelf), try XCTUnwrap(shelf.page(of: "inbox")).rows)
    }

    private var keptNotes: [String] {
        Diagnostics.entries.map(\.text).filter { $0.hasPrefix("KEPT-") }
    }

    /// His ticks on the kept rows as the launch's first page lands from
    /// another mailbox under the same numbers: the listing throws the copy
    /// away and its page waits for the ticks to go (`OverKept`, `KeptSwap`),
    /// so the kept rows are still what he sees and acts on. Edit mode's Mark
    /// as Read and Delete, the reading pane's Flag and a letter opened each
    /// name the kept row's letter, and write nothing and show nothing,
    /// whether the fresh page has the row's UID or not; only the row it
    /// lacks is asked about. The rows the Mark, the Flag and the letter
    /// opened were refused on come off the list; Edit mode's Delete leaves
    /// its row to the reload after it, as ever. When the ticks go, the
    /// fresh page goes on with the server's letters under those ids.
    @MainActor
    func testADiscardWithTheKeptRowsStillShownWritesAndShowsNothingOnThem() async throws {
        let (_, repository, kept) = try await anotherMailboxUnderTheKeptNumbers()
        let list = ListLetters()
        list.showKept(kept)
        var over = OverKept()
        XCTAssertTrue(over.fetch(showingKept: list.fromShelf, quietly: false))
        let asked = list.askingAfresh()
        let first = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        over.came(first, asked: asked)
        let ticked = KeptSwap.swap(atTop: true, searching: false, ticked: true, touching: false)
        XCTAssertNil(over.landing(showingKept: list.fromShelf, ticked), "the page waits for his ticks")
        XCTAssertEqual(list.shown.map(\.id), kept.map(\.id), "the kept rows are what he sees")
        XCTAssertEqual(keptNotes, ["KEPT-DISCARDED folder=INBOX reason=msgid"])

        let (marked, binned, flagged, opened) = (kept[0], kept[1], kept[2], kept[3])
        let lacked = try XCTUnwrap(kept.last)
        let onPage = Set(first.map(\.id))
        XCTAssertTrue([marked, binned, flagged, opened].allSatisfy { onPage.contains($0.id) })
        XCTAssertFalse(onPage.contains(lacked.id))
        let refused = [marked, binned, flagged, opened, lacked]
        let flags = refused.map { server.flags(uid: uid($0.id), in: Server.inbox) }
        let trash = server.uids(in: Server.trash)
        server.clearLog()

        // Edit mode's Mark as Read, as `applyRead` makes it, and Delete.
        for m in [marked, lacked] {
            do {
                try await repository.setRead(true, on: m)
                XCTFail("marked")
            } catch is MailShelf.NotTheKeptLetter {
                PaneActions.notTheKeptLetter(m, list: list)
            }
        }
        try? await repository.delete(binned)
        // The reading pane's Flag, and a letter opened there.
        let done = await PaneActions.run(.flag(true), on: flagged, inFolderWithRole: .inbox,
                                         list: list, repository: repository, requestSweep: {})
        XCTAssertFalse(done)
        let open = await refusal { _ = try await repository.open(opened) }
        XCTAssertEqual(open as? MailShelf.NotTheKeptLetter, Self.notKept)
        PaneActions.notTheKeptLetter(opened, list: list)

        XCTAssertEqual(server.log.map(\.command), ["UID FETCH \(uid(lacked.id)) (UID X-GM-MSGID)"],
                       "asked only of the row the fresh page lacks, and nothing written")
        XCTAssertEqual(refused.map { server.flags(uid: uid($0.id), in: Server.inbox) }, flags)
        XCTAssertEqual(server.uids(in: Server.trash), trash)
        let taken = Set([marked, flagged, opened, lacked].map(\.id))
        XCTAssertEqual(list.shown.map(\.id), kept.map(\.id).filter { !taken.contains($0) })
        XCTAssertEqual(keptNotes.dropFirst(), ["KEPT-UNVOUCHED folder=INBOX nothing-sent",
                                               "KEPT-UNVOUCHED folder=INBOX nothing-sent",
                                               "KEPT-UNVOUCHED folder=INBOX nothing-sent",
                                               "KEPT-UNVOUCHED folder=INBOX nothing-sent",
                                               "KEPT-UNVOUCHED folder=INBOX nothing-shown"])

        // Done: the fresh page goes on, the server's letters under the ids.
        let unticked = KeptSwap.swap(atTop: true, searching: false, ticked: false, touching: false)
        let fresh = try XCTUnwrap(over.landing(showingKept: list.fromShelf, unticked))
        _ = list.fetchedAfresh(fresh.page, asked: fresh.asked)
        XCTAssertEqual(list.shown.map(\.id), first.map(\.id))
        for m in [marked, binned, flagged, opened] {
            let theirs = try XCTUnwrap(list.letter(m.id))
            XCTAssertEqual(theirs.gmailMessageID, server.gmailMessageID(uid: uid(m.id), in: Server.inbox))
            XCTAssertNotEqual(theirs.gmailMessageID, m.gmailMessageID)
        }
    }

    /// The fresh page landed from another mailbox under the same numbers,
    /// and a write naming a kept row's letter under a UID the page has as
    /// another letter: the Mark, the Flag, the Move and the Delete are each
    /// refused at once, and nothing at all is sent, not even a question. The
    /// server has named that UID's letter in this launch already. The
    /// letters it has there are as they were, and stay on the kept page.
    func testAWriteOnAKeptRowWhoseUIDTheFreshPageHasAsAnotherLetterSendsNothingAtAll() async throws {
        let (shelf, repository, kept) = try await anotherMailboxUnderTheKeptNumbers()
        let first = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let rows = Array(kept.prefix(4))
        for row in rows {
            let theirs = try XCTUnwrap(first.first { $0.id == row.id })
            XCTAssertNotEqual(theirs.gmailMessageID, row.gmailMessageID)
        }
        let flags = rows.map { server.flags(uid: uid($0.id), in: Server.inbox) }
        let (trash, starred) = (server.uids(in: Server.trash), server.uids(in: Server.starred))
        server.clearLog()

        let writes: [(String, () async throws -> Void)] = [
            ("mark", { try await repository.setRead(true, on: rows[0]) }),
            ("flag", { try await repository.setFlagged(true, on: rows[1]) }),
            ("move", { try await repository.move(rows[2], to: Server.starred) }),
            ("delete", { try await repository.delete(rows[3]) }),
        ]
        for (label, write) in writes {
            let refused = await refusal { try await write() }
            XCTAssertEqual(refused as? MailShelf.NotTheKeptLetter, Self.notKept, label)
        }
        XCTAssertEqual(server.log.map(\.command), [], "nothing at all")
        XCTAssertEqual(rows.map { server.flags(uid: uid($0.id), in: Server.inbox) }, flags)
        XCTAssertEqual(server.uids(in: Server.trash), trash)
        XCTAssertEqual(server.uids(in: Server.starred), starred)
        XCTAssertEqual(keptNotes, ["KEPT-DISCARDED folder=INBOX reason=msgid"]
                       + Array(repeating: "KEPT-UNVOUCHED folder=INBOX nothing-sent", count: 4))
        XCTAssertEqual(shelf.page(of: "inbox")?.rows.map(\.id), first.map(\.id))
        XCTAssertEqual(shelf.page(of: "inbox")?.rows.map(\.gmailMessageID), first.map(\.gmailMessageID))
    }

    /// The same, under a UID the fresh page does not have: one `UID FETCH`
    /// of the Gmail message id there, which names another letter, and
    /// nothing written. Asked once: a second write on the row is refused at
    /// once, the server having named the letter under that UID.
    func testAWriteOnAKeptRowWhoseUIDTheFreshPageLacksIsAskedAboutOnceAndWritesNothing() async throws {
        let (_, repository, kept) = try await anotherMailboxUnderTheKeptNumbers()
        let first = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let row = try XCTUnwrap(kept.last)
        XCTAssertFalse(first.contains { $0.id == row.id })
        let there = try XCTUnwrap(server.gmailMessageID(uid: uid(row.id), in: Server.inbox))
        XCTAssertNotEqual(there, row.gmailMessageID, "another letter under it")
        let flags = server.flags(uid: uid(row.id), in: Server.inbox)
        server.clearLog()

        let flag = await refusal { try await repository.setFlagged(true, on: row) }
        XCTAssertEqual(flag as? MailShelf.NotTheKeptLetter, Self.notKept)
        XCTAssertEqual(server.log.map(\.command), ["UID FETCH \(uid(row.id)) (UID X-GM-MSGID)"])
        server.clearLog()
        let mark = await refusal { try await repository.setRead(true, on: row) }
        XCTAssertEqual(mark as? MailShelf.NotTheKeptLetter, Self.notKept)
        XCTAssertEqual(server.log.map(\.command), [], "asked once")
        XCTAssertEqual(server.flags(uid: uid(row.id), in: Server.inbox), flags)
    }

    /// The kept Inbox and Drafts, and another mailbox under the same
    /// numbers in both, each listed afresh.
    private func anotherMailboxWithDraftsListed() async throws
        -> (repository: IMAPMailRepository, inbox: [MessageSummary], drafts: [MessageSummary],
            fresh: (inbox: [MessageSummary], drafts: [MessageSummary])) {
        let (shelf, repository, inbox) = try await anotherMailboxUnderTheKeptNumbers(listing: [Server.drafts])
        let drafts = try XCTUnwrap(shelf.page(of: Server.drafts)).rows
        let first = try XCTUnwrap(server.uids(in: Server.drafts).first)
        server.renumber(Server.drafts, validity: server.uidValidity(of: Server.drafts), firstUID: first + 2)
        let freshInbox = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let freshDrafts = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 50)
        return (repository, inbox, drafts, (freshInbox, freshDrafts))
    }

    /// A letter opened from a kept row whose UID the fresh page has as
    /// another letter, in the reading pane or in Drafts' composer: refused
    /// at once, and nothing is fetched, not the letter under that UID nor
    /// its id, so nothing of it can be shown, kept for a Forward or marked.
    func testALetterOpenedFromAKeptRowWhoseUIDTheFreshPageHasAsAnotherLetterFetchesNothing() async throws {
        let (repository, inbox, drafts, fresh) = try await anotherMailboxWithDraftsListed()
        let (tapped, draft) = (inbox[1], drafts[0])
        XCTAssertNotEqual(fresh.inbox.first { $0.id == tapped.id }?.gmailMessageID, tapped.gmailMessageID)
        let there = try XCTUnwrap(fresh.drafts.first { $0.id == draft.id })
        XCTAssertNotEqual(there.gmailMessageID, draft.gmailMessageID)
        Diagnostics.clear()
        server.clearLog()

        let letter = await refusal { _ = try await repository.open(tapped) }
        XCTAssertEqual(letter as? MailShelf.NotTheKeptLetter, Self.notKept)
        let reopened = await refusal { _ = try await repository.reopen(draft) }
        XCTAssertEqual(reopened as? MailShelf.NotTheKeptLetter, Self.notKept)
        XCTAssertEqual(server.log.map(\.command), [], "nothing at all")
        XCTAssertEqual(keptNotes, ["KEPT-UNVOUCHED folder=INBOX nothing-shown",
                                   "KEPT-UNVOUCHED folder=\(Server.drafts) nothing-shown"])
    }

    /// The same, under a UID the fresh page does not have: the one FETCH
    /// of the letter asks for its Gmail message id beside the body, PEEK,
    /// and nothing of it is shown when the server names another letter
    /// there, or, for the draft, none at all. No STORE goes.
    func testALetterOpenedFromAKeptRowWhoseUIDTheFreshPageLacksIsAskedAboutByItsOwnFetch() async throws {
        let (repository, inbox, drafts, fresh) = try await anotherMailboxWithDraftsListed()
        let tapped = try XCTUnwrap(inbox.last)
        let draft = try XCTUnwrap(drafts.last)
        XCTAssertFalse(fresh.inbox.contains { $0.id == tapped.id })
        XCTAssertFalse(fresh.drafts.contains { $0.id == draft.id })
        XCTAssertNotNil(server.letter(uid: uid(tapped.id), in: Server.inbox), "another letter under it")
        XCTAssertNil(server.letter(uid: uid(draft.id), in: Server.drafts), "no draft under it")
        server.clearLog()

        let letter = await refusal { _ = try await repository.open(tapped) }
        XCTAssertEqual(letter as? MailShelf.NotTheKeptLetter, Self.notKept)
        let reopened = await refusal { _ = try await repository.reopen(draft) }
        XCTAssertEqual(reopened as? MailShelf.NotTheKeptLetter, Self.notKept)
        XCTAssertEqual(server.log.filter(\.isUIDCommand).map(\.command),
                       ["UID FETCH \(uid(tapped.id)) (UID X-GM-MSGID BODY.PEEK[])",
                        "UID FETCH \(uid(draft.id)) (UID X-GM-MSGID BODY.PEEK[])"])
    }

    /// The launch's first page lands from another mailbox under the same
    /// numbers and throws the copy away, and his tap on a kept row comes
    /// right after, before the swap has reached the list, as does the
    /// reading pane's Flag on another: each names the kept row's letter, is
    /// refused at once with nothing sent, and its row comes off the list.
    /// Once the fresh page is on the list the pane can still hold a kept
    /// letter: its Flag is refused the same way, and the server's letter the
    /// list now has under that id is left as it is, neither flagged nor
    /// taken off.
    @MainActor
    func testAWriteNamingAKeptLetterRightAfterTheListingHasThrownTheCopyAwayIsRefused() async throws {
        let (_, repository, kept) = try await anotherMailboxUnderTheKeptNumbers()
        let list = ListLetters()
        list.showKept(kept)
        let (tapped, flagged, inPane) = (kept[0], kept[1], kept[2])
        let first = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()

        // The tap's read mark, as `markReadIfNeeded` makes it.
        list.reading(tapped.id, read: true)
        let read = await refusal { try await repository.setRead(true, on: tapped) }
        XCTAssertEqual(read as? MailShelf.NotTheKeptLetter, Self.notKept)
        list.readAnswered(tapped.id, landed: false)
        XCTAssertTrue(PaneActions.notTheKeptLetter(tapped, list: list))
        let flagging = await PaneActions.run(.flag(true), on: flagged, inFolderWithRole: .inbox,
                                             list: list, repository: repository, requestSweep: {})
        XCTAssertFalse(flagging)
        XCTAssertFalse(list.shown.contains { [tapped.id, flagged.id].contains($0.id) })
        XCTAssertEqual(server.log.map(\.command), [])

        _ = list.fetchedAfresh(first)
        let theirs = try XCTUnwrap(list.letter(inPane.id))
        XCTAssertNotEqual(theirs.gmailMessageID, inPane.gmailMessageID)
        XCTAssertFalse(theirs.isFlagged)
        let fromPane = await PaneActions.run(.flag(true), on: inPane, inFolderWithRole: .inbox,
                                             list: list, repository: repository, requestSweep: {})
        XCTAssertFalse(fromPane)
        XCTAssertEqual(server.log.map(\.command), [])
        XCTAssertEqual(list.letter(inPane.id)?.gmailMessageID, theirs.gmailMessageID)
        XCTAssertEqual(list.letter(inPane.id)?.isFlagged, false, "the server's letter, not flagged")
        XCTAssertEqual(list.shown.map(\.id), first.map(\.id), "and not taken off")
        XCTAssertFalse(server.flags(uid: uid(inPane.id), in: Server.inbox).contains("\\Flagged"))
    }

    /// Once his rows come from this launch's listings, a write names the
    /// row's letter and sends exactly what it always sent, and so does a
    /// letter opened, whichever way the row came: the Inbox's first page
    /// (a Mark, a Flag, a Move and a Delete), a conversation on it, a page
    /// below, a day jumped to, a search hit, a letter the watch found, an
    /// All Mailboxes hit from All Mail whose Inbox row is on the list, the
    /// Trash (deleted there for good) and Drafts (reopened and removed).
    /// Each row is one that way brought first, after a launch with a copy
    /// kept, of All Mail's page too. The SELECTs follow the folder, as ever,
    /// and are left out.
    func testOrdinaryWritesAndOpensSendWhatTheyAlwaysDidWhicheverWayTheRowCame() async throws {
        let newest = try XCTUnwrap(server.uids(in: Server.inbox).last
            .flatMap { server.letter(uid: $0, in: Server.inbox) })
        server.deliver(Server.Letter(from: Server.jane, to: [Server.owner], subject: "Re: " + newest.subject,
                                     date: Server.newestDate.addingTimeInterval(600),
                                     text: "Agreed.\r\n", flags: ["\\Seen"],
                                     messageID: "<agreed@example.com>", inReplyTo: newest.messageID,
                                     joins: newest.messageID),
                       to: [Server.inbox, Server.allMail])
        try await earlierLaunch(listing: [Server.allMail, Server.trash, Server.drafts])
        let repository = makeRepository(shelf: makeShelf())
        _ = try await repository.listMailboxes()
        var brought: Set<String> = []
        func firstBroughtBy(_ rows: [MessageSummary], file: StaticString = #filePath,
                            line: UInt = #line) throws -> MessageSummary {
            defer { brought.formUnion(rows.map(\.id)) }
            return try XCTUnwrap(rows.first { !brought.contains($0.id) }, file: file, line: line)
        }
        func sent() -> [String] { server.log.filter { $0.verb != "SELECT" }.map(\.command) }
        func opensAndFlagsAsEver(_ row: MessageSummary, _ label: String) async throws {
            server.clearLog()
            _ = try await repository.open(row)
            try await repository.setFlagged(true, on: row)
            XCTAssertEqual(sent(), ["UID FETCH \(uid(row.id)) (UID BODY.PEEK[])",
                                    "UID STORE \(uid(row.id)) +FLAGS.SILENT (\\Flagged)"], label)
        }

        let first = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        brought.formUnion(first.map(\.id))
        try await opensAndFlagsAsEver(first[4], "the first page")
        server.clearLog()
        try await repository.setRead(true, on: first[5])
        try await repository.move(first[6], to: Server.starred)
        try await repository.delete(first[7])
        XCTAssertEqual(sent(), ["UID STORE \(uid(first[5].id)) +FLAGS.SILENT (\\Seen)",
                                "UID MOVE \(uid(first[6].id)) \"\(Server.starred)\"",
                                "UID MOVE \(uid(first[7].id)) \"\(Server.trash)\""], "the first page")
        let stack = try XCTUnwrap(MessageThread.rows(for: first, grouped: true)
            .first { $0.messages.count == 2 })
        try await opensAndFlagsAsEver(try XCTUnwrap(stack.messages.first { $0.id != stack.newest.id }),
                                      "a conversation's earlier letter")

        let below = try await repository.listMessages(in: "inbox", beforeUID: first.last?.id, limit: 50)
        try await opensAndFlagsAsEver(try firstBroughtBy(below), "a page below")

        let day = try XCTUnwrap(below.last?.date).addingTimeInterval(-15 * 86_400)
        let window = try await repository.messages(around: day, in: "inbox", limit: 10)
        try await opensAndFlagsAsEver(try firstBroughtBy(try XCTUnwrap(window).messages), "a day")

        let hits = try await repository.search(in: "inbox", query: "garden", scope: .currentMailbox,
                                               beforeUID: nil, limit: 50)
        try await opensAndFlagsAsEver(try firstBroughtBy(hits), "a search hit")

        server.arrive(Server.Letter(from: Server.sam, to: [Server.owner], subject: "Just come",
                                    date: Server.newestDate.addingTimeInterval(1_200),
                                    text: "Hello.\r\n", messageID: "<just@example.com>"),
                      in: [Server.inbox, Server.allMail])
        let news = try await repository.news(in: "inbox", known: (first + below).map(\.id),
                                             searchingAnyway: false)
        try await opensAndFlagsAsEver(try firstBroughtBy(news.arrived), "a letter the watch found")

        let everywhere = try await repository.search(in: "inbox", query: "tickets", scope: .allMailboxes,
                                                     beforeUID: nil, limit: 50)
        let twin = try XCTUnwrap(everywhere.first { hit in
            hit.mailboxID == Server.allMail && !brought.contains(hit.id)
                && first.contains { $0.gmailMessageID == hit.gmailMessageID }
        })
        brought.formUnion(everywhere.map(\.id))
        try await opensAndFlagsAsEver(twin, "All Mail's copy of an Inbox row")

        let trash = try await repository.listMessages(in: Server.trash, beforeUID: nil, limit: 50)
        try await opensAndFlagsAsEver(trash[1], "the Trash")
        server.clearLog()
        try await repository.delete(trash[0])
        XCTAssertEqual(sent(), ["UID STORE \(uid(trash[0].id)) +FLAGS.SILENT (\\Deleted)",
                                "UID EXPUNGE \(uid(trash[0].id))"], "the Trash")

        let drafts = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 50)
        server.clearLog()
        _ = try await repository.reopen(drafts[0])
        try await repository.deleteDraft(drafts[0].id)
        XCTAssertEqual(sent(), ["UID FETCH \(uid(drafts[0].id)) (UID BODY.PEEK[])",
                                "UID STORE \(uid(drafts[0].id)) +FLAGS.SILENT (\\Deleted)",
                                "UID EXPUNGE \(uid(drafts[0].id))"], "Drafts")
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        XCTAssertEqual(keptNotes, [])
    }

    /// The copy's own mailbox, with mail come since the copy was kept: the
    /// launch's first page has the new letters on top, and the oldest kept
    /// rows are not on it. The copy stays, and those rows are still drawn
    /// while the page waits for his ticks or for a finger to lift
    /// (`KeptSwap`), and in a conversation opened from the kept page before
    /// the listing, which outlasts the swap. The server has named no letter
    /// under their UIDs in this launch, so each is asked about once, at one
    /// round trip: Edit mode's Mark and the pane's Flag send one `UID FETCH`
    /// of the Gmail message id before the STORE, and a second write on the
    /// row the STORE alone; a letter opened asks for the id in its own
    /// FETCH; and the conversation's earlier letter, flagged after the swap,
    /// is asked about first too. A kept row the page has sends the STORE
    /// alone. The Inbox's listing, which showed the copy to be this
    /// mailbox's, used to let all of them go unasked (`MailShelf.unproven`);
    /// a call naming its letter goes by what the server has named under the
    /// UID in this launch.
    @MainActor
    func testAKeptRowPushedOffTheFreshPageByNewMailIsAskedAboutOnce() async throws {
        // A reply to the oldest letter the kept page will have beside it:
        // a conversation on that page, its earlier letter at the bottom.
        let before = server.uids(in: Server.inbox)
        let earlier = try XCTUnwrap(server.letter(uid: before[before.count - 49], in: Server.inbox))
        server.deliver(Server.Letter(from: Server.jane, to: [Server.owner], subject: "Re: " + earlier.subject,
                                     date: Server.newestDate.addingTimeInterval(600),
                                     text: "Agreed.\r\n", flags: ["\\Seen"],
                                     messageID: "<agreed@example.com>", inReplyTo: earlier.messageID,
                                     joins: earlier.messageID),
                       to: [Server.inbox, Server.allMail])
        try await earlierLaunch()
        // Four letters come while the app is closed.
        for n in 1...4 {
            server.arrive(Server.Letter(from: Server.sam, to: [Server.owner], subject: "Come since \(n)",
                                        date: Server.newestDate.addingTimeInterval(TimeInterval(600 + 600 * n)),
                                        text: "Hello.\r\n", messageID: "<since-\(n)@example.org>"),
                          in: [Server.inbox, Server.allMail])
        }
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let kept = try XCTUnwrap(shelf.page(of: "inbox")).rows
        let stack = try XCTUnwrap(MessageThread.rows(for: kept, grouped: true)
            .first { $0.messages.count == 2 })
        let inConversation = try XCTUnwrap(stack.messages.first { $0.id != stack.newest.id })
        XCTAssertEqual(inConversation.id, kept.last?.id)

        // The conversation opened at launch, before the listing: its newest
        // letter is asked about by its own FETCH, as it always was.
        _ = try await repository.open(stack.newest)

        let list = ListLetters()
        list.showKept(kept)
        var over = OverKept()
        XCTAssertTrue(over.fetch(showingKept: list.fromShelf, quietly: false))
        let asked = list.askingAfresh()
        let first = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        over.came(first, asked: asked)
        XCTAssertEqual(keptNotes, [], "the same mailbox: the copy stays")
        for (ticked, touching) in [(true, false), (false, true)] {
            let held = KeptSwap.swap(atTop: true, searching: false, ticked: ticked, touching: touching)
            XCTAssertNil(over.landing(showingKept: list.fromShelf, held), "the page waits")
        }
        XCTAssertEqual(list.shown.map(\.id), kept.map(\.id), "the kept rows are what he sees")
        let onPage = Set(first.map(\.id))
        let lacked = kept.filter { !onPage.contains($0.id) }
        XCTAssertEqual(lacked.count, 4)
        let (marked, flagged, opened) = (lacked[0], lacked[1], lacked[2])
        XCTAssertEqual(lacked[3].id, inConversation.id)
        let listed = try XCTUnwrap(kept.dropFirst(5).first { onPage.contains($0.id) })

        // Edit mode's Mark as Unread under his ticks, as `applyRead` makes it.
        server.clearLog()
        XCTAssertTrue(marked.isRead)
        try await repository.setRead(false, on: marked)
        XCTAssertEqual(server.log.map(\.command), ["UID FETCH \(uid(marked.id)) (UID X-GM-MSGID)",
                                                   "UID STORE \(uid(marked.id)) -FLAGS.SILENT (\\Seen)"])

        // The pane's Flag, and its Flag again: asked once.
        server.clearLog()
        let done = await PaneActions.run(.flag(true), on: flagged, inFolderWithRole: .inbox,
                                         list: list, repository: repository, requestSweep: {})
        XCTAssertTrue(done)
        XCTAssertEqual(server.log.map(\.command), ["UID FETCH \(uid(flagged.id)) (UID X-GM-MSGID)",
                                                   "UID STORE \(uid(flagged.id)) +FLAGS.SILENT (\\Flagged)"])
        server.clearLog()
        try await repository.setFlagged(false, on: flagged)
        XCTAssertEqual(server.log.map(\.command), ["UID STORE \(uid(flagged.id)) -FLAGS.SILENT (\\Flagged)"])

        // A letter opened, its id asked in its own FETCH.
        server.clearLog()
        let letter = try await repository.open(opened)
        XCTAssertEqual(letter.subject, opened.subject)
        XCTAssertEqual(server.log.map(\.command), ["UID FETCH \(uid(opened.id)) (UID X-GM-MSGID BODY.PEEK[])"])

        // A kept row the fresh page has: the STORE alone.
        server.clearLog()
        try await repository.setFlagged(true, on: listed)
        XCTAssertEqual(server.log.map(\.command), ["UID STORE \(uid(listed.id)) +FLAGS.SILENT (\\Flagged)"])

        // The ticks go and the fresh page is on the list; the conversation
        // opened at launch still has its earlier letter, and flags it.
        let unticked = KeptSwap.swap(atTop: true, searching: false, ticked: false, touching: false)
        let fresh = try XCTUnwrap(over.landing(showingKept: list.fromShelf, unticked))
        _ = list.fetchedAfresh(fresh.page, asked: fresh.asked)
        XCTAssertEqual(list.shown.map(\.id), first.map(\.id))
        server.clearLog()
        let fromConversation = await PaneActions.run(.flag(true), on: inConversation, inFolderWithRole: .inbox,
                                                     list: list, repository: repository, requestSweep: {})
        XCTAssertTrue(fromConversation)
        XCTAssertEqual(server.log.map(\.command),
                       ["UID FETCH \(uid(inConversation.id)) (UID X-GM-MSGID)",
                        "UID STORE \(uid(inConversation.id)) +FLAGS.SILENT (\\Flagged)"])

        XCTAssertFalse(server.flags(uid: uid(marked.id), in: Server.inbox).contains("\\Seen"))
        XCTAssertTrue(server.flags(uid: uid(inConversation.id), in: Server.inbox).contains("\\Flagged"))
        XCTAssertEqual(keptNotes, [])
    }

    /// A write or a letter opened that names no letter goes by the rules it
    /// always did. On Gmail, a kept row before the Inbox's listing is asked
    /// about by the id it was kept with, and after it a row kept for All
    /// Mail is not, the mailbox having been shown to be the copy's
    /// (`MailShelf.unproven`). On a server without Gmail's extension no row
    /// has an id to name, kept or listed, and nothing is asked: the
    /// UIDVALIDITY each write names is what tells, as it always was.
    func testAWriteNamingNoLetterAndAServerWithoutGmailsExtensionGoAsTheyDid() async throws {
        try await earlierLaunch(listing: [Server.allMail])
        var shelf = makeShelf()
        var repository = makeRepository(shelf: shelf)
        let rows = try XCTUnwrap(shelf.page(of: "inbox")).rows
        let allMail = try XCTUnwrap(shelf.page(of: Server.allMail)).rows
        server.clearLog()
        try await repository.setRead(true, id: rows[0].id, mailboxID: "inbox")
        XCTAssertEqual(verbs, ["LOGIN", "NOOP", "LIST", "SELECT", "UID FETCH", "UID STORE"])
        XCTAssertEqual(command(4), "UID FETCH \(uid(rows[0].id)) (UID X-GM-MSGID)")
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        try await repository.setFlagged(true, id: allMail[5].id, mailboxID: Server.allMail)
        _ = try await repository.loadMessage(id: allMail[6].id, mailboxID: Server.allMail)
        XCTAssertEqual(server.log.filter(\.isUIDCommand).map(\.command),
                       ["UID STORE \(uid(allMail[5].id)) +FLAGS.SILENT (\\Flagged)",
                        "UID FETCH \(uid(allMail[6].id)) (UID BODY.PEEK[])"], "Gmail, naming nothing")

        server = ScriptedIMAPServer()
        server.withheldCapabilities = ["X-GM-EXT-1"]
        MailShelf.wipe(root: kept)
        let before = try await earlierLaunch()
        XCTAssertEqual(before.compactMap(\.gmailMessageID), [])
        shelf = makeShelf()
        repository = makeRepository(shelf: shelf)
        let plain = try XCTUnwrap(shelf.page(of: "inbox")).rows
        XCTAssertEqual(plain.compactMap(\.gmailMessageID), [], "kept with none")
        server.clearLog()
        _ = try await repository.open(plain[1])
        try await repository.setFlagged(true, on: plain[1])
        XCTAssertEqual(server.log.filter(\.isUIDCommand).map(\.command),
                       ["UID FETCH \(uid(plain[1].id)) (UID BODY.PEEK[])",
                        "UID STORE \(uid(plain[1].id)) +FLAGS.SILENT (\\Flagged)"], "a kept row")
        let listed = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        _ = try await repository.open(listed[2])
        try await repository.setRead(true, on: listed[2])
        XCTAssertEqual(server.log.map(\.command),
                       ["UID FETCH \(uid(listed[2].id)) (UID BODY.PEEK[])",
                        "UID STORE \(uid(listed[2].id)) +FLAGS.SILENT (\\Seen)"], "a listed row")
    }

    /// A folder renumbered in this launch: what the server named under its
    /// UIDs is forgotten with the numbering. A row under the new numbers
    /// that no listing has brought yet is asked about, and goes once the
    /// server names its letter there, rather than being refused on what the
    /// old numbers said under the same UID. A row under the old numbers is
    /// refused with nothing sent, by the UIDVALIDITY it names (B-039).
    func testANewUIDValidityForgetsWhatTheOldNumbersNamed() async throws {
        let repository = makeRepository(shelf: makeShelf())
        _ = try await repository.folders()
        let before = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let old = try XCTUnwrap(before.first)
        // Renumbered while the connection was down, where a SELECT shows it.
        await server.resetConnections()
        server.renumber(Server.inbox, validity: 700_001, firstUID: 1_002)
        let after = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 1)
        XCTAssertEqual(after.map { uid($0.id) }, [uid(old.id) + 2], "the new newest, alone")
        let there = try XCTUnwrap(server.gmailMessageID(uid: uid(old.id), in: Server.inbox))
        XCTAssertNotEqual(there, old.gmailMessageID, "the old newest's UID names the letter before it")
        let renumbered = MessageSummary(id: "700001/\(uid(old.id))", mailboxID: "inbox", sender: "",
                                        subject: "", preview: "", date: old.date, isRead: true,
                                        isFlagged: false, gmailMessageID: there)
        server.clearLog()

        try await repository.setFlagged(true, on: renumbered)
        XCTAssertEqual(server.log.map(\.command), ["UID FETCH \(uid(old.id)) (UID X-GM-MSGID)",
                                                   "UID STORE \(uid(old.id)) +FLAGS.SILENT (\\Flagged)"])
        server.clearLog()
        let stale = await refusal { try await repository.setFlagged(true, on: old) }
        XCTAssertEqual(stale as? MailError, .cannotConnect)
        XCTAssertEqual(server.log.map(\.command), [])
    }

    /// A folder tapped in the kept folder pane before the launch's LIST
    /// has landed, or with none yet: its first page waits for the LIST, so
    /// its rows are counted in All Mail and in the Inbox as Gmail counts
    /// them, and are kept so. Without it, reading one left All Mail's count
    /// high, at this launch and every one after until the folder was listed
    /// again.
    func testAFolderListedBeforeTheLaunchsListIsCountedAsGmailCountsIt() async throws {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        server.clearLog()

        let starred = try await repository.listMessages(in: Server.starred, beforeUID: nil, limit: 50)
        XCTAssertEqual(verbs, ["LOGIN", "LIST", "SELECT", "UID SEARCH", "UID FETCH"])
        XCTAssertFalse(starred.isEmpty)
        shelf.flush()
        for (label, rows) in [("listed", starred),
                              ("kept", makeShelf().page(of: Server.starred)?.rows ?? [])] {
            XCTAssertEqual(rows.count, starred.count, label)
            for row in rows {
                XCTAssertEqual(Set(row.countedFolderIDs), [Server.starred, Server.inbox, Server.allMail],
                               "\(label): \(row.subject)")
            }
        }
    }

    // MARK: - Phase 1: the wire and the log

    /// A launch with a copy kept sends exactly what a launch without one
    /// sends: LOGIN, the one LIST, the Inbox's SELECT, SEARCH and page, and
    /// then the counts. Drawing the kept folders and Inbox sends nothing.
    func testALaunchWithACopyKeptSendsWhatALaunchWithoutOneSends() async throws {
        var launches: [[Server.LogEntry]] = []
        for keeping in [false, true] {
            server = ScriptedIMAPServer()
            MailShelf.wipe(root: kept)
            if keeping { try await earlierLaunch() }
            let sent = server.log.count
            let connections = server.connectionsBegun

            let repository = makeRepository(shelf: makeShelf())
            let folders = repository.shelf?.folders
            let page = ListOpening.kept(for: .inboxBeforeListing, jumpingTo: nil,
                                        from: repository.shelf)
            XCTAssertEqual(folders?.count, keeping ? 7 : nil)
            XCTAssertEqual(page?.rows.count, keeping ? 50 : nil)
            XCTAssertEqual(server.log.count, sent)
            XCTAssertEqual(server.connectionsBegun, connections)

            let sweeps = await SweepCoalescer(held: true) { _ = try? await repository.listMailboxes() }
            await sweeps.request()
            async let names = repository.folders()
            async let firstPage = repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
            _ = try await (names, firstPage)
            await sweeps.release(runningOwed: true)
            try await finishing { await sweeps.idle() }
            launches.append(Array(server.log.dropFirst(sent)))
            // Each pass has a server of its own; `tearDown` sees the last.
            XCTAssertEqual(server.violations, [], keeping ? "with a copy" : "without one")
        }
        XCTAssertEqual(launches[1].map(\.command), launches[0].map(\.command))
        XCTAssertEqual(Array(launches[1].prefix(5).map(\.verb)),
                       ["LOGIN", "LIST", "SELECT", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(launches[1].count, 5 + 1 + 7)
    }

    /// Nothing kept is written to the connection log: drawing the kept
    /// pages and folders writes nothing at all, and a write vouched for and
    /// refused, and a listing that throws the copy away, say what happened
    /// in numbers and the folder's name, and not a subject, a sender or a
    /// preview of anything kept.
    func testNothingKeptIsWrittenToTheConnectionLog() async throws {
        try await earlierLaunch(listing: [Server.sent])
        server.renumber(Server.inbox, validity: server.uidValidity(of: Server.inbox), firstUID: 1_002)
        Diagnostics.clear()

        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let folders = try XCTUnwrap(shelf.folders)
        let inbox = try XCTUnwrap(shelf.page(of: "inbox"))
        let sent = try XCTUnwrap(shelf.page(of: Server.sent))
        XCTAssertEqual(folders.count, 7)
        XCTAssertEqual(Diagnostics.entries.count, 0, "drawing them logs nothing")

        _ = try? await repository.setFlagged(true, on: inbox.rows[1])
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)

        // His correspondence as kept, less his own address, which is the
        // account's and is on LOGIN, and which Sent's rows are from.
        var words: Set<String> = []
        for row in inbox.rows + sent.rows {
            words.insert(row.subject)
            if row.sender != Server.owner.formatted { words.insert(row.sender) }
            if !row.preview.isEmpty { words.insert(row.preview) }
        }
        XCTAssertGreaterThan(words.count, 100)
        let beside = Diagnostics.entries.filter { $0.direction != .received }
        XCTAssertEqual(beside.map(\.text).filter { $0.hasPrefix("KEPT-") },
                       ["KEPT-UNVOUCHED folder=INBOX nothing-sent",
                        "KEPT-DISCARDED folder=INBOX reason=msgid"])
        let leaks = beside.filter { entry in words.contains { entry.text.contains($0) } }
        XCTAssertEqual(leaks.map(\.text), [])
    }
}

