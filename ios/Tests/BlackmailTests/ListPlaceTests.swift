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

    /// A row taken off by a Delete, the top one: the next keeps its place.
    func testARowTakenOffLeavesTheNextWhereItWas() throws {
        let before = grouped(folder)
        let place = ListPlace(rows: before, visible: onScreen(from: 3, count: 5, offset: 10),
                              selected: [])
        let after = grouped(folder.filter { $0.id != "7/146" })
        let landing = try XCTUnwrap(place.landing(in: after))
        XCTAssertEqual(after[landing.row].id, "7/145")
        XCTAssertEqual(landing.offset, 10 + Self.row)
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
        // while the search showed.
        let move = places.searchEnded(showingResults: true)
        guard case .back(let place) = move else { return XCTFail("\(move)") }
        let now = grouped(folder.filter { $0.id != "7/143" })
        let landing = try XCTUnwrap(place.landing(in: now))
        XCTAssertEqual(now[landing.row].id, "7/142", "H, where it was")
        XCTAssertEqual(landing.offset, -12 + Self.row)
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
        list.apply(previews: ["7/148": "Fetched for the hit under the Inbox's id"])
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
                                            recipients: RecipientBook(defaults: defaults))
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
                              apply: { list.apply(previews: $0) })
        XCTAssertTrue(list.folder.allSatisfy { $0.preview.isEmpty })
        list.showResults(try await repository.search(in: "inbox", query: "garden",
                                                     scope: .currentMailbox, beforeUID: nil,
                                                     limit: 50))

        let asked = list.endSearch()
        XCTAssertEqual(asked.count, 20)
        await PreviewPass.run(PreviewPass.groups(for: asked),
                              fetch: { try await repository.previews(for: $0, in: $1) },
                              isCurrent: { true },
                              apply: { list.apply(previews: $0) })
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
}
