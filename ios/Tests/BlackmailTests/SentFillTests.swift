import XCTest
@testable import Blackmail

/// The address book filled from his Sent Mail, once per account (B-155):
/// the people his letters of the last six months went to, ranked by how
/// many and how recent, taken in as written to within the book's 300,
/// never pushing out his own addresses and leaving out letters only to
/// them; read in the background line after the Inbox's first page, with
/// nothing marked read.
final class SentFillTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "SentFillTests"

    private var server: ScriptedIMAPServer!
    private var defaults: UserDefaults!
    private var book: RecipientBook!
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        server = nil
        defaults = nil
        book = nil
        super.tearDown()
    }

    // MARK: - Letters

    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func days(_ n: Double) -> Date { Self.now.addingTimeInterval(-n * 86_400) }

    private func address(_ text: String, _ name: String? = nil) -> MailAddress {
        let at = text.lastIndex(of: "@")!
        return MailAddress(name: name, mailbox: String(text[..<at]),
                           host: String(text[text.index(after: at)...]))
    }

    private func letter(to: [MailAddress], cc: [MailAddress] = [], bcc: [MailAddress] = [],
                        went: Date?, dated: Date? = nil) -> IMAPFetchResult {
        var envelope = IMAPEnvelope()
        envelope.date = dated ?? went
        envelope.from = [address("owner@example.com")]
        envelope.to = to
        envelope.cc = cc
        envelope.bcc = bcc
        return IMAPFetchResult(uid: 1, internalDate: went, envelope: envelope)
    }

    private let mine = OwnAddresses(["owner@example.com", "Second@Example.com"])

    private func entry(_ address: String, name: String? = nil, uses: Int, at: Date) -> KnownRecipient {
        KnownRecipient(address: address, name: name, uses: uses, lastSeen: at)
    }

    // MARK: - The people he wrote to

    /// Most letters first, then the newest, then by address; each counted
    /// once a letter, wherever it was named in it, with the date of the
    /// newest.
    func testThePeopleHeWroteToAreRankedByLettersThenByTheNewest() {
        let letters = [
            letter(to: [address("sam@example.com")], went: days(100)),
            letter(to: [address("sam@example.com")], cc: [address("carlo@example.org")], went: days(50)),
            letter(to: [address("jane@example.com")], went: days(2)),
            letter(to: [address("carlo@example.org")], went: days(10)),
            letter(to: [address("bea@example.com")], went: days(2)),
        ]
        let people = RecipientBook.writtenTo(letters, besides: mine)
        XCTAssertEqual(people.map(\.address), ["carlo@example.org", "sam@example.com",
                                               "bea@example.com", "jane@example.com"])
        XCTAssertEqual(people.map(\.uses), [2, 2, 1, 1])
        XCTAssertEqual(people.map(\.lastSeen), [days(10), days(50), days(2), days(2)])
    }

    /// To, Cc and Bcc each count, an address once a letter whatever it is
    /// named in, in any letter case.
    func testToCcAndBccEachCountAndAnAddressOnceALetter() {
        let letters = [
            letter(to: [address("sam@example.com")], cc: [address("Sam@Example.com")],
                   bcc: [address("SAM@example.com")], went: days(3)),
            letter(to: [address("jane@example.com")], bcc: [address("carlo@example.org")], went: days(4)),
            letter(to: [], cc: [address("bea@example.com")], went: days(5)),
        ]
        let people = RecipientBook.writtenTo(letters, besides: mine)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: people.map { ($0.address, $0.uses) }),
                       ["sam@example.com": 1, "jane@example.com": 1, "carlo@example.org": 1,
                        "bea@example.com": 1])
    }

    /// His own addresses, the account's and the others Settings lists, in
    /// any case, are never taken in; a letter only to them gives nothing,
    /// and one to him and Sam gives Sam.
    func testHisOwnAreNeverTakenAndALetterOnlyToThemGivesNothing() {
        let letters = [
            letter(to: [address("owner@example.com")], went: days(1)),
            letter(to: [address("second@example.com", "Me")], cc: [address("OWNER@example.com")],
                   went: days(1)),
            letter(to: [address("owner@example.com"), address("sam@example.com", "Sam")], went: days(2)),
        ]
        let people = RecipientBook.writtenTo(letters, besides: mine)
        XCTAssertEqual(people, [entry("sam@example.com", name: "Sam", uses: 1, at: days(2))])
        XCTAssertEqual(RecipientBook.writtenTo(Array(letters.prefix(2)), besides: mine), [])
    }

    /// The name is the newest letter's that names it; a blank, or the
    /// address again, is no name; Gmail's date for a letter before its own.
    func testTheNameIsTheNewestLettersAndTheDateGmailsFirst() {
        let letters = [
            letter(to: [address("sam@example.com", "Sam Example")], went: days(9)),
            letter(to: [address("sam@example.com", "Sammy")], went: days(4)),
            letter(to: [address("sam@example.com", "  ")], went: days(1)),
            letter(to: [address("sam@example.com", "sam@example.com")], went: days(1)),
            letter(to: [address("carlo@example.org")], went: nil, dated: days(6)),
            letter(to: [address("jane@example.com")], went: days(7), dated: days(-300)),
        ]
        let people = RecipientBook.writtenTo(letters, besides: mine)
        XCTAssertEqual(people.first { $0.address == "sam@example.com" }?.name, "Sammy")
        XCTAssertEqual(people.first { $0.address == "sam@example.com" }?.lastSeen, days(1))
        XCTAssertEqual(people.first { $0.address == "carlo@example.org" }?.lastSeen, days(6))
        XCTAssertEqual(people.first { $0.address == "jane@example.com" }?.lastSeen, days(7),
                       "a Date in the future is not taken over Gmail's")
    }

    /// A group's name, or an address with nothing on one side of its @, is
    /// nobody; a letter with no envelope gives nothing.
    func testAGroupWithNoAddressIsNobody() {
        var bare = IMAPFetchResult(uid: 9, internalDate: days(1))
        bare.envelope = nil
        let letters = [
            letter(to: [MailAddress(name: nil, mailbox: "undisclosed-recipients", host: "")],
                   bcc: [address("sam@example.com")], went: days(1)),
            letter(to: [MailAddress(name: nil, mailbox: "", host: "example.com")], went: days(1)),
            bare,
        ]
        XCTAssertEqual(RecipientBook.writtenTo(letters, besides: mine).map(\.address), ["sam@example.com"])
    }

    // MARK: - The book

    /// Taken in as written to, best first, as many as the 300 holds beside
    /// his own addresses in it, both kept; what was only seen goes first.
    func testTheFillGoesInWithinTheThreeHundredBesideHisOwn() {
        book.noteOwn(address: "owner@example.com", name: "Owner")
        book.note(address: "second@example.com")
        for n in 0..<280 { book.note(address: "seen\(n)@news.example.com") }
        let people = (0..<400).map {
            entry("p\($0)@example.org", uses: 400 - $0, at: days(Double($0)))
        }
        let taken = book.fill(with: people, besides: mine)
        XCTAssertEqual(taken, 298)
        let all = book.snapshot()
        XCTAssertEqual(all.count, RecipientBook.capacity)
        let kept = Set(all.map(\.address))
        XCTAssertTrue(kept.contains("owner@example.com"))
        XCTAssertTrue(kept.contains("second@example.com"))
        XCTAssertTrue(kept.isSuperset(of: (0..<298).map { "p\($0)@example.org" }))
        XCTAssertFalse(kept.contains("p298@example.org"))
        XCTAssertFalse(kept.contains { $0.hasSuffix("@news.example.com") })
        XCTAssertEqual(all.first { $0.address == "p0@example.org" }?.uses, 400)
    }

    /// An entry the book has keeps its name, or takes the fill's if it has
    /// none, and the larger count and the later date: a letter sent from
    /// the app is counted once.
    func testAnEntryKeepsItsNameAndTakesTheLargerCountAndTheLaterDate() {
        book.used(address: "sam@example.com", name: "Sam Example")
        book.used(address: "sam@example.com")
        book.note(address: "carlo@example.org")
        let before = book.snapshot().first { $0.address == "sam@example.com" }!
        book.fill(with: [entry("sam@example.com", name: "Sammy", uses: 1, at: days(400)),
                         entry("carlo@example.org", name: "Carlo", uses: 5, at: days(3))],
                  besides: mine)
        let sam = book.snapshot().first { $0.address == "sam@example.com" }!
        XCTAssertEqual(sam.name, "Sam Example")
        XCTAssertEqual(sam.uses, 2)
        XCTAssertEqual(sam.lastSeen, before.lastSeen)
        let carlo = book.snapshot().first { $0.address == "carlo@example.org" }!
        XCTAssertEqual(carlo.name, "Carlo")
        XCTAssertEqual(carlo.uses, 5)
        XCTAssertGreaterThan(carlo.lastSeen, days(3), "the later of the two")
    }

    /// Filled, the book is all people written to and his own; his own,
    /// noted at launch and seldom chosen, stay through every address noted
    /// after, each of which, only seen, is the one to go.
    func testHisOwnAreNeverPushedOutAfterTheFill() {
        book.keepOwn(mine)
        book.noteOwn(address: "owner@example.com", name: "Owner")
        book.note(address: "second@example.com")
        book.fill(with: (0..<400).map { entry("p\($0)@example.org", uses: 1, at: days(Double($0))) },
                  besides: mine)
        for n in 0..<50 { book.note(address: "news\(n)@example.com") }
        let kept = Set(book.snapshot().map(\.address))
        XCTAssertEqual(kept.count, RecipientBook.capacity)
        XCTAssertTrue(kept.contains("owner@example.com"))
        XCTAssertTrue(kept.contains("second@example.com"))
        XCTAssertTrue(kept.isSuperset(of: (0..<298).map { "p\($0)@example.org" }))
        XCTAssertFalse(kept.contains { $0.hasPrefix("news") })
    }

    /// His own address first among those that start alike after the fill:
    /// his letters to himself are not counted, so each of his own in the
    /// book is counted one more than anyone taken in, and Owen, written to
    /// forty times, whose name starts as his does, comes below it, as does
    /// a correspondent whose address starts as his second one's.
    func testHisOwnComeFirstAmongThoseThatStartAlikeAfterTheFill() {
        book.keepOwn(mine)
        book.noteOwn(address: "owner@example.com", name: "Sam Owner")
        book.used(address: "owner@example.com")
        book.note(address: "second@example.com")
        book.used(address: "carlo@example.org")
        book.fill(with: [entry("owen@example.org", name: "Owen Example", uses: 40, at: days(1)),
                         entry("secretary@example.org", uses: 3, at: days(2)),
                         entry("carlo@example.org", uses: 1, at: days(3))],
                  besides: mine)
        XCTAssertEqual(book.suggestions(for: "ow").map(\.address), ["owner@example.com", "owen@example.org"])
        XCTAssertEqual(book.suggestions(for: "sam").map(\.address), ["owner@example.com"])
        XCTAssertEqual(book.suggestions(for: "sec").map(\.address),
                       ["second@example.com", "secretary@example.org"])
        XCTAssertEqual(book.snapshot().first { $0.address == "owner@example.com" }?.uses, 41)
        XCTAssertEqual(book.snapshot().first { $0.address == "owen@example.org" }?.uses, 40)
        XCTAssertEqual(book.addresses(startingWith: "ow", besides: mine), ["owen@example.org"],
                       "search still never asks for his own")

        // Counted more already, his own keep their count; a fill that
        // takes nobody changes nothing.
        let other = RecipientBook(defaults: defaults)
        other.removeAll()
        other.keepOwn(mine)
        for _ in 0..<60 { other.used(address: "owner@example.com") }
        other.note(address: "second@example.com")
        other.fill(with: [], besides: mine)
        XCTAssertEqual(other.snapshot().first { $0.address == "second@example.com" }?.uses, 0)
        other.fill(with: [entry("owen@example.org", uses: 40, at: days(1))], besides: mine)
        XCTAssertEqual(other.snapshot().first { $0.address == "owner@example.com" }?.uses, 60)
        XCTAssertEqual(other.snapshot().first { $0.address == "second@example.com" }?.uses, 41)
    }

    /// The same for a book told his addresses as a repository is made,
    /// before any fill: a book full of people chosen keeps them.
    func testABookToldHisAddressesNeverEvictsThem() {
        let other = RecipientBook(defaults: defaults)
        other.removeAll()
        other.keepOwn(mine)
        other.noteOwn(address: "owner@example.com", name: "Owner")
        for n in 0..<320 { other.used(address: "p\(n)@example.org") }
        let kept = Set(other.snapshot().map(\.address))
        XCTAssertEqual(kept.count, RecipientBook.capacity)
        XCTAssertTrue(kept.contains("owner@example.com"))
    }

    /// Once per account: marked by address in any case, kept with the book
    /// across launches, another account not marked.
    func testTheFillIsMarkedOncePerAccount() {
        XCTAssertFalse(book.filledFromSent(account: "owner@example.com"))
        book.markFilledFromSent(account: " Owner@Example.com ")
        book.markFilledFromSent(account: "owner@example.com")
        XCTAssertTrue(book.filledFromSent(account: "owner@example.com"))
        XCTAssertFalse(book.filledFromSent(account: "other@example.com"))
        XCTAssertTrue(RecipientBook(defaults: defaults).filledFromSent(account: "OWNER@example.com"))
        XCTAssertEqual(defaults.stringArray(forKey: "blackmail.recipients.filledFromSent"),
                       ["owner@example.com"])
    }

    /// Of Sent Mail's letters since the day, the newest 2,000.
    func testTheNewestTwoThousandAreRead() {
        XCTAssertEqual(IMAPMailRepository.bookFillLetters, 2_000)
        XCTAssertEqual(IMAPMailRepository.bookFillMonths, 6)
        let uids = (1...2_500).map { UInt32($0 * 2) }
        let read = IMAPMailRepository.lettersForTheBook(uids.reversed())
        XCTAssertEqual(read.count, 2_000)
        XCTAssertEqual(read.first, 1_002)
        XCTAssertEqual(read.last, 5_000)
        XCTAssertEqual(IMAPMailRepository.lettersForTheBook([7, 3]), [3, 7])
    }

    // MARK: - Over the server

    private func makeRepository(others: [String] = ["second@example.com"],
                                transport: MailTransportFactory? = nil) -> IMAPMailRepository {
        var saved = server.account
        saved.otherAddresses = others
        return IMAPMailRepository(account: server.account, password: server.password,
                                  transport: transport ?? server.transportFactory,
                                  saved: { saved }, recipients: book,
                                  now: { Self.now }, calendar: utc)
    }

    private func sent(to: [Server.Address], cc: [Server.Address] = [], daysAgo: Double,
                      read: Bool = true, n: Int) -> UInt32 {
        let uids = server.deliver(Server.Letter(from: Server.owner, to: to, cc: cc,
                                                subject: "B-155 \(n)", date: days(daysAgo),
                                                text: "A note.\r\n", flags: read ? ["\\Seen"] : [],
                                                messageID: "<b155-\(n)@example.com>"),
                                  to: [Server.sent, Server.allMail])
        return uids[Server.sent] ?? 0
    }

    private func notes(saying text: String) -> Int {
        Diagnostics.entries.filter { $0.direction == .note && $0.text == text }.count
    }

    /// After the Inbox's first page: one SEARCH SINCE six months ago in
    /// Sent Mail and one FETCH of the envelopes alone, nothing else; no
    /// letter marked, an unread one left unread. The people written to in
    /// the six months are offered as he types, Carlo's eight letters first;
    /// one written to seven months ago is not, nor his own second address
    /// nor anyone of a letter only to it.
    func testTheFillIsASearchAndTheEnvelopesInSentMailAndNothingElse() async throws {
        let quentin = Server.Address(name: "Quentin Fill", address: "quentin.b155@example.com")
        sent(to: [quentin], daysAgo: 120, read: false, n: 1)
        sent(to: [Server.Address(name: nil, address: "second@example.com")], daysAgo: 30, n: 2)
        sent(to: [Server.owner, Server.sam], daysAgo: 20, n: 3)
        sent(to: [Server.Address(name: "Old Friend", address: "old.b155@example.com")],
             daysAgo: 215, n: 4)
        let unread = sent(to: [quentin], daysAgo: 60, read: false, n: 5)
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        let said = notes(saying: "BOOK-FILL letters=12 people=3")

        let filled = await repository.fillBookFromSent()
        XCTAssertEqual(filled, .filled(letters: 12, people: 3))
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(server.log[0].command, "SELECT \"[Gmail]/Sent Mail\"")
        XCTAssertEqual(server.log[1].command, "UID SEARCH SINCE \"21-Mar-2026\"")
        XCTAssertTrue(server.log[2].command.hasSuffix(" (UID INTERNALDATE ENVELOPE)"), server.log[2].command)
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        XCTAssertFalse(server.log.contains { $0.command.contains("BODY") || $0.command.contains("FLAGS") })
        XCTAssertEqual(server.flags(uid: unread, in: Server.sent), [])
        XCTAssertEqual(notes(saying: "BOOK-FILL letters=12 people=3"), said + 1)

        XCTAssertEqual(book.suggestions(for: "quen").map(\.address), ["quentin.b155@example.com"])
        XCTAssertEqual(book.suggestions(for: "quen").first?.name, "Quentin Fill")
        XCTAssertEqual(book.suggestions(for: "quen").first?.uses, 2)
        XCTAssertEqual(book.suggestions(for: "carl").first?.uses, 8)
        XCTAssertEqual(book.suggestions(for: "sam").map(\.address), ["sam@example.com"])
        XCTAssertEqual(book.suggestions(for: "old").map(\.address), [])
        XCTAssertEqual(book.suggestions(for: "second").map(\.address), [], "his own, not taken in")
        XCTAssertTrue(book.filledFromSent(account: server.account.address))
    }

    /// Once for the account: asked again, by this repository or by one
    /// made for a new password, nothing is sent.
    func testASecondFillSendsNothing() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let first = await repository.fillBookFromSent()
        XCTAssertEqual(first, .filled(letters: 8, people: 1))
        server.clearLog()
        let again = await repository.fillBookFromSent()
        XCTAssertEqual(again, .filledBefore)
        let next = makeRepository()
        _ = try await next.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        let afresh = await next.fillBookFromSent()
        XCTAssertEqual(afresh, .filledBefore)
        XCTAssertEqual(server.log.map(\.command), [])
    }

    /// With no connection up, or before the folders are listed, nothing is
    /// sent and no connection is made; nothing is marked, so the next
    /// launch tries again.
    func testNothingIsSentWithoutAConnection() async throws {
        let cold = makeRepository()
        let none = await cold.fillBookFromSent()
        XCTAssertEqual(none, .notNow)
        XCTAssertEqual(server.connectionsOpened, 0)
        XCTAssertEqual(server.log.map(\.command), [])
        XCTAssertFalse(book.filledFromSent(account: server.account.address))
    }

    /// A LIST that names no `\Sent` sends nothing: never All Mail, which
    /// holds the letters to him too.
    func testNoSentMailSendsNothingAndNeverAllMail() async throws {
        server.unlistedMailboxes = [Server.sent]
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        let none = await repository.fillBookFromSent()
        XCTAssertEqual(none, .notNow)
        XCTAssertEqual(server.log.map(\.command), [])
        XCTAssertFalse(book.filledFromSent(account: server.account.address))
    }

    /// The connection lost under it: nothing filled, no reconnect, nothing
    /// marked, and nothing sent if it is asked again with none; the next
    /// launch's fills.
    func testALostConnectionFillsNothingAndMarksNothing() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        server.holdReplies(to: "UID SEARCH")
        let fill = Task { await repository.fillBookFromSent() }
        try await until { await self.server.heldReplies(to: "UID SEARCH") == 1 }
        await server.resetConnections()
        let lost = await fill.value
        server.stopHolding("UID SEARCH")

        XCTAssertEqual(lost, .notNow)
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH"])
        XCTAssertEqual(server.connectionsOpened, 1, "no reconnect")
        XCTAssertFalse(book.filledFromSent(account: server.account.address))
        XCTAssertEqual(book.suggestions(for: "carl").first?.uses ?? 0, 0)
        // And with the connection gone, asked again, nothing is sent and
        // none is made for it.
        let again = await repository.fillBookFromSent()
        XCTAssertEqual(again, .notNow)
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH"])
        XCTAssertEqual(server.connectionsOpened, 1)

        let next = makeRepository()
        _ = try await next.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let filled = await next.fillBookFromSent()
        XCTAssertEqual(filled, .filled(letters: 8, people: 1))
    }

    /// All or nothing: of three holds, the second refused, nothing is
    /// filled and nothing marked, and the third is not asked for; asked
    /// again with the server answering, all of it is taken.
    func testAHoldRefusedFillsNothingAndMarksNothing() async throws {
        for n in 0..<242 {
            sent(to: [Server.Address(name: nil, address: "p\(n)@example.org")],
                 daysAgo: 1 + Double(n) / 10, n: 100 + n)
        }
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        server.holdReplies(to: "UID FETCH")
        let fill = Task { await repository.fillBookFromSent() }
        try await until { await self.server.heldReplies(to: "UID FETCH") == 1 }
        server.refusedVerbs = ["UID FETCH"]
        await server.releaseReplies(to: "UID FETCH")
        let refused = await fill.value

        XCTAssertEqual(refused, .notNow)
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH", "UID FETCH", "UID FETCH"])
        XCTAssertEqual(server.log.map(\.status), ["OK", "OK", "OK", "NO"])
        XCTAssertFalse(book.filledFromSent(account: server.account.address))
        XCTAssertEqual(book.suggestions(for: "p0@").map(\.address), [])
        XCTAssertEqual(book.suggestions(for: "carl").first?.uses ?? 0, 0)

        server.refusedVerbs = []
        let filled = await repository.fillBookFromSent()
        XCTAssertEqual(filled, .filled(letters: 250, people: 243))
        XCTAssertTrue(book.filledFromSent(account: server.account.address))
    }

    /// Letters found and none of their envelopes read, a FETCH answered OK
    /// with nothing the app can use: not marked, so the next try reads them.
    func testNoEnvelopeReadMarksNothing() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        server.envelopeless = Set(1...1_000)
        let none = await repository.fillBookFromSent()
        XCTAssertEqual(none, .notNow)
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH", "UID FETCH"])
        XCTAssertFalse(book.filledFromSent(account: server.account.address))

        server.envelopeless = []
        let filled = await repository.fillBookFromSent()
        XCTAssertEqual(filled, .filled(letters: 8, people: 1))
    }

    /// Two asked for at once: one SEARCH and one FETCH, the other not
    /// begun beside it.
    func testTwoAtOnceReadOnce() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        async let first = repository.fillBookFromSent()
        async let second = repository.fillBookFromSent()
        let both = await [first, second]
        XCTAssertEqual(both.filter { $0 == .filled(letters: 8, people: 1) }.count, 1, "\(both)")
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH", "UID FETCH"])
    }

    /// The envelopes a hundred letters a hold: 250 letters, three FETCHes,
    /// each its own hold, so a letter he taps waits for one at most.
    func testTheEnvelopesGoAHundredAHold() async throws {
        for n in 0..<242 {
            sent(to: [Server.Address(name: nil, address: "p\(n)@example.org")],
                 daysAgo: 1 + Double(n) / 10, n: 100 + n)
        }
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        let filled = await repository.fillBookFromSent()
        XCTAssertEqual(filled, .filled(letters: 250, people: 243))
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH", "UID FETCH", "UID FETCH", "UID FETCH"])
        XCTAssertEqual(IMAPClient.envelopesPerHold, 100)
    }

    /// What the app wires: the fill asked for once the Inbox's first page
    /// has been tried, after the counts are let go and before the watch
    /// starts, and not waited for;
    /// each repository telling the book his addresses as it is made, and
    /// Settings' Save; the fill's flag set before its first await; the
    /// envelopes in the background line, with no flags and no body, any
    /// hold refused throwing.
    func testTheFillIsAskedForAfterTheFirstPageAndWaitedForByNothing() throws {
        let ios = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: ios.appendingPathComponent(path), encoding: .utf8)
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: " ")
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .joined(separator: " ")
        }
        func inOrder(_ steps: [String], in code: String, line: UInt = #line) {
            var from = code.startIndex
            for step in steps {
                guard let found = code.range(of: step, range: from..<code.endIndex) else {
                    return XCTFail("missing, or out of order: \(step)", line: line)
                }
                from = found.upperBound
            }
        }
        let root = try source("Sources/Blackmail/UI/RootViewController.swift")
        inOrder(["list.onFirstLoadFinished = { [weak self] came in",
                 "self?.mailboxList.releaseSweeps(firstPageCame: came)",
                 "self?.warnOfExpiryIfDue()",
                 "self?.firstPageTried = true",
                 "if let repository = self?.repository {",
                 "Task { _ = await repository.fillBookFromSent() }",
                 "self?.watch.start()",
                 "SafeStart.app.firstPageTried("], in: root)
        XCTAssertEqual(root.components(separatedBy: "fillBookFromSent()").count - 1, 1)

        let repository = try source("Sources/Blackmail/Mail/IMAPMailRepository.swift")
        inOrder(["recipients.noteOwn(address: account.address, name: account.displayName)",
                 "recipients.keepOwn(OwnAddresses(account: account.withSettings(of: saved())))"],
                in: repository)
        inOrder(["func fillBookFromSent() async -> BookFill {",
                 "guard !recipients.filledFromSent(account: key) else { return .filledBefore }",
                 "guard !retired, !fillingBook, let sent = roleNames[.sent] else { return .notNow }",
                 "fillingBook = true",
                 "guard await imap.isConnected else { return .notNow }",
                 "let found = try await client.search(",
                 "let letters = try await client.fetchEnvelopes(",
                 "guard asked.isEmpty || letters.contains(where: { $0.envelope != nil }) else {",
                 "recipients.flush()",
                 "recipients.markFilledFromSent(account: key)"], in: repository)

        let client = try source("Sources/Blackmail/IMAP/IMAPClient.swift")
        inOrder(["func fetchEnvelopes(uids: [UInt32], in mailbox: String, validity: UInt32) async throws",
                 "try Task.checkCancellation()",
                 "try await inMailbox(mailbox, validity: validity, .background) {",
                 "\"UID FETCH \\(chunk) \\(Self.envelopeItems)\"",
                 "guard let answer else { throw MailError.cannotConnect }"], in: client)

        // Settings' Save tells the book his addresses too, so one he has
        // just added is never pushed out before the next launch.
        let store = try source("Sources/Blackmail/Mail/CredentialStore.swift")
        inOrder(["static func saveAccountOnly(_ account: MailAccount) throws {",
                 "RecipientBook.shared.noteOwn(address: clean.address, name: clean.displayName)",
                 "RecipientBook.shared.keepOwn(OwnAddresses(account: clean))"], in: store)
        XCTAssertEqual(IMAPClient.envelopeItems, "(UID INTERNALDATE ENVELOPE)")
    }

    /// Waits, a millisecond at a time and never for more than two seconds,
    /// until `condition` holds.
    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<2_000 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out", file: file, line: line)
    }
}
