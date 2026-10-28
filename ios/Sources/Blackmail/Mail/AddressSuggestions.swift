import Foundation

/// A person in his Contacts who has an email address, as the address
/// fields offer them (B-162): the name as the Contacts app shows it, the
/// first and last names it is found by, and each address, in the card's
/// order. Read on the iPad by `AddressContacts`; handed to the share
/// extension through `ShareMirror`.
struct ContactCard: Codable, Equatable {
    /// As Contacts shows it (`CNContactFormatter`, full name, in his own
    /// order of first and last), or empty for a card with no name.
    let name: String
    let givenName: String
    let familyName: String
    /// As the card has them, in its order.
    let addresses: [String]

    /// The addresses as the book keeps one (`RecipientBook.keys(for:)`),
    /// lowercased and bare, in the card's order; those that are not an
    /// address left out. Made once, never at a keystroke.
    let keys: [String]
    /// The three names folded (`RecipientBook.folded`), the empty ones left
    /// out: what a name he types is matched against. Made once too, so a
    /// keystroke over some hundreds of cards folds nothing but what he
    /// typed.
    let folded: [String]

    /// The most cards read (`AddressContacts`), and so handed to the share
    /// extension: more than any one man's address book, a bound on a
    /// Keychain item and on every keystroke.
    static let most = 2_000

    init(name: String, givenName: String = "", familyName: String = "", addresses: [String]) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.givenName = givenName
        self.familyName = familyName
        self.addresses = addresses
        var seen = Set<String>()
        keys = addresses
            .map { MailFormat.bareAddress($0.trimmingCharacters(in: .whitespacesAndNewlines)).lowercased() }
            .filter { $0.contains("@") && $0.count > 2 && seen.insert($0).inserted }
        folded = [name, givenName, familyName].map(RecipientBook.folded).filter { !$0.isEmpty }
    }

    private enum CodingKeys: String, CodingKey {
        case name, givenName, familyName, addresses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name),
                  givenName: try c.decode(String.self, forKey: .givenName),
                  familyName: try c.decode(String.self, forKey: .familyName),
                  addresses: try c.decode([String].self, forKey: .addresses))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(givenName, forKey: .givenName)
        try c.encode(familyName, forKey: .familyName)
        try c.encode(addresses, forKey: .addresses)
    }
}

/// Whether the app may read his Contacts, and when it asks (B-162).
///
/// Mail is Apple's own and is never asked. A third-party app reads
/// Contacts only once he has said yes to iOS's question, which iOS puts up
/// once: answered, it never comes again, and only Settings changes it. So
/// it is asked at the one moment its use is plain, the first time he types
/// in To, Cc or Bcc, and never at launch. A no is kept: nothing is read
/// and nothing is asked again.
enum ContactsAccess: Equatable {
    /// Never asked, or asked and the question never answered.
    case notAsked
    /// All his Contacts, or on iPadOS 18 the ones he chose to share.
    case allowed
    /// Declined, or barred on the iPad by a restriction.
    case refused

    /// From `CNAuthorizationStatus`'s raw value: 0 not determined, 1
    /// restricted, 2 denied, 3 authorized, and 4 limited, iPadOS 18's
    /// "Select Contacts", which this SDK (16.5) does not name. A value
    /// newer still is taken as a no: nothing read, nothing asked.
    init(status: Int) {
        switch status {
        case 0: self = .notAsked
        case 3, 4: self = .allowed
        default: self = .refused
        }
    }

    /// Whether his typing in an address field puts the question up: only
    /// while it has never been answered.
    var asksWhenHeTypes: Bool { self == .notAsked }
}

/// The rows an address field offers for what he has typed, from the book
/// of the people he has written to and seen (`RecipientBook`) and from his
/// Contacts (B-162), as Mail offers them.
///
/// Mail suggests, as he types, the people he has written to before (its
/// recents) and the people in his Contacts, each address of a contact
/// with several (Apple's iPadOS 18 guide, "Send email": "As you type, Mail
/// automatically suggests people from your Contacts, along with email
/// addresses for people who have more than one email address"), a person
/// named as Contacts names them. So, of the addresses whose first or last
/// name, or the address itself, starts with what he typed:
///
/// 1. the ones he has written to, first, as the book ranks them;
/// 2. then his Contacts, in the order Contacts lists them, each address of
///    a card in the card's order;
/// 3. then the ones the book has only seen go past, the people whose
///    letters he has received, as the book ranks them: found by the start
///    of a word of their name alone, never by their address (B-177), as
///    Mail's "SIRI FOUND IN APPS" offers "Zqxa Rmfix" for "zqx" and
///    nothing for "zqxa.b" of zqxa.b162@example.net; one with no name, or
///    an address for a name, is not offered;
/// 4. and last, the book's own matches within an address or a name
///    (`RecipientBook.match`, B-017), which Mail does not make, of the
///    people he has written to only.
///
/// One row an address, named as Contacts names it when a card has it.
/// Nothing for nothing typed: the composers never ask with it (B-073).
enum AddressSuggestions {

