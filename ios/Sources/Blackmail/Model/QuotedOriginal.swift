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

    /// What a Reply, Reply All or Forward of `m` quotes, given the region
    /// it has just put into the body.
    init(quoting m: Message, as kind: Kind, region: String) {
        self.kind = kind
        self.region = region
        let markup = m.htmlBody.flatMap { $0.isEmpty ? nil : $0 }
        html = markup
        pictures = markup == nil ? [] : Self.pictures(of: m)
    }

    init(kind: Kind, region: String, html: String?, pictures: [Picture]) {
        self.kind = kind
        self.region = region
        self.html = html
        self.pictures = pictures
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
    /// parts of the stored draft.
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
