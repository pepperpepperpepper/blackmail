import XCTest
@testable import Blackmail

/// Tests for a draft surviving being put down and picked up again.
///
/// The thing being defended is simple: a letter he was interrupted writing
/// must still be there, ONCE, and must be finishable. Every failure below
/// produces either a folder slowly filling with near-identical half-letters
/// or work quietly lost, and at ninety, with email as his main
/// correspondence, being interrupted mid-letter is the normal case rather
/// than the exceptional one.
final class DraftLifecycleTests: XCTestCase {

    private var repository: MockMailRepository!

    override func setUp() {
        super.setUp()
        repository = MockMailRepository()
    }

    private func draft(_ subject: String) -> Draft {
        Draft(to: ["a@b.com"], subject: subject, body: "half a thought")
    }

    // MARK: - Saving

    func testASavedDraftComesBackWithAnIdentity() async throws {
        // Without an id the caller has no way to say "replace THAT one".
        let id = try await repository.saveDraft(draft("first"))
        XCTAssertNotNil(id)
        let reopened = try await repository.loadDraft(id: id!, mailboxID: "drafts")
        XCTAssertEqual(reopened.subject, "first")
        XCTAssertEqual(reopened.savedID, id)
    }

    func testSavingTwiceREPLACESRatherThanAccumulating() async throws {
        // The original bug. Each save appended another copy, so a letter
        // put down three times became three near-identical drafts and he
        // could not tell which was current.
        var d = draft("first")
        d.savedID = try await repository.saveDraft(d)
        d.subject = "second"
        d.savedID = try await repository.saveDraft(d)
        d.subject = "third"
        _ = try await repository.saveDraft(d)

        XCTAssertEqual(repository.savedDrafts.count, 1)
        XCTAssertEqual(repository.savedDrafts.values.first?.subject, "third")
    }

    func testAFirstSaveOfAnUnsavedDraftDoesNotDeleteAnything() async throws {
        _ = try await repository.saveDraft(draft("keep me"))
        _ = try await repository.saveDraft(draft("and me"))
        XCTAssertEqual(repository.savedDrafts.count, 2,
                       "two different letters, not one replacing the other")
    }

    func testTheReturnedIdIsTheNewCopyAndNotTheOldOne() async throws {
        // Chaining depends on this: if a save handed back the id it
        // replaced, the NEXT save would delete a message that no longer
        // exists and leave the current one behind forever.
        var d = draft("first")
        let first = try await repository.saveDraft(d)
        d.savedID = first
        let second = try await repository.saveDraft(d)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(repository.savedDrafts.keys.first, second)
    }

    // MARK: - Reopening

    func testReopeningRestoresEveryFieldHeWouldExpectToStillBeThere() async throws {
        var d = Draft(to: ["a@b.com"], cc: ["c@d.com"],
                      subject: "the roof", body: "about the roof")
        d.savedID = try await repository.saveDraft(d)

        let back = try await repository.loadDraft(id: d.savedID!, mailboxID: "drafts")
        XCTAssertEqual(back.to, ["a@b.com"])
        XCTAssertEqual(back.cc, ["c@d.com"], "a Cc he typed must survive being put down")
        XCTAssertEqual(back.subject, "the roof")
        XCTAssertEqual(back.body, "about the roof")
    }

    func testAReopenedDraftCarriesTheIdSoFinishingItReplacesTheOriginal() async throws {
        var d = draft("first")
        d.savedID = try await repository.saveDraft(d)
        let back = try await repository.loadDraft(id: d.savedID!, mailboxID: "drafts")
        XCTAssertEqual(back.savedID, d.savedID,
                       "lose this and finishing a draft leaves the stub behind")
    }

    // MARK: - Finishing

    func testDeletingADraftRemovesIt() async throws {
        let id = try await repository.saveDraft(draft("regrets"))!
        try await repository.deleteDraft(id)
        XCTAssertTrue(repository.savedDrafts.isEmpty)
    }

