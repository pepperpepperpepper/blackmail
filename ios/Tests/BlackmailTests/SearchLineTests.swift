import XCTest
@testable import Blackmail

/// A SEARCH answer read off its bytes (B-063), and the ESEARCH answer a date
/// jump asks for instead.
///
/// `IMAPParser.parseSearch` takes a line that is nothing but `* SEARCH` and
/// numbers in one pass over its bytes (`plainSearchNumbers`), and gives any
/// other line to the tokenizer as before. These hold the byte path to the
/// tokenizer's answer on every line it takes, and to taking nothing it
/// should not.
final class SearchLineTests: XCTestCase {

    private func line(_ text: String) -> IMAPResponseLine {
        IMAPResponseLine(text: text, literals: [])
    }

    // MARK: - The byte path

    /// Every line, plain or not: what `parseSearch` gives is what the
    /// tokenizer alone gives. The plain ones are taken on the byte path,
    /// and the rest are not, each for its own reason.
    func testTheBytePathGivesWhatTheTokenizerGivesOnEveryLine() {
        let taken: [String: [UInt32]] = [
            "* SEARCH 2 84 882": [2, 84, 882],
            "* search 2 84 882": [2, 84, 882],
            "* Search 7": [7],
            "* SORT 5 3 9": [5, 3, 9],
            "* sort 1": [1],
            "* SEARCH": [],
            "* SORT": [],
            "* SEARCH 4294967295": [4_294_967_295],
            "* SEARCH 0 007 4294967295": [0, 7, 4_294_967_295],
        ]
        let passedOn = [
            "* SEARCH 4294967296",          // one past UInt32
            "* SEARCH 99999999999",         // eleven digits
            "* SEARCH 00000000001",         // eleven digits, a small number
            "* SEARCH 1  2",                // two spaces
            "* SEARCH 1 2 ",                // a space at the end
            "* SEARCH ",                    // the same, with no number
            "* SEARCH\t1 2",                // a tab
            "* SEARCH 1\t2",
            "* SEARCH 1:5 9",               // a range
            "* SEARCH 2 84 (MODSEQ 7)",     // CONDSTORE's trailer
            "* SEARCH 12a",                 // a letter
            "* SEARCH1 2",                  // no space after the keyword
            "* SEARCHES 2",                 // another word
            "* SORTED 2",
            "*  SEARCH 2",                  // two spaces after the star
            "SEARCH 2",                     // no star
            "* 4231 EXISTS",                // another answer altogether
            "* 3 EXPUNGE",
            "* ESEARCH (TAG \"a012\") UID MIN 4231",
            "* OK [UIDNEXT 900] Predicted next UID.",
            "",
            "*",
            "* ",
        ]
        for (text, numbers) in taken {
            XCTAssertEqual(IMAPParser.plainSearchNumbers(text), numbers, text)
            XCTAssertEqual(IMAPParser.tokenizedSearchNumbers(line(text)), numbers, text)
            XCTAssertEqual(IMAPParser.parseSearch([line(text)]), numbers, text)
        }
        for text in passedOn {
            XCTAssertNil(IMAPParser.plainSearchNumbers(text), text)
            XCTAssertEqual(IMAPParser.parseSearch([line(text)]),
                           IMAPParser.tokenizedSearchNumbers(line(text)), text)
        }
        // The tokenizer's own rules on what it was passed, kept as they were.
        XCTAssertEqual(IMAPParser.parseSearch([line("* SEARCH 1:5 9")]), [1, 2, 3, 4, 5, 9])
        XCTAssertEqual(IMAPParser.parseSearch([line("* SEARCH 2 84 (MODSEQ 7)")]), [2, 84])
        XCTAssertEqual(IMAPParser.parseSearch([line("* SEARCH 4294967296 3")]), [3])
        XCTAssertEqual(IMAPParser.parseSearch([line("* SEARCH 00000000001")]), [1])
        XCTAssertEqual(IMAPParser.parseSearch([line("* SEARCH 1  2")]), [1, 2])
        XCTAssertEqual(IMAPParser.parseSearch([line("* 4231 EXISTS")]), [])
        XCTAssertEqual(IMAPParser.parseSearch([line("* SEARCHES 2")]), [])
    }

