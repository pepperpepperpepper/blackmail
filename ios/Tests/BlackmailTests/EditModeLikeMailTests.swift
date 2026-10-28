import XCTest
@testable import Blackmail

/// The list's Edit mode as Mail's (B-174), from the side-by-side round of
/// 2026-10-27 (comparison C-03): Mark, Move and Trash grey until a row is
/// ticked; Edit grey in an empty folder, and Edit mode over when its last
/// row goes; the title "1 Selected"; a ticked row's letter in the reading
/// pane, and the letter before put back as Edit mode ends; the pane dimmed
/// with nothing ticked; a ticked row blue with a white tick.
///
/// The rules are `EditBar`'s and `EditPane`'s, run here. The controllers
/// and the row are UIKit and built only for the device, so how they use
/// the rules is read from their source, comment lines out, as
/// `EditBarTests` reads it.
final class EditModeLikeMailTests: XCTestCase {

    // MARK: - The bar and the title (C1, C2, C3)

    /// Mail's words, "%1$lu Selected" for every count, and the folder's
    /// name with nothing ticked.
    func testTheTitleSaysHowManyAreSelected() {
        XCTAssertEqual(EditBar.title(ticked: 1, folder: "Notes"), "1 Selected")
        XCTAssertEqual(EditBar.title(ticked: 3, folder: "Notes"), "3 Selected")
        XCTAssertEqual(EditBar.title(ticked: 1200, folder: "Notes"), "1200 Selected")
        XCTAssertEqual(EditBar.title(ticked: 0, folder: "Notes"), "Notes")
        XCTAssertEqual(EditBar.title(ticked: 0, folder: "Inbox"), "Inbox")
    }

    /// Mark, Move and the third button can be tapped from the first tick,
    /// and not before.
    func testMarkMoveAndTrashWaitForATick() {
        XCTAssertFalse(EditBar.acts(ticked: 0))
        XCTAssertTrue(EditBar.acts(ticked: 1))
        XCTAssertTrue(EditBar.acts(ticked: 40))
    }

    /// Edit is grey with no rows, Cancel never; Edit mode ends by itself
    /// when the folder's last row goes, and only then: not over a search
    /// with no hits.
    func testEditIsGreyInAnEmptyFolderAndEndsWithTheLastRow() {
        XCTAssertFalse(EditBar.canEdit(rows: 0, editing: false))
        XCTAssertTrue(EditBar.canEdit(rows: 1, editing: false))
        XCTAssertTrue(EditBar.canEdit(rows: 0, editing: true), "Cancel")
        XCTAssertTrue(EditBar.ends(rows: 0, editing: true, searching: false))
        XCTAssertFalse(EditBar.ends(rows: 1, editing: true, searching: false))
        XCTAssertFalse(EditBar.ends(rows: 0, editing: false, searching: false))
        XCTAssertFalse(EditBar.ends(rows: 0, editing: true, searching: true), "no hits")
        XCTAssertFalse(EditBar.ends(rows: 1, editing: true, searching: true))
    }

    /// Edit's button as the last row goes in Edit mode: Edit mode ends
    /// first, and Edit is grey after it, by the rows and Edit mode as they
    /// are then. Asked while Edit mode was on, it came out blue.
    func testEditIsGreyOnceEditModeEndsWithTheLastRow() {
        var editing = true
        if EditBar.ends(rows: 0, editing: editing, searching: false) { editing = false }
        XCTAssertFalse(EditBar.canEdit(rows: 0, editing: editing))
        XCTAssertTrue(EditBar.canEdit(rows: 0, editing: true), "asked before the end")
    }

    /// Dimmed in Edit mode with nothing ticked; in full colour with a tick,
    /// and out of Edit mode.
    func testThePaneIsDimmedWithNothingTicked() {
        XCTAssertTrue(EditBar.dimsPane(editing: true, ticked: 0))
        XCTAssertFalse(EditBar.dimsPane(editing: true, ticked: 1))
        XCTAssertFalse(EditBar.dimsPane(editing: true, ticked: 2))
        XCTAssertFalse(EditBar.dimsPane(editing: false, ticked: 0))
    }

    // MARK: - The pane (C4)

