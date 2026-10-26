import XCTest
@testable import Blackmail

/// Letters fetched ahead for reading with no connection (B-160, the second
/// of its three parts): Mail downloads mail ahead of his opening it, so with
/// no connection a letter he never opened opens. Here the newest unread
/// letters of the Inbox's kept page are fetched whole after its first page
/// and its previews, in pieces in the background line, by BODY.PEEK with
/// Gmail's id asked beside the first, never a STORE, and kept as letters
/// fetched ahead, which go first.
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
                       waiting.map { "UID FETCH \(uid($0.id)) (UID X-GM-MSGID BODY.PEEK[]<0.131072>)" })
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
            "UID FETCH \(long) (UID X-GM-MSGID BODY.PEEK[]<0.\(piece)>)",
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

    /// Another letter at the UID than the row's: the client asks no more
    /// after the first piece, and nothing is handed back.
    func testAnotherLetterUnderTheUIDIsNotFetched() async throws {
        let client = IMAPClient(account: server.account, transport: server.transportFactory)
        try await client.connect(password: server.password)
        let newest = try XCTUnwrap(server.uids(in: Server.inbox).last)
        let validity = server.uidValidity(of: Server.inbox)
        let real = try XCTUnwrap(server.gmailMessageID(uid: newest, in: Server.inbox))
        server.clearLog()
        let got = try await client.fetchBodyAhead(uid: newest, in: Server.inbox, validity: validity,
                                                  letter: real + 1, piece: 64, most: 1 << 20)
        XCTAssertNil(got)
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID FETCH"])
        let whole = try await client.fetchBodyAhead(uid: newest, in: Server.inbox, validity: validity,
                                                    letter: real, piece: 64, most: 1 << 20)
        XCTAssertEqual(whole, server.raw(uid: newest, in: Server.inbox))
        let over = try await client.fetchBodyAhead(uid: newest, in: Server.inbox, validity: validity,
                                                   letter: real, piece: 64, most: 100)
        XCTAssertNil(over, "past the most it may be")
        await client.disconnect()
    }

    // MARK: - The store

    /// Fetched ahead, a letter goes first: before any he opened when the
    /// store is past its bounds, and past their own bounds the one fetched
    /// longest ago. Opened, it is a letter he opened. Fetched ahead again,
    /// a letter he opened stays as it was.
    func testLettersFetchedAheadGoFirst() throws {
        var options = KeptLetters.Options()
        options.bounds.letters = 4
        options.bounds.ahead = 2
        let shelf = makeShelf(options: options)
        let letters = shelf.letters
        func raw(_ n: Int) -> Data { Data("Subject: \(n)\r\n\r\nLetter \(n).\r\n".utf8) }
        func keep(_ n: Int, ahead: Bool) {
            letters.keep(raw(n), in: Server.inbox, validity: 1, uid: UInt32(n), message: UInt64(n), ahead: ahead)
        }
        func kept() -> [UInt32] { letters.records.map(\.uid) }
        keep(1, ahead: false)
        keep(2, ahead: true)
        keep(3, ahead: false)
        keep(4, ahead: true)
        XCTAssertEqual(kept(), [1, 2, 3, 4])
        keep(5, ahead: true)
        XCTAssertEqual(kept(), [1, 3, 4, 5], "past their own bound, the oldest fetched ahead")
        keep(6, ahead: false)
        XCTAssertEqual(kept(), [1, 3, 5, 6], "past the store's, one fetched ahead before one opened")
        XCTAssertNotNil(letters.letter(in: Server.inbox, validity: 1, uid: 5, message: 5, touch: true))
        keep(7, ahead: false)
        XCTAssertEqual(kept(), [3, 6, 5, 7], "opened, it is evicted as one he opened")
        keep(3, ahead: true)
        XCTAssertEqual(kept(), [3, 6, 5, 7], "fetched ahead again, left as it was")
        XCTAssertFalse(letters.records.contains(where: \.isAhead))
        XCTAssertTrue(letters.has(in: Server.inbox, validity: 1, uid: 7, message: 7))
        XCTAssertFalse(letters.has(in: Server.inbox, validity: 1, uid: 7, message: 8))
        shelf.flush()
        XCTAssertEqual(makeShelf(options: options).letters.records.map(\.uid), [3, 6, 5, 7])
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
                                    + "let repository = self.repository "
                                    + "Task { await previews?.value await repository.fetchAhead() } }"))
        XCTAssertEqual(list.components(separatedBy: "fetchAhead(").count - 1, 4)
        let client = try source("IMAP/IMAPClient.swift")
        let ahead = try section(of: client, from: "func fetchBodyAhead(", to: "struct LetterInPart")
        XCTAssertTrue(ahead.contains("try await inMailbox(mailbox, validity: validity, .background)"))
        XCTAssertFalse(ahead.contains(".interactive"))
        XCTAssertFalse(ahead.contains("BODY["))
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
