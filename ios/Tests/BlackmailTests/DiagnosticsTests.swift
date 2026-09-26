import XCTest
@testable import Blackmail

/// Tests for the one file that can leak the account password.
///
/// The diagnostics transcript exists to be copied and sent to whoever is
/// helping over the phone, so a redaction failure does not merely log a
/// secret — it publishes one. These tests are the reason the log store is
/// Foundation-only rather than living inside the UIKit-guarded presenter.
final class DiagnosticsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Diagnostics.clear()
    }

    // MARK: - IMAP LOGIN

    func testImapLoginPasswordIsRemovedButUsernameSurvives() {
        let redacted = Diagnostics.redact(#"a003 LOGIN him@example.com "hunter2pass1234""#)
        XCTAssertFalse(redacted.contains("hunter2pass1234"), "the password is still in the log")
        XCTAssertTrue(redacted.contains("him@example.com"),
                      "the username is not secret and is genuinely useful when diagnosing")
        XCTAssertTrue(redacted.contains("a003"), "the tag is needed to pair command with reply")
    }

    func testLoginRedactionIsCaseInsensitiveAndSurvivesOddSpacing() {
        for variant in [#"a1 login him@x.com "secret-value""#,
                        #"a1 Login him@x.com secret-value"#,
                        "a1 LOGIN him@x.com secret-value"] {
            XCTAssertFalse(Diagnostics.redact(variant).lowercased().contains("secret"),
                           "leaked from: \(variant)")
        }
    }

    func testPasswordContainingSpacesOrQuotesIsStillFullyRemoved() {
        // An app password pasted straight from Google keeps its spaces, and
        // the redactor must not stop at the first one.
        let line = #"a1 LOGIN him@x.com "abcd efgh ijkl mnop""#
        let redacted = Diagnostics.redact(line)
        for chunk in ["abcd", "efgh", "ijkl", "mnop"] {
            XCTAssertFalse(redacted.contains(chunk), "leaked \(chunk)")
        }
    }

    // MARK: - SMTP AUTH

    func testSmtpAuthPayloadsAreRemoved() {
        let plain = Diagnostics.redact("AUTH PLAIN AGhpbUB4LmNvbQBzZWNyZXQ=")
        XCTAssertFalse(plain.contains("AGhpbUB4LmNvbQBzZWNyZXQ="))
        XCTAssertTrue(plain.contains("AUTH PLAIN"), "the mechanism is useful, the payload is not")

        let login = Diagnostics.redact("AUTH LOGIN aGltQHguY29t")
        XCTAssertFalse(login.contains("aGltQHguY29t"))
    }

    /// The AUTH LOGIN dialogue sends the password as a bare base64 line with
    /// no keyword attached, so there is nothing to pattern-match on. Anything
    /// that is nothing but a long base64 token is redacted on suspicion.
    func testBareBase64LineIsRedactedOnSuspicion() {
        XCTAssertEqual(Diagnostics.redact("c2VjcmV0cGFzc3dvcmQxMjM0"), "<redacted>")
        XCTAssertEqual(Diagnostics.redact("  c2VjcmV0cGFzc3dvcmQxMjM0  "), "<redacted>")
    }

    func testOrdinaryProtocolTrafficIsNotRedacted() {
        // Over-redaction costs a support call, so check the common lines survive.
        let keep = [
            "* OK [UIDVALIDITY 1474997782] UIDs valid",
            #"* LIST (\HasNoChildren \Sent) "/" "[Gmail]/Sent Mail""#,
            "a004 OK [READ-WRITE] SELECT completed",
            "* 12 FETCH (UID 345 FLAGS (\\Seen))",
            "250-smtp.gmail.com at your service",
            "a005 NO [AUTHENTICATIONFAILED] Invalid credentials (Failure)",
        ]
        for line in keep {
            XCTAssertEqual(Diagnostics.redact(line), line, "over-redacted: \(line)")
        }
    }

    func testShortTokensAreNotMistakenForCredentials() {
        // A short alphanumeric run is ordinary protocol vocabulary.
        XCTAssertEqual(Diagnostics.redact("OK"), "OK")
        XCTAssertEqual(Diagnostics.redact("CAPABILITY"), "CAPABILITY")
        XCTAssertEqual(Diagnostics.redact("a001"), "a001")
    }

    // MARK: - Content

    func testLiteralsAreDescribedRatherThanReproduced() {
        // His correspondence is not diagnostic data.
        XCTAssertEqual(Diagnostics.describeLiteral(byteCount: 2048), "{2048 bytes}")
    }

    // MARK: - The store

    func testLogRedactsOnTheWayInSoTheBufferNeverHoldsASecret() {
        Diagnostics.log(.sent, #"a1 LOGIN him@x.com "topsecret1234""#)
        let stored = Diagnostics.entries.map(\.text).joined()
        XCTAssertFalse(stored.contains("topsecret1234"),
                       "redaction must happen on write, or the secret exists in memory")
        XCTAssertFalse(Diagnostics.transcript().contains("topsecret1234"))
    }

    func testBufferIsBoundedSoALongSessionCannotGrowForever() {
        for i in 0..<900 { Diagnostics.log(.note, "line \(i)") }
        XCTAssertLessThanOrEqual(Diagnostics.entries.count, 500)
        // The ring keeps the RECENT end, which is the end that explains the
        // failure you are currently looking at.
        XCTAssertTrue(Diagnostics.transcript().contains("line 899"))
        XCTAssertFalse(Diagnostics.transcript().contains("line 0 "))
    }

    func testTranscriptIsStableRegardlessOfDeviceLocale() {
        Diagnostics.log(.sent, "a1 CAPABILITY")
        let text = Diagnostics.transcript()
        XCTAssertTrue(text.contains("→ a1 CAPABILITY"))
        // en_US_POSIX timestamps, so a device set to another language still
        // produces a transcript someone else can read.
        XCTAssertNotNil(text.range(of: #"^\d{2}:\d{2}:\d{2}\.\d{3} "#,
                                   options: .regularExpression))
    }
}
