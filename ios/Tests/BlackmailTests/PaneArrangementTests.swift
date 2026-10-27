import XCTest
@testable import Blackmail

/// Two panes or three (D-015, B-048): the choice and where it is kept, the
/// widths of each arrangement, what is on screen after each thing he can
/// do, and which of those things opens a folder, by value and over the
/// scripted server. The container that lays the panes out is UIKit and
/// never runs on this host: it hands `PaneShell` what only it can do, and
/// its source is read to check that it does as it is told.
final class PaneArrangementTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "PaneArrangementTests"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "blackmail.panes")
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        super.tearDown()
    }

    private let inbox = Mailbox(id: "INBOX", name: "INBOX", unreadCount: 6, role: .inbox)
    private let sent = Mailbox(id: "[Gmail]/Sent Mail", name: "Sent Mail", unreadCount: 0,
                               role: .sent, depth: 1)
    private let receipts = Mailbox(id: "INBOX/Receipts", name: "Receipts", unreadCount: 0,
                                   role: nil, depth: 1)

    // MARK: - The choice, kept

    func testThreePanesUntilHeChoosesTwo() {
        UserDefaults.standard.removeObject(forKey: "blackmail.panes")
        XCTAssertEqual(PaneArrangement.key, "blackmail.panes")
        XCTAssertEqual(PaneArrangement.saved, .three)
        XCTAssertEqual(PaneArrangement(launching: PaneArrangement.saved).panes, .three)
    }

    func testTheChoiceIsKeptForTheNextLaunch() {
        PaneArrangement.saved = .two
        XCTAssertEqual(UserDefaults.standard.object(forKey: "blackmail.panes") as? String, "two")
        XCTAssertEqual(PaneArrangement.saved, .two)
        XCTAssertEqual(PaneArrangement(launching: PaneArrangement.saved).panes, .two)
        PaneArrangement.saved = .three
        XCTAssertEqual(PaneArrangement.saved, .three)
    }

    /// Anything but the two words is three panes, so an update, or a value
    /// written under the key by something else, never opens him in an
    /// arrangement he did not choose.
    func testAnythingElseUnderTheKeyIsThreePanes() {
        for stored: Any in ["Two", "2", "", true, 2] {
            UserDefaults.standard.set(stored, forKey: "blackmail.panes")
            XCTAssertEqual(PaneArrangement.saved, .three, "\(stored)")
        }
    }

    // MARK: - Widths

    /// D-009's three, unchanged: 20.9% / 27.6% / the rest.
    func testThreePanesAreD009sWidths() {
        XCTAssertEqual(PaneArrangement.columns(.three, screenWidth: 1194),
                       .init(mailboxes: 250, list: 330, message: 613))
        XCTAssertEqual(PaneArrangement.columns(.three, screenWidth: 1366),
                       .init(mailboxes: 285, list: 377, message: 703))
    }

    /// D-003's two: a 375 pt left column on either iPad, which the
    /// Mailboxes and the list take turns in, and the message the rest. On
    /// the 12.9-inch the list is within 2 pt of its three-pane width, so the
    /// switch adds and takes away the Mailboxes column and little else, as
    /// iOS 10's did.
    func testTwoPanesAreA375PointColumnAndTheMessage() {
        XCTAssertEqual(PaneArrangement.columns(.two, screenWidth: 1194),
                       .init(mailboxes: 375, list: 375, message: 818.5))
        XCTAssertEqual(PaneArrangement.columns(.two, screenWidth: 1366),
                       .init(mailboxes: 375, list: 375, message: 990.5))
        let three = PaneArrangement.columns(.three, screenWidth: 1366)
        XCTAssertEqual(abs(three.list - 375), 2)
    }

    /// Every point of the screen is a pane or a divider, in both, on every
    /// landscape iPad this could be on; and no pane is ever zero wide, the
    /// one not in front being hidden instead (B-027).
    func testTheColumnsFillTheScreen() {
        for w: CGFloat in [1024, 1080, 1112, 1133, 1180, 1194, 1210, 1366, 1376] {
            let three = PaneArrangement.columns(.three, screenWidth: w)
            XCTAssertEqual(three.mailboxes + three.list + three.message + 1.0, w, "\(w)")
            let two = PaneArrangement.columns(.two, screenWidth: w)
            XCTAssertEqual(two.list, two.mailboxes, "\(w)")
            XCTAssertEqual(two.list + two.message + 0.5, w, "\(w)")
            for columns in [three, two] {
                XCTAssertGreaterThan(min(columns.mailboxes, columns.list, columns.message),
                                     200, "\(w)")
            }
            // Two panes give the letter more room than three, everywhere.
            XCTAssertGreaterThan(two.message, three.message, "\(w)")
        }
    }

    // MARK: - What the left column shows

    /// The list beside the Mailboxes' divider, the divider there, and
    /// nothing before the list's calendar: the corner is the Mailboxes'.
    func testLaunchingInThreePanes() {
        let panes = PaneArrangement(launching: .three)
        XCTAssertEqual(panes.leftColumn, .mailboxes)
        XCTAssertTrue(panes.mailboxesOnScreen)
        XCTAssertTrue(panes.listOnScreen)
        XCTAssertFalse(panes.listAtScreenEdge)
        XCTAssertTrue(panes.mailboxDividerOnScreen)
        XCTAssertEqual(panes.itemsBeforeCalendar, [])
    }

    /// In two panes the app opens into the Inbox's list, at the screen's
    /// edge with no divider before it, and the folders behind
    /// "< Mailboxes", as iOS 10 Mail did. The view button comes first in the
    /// list's bar, in the corner, then "< Mailboxes", then the calendar.
    func testLaunchingInTwoPanesShowsTheList() {
        let panes = PaneArrangement(launching: .two)
        XCTAssertEqual(panes.leftColumn, .list)
        XCTAssertFalse(panes.mailboxesOnScreen)
        XCTAssertTrue(panes.listOnScreen)
        XCTAssertTrue(panes.listAtScreenEdge)
        XCTAssertFalse(panes.mailboxDividerOnScreen)
        XCTAssertEqual(panes.itemsBeforeCalendar, [.viewButton, .back])
    }

    /// From three to two, the list he was reading stays on screen, now in
    /// the left column, with "< Mailboxes" over it.
    func testSwitchingToTwoKeepsTheListOnScreen() {
        var panes = PaneArrangement(launching: .three)
        panes.switchPanes()
        XCTAssertEqual(panes.panes, .two)
        XCTAssertEqual(panes.leftColumn, .list)
        XCTAssertTrue(panes.listOnScreen)
        XCTAssertEqual(panes.itemsBeforeCalendar, [.viewButton, .back])
    }

    /// From two to three with the folders in front, the open folder's list
    /// goes back in the middle; with the list in front, the folders come
    /// back on the left.
    func testSwitchingToThreeShowsBothWhicheverWasInFront() {
        var fromFolders = PaneArrangement(launching: .two)
        fromFolders.back()
        XCTAssertEqual(fromFolders.leftColumn, .mailboxes)
        XCTAssertFalse(fromFolders.listOnScreen)
        fromFolders.switchPanes()
        XCTAssertEqual(fromFolders.panes, .three)
        XCTAssertTrue(fromFolders.listOnScreen)
        XCTAssertTrue(fromFolders.mailboxesOnScreen)
        XCTAssertEqual(fromFolders.leftColumn, .mailboxes)
        XCTAssertFalse(fromFolders.listAtScreenEdge)
        XCTAssertTrue(fromFolders.mailboxDividerOnScreen)
        XCTAssertEqual(fromFolders.itemsBeforeCalendar, [])

        var fromList = PaneArrangement(launching: .two)
        fromList.switchPanes()
        XCTAssertEqual(fromList.panes, .three)
        XCTAssertTrue(fromList.listOnScreen)
        XCTAssertTrue(fromList.mailboxesOnScreen)

        // And back to two lands on the list, not on the folders he had in
        // front before the switch.
        fromFolders.switchPanes()
        XCTAssertEqual(fromFolders.leftColumn, .list)
        XCTAssertTrue(fromFolders.listOnScreen)
    }

    func testBackShowsTheFoldersInTwoPanesAndIsNothingInThree() {
        var two = PaneArrangement(launching: .two)
        two.back()
        XCTAssertEqual(two.leftColumn, .mailboxes)
        XCTAssertTrue(two.mailboxesOnScreen)
        XCTAssertFalse(two.listOnScreen)

        var three = PaneArrangement(launching: .three)
        three.back()
        XCTAssertEqual(three, PaneArrangement(launching: .three))
        XCTAssertTrue(three.listOnScreen)
    }

    /// Another folder opens as a tap in the three-pane sidebar opens it,
    /// and its list comes in front.
    func testTappingAnotherFolderInTwoPanesOpensIt() {
        var panes = PaneArrangement(launching: .two)
        panes.back()
        XCTAssertEqual(panes.tapped(sent, showing: inbox), .open)
        XCTAssertEqual(panes.leftColumn, .list)
        XCTAssertEqual(panes.itemsBeforeCalendar, [.viewButton, .back])
    }

    /// The folder already open brings back the list he left, and opens
    /// nothing: no new list, no fetch, the search and his place in it kept.
    func testTappingTheOpenFolderInTwoPanesGoesBackToItsList() {
        var panes = PaneArrangement(launching: .two)
        panes.back()
        XCTAssertEqual(panes.tapped(sent, showing: sent), .showList)
        XCTAssertEqual(panes.leftColumn, .list)

        // The Inbox the list opens on at launch is named by its role until
        // LIST has been heard from; the row he taps is the listed one.
        panes.back()
        XCTAssertEqual(panes.tapped(inbox, showing: .inboxBeforeListing), .showList)
        panes.back()
        XCTAssertEqual(panes.tapped(inbox, showing: inbox), .showList)
        // A folder filed under the Inbox is not the Inbox.
        panes.back()
        XCTAssertEqual(panes.tapped(receipts, showing: .inboxBeforeListing), .open)
        XCTAssertEqual(panes.tapped(receipts, showing: inbox), .open)
    }

    /// In three panes every tap opens, the open folder's included, which is
    /// how he fetches it again from the top there, as he always could.
    func testEveryTapOpensInThreePanes() {
        var panes = PaneArrangement(launching: .three)
        XCTAssertEqual(panes.tapped(sent, showing: inbox), .open)
        XCTAssertEqual(panes.tapped(inbox, showing: inbox), .open)
        XCTAssertEqual(panes.tapped(inbox, showing: .inboxBeforeListing), .open)
        XCTAssertEqual(panes, PaneArrangement(launching: .three))
    }

    /// Back after a while away lands him in the Inbox's list, in front, and
    /// leaves two panes two (B-037: a return must not undo the switch).
    func testComingBackShowsTheListAndKeepsTwoPanes() {
        var panes = PaneArrangement(launching: .two)
        panes.back()
        panes.showList()
        XCTAssertEqual(panes.panes, .two)
        XCTAssertEqual(panes.leftColumn, .list)

        var three = PaneArrangement(launching: .three)
        three.showList()
        XCTAssertEqual(three, PaneArrangement(launching: .three))
    }

    func testVoiceOverSaysWhatTheViewButtonWillDo() {
        var panes = PaneArrangement(launching: .three)
        XCTAssertEqual(panes.viewButtonLabel, "Hide Mailboxes")
        panes.switchPanes()
        XCTAssertEqual(panes.viewButtonLabel, "Show Mailboxes")
        panes.back()
        XCTAssertEqual(panes.viewButtonLabel, "Show Mailboxes")
    }

    // MARK: - What the container is told

    /// What `PaneShell` tells the container, in order: a new list for a
    /// folder, and the panes laid out, with the arrangement they move from
    /// after the view button, "< Mailboxes" and a folder tapped in two
    /// panes, and nil after anything else (B-066, B-077).
    private enum Told: Equatable {
        case opened(String)
        case laidOut(PaneArrangement.Panes, PaneArrangement.Column, from: PaneArrangement?)
    }

    private static let threePanes = PaneArrangement(launching: .three)
    private static let listInFront = PaneArrangement(launching: .two)
    private static var foldersInFront: PaneArrangement {
        var panes = PaneArrangement(launching: .two)
        panes.back()
        return panes
    }

    /// The container's half, written down rather than done.
    @MainActor
    private final class Container {
        let shell: PaneShell
        private var told: [Told] = []

        init(launching panes: PaneArrangement.Panes) {
            shell = PaneShell(launching: panes)
            shell.openList = { [unowned self] folder in self.told.append(.opened(folder.id)) }
            shell.layOut = { [unowned self] panes, from in
                self.told.append(.laidOut(panes.panes, panes.leftColumn, from: from))
            }
        }

        /// Everything told since the last time this was asked.
        func take() -> [Told] {
            defer { told = [] }
            return told
        }
    }

    /// The view button lays out the other arrangement, keeps it for the
    /// next launch, and opens nothing.
    @MainActor
    func testTheViewButtonLaysOutTheOtherArrangementAndKeepsIt() {
        let container = Container(launching: .three)
        container.shell.switchPanes()
        XCTAssertEqual(container.take(), [.laidOut(.two, .list, from: Self.threePanes)])
        XCTAssertEqual(PaneArrangement.saved, .two)

        container.shell.back()
        _ = container.take()
        container.shell.switchPanes()
        XCTAssertEqual(container.take(), [.laidOut(.three, .mailboxes, from: Self.foldersInFront)])
        XCTAssertEqual(PaneArrangement.saved, .three)
        XCTAssertEqual(container.shell.arrangement, PaneArrangement(launching: .three))
    }

    /// The view button, "< Mailboxes" and a folder tapped in two panes tell
    /// the container where the panes were, since they move (B-066,
    /// B-077): the view button from each of the three places it can be
    /// tapped, "< Mailboxes" from the list in front, a folder tap from the
    /// folders in front, the folder open or another. A folder tap in three
    /// panes changes nothing and says nil; so do "< Mailboxes" with the
    /// folders in front already, a folder opened another way and a return
    /// to the list, which are laid out with nothing moving.
    @MainActor
    func testWhatSaysWhereThePanesWere() {
        let container = Container(launching: .three)
        container.shell.switchPanes()
        XCTAssertEqual(container.take(), [.laidOut(.two, .list, from: Self.threePanes)])
        container.shell.switchPanes()
        XCTAssertEqual(container.take(), [.laidOut(.three, .mailboxes, from: Self.listInFront)])
        container.shell.switchPanes()
        container.shell.back()
        _ = container.take()
        container.shell.switchPanes()
        XCTAssertEqual(container.take(), [.laidOut(.three, .mailboxes, from: Self.foldersInFront)])

        let two = Container(launching: .two)
        two.shell.back()
        XCTAssertEqual(two.take(), [.laidOut(.two, .mailboxes, from: Self.listInFront)])
        two.shell.tapped(inbox, showing: inbox)
        XCTAssertEqual(two.take(), [.laidOut(.two, .list, from: Self.foldersInFront)])
        two.shell.back()
        _ = two.take()
        two.shell.tapped(sent, showing: inbox)
        XCTAssertEqual(two.take(), [.opened(sent.id), .laidOut(.two, .list, from: Self.foldersInFront)])

        // Nothing moves for these: with the list in front already, a folder
        // opened another way and a return; with the folders in front,
        // "< Mailboxes" again, a folder opened another way, and a return.
        two.shell.open(receipts)
        two.shell.showList()
        var quiet = two.take()
        two.shell.back()
        _ = two.take()
        two.shell.back()
        two.shell.open(receipts)
        quiet += two.take()
        two.shell.back()
        _ = two.take()
        two.shell.showList()
        quiet += two.take()
        let three = Container(launching: .three)
        three.shell.tapped(sent, showing: inbox)
        three.shell.back()
        three.shell.showList()
        three.shell.open(receipts)
        quiet += three.take()
        XCTAssertEqual(quiet.count, 13)
        for told in quiet {
            if case .laidOut(_, _, let from) = told { XCTAssertNil(from, "\(told)") }
        }
    }

    /// "< Mailboxes" lays out the folders, from the list in front, and
    /// opens nothing.
    @MainActor
    func testMailboxesLaysOutTheFoldersAndOpensNothing() {
        let container = Container(launching: .two)
        container.shell.back()
        XCTAssertEqual(container.take(), [.laidOut(.two, .mailboxes, from: Self.listInFront)])
    }

    /// In two panes the folder already open is laid out in front and not
    /// opened; another is opened, and then laid out in front, in that order,
    /// since laying out dresses the list's bar and it has to be the new
    /// list's. Both from the folders in front. In three, every tap opens,
    /// and nothing moves.
    @MainActor
    func testATapOpensAnotherFolderAndShowsTheOpenOnesList() {
        let two = Container(launching: .two)
        two.shell.back()
        _ = two.take()
        two.shell.tapped(inbox, showing: .inboxBeforeListing)
        XCTAssertEqual(two.take(), [.laidOut(.two, .list, from: Self.foldersInFront)])
        two.shell.back()
        _ = two.take()
        two.shell.tapped(sent, showing: inbox)
        XCTAssertEqual(two.take(), [.opened(sent.id), .laidOut(.two, .list, from: Self.foldersInFront)])

        let three = Container(launching: .three)
        three.shell.tapped(inbox, showing: inbox)
        XCTAssertEqual(three.take(), [.opened(inbox.id), .laidOut(.three, .mailboxes, from: nil)])
    }

    /// A folder opened with no tap on it, B-003's Inbox after a while away
    /// in another folder and All Mail for the date jump, comes in front in
    /// two panes, and two panes stay two.
    @MainActor
    func testEveryFolderOpenedComesInFront() {
        let container = Container(launching: .two)
        container.shell.back()
        _ = container.take()
        container.shell.open(inbox)
        XCTAssertEqual(container.take(), [.opened(inbox.id), .laidOut(.two, .list, from: nil)])
        XCTAssertEqual(container.shell.arrangement.panes, .two)
    }

    /// Back after a while away to the Inbox already showing: its list in
    /// front, nothing opened (the list fetches its newest itself, B-003),
    /// and two panes left two (B-037).
    @MainActor
    func testComingBackToTheInboxShowsItsListInTwoPanes() {
        let container = Container(launching: .two)
        container.shell.back()
        _ = container.take()
        container.shell.showList()
        XCTAssertEqual(container.take(), [.laidOut(.two, .list, from: nil)])
        XCTAssertEqual(container.shell.arrangement.panes, .two)
    }

    // MARK: - On the wire

    /// Nothing is fetched because of a switch, a "< Mailboxes", or a tap on
    /// the folder already open, in any order; a tap on another folder
    /// fetches its first page and nothing else, the three commands a tap in
    /// the three-pane sidebar sends. `PaneShell` decides, over the scripted
    /// server, with the container's one fetching part bound to the
    /// repository: a new list for a folder, which loads its first page as
    /// the list's `reload` does.
    @MainActor
    func testOnlyATapOnAnotherFolderGoesOnTheWire() async throws {
        let server = ScriptedIMAPServer()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        let repository = IMAPMailRepository(account: server.account, password: server.password,
                                            transport: server.transportFactory,
                                            recipients: RecipientBook(defaults: defaults),
                                            shelf: keptShelf(for: server.account))
        let shell = PaneShell(launching: .two)
        var shown = Mailbox.inboxBeforeListing
        var opened: [String] = []
        var loading: [Task<Void, Error>] = []
        shell.openList = { folder in
            shown = folder
            opened.append(folder.id)
            loading.append(Task {
                _ = try await repository.listMessages(in: folder.id, beforeUID: nil, limit: 50)
            })
        }
        func settled() async throws {
            for load in loading { try await load.value }
            loading = []
        }

        // Launch: the Inbox's first page.
        _ = try await repository.listMessages(in: shown.id, beforeUID: nil, limit: 50)
        server.clearLog()

        shell.switchPanes()
        shell.switchPanes()
        shell.back()
        shell.tapped(inbox, showing: shown)
        shell.back()
        shell.switchPanes()
        shell.switchPanes()
        shell.tapped(inbox, showing: shown)
        try await settled()
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(opened, [])
        XCTAssertEqual(shell.arrangement.leftColumn, .list)

        shell.back()
        shell.tapped(sent, showing: shown)
        try await settled()
        XCTAssertEqual(server.log.map(\.verb), ["SELECT", "UID SEARCH", "UID FETCH"])
        XCTAssertEqual(server.log.dropFirst().map(\.selected), [Server.sent, Server.sent])
        server.clearLog()

        shell.switchPanes()
        shell.switchPanes()
        shell.back()
        shell.tapped(sent, showing: shown)
        shell.showList()
        try await settled()
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(opened, [Server.sent])
        XCTAssertEqual(server.violations, [])
    }

    // MARK: - The container

    /// At launch the folders come after LOGIN and LIST, from half a second
    /// to six on the iPad. A folder he taps in that time keeps its
    /// highlight when they come: the launch highlights the folder that is
    /// open, not the Inbox whatever is open (B-086). The Inbox before the
    /// first frame stays, as nothing can have been tapped then.
    func testTheLaunchHighlightsTheFolderThatIsOpenWhenTheFoldersCome() throws {
        let root = try source("RootViewController.swift")
        let wait = try XCTUnwrap(root.range(of: "await mailboxList.showFolders()"))
        let next = root[wait.upperBound...].split(separator: "\n", omittingEmptySubsequences: true)
            .first.map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(next, "mailboxList.select(mailboxID: list.mailboxID)")
        XCTAssertEqual(lines(of: root, containing: "mailboxList.select(mailboxID: \"inbox\")").count, 1,
                       "only the first frame's Inbox, before anything can be tapped")
        let firstFrame = try XCTUnwrap(root.range(of: "mailboxList.select(mailboxID: \"inbox\")"))
        XCTAssertLessThan(firstFrame.lowerBound, wait.lowerBound)
    }

    /// A file of the app's source with its comment lines taken out.
    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/UI/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
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

    /// The lines of `code` that contain `text`, trimmed.
    private func lines(of code: String, containing text: String) -> [String] {
        code.components(separatedBy: "\n")
            .filter { $0.contains(text) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// What goes on the wire when a list is swapped in or fetched again.
    private let fetching = ["openMailbox(", "shell.open(", "reload(", "returnToNewest(",
                            "refreshMailboxes(", "refreshCounts(", "showFolders(", "Task"]

    /// `RootViewController` is UIKit and never runs on this host, so a
    /// container that stopped going through `PaneShell` would leave every
    /// other test here passing. Its source is read instead, as
    /// `MailboxNameTests` reads the screens', function by function: the
    /// shell is made once, in the kept arrangement; the view button,
    /// "< Mailboxes" and a folder tap each hand over to it and fetch
    /// nothing themselves; every folder opened, the Inbox on a return and
    /// All Mail for the date jump included, is opened through it; a return
    /// to the Inbox already showing puts the list in front through it; and
    /// the list is swapped for a new one nowhere but where it asks.
    func testEveryButtonAndTapGoesThroughTheShell() throws {
        let code = try source("RootViewController.swift")

        XCTAssertEqual(lines(of: code, containing: "PaneShell("),
                       ["private let shell = PaneShell(launching: PaneArrangement.saved)"])
        XCTAssertEqual(lines(of: code, containing: "PaneArrangement(launching:"), [])
        // The choice is kept by the shell, at each switch, and only there.
        XCTAssertEqual(lines(of: code, containing: "PaneArrangement.saved ="), [])

        let wiring = body(after: "func wireNavigation(", in: code)
        XCTAssertTrue(wiring.contains(
            "shell.openList = { [weak self] mailbox in self?.openMailbox(mailbox) }"))
        XCTAssertTrue(wiring.contains(
            "shell.layOut = { [weak self] panes, from in self?.arrange(panes, switchedFrom: from) }"))
        XCTAssertEqual(lines(of: code, containing: "switchedFrom: from"),
                       ["shell.layOut = { [weak self] panes, from in self?.arrange(panes, switchedFrom: from) }"])
        XCTAssertEqual(lines(of: code, containing: "openMailbox("),
                       ["shell.openList = { [weak self] mailbox in self?.openMailbox(mailbox) }",
                        "private func openMailbox(_ mailbox: Mailbox) {"])

        let viewButton = body(after: "func viewButtonTapped(", in: code)
        let back = body(after: "func backToMailboxes(", in: code)
        let tap = body(after: "mailboxList.onSelectMailbox = ", in: code)
        XCTAssertTrue(viewButton.contains("shell.switchPanes()"), viewButton)
        XCTAssertTrue(back.contains("shell.back()"), back)
        XCTAssertTrue(tap.contains("self.shell.tapped(mailbox, showing: self.list.shownMailbox)"), tap)
        for (name, handler) in [("view button", viewButton), ("< Mailboxes", back), ("tap", tap)] {
            for call in fetching {
                XCTAssertFalse(handler.contains(call), "\(name): \(call)")
            }
        }
        // The open folder keeps its highlight, whichever column it is in.
        for handler in [viewButton, back] {
            XCTAssertTrue(handler.contains("mailboxList.select(mailboxID: list.mailboxID)"), handler)
        }

        let returning = body(after: "func returnedFromAway(", in: code)
        let refresh = try XCTUnwrap(returning.range(of: "case .refreshInbox:"))
        let openInbox = try XCTUnwrap(returning.range(of: "case .openInbox:"))
        XCTAssertTrue(returning[refresh.upperBound..<openInbox.lowerBound]
                        .contains("shell.showList()"))
        XCTAssertTrue(returning[openInbox.upperBound...].contains("shell.open(inbox)"))
        XCTAssertTrue(body(after: "func jumpAcrossMailboxes(", in: code).contains("shell.open(all)"))
    }

    /// The other half of the container's source: that it lays the panes out
    /// one property of `PaneArrangement` to one setting. The widths to the
    /// width constraints, the list's left edge, which views are hidden, the
    /// controls in the list's bar and the name VoiceOver reads; the layout
    /// sweep at each change; nothing animated, here or where the list
    /// places its bar's items; and the calendar last among them, beside the
    /// title. The view button is `sidebar.left` with the app's minimum
    /// target, and it and "< Mailboxes" take a tap only when nothing else is
    /// touched.
    func testTheContainerLaysOutAsTheArrangementSays() throws {
        let code = try source("RootViewController.swift")

        let sizing = body(after: "func sizeColumns(", in: code)
        for line in ["PaneArrangement.columns(panes, screenWidth: screenWidth)",
                     "mailboxWidth.constant = columns.mailboxes",
                     "listWidth.constant = columns.list"] {
            XCTAssertTrue(sizing.contains(line), line)
        }
        let arranging = body(after: "func arrange(", in: code)
        for line in ["sizeColumns(panes.panes)",
                     "let edge = panes.listAtScreenEdge",
                     "NSLayoutConstraint.deactivate([edge ? listBesideMailboxes : listInLeftColumn])",
                     "NSLayoutConstraint.activate([edge ? listInLeftColumn : listBesideMailboxes])",
                     "mailboxNav.view.isHidden = !panes.mailboxesOnScreen",
                     "listNav.view.isHidden = !panes.listOnScreen",
                     "divider1.isHidden = !panes.mailboxDividerOnScreen",
                     "button?.accessibilityLabel = panes.viewButtonLabel",
                     "dressList(panes)",
                     "UIView.performWithoutAnimation { view.layoutIfNeeded() }",
                     "LayoutAudit.panesChanged(to: describe(panes))"] {
            XCTAssertTrue(arranging.contains(line), line)
        }
        let dressing = body(after: "func dressList(", in: code)
        for line in ["list.itemsBeforeCalendar = panes.itemsBeforeCalendar.map",
                     "case .viewButton: return listViewItem",
                     "case .back: return backItem"] {
            XCTAssertTrue(dressing.contains(line), line)
        }
        XCTAssertTrue(body(after: "override func viewDidLoad(", in: code).contains(
            "shell.arrangement.listAtScreenEdge ? listInLeftColumn : listBesideMailboxes"))

        for wiring in ["UIImage(systemName: \"sidebar.left\"",
                       "constraint(equalToConstant: Theme.minHitTarget)"] {
            XCTAssertTrue(code.contains(wiring), wiring)
        }
        // The view button and "< Mailboxes", both of which move the panes.
        XCTAssertEqual(code.components(separatedBy: "button.isExclusiveTouch = true").count - 1, 2)
        // The container animates nothing itself: the view button's switch
        // moves pictures, in `PaneMotion` (B-066).
        for motion in ["UIView.animate", "animated: true", "UIViewPropertyAnimator", ".transform"] {
            XCTAssertFalse(code.contains(motion), motion)
        }

        // The list's side: the container's items, then the calendar, put
        // in place at once, and nothing else in the list setting its
        // leading items over them.
        let list = try source("MessageListViewController.swift")
        let placing = body(after: "func placeLeadingItems(", in: list)
        XCTAssertTrue(placing.contains(
            "navigationItem.setLeftBarButtonItems(itemsBeforeCalendar + [jumpItem].compactMap { $0 },"),
                      placing)
        XCTAssertTrue(placing.contains("animated: false"), placing)
        XCTAssertFalse(placing.contains("animated: true"), placing)
        XCTAssertEqual(lines(of: list, containing: "leftBarButtonItem"), [])
        XCTAssertEqual(lines(of: list, containing: "LeftBarButtonItems").count, 1)
    }

    /// Where VoiceOver goes after a move (B-079), read. Each of the three
    /// names its element, and none leaves VoiceOver to choose: left to
    /// choose, on the iPad it went to the letter's Flag. The view button's
    /// switch: its twin in the corner, as before. "< Mailboxes", a pop:
    /// the open folder's row, highlighted just before, else the folders'
    /// table. A folder tap in two panes, a push: the list's highlighted
    /// row, else its first row wholly in sight, below the search band,
    /// else its table, the list read after the shell has made a new one,
    /// and the row held by the list for VoiceOver until it is there.
    /// A highlighted row counts if any of it is in sight. And the column
    /// named is shown when each is posted: the panes are hidden and shown
    /// in `arrange` before it can return early, with nothing put off until
    /// later, and the motion's cover, the one thing hidden from VoiceOver,
    /// is put beside them, not around them.
    ///
    /// The third change. The row named is shown whole first, with the least
    /// scroll, while the column is still hidden, before the panes move: the
    /// folder's row at "< Mailboxes", and the list's highlighted row at a
    /// tap on the open folder in two panes. And the folder's row is held
    /// for VoiceOver after "< Mailboxes": once VoiceOver has been on it, a
    /// move by itself to the view button in the corner, or to the reading
    /// pane from any folder but the last, is put back, once, with a layout
    /// change, the row shown whole first. The reading pane found by where
    /// it is too, for WebKit's elements in the letter's text. The folders
    /// out of sight, or the row with them, let go. A folder tap and the
    /// view button let go of both rows held.
    func testVoiceOverIsPutWhereTheMoveTakesHim() throws {
        let code = try source("RootViewController.swift")

        XCTAssertFalse(code.contains("argument: nil"))
        XCTAssertEqual(lines(of: code, containing: "UIAccessibility.post("),
                       ["UIAccessibility.post(notification: .layoutChanged,",
                        "UIAccessibility.post(notification: .screenChanged, argument: place)",
                        "UIAccessibility.post(notification: .layoutChanged, argument: place)",
                        "UIAccessibility.post(notification: .screenChanged,"])

        let viewButton = flat(body(after: "func viewButtonTapped(", in: code))
        let switched = try XCTUnwrap(viewButton.range(of: "shell.switchPanes()"))
        let foldersLet = try XCTUnwrap(viewButton.range(of: "letGoOfFoldersRow()"), viewButton)
        let listLet = try XCTUnwrap(viewButton.range(of: "list.letGoOfVoiceOver()"), viewButton)
        let twin = try XCTUnwrap(viewButton.range(of:
            "UIAccessibility.post(notification: .layoutChanged, argument: "
            + "shell.arrangement.leftColumn == .list ? listViewButton : mailboxesViewButton)"), viewButton)
        XCTAssertLessThan(switched.upperBound, foldersLet.lowerBound)
        XCTAssertLessThan(foldersLet.upperBound, twin.lowerBound)
        XCTAssertLessThan(listLet.upperBound, twin.lowerBound)

        let back = flat(body(after: "func backToMailboxes(", in: code))
        let highlighted = try XCTUnwrap(back.range(of: "mailboxList.select(mailboxID: list.mailboxID)"))
        let whole = try XCTUnwrap(back.range(of:
            "mailboxList.tableView.showWhole(forVoiceOver: mailboxList.tableView.indexPathForSelectedRow)"),
                                  back)
        let popped = try XCTUnwrap(back.range(of: "shell.back()"))
        let placed = try XCTUnwrap(back.range(of:
            "let place = mailboxList.tableView.voiceOverPlace(orFirstRow: false)"), back)
        let toFolder = try XCTUnwrap(back.range(of:
            "UIAccessibility.post(notification: .screenChanged, argument: place)"), back)
        let heldRow = try XCTUnwrap(back.range(of:
            "foldersVoiceOver.send(toRow: place is UITableViewCell, "
            + "last: mailboxList.tableView.voiceOverIsLast( mailboxList.tableView.indexPathForSelectedRow), "
            + "running: UIAccessibility.isVoiceOverRunning, at: Date())"), back)
        XCTAssertLessThan(highlighted.upperBound, whole.lowerBound)
        XCTAssertLessThan(whole.upperBound, popped.lowerBound)
        XCTAssertLessThan(popped.upperBound, placed.lowerBound)
        let watched = try XCTUnwrap(back.range(of: "watchFoldersRow() }"), back)
        XCTAssertLessThan(placed.upperBound, toFolder.lowerBound)
        XCTAssertLessThan(toFolder.upperBound, heldRow.lowerBound)
        XCTAssertLessThan(heldRow.upperBound, watched.lowerBound)

        // The folder's row held: looked for as VoiceOver moves, put back
        // only when `FoldersVoiceOver` says so, shown whole first
        // (`testVoiceOverIsAskedWhereItIsWhileARowIsHeld`).
        XCTAssertTrue(flat(code).contains(
            "addObserver(self, selector: #selector(voiceOverMoved(_:)), "
            + "name: UIAccessibility.elementFocusedNotification, object: nil)"))
        // The row: the folders' highlighted one, by the same finder as the
        // list's rows. Then the corner's view button, then the reading
        // pane, each by the view the element is in, or by where it is for
        // one in no view, as WebKit's in the letter's text; anything else
        // is his. Whether the row is the folders' last, from which a swipe
        // goes to the reading pane, is told as it is sent.
        let landing = flat(body(after: "private func foldersLanding(on element: Any?)", in: code))
        XCTAssertEqual(landing, "{ guard let element else { return .other } "
                       + "let folders: UITableView = mailboxList.tableView "
                       + "if let row = folders.voiceOverRow(of: element) { "
                       + "return row == folders.indexPathForSelectedRow ? .sentRow : .other } "
                       + "if mailboxesViewButton.voiceOverHolds(element) { return .corner } "
                       + "return detailNav.view.voiceOverHolds(element) ? .pane : .other }")
        XCTAssertFalse(code.contains("voiceOverHolder("), "the container finds by `voiceOverHolds`")
        XCTAssertFalse(code.contains("isDescendant("), "the container finds by `voiceOverHolds`")

        let tap = flat(body(after: "mailboxList.onSelectMailbox = ", in: code))
        let letGo = try XCTUnwrap(tap.range(of: "self.letGoOfFoldersRow()"), tap)
        let showing = try XCTUnwrap(tap.range(of:
            "if self.shell.arrangement.panes == .two, "
            + "PaneArrangement.isShowing(mailbox, in: self.list.shownMailbox) { "
            + "self.list.showHighlightedRowWhole() }"), tap)
        let tapped = try XCTUnwrap(tap.range(of: "self.shell.tapped(mailbox, showing: self.list.shownMailbox)"))
        let inTwo = try XCTUnwrap(tap.range(of: "if self.shell.arrangement.panes == .two {"))
        let toList = try XCTUnwrap(tap.range(of:
            "UIAccessibility.post(notification: .screenChanged, "
            + "argument: self.list.placeVoiceOver())"), tap)
        XCTAssertLessThan(letGo.upperBound, showing.lowerBound)
        XCTAssertLessThan(showing.upperBound, tapped.lowerBound)
        XCTAssertLessThan(tapped.upperBound, inTwo.lowerBound)
        XCTAssertLessThan(inTwo.upperBound, toList.lowerBound)
        // The list read again after the tap, for the post: a folder opened
        // has a new one.
        XCTAssertEqual(tap.components(separatedBy: "self.list").count - 1, 4, tap)
        XCTAssertEqual(tap[tapped.upperBound...].components(separatedBy: "self.list").count - 1, 1, tap)
        XCTAssertEqual(lines(of: code, containing: "voiceOverPlace(").count, 2)
        XCTAssertEqual(lines(of: code, containing: "placeVoiceOver(").count, 1)
        XCTAssertEqual(lines(of: code, containing: "showWhole(").count, 2)
        XCTAssertEqual(lines(of: code, containing: "showHighlightedRowWhole(").count, 1)

        // The list's side of the least scroll: its highlighted row, with
        // the sums the naming uses. And letting go.
        let list = try source("MessageListViewController.swift")
        XCTAssertEqual(flat(body(after: "func showHighlightedRowWhole()", in: list)),
                       "{ tableView.showWhole(forVoiceOver: tableView.indexPathForSelectedRow) }")
        XCTAssertEqual(flat(body(after: "func letGoOfVoiceOver()", in: list)),
                       "{ voiceOver.letGo() stopWatchingVoiceOver() }")

        // The list's: its highlighted row, else its first row wholly in
        // sight, else its table, held for VoiceOver as it is posted.
        let placeVoiceOver = flat(body(after: "func placeVoiceOver() -> UIView", in: list))
        let named = try XCTUnwrap(placeVoiceOver.range(of:
            "let place = tableView.voiceOverPlace(orFirstRow: true)"), placeVoiceOver)
        let held = try XCTUnwrap(placeVoiceOver.range(of:
            "voiceOver.send(to: voiceOverRow(of: place), running: UIAccessibility.isVoiceOverRunning, "
            + "at: Date())"), placeVoiceOver)
        let watching = try XCTUnwrap(placeVoiceOver.range(of: "watchVoiceOver()"), placeVoiceOver)
        let posted = try XCTUnwrap(placeVoiceOver.range(of: "return place }"), placeVoiceOver)
        XCTAssertLessThan(named.upperBound, held.lowerBound)
        XCTAssertLessThan(held.upperBound, watching.lowerBound)
        XCTAssertLessThan(watching.upperBound, posted.lowerBound)

        // In sight: between the bars, and below the band pinned at the top.
        // A highlighted row with any of it in sight; a first row wholly in
        // it. Not `visibleCells`, which counts the rows under the band.
        let geometry = try source("VoiceOverPlace.swift")
        let selected = flat(body(after: "func voiceOverPlace(orFirstRow: Bool) -> UIView", in: geometry))
        XCTAssertEqual(selected,
                       "{ voiceOverPlace(at: indexPathForSelectedRow, orFirstRow: orFirstRow) }")
        let placing = flat(body(after: "func voiceOverPlace(at row: IndexPath?, orFirstRow: Bool) -> UIView",
                                in: geometry))
        let sight = try XCTUnwrap(placing.range(of: "let sight = self.sight"), placing)
        let row = try XCTUnwrap(placing.range(of:
            "if let row, holds(row), sight.showsPart(rectForRow(at: row).minY, rectForRow(at: row).maxY), "
            + "let cell = cellForRow(at: row) { return cell }"), placing)
        let first = try XCTUnwrap(placing.range(of:
            "if orFirstRow, "
            + "let first = (indexPathsForVisibleRows ?? []).sorted().first(where: { row in "
            + "sight.showsWhole(rectForRow(at: row).minY, rectForRow(at: row).maxY) }), "
            + "let cell = cellForRow(at: first) { return cell }"), placing)
        let table = try XCTUnwrap(placing.range(of: "return self }"), placing)
        XCTAssertLessThan(sight.upperBound, row.lowerBound)
        XCTAssertLessThan(row.upperBound, first.lowerBound)
        XCTAssertLessThan(first.upperBound, table.lowerBound)
        XCTAssertFalse(placing.contains("visibleCells"), placing)
        XCTAssertEqual(placing.components(separatedBy: "return ").count - 1, 3, placing)
        // The sums, from the table as it is: its offset and height, its bars
        // as its adjusted insets, the first section's header as the band.
        XCTAssertEqual(flat(body(after: "var sight: TableSight", in: geometry)),
                       "{ TableSight(offset: contentOffset.y, height: bounds.height, "
                       + "barTop: adjustedContentInset.top, barBottom: adjustedContentInset.bottom, "
                       + "band: numberOfSections > 0 ? rectForHeader(inSection: 0).height : 0, "
                       + "content: contentSize.height) }")
        XCTAssertEqual(flat(body(after: "private func holds(_ row: IndexPath) -> Bool", in: geometry)),
                       "{ row.section < numberOfSections && row.row < numberOfRows(inSection: row.section) }")
        // The least scroll: only with VoiceOver running, laid out first, by
        // `TableSight`, not animated.
        let least = flat(body(after: "func showWhole(forVoiceOver row: IndexPath?)", in: geometry))
        XCTAssertEqual(least, "{ guard UIAccessibility.isVoiceOverRunning, let row, holds(row) else { return } "
                       + "layoutIfNeeded() let rect = rectForRow(at: row) "
                       + "guard let offset = sight.offset(showingWhole: rect.minY, rect.maxY) "
                       + "else { return } "
                       + "setContentOffset(CGPoint(x: contentOffset.x, y: offset), animated: false) "
                       + "layoutIfNeeded() }")
        XCTAssertEqual(lines(of: geometry, containing: "contentOffset"),
                       ["setContentOffset(CGPoint(x: contentOffset.x, y: offset), animated: false)",
                        "TableSight(offset: contentOffset.y, height: bounds.height,"])

        // Shown, laid out and in the window when posted.
        let arranging = body(after: "func arrange(", in: code)
        let early = try XCTUnwrap(arranging.range(of: "guard view.window != nil else { return }"))
        for line in ["mailboxNav.view.isHidden = !panes.mailboxesOnScreen",
                     "listNav.view.isHidden = !panes.listOnScreen"] {
            let hiding = try XCTUnwrap(arranging.range(of: line), line)
            XCTAssertLessThan(hiding.upperBound, early.lowerBound, line)
        }
        for later in ["DispatchQueue", "Task", "async", "perform(#selector", "RunLoop"] {
            XCTAssertFalse(arranging.contains(later), later)
        }
        XCTAssertEqual(lines(of: code, containing: "isHidden ="),
                       ["mailboxNav.view.isHidden = !panes.mailboxesOnScreen",
                        "listNav.view.isHidden = !panes.listOnScreen",
                        "divider1.isHidden = !panes.mailboxDividerOnScreen"])
        let motion = try source("PaneMotion.swift")
        XCTAssertEqual(lines(of: motion, containing: "accessibility"),
                       ["cover.accessibilityElementsHidden = true"])
        XCTAssertEqual(lines(of: motion, containing: "addSubview(cover)"), ["root.addSubview(cover)"])
        XCTAssertFalse(motion.contains("accessibilityViewIsModal"))
    }

    /// VoiceOver kept on its letter when the list's rows are drawn again
    /// (B-079, the second change), read. Each of the list's three reloads,
    /// the regroup, the kept page and a day's mail, takes VoiceOver's row
    /// before the reload and puts VoiceOver back on its letter at its end,
    /// once the list is where it goes. There are no other reloads. The row
    /// taken: the one VoiceOver was sent to, while held, else the one it is
    /// on, found from where VoiceOver is now, never with it off. Put back
    /// with a layout change, on the cell for its letter, laid out first. A
    /// row VoiceOver has been sent to is looked for as VoiceOver moves, and
    /// it is put there once if it went to another row, or to the list's own
    /// bar or table. What VoiceOver is on is told apart in that order: a
    /// row, his typing, the list's own column, its bar apart, in the Outbox
    /// only its view button and "< Mailboxes", the panes beside it in the
    /// container, anything else, by view or, for an element in no view, by
    /// where it is. With
    /// the list's column out of sight nothing is held, and a row he opens
    /// or ticks lets it go. A row is shown whole, with the least scroll,
    /// before VoiceOver is put on it.
    func testVoiceOverStaysOnItsLetterWhenTheRowsAreDrawnAgain() throws {
        let list = try source("MessageListViewController.swift")

        XCTAssertEqual(lines(of: list, containing: "reloadData()"),
                       ["tableView.reloadData()", "tableView.reloadData()", "tableView.reloadData()"])
        XCTAssertFalse(list.contains("reloadSections"))
        XCTAssertFalse(list.contains("reloadRows("))
        XCTAssertFalse(list.contains("insertRows("))
        XCTAssertFalse(list.contains("deleteRows("))
        for opener in ["private func regroup(highlighting opened: String? = nil, "
                       + "to move: ListPlaces.Move = .stay,",
                       "private func showKeptPage()",
                       "private func show(_ window: MessageWindow)"] {
            let redraw = flat(body(after: opener, in: list))
            let taken = try XCTUnwrap(redraw.range(of:
                "let voiceOverOn = voiceOverHeld() defer { keepVoiceOver(voiceOverOn) }"), opener)
            let rebuilt = try XCTUnwrap(redraw.range(of: "rebuildRows()"), opener)
            let reloaded = try XCTUnwrap(redraw.range(of: "tableView.reloadData()"), opener)
            XCTAssertLessThan(taken.upperBound, rebuilt.lowerBound, opener)
            XCTAssertLessThan(rebuilt.upperBound, reloaded.lowerBound, opener)
            XCTAssertEqual(redraw.components(separatedBy: "keepVoiceOver(").count - 1, 1, opener)
            XCTAssertEqual(redraw.components(separatedBy: "defer").count - 1, 1, opener)
        }
        XCTAssertEqual(lines(of: list, containing: "keepVoiceOver(voiceOverOn)"),
                       ["defer { keepVoiceOver(voiceOverOn) }", "defer { keepVoiceOver(voiceOverOn) }",
                        "defer { keepVoiceOver(voiceOverOn) }"])

        // Taken: VoiceOver's own element, as the list sees it, only with it
        // on, and nothing with the list's column out of sight.
        let held = flat(body(after: "private func voiceOverHeld()", in: list))
        XCTAssertEqual(held, "{ guard listInSight else { letGoOfVoiceOver() return nil } "
                       + "let running = UIAccessibility.isVoiceOverRunning "
                       + "let on = voiceOverLanding( on: running ? UIAccessibility.focusedElement(using: "
                       + ".notificationVoiceOver) : nil, sentTo: nil) "
                       + "return voiceOver.held(running: running, on: voiceOverRow(at: on.row), "
                       + "landing: on.landing, at: Date()) }")
        let sight = flat(body(after: "private var listInSight: Bool", in: list))
        XCTAssertEqual(sight, "{ var shown: UIView? = tableView while let view = shown { "
                       + "if view.isHidden { return false } shown = view.superview } "
                       + "return tableView.window != nil }")

        // What VoiceOver is on: a row of the list first, the one it was
        // sent to or another; then his typing, a key or the search field
        // being edited; then the list's own column; else elsewhere.
        let landing = flat(body(after: "private func voiceOverLanding(", in: list))
        let nothing = try XCTUnwrap(landing.range(of: "guard let element else { return (.elsewhere, nil) }"),
                                    landing)
        let onRow = try XCTUnwrap(landing.range(of: "if let on = listRow(of: element) {"), landing)
        let typing = try XCTUnwrap(landing.range(of:
            "if (element as? NSObject)?.accessibilityTraits.contains(.keyboardKey) == true "
            + "|| (!isOutbox && searchBar.isTyping) { return (.typing, nil) }"), landing)
        // The list's own column, its bar apart: in the Outbox, which has no
        // search band, only the view button and "< Mailboxes", the items
        // before the calendar; its title and Edit, a swipe from the first
        // row, are its own column. Each found by `voiceOverHolds`: by the
        // view the element is in, else by where it is, as WebKit's
        // elements in the letter's text are found in the reading pane.
        let own = try XCTUnwrap(landing.range(of:
            "if let column = navigationController?.view ?? view, column.voiceOverHolds(element) { "
            + "if let bar = navigationController?.navigationBar, bar.voiceOverHolds(element), "
            + "!isOutbox || itemsBeforeCalendar.contains(where: { item in "
            + "item.customView?.voiceOverHolds(element) == true }) { return (.listBar, nil) } "
            + "return (.listOwn, nil) }"), landing)
        let beside = try XCTUnwrap(landing.range(of:
            "if let panes = navigationController?.parent?.view, panes.voiceOverHolds(element) { "
            + "return (.beside, nil) }"), landing)
        XCTAssertFalse(landing.contains("isDescendant("), landing)
        XCTAssertFalse(landing.contains("voiceOverHolder("), landing)
        let elsewhere = try XCTUnwrap(landing.range(of: "return (.elsewhere, nil) }", options: .backwards),
                                      landing)
        XCTAssertLessThan(nothing.upperBound, onRow.lowerBound)
        XCTAssertLessThan(onRow.upperBound, typing.lowerBound)
        XCTAssertLessThan(typing.upperBound, own.lowerBound)
        XCTAssertLessThan(own.upperBound, beside.lowerBound)
        XCTAssertLessThan(beside.upperBound, elsewhere.lowerBound)
        // The row sent to by its place in the list alone, not by its words
        // (the fourth change).
        XCTAssertTrue(landing.contains("if let on = listRow(of: element) { "
                                       + "guard let place else { return (.otherRow, on) } "
                                       + "return (on == voiceOverRow(of: place)?.index ? .sentRow : .otherRow, on) }"),
                      landing)
        XCTAssertFalse(landing.contains("accessibilityLabel"), landing)
        XCTAssertTrue(flat(try source("SearchHeaderView.swift")).contains("var isTyping: Bool { field.isEditing }"))

        // A row of the list: a cell of this table or inside one, or UIKit's
        // element for a row, by where it is, off the search band. Not the
        // table, the band, or anything of another table. Found as the
        // folders' row is, in one place.
        let row = flat(body(after: "private func listRow(of element: Any) -> Int?", in: list))
        XCTAssertEqual(row, "{ let band = isOutbox ? nil : UIAccessibility.convertToScreenCoordinates("
                       + "searchBar.bounds, in: searchBar) "
                       + "return tableView.voiceOverRow(of: element, besides: band)?.row }")
        let geometry = try source("VoiceOverPlace.swift")
        XCTAssertTrue(flat(body(after: "static func voiceOverHolder(of element: Any) -> UIView?", in: geometry))
            .contains("holder = (holder as? UIAccessibilityElement)?.accessibilityContainer"))
        // In a view: by the view it is or is in, else, for an element in no
        // view, by the middle of its frame on the view's part of the
        // screen, only with nothing presented over the window.
        XCTAssertEqual(flat(body(after: "func voiceOverHolds(_ element: Any) -> Bool", in: geometry)),
                       "{ if let holder = UIView.voiceOverHolder(of: element) { "
                       + "return holder.isDescendant(of: self) } "
                       + "guard let window, window.rootViewController?.presentedViewController == nil, "
                       + "let frame = (element as? NSObject)?.accessibilityFrame else { return false } "
                       + "return UIAccessibility.convertToScreenCoordinates(bounds, in: self) "
                       + ".contains(CGPoint(x: frame.midX, y: frame.midY)) }")
        // The last row, by the sums in `FoldersVoiceOver`, from the table's
        // own rows in each section.
        XCTAssertEqual(flat(body(after: "func voiceOverIsLast(_ row: IndexPath?) -> Bool", in: geometry)),
                       "{ guard let row else { return false } "
                       + "return FoldersVoiceOver.isLast(row.row, in: row.section, "
                       + "of: (0..<numberOfSections).map { numberOfRows(inSection: $0) }) }")
        let finder = flat(body(after: "func voiceOverRow(of element: Any, besides band: CGRect? = nil)",
                               in: geometry))
        for part in ["guard var view = UIView.voiceOverHolder(of: element) else { return nil }",
                     "if view === self {",
                     "guard !(element is UIView), let frame = (element as? NSObject)?.accessibilityFrame",
                     "if let band, band.contains(middle) { return nil }",
                     "UIAccessibility.convertToScreenCoordinates(rectForRow(at: row), in: self) .contains(middle)",
                     "while view !== self {",
                     "if let cell = view as? UITableViewCell { return indexPath(for: cell) }"] {
            XCTAssertTrue(finder.contains(part), part)
        }
        XCTAssertFalse(list.contains("holderView("))

        // Put back: laid out, the cell for its letter or in its place, by
        // the rules of a move, with a layout change.
        let place = flat(body(after: "private func voiceOverPlace(keeping held: ListVoiceOver.Row?)", in: list))
        XCTAssertTrue(place.contains("switch ListVoiceOver.step(after: held, in: threads)"), place)
        let laidOut = try XCTUnwrap(place.range(of: "tableView.layoutIfNeeded()"), place)
        let cell = try XCTUnwrap(place.range(of:
            "return tableView.voiceOverPlace(at: IndexPath(row: row, section: 0), orFirstRow: true)"), place)
        XCTAssertLessThan(laidOut.upperBound, cell.lowerBound)
        XCTAssertTrue(place.contains("case .leave: return nil"), place)
        XCTAssertTrue(place.contains("case .table: return tableView"), place)
        let keep = flat(body(after: "private func keepVoiceOver(", in: list))
        XCTAssertEqual(keep, "{ guard let place = voiceOverPlace(keeping: held) else { return } "
                       + "voiceOver.redrawn(to: voiceOverRow(of: place)) "
                       + "putVoiceOver(on: place) }")
        // Put on a row: shown whole first, with the least scroll, then a
        // layout change. The list's one post.
        XCTAssertEqual(flat(body(after: "private func putVoiceOver(on place: UIView)", in: list)),
                       "{ tableView.showWhole(forVoiceOver: "
                       + "(place as? UITableViewCell).flatMap { tableView.indexPath(for: $0) }) "
                       + "UIAccessibility.post(notification: .layoutChanged, argument: place) }")
        XCTAssertEqual(lines(of: list, containing: "putVoiceOver(on: place)"),
                       ["putVoiceOver(on: place)", "putVoiceOver(on: place)"])
        // A row he opens or ticks lets the row held go, first thing.
        let selected = flat(body(after: "override func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath)",
                                 in: list))
        XCTAssertTrue(selected.hasPrefix("{ letGoOfVoiceOver() guard !inEditMode"), selected)

        // Looked for as VoiceOver moves, and put there at most once
        // (`testVoiceOverIsAskedWhereItIsWhileARowIsHeld`).
        XCTAssertTrue(flat(list).contains(
            "addObserver(self, selector: #selector(voiceOverMoved(_:)), "
            + "name: UIAccessibility.elementFocusedNotification, object: nil)"))
        XCTAssertEqual(lines(of: list, containing: "UIAccessibility.post(").count, 1)
        XCTAssertFalse(list.contains(".screenChanged"))
    }

    /// Where VoiceOver is, asked of VoiceOver itself while a row is held
    /// (B-079, the fourth change), read. On the iPad the element named with
    /// VoiceOver's moves was nothing the app could find, so neither the
    /// list nor the container ever saw VoiceOver leave the row. Neither
    /// reads it now. At each of VoiceOver's moves, while a row is held,
    /// VoiceOver is asked on the next turn; and every tenth of a second, on
    /// a timer on the main run loop in its common modes, started as the row
    /// is sent to, and told apart only when VoiceOver is on another object.
    /// VoiceOver on nothing is passed over, the row still held: it is not
    /// told apart as elsewhere, which would let the row go.
    /// The ticks stop with nothing held, VoiceOver off or past the bound,
    /// once the row is put back or let go, and where the row is let go:
    /// the list's at the view button, a row opened, the list out of sight;
    /// the folders' at a folder tap, the view button, the folders out of
    /// sight. The timer is made in one place and invalidated only where the
    /// ticks stop or start again. The rest is as before: put back only when
    /// `ListVoiceOver` or `FoldersVoiceOver` says so, shown whole first.
    func testVoiceOverIsAskedWhereItIsWhileARowIsHeld() throws {
        let list = try source("MessageListViewController.swift")
        let code = try source("RootViewController.swift")
        let geometry = try source("VoiceOverPlace.swift")
        for file in [list, code, geometry] {
            XCTAssertFalse(file.contains("focusedElementUserInfoKey"))
        }

        // The list.
        XCTAssertEqual(flat(body(after: "@objc private func voiceOverMoved(", in: list)),
                       "{ guard isViewLoaded, voiceOver.sentRow(at: Date()) != nil else { return } "
                       + "DispatchQueue.main.async { [weak self] in "
                       + "self?.lookAtVoiceOver(onlyIfMoved: false) } }")
        XCTAssertEqual(flat(body(after: "@objc private func voiceOverTick()", in: list)),
                       "{ lookAtVoiceOver(onlyIfMoved: true) }")
        XCTAssertEqual(flat(body(after: "private func lookAtVoiceOver(onlyIfMoved: Bool)", in: list)),
                       "{ let now = Date() "
                       + "guard focusWatch.goesOn(holding: isViewLoaded && UIAccessibility.isVoiceOverRunning "
                       + "&& voiceOver.sentRow(at: now) != nil) else { stopWatchingVoiceOver() return } "
                       + "guard listInSight else { letGoOfVoiceOver() return } "
                       + "guard let element = UIAccessibility.focusedElement(using: .notificationVoiceOver) "
                       + "else { return } "
                       + "let changed = focusWatch.changed(to: element as AnyObject) "
                       + "guard changed || !onlyIfMoved, let sent = voiceOver.sentRow(at: now), "
                       + "let place = voiceOverPlace(keeping: sent) else { return } "
                       + "let landing = voiceOverLanding(on: element, sentTo: place).landing "
                       + "let put = voiceOver.moved(to: landing, at: now) "
                       + "if voiceOver.sentRow(at: now) == nil { stopWatchingVoiceOver() } "
                       + "guard put != nil else { return } "
                       + "putVoiceOver(on: place) }")
        XCTAssertEqual(flat(body(after: "private func watchVoiceOver()", in: list)),
                       "{ voiceOverTicks?.invalidate() "
                       + "voiceOverTicks = focusWatch.start(holding: voiceOver.sentRow(at: Date()) != nil) "
                       + "? Timer.voiceOverTicks(self, #selector(voiceOverTick)) : nil }")
        XCTAssertEqual(flat(body(after: "private func stopWatchingVoiceOver()", in: list)),
                       "{ focusWatch.stop() voiceOverTicks?.invalidate() voiceOverTicks = nil }")
        XCTAssertEqual(lines(of: list, containing: "voiceOver.letGo()"), ["voiceOver.letGo()"])
        XCTAssertEqual(lines(of: list, containing: "letGoOfVoiceOver()"),
                       ["func letGoOfVoiceOver() {", "letGoOfVoiceOver()", "letGoOfVoiceOver()",
                        "letGoOfVoiceOver()"])
        XCTAssertEqual(lines(of: list, containing: "watchVoiceOver()"),
                       ["watchVoiceOver()", "private func watchVoiceOver() {"])
        XCTAssertEqual(lines(of: list, containing: "voiceOverTicks?.invalidate()").count, 2)
        XCTAssertEqual(lines(of: list, containing: "Timer").count, 2)
        XCTAssertEqual(lines(of: list, containing: "DispatchQueue").count, 1)
        XCTAssertEqual(lines(of: list, containing: "focusedElement(").count, 2)

        // The container, for the folder's row.
        XCTAssertEqual(flat(body(after: "@objc private func voiceOverMoved(", in: code)),
                       "{ guard foldersVoiceOver.holding(at: Date()) else { return } "
                       + "DispatchQueue.main.async { [weak self] in "
                       + "self?.lookAtFoldersRow(onlyIfMoved: false) } }")
        XCTAssertEqual(flat(body(after: "@objc private func foldersTick()", in: code)),
                       "{ lookAtFoldersRow(onlyIfMoved: true) }")
        XCTAssertEqual(flat(body(after: "private func lookAtFoldersRow(onlyIfMoved: Bool)", in: code)),
                       "{ let now = Date() "
                       + "guard foldersWatch.goesOn(holding: UIAccessibility.isVoiceOverRunning "
                       + "&& foldersVoiceOver.holding(at: now)) else { stopWatchingFoldersRow() return } "
                       + "let place = mailboxList.tableView.voiceOverPlace(orFirstRow: false) "
                       + "guard !mailboxNav.view.isHidden, place is UITableViewCell else { "
                       + "letGoOfFoldersRow() return } "
                       + "guard let element = UIAccessibility.focusedElement(using: .notificationVoiceOver) "
                       + "else { return } "
                       + "let changed = foldersWatch.changed(to: element as AnyObject) "
                       + "guard changed || !onlyIfMoved else { return } "
                       + "let put = foldersVoiceOver.moved(to: foldersLanding(on: element), at: now) "
                       + "if !foldersVoiceOver.holding(at: now) { stopWatchingFoldersRow() } "
                       + "guard put else { return } "
                       + "mailboxList.tableView.showWhole(forVoiceOver: "
                       + "mailboxList.tableView.indexPathForSelectedRow) "
                       + "UIAccessibility.post(notification: .layoutChanged, argument: place) }")
        XCTAssertEqual(flat(body(after: "private func watchFoldersRow()", in: code)),
                       "{ foldersTicks?.invalidate() "
                       + "foldersTicks = foldersWatch.start(holding: foldersVoiceOver.holding(at: Date())) "
                       + "? Timer.voiceOverTicks(self, #selector(foldersTick)) : nil }")
        XCTAssertEqual(flat(body(after: "private func letGoOfFoldersRow()", in: code)),
                       "{ foldersVoiceOver.letGo() stopWatchingFoldersRow() }")
        XCTAssertEqual(flat(body(after: "private func stopWatchingFoldersRow()", in: code)),
                       "{ foldersWatch.stop() foldersTicks?.invalidate() foldersTicks = nil }")
        XCTAssertEqual(lines(of: code, containing: "foldersVoiceOver.letGo()"), ["foldersVoiceOver.letGo()"])
        XCTAssertEqual(lines(of: code, containing: "letGoOfFoldersRow()"),
                       ["letGoOfFoldersRow()", "private func letGoOfFoldersRow() {", "letGoOfFoldersRow()",
                        "self.letGoOfFoldersRow()"])
        XCTAssertEqual(lines(of: code, containing: "watchFoldersRow()"),
                       ["watchFoldersRow()", "private func watchFoldersRow() {"])
        XCTAssertEqual(lines(of: code, containing: "foldersTicks?.invalidate()").count, 2)
        XCTAssertEqual(lines(of: code, containing: "Timer").count, 2)
        XCTAssertEqual(lines(of: code, containing: "focusedElement(").count, 1)

        // The timer: a tenth of a second, repeating, on the main run loop
        // in its common modes.
        XCTAssertEqual(flat(body(after: "static func voiceOverTicks(_ target: Any, _ selector: Selector) -> Timer",
                                 in: geometry)),
                       "{ let ticks = Timer(timeInterval: FocusWatch.every, target: target, selector: selector, "
                       + "userInfo: nil, repeats: true) RunLoop.main.add(ticks, forMode: .common) return ticks }")
    }

    // MARK: - The panes, moving

    /// `text` with every run of spaces and line breaks made one space.
    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).joined(separator: " ")
    }

    /// The container's half of B-066 and B-077, read: the pictures of the
    /// screen as it was are cut before anything is laid out, from the
    /// screen as laid out, with a bounce looked for and coasting stopped
    /// first, and Prefer Cross-Fade Transitions asked at the tap; the panes
    /// are then laid out exactly as before, the layout sweep runs on them,
    /// and only then does the motion go over them. Reduce Motion is asked
    /// nowhere. A change still moving is ended before anything lays the
    /// panes out, before the iPad turns, and as the app stops being in
    /// front. The buttons hand over to the shell and know nothing of the
    /// motion.
    func testTheChangeMovesPicturesOverPanesAlreadyLaidOut() throws {
        let code = try source("RootViewController.swift")

        XCTAssertEqual(lines(of: code, containing: "PaneMotion("),
                       ["private let motion = PaneMotion()"])
        let arranging = body(after: "func arrange(", in: code)
        XCTAssertTrue(arranging.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                        .hasPrefix("let wasMoving = motion.finish()"), arranging)
        XCTAssertTrue(arranging.contains(
            "let cut = wasMoving ? nil : from.flatMap { pictures(from: $0, to: panes) }"), arranging)
        let cutting = try XCTUnwrap(arranging.range(of: "pictures("))
        let sizing = try XCTUnwrap(arranging.range(of: "sizeColumns(panes.panes)"))
        let swapping = try XCTUnwrap(arranging.range(of: "NSLayoutConstraint.deactivate("))
        XCTAssertLessThan(cutting.lowerBound, sizing.lowerBound)
        XCTAssertLessThan(cutting.lowerBound, swapping.lowerBound)
        let laying = try XCTUnwrap(arranging.range(of: "UIView.performWithoutAnimation { view.layoutIfNeeded() }"))
        let sweeping = try XCTUnwrap(arranging.range(of: "LayoutAudit.panesChanged(to: describe(panes))"))
        let playing = try XCTUnwrap(arranging.range(of: "if let cut { motion.play(cut) }"))
        XCTAssertLessThan(laying.upperBound, sweeping.lowerBound)
        XCTAssertLessThan(sweeping.upperBound, playing.lowerBound)
        XCTAssertEqual(lines(of: code, containing: "motion.play("), ["if let cut { motion.play(cut) }"])
        XCTAssertEqual(lines(of: code, containing: "motion.cut("),
                       ["return motion.cut(move, stage: stage)"])

        let picturing = body(after: "func pictures(", in: code)
        for line in ["let emptyLabel = detail.emptyLabel",
                     "PaneMove.switching(from: from, to: panes, screenWidth: screenWidth,",
                     "reading: emptyLabel == nil ? .words : .nothing,",
                     "crossFading: PaneMotion.crossFading) else {",
                     "guard arranged == from else",
                     "root: view, mailboxes: mailboxNav.view, list: listNav.view, message: detailNav.view",
                     "corner: from.leftColumn == .list ? listViewButton : mailboxesViewButton",
                     "mailboxesButton: mailboxesViewButton, listButton: listViewButton,",
                     "letterBar: detailNav.navigationBar, placeholder: emptyLabel)"] {
            XCTAssertTrue(picturing.contains(line), line)
        }
        // A list, the folders or the letter in the pictures, hidden or
        // not, bouncing past an end is looked for before anything is
        // touched, and turns the motion down with a line in the log; only
        // then is one coasting stopped, and only then are the pictures cut.
        let cut = try XCTUnwrap(picturing.range(of: "motion.cut("))
        let pictured = try XCTUnwrap(picturing.range(
            of: "let scrolls = move.looked.compactMap { scrolling(in: $0) }"))
        let looked = try XCTUnwrap(picturing.range(
            of: "guard !scrolls.contains(where: { PaneMotion.isBouncing($0) }) else {"))
        let refused = try XCTUnwrap(picturing.range(
            of: "Diagnostics.log(.note, \"pane motion: bouncing; switched at once\")\n            return nil"))
        let held = try XCTUnwrap(picturing.range(of: "for scroll in scrolls { PaneMotion.holdStill(scroll) }"))
        let checked = try XCTUnwrap(picturing.range(of: "guard arranged == from else"))
        XCTAssertLessThan(checked.upperBound, pictured.lowerBound)
        XCTAssertLessThan(pictured.upperBound, looked.lowerBound)
        XCTAssertLessThan(looked.upperBound, refused.lowerBound)
        XCTAssertLessThan(refused.upperBound, held.lowerBound)
        XCTAssertLessThan(held.upperBound, cut.lowerBound)
        XCTAssertEqual(lines(of: code, containing: "holdStill("),
                       ["for scroll in scrolls { PaneMotion.holdStill(scroll) }"])
        XCTAssertEqual(lines(of: code, containing: "isBouncing("),
                       ["guard !scrolls.contains(where: { PaneMotion.isBouncing($0) }) else {"])
        XCTAssertEqual(lines(of: code, containing: "setContentOffset"), [])
        let scrolling = body(after: "func scrolling(in pane: PaneMove.Pane)", in: code)
        for line in ["case .mailboxes: return mailboxList.tableView",
                     "case .list: return list.tableView",
                     "case .message: return detail.letterScroll"] {
            XCTAssertTrue(scrolling.contains(line), line)
        }
        // Mail's rule: Reduce Motion changes nothing here.
        XCTAssertFalse(code.contains("isReduceMotionEnabled"))
        XCTAssertFalse(code.contains("prefersCrossFadeTransitions"))

        let turning = body(after: "override func viewWillTransition(", in: code)
        let ended = try XCTUnwrap(turning.range(of: "motion.finish()"))
        let resized = try XCTUnwrap(turning.range(of: "sizeColumns("))
        XCTAssertLessThan(ended.upperBound, resized.lowerBound)
        XCTAssertTrue(flat(body(after: "func watchForReturn(", in: code)).contains(
            "centre.addObserver(self, selector: #selector(lookingAway), "
            + "name: UIApplication.willResignActiveNotification, object: nil)"))
        XCTAssertTrue(body(after: "func lookingAway(", in: code).contains("motion.finish()"))
        XCTAssertEqual(lines(of: code, containing: "motion.finish()").count, 3)

        for handler in [body(after: "func viewButtonTapped(", in: code),
                        body(after: "func backToMailboxes(", in: code),
                        body(after: "mailboxList.onSelectMailbox = ", in: code)] {
            XCTAssertFalse(handler.contains("motion"), handler)
        }
        // Still just the two buttons that move the panes, each taken only
        // while nothing else is touched.
        XCTAssertEqual(code.components(separatedBy: "button.isExclusiveTouch = true").count - 1, 2)
    }

    /// `PaneMotion`, read. Pictures of the screen as it was, cut before
    /// anything is laid out, and of the panes as laid out, cut only once
    /// the cover is up with the screen as it was at its top, which goes
    /// only once every picture is in place. A cover that takes every
    /// touch, is hidden from VoiceOver and is the only thing put on the
    /// screen. Frames set sideways only and opacities, on Core Animation's
    /// spring with `Theme`'s mass, stiffness and critical damping for
    /// `Theme.paneMoveDuration`, the bars on `Theme`'s bar clock and the
    /// cross-fade on `Theme`'s curves, and no other clock; nothing of a
    /// real view touched; Prefer Cross-Fade Transitions read at every tap
    /// and Reduce Motion never; ended by taking the cover away, from the
    /// end of the motion if it is still its own and from a deadline that a
    /// slowed window stretches.
    func testTheMotionIsPicturesOnUIKitsSpring() throws {
        let code = try source("PaneMotion.swift")

        for line in ["cover.isUserInteractionEnabled = true",
                     "cover.accessibilityElementsHidden = true",
                     "autoresizingMask = []",
                     "holder.clipsToBounds = true",
                     "pictures.clipsToBounds = move.column != nil",
                     "cover.insertSubview(pictures, at: 0)",
                     "let total = max(Theme.paneMoveDuration, Theme.paneBarDuration)",
                     "let speed = max(Double(root.window?.layer.speed ?? 1), 0.05)",
                     "DispatchQueue.main.asyncAfter(deadline: .now() + total / speed + 1.0)",
                     "CATransaction.setCompletionBlock",
                     "let spring = CASpringAnimation(keyPath: keyPath)",
                     "spring.mass = CGFloat(Theme.paneSpringMass)",
                     "spring.stiffness = CGFloat(Theme.paneSpringStiffness)",
                     "spring.damping = CGFloat(Theme.paneSpringDamping)",
                     "spring.initialVelocity = 0",
                     "spring.duration = Theme.paneMoveDuration",
                     "animation.duration = Theme.paneBarDuration",
                     "animation.timingFunction = curve(Theme.paneBarCurve)",
                     "changes.append(.fade(holder, curve: Theme.paneCrossFadeCurve))",
                     "changes.append(.fade(bar, curve: Theme.paneBarCurve))"] {
            XCTAssertTrue(code.contains(line), line)
        }
        for never in ["UIView.animate", "withDuration", "UIViewPropertyAnimator",
                      "usingSpringWithDamping", "UISpringTimingParameters", ".repeat",
                      ".autoreverse", "transform", "isHidden =", "NSLayoutConstraint", ".constant",
                      "layoutIfNeeded", "tableView", "WKWebView", "navigationController",
                      "cover.alpha", "flexible", "isUserInteractionEnabled = false", "static let",
                      "isReduceMotionEnabled", "damping = 500", "allowsOverdamping",
                      "origin.y", "size.height ="] {
            XCTAssertFalse(code.contains(never), never)
        }
        // Every frame it makes sits at the top of the screen or under the
        // bars, and nothing is shifted down; a patch is put where its button
        // is in its picture.
        XCTAssertEqual(Set(lines(of: code, containing: "let top =")),
                       ["let top = strip.underBar ? barsBottom : 0"])
        for y in code.components(separatedBy: " y: ").dropFirst() {
            XCTAssertTrue(["0,", "top,", "barsBottom,", "0.5)"].contains { y.hasPrefix($0) },
                          String(y.prefix(40)))
        }
        for dy in code.components(separatedBy: "dy: ").dropFirst() {
            XCTAssertTrue(["0)", "-top)", "-span.minY)"].contains { dy.hasPrefix($0) },
                          String(dy.prefix(40)))
        }

        let crossFading = body(after: "static var crossFading: Bool", in: code)
        XCTAssertEqual(crossFading.trimmingCharacters(in: CharacterSet(charactersIn: "{} \n")),
                       "UIAccessibility.prefersCrossFadeTransitions")

        // Pictures of the screen as it was in `cut`, and only there; of the
        // panes as laid out in `play`, and only there, once the cover with
        // the screen as it was is up, before the screen as it was goes, and
        // before anything moves.
        XCTAssertEqual(lines(of: code, containing: "afterScreenUpdates:"),
                       ["root.resizableSnapshotView(from: span, afterScreenUpdates: false, withCapInsets: .zero)",
                        "pane.resizableSnapshotView(from: span, afterScreenUpdates: true, withCapInsets: .zero)"])
        let cutting = body(after: "func cut(", in: code)
        let playing = body(after: "func play(", in: code)
        XCTAssertFalse(cutting.contains("laidOut("))
        XCTAssertTrue(cutting.contains("still(of: bounds, in: root)"))
        XCTAssertFalse(playing.contains("still("))
        let veiled = try XCTUnwrap(playing.range(of: "cover.addSubview(veil)"))
        let covered = try XCTUnwrap(playing.range(of: "root.addSubview(cover)"))
        let firstLaidOut = try XCTUnwrap(playing.range(of: "laidOut("))
        let placed = try XCTUnwrap(playing.range(of: "cover.insertSubview(pictures, at: 0)"))
        let unveiled = try XCTUnwrap(playing.range(of: "cut.veil?.removeFromSuperview()"))
        let moving = try XCTUnwrap(playing.range(of: "CATransaction.begin()"))
        XCTAssertLessThan(veiled.upperBound, covered.lowerBound)
        XCTAssertLessThan(covered.upperBound, firstLaidOut.lowerBound)
        XCTAssertLessThan(firstLaidOut.upperBound, placed.lowerBound)
        XCTAssertLessThan(placed.upperBound, unveiled.lowerBound)
        XCTAssertLessThan(unveiled.upperBound, moving.lowerBound)
        // Each picture is checked against where the model says its pane is:
        // as it was where it was, as laid out where it is now.
        XCTAssertTrue(cutting.contains("misplaced(strip.pane, x: strip.x, width: strip.width, stage: stage)"))
        XCTAssertTrue(flat(playing).contains(
            "misplaced(strip.pane, x: strip.toX, width: strip.toShownWidth, stage: stage)"))
        // The glyph is drawn in the corner only when the pictures move.
        let glyph = try XCTUnwrap(cutting.range(of: "if move.motion == .spring {\n            guard stage.corner.window != nil"))
        XCTAssertLessThan(glyph.lowerBound, try XCTUnwrap(cutting.range(of: "let fresh = UIImageView(")).lowerBound)

        // Darkened and shadowed as the model says, on the spring.
        for line in ["dim.backgroundColor = .black", "dim.alpha = strip.dim",
                     "changes.append(.alpha(dim, to: strip.toDim))",
                     "shadow.alpha = strip.shadow",
                     "changes.append(.alpha(shadow, to: strip.toShadow))"] {
            XCTAssertTrue(playing.contains(line), line)
        }
        let applying = body(after: "private func apply(", in: code)
        for line in ["clock: .spring", "clock: .bars", "clock: .fade(curve)"] {
            XCTAssertTrue(applying.contains(line), line)
        }
        // Each change on its own clock: a frame and a darkening on the
        // spring; a bar's slide and its fade both on the bar clock, and
        // nothing else on it; a cross-fade on its curve.
        func clocks(of change: String, upTo next: String) throws -> [String] {
            let start = try XCTUnwrap(applying.range(of: "case .\(change)("), change)
            let end = try XCTUnwrap(applying.range(of: next, range: start.upperBound..<applying.endIndex),
                                    next)
            return applying[start.upperBound..<end.lowerBound]
                .components(separatedBy: "clock: .").dropFirst().map { String($0.prefix(while: { $0.isLetter })) }
        }
        XCTAssertEqual(try clocks(of: "frame", upTo: "case .alpha("), ["spring", "spring"])
        XCTAssertEqual(try clocks(of: "alpha", upTo: "case .bar("), ["spring"])
        XCTAssertEqual(try clocks(of: "bar", upTo: "case .fade("), ["bars", "bars"])
        XCTAssertEqual(try clocks(of: "fade", upTo: "\n    }"), ["fade"])
        XCTAssertEqual(applying.components(separatedBy: "clock: .bars").count - 1, 2)

        let finishing = body(after: "func finish(", in: code)
        XCTAssertTrue(finishing.contains("cover.removeFromSuperview()"), finishing)
        XCTAssertTrue(finishing.contains("self.cover = nil"), finishing)
        XCTAssertEqual(lines(of: code, containing: "removeFromSuperview()"),
                       ["cut.veil?.removeFromSuperview()", "cover.removeFromSuperview()"])
        // The deadline and the end of the motion act only for the cover
        // they were started for.
        XCTAssertEqual(lines(of: code, containing: "guard let self, cover === self.cover else { return }")
                        .count, 2)
        XCTAssertTrue(playing.contains("Diagnostics.log(.note, \"pane motion: deadline\")"), playing)

        // Coasting is stopped where it is, and only inside its ends; a
        // bounce is only looked at. Both reckon the ends from all four of
        // UIKit's insets, through `PaneMove.Rest`.
        let holding = body(after: "static func holdStill(", in: code)
        for line in ["let rest = rest(of: scroll)",
                     "guard scroll.isDecelerating, rest.holds(scroll.contentOffset) else { return }",
                     "scroll.setContentOffset(rest.clamped(scroll.contentOffset), animated: false)"] {
            XCTAssertTrue(holding.contains(line), line)
        }
        let bouncing = body(after: "static func isBouncing(", in: code)
        XCTAssertEqual(bouncing.trimmingCharacters(in: CharacterSet(charactersIn: "{} \n")),
                       "!rest(of: scroll).holds(scroll.contentOffset)")
        XCTAssertEqual(lines(of: code, containing: "setContentOffset"),
                       ["scroll.setContentOffset(rest.clamped(scroll.contentOffset), animated: false)"])
        XCTAssertTrue(flat(body(after: "func rest(of scroll: UIScrollView)", in: code)).contains(
            "let inset = scroll.adjustedContentInset return PaneMove.Rest(contentSize: scroll.contentSize, "
            + "viewSize: scroll.bounds.size, insetTop: inset.top, insetLeft: inset.left, "
            + "insetBottom: inset.bottom, insetRight: inset.right)"))

        // "No message selected": refused unless centred where the model
        // says; painted out of the letter's picture in the pane's canvas;
        // its own picture over the letter's and under the dividers, going
        // only as far as the model's middle goes.
        for line in ["if let middle = move.placeholder {",
                     "guard let placeholder = stage.placeholder, placeholder.window != nil else {",
                     "guard abs(frame.midX - middle.x) <= 0.5 else {",
                     "if strip.pane == .message, let label {",
                     "patches.append((label.frame, Theme.canvas))"] {
            XCTAssertTrue(cutting.contains(line), line)
        }
        XCTAssertTrue(flat(playing).contains(
            "changes.append(.frame(label.picture, to: label.frame.offsetBy(dx: label.middle.toX - label.middle.x, dy: 0)))"))
        let strips = try XCTUnwrap(playing.range(of: "for strip in move.strips {\n            guard let piece"))
        let riding = try XCTUnwrap(playing.range(of: "pictures.addSubview(label.picture)"))
        let dividers = try XCTUnwrap(playing.range(of: "for line in move.lines {"))
        XCTAssertLessThan(strips.upperBound, riding.lowerBound)
        XCTAssertLessThan(riding.upperBound, dividers.lowerBound)

        // The letter's side: read and nothing else, nothing loaded or drawn
        // again; and its bar holds no title and nothing on the left, so the
        // actions' picture is right at both ends.
        let detail = try source("MessageDetailViewController.swift")
        XCTAssertEqual(lines(of: detail, containing: "var letterScroll"),
                       ["var letterScroll: UIScrollView? { webView.isHidden ? nil : webView.scrollView }"])
        XCTAssertEqual(lines(of: detail, containing: "var emptyLabel"),
                       ["var emptyLabel: UIView? { placeholder.isHidden ? nil : placeholder }"])
        XCTAssertEqual(lines(of: detail, containing: "PaneMotion"), [])
        XCTAssertEqual(lines(of: detail, containing: "title ="), ["title = \"\""])
        XCTAssertEqual(lines(of: detail, containing: "leftBarButtonItem"), [])
        XCTAssertEqual(lines(of: detail, containing: "titleView"), [])
    }
}
