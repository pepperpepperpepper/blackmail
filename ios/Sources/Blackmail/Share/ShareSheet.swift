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
///
/// A share with no files that cannot reach the server waits in the app's
/// Outbox, as Mail's share sheet leaves a letter in Mail's (B-153): the
/// sheet closes with the sent sound, and the letter goes when Blackmail is
/// next opened or comes back to the front. Handed over through the shared
/// Keychain group (`ShareMirror.wait`), since nothing else is shared with
/// the app. A share with files is refused as before, with the reason, the
/// sheet staying: its files are in the extension's own temporary
/// directory, which the app cannot read. So is every share from the day
/// the app stops opening (`waits(at:appStops:calendar:)`).
@MainActor
final class ShareSheet {

    let shared: ShareMirror.Shared
    /// The share's own, made once with the sheet: the name its letter waits
    /// under for the app, and its key in the app's Outbox, so however often
    /// Send is tapped it is one letter there (B-153).
    let key = UUID().uuidString.lowercased()
    /// The Message-ID every attempt at the letter goes under, from the sheet
    /// and from the Outbox, so one cut off after its DATA can be looked for
    /// in Sent Mail before it goes again (B-153).
    let messageID: String
    private var actions: ComposeActions!
    /// Cancel, rather than a letter that went, is what put the sheet away.
    private var cancelled = false
    /// The letter as the share began it, before he touched it.
    private var started = Draft()
    /// Send has been tapped, whether or not the letter went.
    private var sendTapped = false

