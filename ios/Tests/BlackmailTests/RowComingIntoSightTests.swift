import XCTest
@testable import Blackmail

/// B-143: a row came into sight with its two grey preview lines empty after
/// its preview had landed. On the test iPad on 2026-10-26 (round
/// r6-s7-fixes, check 6, int17 at 92f2cb9), fourteen letters APPENDed to
/// "Notes", the folder opened, the previews let land in one FETCH, then the
/// list scrolled a row at a time: in one try of ten the row of letter 9,
/// "Try6 Writer9", whose preview had come 2.3 s before, came in at the
/// bottom with both lines empty, between rows that had theirs, and stayed so
/// until it was scrolled away and back.
///
/// The cause, read in the code: the list patched a landed preview into the
/// cells of the rows in sight alone (`indexPathsForVisibleRows`), and since
/// iOS 15 the table makes the cell for the row just past the edge ahead of
/// time and shows it later without asking for it again; as it came in,
/// only its date was written again (B-139). Since B-135 a row whose preview
/// the list holds is never asked for again, so nothing filled it.
///
/// Now the list draws every cell by one writer, by the parts of the row
/// each moment names (`RowParts`), and a cell coming into sight is drawn
/// whole, so it comes in as a cell made for it then would. The parts are
/// run here over a model of the table, the rows in sight and the row made
/// ahead past the bottom, with the list's real letters (`ListLetters`) and
/// rows (`MessageThread`); the UIKit wiring is read from its source, as
/// `DatesRedrawnTests` reads it.
final class RowComingIntoSightTests: XCTestCase {

    private static let notes = Mailbox(id: "Notes", name: "Notes", unreadCount: 0, role: nil)
    private static let now = Date(timeIntervalSince1970: 1_793_000_000)

    /// The round's letters for try `try`: fourteen, read, from a writer
    /// each, letter 1 the newest, so its rows run Writer1 at the top down to
    /// Writer14, as the round saw Writer9 above Writer10 and Writer11.
    private func letters(try attempt: Int = 6) -> [MessageSummary] {
        (1...14).map { m in
            MessageSummary(id: "7/\(260 + m)", mailboxID: Self.notes.id,
                           sender: "Try\(attempt) Writer\(m) <writer\(m)@example.net>",
                           subject: "R6 B-135 rows try \(attempt) letter \(m)", preview: "",
                           date: Self.now.addingTimeInterval(Double(-60 * m)),
                           isRead: true, isFlagged: false, threadID: "T-\(m)")
        }
    }