    private func letter(_ uid: Int, thread: String) -> MessageSummary {
        MessageSummary(id: "7/\(uid)", mailboxID: "INBOX",
                       sender: "Sam Example <sam@example.com>", subject: "About \(thread)",
                       preview: "", date: Date(timeIntervalSince1970: 1_790_000_000 + Double(uid) * 3_600),
                       isRead: true, isFlagged: false, threadID: thread)
    }

    /// Rows: 0 the conversation A (150, 147), 1 B (149), 2 C (148).
    private var threads: [MessageThread] {
        MessageThread.rows(for: [letter(150, thread: "A"), letter(149, thread: "B"),
                                 letter(148, thread: "C"), letter(147, thread: "A")],
                           grouped: true)
    }

    private func ids(_ back: EditPane.Back) -> [String]? {
        if case .letters(let thread) = back { return thread.messages.map(\.id) }
        return nil
    }

    /// One row ticked: its letter goes in the pane; Edit mode over: the
    /// letter before comes back, as the list has it now.
    func testOneTickShowsItsLetterAndTheLetterBeforeComesBack() {
        let threads = self.threads
        XCTAssertEqual(threads.map(\.id), ["7/150", "7/149", "7/148"])
        var pane = EditPane()
        pane.begin(showing: ["7/149"], thread: threads[1])
        XCTAssertEqual(pane.ticked([2], in: threads, showing: ["7/149"]), 2)
        // The pane shows C now, its letter first.
        XCTAssertEqual(ids(pane.end(in: threads, showing: ["7/148"])), ["7/149"])
    }

    /// The conversation shown before, by any of its letters, comes back
    /// whole; with the pane empty before, it goes back to empty.
    func testTheConversationOrNothingComesBack() {
        let threads = self.threads
        var pane = EditPane()
        pane.begin(showing: ["7/147", "7/150"], thread: threads[0])
        XCTAssertEqual(pane.ticked([1], in: threads, showing: ["7/147", "7/150"]), 1)
        XCTAssertEqual(ids(pane.end(in: threads, showing: ["7/149"])), ["7/150", "7/147"])

        pane.begin(showing: [], thread: nil)
        XCTAssertEqual(pane.ticked([2], in: threads, showing: []), 2)
        guard case .empty = pane.end(in: threads, showing: ["7/148"]) else {
            return XCTFail("empty again")
        }
    }

    /// Nothing goes in the pane for no tick, two or more ticks, the row the
    /// pane already shows, a row out of range, outside Edit mode, or in a
    /// folder whose rows open the composer; and with nothing put in the
    /// pane, nothing is put back.
    func testOnlyOneTickOfAnotherRowChangesThePane() {
        let threads = self.threads
        var pane = EditPane()
        XCTAssertNil(pane.ticked([2], in: threads, showing: []), "not in Edit mode")
        pane.begin(showing: ["7/150"], thread: threads[0])
        XCTAssertNil(pane.ticked([], in: threads, showing: ["7/150"]))
        XCTAssertNil(pane.ticked([1, 2], in: threads, showing: ["7/150"]))
        XCTAssertNil(pane.ticked([0], in: threads, showing: ["7/150"]), "already in the pane")
        XCTAssertNil(pane.ticked([9], in: threads, showing: ["7/150"]))
        XCTAssertNil(pane.ticked([2], in: threads, showing: ["7/150"], opens: false), "Drafts")
        guard case .stay = pane.end(in: threads, showing: ["7/150"]) else {
            return XCTFail("nothing to put back")
        }
    }

