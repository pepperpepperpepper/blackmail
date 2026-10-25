import Foundation

/// The warning before the app stops opening (D-004 item 3, B-137): in the
/// last thirty days, once a day, an alert he dismisses with OK, saying in
/// plain words the day it stops and what to use after it.
///
/// Its words are new on his screen and wait for the owner's approval (TODO,
/// "The new words on his screen"). Mail has nothing like it to copy: Mail
/// never stops opening. Apple Mail stays on his iPad with his account in it
/// (the default), so Mail is what he is told to use.
///
/// The day rules are here, on the host; when it is put up is the screens'
/// (`RootViewController.warnOfExpiryIfDue`): only with nothing over the
/// mail, so never over a letter he is writing, an alert or a sheet; never
/// under his finger on the list (B-103) or while a letter is printed; and
/// never before the launch's first page has been tried.
struct ExpiryWarning {

    /// From the thirtieth day before the day it stops, in the iPad's
    /// calendar and zone, up to the instant it stops.
    static let days = 30

    /// When it was last put up, in `UserDefaults`.
    static let key = "blackmail.expiryWarningShown"

    /// What the profile said (`AppExpiry`).
    let found: AppExpiry.Found
    let defaults: UserDefaults

    /// The app's: its own profile, read once a launch, and the iPad's
    /// defaults.
    static var app: ExpiryWarning { ExpiryWarning(found: AppExpiry.app, defaults: .standard) }

    /// The words to put up at `now`, or nil when there is nothing to say:
    /// no profile, not yet the last thirty days, already said today, or
    /// past the instant, when the words would be untrue.
    func words(at now: Date, locale: Locale = .current,
               timeZone: TimeZone = .current) -> String? {
        guard case .stops(let stops) = found else { return nil }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        guard Self.isDue(stops: stops, now: now,
                         lastShown: defaults.object(forKey: Self.key) as? Date,
                         calendar: calendar) else { return nil }
        return Self.words(stops: stops, locale: locale, timeZone: timeZone)
    }

    /// It has been put up at `now`, or OK tapped then: not again that day.
    /// Said at both, so a warning left up past midnight is not put up again
    /// on the day he reads it.
    func shown(at now: Date) {
        defaults.set(now, forKey: Self.key)
    }

    /// Whether to say it at `now`: before the instant it stops, on or after
    /// the thirtieth day before that day, and not on the day it was last
    /// said. A day is the calendar's, in its zone: once a day is once from
    /// midnight to midnight where he is.
    static func isDue(stops: Date, now: Date, lastShown: Date?, calendar: Calendar) -> Bool {
        guard now < stops,
              let left = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                                 to: calendar.startOfDay(for: stops)).day,
              left <= days
        else { return false }
        if let lastShown, calendar.isDate(lastShown, inSameDayAs: now) { return false }
        return true
    }

    /// The words, the day written as the iPad writes a long date (B-119):
    /// with his US region "September 18, 2027".
    static func words(stops: Date, locale: Locale, timeZone: TimeZone) -> String {
        let day = DisplayDates.shared.string(from: stops, .longDate, locale: locale,
                                             timeZone: timeZone)
        return "This app will stop opening on \(day). After that, use Mail."
    }
}
