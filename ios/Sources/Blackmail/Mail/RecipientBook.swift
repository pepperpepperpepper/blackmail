import Foundation

/// One address he has written to, or that has written to him.
struct KnownRecipient: Codable, Equatable {
    /// Lowercased, and the identity of the entry.
    let address: String
    /// The display name last seen with it, if any.
    var name: String?
    /// How many letters he has actually ADDRESSED to it. Seeing an address
    /// go past in a list does not count; choosing it does.
    var uses: Int
    var lastSeen: Date

    /// What the suggestion row says. The name when there is one, because
    /// "Margaret Ellis" is recognisable and
    /// "m.ellis1947@example.net" is a puzzle.
    var display: String {
        guard let name, !name.isEmpty else { return address }
        return name
    }
}

/// The addresses the composer can offer instead of making him type.
///
/// The reason this exists is one fact: he *sends emails
/// to himself*, constantly, and he is ninety. Every one of those meant
/// typing a full address on a glass keyboard with no comma key and no
/// uppercase — and the same for every Cc, to people he writes to every
/// week. Mail has autocompleted addresses since before the iPad this is
/// modelled on.
///
/// **Not backed by Contacts, on purpose.** The Contacts framework would put
/// a permission prompt in front of a man who will not know what it is
/// asking, and a "Don't Allow" tapped once is invisible and permanent. The
/// addresses here come from his own mailbox, which he already has: every
/// envelope the message list fetches is harvested on the way past, at no
/// extra network cost, because the list already asks for ENVELOPE to draw a
/// row.
///
/// Stored in `UserDefaults` alongside the account for the same reason the
/// account is: none of it is secret. It is a list of people he corresponds
/// with, already sitting in plaintext on the server.
final class RecipientBook {

    static let shared = RecipientBook()

    /// Enough to cover anyone he writes to, small enough that the ranking
    /// stays instant and `UserDefaults` stays a reasonable home.
    static let capacity = 300

    /// How many rows the composer offers at once.
    static let suggestionLimit = 4

    private static let storageKey = "blackmail.recipients"

    /// Written from the repository's actor as envelopes go past, and read on
    /// the main thread at every keystroke in an address field, so every
    /// touch of it is under `lock`. Without it a read that met a write
    /// could crash the app: `suggestions(for:)` copying the values while an
    /// insert or an eviction rebuilt the dictionary.
    private var entries: [String: KnownRecipient] = [:]
    /// Something has changed since the book was last written out. Under
    /// `lock` with `entries`, because a flush from one thread has to see
    /// what another has noted.
    private var dirty = false
    /// Held for the dictionary and the flag, and for nothing else: never
    /// across the encode or the write to the defaults. A keystroke waits at
    /// most for one `record`, a few microseconds, and never for a flush.
    /// Not an actor for the same reason: that would make `suggestions(for:)`
    /// async, and the rows would appear a run-loop turn after the letter he
    /// typed.
    private let lock = NSLock()
    /// Puts flushes in single file, and is taken by nothing else. Two at
    /// once, from the repository and from the app going into the
    /// background, could otherwise finish in the other order and leave the
    /// older copy on disk. Neither the composer nor a note ever waits on it.
    private let flushing = NSLock()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Recording

    /// Seen in passing — in a list, or on a message he opened.
    ///
    /// Kept in memory only. Whoever notes a batch flushes once when it is
    /// done: the repository at the end of each page of rows. Writing the
    /// whole book out per address meant re-encoding three hundred entries
    /// a hundred times for every fifty rows, about 1.2 ms each time, on the
    /// repository's actor, so every other call to it waited for the page.
    func note(address: String, name: String? = nil) {
        record(address: address, name: name, chosen: false)
    }

    /// Actually addressed a letter to. Ranks above anything merely seen.
    ///
    /// Written out at once. It happens once per recipient of a letter he
    /// sends, and a use is the one thing about an address that watching his
    /// mail go past cannot teach the book again.
    func used(address: String, name: String? = nil) {
        record(address: address, name: name, chosen: true)
        flush()
    }

