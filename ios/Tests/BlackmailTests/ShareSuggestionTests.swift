import XCTest
@testable import Blackmail

/// The people at the top of the share sheet, as Mail has them there
/// (B-163): each letter that goes is told to iOS by the people it went
/// to, from the app and from the share sheet, never one that did not go
/// and never one to nobody but himself; and a share opened from one of
/// those circles begins with them in To. What iOS does with it is the
/// iPad's to show; here, what Blackmail tells it, and when.
@MainActor
final class ShareSuggestionTests: XCTestCase {

    private let account = MailAccount(address: "owner@example.com", username: "owner@example.com",
                                      displayName: "Sam", signature: "Sam",
                                      otherAddresses: ["Sam.Second@Example.net"])
    private var mine: OwnAddresses { OwnAddresses(account: account) }
    private let page = URL(string: "https://en.wikipedia.org/wiki/Mercury_(planet)")!

    override func setUp() {
        super.setUp()
        removeTranscripts()
    }

    override func tearDown() {
        removeTranscripts()
        UserDefaults.standard.removePersistentDomain(forName: "ShareSuggestionTests")
        super.tearDown()
    }

    private nonisolated func transcript(_ outcome: String) -> String {
        (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
    }

    private nonisolated func removeTranscripts() {
        for outcome in ["ok", "fail"] { try? FileManager.default.removeItem(atPath: transcript(outcome)) }
    }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    /// The connection a letter went on, let go of and its transcript
    /// written, so the test leaves neither behind.
    private func lettingGo(_ server: ScriptedSubmission, outcome: String = "ok") async throws {
        try await until {
            await server.isClosed && FileManager.default.fileExists(atPath: self.transcript(outcome))
        }
    }

    // MARK: - Who a letter was written to

    /// To then Cc, each person once whatever the case, the name the letter
    /// gave kept; Bcc left out, since the circle fills To.
    func testTheConversationIsToThenCcWithoutBcc() async throws {
        let draft = Draft(to: ["Carlo Example <carlo@example.org>", "dee@example.com"],
                          cc: ["CARLO@example.org", "\"Ellis, Fay\" <fay@example.com>"],
                          bcc: ["hidden@example.com"])
        let conversation = try XCTUnwrap(SentConversation.of(draft, mine: mine))
        XCTAssertEqual(conversation.people, [
            MailFormat.Recipient(name: "Carlo Example", address: "carlo@example.org"),
            MailFormat.Recipient(name: nil, address: "dee@example.com"),
            MailFormat.Recipient(name: "Ellis, Fay", address: "fay@example.com"),
        ])
        XCTAssertEqual(conversation.identifier, "carlo@example.org,dee@example.com,fay@example.com")
        XCTAssertEqual(conversation.name, "Carlo Example, dee@example.com, Ellis, Fay")
    }

    /// The same people in another order, or in another case, are one
    /// conversation: one circle, not one for each way he wrote them.
    func testTheSamePeopleAreOneConversation() async throws {
        let one = try XCTUnwrap(SentConversation.of(
            Draft(to: ["carlo@example.org"], cc: ["Dee <dee@example.com>"]), mine: mine))
        let other = try XCTUnwrap(SentConversation.of(
            Draft(to: ["DEE@example.com", "Carlo <Carlo@Example.org>"]), mine: mine))
        XCTAssertEqual(one.identifier, other.identifier)
    }

    /// A letter to nobody but himself, at any of his addresses, in any
    /// case, under any name, tells iOS nothing; to him and Carlo, Carlo
    /// alone. One with only a blind copy, an empty group or no address
    /// names nobody either.
    func testHisOwnAddressesAndBlindCopiesNameNobody() async throws {
        XCTAssertNil(SentConversation.of(Draft(to: ["owner@example.com"]), mine: mine))
        XCTAssertNil(SentConversation.of(Draft(to: ["Sam <sam.second@example.net>"],
                                               cc: ["OWNER@example.com"]), mine: mine))
        XCTAssertNil(SentConversation.of(Draft(bcc: ["carlo@example.org"]), mine: mine))
        XCTAssertNil(SentConversation.of(Draft(to: ["undisclosed-recipients:;", "Carlo"]), mine: mine))
        let both = try XCTUnwrap(SentConversation.of(
            Draft(to: ["owner@example.com", "carlo@example.org"]), mine: mine))
        XCTAssertEqual(both.people.map(\.address), ["carlo@example.org"])
    }

    // MARK: - To, for a share opened from a circle

    /// The people iOS hands back, each as the field keeps an entry; the
    /// addresses of the conversation where it hands back no people; and
    /// nobody where it hands back nothing, as a share from Blackmail's
    /// icon begins.
    func testToIsThePeopleOfTheCircle() async throws {
        XCTAssertEqual(SentConversation.to(
            people: [MailFormat.Recipient(name: "Carlo Example", address: "carlo@example.org"),
                     MailFormat.Recipient(name: nil, address: "dee@example.com"),
                     MailFormat.Recipient(name: "Carlo", address: "CARLO@example.org"),
                     MailFormat.Recipient(name: "Nobody", address: "not an address")],
            identifier: "ignored@example.com"),
            ["Carlo Example <carlo@example.org>", "dee@example.com"])
        XCTAssertEqual(SentConversation.to(people: [], identifier: "carlo@example.org,dee@example.com"),
                       ["carlo@example.org", "dee@example.com"])
        XCTAssertEqual(SentConversation.to(people: [], identifier: nil), [])
        XCTAssertEqual(SentConversation.to(people: [], identifier: ""), [])
    }

    /// What one letter told comes back as its To: the circle opens on the
    /// people it went to.
    func testALettersCircleOpensOnItsPeople() async throws {
        let draft = Draft(to: ["Carlo Example <carlo@example.org>"], cc: ["dee@example.com"])
        let conversation = try XCTUnwrap(SentConversation.of(draft, mine: mine))
        XCTAssertEqual(SentConversation.to(people: conversation.people, identifier: conversation.identifier),
                       draft.to + draft.cc)
        XCTAssertEqual(SentConversation.to(people: [], identifier: conversation.identifier),
                       ["carlo@example.org", "dee@example.com"])
    }

    // MARK: - From the app: the repository's send

    private func repository(_ server: ScriptedSubmission, told: Told) -> IMAPMailRepository {
        let book = RecipientBook(defaults: UserDefaults(suiteName: "ShareSuggestionTests")!)
        return IMAPMailRepository(account: account, password: "app-password",
                                  transport: { _, _ in server }, recipients: book,
                                  signatureImages: { [] },
                                  donate: { told.add($0) })
    }

    /// A letter the server took: told once, by the people it went to.
    func testALetterFromTheAppThatWentIsTold() async throws {
        let server = ScriptedSubmission()
        let told = Told()
        let app = repository(server, told: told)

        try await app.send(Draft(to: ["Carlo <carlo@example.org>"], cc: ["owner@example.com"],
                                        subject: "The garden", body: "Hello"), progress: nil)

        XCTAssertEqual(told.all.map(\.people),
                       [[MailFormat.Recipient(name: "Carlo", address: "carlo@example.org")]])
        try await lettingGo(server)
    }

    /// A letter the server refused tells nothing, and nor does one to
    /// nobody but himself that went.
    func testALetterFromTheAppThatDidNotGoOrWentToHimIsNotTold() async throws {
        let refusing = ScriptedSubmission(letterReply: "552 5.3.4 Message too big")
        let told = Told()
        do {
            try await repository(refusing, told: told).send(
                Draft(to: ["carlo@example.org"], subject: "Big", body: "Hello"), progress: nil)
            XCTFail("the server refused it")
        } catch {}
        try await lettingGo(refusing, outcome: "fail")
        XCTAssertTrue(told.all.isEmpty)

        removeTranscripts()
        let server = ScriptedSubmission()
        try await repository(server, told: told).send(
            Draft(to: ["sam.second@example.net"], subject: "A link", body: "Hello"), progress: nil)
        let letters = await server.letters
        XCTAssertEqual(letters.count, 1, "it went")
        XCTAssertTrue(told.all.isEmpty)
        try await lettingGo(server)
    }

    // MARK: - From the share sheet

    private var log: [String] = []
    private var told: [SentConversation] = []

    private func sheet(_ server: ScriptedSubmission, circle: [String] = []) -> ShareSheet {
        ShareSheet(
            shared: ShareMirror.Shared(account: account, password: "app-password",
                                       signatureImages: [], recipients: []),
            transport: { _, _ in server },
            readFile: { _ in Data() },
            noteSent: { _ in },
            finish: { [unowned self] in log.append("finish") },
            cancel: { [unowned self] in log.append("cancel") },
            showError: { [unowned self] _ in log.append("error") },
            draw: { _ in },
            background: BackgroundTime(begin: { _, _ in nil }, end: { _ in }),
            circle: circle,
            donate: { [unowned self] in told.append($0) })
    }

    /// A share that went is told once, as the app's letters are; one that
    /// did not is not, nor one to nobody but himself.
    func testAShareThatWentIsToldAndOneThatDidNotIsNot() async throws {
        let server = ScriptedSubmission()
        let sent = sheet(server)
        var draft = sent.letter(from: [.link(page, title: "Mercury")])
        draft.to = ["Carlo <carlo@example.org>"]
        await sent.send { draft }?.value
        XCTAssertEqual(log, ["finish"])
        XCTAssertEqual(told.map(\.identifier), ["carlo@example.org"])
        try await lettingGo(server)

        removeTranscripts()
        let offline = sheet(ScriptedSubmission(failsToOpen: true))
        await offline.send { draft }?.value
        XCTAssertEqual(log, ["finish", "error"])
        XCTAssertEqual(told.count, 1, "nothing more for a share that did not go")

        let toHim = ScriptedSubmission()
        let mineOnly = sheet(toHim)
        var own = mineOnly.letter(from: [.link(page, title: "Mercury")])
        own.to = ["sam.second@example.net"]
        await mineOnly.send { own }?.value
        XCTAssertEqual(log, ["finish", "error", "finish"])
        XCTAssertEqual(told.count, 1, "nothing for one to him alone")
        try await lettingGo(toHim)
    }

    /// A share opened from a circle begins with its people in To, which
    /// Cancel asks nothing about, as it began so; and the letter goes to
    /// them.
    func testAShareFromACircleBeginsWithItsPeopleInTo() async throws {
        let server = ScriptedSubmission()
        let to = SentConversation.to(people: [MailFormat.Recipient(name: "Carlo", address: "carlo@example.org")],
                                     identifier: "carlo@example.org")
        let sheet = sheet(server, circle: to)
        let draft = sheet.letter(from: [.link(page, title: "Mercury")])
        XCTAssertEqual(draft.to, ["Carlo <carlo@example.org>"])
        XCTAssertFalse(sheet.asksBeforeCancelling(draft), "as the share began it")
        var emptied = draft
        emptied.to = []
        XCTAssertTrue(sheet.asksBeforeCancelling(emptied), "Carlo taken out is his doing")

        await sheet.send { draft }?.value
        let commands = await server.commands
        XCTAssertTrue(commands.contains("RCPT TO:<carlo@example.org>"), "\(commands)")
        try await lettingGo(server)
    }

    // MARK: - Declared, and wired, as Apple has it

    private func file(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    private func plist(_ name: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/\(name)")
        return try XCTUnwrap(PropertyListSerialization.propertyList(
            from: try Data(contentsOf: url), format: nil) as? [String: Any])
    }

    /// The share extension takes the intent, as Apple's "Supporting
    /// suggestions in your app's share extension" has it, and the app
    /// names the one it tells iOS of.
    func testBothBundlesDeclareTheIntent() async throws {
        let share = try plist("ShareInfo.plist")
        let ext = try XCTUnwrap(share["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(ext["NSExtensionAttributes"] as? [String: Any])
        XCTAssertEqual(attributes["IntentsSupported"] as? [String], ["INSendMessageIntent"])
        let app = try plist("Info.plist")
        XCTAssertEqual(app["NSUserActivityTypes"] as? [String], ["INSendMessageIntent"])
    }

    /// The device's half, read from the source, as it never builds here:
    /// the sheet's To from the intent it was opened with, its letters told
    /// by the one call, Intents linked, and what was told taken back with
    /// the account.
    func testTheDeviceHalfIsWired() async throws {
        let sheet = try file("Sources/Blackmail/Share/ShareViewController.swift")
        XCTAssertTrue(sheet.contains("import Intents"))
        XCTAssertTrue(sheet.contains("guard let intent = extensionContext?.intent as? INSendMessageIntent else { return [] }"))
        XCTAssertTrue(sheet.contains("SentConversation.to(people: people, identifier: intent.conversationIdentifier)"))
        XCTAssertTrue(sheet.contains("shared: shared, items: items, leftOut: line, to: circle(),"))
        XCTAssertTrue(sheet.contains("background: .extensionTime, circle: to, "
                                     + "donate: SentConversation.donate) draft = sheet.letter(from: items)"))

        let told = try file("Sources/Blackmail/Share/SentConversation.swift")
        XCTAssertTrue(told.contains("interaction.direction = .outgoing"))
        XCTAssertTrue(told.contains("conversationIdentifier: conversation.identifier"))
        XCTAssertTrue(told.contains("guard ShareMirror.app != nil else { return }"))

        let package = try file("Package.swift")
        XCTAssertTrue(package.contains(".linkedFramework(\"Intents\", .when(platforms: [.iOS]))"))

        let store = try file("Sources/Blackmail/Mail/CredentialStore.swift")
        let clear = try XCTUnwrap(store.range(of: "static func clear() {"))
        let end = try XCTUnwrap(store.range(of: "private static func baseQuery("))
        XCTAssertTrue(store[clear.upperBound..<end.lowerBound].contains("SentConversation.forgetAll()"))
    }
}

/// What a repository told, from any thread.
private final class Told: @unchecked Sendable {
    private let lock = NSLock()
    private var told: [SentConversation] = []

    var all: [SentConversation] {
        lock.lock()
        defer { lock.unlock() }
        return told
    }

    func add(_ conversation: SentConversation) {
        lock.lock()
        told.append(conversation)
        lock.unlock()
    }
}
