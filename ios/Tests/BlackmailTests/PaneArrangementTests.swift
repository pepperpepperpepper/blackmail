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
    /// after the view button and nil after anything else (B-066).
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

    /// Only the view button tells the container where the panes were, from
    /// each of the three places it can be tapped, since only its switch
    /// moves (B-066). "< Mailboxes", a folder tapped either way, a folder
    /// opened and a return to the list say nil, and are laid out with
    /// nothing moving.
    @MainActor
    func testOnlyTheViewButtonSaysWhereThePanesWere() {
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
        two.shell.tapped(inbox, showing: inbox)
        two.shell.back()
        two.shell.tapped(sent, showing: inbox)
        two.shell.open(receipts)
        two.shell.showList()
        let three = Container(launching: .three)
        three.shell.tapped(sent, showing: inbox)
        three.shell.showList()
        for told in two.take() + three.take() {
            if case .laidOut(_, _, let from) = told { XCTAssertNil(from, "\(told)") }
        }
    }

    /// "< Mailboxes" lays out the folders, and opens nothing.
    @MainActor
    func testMailboxesLaysOutTheFoldersAndOpensNothing() {
        let container = Container(launching: .two)
        container.shell.back()
        XCTAssertEqual(container.take(), [.laidOut(.two, .mailboxes, from: nil)])
    }

    /// In two panes the folder already open is laid out in front and not
    /// opened; another is opened, and then laid out in front, in that order,
    /// since laying out dresses the list's bar and it has to be the new
    /// list's. In three, every tap opens.
    @MainActor
    func testATapOpensAnotherFolderAndShowsTheOpenOnesList() {
        let two = Container(launching: .two)
        two.shell.back()
        _ = two.take()
        two.shell.tapped(inbox, showing: .inboxBeforeListing)
        XCTAssertEqual(two.take(), [.laidOut(.two, .list, from: nil)])
        two.shell.back()
        _ = two.take()
        two.shell.tapped(sent, showing: inbox)
        XCTAssertEqual(two.take(), [.opened(sent.id), .laidOut(.two, .list, from: nil)])

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

    // MARK: - The switch, moving

    /// `text` with every run of spaces and line breaks made one space.
    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).joined(separator: " ")
    }

    /// The container's half of B-066, read: the pictures are cut before
    /// anything is laid out, from the screen as laid out, with coasting
    /// stopped first and Reduce Motion asked at the tap; the panes are then
    /// laid out exactly as before, the layout sweep runs on them, and only
    /// then do the pictures go over them. A switch still moving is ended
    /// before anything lays the panes out, before the iPad turns, and as
    /// the app stops being in front. The buttons hand over to the shell
    /// and know nothing of the motion.
    func testTheSwitchMovesPicturesOverPanesAlreadyLaidOut() throws {
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
        let sweeping = try XCTUnwrap(arranging.range(of: "LayoutAudit.panesChanged(to: describe(panes))"))
        let playing = try XCTUnwrap(arranging.range(of: "if let cut { motion.play(cut) }"))
        XCTAssertLessThan(sweeping.upperBound, playing.lowerBound)
        XCTAssertEqual(lines(of: code, containing: "motion.play("), ["if let cut { motion.play(cut) }"])
        XCTAssertEqual(lines(of: code, containing: "motion.cut("),
                       ["return motion.cut(move, stage: stage, dissolving: PaneMotion.dissolving)"])

        let picturing = body(after: "func pictures(", in: code)
        for line in ["let emptyLabel = detail.emptyLabel",
                     "PaneMove.switching(from: from, to: panes, screenWidth: screenWidth,",
                     "reading: emptyLabel == nil ? .words : .nothing) else {",
                     "guard arranged == from else",
                     "tapped: from.leftColumn == .list ? listViewButton : mailboxesViewButton",
                     "listTwin: listViewButton, letterBar: detailNav.navigationBar, placeholder: emptyLabel",
                     "root: view, mailboxes: mailboxNav.view, list: listNav.view, message: detailNav.view",
                     "dissolving: PaneMotion.dissolving"] {
            XCTAssertTrue(picturing.contains(line), line)
        }
        // A list or letter bouncing past an end, in any pane pictured, is
        // looked for before anything is touched, and turns the motion down
        // with a line in the log; only then is one coasting stopped, and
        // only then are the pictures cut.
        let cut = try XCTUnwrap(picturing.range(of: "motion.cut("))
        let pictured = try XCTUnwrap(picturing.range(
            of: "let scrolls = move.strips.compactMap { scrolling(in: $0.pane) }"))
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
        // Every pane pictured is looked at: the Mailboxes, the list and the
        // letter, when there is one.
        let scrolling = body(after: "func scrolling(in pane: PaneMove.Pane)", in: code)
        for line in ["case .mailboxes: return mailboxList.tableView",
                     "case .list: return list.tableView",
                     "case .message: return detail.letterScroll"] {
            XCTAssertTrue(scrolling.contains(line), line)
        }

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
                        body(after: "func backToMailboxes(", in: code)] {
            XCTAssertFalse(handler.contains("motion"), handler)
        }
        // Still just the two buttons that move the panes, each taken only
        // while nothing else is touched.
        XCTAssertEqual(code.components(separatedBy: "button.isExclusiveTouch = true").count - 1, 2)
    }

    /// `PaneMotion`, read: pictures of the screen as it was, never as the
    /// next frame will draw it; a cover that takes every touch, is hidden
    /// from VoiceOver and is the only thing put on the screen; frames set
    /// sideways only, eased in and out, for the durations of
    /// `PaneMove.timeline` and no others; nothing of a real view touched;
    /// Reduce Motion and Prefer Cross-Fade Transitions read at every tap;
    /// ended by taking the cover away, from every completion that is still
    /// its own and from a deadline that a slowed window stretches.
    func testTheMotionIsPicturesMovedSidewaysOnly() throws {
        let code = try source("PaneMotion.swift")

        for line in ["afterScreenUpdates: false",
                     ".curveEaseInOut",
                     "PaneMove.timeline(dissolving: dissolving)",
                     "for phase in cut.timeline",
                     "cover.isUserInteractionEnabled = true",
                     "cover.accessibilityElementsHidden = true",
                     "autoresizingMask = []",
                     "holder.clipsToBounds = true",
                     "pictures.alpha = 0",
                     "let speed = max(Double(cut.root.window?.layer.speed ?? 1), 0.05)",
                     "DispatchQueue.main.asyncAfter(deadline: .now() + total / speed + 1.0)",
                     "let total = cut.timeline.map(\\.duration).reduce(0, +)"] {
            XCTAssertTrue(code.contains(line), line)
        }
        for never in ["afterScreenUpdates: true", "isHidden", "NSLayoutConstraint", ".constant",
                      "layoutIfNeeded", "transform", "UIViewPropertyAnimator",
                      "usingSpringWithDamping", "UISpringTimingParameters", ".repeat",
                      ".autoreverse", "origin.y", "size.height =", "withDuration: 0.",
                      "tableView", "WKWebView", "navigationController", "cover.alpha",
                      "flexible", "isUserInteractionEnabled = false", "static let"] {
            XCTAssertFalse(code.contains(never), never)
        }
        // Every frame it makes sits at the top of the screen, or under the
        // bars for the backdrop's hairline, and nothing is shifted down.
        for y in code.components(separatedBy: " y: ").dropFirst() {
            XCTAssertTrue(y.hasPrefix("0,") || y.hasPrefix("barsBottom,"), String(y.prefix(40)))
        }
        for dy in code.components(separatedBy: "dy: ").dropFirst() {
            XCTAssertTrue(dy.hasPrefix("0)"), String(dy.prefix(40)))
        }
        // Each animation goes for a duration out of the timeline.
        for duration in code.components(separatedBy: "withDuration: ").dropFirst() {
            XCTAssertTrue(["slide,", "duration,"].contains { duration.hasPrefix($0) },
                          String(duration.prefix(40)))
        }

        let dissolving = body(after: "static var dissolving: Bool", in: code)
        XCTAssertTrue(dissolving.contains("UIAccessibility.isReduceMotionEnabled"), dissolving)
        XCTAssertTrue(dissolving.contains("UIAccessibility.prefersCrossFadeTransitions"), dissolving)

        let finishing = body(after: "func finish(", in: code)
        XCTAssertTrue(finishing.contains("cover.removeFromSuperview()"), finishing)
        XCTAssertTrue(finishing.contains("self.cover = nil"), finishing)
        XCTAssertEqual(lines(of: code, containing: "removeFromSuperview()"),
                       ["cover.removeFromSuperview()"])
        // The deadline, the slide's end and the fade's end act only for the
        // cover they were started for.
        XCTAssertEqual(lines(of: code, containing: "guard let self, cover === self.cover else { return }")
                        .count, 3)
        let playing = body(after: "func play(", in: code)
        XCTAssertTrue(playing.contains("guard finished else { self.finish(); return }"), playing)
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
        let cutting = body(after: "func cut(", in: code)
        for line in ["if let middle = move.placeholder {",
                     "guard let placeholder = stage.placeholder, placeholder.window != nil else {",
                     "guard abs(frame.midX - middle.x) <= 0.5 else {",
                     "if strip.pane == .message, let label {",
                     "let patch = UIView(frame: label.frame.offsetBy(dx: -strip.x, dy: 0))",
                     "label.frame.offsetBy(dx: label.middle.toX - label.middle.x, dy: 0)))"] {
            XCTAssertTrue(cutting.contains(line), line)
        }
        let patching = body(after: "if strip.pane == .message, let label", in: cutting)
        XCTAssertTrue(patching.contains("patch.backgroundColor = Theme.canvas"), patching)
        let strips = try XCTUnwrap(cutting.range(of: "for strip in move.strips {\n            let span"))
        let riding = try XCTUnwrap(cutting.range(of: "pictures.addSubview(label.picture)"))
        let dividers = try XCTUnwrap(cutting.range(of: "for line in move.lines {"))
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
