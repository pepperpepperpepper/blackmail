import XCTest
@testable import Blackmail

/// A Save in Settings with no connection (B-085). Seen on the iPad on
/// 2026-10-19: with Airplane Mode on, every Save was followed by "Can't
/// connect to mail server." The save had worked. The list asked for the
/// folder counts after it, and that sweep could not reach the server. No
/// count changes with what Settings saves, so the Save asks the server for
/// nothing now. His Refresh still says when there is no connection.
///
/// Read from the source: the controllers are UIKit and are not built on
/// the machine the suite runs on.
final class QuietSaveTests: XCTestCase {

    /// Save takes his addresses and draws the rows again, and that is all:
    /// no sweep, no page, nothing on the connection. Drawing the rows
    /// again asks for nothing either: `regroup()` calls none of the hooks
    /// to the counts, and the container, told the rows were drawn again,
    /// hands the reading pane its new letters and nothing more.
    func testSettingsSaveAsksTheServerForNothing() throws {
        let onSaved = try savedHandler()
        XCTAssertTrue(onSaved.contains(
            "guard let self else { return } self.mine = OwnAddresses(account: saved) "
            + "self.regroup() }"))
        for fetch in ["onRefreshRequested", "refreshMailboxes", "refreshCounts", "requestSweep",
                      "onMessagesChanged", "countsCame", "reload(", "fetchOverKept",
                      "returnToNewest", "uploadWaiting", "repository", "Task"] {
            XCTAssertFalse(onSaved.contains(fetch), fetch)
        }

        let list = try source("UI/MessageListViewController.swift")
        let start = try XCTUnwrap(list.range(of: "private func regroup("))
        let end = try XCTUnwrap(list.range(of: "private func place() -> ListPlace {",
                                           range: start.upperBound..<list.endIndex))
        let regroup = list[start.upperBound..<end.lowerBound]
        for fetch in ["onRefreshRequested", "refreshMailboxes", "refreshCounts", "requestSweep",
                      "onMessagesChanged", "countsCame", "reload(", "repository", "Task"] {
            XCTAssertFalse(regroup.contains(fetch), "regroup: \(fetch)")
        }
        let root = try source("UI/RootViewController.swift")
        XCTAssertTrue(root.contains(
            "list.onRegrouped = { [weak self] in guard let self else { return } "
            + "self.detail.takeArrivals(from: self.list.conversations) }"))
    }

