import XCTest
@testable import Blackmail

/// A conversation's stack in Mail's order (B-074): Mail on iPadOS 18 with
/// its factory settings, Most Recent Message on Top off and Collapse Read
/// Messages on. The oldest letter at the top and the newest at the bottom;
/// the letters he has read closed to their line, the unread ones and the
/// newest open; the pane opening at the newest; letters that come while it
/// is open going in at the bottom; and his place kept as letters above him
/// grow, and as the header changes height.
///
/// The order, the rule for what is open, where the pane opens and what goes
/// in at the bottom are pure, and tested here. What does them on the
/// screen, the pane's controller, the list's and the stack's script, is
/// UIKit and WebKit, and read from their source.
final class ConversationOrderTests: XCTestCase {

    // MARK: - Letters

    /// A letter of a conversation, `n` minutes into the day: the higher the
    /// later, and the list's order is the highest first.
    private func letter(_ n: Int, read: Bool = true, mailbox: String = "INBOX",
                        gmail: UInt64? = nil, sender: String = "Sam Example <sam@example.com>")
        -> MessageSummary {
        MessageSummary(id: "1/\(n)", mailboxID: mailbox, sender: sender,
                       subject: "Re: the roof", preview: "letter \(n)",
                       date: Date(timeIntervalSince1970: 1_790_000_000 + Double(n) * 60),
                       isRead: read, isFlagged: false, threadID: "t1",
                       gmailMessageID: gmail ?? UInt64(9_000 + n))
    }

    /// A conversation as the list has it: newest first.
    private func thread(_ letters: MessageSummary...) -> MessageThread {
        MessageThread(messages: letters)
    }

    private func ids(_ entries: [ConversationDocument.Entry]) -> [String] { entries.map(\.id) }
    private func open(_ entries: [ConversationDocument.Entry]) -> [String] {
        entries.filter(\.isExpanded).map(\.id)
    }

    // MARK: - The order

    /// The oldest at the top, the newest at the bottom: the list's
    /// newest-first order turned over. It ran newest first, a guess
    /// (B-022); Mail's factory setting has Most Recent Message on Top off.
    func testTheStackRunsFromTheOldestAtTheTopToTheNewestAtTheBottom() {
        let stack = ConversationDocument.stack(of: thread(letter(4), letter(3), letter(2), letter(1)))
        XCTAssertEqual(ids(stack), ["1/1", "1/2", "1/3", "1/4"])
        XCTAssertEqual(stack.map(\.date), stack.map(\.date).sorted(), "in date order")
    }

    /// The order is the list's, turned over, and not re-sorted by the
    /// letters' dates: a letter dated wrong keeps its place, and the letter
    /// the row stands for, the one he tapped the row to read, is at the
    /// bottom, open.
    func testTheLetterTheRowStandsForIsAtTheBottomWhateverItsDate() {
        var early = letter(9)
        early.date = Date(timeIntervalSince1970: 1_700_000_000)
        let stack = ConversationDocument.stack(of: thread(early, letter(3), letter(2)))
        XCTAssertEqual(ids(stack), ["1/2", "1/3", "1/9"])
        XCTAssertEqual(stack.last?.isExpanded, true)
    }

    /// Each letter is drawn from its row: sender, date, the line's few
    /// words, and no body until it is fetched.
    func testEachLetterIsDrawnFromItsRow() {
        let stack = ConversationDocument.stack(of: thread(letter(2), letter(1)))
        XCTAssertEqual(stack.first, ConversationDocument.Entry(
            id: "1/1", sender: "Sam Example <sam@example.com>",
            date: Date(timeIntervalSince1970: 1_790_000_060), body: nil,
            isExpanded: false, preview: "letter 1"))
    }

    // MARK: - What is open

    /// Collapse Read Messages, Mail's default: every letter he has read is
    /// closed to its line, but the newest, which is open.
    func testReadLettersAreClosedAndTheNewestIsOpen() {
        let stack = ConversationDocument.stack(of: thread(letter(3), letter(2), letter(1)))
        XCTAssertEqual(open(stack), ["1/3"])
    }

