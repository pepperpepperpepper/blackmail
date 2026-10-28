import XCTest
@testable import Blackmail

/// The people whose letters he has only received, in the address fields'
/// list (B-177), as Mail offers them under "SIRI FOUND IN APPS": by name,
/// after the people he has written to and his Contacts, never by their
/// address. Mail, given a received letter from Zqxa Rmfix at
/// zqxa.b162@example.net, offered "Zqxa Rmfix" for "zqx" and nothing for
/// "zqxa.b". The book keeps them apart from the 300 he has written to,
/// with a bound of their own, so a book filled from his Sent Mail no
/// longer pushes each of them out as it is noted.
final class SeenSendersTests: XCTestCase {

    private static let suite = "SeenSendersTests"

    private var defaults: UserDefaults!
    private var book: RecipientBook!

    private let mine = OwnAddresses(["owner@example.com"])
    private let when = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        book.removeAll()
        book.keepOwn(mine)
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        defaults = nil
        book = nil
        super.tearDown()
    }

    /// The book as the comparison found it: filled from Sent Mail to the
    /// 300 with people he wrote to.
    private func fillToTheBrim() {
        book.noteOwn(address: "owner@example.com", name: "Owner")
        let people = (0..<400).map {
            KnownRecipient(address: String(format: "p%03d@example.org", $0), name: "Person \($0)",
                           uses: 1 + $0 % 7, lastSeen: when.addingTimeInterval(Double(-$0) * 60))
        }
        book.fill(with: people, besides: mine)
    }

    private func offered(_ typed: String, cards: [ContactCard] = []) -> [String] {
        ComposeForm.suggestions(book.snapshot(), contacts: cards, field: typed, after: .typed)
            .map(\.address)
    }

    // MARK: - Kept

    /// A sender noted from a listed letter stays in a book the fill has
    /// filled, and is offered by name; until B-177 it went as it came.
    func testASenderNotedAfterTheFillIsKeptAndOfferedByName() {
        fillToTheBrim()
        book.note(address: "zqxa.b162@example.net", name: "Zqxa Rmfix")
        XCTAssertTrue(book.snapshot().contains { $0.address == "zqxa.b162@example.net" })
        let rows = ComposeForm.suggestions(book.snapshot(), field: "zqx", after: .typed)
        XCTAssertEqual(rows.map(\.address), ["zqxa.b162@example.net"])
        XCTAssertEqual(rows.map(\.display), ["Zqxa Rmfix"])
        XCTAssertEqual(offered("Rmf"), ["zqxa.b162@example.net"], "the last name too")
        XCTAssertEqual(offered("zqxa r"), ["zqxa.b162@example.net"], "the name typed on")
    }

    /// Written out and read again, it is still there.
    func testTheSeenSurviveAReopening() {
        fillToTheBrim()
        book.note(address: "zqxa.b162@example.net", name: "Zqxa Rmfix")
        book.flush()
        let again = RecipientBook(defaults: defaults)
        XCTAssertTrue(again.snapshot().contains { $0.address == "zqxa.b162@example.net" })
        XCTAssertEqual(again.snapshot().filter { $0.uses > 0 }.count, RecipientBook.capacity)
    }

    /// Their own bound: past it the oldest seen goes, never anyone he has
    /// written to, nor his own.
    func testTheSeenHaveABoundOfTheirOwnTheNewestKept() {
        fillToTheBrim()
        let writtenTo = Set(book.snapshot().map(\.address))
        let count = RecipientBook.seenCapacity + 20
        for n in 0..<count {
            book.note(address: String(format: "s%04d@news.example.com", n), name: "Seen \(n)")
        }
        let all = book.snapshot()
        let kept = Set(all.map(\.address))
        XCTAssertEqual(all.count, RecipientBook.capacity + RecipientBook.seenCapacity)
        XCTAssertTrue(kept.isSuperset(of: writtenTo))
        XCTAssertTrue(kept.contains("owner@example.com"))
        XCTAssertTrue(kept.isSuperset(of: (20..<count).map { String(format: "s%04d@news.example.com", $0) }))
        XCTAssertTrue(kept.isDisjoint(with: (0..<20).map { String(format: "s%04d@news.example.com", $0) }))
    }

    /// People he writes to beyond the 300 still push out the oldest of
    /// them, and none of the seen.
    func testTheThreeHundredStayTheirsAlone() {
        book.noteOwn(address: "owner@example.com", name: "Owner")
        for n in 0..<10 { book.note(address: "seen\(n)@example.net", name: "Seen \(n)") }
        for n in 0..<(RecipientBook.capacity + 5) {
            book.used(address: String(format: "w%03d@example.org", n))
        }
        let all = book.snapshot()
        XCTAssertEqual(all.filter { $0.uses > 0 || mine.contains($0.address) }.count, RecipientBook.capacity)
        XCTAssertEqual(all.filter { $0.address.hasPrefix("seen") }.count, 10)
        XCTAssertTrue(all.contains { $0.address == "owner@example.com" })
    }

    // MARK: - Offered by name only

    /// Not by the address: "zqxa.b" offers nothing, nor "zqxa.b162",
    /// nor a part within; a seen address with no name, or an address for
    /// a name, is not offered at all.
    func testNeverByTheAddress() {
        book.note(address: "zqxa.b162@example.net", name: "Zqxa Rmfix")
        book.note(address: "bare@example.net")
        book.note(address: "named@example.net", name: "named@example.net")
        for typed in ["zqxa.b", "zqxa.b162", "b162", "xa", "bare", "named", "example"] {
            XCTAssertEqual(offered(typed), [], typed)
        }
        XCTAssertEqual(offered("zqxa"), ["zqxa.b162@example.net"])
    }

    /// After the people he has written to and his Contacts, as Mail's
    /// "SIRI FOUND IN APPS" comes after its Recents.
    func testAfterThePeopleWrittenToAndHisContacts() {
        book.note(address: "zqxa.b162@example.net", name: "Zqxa Rmfix")
        book.used(address: "zqxo@example.org", name: "Zqxo Writ")
        let cards = [ContactCard(name: "Zqxi Card", givenName: "Zqxi", familyName: "Card",
                                 addresses: ["card@example.com"])]
        XCTAssertEqual(offered("zqx", cards: cards),
                       ["zqxo@example.org", "card@example.com", "zqxa.b162@example.net"])
    }

    /// His own addresses are never only seen: the account's, noted under
    /// his name, and his second, noted from a list, are found by the start
    /// of the address as the people he writes to are, before any fill.
    func testHisOwnAreNeverOnlySeen() {
        book.keepOwn(OwnAddresses(["owner@example.com", "second@example.com"]))
        book.noteOwn(address: "owner@example.com", name: "Carlo")
        book.note(address: "second@example.com")
        XCTAssertEqual(offered("own"), ["owner@example.com"])
        XCTAssertEqual(offered("sec"), ["second@example.com"])
        XCTAssertEqual(book.snapshot().map(\.uses), [1, 1])
    }

    /// Someone he has written to is found by the start of the address as
    /// ever, and within it (B-017): only the seen are by name alone.
    func testThePeopleWrittenToAreFoundAsEver() {
        book.used(address: "zqxa.b162@example.net", name: "Zqxa Rmfix")
        XCTAssertEqual(offered("zqxa.b"), ["zqxa.b162@example.net"])
        XCTAssertEqual(offered("b162"), ["zqxa.b162@example.net"])
    }
}
