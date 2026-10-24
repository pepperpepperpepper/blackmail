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
///
/// ## A word with an accent (B-105)
///
/// Every word is written here as a quoted string, and a quoted string is
/// 7-bit: Gmail answered BAD to "Müller" in one, and to the curly ’ of
/// "don’t", with CHARSET UTF-8 or without, so one such word sank the whole
/// search, "Could not search. Check the connection." The client sends each
/// quoted string with 8-bit text in it as a literal instead, its bytes as
/// they are, and leaves the rest as written here (`IMAPWireCommand`).
///
/// ## A name half typed (B-123)
///
/// Mail's search on the iPad matches the start of words, ignoring case and
/// accents, as he types: "Marg" finds Margaret's letters (iOS 18.6's
/// Message.framework, `= '%@*'cdwt`). Gmail matches whole words only, so
/// "Marg" found nothing here until the last letter of her name was in.
/// The word he is still typing (`halfWord(of:)`) is asked for as before,
/// and beside it, in the same group, From, To or Cc of up to `mostPeople`
/// addresses from the people the app already knows whose name or address
/// starts with it (`RecipientBook.addresses(startingWith:besides:)`). A
/// word with a space after it is a whole word, searched as before; the
/// subject and the body are never searched by the start of a word, which
/// needs an index of the whole mailbox the app does not keep (D-016).
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
    ///
    /// `people`, addresses whose name or address starts with the word he
    /// is still typing, best first, are asked for in From, To or Cc in
    /// that word's group, beside the word, the first `mostPeople` that
    /// `askable` keeps (B-123). Only when there is such a word
    /// (`halfWord(of:)`); otherwise, and with none, the key is byte for
    /// byte what it was.
    static func imap(for query: String, people: [String] = []) -> String? {
        let asked = words(of: query)
        guard let last = asked.last else { return nil }
        let also = halfWord(of: query) == nil ? [] : askable(people, besides: last)
        let groups = asked.dropLast().map { anyField($0) } + [anyField(last, people: also)]
        guard groups.count > 1 else { return groups[0] }
        return groups.map { "(\($0))" }.joined(separator: " ")
    }

    /// `OR OR OR OR FROM "x" TO "x" CC "x" SUBJECT "x" BODY "x"`, and after
    /// it, for each of `people`, `FROM "a" TO "a" CC "a"`, each with one
    /// more OR before the lot (B-123).
    ///
    /// RFC 3501's OR is strictly binary and written in prefix form, so N
    /// fields need N-1 leading ORs. Built by folding rather than by hand:
    /// the hand-written version had the right number of ORs for three
    /// fields and would have been silently wrong the moment a fourth was
    /// added — an unbalanced key is a BAD, which this app renders as
    /// "Can't connect to mail server."
    static func anyField(_ word: String, people: [String] = []) -> String {
        let escaped = escape(word)
        var terms = fields.map { "\($0) \"\(escaped)\"" }
        for person in people {
            let address = escape(person)
            terms += peopleFields.map { "\($0) \"\(address)\"" }
        }
        var key = terms[0]
        for term in terms.dropFirst() {
            key = "OR \(key) \(term)"
        }
        return key
    }

    // MARK: - A name half typed (B-123)

    /// The fields a person's address is asked for in: his letters from
    /// them, and to them, and those they were copied on. Not the subject
    /// or the body, where an address is not how a person is written.
    static let peopleFields = ["FROM", "TO", "CC"]

    /// The fewest letters and digits a word he is still typing has before
    /// the people it may be the start of are asked for. Mail's own words
    /// start at two, but two say too little: "Al", "Ed" and "Jo" are names
    /// on their own, which the word finds whole, and "to", "my" and "in"
    /// are words, while the people of a book of 300 whose name starts with
    /// two letters are many more than `mostPeople`, so the four asked for
    /// would be picked by the book's order and not by what he typed. At
    /// three the word has narrowed, and a three-letter name, "Ann" or
    /// "Sam", is found whole as before, its letters among the hits.
    static let shortestHalfWord = 3

    /// How many people a half-typed word asks for at most, the composer's
    /// suggestions' number (`RecipientBook.suggestionLimit`). Four
    /// addresses of 100 bytes are about 1.3 KB more on the SEARCH line,
    /// where Gmail took 17.6 KB in 112 ms (B-105).
    static let mostPeople = 4

    /// The longest address asked for, in UTF-8 bytes. A person's address
    /// is far shorter; a longer one in the book is passed over, so the
    /// line stays bounded whatever the book holds.
    static let longestAddress = 100

    /// The word he is still typing: the last of `words(of:)`, when nothing
    /// was typed after it, not a space, a closing quote mark or a dash,
    /// and it has `shortestHalfWord` letters or digits. Nil otherwise.
    ///
    /// A word with a space after it is finished, as the keyboard's
    /// suggestions finish a word with one, and is searched whole, as
    /// before. A phrase in quote marks is closed by its last mark. A word
    /// cut off by the twenty-word limit, or asked for already, is not the
    /// last asked unless it is that same word, typed again.
    static func halfWord(of query: String) -> String? {
        guard let typed = query.last, !typed.isWhitespace,
              let last = words(of: query).last,
              !last.contains(where: { $0.isWhitespace }),
              query.lowercased().hasSuffix(last.lowercased()),
              last.filter({ $0.isLetter || $0.isNumber }).count >= shortestHalfWord
        else { return nil }
        return last
    }

    /// The addresses of `people` to ask for: in their order, the first
    /// `mostPeople` that look like an address, none over `longestAddress`
    /// bytes, none with a control character in it, none twice in any
    /// case, and not the word itself, which its group asks for already.
    static func askable(_ people: [String], besides word: String) -> [String] {
        var seen: Set<String> = [word.lowercased()]
        var out: [String] = []
        for person in people where out.count < mostPeople {
            let address = person.trimmingCharacters(in: .whitespacesAndNewlines)
            guard address.contains("@"), address.utf8.count <= longestAddress,
                  !address.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
                  seen.insert(address.lowercased()).inserted
            else { continue }
            out.append(address)
        }
        return out
    }
}