    /// Every letter he has not read is open, wherever it is in the stack, as
    /// Mail shows them in full; the newest is open whether he has read it or
    /// not. It used to be the newest alone, the unread ones closed.
    func testUnreadLettersAreOpenWithTheNewest() {
        let stack = ConversationDocument.stack(of: thread(letter(5), letter(4, read: false),
                                                          letter(3), letter(2, read: false),
                                                          letter(1)))
        XCTAssertEqual(open(stack), ["1/2", "1/4", "1/5"])
        XCTAssertEqual(open(ConversationDocument.stack(of: thread(letter(2, read: false),
                                                                  letter(1, read: false)))),
                       ["1/1", "1/2"])
        XCTAssertEqual(open(ConversationDocument.stack(of: thread(letter(1, read: false)))), ["1/1"])
    }

    /// What the pane fetches as the stack opens, besides the newest: the
    /// unread letters, newest first, and nothing it shows closed.
    func testTheUnreadLettersAreTheOnesOpenedWithTheNewest() {
        let t = thread(letter(5, read: false), letter(4, read: false), letter(3),
                       letter(2, read: false), letter(1))
        XCTAssertEqual(ConversationDocument.openedWithTheNewest(t).map(\.id), ["1/4", "1/2"])
        XCTAssertEqual(ConversationDocument.openedWithTheNewest(thread(letter(2), letter(1))), [])
        XCTAssertEqual(ConversationDocument.openedWithTheNewest(thread(letter(1, read: false))), [])
    }

    /// What a tap on the conversation's row marks read, all at once: the
    /// newest, as a tap on a row always has, then the unread letters the
    /// stack opens with it. The list leaves out any already read.
    func testTheTapMarksTheNewestAndTheUnreadOnesAtOnce() {
        let t = thread(letter(5, read: false), letter(4, read: false), letter(3),
                       letter(2, read: false), letter(1))
        XCTAssertEqual(ConversationDocument.readAtTheTap(t).map(\.id), ["1/5", "1/4", "1/2"])
        XCTAssertEqual(ConversationDocument.readAtTheTap(thread(letter(2), letter(1))).map(\.id),
                       ["1/2"])
        XCTAssertEqual(ConversationDocument.readAtTheTap(thread(letter(3), letter(2, read: false),
                                                                letter(1))).map(\.id),
                       ["1/3", "1/2"])
    }

    // MARK: - Where it opens

    /// When he has read every letter but the newest, the pane opens at the
    /// newest, at the bottom, with the line of the letter before it above
    /// it, so he can see there is more above. A letter alone opens at
    /// itself.
    func testTheStackOpensAtTheNewestWhenHeHasReadTheRest() {
        let read = ConversationDocument.stack(of: thread(letter(3), letter(2), letter(1)))
        XCTAssertEqual(ConversationDocument.opensAt(read), "m1_2")
        let newestUnread = ConversationDocument.stack(of: thread(letter(3, read: false), letter(2),
                                                                 letter(1)))
        XCTAssertEqual(ConversationDocument.opensAt(newestUnread), "m1_2")
        XCTAssertEqual(ConversationDocument.opensAt(ConversationDocument.stack(of: thread(letter(1)))),
                       "m1_1")
        XCTAssertNil(ConversationDocument.opensAt([]))
    }

    /// With letters he has not read besides the newest, the pane opens at
    /// the oldest of them, under the line of the letter before it. Opened
    /// at the newest, the unread ones above it were out of sight while the
    /// tap marked them read, and nothing on screen said they had come.
    func testTheStackOpensAtTheOldestLetterHeHasNotRead() {
        let one = ConversationDocument.stack(of: thread(letter(3), letter(2, read: false),
                                                        letter(1)))
        XCTAssertEqual(ConversationDocument.opensAt(one), "m1_1")
        let two = ConversationDocument.stack(of: thread(letter(5, read: false), letter(4, read: false),
                                                        letter(3), letter(2), letter(1)))
        XCTAssertEqual(ConversationDocument.opensAt(two), "m1_3")
        let apart = ConversationDocument.stack(of: thread(letter(5), letter(4, read: false),
                                                          letter(3), letter(2, read: false),
                                                          letter(1)))
        XCTAssertEqual(ConversationDocument.opensAt(apart), "m1_1")
        let none = ConversationDocument.stack(of: thread(letter(3), letter(2, read: false),
                                                         letter(1, read: false)))
        XCTAssertEqual(ConversationDocument.opensAt(none), "m1_1", "the oldest unread, at the top")
    }

