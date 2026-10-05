import XCTest
@testable import Blackmail

/// The composer's Send and Save Draft without the sheet: one letter per
/// tap however many taps, the sheet closed as soon as the letter has gone
/// and Drafts tidied after, everything put back when it has not gone, and
/// the time asked of iOS around each given back exactly once.
@MainActor
final class ComposeActionsTests: XCTestCase {

    private var log: [String] = []
    private var draws: [ComposeActions.Look] = []
    private var errors: [MailError] = []
    private var sends = 0
    private var saves = 0
    private var background = FakeBackground()

    /// What the send, the save and the draft's removal do when they are
    /// asked: answer at once, unless held.
    private var sendOutcome: Result<Void, Error> = .success(())
    private var holdSend: Held?
    private var holdDelete: Held?
    private var holdSave: Held?
    /// Progress the send reports before it is answered, as (written, total).
    private var progress: [(Int, Int)] = []
    /// The last send's progress report, to be called after it has ended.
    private var lastReport: UploadProgress?
    /// The pauses before an autosave, each waiting until the test lets it
    /// go, so no test waits the real seconds.
    private var pauses = Held()

    /// An autosave's pause a test left waiting ends with it.
    override func tearDown() async throws {
        pauses.release()
        try await super.tearDown()
    }

    /// Everything as a fresh test finds it, for a test that tries more than
    /// one way through.
    private func reset() {
        pauses.release()
        log = []
        draws = []
        errors = []
        sends = 0
        saves = 0
        background = FakeBackground()
        sendOutcome = .success(())
        holdSend = nil
        holdDelete = nil
        holdSave = nil
        progress = []
        lastReport = nil
        pauses = Held()
    }

    /// With `keeping`, what the letter is kept as on the iPad, and taken
    /// off it, is written into the log as well.
    private func makeActions(keeping: Bool = false) -> ComposeActions {
        background.log = { [unowned self] in log.append($0) }
        let kept = DraftKeeping(
            keep: { [unowned self] _, finished in log.append(finished ? "keep" : "keep unfinished") },
            forget: { [unowned self] in log.append("forget") },
            abandon: { [unowned self] in log.append("abandon") },
            letGo: { [unowned self] in log.append("let go") },
            tidy: { [unowned self] in log.append("tidy") },
            putBack: { [unowned self] in log.append("put back") },
            wait: { [pauses] _ in try await pauses.wait() })
        return ComposeActions(
            sendLetter: { [unowned self] _, report in
                sends += 1
                log.append("send")
                lastReport = report
                for (written, total) in progress { report(written, total) }
                try await holdSend?.wait()
                try sendOutcome.get()
            },
            saveDraft: { [unowned self] _ in
                saves += 1
                log.append("save")
                try await holdSave?.wait()
            },
            deleteDraft: { [unowned self] id, _ in
                log.append("delete \(id)")
                try await holdDelete?.wait()
            },
            dismiss: { [unowned self] in log.append("dismiss") },
            showError: { [unowned self] in errors.append($0); log.append("error") },
            draw: { [unowned self] in draws.append($0) },
            background: background.time,
            keeping: keeping ? kept : .nowhere,
            queued: { [unowned self] in log.append("queued") })
    }

    private func draft(savedAs id: String? = nil) -> Draft {
        var draft = Draft()
        draft.to = ["carlo@example.org"]
        draft.subject = "Sunday"
        draft.body = "See you at one."
        draft.savedID = id
        return draft
    }

    /// Waits, a millisecond at a time and never for more than a second,
    /// until `condition` holds.
    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    /// Returns once everything already queued on the main actor has run:
    /// the send's own task up to where it waits, or a progress report's
    /// hop. The main actor takes its work in turn, and this goes last.
    private func settled() async {
        await Task { @MainActor in }.value
    }

    // MARK: - One letter per tap

    /// Send tapped twice, the second while the first is on its way: one
    /// letter. The old Send stayed live through the whole upload, and a tap
    /// that seemed to have missed sent the letter again.
    func testASecondTapWhileTheLetterIsOnItsWaySendsNothing() async throws {
        holdSend = Held()
        let actions = makeActions()

        let first = try XCTUnwrap(actions.send(draft(), then: nil))
        XCTAssertTrue(actions.isSending)
        XCTAssertNil(actions.send(draft(), then: nil), "a second tap while the first is on its way")
        try await until { holdSend?.waiting == 1 }
        XCTAssertNil(actions.send(draft(), then: nil), "a third, with the letter on the wire")

        holdSend?.release()
        await first.value
        XCTAssertNil(actions.send(draft(), then: nil), "a tap after it has gone")
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(log.filter { $0 == "dismiss" }.count, 1)
    }

