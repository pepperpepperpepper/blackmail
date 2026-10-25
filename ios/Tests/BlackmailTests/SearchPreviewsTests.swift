import XCTest
@testable import Blackmail

/// The previews a search's hits have drawn, carried to the same letters in
/// the next answer as he types (`SearchPreviews`, `ListLetters.showResults`,
/// B-135): which letters take one and which do not, the preview alone going
/// across, the bound, an answer that came after its list was replaced, a
/// page of hits, the controller's wiring read from the source, and over the
/// scripted server the preview FETCHes a name typed a letter at a time asks
/// for, as the list asked them before and as it asks them now.
final class SearchPreviewsTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let allMail = "[Gmail]/All Mail"

    /// A row, `id` in `mailbox`, carrying Gmail's id `letter` (none for nil).
    private func row(_ id: String, in mailbox: String = allMail, letter: UInt64? = nil,
                     preview: String = "", read: Bool = true, flagged: Bool = false,
                     subject: String = "The garden") -> MessageSummary {
        var row = MessageSummary(id: id, mailboxID: mailbox,
                                 sender: "Margaret Ellis <m.ellis1947@example.net>",
                                 subject: subject, preview: preview,
                                 date: Date(timeIntervalSince1970: 1_790_000_000),
                                 isRead: read, isFlagged: flagged, threadID: "T-\(id)")
        row.gmailMessageID = letter
        return row
    }

    // MARK: - Which letters take one

    /// A hit takes the preview its letter drew in the answer before, and
    /// only the rest are asked for; a hit with its own keeps it.
    @MainActor
    func testAHitTakesThePreviewItsLetterDrewInTheAnswerBefore() {
        let list = ListLetters()
        var asked = list.showResults([row("9/10", letter: 10), row("9/11", letter: 11)])
        XCTAssertEqual(asked.map(\.id), ["9/10", "9/11"])
        list.apply(previews: ["9/10": "Shall we meet at noon?", "9/11": "The roses are out."])

        asked = list.showResults([row("9/11", letter: 11), row("9/12", letter: 12),
                                  row("9/10", letter: 10, preview: "Its own words.")])
        XCTAssertEqual(asked.map(\.id), ["9/12"])
        XCTAssertEqual(list.results?.map(\.preview), ["The roses are out.", "", "Its own words."])
    }

    /// The hits of a search in the folder take the previews its rows drew,
    /// under the same folder and id. An All Mailboxes hit of the same letter,
    /// under All Mail's id, takes nothing and is asked for: not across
    /// folders by Gmail's id.
    @MainActor
    func testAHitTakesThePreviewTheFoldersRowDrewUnderTheSameFolderAndID() {
        let list = ListLetters()
        list.fetchedAfresh([row("1/500", in: "INBOX", letter: 10), row("1/501", in: "INBOX", letter: 11)])
        list.apply(previews: ["1/500": "Shall we meet at noon?"])

        let inFolder = list.showResults([row("1/500", in: "INBOX", letter: 10),
                                         row("1/501", in: "INBOX", letter: 11)])
        XCTAssertEqual(inFolder.map(\.id), ["1/501"], "the folder's other row drew nothing yet")
        XCTAssertEqual(list.results?.first?.preview, "Shall we meet at noon?")

        let everywhere = list.showResults([row("9/10", letter: 10)])
        XCTAssertEqual(everywhere.map(\.id), ["9/10"])
        XCTAssertEqual(list.results?.first?.preview, "")
    }

    /// Never another letter's. Under the same folder and id, a row of
    /// another Gmail id, as a row kept from an earlier launch can be another
    /// mailbox's (D-016); a row with Gmail's id and one without, either way
    /// round, as a draft kept on the iPad draws its own words with none;
    /// and, on a server with no Gmail ids, another folder's row under the
    /// same id. Each hit is asked for. With no Gmail id on either, the same
    /// folder and id carry, as a Refresh carries them.
    @MainActor
    func testNothingCrossesFromAnotherLetterOrAcrossAMissingGmailID() {
        let list = ListLetters()
        list.fetchedAfresh([row("9/20", letter: 99, preview: "Another mailbox's letter."),
                            row("9/21", preview: "A draft's own words."),
                            row("9/22", letter: 22, preview: "Gmail's letter."),
                            row("9/23", in: "Trash", preview: "The Trash's letter."),
                            row("9/24", preview: "No Gmail ids here.")])
        let asked = list.showResults([row("9/20", letter: 20), row("9/21", letter: 21),
                                      row("9/22"), row("9/23"), row("9/24")])
        XCTAssertEqual(asked.map(\.id), ["9/20", "9/21", "9/22", "9/23"])
        XCTAssertEqual(list.results?.map(\.preview), ["", "", "", "", "No Gmail ids here."])
    }

    /// Only the preview goes across. The new answer's read mark, flag and
    /// everything else stand, as a letter marked read or flagged elsewhere
    /// between two answers has them.
    @MainActor
    func testOnlyThePreviewGoesAcrossTheMarksAreTheNewAnswers() {
        let list = ListLetters()
        list.showResults([row("9/10", letter: 10, read: false, flagged: false)])
        list.apply(previews: ["9/10": "Shall we meet at noon?"])

        let changed = row("9/10", letter: 10, read: true, flagged: true, subject: "Re: The garden")
        XCTAssertEqual(list.showResults([changed]), [])
        var expected = changed
        expected.preview = "Shall we meet at noon?"
        XCTAssertEqual(list.results, [expected])
    }

    /// A letter drawn in an answer no longer on screen still gives its
    /// preview: "Marg", then "Margx" with nothing found, then "Marg" again,
    /// and a search after the last one was cancelled.
    @MainActor
    func testAPreviewDrawnBeforeTheAnswerOnScreenStillCarries() {
        let list = ListLetters()
        list.showResults([row("9/10", letter: 10), row("9/11", letter: 11)])
        list.apply(previews: ["9/10": "Noon.", "9/11": "Roses."])
        XCTAssertEqual(list.showResults([]), [])
        XCTAssertEqual(list.showResults([row("9/11", letter: 11), row("9/10", letter: 10)]), [])
        XCTAssertEqual(list.results?.map(\.preview), ["Roses.", "Noon."])

        list.endSearch()
        XCTAssertEqual(list.showResults([row("9/10", letter: 10)]), [])
        XCTAssertEqual(list.results?.map(\.preview), ["Noon."])
    }

    // MARK: - The bound

    /// The last 300 drawn are kept, the one drawn longest ago going first;
    /// a letter drawn again is the newest again.
    @MainActor
    func testTheLastThreeHundredDrawnAreKept() {
        XCTAssertEqual(SearchPreviews.most, 300)
        var drawn = SearchPreviews()
        let rows = (0..<302).map { row("9/\($0)", letter: UInt64($0), preview: "Letter \($0).") }
        drawn.note(Array(rows[0..<300]))
        XCTAssertEqual(drawn.count, 300)
        func carries(_ n: Int) -> Bool {
            drawn.carrying(into: [row("9/\(n)", letter: UInt64(n))], from: []).first?.preview
                == "Letter \(n)."
        }
        XCTAssertTrue(carries(0))

        drawn.note([rows[0]])
        drawn.note([rows[300]])
        XCTAssertEqual(drawn.count, 300)
        XCTAssertTrue(carries(0), "drawn again, the newest")
        XCTAssertFalse(carries(1), "drawn longest ago, gone")
        XCTAssertTrue(carries(2))
        XCTAssertTrue(carries(300))

        drawn.note([rows[301], row("9/302", letter: 302)])
        XCTAssertEqual(drawn.count, 300, "a row with no preview is not kept")
        XCTAssertFalse(carries(2))
        XCTAssertTrue(carries(301))
        XCTAssertTrue(carries(0))
    }

    // MARK: - An answer that came late, and a page of hits

    /// The answer on its way as the list was replaced is not drawn but set
    /// aside with its group, and nothing after it is asked for; the next
    /// answer's hits of those letters take it, those of that group's folder
    /// alone.
    @MainActor
    func testAnAnswerThatCameAfterTheListWasReplacedServesTheNextAnswer() async {
        let list = ListLetters()
        let rows = [row("9/10"), row("9/10", in: "[Gmail]/Trash"), row("9/11"),
                    row("9/12", in: "[Gmail]/Spam")]
        list.showResults(rows)
        var current = true
        var asked: [String] = []
        var applied: [String: String] = [:]
        await PreviewPass.run(PreviewPass.groups(for: rows),
                              fetch: { ids, mailbox in
                                  asked.append(mailbox)
                                  current = false
                                  return Dictionary(uniqueKeysWithValues: ids.map { ($0, "Words of \($0).") })
                              },
                              isCurrent: { current },
                              apply: { applied.merge($0) { a, _ in a } },
                              aside: { previews, group in
                                  list.previewsCameLate(previews, in: group.mailboxID, for: rows)
                              })
        XCTAssertEqual(asked, [Self.allMail])
        XCTAssertEqual(applied, [:])
        XCTAssertTrue(list.results?.allSatisfy { $0.preview.isEmpty } == true, "not drawn")

        let next = list.showResults([row("9/11"), row("9/10", in: "[Gmail]/Trash"), row("9/10")])
        XCTAssertEqual(next.map(\.mailboxID), ["[Gmail]/Trash"])
        XCTAssertEqual(list.results?.map(\.preview), ["Words of 9/11.", "", "Words of 9/10."])
    }

    /// The next page of hits comes with the previews already drawn for its
    /// letters, and the folder's next page as before.
    @MainActor
    func testAPageOfHitsTakesThePreviewsAlreadyDrawn() {
        let list = ListLetters()
        list.showResults([row("9/10", letter: 10), row("9/11", letter: 11)])
        list.apply(previews: ["9/10": "Noon.", "9/11": "Roses."])
        list.showResults([row("9/30", letter: 30)])

        let fresh = list.appendPage([row("9/30", letter: 30), row("9/11", letter: 11),
                                     row("9/12", letter: 12)], toResults: true)
        XCTAssertEqual(fresh.map(\.id), ["9/11", "9/12"])
        XCTAssertEqual(fresh.map(\.preview), ["Roses.", ""])

        list.endSearch()
        let folderPage = list.appendPage([row("1/7", in: "INBOX", letter: 10)], toResults: false)
        XCTAssertEqual(folderPage.map(\.preview), [""], "a folder's page as before")
    }

    // MARK: - The wiring

    /// The list asks for the previews `showResults` says are still to come,
    /// and for a page's only where it has none; an answer that came late is
    /// set aside for the list's letters. Read from the source: the
    /// controller is UIKit.
    func testTheListAsksOnlyForTheHitsWithNoPreviewAndSetsALateAnswerAside() throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains("searchFailed = false searchShown = text let move = showingResults() "
                                    + "let unpreviewed = letters.showResults(hits) "
                                    + "reachedOldestMessage = hits.count < Self.pageSize"))
        XCTAssertTrue(list.contains("placePull() loadPreviews(for: unpreviewed) }"))
        XCTAssertFalse(list.contains("loadPreviews(for: hits"))
        XCTAssertTrue(list.contains("let fresh = self.letters.appendPage(older, toResults: searching) "
                                    + "guard !fresh.isEmpty else { return } self.regroup() "
                                    + "self.loadPreviews(for: fresh.filter { $0.preview.isEmpty }) }"))
        XCTAssertTrue(list.contains("aside: { @MainActor previews, group in "
                                    + "self?.letters.previewsCameLate(previews, in: group.mailboxID, "
                                    + "for: rows) })"))
    }

    // MARK: - Over the wire

    private static let margaret = Server.Address(name: "Margaret Ellis",
                                                 address: "m.ellis1947@example.net")
    private static let margot = Server.Address(name: "Margot Fay", address: "margot.fay@example.com")
    private static let mark = Server.Address(name: "Mark Holt", address: "mark.holt@example.org")
    private static let martha = Server.Address(name: "Martha Day", address: "martha.day@example.com")

    /// The letters a name typed slowly finds, of the kinds a mailbox holds:
    /// plain, HTML alone, both, and with a file; one of Margaret's binned,
    /// and Carlo's that names her in its words.
    private func deliverMarys(to server: ScriptedIMAPServer) {
        var stamp: TimeInterval = 0
        func send(_ from: Server.Address, _ subject: String, text: String?, html: String? = nil,
                  file: Bool = false, to mailboxes: [String] = [Server.inbox, Server.allMail]) {
            stamp += 3_600
            var letter = Server.Letter(from: from, to: [Server.owner], subject: subject,
                                       date: Server.newestDate.addingTimeInterval(stamp),
                                       text: text, html: html,
                                       messageID: "<searchprev-\(Int(stamp))@example.org>")
            if file {
                letter.files = [Server.File(name: "notes.pdf", type: "APPLICATION", subtype: "PDF",
                                            bytes: Data("%PDF-1.4 notes".utf8), contentID: nil)]
            }
            server.deliver(letter, to: mailboxes)
        }
        for (i, who) in [Self.margaret, Self.margot, Self.mark, Self.martha].enumerated() {
            send(who, "Lunch \(i)", text: "Shall we meet at noon, \(i)?\r\n")
            send(who, "Roses \(i)", text: nil, html: "<p>The roses are out, \(i).</p>")
            send(who, "Visit \(i)", text: "Tuesday suits, \(i).\r\n",
                 html: "<p>Tuesday suits, \(i).</p>")
            send(who, "Notes \(i)", text: "The notes, \(i).\r\n", file: true)
        }
        send(Self.margaret, "Old seeds", text: "Those can go.\r\n", to: [Server.trash])
        send(Server.carlo, "Cuttings", text: "Margaret asked for cuttings.\r\n")
    }

    private struct Pass: Equatable {
        var hits = 0
        var asked = 0
        var fetches = 0
        var selects = 0
    }

    /// "Margaret" typed a letter at a time, each pause an answer and its
    /// preview pass to the end, from the Inbox's first page drawn, as he
    /// searches from it: as the list asked before, every hit, and as it asks
    /// now, in All Mailboxes and in the Inbox alone. The previews each hit
    /// shows are the ones fetched for it, and the counts are printed for
    /// KNOWN_ISSUES. In All Mailboxes only "Mar" and "Margaret" ask
    /// anything, the second for Carlo's letter alone, which "Margaret" is
    /// the first to find; in the Inbox nothing is asked, its rows having
    /// drawn every hit.
    @MainActor
    func testANameTypedALetterAtATimeAsksOnlyForTheLettersNotDrawnBefore() async throws {
        let server = ScriptedIMAPServer(inboxCount: 12)
        server.matchesWholeWords = true
        deliverMarys(to: server)
        let suite = "SearchPreviewsTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = IMAPMailRepository(account: server.account, password: server.password,
                                            transport: server.transportFactory,
                                            recipients: RecipientBook(defaults: defaults),
                                            shelf: keptShelf(for: server.account))
        let inbox = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(inbox.count, 29)
        let typed = ["Ma", "Mar", "Marg", "Marga", "Margar", "Margare", "Margaret"]

        /// The previews of `rows`, asked for as the list asks, counted.
        func pass(_ rows: [MessageSummary], apply: ([String: String]) -> Void) async -> Pass {
            server.clearLog()
            await PreviewPass.run(PreviewPass.groups(for: rows),
                                  fetch: { try await repository.previews(for: $0, in: $1) },
                                  isCurrent: { true },
                                  apply: { apply($0) })
            let log = server.log
            return Pass(hits: 0, asked: rows.count,
                        fetches: log.filter { $0.verb == "UID FETCH" && $0.command.contains("BODY.PEEK[")
                                              && $0.command.contains("]<0.") }.count,
                        selects: log.filter { $0.verb == "SELECT" || $0.verb == "EXAMINE" }.count)
        }

        // Every hit's own preview, fetched apart, to hold the carried ones to.
        var gathered: [String: String] = [:]
        for scope in [MailSearchScope.allMailboxes, .currentMailbox] {
            for text in typed {
                let hits = try await repository.search(in: "inbox", query: text, scope: scope,
                                                       beforeUID: nil, limit: 50)
                for group in PreviewPass.groups(for: hits) {
                    for (id, words) in try await repository.previews(for: group.ids, in: group.mailboxID) {
                        gathered["\(group.mailboxID)|\(id)"] = words
                    }
                }
            }
        }
        let everyPreview = gathered

        /// Each answer as he types and its pass, from the Inbox drawn, with
        /// the list's carrying or, as before, every hit asked for.
        func typing(in scope: MailSearchScope, carrying: Bool) async throws -> [Pass] {
            let list = ListLetters()
            _ = await pass(list.fetchedAfresh(inbox)) { list.apply(previews: $0) }
            var steps: [Pass] = []
            for text in typed {
                let hits = try await repository.search(in: "inbox", query: text, scope: scope,
                                                       beforeUID: nil, limit: 50)
                let shown = list.showResults(hits)
                var step = await pass(carrying ? shown : hits) { list.apply(previews: $0) }
                step.hits = hits.count
                steps.append(step)
                if !carrying { continue }
                for hit in list.results ?? [] {
                    XCTAssertFalse(hit.preview.isEmpty, "\(text): \(hit.subject)")
                    XCTAssertEqual(hit.preview, everyPreview["\(hit.mailboxID)|\(hit.id)"],
                                   "\(text): \(hit.subject)")
                }
            }
            return steps
        }

        let runs = [("All Mailboxes, before", try await typing(in: .allMailboxes, carrying: false)),
                    ("All Mailboxes, now", try await typing(in: .allMailboxes, carrying: true)),
                    ("the Inbox, before", try await typing(in: .currentMailbox, carrying: false)),
                    ("the Inbox, now", try await typing(in: .currentMailbox, carrying: true))]
        for (name, steps) in runs {
            let totals = (steps.reduce(0) { $0 + $1.asked }, steps.reduce(0) { $0 + $1.fetches },
                          steps.reduce(0) { $0 + $1.selects })
            print("B-135 \(name): " + zip(typed, steps).map {
                "\($0.0) \($0.1.hits) hits \($0.1.asked) asked \($0.1.fetches) FETCH \($0.1.selects) SELECT"
            }.joined(separator: "; ") + "; previews asked, FETCH, SELECT in all: \(totals)")
        }

        let (allBefore, allNow, inboxBefore, inboxNow) = (runs[0].1, runs[1].1, runs[2].1, runs[3].1)
        XCTAssertEqual(allBefore.map(\.hits), [0, 17, 9, 5, 5, 5, 6])
        XCTAssertEqual(allBefore.map(\.asked), allBefore.map(\.hits))
        XCTAssertEqual(allBefore.map(\.fetches), [0, 3, 3, 3, 3, 3, 3])
        XCTAssertEqual(allBefore.map(\.selects), [0, 2, 2, 2, 2, 2, 1])
        XCTAssertEqual(allNow.map(\.hits), allBefore.map(\.hits))
        XCTAssertEqual(allNow.map(\.asked), [0, 17, 0, 0, 0, 0, 1])
        XCTAssertEqual(allNow.map(\.fetches), [0, 3, 0, 0, 0, 0, 1])
        XCTAssertEqual(allNow.map(\.selects), [0, 2, 0, 0, 0, 0, 0])
        XCTAssertEqual(inboxBefore.map(\.hits), [0, 16, 8, 4, 4, 4, 5])
        XCTAssertEqual(inboxBefore.map(\.asked), inboxBefore.map(\.hits))
        XCTAssertEqual(inboxBefore.map(\.fetches), [0, 2, 2, 2, 2, 2, 2])
        XCTAssertEqual(inboxNow.map(\.hits), inboxBefore.map(\.hits))
        XCTAssertEqual(inboxNow.map(\.asked), [0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(inboxNow.map(\.fetches), [0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(server.violations, [])
    }

    // MARK: - Helpers

    /// The file under Sources/Blackmail, its comment lines left out and its
    /// white space made single spaces.
    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }
}
