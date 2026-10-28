import XCTest
@testable import Blackmail

/// Quick Look of a picture with its bars from iOS 18, as on 16 and 17
/// (B-176, B-171): iOS 18's Quick Look opens a picture with its bars
/// hidden until a tap, in every app, decided once as it is presented
/// behind a flag of its own (`QuickLookBars`). The pane sets that flag
/// between the presentation style and the presentation, in the one place
/// every Quick Look is made, only from iOS 18 and only where Quick Look
/// has both the method and the flag. The pane is UIKit and built only for
/// the device, so it is read from its source, comment lines out. What it
/// looks like on 18 is a simulator check.
final class QuickLookBarsTests: XCTestCase {

    /// The names as QuickLook in the iOS 18.6 runtime has them.
    func testTheNames() {
        XCTAssertEqual(QuickLookBars.decider, "_setDefaultFullscreenStateIfNeeded")
        XCTAssertEqual(QuickLookBars.flag, "_didSetDefaultFullscreenState")
    }

    /// The flag set once, behind the check of 18 and both guards, after
    /// the presentation style and before the presentation; nothing else
    /// in the presentation changed, and on 16 and 17 nothing is asked.
    func testThePaneSetsTheFlagFrom18AloneBeforePresenting() throws {
        let pane = try source("Sources/Blackmail/UI/MessageDetailViewController.swift")
        let gate = "if ProcessInfo.processInfo.isOperatingSystemAtLeast( "
            + "OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0)), "
            + "preview.responds(to: NSSelectorFromString(QuickLookBars.decider)), "
            + "class_getInstanceVariable(QLPreviewController.self, QuickLookBars.flag) != nil { "
            + "preview.setValue(true, forKey: QuickLookBars.flag) }"
        XCTAssertTrue(pane.contains("let preview = QLPreviewController() preview.dataSource = self "
                                    + "preview.delegate = self preview.modalPresentationStyle = .fullScreen "
                                    + gate + " if use == .markupAndReply || MarkupReply.marksUp(attachment) {"),
                      "right after the presentation style")
        let branch = try part(of: pane, from: "case .quickLook, .markupAndReply, .saveImage, .copy:",
                              to: "} catch {")
        inOrder(["let preview = QLPreviewController()",
                 "preview.modalPresentationStyle = .fullScreen",
                 gate,
                 "present(preview, animated: true, completion: ready)"], in: branch)

        XCTAssertFalse(pane.contains("#available"))
        XCTAssertEqual(count("QLPreviewController()", in: pane), 1, "one place every Quick Look is made")
        XCTAssertEqual(count("modalPresentationStyle = .fullScreen", in: pane), 1)
        XCTAssertEqual(count("forKey: QuickLookBars.flag", in: pane), 1)
        XCTAssertEqual(count("QuickLookBars.", in: pane), 3, "the guards' two names and the flag set")
        XCTAssertEqual(count("isOperatingSystemAtLeast", in: pane), 1)
        for name in [QuickLookBars.decider, QuickLookBars.flag] {
            XCTAssertFalse(pane.contains(name), "named in `QuickLookBars` alone: \(name)")
        }
    }

    // MARK: - Helpers

    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent(file)
        let text = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        return text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func part(of code: String, from start: String, to end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start), start)
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex), end)
        return String(code[from.lowerBound..<to.lowerBound])
    }

    private func inOrder(_ parts: [String], in text: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        var from = text.startIndex
        for part in parts {
            guard let found = text.range(of: part, range: from..<text.endIndex) else {
                XCTFail("missing or out of order: \(part)", file: file, line: line)
                return
            }
            from = found.upperBound
        }
    }
}
