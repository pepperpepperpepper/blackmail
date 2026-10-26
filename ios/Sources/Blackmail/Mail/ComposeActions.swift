import Foundation

/// The composer's Send and Save Draft: what happens in which order, what the
/// sheet shows meanwhile, and the time asked of iOS around each.
///
/// Out of `ComposeViewController` for the reason `PaneActions` is: the
/// controller is UIKit and does not exist on the machine the suite runs on.
///
/// Send used to show nothing while it worked. A photo letter takes many
/// seconds to go, and all that time Send was still there to be tapped, which
/// is what a man does when a tap seems to have missed, and every tap sent
/// the letter again. On success the sheet stayed until the letter's old copy
/// had been taken out of Drafts as well, a probe, often a reconnect, and
/// three commands more after the letter had already gone.
///
/// Now Send gives way at the tap to a spinner and "Sending…", with how much
/// has gone for a big letter, and nothing that could close the sheet, change
/// the letter's files or send it again is live until it is answered. The
/// sheet closes as soon as the letter has gone; Drafts is tidied up after.
/// If it did not go, everything is as it was, the letter still in the sheet,
/// with the reason.
///
/// A sheet does one of three things, once: Send, Save Draft or Delete
/// Draft. Whichever comes first is the one; the other two do nothing after
/// it, a Send that failed aside, which puts the sheet back as it was.
///
/// The letter is kept on the iPad while he writes it, and by Save Draft
/// before the sheet goes, and taken off it once it has been sent or deleted
/// (`DraftKeeping`, B-051). A Send that cannot reach the server leaves it
/// in the Outbox, and the sheet closes (B-052).
@MainActor
final class ComposeActions {

    /// What the sheet shows.
    enum Look: Equatable {
        /// Send, Cancel and the attachment controls live, and the sheet can
        /// be swiped away.
        case writing
        /// The letter on its way: these words and a spinner where Send was,
        /// Cancel and the attachment controls held, and the sheet kept on
        /// screen.
        case sending(String)
    }

    private enum Stage: Equatable {
        case writing
        /// The send numbered so, which progress reports carry, so one that
        /// lands after its send has failed changes nothing.
        case sending(Int)
        /// Gone. The sheet is on its way off and nothing more is sent from
        /// it.
        case sent
        /// Put away by Save Draft or Delete Draft. Nothing is sent from it.
        case closed
    }

    private var stage = Stage.writing
    private var sends = 0
    private var words = ""

    /// Photos, videos and files chosen in Photo Library or Attach File
    /// that are still being read in, and so are not in the letter yet
    /// (B-108).
    private var itemsComing = 0
    /// A pick came short while Send waited for it: something he chose is
    /// not in the letter, and he is being told so only now
    /// (`itemLanded(cameShort:)`). The letter does not go (`send`).
    private var cameShort = false
    /// Told as Send or Save Draft begins to wait for what is still coming
    /// (`whenWaiting`).
    private var waiting: () -> Void = {}
    /// Whether something chosen is being read in now, not waiting its turn
    /// nor set aside as the app went (`reading`, B-142); with nothing to
    /// ask, all that is coming is.
    private var isReading: () -> Bool = { true }
    /// Told as the sheet is done with what is coming, nothing waiting for
    /// it (`whenClosed`, B-142).
    private var closing: () -> Void = {}
    /// Everything waiting for what is coming in, Send, Save Draft and the
    /// keep as he leaves the app (`itemsLanded`, `readingEnded`), each to
    /// look again when something lands, is set aside or begins to be read.
    private var lookingAgain: [CheckedContinuation<Void, Never>] = []

    private let sendLetter: (Draft, @escaping UploadProgress) async throws -> Void
    private let saveDraft: (Draft) async throws -> Void
    private let deleteDraft: (String, UInt64?) async throws -> Void
    private let dismiss: () -> Void
    private let showError: (MailError) -> Void
    private let draw: (Look) -> Void
    private let background: BackgroundTime
    private let keeping: DraftKeeping
    private let queued: () -> Void
    private let sent: () -> Void

    /// The autosave waiting for him to stop, and whether he has changed the
    /// letter since the sheet opened.
    private var autosave: Task<Void, Never>?
    private var changed = false
    /// A Send from this sheet came back with a reason (`asksAnyway`).
    private var refused = false

