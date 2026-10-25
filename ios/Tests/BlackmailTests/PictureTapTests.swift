import XCTest
@testable import Blackmail

/// A picture in a letter, tapped (B-122). Mail opens a picture the letter
/// carries, one its HTML shows by `cid:`, full screen in Quick Look, whose
/// share button gives Save Image and Save to Files; a tap on one here did
/// nothing. Now the pane's script, in the app's content world, tells the
/// pane of a tap on a picture of the letter's own parts that is not inside
/// a link, and the pane opens that part as a file's row opens a file,
/// when the picture is large enough (`PanePictures`).
///
/// What the script does is run in node on the model of the pane's page
/// (`ModelPage`); the pane's own wiring, which is UIKit and WebKit and
/// does not build here, is read from its source.
final class PictureTapTests: XCTestCase {

    private typealias Tap = PanePictures.Tap

    // MARK: - Letters

    /// A photo sent as Apple Mail sends one, inline with a `Content-ID`.
    private let photo = Attachment(id: "2", filename: "IMG_0412.jpeg", mimeType: "image/jpeg", size: 2_400_000,
                                   contentID: "8F3B2A10-77C4-4E0B-9C61-2D5A0F1E3B47", isInline: true)
    /// A signature's logo, as his own is: 210 by 156, drawn at 35 by 25.
    private let logo = Attachment(id: "3", filename: "logo.png", mimeType: "image/png", size: 7_500,
                                  contentID: "sig-logo", isInline: true)
    /// A picture the body shows by `cid:` that is sent as a file, so the
    /// header lists it too.
    private let listed = Attachment(id: "4", filename: "plan.png", mimeType: "image/png", size: 310_000,
                                    contentID: "image001.png@01DA2B3C.4D5E6F70", isInline: false)
    /// A PDF, a file with no `Content-ID`.
    private let pdf = Attachment(id: "5", filename: "rates.pdf", mimeType: "application/pdf", size: 90_000)

    private func letter(_ id: String, mailbox: String = "INBOX", html: String? = nil,
                        attachments: [Attachment]) -> Message {
        Message(id: id, mailboxID: mailbox, sender: "Sam Example <sam@example.com>",
                senderAddress: "sam@example.com", to: [], cc: [], subject: "The garden",
                date: Date(timeIntervalSince1970: 1_790_000_000), textBody: nil,
                htmlBody: html, attachments: attachments)
    }

    private func tap(_ contentID: String, section: String = "", width: Double = 3_024, height: Double = 4_032,
                     drawn: (Double, Double) = (640, 853)) -> Tap {
        Tap(contentID: contentID, section: section, width: width, height: height,
            drawnWidth: drawn.0, drawnHeight: drawn.1)
    }

    private func address(_ contentID: String) -> String {
        InlineImageRewriter.scheme + "://" + InlineImageRewriter.escapedHost(contentID)
    }

    // MARK: - What the script posts

    /// A tap is read as the script posts it, numbers as WebKit hands them
    /// over or as Swift holds them, and the picture's address read back to
    /// its `Content-ID`. Anything else is no tap: an address of another
    /// scheme, a field missing or of another kind, an address naming no id.
    func testATapIsReadAsTheScriptPostsIt() throws {
        let posted: [String: Any] = ["src": address(listed.contentID!), "section": "m1_5",
                                     "width": NSNumber(value: 1_200), "height": NSNumber(value: 900),
                                     "drawnWidth": NSNumber(value: 640.5), "drawnHeight": NSNumber(value: 480)]
        XCTAssertEqual(Tap(posted), Tap(contentID: listed.contentID!, section: "m1_5", width: 1_200,
                                        height: 900, drawnWidth: 640.5, drawnHeight: 480))
        var swift = posted
        swift["width"] = 1_200
        swift["drawnWidth"] = 640.5
        XCTAssertEqual(Tap(swift)?.width, 1_200)
        XCTAssertEqual(Tap(swift)?.drawnWidth, 640.5)
        var upper = posted
        upper["src"] = "BMCID://" + InlineImageRewriter.escapedHost("sig-logo")
        XCTAssertEqual(Tap(upper)?.contentID, "sig-logo")

        for (key, value) in [("src", "https://example.com/photo.jpg"), ("src", "cid:sig-logo"),
                             ("src", "bmfile:2?letter=1/5"), ("src", "bmcid://"), ("src", ""),
                             ("section", nil), ("width", "1200"), ("drawnHeight", nil),
                             ("src", nil)] as [(String, Any?)] {
            var changed = posted
            changed[key] = value
            XCTAssertNil(Tap(changed as [String: Any]), "\(key) \(String(describing: value))")
        }
        XCTAssertNil(Tap("a picture"))
        XCTAssertNil(Tap(["src": address("sig-logo")]))
    }

