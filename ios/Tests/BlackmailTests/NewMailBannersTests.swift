import XCTest
@testable import Blackmail

/// The red number on the icon and the banners for new mail, as Mail gives
/// them from the factory (B-161): the check iOS wakes the app for, run as
/// the app runs it, `InboxCheck` over the shipping client and
/// `ScriptedIMAPServer`, its state in a file of the test's own; the
/// banners' words, the number, iOS's question, and the safe start's count
/// for a check. The UIKit half that registers the check, puts the banners
/// up and opens a tapped one is read from its source.
@MainActor
final class NewMailBannersTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private var server: ScriptedIMAPServer!
    private var clock: ManualClock!
    private var base: URL!
    private var store: BannerStore!

    /// After every seeded letter: he left the app a minute after the
    /// newest one came.
    private let left = Server.newestDate.addingTimeInterval(60)

    override func setUp() async throws {
        try await super.setUp()
        server = ScriptedIMAPServer()
        clock = ManualClock()
        base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NewMailBannersTests-\(UUID().uuidString)", isDirectory: true)
        store = BannerStore(file: base.appendingPathComponent("New Mail/state.json"))
    }

    override func tearDown() async throws {
        if let server { XCTAssertEqual(server.violations, []) }
        if let base { try? FileManager.default.removeItem(at: base) }
        server = nil
        clock = nil
        base = nil
        store = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// One check, signing in with `password`, the server's by default.
    private func check(password: String? = nil) async -> InboxCheck.Found? {
        let clock = self.clock!
        return await InboxCheck(account: server.account, password: password ?? server.password,
                                transport: server.transportFactory, store: store,
                                now: { clock.now() }).run()
    }

    /// A check that had something from the server.
    private func checked(file: StaticString = #filePath,
                         line: UInt = #line) async throws -> InboxCheck.Found {
        let found = await check()
        return try XCTUnwrap(found, file: file, line: line)
    }

    private var verbs: [String] { server.log.map(\.verb) }

    private var inboxHighest: UInt32 { server.uids(in: Server.inbox).last ?? 0 }

    /// What the app keeps once he has left it, after a check that left the
    /// Inbox's mark at its newest letter.
    private func leftAfterACheck() {
        let mark = InboxMark(validity: server.uidValidity(of: Server.inbox), uid: inboxHighest)
        store.update {
            $0.mark = mark
            $0.leftAt = left
        }
    }

    /// A letter to him that reached the Inbox `after` seconds after he left.
    @discardableResult
    private func arrives(_ subject: String, from: Server.Address = Server.sam,
                         after: TimeInterval = 3_600, text: String? = "Lunch on Sunday?\r\n",
                         read: Bool = false) -> UInt32 {
        var letter = Server.Letter(from: from, to: [Server.owner], subject: subject,
                                   date: left.addingTimeInterval(after), text: text,
                                   messageID: "<\(UUID().uuidString)@example.com>")
        if read { letter.flags = ["\\Seen"] }
        return server.arrive(letter, in: [Server.inbox, Server.allMail])[Server.inbox]!
    }

    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    // MARK: - The check

    /// The first check, before he has ever left the app: where the Inbox
    /// goes is written down, and nothing else is asked or put up. LOGIN,
    /// one STATUS, LOGOUT. The count is the Inbox's unread letters, the
    /// folder pane's number.
    func testTheFirstCheckOnlyMarksWhereTheInboxGoes() async throws {
        let found = try await checked()
        XCTAssertEqual(found, InboxCheck.Found(unread: 6, banners: []))
        XCTAssertEqual(verbs, ["LOGIN", "STATUS", "LOGOUT"])
        XCTAssertEqual(server.log[1].command, "STATUS \"INBOX\" (UNSEEN UIDNEXT UIDVALIDITY)")
        // UIDNEXT less one: at or above the newest letter, as Gmail's UIDs
        // leave gaps.
        let mark = try XCTUnwrap(store.load().mark)
        XCTAssertEqual(mark.validity, server.uidValidity(of: Server.inbox))
        XCTAssertGreaterThanOrEqual(mark.uid, inboxHighest)
        XCTAssertLessThan(mark.uid, arrives("Next"))
        XCTAssertEqual(store.load().checkedAt, clock.now())
    }

    /// Letters that reached the Inbox after he left: a banner each, oldest
    /// first, so the newest is on top, the sender's name over the subject
    /// and the first of the letter's words, as Mail's banner has them. The
    /// letters stay unread and where they were: nothing is sent that marks,
    /// moves or writes, and nothing of SMTP.
    func testALetterThatCameAfterHeLeftHasItsBanner() async throws {
        leftAfterACheck()
        let first = arrives("Sunday", after: 600)
        let second = arrives("", from: Server.carlo, after: 1_200, text: "The roof is done.\r\n")
        let validity = server.uidValidity(of: Server.inbox)

        let found = try await checked()

        XCTAssertEqual(found.unread, 8)
        XCTAssertEqual(found.banners, [
            NewMailBanners.Banner(id: "\(validity)/\(first)",
                                  gmailMessageID: server.gmailMessageID(uid: first, in: Server.inbox),
                                  title: "Sam Example", subtitle: "Sunday", body: "Lunch on Sunday?"),
            NewMailBanners.Banner(id: "\(validity)/\(second)",
                                  gmailMessageID: server.gmailMessageID(uid: second, in: Server.inbox),
                                  title: "Carlo", subtitle: "(no subject)",
                                  body: "The roof is done."),
        ])
        XCTAssertEqual(verbs, ["LOGIN", "STATUS", "SELECT", "UID SEARCH", "UID FETCH", "UID FETCH",
                               "LOGOUT"])
        XCTAssertTrue(server.log[3].command.hasPrefix("UID SEARCH UNSEEN UID "))
        XCTAssertTrue(server.log[5].command.contains("BODY.PEEK["), server.log[5].command)
        for uid in [first, second] {
            XCTAssertFalse(server.flags(uid: uid, in: Server.inbox).contains("\\Seen"))
        }
        XCTAssertEqual(store.load().mark?.uid, second)
    }

    /// Nothing above the last check's mark: no SELECT, no SEARCH, and no
    /// banner a second time for a letter that has had one.
    func testEachLetterHasOneBannerAndAQuietInboxCostsOneStatus() async throws {
        leftAfterACheck()
        arrives("Sunday")
        let firstCheck = try await checked()
        XCTAssertEqual(firstCheck.banners.count, 1)
        server.clearLog()

        let second = try await checked()
        XCTAssertEqual(second.banners, [])
        XCTAssertEqual(second.unread, 7)
        XCTAssertEqual(verbs, ["LOGIN", "STATUS", "LOGOUT"])
    }

    /// No banner for a letter already read, on the phone perhaps, nor for
    /// one that came while he was in the app, which was on the list, as
    /// Mail puts up none for mail that comes while it is in front.
    func testNoBannerForALetterReadOrOneThatCameWhileHeWasInTheApp() async throws {
        leftAfterACheck()
        arrives("While he read", after: -30)
        arrives("Read on the phone", read: true)
        let new = arrives("Sunday")

        let found = try await checked()
        XCTAssertEqual(found.banners.map(\.subtitle), ["Sunday"])
        XCTAssertEqual(found.banners.first?.id, "\(server.uidValidity(of: Server.inbox))/\(new)")
    }

    /// After a day away, the newest `most` letters, not a column of every
    /// one; the older ones are not bannered later either.
    func testAtMostTheNewestTwentyBanners() async throws {
        leftAfterACheck()
        let uids = (1...25).map { arrives("Letter \($0)", after: Double($0) * 60) }

        let found = try await checked()
        XCTAssertEqual(found.banners.map(\.subtitle), (6...25).map { "Letter \($0)" })
        XCTAssertEqual(store.load().mark?.uid, uids.last)
        server.clearLog()
        let next = try await checked()
        XCTAssertEqual(next.banners, [])
    }

    /// The mark is written before any letter is fetched: a check that ends
    /// at its FETCH, a letter's summary that crashes it or the connection
    /// lost, never fetches those letters again, so a letter that ends
    /// every check is asked for once.
    func testTheMarkIsKeptBeforeAnyLetterIsFetched() async throws {
        leftAfterACheck()
        let new = arrives("Sunday")
        server.holdReplies(to: "UID FETCH")
        let running = Task { await self.check() }
        for _ in 0..<1_000 {
            if await server.heldReplies(to: "UID FETCH") > 0 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(store.load().mark?.uid, new, "kept as STATUS said it, before the FETCH")
        await server.resetConnections()
        let ended = await running.value
        XCTAssertNil(ended)
        server.stopHolding("UID FETCH")
        server.clearLog()

        let next = try await checked()
        XCTAssertEqual(next.banners, [])
        XCTAssertEqual(verbs, ["LOGIN", "STATUS", "LOGOUT"])
    }

    /// A sign-in refused is not sent again by a check until he has been
    /// back in the app (`NewMailTask.cameToFront`): nothing connects.
    func testARefusedSignInIsNotSentAgainUntilHeIsBack() async throws {
        leftAfterACheck()
        let revoked = server.password
        server.replacePassword(with: "another-password")
        let refused = await check(password: revoked)
        XCTAssertNil(refused)
        XCTAssertEqual(store.load().refusedAt, clock.now())
        XCTAssertEqual(verbs, ["LOGIN"])
        server.clearLog()

        let held = await check(password: revoked)
        XCTAssertNil(held)
        XCTAssertEqual(server.log, [], "no password sent")

        store.update { $0.refusedAt = nil }
        _ = await check(password: revoked)
        XCTAssertEqual(verbs, ["LOGIN"])
    }

    /// A renumbered Inbox, or a mark lost: the unread letters since the day
    /// before he left are searched, and still only those that came after
    /// he left have banners.
    func testARenumberedInboxStartsFromTheDayHeLeft() async throws {
        store.update {
            $0.mark = InboxMark(validity: 1, uid: 99)
            $0.leftAt = left
        }
        arrives("While he read", after: -30)
        arrives("Sunday")

        let found = try await checked()
        XCTAssertEqual(found.banners.map(\.subtitle), ["Sunday"])
        XCTAssertTrue(server.log[3].command.hasPrefix("UID SEARCH UNSEEN SINCE \""),
                      server.log[3].command)
        XCTAssertEqual(store.load().mark?.validity, server.uidValidity(of: Server.inbox))
    }

    // MARK: - The banner, the number and the question

    /// The banner's words: the row's name for the sender, its words for no
    /// subject, and a line of words cut at `longestLine`; a tap hands back
    /// the letter, and a banner the app did not make names none.
    func testTheBannersWordsAndItsTap() async throws {
        var envelope = IMAPEnvelope()
        envelope.from = [MailAddress(name: nil, mailbox: "jane", host: "example.com")]
        let words = String(repeating: "word ", count: 200)
        let banner = NewMailBanners.banner(id: "600001/1300", gmailMessageID: 42,
                                           envelope: envelope, preview: "  " + words)
        XCTAssertEqual(banner.title, "jane@example.com")
        XCTAssertEqual(banner.subtitle, "(no subject)")
        XCTAssertEqual(banner.body.count, NewMailBanners.longestLine)
        XCTAssertEqual(banner.identifier, "INBOX/600001/1300")

        let tapped = NewMailBanners.Tapped(userInfo: banner.userInfo)
        XCTAssertEqual(tapped, NewMailBanners.Tapped(id: "600001/1300", gmailMessageID: 42))
        XCTAssertNil(NewMailBanners.Tapped(userInfo: ["aps": "x"]))
        XCTAssertNil(NewMailBanners.Tapped(userInfo: [NewMailBanners.Tapped.letterKey: "INBOX"]))
    }

    /// The number is the count the app was last told; a count not known
    /// leaves it, and leaving the app sets it again.
    func testTheNumberFollowsTheCountTheAppLearns() async throws {
        var set: [Int] = []
        let badge = AppBadge { set.append($0) }
        badge.again()
        badge.counted(nil)
        XCTAssertEqual(set, [])
        badge.counted(7)
        badge.counted(6)
        badge.counted(-1)
        badge.again()
        XCTAssertEqual(set, [7, 6, 0, 0])
    }

    /// iOS's question goes once, the first time the Inbox's list has come,
    /// and never over a sheet, under his finger or with the app not in front.
    func testTheQuestionIsAskedOnceAtAMomentThatInterruptsNothing() async throws {
        var question = BannerQuestion()
        XCTAssertFalse(question.due(inboxListed: false, sheetUp: false, inHand: false, inFront: true))
        XCTAssertFalse(question.due(inboxListed: true, sheetUp: true, inHand: false, inFront: true))
        XCTAssertFalse(question.due(inboxListed: true, sheetUp: false, inHand: true, inFront: true))
        XCTAssertFalse(question.due(inboxListed: true, sheetUp: false, inHand: false, inFront: false))
        XCTAssertTrue(question.due(inboxListed: true, sheetUp: false, inHand: false, inFront: true))
        XCTAssertFalse(question.due(inboxListed: true, sheetUp: false, inHand: false, inFront: true))
    }

    /// The counts are swept as he comes back only after a check has had the
    /// count since he left.
    func testTheCountsAreSweptOnReturnOnlyAfterACheck() async throws {
        var state = BannerState()
        XCTAssertFalse(state.checkedSinceLeaving)
        state.leftAt = left
        state.checkedAt = left.addingTimeInterval(-1)
        XCTAssertFalse(state.checkedSinceLeaving)
        state.checkedAt = left.addingTimeInterval(1)
        XCTAssertTrue(state.checkedSinceLeaving)
    }

    // MARK: - The safe start

    private func makeStart() -> SafeStart {
        let support = base.appendingPathComponent("Application Support", isDirectory: true)
        let defaults = UserDefaults(suiteName: "NewMailBannersTests")!
        return SafeStart(directory: support.appendingPathComponent("Launches", isDirectory: true),
                         kept: support.appendingPathComponent("Kept", isDirectory: true),
                         searches: support.appendingPathComponent("Recent Searches.json"),
                         letters: support.appendingPathComponent("Local Drafts", isDirectory: true),
                         defaults: defaults, log: { _ in }, wait: { _ in })
    }

    private var count: Int { SafeStart.unfinished(in: makeStart().directory) }

    /// A check is counted as a launch is, and finished as it ends; one goes
    /// only with no launch, and no check, unfinished.
    func testACheckIsCountedAndGoesOnlyWithNothingUnfinished() async throws {
        let start = makeStart()
        XCTAssertTrue(start.checkBegins())
        XCTAssertEqual(count, 1)
        XCTAssertFalse(start.checkBegins(), "one at a time")
        start.checkEnded()
        XCTAssertEqual(count, 0)

        let launched = makeStart()
        launched.launch()
        XCTAssertFalse(launched.checkBegins(), "a launch not yet finished")
        XCTAssertEqual(count, 1)
    }

    /// A check that crashed holds the next one, and the next launch counts
    /// it as one launch unfinished, which takes no step; once that launch
    /// has finished, checks go again. Checks alone never take the count
    /// past one.
    func testACheckThatCrashedHoldsTheNextAndCountsAsOne() async throws {
        XCTAssertTrue(makeStart().checkBegins())
        for _ in 0..<5 { XCTAssertFalse(makeStart().checkBegins()) }
        XCTAssertEqual(count, 1)

        let launch = makeStart()
        XCTAssertEqual(launch.launch(), SafeStart.Steps(after: 1))
        XCTAssertFalse(launch.steps.forgetsKeptState)
        launch.finished()
        XCTAssertTrue(makeStart().checkBegins())
    }

    /// He opens the app while a check is on its way in the same process:
    /// the check's count is taken back, and the launch counts from none.
    func testALaunchDuringACheckTakesItsCountBack() async throws {
        let start = makeStart()
        XCTAssertTrue(start.checkBegins())
        XCTAssertEqual(start.launch(), SafeStart.Steps(after: 0))
        XCTAssertEqual(count, 1, "the launch's own")
        start.checkEnded()
        XCTAssertEqual(count, 1, "the launch's, not taken back by the check's end")
    }

    // MARK: - What the app tells iOS, and the UIKit half

    /// The check's name is in Info.plist, or iOS ends the app as it
    /// registers it; the background mode is the refresh's alone, with no
    /// push, and nothing outside the iPad sends the app anything.
    func testTheCheckIsNamedInInfoPlistAndNothingIsPushed() async throws {
        let ios = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: ios.appendingPathComponent("Resources/Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil)
                                 as? [String: Any])
        XCTAssertEqual(info["BGTaskSchedulerPermittedIdentifiers"] as? [String],
                       [NewMailBanners.taskIdentifier])
        XCTAssertEqual(info["UIBackgroundModes"] as? [String], ["fetch"])
        for name in ["Blackmail.entitlements", "BlackmailWithShare.entitlements"] {
            let entitlements = try String(contentsOf: ios.appendingPathComponent("Resources/\(name)"),
                                          encoding: .utf8)
            XCTAssertFalse(entitlements.contains("aps-environment"), name)
        }
    }

    /// The UIKit half, read from its source: registered at every launch; a
    /// launch into the background starts nothing of the app; the number
    /// set where the folder pane learns the Inbox's count and as he leaves;
    /// no banner while the app is in front; iOS's question once the Inbox's
    /// list has come; a check called off as he comes back, before the
    /// launch is counted.
    func testTheAppSideIsWiredWhereItSays() async throws {
        let delegate = try source("Sources/Blackmail/App/AppDelegate.swift")
        XCTAssertTrue(delegate.contains("-> Bool { if application.applicationState != .background "
                                        + "{ start() } NewMailTask.register() "
                                        + "UNUserNotificationCenter.current().delegate = self "
                                        + "return true }"))
        XCTAssertTrue(delegate.contains("Self.syncShareMirror(readingContacts: false) if window != nil "
                                        + "{ NewMailTask.leaving() } }"))
        XCTAssertTrue(delegate.contains("{ Diagnostics.wentAwayOrCameBack() "
                                        + "NewMailTask.cameToFront() start() "
                                        + "Self.syncShareMirror() }"))
        XCTAssertTrue(delegate.contains("completionHandler([])"))

        let folders = try source("Sources/Blackmail/UI/MailboxListViewController.swift")
        XCTAssertTrue(folders.contains("counted = true AppBadge.app.counted(inboxUnread)"))
        XCTAssertTrue(folders.contains("configure(cell, with: folder) patched = true } "
                                       + "if patched, Theme.textSize != .factory { "
                                       + "tableView.beginUpdates() tableView.endUpdates() } "
                                       + "AppBadge.app.counted(inboxUnread) }"))

        let root = try source("Sources/Blackmail/UI/RootViewController.swift")
        // The address book's fill from Sent Mail (B-155) between, as merged.
        XCTAssertTrue(root.contains("self?.firstPageTried = true self?.askForBannersIfDue() "
                                    + "self?.openTappedBanner() if came,"))
        XCTAssertTrue(root.contains("self?.fillBookOnce() } self?.watch.start()"))
        XCTAssertTrue(root.contains("lastCheckFailed = true return } askForBannersIfDue() "
                                    + "guard lastCheckFailed else { return }"))

        let task = try source("Sources/Blackmail/App/NewMailTask.swift")
        XCTAssertTrue(task.contains("guard !Task.isCancelled, "
                                    + "UIApplication.shared.applicationState == .background, "
                                    + "SafeStart.app.checkBegins() else"))
        XCTAssertTrue(task.contains("requestAuthorization(options: [.alert, .badge])"))
        XCTAssertTrue(task.contains("guard !Task.isCancelled, "
                                    + "UIApplication.shared.applicationState == .background else"))
    }

    /// A check goes only with the iPad on charge and on Wi-Fi, as Mail's
    /// factory Fetch, Automatically, fetches in the background (Apple's
    /// 102578), read from the source: charging or full, the path up over
    /// Wi-Fi, no answer counting as not; looked at before the check is
    /// counted, and a check held there ends at once as a success, the next
    /// one already asked for.
    func testTheCheckGoesOnlyOnChargeAndWiFiAsMailFetches() async throws {
        let task = try source("Sources/Blackmail/App/NewMailTask.swift")
        XCTAssertTrue(task.contains("private static func run(_ task: BGTask) { schedule() "
                                    + "guard running == nil, "
                                    + "UIApplication.shared.applicationState == .background else {"))
        XCTAssertTrue(task.contains("let work = Task { @MainActor in "
                                    + "guard await mailWouldFetch() else { "
                                    + "Diagnostics.log(.note, \"NEW-MAIL held not-charging-on-wifi\") "
                                    + "end(true) return } "
                                    + "guard !Task.isCancelled, "
                                    + "UIApplication.shared.applicationState == .background, "
                                    + "SafeStart.app.checkBegins() else {"))
        XCTAssertTrue(task.contains("device.isBatteryMonitoringEnabled = true "
                                    + "let power = device.batteryState "
                                    + "device.isBatteryMonitoringEnabled = false "
                                    + "guard power == .charging || power == .full else { return false } "
                                    + "return await onWiFi() }"))
        XCTAssertTrue(task.contains("answer(path.status == .satisfied && path.usesInterfaceType(.wifi))"))
        XCTAssertTrue(task.contains("queue.asyncAfter(deadline: .now() + 2) { answer(false) }"))
    }

    /// A tapped banner opens its letter, read from the source: the
    /// notification centre's delegate hands a banner this app made to the
    /// root, starting the app first; the root opens it now, or once the
    /// launch's first page has been tried, never over a sheet; the Inbox in
    /// front, or opened, and the letter's row opened as a tap opens it, at
    /// once or once the list has been fetched again from its newest.
    func testATappedBannerOpensItsLetter() async throws {
        let delegate = try source("Sources/Blackmail/App/AppDelegate.swift")
        XCTAssertTrue(delegate.contains("defer { completionHandler() } "
                                        + "guard response.actionIdentifier == UNNotificationDefaultActionIdentifier, "
                                        + "let letter = NewMailBanners.Tapped( "
                                        + "userInfo: response.notification.request.content.userInfo) "
                                        + "else { return } start() "
                                        + "(window?.rootViewController as? RootViewController)?"
                                        + ".openFromBanner(letter)"))

        let root = try source("Sources/Blackmail/UI/RootViewController.swift")
        XCTAssertTrue(root.contains("func openFromBanner(_ letter: NewMailBanners.Tapped) { "
                                    + "guard !ErrorPresenter.over(self).sheetOpen else { return } "
                                    + "guard firstPageTried else { bannerTapped = letter return } "
                                    + "open(letter) }"))
        XCTAssertTrue(root.contains("private func openTappedBanner() { "
                                    + "guard let letter = bannerTapped else { return } "
                                    + "bannerTapped = nil "
                                    + "guard !ErrorPresenter.over(self).sheetOpen else { return } "
                                    + "open(letter) }"))
        XCTAssertTrue(root.contains("private func open(_ letter: NewMailBanners.Tapped) { "
                                    + "guard list.shownMailbox.role == .inbox else { "
                                    + "let inbox = mailboxList.mailbox(for: .inbox) ?? .inboxBeforeListing "
                                    + "shell.open(inbox) mailboxList.select(mailboxID: inbox.id) "
                                    + "list.onFirstLoadFinished = { [weak self] _ in "
                                    + "_ = self?.list.openRow(of: letter.id, letter: letter.gmailMessageID) } "
                                    + "return } shell.showList() "
                                    + "if list.openRow(of: letter.id, letter: letter.gmailMessageID) { return } "
                                    + "let list = self.list Task { @MainActor in "
                                    + "guard await list.returnToNewest() else { return } "
                                    + "_ = list.openRow(of: letter.id, letter: letter.gmailMessageID) } }"))

        let list = try source("Sources/Blackmail/UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains("func openRow(of id: String, letter: UInt64?) -> Bool { "
                                    + "guard !inEditMode, let row = rowIndex(showing: id) "
                                    + "else { return false } "
                                    + "if let letter, let listed = letters.letter(id)?.gmailMessageID, "
                                    + "listed != letter { return false } "
                                    + "let at = IndexPath(row: row, section: 0) "
                                    + "tableView.selectRow(at: at, animated: false, scrollPosition: .none) "
                                    + "tableView.scrollToRow(at: at, at: .none, animated: false) "
                                    + "tableView(tableView, didSelectRowAt: at) return true }"))
    }
}
