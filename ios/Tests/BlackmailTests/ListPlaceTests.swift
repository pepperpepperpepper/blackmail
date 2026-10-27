import XCTest
@testable import Blackmail

/// Where the message list is when its rows change under him: paging upward
/// after a date jump, a search replacing the folder and ending, and the
/// folder's previews after a search. `ListPlace` and `ListPlaces` decide,
/// with the real `MessageThread` grouping; `MessageListViewController`
/// measures and scrolls.
final class ListPlaceTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

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

    private func index(of id: String, in rows: [MessageThread]) -> Int? {
        rows.firstIndex { $0.messages.contains { $0.id == id } }
    }

    /// Rows `first` onwards on screen, the first `offset` points below the
    /// top of the pane and the rest a row apart.
    private func onScreen(from first: Int, count: Int, offset: Double) -> [(row: Int, offset: Double)] {
        (0..<count).map { (first + $0, offset + Double($0) * Self.row) }
    }

    /// The folder after a jump: ten conversations, A holding two letters.
    private var folder: [MessageSummary] {
        [letter(150, thread: "A"), letter(149, thread: "B"), letter(148, thread: "C"),
         letter(147, thread: "A"), letter(146, thread: "D"), letter(145, thread: "E"),
         letter(144, thread: "F"), letter(143, thread: "G"), letter(142, thread: "H"),
         letter(141, thread: "I"), letter(140, thread: "J")]
    }

    // MARK: - Paging upward after a date jump (list-8)

    /// A page of newer mail above the rows on screen: three new
    /// conversations, one letter joining G, below the top of the pane, and
    /// one joining B, above it. G and B move up to where their new letters
    /// are. The row at the top of the pane stays there, to the point, and
    /// the highlight stays on the letter open in the reading pane.
    ///
    /// The list used to add the change in the row count to the offset, which
    /// here puts C at the top instead of D: a row's slip for G. And it read
    /// the highlight back by row number after the rows were rebuilt, which
    /// here highlights A instead of F.
    func testAPageAboveKeepsTheRowsOnScreenAndTheHighlightWhereTheyWere() throws {
        let before = grouped(folder)
        XCTAssertEqual(before.map { $0.newest.threadID }, ["A", "B", "C", "D", "E", "F", "G",
                                                           "H", "I", "J"])
        // D at the top of the pane, partly scrolled off; F open in the pane.
        let place = ListPlace(rows: before, visible: onScreen(from: 3, count: 7, offset: -30),
                              selected: [5])

        let newer = [letter(160, thread: "K"), letter(159, thread: "G"), letter(158, thread: "L"),
                     letter(157, thread: "B"), letter(156, thread: "M")]
        let after = grouped(newer + folder)

        let landing = try XCTUnwrap(place.landing(in: after))
        XCTAssertEqual(after[landing.row].id, "7/146", "D is still the row at the top of the pane")
        XCTAssertEqual(landing.offset, -30, "to the point")
        XCTAssertEqual(place.selection(in: after, opened: nil, editing: false),
                       [try XCTUnwrap(index(of: "7/144", in: after))], "F is still highlighted")

        // What the row count and the row number gave instead.
        let byCount = 3 + (after.count - before.count)
        XCTAssertEqual(after[byCount].id, "7/148", "C: one row short, for G moving above")
        XCTAssertNotEqual(after[5].id, "7/144", "the old row number is another letter")
    }

    /// Every tick in Edit mode goes with its letters, not its row number.
    func testAPageAboveKeepsEveryTick() throws {
        let before = grouped(folder)
        let place = ListPlace(rows: before, visible: onScreen(from: 0, count: 8, offset: 0),
                              selected: [2, 4, 6])
        let after = grouped([letter(160, thread: "K"), letter(159, thread: "E")] + folder)
        let ticked = place.selection(in: after, opened: nil, editing: true)
        XCTAssertEqual(ticked.map { after[$0].newest.threadID }, ["E", "C", "G"])
    }

    /// The row at the top of the pane is the one newer mail joined: it has
    /// moved up to the new page, and the next row he could see keeps its
    /// place instead of the list following it up.
    func testWhenTheTopRowItselfMovesUpTheNextRowStaysPut() throws {
        let before = grouped(folder)
        let place = ListPlace(rows: before, visible: onScreen(from: 3, count: 5, offset: -30),
                              selected: [])
        let after = grouped([letter(160, thread: "D")] + folder)
        let landing = try XCTUnwrap(place.landing(in: after))
        XCTAssertEqual(after[landing.row].id, "7/145", "E")
        XCTAssertEqual(landing.offset, -30 + Self.row, "where E was")
    }

    /// A row taken off by a Delete, the top one: the rows below close up
    /// into its place, as in Mail (B-093). The next used to keep its own
    /// place, and the row above come down into the gap.
    func testARowTakenOffHasTheRowsBelowCloseUpIntoItsPlace() throws {
        let before = grouped(folder)
        let place = ListPlace(rows: before, visible: onScreen(from: 3, count: 5, offset: 10),
                              selected: [])
        let after = grouped(folder.filter { $0.id != "7/146" })
        let landing = try XCTUnwrap(place.landing(in: after))
        XCTAssertEqual(after[landing.row].id, "7/145")
        XCTAssertEqual(landing.offset, 10, "where D was")
    }

    /// The grouping switch splits every row or merges them. Split, the row
    /// at the top is its newest letter's; merged, a row he could see that
    /// is headed by none of them is found by any letter in it.
    func testTheGroupingSwitchKeepsHisPlaceBothWays() throws {
        let rows = grouped(folder)
        let split = MessageThread.rows(for: folder, grouped: false)
        let atA = ListPlace(rows: rows, visible: onScreen(from: 0, count: 3, offset: -10),
                            selected: [])
        let landing = try XCTUnwrap(atA.landing(in: split))
        XCTAssertEqual(split[landing.row].id, "7/150")
        XCTAssertEqual(landing.offset, -10)

        // Ungrouped, with A's older letter the only row on screen.
        let older = ListPlace(rows: split, visible: [(3, -20)], selected: [3])
        let merged = try XCTUnwrap(older.landing(in: rows))
        XCTAssertEqual(rows[merged.row].id, "7/150", "the row A's letters are in now")
        XCTAssertEqual(merged.offset, -20)
        XCTAssertEqual(older.selection(in: rows, opened: nil, editing: false), [merged.row])

        XCTAssertNil(atA.landing(in: grouped([letter(10, thread: "Z")])), "nothing of it is left")
    }

    /// The offset that puts a row back, held within what the table can
    /// scroll to: the top, and near the end of a short list, the end.
    func testTheOffsetStaysWithinWhatTheTableCanScrollTo() {
        XCTAssertEqual(ListPlace.contentOffset(rowTop: 1_000, offset: -30, range: -64...5_000,
                                               current: 900), 1_030)
        XCTAssertEqual(ListPlace.contentOffset(rowTop: 40, offset: 200, range: -64...5_000,
                                               current: 0), -64)
        XCTAssertEqual(ListPlace.contentOffset(rowTop: 4_900, offset: 0, range: -64...4_500,
                                               current: 4_000), 4_500)
        XCTAssertNil(ListPlace.contentOffset(rowTop: 4_900, offset: 0, range: -64...4_500,
                                             current: 4_500), "at the end already")
    }

    /// A regroup that moved nothing leaves the offset alone, even while the
    /// list is bouncing past either end, outside what it can rest at. It
    /// used to be kept in range before it was compared, and a page that
    /// only joined conversations already listed, or a letter marked read,
    /// during a bounce snapped the list back under his finger.
    func testARowAlreadyInPlaceIsLeftAloneMidBounce() {
        // Pulled 40 points down past the top; the top row is where it was.
        XCTAssertNil(ListPlace.contentOffset(rowTop: 0, offset: 104, range: -64...5_000,
                                             current: -104))
        // Flung 60 points past the end.
        XCTAssertNil(ListPlace.contentOffset(rowTop: 4_560, offset: 0, range: -64...4_500,
                                             current: 4_560))
        // A row that did move is put back, and kept in range.
        XCTAssertEqual(ListPlace.contentOffset(rowTop: 96, offset: 104, range: -64...5_000,
                                               current: -104), -8)
    }

    // MARK: - A search replacing the list, and ending (list-4)

    /// A search's results go to the top, and so does every result set after
    /// them as he types on; cancelling it puts the folder back where he was
    /// in it, by the rows he could see, even though one of them went while
    /// the search showed.
    func testResultsGoToTheTopAndTheFolderComesBackWhereHeWas() throws {
        var places = ListPlaces()
        let rows = grouped(folder)
        let deep = ListPlace(rows: rows, visible: onScreen(from: 6, count: 4, offset: -12),
                             selected: [7])

        XCTAssertEqual(places.resultsShown(overFolder: true, here: deep), .top)
        XCTAssertEqual(places.resultsShown(overFolder: false, here: nil), .top,
                       "more letters typed: the new hits from the top")
        XCTAssertEqual(places.folder, deep, "the folder's place is the one before the search")

        // G, the row at the top of the pane, binned from the reading pane
        // while the search showed: the rows below close up into its place
        // (B-093).
        let move = places.searchEnded(showingResults: true)
        guard case .back(let place) = move else { return XCTFail("\(move)") }
        let now = grouped(folder.filter { $0.id != "7/143" })
        let landing = try XCTUnwrap(place.landing(in: now))
        XCTAssertEqual(now[landing.row].id, "7/142", "H, where G was")
        XCTAssertEqual(landing.offset, -12)
        XCTAssertNil(places.folder)
    }

    /// A search that could not be run replaces the list too, and goes to the
    /// top, where "Could not search" is.
    func testASearchThatCouldNotBeRunGoesToTheTopAndKeepsTheFolder() {
        var places = ListPlaces()
        let deep = ListPlace(rows: grouped(folder), visible: onScreen(from: 8, count: 2, offset: 0),
                             selected: [])
        XCTAssertEqual(places.resultsShown(overFolder: true, here: deep), .top)
        XCTAssertEqual(places.searchEnded(showingResults: true), .back(deep))
    }

    /// The field cleared before any results came: nothing on screen was
    /// replaced, and nothing moves. A Refresh or a jump while the search
    /// showed replaced the folder too, and drops its place.
    func testNothingMovesWhenNothingWasReplacedAndARefreshForgetsTheFolder() {
        var places = ListPlaces()
        XCTAssertEqual(places.searchEnded(showingResults: false), .stay)

        let deep = ListPlace(rows: grouped(folder), visible: onScreen(from: 5, count: 2, offset: 0),
                             selected: [])
        _ = places.resultsShown(overFolder: true, here: deep)
        XCTAssertEqual(places.replaced(), .top)
        XCTAssertNil(places.folder)
        XCTAssertEqual(places.searchEnded(showingResults: false), .stay)

        // A folder with no rows to see, then results: the top when they go.
        _ = places.resultsShown(overFolder: true, here: nil)
        XCTAssertEqual(places.searchEnded(showingResults: true), .top)
    }

    /// A Delete or a Move from Edit mode, or a draft saved in Drafts, fetches
    /// the newest page afresh, and the rows he could see stay where they
    /// were in it. It used to go to the top, like a Refresh, and before that
    /// to whatever row the old offset now showed. Further down than the
    /// newest page reaches, nothing of it is found, and the list goes to
    /// the top. From a search's results, the folder comes back where he was.
    func testTheListFetchedAfterHisOwnEditKeepsHisPlace() throws {
        var places = ListPlaces()
        let rows = grouped(folder)
        // D at the top of the pane; E and F ticked, and deleted.
        let here = ListPlace(rows: rows, visible: onScreen(from: 3, count: 5, offset: -20),
                             selected: [4, 5])
        let move = places.refetched(here: here)
        XCTAssertEqual(move, .back(here))
        guard case .back(let place) = move else { return XCTFail("\(move)") }
        let fetched = grouped(folder.filter { $0.id != "7/145" && $0.id != "7/144" })
        let landing = try XCTUnwrap(place.landing(in: fetched))
        XCTAssertEqual(fetched[landing.row].id, "7/146", "D, where it was")
        XCTAssertEqual(landing.offset, -20)

        let past = ListPlace(rows: grouped([letter(90, thread: "X"), letter(89, thread: "Y")]),
                             visible: [(0, 0), (1, Self.row)], selected: [])
        guard case .back(let far) = places.refetched(here: past) else { return XCTFail() }
        XCTAssertNil(far.landing(in: fetched), "not on the newest page: to the top")

        XCTAssertEqual(places.replaced(), .top, "a Refresh still goes to the top")

        let deep = ListPlace(rows: rows, visible: onScreen(from: 6, count: 3, offset: 0),
                             selected: [])
        _ = places.resultsShown(overFolder: true, here: deep)
        XCTAssertEqual(places.refetched(here: past), .back(deep), "from results: the folder's place")
        XCTAssertNil(places.folder)
    }

    // MARK: - The folder's previews after a search (list-9)

    /// Cancelling a search asks again for the folder's previews its own pass
    /// never fetched, because the search replaced the list first: all but
    /// the ones a hit has brought, under the same id or as the same letter
    /// from All Mail, and the ones taken off by hand.
    @MainActor
    func testEndingASearchReturnsTheFolderPreviewsStillToFetch() {
        let list = ListLetters()
        let inbox = [letter(150, thread: "A", preview: "Came before the search"),
                     letter(149, thread: "B"), letter(148, thread: "C"),
                     letter(147, thread: "D"), letter(146, thread: "E")]
        _ = list.fetchedAfresh(inbox)
        // An All Mailboxes search: B's copy in All Mail, and C and D.
        let b = inbox[1]
        let allMail = MessageSummary(id: "9/9149", mailboxID: Server.allMail, sender: b.sender,
                                     subject: b.subject, preview: "Fetched for the hit",
                                     date: b.date, isRead: true, isFlagged: false,
                                     threadID: b.threadID)
        list.showResults([allMail, letter(148, thread: "C"), letter(147, thread: "D")])
        list.apply(previews: ["7/148": "Fetched for the hit under the Inbox's id"], in: "INBOX")
        // D binned from the pane while the search showed.
        list.take(letter(147, thread: "D"), fromEveryFolder: false)
        list.removalLanded(letter(147, thread: "D"), fromEveryFolder: false)

        let asked = list.endSearch()

        XCTAssertEqual(asked.map(\.id), ["7/146"], "only E still has to be fetched")
        XCTAssertFalse(list.isSearching)
        XCTAssertEqual(list.folder.map(\.preview), ["Came before the search", "Fetched for the hit",
                                                    "Fetched for the hit under the Inbox's id",
                                                    "", ""])
    }

    /// Over the scripted server: the Inbox's first page, a search that
    /// replaces it before its previews are in, and the search cancelled.
    /// The previews asked for then fill every row, where they used to stay
    /// blank until Refresh.
    @MainActor
    func testTheFolderPreviewsCutOffByASearchAreFetchedWhenItEnds() async throws {
        let server = ScriptedIMAPServer()
        let suite = "ListPlaceTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = IMAPMailRepository(account: server.account, password: server.password,
                                            transport: server.transportFactory,
                                            recipients: RecipientBook(defaults: defaults),
                                            shelf: keptShelf(for: server.account))
        let list = ListLetters()
        let page = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)
        let unpreviewed = list.fetchedAfresh(page)
        XCTAssertEqual(unpreviewed.count, 20)

        // The pass stops as the search replaces the list, having filled none.
        var current = true
        await PreviewPass.run(PreviewPass.groups(for: unpreviewed),
                              fetch: { ids, mailbox in
                                  current = false
                                  return try await repository.previews(for: ids, in: mailbox)
                              },
                              isCurrent: { current },
                              apply: { list.apply(previews: $0, in: $1.mailboxID) })
        XCTAssertTrue(list.folder.allSatisfy { $0.preview.isEmpty })
        list.showResults(try await repository.search(in: "inbox", query: "garden",
                                                     scope: .currentMailbox, beforeUID: nil,
                                                     limit: 50))

        let asked = list.endSearch()
        XCTAssertEqual(asked.count, 20)
        await PreviewPass.run(PreviewPass.groups(for: asked),
                              fetch: { try await repository.previews(for: $0, in: $1) },
                              isCurrent: { true },
                              apply: { list.apply(previews: $0, in: $1.mailboxID) })
        XCTAssertEqual(list.folder.filter { $0.preview.isEmpty }.map(\.id), [])
        XCTAssertEqual(server.violations, [])
    }

    // MARK: - New mail the watch has found (B-049)

    /// What a check brought: K and L new, a reply in G's conversation, and
    /// E taken out elsewhere.
    private var news: FolderNews {
        FolderNews(arrived: [letter(160, thread: "K"), letter(159, thread: "G"),
                             letter(158, thread: "L")],
                   gone: ["7/145"])
    }

    /// Every row, as the letters in it.
    private func letters(of rows: [MessageThread]) -> [[String]] {
        rows.map { $0.messages.map(\.id) }
    }

    /// The folder's letters on the list, as the first page leaves them.
    @MainActor
    private func listed() -> ListLetters {
        let list = ListLetters()
        _ = list.fetchedAfresh(folder)
        return list
    }

    /// Scrolled down, D at the top of the pane and F open in the reading
    /// pane: the news is held, and nothing on the list changes, not a row,
    /// not where it sits on screen, not the highlight. Put on, it would have
    /// taken G's row up out from under him and closed E's gap, and every
    /// row he could see below D would have been another letter.
    @MainActor
    func testWhileHeIsScrolledDownNewsIsHeldAndNothingMoves() throws {
        let list = listed()
        let before = grouped(list.shown)
        let place = ListPlace(rows: before, visible: onScreen(from: 3, count: 7, offset: -30),
                              selected: [5])

        XCTAssertFalse(ListPlaces.showsNews(atTop: false, searching: false, ticked: false,
                                            touching: false))
        XCTAssertTrue(list.hold(news))
        let after = grouped(list.shown)
        XCTAssertEqual(letters(of: after), letters(of: before))
        let landing = try XCTUnwrap(place.landing(in: after))
        XCTAssertEqual(landing.row, 3)
        XCTAssertEqual(landing.offset, -30)
        XCTAssertEqual(place.selection(in: after, opened: nil, editing: false), [5])

        // What putting it on there and then would have done.
        let putOn = listed()
        putOn.hold(news)
        putOn.showNews()
        let moved = grouped(putOn.shown)
        XCTAssertNotEqual(moved[4..<9].map(\.id), before[4..<9].map(\.id))
    }

    /// Edit mode with ticks, at the top: held, and every tick stays on its
    /// letter. Without a tick Edit mode holds nothing.
    @MainActor
    func testWhileHeTicksInEditModeNewsIsHeldAndTheTicksStay() {
        let list = listed()
        let before = grouped(list.shown)
        let place = ListPlace(rows: before, visible: onScreen(from: 0, count: 8, offset: 0),
                              selected: [0, 2, 6])
        XCTAssertFalse(ListPlaces.showsNews(atTop: true, searching: false, ticked: true,
                                            touching: false))
        list.hold(news)
        XCTAssertEqual(letters(of: grouped(list.shown)), letters(of: before))
        XCTAssertEqual(place.selection(in: grouped(list.shown), opened: nil, editing: true),
                       [0, 2, 6])
        XCTAssertTrue(ListPlaces.showsNews(atTop: true, searching: false, ticked: false,
                                           touching: false))
    }

    /// A search showing, or a finger on the list, holds it too. The search
    /// ended with the folder back at its top, and the news goes on.
    @MainActor
    func testASearchOrAFingerOnTheListHoldsNewsUntilHeIsBackAtTheTop() {
        let list = listed()
        var places = ListPlaces()
        let top = ListPlace(rows: grouped(list.shown), visible: onScreen(from: 0, count: 6, offset: 0),
                            selected: [])
        XCTAssertEqual(places.resultsShown(overFolder: true, here: top), .top)
        let hits = [letter(148, thread: "C")]
        list.showResults(hits)

        XCTAssertFalse(ListPlaces.showsNews(atTop: true, searching: true, ticked: false,
                                            touching: false))
        XCTAssertFalse(ListPlaces.showsNews(atTop: true, searching: false, ticked: false,
                                            touching: true))
        list.hold(news)
        XCTAssertEqual(list.shown, hits, "the results are left alone")

        list.endSearch()
        XCTAssertEqual(places.searchEnded(showingResults: true), .back(top))
        let added = list.showNews()
        XCTAssertEqual(added.map(\.id), ["7/160", "7/159", "7/158"])
        XCTAssertEqual(grouped(list.shown).prefix(4).map(\.id), ["7/160", "7/159", "7/158", "7/150"])
        XCTAssertFalse(list.shown.contains { $0.id == "7/145" }, "E has gone")
    }

    /// At the top, the new rows go on above and the list stays at the top,
    /// where he sees them. The letter open in the reading pane keeps its
    /// highlight, on its row wherever that now is; F's is two rows down,
    /// and G's, joined by the reply, is second from the top.
    @MainActor
    func testAtTheTopTheNewRowsGoOnAboveAndTheOpenLetterKeepsItsHighlight() throws {
        XCTAssertTrue(ListPlaces.showsNews(atTop: true, searching: false, ticked: false,
                                           touching: false))
        for (open, opened) in [(5, "7/144"), (6, "7/143")] {
            let list = listed()
            let before = grouped(list.shown)
            let place = ListPlace(rows: before, visible: onScreen(from: 0, count: 8, offset: 0),
                                  selected: [open])
            list.hold(news)
            list.showNews()
            let after = grouped(list.shown)
            XCTAssertEqual(after.map { $0.newest.threadID }, ["K", "G", "L", "A", "B", "C", "D",
                                                              "F", "H", "I", "J"])
            let selected = place.selection(in: after, opened: nil, editing: false)
            XCTAssertEqual(selected.count, 1)
            XCTAssertTrue(after[try XCTUnwrap(selected.first)].messages.contains { $0.id == opened })
        }
    }

    /// Only what is new to the list counts, which is when the folder counts
    /// are swept: the same news again is not, nor a letter gone that is off
    /// the list already. A letter that came and went while he was scrolled
    /// down never goes on at all.
    @MainActor
    func testNewsAlreadyHeldOrShownIsNotNewsAgain() {
        let list = listed()
        XCTAssertTrue(list.hold(news))
        XCTAssertFalse(list.hold(news))
        list.showNews()
        XCTAssertFalse(list.hold(news))
        XCTAssertFalse(list.holdsNews)

        XCTAssertTrue(list.hold(FolderNews(arrived: [letter(170, thread: "M")])))
        XCTAssertTrue(list.hold(FolderNews(gone: ["7/170"])))
        XCTAssertEqual(list.showNews(), [])
        XCTAssertFalse(list.shown.contains { $0.id == "7/170" })
        XCTAssertEqual(list.watched.first, "7/160", "the next check goes by what is on the list")
    }

    /// A Refresh, or anything else that fetches the list afresh, lists what
    /// was held with the rest, and a day jumped to has a top of its own:
    /// either drops what was held, a fetch afresh owed included. Kept, the
    /// held letters went on the top again when he was next there, a second
    /// row each, and a fetch afresh owed and already made was made again at
    /// every return to the top.
    @MainActor
    func testFetchingAfreshOrJumpingToADayDropsWhatWasHeld() {
        let list = listed()
        list.hold(news)
        list.hold(FolderNews(refetch: true))
        let page = news.arrived + folder.filter { $0.id != "7/145" }
        _ = list.fetchedAfresh(page)
        XCTAssertFalse(list.holdsNews)
        XCTAssertFalse(list.refetchOwed)
        XCTAssertEqual(list.putNewsOn(atTop: true, searching: false, ticked: false, touching: false),
                       .wait)
        XCTAssertEqual(list.shown.map(\.id), page.map(\.id))

        list.hold(FolderNews(arrived: [letter(170, thread: "M")], refetch: true))
        let day = Array(folder.suffix(4))
        list.showWindow(day)
        XCTAssertFalse(list.holdsNews)
        XCTAssertFalse(list.refetchOwed)
        XCTAssertEqual(list.putNewsOn(atTop: true, searching: false, ticked: false, touching: false),
                       .wait)
        XCTAssertEqual(list.shown.map(\.id), day.map(\.id))
    }

    /// What the watch checks the folder against: every letter the list
    /// holds, the held ones first, while it starts at the folder's newest
    /// letter. Nothing for a day jumped to, whose lowest letter is not the
    /// folder's and above which every letter would come back as new; for a
    /// search showing; or for a list whose first page never came, which
    /// would search the whole folder. For those only the Inbox's count is
    /// checked. An Inbox fetched and empty is checked from nothing.
    @MainActor
    func testTheWatchChecksOnlyAListThatStartsAtTheNewestLetter() {
        let empty = ListLetters()
        XCTAssertNil(empty.toWatch(fromNewest: true, fetched: false), "the first page never came")
        XCTAssertEqual(empty.toWatch(fromNewest: true, fetched: true), [])

        let list = listed()
        XCTAssertEqual(list.toWatch(fromNewest: true, fetched: true), folder.map(\.id))
        XCTAssertNil(list.toWatch(fromNewest: false, fetched: true), "a day")
        list.hold(FolderNews(arrived: [letter(170, thread: "M")]))
        XCTAssertEqual(list.toWatch(fromNewest: true, fetched: true), ["7/170"] + folder.map(\.id))
        list.showResults([letter(148, thread: "C")])
        XCTAssertNil(list.toWatch(fromNewest: true, fetched: true), "a search")
    }

    /// A day jumped to while the check was out does not take its news and
    /// holds none of it; the watch searches for it again at the next check
    /// of the list. The list at the folder's newest takes it, and says
    /// whether any of it was new. What is held goes on only at the top with
    /// nothing in the way; a list owed a fetch afresh is fetched instead,
    /// and until it has been, nothing goes on.
    @MainActor
    func testNewsIsTakenByTheFoldersNewestAndPutOnOnlyAtTheTop() {
        let list = listed()
        XCTAssertEqual(list.take(news, fromNewest: false), .notTaken)
        XCTAssertFalse(list.holdsNews)
        XCTAssertEqual(list.take(FolderNews(), fromNewest: true), .known)
        XCTAssertEqual(list.take(news, fromNewest: true), .new)
        XCTAssertEqual(list.take(news, fromNewest: true), .known)

        XCTAssertEqual(list.putNewsOn(atTop: false, searching: false, ticked: false, touching: false),
                       .wait)
        XCTAssertEqual(list.putNewsOn(atTop: true, searching: false, ticked: false, touching: true),
                       .wait)
        XCTAssertEqual(list.putNewsOn(atTop: true, searching: false, ticked: false, touching: false),
                       .shown(news.arrived))
        XCTAssertEqual(list.putNewsOn(atTop: true, searching: false, ticked: false, touching: false),
                       .wait, "nothing is held")

        XCTAssertEqual(list.take(FolderNews(arrived: [letter(170, thread: "M")], refetch: true),
                                 fromNewest: true), .new)
        for _ in 1...2 {
            XCTAssertEqual(list.putNewsOn(atTop: true, searching: false, ticked: false,
                                          touching: false), .refetch)
        }
        XCTAssertFalse(list.shown.contains { $0.id == "7/170" })
    }

    /// The top is the offset of the table's top inset, to half a point.
    func testTheTopIsWhereTheFirstRowIsAgainstThePane() {
        XCTAssertTrue(ListPlaces.isAtTop(offset: -64, topInset: 64))
        XCTAssertTrue(ListPlaces.isAtTop(offset: -63.6, topInset: 64))
        XCTAssertTrue(ListPlaces.isAtTop(offset: -104, topInset: 64), "pulled down past it")
        XCTAssertFalse(ListPlaces.isAtTop(offset: -63, topInset: 64))
        XCTAssertFalse(ListPlaces.isAtTop(offset: 200, topInset: 64))
    }

    // MARK: - The rows he can see (B-093)

    /// The list as the iPad lays it out, near enough: the search band 43
    /// points tall on top of the rows, the table 810 tall, 74 points of
    /// status and navigation bar over its top and 50 of toolbar under it.
    private static let band = 43.0
    private static let barTop = 74.0
    private static let barBottom = 50.0
    private static let height = 810.0

    /// The top of row `row` in the table, as `rectForRow` gives it.
    private func rowTop(_ row: Int) -> Double { Self.band + Double(row) * Self.row }

    /// Twenty rows, a letter each, newest first: row r is the letter
    /// 200 - r, alone in its conversation. Longer than the pane.
    private var twenty: [MessageSummary] {
        (181...200).reversed().map { letter($0, thread: "t\($0)") }
    }

    /// What of the table is in sight scrolled to `offset`, with `count` rows,
    /// the table `height` tall: 810 as the iPad is held for the rounds, or
    /// another, the iPad turned.
    private func sight(at offset: Double, rows count: Int,
                       height: Double = ListPlaceTests.height) -> TableSight {
        TableSight(offset: offset, height: height, barTop: Self.barTop,
                   barBottom: Self.barBottom, band: Self.band,
                   content: Self.band + Double(count) * Self.row)
    }

    /// The rows the table has on screen scrolled to `offset`: every row in
    /// its bounds, the ones under its bars too.
    private func onScreen(at offset: Double, rows count: Int, height: Double = ListPlaceTests.height)
        -> [(row: Int, top: Double, bottom: Double)] {
        (0..<count).map { ($0, rowTop($0), rowTop($0) + Self.row) }
            .filter { $0.2 > offset && $0.1 < offset + height }
    }

    /// The place taken at `offset`, as `MessageListViewController.place()`
    /// takes it.
    private func place(in rows: [MessageThread], at offset: Double,
                       height: Double = ListPlaceTests.height) -> ListPlace {
        ListPlace(rows: rows, onScreen: onScreen(at: offset, rows: rows.count, height: height),
                  sight: sight(at: offset, rows: rows.count, height: height), selected: [])
    }

    /// The place as it used to be taken: every row on screen.
    private func everyRow(in rows: [MessageThread], at offset: Double) -> ListPlace {
        ListPlace(rows: rows, visible: onScreen(at: offset, rows: rows.count)
                    .map { ($0.row, $0.top - offset) }, selected: [])
    }

    /// Where each letter heading a row is, down from the top of the pane, with
    /// the table at `offset`.
    private func onPane(_ rows: [MessageThread], at offset: Double) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, rowTop($0.offset) - offset) })
    }

    /// The offset `place` puts the table at in `rows`, from `offset`, as
    /// `scroll(to:in:)` does: the row landed on where it was, within what
    /// the table can scroll to, or left alone.
    private func offset(after place: ListPlace, in rows: [MessageThread], from offset: Double,
                        height: Double = ListPlaceTests.height) throws -> Double {
        let landing = try XCTUnwrap(place.landing(in: rows))
        let content = Self.band + Double(rows.count) * Self.row
        let range = -Self.barTop...max(-Self.barTop, content + Self.barBottom - height)
        return ListPlace.contentOffset(rowTop: rowTop(landing.row), offset: landing.offset,
                                       range: range, current: offset) ?? offset
    }

    /// The rows he could see, at `offset` in `rows`: their letters.
    private func inView(_ rows: [MessageThread], at offset: Double,
                        height: Double = ListPlaceTests.height) -> [String] {
        ListPlace.inSight(onScreen(at: offset, rows: rows.count, height: height),
                          sight: sight(at: offset, rows: rows.count, height: height))
            .map { rows[$0.row].id }
    }

    /// The iPad's Delete (B-093): the letter open in the pane, its row
    /// scrolled just above the top of the list, under the bars and the
    /// band, and the row above it under the status bar. Delete in the pane:
    /// its row is taken out at the tap, and every row he can see stays
    /// where it was. The row held used to be the first on screen, the one
    /// under the status bar, and the gap closed below it: every row in view
    /// moved up by one at once.
    func testADeleteJustAboveTheListLeavesEveryRowInViewWhereItWas() throws {
        let before = grouped(twenty)
        let from = 310.0
        // Row 3, "7/197", ends where the band does; row 2 is under the bar.
        XCTAssertEqual(rowTop(3) + Self.row, from + Self.barTop + Self.band)
        XCTAssertEqual(onScreen(at: from, rows: 20).map(\.row), Array(2...11))
        let seen = inView(before, at: from)
        XCTAssertEqual(seen, (190...196).reversed().map { "7/\($0)" }, "rows 4 to 10")
        let here = place(in: before, at: from)
        XCTAssertEqual(here.seen.first?.id, "7/196")
        XCTAssertEqual(here.seen.first?.offset, 117)

        let after = grouped(twenty.filter { $0.id != "7/197" })
        let to = try offset(after: here, in: after, from: from)
        XCTAssertEqual(to, from - Self.row, "the row's height taken off above, out of sight")
        let was = onPane(before, at: from)
        let now = onPane(after, at: to)
        for id in seen { XCTAssertEqual(now[id], was[id], id) }

        // Held by every row on screen, as it was: the one under the status
        // bar stays, and everything he could see goes up a row.
        let old = try offset(after: everyRow(in: before, at: from), in: after, from: from)
        XCTAssertEqual(old, from, "nothing scrolled")
        for id in seen { XCTAssertEqual(onPane(after, at: old)[id], was[id].map { $0 - Self.row }, id) }
    }

    /// A row is in sight with a point or more of it between the bars, below
    /// the band: one with ten points below the band is held, at its own
    /// offset, negative for a row partly under the band; half a point is
    /// not enough. Under the toolbar the same.
    func testARowIsInSightWithAPointOfItBelowTheBand() {
        let rows = [(row: 2, top: 235.0, bottom: 331.0), (row: 3, top: 331.0, bottom: 427.0),
                    (row: 4, top: 427.0, bottom: 523.0), (row: 10, top: 1_003.0, bottom: 1_099.0),
                    (row: 11, top: 1_099.0, bottom: 1_195.0)]
        func held(at offset: Double) -> [Int] {
            ListPlace.inSight(rows, sight: sight(at: offset, rows: 20)).map(\.row)
        }
        XCTAssertEqual(held(at: 310), [4, 10], "the band ends where row 3 does")
        XCTAssertEqual(ListPlace.inSight(rows, sight: sight(at: 310, rows: 20)).map(\.offset),
                       [117, 693])
        XCTAssertEqual(held(at: 300), [3, 4, 10], "ten points of row 3 below the band")
        XCTAssertEqual(ListPlace.inSight(rows, sight: sight(at: 300, rows: 20)).first?.offset, 31)
        XCTAssertEqual(held(at: 309.5), [4, 10], "half a point")
        // The toolbar's top 760 points below the offset: at 310, row 10
        // shows 67 points above it and row 11 none; at 340.5, a point and a
        // half of row 11; at 339.5, half a point.
        XCTAssertEqual(held(at: 340.5), [4, 10, 11])
        XCTAssertEqual(held(at: 339.5), [4, 10])
    }

    /// Nothing in sight, a pane too short for a row below the band, or one
    /// not laid out: every row on screen, as before. Nothing on screen,
    /// nothing.
    func testWithNoRowInSightEveryRowOnScreenIsTaken() {
        let rows = [(row: 3, top: 331.0, bottom: 427.0), (row: 4, top: 427.0, bottom: 523.0)]
        let short = TableSight(offset: 310, height: 160, barTop: 74, barBottom: 50, band: 43,
                               content: 1_963)
        let taken = ListPlace.inSight(rows, sight: short)
        XCTAssertEqual(taken.map(\.row), [3, 4])
        XCTAssertEqual(taken.map(\.offset), [21, 117])
        XCTAssertNil(ListPlace.justAbove(rows, sight: short), "no row above the ones taken")
        XCTAssertTrue(ListPlace.inSight([], sight: sight(at: 0, rows: 0)).isEmpty)
        XCTAssertNil(ListPlace.justAbove([], sight: sight(at: 0, rows: 0)))
    }

    /// The first row he can see taken out, the row above it under the band
    /// (B-093): the rows below close up into its place, as in Mail, the row
    /// above stays where it was, out of sight, and the list is not
    /// scrolled. Whatever of the two shows: the letter's row whole below
    /// the band, at 214, or twenty points of it, at 290, and the row above
    /// with nothing of it in sight or half a point, when it is the row just
    /// above the first he can see (`above`), or a point or ten, when it is
    /// the first he can see itself. With less than a point, the rows below
    /// used to stay where they were, and the row above came down into the
    /// gap.
    func testTheFirstRowInSightTakenOutClosesUpTheRowsBelowWhateverOfTheRowAboveShows() throws {
        let before = grouped(twenty)
        let after = grouped(twenty.filter { $0.id != "7/197" })
        let here = place(in: before, at: 214)
        XCTAssertEqual(here.seen.first?.id, "7/197", "row 3, its top where the band ends")
        XCTAssertEqual(here.seen.first?.offset, 117)
        XCTAssertEqual(here.above?.id, "7/198", "row 2, under the band")
        XCTAssertEqual(here.above?.offset, 21)
        XCTAssertEqual(inView(before, at: 290).first, "7/197", "twenty points of it")
        XCTAssertEqual(place(in: before, at: 290).above?.id, "7/198")
        XCTAssertEqual(inView(before, at: 213.5).first, "7/197", "half a point of the row above")
        XCTAssertEqual(inView(before, at: 213).first, "7/198", "a point of it")
        XCTAssertEqual(place(in: before, at: 213).above?.id, "7/199")

        for from in [214.0, 290.0, 213.5, 213.0, 204.0] {
            let to = try offset(after: place(in: before, at: from), in: after, from: from)
            XCTAssertEqual(to, from, "\(from): not scrolled")
            let was = onPane(before, at: from)
            let now = onPane(after, at: to)
            XCTAssertEqual(now["7/198"], was["7/198"], "\(from): the row above where it was")
            XCTAssertEqual(now["7/196"], was["7/197"], "\(from): the next in its place")
            for row in before[4...11] {
                XCTAssertEqual(now[row.id], was[row.id].map { $0 - Self.row }, "\(from): \(row.id)")
            }
        }
    }

    /// A row taken out above every row he can see closes out of sight:
    /// the one just above the first he can see, under the band, or the one
    /// above that, under the status bar, and every row in view stays where
    /// it was. One taken out below the first he can see: the rows above it
    /// stay where they were, and the rows below close up into its place.
    func testARowTakenOutAboveOrBelowTheFirstInSightLeavesTheRowsAboveItWhereTheyWere() throws {
        let before = grouped(twenty)
        let from = 310.0
        let was = onPane(before, at: from)
        let seen = inView(before, at: from)
        XCTAssertEqual(seen.first, "7/196")
        XCTAssertEqual(place(in: before, at: from).above?.id, "7/197")
        for gone in ["7/197", "7/198"] {
            let after = grouped(twenty.filter { $0.id != gone })
            let to = try offset(after: place(in: before, at: from), in: after, from: from)
            XCTAssertEqual(to, from - Self.row, gone)
            for id in seen { XCTAssertEqual(onPane(after, at: to)[id], was[id], "\(gone): \(id)") }
        }
        let after = grouped(twenty.filter { $0.id != "7/194" })
        let to = try offset(after: place(in: before, at: from), in: after, from: from)
        XCTAssertEqual(to, from)
        let now = onPane(after, at: to)
        for id in ["7/197", "7/196", "7/195"] { XCTAssertEqual(now[id], was[id], id) }
        for id in ["7/193", "7/192", "7/191", "7/190"] {
            XCTAssertEqual(now[id], was[id].map { $0 - Self.row }, id)
        }
    }

    /// The list's first row taken out, some of it in sight and no row on
    /// screen above it: the rows below close up into its place and the list
    /// is not scrolled, at the top, pulled down past it, and a little way
    /// down with most of the row under the band. It used to be put back at
    /// the top a little way down, the next row whole below the band.
    func testTheListsFirstRowTakenOutClosesUpTheRowsBelowWithNoRowAbove() throws {
        let before = grouped(twenty)
        let after = grouped(twenty.filter { $0.id != "7/200" })
        for from in [-74.0, -104.0, 0.0, 20.0] {
            let here = place(in: before, at: from)
            XCTAssertEqual(here.seen.first?.id, "7/200", "\(from)")
            XCTAssertNil(here.above, "\(from)")
            let to = try offset(after: here, in: after, from: from)
            XCTAssertEqual(to, from, "\(from): not scrolled")
            let was = onPane(before, at: from)
            let now = onPane(after, at: to)
            for row in before[1...8] {
                XCTAssertEqual(now[row.id], was[row.id].map { $0 - Self.row }, "\(from): \(row.id)")
            }
        }
    }

    /// Edit mode's Delete of several rows at once (`ListBatch`): the rows
    /// ticked go, and the rows below close up into the first one's place,
    /// the row above it staying where it was. Every row he could see
    /// ticked: the row above stays, and the list is not scrolled. The row
    /// above ticked too, before it went under the band: it closes out of
    /// sight, and the next row he could see comes up into the first one's
    /// place.
    func testEditsDeleteOfSeveralRowsClosesUpIntoTheFirstOnesPlace() throws {
        let before = grouped(twenty)
        let from = 310.0
        let was = onPane(before, at: from)
        let here = place(in: before, at: from)

        let three = grouped(twenty.filter { !["7/196", "7/195", "7/193"].contains($0.id) })
        var to = try offset(after: here, in: three, from: from)
        XCTAssertEqual(to, from)
        var now = onPane(three, at: to)
        XCTAssertEqual(now["7/197"], was["7/197"], "the row above where it was")
        XCTAssertEqual(now["7/194"], was["7/196"])
        XCTAssertEqual(now["7/192"], was["7/195"])
        XCTAssertEqual(now["7/191"], was["7/194"])

        let all = grouped(twenty.filter { !inView(before, at: from).contains($0.id) })
        to = try offset(after: here, in: all, from: from)
        XCTAssertEqual(to, from)
        now = onPane(all, at: to)
        XCTAssertEqual(now["7/197"], was["7/197"])
        XCTAssertEqual(now["7/189"], was["7/196"])

        let andAbove = grouped(twenty.filter { $0.id != "7/197" && $0.id != "7/196" })
        to = try offset(after: here, in: andAbove, from: from)
        XCTAssertEqual(to, from - Self.row)
        now = onPane(andAbove, at: to)
        XCTAssertEqual(now["7/195"], was["7/196"], "the next in the first one's place")
        XCTAssertEqual(now["7/198"], was["7/197"], "still under the band")
    }

    /// The first row he can see a conversation of two letters, its newest
    /// taken out from the reading pane. The other next in the list: the
    /// row stays where it is, headed by it, and nothing moves. The other
    /// far down: the row goes down to it, and the rows below close up into
    /// its place, as for a row taken out. The same for the list's first
    /// row, with no row above it.
    func testAConversationsNewestLetterTakenOutLeavesItsRowOrClosesUp() throws {
        // Row 4 at 310, under the row above; the list's first row at 20,
        // two points of it in sight.
        for (first, other, from) in [(196, 195, 310.0), (196, 185, 310.0),
                                     (200, 199, 20.0), (200, 185, 20.0)] {
            let letters = twenty.map { $0.id == "7/\(other)" ? letter(other, thread: "t\(first)") : $0 }
            let before = grouped(letters)
            let row = try XCTUnwrap(before.firstIndex { $0.id == "7/\(first)" })
            let what = "\(first) and \(other) at \(from)"
            XCTAssertEqual(before[row].messages.map(\.id), ["7/\(first)", "7/\(other)"], what)
            XCTAssertEqual(inView(before, at: from).first, "7/\(first)", what)
            let after = grouped(letters.filter { $0.id != "7/\(first)" })
            let to = try offset(after: place(in: before, at: from), in: after, from: from)
            XCTAssertEqual(to, from, "\(what): not scrolled")
            let was = onPane(before, at: from)
            let now = onPane(after, at: to)
            if row > 0 {
                let above = before[row - 1].id
                XCTAssertEqual(now[above], was[above], "\(what): the row above where it was")
            }
            let below = before[(row + 1)...(row + 4)].map(\.id)
            if other == first - 1 {
                XCTAssertEqual(now["7/\(other)"], was["7/\(first)"], "\(what): its row where it was")
                for id in below { XCTAssertEqual(now[id], was[id], "\(what): \(id)") }
            } else {
                XCTAssertEqual(after.firstIndex { $0.id == "7/\(other)" }, 14, "\(what): gone down")
                for id in below {
                    XCTAssertEqual(now[id], was[id].map { $0 - Self.row }, "\(what): \(id)")
                }
            }
        }
    }

    /// Newer mail joining the first row he can see, on a page put on above,
    /// takes it up the list to that mail, out of sight. That is not a row
    /// taken out: as before (list-8), the next row he can see stays where
    /// it was, and the row above comes down into the place. The grouping
    /// switch merging the first row he can see into the row above's
    /// conversation holds the next one the same way, the merged row in the
    /// first one's place.
    func testNewerMailOrTheGroupingSwitchTakingTheFirstRowInSightLeaveTheNextWhereItWas() throws {
        let before = grouped(twenty)
        let from = 310.0
        let was = onPane(before, at: from)
        let newer = [letter(230, thread: "n230"), letter(229, thread: "t196"),
                     letter(228, thread: "n228")]
        let after = grouped(newer + twenty)
        XCTAssertEqual(after[1].messages.map(\.id), ["7/229", "7/196"], "gone up with its new letter")
        let to = try offset(after: place(in: before, at: from), in: after, from: from)
        let now = onPane(after, at: to)
        for id in inView(before, at: from).dropFirst() { XCTAssertEqual(now[id], was[id], id) }
        XCTAssertEqual(now["7/197"], was["7/196"], "the row above in its place")

        let letters = twenty.map { $0.id == "7/196" ? letter(196, thread: "t197") : $0 }
        let split = MessageThread.rows(for: letters, grouped: false)
        let merged = grouped(letters)
        XCTAssertEqual(merged[3].messages.map(\.id), ["7/197", "7/196"])
        let switched = try offset(after: place(in: split, at: from), in: merged, from: from)
        let wasSplit = onPane(split, at: from)
        let nowMerged = onPane(merged, at: switched)
        XCTAssertEqual(nowMerged["7/195"], wasSplit["7/195"])
        XCTAssertEqual(nowMerged["7/197"], wasSplit["7/196"], "the merged row in its place")
    }

    /// A search's Cancel, the first row he could see deleted while the
    /// results showed, and the newest page fetched afresh without it, newer
    /// mail on top (`refetched`): the rows below closed up into its place,
    /// the row above where it was.
    func testACancelAndAFreshPageAfterTheFirstRowInSightWent() throws {
        let rows = grouped(twenty)
        let from = 214.0
        let without = grouped(twenty.filter { $0.id != "7/197" })

        var places = ListPlaces()
        _ = places.resultsShown(overFolder: true, here: place(in: rows, at: from))
        guard case .back(let folder) = places.searchEnded(showingResults: true) else {
            return XCTFail("no place kept")
        }
        XCTAssertEqual(try offset(after: folder, in: without, from: 0), from)

        guard case .back(let here) = places.refetched(here: place(in: rows, at: from)) else {
            return XCTFail("no place kept")
        }
        let fresh = grouped([letter(230, thread: "n230")] + twenty.filter { $0.id != "7/197" })
        let fetched = try offset(after: here, in: fresh, from: from)
        XCTAssertEqual(fetched, from + Self.row)
        let before = onPane(rows, at: from)
        XCTAssertEqual(onPane(fresh, at: fetched)["7/198"], before["7/198"])
        XCTAssertEqual(onPane(fresh, at: fetched)["7/196"], before["7/197"])
    }

    /// The newest page fetched afresh ending at the row just above the first
    /// he could see: that row is held (`closingUp`), and the list goes to
    /// the end of the page, its last row just above the toolbar, rather
    /// than to the top (`refetched`).
    func testAFreshPageEndingAtTheRowAboveGoesToItsEnd() throws {
        let rows = grouped(twenty)
        let here = place(in: rows, at: 214)
        XCTAssertEqual(here.seen.first?.id, "7/197")
        XCTAssertEqual(here.above?.id, "7/198")
        let fresh = grouped((201...218).reversed().map { letter($0, thread: "n\($0)") }
                            + twenty.prefix(3))
        XCTAssertEqual(fresh.last?.id, "7/198")
        var places = ListPlaces()
        guard case .back(let kept) = places.refetched(here: here) else { return XCTFail("no place kept") }
        let to = try offset(after: kept, in: fresh, from: 214)
        XCTAssertEqual(to, Self.band + Double(fresh.count) * Self.row + Self.barBottom - Self.height,
                       "the end of the page")
        XCTAssertEqual(onPane(fresh, at: to)["7/198"], Self.height - Self.barBottom - Self.row)
    }

    /// The list's first row taken out, no row on screen above it, and on
    /// the same fresh page newer mail has joined the next row he could see
    /// and taken it up the list: that row is passed over, as one newer mail
    /// has joined is (`stands`), and the one after it goes where the first
    /// was.
    func testTheListsFirstRowGoneAndTheNextJoinedByNewerMailHoldsTheOneAfter() throws {
        let rows = grouped(twenty)
        let from = 20.0
        let here = place(in: rows, at: from)
        XCTAssertEqual(here.seen.prefix(3).map(\.id), ["7/200", "7/199", "7/198"])
        XCTAssertNil(here.above)
        let fresh = grouped([letter(230, thread: "n230"), letter(229, thread: "t199")]
                            + twenty.filter { $0.id != "7/200" })
        XCTAssertEqual(fresh[1].messages.map(\.id), ["7/229", "7/199"], "gone up with its new letter")
        let to = try offset(after: here, in: fresh, from: from)
        XCTAssertEqual(onPane(fresh, at: to)["7/198"], onPane(rows, at: from)["7/200"])
    }

    // MARK: - A row put back (B-093)

    /// The controller's redraw for a letter the pane changed
    /// (`regroup(for:)`): the table at `offset` in `rows`, the rows now
    /// `next`, no search, no tick and no finger on the list. Where `taken`
    /// sends the list, at the offset that puts it there as `scroll(to:in:)`
    /// does, or the top as `scrollToTop` sets it, and `taken` told where it
    /// was left.
    private func redraw(_ change: ListChange, _ taken: inout TakenRows, in rows: [MessageThread],
                        at offset: Double, to next: [MessageThread]) throws -> Double {
        let here = place(in: rows, at: offset)
        let to: Double
        switch taken.move(for: change, here: here,
                          atItsTop: ListPlaces.isAtTop(offset: offset, topInset: Self.barTop)) {
        case .putBack(let before) where before.landing(in: next) != nil:
            to = try self.offset(after: before, in: next, from: offset)
        case .putBack, .stay:
            to = try self.offset(after: here, in: next, from: offset)
        case .top:
            to = -Self.barTop
        case let move:
            XCTFail("\(move)")
            to = offset
        }
        taken.drawn(change, from: here, to: place(in: next, at: to))
        return to
    }

    /// A row whose Delete or Move is refused (`PaneActions`, B-062, B-092),
    /// put back with the list as the tap left it: back where it stood, and
    /// every row with it, as before the tap. The first row he can see,
    /// whole or twenty points of it, and the list's first at its top: at
    /// the tap the rows below close up into its place, and put back it is
    /// where it was, the rows below it down a row. A row just above the
    /// list, which closed out of sight, back out of sight, nothing in view
    /// moving; one below the first he can see, back where it was. Put back
    /// by the rows he could see then, as it was, the first in sight went in
    /// above them, out of sight under the search field, and every row in
    /// view stayed a row up.
    func testARefusedRowPutBackGoesBackWhereItStood() throws {
        let rows = grouped(twenty)
        for (gone, from, tapped) in [("7/197", 214.0, 214.0), ("7/197", 290.0, 290.0),
                                     ("7/200", -74.0, -74.0), ("7/197", 310.0, 214.0),
                                     ("7/194", 310.0, 310.0)] {
            let what = "\(gone) at \(from)"
            let without = grouped(twenty.filter { $0.id != gone })
            var taken = TakenRows()
            let to = try redraw(.taken(gone), &taken, in: rows, at: from, to: without)
            XCTAssertEqual(to, tapped, what)
            let back = try redraw(.putBack(gone), &taken, in: without, at: to, to: rows)
            XCTAssertEqual(back, from, "\(what): every row where it was")
            XCTAssertEqual(taken.move(for: .putBack(gone), here: place(in: rows, at: back)), .stay,
                           "\(what): nothing kept once it is back")
        }
        XCTAssertEqual(place(in: rows, at: 214).seen.first?.id, "7/197")
        XCTAssertEqual(place(in: rows, at: 310).above?.id, "7/197")

        for (gone, from) in [("7/197", 214.0), ("7/200", -74.0)] {
            let without = grouped(twenty.filter { $0.id != gone })
            let old = try offset(after: place(in: without, at: from), in: rows, from: from)
            XCTAssertEqual(onPane(rows, at: old)[gone], 21, "\(gone): under the band")
            XCTAssertFalse(inView(rows, at: old).contains(gone), gone)
        }
    }

    /// A row put back by its Undo (B-157), under the new UID the move back
    /// gave it, in front of its old place (`ListLetters.restore`): back
    /// where it stood, as a refused row is, and every row with it. The
    /// first row of a list at its top, found on the test iPad, 2026-10-27:
    /// the place from before the take named it by its old id, which heads
    /// no row now, so the rows below were held as if it had gone, and it
    /// came back above the top of the pane, out of sight. The same for the
    /// first row in sight with a row above it, one out of sight above, and
    /// one below the first in sight.
    func testARowUndoneUnderANewIDGoesBackWhereItStood() throws {
        let rows = grouped(twenty)
        for (gone, from, tapped) in [("7/200", -74.0, -74.0), ("7/197", 214.0, 214.0),
                                     ("7/197", 310.0, 214.0), ("7/194", 310.0, 310.0)] {
            let what = "\(gone) at \(from)"
            let without = grouped(twenty.filter { $0.id != gone })
            let undone = grouped(twenty.map { $0.id == gone ? $0.renamed("7/301") : $0 })
            var taken = TakenRows()
            let to = try redraw(.taken(gone), &taken, in: rows, at: from, to: without)
            XCTAssertEqual(to, tapped, what)
            let back = try redraw(.restored(gone, as: "7/301"), &taken, in: without, at: to, to: undone)
            XCTAssertEqual(back, from, "\(what): every row where it was")
            XCTAssertEqual(onPane(undone, at: back)["7/301"], onPane(rows, at: from)[gone], what)
            XCTAssertEqual(taken.move(for: .restored(gone, as: "7/301"), here: place(in: undone, at: back)),
                           .stay, "\(what): nothing kept once it is back")
        }
        XCTAssertEqual(inView(grouped(twenty), at: -74).first, "7/200", "the list's first at its top")
    }

    /// The first two rows of a list at its top, out together, a drag and
    /// then the pane, or Edit mode, and both undone, in either order: each
    /// back where it stood under its new id, the list at its top, both in
    /// sight.
    func testTheFirstTwoRowsUndoneUnderNewIDsGoBackWhereTheyStood() throws {
        let new = ["7/200": "7/301", "7/199": "7/302"]
        func listed(out: Set<String>, back: Set<String>) -> [MessageThread] {
            grouped(twenty.compactMap { letter in
                if back.contains(letter.id) { return letter.renamed(new[letter.id]!) }
                return out.contains(letter.id) ? nil : letter
            })
        }
        for order in [["7/200", "7/199"], ["7/199", "7/200"]] {
            var taken = TakenRows()
            var at = try redraw(.taken("7/200"), &taken, in: listed(out: [], back: []), at: -74,
                                to: listed(out: ["7/200"], back: []))
            at = try redraw(.taken("7/199"), &taken, in: listed(out: ["7/200"], back: []), at: at,
                            to: listed(out: ["7/200", "7/199"], back: []))
            var back = Set<String>()
            for id in order {
                let out = Set(new.keys).subtracting(back)
                at = try redraw(.restored(id, as: new[id]!), &taken, in: listed(out: out, back: back),
                                at: at, to: listed(out: out.subtracting([id]), back: back.union([id])))
                back.insert(id)
            }
            XCTAssertEqual(at, -74, "\(order): at its top")
            XCTAssertEqual(Array(inView(listed(out: [], back: back), at: at).prefix(2)), ["7/301", "7/302"],
                           "\(order)")
        }
    }

    /// A row put back, by its Undo under its new id or refused under its
    /// own, into a list at its top that has changed since the take, where
    /// the watch's news goes on (`TakenRows.move(for:here:atItsTop:)`,
    /// B-157): the list stays at its top, and the row put back first is
    /// the first, in sight. Held where he was, the row he could see first
    /// kept its place and the row went in above it, above the top of the
    /// pane, out of sight, as the first row undone did on the test iPad,
    /// 2026-10-27. Two ways the list changes at its top: the iPad turned,
    /// the table 1080 tall and more rows in sight; and another row taken
    /// out further down, the list scrolled there and back, both undone.
    /// With a search, a tick or a finger on the list (`atItsTop` false),
    /// and scrolled down, where he is, as before; and only a row put back
    /// goes to the top.
    func testARowPutBackIntoAListAtItsTopThatHasChangedComesBackInSight() throws {
        let rows = grouped(twenty)
        let without = grouped(twenty.filter { $0.id != "7/200" })
        let undone = grouped(twenty.map { $0.id == "7/200" ? $0.renamed("7/301") : $0 })
        let top = -Self.barTop

        for (change, back, id) in [(ListChange.restored("7/200", as: "7/301"), undone, "7/301"),
                                    (.putBack("7/200"), rows, "7/200")] {
            let what = "\(change)"
            var taken = TakenRows()
            XCTAssertEqual(try redraw(.taken("7/200"), &taken, in: rows, at: top, to: without), top, what)
            let turned = place(in: without, at: top, height: 1080)
            XCTAssertGreaterThan(turned.seen.count, place(in: without, at: top).seen.count, what)
            XCTAssertEqual(taken.move(for: change, here: turned), .stay, "\(what): not as the take left it")
            let held = try offset(after: turned, in: back, from: top, height: 1080)
            XCTAssertFalse(inView(back, at: held, height: 1080).contains(id), "\(what): held, above the top")
            XCTAssertEqual(taken.move(for: change, here: turned, atItsTop: true), .top, what)
            XCTAssertEqual(inView(back, at: top, height: 1080).first, id, "\(what): at the top, first")
            XCTAssertEqual(taken.move(for: change, here: turned, atItsTop: false), .stay, what)
        }

        let both = grouped(twenty.filter { $0.id != "7/200" && $0.id != "7/190" })
        let one = grouped(twenty.filter { $0.id != "7/200" }
            .map { $0.id == "7/190" ? $0.renamed("7/302") : $0 })
        let all = grouped(twenty.map { ["7/200": "7/301", "7/190": "7/302"][$0.id].map($0.renamed) ?? $0 })
        var taken = TakenRows()
        XCTAssertEqual(try redraw(.taken("7/200"), &taken, in: rows, at: top, to: without), top)
        XCTAssertTrue(inView(without, at: 310).contains("7/190"))
        XCTAssertEqual(try redraw(.taken("7/190"), &taken, in: without, at: 310, to: both), 310)
        XCTAssertEqual(try redraw(.restored("7/190", as: "7/302"), &taken, in: both, at: top, to: one), top)
        let at = try redraw(.restored("7/200", as: "7/301"), &taken, in: one, at: top, to: all)
        XCTAssertEqual(at, top, "at its top")
        XCTAssertEqual(Array(inView(all, at: at).prefix(2)), ["7/301", "7/199"], "back first, in sight")

        let here = place(in: rows, at: top)
        XCTAssertEqual(TakenRows().move(for: .taken("7/200"), here: here, atItsTop: true), .stay)
        XCTAssertEqual(TakenRows().move(for: .marked, here: here, atItsTop: true), .stay)
        XCTAssertEqual(TakenRows().move(for: .putBack("7/200"), here: here, atItsTop: true), .top)
        XCTAssertEqual(TakenRows().move(for: .putBack("7/200"), here: place(in: rows, at: 310),
                                        atItsTop: false), .stay, "scrolled down: where he is")
    }

    /// Put back once the list has moved since the tap. Scrolled: the rows he
    /// can see then stay where they are, the row goes in above them out of
    /// sight, as any row put back does (`landing`), and the place from
    /// before the tap is dropped. A page of newer mail put on above
    /// meanwhile moves nothing he can see, and the row goes back where it
    /// was. One whose newer mail joins the first row in view moves that
    /// row: not as the tap left it.
    func testARowPutBackAfterTheListHasMovedHoldsTheRowsInViewThen() throws {
        let rows = grouped(twenty)
        let without = grouped(twenty.filter { $0.id != "7/197" })
        var taken = TakenRows()
        XCTAssertEqual(try redraw(.taken("7/197"), &taken, in: rows, at: 214, to: without), 214)
        let scrolled = 250.0
        let back = try redraw(.putBack("7/197"), &taken, in: without, at: scrolled, to: rows)
        let was = onPane(without, at: scrolled)
        for id in inView(without, at: scrolled) { XCTAssertEqual(onPane(rows, at: back)[id], was[id], id) }
        XCTAssertFalse(inView(rows, at: back).contains("7/197"))
        XCTAssertEqual(taken.move(for: .putBack("7/197"), here: place(in: rows, at: back)), .stay)

        taken = TakenRows()
        XCTAssertEqual(try redraw(.taken("7/197"), &taken, in: rows, at: 214, to: without), 214)
        let newer = (201...203).reversed().map { letter($0, thread: "n\($0)") }
        let paged = grouped(newer + twenty.filter { $0.id != "7/197" })
        let held = try offset(after: place(in: without, at: 214), in: paged, from: 214)
        XCTAssertEqual(held, 214 + 3 * Self.row)
        let all = grouped(newer + twenty)
        let again = try redraw(.putBack("7/197"), &taken, in: paged, at: held, to: all)
        XCTAssertEqual(again, held)
        let before = onPane(rows, at: 214)
        for id in inView(rows, at: 214) { XCTAssertEqual(onPane(all, at: again)[id], before[id], id) }

        taken = TakenRows()
        XCTAssertEqual(try redraw(.taken("7/197"), &taken, in: rows, at: 214, to: without), 214)
        let joined = grouped([letter(229, thread: "t196")] + twenty.filter { $0.id != "7/197" })
        let moved = try offset(after: place(in: without, at: 214), in: joined, from: 214)
        XCTAssertEqual(taken.move(for: .putBack("7/197"), here: place(in: joined, at: moved)), .stay)

        // Three rows out, scrolled, all put back: each by the rows in view
        // then, which stay where they are; the place from before the tap
        // is not taken up again by the second.
        let three: Set<String> = ["7/197", "7/196", "7/195"]
        func less(_ ids: Set<String>) -> [MessageThread] {
            grouped(twenty.filter { !ids.contains($0.id) })
        }
        taken = TakenRows()
        var gone = Set<String>()
        var at = 214.0
        for id in ["7/195", "7/196", "7/197"] {
            at = try redraw(.taken(id), &taken, in: less(gone), at: at, to: less(gone.union([id])))
            gone.insert(id)
        }
        XCTAssertEqual(gone, three)
        at = scrolled
        for id in ["7/195", "7/196", "7/197"] {
            let shown = inView(less(gone), at: at)
            let was = onPane(less(gone), at: at)
            at = try redraw(.putBack(id), &taken, in: less(gone), at: at,
                            to: less(gone.subtracting([id])))
            gone.remove(id)
            for row in shown { XCTAssertEqual(onPane(less(gone), at: at)[row], was[row], "\(id): \(row)") }
        }
    }

    /// Two rows out at once, the first he could see and then the one that
    /// closed up into its place, a Move from the pane while the Delete
    /// before it is still on its way: both refused, put back in either
    /// order, every row where it was before the first tap. Taken from the
    /// place before the second take alone, the first put back last went in
    /// above the second, out of sight.
    func testTwoRowsOutAtOncePutBackEitherWayGoBackWhereTheyStood() throws {
        func without(_ ids: Set<String>) -> [MessageThread] {
            grouped(twenty.filter { !ids.contains($0.id) })
        }
        for order in [["7/197", "7/196"], ["7/196", "7/197"]] {
            var taken = TakenRows()
            var at = try redraw(.taken("7/197"), &taken, in: without([]), at: 214, to: without(["7/197"]))
            XCTAssertEqual(inView(without(["7/197"]), at: at).first, "7/196", "closed up into its place")
            at = try redraw(.taken("7/196"), &taken, in: without(["7/197"]), at: at,
                            to: without(["7/197", "7/196"]))
            var gone: Set<String> = ["7/197", "7/196"]
            for id in order {
                at = try redraw(.putBack(id), &taken, in: without(gone), at: at,
                                to: without(gone.subtracting([id])))
                gone.remove(id)
            }
            XCTAssertEqual(at, 214, "\(order): every row where it was")
        }
    }

    /// Edit mode's Delete of three rows, the first he can see among them
    /// (`ListBatch`): taken out one after another at the tap, the oldest
    /// first, the rows below closing up into the first one's place. All
    /// three refused and put back one after another in the same order:
    /// every row where it was before the tap. The oldest taken and the other
    /// two refused: those two where they were, and the rows below closed up
    /// into the oldest one's place. Put back by the rows he could see, as
    /// they were, the first in sight and the next went in above them, out
    /// of sight.
    func testEditsRefusedRowsGoBackWhereTheyStood() throws {
        let from = 214.0
        let ticked = ["7/194", "7/196", "7/197"]
        func without(_ ids: Set<String>) -> [MessageThread] {
            grouped(twenty.filter { !ids.contains($0.id) })
        }
        let was = onPane(grouped(twenty), at: from)
        for refused in [ticked, Array(ticked.dropFirst())] {
            var taken = TakenRows()
            var at = from
            var gone = Set<String>()
            for id in ticked {
                at = try redraw(.taken(id), &taken, in: without(gone), at: at,
                                to: without(gone.union([id])))
                gone.insert(id)
            }
            XCTAssertEqual(at, from, "not scrolled")
            XCTAssertEqual(onPane(without(gone), at: at)["7/195"], was["7/197"], "closed up")
            for id in refused {
                at = try redraw(.putBack(id), &taken, in: without(gone), at: at,
                                to: without(gone.subtracting([id])))
                gone.remove(id)
            }
            let now = onPane(without(gone), at: at)
            XCTAssertEqual(at, from, "\(refused): not scrolled")
            for id in ["7/198", "7/197", "7/196", "7/195"] {
                XCTAssertEqual(now[id], was[id], "\(refused): \(id)")
            }
            if refused.count == 3 {
                XCTAssertEqual(now["7/194"], was["7/194"], "every row where it was")
            } else {
                XCTAssertNil(now["7/194"])
                XCTAssertEqual(now["7/193"], was["7/194"], "closed up into its place")
            }
        }

        var gone = Set(ticked)
        var at = from
        for id in ticked {
            at = try offset(after: place(in: without(gone), at: at), in: without(gone.subtracting([id])),
                            from: at)
            gone.remove(id)
        }
        XCTAssertFalse(inView(grouped(twenty), at: at).contains("7/197"))
        XCTAssertFalse(inView(grouped(twenty), at: at).contains("7/196"))
    }

    /// Drafts or the Outbox drawn again for the rows kept on the iPad
    /// (`ListPlaces.keptDrawn`): at the top, with no search, no tick and
    /// no finger on the list, to the top, where a draft's copy landed by
    /// Save Draft goes, and in sight; anywhere else where he is, the rows
    /// he can see held (B-093). Found on the test iPad, 2026-10-27 (B-165):
    /// drawn where he was at the top, the first row he could see stayed in
    /// its place and the copy went above the top of the pane, out of sight.
    /// And read from the source: `keptChanged` and `listOutbox` take the
    /// move before anything is put on the list and regroup by it.
    func testRowsKeptDrawnAtTheTopStayAtTheTopAndAnywhereElseWhereHeIs() throws {
        XCTAssertEqual(ListPlaces.keptDrawn(atTop: true, searching: false, ticked: false, touching: false),
                       .top)
        for (searching, ticked, touching) in [(true, false, false), (false, true, false),
                                              (false, false, true)] {
            XCTAssertEqual(ListPlaces.keptDrawn(atTop: true, searching: searching, ticked: ticked,
                                                touching: touching), .stay)
        }
        XCTAssertEqual(ListPlaces.keptDrawn(atTop: false, searching: false, ticked: false, touching: false),
                       .stay)

        let rows = grouped(twenty)
        let landed = grouped([letter(230, thread: "d230")] + twenty)
        let held = try offset(after: place(in: rows, at: -74), in: landed, from: -74)
        XCTAssertFalse(inView(landed, at: held).contains("7/230"), "held where he was: above the top")
        XCTAssertEqual(inView(landed, at: -74).first, "7/230", "at the top: first, in sight")
        let down = try offset(after: place(in: rows, at: 310), in: landed, from: 310)
        let was = onPane(rows, at: 310)
        for id in inView(rows, at: 310) { XCTAssertEqual(onPane(landed, at: down)[id], was[id], id) }

        let list = try source("UI/MessageListViewController.swift")
        let changed = flat(body(after: "@objc private func keptChanged(_ note: Notification)", in: list))
        let outbox = flat(body(after: "private func listOutbox()", in: list))
        for (name, code, first) in [("keptChanged", changed, "if let landing"),
                                    ("listOutbox", outbox, "_ = letters.fetchedAfresh([])")] {
            let move = try XCTUnwrap(code.range(of: "let move = keptMove"), name)
            let after = try XCTUnwrap(code.range(of: first), name)
            XCTAssertLessThan(move.lowerBound, after.lowerBound, "\(name): taken before")
            XCTAssertTrue(code.contains("regroup(to: move)"), name)
            XCTAssertFalse(code.contains("regroup()"), name)
        }
        XCTAssertTrue(flat(body(after: "private var keptMove: ListPlaces.Move", in: list)).contains(
            "let here = newsPlace return ListPlaces.keptDrawn(atTop: here.atTop, searching: here.searching, "
                + "ticked: here.ticked, touching: here.touching)"))
    }

    /// The list shows what it showed while the same rows are in sight, each
    /// where it was to half a point. The row out of sight above them and
    /// the rows selected do not count; a row more or less in sight does.
    func testTheListShowsTheSameByTheRowsInSightToHalfAPoint() {
        let rows = grouped(twenty)
        let here = place(in: rows, at: 214)
        XCTAssertEqual(here.seen.map(\.id), (191...197).reversed().map { "7/\($0)" })
        XCTAssertTrue(here.showsTheSame(as: place(in: rows, at: 214)))
        XCTAssertTrue(here.showsTheSame(as: place(in: rows, at: 214.4)))
        XCTAssertFalse(here.showsTheSame(as: place(in: rows, at: 214.5)))
        XCTAssertFalse(here.showsTheSame(as: place(in: rows, at: 310)))
        let seen = (3...9).map { (row: $0, offset: rowTop($0) - 214) }
        XCTAssertTrue(here.showsTheSame(as: ListPlace(rows: rows, visible: seen, selected: [4])),
                      "no row above, a row selected")
        XCTAssertFalse(here.showsTheSame(as: ListPlace(rows: rows, visible: Array(seen.dropLast()),
                                                       selected: [])))
        let other = grouped(twenty.filter { $0.id != "7/193" })
        XCTAssertFalse(here.showsTheSame(as: place(in: other, at: 214)), "another row in sight")
    }

    /// The list's letters say which row went or came back: a Delete from
    /// the pane takes its letter's row out, and refused puts it back, each
    /// by the letter (`PaneActions`); a Flag, a Flag put back and a folder
    /// it is filed in are marks.
    @MainActor
    func testTheLettersSayWhichRowWentOrCameBack() throws {
        let list = listed()
        var told: [ListChange] = []
        list.changed = { told.append($0) }
        let letter = try XCTUnwrap(list.letter("7/146"))
        let started = PaneActions.start(.delete, on: letter, inFolderWithRole: .inbox, list: list)
        XCTAssertEqual(told, [.taken("7/146")])
        XCTAssertNotNil(PaneActions.finish(started, failure: MailError.cannotConnect, requestSweep: {}))
        XCTAssertEqual(told, [.taken("7/146"), .putBack("7/146")])
        told = []
        list.setFlagged(true, on: letter)
        list.flagAnswered(letter, landed: false)
        list.addCountedFolder("Work", to: "7/146")
        XCTAssertEqual(told, [.marked, .marked, .marked])
    }

    /// A page of newer mail put on above, after a date jump, with a letter
    /// in the conversation of the row just above the list, under the band:
    /// that row goes up to the new page, out of sight, and the rows in view
    /// stay put. Held by the row under the status bar, they went up a row.
    func testAPageAboveTakingUpTheRowJustAboveTheListLeavesTheRowsInViewWhereTheyWere() throws {
        let before = grouped(twenty)
        let from = 310.0
        let seen = inView(before, at: from)
        let newer = [letter(230, thread: "n230"), letter(229, thread: "t197"),
                     letter(228, thread: "n228")]
        let after = grouped(newer + twenty)
        XCTAssertEqual(after[1].messages.map(\.id), ["7/229", "7/197"], "gone up with its new letter")
        let to = try offset(after: place(in: before, at: from), in: after, from: from)
        let was = onPane(before, at: from)
        for id in seen { XCTAssertEqual(onPane(after, at: to)[id], was[id], id) }

        let old = try offset(after: everyRow(in: before, at: from), in: after, from: from)
        for id in seen { XCTAssertEqual(onPane(after, at: old)[id], was[id].map { $0 - Self.row }, id) }
    }

    /// A Move from the pane that the server refused puts its row back where
    /// it stood, here just above the list, out of sight: the rows in view
    /// stay put. A Mark or a Flag, which changes no row, moves nothing.
    func testARowPutBackAboveTheListAndAMarkMoveNothingInView() throws {
        let taken = grouped(twenty.filter { $0.id != "7/197" })
        let from = 214.0
        XCTAssertEqual(inView(taken, at: from).first, "7/196")
        let back = grouped(twenty)
        let to = try offset(after: place(in: taken, at: from), in: back, from: from)
        XCTAssertEqual(to, from + Self.row)
        let was = onPane(taken, at: from)
        for id in inView(taken, at: from) { XCTAssertEqual(onPane(back, at: to)[id], was[id], id) }
        let old = try offset(after: everyRow(in: taken, at: from), in: back, from: from)
        XCTAssertEqual(onPane(back, at: old)["7/196"], was["7/196"].map { $0 + Self.row },
                       "held by the row under the bar, the rows in view went down a row")

        var marked = twenty
        marked[4] = MessageSummary(id: "7/196", mailboxID: "INBOX", sender: marked[4].sender,
                                   subject: marked[4].subject, preview: "", date: marked[4].date,
                                   isRead: false, isFlagged: true, threadID: "t196")
        let here = place(in: grouped(twenty), at: 310)
        let landing = try XCTUnwrap(here.landing(in: grouped(marked)))
        XCTAssertNil(ListPlace.contentOffset(rowTop: rowTop(landing.row), offset: landing.offset,
                                             range: -74...1_203, current: 310), "nothing moves")
    }

    /// A search's Cancel comes back by the rows he could see when it began:
    /// the row hidden under the band, deleted from the reading pane while
    /// the results showed, closes out of sight.
    func testASearchsCancelComesBackByTheRowsHeCouldSee() throws {
        var places = ListPlaces()
        let rows = grouped(twenty)
        let from = 310.0
        XCTAssertEqual(places.resultsShown(overFolder: true, here: place(in: rows, at: from)), .top)
        // Results at the top, scrolled down, then Cancel: the folder's rows
        // without the one he deleted, the table at the results' offset.
        guard case .back(let folder) = places.searchEnded(showingResults: true) else {
            return XCTFail("no place kept")
        }
        let now = grouped(twenty.filter { $0.id != "7/197" })
        let to = try offset(after: folder, in: now, from: 600)
        let was = onPane(rows, at: from)
        for id in inView(rows, at: from) { XCTAssertEqual(onPane(now, at: to)[id], was[id], id) }
    }

    /// The controller's half, read: its place is taken from the rows on
    /// screen by their tops and bottoms and what of the table is in sight,
    /// the same `sight` VoiceOver's rows go by, and nowhere else; and every
    /// move that keeps his place takes it there.
    func testTheListTakesItsPlaceByTheRowsInSight() throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertEqual(flat(body(after: "private func place() -> ListPlace", in: list)),
                       "{ let onScreen = (tableView.indexPathsForVisibleRows ?? []) "
                       + ".filter { $0.section == 0 && $0.row < rows.count } .sorted() "
                       + ".map { ip -> (row: Int, top: Double, bottom: Double) in "
                       + "let rect = tableView.rectForRow(at: ip) "
                       + "return (ip.row, Double(rect.minY), Double(rect.maxY)) } "
                       + "let selected = (tableView.indexPathsForSelectedRows ?? []).map(\\.row) "
                       + "return ListPlace(rows: threads, onScreen: onScreen, sight: tableView.sight, "
                       + "selected: selected) }")
        XCTAssertEqual(list.components(separatedBy: "ListPlace(rows:").count - 1, 1)
        XCTAssertEqual(lines(of: list, containing: "place()"),
                       ["let before = place()", "let here = place()",
                        "taken.drawn(change, from: here, to: place())",
                        "private func place() -> ListPlace {",
                        "regroup(to: keepingPlace ? places.refetched(here: place()) : places.replaced())",
                        "let here = place()", "let here = place()",
                        "let move = self.landed.move(forPageAboveFrom: self.place())",
                        "return places.resultsShown(overFolder: overFolder, here: overFolder ? place() : nil)"])
        // A row put back goes back by the place from before its take while
        // the list is as the take left it (`TakenRows`), told by the letters.
        XCTAssertTrue(flat(list).contains("letters.changed = { [weak self] change in "
                                          + "self?.regroup(for: change) self?.updateEmptyState() }"))
        XCTAssertEqual(flat(body(after: "private func regroup(for change: ListChange)", in: list)),
                       "{ let here = place() let news = newsPlace "
                       + "let atItsTop = ListPlaces.showsNews(atTop: news.atTop, searching: news.searching, "
                       + "ticked: news.ticked, touching: news.touching) "
                       + "regroup(to: taken.move(for: change, here: here, atItsTop: atItsTop)) "
                       + "tableView.layoutIfNeeded() taken.drawn(change, from: here, to: place()) }")
        XCTAssertTrue(flat(body(after: "private func regroup(highlighting", in: list)).contains(
            "case .putBack(let taken): if !scroll(to: taken, in: threads) { scroll(to: before, in: threads) }"))
        let sight = flat(body(after: "var sight: TableSight", in: try source("UI/VoiceOverPlace.swift")))
        XCTAssertEqual(sight, "{ TableSight(offset: contentOffset.y, height: bounds.height, "
                       + "barTop: adjustedContentInset.top, barBottom: adjustedContentInset.bottom, "
                       + "band: numberOfSections > 0 ? rectForHeader(inSection: 0).height : 0, "
                       + "content: contentSize.height) }")
    }

    // MARK: - Reading the source

    /// A file under `Sources/Blackmail`, its comment lines taken out.
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
    }

    /// The braces after the first `opener` in `code`, and everything in them.
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
        XCTFail("\(opener) never closes", file: file, line: line)
        return ""
    }

    /// The lines of `code` that contain `text`, trimmed.
    private func lines(of code: String, containing text: String) -> [String] {
        code.components(separatedBy: "\n")
            .filter { $0.contains(text) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Whitespace runs as one space.
    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).joined(separator: " ")
    }
}
