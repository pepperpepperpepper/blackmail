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
    /// for its structure and header, then its text and its HTML, each up to
    /// the section's size, and nothing else of it. It is the letter a whole
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
            "UID FETCH \(n) (UID BODY.PEEK[1.1]<0.\(Self.section)>)",
            "UID FETCH \(n) (UID BODY.PEEK[1.2]<0.\(Self.section)>)",
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
        XCTAssertTrue(page.contains("<div id=\"bm\"><p style=\"color: #8e8e93; margin: 0 0 1em 0; "
                                    + "white-space: normal;\">"
                                    + MailText.shortenedNotice + "</p><p>xxx"), page)
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
    /// asked for. The letter it names is shown.
    func testAKeptLargeRowIsOpenedInPartAndVouchedForByItsFirstFetch() async throws {
        let before = try await earlierLaunch()
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        let row = try XCTUnwrap(shelf.page(of: "inbox")?.rows.first { $0.id == before.id })
        server.clearLog()

        let letter = try await repository.open(row)
        let n = uid(row.id)
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN", "LIST", "SELECT", "UID FETCH",
                                                "UID FETCH", "UID FETCH"])
        XCTAssertEqual(uidFetches, [
            "UID FETCH \(n) (UID X-GM-MSGID BODYSTRUCTURE BODY.PEEK[HEADER])",
            "UID FETCH \(n) (UID BODY.PEEK[1.1]<0.\(Self.section)>)",
            "UID FETCH \(n) (UID BODY.PEEK[1.2]<0.\(Self.section)>)",
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
