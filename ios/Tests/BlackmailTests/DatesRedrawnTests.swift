import XCTest
@testable import Blackmail

/// B-139: the dates already on the screen are written again when the iPad's
/// form or day changes. On the test iPad, after 24-Hour Time was switched on,
/// the status bar read 14:41, and the open letter's header still read "Today
/// at 12:39 PM" and its row "12:39 PM" until a scroll or opening the letter
/// again drew them anew; the same after a change of time zone and back.
///
/// `DisplayDates` lets its formatters go when iOS says the locale or the
/// zone has changed, and then says so on the main queue (`didChange`); the
/// list's rows, the reading pane's header and a conversation's lines write
/// their dates again where they are, on that and as the day turns over
/// (`UIApplication.significantTimeChangeNotification`). The parts that are
/// not UIKit are run here: the word said after the formatters are let go,
/// on the main queue, once for changes that come together; the words the
/// screens write again, for the zone, the clock and the day; the stack's
/// lines as its script writes them, run in node; and the pane's document
/// handing them out when its stack has loaded. The UIKit wiring is read from
/// its source, as `PrintWiringTests` reads the pane's.
final class DatesRedrawnTests: XCTestCase {

    private let newYork = TimeZone(identifier: "America/New_York")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    /// His region (B-119), 24-Hour Time off.
    private let us = Locale(identifier: "en_US")
    /// His region with 24-Hour Time on, as this host's ICU is told it. The
    /// iPad keeps the name, "en_US", and changes the locale's preferences,
    /// which is why `DisplayDates` cannot see the change by the name.
    private let us24 = Locale(identifier: "en_US@hours=h23")
    /// The space the formatter puts before AM and PM.
    private let nb = "\u{202F}"

