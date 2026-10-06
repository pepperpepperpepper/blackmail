import XCTest
@testable import Blackmail

/// A row in Sent Mail, Drafts and the Outbox as Mail on the iPad draws one
/// (B-075). Its top line names the letter's To alone: one person whole, two
/// or more by short names joined "Jane & Sam", "Jane, Sam & Bob", his own
/// addresses left out but for the first, each person once, and "No
/// Recipients" with nobody in To. A conversation there has no count after
/// the names: the row is marked with Mail's blue circled chevron after its
/// date, which no length of names can push off the line. Every other list's
/// rows are as they were, their count on the names.
final class SentRowLikeMailTests: XCTestCase {

    private static let sent = Mailbox(id: "[Gmail]/Sent Mail", name: "Sent Mail",
                                      unreadCount: 0, role: .sent, depth: 1)
    private static let drafts = Mailbox(id: "[Gmail]/Drafts", name: "Drafts",
                                        unreadCount: 0, role: .drafts, depth: 1)
    private static let outbox = Outbox.mailbox(holding: 2)
    private static let inbox = Mailbox(id: "INBOX", name: "Inbox", unreadCount: 0, role: .inbox)
    private static let allMail = Mailbox(id: "[Gmail]/All Mail", name: "All Mail",
                                         unreadCount: 0, role: .archive, depth: 1)
    private static let trash = Mailbox(id: "[Gmail]/Trash", name: "Trash",
                                       unreadCount: 0, role: .trash, depth: 1)
    private static let spam = Mailbox(id: "[Gmail]/Spam", name: "Spam",
                                      unreadCount: 0, role: .junk, depth: 1)
    private static let family = Mailbox(id: "Family", name: "Family", unreadCount: 0)

    private static let mine = OwnAddresses(["owner.example@gmail.com"])
    private static let me = "Owner Example <owner.example@gmail.com>"
    private static let jane = "Jane Example <jane@example.com>"
    private static let sam = "Sam Example <sam@example.com>"
    private static let bob = "Bob Example <bob@example.org>"
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func line(_ to: [String]) -> String {
        RowNames.line(to: to, mine: Self.mine)
    }

    /// A letter of his, listed from `folder`.
    private func letter(_ id: String, in folder: Mailbox, to: [String]?, cc: [String] = [],
                        bcc: [String] = [], thread: String = "t", hoursAgo: Double = 0,
                        from sender: String = SentRowLikeMailTests.me) -> MessageSummary {
        MessageSummary(id: id, mailboxID: folder.id, sender: sender, subject: "Lunch on Sunday",
                       preview: "Shall we say one o'clock?",
                       date: Self.now.addingTimeInterval(-hoursAgo * 3_600),
                       isRead: true, isFlagged: false, threadID: thread,
                       to: to, cc: cc, bcc: bcc)
    }

    /// A conversation of two of his letters, listed from `folder`: the newer
    /// to Sam, Cc Jane, the older to Jane.
    private func conversation(in folder: Mailbox) -> MessageThread {
        MessageThread(messages: [
            letter("1/9", in: folder, to: [Self.sam], cc: [Self.jane]),
            letter("1/8", in: folder, to: [Self.jane], hoursAgo: 2),
        ])
    }

    // MARK: - The name line: nobody, and one

    /// Nobody in To: "No Recipients". A blank entry, an empty group as a
    /// letter sent to Bcc alone carries, and spaces name nobody.
    func testNobodyInToSaysNoRecipients() {
        XCTAssertEqual(line([]), "No Recipients")
        XCTAssertEqual(line([" ", ""]), "No Recipients")
        XCTAssertEqual(line(["undisclosed-recipients:;"]), "No Recipients")
        XCTAssertEqual(line(["Friends: ;"]), "No Recipients")
        XCTAssertEqual(line(["\n"]), RowNames.noRecipients)
    }

    /// One person: whole. The name the letter gives, a quoted one and one
    /// written surname first included; the address where there is none, or
    /// where the "name" is only the address again, in any case.
    func testOnePersonIsNamedWhole() {
        XCTAssertEqual(line([Self.jane]), "Jane Example")
        XCTAssertEqual(line(["\"Example, Jane\" <jane@example.com>"]), "Example, Jane")
        XCTAssertEqual(line(["Jane Q. Example <jane@example.com>"]), "Jane Q. Example")
        XCTAssertEqual(line(["sam@example.com"]), "sam@example.com")
        XCTAssertEqual(line(["<lee@example.com>"]), "lee@example.com")
        XCTAssertEqual(line(["\"JANE@example.com\" <jane@example.com>"]), "jane@example.com")
        XCTAssertEqual(line(["jane@example.com <jane@example.com>"]), "jane@example.com")
        XCTAssertEqual(line(["Sam <sam@example.com>"]), "Sam")
    }