    /// The untagged lines of one answer together, as `IMAPClient` hands
    /// them over: the EXISTS that rode on it adds nothing, and lines taken
    /// either way keep their order.
    func testAnAnswersLinesTogetherKeepTheirOrderAndOnlyTheirNumbers() {
        let lines = ["* 4231 EXISTS", "* SEARCH 10 11 12", "* SEARCH 1:3", "* 2 EXPUNGE",
                     "* SEARCH 40 (MODSEQ 917)", "* SEARCH 50 51"].map(line)
        XCTAssertEqual(IMAPParser.parseSearch(lines), [10, 11, 12, 1, 2, 3, 40, 50, 51])
        XCTAssertEqual(IMAPParser.parseSearch(lines),
                       lines.flatMap(IMAPParser.tokenizedSearchNumbers))
    }

    /// A line with a literal in it is never taken on the byte path: its
    /// text holds a marker where the bytes were, and only the tokenizer
    /// knows what to do with that.
    func testALineWithALiteralGoesToTheTokenizer() {
        let marked = IMAPResponseLine(text: "* SEARCH 4 \u{0}0\u{0}",
                                      literals: [Data("x".utf8)])
        XCTAssertEqual(IMAPParser.parseSearch([marked]), IMAPParser.tokenizedSearchNumbers(marked))
        XCTAssertEqual(IMAPParser.parseSearch([marked]), [4])
    }

    /// His All Mail's `UID SEARCH ALL`: 400,000 UIDs on one line, near
    /// 3 MB. Read right, and quickly; the tokenizer took seconds over it in
    /// the debug build the suite runs.
    func testFourHundredThousandUIDsAreReadQuickly() {
        var bytes = [UInt8]("* SEARCH".utf8)
        bytes.reserveCapacity(3_400_000)
        var expected: [UInt32] = []
        expected.reserveCapacity(400_000)
        var uid: UInt32 = 2_100_000
        for i in 0..<400_000 {
            uid += UInt32(1 + i % 5)
            expected.append(uid)
            bytes.append(0x20)
            bytes.append(contentsOf: String(uid).utf8)
        }
        let answer = line(String(decoding: bytes, as: UTF8.self))

        let started = ContinuousClock.now
        let found = IMAPParser.parseSearch([answer])
        let took = ContinuousClock.now - started

        XCTAssertEqual(found.count, 400_000)
        XCTAssertTrue(found == expected, "the numbers read are not the numbers sent")
        XCTAssertLessThan(took, .milliseconds(500), "\(took)")
    }

    // MARK: - ESEARCH's MIN

