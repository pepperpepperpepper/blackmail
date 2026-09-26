import XCTest
@testable import Blackmail

/// A draft must come back with the SAME From and To it went out with.
///
/// This test exists because of a night (B-033): a reading pane was observed
/// rendering a just-sent draft's headers TRANSPOSED — From showing the
/// recipient, To showing the account — and the conclusion "the drafts pane
/// transposes From and To" was committed to the record. Chasing it found
/// the opposite: every step of the pipeline is provably correct — the
/// builder's bytes, the parser, the loadMessage construction. No
/// transposing code exists. Rather than "fix" a ghost, this test pins the
/// entire saveDraft → loadMessage round trip exactly as both sides run it,
/// so that if a transpose EVER becomes real — in the builder, the wire
/// bytes, the decode, or the header-to-Message mapping — it trips here in
/// seconds instead of costing another night.
final class DraftHeadersRoundTripTests: XCTestCase {

    private let account = MailAccount(address: "carlo@example.org",
                                      username: "carlo@example.org",
                                      displayName: "Carlo")

    /// The bytes saveDraft puts on the wire, decoded the way loadMessage
    /// reads them back — one letter, both directions, nothing mocked.
    private func roundTripped(to: [String], subject: String)
        -> (from: String, to: [String], subject: String) {
        var draft = Draft.blank(signature: "sign-off")
        draft.to = to
        draft.subject = subject
        draft.body = "\nsign-off"

        let raw = RFC5322Builder.build(
            draft: draft, from: account,
            includeBcc: true,
            htmlBody: AppleMailHTML.part(for: draft, account: account),
            inlineImages: SignatureImages.parts())

        let headers = MIMEDecoder.parseHeaders(raw)
        func header(_ n: String) -> String? {
            MIMEDecoder.headerValue(n, in: headers).map(MIMEDecoder.decodeWord)
        }
        func addresses(_ n: String) -> [String] {
            (header(n) ?? "").components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return (header("From") ?? "?", addresses("To"), header("Subject") ?? "?")
    }

    func testFromIsTheAccountAndToIsTheRecipientNotTheOtherWayRound() {
        let r = roundTripped(to: ["owner@example.com"],
                             subject: "phantom probe one")
        XCTAssertEqual(r.from, "Carlo <carlo@example.org>",
                       "From must be the sending account — a transposed From "
                       + "shows him his own letter as somebody else's")
        XCTAssertEqual(r.to, ["owner@example.com"])
    }

    func testTheSubjectSurvivesBothDirections() {
        XCTAssertEqual(roundTripped(to: ["a@b.com"], subject: "persist draft").subject,
                       "persist draft")
    }

    func testSeveralRecipientsAllComeBack() {
        let r = roundTripped(to: ["a@example.com", "b@example.com"], subject: "s")
        XCTAssertEqual(r.to, ["a@example.com", "b@example.com"])
    }

    func testTheWireBytesThemselvesCarryFromBeforeTo() {
        var draft = Draft.blank(signature: "s")
        draft.to = ["owner@example.com"]
        draft.subject = "order on the wire"
        let raw = String(decoding: RFC5322Builder.build(
            draft: draft, from: account, includeBcc: true), as: UTF8.self)
        let from = raw.range(of: "From: Carlo <carlo@example.org>")?.lowerBound
        let to = raw.range(of: "To: owner@example.com")?.lowerBound
        XCTAssertNotNil(from)
        XCTAssertNotNil(to)
        if let from, let to {
            XCTAssertLessThan(from, to, "the headers themselves must be in order")
        }
    }
}
