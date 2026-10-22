import XCTest
@testable import Blackmail

/// A search for a word a quoted string cannot carry (B-105): Müller, é,
/// and the curly ’ his iPad's Smart Punctuation types in every "don’t".
///
/// Gmail answers BAD to 8-bit text in a quoted string, with CHARSET UTF-8
/// or without (measured read-only on the test account, 2026-10-22), and
/// the scripted server answers as it does. On the iPad every such search
/// read "Could not search. Check the connection.", and since B-105 puts
/// every word in one command, one such letter anywhere in what he typed
/// sank the whole search. Such a word goes as a literal: `{7+}`, a line
/// break and its bytes where the server advertises LITERAL- or LITERAL+,
/// as Gmail advertises LITERAL-, and `{7}` and a wait for "+" where it
/// does not, or past LITERAL-'s 4,096 bytes.
///
/// Through the shipping `IMAPMailRepository` and `IMAPClient`, over
/// `ScriptedIMAPServer`, and `IMAPWireCommand` on its own.
final class SearchLiteralTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "SearchLiteralTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var clock: ManualClock!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        clock = ManualClock()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        Diagnostics.clear()
    }

    override func tearDown() {
        // Nothing here may have put two commands in flight on one
        // connection, a literal's bytes written before its "+" included.
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        server = nil
        book = nil
        clock = nil
        super.tearDown()
    }

    private func makeRepository() -> IMAPMailRepository {
        let clock = self.clock!
        return IMAPMailRepository(account: server.account, password: server.password,
                                  transport: server.transportFactory, recipients: book,
                                  now: { clock.now() }, shelf: keptShelf(for: server.account))
    }

    /// A letter from Carlo, its body `text`, newer than every seeded one,
    /// in the Inbox and All Mail unless `mailboxes` says otherwise; its
    /// repository ids, by mailbox.
    @discardableResult
    private func deliver(_ subject: String, _ text: String,
                         to mailboxes: [String] = [Server.inbox, Server.allMail]) -> [String: String] {
        let uids = server.deliver(
            Server.Letter(from: Server.carlo, to: [Server.owner], subject: subject,
                          date: Server.newestDate.addingTimeInterval(3_600), text: text + "\r\n",
                          messageID: "<\(subject.filter { $0.isLetter })@example.org>"),
            to: mailboxes)
        return uids.reduce(into: [:]) { out, pair in
            out[pair.key] = "\(server.uidValidity(of: pair.key))/\(pair.value)"
        }
    }

    private func search(_ repository: IMAPMailRepository, _ query: String,
                        _ scope: MailSearchScope = .currentMailbox) async throws -> [MessageSummary] {
        try await repository.search(in: "inbox", query: query, scope: scope,
                                    beforeUID: nil, limit: 50)
    }

    private var searches: [Server.LogEntry] { server.log.filter { $0.verb == "UID SEARCH" } }

    /// `word` asked for in the five fields, as a literal of its UTF-8
    /// bytes: announced `{n+}` unless `announced` says otherwise, then a
    /// line break and the bytes, as RFC 3501 and RFC 7888 spell it.
    private func anyField(_ word: String,
                          _ announced: (Int) -> String = { "{\($0)+}" }) -> String {
        let literal = announced(word.utf8.count) + "\r\n" + word
        return "OR OR OR OR FROM \(literal) TO \(literal) CC \(literal) SUBJECT \(literal) BODY \(literal)"
    }

    /// `word` in the five fields as a quoted string, as an ASCII word goes.
    private func quotedInAnyField(_ word: String) -> String {
        "OR OR OR OR FROM \"\(word)\" TO \"\(word)\" CC \"\(word)\" SUBJECT \"\(word)\" BODY \"\(word)\""
    }

    // MARK: - The command

    /// Nothing 8-bit in it, and the command goes byte for byte as it was
    /// given, in every form: his ASCII words, a quoted phrase, escapes, a
    /// Message-ID, a date, a range of UIDs. So every search that worked
    /// before goes exactly as it went.
    func testACommandWithNoEightBitTextGoesAsItWas() throws {
        let commands = [
            "UID SEARCH " + (try XCTUnwrap(SearchCriteria.imap(for: "garden"))),
            "UID SEARCH " + (try XCTUnwrap(SearchCriteria.imap(for: "margaret “Plan B” O'Brien e-mail"))),
            "UID SEARCH " + (try XCTUnwrap(SearchCriteria.imap(for: "back\\slash 'quoted' a\"b"))),
            "UID SEARCH HEADER Message-ID \"<draft-1@example.com>\"",
            "UID SEARCH RETURN (MIN) SENTSINCE \"02-Sep-2026\"",
            "UID SEARCH UID 1004:*",
            "UID SEARCH ALL",
        ]
        for form in [IMAPLiteralForm.plus, .minus, .synchronising] {
            for command in commands {
                let wire = IMAPWireCommand(command, literals: form)
                XCTAssertEqual(wire.line, command, "\(form)")
                XCTAssertEqual(wire.continuations, [], "\(form)")
                XCTAssertEqual(wire.logged, command, "\(form)")
            }
        }
    }

    /// A word with an accent is a literal of its UTF-8 bytes: at once on
    /// Gmail's LITERAL- and on LITERAL+, after the server's "+" on a server
    /// with neither. The log has it on one line.
    func testAWordWithAnAccentIsALiteralOfItsBytes() {
        let command = "UID SEARCH CHARSET UTF-8 BODY \"Müller\""
        let atOnce = IMAPWireCommand(command, literals: .minus)
        XCTAssertEqual(atOnce.line, "UID SEARCH CHARSET UTF-8 BODY {7+}\r\nMüller")
        XCTAssertEqual(atOnce.continuations, [])
        XCTAssertEqual(atOnce.logged, "UID SEARCH CHARSET UTF-8 BODY {7+} Müller")
        XCTAssertEqual(IMAPWireCommand(command, literals: .plus), atOnce)

        let waiting = IMAPWireCommand(command, literals: .synchronising)
        XCTAssertEqual(waiting.line, "UID SEARCH CHARSET UTF-8 BODY {7}")
        XCTAssertEqual(waiting.continuations, [Data("Müller".utf8)])
        XCTAssertEqual(waiting.logged, "UID SEARCH CHARSET UTF-8 BODY {7} Müller")
    }

    /// A literal is what the quoted string said, its escapes taken back:
    /// a quote and a backslash go as themselves, raw. A quote with an
    /// accent after it, one character of two scalars, the same.
    func testALiteralHoldsWhatTheQuotedStringSaid() {
        let word = "O\"Brien’s\\"
        let wire = IMAPWireCommand("BODY \"\(SearchCriteria.escape(word))\"", literals: .minus)
        XCTAssertEqual(wire.line, "BODY {12+}\r\n" + word)
        XCTAssertEqual(word.utf8.count, 12)

        let accented = "a\"\u{301}b"
        let marked = IMAPWireCommand("BODY \"\(SearchCriteria.escape(accented))\"", literals: .minus)
        XCTAssertEqual(marked.line, "BODY {5+}\r\n" + accented)
    }

    /// LITERAL-'s limit: 4,096 bytes go at once, and one byte more waits
    /// for "+", the rest of the command written after it, a short word's
    /// `{n+}` in it as ever. On LITERAL+ no size waits; on a server with
    /// neither, every literal does, each with its own "+".
    func testPastLITERALMinusLimitALiteralWaitsForTheServer() {
        let limit = String(repeating: "é", count: 2_048)
        XCTAssertEqual(limit.utf8.count, 4_096)
        XCTAssertEqual(IMAPWireCommand("BODY \"\(limit)\"", literals: .minus).line,
                       "BODY {4096+}\r\n" + limit)

        let over = limit + "e"
        let wire = IMAPWireCommand("(BODY \"\(over)\") (BODY \"Müller\") (BODY \"garden\")",
                                   literals: .minus)
        XCTAssertEqual(wire.line, "(BODY {4097}")
        XCTAssertEqual(wire.continuations,
                       [Data((over + ") (BODY {7+}\r\nMüller) (BODY \"garden\")").utf8)])
        XCTAssertEqual(wire.logged, "(BODY {4097} \(over)) (BODY {7+} Müller) (BODY \"garden\")")
        XCTAssertEqual(IMAPWireCommand("BODY \"\(over)\"", literals: .plus).line,
                       "BODY {4097+}\r\n" + over)

        let each = IMAPWireCommand("FROM \"Müller\" TO \"é\" CC \"x\"", literals: .synchronising)
        XCTAssertEqual(each.line, "FROM {7}")
        XCTAssertEqual(each.continuations, [Data("Müller TO {2}".utf8), Data("é CC \"x\"".utf8)])
    }

    /// A quoted string with no end is not a string to send: it goes as it
    /// is, for the server to refuse, as it was.
    func testAQuotedStringWithNoEndIsLeftAsItIs() {
        let wire = IMAPWireCommand("BODY \"Müller", literals: .minus)
        XCTAssertEqual(wire.line, "BODY \"Müller")
        XCTAssertEqual(wire.continuations, [])
    }

    /// The form is the server's, from what it advertised after LOGIN; with
    /// nothing known, the one every server takes.
    func testTheFormIsTheServers() {
        XCTAssertEqual(IMAPLiteralForm(capabilities: ["IMAP4REV1", "LITERAL-"]), .minus)
        XCTAssertEqual(IMAPLiteralForm(capabilities: ["LITERAL+", "LITERAL-"]), .plus)
        XCTAssertEqual(IMAPLiteralForm(capabilities: ["IMAP4REV1", "ESEARCH"]), .synchronising)
        XCTAssertEqual(IMAPLiteralForm(capabilities: []), .synchronising)
    }

    // MARK: - On Gmail's terms

    /// Müller, in either scope: found, in the folder and in every mailbox
    /// of an All Mailboxes search, Trash, Spam and All Mail each asked
    /// once, the word a literal in all five fields, and nothing answered
    /// BAD. This is what read "Could not search" on the iPad.
    func testAWordWithAnAccentIsFoundInBothScopes() async throws {
        let garden = deliver("The garden", "The garden is ready for the party with Herr Müller.")
        let binned = deliver("Binned roses", "Herr Müller's roses.", to: [Server.trash])
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        server.clearLog()

        let here = try await search(repository, "Müller")
        XCTAssertEqual(here.map(\.id), [garden[Server.inbox]])
        let asked = "UID SEARCH CHARSET UTF-8 \(anyField("Müller"))"
        XCTAssertEqual(searches.map(\.command), [asked])
        XCTAssertEqual(searches.map(\.selected), [Server.inbox])
        XCTAssertEqual(searches.map(\.status), ["OK"])

        server.clearLog()
        let everywhere = try await search(repository, "Müller", .allMailboxes)
        XCTAssertEqual(Set(everywhere.map(\.id)), [garden[Server.allMail], binned[Server.trash]])
        XCTAssertEqual(searches.map(\.command), [asked, asked, asked])
        XCTAssertEqual(searches.map(\.selected), [Server.trash, Server.spam, Server.allMail])
        XCTAssertEqual(searches.map(\.status), ["OK", "OK", "OK"])
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// The curly ’ of "don’t", as Smart Punctuation types it: found, alone
    /// and with an ASCII word beside it, which goes in its quoted strings
    /// byte for byte as before.
    func testTheCurlyApostropheOfDontIsFound() async throws {
        let rain = deliver("We don’t mind the rain", "See you Tuesday.")
        let repository = makeRepository()
        server.clearLog()

        let alone = try await search(repository, "don’t")
        XCTAssertEqual(alone.map(\.id), [rain[Server.inbox]])
        XCTAssertEqual("don’t".utf8.count, 7)
        XCTAssertEqual(searches.map(\.command), ["UID SEARCH CHARSET UTF-8 \(anyField("don’t"))"])

        server.clearLog()
        let two = try await search(repository, "don’t rain")
        XCTAssertEqual(two.map(\.id), [rain[Server.inbox]])
        XCTAssertEqual(searches.map(\.command),
                       ["UID SEARCH CHARSET UTF-8 (\(anyField("don’t"))) (\(quotedInAnyField("rain")))"])
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
    }

    /// A paragraph pasted from a letter, its curly quotes around a phrase
    /// and its apostrophes curly: found, every word with ’ in it a literal,
    /// the quoted phrase one, the ASCII words quoted as before, in one
    /// SEARCH answered OK.
    func testAPastedParagraphWithCurlyQuotesAndApostrophesIsFound() async throws {
        let paragraph = "“I don’t think we’ll manage Tuesday,” Margaret wrote. It’s the garden "
            + "party, and Carlo’s bringing the roses he’s grown since May."
        let letter = deliver("Tuesday", paragraph)
        let repository = makeRepository()
        server.clearLog()

        let found = try await search(repository, paragraph)
        XCTAssertEqual(found.map(\.id), [letter[Server.inbox]])
        let sent = try XCTUnwrap(searches.last)
        XCTAssertEqual(searches.count, 1)
        XCTAssertEqual(sent.status, "OK")
        XCTAssertTrue(sent.command.hasPrefix("UID SEARCH CHARSET UTF-8 ("), sent.command)
        let words = SearchCriteria.words(of: paragraph)
        XCTAssertEqual(words.first, "I don’t think we’ll manage Tuesday,")
        XCTAssertEqual(words.filter { !$0.unicodeScalars.allSatisfy(\.isASCII) },
                       ["I don’t think we’ll manage Tuesday,", "It’s", "Carlo’s", "he’s"])
        for word in words {
            let group = word.unicodeScalars.allSatisfy(\.isASCII)
                ? quotedInAnyField(word) : anyField(word)
            XCTAssertTrue(sent.command.contains("(\(group))"), word)
        }
        XCTAssertEqual(sent.command.components(separatedBy: ") (").count, words.count)
    }

    /// A phrase pasted long, over LITERAL-'s 4,096 bytes: it waits for the
    /// server's "+" in each of the five fields, and is found. Sent at once,
    /// as `{4829+}`, Gmail's limit would refuse it.
    func testAPhraseOverLITERALMinusLimitWaitsForItsPlusAndIsFound() async throws {
        let phrase = Array(repeating: "the garden’s roses", count: 230).joined(separator: " ")
        XCTAssertGreaterThan(phrase.utf8.count, 4_096)
        let roses = deliver("Roses", phrase)
        let repository = makeRepository()
        server.clearLog()

        let found = try await search(repository, "“\(phrase)”")
        XCTAssertEqual(found.map(\.id), [roses[Server.inbox]])
        XCTAssertEqual(searches.map(\.command),
                       ["UID SEARCH CHARSET UTF-8 \(anyField(phrase) { "{\($0)}" })"])
        XCTAssertEqual(searches.map(\.status), ["OK"])
    }

    // MARK: - Other servers

    /// A server with neither LITERAL+ nor LITERAL-: every literal waits
    /// for its "+", and the search is found, on the one connection, the
    /// stream in step.
    func testAServerWithoutLITERALTakesEachWordAfterItsPlus() async throws {
        server.withheldCapabilities = ["LITERAL-"]
        let garden = deliver("The garden", "The garden is ready for Herr Müller.")
        let repository = makeRepository()
        server.clearLog()

        let found = try await search(repository, "Müller garden")
        XCTAssertEqual(found.map(\.id), [garden[Server.inbox]])
        XCTAssertEqual(searches.map(\.command),
                       ["UID SEARCH CHARSET UTF-8 (\(anyField("Müller") { "{\($0)}" })) "
                        + "(\(quotedInAnyField("garden")))"])
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// A server with LITERAL+ takes a literal of any size at once.
    func testAServerWithLITERALPlusTakesALongPhraseAtOnce() async throws {
        server.withheldCapabilities = ["LITERAL-"]
        server.addedCapabilities = ["LITERAL+"]
        let phrase = Array(repeating: "the garden’s roses", count: 230).joined(separator: " ")
        let roses = deliver("Roses", phrase)
        let repository = makeRepository()
        server.clearLog()

        let found = try await search(repository, "“\(phrase)”")
        XCTAssertEqual(found.map(\.id), [roses[Server.inbox]])
        XCTAssertEqual(searches.map(\.command), ["UID SEARCH CHARSET UTF-8 \(anyField(phrase))"])
        XCTAssertEqual(searches.map(\.status), ["OK"])
    }

    // MARK: - Answered BAD

    /// A server that will not take CHARSET answers BAD, and the search
    /// goes again without it, its word still a literal, and is found.
    func testACharsetRefusedGoesAgainWithItsWordStillALiteral() async throws {
        server.refusesCharset = true
        let garden = deliver("The garden", "Herr Müller.")
        let repository = makeRepository()
        server.clearLog()

        let found = try await search(repository, "Müller")
        XCTAssertEqual(found.map(\.id), [garden[Server.inbox]])
        XCTAssertEqual(searches.map { "\($0.command) \($0.status ?? "")" },
                       ["UID SEARCH CHARSET UTF-8 \(anyField("Müller")) BAD",
                        "UID SEARCH \(anyField("Müller")) OK"])
    }

    /// A search the server refuses is still a search that could not be
    /// run, which the list says as "Could not search", and not "No
    /// results": refused in the folder, and refused in All Mail, the
    /// mailbox an All Mailboxes search pages.
    func testASearchRefusedIsStillOneThatCouldNotBeRun() async throws {
        deliver("The garden", "Herr Müller.")
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        server.refusedVerbs = ["UID SEARCH"]
        server.clearLog()

        for scope in [MailSearchScope.currentMailbox, .allMailboxes] {
            do {
                _ = try await search(repository, "Müller", scope)
                XCTFail("a refused search found something: \(scope)")
            } catch {
                XCTAssertEqual(error as? MailError, .cannotConnect, "\(scope)")
            }
        }
        XCTAssertFalse(searches.isEmpty)
        XCTAssertEqual(Set(searches.map(\.status)), ["NO"])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// A literal refused at its announcement, BAD in place of the "+":
    /// nothing more of the command is sent, his word is not read as a
    /// command of its own, and the search is one that could not be run.
    /// The connection stays in step, and the next search on it is found.
    func testALiteralRefusedBeforeItsPlusSendsNothingMore() async throws {
        server.withheldCapabilities = ["LITERAL-"]
        server.refusesLiterals = true
        let garden = deliver("The garden", "Herr Müller.")
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)
        server.clearLog()

        do {
            _ = try await search(repository, "Müller")
            XCTFail("a refused search found something")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        XCTAssertEqual(searches.map { "\($0.command) \($0.status ?? "")" },
                       ["UID SEARCH CHARSET UTF-8 OR OR OR OR FROM {7} BAD",
                        "UID SEARCH OR OR OR OR FROM {7} BAD"])

        server.refusesLiterals = false
        let found = try await search(repository, "Müller")
        XCTAssertEqual(found.map(\.id), [garden[Server.inbox]])
        XCTAssertTrue(Set(server.log.map(\.verb)).isSubset(of: ["NOOP", "UID SEARCH", "UID FETCH"]),
                      "\(server.log)")
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    // MARK: - Every SEARCH

    /// The lowest match alone, Go to Date's SEARCH (`IMAPClient.page`),
    /// goes the same way: its own words are a date, and a word with an
    /// accent in its place is a literal too.
    func testTheLowestMatchAsksWithItsWordAsALiteral() async throws {
        let client = IMAPClient(account: server.account, transport: server.transportFactory)
        try await client.connect(password: server.password)
        let uids = server.deliver(
            Server.Letter(from: Server.carlo, to: [Server.owner], subject: "The garden",
                          date: Server.newestDate.addingTimeInterval(3_600),
                          text: "Herr Müller.\r\n", messageID: "<garden@example.org>"),
            to: [Server.inbox])
        server.clearLog()

        let opened = try await client.page(in: Server.inbox,
                                           searching: [.lowest("BODY \"Müller\""), "ALL"]) { _ in [] }
        XCTAssertEqual(opened.found[0].uids, [try XCTUnwrap(uids[Server.inbox])])
        XCTAssertEqual(searches.map { "\($0.command) \($0.status ?? "")" },
                       ["UID SEARCH RETURN (MIN) CHARSET UTF-8 BODY {7+}\r\nMüller OK",
                        "UID SEARCH ALL OK"])
    }

    // MARK: - The log

    /// The connection log has the search on one line, each literal as its
    /// announcement and its word, and his words no more often than they
    /// were in it before, in their quoted strings: put back in quotes, the
    /// line is the one the build before wrote. On a server that makes each
    /// wait for its "+", the same line, once.
    func testTheLogHasTheSearchOnOneLineAndHisWordsAsBefore() async throws {
        let paragraph = "“I don’t think we’ll manage Tuesday,” Margaret wrote. It’s the garden "
            + "party, and Carlo’s bringing the roses he’s grown since May."
        deliver("Tuesday", paragraph)
        let before = "UID SEARCH CHARSET UTF-8 " + (try XCTUnwrap(SearchCriteria.imap(for: paragraph)))

        for withheld in [[], ["LITERAL-"]] {
            server.withheldCapabilities = Set(withheld)
            let repository = makeRepository()
            _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 20)
            Diagnostics.clear()

            let found = try await search(repository, paragraph)
            XCTAssertEqual(found.count, 1, "\(withheld)")

            let lines = Diagnostics.entries.map(\.text)
            XCTAssertFalse(lines.contains { $0.contains("\r") || $0.contains("\n") }, "\(lines)")
            let sent = Diagnostics.entries.filter { $0.direction == .sent }.map(\.text)
            let searched = sent.filter { $0.contains(" UID SEARCH ") }
            XCTAssertEqual(searched.count, 1, "\(withheld): \(sent)")
            var line = String(try XCTUnwrap(searched.first).drop { $0 != " " }.dropFirst())
            let announced: (Int) -> String = withheld.isEmpty ? { "{\($0)+}" } : { "{\($0)}" }
            for word in SearchCriteria.words(of: paragraph) where !word.unicodeScalars.allSatisfy(\.isASCII) {
                XCTAssertTrue(line.contains(announced(word.utf8.count) + " " + word), word)
                line = line.replacingOccurrences(of: announced(word.utf8.count) + " " + word,
                                                 with: "\"\(SearchCriteria.escape(word))\"")
            }
            XCTAssertEqual(line, before, "\(withheld)")
            // Nowhere else: not in a line of its own, not in an answer.
            let others = lines.filter { !$0.contains(" UID SEARCH ") }
            XCTAssertFalse(others.contains { $0.contains("Carlo’s") || $0.contains("manage Tuesday") },
                           "\(others)")
        }
    }
}
