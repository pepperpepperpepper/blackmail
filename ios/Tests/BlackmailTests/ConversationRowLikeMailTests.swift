import XCTest
@testable import Blackmail

/// A conversation's row in every folder as Mail draws one (B-080). No count
/// after the names, in any folder: the row is marked with Mail's blue
/// circled chevron after its date, as B-075 marked Sent Mail's, Drafts' and
/// the Outbox's. The names are who wrote, as they always were, the newest
/// first, each once. A single letter has no mark. VoiceOver says how many
/// letters, in words. Only a list that gathers letters into conversations
/// has a row of more than one: a search's rows are never marked.
final class ConversationRowLikeMailTests: XCTestCase {

    private static let inbox = Mailbox(id: "INBOX", name: "Inbox", unreadCount: 0, role: .inbox)
    private static let allMail = Mailbox(id: "[Gmail]/All Mail", name: "All Mail",
                                         unreadCount: 0, role: .archive, depth: 1)
    /// Gmail's Important and Starred have no role: LIST gives them
    /// attributes RFC 6154 does not define.
    private static let important = Mailbox(id: "[Gmail]/Important", name: "Important",
                                           unreadCount: 0, depth: 1)
    private static let starred = Mailbox(id: "[Gmail]/Starred", name: "Starred",
                                         unreadCount: 0, depth: 1)
    private static let spam = Mailbox(id: "[Gmail]/Spam", name: "Spam",
                                      unreadCount: 0, role: .junk, depth: 1)
    private static let trash = Mailbox(id: "[Gmail]/Trash", name: "Trash",
                                       unreadCount: 0, role: .trash, depth: 1)
    private static let family = Mailbox(id: "Family", name: "Family", unreadCount: 0)
    private static let letters = Mailbox(id: "Family/Letters", name: "Letters",
                                         unreadCount: 0, depth: 1)
    private static let sent = Mailbox(id: "[Gmail]/Sent Mail", name: "Sent Mail",
                                      unreadCount: 0, role: .sent, depth: 1)
    private static let drafts = Mailbox(id: "[Gmail]/Drafts", name: "Drafts",
                                        unreadCount: 0, role: .drafts, depth: 1)
    private static let outbox = Outbox.mailbox(holding: 2)

    /// Every folder that lists who wrote.
    private static let incoming = [inbox, allMail, important, starred, spam, trash, family, letters]
    /// Every folder.
    private static let every = incoming + [sent, drafts, outbox]

    private static let mine = OwnAddresses(["owner.example@gmail.com"])
    private static let me = "Owner Example <owner.example@gmail.com>"
    private static let carlo = "Carlo <carlo@example.org>"
    private static let margaret = "Margaret Example <margaret@example.org>"
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func letter(_ id: String, in folder: Mailbox, from sender: String,
                        to: [String] = [ConversationRowLikeMailTests.me], hoursAgo: Double = 0,
                        read: Bool = true, flagged: Bool = false, attachment: Bool = false,
                        thread: String = "t") -> MessageSummary {
        MessageSummary(id: id, mailboxID: folder.id, sender: sender, subject: "Lunch on Sunday",
                       preview: "Shall we say one o'clock? \(id)",
                       date: Self.now.addingTimeInterval(-hoursAgo * 3_600),
                       isRead: read, isFlagged: flagged, hasAttachment: attachment,
                       threadID: thread, to: to)
    }

    /// Carlo, Margaret and Carlo again, newest first, listed from `folder`.
    private func conversation(in folder: Mailbox, read: Bool = true) -> MessageThread {
        MessageThread(messages: [
            letter("1/9", in: folder, from: Self.carlo, read: read),
            letter("1/8", in: folder, from: Self.margaret, hoursAgo: 1),
            letter("1/7", in: folder, from: Self.carlo, hoursAgo: 2),
        ])
    }

    // MARK: - The names and the mark

