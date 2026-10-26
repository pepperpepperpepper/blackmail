import XCTest
@testable import Blackmail

/// His Contacts in the address fields' list, beside the book of the people
/// he has written to (B-162), as Mail suggests them: nothing until he
/// types; the start of a first name, a last name or the address; each
/// address of a contact with several; the people he has written to first,
/// then his Contacts, then the addresses only seen; a person named as
/// Contacts names them. Made-up cards in Contacts' order stand in for the
/// iPad's, which the suite cannot read. The question iOS asks, the reading
/// and the share extension's copy are read from the source.
final class ContactSuggestionsTests: XCTestCase {

    private let seen = Date(timeIntervalSince1970: 1_700_000_000)

    /// As Contacts lists them.
    private let cards = [
        ContactCard(name: "Sam Carlo", givenName: "Sam", familyName: "Carlo",
                    addresses: ["sam@example.com", "SCarlo@Example.org"]),
        ContactCard(name: "Pat Núñez", givenName: "Pat", familyName: "Núñez",
                    addresses: ["pat@example.net"]),
        ContactCard(name: "Jo Pine", givenName: "Jo", familyName: "Pine", addresses: []),
    ]

    private func written(_ address: String, _ name: String?, uses: Int = 3) -> KnownRecipient {
        KnownRecipient(address: address, name: name, uses: uses, lastSeen: seen)
    }

    private func seenOnly(_ address: String, _ name: String?) -> KnownRecipient {
        KnownRecipient(address: address, name: name, uses: 0, lastSeen: seen.addingTimeInterval(60))
    }

    private func offered(_ field: String, book: [KnownRecipient] = [],
                         cards: [ContactCard]? = nil) -> [String] {
        ComposeForm.suggestions(book, contacts: cards ?? self.cards, field: field, after: .typed)
            .map(\.address)
    }

    // MARK: - Nothing until he types (B-073)

    /// Going in, a pick and a bubble tapped offer nothing; nor do nothing
    /// typed, spaces, or what he typed once it holds an "@".
    func testNothingUntilHeTypes() {
        for event in [ComposeForm.FieldEvent.entered, .picked, .bubbleTapped] {
            XCTAssertEqual(ComposeForm.suggestions([], contacts: cards, field: "sa", after: event), [])
        }
        for field in ["", "  ", "sam@", "owner@example.com, "] {
            XCTAssertEqual(offered(field), [], field)
        }
    }

    // MARK: - What matches

    /// The start of the first name or of the last name, in any case,
    /// accents aside; "sam c" too. Never within a word.
    func testTheStartOfAFirstOrLastNameFindsAContact() {
        let sam = ["sam@example.com", "scarlo@example.org"]
        XCTAssertEqual(offered("sa"), sam)
        XCTAssertEqual(offered("Car"), sam)
        XCTAssertEqual(offered("sam c"), sam)
        XCTAssertEqual(offered("nun"), ["pat@example.net"])
        XCTAssertEqual(offered("NÚÑ"), ["pat@example.net"])
        for within in ["am", "arlo", "uñez", "ex"] {
            XCTAssertEqual(offered(within), [], within)
        }
    }

    /// The start of an address finds that address alone, not the card's
    /// others.
    func testTheStartOfAnAddressFindsThatAddress() {
        XCTAssertEqual(offered("scar"), ["scarlo@example.org"])
        XCTAssertEqual(offered("pat"), ["pat@example.net"])
    }

    /// Each address of a contact with several, in the card's order, each
    /// under the name Contacts shows, the address under it; a card with no
    /// address is nobody to write to.
    func testEachAddressOfAContactIsOfferedUnderItsContactsName() {
        let rows = ComposeForm.suggestions([], contacts: cards, field: "sam", after: .typed)
        XCTAssertEqual(rows.map(\.address), ["sam@example.com", "scarlo@example.org"])
        XCTAssertEqual(rows.map(\.display), ["Sam Carlo", "Sam Carlo"])
        XCTAssertEqual(offered("jo"), [])
        XCTAssertEqual(offered("pin"), [])
    }

