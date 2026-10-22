// Guarded so this file compiles away on a host without UIKit.
#if canImport(UIKit)

import UIKit
import WebKit

/// One print of one letter (B-110): Print in the Reply sheet, and
/// AirPrint's panel from the Reply button, holding a light copy of the
/// letter the header shows, as Mail prints it.
///
/// The letter's page (`PrintPage`) is loaded into a web view of its own,
/// drawn into a PDF while the app is in front and the view is in its
/// window, and the panel is given the PDF's bytes. Mail hands the panel a
/// live formatter instead; UIKit reads one until the job has gone, after
/// the panel has closed and perhaps with the app in the background, and
/// WebKit's print messages wait with no limit, on a process iOS may suspend
/// there. Drawn first, WebKit is asked only while it can answer, about a
/// bounded letter, and the panel holds bytes.
///
/// What each thing that happens means is `PrintSteps`'.
///
/// The lifetime, in one place. The pane holds the job from the tap to the
/// panel (`MessageDetailViewController.printing`). The web view lives from
/// its load to the end of the drawing, or an earlier end. From then to the
/// panel, at most `PrintSteps.coverLimit`, the job holds the PDF and
/// nothing of WebKit; once the panel is up, only the system's print
/// controller holds anything, the PDF, until it closes. Nothing is written
/// to disk, and nothing is asked of the server but the letter's own
/// pictures, read.
@MainActor
final class LetterPrint: NSObject, WKNavigationDelegate {

    private let letter: Message
    private let repository: MailRepository
    private let style: PrintPage.Style
    /// The reading pane, which the web view is put in while it draws, and
    /// which is looked at before the panel comes.
    private weak var pane: UIViewController?
    /// The Reply button, which the panel comes from.
    private weak var anchor: UIBarButtonItem?
    /// Whether the pane still shows the letter.
    private let stillShown: () -> Bool
    /// Called once, when the job ends, whichever way.
    private let ended: (LetterPrint) -> Void

    private var steps = PrintSteps()
    /// When Print was tapped, for the log.
    private let tapped = ProcessInfo.processInfo.systemUptime
    private var building: Task<Void, Never>?
    private var webView: WKWebView?
    private var loader: InlineImageLoader?
    /// The page's own navigation, which every delegate call is compared
    /// with.
    private var navigation: WKNavigation?
    /// The letter in words, made with its page, for a page that cannot be
    /// drawn.
    private var words: String?
    private var timeLimit: DispatchWorkItem?
    private var nextLook: DispatchWorkItem?
    private var observing = false
    /// The PDF, from the drawing until the panel has it.
    private var pdf: Data?

    init(letter: Message, repository: MailRepository, style: PrintPage.Style,
         pane: UIViewController, anchor: UIBarButtonItem?,
         stillShown: @escaping () -> Bool, ended: @escaping (LetterPrint) -> Void) {
        self.letter = letter
        self.repository = repository
        self.style = style
        self.pane = pane
        self.anchor = anchor
        self.stillShown = stillShown
        self.ended = ended
    }

    /// True from the tap until the panel is up or the job has ended.
    var isPreparing: Bool { steps.isPreparing }

    // MARK: - Start

    /// Builds the page away from the main thread, then loads it; the time
    /// limit runs from now.
    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(wentAway),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        observing = true
        let limit = DispatchWorkItem { [weak self] in self?.take(.late) }
        timeLimit = limit
        DispatchQueue.main.asyncAfter(deadline: .now() + PrintSteps.timeLimit, execute: limit)

