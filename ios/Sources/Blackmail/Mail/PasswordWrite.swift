import Foundation

/// The order the one password item is written in: the new password in
/// place first, anything else under the account only after. Apart from
/// `CredentialStore`, whose Security calls do not exist on the host, so the
/// order can be tried against a keychain of the suite's own.
///
/// It was the other way round. B-033's sweep deleted every item for the
/// account and server, the one read included, and then added the new one;
/// an add that failed, on a full disk or a keychain that would not be
/// written, left no password at all while Settings said "Could not save.
/// Nothing has been changed." The next launch then found no password and
/// showed setup, which saved a new account over the stored one, signature
/// and all. Now a write that fails leaves every item as it was, and the
/// old password works as before.
enum PasswordWrite {

    /// The keychain as the write sees it, for one account and server.
    /// `Ref` names one item: a persistent reference on the device.
    struct Items<Ref: Equatable> {
        /// Every item under the account and server, whatever its protocol
        /// and port: the one `CredentialStore` reads, and any sibling an
        /// older build left beside it (B-033).
        var all: () -> [Ref]
        /// The one `CredentialStore` reads, nil if there is none.
        var read: () -> Ref?
        /// Writes the new password into the item read, where there is one,
        /// in place.
        var update: () -> Int32
        /// Adds an item holding the new password, as the one read.
        var add: () -> Int32
        var remove: (Ref) -> Int32
    }

    /// Security's `errSecSuccess`, `errSecItemNotFound` and
    /// `errSecDuplicateItem`, which the host does not have.
    static let success: Int32 = 0
    static let notFound: Int32 = -25300
    static let duplicate: Int32 = -25299

    /// Writes the new password and leaves one item under the account and
    /// server, holding it; or, failing, returns the status and leaves every
    /// item as it found it.
    ///
    /// The item read is updated in place where there is one, and added
    /// where there is none. Only once that has worked does anything go:
    /// every other item under the account and server, as the sweep took
    /// them, so one item per account stays the invariant (B-033). An add
    /// that collides with an item the update did not find, one no read can
    /// find either, clears the account's items first, since then there is
    /// no password to lose; that is the one removal before the write.
    static func write<Ref>(_ items: Items<Ref>) -> Int32 {
        let before = items.all()
        var status = items.update()
        if status == notFound {
            status = items.add()
            if status == duplicate {
                for ref in before { _ = items.remove(ref) }
                status = items.add()
            }
        }
        guard status == success else { return status }
        // Nothing is removed unless the one holding the new password can be
        // told from the rest.
        guard let kept = items.read() else { return success }
        for ref in before where ref != kept { _ = items.remove(ref) }
        return success
    }
}
