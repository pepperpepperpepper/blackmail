import XCTest
@testable import Blackmail

/// A name changed in Settings, at once (B-082). The name was saved and the
/// next reply still went out From the old one; only a quit and a reopen
/// put the new name on his letters. The repository kept the account it was
/// made with at launch, and every letter it made took the name, the
/// signature and its formatted twin from that. Here what Settings saves is
/// taken as each letter is made (`MailAccount.withSettings`), and the
/// book of addresses offers his own address under the name saved
/// (`RecipientBook.noteOwn`).
final class NameAtOnceTests: XCTestCase {

    private let launched = MailAccount(address: "owner@example.com", username: "owner@example.com",
                                       displayName: "Carlo", signature: "Carlo",
                                       signatureHTML: "<b>Carlo</b>",
                                       otherAddresses: ["carlo.home@example.com"])

    /// The name, the signature and its twin, and his other addresses come
    /// from the account saved; where it connects and as whom stay the
    /// account's own.
    func testWhatSettingsSavesIsTaken() {
        var saved = launched
        saved.address = " Owner@Example.com "
        saved.displayName = "Carlo Wolfeschlegelsteinhausen Example"
        saved.signature = "Carlo W. Example"
        saved.signatureHTML = ""
        saved.otherAddresses = []
        saved.imapHost = "imap.example.net"
        saved.username = "someone@example.net"
        let taken = launched.withSettings(of: saved)
        XCTAssertEqual(taken.displayName, "Carlo Wolfeschlegelsteinhausen Example")
        XCTAssertEqual(taken.signature, "Carlo W. Example")
        XCTAssertEqual(taken.signatureHTML, "")
        XCTAssertEqual(taken.otherAddresses, [])
        XCTAssertEqual(taken.address, "owner@example.com")
        XCTAssertEqual(taken.imapHost, "imap.gmail.com")
        XCTAssertEqual(taken.username, "owner@example.com")
    }

    /// Another address's account, or none, changes nothing.
    func testAnotherAccountOrNoneChangesNothing() {
        var other = launched
        other.address = "someone@example.net"
        other.displayName = "Someone"
        XCTAssertEqual(launched.withSettings(of: other), launched)
        XCTAssertEqual(launched.withSettings(of: nil), launched)
    }

    // MARK: - The book

    private static let suite = "NameAtOnceTests"

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        super.tearDown()
    }

    private func offered(_ typed: String, in book: RecipientBook) -> [String] {
        var field = RecipientBubbles()
        field.type(typed)
        return ComposeForm.suggestions(book.snapshot(), in: field, after: .typed).map(\.display)
    }

    /// His own address under the name saved, in place of the one before;
    /// none when the account has none. Other people's names are learned
    /// as they always were.
    func testHisOwnAddressIsOfferedUnderTheNameSaved() {
        let book = RecipientBook(defaults: UserDefaults(suiteName: Self.suite)!)
        book.noteOwn(address: "owner@example.com", name: "Carlo")
        XCTAssertEqual(offered("own", in: book), ["Carlo"])
        book.noteOwn(address: " Owner@Example.com ", name: " Carlo Wolfeschlegelsteinhausen Example ")
        XCTAssertEqual(offered("own", in: book), ["Carlo Wolfeschlegelsteinhausen Example"])
        XCTAssertEqual(offered("wolf", in: book), ["Carlo Wolfeschlegelsteinhausen Example"])
        XCTAssertEqual(book.snapshot().map(\.address), ["owner@example.com"])
        book.noteOwn(address: "owner@example.com", name: "  ")
        XCTAssertEqual(offered("own", in: book), ["owner@example.com"])
        XCTAssertEqual(offered("carlo", in: book), [])

        book.note(address: "jane@example.com", name: "Jane Example")
        XCTAssertEqual(offered("jan", in: book), ["Jane Example"])
        book.noteOwn(address: "a@example.com; b@example.com", name: "Carlo")
        XCTAssertEqual(book.snapshot().map(\.address).sorted(), ["jane@example.com", "owner@example.com"],
                       "two addresses are not his one")
    }
}

