import XCTest
@testable import Blackmail

/// A file's base64 made a block at a time (`LetterBytes`, B-070) is the
/// base64 the whole file always made (`RFC5322Builder.base64Wrapped`):
/// lines of 76, CRLF between them and none after the last, at every length
/// about a line's end and a block's, and however short the reads that fill
/// a block come back.
final class Base64BlockTests: XCTestCase {

    private static var lengths: [Int] {
        var lengths = Array(0...400)
        let block = LetterBytes.blockBytes
        for edge in [block, 2 * block, 3 * block] { lengths += [edge - 1, edge, edge + 1] }
        lengths.append(1_000_003)
        return lengths
    }

    /// One file and nothing else, made from `files`.
    private func base64(_ files: LetterFiles) throws -> String {
        var bytes = LetterBytes(plan: LetterPlan(pieces: [.file(0)]), files: files)
        var out = Data()
        var blocks = 0
        while let chunk = try bytes.next() {
            out.append(chunk.bindMemory(to: UInt8.self))
            blocks += 1
        }
        XCTAssertEqual(blocks, (files.sizes[0] + LetterBytes.blockBytes - 1) / LetterBytes.blockBytes)
        return String(decoding: out, as: UTF8.self)
    }

    func testABlockAtATimeIsTheWholeFilesBase64() throws {
        XCTAssertEqual(LetterBytes.blockBytes, 58_368)
        XCTAssertEqual(LetterBytes.blockBytes % 57, 0, "a block is whole lines")
        for length in Self.lengths {
            let data = LetterCorpus.bytes(length, seed: length)
            let made = try base64(LetterFiles(holding: [data]))
            XCTAssertEqual(made, RFC5322Builder.base64Wrapped(data), "\(length)")
            XCTAssertEqual(made.utf8.count, RFC5322Builder.base64WrappedLength(length), "\(length)")
        }
    }

    /// Reads that come back short, from 1 to 200 bytes at random, still
    /// fill each block before it is encoded: the same base64.
    func testShortReadsFillTheBlockAllTheSame() throws {
        var seed: UInt64 = 0x5EED_B070
        func random(_ range: ClosedRange<Int>) -> Int {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return range.lowerBound + Int(seed % UInt64(range.count))
        }
        let block = LetterBytes.blockBytes
        for length in Array(0...200) + [block - 1, block, block + 1, 2 * block + 7] {
            let data = LetterCorpus.bytes(length, seed: length + 1)
            let files = LetterFiles(holding: [data])
            files.cut = { _, _, asked in min(asked, random(1...200)) }
            XCTAssertEqual(try base64(files), RFC5322Builder.base64Wrapped(data), "\(length)")
        }
    }

    /// From the disk, read by descriptor, the same.
    func testFromTheDiskTheSame() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Base64BlockTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let block = LetterBytes.blockBytes
        for length in [0, 1, 57, block - 1, block, block + 1, 1_000_003] {
            let data = LetterCorpus.bytes(length, seed: length + 2)
            let url = directory.appendingPathComponent("\(length).bin")
            try data.write(to: url)
            let files = try LetterFiles(opening: [.disk(url, attachedSize: Int64(length))])
            XCTAssertEqual(try base64(files), RFC5322Builder.base64Wrapped(data), "\(length)")
            files.close()
        }
    }
}
