import XCTest
@testable import Blackmail

/// The reading pane's To at the tap (B-127). The header drawn at the tap
/// left the To out, and read "To: me" until the letter's body landed, for a
/// letter in Sent Mail to someone else too, and for good when the body
/// could not be downloaded. The row has carried its To from the ENVELOPE
/// since B-060, for Sent Mail's rows, as it carries the Cc the header has
/// taken from it since B-055; the header takes it now, so the whole header
/// is there at once, as Mail's is. The letter's own To takes its place when
/// it lands.
final class ToAtTheTapTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private func repository(_ server: ScriptedIMAPServer, suite: String) throws -> IMAPMailRepository {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return IMAPMailRepository(account: server.account, password: server.password,
                                  transport: server.transportFactory,
                                  recipients: RecipientBook(defaults: defaults),
                                  shelf: keptShelf(for: server.account))
    }

    /// A letter to several, one a quoted name holding a comma, one a name
    /// whose comma is inside an encoded word, one a bare address: the
    /// header drawn at the tap has the To line the landed letter has, word
    /// for word, before anything of the letter is fetched, and the list's
    /// FETCH is what it was. Not "To: me".
    func testTheHeaderHasItsToLineFromTheTap() async throws {
        let server = ScriptedIMAPServer()
        defer { XCTAssertEqual(server.violations, []) }
        let repository = try repository(server, suite: "ToAtTheTapTests.inbox")
        let uid = try XCTUnwrap(server.deliver(Server.Letter(
            from: Server.Address(name: "Jane Example", address: "jane@example.com"),
            to: [Server.Address(name: "\"Example, Pat\"", address: "pat@example.com"),
                 Server.Address(name: "=?UTF-8?Q?Example=2C_J=C3=A9r=C3=B4me?=",
                                address: "jerome@example.com"),
                 Server.Address(name: nil, address: "lee@example.com")],
            subject: "The garden", date: Server.newestDate, text: "Roses.\r\n",
            messageID: "<garden-to-tap@example.com>"), to: [Server.inbox])[Server.inbox])

        let rows = try await repository.listMessages(in: Server.inbox, beforeUID: nil, limit: 10)
        let fetches = server.log.filter { $0.verb == "UID FETCH" }.map(\.command)
        XCTAssertFalse(fetches.isEmpty)
        for fetch in fetches {
            XCTAssertTrue(fetch.hasSuffix(" (UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE "
                                          + "BODYSTRUCTURE X-GM-LABELS X-GM-THRID X-GM-MSGID)"),
                          fetch)
        }
        XCTAssertFalse(server.log.contains { $0.command.contains("BODY.PEEK[") }, "nothing of the letter")

        let row = try XCTUnwrap(rows.first { $0.id.hasSuffix("/\(uid)") })
        let heading = Message.heading(for: row)
        XCTAssertEqual(MailFormat.recipientsLine("To", heading.to),
                       "To: Example, Pat, Example, J\u{00E9}r\u{00F4}me, lee@example.com")

        let landed = try await repository.loadMessage(id: row.id, mailboxID: Server.inbox)
        XCTAssertEqual(MailFormat.recipientsLine("To", landed.to),
                       MailFormat.recipientsLine("To", heading.to), "the line the letter lands with")
    }

    /// A letter of his in Sent Mail, to Jane and to Carlo: the header at the
    /// tap names them, as the letter does when it lands, where it said "To:
    /// me" of a letter he sent to someone else.
    func testASentMailLetterNamesWhomItWentToFromTheTap() async throws {
        let server = ScriptedIMAPServer()
        defer { XCTAssertEqual(server.violations, []) }
        let repository = try repository(server, suite: "ToAtTheTapTests.sent")
        let uid = try XCTUnwrap(server.deliver(Server.Letter(
            from: Server.owner,
            to: [Server.Address(name: "Jane Example", address: "jane@example.com"), Server.carlo],
            subject: "Sunday", date: Server.newestDate, text: "Lunch at one.\r\n",
            flags: ["\\Seen"], messageID: "<sunday-to-tap@example.com>"), to: [Server.sent])[Server.sent])

        let rows = try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 10)
        let row = try XCTUnwrap(rows.first { $0.id.hasSuffix("/\(uid)") })
        let heading = Message.heading(for: row)
        XCTAssertEqual(heading.to, ["Jane Example <jane@example.com>", "Carlo <carlo@example.org>"])
        XCTAssertEqual(MailFormat.recipientsLine("To", heading.to), "To: Jane Example, Carlo")

        let landed = try await repository.loadMessage(id: row.id, mailboxID: Server.sent)
        XCTAssertEqual(MailFormat.recipientsLine("To", landed.to),
                       MailFormat.recipientsLine("To", heading.to))
    }

    /// A row that does not know whom it went to, kept on the iPad by a
    /// build before rows carried it, has no To in its header, which then
    /// reads "To: me" until the letter lands, as every header did; and a
    /// letter to nobody, a draft begun and put aside, none either. A row
    /// kept with its To has it after a launch, from the copy kept on the
    /// iPad, so a letter opened with no connection has it too.
    func testARowThatDoesNotKnowItsToHasNoneAndAKeptRowHasIts() throws {
        var row = MessageSummary(id: "1/9000", mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                                 subject: "The garden", preview: "Roses.", date: Server.newestDate,
                                 isRead: true, isFlagged: false)
        XCTAssertNil(row.to)
        XCTAssertEqual(Message.heading(for: row).to, [])
        XCTAssertNil(MailFormat.recipientsLine("To", Message.heading(for: row).to))
        row.to = []
        XCTAssertEqual(Message.heading(for: row).to, [])

        row.to = ["\"Example, Pat\" <pat@example.com>", "lee@example.com"]
        let account = ScriptedIMAPServer().account
        let writing = keptShelf(for: account)
        writing.took(page: [row], of: "INBOX", validity: 1)
        writing.flush()
        let kept = try XCTUnwrap(keptShelf(for: account).page(of: "INBOX")?.rows.first)
        XCTAssertEqual(MailFormat.recipientsLine("To", Message.heading(for: kept).to),
                       "To: Example, Pat, lee@example.com")
    }

    /// The header the tap draws is the one a letter whose body could not be
    /// downloaded keeps: the pane says so under it and leaves the header
    /// alone, To and all. And the header view writes "To: me" only where
    /// the letter it is given has no To.
    func testALetterWhoseBodyFailsKeepsTheToItHadAtTheTap() throws {
        let pane = try source("UI/MessageDetailViewController.swift")
        let show = try section(of: pane, from: "func show(summary: MessageSummary) {",
                               to: "func show(thread: MessageThread")
        XCTAssertTrue(show.contains("header.configure(with: .heading(for: summary))"), show)
        let failed = try section(of: show, from: "case .failure(let error):", to: "})")
        XCTAssertTrue(failed.contains("self.message = nil self.renderLoadFailure()"), failed)
        XCTAssertFalse(failed.contains("header."), failed)

        let header = try source("UI/MessageHeaderView.swift")
        XCTAssertTrue(header.contains("toLabel.text = MailFormat.recipientsLine(\"To\", m.to) ?? \"To: me\""))
        let loads = try source("Mail/PaneLoads.swift")
        XCTAssertTrue(loads.contains("to: row.to ?? [], cc: row.cc,"), "the row's To, as its Cc")
    }

    // MARK: - Helpers

    /// A file under `Sources/Blackmail`, comment lines taken out and
    /// whitespace runs made one space.
    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .joined(separator: " ")
    }

    private func section(of code: String, from start: String, to end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start), start)
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex), end)
        return String(code[from.lowerBound..<to.lowerBound])
    }
}