    /// `UID SEARCH RETURN (MIN)`'s answer (RFC 4731): the lowest UID, from
    /// MIN or else from ALL's set; none only for an answer with no items at
    /// all or a count of none; and nil, to be asked again plainly, for
    /// anything else: items that do not say the lowest, a malformed one,
    /// an answer that does not say it is of UIDs.
    func testTheLowestUIDIsReadFromAnESEARCHAnswer() {
        let read: [(String, [UInt32]?)] = [
            ("* ESEARCH (TAG \"a012\") UID MIN 4231", [4231]),
            ("* esearch (tag \"a012\") uid min 9", [9]),
            ("* ESEARCH UID MIN 7", [7]),
            ("* ESEARCH (TAG \"a012\") UID MAX 900 MIN 3", [3]),
            ("* ESEARCH (TAG \"a012\") UID COUNT 12 MIN 31 MAX 900", [31]),
            ("* ESEARCH (TAG \"a012\") UID MIN 4294967295", [4_294_967_295]),
            // ALL's set, its lowest, however it is written.
            ("* ESEARCH (TAG \"a012\") UID ALL 3:9", [3]),
            ("* ESEARCH (TAG \"a012\") UID ALL 12,9:3,40", [3]),
            ("* ESEARCH (TAG \"a012\") UID ALL 17", [17]),
            ("* ESEARCH (TAG \"a012\") UID COUNT 3 ALL 8,5:6", [5]),
            ("* ESEARCH (TAG \"a012\") UID MIN 2 ALL 3:9", [2]),
            // Nothing matched.
            ("* ESEARCH (TAG \"a012\") UID", []),
            ("* ESEARCH UID", []),
            ("* ESEARCH (TAG \"a012\") UID COUNT 0", []),
            // Something, but not the lowest.
            ("* ESEARCH (TAG \"a012\") UID COUNT 37", nil),
            ("* ESEARCH (TAG \"a012\") UID COUNT 12 MAX 900", nil),
            ("* ESEARCH (TAG \"a012\") UID MAX 900", nil),
            ("* ESEARCH (TAG \"a012\") UID MODSEQ 917162500", nil),
            // Malformed.
            ("* ESEARCH (TAG \"a012\") UID MIN", nil),
            ("* ESEARCH (TAG \"a012\") UID COUNT", nil),
            ("* ESEARCH (TAG \"a012\") UID MIN 0", nil),
            ("* ESEARCH (TAG \"a012\") UID MIN +5", nil),
            ("* ESEARCH (TAG \"a012\") UID MIN 4294967296", nil),
            ("* ESEARCH (TAG \"a012\") UID MIN x", nil),
            ("* ESEARCH (TAG \"a012\") UID COUNT x", nil),
            ("* ESEARCH (TAG \"a012\") UID COUNT 4 MIN x", nil),
            ("* ESEARCH (TAG \"a012\") UID ALL 3:*", nil),
            ("* ESEARCH (TAG \"a012\") UID ALL 3:", nil),
            ("* ESEARCH (TAG \"a012\") UID ALL 3,,9", nil),
            ("* ESEARCH (TAG \"a012\") UID ALL 1:2:3", nil),
            ("* ESEARCH (TAG \"a012\") UID ALL 0:9", nil),
            ("* ESEARCH (TAG \"a012\") UID (MIN) 4", nil),
            // Not of UIDs, or not an ESEARCH answer.
            ("* ESEARCH (TAG \"a012\") MIN 4", nil),            // sequence numbers
            ("* ESEARCH (TAG \"a012\")", nil),
            ("* SEARCH 4 5 6", nil),
            ("* 4231 EXISTS", nil),
        ]
        for (text, lowest) in read {
            XCTAssertEqual(IMAPParser.parseSearchMinimum([line(text)]), lowest, text)
        }
        XCTAssertNil(IMAPParser.parseSearchMinimum([]))
        // With other lines about it, as an answer has.
        XCTAssertEqual(IMAPParser.parseSearchMinimum(
            [line("* 12 EXISTS"), line("* ESEARCH (TAG \"a5\") UID MIN 31"), line("* 1 RECENT")]),
                       [31])
        // And the plain parser never reads one as a SEARCH that found
        // nothing, or as anything: it is the client's to read, or to ask
        // again for.
        XCTAssertEqual(IMAPParser.parseSearch([line("* ESEARCH (TAG \"a012\") UID MIN 4231")]), [])
    }

    /// A plain SEARCH answer to `RETURN (MIN)`, from a server that took no
    /// notice of RETURN: its numbers, none for `* SEARCH` alone, and nil
    /// only when there is no SEARCH line at all, so nothing found is told
    /// from nothing said.
    func testAPlainSEARCHAnswerIsToldFromNone() {
        let read: [([String], [UInt32]?)] = [
            (["* SEARCH 9 4 6"], [9, 4, 6]),
            (["* search 9"], [9]),
            (["* SEARCH"], []),
            (["* 12 EXISTS", "* SEARCH 31 40", "* 1 RECENT"], [31, 40]),
            (["* SEARCH 4", "* SEARCH 2"], [4, 2]),
            ([], nil),
            (["* 12 EXISTS"], nil),
            (["* ESEARCH (TAG \"a012\") UID MIN 4"], nil),
            (["* SEARCHES 4"], nil),
            (["* SORT 4 5"], nil),
        ]
        for (lines, numbers) in read {
            XCTAssertEqual(IMAPParser.plainSearchAnswer(lines.map(line)), numbers, "\(lines)")
        }
    }
}
