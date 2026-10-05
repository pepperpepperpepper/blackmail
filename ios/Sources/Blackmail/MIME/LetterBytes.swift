import Foundation

/// A letter's bytes, made in order from its plan and its files, a block at
/// a time (B-070): the text as it is, in slices of at most 64 KiB, and each
/// file as base64 from blocks of 58,368 of its bytes. The same bytes as
/// `RFC5322Builder.base64Wrapped` makes of the whole file, and so as
/// `build` made of the letter.
///
/// 58,368 is 57 × 1024, and 57 bytes make one line of 76 characters: a
/// block is exactly 1,024 lines, so where one block's base64 ends a line
/// ends too, and the next block begins with the CRLF between them. Each
/// block is Foundation's own `base64EncodedData()`, cut into lines here.
///
/// One buffer for what is read and one for what is made, each allocated
/// once: what this holds does not grow with the files. Each file's bytes
/// are counted and their CRC-32 kept as they are read, and at a file's last
/// block, before it is given, the file is read once more past its end,
/// which must give nothing (`longer`). For the wire (`Mode.wire`), each
/// file's count and CRC must also be the rehearsal's, or the letter is
/// stopped there (`changedDuringSend`).
struct LetterBytes {

    /// What is read of a file at once.
    static let blockBytes = 57 * 1024
    /// The most text given at once.
    static let textSlice = 64 * 1024

    enum Mode {
        /// The first pass: each file's count and CRC are found.
        case rehearsal
        /// The second: each file must be what the first found.
        case wire([(bytes: Int, crc: UInt32)])
    }

    private let plan: LetterPlan
    private let files: LetterFiles
    private let mode: Mode
    private let buffers: Buffers
    /// Where in the plan, and where in that piece.
    private var piece = 0
    private var offset = 0
    private var crc = CRC32()

    /// Every byte given so far.
    private(set) var count = 0
    /// Each file read to its end, its bytes and their CRC.
    private(set) var digests: [(bytes: Int, crc: UInt32)] = []

    init(plan: LetterPlan, files: LetterFiles, mode: Mode = .rehearsal) {
        self.plan = plan
        self.files = files
        self.mode = mode
        buffers = Buffers(read: Self.blockBytes,
                          made: max(Self.textSlice, 2 + RFC5322Builder.base64WrappedLength(Self.blockBytes)))
    }

    /// The next bytes of the letter, nil after its last. Valid until the
    /// next call. Throws `LetterSourceFailure` for a file that cannot be
    /// read, that is shorter or longer than its size, or, for the wire,
    /// that is not what the rehearsal read.
    mutating func next() throws -> UnsafeRawBufferPointer? {
        while piece < plan.pieces.count {
            switch plan.pieces[piece] {
            case .text(let text):
                guard offset < text.count else {
                    advance()
                    continue
                }
                let length = min(Self.textSlice, text.count - offset)
                text.withUnsafeBytes { source in
                    buffers.made.copyMemory(from: source.baseAddress! + offset, byteCount: length)
                }
                offset += length
                count += length
                return UnsafeRawBufferPointer(start: buffers.made, count: length)
            case .file(let index):
                let size = files.sizes[index]
                guard offset < size else {
                    // A file of nothing: no base64, and still its end.
                    try ended(index, size: size)
                    advance()
                    continue
                }
                let length = min(Self.blockBytes, size - offset)
                try fill(index, length: length, of: size)
                crc.update(UnsafeRawBufferPointer(start: buffers.read, count: length))
                let first = offset == 0
                offset += length
                let made = encode(length, first: first)
                if offset == size {
                    try ended(index, size: size)
                    advance()
                }
                count += made
                return UnsafeRawBufferPointer(start: buffers.made, count: made)
            }
        }
        return nil
    }

    private mutating func advance() {
        piece += 1
        offset = 0
        crc = CRC32()
    }

    /// `length` bytes of file `index` from `offset` into the read buffer,
    /// however many reads that takes.
    private func fill(_ index: Int, length: Int, of size: Int) throws {
        var got = 0
        while got < length {
            let read = try files.read(index, at: offset + got,
                                      into: UnsafeMutableRawBufferPointer(start: buffers.read + got,
                                                                          count: length - got))
            guard read > 0 else {
                throw LetterSourceFailure(file: index, reason: .shortRead(read: offset + got, of: size))
            }
            got += read
        }
    }

    /// File `index` read to its `size`: nothing after it, and for the wire
    /// the rehearsal's bytes.
    private mutating func ended(_ index: Int, size: Int) throws {
        var probe: UInt8 = 0
        let past = try withUnsafeMutableBytes(of: &probe) { try files.read(index, at: size, into: $0) }
        guard past == 0 else { throw LetterSourceFailure(file: index, reason: .longer) }
        let digest = (bytes: size, crc: crc.value)
        if case .wire(let rehearsed) = mode {
            guard index < rehearsed.count, rehearsed[index].bytes == digest.bytes,
                  rehearsed[index].crc == digest.crc else {
                throw LetterSourceFailure(file: index, reason: .changedDuringSend)
            }
        }
        digests.append(digest)
    }

    /// The read buffer's first `length` bytes as base64 lines into the made
    /// buffer, after a CRLF unless it is the file's first block. Returns
    /// how many bytes that made.
    private func encode(_ length: Int, first: Bool) -> Int {
        func lines() -> Int {
            let encoded = Data(bytesNoCopy: buffers.read, count: length, deallocator: .none)
                .base64EncodedData()
            return encoded.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                let target = buffers.made
                var written = 0
                if !first {
                    target.storeBytes(of: 0x0D, toByteOffset: 0, as: UInt8.self)
                    target.storeBytes(of: 0x0A, toByteOffset: 1, as: UInt8.self)
                    written = 2
                }
                var read = 0
                while read < source.count {
                    if read > 0 {
                        target.storeBytes(of: 0x0D, toByteOffset: written, as: UInt8.self)
                        target.storeBytes(of: 0x0A, toByteOffset: written + 1, as: UInt8.self)
                        written += 2
                    }
                    let line = min(76, source.count - read)
                    (target + written).copyMemory(from: source.baseAddress! + read, byteCount: line)
                    read += line
                    written += line
                }
                return written
            }
        }
        // What Foundation makes along the way goes with each block, not
        // with the whole file. Insurance the host cannot measure.
        #if canImport(ObjectiveC)
        return autoreleasepool { lines() }
        #else
        return lines()
        #endif
    }

    /// The two buffers, allocated once and let go of with the generator.
    private final class Buffers {
        let read: UnsafeMutableRawPointer
        let made: UnsafeMutableRawPointer

        init(read: Int, made: Int) {
            self.read = UnsafeMutableRawPointer.allocate(byteCount: read, alignment: 16)
            self.made = UnsafeMutableRawPointer.allocate(byteCount: made, alignment: 16)
        }

        deinit {
            read.deallocate()
            made.deallocate()
        }
    }
}
