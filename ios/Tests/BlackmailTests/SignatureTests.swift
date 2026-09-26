import XCTest
@testable import Blackmail

/// Tests for the signature that goes out on everything he sends.
///
/// It is the single most-repeated piece of text in the product — every
/// letter, for years — so the cases that matter are the ones that would
/// quietly corrupt it or duplicate it rather than the happy path.
final class SignatureTests: XCTestCase {

    private let sig = "Carlo Example\n100 Example Ave\nAnytown XX 00000"

    private func message(text: String = "hello", subject: String = "Lunch") -> Message {
        Message(id: "1/9", mailboxID: "INBOX",
                sender: "Jane Smith <jane@example.com>", senderAddress: "jane@example.com",
                to: ["carlo@example.com"], cc: [], subject: subject,
                date: Date(timeIntervalSince1970: 1_700_000_000),
                textBody: text, htmlBody: nil, attachments: [])
    }

    // MARK: - The block

    func testNoSigdashIsAddedBecauseMailDoesNotAddOne() {
        // This is a reversal. RFC 3676's "-- " delimiter is the textbook
        // answer and Apple Mail has never emitted one — Sam's own signature
        // arrives with nothing above it in every message he has sent. The
        // delimiter also has a cost with a signature as long as his: clients
        // that treat everything below a sigdash as hideable would collapse
        // the signature's confidentiality notice out of sight.
        let block = Draft.signatureBlock(sig)
        XCTAssertEqual(block, "\n\n" + sig)
        XCTAssertFalse(block.contains("--"))
    }

    func testADelimiterTheOwnerTypedHimselfIsLeftAlone() {
        // We add none, but we do not remove one either. A signature pasted
        // in from another client, delimiter and all, is his text.
        XCTAssertEqual(Draft.signatureBlock("--\nCarlo"), "\n\n--\nCarlo")
    }

    func testAnEmptySignatureAddsNothingAtAll() {
        // Not even the separator. An account that has never been asked must
        // not start sending a bare "--" at the foot of every letter.
        XCTAssertEqual(Draft.signatureBlock(""), "")
        XCTAssertEqual(Draft.signatureBlock("   \n\n  "), "")
    }

    func testInternalBlankLinesAndIndentationSurvive() {
        // People lay signatures out. Collapsing that would silently reformat
        // something he composed deliberately.
        let laid = "Carlo Example\n\n    100 Example Ave\n    Anytown XX 00000"
        XCTAssertTrue(Draft.signatureBlock(laid).hasSuffix(laid))
    }

    // MARK: - Where it lands

    func testAFreshLetterOpensWithTheSignatureBelowTheCursor() {
        let body = Draft.blank(signature: sig).body
        XCTAssertTrue(body.hasSuffix(sig))
        XCTAssertTrue(body.hasPrefix("\n"), "the cursor sits above it")
    }

    func testAReplyPutsTheSignatureABOVETheQuotedText() {
        // Below the quote it is buried under however much of the original
        // he kept, which for a long thread is out of sight entirely.
        let body = Draft.replying(to: message(), all: false,
                                  myAddress: "carlo@example.com", signature: sig).body
        guard let sigAt = body.range(of: sig),
              let quoteAt = body.range(of: "wrote:") else {
            return XCTFail("signature or quote missing from: \(body)")
        }
        XCTAssertLessThan(sigAt.lowerBound, quoteAt.lowerBound)
    }

    func testAForwardPutsTheSignatureAboveTheForwardedHeader() {
        let body = Draft.forwarding(message(), signature: sig).body
        guard let sigAt = body.range(of: sig),
              let fwdAt = body.range(of: "Begin forwarded message:") else {
            return XCTFail("signature or header missing from: \(body)")
        }
        XCTAssertLessThan(sigAt.lowerBound, fwdAt.lowerBound)
    }

    func testTheQuotedTextIsNotItselfPrefixedByTheSignature() {
        // Regression guard: the signature must not end up inside the "> "
        // quoting, which would make it look like the other person said it.
        let body = Draft.replying(to: message(text: "your letter"), all: false,
                                  myAddress: nil, signature: sig).body
        XCTAssertFalse(body.contains("> Carlo Example"))
        XCTAssertTrue(body.contains("> your letter"))
    }

    func testNoSignatureLeavesTheOldBodyShapeExactlyAsItWas() {
        // Everything already verified on device was built without a
        // signature; adding the feature must not move anything for an
        // account that has none.
        let withNone = Draft.replying(to: message(), all: false, myAddress: nil).body
        XCTAssertTrue(withNone.hasPrefix("\n\n"))
        XCTAssertTrue(withNone.contains("wrote:\n> hello"))
    }

    // MARK: - Round trip through the account

    func testTheSignatureSurvivesBeingStoredAndRead() {
        // MailAccount is Codable and persisted as JSON; newlines are the
        // thing most likely to be lost in that trip.
        var account = MailAccount(address: "a@b.com", username: "a@b.com")
        account.signature = sig
        let data = try! JSONEncoder().encode(account)
        let back = try! JSONDecoder().decode(MailAccount.self, from: data)
        XCTAssertEqual(back.signature, sig)
    }

    func testAnAccountEncodedBeforeSignaturesExistedStillDecodes() {
        // The stored account on the dev iPad predates this field. A missing
        // key must default to empty rather than failing to decode, or the
        // app would show the setup form to someone already set up.
        let legacy = #"{"address":"a@b.com","username":"a@b.com","imapHost":"imap.gmail.com","imapPort":993,"smtpHost":"smtp.gmail.com","smtpPort":465,"displayName":"Carlo"}"#
        let back = try? JSONDecoder().decode(MailAccount.self, from: Data(legacy.utf8))
        XCTAssertNotNil(back, "an account stored before this field existed must still load")
        XCTAssertEqual(back?.signature, "")
        XCTAssertEqual(back?.displayName, "Carlo")
    }
}