    /// The Edit bar's Trash or Move taking the letter before with the
    /// ticked one: the pane emptied as Edit mode ends, the letter before
    /// not shown again for a moment, by its own id, any letter of its
    /// conversation, or a copy under another mailbox's id; and put back
    /// when it is not among them. Nothing out of Edit mode, and nothing
    /// left over for the next Edit mode.
    func testTheLetterBeforeIsNotPutBackWhenTheBarTakesIt() {
        let threads = self.threads
        var pane = EditPane()
        pane.begin(showing: ["7/149"], thread: threads[1])
        XCTAssertEqual(pane.ticked([2], in: threads, showing: ["7/149"]), 2)
        pane.taking([letter(148, thread: "C"), letter(149, thread: "B")])
        guard case .empty = pane.end(in: threads, showing: ["7/148"]) else {
            return XCTFail("the letter before goes with them")
        }

        pane.begin(showing: ["7/150", "7/147"], thread: threads[0])
        XCTAssertEqual(pane.ticked([2], in: threads, showing: ["7/150", "7/147"]), 2)
        pane.taking([letter(148, thread: "C"), letter(147, thread: "A")])
        guard case .empty = pane.end(in: threads, showing: ["7/148"]) else {
            return XCTFail("a letter of the conversation before goes")
        }

        let before = letter(149, thread: "B")
        let twin = MessageSummary(id: "9/31", mailboxID: "[Gmail]/All Mail", sender: before.sender,
                                  subject: before.subject, preview: "", date: before.date,
                                  isRead: true, isFlagged: false, threadID: "B")
        pane.begin(showing: ["7/149"], thread: threads[1])
        XCTAssertEqual(pane.ticked([2], in: threads, showing: ["7/149"]), 2)
        pane.taking([letter(148, thread: "C"), twin])
        guard case .empty = pane.end(in: threads, showing: ["7/148"]) else {
            return XCTFail("its copy from All Mail goes")
        }

        pane.begin(showing: ["7/149"], thread: threads[1])
        XCTAssertEqual(pane.ticked([2], in: threads, showing: ["7/149"]), 2)
        pane.taking([letter(148, thread: "C")])
        XCTAssertEqual(ids(pane.end(in: threads, showing: ["7/148"])), ["7/149"], "not among them")

        pane.taking([letter(149, thread: "B")])
        pane.begin(showing: ["7/149"], thread: threads[1])
        XCTAssertEqual(pane.ticked([2], in: threads, showing: ["7/149"]), 2)
        XCTAssertEqual(ids(pane.end(in: threads, showing: ["7/148"])), ["7/149"],
                       "nothing taken out of Edit mode, nothing kept")
    }

    /// A lost answer's look (B-151) finding the letter the pane had opened
    /// before Edit mode gone during it: not put back as Edit mode ends,
    /// from its row nor from the row it had, nor from its conversation's row
    /// left with another letter, the pane emptied as the look empties it;
    /// another letter of its conversation gone leaves it to
    /// come back; nothing out of Edit mode, and nothing kept for the next.
    /// Read from the list: told by the list's `movedAfterAll` in Edit mode,
    /// whether the rows go now or wait for the ticks to be let go.
    func testALetterBeforeALostAnswersLookFoundGoneIsNotPutBack() throws {
        let threads = self.threads
        var pane = EditPane()
        pane.begin(showing: ["7/149"], thread: threads[1])
        XCTAssertEqual(pane.ticked([2], in: threads, showing: ["7/149"]), 2)
        pane.gone([letter(149, thread: "B")])
        guard case .empty = pane.end(in: threads.filter { $0.id != "7/149" }, showing: ["7/148"]) else {
            return XCTFail("gone after all: not from the row it had")
        }

        pane.begin(showing: ["7/149"], thread: threads[1])
        XCTAssertEqual(pane.ticked([2], in: threads, showing: ["7/149"]), 2)
        pane.gone([letter(149, thread: "B")])
        guard case .empty = pane.end(in: threads, showing: ["7/148"]) else {
            return XCTFail("gone, its row held for the ticks")
        }

        pane.begin(showing: ["7/150", "7/147"], thread: threads[0])
        XCTAssertEqual(pane.ticked([2], in: threads, showing: ["7/150", "7/147"]), 2)
        pane.gone([letter(147, thread: "A")])
        XCTAssertEqual(ids(pane.end(in: threads, showing: ["7/148"])), ["7/150", "7/147"],
                       "another letter of its conversation")

        pane.begin(showing: ["7/150", "7/147"], thread: threads[0])
        XCTAssertEqual(pane.ticked([2], in: threads, showing: ["7/150", "7/147"]), 2)
        pane.gone([letter(150, thread: "A")])
        let without = MessageThread.rows(for: [letter(149, thread: "B"), letter(148, thread: "C"),
                                               letter(147, thread: "A")], grouped: true)
        guard case .empty = pane.end(in: without, showing: ["7/148"]) else {
            return XCTFail("gone, its conversation's row left with another letter")
        }

        pane.gone([letter(149, thread: "B")])
        pane.begin(showing: ["7/149"], thread: threads[1])
        XCTAssertEqual(pane.ticked([2], in: threads, showing: ["7/149"]), 2)
        XCTAssertEqual(ids(pane.end(in: threads, showing: ["7/148"])), ["7/149"],
                       "nothing out of Edit mode, nothing kept")

        let list = flat(try source("UI/MessageListViewController.swift"))
        let moved = flat(body(after: "func movedAfterAll(", in: list))
        XCTAssertTrue(moved.hasPrefix("{ if inEditMode { editPane.gone(moved.compactMap { m in "
                                      + "letters.letter(m.id).flatMap { $0.gmailMessageID == m.gmailMessageID "
                                      + "? $0 : nil } }) } let here = "), moved)
    }

