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
        XCTAssertTrue(refresh.contains("if fromPull, !pullAllowed { pull.endRefreshing() return }"),
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
            + "defer { checking?() } return await self.reload(passing: false) },"), refresh)
    }

    /// The spinner is put away as the page answers, as the list goes out of
    /// sight, as the app goes to the background, as another folder's list
    /// takes this one's place, and before the pull is taken off the list.
    func testTheSpinnerIsPutAwayWhereverItCouldBeLeftTurning() throws {
        let list = try list()
        let refresh = body(after: "private func refresh(fromPull: Bool)", in: list)
        XCTAssertTrue(refresh.contains("answered: { self.pull.endRefreshing() },"), refresh)

        XCTAssertTrue(body(after: "override func viewWillDisappear(_ animated: Bool)", in: list)
            .contains("super.viewWillDisappear(animated) pull.endRefreshing()"))

        XCTAssertTrue(list.contains(
            "NotificationCenter.default.addObserver(self, selector: #selector(wentToBackground), "
            + "name: UIApplication.didEnterBackgroundNotification, object: nil)"))
        XCTAssertEqual(body(after: "@objc private func wentToBackground()", in: list),
                       "{ pull.endRefreshing() }")

        XCTAssertEqual(body(after: "func endPull()", in: list), "{ pull.endRefreshing() }")
        let root = try source("UI/RootViewController.swift")
        let opening = body(after: "private func openMailbox(_ mailbox: Mailbox)", in: root)
        inOrder("list.endPull()", "list = MessageListViewController(", in: opening)

        // Taken off in one place, its spinner put away first.
        let placing = body(after: "private func placePull()", in: list)
        XCTAssertTrue(placing.contains(
            "guard isViewLoaded else { return } "
            + "let offered: UIRefreshControl? = pullAllowed ? pull : nil "
            + "guard tableView.refreshControl !== offered else { return } "
            + "if offered == nil { pull.endRefreshing() } "
            + "tableView.refreshControl = offered"), placing)
        for (path, code) in try everySource() {
            XCTAssertEqual(count("refreshControl =", in: code),
                           path == "UI/MessageListViewController.swift" ? 1 : 0, path)
        }
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

    /// The newest page sent to the top under a finger that holds the list at
    /// its top, or pulled down past it, leaves it where the finger has it: it
    /// springs back to the top as he lets go. Set there under the finger,
    /// the rows would jump.
    func testTheTopIsNotSetUnderAFingerThatHoldsTheListThere() throws {
        let top = body(after: "private func scrollToTop()", in: try list())
        XCTAssertEqual(top,
                       "{ tableView.layoutIfNeeded() guard !(tableView.isTracking "
                       + "&& ListPlaces.isAtTop(offset: Double(tableView.contentOffset.y), "
                       + "topInset: Double(tableView.adjustedContentInset.top))) else { return } "
                       + "tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), "
                       + "animated: false) }")
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
        XCTAssertEqual(didScroll, "{ landFreshPage() showNewsIfAtTop() }")
    }
}
