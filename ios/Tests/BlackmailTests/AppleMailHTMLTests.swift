import XCTest
@testable import Blackmail

/// Tests for the HTML half of an outgoing letter.
///
/// The strings pinned here are not a style choice — they were read off Sam's
/// own device's output, and the reason to pin them exactly is that nothing
/// on this project can see the result. A malformed document renders fine in
/// the composer (which shows the plain text) and fine in Sent Mail (same),
/// and goes wrong only in the recipient's client. That is the same blind
/// spot that let this app send replies with no `In-Reply-To` for months.
final class AppleMailHTMLTests: XCTestCase {

    private let sig = "Sam Example\n555-555-0142"
    private let richSig = "<div dir=\"ltr\"><table><tr><td><b>Sam Example</b></td></tr></table></div>"

    private func account(signature: String = "", html: String = "") -> MailAccount {
        MailAccount(address: "sam@example.com", username: "sam@example.com",
                    signature: signature, signatureHTML: html)
    }

    // MARK: - Whether there is an HTML part at all

    func testAPlainNoteWithNothingRichInItStaysPlainText() {
        // A quarter of his mail is genuinely text/plain, and that is Mail's
        // own behaviour rather than an accident. Sending HTML for a one-line
        // note would be a deviation in the other direction from the one this
        // work is fixing.
        XCTAssertNil(AppleMailHTML.part(for: Draft(to: ["a@b.com"], body: "on my way"),
                                        account: account(signature: sig, html: richSig)))
    }

    func testARichSignatureInTheLetterForcesHTML() {
        let draft = Draft(to: ["a@b.com"], body: "on my way" + Draft.signatureBlock(sig))
        XCTAssertNotNil(AppleMailHTML.part(for: draft,
                                           account: account(signature: sig, html: richSig)))
    }

    func testAReplyIsHTMLEVENWithNoSignatureAtAll() {
        // The case that a signature-keyed rule would get wrong. 19 of his
        // 331 HTML messages carry no signature and 18 of those are replies
        // or forwards — exactly the letters where dropping the HTML loses
        // the quoted original's shape.
        let m = message()
        let draft = Draft.replying(to: m, all: false, myAddress: nil)
        XCTAssertNotNil(AppleMailHTML.part(for: draft, account: account()))
    }

    func testAForwardIsHTMLToo() {
        let draft = Draft.forwarding(message())
        XCTAssertNotNil(AppleMailHTML.part(for: draft, account: account()))
    }

    func testAPlainSignatureAloneDoesNotForceHTML() {
        // Nothing rich is present: a text signature renders identically in
        // the plain part, so an HTML twin would say the same thing twice.
        let draft = Draft(to: ["a@b.com"], body: "hi" + Draft.signatureBlock(sig))
        XCTAssertNil(AppleMailHTML.part(for: draft, account: account(signature: sig)))
    }

    // MARK: - The wrapper

    func testTheWrapperIsByteExact() {
        // 458 of 499 of his HTML bodies open with precisely this. No
        // DOCTYPE, one tag in the head, dir="auto" on the body.
        XCTAssertEqual(AppleMailHTML.documentOpen,
                       "<html><head><meta http-equiv=\"content-type\" "
                       + "content=\"text/html; charset=utf-8\"></head><body dir=\"auto\">")
        let doc = AppleMailHTML.document(body: "hi" + Draft.signatureBlock(sig),
                                         signature: sig, signatureHTML: richSig)
        XCTAssertTrue(doc.hasPrefix(AppleMailHTML.documentOpen), doc)
        XCTAssertTrue(doc.hasSuffix("</body></html>"), doc)
    }

    // MARK: - Laying out what he typed

    func testTheFirstLineIsBareAndTheRestAreDivs() {
        // Not a tidy-up waiting to happen: it is what Mail emits, and the
        // asymmetry is real.
        XCTAssertEqual(AppleMailHTML.paragraphs("one\ntwo\nthree", firstLineBare: true),
                       "one<div>two</div><div>three</div>")
    }

    func testABlankLineBecomesADivHoldingABreak() {
        XCTAssertEqual(AppleMailHTML.paragraphs("one\n\ntwo", firstLineBare: true),
                       "one<div><br></div><div>two</div>")
    }

    func testATrailingSpaceSurvivesAsANonBreakingOne() {
        // HTML collapses it away, and a trailing space is how people
        // separate a sign-off from what follows.
        XCTAssertEqual(AppleMailHTML.escape("Thanks "), "Thanks&nbsp;")
    }

    func testMarkupCharactersInHisProseAreEscapedOnceAndOnlyOnce() {
        // Ampersand first, or the ones the other two introduce get escaped
        // again and the reader sees "&amp;lt;".
        XCTAssertEqual(AppleMailHTML.escape("Marks & Spencer <ok>"),
                       "Marks &amp; Spencer &lt;ok&gt;")
        XCTAssertFalse(AppleMailHTML.escape("a & b").contains("&amp;amp;"))
    }

