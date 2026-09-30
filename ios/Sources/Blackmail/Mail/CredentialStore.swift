// Guarded so this file compiles away on a host without Security.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(Security)

import Foundation
import Security

/// Where the one app-specific password lives, and where the account settings
/// that are *not* secret live — deliberately in two different places.
///
/// The password goes in the Keychain as a `kSecClassInternetPassword`. The
/// `MailAccount` itself (address, hosts, ports, display name) is JSON in
/// `UserDefaults`: none of it is a secret, and keeping it out of the Keychain
/// means the account can be inspected, reset or repaired without the Keychain
/// being readable at that moment — which, given the accessibility class below,
/// is not always true.
///
/// `Security.framework` costs us no dependency: in the sparse iPhoneOS 16.5
/// SDK we cross-compile against, `Security.tbd` is a real 131 KB stub with a
/// full symbol list, not one of the 404-byte re-export placeholders that made
/// the iOS 18 SDK unusable. So `import Security` links, exactly as
/// `Network.framework` does for `TLSConnection`.
enum CredentialStore {

    /// Only `save()` throws — a *missing* credential is first launch, not a
    /// fault, so every read returns nil instead.
    enum StoreError: LocalizedError {
        case emptyAddress
        case emptyPassword
        case accountNotEncodable(Error)
        case keychain(OSStatus)

        /// Plain sentences only. `ErrorPresenter`'s rule applies here too: a
        /// 90-year-old reading "OSStatus -34018" learns only that he has
        /// broken something, which he has not.
        var errorDescription: String? {
            switch self {
            case .emptyAddress:        return "Enter your email address."
            case .emptyPassword:       return "Enter your app password."
            case .accountNotEncodable: return "Account settings could not be saved."
            case .keychain:            return "Password could not be saved."
            }
        }

        /// For `ErrorPresenter.log`, never for the screen. This is the only
        /// place the real `OSStatus` survives, and it is what turns "could not
        /// be saved" into something diagnosable after the fact.
        var diagnostic: String {
            switch self {
            case .emptyAddress:              return "CredentialStore: empty address"
            case .emptyPassword:             return "CredentialStore: empty password"
            case .accountNotEncodable(let e): return "CredentialStore: encode failed: \(e)"
            case .keychain(let status):      return "CredentialStore: OSStatus \(status)"
            }
        }
    }

    // MARK: - Storage keys

    /// Versioned so a future change of shape can be detected rather than
    /// silently mis-decoded into a half-empty account.
    private static let accountDefaultsKey = "wtf.uhoh.blackmail.account.v1"

    private static var defaults: UserDefaults { .standard }

    // MARK: - Writing

    /// Stores the account and its password, replacing whatever was there.
    ///
    /// The overwrite is the part that is easy to get wrong: `SecItemAdd`
    /// returns `errSecDuplicateItem` when a matching item already exists and
    /// changes nothing, so a naive add makes "change my password" look like it
    /// worked while the app keeps signing in with the old one forever. Update
    /// first, add only when there is nothing to update, and fall back to
    /// delete-then-add if an add still collides with a stale item whose
    /// primary-key attributes differ from ours.
    /// Saves the account WITHOUT writing the stored password.
    ///
    /// Changing a name or a signature must never write the password item.
    /// That write is the one operation in this type that can fail in a way
    /// that locks him out of his own mail, and editing a sign-off has no
    /// business being able to do that. The item is READ here, in a build
    /// that carries the share extension, so the extension's copy of the
    /// account can be handed the new signature with it.
    static func saveAccountOnly(_ account: MailAccount) throws {
        let clean = normalised(account)
        guard !clean.address.isEmpty else { throw StoreError.emptyAddress }
        do {
            let data = try JSONEncoder().encode(clean)
            defaults.set(data, forKey: accountDefaultsKey)
        } catch {
            throw StoreError.accountNotEncodable(error)
        }
        // The share extension signs with the signature it is handed, so a
        // changed one is handed over now rather than at the next launch.
        if let mirror = ShareMirror.app, let password = loadPassword(for: clean) {
            mirror.publish(account: clean, password: password)
        }
    }

