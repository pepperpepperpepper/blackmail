import XCTest
@testable import Blackmail

/// Mail's sent sound, as the composer and the share sheet play it (B-100).
///
/// When it plays is `ComposeActions`' and `ShareSheet`'s, which run here
/// (`ComposeActionsTests`, `ShareSheetTests`, `OutboxTests`). What plays is
/// UIKit's side, which never builds on this host, so it is read from the
/// source, as `SteadyChromeTests` reads the screens': comment lines out, and
/// runs of white space as one space. One system sound, named once, called
/// from the two sheets alone, and AudioToolbox imported by those two files
/// and no other, each inside its guard, so nothing that builds on this host
/// needs it.
final class SentSoundTests: XCTestCase {

    private static let composer = "Blackmail/UI/ComposeViewController.swift"
    private static let share = "Blackmail/Share/ShareViewController.swift"
    private static let call = "AudioServicesPlaySystemSound(ComposeViewController.sentMailSound)"

    private var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources")
    }

    /// Every Swift file under `Sources`, the app's, the library's and the
    /// extension's, by its path under it, read as code.
    private func everySource() throws -> [String: String] {
        let root = sources.standardizedFileURL.path + "/"
        var found: [String: String] = [:]
        let walk = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = walk?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let path = url.standardizedFileURL.path
            found[String(path.dropFirst(root.count))] = try code(of: url)
        }
        return found
    }

    private func code(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    private func count(_ text: String, in code: String) -> Int {
        code.components(separatedBy: text).count - 1
    }

    /// AudioToolbox is imported by the two sheets' UIKit files and nothing
    /// else: nothing under `Mail/`, not `ShareSheet.swift`, nothing that
    /// builds on this host. In each, after the guard that leaves the file
    /// out of the host's build.
    func testOnlyTheTwoSheetsImportAudioToolboxInsideTheirGuards() throws {
        let all = try everySource()
        XCTAssertGreaterThan(all.count, 100, "the sources were found")
        let importing = all.filter { $0.value.contains("import AudioToolbox") }.keys.sorted()
        XCTAssertEqual(importing, [Self.share, Self.composer])
        XCTAssertEqual(all.keys.filter { $0.hasPrefix("Blackmail/Mail/") && all[$0]!.contains("AudioToolbox") },
                       [])
        XCTAssertFalse(try XCTUnwrap(all["Blackmail/Share/ShareSheet.swift"]).contains("AudioToolbox"))
        for file in importing {
            let code = try XCTUnwrap(all[file])
            let guarded = try XCTUnwrap(code.range(of: "#if canImport(UIKit)"), file)
            let imported = try XCTUnwrap(code.range(of: "import AudioToolbox"), file)
            XCTAssertLessThan(guarded.lowerBound, imported.lowerBound, file)
            XCTAssertEqual(count("import AudioToolbox", in: code), 1, file)
        }
    }

    /// One call in each sheet, of the one sound, named once: mail-sent.caf,
    /// 1001, in the composer. No alert sound, which vibrates where the iPad
    /// can, and no other system sound anywhere.
    func testTheTwoSheetsPlayTheOneSoundNamedOnce() throws {
        let all = try everySource()
        let calling = all.filter { $0.value.contains("AudioServicesPlaySystemSound(") }.keys.sorted()
        XCTAssertEqual(calling, [Self.share, Self.composer])
        for file in calling {
            let code = try XCTUnwrap(all[file])
            XCTAssertEqual(count("AudioServicesPlaySystemSound(", in: code), 1, file)
            XCTAssertEqual(count(Self.call, in: code), 1, "\(file): the sound by its name")
        }
        XCTAssertEqual(all.filter { $0.value.contains("AudioServicesPlayAlertSound") }.keys.sorted(), [])
        XCTAssertEqual(all.filter { $0.value.contains("SystemSoundID") }.keys.sorted(), [Self.composer])
        let composer = try XCTUnwrap(all[Self.composer])
        XCTAssertEqual(count("static let sentMailSound: SystemSoundID = 1001", in: composer), 1)
        XCTAssertEqual(count("1001", in: composer), 1, "the number named once")
        XCTAssertEqual(count("1001", in: try XCTUnwrap(all[Self.share])), 0)
    }

    /// Each sheet hands the sound to the hook that plays it as the sheet
    /// closes after Send: the composer to its `ComposeActions`, the share
    /// sheet to its `ShareSheet`, and to nothing else.
    func testEachSheetHandsTheSoundToItsSendAndNothingElse() throws {
        let all = try everySource()
        let composer = try XCTUnwrap(all[Self.composer])
        XCTAssertTrue(composer.contains(
            "queued: { [weak self] in self?.queuedOnClose = true }, sent: { \(Self.call) })"),
            "the composer's ComposeActions")
        let share = try XCTUnwrap(all[Self.share])
        XCTAssertTrue(share.contains(
            "sheet = ShareSheet( shared: shared, transport: TLSConnection.factory, "
                + "memory: { SharedPhoto.memory() }, noteSent: { ShareMirror.device.noteSent($0) }, "
                + "finish: finish, cancel: cancel, sent: { \(Self.call) },"),
            "the share sheet's ShareSheet")
    }
}
