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

    private func file(_ part: String, of letter: String = "b", shown: Int = 0) -> FileTaps.File {
        FileTaps.File(letter: letter, part: part, shown: shown)
    }

    /// The round's race: A's file, B's line, B's file. A is let go, B
    /// opens. One file tapped alone opens.
    func testTheLastFileTappedOpens() {
        var taps = FileTaps()
        XCTAssertEqual(taps.lastFileTapped, 0)
        let a = file("2", of: "a")
        XCTAssertTrue(taps.tapped(a), "its download starts")
        XCTAssertTrue(taps.opens(a), "alone, it opens")
        taps.lineOpened("b", headerWasOn: "a")
        let b = file("2", of: "b")
        XCTAssertTrue(taps.tapped(b))
        XCTAssertFalse(taps.opens(a), "tapped before B's line and B's file")
        XCTAssertTrue(taps.opens(b))
    }

    /// A file of the letter he left, with no file tapped since: let go
    /// as it lands, as `openAttachment` has said since B-122. And of two
    /// files tapped in turn, the second.
    func testAFileOfTheLetterHeLeftIsLetGo() {
        var taps = FileTaps()
        let a = file("2", of: "a")
        _ = taps.tapped(a)
        taps.lineOpened("b", headerWasOn: "a")
        XCTAssertFalse(taps.opens(a))

        let first = file("2")
        let second = file("3")
        XCTAssertTrue(taps.tapped(first))
        XCTAssertTrue(taps.tapped(second))
        XCTAssertFalse(taps.opens(first))
        XCTAssertTrue(taps.opens(second))
    }

    /// The line of the letter the header is on, closed and opened again,
    /// takes no number: what he tapped there still opens. So does the
    /// newest's, the header's as the stack opens.
    func testTheHeadersOwnLineOpenedAgainLetsNothingGo() {
        var taps = FileTaps()
        let a = file("2", of: "a")
        _ = taps.tapped(a)
        taps.lineOpened("a", headerWasOn: "a")
        XCTAssertTrue(taps.opens(a))
        XCTAssertEqual(taps.lastFileTapped, 1)
        taps.lineOpened("b", headerWasOn: "a")
        XCTAssertFalse(taps.opens(a))
    }

    /// The same file tapped again while it comes starts no download: the
    /// one running opens it, as the last tap, until another file or
    /// another letter's line, and again if he taps it after those. Once
    /// its download has ended, a tap fetches it again. Another place in
    /// the pane is another download.
    func testTheSameFileTappedAgainIsTheDownloadAlreadyComing() {
        var taps = FileTaps()
        let big = file("2")
        XCTAssertTrue(taps.tapped(big))
        XCTAssertFalse(taps.tapped(big), "no second download")
        XCTAssertTrue(taps.opens(big))
        XCTAssertFalse(taps.tapped(big))
        XCTAssertTrue(taps.opens(big))

        let small = file("3")
        XCTAssertTrue(taps.tapped(small))
        XCTAssertFalse(taps.opens(big))
        XCTAssertFalse(taps.tapped(big), "back to the first: its download, still running")
        XCTAssertTrue(taps.opens(big))
        XCTAssertFalse(taps.opens(small))

        taps.lineOpened("a", headerWasOn: "b")
        XCTAssertFalse(taps.opens(big))
        taps.lineOpened("b", headerWasOn: "a")
        XCTAssertFalse(taps.tapped(big), "back on its letter, its download still running")
        XCTAssertTrue(taps.opens(big))

        taps.ended(big)
        XCTAssertFalse(taps.opens(big))
        XCTAssertTrue(taps.tapped(big), "ended: fetched again")
        XCTAssertTrue(taps.opens(big))

        let elsewhere = file("2", shown: 1)
        XCTAssertTrue(taps.tapped(elsewhere), "the pane given something else since")
        XCTAssertFalse(taps.opens(big))
        XCTAssertTrue(taps.opens(elsewhere))
    }

    // MARK: - Over the pane's own loads

    /// What `openAttachment` does, step for step, over the real
    /// `PaneLoads`, each download held until the test lets it go: the
    /// header's row busy while its letter is the header's, a file already
    /// coming tapped again starting nothing, the tap counted for the
    /// warning (`isOpeningFile`, B-137) until its download ends, and, as it
    /// lands, opened only if the pane still shows what it was tapped in,
    /// the last tap was on it, and nothing is up over the pane; its failure
    /// said only on the first two. A letter opened by its line takes the
    /// header (`StackFocus`) and, if it was not the header's already, lets
    /// go every file tapped before it. The source test below holds the
    /// pane to these steps.
    @MainActor
    private final class Pane {
        var focus = StackFocus(opening: "b")
        var taps = FileTaps()
        let loads = PaneLoads()
        var filesOpening = 0
        var fetches = 0
        var busy: Set<String> = []
        var presented: String?
        var said: [String] = []

        /// `part` of `letter`, its download, if one starts, held by `held`.
        func openAttachment(_ part: String, of letter: String, held: Held) {
            if focus.letter == letter { busy.insert(part) }
            let shown = loads.shown
            let file = FileTaps.File(letter: letter, part: part, shown: shown)
            guard taps.tapped(file) else { return }
            filesOpening += 1
            Task { @MainActor in
                defer {
                    filesOpening -= 1
                    taps.ended(file)
                    if focus.letter == letter { busy.remove(part) }
                }
                do {
                    fetches += 1
                    try await held.wait()
                    guard loads.stillShows(shown) else { return }
                    guard taps.opens(file) else { return }
                    guard presented == nil else { return }
                    presented = part
                } catch {
                    guard loads.stillShows(shown), taps.opens(file) else { return }
                    said.append(part)
                }
            }
        }

        /// A letter's line tapped, opening it.
        func lineOpened(_ letter: String) {
            let headerWasOn = focus.letter
            _ = focus.opened(letter, kept: true)
            taps.lineOpened(letter, headerWasOn: headerWasOn)
        }

        /// A letter's line tapped, closing it: the header stays.
        func lineClosed(_ letter: String) {}

        /// Quick Look's Done.
        func done() { presented = nil }
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
    /// last one tapped, is said; an earlier one's is not.
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
    }

    /// One file tapped twice, and three times, while it comes, from a row
    /// among the words or a picture, which keep no spinner and are never
    /// held: one download, which opens it as it lands, its spinner kept
    /// until then and the warning waiting for that one alone. Before, each
    /// tap took a number and a download of its own: the first to land was
    /// let go, its spinner cleared, and he waited for the second.
    @MainActor
    func testTheSameFileTappedAgainOpensAsItsFirstDownloadLands() async throws {
        for fails in [false, true] {
            let pane = Pane()
            let first = Held()
            let again = Held()
            pane.openAttachment("big.pdf", of: "b", held: first)
            try await until { first.waiting == 1 }
            pane.openAttachment("big.pdf", of: "b", held: again)
            pane.openAttachment("big.pdf", of: "b", held: again)
            XCTAssertEqual(pane.filesOpening, 1)
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertEqual(again.waiting, 0, "no second download")
            XCTAssertEqual(pane.fetches, 1)
            XCTAssertEqual(pane.busy, ["big.pdf"])

            first.release(fails ? .failure(Failed()) : .success(()))
            try await until { pane.filesOpening == 0 }
            if fails {
                XCTAssertNil(pane.presented)
                XCTAssertEqual(pane.said, ["big.pdf"], "its failure said, once")
            } else {
                XCTAssertEqual(pane.presented, "big.pdf", "opened as the first download landed")
                XCTAssertTrue(pane.said.isEmpty)
            }
            XCTAssertTrue(pane.busy.isEmpty)

            // Its download over, the file tapped again is fetched again,
            // and opens.
            pane.done()
            let later = Held()
            pane.openAttachment("big.pdf", of: "b", held: later)
            try await until { later.waiting == 1 }
            XCTAssertEqual(pane.fetches, 2)
            later.release()
            try await until { pane.filesOpening == 0 }
            XCTAssertEqual(pane.presented, "big.pdf")
        }
    }

    /// A file, another file, the first again: the first's download, still
    /// running, opens it, and the second is let go. A's file, B's line,
    /// A's line, A's file again: A's download opens it, with nothing
    /// fetched a second time.
    @MainActor
    func testAFileTappedAgainAfterAnotherIsItsOwnDownload() async throws {
        let pane = Pane()
        let big = Held()
        let small = Held()
        let unused = Held()
        pane.openAttachment("big.pdf", of: "b", held: big)
        pane.openAttachment("small.pdf", of: "b", held: small)
        pane.openAttachment("big.pdf", of: "b", held: unused)
        try await until { big.waiting == 1 && small.waiting == 1 }
        XCTAssertEqual(pane.fetches, 2)
        small.release()
        try await until { pane.filesOpening == 1 }
        XCTAssertNil(pane.presented, "small.pdf tapped before the first again")
        big.release()
        try await until { pane.filesOpening == 0 }
        XCTAssertEqual(pane.presented, "big.pdf")
        XCTAssertEqual(unused.waiting, 0)

        let stack = Pane()
        stack.lineOpened("a")
        let a = Held()
        stack.openAttachment("a.pdf", of: "a", held: a)
        stack.lineOpened("b")
        stack.lineOpened("a")
        stack.openAttachment("a.pdf", of: "a", held: unused)
        try await until { a.waiting == 1 }
        XCTAssertEqual(stack.fetches, 1)
        XCTAssertEqual(stack.busy, ["a.pdf"])
        a.release()
        try await until { stack.filesOpening == 0 }
        XCTAssertEqual(stack.presented, "a.pdf")
    }

    /// The header on A, A's file tapped, then A's own line closed and
    /// opened again while it comes: the header never left A, and the file
    /// opens as it lands. A line closed, alone, lets nothing go either.
    @MainActor
    func testTheHeadersLetterClosedAndOpenedAgainKeepsItsFile() async throws {
        let pane = Pane()
        pane.lineOpened("a")
        let a = Held()
        pane.openAttachment("a.pdf", of: "a", held: a)
        try await until { a.waiting == 1 }
        pane.lineClosed("a")
        pane.lineOpened("a")
        a.release()
        try await until { pane.filesOpening == 0 }
        XCTAssertEqual(pane.presented, "a.pdf")

        let closing = Pane()
        let b = Held()
        closing.openAttachment("b.pdf", of: "b", held: b)
        try await until { b.waiting == 1 }
        closing.lineClosed("a")
        b.release()
        try await until { closing.filesOpening == 0 }
        XCTAssertEqual(closing.presented, "b.pdf")
    }

    /// The pane moved on, another row or the pane emptied, still lets go
    /// a file as before (B-122), whatever was tapped last. Back on the
    /// letter, the same file tapped is another download, which opens.
    @MainActor
    func testAFileOfARowHeLeftIsLetGoAsBefore() async throws {
        let pane = Pane()
        let held = Held()
        pane.openAttachment("a.pdf", of: "b", held: held)
        try await until { held.waiting == 1 }
        pane.loads.show(standIn: {}, fetch: { "the next letter" }, settle: { _ in })
        let again = Held()
        pane.openAttachment("a.pdf", of: "b", held: again)
        try await until { again.waiting == 1 }
        held.release()
        try await until { pane.filesOpening == 1 }
        XCTAssertNil(pane.presented)
        again.release()
        try await until { pane.filesOpening == 0 }
        XCTAssertEqual(pane.presented, "a.pdf")

        let left = Pane()
        let gone = Held()
        left.openAttachment("a.pdf", of: "b", held: gone)
        try await until { gone.waiting == 1 }
        left.loads.supersede()
        gone.release()
        try await until { left.filesOpening == 0 }
        XCTAssertNil(left.presented)
    }

    // MARK: - The pane, read

    /// The pane does what `Pane` does: the file named with the pane's
    /// place at the tap, a tap on one already coming starting nothing,
    /// before the count and the task; its download let go in the `defer`
    /// with the count; the guard after `stillShows` and before anything
    /// over the pane is looked at, and in the failure's guard; and a letter
    /// opened by its line, the header's letter read before it moves and
    /// before anything is fetched, letting go what was tapped only when the
    /// header moves. Nothing else takes a number, and nothing puts the
    /// count back.
    func testThePaneOpensTheLastFileTapped() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(code.contains("private var fileTaps = FileTaps()"))
        let open = try section(of: code, from: "private func openAttachment(",
                               to: "private func prepareInlineImages(")
        XCTAssertTrue(open.contains(
            "run(BodyFiles.Busy(attachment.id, of: m.id, busy: true)) "
                + "let shown = loads.shown "
                + "let file = FileTaps.File(letter: m.id, part: attachment.id, shown: shown) "
                + "guard fileTaps.tapped(file, for: item) else { return } filesOpening += 1 "
                + "Task { @MainActor in defer { filesOpening -= 1 fileTaps.ended(file) "
                + "if loads.stillShows(shown) { run(BodyFiles.Busy(attachment.id, of: m.id, busy: false)) } }"),
                      open)
        XCTAssertTrue(open.contains(
            "guard loads.stillShows(shown) else { return } guard fileTaps.opens(file) else { return } "
                + "let use = fileTaps.item(of: file) ?? item "
                + "if !use.presents { keep(data, of: attachment, by: use) return } "
                + "guard presentedViewController == nil else { return }"), open)
        XCTAssertTrue(open.contains(
            "} catch { guard loads.stillShows(shown), fileTaps.opens(file) else { return } "
                + "ErrorPresenter.show(.attachmentFailed, on: self) }"), open)

        let load = try section(of: code, from: "private func loadBody(for id: String, focus: Bool) {",
                               to: "private func settleBody(")
        XCTAssertTrue(load.contains(
            "let headerWasOn = stackFocus.letter "
                + "if focus, stackFocus.opened(id, kept: already != nil && body != nil) == .row { focusRow(row) } "
                + "if focus { fileTaps.lineOpened(id, headerWasOn: headerWasOn) } if let already, let body {"),
                      load)

        XCTAssertEqual(code.components(separatedBy: "fileTaps.tapped(").count - 1, 1)
        XCTAssertEqual(code.components(separatedBy: "fileTaps.ended(").count - 1, 1)
        XCTAssertEqual(code.components(separatedBy: "fileTaps.lineOpened(").count - 1, 1)
        XCTAssertEqual(code.components(separatedBy: "fileTaps.opens(file)").count - 1, 2)
        XCTAssertEqual(code.components(separatedBy: "fileTaps = ").count - 1, 1, "declared, never reset")
        XCTAssertEqual(code.components(separatedBy: "loadBody(for: id, focus: true)").count - 1, 1,
                       "the line's tap alone opens a letter by its line")
        // A line closed returns before it: no number, as `Pane.lineClosed`.
        XCTAssertTrue(code.contains(
            "document.setOpen(opened, id) guard opened else { return } loadBody(for: id, focus: true)"))
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