    /// In every folder that names who wrote, a conversation's row names
    /// them with no count after them, and is marked after its date. Its
    /// own letters' senders are left as they came.
    func testEveryFolderMarksAConversationWithNoCount() {
        for list in Self.incoming {
            let thread = conversation(in: list)
            let shown = thread.displayRow(in: list, mine: Self.mine).sender
            XCTAssertEqual(shown, "Carlo, Margaret Example", list.name)
            XCTAssertFalse(shown.contains("("), list.name)
            XCTAssertFalse(shown.contains("3"), list.name)
            XCTAssertTrue(thread.marksConversation(in: list), list.name)
            XCTAssertEqual(thread.messages.map(\.sender), [Self.carlo, Self.margaret, Self.carlo])
        }
        for list in [Self.sent, Self.drafts, Self.outbox] {
            let thread = MessageThread(messages: [
                letter("1/9", in: list, from: Self.me, to: [Self.carlo]),
                letter("1/8", in: list, from: Self.me, to: [Self.margaret], hoursAgo: 1),
            ])
            XCTAssertEqual(thread.displayRow(in: list, mine: Self.mine).sender, "Carlo & Margaret",
                           list.name)
            XCTAssertTrue(thread.marksConversation(in: list), list.name)
        }
    }

    /// The names are as they were: who wrote, the newest first, each once,
    /// joined by commas, as the row with no folder has always drawn them.
    /// Only the count went. His own letters in the Inbox name him.
    func testTheNamesAreWhoWroteAsBefore() {
        for list in Self.incoming {
            let thread = conversation(in: list)
            XCTAssertEqual(thread.displayRow(in: list, mine: Self.mine).sender,
                           thread.participants.joined(separator: ", "), list.name)
            XCTAssertEqual(thread.displayRow(in: list, mine: Self.mine), thread.displayRow(), list.name)

            let withHim = MessageThread(messages: [
                letter("1/6", in: list, from: Self.me, to: [Self.margaret]),
                letter("1/5", in: list, from: Self.margaret, hoursAgo: 1),
            ])
            XCTAssertEqual(withHim.displayRow(in: list, mine: Self.mine).sender,
                           "Owner Example, Margaret Example", list.name)
        }
    }

    /// A single letter has no mark and no count, in every folder, and is
    /// named as it always was.
    func testASingleLetterHasNoMark() {
        for list in Self.every {
            let single = MessageThread(messages: [letter("1/9", in: list, from: Self.carlo,
                                                         to: [Self.margaret])])
            XCTAssertFalse(single.marksConversation(in: list), list.name)
            let shown = single.displayRow(in: list, mine: Self.mine).sender
            XCTAssertFalse(shown.contains("("), list.name)
            XCTAssertEqual(shown, list.role == .sent || list.role == .drafts || list.role == .outbox
                           ? "Margaret Example" : "Carlo", list.name)
        }
    }

    /// A long list of who wrote is the names' alone: the line has no count
    /// in it to be cut off with them, and the mark is not text on it. The
    /// names keep their label's room and end before the date, and the date
    /// before the mark, at the right edge, in three panes and in two, in
    /// Edit mode too, as his iPad lays them out: a list 300 points wide or
    /// 375, its text from 29 to 15 from its right, 40 less in Edit, and
    /// the mark 18 wide. The date is "Yesterday", 68 points, the widest
    /// that fits before the mark in all four.
    func testALongListOfWhoWroteNeverReachesTheMark() {
        let many = (1...6).map { "Person\($0) Wolfeschlegelsteinhausen <p\($0)@example.com>" }
        let thread = MessageThread(messages: many.enumerated().map { i, who in
            letter("1/\(20 - i)", in: Self.inbox, from: who, hoursAgo: Double(i))
        })
        let shown = thread.displayRow(in: Self.inbox, mine: Self.mine).sender
        XCTAssertTrue(shown.hasPrefix("Person1 Wolfeschlegelsteinhausen, Person2"))
        XCTAssertTrue(shown.hasSuffix("Person6 Wolfeschlegelsteinhausen"))
        XCTAssertTrue(thread.marksConversation(in: Self.inbox))

        for (left, right) in [(CGFloat(29), CGFloat(285)), (29, 245), (29, 360), (29, 320)] {
            let plain = RowTopLine(left: left, right: right, mark: nil, gap: 5, date: 68)
            let marked = RowTopLine(left: left, right: right, mark: 18, gap: 5, date: 68)
            XCTAssertEqual(marked.namesWidth, plain.namesWidth, "\(right)")
            XCTAssertLessThan(marked.namesX + marked.namesWidth, marked.dateX, "\(right)")
            XCTAssertEqual(marked.dateX + marked.dateWidth + 5, marked.markX, "\(right)")
            XCTAssertEqual(marked.markX.map { $0 + 18 }, right, "\(right)")
        }
    }

