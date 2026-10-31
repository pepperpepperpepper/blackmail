import XCTest
@testable import Blackmail

/// A build number he or a helper can read out (B-187): the version, the
/// build and the commit, at the foot of Settings and at the top of the
/// Connection log.
final class BuildStampTests: XCTestCase {

    private let full: [String: Any] = [
        "CFBundleShortVersionString": "0.1",
        "CFBundleVersion": "3",
        BuildStamp.commitKey: "6ce5af1",
    ]

    /// The version, the build in brackets, then the commit.
    func testTheLineReadsVersionBuildAndCommit() {
        XCTAssertEqual(BuildStamp.line(full), "Version 0.1 (3), 6ce5af1")
    }

    /// A build from a tree with changes not committed says so.
    func testChangesNotCommittedAreSaid() {
        var info = full
        info[BuildStamp.changedKey] = true
        XCTAssertEqual(BuildStamp.line(info), "Version 0.1 (3), 6ce5af1 plus changes")
        info[BuildStamp.changedKey] = false
        XCTAssertEqual(BuildStamp.line(info), "Version 0.1 (3), 6ce5af1")
    }

    /// A missing or empty key is left out, never shown as a blank.
    func testAMissingKeyFallsBack() {
        var info = full
        info[BuildStamp.commitKey] = nil
        XCTAssertEqual(BuildStamp.line(info), "Version 0.1 (3)")
        info[BuildStamp.changedKey] = true
        XCTAssertEqual(BuildStamp.line(info), "Version 0.1 (3)", "no commit, nothing to have changed from")
        info[BuildStamp.commitKey] = "  "
        XCTAssertEqual(BuildStamp.line(info), "Version 0.1 (3)")
        info["CFBundleVersion"] = nil
        XCTAssertEqual(BuildStamp.line(info), "Version 0.1")
        info["CFBundleVersion"] = "3"
        info["CFBundleShortVersionString"] = ""
        XCTAssertEqual(BuildStamp.line(info), "Build 3")
        XCTAssertEqual(BuildStamp.line([:]), "Version not known")
        XCTAssertEqual(BuildStamp.line(["CFBundleVersion": 3]), "Version not known", "not a string")
    }

    /// The app's own Info.plist reads as its version and build, and has no
    /// commit typed into it: `package.sh` writes that from git.
    func testTheAppsInfoPlistReads() throws {
        let data = try Data(contentsOf: iosDir.appendingPathComponent("Resources/Info.plist"))
        let info = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let version = try XCTUnwrap(info["CFBundleShortVersionString"] as? String)
        let build = try XCTUnwrap(info["CFBundleVersion"] as? String)
        XCTAssertNil(info[BuildStamp.commitKey])
        XCTAssertNil(info[BuildStamp.changedKey])
        XCTAssertEqual(BuildStamp.line(info), "Version \(version) (\(build))")
    }

    /// `package.sh` writes both keys from git, by the names the app reads.
    func testPackagingStampsTheCommitFromGit() throws {
        let script = try String(contentsOf: iosDir.appendingPathComponent("package.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("COMMIT=$(git rev-parse --short=7 HEAD 2>/dev/null)"))
        XCTAssertTrue(script.contains(#"if [ -n "$(git status --porcelain -- . 2>/dev/null)" ]; then CHANGED=1; fi"#))
        XCTAssertTrue(script.contains(#"info["\#(BuildStamp.commitKey)"] = commit"#))
        XCTAssertTrue(script.contains(#"info["\#(BuildStamp.changedKey)"] = True"#))
    }

    /// The Connection log's text has the line at its top, a blank line
    /// under it, in the view and in what its share button sends.
    func testTheLogHasTheLineAtItsTop() throws {
        XCTAssertEqual(BuildStamp.atTop(of: "12:00:00.000 · one\n12:00:01.000 · two",
                                        stamp: "Version 0.1 (3), 6ce5af1"),
                       "Version 0.1 (3), 6ce5af1\n\n12:00:00.000 · one\n12:00:01.000 · two")
        let code = flat(try source("UI/DiagnosticsViewController.swift"))
        XCTAssertTrue(code.contains("textView.text = BuildStamp.atTop(of: text.isEmpty ? "), code)
        XCTAssertTrue(code.contains("activityItems: [BuildStamp.atTop(of: Diagnostics.transcript())]"))
    }

    /// Settings shows it at its foot, after everything he sets, in a
    /// caption's one label; no other screen does, the log aside.
    func testSettingsShowsItAtItsFoot() throws {
        let code = flat(try source("UI/SettingsViewController.swift"))
        XCTAssertTrue(code.contains("stack.addArrangedSubview(bringBackButton) "
                                    + "stack.addArrangedSubview(caption(BuildStamp.app)) "
                                    + "stack.axis = .vertical"), code)
        let ui = iosDir.appendingPathComponent("Sources/Blackmail/UI")
        let others = try FileManager.default.contentsOfDirectory(atPath: ui.path)
            .filter { $0.hasSuffix(".swift") }
            .filter { try source("UI/\($0)").contains("BuildStamp") }
            .sorted()
        XCTAssertEqual(others, ["DiagnosticsViewController.swift", "SettingsViewController.swift"])
    }

    private var iosDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// A source file, comment lines out.
    private func source(_ file: String) throws -> String {
        try String(contentsOf: iosDir.appendingPathComponent("Sources/Blackmail/\(file)"), encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).joined(separator: " ")
    }
}
