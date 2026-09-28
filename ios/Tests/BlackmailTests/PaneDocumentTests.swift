import XCTest
@testable import Blackmail

/// The reading pane's document, without the web view: a conversation's
/// bodies held until its document has loaded, what is drawn again when
/// WebKit's content process ends, and the header sized for a letter's files
/// before the letter comes. `MessageDetailViewController` runs its web view
/// through `PaneDocument`; the header is drawn from `Message.heading(for:)`.
final class PaneDocumentTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "PaneDocumentTests"

    /// Stands in for a `WKNavigation`, whose identity is all the pane uses.
    private final class Navigation {}

    private func entry(_ id: String, open: Bool = false) -> ConversationDocument.Entry {
        ConversationDocument.Entry(id: id, sender: "Sam Example <sam@example.com>",
                                   date: Server.newestDate, body: nil, isExpanded: open,
                                   preview: "A few words")
    }

    private let body = ConversationDocument.Entry.Rendered(html: "Dear Sam,", isHTML: false)

    private func script(_ id: String, _ body: ConversationDocument.Entry.Rendered) -> String {
        ConversationDocument.javascriptFill(sectionID: ConversationDocument.sectionID(for: id),
                                            html: body.html, isHTML: body.isHTML)
    }

    private func entries(_ content: PaneDocument.Content) -> [ConversationDocument.Entry]? {
        guard case .conversation(let entries) = content else { return nil }
        return entries
    }

    // MARK: - Bodies that come before their document (pane-13)

    /// A body that comes while the stack's document is still loading waits
    /// for it, and goes in once it has finished; it used to be run against
    /// the page before, find no section, and be lost, leaving the letter on
    /// "Loading…". Once the document has loaded, a body goes straight in.
    func testABodyThatComesBeforeTheStackHasLoadedWaitsForIt() {
        var document = PaneDocument()
        let navigation = Navigation()
        document.loaded(.conversation([entry("7/3", open: true), entry("7/2")]),
                        navigation: ObjectIdentifier(navigation))

        XCTAssertNil(document.fill("7/3", with: body), "the document is still loading")
        let later = ConversationDocument.Entry.Rendered(html: "<p>Dear Carlo,</p>", isHTML: true)
        XCTAssertNil(document.fill("7/2", with: later))
        XCTAssertEqual(document.didFinish(ObjectIdentifier(navigation)),
                       [script("7/3", body), script("7/2", later)], "in the order they came")
        XCTAssertEqual(document.didFinish(ObjectIdentifier(navigation)), [], "once")
        XCTAssertEqual(document.fill("7/3", with: body), script("7/3", body), "loaded: at once")
    }

    /// Bodies waiting for a document go with it when another replaces it
    /// first, and the first one's finishing, if WebKit reports it, puts in
    /// nothing. A body for a letter the stack does not hold, or when the
    /// pane shows no stack, goes nowhere.
    func testBodiesWaitingForAReplacedDocumentAreDropped() {
        var document = PaneDocument()
        let first = Navigation()
        let second = Navigation()
        document.loaded(.conversation([entry("7/3", open: true)]), navigation: ObjectIdentifier(first))
        XCTAssertNil(document.fill("7/3", with: body))
        document.loaded(.conversation([entry("7/9", open: true)]), navigation: ObjectIdentifier(second))
        XCTAssertEqual(document.didFinish(ObjectIdentifier(first)), [])
        // The first one's finishing did not finish the second: a body for it
        // still waits, and goes in when the second has loaded.
        XCTAssertNil(document.fill("7/9", with: body), "the second document is still loading")
        XCTAssertEqual(document.didFinish(ObjectIdentifier(second)), [script("7/9", body)])

        XCTAssertNil(document.fill("7/3", with: body), "not a letter of this stack")
        document.loaded(.notice([PaneNotice.loading]), navigation: ObjectIdentifier(first))
        XCTAssertNil(document.fill("7/9", with: body), "no stack on screen")

        // A load WebKit gave no navigation for is taken as loaded.
        document.loaded(.conversation([entry("7/9", open: true)]), navigation: nil)
        XCTAssertEqual(document.fill("7/9", with: body), script("7/9", body))
    }

    // MARK: - WebKit's content process ending (pane-7)

    /// A clock the test moves.
    private final class Clock {
        var now = Server.newestDate
    }

    private func redrawn(_ redraw: PaneDocument.Redraw?) -> [ConversationDocument.Entry]? {
        redraw.flatMap { entries($0.content) }
    }

    /// The process ends with a conversation on screen: it is drawn again
    /// from what the pane holds, the letters he had opened and closed, and
    /// the bodies that had come, the one that could not be downloaded
    /// among them. Nothing used to answer, and the pane stayed black or on
    /// "Loading…".
    ///
    /// Drawn as the stack was first drawn, with no body in the document,
    /// and each body put back into its section by script once it has
    /// loaded, in the stack's order. The redraw used to write the bodies
    /// into the document, where a sender's broken markup is not held inside
    /// its letter's section, as it is put in by script: an unclosed `<div>`
    /// hid every later letter inside a closed one, and an unclosed comment
    /// swallowed the page's own script.
    func testAConversationIsDrawnAgainWithItsBodiesPutBackByScript() throws {
        var document = PaneDocument()
        document.loaded(.conversation([entry("7/3", open: true), entry("7/2"), entry("7/1")]),
                        navigation: nil)
        let broken = ConversationDocument.Entry.Rendered(html: "<div><div><p>Dear Sam,</p><!--",
                                                         isHTML: true)
        _ = document.fill("7/3", with: broken)
        document.setOpen(true, "7/2")
        let failed = ConversationDocument.Entry.Rendered(
            html: "<span class=\"bm-waiting\">This message could not be downloaded.</span>",
            isHTML: false)
        _ = document.fill("7/2", with: failed)
        document.setOpen(false, "7/3")

        document.contentProcessEnded()
        let redraw = try XCTUnwrap(document.redraw())
        let stack = try XCTUnwrap(redrawn(redraw))
        XCTAssertEqual(stack.map(\.id), ["7/3", "7/2", "7/1"])
        XCTAssertEqual(stack.map(\.isExpanded), [false, true, false])
        XCTAssertEqual(stack.map(\.body), [nil, nil, nil], "no body in the document")
        XCTAssertEqual(redraw.bodies.map(\.id), ["7/3", "7/2"])
        XCTAssertEqual(redraw.bodies.map(\.body), [broken, failed])

        let html = ConversationDocument.html(entries: stack, inset: 20, bodyPointSize: 17,
                                             lineHeight: 1.4)
        XCTAssertFalse(html.contains("Dear Sam,"))
        XCTAssertFalse(html.contains("could not be downloaded"))
        XCTAssertTrue(html.contains("class=\"bm-letter bm-open\" id=\"m7_2\""))
        XCTAssertTrue(html.contains("class=\"bm-letter\" id=\"m7_3\""))

        // Drawn, and the bodies given back: they wait for the stack to load,
        // then go in by script, in order, and are kept for the next time.
        let navigation = Navigation()
        document.loaded(redraw.content, navigation: ObjectIdentifier(navigation))
        for (id, body) in redraw.bodies { XCTAssertNil(document.fill(id, with: body)) }
        XCTAssertEqual(document.didFinish(ObjectIdentifier(navigation)),
                       [script("7/3", broken), script("7/2", failed)])
        XCTAssertEqual(entries(document.content)?.map(\.body), [broken, failed, nil])
        XCTAssertNil(document.redraw(), "drawn again once")
    }

    /// Draws again what was lost, as the pane does, and returns it; nil
    /// when there is nothing to draw.
    private func drawAgain(_ document: inout PaneDocument,
                           navigation: Navigation? = nil) -> PaneDocument.Content? {
        guard let redraw = document.redraw() else { return nil }
        document.loaded(redraw.content, navigation: navigation.map(ObjectIdentifier.init))
        for (id, body) in redraw.bodies { _ = document.fill(id, with: body) }
        return redraw.content
    }

    private let letter = Message.heading(for: MessageSummary(
        id: "7/3", mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
        subject: "The garden", preview: "", date: Server.newestDate,
        isRead: true, isFlagged: false))

    /// One letter, or the grey words, are drawn again as they were; the
    /// empty page under a hidden web view is not, and neither is nothing.
    func testALetterOrANoticeIsDrawnAgainAndTheEmptyPaneIsNot() {
        var document = PaneDocument()
        XCTAssertFalse(document.holdsLetter)
        document.loaded(.letter(letter), navigation: nil)
        XCTAssertTrue(document.holdsLetter)
        document.contentProcessEnded()
        XCTAssertTrue(document.holdsLetter, "lost, and still to be cleared if the pane empties")
        guard case .letter(let again)? = drawAgain(&document) else {
            return XCTFail("the letter is drawn again")
        }
        XCTAssertEqual(again.id, "7/3")
        XCTAssertNil(document.redraw(), "once")

        document.loaded(.notice([PaneNotice.loading]), navigation: nil)
        document.contentProcessEnded()
        guard case .notice(let lines)? = drawAgain(&document) else {
            return XCTFail("the notice is drawn again")
        }
        XCTAssertEqual(lines, [PaneNotice.loading])

        document.loaded(.blank, navigation: nil)
        XCTAssertFalse(document.holdsLetter)
        document.contentProcessEnded()
        XCTAssertNil(document.redraw(), "the empty page is not drawn again")
        document.contentProcessEnded()
        XCTAssertNil(document.redraw(), "nor is nothing")
    }

    /// The process ends while he is in another app, and the pane is drawn
    /// again only once he is back: a body that comes meanwhile is kept for
    /// it, and goes in with the rest. A new document the pane draws in the
    /// meantime replaces what was lost, and nothing is drawn again over it.
    func testALostConversationKeepsTheBodiesThatComeBeforeItIsDrawnAgain() throws {
        var document = PaneDocument()
        document.loaded(.conversation([entry("7/3", open: true), entry("7/2")]), navigation: nil)
        document.contentProcessEnded()
        XCTAssertNil(document.fill("7/3", with: body), "no page to put it in")
        let redraw = try XCTUnwrap(document.redraw())
        XCTAssertEqual(redraw.bodies.map(\.id), ["7/3"])
        XCTAssertEqual(redraw.bodies.map(\.body), [body])

        document.loaded(redraw.content, navigation: nil)
        document.contentProcessEnded()
        document.loaded(.notice([PaneNotice.loading]), navigation: nil)
        XCTAssertNil(document.redraw(), "the next letter's document took its place")
    }

    /// A document drawn again and lost again while it loads, or soon after,
    /// is taken as the letter itself ending WebKit's process, as full-size
    /// photographs can on an iPad short of memory: the pane says it could
    /// not be shown, and does not draw it a third time. It used to be drawn
    /// again at every loss, over and over, asking the server for its
    /// pictures each time. Lost again once it has lasted, it is iOS wanting
    /// the memory again, and it is drawn again as the first time.
    func testALetterLostAgainSoonAfterItIsDrawnAgainIsNotDrawnAThirdTime() {
        let clock = Clock()
        var document = PaneDocument(now: { clock.now })
        let navigation = Navigation()
        let finished = { (document: inout PaneDocument) in
            _ = document.didFinish(ObjectIdentifier(navigation))
        }

        // Lost again while the redraw loads.
        document.loaded(.letter(letter), navigation: ObjectIdentifier(navigation))
        document.contentProcessEnded()
        guard case .letter? = drawAgain(&document, navigation: navigation) else {
            return XCTFail("drawn again the first time")
        }
        clock.now += 60
        document.contentProcessEnded()
        guard case .notice([PaneDocument.cannotShow])? = drawAgain(&document) else {
            return XCTFail("the pane says so instead")
        }

        // Those words lost as quickly: nothing simpler is left to try.
        document.contentProcessEnded()
        XCTAssertNil(document.redraw())

        // Lost again soon after the redraw has loaded.
        document.loaded(.letter(letter), navigation: ObjectIdentifier(navigation))
        document.contentProcessEnded()
        _ = drawAgain(&document, navigation: navigation)
        finished(&document)
        clock.now += PaneDocument.settle - 1
        document.contentProcessEnded()
        guard case .notice([PaneDocument.cannotShow])? = drawAgain(&document) else {
            return XCTFail("not drawn a third time")
        }

        // A redraw that has lasted is drawn again when it is lost, and so
        // is a letter the pane drew itself, however soon.
        document.loaded(.letter(letter), navigation: ObjectIdentifier(navigation))
        document.contentProcessEnded()
        _ = drawAgain(&document, navigation: navigation)
        finished(&document)
        clock.now += PaneDocument.settle
        document.contentProcessEnded()
        guard case .letter? = drawAgain(&document, navigation: navigation) else {
            return XCTFail("it lasted: drawn again")
        }
        document.loaded(.letter(letter), navigation: nil)
        document.contentProcessEnded()
        guard case .letter? = drawAgain(&document) else {
            return XCTFail("the pane's own: drawn again")
        }
    }

    // MARK: - The header sized before the letter comes (pane-10)

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        server = nil
        book = nil
        super.tearDown()
    }

    private func makeRepository() -> IMAPMailRepository {
        IMAPMailRepository(account: server.account, password: server.password,
                           transport: server.transportFactory, recipients: book)
    }

    private func files(_ letter: Message) -> [String] {
        letter.listedAttachments.map { "\($0.id) \($0.filename) \($0.mimeType)" }
    }

    /// A letter with two files and a picture its body shows. The header is
    /// drawn from the row at the tap, and lists the same two files, under
    /// the same parts, that it lists once the letter has come, so it is
    /// already the height it will be. It used to list none until then, and
    /// grow a row of at least 44 pt per file when the letter landed,
    /// pushing a conversation's stack down under him.
    func testTheHeaderListsTheLettersFilesFromItsRow() async throws {
        let pdf = Server.File(name: "Roof quote.pdf", type: "APPLICATION", subtype: "PDF",
                              bytes: Data(repeating: 0x25, count: 3_000))
        let notes = Server.File(name: "notes.txt", type: "TEXT", subtype: "PLAIN",
                                bytes: Data("Gutters first.\r\n".utf8))
        let logo = Server.File(name: "logo.png", type: "IMAGE", subtype: "PNG",
                               bytes: Data(repeating: 0x89, count: 200), contentID: "logo@example.org")
        server.deliver(Server.Letter(from: Server.carlo, to: [Server.owner], subject: "The roof",
                                     date: Server.newestDate.addingTimeInterval(3_600),
                                     text: "The quote is attached.\r\n",
                                     html: "<p>The quote is attached. <img src=\"cid:logo@example.org\"></p>",
                                     messageID: "<roof@example.org>", files: [pdf, notes, logo]),
                       to: [Server.inbox])
        server.deliver(Server.Letter(from: Server.sam, to: [Server.owner], subject: "One file",
                                     date: Server.newestDate.addingTimeInterval(1_800),
                                     text: "Here it is.\r\n", messageID: "<one@example.org>",
                                     files: [pdf]),
                       to: [Server.inbox])
        let repository = makeRepository()
        let page = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 5)

        let roof = try XCTUnwrap(page.first { $0.subject == "The roof" })
        XCTAssertTrue(roof.hasAttachment)
        let landed = try await repository.loadMessage(id: roof.id, mailboxID: roof.mailboxID)
        XCTAssertEqual(files(landed), ["2 Roof quote.pdf application/pdf", "3 notes.txt text/plain"])
        XCTAssertEqual(files(Message.heading(for: roof)), files(landed))
        XCTAssertEqual(files(Message.heading(for: roof, subject: "Re: The roof")), files(landed),
                       "a conversation's header too")

        let one = try XCTUnwrap(page.first { $0.subject == "One file" })
        let oneLanded = try await repository.loadMessage(id: one.id, mailboxID: one.mailboxID)
        XCTAssertEqual(files(oneLanded), ["2 Roof quote.pdf application/pdf"])
        XCTAssertEqual(files(Message.heading(for: one)), files(oneLanded))

        // A letter with no files: nothing to list either way.
        let plain = try XCTUnwrap(page.first { $0.attachments.isEmpty && !$0.hasAttachment })
        let plainLanded = try await repository.loadMessage(id: plain.id, mailboxID: plain.mailboxID)
        XCTAssertEqual(files(plainLanded), [])
        XCTAssertEqual(files(Message.heading(for: plain)), [])
    }

    /// The fake server describes a text file as a server does, with the
    /// lines of its base64 after its size: six for a 320-byte file. It
    /// counted by splitting the text on "\n", which never splits a String
    /// whose lines end in "\r\n", one Character, and said one line however
    /// many there were.
    func testTheFakeCountsTheLinesOfATextFile() async throws {
        let notes = Server.File(name: "notes.txt", type: "TEXT", subtype: "PLAIN",
                                bytes: Data(repeating: 0x61, count: 320))
        let uid = try XCTUnwrap(server.deliver(
            Server.Letter(from: Server.carlo, to: [Server.owner], subject: "Notes",
                          date: Server.newestDate.addingTimeInterval(3_600),
                          text: "The notes.\r\n", messageID: "<notes@example.org>",
                          files: [notes]),
            to: [Server.inbox])[Server.inbox])
        let encoded = notes.bytes.base64EncodedString(
            options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])

        let transport = server.transportFactory("imap.example.com", server.port)
        try await transport.open()
        _ = try await transport.readLine()
        func exchange(_ tag: String, _ command: String) async throws -> [String] {
            try await transport.writeLine("\(tag) \(command)")
            var lines: [String] = []
            while true {
                let line = try await transport.readLine()
                lines.append(line)
                if line.hasPrefix(tag + " ") { return lines }
            }
        }
        _ = try await exchange("a1", "LOGIN \"\(server.username)\" \"\(server.password)\"")
        _ = try await exchange("a2", "SELECT INBOX")
        let reply = try await exchange("a3", "UID FETCH \(uid) (BODYSTRUCTURE)").joined()
        XCTAssertTrue(reply.contains("(\"NAME\" \"notes.txt\") NIL NIL \"BASE64\" "
                                     + "\(encoded.utf8.count) 6 NIL "), reply)
        await transport.close()
    }
}