    // MARK: - Splitting a composed letter back up

    func testAReplySplitsIntoTypedTextSignatureAndQuote() {
        let body = "Thanks for this"
            + Draft.signatureBlock(sig)
            + "\n\nOn Sep 20, 2026, at 8:12\u{202F}PM, Jane <j@x.com> wrote:"
            + "\n> first line\n> second line"
        let layout = AppleMailHTML.layout(of: body, signature: sig)

        XCTAssertEqual(layout.typed, "Thanks for this")
        XCTAssertEqual(layout.signature, sig)
        XCTAssertEqual(layout.quote,
                       .reply(attribution: "On Sep 20, 2026, at 8:12\u{202F}PM, "
                              + "Jane <j@x.com> wrote:",
                              body: "first line\nsecond line"))
    }

    func testASentenceOfHisOwnThatLooksLikeAnAttributionIsNotAQuote() {
        // He could write "On Tuesday she wrote:" in a letter. Treating that
        // as the start of a quote would put his own words in a quote block,
        // which is why the line AFTER it has to actually be quoted.
        let layout = AppleMailHTML.layout(of: "On Tuesday she wrote:\nand I agreed",
                                          signature: "")
        XCTAssertNil(layout.quote)
        XCTAssertEqual(layout.typed, "On Tuesday she wrote:\nand I agreed")
    }

    func testAnEmptyQuotedLineUnwrapsWhetherOrNotTheSpaceSurvived() {
        // A relay may strip the trailing space from "> ".
        let body = "\n\nOn Sep 20, 2026, at 8:12\u{202F}PM, Jane <j@x.com> wrote:"
            + "\n> one\n>\n> two"
        guard case let .reply(_, quoted)? =
                AppleMailHTML.layout(of: body, signature: "").quote else {
            return XCTFail("expected a reply")
        }
        XCTAssertEqual(quoted, "one\n\ntwo")
    }

    func testTheSIGNATUREFoundIsTheLastOneSoAQuotedCopyIsNotMistakenForIt() {
        // Replying to himself puts his signature inside the quote as well.
        // Taking the first match would treat everything after the quoted
        // copy as signature and lose the letter.
        let body = "A new note"
            + Draft.signatureBlock(sig)
        let layout = AppleMailHTML.layout(of: "\(sig)\n\n" + body, signature: sig)
        XCTAssertEqual(layout.signature, sig)
        XCTAssertTrue(layout.typed.hasSuffix("A new note"), layout.typed)
    }

    func testAForwardSplitsIntoItsFourFieldsAndABody() {
        let m = message()
        let layout = AppleMailHTML.layout(of: Draft.forwarding(m).body, signature: "")
        guard case let .forward(fields, body)? = layout.quote else {
            return XCTFail("expected a forward, got \(String(describing: layout.quote))")
        }
        XCTAssertEqual(fields.map(\.0), ["From:", "Date:", "To:", "Subject:"])
        XCTAssertEqual(fields.first?.1, "Jane Smith <jane@example.com>")
        XCTAssertEqual(body, "the original text")
    }

    func testABodyWithNoMarkersAtAllIsSimplyAllTypedText() {
        let layout = AppleMailHTML.layout(of: "just a note", signature: "")
        XCTAssertEqual(layout, AppleMailHTML.Layout(typed: "just a note",
                                                    signature: "", quote: nil))
    }

    // MARK: - The reply skeleton

    func testTheReplyPutsTheAttributionAndTheQuoteInSIBLINGBlockquotes() {
        // This looks wrong written down and it is exactly what his device
        // produces: the attribution gets its own `blockquote type="cite"`,
        // and the original gets a second one beside it. Reproduced rather
        // than tidied, because his correspondents' clients already collapse
        // this shape and a different one would stop collapsing.
        let body = "\n\nOn Sep 20, 2026, at 8:12\u{202F}PM, Jane <j@x.com> wrote:\n> hello"
        let doc = AppleMailHTML.document(body: body, signature: "", signatureHTML: "")

        XCTAssertTrue(doc.contains(
            "<div dir=\"ltr\"><br><blockquote type=\"cite\">On Sep 20, 2026, at 8:12\u{202F}PM, "
            + "Jane &lt;j@x.com&gt; wrote:<br><br></blockquote></div>"), doc)
        XCTAssertTrue(doc.contains(
            "<blockquote type=\"cite\"><div dir=\"ltr\">hello</div></blockquote>"), doc)
        XCTAssertEqual(doc.components(separatedBy: "<blockquote type=\"cite\">").count - 1, 2)
    }