    // MARK: - The order

    /// The people he has written to first, then his Contacts in Contacts'
    /// order, then the addresses only seen go past.
    func testWrittenToFirstThenContactsThenSeen() {
        let book = [seenOnly("sales@example.org", "Sales"), written("sal@example.com", "Sal")]
        XCTAssertEqual(offered("sa", book: book),
                       ["sal@example.com", "sam@example.com", "scarlo@example.org", "sales@example.org"])
        // Contacts' order, not the alphabet's, by name or by address.
        let pam = ContactCard(name: "Pam Sole", addresses: ["a.sole@example.com"])
        XCTAssertEqual(offered("p", cards: [cards[1], cards[0], pam]),
                       ["pat@example.net", "a.sole@example.com"])
        XCTAssertEqual(offered("p", cards: [pam, cards[0], cards[1]]),
                       ["a.sole@example.com", "pat@example.net"])
    }

    /// The group decides before how it matched: an address he has written
    /// to, found only by the start of its address, still comes before a
    /// card and an address only seen, each found by a name.
    func testWrittenToFirstHoweverItMatched() {
        let carlZ = [ContactCard(name: "Carl Z", givenName: "Carl", familyName: "Z",
                                 addresses: ["z@example.com"])]
        let book = [written("carlo@example.com", nil, uses: 2), seenOnly("x@example.org", "Carl Seen")]
        XCTAssertEqual(offered("carl", book: book, cards: carlZ),
                       ["carlo@example.com", "z@example.com", "x@example.org"])
        XCTAssertEqual(offered("carl", book: [written("carla@example.com", nil, uses: 2)], cards: carlZ),
                       ["carla@example.com", "z@example.com"])
    }

    /// An address both in the book and on a card is one row, named as
    /// Contacts names it: first when he has written to it, among his
    /// Contacts when the book has only seen it.
    func testAnAddressInBothIsOneRowNamedAsInContacts() {
        let book = [written("scarlo@example.org", "Skip"), seenOnly("sam@example.com", "Sammy"),
                    seenOnly("pa@example.org", "Pa")]
        let rows = ComposeForm.suggestions(book, contacts: cards, field: "sa", after: .typed)
        XCTAssertEqual(rows.map(\.address), ["scarlo@example.org", "sam@example.com"])
        XCTAssertEqual(rows.map(\.display), ["Sam Carlo", "Sam Carlo"])
        XCTAssertEqual(rows.first?.uses, 3)
        // Seen, and on a card: among his Contacts, ahead of the seen.
        XCTAssertEqual(offered("pa", book: book), ["pat@example.net", "pa@example.org"])
        // Found by the name the book has for it too, and named as in
        // Contacts.
        let skip = ComposeForm.suggestions(book, contacts: cards, field: "sk", after: .typed)
        XCTAssertEqual(skip.map(\.address), ["scarlo@example.org"])
        XCTAssertEqual(skip.map(\.display), ["Sam Carlo"])
    }

    /// The book's own matches within an address or a name (B-017), which
    /// Mail does not make, come after every start, his Contacts' too.
    func testTheBooksMatchesWithinComeLast() {
        let book = [written("oscar@example.com", nil, uses: 9)]
        XCTAssertEqual(offered("car", book: book),
                       ["sam@example.com", "scarlo@example.org", "oscar@example.com"])
    }

    /// Four rows at most, as ever.
    func testFourRowsAtMost() {
        let many = (1...6).map { ContactCard(name: "Sam \($0)", addresses: ["sam\($0)@example.com"]) }
        XCTAssertEqual(offered("sam", cards: many).count, RecipientBook.suggestionLimit)
        XCTAssertEqual(offered("sam", cards: many),
                       ["sam1@example.com", "sam2@example.com", "sam3@example.com", "sam4@example.com"])
    }

