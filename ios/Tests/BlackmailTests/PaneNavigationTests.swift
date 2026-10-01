import XCTest
@testable import Blackmail

/// The reading pane locked down: where a page in it may go
/// (`PaneNavigation`), and how its web view is set up.
///
/// The pane shows a stranger's HTML, on a WebKit that may never be updated
/// again. It used to run the letter's script and allow every navigation but
/// a tapped link, so a letter could turn the pane into a web page of its
/// own choosing, a false sign-in page with no address bar, or send a form.
final class PaneNavigationTests: XCTestCase {

    private typealias Kind = PaneNavigation.Kind

    private let blank = URL(string: "about:blank")!
    private let web = URL(string: "https://example.com/sign-in")!

    private func decide(_ kind: Kind, mainFrame: Bool?, _ url: URL?) -> PaneNavigation.Decision {
        PaneNavigation.decide(kind, mainFrame: mainFrame, url: url)
    }

    // MARK: - The decision

    /// The pane's own document: `loadHTMLString` with no base URL, which
    /// WebKit loads as `about:blank`, in the main frame, as "other".
    func testThePanesOwnDocumentLoads() {
        XCTAssertEqual(decide(.other, mainFrame: true, blank), .allow)
    }

    /// Anything else the page does on its own goes nowhere: another page in
    /// the pane, as a `<meta http-equiv="refresh">` asks for; the pane's own
    /// URL in any other way, or in a frame or a new window; a URL of any
    /// scheme, this app's own picture scheme included; and a navigation
    /// with no URL, or of a kind a later WebKit adds.
    func testNothingElseLoads() {
        let urls: [URL?] = [web, URL(string: "http://example.com")!, URL(string: "data:text/html,x")!,
                            URL(string: "javascript:alert(1)")!, URL(string: "file:///etc/hosts")!,
                            URL(string: "bmcid://logo%40example.com")!, URL(string: "about:srcdoc")!,
                            URL(string: "about:blank#top")!, nil]
        for url in urls {
            for mainFrame: Bool? in [true, false, nil] {
                XCTAssertEqual(decide(.other, mainFrame: mainFrame, url), .cancel, "\(String(describing: url))")
            }
        }
        for kind: Kind in [.formSubmitted, .formResubmitted, .backForward, .reload, .unknown] {
            for mainFrame: Bool? in [true, false, nil] {
                for url in [blank, web] {
                    XCTAssertEqual(decide(kind, mainFrame: mainFrame, url), .cancel, "\(kind) \(url)")
                }
            }
        }
        XCTAssertEqual(decide(.other, mainFrame: false, blank), .cancel, "a frame inside a letter")
        XCTAssertEqual(decide(.other, mainFrame: nil, blank), .cancel, "a new window")
    }

    /// A form sent from a letter, to the pane, a frame or a new window, is
    /// cancelled: a form he filled in on a false page is the danger.
    func testAFormIsNeverSent() {
        for mainFrame: Bool? in [true, false, nil] {
            XCTAssertEqual(decide(.formSubmitted, mainFrame: mainFrame, web), .cancel)
            XCTAssertEqual(decide(.formResubmitted, mainFrame: mainFrame, web), .cancel)
        }
    }

    /// A tapped link goes where it always went, whatever it targets: out of
    /// the pane, to "Open this link?" or the composer (`follow`).
    func testATappedLinkIsFollowedAsBefore() {
        let mail = URL(string: "mailto:sam@example.com?subject=Roses")!
        for url in [web, mail, blank] {
            for mainFrame: Bool? in [true, false, nil] {
                XCTAssertEqual(decide(.linkActivated, mainFrame: mainFrame, url), .follow(url))
            }
        }
        XCTAssertEqual(decide(.linkActivated, mainFrame: true, nil), .cancel)
    }

    // MARK: - The web view's setup

    /// `MessageDetailViewController` is UIKit and WebKit, and never builds
    /// on this host, so its setup is read from its source, as
    /// `PaneArrangementTests` reads the container's: comment lines out, and
    /// runs of white space as one space.
    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/UI/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    /// Where `text` first is in `code`, failing if it is not there.
    private func place(of text: String, in code: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String.Index? {
        let found = code.range(of: text)?.lowerBound
        XCTAssertNotNil(found, text, file: file, line: line)
        return found
    }

    /// The letter's script off, WebKit's data kept in memory only, the
    /// stack's script injected into the app's content world, all on the
    /// configuration before the web view is built from it, which is when
    /// WebKit copies it.
    func testTheWebViewIsBuiltLockedDown() throws {
        let code = try source("MessageDetailViewController.swift")
        let built = try XCTUnwrap(place(of: "self.webView = WKWebView(frame: .zero, configuration: config)",
                                        in: code))
        for setting in [
            "config.defaultWebpagePreferences.allowsContentJavaScript = false",
            "config.websiteDataStore = .nonPersistent()",
            "config.userContentController.addUserScript( WKUserScript(source: ConversationDocument.script, "
                + "injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))",
        ] {
            let at = try XCTUnwrap(place(of: setting, in: code))
            XCTAssertLessThan(at, built, setting)
        }
    }

    /// The stack's script and the pane talk in the app's content world
    /// alone: `bmLetter` is registered there and nowhere else, so a
    /// letter's markup has none to post to, and `bmFill` is called there,
    /// where the user script defined it. Nothing is run in the page's
    /// world.
    func testThePanesScriptLivesInTheAppsOwnWorld() throws {
        let code = try source("MessageDetailViewController.swift")
        XCTAssertNotNil(place(of: "config.userContentController.add(self, contentWorld: .defaultClient, "
                                  + "name: \"bmLetter\")", in: code))
        XCTAssertNotNil(place(of: "webView.callAsyncJavaScript(ConversationDocument.Fill.script, "
                                  + "arguments: fill.arguments, in: nil, in: .defaultClient)", in: code))
        XCTAssertFalse(code.contains("add(self, name:"))
        XCTAssertFalse(code.contains(".page"))
        XCTAssertFalse(code.contains("evaluateJavaScript"))
    }

    /// Every navigation is decided by `PaneNavigation`, from what WebKit
    /// says of it, and nothing else in the pane allows one.
    func testEveryNavigationIsDecidedByThePolicy() throws {
        let code = try source("MessageDetailViewController.swift")
        XCTAssertNotNil(place(of: "switch PaneNavigation.decide(PaneNavigation.Kind(action.navigationType), "
                                  + "mainFrame: action.targetFrame?.isMainFrame, url: action.request.url) {",
                              in: code))
        XCTAssertEqual(code.components(separatedBy: "decisionHandler(.allow)").count - 1, 1)
        XCTAssertNotNil(place(of: "case .allow: decisionHandler(.allow) case .cancel: decisionHandler(.cancel) "
                                  + "case .follow(let url): decisionHandler(.cancel) follow(url) }", in: code))
        XCTAssertFalse(code.contains("navigationType =="))
        for kind in ["linkActivated", "formSubmitted", "backForward", "reload", "formResubmitted", "other"] {
            XCTAssertNotNil(place(of: "case .\(kind): self = .\(kind)", in: code), kind)
        }
        XCTAssertNotNil(place(of: "@unknown default: self = .unknown", in: code))
    }
}
