import XCTest
@testable import Blackmail

/// The list, Edit mode and the Updated line as Mail's, from the comparison
/// with Mail of 2026-10-29 (round r6-n-compare, Mail 16.5.1 on the test
/// iPad): the open letter's row blue with white words (C-1b, B-181); a
/// letter with no words saying its file, "No Recipient" and a grey "No
/// Subject" (C-3a, C-5a, B-182); Mark and Move grey in Drafts and a ticked
/// draft in the pane (C-5a, B-183); the Updated line's time of day from
/// the sixth minute, and white (C-6a, C-6b, B-184).
///
/// The rules are `RowShade`'s, `RowPreview`'s, `EditBar`'s, `EditPane`'s
/// and `UpdatedLine`'s, run here. The cell and the list's controller are
/// UIKit and built only for the device, so how they use the rules is read
/// from their source, comment lines out, as `EditModeLikeMailTests` reads
/// it.
final class ListLikeMailTests: XCTestCase {

    // MARK: - B-181, the open letter's row

    /// Out of Edit mode the selected row, the letter in the pane, is
    /// Mail's blue with its lines as on the blue, as a tick is; a press on
    /// another row is grey, its lines as always; a row neither selected nor
    /// pressed leaves the ground as it was, to fade out in its colour.
    func testTheOpenLettersRowIsBlueAsATickIs() {
        let open = RowShade(selected: true, pressed: false, ticks: false)
        XCTAssertEqual(open.ground, .blue)
        XCTAssertTrue(open.onBlue)
        XCTAssertFalse(open.tick, "no tick out of Edit mode")
        XCTAssertEqual(RowShade(selected: true, pressed: true, ticks: false).ground, .blue,
                       "the open row pressed again stays blue")

        let pressed = RowShade(selected: false, pressed: true, ticks: false)
        XCTAssertEqual(pressed.ground, .grey, "Mail's press was not seen: the grey kept")
        XCTAssertFalse(pressed.onBlue)
        XCTAssertFalse(pressed.tick)

        let neither = RowShade(selected: false, pressed: false, ticks: false)
        XCTAssertNil(neither.ground)
        XCTAssertFalse(neither.onBlue)
    }

    /// Edit mode as B-174 made it: a tick blue with its lines on the blue
    /// and the row's own tick; a press blue, the tick shown, its lines as
    /// always until it is ticked.
    func testATickAndAPressInEditModeAsBefore() {
        let ticked = RowShade(selected: true, pressed: false, ticks: true)
        XCTAssertEqual(ticked.ground, .blue)
        XCTAssertTrue(ticked.onBlue)
        XCTAssertTrue(ticked.tick)
        let pressed = RowShade(selected: false, pressed: true, ticks: true)
        XCTAssertEqual(pressed.ground, .blue)
        XCTAssertFalse(pressed.onBlue)
        XCTAssertTrue(pressed.tick)
        let neither = RowShade(selected: false, pressed: false, ticks: true)
        XCTAssertNil(neither.ground)
        XCTAssertFalse(neither.tick)
    }

    /// The cell takes its colours from `RowShade` at every change of the
    /// selection, a press and Edit mode, and nothing else decides them.
    func testTheCellIsDrawnByTheShade() throws {
        let cell = flat(try source("UI/MessageCell.swift"))
        XCTAssertTrue(cell.contains("override func setHighlighted(_ highlighted: Bool, animated: Bool) "
                                    + "{ super.setHighlighted(highlighted, animated: animated) colour() }"))
        XCTAssertFalse(cell.contains("ticks ? Theme.tintBlue : Theme.selection"))
        XCTAssertFalse(cell.contains("ticks && isSelected"))
        XCTAssertEqual(count("selectedGround.backgroundColor =", in: cell), 3,
                       "the first colour, then colour's blue and grey")
    }

    // MARK: - B-182, a row's words

    private func file(_ name: String, inline: Bool = false) -> Attachment {
        Attachment(id: "2", filename: name, mimeType: "image/jpeg", size: 120_000,
                   contentID: inline ? "pic1" : nil, isInline: inline)
    }

    private func row(_ id: String, preview: String = "", subject: String = "A picture",
                     files: [Attachment] = []) -> MessageSummary {
        MessageSummary(id: id, mailboxID: "INBOX", sender: "Pia Photo <pia@example.com>",
                       subject: subject, preview: preview,
                       date: Date(timeIntervalSince1970: 1_790_000_000),
                       isRead: true, isFlagged: false, hasAttachment: !files.isEmpty,
                       attachments: files)
    }

