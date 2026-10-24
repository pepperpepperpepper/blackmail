import XCTest
@testable import Blackmail

/// A letter opens ready to type, as Mail's does (B-120): the keyboard up,
/// the caret in To for a new letter and a forward, at the top of the body,
/// above his signature and the quote, for a reply and a draft reopened from
/// Drafts, and in Subject for a letter to someone with none. The rule is
/// Mail's composer's own, read from iOS 18.6's MessageUI
/// (`-[MFMailComposeController pickInitialFirstResponder]`). What it decides
/// is `ComposeForm`, run here; the two sheets are UIKit and never build on
/// this host, so their wiring is read from their source.
@MainActor
final class ReadyToTypeTests: XCTestCase {

    private let seen = Date(timeIntervalSince1970: 1_700_000_000)
    private let signature = "Sam\n1 Example Street"

    private func message() -> Message {
        Message(id: "1/9", mailboxID: "INBOX",
                sender: "Carlo <carlo@example.org>", senderAddress: "carlo@example.org",
                to: ["owner@example.com"], cc: [], subject: "Lunch",
                date: seen, textBody: "See you at one.", htmlBody: nil,
                attachments: [], messageID: "<a@example.org>", references: nil)
    }

    private func first(_ draft: Draft) -> ComposeForm.FirstField {
        ComposeForm.firstField(to: draft.to, subject: draft.subject)
    }

    // MARK: - Where it opens

    /// A new letter and a forward have nobody in To: To.
    func testANewLetterAndAForwardOpenInTo() {
        XCTAssertEqual(first(Draft.blank(signature: signature)), .to)
        let forward = Draft.forwarding(message(), signature: signature)
        XCTAssertEqual(forward.subject, "Fwd: Lunch")
        XCTAssertEqual(first(forward), .to, "a forward's subject does not take it out of To")
    }

    /// A reply has its people and its subject: the body, the caret at its
    /// start, which is the empty line above his signature and the quote.
    func testAReplyOpensInTheBodyAboveTheQuote() {
        for all in [false, true] {
            let reply = Draft.replying(to: message(), all: all, myAddress: "owner@example.com",
                                       signature: signature)
            XCTAssertEqual(first(reply), .body)
            XCTAssertTrue(reply.body.hasPrefix("\n\n" + signature + "\n\n"),
                          "the caret's line, at 0, is the empty one above the signature")
            let quote = reply.body.range(of: "> See you at one.")
            XCTAssertNotNil(quote)
            XCTAssertGreaterThan(reply.body.distance(from: reply.body.startIndex,
                                                     to: quote!.lowerBound), 0)
        }
        // With no signature, the empty line above the quote.
        let bare = Draft.replying(to: message(), all: false, myAddress: "owner@example.com")
        XCTAssertEqual(first(bare), .body)
        XCTAssertTrue(bare.body.hasPrefix("\n\n"))
    }

    /// A draft reopened from Drafts, the iPad or the Outbox: the same three
    /// questions, as Mail's composer has no case of its own for a draft.
    func testADraftReopenedOpensByTheSameRule() {
        var draft = Draft.blank(signature: signature)
        draft.to = ["carlo@example.org"]
        draft.subject = "Sunday"
        XCTAssertEqual(first(draft), .body)

        draft.subject = ""
        XCTAssertEqual(first(draft), .subject, "to someone, with no subject: Subject")

        draft.to = []
        draft.cc = ["carlo@example.org"]
        draft.subject = "Sunday"
        XCTAssertEqual(first(draft), .to, "Mail asks of To alone, not Cc")

        draft.to = ["  ", ""]
        XCTAssertEqual(first(draft), .to, "an entry of spaces is nobody")
    }

    /// Mail asks whether Subject's length is nought: spaces are a subject.
    func testASubjectOfSpacesIsASubject() {
        XCTAssertEqual(ComposeForm.firstField(to: ["carlo@example.org"], subject: " "), .body)
        XCTAssertEqual(ComposeForm.firstField(to: ["carlo@example.org"], subject: ""), .subject)
        XCTAssertEqual(ComposeForm.firstField(to: [], subject: ""), .to)
    }