    /// His own address, alone in To, is named, whole: a letter he sent
    /// himself names him.
    func testHisOwnAddressAloneIsNamed() {
        XCTAssertEqual(line([Self.me]), "Owner Example")
        XCTAssertEqual(line(["owner.example@gmail.com"]), "owner.example@gmail.com")
    }

    /// A half-typed address in a draft, with no "@", is named as he left
    /// it, alone or among others.
    func testAHalfTypedAddressIsNamedAsHeLeftIt() {
        XCTAssertEqual(line(["jan"]), "jan")
        XCTAssertEqual(line([Self.sam, "jan"]), "Sam & jan")
    }

    /// An address with a semicolon after it, as a draft's field keeps one
    /// typed so, and the last of a group's people, are named: only an
    /// entry with no address in it names nobody. Drafts and the Outbox
    /// read such a draft as Jane's, not "No Recipients".
    func testAnAddressBeforeASemicolonIsNamed() {
        XCTAssertEqual(line(["jane@example.com;"]), "jane@example.com")
        XCTAssertEqual(line(["Jane Example <jane@example.com>;"]), "Jane Example")
        XCTAssertEqual(line(["Friends: jane@example.com", "sam@example.com;"]), "jane & sam")
        XCTAssertEqual(line(["undisclosed-recipients:;", "sam@example.com;"]), "sam@example.com")
        var draft = Draft()
        draft.to = ["jane@example.com;"]
        XCTAssertEqual(Outbox.addressees(of: draft), "jane@example.com")
    }

    // MARK: - Two or more

    /// Two or more: each by a short name, joined as Mail joins them, "&"
    /// before the last and commas before that. However many there are, all
    /// are named, in the letter's order, with no "& 2 more": the line is
    /// cut at its end.
    func testTwoOrMoreAreJoinedAsMailJoinsThem() {
        XCTAssertEqual(line([Self.jane, Self.sam]), "Jane & Sam")
        XCTAssertEqual(line([Self.sam, Self.jane]), "Sam & Jane")
        XCTAssertEqual(line([Self.jane, Self.sam, Self.bob]), "Jane, Sam & Bob")
        XCTAssertEqual(line([Self.jane, Self.sam, Self.bob, "Lee Example <lee@example.com>"]),
                       "Jane, Sam, Bob & Lee")
        let six = (1...6).map { "Person\($0) Example <p\($0)@example.com>" }
        XCTAssertEqual(line(six), "Person1, Person2, Person3, Person4, Person5 & Person6")
        XCTAssertFalse(line(six).contains("more"))
    }

    /// A short name is the name's first word, the word after the comma of
    /// one written surname first, or the address before its "@" where there
    /// is no name. The rule for people Mail finds in no Contacts is
    /// inferred.
    func testEachOfSeveralIsNamedShort() {
        XCTAssertEqual(line(["\"Example, Jane\" <jane@example.com>", Self.sam]), "Jane & Sam")
        XCTAssertEqual(line(["Example, Jane <jane@example.com>", Self.sam]), "Jane & Sam")
        XCTAssertEqual(line(["Jane Q. Example <jane@example.com>", "John Smith, Jr. <js@example.com>"]),
                       "Jane & John")
        XCTAssertEqual(line(["jane@example.com", "sam.example@example.org"]), "jane & sam.example")
        XCTAssertEqual(line([Self.jane, "sam@example.com", "<lee@example.com>"]), "Jane, sam & lee")
        XCTAssertEqual(line(["\"Jane\" <jane@example.com>", "Sam <sam@example.com>"]), "Jane & Sam")
        XCTAssertEqual(RowNames.shortName(MailFormat.Recipient(name: "Example,", address: "x@example.com")),
                       "Example")
        XCTAssertEqual(RowNames.shortName(MailFormat.Recipient(name: nil, address: "@example.com")),
                       "@example.com")
    }

    /// A name broken over lines in the letter's header is one line, whole
    /// or short.
    func testANameBrokenOverLinesIsOneLine() {
        XCTAssertEqual(line(["Jane\u{2028}Example <jane@example.com>"]), "Jane Example")
        XCTAssertEqual(line(["Jane\u{2028}Example <jane@example.com>", Self.sam]), "Jane & Sam")
    }

