import XCTest
@testable import Blackmail

/// The conversation's header at the tap (B-129). A letter opened inside a
/// conversation took the header and the toolbar only once its body had
/// come, so until then Flag, Move and Delete acted on the letter before,
/// and a letter with a different number of files moved the stack when it
/// came. And a letter opened again whose body was kept took them at once,
/// so a letter opened before it and still coming took them back when it
/// landed. Now the letter he opens takes them at the tap, from its row, as
/// the single letter's pane does since P1, with Reply held until its body
/// has come; the last letter he opened owns the header.
final class StackHeaderAtTheTapTests: XCTestCase {

    // MARK: - Which letter has the header

    /// The stack opens on its newest letter, which takes the header whole
    /// when its body lands. A letter he opens by its line takes it at the
    /// tap, from its row; its body landing makes it whole; the newest
    /// landing after that leaves it alone.
    func testALetterOpenedByItsLineTakesTheHeaderAtTheTap() {
        var focus = StackFocus(opening: "1/30")
        XCTAssertEqual(focus.letter, "1/30")
        XCTAssertTrue(focus.takes("1/30"), "the newest, landing, before any tap")
        XCTAssertEqual(focus.opened("1/28", kept: false), .row)
        XCTAssertEqual(focus.letter, "1/28")
        XCTAssertFalse(focus.takes("1/30"), "the newest, landing after the tap")
        XCTAssertTrue(focus.takes("1/28"))

        XCTAssertNil(StackFocus().letter, "no conversation")
        XCTAssertFalse(StackFocus().takes("1/28"))
    }

    /// A letter opened again whose body is in the stack already takes the
    /// header whole at once; one whose body has not come, from its row.
    func testALetterOpenedAgainWithItsBodyKeptTakesItWhole() {
        var focus = StackFocus(opening: "1/30")
        XCTAssertEqual(focus.opened("1/29", kept: true), .letter)
        XCTAssertEqual(focus.letter, "1/29")
        XCTAssertEqual(focus.opened("1/28", kept: false), .row)
        XCTAssertEqual(focus.opened("1/29", kept: true), .letter)
    }

    /// The race: a letter opened, still coming, then one opened again whose
    /// body is kept, which takes the header at once; the first, landing
    /// after, leaves it on the second. And any number of letters opened in
    /// turn: only the last one opened takes it as it lands.
    func testTheLastLetterOpenedOwnsTheHeader() {
        var focus = StackFocus(opening: "1/30")
        _ = focus.opened("1/27", kept: false)
        XCTAssertEqual(focus.opened("1/29", kept: true), .letter)
        XCTAssertFalse(focus.takes("1/27"), "opened before it and still coming")
        XCTAssertEqual(focus.letter, "1/29")

        let opened = ["1/21", "1/22", "1/23", "1/24"]
        for id in opened { _ = focus.opened(id, kept: false) }
        for id in opened.dropLast() { XCTAssertFalse(focus.takes(id), id) }
        XCTAssertTrue(focus.takes("1/24"))
        XCTAssertFalse(focus.takes("1/29"))
        XCTAssertFalse(focus.takes("1/30"))
    }

    // MARK: - Over the pane's own loads

    /// What the pane does with a letter opened by its line, step for step,
    /// over the real `PaneLoads`, each fetch held until the test lets it
    /// go: the header from the row at the tap, or whole at once for a body
    /// kept, then whole when a body lands for the letter opened last. The
    /// body goes into its section whoever has the header.
    @MainActor
    private final class Pane {
        var focus = StackFocus(opening: "n")
        let loads = PaneLoads()
        var kept: Set<String> = []
        var header: [String] = []
        var filled: [String] = []

        func open(_ id: String, held: Held) {
            if focus.opened(id, kept: kept.contains(id)) == .row { header.append("row \(id)") }
            if kept.contains(id) {
                header.append("whole \(id)")
                return
            }
            loads.start({ try await held.wait(); return id }, settle: { [self] result in
                guard case .success(let landed) = result else { return }
                kept.insert(landed)
                filled.append(landed)
                if focus.takes(landed) { header.append("whole \(landed)") }
            })
        }
    }

    /// A letter opened, still coming, then one whose body is kept: the
    /// second has the header at once and keeps it when the first lands,
    /// its body put in its section all the same.
    @MainActor
    func testALetterStillComingDoesNotTakeTheHeaderBackWhenItLands() async throws {
        let pane = Pane()
        pane.kept = ["b"]
        let a = Held()
        pane.open("a", held: a)
        pane.open("b", held: Held())
        XCTAssertEqual(pane.header, ["row a", "whole b"])
        try await until { a.waiting == 1 }
        a.release()
        try await until { pane.loads.inFlight == 0 }
        XCTAssertEqual(pane.filled, ["a"])
        XCTAssertEqual(pane.header, ["row a", "whole b"], "b's still")
    }

