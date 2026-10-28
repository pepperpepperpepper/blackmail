import Foundation

/// A folder's letters in the order Mail lists them (B-178): by when the
/// server took each one, its INTERNALDATE, the newest first, and by UID
/// where two came in the same second, the higher first, as a conversation's
/// letters already go (`MessageThread.byArrival`, B-084).
///
/// The list went by UID, the order the letters were put in the folder. A
/// letter put in out of turn, moved back to the Inbox, brought back by an
/// Undo or copied in by another program, went to the top of the list, with
/// today's mail, whatever its date; Mail's list puts it among the letters of
/// its own day (the comparison of 2026-10-27, C-02c: a letter of 14 June
/// 2025 put in the test account's Notes last, at the top of Blackmail's
/// list and the 37th row of Mail's, among Notes' own letters of that time).
///
/// **By INTERNALDATE, not the Date header.** Mail on iPadOS sorts by date
/// received and has no setting for it (Apple's Mac Mail offers "Date
/// Received" and "Date Sent"; the iPad's has neither, and is reported in
/// Apple's own forums to go by when the letter arrived). In the comparison
/// the two dates of the letter were the same, so it does not settle which;
/// the row still shows the Date header, as Mail's does (C-02d, the same).
///
/// **Gmail cannot sort.** It has no IMAP SORT, so the dates are asked for:
/// `UID FETCH … (UID INTERNALDATE)`, a few dozen bytes a letter. A folder of
/// `wholeFolderAtMost` letters or fewer has every date asked for at once.
/// His Inbox is 60,000 to 150,000 letters and his All Mail 250,000 to
/// 400,000, megabytes of dates for a page of fifty, so a larger folder is
/// dated a span at a time (`known`): every letter that arrived within it has
/// its date, found by `UID SEARCH SINCE … BEFORE …` (INTERNALDATE, by day),
/// and only the letters within it are ordered and listed. Paging down past
/// it, or up past it after a date jump, widens it first.
///
/// How far to widen it is found without guessing, mostly: the dates of a
/// few letters known to be older than the span (`candidates`) are asked
/// for, and the `count`-th newest of them is a date at or before which the
/// `count` letters next below the span are all to be found, since they are
/// the newest of every letter older than the span, these among them. Gmail
/// counts a SEARCH's days from midnight UTC (B-058); each SEARCH asks a day
/// more either side, and only the whole UTC days inside are taken as known.
///
/// Pure arithmetic over what the server answers, `Asking` doing the asking,
/// so the suite runs every step without a server.
struct ArrivalOrder: Equatable, Sendable {

    /// What the order asks the server, inside the hold of the connection
    /// that widens it (`IMAPClient.page`, `IMAPClient.arranging`).
    struct Asking: Sendable {
        /// The INTERNALDATE of each of `uids` the server has, by UID; one
        /// it leaves out has gone from the folder. Nil if it refused.
        let arrivals: @Sendable ([UInt32]) async throws -> [UInt32: Date]?
        /// The UIDs a SEARCH's criteria match. Nil if it refused.
        let matching: @Sendable (String) async throws -> [UInt32]?
    }

    /// A folder this small, or a span with this few undated letters left,
    /// has every date asked for in one FETCH, about 140 KB.
    static let wholeFolderAtMost = 2_000

    /// The fewest letters whose dates are asked for to find how far to
    /// widen (`candidates`).
    static let candidatesAtLeast = 100

    /// How far a widening goes when the candidates do not say, doubling
    /// each time it is not enough.
    static let firstWidening: TimeInterval = 7 * 86_400

    /// Arrivals before this are all taken in one SEARCH, with no beginning.
    static let earliest = Date(timeIntervalSince1970: 631_152_000)   // 1 Jan 1990 UTC

    /// The most widenings one page asks for.
    static let mostSteps = 24

