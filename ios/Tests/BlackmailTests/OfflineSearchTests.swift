import XCTest
@testable import Blackmail

/// Searching with no connection (B-160, the third of its three parts): Mail
/// searches what it has downloaded, and says "Some Results May Not Appear".
/// Here a search that cannot reach the server is answered from the copy
/// kept on the iPad, with nothing sent: the kept rows of the folder, or of
/// every folder kept, and the words kept beside each letter he opened or
/// that was fetched ahead, matched by the words and the rule the server is
/// asked by, as far as the kept copy allows.
///
/// The matching, the words kept beside a letter, the search over the
/// scripted server through the shipping repository, and the list's wiring
/// read from its source.
final class OfflineSearchTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "OfflineSearchTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var line: SearchLine!
    private var root: URL!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        line = SearchLine()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("OfflineSearchTests-\(UUID().uuidString)", isDirectory: true)
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

    private func makeRepository(shelf: MailShelf) -> IMAPMailRepository {
        let imap = server.transportFactory
        let line = self.line!
        return IMAPMailRepository(
            account: server.account, password: server.password,
            transport: { host, port in line.isUp ? imap(host, port) : imap(host, 1) },
            recipients: book, signatureImages: { [] }, shelf: shelf)
    }

    private static let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func row(_ n: Int, from sender: String = "Sam Example <sam@example.com>",
                     to: [String] = ["owner@example.com"], cc: [String] = [],
                     subject: String = "A note", preview: String = "") -> MessageSummary {
        MessageSummary(id: "1/\(n)", mailboxID: "INBOX", sender: sender, subject: subject, preview: preview,
                       date: Self.base.addingTimeInterval(Double(n) * 60), isRead: true, isFlagged: false,
                       threadID: nil, gmailMessageID: UInt64(9_000 + n), to: to, cc: cc)
    }

    private func ids(_ rows: [MessageSummary]) -> [String] { rows.map(\.id) }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<2_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    // MARK: - The matching

    /// Each word wanted, each found in From, To, Cc, the subject, the few
    /// words or the letter's kept words, as a whole word, ignoring case and
    /// accents; the hits newest first.
    func testEveryWordIsWantedEachAnywhereAsAWholeWord() {
        let rows = [
            row(1, subject: "The garden"),
            row(2, from: "Carlo Müller <carlo@example.org>", subject: "Dinner"),
            row(3, cc: ["Jane <jane@example.com>"], subject: "Tickets", preview: "the garden gate"),
            row(4, subject: "Gardener's bill"),
            row(5, subject: "Photos"),
        ]
        let words: [String: String] = ["1/5": "Pictures of the GARDEN in May."]
        func hits(_ query: String) -> [String] {
            ids(KeptSearch.hits(for: query, in: rows) { words[$0.id] })
        }
        XCTAssertEqual(hits("garden "), ["1/5", "1/3", "1/1"], "subject, few words, kept words; newest first")
        XCTAssertEqual(hits("garden jane "), ["1/3"], "every word")
        XCTAssertEqual(hits("muller "), ["1/2"], "no accent")
        XCTAssertEqual(hits("MÜLLER "), ["1/2"])
        XCTAssertEqual(hits("carlo@example.org "), ["1/2"])
        XCTAssertEqual(hits("gard "), [], "not part of a word")
        XCTAssertEqual(hits("a garden "), ["1/5", "1/3", "1/1"], "a word of one letter left out")
        XCTAssertEqual(hits("   "), [])
        XCTAssertEqual(hits("owner@example.com "), ["1/5", "1/4", "1/3", "1/2", "1/1"], "To")
    }

    /// The word he is still typing is the start of a person's name or
    /// address too, as the server is asked for the people it may start
    /// (B-123); never the start of a word of the subject or the letter. A
    /// space after it, and it is a whole word.
    func testAWordHalfTypedIsTheStartOfAPerson() {
        let rows = [row(1, from: "Margaret Example <margaret@example.com>", subject: "Hello"),
                    row(2, subject: "Marginal notes", preview: "marginally"),
                    row(3, to: ["Margo <m@example.com>"])]
        XCTAssertEqual(ids(KeptSearch.hits(for: "Marg", in: rows) { _ in "margins" }), ["1/3", "1/1"])
        XCTAssertEqual(ids(KeptSearch.hits(for: "Marg ", in: rows) { _ in nil }), [])
        XCTAssertEqual(ids(KeptSearch.hits(for: "hello Marg", in: rows) { _ in nil }), ["1/1"])
        XCTAssertEqual(ids(KeptSearch.hits(for: "Ma", in: rows) { _ in nil }), [], "too short to be a start")
    }

    /// Never the start of one of his own: none of his addresses, nor a name
    /// he goes under, as online the book offers neither (B-123); every
    /// letter is to him or from him, so his own name half typed matched
    /// nearly every letter. Another's name or address still matches, and
    /// his name typed whole is a word as before.
    func testAWordHalfTypedIsNeverTheStartOfHisOwn() {
        let mine = OwnAddresses(["owner@example.com"])
        let rows = [row(1, to: ["Carlo Example <owner@example.com>"]),
                    row(2, from: "Carmen <carmen@example.com>", to: ["Carlo Example <owner@example.com>"]),
                    row(3, to: ["Carlo Example <owner@example.com>", "Carlo Example <carlo.two@example.com>"]),
                    row(4, to: ["carlo.two@example.com"]),
                    row(5, to: ["Carlo Example <other@example.com>"])]
        XCTAssertEqual(ids(KeptSearch.hits(for: "Carl", in: rows, besides: mine) { _ in nil }), ["1/5", "1/4"],
                       "his address and the name it goes under in the same letter")
        XCTAssertEqual(ids(KeptSearch.hits(for: "Carl", in: rows, besides: mine, names: ["Carlo Example"]) { _ in nil }),
                       ["1/4"], "and a name of his")
        XCTAssertEqual(ids(KeptSearch.hits(for: "Car", in: rows, besides: mine, names: ["Carlo Example"]) { _ in nil }),
                       ["1/4", "1/2"])
        XCTAssertEqual(ids(KeptSearch.hits(for: "owne", in: rows, besides: mine) { _ in nil }), [])
        XCTAssertEqual(ids(KeptSearch.hits(for: "Carlo ", in: rows, besides: mine) { _ in nil }).count, 5,
                       "typed whole, a word as before")
        XCTAssertEqual(ids(KeptSearch.hits(for: "Carl", in: rows) { _ in nil }).count, 5, "with none of his given")
    }

    /// A phrase in quote marks: as written, in any field; or in the
    /// letter's words, all its words anywhere, as Gmail reads a phrase in
    /// the body.
    func testAPhrase() {
        let rows = [row(1, subject: "Plan B for Sunday"), row(2, subject: "B plan"), row(3)]
        let words = ["1/3": "The plan is the second one, b for short."]
        XCTAssertEqual(ids(KeptSearch.hits(for: "\u{201C}plan b\u{201D}", in: rows) { words[$0.id] }),
                       ["1/3", "1/1"])
    }

    /// A row's kept words are asked for only when the row itself does not
    /// hold a word, and once a row.
    func testTheKeptWordsAreReadOnlyWhenNeeded() {
        let rows = [row(1, subject: "garden roses"), row(2, subject: "garden"), row(3)]
        var asked: [String] = []
        let hits = KeptSearch.hits(for: "garden roses ", in: rows) { row in
            asked.append(row.id)
            return row.id == "1/2" ? "roses and more roses" : nil
        }
        XCTAssertEqual(ids(hits), ["1/2", "1/1"])
        XCTAssertEqual(asked, ["1/2", "1/3"])
    }

    /// Mail's words for results not all there, and a search answered from
    /// the iPad after any failure but one called off.
    func testTheWordsAndWhenTheIPadAnswers() {
        XCTAssertEqual(SearchAnswer.someResults, "Some Results May Not Appear")
        XCTAssertTrue(SearchAnswer.searchesTheIPad(after: MailError.cannotConnect))
        XCTAssertFalse(SearchAnswer.searchesTheIPad(after: CancellationError()))
    }

    // MARK: - The words kept beside a letter

    /// Kept beside the letter, the first `Bounds.words` characters; gone
    /// with it, however it goes; a file of words no letter names swept at
    /// the first use.
    func testTheWordsAreKeptBesideTheLetterAndGoWithIt() throws {
        var options = KeptLetters.Options()
        options.bounds.letters = 2
        options.bounds.words = 10
        let shelf = makeShelf(options: options)
        let letters = shelf.letters
        func keep(_ n: Int, words: String?) {
            letters.keep(Data("Subject: \(n)\r\n\r\nLetter \(n).\r\n".utf8), in: Server.inbox, validity: 1,
                         uid: UInt32(n), message: UInt64(n), words: words)
        }
        func words(_ n: Int) -> String? {
            letters.words(in: Server.inbox, validity: 1, uid: UInt32(n), message: UInt64(n))
        }
        func wordsFile(_ n: Int) -> URL {
            letters.files.appendingPathComponent(
                KeptLetters.wordsFile(KeptLetters.fileName(Server.inbox, 1, UInt32(n), UInt64(n))))
        }
        keep(1, words: "The tiler comes on Tuesday.")
        keep(2, words: nil)
        XCTAssertEqual(words(1), "The tiler ")
        XCTAssertNil(words(2))
        XCTAssertNil(letters.words(in: Server.inbox, validity: 1, uid: 1, message: 2), "another letter")
        XCTAssertTrue(FileManager.default.fileExists(atPath: wordsFile(1).path))

        keep(3, words: "three")
        XCTAssertNil(words(1), "evicted with its letter")
        XCTAssertFalse(FileManager.default.fileExists(atPath: wordsFile(1).path))
        letters.gone(uid: 3, validity: 1, in: Server.inbox)
        _ = letters.records
        XCTAssertFalse(FileManager.default.fileExists(atPath: wordsFile(3).path), "gone with its letter")

        keep(4, words: "four")
        _ = letters.records
        try Data("changed".utf8).write(to: letters.files.appendingPathComponent(
            KeptLetters.fileName(Server.inbox, 1, 4, 4)))
        XCTAssertNil(letters.letter(in: Server.inbox, validity: 1, uid: 4, message: 4, touch: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: wordsFile(4).path), "dropped with it")

        try Data("stray".utf8).write(to: wordsFile(9))
        keep(5, words: "five")
        shelf.flush()
        let next = makeShelf(options: options)
        XCTAssertEqual(next.letters.words(in: Server.inbox, validity: 1, uid: 5, message: 5), "five")
        XCTAssertFalse(FileManager.default.fileExists(atPath: wordsFile(9).path), "swept")
    }

    // MARK: - Over the server

    /// After a launch that listed the Inbox and Sent Mail, opened a letter
    /// and fetched the unread ones ahead, a launch with no connection finds
    /// a word only in the opened letter's body, one only in an unread
    /// letter's, and his reply in Sent Mail only with All Mailboxes, each
    /// letter once, with nothing at all sent.
    func testWithNoConnectionTheKeptCopyIsSearched() async throws {
        server.deliver(Server.Letter(from: Server.sam, to: [Server.owner], subject: "Roof",
                                     date: Server.newestDate.addingTimeInterval(60),
                                     text: "The tiler comes on Tuesday.\r\n", flags: ["\\Seen"],
                                     messageID: "<roof@example.com>"),
                       to: [Server.inbox, Server.allMail])
        server.deliver(Server.Letter(from: Server.carlo, to: [Server.owner], subject: "Plans",
                                     date: Server.newestDate.addingTimeInterval(120),
                                     text: "Bring the trellis.\r\n", messageID: "<plans@example.com>"),
                       to: [Server.inbox, Server.allMail])
        server.deliver(Server.Letter(from: Server.owner, to: [Server.sam], subject: "Re: Roof",
                                     date: Server.newestDate.addingTimeInterval(180),
                                     text: "The tiler is welcome.\r\n", flags: ["\\Seen"],
                                     messageID: "<roof-re@example.com>"),
                       to: [Server.sent, Server.allMail])
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.listMailboxes()
        _ = try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 50)
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let roof = try XCTUnwrap(rows.first { $0.subject == "Roof" })
        _ = try await repository.openLetter(roof)
        await repository.fetchAhead()
        try await until { shelf.letters.records.count == 8 }
        shelf.flush()

        line.isUp = false
        server.clearLog()
        let offline = makeRepository(shelf: makeShelf())
        do {
            _ = try await offline.search(in: "inbox", query: "tiler ", scope: .currentMailbox,
                                         beforeUID: nil, limit: 50)
            XCTFail("searched the server with no connection")
        } catch {}
        let tiler = await offline.searchKept(in: "inbox", query: "tiler ", scope: .currentMailbox)
        XCTAssertEqual(tiler?.map(\.subject), ["Roof"], "in the opened letter's words")
        let trellis = await offline.searchKept(in: "inbox", query: "trellis", scope: .currentMailbox)
        XCTAssertEqual(trellis?.map(\.subject), ["Plans"], "in a letter fetched ahead")
        let everywhere = await offline.searchKept(in: "inbox", query: "roof ", scope: .allMailboxes)
        XCTAssertEqual(everywhere?.map(\.subject), ["Re: Roof", "Roof"], "his reply, from Sent Mail")
        XCTAssertEqual(everywhere?.map(\.mailboxID), [Server.sent, "inbox"])
        let both = await offline.searchKept(in: Server.sent, query: "tiler ", scope: .allMailboxes)
        XCTAssertEqual(both?.map(\.subject), ["Roof"], "only kept words: his reply was never opened")
        let none = await offline.searchKept(in: "inbox", query: "gutters ", scope: .allMailboxes)
        XCTAssertEqual(none, [])
        XCTAssertEqual(server.log, [], "nothing sent")
    }

    /// The repository leaves his own out of a word half typed, as Settings
    /// has his addresses: the seeded letters are all to the account's
    /// address, and its start finds none of them.
    func testTheRepositoryLeavesHisOwnOutOfAWordHalfTyped() async throws {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.listMailboxes()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertFalse(rows.isEmpty)
        line.isUp = false
        let own = await repository.searchKept(in: "inbox", query: "owne", scope: .currentMailbox)
        XCTAssertEqual(own, [])
        let sam = await repository.searchKept(in: "inbox", query: "Sam Exa", scope: .currentMailbox) ?? []
        XCTAssertFalse(sam.isEmpty, "another's start still")
    }

    /// Each letter once with All Mailboxes, the folder's own row first: the
    /// same letter in the Inbox and All Mail is one hit, the Inbox's.
    func testEachLetterOnceTheFoldersOwnFirst() async throws {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.listMailboxes()
        let all = try await repository.listMessages(in: Server.allMail, beforeUID: nil, limit: 50)
        let inbox = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        line.isUp = false
        let hits = await repository.searchKept(in: "inbox", query: "invoice ", scope: .allMailboxes) ?? []
        let inInbox = Set(inbox.compactMap(\.gmailMessageID))
        XCTAssertGreaterThan(hits.filter { inInbox.contains($0.gmailMessageID ?? 0) }.count, 0)
        XCTAssertTrue(all.contains { inInbox.contains($0.gmailMessageID ?? 0) && $0.subject.contains("invoice") },
                      "the same letters kept in All Mail too")
        XCTAssertTrue(hits.contains { !inInbox.contains($0.gmailMessageID ?? 0) }, "All Mail's own too")
        XCTAssertEqual(Set(hits.compactMap(\.gmailMessageID)).count, hits.count, "each once")
        for hit in hits where inInbox.contains(hit.gmailMessageID ?? 0) {
            XCTAssertEqual(hit.mailboxID, "inbox", "the Inbox's own row")
        }
    }

    // MARK: - The list

    /// The list searches the copy kept on the iPad when the server cannot
    /// be reached, unless the search was called off; draws its hits all at
    /// once, with nothing to page; and says Mail's line under them until
    /// the search ends.
    func testTheListSearchesTheIPadWithNoConnection() throws {
        let list = try source("UI/MessageListViewController.swift")
        let run = try section(of: list, from: "private func runSearch(_ text: String) async {",
                              to: "private var searchFailed = false")
        XCTAssertTrue(run.contains("} catch { if SearchAnswer.searchesTheIPad(after: error), !Task.isCancelled, "
                                   + "let kept = await repository.searchKept(in: mailbox.id, query: text, "
                                   + "scope: scope) { fromTheIPad = true outcome = .success(kept) } "
                                   + "else { outcome = .failure(error) } }"), run)
        XCTAssertTrue(run.contains("reachedOldestMessage = hits.count < Self.pageSize "
                                   + "searchingTheIPad = fromTheIPad "
                                   + "if fromTheIPad { reachedOldestMessage = true } sayAge()"))
        XCTAssertTrue(list.contains("if searchingTheIPad, letters.isSearching { say(SearchAnswer.someResults) "
                                    + "return }"))
        let end = try section(of: list, from: "private func showUnfilteredList() {", to: "@objc private func cancelSearch()")
        XCTAssertTrue(end.contains("if searchingTheIPad { searchingTheIPad = false sayAge() }"))
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
private final class SearchLine: @unchecked Sendable {
    private let lock = NSLock()
    private var up = true

    var isUp: Bool {
        get { lock.lock(); defer { lock.unlock() }; return up }
        set { lock.lock(); up = newValue; lock.unlock() }
    }
}