    // MARK: - Closing when it has gone

    /// A letter reopened from Drafts: the sheet closes as soon as the send
    /// is answered, and only then is the old copy taken out of Drafts and
    /// the folder told, in that order. The sheet used to wait for the probe,
    /// the reconnect and the three commands the tidying costs.
    ///
    /// Whatever shows Drafts hears that the letter has gone as the sheet
    /// closes, before the copy is removed, so its row can go at once: the
    /// folder is uncovered while the row is still there, and a tap on it
    /// opened the letter just sent as a draft, to be sent again.
    ///
    /// A progress report that lands after that draws nothing on a sheet
    /// that has gone.
    func testTheSheetClosesWhenTheLetterHasGoneAndDraftsIsTidiedAfter() async throws {
        holdDelete = Held()
        let actions = makeActions()

        let sending = try XCTUnwrap(actions.send(draft(savedAs: "600003/7"),
                                                 then: { [unowned self] in log.append("drafts changed") },
                                                 draftSent: { [unowned self] in log.append("sent \($0)") }))
        try await until { holdDelete?.waiting == 1 }
        XCTAssertEqual(log, ["begin Send", "send", "dismiss", "sent 600003/7", "delete 600003/7"],
                       "the sheet is closed, and the row told to go, while the draft is still being removed")

        holdDelete?.release()
        await sending.value
        XCTAssertEqual(log, ["begin Send", "send", "dismiss", "sent 600003/7", "delete 600003/7",
                             "drafts changed", "end 1"])
        XCTAssertEqual(errors, [])
        XCTAssertEqual(draws, [.sending("Sending…")], "nothing is put back on a sheet that has gone")

        lastReport?(2_000_000, 5_000_000)
        await settled()
        XCTAssertEqual(draws, [.sending("Sending…")], "nor drawn on it")
    }

    /// A draft that could not be removed does not make the letter unsent:
    /// the sheet has gone, and the folder is still told, as before.
    func testADraftThatCannotBeRemovedStillLeavesTheLetterSent() async throws {
        holdDelete = Held()
        let actions = makeActions()
        let sending = try XCTUnwrap(actions.send(draft(savedAs: "600003/7"),
                                                 then: { [unowned self] in log.append("drafts changed") }))
        try await until { holdDelete?.waiting == 1 }
        holdDelete?.release(.failure(MailError.cannotConnect))
        await sending.value
        XCTAssertEqual(log, ["begin Send", "send", "dismiss", "delete 600003/7",
                             "drafts changed", "end 1"])
        XCTAssertEqual(errors, [])
    }

    /// A new letter has no copy in Drafts to remove; the folder is told all
    /// the same, after the sheet has gone, as it always was.
    func testANewLetterClosesTheSheetAndTellsDraftsWithNothingToRemove() async throws {
        let actions = makeActions()
        await actions.send(draft(), then: { [unowned self] in log.append("drafts changed") },
                           draftSent: { [unowned self] in log.append("sent \($0)") })?.value
        XCTAssertEqual(log, ["begin Send", "send", "dismiss", "drafts changed", "end 1"])
    }

    // MARK: - Putting it back when it has not gone

    /// The send fails: the sheet stays with the letter in it, everything is
    /// live again, and the real reason is said. Drafts is left alone, and
    /// Send works again.
    func testAFailedSendKeepsTheSheetAndPutsEverythingBack() async throws {
        sendOutcome = .failure(MailError.messageTooLarge)
        let actions = makeActions()

        await actions.send(draft(savedAs: "600003/7"),
                           then: { [unowned self] in log.append("drafts changed") })?.value
        XCTAssertEqual(draws, [.sending("Sending…"), .writing])
        XCTAssertEqual(errors, [.messageTooLarge])
        XCTAssertEqual(log, ["begin Send", "send", "error", "end 1"])
        XCTAssertFalse(actions.isSending)

        sendOutcome = .failure(CancellationError())
        await actions.send(draft(), then: nil)?.value
        XCTAssertEqual(sends, 2, "Send is live again after a failure")
        XCTAssertEqual(errors, [.messageTooLarge, .notSent],
                       "a failure that is not a MailError says the letter was not sent")
    }

    // MARK: - Waiting in the Outbox

