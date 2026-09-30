// Guarded so this file compiles away on a host without Security; the
// mirror itself (`ShareMirror`) runs on the host against a stand-in.
#if canImport(Security)

import Foundation
import Security

/// `SharedKeychain` on the device: generic-password items in the group the
/// app and the share extension are both signed with.
///
/// The group is named in every query, on the way in and the way out. An
/// app that carries the extension holds two groups, its own first, and an
/// item added without one lands in the first: the mirror would then sit
/// where the extension cannot see it, which looks exactly like never having
/// been written.
final class KeychainSharedStore: SharedKeychain {

    private let group: String
    private static let service = "wtf.uhoh.blackmail.shared"

    init(group: String = ShareMirror.accessGroup) {
        self.group = group
    }

    private func query(_ name: String) -> [String: Any] {
        [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      Self.service,
            kSecAttrAccount as String:      name,
            kSecAttrAccessGroup as String:  group,
        ]
    }

    func data(named name: String) -> Data? {
        var q = query(name)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    /// Update first, add only when there is nothing to update: an add over
    /// an existing item changes nothing and says `errSecDuplicateItem`.
    ///
    /// After first unlock, as the app's own password is, and never to iCloud
    /// Keychain, for the reasons `CredentialStore` gives.
    @discardableResult
    func store(_ data: Data, named name: String) -> Bool {
        let changes: [String: Any] = [
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updated = SecItemUpdate(query(name) as CFDictionary, changes as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return refused(updated, name) }

        var add = query(name)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrSynchronizable as String] = false
        add[kSecAttrLabel as String] = "Blackmail sharing"
        let added = SecItemAdd(add as CFDictionary, nil)
        return added == errSecSuccess ? true : refused(added, name)
    }

    func remove(named name: String) {
        _ = SecItemDelete(query(name) as CFDictionary)
    }

    /// Every item of this service in the group, by its attributes alone:
    /// no item's data is read to list them.
    func names() -> [String] {
        let q: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      Self.service,
            kSecAttrAccessGroup as String:  group,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String:       kSecMatchLimitAll,
        ]
        var found: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &found) == errSecSuccess,
              let items = found as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    /// For the connection log only. -34018 is a build signed without the
    /// group, which is worth being able to tell apart from anything else.
    private func refused(_ status: OSStatus, _ name: String) -> Bool {
        Diagnostics.log(.note, "SharedKeychain: \(name) OSStatus \(status)"
            + (status == errSecMissingEntitlement ? " (not signed with \(group))" : ""))
        return false
    }
}

extension ShareMirror {
    /// The extension's own: the real Keychain group.
    static var device: ShareMirror { ShareMirror(keychain: KeychainSharedStore()) }

    /// The app's, or nil when the app carries no share extension. Such a
    /// build is signed without the shared group (tools/sign-ipa.sh), as
    /// every build before the extension was, so it has nothing to mirror
    /// and no Keychain call to make: its Keychain use stays exactly what
    /// was proven on the iPad, and the connection log is not filled with
    /// writes the Keychain refused.
    static var app: ShareMirror? {
        guard let plugIns = Bundle.main.builtInPlugInsURL,
              FileManager.default.fileExists(
                atPath: plugIns.appendingPathComponent("BlackmailShare.appex").path)
        else { return nil }
        return device
    }
}

#endif