    /// Whatever he has read, every letter the tap marks read is at or below
    /// the section the pane opens at, none above it; and the pane opens no
    /// more than one line above the first of them. Every way five letters
    /// can be read or not.
    func testEveryLetterMarkedAtTheTapStartsAtOrBelowTheTopOfThePane() throws {
        for mask in 0..<32 {
            let letters = (1...5).reversed().map { n in letter(n, read: mask & (1 << (n - 1)) == 0) }
            let t = MessageThread(messages: letters)
            let stack = ConversationDocument.stack(of: t)
            let opens = try XCTUnwrap(ConversationDocument.opensAt(stack))
            let top = try XCTUnwrap(stack.firstIndex { ConversationDocument.sectionID(for: $0.id) == opens })
            let marked = ConversationDocument.readAtTheTap(t).compactMap { m in
                stack.firstIndex { $0.id == m.id }
            }
            let first = try XCTUnwrap(marked.min())
            XCTAssertLessThanOrEqual(top, first, "read/unread mask \(mask)")
            XCTAssertGreaterThanOrEqual(top, first - 1, "read/unread mask \(mask)")
        }
    }

    /// The document says where it opens, in its head, where no letter's
    /// markup can reach, for the stack's script to read as it ends. A stack
    /// of no letters says nothing.
    func testTheDocumentSaysWhereItOpens() throws {
        let stack = ConversationDocument.stack(of: thread(letter(3), letter(2), letter(1)))
        let html = ConversationDocument.html(entries: stack, inset: 20, bodyPointSize: 17,
                                             lineHeight: 1.4)
        let head = try XCTUnwrap(html.components(separatedBy: "</head>").first)
        XCTAssertTrue(head.contains("<meta name=\"bm-opens\" content=\"m1_2\">"), head)
        XCTAssertFalse(ConversationDocument.html(entries: [], inset: 20, bodyPointSize: 17,
                                                 lineHeight: 1.4).contains("bm-opens"))
        // The sections in the stack's order: the oldest first.
        let first = try XCTUnwrap(html.range(of: "id=\"m1_1\"")).lowerBound
        let last = try XCTUnwrap(html.range(of: "id=\"m1_3\"")).lowerBound
        XCTAssertLessThan(first, last)
    }

    // MARK: - Letters that come while it is open

    /// A letter that comes into the conversation goes in at the bottom:
    /// those newer than every letter of the stack, oldest first.
    func testLettersThatComeGoInAtTheBottomOldestFirst() {
        let shown = [letter(1), letter(2), letter(3)]
        let list = [thread(letter(9)),
                    thread(letter(5, read: false), letter(4, read: false), letter(3), letter(2), letter(1))]
        XCTAssertEqual(ConversationDocument.arrivals(after: shown, in: list).map(\.id), ["1/4", "1/5"])
        XCTAssertEqual(ConversationDocument.arrivals(
            after: shown, in: [thread(letter(3), letter(2), letter(1))]), [], "nothing new")
    }

    /// Older letters that join the conversation, as a page further down
    /// the folder brings them, are not put in: the stack would grow above
    /// him. A newer one with them is.
    func testOlderLettersThatJoinAreNotPutIn() {
        let shown = [letter(2), letter(3)]
        XCTAssertEqual(ConversationDocument.arrivals(
            after: shown, in: [thread(letter(3), letter(2), letter(1))]), [])
        XCTAssertEqual(ConversationDocument.arrivals(
            after: shown, in: [thread(letter(4), letter(3), letter(2), letter(1))]).map(\.id), ["1/4"])
    }

    /// The newest of the stack gone from the list, binned on the phone, say:
    /// the conversation is still found by the letters it has left, and what
    /// came after them goes in, but not the letters already shown.
    func testTheConversationIsFoundByAnyLetterStillInIt() {
        let shown = [letter(1), letter(2), letter(3)]
        XCTAssertEqual(ConversationDocument.arrivals(
            after: shown, in: [thread(letter(5), letter(4), letter(2), letter(1))]).map(\.id),
                       ["1/4", "1/5"])
    }

