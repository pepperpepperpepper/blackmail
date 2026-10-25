import XCTest
@testable import Blackmail

/// How the app tells TrollStore's install from a certificate's (B-137):
/// the entitlement TrollStore's helper adds, read from the code signature
/// in the app's own executable.
///
/// The executables here are made up, built in the test: a 64-bit Mach-O's
/// header and load commands, filler for its code, and a code signature's
/// SuperBlob with a made-up CodeDirectory, requirements and CMS, and the
/// entitlements as XML and as DER. The team, app and bundle id are made
/// up ("EXAMPLE000", "org.example.mail"); no real signature is in them.
final class OwnEntitlementsTests: XCTestCase {

    private let entitlement = "com.apple.private.security.container-required"

    // MARK: - Made-up bytes

    private func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    private func le32(_ v: UInt32) -> [UInt8] { be32(v).reversed() }

    private func be64(_ v: UInt64) -> [UInt8] { be32(UInt32(v >> 32)) + be32(UInt32(v & 0xFFFF_FFFF)) }

    private func blob(_ magic: UInt32, _ body: [UInt8]) -> [UInt8] {
        be32(magic) + be32(UInt32(8 + body.count)) + body
    }

    private func tlv(_ tag: UInt8, _ body: [UInt8]) -> [UInt8] {
        let n = body.count
        let length: [UInt8]
        switch n {
        case ..<0x80: length = [UInt8(n)]
        case ..<0x100: length = [0x81, UInt8(n)]
        default: length = [0x82, UInt8(n >> 8), UInt8(n & 0xFF)]
        }
        return [tag] + length + body
    }

    private func utf8(_ text: String) -> [UInt8] { tlv(0x0C, Array(text.utf8)) }
    private func boolean(_ flag: Bool) -> [UInt8] { tlv(0x01, [flag ? 0xFF : 0x00]) }

    /// What a certificate's signing gives the app, made up.
    private var signed: [(String, Any)] {
        [("application-identifier", "EXAMPLE000.org.example.mail"),
         ("com.apple.developer.team-identifier", "EXAMPLE000"),
         ("get-task-allow", false),
         ("keychain-access-groups", ["EXAMPLE000.org.example.mail"])]
    }

    /// The same with TrollStore's entitlement, the bundle id.
    private var trollStore: [(String, Any)] { signed + [(entitlement, "org.example.mail")] }

