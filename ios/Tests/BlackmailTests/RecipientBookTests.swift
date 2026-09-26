import XCTest
@testable import Blackmail

/// Tests for the addresses the composer offers instead of making him type.
///
/// The requirement behind them is one fact: he sends
/// mail to himself constantly, and he is ninety. So the cases that matter
/// are the ones where the obvious answer fails to reach the first row, and
/// the ones where the list offers something he never wrote to.
final class RecipientBookTests: XCTestCase {

    private func entry(_ address: String, name: String? = nil,
                       uses: Int = 0, daysAgo: Int = 0) -> KnownRecipient {
        KnownRecipient(address: address, name: name, uses: uses,
                       lastSeen: Date(timeIntervalSince1970: 1_700_000_000
                                      - Double(daysAgo) * 86_400))
    }

    private func rank(_ all: [KnownRecipient], _ q: String,
                      limit: Int = 4) -> [String] {
        RecipientBook.rank(all, matching: q, limit: limit).map(\.address)
    }

    // MARK: - Matching

    func testANameMatchesBeforeAnAddressThatMerelyContainsTheLetters() {
        // Typing "car" must offer Carlo, not everyone at oscarexample.com.
        let all = [entry("info@oscarexample.com"),
                   entry("carlo@example.org", name: "Carlo Example")]
        XCTAssertEqual(rank(all, "car").first, "carlo@example.org")
    }

    func testASurnameIsFoundAndNotJustTheFirstName() {
        // People search for the name they think of, which is often the
        // second word.
        let all = [entry("m@example.com", name: "Margaret Ellis")]
        XCTAssertEqual(rank(all, "ellis"), ["m@example.com"])
    }

    func testTheLocalPartMatchesBeforeTheDomain() {
        let all = [entry("someone@carlo-removals.com"),
                   entry("carlo@example.org")]
        XCTAssertEqual(rank(all, "carlo").first, "carlo@example.org")
    }

    func testMatchingIgnoresCaseInBothDirections() {
        let all = [entry("carlo@example.org", name: "Carlo Example")]
        XCTAssertEqual(rank(all, "CARLO"), ["carlo@example.org"])
        XCTAssertEqual(rank(all, "example"), ["carlo@example.org"])
    }

    func testSomethingMatchingNothingOffersNothing() {
        // An empty list hides the suggestions view. Offering a wrong
        // address to a 90-year-old is worse than offering none.
        XCTAssertTrue(rank([entry("a@b.com")], "zzz").isEmpty)
    }

    // MARK: - Ranking

    func testAnAddressHeHasWRITTENToOutranksOneHeHasOnlySeen() {
        // The distinction the whole ordering rests on: a newsletter sender
        // seen a hundred times must not outrank the man he replies to.
        let all = [entry("newsletter@example.com", name: "Aaa News", daysAgo: 0),
                   entry("zzz@example.com", name: "Zzz Person", uses: 3, daysAgo: 30)]
        XCTAssertEqual(rank(all, "").first, "zzz@example.com")
    }

    func testAmongEquallyUsedAddressesTheMoreRecentComesFirst() {
        let all = [entry("old@example.com", uses: 2, daysAgo: 100),
                   entry("new@example.com", uses: 2, daysAgo: 1)]
        XCTAssertEqual(rank(all, "").first, "new@example.com")
    }

    func testTheOrderIsTotalSoTheListDoesNotShuffleBetweenKeystrokes() {
        // Identical on every ranking key except the address. Without the
        // final tie-break the two could swap places as he types, and a row
        // that moves under a finger is a letter sent to the wrong person.
        let all = [entry("b@example.com", uses: 1, daysAgo: 5),
                   entry("a@example.com", uses: 1, daysAgo: 5)]
        XCTAssertEqual(rank(all, ""), ["a@example.com", "b@example.com"])
        XCTAssertEqual(rank(all, ""), rank(all, ""))
    }