    /// `finish` ends the share once the letter has gone and `cancel` once
    /// Cancel has put it away: the extension's `completeRequest` and
    /// `cancelRequest`. Each is called at most once, and never both.
    /// `sent` is told once, just before `finish`, as Mail's share sheet
    /// plays its sent sound as it goes (B-100); never before `cancel`, nor
    /// for a letter that did not go.
    /// `noteSent` hears who a letter that went was addressed to
    /// (`ShareMirror.noteSent`). `openFile` says where a staged file is
    /// read from at Send, as it goes (`ShareSheet.staged`). `memory` says
    /// what the extension has left (`SharedPhoto.memory`), for the log at
    /// each step of Send.
    ///
    /// `wait` leaves a letter that could not go for the app's Outbox
    /// (`ShareMirror.wait`, B-153), and says whether it is there; one that
    /// says no leaves the share refused, as one that leaves nothing does.
    /// `appStops` says when the app stops opening (`AppExpiry`), nil for
    /// never, in `calendar`, asked only once a letter could not go, so a
    /// share that goes reads no profile; `now` is the clock the letter is
    /// dated by and the day is read from.
    init(shared: ShareMirror.Shared,
         transport: @escaping MailTransportFactory,
         openFile: @escaping (DraftAttachment) throws -> LetterSource = ShareSheet.staged,
         memory: @escaping @Sendable () -> SharedPhoto.Memory = { SharedPhoto.Memory() },
         noteSent: @escaping ([String]) -> Void,
         finish: @escaping () -> Void,
         cancel: @escaping () -> Void,
         sent: @escaping () -> Void = {},
         showError: @escaping (MailError) -> Void,
         draw: @escaping (ComposeActions.Look) -> Void,
         background: BackgroundTime,
         wait: @escaping (ShareMirror.WaitingShare) -> Bool = { _ in false },
         appStops: @escaping () -> Date? = { nil },
         calendar: Calendar = .current,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.shared = shared
        let account = shared.account
        let messageID = RFC5322Builder.freshMessageID(for: account.address)
        self.messageID = messageID
        let key = self.key
        actions = ComposeActions(
            sendLetter: { draft, progress in
                // His Send: the letter's Date at this attempt, and at every
                // attempt from the Outbox should it wait there.
                let sentAt = now()
                let attempt = DataWent()
                // The letter is made from the staged files as it goes, never
                // whole (B-070): what Send holds does not grow with them. So
                // the log says what was left once the files were read, in
                // the rehearsal before the server is reached; once the
                // envelope was taken, before DATA; and once it had gone,
                // with the least since the extension started and the least
                // at any step of its progress while it went, which is what
                // says whether that held on the iPad.
                let going = LowWater(memory)
                // His photos go in the letter, under his words, and are read
                // from the disk as they go, as the files are (B-109): the
                // markup and the parts are made from one list.
                let letter = ShareLetter.letter(
                    for: draft, account: account,
                    reserving: SignatureImages.contentIDs(of: shared.signatureImages))
                do {
                    try await Submission.send(
                        draft, from: account, password: shared.password,
                        through: SMTPClient(account: account, transport: transport),
                        threadHeaders: nil,
                        attachments: {
                            try letter.bodyPictures.map {
                                ($0.file.filename, $0.file.mimeType, try openFile($0.file),
                                 .inBody(contentID: $0.contentID))
                            } + letter.files.map {
                                ($0.filename, $0.mimeType, try openFile($0), .file)
                            }
                        },
                        htmlBody: letter.html,
                        inlineImages: SignatureImages.parts(of: shared.signatureImages),
                        messageID: messageID,
                        rehearsed: { rehearsal in
                            Diagnostics.log(.note, SharedPhoto.sendNote(
                                "files read", files: rehearsal.files.map { Int64($0.bytes) },
                                memory: memory()))
                        },
                        beforeData: {
                            attempt.went(at: now())
                            Diagnostics.log(.note, SharedPhoto.sendNote("built", memory: memory()))
                        },
                        progress: { written, total in
                            going.note()
                            progress(written, total)
                        },
                        date: sentAt)
                } catch {
                    // No connection: a share with no files waits in the
                    // app's Outbox, the sheet closing as it does when the
                    // letter goes (B-153). Anything else, and a share with
                    // files, stays in the sheet with the reason, as before.
                    guard Outbox.waits(after: error), draft.attachments.isEmpty,
                          Self.waits(at: sentAt, appStops: appStops(), calendar: calendar),
                          wait(ShareMirror.WaitingShare(key: key, account: account, draft: draft,
                                                        messageID: messageID, sentAt: sentAt,
                                                        cutOff: attempt.at))
                    else { throw error }
                    Diagnostics.log(.note, "SHARE-WAITING error=\(error)"
                                    + (attempt.at == nil ? "" : " after-data"))
                    throw Outbox.Waiting()
                }
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
            background: background,
            sent: sent)
    }

    /// Whether a share with no files that cannot go at `now` waits in the
    /// app's Outbox (B-153): always, but from the day the app stops opening,
    /// `appStops`, in `calendar`. From that day it is refused as it was
    /// before: the letter would wait for an app that may not open again
    /// before it goes, and the sheet has said it was as good as sent.
    nonisolated static func waits(at now: Date, appStops: Date?, calendar: Calendar) -> Bool {
        guard let appStops else { return true }
        return now < calendar.startOfDay(for: appStops)
    }

    /// The app that holds the share extension whose bundle is `appex`
    /// (`Blackmail.app/PlugIns/BlackmailShare.appex`), two folders up; nil
    /// for a bundle that is in no app's PlugIns. Where the extension reads
    /// when the app stops opening (`AppExpiry.containingApp`, B-153).
    nonisolated static func containingApp(of appex: URL) -> URL? {
        let plugIns = appex.deletingLastPathComponent()
        let app = plugIns.deletingLastPathComponent()
        guard appex.pathExtension == "appex", plugIns.lastPathComponent == "PlugIns",
              app.pathExtension == "app" else { return nil }
        return app
    }

    /// The letter a share starts as, signed as the app signs a new one.
    func letter(from items: [SharedItem]) -> Draft {
        started = ShareLetter.draft(from: items, signature: shared.account.signature)
        return started
    }

    /// The video whose title is asked of YouTube for the subject
    /// (`VideoTitle`, B-126): the first link in `items` to a YouTube video,
    /// and only while nothing has given the letter a subject, so a link
    /// that came with nothing naming it but its own address. Nil for every
    /// other share: Safari's page has its title, and nothing is asked.
    func videoToName(in items: [SharedItem]) -> URL? {
        guard started.subject.isEmpty else { return nil }
        for case let .link(url, _) in items where VideoTitle.id(of: url) != nil {
            return url
        }
        return nil
    }

    /// What YouTube's title makes of Subject once it has come: `subject`,
    /// when Subject is still as the share began it, empty, he has typed
    /// nothing in it (`typed`), and neither Send nor Cancel has been
    /// tapped. Then it is the share's own subject, and Cancel asks nothing
    /// about it. Nil otherwise, and Subject is left as it is.
    func named(_ subject: String?, now: String, typed: Bool) -> String? {
        guard let subject, !subject.isEmpty, !typed, !cancelled, !sendTapped,
              started.subject.isEmpty, now.isEmpty else { return nil }
        started.subject = subject
        return subject
    }

    var isSending: Bool { actions.isSending }

    /// Send tapped. Nil when the tap sends nothing.
    @discardableResult
    func send(_ letter: @escaping () -> Draft) -> Task<Void, Never>? {
        sendTapped = true
        return actions.send(letter, then: nil)
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

    /// The same, for the sheet's fields of bubbles (B-076), as the app's
    /// composer asks it (`ComposeForm.suggestions(_:in:after:)`).
    func suggestions(in field: RecipientBubbles,
                     after event: ComposeForm.FieldEvent = .typed) -> [KnownRecipient] {
        ComposeForm.suggestions(shared.recipients, in: field, after: event)
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
                     sent: @escaping () -> Void = {},
                     showError: @escaping (MailError) -> Void,
                     draw: @escaping (ComposeActions.Look) -> Void,
                     background: BackgroundTime,
                     wait: @escaping (ShareMirror.WaitingShare) -> Bool = { _ in false },
                     appStops: @escaping () -> Date? = { nil },
                     calendar: Calendar = .current,
                     now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(shared: shared, transport: transport,
                  openFile: { .bytes(try readFile($0)) },
                  memory: memory, noteSent: noteSent, finish: finish, cancel: cancel,
                  sent: sent, showError: showError, draw: draw, background: background,
                  wait: wait, appStops: appStops, calendar: calendar, now: now)
    }
}

/// When an attempt at a share sent its DATA (B-153), from whatever thread
/// the send runs on: a letter cut off after it may have reached Gmail, and
/// the app asks Sent Mail before it sends it again.
final class DataWent: @unchecked Sendable {
    private let lock = NSLock()
    private var time: Date?

    func went(at time: Date) {
        lock.lock()
        self.time = time
        lock.unlock()
    }

    var at: Date? {
        lock.lock()
        defer { lock.unlock() }
        return time
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
