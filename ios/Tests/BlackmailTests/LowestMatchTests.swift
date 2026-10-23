import XCTest
@testable import Blackmail

/// A date jump's SEARCH asks for the lowest UID it matches and nothing else
/// (B-063): `UID SEARCH RETURN (MIN) …` where the server advertises ESEARCH
/// (RFC 4731), as Gmail does, and a plain SEARCH where it does not or will
/// not answer it. Through the real `IMAPClient.page` against the scripted
/// server, whose ESEARCH answers as RFC 4731 has them. Since B-115 the
/// SEARCH for his day itself is asked whole and its letters' dates fetched,
/// and the spans after it each for its lowest UID alone.
final class LowestMatchTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private var server: ScriptedIMAPServer!

    /// Every Inbox letter sent on or after the 101st's day: the newest
    /// twenty, by the seed's one letter a day.
    private let recent = "SENTSINCE \"02-Sep-2026\""
    /// Nothing in the Inbox was sent so late.
    private let none = "SENTSINCE \"01-Jan-2031\""

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        Diagnostics.clear()
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        server = nil
        super.tearDown()
    }

    private func connectedClient() async throws -> IMAPClient {
        let client = IMAPClient(account: server.account, transport: server.transportFactory)
        try await client.connect(password: server.password)
        return client
    }

    /// What a plain SEARCH says is the lowest letter matched, on a client
    /// of its own, so the answer under test is held to the old way's.
    private func lowestByPlainSearch(_ criteria: String) async throws -> UInt32? {
        let client = try await connectedClient()
        return try await client.search(criteria, in: Server.inbox).uids.min()
    }

    private var searches: [String] {
        server.log.filter { $0.verb == "UID SEARCH" }.map(\.command)
    }

    /// The jump's page: the lowest match and the whole listing, nothing
    /// fetched.
    private func jump(_ client: IMAPClient, _ criteria: String) async throws -> [[UInt32]] {
        let opened = try await client.page(in: Server.inbox,
                                           searching: [.lowest(criteria), "ALL"]) { _ in [] }
        return opened.found.map(\.uids)
    }

    /// Gmail's way: one SEARCH asks for the lowest match alone and is
    /// answered with ESEARCH's MIN, the same letter a plain SEARCH's lowest
    /// is; the listing is still asked for whole. The answer is in the
    /// connection log as it came.
    func testTheDatedSearchAsksForItsLowestMatchAlone() async throws {
        let plain = try await lowestByPlainSearch(recent)
        let expected = try XCTUnwrap(plain)
        server.clearLog()
        let client = try await connectedClient()
        let found = try await jump(client, recent)

        XCTAssertEqual(found[0], [expected])
        XCTAssertEqual(found[1].count, 120)
        XCTAssertEqual(searches, ["UID SEARCH RETURN (MIN) \(recent)", "UID SEARCH ALL"])
        let received = Diagnostics.entries.filter { $0.direction == .received }.map(\.text)
        XCTAssertTrue(received.contains { $0.hasPrefix("* ESEARCH (TAG \"a")
                                          && $0.hasSuffix("\") UID MIN \(expected)") },
                      "\(received)")
    }

    // MARK: - The first of several to match (B-115)

    /// Every Inbox letter sent on the 101st's day alone, which is one.
    private let theDay = "SENTSINCE \"02-Sep-2026\" SENTBEFORE \"03-Sep-2026\""

    /// The jump's page asked with a ladder: the lowest match of its first
    /// SEARCH to match anything, and the whole listing.
    private func jump(_ client: IMAPClient, ladder: [String]) async throws -> [[UInt32]] {
        let opened = try await client.page(in: Server.inbox,
                                           searching: [.lowestOfFirst(ladder), "ALL"]) { _ in [] }
        return opened.found.map(\.uids)
    }

    /// Asked in turn: one that matches nothing, then one that does, whose
    /// lowest is the answer, and the one after it never asked; all in the
    /// hold of the one SELECT, on one connection.
    func testALadderStopsAtItsFirstSearchToMatch() async throws {
        let plain = try await lowestByPlainSearch(theDay)
        let expected = try XCTUnwrap(plain)
        server.clearLog()
        let client = try await connectedClient()
        let found = try await jump(client, ladder: [none, theDay, recent])

        XCTAssertEqual(found[0], [expected])
        XCTAssertEqual(found[1].count, 120)
        XCTAssertEqual(searches, ["UID SEARCH RETURN (MIN) \(none)",
                                  "UID SEARCH RETURN (MIN) \(theDay)", "UID SEARCH ALL"])
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN", "SELECT", "UID SEARCH", "UID SEARCH",
                                                "UID SEARCH"])
        XCTAssertEqual(Set(server.log.map(\.connection)).count, 1)
    }

    /// None matching is none, every one asked once; and none at all asked
    /// is none, the listing still whole.
    func testALadderNoneOfWhichMatchesIsNone() async throws {
        let client = try await connectedClient()
        server.clearLog()
        let found = try await jump(client, ladder: [none, none])
        XCTAssertEqual(found[0], [])
        XCTAssertEqual(found[1].count, 120)
        XCTAssertEqual(searches, ["UID SEARCH RETURN (MIN) \(none)",
                                  "UID SEARCH RETURN (MIN) \(none)", "UID SEARCH ALL"])

        let empty = try await jump(client, ladder: [])
        XCTAssertEqual(empty[0], [])
        XCTAssertEqual(empty[1].count, 120)
    }

    /// Each SEARCH of a ladder is asked as one alone is: without ESEARCH
    /// plainly; with RETURN refused, again plainly in the same hold; and a
    /// SEARCH refused whole fails the page, nothing after it asked.
    func testEachSearchOfALadderIsAskedAsOneAloneIs() async throws {
        let plain = try await lowestByPlainSearch(theDay)
        let expected = try XCTUnwrap(plain)

        server.withheldCapabilities = ["ESEARCH"]
        server.clearLog()
        let without = try await jump(try await connectedClient(), ladder: [none, theDay, recent])
        XCTAssertEqual(without[0], [expected])
        XCTAssertEqual(searches, ["UID SEARCH \(none)", "UID SEARCH \(theDay)", "UID SEARCH ALL"])

        server.withheldCapabilities = []
        server.refusesSearchReturn = true
        server.clearLog()
        let refused = try await jump(try await connectedClient(), ladder: [none, theDay, recent])
        XCTAssertEqual(refused[0], [expected])
        XCTAssertEqual(searches, ["UID SEARCH RETURN (MIN) \(none)", "UID SEARCH \(none)",
                                  "UID SEARCH RETURN (MIN) \(theDay)", "UID SEARCH \(theDay)",
                                  "UID SEARCH ALL"])
        XCTAssertEqual(Set(server.log.map(\.connection)).count, 1)

        server.refusesSearchReturn = false
        server.refusedSearchKeys = ["SENTBEFORE"]
        server.clearLog()
        do {
            _ = try await jump(try await connectedClient(), ladder: [none, theDay, recent])
            XCTFail("a SEARCH refused whole fails the page")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        XCTAssertEqual(searches, ["UID SEARCH RETURN (MIN) \(none)",
                                  "UID SEARCH RETURN (MIN) \(theDay)", "UID SEARCH \(theDay)"])
    }

    // MARK: - His day's letters, by their dates (B-115)

    /// The 2nd and 3rd of September as Gmail counts them, from midnight
    /// UTC: two letters, a day apart, each at 14:13 UTC.
    private let twoDays = "SENTSINCE \"02-Sep-2026\" SENTBEFORE \"04-Sep-2026\""

    private func instant(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    /// The 3rd of September, midnight to midnight UTC.
    private var theThird: Range<Date> {
        instant("2026-09-03T00:00:00Z")..<instant("2026-09-04T00:00:00Z")
    }

    /// The jump's page asked with its day: the lowest UID of the day's
    /// letters dated `within`, or of the first of `wider` to match, and
    /// the whole listing.
    private func jump(_ client: IMAPClient, day: String, within: Range<Date>,
                      wider: [String]) async throws -> [[UInt32]] {
        let opened = try await client.page(in: Server.inbox,
                                           searching: [.lowestDated(day, within: within, wider: wider),
                                                       "ALL"]) { _ in [] }
        return opened.found.map(\.uids)
    }

    private var dateFetches: [String] {
        server.log.filter { $0.command.hasSuffix("(UID INTERNALDATE ENVELOPE)") }.map(\.command)
    }

    /// The two letters' UIDs, lower first.
    private func theTwoLetters() async throws -> [UInt32] {
        let client = try await connectedClient()
        let both = try await client.search(twoDays, in: Server.inbox).uids.sorted()
        XCTAssertEqual(both.count, 2)
        return both
    }

    /// The day's letters asked for whole, their dates fetched in the same
    /// hold, and of them the lowest UID dated within the range: the 3rd's,
    /// not the 2nd's below it, which is the lowest of all; nothing wider
    /// asked; one SELECT, one connection.
    func testTheDaysAnswerIsTheLowestUIDDatedWithinIt() async throws {
        let both = try await theTwoLetters()
        server.clearLog()
        let found = try await jump(try await connectedClient(), day: twoDays, within: theThird,
                                   wider: [recent])

        XCTAssertEqual(found[0], [both[1]])
        XCTAssertEqual(found[1].count, 120)
        XCTAssertEqual(searches, ["UID SEARCH \(twoDays)", "UID SEARCH ALL"])
        let set = both[1] == both[0] + 1 ? "\(both[0]):\(both[1])" : "\(both[0]),\(both[1])"
        XCTAssertEqual(dateFetches, ["UID FETCH \(set) (UID INTERNALDATE ENVELOPE)"])
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN", "SELECT", "UID SEARCH", "UID FETCH",
                                                "UID SEARCH"])
        XCTAssertEqual(Set(server.log.map(\.connection)).count, 1)
    }

    /// None of the day's letters dated within the range, as when they are
    /// all his evening before: the wider SEARCHes are asked as a ladder's,
    /// in the same hold, and the first to match decides. The same with a
    /// day that matches nothing, whose dates are not fetched.
    func testWithNoneDatedWithinTheDayTheWiderAreAsked() async throws {
        let both = try await theTwoLetters()
        server.clearLog()
        let client = try await connectedClient()
        let evening = instant("2026-09-02T00:00:00Z")..<instant("2026-09-02T12:00:00Z")
        let found = try await jump(client, day: twoDays, within: evening, wider: [none, recent])
        XCTAssertEqual(found[0], [both[0]])
        XCTAssertEqual(searches, ["UID SEARCH \(twoDays)", "UID SEARCH RETURN (MIN) \(none)",
                                  "UID SEARCH RETURN (MIN) \(recent)", "UID SEARCH ALL"])
        XCTAssertEqual(dateFetches.count, 1)
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN", "SELECT", "UID SEARCH", "UID FETCH",
                                                "UID SEARCH", "UID SEARCH", "UID SEARCH"])

        server.clearLog()
        let empty = try await jump(client, day: none, within: theThird, wider: [recent])
        XCTAssertEqual(empty[0], [both[0]])
        XCTAssertEqual(searches, ["UID SEARCH \(none)", "UID SEARCH RETURN (MIN) \(recent)",
                                  "UID SEARCH ALL"])
        XCTAssertEqual(dateFetches, [])

        server.clearLog()
        let nothing = try await jump(client, day: none, within: theThird, wider: [none])
        XCTAssertEqual(nothing[0], [])
        XCTAssertEqual(nothing[1].count, 120)
    }

    /// A letter given with no ENVELOPE is never made a row, so it is not
    /// landed on either: the 3rd's, so given, leaves the day with none.
    func testALetterGivenWithNoEnvelopeIsNotTheDaysAnswer() async throws {
        let both = try await theTwoLetters()
        server.envelopeless = [both[1]]
        server.clearLog()
        let found = try await jump(try await connectedClient(), day: twoDays, within: theThird,
                                   wider: [recent])
        XCTAssertEqual(found[0], [both[0]])
        XCTAssertEqual(searches, ["UID SEARCH \(twoDays)", "UID SEARCH RETURN (MIN) \(recent)",
                                  "UID SEARCH ALL"])
    }

    /// Without ESEARCH the day is asked as ever, and the wider plainly,
    /// with the same answer; and the day's SEARCH refused fails the page,
    /// nothing fetched and nothing after it asked.
    func testTheDayIsAskedTheSameWithoutESEARCHAndRefusedFailsThePage() async throws {
        let both = try await theTwoLetters()
        server.withheldCapabilities = ["ESEARCH"]
        server.clearLog()
        let evening = instant("2026-09-02T00:00:00Z")..<instant("2026-09-02T12:00:00Z")
        let plain = try await jump(try await connectedClient(), day: twoDays, within: evening,
                                   wider: [none, recent])
        XCTAssertEqual(plain[0], [both[0]])
        XCTAssertEqual(searches, ["UID SEARCH \(twoDays)", "UID SEARCH \(none)",
                                  "UID SEARCH \(recent)", "UID SEARCH ALL"])
        let within = try await jump(try await connectedClient(), day: twoDays, within: theThird,
                                    wider: [recent])
        XCTAssertEqual(within[0], [both[1]])

        server.withheldCapabilities = []
        server.refusedSearchKeys = ["SENTBEFORE"]
        server.clearLog()
        do {
            _ = try await jump(try await connectedClient(), day: twoDays, within: theThird,
                               wider: [recent])
            XCTFail("the day's SEARCH refused fails the page")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        XCTAssertEqual(searches, ["UID SEARCH \(twoDays)"])
        XCTAssertEqual(dateFetches, [])
    }

    /// An ESEARCH answer with no MIN is the server saying nothing matched:
    /// none, with nothing asked again.
    func testAnAnswerWithNoMINIsNothingMatchedAndIsNotAskedAgain() async throws {
        let client = try await connectedClient()
        let found = try await jump(client, none)
        XCTAssertEqual(found[0], [])
        XCTAssertEqual(found[1].count, 120)
        XCTAssertEqual(searches, ["UID SEARCH RETURN (MIN) \(none)", "UID SEARCH ALL"])
    }

    /// A server that does not advertise ESEARCH is asked as it always was,
    /// with a plain SEARCH, and the lowest of what it says is the answer.
    func testWithoutESEARCHTheDatedSearchIsAPlainSearch() async throws {
        let plain = try await lowestByPlainSearch(recent)
        let expected = try XCTUnwrap(plain)
        server.withheldCapabilities = ["ESEARCH"]
        server.clearLog()
        let client = try await connectedClient()
        let found = try await jump(client, recent)
        XCTAssertEqual(found[0], [expected])
        XCTAssertEqual(searches, ["UID SEARCH \(recent)", "UID SEARCH ALL"])

        let nothing = try await jump(client, none)
        XCTAssertEqual(nothing[0], [])
    }

    /// One that advertises ESEARCH and refuses RETURN now is asked again
    /// with a plain SEARCH, in the same hold, on the same connection: the
    /// refusal is never taken for nothing found, nor for a lost line.
    func testARefusedRETURNIsAskedAgainPlainlyInTheSameHold() async throws {
        let plain = try await lowestByPlainSearch(recent)
        let expected = try XCTUnwrap(plain)
        server.refusesSearchReturn = true
        server.clearLog()
        let client = try await connectedClient()
        let found = try await jump(client, recent)

        XCTAssertEqual(found[0], [expected])
        XCTAssertEqual(server.log.map { "\($0.verb) \($0.status ?? "")" },
                       ["LOGIN OK", "SELECT OK", "UID SEARCH NO", "UID SEARCH OK", "UID SEARCH OK"])
        XCTAssertEqual(searches, ["UID SEARCH RETURN (MIN) \(recent)", "UID SEARCH \(recent)",
                                  "UID SEARCH ALL"])
        XCTAssertEqual(Set(server.log.map(\.connection)).count, 1)
        let connected = await client.isConnected
        XCTAssertTrue(connected)
    }

    /// One that takes no notice of RETURN and answers with a plain `*
    /// SEARCH` line has answered: the lowest of that is the jump's, and the
    /// SEARCH is not sent again. Nothing matched is the same: `* SEARCH`
    /// alone, taken as none, with nothing asked again.
    func testAPlainSEARCHAnswerToRETURNIsTakenAndNotAskedAgain() async throws {
        let plain = try await lowestByPlainSearch(recent)
        let expected = try XCTUnwrap(plain)
        server.ignoresSearchReturn = true
        server.clearLog()
        let client = try await connectedClient()

        let found = try await jump(client, recent)
        XCTAssertEqual(found[0], [expected])
        XCTAssertEqual(found[1].count, 120)
        XCTAssertEqual(searches, ["UID SEARCH RETURN (MIN) \(recent)", "UID SEARCH ALL"])

        server.clearLog()
        let nothing = try await jump(client, none)
        XCTAssertEqual(nothing[0], [])
        XCTAssertEqual(searches, ["UID SEARCH RETURN (MIN) \(none)", "UID SEARCH ALL"])
        XCTAssertEqual(Set(server.log.map(\.connection)).count, 1)
    }

    /// An ESEARCH answer that says something, but not the lowest, is not
    /// nothing found: the count alone, the count and the highest, or a MIN
    /// with no number. Each is asked again with a plain SEARCH in the same
    /// hold, and the jump lands on the letter a plain SEARCH finds.
    func testAnESEARCHAnswerThatDoesNotSayTheLowestIsAskedAgainPlainly() async throws {
        let plain = try await lowestByPlainSearch(recent)
        let expected = try XCTUnwrap(plain)
        let answers: [(String, @Sendable ([UInt32]) -> String)] = [
            ("COUNT", { "COUNT \($0.count)" }),
            ("COUNT MAX", { "COUNT \($0.count) MAX \($0.last ?? 0)" }),
            ("MAX", { "MAX \($0.last ?? 0)" }),
            ("MIN alone", { _ in "MIN" }),
            ("MIN 0", { _ in "MIN 0" }),
        ]
        let client = try await connectedClient()
        for (label, items) in answers {
            server.esearchItems = items
            server.clearLog()
            let found = try await jump(client, recent)
            XCTAssertEqual(found[0], [expected], label)
            XCTAssertEqual(searches, ["UID SEARCH RETURN (MIN) \(recent)", "UID SEARCH \(recent)",
                                      "UID SEARCH ALL"], label)
        }
        XCTAssertEqual(Set(server.log.map(\.connection)).count, 1)
    }

    /// And one that does say it, though not as MIN: ALL's set gives its
    /// lowest, and a count of none is nothing matched. Neither is asked
    /// again.
    func testAnESEARCHAnswerOfALLOrOfACountOfNoneIsTaken() async throws {
        let plain = try await lowestByPlainSearch(recent)
        let expected = try XCTUnwrap(plain)
        let client = try await connectedClient()

        // Every match but the lowest, then the lowest, as a set may be
        // written in any order.
        server.esearchItems = { uids in
            "ALL " + (uids.dropFirst().map(String.init) + uids.prefix(1).map(String.init))
                .joined(separator: ",")
        }
        server.clearLog()
        let found = try await jump(client, recent)
        XCTAssertEqual(found[0], [expected])
        XCTAssertEqual(searches, ["UID SEARCH RETURN (MIN) \(recent)", "UID SEARCH ALL"])

        server.esearchItems = { "COUNT \($0.count)" }
        server.clearLog()
        let nothing = try await jump(client, none)
        XCTAssertEqual(nothing[0], [])
        XCTAssertEqual(searches, ["UID SEARCH RETURN (MIN) \(none)", "UID SEARCH ALL"])
    }
}
