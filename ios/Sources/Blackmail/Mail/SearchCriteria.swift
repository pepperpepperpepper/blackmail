import Foundation

/// What "search" means, as an IMAP SEARCH key.
///
/// Pulled out of `IMAPMailRepository` so it could be tested while the
/// repository was behind `#if canImport(Network)`. This is the one string
/// in the app that is BOTH assembled from user input AND concatenated into
/// a protocol command — `IMAPClient.sanitizedCommandText` strips only
/// NUL/CR/LF and deliberately leaves the caller's quoting alone, so the
/// escaping here is the only thing between a typed apostrophe and a
/// malformed command.
///
/// ## Several words, as Mail asks for them (B-105)
///
/// Mail does not send what he typed as one string. It splits it into
/// words, asks for each word in From, To, Cc, Subject or the body, and
/// wants every word: `(OR FROM w (OR SUBJECT w (OR TO w (OR CC w BODY w))))`
/// for each, side by side, which IMAP reads as AND (iOS 18.6's
/// Message.framework). A quoted part is one word, and one-letter words are
/// left out. So "margaret birthday" finds her letter whose subject says
/// birthday by its From and its Subject, each word where it is. One string
/// found it through BODY alone: Gmail matches several words in From, To,
/// Cc and Subject only next to each other, in order, and in BODY, which on
/// Gmail covers the headers too, anywhere and in any order, measured on
/// the test account and written down nowhere.
///
/// A quoted part is asked for as one string, as Mail asks it, which is
/// IMAP's way to ask for a phrase: RFC 3501 matches a string as a
/// substring of the field. Gmail's BODY reads it as all its words,
/// anywhere, so on Gmail “Plan B” finds the letters with the phrase among
/// those with both words, apart or together.
///
/// His iPad types curly quotes and dashes: Smart Punctuation is on by
/// default, and the field leaves it on, as Mail's is not known to turn it
/// off. So “ and ” are quote marks beside ", a dash typed as -- comes as —,
/// and a word typed in single quotes comes as ‘word’. Each is read below.
enum SearchCriteria {

    /// The fields a search looks at.
    ///
    /// **TO and CC are in this list, and their absence was a real hole.**
    /// Search used to match FROM, SUBJECT and BODY only, which means
    /// searching a friend's name found every letter that person SENT him
    /// and none of the ones he sent them — half of a correspondence,
    /// missing, with nothing to indicate it. For someone who searches daily
    /// to find "the letters between me and X", that is the common case
    /// rather than an edge one. Mail matches addressees too.
    ///
    /// Ordered cheapest first only for readability; the server decides how
    /// to evaluate it.
    static let fields = ["FROM", "TO", "CC", "SUBJECT", "BODY"]

    /// No more words than this are asked for; the first ones he typed. A
    /// pasted paragraph is a search of its first twenty words, a line of
    /// about 2 KB, where Gmail took one of 200 groups, 17.6 KB, in 112 ms.
    static let mostWords = 20

    /// The marks that quote a phrase: the keyboard's " and the curly “ and
    /// ” Smart Punctuation makes of it, or a paste brings. They pair in
    /// order, whatever their shape, so “Plan B" is a phrase too.
    static let quoteMarks: Set<Character> = ["\"", "\u{201C}", "\u{201D}"]

    /// The dashes Smart Punctuation makes of a typed -- (—), or a paste
    /// brings: figure, en and em dash and the horizontal bar. Between two
    /// words they part them, as Mail's word rules do. The hyphen of
    /// "e-mail" is not one of them, and stays in its word.
    static let dashes: Set<Character> = ["\u{2012}", "\u{2013}", "\u{2014}", "\u{2015}"]

    /// Single quotes, straight and curly. Inside a word they are its
    /// apostrophe, "O'Brien" and "O’Brien", and stay. Around a word, ‘Plan
    /// B’ as his keyboard types 'Plan B', they are not part of it.
    static let singleQuotes: Set<Character> = ["'", "\u{2018}", "\u{2019}"]

    /// IMAP quoted-string escaping: backslash first, then quote.
    ///
    /// Order matters and is the classic way to get this wrong. Escaping the
    /// quote first would leave the backslash it just inserted to be escaped
    /// again by the second pass, doubling it.
    ///
    /// By Unicode scalar, not by character: a quote with an accent after it
    /// is one character, and a search for the character " passes it by,
    /// which left the quote in the command to end the string early.
    static func escape(_ term: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in term.unicodeScalars {
            if scalar == "\\" || scalar == "\"" { out.append("\\") }
            out.append(scalar)
        }
        return String(out)
    }

