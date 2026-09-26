import XCTest
@testable import Blackmail

/// Tests for a letter with nothing in it saying so.
///
/// The reason is not courtesy to whoever sent an empty message. It is that
/// **a blank reading pane should only ever mean a bug.** B-026 was a
/// message that arrived with a filled-in header and nothing under it, and
/// what made it take three experiments to chase is that a blank pane is
/// exactly what an empty letter looks like. Once an empty letter says so,
/// a pane with nothing in it cannot be explained away.
///
/// The cases that matter are therefore the FALSE positives: anything that
/// wrongly reports "no text" hides a real letter behind a notice saying
/// there isn't one, which is worse than the blank it replaces.
final class EmptyBodyTests: XCTestCase {

    private func empty(text: String? = nil, html: String? = nil) -> Bool {
        MailText.hasNoVisibleContent(text: text, html: html)
    }

    // MARK: - Genuinely nothing

    func testAMessageWithNeitherPartIsEmpty() {
        XCTAssertTrue(empty())
    }

    func testWhitespaceOnlyIsEmpty() {
        // Senders really do ship a plain part containing one newline.
        XCTAssertTrue(empty(text: "\n  \n\t"))
    }

    func testMarkupWithNoWordsInItIsEmpty() {
        XCTAssertTrue(empty(html: "<html><body><div><br></div></body></html>"))
    }

    func testAStylesheetIsNotContent() {
        // An HTML mail's stylesheet routinely runs longer than the message;
        // a letter that is nothing BUT a stylesheet has nothing in it.
        XCTAssertTrue(empty(html: "<html><head><style>p{margin:0}</style></head><body></body></html>"))
    }

    // MARK: - Not empty, and these are the ones that matter

    func testAnyProseMeansNotEmpty() {
        XCTAssertFalse(empty(text: "What a poster!"))
        XCTAssertFalse(empty(html: "<div>What a poster!</div>"))
    }

    func testAPictureWithNoWordsIsALetter() {
        // People send a photograph and say nothing. Calling that "no text"
        // would put a notice over the only thing in the message.
        XCTAssertFalse(empty(html: "<div><img src=\"cid:ii_9z\"></div>"))
    }

    func testASignatureALONEIsNotEmpty() {
        // The case that made this fire far less often than expected, and
        // the one I got wrong first: a subject-only letter from an Apple
        // Mail user still carries the sender's signature in the body, so
        // the pane has something in it and always did. One of the end user's own
        // letters is exactly this shape — no text part, 5.7 kB of HTML,
        // eight characters of prose above the signature table.
        let signatureOnly = """
        <html><head><meta http-equiv="content-type" content="text/html; charset=utf-8">
        </head><body dir="auto"><br id="lineBreakAtBeginningOfSignature">
        <div dir="ltr"><table><tbody><tr><td><b>Sam Example</b><br>
        Example Organisation<br>555-555-0142</td></tr></tbody></table></div>
        </body></html>
        """
        XCTAssertFalse(empty(html: signatureOnly))
    }

    func testAPlainPartWinsOverEmptyMarkup() {
        XCTAssertFalse(empty(text: "the words", html: "<div></div>"))
    }

    func testAnEmptyPlainPartFallsThroughToTheMarkup() {
        // Mirrors `Message.quotableText`: a blank text part is not an
        // answer, it is an absence.
        XCTAssertFalse(empty(text: "   ", html: "<div>the words</div>"))
    }

    // MARK: - What it says

    func testTheNoticeDistinguishesEmptyFromFAILED() {
        // Two different sentences for two different situations, because
        // telling him a letter is empty when the download failed sends him
        // away from a message that is actually there.
        XCTAssertEqual(MailText.emptyBodyNotice, "This message has no text.")
        XCTAssertFalse(MailText.emptyBodyNotice.lowercased().contains("download"))
        XCTAssertFalse(MailText.emptyBodyNotice.lowercased().contains("error"))
    }
}
