import XCTest
@testable import Blackmail

/// A file tapped earlier opened over the letter he had moved to (B-141).
///
/// In a conversation on the test iPad, A's PDF of 14.7 MB was tapped and
/// began downloading; then B's line, which takes the header to B (B-129),
/// then B's own file. A's PDF opened in Quick Look as it landed, over B's
/// header, and B's file, landing under Quick Look, was let go without a
/// word, its spinner cleared. The pane asked only whether it still showed
/// the conversation the file was tapped in. Now the file tapped last opens,
/// and a file tapped before another file, or before another letter's line,
/// is let go as it lands (`FileTaps`).
final class LastFileTappedTests: XCTestCase {

    // MARK: - The rule

    /// The round's race: A's file, B's line, B's file. A is let go, B
    /// opens. One file tapped alone opens.
    func testTheLastFileTappedOpens() {
        var taps = FileTaps()
        XCTAssertEqual(taps.lastFileTapped, 0)
        let a = taps.tapped()
        XCTAssertTrue(taps.opens(a), "alone, it opens")
        taps.lineOpened()
        let b = taps.tapped()
        XCTAssertFalse(taps.opens(a), "tapped before B's line and B's file")
        XCTAssertTrue(taps.opens(b))
    }

    /// A file of the letter he has left, with no file tapped since: let go
    /// as it lands, as `openAttachment` has said since B-122. And of two
    /// files tapped in turn, the second.
    func testAFileOfTheLetterHeLeftIsLetGo() {
        var taps = FileTaps()
        let a = taps.tapped()
        taps.lineOpened()
        XCTAssertFalse(taps.opens(a))

        let first = taps.tapped()
        let second = taps.tapped()
        XCTAssertFalse(taps.opens(first))
        XCTAssertTrue(taps.opens(second))
        XCTAssertGreaterThan(second, first)
    }

    // MARK: - Over the pane's own loads

    /// What `openAttachment` does, step for step, over the real
    /// `PaneLoads`, each download held until the test lets it go: the
    /// header's row busy while its letter is the header's, the tap counted
    /// for the warning (`isOpeningFile`, B-137) until its download ends,
    /// and, as it lands, opened only if the pane still shows what it was
    /// tapped in, it is the last file tapped, and nothing is up over the
    /// pane; its failure said only on the first two. A letter opened by its
    /// line takes the header (`StackFocus`) and lets go every file tapped
    /// before it. The source test below holds the pane to these steps.
    @MainActor
    private final class Pane {
        var focus = StackFocus(opening: "b")
        var taps = FileTaps()
        let loads = PaneLoads()
        var filesOpening = 0
        var busy: Set<String> = []
        var presented: String?
        var said: [String] = []

        /// `file` of `letter`, its download held by `held`.
        func openAttachment(_ file: String, of letter: String, held: Held) {
            if focus.letter == letter { busy.insert(file) }
            let shown = loads.shown
            let tap = taps.tapped()
            filesOpening += 1
            Task { @MainActor in
                defer {
                    filesOpening -= 1
                    if focus.letter == letter { busy.remove(file) }
                }
                do {
                    try await held.wait()
                    guard loads.stillShows(shown) else { return }
                    guard taps.opens(tap) else { return }
                    guard presented == nil else { return }
                    presented = file
                } catch {
                    guard loads.stillShows(shown), taps.opens(tap) else { return }
                    said.append(file)
                }
            }
        }

        /// A letter's line tapped, opening it.
        func lineOpened(_ letter: String) {
            _ = focus.opened(letter, kept: true)
            taps.lineOpened()
        }
    }

    private struct Failed: Error {}

    /// The round's steps: A's PDF, B's line, B's file. A lands first and is
    /// let go, B's spinner kept and the warning still waiting; B lands and
    /// opens, over B's header. Before B-141, A opened and B was let go.
    @MainActor
    func testTheRoundsRaceOpensBsFileNotAs() async throws {
        let pane = Pane()
        pane.lineOpened("a")
        let a = Held()
        pane.openAttachment("a.pdf", of: "a", held: a)
        XCTAssertEqual(pane.busy, ["a.pdf"])
        pane.lineOpened("b")
        let b = Held()
        pane.openAttachment("b.pdf", of: "b", held: b)
        XCTAssertEqual(pane.filesOpening, 2)
        try await until { a.waiting == 1 && b.waiting == 1 }

        a.release()
        try await until { pane.filesOpening == 1 }
        XCTAssertNil(pane.presented, "A's PDF let go")
        XCTAssertTrue(pane.busy.contains("b.pdf"), "B keeps its spinner")
        XCTAssertTrue(pane.said.isEmpty)

        b.release()
        try await until { pane.filesOpening == 0 }
        XCTAssertEqual(pane.presented, "b.pdf")
        XCTAssertFalse(pane.busy.contains("b.pdf"))
        XCTAssertTrue(pane.said.isEmpty)
    }

    /// A's file, then B's line, and nothing more: A lets go as it lands,
    /// nothing opened over B and nothing said, whether it came or failed.
    /// The warning waited for it until it ended.
    @MainActor
    func testAFileHeTappedPastIsNeitherShownNorSaidToHaveFailed() async throws {
        for fails in [false, true] {
            let pane = Pane()
            pane.lineOpened("a")
            let a = Held()
            pane.openAttachment("a.pdf", of: "a", held: a)
            pane.lineOpened("b")
            try await until { a.waiting == 1 }
            XCTAssertEqual(pane.filesOpening, 1, "the warning waits for it")
            a.release(fails ? .failure(Failed()) : .success(()))
            try await until { pane.filesOpening == 0 }
            XCTAssertNil(pane.presented)
            XCTAssertTrue(pane.said.isEmpty)
        }
    }