    /// An address on two cards is offered once, under the first.
    func testAnAddressOnTwoCardsIsOfferedOnce() {
        let twice = [ContactCard(name: "Sam Carlo", addresses: ["sam@example.com"]),
                     ContactCard(name: "Sam Work", addresses: ["SAM@example.com", "sam@example.com"])]
        let rows = ComposeForm.suggestions([], contacts: twice, field: "sam", after: .typed)
        XCTAssertEqual(rows.map(\.address), ["sam@example.com"])
        XCTAssertEqual(rows.map(\.display), ["Sam Carlo"])
    }

    /// Nobody already in the field, typed or a bubble, in any spelling.
    func testNobodyAlreadyInTheFieldIsOffered() {
        XCTAssertEqual(offered("Sam Carlo <SAM@example.com>, sa"), ["scarlo@example.org"])
        var field = RecipientBubbles(entries: ["Sam Carlo <sam@example.com>"])
        field.type("sa")
        XCTAssertEqual(ComposeForm.suggestions([], contacts: cards, in: field, after: .typed).map(\.address),
                       ["scarlo@example.org"])
    }

    // MARK: - The share sheet

    /// The cards come back from the mirror as the app put them, and the
    /// share sheet offers them as the composer does.
    @MainActor
    func testTheShareSheetOffersTheMirroredContacts() throws {
        let keychain = Keychain()
        let mirror = ShareMirror(keychain: keychain)
        mirror.publish(account: account, password: "app-password")
        mirror.publish(contacts: cards)
        let shared = try XCTUnwrap(mirror.load())
        XCTAssertEqual(shared.contacts, cards)

        let sheet = shareSheet(shared)
        XCTAssertEqual(sheet.suggestions(for: "car").map(\.address), ["sam@example.com", "scarlo@example.org"])
        XCTAssertEqual(sheet.suggestions(for: "car").map(\.display), ["Sam Carlo", "Sam Carlo"])
        XCTAssertEqual(sheet.suggestions(for: "car", after: .entered), [])
        var field = RecipientBubbles()
        field.type("nu")
        XCTAssertEqual(sheet.suggestions(in: field).map(\.address), ["pat@example.net"])
    }

    /// The app's sync hands over what it read; cards that could not be
    /// read leave the copy as it was; none, as when he has said no, take it
    /// away; no account takes everything.
    func testTheMirrorFollowsWhatTheAppRead() {
        let keychain = Keychain()
        let mirror = ShareMirror(keychain: keychain)
        let suite = "ContactSuggestionsTests"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let book = RecipientBook(defaults: UserDefaults(suiteName: suite)!)

        mirror.sync(account: account, password: "pw", signatureImages: [], book: book, contacts: cards)
        XCTAssertEqual(mirror.load()?.contacts, cards)
        mirror.sync(account: account, password: "pw", signatureImages: [], book: book, contacts: nil)
        XCTAssertEqual(mirror.load()?.contacts, cards)
        mirror.sync(account: account, password: "pw", signatureImages: [], book: book, contacts: [])
        XCTAssertEqual(mirror.load()?.contacts, [])
        mirror.sync(account: account, password: "pw", signatureImages: [], book: book, contacts: cards)
        mirror.sync(account: nil, password: nil, signatureImages: [], book: book, contacts: cards)
        XCTAssertTrue(keychain.items.isEmpty)
    }

    // MARK: - The question

    /// Asked only while never answered: a yes, iPadOS 18's "Select
    /// Contacts" among them, reads; a no, a restriction or anything newer
    /// reads nothing and asks nothing.
    func testTheQuestionIsAskedOnlyWhileNeverAnswered() {
        XCTAssertEqual(ContactsAccess(status: 0), .notAsked)
        XCTAssertTrue(ContactsAccess(status: 0).asksWhenHeTypes)
        for status in [3, 4] {
            XCTAssertEqual(ContactsAccess(status: status), .allowed, "\(status)")
        }
        for status in [1, 2, 5, -1] {
            XCTAssertEqual(ContactsAccess(status: status), .refused, "\(status)")
        }
        for status in [1, 2, 3, 4, 5] {
            XCTAssertFalse(ContactsAccess(status: status).asksWhenHeTypes, "\(status)")
        }
    }