/// The letters themselves over the scripted servers (B-082): after Save,
/// without a relaunch, a new letter, Reply, Reply All and Forward, a draft
/// saved to Gmail and one sent from Drafts, a letter from the Outbox, and
/// a shared one all go From the name saved; the signature's formatted twin
/// as saved too. Put back, the name before goes again.
@MainActor
final class NameAtOnceSendTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "NameAtOnceSendTests"
    private static let newName = "Carlo Wolfeschlegelsteinhausen Example"

    private var server: ScriptedIMAPServer!
    private var saved: SavedAccount!
    private var line: Line!
    private var submissions: Submissions!
    private var book: RecipientBook!
    private var root: URL!
    private var passTime = FakeBackground()

    override func setUp() async throws {
        try await super.setUp()
        server = ScriptedIMAPServer()
        saved = SavedAccount(launched)
        line = Line()
        submissions = Submissions()
        passTime = FakeBackground()
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: UserDefaults(suiteName: Self.suite)!)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NameAtOnceTests-\(UUID().uuidString)", isDirectory: true)
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
        server = nil
        saved = nil
        line = nil
        submissions = nil
        book = nil
        root = nil
        try await super.tearDown()
    }

    /// The account as the app launched with it: named, with a signature
    /// and its formatted twin.
    private var launched: MailAccount {
        var account = server.account
        account.displayName = "Carlo"
        account.signature = "Carlo\n1 Example Street"
        account.signatureHTML = "<table><tr><td><b>Carlo</b></td></tr></table>"
        return account
    }

    /// The app's repository over the scripted servers, made at launch with
    /// `launched`, reading what Settings saved from `saved`.
    private func makeRepository() -> IMAPMailRepository {
        let imap = server.transportFactory
        let line = self.line!
        let saved = self.saved!
        let submissions = self.submissions!
        return IMAPMailRepository(
            account: launched, password: server.password,
            transport: { host, port in
                guard line.isUp else {
                    return port == 465 ? ScriptedSubmission(failsToOpen: true) : imap(host, 1)
                }
                return port == 465 ? submissions.next() : imap(host, port)
            },
            saved: { saved.account },
            recipients: book,
            signatureImages: { [] },
            shelf: keptShelf(for: server.account))
    }

    /// Save in Settings: the account stored with `change` made to it, as
    /// `CredentialStore.saveAccountOnly` stores it, and his own address
    /// noted under its name, as it is noted there.
    private func save(_ change: (inout MailAccount) -> Void) {
        var account = saved.account ?? launched
        change(&account)
        saved.account = account
        book.noteOwn(address: account.address, name: account.displayName)
    }

    private func rename(_ name: String) {
        save { $0.displayName = name }
    }

    private func made() -> [ScriptedSubmission] { submissions.all }

    /// The last letter that went, as it went.
    private func lastSent() async throws -> Data {
        let submission = try XCTUnwrap(made().last)
        let letters = await submission.letters
        XCTAssertEqual(letters.count, 1)
        return try XCTUnwrap(letters.first)
    }

    private func from(_ raw: Data) -> String? {
        MIMEDecoder.headerValue("From", in: MIMEDecoder.parseHeaders(raw)).map(MIMEDecoder.decodeWord)
    }

    private func newLetter(_ subject: String = "B-082 a new letter") -> Draft {
        var draft = Draft.blank(signature: saved.account?.signature ?? "")
        draft.to = ["jane@example.com"]
        draft.subject = subject
        draft.body = "Lunch at one?" + draft.body
        return draft
    }

    /// A letter from Sam in the Inbox, opened.
    private func samsLetter(_ repository: IMAPMailRepository) async throws -> Message {
        let letter = Server.Letter(from: Server.sam, to: [Server.owner, Server.jane],
                                   subject: "B-082 Thursday", date: Server.newestDate,
                                   text: "Are you free?\r\n", messageID: "<thursday@example.com>")
        let uid = try XCTUnwrap(server.deliver(letter, to: [Server.inbox])[Server.inbox])
        return try await repository.loadMessage(id: "\(server.uidValidity(of: Server.inbox))/\(uid)",
                                                mailboxID: Server.inbox)
    }

    private var drafts: [UInt32] { server.uids(in: Server.drafts) }

    private func draftRaw() throws -> Data {
        try XCTUnwrap(server.raw(uid: try XCTUnwrap(drafts.last), in: Server.drafts))
    }

    // MARK: - New, Reply, Reply All, Forward

    /// The next letter after Save goes From the name saved, with no
    /// relaunch; put back, the name before.
    func testTheNextLetterAfterSaveGoesUnderTheNameSaved() async throws {
        let repository = makeRepository()
        try await repository.send(newLetter())
        let sent1 = try await lastSent()
        XCTAssertEqual(from(sent1), "Carlo <\(server.username)>")

        rename(Self.newName)
        try await repository.send(newLetter())
        let sent2 = try await lastSent()
        XCTAssertEqual(from(sent2), "\(Self.newName) <\(server.username)>")

        rename("Carlo")
        try await repository.send(newLetter())
        let sent3 = try await lastSent()
        XCTAssertEqual(from(sent3), "Carlo <\(server.username)>")
    }

    /// Reply, Reply All and Forward, written after Save, as the pane makes
    /// them, go From the name saved.
    func testReplyReplyAllAndForwardGoUnderTheNameSaved() async throws {
        let repository = makeRepository()
        let m = try await samsLetter(repository)
        rename(Self.newName)
        let account = try XCTUnwrap(saved.account)
        let mine = OwnAddresses(account: account)
        let letters = [Draft.replying(to: m, all: false, mine: mine, signature: account.signature),
                       Draft.replying(to: m, all: true, mine: mine, signature: account.signature),
                       Draft.forwarding(m, signature: account.signature)]
        for var draft in letters {
            if draft.to.isEmpty { draft.to = ["jane@example.com"] }
            draft.body = "Yes.\n" + draft.body
            try await repository.send(draft)
            let sent4 = try await lastSent()
            XCTAssertEqual(from(sent4), "\(Self.newName) <\(server.username)>",
                           draft.subject)
        }
        XCTAssertEqual(made().count, 3)
    }

    // MARK: - Drafts

    /// A draft saved to Gmail after Save carries the name saved, by the
    /// repository and by the pass that takes a letter kept on the iPad up;
    /// a draft saved before, reopened from Drafts and sent after, goes
    /// From the name saved, as one would after a relaunch.
    func testDraftsAndALetterSentFromDraftsTakeTheNameSaved() async throws {
        let repository = makeRepository()
        var before = newLetter("B-082 a draft before")
        before.body = "Half a thought." + Draft.blank(signature: launched.signature).body
        _ = try await repository.saveDraft(before)
        XCTAssertEqual(from(try draftRaw()), "Carlo <\(server.username)>")
        let saidBefore = try XCTUnwrap(drafts.last)

        rename(Self.newName)
        _ = try await repository.saveDraft(newLetter("B-082 a draft after"))
        XCTAssertEqual(from(try draftRaw()), "\(Self.newName) <\(server.username)>")

        let kept = makeKept()
        try await kept.save(newLetter("B-082 a kept draft"), as: "letter-1", to: repository)
        XCTAssertEqual(from(try draftRaw()), "\(Self.newName) <\(server.username)>")

        let reopened = try await repository.loadDraft(
            id: "\(server.uidValidity(of: Server.drafts))/\(saidBefore)", gmailMessageID: nil,
            mailboxID: Server.drafts)
        try await repository.send(reopened)
        let sent5 = try await lastSent()
        XCTAssertEqual(from(sent5), "\(Self.newName) <\(server.username)>")
    }

    /// A letter left in the Outbox before Save goes, once the line is back,
    /// From the name saved, as it would after a relaunch: what he wrote is
    /// kept, and the letter is made as it goes.
    func testALetterInTheOutboxGoesUnderTheNameSavedWhenItGoes() async throws {
        let repository = makeRepository()
        let kept = makeKept()
        line.isUp = false
        kept.opened("letter-1")
        do {
            try await kept.send(newLetter("B-082 from the Outbox"), as: "letter-1", to: repository,
                                progress: nil)
            XCTFail("the line is down")
        } catch is Outbox.Waiting {
        }
        kept.closed("letter-1")
        XCTAssertEqual(kept.outboxRows.count, 1)
        XCTAssertEqual(made().count, 0)

        rename(Self.newName)
        line.isUp = true
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        await kept.uploadWaiting(to: repository)?.value
        XCTAssertEqual(kept.outboxRows.count, 0)
        XCTAssertEqual(made().count, 1)
        let sent6 = try await lastSent()
        XCTAssertEqual(from(sent6), "\(Self.newName) <\(server.username)>")
    }

    // MARK: - The signature

    /// "Send my signature as plain text instead", saved: the next letter
    /// goes without the formatted twin. Restored, it goes with it again.
    func testTheFormattedSignatureFollowsWhatIsSaved() async throws {
        let repository = makeRepository()
        try await repository.send(newLetter())
        let sent7 = try await lastSent()
        XCTAssertTrue(MIMEDecoder.decodeMessage(sent7).html?
                        .contains("<b>Carlo</b>") == true)

        save { $0.signatureHTML = "" }
        try await repository.send(newLetter())
        let plain = MIMEDecoder.decodeMessage(try await lastSent())
        XCTAssertNil(plain.html, "as plain text")
        XCTAssertTrue(plain.text?.contains("1 Example Street") == true)

        save { $0.signatureHTML = launched.signatureHTML }
        try await repository.send(newLetter())
        let sent8 = try await lastSent()
        XCTAssertTrue(MIMEDecoder.decodeMessage(sent8).html?
                        .contains("<b>Carlo</b>") == true)
    }

    /// A signature changed in Settings is found at the foot of the next
    /// letter, which the composer signs with it, and its formatted twin
    /// goes with it. The old text was looked for, not found, and the twin
    /// left off until a relaunch.
    func testAChangedSignatureIsFoundInTheNextLetter() async throws {
        let repository = makeRepository()
        save { $0.signature = "Carlo W. Example\n1 Example Street" }
        try await repository.send(newLetter())
        let letter = MIMEDecoder.decodeMessage(try await lastSent())
        XCTAssertTrue(letter.text?.contains("Carlo W. Example") == true)
        let html = try XCTUnwrap(letter.html, "the twin goes")
        XCTAssertTrue(html.contains("<b>Carlo</b>"), html)
    }

    // MARK: - The book

    /// His own address is offered under the name saved, and a page of his
    /// old letters, From the name he had then, does not put it back. Made
    /// again, as at the next launch, the repository notes the name saved.
    func testTheBookKeepsTheNameSavedForHisAddress() async throws {
        let repository = makeRepository()
        func offered() -> [String] {
            var field = RecipientBubbles()
            field.type("own")
            return ComposeForm.suggestions(book.snapshot(), in: field, after: .typed).map(\.display)
        }
        XCTAssertEqual(offered(), ["Carlo"])
        rename(Self.newName)
        XCTAssertEqual(offered(), [Self.newName])

        let himself = Server.Address(name: "Carlo", address: server.username)
        server.deliver(Server.Letter(from: himself, to: [himself], subject: "B-082 to himself",
                                     date: Server.newestDate.addingTimeInterval(60),
                                     text: "A note.\r\n", messageID: "<note@example.com>"),
                       to: [Server.inbox])
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        XCTAssertEqual(offered(), [Self.newName], "an old letter does not name him")

        // A name an earlier build learned from such a letter is replaced
        // by the name saved at the next launch.
        book.note(address: server.username, name: "Carlo")
        XCTAssertEqual(offered(), ["Carlo"])
        let relaunched = IMAPMailRepository(account: try XCTUnwrap(saved.account),
                                            password: server.password,
                                            transport: server.transportFactory,
                                            recipients: book, signatureImages: { [] })
        XCTAssertEqual(offered(), [Self.newName])
        await relaunched.retire()
    }

    /// The name taken off in Settings: his address is offered bare, as his
    /// letters now go, and stays so past a page of his old letters and the
    /// next launch, whatever name the book had learned.
    func testANameTakenOffLeavesHisAddressBare() async throws {
        let repository = makeRepository()
        func offered() -> [String] {
            var field = RecipientBubbles()
            field.type("own")
            return ComposeForm.suggestions(book.snapshot(), in: field, after: .typed).map(\.display)
        }
        XCTAssertEqual(offered(), ["Carlo"])
        rename("")
        XCTAssertEqual(offered(), [server.username])
        try await repository.send(newLetter())
        let sent = try await lastSent()
        XCTAssertEqual(from(sent), server.username)

        let himself = Server.Address(name: "Carlo", address: server.username)
        server.deliver(Server.Letter(from: himself, to: [himself], subject: "B-082 to himself",
                                     date: Server.newestDate.addingTimeInterval(60),
                                     text: "A note.\r\n", messageID: "<note@example.com>"),
                       to: [Server.inbox])
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        XCTAssertEqual(offered(), [server.username], "an old letter does not name him")

        book.note(address: server.username, name: "Carlo")
        let relaunched = IMAPMailRepository(account: try XCTUnwrap(saved.account),
                                            password: server.password,
                                            transport: server.transportFactory,
                                            recipients: book, signatureImages: { [] })
        XCTAssertEqual(offered(), [server.username], "the next launch")
        await relaunched.retire()
    }

    // MARK: - The share sheet

    /// The share extension's copy of the account, handed the one saved, as
    /// `CredentialStore.saveAccountOnly` hands it over at Save: the next
    /// share goes From the name saved.
    func testTheNextShareGoesUnderTheNameSaved() async throws {
        let mirror = ShareMirror(keychain: MemoryKeychain())
        mirror.publish(account: launched, password: "app-password")
        var renamed = launched
        renamed.displayName = Self.newName
        mirror.publish(account: renamed, password: "app-password")

        let shared = try XCTUnwrap(mirror.load())
        let server = ScriptedSubmission()
        let sheet = ShareSheet(
            shared: shared,
            transport: { _, _ in server },
            noteSent: { _ in }, finish: {}, cancel: {}, showError: { XCTFail("\($0)") },
            draw: { _ in },
            background: BackgroundTime(begin: { _, _ in nil }, end: { _ in }))
        var draft = sheet.letter(from: [.link(URL(string: "https://example.com/garden")!,
                                              title: "B-082 shared")])
        draft.to = ["jane@example.com"]
        await sheet.send { draft }?.value
        let letters = await server.letters
        XCTAssertEqual(letters.count, 1)
        XCTAssertEqual(from(try XCTUnwrap(letters.first)), "\(Self.newName) <\(launched.address)>")
    }

    // MARK: - Helpers

    /// The app's `LocalDrafts` over this test's directory.
    private func makeKept() -> LocalDrafts {
        let clock = ManualClock()
        let store = LocalDraftStore(root: root, now: {
            clock.advance(by: 1)
            return clock.now()
        })
        return LocalDrafts(store: store, account: server.username, background: passTime.time)
    }
}