    static func save(account: MailAccount, password: String) throws {
        let clean = normalised(account)
        guard !clean.address.isEmpty else { throw StoreError.emptyAddress }
        // Gmail prints app passwords in four spaced groups ("abcd efgh ijkl
        // mnop") and he will type them, or paste them, exactly as printed.
        // IMAP AUTH would reject that, so the spaces come out here — once, at
        // the boundary — rather than being fixed up at every login site.
        let secret = password.filter { !$0.isWhitespace }
        guard !secret.isEmpty else { throw StoreError.emptyPassword }

        let status = writePassword(secret, address: clean.address, host: clean.imapHost)
        guard status == errSecSuccess else { throw StoreError.keychain(status) }

        // The normalised account is what gets stored, so that the address this
        // password was filed under is byte-for-byte the address a later
        // `loadPassword(for:)` builds its query from. Saving the raw account
        // here and the trimmed one there is how a password gets written and
        // then never found again.
        do {
            let data = try JSONEncoder().encode(clean)
            defaults.set(data, forKey: accountDefaultsKey)
        } catch {
            throw StoreError.accountNotEncodable(error)
        }
        // Where the share extension can read them (B-036). A new app
        // password has to reach it at once: sharing with the old one would
        // be refused, and he would be told so in a sheet over Safari.
        ShareMirror.app?.publish(account: clean, password: secret)
    }

    /// Whitespace off every field a typist or a paste can ruin, and a username
    /// defaulted to the address. A trailing space on a host is invisible on
    /// screen and fails as an unresolvable name, which reads to him as "the
    /// internet is broken".
    private static func normalised(_ account: MailAccount) -> MailAccount {
        func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        var out = account
        out.address = trim(account.address)
        out.imapHost = trim(account.imapHost)
        out.smtpHost = trim(account.smtpHost)
        out.username = trim(account.username).isEmpty ? out.address : trim(account.username)
        out.displayName = trim(account.displayName)
        return out
    }

    // MARK: - Reading

