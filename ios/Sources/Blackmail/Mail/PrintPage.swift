import Foundation

/// A letter made into the page that is printed (B-110): light, black on
/// white, its header as Mail prints it (B-172), then its body as the pane
/// shows it, in the sender's own colours, with its pictures and its files
/// (B-170).
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
/// Since B-169 the pane inverts only the letters Mail turns to the dark,
/// draws a letter with a picture from the web, or a light scheme only, on
/// its own white, and one that declares the dark in its own colours, its
/// style for the dark with it (`LetterScheme`). The page printed is as it
/// was for all three: white paper, the sender's colours, no style brought
/// back from the letter's head, as Mail prints. A picture behind a
/// letter's words, its body's `background`, is given to `#bm` by the rule
/// the pane draws it with (`PanePage.backdrop`), and prints as no
/// background does: not at all, and not as a file after the words either.
///
/// Pure string work, Foundation only, built away from the main thread as
/// the pane's page is (`PanePage`), so the suite can test it; `LetterPrint`
/// draws it.
enum PrintPage {

    /// The sizes of the pane's header and body, read from `Theme` on the
    /// main thread and handed in, so this file stays free of UIKit. Since
    /// the paper's header is Mail's (B-172), its lines are all at
    /// `metaPointSize`, the pane's header lines' size; the sender's and the
    /// subject's sizes are handed in as before and not used on paper.
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

    /// The header's lines, as Mail prints them (B-172): "From:",
    /// "Subject:", "Date:" and "To:", in that order, each label grey and
    /// set to the right, then the name in black and the address after it
    /// in grey; and a line per file of the letter, which the page draws in
    /// its body, as the pane does, and not in the header, and the letter
    /// in words lists after its text (B-170).
    ///
    /// Seen on the test iPad, Mail 16.5.1, 2026-10-27 (round r6-i-compare,
    /// C-17b), in the print's preview of a plain letter: "From: Sam Plain
    /// sam.b147@example.net", "Subject: R6 B-147 plain rm", "Date: Oct 27,
    /// 2026 at 1:25:45 PM", "To: Carlo" and his address, then a rule.
    /// Until B-172 the paper had the reading pane's header
    /// (`MessageHeaderView.configure`): the sender's name in blue, "To:"
    /// and names alone, a rule, the subject in bold, the date in the
    /// pane's long form, a rule.
    ///
    /// Not seen, and made as the seen lines are: "Cc:", after "To:", only
    /// for a letter with one, as Mail's header names it; several people on
    /// a line, each a name and its address, a comma between; a person with
    /// no name, the address alone in black; a letter with nobody in To, no
    /// "To:" line, where the paper had "To: me". "(no subject)" for a
    /// letter with none, as the pane says. The date is Mail's
    /// (`MailFormat.printedTimestamp`), never "Today" or "Yesterday": the
    /// paper is read on another day. It is when the letter arrived, its
    /// Date where that is not known (`Message.headerDate`), as Mail 16.5.1
    /// prints it: seen on the test iPad on 2026-10-28 (round r6-l-fix,
    /// B-178), "Date: Oct 28, 2026 at 2:15:14 PM" on a letter dated 1
    /// March 2024 that arrived then.
    struct Head: Equatable {
        /// One person of a line: the name, and the address after it, nil
        /// when the entry is an address alone.
        struct Person: Equatable {
            let name: String
            let address: String?
        }

        /// A line of the header: its label, and the people or the words
        /// after it.
        struct Line: Equatable {
            let label: String
            let people: [Person]
            let text: String?
        }

        let from: Person
        let subject: String
        let date: String
        let to: [Person]
        let cc: [Person]
        let files: [String]

        /// The lines in Mail's order, a person's line only with someone in
        /// it.
        var lines: [Line] {
            [Line(label: "From:", people: [from], text: nil),
             Line(label: "Subject:", people: [], text: subject),
             Line(label: "Date:", people: [], text: date)]
                + [("To:", to), ("Cc:", cc)].filter { !$0.1.isEmpty }
                    .map { Line(label: $0.0, people: $0.1, text: nil) }
        }
    }

    /// The person an entry of a header names (`MailFormat.recipientName`),
    /// with its address when it has a name of its own.
    static func person(_ entry: String) -> Head.Person {
        let entry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = MailFormat.recipientName(entry)
        let address = entry.contains("<") ? MailFormat.bareAddress(entry) : ""
        return Head.Person(name: name, address: address.isEmpty || address == name ? nil : address)
    }

