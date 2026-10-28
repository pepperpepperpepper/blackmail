import XCTest
@testable import Blackmail

/// The date a printed letter's "Date:", a reply's "On ... wrote:" and
/// Forward's header give (B-178, the third round): when the letter arrived,
/// as Mail 16.5.1's print and reply give it; its Date only where that is
/// not known, a letter kept on the iPad with no arrival.
///
/// Found on the test iPad on 2026-10-28 (round r6-l-fix): for a letter
/// dated 1 March 2024 that arrived at 2:15 PM that day, Mail printed
/// "Date: Oct 28, 2026 at 2:15:14 PM" and wrote "On Oct 28, 2026, at 2:15
/// PM, ... wrote:", and for one dated that morning at 9 that arrived on 8
/// October, "Date: Oct 8, 2026 at 12:00:00 PM" and "On Oct 8, 2026, at
/// 12:00 PM, ... wrote:". Blackmail printed and wrote their Dates, "Mar 1,
/// 2024" and "Oct 28, 2026 at 9:00". The words and their forms are kept;
/// only which date. Mail's Forward was not looked at: it goes by the same
/// rule. And the letter the pane holds carries its row's arrival wherever
/// it is handed on: Reply, Reply All, Forward and Print from the Reply
/// sheet, Markup and Reply, a row's own Reply, a conversation's letters.
final class PaperDateTests: XCTestCase {

    private let us = Locale(identifier: "en_US")
    private let york = TimeZone(identifier: "America/New_York")!

    /// 1 March 2024, noon in New York: "dated old"'s Date.
    private let march = Date(timeIntervalSince1970: 1_709_312_400)
    /// 28 October 2026, 2:15:14 PM in New York: when "dated old" arrived.
    private let came = Date(timeIntervalSince1970: 1_793_211_314)
    /// 8 October 2026, noon in New York: when "came old" arrived.
    private let october8 = Date(timeIntervalSince1970: 1_791_475_200)
    /// 28 October 2026, 9 AM in New York: "came old"'s Date.
    private let morning = Date(timeIntervalSince1970: 1_793_192_400)

    private func letter(_ subject: String, dated: Date, arrived: Date?) -> Message {
        var m = Message(id: "1/1187", mailboxID: "Notes", sender: "Dora Example <dora@example.net>",
                        senderAddress: "dora@example.net", to: ["Jane Example <jane@example.com>"], cc: [],
                        subject: subject, date: dated, textBody: "A few words.", htmlBody: nil,
                        attachments: [])
        m.arrived = arrived
        return m
    }

    /// The print's "Date:" in Mail's words for when each letter arrived,
    /// as Mail's preview read on the iPad.
    func testThePrintGivesWhenTheLetterArrivedInMailsWords() {
        let nb = "\u{202F}"
        func printed(_ m: Message) -> String {
            PrintPage.head(m, size: { "\($0)" }, locale: us, timeZone: york).date
        }
        let datedOld = printed(letter("R6 B-178 dated old", dated: march, arrived: came))
        let cameOld = printed(letter("R6 B-178 came old", dated: morning, arrived: october8))
        // The iPad's formatter puts U+202F before PM on iPadOS 17 and
        // later, an ordinary space before (`quoteAttribution`).
        XCTAssertTrue(["Oct 28, 2026 at 2:15:14 PM", "Oct 28, 2026 at 2:15:14\(nb)PM"].contains(datedOld),
                      datedOld)
        XCTAssertTrue(["Oct 8, 2026 at 12:00:00 PM", "Oct 8, 2026 at 12:00:00\(nb)PM"].contains(cameOld),
                      cameOld)
        XCTAssertEqual(printed(letter("Mar", dated: march, arrived: came)),
                       MailFormat.printedTimestamp(came, locale: us, timeZone: york))
        XCTAssertNotEqual(datedOld, MailFormat.printedTimestamp(march, locale: us, timeZone: york))
        XCTAssertNotEqual(cameOld, MailFormat.printedTimestamp(morning, locale: us, timeZone: york))
    }

    /// A reply's "On ... wrote:" and Forward's "Date:" by the arrival too,
    /// never the Date; the words as before (`quoteAttribution`,
    /// `forwardedDate`).
    func testTheReplyAndTheForwardGiveWhenTheLetterArrived() {
        for (dated, arrived) in [(march, came), (morning, october8)] {
            let m = letter("R6 B-178", dated: dated, arrived: arrived)
            for all in [false, true] {
                let reply = Draft.replying(to: m, all: all, mine: OwnAddresses([]))
                XCTAssertTrue(reply.body.contains(MailFormat.quoteAttribution(arrived, sender: m.sender)
                                                  + "\n> A few words."), reply.body)
                XCTAssertFalse(reply.body.contains(MailFormat.quoteAttribution(dated, sender: m.sender)))
                XCTAssertTrue(reply.quote?.region.hasPrefix(MailFormat.quoteAttribution(arrived, sender: m.sender))
                              == true)
            }
            let forward = Draft.forwarding(m)
            XCTAssertTrue(forward.body.contains("Date: \(MailFormat.forwardedDate(arrived))\n"), forward.body)
            XCTAssertFalse(forward.body.contains(MailFormat.forwardedDate(dated)))
        }
        // In Mail's words with his region, as Mail's composer read.
        let line = MailFormat.quoteAttribution(letter("x", dated: march, arrived: came).headerDate,
                                               sender: "Dora Example <dora@example.net>",
                                               locale: us, timeZone: york)
        XCTAssertTrue(line.hasPrefix("On Oct 28, 2026, at 2:15"), line)
        XCTAssertTrue(line.hasSuffix("PM, Dora Example <dora@example.net> wrote:"), line)
    }