    /// Nothing from another conversation: not one in another folder whose
    /// letter has the same id, as every Gmail Inbox has UIDVALIDITY 1, nor
    /// a row kept on the iPad whose id the server has given to another
    /// letter (D-016), nor a list that does not group, a search's say,
    /// where a row is one letter.
    func testNothingComesFromAnotherConversation() {
        let shown = [letter(1), letter(2)]
        XCTAssertEqual(ConversationDocument.arrivals(
            after: shown, in: [thread(letter(3, mailbox: "Sent"), letter(2, mailbox: "Sent"))]), [])
        XCTAssertEqual(ConversationDocument.arrivals(
            after: shown, in: [thread(letter(3), letter(2, gmail: 1))]), [])
        XCTAssertEqual(ConversationDocument.arrivals(
            after: shown, in: [thread(letter(3)), thread(letter(2)), thread(letter(1))]), [])
        XCTAssertEqual(ConversationDocument.arrivals(after: [], in: [thread(letter(3))]), [])
    }

    /// The stack takes them only once its page has loaded and while WebKit
    /// has it: they go in as the stack draws its letters, after the last,
    /// and are kept in it, so a redraw has them and their bodies have a
    /// section to go into. A letter already in the stack is not put in
    /// twice.
    func testTheStackTakesThemOnceItHasLoaded() throws {
        final class Navigation {}
        let navigation = Navigation()
        var document = PaneDocument()
        let stack = ConversationDocument.stack(of: thread(letter(2), letter(1)))
        let came = ConversationDocument.entry(for: letter(3, read: false), open: true)
        document.loaded(.conversation(stack), navigation: ObjectIdentifier(navigation))

        XCTAssertNil(document.append([came]), "still loading")
        _ = document.didFinish(ObjectIdentifier(navigation))
        let append = try XCTUnwrap(document.append([came, stack[1]]))
        XCTAssertEqual(append, ConversationDocument.Append([came]))
        guard case .conversation(let entries) = document.content else { return XCTFail() }
        XCTAssertEqual(ids(entries), ["1/1", "1/2", "1/3"])
        XCTAssertNil(document.append([came]), "once")
        let body = ConversationDocument.Entry.Rendered(html: "Dear Sam,", isHTML: false)
        XCTAssertEqual(document.fill("1/3", with: body)?.sectionID, "m1_3")

        document.contentProcessEnded()
        XCTAssertNil(document.append([ConversationDocument.entry(for: letter(4), open: false)]),
                     "lost to WebKit")
        var single = PaneDocument()
        single.loaded(.notice(["Loading…"]), navigation: nil)
        XCTAssertNil(single.append([came]), "no stack")
    }

    /// What goes in is the stack's own sections, drawn as at the start: its
    /// id, open or closed, "Loading…" until its body comes, the sender
    /// escaped. It goes to the stack's `bmAppend` as an argument.
    func testWhatGoesInIsTheStacksOwnSections() {
        let append = ConversationDocument.Append([
            ConversationDocument.entry(for: letter(3, read: false), open: true),
            ConversationDocument.entry(for: letter(4, sender: "<b>Jane</b> <j@example.com>"), open: false),
        ])
        XCTAssertTrue(append.html.hasPrefix("<div class=\"bm-letter bm-open\" id=\"m1_3\">"), append.html)
        XCTAssertTrue(append.html.contains("<div class=\"bm-letter\" id=\"m1_4\">"), append.html)
        XCTAssertTrue(append.html.contains("Loading…"))
        XCTAssertFalse(append.html.contains("<b>Jane"), append.html)
        XCTAssertEqual(ConversationDocument.Append.script, "bmAppend(html)")
        XCTAssertEqual(append.arguments["html"] as? String, append.html)
        XCTAssertEqual(append.arguments.count, 1)
    }

    // MARK: - His place when the header changes

