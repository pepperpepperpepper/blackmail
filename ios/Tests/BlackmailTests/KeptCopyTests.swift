import XCTest
@testable import Blackmail

/// D-016: a copy of his mail is kept on the iPad. What is here so far is
/// what it rests on, over the shipping repository and client: nothing of
/// his mail is written into the connection log beside the wire, and every
/// row carries the Gmail message id a kept letter is to be keyed on, from
/// the FETCH the list already sends.
final class KeptCopyTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "KeptCopyTests"

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
                                  now: { clock.now() })
    }

    private var verbs: [String] { server.log.map(\.verb) }

    private func uid(_ id: String) -> UInt32 { UInt32(id.split(separator: "/").last ?? "")! }

    // MARK: - The connection log

    /// A listing leaves no subject and no correspondent of any letter in
    /// the folder in the connection log, from the top or a page down,
    /// except in the server's own answers, whose ENVELOPEs carry them and
    /// which are what the log is for. The log is made to be copied out to
    /// whoever is helping, and every send writes it to a file. The session
    /// is still pinned in numbers by SESSION-IDENT, which is what the
    /// device checks of B-045 read, and the listing costs the commands it
    /// did.
    func testAListingLeavesNoSubjectOrCorrespondentInTheLogBesideTheWire() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        server.clearLog()

        let top = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(verbs, ["SELECT", "UID SEARCH", "UID FETCH"])
        server.clearLog()
        let next = try await repository.listMessages(in: "inbox", beforeUID: top.last?.id, limit: 50)
        XCTAssertEqual(verbs, ["UID FETCH"])
        XCTAssertEqual(top.count + next.count, 100)

        // His correspondence: every subject, and every name and address on
        // a letter but his own, which is the account's and is on LOGIN.
        let letters = server.uids(in: Server.inbox).compactMap {
            server.letter(uid: $0, in: Server.inbox)
        }
        XCTAssertEqual(letters.count, 120)
        var correspondence: Set<String> = []
        for letter in letters {
            correspondence.insert(letter.subject)
            for person in [letter.from] + letter.to + letter.cc where person != Server.owner {
                correspondence.insert(person.address)
                if let name = person.name { correspondence.insert(name) }
            }
        }

        let entries = Diagnostics.entries
        let beside = entries.filter { $0.direction != .received }
        XCTAssertFalse(beside.isEmpty)
        let leaks = beside.filter { entry in correspondence.contains { entry.text.contains($0) } }
        XCTAssertEqual(leaks.count, 0, leaks.prefix(3).map(\.text).joined(separator: "\n"))

        // Not vacuous: the server's answers are in the same log, and they
        // do carry the letters, as the wire log is meant to.
        XCTAssertTrue(entries.contains {
            $0.direction == .received && $0.text.contains(top[0].subject)
        })

        // One a page, each naming the page's first row: its conversation,
        // and the letter itself by the id the server gave it.
        let ident = beside.filter { $0.text.hasPrefix("SESSION-IDENT") }.map(\.text)
        let validity = server.uidValidity(of: Server.inbox)
        XCTAssertEqual(ident, try [top, next].map { page in
            let first = try XCTUnwrap(page.first)
            let thread = try XCTUnwrap(first.threadID)
            let letter = try XCTUnwrap(server.gmailMessageID(uid: uid(first.id), in: Server.inbox))
            return "SESSION-IDENT folder=INBOX uidv=\(validity) exists=120 uids=120 "
                + "first-row=\(thread) msgid=\(letter)"
        })
    }

    // MARK: - What a kept letter is keyed on

    /// Every row carries Gmail's id for the letter, from the summary FETCH
    /// the list already sends, and the listing costs no more commands for
    /// it. The id is the letter's and not the folder's: the Inbox and All
    /// Mail give one letter two UIDs, and this one id.
    func testEveryRowCarriesGmailsMessageIDTheSameFromEveryFolder() async throws {
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        server.clearLog()

        let inbox = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(verbs, ["SELECT", "UID SEARCH", "UID FETCH"])
        let fetch = try XCTUnwrap(server.log.last?.command)
        XCTAssertTrue(fetch.hasSuffix(" (UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODYSTRUCTURE "
                                      + "X-GM-LABELS X-GM-THRID X-GM-MSGID)"), fetch)
        let ids = inbox.compactMap(\.gmailMessageID)
        XCTAssertEqual(ids.count, 50)
        XCTAssertEqual(Set(ids).count, 50)
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        // The number the server gave the letter, and not its thread's.
        // Every letter here is a conversation of its own, so a thread id
        // would pass for a letter's on uniqueness alone; on Gmail every
        // reply in a conversation shares one, and a copy keyed on it would
        // keep one letter of each.
        for row in inbox {
            XCTAssertEqual(row.gmailMessageID, server.gmailMessageID(uid: uid(row.id), in: Server.inbox),
                           row.subject)
        }

        server.clearLog()
        let allMail = try await repository.listMessages(in: Server.allMail, beforeUID: nil, limit: 50)
        XCTAssertEqual(verbs, ["SELECT", "UID SEARCH", "UID FETCH"])
        // The Inbox's subjects are one to a letter.
        let there = Dictionary(allMail.map { ($0.subject, $0) }, uniquingKeysWith: { first, _ in first })
        var both = 0
        for row in inbox {
            guard let same = there[row.subject] else { continue }
            both += 1
            XCTAssertNotEqual(same.id, row.id, row.subject)
            XCTAssertEqual(same.gmailMessageID, row.gmailMessageID, row.subject)
        }
        XCTAssertGreaterThan(both, 40)
    }

    /// A server without Gmail's extension is not asked for the id, as it
    /// is not asked for the labels or the thread: one item it does not
    /// know and it refuses the whole FETCH, and the page with it. Its rows
    /// have no id.
    func testAServerWithoutGmailsExtensionIsNotAskedForTheIDAndItsRowsHaveNone() async throws {
        server.withheldCapabilities = ["X-GM-EXT-1"]
        let repository = makeRepository()
        _ = try await repository.listMailboxes()
        server.clearLog()

        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(rows.count, 50)
        XCTAssertEqual(verbs, ["SELECT", "UID SEARCH", "UID FETCH"])
        let fetch = try XCTUnwrap(server.log.last?.command)
        XCTAssertTrue(fetch.hasSuffix(" (UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODYSTRUCTURE)"),
                      fetch)
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        XCTAssertEqual(rows.compactMap(\.gmailMessageID), [])
        XCTAssertEqual(rows.compactMap(\.threadID), [])
    }
}
