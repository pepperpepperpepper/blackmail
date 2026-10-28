import XCTest
@testable import Blackmail

/// A link tapped in a letter opens at once, in Safari or the app that
/// claims it, as Mail opens one (B-145): no "Open this link?" first, which
/// the pane asked since B-055. A `mailto:` still opens this app's composer
/// with its address (B-036). The same in a plain letter, whose links the
/// pane makes (`TextLinks`), in an HTML letter and in a conversation's
/// stack: all three are pages of the one web view, whose every tapped link
/// comes to `follow` (`PaneNavigation`).
///
/// `follow` is UIKit, which the suite cannot run, and is read from the
/// source; where a tap goes is `PaneNavigation.decide`, run here.
final class LinkAtOnceTests: XCTestCase {

    /// Every tapped link, whatever page it is in and whatever it targets,
    /// is taken out of the pane to `follow`: a web address, YouTube's, a
    /// `www.` address as a plain letter's page writes it, and a `mailto:`.
    /// Nothing is asked on the way: the decision has no case for a
    /// question.
    func testEveryTappedLinkGoesToFollow() throws {
        let plain = TextLinks.plain("See https://youtu.be/abc and www.example.com. Or mailto:sam@example.com",
                                    escaping: .ampersandAndLessThan)
        let made = plain.components(separatedBy: "href=\"").dropFirst()
            .map { String($0.prefix(while: { $0 != "\"" })) }
        XCTAssertEqual(made, ["https://youtu.be/abc", "http://www.example.com", "mailto:sam@example.com"])
        for link in made + ["https://example.com/a?b=1&c=2", "tel:555-555-0142"] {
            let url = try XCTUnwrap(URL(string: link))
            for mainFrame: Bool? in [true, false, nil] {
                XCTAssertEqual(PaneNavigation.decide(.linkActivated, mainFrame: mainFrame, url: url),
                               .follow(url), link)
            }
        }
    }

