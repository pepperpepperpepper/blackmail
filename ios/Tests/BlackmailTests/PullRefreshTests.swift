import XCTest
@testable import Blackmail

/// The pull down past the top of the message list, which checks for mail as
/// Mail's does (B-103): where it is offered, and its wiring in the list,
/// read from the source as `RefreshTapTests` reads it, the list being UIKit,
/// which never builds on this host. One page at a time, and the page's
/// answer before the counts and the pass, are `RefreshTapTests`'. With the
/// status bar's tap to the top, which was there already and is pinned here.
final class PullRefreshTests: XCTestCase {

    // MARK: - Where it is offered

    /// Every one of the sixteen: offered only on a list from the folder's
    /// newest letters, out of Edit mode, with no search typed, shown or in
    /// hand, and the panes still.
    func testWhereThePullIsOffered() {
        for editing in [false, true] {
            for searching in [false, true] {
                for fromNewest in [false, true] {
                    for moving in [false, true] {
                        let allowed = PullRefresh.allowed(editing: editing, searching: searching,
                                                          fromNewest: fromNewest, moving: moving)
                        XCTAssertEqual(allowed, !editing && !searching && fromNewest && !moving,
                                       "editing \(editing), searching \(searching), "
                                       + "from the newest \(fromNewest), moving \(moving)")
                    }
                }
            }
        }
        XCTAssertTrue(PullRefresh.allowed(editing: false, searching: false, fromNewest: true,
                                          moving: false))
    }

    /// The words on the line while the page is out are Mail's, and the ones
    /// the line has said over the kept page since D-016: one string for both.
    func testTheLineSaysCheckingForMail() throws {
        XCTAssertEqual(StatusLine.checking, "Checking for Mail…")
        let line = try source("Mail/MailWatch.swift")
        XCTAssertTrue(line.contains("let lines = [age ?? (failure == nil ? StatusLine.checking : nil),"))
        XCTAssertEqual(count("Checking for Mail", in: try source("Mail/MailWatch.swift")), 0)
        XCTAssertEqual(count("Checking for Mail", in: try list()), 0)
    }

    // MARK: - The wiring, read from the source