    /// Two letters opened, both coming, the second answered first: each
    /// takes the header from its row at its tap, and the second alone
    /// makes it whole, whichever lands first.
    @MainActor
    func testTwoLettersComingTheSecondOwnsTheHeaderWhicheverLandsFirst() async throws {
        let pane = Pane()
        let a = Held()
        let c = Held()
        pane.open("a", held: a)
        pane.open("c", held: c)
        XCTAssertEqual(pane.header, ["row a", "row c"])
        try await until { a.waiting == 1 && c.waiting == 1 }
        c.release()
        a.release()
        try await until { pane.loads.inFlight == 0 }
        XCTAssertEqual(Set(pane.filled), ["a", "c"])
        XCTAssertEqual(pane.header, ["row a", "row c", "whole c"])
    }

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

    // MARK: - The pane

    /// The pane, read: a line opened marks its letter's focus at the tap,
    /// before anything is fetched, and draws the header from its row when
    /// its body is not in the stack, Reply held (`message` nil), Flag, Move
    /// and Delete on it (`summary`), its files grey, the stack hanging from
    /// the header (B-128); a body landing makes the header whole only for
    /// the letter opened last; the stack opens on its newest, and every
    /// other show and the empty pane forget it. Reply does nothing without
    /// a letter; Flag, Move and Delete act on `summary`.
    func testThePaneTakesTheHeaderAtTheTap() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        let load = try section(of: code, from: "private func loadBody(for id: String, focus: Bool) {",
                               to: "private func settleBody(")
        for wiring in [
            "guard let row = threadSummaries[id] else { return } let already = loaded[id] "
                + "let body = document.body(of: id) let headerWasOn = stackFocus.letter "
                + "if focus, stackFocus.opened(id, kept: already != nil && body != nil) == .row { focusRow(row) } "
                + "if focus { fileTaps.lineOpened(id, headerWasOn: headerWasOn) } "
                + "if let already, let body { drawBody(already, body, focus: focus) return }",
            "loads.start({ try await repository.openLetter(row) }",
        ] {
            XCTAssertTrue(load.contains(wiring), wiring)
        }
        let tapAt = try XCTUnwrap(load.range(of: "focusRow(row)"))
        XCTAssertLessThan(tapAt.upperBound, try XCTUnwrap(load.range(of: "loads.start(")).lowerBound,
                          "the header before the fetch is asked for")

        let row = try section(of: code, from: "private func focusRow(_ row: MessageSummary) {",
                              to: "private func focusLetter(")
        XCTAssertTrue(row.contains(
            "message = nil summary = row let before = header.frame.height "
            + "header.configure(with: .heading(for: row)) header.onSelectAttachment = nil "
            + "keepPlace(headerWas: before) }"), row)

        let letter = try section(of: code, from: "private func focusLetter(_ m: Message) {",
                                 to: "private func keepPlace(")
        XCTAssertTrue(letter.contains("{ guard stackFocus.takes(m.id) else { return } message = m "
                                      + "summary = threadSummaries[m.id] ?? summary"), letter)

        let tapped = try section(of: code, from: "func userContentController(",
                                 to: "private func markOpened(")
        XCTAssertTrue(tapped.contains("document.setOpen(opened, id) guard opened else { return } "
                                      + "loadBody(for: id, focus: true)"), tapped)

        XCTAssertTrue(code.contains("stackFocus = StackFocus(opening: thread.newest.id)"))
        XCTAssertEqual(code.components(separatedBy: "stackFocus = StackFocus()").count, 4,
                       "declared, the empty pane and the single letter")
        XCTAssertEqual(code.components(separatedBy: "focusRow(").count, 3, "declared, and the tap's")
        XCTAssertEqual(code.components(separatedBy: "stackFocus.opened(").count, 2, "the tap's alone")
        XCTAssertTrue(code.contains("@objc private func replyTapped() { guard let m = message else { return }"))
        for button in ["@objc private func flagTapped() { guard let s = summary else { return }",
                       "@objc private func moveTapped() { guard let s = summary else { return }",
                       "@objc private func deleteTapped() { guard let s = summary, "
                       + "writes.deleteGoes(at: ProcessInfo.processInfo.systemUptime) else { return }"] {
            XCTAssertTrue(code.contains(button), button)
        }
    }

    // MARK: - Helpers

    /// A file under `Sources/Blackmail`, comment lines taken out and
    /// whitespace runs made one space.
    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .joined(separator: " ")
    }

    private func section(of code: String, from start: String, to end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start), start)
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex), end)
        return String(code[from.lowerBound..<to.lowerBound])
    }
}