    /// The `Content-ID` a tap reads is the one the loader serves the
    /// picture by: the body's `cid:` pointed at the loader
    /// (`InlineImageRewriter.rewrite`), read back by the same function the
    /// loader reads it with, for ids as Apple Mail, Outlook, Gmail and this
    /// app's own signature write them.
    func testTheIDATapReadsIsTheOneTheLoaderServes() throws {
        for id in [photo.contentID!, listed.contentID!, "ii_lv3x2a1b0", "sig-logo",
                   "part1.06090408.01060107@example.com", "image002.jpg@01D9A1B2.C3D4E5F0"] {
            let page = InlineImageRewriter.rewrite("<p>Look</p><img src=\"cid:\(id)\" alt=\"\">", known: [id])
            let src = try XCTUnwrap(page.components(separatedBy: "src=\"").last?.components(separatedBy: "\"").first)
            XCTAssertTrue(src.hasPrefix("bmcid://"), src)
            XCTAssertEqual(InlineImageRewriter.contentID(of: try XCTUnwrap(URL(string: src))), id)
            let posted: [String: Any] = ["src": src, "section": "", "width": 400, "height": 300,
                                         "drawnWidth": 400, "drawnHeight": 300]
            XCTAssertEqual(Tap(posted)?.contentID, id)
        }
    }

    // MARK: - Which pictures open

    /// A picture opens when it is at least 100 each way in itself, and
    /// drawn at least 100 along its longer side and 44 along its shorter
    /// (`PanePictures.least`, `leastAcross`): a photo does, and a panorama
    /// whatever the panes; a spacer drawn large, a picture not come, an
    /// icon, and a logo drawn small, as his own signature's, do not.
    func testOnlyAPictureLargeEnoughOpens() {
        XCTAssertEqual(PanePictures.least, 100)
        XCTAssertEqual(PanePictures.leastAcross, 44)
        for (name, t) in [
            ("a photo, 3024 by 4032 drawn 640 by 853", tap("p")),
            ("at the bound", tap("p", width: 100, height: 100, drawn: (100, 44))),
            ("at the bound, upright", tap("p", width: 100, height: 100, drawn: (44, 100))),
            ("a small photo drawn small", tap("p", width: 320, height: 240, drawn: (160, 120))),
            ("a panorama in two panes", tap("p", width: 8_064, height: 1_344, drawn: (652, 108.7))),
            ("a panorama in three panes", tap("p", width: 8_064, height: 1_344, drawn: (501, 83.5))),
            ("a banner logo", tap("p", width: 1_200, height: 300, drawn: (300, 75))),
        ] {
            XCTAssertTrue(t.opens, name)
        }
        for (name, t) in [
            ("his signature's logo", tap("p", width: 210, height: 156, drawn: (35, 25))),
            ("a spacer drawn wide", tap("p", width: 1, height: 1, drawn: (600, 20))),
            ("a spacer drawn large", tap("p", width: 1, height: 1, drawn: (600, 400))),
            ("not come", tap("p", width: 0, height: 0, drawn: (640, 480))),
            ("an icon", tap("p", width: 64, height: 64, drawn: (32, 32))),
            ("an icon drawn large", tap("p", width: 64, height: 64, drawn: (128, 128))),
            ("99 wide", tap("p", width: 99, height: 400, drawn: (400, 400))),
            ("99 high", tap("p", width: 400, height: 99, drawn: (400, 400))),
            ("drawn 99 each way", tap("p", width: 400, height: 400, drawn: (99, 99))),
            ("drawn 43 high", tap("p", width: 400, height: 400, drawn: (400, 43))),
            ("drawn 43 wide", tap("p", width: 400, height: 400, drawn: (43, 400))),
            ("a rule drawn thin", tap("p", width: 600, height: 120, drawn: (600, 12))),
            ("not a number", tap("p", width: .nan, height: 400, drawn: (400, 400))),
            ("drawn not a number", tap("p", width: 400, height: 400, drawn: (400, .nan))),
            ("endless", tap("p", width: .infinity, height: 400, drawn: (400, 400))),
            ("drawn endless", tap("p", width: 400, height: 400, drawn: (.infinity, 400))),
        ] {
            XCTAssertFalse(t.opens, name)
        }
    }