    /// A letter drawn with no words says its file, inline or attached, as
    /// Mail's rows said "Attachment: h-photo.jpg" and "Attachment:
    /// IMG_0131.jpg"; its first named file where it has more.
    func testALetterWithNoWordsSaysItsFile() {
        XCTAssertEqual(RowPreview.preview(of: row("1/5", files: [file("IMG_0131.jpg")]),
                                          drawnWithNoWords: true),
                       "Attachment: IMG_0131.jpg")
        XCTAssertEqual(RowPreview.preview(of: row("1/6", files: [file("h-photo.jpg", inline: true)]),
                                          drawnWithNoWords: true),
                       "Attachment: h-photo.jpg")
        XCTAssertEqual(RowPreview.preview(of: row("1/7", files: [file(""), file("Menu.pdf"),
                                                                   file("Map.jpg")]),
                                          drawnWithNoWords: true),
                       "Attachment: Menu.pdf")
    }

    /// Its words where it has any; nothing where its preview has not come
    /// yet, where it carries no file, or none with a name.
    func testOtherwiseTheRowIsAsItWas() {
        XCTAssertEqual(RowPreview.preview(of: row("1/5", preview: "See the photo.",
                                                  files: [file("IMG_0131.jpg")]),
                                          drawnWithNoWords: false),
                       "See the photo.")
        XCTAssertEqual(RowPreview.preview(of: row("1/5", files: [file("IMG_0131.jpg")]),
                                          drawnWithNoWords: false), "", "not come yet")
        XCTAssertEqual(RowPreview.preview(of: row("1/5"), drawnWithNoWords: true), "")
        XCTAssertEqual(RowPreview.preview(of: row("1/5", files: [file("")]), drawnWithNoWords: true), "")
    }

    /// The list knows a letter drawn with no words once its preview has
    /// come back empty, and not before; one with words is not.
    @MainActor
    func testTheListKnowsALetterDrawnWithNoWords() {
        let list = ListLetters()
        let picture = row("1/500", files: [file("IMG_0131.jpg")])
        let words = row("1/501")
        let waiting = row("1/502")
        _ = list.fetchedAfresh([picture, words, waiting])
        XCTAssertFalse(list.drawnWithNoWords(picture), "not asked yet")
        list.apply(previews: ["1/500": "", "1/501": "The roses are out."], in: "INBOX")
        let drawn = list.shownRow(of: picture)
        XCTAssertNotNil(drawn)
        XCTAssertTrue(list.drawnWithNoWords(drawn ?? picture))
        XCTAssertEqual(RowPreview.preview(of: drawn ?? picture,
                                          drawnWithNoWords: list.drawnWithNoWords(drawn ?? picture)),
                       "Attachment: IMG_0131.jpg")
        XCTAssertFalse(list.drawnWithNoWords(list.shownRow(of: words) ?? words))
        XCTAssertFalse(list.drawnWithNoWords(waiting))
    }

    /// "No Subject" for a letter with none, in the grey; a subject white.
    func testNoSubjectInTheGrey() {
        XCTAssertEqual(RowPreview.subject(""), "No Subject")
        XCTAssertTrue(RowPreview.subjectIsGrey(""))
        XCTAssertEqual(RowPreview.subject("Lunch"), "Lunch")
        XCTAssertFalse(RowPreview.subjectIsGrey("Lunch"))
    }

    /// Mail's "No Recipient", one, on a draft's row and the Outbox's.
    func testNoRecipientAsMailSaysIt() {
        XCTAssertEqual(RowNames.noRecipient, "No Recipient")
        XCTAssertEqual(Outbox.addressees(of: Draft()), "No Recipient")
    }

    /// The list draws every row's grey lines by `RowPreview`, from the
    /// letter whose preview the row shows; the cell its subject and its
    /// colour, the grey taking the row's state.
    func testTheListAndTheCellUseTheWords() throws {
        let list = flat(try source("UI/MessageListViewController.swift"))
        XCTAssertTrue(list.contains("if parts.contains(.lines) { var row = thread.displayRow(in: mailbox, "
                                    + "mine: mine) row.preview = RowPreview.preview(of: thread.newest, "
                                    + "drawnWithNoWords: letters.drawnWithNoWords(thread.newest)) "
                                    + "cell.configure(with: row, marked: thread.marksConversation(in: mailbox))"))
        let cell = flat(try source("UI/MessageCell.swift"))
        XCTAssertTrue(cell.contains("subjectLabel.text = RowPreview.subject(m.subject) "
                                    + "subjectIsGrey = RowPreview.subjectIsGrey(m.subject) drawSubject()"))
        XCTAssertTrue(cell.contains("private func drawSubject() { subjectLabel.textColor = "
                                    + "subjectIsGrey ? grey : Theme.primaryText }"))
        XCTAssertFalse(cell.contains("(no subject)"))
    }

    // MARK: - B-183, Drafts in Edit mode