    /// A send that could not reach the server, `Outbox.Waiting`: the sheet
    /// closes with the notice, the letter is let go to the pass, and nothing
    /// is taken out of Drafts, since nothing has gone. The time is given
    /// back once, and nothing is drawn on the sheet after it.
    func testALetterLeftInTheOutboxClosesTheSheetAndTouchesNothingInDrafts() async throws {
        sendOutcome = .failure(Outbox.Waiting())
        let actions = makeActions(keeping: true)
        await actions.send({ [unowned self] in draft(savedAs: "600003/7") }, then: {
            [unowned self] in log.append("drafts changed")
        }, draftSent: { [unowned self] in log.append("sent \($0)") })?.value
        XCTAssertEqual(log, ["begin Send", "keep unfinished", "send", "let go", "queued", "dismiss",
                             "end 1"])
        XCTAssertEqual(errors, [])
        XCTAssertEqual(draws, [.sending("Sending…")])
        XCTAssertTrue(actions.isSending, "done with: nothing more goes from it")
        XCTAssertNil(actions.send({ [unowned self] in draft() }, then: nil))
        XCTAssertEqual(sends, 1)
    }

    // MARK: - Background time

    /// Asked for once at the tap and given back once, after the letter and
    /// the tidying, whichever way the send ends; and none is asked of iOS
    /// when it will give none.
    func testBackgroundTimeIsGivenBackExactlyOnceWhateverHappens() async throws {
        await makeActions().send(draft(savedAs: "600003/7"), then: nil)?.value
        XCTAssertEqual(background.begun, ["Send"])
        XCTAssertEqual(background.ended, [1])

        reset()
        sendOutcome = .failure(MailError.cannotConnect)
        await makeActions().send(draft(), then: nil)?.value
        XCTAssertEqual(background.begun, ["Send"])
        XCTAssertEqual(background.ended, [1])

        reset()
        background.grants = false
        await makeActions().send(draft(), then: nil)?.value
        XCTAssertEqual(background.ended, [], "nothing to give back")
        XCTAssertEqual(log.filter { $0 == "dismiss" }.count, 1)
    }

    /// iOS wants the time back while the letter is still going: it is given
    /// back there and then, and that is all. The sheet stays, nothing is
    /// said, and the send carries on; when it is answered it is dealt with
    /// as usual, the time not given back a second time.
    func testTheTimeRunningOutEndsNothingButTheTime() async throws {
        holdSend = Held()
        var actions = makeActions()
        var sending = try XCTUnwrap(actions.send(draft(), then: nil))
        try await until { holdSend?.waiting == 1 }

        background.expire(1)
        XCTAssertEqual(background.ended, [1])
        XCTAssertFalse(log.contains("dismiss"))
        XCTAssertEqual(errors, [])
        XCTAssertEqual(draws, [.sending("Sending…")])
        XCTAssertNil(actions.send(draft(), then: nil), "still on its way")

        holdSend?.release()
        await sending.value
        XCTAssertEqual(log.filter { $0 == "dismiss" }.count, 1, "it went, so the sheet closes")
        XCTAssertEqual(background.ended, [1])

        // And a failure after the time ran out is said, as any other.
        reset()
        holdSend = Held()
        actions = makeActions()
        sending = try XCTUnwrap(actions.send(draft(), then: nil))
        try await until { holdSend?.waiting == 1 }
        background.expire(1)
        holdSend?.release(.failure(MailError.cannotConnect))
        await sending.value
        XCTAssertEqual(errors, [.cannotConnect])
        XCTAssertEqual(draws, [.sending("Sending…"), .writing])
        XCTAssertEqual(background.ended, [1])
    }

    // MARK: - Save Draft

