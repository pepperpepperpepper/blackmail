import XCTest
@testable import Blackmail

/// The list in date order, as Mail's (B-178): the newest first by when the
/// server took each letter, its INTERNALDATE, and by UID where two came in
/// the same second, not by the folder's UIDs, the order the letters were
/// put in it.
///
/// Found in the comparison with Mail of 2026-10-27 (C-02c): a letter of 14
/// June 2025 put in the test account's Notes last was the 37th row of
/// Mail's list, among Notes' letters of that time, and at the top of
/// Blackmail's, above the letters of October 2026.
///
/// First the order alone (`ArrivalOrder`), over a folder of the size of his
/// Inbox answered from memory, which says how much it asks; then the
/// repository over `ScriptedIMAPServer`: the list, every page to the end,
/// Go to Date, Undo's put-back, the copy kept on the iPad across a launch,
/// and the watch's news.
final class ListInDateOrderTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "ListInDateOrderTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer(inboxCount: 40)
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        server = nil
        book = nil
        super.tearDown()
    }

    private static let day: TimeInterval = 86_400

    // MARK: - A folder answered from memory

    /// A folder held in memory, answering the order's two questions as
    /// Gmail does: the dates of the UIDs it holds, and a SEARCH by SINCE and
    /// BEFORE, days counted from midnight UTC. It counts what it is asked.
    private final class Folder: @unchecked Sendable {
        let arrivals: [UInt32: Date]
        private let lock = NSLock()
        private var _dated = 0
        private var _searches: [String] = []
        /// Letters left out of the first answer that asks for their dates,
        /// as a FETCH answered in part leaves them out, and given after.
        private var withheld: Set<UInt32>

        init(_ arrivals: [UInt32: Date], withholdingOnce withheld: Set<UInt32> = []) {
            self.arrivals = arrivals
            self.withheld = withheld
        }

        var listing: [UInt32] { arrivals.keys.sorted() }
        var dated: Int { lock.lock(); defer { lock.unlock() }; return _dated }
        var searches: [String] { lock.lock(); defer { lock.unlock() }; return _searches }

        /// Every UID, the newest first by arrival, the UID breaking a tie.
        var listOrder: [UInt32] {
            arrivals.sorted { a, b in
                a.value != b.value ? a.value > b.value : a.key > b.key
            }.map(\.key)
        }

        var asking: ArrivalOrder.Asking {
            ArrivalOrder.Asking(
                arrivals: { [self] uids in
                    lock.lock()
                    _dated += uids.count
                    let wanted = Set(uids).subtracting(withheld)
                    withheld.subtract(uids)
                    lock.unlock()
                    return arrivals.filter { wanted.contains($0.key) }
                },
                matching: { [self] criteria in
                    lock.lock()
                    _searches.append(criteria)
                    lock.unlock()
                    return Self.match(criteria, in: arrivals)
                })
        }

        private static let formatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "dd-MMM-yyyy"
            return f
        }()

        static func match(_ criteria: String, in arrivals: [UInt32: Date]) -> [UInt32] {
            var since: Date?
            var before: Date?
            let words = criteria.split(separator: " ").map(String.init)
            var i = 0
            while i < words.count {
                let word = words[i]
                if word == "SINCE" || word == "BEFORE", i + 1 < words.count {
                    let value = formatter.date(from: words[i + 1].replacingOccurrences(of: "\"", with: ""))
                    if word == "SINCE" { since = value } else { before = value }
                    i += 2
                } else {
                    i += 1
                }
            }
            return arrivals.filter { _, date in
                (since.map { date >= $0 } ?? true) && (before.map { date < $0 } ?? true)
            }.keys.sorted()
        }
    }

    private static let start = Date(timeIntervalSince1970: 1_600_000_000)

    /// A folder of `count` letters a few hours apart, the oldest the lowest
    /// UID, as mail that came as it was sent is, with `outOfTurn` put in
    /// after them, each the next UID up, arrived when it says.
    private func folder(_ count: Int, every hours: Double = 5,
                        outOfTurn: [Date] = []) -> Folder {
        var arrivals: [UInt32: Date] = [:]
        for i in 0..<count {
            arrivals[UInt32(1_000 + i * 3)] = Self.start.addingTimeInterval(Double(i) * hours * 3_600)
        }
        for (j, date) in outOfTurn.enumerated() {
            arrivals[UInt32(1_000 + count * 3 + j)] = date
        }
        return Folder(arrivals)
    }

    /// Every page of the order from the top, `limit` at a time, as the list
    /// walks them.
    private func walk(_ folder: Folder, limit: Int) async throws -> [UInt32] {
        var order = ArrivalOrder(validity: 1, listing: folder.listing)
        try await order.reachDown(below: nil, count: limit, asking: folder.asking)
        var rows = order.older(than: nil, limit: limit)
        while let last = rows.last {
            try await order.reachDown(below: last, count: limit, asking: folder.asking)
            let page = order.older(than: last, limit: limit)
            if page.isEmpty { break }
            rows += page
        }
        return rows
    }

    /// A folder of his Inbox's size, 60,000 letters, with three put in it
    /// last though they came long before, one that came seven hours ago
    /// put in after them, and one a moment ago: the first page is the
    /// fifty letters that came last, the one of seven hours ago fourth, the
    /// three in their places far below, and it asks the dates of a few
    /// hundred letters, not of 60,000.
    func testTheFirstPageOfALargeFolderIsTheLettersThatCameLast() async throws {
        let count = 60_000
        let newest = Self.start.addingTimeInterval(Double(count - 1) * 5 * 3_600)
        let folder = folder(count, outOfTurn: [
            Self.start.addingTimeInterval(400 * Self.day),
            Self.start.addingTimeInterval(9_000 * Self.day),
            Self.start.addingTimeInterval(12_000 * Self.day),
            newest.addingTimeInterval(60),
            newest.addingTimeInterval(-7 * 3_600),
        ])
        var order = ArrivalOrder(validity: 1, listing: folder.listing)
        try await order.reachDown(below: nil, count: 50, asking: folder.asking)
        let page = order.older(than: nil, limit: 50)

        XCTAssertEqual(page, Array(folder.listOrder.prefix(50)))
        XCTAssertEqual(page.first, 1_000 + UInt32(count * 3) + 3, "the one that came a moment ago")
        XCTAssertEqual(page.firstIndex(of: 1_000 + UInt32(count * 3) + 4), 3, "seven hours ago")
        for put in [UInt32(count * 3 + 1_000), UInt32(count * 3 + 1_001), UInt32(count * 3 + 1_002)] {
            XCTAssertFalse(page.contains(put), "\(put) is far below")
        }
        XCTAssertLessThan(folder.dated, 500, "the dates of a few hundred letters")
        XCTAssertFalse(order.completeBelow)
        XCTAssertTrue(order.completeAbove)
    }

    /// Scrolled to the end, fifty at a time, the whole folder comes in date
    /// order, each letter once, the letters put in out of turn among those
    /// of their own time, though the order widens a span at a time.
    func testEveryPageToTheEndIsInDateOrder() async throws {
        let folder = folder(5_000, every: 7, outOfTurn: [
            Self.start.addingTimeInterval(30 * Self.day),
            Self.start.addingTimeInterval(800 * Self.day),
            Self.start.addingTimeInterval(-90 * Self.day),
        ])
        let rows = try await walk(folder, limit: 50)
        XCTAssertEqual(rows, folder.listOrder)
        XCTAssertEqual(rows.last, 1_000 + 5_000 * 3 + 2, "the one that came before them all")
    }

    /// A folder of `wholeFolderAtMost` letters or fewer has every date asked
    /// for at once, in one FETCH, with no SEARCH, and is known whole.
    func testASmallFolderIsDatedInOneGo() async throws {
        let folder = folder(300, outOfTurn: [Self.start.addingTimeInterval(3 * Self.day)])
        var order = ArrivalOrder(validity: 1, listing: folder.listing)
        try await order.reachDown(below: nil, count: 50, asking: folder.asking)
        XCTAssertEqual(folder.dated, 301)
        XCTAssertEqual(folder.searches, [])
        XCTAssertTrue(order.completeBelow && order.completeAbove)
        XCTAssertEqual(order.older(than: nil, limit: 400), folder.listOrder)
    }

    /// In the same second the higher UID is the newer; a letter the server
    /// gives no date for has gone, and is not listed.
    func testTheSameSecondAndALetterGone() async throws {
        let same = Self.start.addingTimeInterval(Self.day)
        let folder = Folder([10: same, 11: Self.start, 12: same, 13: Self.start.addingTimeInterval(9)])
        var order = ArrivalOrder(validity: 1, listing: [10, 11, 12, 13, 14])
        try await order.reachDown(below: nil, count: 50, asking: folder.asking)
        XCTAssertEqual(order.older(than: nil, limit: 50), [12, 10, 13, 11])
        XCTAssertEqual(order.older(than: 10, limit: 50), [13, 11])
        XCTAssertEqual(order.newer(than: 13, limit: 50), [12, 10])
    }

    /// A Refresh carries the order on: only the letters new to the folder
    /// since have their dates asked for, and none when there are none.
    func testARefreshAsksOnlyTheNewLettersDates() async throws {
        var arrivals = folder(5_000).arrivals
        let first = Folder(arrivals)
        var order = ArrivalOrder(validity: 1, listing: first.listing)
        try await order.reachDown(below: nil, count: 50, asking: first.asking)

        let again = Folder(arrivals)
        var same = ArrivalOrder(validity: 1, listing: again.listing, carrying: order)
        same.fromTheTop()
        try await same.reachDown(below: nil, count: 50, asking: again.asking)
        XCTAssertEqual(again.dated, 0)
        XCTAssertEqual(again.searches, [])
        XCTAssertEqual(same.older(than: nil, limit: 50), order.older(than: nil, limit: 50))

        arrivals[90_000] = Self.start.addingTimeInterval(2 * Self.day)
        arrivals[90_001] = Self.start.addingTimeInterval(5_000 * 5 * 3_600)
        let later = Folder(arrivals)
        var refreshed = ArrivalOrder(validity: 1, listing: later.listing, carrying: order)
        refreshed.fromTheTop()
        try await refreshed.reachDown(below: nil, count: 50, asking: later.asking)
        XCTAssertEqual(later.dated, 2)
        XCTAssertEqual(later.searches, [])
        XCTAssertEqual(refreshed.older(than: nil, limit: 50), Array(later.listOrder.prefix(50)))
        XCTAssertEqual(refreshed.older(than: nil, limit: 1), [90_001])

        var renumbered = ArrivalOrder(validity: 2, listing: later.listing, carrying: order)
        XCTAssertNil(renumbered.known, "another numbering carries nothing")
        try await renumbered.reachDown(below: nil, count: 50, asking: later.asking)
        XCTAssertEqual(renumbered.older(than: nil, limit: 50), Array(later.listOrder.prefix(50)))
    }

    /// A date jump: the span around the letter it lands on, widened down
    /// and up, is the folder's order there, and paging from it either way
    /// goes on in date order to both ends.
    func testAJumpsWindowAndThePagesEitherSideAreInDateOrder() async throws {
        let folder = folder(6_000, every: 6, outOfTurn: [
            Self.start.addingTimeInterval(700 * Self.day + 3_600),
            Self.start.addingTimeInterval(701 * Self.day),
        ])
        let everything = folder.listOrder
        let anchor: UInt32 = 1_000 + 2_800 * 3
        var order = ArrivalOrder(validity: 1, listing: folder.listing)
        let now = Self.start.addingTimeInterval(1_600 * Self.day)
        let reached = try await order.reach(anchor, asking: folder.asking)
        XCTAssertTrue(reached)
        try await order.reachDown(below: anchor, count: 50, asking: folder.asking)
        try await order.reachUp(above: anchor, count: 60, now: now, asking: folder.asking)
        let window = PageWindow.jumpWindow(around: anchor, in: order.ascending, limit: 50)
        let at = try XCTUnwrap(everything.firstIndex(of: anchor))
        let start = at - window.anchorIndex
        XCTAssertTrue(start >= 0 && start + window.uids.count <= everything.count)
        if start >= 0, start + window.uids.count <= everything.count {
            XCTAssertEqual(window.uids, Array(everything[start..<(start + window.uids.count)]))
        }
        XCTAssertEqual(window.uids.count, 100, "39 below it, ten and a page of fifty above")
        XCTAssertEqual(window.uids.firstIndex(of: anchor), window.anchorIndex)
        XCTAssertFalse(window.reachedNewest && order.completeAbove)
        XCTAssertLessThan(folder.dated, 1_000)

        var up = window.uids
        while let top = up.first {
            try await order.reachUp(above: top, count: 50, now: now, asking: folder.asking)
            let page = order.newer(than: top, limit: 50)
            if page.isEmpty { break }
            up = page + up
        }
        var all = up
        while let last = all.last {
            try await order.reachDown(below: last, count: 50, asking: folder.asking)
            let page = order.older(than: last, limit: 50)
            if page.isEmpty { break }
            all += page
        }
        XCTAssertEqual(all, everything)
    }

    /// A listing from the top after a date jump in a folder too large to
    /// date whole: the jump's span, whose top is a fixed date, is let go
    /// (`fromTheTop`), and the first page is the letters that came last,
    /// not the jumped-to day's.
    func testAListingFromTheTopAfterAJumpBeginsWithTheNewest() async throws {
        let folder = folder(6_000, every: 6, outOfTurn: [Self.start.addingTimeInterval(50 * Self.day)])
        let anchor: UInt32 = 1_000 + 2_800 * 3
        var jumped = ArrivalOrder(validity: 1, listing: folder.listing)
        let now = Self.start.addingTimeInterval(1_600 * Self.day)
        let reached = try await jumped.reach(anchor, asking: folder.asking)
        XCTAssertTrue(reached)
        try await jumped.reachDown(below: anchor, count: 50, asking: folder.asking)
        try await jumped.reachUp(above: anchor, count: 60, now: now, asking: folder.asking)
        XCTAssertFalse(jumped.completeAbove, "the jump's span ends at a fixed date")
        XCTAssertGreaterThanOrEqual(jumped.rows(below: nil), 50)

        var top = ArrivalOrder(validity: 1, listing: folder.listing, carrying: jumped)
        top.fromTheTop()
        try await top.reachDown(below: nil, count: 50, asking: folder.asking)
        XCTAssertEqual(top.older(than: nil, limit: 50), Array(folder.listOrder.prefix(50)))
        XCTAssertTrue(top.completeAbove)
    }

    /// A letter the dates FETCH left out, answered in part, is off that
    /// listing's list. The next listing that still finds it in the folder
    /// owes its date again and lists it in its place, whether its row comes
    /// with the page's FETCH (`foldedPage`) or its date is asked for alone;
    /// one gone from the folder since is not owed.
    func testALetterTheDatesLeftOutIsListedAtTheNextListing() async throws {
        let dates = folder(300).arrivals
        let left: UInt32 = 1_000 + 290 * 3
        let folder = Folder(dates, withholdingOnce: [left])
        var order = ArrivalOrder(validity: 1, listing: folder.listing)
        try await order.reachDown(below: nil, count: 50, asking: folder.asking)
        XCTAssertTrue(order.completeBelow && order.completeAbove)
        XCTAssertFalse(order.older(than: nil, limit: 400).contains(left), "off this listing's list")
        XCTAssertEqual(folder.dated, 300)

        var refreshed = ArrivalOrder(validity: 1, listing: folder.listing, carrying: order)
        refreshed.fromTheTop()
        try await refreshed.reachDown(below: nil, count: 50, asking: folder.asking)
        XCTAssertEqual(folder.dated, 301, "its date asked for alone")
        XCTAssertEqual(refreshed.older(than: nil, limit: 400), folder.listOrder)
        XCTAssertEqual(refreshed.older(than: nil, limit: 50).firstIndex(of: left), 9, "the tenth newest")

        var folded = ArrivalOrder(validity: 1, listing: folder.listing, carrying: order)
        folded.fromTheTop()
        let fetched = try XCTUnwrap(folded.foldedPage(limit: 50))
        XCTAssertEqual(fetched.first, left)
        folded.settleOwed(from: [left: try XCTUnwrap(dates[left])])
        XCTAssertEqual(folded.older(than: nil, limit: 400), folder.listOrder)

        let gone = Folder(dates.filter { $0.key != left })
        let without = ArrivalOrder(validity: 1, listing: gone.listing, carrying: order)
        XCTAssertEqual(without.owed, [])
        XCTAssertNil(without.foldedPage(limit: 50))
    }

    // MARK: - The repository

    private func makeRepository(shelf: MailShelf? = nil, now: Date? = nil) -> IMAPMailRepository {
        let clock = now ?? Server.newestDate.addingTimeInterval(Self.day)
        return IMAPMailRepository(account: server.account, password: server.password,
                                  transport: server.transportFactory, recipients: book,
                                  now: { clock }, shelf: shelf ?? keptShelf(for: server.account))
    }

    private func uid(_ id: String) -> UInt32 { UInt32(id.split(separator: "/")[1])! }

    /// The fixture of the comparison: a letter of last year put in the
    /// folder last, the highest UID, its INTERNALDATE and its Date both a
    /// year back, as the round's letters were made.
    private func lastYear(_ subject: String = "R6 B-119 date lastyear rm",
                          arrived: Date? = nil, dated: Date? = nil) -> Server.Letter {
        let when = Server.newestDate.addingTimeInterval(-(20.4 * Self.day))
        return Server.Letter(from: Server.sam, to: [Server.owner], subject: subject,
                             date: dated ?? when, text: "From last year.\r\n", flags: ["\\Seen"],
                             messageID: "<\(subject.split(separator: " ").joined())@example.com>",
                             arrived: arrived ?? when)
    }

    /// The letter put in last sits among the letters of its own time, by
    /// date, as in Mail, not at the top: the 22nd row, under the letters of
    /// the twenty days after it, with the dates of the rows above it all
    /// after its own and those below before.
    func testALetterPutInLastSitsByItsDateNotAtTheTop() async throws {
        let put = try XCTUnwrap(server.deliver(lastYear(), to: [Server.inbox, Server.allMail])[Server.inbox])
        XCTAssertEqual(server.uids(in: Server.inbox).max(), put, "the highest UID in the Inbox")
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let at = try XCTUnwrap(rows.firstIndex { uid($0.id) == put })
        XCTAssertEqual(at, 21)
        XCTAssertTrue(rows[..<at].allSatisfy { $0.date > rows[at].date })
        XCTAssertTrue(rows[(at + 1)...].allSatisfy { $0.date < rows[at].date })
        XCTAssertEqual(rows.map(\.arrived), rows.map(\.arrived).sorted { $0! > $1! })
        XCTAssertNotEqual(rows.first.map { uid($0.id) }, put)
    }

    /// A letter whose two dates differ: arrived among the letters of its
    /// own time, but its Date saying today. It sits where it arrived, as
    /// Mail's list goes by when a letter arrived, and its row shows when it
    /// arrived, as Mail's does (seen 2026-10-28); the letter keeps its Date,
    /// and the reading pane's header (B-178, the second round), Print, a
    /// reply's "On ... wrote:" and Forward (the third) go by when it
    /// arrived (`Message.headerDate`), its Date only where that is not
    /// known.
    func testALetterWhoseTwoDatesDifferSitsWhereItArrived() async throws {
        let arrived = Server.newestDate.addingTimeInterval(-(10.4 * Self.day))
        let letter = lastYear("Dated today, came ten days ago", arrived: arrived,
                              dated: Server.newestDate.addingTimeInterval(3_600))
        let put = try XCTUnwrap(server.deliver(letter, to: [Server.inbox])[Server.inbox])
        let rows = try await makeRepository().listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let at = try XCTUnwrap(rows.firstIndex { uid($0.id) == put })
        XCTAssertEqual(at, 11)
        XCTAssertEqual(rows[at].date, letter.date)
        XCTAssertEqual(rows[at].arrived, arrived)
        let drawn = MessageThread.rows(for: rows, grouped: true).map { $0.displayRow() }
        let row = try XCTUnwrap(drawn.first { uid($0.id) == put })
        XCTAssertEqual(row.listDate, arrived)
    }

    /// Scrolled to the end a page of seven at a time, every letter once,
    /// in date order, the one put in last among them.
    func testScrolledToTheEndEveryLetterOnceInDateOrder() async throws {
        let put = try XCTUnwrap(server.deliver(lastYear(), to: [Server.inbox])[Server.inbox])
        let repository = makeRepository()
        var rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 7)
        while let last = rows.last {
            let page = try await repository.listMessages(in: "inbox", beforeUID: last.id, limit: 7)
            if page.isEmpty { break }
            rows += page
        }
        XCTAssertEqual(rows.count, server.uids(in: Server.inbox).count)
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
        XCTAssertEqual(rows.map(\.arrived), rows.map(\.arrived).sorted { $0! > $1! })
        XCTAssertTrue(rows.contains { uid($0.id) == put })
    }

    /// Go to Date with the letter put in last: the day of it lands on it,
    /// among its own time's letters, the rows above it newer and those
    /// below older; and a day of the folder's own letters still lands on
    /// that day's letter.
    func testGoToDateLandsOnTheRightDay() async throws {
        let letter = lastYear()
        let put = try XCTUnwrap(server.deliver(letter, to: [Server.inbox])[Server.inbox])
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)

        let window = try await XCTUnwrapAsync(await repository.messages(around: letter.date,
                                                                        in: "inbox", limit: 10))
        XCTAssertEqual(uid(window.messages[window.anchorIndex].id), put)
        let dates = window.messages.compactMap(\.arrived)
        XCTAssertEqual(dates, dates.sorted(by: >))

        let tenDaysBack = Server.newestDate.addingTimeInterval(-(10 * Self.day))
        let other = try await XCTUnwrapAsync(await repository.messages(around: tenDaysBack,
                                                                       in: "inbox", limit: 10))
        let landed = other.messages[other.anchorIndex]
        XCTAssertEqual(Calendar.current.startOfDay(for: landed.date),
                       Calendar.current.startOfDay(for: tenDaysBack))
        let below = try await repository.listMessages(in: "inbox",
                                                      beforeUID: other.messages.last!.id, limit: 50)
        let above = try await repository.listMessages(in: "inbox",
                                                      afterUID: other.messages.first!.id, limit: 50)
        let all = above + other.messages + below
        XCTAssertEqual(all.map(\.arrived), all.map(\.arrived).sorted { $0! > $1! })
        XCTAssertTrue(all.contains { uid($0.id) == put })
    }

    /// Trashed and brought back by its Undo, a letter is in the Inbox under
    /// a new UID, the highest; listed again, it is where it stood, by when
    /// it arrived, which Gmail keeps through the moves, not at the top.
    func testUndoneALetterIsListedWhereItStoodNotAtTheTop() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let letter = rows[4]
        let landed = try await repository.deleteLanding(
            letter.id, gmailMessageID: letter.gmailMessageID, from: letter.mailboxID)
        let landing = try XCTUnwrap(landed)
        let moved = try await repository.moveBack(landing, to: "inbox")
        let back = try XCTUnwrap(moved)
        XCTAssertEqual(server.uids(in: Server.inbox).max(), uid(back))

        let again = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(again[4].id, back)
        XCTAssertEqual(again[4].gmailMessageID, letter.gmailMessageID)
        XCTAssertEqual(again.map(\.subject), rows.map(\.subject))
    }

    /// The copy kept on the iPad after a relaunch: the folder's rows in the
    /// order they were listed, the letter put in last among them, and the
    /// pages scrolled kept below the first in that order, the third asked
    /// for from the letter put in last, the last row of the second, whose
    /// UID is above every other's.
    func testARelaunchKeepsTheOrder() async throws {
        let put = try XCTUnwrap(server.deliver(lastYear(), to: [Server.inbox])[Server.inbox])
        let shelf = keptShelf(for: server.account)
        let repository = makeRepository(shelf: shelf)
        var rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 11)
        rows += try await repository.listMessages(in: "inbox", beforeUID: rows.last!.id, limit: 11)
        XCTAssertEqual(rows.last.map { uid($0.id) }, put)
        rows += try await repository.listMessages(in: "inbox", beforeUID: rows.last!.id, limit: 11)
        shelf.flush()

        let kept = try XCTUnwrap(keptShelf(for: server.account).page(of: Server.inbox)).rows
        XCTAssertEqual(kept.map(\.id), rows.map(\.id))
        XCTAssertTrue(kept.contains { uid($0.id) == put })

        let later = keptShelf(for: server.account)
        let relisted = try await makeRepository(shelf: later).listMessages(in: "inbox", beforeUID: nil,
                                                                           limit: 11)
        later.flush()
        XCTAssertEqual(relisted.map(\.id), Array(rows.prefix(11)).map(\.id))
        let keptAgain = try XCTUnwrap(keptShelf(for: server.account).page(of: Server.inbox)).rows
        XCTAssertEqual(keptAgain.map(\.id), rows.map(\.id), "the pages below kept, in their order")
    }

    /// A date jump whose window the list never shows, a search typed or
    /// cancelled before it landed (`listGeneration`), leaves its order as
    /// the folder's snapshot all the same, its span around the day jumped
    /// to. The page below the list's own from the top is the next fifty by
    /// arrival, not the jumped-to day's newest: the cursor's date lies above
    /// the jump's span, and the span is found again from it
    /// (`ArrivalOrder.reaches(below:count:)`, `reach`).
    func testAPageBelowTheTopAfterAJumpNotShownGoesOnFromTheTop() async throws {
        server = ScriptedIMAPServer(inboxCount: 2_500)
        let repository = makeRepository()
        let top = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let old = Server.newestDate.addingTimeInterval(-2_200 * Self.day)
        let jumped = try await repository.messages(around: old, in: "inbox", limit: 50)
        XCTAssertNotNil(jumped, "the jump lands, and is not shown")

        let next = try await repository.listMessages(in: "inbox", beforeUID: top.last!.id, limit: 50)
        let all = server.uids(in: Server.inbox).sorted(by: >)
        XCTAssertEqual(top.map { uid($0.id) }, Array(all[0..<50]))
        XCTAssertEqual(next.map { uid($0.id) }, Array(all[50..<100]), "the next fifty by arrival")

        let above = try await repository.listMessages(in: "inbox", afterUID: next.first!.id, limit: 50)
        XCTAssertEqual(above.map { uid($0.id) }, Array(all[0..<50]), "and up from it, the top page")
    }

    // MARK: - The watch's news

    /// A letter that came after the list was fetched from the top and
    /// before a date jump the list never showed is news at the next check:
    /// the jump's listing holds it, and dated it after every row the list
    /// holds, so it is not one put in out of turn before the listing.
    func testALetterThatCameBeforeAJumpNotShownIsNews() async throws {
        server = ScriptedIMAPServer(inboxCount: 2_500)
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let come = Server.Letter(from: Server.sam, to: [Server.owner], subject: "Just come",
                                 date: Server.newestDate.addingTimeInterval(1_200),
                                 text: "Hello.\r\n", messageID: "<just@example.com>")
        let new = try XCTUnwrap(server.arrive(come, in: [Server.inbox, Server.allMail])[Server.inbox])
        let old = Server.newestDate.addingTimeInterval(-2_200 * Self.day)
        let jumped = try await repository.messages(around: old, in: "inbox", limit: 50)
        XCTAssertNotNil(jumped)

        let news = try await repository.news(in: "inbox", known: rows.map(\.id), searchingAnyway: true)
        XCTAssertEqual(news.arrived.map { uid($0.id) }, [new])
        XCTAssertFalse(news.refetch)
    }

    /// A letter put in the folder out of turn before the list was fetched,
    /// the highest UID there but arrived below the rows the list holds, is
    /// not news at the next check: only the letter that has come since is,
    /// and the list is not fetched afresh (`newsOnce`). Taken for news, it
    /// would have the list fetched afresh at every check that found a
    /// change, the list never holding a row as old.
    func testALetterPutInOutOfTurnBeforeTheListingIsNotNews() async throws {
        let put = try XCTUnwrap(server.deliver(lastYear(), to: [Server.inbox, Server.allMail])[Server.inbox])
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        XCTAssertFalse(rows.contains { uid($0.id) == put }, "below the rows listed")
        XCTAssertLessThan(rows.map { uid($0.id) }.max() ?? .max, put)

        let come = Server.Letter(from: Server.sam, to: [Server.owner], subject: "Just come",
                                 date: Server.newestDate.addingTimeInterval(1_200),
                                 text: "Hello.\r\n", messageID: "<just@example.com>")
        let new = try XCTUnwrap(server.arrive(come, in: [Server.inbox, Server.allMail])[Server.inbox])
        let news = try await repository.news(in: "inbox", known: rows.map(\.id), searchingAnyway: true)
        XCTAssertEqual(news.arrived.map { uid($0.id) }, [new])
        XCTAssertFalse(news.refetch)
    }

    private func row(_ uid: Int, arrived hours: Double) -> MessageSummary {
        let when = Server.newestDate.addingTimeInterval(hours * 3_600)
        var row = MessageSummary(id: "7/\(uid)", mailboxID: "inbox", sender: "Sam",
                                 subject: "letter \(uid)", preview: "", date: when,
                                 isRead: true, isFlagged: false)
        row.arrived = when
        return row
    }

    /// A letter the watch brings goes where its arrival puts it: at the top
    /// for one that has just come, among the rows of its own time for one
    /// put in the folder out of turn; one that came before every row the
    /// list holds has the list fetched afresh, which places it.
    @MainActor
    func testTheWatchesNewsGoesWhereItsDatePutsIt() {
        let list = ListLetters()
        _ = list.fetchedAfresh([row(10, arrived: 0), row(9, arrived: -2), row(8, arrived: -4)])
        list.hold(FolderNews(arrived: [row(12, arrived: 1), row(11, arrived: -3)]))
        XCTAssertEqual(list.putNewsOn(atTop: true, searching: false, ticked: false, touching: false),
                       .shown([row(12, arrived: 1), row(11, arrived: -3)]))
        XCTAssertEqual(list.folder.map(\.id), ["7/12", "7/10", "7/9", "7/11", "7/8"])

        list.hold(FolderNews(arrived: [row(13, arrived: -9)]))
        XCTAssertEqual(list.putNewsOn(atTop: true, searching: false, ticked: false, touching: false),
                       .refetch)
        XCTAssertEqual(list.folder.map(\.id), ["7/12", "7/10", "7/9", "7/11", "7/8"])
    }
}

/// `XCTUnwrap` of an async expression's value.
private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath,
                               line: UInt = #line) async throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}
