import Foundation

/// A search with no connection, over the copy kept on the iPad (B-160): the
/// kept rows of the folder, or of every folder kept, and the words kept
/// with the letters he opened or that were fetched ahead. Mail searches an
/// index on the device and so finds with no connection what it has
/// downloaded; here, what is kept.
///
/// As near the server's search as the kept copy allows (`SearchCriteria`):
/// the same words, each wanted, each in From, To, Cc, the subject or the
/// words of the letter, a whole word as Gmail matches it, ignoring case and
/// accents; a phrase in quote marks as it is written, or in the words all
/// its words; the word he is still typing, as the start of a person's name
/// or address too, as the server is asked for the people it may be the
/// start of (B-123). The words of a letter are what is kept of them: its
/// row's few words, and for a letter kept whole the first
/// `KeptLetters.Bounds.words` characters of what the pane would quote. Its
/// files' names and the words in its pictures are not searched, nor are
/// the letters not kept, which is what the line under the list says
/// (`SearchAnswer.someResults`).
///
/// Out of the repository for the reason `SearchCriteria` is: so the suite
/// can run it apart from the wire.
enum KeptSearch {

    /// A letter's words, as kept beside it: what the reading pane would
    /// quote of it, its text, or the words of its HTML, at most
    /// `KeptLetters.Bounds().words` characters of them.
    static func words(of letter: Message) -> String {
        letter.quotableText(within: KeptLetters.Bounds().words).text
    }

    /// The rows of `rows` that hold every word of `query`, newest first.
    /// `words` gives a row's letter's words where they are kept, nil
    /// where not; it is asked only when the row itself does not hold a
    /// word, once a row.
    static func hits(for query: String, in rows: [MessageSummary],
                     words: (MessageSummary) -> String?) -> [MessageSummary] {
        let asked = SearchCriteria.words(of: query).map(fold)
        guard let last = asked.last else { return [] }
        let starting = SearchCriteria.halfWord(of: query) == nil ? nil : last
        return rows.filter { row in
            let people = fold(([row.sender] + (row.to ?? []) + row.cc + row.bcc).joined(separator: "\n"))
            let own = people + "\n" + fold(row.subject) + "\n" + fold(row.preview)
            var body: String??
            return asked.allSatisfy { word in
                if holds(word, in: own) { return true }
                if word == starting, startsAWord(word, in: people) { return true }
                if body == nil { body = .some(words(row).map(fold)) }
                guard let text = body ?? nil else { return false }
                return holds(word, in: text)
                    || (word.contains(" ") && word.split(separator: " ").allSatisfy { holds(String($0), in: text) })
            }
        }.sorted(by: SearchMerge.isOrderedBefore)
    }

    /// `text` without case, accents or the curly apostrophe's shape.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }

    /// Whether `text` holds `word` as a whole word, or a phrase, both
    /// folded: what is on either side of it is not a letter or a digit.
    static func holds(_ word: String, in text: String) -> Bool {
        found(word, in: text, wholeAtEnd: true)
    }

    /// Whether a word of `text` starts with `word`, both folded.
    static func startsAWord(_ word: String, in text: String) -> Bool {
        found(word, in: text, wholeAtEnd: false)
    }

    private static func found(_ word: String, in text: String, wholeAtEnd: Bool) -> Bool {
        guard !word.isEmpty else { return false }
        var from = text.startIndex
        while let at = text.range(of: word, range: from..<text.endIndex) {
            let before = at.lowerBound == text.startIndex ? nil : text[text.index(before: at.lowerBound)]
            let after = at.upperBound == text.endIndex ? nil : text[at.upperBound]
            if !isWordy(before), !wholeAtEnd || !isWordy(after) { return true }
            from = text.index(after: at.lowerBound)
        }
        return false
    }

    private static func isWordy(_ c: Character?) -> Bool {
        guard let c else { return false }
        return c.isLetter || c.isNumber
    }
}
