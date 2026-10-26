import XCTest
@testable import Blackmail

/// A reply carries the original's files when it goes to someone the
/// original did not, as Mail's When Adding Recipients does, and Forward
/// asks Mail's question (B-107).
///
/// The rule is `ReplyFiles`, pure, and run here; the composer and the pane
/// that call it are UIKit and never build on this host, so their wiring is
/// read from the source in `ReplyFilesWiringTests`, below. What a reply
/// carrying rows sends is `RichQuoteTests`' and `RichQuoteRepositoryTests`';
/// the Trash is `KeptReferencesTests`'.
final class ReplyFilesTests: XCTestCase {

    /// His two addresses: the account's, and a second one of his.
    private let sam = "Sam Example <sam@example.com>"
    private let second = "sam.at.home@example.net"
    private let jane = "Jane Example <jane@example.com>"
    private let carlo = "Carlo <carlo@example.org>"
    private let pat = "pat@example.org"

    private let garden = Attachment(id: "2", filename: "garden.jpg", mimeType: "image/jpeg",
                                    size: 1200, contentID: "ii_garden01", isInline: true)
    private let logo = Attachment(id: "3", filename: "logo.png", mimeType: "image/png",
                                  size: 600, contentID: "sig-logo", isInline: true)
    private let programme = Attachment(id: "4", filename: "Programme.pdf",
                                       mimeType: "application/pdf", size: 22)

    /// Jane's letter to him, Carlo copied: her photograph and her logo
    /// shown in its body, and a PDF. `authors`, a From of several, each
    /// its own entry, the first of them the sender.
    private func letter(from: String? = nil, authors: [String]? = nil, to: [String]? = nil,
                        cc: [String]? = nil, bcc: [String] = [], replyTo: [String] = [],
                        attachments: [Attachment]? = nil) -> Message {
        let author = from ?? authors?.first ?? jane
        return Message(id: "600001/41", mailboxID: "INBOX", sender: author,
                       senderAddress: MailFormat.bareAddress(author),
                       to: to ?? [sam], cc: cc ?? [carlo], bcc: bcc, replyTo: replyTo,
                       from: authors ?? [author], subject: "The garden",
                       date: Date(timeIntervalSince1970: 1_790_000_000),
                       textBody: "Here is the garden.", htmlBody: nil,
                       attachments: attachments ?? [garden, logo, programme],
                       messageID: "<garden-1@example.com>", gmailMessageID: 1_790_000_000_041)
    }

    private func rule(_ m: Message? = nil) throws -> ReplyFiles {
        try XCTUnwrap(ReplyFiles(replyingTo: m ?? letter()))
    }

    /// The rows after the recipients change, `attachments` before; the
    /// same rows when nothing changes.
    private func follow(_ files: inout ReplyFiles, to: [String], cc: [String] = [],
                        bcc: [String] = [], in attachments: [DraftAttachment] = []) -> [DraftAttachment] {
        files.recipientsChanged(to: to, cc: cc, bcc: bcc, in: attachments) ?? attachments
    }

    private func reply(_ m: Message, all: Bool) -> Draft {
        Draft.replying(to: m, all: all, mine: OwnAddresses(["sam@example.com", second]))
    }

    private var photo: DraftAttachment {
        DraftAttachment(source: .localFile(URL(fileURLWithPath: "/staged/Photo.jpg")),
                        filename: "Photo.jpg", mimeType: "image/jpeg", size: 4000)
    }

    // MARK: - No one new

    /// Reply goes to her, Reply All to her and Carlo: no one the letter did
    /// not go to, and no rows.
    func testReplyAndReplyAllAddNoOne() throws {
        for all in [false, true] {
            let draft = reply(letter(), all: all)
            var files = try rule()
            XCTAssertFalse(files.wouldAdd(to: draft.to, cc: draft.cc, bcc: draft.bcc), "all: \(all)")
            XCTAssertNil(files.recipientsChanged(to: draft.to, cc: draft.cc, bcc: draft.bcc, in: []))
            XCTAssertEqual(files.state, .notCarried)
        }
    }