    /// A name that is itself an address, other than the one it names, is
    /// shown with the real address after it, whole or among several, so it
    /// cannot pass for someone else.
    func testANameThatIsAnotherAddressShowsTheRealOne() {
        let posing = "\"jane@example.com\" <other@example.net>"
        XCTAssertEqual(line([posing]), "jane@example.com <other@example.net>")
        XCTAssertEqual(line([posing, Self.sam]), "jane@example.com <other@example.net> & Sam")
    }

    // MARK: - His own addresses, and each person once

    /// Among two or more, his own addresses are left out, except the first
    /// entry, which never is. One left is named whole.
    ///
    /// His addresses are Mail's: the ones he has, as written, in any letter
    /// case (`OwnAddresses`, B-076). Gmail's other spellings of his mailbox,
    /// a dot, a + tag, googlemail.com, are not his, and are named, as Mail
    /// names them. Until the merge with B-076 they were left out here, as
    /// Reply then left them out.
    func testHisOwnAddressesAreLeftOutButForTheFirst() {
        XCTAssertEqual(line([Self.jane, Self.me, Self.sam]), "Jane & Sam")
        XCTAssertEqual(line([Self.jane, "Owner.Example+lists@googlemail.com", Self.sam]),
                       "Jane, Owner.Example+lists & Sam")
        XCTAssertEqual(line([Self.jane, Self.me]), "Jane Example")
        XCTAssertEqual(line([Self.me, Self.jane]), "Owner & Jane")
        XCTAssertEqual(line([Self.me, Self.jane, "OWNER.EXAMPLE@GMAIL.COM"]), "Owner & Jane")
        XCTAssertEqual(line([Self.me, "ownerexample@gmail.com"]), "Owner & ownerexample")
    }

    /// Each person once: an address named again, in any case or with a
    /// name, and a name given again at another address, as one person
    /// written at two. One left is named whole, as the first naming has it.
    func testEachPersonIsNamedOnce() {
        XCTAssertEqual(line([Self.jane, "JANE@example.com"]), "Jane Example")
        XCTAssertEqual(line(["jane@example.com", Self.jane]), "jane@example.com")
        XCTAssertEqual(line([Self.jane, "Jane Example <jane@work.example>"]), "Jane Example")
        XCTAssertEqual(line([Self.jane, Self.sam, "jane@EXAMPLE.com", Self.sam]), "Jane & Sam")
        XCTAssertEqual(line(["sam@example.com", "sam@example.org"]), "sam & sam")
    }

    // MARK: - Rows

    /// The row names the To alone: not the Cc, not the Bcc, and not him.
    /// A letter sent to Cc or Bcc alone says "No Recipients".
    func testARowNamesItsToAlone() {
        let one = letter("1/9", in: Self.sent, to: [Self.jane], cc: [Self.sam], bcc: [Self.bob])
        XCTAssertEqual(MessageThread(messages: [one]).displayRow(in: Self.sent, mine: Self.mine).sender,
                       "Jane Example")
        for blind in [letter("1/8", in: Self.sent, to: [], bcc: [Self.bob]),
                      letter("1/7", in: Self.sent, to: [], cc: [Self.sam])] {
            XCTAssertEqual(MessageThread(messages: [blind]).displayRow(in: Self.sent, mine: Self.mine)
                            .sender, "No Recipients")
        }
    }

    /// A conversation names the To of every letter in it, the newest
    /// letter's first, each person once, him left out but for the first.
    func testAConversationNamesEveryLettersTo() {
        let thread = MessageThread(messages: [
            letter("1/9", in: Self.sent, to: [Self.sam], cc: [Self.bob]),
            letter("1/8", in: Self.sent, to: [Self.jane, Self.sam, Self.me], hoursAgo: 1),
            letter("1/7", in: Self.sent, to: [Self.me], hoursAgo: 2),
        ])
        XCTAssertEqual(thread.displayRow(in: Self.sent, mine: Self.mine).sender, "Sam & Jane")
        XCTAssertEqual(conversation(in: Self.sent).displayRow(in: Self.sent, mine: Self.mine).sender,
                       "Sam & Jane")
        let toHimself = MessageThread(messages: [
            letter("1/6", in: Self.sent, to: [Self.me]),
            letter("1/5", in: Self.sent, to: [Self.me], hoursAgo: 1),
        ])
        XCTAssertEqual(toHimself.displayRow(in: Self.sent, mine: Self.mine).sender, "Owner Example")
    }

