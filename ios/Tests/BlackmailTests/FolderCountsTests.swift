import XCTest
@testable import Blackmail

/// The folder pane's counts between sweeps and where each folder is drawn
/// (B-059): the two count bugs seen on the iPad on 2026-09-30, a read mark
/// drawn on the Inbox's block alone, and a sweep that left before a read
/// mark putting the letter back. The pane is UIKit, so its wiring is read
/// from its source.
final class FolderCountsTests: XCTestCase {

    private let inbox = "INBOX"
    private let drafts = "[Gmail]/Drafts"
    private let sent = "[Gmail]/Sent Mail"
    private let allMail = "[Gmail]/All Mail"
    private let important = "[Gmail]/Important"

    /// His folders as a sweep lists them, the Inbox first, with `unread`
    /// letters in the Inbox, All Mail and Important, where an unread letter
    /// in the Inbox is counted, and `sent` in Sent Mail.
    private func folders(unread: Int = 2, sent sentCount: Int = 1) -> [Mailbox] {
        [Mailbox(id: inbox, name: "INBOX", unreadCount: unread, role: .inbox),
         Mailbox(id: drafts, name: "Drafts", unreadCount: 0, role: .drafts, depth: 1),
         Mailbox(id: sent, name: "Sent Mail", unreadCount: sentCount, role: .sent, depth: 1),
         Mailbox(id: allMail, name: "All Mail", unreadCount: unread, role: .archive, depth: 1),
         Mailbox(id: important, name: "Important", unreadCount: unread, role: nil, depth: 1)]
    }

    private func count(_ counts: FolderCounts, _ id: String) -> Int? {
        counts.folders.first { $0.id == id }?.unreadCount
    }

    private func kept(_ list: [Mailbox]) -> FolderCounts {
        var counts = FolderCounts()
        counts.take(list)
        return counts
    }

    // MARK: - Where a folder is drawn

    /// Each folder is found in its block, at its row there: the Inbox alone
    /// in the first, the rest in the second, the Outbox in a third while
    /// letters wait. Never at its place in the flat list in the first
    /// block, where a read mark used to look for every folder's cell.
    func testEveryFolderIsFoundWhereItIsDrawn() {
        let counts = kept(folders())
        let blocks = counts.blocks(outbox: 0)
        XCTAssertEqual(blocks.map(\.count), [1, 4])
        let inboxPlace = FolderCounts.place(of: inbox, in: blocks)
        XCTAssertEqual(inboxPlace?.section, 0)
        XCTAssertEqual(inboxPlace?.row, 0)
        for (flat, id) in [drafts, sent, allMail, important].enumerated() {
            let place = FolderCounts.place(of: id, in: blocks)
            XCTAssertEqual(place?.section, 1, id)
            XCTAssertEqual(place?.row, flat, id)
        }
        // By its role word, as the message pane names the Inbox at launch.
        XCTAssertEqual(FolderCounts.place(of: "inbox", in: blocks)?.section, 0)
        XCTAssertNil(FolderCounts.place(of: "[Gmail]/Gone", in: blocks))

        let waiting = counts.blocks(outbox: 2)
        XCTAssertEqual(waiting.map(\.count), [1, 4, 1])
        XCTAssertEqual(FolderCounts.place(of: Outbox.mailboxID, in: waiting)?.section, 2)
        XCTAssertEqual(FolderCounts.place(of: sent, in: waiting)?.section, 1)
    }

    /// With no Inbox listed, the rest are the first block.
    func testWithNoInboxTheFoldersAreTheFirstBlock() {
        let counts = kept(Array(folders().dropFirst()))
        let blocks = counts.blocks(outbox: 0)
        XCTAssertEqual(blocks.map(\.count), [4])
        XCTAssertEqual(FolderCounts.place(of: sent, in: blocks)?.section, 0)
        XCTAssertEqual(FolderCounts.place(of: sent, in: blocks)?.row, 1)
    }

    /// A read mark changes every folder the letter is counted in, and says
    /// which: the Inbox, All Mail and Important, each drawn in its block.
    func testAReadMarkChangesEveryFolderItIsCountedIn() {
        var counts = kept(folders())
        let changed = counts.adjust([inbox, allMail, important], by: -1)
        XCTAssertEqual(changed.map(\.id), [inbox, allMail, important])
        XCTAssertEqual(changed.map(\.unreadCount), [1, 1, 1])
        XCTAssertEqual(count(counts, sent), 1, "untouched")
        let blocks = counts.blocks(outbox: 0)
        XCTAssertEqual(changed.compactMap { FolderCounts.place(of: $0.id, in: blocks)?.section },
                       [0, 1, 1])
        // Never below none, and a folder not listed is passed over.
        let again = counts.adjust([drafts, "[Gmail]/Gone"], by: -1)
        XCTAssertEqual(again, [])
        XCTAssertEqual(count(counts, drafts), 0)
    }

