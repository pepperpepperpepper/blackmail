import Foundation

/// A whole conversation as one HTML document.
///
/// Mail opens a thread in the READING PANE as a stack of its letters, the
/// latest open and the rest collapsed to a line you can tap. This app used
/// to open the thread OUT IN THE LIST instead — recorded as B-022 — on the
/// reasoning that the pane should always hold exactly one letter. The
/// requirement is that the app work the way the one he knows
/// works, so this is the stack.
///
/// **One web view, not one per letter.** That is the whole design decision
/// and it is worth the sentence: a column of `WKWebView`s is the standard
/// way to build this and it brings the standard defect with it, because a
/// web view does not know how tall it is until it has laid out, so each one
/// reports its height a moment after the others and the text jumps under
/// the reader's thumb while he is trying to read it. It also costs a web
/// content process per letter. Rendering the conversation as a single
/// document makes the height question disappear — the one scroll view
/// simply scrolls — and collapsing is a class on a `<div>`.
///
/// Pure, and out here rather than in the view controller, so the suite on
/// Linux can test it. The controller is behind `#if canImport(UIKit)` and
/// does not exist on the machine the tests run on.
enum ConversationDocument {

    /// One letter's place in the stack.
    struct Entry: Equatable {
        let id: String
        let sender: String
        let date: Date
        /// Nil until the body has been fetched. The stack is drawn from the
        /// summaries the list already has, so the headers appear at once and
        /// the bodies drop in as they arrive — rather than the pane staying
        /// empty until the slowest fetch returns.
        var body: Rendered?
        var isExpanded: Bool
        var preview: String

        struct Rendered: Equatable {
            let html: String
            /// Whether `html` came from the sender as markup. Drives the
            /// invert trick below, which must not be applied to text.
            let isHTML: Bool
        }
    }

    /// The `id` attribute of the section holding one letter, so a body can
    /// be injected into it later without redrawing the document.
    static func sectionID(for messageID: String) -> String {
        // A message id is "<uidvalidity>/<uid>", and the slash is not legal
        // in a CSS selector without escaping.
        "m" + messageID.replacingOccurrences(of: "/", with: "_")
    }