    private func xml(_ entitlements: [(String, Any)]) throws -> [UInt8] {
        let plist = Dictionary(entitlements, uniquingKeysWith: { $1 })
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml,
                                                      options: 0)
        return blob(0xFADE_7171, [UInt8](data))
    }

    private func derValue(_ value: Any) -> [UInt8] {
        switch value {
        case let text as String: return utf8(text)
        case let flag as Bool: return boolean(flag)
        case let list as [String]: return tlv(0x30, list.flatMap(utf8))
        case let raw as [UInt8]: return raw
        default: fatalError("no DER for \(value)")
        }
    }

    /// DER entitlements as Apple writes them: [APPLICATION 16] { INTEGER 1,
    /// [CONTEXT 16] { SEQUENCE { key, value } ... } }.
    private func derBody(_ entitlements: [(String, Any)]) -> [UInt8] {
        let pairs = entitlements.sorted { $0.0 < $1.0 }
            .flatMap { tlv(0x30, utf8($0.0) + derValue($0.1)) }
        return tlv(0x70, tlv(0x02, [0x01]) + tlv(0xB0, pairs))
    }

    private func der(_ entitlements: [(String, Any)]) -> [UInt8] {
        blob(0xFADE_7172, derBody(entitlements))
    }

    /// A CodeDirectory's shape, its hashes filler, naming the made-up app.
    private var codeDirectory: [UInt8] {
        blob(0xFADE_0C02, be32(0x20400) + [UInt8](repeating: 0, count: 36)
             + Array("org.example.mail\0EXAMPLE000\0".utf8)
             + [UInt8](repeating: 0x5A, count: 32 * 12))
    }

    private var requirements: [UInt8] { blob(0xFADE_0C01, be32(0)) }
    private var cms: [UInt8] { blob(0xFADE_0B01, [UInt8](repeating: 0x3C, count: 200)) }

    private func superBlob(_ slots: [(UInt32, [UInt8])]) -> [UInt8] {
        let header = 12 + 8 * slots.count
        var index: [UInt8] = []
        var body: [UInt8] = []
        for (slot, bytes) in slots {
            index += be32(slot) + be32(UInt32(header + body.count))
            body += bytes
        }
        return be32(0xFADE_0CC0) + be32(UInt32(header + body.count)) + be32(UInt32(slots.count))
            + index + body
    }

    /// A signature as the signers lay it out: CodeDirectory, requirements,
    /// the XML and DER entitlements, the CMS.
    private func signature(_ entitlements: [(String, Any)]) throws -> [UInt8] {
        superBlob([(0, codeDirectory), (2, requirements), (5, try xml(entitlements)),
                   (7, der(entitlements)), (0x10000, cms)])
    }

    /// The app's code, filler with the entitlement's name in it, as the
    /// app's own strings would have it: never to be taken for a signature's.
    private var code: [UInt8] {
        [UInt8](repeating: 0x1F, count: 300) + Array("\0\(entitlement)\0".utf8)
            + [UInt8](repeating: 0x20, count: 301)
    }

    /// A made-up arm64 executable: its header, a segment's and an entry
    /// point's load commands, LC_CODE_SIGNATURE when `signature` is given
    /// (or each of `signatureCommands`), the code, then the signature
    /// sixteen-aligned at the end of the file.
    private func machO(_ signature: [UInt8]?, signatureCommands: Int = 1,
                       cpu: UInt32 = 0x0100_000C) -> [UInt8] {
        let segment = le32(0x19) + le32(72) + [UInt8](repeating: 0, count: 64)
        let main = le32(0x8000_0028) + le32(24) + [UInt8](repeating: 0, count: 16)
        let signing = signature == nil ? 0 : signatureCommands
        let commandBytes = segment.count + main.count + 16 * signing
        var at = 32 + commandBytes + code.count
        let padding = (16 - at % 16) % 16
        at += padding
        var commands = segment + main
        for _ in 0..<signing {
            commands += le32(0x1D) + le32(16) + le32(UInt32(at))
                + le32(UInt32(signature?.count ?? 0))
        }
        let header = le32(0xFEED_FACF) + le32(cpu) + le32(0) + le32(2)
            + le32(UInt32(2 + signing)) + le32(UInt32(commandBytes)) + le32(0) + le32(0)
        return header + commands + code + [UInt8](repeating: 0, count: padding) + (signature ?? [])
    }

    private func held(_ bytes: [UInt8]) -> OwnEntitlements.Holding {
        OwnEntitlements.holding(OwnEntitlements.containerRequired, in: Data(bytes))
    }

    // MARK: - What the signature says

    /// TrollStore's install holds the entitlement and a certificate's does
    /// not, with its name in the app's own code either way: the signature
    /// is read, never the bytes searched.
    func testTrollStoresSignatureHoldsItAndACertificatesDoesNot() throws {
        XCTAssertEqual(OwnEntitlements.containerRequired, entitlement)
        let certificate = machO(try signature(signed))
        XCTAssertNotNil(Data(certificate).range(of: Data(entitlement.utf8)), "the name in the code")
        XCTAssertEqual(held(certificate), .notHeld)
        XCTAssertEqual(held(machO(try signature(trollStore))), .held)

        // The rest of what a signature holds is read as such.
        let entitlements = try XCTUnwrap(OwnEntitlements.entitlements(
            inMachO: OwnEntitlements.Bytes(Data(machO(try signature(trollStore))))))
        XCTAssertEqual(entitlements["application-identifier"] as? String,
                       "EXAMPLE000.org.example.mail")
        XCTAssertEqual(entitlements["get-task-allow"] as? Bool, false)
        XCTAssertEqual(entitlements[entitlement] as? String, "org.example.mail")

        // The name elsewhere in the signature than its entitlements' keys:
        // in the CodeDirectory, in the CMS, as a value, as a key nested
        // inside another's.
        let named = Array(entitlement.utf8)
        let inDirectory = blob(0xFADE_0C02, Array(codeDirectory.dropFirst(8)) + named)
        let inCMS = blob(0xFADE_0B01, [UInt8](repeating: 0x3C, count: 20) + named)
        XCTAssertEqual(held(machO(superBlob([(0, inDirectory), (2, requirements),
                                             (5, try xml(signed)), (7, der(signed)),
                                             (0x10000, inCMS)]))), .notHeld)
        let asValue = signed + [("keychain-access-groups-extra", entitlement)]
        XCTAssertEqual(held(machO(try signature(asValue))), .notHeld)
        let nested = signed + [("com.example.nested",
                                tlv(0xB0, tlv(0x30, utf8(entitlement) + utf8("org.example.mail"))))]
        XCTAssertEqual(held(machO(superBlob([(0, codeDirectory), (7, der(nested))]))), .notHeld)
    }

    /// The DER blob where there is one, as iOS 15 and later go by it; the
    /// XML one where there is not; none at all is not held. The index's
    /// order, and slots other than these, change nothing.
    func testTheDERBlobIsReadWhereThereIsOneAndTheXMLOtherwise() throws {
        let cd = (UInt32(0), codeDirectory)
        XCTAssertEqual(held(machO(superBlob([cd, (5, try xml(trollStore))]))), .held)
        XCTAssertEqual(held(machO(superBlob([cd, (5, try xml(signed))]))), .notHeld)
        XCTAssertEqual(held(machO(superBlob([cd, (7, der(trollStore))]))), .held)
        XCTAssertEqual(held(machO(superBlob([cd, (7, der(signed))]))), .notHeld)
        XCTAssertEqual(held(machO(superBlob([cd, (5, try xml(trollStore)), (7, der(signed))]))),
                       .notHeld, "the DER one is what iOS goes by")
        XCTAssertEqual(held(machO(superBlob([cd, (5, try xml(signed)), (7, der(trollStore))]))),
                       .held)
        // Shuffled, with an alternate CodeDirectory as some signers write
        // one, the DER blob first.
        XCTAssertEqual(held(machO(superBlob([(0x10000, cms), (7, der(trollStore)),
                                             (0x1000, codeDirectory), (5, try xml(trollStore)),
                                             cd]))), .held)
        // Signed with no entitlements at all.
        XCTAssertEqual(held(machO(superBlob([cd, (2, requirements), (0x10000, cms)]))), .notHeld)
        XCTAssertEqual(held(machO(superBlob([]))), .notHeld)
        // A Data that does not begin at index 0 reads the same.
        let bytes = machO(try signature(trollStore))
        let shifted = Data([0xAA, 0xBB, 0xCC] + bytes).dropFirst(3)
        XCTAssertNotEqual(shifted.startIndex, 0)
        XCTAssertEqual(OwnEntitlements.holding(OwnEntitlements.containerRequired, in: shifted),
                       .held)
    }

    /// Held by a non-empty string, as TrollStore's helper writes the bundle
    /// id, or by true; not by false, an empty string, a list or a number.
    func testOnlyAStringOrTrueHoldsIt() throws {
        func both(_ value: Any) throws -> [OwnEntitlements.Holding] {
            let entitlements = signed + [(entitlement, value)]
            return [held(machO(superBlob([(0, codeDirectory), (5, try xml(entitlements))]))),
                    held(machO(superBlob([(0, codeDirectory), (7, der(entitlements))])))]
        }
        XCTAssertEqual(try both("org.example.mail"), [.held, .held])
        XCTAssertEqual(try both(true), [.held, .held])
        XCTAssertEqual(try both(false), [.notHeld, .notHeld])
        XCTAssertEqual(try both(""), [.notHeld, .notHeld])
        XCTAssertEqual(try both(["org.example.mail"]), [.notHeld, .notHeld])
        let one = signed + [(entitlement, tlv(0x02, [0x01]))]
        XCTAssertEqual(held(machO(superBlob([(0, codeDirectory), (7, der(one))]))), .notHeld)
    }

    /// Anything that does not hold together is unread, never held and
    /// never a fault: not a Mach-O, no signature, a file cut short at every
    /// length, a length or an offset past what holds it, a second
    /// signature, the wrong magic, DER of the wrong shape.
    func testAnythingThatDoesNotHoldTogetherIsUnread() throws {
        XCTAssertEqual(held([]), .unread)
        XCTAssertEqual(held(Array("not an executable at all".utf8)), .unread)
        let whole = machO(try signature(trollStore))
        // 32-bit, and big-endian.
        XCTAssertEqual(held(le32(0xFEED_FACE) + whole.dropFirst(4)), .unread)
        XCTAssertEqual(held(be32(0xFEED_FACF) + whole.dropFirst(4)), .unread)
        XCTAssertEqual(held(machO(nil)), .unread, "no LC_CODE_SIGNATURE")
        XCTAssertEqual(held(machO(try signature(trollStore), signatureCommands: 2)), .unread)
        for end in 0..<whole.count {
            XCTAssertEqual(held(Array(whole[0..<end])), .unread, "\(end)")
        }

        func patched(_ bytes: [UInt8], at offset: Int, _ value: [UInt8]) -> [UInt8] {
            var out = bytes
            out.replaceSubrange(offset..<(offset + value.count), with: value)
            return out
        }
        // The load commands: sizeofcmds past the file, a command of size 0,
        // one past the table, the signature's offset past the file.
        XCTAssertEqual(held(patched(whole, at: 20, le32(UInt32(whole.count)))), .unread)
        XCTAssertEqual(held(patched(whole, at: 32 + 4, le32(0))), .unread)
        XCTAssertEqual(held(patched(whole, at: 32 + 4, le32(4096))), .unread)
        let signing = 32 + 72 + 24
        XCTAssertEqual(held(patched(whole, at: signing + 8, le32(UInt32(whole.count)))), .unread)
        XCTAssertEqual(held(patched(whole, at: signing + 12, le32(UInt32(whole.count)))), .unread)

        // The SuperBlob: its magic, its length past the signature, its
        // count past its length, an offset past it, a blob's length past
        // it or under its header, the DER slot with the XML magic, a slot
        // twice.
        let sig = try signature(trollStore)
        let start = whole.count - sig.count
        XCTAssertEqual(held(patched(whole, at: start, be32(0xFADE_0CC1))), .unread)
        XCTAssertEqual(held(patched(whole, at: start + 4, be32(UInt32(sig.count + 1)))), .unread)
        XCTAssertEqual(held(patched(whole, at: start + 8, be32(1000))), .unread)
        let derIndex = start + 12 + 8 * 3
        XCTAssertEqual(held(patched(whole, at: derIndex + 4, be32(UInt32(sig.count)))), .unread)
        let derAt = Int(UInt32(whole[derIndex + 4]) << 24 | UInt32(whole[derIndex + 5]) << 16
                        | UInt32(whole[derIndex + 6]) << 8 | UInt32(whole[derIndex + 7]))
        XCTAssertEqual(held(patched(whole, at: start + derAt + 4, be32(UInt32(sig.count)))), .unread)
        XCTAssertEqual(held(patched(whole, at: start + derAt + 4, be32(4))), .unread)
        XCTAssertEqual(held(patched(whole, at: start + derAt, be32(0xFADE_7171))), .unread)
        XCTAssertEqual(held(machO(superBlob([(7, der(trollStore)), (7, der(trollStore))]))),
                       .unread)
        XCTAssertEqual(held(machO(superBlob([(5, blob(0xFADE_7171, Array("not a plist".utf8)))]))),
                       .unread)
        let array = try PropertyListSerialization.data(fromPropertyList: [entitlement], format: .xml,
                                                       options: 0)
        XCTAssertEqual(held(machO(superBlob([(5, blob(0xFADE_7171, [UInt8](array)))]))), .unread)

        // DER of the wrong shape: a SEQUENCE for the top, no version, a
        // pair not a SEQUENCE, a key not a string, three in a pair, a
        // BOOLEAN of two bytes, a key not UTF-8, cut inside.
        let pair = tlv(0x30, utf8(entitlement) + utf8("org.example.mail"))
        func derBlob(_ body: [UInt8]) -> [UInt8] {
            machO(superBlob([(0, codeDirectory), (7, blob(0xFADE_7172, body))]))
        }
        XCTAssertEqual(held(derBlob(derBody(trollStore))), .held)
        XCTAssertEqual(held(derBlob(tlv(0x30, tlv(0x02, [0x01]) + tlv(0xB0, pair)))), .unread)
        XCTAssertEqual(held(derBlob(tlv(0x70, tlv(0xB0, pair)))), .unread)
        XCTAssertEqual(held(derBlob(tlv(0x70, tlv(0x02, [0x01]) + tlv(0xB0, tlv(0x31, utf8(entitlement) + utf8("x")))))),
                       .unread)
        XCTAssertEqual(held(derBlob(tlv(0x70, tlv(0x02, [0x01]) + tlv(0xB0, tlv(0x30, tlv(0x04, Array(entitlement.utf8)) + utf8("x")))))),
                       .unread)
        XCTAssertEqual(held(derBlob(tlv(0x70, tlv(0x02, [0x01]) + tlv(0xB0, tlv(0x30, utf8(entitlement) + utf8("x") + utf8("y")))))),
                       .unread)
        XCTAssertEqual(held(derBlob(tlv(0x70, tlv(0x02, [0x01]) + tlv(0xB0, tlv(0x30, utf8(entitlement) + tlv(0x01, [0xFF, 0xFF])))))),
                       .unread)
        XCTAssertEqual(held(derBlob(tlv(0x70, tlv(0x02, [0x01]) + tlv(0xB0, tlv(0x30, tlv(0x0C, [0xFF, 0xFE]) + utf8("x")))))),
                       .unread)
        let body = derBody(trollStore)
        for end in 0..<body.count {
            XCTAssertNotEqual(held(derBlob(Array(body[0..<end]))), .held, "\(end)")
        }

        // Any one byte of a certificate's executable changed: never held.
        let certificate = machO(try signature(signed))
        for at in 0..<certificate.count {
            var changed = certificate
            changed[at] ^= 0xFF
            XCTAssertNotEqual(held(changed), .held, "\(at)")
        }
    }

    /// A fat file holds it only if every slice does; a slice outside the
    /// file, none, too many, or one that is not a Mach-O is unread.
    func testAFatFileHoldsItOnlyIfEverySliceDoes() throws {
        let troll = machO(try signature(trollStore))
        let cert = machO(try signature(signed))
        func fat(_ slices: [[UInt8]], wide: Bool = false, count: Int? = nil,
                 offsetBy: Int = 0) -> [UInt8] {
            let entry = wide ? 32 : 20
            var at = 8 + entry * slices.count
            at += (4096 - at % 4096) % 4096
            var header = be32(wide ? 0xCAFE_BABF : 0xCAFE_BABE) + be32(UInt32(count ?? slices.count))
            var body: [UInt8] = []
            for slice in slices {
                let offset = at + body.count + offsetBy
                header += be32(0x0100_000C) + be32(0)
                header += wide ? be64(UInt64(offset)) + be64(UInt64(slice.count)) + be32(14) + be32(0)
                               : be32(UInt32(offset)) + be32(UInt32(slice.count)) + be32(14)
                body += slice + [UInt8](repeating: 0, count: (16 - slice.count % 16) % 16)
            }
            return header + [UInt8](repeating: 0, count: at - header.count) + body
        }
        XCTAssertEqual(held(fat([troll])), .held)
        XCTAssertEqual(held(fat([troll, troll])), .held)
        XCTAssertEqual(held(fat([troll, troll], wide: true)), .held)
        XCTAssertEqual(held(fat([troll, cert])), .notHeld)
        XCTAssertEqual(held(fat([cert, troll], wide: true)), .notHeld)
        XCTAssertEqual(held(fat([cert])), .notHeld)
        XCTAssertEqual(held(fat([troll, Array("not a Mach-O".utf8)])), .unread)
        XCTAssertEqual(held(fat([troll, fat([troll])])), .unread, "a fat file inside")
        XCTAssertEqual(held(fat([troll], offsetBy: 4096)), .unread)
        XCTAssertEqual(held(fat([troll], wide: true, offsetBy: 4096)), .unread)
        XCTAssertEqual(held(fat([], count: 0)), .unread)
        XCTAssertEqual(held(fat([troll], count: 33)), .unread)
        XCTAssertEqual(held(fat([troll], count: 2)), .unread)
    }

    /// The executable is read from its file: a file it cannot read, or no
    /// file, is unread.
    func testTheExecutableIsReadFromItsFile() throws {
        let files = FileManager.default
        let folder = files.temporaryDirectory
            .appendingPathComponent("OwnEntitlementsTests-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: folder) }
        let troll = folder.appendingPathComponent("TrollStore")
        let cert = folder.appendingPathComponent("Certificate")
        try Data(machO(try signature(trollStore))).write(to: troll)
        try Data(machO(try signature(signed))).write(to: cert)
        XCTAssertEqual(OwnEntitlements.containerRequired(executable: troll), .held)
        XCTAssertEqual(OwnEntitlements.containerRequired(executable: cert), .notHeld)
        XCTAssertEqual(OwnEntitlements.containerRequired(executable: nil), .unread)
        XCTAssertEqual(OwnEntitlements.containerRequired(
            executable: folder.appendingPathComponent("missing")), .unread)
        XCTAssertEqual(OwnEntitlements.containerRequired(executable: folder), .unread)
    }

    // MARK: - Where it is read

    private var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources")
    }

    /// The file's code without its comments, on one line.
    private func sourceCode(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    /// Read once a launch from the app's own executable, before its
    /// profile, "unread" said in the connection log; TrollStore only when
    /// held. The file beside the bundle is no longer looked for, and the
    /// whole name is in no line of the app's code.
    func testItIsReadFromTheAppsOwnExecutableAtLaunch() throws {
        let expiry = try sourceCode(sources.appendingPathComponent("Blackmail/Mail/AppExpiry.swift"))
        XCTAssertTrue(expiry.contains(
            "static let app: Found = { "
            + "let entitlement = OwnEntitlements.containerRequired(executable: Bundle.main.executableURL) "
            + "if entitlement == .unread { Diagnostics.log(.note, \"EXPIRY entitlements unread\") } "
            + "let found = read(bundle: Bundle.main.bundleURL, containerRequired: entitlement, now: Date()) "
            + "Diagnostics.log(.note, \"EXPIRY \\(found.logged)\") return found }()"), expiry)
        XCTAssertTrue(expiry.contains(
            "now: Date, files: FileManager = .default) -> Found { "
            + "if containerRequired == .held { return .trollStore } "
            + "let profile = bundle.appendingPathComponent(profileName)"), expiry)
        XCTAssertEqual(expiry.components(separatedBy: "return .trollStore").count - 1, 1, expiry)
        XCTAssertFalse(expiry.contains("_TrollStore"))
        XCTAssertFalse(expiry.contains("deletingLastPathComponent"))

        let own = try sourceCode(sources.appendingPathComponent("Blackmail/Mail/OwnEntitlements.swift"))
        XCTAssertTrue(own.contains("guard let url, let file = try? Data(contentsOf: url, "
                                   + "options: .mappedIfSafe) else { return .unread } "
                                   + "return holding(containerRequired, in: file)"), own)

        let walk = try XCTUnwrap(FileManager.default.enumerator(at: sources,
                                                                includingPropertiesForKeys: nil))
        var read = 0
        var askers: Set<String> = []
        for case let url as URL in walk where url.pathExtension == "swift" {
            let text = try sourceCode(url)
            read += 1
            XCTAssertFalse(text.contains(entitlement), url.lastPathComponent)
            XCTAssertFalse(text.contains("_TrollStore"), url.lastPathComponent)
            if text.contains("OwnEntitlements.") { askers.insert(url.lastPathComponent) }
        }
        XCTAssertGreaterThan(read, 100)
        XCTAssertEqual(askers, ["AppExpiry.swift"])
    }
}