    /// The header grows by a line or a file's row as he opens a letter with
    /// more recipients or files: the stack is scrolled down by as much, so
    /// what he sees stays where it was; shrunk, up by as much. Within what
    /// the stack can scroll to.
    func testTheStackMovesAgainstTheHeader() {
        XCTAssertEqual(StackPlace.offset(from: 300, headerGrewBy: 44, range: 0...1000), 344)
        XCTAssertEqual(StackPlace.offset(from: 300, headerGrewBy: -20, range: 0...1000), 280)
        XCTAssertEqual(StackPlace.offset(from: 10, headerGrewBy: -20, range: 0...1000), 0)
        XCTAssertEqual(StackPlace.offset(from: 990, headerGrewBy: 44, range: 0...1000), 1000)
        XCTAssertNil(StackPlace.offset(from: 300, headerGrewBy: 0, range: 0...1000))
        XCTAssertNil(StackPlace.offset(from: 0, headerGrewBy: 44, range: 0...0),
                     "a stack shorter than the pane cannot scroll")
        XCTAssertNil(StackPlace.offset(from: 0, headerGrewBy: -44, range: 0...1000))
    }

    // MARK: - The stack's script

    /// The script opens the stack at the section the document names,
    /// putting its top at the top of the pane, and holds it there as the
    /// stack grows above it, until he touches the pane in any way.
    func testTheScriptOpensWhereTheDocumentSaysAndHoldsItUntilHeTouches() {
        let script = ConversationDocument.script
        for wiring in [
            "var opens = document.querySelector('head > meta[name=\"bm-opens\"]');",
            "bmOpening = opens ? document.getElementById(opens.getAttribute('content')) : null;",
            "if (bmOpening) { window.scrollTo(0, window.pageYOffset + bmOpening.getBoundingClientRect().top);",
            "['touchstart', 'mousedown', 'wheel', 'keydown'].forEach(function (name) { "
                + "window.addEventListener(name, bmLetGo, { capture: true, passive: true });",
            "function bmLetGo() { if (!bmOpening) return; bmOpening = null; bmTake(); }",
            "window.addEventListener('load', bmKeep); bmKeep(); })();",
        ] {
            XCTAssertTrue(flat(script).contains(wiring), wiring)
        }
    }

    /// The hold lets go on any scroll the script did not make: the status
    /// bar tapped, VoiceOver's scroll, the header changing height. None of
    /// those is a touch on the page, and the hold went on, so the next
    /// letter to grow pulled him back to where the stack opened. The script
    /// notes where it put the page, and a scroll to anywhere else lets go.
    func testTheHoldLetsGoOnAScrollTheScriptDidNotMake() {
        let script = flat(ConversationDocument.script)
        for wiring in [
            "var bmOpening = null; var bmSet = null;",
            "if (bmOpening) { window.scrollTo(0, window.pageYOffset + bmOpening.getBoundingClientRect().top); "
                + "bmSet = window.pageYOffset; } else if (bmPlace) {",
            "window.addEventListener('scroll', function () { "
                + "if (bmOpening && bmSet !== null && Math.abs(window.pageYOffset - bmSet) > 1) bmLetGo(); "
                + "else if (!bmOpening) bmTake(); }, { passive: true });",
        ] {
            XCTAssertTrue(script.contains(wiring), wiring)
        }
    }

    /// The last letter, open or closed, is at least the pane's height, so
    /// any letter's top can be put at the top of the pane from the first
    /// frame, before the bodies have come, and nothing moves when they
    /// come. On the last letter whatever it is: on the last open one, a
    /// letter put in at the bottom closed, or the newest closed by its
    /// line, took the floor away, and the stack got shorter under him.
    func testTheLastLetterOpenOrClosedIsAtLeastThePanesHeight() {
        let html = flat(ConversationDocument.html(entries: [], inset: 20, bodyPointSize: 17,
                                                  lineHeight: 1.4))
        XCTAssertTrue(html.contains("body > .bm-letter:last-child { min-height: 100vh; "
                                    + "box-sizing: border-box; }"), html)
        XCTAssertFalse(html.contains(".bm-open:last-child"), html)
        XCTAssertEqual(html.components(separatedBy: "min-height").count, 2, "one floor")
    }

