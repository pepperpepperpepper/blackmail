import Foundation

/// What the reading pane's web view holds, the letters' bodies waiting to go
/// into it, and what to draw again when WebKit loses it.
///
/// Out of `MessageDetailViewController` for the reason `PaneLoads` is: the
/// controller is UIKit and WebKit, and does not exist on the machine the
/// suite runs on.
///
/// Two things went wrong with the document here, and both left a letter
/// that never appeared.
///
/// A conversation's bodies are put into their sections by script once they
/// come (`ConversationDocument.javascriptFill`). A body that came before the
/// stack's own document had finished loading ran against the page before
/// it, found no section, and was lost: the letter said "Loading…" for good,
/// or until he closed and opened it again. It is likelier the faster the
/// body comes, and a letter already downloaded comes at once. Now a body is
/// held until the document it is for has finished loading, and dropped with
/// it if another document replaces it first.
///
/// And the web view's content runs in a process of WebKit's own, which iOS
/// ends when it needs the memory, typically while he is in another app with
/// photographs, and more often on a smaller iPad. Nothing answered for that,
/// so he could come back to a black pane, or to a conversation stuck on
/// "Loading…", with the letter's header still over it. The pane holds
/// everything it drew, so it draws it again from that, without fetching a
/// letter again, once he can see it (`redraw`).
///
/// A conversation is drawn again as it was first drawn: the stack without
/// its bodies, and each body put into its section by script once the stack
/// has loaded, never written into the document itself. Script puts a body
/// in as a fragment, which keeps a sender's broken markup inside its own
/// section. Written into the document, a stray `</div>` would close the
/// letter's section early and show the rest of it under a closed letter,
/// an unclosed `<div>` would put every later letter inside it and hide them
/// with it, and an unclosed comment or `<style>` would swallow the page's
/// own script, so that no letter could be opened and no body put in. It
/// would also run a sender's `<script>`, and hold the page's loading, and
/// every body waiting on it, until each remote picture had come.
///
/// The letter itself can be what ends the process, as a stack of full-size
/// photographs can on an iPad with little memory, and drawing it again
/// would only end it again, over and over, each time asking the server for
/// its pictures anew. So a document that was drawn again is not drawn a
/// third time if it is lost again while it loads or soon after (`settle`):
/// the pane says it could not be shown.
struct PaneDocument {

    enum Content {
        /// Nothing of the pane's: no document yet, or none left to draw
        /// again after WebKit lost one.
        case nothing
        /// The empty page the pane is cleared to.
        case blank
        /// Grey words in place of a letter: "Loading…", or why there is none.
        case notice([String])
        /// One letter.
        case letter(Message)
        /// A conversation's stack, with the bodies that have come and which
        /// letters are open.
        case conversation([ConversationDocument.Entry])
    }

    /// What to draw again after WebKit lost the document. For a
    /// conversation, `content` is the stack with no bodies in it, the page
    /// it was first drawn as, and `bodies` are the ones that had come, in
    /// the stack's order, to go back in by `fill` once it has loaded.
    struct Redraw {
        let content: Content
        let bodies: [(id: String, body: ConversationDocument.Entry.Rendered)]
    }

    /// What the pane says in place of a document drawn again and lost again.
    static let cannotShow = "This message could not be shown."

    /// How long, in seconds, a document drawn again has to have lasted once
    /// loaded for its loss to be taken as iOS wanting the memory once more,
    /// and drawn again, rather than as the letter ending the process.
    static let settle: TimeInterval = 10

    private(set) var content: Content = .nothing
    /// The load that put `content` in, as WebKit names it; nil when there
    /// was none to wait for.
    private var navigation: ObjectIdentifier?
    private var finished = true
    /// Scripts for bodies that came while the document was still loading.
    private var waiting: [String] = []
    /// The document went with WebKit's process and has not been drawn
    /// again. `content` is still what it held, and bodies that come
    /// meanwhile are kept in it for the redraw.
    private var lost = false

    /// Who drew the document on screen: the pane, or `redraw`, and then
    /// when it finished loading, nil while it is still loading.
    private enum Drawn {
        case byPane
        case again(finished: Date?)
    }
    private var drawn = Drawn.byPane
    /// Between `redraw` and the `loaded` of what it returned.
    private var redrawing = false
    private let now: () -> Date

