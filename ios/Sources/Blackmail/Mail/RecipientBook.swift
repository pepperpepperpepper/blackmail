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

    private var entries: [String: KnownRecipient] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Recording

    /// Seen in passing — in a list, or on a message he opened.
    func note(address: String, name: String? = nil) {
        record(address: address, name: name, chosen: false)
    }

    /// Actually addressed a letter to. Ranks above anything merely seen.
    func used(address: String, name: String? = nil) {
        record(address: address, name: name, chosen: true)
    }

    private func record(address: String, name: String?, chosen: Bool) {
        let key = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // A bare word is not an address, and neither is an empty one.
        guard key.contains("@"), key.count > 2 else { return }

        var entry = entries[key] ?? KnownRecipient(address: key, name: nil, uses: 0,
                                                   lastSeen: .distantPast)
        // A name once learned is kept unless a better one turns up. Senders
        // routinely arrive bare in one message and named in the next.
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            entry.name = name.trimmingCharacters(in: .whitespaces)
        }
        if chosen { entry.uses += 1 }
        entry.lastSeen = Date()
        entries[key] = entry
        evictIfNeeded()
        save()
    }

    /// Drops the least useful when full: never-chosen entries first, oldest
    /// first within that. Someone he has actually written to survives a
    /// thousand newsletters.
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
        Self.rank(Array(entries.values), matching: query, limit: limit)
    }

    /// The pure half, so the ordering can be tested without a store.
    ///
    /// An EMPTY query is deliberately not empty-handed: it offers the
    /// addresses he uses most, which is what makes writing to himself one
    /// tap instead of a whole address.
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

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode([KnownRecipient].self, from: data)
        else { return }
        entries = Dictionary(stored.map { ($0.address, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Array(entries.values)) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Test seam.
    func removeAll() {
        entries = [:]
        defaults.removeObject(forKey: Self.storageKey)
    }
}
