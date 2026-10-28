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

/// The addresses the composer can offer instead of making him type, and
/// the people search asks for beside a name he is still typing, so "Marg"
/// finds Margaret's letters (`addresses(startingWith:besides:)`, B-123).
///
/// The reason this exists is one fact: he *sends emails
/// to himself*, constantly, and he is ninety. Every one of those meant
/// typing a full address on a glass keyboard with no comma key and no
/// uppercase — and the same for every Cc, to people he writes to every
/// week. Mail has autocompleted addresses since before the iPad this is
/// modelled on.
///
/// **Not backed by Contacts.** The addresses here come from his own
/// mailbox, which he already has: every envelope the message list fetches
/// is harvested on the way past, at no extra network cost, because the
/// list already asks for ENVELOPE to draw a row. His Contacts are offered
/// beside them since B-162, as Mail offers them, by the address fields'
/// list (`AddressSuggestions`), never kept here. Until then they were left
/// out on purpose, for the question iOS asks first; the owner chose Mail's
/// way on 2026-10-26.
///
/// **And from his Sent Mail, once per account** (B-155). Mail suggests
/// everyone he has written to from its Recents; a book that learned only
/// from the rows listed missed about half the people he writes to in a
/// month until one of their letters was listed. So the envelopes of the
/// last six months of his Sent Mail are read once, after the Inbox's first
/// page (`IMAPMailRepository.fillBookFromSent`), and the people he wrote to
/// go in as written to (`writtenTo`, `fill`), within the 300, his own
/// addresses never pushed out.
///
/// **The people only seen are kept apart** (B-177). Mail offers someone
/// whose letter he has only received, by name, under "SIRI FOUND IN
/// APPS"; where it puts them beside its Recents and his Contacts was not
/// seen. Filled from Sent Mail, the 300 held nobody else, and an address
/// noted from a letter went out again at once to make room. So the
/// addresses only seen have a bound of their own (`seenCapacity`) beside
/// the 300 of his own and the people he has written to (`evictIfNeeded`),
/// and the address fields offer them by their name alone, after the people
/// he has written to and his Contacts, the plan's order
/// (`AddressSuggestions`).
///
/// Stored in `UserDefaults` alongside the account for the same reason the
/// account is: none of it is secret. It is a list of people he corresponds
/// with, already sitting in plaintext on the server.
final class RecipientBook {

    static let shared = RecipientBook()

    /// Enough to cover anyone he writes to, small enough that the ranking
    /// stays instant and `UserDefaults` stays a reasonable home. His own
    /// addresses and the people he has written to (`uses` above nothing).
    static let capacity = 300

    /// The addresses only seen go past, never chosen and none of his own,
    /// beside the 300 and bounded apart (B-177): the people whose letters
    /// he has received, the newest kept. Until then they shared the 300,
    /// and once the fill from Sent Mail had filled it each went as it came.
    static let seenCapacity = 300

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
    /// His own addresses as the account last told the book
    /// (`keepOwn`): never evicted. Under `lock` with `entries`. Empty until
    /// a repository is made, which is before anything is noted.
    private var own = OwnAddresses([])
    /// The addresses in the book that are his own (`own`), so that the
    /// eviction and a note ask a set and do not take each address apart
    /// again (`OwnAddresses.contains`). Made again whenever `own` is told
    /// (`keepOwn`, `fill`) or the book is read (`load`), and added to as an
    /// address new to the book is noted; the eviction never drops one of
    /// them. Under `lock` with `entries`.
    private var ownInBook = Set<String>()
    /// Held for the dictionary, the flag and the addresses of his own, and
    /// for nothing else: never across the encode or the write to the
    /// defaults. A keystroke waits at most for one `record`, and never for
    /// a flush. A `record` of addresses the book has, as most of a page's
    /// are, is a few lookups; one with an address new to a full book also
    /// drops the oldest of its part (`evictIfNeeded`), a pass over the 600.
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

