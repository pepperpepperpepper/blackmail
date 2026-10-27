import Foundation

/// A downloaded letter made into what the reading pane shows: the whole
/// page for a letter on its own, or the body that goes into its section of
/// a conversation's stack.
///
/// Pure string work, out of `MessageDetailViewController` so that it runs
/// away from the main thread, which `PaneLoads` sees to, and so the suite
/// can test it. It used to run on the main thread as the letter came:
/// taking off the sender's document wrapper, pointing the letter's pictures
/// at the loader, working out whether there is anything in it to show, and
/// escaping plain text. On a letter of a megabyte that held the screen for
/// a tenth of a second or more; see PERFORMANCE.md #1.
///
/// The links a letter writes out as words are made links here as well
/// (`TextLinks`): the pane runs no script of the letter's and has WebKit's
/// data detectors off, so a link the page does not carry as `<a>` cannot be
/// tapped. A tap on one goes where a tap on any link in a letter goes
/// (`PaneNavigation`).
enum PanePage {

    /// The pane's measurements, read from `Theme` on the main thread and
    /// handed in, so this file stays free of UIKit.
    struct Style: Sendable {
        /// The content inset, matched to the conversation's so a letter and
        /// a stack are laid out alike.
        let inset: Int
        let bodyPointSize: Int
        let lineHeight: Double
    }

    /// The `Content-ID`s the letter has parts for. Only these are pointed
    /// at the loader (`InlineImageRewriter`); they are also what
    /// `MessageDetailViewController.prepareInlineImages` points the loader
    /// at, from the same parts.
    static func contentIDs(of m: Message) -> Set<String> {
        Set(m.attachments.compactMap(\.contentID))
    }

    /// Where the loader finds a picture a page asks for by `Content-ID`:
    /// the part, and the letter it is in.
    struct Picture: Equatable, Sendable {
        let messageID: String
        let mailboxID: String
        /// The part's number, as `fetchAttachmentData` takes it.
        let section: String
        let mimeType: String
    }

    /// The pictures of `letters` by `Content-ID`, for the loader of the
    /// page that shows them: the pane's (`prepareInlineImages`) and a
    /// printed letter's (`LetterPrint`, B-110). A `Content-ID` only means
    /// anything inside the letter that declared it, and two letters can
    /// both have `cid:image001.png`; where they do, the later letter's is
    /// served.
    static func pictures(of letters: [Message]) -> [String: Picture] {
        var parts: [String: Picture] = [:]
        for m in letters {
            for attachment in m.attachments {
                guard let cid = attachment.contentID else { continue }
                parts[cid] = Picture(messageID: m.id, mailboxID: m.mailboxID,
                                     section: attachment.id, mimeType: attachment.mimeType)
            }
        }
        return parts
    }