    /// Once he has touched it, the script keeps his place: the letter at
    /// the top of the pane, and how far down it sits, taken as he scrolls,
    /// and put back whenever a letter grows or shrinks, a body come into
    /// it, its pictures loaded, the pane a new width. Every letter's section
    /// is watched, those put in at the bottom too. WebKit's own anchoring is
    /// off, so he is not moved twice.
    func testTheScriptKeepsHisPlaceAsLettersAboveHimGrow() throws {
        let script = flat(ConversationDocument.script)
        for wiring in [
            "var letters = document.querySelectorAll('body > .bm-letter');",
            "if (box.bottom > 0) { bmPlace = { section: letters[i], top: box.top }; return; }",
            "} else if (bmPlace) { var moved = bmPlace.section.getBoundingClientRect().top - bmPlace.top; "
                + "if (moved !== 0) window.scrollBy(0, moved); } bmTake(); }",
            "if (window.ResizeObserver) bmWatch = new ResizeObserver(bmKeep);",
            "if (bmWatch) bmWatch.observe(head.parentNode);",
            "for (var i = 0; i < heads.length; i++) bmWire(heads[i]);",
            "else if (!bmOpening) bmTake(); }, { passive: true });",
        ] {
            XCTAssertTrue(script.contains(wiring), wiring)
        }
        // Opening a letter moves nothing above it: no scroll in the toggle.
        let toggle = try XCTUnwrap(script.components(separatedBy: "function bmFill").first)
        XCTAssertFalse(toggle.contains("scroll"), toggle)
        let html = ConversationDocument.html(entries: [], inset: 20, bodyPointSize: 17, lineHeight: 1.4)
        XCTAssertTrue(html.contains("html, body { overflow-anchor: none; }"), html)
    }

    /// Letters put in at the bottom are appended to the body, as the
    /// stack's own are its children, and their lines wired as the first
    /// ones were.
    func testTheScriptPutsLettersInAtTheBottom() {
        let script = flat(ConversationDocument.script)
        XCTAssertTrue(script.contains(
            "function bmAppend(html) { var holder = document.createElement('div'); holder.innerHTML = html; "
                + "while (holder.firstElementChild) { "
                + "var section = document.body.appendChild(holder.firstElementChild); "
                + "var head = section.querySelector('.bm-head'); if (head) bmWire(head); } }"), script)
    }

    // MARK: - The wiring, read from the source

