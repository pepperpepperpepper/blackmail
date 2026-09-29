import XCTest
@testable import Blackmail

/// Which of `SMTPClient`'s reads may wait on the long bound.
///
/// The conversation runs over a transport that answers the way Gmail's
/// submission server does and notes, for every line it hands back, how long
/// the client allowed the read to wait. Nothing is sent anywhere.
final class SMTPReplyWaitTests: XCTestCase {

    override func tearDown() {
        // `send` leaves its transcript in the temporary directory, as it does
        // on the device, where that is the evidence. Here it is litter, and
        // a failed send leaves it under the other name.
        for outcome in ["ok", "fail"] {
            let transcript = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
            try? FileManager.default.removeItem(atPath: transcript)
        }
        super.tearDown()
    }

    /// Only the reply to the letter itself: the 250 after DATA's terminating
    /// dot, which comes once the whole letter has crossed his uplink and
    /// Gmail has taken it. Every other reply answers a command line and keeps
    /// the short bound, so a server that has gone quiet is still found out
    /// in seconds.
    func testOnlyTheReplyToTheLetterItselfWaitsOnTheLongBound() async throws {
        let transport = ScriptedSubmission()
        let account = MailAccount(address: "owner@example.com", username: "owner@example.com")
        let client = SMTPClient(account: account, transport: { _, _ in transport })

        try await client.send(Data("Subject: Sunday\r\n\r\nSee you at one.\r\n".utf8),
                              from: "owner@example.com", to: ["carlo@example.org"],
                              password: "app-password")

        let reads = await transport.reads
        XCTAssertEqual(reads.filter { $0.wait == .afterUpload }.map(\.line),
                       ["250 2.0.0 OK queued as 1234"])
        XCTAssertEqual(reads.map(\.line).last, "221 2.0.0 closing connection")
        XCTAssertEqual(reads.filter { $0.wait == .ordinary }.count, reads.count - 1)
    }
}