    /// A letter of his own, from Sent Mail, answered to whom it went.
    func testAReplyToHisOwnLetterAddsNoOne() throws {
        let his = letter(from: sam, to: [jane], cc: [])
        let draft = reply(his, all: false)
        XCTAssertEqual(draft.to, [jane])
        var files = try rule(his)
        XCTAssertNil(files.recipientsChanged(to: draft.to, cc: draft.cc, bcc: draft.bcc, in: []))
    }

    /// Her Reply-To, the authors of a letter written by several, its Bcc,
    /// and the address alone where there is no name, are its people.
    func testEveryoneTheLetterNamesIsAmongItsPeople() throws {
        let m = letter(from: "Jane Example <jane@example.com>, Ann <ann@example.com>",
                       to: ["undisclosed-recipients:;"], cc: [],
                       bcc: ["Bea <bea@example.com>"], replyTo: ["Club <club@example.org>"])
        XCTAssertEqual(ReplyFiles.people(of: m),
                       ["jane@example.com", "ann@example.com", "bea@example.com",
                        "club@example.org"])
        var files = try rule(m)
        for one in ["jane@example.com", "Ann <ann@example.com>", "BEA@example.com",
                    "club@example.org"] {
            XCTAssertNil(files.recipientsChanged(to: [one], cc: [], bcc: [], in: []), one)
        }
    }

    /// A letter whose names are broken over lines, as `ReplyAddressingTests`
    /// feeds them in: in a From of two, a Reply-To, a To, a Cc, and an
    /// address itself. The reply goes to each on one line, and each is among
    /// the letter's people, so neither Reply nor Reply All opens with a row,
    /// nor would Send put them in. Read from each entry's first line, these
    /// were a name alone, or another address, and the reply's own To or Cc
    /// was someone new.
    func testNamesBrokenOverLinesAreAmongThePeople() throws {
        for gap in ["\n", "\r\n", "\u{2028}", "\u{0085}"] {
            let letters: [(String, Message, String)] = [
                ("a From of two", letter(authors: ["Jane\(gap)Example <jane@example.com>",
                                                   "Ann\(gap)Other <ann@example.com>"]),
                 "Ann Other <ann@example.com>"),
                ("a Reply-To", letter(replyTo: ["Club\(gap)News <club@example.org>"]),
                 "Club News <club@example.org>"),
                ("a To", letter(to: [sam, "<other@example.net>\(gap)Pat <pat@example.org>"]),
                 "\"<other@example.net> Pat\" <pat@example.org>"),
                ("a Cc", letter(cc: ["Carlo\(gap)Rossi <carlo@example.org>"]),
                 "Carlo Rossi <carlo@example.org>"),
                ("an address", letter(cc: ["Carlo <carlo@exa\(gap)mple.org>"]),
                 "Carlo <carlo@example.org>"),
            ]
            for (field, m, entry) in letters {
                let said = "\(field), \(gap.debugDescription)"
                var addressed: [String] = []
                for all in [false, true] {
                    let draft = reply(m, all: all)
                    addressed += draft.to + draft.cc
                    var files = try rule(m)
                    XCTAssertFalse(files.wouldAdd(to: draft.to, cc: draft.cc, bcc: draft.bcc),
                                   "\(said), all: \(all), people \(files.people.sorted())")
                    XCTAssertNil(files.recipientsChanged(to: draft.to, cc: draft.cc, bcc: draft.bcc,
                                                         in: []), "\(said), all: \(all)")
                    XCTAssertEqual(files.state, .notCarried, said)
                }
                XCTAssertTrue(addressed.contains(entry), "\(said): the reply goes to it, \(addressed)")
            }
        }
    }

    /// The same address in another case, or with another name or none, is
    /// the same person. An entry with no address in it is no one.
    func testTheSameAddressWrittenAnotherWayIsNoOneNew() throws {
        var files = try rule()
        for to in [["JANE@EXAMPLE.COM"], ["Janie <Jane@Example.com>"], ["jane@example.com"],
                   ["\"Example, Jane\" <jane@example.com>"], ["Carlo C. <CARLO@example.org>"],
                   ["undisclosed-recipients:;"], ["Jane"], [""]] {
            XCTAssertFalse(files.wouldAdd(to: to, cc: [], bcc: []), "\(to)")
            XCTAssertNil(files.recipientsChanged(to: to, cc: [], bcc: [], in: []), "\(to)")
        }
        XCTAssertEqual(files.state, .notCarried)
    }

    // MARK: - Someone new