/// What `CredentialStore` keeps, as Settings saves it.
private final class SavedAccount: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: MailAccount?

    init(_ account: MailAccount?) { stored = account }

    var account: MailAccount? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// A submission server per connection, as the SMTP client makes one per
/// letter.
private final class Submissions: @unchecked Sendable {
    private let lock = NSLock()
    private var servers: [ScriptedSubmission] = []

    func next() -> ScriptedSubmission {
        lock.lock()
        defer { lock.unlock() }
        let server = ScriptedSubmission()
        servers.append(server)
        return server
    }

    var all: [ScriptedSubmission] {
        lock.lock()
        defer { lock.unlock() }
        return servers
    }
}

/// Whether the line is up: down, every connection is refused.
private final class Line: @unchecked Sendable {
    private let lock = NSLock()
    private var up = true

    var isUp: Bool {
        get { lock.lock(); defer { lock.unlock() }; return up }
        set { lock.lock(); up = newValue; lock.unlock() }
    }
}

/// The shared Keychain group as a dictionary.
private final class MemoryKeychain: SharedKeychain {
    private var items: [String: Data] = [:]
    func data(named name: String) -> Data? { items[name] }
    func store(_ data: Data, named name: String) -> Bool {
        items[name] = data
        return true
    }
    func remove(named name: String) { items[name] = nil }
    func names() -> [String] { Array(items.keys) }
}