    /// The one question is put by the app's composer as he types in an
    /// address field, and nowhere else: not at launch, not by the share
    /// extension. The composer offers his Contacts, and offers the list
    /// again when they come in at his yes.
    func testTheQuestionIsPutOnlyAsHeTypes() throws {
        let sources = try allSources()
        let asking = sources.filter { $0.value.contains("requestAccess(") }
        XCTAssertEqual(Array(asking.keys), ["Mail/AddressContacts.swift"])
        XCTAssertEqual(count("requestAccess(", in: try source("Mail/AddressContacts.swift")), 1)
        XCTAssertTrue(try source("Mail/AddressContacts.swift").contains(
            "func heTyped(then cameIn: @escaping () -> Void) { guard !answered else { return } "
                + "guard Self.access.asksWhenHeTypes else { answered = true return } lock.lock()"))
        let typing = sources.filter { $0.value.contains("AddressContacts.shared.heTyped") }
        XCTAssertEqual(Array(typing.keys), ["UI/ComposeViewController.swift"])

        let composer = try source("UI/ComposeViewController.swift")
        XCTAssertTrue(composer.contains("@objc private func addressEditingChanged(_ field: RecipientField) { "
            + "activeAddressField = field refreshSuggestions(after: .typed) updateSend() followRecipients() "
            + "AddressContacts.shared.heTyped { [weak self] in self?.contactsCameIn() } }"))
        XCTAssertEqual(count("AddressContacts.shared.heTyped", in: composer), 1)
        XCTAssertTrue(composer.contains("suggestions = ComposeForm.suggestions(RecipientBook.shared.snapshot(), "
            + "contacts: AddressContacts.shared.snapshot(), in: field.bubbles, after: event)"))
        XCTAssertTrue(composer.contains("private func contactsCameIn() { guard let field = activeAddressField, "
            + "field.isEditing else { return } refreshSuggestions(after: lastAddressEvent) }"))
        XCTAssertTrue(composer.contains("lastAddressEvent = event suggestions = ComposeForm.suggestions("))

        // The mirror's sync reads, if allowed, and never asks; the read is
        // before the mirror, so a build without the extension reads too.
        let app = try source("App/AppDelegate.swift")
        XCTAssertTrue(app.contains("mirrorQueue.async { let contacts = reads ? "
            + "AddressContacts.shared.readIfAllowed() : nil guard let mirror = ShareMirror.app else { return }"))
        XCTAssertTrue(app.contains("book: .shared, contacts: contacts)"))
        XCTAssertFalse(app.contains("heTyped"))
        XCTAssertTrue(try source("Mail/AddressContacts.swift").contains(
            "func readIfAllowed() -> [ContactCard]? { guard Self.access == .allowed else { keep([]) return [] }"))
    }

    /// Once iOS's question is found answered, a keystroke asks iOS
    /// nothing more, not even how it was answered: the answer is noted
    /// where it is found, and only there.
    func testAKeystrokeAsksNothingOnceTheQuestionIsAnswered() throws {
        let contacts = try source("Mail/AddressContacts.swift")
        XCTAssertTrue(contacts.contains("private var answered = false"))
        XCTAssertTrue(contacts.contains("func heTyped(then cameIn: @escaping () -> Void) { guard !answered "
            + "else { return } guard Self.access.asksWhenHeTypes else { answered = true return }"))
        XCTAssertEqual(count("answered = true", in: contacts), 1)
    }

