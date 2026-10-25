import XCTest
@testable import Blackmail

/// The previews a search's hits have drawn, carried to the same letters in
/// the next answer as he types (`SearchPreviews`, `ListLetters.showResults`,
/// B-135): which letters take one and which do not, the preview alone going
/// across, the bound, an answer that came after its list was replaced, one
/// in time drawn and kept for its folder alone, a page of hits, letters
/// drawn with no words, a folder's row whose letter's words are kept asked
/// for all the same, the controller's wiring read from the source, and over
/// the scripted server the preview FETCHes a name typed a letter at a time
/// asks for, as the list asked them before and as it asks them now, an
/// empty draft among the hits, and the Inbox's rows after Cancel.
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
        list.apply(previews: ["9/10": "Shall we meet at noon?", "9/11": "The roses are out."],
                   in: Self.allMail)

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
        list.apply(previews: ["1/500": "Shall we meet at noon?"], in: "INBOX")

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
        list.apply(previews: ["9/10": "Shall we meet at noon?"], in: Self.allMail)

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
        list.apply(previews: ["9/10": "Noon.", "9/11": "Roses."], in: Self.allMail)
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
        XCTAssertEqual(drawn.count, 300)
        XCTAssertTrue(drawn.hasDrawn(row("9/302", letter: 302)), "a row handed in with none, drawn with none")
        XCTAssertFalse(carries(2))
        XCTAssertFalse(carries(3), "the row with none counted among the 300")
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
                              apply: { answer, _ in applied.merge(answer) { a, _ in a } },
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

    /// An answer that comes in time is drawn into its group's folder alone,
    /// and kept for that folder's hits alone. One id in All Mail, the Trash
    /// and the Inbox, as folders under one UIDVALIDITY would give, is three
    /// letters: each hit takes its own folder's words, the Inbox's row under
    /// the same id none, and an answer after one with nothing found carries
    /// each hit its own.
    @MainActor
    func testAnAnswerOnTimeIsDrawnAndKeptForItsGroupsFolderAlone() async {
        let list = ListLetters()
        list.fetchedAfresh([row("9/10", in: "INBOX")])
        let rows = [row("9/10"), row("9/10", in: "[Gmail]/Trash")]
        XCTAssertEqual(list.showResults(rows).count, 2)
        await PreviewPass.run(PreviewPass.groups(for: rows),
                              fetch: { ids, mailbox in
                                  Dictionary(uniqueKeysWithValues: ids.map { ($0, "Words in \(mailbox).") })
                              },
                              isCurrent: { true },
                              apply: { list.apply(previews: $0, in: $1.mailboxID) })
        XCTAssertEqual(list.results?.map(\.preview),
                       ["Words in [Gmail]/All Mail.", "Words in [Gmail]/Trash."])
        XCTAssertEqual(list.folder.map(\.preview), [""], "the Inbox's letter under the same id")

        XCTAssertEqual(list.showResults([]), [])
        XCTAssertEqual(list.showResults([row("9/10", in: "[Gmail]/Trash"), row("9/10")]), [])
        XCTAssertEqual(list.results?.map(\.preview),
                       ["Words in [Gmail]/Trash.", "Words in [Gmail]/All Mail."])
    }

    /// The next page of hits comes with the previews already drawn for its
    /// letters, and the folder's next page as before.
    @MainActor
    func testAPageOfHitsTakesThePreviewsAlreadyDrawn() {
        let list = ListLetters()
        list.showResults([row("9/10", letter: 10), row("9/11", letter: 11)])
        list.apply(previews: ["9/10": "Noon.", "9/11": "Roses."], in: Self.allMail)
        list.showResults([row("9/30", letter: 30)])

        let fresh = list.appendPage([row("9/30", letter: 30), row("9/11", letter: 11),
                                     row("9/12", letter: 12)], toResults: true)
        XCTAssertEqual(fresh.map(\.id), ["9/11", "9/12"])
        XCTAssertEqual(fresh.map(\.preview), ["Roses.", ""])

        list.endSearch()
        let folderPage = list.appendPage([row("1/7", in: "INBOX", letter: 10)], toResults: false)
        XCTAssertEqual(folderPage.map(\.preview), [""], "a folder's page as before")
    }

    /// A page of hits makes the previews it carried the newest, as an
    /// answer does: a letter drawn first, and found again on a page after
    /// 299 others were drawn, outlasts the next one drawn, where the oldest
    /// of the 299 goes.
    @MainActor
    func testAPageOfHitsMakesThePreviewsItCarriedTheNewest() {
        let list = ListLetters()
        list.showResults([row("9/0", letter: 0)])
        list.apply(previews: ["9/0": "The first."], in: Self.allMail)
        let others = (1..<300).map { row("9/\($0)", letter: UInt64($0)) }
        list.showResults(others)
        list.apply(previews: Dictionary(uniqueKeysWithValues: others.map { ($0.id, "Words of \($0.id).") }),
                   in: Self.allMail)

        list.showResults([row("9/400", letter: 400)])
        let page = list.appendPage([row("9/0", letter: 0)], toResults: true)
        XCTAssertEqual(page.map(\.preview), ["The first."])
        list.apply(previews: ["9/400": "The newest."], in: Self.allMail)

        XCTAssertEqual(list.showResults([]), [])
        XCTAssertEqual(list.showResults([row("9/0", letter: 0)]), [], "found on the page, the newest")
        XCTAssertEqual(list.results?.map(\.preview), ["The first."])
        XCTAssertEqual(list.showResults([row("9/1", letter: 1)]).map(\.id), ["9/1"],
                       "the oldest of the others, gone")
    }

    // MARK: - Drawn with no words (B-135's check)

    /// A hit whose letter was drawn with no words, as an empty draft is, is
    /// drawn: the next answer, and the one after one with nothing found,
    /// do not ask for it, nor does a page of hits. A hit asked for and not
    /// answered is asked for again; a draft saved again, a new id, is
    /// asked for; and the same folder and id under another Gmail id too.
    @MainActor
    func testAHitDrawnWithNoWordsIsNotAskedForAgain() {
        let list = ListLetters()
        var asked = list.showResults([row("9/40", letter: 40), row("9/41", letter: 41),
                                      row("9/42", letter: 42)])
        XCTAssertEqual(asked.map(\.id), ["9/40", "9/41", "9/42"])
        list.apply(previews: ["9/40": "", "9/41": "Roses."], in: Self.allMail)

        asked = list.showResults([row("9/40", letter: 40), row("9/41", letter: 41),
                                  row("9/42", letter: 42)])
        XCTAssertEqual(asked.map(\.id), ["9/42"], "the empty draft drawn, the one not answered asked again")
        XCTAssertEqual(list.results?.map(\.preview), ["", "Roses.", ""])
        XCTAssertEqual(list.showResults([]), [])
        XCTAssertEqual(list.showResults([row("9/40", letter: 40)]), [], "after nothing found")
        XCTAssertEqual(list.showResults([row("9/43", letter: 43), row("9/40", letter: 99)]).map(\.id),
                       ["9/43", "9/40"], "saved again, and another Gmail id under the same id")

        list.showResults([row("9/41", letter: 41)])
        let page = list.appendPage([row("9/40", letter: 40), row("9/44", letter: 44)], toResults: true)
        XCTAssertEqual(list.toDraw(page).map(\.id), ["9/44"], "a page of hits")
    }

    /// The folder's own row drawn with no words, as an empty draft in
    /// Drafts, is not asked for again by a Refresh, a page fetched afresh
    /// under a search, a hit of the same letter, a cancelled search or a
    /// page of the folder; a draft saved again in its place is asked for.
    @MainActor
    func testAFolderRowDrawnWithNoWordsIsNotAskedForAgain() {
        let drafts = ScriptedIMAPServer.drafts
        func draft(_ id: String, _ letter: UInt64) -> MessageSummary { row(id, in: drafts, letter: letter) }
        let list = ListLetters()
        XCTAssertEqual(list.fetchedAfresh([draft("1/7", 7), draft("1/8", 8)]).map(\.id), ["1/7", "1/8"])
        list.apply(previews: ["1/7": "", "1/8": "Half a thought."], in: drafts)

        XCTAssertEqual(list.fetchedAfresh([draft("1/7", 7), draft("1/8", 8)]), [], "a Refresh")
        XCTAssertEqual(list.folder.map(\.preview), ["", "Half a thought."])
        XCTAssertEqual(list.showResults([draft("1/7", 7)]), [], "a hit of the same letter")
        XCTAssertEqual(list.fetchedUnderSearch([draft("1/7", 7), draft("1/8", 8)]), [], "under a search")
        XCTAssertEqual(list.endSearch(), [], "a cancelled search")

        XCTAssertEqual(list.fetchedAfresh([draft("1/9", 9), draft("1/8", 8)]).map(\.id), ["1/9"],
                       "saved again: a new id")
        let page = list.appendPage([draft("1/7", 7)], toResults: false)
        XCTAssertEqual(page.map(\.id), ["1/7"])
        XCTAssertEqual(list.toDraw(page), [], "a page of the folder")
    }

    /// An answer with no words that came after its list was replaced is
    /// kept as drawn, for its folder's rows alone.
    @MainActor
    func testALateAnswerWithNoWordsIsKeptAsDrawn() {
        let list = ListLetters()
        let rows = [row("9/40", letter: 40), row("9/40", in: "[Gmail]/Trash", letter: 40)]
        list.showResults(rows)
        list.previewsCameLate(["9/40": ""], in: Self.allMail, for: rows)
        XCTAssertEqual(list.showResults(rows).map(\.mailboxID), ["[Gmail]/Trash"])
    }

    /// Letters drawn with no words are among the last 300 drawn, and go as
    /// the others do.
    @MainActor
    func testLettersDrawnWithNoWordsAreAmongTheLastThreeHundred() {
        var drawn = SearchPreviews()
        let rows = (0..<301).map { row("9/\($0)", letter: UInt64($0)) }
        drawn.note(Array(rows[0..<300]))
        XCTAssertEqual(drawn.count, 300)
        XCTAssertTrue(drawn.hasDrawn(rows[0]))
        XCTAssertFalse(drawn.hasDrawn(rows[300]))
        drawn.note([rows[300]])
        XCTAssertEqual(drawn.count, 300)
        XCTAssertFalse(drawn.hasDrawn(rows[0]), "drawn longest ago, gone")
        XCTAssertTrue(drawn.hasDrawn(rows[1]))
        XCTAssertTrue(drawn.hasDrawn(rows[300]))
    }

    // MARK: - Words kept are the hits' to take

    /// The folder's answer came after the list was replaced, as when he
    /// starts typing before the Inbox's previews land: its words are kept
    /// for the hits, and its rows, left with none, are asked for again by a
    /// cancelled search, by every Refresh after, and by a page fetched
    /// afresh under a search. A letter the same answer drew with no words
    /// is not. The same when a Refresh replaced the list.
    @MainActor
    func testAFolderRowWhoseAnswerCameLateIsAskedForAgain() {
        let page = [row("1/5", in: "INBOX", letter: 5), row("1/6", in: "INBOX", letter: 6)]
        let late = ["1/5": "Shall we meet at noon?", "1/6": ""]
        let list = ListLetters()
        let asked = list.fetchedAfresh(page)
        XCTAssertEqual(asked.map(\.id), ["1/5", "1/6"])
        list.showResults([row("9/70", letter: 70)])
        list.previewsCameLate(late, in: "INBOX", for: asked)

        XCTAssertEqual(list.endSearch().map(\.id), ["1/5"], "a cancelled search")
        XCTAssertEqual(list.folder.map(\.preview), ["", ""])
        XCTAssertEqual(list.fetchedAfresh(page).map(\.id), ["1/5"], "a Refresh")
        XCTAssertEqual(list.fetchedAfresh(page).map(\.id), ["1/5"], "and the one after")
        list.showResults([])
        XCTAssertEqual(list.fetchedUnderSearch(page).map(\.id), ["1/5"],
                       "a page fetched afresh under a search")

        let refreshed = ListLetters()
        refreshed.previewsCameLate(late, in: "INBOX", for: refreshed.fetchedAfresh(page))
        XCTAssertEqual(refreshed.fetchedAfresh(page).map(\.id), ["1/5"], "a Refresh over the folder's pass")
    }

    /// A letter drawn with words as a hit, below the folder's pages loaded
    /// or among hits a narrower answer then dropped: after the search is
    /// cancelled its folder row, which takes nothing kept, is asked for on
    /// the page scrolled to and by a Refresh. A hit of it still takes them.
    @MainActor
    func testAFolderRowOfALetterDrawnAsAHitIsAskedFor() {
        let list = ListLetters()
        list.fetchedAfresh([row("1/90", in: "INBOX", letter: 90)])
        list.apply(previews: ["1/90": "The newest."], in: "INBOX")
        XCTAssertEqual(list.showResults([row("1/5", in: "INBOX", letter: 5)]).map(\.id), ["1/5"])
        list.apply(previews: ["1/5": "Deep down."], in: "INBOX")
        XCTAssertEqual(list.endSearch(), [])

        let page = list.appendPage([row("1/5", in: "INBOX", letter: 5)], toResults: false)
        XCTAssertEqual(page.map(\.preview), [""])
        XCTAssertEqual(list.toDraw(page).map(\.id), ["1/5"], "the page scrolled to")
        XCTAssertEqual(list.showResults([row("1/5", in: "INBOX", letter: 5)]), [], "a hit takes them")
        XCTAssertEqual(list.results?.map(\.preview), ["Deep down."])

        let narrowed = ListLetters()
        narrowed.fetchedAfresh([row("1/90", in: "INBOX", letter: 90, preview: "The newest.")])
        let hits = narrowed.showResults([row("1/8", in: "INBOX", letter: 8),
                                         row("1/9", in: "INBOX", letter: 9)])
        narrowed.showResults([row("1/9", in: "INBOX", letter: 9)])
        narrowed.previewsCameLate(["1/8": "From Peyton.", "1/9": "Also."], in: "INBOX", for: hits)
        narrowed.endSearch()
        XCTAssertEqual(narrowed.fetchedAfresh([row("1/8", in: "INBOX", letter: 8),
                                               row("1/90", in: "INBOX", letter: 90)]).map(\.id),
                       ["1/8"], "a Refresh after a narrower answer dropped it")
    }

    // MARK: - The wiring

    /// The list asks for the previews `showResults` says are still to come,
    /// and for a page's only where it has none; an answer that came late is
    /// set aside for the list's letters, and one in time is drawn into its
    /// group's folder alone. Read from the source: the controller is UIKit.
    func testTheListAsksOnlyForTheHitsWithNoPreviewAndSetsALateAnswerAside() throws {
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertTrue(list.contains("searchFailed = false searchShown = text let move = showingResults() "
                                    + "let unpreviewed = letters.showResults(hits) "
                                    + "reachedOldestMessage = hits.count < Self.pageSize"))
        XCTAssertTrue(list.contains("placePull() loadPreviews(for: unpreviewed) }"))
        XCTAssertFalse(list.contains("loadPreviews(for: hits"))
        XCTAssertTrue(list.contains("let fresh = self.letters.appendPage(older, toResults: searching) "
                                    + "guard !fresh.isEmpty else { return } self.regroup() "
                                    + "self.loadPreviews(for: self.letters.toDraw(fresh)) }"))
        XCTAssertFalse(list.contains("fresh.filter { $0.preview.isEmpty }"))
        XCTAssertTrue(list.contains("aside: { @MainActor previews, group in "
                                    + "self?.letters.previewsCameLate(previews, in: group.mailboxID, "
                                    + "for: rows) })"))
        XCTAssertTrue(list.contains("apply: { @MainActor previews, group in "
                                    + "self?.apply(previews, in: group.mailboxID) },"))
        XCTAssertTrue(list.contains("private func apply(_ previews: [String: String], in mailboxID: String) { "
                                    + "letters.apply(previews: previews, in: mailboxID)"))
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
        func pass(_ rows: [MessageSummary],
                  apply: ([String: String], String) -> Void) async -> Pass {
            server.clearLog()
            await PreviewPass.run(PreviewPass.groups(for: rows),
                                  fetch: { try await repository.previews(for: $0, in: $1) },
                                  isCurrent: { true },
                                  apply: { apply($0, $1.mailboxID) })
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
            _ = await pass(list.fetchedAfresh(inbox)) { list.apply(previews: $0, in: $1) }
            var steps: [Pass] = []
            for text in typed {
                let hits = try await repository.search(in: "inbox", query: text, scope: scope,
                                                       beforeUID: nil, limit: 50)
                let shown = list.showResults(hits)
                var step = await pass(carrying ? shown : hits) { list.apply(previews: $0, in: $1) }
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

    /// The UIDs a preview FETCH in `log` names, each with the folder it
    /// was asked of: `UID FETCH 83185,83701 (UID BODY.PEEK[1]<0.2048>)`.
    private func previewsAsked(in log: [ScriptedIMAPServer.LogEntry]) -> [(folder: String?, uid: UInt32)] {
        log.filter { $0.verb == "UID FETCH" && $0.command.contains("BODY.PEEK[")
                     && $0.command.contains("]<0.") }
            .flatMap { entry -> [(folder: String?, uid: UInt32)] in
                let set = entry.command.split(separator: " ")[2]
                return set.split(separator: ",").flatMap { range -> [UInt32] in
                    let ends = range.split(separator: ":").compactMap { UInt32($0) }
                    guard let low = ends.first, let high = ends.last, low <= high else { return [] }
                    return Array(low...high)
                }.map { (entry.selected, $0) }
            }
    }

    /// Two empty drafts to Peyton among a search's hits, as the round on
    /// the test iPad found them: one of two bytes, as those were, and one
    /// of none. "Pey" typed, then t, o and n, each pause an answer and its
    /// pass to the end, in All Mailboxes from the Inbox's page drawn: the
    /// two-byte draft's preview is asked for once in all, at "Pey", and
    /// answered with none, and the other's never, the server sizing its
    /// words at nothing; no pause after the first asks anything. Then
    /// Drafts, opened and refreshed three times: the same, once in all.
    @MainActor
    func testAnEmptyDraftAmongTheHitsIsAskedForOnceHoweverManyPauses() async throws {
        let server = ScriptedIMAPServer(inboxCount: 12)
        let peyton = Server.Address(name: "Peyton Lane", address: "peyton.lane@example.com")
        let draftFlags: Set<String> = ["\\Draft", "\\Seen"]
        func letter(_ stamp: TimeInterval, from: Server.Address, to: Server.Address, _ subject: String,
                    text: String, flags: Set<String> = ["\\Seen"]) -> Server.Letter {
            Server.Letter(from: from, to: [to], subject: subject,
                          date: Server.newestDate.addingTimeInterval(stamp), text: text, flags: flags,
                          messageID: "<emptydraft-\(Int(stamp))@example.org>")
        }
        server.deliver(letter(3_600, from: peyton, to: Server.owner, "Lunch", text: "Noon suits.\r\n"),
                       to: [Server.inbox, Server.allMail])
        server.deliver(letter(7_200, from: Server.owner, to: peyton, "Re: Lunch", text: "See you then.\r\n"),
                       to: [Server.sent, Server.allMail])
        let twoBytes = server.deliver(letter(10_800, from: Server.owner, to: peyton, "", text: "\r\n",
                                             flags: draftFlags),
                                      to: [Server.drafts, Server.allMail])
        let noBytes = server.deliver(letter(14_400, from: Server.owner, to: peyton, "", text: "",
                                            flags: draftFlags),
                                     to: [Server.drafts, Server.allMail])
        let suite = "SearchPreviewsTests.emptyDraft"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = IMAPMailRepository(account: server.account, password: server.password,
                                            transport: server.transportFactory,
                                            recipients: RecipientBook(defaults: defaults),
                                            shelf: keptShelf(for: server.account))

        /// The previews `rows` are still to be asked for, asked as the list
        /// asks, and the UIDs each FETCH named.
        func pass(_ rows: [MessageSummary], into list: ListLetters) async -> [(folder: String?, uid: UInt32)] {
            server.clearLog()
            await PreviewPass.run(PreviewPass.groups(for: rows),
                                  fetch: { try await repository.previews(for: $0, in: $1) },
                                  isCurrent: { true },
                                  apply: { list.apply(previews: $0, in: $1.mailboxID) })
            return previewsAsked(in: server.log)
        }
        func times(_ asked: [(folder: String?, uid: UInt32)], _ folder: String, _ uid: UInt32?) -> Int {
            asked.filter { $0.folder == folder && $0.uid == uid }.count
        }

        let list = ListLetters()
        let inbox = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        _ = await pass(list.fetchedAfresh(inbox), into: list)
        var everyAsked: [(folder: String?, uid: UInt32)] = []
        var rowsEach: [Int] = []
        var fetchedEach: [Int] = []
        for text in ["Pey", "Peyt", "Peyto", "Peyton"] {
            let hits = try await repository.search(in: "inbox", query: text, scope: .allMailboxes,
                                                   beforeUID: nil, limit: 50)
            XCTAssertEqual(hits.count, 4, text)
            let toDraw = list.showResults(hits)
            rowsEach.append(toDraw.count)
            let asked = await pass(toDraw, into: list)
            fetchedEach.append(asked.count)
            everyAsked += asked
            XCTAssertEqual(list.results?.filter { $0.preview.isEmpty }.count, 2, text)
        }
        let allMail = Server.allMail
        XCTAssertEqual(times(everyAsked, allMail, twoBytes[allMail]), 1, "the two-byte draft, once in all")
        XCTAssertEqual(times(everyAsked, allMail, noBytes[allMail]), 0, "the draft of none, never")
        XCTAssertEqual(rowsEach, [4, 0, 0, 0], "no hit handed to the pass after the first pause")
        XCTAssertEqual(fetchedEach, [3, 0, 0, 0])

        let drafts = ListLetters()
        var draftsAsked: [(folder: String?, uid: UInt32)] = []
        var draftRowsEach: [Int] = []
        for _ in 0..<4 {
            let page = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 50)
            let toDraw = drafts.fetchedAfresh(page)
            draftRowsEach.append(toDraw.count)
            draftsAsked += await pass(toDraw, into: drafts)
        }
        XCTAssertEqual(times(draftsAsked, Server.drafts, twoBytes[Server.drafts]), 1,
                       "opened, and refreshed three times: once in all")
        XCTAssertEqual(times(draftsAsked, Server.drafts, noBytes[Server.drafts]), 0)
        XCTAssertEqual(draftRowsEach, [4, 0, 0, 0])
        print("B-135 empty drafts: hits handed to the pass \(rowsEach), UIDs FETCHed \(fetchedEach), "
              + "the two-byte draft's \(times(everyAsked, allMail, twoBytes[allMail])); Drafts opened "
              + "and refreshed three times: rows \(draftRowsEach), the two-byte draft's "
              + "\(times(draftsAsked, Server.drafts, twoBytes[Server.drafts]))")
        XCTAssertEqual(server.violations, [])
    }

    /// Over the scripted server, the Inbox paged by five. Its first page's
    /// previews come after he has begun a search, and are set aside, as the
    /// list sets them; "Peyton" in Current Mailbox finds a letter on its
    /// second page, not loaded, and draws it; Cancel; then the second page,
    /// scrolled to. Cancel asks for the first page's rows again and draws
    /// them, and the second page asks for the letter's row once and draws
    /// its words: no row left two grey lines.
    @MainActor
    func testFolderRowsWhoseLettersWereDrawnElsewhereAreAskedForAndDrawn() async throws {
        let server = ScriptedIMAPServer(inboxCount: 12)
        let peyton = Server.Address(name: "Peyton Lane", address: "peyton.lane@example.com")
        func letter(_ stamp: TimeInterval, from: Server.Address, _ subject: String,
                    text: String) -> Server.Letter {
            Server.Letter(from: from, to: [Server.owner], subject: subject,
                          date: Server.newestDate.addingTimeInterval(stamp), text: text, flags: ["\\Seen"],
                          messageID: "<keptwords-\(Int(stamp))@example.org>")
        }
        let lunch = server.deliver(letter(3_600, from: peyton, "Lunch", text: "Noon suits me fine.\r\n"),
                                   to: [Server.inbox, Server.allMail])
        for i in 0..<6 {
            _ = server.deliver(letter(7_200 + Double(i) * 60, from: Self.margaret, "Garden \(i)",
                                      text: "Roses \(i).\r\n"),
                               to: [Server.inbox, Server.allMail])
        }
        let suite = "SearchPreviewsTests.keptWords"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = IMAPMailRepository(account: server.account, password: server.password,
                                            transport: server.transportFactory,
                                            recipients: RecipientBook(defaults: defaults),
                                            shelf: keptShelf(for: server.account))
        let list = ListLetters()
        func pass(_ rows: [MessageSummary]) async -> [(folder: String?, uid: UInt32)] {
            server.clearLog()
            await PreviewPass.run(PreviewPass.groups(for: rows),
                                  fetch: { try await repository.previews(for: $0, in: $1) },
                                  isCurrent: { true },
                                  apply: { list.apply(previews: $0, in: $1.mailboxID) })
            return previewsAsked(in: server.log)
        }

        let first = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 5)
        XCTAssertEqual(first.map(\.subject), (1..<6).reversed().map { "Garden \($0)" })
        let firstAsked = list.fetchedAfresh(first)
        XCTAssertEqual(firstAsked.count, 5)
        // The pass's first look finds the list current; its answer comes after
        // the search has replaced it.
        var looks = 0
        server.clearLog()
        await PreviewPass.run(PreviewPass.groups(for: firstAsked),
                              fetch: { try await repository.previews(for: $0, in: $1) },
                              isCurrent: { looks += 1; return looks == 1 },
                              apply: { list.apply(previews: $0, in: $1.mailboxID) },
                              aside: { list.previewsCameLate($0, in: $1.mailboxID, for: firstAsked) })
        XCTAssertEqual(previewsAsked(in: server.log).count, 5, "the first page's answer, set aside")
        XCTAssertEqual(list.folder.map(\.preview), Array(repeating: "", count: 5))

        let hits = try await repository.search(in: "inbox", query: "Peyton", scope: .currentMailbox,
                                               beforeUID: nil, limit: 50)
        XCTAssertEqual(hits.map(\.subject), ["Lunch"])
        let hitAsked = await pass(list.showResults(hits))
        XCTAssertEqual(hitAsked.map(\.uid), [lunch[Server.inbox]].compactMap { $0 })
        XCTAssertEqual(list.results?.map(\.preview), ["Noon suits me fine."])

        let cancelAsked = await pass(list.endSearch())
        XCTAssertEqual(cancelAsked.count, 5, "Cancel asks for the first page's rows")
        XCTAssertEqual(list.folder.map(\.preview), (1..<6).reversed().map { "Roses \($0)." })

        let second = try await repository.listMessages(in: "inbox", beforeUID: list.cursor, limit: 5)
        let row = try XCTUnwrap(second.first { $0.subject == "Lunch" }, "the second page holds it")
        XCTAssertEqual(SearchPreviews.key(row), SearchPreviews.key(hits[0]), "the same letter")
        let fresh = list.appendPage(second, toResults: false)
        let pageAsked = await pass(list.toDraw(fresh))
        XCTAssertEqual(pageAsked.filter { $0.uid == lunch[Server.inbox] }.count, 1,
                       "the second page asks for the letter's row")
        XCTAssertEqual(list.folder.first { $0.id == row.id }?.preview, "Noon suits me fine.")
        XCTAssertFalse(list.folder.contains { $0.preview.isEmpty }, "no row left two grey lines")
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
