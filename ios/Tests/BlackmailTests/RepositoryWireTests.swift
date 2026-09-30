import XCTest
@testable import Blackmail

/// The shipping `IMAPMailRepository`, over the shipping `IMAPClient`, with
/// `ScriptedIMAPServer` where the socket would be.
///
/// Everything else in this suite tests the pieces the repository is built
/// from. These test the repository itself: what it sends, in which mailbox,
/// and what it makes of the answers. Until the transport seam existed the
/// repository did not compile on this host at all, so every property below
/// was previously checked only by reading the code or on the iPad.
final class RepositoryWireTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    /// The recipient book's own store, so a run neither reads nor writes
    /// this machine's standard defaults.
    private static let suite = "RepositoryWireTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    /// The repository's clock. Only a test about a quiet spell moves it:
    /// what the repository sends can depend on how long ago it last asked
    /// about a folder (B-045), so on the wall clock a stalled host would add
    /// a NOOP to the exact traffic these tests pin.
    private var clock: ManualClock!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        clock = ManualClock()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
    }

    override func tearDown() {
        // Whatever else a test checked, nothing it did may have put two
        // commands in flight on one connection.
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        server = nil
        book = nil
        clock = nil
        super.tearDown()
    }

    private func makeRepository(password: String? = nil) -> IMAPMailRepository {
        let clock = self.clock!
        return IMAPMailRepository(account: server.account, password: password ?? server.password,
                                  transport: server.transportFactory, recipients: book,
                                  now: { clock.now() }, shelf: keptShelf(for: server.account))
    }

    /// The repository's id for a letter: "<uidvalidity>/<uid>".
    private func id(_ uid: UInt32, in mailbox: String) -> String {
        "\(server.uidValidity(of: mailbox))/\(uid)"
    }

    /// Every subject the server holds in `mailbox`, oldest first.
    private func subjects(in mailbox: String) -> [String] {
        server.uids(in: mailbox).compactMap { server.letter(uid: $0, in: mailbox)?.subject }
    }

    /// Runs `body`, then checks that every UID command it sent ran with
    /// `mailbox` selected and succeeded, and that there was at least one.
    @discardableResult
    private func expectingMailbox<T>(_ mailbox: String,
                                     file: StaticString = #filePath, line: UInt = #line,
                                     _ body: () async throws -> T) async throws -> T {
        let before = server.log.count
        let result = try await body()
        let sent = server.log.dropFirst(before).filter(\.isUIDCommand)
        XCTAssertFalse(sent.isEmpty, "no UID command was sent", file: file, line: line)
        for entry in sent {
            XCTAssertEqual(entry.selected, mailbox, "\(entry)", file: file, line: line)
            XCTAssertEqual(entry.status, "OK", "\(entry)", file: file, line: line)
        }
        return result
    }

    // MARK: - The whole path, once

    func testTheRealRepositoryLogsInListsFoldersPagesTheInboxAndOpensALetter() async throws {
        let repository = makeRepository()

        // Folders: the "[Gmail]" container is \Noselect and not offered, and
        // the order is the fixed one the sidebar depends on.
        let mailboxes = try await repository.listMailboxes()
        XCTAssertEqual(mailboxes.map(\.id), [Server.inbox, Server.drafts, Server.sent, Server.spam,
                                             Server.trash, Server.allMail, Server.starred])
        XCTAssertEqual(mailboxes.map(\.name), ["INBOX", "Drafts", "Sent Mail", "Spam",
                                               "Trash", "All Mail", "Starred"])
        XCTAssertEqual(mailboxes.first?.role, .inbox)
        XCTAssertEqual(mailboxes.first?.unreadCount, 6)
        XCTAssertEqual(mailboxes.first { $0.id == Server.trash }?.role, .trash)

        // Three pages of the Inbox and then nothing, newest first, each
        // row the letter the server holds under that UID.
        let uids = server.uids(in: Server.inbox)
        var rows: [MessageSummary] = []
        var cursor: String?
        for expected in [50, 50, 20, 0] {
            let before = server.log.count
            let page = try await repository.listMessages(in: "inbox", beforeUID: cursor, limit: 50)
            XCTAssertEqual(page.count, expected)
            if cursor != nil {
                // Paging walks the snapshot: one FETCH a page and no SEARCH.
                let sent = server.log.dropFirst(before).map(\.verb)
                XCTAssertEqual(sent, expected == 0 ? [] : ["UID FETCH"])
            }
            rows += page
            cursor = page.last?.id ?? cursor
        }
        XCTAssertEqual(rows.map(\.id), uids.reversed().map { id($0, in: Server.inbox) })
        XCTAssertEqual(rows.map(\.subject),
                       uids.reversed().map { server.letter(uid: $0, in: Server.inbox)?.subject ?? "?" })
        // The second newest has quotes in its subject, which the server
        // sends as a literal inside the ENVELOPE.
        XCTAssertEqual(rows[1].subject, "Letter 119: the \"photos\" one")
        XCTAssertEqual(rows.prefix(7).map(\.isRead), [false, false, false, false, false, false, true])

        // Previews for the first page: two FETCHes, one per byte cap.
        let firstPage = Array(rows.prefix(50))
        let before = server.log.count
        let previews = try await repository.previews(for: firstPage.map(\.id), in: "inbox")
        XCTAssertEqual(previews.count, 50)
        for row in firstPage {
            let text = previews[row.id] ?? ""
            XCTAssertNotNil(text.range(of: "a few words about the", options: .caseInsensitive),
                            row.subject)
            XCTAssertFalse(text.contains("<"), row.subject)
        }
        let previewItems = server.log.dropFirst(before)
            .map { $0.command.split(separator: " ").last ?? "" }
        XCTAssertEqual(Set(previewItems), ["BODY.PEEK[1]<0.2048>)", "BODY.PEEK[1]<0.8192>)"])

        // One letter, whole. Letter 117 is unread and multipart/alternative.
        let target = rows[3]
        let message = try await repository.loadMessage(id: target.id, mailboxID: "inbox")
        XCTAssertEqual(message.subject, "Letter 117: dinner")
        XCTAssertEqual(message.senderAddress, "sam@example.com")
        XCTAssertEqual(message.messageID, "<letter-117@example.org>")
        XCTAssertNotNil(message.textBody?.range(of: "A few words about the dinner."))
        XCTAssertNotNil(message.htmlBody?.range(of: "<b>dinner</b>"))
        XCTAssertEqual(server.log.last?.command, "UID FETCH \(uids[116]) (UID BODY.PEEK[])")
        // PEEK, so opening it did not mark it read behind the user's back.
        XCTAssertFalse(server.flags(uid: uids[116], in: Server.inbox).contains("\\Seen"))

        // All of that on one connection, one login and one SELECT, with
        // nothing refused.
        XCTAssertEqual(server.connectionsOpened, 1)
        XCTAssertEqual(server.log.filter { $0.verb == "LOGIN" }.count, 1)
        XCTAssertEqual(server.log.filter { $0.verb == "SELECT" }.map(\.command), ["SELECT \"INBOX\""])
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
    }

    // MARK: - Which mailbox each command ran in

    func testTheServerLogRecordsTheMailboxEachCommandWasMeantFor() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        // LIST and STATUS need no mailbox, and nothing is selected yet.
        XCTAssertTrue(server.log.allSatisfy { $0.selected == nil })

        let inbox = try await expectingMailbox(Server.inbox) {
            try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)
        }
        try await expectingMailbox(Server.inbox) {
            try await repository.previews(for: inbox.map(\.id), in: "inbox")
        }
        let sent = try await expectingMailbox(Server.sent) {
            try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 20)
        }
        let reply = try await expectingMailbox(Server.sent) {
            try await repository.loadMessage(id: sent[0].id, mailboxID: Server.sent)
        }
        XCTAssertEqual(reply.subject, sent[0].subject)

        // Back to the Inbox. The SELECT itself is logged against the mailbox
        // it left, which is what "selected at the time" means.
        let letter = try await expectingMailbox(Server.inbox) {
            try await repository.loadMessage(id: inbox[2].id, mailboxID: "inbox")
        }
        XCTAssertEqual(letter.subject, inbox[2].subject)
        let reselect = server.log.last { $0.verb == "SELECT" }
        XCTAssertEqual(reselect?.command, "SELECT \"INBOX\"")
        XCTAssertEqual(reselect?.selected, Server.sent)

        try await expectingMailbox(Server.inbox) {
            try await repository.setRead(true, id: inbox[2].id, mailboxID: "inbox")
        }
        let readUID = Array(server.uids(in: Server.inbox).reversed())[2]
        XCTAssertTrue(server.flags(uid: readUID, in: Server.inbox).contains("\\Seen"))

        let binned = try await expectingMailbox(Server.trash) {
            try await repository.search(in: Server.trash, query: "garden", scope: .currentMailbox,
                                        beforeUID: nil, limit: 20)
        }
        XCTAssertEqual(binned.map(\.subject), ["Binned: old garden"])

        // Delete from the Inbox is a MOVE issued in the Inbox, and the
        // letter ends up in Trash and nowhere else.
        let doomed = inbox[4]
        let doomedUID = Array(server.uids(in: Server.inbox).reversed())[4]
        let subject = try XCTUnwrap(server.letter(uid: doomedUID, in: Server.inbox)?.subject)
        try await expectingMailbox(Server.inbox) {
            try await repository.delete(doomed.id, from: "inbox")
        }
        XCTAssertEqual(server.log.last?.command, "UID MOVE \(doomedUID) \"[Gmail]/Trash\"")
        XCTAssertFalse(server.uids(in: Server.inbox).contains(doomedUID))
        XCTAssertTrue(subjects(in: Server.trash).contains(subject))
        XCTAssertFalse(subjects(in: Server.allMail).contains(subject))

        XCTAssertEqual(server.connectionsOpened, 1)
    }

    // MARK: - The fake's own guarantees, through the real client

    /// Writes `command` down `link` as it stands and reads to its tagged
    /// answer, which it returns. No client in between.
    private func exchange(_ link: any MailTransport, _ tag: String,
                          _ command: String) async throws -> String {
        try await link.writeLine("\(tag) \(command)")
        while true {
            let line = try await link.readLine()
            if line.hasPrefix(tag + " ") { return line }
        }
    }

    func testAUIDCommandWithNoMailboxSelectedIsRefusedOnThatConnection() async throws {
        // Written straight down a connection of its own, because the client
        // no longer sends a UID command without the SELECT it needs.
        let link = server.transportFactory(server.account.imapHost, server.port)
        try await link.open()
        _ = try await link.readLine()
        _ = try await exchange(link, "a1", "LOGIN \"\(server.username)\" \"\(server.password)\"")
        let refused = try await exchange(link, "a2", "UID SEARCH ALL")
        XCTAssertTrue(refused.hasPrefix("a2 BAD"), refused)
        XCTAssertEqual(server.log.last, Server.LogEntry(connection: 1, selected: nil,
                                                        command: "UID SEARCH ALL", status: "BAD"))

        let client = IMAPClient(account: server.account, transport: server.transportFactory)
        try await client.connect(password: server.password)
        let all = try await client.searchAll(in: Server.inbox)
        XCTAssertEqual(all, IMAPMailboxUIDs(validity: server.uidValidity(of: Server.inbox),
                                            uids: server.uids(in: Server.inbox)))

        // Selection belongs to the connection, not the server: the first one
        // still has nothing selected, whatever the second has open.
        let again = try await exchange(link, "a3", "UID SEARCH ALL")
        XCTAssertTrue(again.hasPrefix("a3 BAD"), again)
        XCTAssertEqual(server.log.last?.connection, 1)
        await link.close()
    }

    func testASocketThatDiedWhileTheIPadSleptCostsOneReconnectAndTheReadStillLands() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)

        await server.resetConnections()
        let message = try await repository.loadMessage(id: rows[0].id, mailboxID: "inbox")

        XCTAssertEqual(message.subject, rows[0].subject)
        XCTAssertEqual(server.connectionsOpened, 2)
        // The FETCH went into the dead socket and never arrived...
        XCTAssertEqual(server.lostWrites.map(\.verb), ["UID FETCH"])
        // ...and the read retry sent it again on the new connection, with
        // the Inbox selected there first.
        let retried = server.log.filter { $0.connection == 2 && $0.isUIDCommand }
        XCTAssertEqual(retried.map(\.verb), ["UID FETCH"])
        XCTAssertEqual(retried.map(\.selected), [Server.inbox])
    }

    // MARK: - Every read survives a socket that died while he was away

    /// An "All Mailboxes" search: All Mail, Trash and Spam at once.
    private func searchEverywhere(_ repository: IMAPMailRepository,
                                  for query: String) async throws -> [MessageSummary] {
        try await repository.search(in: "inbox", query: query, scope: .allMailboxes,
                                    beforeUID: nil, limit: 50)
    }

    func testTheFirstSearchEverywhereAfterADeadSocketStillFindsWhatIsInTheBin() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        let before = try await searchEverywhere(repository, for: "garden")
        XCTAssertTrue(before.contains { $0.subject == "Binned: old garden" })
        XCTAssertTrue(before.contains { $0.mailboxID == Server.spam })
        XCTAssertTrue(before.contains { $0.mailboxID == Server.allMail })

        await server.resetConnections()
        let after = try await searchEverywhere(repository, for: "garden")

        // The Trash's SELECT went into the dead socket. That failure used to
        // be swallowed as "the Trash would not open", the Spam search
        // reconnected, and the binned letter was silently missing from the
        // results. Now the whole search runs again on one new connection.
        XCTAssertEqual(after.map(\.id), before.map(\.id))
        XCTAssertEqual(server.lostWrites.map(\.command), ["SELECT \"[Gmail]/Trash\""])
        XCTAssertEqual(server.connectionsOpened, 2)
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
    }

    /// Straight after the folder was listed, so the SEARCH is the first
    /// thing written into the dead socket. After a quiet spell, which is
    /// how a socket dies on the iPad, it is the NOOP in front of it
    /// (`ArrivingMailTests`).
    func testTheFirstSearchInAFolderAfterADeadSocketCostsOneReconnect() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)
        let before = try await repository.search(in: "inbox", query: "dinner", scope: .currentMailbox,
                                                 beforeUID: nil, limit: 50)
        XCTAssertFalse(before.isEmpty)

        await server.resetConnections()
        let after = try await repository.search(in: "inbox", query: "dinner", scope: .currentMailbox,
                                                beforeUID: nil, limit: 50)

        XCTAssertEqual(after.map(\.id), before.map(\.id))
        XCTAssertEqual(server.lostWrites.map(\.verb), ["UID SEARCH"])
        // The whole cost of the dead socket: a login, the SELECT the new
        // session needs, and the search again. No CAPABILITY anywhere.
        XCTAssertEqual(server.log.filter { $0.connection == 2 }.map(\.verb),
                       ["LOGIN", "SELECT", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(server.connectionsOpened, 2)
    }

    /// Straight after the folder was listed, as above.
    func testAJumpToADayAfterADeadSocketStillLands() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)
        let day = Server.newestDate.addingTimeInterval(-40 * 86_400)
        let first = try await repository.messages(around: day, in: "inbox", limit: 20)
        let before = try XCTUnwrap(first)

        await server.resetConnections()
        let second = try await repository.messages(around: day, in: "inbox", limit: 20)
        let after = try XCTUnwrap(second)

        XCTAssertEqual(after.messages.map(\.id), before.messages.map(\.id))
        XCTAssertEqual(after.anchorIndex, before.anchorIndex)
        XCTAssertEqual(server.lostWrites.map(\.verb), ["UID SEARCH"])
        XCTAssertEqual(server.connectionsOpened, 2)
    }

    func testLoadingUpwardAfterADeadSocketStillLoads() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let before = try await repository.listMessages(in: "inbox", afterUID: rows[30].id, limit: 10)
        XCTAssertEqual(before.map(\.id), rows[20..<30].map(\.id))

        await server.resetConnections()
        let after = try await repository.listMessages(in: "inbox", afterUID: rows[30].id, limit: 10)

        XCTAssertEqual(after.map(\.id), before.map(\.id))
        XCTAssertEqual(server.lostWrites.map(\.verb), ["UID FETCH"])
        XCTAssertEqual(server.connectionsOpened, 2)
    }

    func testATrashThatWillNotOpenCostsOnlyItsOwnHits() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        let everything = try await searchEverywhere(repository, for: "garden")
        server.refusedMailboxes = [Server.trash]
        server.clearLog()

        let hits = try await searchEverywhere(repository, for: "garden")

        // A refusal is not a lost connection: no reconnect, no retry, and
        // Spam and All Mail are still searched.
        XCTAssertEqual(hits.map(\.id), everything.filter { $0.mailboxID != Server.trash }.map(\.id))
        XCTAssertTrue(hits.contains { $0.mailboxID == Server.spam })
        XCTAssertEqual(server.log.filter { $0.status != "OK" }.map(\.command),
                       ["SELECT \"[Gmail]/Trash\""])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    func testBothBinsRefusingStillLeavesTheAllMailHalfOfTheSearch() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        // Leaves All Mail selected, which is the case that went wrong: the
        // two refusals left the server with nothing selected, the repository
        // still believed All Mail was, skipped its SELECT, and the search
        // itself was answered BAD and shown as "Could not search".
        let everything = try await searchEverywhere(repository, for: "garden")
        server.refusedMailboxes = [Server.trash, Server.spam]
        server.clearLog()

        let hits = try await searchEverywhere(repository, for: "garden")

        XCTAssertEqual(hits.map(\.id), everything.filter { $0.mailboxID == Server.allMail }.map(\.id))
        XCTAssertEqual(server.log.filter { $0.status != "OK" }.map(\.command),
                       ["SELECT \"[Gmail]/Trash\"", "SELECT \"[Gmail]/Spam\""])
        XCTAssertEqual(server.log.last { $0.verb == "SELECT" }?.command,
                       "SELECT \"[Gmail]/All Mail\"")
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    func testAFolderThatWillNotOpenDoesNotStrandTheOneOpenBeforeIt() async throws {
        let repository = makeRepository()
        let inbox = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)

        // A label deleted in another client, tapped once.
        server.refusedMailboxes = [Server.starred]
        do {
            _ = try await repository.listMessages(in: Server.starred, beforeUID: nil, limit: 20)
            XCTFail("a folder the server will not open cannot be listed")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }

        // Back to the Inbox, which the repository had open before the
        // refusal and the server no longer has. It has to be selected again.
        let again = try await expectingMailbox(Server.inbox) {
            try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)
        }
        XCTAssertEqual(again.map(\.id), inbox.map(\.id))

        // The same through a preview pass that is refused, for rows listed
        // while the Trash would still open. Its SELECT is refused and the
        // FETCH that depended on it is not sent. Then the next page of the
        // Inbox, which walks the snapshot and sends only a FETCH, after
        // the SELECT the refusal made necessary.
        server.refusedMailboxes = []
        let binned = try await repository.listMessages(in: Server.trash, beforeUID: nil, limit: 5)
        _ = try await repository.loadMessage(id: again[0].id, mailboxID: "inbox")
        server.refusedMailboxes = [Server.trash]
        let mark = server.log.count
        let previews = try? await repository.previews(for: binned.map(\.id), in: Server.trash)
        XCTAssertNil(previews)
        XCTAssertEqual(server.log.dropFirst(mark).map(\.command), ["SELECT \"[Gmail]/Trash\""])
        let next = try await expectingMailbox(Server.inbox) {
            try await repository.listMessages(in: "inbox", beforeUID: again.last?.id, limit: 20)
        }
        XCTAssertEqual(next.count, 20)
        XCTAssertTrue(Set(next.map(\.id)).isDisjoint(with: again.map(\.id)))
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    func testASearchCancelledByTheNextKeystrokeStopsWithoutReconnecting() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        server.holdReplies(to: "UID SEARCH")
        server.clearLog()

        let superseded = Task {
            try await repository.search(in: "inbox", query: "garden", scope: .allMailboxes,
                                        beforeUID: nil, limit: 50)
        }
        // The Trash search is on the wire and its answer is held back: the
        // next keystroke lands now, whatever the machine's speed.
        try await waitForCommand { $0.verb == "UID SEARCH" }
        superseded.cancel()
        await server.releaseReplies(to: "UID SEARCH")
        do {
            _ = try await finishing { try await superseded.value }
            XCTFail("a search cancelled mid-flight must not come back with results")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        // It read the answer to the command it had on the wire and sent
        // nothing after it. It used to drop that answer, which cost the
        // connection, and before that it carried on into Spam and All Mail
        // and opened a new connection for each.
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH"])
        XCTAssertEqual(server.log.last?.selected, Server.trash)
        XCTAssertEqual(server.log.map(\.status), ["OK", "OK"])

        // The search that replaced it runs straight away, on the same
        // connection, and is complete.
        let hits = try await finishing { try await self.searchEverywhere(repository, for: "garden") }
        XCTAssertTrue(hits.contains { $0.subject == "Binned: old garden" })
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// Cancelled while the NOOP that asks for the open folder's news (B-045)
    /// was on its way back, a minute after the folder was listed. It reads
    /// the NOOP's answer and sends nothing after it: the SEARCH, Gmail's
    /// slow step, would only hold up the search that replaced it.
    func testASearchCancelledAsItsNOOPComesBackSendsNoSearch() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)
        clock.advance(by: 60)
        server.holdReplies(to: "NOOP")
        server.clearLog()

        let superseded = Task {
            try await repository.search(in: "inbox", query: "garden", scope: .currentMailbox,
                                        beforeUID: nil, limit: 20)
        }
        try await waitForCommand { $0.verb == "NOOP" }
        superseded.cancel()
        await server.releaseReplies(to: "NOOP")
        do {
            let page = try await finishing { try await superseded.value }
            XCTFail("a cancelled search handed back \(page.count) results")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(server.log.map(\.verb), ["NOOP"])
        XCTAssertEqual(server.log.map(\.status), ["OK"])

        let hits = try await finishing {
            try await repository.search(in: "inbox", query: "garden", scope: .currentMailbox,
                                        beforeUID: nil, limit: 20)
        }
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// Cancelled while the last command it needed was on its way back: the
    /// FETCH of its first page. The FETCH is read whole, and the search
    /// still throws rather than handing back a page for a query he has
    /// already typed past. The list drops a superseded search's results only
    /// once the replacement's debounce has run, so a page returned in that
    /// gap would be drawn under the new query.
    func testASearchCancelledAsItsLastFetchComesBackStillEndsCancelled() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)
        server.clearLog()
        server.holdReplies(to: "UID FETCH")

        let superseded = Task {
            try await repository.search(in: "inbox", query: "garden", scope: .currentMailbox,
                                        beforeUID: nil, limit: 20)
        }
        try await waitForCommand { $0.verb == "UID FETCH" }
        superseded.cancel()
        await server.releaseReplies(to: "UID FETCH")
        do {
            let page = try await finishing { try await superseded.value }
            XCTFail("a cancelled search handed back \(page.count) results")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(server.log.map(\.verb), ["UID SEARCH", "UID FETCH"])
        XCTAssertEqual(server.log.map(\.status), ["OK", "OK"])

        let hits = try await finishing {
            try await repository.search(in: "inbox", query: "garden", scope: .currentMailbox,
                                        beforeUID: nil, limit: 20)
        }
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// Cancelled while its Trash was being refused: a folder deleted in
    /// another client, and a keystroke landing as the NO came back. The
    /// search is reported as cancelled, not as the refusal. A refused Trash
    /// on its own is swallowed so the rest of the search survives; in a
    /// cancelled search it used to come out as "Could not search" instead.
    func testASearchCancelledAsItsTrashIsRefusedEndsCancelledAndSendsNothingMore() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        server.refusedMailboxes = [Server.trash]
        server.holdReplies(to: "SELECT")
        server.clearLog()

        let superseded = Task { try await self.searchEverywhere(repository, for: "garden") }
        try await waitForCommand { $0.command == "SELECT \"[Gmail]/Trash\"" }
        superseded.cancel()
        await server.releaseReplies(to: "SELECT")
        do {
            _ = try await finishing { try await superseded.value }
            XCTFail("a cancelled search came back with results")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(server.log.map(\.command), ["SELECT \"[Gmail]/Trash\""])
        XCTAssertEqual(server.log.map(\.status), ["NO"])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// Cancelled once its Trash was open, before the Trash SEARCH, Gmail's
    /// slow step, was sent. Nothing more goes: the SEARCH would only hold up
    /// the search that replaced it.
    func testASearchCancelledAsItsTrashOpensSendsNoSearchThere() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        server.holdReplies(to: "SELECT")
        server.clearLog()

        let superseded = Task { try await self.searchEverywhere(repository, for: "garden") }
        try await waitForCommand { $0.command == "SELECT \"[Gmail]/Trash\"" }
        superseded.cancel()
        await server.releaseReplies(to: "SELECT")
        do {
            _ = try await finishing { try await superseded.value }
            XCTFail("a cancelled search came back with results")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(server.log.map(\.command), ["SELECT \"[Gmail]/Trash\""])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// Cancelled while its Trash summaries were on their way back. Spam is
    /// not opened after them.
    func testASearchCancelledDuringItsBinnedSummariesGoesNoFurther() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        server.holdReplies(to: "UID FETCH")
        server.clearLog()

        let superseded = Task { try await self.searchEverywhere(repository, for: "garden") }
        try await waitForCommand { $0.verb == "UID FETCH" }
        superseded.cancel()
        await server.releaseReplies(to: "UID FETCH")
        do {
            _ = try await finishing { try await superseded.value }
            XCTFail("a cancelled search came back with results")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(server.log.last?.selected, Server.trash)
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// Cancelled, and then the connection dies under the Trash SEARCH it
    /// had on the wire. It is reported as cancelled, not as the lost
    /// connection, and nothing reconnects for it.
    func testASearchCancelledAsItsConnectionDiesEndsCancelled() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        server.holdReplies(to: "UID SEARCH")
        server.clearLog()

        let superseded = Task { try await self.searchEverywhere(repository, for: "garden") }
        try await waitForCommand { $0.verb == "UID SEARCH" }
        superseded.cancel()
        await server.resetConnections()
        do {
            _ = try await finishing { try await superseded.value }
            XCTFail("a cancelled search came back with results")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        await server.releaseReplies(to: "UID SEARCH")
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH"])
        XCTAssertEqual(server.connectionsOpened, 1)

        let hits = try await finishing { try await self.searchEverywhere(repository, for: "garden") }
        XCTAssertTrue(hits.contains { $0.subject == "Binned: old garden" })
        XCTAssertEqual(server.connectionsOpened, 2)
    }

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

    /// Waits, a millisecond at a time and never for more than a second,
    /// until the server has received a command matching `matches`, looking
    /// only at what arrived after the first `since` entries of the log.
    private func waitForCommand(since: Int = 0,
                                file: StaticString = #filePath, line: UInt = #line,
                                _ matches: (Server.LogEntry) -> Bool) async throws {
        for _ in 0..<1_000 {
            if server.log.dropFirst(since).contains(where: matches) { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("the command never reached the server", file: file, line: line)
    }

    // MARK: - Typing a search

    /// "photo" typed a key a second, the way he types, with the list's
    /// debounce in front of every search and each search cancelled by the
    /// next key, as the list's search field does it.
    ///
    /// Replies take Gmail's times over a 50 ms round trip, at a fiftieth of
    /// the scale: a round trip is 1 ms, a text SEARCH 7 ms, a FETCH of
    /// summaries 2 ms, and the 350 ms debounce 7 ms. At a key a second an
    /// All Mailboxes search, 1.7 s on Gmail, is still on the wire when the
    /// next key lands. Where it has got to depends on the timing, so here
    /// each key lands on a named command, a different mailbox each time,
    /// rather than on a timer the scheduler could stretch.
    ///
    /// While the third search is in All Mail he taps a letter there, which
    /// opens it and marks it read.
    ///
    /// What used to happen: every cancelled search tore the connection
    /// down, each search after it reconnected, a false "Could not search"
    /// was drawn between keys, and the letter's read mark failed.
    func testTypingASearchAKeyASecondKeepsOneConnectionAndOnlyTheLastSearchAnswers() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        server.defaultDelay = .milliseconds(1)
        server.delays = ["UID SEARCH": .milliseconds(7), "UID FETCH": .milliseconds(2)]
        server.clearLog()

        let outcomes = SearchOutcomes()
        var debounce: Task<Void, Never>?
        func key(_ text: String) {
            debounce?.cancel()
            debounce = Task {
                try? await Task.sleep(for: .milliseconds(7))
                guard !Task.isCancelled else { return }
                do {
                    outcomes.record(text, .success(try await self.searchEverywhere(repository, for: text)))
                } catch {
                    outcomes.record(text, .failure(error))
                }
            }
        }

        // Each key but the last lands while the search before it has a
        // SEARCH in this mailbox on the wire.
        let landsDuring = [Server.trash, Server.spam, Server.allMail, Server.trash]
        let word = Array("photo")
        var tapped: Task<(Message, Void), Error>?
        let letterUID = try XCTUnwrap(server.uids(in: Server.allMail).last)
        let letterID = id(letterUID, in: Server.allMail)

        for (index, mailbox) in landsDuring.enumerated() {
            let mark = server.log.count
            key(String(word[...index]))
            try await waitForCommand(since: mark) { $0.verb == "UID SEARCH" && $0.selected == mailbox }
            if mailbox == Server.allMail {
                tapped = Task {
                    async let opened = repository.loadMessage(id: letterID, mailboxID: Server.allMail)
                    async let marked: Void = repository.setRead(true, id: letterID,
                                                                mailboxID: Server.allMail)
                    return try await (opened, marked)
                }
            }
        }
        key(String(word))
        let last = try XCTUnwrap(debounce)
        try await finishing { await last.value }

        // Every search but the last was cancelled, and said so.
        let results = outcomes.all
        XCTAssertEqual(results.map(\.query), ["p", "ph", "pho", "phot", "photo"])
        for result in results.dropLast() {
            switch result.outcome {
            case .success(let hits):
                XCTFail("\(result.query): a superseded search returned \(hits.count) results")
            case .failure(let error):
                XCTAssertTrue(error is CancellationError, "\(result.query): \(error)")
            }
        }

        // The last one found what a search nobody interrupted finds.
        let reference = ScriptedIMAPServer()
        let fresh = IMAPMailRepository(account: reference.account, password: reference.password,
                                       transport: reference.transportFactory, recipients: book)
        _ = try await fresh.listMailboxes()
        let expected = try await searchEverywhere(fresh, for: "photo")
        XCTAssertTrue(expected.contains { $0.mailboxID == Server.trash })
        guard case .success(let hits) = results.last?.outcome else {
            return XCTFail("the last search failed: \(String(describing: results.last))")
        }
        XCTAssertEqual(hits.map(\.id), expected.map(\.id))

        // The letter he tapped opened, and its read mark landed.
        let tap = try XCTUnwrap(tapped)
        let (message, _) = try await finishing { try await tap.value }
        XCTAssertEqual(message.subject, server.letter(uid: letterUID, in: Server.allMail)?.subject)
        XCTAssertTrue(server.flags(uid: letterUID, in: Server.allMail).contains("\\Seen"))
        let letterCommands = server.log.filter {
            $0.command == "UID FETCH \(letterUID) (UID BODY.PEEK[])"
                || $0.command == "UID STORE \(letterUID) +FLAGS.SILENT (\\Seen)"
        }
        // Opening and marking go out together and either may reach the gate
        // first; both ran in the mailbox the letter is in.
        XCTAssertEqual(letterCommands.map(\.verb).sorted(), ["UID FETCH", "UID STORE"])
        XCTAssertEqual(letterCommands.map(\.selected), [Server.allMail, Server.allMail])

        // One connection throughout, nothing lost into a dead one, every
        // command answered OK, and no two ever in flight at once (tearDown).
        // Each superseded search stopped at the SEARCH it had on the wire;
        // only the last got as far as All Mail.
        XCTAssertEqual(server.connectionsOpened, 1)
        XCTAssertEqual(server.lostWrites, [])
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        XCTAssertEqual(server.log.filter { $0.verb == "UID SEARCH" }.map(\.selected),
                       [Server.trash,
                        Server.trash, Server.spam,
                        Server.trash, Server.spam, Server.allMail,
                        Server.trash,
                        Server.trash, Server.spam, Server.allMail])
    }

    // MARK: - Previews for results from several mailboxes

    func testPreviewsForHitsFromSeveralMailboxesAllArriveThroughTheListsPreviewPass() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        let hits = try await searchEverywhere(repository, for: "garden")
        let groups = PreviewPass.groups(for: hits)
        XCTAssertEqual(Set(groups.map(\.mailboxID)), [Server.allMail, Server.trash, Server.spam])
        server.clearLog()

        // The pass the list runs, against the real repository.
        var previews: [String: String] = [:]
        await PreviewPass.run(groups,
                              fetch: { try await repository.previews(for: $0, in: $1) },
                              isCurrent: { true },
                              apply: { previews.merge($0) { a, _ in a } })

        // One mailbox's FETCHes after another's, in the order the groups
        // are drawn, each run with its own mailbox selected.
        let fetches = server.log.filter { $0.verb == "UID FETCH" }
        XCTAssertTrue(fetches.allSatisfy { $0.status == "OK" }, "\(fetches)")
        var ranIn: [String?] = []
        for entry in fetches where ranIn.last != entry.selected { ranIn.append(entry.selected) }
        XCTAssertEqual(ranIn, groups.map(\.mailboxID))
        for hit in hits {
            XCTAssertNotNil(previews[hit.id]?.range(of: "garden", options: .caseInsensitive),
                            "\(hit.mailboxID): \(hit.subject)")
        }
    }

    /// A server that accepts the connection and never says a word. The
    /// greeting's read is cut off at its deadline, with no reset needed to
    /// end it, and the call fails. It used to hang until the socket itself
    /// died.
    func testASilentServerIsCutOffAtTheReadDeadline() async throws {
        server.timeout = .milliseconds(20)
        server.isSilent = true
        let repository = makeRepository()

        let started = ContinuousClock.now
        do {
            _ = try await finishing(within: 1) { try await repository.listMailboxes() }
            XCTFail("a server that never answers cannot produce a folder list")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - started, .milliseconds(20))
        // The greeting never came, so nothing got as far as a command. And
        // that connection was never up, so the read retry left it there.
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// The same silence arriving mid-session, as after a Wi-Fi roam: the
    /// letter's FETCH is cut off at its deadline, the read retry's new
    /// connection is cut off at its greeting, and once the server answers
    /// again the next tap connects cleanly and gets its own letter.
    func testAServerThatGoesQuietMidSessionIsCutOffAndTheNextCallReconnects() async throws {
        server.timeout = .milliseconds(20)
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)

        server.isSilent = true
        do {
            _ = try await finishing(within: 1) {
                try await repository.loadMessage(id: rows[0].id, mailboxID: "inbox")
            }
            XCTFail("a server that stopped answering cannot have sent a letter")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        XCTAssertEqual(server.connectionsOpened, 2)
        XCTAssertEqual(server.log.last?.verb, "UID FETCH")
        XCTAssertNil(server.log.last?.status)

        server.isSilent = false
        let message = try await finishing {
            try await repository.loadMessage(id: rows[1].id, mailboxID: "inbox")
        }
        XCTAssertEqual(message.subject, rows[1].subject)
        XCTAssertEqual(server.connectionsOpened, 3)
        XCTAssertEqual(server.log.filter { $0.connection == 3 }.map(\.verb),
                       ["LOGIN", "SELECT", "UID FETCH"])
    }

    func testUIDPLUSIsLearnedWhereverLoginPutsTheCapabilities() async throws {
        for placement in [Server.LoginCapabilities.inTaggedOK, .untagged, .omitted] {
            server = ScriptedIMAPServer()
            server.loginCapabilities = placement
            let repository = makeRepository()
            let draft = try XCTUnwrap(server.uids(in: Server.drafts).first)

            try await repository.deleteDraft(id(draft, in: Server.drafts))

            // UIDPLUS is only in the post-login list, and without it the
            // client would fall back to a plain EXPUNGE of the whole folder.
            XCTAssertTrue(server.log.contains { $0.command == "UID EXPUNGE \(draft)" }, "\(placement)")
            XCTAssertFalse(server.log.contains { $0.verb == "EXPUNGE" }, "\(placement)")
            XCTAssertFalse(server.uids(in: Server.drafts).contains(draft), "\(placement)")
        }
    }

    func testADraftGoesUpAsALiteralComesBackAndASecondSaveReplacesIt() async throws {
        let repository = makeRepository()
        var draft = Draft(to: ["carlo@example.org"], subject: "Plans for Sunday",
                          body: "Half a thought.")

        let first = try await repository.saveDraft(draft)
        let firstID = try XCTUnwrap(first, "APPENDUID should have named the new copy")
        let reopened = try await repository.loadDraft(id: firstID, mailboxID: Server.drafts)
        XCTAssertEqual(reopened.subject, "Plans for Sunday")
        XCTAssertEqual(reopened.to, ["carlo@example.org"])
        XCTAssertTrue(reopened.body.contains("Half a thought."))

        draft = reopened
        draft.body = "A whole thought."
        let second = try await repository.saveDraft(draft)
        XCTAssertNotEqual(second, first)

        // Replaced, not accumulated: one copy on the server, the new one.
        let copies = server.uids(in: Server.drafts).filter {
            server.letter(uid: $0, in: Server.drafts)?.subject == "Plans for Sunday"
        }
        XCTAssertEqual(copies.map { id($0, in: Server.drafts) }, [second].compactMap { $0 })
        XCTAssertEqual(server.log.filter { $0.verb == "APPEND" }.map(\.status), ["OK", "OK"])
    }

    func testRepliesThatTakeTimeStillArriveWholeAndInOrder() async throws {
        server.defaultDelay = .milliseconds(1)
        server.delays = ["UID FETCH": .milliseconds(3)]
        let repository = makeRepository()

        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)
        let newest = server.uids(in: Server.inbox).suffix(20).reversed()
        XCTAssertEqual(rows.map(\.id), newest.map { id($0, in: Server.inbox) })

        // Tapping a row fires the fetch and the read mark together; the
        // client's exchange gate has to keep the two replies apart. Without
        // it the server records the overlap (see tearDown) and the second
        // read fails at once, so a broken gate turns this red rather than
        // hanging the suite.
        let tapped = rows[1].id
        let message = try await finishing {
            async let opened = repository.loadMessage(id: tapped, mailboxID: "inbox")
            async let marked: Void = repository.setRead(true, id: tapped, mailboxID: "inbox")
            try await marked
            return try await opened
        }
        XCTAssertEqual(message.subject, rows[1].subject)
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    // MARK: - Writes are never sent twice

    func testAWriteIntoADeadSocketGoesOutOnceAndIsNotRepeatedOnANewConnection() async throws {
        let writes: [(verb: String, run: (IMAPMailRepository, MessageSummary) async throws -> Void)] = [
            ("UID MOVE", { try await $0.delete($1.id, from: "inbox") }),
            ("UID STORE", { try await $0.setRead(true, id: $1.id, mailboxID: "inbox") }),
            ("UID STORE", { try await $0.setFlagged(true, id: $1.id, mailboxID: "inbox") }),
            ("UID MOVE", { try await $0.move($1.id, from: "inbox", to: Server.sent) }),
        ]
        for (verb, write) in writes {
            server = ScriptedIMAPServer()
            let repository = makeRepository()
            let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
            let inboxBefore = server.uids(in: Server.inbox)

            await server.resetConnections()
            do {
                try await write(repository, rows[0])
                XCTFail("\(verb): a write into a dead socket cannot have succeeded")
            } catch {
                XCTAssertEqual(error as? MailError, .cannotConnect, verb)
            }

            // It went out once, into the dead socket, and was NOT carried to
            // a new connection. It may have reached the server before the
            // socket died, and doing it twice is not the same as doing it
            // once. Within a minute and a half of the last command there is
            // no probe first either, which is B-024's trade.
            XCTAssertEqual(server.lostWrites.map(\.verb), [verb], verb)
            XCTAssertEqual(server.connectionsOpened, 1, verb)
            XCTAssertEqual(server.uids(in: Server.inbox), inboxBefore, verb)
            XCTAssertEqual(server.violations, [], verb)
        }
    }

    func testAWriteAfterAQuietSpellProbesTheConnectionFirstAndIsStillSentOnce() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let newest = try XCTUnwrap(server.uids(in: Server.inbox).last)
        XCTAssertFalse(rows[0].isRead)

        // Past the ninety seconds, on a connection that is still alive: one
        // NOOP, then the write.
        clock.advance(by: 91)
        server.clearLog()
        try await repository.setRead(true, id: rows[0].id, mailboxID: "inbox")
        XCTAssertEqual(server.log.map(\.verb), ["NOOP", "UID STORE"])

        // And on one that died while he was away. The NOOP finds it dead and,
        // being safe to repeat, is repeated on a new connection; the write is
        // sent once, there, after the SELECT the new connection needs.
        clock.advance(by: 91)
        await server.resetConnections()
        server.clearLog()
        try await repository.setRead(false, id: rows[0].id, mailboxID: "inbox")
        XCTAssertEqual(server.lostWrites.map(\.command), ["NOOP"])
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN", "NOOP", "SELECT", "UID STORE"])
        XCTAssertEqual(server.log.map(\.connection), [2, 2, 2, 2])
        XCTAssertFalse(server.flags(uid: newest, in: Server.inbox).contains("\\Seen"))
    }

    func testAWriteSoonAfterTheLastCommandIsNotProbed() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)

        clock.advance(by: 89)
        server.clearLog()
        try await repository.setFlagged(true, id: rows[0].id, mailboxID: "inbox")
        XCTAssertEqual(server.log.map(\.verb), ["UID STORE"])
    }

    /// A flag set after a quiet spell, with a search on the wire and
    /// previews and the folder sweep queued behind it. The probe goes as
    /// soon as the search's answer is in, and the write after it, ahead of
    /// the sweep. Probe and write are two holds of the connection, so the
    /// one queued exchange at the head of the line when the probe ends, the
    /// previews' FETCH here, goes between them; nothing else does.
    func testAProbedWriteGoesAheadOfWorkQueuedBeforeIt() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        server.clearLog()
        server.holdReplies(to: "UID SEARCH")

        let search = Task {
            try await repository.search(in: "inbox", query: "garden", scope: .currentMailbox,
                                        beforeUID: nil, limit: 10)
        }
        try await waitForCommand { $0.verb == "UID SEARCH" }
        let previews = Task { try await repository.previews(for: rows.map(\.id), in: "inbox") }
        try await until { await repository.waitingForExchange == 1 }
        let sweep = Task { try await repository.listMailboxes() }
        try await until { await repository.waitingForExchange == 2 }

        clock.advance(by: 91)
        let flag = Task { try await repository.setFlagged(true, id: rows[0].id, mailboxID: "inbox") }
        try await until { await repository.waitingForExchange == 3 }
        server.holdReplies(to: "UID FETCH")
        await server.releaseReplies(to: "UID SEARCH")
        // The probe has gone and the previews have the connection; the
        // write, the sweep and the search's page are waiting.
        try await waitForCommand { $0.verb == "UID FETCH" }
        try await until { await repository.waitingForExchange == 3 }
        await server.releaseReplies(to: "UID FETCH")

        try await finishing { try await flag.value }
        _ = try await finishing { try await search.value }
        _ = try await finishing { try await previews.value }
        _ = try await finishing { try await sweep.value }

        XCTAssertEqual(Array(server.log.map(\.verb).prefix(5)),
                       ["UID SEARCH", "NOOP", "UID FETCH", "UID STORE", "LIST"])
        XCTAssertTrue(server.log[2].command.contains("BODY.PEEK[1]<0."), "\(server.log[2])")
        XCTAssertTrue(server.flags(uid: try XCTUnwrap(UInt32(rows[0].id.split(separator: "/").last ?? "")),
                                   in: Server.inbox).contains("\\Flagged"))
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    // MARK: - A refused password is sent once

    func testARefusedPasswordIsSentOnceAndNotRetried() async throws {
        let reads: [(label: String, run: (IMAPMailRepository) async throws -> Void)] = [
            ("folders", { _ = try await $0.listMailboxes() }),
            ("list", { _ = try await $0.listMessages(in: "inbox", beforeUID: nil, limit: 20) }),
            ("date jump", { _ = try await $0.messages(around: Server.newestDate, in: "inbox",
                                                      limit: 20) }),
            ("search here", { _ = try await $0.search(in: "inbox", query: "garden",
                                                      scope: .currentMailbox,
                                                      beforeUID: nil, limit: 20) }),
            ("search everywhere", { _ = try await $0.search(in: "inbox", query: "garden",
                                                            scope: .allMailboxes,
                                                            beforeUID: nil, limit: 20) }),
        ]
        for (label, read) in reads {
            server = ScriptedIMAPServer()
            let repository = makeRepository(password: "not-the-password")
            do {
                try await read(repository)
                XCTFail("\(label): nothing can be read with the wrong password")
            } catch {
                XCTAssertEqual(error as? MailError, .passwordNeedsUpdating, label)
            }
            // One failed login, not two. The read retry used to send the
            // same wrong password again, and with a revoked app password
            // every search he typed cost two, which is how an account gets
            // throttled.
            XCTAssertEqual(server.log.map(\.verb), ["LOGIN"], label)
            XCTAssertEqual(server.connectionsOpened, 1, label)
        }
    }

    /// A second screen wants the connection while the first is still
    /// making it, with a password Gmail refuses: once during the TLS
    /// handshake, when the client does not yet call itself connected and
    /// the second call asks to connect as well, and once while LOGIN is on
    /// its way, when it does and the second call queues its command
    /// instead. Either way the refusal is both calls' answer, and the
    /// password goes once. The second call used to send it again, on a
    /// connection of its own.
    func testAPasswordRefusedWhileAnotherCallWaitsForTheConnectionIsStillSentOnce() async throws {
        let windows: [(label: String, hold: (ScriptedIMAPServer) -> Void,
                       underway: (ScriptedIMAPServer) -> Bool,
                       release: (ScriptedIMAPServer) async -> Void)] = [
            ("handshake", { $0.holdHandshakes() }, { _ in true }, { await $0.releaseHandshakes() }),
            ("login", { $0.holdReplies(to: "LOGIN") }, { $0.log.contains { $0.verb == "LOGIN" } },
             { await $0.releaseReplies(to: "LOGIN") }),
        ]
        for (label, hold, underway, release) in windows {
            server = ScriptedIMAPServer()
            hold(server)
            let repository = makeRepository(password: "not-the-password")
            let first = Task { _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20) }
            try await until { underway(self.server) }
            let second = Task { _ = try await repository.listMailboxes() }
            try await until { await repository.waitingForExchange == 1 }
            await release(server)

            for (call, task) in [("first", first), ("second", second)] {
                do {
                    try await finishing { try await task.value }
                    XCTFail("\(label), \(call): nothing can be read with the wrong password")
                } catch {
                    XCTAssertEqual(error as? MailError, .passwordNeedsUpdating, "\(label), \(call)")
                }
            }
            XCTAssertEqual(server.log.map(\.verb), ["LOGIN"], label)
            XCTAssertEqual(server.connectionsOpened, 1, label)
        }
    }

    /// The same two windows with a connect that fails some other way: a
    /// server that accepts the connection and never greets, and a socket
    /// that dies while LOGIN is on its way. The failure is both calls'
    /// answer, and there is one connection. In the LOGIN window the second
    /// call has found the client calling itself connected and queued its
    /// command; its read retry used to take the failure for a dropped
    /// socket and connect again, which against a server that says nothing
    /// is a second connect timeout.
    func testAConnectThatFailsWhileAnotherCallWaitsForItIsMadeOnce() async throws {
        let windows: [(label: String, hold: (ScriptedIMAPServer) -> Void,
                       underway: (ScriptedIMAPServer) -> Bool,
                       fail: (ScriptedIMAPServer) async -> Void, commands: [String])] = [
            ("handshake", { $0.holdHandshakes() }, { _ in true },
             { server in
                 server.isSilent = true
                 server.timeout = .milliseconds(20)
                 await server.releaseHandshakes()
             }, []),
            ("login", { $0.holdReplies(to: "LOGIN") }, { $0.log.contains { $0.verb == "LOGIN" } },
             { server in
                 await server.resetConnections()
                 await server.releaseReplies(to: "LOGIN")
             }, ["LOGIN"]),
        ]
        for (label, hold, underway, fail, commands) in windows {
            server = ScriptedIMAPServer()
            hold(server)
            let repository = makeRepository()
            let first = Task { _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20) }
            try await until { underway(self.server) }
            let second = Task { _ = try await repository.listMailboxes() }
            try await until { await repository.waitingForExchange == 1 }
            await fail(server)

            for (call, task) in [("first", first), ("second", second)] {
                do {
                    try await finishing { try await task.value }
                    XCTFail("\(label), \(call): read without a connection")
                } catch {
                    XCTAssertEqual(error as? MailError, .cannotConnect, "\(label), \(call)")
                }
            }
            XCTAssertEqual(server.log.map(\.verb), commands, label)
            XCTAssertEqual(server.connectionsOpened, 1, label)
        }
    }

    // MARK: - Searches paged across a dead socket

    /// Every page of an "All Mailboxes" search for "garden", three at a time,
    /// on a fresh server, killing the connection just before page `k` (from
    /// zero) is asked for. Three at a time interleaves Trash and Spam hits
    /// with All Mail's across many page boundaries.
    private func pagesOfTheGardenSearch(resettingBefore k: Int?) async throws -> [[String]] {
        server = ScriptedIMAPServer()
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        var pages: [[String]] = []
        var cursor: String?
        while pages.count < 40 {
            if pages.count == k { await server.resetConnections() }
            let page = try await repository.search(in: "inbox", query: "garden", scope: .allMailboxes,
                                                   beforeUID: cursor, limit: 3)
            guard !page.isEmpty else { break }
            pages.append(page.map(\.id))
            cursor = page.last?.id
        }
        return pages
    }

    func testASearchPagedAcrossADeadSocketNeitherSkipsNorRepeatsAHit() async throws {
        let clean = try await pagesOfTheGardenSearch(resettingBefore: nil)
        let all = clean.flatMap { $0 }
        XCTAssertGreaterThan(clean.count, 8)
        XCTAssertEqual(Set(all).count, all.count, "a hit came out twice")
        XCTAssertTrue(clean.dropFirst().contains { page in
            page.contains { $0.hasPrefix("\(server.uidValidity(of: Server.trash))/") }
        }, "no Trash hit lands past the first page, so no boundary is tested")

        for k in 1..<8 {
            let faulted = try await pagesOfTheGardenSearch(resettingBefore: k)
            XCTAssertEqual(faulted, clean, "connection reset before page \(k + 1)")
            // The page that found the socket dead ran again on one new
            // connection, and nothing about the merge was carried across
            // half-done.
            XCTAssertEqual(server.connectionsOpened, 2, "reset before page \(k + 1)")
            XCTAssertEqual(server.violations, [], "reset before page \(k + 1)")
        }
    }

    /// Some pages of that search are merged entirely from what earlier
    /// pages fetched and send nothing, so no command on the wire is there to
    /// notice a cancel. A caller cancelled by then still gets no page, and
    /// the search does not move on without him: asked again, the page is the
    /// one an uninterrupted run hands out.
    func testACancelledCallerGetsNoPageEvenWhenThePageNeedsNoCommand() async throws {
        let clean = try await pagesOfTheGardenSearch(resettingBefore: nil)

        // Which page needs no command, found on one run and cancelled on
        // the next.
        var quiet: Int?
        server = ScriptedIMAPServer()
        var repository = makeRepository()
        _ = try await repository.listMailboxes()
        var cursor: String?
        for (k, expected) in clean.enumerated() {
            let before = server.log.count
            let page = try await repository.search(in: "inbox", query: "garden", scope: .allMailboxes,
                                                   beforeUID: cursor, limit: 3)
            XCTAssertEqual(page.map(\.id), expected)
            if k > 0, server.log.count == before {
                quiet = k
                break
            }
            cursor = page.last?.id
        }
        let k = try XCTUnwrap(quiet, "every page sent a command, so the case is never reached")

        server = ScriptedIMAPServer()
        repository = makeRepository()
        _ = try await repository.listMailboxes()
        cursor = nil
        for expected in clean.prefix(k) {
            let page = try await repository.search(in: "inbox", query: "garden", scope: .allMailboxes,
                                                   beforeUID: cursor, limit: 3)
            XCTAssertEqual(page.map(\.id), expected)
            cursor = page.last?.id
        }
        let before = server.log.count
        let from = cursor
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await repository.search(in: "inbox", query: "garden", scope: .allMailboxes,
                                               beforeUID: from, limit: 3)
        }
        do {
            let page = try await finishing { try await cancelled.value }
            XCTFail("a cancelled caller was handed page \(k + 1): \(page.map(\.id))")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(server.log.count, before)

        let again = try await repository.search(in: "inbox", query: "garden", scope: .allMailboxes,
                                                beforeUID: from, limit: 3)
        XCTAssertEqual(again.map(\.id), clean[k])
        if k + 1 < clean.count {
            let next = try await repository.search(in: "inbox", query: "garden", scope: .allMailboxes,
                                                   beforeUID: again.last?.id, limit: 3)
            XCTAssertEqual(next.map(\.id), clean[k + 1])
        }
    }

    // MARK: - A mailbox renumbered while the connection was down

    func testAListingRenumberedBehindADeadSocketIsRefusedRatherThanCutFromOldUIDs() async throws {
        let repository = makeRepository()
        let first = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)
        let cursor = try XCTUnwrap(first.last?.id)

        // Renumbered so that the old UIDs now name OTHER letters.
        await server.resetConnections()
        server.renumber(Server.inbox, validity: 700_001, firstUID: 990)
        do {
            let page = try await repository.listMessages(in: "inbox", beforeUID: cursor, limit: 20)
            XCTFail("paged from a cursor in the old numbering: \(page.map(\.subject))")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }

        // What the list's next reload does: from the top, in the new
        // numbering, and the same letters.
        let fresh = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)
        XCTAssertEqual(fresh.map(\.subject), first.map(\.subject))
        XCTAssertTrue(fresh.allSatisfy { $0.id.hasPrefix("700001/") }, "\(fresh.map(\.id))")
        let next = try await repository.listMessages(in: "inbox", beforeUID: fresh.last?.id, limit: 20)
        XCTAssertEqual(next.count, 20)
    }

    func testASearchRenumberedBehindADeadSocketIsRefusedRatherThanPagedFromOldUIDs() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        let first = try await repository.search(in: "inbox", query: "garden", scope: .allMailboxes,
                                                beforeUID: nil, limit: 7)
        let cursor = try XCTUnwrap(first.last?.id)

        await server.resetConnections()
        server.renumber(Server.allMail, validity: 700_002, firstUID: 4_990)
        do {
            let page = try await repository.search(in: "inbox", query: "garden",
                                                   scope: .allMailboxes, beforeUID: cursor, limit: 7)
            XCTFail("paged a search from UIDs in the old numbering: \(page.map(\.subject))")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }

        // A new search starts clean, and finds the same letters.
        let again = try await repository.search(in: "inbox", query: "garden", scope: .allMailboxes,
                                                beforeUID: nil, limit: 7)
        XCTAssertEqual(again.map(\.subject), first.map(\.subject))
        XCTAssertTrue(again.filter { $0.mailboxID == Server.allMail }
                        .allSatisfy { $0.id.hasPrefix("700002/") })
    }

    /// Loading upward after a jump, the Inbox renumbered behind a dead
    /// socket. The fetch's own SELECT, on the new connection, is what
    /// finds it, and there is nothing more to load above him: an empty
    /// page, which is what stops the list asking, not an error it would
    /// meet again at every scroll to the top.
    func testLoadingUpwardIntoAFolderRenumberedBehindADeadSocketFindsNothingMore() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let before = try await repository.listMessages(in: "inbox", afterUID: rows[30].id, limit: 10)
        XCTAssertEqual(before.map(\.id), rows[20..<30].map(\.id))

        await server.resetConnections()
        server.renumber(Server.inbox, validity: 700_001, firstUID: 990)
        server.clearLog()
        let after = try await repository.listMessages(in: "inbox", afterUID: rows[30].id, limit: 10)

        XCTAssertEqual(after.map(\.id), [])
        XCTAssertEqual(server.lostWrites.map(\.verb), ["UID FETCH"])
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN", "SELECT"])
        XCTAssertEqual(server.connectionsOpened, 2)
    }

    /// Rows drawn before the Inbox was renumbered, asked about once
    /// something else has already seen the new numbering, with another
    /// folder selected by then. The page above them is empty and the
    /// previews are simply missing, neither costing a command; the page
    /// below is refused rather than cut from the new numbers with an old
    /// cursor, which drew other letters.
    func testRowsFromBeforeARenumberingThatHasBeenSeenAreNeitherPagedNorPreviewed() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)

        await server.resetConnections()
        server.renumber(Server.inbox, validity: 700_001, firstUID: 990)
        do {
            _ = try await repository.loadMessage(id: rows[0].id, mailboxID: "inbox")
            XCTFail("opened a letter by a UID from the old numbering")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        _ = try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 5)
        server.clearLog()

        let above = try await repository.listMessages(in: "inbox", afterUID: rows[30].id, limit: 10)
        XCTAssertEqual(above.map(\.id), [])
        XCTAssertEqual(server.log, [], "paging upward sent something")

        let previews = try await repository.previews(for: rows.prefix(10).map(\.id), in: "inbox")
        XCTAssertEqual(previews, [:])
        XCTAssertEqual(server.log, [], "previews sent something")

        do {
            let page = try await repository.listMessages(in: "inbox", beforeUID: rows.last?.id, limit: 20)
            XCTFail("paged from a cursor in the old numbering: \(page.map(\.subject))")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        XCTAssertFalse(server.log.contains { $0.verb == "UID FETCH" }, "\(server.log)")
        XCTAssertEqual(server.connectionsOpened, 2)
    }

    // MARK: - An attachment the letter does not have

    /// Refused on the letter's structure, before the part's bytes are
    /// asked for.
    func testAnAttachmentTheLetterHasNoPartForIsRefusedBeforeAnyBytesAreFetched() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)
        server.clearLog()

        do {
            _ = try await repository.fetchAttachmentData("9", of: rows[3].id, mailboxID: "inbox")
            XCTFail("fetched a part the letter does not have")
        } catch {
            XCTAssertEqual(error as? MailError, .attachmentFailed)
        }
        XCTAssertEqual(server.log.map(\.verb), ["UID FETCH"])
        XCTAssertFalse(server.log.contains { $0.command.contains("BODY.PEEK") }, "\(server.log)")
    }
}

/// What each search in a typing run came to, in the order they ended.
private final class SearchOutcomes: @unchecked Sendable {
    struct Entry {
        let query: String
        let outcome: Result<[MessageSummary], Error>
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    var all: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.sorted { $0.query.count < $1.query.count }
    }

    func record(_ query: String, _ outcome: Result<[MessageSummary], Error>) {
        lock.lock()
        entries.append(Entry(query: query, outcome: outcome))
        lock.unlock()
    }
}
