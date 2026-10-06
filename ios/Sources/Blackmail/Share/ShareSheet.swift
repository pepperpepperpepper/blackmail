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
/// The letter goes by `Submission`, which the app's repository sends through,
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
    /// (`ShareMirror.noteSent`). `openFile` says where a staged file is
    /// read from at Send, as it goes (`ShareSheet.staged`). `memory` says
    /// what the extension has left (`SharedPhoto.memory`), for the log at
    /// each step of Send.
    init(shared: ShareMirror.Shared,
         transport: @escaping MailTransportFactory,
         openFile: @escaping (DraftAttachment) throws -> LetterSource = ShareSheet.staged,
         memory: @escaping @Sendable () -> SharedPhoto.Memory = { SharedPhoto.Memory() },
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
                // The letter is made from the staged files as it goes, never
                // whole (B-070): what Send holds does not grow with them. So
                // the log says what was left once the files were read, in
                // the rehearsal before the server is reached; once the
                // envelope was taken, before DATA; and once it had gone,
                // with the least since the extension started and the least
                // at any step of its progress while it went, which is what
                // says whether that held on the iPad.
                let going = LowWater(memory)
                try await Submission.send(
                    draft, from: account, password: shared.password,
                    through: SMTPClient(account: account, transport: transport),
                    threadHeaders: nil,
                    attachments: {
                        try draft.attachments.map { ($0.filename, $0.mimeType, try openFile($0)) }
                    },
                    htmlBody: ShareLetter.html(for: draft, account: account),
                    inlineImages: SignatureImages.parts(of: shared.signatureImages),
                    rehearsed: { rehearsal in
                        Diagnostics.log(.note, SharedPhoto.sendNote(
                            "files read", files: rehearsal.files.map { Int64($0.bytes) },
                            memory: memory()))
                    },
                    beforeData: {
                        Diagnostics.log(.note, SharedPhoto.sendNote("built", memory: memory()))
                    },
                    progress: { written, total in
                        going.note()
                        progress(written, total)
                    })
                Diagnostics.log(.note, SharedPhoto.sendNote("sent", memory: memory(),
                                                            whileGoing: going.least))
                // Only after the server took it, as the app's book counts
                // only letters that went.
                noteSent(Submission.recipients(of: draft).map(MailFormat.bareAddress))
            },
            // Never asked: Cancel puts a share away without keeping a
            // draft, and a share has no copy in Drafts to tidy.
            saveDraft: { _ in },
            deleteDraft: { _, _ in },
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
        return actions.deleteAndClose(nil, letter: nil, then: nil)
    }

    /// Whether Cancel asks before putting the share away: when `letter`,
    /// the sheet as it stands, has anything of his in it that the share did
    /// not begin with. Words above his signature, an address, a subject of
    /// his own, or a file taken off (B-069). As the share began it, it goes
    /// without a word, as Mail's does.
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
            || Submission.recipients(of: letter) != Submission.recipients(of: started)
            || !ComposeForm.sameFiles(letter, started)
    }

    /// What the address field he is in offers after `event`, from the
    /// app's own book as it was mirrored, as the app's composer offers it
    /// (`ComposeForm.suggestions`): matches only while he types, nothing
    /// as he goes into a field or with nothing typed (B-073), nothing once
    /// what he has typed holds an "@", nothing already in the field, and
    /// nothing after a pick until he types again.
    func suggestions(for field: String,
                     after event: ComposeForm.FieldEvent = .typed) -> [KnownRecipient] {
        ComposeForm.suggestions(shared.recipients, field: field, after: event)
    }

    /// A file staged on this device by `AttachmentStore`, to be read from
    /// the disk as the letter goes, at the size it was staged at
    /// (`ShareItems.Staging`). A share has nothing but staged files.
    nonisolated static func staged(_ attachment: DraftAttachment) throws -> LetterSource {
        guard case let .localFile(url) = attachment.source else {
            throw MailError.attachmentFailed
        }
        return .disk(url, attachedSize: attachment.size)
    }
}

extension ShareSheet {

    /// A sheet whose files' bytes are handed over in memory by `readFile`,
    /// rather than read from the disk as the letter goes: for a test.
    convenience init(shared: ShareMirror.Shared,
                     transport: @escaping MailTransportFactory,
                     readFile: @escaping (DraftAttachment) throws -> Data,
                     memory: @escaping @Sendable () -> SharedPhoto.Memory = { SharedPhoto.Memory() },
                     noteSent: @escaping ([String]) -> Void,
                     finish: @escaping () -> Void,
                     cancel: @escaping () -> Void,
                     showError: @escaping (MailError) -> Void,
                     draw: @escaping (ComposeActions.Look) -> Void,
                     background: BackgroundTime) {
        self.init(shared: shared, transport: transport,
                  openFile: { .bytes(try readFile($0)) },
                  memory: memory, noteSent: noteSent, finish: finish, cancel: cancel,
                  showError: showError, draw: draw, background: background)
    }
}

/// The least memory there was at any report of a letter's progress: what
/// the share extension had left while the letter went (B-070). Reports come
/// from whatever thread the write resumes on, so it is guarded.
final class LowWater: @unchecked Sendable {
    private let memory: @Sendable () -> SharedPhoto.Memory
    private let lock = NSLock()
    private var lowest: Int64?

    init(_ memory: @escaping @Sendable () -> SharedPhoto.Memory) {
        self.memory = memory
    }

    /// Reads the memory left now.
    func note() {
        guard let available = memory().available else { return }
        lock.lock()
        lowest = min(lowest ?? available, available)
        lock.unlock()
    }

    /// The least read, nil when none was.
    var least: Int64? {
        lock.lock()
        defer { lock.unlock() }
        return lowest
    }
}