    /// His own address, under the name his account gives him: it replaces
    /// any name the book had for it, and an account with no name leaves it
    /// with none (B-082). Noted at each launch and at each Save in
    /// Settings, so a changed name is the one offered at once. A letter
    /// going past in a list does not name his address
    /// (`IMAPMailRepository.rows`): an old letter of his carries the name
    /// he had then.
    ///
    /// Counted as written to, once at least (B-177): his own address is
    /// never one only seen, which the address fields offer by its name
    /// alone, and "own" still finds owner@example.com under his name.
    func noteOwn(address: String, name: String) {
        let keys = Self.keys(for: address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        guard keys.count == 1, let key = keys.first, key.contains("@"), key.count > 2 else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        lock.lock()
        defer { lock.unlock() }
        let known = entries[key]
        var entry = known ?? KnownRecipient(address: key, name: nil, uses: 0,
                                            lastSeen: .distantPast)
        // A part can have grown only if the address is new to the book or
        // was only seen until now (`evictIfNeeded`).
        let grown = known == nil || entry.uses == 0
        if known == nil, own.contains(key) { ownInBook.insert(key) }
        entry.name = trimmed.isEmpty ? nil : trimmed
        entry.uses = max(entry.uses, 1)
        entry.lastSeen = Date()
        entries[key] = entry
        if grown { evictIfNeeded() }
        dirty = true
    }

    /// His own addresses, the account's and every other Settings lists,
    /// which the book never evicts (B-155). Told by each repository as it
    /// is made, and again by the fill from his Sent Mail. Filled with the
    /// people he wrote to, the book holds few entries never chosen, and his
    /// own, noted at launch and seldom chosen, were the first a newsletter
    /// noted next would have pushed out.
    ///
    /// Each of his own in the book counted as written to, once at least, as
    /// a note of it would (`record`, B-177): one the book had only seen
    /// before the account listed it as his is never one only seen, here
    /// nor in a book read again before his addresses are told (`load`).
    /// And the parts held to their bounds again at once (`evictIfNeeded`):
    /// one of his counts in the 300 from here, one he has taken off counts
    /// as anyone else, and a note of an address the book has does not look
    /// at them.
    func keepOwn(_ mine: OwnAddresses) {
        lock.lock()
        defer { lock.unlock() }
        own = mine
        findOwnInBook()
        let before = entries.count
        // Written back whole, not as `entries[key]?.uses = 1`. A change
        // made in place inside a Dictionary compiles, with this toolchain,
        // to a coroutine that needs `swift_coroFrameAlloc`, which the iOS
        // 16 runtime does not have, and the device link fails.
        for key in ownInBook {
            guard var entry = entries[key], entry.uses == 0 else { continue }
            entry.uses = 1
            entries[key] = entry
            dirty = true
        }
        evictIfNeeded()
        if entries.count != before { dirty = true }
    }

    /// `ownInBook` made again from `own` and the whole book. The caller
    /// holds `lock`.
    private func findOwnInBook() {
        ownInBook = Set(entries.keys.filter { own.contains($0) })
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
        // Whether a part of the book can have grown past its bound: an
        // address new to it, or one only seen now written to. A note of an
        // address the book has, as most of a page's are, changes no part's
        // size and does not look at them (`evictIfNeeded`), so it costs
        // what it did before B-177.
        var grown = false
        for key in keys {
            let known = entries[key]
            var entry = known ?? KnownRecipient(address: key, name: nil, uses: 0,
                                                lastSeen: .distantPast)
            if known == nil, own.contains(key) { ownInBook.insert(key) }
            let wasSeen = entry.uses == 0
            // A name once learned is kept unless a better one turns up.
            // Senders routinely arrive bare in one message and named in the
            // next.
            if keys.count == 1, let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                entry.name = name.trimmingCharacters(in: .whitespaces)
            }
            if chosen { entry.uses += 1 }
            // His own, as the account lists them, are never only seen
            // (B-177): his second address is found by its start, as the
            // people he writes to are.
            if ownInBook.contains(key) { entry.uses = max(entry.uses, 1) }
            if known == nil || (wasSeen && entry.uses > 0) { grown = true }
            entry.lastSeen = seen
            entries[key] = entry
        }
        if grown { evictIfNeeded() }
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

    /// Drops the oldest of a part that is over its bound (B-177): the
    /// people he has written to, with his own, held to the 300 (`capacity`),
    /// and those only seen to theirs (`seenCapacity`). Someone he has
    /// actually written to survives a thousand newsletters, and the sender
    /// of a letter he received survives the fill from his Sent Mail. Never
    /// one of his own addresses (`ownInBook`, B-155), which count in the
    /// 300. The caller holds `lock`.
    ///
    /// Until B-177 the book had the one bound, and what was only seen went
    /// first: filled with the people he wrote to, it kept no one else.
    private func evictIfNeeded() {
        guard entries.count > min(Self.capacity, Self.seenCapacity) else { return }
        var written: [KnownRecipient] = []
        var seen: [KnownRecipient] = []
        for entry in entries.values where !ownInBook.contains(entry.address) {
            if entry.uses > 0 {
                written.append(entry)
            } else {
                seen.append(entry)
            }
        }
        for (part, bound) in [(written, Self.capacity - ownInBook.count), (seen, Self.seenCapacity)]
        where part.count > bound {
            let oldest = part.sorted {
                if $0.lastSeen != $1.lastSeen { return $0.lastSeen < $1.lastSeen }
                return $0.address < $1.address
            }
            for entry in oldest.prefix(part.count - max(0, bound)) {
                entries[entry.address] = nil
            }
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
    /// offer Carlo before it offers anyone at `oscarexample.com`. Asked by
    /// the address fields' list beside his Contacts too
    /// (`AddressSuggestions`, B-162): 0 to 2 are starts, 3 and 4 within.
    static func match(_ entry: KnownRecipient, _ q: String) -> Int? {
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

    // MARK: - Search (B-123)

    /// The addresses of the people a word he is still typing in search may
    /// be the start of, best first: every entry whose name or address
    /// starts with it (`startTier`), as Mail's search on the iPad matches
    /// the start of words, ignoring case and accents. `SearchCriteria`
    /// asks for the first few of them beside the word.
    ///
    /// Never his own: none of `mine`, the addresses his account lists as
    /// his and its login (`OwnAddresses(account:)`), nor an address under
    /// a name the book has for any of them. Every letter in his mailbox is
    /// to him or from him, and about half he sends go to his second
    /// address, so one of his beside "Bla" would turn a search for Blair
    /// into his whole mailbox, or half of it; his own name, typed whole,
    /// still finds what it found. Asked of `mine` and not of the names
    /// alone: the book names his second address with whatever his letters
    /// to it carried (`IMAPMailRepository.rows` passes over only the
    /// account's own), or with nothing.
    func addresses(startingWith word: String, besides mine: OwnAddresses) -> [String] {
        lock.lock()
        let all = Array(entries.values)
        lock.unlock()
        return Self.addresses(all, startingWith: word, besides: mine)
    }

    /// The pure half of `addresses(startingWith:besides:)`. In order of
    /// where the word starts (a name's word, then the address's part
    /// before the @, then the whole address), then as the composer's
    /// suggestions go: the addresses he has written to most, then the
    /// ones seen last, then by address, so the order is total.
    static func addresses(_ all: [KnownRecipient], startingWith word: String,
                          besides mine: OwnAddresses) -> [String] {
        let typed = folded(word)
        guard !typed.isEmpty else { return [] }
        let hisNames = Set(all.filter { mine.contains($0.address) }
            .compactMap { $0.name.map(folded) }
            .filter { !$0.isEmpty })

        let scored: [(KnownRecipient, Int)] = all.compactMap { entry in
            guard !mine.contains(entry.address) else { return nil }
            if let name = entry.name, hisNames.contains(folded(name)) { return nil }
            guard let tier = startTier(entry, typed) else { return nil }
            return (entry, tier)
        }
        return scored.sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            if a.0.uses != b.0.uses { return a.0.uses > b.0.uses }
            if a.0.lastSeen != b.0.lastSeen { return a.0.lastSeen > b.0.lastSeen }
            return a.0.address < b.0.address
        }
        .map { $0.0.address }
    }

    /// Where `typed`, folded, starts a word of the entry: 0 for a word of
    /// its name, 1 for one of its address before the @, "ellis" of
    /// "m.ellis1947", 2 for the whole address, "margaret@exa"; nil for
    /// none. Never the part after the @: "gmai" is the start of most of
    /// his correspondents' addresses, and of nobody's name.
    ///
    /// Not the name of a letter sent on someone's behalf, which has "via"
    /// as a word in it: "'Margaret Ellis' via Garden Club" at the group's
    /// address, "Jane Doe via LinkedIn" at the service's. The book keeps
    /// the last name it saw for an address, so Margaret's name would ask
    /// for every letter of the group, other people's too. Its address is
    /// matched as any other.
    private static func startTier(_ entry: KnownRecipient, _ typed: String) -> Int? {
        if let name = entry.name.map(folded), !onBehalf(name), startsAWord(name, typed) {
            return 0
        }
        let address = folded(entry.address)
        let local = address.lastIndex(of: "@").map { String(address[..<$0]) } ?? address
        if startsAWord(local, typed) { return 1 }
        if address.hasPrefix(typed) { return 2 }
        return nil
    }

    /// Whether a folded name has "via" as a word in it, "(via" too.
    private static func onBehalf(_ name: String) -> Bool {
        name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains("via")
    }

    /// Whether `typed` is at the start of `text` or just after a character
    /// that is not a letter or a digit: a space, a dot, a hyphen, "<".
    static func startsAWord(_ text: String, _ typed: String) -> Bool {
        var atAStart = true
        var index = text.startIndex
        while index < text.endIndex {
            if atAStart, text[index...].hasPrefix(typed) { return true }
            atAStart = !text[index].isLetter && !text[index].isNumber
            index = text.index(after: index)
        }
        return false
    }

    /// Lower case, accents off, so "nun" starts "Núñez", and "mül" and
    /// "mul" both start "Müller"; apostrophes, straight or curly, out, so
    /// "O’Bri", as his keyboard types it, starts "O'Brien"
    /// (`SearchCriteria.singleQuotes`); each run of white space one space.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .filter { !SearchCriteria.singleQuotes.contains($0) }
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    // MARK: - From his Sent Mail (B-155)

    /// The people his letters went to, from their envelopes in Sent Mail,
    /// best first: each letter's To, Cc and Bcc, an address counted once a
    /// letter and never one of his own (`mine`), so a letter only to his
    /// own addresses gives nothing. Each as written to: `uses` the letters
    /// to it, `lastSeen` when the newest of them went, Gmail's date for it
    /// (INTERNALDATE) or else its Date, and the name the newest letter
    /// naming it gave it. In the order the composer ranks by: the most
    /// letters first, then the newest, then by address, so it is total.
    static func writtenTo(_ letters: [IMAPFetchResult], besides mine: OwnAddresses) -> [KnownRecipient] {
        var people: [String: KnownRecipient] = [:]
        var namedAt: [String: Date] = [:]
        for letter in letters {
            guard let envelope = letter.envelope else { continue }
            let went = letter.internalDate ?? envelope.date ?? .distantPast
            var counted = Set<String>()
            for to in envelope.to + envelope.cc + envelope.bcc {
                // A group's name, "undisclosed-recipients", has no host,
                // and is nobody (`OwnAddresses.key`).
                guard let key = OwnAddresses.key(to.address), key.count > 2, !mine.contains(key),
                      counted.insert(key).inserted else { continue }
                var person = people[key]
                    ?? KnownRecipient(address: key, name: nil, uses: 0, lastSeen: .distantPast)
                person.uses += 1
                person.lastSeen = max(person.lastSeen, went)
                let name = (to.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, name.lowercased() != key, went >= namedAt[key] ?? .distantPast {
                    person.name = name
                    namedAt[key] = went
                }
                people[key] = person
            }
        }
        return people.values.sorted { a, b in
            if a.uses != b.uses { return a.uses > b.uses }
            if a.lastSeen != b.lastSeen { return a.lastSeen > b.lastSeen }
            return a.address < b.address
        }
    }

    /// The people his Sent Mail says he wrote to (`writtenTo`) taken in as
    /// written to, in their order, as many as the 300 holds beside the
    /// addresses of his own in it, which are never pushed out (`mine`, kept
    /// from now as `keepOwn` keeps it). An entry the book has keeps its
    /// name, or takes this one if it has none, and the larger count and
    /// the later date, so a letter sent from the app and counted as it went
    /// (`used`) is not counted twice. What no longer fits in the 300 goes,
    /// the oldest first; the addresses only seen are kept apart, beside it
    /// (`seenCapacity`, B-177). Written out by the caller (`flush`).
    /// Returns how many were taken in.
    ///
    /// And each of his own in the book counted one more than anyone taken
    /// in, if it was not already. His letters to himself are not counted,
    /// so on the first day his own address, chosen from the app once or
    /// never, came below everyone whose name or address starts as his and
    /// whom he wrote to, until he had sent to himself as often. He writes
    /// to himself more than to anyone; Mail's Recents would count those
    /// letters, and this stands in for them.
    @discardableResult
    func fill(with people: [KnownRecipient], besides mine: OwnAddresses) -> Int {
        lock.lock()
        defer { lock.unlock() }
        own = mine
        findOwnInBook()
        let room = Self.capacity - ownInBook.count
        var taken = 0
        var most = 0
        for person in people where !mine.contains(person.address) {
            guard taken < room else { break }
            var entry = entries[person.address]
                ?? KnownRecipient(address: person.address, name: nil, uses: 0, lastSeen: .distantPast)
            if (entry.name ?? "").isEmpty, let name = person.name, !name.isEmpty {
                entry.name = name
            }
            entry.uses = max(entry.uses, person.uses)
            entry.lastSeen = max(entry.lastSeen, person.lastSeen)
            entries[person.address] = entry
            most = max(most, entry.uses)
            taken += 1
        }
        if taken > 0 {
            for var entry in entries.values where ownInBook.contains(entry.address) {
                entry.uses = max(entry.uses, most + 1)
                entries[entry.address] = entry
            }
        }
        evictIfNeeded()
        if taken > 0 { dirty = true }
        return taken
    }

    private static let filledKey = "blackmail.recipients.filledFromSent"

    /// Whether the book has been filled from the Sent Mail of the account
    /// at `address` (`IMAPMailRepository.fillBookFromSent`): once per
    /// account, in any letter case, kept with the book.
    func filledFromSent(account address: String) -> Bool {
        (defaults.stringArray(forKey: Self.filledKey) ?? []).contains(Self.accountKey(address))
    }

    /// The fill from that account's Sent Mail done, never to be asked
    /// again.
    func markFilledFromSent(account address: String) {
        var filled = defaults.stringArray(forKey: Self.filledKey) ?? []
        let key = Self.accountKey(address)
        guard !filled.contains(key) else { return }
        filled.append(key)
        defaults.set(filled, forKey: Self.filledKey)
    }

    private static func accountKey(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
        findOwnInBook()
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
        ownInBook = []
        dirty = false
        lock.unlock()
        defaults.removeObject(forKey: Self.storageKey)
    }
}
