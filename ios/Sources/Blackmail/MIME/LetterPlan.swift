import Foundation

/// Where a file of a letter comes from at Send (B-070): bytes already in
/// memory, a forward's part fetched from the server; or a file on this
/// iPad, a photo or a video he attached, with the size it had when it was
/// attached, nil where that is not known.
enum LetterSource {
    case bytes(Data)
    case disk(URL, attachedSize: Int64?)
}

/// A letter as `RFC5322Builder.plan` makes it: every header, boundary,
/// part header and line of text as bytes, and each file as a place for its
/// base64, by its index among the letter's files (B-070).
///
/// Pure. It says what the letter is and nothing is read to make it; its
/// exact length is known from the files' sizes alone (`length`). Reading
/// the files, and making their base64, belong to `LetterBytes`, which
/// makes the same bytes for a draft's APPEND (`rendered`) and for SMTP's
/// DATA (`DataStream`).
struct LetterPlan {

    enum Piece {
        case text(Data)
        /// The file at this index, as base64 in 76-character lines with
        /// CRLF between them and none after the last
        /// (`RFC5322Builder.base64Wrapped`).
        case file(Int)
    }

    let pieces: [Piece]

    /// The letter's bytes, for files of `sizes` bytes: its text, and each
    /// file's base64 as `base64WrappedLength` counts it.
    func length(sizes: [Int]) -> Int {
        pieces.reduce(0) { total, piece in
            switch piece {
            case .text(let text): return total + text.count
            case .file(let index): return total + RFC5322Builder.base64WrappedLength(sizes[index])
            }
        }
    }

    /// The whole letter in one `Data` of its exact length, its files' bytes
    /// given: what `RFC5322Builder.build` returns, for a draft's APPEND.
    /// Made by `LetterBytes`, so a draft's base64 is SMTP's, block for
    /// block.
    func rendered(from data: [Data]) -> Data {
        let files = LetterFiles(holding: data)
        var out = Data(capacity: length(sizes: files.sizes))
        var bytes = LetterBytes(plan: self, files: files)
        do {
            while let chunk = try bytes.next() {
                out.append(chunk.bindMemory(to: UInt8.self))
            }
        } catch {
            // Bytes in memory are read without a system call, to their
            // exact count, and nothing is compared: nothing here can fail.
            preconditionFailure("a letter from memory failed: \(error)")
        }
        return out
    }
}