    /// The first three go to the repository; `deleteDraft` is handed the
    /// copy's id and Gmail's id for the letter it is (`Draft.savedLetter`).
    /// `dismiss`, `showError` and `draw` are the sheet's, and are called
    /// only while it is up: nothing is drawn on a sheet that has closed.
    /// `dismiss` is called once, and has to close the sheet whatever it has
    /// up over itself at the time: after it nothing puts the sheet back, so
    /// one left open would be left held as it was drawn last. `keeping` is
    /// where the letter is kept on the iPad; the composer's is
    /// `LocalDrafts`. `queued` is told, just before `dismiss`, that the
    /// letter did not go and waits in the Outbox: `sendLetter` threw
    /// `Outbox.Waiting`. `sent` is told once, before `queued` and
    /// `dismiss`, that the sheet is closing on a letter that has gone or
    /// waits in the Outbox, as Mail's composer plays its sent sound for
    /// both (B-100): never for a refusal, Save Draft, Delete Draft or a
    /// sheet put away without Send.
    init(sendLetter: @escaping (Draft, @escaping UploadProgress) async throws -> Void,
         saveDraft: @escaping (Draft) async throws -> Void,
         deleteDraft: @escaping (String, UInt64?) async throws -> Void,
         dismiss: @escaping () -> Void,
         showError: @escaping (MailError) -> Void,
         draw: @escaping (Look) -> Void,
         background: BackgroundTime,
         keeping: DraftKeeping = .nowhere,
         queued: @escaping () -> Void = {},
         sent: @escaping () -> Void = {}) {
        self.sendLetter = sendLetter
        self.saveDraft = saveDraft
        self.deleteDraft = deleteDraft
        self.dismiss = dismiss
        self.showError = showError
        self.draw = draw
        self.background = background
        self.keeping = keeping
        self.queued = queued
        self.sent = sent
    }

    /// Whether a letter is on its way, or has gone.
    var isSending: Bool {
        switch stage {
        case .sending, .sent: return true
        case .writing, .closed: return false
        }
    }

    /// Whether the sheet is his to change: no letter on its way or gone,
    /// and not put away by Save Draft or Delete Draft. What changes the
    /// letter by itself, as a reply's files coming and going with its
    /// recipients do (`ReplyFiles`, B-107), changes it only then, so the
    /// letter that goes or is saved is the one he saw.
    var isWriting: Bool { stage == .writing }

    // MARK: - Photos, videos and files on their way in

    /// Something chosen in Photo Library or Attach File has started to come
    /// in. Every one has to be matched by `itemLanded`, whether it arrived
    /// or not (`ComposeIntake`).
    func itemComing() {
        itemsComing += 1
    }

    /// `waiting` is told, at the tap, when Send or Save Draft is to wait
    /// for something still coming: what is bringing it in gives all of it
    /// one bound from then (`ComposeIntake.hurry`), so the wait as a whole
    /// is bounded, not each thing one after the other (B-108). Not as he
    /// leaves the app, which waits only while iOS lets it.
    func whenWaiting(_ waiting: @escaping () -> Void) {
        self.waiting = waiting
    }

    /// `isReading` tells whether something chosen is being read in now
    /// (`ComposeIntake.isReading`): not waiting its turn, nor set aside as
    /// the app went, neither of which comes while the app is away
    /// (B-142). What `putAside` waits for.
    func reading(_ isReading: @escaping () -> Bool) {
        self.isReading = isReading
    }

    /// `closing` is told once the sheet is done with what is coming in and
    /// nothing waits for it (B-142): Delete Draft, a Cancel that asked
    /// nothing, the sheet put away, or a Send that has gone. Not Save
    /// Draft, which waits for it after the sheet has gone. What is reading
    /// it in calls the read under way off (`ComposeIntake.close`): left
    /// running, Photos' copy of a large video kept a claim on the app that
    /// got it ended by iOS once he left the app.
    func whenClosed(_ closing: @escaping () -> Void) {
        self.closing = closing
    }

    /// What is being read in has changed without landing
    /// (`ComposeIntake`, B-142): set aside as the app went, so a keep that
    /// waits for it (`putAside`) waits no longer, and a Send or a Save
    /// Draft gives its background time back; or begun, so they ask for it
    /// again. Still coming, it counts as before.
    func readingChanged() {
        lookAgain()
    }