    /// The part a tap opens is the letter's own, by its `Content-ID`: the
    /// photo, a picture the header lists as well, and of two under one id
    /// the one the loader serves, the last (`PanePage.pictures`). Nothing
    /// for an id the letter has no part for, or a picture too small,
    /// whatever part it is.
    func testThePictureOpenedIsTheLettersOwnPart() {
        let twin = Attachment(id: "6", filename: "a.png", mimeType: "image/png", size: 200_000,
                              contentID: "same", isInline: true)
        let twin2 = Attachment(id: "7", filename: "b.png", mimeType: "image/png", size: 200_000,
                               contentID: "same", isInline: true)
        let m = letter("7/3", attachments: [photo, logo, listed, pdf, twin, twin2])
        XCTAssertEqual(PanePictures.part(photo.contentID!, of: m), photo)
        XCTAssertEqual(PanePictures.part(listed.contentID!, of: m), listed)
        XCTAssertEqual(PanePictures.part("same", of: m), twin2)
        XCTAssertEqual(PanePictures.part("same", of: m)?.id, PanePage.pictures(of: [m])["same"]?.section)
        XCTAssertNil(PanePictures.part("image003.png@01DA2B3C.4D5E6F70", of: m))
        XCTAssertNil(PanePictures.part("", of: m))

        let opened = PanePictures.opening(tap(photo.contentID!), inStack: false, alone: m, stack: [:],
                                          his: { _ in nil })
        XCTAssertEqual(opened?.letter.id, "7/3")
        XCTAssertEqual(opened?.part, photo)
        XCTAssertNil(PanePictures.opening(tap(logo.contentID!, width: 210, height: 156, drawn: (35, 25)),
                                          inStack: false, alone: m, stack: [:], his: { _ in nil }),
                     "his logo, drawn small")
        XCTAssertNil(PanePictures.opening(tap("not-in-it"), inStack: false, alone: m, stack: [:],
                                          his: { _ in nil }))
        XCTAssertNil(PanePictures.opening(tap(photo.contentID!), inStack: false, alone: nil, stack: [:],
                                          his: { _ in nil }), "no letter in the pane")
    }

