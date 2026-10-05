import XCTest
@testable import Blackmail

/// The planned letter is the letter `build` always made (B-070):
/// planned and made whole from bytes, planned and made from files on the
/// disk, and `ReferenceBuilder`, the builder frozen before B-070, all the
/// same to the byte, with the same boundary draws, and its length known
/// from the files' sizes alone. And what goes after DATA is the old payload
/// of it, however the stream is cut, with nothing the stuffer had to do.
final class LetterPlanTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LetterPlanTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        super.tearDown()
    }

    /// `c`'s files written to the disk, each as a source at its size.
    private func onDisk(_ c: LetterCase) throws -> [LetterSource] {
        try c.files.enumerated().map { index, file in
            let url = directory.appendingPathComponent("\(UUID().uuidString)-\(index)")
            try file.data.write(to: url)
            return .disk(url, attachedSize: Int64(file.data.count))
        }
    }

    private func made(_ plan: LetterPlan, _ files: LetterFiles) throws -> Data {
        var bytes = LetterBytes(plan: plan, files: files)
        var out = Data()
        while let chunk = try bytes.next() { out.append(chunk.bindMemory(to: UInt8.self)) }
        return out
    }

    /// Where two letters first differ, for a failure that says so.
    private func differ(_ one: Data, _ other: Data) -> String {
        let at = zip(one, other).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            ?? min(one.count, other.count)
        return "\(one.count) bytes against \(other.count), first difference at \(at)"
    }

    /// Every shape, body, header, name and size, from bytes and from
    /// the disk, is the reference builder's letter, with as many boundary
    /// draws; the plan's length is its count, known before a file is read.
    func testEveryShapeIsTheReferenceBuildersBytes() throws {
        let cases = LetterCorpus.cases
        XCTAssertGreaterThan(cases.count, 280)
        for c in cases {
            let referenceToken = Counting(), builtToken = Counting(), planToken = Counting()
            let reference = c.reference(referenceToken)
            let built = c.built(builtToken)
            let plan = c.plan(planToken)
            XCTAssertEqual(built, reference, "\(c.label): build, \(differ(built, reference))")
            XCTAssertEqual(builtToken.draws, referenceToken.draws, "\(c.label): build's draws")
            XCTAssertEqual(planToken.draws, referenceToken.draws, "\(c.label): plan's draws")
            XCTAssertEqual(plan.length(sizes: c.files.map(\.data.count)), reference.count, c.label)

            let rendered = plan.rendered(from: c.files.map(\.data))
            XCTAssertEqual(rendered, reference, "\(c.label): from bytes, \(differ(rendered, reference))")

            let files = try LetterFiles(opening: onDisk(c))
            XCTAssertEqual(files.sizes, c.files.map(\.data.count), c.label)
            let streamed = try made(plan, files)
            files.close()
            XCTAssertEqual(streamed, reference, "\(c.label): from the disk, \(differ(streamed, reference))")
        }
    }

    /// The builder's letters need no stuffing: QP writes a leading dot as
    /// `=2E`, base64 has none, and no header or boundary line begins with
    /// one, and every line break is CRLF already. So what goes after DATA is
    /// the letter as it is, then the terminator: three bytes, or five for a
    /// plain letter of one part that does not end in a line break (B-068),
    /// which gets a CRLF first.
    func testTheBuildersLettersNeedNoStuffing() {
        for c in LetterCorpus.cases {
            let raw = c.reference(Counting())
            let payload = SMTPClient.dataPayload(raw)
            let endsALine = raw.suffix(2) == Data([0x0D, 0x0A])
            XCTAssertTrue(endsALine || c.isPlainShape, "\(c.label): only one part may end open")
            XCTAssertEqual(payload.count - raw.count, endsALine ? 3 : 5, c.label)
            XCTAssertEqual(payload.prefix(raw.count), raw, "\(c.label): a dot was stuffed")
        }
    }

    /// Below the transport, the stream from the disk hands out exactly
    /// the old payload, in pieces of 64 KiB but the last, and says its
    /// counts before a byte of it goes. Each file's CRC is its bytes'.
    func testTheStreamIsTheOldPayloadInPiecesOf64KiB() throws {
        for c in LetterCorpus.cases where c.label.hasPrefix("size") || c.label.hasPrefix("every") {
            let plan = c.plan(Counting())
            let reference = c.reference(Counting())
            let payload = SMTPClient.dataPayload(reference)
            let files = try LetterFiles(opening: onDisk(c))
            defer { files.close() }
            let stream = try DataStream(plan: plan, files: files)
            XCTAssertEqual(stream.rawCount, reference.count, c.label)
            XCTAssertEqual(stream.total, payload.count, c.label)
            XCTAssertEqual(stream.rehearsal.files.map(\.bytes), c.files.map(\.data.count), c.label)
            var crcs: [UInt32] = []
            for file in c.files {
                var crc = CRC32()
                crc.update(file.data)
                crcs.append(crc.value)
            }
            XCTAssertEqual(stream.rehearsal.files.map(\.crc), crcs, c.label)

            var pieces: [Data] = []
            try stream.begin()
            while let piece = try stream.next() { pieces.append(piece) }
            XCTAssertEqual(pieces.dropLast().map(\.count),
                           Array(repeating: DataStream.pieceBytes, count: max(0, pieces.count - 1)),
                           c.label)
            XCTAssertLessThanOrEqual(pieces.last?.count ?? 0, DataStream.pieceBytes)
            let joined = pieces.reduce(Data(), +)
            XCTAssertEqual(joined, payload, "\(c.label): \(differ(joined, payload))")
        }
    }

    /// The stream is one pass: asked again after its last piece, or
    /// claimed again, it refuses, rather than hand out a second letter, or
    /// a second dot.
    func testAStreamGoesOnce() throws {
        let stream = try DataStream(raw: Data("Subject: x\r\n\r\nx\r\n".utf8))
        var pieces = 0
        try stream.begin()
        while try stream.next() != nil { pieces += 1 }
        XCTAssertEqual(pieces, 1)
        XCTAssertThrowsError(try stream.next()) { error in
            XCTAssertEqual(error as? LetterSourceFailure, Self.refused)
        }
        XCTAssertThrowsError(try stream.begin()) { error in
            XCTAssertEqual(error as? LetterSourceFailure, Self.refused)
        }
    }

    /// A pass cut off part of the way, as a write is by its deadline, is
    /// never taken up again: claimed a second time it refuses, and so does
    /// every piece asked for after, so the rest of the letter never goes
    /// as a letter of its own, headless, with a dot. A piece asked for with
    /// no claim at all is refused the same, and the claim after it too.
    func testAStreamCutOffPartOfTheWayIsNeverTakenUpAgain() throws {
        let stream = try DataStream(raw: LetterCorpus.bytes(300_000, seed: 9))
        try stream.begin()
        XCTAssertEqual(try stream.next()?.count, DataStream.pieceBytes)
        XCTAssertThrowsError(try stream.begin()) { error in
            XCTAssertEqual(error as? LetterSourceFailure, Self.refused)
        }
        XCTAssertThrowsError(try stream.next()) { error in
            XCTAssertEqual(error as? LetterSourceFailure, Self.refused)
        }

        let unclaimed = try DataStream(raw: LetterCorpus.bytes(300_000, seed: 9))
        XCTAssertThrowsError(try unclaimed.next()) { error in
            XCTAssertEqual(error as? LetterSourceFailure, Self.refused)
        }
        XCTAssertThrowsError(try unclaimed.begin()) { error in
            XCTAssertEqual(error as? LetterSourceFailure, Self.refused)
        }

        let twice = try DataStream(raw: LetterCorpus.bytes(300_000, seed: 9))
        try twice.begin()
        XCTAssertThrowsError(try twice.begin()) { error in
            XCTAssertEqual(error as? LetterSourceFailure, Self.refused)
        }
        XCTAssertThrowsError(try twice.next())
    }

    private static let refused = LetterSourceFailure(file: nil, reason: .countMismatch)
}