    let validity: UInt32
    /// Every UID the folder's SEARCH ALL found, ascending.
    let listing: [UInt32]
    /// The INTERNALDATE of each letter asked for in this launch, or brought
    /// with its row, by UID; kept for a letter gone from the folder too,
    /// which a page can still be asked from below.
    private(set) var arrivals: [UInt32: Date] = [:]
    /// Letters of `listing` the server gave no date for: gone since, or
    /// left out of an answer it did not give whole (a chunk refused, or
    /// Gmail's "Some messages could not be FETCHed"). Not listed in this
    /// listing; owed again by the next that still has them.
    private(set) var missing: Set<UInt32> = []
    /// The arrivals within which every letter of the folder has its date:
    /// `distantPast` at the bottom when every older one has, `distantFuture`
    /// at the top when every newer one has. Nil until a span is known.
    private(set) var known: Range<Date>?
    /// Letters of `listing` that came after the listing this one carries
    /// on from, whose dates are to be asked for before `known` holds again.
    private(set) var owed: [UInt32] = []
    /// Letters owed whose row the page's FETCH did not bring
    /// (`settleOwed(from:)`): owed again by the next listing.
    private(set) var unanswered: [UInt32] = []
    /// The letters of `listing` that arrived within `known`, the oldest
    /// first, as `PageWindow` walks them.
    private(set) var ascending: [UInt32] = []

    init(validity: UInt32, listing: [UInt32]) {
        self.validity = validity
        self.listing = listing.sorted()
    }

    /// A listing of the same folder afresh, carrying on from `previous`
    /// where it is the same numbering: the dates already asked for, and
    /// the span, once the letters new to the folder since have theirs.
    /// The letters the last one was given no date or row for and that are
    /// still in the folder are owed again with them: the span carried
    /// covers them, and nothing else would ask for their dates, so they
    /// would stay off the list for the rest of the launch.
    init(validity: UInt32, listing: [UInt32], carrying previous: ArrivalOrder?) {
        self.init(validity: validity, listing: listing)
        guard let previous, previous.validity == validity else { return }
        arrivals = previous.arrivals
        let before = Set(previous.listing)
        let again = Set(previous.unanswered).union(previous.missing)
        owed = self.listing.filter { !before.contains($0) || again.contains($0) }
        known = previous.known
        rebuild()
    }

    // MARK: - Where a letter stands

    /// Whether `a`, arrived `da`, comes before `b`, arrived `db`, in the
    /// oldest-first order: the earlier, or in the same second the lower UID.
    static func isOlder(_ a: UInt32, _ da: Date, than b: UInt32, _ db: Date) -> Bool {
        da != db ? da < db : a < b
    }

    var completeBelow: Bool { known?.lowerBound == .distantPast }
    var completeAbove: Bool { known?.upperBound == .distantFuture }

    func arrival(of uid: UInt32) -> Date? { arrivals[uid] }

    /// The rows the order holds older than `cursor`, newest first, up to
    /// `limit`; nil for the top. A cursor not among them, a letter gone or
    /// outside the span, goes by its date.
    func older(than cursor: UInt32?, limit: Int) -> [UInt32] {
        guard limit > 0 else { return [] }
        let end = cursor.map(lowerIndex) ?? ascending.count
        return Array(ascending[max(0, end - limit)..<end].reversed())
    }

    /// The `limit` rows next newer than `cursor`, newest first.
    func newer(than cursor: UInt32, limit: Int) -> [UInt32] {
        guard limit > 0 else { return [] }
        let start = upperIndex(cursor)
        return Array(ascending[start..<min(ascending.count, start + limit)].reversed())
    }

    /// How many rows the order holds below `cursor`, or in all for nil.
    func rows(below cursor: UInt32?) -> Int { cursor.map(lowerIndex) ?? ascending.count }

    /// How many above it.
    func rows(above cursor: UInt32) -> Int { ascending.count - upperIndex(cursor) }

