import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A letter's files, held open from before the letter is made until its
/// attempt has ended (B-070).
///
/// Each file on the disk is opened once, by descriptor, and read by
/// position (`pread`). So the letter goes whole even when the file's name
/// is taken away while it goes: a second share's purge in the same
/// extension, or LocalDrafts tidying a letter's folder. And so the two
/// passes over it, the rehearsal and the wire (`DataStream`), read the
/// same file.
///
/// Opened, a file is checked before anything is said to a server: it must
/// be a regular file, never a directory or a pipe, and the size it was
/// when it was attached, where that is known. A share's staged copy is
/// measured once it is copied (`ShareItems.Staging.file`); a photo from the
/// composer is the size of the bytes written; a letter kept on the iPad
/// links its photos, the same file. Any other size is a file that changed.
/// A file whose size when attached is not known is not checked, and
/// `Submission` logs it so.
///
/// POSIX, not `FileHandle`, whose reads at the end of a file differ
/// between this host and the iPad. Closed by `Submission.send` on every
/// way out, and when let go of besides. Never more than one consumer.
final class LetterFiles {

    private enum Held {
        case bytes(Data)
        case descriptor(Int32)
        case closed
    }

    private var held: [Held]

    /// Each file's size: the descriptor's `fstat`, or the bytes' count.
    let sizes: [Int]

    /// For a test: how many of the `asked` bytes at `offset` of file `file`
    /// a read gives, fewer than asked as a short read, nought as the end of
    /// the file; or what it throws. Nil, every read is the system's.
    var cut: ((_ file: Int, _ offset: Int, _ asked: Int) throws -> Int)?

    /// Opens every file on the disk, and holds every one in memory as it
    /// is. Throws `LetterSourceFailure` for the first that cannot go, with
    /// every one opened before it closed again.
    init(opening sources: [LetterSource]) throws {
        var held: [Held] = []
        var sizes: [Int] = []
        do {
            for (index, source) in sources.enumerated() {
                switch source {
                case .bytes(let data):
                    held.append(.bytes(data))
                    sizes.append(data.count)
                case let .disk(url, attachedSize):
                    let opened = try Self.open(url, index: index, attachedSize: attachedSize)
                    held.append(.descriptor(opened.descriptor))
                    sizes.append(opened.size)
                }
            }
        } catch {
            for case .descriptor(let descriptor) in held { _ = systemClose(descriptor) }
            throw error
        }
        self.held = held
        self.sizes = sizes
    }

    /// Bytes in memory only, which cannot fail to open.
    init(holding data: [Data]) {
        held = data.map { .bytes($0) }
        sizes = data.map(\.count)
    }

    deinit {
        close()
    }

    private static func open(_ url: URL, index: Int, attachedSize: Int64?) throws
        -> (descriptor: Int32, size: Int) {
        // Not blocking, so a pipe in a file's place is refused below rather
        // than waited on for a writer. A regular file reads the same either
        // way.
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return systemOpen(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        }
        guard descriptor >= 0 else {
            throw LetterSourceFailure(file: index, reason: .notOpenable(errno))
        }
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            let failed = errno
            _ = systemClose(descriptor)
            throw LetterSourceFailure(file: index, reason: .notOpenable(failed))
        }
        // S_IFMT and S_IFREG, written out: their types differ between
        // Glibc and Darwin.
        guard UInt32(status.st_mode) & 0o170000 == 0o100000 else {
            _ = systemClose(descriptor)
            throw LetterSourceFailure(file: index, reason: .notAFile)
        }
        let size = Int64(status.st_size)
        if let attachedSize, attachedSize != size {
            _ = systemClose(descriptor)
            throw LetterSourceFailure(file: index, reason: .changedSinceAttached(attached: attachedSize,
                                                                                 now: size))
        }
        return (descriptor, Int(size))
    }

    /// Up to `buffer.count` bytes of file `index` from `offset`, into
    /// `buffer`: how many, fewer at the end of the file, nought past it.
    /// Throws `unreadable` for a read the system refuses, or a file closed.
    func read(_ index: Int, at offset: Int, into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        var asked = buffer.count
        if let cut { asked = min(asked, max(0, try cut(index, offset, asked))) }
        guard asked > 0 else { return 0 }
        switch held[index] {
        case .bytes(let data):
            guard offset < data.count else { return 0 }
            let count = min(asked, data.count - offset)
            data.withUnsafeBytes { source in
                buffer.baseAddress!.copyMemory(from: source.baseAddress! + offset, byteCount: count)
            }
            return count
        case .descriptor(let descriptor):
            while true {
                let read = pread(descriptor, buffer.baseAddress, asked, off_t(offset))
                if read >= 0 { return read }
                if errno == EINTR { continue }
                throw LetterSourceFailure(file: index, reason: .unreadable(errno))
            }
        case .closed:
            throw LetterSourceFailure(file: index, reason: .unreadable(EBADF))
        }
    }

    /// Lets every descriptor go. Called more than once, harmlessly; a read
    /// after it fails rather than reading whatever took the number since.
    func close() {
        for index in held.indices {
            if case .descriptor(let descriptor) = held[index] { _ = systemClose(descriptor) }
            held[index] = .closed
        }
    }
}

/// Why a letter's file could not go, or why a letter was stopped before its
/// terminating dot (B-070). Numbers only in what it says.
///
/// Not a `MailError`: he reads "Message was not sent.", as for a file that
/// could not be read whole before (`SMTPClient.userFacing`).
struct LetterSourceFailure: Error, Equatable {

    enum Reason: Equatable {
        case notOpenable(Int32)
        case notAFile
        case changedSinceAttached(attached: Int64, now: Int64)
        case shortRead(read: Int, of: Int)
        /// More than its size: the file grew.
        case longer
        case unreadable(Int32)
        /// Read again for the wire, not the bytes the rehearsal read.
        case changedDuringSend
        /// Not as many bytes as were counted.
        case countMismatch
    }

    /// Which of the letter's files, from nought; nil for the letter as a
    /// whole.
    let file: Int?
    let reason: Reason

    /// The reason as the log has it.
    var words: String {
        switch reason {
        case .notOpenable(let number): return "not openable errno=\(number)"
        case .notAFile: return "not a file"
        case let .changedSinceAttached(attached, now): return "size \(now) attached \(attached)"
        case let .shortRead(read, of): return "short read \(read) of \(of)"
        case .longer: return "longer than its size"
        case .unreadable(let number): return "unreadable errno=\(number)"
        case .changedDuringSend: return "changed since the rehearsal"
        case .countMismatch: return "count mismatch"
        }
    }

    /// The file as the log numbers it, from one, or "-" for the letter.
    var fileNumber: String { file.map { "\($0 + 1)" } ?? "-" }
}

#if canImport(Darwin)
private func systemOpen(_ path: UnsafePointer<CChar>, _ flags: Int32) -> Int32 {
    Darwin.open(path, flags)
}
private func systemClose(_ descriptor: Int32) -> Int32 { Darwin.close(descriptor) }
#elseif canImport(Glibc)
private func systemOpen(_ path: UnsafePointer<CChar>, _ flags: Int32) -> Int32 {
    Glibc.open(path, flags)
}
private func systemClose(_ descriptor: Int32) -> Int32 { Glibc.close(descriptor) }
#endif
