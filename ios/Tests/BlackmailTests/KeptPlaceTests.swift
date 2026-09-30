import XCTest
@testable import Blackmail

/// Where the message list is when the folder's fresh first page lands over
/// the page kept on the iPad (D-016), which it drew before anything had been
/// sent: `KeptSwap` decides, `ListLetters` holds the letters, and
/// `ListPlace` finds his place again with the real `MessageThread`
/// grouping, as in `ListPlaceTests`. `MessageListViewController` measures,
/// and scrolls as it is told.
@MainActor
final class KeptPlaceTests: XCTestCase {

    /// The list's fixed row height, near enough; the maths only needs one.
    private static let row = 96.0

    private func letter(_ uid: Int, thread: String, preview: String = "") -> MessageSummary {
        MessageSummary(id: "7/\(uid)", mailboxID: "INBOX",
                       sender: "Sam Example <sam@example.com>",
                       subject: "About \(thread)", preview: preview,
                       date: Date(timeIntervalSince1970: 1_790_000_000 + Double(uid) * 3_600),
                       isRead: true, isFlagged: false, threadID: thread)
    }

    private func grouped(_ letters: [MessageSummary]) -> [MessageThread] {
        MessageThread.rows(for: letters, grouped: true)
    }

    /// Rows `first` onwards on screen, the first `offset` points below the
    /// top of the pane and the rest a row apart.
    private func onScreen(from first: Int, count: Int, offset: Double) -> [(row: Int, offset: Double)] {
        (0..<count).map { (first + $0, offset + Double($0) * Self.row) }
    }

    /// Every row, as the letters in it.
    private func letters(of rows: [MessageThread]) -> [[String]] {
        rows.map { $0.messages.map(\.id) }
    }

    /// The kept page: ten conversations, A holding two letters.
    private var folder: [MessageSummary] {
        [letter(150, thread: "A"), letter(149, thread: "B"), letter(148, thread: "C"),
         letter(147, thread: "A"), letter(146, thread: "D"), letter(145, thread: "E"),
         letter(144, thread: "F"), letter(143, thread: "G"), letter(142, thread: "H"),
         letter(141, thread: "I"), letter(140, thread: "J")]
    }


    /// The folder's first page, as it lands over the kept rows: K and a
    /// reply in G's conversation new since, and E gone.
    private var freshOverKept: [MessageSummary] {
        [letter(160, thread: "K"), letter(159, thread: "G")] + folder.filter { $0.id != "7/145" }
    }

    /// The kept rows on the list, as a launch draws them.
    private func keptOnScreen() -> ListLetters {
        let list = ListLetters()
        list.showKept(folder)
        return list
    }

    /// Where the fresh page goes: nowhere while a finger is on the list,
    /// whatever else; nowhere while rows are ticked in Edit mode, as the
    /// watch's letters wait (B-049); under a search, shown or typed, which
    /// is left alone; in place at the top; and with his place held when he
    /// has scrolled.
    func testAFreshPageGoesWhereHeIsAndNotUnderAFingerOrHisTicks() async throws {
        for atTop in [true, false] {
            for searching in [true, false] {
                for ticked in [true, false] {
                    XCTAssertEqual(KeptSwap.swap(atTop: atTop, searching: searching, ticked: ticked,
                                                 touching: true), .waitForLift)
                }
                XCTAssertEqual(KeptSwap.swap(atTop: atTop, searching: searching, ticked: true,
                                             touching: false), .waitForTicks)
            }
            XCTAssertEqual(KeptSwap.swap(atTop: atTop, searching: true, ticked: false, touching: false),
                           .underSearch)
        }
        XCTAssertEqual(KeptSwap.swap(atTop: true, searching: false, ticked: false, touching: false), .top)
        XCTAssertEqual(KeptSwap.swap(atTop: false, searching: false, ticked: false, touching: false),
                       .holdingPlace)
    }

