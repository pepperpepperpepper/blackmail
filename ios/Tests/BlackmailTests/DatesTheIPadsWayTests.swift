import XCTest
@testable import Blackmail

/// Every date shown to him is written the iPad's way, as Mail writes it
/// (B-119): the locale's own styles and templates, so the region decides
/// the order of day and month, the clock and the year. His iPad's region
/// writes month first. The app wrote "03/10/26" for 3 October in every
/// region, which he reads as March 10, and "3 October 2026 at 9:14 AM" in
/// the header and on paper.
///
/// The strings are this host's ICU's, pinned exactly in three regions: the
/// United States, his; Britain, day first; and Canada, year first in a
/// short date. The iPad writes its own ICU's, which is what its Mail
/// writes: the point is that nothing here decides the order. Then the
/// source, read: no fixed pattern in anything that draws a date for him.
final class DatesTheIPadsWayTests: XCTestCase {

    private struct Region {
        let locale: Locale
        let zone: TimeZone
    }

    private let us = Region(locale: Locale(identifier: "en_US"),
                            zone: TimeZone(identifier: "America/New_York")!)
    private let gb = Region(locale: Locale(identifier: "en_GB"),
                            zone: TimeZone(identifier: "Europe/London")!)
    private let ca = Region(locale: Locale(identifier: "en_CA"),
                            zone: TimeZone(identifier: "America/Toronto")!)
    /// The space the formatter puts before AM and PM.
    private let nb = "\u{202F}"

