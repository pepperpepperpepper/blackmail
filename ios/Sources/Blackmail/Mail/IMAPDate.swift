import Foundation

/// Dates as IMAP wants to read them, and as he wants to read them.
///
/// Separated from the repository so both halves are testable without a
/// server. The wire half has three ways to be quietly wrong — the wrong
/// month abbreviation, the wrong day either side of midnight, and the wrong
/// search key — and none of them fails loudly: they return the wrong mail,
/// or no mail, and look exactly like an empty mailbox.
enum IMAPDate {

    /// `20-Jun-2026`, quoted, ready to follow SENTSINCE or SINCE.
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

    /// The SEARCHes a jump asks in turn for the letter it opens at, the
    /// first to match anything deciding, the rest not asked (B-115,
    /// `IMAPClient.PageSearch.lowestOfFirst`): the letters dated within the
    /// day itself (`sentWithin`, one day); only if there are none, within
    /// the two days from it, then the four, and so on, doubling; and last
    /// every letter dated on or after the day (`sentOnOrAfter`), the one
    /// SEARCH a jump asked before.
    ///
    /// **Why not that one alone.** Of what the SEARCH matches the jump keeps
    /// the lowest UID (`PageWindow.anchor`), the letter that came into the
    /// folder first, which is the earliest dated only while the folder's
    /// letters came in the order they were written. Mail that came as it
    /// was sent does; a label does not, its UIDs going by when the label
    /// was put on, nor mail imported or copied in, nor a letter moved back
    /// into the Inbox. On the size test of 2026-10-23 the account's own
    /// letters, the lowest UIDs and dated 2026, matched every day asked
    /// back to 2011, and every jump landed on them at the foot of the
    /// folder. Bounded to the day, the lowest UID is one of that day's
    /// letters however the folder is ordered; widened, one of the first
    /// span's that has any, which with nothing in its first half is a
    /// letter of its second. Each bounded SEARCH there matched a few
    /// hundred letters at most and Gmail answered it in 0.05 to 0.08 s,
    /// where the one with no end, matching up to 57,209, took up to 1.04 s.
    ///
    /// **Bounded.** At most `spanSearches` spans, one day to 2^14 days, some
    /// 44 years, and none reaching the day before which every letter
    /// matched arrived (`BEFORE`, a week after `now`): the SEARCH with no
    /// end is asked in its place, as after the widest. So a day with mail
    /// is one SEARCH, as before; a day after the newest letter is a few
    /// spans and then the SEARCH a jump always asked, which says what it
    /// said; and no jump asks more than `spanSearches` + 1, for a day long
    /// before any mail.
    static func jumpSearches(from date: Date, now: Date, timeZone: TimeZone = .current) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let arrivedBefore = calendar.date(byAdding: .day, value: arrivalSlack + 1, to: now) ?? now
        let reach = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                            to: calendar.startOfDay(for: arrivedBefore)).day ?? 0
        var searches: [String] = []
        var days = 1
        while days < reach, searches.count < spanSearches {
            searches.append(sentWithin(date, days: days, now: now, timeZone: timeZone))
            days *= 2
        }
        searches.append(sentOnOrAfter(date, now: now, timeZone: timeZone))
        return searches
    }

    /// How many spans a jump asks for at most before the SEARCH with no end
    /// (`jumpSearches`): one day, two, four, to 2^14 days, some 44 years.
    static let spanSearches = 15

    /// The letters dated within the `days` from `date`'s day, that day the
    /// first: `SENTSINCE` it and `SENTBEFORE` the day `days` after it, his
    /// calendar's dates, which Gmail counts from midnight UTC as it does
    /// `SENTSINCE` alone (B-058, `PageWindow.landing`); and arrived as
    /// `sentOnOrAfter` has it, no more than `arrivalSlack` days before the
    /// day and no later than a week after `now`.
    static func sentWithin(_ date: Date, days: Int, now: Date,
                           timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let end = calendar.date(byAdding: .day, value: days, to: date) ?? date
        return "SENTSINCE \(criteriaValue(for: date, timeZone: timeZone)) "
            + "SENTBEFORE \(criteriaValue(for: end, timeZone: timeZone)) "
            + arrival(around: date, now: now, calendar: calendar)
    }

    /// Every letter dated on or after a day: the last of a jump's SEARCHes
    /// (`jumpSearches`), asked when no span from the day found one.
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
    ///
    /// **Bounded by arrival as well (B-058).** The jump's window is fetched
    /// around the lowest UID matched (`PageWindow.anchor`), and lands on
    /// it but for the hours his day and Gmail's differ (`PageWindow.landing`).
    /// A letter whose Date is wrong into the future, one that arrived in
    /// 2014 saying 2037, matches every day before 2037 by its Date, and
    /// arrived before the letters it is matched with, so has the lowest UID
    /// among them: every jump this SEARCH decided would land on it, for
    /// good, and nothing on the iPad could clear it. A span (`sentWithin`)
    /// matches it only once it reaches 2037, but this SEARCH is still asked
    /// after them. So it, and every span, also asks that the letter arrived
    /// no more than `arrivalSlack` days before the day (`SINCE`,
    /// INTERNALDATE): a letter cannot reach Gmail before it is written, so
    /// one sent on or after the day arrives on or after it, give or take a
    /// sender's clock running fast, which the slack is for. Mail delayed in
    /// arriving still matches, however late. One string, so no round trip
    /// more.
    ///
    /// **And not arrived in the future (B-058).** Whatever copies mail into
    /// Gmail, by APPEND or by Gmail's import, may set when it arrived from
    /// its Date, so a letter dated 2037 copied in years ago arrived, as far
    /// as Gmail says, in 2037, and passes the bound above for every day
    /// before then. So the SEARCH also asks that it arrived no later than a
    /// week after `now` (`BEFORE` the day after that): it leaves such a
    /// letter out for as long as its date is still ahead, and nothing that
    /// has really arrived, but with the iPad's clock more than a week slow.
    static func sentOnOrAfter(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return "SENTSINCE \(criteriaValue(for: date, timeZone: timeZone)) "
            + arrival(around: date, now: now, calendar: calendar)
    }

    /// When a letter a jump finds may have arrived (B-058): no more than
    /// `arrivalSlack` days before the day asked for, and before the day
    /// after a week from `now`, both in `calendar`'s days.
    private static func arrival(around date: Date, now: Date, calendar: Calendar) -> String {
        let arrivedFrom = calendar.date(byAdding: .day, value: -arrivalSlack, to: date) ?? date
        let arrivedBefore = calendar.date(byAdding: .day, value: arrivalSlack + 1, to: now) ?? now
        return "SINCE \(criteriaValue(for: arrivedFrom, timeZone: calendar.timeZone)) "
            + "BEFORE \(criteriaValue(for: arrivedBefore, timeZone: calendar.timeZone))"
    }

    /// How many days before the day asked for a letter dated on or after
    /// it may have arrived and still be found by a jump (`sentOnOrAfter`,
    /// `sentWithin`): a sender's clock a week fast is wrong, but its letter
    /// is still found. A Date further ahead of its arrival is a letter
    /// dated wrong.
    static let arrivalSlack = 7

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
