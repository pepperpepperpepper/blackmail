import Foundation

/// When this app stops opening (D-004, B-137), read from its own
/// `embedded.mobileprovision` at launch and never written into the code:
/// the profile and the certificate are the owner's to choose, and the build
/// that goes on his iPad is never touched again.
///
/// A sideloaded app stops launching the instant its embedded profile, or the
/// certificate it was signed with, runs out. The profile is a CMS envelope
/// (DER) around an XML plist: its `ExpirationDate`, and the `notAfter` of
/// the certificates in its `DeveloperCertificates`, which Apple caps at the
/// membership's end and which today is the same instant as the profile's.
///
/// Nothing at all where there is no profile: the simulator, a build run
/// from the host, and an install by TrollStore, which never runs out. This
/// project's TrollStore installs carry the profile all the same (they are
/// the signed IPA, `tools/sign-ipa.sh`), so TrollStore is told by the
/// entitlement its helper adds to the app's own signature
/// (`OwnEntitlements`). Not by the file it leaves beside the app in the
/// bundle container: the app's sandbox denies even a look at it, which
/// reads as no file (the test iPad, 2026-10-25).
enum AppExpiry {

    /// What was found.
    enum Found: Equatable {
        /// The profile, and the instant the app stops opening.
        case stops(Date)
        /// No profile in the bundle.
        case noProfile
        /// Installed by TrollStore, its signature holding the entitlement
        /// TrollStore adds: it never stops opening.
        case trollStore
        /// A profile, but no date could be read from it.
        case unreadable
    }

    /// Where the signing puts the profile, in the app's bundle.
    static let profileName = "embedded.mobileprovision"

    /// This app's, read once a launch, the first time it is asked for, and
    /// said in the connection log for whoever helps: its own executable's
    /// entitlements, then its profile.
    static let app: Found = {
        let entitlement = OwnEntitlements.containerRequired(executable: Bundle.main.executableURL)
        if entitlement == .unread { Diagnostics.log(.note, "EXPIRY entitlements unread") }
        let found = read(bundle: Bundle.main.bundleURL, containerRequired: entitlement, now: Date())
        Diagnostics.log(.note, "EXPIRY \(found.logged)")
        return found
    }()

    /// What the bundle at `bundle` says, as of `now`, its executable's
    /// signature holding TrollStore's entitlement or not. Only `.held` is
    /// TrollStore: a signature that could not be read is taken as a
    /// certificate's, and the profile read, so the warning stays.
    static func read(bundle: URL, containerRequired: OwnEntitlements.Holding, now: Date,
                     files: FileManager = .default) -> Found {
        if containerRequired == .held { return .trollStore }
        let profile = bundle.appendingPathComponent(profileName)
        guard files.fileExists(atPath: profile.path) else { return .noProfile }
        guard let data = try? Data(contentsOf: profile),
              let stops = stops(profile: data, now: now) else { return .unreadable }
        return .stops(stops)
    }

    /// The instant the app signed with `profile` stops opening: its
    /// `ExpirationDate`, or a certificate's `notAfter` if that is earlier.
    /// A certificate already out of date at `now` is left out: the app is
    /// open, so it was not signed with that one. Nil when the profile has
    /// no `ExpirationDate`; a certificate that cannot be read is passed
    /// over.
    static func stops(profile: Data, now: Date) -> Date? {
        guard let plist = plist(in: profile),
              let expires = plist["ExpirationDate"] as? Date else { return nil }
        let certificates = (plist["DeveloperCertificates"] as? [Any] ?? [])
            .compactMap { $0 as? Data }
            .compactMap(notAfter(certificate:))
            .filter { $0 > now }
        return ([expires] + certificates).min()
    }