    /// The letter a tap is of: on a letter's own page, the letter shown,
    /// whatever section the tap names, since that page holds no other; in
    /// a stack, the letter of the section, one of the conversation's that
    /// has come or his from Sent Mail, and never the letter shown alone
    /// before, a letter whose body has not come, or none for "".
    func testTheLetterIsTheOneWhoseSectionThePictureIsIn() {
        let mine = Attachment(id: "2", filename: "IMG_0413.jpeg", mimeType: "image/jpeg", size: 2_000_000,
                              contentID: photo.contentID, isInline: true)
        let first = letter("1/3", attachments: [photo])
        let second = letter("1/5", attachments: [photo, logo])
        let his = letter("6/4", mailbox: "[Gmail]/Sent Mail", attachments: [mine])
        let stack = ["1/3": first, "1/5": second]
        let hisBySection: (String) -> Message? = { $0 == "mr6_4" ? his : nil }

        XCTAssertEqual(PanePictures.opening(tap(photo.contentID!, section: "m1_3"), inStack: true, alone: second,
                                            stack: stack, his: hisBySection)?.letter.id, "1/3")
        XCTAssertEqual(PanePictures.opening(tap(photo.contentID!, section: "m1_5"), inStack: true, alone: first,
                                            stack: stack, his: hisBySection)?.letter.id, "1/5")
        let mineOpened = PanePictures.opening(tap(photo.contentID!, section: "mr6_4"), inStack: true,
                                              alone: second, stack: stack, his: hisBySection)
        XCTAssertEqual(mineOpened?.letter.id, "6/4")
        XCTAssertEqual(mineOpened?.letter.mailboxID, "[Gmail]/Sent Mail")
        XCTAssertEqual(mineOpened?.part, mine)
        for section in ["", "m1_9", "m6_4", "bm", "m1_3 "] {
            XCTAssertNil(PanePictures.opening(tap(photo.contentID!, section: section), inStack: true,
                                              alone: second, stack: stack, his: hisBySection), section)
        }
        XCTAssertNil(PanePictures.opening(tap(logo.contentID!, section: "m1_3"), inStack: true, alone: second,
                                          stack: stack, his: hisBySection), "1/3 has no logo")
        for section in ["", "m1_3", "mr6_4"] {
            XCTAssertEqual(PanePictures.opening(tap(logo.contentID!, section: section, width: 400, height: 300,
                                                    drawn: (400, 300)),
                                                inStack: false, alone: second, stack: stack,
                                                his: hisBySection)?.letter.id, "1/5", section)
        }
    }

    /// His letter from Sent Mail in a stack (B-104) is kept once its body
    /// has come, by its entry, for a picture tapped in it; not before, not
    /// a letter that is not the one asked for, and not once the pane has
    /// moved on.
    func testHisLetterIsKeptForItsPicturesWhileTheStackShows() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func row(_ id: String, _ mailbox: String, _ n: Int, gmail: UInt64) -> MessageSummary {
            MessageSummary(id: id, mailboxID: mailbox, sender: "Sam Example <sam@example.com>",
                           subject: "Re: the roof", preview: "letter \(n)",
                           date: base.addingTimeInterval(Double(n) * 60), isRead: true, isFlagged: false,
                           threadID: "1700000000000000042", gmailMessageID: gmail,
                           arrived: base.addingTimeInterval(Double(n) * 60))
        }
        let stack = [row("1/3", "INBOX", 3, gmail: 9_003), row("1/5", "INBOX", 5, gmail: 9_005)]
        var related = PaneRelated()
        XCTAssertNil(related.show(stack, completing: 42, remembered: nil))
        _ = related.take(RelatedLetters(folderName: "Sent Mail",
                                        letters: [row("6/4", "[Gmail]/Sent Mail", 4, gmail: 8_004)]),
                         stack: stack)
        let load = try XCTUnwrap(related.load(for: "r6/4"))
        XCTAssertNil(related.letter(inSection: "mr6_4"), "not come")

        related.keep(letter("6/9", mailbox: "[Gmail]/Sent Mail", attachments: [photo]), for: load)
        XCTAssertNil(related.letter(inSection: "mr6_4"), "another letter than the one asked for")
        let his = letter("6/4", mailbox: "[Gmail]/Sent Mail", attachments: [photo])
        related.keep(his, for: load)
        XCTAssertEqual(related.letter(inSection: "mr6_4")?.id, "6/4")
        XCTAssertNil(related.letter(inSection: "m6_4"))
        XCTAssertNil(related.letter(inSection: "m1_5"), "a letter of the conversation's")
        XCTAssertEqual(related.bodyCame(for: load), "r6/4")
        XCTAssertEqual(related.letter(inSection: "mr6_4")?.id, "6/4")

