import XCTest
@testable import Blackmail

/// The CRC-32 a letter's files are checked by before the dot (B-070) is
/// IEEE's, `zlib.crc32`'s, so an iPad check can compare a file that arrived
/// on the host with stock tools; and the same in pieces as whole.
final class CRC32Tests: XCTestCase {

    private func crc(_ text: String) -> UInt32 {
        var crc = CRC32()
        crc.update(Data(text.utf8))
        return crc.value
    }

    func testTheCheckValueAndNothing() {
        XCTAssertEqual(crc("123456789"), 0xCBF4_3926)
        XCTAssertEqual(CRC32.hex(crc("123456789")), "CBF43926")
        XCTAssertEqual(crc(""), 0)
        XCTAssertEqual(CRC32.hex(0), "00000000")
        XCTAssertEqual(crc("The quick brown fox jumps over the lazy dog"), 0x414F_A339)
    }

    func testInPiecesAsWhole() {
        let data = LetterCorpus.bytes(100_003, seed: 70)
        var whole = CRC32()
        whole.update(data)
        for cut in [0, 1, 57, 58_368, 100_002, 100_003] {
            var pieces = CRC32()
            pieces.update(data.prefix(cut))
            pieces.update(data.dropFirst(cut))
            XCTAssertEqual(pieces.value, whole.value, "\(cut)")
        }
    }
}