    /// The pane gone on from the ticked letter, as after its own Delete, is
    /// left; a letter before that the list has lost comes back from the row
    /// it had; and Edit mode, once ended, has nothing more to put back.
    func testThePaneIsLeftWhereItWentOnAndEditModeEndsOnce() {
        let threads = self.threads
        var pane = EditPane()
        pane.begin(showing: ["7/149"], thread: threads[1])
        XCTAssertEqual(pane.ticked([2], in: threads, showing: ["7/149"]), 2)
        guard case .stay = pane.end(in: threads, showing: ["7/150"]) else {
            return XCTFail("the pane went on")
        }
        guard case .stay = pane.end(in: threads, showing: ["7/148"]) else {
            return XCTFail("ended once")
        }

        pane.begin(showing: ["7/149"], thread: threads[1])
        XCTAssertEqual(pane.ticked([0], in: threads, showing: ["7/149"]), 0)
        let without = threads.filter { $0.id != "7/149" }
        XCTAssertEqual(ids(pane.end(in: without, showing: ["7/150"])), ["7/149"])

        // The second of two ticks left alone puts its letter in the pane.
        pane.begin(showing: ["7/149"], thread: threads[1])
        XCTAssertNil(pane.ticked([0, 2], in: threads, showing: ["7/149"]))
        XCTAssertEqual(pane.ticked([2], in: threads, showing: ["7/149"]), 2)
    }

    // MARK: - The controllers, read

