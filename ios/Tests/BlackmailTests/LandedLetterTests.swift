import XCTest
@testable import Blackmail

/// Go to Date landing on a letter that begins a conversation, with Organize
/// by Thread on (B-117), seen on the test iPad on 2026-10-23: 1 June 2012,
/// the day's first letter UID 762, its reply UID 773 on 5 June, the eleventh
/// newer letter. The window, 723 to 772, kept ten above the letter, so the
/// reply was not in it, and the letter was drawn in a row of its own at the
/// top. The page above, 773 to 822, asked for as the day landed (B-094),
/// came 0.12 s later; the reply joined the letter's row and took it up the
/// list, dated 5 June, out of sight, and the day's next letter, 763, came
/// down into the top place.
///
/// Now the window's FETCH brings the page above too (`PageWindow.jumpWindow`),
/// so the row that carries the letter is its conversation's from the first
/// frame, up the list, and the jump opens on the day's next row (B-118);
/// and while he has not moved the list, a page above holds the row opened
/// on where it is, by the letter heading it (`LandedLetter`,
/// `ListPlace.landing(in:holding:)`). A reply on such a page to a letter in
/// it takes it up the list, and the day's next row comes into its place, as
/// Mail's list shows the day (B-118). The arithmetic and the grouping are
/// the real ones; the controller's half is read from its source.
final class LandedLetterTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    // MARK: - The letters, as on the iPad

    /// UID 762 and its reply 773 one conversation, and 771 with 775, as on
    /// the test account; every other letter one of its own. One a day, near
    /// enough: the dates only have to fall in order.
    private func letter(_ uid: UInt32, in thread: String? = nil) -> MessageSummary {
        let threads: [UInt32: String] = [762: "H", 773: "H", 771: "P", 775: "P"]
        return MessageSummary(id: "7/\(uid)", mailboxID: "INBOX",
                              sender: "Harper Mock <harper.mock@example.com>",
                              subject: uid == 773 ? "Re: Watch and winter evening weather lunch"
                                : "Letter \(uid)",
                              preview: "",
                              date: Date(timeIntervalSince1970: 1_338_542_760 + (Double(uid) - 762) * 43_200),
                              isRead: true, isFlagged: false,
                              threadID: thread ?? threads[uid] ?? "T\(uid)")
    }

    /// The letters with these UIDs, newest first, as the list has them.
    private func letters(_ uids: ClosedRange<UInt32>) -> [MessageSummary] {
        uids.reversed().map { letter($0) }
    }

    private func grouped(_ letters: [MessageSummary], _ on: Bool = true) -> [MessageThread] {
        MessageThread.rows(for: letters, grouped: on)
    }

    private func row(holding id: String, in rows: [MessageThread]) -> Int? {
        rows.firstIndex { $0.messages.contains { $0.id == id } }
    }

    /// Where the list was as the jump landed: the row with `letter` the
    /// first he can see, 120 points down the pane, under the bars and the
    /// band, and five rows below it, a row apart; the row above it just
    /// out of sight under the band. With `under` rows he can see above the
    /// letter's, as VoiceOver's own scrolling can leave the list, the
    /// first of those 120 points down and the letter's row that many rows
    /// lower.
    private func landedPlace(on letter: String, in rows: [MessageThread],
                             under: Int = 0) throws -> ListPlace {
        let first = try XCTUnwrap(row(holding: letter, in: rows)) - under
        return ListPlace(rows: rows, visible: (0..<6).map { (first + $0, 120 + Double($0) * 96) },
                         above: first > 0 ? (first - 1, 24) : nil, selected: [])
    }

    /// The row `offset` points down the pane, the list put where `landing`
    /// says, its rows a row apart, 96 points, as `landedPlace` has them:
    /// what he sees there, whichever row the landing names.
    private func row(at offset: Double, by landing: (row: Int, offset: Double)) -> Int {
        landing.row + Int(((offset - landing.offset) / 96).rounded())
    }

    /// The size test's Inbox, by UID, 1 to 57,209.
    private let inbox: [UInt32] = Array(1...57_209)

    // MARK: - The first frame

    /// The window alone was 723 to 772, as on the iPad, its row for 762 a
    /// row of its own. The jump's window is that and the page above it,
    /// 723 to 822, in one: 762 is the 61st row from the top, and its row is
    /// its conversation's, headed by 773, dated 5 June, from the first frame,
    /// and the list opens on 763, the day's next letter (B-118). The page
    /// above coming after the window alone, the row held, 762's, goes up
    /// with its reply, and 763 comes into its place: the same row.
    func testTheJumpsWindowHasThePageAboveSoTheLettersRowIsItsConversationsFromTheStart() throws {
        let alone = PageWindow.window(around: 762, in: inbox, limit: 50)
        XCTAssertEqual(alone.uids.first, 772)
        XCTAssertEqual(alone.uids.last, 723)

        let jump = PageWindow.jumpWindow(around: 762, in: inbox, limit: 50)
        XCTAssertEqual(jump.uids, Array((723...822).reversed()))
        XCTAssertEqual(jump.uids[jump.anchorIndex], 762)
        XCTAssertEqual(jump.anchorIndex, 60)
        XCTAssertFalse(jump.reachedNewest)
        XCTAssertFalse(jump.reachedOldest)

        let before = grouped(alone.uids.map { letter($0) })
        let first = grouped(jump.uids.map { letter($0) })
        let was = try XCTUnwrap(row(holding: "7/762", in: before))
        XCTAssertEqual(before[was].messages.map(\.id), ["7/762"], "a row of its own, as it was drawn")
        let now = try XCTUnwrap(row(holding: "7/762", in: first))
        XCTAssertEqual(first[now].id, "7/773")
        XCTAssertEqual(first[now].messages.map(\.id), ["7/773", "7/762"])
        XCTAssertEqual(first[now].newest.subject, "Re: Watch and winter evening weather lunch")
        // The row a window holding the conversation whole opens on, and the
        // one the hold puts there when the page above comes after a window
        // without it: the same row, with the same rows below it.
        let window = MessageWindow(messages: jump.uids.map { letter($0) }, anchorIndex: jump.anchorIndex,
                                   reachedNewest: false, reachedOldest: false,
                                   landedOn: letter(762).date,
                                   dayStart: Date(timeIntervalSince1970: 1_338_508_800))
        let opens = try XCTUnwrap(ListOpening.dayRow(in: first, for: window)).row
        XCTAssertEqual(first[opens].id, "7/763")
        let held = try XCTUnwrap(try landedPlace(on: "7/762", in: before)
            .landing(in: first, holding: "7/762"))
        XCTAssertEqual(row(at: 120, by: held), opens)
        XCTAssertLessThan(now, opens, "the conversation up the list")
    }

    /// The page above follows on from the jump's window, and the page below
    /// it, with nothing left out and nothing twice; near the newest letter
    /// the page above is short and the window reaches it; with nothing newer
    /// than the window, it is the window alone.
    func testThePageAboveJoinsUpAndStopsAtTheNewest() {
        let jump = PageWindow.jumpWindow(around: 762, in: inbox, limit: 50)
        XCTAssertEqual(PageWindow.newer(than: jump.uids[0], in: inbox, limit: 50),
                       Array((823...872).reversed()))
        XCTAssertEqual(PageWindow.older(than: jump.uids.last, in: inbox, limit: 50).first, 722)

        let near = PageWindow.jumpWindow(around: 57_170, in: inbox, limit: 50)
        XCTAssertEqual(near.uids, Array((57_131...57_209).reversed()))
        XCTAssertEqual(near.uids[near.anchorIndex], 57_170)
        XCTAssertTrue(near.reachedNewest)

        let top = PageWindow.jumpWindow(around: 57_205, in: inbox, limit: 50)
        XCTAssertEqual(top, PageWindow.window(around: 57_205, in: inbox, limit: 50))
        XCTAssertTrue(top.reachedNewest)

        // With gaps where letters were expunged, and small.
        let gappy: [UInt32] = [3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36]
        let small = PageWindow.jumpWindow(around: 12, in: gappy, limit: 5)
        XCTAssertEqual(small.uids, [30, 27, 24, 21, 18, 15, 12, 9, 6, 3])
        XCTAssertEqual(small.uids[small.anchorIndex], 12)
        XCTAssertFalse(small.reachedNewest)
        XCTAssertTrue(small.reachedOldest)
        XCTAssertEqual(PageWindow.jumpWindow(around: 12, in: gappy, limit: 1).uids, [15, 12])
        XCTAssertEqual(PageWindow.jumpWindow(around: 13, in: gappy, limit: 5).uids, [])
    }

    /// The jump's FETCH answered without its anchor: it lands beside it, on
    /// the day, not at the top of the window, sixty letters newer, as it
    /// would have with the first row. The nearest row older than the
    /// anchor, 761, of 31 May, and from there `landing` moves up to the
    /// nearest dated on or after his day, 763. With the anchor there, its
    /// own row; with no row older, the last, the nearest newer.
    func testAnAnchorTheServerLeftOutLandsBesideItNotAtTheTopOfTheWindow() {
        let jump = PageWindow.jumpWindow(around: 762, in: inbox, limit: 50)
        XCTAssertEqual(PageWindow.anchorRow(762, fetched: jump.uids), jump.anchorIndex)

        let without = jump.uids.filter { $0 != 762 }
        let row = PageWindow.anchorRow(762, fetched: without)
        XCTAssertEqual(row.map { without[$0] }, 761)
        let dayStart = Date(timeIntervalSince1970: 1_338_508_800) // 1 June 2012, midnight UTC
        let landed = PageWindow.landing(dates: without.map { letter($0).date }, anchor: row ?? 0,
                                        dayStart: dayStart, searchedFrom: dayStart,
                                        notAfter: Date(timeIntervalSince1970: 1_791_028_800))
        XCTAssertEqual(without[landed], 763, "the day's next letter, not 822")

        let newer = jump.uids.filter { $0 > 762 }
        XCTAssertEqual(PageWindow.anchorRow(762, fetched: newer).map { newer[$0] }, 763)
        XCTAssertNil(PageWindow.anchorRow(762, fetched: []))
    }

    // MARK: - A page above, landing

    /// The case on the iPad, the page above coming after a window without it.
    /// The reply joins the letter's row and takes it up the list, dated 5
    /// June. By the rows he could see the row is passed over, and the row
    /// above it comes down into its place: 763 on top, over 761. Held, the
    /// same since B-118: the day's next letter in its place, where Mail's
    /// list shows the day. On B-117 the row held stayed on top, the
    /// conversation's, over the rows of 4 to 1 June.
    func testAReplyOnThePageAboveTakesTheHeldRowUpAndTheDaysNextLetterComesIntoItsPlace() throws {
        let before = grouped(letters(723...772))
        let place = try landedPlace(on: "7/762", in: before)
        let after = grouped(letters(773...822) + letters(723...772))

        let stayed = try XCTUnwrap(place.landing(in: after))
        XCTAssertEqual(after[stayed.row].id, "7/761", "761 held where it was")
        XCTAssertEqual(stayed.offset, 216)
        XCTAssertEqual(after[stayed.row - 1].id, "7/763", "and 763 come down onto the top place")

        let held = try XCTUnwrap(place.landing(in: after, holding: "7/762"))
        XCTAssertEqual(after[row(at: 120, by: held)].id, "7/763", "the day's next letter in its place")
        XCTAssertEqual(after[row(at: 216, by: held)].id, "7/761")
        let conversation = try XCTUnwrap(row(holding: "7/762", in: after))
        XCTAssertEqual(after[conversation].messages.map(\.id), ["7/773", "7/762"])
        XCTAssertLessThan(conversation, row(at: 120, by: held), "up the list")
    }

    /// A reply further up than the jump's window reaches, on the page above
    /// it asked for as the day lands, to the conversation of 762 and 773, up
    /// the list out of his sight: the row the jump opened on, 763, is not
    /// joined, and held, it stays where it is, 761 under it.
    func testAReplyOnTheNextPageUpToAConversationUpTheListLeavesTheRowHeldWhereItIs() throws {
        func withReply(_ uid: UInt32) -> MessageSummary { letter(uid, in: uid == 840 ? "H" : nil) }
        let window = (723...822).reversed().map(withReply)
        let before = grouped(window)
        let place = try landedPlace(on: "7/763", in: before)
        let after = grouped((823...872).reversed().map(withReply) + window)

        let held = try XCTUnwrap(place.landing(in: after, holding: "7/763"))
        XCTAssertEqual(after[held.row].id, "7/763")
        XCTAssertEqual(held.offset, 120)
        XCTAssertEqual(after[held.row + 1].id, "7/761")
        let conversation = try XCTUnwrap(row(holding: "7/762", in: after))
        XCTAssertEqual(after[conversation].messages.map(\.id), ["7/840", "7/773", "7/762"])
    }

    /// The letter's row held at its own place on the pane, not at the first
    /// row he can see: two rows in sight above it, as VoiceOver's own
    /// scrolling can leave the list, which is not a drag and does not let
    /// the letter go. A reply on the page above joins it and takes it up the
    /// list, and the day's next letter, 763, comes into its place, 312 points
    /// down, 761 under it, and the rows above down a row; by the rows he
    /// could see, 764 stays at the top and 761 comes up into the letter's
    /// place. And with the jump's window, the row it opens on, 763, two rows
    /// under the top: a reply on the page after it to 764, a row above it in
    /// sight, takes 764 up the list; held, 763 stays where it is, 312 points
    /// down, and 765 comes down into 764's place; by the rows he could see,
    /// 765 stays at the top and 763 goes up a row.
    func testTheLettersRowIsHeldWhereItIsNotWhereTheFirstRowInSightIs() throws {
        let before = grouped(letters(723...772))
        let place = try landedPlace(on: "7/762", in: before, under: 2)
        XCTAssertEqual(place.seen.prefix(3).map(\.id), ["7/764", "7/763", "7/762"])
        XCTAssertEqual(place.seen[2].offset, 312)
        let after = grouped(letters(773...822) + letters(723...772))

        let held = try XCTUnwrap(place.landing(in: after, holding: "7/762"))
        XCTAssertEqual(after[row(at: 312, by: held)].id, "7/763",
                       "the day's next letter in the letter's place, not the top row's")
        XCTAssertEqual(after[row(at: 408, by: held)].id, "7/761")
        XCTAssertEqual(after[row(at: 216, by: held)].id, "7/764", "the rows above down a row")
        let stayed = try XCTUnwrap(place.landing(in: after))
        XCTAssertEqual(after[stayed.row].id, "7/764", "by the rows, 764 held")
        XCTAssertEqual(stayed.offset, 120)
        XCTAssertEqual(after[row(at: 312, by: stayed)].id, "7/761", "and 761 come up into the letter's place")

        func withReply(_ uid: UInt32) -> MessageSummary { letter(uid, in: uid == 840 ? "T764" : nil) }
        let window = (723...822).reversed().map(withReply)
        let jumped = try landedPlace(on: "7/763", in: grouped(window), under: 2)
        XCTAssertEqual(jumped.seen.prefix(3).map(\.id), ["7/765", "7/764", "7/763"])
        let next = grouped((823...872).reversed().map(withReply) + window)
        let kept = try XCTUnwrap(jumped.landing(in: next, holding: "7/763"))
        XCTAssertEqual(next[row(at: 312, by: kept)].id, "7/763")
        XCTAssertEqual(next[row(at: 216, by: kept)].id, "7/765", "765 down into 764's place")
        let rows = try XCTUnwrap(jumped.landing(in: next))
        XCTAssertEqual(next[row(at: 120, by: rows)].id, "7/765")
        XCTAssertEqual(next[row(at: 216, by: rows)].id, "7/763", "763 up a row")
    }

    /// Organize by Thread off: a reply joins nothing, the letter keeps its
    /// own row, and held or not the rows he can see stay where they were.
    func testWithOrganizeByThreadOffNothingMovesEitherWay() throws {
        let before = grouped(letters(723...772), false)
        let place = try landedPlace(on: "7/762", in: before)
        let after = grouped(letters(773...822) + letters(723...772), false)
        let held = try XCTUnwrap(place.landing(in: after, holding: "7/762"))
        XCTAssertEqual(after[held.row].id, "7/762")
        XCTAssertEqual(held.offset, 120)
        let stayed = try XCTUnwrap(place.landing(in: after))
        XCTAssertEqual(stayed.row, held.row)
        XCTAssertEqual(stayed.offset, held.offset)
    }

    /// Letters taken out near the landing leave the rules as they were. The
    /// letter itself gone with its row, the rows below close up into its
    /// place (B-093), held or not: the row above stays where it was, under
    /// the band, and 761 comes up to the top. A row below it gone, the
    /// letter's row stays where it is. The letter out of his sight, the
    /// rows he can see are held (B-042).
    func testLettersTakenOutAndALetterOutOfSightGoByTheRowsHeCouldSee() throws {
        let alone = grouped(letters(723...772))
        let landedAlone = try landedPlace(on: "7/762", in: alone)
        let gone = grouped(letters(723...772).filter { $0.id != "7/762" })
        let closed = try XCTUnwrap(landedAlone.landing(in: gone, holding: "7/762"))
        let plain = try XCTUnwrap(landedAlone.landing(in: gone))
        XCTAssertEqual(closed.row, plain.row)
        XCTAssertEqual(closed.offset, plain.offset)
        XCTAssertEqual(gone[closed.row].id, "7/763")
        XCTAssertEqual(closed.offset, 24)
        XCTAssertEqual(gone[closed.row + 1].id, "7/761")

        let before = grouped(letters(723...822))
        let place = try landedPlace(on: "7/762", in: before)
        let below = grouped(letters(723...822).filter { $0.id != "7/760" })
        let kept = try XCTUnwrap(place.landing(in: below, holding: "7/762"))
        XCTAssertEqual(below[kept.row].id, "7/773")
        XCTAssertEqual(kept.offset, 120)

        XCTAssertTrue(place.heads("7/773"))
        XCTAssertFalse(place.heads("7/730"))
        let after = grouped(letters(823...872) + letters(723...822))
        let away = try XCTUnwrap(place.landing(in: after, holding: "7/730"))
        let rows = try XCTUnwrap(place.landing(in: after))
        XCTAssertEqual(away.row, rows.row)
        XCTAssertEqual(away.offset, rows.offset)
    }

    // MARK: - Held until he moves the list

    /// Landed, a page above holds the letter's row while he can see it
    /// headed by the letter; a page that comes with the letter out of his
    /// sight lets it go for good, and so does one that comes with it in a
    /// row he can see that newer mail has joined, answered on a page before;
    /// he lets it go by moving the list; a tap on the letter's own row keeps
    /// it, a tap on another lets it go; a jump that found no row holds none.
    func testTheLetterIsHeldUntilHeMovesTheListOrItGoesOutOfSight() throws {
        let rows = grouped(letters(723...822))
        let inSight = try landedPlace(on: "7/763", in: rows)
        let elsewhere = try landedPlace(on: "7/730", in: rows)

        var landed = LandedLetter()
        XCTAssertEqual(landed.move(forPageAboveFrom: inSight), .stay, "no jump, nothing held")

        landed.landed(on: "7/763")
        XCTAssertEqual(landed.move(forPageAboveFrom: inSight), .holding("7/763"))
        XCTAssertEqual(landed.move(forPageAboveFrom: inSight), .holding("7/763"), "page after page")

        landed.tapped(rows[try XCTUnwrap(row(holding: "7/763", in: rows))])
        XCTAssertEqual(landed.letter, "7/763", "a tap on its own row opens it where it is")
        landed.tapped(rows[try XCTUnwrap(row(holding: "7/761", in: rows))])
        XCTAssertNil(landed.letter, "a tap on another row is his")
        XCTAssertEqual(landed.move(forPageAboveFrom: inSight), .stay)

        landed.landed(on: "7/763")
        landed.letGo()
        XCTAssertEqual(landed.move(forPageAboveFrom: inSight), .stay, "moved by him")

        landed.landed(on: "7/763")
        XCTAssertEqual(landed.move(forPageAboveFrom: elsewhere), .stay, "out of his sight")
        XCTAssertEqual(landed.move(forPageAboveFrom: inSight), .stay, "and not taken up again")

        let joined = try landedPlace(on: "7/762", in: rows)
        XCTAssertEqual(joined.seen[0].letters, ["7/773", "7/762"])
        landed.landed(on: "7/762")
        XCTAssertEqual(landed.move(forPageAboveFrom: joined), .stay, "in sight, its row headed by its reply")
        XCTAssertNil(landed.letter)

        landed.landed(on: nil)
        XCTAssertEqual(landed.move(forPageAboveFrom: inSight), .stay)
    }

    // MARK: - The previews

    /// A jump's previews from the row it lands on down first, then the page
    /// above it, every row once; from the top, or past the end, as before.
    func testAJumpsPreviewsBeginAtTheRowItLandsOn() {
        let rows = letters(723...822)
        let start = 49 // 773, the first letter of the row landed on.
        let groups = PreviewPass.groups(for: rows, from: start)
        XCTAssertEqual(groups.map(\.mailboxID), ["INBOX", "INBOX"])
        guard groups.count == 2 else { return }
        XCTAssertEqual(groups[0].ids.first, "7/773")
        XCTAssertEqual(groups[0].ids.count, 51)
        XCTAssertEqual(groups[1].ids.first, "7/822")
        XCTAssertEqual(groups.flatMap(\.ids).sorted(), rows.map(\.id).sorted())
        XCTAssertEqual(PreviewPass.groups(for: rows, from: 0), PreviewPass.groups(for: rows))
        XCTAssertEqual(PreviewPass.groups(for: rows, from: 100), PreviewPass.groups(for: rows))
        XCTAssertEqual(PreviewPass.groups(for: [], from: 3), [])
    }

    // MARK: - Over the wire

    /// The shipping repository against the scripted server, the iPad's case
    /// made small: 130 letters, one every twelve hours from 2 May 2012; 1
    /// June's first, the 61st, at 9.26 am, begins a conversation whose
    /// reply, the 72nd, is the eleventh newer letter. The jump lands on the
    /// 61st, with one window FETCH, the 22nd to the 121st, the page above
    /// in it, and nothing fetched after it; the row that carries the 61st
    /// is the conversation's, headed by the reply. The next page up begins
    /// at the 122nd.
    func testAJumpFetchesThePageAboveInTheWindowsOneFetch() async throws {
        let server = ScriptedIMAPServer(inboxCount: 0)
        defer { XCTAssertEqual(server.violations, []) }
        let suite = "LandedLetterTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_335_950_760) // 2 May 2012, 9.26 am UTC
        var first: Server.Letter?
        for k in 0..<130 {
            let date = start.addingTimeInterval(Double(k) * 43_200)
            var letter = Server.Letter(from: Server.carlo, to: [Server.owner],
                                       subject: k == 60 ? "Watch and winter evening weather lunch"
                                         : k == 71 ? "Re: Watch and winter evening weather lunch"
                                         : "Letter \(k)",
                                       date: date, text: "A few words.\r\n",
                                       messageID: "<letter-\(k)@example.org>")
            if k == 71, let first {
                letter.inReplyTo = first.messageID
                letter.joins = first.messageID
            }
            if k == 60 { first = letter }
            server.deliver(letter, to: [Server.inbox, Server.allMail])
        }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_791_028_800) // 3 October 2026, noon UTC
        let repository = IMAPMailRepository(account: server.account, password: server.password,
                                            transport: server.transportFactory,
                                            recipients: RecipientBook(defaults: defaults),
                                            now: { now }, calendar: utc)
        let picked = utc.date(from: DateComponents(year: 2012, month: 6, day: 1, hour: 12))!
        server.clearLog()

        let jumped = try await repository.messages(around: picked, in: "inbox", limit: 50)
        let window = try XCTUnwrap(jumped)
        // The k-th letter delivered, by its UID and its id.
        let uids = server.uids(in: Server.inbox)
        XCTAssertEqual(uids.count, 130)
        let validity = server.uidValidity(of: Server.inbox)
        func id(_ k: Int) -> String { "\(validity)/\(uids[k])" }
        XCTAssertEqual(window.messages[window.anchorIndex].id, id(60))
        XCTAssertEqual(window.messages[window.anchorIndex].subject, "Watch and winter evening weather lunch")
        XCTAssertEqual(window.messages.map(\.id), (21...120).reversed().map(id))
        XCTAssertFalse(window.reachedNewest)

        // His day's letters' dates, the folder's letters' arrivals for the
        // list's order (B-178), and the window.
        let fetches = server.log.filter { $0.verb == "UID FETCH" }.map(\.command)
        XCTAssertEqual(fetches.count, 3, "\(fetches)")
        XCTAssertEqual(fetches.first, "UID FETCH \(uids[60]):\(uids[61]) (UID INTERNALDATE ENVELOPE)")
        XCTAssertEqual(fetches[1].hasSuffix(" (UID INTERNALDATE)"), true, fetches[1])
        XCTAssertTrue(fetches.last?.hasPrefix("UID FETCH \(uids[21]):\(uids[120]) (") == true,
                      "\(fetches)")
        XCTAssertEqual(server.log.last?.verb, "UID FETCH", "nothing after the window's")

        let rows = grouped(window.messages)
        let landed = try XCTUnwrap(row(holding: id(60), in: rows))
        XCTAssertEqual(rows[landed].messages.map(\.id), [id(71), id(60)])
        XCTAssertEqual(rows[landed].newest.subject, "Re: Watch and winter evening weather lunch")

        let above = try await repository.listMessages(in: "inbox", afterUID: window.messages[0].id,
                                                      limit: 50)
        XCTAssertEqual(above.map(\.id), (121...129).reversed().map(id))
    }

    // MARK: - The controller, read

    /// The jump's window is the one the repository fetches and the one it
    /// works the landing out on; the Mock's has the page above too.
    func testTheRepositoryAsksForTheJumpsWindow() throws {
        let repository = try source("Mail/IMAPMailRepository.swift")
        XCTAssertEqual(lines(of: repository, containing: "PageWindow.jumpWindow(").count, 2)
        XCTAssertFalse(repository.contains("PageWindow.window(around:"))
        // Cut from the list's order, by when the letters arrived (B-178).
        XCTAssertTrue(flat(repository).contains(
            "var window = PageWindow.jumpWindow(around: anchor, in: order.ascending, limit: limit)"))
        XCTAssertTrue(flat(repository).contains(
            "let window = PageWindow.jumpWindow(around: anchor, in: order.ascending, limit: limit) "
                + "return (Jumped(order: order, anchor: anchor), window.uids)"))
        // An anchor left out of the FETCH: beside it, not the first row.
        XCTAssertTrue(flat(repository).contains(
            "let anchorRow = min(PageWindow.anchorRow(fetched: opened.summaries.compactMap(\\.uid), "
                + "in: window) ?? 0, rows.count - 1)"))
        XCTAssertTrue(flat(repository).contains(
            "let landedIndex = PageWindow.landing( dates: rows.map(\\.date), anchor: anchorRow,"))
    }

    /// `show` lands on the row it opens on, the oldest dated on or after the
    /// day since B-118, and holds the letter heading it, after the scroll;
    /// its previews begin at that row. The page
    /// above is drawn by the hold's move, which a regroup puts into effect
    /// by the letter; and nothing else draws by it: a letter taken out or
    /// put back, the grouping switch, the watch's letters, a page below and
    /// a fresh list each draw as they did.
    func testTheListHoldsTheLetterOnlyForThePagesAbove() throws {
        let list = try source("UI/MessageListViewController.swift")
        let show = flat(body(after: "private func show(_ window: MessageWindow)", in: list))
        inOrder(["let landedRow = day?.row",
                 "if let row = landedRow { tableView.scrollToRow(at: IndexPath(row: row, section: 0), "
                    + "at: .top, animated: false) }",
                 "landed.landed(on: landedRow.map { threads[$0].id })",
                 "let seenFrom = landedRow.flatMap { row in "
                    + "window.messages.firstIndex { $0.id == threads[row].id } } ?? anchorIndex",
                 "loadPreviews(for: window.messages, from: seenFrom) }"], in: show)
        XCTAssertEqual(lines(of: list, containing: "landed.landed(").count, 1)

        let previous = flat(body(after: "private func loadPreviousPage()", in: list))
        inOrder(["let fresh = self.letters.prependPage(newer)",
                 "let move = self.landed.move(forPageAboveFrom: self.place())",
                 "UIView.performWithoutAnimation { self.regroup(to: move) }"], in: previous)
        XCTAssertEqual(lines(of: list, containing: "landed.move(").count, 1)
        XCTAssertEqual(lines(of: list, containing: ".holding("), ["case .holding(let letter):"],
                       "only the hold makes that move")

        let regroup = flat(body(after: "private func regroup(highlighting", in: list))
        XCTAssertTrue(regroup.contains("case .holding(let letter): "
                                       + "scroll(to: before, in: threads, holding: letter) "
                                       + "case .stay: scroll(to: before, in: threads) }"), regroup)
        XCTAssertTrue(regroup.hasPrefix("{ let before = held ?? place() let voiceOverOn = voiceOverHeld() "
                                        + "defer { keepVoiceOver(voiceOverOn) }"), regroup)
        XCTAssertTrue(flat(body(after: "private func scroll(to place: ListPlace", in: list)).hasPrefix(
            "{ guard let landing = place.landing(in: threads, holding: letter) else { return false }"))
        XCTAssertEqual(lines(of: list, containing: "holding: letter").count, 2)
        // Organize by Thread, the watch, a fresh list, an edit: as before.
        XCTAssertTrue(flat(list).contains(
            "settings.onOrganizeByThreadChanged = { [weak self] in self?.regroup() }"))
        XCTAssertTrue(flat(body(after: "private func regroup(for change: ListChange)", in: list))
            .contains("regroup(to: taken.move(for: change, here: here, atItsTop: atItsTop))"))
    }

    /// He moves the list, and the letter is let go: a drag, the status bar,
    /// a tap on another row, Edit, a search typed or run, the list fetched
    /// afresh (Refresh, a folder opened, after an edit, the watch's fetch),
    /// another day, the panes moving, and the list laid out at another size.
    func testEveryWayHeMovesTheListLetsTheLetterGo() throws {
        let list = try source("UI/MessageListViewController.swift")
        func starts(_ opener: String, with first: String, line: UInt = #line) {
            XCTAssertTrue(flat(body(after: opener, in: list)).hasPrefix("{ " + first),
                          opener, line: line)
        }
        starts("override func scrollViewWillBeginDragging(_ scrollView: UIScrollView)",
               with: "landed.letGo()")
        starts("override func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool",
               with: "landed.letGo() return true }")
        starts("@objc private func editTapped()", with: "landed.letGo()")
        starts("private func queryChanged(_ text: String)", with: "landed.letGo()")
        starts("private func startReplacingList() -> Int",
               with: "listGeneration += 1 landed.letGo()")
        XCTAssertTrue(flat(body(after: "private func runSearch(_ text: String) async", in: list))
            .hasPrefix("{ listGeneration += 1 let generation = listGeneration "
                       + "let scope = searchScope landed.letGo()"))
        let reload = flat(body(after: "func reload(keepingPlace: Bool = false", in: list))
        XCTAssertTrue(reload.contains("listGeneration += 1 let generation = listGeneration "
                                      + "landed.letGo() stopSearching()"), reload)
        let tap = flat(body(after: "override func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath)",
                            in: list))
        XCTAssertTrue(tap.hasPrefix("{ letGoOfVoiceOver() guard !inEditMode else "
                                    + "{ updateSelectAllTitle(); paneFollowsTicks(); return } "
                                    + "if letters.isSearching { keepSearch(searchShown) } "
                                    + "landed.tapped(threads[ip.row]) switch rows[ip.row]"), tap)
        XCTAssertTrue(flat(list).contains("guard panesMoving != oldValue else { return } "
                                          + "if panesMoving { landed.letGo() } placePull()"))
        XCTAssertEqual(flat(body(after: "override func viewDidLayoutSubviews()", in: list)),
                       "{ super.viewDidLayoutSubviews() guard view.bounds.size != laidOutSize "
                       + "else { return } laidOutSize = view.bounds.size landed.letGo() }")
        XCTAssertEqual(lines(of: list, containing: "landed.letGo()").count, 9)
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

    /// Each of `steps` in `code`, in that order.
    private func inOrder(_ steps: [String], in code: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        var from = code.startIndex
        for step in steps {
            guard let found = code.range(of: step, range: from..<code.endIndex) else {
                XCTFail("not in order: \(step)\n\(code)", file: file, line: line)
                return
            }
            from = found.upperBound
        }
    }
}