    /// Scrolled down the kept rows, D at the top of the pane and F open in
    /// the reading pane, as the fresh page lands: the rows he can see stay
    /// where they are, D to the point, though two rows have come in above
    /// it and E has gone, and F keeps its highlight. Put at the top as a
    /// Refresh is, D would have been out of sight.
    func testScrolledDownTheKeptRowsTheFreshPageHoldsTheRowsHeCanSee() async throws {
        let list = keptOnScreen()
        XCTAssertTrue(list.fromShelf)
        let before = grouped(list.shown)
        let place = ListPlace(rows: before, visible: onScreen(from: 3, count: 5, offset: -30),
                              selected: [5])
        let swap = KeptSwap.swap(atTop: false, searching: false, ticked: false, touching: false)
        XCTAssertEqual(swap, .holdingPlace)
        var places = ListPlaces()
        guard case .back(let here) = places.refetched(here: place) else { return XCTFail() }

        _ = list.fetchedAfresh(freshOverKept)
        XCTAssertFalse(list.fromShelf)
        let after = grouped(list.shown)
        XCTAssertEqual(after.first?.id, "7/160")
        let landing = try XCTUnwrap(here.landing(in: after))
        XCTAssertEqual(after[landing.row].id, "7/146", "D, where it was")
        XCTAssertEqual(landing.offset, -30)
        let selected = here.selection(in: after, opened: nil, editing: false)
        XCTAssertEqual(selected.map { after[$0].id }, ["7/144"], "F")
    }

    /// The page as the list lands it (`OverKept.landing`), what
    /// `MessageListViewController.landFreshPage` does with what comes back.
    private func land(_ over: inout OverKept, on list: ListLetters, atTop: Bool = true,
                      ticked: Bool = false, touching: Bool) -> Bool {
        let swap = KeptSwap.swap(atTop: atTop, searching: list.isSearching, ticked: ticked,
                                 touching: touching)
        guard let fresh = over.landing(showingKept: list.fromShelf, swap) else { return false }
        _ = list.fetchedAfresh(fresh.page, asked: fresh.asked)
        return true
    }

    /// A finger on the list as the fresh page comes: the page is held and
    /// the kept rows stay as they are, however often it is looked at, until
    /// the finger lifts; then it goes on, at the top here, and nothing
    /// waits after it. The same for rows ticked in Edit mode, until Done.
    func testUnderAFingerOrHisTicksTheFreshPageWaitsAndGoesOnWhenTheyGo() async throws {
        for (label, ticked, touching) in [("a finger", false, true), ("ticks", true, false)] {
            let list = keptOnScreen()
            let before = letters(of: grouped(list.shown))
            var over = OverKept()
            XCTAssertTrue(over.fetch(showingKept: list.fromShelf, quietly: false), label)
            over.came(freshOverKept, asked: list.askingAfresh())

            for _ in 0..<3 {
                XCTAssertFalse(land(&over, on: list, ticked: ticked, touching: touching), label)
            }
            XCTAssertEqual(letters(of: grouped(list.shown)), before, label)
            XCTAssertTrue(list.fromShelf, label)
            XCTAssertNotNil(over.waiting, label)

            XCTAssertTrue(land(&over, on: list, touching: false), label)
            XCTAssertEqual(list.shown.map(\.id), freshOverKept.map(\.id), label)
            XCTAssertFalse(list.fromShelf, label)
            XCTAssertNil(over.waiting, label)
            XCTAssertFalse(land(&over, on: list, touching: false), "nothing more to land")
        }
    }

    /// A page held for a finger, when he has replaced the kept rows
    /// meanwhile with a Refresh or a day, is dropped: that list has the
    /// say, and the finger lifting puts nothing over it.
    func testAFreshPageHeldOverKeptRowsHeHasReplacedIsDropped() async throws {
        let list = keptOnScreen()
        var over = OverKept()
        XCTAssertTrue(over.fetch(showingKept: true, quietly: false))
        over.came(freshOverKept, asked: list.askingAfresh())
        XCTAssertFalse(land(&over, on: list, touching: true))

        let day = [letter(120, thread: "X"), letter(119, thread: "Y")]
        list.showWindow(day)
        XCTAssertFalse(land(&over, on: list, touching: false))
        XCTAssertNil(over.waiting)
        XCTAssertEqual(list.shown.map(\.id), day.map(\.id))
    }

