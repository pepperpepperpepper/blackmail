import XCTest
@testable import Blackmail

/// VoiceOver kept on its letter when the message list's rows are drawn
/// again (B-079, the second change). `ListVoiceOver` decides, with the real
/// grouping; `MessageListViewController` finds the row VoiceOver is on and
/// names the cell. On the test iPad the cell named for a folder's first row was handed
/// out again when its fresh page was drawn over the kept one: VoiceOver read
/// the second row's words in the first row's box, then went to the view
/// button.
///
/// And the third change: the row held after VoiceOver has got there, and
/// put back once if VoiceOver leaves it by itself, as it did once in each
/// launch on the iPad; the same for the folder's row after "< Mailboxes"
/// (`FoldersVoiceOver`); and the least scroll that shows a row whole
/// before VoiceOver is put on it (`TableSight`).
final class ListVoiceOverTests: XCTestCase {

    private func letter(_ uid: Int, thread: String) -> MessageSummary {
        MessageSummary(id: "7/\(uid)", mailboxID: "INBOX",
                       sender: "Sam Example <sam@example.com>",
                       subject: "About \(thread)", preview: "",
                       date: Date(timeIntervalSince1970: 1_790_000_000 + Double(uid) * 3_600),
                       isRead: true, isFlagged: false, threadID: thread)
    }

    private func rows(_ letters: [MessageSummary]) -> [MessageThread] {
        MessageThread.rows(for: letters, grouped: true)
    }

    /// A kept page: four conversations, one letter each, A the newest.
    private var kept: [MessageSummary] {
        [letter(104, thread: "A"), letter(103, thread: "B"), letter(102, thread: "C"),
         letter(101, thread: "D")]
    }

    private func row(_ index: Int, in letters: [MessageSummary]) throws -> ListVoiceOver.Row {
        try XCTUnwrap(ListVoiceOver.Row(index, in: rows(letters)))
    }

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - The row after the rows are drawn again

    /// The fresh page with a letter come on top: the letter VoiceOver was
    /// on is now the second row down, and that is the row, not the first.
    func testTheRowThatNowShowsTheSameLetter() throws {
        let fresh = [letter(105, thread: "E")] + kept
        XCTAssertEqual(ListVoiceOver.step(after: try row(0, in: kept), in: rows(fresh)), .same(1))
        XCTAssertEqual(ListVoiceOver.step(after: try row(2, in: kept), in: rows(fresh)), .same(3))
        // The same rows: the same row.
        XCTAssertEqual(ListVoiceOver.step(after: try row(1, in: kept), in: rows(kept)), .same(1))
    }

    /// A newer letter has joined the conversation and taken its row to the
    /// top: found by the letter that was in it.
    func testAConversationJoinedByANewerLetterIsFoundByItsLetters() throws {
        let joined = [letter(105, thread: "C")] + kept
        let after = rows(joined)
        XCTAssertEqual(after.first?.messages.map(\.id), ["7/105", "7/102"])
        XCTAssertEqual(ListVoiceOver.step(after: try row(2, in: kept), in: after), .same(0))
    }

    /// The letter gone: the row now in its place, the one that came after
    /// it; the last gone, the row now last.
    func testItsLetterGoneTheRowInItsPlace() throws {
        let withoutB = kept.filter { $0.threadID != "B" }
        XCTAssertEqual(ListVoiceOver.step(after: try row(1, in: kept), in: rows(withoutB)), .inPlace(1))
        let withoutD = kept.filter { $0.threadID != "D" }
        XCTAssertEqual(ListVoiceOver.step(after: try row(3, in: kept), in: rows(withoutD)), .inPlace(2))
    }

    /// No rows left: the table, whose first element VoiceOver takes.
    func testNoRowsTheTable() throws {
        XCTAssertEqual(ListVoiceOver.step(after: try row(0, in: kept), in: []), .table)
    }

    /// Held nothing: nothing posted.
    func testNothingHeldNothingPosted() {
        XCTAssertEqual(ListVoiceOver.step(after: nil, in: rows(kept)), .leave)
        XCTAssertNil(ListVoiceOver.Row(4, in: rows(kept)))
        XCTAssertNil(ListVoiceOver.Row(-1, in: rows(kept)))
    }

    // MARK: - Which row is held

    /// VoiceOver off: nothing held, whatever it was sent to, so nothing is
    /// posted.
    func testVoiceOverOffHoldsNothing() throws {
        var voiceOver = ListVoiceOver()
        XCTAssertNil(voiceOver.held(running: false, on: try row(1, in: kept), landing: .otherRow,
                                    at: start))
        voiceOver.send(to: try row(1, in: kept), running: false, at: start)
        XCTAssertNil(voiceOver.sentRow(at: start))
        XCTAssertNil(voiceOver.held(running: true, on: nil, landing: .elsewhere, at: start))
        XCTAssertNil(voiceOver.held(running: false, on: nil, landing: .elsewhere, at: start))
    }

