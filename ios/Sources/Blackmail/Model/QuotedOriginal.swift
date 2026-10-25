import Foundation

/// The letter a reply or a forward quotes, carried beside the quote the
/// composer shows him.
///
/// The composer is plain text (D-013), so what he sees under his reply is
/// the original flattened to words. Mail sends the original as it looked,
/// its pictures, links and tables inside the quote. This is what lets the
/// letter's HTML do the same: the original's own markup and where its
/// pictures are, held until Send, and used only if the quote he sends is
/// the quote he was given.
///
/// **The rule, and why it is this one.** `region` is the quote exactly as it
/// went into the body. At Send, if the body still ends with it, byte for
/// byte, he has not touched the quote, and the HTML carries the original's
/// markup. If it does not, he has edited it, cut it short or deleted it, and
/// the HTML renders what he left, as plain text with its addresses linked,
/// the way it did before the original's markup was carried at all. Nothing
/// finer is attempted. Mapping an edit in the flattened words back onto the
/// original's markup cannot be done faithfully (a sentence in the text part
/// may not even exist in the markup), and a near miss would send, in the
/// HTML that most people read, words he had deleted from the letter he saw.
/// So any change at all, even a space, gives up the original's look rather
/// than risk that.
///
/// The pictures are held as pointers to the original's parts and not as
/// bytes, for the reason `DraftAttachment` gives: they are fetched when the
/// letter is built, and usually from the copy the reading pane already has.
/// The markup is the original's own string, shared with the letter on
/// screen rather than copied.
struct QuotedOriginal {

    enum Kind: Equatable {
        case reply, forward
    }

    /// One part of the original its markup can show by `cid:`.
    struct Picture: Equatable {
        /// The id as the original's markup writes it, brackets stripped.
        let contentID: String
        let filename: String
        let mimeType: String
        let size: Int64?
        let messageID: String
        let mailboxID: String
        /// The IMAP section path of the part, as `DraftAttachment` names one.
        let section: String
        /// Gmail's id for the original (X-GM-MSGID), nil where the server
        /// named none, as `DraftAttachment.Source` carries it: the picture
        /// goes only from that letter.
        var letter: UInt64? = nil

        var source: DraftAttachment.Source {
            .messagePart(messageID: messageID, mailboxID: mailboxID, section: section,
                         letter: letter)
        }

        /// True when `attachment` is this same part of the same letter: how
        /// a forward's file row is known to be one of the quote's pictures.
        /// Both are made from the one letter at the one time, so they name
        /// it by the same Gmail id or both by none.
        func isSource(of attachment: DraftAttachment) -> Bool {
            guard case let .messagePart(m, box, s, _) = attachment.source else { return false }
            return m == messageID && box == mailboxID && s == section
        }
    }

    var kind: Kind
    /// The quote as it went into the body: the attribution line or the
    /// forwarded-message header, and the original's words under it, to the
    /// end of the body.
    var region: String
    /// The original's markup, as it came; nil when it was plain text.
    var html: String?
    /// Every part of the original that has a Content-ID. Only those its
    /// markup turns out to show go with the letter.
    var pictures: [Picture]
    /// True when the original was shown only in part
    /// (`Message.isShortened`), or its words were cut to what a quote puts
    /// into the composer (`largestWords`, `largestLines`, B-140; `html` is
    /// then nil): `region` ends with `shortenedEnding`, and the HTML twin
    /// ends the quote with the same line, grey (`AppleMailHTML.letter`).
    /// False for a quote taken back from a saved draft, whose stored markup
    /// carries the line already, and for every other.
    var isShortened = false

    /// What the quote of a letter shown only in part, or cut, ends with,
    /// under the original's words (`Message.quoted(eachLineAfter:)`): a
    /// blank line, then the reading pane's own words for it, "Only the
    /// beginning of this message is shown." A reply's quote marks both
    /// lines with "> ", as it marks every line of the original.
    static let shortenedEnding = "\n\n" + MailText.shortenedNotice

    /// The most of an original's words a quote puts into the composer: 64
    /// KiB of UTF-8, counted as the composer is given them, each line with
    /// its "> " in a reply (`Message.quoted`, B-140). About 11,000 words
    /// of English, thirty pages and more.
    ///
    /// The composer's body is a text view as tall as its words, laid out
    /// and drawn whole as the sheet comes up. A Reply to a letter whose 2
    /// MB HTML part was nearly all words put about 1.7 MB of them there,
    /// and the sheet never came: the keyboard rose with nothing over the
    /// pane and the app took no touch until it was ended. The bound is
    /// ours, for that view; Mail's composer is a web view. As the original's
    /// markup has its ceiling (`AppleMailHTML.largestQuotedMarkup`), its
    /// words have this one.
    static let largestWords = 64 << 10