    // MARK: - A sweep that left before a read mark

    /// The sweep out when he reads a letter lands with the count from
    /// before his mark, exactly the pane's before it: the mark is put on
    /// it, and the Inbox stays at 1, not 2, as do the other folders the
    /// letter was counted in, while a folder he did not touch takes the
    /// sweep's count. Its answer is to be kept so. The sweep after the mark
    /// lands whole.
    func testASweepThatLeftBeforeAReadMarkDoesNotPutTheLetterBack() {
        var counts = kept(folders(unread: 2, sent: 1))
        let sweep = counts.mark
        _ = counts.adjust([inbox, allMail, important], by: -1)
        XCTAssertEqual(counts.land(folders(unread: 2, sent: 4), sweptFrom: sweep), 3)
        XCTAssertEqual(count(counts, inbox), 1)
        XCTAssertEqual(count(counts, allMail), 1)
        XCTAssertEqual(count(counts, important), 1)
        XCTAssertEqual(count(counts, sent), 4, "the sweep's, untouched here")

        // The sweep owed after the mark, and then one with new mail: whole.
        let owed = counts.mark
        XCTAssertEqual(counts.land(folders(unread: 1, sent: 4), sweptFrom: owed), 0)
        XCTAssertEqual(count(counts, inbox), 1)
        let later = counts.mark
        XCTAssertEqual(counts.land(folders(unread: 3, sent: 4), sweptFrom: later), 0)
        XCTAssertEqual(count(counts, inbox), 3)
    }

    /// A sweep that left after the mark has it: taken whole, even where it
    /// differs from the pane's arithmetic, since it is what the server has.
    func testASweepThatLeftAfterTheMarkIsTakenWhole() {
        var counts = kept(folders(unread: 2))
        _ = counts.adjust([inbox], by: -1)
        let sweep = counts.mark
        XCTAssertEqual(counts.land(folders(unread: 5), sweptFrom: sweep), 0)
        XCTAssertEqual(count(counts, inbox), 5)
    }

    /// An unread mark is held as a read mark is. A mark at none holds
    /// nothing: the number did not move, so the pane's count was not the
    /// server's, and the sweep's is taken.
    func testAnUnreadMarkIsHeldAndAMarkAtNoneHoldsNothing() {
        var counts = kept(folders(unread: 1))
        var sweep = counts.mark
        _ = counts.adjust([inbox], by: 1)
        XCTAssertEqual(counts.land(folders(unread: 1), sweptFrom: sweep), 1)
        XCTAssertEqual(count(counts, inbox), 2)

        counts = kept(folders(unread: 0))
        sweep = counts.mark
        XCTAssertEqual(counts.adjust([inbox], by: -1), [])
        XCTAssertEqual(counts.land(folders(unread: 1), sweptFrom: sweep), 0)
        XCTAssertEqual(count(counts, inbox), 1)
    }

    /// A count kept from the last launch that the server has gone on from
    /// gives way to the sweep, whichever side of his mark its STATUS went:
    /// two letters came overnight to a kept none, and he read one; or the
    /// kept 5 is 3 since he read two on his phone, and he read one here.
    /// Held, the pane would say none, or 4; the sweep's count is never
    /// lower than the server's, and the sweep owed after the mark says it.
    func testACountKeptFromTheLastLaunchGivesWayToTheSweep() {
        for (statusSaw, server) in [(2, 1), (1, 1)] {
            var counts = kept(folders(unread: 0))
            let sweep = counts.mark
            _ = counts.adjust([inbox, allMail, important], by: -1)
            XCTAssertEqual(counts.land(folders(unread: statusSaw), sweptFrom: sweep), 0)
            XCTAssertEqual(count(counts, inbox), statusSaw)
            XCTAssertGreaterThanOrEqual(count(counts, inbox) ?? 0, server)
        }
        for (statusSaw, server) in [(3, 2), (2, 2)] {
            var counts = kept(folders(unread: 5))
            let sweep = counts.mark
            _ = counts.adjust([inbox], by: -1)
            XCTAssertEqual(counts.land(folders(unread: statusSaw), sweptFrom: sweep), 0)
            XCTAssertEqual(count(counts, inbox), statusSaw)
            XCTAssertGreaterThanOrEqual(count(counts, inbox) ?? 0, server)
        }
    }

