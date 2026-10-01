import XCTest
@testable import Blackmail

/// The loader's pictures: each answered once, and never after WebKit has
/// stopped it, and the fetch under one stopped called off
/// (`PictureRequests`). What a fetch called off sends on the connection is
/// `LargeLetterTests`'.
final class PictureRequestsTests: XCTestCase {

    /// A fetch that runs until it is called off, or for a minute.
    private func waiting() -> Task<Void, Never> {
        Task { try? await Task.sleep(nanoseconds: 60_000_000_000) }
    }

    func testARequestIsAnsweredOnce() {
        var requests = PictureRequests<Int>()
        requests.begin(1)
        let fetch = waiting()
        requests.answering(1, with: fetch)
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests.answer(1))
        XCTAssertFalse(requests.answer(1), "answered twice")
        XCTAssertFalse(fetch.isCancelled, "answering calls nothing off")
        XCTAssertEqual(requests.count, 0)
        fetch.cancel()
    }

    /// Stopped, as WebKit stops every picture still coming when the page
    /// goes: never answered, and its fetch called off.
    func testARequestStoppedIsNeverAnsweredAndItsFetchIsCalledOff() {
        var requests = PictureRequests<Int>()
        let fetches = (0..<3).map { k -> Task<Void, Never> in
            requests.begin(k)
            let fetch = waiting()
            requests.answering(k, with: fetch)
            return fetch
        }
        requests.stop(0)
        requests.stop(2)
        XCTAssertEqual(fetches.map(\.isCancelled), [true, false, true])
        XCTAssertFalse(requests.answer(0))
        XCTAssertFalse(requests.answer(2))
        XCTAssertTrue(requests.answer(1), "the one still wanted")
        // Stopped again, or after it was answered: nothing more.
        requests.stop(1)
        XCTAssertFalse(fetches[1].isCancelled)
        fetches[1].cancel()
    }

    /// A fetch given for a request no longer wanted is called off at once.
    func testAFetchForARequestAlreadyStoppedIsCalledOffAtOnce() {
        var requests = PictureRequests<Int>()
        requests.begin(7)
        requests.stop(7)
        let fetch = waiting()
        requests.answering(7, with: fetch)
        XCTAssertTrue(fetch.isCancelled)
        XCTAssertFalse(requests.answer(7))
        XCTAssertEqual(requests.count, 0)
    }
}
