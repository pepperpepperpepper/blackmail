import XCTest
@testable import Blackmail

/// What `IMAPClient.connect` puts on the wire before the first command that
/// does anything, against `ScriptedIMAPServer`.
///
/// Each of these commands is a round trip paid before he sees any mail, on
/// every connect, and there is a connect after every dropped socket as well
/// as at launch. So the handshake is asserted command by command rather
/// than only by whether it worked.
final class IMAPConnectTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    func testCapabilitiesAreAskedForOnlyWhenNothingElseAnnouncedThem() async throws {
        let cases: [(label: String, greeting: Server.Greeting,
                     placement: Server.LoginCapabilities, handshake: [String])] = [
            ("in LOGIN's tagged OK, as Gmail does", .ready, .inTaggedOK, ["LOGIN"]),
            ("untagged, ahead of LOGIN's OK", .ready, .untagged, ["LOGIN"]),
            ("not announced", .ready, .omitted, ["LOGIN", "CAPABILITY"]),
            ("in a PREAUTH greeting", .preauthenticated(announcingCapabilities: true), .omitted, []),
            ("PREAUTH without them", .preauthenticated(announcingCapabilities: false), .omitted,
             ["CAPABILITY"]),
        ]
        for c in cases {
            let server = Server()
            server.greeting = c.greeting
            server.loginCapabilities = c.placement
            let client = IMAPClient(account: server.account, transport: server.transportFactory)

            try await client.connect(password: server.password)

            // Nothing before LOGIN: the pre-login list was never used for
            // anything. And the PREAUTH cases send no LOGIN at all, which
            // the server would refuse.
            XCTAssertEqual(server.log.map(\.verb), c.handshake, c.label)
            XCTAssertEqual(server.log.filter { $0.status != "OK" }, [], c.label)

            // The list that was kept is the post-login one. UIDPLUS is only
            // in that list, and without it this delete would be a plain
            // EXPUNGE of the whole folder rather than of this one draft.
            let draft = try XCTUnwrap(server.uids(in: Server.drafts).first, c.label)
            try await client.expunge(uid: draft, in: Server.drafts,
                                     validity: server.uidValidity(of: Server.drafts))
            XCTAssertEqual(server.log.dropFirst(c.handshake.count).map(\.command),
                           ["SELECT \"[Gmail]/Drafts\"",
                            "UID STORE \(draft) +FLAGS.SILENT (\\Deleted)",
                            "UID EXPUNGE \(draft)"], c.label)
            XCTAssertEqual(server.violations, [], c.label)
        }
    }

    func testAWrongPasswordIsStillToldApartFromAServerThatCannotBeReached() async throws {
        let server = Server()
        let client = IMAPClient(account: server.account, transport: server.transportFactory)
        do {
            try await client.connect(password: "not-the-password")
            XCTFail("a refused LOGIN must not connect")
        } catch {
            XCTAssertEqual(error as? MailError, .passwordNeedsUpdating)
        }
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN"])
        XCTAssertEqual(server.log.first?.status, "NO")
        let connected = await client.isConnected
        XCTAssertFalse(connected)
        XCTAssertEqual(server.violations, [])
    }

    /// A LOGIN refused for a reason that is not the password is its own
    /// failure, with Google's ALERT text kept to be shown, and not "Can't
    /// connect to mail server.", which no change of Wi-Fi or password
    /// could mend. Gmail's words, as it refuses app passwords made wrongly,
    /// wants a sign-in on the web, or counts too many connections.
    func testALoginRefusedForAnotherReasonSaysWhyWithGooglesWords() async throws {
        let server = Server()
        server.passwordRevoked = true
        server.loginRefusal = "[ALERT] Application-specific password required: "
            + "https://support.google.com/accounts/answer/185833 (Failure)"
        let client = IMAPClient(account: server.account, transport: server.transportFactory)
        do {
            try await client.connect(password: server.password)
            XCTFail("a refused LOGIN must not connect")
        } catch {
            XCTAssertEqual(error as? MailError, .signInRefused(alert:
                "Application-specific password required: "
                + "https://support.google.com/accounts/answer/185833 (Failure)"))
        }
        let kept = await client.loginRefusal
        XCTAssertEqual(kept?.failure, .signInRefused(alert:
            "Application-specific password required: "
            + "https://support.google.com/accounts/answer/185833 (Failure)"))

        func refusal(_ status: IMAPStatus, _ detail: String,
                     _ untagged: [String] = []) -> MailError {
            IMAPClient.refusal(of: IMAPCommandResult(
                status: status, detail: detail,
                untagged: untagged.map { IMAPResponseLine(text: $0, literals: []) }))
        }
        XCTAssertEqual(refusal(.no, "[AUTHENTICATIONFAILED] Invalid credentials (Failure)"),
                       .passwordNeedsUpdating)
        // WEBALERT's argument is a sign-in link into the account: left out.
        XCTAssertEqual(refusal(.no, "[WEBALERT https://accounts.google.com/signin/continue?"
                                    + "sarp=1&scc=1&plt=AKgnsbt] Web login required."),
                       .signInRefused(alert: "Web login required."))
        XCTAssertEqual(refusal(.no, "Login failed", ["* NO [ALERT] Too many simultaneous "
                                                     + "connections. (Failure)"]),
                       .signInRefused(alert: "Too many simultaneous connections. (Failure)"))
        XCTAssertEqual(refusal(.no, "[UNAVAILABLE] Temporary System Problem. Try again later."),
                       .signInRefused(alert: nil))
        XCTAssertEqual(refusal(.bad, "Could not parse command"), .signInRefused(alert: nil))
        // A BAD is never the password's, whatever it carries.
        XCTAssertEqual(refusal(.bad, "[AUTHENTICATIONFAILED] Invalid credentials"),
                       .signInRefused(alert: nil))
    }

    /// A client retired for a new password closes its connection and makes
    /// no other, so nothing still holding it signs in with the old password.
    func testARetiredClientSignsInNoMore() async throws {
        let server = Server()
        let client = IMAPClient(account: server.account, transport: server.transportFactory)
        try await client.connect(password: server.password)
        await client.retire().value
        do {
            try await client.connect(password: server.password)
            XCTFail("a retired client must not connect")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN", "LOGOUT"])
    }

    /// Google's sentence goes into an alert: one line of printable
    /// characters, a bounded number of them, and nothing for an empty one.
    func testAnAlertIsOneBoundedLineOfText() {
        XCTAssertEqual(IMAPParser.alert(in: "[ALERT]\u{7}Your\taccount   is\u{0}disabled"),
                       "Your account is disabled")
        XCTAssertNil(IMAPParser.alert(in: "[ALERT]   "))
        XCTAssertNil(IMAPParser.alert(in: "[AUTHENTICATIONFAILED] Invalid credentials"))
        XCTAssertNil(IMAPParser.alert(in: "Login failed", untagged: [
            IMAPResponseLine(text: "* CAPABILITY IMAP4rev1 [ALERT] not a status line",
                             literals: [])]))
        let long = IMAPParser.alert(in: "[ALERT] " + String(repeating: "word ", count: 500))
        XCTAssertEqual(long?.count, IMAPParser.alertLength + 1)
        XCTAssertEqual(long?.last, "…")
    }
}
