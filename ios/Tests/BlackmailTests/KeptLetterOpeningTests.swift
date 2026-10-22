import XCTest
@testable import Blackmail

/// The letters he opened, kept on the iPad and shown from there (D-016's
/// phase 2, B-111), over the shipping repository and client, the scripted
/// IMAP server, a scripted submission server per connection and a shelf in
/// a directory of the test's own, as `KeptCopyTests` runs them. The line
/// can be taken down: then every connection is refused, as a connect with
/// no route is.
///
/// What is kept and what is not; a letter shown from the copy with nothing
/// sent, at once, at the next launch, with a connection and without, made
/// as the fetched letter is made; never where this launch's server has
/// named another letter there; never the server's word, so a write on it is
/// asked about; its pictures and files from it, by folder and id; a
/// Forward of it carrying the server's bytes; what takes it away; a
/// password saved; the log. And, read from the source, where the copy is
/// read and where it is not.
final class KeptLetterOpeningTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "KeptLetterOpeningTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var clock: ManualClock!
    private var line: OpeningLine!
    private var submissions: OpeningSubmissions!
    private var root: URL!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        clock = ManualClock()
        line = OpeningLine()
        submissions = OpeningSubmissions()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("KeptLetterOpeningTests-\(UUID().uuidString)", isDirectory: true)
        Diagnostics.clear()
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        if let root {
            MailShelf.wipe(root: kept)
            try? FileManager.default.removeItem(at: root)
        }
        for outcome in ["ok", "fail"] {
            let transcript = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
            try? FileManager.default.removeItem(atPath: transcript)
        }
        server = nil
        book = nil
        clock = nil
        line = nil
        submissions = nil
        root = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private var kept: URL { root.appendingPathComponent("Kept", isDirectory: true) }

    /// The shelf a launch makes, over whatever earlier ones left.
    private func makeShelf() -> MailShelf {
        let clock = self.clock!
        return MailShelf(root: kept, address: server.username, host: server.account.imapHost,
                         now: { clock.now() })
    }

    /// The app's repository over `shelf`: made again, it is the next
    /// launch's.
    private func makeRepository(shelf: MailShelf?,
                                largeLetterBytes: Int = IMAPMailRepository.largeLetterBytes)
        -> IMAPMailRepository {
        let imap = server.transportFactory
        let line = self.line!
        let submissions = self.submissions!
        let clock = self.clock!
        return IMAPMailRepository(
            account: server.account, password: server.password,
            transport: { host, port in
                guard line.isUp else {
                    return port == 465 ? ScriptedSubmission(failsToOpen: true) : imap(host, 1)
                }
                return port == 465 ? submissions.next() : imap(host, port)
            },
            recipients: book, now: { clock.now() }, signatureImages: { [] }, shelf: shelf,
            largeLetterBytes: largeLetterBytes)
    }

    /// An earlier launch, as it leaves the iPad: the folders swept, the
    /// Inbox listed from the top, the letters at `opened` opened from their
    /// rows as the reading pane opens them, and everything written, as
    /// going into the background writes it. The Inbox's rows.
    @discardableResult
    private func earlierLaunch(opening opened: [Int] = [0, 1]) async throws -> [MessageSummary] {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.listMailboxes()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        for i in opened { _ = try await repository.openLetter(rows[i]) }
        XCTAssertEqual(shelf.letters.records.count, opened.count, "kept")
        shelf.flush()
        return rows
    }

    /// The next launch: a shelf and a repository made afresh, and its kept
    /// Inbox rows, before any page has come.
    private func nextLaunch() throws -> (MailShelf, IMAPMailRepository, [MessageSummary]) {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        return (shelf, repository, try XCTUnwrap(shelf.page(of: "inbox")).rows)
    }

    private var verbs: [String] { server.log.map(\.verb) }

    private func uid(_ id: String) -> UInt32 { UInt32(id.split(separator: "/").last ?? "") ?? 0 }

    private var notes: [String] {
        Diagnostics.entries.filter { $0.direction == .note }.map(\.text)
            .filter { $0.hasPrefix("KEPT-LETTER") }
    }

    private var shown: Int { notes.filter { $0.hasPrefix("KEPT-LETTER shown") }.count }

    private func refusal(file: StaticString = #filePath, line: UInt = #line,
                         _ body: () async throws -> Void) async -> Error? {
        do {
            try await body()
            XCTFail("it went", file: file, line: line)
            return nil
        } catch {
            return error
        }
    }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<2_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    private static let style = PanePage.Style(inset: 20, bodyPointSize: 17, lineHeight: 1.4)

    /// The two letters field by field, the date too unless `date` is false.
    private func assertSame(_ a: Message, _ b: Message, date: Bool = true, _ what: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.id, b.id, what, file: file, line: line)
        XCTAssertEqual(a.mailboxID, b.mailboxID, what, file: file, line: line)
        XCTAssertEqual(a.sender, b.sender, what, file: file, line: line)
        XCTAssertEqual(a.senderAddress, b.senderAddress, what, file: file, line: line)
        XCTAssertEqual(a.to, b.to, what, file: file, line: line)
        XCTAssertEqual(a.cc, b.cc, what, file: file, line: line)
        XCTAssertEqual(a.bcc, b.bcc, what, file: file, line: line)
        XCTAssertEqual(a.replyTo, b.replyTo, what, file: file, line: line)
        XCTAssertEqual(a.from, b.from, what, file: file, line: line)
        XCTAssertEqual(a.subject, b.subject, what, file: file, line: line)
        if date { XCTAssertEqual(a.date, b.date, what, file: file, line: line) }
        XCTAssertEqual(a.textBody, b.textBody, what, file: file, line: line)
        XCTAssertEqual(a.htmlBody, b.htmlBody, what, file: file, line: line)
        XCTAssertEqual(a.attachments, b.attachments, what, file: file, line: line)
        XCTAssertEqual(a.messageID, b.messageID, what, file: file, line: line)
        XCTAssertEqual(a.inReplyTo, b.inReplyTo, what, file: file, line: line)
        XCTAssertEqual(a.references, b.references, what, file: file, line: line)
        XCTAssertEqual(a.gmailMessageID, b.gmailMessageID, what, file: file, line: line)
        XCTAssertEqual(a.isShortened, b.isShortened, what, file: file, line: line)
        XCTAssertEqual(PanePage.letter(a, style: Self.style), PanePage.letter(b, style: Self.style),
                       what, file: file, line: line)
        XCTAssertEqual(PanePage.stackBody(a), PanePage.stackBody(b), what, file: file, line: line)
    }

    private let plansBytes = Data((0..<3000).map { UInt8(truncatingIfNeeded: $0 &* 13 &+ 1) })
    private let roofBytes = Data((0..<1500).map { UInt8(truncatingIfNeeded: $0 &* 5 &+ 11) })

    /// Sam's "Plans", with Plans.pdf, the newest letter, in the Inbox and
    /// All Mail.
    @discardableResult
    private func deliverPlans() -> [String: UInt32] {
        server.deliver(Server.Letter(
            from: Server.sam, to: [Server.owner], subject: "Plans",
            date: Server.newestDate.addingTimeInterval(120), text: "The plans.\r\n",
            messageID: "<plans@example.com>",
            files: [Server.File(name: "Plans.pdf", type: "APPLICATION", subtype: "PDF",
                                bytes: plansBytes)]),
            to: [Server.inbox, Server.allMail])
    }

    /// Sam's "Roof", its words showing its one picture by `cid:`.
    @discardableResult
    private func deliverRoof() -> [String: UInt32] {
        server.deliver(Server.Letter(
            from: Server.sam, to: [Server.owner], subject: "Roof",
            date: Server.newestDate.addingTimeInterval(60),
            html: "<p>The roof.</p><img src=\"cid:roof1\">", messageID: "<roof@example.com>",
            files: [Server.File(name: "roof.jpg", type: "IMAGE", subtype: "JPEG", bytes: roofBytes,
                                contentID: "roof1")]),
            to: [Server.inbox, Server.allMail])
    }

    /// A letter made of the bytes given, newest of all, in the Inbox and
    /// All Mail: `header` without its blank line, and `body` with its
    /// sections and BODYSTRUCTURE.
    @discardableResult
    private func deliverRaw(_ subject: String, header: String, body: Data,
                            sections: [String: Data], structure: String,
                            at offset: TimeInterval) -> [String: UInt32] {
        let head = Data((header + "\r\n").utf8)
        var all = sections
        all["HEADER"] = head
        all["TEXT"] = body
        return server.deliver(
            raw: head + body, sections: all, structure: structure,
            as: Server.Letter(from: Server.carlo, to: [Server.owner], subject: subject,
                              date: Server.newestDate.addingTimeInterval(offset), text: "",
                              messageID: "<\(subject.filter(\.isLetter))@example.org>"),
            to: [Server.inbox, Server.allMail])
    }

    // MARK: - Opened and kept

    /// A letter opened from a row this launch has listed: the FETCH is the
    /// one `loadMessage` sends, byte for byte, and the letter is kept. The
    /// same row opened again in the launch is shown from the copy with
    /// nothing sent, the same letter.
    func testOpenedOnlineTheFetchIsLoadMessagesAndOpenedAgainNothingIsSent() async throws {
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.listMailboxes()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let plain = makeRepository(shelf: nil)
        _ = try await plain.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()

        let fetched = try await repository.openLetter(rows[0])
        let opened = server.log.map(\.command)
        server.clearLog()
        _ = try await plain.loadMessage(id: rows[0].id, gmailMessageID: rows[0].gmailMessageID,
                                        mailboxID: rows[0].mailboxID)
        XCTAssertEqual(opened, server.log.map(\.command))
        XCTAssertEqual(opened, ["UID FETCH \(uid(rows[0].id)) (UID BODY.PEEK[])"])
        XCTAssertEqual(shelf.letters.records.map(\.uid), [uid(rows[0].id)])
        XCTAssertEqual(shelf.letters.records.first?.message, rows[0].gmailMessageID)
        XCTAssertEqual(shelf.letters.records.first?.folder, Server.inbox)

        server.clearLog()
        let again = try await repository.openLetter(rows[0])
        XCTAssertEqual(server.log, [], "nothing sent")
        assertSame(fetched, again, "the same letter")
        XCTAssertEqual(shown, 1)
        XCTAssertEqual(notes.filter { $0.hasPrefix("KEPT-LETTER kept") }.count, 1)
    }

    /// The next launch, from the kept rows before any page has come: each
    /// letter opened before is shown with no command at all, not even the
    /// LOGIN, with a connection and without.
    func testTheNextLaunchShowsAKeptLetterWithNoCommandAtAllOnlineAndOffline() async throws {
        let before = try await earlierLaunch()
        let connections = server.connectionsOpened
        server.clearLog()

        let (shelf, online, rows) = try nextLaunch()
        XCTAssertEqual(rows.map(\.id), before.map(\.id))
        XCTAssertEqual(shelf.letters.records.map(\.uid), [uid(rows[0].id), uid(rows[1].id)])
        // Through the protocol, as the reading pane holds its repository.
        let pane: MailRepository = online
        let second = try await pane.openLetter(rows[1])
        let first = try await pane.openLetter(rows[0])
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(server.connectionsOpened, connections, "no connection made")
        shelf.flush()
        XCTAssertEqual(makeShelf().letters.records.map(\.uid), [uid(rows[1].id), uid(rows[0].id)],
                       "each showing made its letter the newest")
        XCTAssertEqual(first.subject, before[0].subject)
        XCTAssertEqual(second.subject, before[1].subject)

        line.isUp = false
        let (_, offline, keptRows) = try nextLaunch()
        let again = try await offline.openLetter(keptRows[1])
        assertSame(second, again, "offline")
        XCTAssertEqual(server.log, [])
        XCTAssertEqual(shown, 3)
    }

    /// With no connection, a letter never opened fails as it does today,
    /// and nothing is kept.
    func testOfflineALetterNeverOpenedFailsAsTodayAndNothingIsKept() async throws {
        try await earlierLaunch()
        line.isUp = false
        let (shelf, repository, rows) = try nextLaunch()
        let failed = await refusal { _ = try await repository.openLetter(rows[5]) }
        XCTAssertEqual(failed as? MailError, .cannotConnect)
        XCTAssertEqual(shelf.letters.records.count, 2)
        XCTAssertFalse(shelf.letters.records.contains { $0.uid == uid(rows[5].id) })
    }

    // MARK: - Made as the fetched letter is

    /// The letter from the copy is the fetched one, field by field, and so
    /// are the pane's page and the stack's body built from it, for every
    /// shape of letter: plain, HTML, plain and HTML, related with a `cid:`
    /// picture, mixed with a picture and with a file, ISO-8859-1, encoded
    /// words in its header, and with no Date, whose date both ways is the
    /// time it was decoded and is left out.
    func testTheLetterFromTheCopyIsTheFetchedOneFieldByFieldForEveryShape() async throws {
        deliverPlans()
        deliverRoof()
        server.deliver(Server.Letter(from: Server.jane, to: [Server.owner], cc: [Server.carlo],
                                     subject: "Both", date: Server.newestDate.addingTimeInterval(30),
                                     text: "Plain words.\r\n", html: "<p>Rich <b>words</b>.</p>",
                                     messageID: "<both@example.com>", inReplyTo: "<earlier@x>",
                                     references: "<first@x> <earlier@x>"),
                       to: [Server.inbox, Server.allMail])
        let latin = Data("Caf\u{E9} au lait, \u{E0} bient\u{F4}t.\r\n".unicodeScalars
                            .map { UInt8($0.value) })
        deliverRaw("Latin", header: "From: Carlo <carlo@example.org>\r\nTo: owner@example.com\r\n"
                   + "Subject: Latin\r\nDate: Tue, 20 Oct 2026 10:00:00 +0000\r\n"
                   + "Message-ID: <Latin@example.org>\r\nMIME-Version: 1.0\r\n"
                   + "Content-Type: text/plain; charset=ISO-8859-1\r\n"
                   + "Content-Transfer-Encoding: 8bit\r\n",
                   body: latin, sections: ["1": latin],
                   structure: "(\"TEXT\" \"PLAIN\" (\"CHARSET\" \"ISO-8859-1\") NIL NIL \"8BIT\" "
                    + "\(latin.count) 1 NIL NIL NIL NIL)", at: 200)
        let words = Data("Gr=C3=BC=C3=9Fe aus K=C3=B6ln.\r\n".utf8)
        deliverRaw("Encoded", header: "From: =?ISO-8859-1?Q?Jos=E9_Mart=EDnez?= <jose@example.com>\r\n"
                   + "To: =?UTF-8?B?SsO2cmc=?= <jorg@example.com>, owner@example.com\r\n"
                   + "Subject: =?UTF-8?Q?Gr=C3=BC=C3=9Fe_aus_K=C3=B6ln?= Encoded\r\n"
                   + "Date: Tue, 20 Oct 2026 11:00:00 +0200\r\n"
                   + "Message-ID: <Encoded@example.org>\r\nMIME-Version: 1.0\r\n"
                   + "Content-Type: text/plain; charset=utf-8\r\n"
                   + "Content-Transfer-Encoding: quoted-printable\r\n",
                   body: words, sections: ["1": words],
                   structure: "(\"TEXT\" \"PLAIN\" (\"CHARSET\" \"UTF-8\") NIL NIL "
                    + "\"QUOTED-PRINTABLE\" \(words.count) 1 NIL NIL NIL NIL)", at: 210)
        let undated = Data("No date on this one.\r\n".utf8)
        deliverRaw("Undated", header: "From: Carlo <carlo@example.org>\r\nTo: owner@example.com\r\n"
                   + "Subject: Undated\r\nMessage-ID: <Undated@example.org>\r\nMIME-Version: 1.0\r\n"
                   + "Content-Type: text/plain; charset=utf-8\r\n",
                   body: undated, sections: ["1": undated],
                   structure: "(\"TEXT\" \"PLAIN\" (\"CHARSET\" \"UTF-8\") NIL NIL \"7BIT\" "
                    + "\(undated.count) 1 NIL NIL NIL NIL)", at: 220)
        let html = "<p>The porch.</p><img src=\"cid:porch1\">\r\n"
        let picture = roofBytes.base64EncodedString(options: [.lineLength76Characters,
                                                              .endLineWithCarriageReturn,
                                                              .endLineWithLineFeed])
        let related = Data(("--rel\r\nContent-Type: text/html; charset=utf-8\r\n\r\n" + html
                            + "--rel\r\nContent-Type: image/jpeg; name=\"porch.jpg\"\r\n"
                            + "Content-Transfer-Encoding: base64\r\nContent-ID: <porch1>\r\n"
                            + "Content-Disposition: inline; filename=\"porch.jpg\"\r\n\r\n"
                            + picture + "\r\n--rel--\r\n").utf8)
        deliverRaw("Related", header: "From: Carlo <carlo@example.org>\r\nTo: owner@example.com\r\n"
                   + "Subject: Related\r\nDate: Tue, 20 Oct 2026 12:00:00 +0000\r\n"
                   + "Message-ID: <Related@example.org>\r\nMIME-Version: 1.0\r\n"
                   + "Content-Type: multipart/related; boundary=\"rel\"\r\n",
                   body: related, sections: ["1": Data(html.utf8), "2": Data(picture.utf8)],
                   structure: "((\"TEXT\" \"HTML\" (\"CHARSET\" \"UTF-8\") NIL NIL \"7BIT\" "
                    + "\(html.utf8.count) 1 NIL NIL NIL NIL)(\"IMAGE\" \"JPEG\" (\"NAME\" \"porch.jpg\") "
                    + "\"<porch1>\" NIL \"BASE64\" \(picture.utf8.count) NIL "
                    + "(\"INLINE\" (\"FILENAME\" \"porch.jpg\")) NIL NIL) \"RELATED\" "
                    + "(\"BOUNDARY\" \"rel\") NIL NIL NIL)", at: 230)

        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.listMailboxes()
        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        let subjects = ["Related", "Undated", "Encoded", "Latin", "Plans", "Roof",
                        "Both", rows[9].subject, rows[10].subject]
        var fetched: [String: Message] = [:]
        for subject in subjects {
            let row = try XCTUnwrap(rows.first { $0.subject == subject }, subject)
            fetched[subject] = try await repository.openLetter(row)
        }
        XCTAssertEqual(shelf.letters.records.count, subjects.count)
        XCTAssertEqual(fetched["Latin"]?.textBody?.hasPrefix("Café au lait, à bientôt."), true)
        XCTAssertEqual(fetched["Encoded"]?.sender, "José Martínez <jose@example.com>")
        XCTAssertEqual(fetched["Encoded"]?.subject, "Grüße aus Köln Encoded")
        XCTAssertTrue(fetched["Related"]?.htmlBody?.contains("cid:porch1") == true)
        shelf.flush()

        line.isUp = false
        let (_, offline, kept) = try nextLaunch()
        for subject in subjects {
            let row = try XCTUnwrap(kept.first { $0.subject == subject }, subject)
            let again = try await offline.openLetter(row)
            assertSame(try XCTUnwrap(fetched[subject]), again, date: subject != "Undated", subject)
        }
        XCTAssertEqual(shown, subjects.count)
    }

    // MARK: - Never where the server has named another letter

    /// A kept row whose UID this launch's server has named as another
    /// letter, by a page further down that keeps nothing and throws nothing
    /// away: the copy is not shown, the opening is refused with nothing
    /// sent, as today, and the refusal takes the kept letter.
    func testNotShownWhereTheServerHasNamedAnotherLetterAndRefusedWithNothingSent() async throws {
        try await earlierLaunch()
        let validity = server.uidValidity(of: Server.inbox)
        server.renumber(Server.inbox, validity: validity, firstUID: 1_002)
        let (shelf, repository, rows) = try nextLaunch()
        let target = rows[0]
        let page = try await repository.listMessages(in: "inbox",
                                                     beforeUID: "\(validity)/\(uid(target.id) + 1)",
                                                     limit: 5)
        let there = try XCTUnwrap(page.first { $0.id == target.id })
        XCTAssertNotEqual(there.gmailMessageID, target.gmailMessageID, "another letter there now")
        server.clearLog()

        let failed = await refusal { _ = try await repository.openLetter(target) }
        XCTAssertEqual(failed as? MailShelf.NotTheKeptLetter, MailShelf.NotTheKeptLetter())
        XCTAssertEqual(server.log, [], "nothing sent")
        XCTAssertEqual(shown, 0)
        XCTAssertFalse(shelf.letters.records.contains { $0.uid == uid(target.id) }, "taken")
        XCTAssertEqual(shelf.letters.records.count, 1)
    }

    /// A kept row of a folder this launch's server has given another
    /// UIDVALIDITY, by a search, which keeps nothing and throws nothing
    /// away: the copy is not shown, and the FETCH is not sent.
    func testNotShownWhereTheServerHasGivenTheFolderAnotherUIDValidity() async throws {
        try await earlierLaunch()
        server.renumber(Server.inbox, validity: server.uidValidity(of: Server.inbox) + 9,
                        firstUID: 1_000)
        let (_, repository, rows) = try nextLaunch()
        let hits = try await repository.search(in: "inbox", query: "garden", scope: .currentMailbox,
                                               beforeUID: nil, limit: 50)
        XCTAssertFalse(hits.isEmpty)
        server.clearLog()
        _ = await refusal { _ = try await repository.openLetter(rows[0]) }
        XCTAssertEqual(shown, 0)
        XCTAssertFalse(server.log.contains { $0.verb == "UID FETCH" })
    }

    /// A row naming another Gmail id than the letter was kept as, or none:
    /// not shown, and offline it fails as a letter never opened does.
    func testNotShownForAnotherGmailIDOrNone() async throws {
        try await earlierLaunch()
        line.isUp = false
        let (_, repository, rows) = try nextLaunch()
        var other = rows[0]
        other.gmailMessageID = rows[1].gmailMessageID
        var none = rows[0]
        none.gmailMessageID = nil
        for row in [other, none] {
            let failed = await refusal { _ = try await repository.openLetter(row) }
            XCTAssertEqual(failed as? MailError, .cannotConnect)
        }
        XCTAssertEqual(shown, 0)
        _ = try await repository.openLetter(rows[0])
        XCTAssertEqual(shown, 1)
    }

    /// The first page of a launch that says the copy was not this
    /// mailbox's, the Inbox renumbered or another letter under a kept UID,
    /// takes the kept letters with it: none is shown after.
    func testAfterARenumberedInboxOrAnotherLetterOnTheFirstPageNoneIsShown() async throws {
        for another in [false, true] {
            let rows = try await earlierLaunch()
            let validity = server.uidValidity(of: Server.inbox)
            if another {
                server.renumber(Server.inbox, validity: validity, firstUID: 1_002)
            } else {
                server.renumber(Server.inbox, validity: validity + 1, firstUID: 1_000)
            }
            let (shelf, repository, _) = try nextLaunch()
            _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
            XCTAssertEqual(shelf.letters.records, [], "another: \(another)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: shelf.letters.files.path))
            _ = try? await repository.openLetter(rows[0])
            XCTAssertEqual(shown, 0, "another: \(another)")
            MailShelf.wipe(root: kept)
        }
    }

    // MARK: - Not the server's word

    /// A letter shown from the copy is not the server's word in this
    /// launch: a read mark, a flag, a move and a delete on one each ask
    /// the server first, the vouching `UID FETCH` of its Gmail id, as on
    /// any row this launch has not had.
    func testAWriteOnALetterShownFromTheCopyIsVouchedForFirst() async throws {
        try await earlierLaunch(opening: [0, 1, 2, 3])
        server.clearLog()
        let (_, repository, rows) = try nextLaunch()
        for i in 0..<4 { _ = try await repository.openLetter(rows[i]) }
        XCTAssertEqual(shown, 4)
        XCTAssertEqual(server.log, [])

        try await repository.setRead(false, on: rows[0])
        try await repository.setFlagged(true, on: rows[1])
        try await repository.move(rows[2], to: Server.spam)
        try await repository.delete(rows[3])
        let asked = server.log.filter(\.isUIDCommand).map(\.command).filter {
            $0.hasSuffix("(UID X-GM-MSGID)")
        }
        XCTAssertEqual(asked, (0..<4).map { "UID FETCH \(uid(rows[$0].id)) (UID X-GM-MSGID)" })
        let writes = server.log.filter { ["UID STORE", "UID MOVE"].contains($0.verb) }
        XCTAssertEqual(writes.count, 4)
        for (question, write) in zip(asked, writes) {
            let q = try XCTUnwrap(server.log.firstIndex { $0.command == question })
            let w = try XCTUnwrap(server.log.firstIndex { $0 == write })
            XCTAssertLessThan(q, w)
        }
    }

    // MARK: - Never kept

    /// A letter opened in parts, too large to fetch whole, says why it is
    /// not kept; so do a Drafts letter, a row counted in Drafts, a row with
    /// no Gmail id, and an opening called off before its body came. A row
    /// whose Gmail id is not the one the server named is refused, and
    /// nothing of it kept.
    func testNeverKeptInPartsADraftAnUnnamedRowAnotherLetterOrACancelledOpen() async throws {
        let shelf = makeShelf()
        let small = makeRepository(shelf: shelf, largeLetterBytes: 100)
        _ = try await small.listMailboxes()
        let large = try await small.listMessages(in: "inbox", beforeUID: nil, limit: 5)
        _ = try await small.openLetter(large[0])
        XCTAssertEqual(notes.last, "KEPT-LETTER not-kept reason=size")

        let repository = makeRepository(shelf: shelf)
        _ = try await repository.listMailboxes()
        let drafts = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 5)
        _ = try await repository.openLetter(try XCTUnwrap(drafts.first))
        XCTAssertEqual(notes.last, "KEPT-LETTER not-kept reason=draft")
        let all = try await repository.listMessages(in: Server.allMail, beforeUID: nil, limit: 200)
        let counted = try XCTUnwrap(all.first { $0.countedFolderIDs.contains(Server.drafts) })
        _ = try await repository.openLetter(counted)
        XCTAssertEqual(notes.last, "KEPT-LETTER not-kept reason=draft")

        let rows = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        var unnamed = rows[0]
        unnamed.gmailMessageID = nil
        _ = try await repository.openLetter(unnamed)
        XCTAssertEqual(notes.last, "KEPT-LETTER not-kept reason=unnamed")
        var another = rows[1]
        another.gmailMessageID = rows[2].gmailMessageID
        let refused = await refusal { _ = try await repository.openLetter(another) }
        XCTAssertEqual(refused as? MailShelf.NotTheKeptLetter, MailShelf.NotTheKeptLetter())

        server.holdReplies(to: "UID FETCH")
        let opening = Task { try await repository.openLetter(rows[3]) }
        try await until { await server.heldReplies(to: "UID FETCH") > 0 }
        opening.cancel()
        await server.releaseReplies(to: "UID FETCH")
        _ = try? await opening.value
        XCTAssertEqual(notes.last, "KEPT-LETTER not-kept reason=cancelled")

        XCTAssertEqual(shelf.letters.records, [])
    }

    /// `loadMessage` and `loadDraft` keep nothing and show nothing from the
    /// copy: with the letter kept, `loadMessage`'s wire is as it always was.
    func testLoadMessageAndLoadDraftKeepNothingAndLoadMessagesWireIsUnchanged() async throws {
        let before = try await earlierLaunch(opening: [0])
        Diagnostics.clear()
        let (shelf, repository, _) = try nextLaunch()
        let records = shelf.letters.records
        _ = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        server.clearLog()
        _ = try await repository.open(before[0])
        _ = try await repository.open(before[1])
        XCTAssertEqual(server.log.map(\.command),
                       ["UID FETCH \(uid(before[0].id)) (UID BODY.PEEK[])",
                        "UID FETCH \(uid(before[1].id)) (UID BODY.PEEK[])"])
        let drafts = try await repository.listMessages(in: Server.drafts, beforeUID: nil, limit: 5)
        _ = try await repository.reopen(try XCTUnwrap(drafts.first))
        XCTAssertEqual(shelf.letters.records, records, "nothing kept, nothing touched")
        XCTAssertEqual(notes, [])
    }

    // MARK: - Nothing kept is sent

    /// A Forward of a letter shown from the copy, the kept file altered and
    /// its record's CRC made to match: what goes carries the server's bytes,
    /// its file FETCHed naming X-GM-MSGID, and offline it waits for the
    /// connection. The same for a draft of it saved to Drafts.
    func testAForwardOfALetterShownFromTheCopyCarriesTheServersBytes() async throws {
        let plans = try XCTUnwrap(deliverPlans()[Server.inbox])
        let rows = try await earlierLaunch(opening: [])
        let row = try XCTUnwrap(rows.first { $0.subject == "Plans" })
        do {
            let shelf = makeShelf()
            let repository = makeRepository(shelf: shelf)
            _ = try await repository.listMailboxes()
            _ = try await repository.openLetter(row)
            XCTAssertEqual(shelf.letters.records.count, 1)
            shelf.flush()
        }

        // The kept file changed, the PDF in it other bytes of the same
        // length, and the index's CRC made to match, so the check passes.
        let altered = Data(plansBytes.reversed())
        try alterKept(replacing: plansBytes, with: altered)
        server.clearLog()

        let (shelf, repository, kept) = try nextLaunch()
        let keptRow = try XCTUnwrap(kept.first { $0.id == row.id })
        let message = try await repository.openLetter(keptRow)
        XCTAssertEqual(shown, 1)
        let file = try XCTUnwrap(message.attachments.first { $0.filename == "Plans.pdf" })
        let onScreen = try await repository.fetchAttachmentData(file.id, of: message.id,
                                                               mailboxID: message.mailboxID)
        XCTAssertEqual(onScreen, altered, "the pane shows what was kept")
        XCTAssertEqual(server.log, [])

        var forward = Draft.forwarding(message)
        forward.to = ["carlo@example.org"]
        try await repository.send(forward, progress: nil)
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(carries(sent.last, plansBytes), "the server's file")
        XCTAssertFalse(carries(sent.last, altered))
        let fetches = server.log.filter { $0.verb == "UID FETCH" }.map(\.command)
        XCTAssertTrue(fetches.contains { $0.hasPrefix("UID FETCH \(plans) (") && $0.contains("X-GM-MSGID") },
                      fetches.joined(separator: "\n"))
        XCTAssertTrue(fetches.contains("UID FETCH \(plans) (UID BODY.PEEK[2])"))

        // A part that names no letter, as one kept by a build before the
        // ids were, goes from the server too, by folder and UID.
        var unnamed = forward
        unnamed.attachments = forward.attachments.map { attachment in
            guard case let .messagePart(id, mailbox, section, _) = attachment.source else {
                return attachment
            }
            return DraftAttachment(source: .messagePart(messageID: id, mailboxID: mailbox,
                                                        section: section, letter: nil),
                                   filename: attachment.filename, mimeType: attachment.mimeType,
                                   size: attachment.size)
        }
        try await repository.send(unnamed, progress: nil)
        let both = await submissions.letters()
        XCTAssertEqual(both.count, 2)
        XCTAssertTrue(carries(both.last, plansBytes), "the server's file, named by folder and UID")
        XCTAssertFalse(carries(both.last, altered))

        _ = try await repository.saveDraft(forward)
        let draft = try XCTUnwrap(server.uids(in: Server.drafts).compactMap {
            server.raw(uid: $0, in: Server.drafts)
        }.last { String(decoding: $0, as: UTF8.self).contains("Plans.pdf") })
        XCTAssertTrue(carries(String(decoding: draft, as: UTF8.self), plansBytes))
        XCTAssertFalse(carries(String(decoding: draft, as: UTF8.self), altered))

        line.isUp = false
        await server.resetConnections()
        let offline = makeRepository(shelf: shelf)
        let again = try await offline.openLetter(keptRow)
        var waiting = Draft.forwarding(again)
        waiting.to = ["carlo@example.org"]
        let failed = await refusal { try await offline.send(waiting, progress: nil) }
        XCTAssertEqual(failed as? MailError, .cannotConnect, "it waits for the connection")
        let draftFailed = await refusal { _ = try await offline.saveDraft(waiting) }
        XCTAssertEqual(draftFailed as? MailError, .cannotConnect)
        let sentAfter = await submissions.letters()
        XCTAssertEqual(sentAfter.count, 2, "nothing more went")
    }

    /// The kept letter's file with `old` bytes, base64 as the server sent
    /// them, made `new`, and its record's CRC-32 rewritten to match.
    private func alterKept(replacing old: Data, with new: Data) throws {
        let shelf = makeShelf()
        let record = try XCTUnwrap(shelf.letters.records.first)
        let url = shelf.letters.files.appendingPathComponent(record.file)
        let options: Data.Base64EncodingOptions = [.lineLength76Characters,
                                                   .endLineWithCarriageReturn, .endLineWithLineFeed]
        var raw = try Data(contentsOf: url)
        let from = Data(old.base64EncodedString(options: options).utf8)
        let to = Data(new.base64EncodedString(options: options).utf8)
        XCTAssertEqual(from.count, to.count)
        let range = try XCTUnwrap(raw.range(of: from))
        raw.replaceSubrange(range, with: to)
        try raw.write(to: url)
        let index = shelf.directory.appendingPathComponent("letters.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: index))
                                    as? [String: Any])
        var letters = try XCTUnwrap(object["letters"] as? [[String: Any]])
        letters[0]["crc"] = Int(KeptLetters.crc(raw))
        object["letters"] = letters
        try JSONSerialization.data(withJSONObject: object).write(to: index)
    }

    private func carries(_ letter: String?, _ bytes: Data) -> Bool {
        letter?.contains(String(bytes.base64EncodedString().prefix(60))) == true
    }

    // MARK: - Its pictures and files

    /// The pictures and files of letters shown from the copy come from it
    /// with nothing sent, offline included: the last one shown's from
    /// memory, an earlier one's from its file. A part asked for under the
    /// same "<uidvalidity>/<uid>" in another folder is not served from it.
    func testThePicturesAndFilesOfALetterShownFromTheCopyComeFromItWithNothingSent() async throws {
        deliverPlans()
        deliverRoof()
        let rows = try await earlierLaunch(opening: [0, 1])
        XCTAssertEqual(Set(rows.prefix(2).map(\.subject)), ["Plans", "Roof"])

        line.isUp = false
        server.clearLog()
        let (_, repository, kept) = try nextLaunch()
        let roof = try await repository.openLetter(try XCTUnwrap(kept.first { $0.subject == "Roof" }))
        let picture = try XCTUnwrap(roof.attachments.first { $0.contentID == "roof1" })
        let shownRoof = try await repository.fetchAttachmentData(picture.id, of: roof.id,
                                                                mailboxID: roof.mailboxID)
        XCTAssertEqual(shownRoof, roofBytes)
        let plans = try await repository.openLetter(try XCTUnwrap(kept.first { $0.subject == "Plans" }))
        let pdf = try XCTUnwrap(plans.attachments.first { $0.filename == "Plans.pdf" })
        let shownPDF = try await repository.fetchAttachmentData(pdf.id, of: plans.id,
                                                               mailboxID: plans.mailboxID)
        XCTAssertEqual(shownPDF, plansBytes)
        let earlier = try await repository.fetchAttachmentData(picture.id, of: roof.id,
                                                              mailboxID: roof.mailboxID)
        XCTAssertEqual(earlier, roofBytes, "from its file, read again")

        for elsewhere in [Server.sent, Server.allMail] {
            let other = await refusal {
                _ = try await repository.fetchAttachmentData(pdf.id, of: plans.id, mailboxID: elsewhere)
            }
            XCTAssertNotNil(other, elsewhere)
        }
        XCTAssertEqual(server.log, [])
    }

    /// The letter shown from the copy at launch, and then a first page
    /// that says the copy was another mailbox's, its UID now another
    /// letter with a picture at the same part: that letter, opened from the
    /// fresh row, is fetched, and its picture is its own, not the one shown
    /// from the copy under the same folder and id.
    func testALetterFetchedUnderTheIDOfOneShownFromTheCopyServesItsOwnPicture() async throws {
        let porchBytes = Data((0..<1500).map { UInt8(truncatingIfNeeded: $0 &* 23 &+ 2) })
        server.deliver(Server.Letter(
            from: Server.jane, to: [Server.owner], subject: "Porch",
            date: Server.newestDate.addingTimeInterval(30),
            html: "<p>The porch.</p><img src=\"cid:porch1\">", messageID: "<porch@example.com>",
            files: [Server.File(name: "porch.jpg", type: "IMAGE", subtype: "JPEG", bytes: porchBytes,
                                contentID: "porch1")]),
            to: [Server.inbox, Server.allMail])
        deliverRoof()
        let before = try await earlierLaunch(opening: [0])
        // Renumbered under the UIDVALIDITY it had, so that the Roof's UID
        // holds the Porch, the letter before it.
        let count = UInt32(server.uids(in: Server.inbox).count)
        server.renumber(Server.inbox, validity: server.uidValidity(of: Server.inbox),
                        firstUID: uid(before[0].id) - 2 * (count - 2))

        let (shelf, repository, kept) = try nextLaunch()
        let roof = try await repository.openLetter(kept[0])
        XCTAssertEqual(roof.subject, "Roof")
        XCTAssertEqual(shown, 1)
        let fresh = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 50)
        XCTAssertEqual(shelf.letters.records, [], "the copy thrown away")
        let porchRow = try XCTUnwrap(fresh.first { $0.id == kept[0].id })
        XCTAssertEqual(porchRow.subject, "Porch")
        let porch = try await repository.openLetter(porchRow)
        let picture = try XCTUnwrap(porch.attachments.first { $0.contentID == "porch1" })
        XCTAssertEqual(picture.id, try XCTUnwrap(roof.attachments.first?.id))
        let data = try await repository.fetchAttachmentData(picture.id, of: porch.id,
                                                           mailboxID: porch.mailboxID)
        XCTAssertEqual(data, porchBytes)
    }

    // MARK: - Taken away

    /// Delete, a move to the Trash or to Spam, and an EXPUNGE from the
    /// Trash take the kept letter, every copy of it binned; a move out of
    /// All Mail to a label takes nothing.
    func testDeleteTrashSpamAndExpungeTakeTheKeptLetterAndAllMailToALabelDoesNot() async throws {
        server.addFolder("Family", attributes: ["\\HasNoChildren"], label: "Family",
                         validity: 600_100, firstUID: 10)
        let shelf = makeShelf()
        let repository = makeRepository(shelf: shelf)
        _ = try await repository.listMailboxes()
        let inbox = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let all = try await repository.listMessages(in: Server.allMail, beforeUID: nil, limit: 200)
        let trash = try await repository.listMessages(in: Server.trash, beforeUID: nil, limit: 5)
        for row in inbox.prefix(3) { _ = try await repository.openLetter(row) }
        let deletedInAll = try XCTUnwrap(all.first { $0.gmailMessageID == inbox[0].gmailMessageID })
        _ = try await repository.openLetter(deletedInAll)
        let filed = try XCTUnwrap(all.first { row in
            !inbox.prefix(3).contains { $0.gmailMessageID == row.gmailMessageID }
                && !row.countedFolderIDs.contains(Server.drafts)
        })
        _ = try await repository.openLetter(filed)
        let binned = try XCTUnwrap(trash.first)
        _ = try await repository.openLetter(binned)
        XCTAssertEqual(shelf.letters.records.count, 6)

        try await repository.delete(inbox[0])
        try await repository.move(inbox[1], to: Server.spam)
        try await repository.move(inbox[2], to: Server.trash)
        try await repository.delete(binned)
        try await repository.move(filed, to: "Family")
        let left = shelf.letters.records
        XCTAssertEqual(left.map(\.folder), [Server.allMail])
        XCTAssertEqual(left.map(\.message), [filed.gmailMessageID])
        line.isUp = false
        let offline = makeRepository(shelf: shelf)
        for row in inbox.prefix(3) {
            _ = await refusal { _ = try await offline.openLetter(row) }
        }
        XCTAssertEqual(shown, 0)
    }

    // MARK: - A password saved

    /// A password saved wipes `Kept/`: the old repository's keep on its way
    /// lands nowhere, and the new one shows none.
    func testAPasswordSavedTheOldRepositorysKeepLandsNowhereAndTheNewOneShowsNone() async throws {
        let shelf = makeShelf()
        let old = makeRepository(shelf: shelf)
        _ = try await old.listMailboxes()
        let rows = try await old.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        _ = try await old.openLetter(rows[0])
        XCTAssertEqual(shelf.letters.records.count, 1)

        server.holdReplies(to: "UID FETCH")
        let opening = Task { try await old.openLetter(rows[1]) }
        try await until { await server.heldReplies(to: "UID FETCH") > 0 }
        MailShelf.wipe(root: kept)
        await server.releaseReplies(to: "UID FETCH")
        _ = try await opening.value
        shelf.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: kept.path), "landed nowhere")

        line.isUp = false
        let fresh = makeShelf()
        let new = makeRepository(shelf: fresh)
        for row in rows.prefix(2) {
            let failed = await refusal { _ = try await new.openLetter(row) }
            XCTAssertEqual(failed as? MailError, .cannotConnect)
        }
        XCTAssertEqual(shown, 0)
    }

    // MARK: - The log

    /// Nothing of a kept letter is written to the log beside the wire: a
    /// showing sends nothing, and its notes are numbers alone.
    func testNothingOfAKeptLetterIsWrittenToTheLog() async throws {
        deliverPlans()
        deliverRoof()
        try await earlierLaunch(opening: [0, 1, 2])
        Diagnostics.clear()
        let (_, repository, rows) = try nextLaunch()
        for row in rows.prefix(3) {
            let m = try await repository.openLetter(row)
            for file in m.attachments {
                _ = try await repository.fetchAttachmentData(file.id, of: m.id, mailboxID: m.mailboxID)
            }
        }
        XCTAssertEqual(shown, 3)
        let entries = Diagnostics.entries
        XCTAssertEqual(entries.filter { $0.direction != .note }.count, 0, "nothing sent")
        var words: Set<String> = ["Plans", "Roof", "plans.pdf", "Plans.pdf", "roof.jpg", "Sam Example",
                                  "sam@example.com", "INBOX"]
        for row in rows.prefix(3) { words.insert(row.subject) }
        for entry in entries {
            for word in words { XCTAssertFalse(entry.text.contains(word), entry.text) }
            for row in rows.prefix(3) {
                XCTAssertFalse(entry.text.contains(String(uid(row.id))), entry.text)
            }
        }
    }

    // MARK: - Read from the source

    /// The reading pane opens a row with `openLetter` in exactly its three
    /// places, the letter tapped, a conversation's newest and a letter of
    /// it opened; his letters from Sent Mail (B-104) go by `loadMessage`.
    /// `openLetter` is a requirement of the protocol itself, so the
    /// repository's own is the one the pane calls.
    func testThePaneOpensItsRowsWithOpenLetterAndHisSentMailWithLoadMessage() throws {
        let pane = try source("UI/MessageDetailViewController.swift")
        XCTAssertEqual(pane.components(separatedBy: "repository.openLetter(").count - 1, 3)
        XCTAssertTrue(pane.contains("try await repository.openLetter(summary)"))
        XCTAssertTrue(pane.contains("try await repository.openLetter(newest)"))
        XCTAssertTrue(pane.contains("loads.start({ try await repository.openLetter(row) }"))
        let related = try section(of: pane, from: "private func loadRelated(",
                                  to: "private func settleRelated(")
        XCTAssertTrue(related.contains("repository.loadMessage("))
        XCTAssertFalse(related.contains("openLetter"))
        XCTAssertEqual(pane.components(separatedBy: "repository.loadMessage(").count - 1, 1)

        let protocolFile = try source("Mail/MailRepository.swift")
        let requirements = try section(of: protocolFile, from: "protocol MailRepository {",
                                       to: "enum MailSearchScope")
        XCTAssertTrue(requirements.contains("func openLetter(_ row: MessageSummary) async throws -> Message"))
    }

    /// In the repository the copy of the letters is reached in three places
    /// alone: `keptLetter`, the keep after a whole FETCH, and `keptPart`.
    /// `keptLetter` neither makes the letter `lastBody` nor tells `seen`
    /// or the shelf's vouching. A forward's parts never come through the
    /// public `fetchAttachmentData`, and the letter on screen they may come
    /// from is `lastBody` alone.
    func testTheRepositoryReadsTheCopyInThreePlacesAndNeverForWhatIsSent() throws {
        let repository = try source("Mail/IMAPMailRepository.swift")
        XCTAssertEqual(repository.components(separatedBy: "shelf.letters.").count
                        + repository.components(separatedBy: "shelf?.letters.").count - 2, 3)
        let shown = try section(of: repository, from: "private func keptLetter(",
                                to: "private func keptFolderName(")
        XCTAssertTrue(shown.contains("shelf.letters.letter(in: name, validity: at.validity, "
                                     + "uid: at.uid, message: letter, touch: true)"))
        XCTAssertFalse(shown.contains("lastBody"))
        XCTAssertFalse(shown.contains("saw("))
        XCTAssertFalse(shown.contains("vouched"))
        XCTAssertFalse(shown.contains("lastStructure"))
        let keep = try section(of: repository, from: "private func keep(_ raw: Data,",
                               to: "private func loadLetterInPartOnce(")
        XCTAssertTrue(keep.contains("shelf?.letters.keep(raw, in: name, validity: validity, "
                                    + "uid: uid, message: named)"))
        let part = try section(of: repository, from: "private func keptPart(",
                               to: "private func fetchAttachmentDataNotKept(")
        XCTAssertTrue(part.contains("shelf?.letters.letter(in: name, validity: at.validity, "
                                    + "uid: at.uid, message: entry.letter, touch: false)"))

        let load = try section(of: repository, from: "private func loadMessageOnce(",
                               to: "private func keep(_ raw: Data,")
        XCTAssertTrue(load.contains("if let row { keep(raw, of: row, named: named, in: name, "
                                    + "uid: message.uid, validity: message.validity) }"))
        let public_ = try section(of: repository, from: "func loadMessage(id: String,",
                                  to: "private func loadMessageOnce(")
        XCTAssertTrue(public_.contains("whole: false) }"))
        XCTAssertFalse(public_.contains("keeping"))
        let draft = try section(of: repository, from: "func loadDraft(id: String,",
                                to: "private func draftsFolder()")
        XCTAssertFalse(draft.contains("keeping"))

        let carried = try section(of: repository, from: "private func fetchCarried(",
                                  to: "private func carriedPartIfThere(")
        XCTAssertFalse(carried.contains("try await fetchAttachmentData("))
        XCTAssertTrue(carried.contains("try await fetchAttachmentDataNotKept(section,"))
        let onScreen = try section(of: repository, from: "private func partOnScreen(",
                                   to: "private func carriedPart(")
        XCTAssertTrue(onScreen.contains("guard let cached = lastBody"))
        XCTAssertFalse(onScreen.contains("kept"))
        let notKept = try section(of: repository, from: "private func fetchAttachmentDataNotKept(",
                                  to: "private func fetchKnownPartOnce(")
        XCTAssertFalse(notKept.contains("kept"))
    }

    /// Nothing in the screens, Local Drafts, the Outbox's submission, SMTP
    /// or the share extension names the kept letters.
    func testTheKeptLettersAreNamedNowhereThatWritesOrSends() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources", isDirectory: true)
        let places = ["Blackmail/UI", "Blackmail/SMTP", "Blackmail/Share", "BlackmailShare",
                      "Blackmail/Mail/LocalDrafts.swift", "Blackmail/Mail/Submission.swift",
                      "Blackmail/Mail/Outbox.swift"]
        var read = 0
        for place in places {
            let url = sources.appendingPathComponent(place)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }
            let files = isDirectory.boolValue
                ? ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
                    .filter { $0.hasSuffix(".swift") }.map { url.appendingPathComponent($0) }
                : [url]
            for file in files {
                let text = try String(contentsOf: file, encoding: .utf8)
                read += 1
                for name in ["KeptLetters", "shelf?.letters", "shelf.letters", "keptPart",
                             "keptLetter", "keptOnScreen"] {
                    XCTAssertFalse(text.contains(name), "\(file.lastPathComponent): \(name)")
                }
            }
        }
        XCTAssertGreaterThan(read, 10)
    }

    // MARK: - Source helpers

    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }

    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/\(file)")
        let text = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        return flat(text)
    }

    private func section(of code: String, from start: String, to end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start), start)
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex), end)
        return String(code[from.lowerBound..<to.lowerBound])
    }
}

/// The network, up or down, from any thread.
private final class OpeningLine: @unchecked Sendable {
    private let lock = NSLock()
    private var up = true

    var isUp: Bool {
        get { lock.lock(); defer { lock.unlock() }; return up }
        set { lock.lock(); up = newValue; lock.unlock() }
    }
}

/// A submission server per connection, and every letter any was handed.
private final class OpeningSubmissions: @unchecked Sendable {
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

    func letters() async -> [String] {
        var out: [String] = []
        for server in servers {
            out += await server.letters.map { String(decoding: $0, as: UTF8.self) }
        }
        return out
    }
}