    func testTheAddressInTheAttributionIsEscapedNotLeftAsMarkup() {
        // Unescaped, `<j@x.com>` is an unknown tag and the address vanishes
        // from the rendered attribution entirely.
        let body = "\n\nOn Sep 20, 2026, at 8:12\u{202F}PM, Jane <j@x.com> wrote:\n> hi"
        let doc = AppleMailHTML.document(body: body, signature: "", signatureHTML: "")
        XCTAssertTrue(doc.contains("&lt;j@x.com&gt;"))
        XCTAssertFalse(doc.contains("<j@x.com>"))
    }

    // MARK: - The forward skeleton

    func testTheForwardHeaderLabelsAreBoldAndSoIsTheSubjectItself() {
        let doc = AppleMailHTML.document(body: Draft.forwarding(message()).body,
                                         signature: "", signatureHTML: "")
        XCTAssertTrue(doc.contains("Begin forwarded message:"), doc)
        XCTAssertTrue(doc.contains("<b>From:</b> Jane Smith &lt;jane@example.com&gt;<br>"), doc)
        XCTAssertTrue(doc.contains("<b>Subject:</b> <b>Lunch</b><br>"), doc)
    }

    // MARK: - The signature

    func testTheStoredMarkupGoesInVerbatimUnderTheAnchor() {
        // Verbatim apart from the table colours the quirks-mode fix has to
        // add, and inside the white sheet. Everything of his that is not a
        // `<table>` opening tag must come through untouched.
        let doc = AppleMailHTML.document(body: "hi" + Draft.signatureBlock(sig),
                                         signature: sig, signatureHTML: richSig)
        XCTAssertTrue(doc.contains(AppleMailHTML.signatureAnchor
                                   + AppleMailHTML.signatureOpen
                                   + AppleMailHTML.onWhitePaper(richSig)
                                   + AppleMailHTML.signatureClose), doc)
        XCTAssertTrue(doc.contains("<b>Sam Example</b>"), "his markup was altered")
    }

    // MARK: - The quirks-mode table trap

    /// Apple Mail's envelope has no DOCTYPE, so the letter renders in quirks
    /// mode, and in quirks mode a `<table>` does not inherit `color` from
    /// its ancestors. Without this the wrapper's black text stops at the
    /// first `<td>` and his signature is white-on-white — invisible, not
    /// merely ugly.
    func testEveryTableInTheSignatureCarriesItsOwnColours() {
        let doc = AppleMailHTML.document(body: "hi" + Draft.signatureBlock(sig),
                                         signature: sig, signatureHTML: richSig)
        XCTAssertFalse(doc.contains("<table>"),
                       "a bare <table> inherits nothing in quirks mode")
        XCTAssertTrue(doc.contains("color: rgb(0, 0, 0)"), doc)
        XCTAssertTrue(doc.contains("background-color: rgb(255, 255, 255)"), doc)
    }

    func testOnWhitePaperPrependsToAnExistingStyleRatherThanReplacingIt() {
        let out = AppleMailHTML.onWhitePaper(
            "<table style=\"font-family: Georgia;\"><tr><td>x</td></tr></table>")
        XCTAssertTrue(out.contains("font-family: Georgia;"), out)
        XCTAssertTrue(out.contains(AppleMailHTML.signatureTableStyle), out)
        // His own declarations come AFTER ours, so where they disagree his win.
        guard let ours = out.range(of: AppleMailHTML.signatureTableStyle),
              let his = out.range(of: "font-family: Georgia;") else { return XCTFail(out) }
        XCTAssertLessThan(ours.lowerBound, his.lowerBound)
    }

    func testOnWhitePaperHandlesSeveralTablesAndLeavesOtherTagsAlone() {
        let out = AppleMailHTML.onWhitePaper(
            "<div><table><tr><td>a</td></tr></table><p>between</p>"
            + "<table style=\"width:100%\"><tr><td>b</td></tr></table></div>")
        XCTAssertEqual(out.components(separatedBy: AppleMailHTML.signatureTableStyle).count - 1, 2)
        XCTAssertTrue(out.contains("<p>between</p>"))
        XCTAssertTrue(out.contains("<div>"))
    }

    func testOnWhitePaperLeavesMarkupWithNoTableCompletelyAlone() {
        let plain = "<div dir=\"ltr\">Sam Example<br>555-555-0142</div>"
        XCTAssertEqual(AppleMailHTML.onWhitePaper(plain), plain)
    }

    /// An unterminated `<table` must not eat the rest of the signature.
    func testOnWhitePaperSurvivesMalformedMarkup() {
        let broken = "<div>before<table style=\"x"
        XCTAssertEqual(AppleMailHTML.onWhitePaper(broken), broken)
    }

