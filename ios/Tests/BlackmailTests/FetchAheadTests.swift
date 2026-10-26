import XCTest
@testable import Blackmail

/// Letters fetched ahead for reading with no connection (B-160, the second
/// of its three parts): Mail downloads mail ahead of his opening it, so with
/// no connection a letter he never opened opens. Here the newest unread
/// letters of the Inbox's kept page are fetched whole after its first page
/// and its previews, in pieces in the background line while the Inbox is
/// the folder open, by BODY.PEEK with Gmail's id and size asked beside the
/// first, never a STORE, and kept as letters fetched ahead, in room of
/// their own, the oldest letter going first, so a pass over letters kept
/// already sends nothing, however full the store.
///
/// The rule, the store's tier, the client's pieces and the pass over the
/// scripted server through the shipping repository and client, and the
/// list's wiring read from its source.
final class FetchAheadTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "FetchAheadTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var line: AheadLine!
    private var root: URL!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        line = AheadLine()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("FetchAheadTests-\(UUID().uuidString)", isDirectory: true)
        Diagnostics.clear()
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
        line = nil
        root = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private var kept: URL { root.appendingPathComponent("Kept", isDirectory: true) }

    private func makeShelf(options: KeptLetters.Options = KeptLetters.Options()) -> MailShelf {
        MailShelf(root: kept, address: server.username, host: server.account.imapHost, letters: options)
    }

    private func makeRepository(shelf: MailShelf, largeLetterBytes: Int = IMAPMailRepository.largeLetterBytes,
                                aheadLetters: Int = IMAPMailRepository.mostAhead,
                                aheadBytes: Int = IMAPMailRepository.mostAheadBytes) -> IMAPMailRepository {
        let imap = server.transportFactory
        let line = self.line!
        return IMAPMailRepository(
            account: server.account, password: server.password,
            transport: { host, port in line.isUp ? imap(host, port) : imap(host, 1) },
            recipients: book, signatureImages: { [] }, shelf: shelf, largeLetterBytes: largeLetterBytes,
            aheadLetters: aheadLetters, aheadBytes: aheadBytes)
    }

    /// A launch with a connection: the folders, the Inbox's first page.
    private func listed(_ repository: IMAPMailRepository) async throws -> [MessageSummary] {
        _ = try await repository.listMailboxes()
        return try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
    }

    private func uid(_ id: String) -> UInt32 { UInt32(id.split(separator: "/").last ?? "") ?? 0 }

    /// The seeded Inbox's unread letters, newest first: its newest six.
    private func unread(_ rows: [MessageSummary]) -> [MessageSummary] { rows.filter { !$0.isRead } }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<2_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    // MARK: - The rule

    /// The unread rows with a Gmail id, newest first as given, the first
    /// `most` of them.
    func testWhichLettersAreFetchedAhead() {
        func row(_ n: Int, read: Bool, gmail: UInt64? = 1) -> MessageSummary {
            MessageSummary(id: "1/\(n)", mailboxID: "INBOX", sender: "Sam", subject: "\(n)", preview: "",
                           date: Date(timeIntervalSince1970: Double(n)), isRead: read, isFlagged: false,
                           threadID: nil, gmailMessageID: gmail.map { $0 + UInt64(n) })
        }
        let rows = [row(9, read: false), row(8, read: true), row(7, read: false, gmail: nil),
                    row(6, read: false), row(5, read: false), row(4, read: false)]
        XCTAssertEqual(FetchAhead.letters(on: rows, most: 3).map(\.id), ["1/9", "1/6", "1/5"])
        XCTAssertEqual(FetchAhead.letters(on: rows, most: 50).map(\.id), ["1/9", "1/6", "1/5", "1/4"])
        XCTAssertEqual(IMAPMailRepository.mostAhead, 50)
        XCTAssertEqual(IMAPMailRepository.mostAheadBytes, 20 << 20)
    }

    // MARK: - Over the server

    /// After the Inbox's first page, the pass fetches its unread letters,
    /// newest first, each by `BODY.PEEK[]` from its first byte with Gmail's
    /// id asked beside it, and nothing else: no STORE, no SELECT of another
    /// folder, nothing marked read. Each is kept as fetched ahead, and at
    /// the next launch, with no connection, opens from the iPad, with
    /// nothing sent, and is then a letter he opened.
    func testTheNewestUnreadLettersAreFetchedByPeekAndOpenOffline() async throws {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let rows = try await listed(repository)
        let waiting = unread(rows)
        XCTAssertEqual(waiting.count, 6)
        server.clearLog()

        await repository.fetchAhead()
        XCTAssertEqual(server.log.map(\.verb), Array(repeating: "UID FETCH", count: 6))
        XCTAssertEqual(server.log.map(\.command),
                       waiting.map { "UID FETCH \(uid($0.id)) (UID X-GM-MSGID RFC822.SIZE BODY.PEEK[]<0.131072>)" })
        XCTAssertFalse(server.log.contains { $0.command.contains("BODY[") })
        for row in waiting {
            XCTAssertFalse(server.flags(uid: uid(row.id), in: Server.inbox).contains("\\Seen"), row.id)
        }
        try await until { shelf.letters.records.count == 6 }
        XCTAssertTrue(shelf.letters.records.allSatisfy(\.isAhead))
        XCTAssertEqual(Set(shelf.letters.records.map(\.uid)), Set(waiting.map { uid($0.id) }))
        shelf.flush()

        line.isUp = false
        server.clearLog()
        let offline = makeShelf()
        let next = makeRepository(shelf: offline)
        let keptRow = try XCTUnwrap(offline.page(of: "inbox")?.rows.first { $0.id == waiting[2].id })
        let letter = try await next.openLetter(keptRow)
        XCTAssertEqual(letter.subject, waiting[2].subject)
        XCTAssertFalse((letter.textBody ?? letter.htmlBody ?? "").isEmpty)
        XCTAssertEqual(server.log, [], "nothing sent")
        XCTAssertEqual(offline.letters.records.filter { !$0.isAhead }.map(\.uid), [uid(waiting[2].id)],
                       "opened, it is a letter he opened")
    }

    /// A letter larger than a piece comes a piece at a time, each its own
    /// exchange, Gmail's id asked beside the first alone, and is kept whole,
    /// byte for byte the server's.
    func testALetterOfSeveralPiecesComesWhole() async throws {
        let words = String(repeating: "The long letter goes on and on. ", count: 9_000) + "\r\n"
        let delivered = server.deliver(Server.Letter(from: Server.sam, to: [Server.owner], subject: "Long",
                                                     date: Server.newestDate.addingTimeInterval(60),
                                                     text: words, messageID: "<long@example.com>"),
                                       to: [Server.inbox, Server.allMail])
        let long = try XCTUnwrap(delivered[Server.inbox])
        let raw = try XCTUnwrap(server.raw(uid: long, in: Server.inbox))
        XCTAssertGreaterThan(raw.count, 2 * IMAPMailRepository.aheadPiece)
        XCTAssertLessThan(raw.count, 3 * IMAPMailRepository.aheadPiece)
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf, aheadLetters: 1)
        _ = try await listed(repository)
        server.clearLog()

        await repository.fetchAhead()
        let piece = IMAPMailRepository.aheadPiece
        XCTAssertEqual(server.log.map(\.command), [
            "UID FETCH \(long) (UID X-GM-MSGID RFC822.SIZE BODY.PEEK[]<0.\(piece)>)",
            "UID FETCH \(long) (UID BODY.PEEK[]<\(piece).\(piece)>)",
            "UID FETCH \(long) (UID BODY.PEEK[]<\(2 * piece).\(piece)>)",
        ])
        try await until { shelf.letters.records.count == 1 }
        let record = try XCTUnwrap(shelf.letters.records.first)
        let kept = shelf.letters.letter(in: Server.inbox, validity: record.validity, uid: record.uid,
                                        message: record.message, touch: false)
        XCTAssertEqual(kept, raw)
    }

    /// The bounds: no more than the newest `aheadLetters` unread letters,
    /// and the pass stops once `aheadBytes` have come.
    func testThePassStopsAtItsBounds() async throws {
        let few = makeShelf()
        let two = makeRepository(shelf: few, aheadLetters: 2)
        let rows = try await listed(two)
        await two.fetchAhead()
        try await until { few.letters.records.count == 2 }
        XCTAssertEqual(Set(few.letters.records.map(\.uid)), Set(unread(rows).prefix(2).map { uid($0.id) }))

        MailShelf.wipe(root: kept)
        let small = makeShelf()
        let one = makeRepository(shelf: small, aheadBytes: 1)
        _ = try await listed(one)
        server.clearLog()
        await one.fetchAhead()
        XCTAssertEqual(server.log.count, 1, "stopped once a byte had come")
    }

    /// Passed over: a letter kept already, so a second pass sends nothing;
    /// one above the size opened in parts; a letter read; and everything
    /// with no connection up, where nothing at all is sent, not even a
    /// LOGIN.
    func testWhatIsPassedOver() async throws {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let rows = try await listed(repository)
        await repository.fetchAhead()
        try await until { shelf.letters.records.count == 6 }
        server.clearLog()
        await repository.fetchAhead()
        XCTAssertEqual(server.log, [], "kept already")
        XCTAssertEqual(Set(shelf.letters.records.map(\.uid)), Set(unread(rows).map { uid($0.id) }),
                       "no letter read")

        MailShelf.wipe(root: kept)
        let big = makeShelf()
        let small = makeRepository(shelf: big, largeLetterBytes: 10)
        _ = try await listed(small)
        server.clearLog()
        await small.fetchAhead()
        XCTAssertEqual(server.log, [], "each above the size opened in parts")

        line.isUp = false
        server.clearLog()
        let offline = makeRepository(shelf: makeShelf())
        await offline.fetchAhead()
        XCTAssertEqual(server.log, [], "no connection made")
    }

    /// Only while the Inbox is the folder open, under the row's
    /// UIDVALIDITY: with nothing open, or another folder, nothing is sent,
    /// not even a SELECT. Another letter at the UID than the row's: the
    /// client asks no more after the first piece, and nothing is handed
    /// back. Past the most it may be by the size given beside the first
    /// piece: nothing more asked.
    func testAnotherLetterUnderTheUIDIsNotFetched() async throws {
        let client = IMAPClient(account: server.account, transport: server.transportFactory)
        try await client.connect(password: server.password)
        let newest = try XCTUnwrap(server.uids(in: Server.inbox).last)
        let validity = server.uidValidity(of: Server.inbox)
        let real = try XCTUnwrap(server.gmailMessageID(uid: newest, in: Server.inbox))
        let raw = try XCTUnwrap(server.raw(uid: newest, in: Server.inbox))
        server.clearLog()
        let closed = try await client.fetchBodyAhead(uid: newest, in: Server.inbox, validity: validity,
                                                     letter: real, piece: 64, most: 1 << 20)
        XCTAssertEqual(closed, .notOpen)
        XCTAssertEqual(server.log, [])
        _ = try await client.searchAll(in: Server.sent)
        server.clearLog()
        let elsewhere = try await client.fetchBodyAhead(uid: newest, in: Server.inbox, validity: validity,
                                                        letter: real, piece: 64, most: 1 << 20)
        XCTAssertEqual(elsewhere, .notOpen)
        XCTAssertEqual(server.log, [], "nothing sent, not even a SELECT")

        _ = try await client.searchAll(in: Server.inbox)
        server.clearLog()
        let renumbered = try await client.fetchBodyAhead(uid: newest, in: Server.inbox, validity: validity + 1,
                                                         letter: real, piece: 64, most: 1 << 20)
        XCTAssertEqual(renumbered, .notOpen)
        let got = try await client.fetchBodyAhead(uid: newest, in: Server.inbox, validity: validity,
                                                  letter: real + 1, piece: 64, most: 1 << 20)
        XCTAssertEqual(got, .notThere)
        XCTAssertEqual(server.log.map(\.verb), ["UID FETCH"])
        let whole = try await client.fetchBodyAhead(uid: newest, in: Server.inbox, validity: validity,
                                                    letter: real, piece: 64, most: 1 << 20)
        XCTAssertEqual(whole, .letter(raw))
        server.clearLog()
        let over = try await client.fetchBodyAhead(uid: newest, in: Server.inbox, validity: validity,
                                                   letter: real, piece: 64, most: 100)
        XCTAssertEqual(over, .over(raw.count), "past the most it may be, by its size")
        XCTAssertEqual(server.log.count, 1, "nothing asked past the first piece")
        await client.disconnect()
    }

    // MARK: - The store

    /// Letters fetched ahead have room of their own: neither kind ever
    /// goes for the other. Past their room the oldest letter goes, by its
    /// UID, not the one fetched longest ago, so the newest stay; one older
    /// than every letter in a full room is not kept, nothing going for it,
    /// and the room says so before it is fetched (`roomAhead`). Opened, a
    /// letter fetched ahead is one he opened, and the letters he opened go
    /// as theirs do. Fetched ahead again, a letter he opened stays as it
    /// was.
    func testLettersFetchedAheadHaveRoomOfTheirOwn() throws {
        var options = KeptLetters.Options()
        options.bounds.letters = 2
        options.bounds.ahead = 2
        let shelf = makeShelf(options: options)
        let letters = shelf.letters
        func raw(_ n: Int) -> Data { Data("Subject: \(n)\r\n\r\nLetter \(n).\r\n".utf8) }
        func keep(_ n: Int, ahead: Bool) {
            letters.keep(raw(n), in: Server.inbox, validity: 1, uid: UInt32(n), message: UInt64(n), ahead: ahead)
        }
        func kept() -> [UInt32] { letters.records.map(\.uid) }
        keep(1, ahead: false)
        keep(2, ahead: false)
        keep(10, ahead: true)
        keep(11, ahead: true)
        XCTAssertEqual(kept(), [1, 2, 10, 11], "each in its own room")
        keep(3, ahead: false)
        XCTAssertEqual(kept(), [2, 10, 11, 3], "a letter opened puts out one opened")
        keep(12, ahead: true)
        XCTAssertEqual(kept(), [2, 11, 3, 12], "past their room, the oldest letter")
        XCTAssertNil(letters.roomAhead(validity: 1, uid: 9), "older than both: no room")
        XCTAssertNotNil(letters.roomAhead(validity: 1, uid: 13))
        XCTAssertNotNil(letters.roomAhead(validity: 1, uid: 11), "only 12 is newer")
        keep(9, ahead: true)
        XCTAssertEqual(kept(), [2, 11, 3, 12], "not kept, and nothing goes for it")
        XCTAssertNotNil(letters.letter(in: Server.inbox, validity: 1, uid: 11, message: 11, touch: true))
        XCTAssertEqual(kept(), [3, 12, 11], "opened, it is one he opened, and the oldest opened goes")
        XCTAssertEqual(letters.records.filter(\.isAhead).map(\.uid), [12])
        keep(3, ahead: true)
        XCTAssertEqual(kept(), [3, 12, 11], "fetched ahead again, left as it was")
        XCTAssertTrue(letters.has(in: Server.inbox, validity: 1, uid: 12, message: 12))
        XCTAssertFalse(letters.has(in: Server.inbox, validity: 1, uid: 12, message: 13))
        shelf.flush()
        XCTAssertEqual(makeShelf(options: options).letters.records.map(\.uid), [3, 12, 11])
    }

    /// The words kept beside a letter count with it, in the bounds and
    /// against the floor.
    func testTheWordsCountWithTheLetter() throws {
        let raw = Data("Subject: 1\r\n\r\nLetter.\r\n".utf8)
        let words = String(repeating: "w", count: 100)
        var options = KeptLetters.Options()
        options.bounds.bytes = 2 * raw.count + 150
        let shelf = makeShelf(options: options)
        shelf.letters.keep(raw, in: Server.inbox, validity: 1, uid: 1, message: 1, words: words)
        shelf.letters.keep(raw, in: Server.inbox, validity: 1, uid: 2, message: 2, words: words)
        XCTAssertEqual(shelf.letters.records.map(\.uid), [2], "two letters' bytes, and their words")
        XCTAssertEqual(shelf.letters.records.first?.words, 100)
        XCTAssertEqual(shelf.letters.records.first?.kept, raw.count + 100)

        MailShelf.wipe(root: kept)
        var floor = KeptLetters.Options()
        floor.bounds.floor = 1_000
        floor.freeSpace = { 1_000 + Int64(raw.count) + 50 }
        let near = makeShelf(options: floor)
        near.letters.keep(raw, in: Server.inbox, validity: 1, uid: 1, message: 1, words: words)
        XCTAssertEqual(near.letters.records, [], "under the floor with its words")
    }

    // MARK: - Passes over a full store

    /// A store full of letters he opened leaves the letters fetched ahead
    /// their room: a pass keeps every one it fetched, and the next, with
    /// nothing new, sends nothing. Each one fetched ahead used to put out
    /// the one fetched before it, and every pass fetched them all again.
    func testAFullStoreOfOpenedLettersAndTwoPasses() async throws {
        var options = KeptLetters.Options()
        options.bounds.letters = 3
        let shelf = makeShelf(options: options)
        for n in 1...3 {
            shelf.letters.keep(Data("Subject: \(n)\r\n\r\nOpened \(n).\r\n".utf8), in: "Archive", validity: 1,
                               uid: UInt32(n), message: UInt64(n))
        }
        XCTAssertEqual(shelf.letters.records.count, 3)
        let repository = makeRepository(shelf: shelf)
        let rows = try await listed(repository)
        server.clearLog()
        await repository.fetchAhead()
        XCTAssertEqual(server.log.count, 6)
        try await until { shelf.letters.records.filter(\.isAhead).count == 6 }
        XCTAssertEqual(shelf.letters.records.filter { !$0.isAhead }.count, 3, "none he opened went")
        XCTAssertEqual(Set(shelf.letters.records.filter(\.isAhead).map(\.uid)), Set(unread(rows).map { uid($0.id) }))

        server.clearLog()
        await repository.fetchAhead()
        XCTAssertEqual(server.log, [], "the second pass sends nothing")
    }

    /// With more unread letters than the room holds, one new letter is one
    /// FETCH: the pass fetches it, the oldest letter fetched ahead goes,
    /// and the rest are kept already. A pass after it sends nothing.
    func testOneNewLetterIsOneFetch() async throws {
        var options = KeptLetters.Options()
        options.bounds.ahead = 3
        let shelf = makeShelf(options: options)
        let repository = makeRepository(shelf: shelf, aheadLetters: 3)
        let rows = try await listed(repository)
        let waiting = unread(rows)
        XCTAssertGreaterThan(waiting.count, 3)
        await repository.fetchAhead()
        try await until { shelf.letters.records.count == 3 }

        let fresh = server.deliver(Server.Letter(from: Server.sam, to: [Server.owner], subject: "New",
                                                 date: Server.newestDate.addingTimeInterval(60),
                                                 text: "Something new.\r\n", messageID: "<new@example.com>"),
                                   to: [Server.inbox, Server.allMail])
        let new = try XCTUnwrap(fresh[Server.inbox])
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        await repository.fetchAhead()
        XCTAssertEqual(server.log.map(\.command),
                       ["UID FETCH \(new) (UID X-GM-MSGID RFC822.SIZE BODY.PEEK[]<0.131072>)"])
        try await until { shelf.letters.records.contains { $0.uid == new } }
        XCTAssertEqual(Set(shelf.letters.records.map(\.uid)),
                       Set([new] + waiting.prefix(2).map { uid($0.id) }), "the oldest went")

        server.clearLog()
        await repository.fetchAhead()
        XCTAssertEqual(server.log, [], "nothing more")
    }

    /// The pass stops at the first letter the room has no room for without
    /// a newer one going, before it is fetched: by the count, nothing
    /// asked; by its size, given beside the first piece, nothing past that
    /// piece, and nothing at all at the next pass.
    func testThePassStopsWhereTheRoomIsFull() async throws {
        var options = KeptLetters.Options()
        options.bounds.ahead = 2
        let two = makeShelf(options: options)
        let repository = makeRepository(shelf: two)
        let rows = try await listed(repository)
        let waiting = unread(rows)
        server.clearLog()
        await repository.fetchAhead()
        XCTAssertEqual(server.log.count, 2, "the third never asked")
        try await until { two.letters.records.count == 2 }
        server.clearLog()
        await repository.fetchAhead()
        XCTAssertEqual(server.log, [])

        // The room for the newest two and half the third.
        let kept = Dictionary(uniqueKeysWithValues: two.letters.records.map { ($0.uid, $0.kept) })
        let third = try XCTUnwrap(server.raw(uid: uid(waiting[2].id), in: Server.inbox))
        MailShelf.wipe(root: self.kept)
        var bytes = KeptLetters.Options()
        bytes.bounds.aheadBytes = (kept[uid(waiting[0].id)] ?? 0) + (kept[uid(waiting[1].id)] ?? 0)
            + third.count / 2
        let small = makeShelf(options: bytes)
        let next = makeRepository(shelf: small)
        _ = try await listed(next)
        server.clearLog()
        await next.fetchAhead()
        XCTAssertEqual(server.log.map(\.command).last,
                       "UID FETCH \(uid(waiting[2].id)) (UID X-GM-MSGID RFC822.SIZE BODY.PEEK[]<0.131072>)")
        XCTAssertEqual(server.log.count, 3, "the third's first piece, and no more")
        try await until { small.letters.records.count == 2 }
        server.clearLog()
        await next.fetchAhead()
        XCTAssertEqual(server.log, [], "nothing at the next pass")
    }

    /// Only while the Inbox is the folder open: with Sent Mail open the
    /// pass sends nothing, not a SELECT of the Inbox, so his next tap there
    /// waits for nothing, and a lookup's few words there are not skipped.
    func testNothingIsFetchedWhileAnotherFolderIsOpen() async throws {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await listed(repository)
        _ = try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 50)
        server.clearLog()
        await repository.fetchAhead()
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(shelf.letters.records, [])
    }

    /// Two asked at once are one pass: each letter fetched once. The pass
    /// is marked as under way before its first wait, read from the source,
    /// since whether two calls meet in that wait is the scheduler's to say.
    func testTwoAskedAtOnceAreOnePass() async throws {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let rows = try await listed(repository)
        server.clearLog()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { await repository.fetchAhead() } }
        }
        XCTAssertEqual(server.log.count, unread(rows).count)
        XCTAssertEqual(Set(server.log.map(\.command)).count, server.log.count, "none twice")

        let code = try source("Mail/IMAPMailRepository.swift")
        let pass = try section(of: code, from: "func fetchAhead() async {", to: "passing: for row in")
        let marked = try XCTUnwrap(pass.range(of: "fetchingAhead = true"))
        let wait = try XCTUnwrap(pass.range(of: "await "))
        XCTAssertLessThan(marked.lowerBound, wait.lowerBound, "marked before the first wait")
        XCTAssertTrue(pass.contains("guard !retired, !fetchingAhead, !fillingBook, let shelf, let listed "
                                    + "else { return } fetchingAhead = true"))
    }

    // MARK: - The list

    /// The list starts the pass for the Inbox alone, after its fresh first
    /// page's previews: at a Refresh or a launch's page, and as a page
    /// fetched over the kept one lands. The client's pieces go in the
    /// background line.
    func testTheListStartsThePassAfterTheInboxsPreviews() throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains("if passing { kept.uploadWaiting(to: repository) } "
                                    + "fetchAhead(after: pagePreviews) return true"))
        XCTAssertTrue(list.contains("updateSelectAllTitle() fetchAhead(after: loadPreviews(for: unpreviewed)) }"))
        XCTAssertTrue(list.contains("private func fetchAhead(after previews: Task<Void, Never>?) { "
                                    + "guard mailbox.role == .inbox else { return } "
                                    + "let repository = self.repository let ended = afterFetchAhead "
                                    + "Task { @MainActor in await previews?.value "
                                    + "await repository.fetchAhead() ended?() } }"))
        XCTAssertEqual(list.components(separatedBy: "fetchAhead(").count - 1, 4)
        let client = try source("IMAP/IMAPClient.swift")
        let ahead = try section(of: client, from: "func fetchBodyAhead(", to: "struct LetterInPart")
        XCTAssertTrue(ahead.contains("try await beginExchange(.background)"))
        XCTAssertTrue(ahead.contains("guard selectedMailbox == mailbox, mailboxState?.uidValidity == validity else { "
                                     + "return .notOpen }"))
        XCTAssertFalse(ahead.contains("inMailbox("), "never a SELECT")
        XCTAssertFalse(ahead.contains(".interactive"))
        XCTAssertFalse(ahead.contains("BODY["))
    }

    /// No two of the background line's errands fight over the folder open
    /// on the connection: the pass, which never selects, is not begun
    /// beside the book's fill from Sent Mail (B-155), and the look for a
    /// lost answer (B-151), whose SELECT would end it, waits for the next
    /// check while either is under way. The fill waits for the launch's
    /// pass where the Inbox's first page came.
    func testTheLookAndTheFillNeverGoBesideThePass() throws {
        let repository = try source("Mail/IMAPMailRepository.swift")
        XCTAssertTrue(repository.contains(
            "guard !retired, !fetchingAhead, !fillingBook, let shelf, let listed else { return } "
                + "fetchingAhead = true"))
        XCTAssertTrue(repository.contains(
            "func lookAfterLostAnswers() async -> [MovedAfterAll] { "
                + "guard !retired, !lostAnswers.isEmpty, !fetchingAhead, !fillingBook else { return [] }"))
        let root = try source("UI/RootViewController.swift")
        XCTAssertTrue(root.contains("if came, self?.list.shownMailbox.role == .inbox { "
                                    + "self?.fillBookAfterAhead = true } else { self?.fillBookOnce() }"))
    }

    // MARK: - Source

    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }

    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/\(file)")
        let text = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        return flat(text)
    }

    private func section(of code: String, from start: String, to end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start), start)
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex), end)
        return String(code[from.lowerBound..<to.lowerBound])
    }
}

/// The connection, up or down.
private final class AheadLine: @unchecked Sendable {
    private let lock = NSLock()
    private var up = true

    var isUp: Bool {
        get { lock.lock(); defer { lock.unlock() }; return up }
        set { lock.lock(); up = newValue; lock.unlock() }
    }
}
