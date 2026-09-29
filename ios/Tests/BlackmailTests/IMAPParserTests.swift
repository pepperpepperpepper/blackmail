import XCTest
@testable import Blackmail

/// Tests for the IMAP response parser.
///
/// This is the module that crashed. `fetchSummaries` asks for BODYSTRUCTURE on
/// every message in a page, so a single malformed one does not spoil a row —
/// it takes down the refresh, every time, forever, on a device whose owner
/// cannot delete the offending message. That is the shape of failure these
/// tests exist to prevent.
final class IMAPParserTests: XCTestCase {

    private func line(_ text: String, literals: [Data] = []) -> IMAPResponseLine {
        IMAPResponseLine(text: text, literals: literals)
    }

    // MARK: - Tokenizer

    func testQuotedStringsEscapesAndNil() {
        let tokens = IMAPParser.tokenize(line(#"(a "quoted \"inner\" string" NIL)"#))
        guard case .list(let items)? = tokens.first else { return XCTFail("expected a list") }
        XCTAssertEqual(items.count, 3)
        if case .quoted(let s) = items[1] {
            XCTAssertEqual(s, #"quoted "inner" string"#)
        } else {
            XCTFail("expected a quoted string, got \(items[1])")
        }
        if case .nilValue = items[2] {} else {
            XCTFail("NIL must be nilValue, never the atom \"NIL\"")
        }
    }

    func testUnbalancedParensDegradeRatherThanCrash() {
        _ = IMAPParser.tokenize(line("(((((unclosed"))
        _ = IMAPParser.tokenize(line("closed)))))"))
        _ = IMAPParser.tokenize(line(#"(unterminated "quote"#))
    }

    /// REGRESSION, and the worst defect found in the whole engine. The
    /// BODYSTRUCTURE walker recursed once per nesting level with no cap and
    /// segfaulted at roughly 2,000 levels — reachable from one crafted message
    /// sitting in the inbox. Note the `indirect enum` token tree also recurses
    /// when it is RELEASED, so capping only the walker was not sufficient.
    func testPathologicallyNestedBodyStructureDoesNotCrash() {
        let depth = 5_000
        let nested = String(repeating: "(", count: depth)
            + #""TEXT" "PLAIN" NIL NIL NIL "7BIT" 1 1"#
            + String(repeating: ")", count: depth)
        let started = Date()
        let results = IMAPParser.parseFetch([line("* 1 FETCH (UID 1 BODYSTRUCTURE \(nested))")])
        XCTAssertLessThan(Date().timeIntervalSince(started), 5.0)
        XCTAssertNotNil(results.first, "it should still produce a result, just a capped one")
    }

    // MARK: - FETCH

    func testFetchItemsInAnyOrderWithUnknownItemsIgnored() {
        let l = line("""
        * 12 FETCH (FLAGS (\\Seen \\Flagged) UID 345 X-GM-MSGID 99 RFC822.SIZE 4096 \
        INTERNALDATE "18-Sep-2026 09:14:03 +0100")
        """)
        let results = IMAPParser.parseFetch([l])
        let r = results.first
        XCTAssertEqual(r?.uid, 345)
        XCTAssertEqual(r?.size, 4096)
        XCTAssertEqual(r?.isSeen, true)
        XCTAssertEqual(r?.isFlagged, true)
        XCTAssertNotNil(r?.internalDate, "INTERNALDATE must parse under en_US_POSIX")
    }

    func testInternalDateParsesRegardlessOfDeviceLocale() {
        // A DateFormatter without en_US_POSIX reads "Sep" in the device's
        // language, so on a French iPad every date silently becomes nil and
        // the list sorts by epoch.
        let r = IMAPParser.parseFetch([
            line(#"* 1 FETCH (UID 1 INTERNALDATE "18-Sep-2026 09:14:03 +0100")"#)
        ]).first
        guard let d = r?.internalDate else { return XCTFail("INTERNALDATE did not parse") }
        XCTAssertEqual(d.timeIntervalSince1970, 1789719243, accuracy: 1)
    }

    func testEnvelopeAddressesAndEncodedSubject() {
        let l = line("""
        * 1 FETCH (UID 7 ENVELOPE ("Fri, 18 Sep 2026 09:14:03 +0100" \
        "=?UTF-8?Q?Caf=C3=A9_meeting?=" \
        (("Jane Smith" NIL "jane" "example.com")) NIL NIL \
        (("Bob" NIL "bob" "example.org")) NIL NIL NIL "<abc@example.com>"))
        """)
        let r = IMAPParser.parseFetch([l]).first
        let env = r?.envelope
        XCTAssertEqual(env?.subject, "Café meeting", "RFC 2047 must be decoded in the envelope")
        XCTAssertEqual(env?.from.first?.name, "Jane Smith")
        XCTAssertEqual(env?.from.first?.address, "jane@example.com")
        XCTAssertEqual(env?.from.first?.formatted, "Jane Smith <jane@example.com>")
        XCTAssertEqual(env?.to.first?.address, "bob@example.org")
        XCTAssertEqual(env?.messageID, "<abc@example.com>")
    }

    func testLiteralIsSplicedBackByIndex() {
        // TLSConnection has already consumed the bytes and left a marker; the
        // parser must look them up rather than re-read the socket.
        let marker = "\(IMAPResponseLine.literalMarker)0\(IMAPResponseLine.literalMarker)"
        let l = line("* 1 FETCH (UID 4 BODY[] \(marker))", literals: [Data("raw body".utf8)])
        let r = IMAPParser.parseFetch([l]).first
        XCTAssertEqual(r?.body.map { String(decoding: $0, as: UTF8.self) }, "raw body")
    }

    func testOutOfRangeLiteralIndexDoesNotCrash() {
        let marker = "\(IMAPResponseLine.literalMarker)9\(IMAPResponseLine.literalMarker)"
        _ = IMAPParser.parseFetch([line("* 1 FETCH (UID 4 BODY[] \(marker))", literals: [])])
    }

    // MARK: - LIST and SELECT

    func testListReadsSpecialUseAndDelimiter() {
        let rows = IMAPParser.parseList([
            line(#"* LIST (\HasNoChildren \Sent) "/" "[Gmail]/Sent Mail""#),
            line(#"* LIST (\HasNoChildren \Trash) "/" "[Gmail]/Trash""#),
            line(#"* LIST (\HasNoChildren) "/" "INBOX""#),
        ])
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].name, "[Gmail]/Sent Mail")
        XCTAssertEqual(rows[0].delimiter, "/")
        XCTAssertEqual(rows[0].specialUse, .sent)
        XCTAssertEqual(rows[1].specialUse, .trash)
        XCTAssertEqual(rows[2].specialUse, .inbox, "INBOX is special-cased by name")
    }

    func testModifiedUTF7FolderNameIsDecoded() {
        // Without this a German or Japanese folder shows as "&AOQ-" gibberish.
        let rows = IMAPParser.parseList([line(#"* LIST () "/" "Gesch&AOQ-ftlich""#)])
        XCTAssertEqual(rows.first?.name, "Geschäftlich")
    }

    func testSelectReadsUidValidityWhichIsTheCorrectnessCriticalOne() {
        let state = IMAPParser.parseSelect([
            line("* 42 EXISTS"),
            line("* OK [UIDVALIDITY 1474997782] UIDs valid"),
            line("* OK [UIDNEXT 512] Predicted next UID"),
            line(#"* FLAGS (\Answered \Flagged \Seen)"#),
            line(#"* OK [PERMANENTFLAGS (\Answered \Flagged \Seen \*)] Limited"#),
        ])
        XCTAssertEqual(state?.uidValidity, 1474997782)
        XCTAssertEqual(state?.uidNext, 512)
        XCTAssertEqual(state?.exists, 42)
        XCTAssertEqual(state?.readOnly, false)
    }

    /// EXISTS sets the count and each EXPUNGE takes one off it, in the order
    /// they came, whatever else is in the answer; an answer with neither
    /// leaves it alone (B-045).
    func testMessageCountFollowsExistsAndExpungeInTheOrderTheyCame() {
        let answer = [
            line("* 12 FETCH (UID 1004 FLAGS (\\Seen))"),
            line("* 3 EXPUNGE"),
            line("* 20 EXISTS"),
            line("* 7 expunge"),
            line("* SEARCH 1 2 3"),
        ]
        XCTAssertEqual(IMAPParser.messageCount(after: answer, from: 17), 19)
        XCTAssertEqual(IMAPParser.messageCount(after: [line("* 3 EXPUNGE"), line("* 1 EXPUNGE")],
                                               from: 17), 15)
        XCTAssertNil(IMAPParser.messageCount(after: [answer[0], answer[4],
                                                     line("* OK [UIDNEXT 9] Predicted next UID")],
                                             from: 17))
        // The words inside a FETCH are not a count, however they read.
        XCTAssertNil(IMAPParser.messageCount(
            after: [line(#"* 12 FETCH (UID 1004 ENVELOPE (NIL "* 20 EXISTS" NIL NIL NIL NIL NIL NIL NIL NIL))"#)],
            from: 17))
    }

    func testSearchAndResponseCode() {
        XCTAssertEqual(IMAPParser.parseSearch([line("* SEARCH 1 2 3 55")]), [1, 2, 3, 55])
        XCTAssertEqual(IMAPParser.parseSearch([line("* SEARCH")]), [])
        XCTAssertEqual(IMAPParser.responseCode("[AUTHENTICATIONFAILED] Invalid credentials"),
                       "AUTHENTICATIONFAILED")
    }

    // MARK: - Fuzz

    func testMutatedGarbageNeverCrashes() {
        let seeds = [
            #"* 1 FETCH (UID 1 ENVELOPE ("d" "s" (("n" NIL "m" "h")) NIL NIL NIL NIL NIL NIL NIL))"#,
            #"* LIST (\Sent) "/" "x""#,
            "* OK [UIDVALIDITY 1] x",
            "* SEARCH 1 2 3",
        ]
        var rng = SystemRandomNumberGenerator()
        for seed in seeds {
            for _ in 0..<400 {
                var chars = Array(seed)
                let cuts = Int.random(in: 1...4, using: &rng)
                for _ in 0..<cuts where !chars.isEmpty {
                    let i = Int.random(in: 0..<chars.count, using: &rng)
                    switch Int.random(in: 0...2, using: &rng) {
                    case 0: chars.remove(at: i)
                    case 1: chars.insert(#"()"\{}"#.randomElement()!, at: i)
                    default: chars[i] = #"()"\ NIL{}0"#.randomElement()!
                    }
                }
                let mutated = line(String(chars))
                _ = IMAPParser.parseFetch([mutated])
                _ = IMAPParser.parseList([mutated])
                _ = IMAPParser.parseSelect([mutated])
                _ = IMAPParser.parseSearch([mutated])
            }
        }
    }
}
