import Foundation

/// A letter made into the page that is printed (B-110): light, black on
/// white, its header as the reading pane's header draws it, then its body as
/// the pane shows it, in the sender's own colours, with its pictures.
///
/// Mail prints one message this way: its header view, then its body's web
/// view (iOS 18.6's MobileMailUI). The pane itself cannot be printed. Its
/// page is dark (D-010): plain text white on black, HTML under an invert,
/// which prints as it is drawn, white on black, since a build stamped
/// before iOS 16.4 prints backgrounds (seen on the test iPad, 2026-10-23),
/// or white on white with them off. Its header is UIKit, outside the page,
/// and a conversation's stack would print every letter open in it. So the
/// letter is drawn again, here, on a page of its own.
///
/// Pure string work, Foundation only, built away from the main thread as
/// the pane's page is (`PanePage`), so the suite can test it; `LetterPrint`
/// draws it.
enum PrintPage {

    /// The sizes of the pane's header and body, read from `Theme` on the
    /// main thread and handed in, so this file stays free of UIKit.
    struct Style: Sendable {
        let senderPointSize: Int
        let metaPointSize: Int
        let subjectPointSize: Int
        let bodyPointSize: Int
        let lineHeight: Double
    }

    /// The most of a plain letter printed: 128 KiB, about 60 pages at 17
    /// pt. A letter over it is cut, and says so above it.
    static let textLimit = 128 * 1_024
    /// The most of an HTML letter printed: 512 KiB of markup.
    static let htmlLimit = 512 * 1_024

    /// US Letter, in points, and the margin all round. A4 paper takes it
    /// scaled, as AirPrint scales it.
    static let paperWidth: Double = 612
    static let paperHeight: Double = 792
    static let margin: Double = 36

    /// The header's lines, in the pane's order and words
    /// (`MessageHeaderView.configure`): the sender's name, "To: …" or "To:
    /// me", "Cc: …" only when there is one, the subject or "(no subject)",
    /// the date, and a line per file the header lists. The date is written
    /// out in full (`MailFormat.fullTimestamp`), never "Today" or
    /// "Yesterday": the paper is read on another day.
    struct Head: Equatable {
        let sender: String
        let to: String
        let cc: String?
        let subject: String
        let date: String
        let files: [String]
    }

    /// `size` gives a file's size in words, as the pane's header writes it;
    /// a file whose size is not known has its name alone. An inline picture
    /// the body shows has no line, as it has no row in the pane.
    static func head(_ m: Message, size: (Int64) -> String,
                     locale: Locale = .current, timeZone: TimeZone = .current) -> Head {
        Head(sender: MailFormat.displayName(m.sender),
             to: MailFormat.recipientsLine("To", m.to) ?? "To: me",
             cc: MailFormat.recipientsLine("Cc", m.cc),
             subject: jobName(m),
             date: MailFormat.fullTimestamp(m.date, locale: locale, timeZone: timeZone),
             files: m.listedAttachments.map { file in
                 file.size.map { file.filename + " (" + size($0) + ")" } ?? file.filename
             })
    }