    /// A stranger in Cc, a Bcc, and his own second address, which the
    /// letter did not go to: each puts the rows in, after his own photo.
    func testAStrangerInCcOrBccOrHisSecondAddressPutsTheRowsIn() throws {
        let draft = reply(letter(), all: false)
        for (cc, bcc) in [([pat], [String]()), ([], [pat]), ([second], []),
                          ([carlo, "Pat <PAT@example.org>"], [])] {
            var files = try rule()
            XCTAssertTrue(files.wouldAdd(to: draft.to, cc: cc, bcc: bcc), "\(cc) \(bcc)")
            let rows = files.recipientsChanged(to: draft.to, cc: cc, bcc: bcc, in: [photo])
            XCTAssertEqual(rows, [photo] + files.rows, "\(cc) \(bcc)")
            XCTAssertEqual(files.state, .carriedAuto)
            // Once in, more people put in nothing more.
            XCTAssertNil(files.recipientsChanged(to: draft.to, cc: cc + ["x@example.net"],
                                                 bcc: bcc, in: rows ?? []))
        }
    }

    /// The stranger taken off again: the rule's rows go, his photo stays,
    /// and the rule is where it began, so the next stranger puts them in
    /// again.
    func testTakingTheStrangerOffTakesOnlyTheRulesRowsOut() throws {
        var files = try rule()
        let added = follow(&files, to: [jane], cc: [pat], in: [photo])
        XCTAssertEqual(added.count, 4)
        let back = follow(&files, to: [jane], in: added)
        XCTAssertEqual(back, [photo])
        XCTAssertEqual(files.state, .notCarried)
        XCTAssertEqual(follow(&files, to: [jane], bcc: [second], in: back), [photo] + files.rows)
    }

    /// A Remove on one of the rule's rows is his: the rule stops for the
    /// letter, and what is left stays whoever it goes to. A Remove of his
    /// own photo changes nothing of the rule.
    func testARemoveIsHisChoiceAndTheRuleStops() throws {
        var files = try rule()
        var rows = follow(&files, to: [jane], cc: [pat], in: [photo])
        files.removed(photo)
        rows.removeAll { $0 == photo }
        XCTAssertEqual(files.state, .carriedAuto, "his own photo is not the rule's")

        let pdf = try XCTUnwrap(rows.last)
        XCTAssertEqual(pdf.filename, "Programme.pdf")
        files.removed(pdf)
        rows.removeLast()
        XCTAssertEqual(files.state, .hisChoice)

        XCTAssertNil(files.recipientsChanged(to: [jane], cc: [], bcc: [], in: rows),
                     "the stranger gone, the rest stays")
        XCTAssertFalse(files.wouldAdd(to: [jane], cc: [], bcc: []))
        XCTAssertNil(files.recipientsChanged(to: [jane], cc: [pat], bcc: [], in: rows))
        XCTAssertFalse(files.wouldAdd(to: [jane], cc: [pat], bcc: []))
        XCTAssertEqual(rows.map(\.filename), ["garden.jpg", "logo.png"])
    }

    /// A Remove before any row of the rule's is in changes nothing.
    func testARemoveWhileNothingIsCarriedChangesNothing() throws {
        var files = try rule()
        files.removed(files.rows[0])
        XCTAssertEqual(files.state, .notCarried)
        XCTAssertTrue(files.wouldAdd(to: [pat], cc: [], bcc: []))
    }

    /// `wouldAdd` changes nothing, and says what `recipientsChanged` then
    /// does, in every state, for each set of people.
    func testWouldAddChangesNothingAndAgreesWithTheRule() throws {
        let sets: [([String], [String], [String])] = [
            ([jane], [], []), ([jane], [pat], []), ([], [], [pat]), ([second], [], []),
            ([jane, carlo], [], []), ([], [], []), (["JANE@example.com"], ["Pat"], []),
        ]
        var states: [ReplyFiles] = [try rule()]
        var carried = try rule()
        _ = follow(&carried, to: [pat])
        states.append(carried)
        var his = carried
        his.removed(his.rows[0])
        states.append(his)
        XCTAssertEqual(states.map(\.state), [.notCarried, .carriedAuto, .hisChoice])
        for start in states {
            for (to, cc, bcc) in sets {
                let asked = start
                let would = asked.wouldAdd(to: to, cc: cc, bcc: bcc)
                XCTAssertEqual(asked, start, "wouldAdd changes nothing")
                var files = start
                let before = start.state == .notCarried ? [] : files.rows
                let after = files.recipientsChanged(to: to, cc: cc, bcc: bcc, in: before)
                XCTAssertEqual(would, after.map { $0.count > before.count } ?? false,
                               "\(start.state) \(to) \(cc) \(bcc)")
            }
        }
    }

