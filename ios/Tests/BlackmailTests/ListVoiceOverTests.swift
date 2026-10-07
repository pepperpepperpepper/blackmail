import XCTest
@testable import Blackmail

/// VoiceOver kept on its letter when the message list's rows are drawn
/// again (B-079, the second change). `ListVoiceOver` decides, with the real
/// grouping; `MessageListViewController` finds the row VoiceOver is on and
/// names the cell. On the test iPad the cell named for a folder's first row was handed
/// out again when its fresh page was drawn over the kept one: VoiceOver read
/// the second row's words in the first row's box, then went to the view
/// button.
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
        for landing in [ListVoiceOver.Landing.elsewhere, .listOwn, .typing] {
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
        XCTAssertEqual(voiceOver.held(running: true, on: nil, landing: .elsewhere, at: soon),
                       try row(0, in: kept))
        XCTAssertEqual(voiceOver.held(running: true, on: try row(3, in: kept), landing: .otherRow,
                                      at: soon),
                       try row(0, in: kept))
        let bound = start.addingTimeInterval(ListVoiceOver.bound)
        XCTAssertEqual(voiceOver.sentRow(at: bound), try row(0, in: kept))
        XCTAssertEqual(voiceOver.held(running: true, on: nil, landing: .listOwn, at: bound),
                       try row(0, in: kept))
        let later = bound.addingTimeInterval(0.1)
        XCTAssertNil(voiceOver.sentRow(at: later))
        XCTAssertEqual(voiceOver.held(running: true, on: try row(3, in: kept), landing: .otherRow,
                                      at: later),
                       try row(3, in: kept))
        XCTAssertNil(voiceOver.held(running: true, on: nil, landing: .elsewhere, at: later))
        XCTAssertNil(voiceOver.held(running: true, on: nil, landing: .listOwn, at: later))
        XCTAssertLessThanOrEqual(ListVoiceOver.bound, 3)
    }

    /// Sent to a row and still held, but VoiceOver on the folders, the
    /// reading pane or a sheet once the screen change has landed: his, and
    /// nothing held. On the iPad it landed 1.3 to 1.6 s after the tap.
    func testElsewhereOnceTheScreenChangeHasLandedHoldsNothing() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        let landed = start.addingTimeInterval(ListVoiceOver.screenChange)
        XCTAssertEqual(voiceOver.held(running: true, on: nil, landing: .elsewhere,
                                      at: landed.addingTimeInterval(-0.05)),
                       try row(0, in: kept))
        XCTAssertNil(voiceOver.held(running: true, on: nil, landing: .elsewhere, at: landed))
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
        voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)), kept: false,
                          at: start.addingTimeInterval(0.5))
        let held = try XCTUnwrap(voiceOver.sentRow(at: start.addingTimeInterval(0.6)))
        XCTAssertEqual(held.index, 1)
        XCTAssertEqual(ListVoiceOver.step(after: held, in: rows(fresh)), .same(1))
    }

    /// VoiceOver there while the rows are the kept page: held until the
    /// fresh page has been drawn, and let go then.
    func testThereOnTheKeptPageItIsHeldThroughTheFreshPage() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        let there = start.addingTimeInterval(1.3)
        XCTAssertNil(voiceOver.moved(to: .sentRow, kept: true, at: there))
        XCTAssertEqual(voiceOver.sentRow(at: there), try row(0, in: kept))
        // The kept page drawn again: still held.
        voiceOver.redrawn(to: try row(0, in: kept), kept: true, at: there)
        XCTAssertEqual(voiceOver.sentRow(at: there), try row(0, in: kept))
        // The fresh page: VoiceOver put on its letter, and the row let go.
        voiceOver.redrawn(to: try row(0, in: kept), kept: false, at: there)
        XCTAssertNil(voiceOver.sentRow(at: there))
    }

    /// There, with the fresh page drawn already, or a folder with no kept
    /// page, and nothing posted by the list: the screen change has landed.
    /// Let go at once.
    func testThereOnTheFreshPageItIsLetGo() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(3, in: kept), running: true, at: start)
        XCTAssertNil(voiceOver.moved(to: .sentRow, kept: false, at: start.addingTimeInterval(1.4)))
        XCTAssertNil(voiceOver.sentRow(at: start.addingTimeInterval(1.4)))
    }

    /// Gone to another of the list's rows, or to a cell drawn since for
    /// another letter: put on the row it was sent to, once.
    func testGoneToAnotherRowItIsPutThereOnce() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        let landed = start.addingTimeInterval(1.3)
        XCTAssertEqual(voiceOver.moved(to: .otherRow, kept: true, at: landed), try row(0, in: kept))
        XCTAssertNil(voiceOver.sentRow(at: landed))
        XCTAssertNil(voiceOver.moved(to: .otherRow, kept: true, at: landed))
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
                voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)), kept: false,
                                  at: start.addingTimeInterval(0.6))
            }
            let landed = start.addingTimeInterval(1.33)
            let put = try XCTUnwrap(voiceOver.moved(to: .listOwn, kept: !redrawn, at: landed))
            XCTAssertEqual(put.index, redrawn ? 1 : 0)
            XCTAssertNil(voiceOver.sentRow(at: landed))
            XCTAssertNil(voiceOver.moved(to: .listOwn, kept: !redrawn, at: landed))
        }
        // As late as the bound, and not after it.
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        XCTAssertEqual(voiceOver.moved(to: .listOwn, kept: false,
                                       at: start.addingTimeInterval(ListVoiceOver.bound)),
                       try row(0, in: kept))
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        XCTAssertNil(voiceOver.moved(to: .listOwn, kept: false,
                                     at: start.addingTimeInterval(ListVoiceOver.bound + 0.1)))
    }

    /// There through the list's own post, after the fresh page, sooner than
    /// the screen change could land: held. The screen change then lands on
    /// the cell it named, now another letter's, or on the view button: put
    /// back on the row, once.
    func testThereThroughTheListsOwnPostAStaleLandingIsPutBackOnce() throws {
        let fresh = [letter(105, thread: "E")] + kept
        for stale in [ListVoiceOver.Landing.otherRow, .listOwn] {
            var voiceOver = ListVoiceOver()
            voiceOver.send(to: try row(0, in: kept), running: true, at: start)
            voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)), kept: false,
                              at: start.addingTimeInterval(0.5))
            let there = start.addingTimeInterval(0.7)
            XCTAssertNil(voiceOver.moved(to: .sentRow, kept: false, at: there))
            XCTAssertEqual(voiceOver.sentRow(at: there)?.index, 1)
            // On the row again: still held.
            XCTAssertNil(voiceOver.moved(to: .sentRow, kept: false, at: start.addingTimeInterval(1)))
            let landed = start.addingTimeInterval(1.3)
            XCTAssertEqual(voiceOver.moved(to: stale, kept: false, at: landed)?.index, 1, "\(stale)")
            XCTAssertNil(voiceOver.sentRow(at: landed))
            XCTAssertNil(voiceOver.moved(to: stale, kept: false, at: landed))
        }
    }

    /// There early, and another reload before the screen change could land:
    /// still held, on the cell for its letter.
    func testThereEarlyAnotherReloadStillHolds() throws {
        let fresh = [letter(105, thread: "E")] + kept
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)), kept: false,
                          at: start.addingTimeInterval(0.5))
        XCTAssertNil(voiceOver.moved(to: .sentRow, kept: false, at: start.addingTimeInterval(0.7)))
        voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)), kept: false,
                          at: start.addingTimeInterval(0.9))
        XCTAssertEqual(voiceOver.sentRow(at: start.addingTimeInterval(0.9))?.index, 1)
        XCTAssertEqual(voiceOver.moved(to: .otherRow, kept: false,
                                       at: start.addingTimeInterval(1.3))?.index, 1)
    }

    /// There early, but the move comes once the screen change has landed:
    /// his, or VoiceOver's, and let go with nothing posted. A reload then
    /// lets go too.
    func testThereEarlyAMoveOnceTheScreenChangeHasLandedIsHis() throws {
        let fresh = [letter(105, thread: "E")] + kept
        let landed = start.addingTimeInterval(ListVoiceOver.screenChange)
        for move in [ListVoiceOver.Landing.otherRow, .listOwn, .elsewhere, .typing] {
            var voiceOver = ListVoiceOver()
            voiceOver.send(to: try row(0, in: kept), running: true, at: start)
            voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)), kept: false,
                              at: start.addingTimeInterval(0.5))
            XCTAssertNil(voiceOver.moved(to: .sentRow, kept: false, at: start.addingTimeInterval(0.7)))
            XCTAssertNil(voiceOver.moved(to: move, kept: false, at: landed), "\(move)")
            XCTAssertNil(voiceOver.sentRow(at: landed), "\(move)")
        }
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)), kept: false,
                          at: start.addingTimeInterval(0.5))
        XCTAssertNil(voiceOver.moved(to: .sentRow, kept: false, at: start.addingTimeInterval(0.7)))
        voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)), kept: false, at: landed)
        XCTAssertNil(voiceOver.sentRow(at: landed))
    }

    /// There early, then on the folders, the reading pane, or typing: let
    /// go, and never put back from there.
    func testThereEarlyThenElsewhereLetsGo() throws {
        let fresh = [letter(105, thread: "E")] + kept
        for move in [ListVoiceOver.Landing.elsewhere, .typing] {
            var voiceOver = ListVoiceOver()
            voiceOver.send(to: try row(0, in: kept), running: true, at: start)
            voiceOver.redrawn(to: ListVoiceOver.Row(1, in: rows(fresh)), kept: false,
                              at: start.addingTimeInterval(0.5))
            XCTAssertNil(voiceOver.moved(to: .sentRow, kept: false, at: start.addingTimeInterval(0.7)))
            XCTAssertNil(voiceOver.moved(to: move, kept: false, at: start.addingTimeInterval(1)), "\(move)")
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
        XCTAssertNil(voiceOver.moved(to: .elsewhere, kept: true, at: away))
        XCTAssertEqual(voiceOver.sentRow(at: away), try row(0, in: kept))
        XCTAssertEqual(voiceOver.held(running: true, on: nil, landing: .elsewhere, at: away),
                       try row(0, in: kept))
        // Then onto a cell drawn since for another letter: put there, once.
        let landed = start.addingTimeInterval(1.3)
        XCTAssertEqual(voiceOver.moved(to: .otherRow, kept: false, at: landed), try row(0, in: kept))
        XCTAssertNil(voiceOver.sentRow(at: landed))
    }

    /// On the folders, the reading pane or a sheet once the screen change
    /// has landed: his. Let go, nothing posted.
    func testElsewhereOnceTheScreenChangeHasLandedLetsGo() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        let landed = start.addingTimeInterval(ListVoiceOver.screenChange)
        XCTAssertNil(voiceOver.moved(to: .elsewhere, kept: false, at: landed))
        XCTAssertNil(voiceOver.sentRow(at: landed))
        XCTAssertNil(voiceOver.moved(to: .listOwn, kept: false, at: landed))
    }

    /// He types in the search field, or VoiceOver is on a key, before it
    /// has been on the row: let go, nothing posted, and nothing put back
    /// after.
    func testLandedWhileTypingLetsGo() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        XCTAssertNil(voiceOver.moved(to: .typing, kept: false, at: start.addingTimeInterval(1)))
        XCTAssertNil(voiceOver.sentRow(at: start.addingTimeInterval(1)))
        XCTAssertNil(voiceOver.moved(to: .listOwn, kept: false, at: start.addingTimeInterval(1.3)))
    }

    /// Once VoiceOver has been there, any move after it is his, or
    /// VoiceOver's: let go, and nothing posted. A row he has swiped to is
    /// not taken from him.
    func testAMoveAfterItWasThereLetsGo() throws {
        for move in [ListVoiceOver.Landing.otherRow, .listOwn] {
            var voiceOver = ListVoiceOver()
            voiceOver.send(to: try row(0, in: kept), running: true, at: start)
            XCTAssertNil(voiceOver.moved(to: .sentRow, kept: true, at: start.addingTimeInterval(1.3)))
            XCTAssertNil(voiceOver.moved(to: move, kept: true, at: start.addingTimeInterval(1.5)),
                         "\(move)")
            XCTAssertNil(voiceOver.sentRow(at: start.addingTimeInterval(1.5)))
            XCTAssertNil(voiceOver.held(running: true, on: nil, landing: .listOwn,
                                        at: start.addingTimeInterval(2)))
        }
    }

    /// After the bound: nothing, and let go.
    func testAfterTheBoundNothing() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        XCTAssertNil(voiceOver.moved(to: .otherRow, kept: true,
                                     at: start.addingTimeInterval(ListVoiceOver.bound + 0.5)))
        XCTAssertNil(voiceOver.sentRow(at: start))
    }

    /// The rows gone, the table named: nothing left to hold.
    func testTheTableNamedLetsGo() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.send(to: try row(0, in: kept), running: true, at: start)
        voiceOver.redrawn(to: nil, kept: false, at: start)
        XCTAssertNil(voiceOver.sentRow(at: start))
    }

    /// Nothing sent: a reload or a move changes nothing.
    func testNothingSentNothingChanges() throws {
        var voiceOver = ListVoiceOver()
        voiceOver.redrawn(to: try row(1, in: kept), kept: false, at: start)
        XCTAssertNil(voiceOver.sentRow(at: start))
        for landing in [ListVoiceOver.Landing.sentRow, .otherRow, .listOwn, .typing, .elsewhere] {
            XCTAssertNil(voiceOver.moved(to: landing, kept: true, at: start))
        }
    }
}
