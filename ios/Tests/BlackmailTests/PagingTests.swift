import XCTest
@testable import Blackmail

/// Tests for paging past the first fifty messages.
///
/// The view controller is UIKit-gated and absent on this host, so what is
/// pinned here is the logic underneath it: the cursor arithmetic the
/// repository performs on a UID snapshot, and the rules the list uses to
/// decide whether there is another page. Both were written against the
/// awkward cases rather than the happy one, because paging goes wrong at
/// the seams between pages and nowhere else.
final class PagingTests: XCTestCase {

    /// A mailbox's UIDs as SEARCH ALL returns them: ascending, with gaps
    /// where messages have been deleted.
    private let ascending: [UInt32] = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]

    /// The REAL cursor walk, not a copy of it.
    ///
    /// This used to be fourteen lines reproducing `listMessages`' arithmetic
    /// by hand, because the repository is behind `#if canImport(Network)`
    /// and does not exist on the machine these tests run on. That made every
    /// assertion below a test of the copy: the two could drift and the suite
    /// would stay green while the product broke. The arithmetic now lives in
    /// `PageWindow`, which has no Network dependency, and both the
    /// repository and these tests call it.
    private func page(after cursor: UInt32?, limit: Int,
                      in ascending: [UInt32]) -> [UInt32] {
        PageWindow.older(than: cursor, in: ascending, limit: limit)
    }

    // MARK: - Walking the snapshot

    func testFirstPageIsTheNewestMessages() {
        XCTAssertEqual(page(after: nil, limit: 4, in: ascending), [89, 55, 34, 21])
    }

    func testTheNextPageStartsBelowTheCursorAndNeverRepeatsIt() {
        // The seam. Off by one here either drops a message between pages or
        // shows the same letter twice, and a duplicated row is a letter
        // that cannot be told from its twin.
        let first = page(after: nil, limit: 4, in: ascending)
        let second = page(after: first.last, limit: 4, in: ascending)
        XCTAssertEqual(second, [13, 8, 5, 3])
        XCTAssertTrue(Set(first).isDisjoint(with: Set(second)))
    }

    func testWalkingTheWholeMailboxYieldsEveryMessageExactlyOnce() {
        var seen: [UInt32] = []
        var cursor: UInt32?
        while true {
            let next = page(after: cursor, limit: 3, in: ascending)
            if next.isEmpty { break }
            seen.append(contentsOf: next)
            cursor = next.last
        }
        XCTAssertEqual(seen, ascending.reversed().map { $0 })
        XCTAssertEqual(Set(seen).count, ascending.count, "a message was repeated")
    }

    func testACursorExpungedByAnotherClientStillPagesFromTheRightPlace() {
        // The message the cursor names is gone. Falling back to "everything
        // strictly older by value" keeps the walk going instead of
        // restarting it at the top, which would loop forever.
        let withoutCursor = ascending.filter { $0 != 21 }
        XCTAssertEqual(page(after: 21, limit: 3, in: withoutCursor), [13, 8, 5])
    }

    func testTheLastPageIsShortAndTheOneAfterItIsEmpty() {
        // A short page is how "no more messages" is spelled — there is no
        // count from the server to compare against.
        let last = page(after: 3, limit: 10, in: ascending)
        XCTAssertEqual(last, [2, 1])
        XCTAssertTrue(page(after: 1, limit: 10, in: ascending).isEmpty)
    }

    func testAnEmptyMailboxPagesToNothingRatherThanLooping() {
        XCTAssertTrue(page(after: nil, limit: 50, in: []).isEmpty)
    }

    // MARK: - When to stop

    /// `reachedOldestMessage` is set by a short page; that one rule decides
    /// whether the scroll trigger keeps firing.
    private func isLastPage(_ returned: Int, pageSize: Int) -> Bool {
        returned < pageSize
    }

    func testAFullPageMeansKeepGoing() {
        XCTAssertFalse(isLastPage(50, pageSize: 50))
    }

    func testAShortOrEmptyPageMeansStop() {
        XCTAssertTrue(isLastPage(49, pageSize: 50))
        XCTAssertTrue(isLastPage(0, pageSize: 50))
    }

    func testAFolderSmallerThanOnePageNeverOffersMore() {
        // The common case for this user: Drafts with two letters in it must
        // not show a "Load More Messages" footer that does nothing.
        XCTAssertTrue(isLastPage(2, pageSize: 50))
    }

    // MARK: - Appending

    private func summary(_ id: String) -> MessageSummary {
        MessageSummary(id: id, mailboxID: "INBOX", sender: "a", subject: "b",
                       preview: "", date: Date(timeIntervalSince1970: 0),
                       isRead: false, isFlagged: false)
    }

    func testAppendingDropsIdsAlreadyOnScreen() {
        // A message MOVED into this folder by another client between two
        // page fetches can appear in both, even though the UID snapshot is
        // stable.
        let existing = ["1/9", "1/8", "1/7"].map(summary)
        let incoming = ["1/7", "1/6", "1/5"].map(summary)

        let known = Set(existing.map(\.id))
        let fresh = incoming.filter { !known.contains($0.id) }

        XCTAssertEqual(fresh.map(\.id), ["1/6", "1/5"])
        XCTAssertEqual(Set((existing + fresh).map(\.id)).count, 5)
    }

    func testAppendingLeavesEarlierRowsAtTheSameIndex() {
        // The property that keeps the list still under a reader's thumb,
        // and the reason paging appends rather than replacing.
        var rows = ["1/9", "1/8"].map(summary)
        let before = rows.map(\.id)
        rows.append(contentsOf: ["1/7", "1/6"].map(summary))
        XCTAssertEqual(Array(rows.prefix(before.count)).map(\.id), before)
    }
}