    /// In Drafts Mark and Move are grey whatever is ticked, the third
    /// button blue with a tick; everywhere else as before.
    func testMarkAndMoveAreGreyInDrafts() {
        XCTAssertFalse(EditBar.marksAndMoves(ticked: 1, inFolderWithRole: .drafts))
        XCTAssertFalse(EditBar.marksAndMoves(ticked: 0, inFolderWithRole: .drafts))
        XCTAssertTrue(EditBar.acts(ticked: 1), "Trash blue in Drafts too")
        XCTAssertTrue(EditBar.marksAndMoves(ticked: 1, inFolderWithRole: .inbox))
        XCTAssertTrue(EditBar.marksAndMoves(ticked: 3, inFolderWithRole: nil))
        XCTAssertTrue(EditBar.marksAndMoves(ticked: 1, inFolderWithRole: .outbox), "the Outbox as before")
        XCTAssertFalse(EditBar.marksAndMoves(ticked: 0, inFolderWithRole: .inbox))
    }

    private func draft(_ id: String) -> MessageSummary {
        MessageSummary(id: id, mailboxID: "[Gmail]/Drafts", sender: "Dee Draft", subject: "",
                       preview: "", date: Date(timeIntervalSince1970: 1_790_000_000),
                       isRead: true, isFlagged: false, threadID: id)
    }

    /// A draft on the server ticked in Drafts opens in the pane, as Mail's;
    /// one kept on the iPad does not, nor anything in the Outbox; every
    /// other folder's as before.
    func testATickedDraftOnTheServerIsShownInThePane() {
        let server = MessageThread.rows(for: [draft("4/90")], grouped: false)[0]
        let kept = MessageThread.rows(for: [draft("local:ABC")], grouped: false)[0]
        XCTAssertNotNil(LocalDraft.key(ofRow: "local:ABC"), "the row id of a draft kept on the iPad")
        XCTAssertTrue(EditPane.opens(server, inFolderWithRole: .drafts, outbox: false))
        XCTAssertFalse(EditPane.opens(kept, inFolderWithRole: .drafts, outbox: false))
        XCTAssertFalse(EditPane.opens(server, inFolderWithRole: .outbox, outbox: true))
        XCTAssertTrue(EditPane.opens(server, inFolderWithRole: .inbox, outbox: false))

        let threads = MessageThread.rows(for: [draft("local:ABC"), draft("4/90")], grouped: false)
        let opens: (MessageThread) -> Bool = { EditPane.opens($0, inFolderWithRole: .drafts, outbox: false) }
        var pane = EditPane()
        pane.begin(showing: [], thread: nil)
        XCTAssertEqual(pane.ticked([1], in: threads, showing: [], opens: opens), 1)
        guard case .empty = pane.end(in: threads, showing: ["4/90"]) else {
            return XCTFail("Cancel puts the pane back")
        }
        pane.begin(showing: [], thread: nil)
        XCTAssertNil(pane.ticked([0], in: threads, showing: [], opens: opens), "kept on the iPad")
    }

    // MARK: - B-184, the Updated line

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 21 September 2026, 14:13:20 UTC.
    private let checked = Date(timeIntervalSince1970: 1_790_000_000)

    private func said(after seconds: TimeInterval) -> String {
        UpdatedLine.age(of: checked, now: checked.addingTimeInterval(seconds), calendar: Self.utc,
                        locale: Locale(identifier: "en_US"))
    }

    /// The minutes through five, as Mail said "Updated 5 minutes ago" at
    /// 5:14; the time of day from the sixth, as Mail's "Updated at 12:36
    /// PM" at 10:08; the rest as before.
    func testTheTimeOfDayFromTheSixthMinute() {
        XCTAssertEqual(UpdatedLine.minutesUntil, 360)
        XCTAssertEqual(said(after: 59), "Updated Just Now")
        XCTAssertEqual(said(after: 60), "Updated 1 minute ago")
        XCTAssertEqual(said(after: 2 * 60 + 7), "Updated 2 minutes ago")
        XCTAssertEqual(said(after: 5 * 60 + 14), "Updated 5 minutes ago")
        XCTAssertEqual(said(after: 5 * 60 + 59), "Updated 5 minutes ago")
        XCTAssertTrue(said(after: 6 * 60).hasPrefix("Updated at 2:13"), said(after: 6 * 60))
        XCTAssertTrue(said(after: 10 * 60 + 8).hasPrefix("Updated at 2:13"))
        XCTAssertTrue(said(after: 59 * 60).hasPrefix("Updated at 2:13"))
    }

    /// The line white, as Mail's is.
    func testTheLineIsWhite() throws {
        let list = flat(try source("UI/MessageListViewController.swift"))
        XCTAssertTrue(list.contains("statusLabel.font = Theme.fontToolbarStatus "
                                    + "statusLabel.textColor = Theme.primaryText"))
        XCTAssertFalse(list.contains("statusLabel.textColor = Theme.secondaryText"))
    }

    // MARK: - Reading the source

    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).joined(separator: " ")
    }
}