    /// New mail the sweep saw, as well as the letter he read since it
    /// left, is taken with the sweep's count: one too many until the sweep
    /// owed after the mark, rather than the new letter not counted.
    func testNewMailTheSweepSawIsTaken() {
        var counts = kept(folders(unread: 2))
        let sweep = counts.mark
        _ = counts.adjust([inbox], by: -1)
        XCTAssertEqual(counts.land(folders(unread: 3), sweptFrom: sweep), 0)
        XCTAssertEqual(count(counts, inbox), 3)
    }

    /// A mark made by the role word holds the folder it matched.
    func testAMarkByItsRoleWordHoldsTheFolderItMatched() {
        var counts = kept(folders(unread: 2))
        let sweep = counts.mark
        _ = counts.adjust(["inbox"], by: -1)
        counts.land(folders(unread: 2), sweptFrom: sweep)
        XCTAssertEqual(count(counts, inbox), 1)
    }

    /// While the pane has names and no counts, the noughts are not counts:
    /// the first sweep's are taken whole, and a mark is put on one only
    /// when it says that same nought, which was then the count. Marked
    /// unread with the server at 3, the pane's 1 gives way to the 3.
    func testNamesWithoutCountsGiveWayToTheFirstSweep() {
        var counts = FolderCounts()
        counts.take(folders(unread: 0, sent: 0))
        var sweep = counts.mark
        _ = counts.adjust([inbox], by: -1)
        XCTAssertEqual(counts.land(folders(unread: 2), sweptFrom: sweep), 0)
        XCTAssertEqual(count(counts, inbox), 2)

        counts.take(folders(unread: 0, sent: 0))
        sweep = counts.mark
        _ = counts.adjust([inbox], by: 1)
        XCTAssertEqual(counts.land(folders(unread: 3), sweptFrom: sweep), 0)
        XCTAssertEqual(count(counts, inbox), 3)
        counts.take(folders(unread: 0, sent: 0))
        sweep = counts.mark
        _ = counts.adjust([inbox], by: 1)
        XCTAssertEqual(counts.land(folders(unread: 0), sweptFrom: sweep), 1)
        XCTAssertEqual(count(counts, inbox), 1)
    }

    // MARK: - The pane

    /// The pane draws a mark's counts where each folder is, holds a sweep
    /// that left before a mark to the pane's counts and keeps them so, and
    /// draws the kept folders as counts and the names alone as none.
    func testThePaneUsesTheFoldersPlacesAndHoldsMarksOverAStaleSweep() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/UI/MailboxListViewController.swift")
        let pane = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " }).joined(separator: " ")
        XCTAssertFalse(pane.contains("section: 0"))
        XCTAssertTrue(pane.contains(
            "func adjustUnreadCounts(_ mailboxIDs: [String], by delta: Int) { "
            + "sweeps.requestIfRunning()"))
        XCTAssertTrue(pane.contains(
            "let blocks = groups for folder in counts.adjust(mailboxIDs, by: delta) { "
            + "guard let place = FolderCounts.place(of: folder.id, in: blocks), "
            + "let cell = tableView.cellForRow(at: IndexPath(row: place.row, "
            + "section: place.section)) else { continue } configure(cell, with: folder) }"))
        XCTAssertTrue(pane.contains(
            "let mark = counts.mark do { let fresh = try await repository.listMailboxes() "
            + "let held = counts.land(fresh, sweptFrom: mark) if held > 0 { "
            + "repository.shelf?.took(folders: counts.folders) "
            + "Diagnostics.log(.note, \"FOLDER-COUNTS held-over-sweep=\\(held)\") }"))
        XCTAssertTrue(pane.contains("counts.take(kept)"))
        XCTAssertTrue(pane.contains("counts.take(fresh)"))
        XCTAssertTrue(pane.contains("counts.blocks(outbox: outboxCount)"))
    }

    /// The gap under a block is clear and lets taps through, since a
    /// footer in the pane's plain table floats, and one left where the
    /// keyboard pinned it lay over the Important row: painted, it drew the
    /// row blank and took its taps (B-065).
    func testTheGapBetweenBlocksHidesNoRowAndTakesNoTap() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/UI/MailboxListViewController.swift")
        let pane = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " }).joined(separator: " ")
        XCTAssertTrue(pane.contains(
            "guard s < groups.count - 1 else { return nil } let spacer = UIView() "
            + "spacer.backgroundColor = .clear spacer.isUserInteractionEnabled = false "
            + "return spacer"))
        XCTAssertFalse(pane.contains("spacer.backgroundColor = Theme.canvas"))
    }
}
