import XCTest

/// The app's Info.plist, read as the build copies it (B-067).
final class InfoPlistTests: XCTestCase {

    private func appInfo() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil)
                             as? [String: Any])
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
}
