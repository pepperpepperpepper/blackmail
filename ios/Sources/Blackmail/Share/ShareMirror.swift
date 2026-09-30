import Foundation

/// Named blobs in the one Keychain group the app and its share extension
/// both hold. A seam: the device's is `KeychainSharedStore`, the host
/// tests' an in-memory stand-in.
protocol SharedKeychain: AnyObject {
    func data(named name: String) -> Data?
    /// False when the Keychain refused the write. On the device that mostly
    /// means a build signed without the shared group in its entitlements,
    /// which is not his to fix and not worth an alert: the app carries on,
    /// and only sharing waits for a properly signed build.
    @discardableResult func store(_ data: Data, named name: String) -> Bool
    func remove(named name: String)
    /// The name of every item there is, in no particular order.
    func names() -> [String]
}

/// What the app leaves where its share extension can read it (B-036).
///
/// The extension sends by itself, as Mail's does, so a shared link goes
/// without the app being opened. For that it needs everything the app would
/// use: the account and its app password, the signature and its pictures,
/// and the addresses the composer offers. The password is in the Keychain
/// and the rest in the app's `UserDefaults`, and an extension can read
/// neither: the provisioning profile is a wildcard, which Apple does not
/// allow App Groups on, so the usual shared container does not exist here.
/// What the profile does allow is `keychain-access-groups JGLH7HX44Y.*`, so
/// the app mirrors what the extension needs into one group both are signed
/// with, `accessGroup`, and the extension reads it from there.
///
/// Each item is written only when it has changed, so the mirror costs
/// nothing at the launches and backgroundings where nothing has.
///
/// The one thing that flows the other way is who the extension sent to
/// (`noteSent`), which the app takes in its own book as used (`sync`), so
/// his own second address stays at the top of the suggestions whichever
/// way he last wrote to it. Each letter's addresses are an item of their
/// own, written once by the extension and removed by the app only once it
/// has them: two processes reading, changing and writing back one list,
/// with nothing to keep them apart, could each lose what the other wrote.
struct ShareMirror {

    /// The group both are signed with: `keychain-access-groups` in
    /// ios/Resources/BlackmailWithShare.entitlements, the app's when it
    /// carries the extension, and BlackmailShare.entitlements.
    static let accessGroup = "JGLH7HX44Y.wtf.uhoh.blackmail.shared"

    /// Everything the extension needs to write and send a letter as he
    /// would from the app.
    struct Shared: Equatable {
        var account: MailAccount
        var password: String
        var signatureImages: [SignatureImages.InlineImage]
        var recipients: [KnownRecipient]
    }

    /// The item names, which are also what the Keychain files them under.
    enum Item: String, CaseIterable {
        case credentials
        case signatureImages = "signature-images"
        case recipients
    }

    /// What each letter the extension sent is filed under, followed by
    /// its place in line and a name no other letter has.
    static let sentPrefix = "sent-from-share."

    /// How many letters' addresses the extension keeps for the app to take.
    /// The app takes them at every launch and return, so this is only
    /// reached by hundreds of shares with the app never opened; the oldest
    /// go first.
    static let sentLimit = 200

    private struct Credentials: Codable {
        var account: MailAccount
        var password: String
    }

    let keychain: SharedKeychain

    // MARK: - The app's side

    /// Mirrors the account and its password. The password as the Keychain
    /// holds it for the app, spaces already out (`CredentialStore.save`).
    func publish(account: MailAccount, password: String) {
        write(Credentials(account: account, password: password), as: .credentials)
    }

    func publish(signatureImages: [SignatureImages.InlineImage]) {
        write(signatureImages, as: .signatureImages)
    }

    /// In a fixed order, so an unchanged book encodes to the same bytes and
    /// is not written again.
    func publish(recipients: [KnownRecipient]) {
        write(recipients.sorted { $0.address < $1.address }, as: .recipients)
    }

    /// Everything gone: the account was removed from the app, and a share
    /// must not go on sending as it.
    func clear() {
        for item in Item.allCases { keychain.remove(named: item.rawValue) }
        for name in sentNames() { keychain.remove(named: name) }
    }

    /// Brings the mirror up to date with the app, and hands the app's book
    /// the addresses the extension has sent to since last time.
    ///
    /// Called at launch, which covers an account set up by a build from
    /// before the mirror existed, and whenever the app goes into or comes
    /// back from the background.
    ///
    /// No account clears the mirror. No password with an account leaves the
    /// mirrored credentials as they are: before the first unlock after a
    /// restart the app's own Keychain read fails, and that is not a reason
    /// to stop the extension working once he has unlocked.
    func sync(account: MailAccount?, password: String?,
              signatureImages: [SignatureImages.InlineImage], book: RecipientBook) {
        guard let account else {
            clear()
            return
        }
        if let password { publish(account: account, password: password) }
        publish(signatureImages: signatureImages)
        // `used` writes the book out before it returns.
        takeSent { for address in $0 { book.used(address: address) } }
        publish(recipients: book.snapshot())
    }

    /// Hands `take` what the extension has sent to, oldest first, and only
    /// then forgets it: exactly the letters handed over, so one the
    /// extension notes meanwhile waits for next time, and none is gone
    /// before `take` has it safe.
    func takeSent(_ take: ([String]) -> Void) {
        let names = sentNames()
        guard !names.isEmpty else { return }
        take(names.flatMap { read([String].self, from: $0) ?? [] })
        for name in names { keychain.remove(named: name) }
    }

    // MARK: - The extension's side

    /// What the extension works from, or nil when the app has not mirrored
    /// an account: none set up, or not opened since the build that mirrors.
    func load() -> Shared? {
        guard let credentials = read(Credentials.self, from: .credentials),
              !credentials.password.isEmpty else { return nil }
        return Shared(account: credentials.account,
                      password: credentials.password,
                      signatureImages: read([SignatureImages.InlineImage].self,
                                            from: .signatureImages) ?? [],
                      recipients: read([KnownRecipient].self, from: .recipients) ?? [])
    }

    /// A letter sent from the extension, by the addresses it went to, for
    /// the app to take in its book (`sync`).
    func noteSent(_ addresses: [String]) {
        guard !addresses.isEmpty else { return }
        let held = sentNames()
        for name in held.prefix(max(0, held.count - Self.sentLimit + 1)) {
            keychain.remove(named: name)
        }
        let next = (held.last.map(Self.place(of:)) ?? 0) + 1
        write(addresses, as: Self.sentPrefix + String(format: "%012ld.", next) + UUID().uuidString)
    }

    // MARK: - Plumbing

    /// The letters the extension has noted, oldest first: the place in
    /// line is written with its leading zeros, so the names sort as it does.
    private func sentNames() -> [String] {
        keychain.names().filter { $0.hasPrefix(Self.sentPrefix) }.sorted()
    }

    private static func place(of name: String) -> Int {
        Int(name.dropFirst(sentPrefix.count).prefix { $0 != "." }) ?? 0
    }

    private func write<T: Encodable>(_ value: T, as item: Item) {
        write(value, as: item.rawValue)
    }

    private func write<T: Encodable>(_ value: T, as name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(value) else { return }
        guard keychain.data(named: name) != data else { return }
        if !keychain.store(data, named: name) {
            Diagnostics.log(.note, "ShareMirror: could not write \(name)")
        }
    }

    private func read<T: Decodable>(_ type: T.Type, from item: Item) -> T? {
        read(type, from: item.rawValue)
    }

    private func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = keychain.data(named: name) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
