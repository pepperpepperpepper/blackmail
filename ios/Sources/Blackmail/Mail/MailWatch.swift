import Foundation

/// New mail while he has the app in front of him, without a tap (B-049).
///
/// Every half minute, one question on the one connection, in the background
/// line of its exchange gate: with the Inbox's list in front of him, a NOOP,
/// whose answer says what has arrived in the Inbox and gone from it; with
/// another folder, a STATUS of the Inbox, for its count beside its name.
/// Only when the NOOP says something has changed, or what the last check
/// found never reached the list (`searchOwed`), does a SEARCH follow, and a
/// FETCH of the new letters' summaries alone
/// (`IMAPMailRepository.news(in:known:searchingAnyway:)`).
///
/// Chosen over IMAP IDLE, on this connection or a second one, for what the
/// app already is. One connection is deliberate (PERFORMANCE.md, the single
/// exchange gate), and IDLE on it would put a DONE and its answer in front
/// of every tap, a read with no deadline where `TransportDeadline` bounds
/// every read, and a gate that has to break a command it did not start. A
/// second connection costs a second LOGIN at every return to the app,
/// doubles what a revoked password sends, and needs its own reconnects and
/// Gmail's end of IDLE after about half an hour. A NOOP is what the
/// connection already sends as B-024's probe, the warm-up and B-045's
/// catch-up; it waits behind nothing he taps, and costs a round trip of a
/// hundred bytes. The price is up to half a minute before a letter shows,
/// where IDLE would take seconds. Mail itself fetches a Gmail account on a
/// schedule rather than being told, unless set up otherwise.
///
/// Nothing runs while the app is in the background: `stop` as it goes,
/// `start` as it comes back, where the warm-up and the return to the Inbox
/// after a while away (`Sitting`) come first as before. Checks never
/// overlap: the next is half a minute after the last has finished, so work
/// he did not ask for cannot pile up on the connection behind a slow one.
///
/// On the main actor, with the list it feeds, which is where what it finds
/// is drawn. The screens are UIKit, so what it asks of them is
/// `MailWatchTarget`, and the host tests hand it one of their own.
@MainActor
final class MailWatch {

    /// Half a minute: a letter is on the list about fifteen seconds after
    /// it reaches Gmail on average, thirty at worst, where he asked for a
    /// minute or better. Twice the NOOPs of a minute, 120 an hour while the
    /// app is in front, each a hundred bytes each way; the screen being on
    /// costs far more than the radio does. And the connection is never quiet
    /// for the ninety seconds after which a write probes it first (B-024),
    /// nor for the half hour after which Gmail ends a session, so his taps
    /// meet a connection proven a moment ago, and a socket that dies in the
    /// quiet is found by a check rather than by the letter he opens.
    nonisolated static let interval: TimeInterval = 30

    /// How a check went, for the line under the list.
    enum Outcome: Equatable {
        /// The Inbox's list is up to date with the server, as of `at`.
        case listed(mailboxID: String, at: Date)
        /// The server answered, for the Inbox's count; no list was checked.
        case reached(at: Date)
        /// The check could not be made, with what a read of it would say.
        case failed(MailError, at: Date)
    }

    weak var target: MailWatchTarget?

    /// Whether the next check of the Inbox's list searches whatever its NOOP
    /// says: the last one's news never reached the list. The server tells a
    /// session of a letter once, on the first answer after it arrives, so a
    /// check whose SEARCH had gone and whose letters were then lost, to a
    /// FETCH refused, to the app going away with the check out, or to a list
    /// that had moved on, left every NOOP after it saying nothing had
    /// changed, and the letter off the list under "Updated Just Now" until
    /// another came. Set by any check of the list that fails or is stopped,
    /// since it cannot say how far it got; cleared once news is taken, or a
    /// search finds none. Costs a SEARCH at most, at the next check.
    private(set) var searchOwed = false

    private let repository: MailRepository
    private let interval: TimeInterval
    private let now: () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var loop: Task<Void, Never>?

    /// Checks finished since the watch was made. How a test knows one is
    /// over without sleeping on it.
    private(set) var checks = 0

    var isWatching: Bool { loop != nil }

