import XCTest

/// Print wired into the reading pane (B-110): the Reply sheet's fourth row,
/// and the job that draws the letter into a PDF and hands AirPrint's panel
/// its bytes (`LetterPrint`).
///
/// Both are UIKit and WebKit and never build on this host, so they are read
/// from their source, as `PaneNavigationTests` reads the pane's: comment
/// lines out, and runs of white space as one space. What each event means
/// is `PrintSteps`', tested on its own.
final class PrintWiringTests: XCTestCase {

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

    private func place(of text: String, in code: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String.Index? {
        let found = code.range(of: text)?.lowerBound
        XCTAssertNotNil(found, text, file: file, line: line)
        return found
    }

    private func count(_ text: String, in code: String) -> Int {
        code.components(separatedBy: text).count - 1
    }

    /// The code from `start` up to `end`, both found.
    private func part(of code: String, from start: String, to end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start))
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex))
        return String(code[from.lowerBound..<to.lowerBound])
    }

    private var pane: String { get throws { try source("UI/MessageDetailViewController.swift") } }
    private var job: String { get throws { try source("UI/LetterPrint.swift") } }

    // MARK: - The Reply sheet

    /// Reply, Reply All, Forward, Print, then Cancel, as Mail's Reply
    /// button had them; Print greyed only while a print is made ready, and
    /// given the sheet's own letter, the one the header shows.
    func testPrintIsTheSheetsFourthRow() throws {
        let sheet = try part(of: pane, from: "@objc private func replyTapped() {",
                             to: "private func printLetter(")
        XCTAssertTrue(sheet.hasPrefix("@objc private func replyTapped() { guard let m = message else { return }"))
        var last = sheet.startIndex
        for row in ["UIAlertAction(title: \"Reply\", style: .default)",
                    "UIAlertAction(title: \"Reply All\", style: .default)",
                    "UIAlertAction(title: \"Forward\", style: .default)",
                    "let printRow = UIAlertAction(title: \"Print\", style: .default) { [weak self] _ in "
                        + "self?.printLetter(m) }",
                    "printRow.isEnabled = printing?.isPreparing != true sheet.addAction(printRow) "
                        + "sheet.addAction(UIAlertAction(title: \"Cancel\", style: .cancel)) "
                        + "present(sheet, animated: true)"] {
            let at = try XCTUnwrap(place(of: row, in: sheet), row)
            XCTAssertGreaterThanOrEqual(at, last, row)
            last = at
        }
        XCTAssertEqual(count("UIAlertAction(title:", in: sheet), 5)
        XCTAssertEqual(count("\"Print\"", in: try pane), 1)
        // No button of its own: the toolbar is as it was.
        XCTAssertTrue(try pane.contains(".reply: (\"arrowshape.turn.up.left\", #selector(replyTapped)),"))
        XCTAssertFalse(try pane.contains("printTapped"))
    }

    /// One job held, replaced only once it is no longer being made ready,
    /// and let go only by its own end; it is given the sheet's letter, the
    /// Reply button, and whether the pane still shows that letter by its id
    /// and its folder.
    func testThePaneHoldsOneJob() throws {
        let pane = try self.pane
        XCTAssertEqual(count("private var printing: LetterPrint?", in: pane), 1)
        let printing = try part(of: pane, from: "private func printLetter(_ m: Message) {",
                                to: "private var printStyle")
        XCTAssertTrue(printing.hasPrefix("private func printLetter(_ m: Message) { "
                                         + "guard printing?.isPreparing != true else { return }"), printing)
        for wiring in ["letter: m, repository: repository, style: printStyle, pane: self, "
                           + "anchor: actionItems[.reply],",
                       "guard let shown = self?.message else { return false } "
                           + "return shown.id == m.id && shown.mailboxID == m.mailboxID",
                       "ended: { [weak self] job in guard let self, self.printing === job else { return } "
                           + "self.printing = nil })",
                       "printing = job job.start() }"] {
            XCTAssertNotNil(place(of: wiring, in: printing), wiring)
        }
        XCTAssertEqual(count("printing = nil", in: pane), 1)
        XCTAssertEqual(count("printing = ", in: pane), 2, "the job, and nil")
        XCTAssertFalse(pane.contains("printFormatter"))
        XCTAssertFalse(pane.contains("UIPrintInteractionController"))
    }

    /// The pane's pictures and a printed letter's come from one map.
    func testThePanesPicturesAreThePrintsMap() throws {
        let pane = try self.pane
        XCTAssertNotNil(place(of: "private func prepareInlineImages(for letters: [Message]) { "
                                  + "let parts = PanePage.pictures(of: letters)", in: pane))
        XCTAssertNotNil(place(of: "part.section, of: part.messageID, mailboxID: part.mailboxID)", in: pane))
        XCTAssertFalse(pane.contains("parts[cid] ="))
        XCTAssertNotNil(place(of: "let pictures = PanePage.pictures(of: [letter])", in: try job))
    }

    /// The printed header is the pane's: the same words from the same
    /// letter, in `MessageHeaderView` and in `PrintPage`.
    func testThePrintedHeaderIsThePanes() throws {
        let header = try source("UI/MessageHeaderView.swift")
        let printed = try source("Mail/PrintPage.swift")
        for words in ["MailFormat.displayName(m.sender)",
                      "MailFormat.recipientsLine(\"To\", m.to) ?? \"To: me\"",
                      "MailFormat.recipientsLine(\"Cc\", m.cc)",
                      "m.subject.isEmpty ? \"(no subject)\" : m.subject",
                      "m.listedAttachments"] {
            XCTAssertTrue(header.contains(words), words)
            XCTAssertTrue(printed.contains(words), words)
        }
        XCTAssertTrue(header.contains("MailFormat.detailTimestamp(m.date)"), "on screen, as it was")
        XCTAssertFalse(printed.contains("detailTimestamp"))
        XCTAssertTrue(printed.contains("MailFormat.fullTimestamp(m.date, locale: locale, timeZone: timeZone)"))
        // The sizes as the header writes them.
        XCTAssertTrue(header.contains("ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)"))
        XCTAssertTrue(try job.contains("ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)"))
    }

    // MARK: - The job's web view

    /// Its own configuration, locked down as the pane's is, all of it set
    /// before the view is built from it; no script of any kind, the app's
    /// or the letter's.
    func testTheJobsWebViewIsLockedDown() throws {
        let job = try self.job
        let built = try XCTUnwrap(place(of: "let web = WKWebView(frame:", in: job))
        for setting in ["let config = WKWebViewConfiguration()",
                        "config.defaultWebpagePreferences.allowsContentJavaScript = false",
                        "config.websiteDataStore = .nonPersistent()",
                        "let loader = InlineImageLoader() "
                            + "config.setURLSchemeHandler(loader, forURLScheme: InlineImageRewriter.scheme)"] {
            let at = try XCTUnwrap(place(of: setting, in: job), setting)
            XCTAssertLessThan(at, built, setting)
        }
        XCTAssertEqual(count("WKWebView(frame:", in: job), 1)
        for never in ["addUserScript", "userContentController", "evaluateJavaScript", "callAsyncJavaScript",
                      "WKUserScript", "WKScriptMessageHandler"] {
            XCTAssertFalse(job.contains(never), never)
        }
    }

    /// Light, unseen, untouchable and silent to VoiceOver, behind the pane's
    /// own views, in its window; its page loaded as the pane loads its own.
    func testTheJobsWebViewIsLightAndUnseen() throws {
        let job = try self.job
        for setting in ["web.overrideUserInterfaceStyle = .light", "web.alpha = 0",
                        "web.isUserInteractionEnabled = false", "web.accessibilityElementsHidden = true",
                        "web.navigationDelegate = self", "paneView.insertSubview(web, at: 0)",
                        "navigation = web.loadHTMLString(page, baseURL: nil)"] {
            XCTAssertNotNil(place(of: setting, in: job), setting)
        }
        XCTAssertFalse(job.contains("NSLayoutConstraint"))
        XCTAssertFalse(job.contains("baseURL: URL"))
    }

    /// The page goes nowhere: the pane's policy, the one allow, and no link
    /// followed or opened.
    func testTheJobsPageGoesNowhere() throws {
        let job = try self.job
        XCTAssertNotNil(place(of: "switch PaneNavigation.decide(PaneNavigation.Kind(action.navigationType), "
                                  + "mainFrame: action.targetFrame?.isMainFrame, url: action.request.url) { "
                                  + "case .allow: decisionHandler(.allow) case .cancel, .follow: "
                                  + "decisionHandler(.cancel) }", in: job))
        XCTAssertEqual(count("decisionHandler(.allow)", in: job), 1)
        XCTAssertFalse(job.contains(".open("))
        XCTAssertFalse(job.contains("follow("))
    }

    /// Each of the page's navigation calls is about its own navigation,
    /// compared by identity; another's commit is a failure, and another's
    /// failure is nothing.
    func testEachNavigationCallIsComparedWithTheJobsOwn() throws {
        let job = try self.job
        for call in [
            "didCommit navigation: WKNavigation!) { take(isOwn(navigation) ? .committed : .failed) }",
            "didFinish navigation: WKNavigation!) { guard isOwn(navigation) else { return } take(.finished) }",
            "didFail navigation: WKNavigation!, withError error: Error) { guard isOwn(navigation) else "
                + "{ return } take(.failed) }",
            "didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { "
                + "guard isOwn(navigation) else { return } take(.failed) }",
            "func webViewWebContentProcessDidTerminate(_ w: WKWebView) { take(.processEnded) }",
            "private func isOwn(_ navigation: WKNavigation?) -> Bool { guard let navigation, "
                + "let own = self.navigation else { return false } return navigation === own }",
        ] {
            XCTAssertNotNil(place(of: call, in: job), call)
        }
        XCTAssertEqual(count("isOwn(navigation)", in: job), 4)
    }

    /// The job's one call on the repository is a read of the letter's own
    /// pictures; nothing is written, to the disk or anywhere else.
    func testTheJobOnlyReadsTheLettersPictures() throws {
        let job = try self.job
        let calls = job.components(separatedBy: "repository.").dropFirst()
            .map { $0.prefix(while: { $0.isLetter }) }
        XCTAssertEqual(calls, ["fetchAttachmentData"])
        for never in ["FileManager", "write(to:", "AttachmentStore", "MailShelf", "LocalDrafts",
                      "UserDefaults", "]?."] {
            XCTAssertFalse(job.contains(never), never)
        }
    }

    // MARK: - Drawing, and the panel

    /// Drawn only while the pane shows the letter in its window with the
    /// app in front, through a renderer of Letter paper set by its own
    /// rectangles, into a PDF; then the web view is torn down before the
    /// panel.
    func testTheLetterIsDrawnIntoAPDFFirst() throws {
        let job = try self.job
        for wiring in [
            "private func draw(inWords: Bool) { guard stillShown(), pane?.viewIfLoaded?.window != nil else "
                + "{ return end(.moved) } guard UIApplication.shared.applicationState == .active else "
                + "{ return end(.away) }",
            "renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)",
            "UISimpleTextPrintFormatter(text: words",
            "let pages = renderer.numberOfPages",
            "renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))",
            "made = UIGraphicsPDFRenderer(bounds: paper).pdfData { context in for page in 0..<pages { "
                + "context.beginPage() renderer.drawPage(at: page, in: paper) } }",
            "let answer = steps.drawn(pages: pages, at: now) if answer == .look { teardown() pdf = made",
            "private final class PaperRenderer: UIPrintPageRenderer { override var paperRect: CGRect {",
            "override var printableRect: CGRect { paperRect.insetBy(dx: PrintPage.margin, dy: PrintPage.margin) }",
        ] {
            XCTAssertNotNil(place(of: wiring, in: job), wiring)
        }
        XCTAssertFalse(job.contains("setValue("), "nothing set by key")
        XCTAssertFalse(job.contains("perform(NSSelectorFromString"))
    }

    /// The panel is given the PDF's bytes, never a live formatter or
    /// renderer, and only in the turn a look has found nothing over the pane
    /// and the app in front; its completion clears the shared controller
    /// only while it is still this job's.
    func testThePanelHoldsBytesSetOnlyAfterTheLook() throws {
        let job = try self.job
        XCTAssertNotNil(place(of: "let answer = steps.look(covered: pane?.presentedViewController != nil, "
                                  + "active: UIApplication.shared.applicationState == .active, "
                                  + "shown: stillShown() && pane?.viewIfLoaded?.window != nil,", in: job))
        XCTAssertNotNil(place(of: "case .present: present()", in: job))
        XCTAssertEqual(count("present()", in: job), 2, "its one call, from the look's answer, and itself")
        let present = try part(of: job, from: "private func present() {", to: "private func end(")
        XCTAssertTrue(present.hasPrefix("private func present() { guard let pdf, let anchor, "
                                        + "UIPrintInteractionController.canPrint(pdf) else { return end(.refused) }"))
        for wiring in ["let info = UIPrintInfo.printInfo() info.outputType = .general "
                           + "info.jobName = PrintPage.jobName(letter) shared.printInfo = info "
                           + "shared.printingItem = pdf",
                       "let shown = shared.present(from: anchor, animated: true) {",
                       "if controller.printInfo === info { controller.printingItem = nil "
                           + "controller.printInfo = nil }",
                       "if shared.printInfo === info { shared.printingItem = nil shared.printInfo = nil }",
                       "self.pdf = nil guard shown else {",
                       "Diagnostics.log(.note, \"PRINT panel over=\\(pane?.presentedViewController != nil)\")"] {
            XCTAssertNotNil(place(of: wiring, in: present), wiring)
        }
        XCTAssertEqual(count("printInfo = info", in: job), 1)
        XCTAssertEqual(count("printingItem = pdf", in: job), 1)
        XCTAssertEqual(count("printingItem = nil", in: job), 2)
        XCTAssertEqual(count("printInfo === info {", in: job), 2)
        for never in [".printFormatter", "printPageRenderer", ".delegate ="] {
            XCTAssertFalse(job.contains(never), never)
        }
    }

    /// One teardown, the view's loading stopped while it is alive and then
    /// taken out, on every end and as soon as the drawing is done; the time
    /// limit, the looks and the observer of the app's going all stopped at
    /// the end.
    func testEveryEndTearsTheWebViewDown() throws {
        let job = try self.job
        XCTAssertNotNil(place(of: "private func teardown() { guard let web = webView else { return } "
                                  + "web.stopLoading() web.navigationDelegate = nil web.removeFromSuperview() "
                                  + "loader?.fetch = nil webView = nil loader = nil navigation = nil }", in: job))
        XCTAssertEqual(count("stopLoading()", in: job), 1)
        XCTAssertEqual(count("removeFromSuperview()", in: job), 1)
        XCTAssertEqual(count("teardown()", in: job), 3, "after the drawing, at the end, and itself")
        XCTAssertNotNil(place(of: "private func end(_ why: PrintSteps.EndWhy?) { guard !finished else "
                                  + "{ return } finished = true steps.end() if let why { Diagnostics.log(.note, "
                                  + "\"PRINT ended why=\\(why.rawValue)\") } teardown() building?.cancel() "
                                  + "building = nil timeLimit?.cancel() timeLimit = nil nextLook?.cancel() "
                                  + "nextLook = nil stopObserving() pdf = nil ended(self) }", in: job))
        XCTAssertNotNil(place(of: "case .end(let why): end(why)", in: job))
        XCTAssertNotNil(place(of: "self?.end(nil)", in: job), "the panel closed")
        XCTAssertEqual(count("steps.end()", in: job), 1)
    }

    /// The app's going is heard, and no longer once the panel is up or the
    /// job has ended; the time limit and the looks use the steps' times.
    func testTheAppsGoingAndTheTimes() throws {
        let job = try self.job
        XCTAssertNotNil(place(of: "NotificationCenter.default.addObserver(self, selector: #selector(wentAway), "
                                  + "name: UIApplication.didEnterBackgroundNotification, object: nil)", in: job))
        XCTAssertNotNil(place(of: "NotificationCenter.default.removeObserver(self, name: "
                                  + "UIApplication.didEnterBackgroundNotification, object: nil)", in: job))
        XCTAssertNotNil(place(of: "@objc private func wentAway() { take(.away) }", in: job))
        XCTAssertNotNil(place(of: "stopObserving() let shown = shared.present(from:", in: job))
        XCTAssertNotNil(place(of: "DispatchQueue.main.asyncAfter(deadline: .now() + PrintSteps.timeLimit, "
                                  + "execute: limit)", in: job))
        XCTAssertNotNil(place(of: "DispatchQueue.main.asyncAfter(deadline: .now() + PrintSteps.coverRetry, "
                                  + "execute: again)", in: job))
        XCTAssertTrue(try source("Mail/PrintSteps.swift").contains("now - readyAt < Self.coverLimit"))
    }

    /// Every way a print ends is logged, counts only: no name, no
    /// subject, no address.
    func testTheLogSaysCountsOnly() throws {
        let job = try self.job
        let lines = job.components(separatedBy: "Diagnostics.log(.note, ").dropFirst()
            .map { $0.components(separatedBy: "\")")[0] }
        XCTAssertEqual(lines.count, 5)
        for line in ["\"PRINT ready pages=\\(pages) bytes=\\(made.count) \" + \"ms=\\(Int((now - tapped) * 1_000))",
                     "\"PRINT words why=\\(why.rawValue)",
                     "\"PRINT ended why=\\(why.rawValue)",
                     "\"PRINT closed done=\\(done)",
                     "\"PRINT panel over=\\(pane?.presentedViewController != nil)"] {
            XCTAssertTrue(lines.contains(line), line)
        }
        XCTAssertFalse(lines.joined().contains("letter"))
        XCTAssertFalse(lines.joined().contains("subject"))
    }
}
