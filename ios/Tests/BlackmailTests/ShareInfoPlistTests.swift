import XCTest
@testable import Blackmail

/// The share extension's Info.plist, read as the iPad reads it: what it is
/// offered for, and how it is loaded. Five photos, five videos and five
/// files, as the composer's picker allows five (B-070); a page or a link
/// from Safari; words. `XPC!`, or it is installed and never loaded; and
/// the principal class `@objc(ShareViewController)` names.
final class ShareInfoPlistTests: XCTestCase {

    func testTheExtensionIsOfferedForWhatItCanSend() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/ShareInfo.plist")
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(
            from: try Data(contentsOf: url), format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "XPC!")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "wtf.uhoh.blackmail.share")
        let ext = try XCTUnwrap(plist["NSExtension"] as? [String: Any])
        XCTAssertEqual(ext["NSExtensionPointIdentifier"] as? String, "com.apple.share-services")
        XCTAssertEqual(ext["NSExtensionPrincipalClass"] as? String, "ShareViewController")
        let attributes = try XCTUnwrap(ext["NSExtensionAttributes"] as? [String: Any])
        let rule = try XCTUnwrap(attributes["NSExtensionActivationRule"] as? [String: Any])
        XCTAssertEqual(rule["NSExtensionActivationSupportsImageWithMaxCount"] as? Int, 5)
        XCTAssertEqual(rule["NSExtensionActivationSupportsMovieWithMaxCount"] as? Int, 5)
        XCTAssertEqual(rule["NSExtensionActivationSupportsFileWithMaxCount"] as? Int, 5)
        XCTAssertEqual(rule["NSExtensionActivationSupportsWebURLWithMaxCount"] as? Int, 1)
        XCTAssertEqual(rule["NSExtensionActivationSupportsWebPageWithMaxCount"] as? Int, 1)
        XCTAssertEqual(rule["NSExtensionActivationSupportsText"] as? Bool, true)
        XCTAssertEqual(rule.count, 6, "\(rule.keys.sorted())")
    }
}
