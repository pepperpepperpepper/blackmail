import Foundation

/// IEEE CRC-32, the one `zlib.crc32` computes, over bytes that come in
/// pieces (B-070).
///
/// What a letter's file is checked by before the terminating dot goes: the
/// file read for the wire must be the file read for the rehearsal, byte for
/// byte (`DataStream`). Logged as eight upper-case hex digits, so an iPad
/// check can compare a file that arrived with `zlib.crc32` on the host.
///
/// It finds a file that changed by accident: one rewritten, cut short or
/// grown while the letter went. It is not a seal against anyone who means
/// to change one.
struct CRC32 {

    private static let table: [UInt32] = (0..<256).map { index in
        var c = UInt32(index)
        for _ in 0..<8 {
            c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    private var state: UInt32 = 0xFFFF_FFFF

    init() {}

    /// The CRC of the bytes given so far.
    var value: UInt32 { state ^ 0xFFFF_FFFF }

    mutating func update(_ bytes: UnsafeRawBufferPointer) {
        guard !bytes.isEmpty else { return }
        var c = state
        Self.table.withUnsafeBufferPointer { table in
            for byte in bytes {
                c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
            }
        }
        state = c
    }

    mutating func update(_ data: Data) {
        data.withUnsafeBytes { update($0) }
    }

    /// `value` as the log has it: `CBF43926`.
    static func hex(_ value: UInt32) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 8 - digits.count)) + digits
    }
}
