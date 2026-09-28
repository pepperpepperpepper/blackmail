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

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
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
        super.tearDown()
    }

    private func makeRepository(password: String? = nil,
                                now: @escaping @Sendable () -> Date = { Date() })
        -> IMAPMailRepository {
        IMAPMailRepository(account: server.account, password: password ?? server.password,
                           transport: server.transportFactory, recipients: book, now: now)
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

    func testAUIDCommandWithNoMailboxSelectedIsRefusedOnThatConnection() async throws {
        let client = IMAPClient(account: server.account, transport: server.transportFactory)
        try await client.connect(password: server.password)
        do {
            _ = try await client.searchAll()
            XCTFail("a UID SEARCH with nothing selected must not succeed")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        XCTAssertEqual(server.log.last, Server.LogEntry(connection: 1, selected: nil,
                                                        command: "UID SEARCH ALL", status: "BAD"))

        try await client.select(Server.inbox)
        let all = try await client.searchAll()
        XCTAssertEqual(all, server.uids(in: Server.inbox))

        // Selection belongs to the connection, not the server: a second one
        // starts with nothing selected, whatever the first has open.
        let other = IMAPClient(account: server.account, transport: server.transportFactory)
        try await other.connect(password: server.password)
        _ = try? await other.searchAll()
        XCTAssertEqual(server.log.last?.connection, 2)
        XCTAssertEqual(server.log.last?.status, "BAD")
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

        // The same through a preview pass that is refused, then the next
        // page of the Inbox, which walks the snapshot and sends only a FETCH.
        server.refusedMailboxes = [Server.trash]
        _ = try? await repository.previews(for: ["\(server.uidValidity(of: Server.trash))/80"],
                                           in: Server.trash)
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
        // Every reply takes a couple of milliseconds, as every reply on the
        // device takes at least a round trip. That is what decides the race
        // in `ReadBuffer.receiveChunk` for a read started after the cancel:
        // its deadline, cancelled with it, throws at once and the reply is
        // not there yet. With replies that took no time at all the race
        // would be a coin toss the device never plays.
        server.defaultDelay = .milliseconds(2)
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
            // What the list sees. Only its own cancellation check keeps
            // this from being drawn as "Could not search".
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        // It stopped where it was. It used to carry on into Spam and All
        // Mail and open a new connection for each, just to fail again.
        XCTAssertEqual(server.connectionsOpened, 1)
        XCTAssertEqual(server.log.filter { $0.verb == "UID SEARCH" }.map(\.selected), [Server.trash])

        // The search that replaced it reconnects once and is complete.
        server.defaultDelay = .zero
        server.delays = [:]
        let hits = try await searchEverywhere(repository, for: "garden")
        XCTAssertTrue(hits.contains { $0.subject == "Binned: old garden" })
        XCTAssertEqual(server.connectionsOpened, 2)
    }

    /// Waits, a millisecond at a time and never for more than a second,
    /// until the server has received a command matching `matches`.
    private func waitForCommand(file: StaticString = #filePath, line: UInt = #line,
                                _ matches: (Server.LogEntry) -> Bool) async throws {
        for _ in 0..<1_000 {
            if server.log.contains(where: matches) { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("the command never reached the server", file: file, line: line)
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

    /// What the device does today, not what it should: see
    /// `ReadBuffer.receiveChunk`. The deadline throws on time and then waits
    /// for a receive that a silent peer never answers, so the call hangs
    /// until the socket itself dies. When the deadline is made to end the
    /// read on its own, turn this round: the call should fail at about the
    /// deadline with no reset needed.
    func testASilentServerIsNotCutOffAtTheReadDeadlineYet() async throws {
        server.readTimeout = .milliseconds(2)
        server.isSilent = true
        let repository = makeRepository()

        let finished = Flag()
        let call = Task {
            defer { finished.set() }
            return try await repository.listMailboxes()
        }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(finished.isSet, "the read ended at its deadline, which it does not do yet")

        await server.resetConnections()
        do {
            _ = try await finishing { try await call.value }
            XCTFail("a server that never answers cannot produce a folder list")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        // The greeting never came, so nothing got as far as a command. And
        // that connection was never up, so the read retry left it there.
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(server.connectionsOpened, 1)
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
        let clock = TestClock()
        let repository = makeRepository(now: { clock.now() })
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
        let clock = TestClock()
        let repository = makeRepository(now: { clock.now() })
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)

        clock.advance(by: 89)
        server.clearLog()
        try await repository.setFlagged(true, id: rows[0].id, mailboxID: "inbox")
        XCTAssertEqual(server.log.map(\.verb), ["UID STORE"])
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
}

/// A clock a test moves by hand, so ninety seconds of quiet cost nothing.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_790_000_000)

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current += seconds
        lock.unlock()
    }
}
