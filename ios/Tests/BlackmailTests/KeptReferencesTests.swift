import XCTest
@testable import Blackmail

/// What a letter kept on the iPad names on the server (B-051, B-052): the
/// copy in Drafts it was reopened from, a forward's or a reopened draft's
/// files, and its quote's pictures. Each is named by folder and UID, and
/// by Gmail's id for its letter (X-GM-MSGID), kept with the letter in
/// `Local Drafts/`; nothing is removed, fetched into the letter or sent by
/// folder and UID alone unless the server has shown in this launch that the
/// UID holds that letter.
///
/// A later launch is a new repository, over the same kept copy, and a new
/// `LocalDrafts` over the same directory. Another mailbox under the same
/// address, as a password saved in Settings can open (B-033), is the same
/// mailbox renumbered under the UIDVALIDITY it had, so that a UID the
/// letter names holds another letter.
///
/// These run the composer's own wiring (`ComposeActions(letter:…)`), the
/// shipping `LocalDrafts` over a store in a directory of the test's own, the
/// shipping repository over the scripted IMAP server, and a scripted
/// submission server per connection. The line can be taken down: then every
/// connection is refused, as a connect with no route is.
@MainActor
final class KeptReferencesTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "KeptReferencesTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var line: ReferenceLine!
    private var submissions: ReferenceSubmissions!
    /// The repository's clock, which only a test moves, so a stalled host
    /// cannot add a probe to the traffic a test pins.
    private var clock: ManualClock!
    /// When each letter is kept: a second later every time.
    private var keptClock: ManualClock!
    private var root: URL!
    private var background = FakeBackground()
    private var passTime = FakeBackground()
    private var pauses = Held()
    private var dismissals = 0
    private var errors: [MailError] = []

    private let plansBytes = Data((0..<3000).map { UInt8(truncatingIfNeeded: $0 &* 13 &+ 1) })
    private let resultsBytes = Data((0..<3000).map { UInt8(truncatingIfNeeded: $0 &* 17 &+ 5) })

    override func setUp() async throws {
        try await super.setUp()
        server = ScriptedIMAPServer()
        line = ReferenceLine()
        submissions = ReferenceSubmissions()
        clock = ManualClock()
        keptClock = ManualClock()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("KeptReferencesTests-\(UUID().uuidString)", isDirectory: true)
        background = FakeBackground()
        passTime = FakeBackground()
        pauses = Held()
        dismissals = 0
        errors = []
        Diagnostics.clear()
    }

    override func tearDown() async throws {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        if let root { try? FileManager.default.removeItem(at: root) }
        for outcome in ["ok", "fail"] {
            let transcript = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
            try? FileManager.default.removeItem(atPath: transcript)
        }
        pauses.release()
        server = nil
        book = nil
        line = nil
        submissions = nil
        clock = nil
        keptClock = nil
        root = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// The app's repository: made again, it is the next launch's, over the
    /// copy of his mail the last one kept.
    private func makeRepository() -> IMAPMailRepository {
        let imap = server.transportFactory
        let line = self.line!
        let submissions = self.submissions!
        let clock = self.clock!
        return IMAPMailRepository(
            account: server.account, password: server.password,
            transport: { host, port in
                guard line.isUp else {
                    return port == 465 ? ScriptedSubmission(failsToOpen: true) : imap(host, 1)
                }
                return port == 465 ? submissions.next() : imap(host, port)
            },
            recipients: book,
            now: { clock.now() },
            signatureImages: { [] },
            shelf: keptShelf(for: server.account))
    }

    /// The app's `LocalDrafts` over this test's directory. A second one
    /// over the same directory is the app launched again.
    private func makeKept() -> LocalDrafts {
        let clock = keptClock!
        let store = LocalDraftStore(root: root, now: {
            clock.advance(by: 1)
            return clock.now()
        })
        return LocalDrafts(store: store, account: server.username, background: passTime.time)
    }

    /// The composer's actions for letter `key`, wired as the composer
    /// wires them.
    private func makeActions(_ key: String, kept: LocalDrafts,
                             repository: MailRepository) -> ComposeActions {
        kept.opened(key)
        return ComposeActions(letter: key, repository: repository, kept: kept,
                              dismiss: { [unowned self] in dismissals += 1 },
                              showError: { [unowned self] in errors.append($0) },
                              draw: { _ in },
                              background: background.time,
                              wait: { [pauses] _ in try await pauses.wait() })
    }

    private func letter(_ subject: String) -> Draft {
        var draft = Draft()
        draft.to = ["carlo@example.org"]
        draft.subject = subject
        draft.body = "Lunch at one?"
        return draft
    }

    /// Save Draft as the line goes, every connection open dying with it:
    /// the letter kept as `key`, its APPEND written into the dead socket,
    /// so the next upload looks for it in Drafts first (B-051). Then the
    /// line comes back.
    private func savedOffline(_ draft: Draft, as key: String, kept: LocalDrafts,
                              repository: IMAPMailRepository) async {
        line.isUp = false
        await server.resetConnections()
        await makeActions(key, kept: kept, repository: repository)
            .saveAndClose({ draft }, then: nil)?.value
        line.isUp = true
    }

    /// Send with the line down: the letter waits in the Outbox as `key`.
    private func sentOffline(_ draft: Draft, as key: String, kept: LocalDrafts,
                             repository: IMAPMailRepository) async {
        line.isUp = false
        await server.resetConnections()
        await makeActions(key, kept: kept, repository: repository).send({ draft }, then: nil)?.value
        line.isUp = true
    }

    private func uid(_ id: String) -> UInt32 {
        UInt32(id.split(separator: "/").last ?? "") ?? 0
    }

    /// The UIDs of the letters called `subject` in Drafts.
    private func copies(_ subject: String) -> [UInt32] {
        server.uids(in: Server.drafts).filter {
            server.letter(uid: $0, in: Server.drafts)?.subject == subject
        }
    }

    private func notes(_ prefix: String) -> [String] {
        Diagnostics.entries.filter { $0.direction == .note }.map(\.text)
            .filter { $0.hasPrefix(prefix) }
    }

    /// Sam's "Plans" with Plans.pdf, the newest letter, in `mailboxes`.
    @discardableResult
    private func deliverPlans(to mailboxes: [String] = [Server.inbox, Server.allMail])
        -> [String: UInt32] {
        server.deliver(Server.Letter(
            from: Server.sam, to: [Server.owner], subject: "Plans", date: Server.newestDate,
            text: "The plans.\r\n", messageID: "<plans@example.com>",
            files: [Server.File(name: "Plans.pdf", type: "APPLICATION", subtype: "PDF",
                                bytes: plansBytes)]), to: mailboxes)
    }

    /// Another letter, newer, whose file is at the same section as the
    /// Plans' file.
    private func deliverResults() {
        server.deliver(Server.Letter(
            from: Server.jane, to: [Server.owner], subject: "Medical results",
            date: Server.newestDate.addingTimeInterval(60), text: "The results.\r\n",
            messageID: "<results@example.com>",
            files: [Server.File(name: "Results.pdf", type: "APPLICATION", subtype: "PDF",
                                bytes: resultsBytes)]), to: [Server.inbox, Server.allMail])
    }

    /// The Inbox renumbered under the UIDVALIDITY it had, so that `uid`
    /// holds its newest letter: another mailbox under the same numbers.
    private func renumberInbox(soThat uid: UInt32) {
        let count = UInt32(server.uids(in: Server.inbox).count)
        server.renumber(Server.inbox, validity: server.uidValidity(of: Server.inbox),
                        firstUID: uid - 2 * (count - 1))
    }

    /// Drafts renumbered under the UIDVALIDITY it had, so that `uid` holds
    /// the draft called `subject`: another mailbox under the same numbers.
    private func renumberDrafts(soThat uid: UInt32, holds subject: String) throws {
        let at = try XCTUnwrap(server.uids(in: Server.drafts).firstIndex {
            server.letter(uid: $0, in: Server.drafts)?.subject == subject
        })
        server.renumber(Server.drafts, validity: server.uidValidity(of: Server.drafts),
                        firstUID: uid - 2 * UInt32(at))
        XCTAssertEqual(copies(subject), [uid])
    }

    /// Save Draft of `draft` as `key` whose APPEND reaches Gmail and whose
    /// answer is lost with the line, then the next pass, which finds the
    /// copy by its version's Message-ID and takes it as the letter's own
    /// rather than send it again (B-051). Returns the id the pass left in
    /// `landed`: a copy this launch had no APPENDUID for.
    private func landedAfterACutOff(_ draft: Draft, as key: String, kept: LocalDrafts,
                                    repository: IMAPMailRepository) async throws -> String {
        server.holdReplies(to: "APPEND")
        let saving = try XCTUnwrap(makeActions(key, kept: kept, repository: repository)
            .saveAndClose({ draft }, then: nil))
        try await until { server.log.contains { $0.verb == "APPEND" } }
        await server.resetConnections()
        await saving.value
        await server.releaseReplies(to: "APPEND")
        XCTAssertEqual(kept.waiting.map(\.key), [key], "the iPad never heard")

        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        server.clearLog()
        await kept.uploadWaiting(to: repository)?.value
        XCTAssertEqual(server.log.filter { $0.verb == "APPEND" }, [], "found, not sent again")
        return try XCTUnwrap(kept.landed[key])
    }

    /// A forward of the Plans, made as the app makes one: from its row,
    /// the letter opened and forwarded.
    private func forwardOfPlans(_ repository: IMAPMailRepository) async throws
        -> (draft: Draft, row: MessageSummary) {
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let row = try XCTUnwrap(rows.first { $0.subject == "Plans" })
        var draft = Draft.forwarding(try await repository.open(row))
        draft.to = ["carlo@example.org"]
        return (draft, row)
    }

    private let roof = Data((0..<1500).map { UInt8(truncatingIfNeeded: $0 &* 5 &+ 11) })
    private let scan = Data((0..<1500).map { UInt8(truncatingIfNeeded: $0 &* 23 &+ 2) })

    /// A letter whose words show a picture by `cid:`, the picture its only
    /// file, at the same section in every such letter.
    private func pictured(_ subject: String, _ id: String, _ bytes: Data,
                          at date: Date) -> Server.Letter {
        Server.Letter(from: Server.sam, to: [Server.owner], subject: subject, date: date,
                      html: "<p>\(subject).</p><img src=\"cid:\(id)\">",
                      messageID: "<\(id)@example.com>",
                      files: [Server.File(name: "\(id).jpg", type: "IMAGE", subtype: "JPEG",
                                          bytes: bytes, contentID: id)])
    }

    private func carries(_ letter: String?, _ bytes: Data) -> Bool {
        letter?.contains(String(bytes.base64EncodedString().prefix(60))) == true
    }

    // MARK: - The copy a draft was reopened from

    /// A draft reopened from its row and saved as the line went names its
    /// copy by Gmail's id. In a later launch, with Drafts renumbered under
    /// the same UIDVALIDITY so that the copy's UID holds another draft, the
    /// upload removes nothing: the look for the cut-off upload and the new
    /// version go, the other draft stays, and the log says where and why.
    /// Before, the upload's UID STORE and UID EXPUNGE went onto the other
    /// draft.
    func testASupersededCopyThatIsAnotherDraftIsNotExpunged() async throws {
        let first = makeRepository()
        let rows = try await first.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        let row = try XCTUnwrap(rows.first { $0.subject == "Unfinished 1" })
        var reopened = try await first.reopen(row)
        XCTAssertEqual(reopened.savedLetter, row.gmailMessageID)
        reopened.subject = "Finished"
        await savedOffline(reopened, as: "letter-1", kept: makeKept(), repository: first)

        server.renumber(Server.drafts, validity: server.uidValidity(of: Server.drafts),
                        firstUID: uid(row.id))
        XCTAssertEqual(copies("Unfinished 2"), [uid(row.id)], "its UID holds another draft now")

        let repository = makeRepository()
        let kept = makeKept()
        XCTAssertEqual(kept.store.letter("letter-1")?.draft.savedLetter, row.gmailMessageID,
                       "kept across the launch")
        _ = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        server.clearLog()
        await kept.uploadWaiting(to: repository)?.value

        XCTAssertEqual(server.log.map(\.verb), ["UID SEARCH", "APPEND"],
                       "nothing sent onto the other draft")
        XCTAssertEqual(copies("Finished").count, 1, "the new version went up")
        XCTAssertEqual(copies("Unfinished 2"), [uid(row.id)])
        XCTAssertEqual(copies("Unfinished 1").count, 1, "its own copy is left, not guessed at")
        XCTAssertEqual(kept.store.letters().count, 0)
        XCTAssertEqual(notes("DRAFT-SUPERSEDED"),
                       ["DRAFT-SUPERSEDED folder=\(Server.drafts) not-that-letter left"])
    }

    /// The same with Drafts not listed in the later launch: the copy is
    /// asked about, one FETCH of its Gmail id after the APPEND, in the hold
    /// of the look's SELECT, and the answer, another draft, removes
    /// nothing.
    func testASupersededCopyNotYetListedIsAskedAboutAndNotExpunged() async throws {
        let first = makeRepository()
        let rows = try await first.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        let row = try XCTUnwrap(rows.first { $0.subject == "Unfinished 1" })
        var reopened = try await first.reopen(row)
        reopened.subject = "Finished"
        await savedOffline(reopened, as: "letter-1", kept: makeKept(), repository: first)
        server.renumber(Server.drafts, validity: server.uidValidity(of: Server.drafts),
                        firstUID: uid(row.id))

        let repository = makeRepository()
        let kept = makeKept()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        server.clearLog()
        await kept.uploadWaiting(to: repository)?.value

        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH", "APPEND", "UID FETCH"])
        XCTAssertEqual(server.log.last?.command, "UID FETCH \(uid(row.id)) (UID X-GM-MSGID)")
        XCTAssertEqual(copies("Unfinished 2"), [uid(row.id)])
        XCTAssertEqual(copies("Finished").count, 1)
    }

    /// No renumbering: in a later launch the copy is still the draft's, and
    /// goes as it always did once Drafts has been listed, a UID STORE and a
    /// UID EXPUNGE after the APPEND; with Drafts not yet listed it is asked
    /// about once first.
    func testTheSameCopyInALaterLaunchIsRemovedAskedAboutOnlyIfUnlisted() async throws {
        let first = makeRepository()
        let rows = try await first.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        for (n, row) in rows.enumerated() {
            var reopened = try await first.reopen(row)
            reopened.subject = "Finished \(n)"
            await savedOffline(reopened, as: "letter-\(n)", kept: makeKept(), repository: first)
        }

        var repository = makeRepository()
        var kept = makeKept()
        _ = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        kept.opened("letter-1")
        server.clearLog()
        await kept.uploadWaiting(to: repository)?.value
        XCTAssertEqual(server.log.map(\.verb), ["UID SEARCH", "APPEND", "UID STORE", "UID EXPUNGE"],
                       "listed: what the upload always sent")
        XCTAssertFalse(server.uids(in: Server.drafts).contains(uid(rows[0].id)))

        repository = makeRepository()
        kept = makeKept()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        server.clearLog()
        await kept.uploadWaiting(to: repository)?.value
        XCTAssertEqual(server.log.map(\.verb),
                       ["SELECT", "UID SEARCH", "APPEND", "UID FETCH", "UID STORE", "UID EXPUNGE"])
        XCTAssertEqual(server.log.dropFirst(3).first?.command, "UID FETCH \(uid(rows[1].id)) (UID X-GM-MSGID)")
        XCTAssertFalse(server.uids(in: Server.drafts).contains(uid(rows[1].id)))
        XCTAssertEqual(copies("Finished 0").count + copies("Finished 1").count, 2)
    }

    /// A copy this launch put in Drafts, reopened from the row its upload
    /// drew, which names no letter: Gmail's id for it is asked in the
    /// letter's own FETCH, at no round trip more, and the draft made from
    /// it names its copy by it. Kept offline and taken up in a later launch
    /// with Drafts renumbered, it removes no other draft.
    func testACopyThisLaunchUploadedIsNamedWhenReopened() async throws {
        let first = makeRepository()
        let kept = makeKept()
        _ = try await first.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        kept.keep(letter("Sunday"), as: "letter-1", unfinished: false)
        await kept.uploadWaiting(to: first)?.value
        let landed = try XCTUnwrap(kept.landed["letter-1"])

        server.clearLog()
        var reopened = try await first.loadDraft(id: landed, mailboxID: Server.drafts)
        XCTAssertEqual(server.log.filter(\.isUIDCommand).map(\.command),
                       ["UID FETCH \(uid(landed)) (UID X-GM-MSGID BODY.PEEK[])"])
        XCTAssertEqual(reopened.savedID, landed)
        XCTAssertEqual(reopened.savedLetter, server.gmailMessageID(uid: uid(landed),
                                                                  in: Server.drafts))
        reopened.subject = "Monday"
        await savedOffline(reopened, as: "letter-2", kept: kept, repository: first)

        server.renumber(Server.drafts, validity: server.uidValidity(of: Server.drafts),
                        firstUID: uid(landed) - 2)
        XCTAssertEqual(copies("Unfinished 1"), [uid(landed)], "its UID holds another draft now")

        let repository = makeRepository()
        _ = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        server.clearLog()
        await makeKept().uploadWaiting(to: repository)?.value
        XCTAssertEqual(server.log.map(\.verb), ["UID SEARCH", "APPEND"])
        XCTAssertEqual(copies("Monday").count, 1)
        XCTAssertEqual(copies("Sunday").count, 1)
        XCTAssertEqual(copies("Unfinished 1").count + copies("Unfinished 2").count, 2)
    }

    /// A copy found in Drafts by its version's Message-ID after an upload
    /// cut off once Gmail had it, and taken by the next pass as the
    /// letter's own, is this launch's own as one its APPEND named is:
    /// reopened from the row the pass draws, its Gmail id is asked in its
    /// FETCH, and the draft names its copy by it. Kept offline and taken up
    /// in a later launch with Drafts renumbered, it removes no other draft.
    /// Before, it was fetched plainly and named nothing, and the upload
    /// expunged the draft now under its UID.
    func testACopyFoundByItsMessageIDIsNamedWhenReopened() async throws {
        let first = makeRepository()
        let kept = makeKept()
        _ = try await first.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let landed = try await landedAfterACutOff(letter("Sunday"), as: "letter-1", kept: kept,
                                                  repository: first)

        server.clearLog()
        var reopened = try await first.loadDraft(id: landed, mailboxID: Server.drafts)
        XCTAssertEqual(server.log.filter(\.isUIDCommand).map(\.command),
                       ["UID FETCH \(uid(landed)) (UID X-GM-MSGID BODY.PEEK[])"])
        XCTAssertEqual(reopened.savedLetter, server.gmailMessageID(uid: uid(landed),
                                                                  in: Server.drafts))
        reopened.subject = "Monday"
        await savedOffline(reopened, as: "letter-2", kept: kept, repository: first)
        try renumberDrafts(soThat: uid(landed), holds: "Unfinished 1")

        let repository = makeRepository()
        _ = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        server.clearLog()
        await makeKept().uploadWaiting(to: repository)?.value
        XCTAssertFalse(server.log.contains { $0.verb == "UID STORE" || $0.verb == "UID EXPUNGE" },
                       "nothing sent onto the other draft")
        XCTAssertEqual(copies("Unfinished 1"), [uid(landed)])
        XCTAssertEqual(copies("Monday").count, 1)
        XCTAssertEqual(copies("Sunday").count, 1)
    }

    /// The same copy carrying a forward's file: the forward of the Plans
    /// kept as a draft, its upload cut off, taken by the next pass, then
    /// reopened from the row the pass drew and sent with no connection. In
    /// a later launch another draft, carrying another file at the same
    /// section, is under the copy's UID. Nothing of the other draft is
    /// fetched or sent, and it stays: the copy is looked for in All Mail by
    /// its id instead. Before, the other draft's file went as Plans.pdf and
    /// the other draft was expunged.
    ///
    /// The scripted server keeps a letter APPENDed to it as one text part,
    /// so the copy found in All Mail has no file to give there, and the
    /// letter stays in the Outbox saying the attachment could not be had;
    /// on Gmail the copy's file is where it was put.
    func testAForwardReopenedFromACopyFoundByItsMessageIDSendsNoOtherDraftsFile() async throws {
        deliverPlans()
        let first = makeRepository()
        let kept = makeKept()
        let forward = try await forwardOfPlans(first)
        let landed = try await landedAfterACutOff(forward.draft, as: "letter-1", kept: kept,
                                                  repository: first)
        let reopened = try await first.loadDraft(id: landed, mailboxID: Server.drafts)
        XCTAssertEqual(reopened.attachments.map(\.filename), ["Plans.pdf"])
        await sentOffline(reopened, as: "letter-2", kept: kept, repository: first)
        server.deliver(Server.Letter(
            from: Server.owner, to: [Server.sam], subject: "Other draft",
            date: Server.newestDate, text: "Another thought.\r\n", flags: ["\\Draft", "\\Seen"],
            messageID: "<draft-other@example.com>",
            files: [Server.File(name: "Results.pdf", type: "APPLICATION", subtype: "PDF",
                                bytes: resultsBytes)]), to: [Server.drafts, Server.allMail])
        try renumberDrafts(soThat: uid(landed), holds: "Other draft")

        let repository = makeRepository()
        let later = makeKept()
        _ = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        server.clearLog()
        await later.uploadWaiting(to: repository)?.value

        let sent = await submissions.letters()
        XCTAssertFalse(sent.contains { carries($0, resultsBytes) }, "never the other draft's file")
        XCTAssertFalse(server.log.contains { $0.selected == Server.drafts && $0.isUIDCommand },
                       "nothing asked of the draft the listing named under the UID")
        XCTAssertEqual(copies("Other draft"), [uid(landed)])
        let copy = try XCTUnwrap(reopened.savedLetter)
        XCTAssertTrue(server.log.contains {
            $0.selected == Server.allMail && $0.command == "UID SEARCH X-GM-MSGID \(copy)"
        })
        XCTAssertEqual(notes("CARRIED-PART"),
                       ["CARRIED-PART folder=\(Server.drafts) reason=another-letter"])
        XCTAssertEqual(later.outbox.map(\.key), ["letter-2"])
    }

    /// Drafts' list leaves out the copy a kept letter will replace only
    /// where the listing names the letter the kept one names there. In the
    /// launch that kept it the copy is not listed; in a later one, with
    /// Drafts renumbered so that another draft is under the copy's UID,
    /// that draft is. It used to be hidden by its UID alone, for as long as
    /// the letter waited.
    func testDraftsLeavesOutOnlyTheCopyAKeptLetterNames() async throws {
        let first = makeRepository()
        var rows = try await first.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        let row = try XCTUnwrap(rows.first { $0.subject == "Unfinished 1" })
        var reopened = try await first.reopen(row)
        reopened.subject = "Finished"
        var kept = makeKept()
        await savedOffline(reopened, as: "letter-1", kept: kept, repository: first)
        var list = ListLetters()
        _ = list.fetchedAfresh(rows)
        list.keep(kept.draftsRows(in: Server.drafts, from: "Owner"),
                  replacing: kept.replacedInDrafts)
        XCTAssertFalse(list.shown.contains { $0.id == row.id }, "its copy is not listed")

        server.renumber(Server.drafts, validity: server.uidValidity(of: Server.drafts),
                        firstUID: uid(row.id))
        let repository = makeRepository()
        kept = makeKept()
        rows = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        XCTAssertEqual(rows.first { $0.id == row.id }?.subject, "Unfinished 2")
        list = ListLetters()
        _ = list.fetchedAfresh(rows)
        list.keep(kept.draftsRows(in: Server.drafts, from: "Owner"),
                  replacing: kept.replacedInDrafts)
        XCTAssertEqual(list.shown.first { $0.id == row.id }?.subject, "Unfinished 2",
                       "another draft under its UID is listed")
    }

    /// Everyday use, one launch: a draft reopened from its row, then saved,
    /// sends the APPEND and its copy's removal; reopened again and sent, the
    /// copy's removal after the letter. No question: the listing named the
    /// letter under the UID.
    func testADraftReopenedSavedAndSentInOneLaunchSendsWhatItAlwaysDid() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        var rows = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        var reopened = try await repository.reopen(rows[0])
        reopened.body = "Changed at the kitchen table."
        server.clearLog()
        await makeActions("letter-1", kept: kept, repository: repository)
            .saveAndClose({ reopened }, then: nil)?.value
        XCTAssertEqual(server.log.map(\.verb), ["APPEND", "UID STORE", "UID EXPUNGE"])

        rows = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        let saved = try XCTUnwrap(rows.first { $0.subject == reopened.subject })
        let again = try await repository.reopen(saved)
        server.clearLog()
        await makeActions("letter-2", kept: kept, repository: repository)
            .send({ again }, then: nil)?.value
        XCTAssertEqual(server.log.map(\.verb), ["UID STORE", "UID EXPUNGE"])
        XCTAssertFalse(server.uids(in: Server.drafts).contains(uid(saved.id)))
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// A draft reopened from its row and sent with no connection waits in
    /// the Outbox naming its copy. In a later launch with Drafts renumbered,
    /// the pass sends the letter and removes no other draft.
    func testAReopenedDraftSentByAPassRemovesNoOtherDraft() async throws {
        let first = makeRepository()
        let rows = try await first.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        let row = try XCTUnwrap(rows.first { $0.subject == "Unfinished 1" })
        var reopened = try await first.reopen(row)
        reopened.to = ["carlo@example.org"]
        await sentOffline(reopened, as: "letter-1", kept: makeKept(), repository: first)
        server.renumber(Server.drafts, validity: server.uidValidity(of: Server.drafts),
                        firstUID: uid(row.id))

        let repository = makeRepository()
        let kept = makeKept()
        _ = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        server.clearLog()
        await kept.uploadWaiting(to: repository)?.value
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertFalse(server.log.contains { $0.verb == "UID EXPUNGE" || $0.verb == "UID STORE" })
        XCTAssertEqual(copies("Unfinished 2"), [uid(row.id)])
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// Kept from an earlier launch and opened in the composer, a reopened
    /// draft sent, and another deleted with Delete Draft, remove no other
    /// draft when Drafts has been renumbered under the same UIDVALIDITY so
    /// that each copy's UID holds another: the composer names the copy's
    /// letter as a pass does.
    func testAKeptDraftSentOrDeletedFromTheComposerRemovesNoOtherDraft() async throws {
        let first = makeRepository()
        let rows = try await first.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        for (n, row) in rows.enumerated() {
            let reopened = try await first.reopen(row)
            await savedOffline(reopened, as: "letter-\(n)", kept: makeKept(), repository: first)
        }
        server.deliver(Server.Letter(from: Server.owner, to: [Server.sam], subject: "Unfinished 3",
                                     date: Server.newestDate, text: "A third thought.\r\n",
                                     flags: ["\\Draft", "\\Seen"],
                                     messageID: "<draft-3@example.com>"), to: [Server.drafts])
        server.renumber(Server.drafts, validity: server.uidValidity(of: Server.drafts),
                        firstUID: uid(rows[1].id) - 2)
        let before = server.uids(in: Server.drafts).map { server.letter(uid: $0, in: Server.drafts)?.subject }
        XCTAssertEqual(server.letter(uid: uid(rows[0].id), in: Server.drafts)?.subject,
                       "Unfinished 3")
        XCTAssertEqual(server.letter(uid: uid(rows[1].id), in: Server.drafts)?.subject,
                       "Unfinished 1")

        let repository = makeRepository()
        let kept = makeKept()
        _ = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        server.clearLog()
        let sending = try XCTUnwrap(kept.letter("letter-0")).draft
        await makeActions("letter-0", kept: kept, repository: repository)
            .send({ sending }, then: nil)?.value
        let deleting = try XCTUnwrap(kept.letter("letter-1")).draft
        await makeActions("letter-1", kept: kept, repository: repository)
            .deleteAndClose(deleting.savedID, letter: deleting.savedLetter, then: nil)?.value

        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertFalse(server.log.contains { $0.verb == "UID STORE" || $0.verb == "UID EXPUNGE" })
        XCTAssertEqual(server.uids(in: Server.drafts).map {
            server.letter(uid: $0, in: Server.drafts)?.subject }, before)
    }

    /// On a server without Gmail's extension nothing is named, and all of
    /// it goes by folder and UID as it always did: a copy this launch put
    /// in Drafts is reopened with its plain FETCH and its words, and a
    /// forward kept in the Outbox from an earlier launch sends its file.
    func testWithoutGmailsExtensionNothingIsNamedAndItAllGoesAsBefore() async throws {
        server.withheldCapabilities = ["X-GM-EXT-1"]
        let plans = try XCTUnwrap(deliverPlans()[Server.inbox])
        let first = makeRepository()
        let kept = makeKept()
        let forward = try await forwardOfPlans(first)
        guard case let .messagePart(_, _, _, named) = try XCTUnwrap(forward.draft.attachments.first).source
        else { return XCTFail("not a part of a letter on the server") }
        XCTAssertNil(named)

        kept.keep(letter("Sunday"), as: "letter-1", unfinished: false)
        await kept.uploadWaiting(to: first)?.value
        let landed = try XCTUnwrap(kept.landed["letter-1"])
        server.clearLog()
        let reopened = try await first.loadDraft(id: landed, mailboxID: Server.drafts)
        XCTAssertEqual(server.log.filter(\.isUIDCommand).map(\.command),
                       ["UID FETCH \(uid(landed)) (UID BODY.PEEK[])"])
        XCTAssertTrue(reopened.body.contains("Lunch at one?"))
        XCTAssertNil(reopened.savedLetter)

        await sentOffline(forward.draft, as: "forward", kept: kept, repository: first)
        let repository = makeRepository()
        _ = try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 10)
        server.clearLog()
        await makeKept().uploadWaiting(to: repository)?.value
        let sent = await submissions.letters()
        XCTAssertTrue(carries(sent.last, plansBytes))
        XCTAssertEqual(server.log.filter(\.isUIDCommand).map(\.command),
                       ["UID FETCH \(plans) (UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODYSTRUCTURE)",
                        "UID FETCH \(plans) (UID BODY.PEEK[2])"])
    }

    // MARK: - A forward's files

    /// A forward of the Plans sent with no connection. In a later launch
    /// the Inbox is another mailbox under the same numbers, and the Plans'
    /// UID holds the medical results. The pass does not send their file as
    /// Plans.pdf: the FETCH that describes the letter names another, and
    /// nothing more is fetched there; the Plans are found in All Mail by
    /// their id, and their own file goes. Before, the results' file went
    /// under the Plans' file's name.
    func testAForwardWhoseOriginalsUIDIsAnotherLetterSendsItsOwnFileFromAllMail() async throws {
        let plans = try XCTUnwrap(deliverPlans()[Server.inbox])
        let first = makeRepository()
        let forward = try await forwardOfPlans(first)
        await sentOffline(forward.draft, as: "forward", kept: makeKept(), repository: first)
        deliverResults()
        renumberInbox(soThat: plans)
        XCTAssertEqual(server.letter(uid: plans, in: Server.inbox)?.subject, "Medical results")

        let repository = makeRepository()
        let kept = makeKept()
        _ = try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 10)
        server.clearLog()
        await kept.uploadWaiting(to: repository)?.value

        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(carries(sent.first, plansBytes), "the Plans' own file")
        XCTAssertFalse(carries(sent.first, resultsBytes), "not the results' file")
        XCTAssertTrue(sent.first?.contains("Plans.pdf") == true)
        let inbox = server.log.filter { $0.selected == Server.inbox && $0.isUIDCommand }
        XCTAssertEqual(inbox.count, 1, "one FETCH describing the letter, and no part of it")
        XCTAssertFalse(inbox.contains { $0.command.contains("BODY.PEEK") })
        let id = try XCTUnwrap(forward.row.gmailMessageID)
        XCTAssertTrue(server.log.contains {
            $0.selected == Server.allMail && $0.command == "UID SEARCH X-GM-MSGID \(id)"
        })
        XCTAssertEqual(notes("CARRIED-PART"),
                       ["CARRIED-PART folder=INBOX reason=another-letter",
                        "CARRIED-PART found folder=\(Server.allMail)"])
        XCTAssertEqual(kept.store.letters().count, 0)
    }

    /// The same, the Plans nowhere in this mailbox: nothing is sent, not a
    /// byte of the letter under their UID is fetched, the forward stays in
    /// the Outbox saying so, the letter after it goes, and the next pass
    /// does not try it again. Sent from the composer, the sheet stays with
    /// the same words.
    func testAForwardWhoseOriginalIsNowhereStaysInTheOutboxSayingSo() async throws {
        let plans = try XCTUnwrap(deliverPlans())
        let first = makeRepository()
        let forward = try await forwardOfPlans(first)
        let kept = makeKept()
        await sentOffline(forward.draft, as: "forward", kept: kept, repository: first)
        await sentOffline(letter("Fine"), as: "fine", kept: kept, repository: first)
        for (mailbox, at) in plans { server.removeElsewhere(uid: at, from: mailbox) }
        deliverResults()
        renumberInbox(soThat: try XCTUnwrap(plans[Server.inbox]))

        let repository = makeRepository()
        let later = makeKept()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        server.clearLog()
        await later.uploadWaiting(to: repository)?.value

        var sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(sent.first?.contains("Subject: Fine") == true, "the letter after it went")
        XCTAssertFalse(server.log.contains { $0.selected == Server.inbox && $0.isUIDCommand },
                       "nothing asked of the letter the listing named under the UID")
        XCTAssertEqual(later.outbox.map(\.key), ["forward"])
        XCTAssertEqual(later.whyNotSent("forward"), .attachmentsMissing)
        let row = try XCTUnwrap(later.outboxRows.first)
        XCTAssertEqual(row.preview.components(separatedBy: "\n").first,
                       "Attachment could not be downloaded.")
        XCTAssertEqual(notes("CARRIED-PART"),
                       ["CARRIED-PART folder=INBOX reason=another-letter",
                        "CARRIED-PART not-found nothing-sent"])

        server.clearLog()
        await later.uploadWaiting(to: repository)?.value
        XCTAssertEqual(server.log.map(\.verb), [], "not tried again unasked")

        let opened = try XCTUnwrap(later.letter("forward")).draft
        dismissals = 0
        errors = []
        await makeActions("forward", kept: later, repository: repository)
            .send({ opened }, then: nil)?.value
        XCTAssertEqual(errors, [.attachmentsMissing])
        XCTAssertEqual(dismissals, 0, "the sheet stays with the letter")
        sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
    }

    /// The letter under the Plans' old UID, opened in the later launch, is
    /// the one the repository has to hand when the pass comes: it is not
    /// taken for the Plans, whose file is found in All Mail.
    func testALetterOnScreenUnderTheOriginalsUIDIsNotTakenForIt() async throws {
        let plans = try XCTUnwrap(deliverPlans()[Server.inbox])
        let first = makeRepository()
        let forward = try await forwardOfPlans(first)
        await sentOffline(forward.draft, as: "forward", kept: makeKept(), repository: first)
        deliverResults()
        renumberInbox(soThat: plans)

        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let onScreen = try XCTUnwrap(rows.first { uid($0.id) == plans })
        XCTAssertEqual(onScreen.subject, "Medical results")
        _ = try await repository.open(onScreen)
        await makeKept().uploadWaiting(to: repository)?.value

        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(carries(sent.first, plansBytes))
        XCTAssertFalse(carries(sent.first, resultsBytes))
    }

    /// A forward whose original's folder has been renumbered with a new
    /// UIDVALIDITY since: its UID means nothing there now, and the original
    /// is found in All Mail by its id and its file goes. Named by folder and
    /// UID alone, the same forward is refused for its own sake
    /// (`OutboxTests`).
    func testAForwardWhoseOriginalsFolderWasRenumberedIsFoundInAllMail() async throws {
        deliverPlans()
        let first = makeRepository()
        let forward = try await forwardOfPlans(first)
        await sentOffline(forward.draft, as: "forward", kept: makeKept(), repository: first)
        server.renumber(Server.inbox, validity: 777, firstUID: 1)

        let repository = makeRepository()
        let kept = makeKept()
        _ = try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 10)
        await kept.uploadWaiting(to: repository)?.value
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(carries(sent.first, plansBytes))
        XCTAssertEqual(notes("CARRIED-PART").first, "CARRIED-PART folder=INBOX reason=folder")
        XCTAssertEqual(kept.outbox.count, 0)
    }

    /// A forward's quoted picture the same: sent from the Outbox in a later
    /// launch with its original's UID holding another letter, the picture in
    /// the quote is the original's own, found in All Mail, and never the
    /// other letter's picture at the same section.
    func testAQuotedPictureGoesOnlyFromItsOwnLetter() async throws {
        let original = try XCTUnwrap(server.deliver(
            pictured("The roof", "roof", roof, at: Server.newestDate),
            to: [Server.inbox, Server.allMail])[Server.inbox])
        let first = makeRepository()
        let rows = try await first.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let row = try XCTUnwrap(rows.first { $0.subject == "The roof" })
        var forward = Draft.forwarding(try await first.open(row))
        forward.to = ["carlo@example.org"]
        XCTAssertEqual(forward.quote?.pictures.map(\.letter), [row.gmailMessageID])
        await sentOffline(forward, as: "forward", kept: makeKept(), repository: first)
        server.deliver(pictured("A scan", "scan", scan, at: Server.newestDate.addingTimeInterval(60)),
                       to: [Server.inbox, Server.allMail])
        renumberInbox(soThat: original)

        let repository = makeRepository()
        _ = try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 10)
        await makeKept().uploadWaiting(to: repository)?.value

        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(carries(sent.first, roof), "the roof, in the quote")
        XCTAssertFalse(carries(sent.first, scan), "never the other letter's picture")
        XCTAssertEqual(notes("CARRIED-PART").last, "CARRIED-PART found folder=\(Server.allMail)")
    }

    /// A forward's quoted picture whose original is nowhere in this
    /// mailbox holds the letter as a file does: in the Outbox, saying so,
    /// the other letter's picture never sent in its place.
    func testAQuotedPictureWhoseOriginalIsNowhereHoldsTheLetter() async throws {
        let original = server.deliver(pictured("The roof", "roof", roof, at: Server.newestDate),
                                      to: [Server.inbox, Server.allMail])
        let first = makeRepository()
        let rows = try await first.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let row = try XCTUnwrap(rows.first { $0.subject == "The roof" })
        var forward = Draft.forwarding(try await first.open(row))
        forward.to = ["carlo@example.org"]
        await sentOffline(forward, as: "forward", kept: makeKept(), repository: first)
        for (mailbox, at) in original { server.removeElsewhere(uid: at, from: mailbox) }
        server.deliver(pictured("A scan", "scan", scan, at: Server.newestDate.addingTimeInterval(60)),
                       to: [Server.inbox, Server.allMail])
        renumberInbox(soThat: try XCTUnwrap(original[Server.inbox]))

        let repository = makeRepository()
        let kept = makeKept()
        _ = try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 10)
        await kept.uploadWaiting(to: repository)?.value
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 0)
        XCTAssertEqual(kept.whyNotSent("forward"), .attachmentsMissing)
        XCTAssertEqual(notes("CARRIED-PART").last, "CARRIED-PART not-found nothing-sent")
    }

    /// Everyday use, one launch: a forward made from a row and sent at once
    /// takes its file from the letter just opened, and asks the server for
    /// nothing. With another letter opened since, its file is fetched as it
    /// always was: the FETCH that describes the letter, then the part.
    func testAForwardMadeAndSentInOneLaunchAsksForNothingMore() async throws {
        let plans = try XCTUnwrap(deliverPlans()[Server.inbox])
        let repository = makeRepository()
        let kept = makeKept()
        let forward = try await forwardOfPlans(repository)
        server.clearLog()
        await makeActions("letter-1", kept: kept, repository: repository)
            .send({ forward.draft }, then: nil)?.value
        var sent = await submissions.letters()
        XCTAssertTrue(carries(sent.last, plansBytes))
        XCTAssertEqual(server.log.map(\.verb), [], "the letter on screen has the file")

        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        _ = try await repository.open(try XCTUnwrap(rows.last))
        server.clearLog()
        await makeActions("letter-2", kept: kept, repository: repository)
            .send({ forward.draft }, then: nil)?.value
        sent = await submissions.letters()
        XCTAssertTrue(carries(sent.last, plansBytes))
        XCTAssertEqual(server.log.map(\.command),
                       ["UID FETCH \(plans) (UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE "
                            + "BODYSTRUCTURE X-GM-LABELS X-GM-THRID X-GM-MSGID)",
                        "UID FETCH \(plans) (UID BODY.PEEK[2])"])
    }

    /// The Outbox pass for a forward kept this launch sends what it always
    /// did: the file from the letter on screen, nothing asked of the server.
    func testAnOutboxLetterKeptThisLaunchGoesAsItDid() async throws {
        deliverPlans()
        let repository = makeRepository()
        let kept = makeKept()
        let forward = try await forwardOfPlans(repository)
        await sentOffline(forward.draft, as: "forward", kept: kept, repository: repository)
        _ = try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 10)
        server.clearLog()
        await kept.uploadWaiting(to: repository)?.value
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(carries(sent.first, plansBytes))
        XCTAssertEqual(server.log.map(\.verb), [])
    }

    /// Autosave keeps the forward on the iPad with its original's id beside
    /// its folder and UID, and sends nothing.
    func testAnAutosavedForwardKeepsTheIDAndSendsNothing() async throws {
        deliverPlans()
        let repository = makeRepository()
        let kept = makeKept()
        let forward = try await forwardOfPlans(repository)
        let actions = makeActions("letter-1", kept: kept, repository: repository)
        server.clearLog()
        actions.edited { forward.draft }
        try await until { pauses.waiting == 1 }
        pauses.release()
        try await until { kept.store.letter("letter-1") != nil }

        XCTAssertEqual(server.log.map(\.verb), [])
        let file = try XCTUnwrap(kept.store.letter("letter-1")?.draft.attachments.first)
        guard case let .messagePart(_, _, _, id) = file.source else {
            return XCTFail("not a part of a letter on the server")
        }
        XCTAssertEqual(id, forward.row.gmailMessageID)
        XCTAssertEqual(makeKept().store.letter("letter-1")?.draft.attachments.count, 1)
    }

    // MARK: - A draft's files

    /// A draft carrying a forward's file whose original is nowhere in this
    /// mailbox is not taken to Drafts without it: it stays on the iPad, its
    /// row in Drafts saying so under "On this iPad only", and is not tried
    /// again until he changes it; the letter kept before it goes up.
    func testADraftWhoseFileIsNowhereStaysInDraftsSayingSo() async throws {
        let plans = try XCTUnwrap(deliverPlans())
        let first = makeRepository()
        let forward = try await forwardOfPlans(first)
        var kept = makeKept()
        kept.keep(letter("Older"), as: "older", unfinished: false)
        kept.keep(forward.draft, as: "forward", unfinished: false)
        for (mailbox, at) in plans { server.removeElsewhere(uid: at, from: mailbox) }
        deliverResults()
        renumberInbox(soThat: try XCTUnwrap(plans[Server.inbox]))

        let repository = makeRepository()
        kept = makeKept()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        await kept.uploadWaiting(to: repository)?.value

        XCTAssertEqual(copies("Older").count, 1)
        XCTAssertEqual(copies(forward.draft.subject), [])
        XCTAssertEqual(kept.waiting.map(\.key), ["forward"])
        let row = try XCTUnwrap(kept.draftsRows(in: Server.drafts, from: "Owner").first)
        XCTAssertEqual(Array(row.preview.components(separatedBy: "\n").prefix(2)),
                       [LocalDraft.mark, "Attachment could not be downloaded."])

        server.clearLog()
        await kept.uploadWaiting(to: repository)?.value
        XCTAssertEqual(server.log.map(\.verb), [], "not tried again unasked")
    }

    /// The same draft, changed since with its file taken off, and refused
    /// by the server for a reason of its own: its row no longer says its
    /// file is missing. A letter's reason is set with its refusal, and an
    /// earlier refusal's does not stay behind.
    func testADraftRefusedAgainForAnotherReasonNoLongerSaysItsFileIsMissing() async throws {
        let plans = try XCTUnwrap(deliverPlans())
        let first = makeRepository()
        let forward = try await forwardOfPlans(first)
        makeKept().keep(forward.draft, as: "forward", unfinished: false)
        for (mailbox, at) in plans { server.removeElsewhere(uid: at, from: mailbox) }

        let repository = makeRepository()
        let kept = makeKept()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        await kept.uploadWaiting(to: repository)?.value
        XCTAssertEqual(kept.whyNotSent("forward"), .attachmentsMissing)

        var changed = try XCTUnwrap(kept.letter("forward")).draft
        changed.attachments = []
        XCTAssertTrue(kept.keep(changed, as: "forward", unfinished: false))
        server.refusedVerbs = ["APPEND"]
        server.clearLog()
        await kept.uploadWaiting(to: repository)?.value
        XCTAssertEqual(server.log.last?.verb, "APPEND")
        XCTAssertEqual(kept.waiting.map(\.key), ["forward"])
        XCTAssertNil(kept.whyNotSent("forward"))
        let row = try XCTUnwrap(kept.draftsRows(in: Server.drafts, from: "Owner").first)
        XCTAssertFalse(row.preview.contains("Attachment could not be downloaded."))
    }

    // MARK: - Letters kept before the ids were

    /// A letter kept by a build before the ids were: its `letter.json` has
    /// none, and no count of passwords saved. It reads, and goes, as it
    /// always did: its file fetched by folder and UID, its old copy removed.
    /// Once a password has been saved, from the next launch on, what it names
    /// by folder and UID alone is left out, as a letter of another account
    /// opens, and it is not taken to the server unasked; the save itself
    /// touches no letter, and nothing changes in the launch that made it.
    /// A letter kept after the save, naming things by UID alone, is this
    /// mailbox's and goes.
    func testALetterKeptBeforeTheIDsGoesAsBeforeUntilAPasswordIsSaved() async throws {
        let plans = try XCTUnwrap(deliverPlans()[Server.inbox])
        let drafts = server.uids(in: Server.drafts)
        let validity = (inbox: server.uidValidity(of: Server.inbox),
                        drafts: server.uidValidity(of: Server.drafts))
        func legacy(_ key: String, subject: String, savedID: String?, file: Bool) throws -> URL {
            var json: [String: Any] = [
                "format": 1, "key": key, "version": "v-\(key)", "tried": [String](),
                "unfinished": false, "keptAt": 700_000_000.0, "account": server.username,
                "to": ["carlo@example.org"], "cc": [String](), "bcc": [String](),
                "subject": subject, "body": "Kept long ago.", "files": [[String: Any]]()]
            if let savedID { json["savedID"] = savedID }
            if file {
                json["files"] = [["filename": "Plans.pdf", "mimeType": "application/pdf",
                                  "size": 3000, "messageID": "\(validity.inbox)/\(plans)",
                                  "mailboxID": Server.inbox, "section": "2"]]
                json["quote"] = ["forward": true, "region": "Begin forwarded message:",
                                 "pictures": [["contentID": "p", "filename": "p.jpg",
                                               "mimeType": "image/jpeg",
                                               "messageID": "\(validity.inbox)/\(plans)",
                                               "mailboxID": Server.inbox, "section": "3"]]]
            }
            let folder = root.appendingPathComponent(key, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("letter.json")
            try JSONSerialization.data(withJSONObject: json).write(to: url)
            return url
        }
        let forwardFile = try legacy("forward", subject: "Forward", savedID: nil, file: true)
        let reopenedFile = try legacy("reopened", subject: "Reopened",
                                      savedID: "\(validity.drafts)/\(drafts[1])", file: false)

        var kept = makeKept()
        let read = try XCTUnwrap(kept.letter("forward")).draft
        XCTAssertEqual(read.attachments.count, 1, "an old letter reads")
        XCTAssertEqual(read.attachments.first?.isPartByUIDAlone, true)
        XCTAssertEqual(read.quote?.pictures.count, 1)
        XCTAssertEqual(kept.letter("reopened")?.draft.savedID, "\(validity.drafts)/\(drafts[1])")
        XCTAssertEqual(kept.replacedInDrafts, ["\(validity.drafts)/\(drafts[1])": nil])

        let before = try [Data(contentsOf: forwardFile), Data(contentsOf: reopenedFile)]
        LocalDraftStore.notePasswordSaved(in: root)
        XCTAssertEqual(try [Data(contentsOf: forwardFile), Data(contentsOf: reopenedFile)], before,
                       "the save touches no letter")
        XCTAssertEqual(kept.letter("forward")?.draft.attachments.count, 1,
                       "the launch that saved it still runs as the old password")

        kept = makeKept()
        XCTAssertEqual(kept.letter("forward")?.draft.attachments.count, 0)
        XCTAssertNil(kept.letter("forward")?.draft.quote)
        XCTAssertNil(kept.letter("reopened")?.draft.savedID)
        XCTAssertEqual(kept.replacedInDrafts, [:])
        let repository = makeRepository()
        _ = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        server.clearLog()
        await kept.uploadWaiting(to: repository)?.value
        XCTAssertEqual(server.log.map(\.verb), [], "neither goes by itself")
        XCTAssertEqual(Set(kept.waiting.map(\.key)), ["forward", "reopened"])
        XCTAssertTrue(server.uids(in: Server.drafts).contains(drafts[1]))

        var named = letter("Kept after")
        named.savedID = "\(validity.drafts)/\(drafts[0])"
        kept.keep(named, as: "after", unfinished: false)
        kept = makeKept()
        XCTAssertEqual(kept.letter("after")?.draft.savedID, named.savedID,
                       "kept since the save, it names this mailbox's")
        XCTAssertNil(makeKept().letter("reopened")?.draft.savedID, "and still, launch after launch")
    }

    /// Before the save, in a launch of its own, the old letters go as they
    /// always did: the forward's file by folder and UID, the reopened
    /// draft's old copy removed.
    func testALetterKeptBeforeTheIDsGoesAsItAlwaysDid() async throws {
        let plans = try XCTUnwrap(deliverPlans()[Server.inbox])
        let first = makeRepository()
        let rows = try await first.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        var reopened = try await first.reopen(rows[0])
        reopened.savedLetter = nil
        reopened.subject = "Reopened"
        var forward = letter("Forward")
        forward.attachments = [DraftAttachment(
            source: .messagePart(messageID: "\(server.uidValidity(of: Server.inbox))/\(plans)",
                                 mailboxID: Server.inbox, section: "2"),
            filename: "Plans.pdf", mimeType: "application/pdf", size: 3000)]
        let kept = makeKept()
        kept.keep(reopened, as: "reopened", unfinished: false)
        kept.keep(forward, as: "forward", unfinished: false)

        let repository = makeRepository()
        _ = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        await makeKept().uploadWaiting(to: repository)?.value
        XCTAssertEqual(copies("Reopened").count, 1)
        XCTAssertFalse(server.uids(in: Server.drafts).contains(uid(rows[0].id)))
        let copy = try XCTUnwrap(copies("Forward").first)
        XCTAssertTrue(carries(server.letter(uid: copy, in: Server.drafts)?.text, plansBytes),
                      "its file fetched by folder and UID")
    }

    /// Letters kept before a password save that name their letters by
    /// Gmail's id, and one that names nothing on the server, go as ever from
    /// the next launch: the draft reopened from its row keeps its copy and
    /// removes it, the server showing it the same letter, the forward keeps
    /// its file and sends it, and the plain letter goes up. Only what a
    /// letter names by folder and UID alone is left out after a save.
    func testLettersNamingTheirLettersGoAsEverAfterAPasswordSave() async throws {
        deliverPlans()
        let first = makeRepository()
        let forward = try await forwardOfPlans(first)
        let rows = try await first.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        let row = try XCTUnwrap(rows.first { $0.subject == "Unfinished 1" })
        var reopened = try await first.reopen(row)
        reopened.subject = "Finished"
        let kept = makeKept()
        kept.keep(letter("Plain"), as: "plain", unfinished: false)
        kept.keep(reopened, as: "reopened", unfinished: false)
        await sentOffline(forward.draft, as: "forward", kept: kept, repository: first)
        LocalDraftStore.notePasswordSaved(in: root)

        let repository = makeRepository()
        let later = makeKept()
        XCTAssertEqual(later.letter("reopened")?.draft.savedID, row.id)
        XCTAssertEqual(later.letter("reopened")?.draft.savedLetter, row.gmailMessageID)
        XCTAssertEqual(later.letter("forward")?.draft.attachments.count, 1)
        XCTAssertEqual(later.replacedInDrafts, [row.id: row.gmailMessageID])
        _ = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 10)
        await later.uploadWaiting(to: repository)?.value

        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(carries(sent.first, plansBytes))
        XCTAssertEqual(copies("Plain").count, 1)
        XCTAssertEqual(copies("Finished").count, 1)
        XCTAssertEqual(copies("Unfinished 1"), [], "its copy removed")
        XCTAssertEqual(later.store.letters().count, 0)
    }

    // MARK: - The line going while a part is found

    /// The line going while the Plans are looked for in All Mail is not the
    /// Plans' being nowhere: the forward waits in the Outbox saying
    /// nothing, and the next pass, the line back, sends their own file.
    func testALineThatGoesWhileTheOriginalIsLookedForLeavesTheForwardWaiting() async throws {
        let plans = try XCTUnwrap(deliverPlans()[Server.inbox])
        let first = makeRepository()
        let forward = try await forwardOfPlans(first)
        await sentOffline(forward.draft, as: "forward", kept: makeKept(), repository: first)
        deliverResults()
        renumberInbox(soThat: plans)

        let repository = makeRepository()
        let kept = makeKept()
        _ = try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 10)
        server.holdReplies(to: "UID SEARCH")
        let pass = try XCTUnwrap(kept.uploadWaiting(to: repository))
        try await until { server.log.contains { $0.command.hasPrefix("UID SEARCH X-GM-MSGID") } }
        line.isUp = false
        await server.resetConnections()
        await server.releaseReplies(to: "UID SEARCH")
        await pass.value
        XCTAssertEqual(kept.outbox.map(\.key), ["forward"])
        XCTAssertNil(kept.whyNotSent("forward"))
        XCTAssertEqual(notes("CARRIED-PART"), ["CARRIED-PART folder=INBOX reason=another-letter"])

        line.isUp = true
        _ = try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 10)
        await kept.uploadWaiting(to: repository)?.value
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(carries(sent.first, plansBytes))
        XCTAssertFalse(carries(sent.first, resultsBytes))
        XCTAssertEqual(kept.outbox.count, 0)
    }

    /// The line going during the FETCH that describes the original is not
    /// the original's being gone: nothing is said of the file and nothing
    /// is looked for, the forward waits in the Outbox, and the next pass
    /// sends it.
    func testALineThatGoesWhileTheOriginalIsDescribedLeavesTheForwardWaiting() async throws {
        deliverPlans()
        let first = makeRepository()
        let forward = try await forwardOfPlans(first)
        await sentOffline(forward.draft, as: "forward", kept: makeKept(), repository: first)

        let repository = makeRepository()
        let kept = makeKept()
        _ = try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 10)
        server.clearLog()
        server.holdReplies(to: "UID FETCH")
        let pass = try XCTUnwrap(kept.uploadWaiting(to: repository))
        try await until { server.log.contains { $0.verb == "UID FETCH" } }
        line.isUp = false
        await server.resetConnections()
        await server.releaseReplies(to: "UID FETCH")
        await pass.value
        XCTAssertEqual(server.log.filter(\.isUIDCommand).first?.selected, Server.inbox)
        XCTAssertEqual(kept.outbox.map(\.key), ["forward"])
        XCTAssertNil(kept.whyNotSent("forward"))
        XCTAssertEqual(notes("CARRIED-PART"), [])

        line.isUp = true
        _ = try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 10)
        await kept.uploadWaiting(to: repository)?.value
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(carries(sent.first, plansBytes))
        XCTAssertEqual(kept.outbox.count, 0)
    }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }
}

/// The network, up or down, from any thread.
private final class ReferenceLine: @unchecked Sendable {
    private let lock = NSLock()
    private var up = true

    var isUp: Bool {
        get { lock.lock(); defer { lock.unlock() }; return up }
        set { lock.lock(); up = newValue; lock.unlock() }
    }
}

/// A submission server per connection, as the SMTP client makes one per
/// letter, and every letter any of them was handed.
private final class ReferenceSubmissions: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [ScriptedSubmission] = []

    func next() -> ScriptedSubmission {
        let server = ScriptedSubmission()
        lock.lock()
        made.append(server)
        lock.unlock()
        return server
    }

    func letters() async -> [String] {
        lock.lock()
        let servers = made
        lock.unlock()
        var out: [String] = []
        for server in servers {
            out += await server.letters.map { String(decoding: $0, as: UTF8.self) }
        }
        return out
    }
}