    /// VoiceOver on something that is not a row of the list, the folders,
    /// the reading pane, a sheet, the search field, the list's bar, and not
    /// sent to one: nothing held.
    func testVoiceOverElsewhereHoldsNothing() {
        let voiceOver = ListVoiceOver()
        for landing in [ListVoiceOver.Landing.elsewhere, .beside, .listOwn, .listBar, .typing] {
            XCTAssertNil(voiceOver.held(running: true, on: nil, landing: landing, at: start))
            XCTAssertEqual(ListVoiceOver.step(after: voiceOver.held(running: true, on: nil,
                                                                    landing: landing, at: start),
                                              in: rows(kept)), .leave)
        }
    }

    /// VoiceOver on a row of the list: that row.
    func testVoiceOverOnARowHoldsIt() throws {
        let voiceOver = ListVoiceOver()
        XCTAssertEqual(voiceOver.held(running: true, on: try row(2, in: kept), landing: .otherRow,
                                      at: start),
                       try row(2, in: kept))
    }

    /// Sent to a row: that row, over another row VoiceOver is on or the
    /// list's own bar, for the bound at most. VoiceOver took about 1.3
    /// seconds to get there on the iPad. Over the folders or the reading
    /// pane only while it is on its way, before the screen change has
    /// landed.
    func testARowSentToIsHeldUntilTheBound() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        let soon = start.addingTimeInterval(1.3)
        for away in [ListVoiceOver.Landing.elsewhere, .beside] {
            XCTAssertEqual(voiceOver.held(running: true, on: nil, landing: away, at: soon),
                           try row(0, in: kept))
        }
        XCTAssertEqual(voiceOver.held(running: true, on: try row(3, in: kept), landing: .otherRow,
                                      at: soon),
                       try row(0, in: kept))
        let bound = start.addingTimeInterval(ListVoiceOver.bound)
        XCTAssertEqual(voiceOver.sentRow(at: bound), try row(0, in: kept))
        for own in [ListVoiceOver.Landing.listOwn, .listBar] {
            XCTAssertEqual(voiceOver.held(running: true, on: nil, landing: own, at: bound),
                           try row(0, in: kept))
        }
        let later = bound.addingTimeInterval(0.1)
        XCTAssertNil(voiceOver.sentRow(at: later))
        XCTAssertEqual(voiceOver.held(running: true, on: try row(3, in: kept), landing: .otherRow,
                                      at: later),
                       try row(3, in: kept))
        XCTAssertNil(voiceOver.held(running: true, on: nil, landing: .elsewhere, at: later))
        XCTAssertNil(voiceOver.held(running: true, on: nil, landing: .listOwn, at: later))
        XCTAssertNil(voiceOver.held(running: true, on: nil, landing: .listBar, at: later))
        XCTAssertLessThanOrEqual(ListVoiceOver.bound, 3)
    }

    /// Sent to a row and still held, but VoiceOver on the folders, the
    /// reading pane or a sheet once the screen change has landed: his, and
    /// nothing held. On the iPad it landed 1.3 to 1.6 s after the tap.
    func testElsewhereOnceTheScreenChangeHasLandedHoldsNothing() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        let landed = start.addingTimeInterval(ListVoiceOver.screenChange)
        for away in [ListVoiceOver.Landing.elsewhere, .beside] {
            XCTAssertEqual(voiceOver.held(running: true, on: nil, landing: away,
                                          at: landed.addingTimeInterval(-0.05)),
                           try row(0, in: kept))
            XCTAssertNil(voiceOver.held(running: true, on: nil, landing: away, at: landed))
        }
        XCTAssertEqual(voiceOver.sentRow(at: landed), try row(0, in: kept))
        XCTAssertGreaterThanOrEqual(ListVoiceOver.screenChange, 1.6)
        XCTAssertLessThan(ListVoiceOver.screenChange, ListVoiceOver.bound)
    }

    /// Sent to a row and still held, but he is typing in the search field,
    /// or VoiceOver is on a key: nothing held, at any time, so VoiceOver is
    /// not taken off the keys.
    func testTypingHoldsNothing() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        for after in [0.2, 1.0, 2.0] {
            XCTAssertNil(voiceOver.held(running: true, on: nil, landing: .typing,
                                        at: start.addingTimeInterval(after)), "\(after)")
        }
    }

    /// Sent to the table, for a folder with no rows yet: nothing held. The
    /// table is not handed out again.
    func testTheTableSentToHoldsNothing() {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: nil, running: true, at: start)
        XCTAssertNil(voiceOver.sentRow(at: start))
    }

    /// The list's column out of sight, after "< Mailboxes": let go.
    func testLetGo() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        voiceOver.letGo()
        XCTAssertNil(voiceOver.sentRow(at: start))
        XCTAssertNil(voiceOver.held(running: true, on: nil, landing: .listOwn, at: start))
    }

    // MARK: - Letting go

    /// The rows drawn again while VoiceOver is on its way: the row held goes
    /// with its letter.
    func testTheRowHeldFollowsItsLetter() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        let fresh = [letter(105, thread: "E")] + kept
        voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)))
        let held = try XCTUnwrap(voiceOver.sentRow(at: start.addingTimeInterval(0.6)))
        XCTAssertEqual(held.index, 1)
        XCTAssertEqual(ListVoiceOver.step(after: held, in: rows(fresh)), .same(1))
    }

    /// VoiceOver there while the rows are the kept page: held through the
    /// fresh page, on the row for its letter, and after it, to the bound.
    /// On the iPad the Inbox opened anew had its fresh page 1.55 s after the
    /// tap, after VoiceOver had got there at 1.42 s.
    func testThereOnTheKeptPageItIsHeldThroughTheFreshPage() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        let there = start.addingTimeInterval(1.42)
        XCTAssertNil(voiceOver.moved(to: .sentRow, at: there))
        XCTAssertEqual(voiceOver.sentRow(at: there), try row(0, in: kept))
        // The kept page drawn again: still held.
        voiceOver.redrawn(to: try row(0, in: kept))
        XCTAssertEqual(voiceOver.sentRow(at: there), try row(0, in: kept))
        // The fresh page, a letter come on top: held on its letter's row.
        let fresh = [letter(105, thread: "E")] + kept
        voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)))
        XCTAssertEqual(voiceOver.sentRow(at: start.addingTimeInterval(1.55))?.index, 1)
        // On it again, from the list's own post: still held, to the bound.
        XCTAssertNil(voiceOver.moved(to: .sentRow, at: start.addingTimeInterval(1.6)))
        XCTAssertEqual(voiceOver.sentRow(at: start.addingTimeInterval(ListVoiceOver.bound))?.index, 1)
        XCTAssertNil(voiceOver.sentRow(at: start.addingTimeInterval(ListVoiceOver.bound + 0.1)))
    }

    /// There, with the fresh page drawn already, or a folder with no kept
    /// page, and nothing posted by the list: still held, to the bound. It
    /// was let go at once here, and VoiceOver, leaving the row by itself
    /// 0.9 s later, was left on the reading pane's Flag.
    func testThereOnTheFreshPageItStaysHeld() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(3, in: kept), running: true, at: start)
        XCTAssertNil(voiceOver.moved(to: .sentRow, at: start.addingTimeInterval(1.11)))
        XCTAssertEqual(voiceOver.sentRow(at: start.addingTimeInterval(1.11)), try row(3, in: kept))
        XCTAssertEqual(voiceOver.held(running: true, on: try row(3, in: kept), landing: .sentRow,
                                      at: start.addingTimeInterval(2)),
                       try row(3, in: kept))
        XCTAssertEqual(voiceOver.sentRow(at: start.addingTimeInterval(ListVoiceOver.bound)),
                       try row(3, in: kept))
    }

    /// Gone to another of the list's rows, or to a cell drawn since for
    /// another letter: put on the row it was sent to, once.
    func testGoneToAnotherRowItIsPutThereOnce() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        let landed = start.addingTimeInterval(1.3)
        XCTAssertEqual(voiceOver.moved(to: .otherRow, at: landed), try row(0, in: kept))
        XCTAssertNil(voiceOver.sentRow(at: landed))
        XCTAssertNil(voiceOver.moved(to: .otherRow, at: landed))
    }

    /// Landed straight on the list's own bar, the view button, as in Sent
    /// Mail and the Inbox opened anew on the iPad, or on its table, before
    /// ever being on the row, within the bound: put on the row, once, the
    /// fresh page drawn or not. Then let go.
    func testLandedOnTheListsOwnBarBeforeTheRowItIsPutThereOnce() throws {
        let fresh = [letter(105, thread: "E")] + kept
        for redrawn in [false, true] {
            var voiceOver = ListVoiceOver()
            voiceOver.send(to: try row(0, in: kept), running: true, at: start)
            if redrawn {
                voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)))
            }
            let landed = start.addingTimeInterval(1.33)
            let put = try XCTUnwrap(voiceOver.moved(to: .listBar, at: landed))
            XCTAssertEqual(put.index, redrawn ? 1 : 0)
            XCTAssertNil(voiceOver.sentRow(at: landed))
            XCTAssertNil(voiceOver.moved(to: .listBar, at: landed))
        }
        // Its table, or the search field: the same.
        var table = ListVoiceOver()
        table.send(to: try row(0, in: kept), running: true, at: start)
        XCTAssertEqual(table.moved(to: .listOwn, at: start.addingTimeInterval(1.33)), try row(0, in: kept))
        XCTAssertNil(table.moved(to: .listOwn, at: start.addingTimeInterval(1.4)))
        // As late as the bound, and not after it.
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        XCTAssertEqual(voiceOver.moved(to: .listOwn, at: start.addingTimeInterval(ListVoiceOver.bound)),
                       try row(0, in: kept))
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        XCTAssertNil(voiceOver.moved(to: .listOwn, at: start.addingTimeInterval(ListVoiceOver.bound + 0.1)))
    }

    /// There through the list's own post, after the fresh page, sooner than
    /// the screen change could land: held. The screen change then lands on
    /// the cell it named, now another letter's, or on the view button: put
    /// back on the row, once.
    func testThereThroughTheListsOwnPostAStaleLandingIsPutBackOnce() throws {
        let fresh = [letter(105, thread: "E")] + kept
        for stale in [ListVoiceOver.Landing.otherRow, .listOwn, .listBar] {
            var voiceOver = ListVoiceOver()
            voiceOver.send(to: try row(0, in: kept), running: true, at: start)
            voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)))
            let there = start.addingTimeInterval(0.7)
            XCTAssertNil(voiceOver.moved(to: .sentRow, at: there))
            XCTAssertEqual(voiceOver.sentRow(at: there)?.index, 1)
            // On the row again: still held.
            XCTAssertNil(voiceOver.moved(to: .sentRow, at: start.addingTimeInterval(1)))
            let landed = start.addingTimeInterval(1.3)
            XCTAssertEqual(voiceOver.moved(to: stale, at: landed)?.index, 1, "\(stale)")
            XCTAssertNil(voiceOver.sentRow(at: landed))
            XCTAssertNil(voiceOver.moved(to: stale, at: landed))
        }
    }

    /// There early, and another reload before the screen change could land:
    /// still held, on the cell for its letter.
    func testThereEarlyAnotherReloadStillHolds() throws {
        let fresh = [letter(105, thread: "E")] + kept
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)))
        XCTAssertNil(voiceOver.moved(to: .sentRow, at: start.addingTimeInterval(0.7)))
        voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)))
        XCTAssertEqual(voiceOver.sentRow(at: start.addingTimeInterval(0.9))?.index, 1)
        XCTAssertEqual(voiceOver.moved(to: .otherRow, at: start.addingTimeInterval(1.3))?.index, 1)
    }

    /// There early, but the move comes once the screen change has landed,
    /// to another row, the search field, a sheet or the keys: his, and let
    /// go with nothing posted. A reload then keeps it held.
    func testThereEarlyAMoveOnceTheScreenChangeHasLandedIsHis() throws {
        let fresh = [letter(105, thread: "E")] + kept
        let landed = start.addingTimeInterval(ListVoiceOver.screenChange)
        for move in [ListVoiceOver.Landing.otherRow, .listOwn, .elsewhere, .typing] {
            var voiceOver = ListVoiceOver()
            voiceOver.send(to: try row(0, in: kept), running: true, at: start)
            voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)))
            XCTAssertNil(voiceOver.moved(to: .sentRow, at: start.addingTimeInterval(0.7)))
            XCTAssertNil(voiceOver.moved(to: move, at: landed), "\(move)")
            XCTAssertNil(voiceOver.sentRow(at: landed), "\(move)")
        }
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)))
        XCTAssertNil(voiceOver.moved(to: .sentRow, at: start.addingTimeInterval(0.7)))
        voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)))
        XCTAssertEqual(voiceOver.sentRow(at: landed)?.index, 1)
    }

    /// There early, then on a sheet, or typing: let go, and never put back
    /// from there.
    func testThereEarlyThenElsewhereLetsGo() throws {
        let fresh = [letter(105, thread: "E")] + kept
        for move in [ListVoiceOver.Landing.elsewhere, .typing] {
            var voiceOver = ListVoiceOver()
            voiceOver.send(to: try row(0, in: kept), running: true, at: start)
            voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)))
            XCTAssertNil(voiceOver.moved(to: .sentRow, at: start.addingTimeInterval(0.7)))
            XCTAssertNil(voiceOver.moved(to: move, at: start.addingTimeInterval(1)), "\(move)")
            XCTAssertNil(voiceOver.sentRow(at: start.addingTimeInterval(1)), "\(move)")
        }
    }

    /// Not yet on the list: what it was on went out of sight with the
    /// folders, and it is still on its way. Nothing posted, and the row
    /// still held, for the fresh page and for its getting there.
    func testNotYetOnTheListTheRowStaysHeld() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        let away = start.addingTimeInterval(0.5)
        XCTAssertNil(voiceOver.moved(to: .elsewhere, at: away))
        XCTAssertNil(voiceOver.moved(to: .beside, at: away))
        XCTAssertEqual(voiceOver.sentRow(at: away), try row(0, in: kept))
        XCTAssertEqual(voiceOver.held(running: true, on: nil, landing: .beside, at: away),
                       try row(0, in: kept))
        // Then onto a cell drawn since for another letter: put there, once.
        let landed = start.addingTimeInterval(1.3)
        XCTAssertEqual(voiceOver.moved(to: .otherRow, at: landed), try row(0, in: kept))
        XCTAssertNil(voiceOver.sentRow(at: landed))
    }

    /// On the folders, the reading pane or a sheet once the screen change
    /// has landed, never having been on the row: his. Let go, nothing
    /// posted.
    func testElsewhereOnceTheScreenChangeHasLandedLetsGo() throws {
        for away in [ListVoiceOver.Landing.elsewhere, .beside] {
            var voiceOver = ListVoiceOver()
            voiceOver.send(to: try row(0, in: kept), running: true, at: start)
            let landed = start.addingTimeInterval(ListVoiceOver.screenChange)
            XCTAssertNil(voiceOver.moved(to: away, at: landed), "\(away)")
            XCTAssertNil(voiceOver.sentRow(at: landed), "\(away)")
            XCTAssertNil(voiceOver.moved(to: .listOwn, at: landed), "\(away)")
        }
    }

    /// He types in the search field, or VoiceOver is on a key, before it
    /// has been on the row: let go, nothing posted, and nothing put back
    /// after.
    func testLandedWhileTypingLetsGo() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        XCTAssertNil(voiceOver.moved(to: .typing, at: start.addingTimeInterval(1)))
        XCTAssertNil(voiceOver.sentRow(at: start.addingTimeInterval(1)))
        XCTAssertNil(voiceOver.moved(to: .listOwn, at: start.addingTimeInterval(1.3)))
    }

    /// Once VoiceOver has been there, a move to what he can swipe to from a
    /// row, another row, the search field or the toolbar, or to a sheet or
    /// the keys, is his: let go, and nothing posted, then or after. A row he
    /// has swiped to is not taken from him.
    func testAMoveAfterItWasThereLetsGo() throws {
        for move in [ListVoiceOver.Landing.otherRow, .listOwn, .elsewhere, .typing] {
            var voiceOver = ListVoiceOver()
            voiceOver.send(to: try row(0, in: kept), running: true, at: start)
            XCTAssertNil(voiceOver.moved(to: .sentRow, at: start.addingTimeInterval(1.3)))
            XCTAssertNil(voiceOver.moved(to: move, at: start.addingTimeInterval(1.5)),
                         "\(move)")
            XCTAssertNil(voiceOver.sentRow(at: start.addingTimeInterval(1.5)))
            XCTAssertNil(voiceOver.held(running: true, on: nil, landing: .listOwn,
                                        at: start.addingTimeInterval(2)))
            XCTAssertNil(voiceOver.moved(to: .beside, at: start.addingTimeInterval(2)), "\(move)")
        }
    }

    /// After the bound: nothing, and let go.
    func testAfterTheBoundNothing() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        XCTAssertNil(voiceOver.moved(to: .otherRow, at: start.addingTimeInterval(ListVoiceOver.bound + 0.5)))
        XCTAssertNil(voiceOver.sentRow(at: start))
    }

    /// The rows gone, the table named: nothing left to hold.
    func testTheTableNamedLetsGo() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        voiceOver.redrawn(to: nil)
        XCTAssertNil(voiceOver.sentRow(at: start))
    }

    /// Nothing sent: a reload or a move changes nothing.
    func testNothingSentNothingChanges() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.redrawn(to: try row(1, in: kept))
        XCTAssertNil(voiceOver.sentRow(at: start))
        for landing in [ListVoiceOver.Landing.sentRow, .otherRow, .listOwn, .listBar, .typing,
                        .beside, .elsewhere] {
            XCTAssertNil(voiceOver.moved(to: landing, at: start))
        }
    }

    // MARK: - VoiceOver leaving the row by itself (the third change)

    /// On the iPad, once in each launch: VoiceOver on the letter's row at
    /// 1.15 s, then by itself on the reading pane's Flag at 2.03 s; with the
    /// pane empty, on the view button in the list's bar. Put back on the
    /// row, once, and let go: a second leave is left where it goes.
    func testLeavingTheRowByItselfIsPutBackOnce() throws {
        for away in [ListVoiceOver.Landing.beside, .listBar] {
            var voiceOver = ListVoiceOver()
            voiceOver.send(to: try row(2, in: kept), running: true, at: start)
            XCTAssertNil(voiceOver.moved(to: .sentRow, at: start.addingTimeInterval(1.15)), "\(away)")
            XCTAssertEqual(voiceOver.moved(to: away, at: start.addingTimeInterval(2.03)),
                           try row(2, in: kept), "\(away)")
            XCTAssertNil(voiceOver.sentRow(at: start.addingTimeInterval(2.03)), "\(away)")
            // Put back, it is there again, and goes again: left.
            XCTAssertNil(voiceOver.moved(to: .sentRow, at: start.addingTimeInterval(2.2)), "\(away)")
            XCTAssertNil(voiceOver.moved(to: away, at: start.addingTimeInterval(2.5)), "\(away)")
        }
    }

    /// The same after the fresh page, there on the kept page first: put
    /// back on the row its letter is on now.
    func testLeavingAfterTheFreshPageIsPutBackOnItsLetter() throws {
        let fresh = [letter(105, thread: "E")] + kept
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        XCTAssertNil(voiceOver.moved(to: .sentRow, at: start.addingTimeInterval(1.42)))
        voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)))
        XCTAssertNil(voiceOver.moved(to: .sentRow, at: start.addingTimeInterval(1.6)))
        XCTAssertEqual(voiceOver.moved(to: .listBar, at: start.addingTimeInterval(2.3))?.index, 1)
        XCTAssertNil(voiceOver.sentRow(at: start.addingTimeInterval(2.3)))
    }

    /// Any time within the bound, the latest seen being 2.75 s on the iPad
    /// in the first round; not after it.
    func testLeavingIsPutBackOnlyWithinTheBound() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        XCTAssertNil(voiceOver.moved(to: .sentRow, at: start.addingTimeInterval(1.1)))
        XCTAssertEqual(voiceOver.moved(to: .beside, at: start.addingTimeInterval(2.75)),
                       try row(0, in: kept))
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        XCTAssertNil(voiceOver.moved(to: .sentRow, at: start.addingTimeInterval(1.1)))
        XCTAssertNil(voiceOver.moved(to: .beside,
                                     at: start.addingTimeInterval(ListVoiceOver.bound + 0.1)))
        XCTAssertNil(voiceOver.sentRow(at: start))
    }

    /// Let go, as when he opens a row or switches the panes: a leave after
    /// is not put back. And with VoiceOver off nothing is ever held.
    func testLetGoOrVoiceOverOffNothingIsPutBack() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        XCTAssertNil(voiceOver.moved(to: .sentRow, at: start.addingTimeInterval(1.1)))
        voiceOver.letGo()
        XCTAssertNil(voiceOver.moved(to: .beside, at: start.addingTimeInterval(2)))
        XCTAssertNil(voiceOver.moved(to: .listBar, at: start.addingTimeInterval(2)))
        var off = ListVoiceOver()
        off.send(to: try row(0, in: kept), running: false, at: start)
        for landing in [ListVoiceOver.Landing.sentRow, .beside, .listBar, .otherRow] {
            XCTAssertNil(off.moved(to: landing, at: start.addingTimeInterval(2)), "\(landing)")
        }
    }

    // MARK: - The folder's row after "< Mailboxes"

    /// On the iPad, VoiceOver turned on while the app ran: on the Inbox's
    /// row at 1.33 s, then by itself on Flag at 2.22 s. Put back, once. The
    /// same for the view button in the corner.
    func testTheFoldersRowLeftByItselfIsPutBackOnce() {
        for away in [FoldersVoiceOver.Landing.pane, .corner] {
            var folders = FoldersVoiceOver()
            folders.send(toRow: true, last: false, running: true, at: start)
            XCTAssertTrue(folders.holding(at: start), "\(away)")
            XCTAssertFalse(folders.moved(to: .sentRow, at: start.addingTimeInterval(1.33)), "\(away)")
            XCTAssertTrue(folders.holding(at: start.addingTimeInterval(1.33)), "\(away)")
            XCTAssertTrue(folders.moved(to: away, at: start.addingTimeInterval(2.22)), "\(away)")
            XCTAssertFalse(folders.holding(at: start.addingTimeInterval(2.22)), "\(away)")
            XCTAssertFalse(folders.moved(to: .sentRow, at: start.addingTimeInterval(2.4)), "\(away)")
            XCTAssertFalse(folders.moved(to: away, at: start.addingTimeInterval(2.6)), "\(away)")
        }
    }

    /// The last folder, a label at the bottom: nothing is between it and
    /// the reading pane, the folders' toolbar and the list being hidden, so
    /// a swipe of his from it goes there. That move is his: let go, nothing
    /// put back, and a later move is not put back either. The view button
    /// in the corner is still put back from, once.
    func testFromTheLastFolderTheReadingPaneIsHis() {
        var folders = FoldersVoiceOver()
        folders.send(toRow: true, last: true, running: true, at: start)
        XCTAssertFalse(folders.moved(to: .sentRow, at: start.addingTimeInterval(1.2)))
        XCTAssertFalse(folders.moved(to: .pane, at: start.addingTimeInterval(1.8)))
        XCTAssertFalse(folders.holding(at: start.addingTimeInterval(1.8)))
        XCTAssertFalse(folders.moved(to: .corner, at: start.addingTimeInterval(2.1)))
        var corner = FoldersVoiceOver()
        corner.send(toRow: true, last: true, running: true, at: start)
        XCTAssertFalse(corner.moved(to: .sentRow, at: start.addingTimeInterval(1.2)))
        XCTAssertTrue(corner.moved(to: .corner, at: start.addingTimeInterval(2.1)))
        XCTAssertFalse(corner.moved(to: .sentRow, at: start.addingTimeInterval(2.3)))
        XCTAssertFalse(corner.moved(to: .corner, at: start.addingTimeInterval(2.5)))
    }

    /// The last row of a table: the last of its section, with no rows in
    /// any section after it. The folders in their blocks: the Inbox's
    /// block, the rest, the labels. A last block with no rows leaves the
    /// last row in the block before it.
    func testTheLastRowOfTheFolders() {
        let blocks = [5, 3, 4]
        XCTAssertTrue(FoldersVoiceOver.isLast(3, in: 2, of: blocks))
        XCTAssertFalse(FoldersVoiceOver.isLast(2, in: 2, of: blocks))
        XCTAssertFalse(FoldersVoiceOver.isLast(2, in: 1, of: blocks))
        XCTAssertFalse(FoldersVoiceOver.isLast(4, in: 0, of: blocks))
        XCTAssertFalse(FoldersVoiceOver.isLast(0, in: 0, of: blocks))
        XCTAssertTrue(FoldersVoiceOver.isLast(2, in: 1, of: [5, 3, 0, 0]))
        XCTAssertFalse(FoldersVoiceOver.isLast(2, in: 1, of: [5, 3, 0, 1]))
        XCTAssertTrue(FoldersVoiceOver.isLast(0, in: 0, of: [1]))
        // Rows the table does not have.
        XCTAssertFalse(FoldersVoiceOver.isLast(4, in: 2, of: blocks))
        XCTAssertFalse(FoldersVoiceOver.isLast(0, in: 3, of: blocks))
        XCTAssertFalse(FoldersVoiceOver.isLast(-1, in: 2, of: [5, 3, 0]))
        XCTAssertFalse(FoldersVoiceOver.isLast(0, in: 0, of: []))
    }

    /// Before VoiceOver is on the row nothing is put back: it is on its way,
    /// and may still be on Flag or "< Mailboxes". Still held after.
    func testTheFoldersRowBeforeVoiceOverIsThereIsWaitedFor() {
        var folders = FoldersVoiceOver()
        folders.send(toRow: true, last: false, running: true, at: start)
        XCTAssertFalse(folders.moved(to: .pane, at: start.addingTimeInterval(0.3)))
        XCTAssertFalse(folders.moved(to: .corner, at: start.addingTimeInterval(0.4)))
        XCTAssertFalse(folders.moved(to: .other, at: start.addingTimeInterval(0.6)))
        XCTAssertTrue(folders.holding(at: start.addingTimeInterval(0.6)))
        XCTAssertFalse(folders.moved(to: .sentRow, at: start.addingTimeInterval(1.2)))
        XCTAssertTrue(folders.moved(to: .pane, at: start.addingTimeInterval(2.1)))
    }

    /// There, then on another folder, or the folders' bar a swipe from the
    /// first folder, or a sheet: his. Let go, nothing put back after.
    func testTheFoldersRowLetGoAtAMoveOfHis() {
        var folders = FoldersVoiceOver()
        folders.send(toRow: true, last: false, running: true, at: start)
        XCTAssertFalse(folders.moved(to: .sentRow, at: start.addingTimeInterval(1.2)))
        XCTAssertFalse(folders.moved(to: .other, at: start.addingTimeInterval(1.8)))
        XCTAssertFalse(folders.holding(at: start.addingTimeInterval(1.8)))
        XCTAssertFalse(folders.moved(to: .pane, at: start.addingTimeInterval(2.1)))
        XCTAssertFalse(folders.moved(to: .corner, at: start.addingTimeInterval(2.2)))
    }

    /// Nothing held for the folders' table, with VoiceOver off, after a
    /// folder tap or a switch of the panes, or past the bound.
    func testTheFoldersRowHeldOnlyForARowWithVoiceOverOnWithinTheBound() {
        for (row, running) in [(false, true), (true, false)] {
            var folders = FoldersVoiceOver()
            folders.send(toRow: row, last: false, running: running, at: start)
            XCTAssertFalse(folders.holding(at: start))
            XCTAssertFalse(folders.moved(to: .sentRow, at: start.addingTimeInterval(1.2)))
            XCTAssertFalse(folders.moved(to: .pane, at: start.addingTimeInterval(2)))
        }
        var folders = FoldersVoiceOver()
        folders.send(toRow: true, last: false, running: true, at: start)
        XCTAssertFalse(folders.moved(to: .sentRow, at: start.addingTimeInterval(1.2)))
        folders.letGo()
        XCTAssertFalse(folders.moved(to: .pane, at: start.addingTimeInterval(2)))
        folders.send(toRow: true, last: false, running: true, at: start)
        XCTAssertFalse(folders.moved(to: .sentRow, at: start.addingTimeInterval(1.2)))
        XCTAssertTrue(folders.holding(at: start.addingTimeInterval(ListVoiceOver.bound)))
        XCTAssertFalse(folders.moved(to: .corner, at: start.addingTimeInterval(ListVoiceOver.bound + 0.1)))
        XCTAssertFalse(folders.holding(at: start))
    }

    // MARK: - The least scroll that shows a row whole

    /// The list as the simulator read it, an iPad (7th generation): 70
    /// points of bar over it, a 44.5-point search band, 50 points of
    /// toolbar under it, in an 810-point column. Rows 96 points high, the
    /// first under the band.
    private func list(at offset: CGFloat, rows: Int = 30, footer: CGFloat = 0) -> TableSight {
        TableSight(offset: offset, height: 810, barTop: 70, barBottom: 50, band: 44.5,
                   content: 44.5 + CGFloat(rows) * 96 + footer)
    }

    private func rect(_ row: Int) -> (minY: CGFloat, maxY: CGFloat) {
        (44.5 + CGFloat(row) * 96, 44.5 + CGFloat(row + 1) * 96)
    }

    /// A row with 38 points under the band, as the letter's row on the
    /// iPad: the list moves down those 38 points, and the row's top is then
    /// just below the band. On the iPad VoiceOver took the list 230 points,
    /// to its top.
    func testARowUnderTheBandMovesDownByThePartUnderIt() {
        let row = rect(2)
        let sight = list(at: row.minY + 38 - 114.5)
        XCTAssertTrue(sight.showsPart(row.minY, row.maxY))
        XCTAssertFalse(sight.showsWhole(row.minY, row.maxY))
        let moved = sight.offset(showingWhole: row.minY, row.maxY)
        XCTAssertEqual(moved, sight.offset - 38)
        var after = sight
        after.offset = moved ?? sight.offset
        XCTAssertEqual(after.top, row.minY)
        XCTAssertTrue(after.showsWhole(row.minY, row.maxY))
        // The sixth row, 29 points under: 29 points, where VoiceOver went
        // 284 and left the row in the middle of the list.
        let sixth = rect(5)
        let under = list(at: sixth.minY + 29 - 114.5)
        XCTAssertEqual(under.offset(showingWhole: sixth.minY, sixth.maxY), under.offset - 29)
        // As in the simulator: the sixth row 69 points under, the list
        // scrolled 479 points, moved to 410.
        XCTAssertEqual(list(at: 479).offset(showingWhole: sixth.minY, sixth.maxY), 410)
    }

    /// A row with part of it under the toolbar: the list moves up by that
    /// part, and the row's bottom is then on the toolbar's top.
    func testARowUnderTheBottomBarMovesUpByThePartUnderIt() {
        let row = rect(9)
        let sight = list(at: 200)
        XCTAssertEqual(sight.bottom, 960)
        XCTAssertEqual(row.maxY - sight.bottom, 44.5)
        let moved = sight.offset(showingWhole: row.minY, row.maxY)
        XCTAssertEqual(moved, 244.5)
        var after = sight
        after.offset = moved ?? sight.offset
        XCTAssertEqual(after.bottom, row.maxY)
        XCTAssertTrue(after.showsWhole(row.minY, row.maxY))
        // As in the simulator: the seventh row, the list at its top, 26.5
        // points under the toolbar, moved up 26.5.
        let seventh = rect(6)
        XCTAssertEqual(list(at: -70).offset(showingWhole: seventh.minY, seventh.maxY), -43.5)
        // Taller than what is in sight: its top just below the band, not
        // under it.
        let tall = (minY: CGFloat(200), maxY: CGFloat(1000))
        let atTop = list(at: 0)
        XCTAssertEqual(atTop.offset(showingWhole: tall.minY, tall.maxY), 85.5)
    }

    /// The list's first row 40 points under the band: back to the list's
    /// top, and no further.
    func testTheFirstRowGoesBackToTheListsTop() {
        let first = rect(0)
        let sight = list(at: -70 + 40)
        XCTAssertEqual(sight.offset(showingWhole: first.minY, first.maxY), -70)
        // At the top, it is whole.
        XCTAssertNil(list(at: -70).offset(showingWhole: first.minY, first.maxY))
    }

    /// The last row under the toolbar: to the list's end, and never past
    /// it, even with the height of the rows behind.
    func testTheLastRowGoesToTheListsEndAndNoFurther() {
        let last = rect(29)
        let sight = list(at: 2140)
        XCTAssertEqual(last.maxY - sight.bottom, 24.5)
        let end = sight.content + 50 - 810
        XCTAssertEqual(sight.offset(showingWhole: last.minY, last.maxY), end)
        // With the load-more footer under it, the same move.
        XCTAssertEqual(list(at: 2140, footer: 60).offset(showingWhole: last.minY, last.maxY), end)
        // The height not yet grown for it: to the end, not past it.
        var short = sight
        short.content -= 20
        XCTAssertEqual(short.offset(showingWhole: last.minY, last.maxY), short.content + 50 - 810)
        // At that end already, or beyond it: no move, and not back.
        short.content -= 20
        XCTAssertNil(short.offset(showingWhole: last.minY, last.maxY))
        // A table that cannot move: nothing.
        var stuck = list(at: -70, rows: 5)
        stuck.barBottom = 400
        stuck.content = 300
        let row = rect(3)
        XCTAssertTrue(stuck.showsPart(row.minY, row.maxY))
        XCTAssertFalse(stuck.showsWhole(row.minY, row.maxY))
        XCTAssertNil(stuck.offset(showingWhole: row.minY, row.maxY))
    }

    /// Already whole, to half a point, or none of it in sight: no scroll.
    /// The same sums say what is wholly in sight for the first row named.
    func testAWholeRowOrOneOutOfSightDoesNotMove() {
        let sight = list(at: 300)
        let whole = rect(6)
        XCTAssertTrue(sight.showsWhole(whole.minY, whole.maxY))
        XCTAssertNil(sight.offset(showingWhole: whole.minY, whole.maxY))
        // A hair under the band: whole.
        let hair = list(at: whole.minY + 0.3 - 114.5)
        XCTAssertTrue(hair.showsWhole(whole.minY, whole.maxY))
        XCTAssertNil(hair.offset(showingWhole: whole.minY, whole.maxY))
        // Wholly under the band, or below the toolbar: not named, not moved.
        let under = rect(1)
        XCTAssertFalse(sight.showsPart(under.minY, under.maxY))
        XCTAssertNil(sight.offset(showingWhole: under.minY, under.maxY))
        let below = rect(20)
        XCTAssertFalse(sight.showsPart(below.minY, below.maxY))
        XCTAssertNil(sight.offset(showingWhole: below.minY, below.maxY))
        // Less than a point of it in sight: not named, not moved.
        let edge = rect(3)
        let sliver = list(at: edge.maxY - 0.5 - 114.5)
        XCTAssertFalse(sliver.showsPart(edge.minY, edge.maxY))
        XCTAssertNil(sliver.offset(showingWhole: edge.minY, edge.maxY))
    }

    /// The folders: no band, so only the bars count.
    func testTheFoldersHaveNoBand() {
        let folders = TableSight(offset: 30, height: 810, barTop: 70, barBottom: 0, band: 0,
                                 content: 20 * 50)
        XCTAssertEqual(folders.top, 100)
        XCTAssertEqual(folders.offset(showingWhole: 80, 130), 10)
        XCTAssertNil(folders.offset(showingWhole: 100, 150))
    }
}