    /// What he is still typing, never made a bubble, is not followed as he
    /// types it; at Send, everyone the letter would go to is asked about,
    /// and a stranger typed there puts the rows in.
    func testAStrangerStillBeingTypedCountsAtSend() throws {
        var cc = RecipientBubbles(entries: [carlo])
        cc.type("pat@example.org")
        XCTAssertEqual(cc.entries, [carlo], "not a bubble")
        XCTAssertEqual(cc.recipients, [carlo, pat])

        var files = try rule()
        XCTAssertNil(files.recipientsChanged(to: [jane], cc: cc.entries, bcc: [], in: []),
                     "the bubbles alone: no one new")
        XCTAssertTrue(files.wouldAdd(to: [jane], cc: cc.recipients, bcc: []))
        XCTAssertEqual(files.recipientsChanged(to: [jane], cc: cc.recipients, bcc: [], in: []),
                       files.rows)
        // Made a bubble by leaving the field, the same people: nothing more.
        cc.finish(leaving: true)
        XCTAssertNil(files.recipientsChanged(to: [jane], cc: cc.entries, bcc: [], in: files.rows))
    }

    // MARK: - The rows

    /// The rule's rows are a forward's, byte for byte, made by the one
    /// mapper: every part, the pictures the body shows among them. Don’t
    /// Include leaves a forward those pictures alone.
    func testTheRowsAreAForwardsByteForByte() throws {
        let m = letter()
        let files = try rule(m)
        XCTAssertEqual(files.rows, Draft.forwarding(m).attachments)
        XCTAssertEqual(files.rows, DraftAttachment.carried(from: m))
        XCTAssertEqual(files.rows.map(\.filename), ["garden.jpg", "logo.png", "Programme.pdf"])
        XCTAssertEqual(files.rows.map(\.size), [1200, 600, 22])
        for (row, part) in zip(files.rows, m.attachments) {
            guard case let .messagePart(id, mailbox, section, gmail) = row.source else {
                return XCTFail("\(row.filename) is a part of the original")
            }
            XCTAssertEqual([id, mailbox, section], ["600001/41", "INBOX", part.id])
            XCTAssertEqual(gmail, 1_790_000_000_041)
            XCTAssertEqual(row.mimeType, part.mimeType)
        }
        XCTAssertEqual(Draft.forwarding(m, includingFiles: false).attachments.map(\.filename),
                       ["garden.jpg", "logo.png"])
        XCTAssertEqual(Draft.forwarding(m, includingFiles: true).attachments, files.rows)
        // A reply opens with none of them.
        XCTAssertEqual(reply(m, all: true).attachments, [])
    }

    /// An original with no parts has nothing to carry, and no rule.
    func testAnOriginalWithNoPartsHasNoRule() {
        XCTAssertNil(ReplyFiles(replyingTo: letter(attachments: [])))
        XCTAssertNil(ReplyFiles.opening(letter(attachments: [])).rule)
        XCTAssertNotNil(ReplyFiles(replyingTo: letter(attachments: [logo])))
    }

    /// A reply carrying a megabyte or more of the original's parts waits in
    /// the Outbox for his Refresh, as a forward does (B-072).
    func testAReplyCarryingAMegabyteWaitsAsAForwardDoes() throws {
        let big = Attachment(id: "2", filename: "Scan.pdf", mimeType: "application/pdf",
                             size: 1_200_000)
        let small = Attachment(id: "2", filename: "Scan.pdf", mimeType: "application/pdf",
                               size: 600_000)
        for (part, large) in [(big, true), (small, false)] {
            let m = letter(attachments: [part])
            var draft = reply(m, all: false)
            draft.cc = [pat]
            func waits(_ draft: Draft) -> Bool {
                LocalDraft(key: "r", draft: draft, version: "1", tried: [], unfinished: false,
                           keptAt: Date(), account: nil, gone: false).fetchesLarge
            }
            XCTAssertFalse(waits(draft), "no rows, nothing to fetch")
            var files = try rule(m)
            draft.attachments = follow(&files, to: draft.to, cc: draft.cc)
            XCTAssertEqual(waits(draft), large, "\(part.size ?? 0)")
        }
    }