    /// Each address filed under itself (`keys(for:)`): "jane@example.com;",
    /// as a share sent by a build before B-081 can still hand the app
    /// (`ShareMirror.takeSent`), is Jane's. A name goes only with an
    /// address that is one.
    private func record(address: String, name: String?, chosen: Bool) {
        let keys = Self.keys(for: address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            // A bare word is not an address, and neither is an empty one.
            .filter { $0.contains("@") && $0.count > 2 }
        guard !keys.isEmpty else { return }

        let seen = Date()

        lock.lock()
        defer { lock.unlock() }
        for key in keys {
            var entry = entries[key] ?? KnownRecipient(address: key, name: nil, uses: 0,
                                                       lastSeen: .distantPast)
            // A name once learned is kept unless a better one turns up.
            // Senders routinely arrive bare in one message and named in the
            // next.
            if keys.count == 1, let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                entry.name = name.trimmingCharacters(in: .whitespaces)
            }
            if chosen { entry.uses += 1 }
            entry.lastSeen = seen
            entries[key] = entry
        }
        evictIfNeeded()
        dirty = true
    }

    /// The addresses a key of the book stands for, each as a key: lowercased
    /// and bare. Most are one address and come back as they are.
    ///
    /// A build before B-081 learned an address with the ";" typed after it,
    /// "jane@example.com;", and two typed with a ";" between them as one,
    /// "a@example.com; b@example.com". Kept so, the list offered Jane twice,
    /// once with the ";", and offered "jane@example.com;" again after Jane
    /// was already a bubble, and the pick made a second bubble for her.
    /// Split at a comma or a ";" as the field is (`MailFormat.addresses(in:)`),
    /// these are "jane@example.com", and "a@example.com" and
    /// "b@example.com".
    ///
    /// Split only when every piece is an address. A malformed
    /// "a;b@example.com", as a letter's header can hold it, stays whole:
    /// split, it would file it under "b@example.com", whom nobody wrote to
    /// (`MailFormat.recipientEntry`).
    static func keys(for address: String) -> [String] {
        let pieces = MailFormat.addresses(in: address).map { MailFormat.bareAddress($0).lowercased() }
        guard !pieces.isEmpty, pieces.allSatisfy({ $0.contains("@") && $0.count > 2 }) else {
            return [address]
        }
        var seen = Set<String>()
        return pieces.filter { seen.insert($0).inserted }
    }

    /// A book as it was stored, each entry filed under its own address
    /// (`keys(for:)`), so one kept by a build before B-081 offers each
    /// person once, without a ";". Two entries for one address become one:
    /// their uses added, the later seen kept, and the name of the entry
    /// that was already that address alone, or else the first name found.
    /// An entry holding several addresses gives each its uses, and no name.
    /// A book with nothing to file again comes back as it was, entry for
    /// entry, in its order.
    static func filed(_ stored: [KnownRecipient]) -> [KnownRecipient] {
        var filed: [String: KnownRecipient] = [:]
        // In the order stored, so the result does not depend on how a
        // dictionary happened to be ordered.
        var order: [String] = []
        for entry in stored {
            let keys = Self.keys(for: entry.address)
            for key in keys {
                var kept: KnownRecipient
                if let known = filed[key] {
                    kept = known
                } else {
                    order.append(key)
                    kept = KnownRecipient(address: key, name: nil, uses: 0, lastSeen: .distantPast)
                }
                if keys.count == 1, let name = entry.name,
                   (kept.name ?? "").isEmpty || (key == entry.address && !name.isEmpty) {
                    kept.name = name
                }
                kept.uses += entry.uses
                kept.lastSeen = max(kept.lastSeen, entry.lastSeen)
                filed[key] = kept
            }
        }
        return order.compactMap { filed[$0] }
    }

    /// Drops the least useful when full: never-chosen entries first, oldest
    /// first within that. Someone he has actually written to survives a
    /// thousand newsletters. The caller holds `lock`.
    private func evictIfNeeded() {
        guard entries.count > Self.capacity else { return }
        let ordered = entries.values.sorted {
            if ($0.uses > 0) != ($1.uses > 0) { return $0.uses == 0 }
            return $0.lastSeen < $1.lastSeen
        }
        for entry in ordered.prefix(entries.count - Self.capacity) {
            entries[entry.address] = nil
        }
    }