    /// The letter is kept on the iPad at the tap, then the sheet goes at
    /// once, the save follows with time asked of iOS for it, then the sheet
    /// lets the letter go, then the folder is told, then the time is given
    /// back. If the time runs out first it is given back then, once, and
    /// the save carries on.
    ///
    /// A save the server does not answer leaves the letter kept: nothing
    /// takes it off the iPad. It used to go to the server and nowhere else,
    /// after the sheet had gone, and a save that failed then lost the letter
    /// with nothing said (B-051).
    func testSaveDraftKeepsTheLetterClosesAndHoldsTimeUntilTheSaveIsAnswered() async throws {
        holdSave = Held()
        let actions = makeActions(keeping: true)
        let saving = try XCTUnwrap(actions.saveAndClose(draft(),
                                                        then: { [unowned self] in log.append("drafts changed") }))
        XCTAssertEqual(log, ["begin Save Draft", "keep", "dismiss"],
                       "kept on the iPad before the sheet goes")
        try await until { holdSave?.waiting == 1 }
        holdSave?.release()
        await saving.value
        XCTAssertEqual(log, ["begin Save Draft", "keep", "dismiss", "save", "let go",
                             "drafts changed", "end 1"])
        XCTAssertEqual(background.ended, [1])

        reset()
        holdSave = Held()
        let again = try XCTUnwrap(makeActions(keeping: true).saveAndClose(
            draft(), then: { [unowned self] in log.append("drafts changed") }))
        try await until { holdSave?.waiting == 1 }
        background.expire(1)
        XCTAssertEqual(background.ended, [1])
        holdSave?.release(.failure(MailError.cannotConnect))
        await again.value
        XCTAssertEqual(log, ["begin Save Draft", "keep", "dismiss", "save", "end 1", "let go",
                             "drafts changed"])
        XCTAssertFalse(log.contains("forget"), "a save that failed leaves the letter kept")
        XCTAssertEqual(background.ended, [1])
        XCTAssertEqual(saves, 1)
    }

    // MARK: - Delete Draft

    /// The sheet goes at once, then the saved copy, then the folder is told;
    /// a letter never saved has no copy to remove, and the folder is told
    /// all the same.
    func testDeleteDraftClosesFirstThenRemovesTheSavedCopy() async throws {
        holdDelete = Held()
        let actions = makeActions()
        let deleting = try XCTUnwrap(actions.deleteAndClose("600003/7", letter: nil,
                                                            then: { [unowned self] in log.append("drafts changed") }))
        XCTAssertEqual(log, ["dismiss"])
        try await until { holdDelete?.waiting == 1 }
        holdDelete?.release()
        await deleting.value
        XCTAssertEqual(log, ["dismiss", "delete 600003/7", "drafts changed"])

        reset()
        await makeActions().deleteAndClose(nil, letter: nil, then: { [unowned self] in log.append("drafts changed") })?.value
        XCTAssertEqual(log, ["dismiss", "drafts changed"])
    }

    // MARK: - One of the three, once

    /// Save Draft and Delete Draft while the letter is on its way do
    /// nothing. The Cancel sheet they are on can still be open when Send is
    /// tapped, and either closed the sheet under the letter: a failure then
    /// had nowhere to be said, and Delete Draft left the letter neither
    /// sent nor kept. After a failure they work again; after the letter has
    /// gone, nothing does.
    func testSaveDraftAndDeleteDraftDoNothingWhileTheLetterIsOnItsWay() async throws {
        holdSend = Held()
        var actions = makeActions()
        var sending = try XCTUnwrap(actions.send(draft(savedAs: "600003/7"), then: nil))
        try await until { holdSend?.waiting == 1 }

        XCTAssertNil(actions.saveAndClose(draft(savedAs: "600003/7"), then: nil))
        XCTAssertNil(actions.deleteAndClose("600003/7", letter: nil, then: nil))
        XCTAssertEqual(log, ["begin Send", "send"], "neither closed the sheet nor touched the draft")

        holdSend?.release(.failure(MailError.cannotConnect))
        await sending.value
        XCTAssertEqual(errors, [.cannotConnect], "the failure is said on the sheet")
        await actions.saveAndClose(draft(savedAs: "600003/7"), then: nil)?.value
        XCTAssertEqual(saves, 1, "Save Draft works again once the letter has failed")

        reset()
        actions = makeActions()
        sending = try XCTUnwrap(actions.send(draft(savedAs: "600003/7"), then: nil))
        await sending.value
        XCTAssertNil(actions.saveAndClose(draft(savedAs: "600003/7"), then: nil))
        XCTAssertNil(actions.deleteAndClose("600003/7", letter: nil, then: nil))
        XCTAssertEqual(log.filter { $0 == "dismiss" }.count, 1, "nothing after the letter has gone")
        XCTAssertEqual(saves, 0)
    }

    /// And once the sheet has been put away by Save Draft or Delete Draft,
    /// nothing is sent from it, nor saved or deleted a second time.
    func testNothingIsSentFromASheetPutAway() async throws {
        let actions = makeActions()
        await actions.saveAndClose(draft(), then: nil)?.value
        XCTAssertNil(actions.send(draft(), then: nil))
        XCTAssertNil(actions.deleteAndClose(nil, letter: nil, then: nil))
        XCTAssertFalse(actions.isSending)

        reset()
        let other = makeActions()
        await other.deleteAndClose("600003/7", letter: nil, then: nil)?.value
        XCTAssertNil(other.send(draft(savedAs: "600003/7"), then: nil))
        XCTAssertNil(other.saveAndClose(draft(savedAs: "600003/7"), then: nil))
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(log.filter { $0 == "dismiss" }.count, 1)
    }

