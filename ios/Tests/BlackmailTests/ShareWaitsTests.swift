import XCTest
@testable import Blackmail

/// B-153: a share with no files and no connection waits in Blackmail's
/// Outbox, as a share in Mail waits in Mail's. The sheet closes with the
/// sent sound, the letter is handed to the app through the shared Keychain
/// group, one item a share however often Send is tapped, and the app takes
/// it into its Outbox at launch and as it comes back to the front, once,
/// to go by the next pass as the share would have sent it. A share with
/// files is refused as before, and so is every share from the day the app
/// stops opening.
@MainActor
final class ShareWaitsTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "ShareWaitsTests"

    private let page = URL(string: "https://en.wikipedia.org/wiki/Mercury_(planet)?wprov=sfti1")!
    /// The time of his Send, in every test.
    private let sharedAt = Date(timeIntervalSince1970: 1_790_000_000)

    private var keychain = HandoverKeychain()
    private var mirror: ShareMirror { ShareMirror(keychain: keychain) }
    private var log: [String] = []
    private var errors: [MailError] = []
    private var swooshes = 0
    private var root: URL!
    private var book: RecipientBook!
    private var passTime = FakeBackground()

    override func setUp() async throws {
        try await super.setUp()
        keychain = HandoverKeychain()
        passTime = FakeBackground()
        log = []
        errors = []
        swooshes = 0
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ShareWaitsTests-\(UUID().uuidString)", isDirectory: true)
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: UserDefaults(suiteName: Self.suite)!)
    }

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        for outcome in ["ok", "fail"] {
            let transcript = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
            try? FileManager.default.removeItem(atPath: transcript)
        }
        root = nil
        book = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private var account: MailAccount {
        MailAccount(address: "owner@example.com", username: "owner@example.com",
                    displayName: "Sam", signature: "Sam\n1 Example Street",
                    signatureHTML: "<table><tr><td><b>Sam</b></td></tr></table>")
    }

    /// The extension's sheet over `server`, handing a letter that cannot go
    /// to this test's Keychain group, the app stopping at `appStops`.
    private func sheet(_ server: @escaping @Sendable () -> ScriptedSubmission,
                       appStops: Date? = nil, files: [URL: Data] = [:]) -> ShareSheet {
        let shared = ShareMirror.Shared(account: account, password: "app-password",
                                        signatureImages: [], recipients: [])
        let mirror = self.mirror
        let at = sharedAt
        return ShareSheet(
            shared: shared,
            transport: { _, _ in server() },
            openFile: { attachment in
                guard case let .localFile(url) = attachment.source, let data = files[url] else {
                    throw MailError.attachmentFailed
                }
                return .bytes(data)
            },
            noteSent: { _ in },
            finish: { [unowned self] in log.append("finish") },
            cancel: { [unowned self] in log.append("cancel") },
            sent: { [unowned self] in swooshes += 1 },
            showError: { [unowned self] in errors.append($0); log.append("error") },
            draw: { _ in },
            background: BackgroundTime(begin: { _, _ in nil }, end: { _ in }),
            wait: { mirror.wait($0) },
            appStops: { appStops },
            calendar: utc,
            now: { at })
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func letter(_ sheet: ShareSheet, _ items: [SharedItem]) -> Draft {
        var draft = sheet.letter(from: items)
        draft.to = ["owner@example.net"]
        return draft
    }

    private func waiting() -> [ShareMirror.WaitingShare] {
        mirror.waitingShares().compactMap(\.share)
    }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<2_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    // MARK: - The sheet

    /// The owner's case: a page shared from Safari with no connection. The
    /// sheet closes as when a letter goes, with one sent sound and no
    /// alert, and the letter waits for the app under the share's own key:
    /// whom it is to, its subject and words, the Message-ID its attempt
    /// went under, the time of his Send, and the name and signature he sent
    /// it with. A second Send sends and leaves nothing more.
    func testAShareWithNoConnectionClosesAndWaitsForTheApp() async throws {
        let sheet = sheet({ ScriptedSubmission(failsToOpen: true) })
        let draft = letter(sheet, [.link(page, title: "Mercury - Wikipedia")])

        await sheet.send { draft }?.value

        XCTAssertEqual(log, ["finish"], "the sheet closes, the share completed")
        XCTAssertEqual(errors, [])
        XCTAssertEqual(swooshes, 1)
        XCTAssertEqual(keychain.items.keys.sorted(), [ShareMirror.waitingPrefix + sheet.key])
        let share = try XCTUnwrap(waiting().first)
        XCTAssertEqual(share.key, sheet.key)
        XCTAssertEqual(share.account, "owner@example.com")
        XCTAssertEqual(share.to, ["owner@example.net"])
        XCTAssertEqual(share.subject, "Mercury - Wikipedia")
        XCTAssertEqual(share.body, draft.body)
        XCTAssertEqual(share.messageID, sheet.messageID)
        XCTAssertTrue(sheet.messageID.hasSuffix("@example.com>"))
        XCTAssertEqual(share.sentAt, sharedAt)
        XCTAssertEqual(share.atSend, AtSend(name: "Sam", date: sharedAt, signature: .init(
            text: "Sam\n1 Example Street", html: "<table><tr><td><b>Sam</b></td></tr></table>")))
        XCTAssertNil(share.cutOff, "nothing went")

        XCTAssertNil(sheet.send { draft }, "a second Send sends nothing")
        XCTAssertEqual(keychain.items.count, 1)
        XCTAssertEqual(swooshes, 1)
    }

    /// The handover is the share's own: written again, as a Send that
    /// cannot go again would write it, it is the one item still.
    func testAShareWrittenTwiceIsOneLetter() throws {
        let share = ShareMirror.WaitingShare(key: "one", account: account, draft: Draft(),
                                             messageID: "<one@example.com>", sentAt: sharedAt,
                                             cutOff: nil)
        XCTAssertTrue(mirror.wait(share))
        XCTAssertTrue(mirror.wait(share))
        XCTAssertEqual(keychain.items.count, 1)
        XCTAssertEqual(keychain.writes, [ShareMirror.waitingPrefix + "one"])
    }

    /// Cut off after its DATA, no 250 back: it waits, with the time of the
    /// cut, so the app asks Sent Mail before it goes again.
    /// The attempt went under the Message-ID and the Date handed over, so
    /// Sent Mail is asked for the letter Gmail may have.
    func testAShareCutOffAfterItsDataWaitsUnsettled() async throws {
        let server = ScriptedSubmission(hangsUpBeforeLetterReply: true)
        let sheet = sheet({ server })
        let draft = letter(sheet, [.link(page, title: nil)])

        await sheet.send { draft }?.value

        XCTAssertEqual(log, ["finish"])
        let share = try XCTUnwrap(waiting().first)
        XCTAssertEqual(share.cutOff, sharedAt)
        let went = await server.letters
        let raw = try XCTUnwrap(went.first)
        let headers = MIMEDecoder.parseHeaders(raw)
        XCTAssertEqual(MIMEDecoder.headerValue("Message-ID", in: headers), share.messageID)
        XCTAssertEqual(MIMEDecoder.headerValue("Date", in: headers),
                       RFC5322Builder.rfc5322Date(sharedAt))
    }

    /// A share with a photo, with no connection, is refused as before: its
    /// file is the extension's, which the app cannot read. The sheet stays
    /// with the reason, no sound, and nothing waits.
    func testAShareWithFilesIsStillRefused() async throws {
        let url = URL(fileURLWithPath: "/staged/0/Garden.jpg")
        let photo = Data((0..<600).map { UInt8($0 % 251) })
        let sheet = sheet({ ScriptedSubmission(failsToOpen: true) }, files: [url: photo])
        let draft = letter(sheet, [.link(page, title: nil),
                                   .file(url, filename: "Garden.jpg", mimeType: "image/jpeg",
                                         size: Int64(photo.count))])

        await sheet.send { draft }?.value

        XCTAssertEqual(log, ["error"], "the sheet stays")
        XCTAssertEqual(errors, [.cannotConnect])
        XCTAssertEqual(swooshes, 0)
        XCTAssertTrue(keychain.items.isEmpty)
    }

    /// A refusal that is not the connection's, a recipient or the letter
    /// refused, stays in the sheet as before; and so does a share the
    /// Keychain will not take.
    func testARefusalAndAHandoverRefusedStayInTheSheet() async throws {
        let refused = sheet({ ScriptedSubmission(letterReply: "554 5.7.0 Message refused") })
        await refused.send { [self] in letter(refused, [.link(page, title: nil)]) }?.value
        XCTAssertEqual(log, ["error"])
        XCTAssertTrue(keychain.items.isEmpty)

        keychain.refuses = true
        let offline = sheet({ ScriptedSubmission(failsToOpen: true) })
        await offline.send { [self] in letter(offline, [.link(page, title: nil)]) }?.value
        XCTAssertEqual(log, ["error", "error"])
        XCTAssertEqual(errors.last, .cannotConnect)
        XCTAssertTrue(keychain.items.isEmpty)
        XCTAssertEqual(swooshes, 0)
    }

    /// From the day the app stops opening, in his calendar, a share with no
    /// connection is refused as before; the day before, it waits.
    func testFromTheDayTheAppStopsAShareIsRefusedAgain() async throws {
        let stops = sharedAt.addingTimeInterval(6 * 3_600)
        XCTAssertTrue(utc.isDate(stops, inSameDayAs: sharedAt), "the share on the day it stops")
        let late = sheet({ ScriptedSubmission(failsToOpen: true) }, appStops: stops)
        await late.send { [self] in letter(late, [.link(page, title: nil)]) }?.value
        XCTAssertEqual(log, ["error"])
        XCTAssertTrue(keychain.items.isEmpty)

        let early = sheet({ ScriptedSubmission(failsToOpen: true) },
                          appStops: stops.addingTimeInterval(86_400))
        await early.send { [self] in letter(early, [.link(page, title: nil)]) }?.value
        XCTAssertEqual(log, ["error", "finish"])
        XCTAssertEqual(keychain.items.count, 1)

        XCTAssertTrue(ShareSheet.waits(at: sharedAt, appStops: nil, calendar: utc))
        XCTAssertFalse(ShareSheet.waits(at: stops.addingTimeInterval(86_400), appStops: stops,
                                        calendar: utc))
        XCTAssertFalse(ShareSheet.waits(at: utc.startOfDay(for: stops), appStops: stops,
                                        calendar: utc))
        XCTAssertTrue(ShareSheet.waits(at: utc.startOfDay(for: stops).addingTimeInterval(-1),
                                       appStops: stops, calendar: utc))
    }

    // MARK: - The app takes it

    private func makeKept() -> LocalDrafts {
        LocalDrafts(store: LocalDraftStore(root: root), account: "owner@example.com",
                    background: passTime.time)
    }

    private func handOver(cutOff: Date? = nil, key: String = "shared-1") -> ShareMirror.WaitingShare {
        var draft = ShareLetter.draft(from: [.link(page, title: "Mercury - Wikipedia")],
                                      signature: account.signature)
        draft.to = ["owner@example.net"]
        let share = ShareMirror.WaitingShare(key: key, account: account, draft: draft,
                                             messageID: "<\(key)@example.com>", sentAt: sharedAt,
                                             cutOff: cutOff)
        XCTAssertTrue(mirror.wait(share))
        return share
    }

    /// Taken into the Outbox as his Send would have left it: under the
    /// share's key and Message-ID, dated by his Send, with the name and the
    /// signature it was sent with, a share. Listed, "1 Unsent Message", and
    /// the lists told; the handover forgotten.
    func testTheAppTakesAShareIntoItsOutbox() throws {
        let share = handOver()
        let kept = makeKept()
        var told = 0
        let observer = NotificationCenter.default.addObserver(
            forName: LocalDrafts.changed, object: nil, queue: nil) { _ in told += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        kept.takeShares(from: mirror)

        let letter = try XCTUnwrap(kept.store.letter(share.key))
        XCTAssertEqual(letter.outbox, share.messageID)
        XCTAssertEqual(letter.outboxState, .waiting)
        XCTAssertEqual(letter.atSend, share.atSend)
        XCTAssertEqual(letter.keptAt, sharedAt)
        XCTAssertEqual(letter.account, "owner@example.com")
        XCTAssertTrue(letter.isShared)
        XCTAssertEqual(letter.draft.subject, "Mercury - Wikipedia")
        XCTAssertEqual(letter.draft.to, ["owner@example.net"])
        XCTAssertEqual(letter.draft.body, share.body)
        XCTAssertEqual(kept.outbox.map(\.key), [share.key])
        XCTAssertEqual(kept.outboxRows.count, 1)
        XCTAssertEqual(Outbox.unsent(kept.outbox.count), "1 Unsent Message")
        XCTAssertEqual(told, 1)
        XCTAssertTrue(keychain.items.isEmpty, "the handover forgotten")
    }

    /// Never twice. The handover left where the app was ended between
    /// taking it and forgetting it: taken again, it is the one letter. A
    /// Keychain that will not forget it: the letter is taken out of the
    /// Outbox again, to be taken next time, never both. A handover that
    /// cannot be read is forgotten.
    func testAShareIsTakenOnce() throws {
        let share = handOver()
        let kept = makeKept()
        kept.takeShares(from: mirror)
        var changed = try XCTUnwrap(kept.store.letter(share.key)).draft
        changed.body = "Have a look." + changed.body
        try kept.store.keep(changed, as: share.key, unfinished: true, account: "owner@example.com")
        _ = try kept.store.enterOutbox(share.key)
        _ = handOver()
        kept.takeShares(from: mirror)
        XCTAssertEqual(kept.outbox.count, 1)
        XCTAssertEqual(kept.store.letter(share.key)?.draft.body, changed.body,
                       "the letter in the Outbox as it is, not taken over again")
        XCTAssertTrue(keychain.items.isEmpty)

        let stuck = handOver(key: "shared-2")
        keychain.keepsOnRemove = true
        kept.takeShares(from: mirror)
        XCTAssertNil(kept.store.letter(stuck.key), "not both")
        XCTAssertEqual(kept.outbox.map(\.key), [share.key])
        XCTAssertEqual(keychain.items.count, 1)
        keychain.keepsOnRemove = false
        kept.takeShares(from: mirror)
        XCTAssertEqual(Set(kept.outbox.map(\.key)), [share.key, stuck.key])
        XCTAssertTrue(keychain.items.isEmpty)

        keychain.items[ShareMirror.waitingPrefix + "broken"] = Data("not a letter".utf8)
        kept.takeShares(from: mirror)
        XCTAssertTrue(keychain.items.isEmpty)
        XCTAssertEqual(kept.outbox.count, 2)
    }

    /// A letter put in the Outbox by a build before shares were, and one
    /// kept since, read as no share; a share opened from the Outbox in the
    /// composer and kept again is a share still.
    func testAShareStaysAShareAndOlderLettersAreNone() throws {
        let share = handOver()
        let kept = makeKept()
        kept.takeShares(from: mirror)
        var draft = try XCTUnwrap(kept.store.letter(share.key)).draft
        draft.body = "Have a look." + draft.body
        try kept.store.keep(draft, as: share.key, unfinished: true, account: "owner@example.com")
        XCTAssertEqual(kept.store.letter(share.key)?.isShared, true)

        let file = root.appendingPathComponent(share.key, isDirectory: true)
            .appendingPathComponent("letter.json")
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(json["shared"] as? Bool, true)
        json["shared"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: file, options: .atomic)
        XCTAssertEqual(kept.store.letter(share.key)?.isShared, false)

        try kept.store.keep(draft, as: "mine", unfinished: false, account: "owner@example.com")
        XCTAssertEqual(kept.store.letter("mine")?.isShared, false)
    }

    // MARK: - Wiring and the day it stops

    /// Read from the source: the app takes the shares in as its screens
    /// come up and as it comes back to the front, before that return's
    /// pass; the extension hands a letter over through the shared group,
    /// and knows when the app stops from the app's own profile.
    func testTheAppAndTheExtensionAreWired() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail", isDirectory: true)
        let root = try String(contentsOf: sources.appendingPathComponent("UI/RootViewController.swift"))
        XCTAssertTrue(root.contains("LocalDrafts.shared.takeShares(from: mirror)"))
        XCTAssertEqual(root.components(separatedBy: "takeWaitingShares()").count - 1, 3,
                       "defined, at launch, and on return")
        let back = try XCTUnwrap(root.range(of: "self.takeWaitingShares()"))
        let pass = try XCTUnwrap(root.range(of: "LocalDrafts.shared.uploadWaiting(to: repository)\n"))
        XCTAssertLessThan(back.lowerBound, pass.lowerBound, "before the return's pass")
        let share = try String(contentsOf: sources.appendingPathComponent("Share/ShareViewController.swift"))
        XCTAssertTrue(share.contains("wait: { ShareMirror.device.wait($0) }"))
        XCTAssertTrue(share.contains("appStops: { AppExpiry.containingApp.stops }"))
    }

    /// When the app stops, read from the extension: the app's profile, two
    /// folders up from the extension's bundle in the app's PlugIns; the
    /// extension's own where the app's has none, or there is no app;
    /// nothing where neither has one.
    func testTheExtensionReadsWhenTheAppStops() throws {
        let files = FileManager.default
        let container = root.appendingPathComponent("Container", isDirectory: true)
        let app = container.appendingPathComponent("Blackmail.app", isDirectory: true)
        let appex = app.appendingPathComponent("PlugIns/BlackmailShare.appex", isDirectory: true)
        try files.createDirectory(at: appex, withIntermediateDirectories: true)
        func profile(_ expires: Date) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: ["ExpirationDate": expires],
                                               format: .xml, options: 0)
        }
        let appStops = sharedAt.addingTimeInterval(30 * 86_400)
        let appexStops = sharedAt.addingTimeInterval(40 * 86_400)
        let now = sharedAt

        XCTAssertEqual(ShareSheet.containingApp(of: appex)?.standardizedFileURL,
                       app.standardizedFileURL)
        XCTAssertNil(ShareSheet.containingApp(of: app))
        XCTAssertNil(ShareSheet.containingApp(of: container.appendingPathComponent("Share.appex")))
        let held = ShareSheet.containingApp(of: appex)
        XCTAssertEqual(AppExpiry.forShare(app: held, appex: appex, now: now), .noProfile)
        try profile(appexStops).write(to: appex.appendingPathComponent("embedded.mobileprovision"))
        XCTAssertEqual(AppExpiry.forShare(app: held, appex: appex, now: now), .stops(appexStops))
        try profile(appStops).write(to: app.appendingPathComponent("embedded.mobileprovision"))
        XCTAssertEqual(AppExpiry.forShare(app: held, appex: appex, now: now), .stops(appStops))
        XCTAssertEqual(AppExpiry.forShare(app: held, appex: appex, now: now).stops, appStops)
        XCTAssertEqual(AppExpiry.forShare(app: nil, appex: appex, now: now), .stops(appexStops))
        XCTAssertNil(AppExpiry.Found.noProfile.stops)
        XCTAssertNil(AppExpiry.Found.trollStore.stops)
    }

    // MARK: - It goes

    /// Over the shipping repository: the share taken in at the next
    /// opening goes by the next pass, once, as the share would have sent
    /// it: the same HTML, the link a link in it, From the name it was
    /// shared with, dated by his Send, under the share's Message-ID.
    func testATakenShareGoesAsTheShareWouldHaveSentIt() async throws {
        let offline = sheet({ ScriptedSubmission(failsToOpen: true) })
        let draft = letter(offline, [.link(page, title: "Mercury - Wikipedia")])
        await offline.send { draft }?.value
        XCTAssertEqual(log, ["finish"])

        let online = ScriptedSubmission()
        let direct = sheet({ online })
        await direct.send { draft }?.value
        let directLetters = await online.letters
        let directLetter = try XCTUnwrap(directLetters.first)

        let server = ScriptedIMAPServer(inboxCount: 6)
        let submissions = ScriptedSubmission()
        let imap = server.transportFactory
        let repository = IMAPMailRepository(
            account: server.account, password: server.password,
            transport: { host, port in port == 465 ? submissions as any MailTransport : imap(host, port) },
            recipients: book, signatureImages: { [] })
        let kept = makeKept()
        kept.takeShares(from: mirror)
        XCTAssertEqual(kept.outbox.count, 1)
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        await kept.uploadWaiting(to: repository)?.value

        XCTAssertEqual(kept.outbox.count, 0)
        let sent = await submissions.letters
        XCTAssertEqual(sent.count, 1)
        let raw = try XCTUnwrap(sent.first)
        func header(_ name: String, _ raw: Data) -> String? {
            MIMEDecoder.headerValue(name, in: MIMEDecoder.parseHeaders(raw)).map(MIMEDecoder.decodeWord)
        }
        XCTAssertEqual(header("Message-ID", raw), offline.messageID)
        XCTAssertEqual(header("Date", raw), RFC5322Builder.rfc5322Date(sharedAt))
        XCTAssertEqual(header("From", raw), "Sam <owner@example.com>")
        XCTAssertEqual(header("Subject", raw), "Mercury - Wikipedia")
        let html = try XCTUnwrap(MIMEDecoder.decodeMessage(raw).html)
        XCTAssertTrue(html.contains("<a href=\"\(page.absoluteString)\">"), html)
        XCTAssertEqual(html, MIMEDecoder.decodeMessage(directLetter).html, "as the share sends it")
        XCTAssertEqual(MIMEDecoder.decodeMessage(raw).text,
                       MIMEDecoder.decodeMessage(directLetter).text)
        XCTAssertEqual(server.violations, [])
    }

    /// Cut off after its DATA in the sheet: taken in unsettled, and found
    /// in Sent Mail by its Message-ID, it is not sent again.
    func testAShareCutOffAfterItsDataIsNotSentTwice() async throws {
        let share = handOver(cutOff: sharedAt)
        let server = ScriptedIMAPServer(inboxCount: 6)
        server.deliver(ScriptedIMAPServer.Letter(
            from: ScriptedIMAPServer.owner, to: [ScriptedIMAPServer.Address(name: nil,
                                                                             address: "owner@example.net")],
            subject: share.subject, date: sharedAt, text: "It went.\r\n", flags: ["\\Seen"],
            messageID: share.messageID), to: [Server.sent, Server.allMail])
        let submissions = ScriptedSubmission()
        let imap = server.transportFactory
        let repository = IMAPMailRepository(
            account: server.account, password: server.password,
            transport: { host, port in port == 465 ? submissions as any MailTransport : imap(host, port) },
            recipients: book, signatureImages: { [] })
        let kept = makeKept()
        kept.takeShares(from: mirror)
        let letter = try XCTUnwrap(kept.store.letter(share.key))
        XCTAssertEqual(letter.outboxState, .beingSent)
        XCTAssertEqual(letter.cutOff, sharedAt)

        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        await kept.uploadWaiting(to: repository)?.value

        let looks = server.log.filter { $0.command.contains("HEADER Message-ID") }
        XCTAssertEqual(looks.count, 1, "Sent Mail asked first")
        let sent = await submissions.letters
        XCTAssertEqual(sent.count, 0, "found there, not sent again")
        XCTAssertEqual(kept.outbox.count, 0)
        XCTAssertEqual(server.violations, [])
    }
}

/// The shared Keychain group as a dictionary, counting what is written to
/// it. `refuses` refuses every write; `keepsOnRemove` keeps an item it is
/// told to remove.
private final class HandoverKeychain: SharedKeychain {
    var items: [String: Data] = [:]
    var writes: [String] = []
    var refuses = false
    var keepsOnRemove = false

    func data(named name: String) -> Data? { items[name] }

    func store(_ data: Data, named name: String) -> Bool {
        guard !refuses else { return false }
        writes.append(name)
        items[name] = data
        return true
    }

    func remove(named name: String) {
        guard !keepsOnRemove else { return }
        items[name] = nil
    }

    func names() -> [String] { Array(items.keys) }
}
