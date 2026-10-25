import XCTest
@testable import Blackmail

/// Mail's Complete Threads (B-104): his own letters of an Inbox
/// conversation that are only in Sent Mail, brought into the reading pane's
/// stack, closed, by date, read only, and never anywhere else.
///
/// What decides it, where his letters go and which are shown are pure, and
/// tested here; the lookup over the scripted server, through the shipping
/// repository and client, so the commands counted are the ones the app
/// sends. The pane's controller, the list's and Settings are UIKit, and read
/// from their source.
final class CompleteThreadsTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "CompleteThreadsTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var clock: ManualClock!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        clock = ManualClock()
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        UserDefaults.standard.removeObject(forKey: ConversationSettings.completeThreadsKey)
        for outcome in ["ok", "fail"] {
            let transcript = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
            try? FileManager.default.removeItem(atPath: transcript)
        }
        server = nil
        book = nil
        clock = nil
        super.tearDown()
    }

    // MARK: - Letters

    private static let base = Date(timeIntervalSince1970: 1_790_000_000)

    /// A letter of the conversation in the Inbox, `n` minutes in.
    private func inbox(_ n: Int, read: Bool = true) -> MessageSummary {
        MessageSummary(id: "1/\(n)", mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                       subject: "Re: the roof", preview: "letter \(n)",
                       date: Self.base.addingTimeInterval(Double(n) * 60),
                       isRead: read, isFlagged: false, threadID: "1700000000000000042",
                       gmailMessageID: UInt64(9_000 + n),
                       arrived: Self.base.addingTimeInterval(Double(n) * 60))
    }

    /// A letter of his in Sent Mail, `n` minutes in: taken by Gmail then,
    /// unless `arrived` says otherwise, and dated `dated` minutes in.
    private func his(_ n: Int, arrived: Int? = nil, dated: Int? = nil, read: Bool = true,
                     gmail: UInt64? = nil, id: String? = nil) -> MessageSummary {
        MessageSummary(id: id ?? "6/\(n)", mailboxID: Server.sent, sender: "owner@example.com",
                       subject: "Re: the roof", preview: "mine \(n)",
                       date: Self.base.addingTimeInterval(Double(dated ?? n) * 60),
                       isRead: read, isFlagged: false, threadID: "1700000000000000042",
                       gmailMessageID: gmail ?? UInt64(8_000 + n),
                       arrived: Self.base.addingTimeInterval(Double(arrived ?? n) * 60))
    }

    /// A conversation as the list has it: newest first.
    private func thread(_ letters: MessageSummary...) -> MessageThread {
        MessageThread(messages: letters)
    }

    private func found(_ letters: MessageSummary..., in folder: String = "Sent Mail") -> RelatedLetters {
        RelatedLetters(folderName: folder, letters: letters)
    }

    private func ids(_ entries: [ConversationDocument.Entry]) -> [String] { entries.map(\.id) }

    // MARK: - Where his letters go

    /// His letters go in where they came, by when Gmail took them: before
    /// the first letter, between two, and after the last; the stack's own
    /// letters as they would be without them, and his closed, each saying
    /// where it was found.
    func testHisLettersGoInBeforeBetweenAndAfterTheConversationsByWhenTheyCame() {
        let t = thread(inbox(5), inbox(3))
        let stack = ConversationDocument.stack(of: t, related: found(his(6), his(1), his(4)))
        XCTAssertEqual(ids(stack), ["r6/1", "1/3", "r6/4", "1/5", "r6/6"])
        XCTAssertEqual(stack.filter { $0.foundIn == nil }, ConversationDocument.stack(of: t),
                       "the conversation's own letters as they were")
        XCTAssertEqual(stack.filter { $0.foundIn != nil }.map(\.isExpanded), [false, false, false])
        XCTAssertEqual(Set(stack.compactMap(\.foundIn)), ["Sent Mail"])
        XCTAssertEqual(stack[0], ConversationDocument.Entry(
            id: "r6/1", sender: "owner@example.com", date: Self.base.addingTimeInterval(60),
            body: nil, isExpanded: false, preview: "mine 1", foundIn: "Sent Mail"))

        // None found, or none asked: the stack as before.
        XCTAssertEqual(ConversationDocument.stack(of: t, related: nil), ConversationDocument.stack(of: t))
        XCTAssertEqual(ConversationDocument.stack(of: t, related: RelatedLetters.none), ConversationDocument.stack(of: t))
    }

    /// By when Gmail took it, not by its Date; where Gmail took two in the
    /// same second, by their Dates; where both are the same, after the
    /// conversation's own.
    func testTiesAreBrokenByTheDate() {
        let t = thread(inbox(5), inbox(3))
        // Dated before the first letter, taken after it.
        XCTAssertEqual(ids(ConversationDocument.stack(of: t, related: found(his(4, dated: 1)))),
                       ["1/3", "r6/4", "1/5"])
        // Taken in the same second as the letter of 3 minutes: dated a
        // minute before it, before it; a minute after, after it.
        XCTAssertEqual(ids(ConversationDocument.stack(of: t, related: found(his(10, arrived: 3, dated: 2)))),
                       ["r6/10", "1/3", "1/5"])
        XCTAssertEqual(ids(ConversationDocument.stack(of: t, related: found(his(10, arrived: 3, dated: 4)))),
                       ["1/3", "r6/10", "1/5"])
        // Taken and dated with it: after it.
        XCTAssertEqual(ids(ConversationDocument.stack(of: t, related: found(his(10, arrived: 3, dated: 3)))),
                       ["1/3", "r6/10", "1/5"])
        // Two of his in a run, oldest first.
        XCTAssertEqual(ids(ConversationDocument.stack(of: t, related: found(his(9), his(7), his(8)))),
                       ["1/3", "1/5", "r6/7", "r6/8", "r6/9"])
    }

    /// The runs that go in after the stack has drawn, each with the letter
    /// of the stack they go before, nil for after the last.
    func testTheRunsNameTheLetterTheyGoBefore() {
        let stack = [inbox(3), inbox(5)]
        let places = ConversationDocument.places(of: [his(6), his(1), his(4), his(2)], among: stack)
        XCTAssertEqual(places.map(\.before), ["1/3", "1/5", nil])
        XCTAssertEqual(places.map { $0.letters.map(\.id) }, [["6/1", "6/2"], ["6/4"], ["6/6"]])
        XCTAssertEqual(ConversationDocument.places(of: [], among: stack), [])
    }

    /// His letters are closed however they are flagged, read or not, and
    /// what the tap marks read and the stack opens with is the
    /// conversation's alone: neither takes his letters.
    func testHisLettersAreAlwaysClosedAndNeverMarkedOrOpenedWithTheNewest() {
        let t = thread(inbox(5, read: false), inbox(3, read: false))
        let stack = ConversationDocument.stack(of: t, related: found(his(1, read: false), his(4, read: false),
                                                                     his(6, read: false)))
        XCTAssertEqual(stack.filter(\.isExpanded).map(\.id), ["1/3", "1/5"])
        XCTAssertEqual(ConversationDocument.openedWithTheNewest(t).map(\.id), ["1/3"])
        XCTAssertEqual(ConversationDocument.readAtTheTap(t).map(\.id), ["1/5", "1/3"])
        XCTAssertFalse(ConversationDocument.readAtTheTap(t).contains { $0.mailboxID == Server.sent })
    }

    /// The stack opens at the same letter with his letters as without, one
    /// line below the top whenever there is a line above it: the line held
    /// at the top is the one directly above it, his or theirs. Every way
    /// four letters can be read or not, with his letters before, between
    /// and after; in the document's head too. That is the picture his
    /// letters going in later leave (`bmInsert`), so the first frame and a
    /// late lookup look the same.
    func testTheStackOpensOneLineAboveTheSameLetterWithAndWithoutHisLetters() throws {
        let placements: [[MessageSummary]] = [
            [his(1)], [his(4)], [his(6)], [his(8)], [his(1), his(4), his(6), his(8)],
            [his(2), his(4), his(4, gmail: 1, id: "6/40")],
        ]
        func at(_ entries: [ConversationDocument.Entry]) throws -> Int {
            try XCTUnwrap(entries.firstIndex { $0.isExpanded })
        }
        for mask in 0..<16 {
            let letters = [7, 5, 3, 2].enumerated().map { i, n in inbox(n, read: mask & (1 << i) == 0) }
            let t = MessageThread(messages: letters)
            let without = ConversationDocument.stack(of: t)
            let first = try at(without)
            for mine in placements {
                let with = ConversationDocument.stack(of: t, related: RelatedLetters(folderName: "Sent Mail",
                                                                                     letters: mine))
                let open = try at(with)
                let name = "mask \(mask), \(mine.map(\.id))"
                XCTAssertEqual(with[open].id, without[first].id, "the same letter: \(name)")
                XCTAssertNil(with[open].foundIn, name)
                let line = open > 0 ? with[open - 1].id : with[open].id
                let opens = try XCTUnwrap(ConversationDocument.opensAt(with))
                XCTAssertEqual(opens, ConversationDocument.sectionID(for: line), name)
                // A line above it without his letters, a line above it with them.
                if first > 0 { XCTAssertGreaterThan(open, 0, name) }
                let html = ConversationDocument.html(entries: with, inset: 20, bodyPointSize: 17,
                                                     lineHeight: 1.4)
                XCTAssertTrue(html.contains("<meta name=\"bm-opens\" content=\"\(opens)\">"), name)
            }
        }

        // The commonest: his reply between a letter read and the newest.
        let common = ConversationDocument.stack(of: thread(inbox(5), inbox(3)), related: found(his(4)))
        XCTAssertEqual(ConversationDocument.opensAt(common), "mr6_4")
        XCTAssertEqual(ConversationDocument.opensAt(ConversationDocument.stack(of: thread(inbox(5), inbox(3)))),
                       "m1_3")
        // His letter the oldest, above the oldest letter he has not read.
        let first = ConversationDocument.stack(of: thread(inbox(5, read: false), inbox(3, read: false)),
                                               related: found(his(1)))
        XCTAssertEqual(ConversationDocument.opensAt(first), "mr6_1")

        // Drawn again after WebKit lost the page with a letter of his open:
        // at the conversation's first open letter still, his passed over,
        // and at that letter itself when what is directly above it is his,
        // open, and no line.
        var above = ConversationDocument.stack(of: thread(inbox(5), inbox(3)), related: found(his(1)))
        above[0].isExpanded = true
        XCTAssertEqual(ConversationDocument.opensAt(above), "m1_3")
        var opened = common
        opened[1].isExpanded = true
        XCTAssertEqual(ConversationDocument.opensAt(opened), "m1_5")

        // And a stack of his letters alone opens nowhere.
        XCTAssertNil(ConversationDocument.opensAt([ConversationDocument.entry(forHis: his(1),
                                                                              foundIn: "Sent Mail")]))
    }

    /// His letter's section is "mr" and its id in Sent Mail, which the
    /// conversation's, "m" and a digit, can never be, even where the two
    /// folders' ids are the same.
    func testHisSectionsCanNeverBeTheConversations() {
        for (v, uid) in [(1, 5), (6, 5), (600004, 701), (0, 0)] {
            let mine = his(uid, id: "\(v)/\(uid)")
            let theirs = MessageSummary(id: "\(v)/\(uid)", mailboxID: "INBOX", sender: "s", subject: "",
                                        preview: "", date: Self.base, isRead: true, isFlagged: false)
            let section = ConversationDocument.sectionID(for: ConversationDocument.relatedID(of: mine))
            XCTAssertEqual(section, "mr\(v)_\(uid)")
            XCTAssertNotEqual(section, ConversationDocument.sectionID(for: theirs.id))
            XCTAssertTrue(ConversationDocument.sectionID(for: theirs.id).dropFirst().first!.isNumber)
        }
    }

    // MARK: - Which are shown

    /// From Sent Mail's FETCH, only his letters that are there alone: one
    /// in the Inbox too, which lists `\Inbox` from Sent Mail, as a letter he
    /// sent himself does, and one with no Gmail id, go.
    func testOnlyLettersInSentMailAloneWithAGmailIDAreKept() {
        let fetched = [
            IMAPFetchResult(uid: 1, gmailMessageID: 11, labels: []),
            IMAPFetchResult(uid: 2, gmailMessageID: 12, labels: ["\\Inbox"]),
            IMAPFetchResult(uid: 3, gmailMessageID: 13, labels: ["\\Important", "\\inbox"]),
            IMAPFetchResult(uid: 4, gmailMessageID: nil, labels: []),
            IMAPFetchResult(uid: 5, gmailMessageID: 15, labels: ["Family", "\\Important"]),
        ]
        XCTAssertEqual(CompleteThreads.onlyInSentMail(fetched).map(\.uid), [1, 5])
    }

    /// None the stack has already, by Gmail's id or by id; none without a
    /// Gmail id; the newest twenty by when Gmail took them, oldest first.
    func testTheStacksOwnLettersGoAndTheNewestTwentyAreKept() {
        let letters = [his(3), his(1), his(2)]
        XCTAssertEqual(CompleteThreads.shown(letters, besides: []).map(\.id), ["6/1", "6/2", "6/3"])
        XCTAssertEqual(CompleteThreads.shown(letters, besides: [8_002]).map(\.id), ["6/1", "6/3"])
        XCTAssertEqual(CompleteThreads.shown(letters, besides: [], apartFrom: ["6/3", "1/1"]).map(\.id),
                       ["6/1", "6/2"])
        var nameless = his(4)
        nameless.gmailMessageID = nil
        XCTAssertEqual(CompleteThreads.shown(letters + [nameless], besides: []).count, 3)

        let many = (1...30).map { his($0, arrived: 100 - $0) }
        let kept = CompleteThreads.shown(many, besides: [])
        XCTAssertEqual(kept.count, CompleteThreads.mostLetters)
        XCTAssertEqual(CompleteThreads.mostLetters, 20)
        XCTAssertEqual(kept.map(\.id), (1...20).reversed().map { "6/\($0)" },
                       "the newest by when Gmail took them, the oldest first")
    }

    /// Gmail's thread id goes into the search only as a number: all digits,
    /// and within 64 bits.
    func testOnlyAThreadIDOfDigitsIsAskedFor() {
        XCTAssertEqual(CompleteThreads.threadNumber("1700000000000000042"), 1_700_000_000_000_000_042)
        XCTAssertEqual(CompleteThreads.threadNumber("18446744073709551615"), UInt64.max)
        for bad in [nil, "", "18446744073709551616", "12a", " 12", "+12", "-12", "1 OR ALL",
                    "12\r\nA1 LOGOUT", "١٢"] as [String?] {
            XCTAssertNil(CompleteThreads.threadNumber(bad), bad ?? "nil")
        }
    }

    /// Looked up only for a conversation of more than one letter in the
    /// Inbox, grouped, with Gmail's thread id and the switch on: never for a
    /// single letter, a search, another folder, the switch off, or a thread
    /// id that is not a number.
    func testOnlyAnInboxConversationWithTheSwitchOnIsLookedUp() {
        let t = thread(inbox(5), inbox(3))
        XCTAssertEqual(CompleteThreads.thread(toComplete: t, listedIn: .inbox, searching: false,
                                              switchedOn: true), 1_700_000_000_000_000_042)
        XCTAssertNil(CompleteThreads.thread(toComplete: thread(inbox(5)), listedIn: .inbox,
                                            searching: false, switchedOn: true), "a single letter")
        XCTAssertNil(CompleteThreads.thread(toComplete: t, listedIn: .inbox, searching: true,
                                            switchedOn: true), "a search")
        XCTAssertNil(CompleteThreads.thread(toComplete: t, listedIn: .inbox, searching: false,
                                            switchedOn: false), "the switch off")
        for role in [nil, .sent, .drafts, .trash, .archive, .junk, .outbox] as [Mailbox.Role?] {
            XCTAssertNil(CompleteThreads.thread(toComplete: t, listedIn: role, searching: false,
                                                switchedOn: true), "\(String(describing: role))")
        }
        var odd = inbox(6)
        odd.threadID = "t1"
        XCTAssertNil(CompleteThreads.thread(toComplete: thread(odd, inbox(3)), listedIn: .inbox,
                                            searching: false, switchedOn: true), "not a number")
    }

    // MARK: - The line and the label

    /// His letter is drawn as any letter's line is, and once open says where
    /// it was found, from the folder's name, over its body: words of the
    /// page's own, hidden while it is closed, grey.
    func testHisLetterSaysWhereItWasFoundOnceOpen() throws {
        let t = thread(inbox(5), inbox(3))
        let stack = ConversationDocument.stack(of: t, related: found(his(4), in: "Sent Mail"))
        let html = flat(ConversationDocument.html(entries: stack, inset: 20, bodyPointSize: 17,
                                                  lineHeight: 1.4))
        XCTAssertTrue(html.contains("<div class=\"bm-letter\" id=\"mr6_4\"> <div class=\"bm-head\"> "
                                    + "<span class=\"bm-from\">owner@example.com</span> "
                                    + "<span class=\"bm-peek\">mine 4</span>"), html)
        XCTAssertTrue(html.contains("</div> <div class=\"bm-found\">Found in Sent Mail</div>"
                                    + "<div class=\"bm-body bm-text\"><span class=\"bm-waiting\">Loading…"),
                      html)
        XCTAssertEqual(html.components(separatedBy: "Found in").count, 2, "the conversation's own say nothing")
        XCTAssertTrue(html.contains(".bm-found { color: #8e8e93; font-size: 14px; "
                                    + "padding: 0 20px 8px 20px; }"), html)
        XCTAssertTrue(html.contains(".bm-letter:not(.bm-open) > .bm-found { display: none; }"), html)

        // From the folder's name, whatever it is, and escaped.
        let other = flat(ConversationDocument.html(
            entries: ConversationDocument.stack(of: t, related: found(his(4), in: "Sent")),
            inset: 20, bodyPointSize: 17, lineHeight: 1.4))
        XCTAssertTrue(other.contains("<div class=\"bm-found\">Found in Sent</div>"), other)
        let odd = ConversationDocument.html(
            entries: ConversationDocument.stack(of: t, related: found(his(4), in: "<b>Out</b> & Back")),
            inset: 20, bodyPointSize: 17, lineHeight: 1.4)
        XCTAssertTrue(odd.contains("Found in &lt;b&gt;Out&lt;/b&gt; &amp; Back"), odd)
        XCTAssertEqual(CompleteThreads.foundIn("Sent Mail"), "Found in Sent Mail")
    }

    // MARK: - Going in after the stack has drawn

    /// What goes in is his letters' sections as the stack draws them,
    /// closed, with the section they go before, "" for after the last, as
    /// the arguments of the stack's `bmInsert`, after the pane's word on
    /// whether its scroll view is moving the stack.
    func testWhatGoesInIsHisSectionsAndTheSectionTheyGoBefore() {
        let entries = [ConversationDocument.entry(forHis: his(1), foundIn: "Sent Mail"),
                       ConversationDocument.entry(forHis: his(2), foundIn: "Sent Mail")]
        let insert = ConversationDocument.Insert(entries, before: "1/3")
        XCTAssertTrue(insert.html.hasPrefix("<div class=\"bm-letter\" id=\"mr6_1\">"), insert.html)
        XCTAssertTrue(insert.html.contains("<div class=\"bm-letter\" id=\"mr6_2\">"), insert.html)
        XCTAssertFalse(insert.html.contains("bm-open"))
        XCTAssertEqual(insert.before, "m1_3")
        XCTAssertEqual(ConversationDocument.Insert(entries, before: nil).before, "")
        XCTAssertEqual(ConversationDocument.Insert.script, "bmPaneMoving(moving); bmInsert(html, before)")
        for moving in [false, true] {
            let arguments = insert.arguments(moving: moving)
            XCTAssertEqual(arguments["html"] as? String, insert.html)
            XCTAssertEqual(arguments["before"] as? String, "m1_3")
            XCTAssertEqual(arguments["moving"] as? Bool, moving)
            XCTAssertEqual(arguments.count, 3)
        }
    }

    /// The script puts them in before the section named, one of the
    /// stack's own, or at the bottom for none, and nothing if the section
    /// named is not one of the stack's; wires their lines as the rest are;
    /// and keeps the letter he is reading where it is. That is the section
    /// named when it begins on the glass with nothing above it there but
    /// closed lines: read before they go in, the page scrolled by as much as
    /// it moved, or, while the stack holds the line it opened at, the hold
    /// passed to the last of his, now directly above it. Otherwise the place
    /// is kept as it always is, the line held or the letter at the top. All
    /// of it once the stack is still (below).
    func testTheScriptKeepsTheLetterHeIsReadingWhereItIs() {
        let script = flat(ConversationDocument.script)
        XCTAssertTrue(script.contains(
            "function bmInsert(html, beforeID) { "
                + "if (bmHeld.length || bmMoving()) { bmLater(function () { bmInsert(html, beforeID); }); return; } "
                + "var at = null; if (beforeID) { "
                + "var letters = document.querySelectorAll('body > .bm-letter'); "
                + "for (var i = 0; i < letters.length; i++) { "
                + "if (letters[i].id === beforeID) { at = letters[i]; break; } } if (!at) return; } "
                + "var still = bmReading(at) ? at.getBoundingClientRect().top : null; "
                + "var holder = document.createElement('div'); holder.innerHTML = html; "
                + "var last = null; while (holder.firstElementChild) { "
                + "last = document.body.insertBefore(holder.firstElementChild, at); "
                + "var head = last.querySelector('.bm-head'); if (head) bmWire(head); } "
                + "if (still !== null && last) { if (bmOpening) { bmOpening = last; } else { "
                + "var moved = at.getBoundingClientRect().top - still; "
                + "if (moved !== 0) window.scrollBy(0, moved); bmTake(); } } "
                + "bmKeep(); }"), script)
        XCTAssertTrue(script.contains(
            "function bmReading(at) { if (!at) return false; "
                + "var top = at.getBoundingClientRect().top; "
                + "if (!(top > 0 && top < window.innerHeight)) return false; "
                + "for (var s = at.previousElementSibling; s; s = s.previousElementSibling) { "
                + "if (s.getBoundingClientRect().bottom <= 0) break; "
                + "if (s.classList.contains('bm-open')) return false; } return true; }"), script)
    }

    /// Held while the stack moves under a finger or coasts after it, as the
    /// iPad showed it must be (2026-10-22): a `scrollBy` made then was lost,
    /// and the letter he was reading dropped a line. Held while the pane's
    /// last word said its scroll view moves the stack, or a second after a
    /// word never followed; while a finger is on the page, from its
    /// touchstart to the touchend or touchcancel that leaves none, or five
    /// seconds after the last of its touches, whichever is first; and while
    /// a scroll not the script's own came in the last quarter of a second;
    /// looked at again every tenth of a second, and
    /// then put in as at rest. What comes while one is held waits behind
    /// it, in the order it came: more of his letters, letters put in at the
    /// bottom, and a body for a section not on the page yet. Each held
    /// change runs once, the next not lost if one throws. Read from the
    /// script, for a host without node; `HisLineUnderTheFingerTests` runs it.
    func testTheScriptHoldsHisLettersWhileTheStackMovesUnderAFinger() {
        let script = flat(ConversationDocument.script)
        for wiring in [
            "var bmHeld = []; var bmHeldTimer = null; var bmFingers = 0; var bmFingered = -1e9; "
                + "var bmPane = -1e9; var bmSettle = 250; var bmLostTouch = 5000; var bmPaneLapse = 1000;",
            "function bmFinger(event) { bmFingers = event.touches.length; bmFingered = performance.now(); }",
            "function bmPaneMoving(moving) { bmPane = moving ? performance.now() : -1e9; }",
            "function bmMoving() { var now = performance.now(); "
                + "return now - bmScrolled < bmSettle || (bmFingers > 0 && now - bmFingered < bmLostTouch) "
                + "|| now - bmPane < bmPaneLapse; }",
            "function bmLater(change) { bmHeld.push(change); "
                + "if (bmHeldTimer === null) bmHeldTimer = setTimeout(bmRelease, 100); }",
            "function bmRelease() { bmHeldTimer = null; "
                + "if (bmMoving()) { bmHeldTimer = setTimeout(bmRelease, 100); return; } "
                + "var held = bmHeld; bmHeld = []; "
                + "for (var i = 0; i < held.length; i++) { try { held[i](); } catch (e) {} } }",
            "function bmInsert(html, beforeID) { "
                + "if (bmHeld.length || bmMoving()) { bmLater(function () { bmInsert(html, beforeID); }); return; }",
            "function bmAppend(html) { if (bmHeld.length) { bmLater(function () { bmAppend(html); }); return; }",
            "var el = document.getElementById(id); if (!el) { "
                + "if (bmHeld.length) bmLater(function () { bmFill(id, html, isHTML); }); return; }",
            "['touchstart', 'touchmove', 'touchend', 'touchcancel'].forEach(function (name) { "
                + "window.addEventListener(name, bmFinger, { capture: true, passive: true }); });",
        ] {
            XCTAssertTrue(script.contains(wiring), wiring)
        }
        XCTAssertEqual(script.components(separatedBy: "bmLater(").count - 1, 4,
                       "defined, his letters, the bottom's, a body")
    }

    /// Kept in the stack, so a redraw has them and their bodies a section to
    /// go into; held while the stack is still loading and handed back as it
    /// finishes, before the bodies; kept for the redraw while WebKit has
    /// lost it; nothing, and nothing kept, for no stack or a letter not in
    /// it; and never twice.
    func testTheStackTakesThemOnceItHasLoadedAndKeepsThem() throws {
        final class Navigation {}
        let navigation = Navigation()
        var document = PaneDocument()
        let stack = ConversationDocument.stack(of: thread(inbox(5), inbox(3)))
        let first = ConversationDocument.entry(forHis: his(1), foundIn: "Sent Mail")
        let last = ConversationDocument.entry(forHis: his(6), foundIn: "Sent Mail")
        document.loaded(.conversation(stack), navigation: ObjectIdentifier(navigation))

        XCTAssertNil(document.insert([first], before: "1/3"), "still loading")
        let body = ConversationDocument.Entry.Rendered(html: "Dear Sam,", isHTML: false)
        XCTAssertNil(document.fill("1/5", with: body))
        let finished = document.didFinish(ObjectIdentifier(navigation))
        XCTAssertEqual(finished.inserts, [ConversationDocument.Insert([first], before: "1/3")])
        XCTAssertEqual(finished.fills.map(\.sectionID), ["m1_5"])
        XCTAssertEqual(document.didFinish(ObjectIdentifier(navigation)), PaneDocument.Finished(), "once")

        XCTAssertEqual(document.insert([last], before: nil), ConversationDocument.Insert([last], before: nil))
        XCTAssertNil(document.insert([last, first], before: nil), "never twice")
        XCTAssertNil(document.insert([ConversationDocument.entry(forHis: his(2), foundIn: "Sent Mail")],
                                     before: "1/9"), "not a letter of the stack")
        guard case .conversation(let entries) = document.content else { return XCTFail() }
        XCTAssertEqual(ids(entries), ["r6/1", "1/3", "1/5", "r6/6"])

        // Opened, its body goes into its own section, and it is kept so.
        document.setOpen(true, "r6/1")
        let mine = ConversationDocument.Entry.Rendered(html: "Yes, Tuesday.", isHTML: false)
        XCTAssertEqual(document.fill("r6/1", with: mine)?.sectionID, "mr6_1")

        // Lost to WebKit: kept, for the redraw, which draws them in the
        // first frame, his body put back as the others are.
        document.contentProcessEnded()
        XCTAssertNil(document.insert([ConversationDocument.entry(forHis: his(4), foundIn: "Sent Mail")],
                                     before: "1/5"))
        let redraw = try XCTUnwrap(document.redraw())
        guard case .conversation(let drawn) = redraw.content else { return XCTFail() }
        XCTAssertEqual(ids(drawn), ["r6/1", "1/3", "r6/4", "1/5", "r6/6"])
        XCTAssertEqual(drawn.first?.isExpanded, true)
        XCTAssertEqual(redraw.bodies.map(\.id), ["r6/1", "1/5"])

        var single = PaneDocument()
        single.loaded(.notice(["Loading…"]), navigation: nil)
        XCTAssertNil(single.insert([first], before: nil), "no stack")
    }

    // MARK: - Work aside

    /// The lookup runs aside: its answer goes on screen while the pane
    /// shows what it was for, not once the pane has moved on; and a letter
    /// opened meanwhile settles as soon as it has come, not after it.
    @MainActor
    func testTheLookupIsCalledOffWithThePaneAndHoldsNothingUp() async throws {
        let loads = PaneLoads()
        let events = Events()
        let held = AsyncGate()
        loads.show(standIn: { events.add("stand-in") }, fetch: { "newest" },
                   settle: { events.add("drawn \((try? $0.get()) ?? "-")") })
        loads.aside({ await held.wait(); return "his" }, settle: { events.add("his \($0)") })
        loads.start({ "opened" }, settle: { events.add("drawn \((try? $0.get()) ?? "-")") })
        try await until { events.all.count == 3 }
        XCTAssertEqual(events.all, ["stand-in", "drawn newest", "drawn opened"])
        await held.open()
        try await until { loads.inFlight == 0 }
        XCTAssertEqual(events.all.last, "his his")

        // The pane moved on while it ran: nothing drawn.
        let again = AsyncGate()
        loads.aside({ await again.wait(); return "late" }, settle: { events.add("his \($0)") })
        loads.supersede()
        await again.open()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(events.all.contains("his late"))
        XCTAssertEqual(loads.inFlight, 0)
    }

    // MARK: - His letters in the pane

    /// Found once the stack has drawn: his letters less the stack's own go
    /// in, in runs, through the document. A tap on his line is his
    /// letter's, and no letter of the conversation's; opening it fetches
    /// that letter from Sent Mail by its id and Gmail's id for it; and its
    /// body goes into his own section, "mr…", once, not to be fetched again.
    func testHisLetterFoundLateOpensFromSentMailIntoItsOwnSection() throws {
        final class Navigation {}
        let navigation = Navigation()
        let t = thread(inbox(5), inbox(3))
        let stack = Array(t.messages.reversed())
        var related = PaneRelated()
        XCTAssertNil(related.show(stack, completing: 42, remembered: nil), "nothing in the first frame")
        XCTAssertNil(related.entryID(forSection: "mr6_4"))
        var document = PaneDocument()
        document.loaded(.conversation(ConversationDocument.stack(of: t)), navigation: ObjectIdentifier(navigation))
        _ = document.didFinish(ObjectIdentifier(navigation))

        let runs = related.take(found(his(4), his(6)), stack: stack)
        XCTAssertEqual(runs.map { $0.entries.map(\.id) }, [["r6/4"], ["r6/6"]])
        XCTAssertEqual(runs.map(\.before), ["1/5", nil])
        XCTAssertEqual(runs.flatMap { $0.entries.map(\.foundIn) }, ["Sent Mail", "Sent Mail"])
        for run in runs { XCTAssertNotNil(document.insert(run.entries, before: run.before)) }

        XCTAssertEqual(related.entryID(forSection: "mr6_4"), "r6/4")
        XCTAssertEqual(related.entryID(forSection: "mr6_6"), "r6/6")
        XCTAssertNil(related.entryID(forSection: "m1_5"), "a letter of the conversation's")
        XCTAssertNil(related.entryID(forSection: "m6_4"))

        let load = try XCTUnwrap(related.load(for: "r6/4"))
        XCTAssertEqual(load, PaneRelated.Load(entryID: "r6/4", id: "6/4", gmailMessageID: 8_004,
                                              mailboxID: Server.sent))
        XCTAssertNil(related.load(for: "1/5"), "a letter of the conversation's")
        XCTAssertNil(related.load(for: "6/4"), "by its entry, not its id")

        let into = related.bodyCame(for: load)
        XCTAssertEqual(into, "r6/4")
        let body = ConversationDocument.Entry.Rendered(html: "Yes, Tuesday.", isHTML: false)
        XCTAssertEqual(document.fill(into, with: body)?.sectionID, "mr6_4")
        XCTAssertNil(related.load(for: "r6/4"), "in its section, not fetched again")
        XCTAssertNotNil(related.load(for: "r6/6"))

        related.clear()
        XCTAssertNil(related.entryID(forSection: "mr6_6"), "the pane moved on")
        XCTAssertNil(related.load(for: "r6/6"))
    }

    /// Remembered from the last ten minutes: in the first frame, less the
    /// stack's own, nothing looked up, and opened the same way. Remembered as
    /// none: the stack as before and nothing looked up. Not to be completed:
    /// nothing, whatever is remembered.
    func testHisLettersRememberedAreInTheFirstFrameAndOpenTheSameWay() throws {
        let t = thread(inbox(5), inbox(3))
        let stack = Array(t.messages.reversed())
        var related = PaneRelated()
        let first = try XCTUnwrap(related.show(stack, completing: 42,
                                               remembered: found(his(4), his(5, gmail: 9_005))))
        XCTAssertEqual(first, found(his(4)))
        XCTAssertNil(related.lookUp(afterTheNewestCame: true), "nothing to look up")
        let entries = ConversationDocument.stack(of: t, related: first)
        XCTAssertEqual(ids(entries), ["1/3", "r6/4", "1/5"])
        XCTAssertEqual(related.entryID(forSection: "mr6_4"), "r6/4")
        let load = try XCTUnwrap(related.load(for: "r6/4"))
        XCTAssertEqual(load, PaneRelated.Load(entryID: "r6/4", id: "6/4", gmailMessageID: 8_004,
                                              mailboxID: Server.sent))
        var document = PaneDocument()
        document.loaded(.conversation(entries), navigation: nil)
        let body = ConversationDocument.Entry.Rendered(html: "Yes, Tuesday.", isHTML: false)
        XCTAssertEqual(document.fill(related.bodyCame(for: load), with: body)?.sectionID, "mr6_4")

        XCTAssertEqual(related.show(stack, completing: 42, remembered: RelatedLetters.none), RelatedLetters.none)
        XCTAssertNil(related.lookUp(afterTheNewestCame: true))
        XCTAssertNil(related.entryID(forSection: "mr6_4"), "the conversation before forgotten")
        XCTAssertNil(related.show(stack, completing: nil, remembered: found(his(4))))
        XCTAssertNil(related.lookUp(afterTheNewestCame: true))
        XCTAssertNil(related.entryID(forSection: "mr6_4"))
    }

    /// A letter of his under the id of one of the stack's, the two folders
    /// numbered alike, or with the Gmail id of one of them, is left out,
    /// remembered or found late: none of it is shown or can be opened. And
    /// with no stack, nothing goes in.
    func testALetterOfHisUnderAnIDOfTheStacksIsLeftOut() {
        let twin = MessageSummary(id: "6/4", mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                                  subject: "Re: the roof", preview: "the twin",
                                  date: Self.base.addingTimeInterval(4 * 60 + 30), isRead: true,
                                  isFlagged: false, threadID: "1700000000000000042",
                                  gmailMessageID: 9_104, arrived: Self.base.addingTimeInterval(4 * 60 + 30))
        let t = thread(inbox(5), twin, inbox(3))
        let stack = Array(t.messages.reversed())
        let mine = found(his(4), his(2), his(6, gmail: 9_005))

        var remembered = PaneRelated()
        XCTAssertEqual(remembered.show(stack, completing: 42, remembered: mine)?.letters.map(\.id), ["6/2"])
        XCTAssertNil(remembered.entryID(forSection: "mr6_4"))
        XCTAssertNil(remembered.load(for: "r6/4"))
        XCTAssertNil(remembered.load(for: "r6/6"))

        var late = PaneRelated()
        _ = late.show(stack, completing: 42, remembered: nil)
        XCTAssertEqual(late.take(mine, stack: stack).flatMap { $0.entries.map(\.id) }, ["r6/2"])
        XCTAssertNil(late.entryID(forSection: "mr6_4"))
        XCTAssertNil(late.load(for: "r6/4"))
        XCTAssertNotNil(late.load(for: "r6/2"))
        XCTAssertEqual(PaneRelated.apart(mine, from: stack).letters.map(\.id), ["6/2"])
        XCTAssertEqual(late.take(found(his(1)), stack: []).count, 0, "no stack")
    }

    /// The lookup is due once the conversation's newest letter has come, and
    /// once: not if it could not be downloaded, not after the pane has moved
    /// on, and never for a conversation not to be completed.
    func testTheLookupStartsOnceTheNewestLetterHasCome() {
        let stack = [inbox(3), inbox(5)]
        var related = PaneRelated()
        _ = related.show(stack, completing: 42, remembered: nil)
        XCTAssertEqual(related.lookUp(afterTheNewestCame: true), 42)
        XCTAssertNil(related.lookUp(afterTheNewestCame: true), "once")
        _ = related.show(stack, completing: 42, remembered: nil)
        XCTAssertNil(related.lookUp(afterTheNewestCame: false), "the newest not downloaded")
        XCTAssertNil(related.lookUp(afterTheNewestCame: true))
        _ = related.show(stack, completing: 42, remembered: nil)
        related.clear()
        XCTAssertNil(related.lookUp(afterTheNewestCame: true), "the pane moved on")
        _ = related.show(stack, completing: nil, remembered: nil)
        XCTAssertNil(related.lookUp(afterTheNewestCame: true), "not to be completed")
    }

    // MARK: - The memo

    /// Remembered for ten minutes, not a moment after, and not for a clock
    /// set back; forgotten whole; and an answer asked before it was
    /// forgotten never kept after.
    func testTheMemoLastsTenMinutes() {
        let memo = RelatedMemo(now: { [clock] in clock!.now() })
        memo.keep(found(his(1)), inThread: 7, asOf: memo.generation)
        XCTAssertEqual(memo.letters(inThread: 7), found(his(1)))
        XCTAssertNil(memo.letters(inThread: 8))
        clock.advance(by: 599)
        XCTAssertEqual(memo.letters(inThread: 7), found(his(1)))
        clock.advance(by: 1)
        XCTAssertNil(memo.letters(inThread: 7), "ten minutes on")

        memo.keep(found(his(2)), inThread: 7, asOf: memo.generation)
        memo.keep(found(his(3)), inThread: 9, asOf: memo.generation)
        memo.forget()
        XCTAssertNil(memo.letters(inThread: 7))
        XCTAssertNil(memo.letters(inThread: 9))

        // Asked before a forgetting, answered after it: not kept.
        let asked = memo.generation
        memo.forget()
        memo.keep(found(his(4)), inThread: 7, asOf: asked)
        XCTAssertNil(memo.letters(inThread: 7), "an answer from before the forgetting")
        memo.keep(found(his(4)), inThread: 7, asOf: memo.generation)
        XCTAssertEqual(memo.letters(inThread: 7), found(his(4)))

        final class Hands: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_000) }
        let hands = Hands()
        let set = RelatedMemo(now: { hands.now })
        set.keep(found(his(1)), inThread: 7, asOf: set.generation)
        hands.now = hands.now.addingTimeInterval(-50)
        XCTAssertNil(set.letters(inThread: 7), "the clock set back")
        XCTAssertEqual(CompleteThreads.remembered, 600)
    }

    // MARK: - Over the server

    private func makeRepository(transport: MailTransportFactory? = nil) -> IMAPMailRepository {
        let clock = self.clock!
        return IMAPMailRepository(account: server.account, password: server.password,
                                  transport: transport ?? server.transportFactory, recipients: book,
                                  now: { clock.now() }, shelf: keptShelf(for: server.account))
    }

    /// Sam's letter in the Inbox, his reply in Sent Mail alone, and Sam's
    /// answer in the Inbox: one Gmail conversation, newer than every other
    /// letter. Returns the reply's UID in Sent Mail.
    @discardableResult
    private func roof(sentIn sent: String = Server.sent) -> UInt32 {
        let start = Server.newestDate.addingTimeInterval(86_400)
        server.deliver(Server.Letter(from: Server.sam, to: [Server.owner], subject: "B-104 roof",
                                     date: start, text: "Shall we fix the roof?\r\n",
                                     messageID: "<roof-1@example.com>"),
                       to: [Server.inbox, Server.allMail])
        let reply = server.deliver(Server.Letter(from: Server.owner, to: [Server.sam],
                                                 subject: "Re: B-104 roof",
                                                 date: start.addingTimeInterval(3_600),
                                                 text: "Yes, on Tuesday.\r\n", flags: ["\\Seen"],
                                                 messageID: "<roof-2@example.com>",
                                                 inReplyTo: "<roof-1@example.com>",
                                                 joins: "<roof-1@example.com>"),
                                   to: [sent, Server.allMail])
        server.deliver(Server.Letter(from: Server.sam, to: [Server.owner], subject: "Re: B-104 roof",
                                     date: start.addingTimeInterval(7_200),
                                     text: "Tuesday it is.\r\n",
                                     messageID: "<roof-3@example.com>",
                                     inReplyTo: "<roof-2@example.com>",
                                     joins: "<roof-1@example.com>"),
                       to: [Server.inbox, Server.allMail])
        return reply[sent] ?? 0
    }

    /// The Inbox's first page, and its conversation of more than one letter
    /// at the top, as the list groups it.
    private func inboxConversation(_ repository: IMAPMailRepository) async throws
        -> (thread: MessageThread, number: UInt64, besides: Set<UInt64>) {
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let thread = try XCTUnwrap(MessageThread.group(rows).first)
        XCTAssertGreaterThan(thread.count, 1)
        let number = try XCTUnwrap(CompleteThreads.thread(toComplete: thread, listedIn: .inbox,
                                                          searching: false, switchedOn: true))
        return (thread, number, Set(thread.messages.compactMap(\.gmailMessageID)))
    }

    /// Opening an Inbox conversation looks in Sent Mail with one SELECT,
    /// one UID SEARCH X-GM-THRID and one UID FETCH of the hits' summaries,
    /// then one FETCH of their previews, and nothing else: no STORE, MOVE,
    /// COPY or APPEND. His reply comes as a row of Sent Mail's, with its few
    /// words, and the folder's name as the Mailboxes pane has it. Opened, it
    /// comes from Sent Mail, its body peeked at, nothing marked.
    func testALookupIsASelectASearchAndAFetchInSentMailAndThePreviews() async throws {
        let uid = roof()
        let repository = makeRepository()
        let (thread, number, besides) = try await inboxConversation(repository)
        server.clearLog()

        let found = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH", "UID FETCH", "UID FETCH"])
        XCTAssertEqual(server.log[0].command, "SELECT \"[Gmail]/Sent Mail\"")
        XCTAssertEqual(server.log[1].command, "UID SEARCH X-GM-THRID \(number)")
        XCTAssertTrue(server.log[2].command.hasPrefix("UID FETCH \(uid) (UID FLAGS INTERNALDATE"),
                      server.log[2].command)
        XCTAssertTrue(server.log[3].command.hasPrefix("UID FETCH \(uid) (UID BODY.PEEK["),
                      server.log[3].command)
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])

        XCTAssertEqual(found.folderName, "Sent Mail")
        let mine = try XCTUnwrap(found.letters.first)
        XCTAssertEqual(found.letters.count, 1)
        XCTAssertEqual(mine.id, "\(server.uidValidity(of: Server.sent))/\(uid)")
        XCTAssertEqual(mine.mailboxID, Server.sent)
        XCTAssertEqual(mine.subject, "Re: B-104 roof")
        XCTAssertTrue(mine.preview.hasPrefix("Yes, on Tuesday"), mine.preview)
        XCTAssertFalse(thread.messages.contains { $0.gmailMessageID == mine.gmailMessageID })

        server.clearLog()
        let letter = try await repository.loadMessage(id: mine.id, gmailMessageID: mine.gmailMessageID,
                                                      mailboxID: mine.mailboxID)
        XCTAssertTrue(letter.textBody?.contains("Yes, on Tuesday.") == true)
        XCTAssertEqual(server.log.map(\.verb), ["UID FETCH"])
        XCTAssertTrue(server.log[0].command.contains("BODY.PEEK[]"), server.log[0].command)
        XCTAssertEqual(server.flags(uid: uid, in: Server.sent), ["\\Seen"])
        XCTAssertFalse(server.log.contains { ["UID STORE", "UID MOVE", "UID COPY", "APPEND"].contains($0.verb) })
    }

    /// A letter he wrote to himself in the conversation is in the Inbox as
    /// well as Sent Mail: the stack has it already, and the lookup brings
    /// it no second time, whatever the stack's own Gmail ids.
    func testALetterToHimselfShowsOnce() async throws {
        roof()
        server.deliver(Server.Letter(from: Server.owner, to: [Server.owner], subject: "Re: B-104 roof",
                                     date: Server.newestDate.addingTimeInterval(86_400 + 5_400),
                                     text: "A note to myself.\r\n", flags: ["\\Seen"],
                                     messageID: "<roof-self@example.com>",
                                     joins: "<roof-1@example.com>"),
                       to: [Server.inbox, Server.sent, Server.allMail])
        let repository = makeRepository()
        let (thread, number, _) = try await inboxConversation(repository)
        XCTAssertEqual(thread.count, 3)
        let found = await repository.lettersOfHis(inThread: number, besides: [])
        XCTAssertEqual(found.letters.map(\.subject), ["Re: B-104 roof"])
        XCTAssertEqual(found.letters.map(\.preview.first), ["Y"])
    }

    /// A LIST that names no `\Sent` sends nothing: never All Mail in its
    /// place, which holds the conversation's Inbox letters too.
    func testNoSentMailSendsNothingAndNeverAllMail() async throws {
        roof()
        server.unlistedMailboxes = [Server.sent]
        let repository = makeRepository()
        let (_, number, besides) = try await inboxConversation(repository)
        server.clearLog()
        let found = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertEqual(found, .none)
        XCTAssertEqual(server.log.map(\.command), [])
    }

    /// The label is built from the folder's name: a server whose `\Sent`
    /// is called "Sent" says "Found in Sent".
    func testTheLabelIsBuiltFromTheSentFoldersName() async throws {
        server.unlistedMailboxes = [Server.sent]
        server.addFolder("Sent", attributes: ["\\HasNoChildren", "\\Sent"], label: "\\Sent",
                         validity: 77, firstUID: 10)
        roof(sentIn: "Sent")
        let repository = makeRepository()
        let (thread, number, besides) = try await inboxConversation(repository)
        server.clearLog()
        let found = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertEqual(server.log.first?.command, "SELECT \"Sent\"")
        XCTAssertEqual(found.folderName, "Sent")
        XCTAssertEqual(found.letters.map(\.id), ["77/10"])
        let html = ConversationDocument.html(entries: ConversationDocument.stack(of: thread, related: found),
                                             inset: 20, bodyPointSize: 17, lineHeight: 1.4)
        XCTAssertTrue(html.contains("<div class=\"bm-found\">Found in Sent</div>"), html)
    }

    /// Sent Mail refused, NO to its SELECT or BAD to the search: nothing
    /// found and nothing thrown, so no alert; one line in the connection
    /// log; and no conversation looks there again this launch.
    func testARefusalGivesNothingOnceAndStopsTheLookups() async throws {
        for refusal in ["SELECT", "UID SEARCH"] {
            server = ScriptedIMAPServer()
            roof()
            if refusal == "SELECT" { server.refusedMailboxes = [Server.sent] }
            else { server.refusedSearchKeys = ["X-GM-THRID"] }
            let repository = makeRepository()
            let (_, number, besides) = try await inboxConversation(repository)
            server.clearLog()
            let said = notes(saying: "RELATED refused")

            let found = await repository.lettersOfHis(inThread: number, besides: besides)
            XCTAssertEqual(found, .none, refusal)
            XCTAssertEqual(server.log.last?.verb, refusal)
            XCTAssertNotEqual(server.log.last?.status, "OK")
            XCTAssertEqual(notes(saying: "RELATED refused"), said + 1, refusal)

            let sent = server.log.count
            let again = await repository.lettersOfHis(inThread: number, besides: besides)
            let another = await repository.lettersOfHis(inThread: number + 1, besides: [])
            XCTAssertEqual(again, .none)
            XCTAssertEqual(another, .none)
            XCTAssertEqual(server.log.count, sent, "\(refusal): no further lookups")
            XCTAssertEqual(notes(saying: "RELATED refused"), said + 1)
            let isConnected = await repository.isConnected
            XCTAssertTrue(isConnected, "the connection stays up")
        }
    }

    /// The connection lost under the lookup: nothing found, and nothing
    /// tried again: no reconnect, no second search.
    func testALostConnectionGivesNothingAndIsNotTriedAgain() async throws {
        roof()
        let repository = makeRepository()
        let (_, number, besides) = try await inboxConversation(repository)
        server.clearLog()
        server.holdReplies(to: "UID SEARCH")
        let lookup = Task { await repository.lettersOfHis(inThread: number, besides: besides) }
        try await until { await self.server.heldReplies(to: "UID SEARCH") == 1 }
        await server.resetConnections()
        let found = await lookup.value
        server.stopHolding("UID SEARCH")

        XCTAssertEqual(found, .none)
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH"])
        XCTAssertEqual(server.connectionsOpened, 1, "no reconnect")
        // And with no connection up, nothing is sent at all.
        let again = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertEqual(again, .none)
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH"])
        XCTAssertEqual(server.connectionsOpened, 1)
    }

    /// Called off, as the pane moving on calls it off, it stops between
    /// commands: the SELECT on the wire finishes, and nothing follows it.
    func testCancellationStopsTheLookupBetweenCommands() async throws {
        roof()
        let repository = makeRepository()
        let (_, number, besides) = try await inboxConversation(repository)
        server.clearLog()
        server.holdReplies(to: "SELECT")
        let lookup = Task { await repository.lettersOfHis(inThread: number, besides: besides) }
        try await until { await self.server.heldReplies(to: "SELECT") == 1 }
        lookup.cancel()
        await server.releaseReplies(to: "SELECT")
        server.stopHolding("SELECT")
        let found = await lookup.value

        XCTAssertEqual(found, .none)
        XCTAssertEqual(server.log.map(\.verb), ["SELECT"])
        XCTAssertNil(repository.rememberedLettersOfHis(inThread: number, besides: besides))
        let isConnected = await repository.isConnected
        XCTAssertTrue(isConnected)
    }

    /// Without Gmail's extension, or before anything has been listed with
    /// no connection, nothing is sent and no connection is made.
    func testNothingIsSentWithoutGmailsExtensionOrAConnection() async throws {
        let cold = makeRepository()
        let none = await cold.lettersOfHis(inThread: 42, besides: [])
        XCTAssertEqual(none, .none)
        XCTAssertEqual(server.connectionsOpened, 0)
        XCTAssertEqual(server.log.map(\.command), [])

        server.withheldCapabilities = ["X-GM-EXT-1"]
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        let without = await repository.lettersOfHis(inThread: 42, besides: [])
        XCTAssertEqual(without, .none)
        XCTAssertEqual(server.log.map(\.command), [])
    }

    /// The conversation opened again within ten minutes sends nothing, and
    /// its letters are at hand at once for the first frame, less the stack's
    /// own; ten minutes on, it looks again.
    func testAConversationOpenedAgainWithinTenMinutesSendsNothing() async throws {
        roof()
        let repository = makeRepository()
        let (_, number, besides) = try await inboxConversation(repository)
        XCTAssertNil(repository.rememberedLettersOfHis(inThread: number, besides: besides))
        let first = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertEqual(first.letters.count, 1)
        server.clearLog()

        let again = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertEqual(again, first)
        XCTAssertEqual(repository.rememberedLettersOfHis(inThread: number, besides: besides), first)
        let mine = try XCTUnwrap(first.letters.first?.gmailMessageID)
        XCTAssertEqual(repository.rememberedLettersOfHis(inThread: number, besides: besides.union([mine])),
                       RelatedLetters(folderName: "Sent Mail", letters: []))
        XCTAssertEqual(server.log.map(\.command), [])

        clock.advance(by: 600)
        XCTAssertNil(repository.rememberedLettersOfHis(inThread: number, besides: besides))
        let later = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertEqual(later, first)
        // Sent Mail still open on the connection: its news asked for first,
        // in place of the SELECT, so a letter filed since is found.
        XCTAssertEqual(server.log.map(\.verb), ["NOOP", "UID SEARCH", "UID FETCH", "UID FETCH"])
    }

    /// A reply Gmail files in Sent Mail while the connection has it open,
    /// as after a conversation looked up a moment before, is found by the
    /// next lookup: Sent Mail's news is asked for first, as a listing asks,
    /// and not taken from a keystroke's ten seconds.
    func testAReplyFiledWhileSentMailIsOpenIsFound() async throws {
        roof()
        let repository = makeRepository()
        let (_, number, besides) = try await inboxConversation(repository)
        let first = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertEqual(first.letters.count, 1)
        _ = server.arrive(Server.Letter(from: Server.owner, to: [Server.sam], subject: "Re: B-104 roof",
                                        date: Server.newestDate.addingTimeInterval(86_400 + 9_000),
                                        text: "And the gutter.\r\n", flags: ["\\Seen"],
                                        messageID: "<roof-4@example.com>",
                                        joins: "<roof-1@example.com>"),
                          in: [Server.sent, Server.allMail])
        await repository.forgetLettersOfHis()
        clock.advance(by: 5)
        server.clearLog()

        let again = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertEqual(server.log.map(\.verb), ["NOOP", "UID SEARCH", "UID FETCH", "UID FETCH"])
        XCTAssertEqual(again.letters.map(\.preview.first), ["Y", "A"])
    }

    /// A letter he sends, his Refresh and a new password saved each forget
    /// what was found, so a reply just sent is looked for afresh.
    func testASendARefreshAndAPasswordSavedForgetWhatWasFound() async throws {
        roof()
        let imap = server.transportFactory
        let repository = makeRepository(transport: { host, port in
            port == 465 ? ScriptedSubmission() : imap(host, port)
        })
        let (_, number, besides) = try await inboxConversation(repository)

        _ = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertNotNil(repository.rememberedLettersOfHis(inThread: number, besides: besides))
        var draft = Draft.blank(signature: "")
        draft.to = ["sam@example.com"]
        draft.subject = "Re: B-104 roof"
        draft.body = "And the gutter."
        try await repository.send(draft)
        XCTAssertNil(repository.rememberedLettersOfHis(inThread: number, besides: besides), "a send")

        _ = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertNotNil(repository.rememberedLettersOfHis(inThread: number, besides: besides))
        await repository.forgetLettersOfHis()
        XCTAssertNil(repository.rememberedLettersOfHis(inThread: number, besides: besides), "Refresh")

        _ = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertNotNil(repository.rememberedLettersOfHis(inThread: number, besides: besides))
        await repository.retire()
        XCTAssertNil(repository.rememberedLettersOfHis(inThread: number, besides: besides), "a password")
        let retired = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertEqual(retired, .none)
    }

    /// Forgotten while a lookup is out, as a letter he sent landing forgets
    /// it between the lookup's SEARCH and its last FETCH: the lookup's
    /// answer is shown, and not kept, so the next opening asks again and
    /// finds the reply filed meanwhile, where it was served without it for
    /// ten minutes.
    func testALookupOutWhenTheMemoIsForgottenIsNotKept() async throws {
        roof()
        let repository = makeRepository()
        let (_, number, besides) = try await inboxConversation(repository)
        server.clearLog()
        server.holdReplies(to: "UID FETCH")
        let lookup = Task { await repository.lettersOfHis(inThread: number, besides: besides) }
        try await until { await self.server.heldReplies(to: "UID FETCH") == 1 }
        _ = server.arrive(Server.Letter(from: Server.owner, to: [Server.sam], subject: "Re: B-104 roof",
                                        date: Server.newestDate.addingTimeInterval(86_400 + 9_000),
                                        text: "And the gutter.\r\n", flags: ["\\Seen"],
                                        messageID: "<roof-4@example.com>",
                                        joins: "<roof-1@example.com>"),
                          in: [Server.sent, Server.allMail])
        await repository.forgetLettersOfHis()
        await server.releaseReplies(to: "UID FETCH")
        let first = await lookup.value
        XCTAssertEqual(first.letters.count, 1, "the answer it had, shown")
        XCTAssertNil(repository.rememberedLettersOfHis(inThread: number, besides: besides), "and not kept")

        server.clearLog()
        let again = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertTrue(server.log.contains { $0.command == "UID SEARCH X-GM-THRID \(number)" })
        XCTAssertEqual(again.letters.map(\.preview.first), ["Y", "A"])
        XCTAssertEqual(repository.rememberedLettersOfHis(inThread: number, besides: besides), again)
    }

    /// The Outbox finding in Sent Mail a letter whose sending it could not
    /// be sure of, its 250 lost, forgets what was found, as a send does; a
    /// look that finds none leaves it.
    func testTheOutboxFindingHisLetterForgetsWhatWasFound() async throws {
        roof()
        let repository = makeRepository()
        let (_, number, besides) = try await inboxConversation(repository)
        _ = await repository.lettersOfHis(inThread: number, besides: besides)
        XCTAssertNotNil(repository.rememberedLettersOfHis(inThread: number, besides: besides))

        let none = try await repository.sentMail(holds: ["<never-sent@example.com>"])
        XCTAssertEqual(none, [])
        XCTAssertNotNil(repository.rememberedLettersOfHis(inThread: number, besides: besides),
                        "nothing found, nothing forgotten")

        let found = try await repository.sentMail(holds: ["<roof-2@example.com>"])
        XCTAssertEqual(found, ["<roof-2@example.com>"])
        XCTAssertNil(repository.rememberedLettersOfHis(inThread: number, besides: besides))
    }

    /// The few words of his lines are fetched only while Sent Mail is still
    /// the folder open: a letter he opened in the Inbox while the search was
    /// out goes first and opens the Inbox, and then nothing more is sent
    /// for the lookup, no second SELECT of his Sent Mail and none of the
    /// Inbox after it. His line goes without its words.
    func testHisLinesGoWithoutTheirWordsOnceTheInboxIsOpen() async throws {
        roof()
        let repository = makeRepository()
        let (thread, number, besides) = try await inboxConversation(repository)
        server.clearLog()
        server.holdReplies(to: "UID SEARCH")
        let lookup = Task { await repository.lettersOfHis(inThread: number, besides: besides) }
        try await until { await self.server.heldReplies(to: "UID SEARCH") == 1 }
        let newest = thread.newest
        let opened = Task {
            try await repository.loadMessage(id: newest.id, gmailMessageID: newest.gmailMessageID,
                                             mailboxID: newest.mailboxID)
        }
        try await until { await repository.waitingForExchange == 1 }
        await server.releaseReplies(to: "UID SEARCH")
        let found = await lookup.value
        _ = try await opened.value

        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH", "UID FETCH", "SELECT", "UID FETCH"])
        XCTAssertEqual(server.log[3].command, "SELECT \"INBOX\"")
        XCTAssertTrue(server.log[4].command.contains("BODY.PEEK[]"), server.log[4].command)
        XCTAssertEqual(found.letters.count, 1)
        XCTAssertEqual(found.letters.first?.preview, "")
    }

    // MARK: - The switch

    /// On unless he has turned it off: read with `object(forKey:)`, so an
    /// absent value is on and an explicit off stays off.
    func testTheSwitchIsOnUntilTurnedOff() {
        XCTAssertEqual(ConversationSettings.completeThreadsKey, "blackmail.completeThreads")
        UserDefaults.standard.removeObject(forKey: ConversationSettings.completeThreadsKey)
        XCTAssertTrue(ConversationSettings.completeThreads)
        ConversationSettings.completeThreads = false
        XCTAssertFalse(ConversationSettings.completeThreads)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "blackmail.completeThreads") as? Bool, false)
        ConversationSettings.completeThreads = true
        XCTAssertTrue(ConversationSettings.completeThreads)
        XCTAssertTrue(SafeStart.viewSettings.contains(ConversationSettings.completeThreadsKey),
                      "a safe start puts it back on")
        let settings = (try? source("Mail/ConversationSettings.swift")) ?? ""
        XCTAssertTrue(settings.contains("UserDefaults.standard.object(forKey: completeThreadsKey) "
                                        + "as? Bool ?? true"), settings)
    }

    /// Settings has it under Organize by Thread, with Mail's words, the
    /// switch called by them and the row one stop, and the line under it
    /// from Apple's own; turned, it is saved at once.
    func testSettingsHasTheSwitchUnderOrganizeByThread() throws {
        let code = try source("UI/SettingsViewController.swift")
        let organize = try XCTUnwrap(code.range(of: "stack.addArrangedSubview(organizeRow)"))
        let complete = try XCTUnwrap(code.range(of: "stack.addArrangedSubview(completeRow)"))
        XCTAssertLessThan(organize.lowerBound, complete.lowerBound)
        for wiring in [
            "private static let completeTitle = \"Complete Threads\"",
            "private static let completeCaption = \"Show all the messages in a thread, "
                + "even if some have been moved to other mailboxes.\"",
            "stack.addArrangedSubview(completeRow) stack.addArrangedSubview(caption(Self.completeCaption)) "
                + "completeSwitch.isOn = ConversationSettings.completeThreads "
                + "completeSwitch.accessibilityLabel = Self.completeTitle",
            "label.text = Self.completeTitle label.isAccessibilityElement = false",
            "@objc private func completeToggled() { "
                + "ConversationSettings.completeThreads = completeSwitch.isOn }",
        ] {
            XCTAssertTrue(code.contains(wiring), wiring)
        }
    }

    // MARK: - The wiring, read from the source

    /// The list asks for his letters with the conversation it opens, by the
    /// rule above, and the container hands it to the pane; the list itself
    /// never has them: not its rows, its letters, its Edit mode or its
    /// counts.
    func testTheListAsksAndNeverHasThem() throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains("var onSelectThread: ((MessageThread, UInt64?) -> Void)?"))
        XCTAssertTrue(list.contains("onSelectThread?(thread, CompleteThreads.thread( toComplete: thread, "
                                    + "listedIn: mailbox.role, searching: letters.isSearching, "
                                    + "switchedOn: ConversationSettings.completeThreads))"), list)
        let root = try source("UI/RootViewController.swift")
        XCTAssertTrue(root.contains("list.onSelectThread = { [weak self] thread, completing in "
                                    + "self?.detail.show(thread: thread, completing: completing) }"))
        for file in ["UI/MessageListViewController.swift", "UI/RootViewController.swift",
                     "Mail/ListLetters.swift", "Mail/ListBatch.swift", "Mail/ListEdit.swift",
                     "Mail/PaneActions.swift", "Mail/FolderCounts.swift", "Mail/MailShelf.swift",
                     "Mail/LocalDrafts.swift"] {
            let code = try source(file)
            for never in ["lettersOfHis", "RelatedLetters", "relatedID", "related[", "PaneRelated"] {
                XCTAssertFalse(code.contains(never), "\(file): \(never)")
            }
        }
    }

    /// The pane draws his letters remembered in the first frame, and
    /// otherwise looks for them aside once the conversation's newest letter
    /// has come, and only then: not as the stack opens. What it holds of
    /// them is `PaneRelated`'s, given the stack's letters, and forgotten
    /// whenever the pane shows anything else; the loads are called off with
    /// them.
    func testThePaneLooksAfterTheNewestAndForgetsThemWhenItMovesOn() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(code.contains("private var related = PaneRelated()"))
        let show = try section(of: code, from: "func show(thread: MessageThread, completing: UInt64?) {",
                               to: "private func lookForHis(")
        for wiring in [
            "stackLetters = thread.messages.reversed()",
            "let besides = Set(thread.messages.compactMap(\\.gmailMessageID))",
            "let remembered = related.show(stackLetters, completing: completing, remembered: "
                + "completing.flatMap { self.repository.rememberedLettersOfHis(inThread: $0, besides: besides) })",
            "let entries = ConversationDocument.stack(of: thread, related: remembered)",
            "settle: { [weak self] result in self?.settleBody(result, for: newest.id, focus: true) "
                + "self?.lookForHis(afterTheNewestCame: (try? result.get()) != nil, besides: besides) })",
        ] {
            XCTAssertTrue(show.contains(wiring), wiring)
        }
        let order = ["stackLetters = thread.messages.reversed()", "related.show(stackLetters",
                     "ConversationDocument.stack(of: thread, related: remembered)"]
            .compactMap { show.range(of: $0)?.lowerBound }
        XCTAssertEqual(order.count, 3)
        XCTAssertEqual(order, order.sorted(), "the stack's letters before his, his before the first frame")
        XCTAssertFalse(show.contains("loads.aside("), "not as the stack opens")
        XCTAssertFalse(show.contains("lettersOfHis("), "not as the stack opens")

        let look = try section(of: code, from: "private func lookForHis(", to: "private func takeRelated(")
        XCTAssertTrue(look.contains("private func lookForHis(afterTheNewestCame came: Bool, besides: Set<UInt64>) { "
                                    + "guard let thread = related.lookUp(afterTheNewestCame: came) else { return } "
                                    + "let repository = self.repository "
                                    + "loads.aside({ await repository.lettersOfHis(inThread: thread, besides: besides) }, "
                                    + "settle: { [weak self] found in self?.takeRelated(found) }) }"), look)
        XCTAssertEqual(code.components(separatedBy: "lookForHis(").count, 3, "called from the newest's settling alone")
        XCTAssertEqual(code.components(separatedBy: "loads.aside(").count, 2)

        for start in ["func showEmpty() {", "func show(summary: MessageSummary) {"] {
            let whole = try section(of: code, from: start, to: "placeholder.")
            XCTAssertTrue(whole.contains("stackLetters = [] related.clear()"), start)
        }
        let empty = try section(of: code, from: "func showEmpty() {", to: "func clearIfShowingDeletedMessage")
        XCTAssertTrue(empty.contains("loads.supersede()"))
    }

    /// His letters go in once they have come, through the document, which
    /// holds them while the stack loads; at its finish they go in before the
    /// bodies; and by the stack's `bmInsert`, in the app's content world.
    func testHisLettersGoInByTheDocumentOnceTheStackHasLoaded() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        let take = try section(of: code, from: "private func takeRelated(_ found: RelatedLetters) {",
                               to: "private func loadRelated(")
        XCTAssertTrue(take.contains("private func takeRelated(_ found: RelatedLetters) { "
                                    + "for place in related.take(found, stack: stackLetters) { "
                                    + "guard let insert = document.insert(place.entries, before: place.before) "
                                    + "else { continue } run(insert) } }"), take)
        XCTAssertTrue(code.contains("private func run(_ insert: ConversationDocument.Insert) { "
                                    + "let moving = stackMoving "
                                    + "webView.callAsyncJavaScript(ConversationDocument.Insert.script, "
                                    + "arguments: insert.arguments(moving: moving), in: nil, in: .defaultClient) "
                                    + "if moving { watchTheStack() } }"))
        XCTAssertTrue(code.contains("let finished = document.didFinish(ObjectIdentifier(navigation)) "
                                    + "for insert in finished.inserts { run(insert) } "
                                    + "for fill in finished.fills { run(fill) }"))
    }

    /// The pane's word to the stack's script on its scroll view (B-104):
    /// moving while UIKit's scroll view tracks a finger, drags or
    /// decelerates, which is how the page learns of a finger it never
    /// heard, held still or not, and of a bounce. Said with each insert,
    /// and while it moves, every tenth of a second on the main run loop's
    /// common modes, which a drag does not hold up, to the page on screen;
    /// the ticks stop at the first word that it is still, and are the
    /// only other way the word goes. `HisLineUnderTheFingerTests` runs the
    /// script with a model of it.
    func testThePaneTellsTheStackWhetherItsScrollViewMovesIt() throws {
        for tracking in [false, true] {
            for dragging in [false, true] {
                for decelerating in [false, true] {
                    XCTAssertEqual(ConversationDocument.Motion.stack(tracking: tracking, dragging: dragging,
                                                                     decelerating: decelerating),
                                   tracking || dragging || decelerating)
                }
            }
        }
        XCTAssertEqual(ConversationDocument.Motion.every, 0.1)
        XCTAssertEqual(ConversationDocument.Motion.script, "bmPaneMoving(moving)")
        XCTAssertEqual(ConversationDocument.Motion.arguments(true)["moving"] as? Bool, true)
        XCTAssertEqual(ConversationDocument.Motion.arguments(false)["moving"] as? Bool, false)
        XCTAssertEqual(ConversationDocument.Motion.arguments(true).count, 1)

        let code = try source("UI/MessageDetailViewController.swift")
        for wiring in [
            "private var stackMoving: Bool { let scroll = webView.scrollView "
                + "return ConversationDocument.Motion.stack(tracking: scroll.isTracking, dragging: scroll.isDragging, "
                + "decelerating: scroll.isDecelerating) }",
            "private var motionTicks: Timer?",
            "private func watchTheStack() { guard motionTicks == nil else { return } "
                + "let ticks = Timer(timeInterval: ConversationDocument.Motion.every, target: self, "
                + "selector: #selector(motionTick), userInfo: nil, repeats: true) "
                + "RunLoop.main.add(ticks, forMode: .common) motionTicks = ticks }",
            "@objc private func motionTick() { let moving = stackMoving "
                + "webView.callAsyncJavaScript(ConversationDocument.Motion.script, "
                + "arguments: ConversationDocument.Motion.arguments(moving), in: nil, in: .defaultClient) "
                + "guard !moving else { return } motionTicks?.invalidate() motionTicks = nil }",
        ] {
            XCTAssertTrue(code.contains(wiring), wiring)
        }
        XCTAssertEqual(code.components(separatedBy: "watchTheStack()").count - 1, 2, "defined, and run by an insert")
        XCTAssertEqual(code.components(separatedBy: "ConversationDocument.Motion.script").count - 1, 1)
        XCTAssertEqual(code.components(separatedBy: "motionTicks = ").count - 1, 2, "set by the watch, cleared by a tick")
    }

    /// A tap on his line opens or closes it and fetches its body, and does
    /// nothing else, before the conversation's own letters are looked at: no
    /// read mark, and no focus, so the header and the toolbar stay on the
    /// letter he opened last whether they follow a letter when its body
    /// lands, as now, or at the tap. And his body landing has no way to
    /// the header: its load and its settling touch none of what the
    /// toolbar acts on, and never reach `focusLetter`.
    func testATapOnHisLineNeitherMarksNorFocuses() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        let tapped = try section(of: code, from: "func userContentController(",
                                 to: "private func markOpened(")
        let his = try XCTUnwrap(tapped.range(of: "if let his = related.entryID(forSection: sectionID) { "
                                             + "document.setOpen(opened, his) if opened { loadRelated(his) } "
                                             + "return }"), tapped)
        let theirs = try XCTUnwrap(tapped.range(of: "loadBody(for: id, focus: true)"))
        XCTAssertLessThan(his.upperBound, theirs.lowerBound, "his returns before the conversation's")
        XCTAssertLessThan(his.upperBound, try XCTUnwrap(tapped.range(of: "markOpened(id)")).lowerBound)

        let related = try section(of: code, from: "private func loadRelated(",
                                  to: "private static let couldNotDownload")
        for never in ["focusLetter", "markOpened", "onLetterOpened", "drawBody", "settleBody",
                      "loadBody", "focused", "message =", "summary =", "self.summary", "loaded[",
                      "threadSummaries", "stackLetters", "header.", "setActionsEnabled"] {
            XCTAssertFalse(related.contains(never), never)
        }
        // What it fetches, and where the body goes, are `PaneRelated`'s
        // (`testHisLetterFoundLateOpensFromSentMailIntoItsOwnSection`): his
        // own section, never one by the letter's id.
        for wiring in [
            "guard let load = related.load(for: entryID) else { return }",
            "loads.start({ try await repository.loadMessage(id: load.id, gmailMessageID: load.gmailMessageID, "
                + "mailboxID: load.mailboxID) }, prepare: { m in (m, PanePage.stackBody(m)) }, "
                + "settle: { [weak self] result in self?.settleRelated(result, for: load) })",
            "case .success(let (m, body)): prepareInlineImages(for: [m]) related.keep(m, for: load) "
                + "fill(related.bodyCame(for: load), body) "
                + "case .failure: fill(load.entryID, Self.couldNotDownload)",
        ] {
            XCTAssertTrue(related.contains(wiring), wiring)
        }
        XCTAssertFalse(related.contains("fill(m.id"))
        let take = try section(of: code, from: "private func takeRelated(", to: "private func loadRelated(")
        for never in ["focusLetter", "markOpened", "focused", "summary =", "message ="] {
            XCTAssertFalse(take.contains(never), never)
        }
    }

    /// Nothing of his letters is kept on the iPad: nothing in the lookup,
    /// the previews it fetches, or the pane's handling of them reaches the
    /// copy kept on the iPad or the letters kept there.
    func testHisLettersAreNeverKept() throws {
        let repository = try source("Mail/IMAPMailRepository.swift")
        let lookup = try section(of: repository, from: "func lettersOfHis(inThread thread: UInt64",
                                 to: "private func letterFiles(")
        let previews = try section(of: repository, from: "private func previewTexts(",
                                   to: "private static func preview(from")
        let pane = try source("UI/MessageDetailViewController.swift")
        let handling = try section(of: pane, from: "private func lookForHis(",
                                   to: "private var pageStyle")
        let held = try source("Mail/PaneRelated.swift")
        for (name, code) in [("lookup", lookup), ("previews", previews), ("pane", handling), ("held", held)] {
            for never in ["shelf", "MailShelf", "LocalDrafts", "kept.", "Outbox"] {
                XCTAssertFalse(code.contains(never), "\(name): \(never)")
            }
        }
        // The rows' own path is the one every row takes, and keeps nothing.
        let rows = try section(of: repository, from: "private func rows(from fetched:",
                               to: "func messages(around date: Date")
        XCTAssertFalse(rows.contains("shelf"))
        XCTAssertTrue(lookup.contains("hisLetters.keep(found, inThread: thread, asOf: asOf)"))
        XCTAssertTrue(lookup.contains("try await previewTexts(for: letters.map(\\.id), in: sent, client: client, "
                                      + "whileOpen: true)"))
        XCTAssertFalse(lookup.contains("previews(for:"), "not the previews the kept page takes")
        XCTAssertTrue(repository.contains("nonisolated let hisLetters: RelatedMemo"))
    }

    /// Nothing of his letters is kept on the iPad by the lookup either: the
    /// few words fetched for his line do not reach Sent Mail's page kept on
    /// the iPad, where his reply is a row already, and no other kept page
    /// gains it.
    func testTheLookupLeavesTheKeptCopyAsItWas() async throws {
        roof()
        let repository = makeRepository()
        let sentPage = try await repository.listMessages(in: Server.sent, beforeUID: nil, limit: 50)
        let (_, number, besides) = try await inboxConversation(repository)
        let shelf = try XCTUnwrap(repository.shelf)
        let before = shelf.page(of: Server.sent)?.rows
        let inboxBefore = shelf.page(of: "inbox")?.rows

        let found = await repository.lettersOfHis(inThread: number, besides: besides)
        let mine = try XCTUnwrap(found.letters.first)
        XCTAssertFalse(mine.preview.isEmpty)
        XCTAssertTrue(sentPage.contains { $0.id == mine.id }, "his reply is a row of Sent Mail's")
        XCTAssertEqual(shelf.page(of: Server.sent)?.rows, before)
        XCTAssertEqual(shelf.page(of: Server.sent)?.rows.first { $0.id == mine.id }?.preview, "")
        XCTAssertEqual(shelf.page(of: "inbox")?.rows, inboxBefore)
        XCTAssertFalse(shelf.page(of: "inbox")?.rows.contains { $0.gmailMessageID == mine.gmailMessageID }
                       ?? true)
    }

    /// What forgets the memo: a letter sent once the server has it, his
    /// Refresh before its page, and the repository retired for a new
    /// password.
    func testWhatForgetsIsWiredWhereItSays() throws {
        let repository = try source("Mail/IMAPMailRepository.swift")
        XCTAssertTrue(repository.contains("self.recipients.used(address: MailFormat.bareAddress(address)) } "
                                          + "hisLetters.forget()"))
        XCTAssertTrue(repository.contains("func retire() async { retired = true hisLetters.forget() "
                                          + "await imap.retire() }"))
        XCTAssertTrue(repository.contains("if !found.isEmpty { self.hisLetters.forget() } return found"))
        let lookup = try section(of: repository, from: "func lettersOfHis(inThread thread: UInt64",
                                 to: "nonisolated func rememberedLettersOfHis(")
        let asOf = try XCTUnwrap(lookup.range(of: "let asOf = hisLetters.generation"))
        let search = try XCTUnwrap(lookup.range(of: "try await client.search("))
        XCTAssertLessThan(asOf.lowerBound, search.lowerBound, "taken before Sent Mail is asked")
        XCTAssertTrue(lookup.contains("hisLetters.keep(found, inThread: thread, asOf: asOf)"))
        let list = try source("UI/MessageListViewController.swift")
        let refresh = try section(of: list, from: "@objc private func refreshTapped() {",
                                  to: "@objc private func editTapped()")
        XCTAssertTrue(refresh.contains("defer { checking?() } await self.repository.forgetLettersOfHis() "
                                       + "return await self.reload(passing: false) }"), refresh)
    }

    // MARK: - Helpers

    private func notes(saying text: String) -> Int {
        Diagnostics.entries.filter { $0.direction == .note && $0.text == text }.count
    }

    /// Waits, a millisecond at a time and never for more than two seconds,
    /// until `condition` holds.
    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<2_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

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

/// What happened, in order, from any thread.
private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func add(_ event: String) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

/// Holds whoever waits on it until it is opened.
private actor AsyncGate {
    private var opened = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        opened = true
        for waiter in waiting { waiter.resume() }
        waiting = []
    }
}
