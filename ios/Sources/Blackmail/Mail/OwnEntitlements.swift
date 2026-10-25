import Foundation

/// The app's own entitlements, read from the code signature in its own
/// executable (B-137): how the app tells an install by TrollStore, which
/// never expires, from one by a certificate, which does.
///
/// TrollStore's helper signs every app it installs again, and adds
/// `com.apple.private.security.container-required`, set to the bundle id,
/// so that the app gets its data container. The IPA as built has no such
/// entitlement, and no install by a certificate can: a private entitlement
/// the profile does not grant is refused by iOS. So "my own signature
/// holds it" means TrollStore, or an installer like it, and no expiry.
///
/// Read from the executable rather than asked of the system
/// (`SecTaskCopyValueForEntitlement`, which the iOS SDK does not declare):
/// the bytes are the ones iOS checked at launch, the app's sandbox lets it
/// read its own bundle (measured 2026-10-25, where the file TrollStore
/// leaves beside the bundle could not even be seen), no symbol outside the
/// SDK is needed, and every step can be tried on the host. Anything that
/// cannot be read is `.unread`, which the caller takes as a certificate's
/// install: the warning stays.
///
/// The executable is a 64-bit Mach-O, or a fat file of them. Its
/// `LC_CODE_SIGNATURE` points at a SuperBlob (big-endian) indexing blobs
/// by slot: the entitlements as a DER blob (slot 7, iOS 15 and later go
/// by it) and as an XML plist (slot 5). The DER one is read where there is
/// one, the XML one otherwise. Every offset and length is checked against
/// what holds it; nothing is searched for in the bytes.
enum OwnEntitlements {

    /// What the signature says of one entitlement.
    enum Holding: Equatable {
        /// Held: a non-empty string, or true.
        case held
        /// Read, and not held: absent, false, empty, or anything else.
        case notHeld
        /// The executable or its signature could not be read.
        case unread
    }

    /// `com.apple.private.security.container-required`, put together at
    /// run time. Written whole, the name would sit in the app's own
    /// binary, where a search of its bytes would find the app's code and
    /// not its signature.
    static let containerRequired = ["com", "apple", "private", "security", "container-required"]
        .joined(separator: ".")