    /// The index in `ascending` of the first row not older than `cursor`.
    /// A cursor with no date, a letter gone before it was dated, stands
    /// just above the letter with the next lower UID, as it did while the
    /// list went by UID.
    private func lowerIndex(_ cursor: UInt32) -> Int {
        if let at = ascending.firstIndex(of: cursor) { return at }
        guard let date = arrivals[cursor] else {
            let next = ascending.filter { $0 < cursor }.max()
            return next.flatMap { ascending.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        }
        return ascending.firstIndex { uid in
            guard let d = arrivals[uid] else { return false }
            return !Self.isOlder(uid, d, than: cursor, date)
        } ?? ascending.count
    }

    /// The index in `ascending` of the first row newer than `cursor`; for a
    /// cursor with no date, the letter with the next higher UID.
    private func upperIndex(_ cursor: UInt32) -> Int {
        if let at = ascending.firstIndex(of: cursor) { return at + 1 }
        guard let date = arrivals[cursor] else {
            let next = ascending.filter { $0 > cursor }.min()
            return next.flatMap { ascending.firstIndex(of: $0) } ?? ascending.count
        }
        return ascending.firstIndex { uid in
            guard let d = arrivals[uid] else { return false }
            return Self.isOlder(cursor, date, than: uid, d)
        } ?? ascending.count
    }

    /// Whether `count` rows below `cursor` are placed already, or every
    /// row below it is: nothing to ask before the page.
    func reaches(below cursor: UInt32, count: Int) -> Bool {
        guard owed.isEmpty, known != nil, arrivals[cursor] != nil else { return false }
        return completeBelow || rows(below: cursor) >= count
    }

    /// The same above it.
    func reaches(above cursor: UInt32, count: Int) -> Bool {
        guard owed.isEmpty, known != nil, arrivals[cursor] != nil else { return false }
        return completeAbove || rows(above: cursor) >= count
    }

    /// The letters to fetch for the first page of a listing from the top
    /// that carries on from the last (`init(validity:listing:carrying:)`),
    /// when the letters new to the folder since are few: those, and the
    /// `limit` newest the order holds, so the page's own FETCH brings the
    /// new letters' dates with their rows and nothing more is asked
    /// (`settleOwed(from:)`). A Refresh sends the commands it sent before
    /// B-178; its FETCH asks for the new letters on top of the `limit`.
    /// Nil when the order is to be widened first: nothing carried, a span
    /// that does not reach the newest letter, or many new letters.
    func foldedPage(limit: Int) -> [UInt32]? {
        guard let known, known.upperBound == .distantFuture, !owed.isEmpty,
              owed.count <= max(limit, 1) else { return nil }
        let owing = Set(owed)
        var held: [(UInt32, Date)] = []
        for (uid, date) in arrivals where known.contains(date) && listed(uid) && !owing.contains(uid) {
            held.append((uid, date))
        }
        held.sort { Self.isOlder($1.0, $1.1, than: $0.0, $0.1) }
        return owed + held.prefix(limit).map(\.0)
    }

    /// The dates of the letters new to the folder, as the page's FETCH
    /// brought them (`foldedPage`). One it brought no row for, as a FETCH
    /// that leaves out a letter it gives no ENVELOPE for (`IMAPClient.
    /// ordered`), is not listed now, and is owed again by the next listing,
    /// which may bring its line.
    mutating func settleOwed(from dates: [UInt32: Date]) {
        guard !owed.isEmpty else { return }
        for uid in owed {
            if let date = dates[uid] { arrivals[uid] = date } else { unanswered.append(uid) }
        }
        owed = []
        rebuild()
    }

    /// For a listing from the top: a span carried on from a date jump's,
    /// which does not reach the newest letter, is let go; the dates stay.
    mutating func fromTheTop() {
        guard let known, known.upperBound != .distantFuture else { return }
        self.known = nil
        rebuild()
    }

    // MARK: - Learning

    /// The answer to a FETCH of `asked`'s dates.
    private mutating func learn(asked: [UInt32], answered: [UInt32: Date]) {
        arrivals.merge(answered) { _, new in new }
        for uid in asked where answered[uid] == nil { missing.insert(uid) }
    }

    private mutating func rebuild() {
        guard let known, owed.isEmpty else {
            ascending = []
            return
        }
        var rows: [(UInt32, Date)] = []
        for (uid, date) in arrivals where known.contains(date) && !missing.contains(uid)
            && listed(uid) {
            rows.append((uid, date))
        }
        rows.sort { Self.isOlder($0.0, $0.1, than: $1.0, $1.1) }
        ascending = rows.map(\.0)
    }

    /// Whether `uid` is in `listing`.
    func listed(_ uid: UInt32) -> Bool {
        var low = 0
        var high = listing.count
        while low < high {
            let mid = (low + high) / 2
            if listing[mid] < uid { low = mid + 1 } else { high = mid }
        }
        return low < listing.count && listing[low] == uid
    }

    // MARK: - Asking

    private mutating func date(_ uids: [UInt32], _ asking: Asking) async throws {
        guard !uids.isEmpty else { return }
        guard let answered = try await asking.arrivals(uids) else { throw MailError.cannotConnect }
        learn(asked: uids, answered: answered)
    }

    /// The letters new to the folder since the listing carried on from,
    /// dated, so the span holds again.
    private mutating func settleOwed(_ asking: Asking) async throws {
        guard !owed.isEmpty else { return }
        let asked = owed
        try await date(asked, asking)
        owed = []
        rebuild()
    }

    /// The letters of `listing` with no date asked for yet.
    private var undated: [UInt32] {
        listing.filter { arrivals[$0] == nil && !missing.contains($0) }
    }

    /// Dates every letter left, when few enough are, and knows the whole
    /// folder. True when it did.
    private mutating func dateEverythingIfFew(_ asking: Asking) async throws -> Bool {
        let left = undated
        guard left.count <= Self.wholeFolderAtMost else { return false }
        try await date(left, asking)
        known = Date.distantPast..<Date.distantFuture
        rebuild()
        return true
    }

    /// The span widened down until it holds `count` rows below `cursor`,
    /// or every row below it; nil for the top of the folder.
    mutating func reachDown(below cursor: UInt32?, count: Int, asking: Asking) async throws {
        try await settleOwed(asking)
        var widening = Self.firstWidening
        for _ in 0..<Self.mostSteps {
            if completeBelow { return }
            let short = count - rows(below: cursor)
            if short <= 0, known != nil { return }
            if try await dateEverythingIfFew(asking) { return }
            let lower = known?.lowerBound ?? .distantFuture
            // The letters that came into the folder before the span's
            // first, the newest of them, which are mostly those that arrived
            // just before it.
            let left = undated
            let floor = ascending.min() ?? .max
            let pool = left.filter { $0 < floor }
            let want = max(Self.candidatesAtLeast, 2 * max(short, 1))
            try await date(Array((pool.isEmpty ? left : pool).suffix(want)), asking)

            let below = arrivals.compactMap { uid, date -> Date? in
                date < lower && listed(uid) && !missing.contains(uid) ? date : nil
            }.sorted(by: >)
            let need = max(short, 1)
            let bound: Date
            if below.count >= need {
                bound = below[need - 1]
            } else if let oldest = below.last {
                bound = min(oldest, lower).addingTimeInterval(-widening)
                widening *= 2
            } else {
                continue
            }
            let from = Self.dayStart(bound)
            var criteria: String
            let newLower: Date
            if from <= Self.earliest {
                criteria = lower == .distantFuture ? "ALL" : ""
                newLower = .distantPast
            } else {
                criteria = "SINCE \(Self.day(from, plus: -1))"
                newLower = from
            }
            if lower != .distantFuture {
                criteria += (criteria.isEmpty ? "" : " ") + "BEFORE \(Self.day(Self.dayStart(lower), plus: 1))"
            }
            guard let matched = try await asking.matching(criteria) else {
                throw MailError.cannotConnect
            }
            try await date(matched.filter { listed($0) && arrivals[$0] == nil && !missing.contains($0) },
                           asking)
            known = newLower..<(known?.upperBound ?? .distantFuture)
            rebuild()
        }
    }

    /// The span widened up until it holds `count` rows above `cursor`, or
    /// every row above it, `now` the iPad's clock: after a date jump.
    mutating func reachUp(above cursor: UInt32, count: Int, now: Date,
                          asking: Asking) async throws {
        try await settleOwed(asking)
        var widening = Self.firstWidening
        for _ in 0..<Self.mostSteps {
            guard let upper = known?.upperBound, upper != .distantFuture else { return }
            let short = count - rows(above: cursor)
            if short <= 0 { return }
            if try await dateEverythingIfFew(asking) { return }
            // The letters that came into the folder after the span's first,
            // which are mostly those that arrived after it; a letter put in
            // out of turn has a UID far above its time, and is not where
            // the next arrivals are looked for.
            let left = undated
            let first = ascending.min() ?? 0
            let pool = left.filter { $0 > first }
            let want = max(Self.candidatesAtLeast, 2 * short)
            try await date(Array((pool.isEmpty ? left : pool).prefix(want)), asking)

            let above = arrivals.compactMap { uid, date -> Date? in
                date >= upper && listed(uid) && !missing.contains(uid) ? date : nil
            }.sorted()
            let bound: Date
            if above.count >= short {
                bound = above[short - 1]
            } else {
                bound = max(above.last ?? upper, upper).addingTimeInterval(widening)
                widening *= 2
            }
            let to = Self.dayStart(bound).addingTimeInterval(86_400)
            var criteria = "SINCE \(Self.day(Self.dayStart(upper), plus: -1))"
            let newUpper: Date
            if to > now.addingTimeInterval(Double(IMAPDate.arrivalSlack + 1) * 86_400) {
                newUpper = .distantFuture
            } else {
                criteria += " BEFORE \(Self.day(to, plus: 1))"
                newUpper = to
            }
            guard let matched = try await asking.matching(criteria) else {
                throw MailError.cannotConnect
            }
            try await date(matched.filter { listed($0) && arrivals[$0] == nil && !missing.contains($0) },
                           asking)
            known = (known?.lowerBound ?? .distantPast)..<newUpper
            rebuild()
        }
    }

    /// A span around `uid`'s arrival, its UTC day, in place of the one
    /// known, unless that holds it already: where a date jump lands.
    /// False when the server has no date for it.
    mutating func reach(_ uid: UInt32, asking: Asking) async throws -> Bool {
        try await settleOwed(asking)
        if let arrived = arrivals[uid], let known, known.contains(arrived) { return true }
        if try await dateEverythingIfFew(asking) { return arrivals[uid] != nil && !missing.contains(uid) }
        if arrivals[uid] == nil, !missing.contains(uid) { try await date([uid], asking) }
        guard let arrived = arrivals[uid], !missing.contains(uid) else { return false }
        if let known, known.contains(arrived) { return true }
        let day = Self.dayStart(arrived)
        let criteria = "SINCE \(Self.day(day, plus: -1)) BEFORE \(Self.day(day, plus: 2))"
        guard let matched = try await asking.matching(criteria) else { throw MailError.cannotConnect }
        try await date(matched.filter { listed($0) && arrivals[$0] == nil && !missing.contains($0) },
                       asking)
        known = day..<day.addingTimeInterval(86_400)
        rebuild()
        return true
    }

    // MARK: - Days

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// Midnight UTC of `date`'s day, as Gmail counts a SEARCH's days.
    static func dayStart(_ date: Date) -> Date { utc.startOfDay(for: date) }

    /// The day `days` after `day`, as a SEARCH's date.
    static func day(_ day: Date, plus days: Int) -> String {
        let moved = utc.date(byAdding: .day, value: days, to: day) ?? day
        return IMAPDate.criteriaValue(for: moved, timeZone: utc.timeZone)
    }
}
