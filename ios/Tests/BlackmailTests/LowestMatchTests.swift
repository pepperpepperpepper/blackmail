import XCTest
@testable import Blackmail

/// A date jump's SEARCH asks for the lowest UID it matches and nothing else
/// (B-063): `UID SEARCH RETURN (MIN) …` where the server advertises ESEARCH
/// (RFC 4731), as Gmail does, and a plain SEARCH where it does not or will
/// not answer it. Through the real `IMAPClient.page` against the scripted
/// server, whose ESEARCH answers as RFC 4731 has them.
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