    /// `now` and `sleep` are the real clock's; a test hands in one it moves.
    init(repository: MailRepository, interval: TimeInterval = MailWatch.interval,
         now: @escaping () -> Date = { Date() },
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
             try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
         }) {
        self.repository = repository
        self.interval = interval
        self.now = now
        self.sleep = sleep
    }

    /// Starts checking, the first check an interval from now. Does nothing
    /// if it is already running.
    func start() {
        guard loop == nil else { return }
        let interval = self.interval
        let sleep = self.sleep
        loop = Task { [weak self] in
            while true {
                do { try await sleep(interval) } catch { return }
                guard let self, !Task.isCancelled else { return }
                await self.check()
            }
        }
    }

    /// Stops, as the app goes into the background. A check under way is
    /// cancelled: the command it has on the wire is answered, as any is
    /// (`IMAPClient.beginExchange`), and nothing after it is sent; what it
    /// had found is searched for again at the first check after the return
    /// (`searchOwed`). Returns the checks it stopped, which a test waits for
    /// to know they are over.
    @discardableResult
    func stop() -> Task<Void, Never>? {
        let stopped = loop
        loop?.cancel()
        loop = nil
        return stopped
    }

    /// One check. With the Inbox's list in front of him, its news, handed to
    /// the list to show or hold, and the folder counts swept when it has
    /// told the list anything new; the sweep is the one the folder pane
    /// already merges (`SweepCoalescer`), so a burst of letters costs one or
    /// two. With another folder, the Inbox's unread count, and a sweep only
    /// when it is not what the folder pane says.
    func check() async {
        guard let target else { return }
        let outcome: Outcome
        do {
            if let inbox = target.watchedInbox {
                let news: FolderNews
                do {
                    news = try await repository.news(in: inbox.mailboxID, known: inbox.letters,
                                                     searchingAnyway: searchOwed)
                } catch {
                    searchOwed = true
                    throw error
                }
                // Owed until the list has taken it.
                searchOwed = !news.isEmpty
                try Task.checkCancellation()
                // Handed over when there is none too: what the list has held
                // may go on now. A finger lifted from a tap, which is no
                // drag, tells the list nothing, and letters held while it
                // rested there would wait for the next to arrive or a scroll.
                switch target.found(news, in: inbox.mailboxID) {
                case .new:
                    searchOwed = false
                    target.countsChanged()
                case .known:
                    searchOwed = false
                case .notTaken:
                    if !news.isEmpty { target.countsChanged() }
                }
                outcome = .listed(mailboxID: inbox.mailboxID, at: now())
            } else {
                let unread = try await repository.inboxUnread()
                try Task.checkCancellation()
                if let unread, unread != target.shownInboxUnread { target.countsChanged() }
                outcome = .reached(at: now())
            }
        } catch {
            // Stopped as the app went away: nobody is looking.
            if error is CancellationError || Task.isCancelled { return }
            outcome = .failed((error as? MailError) ?? .cannotConnect, at: now())
        }
        checks += 1
        target.checked(outcome)
    }
}

/// What the watch needs of the screens: the root view controller in the
/// app, a stand-in over `ListLetters` in the host tests.
@MainActor
protocol MailWatchTarget: AnyObject {
    /// The Inbox's list, when it is the list in front of him and starts at
    /// the Inbox's newest letter: its mailbox, and every letter it holds
    /// from the Inbox, the ones not yet drawn included (`ListLetters.watched`).
    /// Nil for another folder, a day jumped to, a search showing, and a list
    /// whose first page never came, for all of which only the Inbox's count
    /// is checked (`ListLetters.toWatch`).
    var watchedInbox: (mailboxID: String, letters: [String])? { get }
    /// The Inbox's unread count as the folder pane shows it, nil if it
    /// shows none.
    var shownInboxUnread: Int? { get }
    /// News of the Inbox, for its list to show or hold, and what the list
    /// made of it. At every check of the Inbox's list, with no news too, for
    /// what the list has held to go on if he is now at the top.
    func found(_ news: FolderNews, in mailboxID: String) -> NewsTaken
    /// The folder counts may be out of date.
    func countsChanged()
    /// How the check went, for the line under the list.
    func checked(_ outcome: MailWatch.Outcome)
}

/// What the list made of a check's news (`MailWatchTarget.found`).
enum NewsTaken: Equatable {
    /// Held or put on, some of it new to the list: the counts are swept.
    case new
    /// Every letter of it held or on the list already, or already off it.
    case known
    /// Not taken: the list it was found for has gone while the check was
    /// out, to another folder or to a day. The counts are swept all the
    /// same, since they follow the Inbox whatever is in front, and the next
    /// check of the Inbox's list searches again (`MailWatch.searchOwed`).
    case notTaken
}

