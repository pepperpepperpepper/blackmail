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
                       + "let nav = UINavigationController(rootViewController: compose) "
                       + "nav.modalPresentationStyle = .formSheet present(nav, animated: true) return } "
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