    /// The pane draws the stack in Mail's order, fetches the newest first
    /// and with it the header, then the unread letters, its rows of them
    /// read, since the list marks them at the tap. It does not mark them
    /// itself, a redraw of the list each. A tap on a line marks that
    /// letter, and only it, as before.
    func testThePaneDrawsTheStackInMailsOrder() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        let show = try section(of: code, from: "func show(thread: MessageThread) {",
                               to: "private var pageStyle")
        for wiring in [
            "stackLetters = thread.messages.reversed()",
            "let entries = ConversationDocument.stack(of: thread)",
            "renderConversation(entries)",
            "self?.settleBody(result, for: newest.id, focus: true)",
            "}) for letter in ConversationDocument.openedWithTheNewest(thread) { "
                + "loadBody(for: letter.id, focus: false) var read = letter read.isRead = true "
                + "threadSummaries[letter.id] = read } }",
        ] {
            XCTAssertTrue(show.contains(wiring), wiring)
        }
        XCTAssertFalse(show.contains("isExpanded: m.id == thread.newest.id"))
        XCTAssertFalse(show.contains("markOpened"), show)
        XCTAssertFalse(show.contains("onLetterOpened"), show)
        let tapped = try section(of: code, from: "func userContentController(",
                                 to: "private func markOpened(")
        XCTAssertTrue(tapped.contains("document.setOpen(opened, id) guard opened else { return } "
                                      + "loadBody(for: id, focus: true)"), tapped)
        XCTAssertTrue(tapped.contains("markOpened(id) }"), tapped)
        let mark = try section(of: code, from: "private func markOpened(_ id: String) {",
                               to: "func takeArrivals(")
        XCTAssertTrue(mark.contains("if let row = threadSummaries[id], !row.isRead { var read = row "
                                    + "read.isRead = true threadSummaries[id] = read onLetterOpened?(row) }"),
                      mark)
    }

    /// A tap on a conversation's row marks the newest and the unread
    /// letters the stack opens with it, in one go: each held over a listing
    /// on its way, the rows redrawn once for the lot, then a STORE each.
    /// It was a redraw of the list for each unread letter, inside the tap.
    func testTheListMarksTheTapsLettersWithOneRedraw() throws {
        let list = try source("UI/MessageListViewController.swift")
        let open = try section(of: list, from: "private func open(_ thread: MessageThread, at ip: IndexPath) {",
                               to: "private func open(_ summary: MessageSummary")
        XCTAssertTrue(open.contains("onSelectThread?(thread) "
                                    + "markReadIfNeeded(ConversationDocument.readAtTheTap(thread)) }"), open)
        let one = try section(of: list, from: "private func markReadIfNeeded(_ summary: MessageSummary) {",
                              to: "private func markReadIfNeeded(_ summaries: [MessageSummary]) {")
        XCTAssertTrue(one.contains("markReadIfNeeded([summary]) }"), one)
        let lot = try section(of: list, from: "private func markReadIfNeeded(_ summaries: [MessageSummary]) {",
                              to: "private func sendRead(")
        for wiring in [
            "let marked = summaries.filter { !$0.isRead } guard let first = marked.first else { return }",
            "for m in marked { letters.reading(m.id, read: true) }",
            "regroup(highlighting: first.id) for m in marked { sendRead(m) } }",
        ] {
            XCTAssertTrue(lot.contains(wiring), wiring)
        }
        XCTAssertEqual(lot.components(separatedBy: "regroup(").count, 2, "one redraw: \(lot)")
    }

    /// Letters that come go in at the bottom, open if unread with their
    /// bodies fetched, the header left on the letter he had, and none of
    /// them marked read. The list tells the pane each time its rows are
    /// drawn again, with its conversations.
    func testLettersThatComeAreWiredFromTheListToTheBottomOfTheStack() throws {
        let pane = try source("UI/MessageDetailViewController.swift")
        let take = try section(of: pane, from: "func takeArrivals(from threads: [MessageThread]) {",
                               to: "private func renderLoadFailure()")
        for wiring in [
            "guard !stackLetters.isEmpty else { return }",
            "let more = ConversationDocument.arrivals(after: stackLetters, in: threads)",
            "let append = document.append(more.map { ConversationDocument.entry(for: $0, open: !$0.isRead) })",
            "stackLetters += more",
            "webView.callAsyncJavaScript(ConversationDocument.Append.script, arguments: append.arguments, "
                + "in: nil, in: .defaultClient)",
            "for letter in more where !letter.isRead { loadBody(for: letter.id, focus: false) }",
        ] {
            XCTAssertTrue(take.contains(wiring), wiring)
        }
        XCTAssertFalse(take.contains("markOpened"), "he did not open them")
        XCTAssertFalse(take.contains("focus: true"), "the header stays on his letter")

        let root = try source("UI/RootViewController.swift")
        XCTAssertTrue(root.contains("list.onRegrouped = { [weak self] in guard let self else { return } "
                                    + "self.detail.takeArrivals(from: self.list.conversations) }"))
        let list = try source("UI/MessageListViewController.swift")
        let regroup = try section(of: list, from: "private func regroup(highlighting",
                                  to: "private func place()")
        XCTAssertTrue(regroup.contains("scroll(to: before, in: threads) } onRegrouped?() }"), regroup)
        XCTAssertTrue(list.contains("var conversations: [MessageThread] { threads }"))
    }

    /// The header pointed at a letter he opened keeps the stack where it was
    /// on the glass: its height taken before, and the stack scrolled by the
    /// difference after it is laid out.
    func testTheHeaderKeepsHisPlace() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        let focus = try section(of: code, from: "private func focusLetter(_ m: Message) {",
                                to: "private func fill(")
        for wiring in [
            "let before = header.frame.height header.configure(with: m)",
            "keepPlace(headerWas: before) }",
            "view.layoutIfNeeded() let scroll = webView.scrollView",
            "guard let y = StackPlace.offset(from: Double(scroll.contentOffset.y), "
                + "headerGrewBy: Double(header.frame.height - before), range: lowest...highest) "
                + "else { return } scroll.contentOffset.y = CGFloat(y)",
        ] {
            XCTAssertTrue(focus.contains(wiring), wiring)
        }
    }

    // MARK: - Helpers

    /// Whitespace runs as one space, so wiring reads as one line.
    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }

    /// A file under `Sources/Blackmail`, comment lines taken out and
    /// whitespace runs made one space.
    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(file)")
        let text = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        return flat(text)
    }

    private func section(of code: String, from start: String, to end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start), start)
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex), end)
        return String(code[from.lowerBound..<to.lowerBound])
    }
}
