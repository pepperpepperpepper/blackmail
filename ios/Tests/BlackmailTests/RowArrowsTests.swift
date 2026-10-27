import XCTest
@testable import Blackmail

/// Mail's grey reply and forward arrows on the rows (B-102), from the flags
/// Gmail sends with every row already: `\Answered` and `$Forwarded`. Read
/// off the FETCH, carried on the row and kept with it on the iPad, drawn in
/// the gutter where the unread dot goes and read by VoiceOver where it reads
/// "Unread". Nothing is written to Gmail.
///
/// The cell is UIKit, which never builds on this host, so its wiring is read
/// from the source, as `SteadyChromeTests` reads it: comment lines out, and
/// runs of white space as one space.
final class RowArrowsTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    // MARK: - The flags on the wire

    private func fetched(_ flags: String) -> IMAPFetchResult? {
        IMAPParser.parseFetch([IMAPResponseLine(text: "* 1 FETCH (UID 4 FLAGS (\(flags)))",
                                                literals: [])]).first
    }

    /// `\Answered` and `$Forwarded` together, as Gmail sends a letter both
    /// answered and forwarded: both read.
    func testAnsweredAndForwardedAreReadOffTheFlags() throws {
        let both = try XCTUnwrap(fetched(#"\Seen \Answered $Forwarded"#))
        XCTAssertTrue(both.isAnswered)
        XCTAssertTrue(both.isForwarded)
        XCTAssertTrue(both.isSeen)
        XCTAssertFalse(both.isFlagged)
    }

    /// Any case, and the keyword without its dollar, which iOS's Mail knows
    /// too.
    func testEitherSpellingAndAnyCaseCount() throws {
        XCTAssertEqual(fetched(#"\ANSWERED"#)?.isAnswered, true)
        XCTAssertEqual(fetched(#"\answered"#)?.isAnswered, true)
        XCTAssertEqual(fetched("Forwarded")?.isForwarded, true)
        XCTAssertEqual(fetched("$forwarded")?.isForwarded, true)
        XCTAssertEqual(fetched("$FORWARDED")?.isForwarded, true)
        XCTAssertEqual(fetched("$Forwarded")?.isAnswered, false, "forwarded is not answered")
        XCTAssertEqual(fetched(#"\Answered"#)?.isForwarded, false, "answered is not forwarded")
    }

    /// No flags, other flags, and words that only contain the marks: none.
    func testOtherFlagsAreNeither() throws {
        for flags in ["", #"\Seen \Flagged"#, #"\Draft $NotPhishing"#, "$ForwardedTo NotForwarded",
                      #"\Answer $Forward"#, #"\Forwarded"#] {
            let r = try XCTUnwrap(fetched(flags), flags)
            XCTAssertFalse(r.isAnswered, flags)
            XCTAssertFalse(r.isForwarded, flags)
        }
    }

    // MARK: - What a row shows

    private static let inbox = Mailbox(id: "INBOX", name: "Inbox", unreadCount: 0, role: .inbox)
    private static let mine = OwnAddresses(["owner@example.com"])
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)
    private static let stamp = MailFormat.listTimestamp(now, now: now)

    private func letter(_ id: String, from sender: String = "Carlo <carlo@example.org>",
                        hoursAgo: Double = 0, read: Bool = true,
                        answered: Bool = false, forwarded: Bool = false) -> MessageSummary {
        MessageSummary(id: id, mailboxID: "INBOX", sender: sender, subject: "Lunch on Sunday",
                       preview: "", date: Self.now.addingTimeInterval(-hoursAgo * 3_600),
                       isRead: read, isFlagged: false, isAnswered: answered,
                       isForwarded: forwarded, threadID: "t")
    }

    private func label(_ thread: MessageThread) -> String {
        thread.accessibilityLabel(in: Self.inbox, mine: Self.mine, now: Self.now)
    }

    /// The arrow for a read letter: the reply arrow for one answered, the
    /// forward arrow for one forwarded, the reply arrow for one both, and
    /// none for one neither. The symbols are Mail's, filled.
    func testTheArrowForEachMark() {
        XCTAssertEqual(RowArrow(read: true, answered: true, forwarded: false), .replied)
        XCTAssertEqual(RowArrow(read: true, answered: false, forwarded: true), .forwarded)
        XCTAssertEqual(RowArrow(read: true, answered: true, forwarded: true), .replied)
        XCTAssertNil(RowArrow(read: true, answered: false, forwarded: false))
        XCTAssertEqual(RowArrow.replied.symbolName, "arrowshape.turn.up.left.fill")
        XCTAssertEqual(RowArrow.forwarded.symbolName, "arrowshape.turn.up.right.fill")
        XCTAssertEqual(RowArrow.replied.spoken, "Replied")
        XCTAssertEqual(RowArrow.forwarded.spoken, "Forwarded")
    }

    /// An unread letter shows its dot, never an arrow, whatever its marks:
    /// the dot has the gutter. Read, its arrow shows.
    func testTheDotWinsTheGutter() {
        for (answered, forwarded) in [(true, false), (false, true), (true, true)] {
            XCTAssertNil(RowArrow(read: false, answered: answered, forwarded: forwarded))
            XCTAssertNil(letter("1/9", read: false, answered: answered, forwarded: forwarded).arrow)
            XCTAssertNotNil(letter("1/9", answered: answered, forwarded: forwarded).arrow)
        }
    }

    /// A conversation's row shows its newest letter's mark, the letter whose
    /// date and preview it shows: answered or forwarded, its arrow; an older
    /// letter's mark alone, none. The row the list draws carries the same
    /// marks, so the cell's arrow is the conversation's.
    func testAConversationShowsItsNewestLettersMark() {
        let answered = MessageThread.group([
            letter("1/9", answered: true),
            letter("1/8", hoursAgo: 1),
        ])[0]
        XCTAssertEqual(answered.arrow, .replied)
        XCTAssertEqual(answered.displayRow(in: Self.inbox, mine: Self.mine).arrow, .replied)

        let forwarded = MessageThread.group([
            letter("1/9", forwarded: true),
            letter("1/8", hoursAgo: 1, answered: true),
        ])[0]
        XCTAssertEqual(forwarded.arrow, .forwarded)
        let row = forwarded.displayRow(in: Self.inbox, mine: Self.mine)
        XCTAssertEqual([row.isAnswered, row.isForwarded], [false, true])
        XCTAssertEqual(row.arrow, .forwarded)

        let older = MessageThread.group([
            letter("1/9"),
            letter("1/8", hoursAgo: 1, answered: true, forwarded: true),
        ])[0]
        XCTAssertNil(older.arrow)
        let plain = older.displayRow(in: Self.inbox, mine: Self.mine)
        XCTAssertEqual([plain.isAnswered, plain.isForwarded], [false, false])
        XCTAssertNil(plain.arrow)
    }

    /// The newest is the last that came, not the first listed (B-084): the
    /// letter that came last, listed below another, gives the row its mark.
    func testTheNewestIsTheLastToCome() {
        var first = letter("1/9", hoursAgo: 1)
        var reply = letter("1/8", answered: true)
        first.arrived = Self.now.addingTimeInterval(-3_600)
        reply.arrived = Self.now
        let row = MessageThread.group([first, reply])[0]
        XCTAssertEqual(row.newest.id, "1/8")
        XCTAssertEqual(row.arrow, .replied)
        XCTAssertEqual(row.displayRow().arrow, .replied)
    }

    /// A conversation with any letter unread shows the dot, its newest
    /// letter answered or not: no arrow.
    func testAnUnreadLetterAnywhereKeepsTheDot() {
        let row = MessageThread.group([
            letter("1/9", answered: true),
            letter("1/8", hoursAgo: 1, read: false),
        ])[0]
        XCTAssertFalse(row.isRead)
        XCTAssertNil(row.arrow)
        XCTAssertNil(row.displayRow().arrow)
    }

    /// VoiceOver reads "Replied" or "Forwarded" where the row shows the
    /// arrow, in the place it reads "Unread" for the dot, and neither where
    /// it shows none: an unread answered letter reads "Unread" alone, and
    /// so does a conversation whose newest letter is answered and whose
    /// older one is unread.
    func testVoiceOverReadsTheArrowOnlyWhereItShows() {
        let one = { (read: Bool, answered: Bool, forwarded: Bool) in
            MessageThread(messages: [self.letter("1/9", read: read, answered: answered,
                                                 forwarded: forwarded)])
        }
        XCTAssertEqual(label(one(true, true, false)),
                       "Replied, Carlo, Lunch on Sunday, \(Self.stamp)")
        XCTAssertEqual(label(one(true, false, true)),
                       "Forwarded, Carlo, Lunch on Sunday, \(Self.stamp)")
        XCTAssertEqual(label(one(true, true, true)),
                       "Replied, Carlo, Lunch on Sunday, \(Self.stamp)")
        XCTAssertEqual(label(one(true, false, false)), "Carlo, Lunch on Sunday, \(Self.stamp)")
        XCTAssertEqual(label(one(false, true, true)),
                       "Unread, Carlo, Lunch on Sunday, \(Self.stamp)")

        let conversation = MessageThread.group([
            letter("1/9", answered: true),
            letter("1/8", from: "Margaret <m@example.org>", hoursAgo: 1),
        ])[0]
        XCTAssertEqual(label(conversation),
                       "Replied, Carlo, Margaret, 2 messages, Lunch on Sunday, \(Self.stamp)")
        let olderOnly = MessageThread.group([
            letter("1/9"),
            letter("1/8", from: "Margaret <m@example.org>", hoursAgo: 1, forwarded: true),
        ])[0]
        XCTAssertEqual(label(olderOnly), "Carlo, Margaret, 2 messages, Lunch on Sunday, \(Self.stamp)")
        // The newest letter read and answered, an older one unread: the row
        // shows the dot, so VoiceOver reads "Unread" and no "Replied", the
        // conversation's arrow and not the newest letter's own.
        let unreadOlder = MessageThread.group([
            letter("1/9", answered: true),
            letter("1/8", from: "Margaret <m@example.org>", hoursAgo: 1, read: false),
        ])[0]
        XCTAssertEqual(label(unreadOlder),
                       "Unread, Carlo, Margaret, 2 messages, Lunch on Sunday, \(Self.stamp)")
    }

    // MARK: - Kept on the iPad

    private var base: URL!
    private var kept: URL { base.appendingPathComponent("Kept", isDirectory: true) }

    override func setUp() {
        super.setUp()
        base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("RowArrowsTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let base {
            MailShelf.wipe(root: kept)
            try? FileManager.default.removeItem(at: base)
        }
        base = nil
        super.tearDown()
    }

    private func shelf() -> MailShelf {
        MailShelf(root: kept, address: "owner@example.com", host: "imap.gmail.com")
    }

    /// Six read letters, each its own conversation, listed from `folder`:
    /// none, answered, forwarded, both, none, none. The same six letters,
    /// by their Gmail ids, from any folder.
    private func keptRows(in folder: String = "INBOX", firstUID: Int = 900) -> [MessageSummary] {
        (0..<6).map { (i: Int) -> MessageSummary in
            let answered: Bool = i == 1 || i == 3
            let forwarded: Bool = i == 2 || i == 3
            let date: Date = Self.now.addingTimeInterval(Double(-i) * 3_600)
            let message: UInt64 = 1_800_000_000_000_000_000 + UInt64(i)
            return MessageSummary(id: "1/\(firstUID - i)", mailboxID: folder,
                                  sender: "Carlo <carlo@example.org>", subject: "Letter \(i)",
                                  preview: "", date: date, isRead: true, isFlagged: false,
                                  isAnswered: answered, isForwarded: forwarded,
                                  threadID: "t\(i)", gmailMessageID: message)
        }
    }

    /// The file a page is kept in, found by what it says it is.
    private func pageFile(of folder: String, under directory: URL) throws -> URL {
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path)
        where name.hasPrefix("page-") {
            let url = directory.appendingPathComponent(name)
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            if (object as? [String: Any])?["folder"] as? String == folder { return url }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    /// The marks are kept with the rows and read back, so a launch draws
    /// the arrows before the server is heard from. Written only for a row
    /// with the mark; a page kept before the rows carried them reads, every
    /// row with none: no new format.
    func testTheMarksAreKeptAndAPageKeptWithoutThemStillReads() throws {
        let rows = keptRows()
        let writing = shelf()
        writing.took(page: rows, of: "INBOX", validity: 1)
        writing.flush()
        let read = try XCTUnwrap(shelf().page(of: "inbox")).rows
        XCTAssertEqual(read.map(\.isAnswered), rows.map(\.isAnswered))
        XCTAssertEqual(read.map(\.isForwarded), rows.map(\.isForwarded))
        XCTAssertEqual(read.map(\.arrow), [nil, .replied, .forwarded, .replied, nil, nil])

        let file = try pageFile(of: "INBOX", under: writing.directory)
        var page = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file))
                                    as? [String: Any])
        var records = try XCTUnwrap(page["rows"] as? [[String: Any]])
        XCTAssertEqual(records.filter { $0["answered"] != nil }.count, 2, "only the rows answered")
        XCTAssertEqual(records.filter { $0["forwarded"] != nil }.count, 2, "only the rows forwarded")
        for i in records.indices {
            records[i]["answered"] = nil
            records[i]["forwarded"] = nil
        }
        page["rows"] = records
        try JSONSerialization.data(withJSONObject: page).write(to: file)

        let older = try XCTUnwrap(shelf().page(of: "inbox")).rows
        XCTAssertEqual(older.map(\.id), rows.map(\.id))
        XCTAssertEqual(older.map(\.isAnswered), Array(repeating: false, count: 6))
        XCTAssertEqual(older.map(\.isForwarded), Array(repeating: false, count: 6))
    }

    /// The server has a letter as answered, or forwarded: every kept row of
    /// the letter has it, by its Gmail id, in the Inbox and All Mail alike,
    /// and no other row. Found by the id the write names where the folder
    /// has no kept row under it. Taken off again, it is written as nothing.
    func testAMarkGoesOnEveryKeptRowOfTheLetter() throws {
        let shelf = shelf()
        let inbox = keptRows()
        let allMail = keptRows(in: "[Gmail]/All Mail", firstUID: 5_900)
        shelf.took(page: inbox, of: "INBOX", validity: 1)
        shelf.took(page: allMail, of: "[Gmail]/All Mail", validity: 2)
        func rows(_ folder: String) throws -> [MessageSummary] {
            try XCTUnwrap(shelf.page(of: folder)).rows
        }

        shelf.answered(true, id: inbox[0].id, letter: inbox[0].gmailMessageID, in: "INBOX")
        XCTAssertEqual(try rows("inbox").map(\.isAnswered), [true, true, false, true, false, false])
        XCTAssertEqual(try rows("[Gmail]/All Mail").map(\.isAnswered),
                       [true, true, false, true, false, false])
        XCTAssertEqual(try rows("inbox").map(\.isForwarded), inbox.map(\.isForwarded))

        // From All Mail, by a row the Inbox does not keep under that id.
        shelf.forwarded(true, id: allMail[4].id, letter: allMail[4].gmailMessageID,
                        in: "[Gmail]/All Mail")
        XCTAssertEqual(try rows("inbox").map(\.isForwarded), [false, false, true, true, true, false])
        XCTAssertEqual(try rows("[Gmail]/All Mail").map(\.isForwarded),
                       [false, false, true, true, true, false])

        // Named by the letter alone, from a folder with no kept page.
        shelf.answered(true, id: "9/1", letter: inbox[5].gmailMessageID, in: "[Gmail]/Important")
        XCTAssertEqual(try rows("inbox")[5].isAnswered, true)
        XCTAssertEqual(try rows("[Gmail]/All Mail")[5].isAnswered, true)

        shelf.answered(false, id: inbox[1].id, letter: inbox[1].gmailMessageID, in: "INBOX")
        XCTAssertEqual(try rows("inbox").map(\.isAnswered), [true, false, false, true, false, true])
        XCTAssertEqual(try rows("inbox").map(\.arrow), [.replied, nil, .forwarded, .replied, .forwarded,
                                                         .replied])
        shelf.flush()
        let file = try pageFile(of: "INBOX", under: shelf.directory)
        let page = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file))
                                    as? [String: Any])
        let records = try XCTUnwrap(page["rows"] as? [[String: Any]])
        XCTAssertNil(records[1]["answered"], "taken off, written as nothing")
        XCTAssertEqual(records[0]["answered"] as? Bool, true)
        let relaunched = try XCTUnwrap(self.shelf().page(of: "inbox")).rows
        XCTAssertEqual(relaunched.map(\.arrow), [.replied, nil, .forwarded, .replied, .forwarded,
                                                 .replied])
    }

    // MARK: - From the server to the row

    /// Over the shipping repository and client: letters Gmail has as
    /// answered, forwarded, both, and answered but unread, listed from the
    /// Inbox as every listing is, with nothing more asked. Each row carries
    /// its marks, the shelf keeps them, and a launch reads them back.
    func testAListingCarriesTheMarksAndTheShelfKeepsThem() async throws {
        let server = ScriptedIMAPServer()
        defer { XCTAssertEqual(server.violations, []) }
        let suite = "RowArrowsTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        func repository(_ shelf: MailShelf) -> IMAPMailRepository {
            IMAPMailRepository(account: server.account, password: server.password,
                               transport: server.transportFactory,
                               recipients: RecipientBook(defaults: defaults), shelf: shelf)
        }
        let marks: [(String, Set<String>)] = [
            ("answered", ["\\Seen", "\\Answered"]),
            ("forwarded", ["\\Seen", "$Forwarded"]),
            ("both", ["\\Seen", "\\Answered", "Forwarded"]),
            ("unread", ["\\Answered"]),
        ]
        var uids: [String: UInt32] = [:]
        for (i, (name, flags)) in marks.enumerated() {
            let delivered = server.deliver(
                Server.Letter(from: Server.carlo, to: [Server.owner], subject: "B-102 \(name)",
                              date: Server.newestDate.addingTimeInterval(Double(i + 1) * 60),
                              text: "Hello.\r\n", flags: flags,
                              messageID: "<b102-\(name)@example.org>"),
                to: [Server.inbox, Server.allMail])
            uids[name] = try XCTUnwrap(delivered[Server.inbox])
        }
        let shelf = MailShelf(root: kept, address: server.username, host: server.account.imapHost)
        let repo = repository(shelf)
        _ = try await repo.listMailboxes()
        let listed = try await repo.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        func row(_ name: String, in rows: [MessageSummary]) throws -> MessageSummary {
            let uid = try XCTUnwrap(uids[name])
            return try XCTUnwrap(rows.first { $0.id.hasSuffix("/\(uid)") }, name)
        }
        XCTAssertEqual(try row("answered", in: listed).arrow, .replied)
        XCTAssertEqual(try row("forwarded", in: listed).arrow, .forwarded)
        let both = try row("both", in: listed)
        XCTAssertEqual([both.isAnswered, both.isForwarded], [true, true])
        XCTAssertEqual(both.arrow, .replied)
        XCTAssertEqual(try row("unread", in: listed).isAnswered, true)
        XCTAssertNil(try row("unread", in: listed).arrow, "unread: the dot")
        // The seeded letters carry neither mark.
        XCTAssertEqual(listed.filter(\.isAnswered).count, 3)
        XCTAssertEqual(listed.filter(\.isForwarded).count, 2)
        // Nothing was written: the listing's own commands, and no STORE.
        XCTAssertFalse(server.log.contains { $0.verb.contains("STORE") })

        shelf.flush()
        let relaunched = try XCTUnwrap(MailShelf(root: kept, address: server.username,
                                                 host: server.account.imapHost).page(of: "inbox")).rows
        XCTAssertEqual(try row("answered", in: relaunched).arrow, .replied)
        XCTAssertEqual(try row("forwarded", in: relaunched).arrow, .forwarded)
        XCTAssertEqual(try row("both", in: relaunched).arrow, .replied)
        XCTAssertEqual(try row("unread", in: relaunched).isAnswered, true)
        XCTAssertEqual(relaunched.filter(\.isAnswered).count, 3)
        XCTAssertEqual(relaunched.filter(\.isForwarded).count, 2)
    }

    // MARK: - The cell

    /// `path` is under `Sources/Blackmail`.
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

    private func place(of text: String, in code: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String.Index? {
        let found = code.range(of: text)?.lowerBound
        XCTAssertNotNil(found, text, file: file, line: line)
        return found
    }

    /// The arrow is grey, the secondary text's grey, Mail's two filled
    /// symbols each made once at a size of their own (B-071), scaled to fit
    /// a square as wide as the unread dot, centred where the dot is.
    func testTheArrowIsGreyFixedAndWhereTheDotIs() throws {
        let cell = try source("UI/MessageCell.swift")
        XCTAssertNotNil(place(of: "private let repliedArrow = UIImage(systemName: RowArrow.replied.symbolName, "
                                  + "withConfiguration: Theme.rowArrowSymbol)", in: cell))
        XCTAssertNotNil(place(of: "private let forwardedArrow = UIImage(systemName: "
                                  + "RowArrow.forwarded.symbolName, withConfiguration: Theme.rowArrowSymbol)",
                              in: cell))
        XCTAssertNotNil(place(of: "statusIcon.tintColor = Theme.secondaryText", in: cell))
        XCTAssertNotNil(place(of: "statusIcon.contentMode = .scaleAspectFit", in: cell))
        XCTAssertNotNil(place(of: "let size = Theme.rowArrowBox statusIcon.frame = CGRect( "
                                  + "x: gutterX - size / 2, y: (Theme.unreadDotCenterY * Theme.textScale) "
                                  + "- size / 2, width: size, height: size)", in: cell))
        let theme = try source("Theme/Theme.swift")
        XCTAssertNotNil(place(of: "static var rowArrowBox: CGFloat { RowLines.gutterBox(12, at: textSize, "
                                  + "centre: unreadDotCenterX, textLeft: messageTextLeft) }", in: theme))
        XCTAssertEqual(RowLines.gutterBox(12, at: .factory, centre: 14, textLeft: 29), 12,
                       "12 at Large, the dot's width")
        XCTAssertNotNil(place(of: "static let unreadDotDiameter: CGFloat = 12", in: theme),
                        "the arrow as wide as the dot")
        XCTAssertNotNil(place(of: "static var rowArrowSymbol: UIImage.SymbolConfiguration { "
                                  + "UIImage.SymbolConfiguration(pointSize: rowArrowBox, weight: .regular) }",
                              in: theme))
    }

    /// The gutter holds one thing, in this order: the spinner over all,
    /// fading what is under it; the dot; the arrow, only on a row with no
    /// dot (`RowArrow`, tested above); the paperclip, only with neither,
    /// and otherwise at the end of the subject's line.
    func testTheGutterOrderIsSpinnerDotArrowClip() throws {
        let cell = try source("UI/MessageCell.swift")
        XCTAssertNotNil(place(of: "unreadDot.isHidden = m.isRead let arrow = m.arrow "
                                  + "statusIcon.image = arrow == .forwarded ? forwardedArrow : repliedArrow "
                                  + "statusIcon.isHidden = arrow == nil", in: cell))
        XCTAssertNotNil(place(of: "let clipInGutter = attachmentIcon.isHidden == false && unreadDot.isHidden "
                                  + "&& statusIcon.isHidden", in: cell))
        XCTAssertNotNil(place(of: "unreadDot.alpha = isBusy ? 0 : 1 statusIcon.alpha = isBusy ? 0 : 1 "
                                  + "attachmentIcon.alpha = isBusy && clipInGutter ? 0 : 1", in: cell))
        // Under the spinner, which is put on last.
        XCTAssertNotNil(place(of: "for v in [unreadDot, statusIcon, senderLabel, timestampLabel, "
                                  + "subjectLabel, previewLabel, attachmentIcon, flagIcon, conversationMark, "
                                  + "spinner] {", in: cell))
        // The arrow is set nowhere else.
        XCTAssertEqual(cell.components(separatedBy: "statusIcon.isHidden =").count - 1, 2,
                       "hidden at first, then by the row")
    }
}