    // MARK: - Suggesting

    func suggestions(for query: String, limit: Int = RecipientBook.suggestionLimit)
        -> [KnownRecipient] {
        // Copied under the lock and ranked outside it: the ranking takes
        // about a millisecond, the copy a few microseconds.
        lock.lock()
        let all = Array(entries.values)
        lock.unlock()
        return Self.rank(all, matching: query, limit: limit)
    }

    /// Every entry, as it stands. What the share extension is handed
    /// (`ShareMirror`): it cannot read these defaults, and without them his
    /// own second address, the one most of his shared links go to, would
    /// have to be typed out in full on every share.
    func snapshot() -> [KnownRecipient] {
        lock.lock()
        defer { lock.unlock() }
        return Array(entries.values)
    }

    /// The pure half, so the ordering can be tested without a store.
    ///
    /// An EMPTY query is not empty-handed: it gives every entry, the ones
    /// he uses most first. The composers never ask with one. Since B-073
    /// an address field offers nothing until he types, as Mail's does
    /// (`ComposeForm.suggestions`).
    static func rank(_ all: [KnownRecipient], matching query: String,
                     limit: Int) -> [KnownRecipient] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let scored: [(KnownRecipient, Int)] = all.compactMap { entry in
            guard !q.isEmpty else { return (entry, 0) }
            guard let score = match(entry, q) else { return nil }
            return (entry, score)
        }

        return scored.sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }                 // better tier first
            if a.0.uses != b.0.uses { return a.0.uses > b.0.uses }
            if a.0.lastSeen != b.0.lastSeen { return a.0.lastSeen > b.0.lastSeen }
            return a.0.address < b.0.address                    // total, so it is stable
        }
        .prefix(limit)
        .map(\.0)
    }

    /// Lower is better. nil means no match at all.
    ///
    /// Tiered rather than a single substring test because the tiers are
    /// what put the obvious answer on the first row: typing "car" should
    /// offer Carlo before it offers anyone at `oscarexample.com`.
    private static func match(_ entry: KnownRecipient, _ q: String) -> Int? {
        let address = entry.address
        let local = address.split(separator: "@").first.map(String.init) ?? address
        let nameWords = (entry.name ?? "").lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)

        if nameWords.contains(where: { $0.hasPrefix(q) }) { return 0 }
        if local.hasPrefix(q) { return 1 }
        if address.hasPrefix(q) { return 2 }
        if address.contains(q) { return 3 }
        if (entry.name ?? "").lowercased().contains(q) { return 4 }
        return nil
    }

    // MARK: - Storage

    /// The book as last written out. One kept by a build before B-081 is
    /// filed again as it loads, each address under itself (`filed`), and
    /// written out again at the next flush; the share sheet's copy of it is
    /// made again from this one when the app next syncs it (`ShareMirror`).
    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode([KnownRecipient].self, from: data)
        else { return }
        let filed = Self.filed(stored)
        lock.lock()
        defer { lock.unlock() }
        entries = Dictionary(filed.map { ($0.address, $0) }, uniquingKeysWith: { a, _ in a })
        if stored.contains(where: { Self.keys(for: $0.address) != [$0.address] }) {
            dirty = true
        }
        evictIfNeeded()
    }

    /// Writes the book out if anything has changed since it last was.
    ///
    /// Once per page of rows from the repository, at once for an address he
    /// has sent to, and when the app goes into the background. What was
    /// noted since the last flush is lost if the app is killed first, which
    /// costs nothing: the next listing notes it again.
    ///
    /// The entries are copied under `lock` and encoded outside it, so a
    /// keystroke never waits for the encode. A fresh `JSONEncoder` each
    /// time is deliberate; keeping one was measured and bought nothing.
    func flush() {
        flushing.lock()
        defer { flushing.unlock() }

        lock.lock()
        guard dirty else {
            lock.unlock()
            return
        }
        let snapshot = Array(entries.values)
        dirty = false
        lock.unlock()

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Test seam.
    func removeAll() {
        lock.lock()
        entries = [:]
        dirty = false
        lock.unlock()
        defaults.removeObject(forKey: Self.storageKey)
    }
}