    static func loadAccount() -> MailAccount? {
        guard let data = defaults.data(forKey: accountDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(MailAccount.self, from: data)
    }

    static func loadPassword(for account: MailAccount) -> String? {
        var query = baseQuery(address: account.address, host: account.imapHost)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        // A conditional cast, never `as!`: `SecItemCopyMatching` promises a
        // CFTypeRef and nothing more, and a crash here would be a crash on
        // launch with no way for him to get out of it.
        guard let data = item as? Data, !data.isEmpty else { return nil }

        // The same lenient decode the wire uses. An app password is ASCII, but
        // returning nil because a byte was odd would present as "wrong
        // password" and send him off to reset a password that is fine.
        let text = TLSConnection.decode(data)
        return text.isEmpty ? nil : text
    }

    /// True when an account has been configured. Deliberately answered from
    /// `UserDefaults` alone, without touching the Keychain: before the first
    /// unlock after a reboot a Keychain read fails with
    /// `errSecInteractionNotAllowed`, and if that counted as "no account" the
    /// app would throw away a working setup and show the sign-in screen. A
    /// missing password is discovered at login, where it maps to
    /// `MailError.passwordNeedsUpdating` and says so.
    static var hasAccount: Bool { loadAccount() != nil }

    // MARK: - Clearing

    static func clear() {
        // Sweep the whole class rather than only the key we can currently
        // derive. This app stores exactly one internet password, the sandbox
        // limits the delete to our own keychain access group, and the account
        // JSON may already be gone — in which case a targeted delete would
        // leave the password orphaned and undeletable.
        _ = SecItemDelete([kSecClass as String: kSecClassInternetPassword] as CFDictionary)
        defaults.removeObject(forKey: accountDefaultsKey)
        // And the extension's copy, or a share would go on sending as an
        // account that has been taken out of the app.
        ShareMirror.app?.clear()
    }

    // MARK: - Keychain plumbing

    /// The attributes that identify our item, and the *only* ones used to find
    /// it. Port is left out on purpose even though `kSecAttrPort` is part of
    /// an internet password's primary key: if the user ever edits the IMAP
    /// port, a port-keyed query would stop matching and silently orphan the
    /// password instead of updating it.
    ///
    /// Both key parts are trimmed and lowercased here and nowhere else, so
    /// every caller keys the item identically whether or not its `MailAccount`
    /// came back from `loadAccount()`. Addresses and hostnames are
    /// case-insensitive to everyone except a Keychain query, which compares
    /// them as bytes.
    private static func baseQuery(address: String, host: String) -> [String: Any] {
        func key(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return [
            kSecClass as String:        kSecClassInternetPassword,
            kSecAttrAccount as String:  key(address),
            kSecAttrServer as String:   key(host),
            kSecAttrProtocol as String: kSecAttrProtocolIMAPS,
        ]
    }

    /// Returns an `OSStatus` rather than throwing so the three write paths can
    /// be chained without unwinding; `save()` turns the failure into an error.
    private static func writePassword(_ password: String, address: String, host: String) -> OSStatus {
        // B-033: sweep every sibling for this account+server — ANY protocol,
        // ANY port — before writing. An older build's item can differ from
        // our query in a primary-key attribute (its protocol, its port), so
        // `SecItemUpdate` does not match it, `SecItemAdd` succeeds BESIDE it,
        // and `loadPassword` then finds two matches and returns either one.
        // That is exactly what happened on the dev iPad: the setup form saved
        // a fresh app password, IMAP kept accepting the OLD one, and SMTP
        // refused it — a 535 with a credential Python proves valid, whose
        // transcript reads like an impossible bug. One item per account is
        // the invariant; the sweep is what enforces it.
        var sweep: [String: Any] = [
            kSecClass as String:       kSecClassInternetPassword,
            kSecAttrAccount as String: address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            kSecAttrServer as String:  host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
        ]
        _ = SecItemDelete(sweep as CFDictionary)

        let query = baseQuery(address: address, host: host)
        let secret = Data(password.utf8)

        // `kSecAttrAccessible` is set on update as well as add. An item
        // created by an older build with the default accessibility keeps it
        // forever otherwise, and the background-refresh failure that causes is
        // indistinguishable from a network error.
        let changes: [String: Any] = [
            kSecValueData as String: secret,
            kSecAttrAccessible as String: accessibility,
        ]

        let updated = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if updated != errSecItemNotFound { return updated }

        var add = query
        add[kSecValueData as String] = secret
        add[kSecAttrAccessible as String] = accessibility
        // Never to iCloud Keychain. This password is one device's credential
        // for one mailbox; syncing it would put it on hardware nobody here is
        // looking after.
        add[kSecAttrSynchronizable as String] = false
        add[kSecAttrLabel as String] = "Blackmail (\(address))"

        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecDuplicateItem else { return added }

        // An item exists that `SecItemUpdate` did not match — it differs in
        // some primary-key attribute we no longer set (an old build's port, or
        // a different protocol). Clear it out and add ours, otherwise the
        // password can never be changed again.
        _ = SecItemDelete(query as CFDictionary)
        return SecItemAdd(add as CFDictionary, nil)
    }

    /// After first unlock, not the `WhenUnlocked` default. Mail refreshes in
    /// the background with the screen locked, and with the default class every
    /// one of those refreshes would fail to read the password and surface as
    /// "Can't connect to mail server" — a network error he cannot act on, for
    /// a problem that is not the network.
    private static var accessibility: CFString { kSecAttrAccessibleAfterFirstUnlock }
}

#endif
