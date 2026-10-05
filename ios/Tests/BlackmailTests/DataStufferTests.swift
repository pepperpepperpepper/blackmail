import XCTest
@testable import Blackmail

/// The stuffer a letter goes through a piece at a time (B-070): the same
/// bytes, however the letter is cut, as the stuffer `DataPayloadTests`
/// keeps as its reference, which went a byte at a time through the whole
/// letter. The cuts that matter are the ones through a line break's CR and
/// LF and just before a dot that begins a line.
final class DataStufferTests: XCTestCase {

    /// The payload as `transmit` made it before P5a, a byte at a time:
    /// `DataPayloadTests.previousPayload`, kept here too so this holds the
    /// stuffer to something that is not itself.
    private func previousPayload(_ raw: Data) -> Data {
        let cr: UInt8 = 0x0D, lf: UInt8 = 0x0A, dot: UInt8 = 0x2E
        var out = Data()
        var atLineStart = true
        var index = raw.startIndex
        while index < raw.endIndex {
            let byte = raw[index]
            if byte == cr || byte == lf {
                out.append(cr)
                out.append(lf)
                let next = raw.index(after: index)
                if byte == cr, next < raw.endIndex, raw[next] == lf {
                    index = next
                }
                atLineStart = true
            } else {
                if atLineStart && byte == dot { out.append(dot) }
                out.append(byte)
                atLineStart = false
            }
            index = raw.index(after: index)
        }
        if !(out.count >= 2 && out.suffix(2) == Data([0x0D, 0x0A])) {
            out.append(contentsOf: [0x0D, 0x0A])
        }
        out.append(contentsOf: [0x2E, 0x0D, 0x0A])
        return out
    }

    /// `raw` cut at `cuts`, each piece stuffed in turn, then the terminator.
    private func stuffed(_ raw: [UInt8], cutAt cuts: [Int]) -> Data {
        var stuffer = DataStuffer()
        var out: [UInt8] = []
        var start = 0
        for end in cuts + [raw.count] where end >= start {
            raw[start..<end].withUnsafeBytes { stuffer.stuff($0, into: &out) }
            start = end
        }
        let tail = stuffer.finishCount
        let before = out.count
        stuffer.finish(into: &out)
        XCTAssertEqual(out.count - before, tail, "finishCount")
        return Data(out)
    }

    private let awkward = [
        "", ".", "..", "\r\n", "\n", "\r", ".\r\n", "\r\n.\r\n", "\r\n.", ".\r\n.",
        "a\r\n.\r\nb", ".start", "end.", "end\r\n.", "a\n.b", "a\r.b", "a\r\n.\r\nb\r\n",
        ".\n.\r.\r\n.", "...\r\n....\r\n.....", "\n\n\r\r\r\n\n\r", "\r\n\r\n.\r\n\r\n",
        "\n\r.", "\r\r\n.", "no line break at the end", "ends in a lone LF\n",
        "ends in a lone CR\r", "ends in LF CR\n\r", String(repeating: ".\r\n", count: 50),
    ]

    /// Every awkward letter, whole, cut once at every place, cut twice at
    /// every pair of places when it is short, and fed a byte at a time.
    func testEveryCutOfAnAwkwardLetterIsTheWholeLettersPayload() {
        for text in awkward {
            let raw = Array(text.utf8)
            let expected = previousPayload(Data(raw))
            XCTAssertEqual(stuffed(raw, cutAt: []), expected, text.debugDescription)
            XCTAssertEqual(SMTPClient.dataPayload(Data(raw)), expected, text.debugDescription)
            for cut in 0...raw.count {
                XCTAssertEqual(stuffed(raw, cutAt: [cut]), expected, "\(text.debugDescription) at \(cut)")
            }
            if raw.count <= 12 {
                for one in 0...raw.count {
                    for two in one...raw.count {
                        XCTAssertEqual(stuffed(raw, cutAt: [one, two]), expected,
                                       "\(text.debugDescription) at \(one), \(two)")
                    }
                }
            }
            XCTAssertEqual(stuffed(raw, cutAt: Array(0..<raw.count)), expected,
                           "\(text.debugDescription) a byte at a time")
        }
    }

    /// 20,000 letters of dots, line breaks, a letter and a space, cut at
    /// random: each the whole letter's payload.
    func testRandomLettersCutAtRandomAreTheWholeLettersPayload() {
        var seed: UInt64 = 0xB070_5EED_0000_0001
        func random(_ bound: Int) -> Int {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Int(seed % UInt64(bound))
        }
        let alphabet: [UInt8] = [0x2E, 0x0D, 0x0A, 0x61, 0x20]
        for round in 0..<20_000 {
            let raw = (0..<random(40)).map { _ in alphabet[random(alphabet.count)] }
            let cuts = (0..<random(6)).map { _ in random(raw.count + 1) }.sorted()
            let made = stuffed(raw, cutAt: cuts)
            let expected = previousPayload(Data(raw))
            if made != expected {
                XCTFail("round \(round): \(raw) cut at \(cuts)")
                return
            }
        }
    }

    /// The count the rehearsal keeps is the bytes the wire gets.
    func testTheCountIsTheBytes() {
        for text in awkward {
            var stuffer = DataStuffer()
            var counted = StuffedCount()
            Array(text.utf8).withUnsafeBytes { stuffer.stuff($0, into: &counted) }
            stuffer.finish(into: &counted)
            XCTAssertEqual(counted.count, previousPayload(Data(text.utf8)).count, text.debugDescription)
        }
    }
}
