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

    private static func tiff(_ name: String) -> String {
        "Content-Transfer-Encoding: base64\nContent-Type: image/tiff; name=\"\(name)\"\n"
            + "Content-Disposition: inline; filename=\"\(name)\"\n\nSUkqAA==\n"
    }

    private static let print = PrintPage.Style(senderPointSize: 17, metaPointSize: 15, subjectPointSize: 17,
                                               bodyPointSize: 17, lineHeight: 1.41)

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
        let file = m.attachments.first { $0.id == section }!
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

    /// A picture sent to be shown by `cid:` that the body shown does not
    /// show is drawn as a file, as Mail draws a picture its page does not
    /// name: after a plain letter's words, after the words of HTML that
    /// never names it, and alone for a letter of nothing else, which is not
    /// said to have no text; once, at its size, from the loader, opened as
    /// a file is; on paper after a plain letter's words or alone, and not
    /// HTML's (B-185, fixed again). Not for a letter
    /// shown only in part, whose HTML names it in what did not come, as
    /// often as not, while its files are drawn above the words; and the
    /// HTML that names one draws it itself, the pane not again.
    func testAPictureSentToBeShownThatTheBodyDoesNotShowIsDrawnAsAFile() throws {
        let inline = Self.jpeg("photo.jpg", contentID: "photo@example.com", disposition: "inline")
        let shapes: [(name: String, raw: Data, order: [String])] = [
            ("a plain letter", Self.letter(Self.mixed([Self.plain("Our garden."), inline])), ["Our garden.", "2"]),
            ("HTML that never names it", Self.letter(Self.mixed([Self.html("Our garden."), inline])),
             ["Our garden.", "2"]),
            ("nothing else", Self.letter(Self.mixed([inline])), ["1"]),
        ]
        for shape in shapes {
            let m = Self.message(shape.raw)
            let section = try XCTUnwrap(shape.order.last)
            XCTAssertEqual(m.listedAttachments.map(\.id), [], shape.name)
            XCTAssertEqual(m.attachments.map(\.id), [section], shape.name)
            XCTAssertTrue(try XCTUnwrap(m.attachments.first).isShownInBody, shape.name)
            XCTAssertFalse(PanePage.isEmpty(m), shape.name)
            let page = try XCTUnwrap(PanePage.letter(m, style: style), shape.name)
            for (kind, body) in [("page", page), ("stack", PanePage.stackBody(m).html)] {
                let label = "\(shape.name), \(kind)"
                XCTAssertEqual(count(drawn(section, of: m), in: body), 1, label)
                order(shape.order.map { $0 == section ? drawn(section, of: m) : $0 }, in: body, label)
                XCTAssertFalse(body.contains(MailText.emptyBodyNotice), label)
                XCTAssertFalse(body.contains("<!--bm-file:"), label)
            }
            // On paper a plain letter's, after its words or alone, as Mail
            // 16.5.1 prints one (B-185, fixed again); not HTML's, whose
            // own markup does not draw it (B-185).
            XCTAssertEqual(count(drawn(section, of: m), in: PrintPage.body(m).html),
                           shape.name == "HTML that never names it" ? 0 : 1, shape.name)
            let address = BodyFiles.pictureID(section, of: m.id)
            XCTAssertEqual(PanePage.pictures(of: [m])[address],
                           PanePage.Picture(messageID: "7/3", mailboxID: "INBOX", section: section,
                                            mimeType: "image/jpeg"), shape.name)
            XCTAssertEqual(PanePictures.file(address, of: m)?.id, section, shape.name)
            XCTAssertEqual(PanePictures.part(address, of: m)?.id, section, shape.name)
        }

        // Shown only in part: not drawn; a file of the letter still is,
        // above the words.
        var cut = Self.message(Self.letter(Self.mixed([Self.html("Our garden."), inline, Self.pdf("plan.pdf")])))
        cut.isShortened = true
        let page = try XCTUnwrap(PanePage.letter(cut, style: style))
        XCTAssertFalse(page.contains("bmcid://bmfile-"))
        XCTAssertEqual(count(drawn("3", of: cut), in: page), 1)
        order([MailText.shortenedNotice, drawn("3", of: cut), "Our garden."], in: page, "cut")
        XCTAssertFalse(PanePage.stackBody(cut).html.contains("bmcid://bmfile-"))

        // Named by the HTML: drawn there, once, by the letter.
        let named = Self.message(Self.letter(Self.mixed([
            Self.html("Our garden. <img src=\"cid:photo@example.com\">"), inline])))
        let shown = try XCTUnwrap(PanePage.letter(named, style: style))
        XCTAssertEqual(count(address("photo@example.com"), in: shown), 1)
        XCTAssertFalse(shown.contains("bmcid://bmfile-"))
        XCTAssertFalse(PanePage.stackBody(named).html.contains("bmcid://bmfile-"))
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
    /// A tile in Mail's colours for how its letter is drawn in Dark Mode
    /// (B-169): light on a letter drawn light or inverted, dark on one in
    /// its own colours or plain; and a letter's scheme read from its markup
    /// as it came, so a tile, whose icon is the page's own drawing, never
    /// makes a letter light. At the pane's text size by the head's rule,
    /// box and words together (B-166), on the page, in the stack and on
    /// paper; nothing at Large. Integration, int19.
    func testATileFollowsTheLettersSchemeAndTheTextSize() throws {
        let file = Attachment(id: "2", filename: "Rates.pdf", mimeType: "application/pdf", size: 90_000)
        func letter(_ html: String?, text: String? = nil) -> Message {
            Message(id: "7/3", mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                    senderAddress: "jane@example.com", to: [], cc: [], subject: "Rates",
                    date: Date(timeIntervalSince1970: 1_792_679_717), textBody: text, htmlBody: html,
                    attachments: [file])
        }
        let lightBorder = "border: 1px solid rgba(0, 0, 0, 0.3) !important;"
        let darkBorder = "border: 1px solid rgba(255, 255, 255, 0.3) !important;"
        let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)
        let cases: [(Message, LetterScheme?, String)] = [
            (letter("<p>Rates attached.</p>"), .inverted, lightBorder),
            (letter("<p>Rates.</p><img src=\"https://example.com/a.jpg\" width=\"300\">"), .light, lightBorder),
            (letter("<html><head><meta name=\"color-scheme\" content=\"light dark\"></head>"
                    + "<body><p>Rates.</p></body></html>"), .own, darkBorder),
            (letter(nil, text: "Rates attached."), nil, darkBorder),
        ]
        for (m, scheme, border) in cases {
            XCTAssertEqual(m.htmlBody.map { LetterScheme.of(html: $0) }, scheme)
            let page = try XCTUnwrap(PanePage.letter(m, style: style))
            let body = PanePage.stackBody(m)
            for drawn in [page, body.html] {
                XCTAssertTrue(drawn.contains("<a class=\"bm-tile\" href=\"bmfile:2?letter=7/3\""), drawn)
                XCTAssertTrue(drawn.contains(border), "\(String(describing: scheme)): \(drawn)")
            }
            XCTAssertFalse(page.contains("zoom:"), "nothing at Large")
        }
        // The tile's own drawing does not make an inverted letter light.
        let plainHTML = letter("<p>Rates attached.</p>")
        let inverted = try XCTUnwrap(PanePage.letter(plainHTML, style: style))
        XCTAssertTrue(inverted.contains("#bm { filter: "), inverted)

        let large = PanePage.Style(inset: 26, bodyPointSize: 33, lineHeight: 1.41)
        let rule = "a.bm-tile { zoom: 1.941 !important; }"
        XCTAssertEqual(BodyFiles.sizeRule(bodyPointSize: 33), rule)
        XCTAssertEqual(BodyFiles.sizeRule(bodyPointSize: 17), "")
        XCTAssertEqual(BodyFiles.sizeRule(bodyPointSize: 14), "", "never below the default, as WebKit's")
        // No wider than the letter at the larger accessibility sizes: twice
        // Large at most, 356 points with its margin, within the 382 of two
        // panes in portrait and the 540 of paper (int19).
        XCTAssertEqual(BodyFiles.sizeRule(bodyPointSize: 34), "a.bm-tile { zoom: 2.0 !important; }")
        XCTAssertEqual(BodyFiles.sizeRule(bodyPointSize: 40), "a.bm-tile { zoom: 2.0 !important; }")
        XCTAssertEqual(BodyFiles.sizeRule(bodyPointSize: 53), "a.bm-tile { zoom: 2.0 !important; }")
        let tileWidth = 178.0 // 160, its padding 2 × 3, its border 2 × 1, its margin 2 × 5
        XCTAssertLessThanOrEqual(tileWidth * BodyFiles.maxTileZoom, 382)
        XCTAssertTrue(try XCTUnwrap(PanePage.letter(plainHTML, style: large)).contains(rule))
        let none = Message(id: "7/4", mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                           senderAddress: "jane@example.com", to: [], cc: [], subject: "Rates",
                           date: Date(timeIntervalSince1970: 1_792_679_717), textBody: nil,
                           htmlBody: "<p>No files.</p>", attachments: [])
        XCTAssertFalse(try XCTUnwrap(PanePage.letter(none, style: large)).contains("zoom:"))
        XCTAssertTrue(ConversationDocument.html(entries: [], inset: 26, bodyPointSize: 33, lineHeight: 1.41)
                          .contains(rule))
        let print = PrintPage.Style(senderPointSize: 33, metaPointSize: 29, subjectPointSize: 33,
                                    bodyPointSize: 33, lineHeight: 1.41)
        // On paper no tile, and so no rule for one (B-185).
        XCTAssertFalse(PrintPage.made(plainHTML, style: print, size: { "\($0) bytes" }).page.contains("zoom:"))
    }

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
        XCTAssertTrue(light.hasPrefix("<a class=\"bm-tile\" href=\"bmfile:2?letter=7/3\" style=\""), light)
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
        // A letter opened without its files: "Downloading" with Mail's ring
        // for a file that comes as it opens (B-176), "Tap to Download" for
        // one too large to, but neither on paper.
        m.filesLeftOnServer = true
        let coming = BodyFiles.tile(file, of: m, on: .light)
        XCTAssertTrue(coming.contains("color: #007AFF;\">Downloading</span>"), coming)
        XCTAssertTrue(coming.contains(BodyFiles.ring))
        XCTAssertFalse(coming.contains(">PDF</text>"), "the ring in the icon's place")
        XCTAssertTrue(coming.contains(" line-height: normal; color: #007AFF; -webkit-tap-highlight-color"),
                      "the tile's blue, for the ring's arc")
        let large = Attachment(id: "2", filename: file.filename, mimeType: "application/pdf",
                               size: FilesAhead.most + 1)
        XCTAssertTrue(BodyFiles.tile(large, of: m, on: .light).contains("color: #007AFF;\">Tap to Download</span>"))
        XCTAssertTrue(BodyFiles.tile(large, of: m, on: .dark).contains("color: #0A84FF;\">Tap to Download</span>"))
        XCTAssertTrue(BodyFiles.tile(large, of: m, on: .dark).contains(">PDF</text>"))
        let paper = BodyFiles.tile(large, of: m, on: .paper)
        XCTAssertFalse(paper.contains("Tap to Download"))
        XCTAssertFalse(BodyFiles.tile(file, of: m, on: .paper).contains("Downloading"))
        XCTAssertFalse(BodyFiles.tile(file, of: m, on: .paper).contains("bm-file-ring"))
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

        for kind in ["image/jpeg", "IMAGE/JPEG", "image/png", "image/gif", "image/webp", "image/bmp", "image/pjpeg",
                     "image/heic", "IMAGE/HEIC", "image/heif", "image/heic-sequence", "image/heif-sequence"] {
            XCTAssertTrue(BodyFiles.isPicture(Attachment(id: "2", filename: "a", mimeType: kind, size: 1)), kind)
        }
        for kind in ["image/tiff", "image/svg+xml", "image/avif", "application/pdf", "video/mp4"] {
            XCTAssertFalse(BodyFiles.isPicture(Attachment(id: "2", filename: "a", mimeType: kind, size: 1)), kind)
        }
    }

    /// In a stack the loader answers for every body gone in, not the last
    /// alone: two letters' bodies, each with a photo file that is part 2,
    /// put in before the page has loaded and asked for together, are each
    /// answered with its own, and a `Content-ID` the two share is the later
    /// letter's, as when the stack is drawn again. The pane, read: a body
    /// put into a stack, his letter's from Sent Mail and the stack drawn
    /// again add to the map, which a conversation shown starts empty, and a
    /// letter on its own has a map of its own.
    func testEveryBodyOfAStackKeepsItsPicturesInTheLoader() throws {
        func letter(_ id: String) -> Message {
            Message(id: id, mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                    senderAddress: "jane@example.com", to: [], cc: [], subject: "Garden",
                    date: Date(timeIntervalSince1970: 1_792_679_717), textBody: nil,
                    htmlBody: "<p>Our garden.</p><img src=\"cid:logo\">",
                    attachments: [Attachment(id: "2", filename: "garden.jpg", mimeType: "image/jpeg", size: 2_400_000),
                                  Attachment(id: "3", filename: "logo.png", mimeType: "image/png", size: 900,
                                             contentID: "logo", isInline: true)])
        }
        let first = letter("7/3"), second = letter("7/9")
        var map: [String: PanePage.Picture] = [:]
        map = PanePage.pictures(of: [first], adding: map)
        map = PanePage.pictures(of: [second], adding: map)
        XCTAssertEqual(map["bmfile-m7_3-2"],
                       PanePage.Picture(messageID: "7/3", mailboxID: "INBOX", section: "2", mimeType: "image/jpeg"))
        XCTAssertEqual(map["bmfile-m7_9-2"],
                       PanePage.Picture(messageID: "7/9", mailboxID: "INBOX", section: "2", mimeType: "image/jpeg"))
        XCTAssertEqual(map["logo"]?.messageID, "7/9")
        XCTAssertEqual(map, PanePage.pictures(of: [first, second]))
        XCTAssertEqual(PanePage.pictures(of: [first], adding: map)["logo"]?.messageID, "7/3")
        XCTAssertNotNil(PanePage.pictures(of: [first], adding: map)["bmfile-m7_9-2"])

        let code = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(code.contains(
            "private func drawBody(_ m: Message, _ body: ConversationDocument.Entry.Rendered, focus: Bool) { "
                + "prepareInlineImages(for: [m], inStack: true)"))
        XCTAssertTrue(code.contains(
            "case .success(let (m, body)): prepareInlineImages(for: [m], inStack: true) related.keep(m, for: load)"))
        XCTAssertTrue(code.contains("+ drawn.filter { $0.id == stackFocus.letter }, inStack: true)"))
        XCTAssertTrue(code.contains(
            "let parts = inStack ? PanePage.pictures(of: letters, adding: pictureMap) "
                + ": PanePage.pictures(of: letters) pictureMap = parts"))
        XCTAssertTrue(code.contains("loaded = [:] pictureMap = [:] markedUnreadHere = nil "
                                    + "stackFocus = StackFocus(opening: thread.newest.id)"))
        XCTAssertEqual(count("pictureMap = ", in: code), 2)
        // And B-168's "Load All Images" putting a body back (int19).
        XCTAssertTrue(code.contains("self.prepareInlineImages(for: [m], inStack: true) self.fill(id, body)"))
        // And the stack drawn again at a new text size (B-166; int19).
        XCTAssertTrue(code.contains("let drawn = entries.compactMap { loaded[$0.id] } "
                                    + "prepareInlineImages(for: drawn.filter { $0.id != stackFocus.letter } "
                                    + "+ drawn.filter { $0.id == stackFocus.letter }, inStack: true) "
                                    + "renderConversation(entries) for (id, body) in again.bodies { fill(id, body) }"))
        XCTAssertEqual(count("inStack: true)", in: code), 5)
        XCTAssertTrue(code.contains(
            "private func draw(_ m: Message, page: String?) { prepareInlineImages(for: [m]) guard"))
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
        // Printed, cut by the print's own limit: the line and the words,
        // and no file (B-185).
        let long = Message(id: "7/3", mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                           senderAddress: "jane@example.com", to: [], cc: [], subject: "Long",
                           date: Date(timeIntervalSince1970: 1_792_679_717), textBody: nil,
                           htmlBody: "<p>" + String(repeating: "a", count: PrintPage.htmlLimit + 1),
                           attachments: [after])
        let printed = PrintPage.body(long).html
        order([PrintPage.shortened, "<p>aaa"], in: printed, "printed")
        XCTAssertFalse(printed.contains("bmfile"), "printed")
    }

    // MARK: - On paper

    /// A printed letter has none of its files, as Mail prints none (B-185;
    /// round r6-n-compare, C-3b, 29 October 2026): Mail 16.5.1 prints the
    /// letter whose only content is an attached picture as its header
    /// alone, and the one whose HTML shows its picture by `cid:` with the
    /// picture. So an attached picture prints no `<img>`, a PDF no tile,
    /// a letter with words and files its words alone, a file's mark among
    /// the words stays the comment it came as, and a picture the HTML
    /// shows by `cid:` prints there, decoded as it is drawn. The pane
    /// draws every one, as before. From B-170 to B-185 the paper drew
    /// them as the pane does.
    func testAPrintedLetterHasNoneOfItsFilesAsMailsHasNone() throws {
        let print = PrintPage.Style(senderPointSize: 17, metaPointSize: 15, subjectPointSize: 17,
                                    bodyPointSize: 17, lineHeight: 1.41)
        func page(_ m: Message) -> String {
            PrintPage.letter(m, style: print, size: { "\($0) bytes" })
        }
        func body(_ page: String) throws -> String {
            let start = try XCTUnwrap(page.range(of: "<div id=\"bm\">"))
            let end = try XCTUnwrap(page.range(of: "</div></body></html>", options: .backwards))
            return String(page[start.upperBound..<end.lowerBound])
        }

        // Only an attached picture: the header alone, as Mail's.
        let picture = Self.message(Self.letter(Self.mixed([Self.jpeg("IMG_0131.jpg")])))
        XCTAssertEqual(picture.attachments.map(\.id), ["1"])
        XCTAssertFalse(PanePage.isEmpty(picture), "the pane draws it")
        XCTAssertTrue(try XCTUnwrap(PanePage.letter(picture, style: style)).contains(drawn("1", of: picture)))
        let alone = page(picture)
        XCTAssertEqual(try body(alone), "", "nothing under the header")
        XCTAssertFalse(alone.contains("<img"), "no picture")
        XCTAssertFalse(alone.contains(MailText.emptyBodyNotice), "no \"no text\" line, as Mail's")
        XCTAssertTrue(alone.contains("<td class=\"bm-label\">From:</td>"), "the header")

        // Words and files: the words, with no picture and no tile, in an
        // HTML letter and a plain one.
        for (kind, words) in [("HTML", Self.html("Our garden.")), ("plain", Self.plain("Our garden."))] {
            var m = Self.message(Self.letter(Self.mixed([words, Self.jpeg("photo.jpg"), Self.pdf("plan.pdf")])))
            m.filesLeftOnServer = true
            XCTAssertEqual(m.attachments.map(\.id), ["2", "3"], kind)
            let pane = try XCTUnwrap(PanePage.letter(m, style: style), kind)
            order(["Our garden.", drawn("2", of: m), drawn("3", of: m)], in: pane, "\(kind), the pane")
            let printed = try body(page(m))
            XCTAssertTrue(printed.contains("Our garden."), kind)
            for file in [drawn("2", of: m), drawn("3", of: m), "bmcid://", "<img", BodyFiles.tileClass,
                         "plan.pdf", "photo.jpg", "Tap to Download"] {
                XCTAssertFalse(printed.contains(file), "\(kind): \(file)")
            }
            XCTAssertFalse(page(m).contains("zoom:"), "\(kind): no tile's rule")
        }

        // A plain letter with a PDF alone: its words, no tile.
        let pdf = Self.message(Self.letter(Self.mixed([Self.plain("The plan."), Self.pdf("plan.pdf")])))
        XCTAssertEqual(try body(page(pdf)), "The plan.")

        // A file's mark among the words: the comment it came as, which
        // nothing draws; the pane makes it the file.
        let tile = Attachment(id: "2", filename: "plan.pdf", mimeType: "application/pdf", size: 9)
        let marked = Message(id: "7/3", mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                             senderAddress: "jane@example.com", to: [], cc: [], subject: "Plan",
                             date: Date(timeIntervalSince1970: 1_792_679_717), textBody: nil,
                             htmlBody: "<p>One.</p>" + BodyFiles.mark("2") + "<p>Two.</p>", attachments: [tile])
        XCTAssertEqual(try body(page(marked)), "<p>One.</p>" + BodyFiles.mark("2") + "<p>Two.</p>")
        order(["<p>One.</p>", drawn("2", of: marked), "<p>Two.</p>"],
              in: try XCTUnwrap(PanePage.letter(marked, style: style)), "marked, the pane")

        // A picture the HTML shows by `cid:`: printed there, decoded as it
        // is drawn, as Mail prints it; once.
        let named = Self.message(Self.letter(Self.mixed([
            Self.html("Our garden. <img src=\"cid:photo@example.com\">"),
            Self.jpeg("h-photo.jpg", contentID: "photo@example.com", disposition: "inline")])))
        let shown = try body(page(named))
        order(["Our garden.", "<img decoding=sync src=\"" + address("photo@example.com") + "\""],
              in: shown, "cid")
        XCTAssertEqual(count("<img ", in: shown), 1)
        XCTAssertFalse(shown.contains("bmcid://bmfile-"))
        XCTAssertNotNil(PanePage.pictures(of: [named])["photo@example.com"],
                        "the print's loader has it")
    }

    /// A plain letter's photo sent inline, which no markup names, prints
    /// after its words, about 81% of the sheet's width, as Mail 16.5.1
    /// prints one (B-185, fixed again; round r6-q-copy, 30 October 2026:
    /// "Page 1 of 2", "Page 2 of 2", the round's tall photo moved whole to
    /// the second sheet), with no break before it, so WebKit moves it to
    /// the next sheet only where it does not fit; with a `Content-ID` or
    /// none, from the address the print's loader serves; after a PDF's
    /// pages; two photos, in the letter's order; a letter of a photo
    /// alone; a letter shown in part, above its words, and none with a
    /// `Content-ID`. Not a picture attached, nor one WebKit cannot draw,
    /// nor an HTML letter's. The pane's page as before.
    func testAPlainLettersInlinePhotoPrintsAfterTheWords() throws {
        func photo(_ section: String, of m: Message) -> String {
            "<img decoding=sync class=\"" + PrintPage.photoClass + "\" src=\""
                + address(BodyFiles.pictureID(section, of: m.id)) + "\" alt=\"\" style=\""
                + PrintPage.photoStyle + "\">"
        }
        let together = "<div style=\"margin: 0; padding: 0; white-space: normal;\">"
        XCTAssertEqual(PrintPage.photoStyle, "display: block !important; width: auto !important;"
                       + " height: auto !important; max-width: 91.85% !important; max-height: 900px !important;"
                       + " margin: 0 !important; padding: 0 !important; border: 0 !important;")
        XCTAssertEqual(Double(PrintPage.photoWidth) / PrintPage.paperWidth, 0.81, accuracy: 0.005, "Mail's")
        XCTAssertEqual(Double(PrintPage.photoHeight), PrintPage.paperHeight - 2 * PrintPage.margin)
        XCTAssertFalse(PrintPage.photoStyle.contains("\(PrintPage.photoWidth)px"),
                       "points are no CSS pixels on paper (r6-r-copy: 496px printed 399 points)")

        // The round's letter: words, then a photo inline with no
        // `Content-ID`; and the same with one.
        let words = "The second paragraph; the photo comes after it."
        for contentID in [nil, "photo@example.com"] {
            let label = contentID ?? "no Content-ID"
            let m = Self.message(Self.letter(Self.mixed([
                Self.plain(words), Self.jpeg("IMG_0185.jpg", contentID: contentID, disposition: "inline")])))
            XCTAssertNil(m.htmlBody, label)
            XCTAssertEqual(m.attachments.map(\.id), ["2"], label)
            XCTAssertEqual(PrintPage.photos(of: m, cut: false).map(\.id), ["2"], label)
            XCTAssertEqual(PrintPage.body(m).html, words + together + photo("2", of: m) + "</div>", label)
            XCTAssertFalse(PrintPage.body(m).html.contains("break-"), label)
            let page = PrintPage.letter(m, style: Self.print, size: { "\($0) bytes" })
            XCTAssertEqual(count("<img ", in: page), 1, label)
            XCTAssertNotNil(PanePage.pictures(of: [m])[BodyFiles.pictureID("2", of: m.id)],
                            "\(label): the print's loader has it")
            let pane = try XCTUnwrap(PanePage.letter(m, style: style), label)
            order([words, drawn("2", of: m)], in: pane, "\(label), the pane")
            XCTAssertFalse(pane.contains(PrintPage.photoClass), label)
            XCTAssertFalse(pane.contains("break-before"), label)
        }

        // After a PDF's pages, which run on under the words; two photos,
        // in the letter's order.
        let two = Self.message(Self.letter(Self.mixed([
            Self.plain(words), Self.jpeg("a.jpg", disposition: "inline"), Self.pdf("plan.pdf"),
            Self.jpeg("b.jpg", disposition: "inline")])))
        XCTAssertEqual(two.attachments.map(\.id), ["2", "3", "4"])
        let strip = PrintPage.pdfPageImages(two, pages: ["3": [1]])
        XCTAssertFalse(strip.isEmpty)
        XCTAssertEqual(PrintPage.body(two, pdfPages: ["3": [1]]).html,
                       words + strip + together + photo("2", of: two) + photo("4", of: two) + "</div>")
        XCTAssertEqual(PrintPage.body(two).html,
                       words + together + photo("2", of: two) + photo("4", of: two) + "</div>")

        // A photo alone, a letter of nothing else: under the header.
        let alone = Self.message(Self.letter(Self.mixed([Self.jpeg("IMG_0185.jpg", disposition: "inline")])))
        XCTAssertEqual(PrintPage.body(alone).html, together + photo("1", of: alone) + "</div>")
        // And under a PDF's pages alone.
        let paged = Self.message(Self.letter(Self.mixed([
            Self.pdf("plan.pdf"), Self.jpeg("IMG_0185.jpg", disposition: "inline")])))
        let pagedStrip = PrintPage.pdfPageImages(paged, pages: ["1": [1]])
        XCTAssertEqual(PrintPage.body(paged, pdfPages: ["1": [1]]).html,
                       pagedStrip + together + photo("2", of: paged) + "</div>")

        // Shown only in part: above the words, under the line, as the
        // pane draws it; one with a `Content-ID` not at all.
        var cut = Self.message(Self.letter(Self.mixed([
            Self.plain(words), Self.jpeg("a.jpg", disposition: "inline"),
            Self.jpeg("b.jpg", contentID: "b@example.com", disposition: "inline")])))
        cut.isShortened = true
        XCTAssertEqual(PrintPage.photos(of: cut, cut: true).map(\.id), ["2"])
        XCTAssertEqual(PrintPage.body(cut).html, PrintPage.shortened + together + photo("2", of: cut) + "</div>"
                       + words)

        // Not printed: a picture attached, a TIFF, and an HTML letter's
        // photo that its markup does not name.
        for (label, raw) in [
            ("attached", Self.letter(Self.mixed([Self.plain(words), Self.jpeg("IMG_0185.jpg")]))),
            ("a TIFF", Self.letter(Self.mixed([Self.plain(words), Self.tiff("scan.tif")]))),
            ("HTML", Self.letter(Self.mixed([Self.html(words), Self.jpeg("IMG_0185.jpg", disposition: "inline")]))),
        ] {
            let m = Self.message(raw)
            XCTAssertEqual(m.attachments.count, 1, label)
            XCTAssertEqual(PrintPage.photos(of: m, cut: false), [], label)
            let printed = PrintPage.body(m).html
            XCTAssertFalse(printed.contains(PrintPage.photoClass), label)
            XCTAssertFalse(printed.contains("break-before"), label)
            XCTAssertFalse(printed.contains("<img"), label)
        }
    }

    /// The photo's most sizes print as points on the sheet (B-185, fixed
    /// again; round r6-r-copy, 30 October 2026): WebKit's print lays the
    /// page out 1.25 times wider than the web view it prints, the
    /// column's 540 points, and shrinks it to the sheet, so a CSS pixel
    /// prints as 0.8 points. The width as a share of the column, which
    /// the shrink leaves as it is: 496 of 540 points, Mail's 81% of the
    /// sheet; the height in the layout's pixels: the column's 720 points
    /// at 0.8, 900. The round's photo, 1600 by 1200, then prints 496 by
    /// 372 points, within the column's height.
    func testAPlainLettersPhotoPrintsAtMailsWidthInPoints() {
        let column = PrintPage.paperWidth - 2 * PrintPage.margin
        XCTAssertEqual(column, 540)
        XCTAssertEqual(PrintPage.printLayoutFactor, 1.25, "WebCore's printingMinimumShrinkFactor")
        XCTAssertEqual(PrintPage.photoWidth, 496)
        XCTAssertEqual(PrintPage.photoWidthShare, "91.85%")
        XCTAssertEqual(PrintPage.photoHeight, 720)
        XCTAssertEqual(PrintPage.photoHeightPixels, 900)
        XCTAssertTrue(PrintPage.photoStyle.contains("max-width: 91.85% !important;"))
        XCTAssertTrue(PrintPage.photoStyle.contains("max-height: 900px !important;"))

        // On paper: the layout is the column times the factor, CSS pixels
        // wide, and each pixel prints 1 / factor points.
        let layout = column * PrintPage.printLayoutFactor
        XCTAssertEqual(layout, 675)
        let share = Double(PrintPage.photoWidthShare.dropLast()) ?? 0
        let printedWidth = layout * share / 100 / PrintPage.printLayoutFactor
        XCTAssertEqual(printedWidth, 496, accuracy: 0.1, "Mail's width")
        XCTAssertEqual(printedWidth / PrintPage.paperWidth, 0.81, accuracy: 0.005)
        let printedHeight = Double(PrintPage.photoHeightPixels) / PrintPage.printLayoutFactor
        XCTAssertEqual(printedHeight, 720, "the column's height")
        // The round's photo, its shape kept.
        let (width, height) = (1_600.0, 1_200.0)
        let scale = min(printedWidth / width, printedHeight / height, 1 / PrintPage.printLayoutFactor)
        XCTAssertEqual(width * scale, 496, accuracy: 0.1)
        XCTAssertEqual(height * scale, 372, accuracy: 0.1)
    }

    // MARK: - Its tile shows it coming

    /// A tile shows its file coming, as Mail's does (B-176): Mail's ring
    /// in its icon's place and "Downloading" in its last line, once
    /// however often it is said, until the pane says it has opened or been
    /// let go, and then as it was, its icon back, "Tap to Download" again
    /// for a file left on the server. Not dimmed, as it was with
    /// "Loading…" (B-148). On a letter's own page and in a body of a
    /// stack; a file of another letter changes nothing. The script run in
    /// node on the model of the page (`ModelPage`).
    func testItsTileShowsItComing() throws {
        var letter = Self.message(BodyInOrderTests.among)
        let coming = BodyFiles.Busy("2.2", of: letter.id, busy: true)
        let done = BodyFiles.Busy("2.2", of: letter.id, busy: false)
        let link = BodyFiles.link("2.2", of: letter.id)
        XCTAssertEqual(coming.link, link)
        XCTAssertEqual(coming.arguments["words"] as? String, "Downloading")
        XCTAssertEqual(coming.arguments["ring"] as? String, BodyFiles.ring)
        XCTAssertEqual(coming.arguments["busy"] as? Bool, true)
        XCTAssertEqual(done.arguments["busy"] as? Bool, false)
        let dimmed = ModelPage.Run.File(href: link, style: [:], status: "Downloading", icon: "bm-file-ring")
        let other = BodyFiles.Busy("2.2", of: "7/9", busy: true)

        // A letter opened without its files: its tile drawn coming, as the
        // file comes as it opens (`FilesAhead`), and so again after a tap.
        for (said, icon, left) in [("", "", false), ("Downloading", "bm-file-ring", true)] {
            letter.filesLeftOnServer = left
            let asItWas = ModelPage.Run.File(href: link, style: [:], status: said, icon: icon)
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
    /// back on the page it was shown on, and not on a page given since,
    /// unless it was handed to what it opens in; by script, in the app's
    /// content world. No header row is told anything.
    func testThePaneShowsTheTileComingFromTheTapToTheEnd() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(code.contains(
            "guard !editDimmed, let m = letter ?? message else { return } "
                + "run(BodyFiles.Busy(attachment.id, of: m.id, busy: true)) let shown = loads.shown"))
        XCTAssertTrue(code.contains(
            "fileTaps.ended(file) if !handedOver && loads.stillShows(shown) { "
                + "run(BodyFiles.Busy(attachment.id, of: m.id, busy: false)) } }"))
        XCTAssertTrue(code.contains(
            "private func run(_ busy: BodyFiles.Busy) { webView.callAsyncJavaScript(BodyFiles.Busy.script, "
                + "arguments: busy.arguments, in: nil, in: .defaultClient) }"))
        XCTAssertEqual(code.components(separatedBy: "BodyFiles.Busy(").count - 1, 3)
        XCTAssertFalse(code.contains("header.setAttachment"))
        XCTAssertFalse(code.contains("onSelectAttachment"))
    }

    /// The tile stays dimmed, saying "Loading…", until what the file opens
    /// in is on the screen: each of the three presentations, Quick Look
    /// for a tap, the held menu's or Markup and Reply's, one since B-176,
    /// Save to Files' and Share's, is
    /// handed the clearing as its completion, which UIKit runs once its
    /// transition has ended, and the `defer` that ends the download clears
    /// it only where nothing was handed over: a failure, a file let go, a
    /// file kept with nothing put over the pane. Cleared in the `defer`
    /// for all, a file kept on the iPad was dimmed for a frame or none
    /// and Quick Look came up a third of a second later over the tile as
    /// it was (found on the test iPad, 2026-10-27). Read from the source.
    func testTheTileIsDimmedUntilQuickLookIsUp() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        let start = try XCTUnwrap(code.range(of: "private func openAttachment("))
        let end = try XCTUnwrap(code.range(of: "private func prepareInlineImages(",
                                           range: start.upperBound..<code.endIndex))
        let open = String(code[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(open.contains(
            "let ready: () -> Void = { [weak self] in guard let self, self.loads.stillShows(shown) else { return } "
                + "self.run(BodyFiles.Busy(attachment.id, of: m.id, busy: false)) }"), open)
        XCTAssertTrue(open.contains("if !handedOver && loads.stillShows(shown) {"), open)
        for presented in [
            "present(UIDocumentPickerViewController(forExporting: [url], asCopy: true), animated: true, "
                + "completion: ready)",
            "share.heldAtLarge() present(share, animated: true, completion: ready)",
            "marking = (m, attachment) } handedOver = true present(preview, animated: true, completion: ready) "
                + "} } catch {",
        ] {
            XCTAssertTrue(open.contains("handedOver = true " + presented)
                          || open.contains(presented), presented)
        }
        XCTAssertEqual(open.components(separatedBy: "handedOver = true present(").count - 1
                       + open.components(separatedBy: "handedOver = true share.heldAtLarge() present(").count - 1,
                       3, open)
        XCTAssertEqual(open.components(separatedBy: "present(").count - 1, 3, open)
        XCTAssertFalse(open.contains("animated: true)"), open)
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
        XCTAssertEqual(menu("application/pdf"), PanePictures.pdfMenu, "Markup and Reply second (B-176)")
        XCTAssertEqual(menu("text/calendar"), PanePictures.fileMenu)
        XCTAssertEqual(menu("IMAGE/TIFF"), PanePictures.menu, "a picture drawn as a tile: Save Image too")
        XCTAssertEqual(menu("image/heic"), PanePictures.menu)
    }

    /// A tap on a picture file opens it whatever its size, as a tile does:
    /// it is a file, and no logo; a hold gives the held photo's menu, by
    /// its picture's address, on a letter's own page and in a stack. A
    /// picture the letter shows by `cid:` is as B-122 has it: not opened
    /// when small. A picture file of another letter opens nothing, nor
    /// does a file that is no picture, by a picture's address.
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
        // The logo by the address of a picture the pane draws: its own,
        // as the pane draws it so where the body shown does not show it.
        XCTAssertEqual(PanePictures.part("bmfile-m7_3-3", of: m), logo)
        XCTAssertNil(PanePictures.part("bmfile-m7_3-4", of: m), "no such part")
        XCTAssertNil(PanePictures.part("bmfile-m7_3-3", of: Message(
            id: "7/3", mailboxID: "INBOX", sender: "Jane <jane@example.com>", senderAddress: "jane@example.com",
            to: [], cc: [], subject: "Plan", date: Date(timeIntervalSince1970: 1_792_679_717), textBody: "Plan.",
            htmlBody: nil, attachments: [Attachment(id: "3", filename: "plan.pdf", mimeType: "application/pdf",
                                                    size: 900)])), "not a picture")
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
            "private func holdFile(_ held: BodyFiles.Hold) { guard presentedViewController == nil, !editDimmed, "
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