    /// Every change of the ticks, and Edit mode's beginning and end, set
    /// the bar, the title and the pane's dimming by the rules; one tick puts
    /// its letter in the pane with no read mark; Edit mode begins with the
    /// pane's letter remembered and ends with it put back before the row is
    /// highlighted again; Edit's button follows the rows.
    func testTheListFollowsTheTicks() throws {
        let list = try source("UI/MessageListViewController.swift")
        let update = flat(body(after: "private func updateSelectAllTitle()", in: list))
        inOrder(["let ticked = inEditMode ? (tableView.indexPathsForSelectedRows?.count ?? 0) : 0",
                 "for item in [markItem, moveItem, deleteItem] { item?.isEnabled = "
                    + "EditBar.acts(ticked: ticked) }",
                 "title = EditBar.title(ticked: ticked, folder: mailbox.displayName)",
                 "onPaneDimmed?(EditBar.dimsPane(editing: inEditMode, ticked: ticked))"],
                in: update)

        let follows = flat(body(after: "private func paneFollowsTicks()", in: list))
        inOrder(["editPane.ticked(ticked, in: threads, showing: lettersInPane(), "
                    + "opens: mailbox.role != .drafts && !isOutbox)",
                 "showInPane(threads[row])"], in: follows)
        let show = flat(body(after: "private func showInPane(_ thread: MessageThread)", in: list))
        XCTAssertTrue(show.contains("onSelectThread?(thread, CompleteThreads.thread("))
        XCTAssertTrue(show.contains("onSelectMessage?(thread.newest)"))
        XCTAssertFalse(show.contains("markRead"), "no read mark for a tick")
        let back = flat(body(after: "private func putPaneBack()", in: list))
        inOrder(["editPane.end(in: threads, showing: lettersInPane())",
                 "case .empty: onPaneEmptied?()",
                 "case .letters(let thread): showInPane(thread)"], in: back)

        let select = flat(body(after: "didSelectRowAt ip: IndexPath)", in: list))
        XCTAssertTrue(select.contains("guard !inEditMode else { updateSelectAllTitle(); "
                                      + "paneFollowsTicks(); return }"))
        let deselect = flat(body(after: "didDeselectRowAt ip: IndexPath)", in: list))
        inOrder(["guard inEditMode else { return }", "updateSelectAllTitle()",
                 "paneFollowsTicks()"], in: deselect)
        let all = flat(body(after: "@objc private func selectAllTapped()", in: list))
        inOrder(["updateSelectAllTitle()", "paneFollowsTicks()"], in: all)

        let edit = flat(body(after: "@objc private func editTapped()", in: list))
        inOrder(["let editing = !inEditMode",
                 "if editing { let shown = lettersInPane() editPane.begin(showing: shown, thread: "
                    + "ListEdit.paneRow(in: threads, showing: shown).map { threads[$0] }) } "
                    + "else { putPaneBack() }",
                 "inEditMode = editing",
                 "tableView.setEditing(editing, animated: true)",
                 "drawRowsInSight(.editMode)",
                 "updateSelectAllTitle()",
                 "if !editing { highlightLetterInPane()"], in: edit)

        // Edit mode ended first, then Edit's button by the rows; then, still
        // in Edit mode, the bar, the title and the pane by the ticks left.
        let empty = flat(body(after: "private func updateEmptyState()", in: list))
        inOrder(["if EditBar.ends(rows: rows.count, editing: inEditMode, "
                    + "searching: letters.isSearching) { editTapped() }",
                 "navigationItem.rightBarButtonItem?.isEnabled = "
                    + "EditBar.canEdit(rows: rows.count, editing: inEditMode)",
                 "if inEditMode { updateSelectAllTitle() paneFollowsTicks() }"],
                in: empty)
        XCTAssertEqual(empty.components(separatedBy: "isEnabled = ").count - 1, 1)
        XCTAssertTrue(flat(list).contains("letters.changed = { [weak self] change in "
                                          + "self?.regroup(for: change) self?.updateEmptyState() }"))
        // And as Cancel ends it, a list with no rows, by Edit mode as it is
        // to be.
        inOrder(["navigationItem.rightBarButtonItem?.title = editing ? EditBar.cancel : EditBar.edit",
                 "if editing { deleteItem.title = discardWord }",
                 "navigationItem.rightBarButtonItem?.isEnabled = "
                    + "EditBar.canEdit(rows: rows.count, editing: editing)"], in: edit)
        // The bar's Delete and Move tell the pane what they take before
        // ending Edit mode (`EditPane.taking`).
        XCTAssertTrue(flat(list).contains("private func delete(_ chosen: [MessageSummary]) { "
                                          + "if inEditMode { editPane.taking(chosen) editTapped() }"))
        XCTAssertTrue(flat(list).contains("if self.inEditMode { self.editPane.taking(chosen) "
                                          + "self.editTapped() } self.runBatch(.move(to: destination)"))
        XCTAssertEqual(flat(list).components(separatedBy: "editPane.taking(").count - 1, 2)
        // Every cell drawn with its ticks, made, coming into sight, and in
        // sight as Edit mode begins and ends (`RowParts.ticks`).
        XCTAssertTrue(flat(list).contains("if parts.contains(.ticks) { cell.ticks = inEditMode }"))
        XCTAssertTrue(RowParts.whole.contains(.ticks))
        XCTAssertTrue(RowParts.patchesInSight.contains(.editMode))
    }

    /// The container hands the list's pane calls to the pane, from the list
    /// on the screen alone, and undims the pane as another folder opens.
    func testTheContainerEmptiesAndDimsThePane() throws {
        let root = flat(try source("UI/RootViewController.swift"))
        XCTAssertTrue(root.contains("list.onPaneEmptied = { [weak self, weak bound] in guard let self, "
                                    + "let bound, bound === self.list else { return } "
                                    + "self.detail.showEmpty() }"))
        XCTAssertTrue(root.contains("list.onPaneDimmed = { [weak self, weak bound] dim in guard let self, "
                                    + "let bound, bound === self.list else { return } "
                                    + "self.detail.dimForEdit(dim) }"))
        XCTAssertTrue(root.contains("listNav.setViewControllers([list], animated: false) "
                                    + "detail.showEmpty() detail.dimForEdit(false)"))
    }