    // MARK: - Photos still on their way in

    /// Send tapped while photos chosen a moment before are still being read
    /// in: the spinner at once, and the letter taken, and sent, only once
    /// the last of them has landed, so it goes with them. It used to be
    /// taken at the tap, and the photos landed in the sheet after the
    /// letter had gone without them.
    func testASendWaitsForPhotosStillOnTheirWayIn() async throws {
        let actions = makeActions()
        var landed = 0
        actions.photoComing()
        actions.photoComing()
        let sending = try XCTUnwrap(actions.send({ [unowned self] in
            log.append("letter with \(landed)")
            return draft()
        }, then: nil))
        await settled()
        XCTAssertEqual(draws, [.sending("Sending…")], "the spinner is up at the tap")
        XCTAssertEqual(log, ["begin Send"], "nothing taken or sent with photos still to come")
        XCTAssertNil(actions.send(draft(), then: nil), "and a second tap sends nothing meanwhile")

        landed = 1
        actions.photoLanded()
        await settled()
        XCTAssertEqual(log, ["begin Send"], "one still to come")

        landed = 2
        actions.photoLanded()
        await sending.value
        XCTAssertEqual(log, ["begin Send", "letter with 2", "send", "dismiss", "end 1"])
    }

    /// Save Draft the same, after the sheet has gone: the draft kept is the
    /// one with the photos in it. A photo that could not be read counts as
    /// landed, and a letter with nothing on its way is taken at once.
    func testSaveDraftWaitsForPhotosStillOnTheirWayIn() async throws {
        let actions = makeActions()
        var landed = 0
        actions.photoComing()
        let saving = try XCTUnwrap(actions.saveAndClose({ [unowned self] in
            log.append("letter with \(landed)")
            return draft()
        }, then: nil))
        await settled()
        // Taken at the tap as well, to be kept on the iPad as it stands
        // before the sheet goes.
        XCTAssertEqual(log, ["begin Save Draft", "letter with 0", "dismiss"])

        landed = 1
        actions.photoLanded()
        await saving.value
        XCTAssertEqual(log, ["begin Save Draft", "letter with 0", "dismiss", "letter with 1",
                             "save", "end 1"])

        reset()
        let other = makeActions()
        other.photoLanded()
        await other.send({ [unowned self] in log.append("letter"); return draft() }, then: nil)?.value
        XCTAssertEqual(log, ["begin Send", "letter", "send", "dismiss", "end 1"],
                       "a photo landing that was never counted holds nothing up")
    }

    // MARK: - The composer held while its letter goes (B-063)

    /// The composer removes the photos it staged as it goes, and it goes
    /// only once nothing holds it. The letter closure it hands Send and Save
    /// Draft holds it, and each keeps that closure until its work is done,
    /// the upload and the save's keep and APPEND, which read those photos:
    /// a sheet closed while its letter still goes is not let go of under
    /// it. Here a stand-in for the sheet, its letter held by the closure.
    func testSendAndSaveDraftHoldTheComposerUntilTheirWorkIsDone() async throws {
        final class Sheet {
            let draft: Draft
            init(_ draft: Draft) { self.draft = draft }
        }
        for way in ["send", "save"] {
            reset()
            let actions = makeActions()
            weak var gone: Sheet?
            let task: Task<Void, Never>?
            do {
                let sheet = Sheet(draft())
                gone = sheet
                if way == "send" {
                    holdSend = Held()
                    task = actions.send({ sheet.draft }, then: nil)
                } else {
                    holdSave = Held()
                    task = actions.saveAndClose({ sheet.draft }, then: nil)
                }
            }
            try await until { self.sends + self.saves == 1 }
            XCTAssertNotNil(gone, "\(way): the sheet was let go of with its letter still going")
            XCTAssertTrue(log.contains("dismiss") == (way == "save"), "\(way): \(log)")

            if way == "send" { holdSend?.release() } else { holdSave?.release() }
            await task?.value
            try await until { gone == nil }
            XCTAssertNil(gone, "\(way): held after its work was done")
        }
    }

    // MARK: - Kept on the iPad

