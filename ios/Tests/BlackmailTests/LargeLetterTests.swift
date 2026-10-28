import XCTest
@testable import Blackmail

/// A letter too large to fetch whole is opened without its files
/// (`IMAPMailRepository.loadMessage`, `IMAPClient.fetchLetterInPart`).
///
/// Above `largeLetterBytes` the reading pane is given the letter's header,
/// the first `largeLetterSectionBytes` of its text and of its HTML, and its
/// files as its structure lists them; a file comes when he taps it, and a
/// forward's when the forward is sent, by its section. Every other letter
/// is fetched as it always was, and so is a draft he reopens, however large.
/// A row kept on the iPad from an earlier launch is vouched for by the
/// first FETCH, as the whole letter's FETCH vouches for it (B-053).
///
/// Most of these give the repository limits of a few kilobytes, so a letter
/// of a few kilobytes stands for one of megabytes and the suite stays fast;
/// the letter of line breaks that once took the app to 1.66 GB is opened at
/// the app's own limits, and its memory measured.
final class LargeLetterTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "LargeLetterTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var submissions: LargeLetterSubmissions!
    private var root: URL!

    /// Above this, a letter here is large; every letter the server seeds
    /// is under it.
    private static let limit = 4_000
    /// The part of a large letter's text or HTML fetched.
    private static let section = 1_000

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer(inboxCount: 6)
        submissions = LargeLetterSubmissions()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LargeLetterTests-\(UUID().uuidString)", isDirectory: true)
        Diagnostics.clear()
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        for outcome in ["ok", "fail"] {
            let transcript = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
            try? FileManager.default.removeItem(atPath: transcript)
        }
        if let root {
            MailShelf.wipe(root: kept)
            try? FileManager.default.removeItem(at: root)
        }
        server = nil
        book = nil
        submissions = nil
        root = nil
        super.tearDown()
    }

    private var kept: URL { root.appendingPathComponent("Kept", isDirectory: true) }

    private func makeShelf() -> MailShelf {
        MailShelf(root: kept, address: server.username, host: server.account.imapHost)
    }

    /// A launch's repository, with this suite's limits or the app's.
    private func makeRepository(shelf: MailShelf? = nil, appLimits: Bool = false,
                                withSubmission: Bool = false) -> IMAPMailRepository {
        let imap = server.transportFactory
        let submissions = self.submissions!
        var transport = imap
        if withSubmission {
            transport = { host, port in port == 465 ? submissions.next() : imap(host, port) }
        }
        return IMAPMailRepository(
            account: server.account, password: server.password, transport: transport,
            recipients: book, signatureImages: { [] }, shelf: shelf ?? makeShelf(),
            largeLetterBytes: appLimits ? IMAPMailRepository.largeLetterBytes : Self.limit,
            largeLetterSectionBytes: appLimits
                ? IMAPMailRepository.largeLetterSectionBytes : Self.section)
    }

    private func uid(_ id: String) -> UInt32 { UInt32(id.split(separator: "/").last ?? "")! }

    private var uidFetches: [String] {
        server.log.filter { $0.verb == "UID FETCH" }.map(\.command)
    }

    // MARK: - Letters

    private let photo = Data((0..<2_400).map { UInt8(truncatingIfNeeded: $0 &* 13 &+ 7) })
    private let report = Data((0..<3_000).map { UInt8(truncatingIfNeeded: $0 &* 5 &+ 1) })

    /// Jane's letter with a photograph shown by `cid:` and a PDF: about
    /// 9 KB on the wire, over this suite's limit.
    private func photographs(html: String? = nil) -> Server.Letter {
        Server.Letter(
            from: Server.Address(name: "Jane Example", address: "jane@example.com"),
            to: [Server.owner], subject: "The garden in June", date: Server.newestDate,
            text: "Here is the garden.\r\n\r\nJane\r\n",
            html: html ?? "<p>Here is the <b>garden</b>.</p><img src=\"cid:ii_garden\">"
                + "<p>Jane</p>",
            messageID: "<garden-large@example.com>",
            files: [Server.File(name: "garden.jpg", type: "IMAGE", subtype: "JPEG",
                                bytes: photo, contentID: "ii_garden"),
                    Server.File(name: "Programme.pdf", type: "APPLICATION", subtype: "PDF",
                                bytes: report)])
    }

    /// `letter` delivered to the Inbox and listed, so the repository knows
    /// its size as the app knows every row's: its row.
    private func listed(_ letter: Server.Letter,
                        by repository: IMAPMailRepository) async throws -> MessageSummary {
        let delivered = try XCTUnwrap(server.deliver(letter, to: [Server.inbox])[Server.inbox])
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        return try XCTUnwrap(rows.first { uid($0.id) == delivered })
    }

    // MARK: - Opened without its files

    /// The letter as the pane gets it, over this suite's limit: one FETCH
    /// for its structure and header, then one for its text and its HTML,
    /// each up to the section's size, and nothing else of it. (Two for
    /// them, one each, until B-113.) It is the letter a whole
    /// fetch gives, field for field and file for file, and nothing of it is
    /// marked read.
    func testALetterAboveTheLimitIsOpenedWithoutItsFiles() async throws {
        let repository = makeRepository()
        let row = try await listed(photographs(), by: repository)
        let n = uid(row.id)
        server.clearLog()

        let letter = try await repository.open(row)
        XCTAssertEqual(uidFetches, [
            "UID FETCH \(n) (UID BODYSTRUCTURE BODY.PEEK[HEADER])",
            "UID FETCH \(n) (UID BODY.PEEK[1.1]<0.\(Self.section)> BODY.PEEK[1.2]<0.\(Self.section)>)",
        ])
        XCTAssertFalse(server.flags(uid: n, in: Server.inbox).contains("\\Seen"), "PEEK")

        let whole = try await makeRepository(appLimits: true).open(row)
        XCTAssertEqual(letter.sender, whole.sender)
        XCTAssertEqual(letter.to, whole.to)
        XCTAssertEqual(letter.subject, whole.subject)
        XCTAssertEqual(letter.date, whole.date)
        XCTAssertEqual(letter.messageID, whole.messageID)
        XCTAssertEqual(letter.references, whole.references)
        XCTAssertEqual(letter.gmailMessageID, whole.gmailMessageID)
        XCTAssertEqual(letter.textBody, whole.textBody)
        XCTAssertEqual(letter.htmlBody, whole.htmlBody)
        XCTAssertEqual(letter.attachments.map(\.id), whole.attachments.map(\.id))
        XCTAssertEqual(letter.attachments.map(\.filename), ["garden.jpg", "Programme.pdf"])
        XCTAssertEqual(letter.attachments.map(\.contentID), whole.attachments.map(\.contentID))
        XCTAssertEqual(letter.attachments.map(\.isInline), [true, false])
        XCTAssertEqual(letter.listedAttachments.map(\.filename), ["Programme.pdf"])
        XCTAssertFalse(letter.isShortened)
        XCTAssertNotNil(PanePage.letter(letter, style: .init(inset: 26, bodyPointSize: 17,
                                                             lineHeight: 1.41)))
    }

    /// A file, and the picture the HTML shows, come when they are asked
    /// for, each by its section alone: the structure came with the letter
    /// and is kept, as a letter fetched whole is kept, so nothing describes
    /// the letter again.
    func testItsFilesAndPicturesComeWhenAskedFor() async throws {
        let repository = makeRepository()
        let row = try await listed(photographs(), by: repository)
        let letter = try await repository.open(row)
        let n = uid(row.id)
        server.clearLog()

        let file = try XCTUnwrap(letter.listedAttachments.first)
        let bytes = try await repository.fetchAttachmentData(file.id, of: letter.id,
                                                             mailboxID: row.mailboxID)
        XCTAssertEqual(bytes, report)
        let picture = try XCTUnwrap(letter.attachments.first { $0.contentID == "ii_garden" })
        let shown = try await repository.fetchAttachmentData(picture.id, of: letter.id,
                                                             mailboxID: row.mailboxID)
        XCTAssertEqual(shown, photo)
        XCTAssertEqual(uidFetches,
                       ["UID FETCH \(n) (UID BODY.PEEK[3])", "UID FETCH \(n) (UID BODY.PEEK[2])"])
    }

    /// Jane's letter with `count` pictures of a kilobyte shown in its
    /// body, and the pictures: over this suite's limit from four of them.
    private func pictures(_ count: Int) -> (letter: Server.Letter, files: [Server.File]) {
        let files = (0..<count).map { k in
            Server.File(name: "p\(k).png", type: "IMAGE", subtype: "PNG",
                        bytes: Data((0..<1_000).map { UInt8(truncatingIfNeeded: $0 &* 3 &+ k) }),
                        contentID: "p\(k)")
        }
        var letter = photographs(html: (0..<count).map { "<img src=\"cid:p\($0)\">" }.joined())
        letter.files = files
        return (letter, files)
    }

    /// A large letter of many pictures, as a stranger can send: each the
    /// pane asks for is one FETCH of its section. Describing the letter
    /// again before each, as for a letter no longer to hand, made forty
    /// pictures eighty FETCHes, every other one carrying the whole
    /// structure, which grows with the pictures: 300 took 603 FETCHes.
    func testEachPictureItShowsIsOneFetch() async throws {
        let (sent, files) = pictures(40)
        let repository = makeRepository()
        let row = try await listed(sent, by: repository)
        server.clearLog()
        let letter = try await repository.open(row)
        let n = uid(row.id)
        XCTAssertEqual(uidFetches.first, "UID FETCH \(n) (UID BODYSTRUCTURE BODY.PEEK[HEADER])")
        server.clearLog()

        let shown = letter.attachments.filter { $0.contentID != nil }
        XCTAssertEqual(shown.count, files.count)
        for picture in shown {
            let bytes = try await repository.fetchAttachmentData(picture.id, of: letter.id,
                                                                 mailboxID: row.mailboxID)
            XCTAssertEqual(bytes, files.first { $0.contentID == picture.contentID }?.bytes)
        }
        XCTAssertEqual(uidFetches, shown.map { "UID FETCH \(n) (UID BODY.PEEK[\($0.id)])" })
    }

    /// Pictures still coming when he taps another letter. WebKit stops
    /// them as the page goes, and each fetch is called off with its request
    /// (`PictureRequests`): the one on the wire finishes, the others leave
    /// the line with nothing sent, and none is answered. Before, every one
    /// went, one after another, and the letter he had tapped came after
    /// them all.
    func testPicturesStillComingWhenHeMovesOnAreCalledOff() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let row = try await listed(pictures(5).letter, by: repository)
        server.clearLog()
        let letter = try await repository.open(row)
        XCTAssertEqual(uidFetches.first,
                       "UID FETCH \(uid(row.id)) (UID BODYSTRUCTURE BODY.PEEK[HEADER])")
        let shown = letter.attachments.filter { $0.contentID != nil }
        server.clearLog()
        server.holdReplies(to: "UID FETCH")

        var requests = PictureRequests<Int>()
        var fetches: [Task<Void, Never>] = []
        for (k, picture) in shown.enumerated() {
            requests.begin(k)
            let fetch = Task {
                _ = try? await repository.fetchAttachmentData(picture.id, of: letter.id,
                                                              mailboxID: row.mailboxID)
            }
            requests.answering(k, with: fetch)
            fetches.append(fetch)
        }
        try await until { self.uidFetches.count == 1 }
        for k in shown.indices { requests.stop(k) }
        await server.releaseReplies(to: "UID FETCH")
        let waited = fetches
        try await finishing { for fetch in waited { await fetch.value } }

        XCTAssertEqual(uidFetches.count, 1, "\(uidFetches)")
        XCTAssertEqual(requests.count, 0)
        XCTAssertFalse(shown.indices.contains { requests.answer($0) }, "a stopped one answered")

        // The letter he tapped comes next, as ever.
        _ = try await repository.open(rows[0])
        XCTAssertEqual(uidFetches.last, "UID FETCH \(uid(rows[0].id)) (UID BODY.PEEK[])")
    }

    /// A millisecond at a time, for a second at most.
    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    /// Reply and Forward of it: the reply carries the original's markup as
    /// a reply of a letter fetched whole does, and nothing of it is fetched
    /// again; the forward carries its picture and its PDF, fetched by their
    /// sections as it is sent.
    func testAReplyAndAForwardOfItStillGo() async throws {
        let repository = makeRepository(withSubmission: true)
        let row = try await listed(photographs(), by: repository)
        let letter = try await repository.open(row)
        let n = uid(row.id)

        var reply = Draft.replying(to: letter, all: false, myAddress: server.username)
        reply.body = "Lovely.\n\n" + reply.body
        server.clearLog()
        try await repository.send(reply)
        XCTAssertEqual(uidFetches, [], "a reply carries none of the original's parts")

        var forward = Draft.forwarding(letter)
        forward.to = ["carlo@example.org"]
        try await repository.send(forward)
        XCTAssertEqual(Set(uidFetches.filter { $0.contains("BODY.PEEK") }),
                       ["UID FETCH \(n) (UID BODY.PEEK[2])", "UID FETCH \(n) (UID BODY.PEEK[3])"])

        let letters = await submissions.letters()
        XCTAssertEqual(letters.count, 2)
        let replied = MIMEDecoder.decodeMessage(letters[0])
        XCTAssertTrue(replied.html?.contains("<b>garden</b>") == true, replied.html ?? "none")
        let forwarded = MIMEDecoder.parse(letters[1])
        let files = MIMEDecoder.decodeMessage(letters[1]).attachments.map { a -> Data in
            let part = MIMEDecoder.part(at: a.id, in: forwarded.structure)
            return MIMEDecoder.decodeTransfer(forwarded.bodies[a.id] ?? Data(),
                                              encoding: part?.encoding ?? "7bit")
        }
        XCTAssertTrue(files.contains(photo), "the picture its quote shows")
        XCTAssertTrue(files.contains(report), "the PDF")
    }

    /// HTML longer than the section is cut where the fetch stopped, and the
    /// letter says so above itself, in the pane and in a conversation. The
    /// cut falls inside a two-byte character, which is dropped rather than
    /// making the whole of it read as Latin-1.
    func testHTMLLongerThanItsSectionIsCutAndThePaneSaysSo() async throws {
        let repository = makeRepository()
        // "é" is two bytes, and 999 bytes of prefix put the cut in the middle
        // of one.
        let long = "<p>" + String(repeating: "x", count: 996) + String(repeating: "é", count: 900)
            + "</p>"
        let row = try await listed(photographs(html: long), by: repository)

        let letter = try await repository.open(row)
        XCTAssertTrue(letter.isShortened)
        let html = try XCTUnwrap(letter.htmlBody)
        XCTAssertEqual(html, "<p>" + String(repeating: "x", count: 996))
        XCTAssertEqual(letter.textBody, "Here is the garden.\n\nJane\n", "the text was not cut")

        let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)
        let page = try XCTUnwrap(PanePage.letter(letter, style: style))
        // Its file under the line, above the words cut short (B-170).
        let tile = BodyFiles.tile(try XCTUnwrap(letter.listedAttachments.first), of: letter, on: .light)
        XCTAssertTrue(page.contains("<div id=\"bm\"><p style=\"color: #8e8e93; margin: 0 0 1em 0; "
                                    + "white-space: normal;\">"
                                    + MailText.shortenedNotice + "</p><div style=\"margin: 0; white-space: normal;\">"
                                    + tile + "</div><p>xxx"), page)
        let stack = PanePage.stackBody(letter)
        XCTAssertTrue(stack.html.hasPrefix("<p style=\"color: #8e8e93;"), stack.html)
        XCTAssertTrue(stack.html.hasSuffix("xxx"))

        // A letter shown whole says nothing of the kind.
        var whole = letter
        whole.isShortened = false
        XCTAssertFalse(try XCTUnwrap(PanePage.letter(whole, style: style))
            .contains(MailText.shortenedNotice))
        XCTAssertFalse(PanePage.stackBody(whole).html.contains(MailText.shortenedNotice))
    }

    /// A text alternative longer than its section, under HTML that came
    /// whole: the pane shows the HTML, all of it, and says nothing of the
    /// text it does not show. A letter of text alone, cut, says so.
    func testATextCutUnderHTMLThatCameWholeIsNotSaidToBeShortened() async throws {
        let repository = makeRepository()
        let long = String(repeating: "Here is the garden in June. ", count: 60)
        var sent = photographs()
        sent.text = long
        let letter = try await repository.open(try await listed(sent, by: repository))
        XCTAssertEqual(letter.textBody?.utf8.count, Self.section, "the text was cut")
        XCTAssertEqual(letter.htmlBody, sent.html)
        XCTAssertFalse(letter.isShortened)
        let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)
        XCTAssertFalse(try XCTUnwrap(PanePage.letter(letter, style: style))
            .contains(MailText.shortenedNotice))

        var plain = sent
        plain.html = nil
        plain.messageID = "<garden-plain@example.com>"
        let cut = try await repository.open(try await listed(plain, by: repository))
        XCTAssertNil(cut.htmlBody)
        XCTAssertTrue(cut.isShortened)
    }

    /// At or under the limit the letter's FETCH is what it always was, and
    /// so is one whose size nothing has said, here a large one taken by its
    /// UID with nothing listed or kept: the everyday wire.
    func testALetterAtOrUnderTheLimitIsFetchedWholeAsEver() async throws {
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let large = try XCTUnwrap(server.deliver(photographs(), to: [Server.inbox])[Server.inbox])
        let unlisted = IMAPMailRepository(account: server.account, password: server.password,
                                          transport: server.transportFactory, recipients: book,
                                          largeLetterBytes: Self.limit,
                                          largeLetterSectionBytes: Self.section)
        server.clearLog()

        _ = try await repository.open(rows[0])
        let letter = try await unlisted.loadMessage(
            id: "\(server.uidValidity(of: Server.inbox))/\(large)", mailboxID: Server.inbox)
        XCTAssertEqual(uidFetches, ["UID FETCH \(uid(rows[0].id)) (UID BODY.PEEK[])",
                                    "UID FETCH \(large) (UID BODY.PEEK[])"])
        XCTAssertEqual(letter.listedAttachments.map(\.filename), ["Programme.pdf"])
    }

    /// A draft of his, however large, is reopened whole: he may change it
    /// and send it again, and a text cut short would go cut short.
    func testADraftIsReopenedWholeHoweverLarge() async throws {
        let repository = makeRepository()
        var draft = photographs()
        draft.from = Server.owner
        draft.to = [Server.jane]
        let placed = try XCTUnwrap(server.deliver(draft, to: [Server.drafts])[Server.drafts])
        let rows = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 50)
        let row = try XCTUnwrap(rows.first { uid($0.id) == placed })
        server.clearLog()

        let reopened = try await repository.reopen(row)
        XCTAssertEqual(uidFetches, ["UID FETCH \(placed) (UID BODY.PEEK[])"])
        XCTAssertEqual(reopened.attachments.map(\.filename), ["garden.jpg", "Programme.pdf"])
    }

    /// A copy this launch put in Drafts, opened in the pane by the id its
    /// upload gave it, which names no letter, when its size is known from
    /// the page kept on the iPad and nothing this launch has listed has
    /// named it: as for the copy a cut-off upload left, listed by the launch
    /// before and found by its Message-ID in this one. Gmail's id for it is
    /// asked in the first FETCH, beside its structure and its header, as
    /// the whole letter's FETCH asks it (`fetchBodyAskingLetter`), nothing
    /// is compared, and the letter shown names it. The kept page is written
    /// here by a second repository on the same shelf, listing Drafts after
    /// this one's upload.
    func testACopyThisLaunchPutInDraftsIsAskedItsIDInItsFirstFetch() async throws {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let draft = Draft(to: ["jane@example.com"], subject: "The garden",
                          body: String(repeating: "The roses are out at last. ", count: 200))
        let upload: String? = try await repository.saveDraft(draft)
        let saved = try XCTUnwrap(upload)
        let rows = try await makeRepository(shelf: shelf)
            .listMessages(in: Server.drafts, beforeUID: nil, limit: 50)
        XCTAssertTrue(rows.contains { $0.id == saved })
        server.clearLog()

        let letter = try await repository.loadMessage(id: saved, mailboxID: Server.drafts)
        XCTAssertEqual(uidFetches.first,
                       "UID FETCH \(uid(saved)) (UID X-GM-MSGID BODYSTRUCTURE BODY.PEEK[HEADER])")
        XCTAssertFalse(uidFetches.contains("UID FETCH \(uid(saved)) (UID BODY.PEEK[])"))
        let named = server.gmailMessageID(uid: uid(saved), in: Server.drafts)
        XCTAssertNotNil(named)
        XCTAssertEqual(letter.gmailMessageID, named)
        XCTAssertEqual(letter.subject, "The garden")
    }

    // MARK: - Kept on the iPad (B-053)

    /// The launch before, as it leaves the iPad: the Inbox listed with the
    /// large letter in it, and kept.
    private func earlierLaunch() async throws -> MessageSummary {
        let shelf = makeShelf()
        let row = try await listed(photographs(), by: makeRepository(shelf: shelf))
        shelf.flush()
        return row
    }

    /// The large row on the kept Inbox, tapped before this launch has
    /// listed anything: the kept page has its size, so it is opened in
    /// part, and the first FETCH asks Gmail's id for it beside the
    /// structure and the header, which is compared before its text is
    /// asked for, in one FETCH with its HTML (two, until B-113). The letter
    /// it names is shown.
    func testAKeptLargeRowIsOpenedInPartAndVouchedForByItsFirstFetch() async throws {
        let before = try await earlierLaunch()
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let row = try XCTUnwrap(shelf.page(of: "inbox")?.rows.first { $0.id == before.id })
        server.clearLog()

        let letter = try await repository.open(row)
        let n = uid(row.id)
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN", "LIST", "SELECT", "UID FETCH",
                                                "UID FETCH"])
        XCTAssertEqual(uidFetches, [
            "UID FETCH \(n) (UID X-GM-MSGID BODYSTRUCTURE BODY.PEEK[HEADER])",
            "UID FETCH \(n) (UID BODY.PEEK[1.1]<0.\(Self.section)> BODY.PEEK[1.2]<0.\(Self.section)>)",
        ])
        XCTAssertEqual(letter.subject, "The garden in June")
        XCTAssertEqual(letter.gmailMessageID, row.gmailMessageID)
        XCTAssertEqual(letter.listedAttachments.map(\.filename), ["Programme.pdf"])
        XCTAssertEqual(Diagnostics.entries.map(\.text).filter { $0.hasPrefix("KEPT-") }, [])
    }

    /// The same row, when the server has another letter under its UID now,
    /// as in another mailbox under the same numbers: the first FETCH names
    /// that letter, and nothing more is asked for or shown, as for a whole
    /// letter (B-053).
    func testAKeptLargeRowThatIsAnotherLetterNowShowsNothingAndFetchesNoMore() async throws {
        let before = try await earlierLaunch()
        server.renumber(Server.inbox, validity: server.uidValidity(of: Server.inbox),
                        firstUID: 1_002)
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let row = try XCTUnwrap(shelf.page(of: "inbox")?.rows.first { $0.id == before.id })
        server.clearLog()

        do {
            _ = try await repository.open(row)
            XCTFail("another letter's is shown")
        } catch {
            XCTAssertEqual(error as? MailShelf.NotTheKeptLetter, MailShelf.NotTheKeptLetter())
        }
        XCTAssertEqual(uidFetches,
                       ["UID FETCH \(uid(row.id)) (UID X-GM-MSGID BODYSTRUCTURE BODY.PEEK[HEADER])"])
        XCTAssertEqual(Diagnostics.entries.map(\.text).filter { $0.hasPrefix("KEPT-") },
                       ["KEPT-UNVOUCHED folder=INBOX nothing-shown"])
        XCTAssertNil(shelf.page(of: "inbox")?.rows.first { $0.id == row.id })
    }

    // MARK: - The letter of line breaks

    /// 35 MB of line breaks inside a multipart, at the app's own limits:
    /// whole, it came to 1.66 GB and got the app killed the moment he
    /// opened it. Opened in part, the pane is given the first 2 MB of its
    /// text and the process holds little more than that at any moment.
    func testTheLetterOfLineBreaksOpensInBoundedMemory() async throws {
        let header = "From: Stranger <stranger@example.com>\r\nTo: owner@example.com\r\n"
            + "Subject: Nothing\r\nDate: Mon, 20 Sep 2026 10:00:00 +0000\r\n"
            + "Message-ID: <breaks@example.com>\r\nMIME-Version: 1.0\r\n"
            + "Content-Type: multipart/mixed; boundary=\"B\"\r\n\r\n"
        let breaks = 35 << 20
        var raw = Data(header.utf8)
        raw.append(Data("--B\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n".utf8))
        let start = raw.count
        raw.append(Data(repeating: 0x0A, count: breaks))
        let end = raw.count
        raw.append(Data("\r\n--B--\r\n".utf8))
        let structure = "((\"TEXT\" \"PLAIN\" (\"CHARSET\" \"UTF-8\") NIL NIL \"7BIT\" \(breaks) "
            + "\(breaks) NIL NIL NIL NIL) \"MIXED\" (\"BOUNDARY\" \"B\") NIL NIL NIL)"
        let envelope = Server.Letter(from: Server.Address(name: "Stranger",
                                                          address: "stranger@example.com"),
                                     to: [Server.owner], subject: "Nothing",
                                     date: Server.newestDate, text: "",
                                     messageID: "<breaks@example.com>")
        let placed = try XCTUnwrap(server.deliver(
            raw: raw, sections: ["HEADER": Data(header.utf8), "1": raw[start..<end]],
            structure: structure, as: envelope, to: [Server.inbox])[Server.inbox])
        let repository = makeRepository(appLimits: true)
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let row = try XCTUnwrap(rows.first { uid($0.id) == placed })

        var opened: Message?
        let grew = try await PeakMemory.growth {
            let shown = try await repository.open(row)
            _ = PanePage.letter(shown, style: .init(inset: 26, bodyPointSize: 17,
                                                    lineHeight: 1.41))
            opened = shown
        }
        let letter = try XCTUnwrap(opened)
        XCTAssertTrue(letter.isShortened)
        XCTAssertEqual(letter.textBody?.utf8.count, IMAPMailRepository.largeLetterSectionBytes)
        XCTAssertEqual(letter.subject, "Nothing")
        XCTAssertFalse(uidFetches.contains("UID FETCH \(placed) (UID BODY.PEEK[])"))
        // 6 MB on the development computer. Whole, with the lines walked in
        // place, 104 MB, the 35 MB crossing the transport, the parser and the
        // decoder in several copies at once; with a list of the lines made
        // first, as it was, 1.66 GB.
        guard let growth = grew else { throw XCTSkip(BoundedLetterTests.unmeasured) }
        XCTAssertLessThan(growth, 60 << 20, "\(growth >> 20) MB")
    }

    // MARK: - Every part of its words (B-113, B-114)

    /// `raw` delivered to the Inbox as Gmail describes and serves it
    /// (`ScriptedIMAPServer.deliver(described:)`): its BODYSTRUCTURE made
    /// from its parts, the letter a message/rfc822 part holds with
    /// `envelope` for its ENVELOPE, and every part's BODY[], the one-part
    /// body of a forwarded letter by its TEXT alone, as Gmail serves it
    /// (B-114). `refusing`, more sections the server will not give.
    private func delivered(_ raw: Data, envelope: String = "NIL", refusing: Set<String> = [],
                           by repository: IMAPMailRepository) async throws -> MessageSummary {
        let letter = Server.Letter(from: Server.Address(name: "Jane", address: "jane@example.com"),
                                   to: [Server.owner], subject: "The programme",
                                   date: Server.newestDate, text: "",
                                   messageID: "<programme-\(raw.count)@example.com>")
        let placed = try XCTUnwrap(server.deliver(described: raw, envelope: envelope, as: letter,
                                                  refusing: refusing, to: [Server.inbox])[Server.inbox])
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        return try XCTUnwrap(rows.first { uid($0.id) == placed })
    }

    /// A PDF of some 5 KB, base64, sent inline as Apple Mail sends one.
    private var bigPDF: String {
        "Content-Type: application/pdf; name=\"Programme.pdf\"\r\n"
            + "Content-Disposition: inline; filename=\"Programme.pdf\"\r\n"
            + "Content-Transfer-Encoding: base64\r\n\r\n"
            + report.base64EncodedString(options: [.lineLength76Characters,
                                                   .endLineWithCarriageReturn, .endLineWithLineFeed])
    }

    private func mime(_ subtype: String, _ boundary: String, _ parts: [String]) -> String {
        "Content-Type: multipart/\(subtype); boundary=\"\(boundary)\"\r\n\r\n"
            + parts.map { "--\(boundary)\r\n" + $0 + "\r\n" }.joined() + "--\(boundary)--\r\n"
    }

    private let top = "From: Jane <jane@example.com>\r\nTo: owner@example.com\r\n"
        + "Subject: The programme\r\nDate: Mon, 20 Sep 2026 10:00:00 +0000\r\n"
        + "Message-ID: <programme@example.com>\r\nMIME-Version: 1.0\r\n"

    /// Apple Mail's letter with a PDF among its words, over the limit: the
    /// plain words and each part of the HTML in one FETCH (one each,
    /// before), the second given what the first left, and never the PDF;
    /// the letter the pane gets is the one a whole fetch gives, every word
    /// of it, the PDF listed.
    func testALargeLetterWithAFileAmongItsWordsShowsThemAll() async throws {
        let first = "<div>Words before the PDF: the programme is below.</div>"
        let second = "<div>Words after the PDF: see you on Thursday at two.</div>"
        let raw = Data((top + mime("alternative", "ALT", [
            "Content-Type: text/plain; charset=utf-8\r\n\r\nWords before the PDF.\r\n\r\n"
                + "Words after the PDF.",
            mime("mixed", "MIX", [
                "Content-Type: text/html; charset=utf-8\r\n\r\n" + first,
                bigPDF,
                "Content-Type: text/html; charset=utf-8\r\n\r\n" + second,
            ]),
        ])).utf8)
        XCTAssertGreaterThan(raw.count, Self.limit)
        let repository = makeRepository()
        let row = try await delivered(raw, by: repository)
        let n = uid(row.id)
        server.clearLog()

        let letter = try await repository.open(row)
        XCTAssertEqual(uidFetches, [
            "UID FETCH \(n) (UID BODYSTRUCTURE BODY.PEEK[HEADER])",
            "UID FETCH \(n) (UID BODY.PEEK[1]<0.\(Self.section)> BODY.PEEK[2.1]<0.\(Self.section)> "
                + "BODY.PEEK[2.3]<0.\(Self.section - first.utf8.count)>)",
        ])
        XCTAssertEqual(letter.htmlBody, first + "<!--bm-file:2.2-->" + second)
        XCTAssertEqual(letter.textBody, "Words before the PDF.\n\nWords after the PDF.")
        XCTAssertFalse(letter.isShortened)
        XCTAssertEqual(letter.listedAttachments.map(\.filename), ["Programme.pdf"])
        XCTAssertTrue(row.hasAttachment)

        let whole = try await makeRepository(appLimits: true).open(row)
        XCTAssertEqual(letter.htmlBody, whole.htmlBody)
        XCTAssertEqual(letter.textBody, whole.textBody)
        XCTAssertEqual(letter.listedAttachments.map(\.id), whole.listedAttachments.map(\.id))
    }

    /// The parts of the HTML share the limit: a first part longer than it
    /// takes it all, and the letter is shown to where its fetch stopped,
    /// said to be only the beginning, with nothing after the cut: not the
    /// PDF's mark, not the header lines of the letter forwarded after it,
    /// and not that letter's words, which are not fetched.
    func testThePartsOfALargeLettersWordsShareTheLimit() async throws {
        let first = "<p>" + String(repeating: "x", count: Self.section + 500) + "</p>"
        let raw = Data((top + mime("mixed", "MIX", [
            "Content-Type: text/html; charset=utf-8\r\n\r\n" + first,
            bigPDF,
            "Content-Type: message/rfc822\r\nContent-Disposition: inline\r\n\r\n"
                + "From: Sam Example <sam@example.com>\r\nSubject: Earlier\r\n"
                + "Content-Type: text/html; charset=utf-8\r\n\r\n<p>Sent from my iPad</p>",
        ])).utf8)
        let envelope = "(NIL \"Earlier\" ((\"Sam Example\" NIL \"sam\" \"example.com\")) NIL NIL NIL "
            + "NIL NIL NIL NIL)"
        let repository = makeRepository()
        let row = try await delivered(raw, envelope: envelope, by: repository)
        let n = uid(row.id)
        server.clearLog()

        let letter = try await repository.open(row)
        XCTAssertEqual(uidFetches, [
            "UID FETCH \(n) (UID BODYSTRUCTURE BODY.PEEK[HEADER])",
            "UID FETCH \(n) (UID BODY.PEEK[1]<0.\(Self.section)>)",
        ])
        XCTAssertEqual(letter.htmlBody, String(first.prefix(Self.section)))
        XCTAssertNil(letter.textBody)
        XCTAssertTrue(letter.isShortened)
    }

    /// A part in both bodies is read by each to its own share of the
    /// limit, fetched once with the more of the two, all three parts in one
    /// FETCH (one each, before): a footer after an HTML longer than the
    /// plain words is whole in the plain words and cut in the HTML, which
    /// the pane shows, and says is only the beginning.
    func testAPartInBothBodiesIsReadByEachToItsOwnShare() async throws {
        let plain = "Short words."
        let html = "<p>" + String(repeating: "h", count: 693) + "</p>"
        let footer = String(repeating: "f", count: 500)
        let raw = Data((top + mime("mixed", "MIX", [
            mime("alternative", "ALT", [
                "Content-Type: text/plain; charset=utf-8\r\n\r\n" + plain,
                "Content-Type: text/html; charset=utf-8\r\n\r\n" + html,
            ]),
            "Content-Type: text/plain; charset=utf-8\r\n\r\n" + footer,
            bigPDF,
        ])).utf8)
        let repository = makeRepository()
        let row = try await delivered(raw, by: repository)
        let n = uid(row.id)
        server.clearLog()

        let letter = try await repository.open(row)
        let htmlShare = Self.section - html.utf8.count
        XCTAssertEqual(uidFetches, [
            "UID FETCH \(n) (UID BODYSTRUCTURE BODY.PEEK[HEADER])",
            "UID FETCH \(n) (UID BODY.PEEK[1.1]<0.\(Self.section)> "
                + "BODY.PEEK[2]<0.\(Self.section - plain.utf8.count)> BODY.PEEK[1.2]<0.\(Self.section)>)",
        ])
        XCTAssertEqual(letter.textBody, plain + "\n" + footer)
        XCTAssertEqual(letter.htmlBody, html + "<div style=\"white-space: pre-wrap;\">"
                       + String(footer.prefix(htmlShare)) + "</div>")
        XCTAssertTrue(letter.isShortened)
    }

    /// A note and the letter it forwards inline, over the limit: their
    /// words in one FETCH (one each, before), the forwarded words asked
    /// for as 2.TEXT, the name Gmail serves them by: asked as 2.1 they were
    /// refused, and the whole letter with them (B-114). The forwarded
    /// letter's header lines come from the envelope its structure carries,
    /// nothing more is fetched for them, and they are the lines the whole
    /// letter's own header gives.
    func testALargeForwardDrawsItsHeaderLinesFromItsStructure() async throws {
        let inner = "From: Sam Example <sam@example.com>\r\nTo: Jane <jane@example.com>\r\n"
            + "Subject: The forwarded words\r\nDate: Wed, 21 Oct 2026 14:36:17 +0000\r\n"
            + "Message-ID: <inner@example.com>\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n"
            + "The forwarded letter's words."
        let envelope = "(\"Wed, 21 Oct 2026 14:36:17 +0000\" \"The forwarded words\" "
            + "((\"Sam Example\" NIL \"sam\" \"example.com\")) ((\"Sam Example\" NIL \"sam\" \"example.com\")) "
            + "((\"Sam Example\" NIL \"sam\" \"example.com\")) ((\"Jane\" NIL \"jane\" \"example.com\")) "
            + "NIL NIL NIL \"<inner@example.com>\")"
        let raw = Data((top + mime("mixed", "FWD", [
            "Content-Type: text/plain; charset=utf-8\r\n\r\nMy own note.",
            "Content-Type: message/rfc822\r\nContent-Disposition: inline\r\n\r\n" + inner,
            bigPDF,
        ])).utf8)
        let repository = makeRepository()
        let row = try await delivered(raw, envelope: envelope, by: repository)
        let n = uid(row.id)
        server.clearLog()

        let letter = try await repository.open(row)
        XCTAssertEqual(uidFetches, [
            "UID FETCH \(n) (UID BODYSTRUCTURE BODY.PEEK[HEADER])",
            "UID FETCH \(n) (UID BODY.PEEK[1]<0.\(Self.section)> BODY.PEEK[2.TEXT]<0.\(Self.section - 12)>)",
        ])
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
        XCTAssertFalse(letter.isShortened)
        let when = try XCTUnwrap(IMAPParser.parseHeaderDate("Wed, 21 Oct 2026 14:36:17 +0000"))
        XCTAssertEqual(letter.textBody, "My own note.\n\nBegin forwarded message:\n\n"
                       + "From: Sam Example <sam@example.com>\nDate: \(MailFormat.forwardedDate(when))\n"
                       + "To: Jane <jane@example.com>\nSubject: The forwarded words\n\n"
                       + "The forwarded letter's words.")
        XCTAssertNil(letter.htmlBody)
        XCTAssertEqual(letter.listedAttachments.map(\.filename), ["Programme.pdf"])

        let whole = try await makeRepository(appLimits: true).open(row)
        XCTAssertEqual(letter.textBody, whole.textBody)
    }

    // MARK: - A part the server will not give (B-114)

    /// The forwarded letter of B-114's step 6 on the iPad, a plain one, and
    /// its ENVELOPE.
    private let forwarded = "From: Sam Example <sam@example.com>\r\nTo: Jane <jane@example.com>\r\n"
        + "Subject: The forwarded words\r\nDate: Wed, 21 Oct 2026 14:36:17 +0000\r\n"
        + "Message-ID: <inner@example.com>\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n"
        + "The forwarded letter's words."
    private let forwardedEnvelope = "(\"Wed, 21 Oct 2026 14:36:17 +0000\" \"The forwarded words\" "
        + "((\"Sam Example\" NIL \"sam\" \"example.com\")) ((\"Sam Example\" NIL \"sam\" \"example.com\")) "
        + "((\"Sam Example\" NIL \"sam\" \"example.com\")) ((\"Jane\" NIL \"jane\" \"example.com\")) "
        + "NIL NIL NIL \"<inner@example.com>\")"

    /// Its header lines, as the plain words draw them.
    private func forwardedLines() throws -> String {
        let when = try XCTUnwrap(IMAPParser.parseHeaderDate("Wed, 21 Oct 2026 14:36:17 +0000"))
        return "Begin forwarded message:\n\nFrom: Sam Example <sam@example.com>\n"
            + "Date: \(MailFormat.forwardedDate(when))\nTo: Jane <jane@example.com>\n"
            + "Subject: The forwarded words\n"
    }

    /// A note, `inner` forwarded inline after it, and the PDF that makes
    /// the letter too large to fetch whole: step 6's letter.
    private func noteAndForward(_ inner: String) -> Data {
        Data((top + mime("mixed", "FWD", [
            "Content-Type: text/plain; charset=utf-8\r\n\r\nMy own note.",
            "Content-Type: message/rfc822\r\nContent-Disposition: inline\r\n\r\n" + inner,
            bigPDF,
        ])).utf8)
    }

    /// A FETCH of a large letter's words answered NO, as Gmail answers one
    /// asking for a part it will not give, costs that part alone: each part
    /// is asked for again alone, the note comes, the forwarded words do
    /// not, and the pane has the note and the forwarded letter's lines,
    /// says it is only the beginning, and lists the PDF, on the one
    /// connection. On the iPad that NO was "This message could not be
    /// downloaded." and "Can't connect to mail server.", the note lost
    /// with it (B-114).
    func testAPartTheServerWillNotGiveCostsThatPartAlone() async throws {
        let repository = makeRepository()
        let row = try await delivered(noteAndForward(forwarded), envelope: forwardedEnvelope,
                                      refusing: ["2.TEXT"], by: repository)
        let n = uid(row.id)
        let connections = server.connectionsOpened
        server.clearLog()

        let letter = try await repository.open(row)
        let note = "BODY.PEEK[1]<0.\(Self.section)>"
        let words = "BODY.PEEK[2.TEXT]<0.\(Self.section - 12)>"
        XCTAssertEqual(uidFetches, [
            "UID FETCH \(n) (UID BODYSTRUCTURE BODY.PEEK[HEADER])",
            "UID FETCH \(n) (UID \(note) \(words))",
            "UID FETCH \(n) (UID \(note))",
            "UID FETCH \(n) (UID \(words))",
        ])
        XCTAssertEqual(server.log.filter { $0.verb == "UID FETCH" }.map(\.status),
                       ["OK", "NO", "OK", "NO"])
        XCTAssertEqual(letter.textBody, try "My own note.\n\n" + forwardedLines() + "\n")
        XCTAssertNil(letter.htmlBody)
        XCTAssertTrue(letter.isShortened)
        XCTAssertEqual(letter.listedAttachments.map(\.filename), ["Programme.pdf"])
        XCTAssertEqual(server.connectionsOpened, connections)
    }

    /// The same for the note: refused, it is left out, and the letter it
    /// forwards comes after it as ever, its lines and its words, said to
    /// be only the beginning.
    func testAForwardedLetterStillComesAfterANoteTheServerWillNotGive() async throws {
        let repository = makeRepository()
        let row = try await delivered(noteAndForward(forwarded), envelope: forwardedEnvelope,
                                      refusing: ["1"], by: repository)
        server.clearLog()

        let letter = try await repository.open(row)
        XCTAssertEqual(server.log.filter { $0.verb == "UID FETCH" }.map(\.status),
                       ["OK", "NO", "NO", "OK"])
        XCTAssertEqual(letter.textBody, try forwardedLines() + "\nThe forwarded letter's words.")
        XCTAssertTrue(letter.isShortened)
    }

    /// A connection that drops while a large letter's words come is not a
    /// part refused: the letter fails as it always has, after the one try
    /// more on a new connection every read has (B-023), and nothing is
    /// asked for alone on a connection that is gone.
    func testAConnectionThatDropsWhileItsWordsComeStillFailsTheLetter() async throws {
        let repository = makeRepository()
        let row = try await delivered(noteAndForward(forwarded), envelope: forwardedEnvelope,
                                      by: repository)
        let n = uid(row.id)
        let connections = server.connectionsOpened
        server.clearLog()
        server.hangsUpOnSections = ["2.TEXT"]

        do {
            let letter = try await repository.open(row)
            XCTFail("opened over a connection that dropped: \(letter.textBody ?? "nil")")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        let structure = "UID FETCH \(n) (UID BODYSTRUCTURE BODY.PEEK[HEADER])"
        let words = "UID FETCH \(n) (UID BODY.PEEK[1]<0.\(Self.section)> "
            + "BODY.PEEK[2.TEXT]<0.\(Self.section - 12)>)"
        XCTAssertEqual(uidFetches, [structure, words, structure, words])
        XCTAssertEqual(server.connectionsOpened, connections + 1)
    }

    /// The same drop when the part refused is asked for again alone: not
    /// a part refused, but the letter failing as it always has, after the
    /// one try more on a new connection, the same again there. Taken for a
    /// refusal, the drop showed the note on a connection that was gone,
    /// left the forwarded words out for good, and never asked again.
    func testAConnectionThatDropsWhileAPartIsAskedForAloneStillFailsTheLetter() async throws {
        let repository = makeRepository()
        let row = try await delivered(noteAndForward(forwarded), envelope: forwardedEnvelope,
                                      refusing: ["2.TEXT"], by: repository)
        let n = uid(row.id)
        let connections = server.connectionsOpened
        server.clearLog()
        server.hangsUpOnSectionsAlone = ["2.TEXT"]

        do {
            let letter = try await repository.open(row)
            XCTFail("opened over a connection that dropped: \(letter.textBody ?? "nil")")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        let note = "BODY.PEEK[1]<0.\(Self.section)>"
        let words = "BODY.PEEK[2.TEXT]<0.\(Self.section - 12)>"
        let once = [
            "UID FETCH \(n) (UID BODYSTRUCTURE BODY.PEEK[HEADER])",
            "UID FETCH \(n) (UID \(note) \(words))",
            "UID FETCH \(n) (UID \(note))",
            "UID FETCH \(n) (UID \(words))",
        ]
        XCTAssertEqual(uidFetches, once + once)
        XCTAssertEqual(server.log.filter { $0.verb == "UID FETCH" }.map(\.status),
                       ["OK", "NO", "OK", nil, "OK", "NO", "OK", nil])
        XCTAssertEqual(server.connectionsOpened, connections + 1)
    }

    /// A large letter whose only words the server will not give: not a
    /// letter with no text, nor the notice above nothing, but the letter
    /// failing as a refused FETCH failed it before B-114, "This message
    /// could not be downloaded. Check the connection and tap it again.",
    /// which a passing failure of Gmail's is worth. Asked once, the one
    /// part not asked again alone, on the one connection.
    func testALargeLetterNoneOfWhoseWordsAreGivenFailsAsItAlwaysHas() async throws {
        let raw = Data((top + mime("mixed", "ONE", [
            "Content-Type: text/plain; charset=utf-8\r\n\r\nThe only words of the letter.",
            bigPDF,
        ])).utf8)
        let repository = makeRepository()
        let row = try await delivered(raw, refusing: ["1"], by: repository)
        let n = uid(row.id)
        let connections = server.connectionsOpened
        server.clearLog()

        do {
            let letter = try await repository.open(row)
            XCTFail("opened with none of its words: \(String(reflecting: letter.textBody)), "
                    + "shortened \(letter.isShortened)")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        XCTAssertEqual(uidFetches, [
            "UID FETCH \(n) (UID BODYSTRUCTURE BODY.PEEK[HEADER])",
            "UID FETCH \(n) (UID BODY.PEEK[1]<0.\(Self.section)>)",
        ])
        XCTAssertEqual(server.log.filter { $0.verb == "UID FETCH" }.map(\.status), ["OK", "NO"])
        XCTAssertEqual(server.connectionsOpened, connections)
    }

    /// The same for the note and the letter it forwards, both refused: the
    /// letter fails, not shown as the forwarded letter's header lines
    /// alone under the notice.
    func testANoteAndAForwardBothRefusedFailTheLetter() async throws {
        let repository = makeRepository()
        let row = try await delivered(noteAndForward(forwarded), envelope: forwardedEnvelope,
                                      refusing: ["1", "2.TEXT"], by: repository)
        let connections = server.connectionsOpened
        server.clearLog()

        do {
            let letter = try await repository.open(row)
            XCTFail("opened with none of its words: \(String(reflecting: letter.textBody))")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        XCTAssertEqual(server.log.filter { $0.verb == "UID FETCH" }.map(\.status),
                       ["OK", "NO", "NO", "NO"])
        XCTAssertEqual(server.connectionsOpened, connections)
    }

    /// The HTML of a plain and HTML pair refused, its plain words given:
    /// the pane has the plain words, not the empty HTML, and says it is
    /// only the beginning, the HTML the letter is drawn by not given. Kept,
    /// the empty HTML was drawn, the notice above nothing.
    func testAnHTMLPartRefusedLeavesThePlainWordsShown() async throws {
        let raw = Data((top + mime("mixed", "MIX", [
            mime("alternative", "ALT", [
                "Content-Type: text/plain; charset=utf-8\r\n\r\nPlain words here.",
                "Content-Type: text/html; charset=utf-8\r\n\r\n<p>HTML words here.</p>",
            ]),
            bigPDF,
        ])).utf8)
        let repository = makeRepository()
        let row = try await delivered(raw, refusing: ["1.2"], by: repository)
        let n = uid(row.id)
        server.clearLog()

        let letter = try await repository.open(row)
        let plain = "BODY.PEEK[1.1]<0.\(Self.section)>"
        let html = "BODY.PEEK[1.2]<0.\(Self.section)>"
        XCTAssertEqual(uidFetches, [
            "UID FETCH \(n) (UID BODYSTRUCTURE BODY.PEEK[HEADER])",
            "UID FETCH \(n) (UID \(plain) \(html))",
            "UID FETCH \(n) (UID \(plain))",
            "UID FETCH \(n) (UID \(html))",
        ])
        XCTAssertEqual(server.log.filter { $0.verb == "UID FETCH" }.map(\.status),
                       ["OK", "NO", "OK", "NO"])
        XCTAssertEqual(letter.textBody, "Plain words here.")
        XCTAssertNil(letter.htmlBody)
        XCTAssertTrue(letter.isShortened)
        let page = try XCTUnwrap(PanePage.letter(letter, style: .init(inset: 26, bodyPointSize: 17,
                                                                      lineHeight: 1.41)))
        XCTAssertEqual(letter.listedAttachments.map(\.filename), ["Programme.pdf"])
        // Its file under the line, above the words (B-170).
        let tile = BodyFiles.tile(letter.listedAttachments[0], of: letter, on: .dark)
        XCTAssertTrue(page.contains(MailText.shortenedNotice + "</p><div style=\"margin: 0; white-space: normal;\">"
                                    + tile + "</div>Plain words here.</div>"), page)
    }

    /// A file that is the whole of a letter forwarded in a large one, a
    /// scan sent as a letter of its own: its row, and its bytes asked for
    /// as 2.TEXT, the name Gmail serves them by, both while the letter is
    /// the one last opened, its structure known, and in a later launch,
    /// the structure fetched again. As 2.1 Gmail refuses them, and the row
    /// opened nothing (B-114).
    func testAFileThatIsAWholeForwardedLetterIsFetchedByTheNameGmailServes() async throws {
        let scan = "From: Sam Example <sam@example.com>\r\nSubject: The scan\r\n"
            + "Content-Type: application/pdf; name=\"scan.pdf\"\r\n"
            + "Content-Disposition: attachment; filename=\"scan.pdf\"\r\n"
            + "Content-Transfer-Encoding: base64\r\n\r\n"
            + photo.base64EncodedString(options: [.lineLength76Characters,
                                                  .endLineWithCarriageReturn, .endLineWithLineFeed])
        let repository = makeRepository()
        let row = try await delivered(noteAndForward(scan), by: repository)
        let n = uid(row.id)

        let letter = try await repository.open(row)
        XCTAssertEqual(letter.listedAttachments.map(\.filename), ["scan.pdf", "Programme.pdf"])
        XCTAssertEqual(letter.listedAttachments.first?.id, "2.1")
        server.clearLog()
        let bytes = try await repository.fetchAttachmentData("2.1", of: row.id, mailboxID: "inbox")
        XCTAssertEqual(bytes, photo)
        XCTAssertEqual(uidFetches, ["UID FETCH \(n) (UID BODY.PEEK[2.TEXT])"])

        let later = makeRepository()
        _ = try await later.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        let again = try await later.fetchAttachmentData("2.1", of: row.id, mailboxID: "inbox")
        XCTAssertEqual(again, photo)
        XCTAssertEqual(uidFetches.count, 2)
        XCTAssertEqual(uidFetches.last, "UID FETCH \(n) (UID BODY.PEEK[2.TEXT])")
        XCTAssertEqual(server.log.filter { $0.status != "OK" }, [])
    }

    /// A large letter of 300 tiny parts of words and a PDF: the 64 a body
    /// holds (`MIMEDecoder.maxBodyWords`), sixteen to a FETCH, so five
    /// FETCHes in all, where it was one for every part, 300 round trips
    /// after the first (B-113); the plain words to the 64th,
    /// said to be only the beginning, as the letter fetched whole is.
    func testALargeLetterOfHundredsOfPartsFetchesWhatABodyHoldsInFewFetches() async throws {
        let words = (0..<300).map { "w\($0)" }
        let raw = Data((top + mime("mixed", "MIX", words.map {
            "Content-Type: text/plain; charset=utf-8\r\n\r\n" + $0
        } + [bigPDF])).utf8)
        XCTAssertGreaterThan(raw.count, Self.limit)
        let repository = makeRepository()
        let row = try await delivered(raw, by: repository)
        let n = uid(row.id)
        server.clearLog()

        let letter = try await repository.open(row)
        var left = Self.section
        var items: [String] = []
        for (i, word) in words.prefix(MIMEDecoder.maxBodyWords).enumerated() {
            items.append("BODY.PEEK[\(i + 1)]<0.\(left)>")
            left -= word.utf8.count
        }
        let batches = stride(from: 0, to: items.count, by: IMAPClient.sectionsPerFetch).map {
            "UID FETCH \(n) (UID " + items[$0..<min($0 + IMAPClient.sectionsPerFetch, items.count)]
                .joined(separator: " ") + ")"
        }
        XCTAssertEqual(uidFetches, ["UID FETCH \(n) (UID BODYSTRUCTURE BODY.PEEK[HEADER])"] + batches)
        XCTAssertEqual(uidFetches.count, 5)
        XCTAssertEqual(letter.textBody, words.prefix(MIMEDecoder.maxBodyWords).joined(separator: "\n"))
        XCTAssertNil(letter.htmlBody)
        XCTAssertTrue(letter.isShortened)
        XCTAssertEqual(letter.listedAttachments.map(\.filename), ["Programme.pdf"])

        // Fetched whole, the same, and said to be only the beginning too.
        let whole = try await makeRepository(appLimits: true).open(row)
        XCTAssertEqual(whole.textBody, letter.textBody)
        XCTAssertTrue(whole.isShortened)
    }

    /// He moves on while a large letter is still coming: the fetch stops
    /// before its next command, and the letter he moved to comes next. It
    /// went on to the end, a command for every part, and the next letter
    /// waited behind it (B-113).
    func testALargeLetterHeHasMovedOnFromStopsBeforeItsNextFetch() async throws {
        let raw = Data((top + mime("mixed", "MIX", (0..<40).map {
            "Content-Type: text/plain; charset=utf-8\r\n\r\nw\($0)"
        } + [bigPDF])).utf8)
        let repository = makeRepository()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let row = try await delivered(raw, by: repository)
        server.clearLog()
        server.holdReplies(to: "UID FETCH")

        let opening = Task { try await repository.open(row) }
        try await until { self.uidFetches.count == 1 }
        opening.cancel()
        await server.releaseReplies(to: "UID FETCH")
        let outcome = await opening.result
        XCTAssertThrowsError(try outcome.get()) { XCTAssertTrue($0 is CancellationError, "\($0)") }
        XCTAssertEqual(uidFetches, ["UID FETCH \(uid(row.id)) (UID BODYSTRUCTURE BODY.PEEK[HEADER])"])

        let other = try XCTUnwrap(rows.first { $0.id != row.id })
        _ = try await repository.open(other)
        XCTAssertEqual(uidFetches.last, "UID FETCH \(uid(other.id)) (UID BODY.PEEK[])")
    }

    /// Words cut short end the body: nothing after them, not the header
    /// lines of a letter forwarded after them that holds no words of its
    /// own, which went in at the end as if the body had come whole.
    func testNothingIsDrawnAfterWordsCutShort() async throws {
        let first = "<p>" + String(repeating: "x", count: Self.section + 500) + "</p>"
        let inner = "From: Sam Example <sam@example.com>\r\nSubject: Only a file\r\n"
            + "Content-Type: multipart/mixed; boundary=\"IN\"\r\n\r\n"
            + "--IN\r\nContent-Type: application/pdf; name=\"x.pdf\"\r\n"
            + "Content-Disposition: attachment; filename=\"x.pdf\"\r\n\r\nJVBERi0\r\n--IN--\r\n"
        let envelope = "(NIL \"Only a file\" ((\"Sam Example\" NIL \"sam\" \"example.com\")) NIL NIL NIL "
            + "NIL NIL NIL NIL)"
        let raw = Data((top + mime("mixed", "MIX", [
            "Content-Type: text/html; charset=utf-8\r\n\r\n" + first,
            "Content-Type: message/rfc822\r\nContent-Disposition: inline\r\n\r\n" + inner,
            bigPDF,
        ])).utf8)
        let repository = makeRepository()
        let row = try await delivered(raw, envelope: envelope, by: repository)

        let letter = try await repository.open(row)
        XCTAssertEqual(letter.htmlBody, String(first.prefix(Self.section)))
        XCTAssertTrue(letter.isShortened)
        XCTAssertEqual(letter.listedAttachments.map(\.filename), ["x.pdf", "Programme.pdf"])
        // Its files drawn above the words cut short, under the pane's line,
        // each saying "Downloading", as it comes as the letter opens, or,
        // too large to, "Tap to Download" (B-170, B-176).
        let page = try XCTUnwrap(PanePage.letter(letter, style: .init(inset: 26, bodyPointSize: 17,
                                                                      lineHeight: 1.41)))
        let tiles = letter.listedAttachments.map { BodyFiles.tile($0, of: letter, on: .light) }
        var from = page.startIndex
        for needle in [PanePage.shortenedLine] + tiles + ["<p>xxx"] {
            let found = try XCTUnwrap(page.range(of: needle, range: from..<page.endIndex), needle)
            from = found.upperBound
        }
        let said = letter.listedAttachments.map {
            FilesAhead.fetches($0, of: letter) ? BodyFiles.downloading : BodyFiles.tapToDownload
        }
        for words in Set(said) {
            XCTAssertEqual(page.components(separatedBy: ">" + words + "</span>").count - 1,
                           said.filter { $0 == words }.count, words)
        }
        XCTAssertEqual(said.count, 2)
    }

    /// A letter opened without its files says so of each: its tile says
    /// "Downloading" with Mail's ring, as Mail's says while it fetches a
    /// large letter's files as it opens (B-176), and the file comes by its
    /// section alone (B-054), as a tap fetches it; one too large to come
    /// unasked says "Tap to Download", as Mail's says of a file it has not
    /// downloaded. The same letter fetched whole has its files in hand,
    /// and its tile says nothing of it (B-170).
    func testALetterOpenedWithoutItsFilesHasTilesThatSayDownloading() async throws {
        let row = try await listed(photographs(), by: makeRepository())
        let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)

        let large = try await makeRepository().open(row)
        XCTAssertTrue(large.filesLeftOnServer)
        let page = try XCTUnwrap(PanePage.letter(large, style: style))
        XCTAssertEqual(large.listedAttachments.map(\.filename), ["Programme.pdf"])
        XCTAssertEqual(FilesAhead.planned(large), large.listedAttachments)
        XCTAssertTrue(page.contains(BodyFiles.tile(large.listedAttachments[0], of: large, on: .light)))
        XCTAssertEqual(page.components(separatedBy: ">Downloading</span>").count - 1, 1)
        XCTAssertEqual(page.components(separatedBy: BodyFiles.ring).count - 1, 1)
        XCTAssertFalse(page.contains("Tap to Download"))
        XCTAssertTrue(PanePage.stackBody(large).html.contains(">Downloading</span>"))
        let file = large.listedAttachments[0]
        let big = Attachment(id: file.id, filename: file.filename, mimeType: file.mimeType,
                             size: FilesAhead.most + 1)
        XCTAssertFalse(FilesAhead.fetches(big, of: large), "too large to come unasked")
        let waits = BodyFiles.tile(big, of: large, on: .light)
        XCTAssertTrue(waits.contains(">Tap to Download</span>"))
        XCTAssertFalse(waits.contains("bm-file-ring"))

        let whole = try await makeRepository(appLimits: true).open(row)
        XCTAssertFalse(whole.filesLeftOnServer)
        let wholePage = try XCTUnwrap(PanePage.letter(whole, style: style))
        XCTAssertTrue(wholePage.contains(BodyFiles.tile(whole.listedAttachments[0], of: whole, on: .light)))
        XCTAssertFalse(wholePage.contains("Tap to Download"))
    }

    // MARK: - A SEARCH in the connection log

    /// The Inbox's SEARCH, one line with a number for every letter, goes
    /// into the connection log as how many it found.
    func testASearchReplyIsLoggedAsACount() async throws {
        let repository = makeRepository()
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let received = Diagnostics.entries.filter { $0.direction == .received }.map(\.text)
        let count = server.uids(in: Server.inbox).count
        XCTAssertTrue(received.contains("* SEARCH {\(count) uids}"), "\(received)")
        XCTAssertFalse(received.contains { $0.hasPrefix("* SEARCH ") && !$0.hasSuffix("uids}") })
    }
}

/// A submission server per connection, and every letter they were given,
/// dot-stuffing undone.
private final class LargeLetterSubmissions: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [ScriptedSubmission] = []

    func next() -> ScriptedSubmission {
        let server = ScriptedSubmission()
        lock.lock()
        made.append(server)
        lock.unlock()
        return server
    }

    private var servers: [ScriptedSubmission] {
        lock.lock()
        defer { lock.unlock() }
        return made
    }

    func letters() async -> [Data] {
        var all: [Data] = []
        for server in servers {
            for stuffed in await server.letters {
                var letter = String(decoding: stuffed, as: UTF8.self)
                    .replacingOccurrences(of: "\r\n..", with: "\r\n.")
                if letter.hasPrefix("..") { letter.removeFirst() }
                all.append(Data(letter.utf8))
            }
        }
        return all
    }
}
