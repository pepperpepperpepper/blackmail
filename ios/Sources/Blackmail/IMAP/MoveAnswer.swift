import Foundation

/// What the answer to a `UID MOVE` or a `UID COPY` of one letter says
/// became of that letter (B-092).
///
/// A tagged OK is not enough. On the test iPad on 2026-10-21 Gmail answered
/// `UID MOVE 343 "[Gmail]/Trash"`, sent in the Inbox, where 343 was, with
/// `OK [COPYUID 2 343 0] (Success)` and no EXPUNGE, and nothing had moved:
/// the letter was in the Inbox still and not in the Trash. 0 is no UID
/// (RFC 4315's `nz-number`), so the answer gave the letter no place in the
/// Trash in its own words. Of about 116 MOVEs in the connection logs kept,
/// 112 were answered with a COPYUID with a UID in it, and one, sent in the
/// wrong mailbox (B-039), with no COPYUID. So the answer is read for the
/// letter itself.
///
/// Out of `IMAPClient`, pure, for the suite.
struct IMAPMoveAnswer: Equatable {

    /// What the answer's COPYUID says of the letter.
    enum CopyUID: String, Equatable {
        /// The answer has none: a server without UIDPLUS, or Gmail's `OK
        /// Success` to a MOVE of a UID the mailbox does not hold, as it
        /// answered one sent in the wrong mailbox on 2026-09-28 (B-039).
        case none
        /// One whose source set holds the letter, with as many UIDs in the
        /// destination, none of them 0.
        case names
        /// One whose source set holds the letter, with 0 among the UIDs in
        /// the destination, as Gmail's on the iPad.
        case zero = "dest-0"
        /// One that does not hold the letter, or cannot be read.
        case other
    }

    let copyUID: CopyUID

    /// Whether the answer has an EXPUNGE. It names a sequence number, not a
    /// UID, and can be for any letter: one another program or a Gmail
    /// filter took out of the mailbox at that moment rides on whatever the
    /// connection is answered next, a Delete's MOVE as much as a NOOP (RFC
    /// 3501 §7.4.1, `IMAPClient.askForNews`).
    let expunged: Bool

    /// A MOVE's answer that shows the letter moved: a COPYUID naming it; or
    /// an EXPUNGE, only where there is no COPYUID at all and the server
    /// gives none, having no UIDPLUS (`uidPlus` false).
    ///
    /// An EXPUNGE cannot be tied to the letter, so it is not taken for the
    /// letter's against a COPYUID that gives it no place, a 0 as on the
    /// iPad or another letter's: that answer with an EXPUNGE for a letter
    /// taken out elsewhere riding on it would be B-092 again. Nor where a
    /// server with UIDPLUS has given no COPYUID: every MOVE Gmail did had
    /// one, and its `OK Success` with none moved nothing (B-039). A server
    /// without UIDPLUS has nothing more to say than the EXPUNGE.
    func showsMove(uidPlus: Bool) -> Bool {
        switch copyUID {
        case .names: return true
        case .zero, .other: return false
        case .none: return expunged && !uidPlus
        }
    }

    /// A COPY's answer with nothing against it: a COPYUID naming the letter,
    /// or none at all, from a server that does not give one. A COPY takes
    /// nothing out, so there is no EXPUNGE to read.
    var showsCopy: Bool { copyUID == .names || copyUID == .none }

    /// For the connection log: `copyuid=dest-0 no-expunge`. Numbers and
    /// words of the protocol, nothing of the letter.
    var described: String {
        "copyuid=\(copyUID.rawValue) " + (expunged ? "expunge" : "no-expunge")
    }

    init(copyUID: CopyUID, expunged: Bool) {
        self.copyUID = copyUID
        self.expunged = expunged
    }

    /// The answer to a MOVE or COPY of `uid` alone. The COPYUID comes on the
    /// tagged OK from Gmail, `a234 OK [COPYUID 2 344 288] (Success)` after
    /// `* 68 EXPUNGE`, and on an untagged OK before the EXPUNGEs as RFC 6851
    /// has it; either is read. Of several, the one that names the letter.
    init(_ answer: IMAPCommandResult, uid: UInt32) {
        let read = Self.copyUIDArguments(in: answer).map { Self.classify($0, uid: uid) }
        let order: [CopyUID] = [.names, .zero, .other]
        copyUID = order.first { read.contains($0) } ?? .none
        expunged = IMAPParser.sizeChanges(after: answer.untagged, from: 0)?.expunged ?? false
    }