/// The wiring the host cannot run: UIKit, and the Keychain.
final class NameAtOnceWiringTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    /// The app's repository reads the account Settings saved, where
    /// Settings saves it.
    func testTheAppsRepositoryReadsTheAccountSaved() throws {
        let repository = try source("Mail/IMAPMailRepository.swift")
        XCTAssertTrue(repository.contains(
            "self.init(account: account, password: password, transport: TLSConnection.factory, "
            + "saved: { CredentialStore.loadAccount() },"), "the app's init")
    }

    /// Save in Settings hands the account saved to the share extension and
    /// his name to the book, and does not touch the password.
    func testSaveHandsTheNameOnAtOnce() throws {
        let store = try source("Mail/CredentialStore.swift")
        let start = try XCTUnwrap(store.range(of: "static func saveAccountOnly("))
        let end = try XCTUnwrap(store.range(of: "static func save(account:", range: start.upperBound..<store.endIndex))
        let body = String(store[start.upperBound..<end.lowerBound])
        XCTAssertTrue(body.contains("RecipientBook.shared.noteOwn(address: clean.address, name: clean.displayName)"))
        XCTAssertTrue(body.contains("mirror.publish(account: clean, password: password)"))
        XCTAssertFalse(body.contains("writePassword"))
    }

    /// Settings' Save, without a password, changes nothing but the list's
    /// note of his addresses: no screen is built again, the connection is
    /// not touched, and a new password still signs in afresh once the sheet
    /// has gone.
    func testSaveRebuildsNothing() throws {
        let list = try source("UI/MessageListViewController.swift")
        let start = try XCTUnwrap(list.range(of: "settings.onSaved = { [weak self] saved in"))
        let end = try XCTUnwrap(list.range(of: "settings.onPasswordSaved", range: start.upperBound..<list.endIndex))
        let onSaved = String(list[start.upperBound..<end.lowerBound])
        XCTAssertTrue(onSaved.contains("self.mine = OwnAddresses(account: saved)"))
        for rebuild in ["RootViewController(", "IMAPMailRepository(", "retire", "onPasswordSaved"] {
            XCTAssertFalse(onSaved.contains(rebuild), rebuild)
        }
        let settings = try source("UI/SettingsViewController.swift")
        XCTAssertTrue(settings.contains("let signIn = onPasswordSaved dismiss(animated: true) { signIn?(updated, password, notice) }"))
    }
}