    /// Send keeps the letter as it takes it, so a send cut off by iOS ending
    /// the app leaves it in Drafts, and takes it off the iPad once it has
    /// gone, before the sheet closes; after the sheet, any copy an upload of
    /// it from the iPad left in Drafts goes, after the copy it was reopened
    /// from. One that fails leaves it kept, and the sheet holding it.
    func testSendKeepsTheLetterAsItGoesAndTakesItOffOnceItHasGone() async throws {
        await makeActions(keeping: true).send(draft(savedAs: "600003/7"), then: nil)?.value
        XCTAssertEqual(log, ["begin Send", "keep unfinished", "send", "forget", "dismiss",
                             "delete 600003/7", "tidy", "end 1"])

        reset()
        sendOutcome = .failure(MailError.cannotConnect)
        await makeActions(keeping: true).send(draft(), then: nil)?.value
        XCTAssertEqual(log, ["begin Send", "keep unfinished", "send", "error", "end 1"])
    }

    /// Delete Draft takes the letter off the iPad before the sheet goes,
    /// and any copy an upload of it left in Drafts after the one named.
    func testDeleteDraftTakesTheLetterOffTheIPadBeforeTheSheetGoes() async throws {
        await makeActions(keeping: true).deleteAndClose(
            "600003/7", letter: nil, then: { [unowned self] in log.append("drafts changed") })?.value
        XCTAssertEqual(log, ["forget", "dismiss", "delete 600003/7", "tidy", "drafts changed"])
    }

    /// Kept a pause after he stops, once however many changes came before
    /// it, and taken as it stands then.
    func testAutosaveKeepsTheLetterOnceHeHasStopped() async throws {
        let actions = makeActions(keeping: true)
        var taken = 0
        for _ in 0..<3 {
            actions.edited { [unowned self] in taken += 1; return draft() }
        }
        try await until { pauses.waiting == 3 }
        XCTAssertEqual(log, [], "nothing kept while he is still typing")

        pauses.release()
        try await until { log.count == 1 }
        await settled()
        XCTAssertEqual(log, ["keep unfinished"])
        XCTAssertEqual(taken, 1, "the two changes before the last waited for nothing")
    }

    /// An autosave still waiting when Send, Save Draft or Delete Draft is
    /// tapped keeps nothing when it comes due: a letter sent, saved or
    /// deleted leaves no autosave behind.
    func testAnAutosaveDueAfterSendSaveOrDeleteKeepsNothing() async throws {
        for ending in ["send", "save", "delete"] {
            reset()
            let actions = makeActions(keeping: true)
            actions.edited { [unowned self] in draft() }
            try await until { pauses.waiting == 1 }
            switch ending {
            case "send": await actions.send(draft(), then: nil)?.value
            case "save": await actions.saveAndClose(draft(), then: nil)?.value
            default: await actions.deleteAndClose(nil, letter: nil, then: nil)?.value
            }
            let before = log
            pauses.release()
            await settled()
            await settled()
            XCTAssertEqual(log, before, ending)
            actions.edited { [unowned self] in draft() }
            XCTAssertEqual(pauses.waiting, 0, "\(ending): no autosave after it")
        }
    }

    /// Leaving the app keeps the letter at once, inside background time
    /// given back once it is kept; the autosave that was waiting keeps
    /// nothing more. With a photo still on its way in, the time is held
    /// until it has landed and the letter is kept again with it.
    func testLeavingTheAppKeepsTheLetterAtOnceInsideBackgroundTime() async throws {
        var actions = makeActions(keeping: true)
        actions.edited { [unowned self] in draft() }
        try await until { pauses.waiting == 1 }
        XCTAssertNil(actions.putAside { [unowned self] in draft() })
        XCTAssertEqual(log, ["begin Keep Draft", "keep unfinished", "end 1"])
        pauses.release()
        await settled()
        XCTAssertEqual(log, ["begin Keep Draft", "keep unfinished", "end 1"])

        reset()
        actions = makeActions(keeping: true)
        actions.edited { [unowned self] in draft() }
        actions.photoComing()
        let aside = try XCTUnwrap(actions.putAside { [unowned self] in draft() })
        XCTAssertEqual(log, ["begin Keep Draft", "keep unfinished"])
        actions.photoLanded()
        await aside.value
        XCTAssertEqual(log, ["begin Keep Draft", "keep unfinished", "keep unfinished", "end 1"])
        XCTAssertEqual(background.ended, [1])

        // iOS wanting the time back first gets it, once.
        reset()
        actions = makeActions(keeping: true)
        actions.edited { [unowned self] in draft() }
        actions.photoComing()
        let expiring = try XCTUnwrap(actions.putAside { [unowned self] in draft() })
        background.expire(1)
        actions.photoLanded()
        await expiring.value
        XCTAssertEqual(background.ended, [1])
    }