    private func lookAgain() {
        let looking = lookingAgain
        lookingAgain = []
        for continuation in looking { continuation.resume() }
    }

    /// Something chosen is in the letter, could not be attached, or was
    /// counted out at its bound (`ComposeIntake.bound`). `cameShort` when
    /// it ends a pick of which something did not come, which he is told
    /// now: a Send waiting for it does not go, the sheet is put back as it
    /// was, and he sees what is missing (B-108). Told before Send, he chose
    /// to send without it.
    func itemLanded(cameShort short: Bool = false) {
        if short, case .sending = stage { cameShort = true }
        itemsComing = max(0, itemsComing - 1)
        lookAgain()
    }

    /// Returns once nothing he chose is still on its way into the letter.
    ///
    /// The picker hands photos over after it has closed, one at a time, as
    /// each is read in, which for a few large ones or a video takes
    /// seconds. Send or Save Draft tapped in that time took the letter as
    /// it stood at the tap: the photos landed in the sheet after it, and the
    /// letter went, or the draft was kept, without them, with nothing to
    /// say so. Now both wait for them, behind the spinner or after the sheet
    /// has gone, and take the letter once they are in. Each is bounded, and
    /// the wait of Send or Save Draft is, as a whole, from the tap
    /// (`whenWaiting`, `ComposeIntake.bound`).
    ///
    /// `time` is Send's or Save Draft's background time. It is given back
    /// while nothing is being read in, all of it set aside as the app went
    /// or waiting its turn, none of which is read while the app is away
    /// (`isReading`, B-142), and asked for again once something is, or all
    /// of it is in. Held, it kept the app running for nothing until iOS
    /// took it back.
    private func itemsLanded(holding time: BackgroundStretch) async {
        while itemsComing > 0 {
            if isReading() { time.resume() } else { time.pause() }
            await withCheckedContinuation { lookingAgain.append($0) }
        }
        time.resume()
    }

    /// Returns once nothing he chose is being read in (`isReading`): all
    /// of it in, or what is left waiting its turn or set aside as the app
    /// went, which does not come while it is away (B-142).
    private func readingEnded() async {
        while itemsComing > 0, isReading() {
            await withCheckedContinuation { lookingAgain.append($0) }
        }
    }

    // MARK: - Send, Save Draft and Delete Draft

