import XCTest
@testable import Blackmail

/// Markup and Reply on a picture held in a letter (B-171). Mail's menu for
/// a file of the letter's has it second, after Quick Look (an iPhone on
/// iOS 16; MobileMailUI's `MARKUP_DOCUMENT` on iOS 18.6); B-150 built the
/// menu without it. Now the item opens the picture in Quick Look with its
/// Markup, a copy made of what he draws, and as Quick Look closes the app's
/// own Reply to the letter opens with the copy in it, under his words, as a
/// photo he adds goes (B-109); nothing drawn, nothing made.
///
/// Where the marking up stands, the copy's name and kind, its staging and
/// the reply's parts are run here (`MarkupReply`, `Draft.replying`,
/// `AppleMailHTML.letter`); the pane and the composer, UIKit, are read from
/// their source. Nothing is sent anywhere.
final class MarkupReplyTests: XCTestCase {

    private let sig = "Sam Example\n555-555-0142"
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkupReplyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        super.tearDown()
    }

    /// A copy as the pane stages one, at a path of its own.
    private func copy(_ n: Int) -> DraftAttachment {
        DraftAttachment(source: .localFile(URL(fileURLWithPath: "/staged/\(n)/IMG_0412.jpeg")),
                        filename: "IMG_0412.jpeg", mimeType: "image/jpeg", size: Int64(1_000 + n))
    }

    private let kinds = ["jpeg": "image/jpeg", "jpg": "image/jpeg", "png": "image/png", "gif": "image/gif",
                         "heic": "image/heic", "tiff": "image/tiff"]

    private var lookup: (String) -> String? { { [kinds] in kinds[$0.lowercased()] } }

    /// Jane's letter to him, her photograph shown in its body by `cid:`.
    private func original() -> Message {
        Message(id: "600001/41", mailboxID: "INBOX", sender: "Jane Example <jane@example.com>",
                senderAddress: "jane@example.com", to: ["Sam Example <sam@example.com>"],
                cc: ["Pat Example <pat@example.com>"], subject: "The garden", date: date,
                textBody: "Here is the garden.",
                htmlBody: "<div>Here is the garden.</div><div><img src=\"cid:ii_garden01\"></div>",
                attachments: [Attachment(id: "2", filename: "IMG_0412.jpeg", mimeType: "image/jpeg",
                                         size: 2_400_000, contentID: "ii_garden01", isInline: true)],
                messageID: "<garden-1@example.com>", gmailMessageID: 1_790_000_000_041)
    }

    // MARK: - The menu

    /// Mail's words, second in Mail's order, and it puts Quick Look over
    /// the pane.
    func testTheMenuHasMarkupAndReplySecondInMailsWords() {
        XCTAssertEqual(PanePictures.menu.map(\.title),
                       ["Quick Look", "Markup and Reply", "Save Image", "Save to Files", "Share", "Copy"])
        XCTAssertEqual(PanePictures.Item.markupAndReply.title, "Markup and Reply")
        XCTAssertTrue(PanePictures.Item.markupAndReply.presents)
    }

    /// Markup and Reply on every picture of the letter's own held: one
    /// shown by `cid:`, a picture file drawn at its size in the body
    /// (B-170), and a picture drawn as a tile, a TIFF; and on a PDF held,
    /// second, as Mail's menu has it (B-176); never on any other file,
    /// whose menu is B-150's as B-170 gives it. A picture from the web
    /// keeps WebKit's menu: the pane's script wires none. Integration,
    /// int19.
    func testMarkupAndReplyIsOnEveryPictureOfTheLettersOwn() throws {
        func menu(_ kind: String) -> [PanePictures.Item] {
            PanePictures.menu(for: Attachment(id: "3", filename: "a", mimeType: kind, size: 1))
        }
        XCTAssertEqual(Array(menu("image/heic").prefix(2)), [.quickLook, .markupAndReply])
        XCTAssertEqual(Array(menu("image/tiff").prefix(2)), [.quickLook, .markupAndReply])
        XCTAssertEqual(menu("application/pdf"), [.quickLook, .markupAndReply, .saveToFiles, .share, .copy])
        XCTAssertFalse(menu("text/calendar").contains(.markupAndReply))

        let photo = Attachment(id: "2", filename: "roses.jpg", mimeType: "image/jpeg", size: 200_000)
        let m = Message(id: "7/3", mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                        senderAddress: "sam@example.com", to: [], cc: [], subject: "Roses",
                        date: Date(timeIntervalSince1970: 1_790_000_000), textBody: "Look.", htmlBody: nil,
                        attachments: [photo])
        let drawn = try XCTUnwrap(PanePage.letter(m, style: PanePage.Style(inset: 26, bodyPointSize: 17,
                                                                           lineHeight: 1.41)))
        let src = InlineImageRewriter.scheme + "://"
            + InlineImageRewriter.escapedHost(BodyFiles.pictureID("2", of: m.id))
        XCTAssertTrue(drawn.contains("<img src=\"" + src + "\""), drawn)
        let held = try XCTUnwrap(PanePictures.Tap(["src": src, "section": "", "width": 640, "height": 480,
                                                   "drawnWidth": 640, "drawnHeight": 480, "hold": true,
                                                   "x": 10, "y": 10] as [String: Any]))
        let opening = try XCTUnwrap(PanePictures.opening(held, inStack: false, alone: m, stack: [:],
                                                         his: { _ in nil }))
        XCTAssertEqual(opening.part, photo)
        let pane = try source("Sources/Blackmail/UI/MessageDetailViewController.swift")
        XCTAssertTrue(pane.contains("hold(PanePictures.menu, opening.part, of: opening.letter, x: tap.x, y: tap.y)"))
        XCTAssertTrue(pane.contains("hold(PanePictures.menu(for: file), file, of: m, x: held.x, y: held.y)"))
    }

    // MARK: - Where the marking up stands

    /// Two Quick Looks, as the pane's `ObjectIdentifier`s of them, alive
    /// while the test runs so that neither's can be the other's.
    private let quickLooks = (NSObject(), NSObject())
    private var first: ObjectIdentifier { ObjectIdentifier(quickLooks.0) }
    private var second: ObjectIdentifier { ObjectIdentifier(quickLooks.1) }

    /// Each copy Quick Look saves while it is up replaces the one before,
    /// which is let go; as it closes, the last is the reply's, once. A copy
    /// after that, with nothing under way, is let go and makes nothing.
    func testTheLastCopySavedGoesInTheReplyAsQuickLookCloses() {
        var markup = MarkupReply()
        XCTAssertFalse(markup.isBusy(at: date))
        XCTAssertNil(markup.begin(first))
        XCTAssertTrue(markup.isBusy(at: date))
        var saved = markup.saved(copy(1), from: first, at: date)
        XCTAssertNil(saved.reply)
        XCTAssertNil(saved.unused)
        saved = markup.saved(copy(2), from: first, at: date + 1)
        XCTAssertNil(saved.reply)
        XCTAssertEqual(saved.unused, copy(1), "the copy before is let go")
        XCTAssertEqual(markup.closed(first, at: date + 2), copy(2))
        XCTAssertEqual(markup.state, .replying(since: date + 2))
        markup.ended()
        XCTAssertEqual(markup.state, .idle)
        XCTAssertFalse(markup.isBusy(at: date + 2))
        XCTAssertNil(markup.closed(first, at: date + 3), "once")
        saved = markup.saved(copy(3), from: first, at: date + 3)
        XCTAssertNil(saved.reply)
        XCTAssertEqual(saved.unused, copy(3))
    }

    /// Quick Look closed with nothing drawn: nothing made, and back at the
    /// letter. A copy that comes within `late` of it still makes the reply,
    /// and one after it is let go; the pane counts as opening a file until
    /// then. A second picture opened for Markup ends the first, its copy
    /// let go.
    func testNothingDrawnMakesNothingAndALateCopyStillMakesTheReply() {
        var markup = MarkupReply()
        _ = markup.begin(first)
        XCTAssertNil(markup.closed(first, at: date))
        XCTAssertEqual(markup.state, .closed(preview: first, since: date))
        XCTAssertTrue(markup.isBusy(at: date + MarkupReply.late))
        XCTAssertFalse(markup.isBusy(at: date + MarkupReply.late + 1))
        let late = markup.saved(copy(1), from: first, at: date + 2)
        XCTAssertEqual(late.reply, copy(1))
        XCTAssertNil(late.unused)
        XCTAssertEqual(markup.state, .replying(since: date + 2))
        markup.ended()
        XCTAssertEqual(markup.state, .idle)

        _ = markup.begin(first)
        XCTAssertNil(markup.closed(first, at: date))
        let tooLate = markup.saved(copy(2), from: first, at: date + MarkupReply.late + 1)
        XCTAssertNil(tooLate.reply)
        XCTAssertEqual(tooLate.unused, copy(2))

        _ = markup.begin(first)
        _ = markup.saved(copy(3), from: first, at: date)
        XCTAssertEqual(markup.begin(second), copy(3), "a second picture opened lets the first's copy go")
        XCTAssertEqual(markup.state, .marking(preview: second, nil))
        XCTAssertNil(markup.closed(second, at: date + 1))
    }

    /// The copy handed to the reply, the pane counts as opening a file
    /// until the reply's composer has opened or the copy has been let go
    /// (`ended`), while Quick Look may still be over it, and not after: so
    /// the warning before the app stops opening cannot come up in between
    /// and keep the reply off the screen. Never longer than `late`, should
    /// the word never come. A picture opened for Markup since is left as
    /// it is by the word.
    func testThePaneIsBusyUntilTheReplyHasOpened() {
        var markup = MarkupReply()
        _ = markup.begin(first)
        _ = markup.saved(copy(1), from: first, at: date)
        XCTAssertEqual(markup.closed(first, at: date), copy(1))
        XCTAssertTrue(markup.isBusy(at: date + 1), "Quick Look still going from over the pane")
        XCTAssertTrue(markup.isBusy(at: date + MarkupReply.late))
        XCTAssertFalse(markup.isBusy(at: date + MarkupReply.late + 1), "not for ever")
        XCTAssertNil(markup.closed(first, at: date + 1))
        XCTAssertEqual(markup.saved(copy(2), from: first, at: date + 1).unused, copy(2),
                       "a copy after the reply's is let go")
        markup.ended()
        XCTAssertFalse(markup.isBusy(at: date + 1))

        _ = markup.begin(first)
        XCTAssertNil(markup.closed(first, at: date))
        XCTAssertEqual(markup.saved(copy(3), from: first, at: date + 1).reply, copy(3))
        XCTAssertTrue(markup.isBusy(at: date + 2), "a late copy's reply too")
        markup.ended()
        XCTAssertFalse(markup.isBusy(at: date + 2))

        _ = markup.begin(second)
        markup.ended()
        XCTAssertEqual(markup.state, .marking(preview: second, nil), "a picture opened since is left")
    }

    /// What another Quick Look than the one the picture was last opened in
    /// hands over is let go, and what it says changes nothing: the first
    /// closed with nothing drawn and the second opened, the first's copy
    /// coming late is not taken for the second's, named after its picture
    /// and put in a reply to its letter. The second's own still is.
    func testACopyFromAnotherQuickLookIsLetGo() {
        var markup = MarkupReply()
        _ = markup.begin(first)
        XCTAssertNil(markup.closed(first, at: date))
        _ = markup.begin(second)
        var saved = markup.saved(copy(1), from: first, at: date + 1)
        XCTAssertNil(saved.reply)
        XCTAssertEqual(saved.unused, copy(1))
        XCTAssertEqual(markup.state, .marking(preview: second, nil))
        XCTAssertNil(markup.closed(first, at: date + 1))
        XCTAssertEqual(markup.state, .marking(preview: second, nil))

        saved = markup.saved(copy(2), from: second, at: date + 2)
        XCTAssertNil(saved.unused)
        XCTAssertNil(markup.closed(first, at: date + 2), "another's closing hands nothing over")
        XCTAssertEqual(markup.state, .marking(preview: second, copy(2)))
        XCTAssertEqual(markup.closed(second, at: date + 3), copy(2))

        _ = markup.begin(second)
        XCTAssertNil(markup.closed(second, at: date))
        saved = markup.saved(copy(3), from: first, at: date + 1)
        XCTAssertNil(saved.reply, "closed with none: another's copy is still not the reply's")
        XCTAssertEqual(saved.unused, copy(3))
        XCTAssertEqual(markup.state, .closed(preview: second, since: date))
    }

    /// Markup is the preview's a file was last opened in for it, while it
    /// is up, and no other's (`marks`, which the pane's delegate answers
    /// by): a Quick Look of a picture or a PDF tapped, or Markup and
    /// Reply's (B-176), begun as each opens; an earlier one, or one of a
    /// file Quick Look marks nothing on, never begun, has none.
    func testOnlyThePreviewOpenedForMarkupHasMarkup() {
        var markup = MarkupReply()
        XCTAssertFalse(markup.marks(in: first), "none under way")
        _ = markup.begin(first)
        XCTAssertTrue(markup.marks(in: first))
        XCTAssertFalse(markup.marks(in: second), "a preview never begun")
        _ = markup.saved(copy(1), from: first, at: date)
        XCTAssertTrue(markup.marks(in: first), "a copy saved, still up")
        XCTAssertEqual(markup.closed(first, at: date + 1), copy(1))
        XCTAssertFalse(markup.marks(in: first), "closed, replying")
        markup.ended()
        XCTAssertFalse(markup.marks(in: first))
        _ = markup.begin(second)
        XCTAssertNil(markup.closed(second, at: date + 2))
        XCTAssertFalse(markup.marks(in: second), "closed with nothing drawn")
        XCTAssertFalse(markup.marks(in: first))
    }

    // MARK: - The copy

    /// The picture's own name, with the extension of the copy Quick Look
    /// saved, and the kind that names: a JPEG, PNG or GIF as it came; any
    /// other kind made a JPEG of, under the same name ending ".jpg". A copy
    /// with no extension keeps the picture's name and kind, and a name a
    /// stranger chose is made safe.
    func testTheCopysNameAndKind() {
        func made(_ name: String, _ type: String = "image/jpeg", copy: String) -> MarkupReply.Picture {
            MarkupReply.picture(original: name, originalType: type,
                                copy: URL(fileURLWithPath: "/private/var/tmp/QuickLook/" + copy),
                                lookup: lookup)
        }
        XCTAssertEqual(made("IMG_0412.jpeg", copy: "IMG_0412.jpeg"),
                       .init(name: "IMG_0412.jpeg", mimeType: "image/jpeg", jpegName: nil))
        XCTAssertEqual(made("IMG_0412.jpeg", copy: "Markup.png"),
                       .init(name: "IMG_0412.png", mimeType: "image/png", jpegName: nil))
        XCTAssertEqual(made("logo.gif", "image/gif", copy: "logo.GIF"),
                       .init(name: "logo.GIF", mimeType: "image/gif", jpegName: nil))
        XCTAssertEqual(made("IMG_0412.HEIC", "image/heic", copy: "IMG_0412.heic"),
                       .init(name: "IMG_0412.heic", mimeType: "image/heic", jpegName: "IMG_0412.jpg"))
        XCTAssertEqual(made("scan.tiff", "image/tiff", copy: "scan.tiff"),
                       .init(name: "scan.tiff", mimeType: "image/tiff", jpegName: "scan.jpg"))
        XCTAssertEqual(made("IMG_0412.jpeg", copy: "edited"),
                       .init(name: "IMG_0412.jpeg", mimeType: "image/jpeg", jpegName: nil))
        XCTAssertEqual(made("photo", "image/png", copy: "photo"),
                       .init(name: "photo", mimeType: "image/png", jpegName: nil),
                       "no extension anywhere: the picture's own kind")
        XCTAssertEqual(made("../../Library/x.jpg", copy: "x.jpg").name, "x.jpg")
        XCTAssertEqual(made("a:b.png", "image/png", copy: "a.png").name, "ab.png")
    }

    /// The copy staged where the composer's photos are, a directory of its
    /// own in `tmp/Attachments`, byte for byte, with its size: a row of his
    /// that goes in the letter under his words. A HEIC is staged as the
    /// JPEG made of it; one no JPEG can be made of goes as it came, a file.
    /// A copy let go takes its directory with it; a file that was not
    /// staged is never touched.
    func testTheCopyIsStagedAndAJPEGMadeWhereItIsNoPictureALetterShows() throws {
        let saved = directory.appendingPathComponent("IMG_0412.jpeg")
        try Data("marked up".utf8).write(to: saved)
        let jpeg = MarkupReply.picture(original: "IMG_0412.jpeg", originalType: "image/jpeg", copy: saved,
                                       lookup: lookup)
        let row = try MarkupReply.stage(saved, as: jpeg, jpeg: { _ in
            XCTFail("a JPEG is not made again")
            return nil
        })
        guard case let .localFile(url) = row.source else { return XCTFail("\(row.source)") }
        XCTAssertNotNil(AttachmentStore.stagingDirectory(of: url))
        XCTAssertEqual(url.lastPathComponent, "IMG_0412.jpeg")
        XCTAssertEqual(try Data(contentsOf: url), Data("marked up".utf8))
        XCTAssertEqual(row.filename, "IMG_0412.jpeg")
        XCTAssertEqual(row.mimeType, "image/jpeg")
        XCTAssertEqual(row.size, 9)
        XCTAssertTrue(row.isBodyPicture)
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path), "Quick Look's own file is left to it")
        MarkupReply.letGo(row)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))

        let heic = directory.appendingPathComponent("IMG_0412.heic")
        try Data("heic".utf8).write(to: heic)
        let picture = MarkupReply.picture(original: "IMG_0412.HEIC", originalType: "image/heic", copy: heic,
                                          lookup: lookup)
        var read: URL?
        let made = try MarkupReply.stage(heic, as: picture, jpeg: { read = $0; return Data("jpeg".utf8) })
        XCTAssertEqual(read, heic)
        guard case let .localFile(madeURL) = made.source else { return XCTFail("\(made.source)") }
        XCTAssertEqual(try Data(contentsOf: madeURL), Data("jpeg".utf8))
        XCTAssertEqual(made.filename, "IMG_0412.jpg")
        XCTAssertEqual(made.mimeType, "image/jpeg")
        XCTAssertTrue(made.isBodyPicture)
        MarkupReply.letGo(made)

        let unread = try MarkupReply.stage(heic, as: picture, jpeg: { _ in nil })
        XCTAssertEqual(unread.filename, "IMG_0412.heic")
        XCTAssertEqual(unread.mimeType, "image/heic")
        XCTAssertFalse(unread.isBodyPicture, "a file under the letter")
        MarkupReply.letGo(unread)

        MarkupReply.letGo(DraftAttachment(source: .localFile(saved), filename: "IMG_0412.jpeg",
                                          mimeType: "image/jpeg", size: 9))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path), "not staged: left")
        MarkupReply.letGo(nil)
    }

    // MARK: - A file tapped, a PDF held (B-176)

    /// Quick Look of a picture or a PDF has Markup, tapped or held, as
    /// Mail's tapped Quick Look had its Markup button on the test iPad
    /// (round r6-i-compare, C-13b), and what he draws there goes in a Reply
    /// as Markup and Reply's does: a picture of any kind, a PDF by its
    /// kind, with a parameter or in any case, or sent with no kind but its
    /// name. Any other file has none, as before.
    func testATappedPictureOrPDFIsMarkedUp() {
        func file(_ type: String, _ name: String = "a") -> Attachment {
            Attachment(id: "2", filename: name, mimeType: type, size: 1)
        }
        for f in [file("image/jpeg"), file("image/heic"), file("IMAGE/PNG"), file("image/tiff"),
                  file("application/pdf"), file("Application/PDF; name=\"R6 B-170 pdf.pdf\""),
                  file("application/octet-stream", "R6 B-170 pdf.PDF")] {
            XCTAssertTrue(MarkupReply.marksUp(f), f.mimeType)
        }
        for f in [file("application/msword", "a.doc"), file("text/calendar", "a.ics"), file("video/mp4"),
                  file("application/octet-stream", "a.docx"), file("application/zip", "a.pdf.zip"), file("")] {
            XCTAssertFalse(MarkupReply.marksUp(f), f.mimeType + " " + f.filename)
        }
        XCTAssertEqual(PanePictures.pdfMenu.map(\.title),
                       ["Quick Look", "Markup and Reply", "Save to Files", "Share", "Copy"])
        XCTAssertEqual(PanePictures.menu(for: file("application/octet-stream", "scan.pdf")), PanePictures.pdfMenu)
        XCTAssertEqual(PanePictures.menu(for: file("application/msword", "a.doc")), PanePictures.fileMenu)
    }

    /// A PDF marked up goes in the reply as it came from Quick Look, a PDF
    /// under its own name and kind, a file of the letter: no JPEG is made
    /// of it, as one is of a HEIC. Its row is no picture of the letter's,
    /// so it goes as a file, and her own PDF is not sent back.
    func testAMarkedUpPDFGoesInTheReplyAsAFile() throws {
        let lookup: (String) -> String? = { [kinds] in
            $0.lowercased() == "pdf" ? "application/pdf" : kinds[$0.lowercased()]
        }
        let saved = directory.appendingPathComponent("R6 B-170 pdf.pdf")
        try Data("%PDF marked".utf8).write(to: saved)
        let made = MarkupReply.picture(original: "R6 B-170 pdf.pdf", originalType: "application/pdf",
                                       copy: saved, lookup: lookup)
        XCTAssertEqual(made, .init(name: "R6 B-170 pdf.pdf", mimeType: "application/pdf", jpegName: nil))
        XCTAssertEqual(MarkupReply.picture(original: "scan", originalType: "application/pdf",
                                           copy: directory.appendingPathComponent("scan"), lookup: lookup),
                       .init(name: "scan", mimeType: "application/pdf", jpegName: nil), "no extension")
        let row = try MarkupReply.stage(saved, as: made, jpeg: { _ in
            XCTFail("no JPEG of a PDF")
            return Data("jpeg".utf8)
        })
        defer { MarkupReply.letGo(row) }
        guard case let .localFile(url) = row.source else { return XCTFail("\(row.source)") }
        XCTAssertEqual(try Data(contentsOf: url), Data("%PDF marked".utf8))
        XCTAssertEqual(row.filename, "R6 B-170 pdf.pdf")
        XCTAssertEqual(row.mimeType, "application/pdf")
        XCTAssertFalse(row.isBodyPicture)

        let m = original()
        var reply = Draft.replying(to: m, all: false, mine: OwnAddresses(["sam@example.com"]), signature: sig)
        reply.attachments.append(row)
        let account = MailAccount(address: "sam@example.com", username: "sam@example.com",
                                  displayName: "Sam Example", signature: sig, signatureHTML: "")
        let letter = AppleMailHTML.letter(for: reply, account: account, pictureID: { "PHOTO-1" })
        XCTAssertEqual(letter.files, [row])
        XCTAssertEqual(letter.bodyPictures, [])
        XCTAssertTrue(letter.pictures.isEmpty, "her own picture is not sent back")
    }

    // MARK: - The reply

    /// The reply is the app's own Reply to the letter, as the pane makes it
    /// (`openCompose`, read below): to Jane alone, not Pat, "Re:", answering
    /// her letter, his signature, her letter quoted, none of her files. The
    /// copy lands in it as a photo he picks lands, after it: in the letter
    /// it goes under the words he types and above his signature and the
    /// quote, a picture of the letter's and no file.
    func testTheReplyIsTheAppsOwnWithTheCopyUnderHisWords() throws {
        let m = original()
        let mine = OwnAddresses(["sam@example.com"])
        var reply = Draft.replying(to: m, all: false, mine: mine, signature: sig)
        XCTAssertEqual(ReplyFiles.opening(m, included: nil).rows, [], "none of her files")
        XCTAssertEqual(reply.to, ReplyAddressing.reply(to: m, all: false, mine: mine).to)
        XCTAssertEqual(reply.to.count, 1)
        XCTAssertTrue(reply.to[0].contains("jane@example.com"), reply.to[0])
        XCTAssertEqual(reply.cc, [])
        XCTAssertEqual(reply.subject, "Re: The garden")
        XCTAssertEqual(reply.inReplyTo, "<garden-1@example.com>")
        XCTAssertNotNil(reply.quote)
        XCTAssertNotNil(reply.original, "marked answered once it has gone (B-152)")
        XCTAssertTrue(reply.body.hasPrefix(Draft.signatureBlock(sig)), reply.body)

        let saved = directory.appendingPathComponent("IMG_0412.jpeg")
        try Data("marked up".utf8).write(to: saved)
        let row = try MarkupReply.stage(saved, as: MarkupReply.picture(original: "IMG_0412.jpeg",
                                                                       originalType: "image/jpeg",
                                                                       copy: saved, lookup: lookup),
                                        jpeg: { _ in nil })
        defer { MarkupReply.letGo(row) }
        reply.attachments.append(row)
        reply.body = "Look at the left." + reply.body

        let account = MailAccount(address: "sam@example.com", username: "sam@example.com",
                                  displayName: "Sam Example", signature: sig, signatureHTML: "")
        var ids = 0
        let letter = AppleMailHTML.letter(for: reply, account: account, pictureID: {
            ids += 1
            return "PHOTO-\(ids)"
        })
        let html = try XCTUnwrap(letter.html)
        XCTAssertTrue(html.contains("Look at the left.<div><br><br><img id=\"PHOTO-1\" "
                                        + "style=\"padding:0px 1px 1px 0px;\" alt=\"IMG_0412.jpeg\" "
                                        + "src=\"cid:PHOTO-1\"></div>" + AppleMailHTML.signatureAnchor), html)
        let anchor = try XCTUnwrap(html.range(of: AppleMailHTML.signatureAnchor)).lowerBound
        let quote = try XCTUnwrap(html.range(of: "<blockquote")).lowerBound
        XCTAssertLessThan(anchor, quote)
        XCTAssertEqual(letter.bodyPictures, [AppleMailHTML.BodyPicture(contentID: "PHOTO-1", file: row)])
        XCTAssertEqual(letter.files, [])
        XCTAssertTrue(letter.pictures.isEmpty, "her own photo is not sent back")
    }

    // MARK: - The pane and the composer

    /// The pane, read: the item opens Quick Look full screen with the pane
    /// as its delegate, as a tap's is, the marking up begun in it
    /// and the letter and picture held, as in a tap's of a picture or a
    /// PDF (B-176); its editing makes a copy, and any other preview's is
    /// off; each copy
    /// is staged with the kind its name says, a JPEG made at the share
    /// sheet's quality, and goes through `MarkupReply` with the Quick Look
    /// it came from; Quick Look closed, the reply. The reply is
    /// `openCompose`'s Reply to the letter, its one file the copy, landing
    /// in the composer, and the marking up ended on every way out of it.
    /// The menu is reached by a hold alone. Nothing in it sends, and
    /// nothing touches the file Quick Look shows.
    func testThePaneOpensMarkupAndHandsTheCopyToAReply() throws {
        let pane = try source("Sources/Blackmail/UI/MessageDetailViewController.swift")
        for wiring in [
            "case .quickLook, .markupAndReply, .saveImage, .copy: let preview = QLPreviewController() "
                + "preview.dataSource = self preview.delegate = self preview.modalPresentationStyle = .fullScreen "
                + "if use == .markupAndReply || MarkupReply.marksUp(attachment) { "
                + "MarkupReply.letGo(markup.begin(ObjectIdentifier(preview))) marking = (m, attachment) } "
                + "handedOver = true present(preview, animated: true, completion: ready) }",
            "case .quickLook, .markupAndReply, .saveToFiles, .share: break",
            "extension MessageDetailViewController: QLPreviewControllerDelegate { "
                + "func previewController(_ controller: QLPreviewController, "
                + "editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode { "
                + "markup.marks(in: ObjectIdentifier(controller)) ? .createCopy : .disabled }",
            "guard let picture = marking?.picture else { return } "
                + "let made = MarkupReply.picture(original: picture.filename, originalType: picture.mimeType, "
                + "copy: modifiedContentsURL, lookup: { UTType(filenameExtension: $0)?.preferredMIMEType })",
            "copy = try MarkupReply.stage(modifiedContentsURL, as: made, jpeg: { "
                + "UIImage(contentsOfFile: $0.path)?.jpegData(compressionQuality: SharedPhoto.quality) })",
            "let saved = markup.saved(copy, from: ObjectIdentifier(controller), at: Date()) "
                + "MarkupReply.letGo(saved.unused) if let reply = saved.reply { replyWithMarkup(reply) } }",
            "func previewControllerDidDismiss(_ controller: QLPreviewController) { "
                + "if let copy = markup.closed(ObjectIdentifier(controller), at: Date()) { replyWithMarkup(copy) } }",
            "private func replyWithMarkup(_ copy: DraftAttachment, tries: Int = 0) { "
                + "guard let letter = marking?.letter else { markup.ended() return MarkupReply.letGo(copy) } "
                + "if let over = presentedViewController { guard over is QLPreviewController, tries < 10 else { "
                + "marking = nil markup.ended() MarkupReply.letGo(copy)",
            "marking = nil openCompose(replyTo: letter, all: false, forward: false, landing: [copy]) "
                + "markup.ended() }",
            "private func openCompose(replyTo m: Message?, all: Bool, forward: Bool, "
                + "included: Bool? = nil, landing: [DraftAttachment] = []) {",
            "let compose = ComposeViewController(repository: repository, draft: draft, "
                + "replyFiles: replyFiles) compose.landing = landing",
            "var isOpeningFile: Bool { filesOpening > 0 || markup.isBusy(at: Date()) }",
        ] {
            XCTAssertTrue(pane.contains(wiring), wiring)
        }
        XCTAssertEqual(count("preview.delegate = self", in: pane), 1, "every preview's, one branch")
        XCTAssertEqual(count(".createCopy", in: pane), 1, "Markup to the preview `marks` names alone")
        XCTAssertEqual(count("QLPreviewController()", in: pane), 1)
        XCTAssertEqual(count("markup.begin(", in: pane), 1)
        XCTAssertEqual(count("PanePictures.menu", in: pane), 2,
                       "a held picture's menu, and a held tile's (B-170; int19)")
        XCTAssertEqual(count("landing: [copy]", in: pane), 1)
        XCTAssertEqual(count("compose.landing", in: pane), 1)
        XCTAssertEqual(count("markup.ended()", in: pane), 3, "every way out of the reply's path")

        let delegate = try part(of: pane, from: "extension MessageDetailViewController: QLPreviewControllerDelegate {",
                                to: "#endif")
        let reply = try part(of: pane, from: "private func replyWithMarkup(", to: "private func follow(")
        for words in ["send", "Submission", "repository", "previewURL", "removeStaged"] {
            XCTAssertFalse(delegate.contains(words), words)
            XCTAssertFalse(reply.contains(words), words)
        }
    }

    /// The composer, read: what it was opened to carry lands after the
    /// letter is taken as it opened, through `landed`, as a photo he picks
    /// lands: so Cancel asks of it, the letter is kept with it, and its
    /// staged file goes with the composer.
    func testTheComposerLandsTheCopyAsAPhotoHePicks() throws {
        let composer = try source("Sources/Blackmail/UI/ComposeViewController.swift")
        XCTAssertTrue(composer.contains("var landing: [DraftAttachment] = []"))
        XCTAssertTrue(composer.contains(
            "opened = currentLetter() for row in landing { guard case let .localFile(url) = row.source "
                + "else { continue } landed(url, row) } updateSend()"))
        XCTAssertTrue(composer.contains("private func landed(_ url: URL, _ row: DraftAttachment) { "
                                            + "staged.record(url) draft.attachments.append(row)"))
        XCTAssertEqual(count("landing", in: composer), 2)

        var letter = Draft.replying(to: original(), all: false, mine: OwnAddresses(["sam@example.com"]),
                                    signature: sig)
        let opened = letter
        letter.attachments.append(copy(1))
        XCTAssertTrue(ComposeForm.asksBeforeClosing(letter, opened: opened), "Cancel asks of his drawing")
    }

    // MARK: - Helpers

    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent(file)
        let text = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        return text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func part(of code: String, from start: String, to end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start), start)
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex), end)
        return String(code[from.lowerBound..<to.lowerBound])
    }
}