    /// One fetch over the kept page at a time. The folder's own goes as the
    /// list opens; while it is out, a watch check that reaches the server
    /// starts no second listing of the same folder, and nor does one while
    /// its page waits for a finger. The watch's goes only after the
    /// folder's own has gone and failed, and never once the fresh page has
    /// landed.
    func testOneFetchOverTheKeptPageAtATimeTheFoldersOwnFirst() async throws {
        let list = keptOnScreen()
        var over = OverKept()
        XCTAssertFalse(over.fetch(showingKept: true, quietly: true), "not before the folder's own")
        XCTAssertTrue(over.fetch(showingKept: list.fromShelf, quietly: false), "the folder's own")
        XCTAssertFalse(over.fetch(showingKept: list.fromShelf, quietly: true), "the watch's, while it is out")
        XCTAssertFalse(over.fetch(showingKept: list.fromShelf, quietly: false))

        over.failed()
        XCTAssertTrue(over.fetch(showingKept: list.fromShelf, quietly: true),
                      "the watch's, the connection back after a launch without one")
        over.came(freshOverKept, asked: list.askingAfresh())
        XCTAssertFalse(over.fetch(showingKept: list.fromShelf, quietly: true), "while its page waits")
        XCTAssertTrue(land(&over, on: list, touching: false))
        XCTAssertFalse(over.fetch(showingKept: list.fromShelf, quietly: true), "the page has landed")
    }

    /// A search started over the kept rows is left alone when the fresh page
    /// lands, its hits, and its paging: the folder under it is replaced. When
    /// the search ends the folder comes back as the fresh page, where he was
    /// in it, and no longer as the kept one.
    func testASearchOverTheKeptRowsIsLeftAloneAndTheFolderComesBackFresh() async throws {
        let list = keptOnScreen()
        var places = ListPlaces()
        let top = ListPlace(rows: grouped(list.shown), visible: onScreen(from: 0, count: 6, offset: 0),
                            selected: [])
        _ = places.resultsShown(overFolder: true, here: top)
        let hits = [letter(148, thread: "C"), letter(143, thread: "G")]
        list.showResults(hits)

        XCTAssertEqual(KeptSwap.swap(atTop: true, searching: true, ticked: false, touching: false),
                       .underSearch)
        let unpreviewed = list.fetchedUnderSearch(freshOverKept)
        XCTAssertEqual(list.shown, hits, "the hits are left alone")
        XCTAssertTrue(list.isSearching)
        XCTAssertFalse(list.fromShelf)
        XCTAssertEqual(unpreviewed.map(\.id), freshOverKept.map(\.id))

        list.endSearch()
        XCTAssertEqual(list.folder.map(\.id), freshOverKept.map(\.id))
        guard case .back(let back) = places.searchEnded(showingResults: true) else { return XCTFail() }
        let landing = try XCTUnwrap(back.landing(in: grouped(list.shown)))
        XCTAssertEqual(grouped(list.shown)[landing.row].id, "7/150", "A, at the top of the pane")
    }

    /// The watch leaves the kept rows alone, checking only the Inbox's
    /// count: they are an earlier launch's, and a check from the lowest of
    /// them would put new letters on top of a page nobody has vouched for.
    /// Once the fresh page has landed, the list is checked as always.
    func testTheWatchChecksTheListOnlyOnceTheFreshPageHasLanded() async throws {
        let list = keptOnScreen()
        XCTAssertNil(list.toWatch(fromNewest: true, fetched: true))
        XCTAssertNil(list.toWatch(fromNewest: true, fetched: false))
        _ = list.fetchedAfresh(freshOverKept)
        XCTAssertEqual(list.toWatch(fromNewest: true, fetched: true), freshOverKept.map(\.id))
    }

    /// A kept preview goes across to the fresh row under the same id only
    /// when the row is the same letter by Gmail's message id: under another
    /// mailbox's same numbers it is another letter's words.
    func testAKeptPreviewGoesOnlyToTheSameLetter() async throws {
        func row(_ uid: Int, message: UInt64, preview: String = "") -> MessageSummary {
            var row = letter(uid, thread: "T\(uid)", preview: preview)
            row.gmailMessageID = message
            return row
        }
        let list = ListLetters()
        list.showKept([row(150, message: 1, preview: "Kept words, the same letter"),
                       row(149, message: 2, preview: "Kept words of another letter")])
        let unpreviewed = list.fetchedAfresh([row(150, message: 1), row(149, message: 9)])
        XCTAssertEqual(list.shown.map(\.preview), ["Kept words, the same letter", ""])
        XCTAssertEqual(unpreviewed.map(\.id), ["7/149"])
    }

