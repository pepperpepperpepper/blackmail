import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Blackmail

/// A YouTube video's title asked of YouTube for a share's subject (B-126):
/// which links are asked about, the one address asked, what is taken from
/// the answer, the YouTube app's cut of a long title, and `done` called
/// once, on the main thread, within the wait, whatever the web does.
/// Nothing here reaches the web: the asking is handed in.
final class VideoTitleTests: XCTestCase {

    private let id = "dQw4w9WgXcQ"

    // MARK: - Which links

    /// The YouTube app's youtu.be link, and youtube.com's watch, shorts,
    /// live and embed pages on www., m. and music.: the video's id.
    func testTheVideoALinkPlays() {
        for link in ["https://youtu.be/\(id)", "https://youtu.be/\(id)?si=AbCdEfGhIjKlMnOp",
                     "http://youtu.be/\(id)", "https://YOUTU.BE/\(id)",
                     "https://www.youtube.com/watch?v=\(id)", "https://www.youtube.com/watch?v=\(id)&t=30s",
                     "https://www.youtube.com/watch?feature=share&v=\(id)",
                     "https://youtube.com/watch?v=\(id)", "https://m.youtube.com/watch?v=\(id)",
                     "https://music.youtube.com/watch?v=\(id)&list=RDAMVM",
                     "https://www.youtube.com/shorts/\(id)", "https://youtube.com/shorts/\(id)?si=x",
                     "https://www.youtube.com/live/\(id)", "https://www.youtube.com/embed/\(id)"] {
            XCTAssertEqual(VideoTitle.id(of: URL(string: link)!), id, link)
        }
    }

    /// Anything else is not asked about: a channel, a playlist, YouTube's
    /// front page, an id of the wrong length or with other characters,
    /// another site, one dressed as YouTube, and another scheme.
    func testEveryOtherLinkIsNotAVideo() {
        for link in ["https://www.youtube.com/@SomeChannel", "https://www.youtube.com/channel/UC1234567890",
                     "https://www.youtube.com/playlist?list=PL0123456789", "https://www.youtube.com/",
                     "https://www.youtube.com/watch", "https://www.youtube.com/watch?list=PL01234567",
                     "https://youtu.be/", "https://youtu.be/dQw4w9WgXc", "https://youtu.be/dQw4w9WgXcQQ",
                     "https://youtu.be/dQw4w9WgXc%2B", "https://www.youtube.com/watch?v=dQw4w9WgX.Q",
                     "https://en.wikipedia.org/wiki/Opera_house", "https://notyoutube.com/watch?v=\(id)",
                     "https://youtube.com.example.net/watch?v=\(id)", "https://example.net/youtu.be/\(id)",
                     "ftp://youtu.be/\(id)", "https://www.youtube.com/results?search_query=\(id)"] {
            XCTAssertNil(VideoTitle.id(of: URL(string: link)!), link)
        }
    }

    // MARK: - What is asked

