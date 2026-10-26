import XCTest
@testable import Blackmail

/// A file drawn among a letter's words is listed once, there (B-148).
///
/// Mail draws a PDF put in the middle of a letter where it sat and has no
/// second row for it: Apple's iPadOS 18 guide and Mail's style sheet for
/// attachments (iOS 18.6) show every file in the body, none in a list
/// above it. Here such a file had two rows from B-113: its row among the
/// words, and its row in the header's file list (B-101). Now the header
/// leaves it out (`BodyFiles.inHeader`), decided from the letter's
/// structure (`MIMEDecoder.filesAmongWords`, by the pieces the body draws,
/// `drawnPieces`), so the header drawn at the tap, from the row, is the
/// header once the body has come, and does not change height under him.
final class FileListedOnceTests: XCTestCase {

    // MARK: - Letters

    private static func raw(_ text: String) -> Data {
        Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)
    }

    private static let top = """
        From: Jane <jane@example.com>
        To: owner@example.com
        Subject: The programme
        Date: Thu, 22 Oct 2026 14:35:17 +0000
        Message-ID: <programme@example.com>
        MIME-Version: 1.0

        """

    private static func pdf(_ name: String, disposition: String = "inline") -> String {
        """
        Content-Transfer-Encoding: base64
        Content-Type: application/pdf; name="\(name)"
        Content-Disposition: \(disposition); filename="\(name)"

        JVBERi0xLjQK
        """
    }

    private static func html(_ words: String) -> String {
        "Content-Type: text/html; charset=\"utf-8\"\n\n<div dir=\"ltr\">\(words)</div>"
    }

    private static func mixed(_ parts: [String], boundary: String = "MIX") -> String {
        "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\n\n"
            + parts.map { "--\(boundary)\n\($0)\n" }.joined() + "--\(boundary)--\n"
    }

    private static func letter(_ body: String) -> Data { raw(top + body) }

    /// The shapes, each with the files its page draws among its words.
    private static var shapes: [(name: String, raw: Data, among: Set<String>, listed: [String])] {
        [
            ("Apple Mail's, the plain words beside", BodyInOrderTests.among, ["2.2"], ["2.2"]),
            ("Apple Mail's, no plain words", BodyInOrderTests.mixed, ["2"], ["2"]),
            ("plain words split by a file, no HTML", BodyInOrderTests.plain, [], ["2"]),
            ("a file after all the words", letter(mixed([html("Here it is."), pdf("end.pdf")])),
             [], ["2"]),
            ("a file before all the words", letter(mixed([pdf("start.pdf"), html("Here it is.")])),
             [], ["1"]),
            ("two among the words and one at the end",
             letter(mixed([html("One."), pdf("a.pdf"), html("Two."), pdf("b.pdf", disposition: "attachment"),
                           html("Three."), pdf("c.pdf")])),
             ["2", "4"], ["2", "4", "6"]),
            ("a picture shown by cid among the words, which is no file",
             letter(mixed([html("Look:"), """
                 Content-Type: image/png; name="photo.png"
                 Content-Disposition: inline; filename="photo.png"
                 Content-ID: <photo@example.com>
                 Content-Transfer-Encoding: base64

                 iVBORw0KGgo=
                 """, html("<img src=\"cid:photo@example.com\"> Sent from my iPad")])),
             [], []),
            ("a note, a file, and a letter forwarded inline",
             letter(mixed([html("My note."), pdf("note.pdf"), """
                 Content-Type: message/rfc822
                 Content-Disposition: inline

                 From: Sam Example <sam@example.com>
                 Subject: Earlier
                 Content-Type: text/html; charset="utf-8"

                 <p>The forwarded words.</p>
                 """])),
             ["2"], ["2"]),
        ]
    }

    private static func message(_ raw: Data, id: String = "7/3") -> Message {
        let decoded = MIMEDecoder.decodeMessage(raw)
        var m = Message(id: id, mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                        senderAddress: "jane@example.com", to: ["owner@example.com"], cc: [],
                        subject: "The programme", date: Date(timeIntervalSince1970: 1_792_679_717),
                        textBody: decoded.text, htmlBody: decoded.html,
                        attachments: decoded.attachments, messageID: "<programme@example.com>")
        m.isShortened = decoded.isShortened
        return m
    }

    /// The list's row for the letter, its files from the structure alone,
    /// as the repository makes it from the BODYSTRUCTURE.
    private static func row(_ raw: Data, id: String = "7/3") -> MessageSummary {
        var row = MessageSummary(id: id, mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                                 subject: "The programme", preview: "", date: Date(timeIntervalSince1970: 1_792_679_717),
                                 isRead: false, isFlagged: false)
        row.attachments = MIMEDecoder.listedAttachments(in: MIMEDecoder.parseStructure(raw))
        return row
    }

    private let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)

    /// The files whose rows a page draws among the words, by their links.
    private func rows(in page: String, of m: Message) -> Set<String> {
        Set(m.listedAttachments.map(\.id).filter {
            page.contains(QuotedMarkup.attributeEscaped(BodyFiles.link($0, of: m.id)))
        })
    }

    // MARK: - Once

    /// Apple Mail's shape for a PDF put among the words: the header has no
    /// row for it, at the tap, from the row, and once the letter has come,
    /// and the page has its one row, where it sat. It is still the
    /// letter's file: listed for its row among the words to open, for a
    /// Forward and for Reply's question (`listedAttachments`), with the
    /// paperclip on its list row.
    func testAPDFAmongTheWordsIsListedOnceFromTheTap() throws {
        let raw = BodyInOrderTests.among
        let row = Self.row(raw)
        XCTAssertEqual(row.attachments.map(\.filename), ["Programme.pdf"])
        XCTAssertEqual(row.attachments.map(\.isAmongWords), [true])
        XCTAssertEqual(BodyFiles.inHeader(.heading(for: row)).map(\.id), [], "at the tap")

        let letter = Self.message(raw)
        XCTAssertEqual(letter.listedAttachments.map(\.id), ["2.2"])
        XCTAssertEqual(letter.attachments.map(\.isAmongWords), [true])
        XCTAssertEqual(BodyFiles.inHeader(letter).map(\.id), [], "once it has come")
        XCTAssertTrue(ReplyFiles.forwardAsks(letter), "a Forward asks about it, as before")
        XCTAssertTrue(IMAPMailRepository.hasAttachment(MIMEDecoder.parseStructure(raw)))

        let page = try XCTUnwrap(PanePage.letter(letter, style: style))
        XCTAssertEqual(rows(in: page, of: letter), ["2.2"])
        XCTAssertEqual(page.components(separatedBy: "Programme.pdf").count - 1, 1, "one row")
        let stack = PanePage.stackBody(letter).html
        XCTAssertEqual(rows(in: stack, of: letter), ["2.2"])
        XCTAssertEqual(stack.components(separatedBy: "Programme.pdf").count - 1, 1)
    }

    /// For every shape, the header leaves out exactly the files the page
    /// draws among the words, no more and no fewer, the same at the tap as
    /// once the letter has come, so its height does not change when the
    /// body comes: decided from the structure by the pieces `joined` draws
    /// (`drawnPieces`). A file before or after all the words, plain words
    /// split by a file, and a picture shown by `cid:` are as they were.
    func testTheHeaderLeavesOutExactlyTheFilesThePageDraws() throws {
        for shape in Self.shapes {
            // A picture shown by `cid:` has its mark too, which stays a
            // comment: it is no file, and the header never listed it.
            let structure = MIMEDecoder.parseStructure(shape.raw)
            XCTAssertEqual(MIMEDecoder.filesAmongWords(MIMEDecoder.bodyPlan(of: structure))
                            .intersection(shape.listed), shape.among, shape.name)
            let letter = Self.message(shape.raw)
            XCTAssertEqual(letter.listedAttachments.map(\.id), shape.listed, shape.name)
            let page = PanePage.letter(letter, style: style) ?? ""
            XCTAssertEqual(rows(in: page, of: letter), shape.among, shape.name)
            XCTAssertEqual(rows(in: PanePage.stackBody(letter).html, of: letter), shape.among, shape.name)

            let header = shape.listed.filter { !shape.among.contains($0) }
            XCTAssertEqual(BodyFiles.inHeader(letter).map(\.id), header, shape.name)
            XCTAssertEqual(BodyFiles.inHeader(.heading(for: Self.row(shape.raw))).map(\.id), header,
                           "\(shape.name), at the tap")
            XCTAssertEqual(Self.row(shape.raw).attachments.map(\.isAmongWords),
                           letter.listedAttachments.map(\.isAmongWords), shape.name)
        }
    }

    // MARK: - A cut

    /// A file whose mark could fall after a cut keeps its row in the
    /// header. A letter too large to fetch whole has each part of its HTML
    /// given what the parts before it left of the limit (`Allowance`), and
    /// nothing is drawn after words cut short, nor before words not
    /// fetched: so a file after a part longer than its share, or before a
    /// part given nothing, is not drawn among the words and keeps its row.
    /// One before a part given something, however little, is drawn, its
    /// mark going in before those words.
    func testAFileWhoseMarkCouldFallAfterACutKeepsItsHeaderRow() throws {
        func plan(_ first: Int, _ second: Int = 10) -> MIMEDecoder.BodyPlan {
            let raw = Self.letter(Self.mixed([
                "Content-Type: text/html; charset=\"utf-8\"\n\n" + String(repeating: "x", count: first),
                Self.pdf("p.pdf"),
                "Content-Type: text/html; charset=\"utf-8\"\n\n" + String(repeating: "y", count: second),
            ]))
            return MIMEDecoder.bodyPlan(of: MIMEDecoder.parseStructure(raw))
        }
        XCTAssertEqual(plan(400).html.compactMap(\.words?.size), [400, 10])
        XCTAssertEqual(MIMEDecoder.filesAmongWords(plan(400), limit: 1_000), ["2"])
        XCTAssertEqual(MIMEDecoder.filesAmongWords(plan(999), limit: 1_000), ["2"], "one byte left")
        XCTAssertEqual(MIMEDecoder.filesAmongWords(plan(999, 5_000), limit: 1_000), ["2"],
                       "the words after it cut, its mark before them")
        XCTAssertEqual(MIMEDecoder.filesAmongWords(plan(1_000), limit: 1_000), [], "nothing left after")
        XCTAssertEqual(MIMEDecoder.filesAmongWords(plan(1_001), limit: 1_000), [], "cut before it")

        // At the app's own limit: HTML of more than 2 MiB before the PDF.
        let limit = IMAPMailRepository.largeLetterSectionBytes
        XCTAssertEqual(limit, 2 << 20)
        XCTAssertEqual(MIMEDecoder.filesAmongWords(plan(limit - 1)), ["2"])
        XCTAssertEqual(MIMEDecoder.filesAmongWords(plan(limit + 1)), [])
        let raw = Self.letter(Self.mixed([
            "Content-Type: text/html; charset=\"utf-8\"\n\n" + String(repeating: "x", count: limit + 1),
            Self.pdf("p.pdf"), Self.html("After the PDF."),
        ]))
        // Fetched whole, as a letter of 2 MB is: the page draws its row,
        // and the header keeps one too, as both did before.
        let whole = Self.message(raw)
        XCTAssertEqual(rows(in: PanePage.letter(whole, style: style) ?? "", of: whole), ["2"])
        XCTAssertEqual(BodyFiles.inHeader(whole).map(\.id), ["2"])
        XCTAssertEqual(BodyFiles.inHeader(.heading(for: Self.row(raw))).map(\.id), ["2"])
    }

    // MARK: - Once the body has come

    /// The structure says a file is among the words, and the page does not
    /// draw it there after all: it keeps its row in the header, and the
    /// header grows by it as the body comes. The HTML refused and the plain
    /// words shown in its place, as a large letter's can be (B-114); HTML
    /// with nothing in it to show, which the pane says has no text; and
    /// HTML cut before the mark. A file whose mark is there is left out.
    func testAFileThePageDoesNotDrawAfterAllKeepsItsRow() {
        let pdf = Attachment(id: "2", filename: "Programme.pdf", mimeType: "application/pdf", size: 90_000,
                             contentID: nil, isInline: true, isAmongWords: true)
        func letter(text: String?, html: String?, shortened: Bool = false) -> Message {
            var m = Message(id: "7/3", mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                            senderAddress: "jane@example.com", to: [], cc: [], subject: "The programme",
                            date: Date(timeIntervalSince1970: 1_792_679_717), textBody: text, htmlBody: html,
                            attachments: [pdf])
            m.isShortened = shortened
            return m
        }
        let drawn = letter(text: nil, html: "<div>Before.</div>" + BodyFiles.mark("2") + "<div>After.</div>")
        XCTAssertEqual(BodyFiles.inHeader(drawn).map(\.id), [])
        XCTAssertEqual(BodyFiles.inHeader(letter(text: "Plain words.", html: nil, shortened: true)).map(\.id),
                       ["2"], "the HTML refused")
        let nothing = letter(text: nil, html: "<div><br></div>" + BodyFiles.mark("2") + "<div></div>")
        XCTAssertTrue(PanePage.isEmpty(nothing))
        XCTAssertEqual(BodyFiles.inHeader(nothing).map(\.id), ["2"], "nothing to show")
        XCTAssertEqual(BodyFiles.inHeader(letter(text: nil, html: "<div>Before, cut sho", shortened: true))
                        .map(\.id), ["2"], "cut before its mark")
        XCTAssertEqual(BodyFiles.inHeader(letter(text: nil, html: nil)).map(\.id), [], "the row's, at the tap")
    }

    // MARK: - Its row shows it coming

    /// With no row in the header, the row among the words shows the file
    /// coming, as the header's row did with its spinner: dimmed, important,
    /// "Loading…" after its name, once however often it is said, until the
    /// pane says it has opened or been let go, and then as it was. On a
    /// letter's own page and in a body of a stack; a file of another
    /// letter changes nothing. The script run in node on the model of the
    /// page (`ModelPage`).
    func testItsRowAmongTheWordsShowsItComing() throws {
        let letter = Self.message(BodyInOrderTests.among)
        let coming = BodyFiles.Busy("2.2", of: letter.id, busy: true)
        let done = BodyFiles.Busy("2.2", of: letter.id, busy: false)
        let link = BodyFiles.link("2.2", of: letter.id)
        XCTAssertEqual(coming.link, link)
        XCTAssertEqual(coming.arguments["words"] as? String, "Loading…")
        XCTAssertEqual(coming.arguments["busy"] as? Bool, true)
        XCTAssertEqual(done.arguments["busy"] as? Bool, false)
        let dimmed = ModelPage.Run.File(href: link, style: ["opacity": "0.5 !important"], marks: [" Loading…"])
        let asItWas = ModelPage.Run.File(href: link, style: [:], marks: [])

        let page = try XCTUnwrap(PanePage.letter(letter, style: style))
        let other = BodyFiles.Busy("2.2", of: "7/9", busy: true)
        var run = try model(page, [.busy(100, coming), .busy(120, other), .busy(150, coming)])
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.files, [dimmed], "coming, said twice, one mark")
        run = try model(page, [.busy(100, coming), .busy(300, done)])
        XCTAssertEqual(run.files, [asItWas], "opened or let go")
        run = try model(page, [.busy(100, other)])
        XCTAssertEqual(run.files, [asItWas], "another letter's file")

        let entry = ConversationDocument.Entry(id: letter.id, sender: letter.sender, date: letter.date,
                                               body: nil, isExpanded: true, preview: "The programme")
        let stack = ConversationDocument.html(entries: [entry], inset: 20, bodyPointSize: 17, lineHeight: 1.4)
        let fill = ConversationDocument.Fill(sectionID: ConversationDocument.sectionID(for: letter.id),
                                             body: PanePage.stackBody(letter))
        run = try model(stack, [.fill(50, fill), .busy(100, coming)])
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.files, [dimmed], "in a stack")
        run = try model(stack, [.fill(50, fill), .busy(100, coming), .busy(200, done)])
        XCTAssertEqual(run.files, [asItWas])
    }

    /// The pane, read: a tap shows the file coming on its row among the
    /// words, whichever letter it is of, beside the header's spinner; the
    /// `defer` that ends the download takes it off on the page it was
    /// shown on, and not on a page given since; by script, in the app's
    /// content world.
    func testThePaneShowsTheRowComingFromTheTapToTheEnd() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(code.contains(
            "if message?.id == m.id { header.setAttachment(attachment.id, busy: true) } "
                + "run(BodyFiles.Busy(attachment.id, of: m.id, busy: true)) let shown = loads.shown"))
        XCTAssertTrue(code.contains(
            "if message?.id == m.id { header.setAttachment(attachment.id, busy: false) } "
                + "if loads.stillShows(shown) { run(BodyFiles.Busy(attachment.id, of: m.id, busy: false)) } }"))
        XCTAssertTrue(code.contains(
            "private func run(_ busy: BodyFiles.Busy) { webView.callAsyncJavaScript(BodyFiles.Busy.script, "
                + "arguments: busy.arguments, in: nil, in: .defaultClient) }"))
        XCTAssertEqual(code.components(separatedBy: "BodyFiles.Busy(").count - 1, 2)
    }

    // MARK: - The pane

    /// Read from the source: the header lists `BodyFiles.inHeader` and
    /// nothing else; the decoder marks each file from the plan by the
    /// pieces the body draws, one function for both.
    func testTheHeaderAndTheBodyGoByOneRule() throws {
        let header = try source("UI/MessageHeaderView.swift")
        XCTAssertTrue(header.contains("let listed = BodyFiles.inHeader(m)"))
        XCTAssertFalse(header.contains("listedAttachments"))
        let decoder = try source("MIME/MIMEDecoder.swift")
        XCTAssertTrue(decoder.contains("let drawn = drawnPieces(pieces, asHTML: asHTML)"))
        XCTAssertTrue(decoder.contains("let drawn = drawnPieces(plan.html, asHTML: true)"))
        XCTAssertEqual(decoder.components(separatedBy: "drawnPieces(").count - 1, 3, "defined, and two uses")
        XCTAssertTrue(decoder.contains("let among = filesAmongWords(plan)"))
        XCTAssertEqual(decoder.components(separatedBy: "Allowance(plan, limit: limit)").count - 1, 1)
    }

    // MARK: - Helpers

    private func model(_ page: String, _ steps: [ModelPage.Step]) throws -> ModelPage.Run {
        do {
            return try ModelPage.run(ConversationDocument.script, page: page, steps: steps, end: 400)
        } catch is ModelPage.NoNode {
            throw XCTSkip("node is not on this host")
        }
    }

    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(file)")
        let text = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        return text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }
}