    /// A row with no Gmail message id carries its preview to the row the
    /// next listing brings: the server's copy of a letter kept in Drafts is
    /// drawn from the letter, with none (`LocalDrafts`), and its preview
    /// was blanked and fetched again at every listing of Drafts after it
    /// had landed. Only two ids that differ keep a preview back.
    func testAPreviewGoesAcrossFromARowWithNoMessageIDAsALandedDraftsIs() async throws {
        var landed = MessageSummary(id: "3/40", mailboxID: "[Gmail]/Drafts", sender: "Owner",
                                    subject: "Sunday", preview: "Started before lunch.",
                                    date: Date(timeIntervalSince1970: 1_790_000_000),
                                    isRead: true, isFlagged: false)
        XCTAssertNil(landed.gmailMessageID)
        let list = ListLetters()
        _ = list.fetchedAfresh([])
        list.landed(landed, replacing: [], atTop: true)
        XCTAssertEqual(list.shown.map(\.id), ["3/40"])

        landed.preview = ""
        landed.gmailMessageID = 1_800_000_000_000_000_040
        let unpreviewed = list.fetchedAfresh([landed])
        XCTAssertEqual(list.shown.map(\.preview), ["Started before lunch."])
        XCTAssertEqual(unpreviewed.map(\.id), [], "nothing to fetch again")
    }

    /// A day jumped to while the kept page is up is a list of its own: no
    /// longer the kept page, so the fresh page, when it comes, does not go
    /// on top of it, paging below it works, and the watch goes by it as by
    /// any list.
    func testADayJumpedToOverTheKeptPageIsNoLongerTheKeptPage() async throws {
        let list = keptOnScreen()
        XCTAssertTrue(list.fromShelf)
        XCTAssertNil(list.toWatch(fromNewest: true, fetched: true))

        let day = [letter(120, thread: "X"), letter(119, thread: "Y")]
        list.showWindow(day)
        XCTAssertFalse(list.fromShelf)
        XCTAssertEqual(list.toWatch(fromNewest: true, fetched: true), day.map(\.id))
        XCTAssertNil(list.toWatch(fromNewest: false, fetched: true), "a day is not the newest")
    }

    /// Unread and unflagged rows, each a letter of its own by Gmail's id.
    private func unread(_ uid: Int, message: UInt64) -> MessageSummary {
        var row = letter(uid, thread: "T\(uid)")
        row.isRead = false
        row.gmailMessageID = message
        return row
    }

    /// He opens a kept row, and flags another, before the fresh page has
    /// landed: the listing was asked before either STORE, and its rows say
    /// unread and unflagged. The dot and the flag stay as he made them over
    /// it, the read mark taken by the server as the page came and the flag
    /// still on its way. The next listing, asked after both were taken, has
    /// the say, whatever it says: here that he has marked the letter unread
    /// again elsewhere.
    func testHisReadMarkAndFlagMadeBeforeTheFreshPageLandsStayOnIt() async throws {
        let kept = [unread(150, message: 1), unread(149, message: 2), unread(148, message: 3)]
        let list = ListLetters()
        list.showKept(kept)
        var over = OverKept()
        XCTAssertTrue(over.fetch(showingKept: list.fromShelf, quietly: false))
        let asked = list.askingAfresh()

        list.reading("7/150", read: true)
        let flagged = try XCTUnwrap(list.letter("7/149"))
        list.setFlagged(true, on: flagged)
        XCTAssertEqual(list.letter("7/150")?.isRead, true)
        list.readAnswered("7/150", landed: true)

        // The page, as the server had it when the listing was asked.
        over.came(kept, asked: asked)
        XCTAssertTrue(land(&over, on: list, touching: false))
        XCTAssertEqual(list.letter("7/150")?.isRead, true, "the dot does not come back")
        XCTAssertEqual(list.letter("7/149")?.isFlagged, true, "nor the flag go")
        XCTAssertEqual(list.letter("7/148")?.isRead, false)

        list.flagAnswered(flagged, landed: true)
        var server = kept
        server[1].isFlagged = true
        let later = list.askingAfresh()
        _ = list.fetchedAfresh(server, asked: later)
        XCTAssertEqual(list.letter("7/150")?.isRead, false, "the listing asked since has the say")
        XCTAssertEqual(list.letter("7/149")?.isFlagged, true)
    }