    /// A letter kept on the iPad by a build before rows carried the
    /// arrival, or one whose row does not say, keeps its Date on the
    /// paper, in the reply and in the forward.
    func testALetterWithNoArrivalKeepsItsDate() {
        let m = letter("Old", dated: march, arrived: nil)
        XCTAssertEqual(PrintPage.head(m, size: { "\($0)" }, locale: us, timeZone: york).date,
                       MailFormat.printedTimestamp(march, locale: us, timeZone: york))
        XCTAssertTrue(Draft.replying(to: m, all: false, mine: OwnAddresses([]))
                        .body.contains(MailFormat.quoteAttribution(march, sender: m.sender)))
        XCTAssertTrue(Draft.forwarding(m).body.contains("Date: \(MailFormat.forwardedDate(march))\n"))
        // Another letter's row gives it nothing.
        let other = MessageSummary(id: "1/9", mailboxID: "Notes", sender: "Sam", subject: "Other",
                                   preview: "", date: morning, isRead: true, isFlagged: false,
                                   arrived: october8)
        XCTAssertEqual(PrintPage.head(m.arriving(as: other), size: { "\($0)" }, locale: us,
                                      timeZone: york).date,
                       MailFormat.printedTimestamp(march, locale: us, timeZone: york))
    }

    /// The pane holds each letter with its row's arrival and hands that
    /// letter on: the single letter's (`message`, which the Reply sheet's
    /// Reply, Reply All, Forward and Print and Markup and Reply take), a
    /// conversation's (`loaded`, then `message` as he opens it), his own
    /// from Sent Mail (`related`, for Markup and Reply on a file of it),
    /// and a row's own Reply (`answer`). Print and the drafts read
    /// `headerDate`.
    func testThePaneHandsOnTheLetterWithItsArrival() throws {
        let pane = try source("Sources/Blackmail/UI/MessageDetailViewController.swift")
        for wiring in [
            "let shown = m.arriving(as: summary) self.message = shown self.header.configure(with: shown)",
            "let m = came.arriving(as: threadSummaries[id]) loaded[id] = m drawBody(m, body, focus: focus)",
            "m = try await repository.openLetter(letter).arriving(as: letter)",
            // A conversation's letter he opens is `loaded`'s, given its
            // arrival above, whether it has just come or came before.
            "drawBody(already, body, focus: focus)",
            "if focus { focusLetter(m) }",
        ] {
            XCTAssertTrue(pane.contains(wiring), wiring)
        }
        // `message` is given nothing else but nil, and `focusLetter`'s `m`.
        let given = pane.components(separatedBy: "message = ").dropFirst()
            .map { String($0.prefix(while: { $0 != " " })) }
        XCTAssertEqual(Set(given), ["nil", "shown", "m"])
        XCTAssertEqual(pane.components(separatedBy: "message = m ").count - 1, 1)
        XCTAssertTrue(pane.contains("private func focusLetter(_ m: Message) { guard stackFocus.takes(m.id) "
                                    + "else { return } message = m"))
        XCTAssertEqual(pane.components(separatedBy: "focusLetter(").count - 1, 2, "defined, and called by drawBody")
        XCTAssertEqual(pane.components(separatedBy: "drawBody(").count - 1, 3)
        XCTAssertEqual(pane.components(separatedBy: "loaded[id] = ").count - 1, 1)
        XCTAssertTrue(pane.contains("let already = loaded[id]"))
        XCTAssertFalse(pane.contains("loaded[id] = came"))
        let related = try source("Sources/Blackmail/Mail/PaneRelated.swift")
        XCTAssertTrue(related.contains("opened[load.entryID] = m.arriving(as: load.row)"))
        XCTAssertEqual(related.components(separatedBy: "opened[load.entryID] = ").count - 1, 1)
        // What the Reply sheet and Markup and Reply hand on is that letter.
        XCTAssertTrue(pane.contains("@objc private func replyTapped() { guard let m = message else { return }"))
        XCTAssertTrue(pane.contains("self?.printLetter(m)"))
        XCTAssertTrue(pane.contains("let shown = message?.id == letter ? message : (loaded[letter] ?? "
                                    + "related.letter(withID: letter))"))
        XCTAssertTrue(pane.contains("alone: message, stack: loaded, his: { related.letter(inSection: $0) })"))
        XCTAssertTrue(pane.contains("openCompose(replyTo: letter, all: false, forward: false, landing: [copy])"))
        // The paper and the drafts by `headerDate`, nowhere by `m.date`.
        let printed = try source("Sources/Blackmail/Mail/PrintPage.swift")
        XCTAssertTrue(printed.contains("MailFormat.printedTimestamp(m.headerDate, locale: locale, timeZone: timeZone)"))
        XCTAssertFalse(printed.contains("m.date"))
        let model = try source("Sources/Blackmail/Model/MailModels.swift")
        XCTAssertTrue(model.contains("MailFormat.quoteAttribution(m.headerDate, sender: m.sender)"))
        XCTAssertTrue(model.contains("MailFormat.forwardedDate(m.headerDate)"))
        XCTAssertFalse(model.contains("quoteAttribution(m.date"))
        XCTAssertFalse(model.contains("forwardedDate(m.date"))
    }

    /// The file with its comment lines left out and every run of white
    /// space as one space, so wiring reads as one line.
    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent(file)
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .joined(separator: " ")
    }
}