    /// Whether the executable at `url` holds `containerRequired`.
    static func containerRequired(executable url: URL?) -> Holding {
        guard let url, let file = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return .unread
        }
        return holding(containerRequired, in: file)
    }

    /// Whether the Mach-O in `file` holds `key`. A fat file holds it only
    /// if every slice does; TrollStore's helper writes one slice.
    static func holding(_ key: String, in file: Data) -> Holding {
        let whole = Bytes(file)
        guard let magic = whole.u32(0, big: true) else { return .unread }
        let slices: [Bytes]
        if magic == fatMagic || magic == fatMagic64 {
            guard let found = fatSlices(whole, wide: magic == fatMagic64) else { return .unread }
            slices = found
        } else {
            slices = [whole]
        }
        var all = Holding.held
        for slice in slices {
            guard let entitlements = entitlements(inMachO: slice) else { return .unread }
            if !holds(entitlements[key]) { all = .notHeld }
        }
        return all
    }

    // MARK: - The Mach-O

    static let fatMagic: UInt32 = 0xCAFE_BABE
    static let fatMagic64: UInt32 = 0xCAFE_BABF
    static let machOMagic64: UInt32 = 0xFEED_FACF
    static let codeSignatureCommand: UInt32 = 0x1D
    static let superBlobMagic: UInt32 = 0xFADE_0CC0
    static let xmlSlot: UInt32 = 5
    static let xmlMagic: UInt32 = 0xFADE_7171
    static let derSlot: UInt32 = 7
    static let derMagic: UInt32 = 0xFADE_7172

    /// A fat file's slices, each whole inside the file; nil if any is not.
    private static func fatSlices(_ file: Bytes, wide: Bool) -> [Bytes]? {
        guard let count = file.u32(4, big: true), count >= 1, count <= 32 else { return nil }
        let entry = wide ? 32 : 20
        var slices: [Bytes] = []
        for index in 0..<Int(count) {
            let at = 8 + index * entry
            let offset: Int?
            let size: Int?
            if wide {
                offset = file.u64(at + 8).flatMap { Int(exactly: $0) }
                size = file.u64(at + 16).flatMap { Int(exactly: $0) }
            } else {
                offset = file.u32(at + 8, big: true).map { Int($0) }
                size = file.u32(at + 12, big: true).map { Int($0) }
            }
            guard let offset, let size, let slice = file.part(offset, size) else { return nil }
            slices.append(slice)
        }
        return slices
    }

    /// The entitlements of one 64-bit Mach-O: empty when it is signed with
    /// none; nil when it is not a Mach-O, has no signature, or anything in
    /// the way does not hold together.
    static func entitlements(inMachO macho: Bytes) -> [String: Any]? {
        guard macho.u32(0, big: false) == machOMagic64,
              let commands = macho.u32(16, big: false),
              let size = macho.u32(20, big: false),
              let table = macho.part(32, Int(size)) else { return nil }
        var at = 0
        var signature: (offset: Int, size: Int)?
        for _ in 0..<Int(commands) {
            guard let command = table.u32(at, big: false),
                  let length = table.u32(at + 4, big: false).map({ Int($0) }),
                  length >= 8, table.part(at, length) != nil else { return nil }
            if command == codeSignatureCommand {
                guard signature == nil, length >= 16,
                      let offset = table.u32(at + 8, big: false),
                      let bytes = table.u32(at + 12, big: false) else { return nil }
                signature = (Int(offset), Int(bytes))
            }
            at += length
        }
        guard let signature, let blob = macho.part(signature.offset, signature.size) else {
            return nil
        }
        return entitlements(inSuperBlob: blob)
    }

    /// The entitlements in a code signature's SuperBlob: the DER blob's if
    /// there is one, else the XML one's, else none.
    static func entitlements(inSuperBlob blob: Bytes) -> [String: Any]? {
        guard blob.u32(0, big: true) == superBlobMagic,
              let length = blob.u32(4, big: true).map({ Int($0) }),
              let whole = blob.part(0, length),
              let count = whole.u32(8, big: true).map({ Int($0) }),
              count <= (length - 12) / 8 else { return nil }
        var slots: [UInt32: Bytes] = [:]
        for index in 0..<count {
            guard let slot = whole.u32(12 + index * 8, big: true),
                  let offset = whole.u32(16 + index * 8, big: true).map({ Int($0) }),
                  slots[slot] == nil else { return nil }
            guard slot == xmlSlot || slot == derSlot else { continue }
            guard let size = whole.u32(offset + 4, big: true).map({ Int($0) }), size >= 8,
                  let inner = whole.part(offset, size) else { return nil }
            slots[slot] = inner
        }
        if let der = slots[derSlot] {
            guard der.u32(0, big: true) == derMagic else { return nil }
            return derEntitlements(der.bytes(from: 8))
        }
        if let xml = slots[xmlSlot] {
            guard xml.u32(0, big: true) == xmlMagic else { return nil }
            return (try? PropertyListSerialization.propertyList(from: Data(xml.bytes(from: 8)),
                                                                options: [], format: nil))
                as? [String: Any]
        }
        return [:]
    }

    /// DER entitlements, as Apple writes them: [APPLICATION 16] holding the
    /// version, an INTEGER, then [CONTEXT 16], the dictionary, a SEQUENCE
    /// of key, a UTF8String, and value for each. A string value is read as
    /// a `String`, a BOOLEAN as a `Bool`; any other as `Other`, its tag.
    static func derEntitlements(_ bytes: [UInt8]) -> [String: Any]? {
        guard let top = DERElement.read(bytes, at: 0, before: bytes.count), top.tag == 0x70,
              let parts = DERElement.children(of: top, in: bytes), parts.count == 2,
              parts[0].tag == 0x02, parts[1].tag == 0xB0,
              let pairs = DERElement.children(of: parts[1], in: bytes) else { return nil }
        var found: [String: Any] = [:]
        for pair in pairs {
            guard pair.tag == 0x30, let both = DERElement.children(of: pair, in: bytes),
                  both.count == 2, both[0].tag == 0x0C,
                  let key = String(bytes: bytes[both[0].contents], encoding: .utf8)
            else { return nil }
            let value = both[1]
            switch value.tag {
            case 0x0C:
                guard let text = String(bytes: bytes[value.contents], encoding: .utf8) else {
                    return nil
                }
                found[key] = text
            case 0x01:
                guard value.contents.count == 1 else { return nil }
                found[key] = bytes[value.contents.lowerBound] != 0
            default:
                found[key] = Other(tag: value.tag)
            }
        }
        return found
    }

    /// A DER value neither a string nor a BOOLEAN: never read as either.
    struct Other: Equatable {
        let tag: UInt8
    }

    /// A value that holds an entitlement: a non-empty string, as
    /// TrollStore's helper writes the bundle id, or true.
    static func holds(_ value: Any?) -> Bool {
        if let text = value as? String { return !text.isEmpty }
        if let flag = value as? Bool { return flag }
        return false
    }

    // MARK: - Reading bytes

    /// A stretch of a file's bytes, read without copying them.
    struct Bytes {
        let data: Data
        /// Where it begins in `data`, as an index of `data`.
        let start: Int
        let count: Int

        init(_ data: Data) {
            self.init(data: data, start: data.startIndex, count: data.count)
        }

        private init(data: Data, start: Int, count: Int) {
            self.data = data
            self.start = start
            self.count = count
        }

        /// The `size` bytes at `offset`, nil unless all of them are here.
        func part(_ offset: Int, _ size: Int) -> Bytes? {
            guard offset >= 0, size >= 0, offset <= count, size <= count - offset else { return nil }
            return Bytes(data: data, start: start + offset, count: size)
        }

        func u32(_ offset: Int, big: Bool) -> UInt32? {
            guard offset >= 0, offset <= count - 4 else { return nil }
            let b = (0..<4).map { UInt32(data[start + offset + $0]) }
            return big ? b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]
                       : b[3] << 24 | b[2] << 16 | b[1] << 8 | b[0]
        }

        func u64(_ offset: Int) -> UInt64? {
            guard let high = u32(offset, big: true), let low = u32(offset + 4, big: true) else {
                return nil
            }
            return UInt64(high) << 32 | UInt64(low)
        }

        /// A copy of its bytes from `offset` to its end.
        func bytes(from offset: Int) -> [UInt8] {
            guard offset < count else { return [] }
            return [UInt8](data[(start + offset)..<(start + count)])
        }
    }
}
