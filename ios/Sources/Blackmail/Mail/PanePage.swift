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
    static func letter(_ m: Message, style: Style) -> String? {
        guard !isEmpty(m) else { return nil }
        let isHTML = m.htmlBody != nil
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
        let content = isHTML
            ? BodyFiles.rows(in: Self.content(text: nil, html: m.htmlBody, known: contentIDs(of: m)), of: m)
            : Self.content(text: m.textBody, html: nil, known: contentIDs(of: m))

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
        // After it, a signature's white sheet, inverted back, its pictures
        // as drawn (`SignatureSheet`, B-130), the stack's own rules; then
        // Mail's bars beside quoted text (`QuoteBars`, B-101). For HTML
        // only: a plain letter's quotes are words, with no blockquote, and
        // it can carry no sheet, its `<` written `&lt;`.
        let smartInvert = isHTML
            ? """
              #bm { filter: \(SignatureSheet.invert); background: #fff; }
              #bm img, #bm video, #bm svg, #bm picture, #bm [style*="background-image"] {
                  filter: \(SignatureSheet.invert); }
              """ + "\n" + SignatureSheet.css(in: "#bm") + "\n" + QuoteBars.css(in: "#bm")
            : ""
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html { -webkit-text-size-adjust: 100%; }
          html, body { margin: 0; padding: 0; background: #000; }
          #bm { padding: \(style.inset)px;
                font: \(style.bodyPointSize)px -apple-system, sans-serif;
                line-height: \(style.lineHeight);
                color: \(isHTML ? "#000" : "#fff"); word-wrap: break-word;\
        \(isHTML ? "" : " white-space: pre-wrap;") }
          img, table { max-width: 100% !important; height: auto; }
          a { color: \(isHTML ? "#007AFF" : "#0A84FF"); }
          \(smartInvert)
        </style></head><body><div id="bm">\(shortened(m))\(content)</div></body></html>
        """
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
    /// text escaped with its leading blank lines dropped; with the links it
    /// writes out made links. The pane's page (`letter`) and a printed
    /// letter's (`PrintPage`, B-110) both draw it, so a printed letter is
    /// the letter he read.
    static func content(text: String?, html: String?, known: Set<String>) -> String {
        if let html {
            return TextLinks.html(InlineImageRewriter.rewrite(DocumentWrapper.stripped(from: html),
                                                              known: known))
        }
        return TextLinks.plain((text ?? "").drop(while: { $0 == "\n" || $0 == "\r" }),
                               escaping: .ampersandAndLessThan)
    }

    /// One letter's body for its section of a conversation's stack: the
    /// sender's markup without its wrapper, text escaped with its leading
    /// blank lines dropped as a letter on its own drops them, or the words
    /// for a letter with nothing in it. Its links are made links, and a file
    /// sent among its words has its row there, as a letter on its own has
    /// them.
    static func stackBody(_ m: Message) -> ConversationDocument.Entry.Rendered {
        let isHTML = m.htmlBody != nil
        let empty = isEmpty(m)
        let content = empty
            ? "<span class=\"bm-waiting\">\(MailText.emptyBodyNotice)</span>"
            : (isHTML
               ? BodyFiles.rows(in: TextLinks.html(InlineImageRewriter.rewrite(
                   DocumentWrapper.stripped(from: m.htmlBody!), known: contentIDs(of: m))), of: m)
               : TextLinks.plain((m.textBody ?? "").drop(while: { $0 == "\n" || $0 == "\r" }),
                                 escaping: .ampersandAndBrackets))
        return .init(html: empty ? content : shortened(m) + content, isHTML: isHTML && !empty)
    }

    /// Whether the pane says the letter has no text: nothing in it to draw,
    /// and all of it there. A letter shown only in part is never said to
    /// have none, but to be only the beginning (B-114).
    static func isEmpty(_ m: Message) -> Bool {
        !m.isShortened && MailText.hasNoVisibleContent(text: m.textBody, html: m.htmlBody)
    }
}
