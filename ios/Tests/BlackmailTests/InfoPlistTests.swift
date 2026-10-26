import XCTest

/// The app's Info.plist, read as the build copies it (B-067).
final class InfoPlistTests: XCTestCase {

    private static let ios = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func info(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.ios.appendingPathComponent("Resources/\(name)"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil)
                             as? [String: Any])
    }

    private func appInfo() throws -> [String: Any] { try info("Info.plist") }

    /// Every Swift file under Sources, by its path under it, comment lines
    /// left out and the rest joined by spaces.
    private func code() throws -> [String: String] {
        let sources = Self.ios.appendingPathComponent("Sources")
        var files: [String: String] = [:]
        let walk = try XCTUnwrap(FileManager.default.enumerator(at: sources,
                                                                includingPropertiesForKeys: nil))
        for case let url as URL in walk where url.pathExtension == "swift" {
            files[String(url.path.dropFirst(sources.path.count + 1))] =
                try String(contentsOf: url, encoding: .utf8)
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.hasPrefix("//") }
                    .joined(separator: " ")
        }
        XCTAssertGreaterThan(files.count, 100, "the sources were found")
        return files
    }

    /// The files holding `text`, with how many times each does.
    private func count(_ text: String, in files: [String: String]) -> [String: Int] {
        files.compactMapValues { code in
            let n = code.components(separatedBy: text).count - 1
            return n == 0 ? nil : n
        }
    }

    /// "Save to Photos" on a picture in a letter ended the app: iOS ends
    /// any app that asks for the library without saying why. Both words
    /// are there, and say something.
    func testPhotosSaysWhyItIsAskedFor() throws {
        let info = try appInfo()
        for key in ["NSPhotoLibraryAddUsageDescription", "NSPhotoLibraryUsageDescription"] {
            let words = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(words?.isEmpty ?? true, key)
        }
    }

    /// Print asks for nothing (B-110): AirPrint's panel finds printers
    /// itself, so the app asks for no Local Network and names no Bonjour
    /// service, and the only words iOS shows for a permission are still the
    /// two for Photos, and since B-162 the one for Contacts, asked as he
    /// types in an address field (`ContactSuggestionsTests`).
    func testPrintAsksForNoPermission() throws {
        let info = try appInfo()
        XCTAssertEqual(info.keys.filter { $0.hasSuffix("UsageDescription") }.sorted(),
                       ["NSContactsUsageDescription", "NSPhotoLibraryAddUsageDescription",
                        "NSPhotoLibraryUsageDescription"])
        XCTAssertNil(info["NSLocalNetworkUsageDescription"])
        XCTAssertNil(info["NSBonjourServices"])
    }

    // MARK: - Dark from the launch (B-124)

    /// The launch screen, `UILaunchScreen` with nothing in it, is the
    /// system's plain screen in the app's style, drawn before any of its
    /// code runs: Light from the first commit, before D-010 made the app
    /// dark, it was white for about 130 ms before the dark rows at every
    /// cold launch. Dark, it is black, as the rows' canvas is. No colour or
    /// image of its own, there being no asset catalog to name one from,
    /// and the status bar's default style, its words light on it.
    func testTheLaunchScreenIsDark() throws {
        let info = try appInfo()
        XCTAssertEqual(info["UIUserInterfaceStyle"] as? String, "Dark")
        XCTAssertEqual((info["UILaunchScreen"] as? [String: Any]).map(\.isEmpty), true)
        XCTAssertEqual(info["UIStatusBarStyle"] as? String, "UIStatusBarStyleDefault")
    }

    /// What else the style reaches, read from the code: nothing he was not
    /// shown dark already. The app makes one window, pinned dark before
    /// anything is in it, so what is presented in it was dark whatever the
    /// plist said: the composer, every alert and sheet, Quick Look, the
    /// connection log's share sheet, the photo and file pickers, Go to
    /// Date's calendar, and the Print panel, a presentation over the pane
    /// (B-110's `PRINT panel over=true`). The paper stays light: its web
    /// view is pinned light and its page says so. The share extension has
    /// a plist of its own, with no style in it, and pins its sheet and its
    /// window dark itself. And nothing reads the app's style from outside
    /// a window.
    func testTheStyleReachesNothingThatWasNotDarkAlready() throws {
        let files = try code()
        XCTAssertEqual(count("UIWindow(", in: files), ["Blackmail/App/AppDelegate.swift": 1])
        let app = try XCTUnwrap(files["Blackmail/App/AppDelegate.swift"])
        let made = try XCTUnwrap(app.range(of: "let window = UIWindow("))
        let pinned = try XCTUnwrap(app.range(of: "window.overrideUserInterfaceStyle = .dark"))
        let filled = try XCTUnwrap(app.range(of: "window.rootViewController = Self.makeRoot()"))
        XCTAssertTrue(made.upperBound < pinned.lowerBound && pinned.upperBound < filled.lowerBound,
                      "pinned dark before anything is in it")

        XCTAssertEqual(count("overrideUserInterfaceStyle = .light", in: files),
                       ["Blackmail/UI/LetterPrint.swift": 1])
        XCTAssertTrue(try XCTUnwrap(files["Blackmail/UI/LetterPrint.swift"])
                        .contains("web.overrideUserInterfaceStyle = .light"))
        XCTAssertTrue(try XCTUnwrap(files["Blackmail/Mail/PrintPage.swift"])
                        .contains("<meta name=\"color-scheme\" content=\"light only\">"))

        let share = try XCTUnwrap(files["Blackmail/Share/ShareViewController.swift"])
        XCTAssertTrue(share.contains("overrideUserInterfaceStyle = .dark"))
        XCTAssertTrue(share.contains("view.window?.overrideUserInterfaceStyle = .dark"))
        XCTAssertNil(try info("ShareInfo.plist")["UIUserInterfaceStyle"])

        for outside in ["UITraitCollection.current", "UIScreen.main.traitCollection",
                        "overrideUserInterfaceStyle = .unspecified"] {
            XCTAssertEqual(count(outside, in: files), [:], outside)
        }
    }
}