    /// A file of the app's sources, comment lines dropped and whitespace
    /// run together.
    private func source(_ path: String) throws -> String {
        try String(contentsOf: sources.appendingPathComponent(path), encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    private var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail")
    }

    private func list() throws -> String { try source("UI/MessageListViewController.swift") }

    /// Every Swift file under `Sources/Blackmail`, as `source` reads it.
    private func everySource() throws -> [(String, String)] {
        let base = sources.path
        guard let walk = FileManager.default.enumerator(atPath: base) else { return [] }
        var files: [(String, String)] = []
        for case let path as String in walk where path.hasSuffix(".swift") {
            files.append((path, try source(path)))
        }
        XCTAssertGreaterThan(files.count, 50)
        return files
    }

    private func count(_ text: String, in code: String) -> Int {
        code.components(separatedBy: text).count - 1
    }

    /// The braces after the first `opener` in `code`, and everything in
    /// them: a function's body, or a closure's.
    private func body(after opener: String, in code: String,
                      file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let start = code.range(of: opener),
              let brace = code[start.upperBound...].firstIndex(of: "{") else {
            XCTFail("no \(opener)", file: file, line: line)
            return ""
        }
        var depth = 0
        var i = brace
        while i < code.endIndex {
            if code[i] == "{" { depth += 1 }
            if code[i] == "}" {
                depth -= 1
                if depth == 0 { return String(code[brace...i]) }
            }
            i = code.index(after: i)
        }
        XCTFail("\(opener) never closes", file: file, line: line)
        return ""
    }

    /// Whether `first` comes before `then` in `code`, both there.
    private func inOrder(_ first: String, _ then: String, in code: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        guard let a = code.range(of: first), let b = code.range(of: then) else {
            XCTFail("\(first) or \(then) missing", file: file, line: line)
            return
        }
        XCTAssertLessThan(a.lowerBound, b.lowerBound, "\(first) before \(then)",
                          file: file, line: line)
    }

    /// The list has one pull, grey and with no words, whose let-go comes to
    /// the same Refresh as the button's, and the Refresh button is in the
    /// bottom bar where it was (D-009). One Refresh, started in one place,
    /// through the gate; nothing starts the spinner but his pull.
    func testThePullAndTheButtonAreOneRefresh() throws {
        let list = try list()
        XCTAssertEqual(count("UIRefreshControl()", in: list), 1)
        XCTAssertTrue(list.contains("private let pull = UIRefreshControl()"))
        XCTAssertTrue(list.contains("pull.tintColor = Theme.secondaryText"))
        XCTAssertTrue(list.contains("pull.addTarget(self, action: #selector(pulled), for: .valueChanged)"))
        XCTAssertFalse(list.contains("pull.attributedTitle"), "no words under the spinner")
        XCTAssertEqual(count("#selector(pulled)", in: list), 1)
        XCTAssertEqual(count("#selector(refreshTapped)", in: list), 1)
        XCTAssertEqual(body(after: "@objc private func pulled()", in: list),
                       "{ refresh(fromPull: true) }")
        XCTAssertEqual(body(after: "@objc private func refreshTapped()", in: list),
                       "{ refresh(fromPull: false) }")

        let refresh = body(after: "private func refresh(fromPull: Bool)", in: list)
        XCTAssertTrue(refresh.contains("if fromPull, !pullAllowed { putPullAway() return }"),
                      "a pull where none is offered starts nothing")
        XCTAssertTrue(refresh.contains("RefreshTap.start( gate: refreshes, "), refresh)
        XCTAssertTrue(list.contains("private let refreshes = RefreshTap.Gate()"))
        XCTAssertEqual(count("RefreshTap.start(", in: list), 1)
        XCTAssertEqual(count("RefreshTap.run(", in: list), 0)
        XCTAssertEqual(count("reload(passing: false)", in: list), 1)

        // The button, as it was.
        XCTAssertTrue(list.contains(
            "let refresh = UIBarButtonItem(title: \"Refresh\", style: .plain, "
            + "target: self, action: #selector(refreshTapped))"))
        XCTAssertTrue(list.contains("browseItems = [refresh, flex, status, flex, mirror]"))
        XCTAssertTrue(list.contains("toolbarItems = browseItems"))

        // UIKit starts the spinner at his pull, and nothing else does. No
        // other screen has a pull: not the Mailboxes, not the letter.
        for (path, code) in try everySource() {
            XCTAssertFalse(code.contains("beginRefreshing"), path)
            if path != "UI/MessageListViewController.swift" {
                XCTAssertFalse(code.contains("UIRefreshControl"), path)
            }
        }
    }

    /// "Checking for Mail…" through `working`, from the page's start to its
    /// end, by a `defer`, so it cannot outstay it; not in the Outbox.
    func testTheLineSaysCheckingWhileThePageIsOut() throws {
        let refresh = body(after: "private func refresh(fromPull: Bool)", in: try list())
        XCTAssertTrue(refresh.contains(
            "page: { let checking = self.isOutbox ? nil : self.working(StatusLine.checking) "
            + "defer { checking?() } await self.repository.forgetLettersOfHis() "
            + "return await self.reload(passing: false) },"), refresh)
    }

    /// The spinner is put away from the page's answer (`endPullAtRest`), and
    /// at once, with nothing left held for the list's rest, as the list goes
    /// out of sight, as the app goes to the background, as another folder's
    /// list takes this one's place, and before the pull is taken off the
    /// list: Edit mode, a search, a day's list and the panes' motion.
    func testTheSpinnerIsPutAwayWhereverItCouldBeLeftTurning() throws {
        let list = try list()
        let refresh = body(after: "private func refresh(fromPull: Bool)", in: list)
        XCTAssertTrue(refresh.contains("answered: { self.endPullAtRest() },"), refresh)

        XCTAssertEqual(body(after: "private func putPullAway()", in: list),
                       "{ pullEnd.putAway() pull.endRefreshing() }")
        XCTAssertEqual(body(after: "override func viewWillDisappear(_ animated: Bool)", in: list),
                       "{ super.viewWillDisappear(animated) putPullAway() dropHeldAlert() }")

        XCTAssertTrue(list.contains(
            "NotificationCenter.default.addObserver(self, selector: #selector(wentToBackground), "
            + "name: UIApplication.didEnterBackgroundNotification, object: nil)"))
        XCTAssertEqual(body(after: "@objc private func wentToBackground()", in: list),
                       "{ putPullAway() }")

        XCTAssertEqual(body(after: "func endPull()", in: list), "{ putPullAway() }")
        let root = try source("UI/RootViewController.swift")
        let opening = body(after: "private func openMailbox(_ mailbox: Mailbox)", in: root)
        inOrder("list.endPull()", "list = MessageListViewController(", in: opening)

        // Taken off in one place, its spinner put away first.
        let placing = body(after: "private func placePull()", in: list)
        XCTAssertTrue(placing.contains(
            "guard isViewLoaded else { return } "
            + "let offered: UIRefreshControl? = pullAllowed ? pull : nil "
            + "guard tableView.refreshControl !== offered else { return } "
            + "if offered == nil { putPullAway() } "
            + "tableView.refreshControl = offered"), placing)
        for (path, code) in try everySource() {
            XCTAssertEqual(count("refreshControl =", in: code),
                           path == "UI/MessageListViewController.swift" ? 1 : 0, path)
        }

        // The spinner put away in four places only: the answer's, the
        // bound's, the rest's and at once. Every other way to it is `putPullAway`, which
        // leaves nothing held: the refusal, the pull taken off, the folder,
        // out of sight and the background.
        XCTAssertEqual(count("pull.endRefreshing()", in: list), 4)
        XCTAssertEqual(count("pull.endRefreshing()",
                             in: body(after: "private func endPullAtRest()", in: list)), 1)
        XCTAssertEqual(count("pull.endRefreshing()",
                             in: body(after: "private func putAwayAtBound(_ hold: Int, round: Int)",
                                      in: list)), 1)
        XCTAssertEqual(count("pull.endRefreshing()",
                             in: body(after: "private func pullSettled()", in: list)), 1)
        XCTAssertEqual(count("putPullAway()", in: list), 6, "five ways, and itself")
    }

    /// The page's answer puts the spinner away at once under a finger on
    /// the list or with the list still, and otherwise holds it for the
    /// list's rest, put away after `PullEnd.bound` if UIKit never says so:
    /// at the bound with a finger on it or the list still, and with the
    /// list still moving, after one more bound, the last. What each asks is
    /// the list as it is then: the spinner, the finger, coasting or
    /// springing back, and the offset against the room above the first row,
    /// the spinner's included.
    func testThePagesAnswerPutsTheSpinnerAwayOnlyWithTheListAtRest() throws {
        let list = try list()
        XCTAssertEqual(body(after: "private func endPullAtRest()", in: list),
                       "{ switch pullEnd.answered(spinning: pull.isRefreshing, "
                       + "fingerDown: tableView.isTracking, moving: listMoving) { "
                       + "case .now: pull.endRefreshing() "
                       + "case .held(let hold): putAwayAtBound(hold, round: 1) } }")
        XCTAssertEqual(body(after: "private func putAwayAtBound(_ hold: Int, round: Int)", in: list),
                       "{ Task { @MainActor [weak self] in "
                       + "try? await Task.sleep(for: .seconds(PullEnd.bound)) "
                       + "guard let self else { return } "
                       + "switch self.pullEnd.due(hold, round: round, "
                       + "fingerDown: self.tableView.isTracking, moving: self.listMoving) { "
                       + "case .gone: return "
                       + "case .now: self.pull.endRefreshing() "
                       + "case .again: self.putAwayAtBound(hold, round: round + 1) } } }")
        XCTAssertEqual(body(after: "private var listMoving: Bool", in: list),
                       "{ PullEnd.moving(decelerating: tableView.isDecelerating, "
                       + "offset: Double(tableView.contentOffset.y), "
                       + "topInset: Double(tableView.adjustedContentInset.top)) }")
        XCTAssertEqual(count("putAwayAtBound(", in: list), 3, "the answer, again, and itself")
        XCTAssertTrue(list.contains("private var pullEnd = PullEnd()"))
    }

    /// A spinner held for the list's rest goes as UIKit says it is at rest:
    /// at the end of its coasting or spring-back, at the end of an animated
    /// scroll, at the end of a drag with none to come, at the status bar's
    /// tap to the top; and as a finger
    /// takes the list, under the finger. Never at the end of a drag that
    /// springs back or coasts on, where it was seen to leave the gap.
    func testAHeldSpinnerGoesAtRestOrUnderAFinger() throws {
        let list = try list()
        XCTAssertEqual(body(after: "private func pullSettled()", in: list),
                       "{ guard pullEnd.settled() else { return } pull.endRefreshing() }")
        XCTAssertEqual(body(after: "override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView)",
                            in: list),
                       "{ closeUpPastTop() pullSettled() showHeldAlert() landFreshPage() "
                       + "showNewsIfAtTop() }")
        XCTAssertEqual(body(after: "override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView)",
                            in: list),
                       "{ closeUpPastTop() pullSettled() }")
        XCTAssertEqual(body(after: "override func scrollViewDidEndDragging(_ scrollView: UIScrollView, "
                                   + "willDecelerate decelerate: Bool)", in: list),
                       "{ showHeldAlert() guard !decelerate else { return } "
                       + "pullSettled() landFreshPage() showNewsIfAtTop() }")
        XCTAssertEqual(body(after: "override func scrollViewWillBeginDragging(_ scrollView: UIScrollView)",
                            in: list),
                       "{ pullSettled() }")
        XCTAssertEqual(count("pullSettled()", in: list), 6, "five ways, and itself")
    }

    /// A page he asked for that fails puts its alert up at once with no
    /// finger on the list, and otherwise as the finger lets go: at the end
    /// of the drag, before the list springs back, or, for a finger that
    /// never dragged, once it is seen to have lifted. Dropped as the list
    /// goes out of sight. A quiet page still puts up none.
    func testAPagesAlertWaitsForTheFingerToLetGo() throws {
        let list = try list()
        let reload = body(after: "func reload(keepingPlace: Bool = false, quietly: Bool = false, "
                                 + "passing: Bool = true) async -> Bool", in: list)
        XCTAssertTrue(reload.contains("if !quietly { showWhenLetGo(error) } return false"), reload)
        XCTAssertFalse(reload.contains("ErrorPresenter"), reload)

        XCTAssertTrue(list.contains("private var afterLetGo = LetGoHold<Error>()"))
        XCTAssertEqual(body(after: "private func showWhenLetGo(_ error: Error)", in: list),
                       "{ guard let now = afterLetGo.show(error, fingerDown: tableView.isTracking) else { "
                       + "watchForLetGo() return } "
                       + "ErrorPresenter.show(reaching: now, on: self) }")
        XCTAssertEqual(body(after: "private func showHeldAlert()", in: list),
                       "{ stopWatchingForLetGo() guard let held = afterLetGo.letGo() else { return } "
                       + "ErrorPresenter.show(reaching: held, on: self) }")
        XCTAssertEqual(body(after: "private func dropHeldAlert()", in: list),
                       "{ stopWatchingForLetGo() afterLetGo.drop() }")
        XCTAssertEqual(body(after: "private func watchForLetGo()", in: list),
                       "{ guard letGoWatch == nil else { return } "
                       + "letGoWatch = Task { @MainActor [weak self] in while !Task.isCancelled { "
                       + "try? await Task.sleep(for: Self.liftCheck) "
                       + "guard let self, !Task.isCancelled else { return } "
                       + "if !self.tableView.isTracking { self.showHeldAlert() return } } } }")
        XCTAssertEqual(body(after: "private func stopWatchingForLetGo()", in: list),
                       "{ letGoWatch?.cancel() letGoWatch = nil }")

        // As the finger lets go, and wherever it is surely off the list.
        let dragged = body(after: "override func scrollViewDidEndDragging(_ scrollView: UIScrollView, "
                                  + "willDecelerate decelerate: Bool)", in: list)
        inOrder("showHeldAlert()", "guard !decelerate else { return }", in: dragged)
        XCTAssertEqual(count("showHeldAlert()", in: list), 5,
                       "the drag's end, the rest, the status bar, the watch, and itself")
        XCTAssertEqual(count("dropHeldAlert()", in: list), 2, "out of sight, and itself")
    }

    /// The pull is taken off, and put back, wherever one of the four things
    /// `PullRefresh` asks may have changed: Edit mode, at the tap of Edit or
    /// Done; a search, as words are typed, the field takes or gives up the
    /// keyboard, results come or go; a day's list, as it lands, and as the
    /// newest page is reached from it or fetched; and the panes' motion, as
    /// it starts and ends. Each from the list as it is then.
    func testThePullIsTakenOffWhereItWouldMoveHimOrWipeAnything() throws {
        let list = try list()
        XCTAssertTrue(body(after: "private var pullAllowed: Bool", in: list).contains(
            "PullRefresh.allowed(editing: tableView.isEditing, "
            + "searching: isSearchingOrTyping || searchBar.isExpanded, "
            + "fromNewest: reachedNewestMessage, moving: panesMoving)"))

        let edit = body(after: "@objc private func editTapped()", in: list)
        inOrder("tableView.setEditing(editing, animated: true)", "placePull()", in: edit)

        XCTAssertTrue(body(after: "private func queryChanged(_ text: String)", in: list)
            .contains("searchQuery = text searchDebounce?.cancel() placePull()"))
        XCTAssertTrue(body(after: "searchBar.onHeightChanged = ", in: list).contains("self.placePull()"))
        let search = body(after: "private func runSearch(_ text: String) async", in: list)
        XCTAssertEqual(count("placePull()", in: search), 2, "results, and a search that failed")
        XCTAssertTrue(body(after: "private func showUnfilteredList()", in: list).contains("placePull()"))

        // Every place the list's top changes.
        XCTAssertEqual(count("reachedNewestMessage = ", in: list), 4)
        XCTAssertTrue(list.contains("private var reachedNewestMessage = true"))
        inOrder("reachedNewestMessage = window.reachedNewest", "placePull()",
                in: body(after: "private func show(_ window: MessageWindow)", in: list))
        let reload = body(after: "func reload(keepingPlace: Bool = false, quietly: Bool = false, "
                                 + "passing: Bool = true) async -> Bool", in: list)
        XCTAssertTrue(reload.contains("reachedNewestMessage = true placePull()"), reload)
        XCTAssertTrue(reload.contains("pagePreviews = loadPreviews(for: unpreviewed) placePull()"),
                      reload)
        XCTAssertTrue(body(after: "private func loadPreviousPage()", in: list).contains(
            "if newer.count < Self.pageSize { self.reachedNewestMessage = true self.placePull() }"))

        // The motion.
        XCTAssertTrue(list.contains(
            "var panesMoving = false { didSet { guard panesMoving != oldValue else { return } "
            + "placePull() } }"))
        let root = try source("UI/RootViewController.swift")
        XCTAssertTrue(root.contains(
            "motion.onMoving = { [weak self] moving in self?.list.panesMoving = moving }"))
        let motion = try source("UI/PaneMotion.swift")
        let playing = body(after: "func play(_ cut: Cut)", in: motion)
        XCTAssertTrue(playing.hasSuffix("CATransaction.commit() onMoving?(true) }"), playing)
        XCTAssertTrue(body(after: "func finish() -> Bool", in: motion).contains(
            "self.cover = nil cover.removeFromSuperview() onMoving?(false) return true"))
        XCTAssertEqual(count("onMoving?(", in: motion), 2)

        // Put on as the list is first drawn.
        XCTAssertTrue(body(after: "override func viewDidLoad()", in: list).contains(
            "pull.addTarget(self, action: #selector(pulled), for: .valueChanged) placePull()"))
    }

    /// The newest page sent to the top leaves a list pulled down past it
    /// where it is while a finger holds it or it springs back: held, it
    /// springs back to the top as he lets go, and springing back, it gets
    /// there itself. Set to the top as it sprang back, it stopped at the
    /// spinner's rest, and the spinner put away there left the list 60 pt
    /// below its top on the iPad. Left at rest past its top, as that band
    /// was, it goes to the top, as a list further down does; at the top
    /// there is nothing to set (`ListPlaces.setsTop`, in `PullEndTests`).
    /// Moving is a finger on it, or its coasting or spring-back.
    func testAListPastItsTopIsLeftWhereItIsOnlyWhileItMoves() throws {
        let top = body(after: "private func scrollToTop()", in: try list())
        XCTAssertEqual(top,
                       "{ tableView.layoutIfNeeded() "
                       + "guard ListPlaces.setsTop(offset: Double(tableView.contentOffset.y), "
                       + "topInset: Double(tableView.adjustedContentInset.top), "
                       + "moving: tableView.isTracking || tableView.isDecelerating) else { return } "
                       + "tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), "
                       + "animated: false) }")
        XCTAssertTrue(ListPlaces.setsTop(offset: -134, topInset: 74, moving: false), "the band")
        XCTAssertFalse(ListPlaces.setsTop(offset: -134, topInset: 74, moving: true), "springing back")
        XCTAssertFalse(ListPlaces.setsTop(offset: -74, topInset: 74, moving: false), "at the top")
        XCTAssertTrue(ListPlaces.setsTop(offset: 200, topInset: 74, moving: true), "far down")
    }

    /// A list come to rest past its top with no spinner turning and no
    /// finger on it, the band the iPad showed, closes up to its top,
    /// animated as a spring-back: at the end of a coasting or spring-back,
    /// and of an animated scroll, each time before a spinner held for the
    /// rest is put away, which UIKit takes to the top itself. What it asks
    /// is the list as it is then (`PullEnd.leftPastTop`, in `PullEndTests`).
    /// A spinner put away at once can still end mid-spring-back: Edit, the
    /// search field, Home, the list leaving the screen, a bound gone by.
    func testABandLeftAtRestClosesUp() throws {
        let list = try list()
        XCTAssertEqual(body(after: "private func closeUpPastTop()", in: list),
                       "{ guard PullEnd.leftPastTop(spinning: pull.isRefreshing, "
                       + "fingerDown: tableView.isTracking, "
                       + "offset: Double(tableView.contentOffset.y), "
                       + "topInset: Double(tableView.adjustedContentInset.top)) else { return } "
                       + "tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), "
                       + "animated: true) }")
        for rest in ["override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView)",
                     "override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView)"] {
            inOrder("closeUpPastTop()", "pullSettled()", in: body(after: rest, in: list))
        }
        XCTAssertEqual(count("closeUpPastTop()", in: list), 3, "two rests, and itself")
        XCTAssertEqual(count("animated: true)", in: body(after: "private func scrollToTop()", in: list)), 0)
    }

    // MARK: - The status bar

    /// A tap on the status bar takes the list to its top, as it does Mail's,
    /// with no code of the app's: UIKit's scroll to top. Nothing turns it
    /// off, and at the top the list does what it does whenever it comes to
    /// rest there: a fresh page waiting over the kept one lands, and mail
    /// held below the top goes on.
    func testTheStatusBarTapStillTakesTheListToItsTop() throws {
        for (path, code) in try everySource() {
            XCTAssertFalse(code.contains("scrollsToTop = false"), path)
            XCTAssertFalse(code.contains("scrollsToTop=false"), path)
            var rest = Substring(code)
            while let found = rest.range(of: "func scrollViewShouldScrollToTop(") {
                let after = String(rest[found.lowerBound...])
                XCTAssertFalse(body(after: "func scrollViewShouldScrollToTop(", in: after)
                    .contains("false"), path)
                rest = rest[found.upperBound...]
            }
        }
        let didScroll = body(after: "override func scrollViewDidScrollToTop(_ scrollView: UIScrollView)",
                             in: try list())
        XCTAssertEqual(didScroll, "{ pullSettled() showHeldAlert() landFreshPage() showNewsIfAtTop() }")
    }
}