    /// Dimmed: the letter and its header see-through over the black, the
    /// bar above them dimmed, and the letter's buttons off while it lasts,
    /// whatever shows or empties the pane meanwhile; Compose still on.
    func testThePaneDimsItsLetterAndItsButtons() throws {
        let pane = try source("UI/MessageDetailViewController.swift")
        let dim = flat(body(after: "func dimForEdit(_ dim: Bool)", in: pane))
        inOrder(["guard dim != editDimmed else { return }", "editDimmed = dim",
                 "header.alpha = dim ? Self.editDim : 1",
                 "webView.alpha = dim ? Self.editDim : 1",
                 "navigationController?.navigationBar.tintAdjustmentMode = dim ? .dimmed : .automatic",
                 "setActionsEnabled(summary != nil)"], in: dim)
        let enable = flat(body(after: "private func setActionsEnabled(_ enabled: Bool)", in: pane))
        inOrder(["let enabled = enabled && !editDimmed",
                 "for item in actionItems.values { item.isEnabled = enabled }",
                 "actionItems[.compose]?.isEnabled = true"], in: enable)
        XCTAssertTrue(flat(pane).contains("private static let editDim: CGFloat = 0.57"))
    }

    /// Dimmed, the letter's files and pictures are no more to be tapped
    /// than its buttons: a tap on one, or a finger held on it, opens
    /// nothing, so Markup and Reply cannot open a Reply the greyed Reply
    /// button would not. Nothing changes in how the pane looks.
    func testTheDimmedLettersFilesAndPicturesAreNotToBeTapped() throws {
        let pane = try source("UI/MessageDetailViewController.swift")
        let open = flat(body(after: "private func openAttachment(_ attachment: Attachment, of letter: Message? = nil, "
                             + "for item: PanePictures.Item = .quickLook)", in: flat(pane)))
        XCTAssertTrue(open.hasPrefix("{ guard !editDimmed, let m = letter ?? message else { return }"), open)
        let picture = flat(body(after: "private func holdPicture(_ tap: PanePictures.Tap)", in: pane))
        XCTAssertTrue(picture.hasPrefix("{ guard presentedViewController == nil, !editDimmed, let opening = "),
                      picture)
        let file = flat(body(after: "private func holdFile(_ held: BodyFiles.Hold)", in: pane))
        XCTAssertTrue(file.hasPrefix("{ guard presentedViewController == nil, !editDimmed, let (m, file) = "),
                      file)
    }

    /// A ticked row in Mail's blue with the tick white, its grey lines in
    /// Mail's see-through grey, set as Edit mode begins and as the row is
    /// selected; the grey of the letter in the pane out of Edit mode.
    func testATickedRowIsBlueWithAWhiteTick() throws {
        let cell = try source("UI/MessageCell.swift")
        XCTAssertTrue(flat(cell).contains("var ticks = false { didSet { guard ticks != oldValue "
                                          + "else { return } colour() } }"))
        XCTAssertTrue(flat(cell).contains("private static let tickedGrey = UIColor(red: 235 / 255, "
                                          + "green: 235 / 255, blue: 245 / 255, alpha: 0.6)"))
        XCTAssertTrue(flat(cell).contains("private var ticked: Bool { ticks && isSelected }"))
        XCTAssertTrue(flat(cell).contains("override func setSelected(_ selected: Bool, animated: Bool) "
                                          + "{ super.setSelected(selected, animated: animated) colour() }"))
        let colour = flat(body(after: "private func colour()", in: cell))
        inOrder(["selectedGround.backgroundColor = ticks ? Theme.tintBlue : Theme.selection",
                 "tintColor = ticks ? .white : nil",
                 "timestampLabel.textColor = grey",
                 "unreadDot.backgroundColor = ticked ? .white : Theme.tintBlue",
                 "drawPreview()"], in: colour)
        XCTAssertTrue(flat(body(after: "private func drawPreview()", in: cell))
                        .contains(".foregroundColor: grey"))
        XCTAssertTrue(flat(cell).contains("selectedBackgroundView = selectedGround"))
    }