    /// The list calls `onRefreshRequested` in one place: his Refresh.
    func testOnlyHisRefreshCallsOnRefreshRequested() throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertEqual(count("onRefreshRequested?(", in: list), 1)
        let start = try XCTUnwrap(list.range(of: "@objc private func refreshTapped() {"))
        let end = try XCTUnwrap(list.range(of: "@objc private func editTapped()",
                                           range: start.upperBound..<list.endIndex))
        XCTAssertTrue(list[start.upperBound..<end.lowerBound]
            .contains("counts: { quietly in self.onRefreshRequested?(quietly) },"))
    }

    /// The list's other two ways to the counts are called where they were:
    /// `requestSweep` by Edit mode's Delete and Move, when a count may
    /// have changed that the list cannot work out (B-062), and by a drag's
    /// Flag and read mark, which go as Edit mode's batch does (B-156); and
    /// `onMessagesChanged` when a letter he opened is another one on the
    /// server now (D-016). Both sweeps are his.
    func testTheOtherWaysToTheCountsAreCalledWhereTheyWere() throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertEqual(count("requestSweep?()", in: list), 2)
        XCTAssertTrue(list.contains(
            "list: self.letters, repository: self.repository, "
            + "requestSweep: { [weak self] in self?.requestSweep?() })"))
        XCTAssertEqual(count("onMessagesChanged?()", in: list), 1)
        XCTAssertTrue(list.contains(
            "} catch is MailShelf.NotTheKeptLetter { "
            + "self.letters.readAnswered(m.id, landed: false) "
            + "PaneActions.notTheKeptLetter(m, list: self.letters) "
            + "self.onMessagesChanged?() return }"))
    }

    /// His Refresh still says when there is no connection: its page is not
    /// quiet, and puts up the alert when it fails. Its counts are not quiet
    /// after a page that came; after one that did not, the page's alert has
    /// said what failed, and they are asked for quietly (B-103).
    func testHisRefreshStillSaysWhenThereIsNoConnection() throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains("defer { checking?() } await self.repository.forgetLettersOfHis() "
                                    + "return await self.reload(passing: false) },"))
        let start = try XCTUnwrap(list.range(of: "func reload(keepingPlace: Bool = false, "
                                             + "quietly: Bool = false, passing: Bool = true) "
                                             + "async -> Bool {"))
        let end = try XCTUnwrap(list.range(of: "func placeVoiceOver()",
                                           range: start.upperBound..<list.endIndex))
        XCTAssertTrue(list[start.upperBound..<end.lowerBound].contains(
            "if !quietly { showWhenLetGo(error) } return false"))
        // Put up as it always was with no finger on the list, and as the
        // finger lets go with one (B-103).
        XCTAssertTrue(list.contains(
            "private func showWhenLetGo(_ error: Error) { "
            + "guard let now = afterLetGo.show(error, fingerDown: tableView.isTracking) else { "
            + "watchForLetGo() return } ErrorPresenter.show(reaching: now, on: self) }"))

        let root = try source("UI/RootViewController.swift")
        XCTAssertTrue(root.contains(
            "list.onRefreshRequested = { [weak self] quietly in "
            + "self?.refreshMailboxes(quietly: quietly) }"))
        XCTAssertTrue(try source("Mail/RefreshTap.swift").contains(
            "let came = (try? await page()) ?? false answered() counts(!came)"))
        XCTAssertTrue(root.contains(
            "private func refreshMailboxes(quietly: Bool = false) { "
            + "mailboxList.select(mailboxID: list.mailboxID) "
            + "mailboxList.refreshCounts(quietly: quietly) }"))

        let folders = try source("UI/MailboxListViewController.swift")
        XCTAssertTrue(folders.contains(
            "func refreshCounts(quietly: Bool = false) { sweeps.request(quietly: quietly) }"))
        XCTAssertTrue(folders.contains(
            "} catch { if !quietly { ErrorPresenter.show(reaching: error, on: self) } } }"))
    }

    /// A sweep asked for as his Refresh asks, with nothing said of
    /// quiet, is his: one that fails says so.
    @MainActor
    func testASweepAskedForAsHisRefreshAsksIsNotQuiet() async {
        var ran: [Bool] = []
        let sweeps = SweepCoalescer { quietly in ran.append(quietly) }
        sweeps.request()
        await sweeps.idle()
        XCTAssertEqual(ran, [false])
    }

    /// A new password goes the way it went: checked, saved, and the
    /// screens built again over a repository that signs in with it once
    /// the sheet has gone. Not by `onSaved`, which Settings calls in one
    /// place, a save with no new password.
    func testThePasswordPathIsAsItWas() throws {
        let settings = try source("UI/SettingsViewController.swift")
        XCTAssertTrue(settings.contains(
            "guard let password else { onSaved?(updated) dismiss(animated: true) return }"))
        XCTAssertEqual(count("onSaved?(", in: settings), 1)
        XCTAssertTrue(settings.contains(
            "let signIn = onPasswordSaved dismiss(animated: true) "
            + "{ signIn?(updated, password, notice) }"))
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains(
            "settings.onPasswordSaved = { [weak self] account, password, notice in "
            + "self?.onPasswordSaved?(account, password, notice) }"))
        let root = try source("UI/RootViewController.swift")
        XCTAssertTrue(root.contains(
            "list.onPasswordSaved = { [weak self] account, password, notice in "
            + "self?.signIn(as: account, password: password, saying: notice) }"))
    }

    // MARK: - Reading the source

    /// What Settings' Save runs in the list, up to the password's.
    private func savedHandler() throws -> String {
        let list = try source("UI/MessageListViewController.swift")
        let start = try XCTUnwrap(list.range(of: "settings.onSaved = { [weak self] saved in"))
        let end = try XCTUnwrap(list.range(of: "settings.onPasswordSaved",
                                           range: start.upperBound..<list.endIndex))
        return String(list[start.upperBound..<end.lowerBound])
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

    private func count(_ text: String, in code: String) -> Int {
        code.components(separatedBy: text).count - 1
    }
}