    /// The page. Never nil: a letter with nothing in it prints the pane's
    /// words for one, in grey, under its header.
    ///
    /// Light only: `color-scheme` says so, the page is white with black
    /// words, and nothing is inverted, so an HTML letter is in its own
    /// colours and a plain one is black. So the pane's rules for a
    /// signature's white sheet (`SignatureSheet`) are not here: with no
    /// invert to cancel, the sheet prints as written, its words black on
    /// the paper's white, its logo as drawn. Every value of the header is
    /// escaped, and only ever written as text, never in an attribute.
    static func letter(_ m: Message, style: Style, size: (Int64) -> String,
                       locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let head = Self.head(m, size: size, locale: locale, timeZone: timeZone)
        let (body, isHTML) = Self.body(m)
        func line(_ kind: String, _ text: String) -> String {
            "<div class=\"\(kind)\">\(ConversationDocument.escape(text))</div>"
        }
        let rule = "<div class=\"bm-rule\"></div>"
        let lines = [line("bm-sender", head.sender), line("bm-meta", head.to)]
            + [head.cc].compactMap { $0 }.map { line("bm-meta", $0) }
            + [rule, line("bm-subject", head.subject), line("bm-meta", head.date)]
            + head.files.map { line("bm-meta", $0) }
            + [rule]
        // Mail's bars beside quoted text (B-101), the pane's own string:
        // Mail's light colours, which on white are as Mail draws them.
        let bars = isHTML ? "\n" + QuoteBars.css(in: "#bm") : ""
        // The header prints in its own colours (`exact`), its lines grey as
        // in the pane and as Mail's header, which UIKit draws, prints them.
        // With no backgrounds printed (`LetterPrint.load`), WebKit changes
        // any text under 4.5:1 on white, and on iPadOS 16.5 and 18 it
        // lightens one of luminance 0.5 or less: `#8e8e8e` would print
        // `#e2e2e2`, all but gone (`adjustColorForVisibilityOnBackground`,
        // read at WebKit's tags for both). `exact` is inherited, and the
        // header has no background to print. Only the header and the
        // notices (`asDrawn`): the sender's words are left to WebKit.
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="color-scheme" content="light only">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html { -webkit-text-size-adjust: 100%; }
          html, body { margin: 0; padding: 0; background: #fff; color: #000; }
          #bm-head { break-inside: avoid; page-break-inside: avoid; margin: 0 0 17px 0;
                     font-family: -apple-system, sans-serif; -webkit-print-color-adjust: exact; }
          #bm-head div { margin: 0; padding: 0; text-align: left; }
          #bm-head .bm-sender { font: 600 \(style.senderPointSize)px -apple-system, sans-serif;
                                color: #007AFF; }
          #bm-head .bm-meta { font: \(style.metaPointSize)px -apple-system, sans-serif;
                              color: #8e8e8e; margin-top: 2px; }
          #bm-head .bm-subject { font: bold \(style.subjectPointSize)px -apple-system, sans-serif;
                                 color: #000; }
          #bm-head .bm-rule { height: 0; border-top: 0.5px solid #c8c8c8; margin: 14px 0 6px 0; }
          #bm { font: \(style.bodyPointSize)px -apple-system, sans-serif;
                line-height: \(style.lineHeight);
                color: #000; word-wrap: break-word;\(isHTML ? "" : " white-space: pre-wrap;") }
          img, table { max-width: 100% !important; height: auto; }
          a { color: #007AFF; }\(bars)
        </style></head><body><div id="bm-head">\(lines.joined())</div><div id="bm">\(body)</div></body></html>
        """
    }

    /// What goes in `#bm`: the body as the pane draws it (`PanePage.content`),
    /// cut to the limit, with the pane's grey line above a letter cut here
    /// or shortened by the pane; or the pane's words for a letter with
    /// nothing in it. Whether it is the letter's HTML. An HTML letter's
    /// pictures decoded as they are drawn (`decodedAtOnce`); a plain
    /// letter's body has none, every `<` in it written `&lt;`.
    static func body(_ m: Message) -> (html: String, isHTML: Bool) {
        guard !MailText.hasNoVisibleContent(text: m.textBody, html: m.htmlBody) else {
            return (empty, false)
        }
        let known = PanePage.contentIDs(of: m)
        if let html = m.htmlBody {
            let cut = Self.cut(html, to: htmlLimit)
            return (notice(cut != nil || m.isShortened)
                        + decodedAtOnce(PanePage.content(text: nil, html: cut ?? html, known: known)), true)
        }
        let text = m.textBody ?? ""
        let cut = Self.cut(text, to: textLimit)
        return (notice(cut != nil || m.isShortened)
                    + PanePage.content(text: cut ?? text, html: nil, known: known), false)
    }

    /// The pane's words for a letter with nothing in it, grey on paper too.
    static let empty = asDrawn("<p style=\"color: #8e8e8e; margin: 0; white-space: normal;\">"
        + MailText.emptyBodyNotice + "</p>")

    /// The pane's grey line, "Only the beginning…", its own string, grey on
    /// paper too.
    static let shortened = asDrawn(PanePage.shortenedLine)

    private static func notice(_ shown: Bool) -> String {
        shown ? shortened : ""
    }

    /// `html` in a block printed in its own colours, as the header is (see
    /// `letter`), so a notice of ours in `#bm` prints grey rather than all
    /// but white. An inline style, which no sender's markup can match; the
    /// block's margins are its paragraph's, as no border or padding comes
    /// between them.
    private static func asDrawn(_ html: String) -> String {
        "<div style=\"-webkit-print-color-adjust: exact;\">" + html + "</div>"
    }

    /// `html` with `decoding=sync` the first attribute of every `<img>`,
    /// so each picture of the printed page is decoded as it is drawn, and
    /// never left half done when the page is drawn into the PDF. The pane's
    /// page is not touched.
    ///
    /// Seen on the test iPad, 2026-10-23: a kept letter's photo at times
    /// printed as a blank of its shape. WebKit decodes a large picture away
    /// from the drawing, unless its `<img>` says otherwise, when it first
    /// paints the print's page, and `LetterPrint` draws that page as soon
    /// as it has loaded; a picture still being decoded then is drawn as
    /// nothing (`BitmapImage::draw`, iOS 16.5). Synchronous, there is never
    /// one in flight.
    ///
    /// First, so it is the one: of two attributes of one name in a tag,
    /// HTML's parser keeps the first, so a sender's own `decoding="async"`,
    /// later in the tag, is dropped. Unquoted, so an `<img` written inside
    /// a sender's quoted attribute, an alt text, gains two words there and
    /// no quote that would end the value early; and a space after it before
    /// a `/` or `>`, which an unquoted value would otherwise take in. A tag
    /// is `<img` or `<image`, which the parser reads as `<img`, in any
    /// case, ending at a space, `/` or `>`; `<imgx` and `</img>` are not
    /// one. One pass over the bytes, as `InlineImageRewriter.rewrite`.
    static func decodedAtOnce(_ html: String) -> String {
        let bytes = Array(html.utf8)
        var out: [UInt8] = []
        var copied = 0
        var i = 0
        while i < bytes.count {
            guard bytes[i] == 0x3C, let end = endOfImageName(bytes, at: i + 1) else {   // <
                i += 1
                continue
            }
            if out.isEmpty { out.reserveCapacity(bytes.count + bytes.count / 16) }
            out.append(contentsOf: bytes[copied..<end])
            out.append(contentsOf: (isSpace(bytes[end]) ? " decoding=sync" : " decoding=sync ").utf8)
            copied = end
            i = end
        }
        guard copied > 0 else { return html }
        out.append(contentsOf: bytes[copied...])
        return String(decoding: out, as: UTF8.self)
    }

    /// Where the name of an `img` or `image` tag starting at `start` ends,
    /// the byte after it being one that ends a tag's name; nil when there is
    /// no such tag there.
    private static func endOfImageName(_ bytes: [UInt8], at start: Int) -> Int? {
        for name in ["img", "image"] {
            let end = start + name.utf8.count
            guard end < bytes.count, endsName(bytes[end]) else { continue }
            // `| 0x20` lowers an ASCII letter, and no other byte lowers to
            // one of these.
            if zip(bytes[start..<end], name.utf8).allSatisfy({ ($0 | 0x20) == $1 }) { return end }
        }
        return nil
    }

    /// The bytes that end a tag's name: HTML's white space, `/` and `>`.
    private static func endsName(_ c: UInt8) -> Bool {
        isSpace(c) || c == 0x2F || c == 0x3E
    }

    /// HTML's white space: tab, line feed, form feed, carriage return, space.
    private static func isSpace(_ c: UInt8) -> Bool {
        c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D || c == 0x20
    }

    /// The letter in words, for when its page could not be drawn: the
    /// header's lines, a blank line, then its text (an HTML letter's made
    /// words, `HTMLText`), under the same limit and line as the page, or
    /// the pane's words for a letter with none.
    static func words(_ m: Message, size: (Int64) -> String,
                      locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let head = Self.head(m, size: size, locale: locale, timeZone: timeZone)
        let lines = [head.sender, head.to] + [head.cc].compactMap { $0 }
            + [head.subject, head.date] + head.files
        // `quotableText`, but with an HTML letter's markup cut to the
        // page's limit before it is made words, so the work is bounded.
        var text = m.textBody ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let html = m.htmlBody {
            text = HTMLText.plainText(from: cut(html, to: htmlLimit) ?? html)
        }
        text = String(text.drop(while: { $0 == "\n" || $0 == "\r" }))
        let said: String
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            said = MailText.emptyBodyNotice
        } else {
            let cut = Self.cut(text, to: textLimit)
            said = (cut != nil || m.isShortened ? MailText.shortenedNotice + "\n\n" : "") + (cut ?? text)
        }
        return lines.joined(separator: "\n") + "\n\n" + said
    }

    /// The print job's name, which the printer's queue shows: the subject,
    /// or "(no subject)", as the header has it.
    static func jobName(_ m: Message) -> String {
        m.subject.isEmpty ? "(no subject)" : m.subject
    }

    /// `body` cut to at most `limit` bytes of UTF-8, at the last whole
    /// character that fits; nil when it is not over the limit. A character
    /// is never broken: a cut through one would end the page in a
    /// replacement mark, or in half a letter with its accent gone.
    static func cut(_ body: String, to limit: Int) -> String? {
        let utf8 = body.utf8
        guard utf8.count > limit else { return nil }
        // Counted a character at a time, from one to the next, so it is as
        // quick for a string bridged from Foundation as for Swift's own.
        var end = body.startIndex
        var used = 0
        while end < body.endIndex {
            let next = body.index(after: end)
            let size = utf8.distance(from: end, to: next)
            guard used + size <= limit else { break }
            used += size
            end = next
        }
        return String(body[..<end])
    }
}
