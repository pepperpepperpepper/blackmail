import XCTest
#if canImport(Glibc)
import Glibc
#endif
@testable import Blackmail

/// His photos go in the letter, after his last typed line and above his
/// signature, as every one of his Apple Mail letters with a picture had
/// them, in place of files under it (B-109).
///
/// Where they go is `AppleMailHTML.letter`'s, with the markup and the parts
/// made from one list; which rows they are is
/// `DraftAttachment.isBodyPicture`'s; a reopened draft knows its own by
/// where its saved markup shows them (`Draft.reopening`); and each goes as
/// a part inside the related set, read from its file as it goes, as a file
/// is (`RFC5322Builder.plan`, `Submission`). Nothing is sent anywhere.
final class PhotosInTheLetterTests: XCTestCase {

    private let sig = "Sam Example\n555-555-0142"
    private let richSig = "<div dir=\"ltr\"><table><tr><td><img src=\"cid:sig-logo\"></td>"
        + "<td><b>Sam Example</b></td></tr></table></div>"
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private let messageID = "<b109-photos@example.com>"
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        Diagnostics.clear()
        removeTranscripts()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotosInTheLetterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        removeTranscripts()
        super.tearDown()
    }

    private func transcript(_ outcome: String) -> String {
        (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
    }

    private func removeTranscripts() {
        for outcome in ["ok", "fail"] { try? FileManager.default.removeItem(atPath: transcript(outcome)) }
    }

    private func account(signature: String = "", html: String = "") -> MailAccount {
        MailAccount(address: "sam@example.com", username: "sam@example.com",
                    displayName: "Sam Example", signature: signature, signatureHTML: html)
    }

    /// Content-IDs a test can read: PHOTO-1, PHOTO-2, and on.
    private final class IDs {
        private var count = 0
        func next() -> String {
            count += 1
            return "PHOTO-\(count)"
        }
    }

    /// A photo he attached: a file on the iPad, as Photo Library, Attach
    /// File and the share sheet stage one.
    private func photo(_ name: String = "IMG_0077.jpg", _ type: String = "image/jpeg",
                       size: Int64 = 1_200) -> DraftAttachment {
        DraftAttachment(source: .localFile(URL(fileURLWithPath: "/staged/\(name)")),
                        filename: name, mimeType: type, size: size)
    }

    /// One photo's markup, as his iPad writes it.
    private func markup(_ id: String, _ name: String = "IMG_0077.jpg") -> String {
        "<div><br><br><img id=\"\(id)\" style=\"padding:0px 1px 1px 0px;\" alt=\"\(name)\" "
            + "src=\"cid:\(id)\"></div>"
    }

    /// A new letter: his words, his signature under them, and `files`.
    private func newLetter(_ words: String = "Dear Carlo,\n\nThe garden.",
                           signature: String? = nil, files: [DraftAttachment]) -> Draft {
        var draft = Draft(to: ["carlo@example.org"], subject: "The garden")
        draft.body = words + Draft.signatureBlock(signature ?? sig)
        draft.attachments = files
        return draft
    }

    private func letter(_ draft: Draft, _ account: MailAccount, forDraft: Bool = false,
                        reserving: Set<String> = []) -> AppleMailHTML.Letter {
        let ids = IDs()
        return AppleMailHTML.letter(for: draft, account: account, reserving: reserving,
                                    forDraft: forDraft, pictureID: ids.next)
    }

    /// Jane's letter to him: her photograph shown in its body, her logo,
    /// and a PDF.
    private func original(html: String? = "<div>Here is the garden.</div>"
                            + "<div><img src=\"cid:ii_garden01\"></div>") -> Message {
        Message(id: "600001/41", mailboxID: "INBOX", sender: "Jane Example <jane@example.com>",
                senderAddress: "jane@example.com", to: ["Sam Example <sam@example.com>"],
                cc: [], subject: "The garden", date: date, textBody: "Here is the garden.",
                htmlBody: html,
                attachments: [
                    Attachment(id: "2", filename: "garden.jpg", mimeType: "image/jpeg",
                               size: 1200, contentID: "ii_garden01", isInline: true),
                    Attachment(id: "3", filename: "Programme.pdf", mimeType: "application/pdf",
                               size: 22),
                ],
                messageID: "<garden-1@example.com>", gmailMessageID: 1_790_000_000_041)
    }

    private func index(of needle: String, in html: String) -> Int {
        html.range(of: needle).map { html.distance(from: html.startIndex, to: $0.lowerBound) } ?? -1
    }

    // MARK: - Where they go in the markup

    /// The shape of his own letters: his words, then the photo in a
    /// `<div>` of its own after two line breaks, then the signature's line
    /// break. A plain signature, and a rich one.
    func testHisPhotoGoesAfterHisWordsAndAboveHisSignature() throws {
        let draft = newLetter(files: [photo()])
        let made = letter(draft, account(signature: sig))
        let expected = AppleMailHTML.documentOpen
            + "Dear Carlo,<div><br></div><div>The garden.</div>"
            + markup("PHOTO-1")
            + AppleMailHTML.signatureAnchor + AppleMailHTML.signatureOpen
            + "<div dir=\"ltr\">Sam Example<div>555-555-0142</div></div>"
            + AppleMailHTML.signatureClose + AppleMailHTML.documentClose
        XCTAssertEqual(made.html, expected)
        XCTAssertEqual(made.bodyPictures, [AppleMailHTML.BodyPicture(contentID: "PHOTO-1",
                                                                     file: photo())])
        XCTAssertEqual(made.files, [], "not a file under the letter as well")

        let rich = try XCTUnwrap(letter(draft, account(signature: sig, html: richSig)).html)
        XCTAssertTrue(rich.contains("<div>The garden.</div>" + markup("PHOTO-1")
                                    + AppleMailHTML.signatureAnchor), rich)
        XCTAssertTrue(rich.contains("cid:sig-logo"))
    }

    /// No signature: the photo ends the letter. Nothing typed: it begins
    /// it, as in his letters that were a picture and his signature.
    func testWithNoSignatureItEndsTheLetterAndWithNoWordsItBeginsIt() {
        let plain = Draft(to: ["carlo@example.org"], body: "On my way", attachments: [photo()])
        XCTAssertEqual(letter(plain, account()).html,
                       AppleMailHTML.documentOpen + "On my way" + markup("PHOTO-1")
                           + AppleMailHTML.documentClose)

        var blank = Draft.blank(signature: sig)
        blank.attachments = [photo()]
        let html = letter(blank, account(signature: sig)).html ?? ""
        XCTAssertTrue(html.hasPrefix(AppleMailHTML.documentOpen + markup("PHOTO-1")
                                     + AppleMailHTML.signatureAnchor), html)
    }

    /// Several: each in its own `<div>`, in the order of his rows, each
    /// under its own Content-ID; a PDF and a video among them go as files,
    /// in their order, and every row is in one place only.
    func testSeveralPhotosEachInADivOfItsOwnInTheOrderOfHisRows() throws {
        let pdf = photo("Plans.pdf", "application/pdf")
        let video = photo("IMG_0005.MOV", "video/quicktime")
        let rows = [photo("IMG_0001.jpg"), pdf, photo("Image-1.png", "image/png"), video,
                    photo("smile.gif", "image/gif")]
        let made = letter(newLetter(files: rows), account(signature: sig))
        XCTAssertEqual(made.bodyPictures.map(\.contentID), ["PHOTO-1", "PHOTO-2", "PHOTO-3"])
        XCTAssertEqual(made.bodyPictures.map(\.file.filename),
                       ["IMG_0001.jpg", "Image-1.png", "smile.gif"])
        XCTAssertEqual(made.files, [pdf, video])
        let html = try XCTUnwrap(made.html)
        XCTAssertTrue(html.contains("<div>The garden.</div>" + markup("PHOTO-1", "IMG_0001.jpg")
                                    + markup("PHOTO-2", "Image-1.png")
                                    + markup("PHOTO-3", "smile.gif")
                                    + AppleMailHTML.signatureAnchor), html)
        XCTAssertEqual(made.bodyPictures.count + made.files.count, rows.count)
    }

    /// A reply, its quote as it was given and changed: the photo is under
    /// his words, the signature under it, the quote under that; with no
    /// signature, the photo is above the quote.
    func testInAReplyThePhotoIsAboveTheSignatureAndTheQuote() throws {
        var reply = Draft.replying(to: original(), all: false, myAddress: "sam@example.com",
                                   signature: sig)
        reply.body = "Lovely." + reply.body
        reply.attachments = [photo()]
        let intact = try XCTUnwrap(letter(reply, account(signature: sig)).html)
        XCTAssertTrue(intact.contains("Here is the garden."), "the original's own markup")
        XCTAssertTrue(intact.contains("Lovely." + markup("PHOTO-1") + AppleMailHTML.signatureAnchor),
                      intact)
        XCTAssertLessThan(index(of: AppleMailHTML.signatureAnchor, in: intact),
                          index(of: "<blockquote", in: intact))

        var changed = reply
        changed.body += " and more"
        XCTAssertFalse(try XCTUnwrap(changed.quote).isIntact(in: changed.body))
        let made = letter(changed, account(signature: sig))
        let html = try XCTUnwrap(made.html)
        XCTAssertTrue(html.contains("Lovely." + markup("PHOTO-1") + AppleMailHTML.signatureAnchor),
                      html)
        XCTAssertLessThan(index(of: AppleMailHTML.signatureAnchor, in: html),
                          index(of: "<blockquote", in: html))
        XCTAssertEqual(made.files, [])

        var unsigned = Draft.replying(to: original(), all: false, myAddress: "sam@example.com")
        unsigned.body = "Lovely." + unsigned.body
        unsigned.attachments = [photo()]
        let bare = try XCTUnwrap(letter(unsigned, account()).html)
        XCTAssertTrue(bare.contains("Lovely." + markup("PHOTO-1") + "<div dir=\"ltr\"><br><blockquote"),
                      bare)
    }

    /// A forward with the original's PDF and its picture, and a photo he
    /// added: the PDF a file, the original's picture in the quote under its
    /// `bmquote` id, and his photo under his words. Each row in one place.
    func testAForwardsPDFGoesAsAFileAndThePhotoHeAddedInTheLetter() throws {
        var forward = Draft.forwarding(original(), signature: sig)
        forward.body = "For you." + forward.body
        forward.attachments.append(photo())
        let made = letter(forward, account(signature: sig))
        XCTAssertEqual(made.pictures.map(\.picture.filename), ["garden.jpg"])
        XCTAssertTrue(made.pictures.allSatisfy { $0.contentID.hasPrefix("bmquote") })
        XCTAssertEqual(made.bodyPictures.map(\.file), [photo()])
        XCTAssertEqual(made.files.map(\.filename), ["Programme.pdf"])
        let html = try XCTUnwrap(made.html)
        XCTAssertTrue(html.contains("For you." + markup("PHOTO-1") + AppleMailHTML.signatureAnchor),
                      html)
        XCTAssertGreaterThan(index(of: "cid:bmquote", in: html),
                             index(of: "Begin forwarded message:", in: html))
    }

    /// A reply's rows of the original's parts (B-107), photographs among
    /// them, are never his photos in the letter: in the quote, or files,
    /// as before, whether the quote is as it was given or changed.
    func testAReplysCarriedPhotoIsNeverABodyPicture() throws {
        let m = original()
        var reply = Draft.replying(to: m, all: false, myAddress: "sam@example.com", signature: sig)
        reply.attachments = DraftAttachment.carried(from: m)
        XCTAssertTrue(reply.attachments.allSatisfy { !$0.isBodyPicture })
        let intact = letter(reply, account(signature: sig))
        XCTAssertEqual(intact.bodyPictures, [])
        XCTAssertEqual(intact.pictures.map(\.picture.filename), ["garden.jpg"])
        XCTAssertEqual(intact.files.map(\.filename), ["Programme.pdf"])
        XCTAssertFalse(intact.html?.contains("padding:0px 1px 1px 0px") ?? true)

        reply.body += " changed"
        let changed = letter(reply, account(signature: sig))
        XCTAssertEqual(changed.bodyPictures, [])
        XCTAssertEqual(changed.files.map(\.filename), ["garden.jpg", "Programme.pdf"])
    }

    // MARK: - Which rows

    /// A JPEG, PNG or GIF of his own, any letter case; a reopened draft's
    /// part marked as one; nothing else.
    func testOnlyAJPEGPNGOrGIFOfHisOwnIsOne() {
        for type in ["image/jpeg", "image/png", "image/gif", "IMAGE/JPEG", " image/png "] {
            XCTAssertTrue(photo("p", type).isBodyPicture, type)
        }
        for type in ["image/heic", "image/tiff", "video/quicktime", "application/pdf",
                     "application/octet-stream", ""] {
            XCTAssertFalse(photo("p", type).isBodyPicture, type)
        }
        let part = DraftAttachment(source: .messagePart(messageID: "1/2", mailboxID: "INBOX",
                                                        section: "2", letter: 7),
                                   filename: "garden.jpg", mimeType: "image/jpeg", size: 10)
        XCTAssertFalse(part.isBodyPicture, "a part of a letter on the server")
        var marked = part
        marked.inBody = true
        XCTAssertTrue(marked.isBodyPicture, "a reopened draft's, in the letter")
        let pdf = DraftAttachment(source: part.source, filename: "a.pdf",
                                  mimeType: "application/pdf", size: 10, inBody: true)
        XCTAssertFalse(pdf.isBodyPicture)
    }

    /// A plain note with a photo is HTML, as Mail sends it; with a video
    /// or a PDF alone it stays plain text, the file under it.
    func testAPlainNoteWithAPhotoIsHTMLAndWithAFileStaysText() {
        let note = "on my way"
        XCTAssertTrue(AppleMailHTML.isNeeded(body: note, signature: "", signatureHTML: "",
                                             files: [photo()]))
        XCTAssertFalse(AppleMailHTML.isNeeded(body: note, signature: "", signatureHTML: "",
                                              files: [photo("a.MOV", "video/quicktime"),
                                                      photo("a.pdf", "application/pdf")]))
        let video = photo("a.MOV", "video/quicktime")
        let made = letter(Draft(to: ["a@b.com"], body: note, attachments: [video]), account())
        XCTAssertNil(made.html)
        XCTAssertEqual(made.files, [video])
        XCTAssertEqual(made.bodyPictures, [])
    }

    // MARK: - Their Content-IDs

    /// Each letter made gives each photo a fresh uppercase UUID, as his
    /// iPad does, never two alike.
    func testEachLetterGivesItsPhotosFreshUppercaseUUIDs() throws {
        let draft = newLetter(files: [photo("a.jpg"), photo("b.jpg")])
        let one = AppleMailHTML.letter(for: draft, account: account(signature: sig))
        let two = AppleMailHTML.letter(for: draft, account: account(signature: sig))
        let ids = one.bodyPictures.map(\.contentID) + two.bodyPictures.map(\.contentID)
        XCTAssertEqual(ids.count, 4)
        XCTAssertEqual(Set(ids).count, 4)
        let html = (one.html ?? "") + (two.html ?? "")
        for id in ids {
            XCTAssertEqual(UUID(uuidString: id)?.uuidString, id)
            XCTAssertEqual(id, id.uppercased())
            XCTAssertTrue(html.contains("src=\"cid:\(id)\""), id)
        }
    }

    /// None is given one the letter uses already, the signature's or one
    /// given before it.
    func testNoPhotoIsGivenAContentIDTheLetterUsesAlready() {
        let draft = newLetter(files: [photo("a.jpg"), photo("b.jpg")])
        let made = AppleMailHTML.letter(for: draft, account: account(signature: sig),
                                        reserving: ["SAME", "sig-logo"], pictureID: { "SAME" })
        XCTAssertEqual(made.bodyPictures.map(\.contentID), ["SAMEX", "SAMEXX"])
    }

    /// A name with an ampersand, angle brackets and double quotes is the
    /// part's name in the `alt`, escaped, and cannot end the attribute.
    func testItsNameIsWrittenSafelyInTheAlt() throws {
        let made = letter(newLetter(files: [photo("Tom & \"Jerry\" <1>.jpg")]),
                          account(signature: sig))
        let html = try XCTUnwrap(made.html)
        XCTAssertTrue(html.contains("alt=\"Tom &amp; Jerry &lt;1&gt;.jpg\" src=\"cid:PHOTO-1\""), html)
    }

    // MARK: - Reopened from Drafts

    /// The Content-IDs a draft's markup shows among his words: this app's
    /// own, with a signature's logo and a forward's quoted picture; Mail's
    /// on another device; Gmail's, with no signature's line break; none
    /// at all.
    func testTheContentIDsAmongHisWordsAreOnlyHis() throws {
        var forward = Draft.forwarding(original(), signature: sig)
        forward.body = "For you." + forward.body
        forward.attachments.append(photo())
        let ours = try XCTUnwrap(letter(forward, account(signature: sig, html: richSig),
                                        forDraft: true).html)
        XCTAssertTrue(ours.contains("cid:sig-logo"))
        XCTAssertTrue(ours.contains("cid:bmquote"))
        XCTAssertEqual(AppleMailHTML.contentIDsAmongHisWords(in: ours), ["PHOTO-1"])

        let mails = "<html><head></head><body dir=\"auto\">Hi<div><br><br><img id=\"AB12\" "
            + "src=\"cid:AB12\"></div><br id=\"lineBreakAtBeginningOfSignature\"><div>Sam "
            + "<img src=\"cid:logo\"></div><div><br><blockquote type=\"cite\">"
            + "<img src=\"cid:quoted\"></blockquote></div></body></html>"
        XCTAssertEqual(AppleMailHTML.contentIDsAmongHisWords(in: mails), ["AB12"])

        let gmails = "<div dir=\"ltr\">Hi<div><img src=\"cid:ii_mine\" alt=\"a.jpg\"></div></div>"
            + "<div class=\"gmail_quote\"><div class=\"gmail_attr\">On Monday Jane wrote:</div>"
            + "<BLOCKQUOTE class=\"gmail_quote\"><img src=\"cid:ii_hers\"></BLOCKQUOTE></div>"
        XCTAssertEqual(AppleMailHTML.contentIDsAmongHisWords(in: gmails), ["ii_mine"])
        XCTAssertEqual(AppleMailHTML.contentIDsAmongHisWords(in: "<div>no pictures</div>"), [])
    }

    /// A saved draft as `loadMessage` hands it back.
    private func reopened(_ raw: Data) -> Message {
        let decoded = MIMEDecoder.decodeMessage(raw)
        return Message(id: "600003/9", mailboxID: "[Gmail]/Drafts", sender: "Sam Example",
                       senderAddress: "sam@example.com", to: ["carlo@example.org"], cc: [],
                       subject: "The garden", date: date, textBody: decoded.text,
                       htmlBody: decoded.html, attachments: decoded.attachments,
                       gmailMessageID: 1_790_000_000_009)
    }

    /// The draft built as the APPEND builds it (`IMAPMailRepository.append`):
    /// the letter for a draft, its photos and files from `bytes` by name.
    private func savedDraft(_ draft: Draft, _ account: MailAccount,
                            signature images: [(contentID: String, filename: String,
                                                mimeType: String, data: Data)] = [],
                            bytes: [String: Data]) -> Data {
        let made = letter(draft, account, forDraft: true,
                          reserving: Set(images.map(\.contentID)))
        return RFC5322Builder.build(
            draft: draft, from: account, date: date, messageID: messageID,
            attachments: made.files.map { ($0.filename, $0.mimeType, bytes[$0.filename] ?? Data()) },
            includeBcc: true, htmlBody: made.html, inlineImages: images,
            bodyPictures: made.bodyPictures.map {
                ($0.contentID, $0.file.filename, $0.file.mimeType, bytes[$0.file.filename] ?? Data())
            },
            boundaryToken: Counting().next)
    }

    /// A draft saved with two photos, a PDF and the signature's logo,
    /// reopened: each photo's row marked as in the letter, the PDF's not,
    /// the logo no row; built again, the two photos under his words, once
    /// each, and the PDF a file. And again, with nothing gained or lost.
    func testAReopenedDraftsPhotosGoInTheLetterAgainOnceEach() throws {
        let logo = (contentID: "sig-logo", filename: "logo.png", mimeType: "image/png",
                    data: LetterCorpus.bytes(90, seed: 3))
        let bytes = ["a.jpg": LetterCorpus.bytes(700, seed: 1), "b.png": LetterCorpus.bytes(800, seed: 2),
                     "Plans.pdf": LetterCorpus.bytes(500, seed: 4)]
        let account = account(signature: sig, html: richSig)
        var draft = newLetter(files: [photo("a.jpg"), photo("Plans.pdf", "application/pdf"),
                                      photo("b.png", "image/png")])
        let signature = [SignatureImages.InlineImage(contentID: "sig-logo", filename: "logo.png",
                                                     mimeType: "image/png",
                                                     dataBase64: logo.data.base64EncodedString())]
        for round in 1...3 {
            let raw = savedDraft(draft, account, signature: [logo], bytes: bytes)
            let back = Draft.reopening(reopened(raw), signatureImages: signature)
            XCTAssertEqual(back.attachments.map(\.filename), ["a.jpg", "b.png", "Plans.pdf"],
                           "round \(round)")
            XCTAssertEqual(back.attachments.map(\.inBody), [true, true, false], "round \(round)")
            let again = letter(back, account)
            XCTAssertEqual(again.bodyPictures.map(\.file.filename), ["a.jpg", "b.png"])
            XCTAssertEqual(again.files.map(\.filename), ["Plans.pdf"])
            draft = back
        }
    }

    /// A quote's picture in a reopened draft is never marked as his: it is
    /// a row that goes in the quote, with his signature above the quote
    /// and with none, where nothing but the quote comes after his photo.
    func testAReopenedForwardsQuotePictureIsNotMarkedAsHis() throws {
        for signature in [sig, ""] {
            let account = account(signature: signature)
            var forward = Draft.forwarding(original(), signature: signature)
            forward.body = "For you." + forward.body
            forward.attachments.append(photo())
            let bytes = ["garden.jpg": LetterCorpus.bytes(600, seed: 5),
                         "Programme.pdf": LetterCorpus.bytes(22, seed: 6),
                         "IMG_0077.jpg": LetterCorpus.bytes(900, seed: 7)]
            let made = letter(forward, account, forDraft: true)
            // The quote's picture as the APPEND carries it: under its bmquote id.
            let quoted = made.pictures.map {
                ($0.contentID, $0.picture.filename, $0.picture.mimeType,
                 bytes[$0.picture.filename] ?? Data())
            }
            let raw = RFC5322Builder.build(
                draft: forward, from: account, date: date, messageID: messageID,
                attachments: made.files.map { ($0.filename, $0.mimeType, bytes[$0.filename] ?? Data()) },
                includeBcc: true, htmlBody: made.html, inlineImages: quoted,
                bodyPictures: made.bodyPictures.map {
                    ($0.contentID, $0.file.filename, $0.file.mimeType,
                     bytes[$0.file.filename] ?? Data())
                },
                boundaryToken: Counting().next)
            let back = Draft.reopening(reopened(raw), signatureImages: [])
            let label = signature.isEmpty ? "no signature" : "signed"
            XCTAssertEqual(back.attachments.map { "\($0.filename) \($0.inBody)" }.sorted(),
                           ["IMG_0077.jpg true", "Programme.pdf false", "garden.jpg false"], label)
            let again = letter(back, account)
            XCTAssertEqual(again.bodyPictures.map(\.file.filename), ["IMG_0077.jpg"], label)
            XCTAssertEqual(again.pictures.map(\.picture.filename), ["garden.jpg"], label)
            XCTAssertEqual(again.files.map(\.filename), ["Programme.pdf"], label)
        }
    }

    /// A draft begun in Mail on another device, its photo under his words:
    /// reopened, the photo is marked as in the letter. One in its quote is
    /// not.
    func testADraftBegunInMailOnAnotherDeviceKeepsItsPhotoInTheLetter() {
        let html = "<html><head><meta http-equiv=\"content-type\" content=\"text/html; "
            + "charset=utf-8\"></head><body dir=\"auto\">Look<div><br><br><img "
            + "id=\"FDDBA47E-B190-45C4-9A21-56A764FC673D\" style=\"padding:0px 1px 1px 0px;\" "
            + "alt=\"IMG_0077.jpg\" src=\"cid:FDDBA47E-B190-45C4-9A21-56A764FC673D\"></div>"
            + "<br id=\"lineBreakAtBeginningOfSignature\"><div dir=\"ltr\">Sam</div>"
            + "<div dir=\"ltr\"><br><blockquote type=\"cite\"><img src=\"cid:THEIRS\">"
            + "</blockquote></div></body></html>"
        let m = Message(id: "600003/9", mailboxID: "[Gmail]/Drafts", sender: "Sam",
                        senderAddress: "sam@example.com", to: [], cc: [], subject: "",
                        date: date, textBody: "Look\n\nSam", htmlBody: html,
                        attachments: [
                            Attachment(id: "2", filename: "IMG_0077.jpg", mimeType: "image/jpeg",
                                       size: 1_466_290,
                                       contentID: "FDDBA47E-B190-45C4-9A21-56A764FC673D",
                                       isInline: true),
                            Attachment(id: "3", filename: "theirs.jpg", mimeType: "image/jpeg",
                                       size: 10, contentID: "THEIRS", isInline: true),
                        ])
        let back = Draft.reopening(m, signatureImages: [])
        XCTAssertEqual(back.attachments.map(\.inBody), [true, false])
        XCTAssertEqual(back.attachments.map(\.isBodyPicture), [true, false])
    }

    // MARK: - Kept on the iPad

    @MainActor
    private func store() -> LocalDraftStore {
        LocalDraftStore(root: directory.appendingPathComponent("Kept", isDirectory: true))
    }

    /// A reopened draft's photo kept on the iPad, as an autosave or the
    /// Outbox keeps it, comes back marked; the other part, not.
    @MainActor
    func testAKeptLettersMarkIsKept() throws {
        let kept = store()
        var draft = newLetter(files: [])
        let source = DraftAttachment.Source.messagePart(messageID: "600003/9",
                                                        mailboxID: "[Gmail]/Drafts",
                                                        section: "2", letter: 9)
        draft.attachments = [DraftAttachment(source: source, filename: "a.jpg",
                                             mimeType: "image/jpeg", size: 700, inBody: true),
                             DraftAttachment(source: .messagePart(messageID: "600003/9",
                                                                  mailboxID: "[Gmail]/Drafts",
                                                                  section: "3", letter: 9),
                                             filename: "Plans.pdf", mimeType: "application/pdf",
                                             size: 500)]
        try kept.keep(draft, as: "draft-1", unfinished: false, account: "sam@example.com")
        let back = try XCTUnwrap(LocalDraftStore(root: kept.root).letter("draft-1"))
        XCTAssertEqual(back.draft.attachments, draft.attachments)
        XCTAssertEqual(back.draft.attachments.map(\.inBody), [true, false])
        let json = try String(decoding: Data(contentsOf: kept.root
            .appendingPathComponent("draft-1/letter.json")), as: UTF8.self)
        XCTAssertEqual(json.components(separatedBy: "\"inBody\"").count - 1, 1,
                       "written only where it is true")
    }

    /// A letter kept before the mark was, with no `inBody`, reads as
    /// unmarked, and one whose mark cannot be read reads the same: the
    /// letter is read, its file goes under it.
    @MainActor
    func testAnOldRecordReadsUnmarkedAndABadMarkTheSame() throws {
        let kept = store()
        var draft = newLetter(files: [])
        draft.attachments = [DraftAttachment(source: .messagePart(messageID: "600003/9",
                                                                  mailboxID: "[Gmail]/Drafts",
                                                                  section: "2", letter: 9),
                                             filename: "a.jpg", mimeType: "image/jpeg", size: 700,
                                             inBody: true)]
        try kept.keep(draft, as: "draft-1", unfinished: false, account: "sam@example.com")
        let file = kept.root.appendingPathComponent("draft-1/letter.json")
        let original = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        XCTAssertEqual(original.components(separatedBy: "\"inBody\":true").count, 2, original)

        for (label, mark) in [("old", nil), ("a string", "\"yes\""), ("a number", "1"),
                              ("null", "null")] as [(String, String?)] {
            var text = original
            if let mark {
                text = text.replacingOccurrences(of: "\"inBody\":true", with: "\"inBody\":\(mark)")
            } else {
                // As a build before the mark wrote it: no such field.
                for written in ["\"inBody\":true,", ",\"inBody\":true"] {
                    text = text.replacingOccurrences(of: written, with: "")
                }
                XCTAssertFalse(text.contains("inBody"), text)
            }
            try Data(text.utf8).write(to: file)
            let back = try XCTUnwrap(LocalDraftStore(root: kept.root).letter("draft-1"), label)
            XCTAssertEqual(back.draft.attachments.map(\.filename), ["a.jpg"], label)
            XCTAssertEqual(back.draft.attachments.map(\.inBody), [false], label)
        }
    }

    // MARK: - As parts of the letter

    private func photoPlan(html: String? = "<div>x</div>",
                           inlineFiles: [(contentID: String, filename: String, mimeType: String)],
                           files: [(filename: String, mimeType: String)] = [],
                           inline: [(contentID: String, filename: String, mimeType: String,
                                     data: Data)] = [],
                           token: Counting = Counting()) -> LetterPlan {
        RFC5322Builder.plan(draft: LetterCorpus.draft("The garden."), from: LetterCorpus.account,
                            date: LetterCorpus.date, messageID: LetterCorpus.messageID,
                            files: files, htmlBody: html, inlineImages: inline,
                            inlineFiles: inlineFiles, boundaryToken: token.next)
    }

    private func places(_ plan: LetterPlan) -> [Int] {
        plan.pieces.compactMap { piece in
            if case let .file(index) = piece { return index }
            return nil
        }
    }

    /// Each photo is a place for its file's base64 inside the related set,
    /// before the signature's picture, with its Content-ID, `inline` and
    /// its name; numbered first, the files after it; and no copy of it as
    /// an attachment.
    func testEachPhotoIsAFilesPlaceInsideTheRelatedSetWithItsHeaders() throws {
        let photo = LetterCorpus.bytes(2_000, seed: 9)
        let pdf = LetterCorpus.bytes(300, seed: 8)
        let plan = photoPlan(inlineFiles: [("PHOTO-1", "IMG_0077.jpg", "image/jpeg")],
                             files: [("Plans.pdf", "application/pdf")], inline: [LetterCorpus.logo])
        XCTAssertEqual(places(plan), [0, 1], "the photo's place, then the file's")
        let raw = plan.rendered(from: [photo, pdf])
        let text = String(decoding: raw, as: UTF8.self)
        let related = "=_Blackmail_" + String(repeating: "0", count: 31) + "2_="
        XCTAssertTrue(text.contains("--\(related)\r\n"
                                    + "Content-Type: image/jpeg; name=\"IMG_0077.jpg\"\r\n"
                                    + "Content-Transfer-Encoding: base64\r\n"
                                    + "Content-ID: <PHOTO-1>\r\n"
                                    + "Content-Disposition: inline; filename=\"IMG_0077.jpg\"\r\n\r\n"
                                    + RFC5322Builder.base64Wrapped(photo) + "\r\n--\(related)\r\n"
                                    + "Content-Type: image/png; name=\"logo.png\""), text)
        XCTAssertFalse(text.contains("attachment; filename=\"IMG_0077.jpg\""))
        XCTAssertTrue(text.contains("Content-Disposition: attachment; filename=\"Plans.pdf\""))

        let parsed = MIMEDecoder.parse(raw)
        XCTAssertEqual(parsed.structure.mimeType, "multipart/mixed")
        let inside = try XCTUnwrap(parsed.structure.children.first)
        XCTAssertEqual(inside.mimeType, "multipart/related")
        XCTAssertEqual(inside.children.map(\.mimeType),
                       ["multipart/alternative", "image/jpeg", "image/png"])
        guard inside.children.count == 3 else { return }
        XCTAssertEqual(inside.children[1].disposition, "inline")
        XCTAssertEqual(MIMEDecoder.strippedContentID(inside.children[1].id), "PHOTO-1")
        XCTAssertEqual(MIMEDecoder.decodeTransfer(parsed.bodies[inside.children[1].section] ?? Data(),
                                                  encoding: "base64"), photo)

        // A photo alone, with no file: the related set is the message.
        let alone = photoPlan(inlineFiles: [("PHOTO-1", "IMG_0077.jpg", "image/jpeg")])
        XCTAssertEqual(places(alone), [0])
        XCTAssertEqual(MIMEDecoder.parse(alone.rendered(from: [photo])).structure.mimeType,
                       "multipart/related")
    }

    /// A name past ASCII is written as a file's is, in encoded words, not
    /// as raw bytes in a header.
    func testANamePastASCIIIsWrittenAsAFilesIs() {
        let raw = photoPlan(inlineFiles: [("PHOTO-1", "Caf\u{E9}.jpg", "image/jpeg")])
            .rendered(from: [Data([1, 2, 3])])
        let text = String(decoding: raw, as: UTF8.self)
        let encoded = RFC5322Builder.encodeIfNeeded("Caf\u{E9}.jpg")
        XCTAssertTrue(text.contains("Content-Type: image/jpeg; name=\"\(encoded)\""), text)
        XCTAssertTrue(text.contains("inline; filename=\"\(encoded)\""), text)
        XCTAssertFalse(raw.contains(where: { $0 > 0x7E }), "nothing past ASCII on the wire")
    }

    /// With no markup to show them in, the photos go as files under the
    /// letter, numbered first all the same: never left behind.
    func testWithNoMarkupThePhotosGoAsFilesAndAreNeverLeftBehind() throws {
        let photo = LetterCorpus.bytes(1_000, seed: 3)
        let plan = photoPlan(html: nil, inlineFiles: [("PHOTO-1", "IMG_0077.jpg", "image/jpeg")],
                             files: [("Plans.pdf", "application/pdf")])
        XCTAssertEqual(places(plan), [0, 1])
        let raw = plan.rendered(from: [photo, Data([9])])
        let decoded = MIMEDecoder.decodeMessage(raw)
        XCTAssertEqual(decoded.attachments.map(\.filename), ["IMG_0077.jpg", "Plans.pdf"])
        XCTAssertEqual(decoded.attachments.map(\.isInline), [false, false])
        XCTAssertTrue(String(decoding: raw, as: UTF8.self).contains(RFC5322Builder.base64Wrapped(photo)))
    }

    /// The planned letter with its photos is the one made whole from their
    /// bytes, the one streamed from the disk, and the reference builder's
    /// with each photo as a picture held in memory, to the byte, with as
    /// many boundary draws; every size about a line's, a block's and a
    /// piece's edge, alone, with the logo, with files, several at once,
    /// with Bcc and threading.
    func testThePlanWithItsPhotosIsTheInMemoryBuildToTheByte() throws {
        var cases: [(label: String, photos: [(contentID: String, filename: String, mimeType: String,
                                              data: Data)],
                     files: [(filename: String, mimeType: String, data: Data)],
                     logo: Bool, bcc: Bool, thread: Bool)] = []
        for size in LetterCorpus.sizes {
            cases.append(("size \(size)", [("PHOTO-1", "IMG_0077.jpg", "image/jpeg",
                                            LetterCorpus.bytes(size, seed: size))], [], false, false, false))
        }
        let photos = (1...3).map { n in
            (contentID: "PHOTO-\(n)", filename: "Image-\(n).png", mimeType: "image/png",
             data: LetterCorpus.bytes(57 * 1024 * n + n, seed: n))
        }
        let files = [(filename: "Plans.pdf", mimeType: "application/pdf",
                      data: LetterCorpus.bytes(65_537, seed: 40)),
                     (filename: "IMG_0005.MOV", mimeType: "video/quicktime",
                      data: LetterCorpus.bytes(116_737, seed: 41))]
        cases.append(("one with the logo", [photos[0]], [], true, false, false))
        cases.append(("one with files", [photos[0]], files, false, true, false))
        cases.append(("three, the logo and files", photos, files, true, true, true))
        cases.append(("a name the boundary would be", [("PHOTO-1",
            "=_Blackmail_" + String(repeating: "0", count: 31) + "1_=", "image/jpeg", Data([1]))],
            [], false, false, false))

        let draft = LetterCorpus.draft("The garden.\n.\nLove")
        for c in cases {
            let inline = c.logo ? [LetterCorpus.logo] : []
            let thread: (messageID: String, references: String?)? =
                c.thread ? ("<parent@example.org>", "<root@example.org>") : nil
            let referenceToken = Counting(), builtToken = Counting(), planToken = Counting()
            let reference = ReferenceBuilder.build(
                draft: draft, from: LetterCorpus.account, date: LetterCorpus.date,
                messageID: LetterCorpus.messageID, inReplyToHeaders: thread, attachments: c.files,
                includeBcc: c.bcc, htmlBody: LetterCorpus.markup, inlineImages: c.photos + inline,
                boundaryToken: referenceToken.next)
            let built = RFC5322Builder.build(
                draft: draft, from: LetterCorpus.account, date: LetterCorpus.date,
                messageID: LetterCorpus.messageID, inReplyToHeaders: thread, attachments: c.files,
                includeBcc: c.bcc, htmlBody: LetterCorpus.markup, inlineImages: inline,
                bodyPictures: c.photos, boundaryToken: builtToken.next)
            let plan = RFC5322Builder.plan(
                draft: draft, from: LetterCorpus.account, date: LetterCorpus.date,
                messageID: LetterCorpus.messageID, inReplyToHeaders: thread,
                files: c.files.map { ($0.filename, $0.mimeType) }, includeBcc: c.bcc,
                htmlBody: LetterCorpus.markup, inlineImages: inline,
                inlineFiles: c.photos.map { ($0.contentID, $0.filename, $0.mimeType) },
                boundaryToken: planToken.next)
            XCTAssertEqual(built, reference, "\(c.label): build")
            XCTAssertEqual(builtToken.draws, referenceToken.draws, "\(c.label): draws")
            XCTAssertEqual(planToken.draws, referenceToken.draws, "\(c.label): plan's draws")
            let data = c.photos.map(\.data) + c.files.map(\.data)
            XCTAssertEqual(places(plan), Array(data.indices), "\(c.label): in order")
            XCTAssertEqual(plan.length(sizes: data.map(\.count)), reference.count, c.label)
            XCTAssertEqual(plan.rendered(from: data), reference, "\(c.label): from bytes")

            let sources = try data.enumerated().map { index, bytes -> LetterSource in
                let url = directory.appendingPathComponent("\(UUID().uuidString)-\(index)")
                try bytes.write(to: url)
                return .disk(url, attachedSize: Int64(bytes.count))
            }
            let opened = try LetterFiles(opening: sources)
            var stream = LetterBytes(plan: plan, files: opened)
            var streamed = Data()
            while let chunk = try stream.next() { streamed.append(chunk.bindMemory(to: UInt8.self)) }
            opened.close()
            XCTAssertEqual(streamed, reference, "\(c.label): from the disk")
            XCTAssertEqual(stream.digests.map(\.bytes), data.map(\.count), c.label)
        }
    }

    // MARK: - The letter whole

    /// Letters made as the app makes them, sent or saved: a new one with
    /// three photos and the signature's logo, a reply with one, and a
    /// forward with the original's picture, its PDF and a photo he added.
    /// Every `cid:` the markup shows has exactly one part, every part shown
    /// inline is shown, and no photo's bytes go twice.
    func testEveryCidHasExactlyOnePartAndEveryInlinePartIsShown() throws {
        let account = account(signature: sig, html: richSig)
        let logo = (contentID: "sig-logo", filename: "logo.png", mimeType: "image/png",
                    data: LetterCorpus.bytes(90, seed: 3))
        var bytes: [String: Data] = ["garden.jpg": LetterCorpus.bytes(600, seed: 5),
                                     "Programme.pdf": LetterCorpus.bytes(22, seed: 6)]
        for n in 1...3 { bytes["IMG_000\(n).jpg"] = LetterCorpus.bytes(500 + n, seed: 20 + n) }
        let fresh = newLetter(files: (1...3).map { photo("IMG_000\($0).jpg") })
        var reply = Draft.replying(to: original(), all: false, myAddress: "sam@example.com",
                                   signature: sig)
        reply.attachments = [photo("IMG_0001.jpg")]
        var forward = Draft.forwarding(original(), signature: sig)
        forward.attachments.append(photo("IMG_0002.jpg"))

        for (label, draft) in [("new", fresh), ("reply", reply), ("forward", forward)] {
            for forDraft in [false, true] {
                let made = letter(draft, account, forDraft: forDraft, reserving: ["sig-logo"])
                let quoted = made.pictures.map {
                    ($0.contentID, $0.picture.filename, $0.picture.mimeType,
                     bytes[$0.picture.filename] ?? Data())
                }
                let raw = RFC5322Builder.build(
                    draft: draft, from: account, date: date, messageID: messageID,
                    attachments: made.files.map { ($0.filename, $0.mimeType, bytes[$0.filename] ?? Data()) },
                    htmlBody: made.html, inlineImages: [logo] + quoted,
                    bodyPictures: made.bodyPictures.map {
                        ($0.contentID, $0.file.filename, $0.file.mimeType,
                         bytes[$0.file.filename] ?? Data())
                    },
                    boundaryToken: Counting().next)
                let decoded = MIMEDecoder.decodeMessage(raw)
                let html = try XCTUnwrap(decoded.html, label)
                let shown = QuotedMarkup.contentIDs(shownBy: html)
                let inline = decoded.attachments.filter(\.isInline)
                for id in shown {
                    XCTAssertEqual(inline.filter { $0.contentID == id }.count, 1, "\(label): \(id)")
                }
                for part in inline {
                    XCTAssertTrue(shown.contains(part.contentID ?? ""), "\(label): \(part.filename)")
                }
                let parsed = MIMEDecoder.parse(raw)
                let sent = decoded.attachments.map { a in
                    MIMEDecoder.decodeTransfer(parsed.bodies[a.id] ?? Data(), encoding: "base64")
                }
                for n in 1...3 {
                    let wanted = bytes["IMG_000\(n).jpg"]!
                    let copies = sent.filter { $0 == wanted }.count
                    let attached = draft.attachments.contains { $0.filename == "IMG_000\(n).jpg" }
                    XCTAssertEqual(copies, attached ? 1 : 0, "\(label): IMG_000\(n).jpg")
                }
                XCTAssertEqual(decoded.attachments.filter { !$0.isInline }.map(\.filename),
                               made.files.map(\.filename), label)
            }
        }
    }

    /// Python's `email` package, its default policy, reads a letter with
    /// photos, the logo and a file with no defect: the photos and the logo
    /// in the related set with the markup, each `cid:` naming one of its
    /// parts, each part's bytes as they went, the file under the letter.
    /// Skipped where there is no Python.
    func testPythonsEmailPackageReadsItAsItWent() throws {
        guard let python = ["/usr/bin/python3", "/usr/local/bin/python3", "/bin/python3"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("no python3 on this host")
        }
        let account = account(signature: sig, html: richSig)
        let logo = (contentID: "sig-logo", filename: "logo.png", mimeType: "image/png",
                    data: LetterCorpus.bytes(90, seed: 3))
        let bytes = ["IMG_0001.jpg": LetterCorpus.bytes(70_001, seed: 1),
                     "Image-2.png": LetterCorpus.bytes(300, seed: 2),
                     "Plans.pdf": LetterCorpus.bytes(5_000, seed: 4)]
        let draft = newLetter(files: [photo("IMG_0001.jpg"), photo("Plans.pdf", "application/pdf"),
                                      photo("Image-2.png", "image/png")])
        let made = AppleMailHTML.letter(for: draft, account: account, reserving: ["sig-logo"])
        let raw = RFC5322Builder.build(
            draft: draft, from: account, date: date, messageID: messageID,
            attachments: made.files.map { ($0.filename, $0.mimeType, bytes[$0.filename] ?? Data()) },
            htmlBody: made.html, inlineImages: [logo],
            bodyPictures: made.bodyPictures.map {
                ($0.contentID, $0.file.filename, $0.file.mimeType, bytes[$0.file.filename] ?? Data())
            })
        let letterURL = directory.appendingPathComponent("letter.eml")
        try raw.write(to: letterURL)
        let script = directory.appendingPathComponent("read.py")
        try Data("""
            import sys, re, hashlib, email, email.policy
            m = email.message_from_bytes(open(sys.argv[1], 'rb').read(), policy=email.policy.default)
            out = []
            for part in m.walk():
                for d in part.defects:
                    out.append('defect %s' % type(d).__name__)
            related = [p for p in m.walk() if p.get_content_type() == 'multipart/related']
            out.append('related %d' % len(related))
            html = m.get_body(('html',)).get_content()
            shown = sorted(set(re.findall(r'src="cid:([^"]+)"', html)))
            out.append('shown ' + ' '.join(shown))
            for p in related[0].iter_parts():
                if p.get_content_maintype() == 'image':
                    out.append('in %s %s %s %s' % (p['Content-ID'].strip('<>'), p.get_content_disposition(),
                               p.get_filename(), hashlib.sha256(p.get_content()).hexdigest()))
            for p in m.iter_attachments():
                if p.get_content_disposition() == 'attachment':
                    out.append('file %s %s' % (p.get_filename(), hashlib.sha256(p.get_content()).hexdigest()))
            print('\\n'.join(out))
            """.utf8).write(to: script)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [script.path, letterURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, output)
        let lines = output.split(separator: "\n").map(String.init)

        func sha(_ data: Data) throws -> String {
            let hasher = Process()
            hasher.executableURL = URL(fileURLWithPath: python)
            hasher.arguments = ["-c", "import sys, hashlib; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())"]
            let input = Pipe(), output = Pipe()
            hasher.standardInput = input
            hasher.standardOutput = output
            try hasher.run()
            input.fileHandleForWriting.write(data)
            try input.fileHandleForWriting.close()
            let digest = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            hasher.waitUntilExit()
            return digest.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let ids = made.bodyPictures.map(\.contentID)
        guard ids.count == 2 else { return XCTFail("two photos in the letter, not \(ids.count)") }
        XCTAssertFalse(lines.contains { $0.hasPrefix("defect") }, output)
        XCTAssertTrue(lines.contains("related 1"), output)
        XCTAssertTrue(lines.contains("shown " + (ids + ["sig-logo"]).sorted().joined(separator: " ")),
                      output)
        XCTAssertTrue(lines.contains("in \(ids[0]) inline IMG_0001.jpg \(try sha(bytes["IMG_0001.jpg"]!))"),
                      output)
        XCTAssertTrue(lines.contains("in \(ids[1]) inline Image-2.png \(try sha(bytes["Image-2.png"]!))"),
                      output)
        XCTAssertTrue(lines.contains("in sig-logo inline logo.png \(try sha(logo.data))"), output)
        XCTAssertEqual(lines.filter { $0.hasPrefix("file ") },
                       ["file Plans.pdf \(try sha(bytes["Plans.pdf"]!))"], output)
    }

    // MARK: - Sent as it goes

    /// Sent through `Submission`, the photo handed over after the file:
    /// read, checked and logged first all the same, as the plan numbers
    /// it, its line saying it is in the body; the rehearsal counts it; and
    /// the letter that arrives is the in-memory build's.
    func testTheRehearsalCountsThePhotoAndTheLogSaysItIsInTheBody() async throws {
        let photo = LetterCorpus.bytes(120_001, seed: 11)
        let pdf = LetterCorpus.bytes(3_000, seed: 12)
        let photoURL = directory.appendingPathComponent("IMG_0077.jpg")
        let pdfURL = directory.appendingPathComponent("Plans.pdf")
        try photo.write(to: photoURL)
        try pdf.write(to: pdfURL)
        let account = account(signature: sig, html: richSig)
        let draft = newLetter(files: [])
        let html = "<div>The garden.</div>" + markup("PHOTO-1") + "<img src=\"cid:sig-logo\">"
        let logo = (contentID: "sig-logo", filename: "logo.png", mimeType: "image/png",
                    data: LetterCorpus.bytes(90, seed: 3))
        let server = ScriptedSubmission()
        let counted = Counted()
        try await Submission.send(
            draft, from: account, password: "app-password",
            through: SMTPClient(account: account, transport: { _, _ in server }),
            threadHeaders: nil,
            attachments: {
                [("Plans.pdf", "application/pdf", .disk(pdfURL, attachedSize: Int64(pdf.count)), .file),
                 ("IMG_0077.jpg", "image/jpeg", .disk(photoURL, attachedSize: Int64(photo.count)),
                  .inBody(contentID: "PHOTO-1"))]
            },
            htmlBody: html, inlineImages: [logo], messageID: messageID,
            rehearsed: { counted.set($0.files.map(\.bytes)) },
            progress: nil, date: date, boundaryToken: Counting().next)

        XCTAssertEqual(counted.value, [photo.count, pdf.count])
        let lines = Diagnostics.entries.map(\.text)
        let plan = lines.first { $0.hasPrefix("LETTER-PLAN") } ?? ""
        XCTAssertTrue(plan.hasPrefix("LETTER-PLAN files=2 file-bytes=\(photo.count + pdf.count) "), plan)
        XCTAssertTrue(plan.hasSuffix(" in-body=1"), plan)
        var photoCRC = CRC32(), pdfCRC = CRC32()
        photoCRC.update(photo)
        pdfCRC.update(pdf)
        XCTAssertEqual(lines.filter { $0.hasPrefix("LETTER-FILE") },
                       ["LETTER-FILE 1 bytes=\(photo.count) crc=\(CRC32.hex(photoCRC.value)) in-body",
                        "LETTER-FILE 2 bytes=\(pdf.count) crc=\(CRC32.hex(pdfCRC.value))"])

        let expected = RFC5322Builder.build(
            draft: draft, from: account, date: date, messageID: messageID,
            attachments: [("Plans.pdf", "application/pdf", pdf)], htmlBody: html,
            inlineImages: [logo], bodyPictures: [("PHOTO-1", "IMG_0077.jpg", "image/jpeg", photo)],
            boundaryToken: Counting().next)
        let letters = await server.letters
        XCTAssertEqual(letters.first, expected)
        for _ in 0..<1_000 {
            if await server.isClosed && FileManager.default.fileExists(atPath: transcript("ok")) { break }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    /// What the rehearsal counted, heard from another thread.
    private final class Counted: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [Int] = []
        func set(_ value: [Int]) { lock.lock(); counts = value; lock.unlock() }
        var value: [Int] { lock.lock(); defer { lock.unlock() }; return counts }
    }

    // MARK: - The share sheet

    /// A shared photo goes where the app puts one: under the words and
    /// above the signature; with a link, the link made one in his words and
    /// the photo's markup left as it is; a PDF beside it a file.
    func testASharedPhotoGoesWhereTheAppPutsOne() throws {
        let account = account(signature: sig)
        let staged = SharedItem.file(URL(fileURLWithPath: "/staged/0/IMG_0776.JPG"),
                                     filename: "IMG_0776.JPG", mimeType: "image/jpeg", size: 900)
        let pdf = SharedItem.file(URL(fileURLWithPath: "/staged/1/Plans.pdf"),
                                  filename: "Plans.pdf", mimeType: "application/pdf", size: 90)
        let alone = ShareLetter.draft(from: [staged], signature: sig)
        let ids = IDs()
        let made = ShareLetter.letter(for: alone, account: account, pictureID: ids.next)
        XCTAssertEqual(made.bodyPictures.map(\.file.filename), ["IMG_0776.JPG"])
        XCTAssertEqual(made.files, [])
        XCTAssertTrue(try XCTUnwrap(made.html).hasPrefix(AppleMailHTML.documentOpen
            + markup("PHOTO-1", "IMG_0776.JPG") + AppleMailHTML.signatureAnchor))

        let page = URL(string: "https://en.wikipedia.org/wiki/Mercury_(planet)")!
        let linked = ShareLetter.draft(from: [.link(page, title: "Mercury"), staged, pdf],
                                       signature: sig)
        let both = ShareLetter.letter(for: linked, account: account, pictureID: IDs().next)
        let html = try XCTUnwrap(both.html)
        XCTAssertTrue(html.contains("<a href=\"\(page.absoluteString)\">\(page.absoluteString)</a>"
                                    + markup("PHOTO-1", "IMG_0776.JPG")
                                    + AppleMailHTML.signatureAnchor), html)
        XCTAssertEqual(both.files.map(\.filename), ["Plans.pdf"])
        let twin = try XCTUnwrap(ShareLetter.html(for: linked, account: account))
        XCTAssertEqual(twin.components(separatedBy: "padding:0px 1px 1px 0px").count, 2,
                       "the twin the sheet has always asked for, with its photo")
        XCTAssertTrue(twin.contains("<a href=\"\(page.absoluteString)\">"))
    }
}