    /// `size` gives a file's size in words, as a file's tile writes it; a
    /// file whose size is not known has its name alone. An inline picture
    /// the body shows has no line, as it is no file in the pane.
    static func head(_ m: Message, size: (Int64) -> String,
                     locale: Locale = .current, timeZone: TimeZone = .current) -> Head {
        Head(from: person(m.sender),
             subject: jobName(m),
             date: MailFormat.printedTimestamp(m.headerDate, locale: locale, timeZone: timeZone),
             to: m.to.map(person),
             cc: m.cc.map(person),
             files: m.listedAttachments.map { file in
                 file.size.map { file.filename + " (" + size($0) + ")" } ?? file.filename
             })
    }

    /// A line of the header in words: its label, then each person's name
    /// and address, a space between, a comma between people.
    static func inWords(_ line: Head.Line) -> String {
        let said = line.text ?? line.people
            .map { person in [person.name, person.address].compactMap { $0 }.joined(separator: " ") }
            .joined(separator: ", ")
        return line.label + " " + said
    }

    /// The page. Never nil: a letter the pane says has no text
    /// (`PanePage.isEmpty`) prints the pane's words for one, in grey, under
    /// its header.
    ///
    /// Light only: `color-scheme` says so, the page is white with black
    /// words, and nothing is inverted, so an HTML letter is in its own
    /// colours and a plain one is black. Its files are in its body, where
    /// the pane draws them, its pictures at their size and every other
    /// file as its tile in Mail's light colours with no "Tap to Download"
    /// (`BodyFiles`, B-170): Mail prints a letter as its body's web view
    /// draws it, files and all. The header lists none, as the pane's does
    /// not. A signature's white sheet prints as written, its words black
    /// on the paper's white, its logo as drawn;
    /// the pane, which had rules of its own for the sheet until B-146, now
    /// inverts it with the rest. Every value of the header is escaped, and
    /// only ever written as text, never in an attribute.
    ///
    /// `heldBack` under Block All Remote Content, for a letter whose
    /// pictures from the web the pane holds back (B-168): every reference to
    /// the web in its markup held back on paper too (`RemoteContent`), and
    /// WebKit's list on the print's web view (`LetterPrint`). No line over
    /// it: the paper has no button.
    static func letter(_ m: Message, style: Style, size: (Int64) -> String,
                       locale: Locale = .current, timeZone: TimeZone = .current,
                       heldBack: Bool = false) -> String {
        letter(m, isEmpty: PanePage.isEmpty(m), style: style, size: size, locale: locale, timeZone: timeZone,
               heldBack: heldBack)
    }

    /// The page and the words of one print, which `LetterPrint` makes
    /// together, as `letter` and `words` make them, with the pane's question
    /// (`PanePage.isEmpty`) asked once for both. Of an HTML letter with no
    /// picture and no words of its own, that makes words of all its
    /// markup, up to the 5 MB of a letter fetched whole, against the
    /// print's time limit (`PrintSteps.timeLimit`).
    static func made(_ m: Message, style: Style, size: (Int64) -> String,
                     locale: Locale = .current, timeZone: TimeZone = .current,
                     heldBack: Bool = false)
        -> (page: String, words: String) {
        let isEmpty = PanePage.isEmpty(m)
        return (letter(m, isEmpty: isEmpty, style: style, size: size, locale: locale, timeZone: timeZone,
                       heldBack: heldBack),
                words(m, isEmpty: isEmpty, size: size, locale: locale, timeZone: timeZone))
    }