    /// `day` October 2026 (or of `year`), at `hour`:`minute`:03 in the
    /// region's own zone.
    private func october(_ day: Int, _ hour: Int, _ minute: Int, year: Int = 2026,
                         in region: Region) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = region.zone
        return calendar.date(from: DateComponents(year: year, month: 10, day: day,
                                                  hour: hour, minute: minute, second: 3))!
    }

    /// Saturday 24 October 2026, noon, where the list is looked at.
    private func now(in region: Region) -> Date { october(24, 12, 0, in: region) }

    /// A row's date: the time today, "Yesterday", the weekday this week,
    /// and the short date before that.
    private func rows(_ region: Region) -> [String] {
        [october(24, 9, 14, in: region), october(23, 18, 43, in: region),
         october(22, 9, 14, in: region), october(3, 9, 14, in: region)].map {
            MailFormat.listTimestamp($0, now: now(in: region), locale: region.locale,
                                     timeZone: region.zone)
        }
    }

    /// The reading pane's header: the relative day and the time, then the
    /// long date and the time.
    private func header(_ region: Region) -> [String] {
        [october(24, 9, 14, in: region), october(23, 18, 43, in: region),
         october(22, 9, 14, in: region), october(3, 9, 14, in: region)].map {
            MailFormat.detailTimestamp($0, now: now(in: region), locale: region.locale,
                                       timeZone: region.zone)
        }
    }

    // MARK: - The rows, the stack's lines and the kept page

    /// The list's rows, a conversation's closed lines and the kept page's
    /// rows are all `listTimestamp` (`MessageCell`, `ConversationDocument`,
    /// `MessageThread`). A letter older than a week: "10/3/26" with his US
    /// region, as Mail's list.
    func testTheRowsDateIsTheRegionsShortDate() {
        XCTAssertEqual(rows(us), ["9:14\(nb)AM", "Yesterday", "Thursday", "10/3/26"])
        XCTAssertEqual(rows(gb), ["09:14", "Yesterday", "Thursday", "03/10/2026"])
        XCTAssertEqual(rows(ca), ["9:14\(nb)AM", "Yesterday", "Thursday", "2026-10-03"])
    }

    // MARK: - The header and the paper

    /// The header: "Today at" and "Yesterday at" with the time, as before,
    /// and the long date with the time, month first with his region:
    /// "October 3, 2026 at 9:14 AM", as Mail's header.
    func testTheHeadersDateIsTheRegionsLongDate() {
        XCTAssertEqual(header(us), ["Today at 9:14\(nb)AM", "Yesterday at 6:43\(nb)PM",
                                    "October 22, 2026 at 9:14\(nb)AM",
                                    "October 3, 2026 at 9:14\(nb)AM"])
        XCTAssertEqual(header(gb), ["Today at 09:14", "Yesterday at 18:43",
                                    "22 October 2026 at 09:14", "3 October 2026 at 09:14"])
        XCTAssertEqual(header(ca), ["Today at 9:14\(nb)AM", "Yesterday at 6:43\(nb)PM",
                                    "October 22, 2026 at 9:14\(nb)AM",
                                    "October 3, 2026 at 9:14\(nb)AM"])
    }

    /// Paper (B-110) has the date in full whatever the day: today's letter
    /// too. Since B-172 in Mail's printed form, the medium date and the
    /// medium time with its seconds, "Oct 27, 2026 at 1:25:45 PM" as Mail
    /// printed it on the test iPad; the region's own, as every date here.
    func testThePrintedDateIsTheRegionsMediumDateAndTime() {
        let letter = { (region: Region) in
            Message(id: "7/3", mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                    senderAddress: "sam@example.com", to: ["jane@example.com"], cc: [],
                    subject: "The garden", date: self.october(24, 9, 14, in: region),
                    textBody: "Hello.", htmlBody: nil, attachments: [])
        }
        let printed = { (region: Region) in
            PrintPage.head(letter(region), size: { "\($0)" }, locale: region.locale,
                           timeZone: region.zone).date
        }
        XCTAssertEqual(printed(us), "Oct 24, 2026 at 9:14:03\(nb)AM")
        XCTAssertEqual(printed(gb), "24 Oct 2026 at 09:14:03")
        XCTAssertEqual(printed(ca), "Oct 24, 2026 at 9:14:03\(nb)AM")
    }

    // MARK: - Go to Date and the status line

    /// "Showing" and "Going to" after a jump, and "No mail on or after":
    /// the day in words, in the region's order, the year only when it is
    /// not this one.
    func testGoToDateSaysTheDayInTheRegionsOrder() {
        func spoken(_ year: Int, _ region: Region) -> String {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = region.zone
            return IMAPDate.spokenDay(october(3, 9, 14, year: year, in: region),
                                      now: now(in: region), calendar: calendar,
                                      locale: region.locale)
        }
        XCTAssertEqual([spoken(2026, us), spoken(2025, us)], ["October 3", "October 3, 2025"])
        XCTAssertEqual([spoken(2026, gb), spoken(2025, gb)], ["3 October", "3 October 2025"])
        XCTAssertEqual([spoken(2026, ca), spoken(2025, ca)], ["October 3", "October 3, 2025"])
    }

    /// The line under the list: the time it was updated today, and the
    /// short date before yesterday.
    func testTheUpdatedLineIsInTheRegionsWay() {
        func said(_ updated: Date, _ region: Region) -> String {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = region.zone
            var line = UpdatedLine()
            line.succeeded(at: updated)
            return line.text(now: now(in: region), calendar: calendar, locale: region.locale)
        }
        XCTAssertEqual(said(october(24, 9, 14, in: us), us), "Updated at 9:14\(nb)AM")
        XCTAssertEqual(said(october(3, 9, 14, in: us), us), "Updated 10/3/26")
        XCTAssertEqual(said(october(24, 9, 14, in: gb), gb), "Updated at 09:14")
        XCTAssertEqual(said(october(3, 9, 14, in: gb), gb), "Updated 03/10/2026")
        XCTAssertEqual(said(october(24, 9, 14, in: ca), ca), "Updated at 9:14\(nb)AM")
        XCTAssertEqual(said(october(3, 9, 14, in: ca), ca), "Updated 2026-10-03")
    }

    // MARK: - The composer's lines

    /// A reply's line, Mail's words around the region's medium date and
    /// short time: "On Oct 3, 2026, at 9:14 AM" with his region, as every
    /// Apple Mail line in his replies reads, and "On 3 Oct 2026, at 09:14"
    /// with a British one, as a British Mail writes it (`PanePageTests`'
    /// letter from one).
    func testTheReplyLineIsMailsInTheRegionsWay() {
        func line(_ region: Region) -> String {
            MailFormat.quoteAttribution(october(3, 9, 14, in: region),
                                        sender: "Jane Smith <jane@example.com>",
                                        locale: region.locale, timeZone: region.zone)
        }
        XCTAssertEqual(line(us), "On Oct 3, 2026, at 9:14\(nb)AM, Jane Smith <jane@example.com> wrote:")
        XCTAssertEqual(line(gb), "On 3 Oct 2026, at 09:14, Jane Smith <jane@example.com> wrote:")
        XCTAssertEqual(line(ca), "On Oct 3, 2026, at 9:14\(nb)AM, Jane Smith <jane@example.com> wrote:")
    }

    /// A forward's Date line, the long date and the long time with the
    /// zone, which a forwarded letter shown in the pane has too
    /// (`ForwardedFields`).
    func testTheForwardedDateIsTheRegionsLongForm() {
        func date(_ region: Region) -> String {
            MailFormat.forwardedDate(october(3, 9, 14, in: region), locale: region.locale,
                                     timeZone: region.zone)
        }
        XCTAssertEqual(date(us), "October 3, 2026 at 9:14:03\(nb)AM EDT")
        XCTAssertEqual(date(gb), "3 October 2026 at 09:14:03 BST")
        XCTAssertEqual(date(ca), "October 3, 2026 at 9:14:03\(nb)AM EDT")
    }

    // MARK: - The source

    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()     // BlackmailTests
        .deletingLastPathComponent()     // Tests
        .deletingLastPathComponent()     // ios
        .appendingPathComponent("Sources")

    /// Every Swift file under Sources, by its path under it, with its
    /// lines, comment lines left out.
    private func code() throws -> [String: [String]] {
        var files: [String: [String]] = [:]
        let walk = try XCTUnwrap(FileManager.default.enumerator(at: Self.sources,
                                                                includingPropertiesForKeys: nil))
        for case let url as URL in walk where url.pathExtension == "swift" {
            let path = String(url.path.dropFirst(Self.sources.path.count + 1))
            files[path] = try String(contentsOf: url, encoding: .utf8)
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.hasPrefix("//") && !$0.isEmpty }
        }
        XCTAssertGreaterThan(files.count, 100, "the sources were found")
        return files
    }

    /// Each file's lines holding `text`.
    private func lines(holding text: String, in files: [String: [String]]) -> [String: [String]] {
        files.compactMapValues { lines in
            let found = lines.filter { $0.contains(text) }
            return found.isEmpty ? nil : found
        }
    }

    /// A fixed pattern is set only where nobody reads it as a date he is
    /// shown: what goes on the wire and is read off it, IMAP's SEARCH day
    /// and the Date header, in `en_US_POSIX`; the connection log's times,
    /// for whoever helps; and a set-aside folder's name. Everything shown
    /// to him is a style or a template. A pattern added anywhere fails
    /// here, until it is looked at.
    func testNoFixedPatternWritesADateHeIsShown() throws {
        let files = try code()
        XCTAssertEqual(lines(holding: "dateFormat =", in: files), [
            "Blackmail/IMAP/IMAPParser.swift": ["formatter.dateFormat = format"],
            "Blackmail/Mail/IMAPDate.swift": ["f.dateFormat = \"dd-MMM-yyyy\""],
            "Blackmail/Mail/IMAPMailRepository.swift": ["f.dateFormat = \"EEE, d MMM yyyy HH:mm:ss Z\"",
                                                        "f.dateFormat = \"d MMM yyyy HH:mm:ss Z\""],
            "Blackmail/MIME/RFC5322Builder.swift": ["f.dateFormat = \"EEE, d MMM yyyy HH:mm:ss Z\""],
            "Blackmail/Mail/Diagnostics.swift": ["stamp.dateFormat = \"HH:mm:ss.SSS\""],
            "Blackmail/Mail/LocalDrafts.swift": ["stamp.dateFormat = \"yyyy-MM-dd HH.mm.ss\""],
        ])
        // Each of them in en_US_POSIX, the one locale any line names.
        XCTAssertEqual(lines(holding: "Locale(identifier:", in: files).mapValues(\.count), [
            "Blackmail/IMAP/IMAPParser.swift": 1, "Blackmail/Mail/IMAPDate.swift": 1,
            "Blackmail/Mail/IMAPMailRepository.swift": 2, "Blackmail/MIME/RFC5322Builder.swift": 1,
            "Blackmail/Mail/Diagnostics.swift": 1, "Blackmail/Mail/LocalDrafts.swift": 1,
        ])
        for (path, found) in lines(holding: "Locale(identifier:", in: files) {
            for line in found {
                XCTAssertTrue(line.hasSuffix("Locale(identifier: \"en_US_POSIX\")"), "\(path): \(line)")
            }
        }
    }

    /// Every formatter in the app, file by file: the ones above, and the
    /// three that write what he sees, each from the locale. `DisplayDates`
    /// writes the rows, the header, the paper and the composer's lines;
    /// `IMAPDate.spokenDay` Go to Date's day; `UpdatedLine.age` the line
    /// under the list. A formatter made anywhere else fails here.
    func testEveryFormatterIsKnown() throws {
        let files = try code()
        XCTAssertEqual(lines(holding: "DateFormatter()", in: files).mapValues(\.count), [
            "Blackmail/Model/MailModels.swift": 1,
            "Blackmail/Mail/IMAPDate.swift": 2, "Blackmail/Mail/MailWatch.swift": 1,
            "Blackmail/IMAP/IMAPParser.swift": 1, "Blackmail/Mail/IMAPMailRepository.swift": 2,
            "Blackmail/MIME/RFC5322Builder.swift": 1, "Blackmail/Mail/Diagnostics.swift": 1,
            "Blackmail/Mail/LocalDrafts.swift": 1,
        ])
        for kind in ["ISO8601DateFormatter", "DateIntervalFormatter", "RelativeDateTimeFormatter",
                     ".formatted(", "FormatStyle"] {
            XCTAssertEqual(lines(holding: kind, in: files), [:], kind)
        }
        // The templates: letters alone, so the locale puts them in order and
        // writes what goes between them.
        XCTAssertEqual(lines(holding: "setLocalizedDateFormatFromTemplate(", in: files), [
            "Blackmail/Model/MailModels.swift": ["formatter.setLocalizedDateFormatFromTemplate(\"EEEE\")"],
            "Blackmail/Mail/IMAPDate.swift":
                ["f.setLocalizedDateFormatFromTemplate(sameYear ? \"dMMMM\" : \"dMMMMy\")"],
            "Blackmail/Mail/MailWatch.swift": ["format.setLocalizedDateFormatFromTemplate(\"jmm\")"],
        ])
        // Go to Date's calendar is the iPad's, never given a locale.
        XCTAssertEqual(lines(holding: "picker.locale", in: files), [:])
    }

    /// Where the dates reach him, each through those, with the iPad's
    /// locale and zone: no caller hands in another.
    func testTheScreensUseTheIPadsLocale() throws {
        let files = try code()
        let expected: [(String, String)] = [
            ("Blackmail/UI/MessageCell.swift", "MailFormat.listTimestamp(date)"),
            ("Blackmail/Mail/ConversationDocument.swift", "MailFormat.listTimestamp(e.date)"),
            ("Blackmail/Mail/ConversationDocument.swift",
             "MailFormat.listTimestamp(e.date, now: now, locale: locale, timeZone: timeZone)"),
            ("Blackmail/Mail/MessageThread.swift", "MailFormat.listTimestamp(listDate, now: now)"),
            ("Blackmail/UI/MessageHeaderView.swift", "MailFormat.detailTimestamp(date)"),
            ("Blackmail/Mail/PrintPage.swift",
             "MailFormat.printedTimestamp(m.headerDate, locale: locale, timeZone: timeZone)"),
            ("Blackmail/Model/MailModels.swift", "MailFormat.quoteAttribution(m.headerDate, sender: m.sender)"),
            ("Blackmail/Model/MailModels.swift", "MailFormat.forwardedDate(m.headerDate)"),
            ("Blackmail/MIME/ForwardedFields.swift", "MailFormat.forwardedDate(date)"),
            ("Blackmail/UI/MessageListViewController.swift", "\"Showing \\(IMAPDate.spokenDay("),
            ("Blackmail/UI/MessageListViewController.swift",
             "\"No mail on or after \\(IMAPDate.spokenDay(date))\""),
            ("Blackmail/Mail/Feedback.swift", "\"Going to \\(IMAPDate.spokenDay(day))…\""),
        ]
        for (path, call) in expected {
            let lines = try XCTUnwrap(files[path], path)
            XCTAssertTrue(lines.contains { $0.contains(call) }, "\(path): \(call)")
        }
        // PrintPage's own locale and zone are the iPad's unless a test hands
        // in others, and so are the stack's lines written again (B-139).
        XCTAssertTrue(try XCTUnwrap(files["Blackmail/Mail/PrintPage.swift"]).contains {
            $0.contains("locale: Locale = .current, timeZone: TimeZone = .current) -> Head {")
        })
        XCTAssertTrue(try XCTUnwrap(files["Blackmail/Mail/ConversationDocument.swift"]).contains {
            $0.contains("init(_ entries: [Entry], now: Date = Date(), locale: Locale = .current,")
        })
        // Nothing calls these with a locale of its own.
        for name in ["listTimestamp(", "detailTimestamp(", "fullTimestamp(", "printedTimestamp(",
                     "quoteAttribution(", "forwardedDate(", "spokenDay("] {
            for (path, found) in lines(holding: name, in: files) {
                for line in found where line.contains("locale:") && !line.contains("func ") {
                    XCTAssertTrue(line.contains("locale: locale"), "\(path): \(line)")
                }
            }
        }
    }
}