    /// Where the answer to a MOVE or COPY of `uid` alone says the letter
    /// went: the destination's UIDVALIDITY and the letter's UID there, from
    /// the COPYUID that names it with a UID for it (`names`), at the place
    /// it has in the source set. Nil from any other answer: none, a 0 as
    /// Gmail's on the iPad, or one for other letters. For the letter's Undo
    /// (B-157), which moves it back from there.
    static func landing(in answer: IMAPCommandResult, uid: UInt32) -> IMAPMoveLanding? {
        for argument in copyUIDArguments(in: answer) where classify(argument, uid: uid) == .names {
            let parts = argument.split(separator: " ", omittingEmptySubsequences: true)
            guard let validity = number(parts[0]), let source = ranges(parts[1]),
                  let destination = ranges(parts[2]),
                  let place = offset(of: uid, in: source),
                  let landed = self.uid(at: place, in: destination) else { continue }
            return IMAPMoveLanding(validity: validity, uid: landed)
        }
        return nil
    }

    /// How far into `ranges` `uid` is, counted from 0 in the order they are
    /// written, each from its low end.
    private static func offset(of uid: UInt32, in ranges: [ClosedRange<UInt32>]) -> UInt64? {
        var before: UInt64 = 0
        for range in ranges {
            if range.contains(uid) { return before + UInt64(uid - range.lowerBound) }
            before += UInt64(range.upperBound - range.lowerBound) + 1
        }
        return nil
    }

    /// The UID `offset` into `ranges`, counted as `offset(of:in:)` counts.
    private static func uid(at offset: UInt64, in ranges: [ClosedRange<UInt32>]) -> UInt32? {
        var left = offset
        for range in ranges {
            let size = UInt64(range.upperBound - range.lowerBound) + 1
            if left < size { return range.lowerBound + UInt32(left) }
            left -= size
        }
        return nil
    }

    /// The arguments of every COPYUID in the answer: on its tagged OK, as
    /// Gmail puts it, and on an untagged OK, as RFC 6851 has it.
    private static func copyUIDArguments(in answer: IMAPCommandResult) -> [String] {
        ([copyUIDArgument(in: answer.detail)]
            + answer.untagged.map { line -> String? in
                let words = line.text.split(separator: " ", maxSplits: 2)
                guard words.count == 3, words[0] == "*", words[1].uppercased() == "OK" else { return nil }
                return copyUIDArgument(in: String(words[2]))
            }).compactMap { $0 }
    }

    /// `"[COPYUID 2 343 0] (Success)"` -> `"2 343 0"`: the code's argument
    /// when the text opens with a COPYUID, as a response code does, nil
    /// otherwise.
    private static func copyUIDArgument(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let opening = "[COPYUID "
        guard trimmed.count > opening.count,
              trimmed.prefix(opening.count).uppercased() == opening,
              let close = trimmed.firstIndex(of: "]") else { return nil }
        let inner = trimmed[trimmed.index(trimmed.startIndex, offsetBy: opening.count)..<close]
        return String(inner)
    }

    /// `"2 343 0"`, of the letter `uid`.
    private static func classify(_ argument: String, uid: UInt32) -> CopyUID {
        let parts = argument.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, number(parts[0]) != nil,
              let source = ranges(parts[1]), let destination = ranges(parts[2]) else { return .other }
        guard source.contains(where: { $0.contains(uid) }) else { return .other }
        if destination.contains(where: { $0.lowerBound == 0 }) { return .zero }
        guard count(source) == count(destination) else { return .other }
        return .names
    }

    /// A UID set as its ranges, `3:5,9` -> `[3...5, 9...9]`, either way round
    /// a range goes; nil for anything else, `*` included, which a COPYUID
    /// has no business giving. 0 is read, so that it can be seen.
    private static func ranges(_ text: Substring) -> [ClosedRange<UInt32>]? {
        var out: [ClosedRange<UInt32>] = []
        for part in text.split(separator: ",", omittingEmptySubsequences: false) {
            let ends = part.split(separator: ":", omittingEmptySubsequences: false)
            guard ends.count == 1 || ends.count == 2 else { return nil }
            var numbers: [UInt32] = []
            for end in ends {
                guard let n = number(end) else { return nil }
                numbers.append(n)
            }
            guard let low = numbers.min(), let high = numbers.max() else { return nil }
            out.append(low...high)
        }
        return out
    }

    /// Digits, and no more of them than a UID has.
    private static func number(_ text: Substring) -> UInt32? {
        guard !text.isEmpty, text.utf8.count <= 10,
              text.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        return UInt32(text)
    }

    private static func count(_ ranges: [ClosedRange<UInt32>]) -> UInt64 {
        ranges.reduce(0) { $0 + UInt64($1.upperBound - $1.lowerBound) + 1 }
    }
}

/// Where a MOVE or COPY put a letter, as its answer's COPYUID says
/// (`IMAPMoveAnswer.landing`): the destination's UIDVALIDITY and the
/// letter's UID there.
struct IMAPMoveLanding: Equatable, Sendable {
    let validity: UInt32
    let uid: UInt32
}