    /// The most lines of an original's words a quote puts into the
    /// composer, under `largestWords` too: 2,000, about what the bytes
    /// allow of a letter's paragraphs with a blank line between each, so
    /// that a letter of short lines is not quoted ten times as many.
    ///
    /// The composer's text view lays out and draws every line it holds,
    /// some work for each whatever its length: 64 KiB is 1,770 lines of
    /// the round's letter in a reply, but some 16,000 of "> 1", and 32,000
    /// of "a" in a forward. The 2 MiB of the letter that froze the app came
    /// to some 55,000. Chosen, not measured, as the bytes are (B-140's
    /// check times a quote at each).
    static let largestLines = 2_000

    /// What a Reply, Reply All or Forward of `m` quotes, given the region
    /// it has just put into the body. `cut` when that region holds only
    /// the words that fit in `largestWords` (`Message.quoted`, B-140): the
    /// quote is then shortened, as a letter shown only in part is, and the
    /// HTML twin quotes the words he was given, not the original's markup.
    /// The markup has every word of the letter, or of the 2 MB fetched of
    /// it, and under the grey "Only the beginning of this message is
    /// shown." it would say what is not so, and send far more than the
    /// composer showed him.
    init(quoting m: Message, as kind: Kind, region: String, cut: Bool = false) {
        self.kind = kind
        self.region = region
        let markup = cut ? nil : m.htmlBody.flatMap { $0.isEmpty ? nil : $0 }
        html = markup
        pictures = markup == nil ? [] : Self.pictures(of: m)
        isShortened = m.isShortened || cut
    }

    /// `text` cut to the whole lines of it that fit in `limit` bytes of
    /// UTF-8, each line counted with `prefix` bytes more, the "> " a reply
    /// gives every line of its quote, and in `lines` lines, and any white
    /// space left at the end of what is kept taken off; nil when all of it
    /// fits and nothing was left out before it (B-140).
    ///
    /// Cut at the end of the last line that fits, so no line is broken,
    /// unless that comes to less than half the limit: a paragraph longer
    /// than that is cut at its last space that fits, or failing one at its
    /// last whole character, rather than leaving the quote nearly empty. A
    /// text of more than `lines` lines is cut at the end of the last of
    /// them, however few bytes that is. A whole character is Swift's, what
    /// the text view draws as one: a flag, a family joined by zero-width
    /// joiners, a letter and the accent written after it.
    ///
    /// `more` when `text` is itself only the beginning of the words, cut
    /// wherever its maker stopped (`HTMLText.plainText(from:limit:)`): its
    /// last line is not whole, and is cut as one that does not fit, even
    /// when all of it fits.
    ///
    /// Walks no further into `text` than `limit` bytes, so a text of
    /// megabytes costs no more than one of the limit.
    static func cut(_ text: String, within limit: Int, lines: Int = .max, prefix: Int = 0,
                    more: Bool = false) -> String? {
        let utf8 = text.utf8
        var used = prefix
        var ends = 0
        var i = utf8.startIndex
        // The last line end within the limit, and how much was used by it;
        // the last space after it, on the line it is cutting.
        var lineEnd: String.Index?
        var lineEndUsed = 0
        var space: String.Index?
        var tooManyLines = false
        while i < utf8.endIndex {
            let byte = utf8[i]
            // The end of the last line it may keep: the next is one too many.
            if byte == 0x0A, ends + 1 >= lines {
                lineEnd = i
                tooManyLines = true
                break
            }
            // A line end brings the next line's prefix with it.
            let cost = byte == 0x0A ? 1 + prefix : 1
            guard used + cost <= limit else { break }
            used += cost
            if byte == 0x0A {
                ends += 1
                lineEnd = i
                lineEndUsed = used
                space = nil
            } else if byte == 0x20 {
                space = i
            }
            i = utf8.index(after: i)
        }
        guard i < utf8.endIndex || more else { return nil }
        let end: String.Index
        if tooManyLines, let lineEnd {
            end = lineEnd
        } else if let lineEnd, lineEndUsed >= limit / 2 || space == nil {
            end = lineEnd
        } else if let space {
            end = space
        } else if i == utf8.endIndex {
            // All of it fits, one line of it, more to come: as it is.
            end = i
        } else {
            // Back to the start of the character the limit fell in, so that
            // none is broken: not the scalar's start alone, which kept the
            // first half of a flag, a family without its last member and
            // a joiner left hanging, a letter without its accent.
            end = characterStart(at: i, in: text)
        }
        var kept = Substring(text.utf8[..<end])
        while let last = kept.unicodeScalars.last, last.properties.isWhitespace {
            kept.unicodeScalars.removeLast()
        }
        return String(kept)
    }

