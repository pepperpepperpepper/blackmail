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
        // The book read whole, his most used first, as the tests here
        // read it. It no longer reaches the screen: since B-073 an
        // address field offers nothing until he types, as Mail's does,
        // and `ComposeLikeMailTests` holds that.
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

    /// The repository notes addresses on its own actor as a page of rows is
    /// built, while the composer ranks them on the main thread at every
    /// keystroke. With nothing between the two, a read that met a write
    /// crashed the app, every run of this.
    ///
    /// The writer mostly updates, and now and then brings in a newcomer,
    /// which the full book makes room for by evicting; a flush now and
    /// then copies the entries too.
    func testNotingOnOneThreadWhileAnotherAsksForSuggestionsIsSafe() {
        let suite = UserDefaults(suiteName: #function)!
        let book = RecipientBook(defaults: suite)
        book.removeAll()

        let written = Flag()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            for i in 0..<5_000 {
                let n = i % 50 == 0 ? 1_000 + i : i % 290
                book.note(address: "person\(n)@example.com", name: "Person \(n)")
                if i % 2_000 == 0 { book.flush() }
            }
            written.set()
            done.signal()
        }
        var asked = 0
        while !written.isSet {
            _ = book.suggestions(for: "")
            asked += 1
        }
        done.wait()

        XCTAssertGreaterThan(asked, 0)
        XCTAssertEqual(book.suggestions(for: "", limit: 1_000).count, RecipientBook.capacity)
        suite.removePersistentDomain(forName: #function)
    }

    /// The repository flushes at the end of every page on its own actor,
    /// while the app flushes on the main thread as it goes into the
    /// background and after every letter sent. A flush copies the entries
    /// and clears the dirty flag while another thread may be noting, so
    /// both are under the same lock as the note. Without it this crashed
    /// thirty runs out of thirty.
    ///
    /// Ten rounds, each from an empty book, because a copy that meets a
    /// write fails soonest while the dictionary is still growing, as it
    /// does on a first launch. The writer never brings in a newcomer past
    /// the book's capacity: the eviction sorts the whole book and would
    /// slow it to a crawl. The writes are counted and dropped, so the
    /// flushes come as fast as they can be encoded.
    func testFlushingOnOneThreadWhileAnotherNotesIsSafe() {
        let defaults = DiscardingDefaults(suiteName: #function)!
        let book = RecipientBook(defaults: defaults)

        let written = Flag()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            for _ in 0..<10 {
                book.removeAll()
                for i in 0..<500 {
                    let n = i % 290
                    book.note(address: "person\(n)@example.com", name: "Person \(n)")
                }
            }
            written.set()
            done.signal()
        }
        var flushes = 0
        while !written.isSet {
            book.flush()
            flushes += 1
        }
        done.wait()
        book.flush()

        XCTAssertGreaterThan(flushes, 0)
        XCTAssertGreaterThan(defaults.writes.value, 0)
        XCTAssertEqual(book.suggestions(for: "", limit: 1_000).count, 290)
    }

    /// Two flushes at once, the repository's at the end of a page and the
    /// app's going into the background, write in the order they copied the
    /// book. The first has copied it without Jane and is still writing
    /// when she is noted and the second starts; the second, which has her,
    /// must be the one left on disk.
    ///
    /// The second waits its turn for at most 20 ms here, long enough to
    /// finish first if nothing made it wait, and in the app for as long as
    /// the first takes.
    func testTwoFlushesAtOnceLeaveTheLaterCopyOnDisk() {
        let suite = "RecipientBookTests.twoFlushes"
        let defaults = GatedDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let book = RecipientBook(defaults: defaults)
        book.note(address: "sam@example.com", name: "Sam Example")

        let firstDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            book.flush()
            firstDone.signal()
        }
        XCTAssertEqual(defaults.firstWriteStarted.wait(timeout: .now() + 5), .success)

        book.note(address: "jane@example.com", name: "Jane Example")
        let secondDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            book.flush()
            secondDone.signal()
        }
        let secondFinishedFirst = secondDone.wait(timeout: .now() + .milliseconds(20)) == .success
        defaults.firstWriteMayFinish.signal()
        XCTAssertEqual(firstDone.wait(timeout: .now() + 5), .success)
        if !secondFinishedFirst {
            XCTAssertEqual(secondDone.wait(timeout: .now() + 5), .success)
        }

        XCTAssertFalse(secondFinishedFirst, "the second flush did not wait for the first")
        XCTAssertEqual(Set(RecipientBook(defaults: defaults).suggestions(for: "").map(\.address)),
                       ["jane@example.com", "sam@example.com"])
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

    /// A field as he leaves it, which the suggestions leave with a comma
    /// and a space after the last address: the addresses, and no blank.
    func testAFieldIsItsAddresses() {
        XCTAssertEqual(MailFormat.addresses(in: "a@b.com, Carlo <c@d.org>, "),
                       ["a@b.com", "Carlo <c@d.org>"])
        XCTAssertEqual(MailFormat.addresses(in: " , "), [])
    }

    func testTheTokenIsWhatIsAfterTheLastCommaOnly() {
        XCTAssertEqual(MailFormat.currentRecipientToken(in: "a@b.com, mar"), "mar")
        XCTAssertEqual(MailFormat.currentRecipientToken(in: "mar"), "mar")
        XCTAssertEqual(MailFormat.currentRecipientToken(in: ""), "")
    }
}

/// Defaults whose first write stops half way until the test lets it go:
/// a flush caught in the middle of writing the book out.
private final class GatedDefaults: UserDefaults, @unchecked Sendable {
    let firstWriteStarted = DispatchSemaphore(value: 0)
    let firstWriteMayFinish = DispatchSemaphore(value: 0)
    private let first = Flag()

    override func set(_ value: Any?, forKey defaultName: String) {
        if !first.isSet {
            first.set()
            firstWriteStarted.signal()
            _ = firstWriteMayFinish.wait(timeout: .now() + 5)
        }
        super.set(value, forKey: defaultName)
    }
}

/// Defaults that count the writes and keep none of them: a flush as cheap
/// as its encoding, so a test can run as many as possible.
private final class DiscardingDefaults: UserDefaults, @unchecked Sendable {
    let writes = Counter()

    override func set(_ value: Any?, forKey defaultName: String) {
        writes.add()
    }
}
