import XCTest
@testable import Blackmail

/// A conversation's letters in the order the server took them (B-084):
/// by INTERNALDATE, the newest first, the UID breaking a tie, and not by
/// the folder's order, which is the order they were put in it, nor by
/// their Date. Gmail keeps INTERNALDATE through a MOVE.
///
/// On the iPad, after Edit mode's Delete of a conversation, its row in
/// Trash named the oldest letter, its time, its subject without "Re:" and
/// its sender first, and the reading pane's stack ran upside down: the
/// Delete had moved the newest letter first, so it had the lowest UID in
/// Trash. The Delete now goes the oldest first (`ListBatchTests`); this is
/// for letters put in a folder out of turn any other way: moved by another
/// mail program, a reply deleted before the letter it answers, a letter
/// put back.
///
/// The grouping is pure, and tested here first. Then the repository's
/// rows, which carry the time from the FETCH they are drawn from, over
/// `ScriptedIMAPServer`, and the copy of his mail kept on the iPad (D-016).
final class ArrivalOrderTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "ArrivalOrderTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
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

    // MARK: - Letters

    private static let morning = Date(timeIntervalSince1970: 1_790_000_000)

    /// A letter of the roof conversation, `uid` in Trash, that the server
    /// took `minutes` into the morning, dated then unless `dated` says
    /// otherwise.
    private func letter(_ uid: Int, came minutes: Double?, dated: Date? = nil,
                        subject: String = "Re: the roof",
                        sender: String = "Sam Example <sam@example.com>",
                        validity: Int = 1, mailbox: String = "[Gmail]/Trash",
                        thread: String = "roof", read: Bool = true) -> MessageSummary {
        let came = minutes.map { Self.morning.addingTimeInterval($0 * 60) }
        var row = MessageSummary(id: "\(validity)/\(uid)", mailboxID: mailbox, sender: sender,
                                 subject: subject, preview: "letter \(uid)",
                                 date: dated ?? came ?? Self.morning,
                                 isRead: read, isFlagged: false, threadID: thread)
        row.arrived = came
        return row
    }

    private let trash = Mailbox(id: "[Gmail]/Trash", name: "Trash", unreadCount: 0, role: .trash)

    // MARK: - The order they came

    /// Trash after the Delete of a conversation sent the newest first: the
    /// newest letter, the reply at 9:47, has the lower UID. The row stands
    /// for it all the same: its subject, its time and its preview, its
    /// sender named first, and VoiceOver reads the same. The stack runs
    /// from Carlo's letter at the top to the reply, which is open, and the
    /// tap marks the reply read with the unread ones. The rows keep their
    /// places in the list, and the row keeps the id of the letter listed
    /// first in it.
    func testAConversationGoesInTheOrderItsLettersCameNotTheFoldersOrder() {
        let oldest = letter(199, came: 45, subject: "the roof", sender: "Carlo <carlo@example.org>")
        let newest = letter(198, came: 47)
        let listed = [letter(200, came: 50, subject: "Lunch", thread: "lunch"),
                      oldest, newest,
                      letter(150, came: 10, subject: "Tickets", thread: "tickets")]
        let rows = MessageThread.group(listed)

        XCTAssertEqual(rows.map(\.subject), ["Lunch", "Re: the roof", "Tickets"], "in their places")
        let row = rows[1]
        XCTAssertEqual(row.messages.map(\.id), ["1/198", "1/199"])
        XCTAssertEqual(row.newest.id, "1/198")
        XCTAssertEqual(row.id, "1/199", "the letter listed first")
        XCTAssertEqual(row.date, newest.date)
        XCTAssertEqual(row.preview, "letter 198")
        XCTAssertEqual(row.participants, ["Sam Example", "Carlo"])
        let drawn = row.displayRow(in: trash, mine: OwnAddresses([]))
        XCTAssertEqual(drawn.sender, "Sam Example, Carlo")
        XCTAssertEqual(drawn.subject, "Re: the roof")
        XCTAssertEqual(drawn.date, newest.date)
        XCTAssertTrue(row.marksConversation(in: trash))
        let now = Self.morning.addingTimeInterval(3_600)
        XCTAssertEqual(row.accessibilityLabel(in: trash, mine: OwnAddresses([]), now: now),
                       "Sam Example, Carlo, 2 messages, Re: the roof, "
                       + MailFormat.listTimestamp(newest.date, now: now))

        let stack = ConversationDocument.stack(of: row)
        XCTAssertEqual(stack.map(\.id), ["1/199", "1/198"], "the oldest at the top")
        XCTAssertEqual(stack.map(\.isExpanded), [false, true])
        XCTAssertEqual(ConversationDocument.opensAt(stack), ConversationDocument.sectionID(for: "1/199"))
    }

    /// The letters he has not read open with the newest, and the tap marks
    /// the newest first, as it does in a conversation in order.
    func testTheTapMarksTheNewestByArrivalAndTheUnreadOnes() {
        let row = MessageThread.group([
            letter(199, came: 45, read: false),
            letter(198, came: 47, read: false),
            letter(197, came: 46),
        ])[0]
        XCTAssertEqual(row.messages.map(\.id), ["1/198", "1/197", "1/199"])
        XCTAssertEqual(ConversationDocument.readAtTheTap(row).map(\.id), ["1/198", "1/199"])
        XCTAssertEqual(ConversationDocument.openedWithTheNewest(row).map(\.id), ["1/199"])
    }

    /// Two letters the server took in the same second, as its INTERNALDATE
    /// counts them: the higher UID is the newer, in whatever order they are
    /// listed. Where the UIDs cannot be compared, from two folders or under
    /// two UIDVALIDITYs, the list's order.
    func testInTheSameSecondTheHigherUIDIsTheNewer() {
        XCTAssertEqual(MessageThread.byArrival([letter(5, came: 1), letter(9, came: 1)]).map(\.id),
                       ["1/9", "1/5"])
        XCTAssertEqual(MessageThread.byArrival([letter(9, came: 1), letter(5, came: 1)]).map(\.id),
                       ["1/9", "1/5"])
        XCTAssertEqual(MessageThread.byArrival([letter(5, came: 1), letter(9, came: 1, validity: 2)])
            .map(\.id), ["1/5", "2/9"])
        XCTAssertEqual(MessageThread.byArrival([letter(5, came: 1),
                                                letter(9, came: 1, mailbox: "INBOX")]).map(\.id),
                       ["1/5", "1/9"])
        // And a later arrival over a higher UID, all three together.
        XCTAssertEqual(MessageThread.byArrival([letter(9, came: 1), letter(7, came: 2),
                                                letter(5, came: 1)]).map(\.id),
                       ["1/7", "1/9", "1/5"])
    }

    /// B-074's rule holds: a letter dated wrong keeps its place, now the
    /// place its arrival gives it, and not its Date's. A reply that came
    /// last but whose sender's clock said 2023 is the newest, at the bottom
    /// of the stack and open; a letter that came first dated 2037 is at the
    /// top.
    func testALetterDatedWrongKeepsThePlaceItsArrivalGives() {
        let early = Date(timeIntervalSince1970: 1_690_000_000)
        let late = Date(timeIntervalSince1970: 2_130_000_000)
        let row = MessageThread.group([
            letter(9, came: 30, dated: early),
            letter(3, came: 20),
            letter(2, came: 10, dated: late),
        ])[0]
        XCTAssertEqual(row.newest.id, "1/9")
        XCTAssertEqual(row.date, early, "the row shows the newest's own Date")
        let stack = ConversationDocument.stack(of: row)
        XCTAssertEqual(stack.map(\.id), ["1/2", "1/3", "1/9"])
        XCTAssertEqual(stack.last?.isExpanded, true)
        XCTAssertNotEqual(stack.map(\.date), stack.map(\.date).sorted(), "not by Date")
    }

    /// A conversation with a letter whose arrival is not known, a row kept
    /// by a build before rows carried it or a letter kept on the iPad,
    /// keeps the folder's order, as before, and fails nothing.
    func testWithoutEveryArrivalAConversationKeepsTheFoldersOrder() {
        let none = [letter(199, came: nil), letter(198, came: nil)]
        XCTAssertEqual(MessageThread.group(none)[0].messages.map(\.id), ["1/199", "1/198"])
        let some = [letter(199, came: 45), letter(198, came: nil), letter(197, came: 47)]
        XCTAssertEqual(MessageThread.group(some)[0].messages.map(\.id), ["1/199", "1/198", "1/197"])
        XCTAssertEqual(MessageThread.group([letter(1, came: nil)])[0].messages.map(\.id), ["1/1"])
        XCTAssertEqual(MessageThread.group([]).count, 0)
    }

    /// A page appended below can bring a letter that came later than the
    /// ones the row had: a reply deleted before the letter it answers is
    /// lower in Trash. The row then stands for it, and keeps its id, so the
    /// list finds it again where it was: his place, his tick or the letter
    /// open, and VoiceOver's row (B-079). Known by the newest, the row
    /// changed identity under him.
    func testTheRowKeepsItsIdWhenAPageBringsALetterThatCameLater() {
        let firstPage = [letter(300, came: 90, subject: "Lunch", thread: "lunch"),
                         letter(200, came: 30, subject: "the roof")]
        let before = MessageThread.group(firstPage)
        XCTAssertEqual(before[1].id, "1/200")
        XCTAssertEqual(before[1].newest.id, "1/200")

        let after = MessageThread.group(firstPage + [letter(120, came: 60)])
        XCTAssertEqual(after.map(\.id), before.map(\.id))
        XCTAssertEqual(after[1].newest.id, "1/120", "the reply that came later")
        XCTAssertEqual(after[1].subject, "Re: the roof")

        let place = ListPlace(rows: before, visible: [(row: 1, offset: 12)], selected: [1])
        XCTAssertEqual(place.landing(in: after)?.row, 1)
        XCTAssertEqual(place.landing(in: after)?.offset, 12)
        XCTAssertEqual(place.selection(in: after, opened: nil, editing: true), [1])
        XCTAssertEqual(ListVoiceOver.step(after: ListVoiceOver.Row(1, in: before), in: after),
                       .same(1))
    }

    /// A letter that comes into the conversation while it is open goes in
    /// at the bottom, as B-074 has it, and one that came before the stack's
    /// newest, from a page below, does not.
    func testLettersThatComeGoInAtTheBottomByArrival() {
        let shown = [letter(199, came: 45), letter(198, came: 47)]
        let list = MessageThread.group([letter(300, came: 50), letter(199, came: 45),
                                        letter(198, came: 47), letter(100, came: 40)])
        XCTAssertEqual(ConversationDocument.arrivals(after: shown, in: list).map(\.id), ["1/300"])
    }

    // MARK: - Over the server

    private func makeRepository(shelf: MailShelf? = nil) -> IMAPMailRepository {
        IMAPMailRepository(account: server.account, password: server.password,
                           transport: server.transportFactory, recipients: book,
                           shelf: shelf ?? keptShelf(for: server.account))
    }

    /// The roof conversation, three letters, as the server took them, a
    /// minute apart: Carlo's, Jane's reply and Sam's.
    private func roof() -> [Server.Letter] {
        let came = Server.newestDate.addingTimeInterval(3_600)
        let first = Server.Letter(from: Server.carlo, to: [Server.owner], subject: "The roof",
                                  date: came, text: "The first letter.\r\n", flags: ["\\Seen"],
                                  messageID: "<roof-1@example.org>", arrived: came)
        let second = Server.Letter(from: Server.jane, to: [Server.owner], subject: "Re: The roof",
                                   date: came.addingTimeInterval(60),
                                   text: "The second letter.\r\n", flags: ["\\Seen"],
                                   messageID: "<roof-2@example.com>", inReplyTo: first.messageID,
                                   joins: first.messageID, arrived: came.addingTimeInterval(60))
        // Dated before both by its sender's clock, and taken last.
        let third = Server.Letter(from: Server.sam, to: [Server.owner], subject: "Re: The roof",
                                  date: came.addingTimeInterval(-86_400),
                                  text: "The newest letter.\r\n", flags: ["\\Seen"],
                                  messageID: "<roof-3@example.com>", inReplyTo: second.messageID,
                                  joins: first.messageID, arrived: came.addingTimeInterval(120))
        return [first, second, third]
    }

    /// Each row carries when the server took its letter, from the
    /// INTERNALDATE the page is fetched with, which the FETCH asked for
    /// already: nothing more is sent. The Date is the letter's own.
    func testARowCarriesWhenTheServerTookItsLetter() async throws {
        let letters = roof()
        for letter in letters { server.deliver(letter, to: [Server.inbox, Server.allMail]) }
        let repository = makeRepository()
        server.clearLog()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let fetches = server.log.filter { $0.verb == "UID FETCH" }.map(\.command)
        XCTAssertTrue(fetches.contains { $0.contains("INTERNALDATE") })
        for letter in letters {
            let row = try XCTUnwrap(rows.first {
                $0.subject == letter.subject && $0.date == letter.date
            }, letter.messageID)
            XCTAssertEqual(row.arrived, letter.arrived, letter.messageID)
        }
        XCTAssertTrue(rows.allSatisfy { $0.arrived != nil })
    }

    /// The roof conversation in Trash out of turn, the newest letter put
    /// there first, as another mail program or the Delete before B-084 put
    /// it: its row names the newest, Sam's reply, though it has the lowest
    /// UID there and is dated a day before the others, and the stack runs
    /// from Carlo's letter down. The kept copy of Trash reads back the
    /// same, after a launch, before the folder is listed.
    func testOutOfTurnInTrashTheRowStandsForTheLetterThatCameLast() async throws {
        let letters = roof()
        var uids: [UInt32] = []
        for letter in letters.reversed() {
            if let uid = server.deliver(letter, to: [Server.trash, Server.allMail])[Server.trash] {
                uids.append(uid)
            }
        }
        XCTAssertEqual(uids, uids.sorted(), "Sam's reply first")
        let shelf = keptShelf(for: server.account)
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.folders()
        let listed = try await repository.listMessages(in: Server.trash, beforeUID: nil, limit: 50)
        shelf.flush()
        let kept = try XCTUnwrap(keptShelf(for: server.account).page(of: Server.trash)).rows
        XCTAssertEqual(kept.map(\.arrived), listed.map(\.arrived))

        for (rows, label) in [(listed, "listed"), (kept, "kept")] {
            let row = try XCTUnwrap(MessageThread.group(rows).first { $0.count == 3 }, label)
            XCTAssertEqual(row.subject, "Re: The roof", label)
            XCTAssertEqual(row.date, letters[2].date, label)
            XCTAssertEqual(row.participants, ["Sam Example", "jane@example.com", "Carlo"], label)
            // The letter listed first, which since the list went by when
            // each letter arrived (B-178) is Sam's reply, the newest, though
            // it has the lowest UID there; by UID it was Carlo's.
            XCTAssertEqual(row.id, "\(server.uidValidity(of: Server.trash))/\(uids[0])",
                           "the letter listed first, \(label)")
            XCTAssertEqual(ConversationDocument.stack(of: row).map(\.date),
                           letters.map(\.date), label)
        }
    }
}