    /// Send tapped. Returns the send's task, or nil when the tap sends
    /// nothing because a letter is already on its way or has gone, or the
    /// sheet has been put away.
    ///
    /// `letter` is asked for the letter once every photo, video and file
    /// chosen before the tap is in it (`itemsLanded`), not at the tap,
    /// waiting at most `ComposeIntake.bound` from the tap for all of them
    /// together (`whenWaiting`). If any of them came to nothing meanwhile
    /// (`itemLanded(cameShort:)`), nothing is sent: the sheet is put back
    /// as it was, with the rows that did come, the words saying what did
    /// not, and Send to tap again (B-108); the letter is kept on the iPad
    /// as it is then, rows and all, as the autosave stopped at the tap
    /// would have kept it. It never goes without something he picked
    /// unless he has been told.
    ///
    /// `draftsChanged` is taken now rather than read from the sheet later:
    /// it is called after the sheet has gone, and the sheet with it.
    ///
    /// `draftSent` hears the id of the letter's copy in Drafts, for a letter
    /// reopened from there, as the sheet closes and before that copy is
    /// removed. The sheet used to cover the folder until the copy had gone;
    /// closing at the 250 uncovers it while the letter just sent is still a
    /// row there, for as long as the tidying takes, and a tap on that row
    /// opened it again as a draft, to be sent a second time. Whatever shows
    /// Drafts takes the row off at this, and `draftsChanged` says when the
    /// folder is worth asking again. The copy an upload of it from the iPad
    /// put up in this launch, which the letter does not name, is not
    /// listed from `keeping.forget` on, until the tidying has removed it
    /// (`LocalDrafts.replacedInDrafts`).
    ///
    /// Background time is asked for at the tap and given back once Drafts
    /// has been tidied, or when iOS wants it back first; and given back
    /// while what it waits for is all set aside as the app went, asked for
    /// again once it is read (`itemsLanded`, B-142). That second case
    /// ends nothing else. The letter carries on if iOS lets the app run,
    /// the sheet stays, and nothing is said until the send itself is
    /// answered, however it is: a letter that went is not reported as
    /// failed for having been interrupted, and one that fails when he comes
    /// back says so then.
    ///
    /// The letter is kept on the iPad as it is taken, and put in the Outbox
    /// by `sendLetter`, so one whose send is cut off by iOS ending the app is
    /// in the Outbox at the next launch, and taken off the iPad once it has
    /// gone, before the sheet closes. With something still coming at the
    /// tap it is kept at the tap as well, as the autosave stopped there
    /// would have kept it (B-142): the wait can outlast the app. What is
    /// set aside as the app goes is read again only on his return
    /// (`ComposeIntake.away`), so a Send left waiting for it goes then,
    /// and an app iOS ends meanwhile leaves the letter in Drafts on the
    /// iPad, not sent.
    ///
    /// A letter that could not reach the server, `Outbox.Waiting` from
    /// `sendLetter`, waits in the Outbox: the sheet closes as for a letter
    /// that went, `queued` says so once, and nothing is drawn after it or
    /// taken out of Drafts, since nothing has gone. Anything else it throws
    /// is about the letter or the account, and the sheet stays with it.
    ///
    /// `sent` is told as the sheet closes either way, once, after
    /// `sendLetter` has returned or thrown `Outbox.Waiting` and never
    /// before: Mail's composer has one 'sent' for a letter that went and
    /// one put in its Outbox, and plays its sound for it (B-100).
    @discardableResult
    func send(_ letter: @escaping () -> Draft, then draftsChanged: (() -> Void)?,
              draftSent: ((String) -> Void)? = nil) -> Task<Void, Never>? {
        guard stage == .writing else { return nil }
        stopAutosave()
        sends += 1
        let attempt = sends
        stage = .sending(attempt)
        cameShort = false
        words = Self.sendingWords(written: 0, of: 0)
        draw(.sending(words))
        if itemsComing > 0 {
            // Kept now, as the autosave stopped here would have kept it:
            // the wait can outlast the app (B-142).
            let draft = letter()
            if !draft.isEmptyLetter { keeping.keep(draft, false) }
            waiting()
        }

        let time = BackgroundStretch("Send", from: background)
        // Holds this strongly, as the send's task below does anyway, and
        // for no longer: the transport lets go of it with the write.
        let report: UploadProgress = { written, total in
            Task { @MainActor in self.uploaded(written, of: total, by: attempt) }
        }
        return Task {
            defer { time.end() }
            await itemsLanded(holding: time)
            // Something he chose came to nothing while this waited, and he
            // is told so now: nothing is taken or sent, and the sheet is
            // his again, with what did come (B-108).
            guard !cameShort else {
                cameShort = false
                stage = .writing
                // Kept as it is now: the autosave stopped at the tap, and
                // rows that came while this waited were no edit of his.
                let draft = letter()
                if !draft.isEmptyLetter { keeping.keep(draft, false) }
                changed = true
                draw(.writing)
                return
            }
            let draft = letter()
            keeping.keep(draft, false)
            changed = true
            do {
                try await sendLetter(draft, report)
            } catch is Outbox.Waiting {
                // In the Outbox, to go when the server can be reached. The
                // sheet is done with it, and from now on the pass takes it.
                stage = .sent
                keeping.letGo()
                closing()
                sent()
                queued()
                dismiss()
                return
            } catch {
                // Pass the real reason through. Flattening everything to
                // "Message was not sent." was fine while that was the only
                // thing the layers below could say; now they can distinguish
                // a letter too large to send from a network that dropped,
                // and collapsing the two would throw away the one piece of
                // information that tells him what to do differently.
                //
                // The sheet is deliberately NOT dismissed on failure - the
                // letter he wrote is still in it.
                refused = true
                stage = .writing
                draw(.writing)
                showError(error as? MailError ?? .notSent)
                return
            }
            stage = .sent
            keeping.forget()
            closing()
            sent()
            dismiss()
            // A sent letter must not stay in Drafts. Without this, finishing
            // a draft left the half-written version behind and he would find
            // it again tomorrow, indistinguishable from something still owed.
            // After the sheet has gone, not before: the letter has, and the
            // tidying is a probe, often a reconnect, and three commands more.
            if let saved = draft.savedID {
                draftSent?(saved)
                try? await deleteDraft(saved, draft.savedLetter)
            }
            // And any copy an upload of it from the iPad left there.
            await keeping.tidy()
            draftsChanged?()
        }
    }