    // MARK: - The modes and the question

    /// Built to Mail's factory default, his iPad's setting not yet read.
    /// Each of Mail's four answers: Never carries nothing and follows
    /// nothing; When Adding Recipients opens with none and follows; Always
    /// opens with them and follows nothing; Ask opens with them for
    /// Include, and with none for Don’t Include or with no question.
    func testTheFourModes() throws {
        XCTAssertEqual(ReplyFiles.mode, .whenAddingRecipients)
        let m = letter()
        let rows = DraftAttachment.carried(from: m)

        var opening = ReplyFiles.opening(m, mode: .never)
        XCTAssertEqual(opening.rows, [])
        XCTAssertNil(opening.rule)

        opening = ReplyFiles.opening(m, mode: .whenAddingRecipients)
        XCTAssertEqual(opening.rows, [])
        XCTAssertEqual(opening.rule, try rule(m))
        XCTAssertEqual(ReplyFiles.opening(m).rule, try rule(m), "the default")

        opening = ReplyFiles.opening(m, mode: .always)
        XCTAssertEqual(opening.rows, rows)
        XCTAssertNil(opening.rule)

        for (included, expected) in [(true, rows), (false, []), (nil, [])] as [(Bool?, [DraftAttachment])] {
            opening = ReplyFiles.opening(m, mode: .ask, included: included)
            XCTAssertEqual(opening.rows, expected, "\(String(describing: included))")
            XCTAssertNil(opening.rule)
        }
    }

    /// Forward asks only of a letter with a file the header lists: a PDF,
    /// one sent inline as Apple Mail sends one, a picture sent as a file.
    /// A signature's logo, or a photograph the body shows, alone asks
    /// nothing. Reply and Reply All ask only under Ask.
    func testForwardAsksOnlyWhenTheHeaderListsAFile() {
        let inlinePDF = Attachment(id: "5", filename: "Menu.pdf", mimeType: "application/pdf",
                                   size: 900, isInline: true)
        let attachedPhoto = Attachment(id: "6", filename: "IMG_1.jpg", mimeType: "image/jpeg",
                                       size: 900, contentID: "photo1")
        for (parts, asks) in [([programme], true), ([inlinePDF], true), ([attachedPhoto], true),
                              ([logo], false), ([garden, logo], false), ([], false),
                              ([garden, programme], true)] {
            let m = letter(attachments: parts)
            XCTAssertEqual(ReplyFiles.forwardAsks(m), asks, "\(parts.map(\.filename))")
            XCTAssertEqual(ReplyFiles.asks(m, mode: .ask), asks)
            for mode in [ReplyFiles.Mode.never, .whenAddingRecipients, .always] {
                XCTAssertFalse(ReplyFiles.asks(m, mode: mode))
            }
            XCTAssertFalse(ReplyFiles.asks(m), "not under the default")
        }
    }

    /// Mail's words for the question and its answers, "Don’t Include" with
    /// Mail's curly apostrophe (B-144).
    func testTheQuestionIsInMailsWords() {
        XCTAssertEqual(ReplyFiles.question, "Include attachments from original message?")
        XCTAssertEqual(ReplyFiles.include, "Include")
        XCTAssertEqual(ReplyFiles.dontInclude, "Don\u{2019}t Include")
        XCTAssertEqual(Array(ReplyFiles.dontInclude.unicodeScalars)[3].value, 0x2019)
        XCTAssertFalse(ReplyFiles.dontInclude.contains("'"), "no straight apostrophe")
    }
}

/// The composer's and the pane's side of B-107, which are UIKit and never
/// build on this host, read from the source as `SentSoundTests` reads it:
/// comment lines out, and runs of white space as one space.
final class ReplyFilesWiringTests: XCTestCase {

    private static let composer = "Blackmail/UI/ComposeViewController.swift"
    private static let pane = "Blackmail/UI/MessageDetailViewController.swift"

