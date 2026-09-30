import XCTest
@testable import Blackmail

/// A `mailto:` link read into the letter it asks for (RFC 6068), so a tap
/// on one opens this app's composer instead of Apple Mail's (B-036).
final class MailtoLinkTests: XCTestCase {

    private func parse(_ link: String) -> MailtoLink.Fields? {
        MailtoLink.parse(link)
    }

    func testABareAddress() {
        XCTAssertEqual(parse("mailto:carlo@example.org"),
                       MailtoLink.Fields(to: ["carlo@example.org"]))
    }

    func testNotAMailtoLinkIsNothing() {
        XCTAssertNil(parse("https://example.org/?to=carlo@example.org"))
        XCTAssertNil(parse("carlo@example.org"))
        XCTAssertEqual(parse("MAILTO:carlo@example.org")?.to, ["carlo@example.org"],
                       "the scheme is not case sensitive")
    }

    /// Several addresses, split on commas, and those in `to=` after the
    /// ones before the `?`.
    func testSeveralAddresses() {
        XCTAssertEqual(parse("mailto:carlo@example.org,%20sam@example.com?to=owner@example.com")?.to,
                       ["carlo@example.org", "sam@example.com", "owner@example.com"])
        XCTAssertEqual(parse("mailto:?to=carlo@example.org%2Csam@example.com")?.to,
                       ["carlo@example.org", "sam@example.com"])
    }

    /// Everything is percent-decoded: an `@` written as `%40`, a space, and
    /// UTF-8 in the subject.
    func testPercentEncoding() {
        let fields = parse("mailto:carlo%40example.org?subject=Caf%C3%A9%20on%20Sunday%3F")
        XCTAssertEqual(fields?.to, ["carlo@example.org"])
        XCTAssertEqual(fields?.subject, "Café on Sunday?")
    }

    /// RFC 6068's `+` is a plus, not a space, or `sam+news@` would arrive
    /// as `sam news@`.
    func testAPlusIsAPlus() {
        let fields = parse("mailto:sam+news@example.com?subject=1+1")
        XCTAssertEqual(fields?.to, ["sam+news@example.com"])
        XCTAssertEqual(fields?.subject, "1+1")
    }

    func testCcAndBccAndTheirRepeats() {
        let fields = parse("mailto:carlo@example.org?cc=sam@example.com&CC=owner@example.com"
                           + "&bcc=archive@example.net")
        XCTAssertEqual(fields?.cc, ["sam@example.com", "owner@example.com"])
        XCTAssertEqual(fields?.bcc, ["archive@example.net"])
    }

    /// The body's line breaks, sent as `%0D%0A`, are the composer's, and
    /// so is a lone `%0D` or `%0A`.
    func testTheBodysLines() {
        let fields = parse("mailto:carlo@example.org?Subject=Lunch&body=See%20you%2C%0D%0A%0D%0ASam")
        XCTAssertEqual(fields?.subject, "Lunch", "keys are not case sensitive")
        XCTAssertEqual(fields?.body, "See you,\n\nSam")
        XCTAssertEqual(parse("mailto:?body=a%0Db%0Ac")?.body, "a\nb\nc")
    }

    /// A link's Cc and Bcc are a stranger's to fill, so the composer opens
    /// with both rows showing whenever the link filled either: an address
    /// in a hidden Bcc row would still get the letter.
    func testALinksCcAndBccAreShown() throws {
        let hidden = try XCTUnwrap(MailtoLink.draft(
            from: URL(string: "mailto:list@example.org?bcc=someone@example.net&subject=Unsubscribe")!,
            signature: "Sam"))
        XCTAssertEqual(hidden.bcc, ["someone@example.net"])
        XCTAssertTrue(hidden.showsCcAndBcc)
        XCTAssertTrue(try XCTUnwrap(MailtoLink.draft(
            from: URL(string: "mailto:list@example.org?cc=someone@example.net")!,
            signature: "Sam")).showsCcAndBcc)
        XCTAssertFalse(try XCTUnwrap(MailtoLink.draft(
            from: URL(string: "mailto:list@example.org?subject=Hello")!,
            signature: "Sam")).showsCcAndBcc, "nothing in them, and the rows stay out of his way")
    }

    /// A malformed escape keeps the field as written rather than losing it,
    /// and fields no composer shows are ignored.
    func testWhatCannotBeReadIsKeptOrIgnored() {
        let fields = parse("mailto:carlo@example.org?subject=100%&in-reply-to=%3Cx@y%3E&body=")
        XCTAssertEqual(fields?.subject, "100%")
        XCTAssertEqual(fields?.body, "")
        XCTAssertEqual(fields?.to, ["carlo@example.org"])
    }

    /// The composer opens with the link's fields and his signature where a
    /// new letter has it: under the body, or under the empty line he types
    /// on.
    func testTheLetterCarriesHisSignature() throws {
        let signature = "Sam"
        let withBody = try XCTUnwrap(MailtoLink.draft(
            from: URL(string: "mailto:carlo@example.org?cc=owner@example.com&subject=Hi&body=Hello")!,
            signature: signature))
        XCTAssertEqual(withBody.to, ["carlo@example.org"])
        XCTAssertEqual(withBody.cc, ["owner@example.com"])
        XCTAssertEqual(withBody.subject, "Hi")
        XCTAssertEqual(withBody.body, "Hello\n\nSam")

        let bare = try XCTUnwrap(MailtoLink.draft(from: URL(string: "mailto:carlo@example.org")!,
                                                  signature: signature))
        XCTAssertEqual(bare.body, Draft.blank(signature: signature).body)
        XCTAssertNil(MailtoLink.draft(from: URL(string: "https://example.org")!, signature: signature))
    }
}
