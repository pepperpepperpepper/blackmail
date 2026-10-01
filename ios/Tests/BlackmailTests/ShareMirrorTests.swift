import XCTest
@testable import Blackmail

/// What the app leaves in the shared Keychain group for its share extension
/// (B-036), behind the `SharedKeychain` seam: the account and password, the
/// signature and its pictures, and the addresses the composer offers, read
/// back whole by the extension; and who the extension sent to, read back by
/// the app.
final class ShareMirrorTests: XCTestCase {

    /// The Keychain group as a dictionary, counting what is written to it.
    /// `removing` runs just before an item goes, where the other process
    /// could be doing anything.
    private final class MemoryKeychain: SharedKeychain {
        var items: [String: Data] = [:]
        var writes: [String] = []
        var refuses = false
        var removing: ((String) -> Void)?

        func data(named name: String) -> Data? { items[name] }

        func store(_ data: Data, named name: String) -> Bool {
            guard !refuses else { return false }
            writes.append(name)
            items[name] = data
            return true
        }

        func remove(named name: String) {
            removing?(name)
            items[name] = nil
        }

        func names() -> [String] { Array(items.keys) }
    }

    private static let suite = "ShareMirrorTests"
    private var keychain = MemoryKeychain()
    private var mirror: ShareMirror { ShareMirror(keychain: keychain) }
    private var book: RecipientBook!