    /// From iOS 17 UIKit draws the tick's check white on a disc in the
    /// tint, white on white in a ticked row's white tint, so the row draws
    /// its own over it: the check in the row's blue on a white disc,
    /// inside UIKit's edit control at UIKit's frame and size, hidden on a
    /// row not ticked, moving nothing (B-174, the iOS 17.5 and 18.6
    /// simulators). Behind a run-time check of 17, so 16 runs the old path
    /// alone: the white tint and nothing else.
    func testFromIOS17TheRowDrawsItsOwnTickOverUIKits() throws {
        let cell = try source("UI/MessageCell.swift")
        let code = flat(cell)
        XCTAssertFalse(cell.contains("#available"))
        XCTAssertTrue(code.contains("private static let drawsOwnTick = ProcessInfo.processInfo"
                                    + ".isOperatingSystemAtLeast( OperatingSystemVersion(majorVersion: 17, "
                                    + "minorVersion: 0, patchVersion: 0))"))
        XCTAssertTrue(code.contains("private static let tickPalette = "
                                    + "UIImage.SymbolConfiguration(paletteColors: [Theme.tintBlue, .white])"),
                      "[check, disc]: the row's blue on white")
        XCTAssertTrue(code.contains("private lazy var tickMark: UIImageView = { let mark = UIImageView() "
                                    + "mark.isUserInteractionEnabled = false mark.isHidden = true return mark }()"),
                      "made only when first asked for, so never on 16")

        let layout = flat(body(after: "override func layoutSubviews()", in: cell))
        XCTAssertTrue(layout.hasPrefix("{ super.layoutSubviews() if Self.drawsOwnTick { placeTick() } "))
        let colour = flat(body(after: "private func colour()", in: cell))
        XCTAssertTrue(colour.contains("tintColor = ticks ? .white : nil if Self.drawsOwnTick { "
                                      + "tickMark.isHidden = !ticked setNeedsLayout() } let grey = self.grey"),
                      "the tint as on 16, and the tick shown or hidden before the early return")

        let place = flat(body(after: "private func placeTick()", in: cell))
        inOrder(["guard ticked, let control = subviews.first(where: { $0 is UIControl }),",
                 "let drawn = control.subviews.first(where: { $0 is UIImageView && $0 !== tickMark }) "
                    + "as? UIImageView else { tickMark.isHidden = true return }",
                 "if tickMark.superview !== control { control.addSubview(tickMark) } "
                    + "else { control.bringSubviewToFront(tickMark) }",
                 "tickMark.preferredSymbolConfiguration = drawn.preferredSymbolConfiguration",
                 "tickMark.image = UIImage(systemName: \"checkmark.circle.fill\", "
                    + "withConfiguration: Self.tickPalette)",
                 "tickMark.frame = drawn.frame",
                 "tickMark.isHidden = false"], in: place)
        for moved in ["drawn.frame =", "control.frame", "drawn.isHidden", "drawn.image ="] {
            XCTAssertFalse(place.contains(moved), "nothing of UIKit's is touched: \(moved)")
        }

        // Everything of the row's own tick is behind the check: the tick
        // reached in `colour` and `placeTick` alone, `placeTick` called in
        // `layoutSubviews` alone, each behind `drawsOwnTick`.
        XCTAssertEqual(count("placeTick()", in: code), 2, "its declaration and its one call")
        XCTAssertEqual(count("if Self.drawsOwnTick {", in: code), 2)
        XCTAssertEqual(count("tickMark", in: code), count("tickMark", in: place) + 2,
                       "its declaration and colour's one use besides placeTick's")
        XCTAssertEqual(count("drawsOwnTick", in: code), 3)
    }

    // MARK: - Reading the source

    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func body(after opener: String, in code: String,
                      file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let start = code.range(of: opener),
              let brace = code[start.upperBound...].firstIndex(of: "{") else {
            XCTFail("no \(opener)", file: file, line: line)
            return ""
        }
        var depth = 0
        var i = brace
        while i < code.endIndex {
            if code[i] == "{" { depth += 1 }
            if code[i] == "}" {
                depth -= 1
                if depth == 0 { return String(code[brace...i]) }
            }
            i = code.index(after: i)
        }
        XCTFail("unclosed \(opener)", file: file, line: line)
        return ""
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).joined(separator: " ")
    }

    private func inOrder(_ parts: [String], in text: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        var from = text.startIndex
        for part in parts {
            guard let found = text.range(of: part, range: from..<text.endIndex) else {
                XCTFail("missing or out of order: \(part)", file: file, line: line)
                return
            }
            from = found.upperBound
        }
    }
}
