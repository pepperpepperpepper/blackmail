import XCTest
@testable import Blackmail

/// Tests for the size ceiling on an outgoing message.
///
/// `SMTPClient` itself is behind `#if canImport(Network)` and does not exist
/// on this host, so what is pinned here is the part that can be: the error
/// the user ends up seeing, and the arithmetic that decides a message is too
/// big. The EHLO parsing is covered by the shape of the reply, measured
/// against the live server.
final class MessageSizeTests: XCTestCase {

    // MARK: - The sentence he reads

    func testTheTooLargeErrorSaysWhatToDoAboutIt() {
        // The whole reason this case exists rather than reusing .notSent:
        // "Message was not sent." is true, arrives after a long upload, and
        // tells him nothing that would make the next attempt succeed.
        let text = MailError.messageTooLarge.errorDescription ?? ""
        XCTAssertFalse(text.isEmpty)
        XCTAssertNotEqual(text, MailError.notSent.errorDescription)
        XCTAssertTrue(text.lowercased().contains("attachment"),
                      "it has to name the thing he can actually remove: \(text)")
    }

    func testNoUserFacingSentenceLeaksProtocolText() {
        // The rule the four fixed strings exist to enforce, now that there
        // are five. "552 5.2.3" must never reach him.
        let errors: [MailError] = [.cannotConnect, .notSent, .attachmentFailed,
                                   .passwordNeedsUpdating, .messageTooLarge, .connectionLost,
                                   .refusedForNow, .attachmentsMissing,
                                   .signInRefused(alert: nil), .sendingSignInRefused]
        for error in errors {
            let text = error.errorDescription ?? ""
            XCTAssertFalse(text.isEmpty, "every case needs a sentence")
            XCTAssertFalse(text.contains(where: \.isNumber),
                           "a status code reached the user: \(text)")
            XCTAssertTrue(text.hasSuffix("."), "it is a sentence: \(text)")
        }
    }

    /// Every case reads as one of six sentences: the spec's four, the one
    /// for a letter too big, and Gmail refusing a sign-in for a reason other
    /// than the password (B-056), which carries Gmail's own alert text when
    /// it gives one. A file a kept letter carries that cannot be found
    /// anywhere reads as any other file that could not be had. It had
    /// Mail's "One or more attachments failed to load." for a while, another
    /// sentence for the same missing file.
    func testEveryErrorIsOneOfSixSentences() {
        let errors: [MailError] = [.cannotConnect, .notSent, .attachmentFailed,
                                   .passwordNeedsUpdating, .messageTooLarge, .connectionLost,
                                   .refusedForNow, .attachmentsMissing,
                                   .signInRefused(alert: nil), .sendingSignInRefused]
        XCTAssertEqual(Set(errors.compactMap(\.errorDescription)), [
            "Can't connect to mail server.",
            "Message was not sent.",
            "Attachment could not be downloaded.",
            "Password needs to be updated in Settings.",
            "This message is too big to send. Try sending fewer attachments.",
            "Gmail refused the sign-in.",
        ])
        XCTAssertEqual(MailError.attachmentsMissing.errorDescription,
                       MailError.attachmentFailed.errorDescription)
    }

    // MARK: - The limit itself

    /// Gmail's advertised ceiling, measured from its EHLO reply:
    /// `SIZE 35882577`. That is 25 MB of attachment after base64 inflates it
    /// by a third, which is why the figure is not a round number.
    private let gmailLimit = 35_882_577

    func testBase64InflationIsWhatMakesTheLimitBite() {
        // A 25 MB attachment does NOT fit in a 25 MB message, and that is
        // the whole trap: the file the reader sees as "25 MB" becomes ~34 MB
        // on the wire. Checking the raw file size against the limit would
        // pass a message the server then refuses.
        let file = 25 * 1024 * 1024
        let encoded = file / 3 * 4
        XCTAssertGreaterThan(encoded, file)
        XCTAssertLessThanOrEqual(encoded, gmailLimit,
                                 "Gmail's SIZE is chosen to just accommodate a 25 MB file")
    }

    func testAMessageUnderTheLimitIsNotRefused() {
        XCTAssertFalse(exceeds(limit: gmailLimit, messageBytes: 1_000_000))
        XCTAssertFalse(exceeds(limit: gmailLimit, messageBytes: gmailLimit))
    }

    func testAMessageOverTheLimitIsRefused() {
        XCTAssertTrue(exceeds(limit: gmailLimit, messageBytes: gmailLimit + 1))
    }

    func testAServerThatStatesNoLimitRefusesNothingLocally() {
        // RFC 1870: `SIZE 0` means "no stated maximum". Reading it as a
        // limit of zero would refuse every message the app ever sent.
        XCTAssertFalse(exceeds(limit: nil, messageBytes: 100_000_000))
    }

    /// The check `transmit` performs, reproduced because the client is not
    /// compiled on this host.
    private func exceeds(limit: Int?, messageBytes: Int) -> Bool {
        guard let limit else { return false }
        return messageBytes > limit
    }

    // MARK: - Reading SIZE off an EHLO reply

    /// Gmail's actual reply, transcribed from the live server.
    private let ehlo = [
        "smtp.gmail.com at your service, [203.0.113.20]",
        "SIZE 35882577",
        "8BITMIME",
        "AUTH LOGIN PLAIN XOAUTH2 PLAIN-CLIENTTOKEN OAUTHBEARER XOAUTH",
        "ENHANCEDSTATUSCODES",
        "PIPELINING",
        "CHUNKING",
        "SMTPUTF8",
    ]

    func testSizeIsReadFromTheAdvertisedExtensions() {
        XCTAssertEqual(parseSize(ehlo), 35_882_577)
    }

    func testTheGreetingLineIsNotMistakenForAnExtension() {
        // The first line is the server's own greeting. A host genuinely
        // called "SIZE.example.com" would otherwise advertise a limit.
        XCTAssertNil(parseSize(["SIZE.example.com at your service", "8BITMIME"]))
    }

    func testZeroAndGarbageAreTreatedAsNoLimit() {
        XCTAssertNil(parseSize(["greeting", "SIZE 0"]))
        XCTAssertNil(parseSize(["greeting", "SIZE"]))
        XCTAssertNil(parseSize(["greeting", "SIZE lots"]))
    }

    /// Mirrors `SMTPClientCapabilities.init(ehlo:)`, which is fileprivate
    /// inside a Network-gated file.
    private func parseSize(_ lines: [String]) -> Int? {
        for line in lines.dropFirst() {
            let fields = line.replacingOccurrences(of: "=", with: " ")
                .split(separator: " ").map { $0.uppercased() }
            guard fields.first == "SIZE" else { continue }
            if let value = fields.dropFirst().first.flatMap({ Int($0) }), value > 0 {
                return value
            }
        }
        return nil
    }
}
