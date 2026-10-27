import XCTest
@testable import Blackmail

/// The warning before the app stops opening (B-137, D-004 item 3).
///
/// The profile here is made up, built in the test: a CMS envelope in DER
/// around an XML plist, as Apple's are, with a certificate of its own
/// making. No real device, team or certificate is in it.
final class ExpiryWarningTests: XCTestCase {

    // MARK: - A made-up profile

    private func tlv(_ tag: UInt8, _ body: [UInt8]) -> [UInt8] {
        let n = body.count
        let length: [UInt8]
        switch n {
        case ..<0x80: length = [UInt8(n)]
        case ..<0x100: length = [0x81, UInt8(n)]
        case ..<0x10000: length = [0x82, UInt8(n >> 8), UInt8(n & 0xFF)]
        default: length = [0x83, UInt8(n >> 16), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
        }
        return [tag] + length + body
    }

    private func seq(_ parts: [UInt8]...) -> [UInt8] { tlv(0x30, parts.flatMap { $0 }) }

    private let signedDataOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02]
    private let dataOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x01]
    private let sha256RSAOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]
    private let sha256OID: [UInt8] = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]
    private let commonNameOID: [UInt8] = [0x55, 0x04, 0x03]

    private func utcTime(_ text: String) -> [UInt8] { tlv(0x17, Array(text.utf8)) }
    private func generalizedTime(_ text: String) -> [UInt8] { tlv(0x18, Array(text.utf8)) }

    /// An X.509 certificate's shape, its contents made up: the fields up to
    /// the validity as RFC 5280 orders them, then a subject, a key and a
    /// signature of filler.
    private func certificate(notBefore: [UInt8] = [], notAfter: [UInt8],
                             version: Bool = true) -> Data {
        let name = seq(tlv(0x31, seq(tlv(0x06, commonNameOID),
                                     tlv(0x0C, Array("Example Distribution".utf8)))))
        let algorithm = seq(tlv(0x06, sha256RSAOID), tlv(0x05, []))
        var signed: [UInt8] = []
        if version { signed += tlv(0xA0, tlv(0x02, [0x02])) }
        signed += tlv(0x02, [0x01, 0x23, 0x45, 0x67])
        signed += algorithm + name
        signed += seq(notBefore.isEmpty ? utcTime("260918102237Z") : notBefore, notAfter)
        signed += name
        signed += seq(algorithm, tlv(0x03, [0x00] + [UInt8](repeating: 0x42, count: 140)))
        return Data(seq(seq(signed), algorithm,
                        tlv(0x03, [0x00] + [UInt8](repeating: 0x24, count: 256))))
    }

    /// A profile: `extra` over a made-up plist's own, in a CMS envelope
    /// with the certificates and a signer's filler after the plist.
    private func profile(expires: Date?, certificates: [Data],
                         extra: [String: Any] = [:]) throws -> Data {
        var plist: [String: Any] = [
            "AppIDName": "Example",
            "Name": "Example Ad Hoc",
            "TeamIdentifier": ["EXAMPLE000"],
            "ProvisionedDevices": ["00000000-0000000000000000"],
            "CreationDate": Date(timeIntervalSince1970: 1_789_000_000),
            "TimeToLive": 364,
            "Version": 1,
            "Platform": ["iOS"],
            "DeveloperCertificates": certificates,
            "Entitlements": ["get-task-allow": false],
        ]
        if let expires { plist["ExpirationDate"] = expires }
        for (key, value) in extra { plist[key] = value }
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml,
                                                     options: 0)
        let content = seq(tlv(0x06, dataOID), tlv(0xA0, tlv(0x04, [UInt8](xml))))
        let signerFiller = tlv(0x31, seq(tlv(0x02, [0x01]),
                                         tlv(0x04, [UInt8](repeating: 0x3C, count: 300))))
        let signedData = seq(tlv(0x02, [0x01]),
                             tlv(0x31, seq(tlv(0x06, sha256OID), tlv(0x05, []))),
                             content,
                             tlv(0xA0, certificates.flatMap { [UInt8]($0) }),
                             signerFiller)
        return Data(seq(tlv(0x06, signedDataOID), tlv(0xA0, signedData)))
    }

    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0,
                     _ s: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h,
                                                  minute: mi, second: s))!
    }

    /// The instant in today's profile and certificate: 18 September 2027,
    /// 10:22:36 UTC.
    private var stops: Date { utc(2027, 9, 18, 10, 22, 36) }

    // MARK: - Reading the profile

    /// The plist is read whole out of its envelope, past the certificates
    /// and the signer after it, and its expiry with it.
    func testTheProfilesPlistIsReadOutOfItsEnvelope() throws {
        let cert = certificate(notAfter: utcTime("270918102236Z"))
        let data = try profile(expires: stops, certificates: [cert])
        let plist = try XCTUnwrap(AppExpiry.plist(in: data))
        XCTAssertEqual(plist["ExpirationDate"] as? Date, stops)
        XCTAssertEqual(plist["Name"] as? String, "Example Ad Hoc")
        XCTAssertEqual((plist["DeveloperCertificates"] as? [Any])?.compactMap { $0 as? Data },
                       [cert])
        // The envelope is DER: a constructed SEQUENCE with a long length.
        XCTAssertEqual(data.first, 0x30)
        XCTAssertEqual(data[data.startIndex + 1], 0x82)

        XCTAssertNil(AppExpiry.plist(in: Data()))
        XCTAssertNil(AppExpiry.plist(in: Data("<?xml version=\"1.0\"?><plist>".utf8)))
        XCTAssertNil(AppExpiry.plist(in: Data("no plist here at all".utf8)))
        // A plist that is not a dictionary.
        let array = try PropertyListSerialization.data(fromPropertyList: ["a"], format: .xml,
                                                       options: 0)
        XCTAssertNil(AppExpiry.plist(in: Data([0x30, 0x00]) + array))
    }

    /// The certificate's `notAfter`, in both of X.509's forms of time,
    /// with the version and without.
    func testTheCertificatesNotAfterIsRead() {
        XCTAssertEqual(AppExpiry.notAfter(certificate: certificate(notAfter: utcTime("270918102236Z"))),
                       stops)
        XCTAssertEqual(AppExpiry.notAfter(certificate: certificate(notAfter: generalizedTime("20270918102236Z"))),
                       stops)
        XCTAssertEqual(AppExpiry.notAfter(certificate: certificate(notAfter: utcTime("270918102236Z"),
                                                                   version: false)),
                       stops)
        // UTCTime's years: 50 to 99 are 1950 to 1999, 00 to 49 2000 to 2049.
        XCTAssertEqual(AppExpiry.notAfter(certificate: certificate(notAfter: utcTime("491231235959Z"))),
                       utc(2049, 12, 31, 23, 59, 59))
        XCTAssertEqual(AppExpiry.notAfter(certificate: certificate(notAfter: utcTime("500101000000Z"))),
                       utc(1950, 1, 1))
        // notBefore is not notAfter.
        XCTAssertEqual(AppExpiry.notAfter(certificate: certificate(notBefore: utcTime("200101000000Z"),
                                                                   notAfter: utcTime("300101000000Z"))),
                       utc(2030, 1, 1))
    }

    /// Anything not a certificate's time where one should be is nothing,
    /// never a wrong date and never a crash.
    func testANotAfterThatCannotBeReadIsNothing() {
        for bad in ["270918102236", "2709181022Z", "270918102236+0000", "27O918102236Z",
                    "270231102236Z", "271318102236Z", "270918252236Z", "270918106036Z", ""] {
            XCTAssertNil(AppExpiry.notAfter(certificate: certificate(notAfter: utcTime(bad))), bad)
        }
        XCTAssertNil(AppExpiry.notAfter(certificate: certificate(notAfter: generalizedTime("270918102236Z"))))
        // The right length, a digit where the Z should be: in either form.
        XCTAssertNil(AppExpiry.notAfter(certificate: certificate(notAfter: utcTime("2709181022360"))))
        XCTAssertNil(AppExpiry.notAfter(certificate: certificate(notAfter: generalizedTime("202709181022360"))))
        XCTAssertNil(AppExpiry.notAfter(certificate: certificate(notAfter: tlv(0x04, Array("270918102236Z".utf8)))))
        let whole = [UInt8](certificate(notAfter: utcTime("270918102236Z")))
        // Cut short at every length: nothing, never a fault.
        for end in 0..<whole.count {
            XCTAssertNil(AppExpiry.notAfter(certificate: Data(whole[0..<end])), "\(end)")
        }
        // A length that runs past its holder.
        var long = whole
        long[1] = 0x83
        XCTAssertNil(AppExpiry.notAfter(certificate: Data(long)))
        // BER's indefinite length.
        XCTAssertNil(AppExpiry.notAfter(certificate: Data([0x30, 0x80, 0x30, 0x80, 0x00, 0x00, 0x00, 0x00])))
        XCTAssertNil(AppExpiry.notAfter(certificate: Data()))
        XCTAssertNil(AppExpiry.notAfter(certificate: Data("not a certificate".utf8)))
        // Fields out of order: no validity where the validity is.
        let shuffled = seq(seq(tlv(0xA0, tlv(0x02, [0x02])), tlv(0x02, [0x01]),
                               seq(utcTime("200101000000Z"), utcTime("300101000000Z"))))
        XCTAssertNil(AppExpiry.notAfter(certificate: Data(shuffled)))
    }

    /// The day it stops: the profile's, or the certificate's if earlier;
    /// one already past left out; one that cannot be read passed over; none
    /// without the profile's own date.
    func testTheAppStopsAtTheEarlierOfTheProfileAndTheCertificate() throws {
        let now = utc(2027, 8, 1)
        let same = certificate(notAfter: utcTime("270918102236Z"))
        XCTAssertEqual(AppExpiry.stops(profile: try profile(expires: stops, certificates: [same]),
                                       now: now), stops)
        let sooner = certificate(notAfter: utcTime("270901000000Z"))
        XCTAssertEqual(AppExpiry.stops(profile: try profile(expires: stops, certificates: [sooner]),
                                       now: now), utc(2027, 9, 1))
        let later = certificate(notAfter: utcTime("300101000000Z"))
        XCTAssertEqual(AppExpiry.stops(profile: try profile(expires: stops, certificates: [later]),
                                       now: now), stops)
        // Two: the sooner, while it is still to come.
        XCTAssertEqual(AppExpiry.stops(profile: try profile(expires: stops,
                                                            certificates: [later, sooner]),
                                       now: now), utc(2027, 9, 1))
        // Once it has passed with the app still opening, the app was not
        // signed with it.
        XCTAssertEqual(AppExpiry.stops(profile: try profile(expires: stops,
                                                            certificates: [later, sooner]),
                                       now: utc(2027, 9, 2)), stops)
        // A certificate that cannot be read, and none at all.
        let broken = Data([0x30, 0x03, 0x02, 0x01, 0x00])
        XCTAssertEqual(AppExpiry.stops(profile: try profile(expires: stops, certificates: [broken]),
                                       now: now), stops)
        XCTAssertEqual(AppExpiry.stops(profile: try profile(expires: stops, certificates: []),
                                       now: now), stops)
        XCTAssertEqual(AppExpiry.stops(profile: try profile(expires: stops, certificates: [],
                                                            extra: ["DeveloperCertificates": "x"]),
                                       now: now), stops)
        // No ExpirationDate, or not a date: nothing, whatever the certificate.
        XCTAssertNil(AppExpiry.stops(profile: try profile(expires: nil, certificates: [sooner]),
                                     now: now))
        XCTAssertNil(AppExpiry.stops(profile: try profile(expires: nil, certificates: [sooner],
                                                          extra: ["ExpirationDate": "2027-09-18"]),
                                     now: now))
    }

    /// The bundle: its profile; nothing without one; nothing for an app
    /// TrollStore installed, its signature holding the entitlement
    /// TrollStore adds, even with a profile in the bundle; the profile read
    /// when the entitlement is not held or could not be read; and a profile
    /// with no date in it. TrollStore's mark beside the bundle decides
    /// nothing: on the iPad the app's sandbox hides it (B-137).
    func testTheBundleIsReadAndTrollStoreAndNoProfileSayNothing() throws {
        let files = FileManager.default
        let container = files.temporaryDirectory
            .appendingPathComponent("ExpiryWarningTests-\(UUID().uuidString)", isDirectory: true)
        let bundle = container.appendingPathComponent("Blackmail.app", isDirectory: true)
        try files.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: container) }
        let now = utc(2027, 8, 1)

        XCTAssertEqual(AppExpiry.read(bundle: bundle, containerRequired: .notHeld, now: now),
                       .noProfile)

        let profileURL = bundle.appendingPathComponent("embedded.mobileprovision")
        try profile(expires: stops, certificates: [certificate(notAfter: utcTime("270918102236Z"))])
            .write(to: profileURL)
        XCTAssertEqual(AppExpiry.read(bundle: bundle, containerRequired: .notHeld, now: now),
                       .stops(stops))
        XCTAssertEqual(AppExpiry.read(bundle: bundle, containerRequired: .unread, now: now),
                       .stops(stops), "a signature not read is a certificate's")
        XCTAssertEqual(AppExpiry.read(bundle: bundle, containerRequired: .held, now: now),
                       .trollStore)

        for mark in ["_TrollStore", "_TrollStoreLite"] {
            let markURL = container.appendingPathComponent(mark)
            try Data().write(to: markURL)
            XCTAssertEqual(AppExpiry.read(bundle: bundle, containerRequired: .notHeld, now: now),
                           .stops(stops), mark)
            try files.removeItem(at: markURL)
        }

        try Data("not a profile".utf8).write(to: profileURL)
        XCTAssertEqual(AppExpiry.read(bundle: bundle, containerRequired: .notHeld, now: now),
                       .unreadable)
        XCTAssertEqual(AppExpiry.read(bundle: bundle, containerRequired: .held, now: now),
                       .trollStore)

        XCTAssertEqual(AppExpiry.Found.stops(stops).logged, "stops 2027-09-18 10:22:36 +0000")
        XCTAssertEqual(AppExpiry.Found.trollStore.logged, "none, TrollStore")
        XCTAssertEqual(AppExpiry.Found.noProfile.logged, "none, no profile")
        XCTAssertEqual(AppExpiry.Found.unreadable.logged, "none, profile unreadable")
    }

    // MARK: - The day rules

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    /// In New York the app stops at 6:22:36 AM on 18 September: said from
    /// the first moment of 19 August, thirty days before, up to that
    /// instant, and not after it.
    func testItIsSaidInTheLastThirtyDaysUpToTheInstant() {
        let ny = calendar("America/New_York")
        func due(_ now: Date) -> Bool {
            ExpiryWarning.isDue(stops: stops, now: now, lastShown: nil, calendar: ny)
        }
        XCTAssertFalse(due(utc(2026, 10, 25)))
        XCTAssertFalse(due(utc(2027, 8, 19, 3, 59, 59)), "11:59:59 PM on 18 August")
        XCTAssertTrue(due(utc(2027, 8, 19, 4)), "midnight starting 19 August")
        XCTAssertTrue(due(utc(2027, 9, 1, 15)))
        XCTAssertTrue(due(utc(2027, 9, 17, 23)))
        XCTAssertTrue(due(utc(2027, 9, 18, 10, 22, 35)), "the second before")
        XCTAssertFalse(due(stops), "the instant itself")
        XCTAssertFalse(due(utc(2027, 9, 18, 12)))
        XCTAssertFalse(due(utc(2028, 1, 1)))
        // Across the clocks going back in November: still thirty days, by
        // the calendar.
        let november = utc(2027, 11, 30, 15)
        XCTAssertTrue(ExpiryWarning.isDue(stops: november, now: utc(2027, 10, 31, 4), lastShown: nil,
                                          calendar: ny))
        XCTAssertFalse(ExpiryWarning.isDue(stops: november, now: utc(2027, 10, 31, 3, 59),
                                           lastShown: nil, calendar: ny))
    }

    /// Once a day: not again the same day, whenever in it; again from the
    /// next midnight where he is.
    func testItIsSaidOnceADay() {
        let ny = calendar("America/New_York")
        let morning = utc(2027, 9, 1, 13)       // 9 AM in New York
        func due(_ now: Date, _ shown: Date?) -> Bool {
            ExpiryWarning.isDue(stops: stops, now: now, lastShown: shown, calendar: ny)
        }
        XCTAssertTrue(due(morning, nil))
        XCTAssertTrue(due(morning, utc(2027, 8, 31, 13)), "shown yesterday")
        XCTAssertFalse(due(morning, morning))
        XCTAssertFalse(due(utc(2027, 9, 2, 3, 59), morning), "11:59 PM the same day")
        XCTAssertTrue(due(utc(2027, 9, 2, 4), morning), "midnight, the next day")
        // A day is his: 9 PM on 1 September in New York is 2 September in
        // UTC, and the same day as the morning.
        XCTAssertFalse(due(utc(2027, 9, 2, 1), morning))
        // Shown at 11:59 PM, due at 12:01 AM.
        XCTAssertTrue(due(utc(2027, 9, 2, 4, 1), utc(2027, 9, 2, 3, 59)))
    }

    /// The words, the day as the iPad's region writes a long date, in his
    /// zone: the instant is 18 September everywhere he could be but west
    /// of Hawaii's, where it is still the 17th.
    func testTheWordsSayTheDayInTheRegionsWay() {
        XCTAssertEqual(ExpiryWarning.words(stops: stops, locale: Locale(identifier: "en_US"),
                                           timeZone: TimeZone(identifier: "America/New_York")!),
                       "This app will stop opening on September 18, 2027. After that, use Mail.")
        XCTAssertEqual(ExpiryWarning.words(stops: stops, locale: Locale(identifier: "en_GB"),
                                           timeZone: TimeZone(identifier: "Europe/London")!),
                       "This app will stop opening on 18 September 2027. After that, use Mail.")
        XCTAssertEqual(ExpiryWarning.words(stops: stops, locale: Locale(identifier: "en_US"),
                                           timeZone: TimeZone(identifier: "Pacific/Pago_Pago")!),
                       "This app will stop opening on September 17, 2027. After that, use Mail.")
        // The form is the locale's own long date, no pattern of its own.
        let formatter = DisplayDates.formatter(.longDate, locale: Locale(identifier: "en_US"),
                                               timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(formatter.dateStyle, .long)
        XCTAssertEqual(formatter.timeStyle, .none)
    }

    /// The warning as the app asks for it: from what the profile said, over
    /// the defaults it keeps the day in.
    func testTheWarningKeepsTheDayItWasShown() throws {
        let suite = "ExpiryWarningTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let us = Locale(identifier: "en_US")
        let ny = TimeZone(identifier: "America/New_York")!
        let morning = utc(2027, 9, 1, 13)

        for found in [AppExpiry.Found.noProfile, .trollStore, .unreadable] {
            XCTAssertNil(ExpiryWarning(found: found, defaults: defaults)
                .words(at: morning, locale: us, timeZone: ny))
        }
        let warning = ExpiryWarning(found: .stops(stops), defaults: defaults)
        XCTAssertNil(warning.words(at: utc(2027, 8, 1), locale: us, timeZone: ny))
        XCTAssertEqual(warning.words(at: morning, locale: us, timeZone: ny),
                       "This app will stop opening on September 18, 2027. After that, use Mail.")
        // Asking is not showing.
        XCTAssertNotNil(warning.words(at: morning, locale: us, timeZone: ny))
        warning.shown(at: morning)
        XCTAssertEqual(defaults.object(forKey: ExpiryWarning.key) as? Date, morning)
        XCTAssertNil(warning.words(at: utc(2027, 9, 1, 20), locale: us, timeZone: ny))
        // 9 PM in New York, the same day there, is the next day in UTC.
        XCTAssertNil(warning.words(at: utc(2027, 9, 2, 1), locale: us, timeZone: ny))
        // Kept: a warning made afresh, as at the next launch, knows it too.
        XCTAssertNil(ExpiryWarning(found: .stops(stops), defaults: defaults)
            .words(at: utc(2027, 9, 1, 22), locale: us, timeZone: ny))
        XCTAssertNotNil(warning.words(at: utc(2027, 9, 2, 13), locale: us, timeZone: ny))

        // Up at 9 PM on 2 September, and still up the next morning, when
        // he taps OK: that is said for 3 September too, and it does not
        // come again that day. Taken as said only when it went up, it
        // would come again within half a minute of the OK.
        warning.shown(at: utc(2027, 9, 3, 1))
        XCTAssertNotNil(warning.words(at: utc(2027, 9, 3, 13), locale: us, timeZone: ny))
        warning.shown(at: utc(2027, 9, 3, 13))
        XCTAssertNil(warning.words(at: utc(2027, 9, 3, 13, 0, 30), locale: us, timeZone: ny))
        XCTAssertEqual(ExpiryWarning.key, "blackmail.expiryWarningShown")
        XCTAssertEqual(ExpiryWarning.days, 30)
    }

    // MARK: - Where it is put up

    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    private func part(of code: String, from start: String, to end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start), start)
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex), end)
        return String(code[from.lowerBound..<to.lowerBound])
    }

    /// The alert: no title, the words, OK alone, put up by
    /// `ErrorPresenter.warn`; only with nothing over the mail, no finger on
    /// the list and no page's alert held for one (B-103), no letter being
    /// printed, and the app not in the background; the day taken as said
    /// once it is up, and again at OK. Asked once the launch's first page
    /// has been tried and at every check of the watch, and from nowhere
    /// else.
    func testItIsPutUpOnlyWithNothingOverTheMail() throws {
        let root = try source("UI/RootViewController.swift")
        let warn = try part(of: root, from: "private func warnOfExpiryIfDue() {",
                            to: "private var wentAwayAt: Date?")
        XCTAssertTrue(warn.contains("guard view.window != nil, presentedViewController == nil, "
                                    + "UIApplication.shared.applicationState != .background, "
                                    + "!list.isInHand, !list.isOpeningDraft, "
                                    + "!detail.isPrinting, !detail.isOpeningFile "
                                    + "else { return }"), warn)
        XCTAssertTrue(warn.contains("let warning = ExpiryWarning.app"), warn)
        XCTAssertTrue(warn.contains("guard let words = warning.words(at: now) else { return }"), warn)
        XCTAssertTrue(warn.contains("ErrorPresenter.warn(words, over: self, shown: { "
                                    + "warning.shown(at: now) "
                                    + "Diagnostics.log(.note, \"EXPIRY-WARNING shown\") "
                                    + "}, dismissed: { warning.shown(at: Date()) })"), warn)
        // Shown is written once the alert is up, and again at OK.
        XCTAssertEqual(warn.components(separatedBy: "shown(at:").count - 1, 2, warn)

        // The finger on the list as the list's own rules have it, and a
        // page's alert held for its let-go.
        let list = try source("UI/MessageListViewController.swift")
        let inHand = try part(of: list, from: "var isInHand: Bool {",
                              to: "@MainActor private func showWhenLetGo(")
        XCTAssertEqual(inHand, "var isInHand: Bool { guard isViewLoaded else { return false } "
                       + "return tableView.isTracking || tableView.isDragging "
                       + "|| tableView.isDecelerating || afterLetGo.held != nil } ")
        // A print, from Print to its panel closed.
        XCTAssertTrue(try source("UI/MessageDetailViewController.swift")
            .contains("var isPrinting: Bool { printing != nil }"))

        // The alert: no title, the words, OK alone, `shown` as the
        // presentation's completion and `dismissed` at OK, the alerts that
        // waited for it put up after.
        let presenter = try source("UI/ErrorPresenter.swift")
        let alert = try part(of: presenter, from: "static func warn(",
                             to: "private static weak var warning")
        XCTAssertEqual(alert, "static func warn(_ text: String, over vc: UIViewController, "
                       + "shown: @escaping () -> Void, dismissed: @escaping () -> Void) { "
                       + "let alert = UIAlertController(title: nil, message: text, "
                       + "preferredStyle: .alert) "
                       + "alert.addAction(UIAlertAction(title: \"OK\", style: .default) { _ in "
                       + "dismissed() warning = nil let waiting = afterWarning "
                       + "afterWarning = [] showFirst(waiting) }) "
                       + "afterWarning = [] warning = alert "
                       + "vc.present(alert, animated: true, completion: shown) } ")
        // Every alert asked for while it is up waits for its OK, a sheet's
        // held alerts too: they all go through `showFirst`.
        let first = try part(of: presenter, from: "private static func showFirst(",
                             to: "static func log(_ line: String) {")
        XCTAssertEqual(first, "private static func showFirst(_ alerts: [() -> Bool]) { "
                       + "guard warning?.presentingViewController == nil else { "
                       + "afterWarning = alerts + afterWarning return } "
                       + "for present in alerts where present() { return } } ")
        XCTAssertTrue(presenter.contains("private static weak var warning: UIAlertController? "
                                         + "private static var afterWarning: [() -> Bool] = []"))
        XCTAssertEqual(presenter.components(separatedBy: "vc.present(").count - 1, 2)
        XCTAssertEqual(presenter.components(separatedBy: "showFirst(").count - 1, 5)

        // Asked once the launch's first page has been tried, and at every
        // check of the watch; nowhere else.
        let launch = try part(of: root, from: "list.onFirstLoadFinished = { [weak self] came in "
                                               + "self?.mailboxList.releaseSweeps",
                              to: "override func viewDidAppear")
        XCTAssertTrue(launch.hasPrefix("list.onFirstLoadFinished = { [weak self] came in "
                                       + "self?.mailboxList.releaseSweeps(firstPageCame: came) "
                                       + "self?.warnOfExpiryIfDue() self?.firstPageTried = true"),
                      launch)
        let checked = try part(of: root, from: "func checked(_ outcome: MailWatch.Outcome) {",
                               to: "guard lastCheckFailed else { return }")
        XCTAssertTrue(checked.hasPrefix("func checked(_ outcome: MailWatch.Outcome) { "
                                        + "list.checked(outcome) warnOfExpiryIfDue() "
                                        + "if case .failed = outcome {"), checked)
        XCTAssertEqual(root.components(separatedBy: "warnOfExpiryIfDue()").count - 1, 3)
        XCTAssertEqual(presenter.components(separatedBy: "warn(").count - 1, 1)
        // Asked with no locale or zone: the iPad's, as every date he is
        // shown (B-119).
        XCTAssertTrue(try source("Mail/ExpiryWarning.swift").contains(
            "func words(at now: Date, locale: Locale = .current, timeZone: TimeZone = .current) "
            + "-> String? {"))
    }

    /// The day is never written into the app: it is the profile's. Only
    /// the root's warning asks for the words, and nothing in the share
    /// sheet, where he is always writing a letter.
    func testTheDayIsNeverInTheCode() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let walk = try XCTUnwrap(FileManager.default.enumerator(at: sources,
                                                                includingPropertiesForKeys: nil))
        var read = 0
        var askers: [String] = []
        for case let url as URL in walk where url.pathExtension == "swift" {
            let code = try String(contentsOf: url, encoding: .utf8)
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            read += 1
            for line in code {
                for day in ["2027", "September 18", "09-18"] {
                    XCTAssertFalse(line.contains(day), "\(url.lastPathComponent): \(line)")
                }
                if line.contains("ExpiryWarning.app") || line.contains("AppExpiry.app") {
                    askers.append(url.lastPathComponent)
                }
            }
        }
        XCTAssertGreaterThan(read, 100)
        XCTAssertEqual(Set(askers), ["RootViewController.swift", "ExpiryWarning.swift"])
        let expiry = try source("Mail/AppExpiry.swift")
        XCTAssertTrue(expiry.contains("read(bundle: Bundle.main.bundleURL, containerRequired: entitlement, now: Date())"))
        XCTAssertTrue(expiry.contains("plist[\"ExpirationDate\"] as? Date"))
    }

    // MARK: - Where it meets the other branches

    /// A screen of the suite's own, for `OverTheMail`.
    private final class Screen {}

    /// The warning waits for a draft tapped in Drafts and for a file or a
    /// picture tapped in the pane while they download, as for a print: put
    /// up meanwhile, UIKit refused the composer, or the pane let the
    /// preview go, and after OK nothing opened. The draft held from the
    /// tap until the one tapped last has come or failed; the file counted
    /// at the tap, before its task, and let go only once its preview is up
    /// or its download has ended, nothing awaited between.
    func testItWaitsForADraftOrAFileOnItsWay() throws {
        var drafts = DraftOpening()
        XCTAssertNil(drafts.loading)
        XCTAssertTrue(drafts.tap("5/12"))
        XCTAssertNotNil(drafts.loading, "on its way from the tap")
        XCTAssertTrue(drafts.tap("5/13"))
        XCTAssertFalse(drafts.landed("5/12"))
        XCTAssertNotNil(drafts.loading, "the draft tapped since still on its way")
        XCTAssertTrue(drafts.landed("5/13"))
        XCTAssertNil(drafts.loading, "opened, or its failure said")

        let root = try source("UI/RootViewController.swift")
        let guarded = try part(of: root, from: "private func warnOfExpiryIfDue() {",
                               to: "let warning = ExpiryWarning.app")
        XCTAssertTrue(guarded.contains("!list.isOpeningDraft,"), guarded)
        XCTAssertTrue(guarded.contains("!detail.isOpeningFile else { return }"), guarded)

        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains("var isOpeningDraft: Bool { drafts.loading != nil }"))
        // Taken off and the composer put up in one turn of the main thread:
        // nothing awaited, and no hop to a later turn, in which a check of
        // the watch could find the draft let go and the composer not up.
        let landed = try part(of: list, from: "guard self.drafts.landed(summary.id) else { return }",
                              to: "private func openWaiting(")
        XCTAssertEqual(landed, "guard self.drafts.landed(summary.id) else { return } "
                       + "self.showDraftSpinners() if let row = self.rowIndex(showing: summary.id) { "
                       + "self.tableView.deselectRow(at: IndexPath(row: row, section: 0), "
                       + "animated: false) } if notKept { PaneActions.notTheKeptLetter(summary, "
                       + "list: self.letters) return } guard let draft else { "
                       + "ErrorPresenter.show(reaching: failure, on: self) return } "
                       + "self.presentComposer(draft, key: nil, from: summary) } } @MainActor ")
        let composer = try part(of: list, from: "private func presentComposer(",
                                to: "private func showDraftSpinners(")
        XCTAssertTrue(composer.hasSuffix("let nav = UINavigationController(rootViewController: compose) "
                                         + "nav.modalPresentationStyle = .formSheet "
                                         + "present(nav, animated: true) } @MainActor "), composer)
        for hop in ["await", "DispatchQueue", "asyncAfter", "Task {", "Task.", "RunLoop", "perform("] {
            XCTAssertFalse(landed.contains(hop), hop)
        }

        let pane = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(pane.contains("private var filesOpening = 0"))
        // And a picture being marked up for Markup and Reply (B-171).
        XCTAssertTrue(pane.contains("var isOpeningFile: Bool { filesOpening > 0 || markup.isBusy(at: Date()) }"))
        let open = try part(of: pane, from: "private func openAttachment(",
                            to: "private func prepareInlineImages(")
        XCTAssertTrue(open.contains("let shown = loads.shown "
                                    + "let file = FileTaps.File(letter: m.id, part: attachment.id, shown: shown) "
                                    + "guard fileTaps.tapped(file, for: item) else { return } filesOpening += 1 "
                                    + "Task { @MainActor in defer { filesOpening -= 1 fileTaps.ended(file) "
                                    + "if message?.id == m.id {"), open)
        XCTAssertEqual(open.components(separatedBy: "filesOpening").count - 1, 2, open)
        XCTAssertEqual(pane.components(separatedBy: "filesOpening").count - 1, 4)
        // Nothing awaited between the file come and its preview put up, and
        // no hop to a later turn: the count is let go in the `defer`, after
        // the preview is presented, in the same turn.
        let shown = try part(of: open, from: "let data = try await", to: "} catch {")
        XCTAssertEqual(shown, "let data = try await repository.fetchAttachmentData( "
                       + "attachment.id, of: m.id, mailboxID: m.mailboxID) "
                       + "guard loads.stillShows(shown) else { return } "
                       + "guard fileTaps.opens(file) else { return } "
                       + "let use = fileTaps.item(of: file) ?? item "
                       + "if !use.presents { keep(data, of: attachment, by: use) return } "
                       + "guard presentedViewController == nil else { return } "
                       + "if let shown = previewURL { AttachmentStore.removeStaged(shown) } "
                       + "previewURL = nil "
                       + "let url = try AttachmentStore.write(data, named: attachment.filename) "
                       + "previewURL = url switch use { case .saveToFiles: "
                       + "present(UIDocumentPickerViewController(forExporting: [url], asCopy: true), animated: true) "
                       + "case .share: let share = UIActivityViewController(activityItems: [url], "
                       + "applicationActivities: nil) share.popoverPresentationController?.sourceView = webView "
                       + "share.popoverPresentationController?.sourceRect = pictureSpot present(share, animated: true) "
                       + "case .markupAndReply: let preview = QLPreviewController() preview.dataSource = self "
                       + "preview.delegate = self preview.modalPresentationStyle = .fullScreen "
                       + "MarkupReply.letGo(markup.begin(ObjectIdentifier(preview))) marking = (m, attachment) "
                       + "present(preview, animated: true) "
                       + "case .quickLook, .saveImage, .copy: "
                       + "let preview = QLPreviewController() preview.dataSource = self "
                       + "preview.modalPresentationStyle = .fullScreen "
                       + "present(preview, animated: true) } ")
        XCTAssertEqual(shown.components(separatedBy: "await").count - 1, 1, shown)
        for hop in ["DispatchQueue", "asyncAfter", "Task {", "Task.", "RunLoop", "perform("] {
            XCTAssertFalse(shown.contains(hop), hop)
        }
    }

    /// No alert is put over the warning itself. Asked for while it is up,
    /// it waits for OK, and the warning has gone by then: an Edit-mode
    /// batch refused after he had opened another folder found the warning
    /// in front, and its refusal went with it, unseen. What is in front
    /// stops below the warning, and an alert asked for over the warning all
    /// the same goes over what the warning is over. Every walk up the
    /// presented screens is `ErrorPresenter.over`'s, but a `mailto:` link's
    /// from another app, which presents its composer at once and waits for
    /// nothing.
    func testNoAlertIsPutOverTheWarningItself() throws {
        let root = Screen(), sheet = Screen(), alert = Screen(), warning = Screen()
        XCTAssertTrue(OverTheMail<Screen>(screens: [], warning: nil).front(root: root) === root)
        XCTAssertTrue(OverTheMail(screens: [sheet], warning: nil).front(root: root) === sheet)
        XCTAssertTrue(OverTheMail(screens: [sheet, alert], warning: nil).front(root: root) === alert)
        XCTAssertTrue(OverTheMail(screens: [warning], warning: warning).front(root: root) === root,
                      "the warning alone: the root under it")
        XCTAssertTrue(OverTheMail(screens: [sheet, warning], warning: warning)
                        .front(root: root) === sheet, "the sheet under it")
        XCTAssertTrue(OverTheMail(screens: [sheet], warning: warning).front(root: root) === sheet,
                      "the warning not among them")

        XCTAssertTrue(OverTheMail.host(for: warning, warning: warning, presenter: root) === root)
        XCTAssertTrue(OverTheMail.host(for: warning, warning: warning, presenter: sheet) === sheet)
        XCTAssertTrue(OverTheMail.host(for: sheet, warning: warning, presenter: root) === sheet)
        XCTAssertTrue(OverTheMail.host(for: sheet, warning: nil, presenter: root) === sheet)
        XCTAssertTrue(OverTheMail.host(for: warning, warning: warning, presenter: nil) === warning,
                      "not presented: as asked")

        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains("private func alertHost(in window: UIWindow?) -> UIViewController { "
                                    + "guard viewIfLoaded?.window == nil, let root = "
                                    + "window?.rootViewController else { return self } "
                                    + "return ErrorPresenter.over(root).front(root: root) }"))
        let presenter = try source("UI/ErrorPresenter.swift")
        let over = try part(of: presenter, from: "static func over(", to: "private static func put(")
        XCTAssertEqual(over, "static func over(_ root: UIViewController) -> OverTheMail<UIViewController> { "
                       + "var screens: [UIViewController] = [] var front = root "
                       + "while let next = front.presentedViewController, !next.isBeingDismissed { "
                       + "screens.append(next) front = next } "
                       + "return OverTheMail(screens: screens, warning: warning, "
                       + "waiting: afterWarning.count) } ")
        let put = try part(of: presenter, from: "private static func put(",
                           to: "let alert = UIAlertController(title: title")
        XCTAssertEqual(put, "private static func put(_ text: String, title: String?, "
                       + "offeringSettings: Bool, on asked: UIViewController) { "
                       + "let vc = OverTheMail.host(for: asked, warning: warning, "
                       + "presenter: asked.presentingViewController) "
                       + "let present = { [weak vc] () -> Bool in "
                       + "guard let vc, vc.viewIfLoaded?.window != nil else { return false } ")

        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let walk = try XCTUnwrap(FileManager.default.enumerator(at: sources,
                                                                includingPropertiesForKeys: nil))
        var walkers: [String] = []
        for case let url as URL in walk where url.pathExtension == "swift" {
            let code = try String(contentsOf: url, encoding: .utf8)
            for line in code.components(separatedBy: "\n")
            where line.contains("while let") && line.contains(".presentedViewController") {
                walkers.append(url.lastPathComponent)
            }
        }
        XCTAssertEqual(walkers.sorted(), ["AppDelegate.swift", "ErrorPresenter.swift"])
        XCTAssertTrue(try source("App/AppDelegate.swift").contains(
            "while let shown = top.presentedViewController, !shown.isBeingDismissed { top = shown } "
            + "let compose = ComposeViewController(repository: root.repository, draft: draft)"))
    }

    /// The warning is not a sheet he has open: left up overnight, the iPad
    /// locked over it, his return after a while away still takes him to the
    /// Inbox at its top, under it (B-003). A sheet does hold it, over the
    /// warning or without it, and so does another alert.
    func testTheWarningIsNotASheetOpenOnHisReturn() throws {
        let sheet = Screen(), alert = Screen(), warning = Screen()
        XCTAssertFalse(OverTheMail<Screen>(screens: [], warning: nil).sheetOpen)
        XCTAssertFalse(OverTheMail(screens: [warning], warning: warning).sheetOpen)
        XCTAssertTrue(OverTheMail(screens: [sheet], warning: nil).sheetOpen)
        XCTAssertTrue(OverTheMail(screens: [alert], warning: nil).sheetOpen)
        XCTAssertTrue(OverTheMail(screens: [sheet], warning: warning).sheetOpen)
        XCTAssertTrue(OverTheMail(screens: [warning, sheet], warning: warning).sheetOpen,
                      "a sheet over it")

        let long = Sitting.awayBeforeReturningToInbox + 1
        let up = OverTheMail(screens: [warning], warning: warning)
        XCTAssertFalse(up.holdsTheReturn)
        XCTAssertEqual(Sitting.onReturn(after: long, showingInbox: true,
                                        sheetOpen: up.holdsTheReturn), .refreshInbox)
        XCTAssertEqual(Sitting.onReturn(after: long, showingInbox: false,
                                        sheetOpen: up.holdsTheReturn), .openInbox)
        XCTAssertEqual(Sitting.onReturn(after: 60, showingInbox: false,
                                        sheetOpen: up.holdsTheReturn), .stay)
        let writing = OverTheMail(screens: [sheet], warning: nil)
        XCTAssertTrue(writing.holdsTheReturn)
        XCTAssertEqual(Sitting.onReturn(after: long, showingInbox: false,
                                        sheetOpen: writing.holdsTheReturn), .stay)

        let root = try source("UI/RootViewController.swift")
        let returning = try part(of: root, from: "private func returnedFromAway() {",
                                 to: "case .stay:")
        XCTAssertTrue(returning.contains("sheetOpen: ErrorPresenter.over(self).holdsTheReturn) {"),
                      returning)
        XCTAssertFalse(returning.contains("presentedViewController"), returning)
    }

    /// An alert waiting behind the warning holds his return after a while
    /// away, as it did before the warning stopped holding it: an Edit-mode
    /// Delete or Move refused in another folder as the warning went up is
    /// addressed to that folder's list, and with the Inbox put in its
    /// place under the warning, the refusal had nothing to go over at OK
    /// and was dropped. Only while the warning is up: one taken away
    /// without its OK holds nothing. With nothing waiting it still runs
    /// under the warning, and a sheet holds it whatever waits.
    func testTheReturnWaitsForAnAlertBehindTheWarning() throws {
        let sheet = Screen(), warning = Screen()
        let long = Sitting.awayBeforeReturningToInbox + 1
        let refused = OverTheMail(screens: [warning], warning: warning, waiting: 1)
        XCTAssertFalse(refused.sheetOpen, "still no sheet")
        XCTAssertTrue(refused.holdsTheReturn)
        XCTAssertTrue(OverTheMail(screens: [warning], warning: warning, waiting: 2).holdsTheReturn)
        XCTAssertEqual(Sitting.onReturn(after: long, showingInbox: false,
                                        sheetOpen: refused.holdsTheReturn), .stay)
        XCTAssertEqual(Sitting.onReturn(after: long, showingInbox: true,
                                        sheetOpen: refused.holdsTheReturn), .stay)
        XCTAssertFalse(OverTheMail(screens: [warning], warning: warning, waiting: 0).holdsTheReturn)
        XCTAssertFalse(OverTheMail<Screen>(screens: [], warning: nil, waiting: 1).holdsTheReturn,
                       "the warning gone without its OK")
        XCTAssertFalse(OverTheMail(screens: [], warning: warning, waiting: 1).holdsTheReturn,
                       "the warning not presented")
        XCTAssertTrue(OverTheMail(screens: [sheet], warning: nil, waiting: 0).holdsTheReturn)
        XCTAssertTrue(OverTheMail(screens: [warning, sheet], warning: warning, waiting: 0)
                        .holdsTheReturn)

        // Counted from the alerts kept for the warning's OK, the very list
        // `showFirst` keeps them in and OK empties.
        let presenter = try source("UI/ErrorPresenter.swift")
        XCTAssertTrue(presenter.contains(
            "return OverTheMail(screens: screens, warning: warning, waiting: afterWarning.count) }"))
        XCTAssertTrue(presenter.contains(
            "guard warning?.presentingViewController == nil else { "
            + "afterWarning = alerts + afterWarning return }"))
        XCTAssertTrue(presenter.contains(
            "warning = nil let waiting = afterWarning afterWarning = [] showFirst(waiting)"))
        let root = try source("UI/RootViewController.swift")
        let returning = try part(of: root, from: "private func returnedFromAway() {",
                                 to: "case .stay:")
        XCTAssertFalse(returning.contains(".sheetOpen"), returning)
    }
}
