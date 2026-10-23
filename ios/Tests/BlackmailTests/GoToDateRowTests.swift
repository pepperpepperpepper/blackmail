import XCTest
@testable import Blackmail

/// Go to Date opens where Mail's list shows the day (B-118), asked for by
/// the owner on 2026-10-23: "Copy how Apple Mail works in terms of the
/// date." With Organize by Thread on, Mail dates a conversation's row by its
/// newest letter and orders the rows by that date, so the list's place for a
/// day is where its rows are dated that day: the rows dated after it above,
/// the rows dated before it below, and a conversation that began on the day
/// but was answered later up where its newest letter puts it. The jump opens
/// on the oldest row dated on or after the day (`ListOpening.dayRow`); with
/// every letter of the day answered later, on the oldest dated after it, and
/// "Showing" names that row's day, as for a day with no mail of its own.
///
/// It used to open on the row that carried the day's first letter, and with
/// that letter answered, the row was its conversation's, up the list: on
/// the test iPad 1 June 2012 opened on "Re: Watch and winter evening weather
/// lunch", dated 5 June, the rows of 4 to 1 June under it, and the day's next
/// letter the eleventh row (B-117).
///
/// The shapes are the size test's, from its plan, as the iPad saw them: each
/// folder's letters in the order written, by their UIDs there; the account's
/// own at the foot of the Inbox, dated 2026; the letters of the days below
/// with their dates in New York, as the iPad shows them, and which of them
/// are one conversation, as Gmail's X-GM-THRID has them on the test account.
/// Every other letter of a window is one of its own, dated between its
/// neighbours. The window and the landing are the real ones
/// (`PageWindow.jumpWindow`, `PageWindow.landing`), and so is the grouping.
final class GoToDateRowTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    // MARK: - The size test's letters

    /// A letter of the size test's plan, by its UID in its folder: when it
    /// was written, in New York; who it is from, or in Sent Mail to; its
    /// subject; and, for a letter in a conversation, the UID of the one the
    /// conversation began with in that folder.
    private typealias Planned = (uid: UInt32, at: String, who: String, subject: String, began: UInt32?)

    /// A folder of the size test, as a jump sees it.
    private struct Folder {
        let mailboxID: String
        /// Every UID in it, lowest first, as `UID SEARCH ALL` gives them.
        let listing: [UInt32]
        /// The account's own letters, at the foot, dated 2026.
        let own: Set<UInt32>
        /// The letters of the plan around the days below.
        let known: [UInt32: Planned]
    }

    /// The Inbox: the account's own 66 letters at the foot, UIDs 1 to 394,
    /// then the 57,143 copied in, 578 to 57,720, in the order written.
    private static let inbox: Folder = {
        let own: [UInt32] = [1, 2, 3, 4, 5, 7, 8, 10, 12, 13, 14, 15, 20, 21, 23, 51, 100, 101,
                             103, 110, 112, 116, 118, 121, 137, 139, 141, 142, 143, 144, 145,
                             146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 158, 160,
                             161, 162, 163, 164, 165, 166, 167, 170, 171, 172, 173, 175, 246,
                             326, 370, 371, 372, 373, 374, 392, 393, 394]
        let known: [Planned] = [
            (578, "2012-01-04T04:08", "Garden Club News", "News for the garden", nil),
            (579, "2012-01-07T05:34", "Jordan Doe", "Walk spring to", 579),
            (580, "2012-01-07T13:36", "Sam Ipsum", "Never a large perhaps walk", nil),
            (581, "2012-01-09T18:46", "Jordan Doe", "Re: Walk spring to", 579),
        ] + firstOfJune + [
            (2947, "2014-01-11T16:18", "Library Events", "Coming up the garden", nil),
            (2948, "2014-01-12T02:50", "Morgan Lorem", "Large student through", 2948),
            (2949, "2014-01-12T05:06", "Alex Surrogate", "Large against", nil),
            (2950, "2014-01-12T10:37", "Concert Hall", "Coming up members", nil),
            (2983, "2014-01-17T16:15", "Morgan Lorem", "Re: Large student through", 2948),
            (3237, "2014-03-09T06:11", "Jordan Imaginary", "During photo", nil),
            (3238, "2014-03-10T03:43", "Kai Placeholder", "Cousin library into drive", 3238),
            (3239, "2014-03-10T04:28", "Pharmacy", "Coming up the garden", nil),
            (3312, "2014-03-26T17:58", "Photo Prints", "Notes from the hall", nil),
            (3313, "2014-03-27T04:40", "Reese Example", "Lovely large yesterday on great dinner", 3313),
            (3314, "2014-03-27T04:42", "Remy Testa", "Hope never cousin letter", 3314),
            (3315, "2014-03-27T09:14", "Noel Notreal", "Large train spring idea", 3315),
            (3316, "2014-03-27T09:46", "Sam Testa", "Know never trip", nil),
            (3317, "2014-03-27T10:37", "Peyton Fictive", "Visit to hope brother in without", 3317),
            (3318, "2014-03-27T11:45", "Quinn Madeup", "Forget dinner neighbor weekend terrible small", nil),
            (3322, "2014-03-28T03:27", "Reese Mock", "Read note out", 3322),
            (3327, "2014-03-29T01:25", "Noel Notreal", "Re: Large train spring idea", 3315),
            (3331, "2014-03-30T04:48", "Peyton Fictive", "Re: Visit to hope brother in without", 3317),
            (3336, "2014-03-30T23:23", "Reese Mock", "Re: Read note out", 3322),
            (3337, "2014-03-31T07:24", "Remy Testa", "Re: Hope never cousin letter", 3314),
            (3339, "2014-03-31T16:50", "Reese Example", "Re: Lovely large yesterday on great dinner", 3313),
            (3341, "2014-04-01T00:13", "Peyton Fictive", "Re: Visit to hope brother in without", 3317),
            (3354, "2014-04-02T16:57", "Reese Example", "Re: Lovely large yesterday on great dinner", 3313),
            (3612, "2014-05-24T18:25", "Alex Imaginary", "Picture think", 3612),
            (3613, "2014-05-26T06:07", "Harper Mock", "Sister forget library perhaps", nil),
            (3614, "2014-05-26T07:23", "Museum Members", "Again nice pharmacy news time", nil),
            (14730, "2018-03-20T17:07", "Noel Ipsum", "Re: Autumn listen", 14662),
            (14731, "2018-03-20T18:26", "Casey Dolor", "Send doctor to picture weekend", 14731),
            (14732, "2018-03-21T03:19", "Blair Notreal", "With city to house between", 14732),
            (14733, "2018-03-21T04:22", "Museum Members", "Coming up the garden", nil),
            (14734, "2018-03-21T08:30", "Oakley Proxy", "Early train morning under city river", 14734),
            (14762, "2018-03-23T17:43", "Oakley Proxy", "Re: Early train morning under city river", 14734),
            (14763, "2018-03-24T04:20", "Casey Dolor", "Re: Send doctor to picture weekend", 14731),
            (14783, "2018-03-25T15:03", "Blair Notreal", "Re: With city to house between", 14732),
            (14805, "2018-03-28T04:18", "Blair Notreal", "Re: With city to house between", 14732),
            (18943, "2019-04-22T14:11", "Hayden Pseudo", "Student write", nil),
            (18944, "2019-04-23T04:59", "Ellis Ersatz", "Weather friend send great", 18944),
            (18945, "2019-04-23T06:39", "Quinn Doe", "Young listen long video", nil),
            (19024, "2019-04-28T12:40", "Ellis Ersatz", "Re: Weather friend send great", 18944),
            (57709, "2026-08-13T18:28", "Bank Statements", "Watch brother wonderful library fine", nil),
            (57710, "2026-08-14T04:28", "Wren Standin", "Through see evening watch", nil),
            (57711, "2026-08-14T04:34", "Reese Doe", "Perhaps story new short week", nil),
        ]
        return Folder(mailboxID: "INBOX", listing: own + Array(578...57_720), own: Set(own),
                      known: Dictionary(uniqueKeysWithValues: known.map { ($0.uid, $0) }))
    }()

    /// The Inbox from 30 May to 10 June 2012, every letter, as the plan has
    /// them: 762 begins a conversation answered by 773 on 5 June, 771 one by
    /// 775, and 777, 8 June's one letter, one answered by 782 on 10 June.
    private static let firstOfJune: [Planned] = [
        (761, "2012-05-30T04:28", "Hayden Lorem", "Student note fine maybe perhaps", nil),
        (762, "2012-06-01T09:26", "Harper Mock", "Watch and winter evening weather lunch", 762),
        (763, "2012-06-01T11:02", "Museum Members", "Terrible great trip doctor listen train", nil),
        (764, "2012-06-01T17:46", "Casey Dummy", "Still young good among dinner answer", nil),
        (765, "2012-06-02T04:37", "Reese Proxy", "Drive young send cousin late", nil),
        (766, "2012-06-02T09:52", "The Daily Brief", "This week the museum", nil),
        (767, "2012-06-03T04:50", "Harper Testa", "Week good garden library book", nil),
        (768, "2012-06-03T06:29", "Concert Hall", "Notes from the library", nil),
        (769, "2012-06-03T08:49", "Wren Testa", "Around doctor city dinner of song", nil),
        (770, "2012-06-04T04:08", "Book Club", "Your update your account", nil),
        (771, "2012-06-04T05:05", "Peyton Doe", "River send again again sister", 771),
        (772, "2012-06-04T15:08", "Library Events", "Notes from the museum", nil),
        (773, "2012-06-05T06:15", "Harper Mock", "Re: Watch and winter evening weather lunch", 762),
        (774, "2012-06-05T08:50", "Taylor Roe", "Garden friend teacher never", nil),
        (775, "2012-06-07T11:19", "Peyton Doe", "Re: River send again again sister", 771),
        (776, "2012-06-07T17:23", "Remy Lorem", "Forget music idea video yesterday morning", nil),
        (777, "2012-06-08T18:20", "Peyton Standin", "From train read story", 777),
        (778, "2012-06-09T05:22", "Blair Ipsum", "By before fine around again", nil),
        (779, "2012-06-09T07:44", "Sam Proxy", "Doctor park to soon question", nil),
        (780, "2012-06-09T18:11", "Pharmacy", "News for members", nil),
        (781, "2012-06-10T06:48", "Emery Madeup", "Trip to winter neighbor long", 781),
        (782, "2012-06-10T08:43", "Peyton Standin", "Re: From train read story", 777),
    ]

    /// Sent Mail: his letters, those copied in from 446 to 24,412 above the
    /// account's own. In it a conversation is his replies: 533 to Harper
    /// Mock on 2 June 2012, his one letter that day, and 536 on 6 June.
    private static let sent: Folder = {
        let own = Array(UInt32(1)...59)
        let known: [Planned] = [
            (532, "2012-05-31T12:21", "Carlo", "Purcell — Concerto", nil),
            (533, "2012-06-02T06:22", "Harper Mock", "Re: Watch and winter evening weather lunch", 533),
            (534, "2012-06-05T06:06", "Carlo", "Haydn — Aria", nil),
            (535, "2012-06-06T05:42", "Carlo", "Elgar — Prelude", nil),
            (536, "2012-06-06T05:42", "Harper Mock", "Re: Watch and winter evening weather lunch", 533),
            (8323, "2019-05-14T18:49", "Carlo", "Purcell — Symphony", nil),
            (8324, "2019-05-15T01:01", "Emery Pseudo", "Re: To tomorrow new idea great between", 8324),
            (8325, "2019-05-15T06:38", "Jules Dummy", "Re: Fine train news on at", 8325),
            (8342, "2019-05-19T11:48", "Jules Dummy", "Re: Fine train news on at", 8325),
        ]
        return Folder(mailboxID: "[Gmail]/Sent Mail", listing: own + Array(446...24_412),
                      own: Set(own), known: Dictionary(uniqueKeysWithValues: known.map { ($0.uid, $0) }))
    }()

    /// All Mail: every letter copied in, from 656 to 84,085, the Inbox's and
    /// his, in the order written. Kai Placeholder's letter of 10 March 2014,
    /// 3238 in the Inbox, is 4417 here, and his reply of 13 March, which is
    /// in Sent Mail and not in the Inbox, is 4441, in its conversation. On 7
    /// and 8 April 2021 his replies to Hayden Ipsum and Parker Notreal, 40081
    /// and 40082, and Tatum Pseudo's 40083, each in a conversation answered
    /// on the 10th.
    private static let allMail: Folder = {
        let own = Array(UInt32(1)...73)
        let known: [Planned] = [
            (4415, "2014-03-09T11:56", "Carlo", "Debussy — Prelude", nil),
            (4416, "2014-03-10T03:36", "Carlo", "Opera house - Wikipedia", nil),
            (4417, "2014-03-10T03:43", "Kai Placeholder", "Cousin library into drive", 4417),
            (4418, "2014-03-10T04:28", "Pharmacy", "Coming up the garden", nil),
            (4441, "2014-03-13T03:59", "Kai Placeholder", "Re: Cousin library into drive", 4417),
            (40066, "2021-04-07T01:23", "Hayden Ipsum", "Re: City sister son send call yesterday", 40028),
            (40072, "2021-04-07T09:11", "Parker Notreal", "Evening very a picture list appointment", 40072),
            (40076, "2021-04-07T12:37", "Hayden Ipsum", "Re: City sister son send call yesterday", 40028),
            (40078, "2021-04-07T14:54", "Kai Surrogate", "Re: News daughter tomorrow", 39981),
            (40079, "2021-04-07T18:01", "Oakley Sample", "Yesterday dinner", nil),
            (40080, "2021-04-07T18:12", "Shay Placeholder", "Always the", nil),
            (40081, "2021-04-07T18:54", "Hayden Ipsum", "Re: City sister son send call yesterday", 40028),
            (40082, "2021-04-07T20:01", "Parker Notreal", "Re: Evening very a picture list appointment", 40072),
            (40083, "2021-04-08T01:30", "Tatum Pseudo", "Re: Book call to and lunch early", 39999),
            (40084, "2021-04-08T03:15", "Library Events", "On weather", nil),
            (40085, "2021-04-08T03:53", "Reese Standin", "During grandchildren into old", nil),
            (40089, "2021-04-08T05:40", "Kai Surrogate", "Re: News daughter tomorrow", 39981),
            (40149, "2021-04-10T10:32", "Kai Surrogate", "Re: News daughter tomorrow", 39981),
            (40153, "2021-04-10T15:58", "Parker Notreal", "Re: Evening very a picture list appointment", 40072),
            (40158, "2021-04-10T23:53", "Tatum Pseudo", "Re: Book call to and lunch early", 39999),
        ]
        return Folder(mailboxID: "[Gmail]/All Mail", listing: own + Array(656...84_085),
                      own: Set(own), known: Dictionary(uniqueKeysWithValues: known.map { ($0.uid, $0) }))
    }()

    private static let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    /// `ymdhm`, "2012-06-01T09:26", in New York.
    private static func ny(_ ymdhm: String) -> Date {
        let parts = ymdhm.split(whereSeparator: { "-T:".contains($0) }).map { Int($0)! }
        return newYork.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2],
                                                 hour: parts[3], minute: parts[4]))!
    }

    /// The day a date falls on in New York, "2012-06-01".
    private func day(_ date: Date) -> String {
        let c = Self.newYork.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// The iPad's clock in the size test's round, 23 October 2026.
    private let now = GoToDateRowTests.ny("2026-10-23T12:44")

    /// The letter with `uid` in `folder`: the plan's, or one of the account's
    /// own, dated from 25 August 2026, or one of its own dated between its
    /// neighbours among the plan's, an hour on from the last of them.
    private func letter(_ uid: UInt32, in folder: Folder) -> MessageSummary {
        let date: Date
        var planned = folder.known[uid]
        if let planned {
            date = Self.ny(planned.at)
        } else if folder.own.contains(uid) {
            date = Self.ny("2026-08-25T09:00").addingTimeInterval(Double(uid) * 3_600)
            planned = (uid, "", "The account", "Own \(uid)", nil)
        } else {
            let around = folder.known.keys.filter { !folder.own.contains($0) }
            let below = around.filter { $0 < uid }.max()
            let above = around.filter { $0 > uid }.min()
            switch (below, above) {
            case let (b?, a?):
                let from = Self.ny(folder.known[b]!.at), to = Self.ny(folder.known[a]!.at)
                date = from.addingTimeInterval(to.timeIntervalSince(from)
                                               * Double(uid - b) / Double(a - b))
            case let (b?, nil):
                date = Self.ny(folder.known[b]!.at).addingTimeInterval(Double(uid - b) * 3_600)
            case let (nil, a?):
                date = Self.ny(folder.known[a]!.at).addingTimeInterval(-Double(a - uid) * 3_600)
            case (nil, nil):
                date = now
            }
        }
        let thread = planned?.began ?? uid
        return MessageSummary(id: "7/\(uid)", mailboxID: folder.mailboxID,
                              sender: planned?.who ?? "Someone", subject: planned?.subject ?? "Letter \(uid)",
                              preview: "", date: date, isRead: true, isFlagged: false,
                              threadID: "\(thread)", gmailMessageID: UInt64(uid),
                              arrived: date)
    }

    private func uid(_ id: String) -> UInt32 {
        UInt32(id.split(separator: "/").last!)!
    }

    /// A jump to `ymd` in `folder`, landed on `anchor` as the repository's
    /// SEARCHes find it (B-115): its window and landing as the repository
    /// works them out, the list's rows, grouped or not, and where the list
    /// opens.
    private struct Opened {
        let window: MessageWindow
        let rows: [MessageThread]
        let opened: ListOpening.DayRow?
    }

    private func jump(to ymd: String, in folder: Folder, landingOn anchor: UInt32,
                      grouped: Bool = true) -> Opened {
        let dayStart = Self.newYork.startOfDay(for: Self.ny(ymd + "T12:00"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = ymd.split(separator: "-").map { Int($0)! }
        let searchedFrom = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
        let notAfter = Self.newYork.date(byAdding: .day, value: IMAPDate.arrivalSlack + 1, to: now)!
        let jumped = PageWindow.jumpWindow(around: anchor, in: folder.listing, limit: 50)
        let letters = jumped.uids.map { letter($0, in: folder) }
        let landed = PageWindow.landing(dates: letters.map(\.date), anchor: jumped.anchorIndex,
                                        dayStart: dayStart, searchedFrom: searchedFrom,
                                        notAfter: notAfter)
        let window = MessageWindow(messages: letters, anchorIndex: landed,
                                   reachedNewest: jumped.reachedNewest,
                                   reachedOldest: jumped.reachedOldest,
                                   landedOn: letters[landed].date,
                                   dayStart: dayStart, notAfter: notAfter)
        let rows = MessageThread.rows(for: letters, grouped: grouped)
        return Opened(window: window, rows: rows, opened: ListOpening.dayRow(in: rows, for: window))
    }

    /// Where `opened` opens: the UID heading the row, the day "Showing"
    /// names, and the UID heading the row under it.
    private func opening(_ opened: Opened, file: StaticString = #filePath,
                     line: UInt = #line) throws -> (uid: UInt32, shows: String, under: UInt32?) {
        let at = try XCTUnwrap(opened.opened, "no row", file: file, line: line)
        let under = opened.rows.indices.contains(at.row + 1) ? uid(opened.rows[at.row + 1].id) : nil
        return (uid(opened.rows[at.row].id), day(at.shown), under)
    }

    /// The row that carries `letter`.
    private func row(holding letter: UInt32, in rows: [MessageThread]) -> MessageThread? {
        rows.first { $0.messages.contains { $0.id == "7/\(letter)" } }
    }

    // MARK: - Organize by Thread on: the days the iPad saw

    /// 1 June 2012, the case found: the day's first letter, 762, was
    /// answered by 773 on 5 June, sixty letters up the jump's window, and
    /// its row is that conversation's, dated 5 June, up among the rows of
    /// 5 June. The list opens on 763, Museum Members, 11.02 am, the oldest
    /// row dated 1 June, and under it 761, of 30 May. "Showing June 1".
    /// It used to open on the conversation, 773.
    func testTheFirstOfJuneOpensOnTheDaysOldestRowNotTheConversationAnsweredLater() throws {
        let opened = jump(to: "2012-06-01", in: Self.inbox, landingOn: 762)
        XCTAssertEqual(opened.window.messages.map { uid($0.id) }, Array((723...822).reversed()))
        XCTAssertEqual(uid(opened.window.messages[opened.window.anchorIndex].id), 762)

        let top = try opening(opened)
        XCTAssertEqual(top.uid, 763, "the day's oldest row, not 773")
        XCTAssertEqual(top.shows, "2012-06-01")
        XCTAssertEqual(top.under, 761, "30 May, below")

        let conversation = try XCTUnwrap(row(holding: 762, in: opened.rows))
        XCTAssertEqual(conversation.messages.map { uid($0.id) }, [773, 762])
        XCTAssertEqual(day(conversation.date), "2012-06-05")
        let at = try XCTUnwrap(opened.rows.firstIndex { $0.id == conversation.id })
        let opens = try XCTUnwrap(opened.opened).row
        XCTAssertLessThan(at, opens, "up where its reply puts it")
        // Above the row opened on, the day's later letters and then the
        // days after it, every row dated on or after the 1st.
        XCTAssertEqual(opened.rows[opens - 1].id, "7/764")
        XCTAssertEqual(opened.rows[opens - 2].id, "7/765")
        XCTAssertTrue(opened.rows[..<opens].allSatisfy { day($0.date) >= "2012-06-01" })
        XCTAssertTrue(opened.rows[(opens + 1)...].allSatisfy { day($0.date) < "2012-06-01" })
    }

    /// 12 January 2014: 2948 answered by 2983, 35 letters up, on 17
    /// January; the list opens on 2949, Alex Surrogate, 5.06 am, over 2947
    /// of the 11th. It used to open on the conversation, dated the 17th.
    func testTheTwelfthOfJanuaryOpensOnItsSecondLetter() throws {
        let opened = jump(to: "2014-01-12", in: Self.inbox, landingOn: 2948)
        let top = try opening(opened)
        XCTAssertEqual(top.uid, 2949)
        XCTAssertEqual(top.shows, "2014-01-12")
        XCTAssertEqual(top.under, 2947)
        XCTAssertEqual(row(holding: 2948, in: opened.rows)?.id, "7/2983")
    }

    /// 21 March 2018: 14732 answered by 14783, 51 letters up, and by 14805
    /// on the page asked as the day lands; 14731 of the 20th answered by
    /// 14763, and 14734 of the 21st by 14762. The list opens on 14733,
    /// Museum Members, 4.22 am, over 14730: 14731 is up in its
    /// conversation's row, dated the 24th, as Mail's list has it.
    func testTheTwentyFirstOfMarchOpensOnItsOldestRowWithTheDayBeforesAnsweredLetterUpTheList() throws {
        let opened = jump(to: "2018-03-21", in: Self.inbox, landingOn: 14732)
        XCTAssertEqual(opened.window.messages.first.map { uid($0.id) }, 14792)
        let top = try opening(opened)
        XCTAssertEqual(top.uid, 14733)
        XCTAssertEqual(top.shows, "2018-03-21")
        XCTAssertEqual(top.under, 14730, "14731 is up with 14763")
        XCTAssertEqual(row(holding: 14731, in: opened.rows)?.id, "7/14763")
        XCTAssertEqual(row(holding: 14734, in: opened.rows)?.id, "7/14762")
        XCTAssertEqual(row(holding: 14732, in: opened.rows)?.messages.map { uid($0.id) }, [14783, 14732],
                       "14805 is on the page asked as the day lands, not in the window")
    }

    /// 23 April 2019: 18944's reply, 19024, is 80 letters up, past the
    /// jump's window: its row is its own, dated the 23rd, and the list opens
    /// on it, as before.
    func testTheTwentyThirdOfAprilOpensOnItsFirstLetterWhoseReplyIsPastTheWindow() throws {
        let opened = jump(to: "2019-04-23", in: Self.inbox, landingOn: 18944)
        XCTAssertEqual(opened.window.messages.first.map { uid($0.id) }, 19004)
        let top = try opening(opened)
        XCTAssertEqual(top.uid, 18944)
        XCTAssertEqual(top.shows, "2019-04-23")
        XCTAssertEqual(top.under, 18943)
    }

    /// 27 March 2014, the day's first three letters each answered later in
    /// a conversation of its own: Reese Example's 3313 by 3339 and 3354,
    /// Remy Testa's 3314 by 3337 on the 31st, Noel Notreal's 3315 by 3327;
    /// and 3317, after 3316, by 3331 and 3341. The list opens on Sam Testa's
    /// 3316, 9.46 am, the oldest row dated the 27th, over Photo Prints of
    /// the 26th, 3312, with Quinn Madeup's 3318 above it; not on the row of
    /// the first letter not in the landed letter's conversation, 3314's,
    /// dated the 31st, up the list. Every row above it is dated on or after
    /// the 27th, and every row below it before.
    func testADayWhoseFirstLettersAreEachAnsweredInTheirOwnConversationsOpensOnItsOldestRow() throws {
        let opened = jump(to: "2014-03-27", in: Self.inbox, landingOn: 3313)
        XCTAssertEqual(uid(opened.window.messages[opened.window.anchorIndex].id), 3313)
        let top = try opening(opened)
        XCTAssertEqual(top.uid, 3316, "not 3337, the conversation of 3314")
        XCTAssertEqual(top.shows, "2014-03-27")
        XCTAssertEqual(top.under, 3312)
        let opens = try XCTUnwrap(opened.opened).row
        XCTAssertEqual(opened.rows[opens - 1].id, "7/3318")
        let answered: [(UInt32, [UInt32])] = [(3313, [3354, 3339, 3313]), (3314, [3337, 3314]),
                                              (3315, [3327, 3315]), (3317, [3341, 3331, 3317])]
        for (first, conversation) in answered {
            let carrying = try XCTUnwrap(row(holding: first, in: opened.rows))
            XCTAssertEqual(carrying.messages.map { uid($0.id) }, conversation)
            let at = try XCTUnwrap(opened.rows.firstIndex { $0.id == carrying.id })
            XCTAssertLessThan(at, opens, "\(first) up where its reply puts it")
        }
        XCTAssertTrue(opened.rows[..<opens].allSatisfy { day($0.date) >= "2014-03-27" })
        XCTAssertTrue(opened.rows[(opens + 1)...].allSatisfy { day($0.date) < "2014-03-27" })
    }

    /// 10 March 2014, whose first letter was not answered in the Inbox, and
    /// Sunday 25 May 2014, which has no letters: as before, 3238 and the
    /// Monday's first, 3613, "Showing May 26".
    func testADayWhoseFirstLetterHeadsItsRowAndADayWithNoMailOpenAsBefore() throws {
        let tenth = try opening(jump(to: "2014-03-10", in: Self.inbox, landingOn: 3238))
        XCTAssertEqual(tenth.uid, 3238)
        XCTAssertEqual(tenth.shows, "2014-03-10")
        XCTAssertEqual(tenth.under, 3237)

        let sunday = jump(to: "2014-05-25", in: Self.inbox, landingOn: 3613)
        let monday = try opening(sunday)
        XCTAssertEqual(monday.uid, 3613)
        XCTAssertEqual(monday.shows, "2014-05-26")
        XCTAssertEqual(monday.under, 3612)
        XCTAssertEqual(day(sunday.window.landedOn), "2014-05-26")
    }

    /// Before the oldest, 1 January 2011: the oldest letter, 578, of 4
    /// January 2012, as before, though the rows under it in the window are
    /// the account's own, dated 2026, on or after the day: below the letter,
    /// never opened on.
    func testADayBeforeTheOldestOpensOnTheOldestNotOnTheAccountsOwnAtTheFoot() throws {
        let opened = jump(to: "2011-01-01", in: Self.inbox, landingOn: 578)
        let top = try opening(opened)
        XCTAssertEqual(top.uid, 578)
        XCTAssertEqual(top.shows, "2012-01-04")
        let under = try XCTUnwrap(top.under)
        XCTAssertTrue(Self.inbox.own.contains(under))
        XCTAssertEqual(opened.rows.count - 1 - (opened.opened?.row ?? 0), 39,
                       "the account's own 39, under it")
        XCTAssertTrue(opened.rows.suffix(39).allSatisfy { day($0.date) >= "2026-08-25" })
    }

    /// The newest day of the letters copied in, 14 August 2026, at the top
    /// of the Inbox: its first letter, the window reaching the newest.
    func testTheNewestDayOpensOnItsFirstLetter() throws {
        let opened = jump(to: "2026-08-14", in: Self.inbox, landingOn: 57_710)
        XCTAssertTrue(opened.window.reachedNewest)
        let top = try opening(opened)
        XCTAssertEqual(top.uid, 57_710)
        XCTAssertEqual(top.shows, "2026-08-14")
        XCTAssertEqual(top.under, 57_709)
    }

    // MARK: - Every letter of the day answered later

    /// Friday 8 June 2012, one letter, 777, answered on the 10th by 782: no
    /// row is dated the 8th. The list opens on the oldest dated after it,
    /// 778, Blair Ipsum, 9 June, 5.22 am, and "Showing" names that day, as
    /// for a day with no mail of its own; under it 776, of the 7th. With
    /// Organize by Thread off, 777 and "Showing June 8", as before.
    func testADayWhoseEveryLetterWasAnsweredLaterOpensOnTheNextRowAndSaysItsDay() throws {
        let opened = jump(to: "2012-06-08", in: Self.inbox, landingOn: 777)
        let top = try opening(opened)
        XCTAssertEqual(top.uid, 778)
        XCTAssertEqual(top.shows, "2012-06-09")
        XCTAssertEqual(top.under, 776)
        XCTAssertEqual(row(holding: 777, in: opened.rows)?.id, "7/782")
        let shown = try XCTUnwrap(opened.opened).shown
        XCTAssertEqual(IMAPDate.spokenDay(shown, now: now, calendar: Self.newYork),
                       IMAPDate.spokenDay(Self.ny("2012-06-09T12:00"), now: now, calendar: Self.newYork))

        let off = try opening(jump(to: "2012-06-08", in: Self.inbox, landingOn: 777, grouped: false))
        XCTAssertEqual(off.uid, 777)
        XCTAssertEqual(off.shows, "2012-06-08")
    }

    // MARK: - Sent Mail and All Mailboxes

    /// Sent Mail, where a conversation is his own replies: on 2 June 2012
    /// his one letter, 533, to Harper Mock, was followed by 536 on the 6th,
    /// so the day has no row of its own: the list opens on 534, of 5 June,
    /// "Showing June 5", under it 532 of 31 May. On 15 May 2019 his first,
    /// 8324, heads its own row: as before; 8325 is up with 8342 of the 19th.
    func testSentMailOpensOnTheOldestRowDatedOnOrAfterTheDay() throws {
        let second = jump(to: "2012-06-02", in: Self.sent, landingOn: 533)
        let top = try opening(second)
        XCTAssertEqual(top.uid, 534)
        XCTAssertEqual(top.shows, "2012-06-05")
        XCTAssertEqual(top.under, 532)
        XCTAssertEqual(row(holding: 533, in: second.rows)?.id, "7/536")

        let may = jump(to: "2019-05-15", in: Self.sent, landingOn: 8324)
        let fifteenth = try opening(may)
        XCTAssertEqual(fifteenth.uid, 8324)
        XCTAssertEqual(fifteenth.shows, "2019-05-15")
        XCTAssertEqual(fifteenth.under, 8323)
        XCTAssertEqual(row(holding: 8325, in: may.rows)?.id, "7/8342")
    }

    /// What dates a row is the folder's own letters. All Mailboxes jumps in
    /// All Mail, where his reply of 13 March 2014 to Kai Placeholder, 4441,
    /// is a letter of the folder: Kai's 4417 is in its row, dated the 13th,
    /// up the list, and the list opens on 4416, his own of 3.36 am, as
    /// before. In the Inbox his reply is not a letter of the list, only of
    /// the reading pane's stack when Complete Threads finds it in Sent Mail
    /// (B-104), and Kai's 3238 is its own row, dated the 10th, opened on.
    /// The same in the conversation the iPad found: 1 June 2012's in the
    /// Inbox is dated 5 June by 773, though its stack has his 536 of the
    /// 6th, and the list opens on 763 either way.
    func testOnlyTheListsOwnLettersDateItsRowsNotHisLettersInTheStack() throws {
        let all = jump(to: "2014-03-10", in: Self.allMail, landingOn: 4416)
        let top = try opening(all)
        XCTAssertEqual(top.uid, 4416)
        XCTAssertEqual(top.shows, "2014-03-10")
        XCTAssertEqual(top.under, 4415)
        let kai = try XCTUnwrap(row(holding: 4417, in: all.rows))
        XCTAssertEqual(kai.messages.map { uid($0.id) }, [4441, 4417])
        XCTAssertEqual(day(kai.date), "2014-03-13")

        let inbox = jump(to: "2014-03-10", in: Self.inbox, landingOn: 3238)
        XCTAssertEqual(try self.opening(inbox).uid, 3238)
        XCTAssertEqual(row(holding: 3238, in: inbox.rows)?.messages.count, 1)

        let june = jump(to: "2012-06-01", in: Self.inbox, landingOn: 762)
        let conversation = try XCTUnwrap(row(holding: 762, in: june.rows))
        let looked = try XCTUnwrap(CompleteThreads.thread(toComplete: conversation, listedIn: .inbox,
                                                          searching: false, switchedOn: true))
        XCTAssertEqual(looked, 762)
        let his = [533, 536].map { letter(UInt32($0), in: Self.sent) }
        let stack = CompleteThreads.shown(his, besides: Set(conversation.messages.compactMap(\.gmailMessageID)))
        XCTAssertEqual(stack.map { uid($0.id) }, [533, 536])
        XCTAssertEqual(day(stack.last!.date), "2012-06-06")
        XCTAssertEqual(day(conversation.date), "2012-06-05", "by 773, not by his 536")
        XCTAssertEqual(try self.opening(june).uid, 763)
    }

    // MARK: - Organize by Thread off: as before

    /// With Organize by Thread off every letter is a row, and the list opens
    /// on the letter landed on and says its day, in every shape above.
    func testWithOrganizeByThreadOffItOpensOnTheLetterLandedOnAsBefore() throws {
        let shapes: [(String, Folder, UInt32)] = [
            ("2012-06-01", Self.inbox, 762), ("2014-01-12", Self.inbox, 2948),
            ("2018-03-21", Self.inbox, 14732), ("2019-04-23", Self.inbox, 18944),
            ("2014-03-10", Self.inbox, 3238), ("2014-05-25", Self.inbox, 3613),
            ("2011-01-01", Self.inbox, 578), ("2026-08-14", Self.inbox, 57_710),
            ("2012-06-08", Self.inbox, 777), ("2012-06-02", Self.sent, 533),
            ("2019-05-15", Self.sent, 8324), ("2014-03-10", Self.allMail, 4416),
        ]
        for (ymd, folder, anchor) in shapes {
            let opened = jump(to: ymd, in: folder, landingOn: anchor, grouped: false)
            let at = try XCTUnwrap(opened.opened, ymd)
            XCTAssertEqual(opened.rows[at.row].id, opened.window.messages[opened.window.anchorIndex].id, ymd)
            XCTAssertEqual(at.row, opened.window.anchorIndex, ymd)
            XCTAssertEqual(at.shown, opened.window.landedOn, ymd)
            XCTAssertEqual(uid(opened.rows[at.row].id), anchor, ymd)
        }
    }

    // MARK: - A folder out of order

    /// In a folder whose letters did not come in the order written, by the
    /// letter landed on, not by date over every row. Within his day the
    /// letter landed on is the lowest UID of the day's (B-115), here 103 of
    /// 3 pm, under 104 of 9 am the same day: with Organize by Thread off it
    /// is 103's row, as before, not the day's earliest. A letter moved into
    /// the folder after the day's first, dated years before, and one dated
    /// wrong, years ahead, each its own row above the day's first and that
    /// answered later: passed over, not "Showing" 2010 or 2036. With no row
    /// at or above the letter dated within the day's bounds, the row that
    /// carries it, and the day landed on; with no row carrying it, nothing.
    func testOutOfOrderItGoesByTheLetterLandedOnAndPassesOverRowsDatedOutsideTheDay() throws {
        let dayStart = Self.ny("2012-06-01T00:00")
        let notAfter = Self.newYork.date(byAdding: .day, value: IMAPDate.arrivalSlack + 1, to: now)!
        func make(_ uid: UInt32, _ at: String, began: UInt32? = nil) -> MessageSummary {
            MessageSummary(id: "7/\(uid)", mailboxID: "INBOX", sender: "Someone",
                           subject: "Letter \(uid)", preview: "", date: Self.ny(at),
                           isRead: true, isFlagged: false, threadID: "\(began ?? uid)",
                           arrived: Self.ny(at))
        }
        func window(_ letters: [MessageSummary], landing uid: UInt32) -> MessageWindow {
            let i = letters.firstIndex { $0.id == "7/\(uid)" }!
            return MessageWindow(messages: letters, anchorIndex: i, reachedNewest: true,
                                 reachedOldest: true, landedOn: letters[i].date,
                                 dayStart: dayStart, notAfter: notAfter)
        }

        let inDay = [make(105, "2012-06-02T10:00"), make(104, "2012-06-01T09:00"),
                     make(103, "2012-06-01T15:00"), make(102, "2012-05-31T10:00"),
                     make(101, "2026-09-01T10:00")]
        let off = MessageThread.rows(for: inDay, grouped: false)
        let byLetter = try XCTUnwrap(ListOpening.dayRow(in: off, for: window(inDay, landing: 103)))
        XCTAssertEqual(off[byLetter.row].id, "7/103", "the letter landed on, not 104, the earliest")
        XCTAssertEqual(day(byLetter.shown), "2012-06-01")

        let moved = [make(108, "2012-06-06T10:00", began: 103), make(107, "2012-06-01T17:00"),
                     make(106, "2036-01-01T10:00"), make(105, "2010-03-01T10:00"),
                     make(103, "2012-06-01T09:00"), make(102, "2012-05-31T10:00"),
                     make(101, "2026-09-01T10:00")]
        let rows = MessageThread.rows(for: moved, grouped: true)
        let opened = try XCTUnwrap(ListOpening.dayRow(in: rows, for: window(moved, landing: 103)))
        XCTAssertEqual(rows[opened.row].id, "7/107", "not 105 of 2010, nor 106 of 2036")
        XCTAssertEqual(day(opened.shown), "2012-06-01")

        let wrong = [make(106, "2036-01-01T10:00", began: 103), make(105, "2010-03-01T10:00"),
                     make(103, "2012-06-01T09:00"), make(102, "2012-05-31T10:00")]
        let none = MessageThread.rows(for: wrong, grouped: true)
        let carrying = try XCTUnwrap(ListOpening.dayRow(in: none, for: window(wrong, landing: 103)))
        XCTAssertEqual(none[carrying.row].messages.map(\.id), ["7/106", "7/103"])
        XCTAssertEqual(carrying.shown, Self.ny("2012-06-01T09:00"), "the day landed on")

        let taken = MessageThread.rows(for: moved.filter { $0.id != "7/103" && $0.id != "7/108" },
                                       grouped: true)
        XCTAssertNil(ListOpening.dayRow(in: taken, for: window(moved, landing: 103)))
        XCTAssertNil(ListOpening.dayRow(in: [], for: MessageWindow(
            messages: [], anchorIndex: 0, reachedNewest: true, reachedOldest: true, landedOn: now)))
    }

    // MARK: - Held until he moves the list

    /// The row opened on is the row held as the pages above come (B-117),
    /// by the letter heading it, and a reply on one of them to a letter in
    /// it takes it up the list, dated as the reply, as Mail's list has it:
    /// the day's next row comes into its place (B-118). On 23 April 2019 the
    /// page asked as the day lands, 19005 to 19054, brings 19024, the reply
    /// to 18944, on 28 April: Quinn Doe's 18945 of the 23rd, 6.39 am, comes
    /// into the top place, over 18943 of the 22nd, and the conversation is
    /// up among the rows of the 28th. Held where it was, as B-117 had it,
    /// the row stayed on top, dated 28 April, over 19023 and the rest of the
    /// 28th. A page after that holds nothing: 18944 is out of his sight,
    /// and were its row in sight, the letter no longer heads it.
    func testAPageAboveThatAnswersTheRowOpenedOnSendsItUpAndTheDaysNextRowTakesItsPlace() throws {
        let opened = jump(to: "2019-04-23", in: Self.inbox, landingOn: 18944)
        let at = try XCTUnwrap(opened.opened)
        var landed = LandedLetter()
        landed.landed(on: opened.rows[at.row].id)
        let place = landedPlace(at: at.row, in: opened.rows)
        XCTAssertEqual(landed.move(forPageAboveFrom: place), .holding("7/18944"))

        let page = PageWindow.newer(than: uid(opened.window.messages[0].id),
                                    in: Self.inbox.listing, limit: 50)
        XCTAssertEqual(page.first, 19054)
        XCTAssertEqual(page.last, 19005)
        let after = MessageThread.rows(for: page.map { letter($0, in: Self.inbox) } + opened.window.messages,
                                       grouped: true)
        let held = try XCTUnwrap(place.landing(in: after, holding: "7/18944"))
        let top = row(at: 120, by: held)
        XCTAssertEqual(after[top].id, "7/18945", "the day's next row, not the conversation")
        XCTAssertEqual(day(after[top].date), "2019-04-23")
        XCTAssertEqual(after[row(at: 216, by: held)].id, "7/18943")
        let conversation = try XCTUnwrap(after.firstIndex { $0.messages.contains { $0.id == "7/18944" } })
        XCTAssertEqual(after[conversation].messages.map { uid($0.id) }, [19024, 18944])
        XCTAssertEqual(day(after[conversation].date), "2019-04-28")
        XCTAssertLessThan(conversation, top, "up the list")
        // Here the rows he could see alone put the same rows on the pane (B-042).
        XCTAssertEqual(row(at: 120, by: try XCTUnwrap(place.landing(in: after))), top)

        XCTAssertEqual(landed.move(forPageAboveFrom: landedPlace(at: top, in: after)), .stay)
        XCTAssertNil(landed.letter)
        landed.landed(on: "7/18944")
        XCTAssertEqual(landed.move(forPageAboveFrom: landedPlace(at: conversation, in: after)), .stay,
                       "in sight, headed by its reply")
    }

    /// All Mail, 8 April 2021: the list opens on the day's first letter,
    /// Tatum Pseudo's 40083, 1.30 am, its own row, over his reply of the 7th
    /// to Parker Notreal, 40082. The page asked as the day lands, 40144 to
    /// 40193, answers both, 40158 and 40153, and both rows go up the list.
    /// The day's next row, Library Events' 40084, 3.15 am, comes into the top
    /// place, and his letter to Hayden Ipsum of the 7th, 40081, closes up
    /// under it: the oldest row dated the 8th over the newest before it,
    /// where Mail's list shows the day. By the rows he could see alone
    /// (B-042), 40081 would stay where it was, a row lower, and 40085 come
    /// down on top.
    func testAPageAboveThatAnswersTheRowOpenedOnAndTheOneUnderItStillOpensOnTheDaysOldestRow() throws {
        let opened = jump(to: "2021-04-08", in: Self.allMail, landingOn: 40083)
        XCTAssertEqual(opened.window.messages.first.map { uid($0.id) }, 40143)
        XCTAssertEqual(opened.window.messages.last.map { uid($0.id) }, 40044)
        let top = try opening(opened)
        XCTAssertEqual(top.uid, 40083)
        XCTAssertEqual(top.shows, "2021-04-08")
        XCTAssertEqual(top.under, 40082)
        let at = try XCTUnwrap(opened.opened).row
        let place = landedPlace(at: at, in: opened.rows)
        var landed = LandedLetter()
        landed.landed(on: opened.rows[at].id)
        XCTAssertEqual(landed.move(forPageAboveFrom: place), .holding("7/40083"))

        let page = PageWindow.newer(than: 40143, in: Self.allMail.listing, limit: 50)
        XCTAssertEqual(page.first, 40193)
        XCTAssertEqual(page.last, 40144)
        let after = MessageThread.rows(for: page.map { letter($0, in: Self.allMail) } + opened.window.messages,
                                       grouped: true)
        let held = try XCTUnwrap(place.landing(in: after, holding: "7/40083"))
        XCTAssertEqual(after[row(at: 120, by: held)].id, "7/40084")
        XCTAssertEqual(day(after[row(at: 120, by: held)].date), "2021-04-08")
        XCTAssertEqual(after[row(at: 216, by: held)].id, "7/40081", "closed up under it")
        XCTAssertEqual(after[row(at: 24, by: held)].id, "7/40085", "under the band")
        XCTAssertEqual(row(holding: 40083, in: after)?.messages.map { uid($0.id) }, [40158, 40083])
        XCTAssertEqual(row(holding: 40082, in: after)?.messages.map { uid($0.id) }, [40153, 40082, 40072])

        let rows = try XCTUnwrap(place.landing(in: after))
        XCTAssertEqual(after[row(at: 312, by: rows)].id, "7/40081", "by the rows alone, where it was")
        XCTAssertEqual(after[row(at: 120, by: rows)].id, "7/40085", "and a newer row of the day on top")
    }

    /// The letter held is the one heading the row opened on, not the one
    /// landed on. 1 June 2012 opened on 763, the list left with two rows in
    /// sight above it, 765 and 764, as VoiceOver's own scrolling can leave
    /// it, which does not let it go; were 764 answered on the page above:
    /// held by 763, its row stays where it was on the pane, 312 points down,
    /// and 765 comes down into 764's place; held by 762, the letter landed
    /// on, which is up the list out of his sight, nothing is held, 765 stays
    /// where it is and 763 goes up a row.
    func testTheRowOpenedOnIsHeldByItsOwnLetterNotTheLetterLandedOn() throws {
        let opened = jump(to: "2012-06-01", in: Self.inbox, landingOn: 762)
        let at = try XCTUnwrap(opened.opened)
        let place = landedPlace(at: at.row, in: opened.rows, under: 2)
        XCTAssertEqual(place.seen.prefix(4).map { uid($0.id) }, [765, 764, 763, 761])
        let page = PageWindow.newer(than: uid(opened.window.messages[0].id),
                                    in: Self.inbox.listing, limit: 50)
        XCTAssertEqual(page.last, 823)
        let answered = page.map { uid -> MessageSummary in
            var summary = letter(uid, in: Self.inbox)
            if uid == 840 { summary.threadID = "764" }
            return summary
        }
        let after = MessageThread.rows(for: answered + opened.window.messages, grouped: true)

        var byRow = LandedLetter()
        byRow.landed(on: opened.rows[at.row].id)
        guard case .holding(let heading) = byRow.move(forPageAboveFrom: place) else {
            return XCTFail("not held")
        }
        XCTAssertEqual(heading, "7/763")
        let held = try XCTUnwrap(place.landing(in: after, holding: heading))
        XCTAssertEqual(after[row(at: 312, by: held)].id, "7/763", "where it was")
        XCTAssertEqual(after[row(at: 216, by: held)].id, "7/765", "765 down into 764's place")

        var byAnchor = LandedLetter()
        byAnchor.landed(on: "7/762")
        XCTAssertEqual(byAnchor.move(forPageAboveFrom: place), .stay, "762 is out of his sight")
        let rows = try XCTUnwrap(place.landing(in: after))
        XCTAssertEqual(after[row(at: 120, by: rows)].id, "7/765")
        XCTAssertEqual(after[row(at: 216, by: rows)].id, "7/763", "763 up a row")
    }

    /// Where the list is as a jump opens on `row`: it the first row he can
    /// see, 120 points down the pane, and five below it, a row apart; the
    /// row above it just out of sight under the band. With `under` rows he
    /// can see above it, as VoiceOver's own scrolling can leave the list,
    /// the first of those 120 points down and the row that many rows lower.
    private func landedPlace(at row: Int, in rows: [MessageThread], under: Int = 0) -> ListPlace {
        let first = row - under
        return ListPlace(rows: rows, visible: (0..<6).map { (first + $0, 120 + Double($0) * 96) }
                            .filter { rows.indices.contains($0.0) },
                         above: first > 0 ? (first - 1, 24) : nil, selected: [])
    }

    /// The row `offset` points down the pane, the list put where `landing`
    /// says, its rows a row apart, 96 points, as `landedPlace` has them:
    /// what he sees there, whichever row the landing names.
    private func row(at offset: Double, by landing: (row: Int, offset: Double)) -> Int {
        landing.row + Int(((offset - landing.offset) / 96).rounded())
    }

    // MARK: - Over the wire

    /// The shipping repository and client against the scripted server, in
    /// New York, the Inbox of 30 May to 10 June 2012 as the plan has it,
    /// with letters every twelve hours either side: the window brings the
    /// day's bounds, his midnight and a week after today, and with the
    /// list's rows the jump to 1 June opens on 763, "Showing" 1 June, and
    /// the jump to 8 June on 778, "Showing" 9 June; with Organize by Thread
    /// off, on 762 and 777, each its own day.
    func testOverTheWireTheWindowCarriesTheDaysBoundsAndOpensOnTheDaysOldestRow() async throws {
        let server = ScriptedIMAPServer(inboxCount: 0)
        defer { XCTAssertEqual(server.violations, []) }
        let suite = "GoToDateRowTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        var planned: [(Planned, Date)] = []
        for k in stride(from: 40, through: 1, by: -1) {
            planned.append(((0, "", "Someone", "Before \(k)", nil),
                            Self.ny("2012-05-30T04:28").addingTimeInterval(-Double(k) * 43_200)))
        }
        planned += Self.firstOfJune.map { ($0, Self.ny($0.at)) }
        for k in 1...60 {
            planned.append(((0, "", "Someone", "After \(k)", nil),
                            Self.ny("2012-06-10T08:43").addingTimeInterval(Double(k) * 43_200)))
        }
        // The k-th delivered is the k-th UID; the plan's by its UID there.
        var messageIDs: [UInt32: String] = [:]
        var delivered: [UInt32: Int] = [:]
        for (k, (plan, date)) in planned.enumerated() {
            var letter = Server.Letter(from: Server.Address(name: plan.who, address: "someone@example.org"),
                                       to: [Server.owner], subject: plan.subject, date: date,
                                       text: "A few words.\r\n", messageID: "<plan-\(k)@example.org>")
            if plan.uid != 0 {
                messageIDs[plan.uid] = letter.messageID
                delivered[plan.uid] = k
            }
            if let began = plan.began, began != plan.uid {
                letter.inReplyTo = messageIDs[began]
                letter.joins = messageIDs[began]
            }
            server.deliver(letter, to: [Server.inbox, Server.allMail])
        }
        let order = server.uids(in: Server.inbox)
        XCTAssertEqual(order.count, 122)
        let validity = server.uidValidity(of: Server.inbox)
        func id(_ planUID: UInt32) -> String { "\(validity)/\(order[delivered[planUID]!])" }

        let clock = now
        let repository = IMAPMailRepository(account: server.account, password: server.password,
                                            transport: server.transportFactory,
                                            recipients: RecipientBook(defaults: defaults),
                                            now: { clock }, calendar: Self.newYork)
        for (ymd, landing, grouped, ungrouped, shows) in [
            ("2012-06-01", UInt32(762), UInt32(763), UInt32(762), "2012-06-01"),
            ("2012-06-08", UInt32(777), UInt32(778), UInt32(777), "2012-06-09"),
        ] {
            let picked = Self.ny(ymd + "T12:00")
            let jumped = try await repository.messages(around: picked, in: "inbox", limit: 50)
            let window = try XCTUnwrap(jumped, ymd)
            XCTAssertEqual(window.messages[window.anchorIndex].id, id(landing), ymd)
            XCTAssertEqual(window.dayStart, Self.newYork.startOfDay(for: picked), ymd)
            XCTAssertEqual(window.notAfter,
                           Self.newYork.date(byAdding: .day, value: IMAPDate.arrivalSlack + 1, to: now), ymd)

            let rows = MessageThread.rows(for: window.messages, grouped: true)
            let opened = try XCTUnwrap(ListOpening.dayRow(in: rows, for: window), ymd)
            XCTAssertEqual(rows[opened.row].id, id(grouped), ymd)
            XCTAssertEqual(day(opened.shown), shows, ymd)

            let flat = MessageThread.rows(for: window.messages, grouped: false)
            let off = try XCTUnwrap(ListOpening.dayRow(in: flat, for: window), ymd)
            XCTAssertEqual(flat[off.row].id, id(ungrouped), ymd)
            XCTAssertEqual(off.shown, window.landedOn, ymd)
            XCTAssertEqual(day(off.shown), ymd, ymd)
        }
    }

    // MARK: - The controller, read

    /// `show` draws the window's letters into the list's rows, then opens on
    /// the row `ListOpening.dayRow` finds in those rows, holds the letter
    /// heading it, says its day, and fetches the previews from it down. The
    /// rows are the list's letters alone, `letters.shown`, which his letters
    /// from Sent Mail are never in. The repositories give the day's bounds.
    func testTheListOpensOnTheDaysRowHoldsItAndSaysItsDay() throws {
        let list = try source("UI/MessageListViewController.swift")
        let show = flat(body(after: "private func show(_ window: MessageWindow)", in: list))
        inOrder(["letters.showWindow(window.messages)",
                 "rebuildRows()",
                 "tableView.reloadData()",
                 "tableView.layoutIfNeeded()",
                 "let day = ListOpening.dayRow(in: threads, for: window)",
                 "let landedRow = day?.row",
                 "if let row = landedRow { tableView.scrollToRow(at: IndexPath(row: row, section: 0), "
                    + "at: .top, animated: false) }",
                 "landed.landed(on: landedRow.map { threads[$0].id })",
                 "say(\"Showing \\(IMAPDate.spokenDay(day?.shown ?? window.landedOn))\")",
                 "let seenFrom = landedRow.flatMap { row in "
                    + "window.messages.firstIndex { $0.id == threads[row].id } } ?? anchorIndex",
                 "loadPreviews(for: window.messages, from: seenFrom) }"], in: show)
        XCTAssertFalse(show.contains("rowIndex(showing:"), show)
        XCTAssertEqual(lines(of: list, containing: "ListOpening.dayRow(").count, 1)
        XCTAssertEqual(lines(of: list, containing: "say(\"Showing ").count, 1)
        XCTAssertTrue(flat(body(after: "private func rebuildRows()", in: list)).contains(
            "rows = MessageThread.rows( for: letters.shown, grouped: !letters.isSearching "
                + "&& ConversationSettings.organizeByThread ).map(Row.thread)"))

        let repository = flat(try source("Mail/IMAPMailRepository.swift"))
        XCTAssertTrue(repository.contains("landedOn: rows[landedIndex].date, dayStart: dayStart, "
                                          + "notAfter: notAfter)"), "the landing's bounds")
        XCTAssertTrue(repository.contains("let dayStart = calendar.startOfDay(for: date)"))
        let mock = flat(try source("Mail/MockMailRepository.swift"))
        XCTAssertTrue(mock.contains("landedOn: all[idx].date, dayStart: date)"))
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
