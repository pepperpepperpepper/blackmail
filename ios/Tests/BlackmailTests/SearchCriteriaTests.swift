import XCTest
@testable import Blackmail

/// Tests for the one string in the app that is both assembled from what he
/// typed and concatenated into a protocol command.
///
/// Two classes of failure, both silent. A malformed key is a BAD, which the
/// app renders as "Can't connect to mail server." — indistinguishable from
/// the network being down. A key that is well-formed but looks in the wrong
/// places returns nothing, which is indistinguishable from the letter not
/// existing.
final class SearchCriteriaTests: XCTestCase {

    // MARK: - Where it looks

    func testAddresseesAreSearchedAndNotJustSenders() {
        // The hole this file was written for. Searching a friend's name
        // used to find every letter that person SENT him and none of the
        // ones he sent them — half a correspondence, missing, with nothing
        // on screen to say so.
        let key = SearchCriteria.imap(for: "margaret")!
        XCTAssertTrue(key.contains("TO \"margaret\""), key)
        XCTAssertTrue(key.contains("CC \"margaret\""), key)
        XCTAssertTrue(key.contains("FROM \"margaret\""), key)
        XCTAssertTrue(key.contains("SUBJECT \"margaret\""), key)
        XCTAssertTrue(key.contains("BODY \"margaret\""), key)
    }

    // MARK: - Shape

    func testEveryFieldIsJoinedByExactlyOneFewerORThanThereAreFields() {
        // RFC 3501's OR is strictly binary and prefix-form, so N fields
        // need N-1 leading ORs. Getting this off by one is an unbalanced
        // key, which is a BAD rather than a wrong result.
        let key = SearchCriteria.imap(for: "x")!
        let ors = key.components(separatedBy: "OR ").count - 1
        XCTAssertEqual(ors, SearchCriteria.fields.count - 1)
    }

    func testTheKeyIsBalancedForAnyNumberOfFields() {
        // Walks the key as a parser would: each OR consumes two following
        // keys, and a well-formed expression ends having consumed exactly
        // one.
        let tokens = SearchCriteria.imap(for: "x")!
            .replacingOccurrences(of: " \"x\"", with: "")
            .split(separator: " ").map(String.init)
        var stack = 1
        for token in tokens {
            stack -= 1
            if token == "OR" { stack += 2 }
        }
        XCTAssertEqual(stack, 0, "unbalanced: \(tokens)")
    }

    func testAnEmptyOrBlankQueryIsNotASearchAtAll() {
        // The caller falls back to listing the folder. Returning a key
        // matching every field against "" would ask the server for the
        // whole mailbox down the search path.
        XCTAssertNil(SearchCriteria.imap(for: ""))
        XCTAssertNil(SearchCriteria.imap(for: "   \n\t "))
    }

    func testSurroundingWhitespaceIsTrimmedRatherThanSearchedFor() {
        // The on-screen keyboard adds a trailing space readily, and
        // `BODY " margaret "` matches nothing.
        XCTAssertEqual(SearchCriteria.imap(for: "  margaret  "),
                       SearchCriteria.imap(for: "margaret"))
    }

    // MARK: - Escaping

    func testAQuoteInTheQueryCannotTerminateTheStringEarly() {
        // `IMAPClient.sanitizedCommandText` strips only NUL/CR/LF and
        // deliberately leaves the caller's quoting alone, so this is the
        // only guard there is.
        let key = SearchCriteria.imap(for: "say \"hello\"")!
        XCTAssertTrue(key.contains("\\\"hello\\\""), key)
        // Two delimiters per field and nothing else unescaped.
        for field in SearchCriteria.fields {
            XCTAssertTrue(key.contains("\(field) \"say \\\"hello\\\"\""), key)
        }
    }

    func testABackslashIsEscapedBeforeTheQuoteAndNotAfter() {
        // Order matters and is the classic way to get this wrong: escaping
        // the quote first leaves the backslash it just inserted to be
        // escaped again by the second pass, doubling it.
        XCTAssertEqual(SearchCriteria.escape("a\\b"), "a\\\\b")
        XCTAssertEqual(SearchCriteria.escape("\""), "\\\"")
        XCTAssertEqual(SearchCriteria.escape("\\\""), "\\\\\\\"")
    }

    func testAnApostropheIsLeftAloneBecauseItIsOrdinaryText() {
        // He will search for "O'Brien". Escaping it would search for a
        // name nobody has.
        XCTAssertEqual(SearchCriteria.escape("O'Brien"), "O'Brien")
    }

    func testANonASCIIQuerySurvivesUnmangled() {
        // The client adds CHARSET UTF-8 when it sees non-ASCII, with a
        // no-CHARSET retry. That only works if the term reached it intact.
        let key = SearchCriteria.imap(for: "Müller")!
        XCTAssertTrue(key.contains("FROM \"Müller\""), key)
    }
}
