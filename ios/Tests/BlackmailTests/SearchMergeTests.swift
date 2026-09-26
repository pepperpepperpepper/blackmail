import XCTest
@testable import Blackmail

/// Tests for interleaving All Mail's hits with Trash's and Spam's.
///
/// Every failure here is invisible on screen. A message emitted on two
/// consecutive pages looks like two similar letters; one that falls between
/// pages looks like a letter that was never there — and "the letter is not
/// there" is precisely the complaint this feature exists to answer, so a
/// merge bug would be indistinguishable from the bug it is fixing.
final class SearchMergeTests: XCTestCase {

    private func row(_ id: String, _ day: Int, mailbox: String = "all") -> MessageSummary {
        MessageSummary(id: id, mailboxID: mailbox, sender: "a", subject: id,
                       preview: "", date: Date(timeIntervalSince1970: Double(day) * 86_400),
                       isRead: false, isFlagged: false)
    }

    /// Newest first, as both streams and the output must be.
    private func stream(_ days: [Int], prefix: String, mailbox: String = "all")
        -> [MessageSummary] {
        days.map { row("\(prefix)/\($0)", $0, mailbox: mailbox) }
    }

    // MARK: - Ordering

    func testTheNewerOfTheTwoHeadsIsAlwaysTakenFirst() {
        let all = stream([9, 6, 3], prefix: "a")
        let bin = stream([8, 5], prefix: "t", mailbox: "trash")
        let m = SearchMerge.take(5, from: all, primaryExhausted: true, and: bin)
        XCTAssertEqual(m.taken.map(\.subject), ["a/9", "t/8", "a/6", "t/5", "a/3"])
    }

    func testABinnedMessageCanBeTheVeryFirstResult() {
        // The case that motivates the whole feature: he binned it
        // yesterday and it is the newest thing matching.
        let m = SearchMerge.take(3, from: stream([5, 4], prefix: "a"),
                                 primaryExhausted: true,
                                 and: stream([9], prefix: "t", mailbox: "trash"))
        XCTAssertEqual(m.taken.first?.subject, "t/9")
    }

    func testTheOutputIsAlwaysDateDescending() {
        let m = SearchMerge.take(10, from: stream([10, 7, 2], prefix: "a"),
                                 primaryExhausted: true,
                                 and: stream([9, 8, 1], prefix: "t", mailbox: "trash"))
        XCTAssertEqual(m.taken.map(\.date), m.taken.map(\.date).sorted(by: >))
    }

    func testMessagesSharingATimestampAreOrderedTotallyAndNotArbitrarily() {
        // Two messages to the second is ordinary — anything sent by a
        // machine. Without a total order the comparison is ambiguous, and
        // across a page boundary that means one emitted twice or skipped.
        let a = row("a/5", 5)
        let t = row("t/5", 5, mailbox: "trash")
        let first = SearchMerge.take(2, from: [a], primaryExhausted: true, and: [t])
        let second = SearchMerge.take(2, from: [a], primaryExhausted: true, and: [t])
        XCTAssertEqual(first.taken.map(\.id), second.taken.map(\.id))
        XCTAssertEqual(first.taken.count, 2)
    }

    // MARK: - The limit, and what is left over

    func testWhatIsNotTakenIsHandedBackInOrderForTheNextPage() {
        let all = stream([9, 6, 3], prefix: "a")
        let bin = stream([8, 5], prefix: "t", mailbox: "trash")
        let first = SearchMerge.take(2, from: all, primaryExhausted: true, and: bin)
        XCTAssertEqual(first.taken.map(\.subject), ["a/9", "t/8"])

        let second = SearchMerge.take(3, from: first.primary, primaryExhausted: true,
                                      and: first.secondary)
        XCTAssertEqual(second.taken.map(\.subject), ["a/6", "t/5", "a/3"])
    }

    func testPagingTheWholeStreamYieldsEveryMessageExactlyOnceAndInOrder() {
        var primary = stream([20, 17, 14, 11, 8, 5, 2], prefix: "a")
        var secondary = stream([19, 13, 12, 4], prefix: "t", mailbox: "trash")
        let expected = (primary + secondary).sorted(by: SearchMerge.isOrderedBefore)

        var seen: [MessageSummary] = []
        while true {
            let m = SearchMerge.take(3, from: primary, primaryExhausted: true,
                                     and: secondary)
            if m.taken.isEmpty { break }
            seen += m.taken
            primary = m.primary
            secondary = m.secondary
        }
        XCTAssertEqual(seen.map(\.id), expected.map(\.id))
        XCTAssertEqual(Set(seen.map(\.id)).count, seen.count, "a message repeated")
    }

    // MARK: - The refill rule

    func testAnEmptyButUnFINISHEDPrimaryStopsTheMergeRatherThanFallingThrough() {
        // The subtle one. If All Mail has more to give, a trashed message
        // from last March must NOT be emitted just because the current
        // chunk ran out — it would land above hundreds of newer letters
        // that have not been fetched yet.
        let m = SearchMerge.take(5, from: [], primaryExhausted: false,
                                 and: stream([3, 2], prefix: "t", mailbox: "trash"))
        XCTAssertTrue(m.taken.isEmpty)
        XCTAssertEqual(m.secondary.count, 2, "nothing consumed")
    }

    func testAnEmptyAndFINISHEDPrimaryLetsTheRestOfTheBinnedResultsThrough() {
        let m = SearchMerge.take(5, from: [], primaryExhausted: true,
                                 and: stream([3, 2], prefix: "t", mailbox: "trash"))
        XCTAssertEqual(m.taken.map(\.subject), ["t/3", "t/2"])
    }

    func testAnExhaustedSecondaryLetsThePrimaryRunOnAlone() {
        let m = SearchMerge.take(5, from: stream([3, 2], prefix: "a"),
                                 primaryExhausted: true, and: [])
        XCTAssertEqual(m.taken.count, 2)
    }

    // MARK: - Degenerate

    func testBothEmptyIsAnEmptyPageAndNotALoop() {
        let m = SearchMerge.take(50, from: [], primaryExhausted: true, and: [])
        XCTAssertTrue(m.taken.isEmpty)
    }

    func testALimitOfZeroTakesNothingAndConsumesNothing() {
        let all = stream([9], prefix: "a")
        let m = SearchMerge.take(0, from: all, primaryExhausted: true, and: [])
        XCTAssertTrue(m.taken.isEmpty)
        XCTAssertEqual(m.primary.count, 1)
    }

    func testResultsKeepTheMailboxTheyWereFoundIn() {
        // Everything downstream — open, flag, move, delete — passes this
        // back. A trashed hit stamped "all mail" would act on a UID that
        // means a different message there.
        let m = SearchMerge.take(2, from: stream([5], prefix: "a"),
                                 primaryExhausted: true,
                                 and: stream([6], prefix: "t", mailbox: "trash"))
        XCTAssertEqual(m.taken.map(\.mailboxID), ["trash", "all"])
    }
}