    /// `now` is the clock `settle` is measured by; a test hands in one it
    /// can move.
    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    /// Whether the web view holds anything of a letter's, or did until
    /// WebKit lost it, which emptying the pane has to clear.
    var holdsLetter: Bool {
        switch content {
        case .nothing, .blank: return false
        case .notice, .letter, .conversation: return true
        }
    }

    /// A new document has been given to the web view, and replaces the last.
    /// Bodies still waiting for the last one go with it: they were for its
    /// sections. With no navigation to wait on, the document is taken as
    /// loaded, and a body goes straight in.
    mutating func loaded(_ content: Content, navigation: ObjectIdentifier?) {
        self.content = content
        self.navigation = navigation
        finished = navigation == nil
        waiting = []
        lost = false
        drawn = redrawing ? .again(finished: finished ? now() : nil) : .byPane
        redrawing = false
    }

    /// A body for one letter of the conversation on screen. Kept in the
    /// stack, so a redraw has it, and returned as the script that puts it in
    /// its section when that can run now. Nil when the document is still
    /// loading, and the script waits for it (`didFinish`); when the document
    /// has been lost, and the redraw puts it in; or when the pane is not
    /// showing a conversation with that letter in it.
    mutating func fill(_ id: String, with body: ConversationDocument.Entry.Rendered) -> String? {
        guard case .conversation(var entries) = content,
              let i = entries.firstIndex(where: { $0.id == id }) else { return nil }
        entries[i].body = body
        content = .conversation(entries)
        guard !lost else { return nil }
        let script = ConversationDocument.javascriptFill(
            sectionID: ConversationDocument.sectionID(for: id), html: body.html, isHTML: body.isHTML)
        guard finished else {
            waiting.append(script)
            return nil
        }
        return script
    }

    /// A letter of the stack opened or closed by hand, so a redraw opens the
    /// same ones.
    mutating func setOpen(_ open: Bool, _ id: String) {
        guard case .conversation(var entries) = content,
              let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].isExpanded = open
        content = .conversation(entries)
    }

    /// A document has finished loading. When it is the one on screen, the
    /// scripts that were waiting for it, in the order they came.
    mutating func didFinish(_ navigation: ObjectIdentifier) -> [String] {
        guard navigation == self.navigation, !finished else { return [] }
        finished = true
        if case .again(nil) = drawn { drawn = .again(finished: now()) }
        defer { waiting = [] }
        return waiting
    }

    /// WebKit's content process has ended and taken the document with it.
    /// Everything but the empty page is to be drawn again (`redraw`); that
    /// is under a hidden web view and has nothing on it to lose.
    ///
    /// Not a document that was itself drawn again and is lost while it
    /// loads, or within `settle` of loading: that is taken as the letter
    /// ending the process, and the pane says it could not be shown instead.
    /// And not those words either, lost as quickly: there is nothing
    /// simpler left to try.
    mutating func contentProcessEnded() {
        let again: Bool
        switch drawn {
        case .byPane: again = false
        case .again(nil): again = true
        case .again(let at?): again = now().timeIntervalSince(at) < Self.settle
        }
        navigation = nil
        finished = false
        waiting = []
        drawn = .byPane
        switch content {
        case .nothing, .blank:
            content = .nothing
            lost = false
        case .notice where again:
            content = .nothing
            lost = false
        case .notice, .letter, .conversation:
            if again { content = .notice([Self.cannotShow]) }
            lost = true
        }
    }

    /// What to draw again, called when he can see the pane: at once, or once
    /// the app is back in front and the pane on screen. iOS ends the process
    /// mostly while he is in another app, and a document drawn again there
    /// would take back the memory it had just been ended for. Nil when
    /// nothing was lost, when it has been drawn again already, or when the
    /// pane has had a new document meanwhile.
    ///
    /// The draw that follows is taken as the redraw (`loaded`), and its
    /// bodies are then given back to `fill`, where they wait for it to load
    /// as any body does.
    mutating func redraw() -> Redraw? {
        guard lost else { return nil }
        lost = false
        redrawing = true
        guard case .conversation(let entries) = content else {
            return Redraw(content: content, bodies: [])
        }
        let bodies = entries.compactMap { entry in entry.body.map { (id: entry.id, body: $0) } }
        let bare = entries.map { entry -> ConversationDocument.Entry in
            var bare = entry
            bare.body = nil
            return bare
        }
        return Redraw(content: .conversation(bare), bodies: bodies)
    }
}