    // MARK: - The mark and the count

    /// In Sent Mail, Drafts and the Outbox a conversation is marked after
    /// its date and has no count on its names; a single letter is neither.
    func testOutgoingMailboxesMarkAConversationInPlaceOfItsCount() {
        for list in [Self.sent, Self.drafts, Self.outbox] {
            let thread = conversation(in: list)
            XCTAssertTrue(thread.marksConversation(in: list), list.name)
            let shown = thread.displayRow(in: list, mine: Self.mine).sender
            XCTAssertEqual(shown, "Sam & Jane", list.name)
            XCTAssertFalse(shown.contains("("), list.name)

            let single = MessageThread(messages: [letter("1/9", in: list, to: [Self.jane])])
            XCTAssertFalse(single.marksConversation(in: list), list.name)
            XCTAssertEqual(single.displayRow(in: list, mine: Self.mine).sender, "Jane Example", list.name)
        }
    }

    /// Every other list keeps its count on the names, "(2)", and no mark:
    /// the Inbox, All Mail, Trash, Spam and a folder of his own, his own
    /// letters there included. Its rows are as they were before B-075, the
    /// row `displayRow()` has always drawn.
    func testEveryOtherListKeepsItsCountAndHasNoMark() {
        for list in [Self.inbox, Self.allMail, Self.trash, Self.spam, Self.family] {
            var thread = conversation(in: list)
            XCTAssertFalse(thread.marksConversation(in: list), list.name)
            XCTAssertEqual(thread.displayRow(in: list, mine: Self.mine).sender, "Owner Example (2)",
                           list.name)
            thread = MessageThread(messages: [
                letter("1/9", in: list, to: [Self.me], from: "Carlo <carlo@example.org>"),
                letter("1/8", in: list, to: [Self.me], hoursAgo: 1, from: "Margaret Example <m@example.org>"),
                letter("1/7", in: list, to: [Self.me], hoursAgo: 2, from: "Carlo <carlo@example.org>"),
            ])
            XCTAssertEqual(thread.displayRow(in: list, mine: Self.mine), thread.displayRow(), list.name)
            XCTAssertEqual(thread.displayRow(in: list, mine: Self.mine).sender, "Carlo, Margaret Example (3)",
                           list.name)
            XCTAssertFalse(thread.marksConversation(in: list), list.name)
        }
    }

    /// The folder a row was listed from decides it, as it decides the
    /// names: letters an All Mailboxes search found in All Mail, in Sent
    /// Mail's list, name him and keep their count, with no mark. A search,
    /// even of Sent Mail alone, is never gathered into conversations, so its
    /// rows have neither; nor with Organize by Thread off.
    func testOnlyAConversationOfTheFoldersOwnIsMarked() {
        let found = MessageThread(messages: [
            letter("2/90", in: Self.allMail, to: [Self.jane]),
            letter("2/89", in: Self.allMail, to: [Self.sam], hoursAgo: 1),
        ])
        XCTAssertFalse(found.marksConversation(in: Self.sent))
        XCTAssertEqual(found.displayRow(in: Self.sent, mine: Self.mine).sender, "Owner Example (2)")

        let letters = conversation(in: Self.sent).messages
        for row in MessageThread.rows(for: letters, grouped: false) {
            XCTAssertFalse(row.marksConversation(in: Self.sent))
            XCTAssertFalse(row.displayRow(in: Self.sent, mine: Self.mine).sender.contains("("))
        }
        XCTAssertEqual(MessageThread.rows(for: letters, grouped: false)
                        .map { $0.displayRow(in: Self.sent, mine: Self.mine).sender },
                       ["Sam Example", "Jane Example"])
        let grouped = MessageThread.rows(for: letters, grouped: true)
        XCTAssertEqual(grouped.count, 1)
        XCTAssertTrue(grouped[0].marksConversation(in: Self.sent))
    }

    /// VoiceOver still hears how many letters a marked conversation holds,
    /// in words, after the names the row shows.
    func testVoiceOverReadsHowManyAMarkedConversationHolds() {
        let stamp = MailFormat.listTimestamp(Self.now, now: Self.now)
        XCTAssertEqual(conversation(in: Self.sent).accessibilityLabel(in: Self.sent, mine: Self.mine,
                                                                       now: Self.now),
                       "Sam & Jane, 2 messages, Lunch on Sunday, \(stamp)")
        XCTAssertEqual(conversation(in: Self.inbox).accessibilityLabel(in: Self.inbox, mine: Self.mine,
                                                                        now: Self.now),
                       "Owner Example, 2 messages, Lunch on Sunday, \(stamp)")
    }