    /// Save Draft, from Cancel: the sheet goes at once and the save follows,
    /// then whatever is showing Drafts catches up.
    ///
    /// The refresh fires AFTER the save, not beside it. Racing them showed
    /// the folder mid-save - the replacement appended and the old copy not
    /// yet gone - so a saved draft appeared briefly as two near-identical
    /// letters. Measured on device: a manual Refresh a moment later showed
    /// one, which is how the race was told apart from a replacement that had
    /// failed.
    ///
    /// Background time is asked for before the sheet goes and given back
    /// once the save is answered, or when iOS wants it back first, and
    /// meanwhile while what it waits for is all set aside as the app went
    /// (`itemsLanded`, B-142). Without
    /// it a photo draft saved just before he locked the iPad could be an
    /// APPEND cut off halfway, and with no sheet left to say so, the draft
    /// would simply not be there.
    ///
    /// `letter` is asked for the draft once every photo, video and file
    /// chosen before the tap is in it, as for Send, at most
    /// `ComposeIntake.bound` from the tap for all of them. One that comes
    /// to nothing is not in it: the sheet has gone, and the draft is kept
    /// without it (B-108). Returns nil, and does nothing, once a
    /// letter is on its way or the sheet has been put away: from the Cancel
    /// sheet, had it still been open when Send went, it would close the
    /// sheet under the letter, and a failure would then have nowhere to be
    /// said. On the iPad that sheet's popover takes a tap on Send and only
    /// closes (B-044), so this is the guard, not a path seen.
    ///
    /// The letter is kept on the iPad as it stands at the tap, before the
    /// sheet goes, and `saveDraft` keeps it again once any photos are in it
    /// and takes it to the server. That used to be all there was, and with
    /// no connection the save failed after the sheet had gone, with nothing
    /// to say so and nothing kept: the letter was lost. Now a save the
    /// server does not take leaves it on the iPad, in Drafts, to go later.
    /// The sheet is let go of once the save has been answered, so nothing
    /// else takes the letter to the server meanwhile.
    ///
    /// Drafts lists it as the sheet goes (`DraftKeeping.putAway`), in place
    /// of the copy it was reopened from, as Mail's does. It used to wait for
    /// the sheet to let go of it, so with no connection the old copy's row
    /// stayed for the seconds the save took to fail, and a new letter had
    /// no row at all (B-087). With a photo still on its way in, once the
    /// photos are in instead: the letter kept at the tap is not the one
    /// saved, and opened or deleted from its row meanwhile, it would be
    /// kept again by the save over what he had done.
    @discardableResult
    func saveAndClose(_ letter: @escaping () -> Draft,
                      then draftsChanged: (() -> Void)?) -> Task<Void, Never>? {
        guard stage == .writing else { return nil }
        stage = .closed
        stopAutosave()
        let time = BackgroundStretch("Save Draft", from: background)
        keeping.keep(letter(), true)
        let itemsWaiting = itemsComing > 0
        if !itemsWaiting { keeping.putAway() }
        if itemsWaiting { waiting() }
        dismiss()
        return Task {
            defer { time.end() }
            await itemsLanded(holding: time)
            let draft = letter()
            if itemsWaiting {
                keeping.keep(draft, true)
                keeping.putAway()
            }
            try? await saveDraft(draft)
            keeping.letGo()
            draftsChanged?()
        }
    }

    /// Delete Draft, from Cancel: the sheet goes at once, then the draft's
    /// copy in Drafts if it has one, then whatever is showing Drafts catches
    /// up. Deletes the saved copy too: this used to only close the sheet,
    /// so "Delete Draft" on a draft reopened from Drafts left it sitting
    /// there, the button saying the one thing it did not do.
    ///
    /// No background time: cut off, the draft is simply still there.
    /// Returns nil, and does nothing, once a letter is on its way or the
    /// sheet has been put away, for the reason `saveAndClose` gives; here
    /// the letter would have been neither sent nor kept. Takes the letter
    /// off the iPad as well, before the sheet goes, and after the copy any
    /// upload of it from there left in Drafts.
    ///
    /// `letter` is Gmail's id for the letter the copy is, as the draft
    /// names it (`Draft.savedLetter`): the copy goes only if the server
    /// shows its UID to hold that letter.
    @discardableResult
    func deleteAndClose(_ saved: String?, letter: UInt64?,
                        then draftsChanged: (() -> Void)?) -> Task<Void, Never>? {
        guard stage == .writing else { return nil }
        stage = .closed
        stopAutosave()
        keeping.forget()
        closing()
        dismiss()
        return Task {
            if let saved { try? await deleteDraft(saved, letter) }
            await keeping.tidy()
            draftsChanged?()
        }
    }