    /// The plist inside the profile's envelope. The envelope is DER, so the
    /// plist is in it whole, as the bytes from `<?xml` to `</plist>`; the
    /// signature is not checked, which iOS has done before the app runs.
    static func plist(in profile: Data) -> [String: Any]? {
        guard let start = profile.range(of: Data("<?xml".utf8)),
              let end = profile.range(of: Data("</plist>".utf8),
                                      in: start.upperBound..<profile.endIndex)
        else { return nil }
        let xml = profile.subdata(in: start.lowerBound..<end.upperBound)
        return (try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil))
            as? [String: Any]
    }

    /// The `notAfter` of an X.509 certificate in DER: the second time in
    /// the validity, the fifth field of the certificate's signed part, or
    /// the fourth where it has no version. Nil for anything else.
    static func notAfter(certificate: Data) -> Date? {
        let bytes = [UInt8](certificate)
        guard let whole = DERElement.read(bytes, at: 0, before: bytes.count), whole.tag == 0x30,
              let signed = DERElement.children(of: whole, in: bytes)?.first, signed.tag == 0x30,
              var fields = DERElement.children(of: signed, in: bytes) else { return nil }
        if fields.first?.tag == 0xA0 { fields.removeFirst() }
        // serialNumber, signature, issuer, validity.
        guard fields.count > 3, fields[0].tag == 0x02, fields[1].tag == 0x30,
              fields[2].tag == 0x30, fields[3].tag == 0x30,
              let times = DERElement.children(of: fields[3], in: bytes), times.count == 2
        else { return nil }
        return time(times[1], in: bytes)
    }

    /// An X.509 time: UTCTime, YYMMDDHHMMSSZ, its years from 1950 to 2049
    /// (RFC 5280, 4.1.2.5.1), or GeneralizedTime, YYYYMMDDHHMMSSZ. Always
    /// in UTC with whole seconds, as RFC 5280 has them.
    private static func time(_ element: DERElement, in bytes: [UInt8]) -> Date? {
        let text = Array(bytes[element.contents])
        let yearDigits: Int
        switch (element.tag, text.count) {
        case (0x17, 13): yearDigits = 2
        case (0x18, 15): yearDigits = 4
        default: return nil
        }
        guard text.last == UInt8(ascii: "Z") else { return nil }
        let digits = text.dropLast()
        guard digits.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }) else {
            return nil
        }
        let numbers = digits.map { Int($0 - UInt8(ascii: "0")) }
        func number(_ from: Int, _ count: Int) -> Int {
            numbers[from..<(from + count)].reduce(0) { $0 * 10 + $1 }
        }
        var year = number(0, yearDigits)
        if yearDigits == 2 { year += year < 50 ? 2000 : 1900 }
        var parts = DateComponents()
        parts.year = year
        parts.month = number(yearDigits, 2)
        parts.day = number(yearDigits + 2, 2)
        parts.hour = number(yearDigits + 4, 2)
        parts.minute = number(yearDigits + 6, 2)
        parts.second = number(yearDigits + 8, 2)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        // A calendar rolls a 31 February over into March: the date is
        // taken only if it reads back as written.
        guard let date = utc.date(from: parts) else { return nil }
        let back = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard back.year == parts.year, back.month == parts.month, back.day == parts.day,
              back.hour == parts.hour, back.minute == parts.minute, back.second == parts.second
        else { return nil }
        return date
    }
}

extension AppExpiry.Found {
    /// For the connection log: what was found, and the instant as UTC.
    var logged: String {
        switch self {
        case .stops(let date): return "stops \(date)"
        case .noProfile: return "none, no profile"
        case .trollStore: return "none, TrollStore"
        case .unreadable: return "none, profile unreadable"
        }
    }
}

/// One element of DER: its tag, and where its contents lie in the bytes.
/// Definite lengths alone, as DER has them, and every one inside the
/// element holding it.
struct DERElement {
    let tag: UInt8
    let contents: Range<Int>

    /// The element at `start`, ending at or before `limit`; nil if there is
    /// none whole there.
    static func read(_ bytes: [UInt8], at start: Int, before limit: Int) -> DERElement? {
        guard start >= 0, limit <= bytes.count, start + 2 <= limit else { return nil }
        let tag = bytes[start]
        // A tag of more than one byte is in no field read here.
        guard tag & 0x1F != 0x1F else { return nil }
        var at = start + 1
        let first = bytes[at]
        at += 1
        var length = 0
        if first & 0x80 == 0 {
            length = Int(first)
        } else {
            // 0x80 alone is BER's indefinite length, which DER never has.
            let count = Int(first & 0x7F)
            guard count >= 1, count <= 4, at + count <= limit else { return nil }
            for _ in 0..<count {
                length = length << 8 | Int(bytes[at])
                at += 1
            }
        }
        guard length <= limit - at else { return nil }
        return DERElement(tag: tag, contents: at..<(at + length))
    }

    /// The elements inside `parent`, in order; nil if they do not fill it.
    static func children(of parent: DERElement, in bytes: [UInt8]) -> [DERElement]? {
        var found: [DERElement] = []
        var at = parent.contents.lowerBound
        while at < parent.contents.upperBound {
            guard let child = read(bytes, at: at, before: parent.contents.upperBound) else {
                return nil
            }
            found.append(child)
            at = child.contents.upperBound
        }
        return found
    }
}