    func testTheWholeCycleLeavesDraftsEmpty() async throws {
        // Write, put down, pick up, put down again, finish. The folder
        // should be empty at the end — the state that says "nothing owed".
        var d = draft("to the council")
        d.savedID = try await repository.saveDraft(d)

        var resumed = try await repository.loadDraft(id: d.savedID!, mailboxID: "drafts")
        resumed.body += " and the gutter"
        resumed.savedID = try await repository.saveDraft(resumed)
        XCTAssertEqual(repository.savedDrafts.count, 1)

        // Sending is what the composer does on Send.
        try await repository.send(resumed)
        try await repository.deleteDraft(resumed.savedID!)
        XCTAssertTrue(repository.savedDrafts.isEmpty,
                      "a sent letter must not still be waiting in Drafts")
    }

    // MARK: - The wire

    func testAppendUIDIsReadFromWhatTheServerActuallySays() {
        // The id every replacement depends on. Gmail answers
        // "[APPENDUID 9 4321] (Success)".
        let parsed = IMAPAppend.uid(in: "[APPENDUID 9 4321] (Success)")
        XCTAssertEqual(parsed?.validity, 9)
        XCTAssertEqual(parsed?.uid, 4321)
    }

    func testASilentServerYieldsNilRatherThanAWrongID() {
        // No UIDPLUS means no id. Guessing one would delete an unrelated
        // message on the next save.
        XCTAssertNil(IMAPAppend.uid(in: "(Success)"))
        XCTAssertNil(IMAPAppend.uid(in: "[APPENDUID 9] (Success)"))
        XCTAssertNil(IMAPAppend.uid(in: "[APPENDUID nine 4321]"))
    }

    // MARK: - Bcc, which must appear in exactly one of the two places

    private var account: MailAccount {
        MailAccount(address: "carlo@example.org", username: "carlo@example.org",
                    displayName: "Carlo")
    }

    private func built(_ draft: Draft, includeBcc: Bool) -> String {
        String(decoding: RFC5322Builder.build(draft: draft, from: account,
                                              includeBcc: includeBcc), as: UTF8.self)
    }

    func testASENTMessageCarriesNoBccHeaderAtAll() {
        // The entire point of Bcc. A surviving header shows every blind
        // recipient to everyone who received the letter.
        let d = Draft(to: ["a@b.com"], bcc: ["secret@example.com"], subject: "x")
        let raw = built(d, includeBcc: false)
        XCTAssertFalse(raw.lowercased().contains("bcc:"), raw)
        XCTAssertFalse(raw.contains("secret@example.com"), raw)
    }

    func testASAVEDDRAFTKeepsItsBccOrHeLosesARecipientSilently() {
        // The opposite requirement, and equally real. A draft is stored,
        // not delivered. Drop the Bcc here and he addresses someone, is
        // interrupted, reopens the letter and the person is simply gone
        // with nothing on screen to say so.
        let d = Draft(to: ["a@b.com"], bcc: ["secret@example.com"], subject: "x")
        let raw = built(d, includeBcc: true)
        XCTAssertTrue(raw.contains("Bcc: secret@example.com"), raw)
    }

    func testAnEmptyBccAddsNoHeaderEvenWhenDraftsWouldAllowOne() {
        let d = Draft(to: ["a@b.com"], subject: "x")
        XCTAssertFalse(built(d, includeBcc: true).lowercased().contains("bcc:"))
    }

    func testSeveralBlindRecipientsAreAllKept() {
        let d = Draft(to: ["a@b.com"], bcc: ["one@example.com", "two@example.com"],
                      subject: "x")
        let raw = built(d, includeBcc: true)
        XCTAssertTrue(raw.contains("one@example.com"), raw)
        XCTAssertTrue(raw.contains("two@example.com"), raw)
    }

    func testCcIsUnaffectedAndStillTravelsOnASentMessage() {
        // Regression guard: Bcc and Cc are adjacent in the builder and it
        // would be easy to gate the wrong one.
        let d = Draft(to: ["a@b.com"], cc: ["seen@example.com"],
                      bcc: ["secret@example.com"], subject: "x")
        let raw = built(d, includeBcc: false)
        XCTAssertTrue(raw.contains("Cc: seen@example.com"), raw)
        XCTAssertFalse(raw.contains("secret@example.com"), raw)
    }
}