    /// A read mark or a flag the server refuses goes back as it was and is
    /// held over nothing. And a mark goes back on, over a listing, only onto
    /// the letter he made it on: a listing that has thrown a kept page away
    /// has another letter under the same id (D-016), and its dot is its own.
    func testARefusedMarkGoesBackAndNoMarkGoesOntoAnotherLetterUnderTheSameID() async throws {
        let kept = [unread(150, message: 1), unread(149, message: 2)]
        let list = ListLetters()
        list.showKept(kept)
        let asked = list.askingAfresh()

        list.reading("7/150", read: true)
        list.readAnswered("7/150", landed: false)
        XCTAssertEqual(list.letter("7/150")?.isRead, false, "put back")
        let flagged = try XCTUnwrap(list.letter("7/149"))
        list.setFlagged(true, on: flagged)
        list.flagAnswered(flagged, landed: false)
        XCTAssertEqual(list.letter("7/149")?.isFlagged, false, "put back")
        var read = kept
        read[0].isRead = true
        _ = list.fetchedAfresh(read, asked: asked)
        XCTAssertEqual(list.letter("7/150")?.isRead, true, "nothing held over the server's word")

        // Another mailbox's letters under the same ids: 150 unread there,
        // 149 read and flagged. His marks, made on the kept rows and still
        // on their way, go on neither, and refused, put nothing back over
        // either.
        list.showKept(kept)
        let before = list.askingAfresh()
        list.reading("7/150", read: true)
        list.reading("7/149", read: true)
        let keptRow = try XCTUnwrap(list.letter("7/149"))
        list.setFlagged(true, on: keptRow)
        var another = [unread(150, message: 7), unread(149, message: 8)]
        another[1].isRead = true
        another[1].isFlagged = true
        _ = list.fetchedAfresh(another, asked: before)
        XCTAssertEqual(list.letter("7/150")?.isRead, false, "another letter's dot is its own")
        list.readAnswered("7/149", landed: false)
        list.flagAnswered(keptRow, landed: false)
        XCTAssertEqual(list.letter("7/149")?.isRead, true, "and is not put back over either")
        XCTAssertEqual(list.letter("7/149")?.isFlagged, true, "nor is its flag")
    }

    /// A row kept on the iPad that the server has said is not the letter it
    /// was kept as comes off the list while the list still has the kept row
    /// under that id, and stays off after the removal has landed, until the
    /// list is fetched afresh. When the fresh page has landed first, the
    /// row under that id is the server's own letter, and it stays.
    func testARowTheServerDisownsComesOffOnlyWhileItIsStillTheKeptOne() async throws {
        let kept = [unread(150, message: 1), unread(149, message: 2)]
        let fresh = [unread(150, message: 7), unread(149, message: 8)]

        let answeredFirst = ListLetters()
        answeredFirst.showKept(kept)
        XCTAssertTrue(PaneActions.notTheKeptLetter(kept[1], list: answeredFirst))
        XCTAssertEqual(answeredFirst.shown.map(\.id), ["7/150"])
        _ = answeredFirst.fetchedAfresh(fresh)
        XCTAssertEqual(answeredFirst.shown.map(\.gmailMessageID), [7, 8],
                       "the listing has the say on what the server has under that id")

        let landedFirst = ListLetters()
        landedFirst.showKept(kept)
        _ = landedFirst.fetchedAfresh(fresh)
        XCTAssertFalse(PaneActions.notTheKeptLetter(kept[1], list: landedFirst))
        XCTAssertEqual(landedFirst.shown.map(\.gmailMessageID), [7, 8], "the server's letter stays")
    }
}