    static func rank(book: [KnownRecipient], contacts: [ContactCard], matching query: String,
                     besides present: Set<String> = [], limit: Int) -> [KnownRecipient] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else {
            return RecipientBook.rank(book.filter { !present.contains($0.address.lowercased()) },
                                      matching: query, limit: limit)
        }
        let typed = RecipientBook.folded(q)

        // Each address of his Contacts once, under the first card that
        // has it, with its place in the order Contacts lists them.
        var cards: [String: (card: ContactCard, place: Int)] = [:]
        var place = 0
        for card in contacts {
            for key in card.keys where !present.contains(key) {
                if cards[key] == nil { cards[key] = (card, place) }
                place += 1
            }
        }
        var known: [String: KnownRecipient] = [:]
        for entry in book where !present.contains(entry.address.lowercased()) {
            known[entry.address.lowercased()] = entry
        }

        var rows: [Row] = []
        for key in Set(known.keys).union(cards.keys) {
            let entry = known[key]
            let card = cards[key]
            // Only seen: by the start of a word of its name, and never
            // within (B-177).
            let bookTier = entry.flatMap {
                $0.uses > 0 ? RecipientBook.match($0, q) : (startsItsName($0, typed) ? 0 : nil)
            }
            let cardTier = card.flatMap { tier(of: $0.card, address: key, typed: typed, q) }
            let row: Row
            if let start = [bookTier.flatMap { $0 <= 2 ? $0 : nil }, cardTier].compactMap({ $0 }).min() {
                let group = (entry?.uses ?? 0) > 0 ? 0 : (card != nil ? 1 : 2)
                row = Row(starts: true, group: group, tier: start, place: card?.place ?? 0,
                          shown: shown(entry, card?.card, key))
            } else if let within = bookTier {
                row = Row(starts: false, group: 0, tier: within, place: 0,
                          shown: shown(entry, card?.card, key))
            } else {
                continue
            }
            rows.append(row)
        }
        return rows.sorted(by: Row.before).prefix(limit).map(\.shown)
    }

    /// One address offered, and where it goes in the list.
    private struct Row {
        /// Its first or last name, or the address, starts with what he
        /// typed; otherwise one of the book's own matches within.
        let starts: Bool
        /// 0 written to, 1 in his Contacts, 2 seen only.
        let group: Int
        let tier: Int
        /// Its place in Contacts' order, for group 1.
        let place: Int
        let shown: KnownRecipient

        /// Total, so the rows cannot change places between keystrokes: a
        /// row that moves under a finger is a letter to the wrong person
        /// (B-017).
        static func before(_ a: Row, _ b: Row) -> Bool {
            if a.starts != b.starts { return a.starts }
            if a.starts, a.group != b.group { return a.group < b.group }
            if a.tier != b.tier { return a.tier < b.tier }
            if a.starts, a.group == 1, a.place != b.place { return a.place < b.place }
            if a.shown.uses != b.shown.uses { return a.shown.uses > b.shown.uses }
            if a.shown.lastSeen != b.shown.lastSeen { return a.shown.lastSeen > b.shown.lastSeen }
            return a.shown.address < b.shown.address
        }
    }

    /// Where what he typed starts something of a card's: 0 a word of its
    /// first or last name, or of the name Contacts shows, so "car" finds
    /// Sam Carlo and "sam c" finds him too; 1 the address, "scar" finding
    /// scarlo@example.com of his two. Never within a word, as Mail's
    /// matches are the starts of words. Case and accents aside
    /// (`RecipientBook.folded`), so "nun" finds Núñez.
    private static func tier(of card: ContactCard, address: String, typed: String, _ q: String) -> Int? {
        if !typed.isEmpty, card.folded.contains(where: { RecipientBook.startsAWord($0, typed) }) {
            return 0
        }
        if address.hasPrefix(q) { return 1 }
        return nil
    }

    /// Whether `typed`, folded, starts a word of the name the book has for
    /// an address only seen (B-177): "zqx" and "rmf" of "Zqxa Rmfix", and
    /// "zqxa r" too, as his Contacts' names are matched (`tier`). Not a
    /// name that is an address, as some letters name their sender, which
    /// would find it by its address after all. Nor the name of a letter
    /// sent on someone's behalf, "via" a word in it, B-123's rule
    /// (`RecipientBook.onBehalf`): the book keeps the last name it saw at
    /// a group's or a service's address, "'Margaret Ellis' via Garden
    /// Club", and typing her name would offer the whole group.
    private static func startsItsName(_ entry: KnownRecipient, _ typed: String) -> Bool {
        guard !typed.isEmpty, let name = entry.name.map(RecipientBook.folded),
              !name.isEmpty, !name.contains("@"), !RecipientBook.onBehalf(name) else { return false }
        return RecipientBook.startsAWord(name, typed)
    }

    /// The row as the list shows it: the name his Contacts card gives the
    /// address when it has one, as Mail names a person, else the book's;
    /// what the book knows of it kept, so a pick and a send count as ever.
    private static func shown(_ entry: KnownRecipient?, _ card: ContactCard?, _ key: String) -> KnownRecipient {
        var shown = entry ?? KnownRecipient(address: key, name: nil, uses: 0, lastSeen: .distantPast)
        if let card, !card.name.isEmpty { shown.name = card.name }
        return shown
    }
}
