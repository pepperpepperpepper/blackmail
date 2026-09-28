import XCTest
@testable import Blackmail

/// The list's and the reading pane's timestamps, with their formatters kept
/// (`DisplayDates`) rather than built on every call: the same words as a
/// formatter built afresh, the day worked out from `now` every time, and
/// the iPad's locale and time zone followed when they change.
final class DisplayDatesTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let posix = Locale(identifier: "en_US_POSIX")

    /// 2026-09-27, a Sunday, at `hour`:`minute` UTC, or `days` later.
    private func sunday(_ hour: Int, _ minute: Int, plusDays days: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 27 + days,
                                                  hour: hour, minute: minute))!
    }

    // MARK: - The day is never kept

    /// One letter, sent at ten to midnight, seen as the clock goes on: a
    /// time, then "Yesterday" once midnight has passed, then its weekday,
    /// then its date. Today and yesterday are `now`'s, worked out on every
    /// call; they used to be the clock's whatever `now` was handed in, and a
    /// kept "today" would go on giving it a time of day after midnight.
    func testTodayAndYesterdayAreWorkedOutFromNowEveryTime() {
        let letter = sunday(23, 50)
        let list = { (now: Date) in
            MailFormat.listTimestamp(letter, now: now, locale: self.posix, timeZone: self.utc)
        }
        let detail = { (now: Date) in
            MailFormat.detailTimestamp(letter, now: now, locale: self.posix, timeZone: self.utc)
        }

        XCTAssertEqual(list(sunday(23, 55)), "11:50 PM")
        XCTAssertEqual(list(sunday(0, 5, plusDays: 1)), "Yesterday")
        XCTAssertEqual(list(sunday(0, 5, plusDays: 2)), "Sunday")
        XCTAssertEqual(list(sunday(23, 0, plusDays: 6)), "Sunday", "within six days")
        XCTAssertEqual(list(sunday(0, 5, plusDays: 7)), "27/09/26")
        XCTAssertEqual(list(sunday(23, 55)), "11:50 PM", "and back")

        XCTAssertEqual(detail(sunday(23, 55)), "Today at 11:50 PM")
        XCTAssertEqual(detail(sunday(0, 5, plusDays: 1)), "Yesterday at 11:50 PM")
        XCTAssertEqual(detail(sunday(0, 5, plusDays: 2)), "27 September 2026 at 11:50 PM")
    }

    // MARK: - The zone and the locale are followed

    /// The same moment, seen from three zones: yesterday in UTC, this
    /// evening in New York, this morning in Tokyo.
    /// A formatter or calendar kept from the first would write the first
    /// zone's answer in all three, as a list kept on after a flight would.
    func testTheSameMomentIsWrittenForTheZoneItIsAskedFor() {
        let letter = sunday(23, 45)
        let now = sunday(0, 30, plusDays: 1)
        let list = { (zone: TimeZone) in
            MailFormat.listTimestamp(letter, now: now, locale: self.posix, timeZone: zone)
        }
        let detail = { (zone: TimeZone) in
            MailFormat.detailTimestamp(letter, now: now, locale: self.posix, timeZone: zone)
        }

        XCTAssertEqual(list(utc), "Yesterday")
        XCTAssertEqual(list(newYork), "7:45 PM")
        XCTAssertEqual(list(tokyo), "8:45 AM")
        XCTAssertEqual(list(utc), "Yesterday", "and back")

        XCTAssertEqual(detail(utc), "Yesterday at 11:45 PM")
        XCTAssertEqual(detail(newYork), "Today at 7:45 PM")
        XCTAssertEqual(detail(tokyo), "Today at 8:45 AM")

        // Far enough back for a date, which falls on another day in Tokyo.
        let older = sunday(20, 0, plusDays: -20)
        XCTAssertEqual(MailFormat.listTimestamp(older, now: now, locale: posix, timeZone: utc),
                       "07/09/26")
        XCTAssertEqual(MailFormat.listTimestamp(older, now: now, locale: posix, timeZone: tokyo),
                       "08/09/26")
    }

    /// The weekday in the language it is asked for, one after another.
    func testTheWeekdayIsInTheLanguageItIsAskedFor() {
        let letter = sunday(12, 0)
        let now = sunday(12, 0, plusDays: 3)
        let names = ["en_US_POSIX", "fr_FR", "de_DE", "en_US_POSIX"].map {
            MailFormat.listTimestamp(letter, now: now, locale: Locale(identifier: $0), timeZone: utc)
        }
        XCTAssertEqual(names, ["Sunday", "dimanche", "Sonntag", "Sunday"])
    }

    // MARK: - Kept, and made again

    /// A formatter is built once for its format and kept; it is built again
    /// when iOS says the time zone or the locale has changed, which is also
    /// how a change to the 24-hour clock arrives, and when it is asked for a
    /// zone or locale other than the one it was made for.
    func testFormattersAreKeptAndMadeAgainWhenTheZoneOrLocaleChanges() {
        let center = NotificationCenter()
        let dates = DisplayDates(notifications: center)
        let letter = sunday(9, 14)
        let time = { (zone: TimeZone) in
            dates.string(from: letter, format: "h:mm a", locale: self.posix, timeZone: zone)
        }

        XCTAssertEqual(time(utc), "9:14 AM")
        XCTAssertEqual(time(utc), "9:14 AM")
        XCTAssertEqual(dates.built, 1, "kept")
        XCTAssertEqual(dates.string(from: letter, format: "EEEE", locale: posix, timeZone: utc),
                       "Sunday")
        XCTAssertEqual(dates.built, 2, "one for each format")

        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        XCTAssertEqual(time(utc), "9:14 AM")
        XCTAssertEqual(dates.built, 3, "made again after the time zone changed")

        center.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        XCTAssertEqual(time(utc), "9:14 AM")
        XCTAssertEqual(dates.built, 4, "made again after the locale changed")

        XCTAssertEqual(time(tokyo), "6:14 PM")
        XCTAssertEqual(time(tokyo), "6:14 PM")
        XCTAssertEqual(dates.built, 5, "made again for another zone, then kept")
        XCTAssertEqual(dates.string(from: letter, format: "h:mm a",
                                    locale: Locale(identifier: "de_DE"), timeZone: tokyo),
                       fresh("h:mm a", Locale(identifier: "de_DE"), tokyo).string(from: letter))
        XCTAssertEqual(dates.built, 6, "and for another locale")
    }

    /// The instance the app uses, and one made as the app would make it,
    /// listen where iOS announces the change: the default centre. The test
    /// above hands in a centre of its own, so it would stay green if the app's
    /// were wired elsewhere, and then a change of zone, language or 24-hour
    /// clock would never reach the kept formatters. Posting both here, in
    /// this process, does nothing but empty the formatters that are kept.
    func testTheAppsFormattersHearTheSystemsNotifications() {
        let letter = sunday(9, 14)
        for dates in [DisplayDates.shared, DisplayDates()] {
            let time = { dates.string(from: letter, format: "h:mm a", locale: self.posix,
                                      timeZone: self.utc) }
            XCTAssertEqual(time(), "9:14 AM")
            let kept = dates.built
            XCTAssertEqual(time(), "9:14 AM")
            XCTAssertEqual(dates.built, kept, "kept")

            NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
            XCTAssertEqual(time(), "9:14 AM")
            XCTAssertEqual(dates.built, kept + 1, "made again after the time zone changed")

            NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification,
                                            object: nil)
            XCTAssertEqual(time(), "9:14 AM")
            XCTAssertEqual(dates.built, kept + 2, "made again after the locale changed")
        }
    }

    private func fresh(_ format: String, _ locale: Locale, _ zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter
    }

    /// The list timestamp exactly as it was written before the formatters
    /// were kept, with the day taken from `now` rather than the clock, and
    /// the locale and zone given rather than the iPad's.
    private func previousList(_ date: Date, now: Date, _ locale: Locale, _ zone: TimeZone) -> String {
        var cal = Calendar.current
        cal.timeZone = zone
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = zone
        if cal.isDate(date, inSameDayAs: now) {
            f.dateFormat = "h:mm a"
        } else if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: y) {
            return "Yesterday"
        } else if let week = cal.date(byAdding: .day, value: -6, to: now), date > week {
            f.dateFormat = "EEEE"
        } else {
            f.dateFormat = "dd/MM/yy"
        }
        return f.string(from: date)
    }

    private func previousDetail(_ date: Date, now: Date, _ locale: Locale, _ zone: TimeZone) -> String {
        var cal = Calendar.current
        cal.timeZone = zone
        let time = fresh("h:mm a", locale, zone)
        if cal.isDate(date, inSameDayAs: now) { return "Today at " + time.string(from: date) }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: y) {
            return "Yesterday at " + time.string(from: date)
        }
        return fresh("d MMMM yyyy 'at' h:mm a", locale, zone).string(from: date)
    }

    /// Word for word what a formatter built afresh writes, across the days
    /// either side of midnight, zones with half- and three-quarter-hour
    /// offsets, and languages with other digits, other day names and
    /// another calendar's year, asked for in turn so the kept formatters
    /// are made again between them.
    func testKeptFormattersWriteWhatFreshOnesWrite() {
        let now = sunday(0, 20, plusDays: 1)
        var letters: [Date] = []
        for hours in stride(from: -26, through: 2, by: 1) {
            letters.append(now.addingTimeInterval(Double(hours) * 3_600))
        }
        for days in [3, 5, 6, 7, 8, 40, 400] {
            letters.append(now.addingTimeInterval(-Double(days) * 86_400 + 1_234))
        }
        let zones = ["UTC", "America/New_York", "Asia/Kolkata", "Pacific/Chatham"]
            .map { TimeZone(identifier: $0)! }
        let locales = ["en_US", "en_GB", "fr_FR", "ar_EG", "th_TH"].map(Locale.init(identifier:))

        for locale in locales {
            for zone in zones {
                for letter in letters {
                    let what = "\(letter) in \(zone.identifier), \(locale.identifier)"
                    XCTAssertEqual(MailFormat.listTimestamp(letter, now: now, locale: locale,
                                                            timeZone: zone),
                                   previousList(letter, now: now, locale, zone), what)
                    XCTAssertEqual(MailFormat.detailTimestamp(letter, now: now, locale: locale,
                                                              timeZone: zone),
                                   previousDetail(letter, now: now, locale, zone), what)
                }
            }
        }
    }

    /// Left to their defaults, the clock, the iPad's locale and its zone,
    /// they say what the code before them said, which read all three
    /// itself. Skipped in the instant either side of midnight, when the
    /// two sides could fairly disagree.
    func testTheDefaultsAreTheClockTheLocaleAndTheZone() {
        for ago: TimeInterval in [60, 86_400, 3 * 86_400, 30 * 86_400] {
            let before = Date()
            let letter = before.addingTimeInterval(-ago)
            let cal = Calendar.current
            let f = DateFormatter()
            let list: String
            if cal.isDateInToday(letter) {
                f.dateFormat = "h:mm a"
                list = f.string(from: letter)
            } else if cal.isDateInYesterday(letter) {
                list = "Yesterday"
            } else if let week = cal.date(byAdding: .day, value: -6, to: before), letter > week {
                f.dateFormat = "EEEE"
                list = f.string(from: letter)
            } else {
                f.dateFormat = "dd/MM/yy"
                list = f.string(from: letter)
            }
            let kept = MailFormat.listTimestamp(letter)
            guard cal.isDate(before, inSameDayAs: Date()) else { continue }
            XCTAssertEqual(kept, list, "\(ago) s ago")
        }
    }

    // MARK: - From several threads

    /// The kept formatters are shared, and a change of zone or locale can be
    /// announced on any thread while they are in use: each caller still
    /// gets its own zone's words. Without the lock, the formatters and the
    /// table that keeps them are changed under a caller mid-call.
    func testTheFormattersCanBeUsedFromSeveralThreadsAtOnce() {
        let center = NotificationCenter()
        let dates = DisplayDates(notifications: center)
        let letter = sunday(9, 14)
        let zones = [utc, tokyo, newYork]
        let expected = zones.map { fresh("h:mm a", posix, $0).string(from: letter) }
        let wrong = Wrong()

        DispatchQueue.concurrentPerform(iterations: 8) { thread in
            for i in 0..<100 {
                let z = (thread + i) % zones.count
                if i % 25 == 0 {
                    center.post(name: i % 50 == 0 ? .NSSystemTimeZoneDidChange
                                    : NSLocale.currentLocaleDidChangeNotification, object: nil)
                }
                let words = dates.string(from: letter, format: "h:mm a", locale: posix,
                                         timeZone: zones[z])
                _ = dates.day(of: letter, now: letter, locale: posix, timeZone: zones[z])
                if words != expected[z] { wrong.add("\(zones[z].identifier): \(words)") }
            }
        }
        XCTAssertEqual(wrong.all, [])
    }
}

private final class Wrong: @unchecked Sendable {
    private let lock = NSLock()
    private var found: [String] = []

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return found
    }

    func add(_ what: String) {
        lock.lock()
        found.append(what)
        lock.unlock()
    }
}
