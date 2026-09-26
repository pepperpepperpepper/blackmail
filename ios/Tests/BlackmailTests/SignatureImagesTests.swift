import XCTest
@testable import Blackmail

/// Tests for the pictures a signature's markup refers to by `cid:`.
///
/// Both images in Sam's real signature point at Google URLs, and both are
/// dead for recipients today. The bytes now travel with the letter instead,
/// and this store is where they live — its own defaults key, deliberately,
/// because putting a nested array on `MailAccount` is a decoding hazard for
/// every account already on disk.
final class SignatureImagesTests: XCTestCase {

    private func suite(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func image(_ id: String = "sig-logo",
                       base64: String = "aGVsbG8=") -> SignatureImages.InlineImage {
        SignatureImages.InlineImage(contentID: id, filename: "\(id).png",
                                    mimeType: "image/png", dataBase64: base64)
    }

    func testAFreshStoreIsEmpty() {
        XCTAssertTrue(SignatureImages.load(defaults: suite("fresh")).isEmpty)
    }

    func testImagesSurviveBeingSavedAndLoaded() {
        let d = suite("roundtrip")
        SignatureImages.save([image()], defaults: d)
        XCTAssertEqual(SignatureImages.load(defaults: d), [image()])
    }

    func testPartsDecodesTheBase64IntoBytes() {
        let d = suite("parts")
        SignatureImages.save([image(base64: "aGVsbG8=")], defaults: d)   // "hello"
        let parts = SignatureImages.parts(defaults: d)
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].contentID, "sig-logo")
        XCTAssertEqual(String(decoding: parts[0].data, as: UTF8.self), "hello")
    }

    func testAnEntryWhoseBytesWillNotDecodeIsDroppedNotSent() {
        // Sending a part with a garbage payload would deliver a broken
        // image — the exact thing this store exists to replace.
        let d = suite("junk")
        SignatureImages.save([image(base64: "not base64 !!"),
                              image("good", base64: "aGVsbG8=")], defaults: d)
        XCTAssertEqual(SignatureImages.parts(defaults: d).map(\.contentID), ["good"])
    }

    func testRemoveAllEmptiesTheStore() {
        let d = suite("clear")
        SignatureImages.save([image()], defaults: d)
        SignatureImages.removeAll(defaults: d)
        XCTAssertTrue(SignatureImages.load(defaults: d).isEmpty)
    }
}