    // MARK: - The top line's geometry

    /// The mark changes the date's label and nothing else on the line: the
    /// names keep their left edge and width, the date keeps its left edge,
    /// and ends `gap` before the mark, which ends at the text's right edge.
    /// Without a mark the line is the frozen row's arithmetic: up to 110
    /// points for the date, 45% of a narrow line, 8 between it and the
    /// names. In three panes on his iPad and in two.
    func testTheMarkMovesNothingButTheDate() {
        for (left, right) in [(CGFloat(29), CGFloat(315)), (29, 360), (29, 250), (29, 200)] {
            let textWidth = right - left
            let stamp = min(110, textWidth * 0.45)
            let plain = RowTopLine(left: left, right: right, mark: nil, gap: 8.5)
            XCTAssertEqual(plain.namesX, left)
            XCTAssertEqual(plain.namesWidth, textWidth - stamp - 8)
            XCTAssertEqual(plain.dateX, right - stamp)
            XCTAssertEqual(plain.dateWidth, stamp)
            XCTAssertNil(plain.markX)

            let marked = RowTopLine(left: left, right: right, mark: 16, gap: 8.5)
            XCTAssertEqual(marked.namesX, plain.namesX)
            XCTAssertEqual(marked.namesWidth, plain.namesWidth)
            XCTAssertEqual(marked.dateX, plain.dateX)
            XCTAssertEqual(marked.markX, right - 16)
            XCTAssertEqual(marked.dateX + marked.dateWidth + 8.5, right - 16)
            XCTAssertLessThan(marked.namesX + marked.namesWidth, marked.dateX)
        }
    }

    // MARK: - The wiring

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
    /// their wiring is read from their source. The list draws every row, at
    /// first and when previews come, with its mark by `marksConversation
    /// (in:)`, and his addresses from the account. The cell draws the line
    /// the row gives, unread again as a sender; shows Mail's chevron, blue,
    /// only on a marked row, a picture with no tap of its own; and lays the
    /// line out by `RowTopLine`. A tap on the row opens the conversation in
    /// the reading pane, as it did.
    func testTheListMarksItsRowsAndTheCellDrawsTheMark() throws {
        let list = try source("UI/MessageListViewController.swift")
        for wiring in [
            "private lazy var mine = OwnAddresses(account: CredentialStore.loadAccount())",
            "case let .thread(t): cell.configure(with: t.displayRow(in: mailbox, mine: mine), "
                + "marked: t.marksConversation(in: mailbox))",
            "case let .thread(thread): cell.configure(with: thread.displayRow(in: mailbox, mine: mine), "
                + "marked: thread.marksConversation(in: mailbox))",
            "case let .thread(thread) where thread.count > 1:",
            "open(thread, at: ip)",
        ] {
            XCTAssertTrue(list.contains(wiring), wiring)
        }
        XCTAssertEqual(list.components(separatedBy: "cell.configure(with:").count - 1, 2)

        let cell = try source("UI/MessageCell.swift")
        for wiring in [
            "senderLabel.text = m.sender",
            "conversationMark.image = UIImage(systemName: \"chevron.forward.circle\", "
                + "withConfiguration: Theme.conversationMarkSymbol)",
            "conversationMark.tintColor = Theme.tintBlue",
            "conversationMark.isHidden = !marked",
            "let markSize = conversationMark.isHidden ? nil : conversationMark.image?.size",
            "let line = RowTopLine(left: left, right: right, mark: markSize?.width, "
                + "gap: Theme.conversationMarkGap)",
            "place(timestampLabel, baseline: Theme.senderBaseline, left: line.dateX, width: line.dateWidth)",
            "place(senderLabel, baseline: Theme.senderBaseline, left: line.namesX, width: line.namesWidth)",
        ] {
            XCTAssertTrue(cell.contains(wiring), wiring)
        }
        XCTAssertFalse(cell.contains("MailFormat.displayName(m.sender)"))
        XCTAssertFalse(cell.contains("conversationMark.isUserInteractionEnabled"))
        XCTAssertFalse(cell.contains("GestureRecognizer"))
        XCTAssertFalse(cell.contains("UIButton"))
    }
}