    /// 2026-10-25 at `hour`:`minute` in New York, or `days` later.
    private func sunday(_ hour: Int, _ minute: Int, plusDays days: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 25 + days,
                                                  hour: hour, minute: minute))!
    }

    /// Whether `note` is `dates`' own. Picked out by hand: this host's
    /// centre matches no object that is not an `NSObject`, and the screens
    /// listen for any.
    private static func said(by dates: DisplayDates, _ note: Notification) -> Bool {
        (note.object as AnyObject?) === dates
    }

    /// Lets the main queue run everything put on it so far.
    private func settle() {
        let drained = expectation(description: "the main queue ran")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
    }

    // MARK: - Said after the formatters are let go

    /// The word comes on the main queue, after iOS's own call has returned,
    /// and an observer of it that writes a date then is given a formatter
    /// built afresh, never the one kept from before: with 24-Hour Time the
    /// locale's name stays "en_US", so a kept formatter would write "12:39
    /// PM" again. For a change of zone and of locale, and for one said on
    /// another thread, as iOS may say it.
    func testTheChangeIsSaidOnTheMainQueueAfterTheFormattersAreLetGo() {
        let center = NotificationCenter()
        let dates = DisplayDates(notifications: center)
        let letter = sunday(12, 39)
        let time = { dates.string(from: letter, .time, locale: self.us, timeZone: self.newYork) }
        XCTAssertEqual(time(), "12:39\(nb)PM")
        XCTAssertEqual(time(), "12:39\(nb)PM")
        let kept = dates.built

        let heard = SaidChanges()
        let token = center.addObserver(forName: DisplayDates.didChange, object: nil,
                                       queue: nil) { note in
            guard Self.said(by: dates, note) else { return }
            let before = dates.built
            let words = time()
            heard.add(SaidChanges.Word(main: Thread.isMainThread,
                                       builtAfresh: dates.built == before + 1, words: words))
        }
        defer { center.removeObserver(token) }

        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        XCTAssertEqual(heard.all, [], "not inside iOS's own call")
        XCTAssertEqual(dates.built, kept, "nothing built yet")
        settle()
        let fresh = SaidChanges.Word(main: true, builtAfresh: true, words: "12:39\(nb)PM")
        XCTAssertEqual(heard.all, [fresh])

        center.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        XCTAssertEqual(heard.all.count, 1, "not inside iOS's own call")
        settle()
        XCTAssertEqual(heard.all.count, 2)
        XCTAssertEqual(heard.all.last, fresh)

        let third = expectation(description: "said from another thread")
        let watch = center.addObserver(forName: DisplayDates.didChange, object: nil,
                                       queue: nil) { note in
            if Self.said(by: dates, note) { third.fulfill() }
        }
        defer { center.removeObserver(watch) }
        DispatchQueue.global().async {
            center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        }
        wait(for: [third], timeout: 5)
        XCTAssertEqual(heard.all.count, 3)
        XCTAssertEqual(heard.all.last, fresh, "on the main queue all the same")
    }

    /// A new zone often comes with its locale, and Settings can say both at
    /// once: the screen is written again once for changes that come
    /// together, not once for each. One that comes after the word has gone
    /// is said again.
    func testChangesThatComeTogetherAreSaidOnce() {
        let center = NotificationCenter()
        let dates = DisplayDates(notifications: center)
        let heard = SaidChanges()
        let token = center.addObserver(forName: DisplayDates.didChange, object: nil,
                                       queue: nil) { note in
            guard Self.said(by: dates, note) else { return }
            heard.add(SaidChanges.Word(main: Thread.isMainThread, builtAfresh: true, words: ""))
        }
        defer { center.removeObserver(token) }

        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        center.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        settle()
        XCTAssertEqual(heard.all.count, 1, "once for the three")

        center.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        settle()
        XCTAssertEqual(heard.all.count, 2, "and again for one after it")
        settle()
        XCTAssertEqual(heard.all.count, 2, "and no more")
    }

    /// The instance the app uses says it where the screens listen, the
    /// default centre, as iOS's own word reaches it there.
    func testTheAppsDatesSayItWhereTheScreensListen() {
        _ = MailFormat.listTimestamp(sunday(12, 39))
        settle()
        let said = expectation(description: "said on the default centre")
        said.assertForOverFulfill = false
        let token = NotificationCenter.default.addObserver(forName: DisplayDates.didChange,
                                                           object: nil, queue: nil) { note in
            if Self.said(by: DisplayDates.shared, note) { said.fulfill() }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        wait(for: [said], timeout: 5)
    }

    // MARK: - The words written again

    /// What the screens write again: a letter of 12:39 PM in New York, seen
    /// at 2:41 PM there, as the test iPad's was. With 24-Hour Time on, then
    /// in Los Angeles, then both, then back: the row, the header and a
    /// conversation's line each follow, as a letter drawn afresh would.
    func testTheWordsWrittenAgainFollowTheZoneAndTheClock() {
        let letter = sunday(12, 39)
        let now = sunday(14, 41)
        let older = sunday(9, 5, plusDays: -20)
        let entries = [entry("5/1", older), entry("5/2", letter)]
        func seen(_ locale: Locale, _ zone: TimeZone) -> [String] {
            let lines = ConversationDocument.Dates(entries, now: now, locale: locale, timeZone: zone).when
            return [MailFormat.listTimestamp(letter, now: now, locale: locale, timeZone: zone),
                    MailFormat.detailTimestamp(letter, now: now, locale: locale, timeZone: zone),
                    lines["m5_2"] ?? "none", lines["m5_1"] ?? "none"]
        }

        XCTAssertEqual(seen(us, newYork),
                       ["12:39\(nb)PM", "Today at 12:39\(nb)PM", "12:39\(nb)PM", "10/5/26"])
        XCTAssertEqual(seen(us24, newYork), ["12:39", "Today at 12:39", "12:39", "10/5/26"],
                       "24-Hour Time on")
        XCTAssertEqual(seen(us, losAngeles),
                       ["9:39\(nb)AM", "Today at 9:39\(nb)AM", "9:39\(nb)AM", "10/5/26"],
                       "in Los Angeles")
        XCTAssertEqual(seen(us24, losAngeles), ["09:39", "Today at 09:39", "09:39", "10/5/26"],
                       "both")
        XCTAssertEqual(seen(us, newYork),
                       ["12:39\(nb)PM", "Today at 12:39\(nb)PM", "12:39\(nb)PM", "10/5/26"],
                       "and back")
    }

    /// And as the day turns over: a letter of 11:50 PM is a time, and
    /// "Today at", until midnight; written again after it, "Yesterday", and
    /// "Yesterday at", as B-043 asked; a week on, its date. The day is
    /// worked out at each writing, so the screen's writing again at
    /// midnight is all that was missing.
    func testTheWordsWrittenAgainFollowTheDay() {
        let letter = sunday(23, 50)
        let entries = [entry("5/9", letter)]
        func seen(_ now: Date) -> [String] {
            [MailFormat.listTimestamp(letter, now: now, locale: us, timeZone: newYork),
             MailFormat.detailTimestamp(letter, now: now, locale: us, timeZone: newYork),
             ConversationDocument.Dates(entries, now: now, locale: us,
                                        timeZone: newYork).when["m5_9"] ?? "none"]
        }

        XCTAssertEqual(seen(sunday(23, 59)), ["11:50\(nb)PM", "Today at 11:50\(nb)PM", "11:50\(nb)PM"])
        XCTAssertEqual(seen(sunday(0, 0, plusDays: 1)),
                       ["Yesterday", "Yesterday at 11:50\(nb)PM", "Yesterday"], "at midnight")
        XCTAssertEqual(seen(sunday(9, 0, plusDays: 2)),
                       ["Sunday", "October 25, 2026 at 11:50\(nb)PM", "Sunday"])
        XCTAssertEqual(seen(sunday(0, 5, plusDays: 7)),
                       ["10/25/26", "October 25, 2026 at 11:50\(nb)PM", "10/25/26"])
    }

    // MARK: - A conversation's lines

    private func entry(_ id: String, _ date: Date, open: Bool = false) -> ConversationDocument.Entry {
        ConversationDocument.Entry(id: id, sender: "Sam Example <sam@example.com>", date: date,
                                   body: nil, isExpanded: open, preview: "A few words")
    }

    /// The words for each line are the ones the stack writes on it when it
    /// is drawn, by its section, every letter's, his from Sent Mail among
    /// them; sent to `bmWhen` as its one argument, in the app's world.
    func testTheStacksLinesAreWrittenAsTheStackWritesThem() throws {
        let now = Date()
        var his = entry("9/4", now.addingTimeInterval(-3 * 86_400))
        his.foundIn = "Sent Mail"
        let entries = [entry("5/1", now.addingTimeInterval(-40 * 86_400)), his,
                       entry("5/2", now.addingTimeInterval(-60), open: true)]
        let dates = ConversationDocument.Dates(entries)
        let page = ConversationDocument.html(entries: entries, inset: 22, bodyPointSize: 17,
                                             lineHeight: 1.3)

        XCTAssertEqual(Set(dates.when.keys), ["m5_1", "m9_4", "m5_2"])
        for e in entries {
            let words = try XCTUnwrap(dates.when[ConversationDocument.sectionID(for: e.id)])
            XCTAssertEqual(words, MailFormat.listTimestamp(e.date), e.id)
            XCTAssertTrue(page.contains("<span class=\"bm-when\">\(ConversationDocument.escape(words))</span>"),
                          "the line as drawn: \(e.id)")
        }
        XCTAssertEqual(ConversationDocument.Dates.script, "bmWhen(when)")
        XCTAssertEqual(dates.arguments.keys.sorted(), ["when"])
        XCTAssertEqual(dates.arguments["when"] as? [String: String], dates.when)
        XCTAssertTrue(ConversationDocument.script.contains("function bmWhen(when) {"))
    }

    /// `bmWhen` itself, run in node over a model of the stack's page: each
    /// line's date written, and nothing else. Not a `bm-when` inside a
    /// letter's own markup, nor a section a letter's markup makes with a
    /// line's id; not a line it has no words for; not a line whose words
    /// are already the same. While the stack holds letters back, as it
    /// moves (`bmLater`), it writes what is on the page and goes again
    /// behind them, so those have theirs too once they are in.
    func testBmWhenWritesTheLinesAloneAndWaitsBehindWhatIsHeld() throws {
        let run = try node(Self.whenProgram)
        XCTAssertEqual(run["lines"] as? [String: String],
                       ["mA": "12:39", "mB": "Yesterday", "mC": "Sunday"])
        XCTAssertEqual(run["writes"] as? [String: Int], ["mA": 1, "mB": 0, "mC": 0],
                       "B's words were the same, C had none")
        XCTAssertEqual(run["others"] as? [String], ["the letter's own", "its own line", "Sunday"],
                       "a letter's markup left alone")
        XCTAssertEqual(run["heldAfterFirst"] as? Int, 0, "nothing held, nothing waits")
        XCTAssertEqual(run["heldAfterSecond"] as? Int, 2, "behind the letters held")
        XCTAssertEqual(run["inserted"] as? String, "14:41", "the letter held has its date once in")
    }

    /// The stack's page as `section` draws it, in miniature, and `bmWhen`
    /// taken out of the script and run on it.
    private static let whenProgram = #"""
    function make(spec, parent) {
      var e = { id: spec.id || '', className: spec.cls || '', kids: [], text: spec.text || '',
                parent: parent, writes: 0 };
      e.classList = { contains: function (c) { return e.className.split(/\s+/).indexOf(c) !== -1; } };
      Object.defineProperty(e, 'firstElementChild', { get: function () { return e.kids[0] || null; } });
      Object.defineProperty(e, 'nextElementSibling', { get: function () {
        if (!e.parent) return null;
        return e.parent.kids[e.parent.kids.indexOf(e) + 1] || null;
      } });
      Object.defineProperty(e, 'textContent', {
        get: function () { return e.kids.length ? e.kids.map(function (k) { return k.textContent; }).join('') : e.text; },
        set: function (v) { e.kids = []; e.text = String(v); e.writes += 1; } });
      e.kids = (spec.kids || []).map(function (k) { return make(k, e); });
      return e;
    }
    function letter(id, when, inside) {
      return { cls: 'bm-letter', id: id, kids: [
        { cls: 'bm-head', kids: [{ cls: 'bm-from', text: 'Sam' }, { cls: 'bm-peek', text: 'A few words' },
                                 { cls: 'bm-when', text: when }] },
        { cls: 'bm-body bm-html', kids: inside || [] }] };
    }
    var body = make({ cls: '', kids: [
      letter('mA', '12:39 PM', [{ cls: 'bm-when', text: "the letter's own" },
                                letter('mB', 'its own line')]),
      letter('mB', 'Yesterday'),
      letter('mC', 'Sunday'),
      { cls: 'bm-found', id: 'mD', kids: [{ cls: 'bm-head', kids: [{ cls: 'bm-when', text: 'Sunday' }] }] }
    ] }, null);
    var document = { querySelectorAll: function (selector) {
      if (selector !== 'body > .bm-letter') throw new Error('asked for ' + selector);
      return body.kids.filter(function (k) { return k.classList.contains('bm-letter'); });
    } };
    var bmHeld = [];
    function bmLater(change) { bmHeld.push(change); }
    eval(INPUT.when);
    var when = { mA: '12:39', mB: 'Yesterday', mD: '9:00', mE: '14:41' };
    bmWhen(when);
    var heldAfterFirst = bmHeld.length;
    bmHeld.push(function () { body.kids.push(make(letter('mE', '2:41 PM'), body)); });
    bmWhen(when);
    var heldAfterSecond = bmHeld.length;
    var held = bmHeld;
    bmHeld = [];
    held.forEach(function (change) { change(); });
    function line(e) { return e.kids[0].kids[2]; }
    var lines = {}, writes = {};
    body.kids.slice(0, 3).forEach(function (e) { lines[e.id] = line(e).text; writes[e.id] = line(e).writes; });
    var a = body.kids[0].kids[1];
    process.stdout.write(JSON.stringify({
      lines: lines, writes: writes,
      others: [a.kids[0].text, line(a.kids[1]).text, body.kids[3].kids[0].kids[0].text],
      heldAfterFirst: heldAfterFirst, heldAfterSecond: heldAfterSecond,
      inserted: line(body.kids[4]).text }));
    """#

    /// `program` run in node with `INPUT.when`, `bmWhen` as the stack's
    /// script defines it, and what it wrote. Skipped where there is no node.
    private func node(_ program: String) throws -> [String: Any] {
        let script = ConversationDocument.script
        let start = try XCTUnwrap(script.range(of: "function bmWhen(when) {"))
        let end = try XCTUnwrap(script.range(of: "\n}\n", range: start.upperBound..<script.endIndex))
        let when = String(script[start.lowerBound..<end.upperBound])
        let input = try JSONSerialization.data(withJSONObject: ["when": when])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "-e",
                             "var INPUT = JSON.parse(require('fs').readFileSync(0, 'utf8'));\n" + program]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() } catch { throw XCTSkip("no node on this host") }
        stdin.fileHandleForWriting.write(input)
        try stdin.fileHandleForWriting.close()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus == 127 { throw XCTSkip("no node on this host") }
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: err, as: UTF8.self))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: out) as? [String: Any])
    }

    // MARK: - The pane's document

    /// Stands in for a `WKNavigation`, whose identity is all the pane uses.
    private final class Navigation {}

    /// The pane's document hands out the stack's dates once its stack has
    /// loaded, every letter's, his letters put in among them included; a
    /// stack still loading, which may have been written before the change,
    /// has them written as it finishes, after what else waited for it. Not
    /// when the pane shows no stack, nor when WebKit has lost it, as the
    /// redraw writes the lines afresh; and not for a stack another has
    /// replaced.
    func testThePaneWritesTheStacksDatesOnceItHasLoaded() throws {
        var document = PaneDocument()
        XCTAssertNil(document.dates(), "nothing in the pane")
        document.loaded(.notice([PaneNotice.loading]), navigation: nil)
        XCTAssertNil(document.dates(), "grey words")

        let now = Date()
        let stack = [entry("5/1", now.addingTimeInterval(-86_400)),
                     entry("5/2", now.addingTimeInterval(-60), open: true)]
        let first = Navigation()
        document.loaded(.conversation(stack), navigation: ObjectIdentifier(first))
        XCTAssertNil(document.dates(), "still loading")
        let fill = ConversationDocument.Entry.Rendered(html: "Dear Sam,", isHTML: false)
        XCTAssertNil(document.fill("5/2", with: fill))
        let finished = document.didFinish(ObjectIdentifier(first))
        XCTAssertEqual(finished.fills.count, 1)
        XCTAssertEqual(finished.dates, ConversationDocument.Dates(stack), "once it has loaded")
        XCTAssertEqual(document.didFinish(ObjectIdentifier(first)), PaneDocument.Finished(), "once")

        XCTAssertEqual(document.dates(), ConversationDocument.Dates(stack), "loaded: at once")
        var his = entry("9/4", now.addingTimeInterval(-3 * 86_400))
        his.foundIn = "Sent Mail"
        XCTAssertNotNil(document.insert([his], before: "5/2"))
        let more = entry("5/3", now)
        XCTAssertNotNil(document.append([more]))
        let all = [stack[0], his, stack[1], more]
        XCTAssertEqual(document.dates(), ConversationDocument.Dates(all), "every letter of it")

        // Nothing owed to a stack another has replaced, nor to one WebKit lost.
        let second = Navigation(), third = Navigation()
        document.loaded(.conversation(stack), navigation: ObjectIdentifier(second))
        XCTAssertNil(document.dates())
        document.loaded(.conversation(stack), navigation: ObjectIdentifier(third))
        XCTAssertNil(document.didFinish(ObjectIdentifier(third)).dates, "drawn after the change")
        document.contentProcessEnded()
        XCTAssertNil(document.dates(), "lost: the redraw writes them afresh")
        let redraw = try XCTUnwrap(document.redraw())
        let fourth = Navigation()
        document.loaded(redraw.content, navigation: ObjectIdentifier(fourth))
        XCTAssertNil(document.didFinish(ObjectIdentifier(fourth)).dates)
        XCTAssertEqual(document.dates(), ConversationDocument.Dates(stack))
    }

    // MARK: - The screens, read

    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    /// The code from `start` up to the end of `end`, both found.
    private func part(of code: String, from start: String, through end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start), start)
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex), end)
        return String(code[from.lowerBound..<to.upperBound])
    }

    private func count(_ text: String, in code: String) -> Int {
        code.components(separatedBy: text).count - 1
    }

    /// What a redraw must not do: load the list or the page again, move
    /// either, touch the selection or ask for anything.
    private let neverInARedraw = ["reloadData", "reloadRows", "reconfigureRows", "reloadSections",
                                  "performBatchUpdates", "beginUpdates", "selectRow", "deselectRow",
                                  "setContentOffset", "contentOffset", "scrollToRow", "setEditing",
                                  "configure(with", "repository", "fetch", "load(", "loadBody",
                                  "renderConversation", "drawAgain", "Task"]

    /// The list hears both words, the formatters let go and the day turned
    /// over, and writes the date of each row in sight again where it is,
    /// and what VoiceOver reads of it, and the line under the list its age;
    /// nothing else. By the list's one writer of a row's cell since B-143
    /// (`draw(_:at:_:)`), with the date and the words alone
    /// (`RowParts.datesChanged`), which draws the date and nothing else of
    /// the row's lines.
    func testTheRowsInSightWriteTheirDatesAgainWhereTheyAre() throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains(
            "for name in [DisplayDates.didChange, UIApplication.significantTimeChangeNotification] { "
            + "NotificationCenter.default.addObserver(self, selector: #selector(datesChanged), "
            + "name: name, object: nil) }"))
        let redraw = try part(of: list, from: "@objc private func datesChanged() {",
                              through: "draw(cell, at: ip, parts) } }")
        XCTAssertTrue(redraw.hasPrefix(
            "@objc private func datesChanged() { drawRowsInSight(.datesChanged) showAge() } "
            + "private func draw(_ cell: MessageCell, at ip: IndexPath, _ parts: RowParts) { "
            + "guard ip.row < rows.count else { return } switch rows[ip.row] { case let .thread(thread): "
            + "if parts.contains(.lines) { cell.configure(with: thread.displayRow(in: mailbox, mine: mine), "
            + "marked: thread.marksConversation(in: mailbox)) } "
            + "else if parts.contains(.date) { cell.drawDate() } "), redraw)
        XCTAssertTrue(redraw.contains(
            "if parts.contains(.label) { "
            + "cell.accessibilityLabel = thread.accessibilityLabel(in: mailbox, mine: mine) } } } "))
        XCTAssertTrue(redraw.hasSuffix(
            "private func drawRowsInSight(_ parts: RowParts) { "
            + "for ip in tableView.indexPathsForVisibleRows ?? [] { "
            + "guard let cell = tableView.cellForRow(at: ip) as? MessageCell else { continue } "
            + "draw(cell, at: ip, parts) } }"), redraw)
        XCTAssertEqual(RowParts.datesChanged, [.date, .label], "the date and the words, not the lines")
        // The lines are drawn by `configure` alone, behind `.lines`, which
        // the dates' redraw does not name.
        for never in neverInARedraw where never != "configure(with" {
            XCTAssertFalse(redraw.contains(never), never)
        }
        XCTAssertEqual(count("configure(with", in: redraw), 1)

        // The row's date has one writer, from the row's own date, as the
        // row is drawn and again.
        let cell = try source("UI/MessageCell.swift")
        XCTAssertTrue(cell.contains("senderLabel.text = m.sender date = m.date drawDate() "))
        XCTAssertTrue(cell.contains("func drawDate() { guard let date else { return } "
                                    + "timestampLabel.text = MailFormat.listTimestamp(date) setNeedsLayout() }"))
        XCTAssertEqual(count("timestampLabel.text =", in: cell), 1)
    }

    /// A row coming into sight has its date written again as it comes:
    /// the cell the table prepared ahead for the row past the edge, before
    /// the change, is not among the rows in sight the redraw names, and is
    /// shown without being drawn again. Drawn whole since B-143, its date
    /// with the rest, by the redraw's writer.
    func testARowComingIntoSightWritesItsDateAgain() throws {
        let list = try source("UI/MessageListViewController.swift")
        let coming = try part(of: list,
                              from: "override func tableView(_ t: UITableView, willDisplay cell: UITableViewCell, "
                                  + "forRowAt ip: IndexPath) {",
                              through: "loadNextPage() }")
        XCTAssertTrue(coming.hasPrefix(
            "override func tableView(_ t: UITableView, willDisplay cell: UITableViewCell, "
            + "forRowAt ip: IndexPath) { "
            + "if let cell = cell as? MessageCell { draw(cell, at: ip, .comingIntoSight) } "),
            "first, before the pages are asked for")
        XCTAssertTrue(RowParts.comingIntoSight.isSuperset(of: RowParts.datesChanged))
        XCTAssertEqual(count("private func draw(_ cell: MessageCell,", in: list), 1)
        XCTAssertEqual(count("cell.drawDate()", in: list), 1)
        XCTAssertEqual(count("tableView(_ t: UITableView, willDisplay cell:", in: list), 1)
    }

    /// The reading pane hears both words too, and writes the header's date
    /// again, and the stack's lines by script, or once the stack has loaded;
    /// nothing is fetched or drawn again.
    func testThePaneWritesTheHeadersDateAndTheStacksAgain() throws {
        let pane = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(pane.contains(
            "for name in [DisplayDates.didChange, UIApplication.significantTimeChangeNotification] { "
            + "NotificationCenter.default.addObserver(self, selector: #selector(datesChanged), "
            + "name: name, object: nil) }"))
        let redraw = try part(of: pane, from: "@objc private func datesChanged() {",
                              through: "in: nil, in: .defaultClient) }")
        XCTAssertEqual(redraw,
            "@objc private func datesChanged() { header.drawDate() "
            + "if let dates = document.dates() { run(dates) } } "
            + "private func run(_ dates: ConversationDocument.Dates) { "
            + "webView.callAsyncJavaScript(ConversationDocument.Dates.script, arguments: dates.arguments, "
            + "in: nil, in: .defaultClient) }")
        for never in neverInARedraw { XCTAssertFalse(redraw.contains(never), never) }
        XCTAssertTrue(pane.contains("for insert in finished.inserts { run(insert) } "
                                    + "for fill in finished.fills { run(fill) } "
                                    + "if let dates = finished.dates { run(dates) } }"),
                      "a stack that loaded after the change, last")

        // The header's date has one writer, from the letter's own date, as
        // the letter is shown and again, and VoiceOver's words with it.
        let header = try source("UI/MessageHeaderView.swift")
        XCTAssertTrue(header.contains("date = m.date spoken = \"From \\(MailFormat.displayName(m.sender)), "
                                      + "\\(m.subject)\" drawDate() "))
        XCTAssertTrue(header.contains("func drawDate() { guard let date else { return } "
                                      + "let when = MailFormat.detailTimestamp(date) dateLabel.text = when "
                                      + "accessibilityLabel = \"\\(spoken), \\(when)\" }"))
        XCTAssertEqual(count("dateLabel.text =", in: header), 1)
        XCTAssertEqual(count("accessibilityLabel =", in: header), 2, "the header's and a file's row")
    }
}

/// What was heard of `didChange`, from whichever thread.
private final class SaidChanges: @unchecked Sendable {
    struct Word: Equatable {
        let main: Bool
        let builtAfresh: Bool
        let words: String
    }

    private let lock = NSLock()
    private var found: [Word] = []

    var all: [Word] {
        lock.lock()
        defer { lock.unlock() }
        return found
    }

    func add(_ word: Word) {
        lock.lock()
        found.append(word)
        lock.unlock()
    }
}