/// What has come into a folder and gone from it since its list was fetched.
struct FolderNews: Equatable {
    /// The new letters, newest first, previews empty.
    var arrived: [MessageSummary] = []
    /// The letters taken out of it elsewhere, by id.
    var gone: [String] = []
    /// The list is to be fetched afresh rather than added to: the folder
    /// has been renumbered, or more has come than one check puts on
    /// (`IMAPMailRepository.mostNews`).
    var refetch = false

    var isEmpty: Bool { arrived.isEmpty && gone.isEmpty && !refetch }
}

/// What the line under the list says at rest: when the list was last
/// brought up to date, the way Mail says it, and that the last try failed
/// when it did, rather than an "Updated Just Now" that is no longer true.
///
/// Mail's words, where they are known. Seen in Mail's own bottom bar in
/// published screenshots of iOS 8 (iOS App Reverse Engineering, 2nd ed.,
/// figures 6-10, 8-1, 8-12, 8-21): "Updated Just Now", "Updated 2 minutes
/// ago", "Updated at 16:55", "Updated Yesterday"; and "Checking for Mail…"
/// and "Updated 5 minutes ago" as users of later versions quote them. When
/// an account fails, Mail keeps its "Updated …" line and says "Account
/// Error" under it. Guessed: "1 minute", singular; where minutes give way
/// to the time of day, here at the hour (iOS 8 showed "at 16:55" eight
/// minutes after it, iOS 13 users "5 minutes ago"); the date form for
/// anything before yesterday; and "No Connection" and "Password Needs
/// Updating" for what failed, since "Account Error" would tell him nothing.
struct UpdatedLine: Equatable {

    enum Failure: Equatable {
        case noConnection
        case password
    }

    /// When the list was last brought up to date, nil if it never has been.
    private(set) var updated: Date?
    /// Why the last try failed, nil if it did not.
    private(set) var failure: Failure?

    /// The list is up to date with the server as of `time`.
    mutating func succeeded(at time: Date) {
        updated = time
        failure = nil
    }

    /// The server answered, but nothing was listed: the check of the Inbox's
    /// count while another folder is in front. The connection is back, so a
    /// failure is no longer the news; but a list that has never been fetched
    /// goes on saying why it is empty until it is.
    mutating func reached() {
        if updated != nil { failure = nil }
    }

    mutating func failed(_ error: MailError) {
        failure = error == .passwordNeedsUpdating ? .password : .noConnection
    }

    /// How the watch's check went, for the line under the list of
    /// `mailboxID`. A check of the Inbox's list brings only that list up to
    /// date; one of the Inbox's count, or of the Inbox's list while another
    /// is in front, says only that the server can be reached.
    mutating func checked(_ outcome: MailWatch.Outcome, listing mailboxID: String) {
        switch outcome {
        case let .listed(checked, at):
            if checked == mailboxID { succeeded(at: at) } else { reached() }
        case .reached:
            reached()
        case let .failed(error, _):
            failed(error)
        }
    }

    /// Two lines when the last try failed, the age over what failed, as
    /// Mail's bar puts its account error under its "Updated" line.
    func text(now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let age = updated.map { Self.age(of: $0, now: now, calendar: calendar, locale: locale) }
        guard let failure else { return age ?? "Checking for Mail…" }
        let said = failure == .password ? "Password Needs Updating" : "No Connection"
        return age.map { "\($0)\n\(said)" } ?? said
    }

    /// "Updated Just Now" for the first minute, then the minutes, then the
    /// time of day, then "Yesterday", then the date. An update dated after
    /// now, the clock having been set back, is given by its time or date
    /// rather than called just now.
    static func age(of updated: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let seconds = now.timeIntervalSince(updated)
        if seconds >= 0, seconds < 60 { return "Updated Just Now" }
        if seconds >= 60, seconds < 3_600 {
            let minutes = Int(seconds / 60)
            return minutes == 1 ? "Updated 1 minute ago" : "Updated \(minutes) minutes ago"
        }
        let format = DateFormatter()
        format.locale = locale
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        if calendar.isDate(updated, inSameDayAs: now) {
            format.setLocalizedDateFormatFromTemplate("jmm")
            return "Updated at \(format.string(from: updated))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(updated, inSameDayAs: yesterday) {
            return "Updated Yesterday"
        }
        format.dateStyle = .short
        format.timeStyle = .none
        return "Updated \(format.string(from: updated))"
    }
}
