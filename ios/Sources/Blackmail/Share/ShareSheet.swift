import Foundation

/// The share extension's letter without its sheet: what Send and Cancel do,
/// in which order, and what the address fields offer.
///
/// The order is not decided here. It is `ComposeActions`', the app
/// composer's own (B-044): Send gives way at the tap to "Sending…" and how
/// far a big letter has got, a second tap sends nothing, the sheet closes
/// at the server's 250, and a letter that did not go leaves everything as
/// it was, with the reason. A sheet over Safari is where a tap that seems
/// to have missed is most likely to be tried again.
///
/// The letter goes by `Outbox`, which the app's repository sends through,
/// on the account `ShareMirror` handed over. Out of the extension's view
/// controller, as `ComposeActions` is out of the composer's, so the suite
/// can run it against `ScriptedSubmission`.
@MainActor
final class ShareSheet {

    let shared: ShareMirror.Shared
    private var actions: ComposeActions!
    /// Cancel, rather than a letter that went, is what put the sheet away.
    private var cancelled = false
    /// The letter as the share began it, before he touched it.
    private var started = Draft()

    /// `finish` ends the share once the letter has gone and `cancel` once
    /// Cancel has put it away: the extension's `completeRequest` and
    /// `cancelRequest`. Each is called at most once, and never both.
    /// `noteSent` hears who a letter that went was addressed to
    /// (`ShareMirror.noteSent`). `readFile` gives a staged file's bytes
    /// back at Send.
    init(shared: ShareMirror.Shared,
         transport: @escaping MailTransportFactory,
         readFile: @escaping (DraftAttachment) throws -> Data = ShareSheet.readStaged,
         noteSent: @escaping ([String]) -> Void,
         finish: @escaping () -> Void,
         cancel: @escaping () -> Void,
         showError: @escaping (MailError) -> Void,
         draw: @escaping (ComposeActions.Look) -> Void,
         background: BackgroundTime) {
        self.shared = shared
        let account = shared.account
        actions = ComposeActions(
            sendLetter: { draft, progress in
                try await Outbox.send(
                    draft, from: account, password: shared.password,
                    through: SMTPClient(account: account, transport: transport),
                    threadHeaders: nil,
                    attachments: {
                        try draft.attachments.map { ($0.filename, $0.mimeType, try readFile($0)) }
                    },
                    htmlBody: ShareLetter.html(for: draft, account: account),
                    inlineImages: SignatureImages.parts(of: shared.signatureImages),
                    progress: progress)
                // Only after the server took it, as the app's book counts
                // only letters that went.
                noteSent(Outbox.recipients(of: draft).map(MailFormat.bareAddress))
            },
            // Never asked: Cancel puts a share away without keeping a
            // draft, and a share has no copy in Drafts to tidy.
            saveDraft: { _ in },
            deleteDraft: { _ in },
            dismiss: { [weak self] in
                guard let self else { return }
                self.cancelled ? cancel() : finish()
            },
            showError: showError,
            draw: draw,
            background: background)
    }

    /// The letter a share starts as, signed as the app signs a new one.
    func letter(from items: [SharedItem]) -> Draft {
        started = ShareLetter.draft(from: items, signature: shared.account.signature)
        return started
    }

    var isSending: Bool { actions.isSending }

    /// Send tapped. Nil when the tap sends nothing.
    @discardableResult
    func send(_ letter: @escaping () -> Draft) -> Task<Void, Never>? {
        actions.send(letter, then: nil)
    }

    /// Cancel tapped: the share is put away, and nothing is sent or kept.
    /// Nil, and nothing done, once a letter is on its way or has gone.
    @discardableResult
    func cancel() -> Task<Void, Never>? {
        guard !actions.isSending else { return nil }
        cancelled = true
        return actions.deleteAndClose(nil, then: nil)
    }

    /// Whether Cancel asks before putting the share away: when `letter`,
    /// the sheet as it stands, has anything of his in it that the share did
    /// not begin with. Words above his signature, an address, a subject of
    /// his own.
    ///
    /// Measured against the letter the share began as, and never against
    /// one handed to Send. A letter that did not go is still his, and
    /// still unsent, which is when throwing it away unasked would cost the
    /// most.
    func asksBeforeCancelling(_ letter: Draft) -> Bool {
        let signature = shared.account.signature
        return AppleMailHTML.layout(of: letter.body, signature: signature).typed
                != AppleMailHTML.layout(of: started.body, signature: signature).typed
            || letter.subject != started.subject
            || Outbox.recipients(of: letter) != Outbox.recipients(of: started)
    }

    /// What the address field he is in offers, from the app's own book as
    /// it was mirrored: nothing once what he has typed is a whole address,
    /// his most used when he has typed nothing, which is what makes his own
    /// second address one tap.
    func suggestions(for field: String) -> [KnownRecipient] {
        let typed = MailFormat.currentRecipientToken(in: field)
        guard !typed.contains("@") else { return [] }
        return RecipientBook.rank(shared.recipients, matching: typed,
                                  limit: RecipientBook.suggestionLimit)
    }

    /// A file staged on this device by `AttachmentStore.write`, read back.
    nonisolated static func readStaged(_ attachment: DraftAttachment) throws -> Data {
        guard case let .localFile(url) = attachment.source else {
            throw MailError.attachmentFailed
        }
        return try Data(contentsOf: url)
    }
}
