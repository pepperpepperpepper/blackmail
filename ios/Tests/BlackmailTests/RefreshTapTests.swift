import XCTest
@testable import Blackmail

/// His Refresh sends what waits in the Outbox, as Mail's does (B-072): which
/// letters each kind of pass takes by their size, the Refresh's order, and
/// its wiring in the screens, read from their source as `SteadyChromeTests`
/// reads it. The passes themselves, over the scripted servers, are in
/// `OutboxTests`.
@MainActor
final class RefreshTapTests: XCTestCase {

    // MARK: - What each pass takes by size

    private func kept(outbox: Bool, files: [DraftAttachment], markup: Int = 0) -> LocalDraft {
        var draft = Draft()
        draft.to = ["carlo@example.org"]
        draft.subject = "Sunday"
        draft.attachments = files
        var letter = LocalDraft(key: "letter-1", draft: draft, version: "1", tried: [],
                                unfinished: false, keptAt: Date(), account: nil, gone: false,
                                outbox: outbox ? "<letter-1@example.com>" : nil)
        letter.markupBytes = markup
        return letter
    }

    /// A forward's file, fetched from Gmail before the letter is built.
    private func fromGmail(_ size: Int64?) -> DraftAttachment {
        DraftAttachment(source: .messagePart(messageID: "600001/1004", mailboxID: "INBOX",
                                             section: "2"),
                        filename: "Garden.mov", mimeType: "video/quicktime", size: size)
    }

    /// A photo on the iPad.
    private func onTheIPad(_ size: Int64) -> DraftAttachment {
        DraftAttachment(source: .localFile(URL(fileURLWithPath: "/nowhere/Garden.jpg")),
                        filename: "Garden.jpg", mimeType: "image/jpeg", size: size)
    }

    /// For each letter, whether a pass nobody asked for, his Refresh and
    /// his leaving take it. Only a large letter in the Outbox changes: his
    /// Refresh takes it now. A large draft still waits for him to leave.
    func testWhatEachPassTakesBySize() async {
        let cases: [(String, LocalDraft, [Bool])] = [
            ("Outbox, 2 MB from Gmail", kept(outbox: true, files: [fromGmail(2_000_000)]),
             [false, true, true]),
            ("Outbox, a file from Gmail of no known size", kept(outbox: true, files: [fromGmail(nil)]),
             [false, true, true]),
            ("Outbox, exactly a megabyte from Gmail",
             kept(outbox: true, files: [fromGmail(Int64(ComposeActions.countsFrom))]),
             [false, true, true]),
            ("Outbox, a byte under it", kept(outbox: true,
                                            files: [fromGmail(Int64(ComposeActions.countsFrom - 1))]),
             [true, true, true]),
            ("Outbox, 2 MB of photos on the iPad", kept(outbox: true, files: [onTheIPad(2_000_000)]),
             [true, true, true]),
            ("Outbox, nothing", kept(outbox: true, files: []), [true, true, true]),
            ("Draft, 2 MB of photos", kept(outbox: false, files: [onTheIPad(2_000_000)]),
             [false, false, true]),
            ("Draft, 2 MB from Gmail", kept(outbox: false, files: [fromGmail(2_000_000)]),
             [false, false, true]),
            ("Draft, a megabyte of quote", kept(outbox: false, files: [], markup: 1_000_000),
             [false, false, true]),
            ("Draft, nothing", kept(outbox: false, files: []), [true, true, true]),
        ]
        for (name, letter, expected) in cases {
            let taken = [LocalDrafts.Pass.unasked, .refresh, .leaving].map { letter.goes(by: $0) }
            XCTAssertEqual(taken, expected, name)
        }
    }

    // MARK: - The order

    /// What `RefreshTap.run` did, in order.
    private final class Said {
        var lines: [String] = []
    }

    /// The page first, then the counts, and once the page's previews and the
    /// counts have come, the pass.
    func testThePageAndTheCountsGoBeforeThePass() async {
        let said = Said()
        await RefreshTap.run(page: { said.lines.append("page"); return true },
                             counts: { said.lines.append("counts") },
                             shown: { said.lines.append("shown") },
                             pass: { said.lines.append("pass") })
        XCTAssertEqual(said.lines, ["page", "counts", "shown", "pass"])
    }