    /// Two files of one letter, the first still coming: the second opens
    /// whichever lands first, and the first is let go. Its failure, the
    /// last one tapped, is said; an earlier one's is not. A line closed
    /// takes no number, so what he tapped still opens.
    @MainActor
    func testOfTwoFilesTheSecondOpensWhicheverLandsFirst() async throws {
        for secondFirst in [false, true] {
            let pane = Pane()
            let big = Held()
            let small = Held()
            pane.openAttachment("big.pdf", of: "b", held: big)
            pane.openAttachment("small.pdf", of: "b", held: small)
            try await until { big.waiting == 1 && small.waiting == 1 }
            if secondFirst {
                small.release()
                try await until { pane.filesOpening == 1 }
                big.release()
            } else {
                big.release()
                try await until { pane.filesOpening == 1 }
                XCTAssertNil(pane.presented, "the first let go, the second still coming")
                small.release()
            }
            try await until { pane.filesOpening == 0 }
            XCTAssertEqual(pane.presented, "small.pdf")
        }

        let pane = Pane()
        let first = Held()
        let last = Held()
        pane.openAttachment("first.pdf", of: "b", held: first)
        pane.openAttachment("last.pdf", of: "b", held: last)
        try await until { first.waiting == 1 && last.waiting == 1 }
        first.release(.failure(Failed()))
        last.release(.failure(Failed()))
        try await until { pane.filesOpening == 0 }
        XCTAssertEqual(pane.said, ["last.pdf"])

        // A line closed: no number taken, the file opens.
        let closing = Pane()
        let held = Held()
        closing.openAttachment("b.pdf", of: "b", held: held)
        try await until { held.waiting == 1 }
        held.release()
        try await until { closing.filesOpening == 0 }
        XCTAssertEqual(closing.presented, "b.pdf")
    }

    /// The pane moved on, another row or the pane emptied, still lets go
    /// a file as before (B-122), whatever was tapped last.
    @MainActor
    func testAFileOfARowHeLeftIsLetGoAsBefore() async throws {
        let pane = Pane()
        let held = Held()
        pane.openAttachment("a.pdf", of: "b", held: held)
        try await until { held.waiting == 1 }
        pane.loads.show(standIn: {}, fetch: { "the next letter" }, settle: { _ in })
        held.release()
        try await until { pane.filesOpening == 0 }
        XCTAssertNil(pane.presented)
    }

    // MARK: - The pane, read

    /// The pane does what `Pane` does: the tap's number taken with the
    /// pane's place, before its task; the guard after `stillShows` and
    /// before anything over the pane is looked at, and in the failure's
    /// guard; and a letter opened by its line, after its focus and before
    /// anything is fetched, taking a number. Nothing else takes one, and
    /// nothing puts the count back.
    func testThePaneOpensTheLastFileTapped() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(code.contains("private var fileTaps = FileTaps()"))
        let open = try section(of: code, from: "private func openAttachment(",
                               to: "private func prepareInlineImages(")
        XCTAssertTrue(open.contains(
            "if message?.id == m.id { header.setAttachment(attachment.id, busy: true) } "
                + "let shown = loads.shown let tap = fileTaps.tapped() filesOpening += 1 "
                + "Task { @MainActor in defer { filesOpening -= 1 "
                + "if message?.id == m.id { header.setAttachment(attachment.id, busy: false) } }"),
                      open)
        XCTAssertTrue(open.contains(
            "guard loads.stillShows(shown) else { return } guard fileTaps.opens(tap) else { return } "
                + "guard presentedViewController == nil else { return }"), open)
        XCTAssertTrue(open.contains(
            "} catch { guard loads.stillShows(shown), fileTaps.opens(tap) else { return } "
                + "ErrorPresenter.show(.attachmentFailed, on: self) }"), open)

        let load = try section(of: code, from: "private func loadBody(for id: String, focus: Bool) {",
                               to: "private func settleBody(")
        XCTAssertTrue(load.contains(
            "if focus, stackFocus.opened(id, kept: already != nil && body != nil) == .row { focusRow(row) } "
                + "if focus { fileTaps.lineOpened() } if let already, let body {"), load)

        XCTAssertEqual(code.components(separatedBy: "fileTaps.tapped()").count - 1, 1)
        XCTAssertEqual(code.components(separatedBy: "fileTaps.lineOpened()").count - 1, 1)
        XCTAssertEqual(code.components(separatedBy: "fileTaps.opens(tap)").count - 1, 2)
        XCTAssertEqual(code.components(separatedBy: "fileTaps = ").count - 1, 1, "declared, never reset")
        XCTAssertEqual(code.components(separatedBy: "loadBody(for: id, focus: true)").count - 1, 1,
                       "the line's tap alone opens a letter by its line")
    }

    // MARK: - Helpers

    /// Waits, a millisecond at a time and never for more than a second,
    /// until `condition` holds.
    @MainActor
    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(file)")
        let text = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        return text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .joined(separator: " ")
    }

    private func section(of code: String, from start: String, to end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start), start)
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex), end)
        return String(code[from.lowerBound..<to.lowerBound])
    }
}