        let m = letter, style = style
        building = Task { @MainActor [weak self] in
            let made = await Self.made(m, style: style)
            guard let self else { return }
            self.words = made.words
            guard self.steps.step == .loading else {
                // The time limit came first, and asked for the words.
                if self.steps.step == .drawing, self.webView == nil { self.draw(inWords: true) }
                return
            }
            self.load(made.page)
        }
    }

    /// The page and the words, made on the cooperative pool rather than the
    /// main actor: an async function isolated to no actor runs away from its
    /// caller (SE-0338), as `PaneLoads.prepared` does.
    private nonisolated static func made(_ m: Message, style: PrintPage.Style) async
        -> (page: String, words: String) {
        let size: (Int64) -> String = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return (PrintPage.letter(m, style: style, size: size), PrintPage.words(m, size: size))
    }

    /// The page in a web view of its own, locked down as the pane's is, and
    /// light.
    private func load(_ page: String) {
        guard let pane, let paneView = pane.viewIfLoaded else { return end(.moved) }
        let config = WKWebViewConfiguration()
        // None of the letter's script runs, nothing of WebKit's is kept,
        // and its pictures come from the loader, as in the pane.
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let loader = InlineImageLoader()
        config.setURLSchemeHandler(loader, forURLScheme: InlineImageRewriter.scheme)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: PrintPage.paperWidth - 2 * PrintPage.margin,
                                          height: PrintPage.paperHeight - 2 * PrintPage.margin),
                            configuration: config)
        // Light, so a sender's rules for a dark appearance, Apple Mail's own
        // among them, never apply.
        web.overrideUserInterfaceStyle = .light
        // In the pane's window, behind everything, unseen and untouchable:
        // WebKit counts a view in a window, with the app in front, as
        // visible, whatever its alpha, and does not suspend it mid-print.
        web.alpha = 0
        web.isUserInteractionEnabled = false
        web.accessibilityElementsHidden = true
        web.navigationDelegate = self

        // The letter's own pictures, and nothing else of the repository's.
        let pictures = PanePage.pictures(of: [letter])
        let repository = self.repository
        loader.fetch = { contentID in
            guard let part = pictures[contentID] else { throw MailError.attachmentFailed }
            let data = try await repository.fetchAttachmentData(part.section, of: part.messageID,
                                                                mailboxID: part.mailboxID)
            return (data, part.mimeType)
        }

        paneView.insertSubview(web, at: 0)
        webView = web
        self.loader = loader
        navigation = web.loadHTMLString(page, baseURL: nil)
        if navigation == nil { take(.failed) }
    }

    // MARK: - The page's navigation

    func webView(_ w: WKWebView, didCommit navigation: WKNavigation!) {
        take(isOwn(navigation) ? .committed : .failed)
    }

    func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {
        guard isOwn(navigation) else { return }
        take(.finished)
    }

    func webView(_ w: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard isOwn(navigation) else { return }
        take(.failed)
    }

    /// Another navigation's failure is nothing: a letter's meta refresh,
    /// cancelled by the policy below, fails this way.
    func webView(_ w: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        guard isOwn(navigation) else { return }
        take(.failed)
    }

    func webViewWebContentProcessDidTerminate(_ w: WKWebView) {
        take(.processEnded)
    }

    /// The page goes nowhere: `PaneNavigation`'s answer, and a tapped link
    /// is not followed either, since nothing here can be tapped.
    func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        switch PaneNavigation.decide(PaneNavigation.Kind(action.navigationType),
                                     mainFrame: action.targetFrame?.isMainFrame,
                                     url: action.request.url) {
        case .allow:
            decisionHandler(.allow)
        case .cancel, .follow:
            decisionHandler(.cancel)
        }
    }

    private func isOwn(_ navigation: WKNavigation?) -> Bool {
        guard let navigation, let own = self.navigation else { return false }
        return navigation === own
    }

    @objc private func wentAway() { take(.away) }

    private func take(_ event: PrintSteps.Event) {
        act(steps.take(event))
    }

    private func act(_ answer: PrintSteps.Answer) {
        switch answer {
        case .wait:
            break
        case .draw:
            draw(inWords: false)
        case .drawWords(let why):
            Diagnostics.log(.note, "PRINT words why=\(why.rawValue)")
            // The words are made with the page; until then, they are drawn
            // as soon as they are (`start`).
            if words != nil { draw(inWords: true) }
        case .look:
            look()
        case .present:
            present()
        case .end(let why):
            end(why)
        }
    }

    // MARK: - Drawing

    /// The page, or the words, drawn into a PDF of Letter-sized pages, if
    /// the pane still shows the letter in its window with the app in front.
    private func draw(inWords: Bool) {
        guard stillShown(), pane?.viewIfLoaded?.window != nil else { return end(.moved) }
        guard UIApplication.shared.applicationState == .active else { return end(.away) }
        let paper = CGRect(x: 0, y: 0, width: PrintPage.paperWidth, height: PrintPage.paperHeight)
        let renderer = PaperRenderer()
        if !inWords, let webView {
            renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        } else {
            let text = UISimpleTextPrintFormatter(text: words ?? PrintPage.jobName(letter))
            text.font = .systemFont(ofSize: 17)
            text.color = .black
            renderer.addPrintFormatter(text, startingAtPageAt: 0)
        }
        let pages = renderer.numberOfPages
        var made = Data()
        if pages > 0 {
            renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
            made = UIGraphicsPDFRenderer(bounds: paper).pdfData { context in
                for page in 0..<pages {
                    context.beginPage()
                    renderer.drawPage(at: page, in: paper)
                }
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        let answer = steps.drawn(pages: pages, at: now)
        if answer == .look {
            // From here on the job holds the PDF and nothing of WebKit.
            teardown()
            pdf = made
            Diagnostics.log(.note, "PRINT ready pages=\(pages) bytes=\(made.count) "
                                + "ms=\(Int((now - tapped) * 1_000))")
        }
        act(answer)
    }

    /// Letter paper, with the margin all round. The renderer's own two
    /// rectangles, overridden; nothing set by key.
    private final class PaperRenderer: UIPrintPageRenderer {
        override var paperRect: CGRect {
            CGRect(x: 0, y: 0, width: PrintPage.paperWidth, height: PrintPage.paperHeight)
        }
        override var printableRect: CGRect {
            paperRect.insetBy(dx: PrintPage.margin, dy: PrintPage.margin)
        }
    }

    // MARK: - The panel

    /// The pane looked at with the PDF ready: the panel if nothing is over
    /// it and the app is in front, and otherwise again in a moment
    /// (`PrintSteps.look`). So a Reply sheet he opened again meanwhile has
    /// the panel once it is closed, never over it.
    private func look() {
        nextLook = nil
        let answer = steps.look(covered: pane?.presentedViewController != nil,
                                active: UIApplication.shared.applicationState == .active,
                                shown: stillShown() && pane?.viewIfLoaded?.window != nil,
                                at: ProcessInfo.processInfo.systemUptime)
        guard answer == .wait else { return act(answer) }
        let again = DispatchWorkItem { [weak self] in self?.look() }
        nextLook = again
        DispatchQueue.main.asyncAfter(deadline: .now() + PrintSteps.coverRetry, execute: again)
    }

    /// AirPrint's panel, from the Reply button, holding the PDF. Called
    /// only from `look`, in the same turn that found nothing over the pane
    /// and the app in front, so a panel already up, QuickLook's or another,
    /// never has its document changed under it.
    private func present() {
        guard let pdf, let anchor, UIPrintInteractionController.canPrint(pdf) else {
            return end(.refused)
        }
        let shared = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = PrintPage.jobName(letter)
        shared.printInfo = info
        shared.printingItem = pdf
        stopObserving()
        let shown = shared.present(from: anchor, animated: true) { [weak self] controller, done, _ in
            // Cleared only if it is still this job's: another print may
            // have the controller by now.
            if controller.printInfo === info {
                controller.printingItem = nil
                controller.printInfo = nil
            }
            Diagnostics.log(.note, "PRINT closed done=\(done)")
            self?.end(nil)
        }
        self.pdf = nil
        guard shown else {
            if shared.printInfo === info {
                shared.printingItem = nil
                shared.printInfo = nil
            }
            return act(steps.presented(false))
        }
        _ = steps.presented(true)
        Diagnostics.log(.note, "PRINT panel over=\(pane?.presentedViewController != nil)")
    }

    // MARK: - The end

    /// The job is over, `why` saying why when it ended with no panel. Once,
    /// however many ways it is reached.
    private func end(_ why: PrintSteps.EndWhy?) {
        guard !finished else { return }
        finished = true
        steps.end()
        if let why { Diagnostics.log(.note, "PRINT ended why=\(why.rawValue)") }
        teardown()
        building?.cancel()
        building = nil
        timeLimit?.cancel()
        timeLimit = nil
        nextLook?.cancel()
        nextLook = nil
        stopObserving()
        pdf = nil
        ended(self)
    }

    private var finished = false

    private func stopObserving() {
        guard observing else { return }
        observing = false
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification,
                                                  object: nil)
    }

    /// The web view gone, and its loader: loading stopped while the view is
    /// alive, so WebKit stops each picture still coming and its fetch is
    /// called off (`PictureRequests`), and nothing is answered after. On
    /// every end, and as soon as the drawing is done.
    private func teardown() {
        guard let web = webView else { return }
        web.stopLoading()
        web.navigationDelegate = nil
        web.removeFromSuperview()
        loader?.fetch = nil
        webView = nil
        loader = nil
        navigation = nil
    }
}

#endif