    /// A page that did not come sets no pass off, as before: there is no
    /// connection for one. The counts are asked for all the same.
    func testAPageThatDidNotComeSetsNoPassOff() async {
        let said = Said()
        await RefreshTap.run(page: { said.lines.append("page"); return false },
                             counts: { said.lines.append("counts") },
                             shown: { said.lines.append("shown") },
                             pass: { said.lines.append("pass") })
        XCTAssertEqual(said.lines, ["page", "counts"])
    }

    /// The pass waits for the previews and the counts however long they
    /// take, and goes once they have come.
    func testThePassWaitsForWhatHeAskedToSee() async throws {
        let said = Said()
        let shown = Held()
        let tap = Task { @MainActor in
            await RefreshTap.run(page: { true },
                                 counts: { said.lines.append("counts") },
                                 shown: {
                                     try? await shown.wait()
                                     said.lines.append("shown")
                                 },
                                 pass: { said.lines.append("pass") })
        }
        for _ in 0..<1_000 where shown.waiting == 0 {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(shown.waiting, 1)
        XCTAssertEqual(said.lines, ["counts"], "no pass while they come")
        shown.release()
        await tap.value
        XCTAssertEqual(said.lines, ["counts", "shown", "pass"])
    }

    // MARK: - The wiring, read from the source

    /// A file of the app's sources, comment lines dropped and whitespace
    /// run together, as `SteadyChromeTests` reads them.
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

    private func count(_ text: String, in code: String) -> Int {
        code.components(separatedBy: text).count - 1
    }

    /// Refresh fetches the page with no pass of its own, asks for the
    /// counts, waits for the page's previews and the counts, and then asks
    /// for the pass with the Refresh's kind. The page's pass goes as before
    /// for every other page, and the previews it waits for are the page's.
    func testRefreshAsksForItsPassAfterThePageAndTheCounts() async throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains(
            "@objc private func refreshTapped() { Task { @MainActor in await RefreshTap.run( "
            + "page: { await self.reload(passing: false) }, "
            + "counts: { self.onRefreshRequested?() }, "
            + "shown: { await self.pagePreviews?.value await self.countsCame() }, "
            + "pass: { _ = self.kept.uploadWaiting(to: self.repository, for: .refresh) }) } }"))
        XCTAssertTrue(list.contains("func reload(keepingPlace: Bool = false, quietly: Bool = false, "
                                    + "passing: Bool = true) async -> Bool"))
        XCTAssertEqual(count("if passing { kept.uploadWaiting(to: repository) }", in: list), 2,
                       "the Outbox's and the page's, each only when it is not his Refresh")
        XCTAssertEqual(count("kept.uploadWaiting(to: repository)", in: list), 3,
                       "those two and the kept page's, all nobody's")
        XCTAssertTrue(list.contains("pagePreviews = loadPreviews(for: unpreviewed)"))
    }

    /// The container hands the list the counts to wait for, and every other
    /// pass keeps its kind: coming back and the watch's check nobody's, and
    /// leaving the app's own. Refresh is the one pass of its kind.
    func testEveryOtherPassKeepsItsKind() async throws {
        let root = try source("UI/RootViewController.swift")
        XCTAssertTrue(root.contains("list.countsCame = { [weak self] in "
                                    + "await self?.mailboxList.countsSwept() }"))
        XCTAssertEqual(count("LocalDrafts.shared.uploadWaiting(to: repository)", in: root), 2,
                       "coming back and the watch's check")
        XCTAssertEqual(count("LocalDrafts.shared.uploadWaiting(to: repository, for: .leaving)",
                             in: root), 1)

        let folders = try source("UI/MailboxListViewController.swift")
        XCTAssertTrue(folders.contains("func countsSwept() async { await sweeps.idle() }"))

        var refreshes = 0
        for folder in ["UI", "App", "Share"] {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/Blackmail/\(folder)")
            for name in try FileManager.default.contentsOfDirectory(atPath: url.path)
            where name.hasSuffix(".swift") {
                refreshes += count("for: .refresh", in: try source("\(folder)/\(name)"))
            }
        }
        XCTAssertEqual(refreshes, 1, "his Refresh's alone")
    }
}
