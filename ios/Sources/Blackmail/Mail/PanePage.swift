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

    /// The page for one letter, or nil when there is nothing in it to draw,
    /// and the pane says so in words instead (`MailText.hasNoVisibleContent`,
    /// B-026).
    static func letter(_ m: Message, style: Style) -> String? {
        guard !MailText.hasNoVisibleContent(text: m.textBody, html: m.htmlBody) else { return nil }
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
        let content = isHTML
            ? TextLinks.html(InlineImageRewriter.rewrite(DocumentWrapper.stripped(from: m.htmlBody!),
                                                         known: contentIDs(of: m)))
            : TextLinks.plain((m.textBody ?? "").drop(while: { $0 == "\n" || $0 == "\r" }),
                              escaping: .ampersandAndLessThan)

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
        let smartInvert = isHTML
            ? """
              #bm { filter: invert(1) hue-rotate(180deg); background: #fff; }
              #bm img, #bm video, #bm svg, #bm picture, #bm [style*="background-image"] {
                  filter: invert(1) hue-rotate(180deg); }
              """
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
        </style></head><body><div id="bm">\(content)</div></body></html>
        """
    }

    /// One letter's body for its section of a conversation's stack: the
    /// sender's markup without its wrapper, text escaped with its leading
    /// blank lines dropped as a letter on its own drops them, or the words
    /// for a letter with nothing in it. Its links are made links as a
    /// letter on its own has them.
    static func stackBody(_ m: Message) -> ConversationDocument.Entry.Rendered {
        let isHTML = m.htmlBody != nil
        let empty = MailText.hasNoVisibleContent(text: m.textBody, html: m.htmlBody)
        let content = empty
            ? "<span class=\"bm-waiting\">\(MailText.emptyBodyNotice)</span>"
            : (isHTML
               ? TextLinks.html(InlineImageRewriter.rewrite(DocumentWrapper.stripped(from: m.htmlBody!),
                                                            known: contentIDs(of: m)))
               : TextLinks.plain((m.textBody ?? "").drop(while: { $0 == "\n" || $0 == "\r" }),
                                 escaping: .ampersandAndBrackets))
        return .init(html: content, isHTML: isHTML && !empty)
    }
}
