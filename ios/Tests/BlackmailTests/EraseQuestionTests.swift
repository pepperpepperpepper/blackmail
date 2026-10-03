import XCTest
@testable import Blackmail

/// The question a Delete inside Trash asks before it erases (B-062): when it
/// is asked, in what words, and that both of the app's Deletes ask it. The
/// alert and the two controllers are UIKit and never build on this host, so
/// their wiring is read from their source, as `SignInTests` reads the forms'.
final class EraseQuestionTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private let folders = [
        Mailbox(id: "inbox", name: "Inbox", unreadCount: 0, role: .inbox),
        Mailbox(id: Server.inbox, name: "INBOX", unreadCount: 0, role: .inbox),
        Mailbox(id: Server.allMail, name: "All Mail", unreadCount: 0, role: .archive),
        Mailbox(id: Server.spam, name: "Spam", unreadCount: 0, role: .junk),
        Mailbox(id: Server.trash, name: "Trash", unreadCount: 0, role: .trash),
        Mailbox(id: Server.sent, name: "Sent Mail", unreadCount: 0, role: .sent),
        Mailbox(id: Server.drafts, name: "Drafts", unreadCount: 0, role: .drafts),
    ]

    private func question(_ mailboxes: [String]) -> EraseQuestion? {
        let letters = mailboxes.enumerated().map { i, mailbox in letter("1/\(i + 1)", in: mailbox) }
        return EraseQuestion.before(deleting: letters, role: { self.folders.role(of: $0) })
    }

    private func letter(_ id: String, in mailbox: String) -> MessageSummary {
        MessageSummary(id: id, mailboxID: mailbox, sender: "Sam Example <sam@example.com>",
                       subject: "Lunch on Sunday", preview: "", date: Server.newestDate,
                       isRead: false, isFlagged: false)
    }

    // MARK: - When it is asked

    /// Only inside Trash, where Delete sets `\Deleted` and Gmail erases the
    /// letter. Everywhere else Delete moves to Trash, Spam included, as
    /// Mail's does from Junk, and nothing is asked.
    func testOnlyALetterInTrashIsErasedAndAsksFirst() {
        XCTAssertTrue(EraseQuestion.erases(fromFolderWithRole: .trash))
        for role: Mailbox.Role? in [.inbox, .archive, .junk, .sent, .drafts, .outbox, nil] {
            XCTAssertFalse(EraseQuestion.erases(fromFolderWithRole: role), "\(String(describing: role))")
        }
        XCTAssertNotNil(question([Server.trash]))
        for mailbox in ["inbox", Server.inbox, Server.allMail, Server.spam, Server.sent,
                        Server.drafts, "Receipts"] {
            XCTAssertNil(question([mailbox]), mailbox)
            XCTAssertNil(question([mailbox, mailbox]), mailbox)
        }
        // By the role word too, before the folders are listed.
        XCTAssertNotNil(EraseQuestion.before(deleting: [letter("1/1", in: "trash")],
                                             role: { [Mailbox]().role(of: $0) }))
    }

    // MARK: - What it says

    /// Mail's form: the verb he tapped in red, Cancel beside it, and
    /// Apple's own sentence for a delete that skips the bin.
    func testTheQuestionIsMailsWordsForOneLetterAndForSeveral() {
        XCTAssertEqual(EraseQuestion.delete, "Delete")
        XCTAssertEqual(EraseQuestion.cancel, "Cancel")
        XCTAssertEqual(question([Server.trash]),
                       EraseQuestion(title: "Delete Message?",
                                     message: "This message will be deleted immediately. "
                                         + "You can't undo this action."))
        XCTAssertEqual(question([Server.trash, Server.trash, Server.trash]),
                       EraseQuestion(title: "Delete 3 Messages?",
                                     message: "These messages will be deleted immediately. "
                                         + "You can't undo this action."))
    }

    /// An All Mailboxes search can tick letters from Trash among others,
    /// which go to Trash: the title counts every letter the Delete takes,
    /// and the sentence only those that cannot be got back.
    func testAMixedSelectionSaysWhichOfItCannotBeGotBack() {
        XCTAssertEqual(question([Server.allMail, Server.trash, Server.spam]),
                       EraseQuestion(title: "Delete 3 Messages?",
                                     message: "1 of them is in the Trash and will be deleted "
                                         + "immediately. You can't undo this action."))
        XCTAssertEqual(question([Server.trash, Server.allMail, Server.trash, Server.allMail]),
                       EraseQuestion(title: "Delete 4 Messages?",
                                     message: "2 of them are in the Trash and will be deleted "
                                         + "immediately. You can't undo this action."))
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

    /// The reading pane's Delete and Edit mode's both ask, by the role of
    /// each letter's own folder, and go only on Delete; the alert has
    /// Cancel and Delete in red, and is an alert, which keeps its Cancel on
    /// the iPad, where an action sheet's popover drops it.
    func testBothDeletesAskInsideTrashAndGoOnlyOnDelete() throws {
        let wiring: [(String, [String])] = [
            ("UI/EraseConfirmation.swift", [
                "let alert = UIAlertController(title: question.title, message: question.message, "
                    + "preferredStyle: .alert)",
                "alert.addAction(UIAlertAction(title: EraseQuestion.cancel, style: .cancel))",
                "alert.addAction(UIAlertAction(title: EraseQuestion.delete, style: .destructive) "
                    + "{ _ in delete() })",
            ]),
            ("UI/MessageDetailViewController.swift", [
                "@objc private func deleteTapped() { guard let s = summary, !writes.deleting "
                    + "else { return } guard let question = questionBeforeDeleting?(s) else { "
                    + "delete(s) return } EraseConfirmation.ask(question, on: self) { [weak self] in "
                    + "guard let self, self.summary?.id == s.id else { return } self.delete(s) } }",
                "private func delete(_ s: MessageSummary) { guard writes.startDelete() else { "
                    + "return } showEmpty()",
            ]),
            ("UI/MessageListViewController.swift", [
                "guard let question = EraseQuestion.before(deleting: chosen, role: { "
                    + "self.role(of: $0) }) else { delete(chosen) return } "
                    + "EraseConfirmation.ask(question, on: self) { [weak self] in "
                    + "self?.delete(chosen) }",
                "private func role(of mailboxID: String) -> Mailbox.Role? { "
                    + "([mailbox] + folders()).role(of: mailboxID) }",
            ]),
            ("UI/RootViewController.swift", [
                "detail.questionBeforeDeleting = { [weak self] letter in guard let self else { "
                    + "return nil } let folders = [self.list.shownMailbox] + "
                    + "self.mailboxList.folders return EraseQuestion.before(deleting: [letter], "
                    + "role: { folders.role(of: $0) }) }",
                "list.folders = { [weak self] in self?.mailboxList.folders ?? [] }",
            ]),
        ]
        for (file, lines) in wiring {
            let code = try source(file)
            for line in lines { XCTAssertTrue(code.contains(line), "\(file): \(line)") }
        }
        // Nothing else in the pane sends a Delete.
        let pane = try source("UI/MessageDetailViewController.swift")
        XCTAssertEqual(pane.components(separatedBy: "performed(.delete").count - 1, 1)
    }
}