    /// Each letter's words as the FETCH answered them.
    private func previews(for rows: [MessageSummary]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: rows.map { ($0.id, "The words of \($0.subject).") })
    }

    // MARK: - The parts

    /// Whatever a patch of the rows in sight draws, a row coming into sight
    /// draws too: whole, as a cell made for it now is drawn. The dates'
    /// patch draws the date and VoiceOver's words and none of the lines,
    /// the spinners' the spinner alone, the previews' the whole row.
    func testWhateverAPatchInSightDrawsARowComingIntoSightDrawsToo() {
        XCTAssertEqual(RowParts.comingIntoSight, .whole)
        XCTAssertEqual(RowParts.made, .whole)
        XCTAssertEqual(RowParts.whole, [.lines, .date, .busy, .label, .ticks])
        XCTAssertEqual(RowParts.patchesInSight.count, 4)
        for patch in RowParts.patchesInSight {
            XCTAssertTrue(RowParts.comingIntoSight.isSuperset(of: patch), "\(patch.rawValue)")
        }
        XCTAssertEqual(RowParts.previewsLanded, .whole)
        XCTAssertEqual(RowParts.datesChanged, [.date, .label])
        XCTAssertEqual(RowParts.draftSpinners, [.busy])
        // Edit mode's ticks, beginning or ending (B-174).
        XCTAssertEqual(RowParts.editMode, [.ticks])
    }

    // MARK: - Over a model of the table

    /// The round's try 6: eight rows in sight, Writer1 to Writer8, and the
    /// cell for Writer9's row made ahead past the bottom with its lines
    /// empty. The previews land and are patched into the rows in sight; the
    /// cell made ahead is not among them. Then the list scrolled a row at a
    /// time, six times: every row coming in has its preview, Writer9's too,
    /// as a cell made for it then would. Nothing is asked for again.
    @MainActor
    func testTheRowMadeAheadComesIntoSightWithItsPreview() {
        let list = ListLetters()
        let page = letters()
        XCTAssertEqual(list.fetchedAfresh(page).count, 14, "none drawn yet")
        let table = PreparedTable(list, in: Self.notes, now: Self.now, rowsInSight: 8)
        XCTAssertEqual(table.inSight, 0..<8)
        XCTAssertEqual(table.madeAhead, [8])
        XCTAssertEqual(table.cell(8)?.lines.subject, "R6 B-135 rows try 6 letter 9")
        XCTAssertEqual(table.cell(8)?.lines.preview, "")

        table.previewsLand(previews(for: page))
        for row in table.inSight {
            XCTAssertEqual(table.cell(row)?.lines.preview, "The words of \(page[row].subject).")
        }
        XCTAssertEqual(table.cell(8)?.lines.preview, "",
                       "made ahead, not among the rows in sight the patch names")
        XCTAssertEqual(list.toDraw(list.shown), [], "held, never asked for again (B-135)")

        for step in 1...6 {
            table.scrollDown()
            XCTAssertEqual(table.inSight, step..<(step + 8))
            table.assertRowsInSightAsMadeNow("after \(step) rows")
        }
        XCTAssertEqual(table.cell(8)?.lines.preview, "The words of R6 B-135 rows try 6 letter 9.")
        XCTAssertEqual(table.cameInBlank, [], "no row came into sight with its lines empty")
    }

    /// The same table drawn as before B-143, a cell coming into sight
    /// having its date and VoiceOver's words written again and nothing else
    /// (B-139's `writeDate`): Writer9's row comes in with its lines empty,
    /// as the round saw it, and stays so; the rows made after the previews
    /// landed have theirs. A model of the wiring then, for an illustration
    /// that the model shows what the iPad showed.
    @MainActor
    func testDrawnAsBeforeTheRowMadeAheadCameInBlank() {
        let list = ListLetters()
        let page = letters()
        _ = list.fetchedAfresh(page)
        let table = PreparedTable(list, in: Self.notes, now: Self.now, rowsInSight: 8,
                                  comingIntoSight: [.date, .label])
        table.previewsLand(previews(for: page))
        for _ in 1...6 { table.scrollDown() }
        XCTAssertEqual(table.cameInBlank, [8], "Writer9's row alone")
        XCTAssertEqual(table.cell(8)?.lines.preview, "")
        XCTAssertEqual(table.cell(9)?.lines.preview, "The words of R6 B-135 rows try 6 letter 10.")
    }

    /// The other two patches, each while a cell waits made ahead: a draft
    /// tapped on the row past the bottom comes in turning; one made ahead
    /// turning, its draft landing while it waits, comes in still; and with
    /// the dates' form changed, the row comes in in the new form, its words
    /// with it (B-139, still so).
    @MainActor
    func testTheRowMadeAheadComesInWithTheSpinnerAndTheDateOfNow() {
        let list = ListLetters()
        let page = letters()
        _ = list.fetchedAfresh(page)
        list.apply(previews: previews(for: page), in: Self.notes.id)
        let table = PreparedTable(list, in: Self.notes, now: Self.now, rowsInSight: 8)
        XCTAssertEqual(table.madeAhead, [8])

        // A draft on its way for Writer9's row, while its cell waits.
        table.draftLoading(page[8].id)
        XCTAssertEqual(table.cell(8)?.busy, false, "made ahead before the tap, not patched")
        table.scrollDown()
        XCTAssertEqual(table.cell(8)?.busy, true, "comes in turning")
        table.assertRowsInSightAsMadeNow("Writer9's draft coming")

        // Writer11's draft tapped instead, its row then made ahead turning,
        // and the draft landing while that cell waits.
        table.draftLoading(page[10].id)
        XCTAssertEqual(table.cell(8)?.busy, false)
        table.scrollDown()
        XCTAssertEqual(table.madeAhead, [10])
        XCTAssertEqual(table.cell(10)?.busy, true, "made ahead while its draft came")
        table.draftLoading(nil)
        XCTAssertEqual(table.cell(10)?.busy, true, "made ahead, not patched")
        table.scrollDown()
        XCTAssertEqual(table.cell(10)?.busy, false, "comes in still")
        table.assertRowsInSightAsMadeNow("the draft let go")

        // The form of the dates changed while Writer12's cell waits.
        XCTAssertEqual(table.madeAhead, [11])
        table.datesChange()
        XCTAssertEqual(table.cell(11)?.date, "form 0", "made ahead, not patched")
        XCTAssertEqual(table.cell(10)?.date, "form 1")
        table.scrollDown()
        XCTAssertEqual(table.cell(11)?.date, "form 1")
        XCTAssertEqual(table.cell(11)?.label.hasSuffix("[form 1]"), true)
        table.assertRowsInSightAsMadeNow("after the form changed")
    }

    // MARK: - The list, read

    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    private func part(of code: String, from start: String, through end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start), start)
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex), end)
        return String(code[from.lowerBound..<to.upperBound])
    }

    private func count(_ text: String, in code: String) -> Int {
        code.components(separatedBy: text).count - 1
    }

    /// What drawing a cell must not do: load a row again, touch the
    /// selection, Edit mode or the scroll, or ask for anything.
    private let neverInADraw = ["reloadData", "reloadRows", "reconfigureRows", "reloadSections",
                                "performBatchUpdates", "beginUpdates", "selectRow", "deselectRow",
                                "setContentOffset", "contentOffset", "scrollToRow", "setEditing",
                                "isEditing", "repository", "fetch", "load(", "loadPreviews", "Task"]

    /// Every cell is drawn by one writer, by the parts named: whole as the
    /// table makes it, and whole as it comes into sight, first, before the
    /// pages are asked for. The writer draws the lines, the date alone, the
    /// spinner and VoiceOver's words, each only where named, and nothing
    /// else; each of them is written nowhere else in the list.
    func testEveryCellIsDrawnByTheOneWriterWholeAsItComesIntoSight() throws {
        let list = try source("UI/MessageListViewController.swift")
        let draw = try part(of: list,
                            from: "private func draw(_ cell: MessageCell, at ip: IndexPath, _ parts: RowParts) {",
                            through: "draw(cell, at: ip, parts) } }")
        XCTAssertEqual(draw,
            "private func draw(_ cell: MessageCell, at ip: IndexPath, _ parts: RowParts) { "
            + "guard ip.row < rows.count else { return } switch rows[ip.row] { case let .thread(thread): "
            + "if parts.contains(.lines) { cell.configure(with: thread.displayRow(in: mailbox, mine: mine), "
            + "marked: thread.marksConversation(in: mailbox)) } "
            + "else if parts.contains(.date) { cell.drawDate() } "
            + "if parts.contains(.busy) { cell.isBusy = thread.messages.contains { $0.id == drafts.loading } } "
            + "if parts.contains(.label) { "
            + "cell.accessibilityLabel = thread.accessibilityLabel(in: mailbox, mine: mine) } "
            + "if parts.contains(.ticks) { cell.ticks = inEditMode } } } "
            + "private func drawRowsInSight(_ parts: RowParts) { "
            + "for ip in tableView.indexPathsForVisibleRows ?? [] { "
            + "guard let cell = tableView.cellForRow(at: ip) as? MessageCell else { continue } "
            + "draw(cell, at: ip, parts) } }")
        for never in neverInADraw { XCTAssertFalse(draw.contains(never), never) }

        let coming = try part(of: list,
                              from: "override func tableView(_ t: UITableView, willDisplay cell: UITableViewCell, "
                                  + "forRowAt ip: IndexPath) {",
                              through: "loadNextPage() }")
        XCTAssertTrue(coming.hasPrefix(
            "override func tableView(_ t: UITableView, willDisplay cell: UITableViewCell, "
            + "forRowAt ip: IndexPath) { "
            + "if let cell = cell as? MessageCell { draw(cell, at: ip, .comingIntoSight) } "), coming)
        let made = try part(of: list,
                            from: "override func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) "
                                + "-> UITableViewCell {",
                            through: "return cell }")
        XCTAssertTrue(made.hasSuffix("draw(cell, at: ip, .made) return cell }"), made)

        XCTAssertEqual(count("draw(cell, at: ip, ", in: list), 3, "made, coming into sight, a patch")
        for writer in ["cell.configure(with:", "cell.drawDate()", "cell.isBusy =",
                       "cell.accessibilityLabel =", "cell.ticks ="] {
            XCTAssertEqual(count(writer, in: list), 1, writer)
        }
        XCTAssertFalse(list.contains("writeDate("), "B-139's writer, folded into the one")
    }

    /// Every patch of the rows in sight goes through the one place that
    /// names them, with parts a row coming into sight draws too: the
    /// previews landing, the dates changing, the draft spinners. The rows in
    /// sight are named nowhere else but where his place is read
    /// (`place()`), which draws nothing, and the list never loads a row
    /// again, or reconfigures one, to draw it.
    func testEveryPatchOfTheRowsInSightGoesThroughTheOnePlace() throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertEqual(count("indexPathsForVisibleRows", in: list), 2)
        XCTAssertTrue(list.contains("private func place() -> ListPlace { "
                                    + "let onScreen = (tableView.indexPathsForVisibleRows ?? [])"))
        XCTAssertEqual(count("cellForRow(at:", in: list), 1, "in `drawRowsInSight` alone")
        XCTAssertFalse(list.contains("visibleCells"))
        XCTAssertFalse(list.contains("reloadRows("))
        XCTAssertFalse(list.contains("reconfigureRows("))

        XCTAssertEqual(count("drawRowsInSight(.", in: list), RowParts.patchesInSight.count)
        XCTAssertTrue(list.contains("rebuildRows() drawRowsInSight(.previewsLanded) }"))
        XCTAssertTrue(list.contains("@objc private func datesChanged() { drawRowsInSight(.datesChanged) "
                                    + "showAge() }"))
        XCTAssertTrue(list.contains("private func showDraftSpinners() { drawRowsInSight(.draftSpinners) }"))
        XCTAssertTrue(list.contains("tableView.setEditing(editing, animated: true) "
                                    + "drawRowsInSight(.editMode)"))
        XCTAssertTrue(list.contains("private func apply(_ previews: [String: String], in mailboxID: String) { "
                                    + "letters.apply(previews: previews, in: mailboxID) rebuildRows() "
                                    + "drawRowsInSight(.previewsLanded) }"))
    }

    /// The Mailboxes column's one patch, a folder's count, asks the table
    /// for the cell at the folder's place, which gives the cell it holds
    /// there, in sight or made ahead (`cellForRowAtIndexPath:`, the SDK's
    /// header since iOS 15); it never goes by the rows in sight.
    func testTheMailboxesColumnAsksForTheCellAtTheFoldersPlace() throws {
        let pane = try source("UI/MailboxListViewController.swift")
        XCTAssertFalse(pane.contains("indexPathsForVisibleRows"))
        XCTAssertFalse(pane.contains("visibleCells"))
        XCTAssertEqual(count("cellForRow(at:", in: pane), 1)
        XCTAssertTrue(pane.contains("let cell = tableView.cellForRow(at: IndexPath(row: place.row, "
                                    + "section: place.section)) else { continue } "
                                    + "configure(cell, with: folder) patched = true }"))
    }
}