    /// A marked row's date is never cut. "Wednesday", the widest date the
    /// list writes, is 80 points at 15, as UIKit measures it on iPadOS
    /// 18.6. In Edit mode in three panes the room before the mark is 74.2,
    /// so the date starts 5.8 sooner and the names end 5.8 sooner, the
    /// mark where it was, as Mail cuts the names and never the date. Where
    /// it fits, out of Edit and in two panes, nothing moves. A row without
    /// a mark is as it was, whatever its date. However long a date, the
    /// names never have less than nothing.
    func testAMarkedRowsDateIsNeverCut() {
        let wednesday: CGFloat = 80
        for right in [CGFloat(285), 245, 360, 320] {
            let marked = RowTopLine(left: 29, right: right, mark: 18, gap: 5, date: wednesday)
            XCTAssertGreaterThanOrEqual(marked.dateWidth, wednesday, "\(right)")
            XCTAssertEqual(marked.markX, right - 18, "\(right)")
            XCTAssertEqual(marked.dateX + marked.dateWidth + 5, right - 18, accuracy: 0.001,
                           "\(right)")
            XCTAssertEqual(marked.namesX, 29, "\(right)")
            XCTAssertEqual(marked.namesX + marked.namesWidth + 8, marked.dateX, accuracy: 0.001,
                           "\(right)")
            for date in [wednesday, 1_000] {
                XCTAssertEqual(RowTopLine(left: 29, right: right, mark: nil, gap: 5, date: date),
                               RowTopLine(left: 29, right: right, mark: nil, gap: 5), "\(right)")
            }
        }
        for right in [CGFloat(285), 360, 320] {
            XCTAssertEqual(RowTopLine(left: 29, right: right, mark: 18, gap: 5, date: wednesday),
                           RowTopLine(left: 29, right: right, mark: 18, gap: 5), "\(right)")
        }
        let edit = RowTopLine(left: 29, right: 245, mark: 18, gap: 5, date: wednesday)
        let before = RowTopLine(left: 29, right: 245, mark: 18, gap: 5)
        XCTAssertEqual(before.dateWidth, 74.2, accuracy: 0.001)
        XCTAssertEqual(edit.dateWidth, 80, accuracy: 0.001)
        XCTAssertEqual(edit.namesWidth, 105, accuracy: 0.001)
        XCTAssertEqual(before.namesWidth - edit.namesWidth, 5.8, accuracy: 0.001)

        let absurd = RowTopLine(left: 29, right: 245, mark: 18, gap: 5, date: 1_000)
        XCTAssertEqual(absurd.namesWidth, 0, accuracy: 0.001)
        XCTAssertEqual(absurd.namesX + absurd.namesWidth + 8, absurd.dateX, accuracy: 0.001)
        XCTAssertEqual(absurd.markX, 245 - 18)
    }

    /// The row is the conversation's newest letter in every field but the
    /// names: its subject, preview, date and id, and the conversation's
    /// unread dot, flag and paperclip, as before. Nothing else on it moves.
    func testOnlyTheNamesChangeOnTheRow() {
        let thread = MessageThread(messages: [
            letter("1/9", in: Self.inbox, from: Self.carlo),
            letter("1/8", in: Self.inbox, from: Self.margaret, hoursAgo: 1, read: false,
                   flagged: true, attachment: true),
        ])
        let row = thread.displayRow(in: Self.inbox, mine: Self.mine)
        let newest = thread.newest
        XCTAssertEqual([row.id, row.mailboxID, row.subject, row.preview, row.threadID ?? ""],
                       [newest.id, newest.mailboxID, newest.subject, newest.preview,
                        newest.threadID ?? ""])
        XCTAssertEqual(row.date, newest.date)
        XCTAssertEqual([row.isRead, row.isFlagged, row.hasAttachment], [false, true, true])
        XCTAssertEqual(row.sender, "Carlo, Margaret Example")
    }

