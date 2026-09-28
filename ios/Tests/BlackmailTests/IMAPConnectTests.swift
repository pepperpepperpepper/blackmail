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
            try await client.select(Server.drafts)
            try await client.expunge(uid: draft)
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
}