/// The list's table as near as the suite can hold it: its rows, cut from
/// the list's letters as the controller cuts them, the cells it holds, for
/// the rows in sight and for the row just past the bottom, made ahead of
/// time (cell prefetching, iOS 15), and each cell drawn by `RowParts` as the
/// controller draws it (`draw(_:at:_:)`): whole as it is made, the parts of
/// a patch for the rows in sight, and `comingIntoSight` as a row comes in.
/// The table gives a row a cell when it is made and lets the cell go when
/// the row has gone out of sight above.
///
/// A cell is what it shows: the row's lines as drawn (`displayRow`), the
/// date as written, its form standing for the iPad's (`datesChange`), the
/// spinner, and VoiceOver's words, with the form.
@MainActor
private final class PreparedTable {
    struct Cell: Equatable {
        /// A cell the table has just dequeued, before anything is drawn on it.
        static let blank = Cell(lines: MessageSummary(id: "", mailboxID: "", sender: "", subject: "",
                                                      preview: "", date: .distantPast,
                                                      isRead: true, isFlagged: false))

        var lines: MessageSummary
        var marked = false
        var date = ""
        var busy = false
        var label = ""
    }

    private let letters: ListLetters
    private let mailbox: Mailbox
    private let now: Date
    private let mine = OwnAddresses([])
    private let comingIntoSight: RowParts
    private let height: Int
    private(set) var rows: [MessageThread]
    private var cells: [Int: Cell] = [:]
    private(set) var top = 0
    private var loading: String?
    private var form = 0
    /// The rows that came into sight with their preview lines empty while
    /// the row held words.
    private(set) var cameInBlank: [Int] = []