    /// The page, given the pane's answer to `PanePage.isEmpty` for `m`.
    private static func letter(_ m: Message, isEmpty: Bool, style: Style, size: (Int64) -> String,
                               locale: Locale, timeZone: TimeZone, heldBack: Bool) -> String {
        let head = Self.head(m, size: size, locale: locale, timeZone: timeZone)
        let (body, isHTML) = Self.body(m, isEmpty: isEmpty, heldBack: heldBack)
        func span(_ kind: String, _ text: String) -> String {
            "<span class=\"\(kind)\">\(ConversationDocument.escape(text))</span>"
        }
        // Mail's lines (B-172): a row each, the label in a cell of its own
        // set to the right, the name black, its address grey after it.
        let lines = head.lines.map { line -> String in
            let said = line.text.map(ConversationDocument.escape) ?? line.people.map { person in
                [span("bm-name", person.name)] + [person.address].compactMap { $0 }.map { span("bm-address", $0) }
            }.map { $0.joined(separator: " ") }.joined(separator: ", ")
            return "<tr><td class=\"bm-label\">\(ConversationDocument.escape(line.label))</td>"
                + "<td class=\"bm-value\">\(said)</td></tr>"
        }
        let rule = "<div class=\"bm-rule\"></div>"
        // Mail's bars beside quoted text (B-101), the pane's own string:
        // Mail's light colours, which on white are as Mail draws them. A
        // plain letter's too, its quotes Mail's blockquotes as in the pane
        // (`PlainQuotes`, B-147), in the same light colours on the paper.
        // The line before a quote ending "wrote:" with the first level's
        // bar and colour, as in the pane (`QuoteBars.attributed`, B-180):
        // Mail's paper with such a line was not seen, so its light colour
        // here is inferred from Mail's paper for the quotes.
        let bars = "\n" + QuoteBars.css(in: "#bm")
            + (isHTML && body.contains(QuoteBars.attributionClass)
                ? "\n" + QuoteBars.attributionCSS(in: "#bm") : "")
        // A file's tile at the body's size, as in the pane (`BodyFiles.sizeRule`,
        // B-166, B-170); nothing at Large or below, nor for a letter with none.
        let tileRule = BodyFiles.sizeRule(bodyPointSize: style.bodyPointSize)
        let tiles = tileRule.isEmpty || !body.contains(BodyFiles.tileClass) ? "" : "\n  " + tileRule
        // The header prints in its own colours (`exact`), its lines grey as
        // in the pane and as Mail's header, which UIKit draws, prints them.
        // With no backgrounds printed (`LetterPrint.load`), WebKit changes
        // any text under 4.5:1 on white, and on iPadOS 16.5 and 18 it
        // lightens one of luminance 0.5 or less: `#8e8e8e` would print
        // `#e2e2e2`, all but gone (`adjustColorForVisibilityOnBackground`,
        // read at WebKit's tags for both). `exact` is inherited, and the
        // header has no background to print. Only the header and the
        // notices (`asDrawn`): the sender's words are left to WebKit.
        //
        // The header's table is in the same document as the sender's
        // markup, whose own `<style>` in the body still applies on paper
        // (`DocumentWrapper.stripped` takes off only the `<head>`): a rule
        // for every `td` or `table`, boxes, a width of 100%, or with
        // `!important` a `td` set as a block, would reach the header's
        // lines. What such a rule could change on the table, its rows and
        // its cells is the header's own, `!important`; with no such rule
        // each is what it would be anyway, and nothing on paper moves.
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="color-scheme" content="light only">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html { -webkit-text-size-adjust: 100%; }
          html, body { margin: 0; padding: 0; background: #fff; color: #000; }
          #bm-head { break-inside: avoid; page-break-inside: avoid; margin: 0 0 17px 0;
                     font-family: -apple-system, sans-serif; -webkit-print-color-adjust: exact; }
          #bm-head table { border-collapse: collapse !important; border-spacing: 0 !important;
                           margin: 0 !important; width: auto !important; border: 0 !important;
                           background: none !important; display: table !important; }
          #bm-head tr { border: 0 !important; background: none !important; display: table-row !important; }
          #bm-head td { padding: 1px 0; vertical-align: top;
                        font: \(style.metaPointSize)px -apple-system, sans-serif;
                        border: 0 !important; background: none !important;
                        display: table-cell !important; width: auto !important; }
          #bm-head .bm-label { color: #8e8e8e; text-align: right; white-space: nowrap; padding-right: 6px; }
          #bm-head .bm-value { color: #000; text-align: left; word-wrap: break-word; }
          #bm-head .bm-address { color: #8e8e8e; }
          #bm-head .bm-rule { height: 0; border-top: 0.5px solid #c8c8c8; margin: 8px 0 6px 0; }
          #bm { font: \(style.bodyPointSize)px -apple-system, sans-serif;
                line-height: \(style.lineHeight);
                color: #000; word-wrap: break-word;\(isHTML ? "" : " white-space: pre-wrap;") }
          img, table { max-width: 100% !important; height: auto; }
          a { color: #007AFF; }\(bars)\(tiles)
        </style></head><body><div id="bm-head"><table>\(lines.joined())</table>\(rule)</div><div id="bm">\(body)</div></body></html>
        """
    }

    /// What goes in `#bm`: the body as the pane draws it (`PanePage.content`),
    /// cut to the limit, with the pane's grey line above a letter cut here
    /// or shortened by the pane; or the pane's words for a letter with
    /// nothing in it, where the pane says them (`PanePage.isEmpty`). A
    /// letter shown only in part never has them, in the pane or on paper:
    /// its line is over whatever came, nothing included (B-114, B-131).
    /// Its files drawn in it as the pane draws them, on paper
    /// (`BodyFiles.drawn`, B-170): where they sat, and the rest after the
    /// words, or above them under the line for a letter cut. Whether it is
    /// the letter's HTML. Its pictures decoded as they are drawn
    /// (`decodedAtOnce`): an HTML letter's and its picture files; a plain
    /// letter's words have none, every `<` in them written `&lt;`.
    static func body(_ m: Message, heldBack: Bool = false) -> (html: String, isHTML: Bool) {
        body(m, isEmpty: PanePage.isEmpty(m), heldBack: heldBack)
    }

    private static func body(_ m: Message, isEmpty: Bool, heldBack: Bool) -> (html: String, isHTML: Bool) {
        guard !isEmpty else {
            return (empty, false)
        }
        let known = PanePage.contentIDs(of: m)
        if let html = m.htmlBody {
            let cut = Self.cut(html, to: htmlLimit)
            let shown = cut != nil || m.isShortened
            // The picture behind its words where the pane draws it, on
            // `#bm` as on a light letter's page, so it is not drawn after
            // the words as a file; printed as no background is (B-169).
            let backdrop = PanePage.backdrop(LetterScheme.reading(html: html).bodyPicture, on: "#bm")
            return (notice(shown)
                        + decodedAtOnce(BodyFiles.drawn(
                            in: PanePage.content(text: nil, html: cut ?? html, known: known, flowed: false,
                                                 heldBack: heldBack, backdrop: backdrop),
                            of: m, on: .paper, cut: shown)), true)
        }
        let text = m.textBody ?? ""
        let cut = Self.cut(text, to: textLimit)
        let shown = cut != nil || m.isShortened
        return (notice(shown)
                    + decodedAtOnce(BodyFiles.drawn(
                        in: PanePage.content(text: cut ?? text, html: nil, known: known, flowed: m.textIsFlowed),
                        of: m, on: .paper, cut: shown)), false)
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
    /// words, `HTMLText`), under the same limits and line as the page, or
    /// the pane's words for a letter with none, only where the pane says
    /// them (`PanePage.isEmpty`, B-131), and a line per file after them,
    /// where the page draws the files it has no mark for (B-170). A letter
    /// shown only in part, or cut here, with no words in what is printed
    /// is the header and the line alone; a letter whose page shows no words
    /// but has something to show, a picture, is the header alone.
    static func words(_ m: Message, size: (Int64) -> String,
                      locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        words(m, isEmpty: PanePage.isEmpty(m), size: size, locale: locale, timeZone: timeZone)
    }

    /// The words, given the pane's answer to `PanePage.isEmpty` for `m`.
    private static func words(_ m: Message, isEmpty: Bool, size: (Int64) -> String,
                              locale: Locale, timeZone: TimeZone) -> String {
        let head = Self.head(m, size: size, locale: locale, timeZone: timeZone)
        let lines = head.lines.map(inWords)
        // `quotableText`, but with an HTML letter's markup cut to the
        // page's limit before it is made words, as the page cuts it: a cut
        // there is a cut, said by the line, as on the page, even when what
        // is left makes no words, a style sheet or a picture's data.
        var text = m.textBody ?? ""
        var cutHere = false
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let html = m.htmlBody {
            let markup = cut(html, to: htmlLimit)
            cutHere = markup != nil
            text = HTMLText.plainText(from: markup ?? html)
        }
        text = String(text.drop(while: { $0 == "\n" || $0 == "\r" }))
        let said: String
        if isEmpty {
            said = MailText.emptyBodyNotice
        } else {
            let cut = Self.cut(text, to: textLimit)
            let words = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : cut ?? text
            said = [cutHere || cut != nil || m.isShortened ? MailText.shortenedNotice : "", words]
                .filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        let files = head.files.isEmpty ? "" : "\n\n" + head.files.joined(separator: "\n")
        return lines.joined(separator: "\n") + (said.isEmpty ? "" : "\n\n" + said) + files
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
