import XCTest
@testable import Blackmail

/// Cc in the reading pane's header, under To, in Mail's way: names, and the
/// address where there is no name. The pane never showed Cc, and wrote a
/// recipient with no name as its brackets, or as nothing at all.
///
/// A name can hold a comma, `"Example, Jane" <jane@example.com>`, and the
/// letter's To and Cc were split on every comma, so such a name came out as
/// two entries, the first of them `"Example`; that is what the header would
/// have shown, and what Reply All tried to send to.
final class ReadingPaneCcTests: XCTestCase {

    // MARK: - Splitting an address list

    func testAnAddressListIsSplitBetweenAddressesOnly() {
        XCTAssertEqual(MailFormat.addressList(
            "\"Example, Jane\" <jane@example.com>, Sam Example <sam@example.com>,sam@example.org"),
                       ["\"Example, Jane\" <jane@example.com>", "Sam Example <sam@example.com>",
                        "sam@example.org"])
        // A comma inside brackets, a comment or a quoted pair.
        XCTAssertEqual(MailFormat.addressList("<\"a,b\"@example.com>, sam@example.com (Example, Sam)"),
                       ["<\"a,b\"@example.com>", "sam@example.com (Example, Sam)"])
        XCTAssertEqual(MailFormat.addressList("\"Sam \\\"The Gardener\\\", Example\" <sam@example.com>, x@example.com"),
                       ["\"Sam \\\"The Gardener\\\", Example\" <sam@example.com>", "x@example.com"])
        // Folded, and with empty entries between commas.
        XCTAssertEqual(MailFormat.addressList(" jane@example.com ,\r\n\t sam@example.com, , "),
                       ["jane@example.com", "sam@example.com"])
        XCTAssertEqual(MailFormat.addressList(""), [])
    }