    init(_ letters: ListLetters, in mailbox: Mailbox, now: Date, rowsInSight: Int,
         comingIntoSight: RowParts = .comingIntoSight) {
        self.letters = letters
        self.mailbox = mailbox
        self.now = now
        self.height = rowsInSight
        self.comingIntoSight = comingIntoSight
        rows = MessageThread.rows(for: letters.shown, grouped: true)
        for row in inSight { comeIntoSight(row) }
        makeAhead()
    }

    var inSight: Range<Int> { top..<min(rows.count, top + height) }

    /// The rows with a cell that are not in sight.
    var madeAhead: [Int] { cells.keys.filter { !inSight.contains($0) }.sorted() }

    func cell(_ row: Int) -> Cell? { cells[row] }

    /// The controller's `draw(_:at:_:)`.
    private func draw(_ row: Int, _ parts: RowParts) {
        guard row < rows.count, var cell = cells[row] else { return }
        let thread = rows[row]
        if parts.contains(.lines) {
            cell.lines = thread.displayRow(in: mailbox, mine: mine)
            cell.marked = thread.marksConversation(in: mailbox)
            cell.date = "form \(form)"
        } else if parts.contains(.date) {
            cell.date = "form \(form)"
        }
        if parts.contains(.busy) { cell.busy = thread.messages.contains { $0.id == loading } }
        if parts.contains(.label) {
            cell.label = thread.accessibilityLabel(in: mailbox, mine: mine, now: now) + " [form \(form)]"
        }
        cells[row] = cell
    }