    /// A share, from a page or of words or a photo, has nobody in To: To,
    /// as the share sheet already opened.
    func testAShareOpensInTo() {
        let sheet = shareSheet()
        let page = URL(string: "https://en.wikipedia.org/wiki/Opera_house")!
        for items: [SharedItem] in [[.link(page, title: "Opera house - Wikipedia")],
                                    [.link(page, title: nil)],
                                    [.text("Three lines\nof a poem")]] {
            XCTAssertEqual(first(sheet.letter(from: items)), .to)
        }
    }

    // MARK: - When

    /// Once, the first time the sheet appears; never with an alert or
    /// another sheet up over it; never once he is in a field himself.
    func testItIsDoneOnceAndNeverOverSomethingOrUnderHisCaret() {
        XCTAssertTrue(ComposeForm.readiesOnAppearing(done: false, covered: false, inAField: false))
        XCTAssertFalse(ComposeForm.readiesOnAppearing(done: true, covered: false, inAField: false))
        XCTAssertFalse(ComposeForm.readiesOnAppearing(done: false, covered: true, inAField: false))
        XCTAssertFalse(ComposeForm.readiesOnAppearing(done: false, covered: false, inAField: true))
        XCTAssertFalse(ComposeForm.readiesOnAppearing(done: true, covered: true, inAField: true))
    }

    // MARK: - The sheets' wiring

    /// Both sheets ask the rule as they appear, mark the one chance taken
    /// whatever it decides, and put the caret where it says: To, Subject,
    /// or the body at 0 with the line brought into view.
    func testBothSheetsAreMadeReadyAsTheyAppear() async throws {
        for file in [Self.composer, Self.share] {
            let code = try source(file)
            for line in ["private var readied = false",
                         "override func viewDidAppear(_ animated: Bool) { "
                            + "super.viewDidAppear(animated) readyToType() }",
                         "let fields: [UIView] = [toField, ccField, bccField, subjectField, bodyView] "
                            + "let inAField = fields.contains { $0.isFirstResponder } "
                            + "defer { readied = true } "
                            + "guard ComposeForm.readiesOnAppearing(done: readied, "
                            + "covered: presentedViewController != nil, "
                            + "inAField: inAField) else { return }",
                         "switch ComposeForm.firstField(to: toField.recipients, "
                            + "subject: subjectField.text ?? \"\") { "
                            + "case .to: toField.becomeFirstResponder() "
                            + "case .subject: subjectField.becomeFirstResponder() "
                            + "case .body: bodyView.becomeFirstResponder() "
                            + "bodyView.selectedRange = NSRange(location: 0, length: 0) "
                            + "keepCaretInView() }"] {
                XCTAssertTrue(code.contains(line), "\(file): \(line)")
            }
            XCTAssertEqual(code.components(separatedBy: "readyToType()").count - 1, 2,
                           "\(file): called from viewDidAppear alone")
            XCTAssertEqual(code.components(separatedBy: "override func viewDidAppear").count - 1, 1,
                           file)
        }
        XCTAssertFalse(try source(Self.share).contains("if draft.to.isEmpty { toField.becomeFirstResponder() }"))
    }

    // MARK: - Helpers

    private static let composer = "UI/ComposeViewController.swift"
    private static let share = "Share/ShareViewController.swift"

    private func shareSheet() -> ShareSheet {
        let account = MailAccount(address: "owner@example.com", username: "owner@example.com",
                                  displayName: "Sam", signature: signature, signatureHTML: "")
        return ShareSheet(
            shared: ShareMirror.Shared(account: account, password: "app-password",
                                       signatureImages: [], recipients: []),
            transport: { _, _ in ScriptedSubmission() },
            noteSent: { _ in }, finish: {}, cancel: {}, showError: { _ in }, draw: { _ in },
            background: BackgroundTime(begin: { _, _ in nil }, end: { _ in }))
    }

    /// The file's code with its comment lines dropped and its spacing
    /// made single, so a line is found however it is wrapped.
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
}