        related.clear()
        XCTAssertNil(related.letter(inSection: "mr6_4"), "the pane moved on")
        related.keep(his, for: load)
        XCTAssertNil(related.letter(inSection: "mr6_4"), "an entry of no conversation shown")

        // The conversation shown again, his letter in it again: not his
        // letter as it came the time before, until it comes again.
        XCTAssertNil(related.show(stack, completing: 42, remembered: nil))
        _ = related.take(RelatedLetters(folderName: "Sent Mail",
                                        letters: [row("6/4", "[Gmail]/Sent Mail", 4, gmail: 8_004)]),
                         stack: stack)
        XCTAssertEqual(related.entryID(forSection: "mr6_4"), "r6/4")
        XCTAssertNil(related.letter(inSection: "mr6_4"), "let go with the conversation before")
        related.keep(his, for: try XCTUnwrap(related.load(for: "r6/4")))
        XCTAssertEqual(related.letter(inSection: "mr6_4")?.id, "6/4")
    }

    // MARK: - The script, on the model of the page

    private func run(_ page: String, _ steps: [ModelPage.Step]) throws -> ModelPage.Run {
        do {
            return try ModelPage.run(ConversationDocument.script, page: page, steps: steps, end: 2_000)
        } catch is ModelPage.NoNode {
            throw XCTSkip("node is not on this host")
        }
    }

    /// A picture's markup, with its own size and its size as drawn.
    private func img(_ id: String, _ src: String, own: (Int, Int) = (3_024, 4_032),
                     drawn: (Int, Int) = (640, 853), extra: String = "") -> String {
        "<img id=\"\(id)\" src=\"\(src)\" data-nw=\"\(own.0)\" data-nh=\"\(own.1)\" "
            + "data-dw=\"\(drawn.0)\" data-dh=\"\(drawn.1)\"\(extra)>"
    }

    /// On a letter's own page, a tap on a picture of its own parts tells
    /// the pane its address, no section, and its sizes, once; the pane
    /// opens the photo from it. A picture inside a link, however deep, one
    /// with an empty `href` too, in an image map or a button, one from the
    /// web, and one by a `cid:` the letter has no part for tell it nothing,
    /// nor does a tap on the words; his signature's logo tells it, and the
    /// pane leaves it. A picture inside a bookmark, an `<a>` with a `name`
    /// and no `href`, as Outlook and Word wrap a signature and a letter
    /// quoted, tells it, and opens; so does one whose `src` has spaces
    /// around it, which WebKit trims, by the address trimmed. Nothing is
    /// posted to `bmLetter`, and nothing throws.
    func testOnALettersOwnPageATapOnItsPictureTellsThePane() throws {
        let html = "<p>Our new garden.</p>"
            + img("photo", "cid:\(photo.contentID!)")
            + "<p><a href=\"https://example.com/garden\">" + img("linked", "cid:\(listed.contentID!)") + "</a></p>"
            + "<a href=\"https://example.com/deep\"><div><span>"
            + img("deep", "cid:\(listed.contentID!)") + "</span></div></a>"
            + img("mapped", "cid:\(listed.contentID!)", extra: " usemap=\"#garden\"")
            + "<button>" + img("button", "cid:\(listed.contentID!)") + "</button>"
            + img("web", "https://example.com/garden.jpg")
            + img("missing", "cid:image009.png@01DA2B3C.4D5E6F70")
            + "<p id=\"words\">Love, Sam</p>"
            + "<div class=\"bm-signature\">" + img("logo", "cid:sig-logo", own: (210, 156), drawn: (35, 25))
            + "</div>"
            + "<a name=\"_MailAutoSig\"><div><span>" + img("bookmarked", "cid:\(listed.contentID!)",
                                                         own: (1_200, 900), drawn: (640, 480))
            + "</span></div></a>"
            + "<a href=\"\">" + img("emptyLink", "cid:\(listed.contentID!)") + "</a>"
            + img("spaced", " cid:\(photo.contentID!) ")
        let m = letter("7/3", html: html, attachments: [photo, logo, listed, pdf])
        let page = try XCTUnwrap(PanePage.letter(m, style: .init(inset: 26, bodyPointSize: 17, lineHeight: 1.41)))
        XCTAssertTrue(page.contains("id=\"bm\""))
        XCTAssertTrue(page.contains("src=\" \(address(photo.contentID!)) \""), "the spaces kept in the page")

        let run = try run(page, ["photo", "linked", "deep", "mapped", "button", "web", "missing", "words", "logo",
                                 "bookmarked", "emptyLink", "spaced"]
                                    .enumerated().map { .click(100 + $0.offset * 100, $0.element) })
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.posts, [])
        XCTAssertEqual(run.pictures, [
            .init(src: address(photo.contentID!), section: "", width: 3_024, height: 4_032,
                  drawnWidth: 640, drawnHeight: 853),
            .init(src: address("sig-logo"), section: "", width: 210, height: 156, drawnWidth: 35, drawnHeight: 25),
            .init(src: address(listed.contentID!), section: "", width: 1_200, height: 900,
                  drawnWidth: 640, drawnHeight: 480),
            .init(src: address(photo.contentID!), section: "", width: 3_024, height: 4_032,
                  drawnWidth: 640, drawnHeight: 853),
        ])
        let taps = run.pictures.compactMap { Tap($0.body) }
        XCTAssertEqual(taps.count, 4)
        let opened = taps.map { PanePictures.opening($0, inStack: false, alone: m, stack: [:], his: { _ in nil }) }
        XCTAssertEqual(opened.map { $0?.part }, [photo, nil, listed, photo],
                       "the photo, not the logo, the picture in a bookmark, the photo by its address trimmed")
    }

    /// In a stack, a picture in a body `bmFill` put in tells the pane the
    /// section of its letter: the one that is the body's own child, not a
    /// section a letter's markup draws inside itself. A body put in again
    /// is wired again, once. A picture in a link is the link's. A tap on
    /// a picture opens or closes no letter.
    func testInAStackATapNamesTheSectionOfItsLetter() throws {
        let entries = [
            ConversationDocument.Entry(id: "1/3", sender: "Sam <sam@example.com>",
                                       date: Date(timeIntervalSince1970: 1_700_000_000), body: nil,
                                       isExpanded: true, preview: "first"),
            ConversationDocument.Entry(id: "1/5", sender: "Sam <sam@example.com>",
                                       date: Date(timeIntervalSince1970: 1_700_000_600), body: nil,
                                       isExpanded: true, preview: "second"),
        ]
        let page = ConversationDocument.html(entries: entries, inset: 20, bodyPointSize: 17, lineHeight: 1.4)
        let first = address(photo.contentID!)
        let fake = "<div class=\"bm-letter\" id=\"m1_3\">" + img("inFake", first) + "</div>"
        let second = img("second", first) + fake
            + "<a href=\"https://example.com\">" + img("secondLinked", first) + "</a>"
        func fill(_ at: Int, _ section: String, _ html: String) -> ModelPage.Step {
            .fill(at, ConversationDocument.Fill(sectionID: section, body: .init(html: html, isHTML: true)))
        }
        let run = try run(page, [
            fill(50, "m1_3", "<p data-h=\"400\">Look</p>" + img("first", first)),
            fill(60, "m1_5", "<p data-h=\"300\">Again</p>" + second),
            .click(200, "first"), .click(300, "second"), .click(400, "inFake"), .click(500, "secondLinked"),
            fill(600, "m1_3", "<p data-h=\"400\">Look</p>" + img("first", first)),
            .click(700, "first"),
        ])
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.pictures.map(\.section), ["m1_3", "m1_5", "m1_5", "m1_3"])
        XCTAssertEqual(Set(run.pictures.map(\.src)), [first])
        XCTAssertEqual(run.posts, [], "no letter opened or closed")
    }

    /// The script, read: the address's scheme, as WebKit reads the `src`,
    /// the link, image map and button rule, a link an `<a>` with an
    /// `href`, the section that is the body's child, the post in the app's
    /// world, the wiring as the document ends and as a body goes in, which
    /// never throws; held where node is not.
    func testTheScriptWiresALettersOwnPicturesOnEveryPage() {
        let script = flat(ConversationDocument.script)
        for wiring in [
            "function bmPictureSrc(img) { return String(img.src || ''); }",
            "if (bmPictureSrc(img).slice(0, 8).toLowerCase() !== 'bmcid://') return false;",
            "if (img.getAttribute('usemap') !== null) return false;",
            "for (var node = img.parentNode; node && node !== document.body; node = node.parentNode) { "
                + "var tag = String(node.tagName || '').toLowerCase(); "
                + "if ((tag === 'a' && node.getAttribute('href') !== null) || tag === 'button') return false; }",
            "if (node.parentNode === document.body) { "
                + "return node.classList && node.classList.contains('bm-letter') ? node.id : ''; }",
            "window.webkit.messageHandlers.bmPicture.postMessage({ src: bmPictureSrc(img), "
                + "section: bmPictureIn(img), width: img.naturalWidth, height: img.naturalHeight, "
                + "drawnWidth: drawn.width, drawnHeight: drawn.height });",
            "function bmWirePictures(root) { try { var pictures = root.querySelectorAll('img'); "
                + "for (var i = 0; i < pictures.length; i++) { if (bmOwnPicture(pictures[i])) "
                + "pictures[i].addEventListener('click', bmPictureTapped); } } catch (e) {} }",
            "body.innerHTML = html; bmWirePictures(body); }",
            "(function () { if (document.body) bmWirePictures(document.body); })(); "
                + "(function () { if (document.getElementById('bm')) return;",
        ] {
            XCTAssertTrue(script.contains(wiring), wiring)
        }
        XCTAssertFalse(script.contains("getAttribute('src')"), "the address as written")
        XCTAssertEqual(PanePictures.handler, "bmPicture")
    }

    // MARK: - The pane

    /// The pane, read from its source: `bmPicture` registered in the app's
    /// content world alone, as `bmLetter` is; a tap read and opened before
    /// anything of the lines is looked at; the letter and part from
    /// `PanePictures`, the stack's letters and his by their sections, the
    /// letter alone otherwise; and opened by `openAttachment`, as a file's
    /// row is. His letter from Sent Mail kept as its body comes. The loader
    /// reads a picture's address as a tap is read.
    func testThePaneOpensATappedPictureAsAFilesRowOpensAFile() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        let built = try XCTUnwrap(code.range(of: "self.webView = WKWebView(frame: .zero, configuration: config)"))
        let registered = try XCTUnwrap(code.range(of: "config.userContentController.add(self, contentWorld: "
                                                      + ".defaultClient, name: PanePictures.handler)"))
        XCTAssertLessThan(built.lowerBound, registered.lowerBound)
        XCTAssertFalse(code.contains("add(self, name:"))
        XCTAssertFalse(code.contains(".page"))

        let handled = try XCTUnwrap(code.range(of: "didReceive scriptMessage: WKScriptMessage) { "
                                                   + "if scriptMessage.name == PanePictures.handler { "
                                                   + "if let tap = PanePictures.Tap(scriptMessage.body) "
                                                   + "{ openPicture(tap) } return } "
                                                   + "guard scriptMessage.name == \"bmLetter\","))
        XCTAssertLessThan(handled.lowerBound, try XCTUnwrap(code.range(of: "related.entryID(forSection:")).lowerBound)
        XCTAssertTrue(code.contains(
            "private func openPicture(_ tap: PanePictures.Tap) { "
                + "guard let opening = PanePictures.opening(tap, inStack: !threadSummaries.isEmpty, "
                + "alone: message, stack: loaded, his: { related.letter(inSection: $0) }) else { return } "
                + "openAttachment(opening.part, of: opening.letter) }"))
        XCTAssertEqual(code.components(separatedBy: "openPicture(").count - 1, 2, "defined, and called by a tap")
        XCTAssertTrue(code.contains("related.keep(m, for: load) fill(related.bodyCame(for: load), body)"))

        let loader = try source("UI/InlineImageLoader.swift")
        XCTAssertTrue(loader.contains(
            "let contentID = task.request.url.flatMap(InlineImageRewriter.contentID(of:)) ?? \"\" "
                + "guard !contentID.isEmpty, let fetch else {"))
    }

    /// A picture, or a file, that comes after the pane has moved on is not
    /// shown, and no failure is said for it, over the letter he stopped on
    /// (`PaneLoads.stillShows`, read in `openAttachment`). The pane still
    /// shows what it was opened from while another letter of the
    /// conversation is opened in it or his letters are looked for, and no
    /// longer once it is given another letter, or the same one again, or
    /// emptied.
    @MainActor
    func testAPictureThatComesAfterThePaneHasMovedOnIsNotShown() throws {
        let loads = PaneLoads()
        let tapped = loads.shown
        XCTAssertTrue(loads.stillShows(tapped))
        loads.start({ "a letter of the stack" }, settle: { _ in })
        XCTAssertTrue(loads.stillShows(tapped), "another letter of the conversation opened")
        loads.aside({ "his letters" }, settle: { _ in })
        XCTAssertTrue(loads.stillShows(tapped), "his letters looked for")
        loads.show(standIn: {}, fetch: { "the next letter" }, settle: { _ in })
        XCTAssertFalse(loads.stillShows(tapped), "another row tapped")
        let next = loads.shown
        XCTAssertTrue(loads.stillShows(next))
        loads.show(standIn: {}, fetch: { "the next letter" }, settle: { _ in })
        XCTAssertFalse(loads.stillShows(next), "its row tapped again")
        let again = loads.shown
        loads.supersede()
        XCTAssertFalse(loads.stillShows(again), "emptied")
        XCTAssertFalse(loads.stillShows(tapped))

        let code = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(code.contains(
            "private func openAttachment(_ attachment: Attachment, of letter: Message? = nil) { "
                + "guard let m = letter ?? message else { return } "
                + "if message?.id == m.id { header.setAttachment(attachment.id, busy: true) } "
                + "let shown = loads.shown "
                + "let file = FileTaps.File(letter: m.id, part: attachment.id, shown: shown) "
                + "guard fileTaps.tapped(file) else { return } filesOpening += 1 "
                + "Task { @MainActor in"))
        XCTAssertTrue(code.contains(
            "let data = try await repository.fetchAttachmentData( attachment.id, of: m.id, mailboxID: m.mailboxID) "
                + "guard loads.stillShows(shown) else { return } "
                + "guard fileTaps.opens(file) else { return } "
                + "guard presentedViewController == nil else { return }"))
        XCTAssertTrue(code.contains(
            "} catch { guard loads.stillShows(shown), fileTaps.opens(file) else { return } "
                + "ErrorPresenter.show(.attachmentFailed, on: self) }"))
        XCTAssertEqual(code.components(separatedBy: ".attachmentFailed, on: self)").count - 1, 1)
    }

    // MARK: - Helpers

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
        return flat(text)
    }

    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }
}