    /// `cellForRowAt`: a cell for `row`, drawn as it is made.
    private func make(_ row: Int) {
        guard row < rows.count else { return }
        cells[row] = .blank
        draw(row, .made)
    }

    /// The cell for the row just past the bottom, made ahead of time.
    private func makeAhead() {
        let next = top + height
        if next < rows.count, cells[next] == nil { make(next) }
    }

    /// `willDisplay`: the row's cell, made now if the table had none.
    private func comeIntoSight(_ row: Int) {
        if cells[row] == nil { make(row) }
        draw(row, comingIntoSight)
        if cells[row]?.lines.preview.isEmpty == true, !rows[row].newest.preview.isEmpty {
            cameInBlank.append(row)
        }
    }

    /// The patches, `drawRowsInSight`: the cells of the rows in sight.
    private func drawRowsInSight(_ parts: RowParts) {
        for row in inSight { draw(row, parts) }
    }

    /// One row down: the top row's cell let go, the row under the bottom
    /// coming into sight, and the row past the new bottom made ahead.
    func scrollDown() {
        cells[top] = nil
        top += 1
        comeIntoSight(top + height - 1)
        makeAhead()
    }

    /// `apply(_:in:)`: the previews into the letters, the rows cut again,
    /// the rows in sight drawn.
    func previewsLand(_ previews: [String: String]) {
        letters.apply(previews: previews, in: mailbox.id)
        rows = MessageThread.rows(for: letters.shown, grouped: true)
        drawRowsInSight(.previewsLanded)
    }

    /// `datesChanged`: the iPad's form of the dates changed.
    func datesChange() {
        form += 1
        drawRowsInSight(.datesChanged)
    }

    /// `showDraftSpinners`: the draft on its way, nil when none is.
    func draftLoading(_ id: String?) {
        loading = id
        drawRowsInSight(.draftSpinners)
    }

    /// Every row in sight shows what a cell made for it now would.
    func assertRowsInSightAsMadeNow(_ when: String, file: StaticString = #filePath, line: UInt = #line) {
        for row in inSight {
            let shown = cells[row]
            cells[row] = .blank
            draw(row, .whole)
            let fresh = cells[row]
            cells[row] = shown
            XCTAssertEqual(shown, fresh, "row \(row), \(when)", file: file, line: line)
        }
    }
}
