import XCTest
@testable import Blackmail

/// Tests for the "Organize by Thread" preference.
///
/// The value of the switch is not that anyone expects him to use it — it
/// is that the off position for conversation grouping EXISTS, in plain
/// words, after three of twelve recent letters from him were about
/// something vanishing. These tests pin the two things that would break
/// that quietly: the default, and the round trip.
final class ConversationSettingsTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "blackmail.organizeByThread")
        super.tearDown()
    }

    func testTheDefaultIsGROUPEDLikeMail() {
        UserDefaults.standard.removeObject(forKey: "blackmail.organizeByThread")
        XCTAssertTrue(ConversationSettings.organizeByThread)
    }

    func testTurningItOffStaysOff() {
        ConversationSettings.organizeByThread = false
        XCTAssertFalse(ConversationSettings.organizeByThread)
    }

    func testAnExplicitFalseIsNotConfusedWithNeverSet() {
        // `bool(forKey:)` answers false for a MISSING key, which would make
        // the default silently become ungrouped; `object(forKey:)` is what
        // keeps absent and explicit-false apart. This pins that choice.
        UserDefaults.standard.set(false, forKey: "blackmail.organizeByThread")
        XCTAssertFalse(ConversationSettings.organizeByThread)
        UserDefaults.standard.set(true, forKey: "blackmail.organizeByThread")
        XCTAssertTrue(ConversationSettings.organizeByThread)
    }

    func testTheSwitchComposesWithTheSearchRule() {
        // The seam the switch hangs on: search results are ungrouped no
        // matter which way the preference points, so the two rules must
        // compose rather than one override the other by accident.
        let letters = [
            MessageSummary(id: "1/9", mailboxID: "INBOX", sender: "a <a@x.com>",
                           subject: "Re: roof", preview: "", date: Date(),
                           isRead: true, isFlagged: false, threadID: "t"),
            MessageSummary(id: "1/4", mailboxID: "INBOX", sender: "b <b@x.com>",
                           subject: "Re: roof", preview: "", date: Date(),
                           isRead: true, isFlagged: false, threadID: "t"),
        ]
        XCTAssertEqual(MessageThread.rows(for: letters, grouped: true).count, 1)
        // The preference off: same flat answer as search.
        XCTAssertEqual(MessageThread.rows(for: letters, grouped: false).count, 2)
    }
}
