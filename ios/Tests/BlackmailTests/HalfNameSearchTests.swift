import XCTest
@testable import Blackmail

/// A name half typed in search finds that person's letters (B-123).
///
/// Mail's search on the iPad matches the start of words as he types, so
/// "Marg" finds Margaret's letters. Gmail matches whole words only, and the
/// scripted server here does too (`matchesWholeWords`), so "Marg" alone
/// finds nothing. The word he is still typing asks, beside itself, for the
/// From, To or Cc of up to 30 people in the book whose name or address
/// starts with it, in a tree of ORs Gmail parses. A word with a space after
/// it is searched as before.
///
/// Through the shipping `IMAPMailRepository` and `IMAPClient`, over
/// `ScriptedIMAPServer`, and `SearchCriteria` and `RecipientBook` on their
/// own.
final class HalfNameSearchTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "HalfNameSearchTests"

    private static let margaret = Server.Address(name: "Margaret Ellis",
                                                 address: "m.ellis1947@example.net")
    private static let margot = Server.Address(name: "Margot Fay", address: "margot.fay@example.com")

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var clock: ManualClock!
    private var stamp: TimeInterval = 0

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer(inboxCount: 12)
        server.matchesWholeWords = true
        clock = ManualClock()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        Diagnostics.clear()
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        server = nil
        book = nil
        clock = nil
        super.tearDown()
    }

    /// The repository, its account named `name` and listing `others` as
    /// his other addresses; `saved` is the account as Settings saved it
    /// since, as the app reads it for each letter.
    private func makeRepository(name: String = "", others: [String] = [],
                                saved: MailAccount? = nil) -> IMAPMailRepository {
        let clock = self.clock!
        var account = server.account
        account.displayName = name
        account.otherAddresses = others
        return IMAPMailRepository(account: account, password: server.password,
                                  transport: server.transportFactory, saved: { saved },
                                  recipients: book, now: { clock.now() },
                                  shelf: keptShelf(for: account))
    }

    /// A letter newer than every one before it, in `mailboxes`; its
    /// repository ids, by mailbox.
    @discardableResult
    private func deliver(from: Server.Address, to: [Server.Address] = [Server.owner],
                         cc: [Server.Address] = [], _ subject: String, _ text: String,
                         to mailboxes: [String] = [Server.inbox, Server.allMail]) -> [String: String] {
        stamp += 3_600
        var letter = Server.Letter(from: from, to: to, subject: subject,
                                   date: Server.newestDate.addingTimeInterval(stamp),
                                   text: text + "\r\n",
                                   messageID: "<half-\(Int(stamp))@example.org>")
        letter.cc = cc
        let uids = server.deliver(letter, to: mailboxes)
        return uids.reduce(into: [:]) { out, pair in
            out[pair.key] = "\(server.uidValidity(of: pair.key))/\(pair.value)"
        }
    }

    private func search(_ repository: IMAPMailRepository, _ query: String,
                        _ scope: MailSearchScope = .currentMailbox,
                        after: String? = nil, limit: Int = 50) async throws -> [MessageSummary] {
        try await repository.search(in: "inbox", query: query, scope: scope,
                                    beforeUID: after, limit: limit)
    }

    private var searches: [Server.LogEntry] { server.log.filter { $0.verb == "UID SEARCH" } }

    /// `word` in the five fields, a quoted string, one OR for each term
    /// after the first, as RFC 3501 writes OR; with `people`, OR that and
    /// each of them in From, To and Cc, the people in a tree of ORs, each
    /// half in parentheses, the first half the smaller: what the key is,
    /// worked out here on its own.
    private func group(_ word: String, _ people: [String] = []) -> String {
        func row(_ terms: [String]) -> String {
            String(repeating: "OR ", count: terms.count - 1) + terms.joined(separator: " ")
        }
        func tree(_ keys: [String]) -> String {
            guard keys.count > 1 else { return keys[0] }
            let first = keys.count / 2
            return "OR (" + tree(Array(keys.prefix(first))) + ") ("
                + tree(Array(keys.dropFirst(first))) + ")"
        }
        let own = row(["FROM", "TO", "CC", "SUBJECT", "BODY"].map { "\($0) \(word)" })
        guard !people.isEmpty else { return own }
        return "OR " + own + " " + tree(people.map { person in
            row(["FROM", "TO", "CC"].map { "\($0) \"\(person)\"" })
        })
    }

    private func q(_ word: String) -> String { "\"\(word)\"" }

    /// `word` as a literal of its UTF-8 bytes, announced `{n+}`.
    private func literal(_ word: String) -> String { "{\(word.utf8.count)+}\r\n\(word)" }

    /// Margaret's three letters, from her, his to her and one she was
    /// copied on, and one of Carlo's that is not hers, in the folders the
    /// scope looks in: All Mail's ids.
    private func margaretsLetters() -> (from: String, to: String, cc: String, other: String) {
        let from = deliver(from: Self.margaret, "Lunch on Sunday", "Shall we meet at noon?")
        let to = deliver(from: Server.owner, to: [Self.margaret], "Re: Lunch on Sunday",
                         "Noon is fine.", to: [Server.sent, Server.allMail])
        let cc = deliver(from: Server.carlo, cc: [Self.margaret], "The roses",
                         "Cuttings for both of you.")
        let other = deliver(from: Server.carlo, "Seeds", "The seeds came today.")
        return (from[Server.allMail]!, to[Server.allMail]!, cc[Server.allMail]!,
                other[Server.allMail]!)
    }

    // MARK: - Over the wire

    /// "Marg", with no space after it, in All Mailboxes: her letters, from
    /// her, to her and the one she was copied on, and nothing else, every
    /// mailbox asked the word in its five fields and her address in From,
    /// To and Cc beside it, in one group. Learned from the Inbox's rows, as
    /// the app learns every address. Without her address, "Marg" is
    /// nobody's whole word and found nothing.
    func testAHalfNameFindsThatPersonsLetters() async throws {
        let letters = margaretsLetters()
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()

        let found = try await search(repository, "Marg", .allMailboxes)
        XCTAssertEqual(Set(found.map(\.id)), [letters.from, letters.to, letters.cc])
        let asked = "UID SEARCH " + group(q("Marg"), [Self.margaret.address])
        XCTAssertEqual(searches.map(\.command), [asked, asked, asked])
        XCTAssertEqual(searches.map(\.selected), [Server.trash, Server.spam, Server.allMail])
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])

        // The same word with nobody in the book: as before, and nothing.
        book.removeAll()
        server.clearLog()
        let alone = try await search(repository, "Marg", .allMailboxes)
        XCTAssertEqual(alone, [])
        XCTAssertEqual(searches.map(\.command), Array(repeating: "UID SEARCH " + group(q("Marg")),
                                                      count: 3))
    }

    /// Many people whose names start so, as the size test's book had 36
    /// "Pey" on the test iPad (2026-10-25), where "Pey" found four of them
    /// and "Picture Pey" missed the picture letter of a fifth: the first 30
    /// in the book's order are each asked for, their letters found, and
    /// "Picture Pey" finds the tenth's letter about the picture. The server
    /// parses the key as Gmail does, refusing ORs nested past 100.
    func testManyPeopleStartingSoAreAllAskedFor() async throws {
        var ids: [String: String] = [:]
        let addresses = (1...32).map { String(format: "peyton.p%02d@example.org", $0) }
        for (i, address) in addresses.enumerated() {
            let who = Server.Address(name: String(format: "Peyton P%02d", i + 1), address: address)
            let subject = i + 1 == 10 ? "Picture of the garden" : "Note \(i + 1)"
            ids[address] = deliver(from: who, subject, "A few words.")[Server.allMail]!
        }
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()

        let first = Array(addresses.prefix(30))
        let found = try await search(repository, "Pey", .allMailboxes)
        XCTAssertEqual(Set(found.map(\.id)), Set(first.map { ids[$0]! }))
        XCTAssertEqual(searches.map(\.command),
                       Array(repeating: "UID SEARCH " + group(q("Pey"), first), count: 3))
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])

        server.clearLog()
        let picture = try await search(repository, "Picture Pey", .allMailboxes)
        XCTAssertEqual(picture.map(\.id), [ids["peyton.p10@example.org"]!])
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
    }

    /// A half name nobody in the book has, and one of two letters, which
    /// says too little: each asked as before, byte for byte, nobody beside
    /// it. "Zeb" finds nothing; "Ma" finds no Margaret.
    func testAHalfNameWithNobodyInTheBookIsSearchedAsBefore() async throws {
        _ = margaretsLetters()
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()

        let zeb = try await search(repository, "Zeb")
        XCTAssertEqual(zeb, [])
        let ma = try await search(repository, "Ma")
        XCTAssertEqual(ma, [])
        XCTAssertEqual(searches.map(\.command),
                       ["UID SEARCH " + group(q("Zeb")), "UID SEARCH " + group(q("Ma"))])
        XCTAssertEqual(searches.map(\.command),
                       ["UID SEARCH " + SearchCriteria.imap(for: "Zeb")!,
                        "UID SEARCH " + SearchCriteria.imap(for: "Ma")!])
    }

    /// Two words: only the last, the one he is still typing, asks for
    /// people. "lunch Marg" finds her two letters about lunch and not the
    /// one about roses; "Marg Ell" asks for "Marg" whole, as before, and
    /// finds nothing, though "Ell" starts her surname.
    func testOnlyTheLastWordAsksForPeople() async throws {
        let letters = margaretsLetters()
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()

        let lunch = try await search(repository, "lunch Marg", .allMailboxes)
        XCTAssertEqual(Set(lunch.map(\.id)), [letters.from, letters.to])
        let both = try await search(repository, "Marg Ell", .allMailboxes)
        XCTAssertEqual(both, [])
        let lunchKey = "UID SEARCH (\(group(q("lunch")))) (\(group(q("Marg"), [Self.margaret.address])))"
        let bothKey = "UID SEARCH (\(group(q("Marg")))) (\(group(q("Ell"), [Self.margaret.address])))"
        XCTAssertEqual(searches.map(\.command),
                       Array(repeating: lunchKey, count: 3) + Array(repeating: bothKey, count: 3))
    }

    /// A whole word, with a space after it, is searched as it always was:
    /// "Marg " finds nothing, "Margaret " finds her letters by her name,
    /// a word in quote marks is closed by them, and nobody is asked for.
    func testAWholeWordIsSearchedAsBefore() async throws {
        let letters = margaretsLetters()
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()

        let marg = try await search(repository, "Marg ", .allMailboxes)
        XCTAssertEqual(marg, [])
        let margaret = try await search(repository, "Margaret ", .allMailboxes)
        XCTAssertEqual(Set(margaret.map(\.id)), [letters.from, letters.to, letters.cc])
        let quoted = try await search(repository, "“Marg”", .allMailboxes)
        XCTAssertEqual(quoted, [])
        XCTAssertEqual(searches.map(\.command),
                       Array(repeating: "UID SEARCH " + group(q("Marg")), count: 3)
                       + Array(repeating: "UID SEARCH " + group(q("Margaret")), count: 3)
                       + Array(repeating: "UID SEARCH " + group(q("Marg")), count: 3))
    }

    /// A half name with an accent, typed with it or without, and one with
    /// the curly apostrophe his keyboard types: each finds that person,
    /// the word a literal where it is 8-bit, as every such word is
    /// (B-105), and the address beside it quoted.
    func testAnAccentedHalfNameFindsThatPerson() async throws {
        let jose = Server.Address(name: "José Núñez", address: "jnunez@example.es")
        let peggy = Server.Address(name: "Peggy O'Brien", address: "peggy@example.ie")
        let fromJose = deliver(from: jose, "Fotos", "Las fotos del jardín.")
        let fromPeggy = deliver(from: peggy, "Tea", "Tea on Thursday?")
        _ = deliver(from: Server.carlo, "Seeds", "The seeds came today.")
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()

        let accented = try await search(repository, "Núñ")
        XCTAssertEqual(accented.map(\.id), [fromJose[Server.inbox]])
        let plain = try await search(repository, "nun")
        XCTAssertEqual(plain.map(\.id), [fromJose[Server.inbox]])
        let first = try await search(repository, "Jos")
        XCTAssertEqual(first.map(\.id), [fromJose[Server.inbox]])
        let curly = try await search(repository, "O’Bri")
        XCTAssertEqual(curly.map(\.id), [fromPeggy[Server.inbox]])
        XCTAssertEqual(searches.map(\.command), [
            "UID SEARCH CHARSET UTF-8 " + group(literal("Núñ"), [jose.address]),
            "UID SEARCH " + group(q("nun"), [jose.address]),
            "UID SEARCH " + group(q("Jos"), [jose.address]),
            "UID SEARCH CHARSET UTF-8 " + group(literal("O’Bri"), [peggy.address]),
        ])
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
    }

    /// The next page asks what the first asked. A page's own rows teach
    /// the book Margot, who also starts "Marg"; asked again with her, the
    /// search would start over and give its first page twice. So would a
    /// space typed after the word while a page is asked for, its words the
    /// same. A new search asks with both, Margaret first, whom he has
    /// written to.
    func testTheNextPageAsksWhatTheFirstAsked() async throws {
        let d = deliver(from: Self.margaret, "Oldest", "One.")
        let c = deliver(from: Self.margaret, "Older", "Two.")
        let b = deliver(from: Server.carlo, cc: [Self.margaret, Self.margot], "Roses", "Three.")
        let a = deliver(from: Self.margaret, "Newest", "Four.")
        book.used(address: Self.margaret.address, name: Self.margaret.name)
        let repository = makeRepository()
        server.clearLog()

        let first = try await search(repository, "Marg", limit: 1)
        XCTAssertEqual(first.map(\.id), [a[Server.inbox]!])
        let second = try await search(repository, "Marg", after: first.last?.id, limit: 1)
        XCTAssertEqual(second.map(\.id), [b[Server.inbox]!])
        XCTAssertEqual(book.addresses(startingWith: "Marg",
                                      besides: OwnAddresses(account: server.account)),
                       [Self.margaret.address, Self.margot.address])
        let third = try await search(repository, "Marg", after: second.last?.id, limit: 1)
        XCTAssertEqual(third.map(\.id), [c[Server.inbox]!])
        let fourth = try await search(repository, "Marg ", after: third.last?.id, limit: 1)
        XCTAssertEqual(fourth.map(\.id), [d[Server.inbox]!])
        XCTAssertEqual(searches.map(\.command),
                       ["UID SEARCH " + group(q("Marg"), [Self.margaret.address])])

        server.clearLog()
        let again = try await search(repository, "Marg", limit: 2)
        XCTAssertEqual(again.map(\.id), [a[Server.inbox]!, b[Server.inbox]!])
        XCTAssertEqual(searches.map(\.command),
                       ["UID SEARCH " + group(q("Marg"), [Self.margaret.address,
                                                          Self.margot.address])])
    }

    /// Never himself: not his address, nor his other address under his
    /// name, though "Owe" and "Mars" start it and he writes to it most.
    /// Every letter is his, so either would have found them all.
    func testHeIsNeverAskedFor() async throws {
        let marshall = Server.Address(name: "Marshall Gray", address: "mgray@example.com")
        let fromMarshall = deliver(from: marshall, "Chess", "Your move.")
        _ = deliver(from: Server.carlo, "Seeds", "The seeds came today.")
        let repository = makeRepository(name: "Owen Marsh")
        book.used(address: "owen.marsh@example.org", name: "Owen Marsh")
        book.used(address: "owen.marsh@example.org", name: "Owen Marsh")
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()

        let mars = try await search(repository, "Mars")
        XCTAssertEqual(mars.map(\.id), [fromMarshall[Server.inbox]])
        let owe = try await search(repository, "Owe")
        XCTAssertEqual(owe, [])
        XCTAssertEqual(searches.map(\.command), ["UID SEARCH " + group(q("Mars"), [marshall.address]),
                                                 "UID SEARCH " + group(q("Owe"))])
    }

    /// His address, with no name for it: "Own" starts it, and asked for,
    /// every letter, each to him or from him, would be found. As before,
    /// nobody, and nothing.
    func testHisAddressIsNeverAskedFor() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()

        let own = try await search(repository, "Own")
        XCTAssertEqual(own.map(\.id), [])
        XCTAssertEqual(searches.map(\.command), ["UID SEARCH " + group(q("Own"))])
    }

    /// His second address, listed under his account (B-076), is his too:
    /// about half he sends go to it, so asked for, it would find half his
    /// mailbox, newest first. The book holds it as his sends teach it,
    /// with no name, then under the name his letters to it carried, not
    /// his account's, with an old address of his under that name too.
    /// "Vid" starts its part before the @, "Gra" that name: each is asked
    /// byte for byte as before, nobody beside it, and finds nothing. With
    /// the account's own address alone left out, as when the second is
    /// not listed, "Vid" asks for it and finds his letter to it. The same
    /// with the address added in Settings after the app was opened.
    func testHisOtherAddressesAreNeverAskedFor() async throws {
        let second = "owen.videos@example.org"
        let old = "grandpa1936@example.net"
        _ = deliver(from: Server.owner, to: [Server.Address(name: "Grandpa", address: second)],
                    "Watch this", "A link.", to: [Server.sent, Server.allMail])
        book.used(address: second)
        book.used(address: second)
        book.note(address: old, name: "Grandpa")

        // The account not knowing it: his letter to it found by "Vid".
        let unknowing = makeRepository(name: "Owen Marsh")
        _ = try await unknowing.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        let found = try await search(unknowing, "Vid", .allMailboxes)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(searches.map(\.command),
                       Array(repeating: "UID SEARCH " + group(q("Vid"), [second]), count: 3))

        let repository = makeRepository(name: "Owen Marsh", others: [second])
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        let vid = try await search(repository, "Vid", .allMailboxes)
        XCTAssertEqual(vid, [])
        book.note(address: second, name: "Grandpa")
        let gra = try await search(repository, "Gra", .allMailboxes)
        XCTAssertEqual(gra, [])
        XCTAssertEqual(searches.map(\.command),
                       Array(repeating: "UID SEARCH " + group(q("Vid")), count: 3)
                       + Array(repeating: "UID SEARCH " + group(q("Gra")), count: 3))
        XCTAssertEqual(searches.map(\.command),
                       Array(repeating: "UID SEARCH " + SearchCriteria.imap(for: "Vid")!, count: 3)
                       + Array(repeating: "UID SEARCH " + SearchCriteria.imap(for: "Gra")!, count: 3))

        // Added in Settings since: his at once.
        var settings = server.account
        settings.displayName = "Owen Marsh"
        settings.otherAddresses = [second]
        let since = makeRepository(name: "Owen Marsh", saved: settings)
        _ = try await since.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        let later = try await search(since, "Vid", .allMailboxes)
        XCTAssertEqual(later, [])
        let laterName = try await search(since, "Gra", .allMailboxes)
        XCTAssertEqual(laterName, [])
        XCTAssertEqual(searches.map(\.command),
                       Array(repeating: "UID SEARCH " + group(q("Vid")), count: 3)
                       + Array(repeating: "UID SEARCH " + group(q("Gra")), count: 3))
    }

    // MARK: - The word he is still typing

    /// The last word, with nothing typed after it, of three letters or
    /// digits or more. Not after a space, a closing quote mark, a closing
    /// single quote or a dash; not a phrase; not a word past the twenty;
    /// not a word whose text only ends the last one typed, that one
    /// dropped as asked already or past the twenty: "ann" of "Joann ann
    /// joann".
    func testTheWordStillBeingTypedIsTheLastWithNothingAfterIt() {
        let open: [(String, String)] = [
            ("Marg", "Marg"), ("  Marg", "Marg"), ("lunch Marg", "Marg"), ("Marg Ell", "Ell"),
            ("‘Marg", "Marg"), ("“Marg", "Marg"), ("garden—Marg", "Marg"), ("O’Bri", "O’Bri"),
            ("Núñ", "Núñ"), ("m.ell", "m.ell"), ("marg@exa", "marg@exa"), ("Marg marg", "Marg"),
            ("ab1", "ab1"), ("Margaret", "Margaret"), ("ann ‘ann", "ann"), ("ann  Ann", "ann"),
        ]
        for (typed, word) in open {
            XCTAssertEqual(SearchCriteria.halfWord(of: typed), word, typed)
        }
        let closed = ["Marg ", "Marg\n", "Marg\t", "“Marg”", "\"Marg\"", "Marg’", "Marg'",
                      "Marg—", "Ma", "Ma ", "a b", "o’b", "x y z", "", "   ", "“”", "lunch Ma",
                      (1...20).map { "w\($0)" }.joined(separator: " ") + " Marg",
                      "Joann ann joann", "Joann ann Joann",
                      (1...19).map { "w\($0)" }.joined(separator: " ") + " ann Joann",
                      (1...19).map { "w\($0)" }.joined(separator: " ") + " ann Jo’ann"]
        for typed in closed {
            XCTAssertNil(SearchCriteria.halfWord(of: typed), typed)
        }
    }

    /// With no word still being typed, or nobody, the key is byte for byte
    /// what it was; with one, its group alone has the people beside it.
    func testTheKeyIsAsBeforeWithoutAHalfWord() {
        let people = ["m.ellis1947@example.net"]
        for typed in ["Marg ", "garden party ", "“Plan B”", "Ma", "lunch Marg ", "Müller ", "x"] {
            XCTAssertEqual(SearchCriteria.imap(for: typed, people: people),
                           SearchCriteria.imap(for: typed), typed)
        }
        XCTAssertEqual(SearchCriteria.imap(for: "garden party", people: people),
                       "(\(group(q("garden")))) (\(group(q("party"), people)))")
        XCTAssertEqual(SearchCriteria.imap(for: "Marg", people: []), group(q("Marg")))
        XCTAssertEqual(SearchCriteria.imap(for: "Marg", people: people), group(q("Marg"), people))
    }

    /// The key's shape for one, two and three people, written out by hand:
    /// the word's five, then each person's three in a tree of ORs.
    func testThePeopleAreATreeOfOrs() {
        let word = #"OR OR OR OR FROM "pey" TO "pey" CC "pey" SUBJECT "pey" BODY "pey""#
        let a = #"OR OR FROM "a@x.org" TO "a@x.org" CC "a@x.org""#
        let b = #"OR OR FROM "b@x.org" TO "b@x.org" CC "b@x.org""#
        let c = #"OR OR FROM "c@x.org" TO "c@x.org" CC "c@x.org""#
        XCTAssertEqual(SearchCriteria.anyField("pey", people: ["a@x.org"]), "OR \(word) \(a)")
        XCTAssertEqual(SearchCriteria.anyField("pey", people: ["a@x.org", "b@x.org"]),
                       "OR \(word) OR (\(a)) (\(b))")
        XCTAssertEqual(SearchCriteria.anyField("pey", people: ["a@x.org", "b@x.org", "c@x.org"]),
                       "OR \(word) OR (\(a)) (OR (\(b)) (\(c)))")
        XCTAssertEqual(SearchCriteria.anyField("pey"), word)
    }

    /// At most 30 people, in the order given; an address over 100 bytes,
    /// one that is no address, one with a control character, one given
    /// twice in any case and the word itself passed over; each escaped.
    /// The line grows by at most 30 addresses in three fields, and its ORs
    /// nest at most 30 deep, counted generously, where Gmail parses about
    /// 100 and a row of 30 people's would be 94.
    func testAtMostThirtyPeopleAndNoLongAddress() throws {
        XCTAssertEqual(SearchCriteria.mostPeople, 30)
        let long = String(repeating: "a", count: 90) + "@example.com"
        XCTAssertGreaterThan(long.utf8.count, SearchCriteria.longestAddress)
        let exactly = String(repeating: "b", count: 88) + "@example.com"
        XCTAssertEqual(exactly.utf8.count, SearchCriteria.longestAddress)
        let people = [long, "nobody", "bad\r\n@example.com", "marg@example.com",
                      "MARG@example.com", "one@example.com", "\"o\\b\"@example.com", exactly,
                      "five@example.com", "six@example.com"]
        let key = try XCTUnwrap(SearchCriteria.imap(for: "marg@example.com", people: people))
        XCTAssertEqual(key, group(q("marg@example.com"),
                                  ["one@example.com", "\\\"o\\\\b\\\"@example.com", exactly,
                                   "five@example.com", "six@example.com"]))
        XCTAssertEqual(SearchCriteria.askable(people, besides: "Marg"),
                       ["marg@example.com", "one@example.com", "\"o\\b\"@example.com", exactly,
                        "five@example.com", "six@example.com"])

        // 40 offered: the first 30, in their order.
        let many = (1...40).map { "p\($0)@example.com" }
        XCTAssertEqual(SearchCriteria.askable(many, besides: "Pey"), Array(many.prefix(30)))
        XCTAssertEqual(SearchCriteria.imap(for: "Pey", people: many),
                       group(q("Pey"), Array(many.prefix(30))))

        // The most it adds: 30 of the longest, three fields each, and the
        // tree's ORs and parentheses.
        let longest = (10...49).map { "\($0)" + String(repeating: "x", count: 86) + "@example.com" }
        XCTAssertEqual(Set(longest.map(\.utf8.count)), [SearchCriteria.longestAddress])
        let grown = try XCTUnwrap(SearchCriteria.imap(for: "Marg", people: longest))
        let plain = try XCTUnwrap(SearchCriteria.imap(for: "Marg"))
        let addresses = 30 * ("OR OR FROM \"\" TO \"\" CC \"\"".count + 3 * 100)
        let tree = "OR ".count + " ".count + 29 * "OR () ()".count
        XCTAssertEqual(grown.utf8.count - plain.utf8.count, addresses + tree)
        XCTAssertLessThan(grown.utf8.count, 11_000)

        // How deep the ORs nest: an OR inside an OR, counted.
        var deepest = 0, depth = 0, open: [Int] = []
        for word in grown.replacingOccurrences(of: "(", with: "( ")
            .replacingOccurrences(of: ")", with: " )").split(separator: " ") {
            switch word {
            case "OR": depth += 1; deepest = max(deepest, depth)
            case "(": open.append(depth)
            case ")": depth = open.removeLast()
            default: break
            }
        }
        XCTAssertLessThanOrEqual(deepest, 30, "a row would be 94")
    }

    // MARK: - The book

    private func person(_ name: String?, _ address: String, uses: Int = 0,
                        seen: TimeInterval = 0) -> KnownRecipient {
        KnownRecipient(address: address, name: name, uses: uses,
                       lastSeen: Date(timeIntervalSince1970: 1_000_000 + seen))
    }

    /// Where a word starts: any word of the name, a word of the address
    /// before the @, or the whole address; never the middle of a word, and
    /// never the part after the @. Ignoring case, accents and apostrophes.
    func testABookEntryMatchesWhereAWordStarts() {
        let all = [
            person("Margaret Ellis", "m.ellis1947@example.net"),
            person("José Núñez", "jnunez@example.es"),
            person("Peggy O'Brien", "peggy@example.ie"),
            person(nil, "smith-jones@example.org"),
            person("Rosemary Hill", "rhill@example.com"),
            person(nil, "info@margate.example"),
            person("Margery Hunt via Garden Club", "garden-club@groups.example"),
            person("Marjorie Lowe (via Shared Docs)", "docs-noreply@example.com"),
            person("Silvia Rand", "srand@example.com"),
        ]
        func found(_ typed: String) -> [String] {
            RecipientBook.addresses(all, startingWith: typed,
                                    besides: OwnAddresses(["owner@example.com"]))
        }
        XCTAssertEqual(found("Marg"), ["m.ellis1947@example.net"])
        XCTAssertEqual(found("ELL"), ["m.ellis1947@example.net"])
        XCTAssertEqual(found("m.el"), ["m.ellis1947@example.net"])
        XCTAssertEqual(found("m.ellis1947@exa"), ["m.ellis1947@example.net"])
        XCTAssertEqual(found("Núñ"), ["jnunez@example.es"])
        XCTAssertEqual(found("nun"), ["jnunez@example.es"])
        XCTAssertEqual(found("jose"), ["jnunez@example.es"])
        XCTAssertEqual(found("O’Bri"), ["peggy@example.ie"])
        XCTAssertEqual(found("obri"), ["peggy@example.ie"])
        XCTAssertEqual(found("jon"), ["smith-jones@example.org"])
        XCTAssertEqual(found("smith-jo"), ["smith-jones@example.org"])
        // A letter sent on someone's behalf: not by that name, which the
        // relay's address carried last, but by the address; "via" is a word.
        XCTAssertEqual(found("Marge"), [])
        XCTAssertEqual(found("Marj"), [])
        XCTAssertEqual(found("Hunt"), [])
        XCTAssertEqual(found("gard"), ["garden-club@groups.example"])
        XCTAssertEqual(found("docs"), ["docs-noreply@example.com"])
        XCTAssertEqual(found("Silv"), ["srand@example.com"])
        // The middle of a word, the domain: nobody.
        XCTAssertEqual(found("mary"), [])
        XCTAssertEqual(found("arg"), [])
        XCTAssertEqual(found("exa"), [])
        XCTAssertEqual(found("ate"), [])
        XCTAssertEqual(found(""), [])
    }

    /// Best first: where the word starts, a name before an address; then
    /// the addresses he has written to most, then those seen last, then by
    /// address, so the order never shuffles. Each of his own addresses and
    /// any under a name the book has for one of them are left out.
    func testTheBookOrdersThemAndLeavesHimOut() {
        let all = [
            person("Owen Marsh", "owner@example.com", uses: 40),
            person("Owen Marsh", "owen.marsh@example.org", uses: 900),
            person(nil, "mark.d@example.com", uses: 9, seen: 9),
            person("Mark Ames", "ames@example.com", uses: 1, seen: 1),
            person("Mary Ward", "mward@example.com", uses: 3, seen: 0),
            person("Marlene Ott", "lott@example.com", uses: 0, seen: 50),
            person("Marco Tull", "tull@example.com", uses: 0, seen: 50),
            person(nil, "mar@example.com"),
        ]
        let him = OwnAddresses(["Owner@Example.com"])
        XCTAssertEqual(RecipientBook.addresses(all, startingWith: "Mar", besides: him),
                       ["mward@example.com", "ames@example.com", "lott@example.com",
                        "tull@example.com", "mark.d@example.com", "mar@example.com"])
        XCTAssertEqual(RecipientBook.addresses(all, startingWith: "Owe", besides: him), [])
        XCTAssertEqual(RecipientBook.addresses(all, startingWith: "Own", besides: him), [])
        // With no name for his address, only his address is left out: the
        // other is nobody the app knows to be him.
        var unnamed = all
        unnamed[0].name = nil
        XCTAssertEqual(RecipientBook.addresses(unnamed, startingWith: "Owe", besides: him),
                       ["owen.marsh@example.org"])
        XCTAssertEqual(RecipientBook.addresses(unnamed, startingWith: "Own", besides: him), [])

        // His second address listed as his (B-076): left out with no name,
        // under its own name, and with any other address under that name.
        let both = OwnAddresses(["owner@example.com", "owen.marsh@example.org"])
        XCTAssertEqual(RecipientBook.addresses(unnamed, startingWith: "Owe", besides: both), [])
        var renamed = unnamed
        renamed[1].name = "Grandpa"
        renamed.append(person("Grandpa", "grandpa1936@example.net", uses: 2))
        renamed.append(person("Grace Hill", "ghill@example.com"))
        XCTAssertEqual(RecipientBook.addresses(renamed, startingWith: "Gra", besides: both),
                       ["ghill@example.com"])
        XCTAssertEqual(RecipientBook.addresses(renamed, startingWith: "Gra", besides: him),
                       ["owen.marsh@example.org", "grandpa1936@example.net", "ghill@example.com"])
        unnamed[1].name = nil
        XCTAssertEqual(RecipientBook.addresses(unnamed, startingWith: "owen.m", besides: both), [])
    }

    // MARK: - The list

    /// The list hands the field's text to the repository as he typed it,
    /// a space after the last word included, after the same 350 ms pause,
    /// in the scope the band shows; a recent search tapped, the words as
    /// kept.
    func testTheListHandsTheTextAsTyped() throws {
        let band = try source("UI/SearchHeaderView.swift")
        XCTAssertNotNil(band.range(of: "onQueryChanged?(field.text ?? \"\")"))
        let list = try source("UI/MessageListViewController.swift")
        for wired in [
            "private static let searchDelay = Duration.milliseconds(350)",
            "searchBar.onQueryChanged = { [weak self] text in self?.queryChanged(text) }",
            "searchDebounce = Task { @MainActor [weak self] in try? await Task.sleep(for: Self.searchDelay) "
                + "guard !Task.isCancelled else { return } await self?.runSearch(text) }",
            "outcome = .success(try await repository.search( in: mailbox.id, query: text, "
                + "scope: scope, beforeUID: nil, limit: Self.pageSize))",
        ] {
            XCTAssertNotNil(list.range(of: wired), wired)
        }
    }

    /// `path` is under `Sources/Blackmail`, comments out and white space
    /// one space, as `RecentSearchesTests` reads it.
    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }
}
