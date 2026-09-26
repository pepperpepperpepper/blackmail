import Foundation

/// Dates as IMAP wants to read them, and as he wants to read them.
///
/// Separated from the repository so both halves are testable without a
/// server. The wire half has three ways to be quietly wrong — the wrong
/// month abbreviation, the wrong day either side of midnight, and the wrong
/// search key — and none of them fails loudly: they return the wrong mail,
/// or no mail, and look exactly like an empty mailbox.
enum IMAPDate {

    /// `20-Jun-2026`, quoted, ready to follow SENTSINCE.
    ///
    /// Three decisions, each of which has a wrong answer that still compiles:
    ///
    /// 1. **`en_US_POSIX`.** RFC 3501 spells the month in English
    ///    abbreviations and nothing else. On a device set to French,
    ///    `MMM` renders `juin`, and the server answers BAD — which this
    ///    app surfaces as "Can't connect to mail server." The iPad is in
    ///    English today; that is not a reason to let the locale decide.
    /// 2. **Day precision, local calendar.** IMAP dates carry no time and
    ///    no zone. Formatting in UTC from a device west of Greenwich turns
    ///    an evening in June into the 21st, so the jump lands a day late on
    ///    exactly the mail he was pointing at.
    /// 3. **Quoted.** `date-text` may be bare, but a bare form leans on the
    ///    server's tokeniser for no gain.
    static func criteriaValue(for date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "dd-MMM-yyyy"
        return "\"\(f.string(from: date))\""
    }

    /// The search that finds the first letter of a day.
    ///
    /// **SENTSINCE, not SINCE.** They are different dates and the difference
    /// is visible: SINCE tests INTERNALDATE, the moment the server took
    /// delivery, while the list rows show the envelope Date — what the
    /// sender's own clock said. Mail delayed overnight has two different
    /// dates, so jumping on INTERNALDATE would land him on a row whose
    /// visible date is not the one he asked for, which reads as the feature
    /// being broken rather than as a distinction between two timestamps.
    ///
    /// "SINCE" in IMAP means on-or-after, inclusive of the day itself, which
    /// is what "go to the 20th" means.
    static func sentOnOrAfter(_ date: Date, timeZone: TimeZone = .current) -> String {
        "SENTSINCE \(criteriaValue(for: date, timeZone: timeZone))"
    }

    /// `20 June` / `20 June 2025` — how the jump reports where it landed.
    ///
    /// The year appears only when it is not the current one, because "20
    /// June 2026" on a day in 2026 is three words where two would do, and
    /// its absence is the fastest way to say "this year".
    static func spokenDay(_ date: Date, now: Date = Date(),
                          calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: date)
            == calendar.component(.year, from: now)
        f.setLocalizedDateFormatFromTemplate(sameYear ? "dMMMM" : "dMMMMy")
        return f.string(from: date)
    }
}