    func testAnEmptyQueryStillOffersHisMostUsedAddresses() {
        // This is what makes writing to himself one tap rather than
        // a whole address: tapping To with nothing typed already
        // offers him.
        let all = [entry("carlo@example.org", name: "Carlo", uses: 9),
                   entry("someone@example.com", uses: 1)]
        XCTAssertEqual(rank(all, "").first, "carlo@example.org")
    }

    func testNoMoreThanTheLimitIsEverOffered() {
        let all = (0..<20).map { entry("p\($0)@example.com", uses: $0) }
        XCTAssertEqual(rank(all, "", limit: 4).count, 4)
    }

    // MARK: - Recording

    func testRecordingIgnoresThingsThatAreNotAddresses() {
        let book = RecipientBook(defaults: UserDefaults(suiteName: #function)!)
        book.removeAll()
        book.note(address: "not an address")
        book.note(address: "")
        book.note(address: "  ")
        XCTAssertTrue(book.suggestions(for: "").isEmpty)
    }

    func testAnAddressIsStoredOnceHoweverOftenItIsSeen() {
        let book = RecipientBook(defaults: UserDefaults(suiteName: #function)!)
        book.removeAll()
        book.note(address: "Carlo@Example.org")
        book.note(address: "carlo@example.org")
        XCTAssertEqual(book.suggestions(for: "").count, 1,
                       "case must not create a second entry")
    }

    func testANameLearnedLaterIsKeptAndNotLostToABareSighting() {
        // Senders arrive bare in one message and named in the next.
        let book = RecipientBook(defaults: UserDefaults(suiteName: #function)!)
        book.removeAll()
        book.note(address: "m@example.com", name: "Margaret Ellis")
        book.note(address: "m@example.com")
        XCTAssertEqual(book.suggestions(for: "").first?.name, "Margaret Ellis")
    }

    func testChoosingAnAddressRanksItAboveOnesOnlySeen() {
        let book = RecipientBook(defaults: UserDefaults(suiteName: #function)!)
        book.removeAll()
        book.note(address: "seen@example.com")
        book.used(address: "written@example.com")
        XCTAssertEqual(book.suggestions(for: "").first?.address, "written@example.com")
    }

    func testTheBookSurvivesBeingReopened() {
        let suite = UserDefaults(suiteName: #function)!
        let book = RecipientBook(defaults: suite)
        book.removeAll()
        book.used(address: "carlo@example.org", name: "Carlo")

        let reopened = RecipientBook(defaults: suite)
        XCTAssertEqual(reopened.suggestions(for: "carlo").first?.address,
                       "carlo@example.org")
    }

    // MARK: - Filling the field

    func testChoosingAnAddressReplacesOnlyTheHalfTypedOne() {
        XCTAssertEqual(
            MailFormat.replacingRecipientToken(in: "car", with: "carlo@example.org"),
            "carlo@example.org, ")
    }

    func testChoosingASecondAddressKeepsTheFirst() {
        XCTAssertEqual(
            MailFormat.replacingRecipientToken(in: "a@b.com, mar",
                                               with: "margaret@example.com"),
            "a@b.com, margaret@example.com, ")
    }

    func testTheSeparatorIsInsertedForHimBecauseHeCannotTypeOne() {
        // The email keyboard has no comma key, so this trailing ", " is
        // the ONLY route to a second recipient.
        let filled = MailFormat.replacingRecipientToken(in: "", with: "a@b.com")
        XCTAssertTrue(filled.hasSuffix(", "), filled)
        XCTAssertEqual(MailFormat.currentRecipientToken(in: filled), "",
                       "and the next address starts from empty")
    }

    func testTheTokenIsWhatIsAfterTheLastCommaOnly() {
        XCTAssertEqual(MailFormat.currentRecipientToken(in: "a@b.com, mar"), "mar")
        XCTAssertEqual(MailFormat.currentRecipientToken(in: "mar"), "mar")
        XCTAssertEqual(MailFormat.currentRecipientToken(in: ""), "")
    }
}
