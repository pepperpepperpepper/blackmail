import XCTest
@testable import Blackmail

/// His own replies in an Inbox conversation, kept on the iPad with it
/// (B-159): Mail keeps the mail it has downloaded, Sent Mail's with the
/// rest, so with Complete Threads on, as it is from the factory, a
/// conversation opened after a relaunch with no connection shows his lines
/// "Found in Sent Mail", and the ones he opened open. Here they lived in
/// memory for ten minutes and were gone after an offline relaunch (D-021,
/// B-111).
///
/// The store through the shelf that keeps it, the pane's rule for its first
/// frame, and the lookup and the opening over the scripted server through
/// the shipping repository and client, launch after launch, with the line
/// taken down for the offline one.
final class HisRepliesKeptTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "HisRepliesKeptTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var clock: ManualClock!
    private var line: HisLine!
    private var root: URL!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        clock = ManualClock()
        line = HisLine()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("HisRepliesKeptTests-\(UUID().uuidString)", isDirectory: true)
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
        clock = nil
        line = nil
        root = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private var kept: URL { root.appendingPathComponent("Kept", isDirectory: true) }

    /// The shelf a launch makes, over whatever earlier ones left.
    private func makeShelf() -> MailShelf {
        let clock = self.clock!
        return MailShelf(root: kept, address: server.username, host: server.account.imapHost,
                         now: { clock.now() })
    }

    private func makeRepository(shelf: MailShelf) -> IMAPMailRepository {
        let imap = server.transportFactory
        let line = self.line!
        let clock = self.clock!
        return IMAPMailRepository(
            account: server.account, password: server.password,
            transport: { host, port in line.isUp ? imap(host, port) : imap(host, 1) },
            recipients: book, now: { clock.now() }, signatureImages: { [] }, shelf: shelf)
    }

    private static let base = Date(timeIntervalSince1970: 1_790_000_000)

    /// A letter of his in Sent Mail, `n` minutes in, in conversation 42.
    private func his(_ n: Int, gmail: UInt64? = nil) -> MessageSummary {
        MessageSummary(id: "6/\(n)", mailboxID: Server.sent, sender: "owner@example.com",
                       subject: "Re: the roof", preview: "mine \(n)",
                       date: Self.base.addingTimeInterval(Double(n) * 60), isRead: true,
                       isFlagged: false, threadID: "42", gmailMessageID: gmail ?? UInt64(8_000 + n),
                       to: ["Sam Example <sam@example.com>"],
                       arrived: Self.base.addingTimeInterval(Double(n) * 60))
    }

    /// A letter of the conversation `thread` in the Inbox, `n` minutes in.
    private func inbox(_ n: Int, thread: UInt64 = 42) -> MessageSummary {
        MessageSummary(id: "1/\(n)", mailboxID: Server.inbox, sender: "Sam Example <sam@example.com>",
                       subject: "Re: the roof", preview: "letter \(n)",
                       date: Self.base.addingTimeInterval(Double(n) * 60), isRead: true,
                       isFlagged: false, threadID: String(thread), gmailMessageID: UInt64(9_000 + n),
                       arrived: Self.base.addingTimeInterval(Double(n) * 60))
    }

    private func found(_ letters: MessageSummary...) -> RelatedLetters {
        RelatedLetters(folderName: "Sent Mail", letters: letters)
    }

    /// The ids, previews and folders of what a shelf keeps for `thread`.
    private func keptIDs(_ shelf: MailShelf, _ thread: UInt64) -> [String]? {
        shelf.lettersOfHis(inThread: thread)?.letters.map(\.id)
    }

    /// Sam's letter in the Inbox, his reply in Sent Mail alone, and Sam's
    /// answer in the Inbox: one Gmail conversation, newer than every other
    /// letter. Returns the reply's UID in Sent Mail.
    @discardableResult
    private func roof() -> UInt32 {
        let start = Server.newestDate.addingTimeInterval(86_400)
        server.deliver(Server.Letter(from: Server.sam, to: [Server.owner], subject: "B-159 roof",
                                     date: start, text: "Shall we fix the roof?\r\n",
                                     messageID: "<roof-1@example.com>"),
                       to: [Server.inbox, Server.allMail])
        let reply = server.deliver(Server.Letter(from: Server.owner, to: [Server.sam],
                                                 subject: "Re: B-159 roof",
                                                 date: start.addingTimeInterval(3_600),
                                                 text: "Yes, on Tuesday.\r\n", flags: ["\\Seen"],
                                                 messageID: "<roof-2@example.com>",
                                                 inReplyTo: "<roof-1@example.com>",
                                                 joins: "<roof-1@example.com>"),
                                   to: [Server.sent, Server.allMail])
        server.deliver(Server.Letter(from: Server.sam, to: [Server.owner], subject: "Re: B-159 roof",
                                     date: start.addingTimeInterval(7_200),
                                     text: "Tuesday it is.\r\n",
                                     messageID: "<roof-3@example.com>",
                                     inReplyTo: "<roof-2@example.com>",
                                     joins: "<roof-1@example.com>"),
                       to: [Server.inbox, Server.allMail])
        return reply[Server.sent] ?? 0
    }

    /// A launch with a connection: the folders swept, the Inbox listed,
    /// its conversation at the top looked up in Sent Mail, and his reply
    /// opened by its line if `opening`; everything written, as going into
    /// the background writes it. The conversation's thread number, the
    /// stack's Gmail ids and his reply's line.
    private func onlineLaunch(opening: Bool) async throws
        -> (number: UInt64, besides: Set<UInt64>, mine: MessageSummary) {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.listMailboxes()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let thread = try XCTUnwrap(MessageThread.group(rows).first)
        let number = try XCTUnwrap(CompleteThreads.thread(toComplete: thread, listedIn: .inbox,
                                                          searching: false, switchedOn: true))
        let besides = Set(thread.messages.compactMap(\.gmailMessageID))
        let found = await repository.lettersOfHis(inThread: number, besides: besides)
        let mine = try XCTUnwrap(found.letters.first)
        if opening { _ = try await repository.openLetter(mine) }
        shelf.flush()
        return (number, besides, mine)
    }

    // MARK: - The store

    /// What a lookup found is kept with its conversation into the next
    /// launch, the rows as the lookup had them, previews and all, under
    /// Sent Mail's name as the Mailboxes pane shows it; another
    /// conversation has none; and a lookup that finds none keeps none.
    func testWhatTheLookupFoundIsKeptIntoTheNextLaunch() throws {
        let first = makeShelf()
        first.took(lettersOfHis: found(his(2), his(4)), inThread: 42, folder: Server.sent, validity: 6)
        first.took(lettersOfHis: found(his(7)), inThread: 43, folder: Server.sent, validity: 6)
        first.flush()

        let next = makeShelf()
        let kept = try XCTUnwrap(next.lettersOfHis(inThread: 42))
        XCTAssertEqual(kept.folderName, "Sent Mail")
        XCTAssertEqual(kept.letters.map(\.id), ["6/2", "6/4"])
        XCTAssertEqual(kept.letters.map(\.preview), ["mine 2", "mine 4"])
        XCTAssertEqual(kept.letters.map(\.mailboxID), [Server.sent, Server.sent])
        XCTAssertEqual(kept.letters.map(\.gmailMessageID), [8_002, 8_004])
        XCTAssertEqual(kept.letters.map(\.to), [["Sam Example <sam@example.com>"],
                                                ["Sam Example <sam@example.com>"]])
        XCTAssertEqual(kept.letters, [his(2), his(4)])
        XCTAssertEqual(keptIDs(next, 43), ["6/7"])
        XCTAssertNil(next.lettersOfHis(inThread: 44))

        next.took(lettersOfHis: .none, inThread: 42, folder: Server.sent, validity: 6)
        XCTAssertNil(next.lettersOfHis(inThread: 42), "none found, none kept")
        XCTAssertEqual(keptIDs(next, 43), ["6/7"])
        next.flush()
        XCTAssertNil(makeShelf().lettersOfHis(inThread: 42))
    }

    /// Sent Mail under another UIDVALIDITY throws away every conversation's
    /// letters, whether a lookup or a listing of Sent Mail from the top
    /// finds it: their ids name other letters there, or none.
    func testAnotherUIDValidityForSentMailThrowsThemAllAway() {
        let shelf = makeShelf()
        shelf.took(lettersOfHis: found(his(2)), inThread: 42, folder: Server.sent, validity: 6)
        shelf.took(lettersOfHis: found(his(7)), inThread: 43, folder: Server.sent, validity: 6)
        shelf.took(lettersOfHis: found(his(9)), inThread: 44, folder: Server.sent, validity: 8)
        XCTAssertNil(shelf.lettersOfHis(inThread: 42))
        XCTAssertNil(shelf.lettersOfHis(inThread: 43))
        XCTAssertEqual(keptIDs(shelf, 44), ["6/9"])

        shelf.took(page: [], of: Server.sent, validity: 9)
        XCTAssertNil(shelf.lettersOfHis(inThread: 44), "listed under another")
        shelf.flush()
        XCTAssertNil(makeShelf().lettersOfHis(inThread: 44))

        shelf.took(lettersOfHis: found(his(9)), inThread: 45, folder: Server.sent, validity: 9)
        shelf.took(page: [], of: Server.sent, validity: 9)
        XCTAssertEqual(keptIDs(shelf, 45), ["6/9"], "listed under the same")
    }

    /// Kept with the conversation and no longer: the Inbox listed from the
    /// top takes the letters of every conversation it no longer holds, and
    /// another folder listed takes none.
    func testTheInboxListedTakesTheConversationsItNoLongerHolds() {
        let shelf = makeShelf()
        shelf.took(lettersOfHis: found(his(2)), inThread: 42, folder: Server.sent, validity: 6)
        shelf.took(lettersOfHis: found(his(7)), inThread: 43, folder: Server.sent, validity: 6)
        shelf.took(page: [inbox(1, thread: 77)], of: Server.allMail, validity: 1)
        XCTAssertEqual(keptIDs(shelf, 42), ["6/2"])
        XCTAssertEqual(keptIDs(shelf, 43), ["6/7"])

        shelf.took(page: [inbox(3), inbox(1, thread: 77)], of: Server.inbox, validity: 1)
        XCTAssertEqual(keptIDs(shelf, 42), ["6/2"])
        XCTAssertNil(shelf.lettersOfHis(inThread: 43), "its conversation off the Inbox")
    }

    /// At most `mostConversations` conversations and `mostLettersOfHis`
    /// letters, the conversation looked up longest ago going first, and a
    /// conversation looked up again the newest.
    func testTheBoundsTakeTheConversationLookedUpLongestAgo() {
        let shelf = makeShelf()
        let most = MailShelf.mostConversations
        for thread in 1...most {
            shelf.took(lettersOfHis: found(his(1)), inThread: UInt64(thread), folder: Server.sent, validity: 6)
        }
        shelf.took(lettersOfHis: found(his(1)), inThread: 1, folder: Server.sent, validity: 6)
        shelf.took(lettersOfHis: found(his(1)), inThread: UInt64(most + 1), folder: Server.sent, validity: 6)
        XCTAssertNotNil(shelf.lettersOfHis(inThread: 1), "looked up again")
        XCTAssertNil(shelf.lettersOfHis(inThread: 2), "the longest ago")
        XCTAssertNotNil(shelf.lettersOfHis(inThread: 3))
        XCTAssertNotNil(shelf.lettersOfHis(inThread: UInt64(most + 1)))

        let twenty = (1...CompleteThreads.mostLetters).map { his($0) }
        let full = RelatedLetters(folderName: "Sent Mail", letters: twenty + [his(99)])
        let conversations = MailShelf.mostLettersOfHis / CompleteThreads.mostLetters
        for thread in 1...(conversations + 1) {
            shelf.took(lettersOfHis: full, inThread: UInt64(10_000 + thread), folder: Server.sent,
                       validity: 6)
        }
        XCTAssertEqual(shelf.lettersOfHis(inThread: 10_002)?.letters.count, CompleteThreads.mostLetters,
                       "no more than a stack shows")
        XCTAssertNil(shelf.lettersOfHis(inThread: 10_001), "past the letters' bound")
        XCTAssertNotNil(shelf.lettersOfHis(inThread: UInt64(10_001 + conversations)))
        XCTAssertNil(shelf.lettersOfHis(inThread: UInt64(most + 1)))
    }

    /// What the server takes away goes from them: his letter deleted or
    /// moved out of Sent Mail, binned from anywhere by its Gmail id, and
    /// one the server says is another letter; a letter binned from Sent
    /// Mail into the Trash stays only where it went. The whole copy thrown
    /// away, and a password saved, take them all.
    func testWhatTheServerTakesAwayGoesFromThem() {
        let shelf = makeShelf()
        shelf.took(lettersOfHis: found(his(2), his(4), his(6), his(8)), inThread: 42,
                   folder: Server.sent, validity: 6)
        shelf.gone("6/2", from: Server.sent)
        shelf.gone("1/9", letter: 8_004, from: Server.allMail, andEveryFolderBut: Server.trash)
        shelf.refuse("6/6", in: Server.sent, keptAs: 8_006)
        shelf.gone("6/8", from: Server.drafts)
        XCTAssertEqual(keptIDs(shelf, 42), ["6/8"])
        shelf.refuse("6/8", in: Server.sent, keptAs: 1)
        XCTAssertEqual(keptIDs(shelf, 42), ["6/8"], "kept as another letter")
        shelf.gone("6/8", from: Server.sent)
        XCTAssertNil(shelf.lettersOfHis(inThread: 42), "none left")

        shelf.took(page: [inbox(3)], of: Server.inbox, validity: 1)
        shelf.took(lettersOfHis: found(his(2)), inThread: 42, folder: Server.sent, validity: 6)
        shelf.took(page: [inbox(3)], of: Server.inbox, validity: 2)
        XCTAssertNil(shelf.lettersOfHis(inThread: 42), "the copy thrown away")

        let again = makeShelf()
        again.took(lettersOfHis: found(his(2)), inThread: 42, folder: Server.sent, validity: 6)
        again.flush()
        MailShelf.wipe(root: kept)
        XCTAssertNil(again.lettersOfHis(inThread: 42))
        XCTAssertNil(makeShelf().lettersOfHis(inThread: 42), "a password saved")
    }

    /// A line found with no few words keeps the few words kept for the
    /// same letter, as a page listed over kept rows does: the lookup skips
    /// them when another folder has been opened between its search and
    /// their FETCH. Not for another letter under the id, and not over few
    /// words found.
    func testALineFoundWithoutItsFewWordsKeepsTheKeptOnes() throws {
        let shelf = makeShelf()
        shelf.took(lettersOfHis: found(his(2), his(4), his(6)), inThread: 42, folder: Server.sent, validity: 6)
        var bare = his(2)
        bare.preview = ""
        var another = his(4, gmail: 1)
        another.preview = ""
        var said = his(6)
        said.preview = "mine at last"
        shelf.took(lettersOfHis: found(bare, another, said), inThread: 42, folder: Server.sent, validity: 6)
        XCTAssertEqual(shelf.lettersOfHis(inThread: 42)?.letters.map(\.preview), ["mine 2", "", "mine at last"])
        shelf.flush()
        XCTAssertEqual(makeShelf().lettersOfHis(inThread: 42)?.letters.map(\.preview),
                       ["mine 2", "", "mine at last"])
        var elsewhere = his(2)
        elsewhere.preview = ""
        shelf.took(lettersOfHis: found(elsewhere), inThread: 43, folder: Server.sent, validity: 6)
        XCTAssertEqual(shelf.lettersOfHis(inThread: 43)?.letters.map(\.preview), [""],
                       "another conversation's are not carried")
    }

    /// Read in the background as the Inbox's kept page is first asked for,
    /// at a launch's first frame, so the first conversation he opens has
    /// them in memory and its frame reads nothing on the main thread.
    func testTheyAreReadInTheBackgroundAsTheInboxIsAskedFor() async throws {
        let first = makeShelf()
        first.took(lettersOfHis: found(his(2)), inThread: 42, folder: Server.sent, validity: 6)
        first.flush()

        let next = makeShelf()
        XCTAssertFalse(next.lettersOfHisRead, "nothing read as the shelf is made")
        _ = next.page(of: Server.sent)
        XCTAssertFalse(next.lettersOfHisRead, "another folder's page asks for none")
        _ = next.page(of: "inbox")
        try await until { next.lettersOfHisRead }
        let file = next.directory.appendingPathComponent("related.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(keptIDs(next, 42), ["6/2"], "read already")
    }

    /// An answer that may be from before a reply he has just sent, the memo
    /// forgotten while the lookup was out, is shown and not kept: neither
    /// remembered nor kept on the iPad, where it could replace a later
    /// lookup's.
    func testAnAnswerFromBeforeTheMemoWasForgottenIsNotKept() async throws {
        roof()
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.listMailboxes()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let thread = try XCTUnwrap(MessageThread.group(rows).first)
        let number = try XCTUnwrap(CompleteThreads.thread(toComplete: thread, listedIn: .inbox,
                                                          searching: false, switchedOn: true))
        let besides = Set(thread.messages.compactMap(\.gmailMessageID))
        let memo = repository.hisLetters
        server.change(after: { $0.verb == "UID SEARCH" }) { memo.forget() }
        let found = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertFalse(found.letters.isEmpty, "shown")
        XCTAssertNil(repository.rememberedLettersOfHis(inThread: number, besides: besides))
        XCTAssertNil(shelf.lettersOfHis(inThread: number), "not kept on the iPad")

        let again = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertEqual(again.letters, found.letters)
        XCTAssertEqual(shelf.lettersOfHis(inThread: number)?.letters.map(\.id), found.letters.map(\.id),
                       "the next lookup's kept")
    }

    // MARK: - The pane's first frame

    /// With nothing remembered, his letters kept on the iPad are in the
    /// stack's first frame, and the lookup still goes once the newest letter
    /// has come: what it finds that is there already is not put in again,
    /// and what has come since is. Remembered from the last ten minutes, the
    /// memo is shown and nothing is looked up, as before.
    func testKeptLinesDrawFirstAndTheLookupStillAddsWhatIsNew() throws {
        let stack = [inbox(3), inbox(5)]
        var related = PaneRelated()
        let first = try XCTUnwrap(related.show(stack, completing: 42, remembered: nil,
                                               kept: found(his(4), his(5, gmail: 9_005))))
        XCTAssertEqual(first, found(his(4)), "less the stack's own")
        XCTAssertEqual(related.entryID(forSection: "mr6_4"), "r6/4")
        XCTAssertEqual(related.load(for: "r6/4")?.row, his(4))
        XCTAssertEqual(related.lookUp(afterTheNewestCame: true), 42, "still asked")

        let runs = related.take(found(his(4), his(6)), stack: stack)
        XCTAssertEqual(runs.flatMap { $0.entries.map(\.id) }, ["r6/6"], "only what came since")
        XCTAssertEqual(related.load(for: "r6/6")?.row, his(6))
        XCTAssertEqual(related.take(found(his(4)), stack: stack).count, 0)

        XCTAssertEqual(related.show(stack, completing: 42, remembered: found(his(2)), kept: found(his(4))),
                       found(his(2)))
        XCTAssertNil(related.lookUp(afterTheNewestCame: true), "remembered: nothing looked up")
        XCTAssertNil(related.show(stack, completing: 42, remembered: nil, kept: nil))
        XCTAssertEqual(related.lookUp(afterTheNewestCame: true), 42)
        XCTAssertNil(related.show(stack, completing: nil, remembered: nil, kept: found(his(4))),
                     "Complete Threads off")
        XCTAssertNil(related.lookUp(afterTheNewestCame: true))
    }

    // MARK: - Over the server

    /// After a launch that looked his reply up and opened it, a relaunch
    /// with no connection has the conversation's line for it, "Found in
    /// Sent Mail" as it was, and opens it from the iPad, with nothing at all
    /// sent: not even the LOGIN. The lookup itself, offline, sends nothing
    /// and finds none, and the kept line stays.
    func testAnOfflineRelaunchShowsHisReplyAndOpensIt() async throws {
        roof()
        let (number, besides, mine) = try await onlineLaunch(opening: true)

        line.isUp = false
        server.clearLog()
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        XCTAssertNil(repository.rememberedLettersOfHis(inThread: number, besides: besides),
                     "the memo is the launch's")
        let kept = try XCTUnwrap(repository.lettersOfHisKept(inThread: number, besides: besides))
        XCTAssertEqual(kept.folderName, "Sent Mail")
        XCTAssertEqual(kept.letters, [mine])
        XCTAssertTrue(mine.preview.hasPrefix("Yes, on Tuesday"), mine.preview)

        let letter = try await repository.openLetter(mine)
        XCTAssertTrue(letter.textBody?.contains("Yes, on Tuesday.") == true)
        let looked = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertEqual(looked, .none)
        XCTAssertEqual(server.log, [], "nothing sent")
        XCTAssertEqual(repository.lettersOfHisKept(inThread: number, besides: besides)?.letters, [mine])
        XCTAssertEqual(repository.lettersOfHisKept(inThread: number, besides: [mine.gmailMessageID!])?
                        .letters, [], "less the stack's own")
    }

    /// A reply of his that was looked up and never opened has its line
    /// offline, and says it cannot be downloaded when opened, as a letter
    /// of the Inbox never opened does.
    func testAReplyNeverOpenedHasItsLineAndNoBodyOffline() async throws {
        roof()
        let (number, besides, mine) = try await onlineLaunch(opening: false)
        line.isUp = false
        let repository = makeRepository(shelf: makeShelf())
        XCTAssertEqual(repository.lettersOfHisKept(inThread: number, besides: besides)?.letters, [mine])
        do {
            _ = try await repository.openLetter(mine)
            XCTFail("opened with no connection")
        } catch {}
    }

    /// His reply opened by its line is fetched as before, its body peeked
    /// at and nothing marked, and kept with the letters he opened under
    /// Sent Mail's four keys; opened again in the same launch, nothing is
    /// sent.
    func testHisReplyOpenedIsKeptAndNothingIsMarked() async throws {
        let uid = roof()
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let thread = try XCTUnwrap(MessageThread.group(rows).first)
        let number = try XCTUnwrap(CompleteThreads.threadNumber(thread.newest.threadID))
        let looked = await repository.lettersOfHis(inThread: number, besides: [])
        let mine = try XCTUnwrap(looked.letters.first)
        server.clearLog()

        _ = try await repository.openLetter(mine)
        XCTAssertEqual(server.log.map(\.verb), ["UID FETCH"])
        XCTAssertTrue(server.log[0].command.contains("BODY.PEEK[]"), server.log[0].command)
        XCTAssertFalse(server.log.contains { ["UID STORE", "UID MOVE", "UID COPY", "APPEND"].contains($0.verb) })
        XCTAssertEqual(server.flags(uid: uid, in: Server.sent), ["\\Seen"])
        try await until { shelf.letters.records.count == 1 }
        let record = try XCTUnwrap(shelf.letters.records.first)
        XCTAssertEqual(record.folder, Server.sent)
        XCTAssertEqual(record.validity, server.uidValidity(of: Server.sent))
        XCTAssertEqual(record.uid, uid)
        XCTAssertEqual(record.message, mine.gmailMessageID)

        server.clearLog()
        _ = try await repository.openLetter(mine)
        XCTAssertEqual(server.log, [], "from the iPad")
    }

    /// Sent Mail renumbered: the next lookup finds his reply under the new
    /// numbers, and the lines kept under the old are gone, so nothing kept
    /// names a UID the folder has given to another letter.
    func testSentMailRenumberedReplacesWhatWasKept() async throws {
        roof()
        let (number, besides, mine) = try await onlineLaunch(opening: false)
        let old = server.uidValidity(of: Server.sent)
        server.renumber(Server.sent, validity: old + 10, firstUID: 1)

        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.listMailboxes()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(repository.lettersOfHisKept(inThread: number, besides: besides)?.letters, [mine])
        let again = await repository.lettersOfHis(inThread: number, besides: besides)
        let now = try XCTUnwrap(again.letters.first)
        XCTAssertNotEqual(now.id, mine.id)
        XCTAssertEqual(now.gmailMessageID, mine.gmailMessageID)
        XCTAssertEqual(repository.lettersOfHisKept(inThread: number, besides: besides)?.letters.map(\.id),
                       [now.id])
        shelf.flush()
        XCTAssertEqual(makeShelf().lettersOfHis(inThread: number)?.letters.map(\.id), [now.id])
    }

    /// Nothing of his letters in the log: their lines read back and his
    /// reply opened from the iPad name no folder, person or word of them.
    func testNothingOfThemInTheLog() async throws {
        roof()
        let (number, besides, mine) = try await onlineLaunch(opening: true)
        line.isUp = false
        Diagnostics.clear()
        let repository = makeRepository(shelf: makeShelf())
        XCTAssertNotNil(repository.lettersOfHisKept(inThread: number, besides: besides))
        _ = try await repository.openLetter(mine)
        XCTAssertFalse(Diagnostics.entries.isEmpty, "the showing's note")
        for entry in Diagnostics.entries {
            for word in ["roof", "Tuesday", "Sam", "sam@example.com", "Sent Mail"] {
                XCTAssertFalse(entry.text.contains(word), entry.text)
            }
        }
    }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<2_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }
}

/// The connection, up or down: down, every connect is refused, as one with
/// no route is.
private final class HisLine: @unchecked Sendable {
    private let lock = NSLock()
    private var up = true

    var isUp: Bool {
        get { lock.lock(); defer { lock.unlock() }; return up }
        set { lock.lock(); up = newValue; lock.unlock() }
    }
}