    /// `follow`: a `mailto:` opens the composer with the letter it asks
    /// for, and anything else is handed to iOS at once. No alert, no
    /// question, and nothing between the tap and the open.
    func testFollowOpensALinkAtOnce() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        let follow = flat(body(after: "private func follow(_ url: URL)", in: code))
        XCTAssertEqual(follow, "{ if url.scheme?.lowercased() == \"mailto\", let draft = MailtoLink.draft("
                       + "from: url, signature: CredentialStore.loadAccount()?.signature ?? \"\") { "
                       + "let compose = ComposeViewController(repository: repository, draft: draft) "
                       + "let nav = UINavigationController.formSheet(compose) "
                       + "present(nav, animated: true) return } "
                       + "UIApplication.shared.open(url) }")
        XCTAssertFalse(follow.contains("UIAlertController"))
        XCTAssertEqual(code.components(separatedBy: "UIApplication.shared.open(").count - 1, 1,
                       "the one place the pane opens a link")
    }

    /// The question is gone from the app: no code under `Sources` says
    /// "Open this link?".
    func testNoCodeAsksOpenThisLink() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 100)
        for file in files {
            let code = try String(contentsOf: file, encoding: .utf8)
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            XCTAssertFalse(code.contains("Open this link"), file.lastPathComponent)
        }
    }

    // MARK: - A link held

    /// A link held has Mail's "Add to Reading List" second, after Open
    /// Link, as Mail's menu on the test iPad had it, where WebKit's had
    /// none (B-176): for a page Safari's list can keep, and for nothing
    /// else, nor in a menu that has it already. The pane answers WebKit
    /// with a menu of its own for such a page alone; for a `mailto:`,
    /// `tel:` or `javascript:` link, or a picture with no link, nil, so
    /// WebKit's menu, or DataDetectors', is as it was.
    func testAHeldLinkOffersAddToReadingListSecond() throws {
        let webKit = ["Open Link", "Copy Link", "Share…"]
        let page = try XCTUnwrap(URL(string: "https://example.com/rm-a"))
        let mail = try XCTUnwrap(URL(string: "mailto:sam@example.com"))
        let phone = try XCTUnwrap(URL(string: "tel:+15555550100"))
        let script = try XCTUnwrap(URL(string: "javascript:void(0)"))
        let web: (URL) -> Bool = { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        XCTAssertEqual(LinkMenu.answered(page, supports: web), page)
        XCTAssertEqual(LinkMenu.answered(try XCTUnwrap(URL(string: "http://example.com/rm-b")), supports: web),
                       URL(string: "http://example.com/rm-b"))
        for other in [mail, phone, script] {
            XCTAssertNil(LinkMenu.answered(other, supports: web), "WebKit's own: \(other)")
        }
        XCTAssertNil(LinkMenu.answered(nil, supports: web), "no link, a picture: WebKit's own")
        XCTAssertNil(LinkMenu.answered(page, supports: { _ in false }), "not kept by the list: WebKit's own")
        XCTAssertEqual(LinkMenu.place(among: webKit, for: page, supports: web), 1)
        var menu = webKit
        menu.insert(LinkMenu.addToReadingList, at: 1)
        XCTAssertEqual(menu, ["Open Link", "Add to Reading List", "Copy Link", "Share…"], "Mail's order")
        XCTAssertNil(LinkMenu.place(among: webKit, for: mail, supports: web), "not a page")
        XCTAssertNil(LinkMenu.place(among: webKit, for: nil, supports: web), "no link: a picture's menu")
        XCTAssertNil(LinkMenu.place(among: menu, for: page, supports: web), "there already")
        XCTAssertNil(LinkMenu.place(among: webKit, for: page, supports: { _ in false }))
        XCTAssertEqual(LinkMenu.place(among: ["Copy Link", "Open Link", "Share…"], for: page, supports: web), 2)
        XCTAssertEqual(LinkMenu.place(among: ["Copy Link", "Share…"], for: page, supports: web), 1)
        XCTAssertEqual(LinkMenu.place(among: [], for: page, supports: web), 0)
        XCTAssertEqual(LinkMenu.symbol, "eyeglasses")
    }

    /// The pane, read: the web view's `WKUIDelegate` is the pane, its
    /// first. For anything held that Safari's list cannot keep
    /// (`LinkMenu.answered`), it answers nil, first, as WebKit is answered
    /// with no delegate. For a page the list can keep, WebKit's suggested
    /// items with the item put in where `LinkMenu` says, adding to that
    /// list, and no preview of its own: whether WebKit's card stays above
    /// it was not seen on the iPad (B-176's check, step 4). Nothing else of
    /// the web view's is handed to it.
    func testTheHeldLinksMenuIsWebKitsWithTheItem() throws {
        let code = flat(try source("UI/MessageDetailViewController.swift"))
        for wiring in [
            "webView.navigationDelegate = self webView.uiDelegate = self",
            "extension MessageDetailViewController: WKUIDelegate {",
            "completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) { "
                + "guard let link = LinkMenu.answered(elementInfo.linkURL, supports: SSReadingList.supportsURL) "
                + "else { completionHandler(nil) return } "
                + "completionHandler(UIContextMenuConfiguration(identifier: nil, "
                + "previewProvider: nil) { suggested in var items = suggested",
            "if let at = LinkMenu.place(among: titles, for: link, supports: SSReadingList.supportsURL) "
                + "{ items.insert(UIAction(title: LinkMenu.addToReadingList, image: UIImage(systemName: LinkMenu.symbol))",
            "try SSReadingList.default()?.addItem(with: link, title: nil, previewText: nil)",
            "}, at: at) } return UIMenu(title: \"\", children: items) })",
        ] {
            XCTAssertTrue(code.contains(wiring), wiring)
        }
        XCTAssertEqual(code.components(separatedBy: "uiDelegate").count - 1, 1)
        XCTAssertEqual(code.components(separatedBy: "completionHandler(").count - 1, 2,
                       "answered once on each way: nil, or the menu")
        XCTAssertEqual(code.components(separatedBy: "elementInfo.").count - 1, 1, "its link alone")
        XCTAssertFalse(code.contains("previewProvider: {"))
        let package = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(package.contains(".linkedFramework(\"SafariServices\", .when(platforms: [.iOS]))"))
    }

    // MARK: - Reading the source

    /// A file under `Sources/Blackmail`, its comment lines taken out.
    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The braces after the first `opener` in `code`, and everything in them.
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

    /// Whitespace runs as one space.
    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).joined(separator: " ")
    }
}