    /// The words to ask for, in the order he typed them (B-105).
    ///
    /// 1. The text, trimmed.
    /// 2. Each pair of quote marks, in order, holds one word: what is
    ///    between them, trimmed, its spaces and line breaks one space each.
    ///    A mark left without a partner is read as a space.
    /// 3. The rest is split at white space and at `dashes`, and
    ///    `singleQuotes` are taken off the ends of each word. Gmail splits
    ///    words further itself.
    /// 4. A word of one character, or with no letter or digit in it, is
    ///    left out, as Mail leaves out one-letter words; "Plan B" asks for
    ///    every "plan". If that leaves nothing, the whole text is the one
    ///    word, its quote marks read as spaces, so "a b" is searched as it
    ///    always was; and if that is nothing, there is nothing to ask for.
    /// 5. A word typed twice, in any case, is asked for once.
    /// 6. The first `mostWords`.
    static func words(of query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let characters = Array(trimmed)

        // Each mark at an even place in the order opens, and the next one
        // closes; a last one with none after it is left alone.
        let marks = characters.indices.filter { quoteMarks.contains(characters[$0]) }
        let closing = Dictionary(uniqueKeysWithValues: stride(from: 0, to: marks.count - 1, by: 2)
            .map { (marks[$0], marks[$0 + 1]) })

        var found: [String] = []
        var loose = ""
        func takeLoose() {
            let parted = loose.map { dashes.contains($0) ? " " : $0 }
            for piece in String(parted).split(whereSeparator: { $0.isWhitespace }) {
                found.append(trimmingSingleQuotes(String(piece)))
            }
            loose = ""
        }
        var at = 0
        while at < characters.count {
            if let end = closing[at] {
                takeLoose()
                found.append(collapsed(String(characters[(at + 1)..<end])))
                at = end + 1
            } else {
                loose.append(quoteMarks.contains(characters[at]) ? " " : characters[at])
                at += 1
            }
        }
        takeLoose()

        var kept = found.filter(isAWord)
        if kept.isEmpty {
            let whole = collapsed(String(trimmed.map { quoteMarks.contains($0) ? " " : $0 }))
            guard !whole.isEmpty else { return [] }
            kept = [whole]
        }
        var seen = Set<String>()
        kept = kept.filter { seen.insert($0.lowercased()).inserted }
        return Array(kept.prefix(mostWords))
    }

    /// Two characters or more, a letter or a digit among them.
    private static func isAWord(_ word: String) -> Bool {
        word.count >= 2 && word.contains { $0.isLetter || $0.isNumber }
    }

    /// Trimmed, every run of white space inside one space.
    private static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func trimmingSingleQuotes(_ word: String) -> String {
        var word = Substring(word)
        while let first = word.first, singleQuotes.contains(first) { word = word.dropFirst() }
        while let last = word.last, singleQuotes.contains(last) { word = word.dropLast() }
        return String(word)
    }

    /// The key for the words of `query`, nil when there are none.
    ///
    /// One word is sent as it always was, with no parentheses, byte for
    /// byte: `OR OR OR OR FROM "x" TO "x" CC "x" SUBJECT "x" BODY "x"`.
    /// Several are each that, in parentheses, side by side, which IMAP
    /// reads as AND.
    static func imap(for query: String) -> String? {
        let asked = words(of: query)
        guard let only = asked.first else { return nil }
        guard asked.count > 1 else { return anyField(only) }
        return asked.map { "(\(anyField($0)))" }.joined(separator: " ")
    }

    /// `OR OR OR OR FROM "x" TO "x" CC "x" SUBJECT "x" BODY "x"`.
    ///
    /// RFC 3501's OR is strictly binary and written in prefix form, so N
    /// fields need N-1 leading ORs. Built by folding rather than by hand:
    /// the hand-written version had the right number of ORs for three
    /// fields and would have been silently wrong the moment a fourth was
    /// added — an unbalanced key is a BAD, which this app renders as
    /// "Can't connect to mail server."
    static func anyField(_ word: String) -> String {
        let escaped = escape(word)
        let terms = fields.map { "\($0) \"\(escaped)\"" }
        var key = terms[0]
        for term in terms.dropFirst() {
            key = "OR \(key) \(term)"
        }
        return key
    }
}
