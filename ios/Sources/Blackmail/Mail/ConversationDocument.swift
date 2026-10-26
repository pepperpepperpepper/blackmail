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
/// that world alone, or to `bmPicture`, by which it says a picture was
/// tapped (B-122). The lines are wired with `addEventListener`, since an
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
        /// For a letter of his from another folder, Sent Mail, brought into
        /// an Inbox conversation (B-104): that folder's name, as the
        /// Mailboxes pane shows it, said over the letter once it is open.
        /// Nil for the conversation's own letters.
        var foundIn: String? = nil

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
    /// conversation's order turned over. That order is the order the server
    /// took the letters (`MessageThread.group`, B-084), which is their
    /// dates' order but for a letter dated wrong; turned over, it keeps at
    /// the bottom the letter the conversation's row stands for, the one he
    /// tapped the row to read. It was the folder's order, by UID, until
    /// B-084, and a conversation put in the folder out of turn, as Edit
    /// mode's Delete put one in Trash, ran upside down.
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

    // MARK: - His letters from Sent Mail

    /// An Inbox conversation's stack with his own letters of it from Sent
    /// Mail among its letters, as Mail's Complete Threads has them (B-104):
    /// each where it came, by when Gmail took it and by its Date where it
    /// took two at once, the oldest at the top; closed to its line. The
    /// conversation's own letters are as `stack(of:)` draws them, in its
    /// order, open and closed as there. For the stack's first frame, when
    /// they are known by then; otherwise they go in as they come
    /// (`places`, `Insert`).
    static func stack(of thread: MessageThread, related: RelatedLetters?) -> [Entry] {
        let own = stack(of: thread)
        guard let related, !related.letters.isEmpty else { return own }
        let placed = places(of: related.letters, among: Array(thread.messages.reversed()))
        func his(before id: String?) -> [Entry] {
            placed.filter { $0.before == id }.flatMap { place in
                place.letters.map { entry(forHis: $0, foundIn: related.folderName) }
            }
        }
        return own.flatMap { his(before: $0.id) + [$0] } + his(before: nil)
    }

    /// Where his letters go among the stack's, `stack` in its order, the
    /// oldest first: each before the first of the stack's letters that came
    /// after it, or after the last, `before` nil. In runs, oldest first, a
    /// run for each letter they go before.
    static func places(of letters: [MessageSummary],
                       among stack: [MessageSummary]) -> [Place] {
        let oldestFirst = letters.sorted { CompleteThreads.isLater($1, than: $0) }
        var out: [Place] = []
        for letter in oldestFirst {
            let before = stack.first(where: { CompleteThreads.isLater($0, than: letter) })?.id
            if let last = out.last, last.before == before {
                out.removeLast()
                out.append(Place(before: before, letters: last.letters + [letter]))
            } else {
                out.append(Place(before: before, letters: [letter]))
            }
        }
        return out
    }

    /// A run of his letters, and the id of the stack's letter they go
    /// before; nil for after the last.
    struct Place: Equatable {
        let before: String?
        let letters: [MessageSummary]
    }

    /// The id of his letter's entry in the stack: the letter's own,
    /// `"<uidvalidity>/<uid>"` in Sent Mail, after an "r". So its section
    /// is "mr…", which no letter of the conversation's, "m" and a digit,
    /// can be, whatever the two folders' numbers.
    static func relatedID(of letter: MessageSummary) -> String {
        "r" + letter.id
    }

    /// His letter's place in the stack, drawn from its row: closed, with
    /// the folder it was found in.
    static func entry(forHis letter: MessageSummary, foundIn folder: String) -> Entry {
        Entry(id: relatedID(of: letter), sender: letter.sender, date: letter.date, body: nil,
              isExpanded: false, preview: letter.preview, foundIn: folder)
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
    ///
    /// With his letters from Sent Mail in the stack (B-104), the letter it
    /// opens at is still one of the conversation's own: the first of them
    /// open, his being closed as the stack opens, and passed over if he had
    /// opened one before WebKit lost the page. The line held above it is the
    /// line directly above it, his or theirs. So the letter it opens at is
    /// one line below the top of the pane whether his letters are in the
    /// first frame or go in after it: put in later between that line and
    /// the letter, they take the line's place at the top, and the letter
    /// stays where it is (`script`, `bmInsert`). Counted by the
    /// conversation's letters alone, as first built, the stack opened at its
    /// own line above the letter, his line went in under it, and the letter
    /// he was reading dropped by a line a second or two after it had come.
    static func opensAt(_ entries: [Entry]) -> String? {
        guard let at = entries.firstIndex(where: { $0.isExpanded && $0.foundIn == nil })
                ?? entries.lastIndex(where: { $0.foundIn == nil }) else { return nil }
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
                     -webkit-tap-highlight-color: transparent;
                     display: flex; align-items: baseline; gap: 8px; }
          /* A line is not text to select, as Mail's are not, and has no
             callout (B-095): a finger held on one began WebKit's selection
             of a word at about 0.7 s, and its Copy menu at 1.4 s. The
             stack's own lines and everything in them; the letters' bodies
             stay selectable. Important, as the pictures' width is: a
             sender's own style sheet applies to the whole stack, and its
             important rule on * or div would beat these otherwise. */
          body > .bm-letter > .bm-head, body > .bm-letter > .bm-head * {
                     -webkit-user-select: none !important; user-select: none !important;
                     -webkit-touch-callout: none !important; }
          /* The line lit under the finger, by the stack's script, from the
             touch until it lifts (B-095). WebKit's own tap highlight, which
             was given this colour, is never painted on a line: it leaves
             out anything but a link or a control that spans more than 30%
             of the pane, and a line spans all of it. Important, for the
             sender's style sheet, as above. */
          body > .bm-letter > .bm-head.bm-press { background: rgba(255,255,255,0.08) !important; }
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
             inverted twice. The invert a letter on its own has too, the one
             string (SignatureSheet.invert). */
          .bm-html { filter: \(SignatureSheet.invert); background: #fff;
                     color: #000; }
          .bm-html img, .bm-html video, .bm-html svg, .bm-html picture,
          .bm-html [style*="background-image"] {
                     filter: \(SignatureSheet.invert); }
          /* A signature's white sheet is inverted with the rest of its
             letter, as Mail draws it: no rule of its own (B-146). */
          /* Mail's bars beside quoted text (B-101): a letter's HTML in its
             light colours, which the invert turns; a plain letter's quotes,
             Mail's blockquotes too (PlainQuotes, B-147), in its dark ones,
             as a plain letter is not inverted. */
        \(QuoteBars.css(in: ".bm-html"))
        \(QuoteBars.css(in: ".bm-text", palette: QuoteBars.dark))
          .bm-body img, .bm-body table { max-width: 100% !important; height: auto; }
          .bm-text a { color: #0A84FF; }
          .bm-html a { color: #007AFF; }
          .bm-waiting { color: #8e8e93; padding: 0 \(inset)px \(inset)px \(inset)px; }
          /* Where his letter from another folder was found, over it once
             it is open (B-104): grey, as the time on the line. */
          .bm-found { color: #8e8e93; font-size: \(bodyPointSize - 3)px;
                      padding: 0 \(inset)px 8px \(inset)px; }
          .bm-letter:not(.bm-open) > .bm-found { display: none; }
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
    /// gets none of this from the script, only its pictures wired (below).
    /// The line toggles its letter
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
    /// bar tapped, VoiceOver's scroll. The header changing height scrolls
    /// nothing since B-128 (`StackPlace`): the stack hangs from it, and the
    /// letter held stays at the top of the pane. The script notes where it
    /// put the page, and a scroll to anywhere else lets go. Without that
    /// the hold went on, and the next letter to grow pulled him back to
    /// where the stack opened. From then
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
    ///
    /// `bmInsert`, which `ConversationDocument.Insert` calls, puts his
    /// letters from Sent Mail in among the stack's (B-104): before the
    /// section named, a letter of the stack's own, or at the bottom for
    /// none; nothing at all if the section named is not one of the stack's.
    /// Their lines are wired as the rest are, and the letter he is reading
    /// is kept where it is on the glass at once. When the section named
    /// begins on the glass with nothing above it there but closed lines
    /// (`bmReading`), that is the section named: the lines above it give
    /// way upwards, and if the stack is still holding the line it opened
    /// at, the hold passes to the last of his lines, now directly above the
    /// letter, as the first frame has it when they are known by then
    /// (`opensAt`). That is the usual stack, opened at the line of a letter
    /// he has read with the newest under it, and his reply between the two.
    /// Otherwise, with an open letter above the place on the glass, or the
    /// place off the glass, the line held, or the letter at the top once he
    /// has touched the pane, stays where it is (`bmKeep`), and what is below
    /// the place moves down.
    ///
    /// **Held while the stack moves** (B-104, seen on the iPad 2026-10-22).
    /// While a finger drags the pane, or the stack coasts after it, the
    /// page's offset is WKWebView's scroll view's, in another process, and
    /// a `scrollBy` of the script's made then is lost: the letter he was
    /// reading dropped a line as his line went in, and went on with the
    /// finger from there. So `bmInsert` holds what it is given while the
    /// stack moves (`bmMoving`): while the pane's last word said its scroll
    /// view moves the stack, a finger on it, dragging, coasting or bouncing
    /// back (`Motion`, `bmPaneMoving`), or a second after a word never
    /// followed; while a finger is on the page, from its touch to the
    /// touchend or touchcancel that leaves none, or five seconds after the
    /// last of its touches if WebKit never says it went; and while a scroll
    /// not the script's own came in the last quarter of a second, as a
    /// coast's do. The page alone does not hear enough: a finger put down
    /// at the tap lands on the page before the stack's, which then hears
    /// none of its touches, a finger held still sends no scroll, and nor
    /// does a bounce at the top. It looks again every tenth of a second
    /// (`bmRelease`) and puts them in once the stack is still, as at rest,
    /// where the `scrollBy` holds. What comes while one is held waits
    /// behind it, in the order it came, so the page keeps the pane's
    /// order: more of his letters, letters for the bottom (`bmAppend`), and
    /// a body for a section not on the page yet (`bmFill`), which would
    /// otherwise find nothing; a body for a letter on the page goes in at
    /// once, as the lines' dates are written again at once, and again
    /// behind what is held (`bmWhen`, B-139). Each runs once, and one that
    /// throws takes none of the rest with it. What is held is the page's
    /// own: a new page, another letter or the stack drawn again, starts
    /// with nothing held, and the pane's document has his letters for a
    /// redraw (`PaneDocument.insert`). With
    /// nothing moving nothing is held, so the stack opened and left alone
    /// takes them at once, as it did.
    ///
    /// **A finger on a line** (B-095). The line is lit from the touch until
    /// the finger lifts, and the lift opens or closes it, the script's own
    /// doing and not WebKit's: WebKit paints no tap highlight on an element
    /// as wide as the pane, and what it does with a touch held a second,
    /// the line no longer selectable, is UIKit's, not in its source. A
    /// touch on a line that lifts within `bmHold` of landing, the finger
    /// still to 10 px, is the tap: the script toggles the letter itself,
    /// and stops WebKit's own tap by its `preventDefault`, which WebKit's
    /// tap waits for. A selection he made in a letter goes at the tap, as
    /// it went at WebKit's. After a touch the script took, the first click
    /// on any line is let pass if it is on that touch's line, within a
    /// second, before another touch, so a tap never toggles twice even if
    /// WebKit's click came anyway; a click on another line, or after the
    /// next touch, toggles as it did. Nothing is done, and the light goes,
    /// for a finger that moves, a scroll of the page, a second finger, a
    /// touch WebKit cancels, a touch that lands on a page still scrolling,
    /// which only stops it, or a line moved under the finger as letters
    /// above it grew; past `bmHold` the light goes and the lift does
    /// nothing. Nor for a touch on a line that lands within `bmShiftQuiet`,
    /// a second, of the pane's word that the header over the stack changed
    /// height, or is down as the word comes (`Shift`, `bmPaneShifted`): the
    /// whole stack moved on the glass by the header's change then, which
    /// the page cannot see, its own coordinates not changing, and a second
    /// tap made at once where the first was is on another line than the
    /// one it was meant for. Not lit, and its lift stops WebKit's tap and
    /// toggles nothing; a touch after the second is a tap again. The touches are heard on the window, as `bmLetGo`'s are,
    /// not on the lines: VoiceOver's activation sends a line a touch rather
    /// than its click when the line or a node above it has a touch
    /// listener, and the window is not a node. So VoiceOver's activation
    /// is the click it was, as is a click from a pointer. Only lines
    /// `bmWire` wired are lit or toggled, those `bmAppend` puts in among
    /// them.
    ///
    /// **A picture tapped** (B-122). On every page the pane loads, a
    /// letter's own or a stack, each `<img>` whose `src` is the loader's
    /// address (`InlineImageRewriter`), a picture of the letter's own parts,
    /// is given a click listener: as the document ends, and as `bmFill`
    /// puts a body in, the only way a body goes into a stack (`bmAppend`
    /// and `bmInsert` put in lines over "Loading…"). The `src` as WebKit
    /// reads it (`img.src`), the address the loader is asked for, with the
    /// spaces a sender left around it trimmed, rather than the attribute as
    /// written, which with a space before it would not be seen as the
    /// loader's. Not one inside a link, an image map or a button, whose tap
    /// is theirs; nor a picture from the web. A link is an `<a>` with an
    /// `href`: one with none, a bookmark such as Outlook and Word wrap a
    /// signature or a letter quoted in (`<a name="_MailAutoSig">`), is no
    /// link, and a tap there goes nowhere in WebKit. The click, which
    /// WebKit makes of a tap as it makes a link's, and not of a drag or a
    /// touch and hold, tells the pane through `bmPicture` the picture's
    /// address, the section it is in, "" on a letter's own page, and its
    /// sizes, its own and as drawn; the pane decides what opens
    /// (`PanePictures`). The section is the one that is the body's own
    /// child, so a letter's markup cannot name another letter's. The
    /// wiring never throws, so nothing a letter holds stops a body going in
    /// or the stack's lines being wired.
    ///
    /// **A picture held** (B-150). Each picture wired for a tap has
    /// WebKit's own menu kept off it, `-webkit-touch-callout: none`, and
    /// its selection, both on the picture itself and important, which no
    /// rule of a letter's outranks. A finger that lands on it alone and
    /// stays within 10 px of where it landed for `bmPictureHold`, half a
    /// second, UIKit's own for a touch and hold, is a hold: the script
    /// tells the pane through `bmPicture` as of a tap, with `hold` and
    /// where the finger is in the web view, its place in the page's
    /// viewport scaled by a pinch (`visualViewport`), and the pane puts up
    /// Mail's menu there (`PanePictures.menu`). The lift after a hold stops
    /// WebKit's own tap by its `preventDefault`, and a click on the picture
    /// before the next touch opens nothing, so a hold never opens Quick
    /// Look as well. A second finger, a finger that moves, a lift before
    /// the half second, or a touch WebKit cancels is no hold; nor a finger
    /// that lands on a page still scrolling, as on a line, which only
    /// stops it, as UIKit gives such a touch to the scroll view: the
    /// page's scrolls are heard on every page for it (`bmScroll`), and a
    /// scroll the stack's script made itself is none. The touches are
    /// heard on the window, as the lines' are, on every page. A picture
    /// from the web, in a link, an image map or a button is not wired, and
    /// keeps WebKit's menu.
    ///
    /// **A file's row coming** (B-148). While the pane downloads a file,
    /// `bmFileBusy`, called through `callAsyncJavaScript` (`BodyFiles.Busy`),
    /// dims each link on the page to it, the row the pane made of the
    /// file's mark among the words, important, and puts the pane's word
    /// for something on its way after its name; once the file has opened
    /// or been let go, it takes both off again. Each mark it put in is
    /// kept, so it takes off its own and nothing of the letter's, and a
    /// file shown coming twice has one mark. On any page, in a letter's own
    /// or a body `bmFill` put in; a link with no row on the page changes
    /// nothing, and it never throws.
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
      if (!el) {
        if (bmHeld.length) bmLater(function () { bmFill(id, html, isHTML); });
        return;
      }
      var body = el.querySelector('.bm-body');
      if (!body) return;
      body.className = 'bm-body ' + (isHTML ? 'bm-html' : 'bm-text');
      body.innerHTML = html;
      bmWirePictures(body);
    }
    function bmWhen(when) {
      var letters = document.querySelectorAll('body > .bm-letter');
      for (var i = 0; i < letters.length; i++) {
        var words = when[letters[i].id];
        if (typeof words !== 'string') continue;
        for (var head = letters[i].firstElementChild; head; head = head.nextElementSibling) {
          if (!head.classList.contains('bm-head')) continue;
          for (var line = head.firstElementChild; line; line = line.nextElementSibling) {
            if (line.classList.contains('bm-when') && line.textContent !== words) line.textContent = words;
          }
        }
      }
      if (bmHeld.length) bmLater(function () { bmWhen(when); });
    }
    var bmOpening = null;
    var bmSet = null;
    var bmPlace = null;
    var bmWatch = null;
    var bmMine = null;
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
      bmMine = window.pageYOffset;
      bmTake();
    }
    function bmLetGo() {
      if (!bmOpening) return;
      bmOpening = null;
      bmTake();
    }
    var bmLines = [];
    var bmPress = null;
    var bmQuiet = null;
    var bmScrolled = -1e9;
    var bmHold = 1200;
    var bmShifted = -1e9;
    var bmShiftQuiet = 1000;
    function bmLineAt(node) {
      for (; node && node !== document.body; node = node.parentNode) {
        if (bmLines.indexOf(node) !== -1) return node;
      }
      return null;
    }
    function bmUnpress() {
      if (!bmPress) return;
      clearTimeout(bmPress.timer);
      bmPress.head.classList.remove('bm-press');
      bmPress = null;
    }
    function bmStill(press, touch) {
      return !!touch && Math.abs(touch.clientX - press.x) <= 10 && Math.abs(touch.clientY - press.y) <= 10;
    }
    function bmPressDown(event) {
      bmUnpress();
      bmQuiet = null;
      if (event.touches.length !== 1 || performance.now() - bmScrolled < 200) return;
      var head = bmLineAt(event.target);
      if (!head) return;
      var touch = event.touches[0];
      var shifted = performance.now() - bmShifted < bmShiftQuiet;
      if (!shifted) head.classList.add('bm-press');
      bmPress = { head: head, x: touch.clientX, y: touch.clientY, shifted: shifted,
                  top: head.getBoundingClientRect().top, at: performance.now(),
                  timer: setTimeout(function () { head.classList.remove('bm-press'); }, bmHold) };
    }
    function bmPaneShifted() {
      bmShifted = performance.now();
      if (!bmPress) return;
      bmPress.shifted = true;
      bmPress.head.classList.remove('bm-press');
    }
    function bmPressMove(event) {
      if (bmPress && (event.touches.length !== 1 || !bmStill(bmPress, event.touches[0]))) bmUnpress();
    }
    function bmPressUp(event) {
      var press = bmPress;
      if (!press) return;
      bmUnpress();
      if (event.touches.length !== 0 || !bmStill(press, event.changedTouches[0])) return;
      event.preventDefault();
      bmQuiet = { head: press.head, until: performance.now() + 1000 };
      if (performance.now() - press.at > bmHold) return;
      if (press.shifted) return;
      if (Math.abs(press.head.getBoundingClientRect().top - press.top) > 10) return;
      var selection = window.getSelection();
      if (selection && !selection.isCollapsed) selection.removeAllRanges();
      bmToggle(press.head.parentNode);
    }
    function bmScroll() {
      if (bmMine !== null && Math.abs(window.pageYOffset - bmMine) <= 1) return;
      bmScrolled = performance.now();
      bmUnpress();
    }
    var bmHeld = [];
    var bmHeldTimer = null;
    var bmFingers = 0;
    var bmFingered = -1e9;
    var bmPane = -1e9;
    var bmSettle = 250;
    var bmLostTouch = 5000;
    var bmPaneLapse = 1000;
    function bmFinger(event) {
      bmFingers = event.touches.length;
      bmFingered = performance.now();
    }
    function bmPaneMoving(moving) {
      bmPane = moving ? performance.now() : -1e9;
    }
    function bmMoving() {
      var now = performance.now();
      return now - bmScrolled < bmSettle || (bmFingers > 0 && now - bmFingered < bmLostTouch)
        || now - bmPane < bmPaneLapse;
    }
    function bmLater(change) {
      bmHeld.push(change);
      if (bmHeldTimer === null) bmHeldTimer = setTimeout(bmRelease, 100);
    }
    function bmRelease() {
      bmHeldTimer = null;
      if (bmMoving()) { bmHeldTimer = setTimeout(bmRelease, 100); return; }
      var held = bmHeld;
      bmHeld = [];
      for (var i = 0; i < held.length; i++) {
        try { held[i](); } catch (e) {}
      }
    }
    function bmWire(head) {
      bmLines.push(head);
      head.addEventListener('click', function (event) {
        var quiet = bmQuiet;
        bmQuiet = null;
        if (quiet && quiet.head === event.currentTarget && performance.now() < quiet.until) return;
        bmToggle(event.currentTarget.parentNode);
      });
      if (bmWatch) bmWatch.observe(head.parentNode);
    }
    function bmAppend(html) {
      if (bmHeld.length) { bmLater(function () { bmAppend(html); }); return; }
      var holder = document.createElement('div');
      holder.innerHTML = html;
      while (holder.firstElementChild) {
        var section = document.body.appendChild(holder.firstElementChild);
        var head = section.querySelector('.bm-head');
        if (head) bmWire(head);
      }
    }
    function bmInsert(html, beforeID) {
      if (bmHeld.length || bmMoving()) { bmLater(function () { bmInsert(html, beforeID); }); return; }
      var at = null;
      if (beforeID) {
        var letters = document.querySelectorAll('body > .bm-letter');
        for (var i = 0; i < letters.length; i++) {
          if (letters[i].id === beforeID) { at = letters[i]; break; }
        }
        if (!at) return;
      }
      var still = bmReading(at) ? at.getBoundingClientRect().top : null;
      var holder = document.createElement('div');
      holder.innerHTML = html;
      var last = null;
      while (holder.firstElementChild) {
        last = document.body.insertBefore(holder.firstElementChild, at);
        var head = last.querySelector('.bm-head');
        if (head) bmWire(head);
      }
      if (still !== null && last) {
        if (bmOpening) {
          bmOpening = last;
        } else {
          var moved = at.getBoundingClientRect().top - still;
          if (moved !== 0) window.scrollBy(0, moved);
          bmTake();
        }
      }
      bmKeep();
    }
    function bmReading(at) {
      if (!at) return false;
      var top = at.getBoundingClientRect().top;
      if (!(top > 0 && top < window.innerHeight)) return false;
      for (var s = at.previousElementSibling; s; s = s.previousElementSibling) {
        if (s.getBoundingClientRect().bottom <= 0) break;
        if (s.classList.contains('bm-open')) return false;
      }
      return true;
    }
    var bmComing = [];
    function bmFileBusy(link, busy, words) {
      try {
        for (var i = bmComing.length - 1; i >= 0; i--) {
          if (bmComing[i].link !== link) continue;
          var was = bmComing.splice(i, 1)[0];
          if (was.mark.parentNode) was.mark.parentNode.removeChild(was.mark);
          was.row.style.removeProperty('opacity');
        }
        if (!busy) return;
        var links = document.querySelectorAll('a');
        for (var j = 0; j < links.length; j++) {
          if (links[j].getAttribute('href') !== link) continue;
          var mark = document.createElement('span');
          mark.textContent = ' ' + words;
          links[j].appendChild(mark);
          links[j].style.setProperty('opacity', '0.5', 'important');
          bmComing.push({ link: link, row: links[j], mark: mark });
        }
      } catch (e) {}
    }
    function bmPictureIn(node) {
      for (; node && node.parentNode; node = node.parentNode) {
        if (node.parentNode === document.body) {
          return node.classList && node.classList.contains('bm-letter') ? node.id : '';
        }
      }
      return '';
    }
    function bmPictureSrc(img) {
      return String(img.src || '');
    }
    function bmOwnPicture(img) {
      if (bmPictureSrc(img).slice(0, 8).toLowerCase() !== 'bmcid://') return false;
      if (img.getAttribute('usemap') !== null) return false;
      for (var node = img.parentNode; node && node !== document.body; node = node.parentNode) {
        var tag = String(node.tagName || '').toLowerCase();
        if ((tag === 'a' && node.getAttribute('href') !== null) || tag === 'button') return false;
      }
      return true;
    }
    function bmPictureTapped(event) {
      var img = event.currentTarget;
      if (!bmOwnPicture(img)) return;
      if (bmPictureHeld === img) { bmPictureHeld = null; return; }
      if (!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bmPicture)) return;
      var drawn = img.getBoundingClientRect();
      window.webkit.messageHandlers.bmPicture.postMessage({
        src: bmPictureSrc(img), section: bmPictureIn(img),
        width: img.naturalWidth, height: img.naturalHeight,
        drawnWidth: drawn.width, drawnHeight: drawn.height });
    }
    function bmWirePictures(root) {
      try {
        var pictures = root.querySelectorAll('img');
        for (var i = 0; i < pictures.length; i++) {
          if (!bmOwnPicture(pictures[i])) continue;
          pictures[i].addEventListener('click', bmPictureTapped);
          pictures[i].style.setProperty('-webkit-touch-callout', 'none', 'important');
          pictures[i].style.setProperty('-webkit-user-select', 'none', 'important');
        }
      } catch (e) {}
    }
    var bmPictureHolding = null;
    var bmPictureHeld = null;
    var bmPictureHold = 500;
    function bmPictureLetGo() {
      if (!bmPictureHolding) return;
      clearTimeout(bmPictureHolding.timer);
      bmPictureHolding = null;
    }
    function bmPictureDown(event) {
      bmPictureLetGo();
      bmPictureHeld = null;
      if (event.touches.length !== 1 || performance.now() - bmScrolled < 200) return;
      var img = event.target;
      if (!img || String(img.tagName || '').toLowerCase() !== 'img' || !bmOwnPicture(img)) return;
      var touch = event.touches[0];
      var holding = { img: img, x: touch.clientX, y: touch.clientY };
      holding.timer = setTimeout(function () { bmPictureHeldDown(holding); }, bmPictureHold);
      bmPictureHolding = holding;
    }
    function bmPictureHeldDown(holding) {
      if (bmPictureHolding !== holding) return;
      bmPictureHolding = null;
      var img = holding.img;
      bmPictureHeld = img;
      if (!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bmPicture)) return;
      var drawn = img.getBoundingClientRect();
      var view = window.visualViewport;
      var scale = view && view.scale > 0 ? view.scale : 1;
      window.webkit.messageHandlers.bmPicture.postMessage({
        src: bmPictureSrc(img), section: bmPictureIn(img),
        width: img.naturalWidth, height: img.naturalHeight,
        drawnWidth: drawn.width, drawnHeight: drawn.height, hold: true,
        x: (holding.x - (view ? view.offsetLeft : 0)) * scale,
        y: (holding.y - (view ? view.offsetTop : 0)) * scale });
    }
    function bmPictureMove(event) {
      if (bmPictureHolding && (event.touches.length !== 1 || !bmStill(bmPictureHolding, event.touches[0]))) {
        bmPictureLetGo();
      }
    }
    function bmPictureUp(event) {
      bmPictureLetGo();
      if (bmPictureHeld && event.touches.length === 0) event.preventDefault();
    }
    (function () {
      if (document.body) bmWirePictures(document.body);
      window.addEventListener('scroll', bmScroll, { passive: true });
      window.addEventListener('touchstart', bmPictureDown, { capture: true, passive: true });
      window.addEventListener('touchmove', bmPictureMove, { capture: true, passive: true });
      window.addEventListener('touchend', bmPictureUp, { capture: true, passive: false });
      window.addEventListener('touchcancel', bmPictureLetGo, { capture: true, passive: true });
    })();
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
      window.addEventListener('touchstart', bmPressDown, { capture: true, passive: true });
      window.addEventListener('touchmove', bmPressMove, { capture: true, passive: true });
      window.addEventListener('touchend', bmPressUp, { capture: true, passive: false });
      window.addEventListener('touchcancel', bmUnpress, { capture: true, passive: true });
      ['touchstart', 'touchmove', 'touchend', 'touchcancel'].forEach(function (name) {
        window.addEventListener(name, bmFinger, { capture: true, passive: true });
      });
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

        // His letter from another folder says where it was found, between
        // its line and its body, shown with the body: words of the page's
        // own, read by VoiceOver before the letter, and left alone by
        // `bmFill`, which fills the body.
        let found = e.foundIn.map {
            "<div class=\"bm-found\">\(escape(CompleteThreads.foundIn($0)))</div>"
        } ?? ""

        return """
        <div class="bm-letter\(open)" id="\(id)">
          <div class="bm-head">
            <span class="bm-from">\(escape(MailFormat.displayName(e.sender)))</span>
            <span class="bm-peek">\(escape(e.preview))</span>
            <span class="bm-when">\(escape(MailFormat.listTimestamp(e.date)))</span>
          </div>
          \(found)\(body)
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

    /// The date on each letter's line written again where it is, as the
    /// iPad writes it now (B-139): after its 24-Hour Time switch, its time
    /// zone or its region has changed, and as the day turns over, so a line
    /// of 11:50 PM reads "Yesterday" once midnight has passed. `script`'s
    /// `bmWhen`, called through `callAsyncJavaScript` with the words for
    /// each section, as `section` writes them.
    ///
    /// The words alone change: nothing is drawn again, no letter opens or
    /// closes, no body is touched or asked for, and the stack does not
    /// move, a line's date being one line that does not wrap. Only the
    /// stack's own lines: the section a body's child, its line the
    /// section's, its date the line's, so a letter's markup with a
    /// `bm-when` of its own is left alone. Sections that `bmInsert` or
    /// `bmAppend` is holding while the stack moves are written as they go
    /// in, `bmWhen` waiting behind them.
    struct Dates: Equatable {
        /// Each letter's section and its line's date.
        let when: [String: String]

        /// The lines of `entries`, written for `now`, in `locale` and
        /// `timeZone`: the clock and the iPad's unless a test hands in others.
        init(_ entries: [Entry], now: Date = Date(), locale: Locale = .current,
             timeZone: TimeZone = .current) {
            var when: [String: String] = [:]
            for e in entries {
                when[ConversationDocument.sectionID(for: e.id)] =
                    MailFormat.listTimestamp(e.date, now: now, locale: locale, timeZone: timeZone)
            }
            self.when = when
        }

        /// What `callAsyncJavaScript` runs, in the app's content world,
        /// where `script` defined `bmWhen`.
        static let script = "bmWhen(when)"

        var arguments: [String: Any] { ["when": when] }
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

    /// His letters from Sent Mail going into the stack once it has loaded
    /// (B-104): `script`'s `bmInsert`, called through `callAsyncJavaScript`
    /// with their sections and the section they go before, "" for after the
    /// last letter. Each is drawn as the stack draws its letters at the
    /// start, closed, its body to come by `Fill` once he opens it.
    struct Insert: Equatable {
        let html: String
        /// The section they go before, "" for none.
        let before: String

        init(_ entries: [Entry], before entryID: String?) {
            html = entries.map(ConversationDocument.section).joined()
            before = entryID.map(ConversationDocument.sectionID) ?? ""
        }

        /// What `callAsyncJavaScript` runs, in the app's content world,
        /// where `script` defined `bmInsert`: the pane's word on its scroll
        /// view first (`Motion`), so the script holds them if it is moving
        /// the stack, then the letters.
        static let script = "bmPaneMoving(moving); bmInsert(html, before)"

        /// `moving`, whether the pane's scroll view is moving the stack as
        /// they are sent (`Motion.stack`).
        func arguments(moving: Bool) -> [String: Any] {
            ["html": html, "before": before, "moving": moving]
        }
    }

    /// What the pane tells the stack's script of its scroll view (B-104,
    /// the second change of 2026-10-22). While a finger drags the stack, or
    /// it coasts or bounces back after one, a `scrollBy` of the script's is
    /// lost, and the script can hear that only by the page's own touches
    /// and scrolls. A finger put down at the tap lands on the page before
    /// the stack's, and the stack's page hears none of its touches; a
    /// finger held still sends no scroll, nor does a bounce at the top.
    /// UIKit's scroll view knows all of them, and always ends them. So
    /// the pane says, with each `Insert`, whether it is moving the stack,
    /// and while it is, every tenth of a second, until it says it is still;
    /// the script holds what goes in for as long as the last word said it
    /// moves (`bmPaneMoving`), and a second at most after a word that was
    /// never followed.
    enum Motion {
        /// Moving the stack: UIKit's scroll view tracking a finger on it,
        /// dragging, or decelerating, which is taken to count the bounce
        /// back from an edge too.
        static func stack(tracking: Bool, dragging: Bool, decelerating: Bool) -> Bool {
            tracking || dragging || decelerating
        }

        /// How often the pane looks again while it moves, in seconds.
        static let every: TimeInterval = 0.1

        /// What `callAsyncJavaScript` runs each time it looks, in the app's
        /// content world, where `script` defined `bmPaneMoving`.
        static let script = "bmPaneMoving(moving)"

        static func arguments(_ moving: Bool) -> [String: Any] { ["moving": moving] }
    }

    /// What the pane tells the stack's script when the header over the
    /// stack has changed height (B-128, `keepPlace`). The stack hangs from
    /// the header, so the whole of it moves on the glass then, by a Cc line
    /// about 20 pt, a file's row 44 pt, or both and more, at the tap on a
    /// line since B-129. A second tap made at once where the first was, a
    /// double tap or a tap to close a letter opened by mistake, lands that
    /// far off the line it was meant for, on the line above or below, and
    /// opened that letter, which took the header and the toolbar, so a
    /// Delete or a Move after it went to a letter he did not mean to open. The page cannot see that move: the web view moves on the
    /// glass, and nothing in the page does. So the script is told, and a
    /// line pressed within a second of it does nothing (`bmPaneShifted`,
    /// `bmShiftQuiet`), nor one pressed as it comes.
    enum Shift {
        /// What `callAsyncJavaScript` runs, in the app's content world,
        /// where `script` defined `bmPaneShifted`.
        static let script = "bmPaneShifted()"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