    /// His Contacts are read at launch and on his return, and not as the
    /// app goes into the background, where the copy is left as it is; and
    /// not at all in a launch that follows launches in a row that never
    /// finished (`SafeStart`'s first step), for the whole of that launch.
    func testContactsAreReadAtLaunchAndOnReturnOnly() throws {
        let app = try source("App/AppDelegate.swift")
        XCTAssertTrue(app.contains("private static func syncShareMirror(readingContacts: Bool = true) { "
            + "let reads = readingContacts && !SafeStart.app.steps.forgetsKeptState mirrorQueue.async { "
            + "let contacts = reads ? AddressContacts.shared.readIfAllowed() : nil"))
        XCTAssertTrue(app.contains("LayoutAudit.beginSweeping() Self.syncShareMirror() "))
        XCTAssertTrue(app.contains("repository.shelf?.flush() Self.syncShareMirror(readingContacts: false) }"))
        XCTAssertTrue(app.contains("Diagnostics.wentAwayOrCameBack() Self.syncShareMirror() }"))
        XCTAssertEqual(count("Self.syncShareMirror()", in: app), 2)
        XCTAssertEqual(count("Self.syncShareMirror(readingContacts: false)", in: app), 1)
        XCTAssertEqual(count("syncShareMirror(", in: app), 4)
        XCTAssertEqual(count("readIfAllowed()", in: app), 1)
        // SafeStart's steps are this launch's, decided at its start.
        XCTAssertTrue(app.contains("SafeStart.app.launch()"))
    }

    /// The share extension reads no Contacts of its own: its sheet offers
    /// the copy the app mirrored.
    func testTheShareExtensionReadsOnlyTheMirror() throws {
        for (file, code) in try allSources() where file.hasPrefix("Share/") {
            for word in ["AddressContacts", "CNContactStore", "import Contacts"] {
                XCTAssertFalse(code.contains(word), "\(file): \(word)")
            }
        }
        let share = try String(contentsOf: root.appendingPathComponent("Sources/BlackmailShare/main.swift"),
                               encoding: .utf8)
        XCTAssertFalse(share.contains("Contacts"))
        let rules = try source("Share/ShareSheet.swift")
        XCTAssertTrue(rules.contains("ComposeForm.suggestions(shared.recipients, contacts: shared.contacts, "
            + "field: field, after: event)"))
        XCTAssertTrue(rules.contains("ComposeForm.suggestions(shared.recipients, contacts: shared.contacts, "
            + "in: field, after: event)"))
    }

    /// The words iOS shows under its question, in the app's Info.plist,
    /// and none in the extension's, which never asks.
    func testTheQuestionsWordsAreTheAppsAlone() throws {
        let app = try plist("Resources/Info.plist")
        XCTAssertEqual(app["NSContactsUsageDescription"] as? String,
                       "As you type, Blackmail suggests people from your Contacts.")
        let share = try plist("Resources/ShareInfo.plist")
        XCTAssertNil(share["NSContactsUsageDescription"])
    }

    // MARK: - Helpers

    private let account = MailAccount(address: "owner@example.com", username: "owner@example.com",
                                      displayName: "Sam", signature: "Sam", signatureHTML: "")

    /// The Keychain group as a dictionary.
    private final class Keychain: SharedKeychain {
        var items: [String: Data] = [:]
        func data(named name: String) -> Data? { items[name] }
        func store(_ data: Data, named name: String) -> Bool {
            items[name] = data
            return true
        }
        func remove(named name: String) { items[name] = nil }
        func names() -> [String] { Array(items.keys) }
    }

    @MainActor
    private func shareSheet(_ shared: ShareMirror.Shared) -> ShareSheet {
        ShareSheet(shared: shared,
                   transport: { _, _ in ScriptedSubmission() },
                   noteSent: { _ in }, finish: {}, cancel: {}, showError: { _ in }, draw: { _ in },
                   background: BackgroundTime(begin: { _, _ in nil }, end: { _ in }))
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
    }

    private func count(_ needle: String, in code: String) -> Int {
        code.components(separatedBy: needle).count - 1
    }

    /// The file's code with its comment lines dropped and its spacing
    /// made single, so a line is found however it is wrapped.
    private func source(_ path: String) throws -> String {
        let text = try String(contentsOf: root.appendingPathComponent("Sources/Blackmail/\(path)"),
                              encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    /// Every Swift file of the library, by its path under it, as `source`
    /// reads it.
    private func allSources() throws -> [String: String] {
        let base = root.appendingPathComponent("Sources/Blackmail")
        var found: [String: String] = [:]
        let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let path = String(url.standardizedFileURL.path.dropFirst(base.standardizedFileURL.path.count + 1))
            found[path] = try source(path)
        }
        return found
    }

    private func plist(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
