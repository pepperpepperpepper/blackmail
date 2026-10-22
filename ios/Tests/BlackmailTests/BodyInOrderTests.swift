import XCTest
@testable import Blackmail

/// A letter's body is every part of it, in order, as Mail draws them
/// (`MIMEDecoder.bodyPlan(of:)`, `MIMEDecoder.joined`).
///
/// B-113: Apple Mail on an iPad sends a file put in the middle of a letter
/// between two parts of its HTML, and the pane showed the words before the
/// file and nothing after it. B-114: a note with a letter forwarded inline
/// after it showed the note alone, and the forwarded letter was nowhere.
/// The shapes here are the ones the test iPad was given on 2026-10-22.
final class BodyInOrderTests: XCTestCase {

    // MARK: - Letters

    private static func raw(_ text: String) -> Data {
        Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)
    }

    private static let header = """
        From: Jane <jane@example.com>
        To: sam@example.com
        Subject: The programme
        Date: Thu, 22 Oct 2026 14:35:17 +0000
        Message-ID: <programme@example.com>
        MIME-Version: 1.0

        """

    private static let pdf = """
        Content-Transfer-Encoding: base64
        Content-Type: application/pdf; x-unix-mode=0644; name="Programme.pdf"
        Content-Disposition: inline; filename="Programme.pdf"

        JVBERi0xLjQK
        """

    static let firstHTML = "<div dir=\"ltr\">Words before the PDF: the programme is below.</div>"
        + "<div dir=\"ltr\"><br></div><div dir=\"ltr\"></div>"
    static let secondHTML = "<div dir=\"ltr\"></div><div dir=\"ltr\"><br></div><div dir=\"ltr\">"
        + "Words after the PDF: see you on Thursday at two.</div><div dir=\"ltr\"><br></div>"
        + "<div dir=\"ltr\">Sent from my iPad</div>"

    private static func document(_ body: String) -> String {
        "<html><head><meta http-equiv=\"content-type\" content=\"text/html; charset=utf-8\"></head>"
            + "<body dir=\"auto\">" + body + "</body></html>"
    }

    static let plainWords = "Words before the PDF: the programme is below.\n\n\n\n"
        + "Words after the PDF: see you on Thursday at two.\n\nSent from my iPad\n"

    /// Apple Mail's shape for a PDF put among the words, as the iPad was
    /// given it (`06-pdf-among.eml`): the plain words whole, and the HTML
    /// split around the PDF, sent inline with no `Content-ID`.
    static var among: Data {
        raw(header + """
            Content-Type: multipart/alternative; boundary="ALT"
            X-Mailer: iPad Mail (20F75)

            --ALT
            Content-Type: text/plain; charset="utf-8"
            Content-Transfer-Encoding: quoted-printable

            \(plainWords)
            --ALT
            Content-Type: multipart/mixed; boundary="MIX"

            --MIX
            Content-Type: text/html; charset="utf-8"

            \(document(firstHTML))
            --MIX
            \(pdf)
            --MIX
            Content-Type: text/html; charset="utf-8"

            \(document(secondHTML))
            --MIX--

            --ALT--
            """)
    }

    /// The same without the plain words (`05-pdf-one.eml`): the HTML, the
    /// PDF, and "Sent from my iPad" after it.
    static var mixed: Data {
        raw(header + """
            Content-Type: multipart/mixed; boundary="MIX"

            --MIX
            Content-Type: text/html; charset="utf-8"

            <div dir="ltr">Here is the programme, sent from Mail on an iPad.</div>
            --MIX
            \(pdf)
            --MIX
            Content-Type: text/html; charset="utf-8"

            <div dir="ltr"><br></div><div dir="ltr">Sent from my iPad</div>
            --MIX--
            """)
    }

    /// Plain words split around the PDF, with no HTML at all.
    static var plain: Data {
        raw(header + """
            Content-Type: multipart/mixed; boundary="MIX"

            --MIX
            Content-Type: text/plain; charset="utf-8"

            Words before the PDF.
            --MIX
            \(pdf)
            --MIX
            Content-Type: text/plain; charset="utf-8"

            Words after the PDF.
            --MIX--
            """)
    }

    static let forwardedHeader = """
        From: Sam Example <sam@example.com>
        To: Jane <jane@example.com>
        Subject: The forwarded words after a note
        Date: Wed, 21 Oct 2026 14:36:17 +0000
        Message-ID: <inner@example.com>


        """

    /// The forwarder's note, then the letter forwarded inline as
    /// message/rfc822 with no name (`09-fwd-note.eml`, mutt's
    /// `mime_forward`).
    static func forward(_ inner: String, files: [String] = []) -> Data {
        raw(header + """
            Content-Type: multipart/mixed; boundary="FWD"

            --FWD
            Content-Type: text/plain; charset="utf-8"
            Content-Transfer-Encoding: quoted-printable

            My own note above the forwarded letter.

            --FWD
            Content-Type: message/rfc822
            Content-Disposition: inline

            \(inner)
            """ + files.map { "--FWD\n" + $0 + "\n" }.joined() + "--FWD--\n")
    }

    static var forwardedWords: String {
        "Content-Type: text/plain; charset=\"utf-8\"\n" + forwardedHeader
            + "The forwarded letter's words, after the forwarder's own note.\n"
    }

    static let when = IMAPParser.parseHeaderDate("Wed, 21 Oct 2026 14:36:17 +0000")!

    /// The header lines Mail draws above the forwarded letter's words.
    static var forwardedLines: String {
        "Begin forwarded message:\n\n"
            + "From: Sam Example <sam@example.com>\n"
            + "Date: \(MailFormat.forwardedDate(when))\n"
            + "To: Jane <jane@example.com>\n"
            + "Subject: The forwarded words after a note\n\n"
    }

    static var forwardedLinesHTML: String {
        "<div dir=\"ltr\"><br>Begin forwarded message:<br><br></div><div dir=\"ltr\">"
            + "<b>From:</b> Sam Example &lt;sam@example.com&gt;<br>"
            + "<b>Date:</b> \(MailFormat.forwardedDate(when))<br>"
            + "<b>To:</b> Jane &lt;jane@example.com&gt;<br>"
            + "<b>Subject:</b> <b>The forwarded words after a note</b><br><br></div>"
    }

    private func letter(_ raw: Data, id: String = "7/3") -> Message {
        let decoded = MIMEDecoder.decodeMessage(raw)
        return Message(id: id, mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                       senderAddress: "jane@example.com", to: ["sam@example.com"], cc: [],
                       subject: "The programme", date: Date(timeIntervalSince1970: 1_792_679_717),
                       textBody: decoded.text, htmlBody: decoded.html,
                       attachments: decoded.attachments, messageID: "<programme@example.com>")
    }

    private func listed(_ raw: Data) -> [String] {
        MIMEDecoder.listedAttachments(in: MIMEDecoder.parseStructure(raw)).map(\.filename)
    }

    private func clip(_ raw: Data) -> Bool {
        IMAPMailRepository.hasAttachment(MIMEDecoder.parseStructure(raw))
    }

    private let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)

    private func order(_ needles: [String], in text: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        var from = text.startIndex
        for needle in needles {
            guard let found = text.range(of: needle, range: from..<text.endIndex) else {
                return XCTFail("\(needle) not after the one before it in \(text)", file: file, line: line)
            }
            from = found.upperBound
        }
    }

    // MARK: - B-113: the words after a file among them

    /// Apple Mail's shape: the HTML is both of its parts, the PDF marked
    /// where it sat, each part without its wrapper; the plain words are the
    /// plain part as it came. The PDF is listed from the structure and from
    /// the letter alike, with its paperclip, and the preview is the plain
    /// words, as before.
    func testTheWordsAfterAFileAmongThemAreInTheBody() {
        let decoded = MIMEDecoder.decodeMessage(Self.among)
        XCTAssertEqual(decoded.html, Self.firstHTML + "<!--bm-file:2.2-->" + Self.secondHTML)
        XCTAssertEqual(decoded.text, Self.plainWords)
        XCTAssertEqual(decoded.attachments.map(\.filename), ["Programme.pdf"])
        XCTAssertEqual(letter(Self.among).listedAttachments.map(\.id), ["2.2"])
        XCTAssertEqual(listed(Self.among), ["Programme.pdf"])
        XCTAssertTrue(clip(Self.among))
        XCTAssertEqual(MIMEDecoder.previewPart(MIMEDecoder.parseStructure(Self.among))?.section, "1")
        XCTAssertEqual(MIMEDecoder.bodyPlan(of: MIMEDecoder.parseStructure(Self.among)).sections,
                       ["1", "2.1", "2.3"])
    }

    /// The same without the plain words: the HTML both parts, and no plain
    /// words of its own, so a reply quotes the HTML's, every one.
    func testTheWordsAfterAFileAreInTheBodyWithNoPlainWordsBeside() {
        let decoded = MIMEDecoder.decodeMessage(Self.mixed)
        XCTAssertEqual(decoded.html, "<div dir=\"ltr\">Here is the programme, sent from Mail on an iPad."
                       + "</div><!--bm-file:2--><div dir=\"ltr\"><br></div><div dir=\"ltr\">Sent from my "
                       + "iPad</div>")
        XCTAssertNil(decoded.text)
        XCTAssertEqual(listed(Self.mixed), ["Programme.pdf"])
        XCTAssertTrue(clip(Self.mixed))
        XCTAssertEqual(MIMEDecoder.previewPart(MIMEDecoder.parseStructure(Self.mixed))?.section, "1")
        order(["Here is the programme", "Sent from my iPad"], in: letter(Self.mixed).quotableText)
    }

    /// Plain words split around a file: both, each on a line of its own,
    /// and no HTML, so no row among them.
    func testPlainWordsAroundAFileAreBothInTheBody() {
        let decoded = MIMEDecoder.decodeMessage(Self.plain)
        XCTAssertEqual(decoded.text, "Words before the PDF.\nWords after the PDF.")
        XCTAssertNil(decoded.html)
        XCTAssertEqual(listed(Self.plain), ["Programme.pdf"])
        XCTAssertTrue(clip(Self.plain))
        let page = PanePage.letter(letter(Self.plain), style: style) ?? ""
        XCTAssertFalse(page.contains(BodyFiles.scheme), page)
    }

    /// A reply quotes every word he saw, the words after the PDF too, and
    /// its HTML twin carries no mark; a forward the same, with the PDF as
    /// a file.
    func testAReplyAndAForwardQuoteEveryWordHeSaw() {
        let account = MailAccount(address: "sam@example.com", username: "sam@example.com",
                                  displayName: "Sam Example")
        let shapes = [(Self.among, ["Words before the PDF", "Words after the PDF", "Sent from my iPad"]),
                      (Self.mixed, ["Here is the programme", "Sent from my iPad"])]
        for (raw, words) in shapes {
            let m = letter(raw)
            let reply = Draft.replying(to: m, all: false, myAddress: "sam@example.com")
            let forward = Draft.forwarding(m)
            for draft in [reply, forward] {
                order(words, in: draft.body)
                let html = AppleMailHTML.letter(for: draft, account: account).html ?? ""
                XCTAssertTrue(html.contains("Sent from my iPad"), html)
                XCTAssertFalse(html.contains("bm-file"), html)
            }
            XCTAssertEqual(forward.attachments.map(\.filename), ["Programme.pdf"])
        }
    }

    /// On the letter's own page and in a conversation's stack, the PDF's
    /// row is where it sat, its name and size as the header has them, and
    /// its link opens it.
    func testAFileAmongTheWordsHasItsRowWhereItSat() throws {
        let m = letter(Self.among)
        let row = "<div style=\"margin: 0;\"><a href=\"bmfile:2.2?letter=7/3\" "
            + "style=\"display: inline-block; padding: 10px 0; text-decoration: none;\">"
            + "Programme.pdf (" + ByteCountFormatter.string(fromByteCount: 9, countStyle: .file)
            + ")</a></div>"
        let page = try XCTUnwrap(PanePage.letter(m, style: style))
        let stack = PanePage.stackBody(m).html
        for drawn in [page, stack] {
            order(["Words before the PDF", row, "Words after the PDF", "Sent from my iPad"], in: drawn)
            XCTAssertFalse(drawn.contains("<!--bm-file:"), drawn)
        }
        XCTAssertEqual(PaneNavigation.decide(.linkActivated, mainFrame: true,
                                             url: URL(string: "bmfile:2.2?letter=7/3")),
                       .openFile(letter: "7/3", section: "2.2"))
    }

    /// Only a file the header lists gets a row: not a picture the body
    /// shows by `cid:`, not a part the letter does not have, and each file
    /// once. A file before or after all the words has no mark at all.
    func testOnlyAFileTheHeaderListsHasARowAmongTheWords() throws {
        let logo = """
            Content-Type: image/png; name="logo.png"
            Content-Transfer-Encoding: base64
            Content-ID: <logo@example.com>
            Content-Disposition: inline; filename="logo.png"

            iVBORw0K
            """
        let raw = Self.raw(Self.header + """
            Content-Type: multipart/mixed; boundary="MIX"

            --MIX
            \(Self.pdf)
            --MIX
            Content-Type: text/html; charset="utf-8"

            <p>One.</p><img src="cid:logo@example.com"><!--bm-file:9--><!--bm-file:2-->
            --MIX
            \(logo)
            --MIX
            Content-Type: text/html; charset="utf-8"

            <p>Two.</p>
            --MIX
            \(Self.pdf)
            --MIX--
            """)
        let decoded = MIMEDecoder.decodeMessage(raw)
        XCTAssertEqual(decoded.html, "<p>One.</p><img src=\"cid:logo@example.com\"><!--bm-file:9-->"
                       + "<!--bm-file:2--><!--bm-file:3--><p>Two.</p>")
        let m = letter(raw)
        XCTAssertEqual(m.listedAttachments.map(\.id), ["1", "5"])
        let page = try XCTUnwrap(PanePage.letter(m, style: style))
        XCTAssertFalse(page.contains("bmfile:"), page)
        XCTAssertTrue(page.contains("<!--bm-file:3-->"), "the logo's mark stays a comment")
        // A sender's own mark of a file the header lists is drawn, as the
        // row it is, but once: each file has one row among the words.
        let twice = BodyFiles.rows(in: "<p>a</p><!--bm-file:5--><p>b</p><!--bm-file:5-->", of: m)
        XCTAssertEqual(twice.components(separatedBy: "bmfile:5?letter=7/3").count - 1, 1, twice)
        XCTAssertTrue(twice.hasSuffix("<p>b</p><!--bm-file:5-->"), twice)
    }

    /// A text file sent inline after the words is a file, as B-101 lists
    /// it, and not the plain words: before, it was taken for them, and a
    /// reply quoted the file in place of the letter.
    func testATextFileAfterTheWordsIsAFileNotTheWords() {
        let raw = Self.raw(Self.header + """
            Content-Type: multipart/mixed; boundary="MIX"

            --MIX
            Content-Type: text/html; charset="utf-8"

            <p>The notes are attached.</p>
            --MIX
            Content-Type: text/plain; charset="utf-8"; name="notes.txt"
            Content-Disposition: inline; filename="notes.txt"

            Gutters first.
            --MIX--
            """)
        let decoded = MIMEDecoder.decodeMessage(raw)
        XCTAssertNil(decoded.text)
        XCTAssertEqual(decoded.html, "<p>The notes are attached.</p>")
        XCTAssertEqual(listed(raw), ["notes.txt"])
        XCTAssertTrue(clip(raw))
        XCTAssertEqual(letter(raw).quotableText.trimmingCharacters(in: .whitespacesAndNewlines),
                       "The notes are attached.")
    }

    /// A row's link opens the file and nothing else: never "Open this
    /// link?", never Safari, and a link that names no letter or no part
    /// opens nothing.
    func testAFilesLinkNeverLeavesThePane() {
        XCTAssertEqual(PaneNavigation.decide(.linkActivated, mainFrame: true,
                                             url: URL(string: BodyFiles.link("1.2.3", of: "600001/42"))),
                       .openFile(letter: "600001/42", section: "1.2.3"))
        for bad in ["bmfile:2", "bmfile:?letter=7/3", "bmfile:2;x?letter=7/3", "BMFILE:2?other=7/3",
                    "bmfile://host/2?letter=7/3"] {
            XCTAssertEqual(PaneNavigation.decide(.linkActivated, mainFrame: true, url: URL(string: bad)),
                           .cancel, bad)
        }
        XCTAssertEqual(PaneNavigation.decide(.other, mainFrame: true,
                                             url: URL(string: "bmfile:2?letter=7/3")), .cancel)
        let web = URL(string: "https://example.com/programme")!
        XCTAssertEqual(PaneNavigation.decide(.linkActivated, mainFrame: true, url: web), .follow(web))
    }

    // MARK: - B-114: a letter forwarded after a note

    /// The note, the forwarded letter's header lines in Mail's form, then
    /// its words; no row and no paperclip, as it carries no file; the
    /// preview the note's.
    func testALetterForwardedAfterANoteIsShownUnderIt() {
        let raw = Self.forward(Self.forwardedWords)
        let decoded = MIMEDecoder.decodeMessage(raw)
        XCTAssertEqual(decoded.text, "My own note above the forwarded letter.\n\n" + Self.forwardedLines
                       + "The forwarded letter's words, after the forwarder's own note.")
        XCTAssertNil(decoded.html)
        XCTAssertEqual(decoded.attachments.map(\.filename), [])
        XCTAssertFalse(clip(raw))
        XCTAssertEqual(MIMEDecoder.previewPart(MIMEDecoder.parseStructure(raw))?.section, "1")
        let m = letter(raw)
        order(["My own note", "Begin forwarded message:", "Subject: The forwarded words after a note",
               "The forwarded letter's words"],
              in: Draft.replying(to: m, all: false, myAddress: "sam@example.com").body)
    }

    /// Sent as base64, as the second run on the iPad was
    /// (`vf-B-fwd-note.eml`): the same.
    func testALetterForwardedAfterANoteInBase64IsShownUnderIt() {
        let inner = "Content-Type: text/plain; charset=\"utf-8\"\nContent-Transfer-Encoding: base64\n"
            + Self.forwardedHeader
            + Data("The forwarded letter's words.\n".utf8).base64EncodedString() + "\n"
        let raw = Self.raw(Self.header + """
            Content-Type: multipart/mixed; boundary="FWD"

            --FWD
            Content-Type: text/plain; charset="utf-8"
            Content-Transfer-Encoding: base64

            \(Data("My own note.\n".utf8).base64EncodedString())

            --FWD
            Content-Type: message/rfc822
            Content-Disposition: inline

            \(inner)
            --FWD--
            """)
        XCTAssertEqual(MIMEDecoder.decodeMessage(raw).text,
                       "My own note.\n\n" + Self.forwardedLines + "The forwarded letter's words.\n")
    }

    /// A forwarded letter of HTML: the pane draws the HTML, the note as
    /// text in it, then the header lines, then the letter's own markup; the
    /// plain words are the note, the lines and the letter's plain words.
    func testAForwardedLetterOfHTMLIsDrawnUnderTheNote() {
        let inner = "Content-Type: multipart/alternative; boundary=\"IN\"\n" + Self.forwardedHeader
            + "--IN\nContent-Type: text/plain; charset=\"utf-8\"\n\nThe garden in June.\n"
            + "--IN\nContent-Type: text/html; charset=\"utf-8\"\n\n"
            + "<html><body style=\"margin: 0\"><p>The <b>garden</b> in June &amp; July.</p></body></html>\n"
            + "--IN--\n"
        let decoded = MIMEDecoder.decodeMessage(Self.forward(inner))
        XCTAssertEqual(decoded.html, "<div style=\"white-space: pre-wrap;\">My own note above the "
                       + "forwarded letter.\n</div>" + Self.forwardedLinesHTML
                       + "<p>The <b>garden</b> in June &amp; July.</p>")
        XCTAssertEqual(decoded.text, "My own note above the forwarded letter.\n\n" + Self.forwardedLines
                       + "The garden in June.")
    }

    /// The header lines are the ones his own Forward writes of the same
    /// letter, Mail's form, in the plain words and in the HTML.
    func testTheHeaderLinesAreTheOnesHisOwnForwardWrites() {
        let raw = Self.forward(Self.forwardedWords)
        let inner = MIMEDecoder.parse(raw).bodies["2"]!
        let fields = MIMEDecoder.forwardedFields(of: MIMEPart(), header: inner)
        XCTAssertEqual(fields?.text, Self.forwardedLines)
        let original = Message(id: "1/1", mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                               senderAddress: "sam@example.com", to: ["Jane <jane@example.com>"], cc: [],
                               subject: "The forwarded words after a note", date: Self.when,
                               textBody: "x", htmlBody: nil, attachments: [])
        XCTAssertTrue(Draft.forwarding(original).body.contains("\n\n" + Self.forwardedLines + "x"))
        XCTAssertEqual(fields?.html, Self.forwardedLinesHTML)
    }

    /// The preview is where the letter begins, its first part, plain words
    /// before HTML where both are the same part: HTML then a plain footer
    /// is previewed from the HTML. It was the footer, the first plain part
    /// of all.
    func testThePreviewIsWhereTheLetterBegins() {
        let raw = Self.raw(Self.header + """
            Content-Type: multipart/mixed; boundary="MIX"

            --MIX
            Content-Type: text/html; charset="utf-8"

            <p>The garden in June.</p>
            --MIX
            Content-Type: text/plain; charset="utf-8"

            The garden club, 12 High Street.
            --MIX--
            """)
        XCTAssertEqual(MIMEDecoder.previewPart(MIMEDecoder.parseStructure(raw))?.section, "1")
        let decoded = MIMEDecoder.decodeMessage(raw)
        XCTAssertEqual(decoded.html, "<p>The garden in June.</p><div style=\"white-space: pre-wrap;\">"
                       + "The garden club, 12 High Street.</div>")
        XCTAssertEqual(decoded.text, "The garden in June.\nThe garden club, 12 High Street.")
    }

    /// The forwarded letter's own file is listed, with the paperclip, and
    /// the letter itself is no file; a forwarded letter whose words are a
    /// text part with a name has them in the body, and no row or paperclip
    /// for them.
    func testAForwardedLettersOwnFilesAreListed() {
        let inner = "Content-Type: multipart/mixed; boundary=\"IN\"\n" + Self.forwardedHeader
            + "--IN\nContent-Type: text/plain; charset=\"utf-8\"\n\nIt carries a PDF of its own.\n"
            + "--IN\nContent-Type: application/pdf; name=\"Earlier.pdf\"\n"
            + "Content-Disposition: attachment; filename=\"Earlier.pdf\"\n"
            + "Content-Transfer-Encoding: base64\n\nJVBERi0xLjQK\n--IN--\n"
        let raw = Self.forward(inner)
        let decoded = MIMEDecoder.decodeMessage(raw)
        XCTAssertEqual(decoded.attachments.map(\.filename), ["Earlier.pdf"])
        XCTAssertEqual(listed(raw), ["Earlier.pdf"])
        XCTAssertTrue(clip(raw))
        order(["My own note", "Begin forwarded message:", "It carries a PDF of its own."],
              in: decoded.text ?? "")

        let named = Self.forward("Content-Type: text/plain; charset=\"utf-8\"; name=\"letter.txt\"\n"
                                 + "Content-Disposition: inline; filename=\"letter.txt\"\n"
                                 + Self.forwardedHeader + "Its words, in a file of their own name.\n")
        XCTAssertEqual(MIMEDecoder.decodeMessage(named).attachments.map(\.filename), [])
        XCTAssertEqual(listed(named), [])
        XCTAssertFalse(clip(named))
        order(["My own note", "Begin forwarded message:", "Its words, in a file of their own name."],
              in: MIMEDecoder.decodeMessage(named).text ?? "")
    }

    /// A letter forwarded as a file, named, or sent as an attachment, or
    /// both, is a file's row with its paperclip, as it always was, and the
    /// body the note alone.
    func testALetterForwardedAsAFileIsStillAFile() {
        let shapes: [(headers: String, name: String)] = [
            ("Content-Type: message/rfc822; name=\"forwarded.eml\"\n"
                + "Content-Disposition: attachment; filename=\"forwarded.eml\"\n", "forwarded.eml"),
            ("Content-Type: message/rfc822\nContent-Disposition: attachment\n", "attachment-2.eml"),
            ("Content-Type: message/rfc822; name=\"forwarded.eml\"\n", "forwarded.eml"),
        ]
        for shape in shapes {
            let raw = Self.raw(Self.header + """
                Content-Type: multipart/mixed; boundary="FWD"

                --FWD
                Content-Type: text/plain; charset="utf-8"

                My own note.
                --FWD
                \(shape.headers)
                \(Self.forwardedWords)
                --FWD--
                """)
            let decoded = MIMEDecoder.decodeMessage(raw)
            XCTAssertEqual(decoded.text, "My own note.", shape.headers)
            XCTAssertNil(decoded.html, shape.headers)
            XCTAssertEqual(decoded.attachments.map(\.filename), [shape.name], shape.headers)
            XCTAssertEqual(listed(raw), [shape.name], shape.headers)
            XCTAssertTrue(clip(raw), shape.headers)
        }
    }

    /// A letter that is nothing but the one it forwards reads as it always
    /// did: its words, with no header lines above them.
    func testALetterThatIsOnlyTheOneItForwardsHasNoHeaderLines() {
        let raw = Self.raw(Self.header + """
            Content-Type: multipart/mixed; boundary="FWD"

            --FWD
            Content-Type: message/rfc822
            Content-Disposition: inline

            \(Self.forwardedWords)
            --FWD--
            """)
        XCTAssertEqual(MIMEDecoder.decodeMessage(raw).text,
                       "The forwarded letter's words, after the forwarder's own note.\n")
    }

    /// A forwarded letter sent inline with a name: drawn under the note, as
    /// any forwarded letter sent inline is, with no row and no paperclip.
    /// Inline is the sender's word that it be shown, and `isAttachment`
    /// takes nothing sent inline for a file; with a name and no
    /// disposition, or sent as an attachment, it is a file
    /// (`testALetterForwardedAsAFileIsStillAFile`).
    func testANamedLetterForwardedInlineIsDrawnUnderTheNote() {
        let raw = Self.raw(Self.header + """
            Content-Type: multipart/mixed; boundary="FWD"

            --FWD
            Content-Type: text/plain; charset="utf-8"

            My own note.
            --FWD
            Content-Type: message/rfc822; name="Earlier letter.eml"
            Content-Disposition: inline; filename="Earlier letter.eml"

            \(Self.forwardedWords)
            --FWD--
            """)
        let decoded = MIMEDecoder.decodeMessage(raw)
        XCTAssertEqual(decoded.text, "My own note.\n\n" + Self.forwardedLines
                       + "The forwarded letter's words, after the forwarder's own note.\n")
        XCTAssertEqual(decoded.attachments.map(\.filename), [])
        XCTAssertEqual(listed(raw), [])
        XCTAssertFalse(clip(raw))
    }

    /// A forwarded letter whose multipart is broken, its boundary never
    /// there, is read as one part of words, numbered as one part is (2.1),
    /// and its header lines are drawn above them: under the letter's own
    /// number its words took the place of the letter's bytes, and the
    /// lines were read from its words, which have none, so the forwarded
    /// words ran on from the note as if they were part of it. The bytes of
    /// the letter are the letter's, for a tap on its row when it is a file.
    func testAForwardedLetterWithABrokenMultipartKeepsItsHeaderLines() {
        let inner = """
            From: Sam <sam@example.com>
            Subject: Broken inner
            Content-Type: multipart/mixed; boundary="NEVER"

            The inner words with no boundary.
            """
        func forward(_ headers: String) -> Data {
            Self.raw(Self.header + """
                Content-Type: multipart/mixed; boundary="FWD"

                --FWD
                Content-Type: text/plain; charset="utf-8"

                My own note.
                --FWD
                \(headers)
                \(inner)
                --FWD--
                """)
        }
        let raw = forward("Content-Type: message/rfc822\nContent-Disposition: inline\n")
        XCTAssertEqual(MIMEDecoder.decodeMessage(raw).text,
                       "My own note.\n\nBegin forwarded message:\n\nFrom: Sam <sam@example.com>\n"
                       + "Subject: Broken inner\n\nThe inner words with no boundary.")
        let parsed = MIMEDecoder.parse(raw)
        XCTAssertEqual(parsed.structure.children.last?.children.first?.section, "2.1")
        XCTAssertEqual(parsed.bodies["2.1"], Data("The inner words with no boundary.".utf8))

        let attached = forward("Content-Type: message/rfc822; name=\"forwarded.eml\"\n"
                               + "Content-Disposition: attachment; filename=\"forwarded.eml\"\n")
        XCTAssertEqual(MIMEDecoder.decodeMessage(attached).attachments.map(\.filename), ["forwarded.eml"])
        XCTAssertEqual(MIMEDecoder.parse(attached).bodies["2"],
                       Data(inner.replacingOccurrences(of: "\n", with: "\r\n").utf8))
    }

    /// A forwarded letter sent base64 or quoted-printable, against RFC
    /// 2046 but sent all the same, is read with its encoding undone: its
    /// header lines, then its words. Before, its encoded lines were drawn
    /// as the forwarded letter's words.
    func testALetterForwardedUnderAnEncodingIsReadUnderIt() {
        let words = "The forwarded letter's words, after the forwarder's own note."
        let inner = Self.forwardedWords.replacingOccurrences(of: "\n", with: "\r\n")
        let base64 = Data(inner.utf8).base64EncodedString(options: [.lineLength76Characters,
                                                                   .endLineWithLineFeed])
        let printable = Self.forwardedWords.replacingOccurrences(of: "=", with: "=3D")
            .replacingOccurrences(of: "words, after", with: "words, =\nafter")
        for (encoding, body) in [("base64", base64), ("quoted-printable", printable)] {
            let raw = Self.raw(Self.header + """
                Content-Type: multipart/mixed; boundary="FWD"

                --FWD
                Content-Type: text/plain; charset="utf-8"

                My own note.
                --FWD
                Content-Type: message/rfc822
                Content-Disposition: inline
                Content-Transfer-Encoding: \(encoding)

                \(body)
                --FWD--
                """)
            let decoded = MIMEDecoder.decodeMessage(raw)
            XCTAssertEqual(decoded.text?.trimmingCharacters(in: .newlines),
                           "My own note.\n\n" + Self.forwardedLines + words, encoding)
            XCTAssertEqual(decoded.attachments.map(\.filename), [], encoding)
            XCTAssertFalse(clip(raw), encoding)
        }
    }

    /// A bounce, as one comes back for a mistyped address
    /// (multipart/report of the explanation, the delivery status and the
    /// letter returned): the explanation alone, in both bodies, as before,
    /// and not the returned letter under "Begin forwarded message:", which
    /// would read as a letter forwarded to him.
    func testABounceShowsItsExplanationAlone() {
        let raw = Self.raw(Self.header + """
            Content-Type: multipart/report; report-type=delivery-status; boundary="R"

            --R
            Content-Type: multipart/alternative; boundary="ALT"

            --ALT
            Content-Type: text/plain; charset="utf-8"

            Address not found.
            --ALT
            Content-Type: text/html; charset="utf-8"

            <p>Address not found.</p>
            --ALT--
            --R
            Content-Type: message/delivery-status

            Reporting-MTA: dns; mail.example.com

            Final-Recipient: rfc822; sam@exmaple.com
            Action: failed
            --R
            Content-Type: message/rfc822

            \(Self.forwardedWords)
            --R--
            """)
        let decoded = MIMEDecoder.decodeMessage(raw)
        XCTAssertEqual(decoded.text, "Address not found.")
        XCTAssertEqual(decoded.html, "<p>Address not found.</p>")
        XCTAssertEqual(MIMEDecoder.bodyPlan(of: MIMEDecoder.parseStructure(raw)).sections, ["1.1", "1.2"])
        XCTAssertEqual(MIMEDecoder.previewPart(MIMEDecoder.parseStructure(raw))?.section, "1.1")
    }

    /// An invitation's ICS with no name beside the words, as a calendar
    /// can send one: neither words nor a file, as before. With no words
    /// beside it, it is the letter's words, as it was: showing its raw ICS
    /// beats showing nothing.
    func testAnUnnamedCalendarBesideTheWordsIsNeitherWordsNorAFile() {
        let invitation = """
            Content-Type: text/calendar; charset="utf-8"; method=REQUEST

            BEGIN:VCALENDAR
            METHOD:REQUEST
            END:VCALENDAR
            """
        let raw = Self.raw(Self.header + """
            Content-Type: multipart/mixed; boundary="MIX"

            --MIX
            Content-Type: text/plain; charset="utf-8"

            Lunch on Thursday at one.
            --MIX
            \(invitation)
            --MIX--
            """)
        let decoded = MIMEDecoder.decodeMessage(raw)
        XCTAssertEqual(decoded.text, "Lunch on Thursday at one.")
        XCTAssertNil(decoded.html)
        XCTAssertEqual(decoded.attachments.map(\.filename), [])
        XCTAssertEqual(listed(raw), [])
        XCTAssertFalse(clip(raw))

        let alone = Self.raw(Self.header + """
            Content-Type: multipart/mixed; boundary="MIX"

            --MIX
            \(invitation)
            --MIX--
            """)
        XCTAssertEqual(MIMEDecoder.decodeMessage(alone).text, "BEGIN:VCALENDAR\nMETHOD:REQUEST\nEND:VCALENDAR")
    }

    /// A letter of more parts of words than a body holds, a hundred parts
    /// of HTML with a PDF among them: the first 64
    /// (`MIMEDecoder.maxBodyWords`), nothing after the last, not the PDF's
    /// mark, and said to be only the beginning. One of 64 is whole.
    func testABodyHoldsSixtyFourPartsOfWords() {
        func letter(_ count: Int) -> Data {
            var parts = (0..<count).map { "Content-Type: text/html; charset=\"utf-8\"\n\n<p>h\($0)</p>" }
            parts.insert(Self.pdf, at: 64)
            return Self.raw(Self.header + "Content-Type: multipart/mixed; boundary=\"MIX\"\n\n"
                            + parts.map { "--MIX\n" + $0 + "\n" }.joined() + "--MIX--\n")
        }
        let first = (0..<64).map { "<p>h\($0)</p>" }.joined()
        let many = MIMEDecoder.decodeMessage(letter(100))
        XCTAssertEqual(many.html, first)
        XCTAssertTrue(many.isShortened)
        XCTAssertEqual(many.attachments.map(\.filename), ["Programme.pdf"])
        XCTAssertEqual(MIMEDecoder.bodyPlan(of: MIMEDecoder.parseStructure(letter(100))).sections.count, 64)

        let all = MIMEDecoder.decodeMessage(letter(64))
        XCTAssertEqual(all.html, first)
        XCTAssertFalse(all.isShortened)
    }
}