    /// The start of the character of `text` that `index`, a place in its
    /// UTF-8, falls in; `index` itself when a character starts there.
    /// Walks the characters from the start up to it, which for a cut is no
    /// further than the limit.
    private static func characterStart(at index: String.Index, in text: String) -> String.Index {
        var start = text.startIndex
        while start < text.endIndex {
            let next = text.index(after: start)
            if next > index { break }
            start = next
        }
        return start
    }

    init(kind: Kind, region: String, html: String?, pictures: [Picture],
         isShortened: Bool = false) {
        self.kind = kind
        self.region = region
        self.html = html
        self.pictures = pictures
        self.isShortened = isShortened
    }

    /// The parts of `m` that could be its pictures, first of each id only.
    private static func pictures(of m: Message, among ids: Set<String>? = nil) -> [Picture] {
        var seen = Set<String>()
        return m.attachments.compactMap { a in
            guard let id = a.contentID, ids.map({ $0.contains(id) }) ?? true,
                  seen.insert(id).inserted else { return nil }
            return Picture(contentID: id, filename: a.filename, mimeType: a.mimeType,
                           size: a.size, messageID: m.id, mailboxID: m.mailboxID,
                           section: a.id, letter: m.gmailMessageID)
        }
    }

    /// Whether `body` still ends with the quote exactly as it was given,
    /// starting a line of its own.
    ///
    /// Compared as bytes: a canonically equivalent spelling that is not the
    /// same bytes counts as an edit, which costs at most the original's look
    /// and never sends anything he took out.
    func isIntact(in body: String) -> Bool {
        let quote = Array(region.utf8)
        let text = Array(body.utf8)
        guard !quote.isEmpty, text.count >= quote.count else { return false }
        let start = text.count - quote.count
        guard text[start...].elementsEqual(quote) else { return false }
        return start == 0 || text[start - 1] == UInt8(ascii: "\n")
    }

    // MARK: - Put down as a draft and picked up again

    /// A fingerprint of a quote as it stands in a body: 64-bit FNV-1a of its
    /// bytes, less any newlines at the end, in hex.
    ///
    /// The trailing newlines are left out because a draft's text does not
    /// keep them: the builder ends the part with one line break and the
    /// reader takes that break as the boundary's, so a body that ended in a
    /// newline comes back without it. Blank lines at the very end are not
    /// words, so nothing he could see is lost by ignoring them.
    static func fingerprint(_ region: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        var bytes = Array(region.utf8)
        while bytes.last == UInt8(ascii: "\n") { bytes.removeLast() }
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// The quote a saved draft of this app's was carrying, or nil.
    ///
    /// A draft is stored as the letter it will become and reopened by
    /// reading that letter back, so anything held beside the text is gone
    /// by the time he picks it up again (AppleMailHTML's `layout` gives the
    /// same reason for deriving the plain structure from the text). The
    /// quote survives inside the stored HTML instead: `AppleMailHTML` marks
    /// where it begins, in a draft only, with the fingerprint of the plain
    /// quote it was made for. It is taken back only when the reopened
    /// text's quote has that same fingerprint, so a draft whose text was
    /// changed anywhere else, in Gmail or another client, comes back as
    /// plain text and nothing more, exactly as a draft begun elsewhere does.
    ///
    /// What comes back is the markup as it was stored, already made safe
    /// and with its pictures under this app's names, and those pictures as
    /// parts of the stored draft. The quote of a letter shown only in part
    /// was stored with its grey line, so it comes back not `isShortened`,
    /// and the line is not added a second time.
    static func recovered(from m: Message, body: String) -> QuotedOriginal? {
        guard let html = m.htmlBody,
              let saved = AppleMailHTML.savedQuote(in: html),
              let found = AppleMailHTML.quoteRegion(of: body),
              fingerprint(found.region) == saved.fingerprint else { return nil }
        let shown = QuotedMarkup.contentIDs(shownBy: saved.markup)
        return QuotedOriginal(kind: found.kind, region: found.region, html: saved.markup,
                              pictures: pictures(of: m, among: shown))
    }
}
