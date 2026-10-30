import XCTest
@testable import Blackmail

/// The Connection log opens at its newest line (B-186). Round r6-p-copy,
/// 2026-10-29: the log's view opened at its oldest line, its scroll to the
/// end asked for before the text view had a size.
final class LogEndTests: XCTestCase {

    /// A log shorter than the view stays at its top, the inset above it.
    func testAShortLogIsAtItsTop() {
        XCTAssertEqual(LogEnd.offset(contentHeight: 300, viewHeight: 900, insetTop: 0, insetBottom: 0), 0)
        XCTAssertEqual(LogEnd.offset(contentHeight: 300, viewHeight: 900, insetTop: 20, insetBottom: 34), -20)
    }

    /// A long one has its end at the foot of the view, above the inset
    /// under it.
    func testALongLogIsAtItsEnd() {
        XCTAssertEqual(LogEnd.offset(contentHeight: 40_000, viewHeight: 900, insetTop: 0, insetBottom: 0), 39_100)
        XCTAssertEqual(LogEnd.offset(contentHeight: 40_000, viewHeight: 900, insetTop: 20, insetBottom: 34),
                       39_134)
        XCTAssertEqual(LogEnd.offset(contentHeight: 900, viewHeight: 900, insetTop: 20, insetBottom: 34), 34)
    }

    /// The view scrolls once it has been laid out with a height, once, and
    /// after Clear and the Layout button, which reload it; never as it
    /// loads, when a scroll moves nothing. Read from its source, comment
    /// lines out: the view is UIKit, built only for the device.
    func testTheViewScrollsAfterItsFirstLayout() throws {
        let code = flat(try source("UI/DiagnosticsViewController.swift"))
        XCTAssertTrue(code.contains("override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews() "
                                    + "guard !scrolledAtOpen, textView.bounds.height > 0 else { return } "
                                    + "scrolledAtOpen = true scrollToEnd() }"), code)
        XCTAssertTrue(code.contains("guard scrolledAtOpen else { return } scrollToEnd() }"))
        XCTAssertTrue(code.contains("textView.layoutManager.ensureLayout(for: textView.textContainer)"))
        XCTAssertTrue(code.contains("LogEnd.offset(contentHeight: textView.contentSize.height, "
                                    + "viewHeight: textView.bounds.height, "
                                    + "insetTop: insets.top, insetBottom: insets.bottom)"))
        XCTAssertFalse(code.contains("scrollRangeToVisible"))
        XCTAssertEqual(code.components(separatedBy: "reload()").count - 1, 4,
                       "its own, viewDidLoad's, Clear's and the Layout button's")
    }

    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).joined(separator: " ")
    }
}
