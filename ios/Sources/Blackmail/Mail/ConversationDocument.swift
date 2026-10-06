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
/// **In Mail's order, from its factory settings** (B-074): the oldest
/// letter at the top and the newest at the bottom; the letters he has read
/// closed to their line, and the unread ones open, with the newest, the one
/// he opened from the list; and the pane opening at the oldest of the open
/// ones, the newest when he has read the rest. It ran newest first until
/// 2026-10-06, which was a guess (B-022). See `stack`, `opensAt` and
/// `script`.
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
///
/// **No script in the document.** The pane runs none of a page's own
/// script, so that a letter's cannot run (`MessageDetailViewController`), and
/// that includes this document's. What opens and closes a letter and puts a
/// body in its section is `script`, which the pane injects as a user script
/// into a content world of the app's own: the letters' markup cannot see it
/// or call it, nor post to the `bmLetter` handler, which is registered in
/// that world alone. The lines are wired with `addEventListener`, since an
/// inline `onclick` is the page's own script and would not run.
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

    // MARK: - Mail's order

    /// The stack of `thread`, top to bottom, as Mail shows a conversation
    /// with its factory settings: Most Recent Message on Top off, Collapse
    /// Read Messages on (B-074).
    ///
    /// The oldest letter at the top and the newest at the bottom: the
    /// list's order turned over. The list's order is the order the letters
    /// came into the folder, which is their dates' order but for a letter
    /// dated wrong or put back in the folder later; turned over, it keeps
    /// at the bottom the letter the conversation's row stands for, the one
    /// he tapped the row to read.
    ///
    /// Open: the newest, and every letter he has not read, as Mail shows
    /// them in full. Closed to its line: every letter he has read but the
    /// newest.
    static func stack(of thread: MessageThread) -> [Entry] {
        let newest = thread.newest.id
        return thread.messages.reversed().map { m in
            entry(for: m, open: m.id == newest || !m.isRead)
        }
    }

    /// One letter's place in the stack, drawn from its row in the list.
    static func entry(for m: MessageSummary, open: Bool) -> Entry {
        Entry(id: m.id, sender: m.sender, date: m.date, body: nil,
              isExpanded: open, preview: m.preview)
    }

    /// The letters of `thread` the stack opens besides the newest: the
    /// unread ones, newest first. The pane fetches each after the newest.
    /// They are in front of him in full, the pane opening at the oldest of
    /// them (`opensAt`), and are marked read at the tap with the newest
    /// (`readAtTheTap`).
    static func openedWithTheNewest(_ thread: MessageThread) -> [MessageSummary] {
        thread.messages.filter { $0.id != thread.newest.id && !$0.isRead }
    }

    /// The letters of `thread` a tap on its row marks read: the newest, as
    /// a tap on a row always has, and the unread ones the stack opens with
    /// it. All at once, by the list: one redraw of the rows for the lot,
    /// where a redraw each held the tap up for as many as were unread.
    static func readAtTheTap(_ thread: MessageThread) -> [MessageSummary] {
        [thread.newest] + openedWithTheNewest(thread)
    }

    /// The section the pane opens at, held at the top of the pane until he
    /// touches it (`script`): the first open letter's, or, when the letter
    /// before it is closed, that letter's line, so that the line shows
    /// there are older letters above.
    ///
    /// In the stack as it opens, the first open letter is the oldest he has
    /// not read, and the newest when he has read the rest. So every letter
    /// marked read as the stack opens starts at or below the top of the
    /// pane, none of them above it, out of sight: he scrolls down through
    /// them to the newest. Opened at the newest, the unread ones above it
    /// were marked read where he could not see them. Mail opens a
    /// conversation at its newest letter, as far as is known; what it does
    /// with several unread letters is not known. Nil for no letters.
    static func opensAt(_ entries: [Entry]) -> String? {
        guard !entries.isEmpty else { return nil }
        let at = entries.firstIndex(where: \.isExpanded) ?? entries.count - 1
        if at > 0, !entries[at - 1].isExpanded { return sectionID(for: entries[at - 1].id) }
        return sectionID(for: entries[at].id)
    }

    /// The letters to put at the bottom of the stack on screen as they come
    /// (B-074): those of its conversation, as the list now has it, that
    /// came after the newest letter of the stack the list still has, and are
    /// not in the stack, oldest first. `shown` is the stack's letters.
    ///
    /// The conversation is the row holding a letter of the stack: the same
    /// letter, by its folder, its id and its Gmail id, since a row kept on
    /// the iPad can carry the id of another letter once the server has
    /// spoken (D-016). Letters older than the newest one shown, as a page
    /// further down can bring, are not put in: the stack would grow above
    /// him. Nothing when the list holds none of the stack: another folder,
    /// a search, or every letter of the stack gone from it. Nothing either
    /// when the list does not group, where a row holds one letter.
    static func arrivals(after shown: [MessageSummary],
                         in threads: [MessageThread]) -> [MessageSummary] {
        let ids = Set(shown.map(\.id))
        for thread in threads {
            guard let at = thread.messages.firstIndex(where: { m in
                ids.contains(m.id) && shown.contains(where: {
                    $0.id == m.id && $0.mailboxID == m.mailboxID && ListEdit.sameLetter($0, m)
                })
            }) else { continue }
            return Array(thread.messages[..<at].filter { !ids.contains($0.id) }.reversed())
        }
        return []
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
        // Where the pane opens (`opensAt`), for `script` to read as the
        // document ends: in the head, which no letter's markup reaches.
        let opens = opensAt(entries).map { "\n<meta name=\"bm-opens\" content=\"\($0)\">" } ?? ""

        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">\(opens)
        <style>
          /* No anchoring of WebKit's own: the stack's script keeps his
             place, and two at once would move him twice. */
          html, body { overflow-anchor: none; }
          html { -webkit-text-size-adjust: 100%; }
          html, body { margin: 0; padding: 0; background: #000; color: #fff;
                       font: \(bodyPointSize)px -apple-system, sans-serif; }
          .bm-letter { border-bottom: 0.5px solid #38383a; }
          /* The last letter, open or closed, is at least as tall as the
             pane, so the stack can open at any letter from the first frame,
             before the bodies have come, and nothing moves when they do: a
             short letter, or a closed one, has the black of the pane under
             it, as a letter alone has. Without it the stack opened at its
             top, and moved up under him when the body came. On the last
             letter whatever it is, and not on the last open one, so the
             stack never gets shorter under him: a letter put in at the
             bottom closed, or the newest closed by its line, took the floor
             away, and WebKit pulled the stack down to its new end. */
          body > .bm-letter:last-child { min-height: 100vh;
                     box-sizing: border-box; }
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
        </body></html>
        """
    }

    /// The stack's own script: every page the pane loads is given it, at
    /// the end of the document, in the app's content world
    /// (`MessageDetailViewController`).
    ///
    /// It wires a tap on each letter's line: only the lines that are the
    /// body's own, and are there as the document loads, before any letter's
    /// markup is put in. A body's markup goes into its section later, by
    /// `bmFill`, so a letter that draws a line of its own never gets a tap
    /// wired to it. A single letter's page, whose markup is in `#bm` from
    /// the start and can close it early and draw such a line beside it,
    /// gets nothing at all from this script. The line toggles its letter
    /// open or closed, as its `onclick` did, and tells the pane either way:
    /// opening one needs its body fetched if it has not been, and the
    /// letter marked read.
    ///
    /// It opens the stack at the oldest letter he has not read, or at the
    /// newest, at the bottom, when he has read the rest (B-074): the
    /// section `opensAt` named, put at the top of the pane. The last
    /// letter is at least as tall as the pane (`html`), so it can be, from
    /// the first frame. It holds it there while the bodies and their
    /// pictures come, which can grow the stack above it, until he touches
    /// the pane, or the pane scrolls by anything but the script: the status
    /// bar tapped, VoiceOver's scroll, the header changing height
    /// (`StackPlace`). The script notes where it put the page, and a scroll
    /// to anywhere else lets go. Without that the hold went on, and the next
    /// letter to grow pulled him back to where the stack opened. From then
    /// on it keeps his place instead: the letter at the top of the pane
    /// stays where it is on the glass when a letter above it grows or
    /// shrinks, as a body comes into it, its pictures load, or it wraps
    /// again at a new width. A letter he opens grows below its own
    /// line, which does not move. The place kept is the letter's: inside a
    /// long letter, a new width shows other words at the top, as it does in
    /// a letter alone (B-066). WebKit's own anchoring is off in the
    /// document, so he is never moved twice.
    ///
    /// `bmFill` and `bmAppend` are defined here as well, in the same world,
    /// where `ConversationDocument.Fill` and `ConversationDocument.Append`
    /// call them. `bmAppend` puts letters that came while the stack was
    /// open at its bottom, and wires their lines.
    static let script = """
    function bmToggle(section) {
      var opening = !section.classList.contains('bm-open');
      section.classList.toggle('bm-open');
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bmLetter) {
        window.webkit.messageHandlers.bmLetter.postMessage({ id: section.id, open: opening });
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
    var bmOpening = null;
    var bmSet = null;
    var bmPlace = null;
    var bmWatch = null;
    function bmTake() {
      bmPlace = null;
      var letters = document.querySelectorAll('body > .bm-letter');
      for (var i = 0; i < letters.length; i++) {
        var box = letters[i].getBoundingClientRect();
        if (box.bottom > 0) { bmPlace = { section: letters[i], top: box.top }; return; }
      }
    }
    function bmKeep() {
      if (bmOpening) {
        window.scrollTo(0, window.pageYOffset + bmOpening.getBoundingClientRect().top);
        bmSet = window.pageYOffset;
      } else if (bmPlace) {
        var moved = bmPlace.section.getBoundingClientRect().top - bmPlace.top;
        if (moved !== 0) window.scrollBy(0, moved);
      }
      bmTake();
    }
    function bmLetGo() {
      if (!bmOpening) return;
      bmOpening = null;
      bmTake();
    }
    function bmWire(head) {
      head.addEventListener('click', function (event) {
        bmToggle(event.currentTarget.parentNode);
      });
      if (bmWatch) bmWatch.observe(head.parentNode);
    }
    function bmAppend(html) {
      var holder = document.createElement('div');
      holder.innerHTML = html;
      while (holder.firstElementChild) {
        var section = document.body.appendChild(holder.firstElementChild);
        var head = section.querySelector('.bm-head');
        if (head) bmWire(head);
      }
    }
    (function () {
      if (document.getElementById('bm')) return;
      if (window.ResizeObserver) bmWatch = new ResizeObserver(bmKeep);
      var heads = document.querySelectorAll('body > .bm-letter > .bm-head');
      for (var i = 0; i < heads.length; i++) bmWire(heads[i]);
      var opens = document.querySelector('head > meta[name="bm-opens"]');
      bmOpening = opens ? document.getElementById(opens.getAttribute('content')) : null;
      ['touchstart', 'mousedown', 'wheel', 'keydown'].forEach(function (name) {
        window.addEventListener(name, bmLetGo, { capture: true, passive: true });
      });
      window.addEventListener('scroll', function () {
        if (bmOpening && bmSet !== null && Math.abs(window.pageYOffset - bmSet) > 1) bmLetGo();
        else if (!bmOpening) bmTake();
      }, { passive: true });
      window.addEventListener('load', bmKeep);
      bmKeep();
    })();
    """

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
          <div class="bm-head">
            <span class="bm-from">\(escape(MailFormat.displayName(e.sender)))</span>
            <span class="bm-peek">\(escape(e.preview))</span>
            <span class="bm-when">\(escape(MailFormat.listTimestamp(e.date)))</span>
          </div>
          \(body)
        </div>
        """
    }

    /// A body going into its letter's section once the stack has loaded:
    /// `script`'s `bmFill`, called through `callAsyncJavaScript` with the
    /// section, the body and its kind as arguments.
    ///
    /// Arguments rather than a script with the body written into it. The
    /// body used to be escaped into a JavaScript string literal, one
    /// character at a time on the main thread: about 0.15 ms a kilobyte, so
    /// two frames for a 200 KB newsletter and a sixth of a second for a
    /// megabyte, and every character that could end the string, the line or
    /// the `<script>` element had to be caught. An argument goes across as a
    /// string and is never read as script, so there is nothing to catch.
    struct Fill: Equatable {
        let sectionID: String
        let body: Entry.Rendered

        /// What `callAsyncJavaScript` runs, in the app's content world,
        /// where `script` defined `bmFill`: the three names are its
        /// arguments.
        static let script = "bmFill(id, html, isHTML)"

        var arguments: [String: Any] {
            ["id": sectionID, "html": body.html, "isHTML": body.isHTML]
        }
    }

    /// Letters that came into the conversation while its stack was open,
    /// going in at the bottom (B-074): `script`'s `bmAppend`, called through
    /// `callAsyncJavaScript` with their sections as the argument. Each is
    /// drawn as the stack draws its letters at the start, from its row, the
    /// body to come by `Fill`.
    struct Append: Equatable {
        let html: String

        init(_ entries: [Entry]) {
            html = entries.map(ConversationDocument.section).joined()
        }

        /// What `callAsyncJavaScript` runs, in the app's content world,
        /// where `script` defined `bmAppend`.
        static let script = "bmAppend(html)"

        var arguments: [String: Any] { ["html": html] }
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