    /// A letter he has not touched is not kept on leaving the app, and a
    /// sheet closed on it keeps nothing of its own. One he changed and then
    /// swiped away stays on the iPad, to go to Drafts, and nothing is sent,
    /// saved or deleted from the sheet after it.
    func testASheetSwipedAwayKeepsWhatHeWroteAndNothingHeDidNot() async throws {
        var actions = makeActions(keeping: true)
        XCTAssertNil(actions.putAside { [unowned self] in draft() })
        actions.sheetGone { draft() }
        XCTAssertEqual(log, ["abandon"])

        reset()
        actions = makeActions(keeping: true)
        actions.edited { [unowned self] in draft() }
        actions.sheetGone { draft() }
        XCTAssertEqual(log, ["keep unfinished", "let go"])
        XCTAssertNil(actions.send(draft(), then: nil))
        XCTAssertNil(actions.saveAndClose(draft(), then: nil))
        XCTAssertNil(actions.deleteAndClose(nil, letter: nil, then: nil))
        pauses.release()
        await settled()
        XCTAssertEqual(log, ["keep unfinished", "let go"])

        // Emptied by hand: nothing worth keeping.
        reset()
        actions = makeActions(keeping: true)
        actions.edited { Draft() }
        actions.sheetGone { Draft() }
        XCTAssertEqual(log, ["abandon"])
    }

    /// Cancel on a letter as it opened closes the sheet with nothing asked
    /// and leaves the letter as it was before the sheet opened (B-069):
    /// what the sheet kept goes. Words typed and taken out again are kept
    /// as they are now first, over what the autosave kept of them; an
    /// emptied letter is not kept at all. Nothing happens after it, and
    /// nothing at all while a letter goes.
    func testCancelOnALetterAsItOpenedClosesWithoutAsking() async throws {
        var actions = makeActions(keeping: true)
        actions.closeWithoutAsking { draft() }
        XCTAssertEqual(log, ["abandon", "dismiss"])
        actions.sheetGone { draft() }
        XCTAssertNil(actions.send(draft(), then: nil))
        XCTAssertNil(actions.saveAndClose(draft(), then: nil))
        XCTAssertEqual(log, ["abandon", "dismiss"], "the sheet is closed")

        // Typed and taken out again: kept as it is now, put back where it
        // was, and the autosave due is called off.
        reset()
        actions = makeActions(keeping: true)
        actions.edited { [unowned self] in draft() }
        actions.closeWithoutAsking { draft() }
        XCTAssertEqual(log, ["keep unfinished", "put back", "abandon", "dismiss"])
        pauses.release()
        await settled()
        XCTAssertEqual(log, ["keep unfinished", "put back", "abandon", "dismiss"])

        // Emptied by hand.
        reset()
        actions = makeActions(keeping: true)
        actions.edited { Draft() }
        actions.closeWithoutAsking { Draft() }
        XCTAssertEqual(log, ["abandon", "dismiss"])

        // While a letter goes.
        reset()
        actions = makeActions(keeping: true)
        let hold = Held()
        holdSend = hold
        let sending = actions.send(draft(), then: nil)
        try await until { log.contains("send") }
        actions.closeWithoutAsking { draft() }
        XCTAssertFalse(log.contains("abandon"))
        XCTAssertFalse(log.contains("dismiss"))
        hold.release()
        await sending?.value
    }

    /// A photo still coming in from the picker is a change Cancel asks
    /// about, until it has landed.
    func testAPhotoStillComingInIsAChange() {
        let actions = makeActions()
        XCTAssertFalse(actions.asksAnyway)
        actions.photoComing()
        XCTAssertTrue(actions.asksAnyway)
        actions.photoLanded()
        XCTAssertFalse(actions.asksAnyway)
    }

