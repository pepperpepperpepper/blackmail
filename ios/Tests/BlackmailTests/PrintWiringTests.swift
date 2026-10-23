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

    /// No backgrounds printed, as Mail prints a letter, so WebKit prints a
    /// dark newsletter's white words grey on white paper: set false in the
    /// configuration before the view is built, by its name, as the app is
    /// stamped below the iOS 16.4 that made it public and where WebKit's
    /// own default became false, and only where the setter is there. Never
    /// an OS version check, which does not link with this toolchain, nor
    /// the property set directly, which would need one (seen on the test
    /// iPad 2026-10-23: white words on a black block).
    func testNoBackgroundIsPrinted() throws {
        let job = try self.job
        let built = try XCTUnwrap(place(of: "let web = WKWebView(frame:", in: job))
        let set = "let preferences = config.preferences if preferences.responds(to: "
            + "NSSelectorFromString(\"setShouldPrintBackgrounds:\")) { "
            + "preferences.setValue(false, forKey: \"shouldPrintBackgrounds\") }"
        let at = try XCTUnwrap(place(of: set, in: job))
        XCTAssertLessThan(at, built)
        XCTAssertEqual(count("shouldPrintBackgrounds", in: job), 1, "set once, and false")
        XCTAssertEqual(count("ShouldPrintBackgrounds", in: job), 1, "the setter looked for once")
        XCTAssertFalse(job.contains("#available"))
        XCTAssertFalse(job.contains(".shouldPrintBackgrounds"))
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
                                  + "case .allow: decisionHandler(.allow) case .cancel, .follow, .openFile: "
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
    /// app in front, the app gone to the background ending it and a
    /// moment's interruption not, through a renderer of Letter paper set by
    /// its own rectangles, into a PDF; then the web view is torn down before
    /// the panel.
    func testTheLetterIsDrawnIntoAPDFFirst() throws {
        let job = try self.job
        for wiring in [
            "private func draw() { guard stillShown(), pane?.viewIfLoaded?.window != nil else "
                + "{ return end(.moved) } guard UIApplication.shared.applicationState != .background else "
                + "{ return end(.away) }",
            "renderer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0)",
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
        // Nothing of the renderer set by key: the one value set by key is
        // the web view's backgrounds (`testNoBackgroundIsPrinted`).
        XCTAssertEqual(count("setValue(", in: job), 1)
        XCTAssertFalse(job.contains("renderer.setValue("), "nothing set by key")
        XCTAssertFalse(job.contains("perform(NSSelectorFromString"))
        // The drawing ends only for the background; the panel waits for the
        // app to be active.
        XCTAssertEqual(count("UIApplication.shared.applicationState", in: job), 2)
        XCTAssertEqual(count("applicationState != .background", in: job), 1)
        XCTAssertEqual(count("applicationState == .active", in: job), 1)
    }

    /// What the steps answer is what is done: the page loaded only at
    /// `load`, the page drawn at `draw`, and the letter drawn again at
    /// `drawWords`, every row of the answer acted on, none left out.
    func testEachAnswerOfTheStepsIsDone() throws {
        let job = try self.job
        XCTAssertNotNil(place(of: "private func act(_ answer: PrintSteps.Answer) { switch answer { "
                                  + "case .wait: break case .load: load() case .draw: draw() "
                                  + "case .drawWords(let why): Diagnostics.log(.note, "
                                  + "\"PRINT words why=\\(why.rawValue)\") draw() "
                                  + "case .look: look() case .present: present() "
                                  + "case .end(let why): end(why) } }", in: job))
        XCTAssertEqual(count("load()", in: job), 2, "its one call, from `load`, and itself")
        XCTAssertEqual(count("draw()", in: job), 3, "from `draw`, from `drawWords`, and itself")
        XCTAssertEqual(count("act(", in: job), 5, "itself, take, the look, the drawing and a refused panel")
    }

    /// The words, never the page, once the steps say so: a page that failed,
    /// whose process ended or that drew nothing is drawn again in words,
    /// never from its web view, which would give nothing again. What is
    /// drawn is read from the steps, the one place that also decides what a
    /// drawing of no pages means next.
    func testTheWordsAreNeverDrawnFromTheWebView() throws {
        let job = try self.job
        XCTAssertNotNil(place(of: "let web = steps.inWords ? nil : webView if let web { "
                                  + "renderer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0) "
                                  + "} else { let text = UISimpleTextPrintFormatter(text: words ?? "
                                  + "PrintPage.jobName(letter))", in: job))
        XCTAssertEqual(count("viewPrintFormatter()", in: job), 1)
        XCTAssertEqual(count("inWords", in: job), 1, "read from the steps, never passed in")
        XCTAssertFalse(job.contains("if let webView"))
    }

    /// The page is loaded, or the words drawn, only once the page and its
    /// words are made, by the steps' `built`: a time limit that comes first
    /// waits for them in the steps, so the job is never left made ready
    /// with nothing to come, Print greyed until the app is started again.
    func testThePageIsLoadedOnlyOnceItAndItsWordsAreMade() throws {
        let job = try self.job
        XCTAssertNotNil(place(of: "building = Task { @MainActor [weak self] in "
                                  + "let made = await Self.made(m, style: style) guard let self else { return } "
                                  + "self.page = made.page self.words = made.words self.take(.built) }", in: job))
        XCTAssertEqual(count("take(.built)", in: job), 1)
        XCTAssertNotNil(place(of: "private func load() { guard let page, let pane, "
                                  + "let paneView = pane.viewIfLoaded else { return end(.moved) } "
                                  + "self.page = nil", in: job))
        XCTAssertEqual(count("self.page = ", in: job), 2, "made, and let go once loaded")
        XCTAssertEqual(count("self.words = ", in: job), 1)
        XCTAssertFalse(job.contains("steps.step"), "what comes next is the steps', never read here")
    }

    /// The pane is looked at from the tap, one look waiting at a time, so
    /// a letter tapped while the page loads ends the print within the
    /// moment; and once it has moved on, the job's loader asks the
    /// repository for none of the old letter's pictures.
    func testAPaneMovedOnEndsThePrintAndAsksForNoPicture() throws {
        let job = try self.job
        let start = try part(of: job, from: "func start() {", to: "private nonisolated static func made(")
        XCTAssertNotNil(place(of: "DispatchQueue.main.asyncAfter(deadline: .now() + PrintSteps.timeLimit, "
                                  + "execute: limit) lookAgain()", in: start))
        XCTAssertNotNil(place(of: "private func look() { nextLook?.cancel() nextLook = nil "
                                  + "let answer = steps.look(", in: job))
        XCTAssertNotNil(place(of: "guard answer == .wait else { return act(answer) } "
                                  + "if steps.isPreparing { lookAgain() } }", in: job))
        XCTAssertNotNil(place(of: "private func lookAgain() { let again = DispatchWorkItem { [weak self] in "
                                  + "self?.look() } nextLook = again DispatchQueue.main.asyncAfter(deadline: "
                                  + ".now() + PrintSteps.coverRetry, execute: again) }", in: job))
        XCTAssertEqual(count("lookAgain()", in: job), 3, "at the start, after a look, and itself")
        XCTAssertEqual(count("nextLook = again", in: job), 1)

        let fetch = try part(of: job, from: "loader.fetch = {", to: "paneView.insertSubview(")
        XCTAssertTrue(fetch.hasPrefix("loader.fetch = { @MainActor contentID in guard stillShown(), "
                                      + "let part = pictures[contentID] else { throw MailError.attachmentFailed } "
                                      + "let data = try await repository.fetchAttachmentData("), fetch)
        XCTAssertNotNil(place(of: "let repository = self.repository, stillShown = self.stillShown", in: job))
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
                                  + "loader?.stopAll() loader?.fetch = nil webView = nil loader = nil "
                                  + "navigation = nil }", in: job))
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

    /// The teardown stops every picture still coming itself, before it lets
    /// go of the loader, and never leaves that to WebKit, which drops the
    /// tasks of a view let go of at once without telling the loader: the
    /// loader stops every request it holds, none answered and every fetch
    /// called off (`PictureRequests.stopAll`), so none still waiting its
    /// turn on the connection goes out after the print has ended (seen on
    /// the test iPad 2026-10-23: four 3.3 MB pictures ahead of the letter
    /// he had tapped). Nothing else stops them all.
    func testTheTeardownStopsThePicturesStillComingItself() throws {
        let job = try self.job
        let teardown = try part(of: job, from: "private func teardown() {", to: "webView = nil")
        XCTAssertNotNil(place(of: "web.removeFromSuperview() loader?.stopAll() loader?.fetch = nil", in: teardown))
        XCTAssertEqual(count("stopAll()", in: job), 1)
        let loader = try source("UI/InlineImageLoader.swift")
        XCTAssertNotNil(place(of: "func stopAll() { requests.stopAll() }", in: loader))
        XCTAssertEqual(count("stopAll()", in: loader), 2, "itself, and the requests'")
        XCTAssertNotNil(place(of: "func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) { "
                                  + "requests.stop(ObjectIdentifier(task)) }", in: loader))
        XCTAssertFalse(try pane.contains("stopAll()"), "the pane's loader is stopped by WebKit, as before")
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
