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
    ///    exactly the mail he was pointing at. A jump gives some of its
    ///    dates in UTC on purpose, Gmail's days that his day falls across,
    ///    worked out from his midnight and not from the day picked
    ///    (`sentOnHisDay`, B-115).
    /// 3. **Quoted.** `date-text` may be bare, but a bare form leans on the
    ///    server's tokeniser for no gain.
    static func criteriaValue(for date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "dd-MMM-yyyy"
        return "\"\(f.string(from: date))\""
    }

    /// What a jump asks for, in the one hold of its page (B-115,
    /// `IMAPClient.PageSearch.lowestDated`): first every letter of the
    /// days that hold any of his day (`sentOnHisDay`), with their dates,
    /// the lowest UID of those dated within his day deciding; only if
    /// there are none, the letters after his day within two days of it,
    /// then four, and so on, doubling (`sentAfterHisDay`), the first to
    /// match anything deciding by its lowest UID and the rest not asked;
    /// and last every letter after his day, with no end.
    ///
    /// **Why not the one SEARCH with no end.** Of what a SEARCH matches the
    /// jump keeps the lowest UID (`PageWindow.anchor`), the letter that came
    /// into the folder first, which is the earliest dated only while the
    /// folder's letters came in the order they were written. Mail that
    /// came as it was sent does; a label does not, its UIDs going by when
    /// the label was put on, nor mail imported or copied in, nor a letter
    /// moved back into the Inbox. On the size test of 2026-10-23 the
    /// account's own letters, the lowest UIDs and dated 2026, matched every
    /// day asked back to 2011, and every jump landed on them at the foot of
    /// the folder. Each bounded SEARCH there matched a few hundred letters
    /// at most and Gmail answered it in 0.05 to 0.08 s, where the one with
    /// no end, matching up to 57,209, took up to 1.04 s.
    ///
    /// **Why his day by its dates.** Gmail counts a SEARCH's days from
    /// midnight UTC (B-058), not from his. West of Greenwich its day holds
    /// his evening before, from 8 pm in New York in summer, and in such a
    /// folder a letter of that evening can have the lowest UID of the day:
    /// taken, the landing moved up from it to the next letter above it on
    /// or after his day, which there can be of any year. East of Greenwich
    /// its day holds his next morning's first hours and misses his own. So
    /// the day's SEARCH asks for both of Gmail's days his day falls across,
    /// two days' letters but few, and their dates are fetched, as the list
    /// shows them; the jump opens at the lowest UID of those dated within
    /// his day (`hisDay`), whatever order the folder is in. The spans after
    /// it start at the first of Gmail's days that begins after his
    /// midnight, so nothing of the evening before is in them, nor anything
    /// of his day, the day's SEARCH having found none: every letter they
    /// match is dated after his day. Their letters' dates are not fetched,
    /// being many.
    ///
    /// **Bounded.** At most `spanSearches` SEARCHes before the one with no
    /// end, his day and spans to 2^14 days, some 44 years, and none
    /// reaching the day before which every letter matched arrived
    /// (`BEFORE`, a week after `now`): the SEARCH with no end is asked in
    /// its place, as after the widest. So a day with mail is one SEARCH and
    /// one FETCH of its letters' dates; a day after the newest letter is
    /// his day, a few spans and then the SEARCH with no end, which finds
    /// nothing, so the jump says what it said before; and no jump asks
    /// more than `spanSearches` + 1 SEARCHes. A day a week or more ahead,
    /// which the picker does not offer, is the SEARCH a jump asked before
    /// alone, every letter on or after the day (`sentOnOrAfter`).
    static func jump(from date: Date, now: Date, timeZone: TimeZone = .current) -> Jump {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hisDay = day(of: date, in: calendar)
        let arrivedBefore = calendar.date(byAdding: .day, value: arrivalSlack + 1, to: now) ?? now
        let reach = calendar.dateComponents([.day], from: hisDay.lowerBound,
                                            to: calendar.startOfDay(for: arrivedBefore)).day ?? 0
        guard reach > 1 else {
            return Jump(day: nil, hisDay: hisDay,
                        wider: [sentOnOrAfter(date, now: now, timeZone: timeZone)])
        }
        var wider: [String] = []
        var days = 2
        while days < reach, wider.count + 1 < spanSearches {
            wider.append(sentAfterHisDay(date, days: days, now: now, timeZone: timeZone))
            days *= 2
        }
        wider.append(sentAfterHisDay(date, days: nil, now: now, timeZone: timeZone))
        return Jump(day: sentOnHisDay(date, now: now, timeZone: timeZone), hisDay: hisDay,
                    wider: wider)
    }

    /// A jump's SEARCHes (`jump(from:now:timeZone:)`).
    struct Jump: Equatable {
        /// Every letter of Gmail's days that hold any of his day
        /// (`sentOnHisDay`), whose dates are fetched; nil for a day a week
        /// or more ahead, where it is not asked.
        var day: String?
        /// His day, from his midnight to his next: of `day`'s letters, the
        /// lowest UID of those dated within it is where the jump opens.
        var hisDay: Range<Date>
        /// Asked in turn only if none of `day`'s letters is dated within
        /// `hisDay`, the first to match anything deciding by its lowest
        /// UID: the spans after his day, and last the SEARCH with no end;
        /// or for a day a week or more ahead, every letter on or after the
        /// day alone.
        var wider: [String]

        /// As the page asks for them.
        var pageSearch: IMAPClient.PageSearch {
            guard let day else { return .lowestOfFirst(wider) }
            return .lowestDated(day, within: hisDay, wider: wider)
        }
    }

    /// How many SEARCHes a jump asks at most before the one with no end
    /// (`jump(from:now:timeZone:)`): his day, then spans of two days, four,
    /// to 2^14 days, some 44 years.
    static let spanSearches = 15

    /// Every letter of the days, as Gmail counts them from midnight UTC
    /// (B-058), that hold any of his day: `SENTSINCE` the one his midnight
    /// falls in and `SENTBEFORE` the one after that his day's last moment
    /// falls in. In New York the day and the next, which hold his evening
    /// before and most of his next day as well; in Tokyo the day before
    /// and the day, which hold most of his day before and his next
    /// morning; in London in winter the day alone. Arrived as
    /// `sentOnOrAfter` has it, no more than `arrivalSlack` days before his
    /// day and no later than a week after `now`.
    static func sentOnHisDay(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hisDay = day(of: date, in: calendar)
        let lastGmailDay = utcCalendar.startOfDay(for: hisDay.upperBound.addingTimeInterval(-1))
        let afterIt = utcCalendar.date(byAdding: .day, value: 1, to: lastGmailDay)
            ?? hisDay.upperBound
        return "SENTSINCE \(criteriaValue(for: hisDay.lowerBound, timeZone: utc)) "
            + "SENTBEFORE \(criteriaValue(for: afterIt, timeZone: utc)) "
            + arrival(around: date, now: now, calendar: calendar)
    }

    /// The letters after his day: `SENTSINCE` the day, as Gmail counts
    /// them from midnight UTC, that his next midnight falls in, and
    /// `SENTBEFORE` the day `days` after his, his calendar's date, or with
    /// no end for nil. That day of Gmail's begins after his own midnight
    /// and no later than his next, so a span matches nothing of his
    /// evening before and leaves out nothing after his day; what it could
    /// match of his day, the day's SEARCH (`sentOnHisDay`) has found none
    /// of before it is asked. Arrived as `sentOnOrAfter` has it.
    static func sentAfterHisDay(_ date: Date, days: Int?, now: Date,
                                timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let next = day(of: date, in: calendar).upperBound
        var words = "SENTSINCE \(criteriaValue(for: next, timeZone: utc)) "
        if let days {
            let end = calendar.date(byAdding: .day, value: days, to: date) ?? date
            words += "SENTBEFORE \(criteriaValue(for: end, timeZone: timeZone)) "
        }
        return words + arrival(around: date, now: now, calendar: calendar)
    }

    /// `date`'s day in `calendar`, from its midnight to the next.
    private static func day(of date: Date, in calendar: Calendar) -> Range<Date> {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        return start..<max(end, start.addingTimeInterval(1))
    }

    /// The zone Gmail counts a SEARCH's days in (B-058).
    private static let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }()

    /// Every letter dated on or after a day: the one SEARCH a jump asked
    /// before B-115, which is now asked only for a day a week or more
    /// ahead (`jump(from:now:timeZone:)`). What it says of the keys holds
    /// for every SEARCH a jump asks.
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
    /// good, and nothing on the iPad could clear it. The day's SEARCH and
    /// the spans (`sentOnHisDay`, `sentAfterHisDay`) match it only once
    /// they reach 2037, but the one with no end is still asked after them.
    /// So every SEARCH a jump asks also asks that the letter arrived no
    /// more than `arrivalSlack` days before the day (`SINCE`,
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
    /// `sentOnHisDay`, `sentAfterHisDay`): a sender's clock a week fast is
    /// wrong, but its letter is still found. A Date further ahead of its
    /// arrival is a letter dated wrong.
    static let arrivalSlack = 7

    /// `June 20` / `June 20, 2025` with his US region, `20 June` / `20 June
    /// 2025` with a British one: how the jump reports where it landed, in
    /// the locale's own order from a template, as every date shown is
    /// (B-119).
    ///
    /// The year appears only when it is not the current one, because "June
    /// 20, 2026" on a day in 2026 is three words where two would do, and
    /// its absence is the fastest way to say "this year". `locale` is the
    /// iPad's unless a test hands in another.
    static func spokenDay(_ date: Date, now: Date = Date(),
                          calendar: Calendar = .current, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: date)
            == calendar.component(.year, from: now)
        f.setLocalizedDateFormatFromTemplate(sameYear ? "dMMMM" : "dMMMMy")
        return f.string(from: date)
    }
}