    /// A Send the server refused is a change Cancel asks about, however
    /// the form reads: it took the letter out of the Outbox, and a Cancel
    /// that asked nothing would put it back there for the next pass to
    /// send again (B-069). A Send that has gone, or waits in the Outbox,
    /// closes the sheet, and one cut short by iOS is not a refusal.
    func testASendTheServerRefusedIsAChange() async {
        var actions = makeActions(keeping: true)
        sendOutcome = .failure(MailError.notSent)
        await actions.send(draft(), then: nil)?.value
        XCTAssertEqual(errors, [.notSent])
        XCTAssertTrue(actions.asksAnyway)

        reset()
        actions = makeActions(keeping: true)
        await actions.send(draft(), then: nil)?.value
        XCTAssertFalse(actions.asksAnyway)
    }

    /// A letter he has emptied is not kept, by the autosave nor on leaving
    /// the app: kept, the empty letter would take the place of the one kept
    /// before, and go to Drafts in place of the copy it was reopened from.
    func testAnEmptiedLetterIsNotKeptOverTheOneBefore() async throws {
        let actions = makeActions(keeping: true)
        actions.edited { Draft() }
        try await until { pauses.waiting == 1 }
        pauses.release()
        await settled()
        await settled()
        XCTAssertEqual(log, [], "the autosave keeps nothing")

        actions.edited { Draft() }
        XCTAssertNil(actions.putAside { Draft() })
        XCTAssertEqual(log, ["begin Keep Draft", "end 1"], "nor does leaving the app")
    }

    // MARK: - How much has gone

    /// A big letter says how far it has got as the pieces go; a small one
    /// only says it is sending. Never 100%: the sheet closes at the answer.
    func testABigLetterSaysHowMuchOfItHasGone() async throws {
        holdSend = Held()
        progress = [(1_000_000, 5_000_000), (2_000_000, 5_000_000), (2_010_000, 5_000_000),
                    (5_000_000, 5_000_000)]
        let actions = makeActions()
        let sending = try XCTUnwrap(actions.send(draft(), then: nil))
        try await until { draws.count == 4 }
        XCTAssertEqual(draws, [.sending("Sending…"), .sending("Sending… 20%"),
                               .sending("Sending… 40%"), .sending("Sending… 99%")],
                       "40% twice is drawn once")
        holdSend?.release(.failure(MailError.cannotConnect))
        await sending.value
        XCTAssertEqual(draws.last, .writing)

        XCTAssertEqual(ComposeActions.sendingWords(written: 0, of: 0), "Sending…")
        XCTAssertEqual(ComposeActions.sendingWords(written: 65_536, of: 200_000), "Sending…")
        XCTAssertEqual(ComposeActions.sendingWords(written: 0, of: 5_000_000), "Sending…")
        XCTAssertEqual(ComposeActions.sendingWords(written: 400_000, of: 1_000_000),
                       "Sending… 40%")
    }

    /// Progress that lands after its send has failed changes nothing, not
    /// even once the next send is on its way: a report from the first
    /// send's upload does not put its figure on the second.
    func testProgressFromASendThatHasEndedIsNotDrawn() async throws {
        var reports: [UploadProgress] = []
        let hold = Held()
        let actions = ComposeActions(
            sendLetter: { _, report in
                reports.append(report)
                if reports.count == 1 { throw MailError.cannotConnect }
                try await hold.wait()
            },
            saveDraft: { _ in }, deleteDraft: { _, _ in }, dismiss: {},
            showError: { [unowned self] in errors.append($0) },
            draw: { [unowned self] in draws.append($0) },
            background: background.time)

        await actions.send(draft(), then: nil)?.value
        let second = try XCTUnwrap(actions.send(draft(), then: nil))
        try await until { hold.waiting == 1 }
        XCTAssertEqual(draws, [.sending("Sending…"), .writing, .sending("Sending…")])

        // The late one first; the live one's figure landing after it means
        // the late one has been dealt with too.
        reports[0](2_000_000, 5_000_000)
        reports[1](1_000_000, 5_000_000)
        try await until { draws.count == 4 }
        XCTAssertEqual(draws.last, .sending("Sending… 20%"))
        XCTAssertFalse(draws.contains(.sending("Sending… 40%")))

        hold.release()
        await second.value
    }
}

/// The letter as it stands at the tap, for the tests where no photo is on
/// its way in.
private extension ComposeActions {

    @discardableResult
    func send(_ draft: Draft, then draftsChanged: (() -> Void)?,
              draftSent: ((String) -> Void)? = nil) -> Task<Void, Never>? {
        send({ draft }, then: draftsChanged, draftSent: draftSent)
    }

    @discardableResult
    func saveAndClose(_ draft: Draft, then draftsChanged: (() -> Void)?) -> Task<Void, Never>? {
        saveAndClose({ draft }, then: draftsChanged)
    }
}
