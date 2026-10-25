import XCTest

/// Whether TrollStore installs on an iPad, as `tools/provision-ipad.sh`
/// tells whoever is at his table (B-138). The rule is a shell function in
/// `tools/trollstore-range.sh`, which the script sources; here it is run in
/// bash on each version that matters, and the script read to see it uses
/// it.
///
/// TrollStore's README: "Supported versions: 14.0 beta 2 - 16.6.1, 16.7 RC
/// (20H18), 17.0", and "16.7.x (excluding 16.7 RC) and 17.0.1+ will NEVER
/// be supported".
final class ProvisionRangeTests: XCTestCase {

    private static let tools = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()     // BlackmailTests
        .deletingLastPathComponent()     // Tests
        .deletingLastPathComponent()     // ios
        .deletingLastPathComponent()     // the repo
        .appendingPathComponent("tools")

    private let bash = "/bin/bash"

    /// Each version and build through `trollstore_range`: its word and its
    /// exit status.
    private func range(_ cases: [(String, String)]) throws -> [String] {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: bash), "no bash here")
        let script = """
            . "$1"; shift
            while [ $# -gt 0 ]; do
                word=$(trollstore_range "$1" "$2"); status=$?
                printf '%s %s\\n' "$word" "$status"
                shift 2
            done
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bash)
        process.arguments = ["-c", script, "bash",
                             Self.tools.appendingPathComponent("trollstore-range.sh").path]
            + cases.flatMap { [$0.0, $0.1] }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let said = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errors = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, errors)
        XCTAssertEqual(errors, "", "nothing on stderr")
        return said.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
    }

    private func check(_ expected: String, _ cases: [(String, String)],
                       file: StaticString = #filePath, line: UInt = #line) throws {
        let said = try range(cases)
        XCTAssertEqual(said.count, cases.count, file: file, line: line)
        let status = expected == "in" ? 0 : 1
        for (index, (version, build)) in cases.enumerated() where index < said.count {
            XCTAssertEqual(said[index], "\(expected) \(status)", "\(version) (\(build))",
                           file: file, line: line)
        }
    }

    /// 14.0 to 16.6.1, the 16.7 RC by its build, and 17.0: in.
    func testTrollStoresVersionsAreIn() throws {
        try check("in", [
            ("14.0", "18A373"), ("14.8.1", "18H107"), ("15.0", "19A346"), ("15.7.9", "19H365"),
            ("16.0", "20A362"), ("16.5.1", "20F75"), ("16.6", "20G75"), ("16.6.1", "20G81"),
            ("16.7", "20H18"), ("17.0", "21A329"), ("17.0.0", "21A329"),
            // Read in base 10: "08" is eight, never a bad octal number.
            ("15.08", "19H12"), ("16.06.01", "20G81"),
        ])
    }

    /// Every 16.7 but the RC, 17.0.1 on, and every later iOS: past. His
    /// iPad's 18.7 among them. A 16.7 whose build was not read is not
    /// taken for the RC.
    func testEverythingAfterIsPast() throws {
        try check("past", [
            ("16.6.2", ""), ("16.7", "20H19"), ("16.7", ""), ("16.7.1", "20H30"),
            ("16.7.2", "20H115"), ("16.7.10", "20H350"), ("16.7.12", "20H364"),
            ("17.0.1", "21A340"), ("17.0.2", "21A350"), ("17.0.3", "21A360"),
            ("17.1", "21B74"), ("17.7.10", "21H450"), ("18.0", "22A3354"),
            ("18.7.9", "22H"), ("26.0.1", "23A355"),
        ])
    }

    /// Before 14.0: below, never in, as the old pattern had iOS 10 to 13.
    func testEverythingBeforeIsBelow() throws {
        try check("below", [
            ("13.7", "17H35"), ("13.99", ""), ("12.5.7", "16H81"), ("10.3.3", "14G60"),
            ("9.3.5", "13G36"), ("8.4.1", "12H321"), ("1.0", ""),
        ])
    }

    /// No version read, or one that is not a version: unknown.
    func testNoVersionIsUnknown() throws {
        try check("unknown", [
            ("", ""), ("x", ""), ("16.a", ""), ("16.6.1.1", ""), (" 16.6", ""), ("-16", ""),
            ("16..1", ""),
        ])
    }

    /// The script reads the build, sources the rule and says what it
    /// says; the old pattern is gone; the pre-flight wants the rule's file;
    /// and bash reads the script.
    func testTheScriptUsesTheRule() throws {
        let path = Self.tools.appendingPathComponent("provision-ipad.sh").path
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let code = text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
        XCTAssertTrue(code.contains("BUILD=$(ideviceinfo -u \"$UDID\" -k BuildVersion 2>/dev/null)"))
        XCTAssertTrue(code.contains("\n. \"$TOOLS/trollstore-range.sh\"\n"
                                    + "case \"$(trollstore_range \"$VER\" \"$BUILD\")\" in\n"))
        for branch in ["\n  in) ", "\n  below) ", "\n  past) ", "\n  *) "] {
            XCTAssertTrue(code.contains(branch), branch)
        }
        XCTAssertFalse(code.contains("1[0-6]"))
        XCTAssertFalse(code.contains("17.0.*"))
        XCTAssertTrue(code.contains(
            "for f in \"$TOOLS/sign-ipa.sh\" \"$TOOLS/check-signature.py\" \"$TOOLS/trollstore-range.sh\" \\"))
        // The rule is in one place.
        XCTAssertEqual(code.components(separatedBy: "trollstore_range").count - 1, 1)

        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: bash), "no bash here")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bash)
        process.arguments = ["-n", path]
        let err = Pipe()
        process.standardError = err
        try process.run()
        let errors = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, errors)
    }
}
