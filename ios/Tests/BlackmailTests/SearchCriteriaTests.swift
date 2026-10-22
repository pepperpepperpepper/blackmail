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
        // only guard there is. A typed quote is a quote mark since B-105,
        // and never reaches a word; one with an accent after it is one
        // character, not a mark, and reaches it whole.
        let key = SearchCriteria.imap(for: "say \"\u{301}hello")!
        XCTAssertEqual(SearchCriteria.words(of: "say \"\u{301}hello"), ["say", "\"\u{301}hello"])
        for field in SearchCriteria.fields {
            XCTAssertTrue(key.contains("\(field) \"\\\"\u{301}hello\""), key)
        }
        XCTAssertEqual(unescapedQuotes(in: key), 2 * 2 * SearchCriteria.fields.count, key)
    }

    func testABackslashIsEscapedBeforeTheQuoteAndNotAfter() {
        // Order matters and is the classic way to get this wrong: escaping
        // the quote first leaves the backslash it just inserted to be
        // escaped again by the second pass, doubling it.
        XCTAssertEqual(SearchCriteria.escape("a\\b"), "a\\\\b")
        XCTAssertEqual(SearchCriteria.escape("\""), "\\\"")
        XCTAssertEqual(SearchCriteria.escape("\\\""), "\\\\\\\"")
    }

    /// A quote or a backslash with an accent after it is one character,
    /// and a search for the character passed it by: the quote went into
    /// the command as it was, and ended the string early.
    func testAQuoteOrBackslashWithAnAccentIsEscapedToo() {
        XCTAssertEqual(SearchCriteria.escape("a\"\u{301}b"), "a\\\"\u{301}b")
        XCTAssertEqual(SearchCriteria.escape("a\\\u{301}b"), "a\\\\\u{301}b")
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
        // And among several words, each one whole.
        XCTAssertEqual(SearchCriteria.words(of: "Müller Grüße 東京都 Ångström"),
                       ["Müller", "Grüße", "東京都", "Ångström"])
        let several = SearchCriteria.imap(for: "Müller Grüße")!
        XCTAssertTrue(several.contains("BODY \"Grüße\""), several)
    }

    // MARK: - Several words, as Mail asks for them (B-105)

    /// Two words are two groups, each in any of the five fields, side by
    /// side, which IMAP reads as AND: a name only in From and a word only
    /// in the body find the letter, in either order.
    func testTwoWordsAreTwoGroupsAndedTogether() throws {
        let key = try XCTUnwrap(SearchCriteria.imap(for: "ab cd"))
        XCTAssertEqual(key, "(OR OR OR OR FROM \"ab\" TO \"ab\" CC \"ab\" SUBJECT \"ab\" BODY \"ab\") "
                          + "(OR OR OR OR FROM \"cd\" TO \"cd\" CC \"cd\" SUBJECT \"cd\" BODY \"cd\")")
        let keys = try XCTUnwrap(parse(key), key)
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys.map(words), [["ab"], ["cd"]])
    }

    /// One word goes byte for byte as it always did: no parentheses, the
    /// same five fields in the same order.
    func testOneWordIsSentByteForByteAsBefore() {
        XCTAssertEqual(SearchCriteria.imap(for: "margaret"),
                       "OR OR OR OR FROM \"margaret\" TO \"margaret\" CC \"margaret\" "
                           + "SUBJECT \"margaret\" BODY \"margaret\"")
        XCTAssertEqual(SearchCriteria.imap(for: "  e-mail\n"),
                       "OR OR OR OR FROM \"e-mail\" TO \"e-mail\" CC \"e-mail\" "
                           + "SUBJECT \"e-mail\" BODY \"e-mail\"")
        // One word left of several is sent the same way, parentheses and all
        // left off.
        XCTAssertEqual(SearchCriteria.imap(for: "Plan B"), SearchCriteria.imap(for: "Plan"))
        XCTAssertEqual(SearchCriteria.imap(for: "“Plan B”"),
                       "OR OR OR OR FROM \"Plan B\" TO \"Plan B\" CC \"Plan B\" "
                           + "SUBJECT \"Plan B\" BODY \"Plan B\"")
    }

    /// A quoted phrase is one word, without its marks, typed with the
    /// keyboard's straight quotes, with the curly ones Smart Punctuation
    /// makes of them, or one of each.
    func testAQuotedPhraseIsOneWordWhateverItsMarks() {
        for typed in ["\"Plan B\"", "“Plan B”", "“Plan B\"", "\"Plan B”", "”Plan B“"] {
            XCTAssertEqual(SearchCriteria.words(of: typed), ["Plan B"], typed)
            XCTAssertEqual(SearchCriteria.words(of: "margaret \(typed) birthday"),
                           ["margaret", "Plan B", "birthday"], typed)
        }
        // Two phrases, and the marks pair in order.
        XCTAssertEqual(SearchCriteria.words(of: "“Plan B” and “the garden”"),
                       ["Plan B", "and", "the garden"])
        // Its own spaces and line breaks one space each, so the line sent
        // has no break in it.
        XCTAssertEqual(SearchCriteria.words(of: "“ Plan \n\t B ”"), ["Plan B"])
    }

    /// A mark with no partner is read as a space: “Plan B as typed before
    /// the closing mark is Plan and B, and B is left out.
    func testAnUnpairedMarkIsASpace() {
        XCTAssertEqual(SearchCriteria.words(of: "“Plan B"), ["Plan"])
        XCTAssertEqual(SearchCriteria.words(of: "Plan” garden"), ["Plan", "garden"])
        XCTAssertEqual(SearchCriteria.words(of: "“Plan B” “garden"), ["Plan B", "garden"])
    }

    /// An apostrophe stays in its word, straight or curly, and is not
    /// escaped. Single quotes around a word are not part of it: his
    /// keyboard types 'Plan B' as ‘Plan B’.
    func testAnApostropheStaysInItsWordAndSingleQuotesAroundOneGo() {
        XCTAssertEqual(SearchCriteria.words(of: "O'Brien"), ["O'Brien"])
        XCTAssertEqual(SearchCriteria.words(of: "O’Brien letter"), ["O’Brien", "letter"])
        XCTAssertTrue(SearchCriteria.imap(for: "O'Brien")!.contains("FROM \"O'Brien\""))
        XCTAssertTrue(SearchCriteria.imap(for: "O’Brien x")!.contains("BODY \"O’Brien\""))
        XCTAssertEqual(SearchCriteria.words(of: "‘Plan B’"), ["Plan"])
        XCTAssertEqual(SearchCriteria.words(of: "'Plan B'"), ["Plan"])
        XCTAssertEqual(SearchCriteria.words(of: "the Smiths’ garden"), ["the", "Smiths", "garden"])
    }

    /// The dashes Smart Punctuation makes of -- part two words, as Mail's
    /// word rules do; a dash alone is no word. The hyphen stays in its word.
    func testSmartDashesPartWordsAndTheHyphenStays() {
        XCTAssertEqual(SearchCriteria.words(of: "Plan—B"), ["Plan"])
        XCTAssertEqual(SearchCriteria.words(of: "garden—party"), ["garden", "party"])
        XCTAssertEqual(SearchCriteria.words(of: "garden – party ‒ tea ― cake"),
                       ["garden", "party", "tea", "cake"])
        XCTAssertEqual(SearchCriteria.words(of: "garden — party"), ["garden", "party"])
        XCTAssertEqual(SearchCriteria.words(of: "e-mail re-sent"), ["e-mail", "re-sent"])
        // Inside a phrase it is what he quoted.
        XCTAssertEqual(SearchCriteria.words(of: "“garden—party”"), ["garden—party"])
    }

    /// One-letter words are left out, as Mail leaves them out, and so is
    /// a word with no letter or digit; a search of nothing else searches
    /// its whole text, as before.
    func testOneLetterWordsAreLeftOutUnlessThereIsNothingElse() {
        XCTAssertEqual(SearchCriteria.words(of: "Plan B"), ["Plan"])
        XCTAssertEqual(SearchCriteria.words(of: "a letter from J Smith"),
                       ["letter", "from", "Smith"])
        XCTAssertEqual(SearchCriteria.words(of: "garden -- && ... party"), ["garden", "party"])
        XCTAssertEqual(SearchCriteria.words(of: "“B”"), ["B"])
        XCTAssertEqual(SearchCriteria.words(of: "a b"), ["a b"])
        XCTAssertEqual(SearchCriteria.imap(for: "a b"),
                       "OR OR OR OR FROM \"a b\" TO \"a b\" CC \"a b\" SUBJECT \"a b\" BODY \"a b\"")
        XCTAssertEqual(SearchCriteria.words(of: "“a” b"), ["a b"])
        XCTAssertEqual(SearchCriteria.words(of: "x"), ["x"])
        XCTAssertEqual(SearchCriteria.words(of: "—"), ["—"])
        XCTAssertEqual(SearchCriteria.words(of: "1 2"), ["1 2"])
        XCTAssertEqual(SearchCriteria.words(of: "B 52"), ["52"])
        // Quote marks and nothing else: nothing to ask for, and nothing found.
        XCTAssertEqual(SearchCriteria.words(of: "“”"), [])
        XCTAssertNil(SearchCriteria.imap(for: " \" \" "))
    }

    /// A word typed twice, in any case, is asked for once, where he first
    /// typed it.
    func testARepeatedWordIsAskedForOnce() {
        XCTAssertEqual(SearchCriteria.words(of: "Plan plan PLAN garden Plan"), ["Plan", "garden"])
        XCTAssertEqual(SearchCriteria.words(of: "“Plan B” “plan b” garden"), ["Plan B", "garden"])
        XCTAssertEqual(SearchCriteria.words(of: "Müller MÜLLER"), ["Müller"])
    }

    /// The first twenty, in the order he typed them.
    func testNoMoreThanTheFirstTwentyWords() throws {
        let typed = (1...30).map { "word\($0)" }
        XCTAssertEqual(SearchCriteria.words(of: typed.joined(separator: " ")),
                       Array(typed.prefix(20)))
        XCTAssertEqual(SearchCriteria.mostWords, 20)
        let key = try XCTUnwrap(SearchCriteria.imap(for: typed.joined(separator: " ")))
        XCTAssertEqual(try XCTUnwrap(parse(key)).count, 20)
    }

    /// Every group is balanced, and so is the whole: a parenthesis closed
    /// for each opened, four ORs in each group, each OR given two keys, and
    /// every field given the group's one word.
    func testEveryGroupAndTheWholeKeyAreBalanced() throws {
        for typed in ["ab cd", "margaret “Plan B” birthday", "O'Brien \\ e-mail Müller x",
                      (1...25).map { "w\($0)" }.joined(separator: " ")] {
            let key = try XCTUnwrap(SearchCriteria.imap(for: typed), typed)
            let asked = SearchCriteria.words(of: typed)
            let keys = try XCTUnwrap(parse(key), key)
            XCTAssertEqual(keys.count, asked.count, typed)
            XCTAssertEqual(keys.map(words), asked.map { [$0] }, typed)
            for group in keys {
                guard case let .group(inside) = group, inside.count == 1 else {
                    return XCTFail("not one key in parentheses: \(key)")
                }
                XCTAssertEqual(ors(inside[0]), SearchCriteria.fields.count - 1, key)
                XCTAssertEqual(fields(inside[0]), SearchCriteria.fields, key)
            }
            XCTAssertEqual(key.filter { $0 == "(" }.count, asked.count)
            XCTAssertEqual(key.filter { $0 == ")" }.count, asked.count)
        }
    }

    /// Each word escaped on its own: a backslash in one is doubled in each
    /// of its five strings, and nothing else in the line ends a string.
    func testEachWordIsEscapedOnItsOwn() throws {
        let key = try XCTUnwrap(SearchCriteria.imap(for: "C:\\Letters garden"))
        XCTAssertTrue(key.contains("(OR OR OR OR FROM \"C:\\\\Letters\" TO \"C:\\\\Letters\""), key)
        XCTAssertEqual(try XCTUnwrap(parse(key)).map(words), [["C:\\Letters"], ["garden"]])
        XCTAssertEqual(unescapedQuotes(in: key), 2 * 2 * SearchCriteria.fields.count)
        // A quote mark never reaches a word: paired it quotes, alone it is
        // a space, and in the whole text searched as before it is a space.
        for typed in ["say \"hello\"", "say \"hello", "\"a\" \"b\"", "a\"b"] {
            for word in SearchCriteria.words(of: typed) {
                XCTAssertFalse(word.unicodeScalars.contains("\""), typed)
            }
        }
    }

    /// A pasted paragraph of 300 words is a search of its first twenty, a
    /// line well inside what Gmail took (17.6 KB).
    func testAPastedParagraphStaysShort() throws {
        let sentence = "Dear Margaret, thank you for the photographs of the garden party last "
            + "Sunday. The roses were splendid and everyone asked after you; we must arrange "
            + "another afternoon before the autumn comes, perhaps at the cottage near the river. "
        var paragraph = ""
        while paragraph.split(separator: " ").count < 300 { paragraph += sentence }
        XCTAssertGreaterThanOrEqual(paragraph.split(separator: " ").count, 300)
        let key = try XCTUnwrap(SearchCriteria.imap(for: paragraph))
        XCTAssertEqual(SearchCriteria.words(of: paragraph).count, SearchCriteria.mostWords)
        XCTAssertLessThan(key.utf8.count, 2_048, "\(key.utf8.count) bytes")
        XCTAssertNotNil(parse(key))
    }

    // MARK: - Reading a key back

    /// A search key as the server reads one.
    private indirect enum Key: Equatable {
        case field(String, String)
        case or(Key, Key)
        case group([Key])
    }

    /// `key` read as RFC 3501's grammar has it, the keys side by side; nil
    /// if it is not well formed: an OR short of two keys, a parenthesis not
    /// closed, a string not ended, or anything left over.
    private func parse(_ key: String) -> [Key]? {
        let text = Array(key.unicodeScalars)
        var at = 0
        func spaces() { while at < text.count, text[at] == " " { at += 1 } }
        func atom() -> String? {
            var out = String.UnicodeScalarView()
            while at < text.count, text[at] != " ", text[at] != "(", text[at] != ")" {
                out.append(text[at]); at += 1
            }
            return out.isEmpty ? nil : String(out)
        }
        func quoted() -> String? {
            guard at < text.count, text[at] == "\"" else { return nil }
            at += 1
            var out = String.UnicodeScalarView()
            while at < text.count {
                let scalar = text[at]
                at += 1
                if scalar == "\"" { return String(out) }
                if scalar == "\\" {
                    guard at < text.count, text[at] == "\\" || text[at] == "\"" else { return nil }
                    out.append(text[at]); at += 1
                } else {
                    out.append(scalar)
                }
            }
            return nil
        }
        func one() -> Key? {
            spaces()
            guard at < text.count else { return nil }
            if text[at] == "(" {
                at += 1
                var inside: [Key] = []
                while true {
                    spaces()
                    if at < text.count, text[at] == ")" { at += 1; break }
                    guard let next = one() else { return nil }
                    inside.append(next)
                }
                return inside.isEmpty ? nil : .group(inside)
            }
            guard let word = atom() else { return nil }
            if word == "OR" {
                guard let left = one(), let right = one() else { return nil }
                return .or(left, right)
            }
            guard SearchCriteria.fields.contains(word), at < text.count, text[at] == " " else {
                return nil
            }
            at += 1
            return quoted().map { .field(word, $0) }
        }
        var keys: [Key] = []
        while true {
            spaces()
            if at == text.count { return keys }
            guard let next = one() else { return nil }
            keys.append(next)
        }
    }

    /// The words a key asks for, once each.
    private func words(_ key: Key) -> [String] {
        switch key {
        case let .field(_, word): return [word]
        case let .or(left, right):
            return (words(left) + words(right)).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        case let .group(inside):
            return inside.flatMap(words).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        }
    }

    private func ors(_ key: Key) -> Int {
        switch key {
        case .field: return 0
        case let .or(left, right): return 1 + ors(left) + ors(right)
        case let .group(inside): return inside.map(ors).reduce(0, +)
        }
    }

    private func fields(_ key: Key) -> [String] {
        switch key {
        case let .field(name, _): return [name]
        case let .or(left, right): return fields(left) + fields(right)
        case let .group(inside): return inside.flatMap(fields)
        }
    }

    /// The quotes in `key` that open or close a string: every one not
    /// escaped by a backslash before it.
    private func unescapedQuotes(in key: String) -> Int {
        var count = 0
        var escaped = false
        for scalar in key.unicodeScalars {
            if escaped { escaped = false; continue }
            if scalar == "\\" { escaped = true } else if scalar == "\"" { count += 1 }
        }
        return count
    }
}