    /// The page for one letter, or nil when there is nothing in it to draw,
    /// and the pane says so in words instead (`MailText.hasNoVisibleContent`,
    /// B-026).
    ///
    /// Never nil for a letter shown only in part (`Message.isShortened`):
    /// what was not fetched, or what the server would not give, can be all
    /// its words, and it is not a letter with no text. Its page says it is
    /// only the beginning, over whatever came (B-114).
    ///
    /// `heldBack` under Block All Remote Content, until "Load All Images"
    /// (`RemotePictures`, B-168): a letter that asks the web for anything
    /// has Mail's line over it, its button naming the letter, and every
    /// reference to the web in it held back (`RemoteContent`); one that
    /// asks for nothing is as it was. Not held back, the page is as it
    /// always was.
    ///
    /// An HTML letter drawn as Mail draws it in Dark Mode (`LetterScheme`,
    /// B-169): inverted, on its own white, or in its own colours, decided
    /// from its markup, or as `scheme` says, which a test uses to draw a
    /// letter inverted. A plain letter's page has no scheme. Decided from
    /// its markup as it came, held back or not: a letter with a picture
    /// from the web is light whether the picture is shown or held back, as
    /// Mail's rule reads the page's `src`, which Block All Remote Content
    /// leaves as written (int19).
    static func letter(_ m: Message, style: Style, heldBack: Bool = false,
                       scheme: LetterScheme? = nil) -> String? {
        guard !isEmpty(m) else { return nil }
        let isHTML = m.htmlBody != nil
        let drawn = m.htmlBody.map { scheme ?? LetterScheme.of(html: $0) }
        let darkWords = !isHTML || drawn == .own
        // Leading blank lines are dropped from PLAIN TEXT before rendering.
        //
        // Not cosmetic tidying — it is this app's own doing coming back.
        // `Draft.replying` and `Draft.forwarding` both open a letter with
        // two newlines so there is room to type ABOVE the quoted part, and
        // those newlines are really sent. Reading such a letter back
        // therefore started it about eighty points down an otherwise empty
        // pane, which on the screen where he actually reads is the most
        // expensive space in the product. Measured against a forward whose
        // header block ended at y 355 and whose first words began at 470.
        //
        // Nothing is lost: blank lines before the first word carry no
        // meaning. HTML is left exactly alone, because whitespace there is
        // not reliably whitespace and the document may open with a layout
        // table.
        //
        // A file sent among the words has its row where it sat, a link that
        // opens it (`BodyFiles`, B-113); a letter with none is as it was.
        let held = heldBack ? Self.held(m, as: m.id, drawn: drawn) : ""
        let html = isHTML
            ? BodyFiles.rows(in: Self.content(text: nil, html: m.htmlBody, known: contentIDs(of: m),
                                              flowed: false, heldBack: !held.isEmpty), of: m)
            : Self.content(text: m.textBody, html: nil, known: contentIDs(of: m), flowed: m.textIsFlowed)
        let content = drawn == .own ? inOwnColours(html, of: m, heldBack: !held.isEmpty) : html

        // Every property lives on #bm, a container the inner document cannot
        // reach, rather than on `body` where a sender's inline style outranks
        // it. The viewport rule is what stops a desktop-width newsletter from
        // needing horizontal scrolling, which `ACCEPTANCE_TESTS.md` calls out by name.
        // Dark body. Plain text is simply light-on-black, but an HTML message
        // carries its OWN colours — almost always dark text assuming a white
        // page — so forcing a black background behind it would give unreadable
        // black-on-black, or white islands if the sender sets their own.
        //
        // So HTML gets inverted the way Smart Invert was doing it, in CSS:
        // invert the lot, then hue-rotate to put the colours back the right way
        // round, then invert images and video AGAIN to cancel it for them. That
        // is exactly the trick that keeps a photograph looking like a
        // photograph while the text around it goes light-on-dark.
        //
        // The invert is the stack's, the one string (`SignatureSheet.invert`).
        // A signature's white sheet is inverted with the rest, as Mail
        // draws it (B-146): its rules, which inverted it back, are gone.
        // After the invert, Mail's bars beside quoted text (`QuoteBars`,
        // B-101), in its light colours, which the invert turns. A plain
        // letter's quotes are Mail's blockquotes too (`PlainQuotes`,
        // B-147), and its page is not inverted: the bars in Mail's dark
        // colours, as Mail draws a plain letter in Dark Mode.
        //
        // Inverted only where Mail turns the letter to the dark, which is
        // a letter with no scheme of its own, no picture from the web and
        // no background picture (`LetterScheme`, B-169); its page is as it
        // always was. One with a picture from the web, or a light scheme
        // only, is drawn light as its sender made it, black words on its
        // own white, the pane's black around it, Mail's bars in its light
        // colours, as on paper. One that declares the dark is drawn in its
        // own colours, words white on the pane's black, its style for the
        // dark with it (`inOwnColours`), Mail's bars in its dark colours.
        let smartInvert: String
        switch drawn {
        case .inverted?:
            smartInvert = """
              #bm { filter: \(SignatureSheet.invert); background: #fff; }
              #bm img, #bm video, #bm svg, #bm picture, #bm [style*="background-image"] {
                  filter: \(SignatureSheet.invert); }
              """ + "\n" + QuoteBars.css(in: "#bm")
        case .light?:
            smartInvert = "#bm { background: #fff; color-scheme: light only; }\n" + QuoteBars.css(in: "#bm")
        case .own?:
            smartInvert = "#bm { color-scheme: light dark; }\n"
                + QuoteBars.css(in: "#bm", palette: QuoteBars.dark)
        case nil:
            smartInvert = QuoteBars.css(in: "#bm", palette: QuoteBars.dark)
        }
        // Mail's line, when there is one, at the body's size whatever the
        // letter's own rules say (B-166, B-168), and in Mail's dark colours
        // over a letter in its own (B-169); nothing otherwise, so the page
        // is as it was.
        let heldSize = held.isEmpty
            ? "" : "\n  " + RemoteContent.sizeRule(in: "#bm", pointSize: style.bodyPointSize)
                + (drawn == .own ? "\n  " + RemoteContent.darkRule(in: "#bm") : "")
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html { -webkit-text-size-adjust: 100%; }
          html, body { margin: 0; padding: 0; background: #000; }
          #bm { padding: \(style.inset)px;
                font: \(style.bodyPointSize)px -apple-system, sans-serif;
                line-height: \(style.lineHeight);
                color: \(darkWords ? "#fff" : "#000"); word-wrap: break-word;\
        \(isHTML ? "" : " white-space: pre-wrap;") }
          img, table { max-width: 100% !important; height: auto; }
          a { color: \(darkWords ? "#0A84FF" : "#007AFF"); }
          \(smartInvert)\(heldSize)
        </style></head><body><div id="bm">\(held)\(shortened(m))\(content)</div></body></html>
        """
    }

    /// Mail's line for `m`, its button naming `id`, when its markup asks the
    /// web for anything (`RemoteContent.line`, B-168); "" when it asks for
    /// nothing, a plain letter's never does, and nothing is held back. For a
    /// letter drawn in its own colours (`drawn`, B-169), the style of its
    /// head and body that comes back with it counts too: a `url()` of the
    /// web there is held back as the markup's are, and Mail's line says so
    /// (int19).
    static func held(_ m: Message, as id: String, drawn: LetterScheme? = nil) -> String {
        guard let html = m.htmlBody else { return "" }
        let asks = RemoteContent.asksTheWeb(DocumentWrapper.stripped(from: html))
            || (drawn == .own && RemoteContent.asksTheWeb(ownFrame(of: m).open))
        return asks ? RemoteContent.line(for: id) : ""
    }

    /// The pane's line above a letter it shows only the beginning of
    /// (`Message.isShortened`), and nothing above any other, whose page is
    /// what it always was. Above the letter rather than under it: the
    /// sender's markup is cut wherever the fetch stopped, inside a table, a
    /// link or a tag, and anything written after it would be drawn inside
    /// that, or not at all. Its own style, grey as "Loading…" is, so that
    /// it reads as the app's and not the sender's.
    static func shortened(_ m: Message) -> String {
        m.isShortened ? shortenedLine : ""
    }

    /// That line, as the pane draws it; a printed letter has it too, over
    /// one the pane shortened or the print cut (`PrintPage`, B-110).
    static let shortenedLine = "<p style=\"color: #8e8e93; margin: 0 0 1em 0; white-space: normal;\">"
        + MailText.shortenedNotice + "</p>"

    /// What goes in `#bm` for a letter's body, `html` when it has one and
    /// `text` otherwise: the sender's markup without its wrapper, with its
    /// pictures by `cid:` pointed at the loader where `known` has them, and
    /// text escaped with its leading blank lines dropped, its quotes Mail's
    /// blockquotes, as deep as `flowed` text counts them (`PlainQuotes`,
    /// B-147); with the links it writes out made links. The pane's page
    /// (`letter`) and a printed letter's (`PrintPage`, B-110) both draw it,
    /// so a printed letter is the letter he read. `flowed` has no default,
    /// so neither can leave it out and count a flowed letter's quotes as
    /// one not flowed.
    ///
    /// `heldBack`, the sender's markup with every reference to the web in it
    /// held back (`RemoteContent.blocked`, B-168), before its pictures by
    /// `cid:` are pointed at the loader, which it leaves as they are.
    static func content(text: String?, html: String?, known: Set<String>, flowed: Bool,
                        heldBack: Bool = false) -> String {
        if let html {
            let page = DocumentWrapper.stripped(from: html)
            return TextLinks.html(InlineImageRewriter.rewrite(heldBack ? RemoteContent.blocked(page) : page,
                                                              known: known))
        }
        return PlainQuotes.html((text ?? "").drop(while: { $0 == "\n" || $0 == "\r" }), flowed: flowed,
                                escaping: .ampersandAndLessThan)
    }

    /// One letter's body for its section of a conversation's stack: the
    /// sender's markup without its wrapper, text escaped with its leading
    /// blank lines dropped as a letter on its own drops them, or the words
    /// for a letter with nothing in it. Its links are made links, a plain
    /// letter's quotes Mail's blockquotes (B-147), and a file sent among its
    /// words has its row there, as a letter on its own has them.
    ///
    /// `heldBack`, the id of the letter's entry in the stack, under Block
    /// All Remote Content until "Load All Images" (`RemotePictures`,
    /// B-168): a letter that asks the web for anything has Mail's line at
    /// the top of its section, its button naming the entry, and every
    /// reference to the web in it held back, as a letter on its own has
    /// them. Nil, the body is as it always was.
    ///
    /// Each letter drawn as Mail draws it in Dark Mode, decided on its own
    /// (`LetterScheme`, B-169): its body's class in the stack says how
    /// (`Rendered.kind`), and one in its own colours has its style for the
    /// dark with it, in a box of its own, as on its own page; held back,
    /// that style's references to the web too (int19).
    static func stackBody(_ m: Message, heldBack: String? = nil) -> ConversationDocument.Entry.Rendered {
        let isHTML = m.htmlBody != nil
        let empty = isEmpty(m)
        let drawn = isHTML && !empty ? LetterScheme.of(html: m.htmlBody!) : .inverted
        let held = empty ? "" : heldBack.map { Self.held(m, as: $0, drawn: drawn) } ?? ""
        var content = empty
            ? "<span class=\"bm-waiting\">\(MailText.emptyBodyNotice)</span>"
            : (isHTML
               ? BodyFiles.rows(in: Self.content(text: nil, html: m.htmlBody, known: contentIDs(of: m),
                                                 flowed: false, heldBack: !held.isEmpty), of: m)
               : PlainQuotes.html((m.textBody ?? "").drop(while: { $0 == "\n" || $0 == "\r" }),
                                  flowed: m.textIsFlowed, escaping: .ampersandAndBrackets))
        if drawn == .own { content = inOwnColours(content, of: m, heldBack: !held.isEmpty) }
        return .init(html: empty ? content : held + shortened(m) + content, isHTML: isHTML && !empty,
                     scheme: drawn)
    }

    /// A letter drawn in its own colours (`LetterScheme.own`, B-169): its
    /// markup in a box of its own, `ownBox`, with the style sheets of its
    /// head in front of it, each rule made to apply in that box alone
    /// (`LetterCSS.scoped`). Taking off the letter's wrapper takes its head
    /// off, and its rules for the dark, `@media (prefers-color-scheme:
    /// dark)`, are in it all but always; without them its words, written
    /// dark for a white page, would be dark on the pane's black.
    ///
    /// The box stands for its root, a `div` of the class
    /// `LetterCSS.rootClass`, and a `div` in it of the class
    /// `LetterCSS.bodyClass` for its body, the markup inside that. Its
    /// rules for its root or its body are theirs, inside the pane's margin,
    /// which they cannot take away. Its body's tag goes with the wrapper,
    /// and with it what a letter can give its body; so the `div` for the
    /// body has its body's `class`, for its rules that name the body by it,
    /// and its `style`, and its `bgcolor` and `text` are the `div`'s
    /// background and colour by a rule in front of the head's that weighs
    /// nothing, as HTML weighs them below every rule of a sheet
    /// (`LetterCSS.legacyColour`). Without them a letter whose white page
    /// is its body's had its dark words on the pane's black, and its rules
    /// for the dark by its body's class matched nothing. A letter with no
    /// style in its head and nothing on its body has the two `div`s alone.
    ///
    /// `heldBack` under Block All Remote Content (B-168): the style brought
    /// back with it has every reference to the web in it held back, as the
    /// markup's are (`RemoteContent.blocked`), so a `url()` in its head or
    /// on its body loads nothing until "Load All Images" (int19).
    static func inOwnColours(_ markup: String, of m: Message, heldBack: Bool = false) -> String {
        let frame = ownFrame(of: m)
        return (heldBack ? RemoteContent.blocked(frame.open) : frame.open) + markup + frame.close
    }

    /// The two `div`s `inOwnColours` puts a letter's markup in, the style
    /// brought back with it in front: what goes before the markup, and what
    /// after.
    static func ownFrame(of m: Message) -> (open: String, close: String) {
        let html = m.htmlBody ?? ""
        let box = ownBox(of: m)
        var letter = LetterScheme.Markup(html)
        letter.read()
        let hints = [("background-color", letter.bodyColour), ("color", letter.bodyText)]
            .compactMap { name, value in value.flatMap(LetterCSS.legacyColour).map { "\(name): \($0);" } }
        var sheets = hints.isEmpty
            ? [] : [":where(#\(box) > .\(LetterCSS.bodyClass)) { " + hints.joined(separator: " ") + " }\n"]
        sheets += LetterScheme.headStyles(of: html).map { LetterCSS.scoped($0, in: "#" + box) }
            .filter { !$0.isEmpty }
        let style = sheets.isEmpty ? "" : "<style>\n" + sheets.joined(separator: "\n") + "</style>"
        let classes = [LetterCSS.bodyClass]
            + (letter.bodyClass ?? "").components(separatedBy: LetterScheme.htmlSpaces).filter { !$0.isEmpty }
        let own = letter.bodyStyle.map { " style=\"" + QuotedMarkup.attributeEscaped($0) + "\"" } ?? ""
        return ("<div id=\"\(box)\" class=\"\(LetterCSS.rootClass)\">" + style
                    + "<div class=\"" + QuotedMarkup.attributeEscaped(classes.joined(separator: " ")) + "\""
                    + own + ">",
                "</div></div>")
    }

    /// The id of that box: from the letter's own, `"<uidvalidity>/<uid>"`,
    /// its slash, and anything but letters, digits and `-`, made an
    /// underscore, so two letters of a stack each have their own.
    static func ownBox(of m: Message) -> String {
        "bm-own-" + String(String.UnicodeScalarView(m.id.unicodeScalars.map {
            ($0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-")) ? $0 : "_"
        }))
    }

    /// Whether the pane says the letter has no text: nothing in it to draw,
    /// and all of it there. A letter shown only in part is never said to
    /// have none, but to be only the beginning (B-114).
    static func isEmpty(_ m: Message) -> Bool {
        !m.isShortened && MailText.hasNoVisibleContent(text: m.textBody, html: m.htmlBody)
    }
}