    private var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources")
    }

    private func source(_ path: String) throws -> String {
        try code(of: sources.appendingPathComponent(path))
    }

    private func code(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    /// Every Swift file under `Sources`, by its path under it, read as code.
    private func everySource() throws -> [String: String] {
        let root = sources.standardizedFileURL.path + "/"
        var found: [String: String] = [:]
        let walk = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = walk?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            found[String(url.standardizedFileURL.path.dropFirst(root.count))] = try code(of: url)
        }
        return found
    }

    private func count(_ text: String, in code: String) -> Int {
        code.components(separatedBy: text).count - 1
    }

    /// The text of the function that begins with `head`, to the next
    /// function's start.
    private func function(_ head: String, in code: String) throws -> String {
        let start = try XCTUnwrap(code.range(of: head), head)
        let rest = code[start.upperBound...]
        let end = [rest.range(of: "@objc private func"), rest.range(of: " private func "),
                   rest.range(of: " func ")].compactMap { $0?.lowerBound }.min() ?? rest.endIndex
        return String(code[start.lowerBound..<end])
    }

    /// The rule follows the bubbles when they change under his hand, when
    /// he leaves a field (which makes a bubble of what he typed and sends
    /// nothing else), after a pick, and as the fields are first shown,
    /// before the letter is taken as it opened. Only while the sheet is his
    /// to change, and from the bubbles, never what he is still typing.
    func testTheComposerFollowsTheBubblesFromEachChange() throws {
        let code = try source(Self.composer)
        for line in [
            "private var replyFiles: ReplyFiles?",
            "init(repository: MailRepository, draft: Draft, key: String? = nil, "
                + "replyFiles: ReplyFiles? = nil) { self.repository = repository "
                + "self.draft = ComposeForm.bounded(draft) "
                + "self.replyFiles = replyFiles",
            "field.addTarget(self, action: #selector(addressEditingEnded(_:)), for: .editingDidEnd)",
            "field.addTarget(self, action: #selector(addressEditingChanged(_:)), for: .editingChanged)",
            "@objc private func addressEditingChanged(_ field: RecipientField) { activeAddressField = field "
                + "refreshSuggestions(after: .typed) updateSend() followRecipients() }",
            "@objc private func addressEditingEnded(_ field: RecipientField) { followRecipients()",
            "refreshSuggestions(after: .picked) updateSend() letterEdited() followRecipients() }",
            "followRecipients() opened = currentLetter()",
            "guard actions.isWriting, var files = replyFiles, "
                + "let rows = files.recipientsChanged(to: to ?? toField.bubbles.entries, "
                + "cc: cc ?? ccField.bubbles.entries, bcc: bcc ?? bccField.bubbles.entries, "
                + "in: draft.attachments) else { return nil } replyFiles = files",
            "draft.attachments = rows rebuildAttachments() letterEdited() if let first, to == nil {",
            "let removed = draft.attachments.remove(at: sender.tag) replyFiles?.removed(removed) "
                + "rebuildAttachments() letterEdited()",
        ] {
            XCTAssertTrue(code.contains(line), line)
        }
        XCTAssertEqual(count("followRecipients()", in: code), 4, "the four places, by the bubbles")
        XCTAssertEqual(count("followRecipients(to: draft.to, cc: draft.cc, bcc: draft.bcc)", in: code), 1)
        XCTAssertFalse(code.contains("toField.recipients, cc: ccField.recipients, bcc: bccField.recipients, in:"))
        let field = try source("Blackmail/UI/RecipientField.swift")
        XCTAssertTrue(field.contains("bubbles.finish(leaving: true) keepMenu() input.text = \"\" "
            + "if had != bubbles { rebuild() } sendActions(for: .editingDidEnd) }"),
            "leaving the field makes a bubble and sends .editingDidEnd alone")
        let actions = try source("Blackmail/Mail/ComposeActions.swift")
        XCTAssertTrue(actions.contains("var isWriting: Bool { stage == .writing }"))
    }

    /// Send asks the rule about everyone the letter would go to, after the
    /// fields are read and before the letter is handed to its send; when it
    /// would put the rows in, they go in, the first is scrolled into the
    /// part of the sheet showing and VoiceOver taken to it, and nothing is
    /// sent.
    func testSendShowsTheRowsInsteadOfSendingWithoutThem() throws {
        let code = try source(Self.composer)
        let send = try function("@objc private func sendTapped()", in: code)
        let order = ["guard !actions.isSending else { return }",
                     "collect()",
                     "if replyFiles?.wouldAdd(to: draft.to, cc: draft.cc, bcc: draft.bcc) == true {",
                     "if let first = followRecipients(to: draft.to, cc: draft.cc, bcc: draft.bcc) {",
                     "showRow(at: first)",
                     "} return }",
                     "actions.send({ self.draft }, then: onDraftsChanged, draftSent: onDraftSent)"]
        var at = send.startIndex
        for step in order {
            let found = try XCTUnwrap(send.range(of: step, range: at..<send.endIndex), step)
            at = found.upperBound
        }
        XCTAssertEqual(count("actions.send(", in: code), 1)
        XCTAssertEqual(count(".wouldAdd(", in: code), 2, "Send's, and Save Draft's")
        XCTAssertEqual(count("showRow(at", in: code), 2, "made once, called from Send alone")
        XCTAssertTrue(code.contains("private func showRow(at index: Int) { view.layoutIfNeeded() "
            + "let rows = attachmentsStack.arrangedSubviews if rows.indices.contains(index) { "
            + "let row = rows[index] scroller.scrollRectToVisible(row.convert(row.bounds, to: scroller), "
            + "animated: true) } UIAccessibility.post(notification: .layoutChanged, "
            + "argument: attachmentWords(at: index)) }"), "laid out, scrolled to, then VoiceOver")
        XCTAssertTrue(code.contains("let rows = attachmentsStack.arrangedSubviews "
            + "guard rows.indices.contains(index) else { return nil } "
            + "return rows[index].subviews.first { $0 is UILabel }"))
    }

    /// Rows a bubble puts in are read out to VoiceOver, after what it is
    /// saying, without taking it from the field; at Send, and at Save
    /// Draft, which hand in what he typed, nothing is read out.
    func testRowsABubblePutsInAreReadOut() throws {
        let code = try source(Self.composer)
        let follow = try function("private func followRecipients(", in: code)
        XCTAssertTrue(follow.contains("letterEdited() if let first, to == nil { "
            + "let words = (first..<rows.count).compactMap { (attachmentWords(at: $0) as? UILabel)?.text } "
            + "UIAccessibility.post(notification: .announcement, argument: NSAttributedString( "
            + "string: words.joined(separator: \", \"), "
            + "attributes: [.accessibilitySpeechQueueAnnouncement: true])) } return first }"), follow)
        XCTAssertEqual(count("notification: .announcement", in: code), 1)
    }

    /// Save Draft asks the rule about everyone the letter would go to, what
    /// he typed and never made a bubble included, and the rows go into the
    /// draft it saves, before it is handed to the save.
    func testSaveDraftKeepsTheRowsTheRuleCallsFor() throws {
        let code = try source(Self.composer)
        XCTAssertTrue(code.contains("title: \"Save Draft\", style: .default) { [weak self] _ in "
            + "guard let self else { return } self.collect() let collected = self.draft "
            + "if self.replyFiles?.wouldAdd(to: collected.to, cc: collected.cc, bcc: collected.bcc) "
            + "== true { self.followRecipients(to: collected.to, cc: collected.cc, bcc: collected.bcc) } "
            + "self.actions.saveAndClose({ self.draft }, then: nil) }"))
        XCTAssertEqual(count("followRecipients(to: collected.to", in: code), 1)
    }

    /// Forward asks Mail's question only of a letter with files the header
    /// lists, at the Reply button, in Mail's words, with Cancel; Include
    /// and Don’t Include each begin the forward with their rows. Reply and
    /// Reply All ask only under Ask.
    func testForwardAsksMailsQuestionAtTheReplyButton() throws {
        let code = try source(Self.pane)
        for line in [
            "guard ReplyFiles.forwardAsks(m) else { return self.openCompose(replyTo: m, all: false, "
                + "forward: true) } self.askAboutFiles { [weak self] in self?.openCompose(replyTo: m, "
                + "all: false, forward: true, included: $0) }",
            "guard ReplyFiles.asks(m) else { return self.openCompose(replyTo: m, all: false, forward: false) }",
            "guard ReplyFiles.asks(m) else { return self.openCompose(replyTo: m, all: true, forward: false) }",
            // Over the row instead, from More's Reply on a row (B-156).
            "let sheet = UIAlertController(title: ReplyFiles.question, message: nil, "
                + "preferredStyle: .actionSheet) if let row { "
                + "sheet.popoverPresentationController?.sourceView = row.view "
                + "sheet.popoverPresentationController?.sourceRect = row.rect } else { "
                + "sheet.popoverPresentationController?.barButtonItem = actionItems[.reply] }",
            "sheet.addAction(UIAlertAction(title: ReplyFiles.include, style: .default) { _ in answer(true) })",
            "sheet.addAction(UIAlertAction(title: ReplyFiles.dontInclude, style: .default) { _ in "
                + "answer(false) }) sheet.addAction(UIAlertAction(title: \"Cancel\", style: .cancel)) "
                + "present(sheet, animated: true)",
            "draft = .forwarding(m, signature: signature, includingFiles: included ?? true)",
        ] {
            XCTAssertTrue(code.contains(line), line)
        }
        // The Reply button's sheet, and More's on a row (B-156).
        XCTAssertEqual(count("ReplyFiles.forwardAsks(", in: code), 2)
        XCTAssertEqual(count("self.askAboutFiles", in: code), 4)
        XCTAssertEqual(count("UIAlertController(title: ReplyFiles.question", in: code), 1)
        // Mail's words are said once, in `ReplyFiles`, and nowhere else.
        let all = try everySource()
        for words in ["Include attachments from original message?", "\"Don\u{2019}t Include\"",
                      "\"Include\""] {
            XCTAssertEqual(all.filter { $0.value.contains(words) }.keys.sorted(),
                           ["Blackmail/Mail/ReplyFiles.swift"], words)
        }
        // The straight apostrophe's answer is said nowhere (B-144).
        XCTAssertEqual(all.filter { $0.value.contains("\"Don't Include\"") }.keys.sorted(), [])
    }

    /// The pane's Reply and Reply All alone hand the composer the rule,
    /// with the rows the mode opens with; a forward, a new letter, a
    /// `mailto:` link, and a letter reopened from Drafts, the iPad or the
    /// Outbox are made without it and keep the rows they have.
    func testOnlyReplyAndReplyAllHandTheComposerTheRule() throws {
        let pane = try source(Self.pane)
        XCTAssertTrue(pane.contains(
            "draft = .replying(to: m, all: all, mine: OwnAddresses(account: account), "
                + "signature: signature) let opening = ReplyFiles.opening(m, included: included) "
                + "draft.attachments = opening.rows replyFiles = opening.rule"))
        XCTAssertTrue(pane.contains("let compose = ComposeViewController(repository: repository, "
            + "draft: draft, replyFiles: replyFiles)"))
        XCTAssertTrue(pane.contains("var replyFiles: ReplyFiles? if let m { if forward { "
            + "draft = .forwarding(m, signature: signature, includingFiles: included ?? true) } else {"),
            "a forward is made without it")
        XCTAssertEqual(count("replyFiles = ", in: pane), 1)
        XCTAssertEqual(count("ReplyFiles.opening(", in: pane), 1)
        let all = try everySource()
        let handing = all.filter { $0.value.contains("replyFiles: replyFiles)") }.keys.sorted()
        XCTAssertEqual(handing, [Self.pane])
        XCTAssertEqual(count("replyFiles: replyFiles)", in: pane), 1)
        let making = all.filter { $0.value.contains("ComposeViewController(repository:") }
        XCTAssertEqual(making.keys.sorted(), ["Blackmail/App/AppDelegate.swift",
                                              "Blackmail/UI/MessageDetailViewController.swift",
                                              "Blackmail/UI/MessageListViewController.swift"])
        XCTAssertEqual(count("ComposeViewController(repository:", in: pane), 2, "mailto: and openCompose")
        for other in ["Blackmail/App/AppDelegate.swift", "Blackmail/UI/MessageListViewController.swift"] {
            XCTAssertFalse(try XCTUnwrap(making[other]).contains("replyFiles"), other)
        }
        XCTAssertEqual(all.filter { $0.value.contains("ReplyFiles(replyingTo:") }.keys.sorted(),
                       ["Blackmail/Mail/ReplyFiles.swift"])
    }
}