    /// The whole document.
    ///
    /// - Parameters:
    ///   - inset: the pane's content inset, matched to the single-message
    ///     view so a conversation and a letter are laid out identically.
    ///   - bodyPointSize / lineHeight: from `Theme`, passed in rather than
    ///     read, so this file stays free of UIKit.
    static func html(entries: [Entry], inset: Int, bodyPointSize: Int,
                     lineHeight: Double) -> String {
        var sections = ""
        for entry in entries {
            sections += section(entry)
        }

        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html { -webkit-text-size-adjust: 100%; }
          html, body { margin: 0; padding: 0; background: #000; color: #fff;
                       font: \(bodyPointSize)px -apple-system, sans-serif; }
          .bm-letter { border-bottom: 0.5px solid #38383a; }
          /* The tappable line. A whole row rather than a chevron, because a
             44 pt target that spans the pane cannot be missed. */
          .bm-head { padding: 12px \(inset)px; cursor: default;
                     -webkit-tap-highlight-color: rgba(255,255,255,0.08);
                     display: flex; align-items: baseline; gap: 8px; }
          .bm-from { font-weight: 600; flex: 0 0 auto; }
          .bm-when { color: #8e8e93; font-size: \(bodyPointSize - 3)px;
                     margin-left: auto; flex: 0 0 auto; white-space: nowrap; }
          .bm-peek { color: #8e8e93; overflow: hidden; text-overflow: ellipsis;
                     white-space: nowrap; flex: 1 1 auto; }
          /* Collapsed hides the body and shows the one-line peek; open does
             the reverse. Both states exist in the document, so opening one
             is a class change and never a reload. */
          .bm-open > .bm-head > .bm-peek { display: none; }
          .bm-letter:not(.bm-open) > .bm-body { display: none; }
          .bm-body { padding: 0 \(inset)px \(inset)px \(inset)px;
                     line-height: \(lineHeight); word-wrap: break-word; }
          .bm-text { white-space: pre-wrap; color: #fff; }
          /* A sender's own markup carries its own colours, almost always
             dark text for a white page, so it is inverted the way Smart
             Invert does it — invert everything, hue-rotate the colours back,
             then invert pictures again to cancel it for them. Scoped to the
             one letter rather than the document, because a conversation
             mixes plain and HTML replies and the plain ones must not be
             inverted twice. */
          .bm-html { filter: invert(1) hue-rotate(180deg); background: #fff;
                     color: #000; }
          .bm-html img, .bm-html video, .bm-html svg, .bm-html picture,
          .bm-html [style*="background-image"] {
                     filter: invert(1) hue-rotate(180deg); }
          /* The signature stays a white sheet with black text, whatever the
             rest of the theme is doing. It is a formal block — the organisation name,
             the logo, the confidentiality notice — and it is the one part of
             a letter that is supposed to look like paper rather than like
             this app. Inverting an already-inverted parent cancels out, so
             this renders exactly as authored, which is the same trick the
             image rule above uses. */
          .bm-html .bm-signature { filter: invert(1) hue-rotate(180deg); }
          /* …and pictures inside it must NOT take the image rule as well, or
             the logo would be inverted three times and come out negative.
             Higher specificity than `.bm-html img`, so it wins. */
          .bm-html .bm-signature img, .bm-html .bm-signature svg,
          .bm-html .bm-signature picture, .bm-html .bm-signature video {
                     filter: none; }
          .bm-body img, .bm-body table { max-width: 100% !important; height: auto; }
          .bm-text a { color: #0A84FF; }
          .bm-html a { color: #007AFF; }
          .bm-waiting { color: #8e8e93; padding: 0 \(inset)px \(inset)px \(inset)px; }
        </style></head><body>
        \(sections)
        <script>
        function bmToggle(id) {
          var el = document.getElementById(id);
          if (!el) return;
          var opening = !el.classList.contains('bm-open');
          el.classList.toggle('bm-open');
          // Swift is told either way: opening one needs its body fetched if
          // it has not been, and needs the letter marked read.
          if (window.webkit && window.webkit.messageHandlers.bmLetter) {
            window.webkit.messageHandlers.bmLetter.postMessage(
              { id: id, open: opening });
          }
        }
        function bmFill(id, html, isHTML) {
          var el = document.getElementById(id);
          if (!el) return;
          var body = el.querySelector('.bm-body');
          if (!body) return;
          body.className = 'bm-body ' + (isHTML ? 'bm-html' : 'bm-text');
          body.innerHTML = html;
        }
        </script>
        </body></html>
        """
    }

    private static func section(_ e: Entry) -> String {
        let id = sectionID(for: e.id)
        let open = e.isExpanded ? " bm-open" : ""

        let body: String
        if let rendered = e.body {
            body = "<div class=\"bm-body \(rendered.isHTML ? "bm-html" : "bm-text")\">"
                + rendered.html + "</div>"
        } else {
            // A placeholder rather than nothing, so an expanded letter whose
            // body has not arrived says so instead of looking like an empty
            // message — the failure B-026 is about.
            body = "<div class=\"bm-body bm-text\"><span class=\"bm-waiting\">"
                + "Loading…</span></div>"
        }

        return """
        <div class="bm-letter\(open)" id="\(id)">
          <div class="bm-head" onclick="bmToggle('\(id)')">
            <span class="bm-from">\(escape(MailFormat.displayName(e.sender)))</span>
            <span class="bm-peek">\(escape(e.preview))</span>
            <span class="bm-when">\(escape(MailFormat.listTimestamp(e.date)))</span>
          </div>
          \(body)
        </div>
        """
    }

    /// What a body is wrapped in when it is injected after the fact.
    ///
    /// `bmFill` takes the inner HTML, so this escapes it for a JavaScript
    /// string literal rather than for HTML.
    static func javascriptFill(sectionID: String, html: String, isHTML: Bool) -> String {
        "bmFill('\(sectionID)', '\(escapeForJS(html))', \(isHTML))"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Everything that would end the single-quoted string, close the
    /// `<script>` element, or break the line in two.
    ///
    /// `</script>` matters as much as the quote: a message body containing
    /// that sequence ends the script element early wherever it appears, and
    /// the rest of the letter is then parsed as markup.
    static func escapeForJS(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count + 16)
        for ch in text {
            switch ch {
            case "\\": out += "\\\\"
            case "'":  out += "\\'"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\u{2028}": out += "\\u2028"   // a line separator ends a JS line
            case "\u{2029}": out += "\\u2029"
            case "<":  out += "\\x3C"           // defuses </script>
            default:   out.append(ch)
            }
        }
        return out
    }
}
