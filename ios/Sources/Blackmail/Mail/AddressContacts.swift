// Guarded so this file compiles away on a host without Contacts. What it
// reads is matched and ranked by `AddressSuggestions`, which the suite runs
// with made-up cards.
#if canImport(Contacts)

import Foundation
import Contacts

/// His Contacts, read on the iPad for the address fields' list (B-162), as
/// Mail suggests from them while he types.
///
/// iOS asks him first, once. The question goes up the first time he types
/// in To, Cc or Bcc in the app's composer (`heTyped`), where what it is for
/// is in front of him, and never at launch. A yes is read at once and the
/// list offered again for what he has typed; a no is the end of it: nothing
/// read, nothing asked again (`ContactsAccess`). The share extension never
/// asks; it is handed the cards the app read (`ShareMirror`).
///
/// Read again, off the main thread, wherever the share mirror is brought up
/// to date (`AppDelegate.syncShareMirror`): at launch, and as the app goes
/// into and comes back from the background, so a card changed in Contacts
/// is offered from his next return to the app. Only names and addresses
/// are read, of the cards that have an address, and kept in memory; never
/// written anywhere but the share mirror.
final class AddressContacts {

    static let shared = AddressContacts()

    /// Held for the cards and the flag, never across a read of Contacts.
    private let lock = NSLock()
    private var cards: [ContactCard] = []
    /// The question is up: a second keystroke under it asks nothing.
    private var asking = false
    private let queue = DispatchQueue(label: "wtf.uhoh.blackmail.contacts", qos: .userInitiated)

    /// The cards as last read, in Contacts' order; none until read, and
    /// none while he has not said yes.
    func snapshot() -> [ContactCard] {
        lock.lock()
        defer { lock.unlock() }
        return cards
    }

    /// Whether the app may read them, as iOS says now.
    static var access: ContactsAccess {
        ContactsAccess(status: CNContactStore.authorizationStatus(for: .contacts).rawValue)
    }

    /// He has typed in an address field of the app's composer. While iOS's
    /// question has never been answered, it goes up, once; at a yes his
    /// cards are read and `cameIn` is called on the main thread, for the
    /// list to be offered again with them. Anything else asks nothing.
    func heTyped(then cameIn: @escaping () -> Void) {
        guard Self.access.asksWhenHeTypes else { return }
        lock.lock()
        guard !asking else {
            lock.unlock()
            return
        }
        asking = true
        lock.unlock()
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { [self] granted, _ in
            queue.async { [self] in
                if granted { _ = read(from: store) }
                lock.lock()
                asking = false
                lock.unlock()
                if granted { DispatchQueue.main.async(execute: cameIn) }
            }
        }
    }

    /// His cards read again if he has said yes, for the share mirror and
    /// the composer: what was read; none when the app may not read them,
    /// the cards held let go too; nil when they could not be read, the
    /// cards held kept. Never asks. Called off the main thread.
    func readIfAllowed() -> [ContactCard]? {
        guard Self.access == .allowed else {
            keep([])
            return []
        }
        return read(from: CNContactStore())
    }

    /// Every card with an address, in Contacts' own order, up to
    /// `ContactCard.most`; each named as Contacts shows it.
    private func read(from store: CNContactStore) -> [ContactCard]? {
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var found: [ContactCard] = []
        do {
            try store.enumerateContacts(with: request) { contact, stop in
                let addresses = contact.emailAddresses.map { $0.value as String }
                guard !addresses.isEmpty else { return }
                found.append(ContactCard(name: CNContactFormatter.string(from: contact, style: .fullName) ?? "",
                                         givenName: contact.givenName, familyName: contact.familyName,
                                         addresses: addresses))
                if found.count >= ContactCard.most { stop.pointee = true }
            }
        } catch {
            Diagnostics.log(.note, "Contacts: not read (\((error as NSError).code))")
            return nil
        }
        keep(found)
        return found
    }

    private func keep(_ found: [ContactCard]) {
        lock.lock()
        cards = found
        lock.unlock()
    }
}

#endif