    override func setUp() {
        super.setUp()
        keychain = MemoryKeychain()
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: UserDefaults(suiteName: Self.suite)!)
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        super.tearDown()
    }

    private let account = MailAccount(address: "owner@example.com", username: "owner@example.com",
                                      displayName: "Sam", signature: "Sam\n1 Example Street",
                                      signatureHTML: "<table><tr><td><b>Sam</b></td></tr></table>")
    private let logo = SignatureImages.InlineImage(contentID: "sig-logo", filename: "logo.png",
                                                   mimeType: "image/png", dataBase64: "iVBORw0KGgo=")

    private func recipient(_ address: String, uses: Int) -> KnownRecipient {
        KnownRecipient(address: address, name: nil, uses: uses,
                       lastSeen: Date(timeIntervalSince1970: 1_700_000_000))
    }

    // MARK: - Round trip

    /// Everything the extension needs comes back as the app put it: the
    /// account with its signature in both forms, the password, the
    /// signature's pictures and the book.
    func testWhatTheAppMirrorsTheExtensionReadsBack() throws {
        let book = [recipient("owner@example.net", uses: 40), recipient("carlo@example.org", uses: 3)]
        mirror.publish(account: account, password: "abcdefghijklmnop")
        mirror.publish(signatureImages: [logo])
        mirror.publish(recipients: book)

        let shared = try XCTUnwrap(mirror.load())
        XCTAssertEqual(shared.account, account)
        XCTAssertEqual(shared.password, "abcdefghijklmnop")
        XCTAssertEqual(shared.signatureImages, [logo])
        XCTAssertEqual(Set(shared.recipients.map(\.address)), Set(book.map(\.address)))
        XCTAssertEqual(shared.recipients.first { $0.address == "owner@example.net" }?.uses, 40)
    }

    /// Nothing mirrored is nothing to send as, and so is an account without
    /// a password; the extension says to open the app once.
    func testNoAccountIsNothingToSendAs() {
        XCTAssertNil(mirror.load())
        mirror.publish(account: account, password: "")
        XCTAssertNil(mirror.load())
    }

    /// A signature and a book but no account: the extension still has
    /// nothing to send as.
    func testTheRestWithoutTheAccountIsNothing() {
        mirror.publish(signatureImages: [logo])
        XCTAssertNil(mirror.load())
    }

    /// Written only when changed, so a launch or a trip to the background
    /// where nothing has changed writes nothing. The book's order is its
    /// own business and does not count as a change.
    func testWhatHasNotChangedIsNotWrittenAgain() {
        let a = recipient("a@example.org", uses: 1), b = recipient("b@example.org", uses: 2)
        mirror.publish(account: account, password: "pw")
        mirror.publish(account: account, password: "pw")
        mirror.publish(recipients: [a, b])
        mirror.publish(recipients: [b, a])
        XCTAssertEqual(keychain.writes, ["credentials", "recipients"])

        mirror.publish(account: account, password: "new-pw")
        XCTAssertEqual(keychain.writes.last, "credentials", "a new password is handed over")
        XCTAssertEqual(mirror.load()?.password, "new-pw")
    }

    /// An account taken out of the app is taken out of the extension.
    func testClearingLeavesNothing() {
        mirror.publish(account: account, password: "pw")
        mirror.publish(signatureImages: [logo])
        mirror.noteSent(["owner@example.net"])
        mirror.clear()
        XCTAssertTrue(keychain.items.isEmpty)
        XCTAssertNil(mirror.load())
    }

    /// A write the Keychain refused, as it does for a build signed without
    /// the group, is not taken for done: the next sync tries it again.
    func testARefusedWriteIsTriedAgain() {
        keychain.refuses = true
        mirror.publish(account: account, password: "pw")
        XCTAssertNil(mirror.load())

        keychain.refuses = false
        mirror.publish(account: account, password: "pw")
        XCTAssertEqual(mirror.load()?.password, "pw")
    }

    // MARK: - The app's sync

    /// Restore Original Signature's pictures are handed to the extension as
    /// they are saved, as the account naming them is, and not only at the
    /// next sync: until then a share went with the restored markup and the
    /// pictures it had before.
    func testRestoredSignaturePicturesReachTheExtensionAsTheyAreSaved() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suite))
        let before = SignatureImages.InlineImage(contentID: "sig-logo", filename: "logo.png",
                                                 mimeType: "image/png", dataBase64: "AAAA")
        mirror.publish(account: account, password: "pw")
        mirror.publish(signatureImages: [before])

        SignatureImages.save([logo], defaults: defaults, mirroringTo: mirror)
        XCTAssertEqual(SignatureImages.load(defaults: defaults), [logo])
        XCTAssertEqual(mirror.load()?.signatureImages, [logo])
    }

    func testSyncMirrorsTheAppsAccountBookAndPictures() throws {
        book.used(address: "owner@example.net")
        mirror.sync(account: account, password: "pw", signatureImages: [logo], book: book)

        let shared = try XCTUnwrap(mirror.load())
        XCTAssertEqual(shared.account, account)
        XCTAssertEqual(shared.signatureImages, [logo])
        XCTAssertEqual(shared.recipients.map(\.address), ["owner@example.net"])
    }

    /// No account in the app, and the extension has none either.
    func testSyncWithNoAccountClearsTheMirror() {
        mirror.publish(account: account, password: "pw")
        mirror.sync(account: nil, password: nil, signatureImages: [], book: book)
        XCTAssertNil(mirror.load())
    }

    /// Before the first unlock after a restart the app cannot read its own
    /// password. That leaves the mirrored one alone rather than taking
    /// sharing away.
    func testSyncWithoutThePasswordKeepsTheMirroredOne() {
        mirror.publish(account: account, password: "pw")
        mirror.sync(account: account, password: nil, signatureImages: [], book: book)
        XCTAssertEqual(mirror.load()?.password, "pw")
    }

    /// Who the extension sent to reaches the app's book as used, once, and
    /// comes back to the extension ranked with it.
    func testWhoTheExtensionSentToReachesTheAppsBook() throws {
        mirror.noteSent(["owner@example.net"])
        mirror.noteSent(["owner@example.net", "carlo@example.org"])
        mirror.sync(account: account, password: "pw", signatureImages: [], book: book)

        XCTAssertEqual(book.suggestions(for: "").map(\.address).first, "owner@example.net")
        XCTAssertEqual(book.snapshot().first { $0.address == "owner@example.net" }?.uses, 2)
        XCTAssertTrue(taken().isEmpty, "taken once")
        XCTAssertEqual(try XCTUnwrap(mirror.load()).recipients
                        .first { $0.address == "owner@example.net" }?.uses, 2)
    }

    private func taken() -> [String] {
        var sent: [String] = []
        mirror.takeSent { sent += $0 }
        return sent
    }

    /// Hundreds of shares with the app never opened keep the latest, in
    /// the order they went.
    func testTheExtensionsListIsBounded() {
        for i in 0..<(ShareMirror.sentLimit + 5) { mirror.noteSent(["n\(i)@example.org"]) }
        let sent = taken()
        XCTAssertEqual(sent.count, ShareMirror.sentLimit)
        XCTAssertEqual(sent.first, "n5@example.org")
        XCTAssertEqual(sent.last, "n\(ShareMirror.sentLimit + 4)@example.org")
    }

    /// A letter the extension notes while the app is taking what it had
    /// noted before is not lost with them: it is there next time.
    func testALetterNotedWhileTheAppTakesWaitsForNextTime() {
        let keychain = self.keychain
        let theExtension = ShareMirror(keychain: keychain)
        theExtension.noteSent(["a@example.org"])
        keychain.removing = { _ in
            keychain.removing = nil
            theExtension.noteSent(["b@example.org"])
        }

        XCTAssertEqual(taken(), ["a@example.org"])
        XCTAssertEqual(taken(), ["b@example.org"])
    }

    /// Nothing is forgotten before the app's book has it written out: an
    /// app killed between the two loses nothing.
    func testNothingIsForgottenBeforeTheBookHasIt() {
        mirror.noteSent(["carlo@example.org"])
        var onDisk: [String] = []
        keychain.removing = { _ in
            onDisk = RecipientBook(defaults: UserDefaults(suiteName: Self.suite)!)
                .snapshot().map(\.address)
        }

        mirror.sync(account: account, password: "pw", signatureImages: [], book: book)

        XCTAssertTrue(onDisk.contains("carlo@example.org"), "\(onDisk)")
    }
}
