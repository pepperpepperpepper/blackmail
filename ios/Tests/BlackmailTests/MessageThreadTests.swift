import XCTest
@testable import Blackmail

/// Tests for grouping a list into conversations.
///
/// The failure that matters is not a cosmetic one. A row now stands for
/// several letters, so grouping two unrelated messages together HIDES one
/// behind the other, and splitting a conversation in half makes him read
/// it in two places. Both look like ordinary lists from the outside.
final class MessageThreadTests: XCTestCase {

    private func message(_ id: String, subject: String, thread: String? = nil,
                         from: String = "Jane <jane@example.com>",
                         daysAgo: Int = 0, read: Bool = true,
                         flagged: Bool = false, attachment: Bool = false)
        -> MessageSummary {
        MessageSummary(id: id, mailboxID: "INBOX", sender: from, subject: subject,
                       preview: "", date: Date(timeIntervalSince1970:
                                                1_700_000_000 - Double(daysAgo) * 86_400),
                       isRead: read, isFlagged: flagged, hasAttachment: attachment,
                       threadID: thread)
    }

    // MARK: - What makes a conversation

    func testGmailsOwnThreadIdWinsOverEverythingElse() {
        // Two letters with completely different subjects that Gmail says
        // are one conversation ARE one conversation. Anything else
        // disagrees with what he sees in Gmail on every other device.
        let threads = MessageThread.group([
            message("1/3", subject: "the roof", thread: "99"),
            message("1/2", subject: "something else entirely", thread: "99"),
        ])
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].count, 2)
    }

    func testDifferentThreadIdsStayApartEvenWithTheSameSubject() {
        // Two people can both write "Hello". Merging them would hide one.
        let threads = MessageThread.group([
            message("1/3", subject: "Hello", thread: "1"),
            message("1/2", subject: "Hello", thread: "2"),
        ])
        XCTAssertEqual(threads.count, 2)
    }

    func testWithoutAThreadIdTheSubjectGroupsThroughReAndFwd() {
        // The fallback, for a server with no Gmail extension.
        let threads = MessageThread.group([
            message("1/3", subject: "Re: Fwd: Re: the roof"),
            message("1/2", subject: "Re: the roof"),
            message("1/1", subject: "the roof"),
        ])
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].count, 3)
    }

    func testTheLocalisedReplyPrefixesGroupToo() {
        // A thread broken in half by one "AW:" is a conversation he has to
        // read in two places.
        XCTAssertEqual(MessageThread.normalisedSubject("AW: the roof"), "the roof")
        XCTAssertEqual(MessageThread.normalisedSubject("SV: the roof"), "the roof")
        XCTAssertEqual(MessageThread.normalisedSubject("Fw: the roof"), "the roof")
        XCTAssertEqual(MessageThread.normalisedSubject("RE:  the roof  "), "the roof")
    }

    func testBlankSubjectsDoNotAllCollapseIntoOneConversation() {
        // Grouping every subjectless letter together would hide them
        // behind each other, which is the worst outcome available.
        let threads = MessageThread.group([
            message("1/2", subject: ""),
            message("1/1", subject: "   "),
        ])
        XCTAssertEqual(threads.count, 2)
    }

    // MARK: - Order

    func testAConversationTakesThePositionOfItsNEWESTMessage() {
        // Where he last saw it. Any re-sort moves rows under his thumb.
        let threads = MessageThread.group([
            message("1/5", subject: "newer alone", thread: "a", daysAgo: 0),
            message("1/4", subject: "the roof", thread: "b", daysAgo: 1),
            message("1/3", subject: "older alone", thread: "c", daysAgo: 2),
            message("1/2", subject: "the roof", thread: "b", daysAgo: 3),
        ])
        XCTAssertEqual(threads.map(\.subject),
                       ["newer alone", "the roof", "older alone"])
    }

    func testTheNewestMessageLeadsItsOwnConversation() {
        let threads = MessageThread.group([
            message("1/4", subject: "the roof", thread: "b", daysAgo: 1),
            message("1/2", subject: "the roof", thread: "b", daysAgo: 3),
        ])
        XCTAssertEqual(threads[0].newest.id, "1/4")
        XCTAssertEqual(threads[0].id, "1/4", "the row's identity is its newest letter")
    }

    func testEveryMessageEndsUpInExactlyOneConversation() {
        let all = (1...9).map {
            message("1/\($0)", subject: "s\($0 % 3)", thread: "t\($0 % 3)")
        }
        let threads = MessageThread.group(all)
        let regrouped = threads.flatMap(\.messages).map(\.id)
        XCTAssertEqual(Set(regrouped), Set(all.map(\.id)))
        XCTAssertEqual(regrouped.count, all.count, "a message was duplicated")
    }

    func testAnEmptyListGroupsToNothing() {
        XCTAssertTrue(MessageThread.group([]).isEmpty)
    }

    // MARK: - What the row says

    func testAConversationIsUnreadIfANYLetterInItIs() {
        // Otherwise a thread with an unread reply looks answered.
        let threads = MessageThread.group([
            message("1/2", subject: "s", thread: "t", read: true),
            message("1/1", subject: "s", thread: "t", read: false),
        ])
        XCTAssertFalse(threads[0].isRead)
    }

    func testAConversationIsFlaggedOrCarriesFilesIfAnyLetterDoes() {
        let threads = MessageThread.group([
            message("1/2", subject: "s", thread: "t"),
            message("1/1", subject: "s", thread: "t", flagged: true, attachment: true),
        ])
        XCTAssertTrue(threads[0].isFlagged)
        XCTAssertTrue(threads[0].hasAttachment)
    }

    func testParticipantsAreNamedOnceEachNewestFirst() {
        // "Margaret, Carlo" says it is a back-and-forth; one name does not.
        let threads = MessageThread.group([
            message("1/3", subject: "s", thread: "t", from: "Carlo <c@x.com>"),
            message("1/2", subject: "s", thread: "t", from: "Margaret <m@x.com>"),
            message("1/1", subject: "s", thread: "t", from: "Carlo <c@x.com>"),
        ])
        XCTAssertEqual(threads[0].participants, ["Carlo", "Margaret"])
    }

    func testTheSubjectShownIsTheNEWESTWording() {
        // Subjects drift: "the roof" becomes "the roof and the gutter".
        let threads = MessageThread.group([
            message("1/2", subject: "Re: the roof and the gutter", thread: "t"),
            message("1/1", subject: "the roof", thread: "t"),
        ])
        XCTAssertEqual(threads[0].subject, "Re: the roof and the gutter")
    }

    func testASingleMessageIsStillAConversationOfOne() {
        // The list has one code path, not two.
        let threads = MessageThread.group([message("1/1", subject: "alone")])
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].count, 1)
        XCTAssertEqual(threads[0].newest.id, "1/1")
    }

    // MARK: - The row it draws

    private func thread(_ messages: [MessageSummary]) -> MessageThread {
        MessageThread.group(messages)[0]
    }

    func testTheCountRidesOnTheSenderLine() {
        // In the sender line rather than a badge, because a badge needs a
        // new view in a layout that is frozen.
        let t = thread([
            message("1/2", subject: "s", thread: "t", from: "Carlo <c@x.com>"),
            message("1/1", subject: "s", thread: "t", from: "Margaret <m@x.com>"),
        ])
        XCTAssertEqual(t.displayRow().sender, "Carlo, Margaret (2)")
    }

    func testASingleLetterGetsNoCountAtAll() {
        // "(1)" after a name would be noise on most rows in the list.
        let t = thread([message("1/1", subject: "s", from: "Carlo <c@x.com>")])
        XCTAssertEqual(t.displayRow().sender, "Carlo")
    }

    func testTheRowAlwaysPreviewsTheNEWESTLetter() {
        // There is no opened-out state any more — a conversation opens in
        // the reading pane (B-022) — so the row has one appearance and it
        // shows the latest thing said, which is what he is looking for
        // when he scans the list.
        let t = thread([
            message("1/2", subject: "s", thread: "t"),
            message("1/1", subject: "s", thread: "t"),
        ])
        XCTAssertEqual(t.displayRow().preview, t.newest.preview)
    }

    func testTheRowCarriesTheConversationsUnreadAndFlagState() {
        let t = thread([
            message("1/2", subject: "s", thread: "t", read: true),
            message("1/1", subject: "s", thread: "t", read: false, flagged: true),
        ])
        let row = t.displayRow()
        XCTAssertFalse(row.isRead)
        XCTAssertTrue(row.isFlagged)
    }

    func testTheRowIsIdentifiedByItsNewestLetter() {
        // The table restores the selection by this id across a regroup.
        let t = thread([
            message("1/2", subject: "s", thread: "t"),
            message("1/1", subject: "s", thread: "t"),
        ])
        XCTAssertEqual(t.displayRow().id, "1/2")
    }

    // MARK: - Search results are not grouped

    func testSearchResultsShowTHEMESSAGETHATMATCHEDNotItsNewestSibling() {
        // The defect: a conversation row stands for its newest letter, so
        // a grouped result set answers a search with somebody else's
        // subject on the row. Across 600 of his own messages in All Mail,
        // 26.5% are not newest in their thread, so about a quarter of any
        // result set was being misrepresented.
        let hits = [
            message("1/9", subject: "the roof", thread: "t", daysAgo: 3),
            message("1/4", subject: "Re: the roof", thread: "t", daysAgo: 1),
        ]
        let rows = MessageThread.rows(for: hits, grouped: false)
        XCTAssertEqual(rows.count, 2, "both hits must have their own row")
        XCTAssertEqual(rows.map { $0.displayRow().id }, ["1/9", "1/4"])
    }

    func testAnUngroupedRowLooksLikeAPlainLetter() {
        // No count, no participants list: a search result is one message
        // and must not claim to be a conversation.
        let rows = MessageThread.rows(for: [message("1/9", subject: "s",
                                                    from: "Carlo <c@x.com>")],
                                      grouped: false)
        XCTAssertEqual(rows[0].displayRow().sender, "Carlo")
        XCTAssertEqual(rows[0].count, 1)
    }

    func testBrowsingAFolderStillGroups() {
        let all = [
            message("1/9", subject: "the roof", thread: "t", daysAgo: 3),
            message("1/4", subject: "Re: the roof", thread: "t", daysAgo: 1),
        ]
        XCTAssertEqual(MessageThread.rows(for: all, grouped: true).count, 1)
    }

    func testUngroupedRowsKeepTheOrderTheServerGave() {
        let hits = (1...4).map { message("1/\($0)", subject: "s\($0)", daysAgo: $0) }
        XCTAssertEqual(MessageThread.rows(for: hits, grouped: false).map(\.id),
                       hits.map(\.id))
    }

}