    // MARK: - Kept while he writes

    /// He has changed the letter. It is kept on the iPad once he has stopped
    /// for `keeping.pause`, a few seconds, so that iOS ending the app while
    /// he writes loses at most those seconds. Nothing is kept while a letter
    /// is on its way, nor once the sheet has been put away: Send keeps the
    /// letter itself, and a letter sent, saved or deleted must not be put
    /// back by an autosave that lands after it. A letter he has emptied is
    /// not kept over the one kept before: an empty draft would replace the
    /// copy on the server it was reopened from.
    func edited(_ letter: @escaping () -> Draft) {
        guard stage == .writing else { return }
        changed = true
        autosave?.cancel()
        let keeping = self.keeping
        autosave = Task {
            do { try await keeping.wait(keeping.pause) } catch { return }
            guard !Task.isCancelled, stage == .writing else { return }
            autosave = nil
            let draft = letter()
            if !draft.isEmptyLetter { keeping.keep(draft, false) }
        }
    }

    /// The app is going into the background with the sheet up: the letter,
    /// if he has changed it, is kept now rather than after the pause, which
    /// a suspended app never reaches.
    ///
    /// Inside background time, as Send and Save Draft are, given back once
    /// it is kept. With a photo or a file still being read in, the time is
    /// held until nothing is, and the letter is kept again with what
    /// landed, or until iOS wants it back. Not for what is set aside as the
    /// app went, or waits its turn, neither of which is read while it is
    /// away (`isReading`, B-142): the time is given back at once, and iOS
    /// suspends the app.
    @discardableResult
    func putAside(_ letter: @escaping () -> Draft) -> Task<Void, Never>? {
        guard stage == .writing, changed else { return nil }
        stopAutosave()
        let time = BackgroundStretch("Keep Draft", from: background)
        let draft = letter()
        if !draft.isEmptyLetter { keeping.keep(draft, false) }
        guard itemsComing > 0, isReading() else {
            time.end()
            return nil
        }
        return Task {
            defer { time.end() }
            await readingEnded()
            guard stage == .writing else { return }
            keeping.keep(letter(), false)
        }
    }

    /// Whether Cancel asks Save Draft or Delete Draft however the letter
    /// compares with how it opened. A photo or a file he chose is still
    /// on its way into the letter, which is about to change. Or a Send from
    /// this sheet came back with a reason, the server's refusal, which took
    /// the letter out of the Outbox if it was there: put back by a Cancel
    /// that asked nothing, the next pass would send what the server had
    /// just refused. Or the letter is a draft the pass has given up on
    /// (`DraftKeeping.isHeldDraft`, B-165), whose row in Drafts says "Open
    /// it, tap Cancel, then Save Draft.": closed with nothing asked, Save
    /// Draft was never offered, and it stayed held. One held in the Outbox
    /// still closes unasked, back there, its row saying to tap Send.
    var asksAnyway: Bool { itemsComing > 0 || refused || keeping.isHeldDraft() }

    /// Cancel on a letter as it opened, or emptied by hand
    /// (`ComposeForm.asksBeforeClosing`): the sheet closes with nothing
    /// asked, as Mail closes a letter he never touched. What the sheet kept
    /// on the iPad goes. One whose words were typed and taken out again is
    /// kept as it is now, over whatever the autosave kept of it meanwhile,
    /// and one opened from the Outbox goes back there (`DraftKeeping.putBack`):
    /// kept again as he wrote, it had come out of the Outbox, and left in
    /// Drafts it would never be sent. An emptied one is not kept at all.
    /// Nothing once a letter is on its way, or the sheet has been put away.
    func closeWithoutAsking(_ letter: () -> Draft) {
        guard stage == .writing else { return }
        stage = .closed
        stopAutosave()
        let draft = letter()
        if changed, !draft.isEmptyLetter {
            keeping.keep(draft, false)
            keeping.putBack()
        }
        keeping.abandon()
        closing()
        dismiss()
    }

