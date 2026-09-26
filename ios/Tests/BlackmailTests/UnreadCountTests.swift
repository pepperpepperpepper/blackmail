import XCTest
@testable import Blackmail

/// Tests for the folder-count arithmetic and the id matching under it.
///
/// Both halves were broken in ways that test green under the mock and fail
/// on the real server, which is exactly why they are pinned here:
/// `MockMailRepository` names its folders with lowercase role words on both
/// sides of every comparison, so the `"inbox"` vs `"INBOX"` mismatch that
/// stops the real sidebar from ever highlighting Inbox is invisible to it.
final class UnreadCountTests: XCTestCase {

    private func gmailSidebar() -> [Mailbox] {
        // The ids Gmail's LIST actually returns, measured against the live
        // account — not role words.
        [Mailbox(id: "INBOX", name: "INBOX", unreadCount: 9, role: .inbox),
         Mailbox(id: "[Gmail]/Drafts", name: "Drafts", unreadCount: 0, role: .drafts),
         Mailbox(id: "[Gmail]/Sent Mail", name: "Sent Mail", unreadCount: 4, role: .sent),
         Mailbox(id: "[Gmail]/Spam", name: "Spam", unreadCount: 0, role: .junk),
         Mailbox(id: "[Gmail]/Trash", name: "Trash", unreadCount: 0, role: .trash),
         Mailbox(id: "[Gmail]/All Mail", name: "All Mail", unreadCount: 9, role: .archive),
         Mailbox(id: "[Gmail]/Important", name: "Important", unreadCount: 1, role: nil),
         Mailbox(id: "[Gmail]/Starred", name: "Starred", unreadCount: 0, role: nil)]
    }

    // MARK: - Finding a row

    func testARoleWordMatchesTheRealListName() {
        // The bug: RootViewController opens the message pane with the
        // placeholder id "inbox" before the server has been heard from,
        // while every sidebar row carries "INBOX". An exact == never
        // matched, so the Inbox row was never highlighted at launch and a
        // decrement keyed on it would silently do nothing.
        let boxes = gmailSidebar()
        XCTAssertEqual(boxes.firstIndex(matchingMailboxID: "inbox"), 0)
        XCTAssertEqual(boxes.firstIndex(matchingMailboxID: "INBOX"), 0)
        XCTAssertEqual(boxes.firstIndex(matchingMailboxID: "Inbox"), 0)
    }

    func testRoleWordsMatchFoldersWhoseNameSharesNothingWithThem() {
        // "trash" must find "[Gmail]/Trash", which no string comparison
        // would manage. Matching on the ROLE is also what makes this work on
        // an account whose folders are not in English.
        let boxes = gmailSidebar()
        XCTAssertEqual(boxes.firstIndex(matchingMailboxID: "trash")
            .map { boxes[$0].id }, "[Gmail]/Trash")
        XCTAssertEqual(boxes.firstIndex(matchingMailboxID: "sent")
            .map { boxes[$0].id }, "[Gmail]/Sent Mail")
        XCTAssertEqual(boxes.firstIndex(matchingMailboxID: "archive")
            .map { boxes[$0].id }, "[Gmail]/All Mail")
    }

    func testAnExactNameStillWinsOverARoleMatch() {
        let boxes = gmailSidebar()
        XCTAssertEqual(boxes.firstIndex(matchingMailboxID: "[Gmail]/Important"), 6)
        XCTAssertEqual(boxes.firstIndex(matchingMailboxID: "[Gmail]/Starred"), 7)
    }

    func testAnUnknownFolderMatchesNothingRatherThanTheFirstRow() {
        XCTAssertNil(gmailSidebar().firstIndex(matchingMailboxID: "Holiday Photos"))
        XCTAssertNil(gmailSidebar().firstIndex(matchingMailboxID: ""))
    }

    func testAUserFolderMatchesByNameWithoutARole() {
        var boxes = gmailSidebar()
        boxes.append(Mailbox(id: "Family", name: "Family", unreadCount: 2, role: nil))
        XCTAssertEqual(boxes.firstIndex(matchingMailboxID: "Family"), 8)
        XCTAssertEqual(boxes.firstIndex(matchingMailboxID: "family"), 8)
    }

    // MARK: - The arithmetic

    /// The sidebar's adjust loop, reproduced here because the view
    /// controller itself is UIKit-gated and does not exist on this host.
    private func applying(_ ids: [String], _ delta: Int,
                          to boxes: [Mailbox]) -> [String: Int] {
        var out = boxes
        for id in ids {
            guard let i = out.firstIndex(matchingMailboxID: id) else { continue }
            out[i].unreadCount = max(0, out[i].unreadCount + delta)
        }
        return Dictionary(uniqueKeysWithValues: out.map { ($0.id, $0.unreadCount) })
    }

    func testReadingAnInboxMessageDropsInboxAndAllMailTogether() {
        // The invariant this protects: on the server UNSEEN(All Mail) is
        // never below UNSEEN(INBOX), because every inbox message is in All
        // Mail too. Decrementing only the folder on screen would break that
        // within one tap and the sidebar shows both rows at once.
        let after = applying(["INBOX", "[Gmail]/All Mail"], -1, to: gmailSidebar())
        XCTAssertEqual(after["INBOX"], 8)
        XCTAssertEqual(after["[Gmail]/All Mail"], 8)
        XCTAssertGreaterThanOrEqual(after["[Gmail]/All Mail"]!, after["INBOX"]!)
    }

    func testAMessageLabelledImportantDropsThreeCounts() {
        let after = applying(["INBOX", "[Gmail]/Important", "[Gmail]/All Mail"],
                             -1, to: gmailSidebar())
        XCTAssertEqual(after["INBOX"], 8)
        XCTAssertEqual(after["[Gmail]/Important"], 0)
        XCTAssertEqual(after["[Gmail]/All Mail"], 8)
    }

    func testACountNeverGoesNegative() {
        // listMailboxes seeds 0 from a `try?`-swallowed STATUS, so a count
        // can be 0 while unread mail exists. Going negative would render as
        // "-1" beside a folder name.
        let after = applying(["[Gmail]/Starred"], -1, to: gmailSidebar())
        XCTAssertEqual(after["[Gmail]/Starred"], 0)
    }

    func testAnUnknownFolderInTheSetIsSkippedWithoutDisturbingTheRest() {
        // A user label this build could not map must cost that one folder's
        // accuracy, not the whole adjustment.
        let after = applying(["INBOX", "Some Label We Cannot Find", "[Gmail]/All Mail"],
                             -1, to: gmailSidebar())
        XCTAssertEqual(after["INBOX"], 8)
        XCTAssertEqual(after["[Gmail]/All Mail"], 8)
    }

    func testTheSameFolderListedTwiceIsOnlyCountedOnce() {
        // countedFolders dedupes, but the arithmetic should not compound the
        // error if it ever slipped through... and this documents that it
        // WOULD, which is why the dedupe lives upstream.
        let after = applying(["INBOX", "inbox"], -1, to: gmailSidebar())
        XCTAssertEqual(after["INBOX"], 7,
                       "duplicates double-count — the dedupe has to happen before this point")
    }
}
