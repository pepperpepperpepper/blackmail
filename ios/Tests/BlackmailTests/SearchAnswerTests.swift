import XCTest
@testable import Blackmail

/// What the list does with a search's answer when it lands. The whole of
/// `runSearch`'s decision apart from the table it redraws.
final class SearchAnswerTests: XCTestCase {

    private let hits = [MessageSummary(id: "1/5", mailboxID: "INBOX", sender: "Sam Example",
                                       subject: "Letter 5: garden", preview: "",
                                       date: Date(timeIntervalSince1970: 0),
                                       isRead: true, isFlagged: false)]

    /// Cancelled by the next keystroke while its answer was on its way back
    /// to the main actor. It found something, and it is still not drawn:
    /// those are hits for a query he has already typed past, and they would
    /// sit under the new one until its own debounce ran out.
    func testASearchCancelledOnItsWayBackDrawsNothingEvenWhenItFoundSomething() {
        XCTAssertEqual(SearchAnswer.settle(.success(hits), cancelled: true, current: true), .ignore)
        XCTAssertEqual(SearchAnswer.settle(.success([]), cancelled: true, current: true), .ignore)
    }

    /// Cancelled, however it ended, is never "Could not search".
    func testACancelledSearchNeverSaysItCouldNotSearch() {
        XCTAssertEqual(SearchAnswer.settle(.failure(MailError.cannotConnect),
                                           cancelled: true, current: true), .ignore)
        XCTAssertEqual(SearchAnswer.settle(.failure(CancellationError()),
                                           cancelled: false, current: true), .ignore)
    }

    func testTheCurrentSearchIsDrawnOrSaysItFailed() {
        XCTAssertEqual(SearchAnswer.settle(.success(hits), cancelled: false, current: true),
                       .draw(hits))
        XCTAssertEqual(SearchAnswer.settle(.success([]), cancelled: false, current: true), .draw([]))
        XCTAssertEqual(SearchAnswer.settle(.failure(MailError.cannotConnect),
                                           cancelled: false, current: true), .failed)
    }

    /// The list has been replaced, by another folder, a cleared field or a
    /// newer search: whatever this one came to is not for the screen.
    func testAnAnswerForAListThatHasMovedOnIsDropped() {
        XCTAssertEqual(SearchAnswer.settle(.success(hits), cancelled: false, current: false), .ignore)
        XCTAssertEqual(SearchAnswer.settle(.failure(MailError.cannotConnect),
                                           cancelled: false, current: false), .ignore)
    }
}