    /// A quote, bracket or comment never closed is split on every comma,
    /// as every list used to be, rather than taking every address after it
    /// into one entry.
    func testABrokenListIsSplitOnEveryComma() {
        for broken in ["\"Example, Jane <jane@example.com>, sam@example.com",
                       "<jane@example.com, sam@example.com",
                       "(Jane, jane@example.com, sam@example.com",
                       "\"Jane\\"] {
            XCTAssertEqual(MailFormat.addressList(broken),
                           broken.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }, broken)
        }
    }

    // MARK: - Naming a recipient

    func testARecipientIsNamedAsMailNamesThem() {
        for (entry, shown) in [
            ("Jane Example <jane@example.com>", "Jane Example"),
            ("\"Example, Jane\" <jane@example.com>", "Example, Jane"),
            ("'Jane Example' <jane@example.com>", "Jane Example"),
            ("jane@example.com", "jane@example.com"),
            ("<jane@example.com>", "jane@example.com"),
            ("\"\" <jane@example.com>", "jane@example.com"),
            ("  Jane Example   <jane@example.com> ", "Jane Example"),
            ("J\u{00E9}r\u{00F4}me Example <jerome@example.com>", "J\u{00E9}r\u{00F4}me Example"),
        ] {
            XCTAssertEqual(MailFormat.recipientName(entry), shown, entry)
        }
    }

    /// The header's lines: "To: …" and "Cc: …", names joined as Mail joins
    /// them. No Cc, no line.
    func testTheHeadersLinesNameEveryRecipient() {
        XCTAssertEqual(MailFormat.recipientsLine("Cc", ["\"Example, Jane\" <jane@example.com>",
                                                        "<sam@example.com>", "Sam Example <sam@example.org>"]),
                       "Cc: Example, Jane, sam@example.com, Sam Example")
        XCTAssertEqual(MailFormat.recipientsLine("To", ["jane@example.com"]), "To: jane@example.com")
        XCTAssertNil(MailFormat.recipientsLine("Cc", []))
    }

    // MARK: - The header view

    /// `MessageHeaderView` is UIKit and never builds on this host, so its
    /// wiring is read from its source, as `PaneNavigationTests` reads the
    /// pane's.
    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/UI/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    /// The Cc line sits under To in To's font and colour, at the text's
    /// inset, and the rule under the names is pinned below it. With no Cc
    /// it has no text, so no height, and no gap above it, so a letter
    /// without one lays out as it did. Both lines say what
    /// `MailFormat.recipientsLine` says, and To "me" when there is no To.
    func testTheHeaderShowsCcUnderToInItsStyle() throws {
        let code = try source("MessageHeaderView.swift")
        for wiring in [
            "private let ccLabel = UILabel()",
            "ccLabel.font = Theme.fontDetailMeta ccLabel.textColor = Theme.secondaryText",
            "for v in [senderLabel, toLabel, ccLabel, topRule,",
            "ccGap = ccLabel.topAnchor.constraint(equalTo: toLabel.bottomAnchor, constant: 0)",
            "ccGap, ccLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: left), "
                + "ccLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -left),",
            "topRule.topAnchor.constraint(equalTo: ccLabel.bottomAnchor, constant: Theme.detailToRuleGap),",
            "toLabel.text = MailFormat.recipientsLine(\"To\", m.to) ?? \"To: me\"",
            "let cc = MailFormat.recipientsLine(\"Cc\", m.cc) ccLabel.text = cc ccLabel.isHidden = cc == nil "
                + "ccGap.constant = cc == nil ? 0 : Theme.detailToCcGap",
        ] {
            XCTAssertTrue(code.contains(wiring), wiring)
        }
        XCTAssertFalse(code.contains("constraint(equalTo: toLabel.bottomAnchor, constant: Theme.detailToRuleGap)"))
        XCTAssertFalse(code.contains("m.to.map(MailFormat.displayName)"))
    }

    // MARK: - A letter's To and Cc, as the repository reads them

    private typealias Server = ScriptedIMAPServer

    /// A letter with a quoted name holding a comma in its Cc, and a name
    /// whose comma is inside an encoded word, which is split on only once
    /// decoded: each is one recipient, named as Mail names them, and Reply
    /// All goes to each address, and to nothing else.
    func testALettersToAndCcAreReadOneAddressEach() async throws {
        let server = ScriptedIMAPServer()
        defer { XCTAssertEqual(server.violations, []) }
        let suite = "ReadingPaneCcTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = ManualClock()
        let repository = IMAPMailRepository(account: server.account, password: server.password,
                                            transport: server.transportFactory,
                                            recipients: RecipientBook(defaults: defaults),
                                            now: { clock.now() }, shelf: keptShelf(for: server.account))
        let uid = try XCTUnwrap(server.deliver(Server.Letter(
            from: Server.Address(name: "Jane Example", address: "jane@example.com"),
            to: [Server.sam, Server.Address(name: "=?UTF-8?Q?Example=2C_J=C3=A9r=C3=B4me?=",
                                            address: "jerome@example.com")],
            cc: [Server.Address(name: "\"Example, Pat\"", address: "pat@example.com"),
                 Server.Address(name: nil, address: "lee@example.com")],
            subject: "The garden", date: Server.newestDate, text: "Roses.\r\n",
            messageID: "<garden-cc@example.com>"), to: [Server.inbox])[Server.inbox])

        let m = try await repository.loadMessage(id: "\(server.uidValidity(of: Server.inbox))/\(uid)",
                                                 mailboxID: Server.inbox)
        XCTAssertEqual(m.to, ["Sam Example <sam@example.com>",
                              "Example, J\u{00E9}r\u{00F4}me <jerome@example.com>"])
        XCTAssertEqual(m.cc, ["\"Example, Pat\" <pat@example.com>", "lee@example.com"])
        XCTAssertEqual(MailFormat.recipientsLine("To", m.to), "To: Sam Example, Example, J\u{00E9}r\u{00F4}me")
        XCTAssertEqual(MailFormat.recipientsLine("Cc", m.cc), "Cc: Example, Pat, lee@example.com")
        // The sender in To, and the letter's To then its Cc in Cc, as Mail
        // addresses a Reply All (B-076), each with its name, and the comma
        // that came out of an encoded word quoted, so the composer's field
        // keeps it one recipient (B-061).
        let all = Draft.replying(to: m, all: true, myAddress: "sam@example.com")
        XCTAssertEqual(all.to, ["Jane Example <jane@example.com>"])
        XCTAssertEqual(all.cc, ["\"Example, J\u{00E9}r\u{00F4}me\" <jerome@example.com>",
                                "\"Example, Pat\" <pat@example.com>", "lee@example.com"])
        XCTAssertEqual(MailFormat.addresses(in: all.to.joined(separator: ", ")), all.to)
        XCTAssertEqual(MailFormat.addresses(in: all.cc.joined(separator: ", ")), all.cc)
    }

    // MARK: - Cc from the tap

    /// The list's row carries the Cc from the ENVELOPE it is fetched with
    /// already, so the header drawn at the tap has the Cc line the landed
    /// letter has, word for word, before anything of the letter is fetched,
    /// and a conversation's stack does not move a line when it lands
    /// (B-042). The list's FETCH is what it was: nothing more is asked. A
    /// letter with no Cc has no line at the tap either.
    func testTheHeaderHasItsCcLineFromTheTap() async throws {
        let server = ScriptedIMAPServer()
        defer { XCTAssertEqual(server.violations, []) }
        let suite = "ReadingPaneCcTests.tap"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = IMAPMailRepository(account: server.account, password: server.password,
                                            transport: server.transportFactory,
                                            recipients: RecipientBook(defaults: defaults),
                                            shelf: keptShelf(for: server.account))
        let uid = try XCTUnwrap(server.deliver(Server.Letter(
            from: Server.Address(name: "Jane Example", address: "jane@example.com"),
            to: [Server.sam],
            cc: [Server.Address(name: "\"Example, Pat\"", address: "pat@example.com"),
                 Server.Address(name: "=?UTF-8?Q?Example=2C_J=C3=A9r=C3=B4me?=",
                                address: "jerome@example.com"),
                 Server.Address(name: nil, address: "lee@example.com")],
            subject: "The garden", date: Server.newestDate, text: "Roses.\r\n",
            messageID: "<garden-cc-tap@example.com>"), to: [Server.inbox])[Server.inbox])

        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let fetches = server.log.filter { $0.verb == "UID FETCH" }.map(\.command)
        XCTAssertFalse(fetches.isEmpty)
        for fetch in fetches {
            XCTAssertTrue(fetch.hasSuffix(" (UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE "
                                          + "BODYSTRUCTURE X-GM-LABELS X-GM-THRID X-GM-MSGID)"),
                          fetch)
        }
        let row = try XCTUnwrap(rows.first { $0.id.hasSuffix("/\(uid)") })
        let heading = Message.heading(for: row)
        XCTAssertEqual(MailFormat.recipientsLine("Cc", heading.cc),
                       "Cc: Example, Pat, Example, J\u{00E9}r\u{00F4}me, lee@example.com")

        let landed = try await repository.loadMessage(id: row.id, mailboxID: Server.inbox)
        XCTAssertEqual(MailFormat.recipientsLine("Cc", landed.cc),
                       MailFormat.recipientsLine("Cc", heading.cc),
                       "the line the letter lands with")

        let plain = try XCTUnwrap(rows.first { !$0.id.hasSuffix("/\(uid)") })
        XCTAssertEqual(plain.cc, [])
        XCTAssertNil(MailFormat.recipientsLine("Cc", Message.heading(for: plain).cc))
    }
}
