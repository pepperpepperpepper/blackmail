import XCTest
@testable import Blackmail

/// Every UID command in the mailbox it was meant for, whatever else is
/// using the connection, and the letter he opens ahead of the work he did
/// not ask for. Over `ScriptedIMAPServer`, through the shipping repository
/// and client.
///
/// The defect these exist for is B-039: a SELECT and the command that
/// depended on it took the connection separately, so another screen's
/// SELECT could land between them and the command ran in the wrong mailbox,
/// where the same UID can name a different letter.
final class MailboxAtomicityTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "MailboxAtomicityTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    /// Never moved. What the repository sends can depend on how long ago it
    /// last asked about a folder (B-045), so on the wall clock a stalled
    /// host would add a NOOP to the exact traffic these tests pin.
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
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        server = nil
        book = nil
        clock = nil
        super.tearDown()
    }

    private func makeRepository(on server: ScriptedIMAPServer? = nil) -> IMAPMailRepository {
        let server = server ?? self.server!
        let clock = self.clock!
        return IMAPMailRepository(account: server.account, password: server.password,
                                  transport: server.transportFactory, recipients: book,
                                  now: { clock.now() }, shelf: keptShelf(for: server.account))
    }

    private static let mailboxes = [Server.inbox, Server.allMail, Server.drafts, Server.sent,
                                    Server.spam, Server.starred, Server.trash]

    /// A server whose mailboxes number their letters from the same UID up,
    /// as real ones do, so a UID command sent to the wrong mailbox finds a
    /// different letter rather than nothing. Numbered before anything
    /// connects, so nothing has an old number to hold on to.
    private func serverWithSharedUIDs() -> ScriptedIMAPServer {
        let server = ScriptedIMAPServer()
        for mailbox in [Server.allMail, Server.trash, Server.spam, Server.starred] {
            server.renumber(mailbox, validity: server.uidValidity(of: mailbox), firstUID: 1_000)
        }
        return server
    }

    /// Every letter the server holds, by mailbox and UID: its Message-ID
    /// and the flags a FETCH there would report.
    private func contents() -> [String: [UInt32: String]] {
        var out: [String: [UInt32: String]] = [:]
        for mailbox in Self.mailboxes {
            for uid in server.uids(in: mailbox) {
                guard let letter = server.letter(uid: uid, in: mailbox) else { continue }
                let flags = server.flags(uid: uid, in: mailbox).sorted().joined(separator: " ")
                out[mailbox, default: [:]][uid] = "\(letter.messageID) \(flags)"
            }
        }
        return out
    }

    /// `contents` without the letter whose Message-ID is `messageID`.
    private func contents(without messageID: String) -> [String: [UInt32: String]] {
        contents().mapValues { $0.filter { !$0.value.hasPrefix(messageID + " ") } }
    }

    /// The UIDs a UID command names, `1004:1008,1010` expanded, or nil for
    /// a command that names none, like SEARCH.
    private func uidsNamed(by entry: Server.LogEntry) -> [UInt32]? {
        guard ["UID FETCH", "UID STORE", "UID MOVE", "UID COPY"].contains(entry.verb) else { return nil }
        let words = entry.command.split(separator: " ")
        guard words.count > 2 else { return nil }
        var uids: [UInt32] = []
        for piece in words[2].split(separator: ",") {
            let bounds = piece.split(separator: ":").compactMap { UInt32($0) }
            guard let low = bounds.first else { return nil }
            let high = bounds.last ?? low
            uids += Array(low...max(low, high))
        }
        return uids
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

    private func searchEverywhere(_ repository: IMAPMailRepository, for query: String,
                                  limit: Int = 50) async throws -> [MessageSummary] {
        try await repository.search(in: "inbox", query: query, scope: .allMailboxes,
                                    beforeUID: nil, limit: limit)
    }

    // MARK: - Previews, a search and a letter, all at once

    /// The preview pass the list used to run: a task per mailbox, all at
    /// once, for the hits of an "All Mailboxes" search. With a new search
    /// typed and a letter opened in the Inbox at the same time.
    ///
    /// It used to leave most previews blank: each FETCH could run in the
    /// mailbox another task had just SELECTed, and there those UIDs name
    /// nothing. The mailboxes here number their letters apart, so a UID
    /// command's own UIDs say which mailbox it was meant for.
    func testPreviewsForSeveralMailboxesFetchedAtOnceEachRunInTheirOwnMailbox() async throws {
        // What a run with nothing else going on finds: the hits, their
        // previews one mailbox at a time, and the second search.
        let reference = ScriptedIMAPServer()
        let calm = makeRepository(on: reference)
        _ = try await calm.listMailboxes()
        let expectedHits = try await searchEverywhere(calm, for: "garden")
        var expectedPreviews: [String: String] = [:]
        for group in PreviewPass.groups(for: expectedHits) {
            expectedPreviews.merge(try await calm.previews(for: group.ids, in: group.mailboxID)) { a, _ in a }
        }
        let expectedDinner = try await searchEverywhere(calm, for: "dinner")
        XCTAssertEqual(Set(PreviewPass.groups(for: expectedHits).map(\.mailboxID)),
                       [Server.allMail, Server.trash, Server.spam])
        XCTAssertEqual(expectedPreviews.count, expectedHits.count)

        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        let inbox = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let hits = try await searchEverywhere(repository, for: "garden")
        XCTAssertEqual(hits.map(\.id), expectedHits.map(\.id))
        server.defaultDelay = .milliseconds(1)
        server.clearLog()

        let previewTasks = PreviewPass.groups(for: hits).map { group in
            Task { try await repository.previews(for: group.ids, in: group.mailboxID) }
        }
        let dinner = Task { try await self.searchEverywhere(repository, for: "dinner") }
        let letter = Task { try await repository.open(inbox[3]) }

        var previews: [String: String] = [:]
        for task in previewTasks {
            previews.merge(try await finishing { try await task.value }) { a, _ in a }
        }
        let dinnerHits = try await finishing { try await dinner.value }
        let message = try await finishing { try await letter.value }

        XCTAssertEqual(previews, expectedPreviews)
        XCTAssertEqual(dinnerHits.map(\.id), expectedDinner.map(\.id))
        XCTAssertEqual(message.subject, inbox[3].subject)

        // Every UID command named UIDs of the mailbox selected when it ran,
        // and was answered OK. They did overlap: more than one mailbox was
        // selected in turn while the previews were being fetched.
        let uidCommands = server.log.filter(\.isUIDCommand)
        for entry in uidCommands {
            XCTAssertEqual(entry.status, "OK", "\(entry)")
            guard let named = uidsNamed(by: entry), let selected = entry.selected else { continue }
            XCTAssertTrue(Set(named).isSubset(of: server.uids(in: selected)), "\(entry)")
        }
        XCTAssertGreaterThan(Set(server.log.compactMap(\.selected)).count, 2)
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    // MARK: - Writes during a search

    /// A Delete, a Move, a read mark or a flag, tapped while an "All
    /// Mailboxes" search runs through Trash, Spam and All Mail, thirty times,
    /// each landing at a different point of the search: before it starts,
    /// while one of its three SEARCHes is on the wire, or at its first page.
    ///
    /// In simulation a Delete issued during a search ran its UID MOVE in the
    /// wrong mailbox in 19 of 30 runs. Here every mailbox numbers its
    /// letters from 1000, so a write in the wrong mailbox changes a
    /// different letter, which is what it did on Gmail.
    ///
    /// Five rounds of six, a round on one server, each trial in a round on a
    /// different one of the six newest letters, all unread and unflagged.
    func testWritesTappedDuringASearchEverywhereChangeOnlyTheirOwnLetter() async throws {
        let writes: [(label: String, verb: String,
                      run: (IMAPMailRepository, MessageSummary) async throws -> Void)] = [
            ("delete", "UID MOVE", { try await $0.delete($1) }),
            ("move", "UID MOVE", { try await $0.move($1, to: Server.sent) }),
            ("read", "UID STORE", { try await $0.setRead(true, on: $1) }),
            ("flag", "UID STORE", { try await $0.setFlagged(true, on: $1) }),
        ]
        func holding(_ messageID: String) -> Set<String> {
            Set(Self.mailboxes.filter { mailbox in
                server.uids(in: mailbox).contains { server.letter(uid: $0, in: mailbox)?.messageID == messageID }
            })
        }

        var round = makeRepository()
        var rows: [MessageSummary] = []
        for trial in 0..<30 {
            if trial % 6 == 0 {
                server = serverWithSharedUIDs()
                round = makeRepository()
                _ = try await round.listMailboxes()
                rows = try await round.listMessages(in: "inbox", beforeUID: nil, limit: 6)
            }
            let repository = round
            let (label, verb, write) = writes[trial % writes.count]
            let context = "trial \(trial), \(label)"
            let target = rows[trial % rows.count]
            let targetUID = try XCTUnwrap(UInt32(target.id.split(separator: "/").last ?? ""))
            let messageID = try XCTUnwrap(server.letter(uid: targetUID, in: Server.inbox)?.messageID)
            let untouched = contents(without: messageID)
            let wasIn = holding(messageID)

            // Gmail's slow step, slow here too, so the search is still going
            // when the write lands.
            server.delays = ["UID SEARCH": .microseconds(500)]
            let mark = server.log.count
            let search = Task { try await self.searchEverywhere(repository, for: "garden", limit: 5) }
            let landing = trial % 9
            try await until { self.server.log.count - mark >= landing }
            try await finishing { try await write(repository, target) }
            let hits = try await finishing { try await search.value }
            server.delays = [:]

            // The write went to the Inbox, named his letter, and changed it
            // and nothing else.
            let written = server.log.dropFirst(mark).filter { $0.verb == verb }
            XCTAssertEqual(written.map(\.selected), [Server.inbox], context)
            XCTAssertTrue(written.allSatisfy { $0.command.hasPrefix("\(verb) \(targetUID) ") }, context)
            XCTAssertEqual(contents(without: messageID), untouched, context)
            let nowIn = holding(messageID)
            let flags = Self.mailboxes.compactMap { mailbox in
                server.uids(in: mailbox).first { server.letter(uid: $0, in: mailbox)?.messageID == messageID }
                    .map { server.flags(uid: $0, in: mailbox) }
            }
            switch label {
            case "delete":
                XCTAssertEqual(nowIn, [Server.trash], context)
            case "move":
                XCTAssertEqual(nowIn, wasIn.subtracting([Server.inbox]).union([Server.sent]), context)
            case "read":
                XCTAssertEqual(nowIn, wasIn, context)
                XCTAssertTrue(flags.allSatisfy { $0.contains("\\Seen") }, context)
            default:
                XCTAssertEqual(nowIn, wasIn, context)
                XCTAssertTrue(flags.allSatisfy { $0.contains("\\Flagged") }, context)
            }

            // And every hit the search drew is the letter the server holds
            // under that UID in that mailbox, where it still holds one.
            XCTAssertFalse(hits.isEmpty, context)
            for hit in hits {
                guard let uid = UInt32(hit.id.split(separator: "/").last ?? ""),
                      let letter = server.letter(uid: uid, in: hit.mailboxID) else { continue }
                XCTAssertEqual(hit.subject, letter.subject, "\(context): \(hit.mailboxID) \(uid)")
            }
            XCTAssertEqual(server.log.filter { $0.status != "OK" }, [], context)
            XCTAssertEqual(server.connectionsOpened, 1, context)
            XCTAssertEqual(server.violations, [], context)
        }
    }

    // MARK: - The reconnect window

    /// A letter tapped while the connection is being made again, after the
    /// socket died while he was away.
    ///
    /// Between the new socket opening and LOGIN's answer the client already
    /// reports itself connected. The repository kept its own note of the
    /// selected mailbox and cleared it only once the connect returned, so a
    /// tap in that window skipped its SELECT and was answered BAD, and so
    /// was the page that had found the socket dead.
    func testALetterTappedWhileTheConnectionIsBeingMadeAgainStillOpens() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)

        await server.resetConnections()
        server.holdReplies(to: "LOGIN")
        // The next page finds the socket dead and makes a new one.
        let page = Task {
            try await repository.listMessages(in: "inbox", beforeUID: rows.last?.id, limit: 10)
        }
        try await until { self.server.log.contains { $0.verb == "LOGIN" && $0.connection == 2 } }
        let tap = Task { try await repository.open(rows[2]) }
        try await until { await repository.waitingForExchange == 1 }
        await server.releaseReplies(to: "LOGIN")

        let message = try await finishing { try await tap.value }
        let next = try await finishing { try await page.value }
        XCTAssertEqual(message.subject, rows[2].subject)
        XCTAssertEqual(next.count, 10)
        XCTAssertTrue(Set(next.map(\.id)).isDisjoint(with: rows.map(\.id)))

        // On the new connection the Inbox was selected before either UID
        // command, and the letter went first.
        let uid = try XCTUnwrap(rows[2].id.split(separator: "/").last)
        XCTAssertEqual(server.log.filter { $0.connection == 2 }.map(\.command).prefix(3),
                       ["LOGIN \"\(server.username)\" \"\(server.password)\"",
                        "SELECT \"INBOX\"", "UID FETCH \(uid) (UID BODY.PEEK[])"])
        XCTAssertTrue(server.log.filter { $0.connection == 2 && $0.isUIDCommand }
                          .allSatisfy { $0.selected == Server.inbox && $0.status == "OK" })
        XCTAssertEqual(server.connectionsOpened, 2)
    }

    // MARK: - A write into a renumbered mailbox

    /// Every kind of write, on a letter drawn before the mailbox was
    /// renumbered behind a dead socket so that its UID now names another
    /// letter. The SELECT on the new connection shows the new numbering;
    /// nothing is written and the call fails.
    func testAWriteToAMailboxRenumberedSinceItsRowWasDrawnWritesNothing() async throws {
        let writes: [(label: String, mailbox: String,
                      run: (IMAPMailRepository, MessageSummary) async throws -> Void)] = [
            ("read", Server.inbox, { try await $0.setRead(true, on: $1) }),
            ("flag", Server.inbox, { try await $0.setFlagged(true, on: $1) }),
            ("delete", Server.inbox, { try await $0.delete($1) }),
            ("move", Server.inbox, { try await $0.move($1, to: Server.sent) }),
            ("delete in Trash", Server.trash, { try await $0.delete($1) }),
            ("discard a draft", Server.drafts, { try await $0.deleteDraft($1.id) }),
        ]
        for (label, mailbox, write) in writes {
            server = ScriptedIMAPServer()
            let repository = makeRepository()
            _ = try await repository.listMailboxes()
            let rows = try await repository.listMessages(in: mailbox, beforeUID: nil, limit: 5)
            let first = try XCTUnwrap(server.uids(in: mailbox).first)

            await server.resetConnections()
            server.renumber(mailbox, validity: server.uidValidity(of: mailbox) + 100,
                            firstUID: first - 2)
            // Something else is what reconnects, and it selects nothing.
            _ = try await repository.listMailboxes()
            let before = contents()
            server.clearLog()

            do {
                try await write(repository, rows[1])
                XCTFail("\(label): a write went out against a renumbered mailbox")
            } catch {
                XCTAssertEqual(error as? MailError, .cannotConnect, label)
            }
            XCTAssertEqual(server.log.map(\.verb), ["SELECT"], label)
            XCTAssertEqual(contents(), before, label)
            XCTAssertEqual(server.connectionsOpened, 2, label)

            // The connection is still good, and the next listing is in the
            // new numbering.
            let fresh = try await repository.listMessages(in: mailbox, beforeUID: nil, limit: 5)
            XCTAssertEqual(fresh.map(\.subject), rows.map(\.subject), label)
            XCTAssertEqual(server.connectionsOpened, 2, label)
        }
    }

    // MARK: - A refused SELECT

    /// A folder deleted in another client, still on screen. Each call that
    /// needs it sends the SELECT, is refused, and sends nothing that
    /// depended on it; the connection stays up for everything else.
    func testARefusedSelectSendsNothingThatDependedOnItAndKeepsTheConnection() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        let starred = try await repository.listMessages(in: Server.starred, beforeUID: nil, limit: 5)
        let inbox = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 5)
        server.refusedMailboxes = [Server.starred]

        let calls: [(label: String, run: () async throws -> Void)] = [
            ("open", { _ = try await repository.open(starred[0]) }),
            ("attachment", {
                _ = try await repository.fetchAttachmentData("1", of: starred[1].id,
                                                             mailboxID: Server.starred)
            }),
            ("previews", { _ = try await repository.previews(for: starred.map(\.id), in: Server.starred) }),
            ("list", { _ = try await repository.listMessages(in: Server.starred, beforeUID: nil, limit: 5) }),
            ("page", {
                _ = try await repository.listMessages(in: Server.starred, beforeUID: starred[1].id, limit: 5)
            }),
            ("search", {
                _ = try await repository.search(in: Server.starred, query: "garden",
                                                scope: .currentMailbox, beforeUID: nil, limit: 5)
            }),
            ("read", { try await repository.setRead(true, on: starred[0]) }),
            ("flag", { try await repository.setFlagged(false, on: starred[0]) }),
            ("delete", { try await repository.delete(starred[0]) }),
            ("move", { try await repository.move(starred[0], to: Server.sent) }),
        ]
        for (label, call) in calls {
            let mark = server.log.count
            do {
                try await call()
                XCTFail("\(label): succeeded in a folder the server will not open")
            } catch {
                XCTAssertEqual(error as? MailError, .cannotConnect, label)
            }
            XCTAssertEqual(server.log.dropFirst(mark).map(\.command), ["SELECT \"[Gmail]/Starred\""], label)
            XCTAssertEqual(server.log.last?.status, "NO", label)
        }

        let letter = try await repository.open(inbox[0])
        XCTAssertEqual(letter.subject, inbox[0].subject)
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    // MARK: - The letter he opens goes first

    /// A search's reply is on its way back; previews, the next page and the
    /// folder sweep are queued behind it, in that order; then he opens a
    /// letter in Sent and taps an attachment of one in the Inbox.
    ///
    /// The search is not interrupted: nothing is written until its answer
    /// has been read. Then his letter and his attachment go, and only then
    /// the queued work, in the order it was queued. The line used to be
    /// first come, first served, so he waited for all of it.
    func testTheLetterHeOpensGoesAheadOfQueuedWorkButNeverInterruptsTheExchangeOnTheWire() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        let sent = try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 5)
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)
        // Letter 117, plain text with an HTML alternative as part 2.
        let withParts = rows[3]
        XCTAssertEqual(withParts.subject, "Letter 117: dinner")
        server.clearLog()
        server.holdReplies(to: "UID SEARCH")

        let search = Task {
            try await repository.search(in: "inbox", query: "dinner", scope: .currentMailbox,
                                        beforeUID: nil, limit: 20)
        }
        try await until { self.server.log.contains { $0.verb == "UID SEARCH" } }
        var background: [Task<Void, Error>] = []
        background.append(Task { _ = try await repository.previews(for: rows.map(\.id), in: "inbox") })
        try await until { await repository.waitingForExchange == 1 }
        background.append(Task {
            _ = try await repository.listMessages(in: "inbox", beforeUID: rows.last?.id, limit: 20)
        })
        try await until { await repository.waitingForExchange == 2 }
        background.append(Task { _ = try await repository.listMailboxes() })
        try await until { await repository.waitingForExchange == 3 }

        let open = Task { try await repository.open(sent[1]) }
        try await until { await repository.waitingForExchange == 4 }
        let attachment = Task {
            try await repository.fetchAttachmentData("2", of: withParts.id, mailboxID: "inbox")
        }
        try await until { await repository.waitingForExchange == 5 }
        XCTAssertEqual(server.log.map(\.verb), ["UID SEARCH"], "something was written over the search")

        await server.releaseReplies(to: "UID SEARCH")
        let letter = try await finishing { try await open.value }
        let html = try await finishing { try await attachment.value }
        let hits = try await finishing { try await search.value }
        for task in background { try await finishing { try await task.value } }

        XCTAssertEqual(letter.subject, sent[1].subject)
        XCTAssertTrue(String(decoding: html, as: UTF8.self).contains("<b>dinner</b>"))
        XCTAssertTrue(hits.contains { $0.id == withParts.id })

        let sentUID = try XCTUnwrap(sent[1].id.split(separator: "/").last)
        let partsUID = try XCTUnwrap(withParts.id.split(separator: "/").last)
        let commands = server.log.map(\.command)
        XCTAssertEqual(Array(commands.prefix(6)),
                       [commands[0],
                        "SELECT \"[Gmail]/Sent Mail\"",
                        "UID FETCH \(sentUID) (UID BODY.PEEK[])",
                        "SELECT \"INBOX\"",
                        "UID FETCH \(partsUID) (UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE "
                            + "BODYSTRUCTURE X-GM-LABELS X-GM-THRID X-GM-MSGID)",
                        "UID FETCH \(partsUID) (UID BODY.PEEK[2])"])

        // Then the background, first come first served: the previews, the
        // page, the sweep, and last the search's own page, which queued
        // only once its SEARCH had been answered.
        let rest = server.log.dropFirst(6)
        let firstPreview = try XCTUnwrap(rest.firstIndex { $0.command.contains("BODY.PEEK[1]<0.") })
        let nextPage = try XCTUnwrap(rest.firstIndex { $0.command.contains("ENVELOPE") })
        let sweep = try XCTUnwrap(rest.firstIndex { $0.verb == "LIST" })
        XCTAssertLessThan(firstPreview, nextPage)
        XCTAssertLessThan(nextPage, sweep)
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// A letter opened while an "All Mailboxes" search is in its Trash goes
    /// as soon as the search is done with the Trash, before it moves on to
    /// Spam, and the search picks up where it stopped, ahead of anything
    /// else queued.
    func testALetterOpenedDuringASearchEverywhereGoesBetweenItsMailboxes() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let alone = try await searchEverywhere(repository, for: "garden")
        server.clearLog()
        server.holdReplies(to: "UID SEARCH")

        let search = Task { try await self.searchEverywhere(repository, for: "garden") }
        try await until { self.server.log.contains { $0.verb == "UID SEARCH" } }
        let open = Task { try await repository.open(rows[1]) }
        try await until { await repository.waitingForExchange == 1 }
        let previews = Task { try await repository.previews(for: rows.map(\.id), in: "inbox") }
        try await until { await repository.waitingForExchange == 2 }
        await server.releaseReplies(to: "UID SEARCH")

        let letter = try await finishing { try await open.value }
        let hits = try await finishing { try await search.value }
        _ = try await finishing { try await previews.value }
        XCTAssertEqual(letter.subject, rows[1].subject)
        XCTAssertEqual(hits.map(\.id), alone.map(\.id))

        let uid = try XCTUnwrap(rows[1].id.split(separator: "/").last)
        let steps = server.log.map { entry -> String in
            entry.verb == "SELECT" ? entry.command : "\(entry.verb) in \(entry.selected ?? "-")"
        }
        XCTAssertEqual(Array(steps.prefix(11)), [
            "SELECT \"[Gmail]/Trash\"", "UID SEARCH in [Gmail]/Trash", "UID FETCH in [Gmail]/Trash",
            "SELECT \"INBOX\"", "UID FETCH in INBOX",
            "SELECT \"[Gmail]/Spam\"", "UID SEARCH in [Gmail]/Spam", "UID FETCH in [Gmail]/Spam",
            "SELECT \"[Gmail]/All Mail\"", "UID SEARCH in [Gmail]/All Mail",
            // The previews, which queued while the search had the gate,
            // wait for the whole of it, and go before its first page.
            "SELECT \"INBOX\"",
        ])
        XCTAssertEqual(server.log[4].command, "UID FETCH \(uid) (UID BODY.PEEK[])")
    }

    /// The next keystroke lands while the search is waiting to take the
    /// connection back from a letter it gave way to, whose SELECT is still
    /// on the wire. The search ends there, cancelled. The letter keeps the
    /// connection until its own answers are in: the next call waits for
    /// it, and nothing is written over the letter's SELECT.
    func testASearchCancelledWhileItWaitsToTakeTheConnectionBackLeavesItWithTheLetter() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        server.clearLog()
        server.holdReplies(to: "UID SEARCH")

        let search = Task { try await self.searchEverywhere(repository, for: "garden") }
        try await until { self.server.log.contains { $0.verb == "UID SEARCH" } }
        let open = Task { try await repository.open(rows[1]) }
        try await until { await repository.waitingForExchange == 1 }
        server.holdReplies(to: "SELECT")
        await server.releaseReplies(to: "UID SEARCH")
        // Done with the Trash, the search has given way to the letter.
        try await until { self.server.log.last?.command == "SELECT \"INBOX\"" }
        try await until { await repository.waitingForExchange == 1 }

        search.cancel()
        do {
            _ = try await finishing { try await search.value }
            XCTFail("a cancelled search came back with results")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        let written = server.log.count
        let folders = Task { try await repository.listMailboxes() }
        try await until { await repository.waitingForExchange == 1 }
        XCTAssertEqual(server.log.count, written, "written over the letter's SELECT")

        await server.releaseReplies(to: "SELECT")
        let letter = try await finishing { try await open.value }
        _ = try await finishing { try await folders.value }
        XCTAssertEqual(letter.subject, rows[1].subject)
        let uid = try XCTUnwrap(rows[1].id.split(separator: "/").last)
        XCTAssertEqual(server.log.dropFirst(written - 1).prefix(3).map(\.command),
                       ["SELECT \"INBOX\"", "UID FETCH \(uid) (UID BODY.PEEK[])", "LIST \"\" \"*\""])
        XCTAssertFalse(server.log.contains { $0.command.hasPrefix("SELECT \"[Gmail]/Spam\"") })
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    // MARK: - A folder he opens, during a search

    /// A folder opened, or a day jumped to, while an "All Mailboxes" search
    /// is in its Trash, with a preview pass queued as well. The page goes
    /// as soon as the search is done with the Trash, all of it at once,
    /// ahead of the previews; then the search carries on. It used to wait
    /// for the whole search, and before that for one command of it at a
    /// time.
    func testAFolderOpenedOrADayJumpedToDuringASearchEverywhereGoesBetweenItsMailboxes() async throws {
        let day = Server.newestDate.addingTimeInterval(-40 * 86_400)
        let opens: [(label: String, steps: [String],
                     run: @Sendable (IMAPMailRepository) async throws -> [String])] = [
            ("folder",
             ["SELECT \"[Gmail]/Sent Mail\"", "UID SEARCH in [Gmail]/Sent Mail",
              "UID FETCH in [Gmail]/Sent Mail"],
             { try await $0.listMessages(in: Server.sent, beforeUID: nil, limit: 5).map(\.id) }),
            ("day",
             ["SELECT \"INBOX\"", "UID SEARCH in INBOX", "UID SEARCH in INBOX", "UID FETCH in INBOX"],
             { try await $0.messages(around: day, in: "inbox", limit: 10)?.messages.map(\.id) ?? [] }),
        ]
        func steps(_ entries: ArraySlice<Server.LogEntry>) -> [String] {
            entries.map { $0.verb == "SELECT" ? $0.command : "\($0.verb) in \($0.selected ?? "-")" }
        }

        for (label, opened, run) in opens {
            server = ScriptedIMAPServer()
            let repository = makeRepository()
            _ = try await repository.listMailboxes()
            let rows = try await repository.listMessages(in: Server.starred, beforeUID: nil, limit: 5)
            let alone = try await run(repository)
            let hits = try await searchEverywhere(repository, for: "garden")
            server.clearLog()
            server.holdReplies(to: "UID SEARCH")

            let search = Task { try await self.searchEverywhere(repository, for: "garden") }
            try await until { self.server.log.contains { $0.verb == "UID SEARCH" } }
            let previews = Task { try await repository.previews(for: rows.map(\.id), in: Server.starred) }
            try await until { await repository.waitingForExchange == 1 }
            let open = Task { try await run(repository) }
            try await until { await repository.waitingForExchange == 2 }
            await server.releaseReplies(to: "UID SEARCH")

            let page = try await finishing { try await open.value }
            let found = try await finishing { try await search.value }
            _ = try await finishing { try await previews.value }
            XCTAssertEqual(page, alone, label)
            XCTAssertEqual(found.map(\.id), hits.map(\.id), label)

            XCTAssertEqual(steps(server.log.prefix(10 + opened.count)), [
                "SELECT \"[Gmail]/Trash\"", "UID SEARCH in [Gmail]/Trash", "UID FETCH in [Gmail]/Trash",
            ] + opened + [
                "SELECT \"[Gmail]/Spam\"", "UID SEARCH in [Gmail]/Spam", "UID FETCH in [Gmail]/Spam",
                "SELECT \"[Gmail]/All Mail\"", "UID SEARCH in [Gmail]/All Mail",
                "SELECT \"[Gmail]/Starred\"", "UID FETCH in [Gmail]/Starred",
            ], label)
            XCTAssertEqual(server.log.filter { $0.status != "OK" }, [], label)
            XCTAssertEqual(server.connectionsOpened, 1, label)
            XCTAssertEqual(server.violations, [], label)
        }
    }

    // MARK: - A draft discarded while a letter waits

    /// A draft is discarded, its `\Deleted` STORE still on the wire when
    /// he opens a letter in the Inbox. The letter goes after the EXPUNGE,
    /// not between it and the STORE: the two used to take the connection
    /// separately, so the EXPUNGE ran in the Inbox the letter had just
    /// selected. With UIDPLUS that left the draft in Drafts; without it,
    /// a plain EXPUNGE in the Inbox would take whatever else there was
    /// marked `\Deleted`.
    func testADraftDiscardedAsALetterIsOpenedIsExpungedFromDraftsWithOrWithoutUIDPLUS() async throws {
        let servers: [(withheld: Set<String>, verb: String)] = [([], "UID EXPUNGE"), (["UIDPLUS"], "EXPUNGE")]
        for (withheld, verb) in servers {
            server = ScriptedIMAPServer()
            server.withheldCapabilities = withheld
            let repository = makeRepository()
            _ = try await repository.listMailboxes()
            let drafts = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 5)
            let inbox = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 5)
            let draftUID = try XCTUnwrap(UInt32(drafts[0].id.split(separator: "/").last ?? ""))
            let inboxBefore = server.uids(in: Server.inbox)
            server.clearLog()
            server.holdReplies(to: "UID STORE")

            let discard = Task { try await repository.deleteDraft(drafts[0].id) }
            try await until { self.server.log.contains { $0.verb == "UID STORE" } }
            let open = Task { try await repository.open(inbox[0]) }
            try await until { await repository.waitingForExchange == 1 }
            await server.releaseReplies(to: "UID STORE")
            try await finishing { try await discard.value }
            let letter = try await finishing { try await open.value }

            XCTAssertEqual(letter.subject, inbox[0].subject, verb)
            let expunges = server.log.filter { $0.verb.hasSuffix("EXPUNGE") }
            XCTAssertEqual(expunges.map(\.verb), [verb])
            XCTAssertEqual(expunges.map(\.selected), [Server.drafts], verb)
            XCTAssertFalse(server.uids(in: Server.drafts).contains(draftUID), verb)
            XCTAssertEqual(server.uids(in: Server.inbox), inboxBefore, verb)
            XCTAssertEqual(server.log.filter { $0.status != "OK" }, [], verb)
            XCTAssertEqual(server.violations, [], verb)
        }
    }

    // MARK: - An "All Mailboxes" search, on the wire

    /// On a quiet connection: three SELECTs, three SEARCHes, the binned
    /// summaries and the first page, in that order, nine commands. And with
    /// a preview pass for the Inbox queueing a command throughout, the same
    /// eight up to All Mail's SEARCH still go back to back, where they used
    /// to take turns with it, a SELECT of the Inbox each time, and each of
    /// those cost the search a SELECT to get back.
    func testASearchEverywhereSendsItsCommandsBackToBackWhateverElseIsQueued() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()

        let alone = try await searchEverywhere(repository, for: "garden")
        let searchSteps = [
            "SELECT \"[Gmail]/Trash\"", "UID SEARCH in [Gmail]/Trash", "UID FETCH in [Gmail]/Trash",
            "SELECT \"[Gmail]/Spam\"", "UID SEARCH in [Gmail]/Spam", "UID FETCH in [Gmail]/Spam",
            "SELECT \"[Gmail]/All Mail\"", "UID SEARCH in [Gmail]/All Mail",
        ]
        func steps(_ entries: ArraySlice<Server.LogEntry>) -> [String] {
            entries.map { $0.verb == "SELECT" ? $0.command : "\($0.verb) in \($0.selected ?? "-")" }
        }
        XCTAssertEqual(steps(server.log[...]), searchSteps + ["UID FETCH in [Gmail]/All Mail"])

        // Again, beside a preview pass that fetches the Inbox's previews
        // five rows at a time for as long as the search runs.
        server.defaultDelay = .milliseconds(1)
        server.clearLog()
        let searching = Flag()
        let finished = Flag()
        let previews = Task {
            var batches = 0
            while !finished.isSet {
                let start = (batches * 5) % rows.count
                _ = try await repository.previews(for: rows[start..<start + 5].map(\.id), in: "inbox")
                batches += 1
                if batches == 2 { searching.set() }
            }
        }
        try await until { searching.isSet }
        let busy = try await finishing { try await self.searchEverywhere(repository, for: "garden") }
        finished.set()
        try await finishing { try await previews.value }

        XCTAssertEqual(busy.map(\.id), alone.map(\.id))
        let start = try XCTUnwrap(server.log.firstIndex { $0.command == "SELECT \"[Gmail]/Trash\"" })
        XCTAssertEqual(steps(server.log[start..<min(start + 8, server.log.count)]), searchSteps)
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
    }

    /// B-011's rules checked against an answer worked out another way. A
    /// search in each of All Mail, Trash and Spam on its own, taken whole,
    /// put newest first with ties broken by id and cut into pages of three,
    /// is what the merged search must hand out page by page: every hit once,
    /// none skipped, and none out of place across a page boundary.
    func testASearchEverywherePagedThreeAtATimeMatchesTheThreeMailboxesMergedByHand() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()

        var everything: [MessageSummary] = []
        for mailbox in [Server.allMail, Server.trash, Server.spam] {
            var cursor: String?
            while true {
                let page = try await repository.search(in: mailbox, query: "garden",
                                                       scope: .currentMailbox,
                                                       beforeUID: cursor, limit: 50)
                everything += page
                guard page.count == 50 else { break }
                cursor = page.last?.id
            }
        }
        let merged = everything.sorted(by: SearchMerge.isOrderedBefore)
        let expected = stride(from: 0, to: merged.count, by: 3).map {
            merged[$0..<min($0 + 3, merged.count)].map(\.id)
        }
        XCTAssertGreaterThan(expected.count, 8)
        XCTAssertTrue(everything.contains { $0.mailboxID == Server.trash })
        XCTAssertTrue(everything.contains { $0.mailboxID == Server.spam })

        var pages: [[String]] = []
        var cursor: String?
        while pages.count < 60 {
            let page = try await repository.search(in: "inbox", query: "garden", scope: .allMailboxes,
                                                   beforeUID: cursor, limit: 3)
            guard !page.isEmpty else { break }
            pages.append(page.map(\.id))
            cursor = page.last?.id
        }
        XCTAssertEqual(pages, expected)
    }
}