    func testWithNoStoredMarkupThePlainSignatureIsRenderedInstead() {
        // An account set up without the rich version must still produce a
        // well-formed letter rather than a signature-shaped hole.
        let doc = AppleMailHTML.document(body: "hi" + Draft.signatureBlock(sig),
                                         signature: sig, signatureHTML: "")
        XCTAssertTrue(doc.contains(AppleMailHTML.signatureAnchor
                                   + AppleMailHTML.signatureOpen
                                   + "<div dir=\"ltr\">Sam Example<div>555-555-0142</div></div>"
                                   + AppleMailHTML.signatureClose),
                      doc)
    }

    // MARK: - The white sheet

    /// The defect this exists to prevent: his stored signature declares
    /// `color: rgb(0, 0, 0)` with `background-color: rgba(255, 255, 255, 0)`
    /// — black text on a TRANSPARENT background — so in a dark-mode client
    /// it renders black-on-dark and vanishes. Measured from the real stored
    /// markup, in which `#fff` appears zero times.
    func testTheSignatureDeclaresItsOwnWhitePageAndBlackText() {
        let doc = AppleMailHTML.document(body: "hi" + Draft.signatureBlock(sig),
                                         signature: sig, signatureHTML: richSig)
        guard let open = doc.range(of: AppleMailHTML.signatureOpen) else {
            return XCTFail(doc)
        }
        let wrapper = String(doc[open])
        XCTAssertTrue(wrapper.contains("background-color: #ffffff"),
                      "without an explicit background the signature inherits the "
                      + "reader's dark surface and the black text disappears")
        XCTAssertTrue(wrapper.contains("color: #000000"))
        XCTAssertTrue(wrapper.contains("color-scheme: light"),
                      "tells a dark-mode client not to auto-invert the block")
    }

    /// The wrapper must sit INSIDE the body and wrap only the signature —
    /// not the typed text, and not the quoted original underneath it.
    func testTheWhiteSheetCoversTheSignatureAndNothingElse() {
        let message = Message(id: "1", mailboxID: "INBOX", sender: "Jane Smith <jane@example.com>",
                              senderAddress: "jane@example.com", to: [], cc: [],
                              subject: "Lunch", date: Date(timeIntervalSince1970: 1789719243),
                              textBody: "the original", htmlBody: nil, attachments: [])
        let draft = Draft.replying(to: message, all: false, myAddress: "him@example.com",
                                   signature: sig)
        let doc = AppleMailHTML.document(body: draft.body, signature: sig,
                                         signatureHTML: richSig)

        guard let open = doc.range(of: AppleMailHTML.signatureOpen),
              let close = doc.range(of: AppleMailHTML.signatureClose,
                                    range: open.upperBound..<doc.endIndex),
              let quote = doc.range(of: "<blockquote") else { return XCTFail(doc) }
        XCTAssertLessThan(close.lowerBound, quote.lowerBound,
                          "the white sheet must close before the quoted original, "
                          + "or the reply he is answering ends up on it too")
        XCTAssertFalse(doc[doc.startIndex..<open.lowerBound].contains("bm-signature"))
    }

    func testTheSignatureIsNotAlsoRepeatedInTheTypedRegion() {
        let doc = AppleMailHTML.document(body: "hi" + Draft.signatureBlock(sig),
                                         signature: sig, signatureHTML: richSig)
        XCTAssertEqual(doc.components(separatedBy: "Sam Example").count - 1, 1,
                       "the signature appears twice: \(doc)")
    }

    // MARK: - Storage

    func testTheMarkupSurvivesBeingStoredWithTheAccount() {
        var a = account(signature: sig, html: richSig)
        a.signatureHTML = richSig
        let back = try! JSONDecoder().decode(
            MailAccount.self, from: try! JSONEncoder().encode(a))
        XCTAssertEqual(back.signatureHTML, richSig)
    }

    func testAnAccountStoredBeforeThisFieldExistedStillDecodes() {
        // The same trap that the plain signature fell into: Swift's
        // synthesized decoder does not use a property's default, so a new
        // field would otherwise make every stored account fail to load and
        // show the setup form to a man who is already set up.
        let legacy = #"{"address":"a@b.com","username":"a@b.com","imapHost":"imap.gmail.com","imapPort":993,"smtpHost":"smtp.gmail.com","smtpPort":465,"displayName":"Sam","signature":"Sam"}"#
        let back = try? JSONDecoder().decode(MailAccount.self, from: Data(legacy.utf8))
        XCTAssertNotNil(back)
        XCTAssertEqual(back?.signatureHTML, "")
        XCTAssertEqual(back?.signature, "Sam")
    }

    // MARK: - Helpers

    private func message() -> Message {
        Message(id: "1/9", mailboxID: "INBOX",
                sender: "Jane Smith <jane@example.com>", senderAddress: "jane@example.com",
                to: ["sam@example.com"], cc: [], subject: "Lunch",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                textBody: "the original text", htmlBody: nil, attachments: [])
    }
}