    /// YouTube's oEmbed for the video's watch page, as JSON, the address
    /// escaped whole, nothing kept and no cookie.
    func testTheQuestionIsYouTubesOembedForTheWatchPage() {
        let question = VideoTitle.question(for: id)
        XCTAssertEqual(question.url?.absoluteString,
                       "https://www.youtube.com/oembed?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3D"
                       + id + "&format=json")
        XCTAssertEqual(question.httpMethod ?? "GET", "GET")
        XCTAssertEqual(question.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertFalse(question.httpShouldHandleCookies)
        XCTAssertEqual(question.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(question.timeoutInterval, 10)
        XCTAssertEqual(VideoTitle.wait, 10)
    }

    // MARK: - The answer

    /// The title, as it is: quotes, an apostrophe, an accent and a dash
    /// untouched, as his subjects had them. On one line, blank lines and
    /// the spaces at either end gone.
    func testTheTitleIsTakenFromAnAnswerOf200() {
        XCTAssertEqual(VideoTitle.title(in: answer(#"{"title":"Bach — Prelude in C","author_name":"x"}"#),
                                        status: 200), "Bach — Prelude in C")
        XCTAssertEqual(VideoTitle.title(in: answer(#"{"title":"Don't \"stop\" – Fauré's Élégie"}"#),
                                        status: 200), #"Don't "stop" – Fauré's Élégie"#)
        XCTAssertEqual(VideoTitle.title(in: answer(#"{"title":"  Tosca,\n\nAct 2  "}"#), status: 200),
                       "Tosca, Act 2")
    }

    /// No title, and the subject stays empty: any status but 200, no
    /// answer, a page that is not JSON (a hotel's sign-in page), JSON
    /// without a title or with an empty one.
    func testAnythingElseHasNoTitle() {
        let good = answer(#"{"title":"Tosca"}"#)
        for status in [nil, 400, 401, 403, 404, 500, 302] {
            XCTAssertNil(VideoTitle.title(in: good, status: status), "\(String(describing: status))")
        }
        XCTAssertNil(VideoTitle.title(in: nil, status: 200))
        XCTAssertNil(VideoTitle.title(in: answer("<html><title>Sign in</title></html>"), status: 200))
        XCTAssertNil(VideoTitle.title(in: answer(#"{"author_name":"x"}"#), status: 200))
        XCTAssertNil(VideoTitle.title(in: answer(#"{"title":5}"#), status: 200))
        XCTAssertNil(VideoTitle.title(in: answer(#"{"title":" \n "}"#), status: 200))
        XCTAssertNil(VideoTitle.title(in: answer(#"["title"]"#), status: 200))
    }

    /// As the YouTube app hands a title to Mail: whole up to 75
    /// characters, longer cut to its first 72 and "...", counted as
    /// characters show, an accent one, as his three long titles with
    /// accents were cut, and an emoji one, which none of his showed.
    func testALongTitleIsCutAsTheYouTubeAppCutsIt() {
        let seventyFive = String(repeating: "a", count: 75)
        XCTAssertEqual(VideoTitle.subject(from: seventyFive), seventyFive)
        XCTAssertEqual(VideoTitle.subject(from: seventyFive + "b"), String(repeating: "a", count: 72) + "...")
        let hundred = String(repeating: "Bach ", count: 20)
        XCTAssertEqual(VideoTitle.subject(from: hundred), String(hundred.prefix(72)) + "...")
        XCTAssertEqual(VideoTitle.subject(from: hundred).count, 75)
        let accents = String(repeating: "é", count: 71) + "🎻ü" + "rest"
        XCTAssertEqual(VideoTitle.subject(from: accents), String(repeating: "é", count: 71) + "🎻" + "...")
        XCTAssertEqual(VideoTitle.subject(from: "Tosca"), "Tosca")
    }

    // MARK: - Asking

    /// The answer comes on another thread, as the web's does: `done` has
    /// the subject, once, on the main thread.
    func testTheSubjectComesOnceOnTheMainThread() {
        let calls = Calls()
        let came = expectation(description: "done")
        var asked: [URLRequest] = []
        VideoTitle.ask(for: URL(string: "https://youtu.be/\(id)?si=xyz")!, through: { request, reply in
            asked.append(request)
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(20)) {
                reply(self.answer(#"{"title":"Tosca, Act 2"}"#), 200)
            }
        }, within: 2) { subject in
            calls.note(subject, main: Thread.isMainThread)
            came.fulfill()
        }
        wait(for: [came], timeout: 5)
        XCTAssertEqual(asked.map { $0.url }, [VideoTitle.question(for: id).url])
        XCTAssertEqual(calls.all, ["Tosca, Act 2"])
        XCTAssertEqual(calls.offMain, 0)
        settle(2.2)
        XCTAssertEqual(calls.all, ["Tosca, Act 2"], "not again at the wait's end")
    }

    /// A long title comes cut, as the YouTube app cuts it.
    func testALongTitleComesCut() {
        let calls = Calls()
        let came = expectation(description: "done")
        let long = String(repeating: "Prelude ", count: 12)
        VideoTitle.ask(for: URL(string: "https://youtu.be/\(id)")!, through: { _, reply in
            DispatchQueue.global().async { reply(self.answer(#"{"title":"\#(long)"}"#), 200) }
        }, within: 2) { subject in
            calls.note(subject, main: Thread.isMainThread)
            came.fulfill()
        }
        wait(for: [came], timeout: 5)
        XCTAssertEqual(calls.all, [String(long.prefix(72)) + "..."])
    }

    /// YouTube says no, or never answers, or answers after the wait: nil,
    /// once, and nothing after it.
    func testNoAnswerInTimeIsNil() {
        let refused = Calls()
        let no = expectation(description: "refused")
        let asked = Date()
        VideoTitle.ask(for: URL(string: "https://youtu.be/\(id)")!, through: { _, reply in
            DispatchQueue.global().async { reply(Data("Unauthorized".utf8), 401) }
        }, within: 3) { refused.note($0, main: Thread.isMainThread); no.fulfill() }
        wait(for: [no], timeout: 5)
        XCTAssertEqual(refused.all, [nil])
        XCTAssertLessThan(Date().timeIntervalSince(asked), 1.5, "at the answer, not the wait's end")

        let silent = Calls()
        let gaveUp = expectation(description: "silent")
        let began = Date()
        VideoTitle.ask(for: URL(string: "https://youtu.be/\(id)")!, through: { _, _ in },
                       within: 0.1) { silent.note($0, main: Thread.isMainThread); gaveUp.fulfill() }
        wait(for: [gaveUp], timeout: 5)
        XCTAssertEqual(silent.all, [nil])
        XCTAssertLessThan(Date().timeIntervalSince(began), 2)

        let late = Calls()
        let tooLate = expectation(description: "late")
        VideoTitle.ask(for: URL(string: "https://youtu.be/\(id)")!, through: { _, reply in
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(300)) {
                reply(self.answer(#"{"title":"Tosca"}"#), 200)
            }
        }, within: 0.05) { late.note($0, main: Thread.isMainThread); tooLate.fulfill() }
        wait(for: [tooLate], timeout: 5)
        settle(0.6)
        XCTAssertEqual(late.all, [nil], "the title after the wait is not used")
        XCTAssertEqual(refused.offMain + silent.offMain + late.offMain, 0)
    }

    /// A link that plays no video is not asked about: nil, on the main
    /// thread, and nothing fetched.
    func testALinkToNoVideoIsNotAsked() {
        let calls = Calls()
        let came = expectation(description: "done")
        var fetched = 0
        VideoTitle.ask(for: URL(string: "https://www.youtube.com/@SomeChannel")!, through: { _, _ in
            fetched += 1
        }, within: 2) { calls.note($0, main: Thread.isMainThread); came.fulfill() }
        wait(for: [came], timeout: 5)
        XCTAssertEqual(fetched, 0)
        XCTAssertEqual(calls.all, [nil])
        XCTAssertEqual(calls.offMain, 0)
    }

    private func answer(_ json: String) -> Data { Data(json.utf8) }

    /// Lets the main thread run for `seconds`, so anything late can come.
    private func settle(_ seconds: TimeInterval) {
        let later = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { later.fulfill() }
        wait(for: [later], timeout: seconds + 5)
    }

    /// What `done` was called with, and how often off the main thread.
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var made: [String?] = []
        private var off = 0

        func note(_ subject: String?, main: Bool) {
            lock.lock()
            made.append(subject)
            if !main { off += 1 }
            lock.unlock()
        }

        var all: [String?] { lock.lock(); defer { lock.unlock() }; return made }
        var offMain: Int { lock.lock(); defer { lock.unlock() }; return off }
    }
}