    /// The sheet has gone without Send, Save Draft or Delete Draft: swiped
    /// away, or Cancel on a letter with nothing in it. Nothing is sent or
    /// saved from it after this. A letter he changed stays on the iPad, and
    /// goes to Drafts with the rest; one he emptied, or never touched, is
    /// left as it was before the sheet opened.
    func sheetGone(_ letter: () -> Draft) {
        guard stage == .writing else { return }
        stage = .closed
        stopAutosave()
        let draft = letter()
        if changed, !draft.isEmptyLetter {
            keeping.keep(draft, false)
            keeping.letGo()
        } else {
            keeping.abandon()
        }
        closing()
    }

    private func stopAutosave() {
        autosave?.cancel()
        autosave = nil
    }

    /// A progress report from send `attempt`, now on the main thread. Drawn
    /// only while that send is still the one on its way, and only when the
    /// words change.
    private func uploaded(_ written: Int, of total: Int, by attempt: Int) {
        guard stage == .sending(attempt) else { return }
        let now = Self.sendingWords(written: written, of: total)
        guard now != words else { return }
        words = now
        draw(.sending(words))
    }

    /// What stands where Send was while the letter goes: "Sending…", and for
    /// a letter big enough to take a while, how much of it has been handed
    /// to the network.
    ///
    /// Never 100%. The count runs ahead of what has arrived
    /// (`UploadProgress`), and after the last byte the server still has to
    /// answer, so a sheet reading 100% would sit there looking stuck. It
    /// closes at the answer instead.
    nonisolated static func sendingWords(written: Int, of total: Int) -> String {
        guard total >= countsFrom, written > 0 else { return "Sending…" }
        return "Sending… \(min(99, written * 100 / total))%"
    }

    /// The smallest letter that says how far it has got. Below about a
    /// megabyte most of a letter goes straight into the network's own
    /// buffer, so a number would jump to the end at once and then wait; a
    /// letter with one photo in it is well past this.
    nonisolated static let countsFrom = 1_000_000
}

/// Time iOS gives the app to finish something after he has left it: a
/// letter on its way, a draft being saved.
///
/// Without it, locking the iPad straight after Send suspends the app with
/// the upload part done. When he comes back the letter can fail, or hang on
/// a connection that has died meanwhile, or have gone and be reported as
/// not sent, which invites him to send it again. With it, iOS lets the work
/// run on for a while after the screen goes off.
///
/// A seam over `UIApplication.beginBackgroundTask`, which the machine the
/// suite runs on does not have. The app's own is `BackgroundTime.app`, in
/// `ComposeViewController.swift`.
struct BackgroundTime {
    /// Asks for time to finish `name`. Returns what to hand `end`, or nil
    /// when none was given. `expired` is called on the main thread if the
    /// time runs out first, and has to give it back before it returns.
    let begin: @MainActor (_ name: String, _ expired: @escaping @MainActor () -> Void) -> Int?
    /// Gives the time back.
    let end: @MainActor (_ id: Int) -> Void
}

/// One stretch of `BackgroundTime`, given back exactly once: when the work
/// is done or when iOS wants it back, whichever comes first, and not again
/// by the other. Not giving it back when iOS asks gets the app killed.
@MainActor
final class BackgroundStretch {
    private let time: BackgroundTime
    private let name: String
    private var id: Int?
    /// Given back by `pause`, to be asked for again by `resume`.
    private var paused = false

    init(_ name: String, from time: BackgroundTime) {
        self.time = time
        self.name = name
        begin()
    }

    private func begin() {
        // Held strongly by the handler, so a stretch nobody else holds is
        // still there to be given back when iOS asks.
        id = time.begin(name) { self.end() }
    }

    /// Given back, for good: done, or iOS wants it back.
    func end() {
        paused = false
        guard let id else { return }
        self.id = nil
        time.end(id)
    }

    /// Given back for now, while the work it is for waits on what is not
    /// happening (B-142), to be asked for again by `resume`. Nothing once
    /// it has been given back.
    func pause() {
        guard id != nil else { return }
        end()
        paused = true
    }

    /// Asked for again, under its name, after `pause`; nothing otherwise,
    /// nor after iOS took it back.
    func resume() {
        guard paused else { return }
        paused = false
        begin()
    }
}
