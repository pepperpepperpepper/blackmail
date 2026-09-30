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
/// this mailbox's; a write on a kept row vouched for first; a launch that
/// sends what it always did; and nothing kept in the log.
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
        _ = try? await repository.setRead(true, id: unread.id, mailboxID: "inbox")
        _ = try? await repository.setFlagged(true, id: other.id, mailboxID: "inbox")
        _ = try? await repository.move(moving.id, from: "inbox", to: Server.starred)
        _ = try? await repository.delete(binned.id, from: "inbox")
        // The move and the delete's move are each refused twice, MOVE and
        // the COPY it falls back to.
        XCTAssertEqual(server.log.filter { $0.status == "NO" }.count, 6)
        XCTAssertEqual(row(unread)?.isRead, false)
        XCTAssertEqual(row(other)?.isFlagged, false)
        XCTAssertNotNil(row(moving))
        XCTAssertNotNil(row(binned))
        XCTAssertEqual(shelf.page(of: "inbox")?.rows.map(\.id), inbox.map(\.id))

        server.refusedVerbs = []
        try await repository.setRead(true, id: unread.id, mailboxID: "inbox")
        try await repository.setFlagged(true, id: plain.id, mailboxID: "inbox")
        try await repository.move(moving.id, from: "inbox", to: Server.starred)
        try await repository.delete(binned.id, from: "inbox")

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
    /// mark goes after one `UID FETCH` of the row's Gmail message id, which
    /// matches, and nothing more is asked of that row. Another kept row is
    /// asked for in turn. Once the Inbox has been listed from the top and
    /// found to be the mailbox the copy was kept from, a write on a row
    /// kept from before goes as it always did, in the Inbox and in any
    /// other folder kept.
    func testAnEarlyWriteOnAKeptRowIsVouchedForOnceBeforeItGoes() async throws {
        try await earlierLaunch(listing: [Server.allMail])
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let rows = try XCTUnwrap(shelf.page(of: "inbox")).rows
        let allMail = try XCTUnwrap(shelf.page(of: Server.allMail)).rows
        server.clearLog()

        try await repository.setRead(true, id: rows[0].id, mailboxID: "inbox")
        XCTAssertEqual(verbs, ["LOGIN", "NOOP", "LIST", "SELECT", "UID FETCH", "UID STORE"])
        XCTAssertEqual(command(4), "UID FETCH \(uid(rows[0].id)) (UID X-GM-MSGID)")
        XCTAssertTrue(server.flags(uid: uid(rows[0].id), in: Server.inbox).contains("\\Seen"))

        server.clearLog()
        try await repository.setFlagged(true, id: rows[0].id, mailboxID: "inbox")
        XCTAssertEqual(verbs, ["UID STORE"], "vouched for once")
        server.clearLog()
        try await repository.setFlagged(true, id: rows[1].id, mailboxID: "inbox")
        XCTAssertEqual(verbs, ["UID FETCH", "UID STORE"])

        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        try await repository.setFlagged(true, id: rows[2].id, mailboxID: "inbox")
        try await repository.delete(rows[3].id, from: "inbox")
        XCTAssertEqual(verbs, ["UID STORE", "UID MOVE"], "the Inbox is listed: nothing to vouch for")
        server.clearLog()
        try await repository.setFlagged(true, id: allMail[5].id, mailboxID: Server.allMail)
        XCTAssertEqual(verbs, ["SELECT", "UID STORE"], "nor in All Mail, the same mailbox")
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
        for write in [{ try await repository.setRead(true, id: read.id, mailboxID: "inbox") },
                      { try await repository.delete(deleted.id, from: "inbox") }] {
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

        let deleted = await refusal { try await repository.delete(binned.id, from: Server.trash) }
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

        try await repository.setFlagged(true, id: rows[0].id, mailboxID: "inbox")
        _ = try await repository.loadMessage(id: rows[1].id, mailboxID: "inbox")
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

        try await repository.delete(trash[0].id, from: Server.trash)
        try await repository.deleteDraft(drafts[0].id)
        try await repository.move(spammed.id, from: "inbox", to: Server.spam)
        try await repository.move(filed.id, from: Server.allMail, to: Server.starred)
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

        try await repository.setFlagged(true, id: row.id, mailboxID: "inbox")
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

    /// A kept row opened before anything in this launch has shown the
    /// server to be the mailbox the copy was kept from: the FETCH that
    /// brings the letter asks for its Gmail message id beside the body, one
    /// round trip as ever, and the letter is shown as the id matches. PEEK:
    /// the FETCH marks nothing read. Vouched for, the row is not asked
    /// about again, opened or written.
    func testALetterOpenedFromAKeptRowIsVouchedForByTheFetchThatBringsIt() async throws {
        try await earlierLaunch()
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let tapped = try XCTUnwrap(shelf.page(of: "inbox")).rows[0]
        XCTAssertFalse(tapped.isRead)
        server.clearLog()

        let letter = try await repository.loadMessage(id: tapped.id, mailboxID: "inbox")
        XCTAssertEqual(verbs, ["LOGIN", "LIST", "SELECT", "UID FETCH"])
        XCTAssertEqual(command(3), "UID FETCH \(uid(tapped.id)) (UID X-GM-MSGID BODY.PEEK[])")
        XCTAssertEqual(letter.subject, tapped.subject)
        XCTAssertFalse((letter.textBody ?? letter.htmlBody ?? "").isEmpty)
        XCTAssertFalse(server.flags(uid: uid(tapped.id), in: Server.inbox).contains("\\Seen"),
                       "PEEK: the FETCH marks nothing read")

        server.clearLog()
        _ = try await repository.loadMessage(id: tapped.id, mailboxID: "inbox")
        try await repository.setRead(true, id: tapped.id, mailboxID: "inbox")
        XCTAssertEqual(server.log.map(\.command),
                       ["UID FETCH \(uid(tapped.id)) (UID BODY.PEEK[])",
                        "UID STORE \(uid(tapped.id)) +FLAGS.SILENT (\\Seen)"])
        XCTAssertEqual(Diagnostics.entries.filter { $0.text.hasPrefix("KEPT-") }.map(\.text), [])
    }

    /// Once the Inbox's listing has proven the mailbox, a letter opened
    /// from a row kept from before is fetched byte for byte as every letter
    /// is, and so is one opened with no copy kept at all: the wire does not
    /// change for a row the server has vouched for.
    func testALetterFromAProvenRowIsFetchedAsItAlwaysWas() async throws {
        try await earlierLaunch()
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let kept = try XCTUnwrap(shelf.page(of: "inbox")).rows
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let plain = makeRepository()
        _ = try await plain.folders()
        server.clearLog()

        _ = try await repository.loadMessage(id: kept[4].id, mailboxID: "inbox")
        _ = try await plain.loadMessage(id: kept[5].id, mailboxID: "inbox")
        XCTAssertEqual(server.log.filter { $0.verb == "UID FETCH" }.map(\.command),
                       ["UID FETCH \(uid(kept[4].id)) (UID BODY.PEEK[])",
                        "UID FETCH \(uid(kept[5].id)) (UID BODY.PEEK[])"])
    }

    /// Kept rows whose UIDs name other letters now, as in another mailbox
    /// under the same numbers. Opened, the FETCH says so and nothing of the
    /// letter comes back, and the tap's read mark after it asks again and
    /// writes nothing. The other way round, the read mark answered first
    /// and the row gone from the kept page, the letter is still asked about
    /// and not shown: a row the server has disowned is never taken for one
    /// that was never kept.
    func testALetterOpenedFromAKeptRowThatIsAnotherLetterShowsNothingAndNothingIsWritten() async throws {
        try await earlierLaunch()
        server.renumber(Server.inbox, validity: server.uidValidity(of: Server.inbox), firstUID: 1_002)
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let rows = try XCTUnwrap(shelf.page(of: "inbox")).rows
        let (opened, readFirst) = (rows[1], rows[2])
        let flags = [opened, readFirst].map { server.flags(uid: uid($0.id), in: Server.inbox) }
        server.clearLog()

        let open = await refusal { _ = try await repository.loadMessage(id: opened.id, mailboxID: "inbox") }
        XCTAssertEqual(open as? MailShelf.NotTheKeptLetter, Self.notKept)
        let mark = await refusal { try await repository.setRead(true, id: opened.id, mailboxID: "inbox") }
        XCTAssertEqual(mark as? MailShelf.NotTheKeptLetter, Self.notKept)

        let first = await refusal { try await repository.setRead(true, id: readFirst.id, mailboxID: "inbox") }
        XCTAssertEqual(first as? MailShelf.NotTheKeptLetter, Self.notKept)
        let then = await refusal { _ = try await repository.loadMessage(id: readFirst.id, mailboxID: "inbox") }
        XCTAssertEqual(then as? MailShelf.NotTheKeptLetter, Self.notKept)

        XCTAssertEqual(server.log.filter { $0.verb == "UID FETCH" }.map(\.command),
                       ["UID FETCH \(uid(opened.id)) (UID X-GM-MSGID BODY.PEEK[])",
                        "UID FETCH \(uid(opened.id)) (UID X-GM-MSGID)",
                        "UID FETCH \(uid(readFirst.id)) (UID X-GM-MSGID)",
                        "UID FETCH \(uid(readFirst.id)) (UID X-GM-MSGID BODY.PEEK[])"])
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
    /// extension to ask: a kept row is vouched for by nothing, so a letter
    /// opened from it shows nothing and a write on it goes nowhere, as the
    /// write's vouching does, and nothing is fetched to find out.
    func testAKeptRowOnAServerWithoutGmailsExtensionIsNeitherOpenedNorWritten() async throws {
        try await earlierLaunch()
        server.withheldCapabilities = ["X-GM-EXT-1"]
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let rows = try XCTUnwrap(shelf.page(of: "inbox")).rows
        XCTAssertNotNil(rows[0].gmailMessageID)
        server.clearLog()

        let open = await refusal { _ = try await repository.loadMessage(id: rows[0].id, mailboxID: "inbox") }
        XCTAssertEqual(open as? MailShelf.NotTheKeptLetter, Self.notKept)
        let flag = await refusal { try await repository.setFlagged(true, id: rows[1].id, mailboxID: "inbox") }
        XCTAssertEqual(flag as? MailShelf.NotTheKeptLetter, Self.notKept)
        XCTAssertEqual(verbs.filter { $0.hasPrefix("UID") }, [])
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

        _ = try? await repository.setFlagged(true, id: inbox.rows[1].id, mailboxID: "inbox")
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
