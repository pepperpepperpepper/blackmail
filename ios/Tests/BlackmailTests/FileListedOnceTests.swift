import XCTest
@testable import Blackmail

/// Every file of a letter is drawn once, in its body, as Mail draws it
/// (B-170).
///
/// Mail has no list of files above a letter: each is in the body where it
/// sits in the letter, the files after the words at its end, a picture at
/// its size and any other file as Mail's tile (iOS 18.6's MobileMailUI:
/// `attachments.css`, and its attachment element's "Tap to Download").
/// Here the header listed every file from B-101 but, since B-148, a file
/// drawn among the words, which had its row there (B-113). Now the header
/// lists none (`MessageHeaderView`), and the pane draws every file in the
/// body (`BodyFiles.drawn`): at its mark, which the decoder leaves where a
/// file sits with words after it (`MIMEDecoder.joined`), and every file
/// with no mark after the words.
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

    private static func jpeg(_ name: String, contentID: String? = nil, disposition: String? = "attachment")
        -> String {
        "Content-Transfer-Encoding: base64\nContent-Type: image/jpeg; name=\"\(name)\"\n"
            + (disposition.map { "Content-Disposition: \($0); filename=\"\(name)\"\n" } ?? "")
            + (contentID.map { "Content-ID: <\($0)>\n" } ?? "")
            + "\n/9j/4AAQSkZJRgABAQ==\n"
    }

    private static func html(_ words: String) -> String {
        "Content-Type: text/html; charset=\"utf-8\"\n\n<div dir=\"ltr\">\(words)</div>"
    }

    private static func plain(_ words: String) -> String {
        "Content-Type: text/plain; charset=\"utf-8\"\n\n\(words)"
    }

    private static func mixed(_ parts: [String], boundary: String = "MIX") -> String {
        "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\n\n"
            + parts.map { "--\(boundary)\n\($0)\n" }.joined() + "--\(boundary)--\n"
    }

    private static func letter(_ body: String) -> Data { raw(top + body) }

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

    private let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)

    private func address(_ contentID: String) -> String {
        InlineImageRewriter.scheme + "://" + InlineImageRewriter.escapedHost(contentID)
    }

    /// How a page names the file at `section` of `m` where the pane drew
    /// it: its tile's link, or its picture's address.
    private func drawn(_ section: String, of m: Message) -> String {
        let file = m.listedAttachments.first { $0.id == section }!
        return BodyFiles.isPicture(file)
            ? address(BodyFiles.pictureID(section, of: m.id))
            : "href=\"" + QuotedMarkup.attributeEscaped(BodyFiles.link(section, of: m.id)) + "\""
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func order(_ needles: [String], in text: String, _ label: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        var from = text.startIndex
        for needle in needles {
            guard let found = text.range(of: needle, range: from..<text.endIndex) else {
                return XCTFail("\(label): \(needle) not after the one before it in \(text)", file: file, line: line)
            }
            from = found.upperBound
        }
    }

    // MARK: - Once, in the body

    /// Each shape: every file the letter lists drawn once, on the letter's
    /// own page and in its body in a stack, in its place among the words
    /// as the order says: among them where it sat, above them for a file
    /// before all of them, and after them for a file after all of them and
    /// for any file of a plain letter. A picture file is drawn as a picture
    /// at its address, any other file as its tile; a picture the HTML shows
    /// by `cid:` is the letter's, and drawn by it alone, once, a file or
    /// not; a letter of a file and no words is its tile, and not "This
    /// message has no text.".
    func testEveryFileIsDrawnOnceInTheBodyWhereItSits() throws {
        let photo = Self.jpeg("photo.jpg")
        let shapes: [(name: String, raw: Data, listed: [String], order: [String])] = [
            ("Apple Mail's, the plain words beside", BodyInOrderTests.among, ["2.2"],
             ["Words before the PDF", "2.2", "Words after the PDF", "Sent from my iPad"]),
            ("Apple Mail's, no plain words", BodyInOrderTests.mixed, ["2"],
             ["Here is the programme", "2", "Sent from my iPad"]),
            ("plain words split by a file", BodyInOrderTests.plain, ["2"],
             ["Words before the PDF.", "Words after the PDF.", "2"]),
            ("a file after all the words", Self.letter(Self.mixed([Self.html("Here it is."), Self.pdf("end.pdf")])),
             ["2"], ["Here it is.", "2"]),
            ("a file before all the words",
             Self.letter(Self.mixed([Self.pdf("start.pdf"), Self.html("Here it is.")])), ["1"],
             ["1", "Here it is."]),
            ("two among the words and one at the end",
             Self.letter(Self.mixed([Self.html("One."), Self.pdf("a.pdf"), Self.html("Two."),
                                     Self.pdf("b.pdf", disposition: "attachment"), Self.html("Three."),
                                     Self.pdf("c.pdf")])),
             ["2", "4", "6"], ["One.", "2", "Two.", "4", "Three.", "6"]),
            ("a photo attached after the words, and a PDF",
             Self.letter(Self.mixed([Self.html("Our garden."), photo, Self.pdf("plan.pdf")])), ["2", "3"],
             ["Our garden.", "2", "3"]),
            ("a plain letter with a photo", Self.letter(Self.mixed([Self.plain("Our garden."), photo])), ["2"],
             ["Our garden.", "2"]),
            ("a note, a file, and a letter forwarded inline",
             Self.letter(Self.mixed([Self.html("My note."), Self.pdf("note.pdf"), """
                 Content-Type: message/rfc822
                 Content-Disposition: inline

                 From: Sam Example <sam@example.com>
                 Subject: Earlier
                 Content-Type: text/html; charset="utf-8"

                 <p>The forwarded words.</p>
                 """])),
             ["2"], ["My note.", "2", "The forwarded words."]),
            ("a file and no words", Self.letter(Self.mixed([Self.pdf("only.pdf")])), ["1"], ["1"]),
        ]
        for shape in shapes {
            let m = Self.message(shape.raw)
            XCTAssertEqual(m.listedAttachments.map(\.id), shape.listed, shape.name)
            XCTAssertFalse(PanePage.isEmpty(m), shape.name)
            let page = try XCTUnwrap(PanePage.letter(m, style: style), shape.name)
            let stack = PanePage.stackBody(m).html
            for (kind, body) in [("page", page), ("stack", stack)] {
                let label = "\(shape.name), \(kind)"
                for section in shape.listed {
                    XCTAssertEqual(count(drawn(section, of: m), in: body), 1, "\(label): \(section) once")
                }
                order(shape.order.map { shape.listed.contains($0) ? drawn($0, of: m) : $0 }, in: body, label)
                XCTAssertFalse(body.contains("<!--bm-file:"), label)
                XCTAssertFalse(body.contains(MailText.emptyBodyNotice), label)
            }
        }

        // Pictures the HTML shows by `cid:`, among the words: the one sent
        // inline is no file, and the one sent with no word that it is
        // inline is listed, as B-101 lists it, and both drawn once, where
        // the letter draws them; nor is a `cid:` that only begins as one
        // of them taken for it.
        let shown = Self.letter(Self.mixed([
            Self.html("Look:"), Self.jpeg("logo.jpg", contentID: "logo@example.com", disposition: "inline"),
            Self.jpeg("photo.jpg", contentID: "photo@example.com", disposition: nil),
            Self.jpeg("other.jpg", contentID: "photo", disposition: nil),
            Self.html("<img src=\"cid:logo@example.com\"><img src=\"cid:photo@example.com\"> Sent from my iPad"),
        ]))
        let m = Self.message(shown)
        XCTAssertEqual(m.listedAttachments.map(\.id), ["3", "4"])
        let page = try XCTUnwrap(PanePage.letter(m, style: style))
        XCTAssertEqual(count(address("logo@example.com"), in: page), 1)
        XCTAssertEqual(count(address("photo@example.com"), in: page), 1)
        XCTAssertEqual(count("bmcid://bmfile-", in: page), 1, "the other photo, drawn by the pane")
        XCTAssertEqual(count(drawn("4", of: m), in: page), 1)
        XCTAssertFalse(page.contains("bmfile:"), "no tile")
    }

    /// A file's mark of the sender's own is drawn once, at the first; any
    /// other file of the letter with no mark goes after the words. The
    /// header lists no file, and the decoder no longer works out which are
    /// among the words: read from the source.
    func testTheHeaderListsNoFile() throws {
        let header = try source("UI/MessageHeaderView.swift")
        for files in ["listedAttachments", "m.attachments", "UIStackView", "attachmentStack", "BodyFiles",
                      "paperclip", "onSelectAttachment", "setAttachment"] {
            XCTAssertFalse(header.contains(files), files)
        }
        XCTAssertTrue(header.contains("bottomRule.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, "
                                      + "constant: Theme.detailDateAttachmentGap + Theme.detailAttachmentRuleGap)"))
        let decoder = try source("MIME/MIMEDecoder.swift")
        XCTAssertFalse(decoder.contains("filesAmongWords"))
        XCTAssertTrue(decoder.contains("guard asHTML, let last, i < last else { continue }"))
        XCTAssertFalse(try source("Model/MailModels.swift").contains("isAmongWords"))
    }

    // MARK: - Mail's tile

    /// The tile, as the style sheet left in Mail for its tiles has it: a
    /// box of 160 by 120, 5 apart, 3 inside a hairline border rounded at
    /// 15, its lines centred; an icon of 37 by 48 with 8 under it, the
    /// file's kind on it; the name and the size in the caption's type,
    /// grey, and the last line in the footnote's, bold and blue, cut with
    /// an ellipsis, each at 12 and 13 px, their sizes at the iPad's default
    /// text size, and none of WebKit's keywords for the system's type,
    /// which follow the text size in Settings (D-007); no callout,
    /// selection or drag. Light on an HTML letter's page, which the page's
    /// invert turns, dark on a plain letter's, light on paper. Its words
    /// escaped, and its link the pane's own.
    func testATileIsMailsTile() throws {
        let file = Attachment(id: "2", filename: "Rates & <Fees> \"2027\".pdf", mimeType: "application/pdf",
                              size: 90_000)
        var m = Message(id: "7/3", mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                        senderAddress: "jane@example.com", to: [], cc: [], subject: "Rates",
                        date: Date(timeIntervalSince1970: 1_792_679_717), textBody: "Rates.", htmlBody: nil,
                        attachments: [file])
        let light = BodyFiles.tile(file, of: m, on: .light)
        for rule in ["display: inline-block !important;", "box-sizing: content-box !important;",
                     "width: 160px !important;", "height: 120px !important;", "margin: 5px !important;",
                     "padding: 3px !important;", "border: 1px solid rgba(0, 0, 0, 0.3) !important;",
                     "border-radius: 15px !important;", "text-align: center;", "text-decoration: none;",
                     "-webkit-touch-callout: none !important;", "-webkit-user-select: none !important;",
                     "-webkit-user-drag: none !important;",
                     "<span style=\"display: block; position: relative; top: 50%; transform: translateY(-50%);\">",
                     "<svg width=\"37\" height=\"48\" viewBox=\"0 0 37 48\" style=\"display: block; "
                        + "margin: 0 auto 8px auto;\">",
                     ">PDF</text>",
                     "font: 12px -apple-system, sans-serif; color: rgba(4, 4, 15, 0.45);\">"
                        + "Rates &amp; &lt;Fees&gt; \"2027\".pdf</span>",
                     "font: 12px -apple-system, sans-serif; color: rgba(4, 4, 15, 0.45);\">"
                        + ByteCountFormatter.string(fromByteCount: 90_000, countStyle: .file) + "</span>",
                     "<span class=\"bm-file-status\" style=\"display: block; overflow: hidden; "
                        + "text-overflow: ellipsis; white-space: nowrap; font: bold 13px -apple-system, sans-serif; "
                        + "color: #007AFF;\"></span>"] {
            XCTAssertTrue(light.contains(rule), rule)
        }
        // Every line in a size written out: none moves with the text size
        // in Settings, and the box holds them at any.
        XCTAssertFalse(light.contains("-apple-system-"), light)
        XCTAssertEqual(count("font: ", in: light), 3)
        XCTAssertEqual(count("px -apple-system, sans-serif;", in: light), 3)
        XCTAssertTrue(light.hasPrefix("<a href=\"bmfile:2?letter=7/3\" style=\""), light)
        XCTAssertTrue(light.hasSuffix("</span></span></a>"), light)
        XCTAssertFalse(light.contains(">\n") || light.contains("> <"), "no white space between tags")
        XCTAssertFalse(light.contains("print-color-adjust"))
        XCTAssertEqual(PaneNavigation.decide(.linkActivated, mainFrame: true,
                                             url: URL(string: "bmfile:2?letter=7/3")),
                       .openFile(letter: "7/3", section: "2"))

        let dark = BodyFiles.tile(file, of: m, on: .dark)
        for rule in ["border: 1px solid rgba(255, 255, 255, 0.3) !important;",
                     "font: 12px -apple-system, sans-serif; color: #8e8e93;\">Rates &amp;",
                     "color: #0A84FF;"] {
            XCTAssertTrue(dark.contains(rule), rule)
        }
        XCTAssertFalse(dark.contains("-apple-system-"), dark)
        // A letter opened without its files: "Tap to Download", but not
        // on paper.
        m.filesLeftOnServer = true
        XCTAssertTrue(BodyFiles.tile(file, of: m, on: .light).contains("color: #007AFF;\">Tap to Download</span>"))
        XCTAssertTrue(BodyFiles.tile(file, of: m, on: .dark).contains("color: #0A84FF;\">Tap to Download</span>"))
        let paper = BodyFiles.tile(file, of: m, on: .paper)
        XCTAssertFalse(paper.contains("Tap to Download"))
        XCTAssertTrue(paper.contains("-webkit-print-color-adjust: exact; break-inside: avoid;"))
        XCTAssertTrue(paper.contains("border: 1px solid rgba(0, 0, 0, 0.3) !important;"))

        // The kind on the icon: from the end of the name, four letters or
        // digits at most; none where there is no such end.
        for (name, kind) in [("notes.docx", ">DOCX<"), ("archive.tar.gz", ">GZ<"), ("README", nil),
                             ("odd.<b>", nil), ("long.markdown", nil)] {
            let tile = BodyFiles.tile(Attachment(id: "3", filename: name, mimeType: "application/octet-stream",
                                                 size: nil), of: m, on: .light)
            XCTAssertEqual(tile.contains("<text "), kind != nil, name)
            if let kind { XCTAssertTrue(tile.contains(kind), name) }
        }
        // A size not known: the line is there, empty.
        XCTAssertTrue(BodyFiles.tile(Attachment(id: "3", filename: "a.pdf", mimeType: "application/pdf", size: nil),
                                     of: m, on: .light)
                        .contains("font: 12px -apple-system, sans-serif; color: rgba(4, 4, 15, 0.45);\"></span>"))
    }

    /// A picture file is drawn at its size, no wider than the letter, from
    /// the loader, by an address that names its letter, so two letters of
    /// a stack, both with a part "2", draw each its own; a picture of a
    /// kind WebKit draws on iPadOS 16 alone, and every other a tile.
    func testAPictureFileIsDrawnAtItsSizeFromTheLoader() throws {
        let photo = Attachment(id: "2", filename: "garden \"June\".jpg", mimeType: "image/jpeg", size: 2_400_000)
        func letter(_ id: String) -> Message {
            Message(id: id, mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                    senderAddress: "jane@example.com", to: [], cc: [], subject: "Garden",
                    date: Date(timeIntervalSince1970: 1_792_679_717), textBody: nil,
                    htmlBody: "<p>Our garden.</p>", attachments: [photo])
        }
        let first = letter("7/3"), second = letter("7/9")
        XCTAssertEqual(BodyFiles.picture(photo, of: first),
                       "<img src=\"bmcid://bmfile-m7_3-2\" alt=\"garden &quot;June&quot;.jpg\">")
        XCTAssertEqual(BodyFiles.pictureID("2", of: "7/9"), "bmfile-m7_9-2")
        let pictures = PanePage.pictures(of: [first, second])
        XCTAssertEqual(pictures["bmfile-m7_3-2"],
                       PanePage.Picture(messageID: "7/3", mailboxID: "INBOX", section: "2", mimeType: "image/jpeg"))
        XCTAssertEqual(pictures["bmfile-m7_9-2"]?.messageID, "7/9")
        XCTAssertTrue(PanePage.stackBody(first).html.contains("bmcid://bmfile-m7_3-2"))
        XCTAssertTrue(PanePage.stackBody(second).html.contains("bmcid://bmfile-m7_9-2"))
        let page = try XCTUnwrap(PanePage.letter(first, style: style))
        XCTAssertTrue(page.contains("img, table { max-width: 100% !important; height: auto; }"))
        XCTAssertTrue(page.contains("#bm img,"), "the photo kept from the invert, as the letter's own")

        for kind in ["image/jpeg", "IMAGE/JPEG", "image/png", "image/gif", "image/webp", "image/bmp", "image/pjpeg"] {
            XCTAssertTrue(BodyFiles.isPicture(Attachment(id: "2", filename: "a", mimeType: kind, size: 1)), kind)
        }
        for kind in ["image/heic", "image/tiff", "image/svg+xml", "application/pdf", "video/mp4"] {
            XCTAssertFalse(BodyFiles.isPicture(Attachment(id: "2", filename: "a", mimeType: kind, size: 1)), kind)
        }
    }

    // MARK: - A cut

    /// A letter shown or printed only in part: a file with no mark in what
    /// came is drawn above the words, under the pane's line, and not after
    /// the sender's markup, which ends wherever the cut fell, here inside a
    /// comment that would take everything after it. A file whose mark came
    /// is drawn at it. A letter whole has them after the words.
    func testAFileACutWouldSwallowIsDrawnAboveTheWords() throws {
        let marked = Attachment(id: "2", filename: "a.pdf", mimeType: "application/pdf", size: 10, isInline: true)
        let after = Attachment(id: "4", filename: "b.pdf", mimeType: "application/pdf", size: 10)
        var m = Message(id: "7/3", mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                        senderAddress: "jane@example.com", to: [], cc: [], subject: "Long",
                        date: Date(timeIntervalSince1970: 1_792_679_717), textBody: nil,
                        htmlBody: "<p>One.</p>" + BodyFiles.mark("2") + "<p>Two, cut <!-- sho",
                        attachments: [marked, after])
        m.isShortened = true
        let page = try XCTUnwrap(PanePage.letter(m, style: style))
        order([PanePage.shortenedLine, drawn("4", of: m), "<p>One.</p>", drawn("2", of: m), "<p>Two, cut"],
              in: page, "shortened")
        order([PanePage.shortenedLine, drawn("4", of: m), "<p>One.</p>"], in: PanePage.stackBody(m).html, "stack")
        m.isShortened = false
        order(["<p>One.</p>", drawn("2", of: m), "<p>Two, cut", drawn("4", of: m)],
              in: try XCTUnwrap(PanePage.letter(m, style: style)), "whole")
        // Printed, cut by the print's own limit.
        let long = Message(id: "7/3", mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                           senderAddress: "jane@example.com", to: [], cc: [], subject: "Long",
                           date: Date(timeIntervalSince1970: 1_792_679_717), textBody: nil,
                           htmlBody: "<p>" + String(repeating: "a", count: PrintPage.htmlLimit + 1),
                           attachments: [after])
        let printed = PrintPage.body(long).html
        order([PrintPage.shortened, drawn("4", of: long), "<p>aaa"], in: printed, "printed")
    }

    // MARK: - On paper

    /// A printed letter's files are in its body as the pane draws them,
    /// on paper: tiles with no "Tap to Download", and a picture file's
    /// picture decoded as it is drawn; none in its header.
    func testAPrintedLettersFilesAreInItsBody() throws {
        let raw = Self.letter(Self.mixed([Self.html("Our garden."), Self.jpeg("photo.jpg"), Self.pdf("plan.pdf")]))
        var m = Self.message(raw)
        m.filesLeftOnServer = true
        let page = PrintPage.letter(m, style: .init(senderPointSize: 17, metaPointSize: 15, subjectPointSize: 17,
                                                    bodyPointSize: 17, lineHeight: 1.41),
                                    size: { "\($0) bytes" })
        let head = try XCTUnwrap(page.components(separatedBy: "<div id=\"bm\">").first)
        XCTAssertFalse(head.contains("plan.pdf"))
        XCTAssertFalse(head.contains("photo.jpg"))
        order(["Our garden.", "<img decoding=sync src=\"bmcid://bmfile-m7_3-2\"",
               BodyFiles.tile(m.listedAttachments[1], of: m, on: .paper)], in: page, "printed")
        XCTAssertFalse(page.contains("Tap to Download"))
        XCTAssertNotNil(PanePage.pictures(of: [m])["bmfile-m7_3-2"], "the print's loader has it")
    }

    // MARK: - Its tile shows it coming

    /// A tile shows its file coming, as the header's row did with its
    /// spinner: dimmed, important, and "Loading…" in its last line, once
    /// however often it is said, until the pane says it has opened or been
    /// let go, and then as it was, "Tap to Download" again for a file left
    /// on the server. On a letter's own page and in a body of a stack; a
    /// file of another letter changes nothing. The script run in node on
    /// the model of the page (`ModelPage`).
    func testItsTileShowsItComing() throws {
        var letter = Self.message(BodyInOrderTests.among)
        let coming = BodyFiles.Busy("2.2", of: letter.id, busy: true)
        let done = BodyFiles.Busy("2.2", of: letter.id, busy: false)
        let link = BodyFiles.link("2.2", of: letter.id)
        XCTAssertEqual(coming.link, link)
        XCTAssertEqual(coming.arguments["words"] as? String, "Loading…")
        XCTAssertEqual(coming.arguments["busy"] as? Bool, true)
        XCTAssertEqual(done.arguments["busy"] as? Bool, false)
        let dimmed = ModelPage.Run.File(href: link, style: ["opacity": "0.5 !important"], status: "Loading…")
        let other = BodyFiles.Busy("2.2", of: "7/9", busy: true)

        for (said, left) in [("", false), ("Tap to Download", true)] {
            letter.filesLeftOnServer = left
            let asItWas = ModelPage.Run.File(href: link, style: [:], status: said)
            let page = try XCTUnwrap(PanePage.letter(letter, style: style))
            var run = try model(page, [.busy(100, coming), .busy(120, other), .busy(150, coming)])
            XCTAssertEqual(run.errors, [])
            XCTAssertEqual(run.files, [dimmed], "coming, said twice")
            run = try model(page, [.busy(100, coming), .busy(150, coming), .busy(300, done)])
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
    }

    /// The pane, read: a tap shows the file coming on its tile, whichever
    /// letter it is of, and the `defer` that ends the download puts it
    /// back on the page it was shown on, and not on a page given since; by
    /// script, in the app's content world. No header row is told anything.
    func testThePaneShowsTheTileComingFromTheTapToTheEnd() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(code.contains(
            "guard let m = letter ?? message else { return } "
                + "run(BodyFiles.Busy(attachment.id, of: m.id, busy: true)) let shown = loads.shown"))
        XCTAssertTrue(code.contains(
            "fileTaps.ended(file) "
                + "if loads.stillShows(shown) { run(BodyFiles.Busy(attachment.id, of: m.id, busy: false)) } }"))
        XCTAssertTrue(code.contains(
            "private func run(_ busy: BodyFiles.Busy) { webView.callAsyncJavaScript(BodyFiles.Busy.script, "
                + "arguments: busy.arguments, in: nil, in: .defaultClient) }"))
        XCTAssertEqual(code.components(separatedBy: "BodyFiles.Busy(").count - 1, 2)
        XCTAssertFalse(code.contains("header.setAttachment"))
        XCTAssertFalse(code.contains("onSelectAttachment"))
    }

    // MARK: - Held

    /// A finger held on a tile is read as the script posts it: the file
    /// its link names and where the finger is, numbers as WebKit hands
    /// them over or as Swift holds them. A link that is no tile's, no
    /// place, a place not a number or not finite, or no `hold`, is
    /// nothing; nor is a picture's tap or hold, which `PanePictures.Tap`
    /// reads. Its menu is the held photo's, less Save Image for a file
    /// that is no picture.
    func testAHoldOnATileIsReadAsTheScriptPostsIt() throws {
        let link = BodyFiles.link("2.2", of: "7/3")
        let post: [String: Any] = ["file": link, "section": "", "hold": NSNumber(value: true),
                                   "x": NSNumber(value: 120.5), "y": NSNumber(value: 300)]
        let hold = try XCTUnwrap(BodyFiles.Hold(post))
        XCTAssertEqual(hold.letter, "7/3")
        XCTAssertEqual(hold.section, "2.2")
        XCTAssertEqual(hold.x, 120.5)
        XCTAssertEqual(hold.y, 300)
        var swift = post
        swift["hold"] = true
        swift["x"] = 12
        XCTAssertEqual(BodyFiles.Hold(swift)?.x, 12)
        for (key, value) in [("file", "https://example.com/a.pdf"), ("file", "bmfile:2"), ("file", nil),
                             ("x", nil), ("y", "300"), ("x", Double.nan), ("y", Double.infinity),
                             ("hold", nil), ("hold", false), ("hold", "yes")] as [(String, Any?)] {
            var changed = post
            changed[key] = value
            XCTAssertNil(BodyFiles.Hold(changed as [String: Any]), "\(key) \(String(describing: value))")
        }
        XCTAssertNil(PanePictures.Tap(post), "no picture's")
        let picture: [String: Any] = ["src": "bmcid://bmfile-m7_3-2", "section": "", "width": 1, "height": 1,
                                      "drawnWidth": 1, "drawnHeight": 1, "hold": true, "x": 1, "y": 1]
        XCTAssertNil(BodyFiles.Hold(picture), "no tile's")

        XCTAssertEqual(PanePictures.fileMenu.map(\.title), ["Quick Look", "Save to Files", "Share", "Copy"])
        XCTAssertEqual(PanePictures.fileMenu.filter(\.presents), [.quickLook, .saveToFiles, .share])
        func menu(_ kind: String) -> [PanePictures.Item] {
            PanePictures.menu(for: Attachment(id: "2", filename: "a", mimeType: kind, size: 1))
        }
        XCTAssertEqual(menu("application/pdf"), PanePictures.fileMenu)
        XCTAssertEqual(menu("text/calendar"), PanePictures.fileMenu)
        XCTAssertEqual(menu("image/heic"), PanePictures.menu, "a picture drawn as a tile: Save Image too")
        XCTAssertEqual(menu("IMAGE/TIFF"), PanePictures.menu)
    }

    /// A tap on a picture file opens it whatever its size, as a tile does:
    /// it is a file, and no logo; a hold gives the held photo's menu, by
    /// its picture's address, on a letter's own page and in a stack. A
    /// picture the letter shows by `cid:` is as B-122 has it: not opened
    /// when small. A picture file of another letter opens nothing.
    func testAPictureFileOpensAtAnySize() throws {
        let photo = Attachment(id: "2", filename: "icon.png", mimeType: "image/png", size: 900)
        let logo = Attachment(id: "3", filename: "logo.png", mimeType: "image/png", size: 900,
                              contentID: "logo", isInline: true)
        let m = Message(id: "7/3", mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                        senderAddress: "jane@example.com", to: [], cc: [], subject: "Icon",
                        date: Date(timeIntervalSince1970: 1_792_679_717), textBody: nil,
                        htmlBody: "<img src=\"cid:logo\">", attachments: [photo, logo])
        func tap(_ src: String, hold: Bool = false, section: String = "") -> PanePictures.Tap {
            PanePictures.Tap(contentID: InlineImageRewriter.contentID(of: URL(string: src)!)!, section: section,
                             width: 32, height: 32, drawnWidth: 32, drawnHeight: 32, isHold: hold)
        }
        let file = "bmcid://bmfile-m7_3-2"
        XCTAssertEqual(PanePictures.opening(tap(file), inStack: false, alone: m, stack: [:], his: { _ in nil })?.part,
                       photo)
        XCTAssertEqual(PanePictures.opening(tap(file, hold: true), inStack: false, alone: m, stack: [:],
                                            his: { _ in nil })?.part, photo)
        XCTAssertEqual(PanePictures.opening(tap(file, section: "m7_3"), inStack: true, alone: nil,
                                            stack: ["7/3": m], his: { _ in nil })?.part, photo)
        XCTAssertNil(PanePictures.opening(tap("bmcid://logo"), inStack: false, alone: m, stack: [:],
                                          his: { _ in nil }), "the letter's own logo, small, as before")
        XCTAssertEqual(PanePictures.opening(tap("bmcid://logo", hold: true), inStack: false, alone: m, stack: [:],
                                            his: { _ in nil })?.part, logo)
        XCTAssertNil(PanePictures.opening(tap("bmcid://bmfile-m7_9-2"), inStack: false, alone: m, stack: [:],
                                          his: { _ in nil }), "another letter's")
        XCTAssertNil(PanePictures.part("bmfile-m7_3-3", of: m), "not a picture file")
    }

    /// The script, on the model of the page: a finger held half a second
    /// on a tile, anywhere on it, tells the pane once, with the tile's link
    /// and where the finger is; its lift is stopped, and the click after
    /// it is stopped, so the file does not open as well; a tap after that
    /// is the link's, not stopped. A lift before the half second is a tap,
    /// and a finger that moves no hold. In a stack, the hold names its
    /// letter's section and opens or closes no letter.
    func testAFingerHeldOnATileTellsThePaneAndOpensNothing() throws {
        let letter = Self.message(BodyInOrderTests.among)
        let link = BodyFiles.link("2.2", of: letter.id)
        let named = "<span id=\"name\" style=\"display: block;"
        let page = try XCTUnwrap(PanePage.letter(letter, style: style))
            .replacingOccurrences(of: "<span style=\"display: block; overflow: hidden;", with: named + " overflow: hidden;")
        XCTAssertTrue(page.contains(named))
        let run = try model(page, [
            .down(100, on: "name", y: 240), .up(700), .click(701, "name"),
            .down(900, on: "name", y: 240), .up(1_000), .click(1_001, "name"),
            .down(1_200, on: "name", y: 240), .up(1_500), .click(1_501, "name"),
            .down(1_700, on: "name", y: 240), .move(1_800, y: 270), .up(2_400), .click(2_401, "name"),
        ], end: 3_000)
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.tileHolds, [.init(file: link, section: "", hold: true, x: 300, y: 240)])
        XCTAssertEqual(run.clicks.map(\.stopped), [true, false, false, false])
        XCTAssertEqual(run.stopped, 1, "the lift of the hold, and no other")
        XCTAssertEqual(run.pictures, [])
        let held = try XCTUnwrap(BodyFiles.Hold(try XCTUnwrap(run.tileHolds.first).body))
        XCTAssertEqual([held.letter, held.section], [letter.id, "2.2"])

        let entry = ConversationDocument.Entry(id: letter.id, sender: letter.sender, date: letter.date,
                                               body: nil, isExpanded: true, preview: "The programme")
        let stack = ConversationDocument.html(entries: [entry], inset: 20, bodyPointSize: 17, lineHeight: 1.4)
        let body = PanePage.stackBody(letter)
        let fill = ConversationDocument.Fill(
            sectionID: ConversationDocument.sectionID(for: letter.id),
            body: .init(html: "<p data-h=\"300\">Words</p>" + body.html.replacingOccurrences(
                of: "<span style=\"display: block; overflow: hidden;", with: named + " overflow: hidden;"),
                        isHTML: body.isHTML))
        let inStack = try model(stack, [.fill(50, fill), .down(200, on: "name", y: 300), .up(800),
                                        .click(801, "name")], end: 1_000)
        XCTAssertEqual(inStack.errors, [])
        XCTAssertEqual(inStack.tileHolds.map(\.section), [ConversationDocument.sectionID(for: letter.id)])
        XCTAssertEqual(inStack.clicks.map(\.stopped), [true])
        XCTAssertEqual(inStack.posts, [], "no letter opened or closed")
    }

    /// The pane, read: a hold on a tile goes to `holdFile`, which puts up
    /// `PanePictures.menu(for:)` for the file a tap on the tile opens, by the
    /// sheet a held photo has; Copy puts a file that is no picture on the
    /// pasteboard as its kind; the script wires each tile's click.
    func testThePanePutsUpTheMenuForAHeldTile() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(code.contains("} else if let hold = BodyFiles.Hold(scriptMessage.body) { holdFile(hold) }"))
        XCTAssertTrue(code.contains(
            "private func holdFile(_ held: BodyFiles.Hold) { guard presentedViewController == nil, "
                + "let (m, file) = self.file(held.section, of: held.letter) else { return } "
                + "hold(PanePictures.menu(for: file), file, of: m, x: held.x, y: held.y) }"))
        XCTAssertEqual(code.components(separatedBy: "hold(PanePictures.").count - 1, 2)
        XCTAssertTrue(code.contains(
            "} else if let kind = [UTType(mimeType: picture.mimeType), named].compactMap({ $0 }) "
                + ".first(where: { !$0.isDynamic && $0 != .data }) { "
                + "UIPasteboard.general.setData(data, forPasteboardType: kind.identifier) }"))
        let script = ConversationDocument.script
        XCTAssertTrue(script.contains(
            "if (bmFileTile(links[j]) === links[j]) links[j].addEventListener('click', bmFileClicked);"))
    }

    // MARK: - Helpers

    private func model(_ page: String, _ steps: [ModelPage.Step], end: Int = 400) throws -> ModelPage.Run {
        do {
            return try ModelPage.run(ConversationDocument.script, page: page, steps: steps, end: end)
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