    // MARK: - VoiceOver

    /// VoiceOver says how many letters a conversation holds, in words,
    /// after the names, in every folder; nothing for a single letter.
    func testVoiceOverSaysHowManyInEveryFolder() {
        let stamp = MailFormat.listTimestamp(Self.now, now: Self.now)
        for list in Self.incoming {
            XCTAssertEqual(conversation(in: list, read: false)
                            .accessibilityLabel(in: list, mine: Self.mine, now: Self.now),
                           "Unread, Carlo, Margaret Example, 3 messages, Lunch on Sunday, \(stamp)",
                           list.name)
            XCTAssertEqual(conversation(in: list).accessibilityLabel(in: list, mine: Self.mine,
                                                                     now: Self.now),
                           "Carlo, Margaret Example, 3 messages, Lunch on Sunday, \(stamp)",
                           list.name)
            let single = MessageThread(messages: [letter("1/9", in: list, from: Self.carlo)])
            XCTAssertEqual(single.accessibilityLabel(in: list, mine: Self.mine, now: Self.now),
                           "Carlo, Lunch on Sunday, \(stamp)", list.name)
        }
    }

    // MARK: - Lists that do not gather

    /// A search's rows are one letter each, in any folder, and so is every
    /// row with Organize by Thread off: no mark, no count, each named by
    /// its own sender.
    func testRowsNotGatheredHaveNoMark() {
        for list in Self.incoming {
            let letters = conversation(in: list).messages
            let rows = MessageThread.rows(for: letters, grouped: false)
            XCTAssertEqual(rows.count, 3, list.name)
            for row in rows {
                XCTAssertFalse(row.marksConversation(in: list), list.name)
            }
            XCTAssertEqual(rows.map { $0.displayRow(in: list, mine: Self.mine).sender },
                           ["Carlo", "Margaret Example", "Carlo"], list.name)
            XCTAssertTrue(MessageThread.rows(for: letters, grouped: true)[0].marksConversation(in: list))
        }
    }

    // MARK: - Read from the source

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

    /// The list and the cell are UIKit and never build on this host, so
    /// their wiring is read from their source. The list gathers a folder's
    /// letters, never a search's, so a search's rows are never marked. The
    /// cell shows or hides the mark by the row alone, with nothing of the
    /// folder in it, and nothing else hides it: not Edit mode, whose ticks
    /// narrow the row and leave the mark after the date. The names' label
    /// is one line, cut at its end, at its own size.
    func testTheCellMarksEveryFolderAlikeInEditToo() throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains(
            "grouped: !letters.isSearching && ConversationSettings.organizeByThread"))

        let cell = try source("UI/MessageCell.swift")
        XCTAssertEqual(cell.components(separatedBy: "conversationMark.isHidden =").count - 1, 2)
        XCTAssertTrue(cell.contains("conversationMark.isHidden = true"))
        XCTAssertTrue(cell.contains("conversationMark.isHidden = !marked"))
        for absent in ["setEditing", "isEditing", "role", "Mailbox", "conversationMark.alpha",
                       "conversationMark.removeFromSuperview", "senderLabel.numberOfLines",
                       "senderLabel.adjustsFontSizeToFitWidth", "senderLabel.lineBreakMode"] {
            XCTAssertFalse(cell.contains(absent), absent)
        }
    }

    /// Nothing in the app writes a count in brackets after a row's names
    /// any more: the one place that did, `MessageThread.displayRow`, has
    /// none, and no other file builds one from a conversation's count.
    func testNoRowWritesACountInBrackets() throws {
        let thread = try source("Mail/MessageThread.swift")
        for absent in ["(\\(count))", "(\\(messages.count))", "\"(\" +"] {
            XCTAssertFalse(thread.contains(absent), absent)
        }
        for path in ["UI/MessageListViewController.swift", "UI/MessageCell.swift",
                     "Mail/RowNames.swift", "Mail/Outbox.swift", "Mail/ListEdit.swift"] {
            let code = try source(path)
            for absent in ["(\\(t.count))", "(\\(thread.count))", "(\\(count))",
                           "(\\(messages.count))"] {
                XCTAssertFalse(code.contains(absent), "\(path): \(absent)")
            }
        }
    }
}
