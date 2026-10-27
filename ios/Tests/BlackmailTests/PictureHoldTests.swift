import XCTest
@testable import Blackmail

/// A finger held on a picture in a letter (B-150). Mail's menu for a file
/// of the letter's is Quick Look, Markup and Reply, Save Image, Save to
/// Files, Share and Copy (an iPhone on iOS 16); its iPadOS 18 guide names
/// Save Image, Save to Files and Share. Here the hold gave WebKit's menu,
/// with Save to Photos and no Save to Files (B-067, B-122). Now the pane's
/// script keeps WebKit's menu off a picture of the letter's own and tells
/// the pane of a hold on it, and the pane puts up Quick Look, Save Image,
/// Save to Files, Share and Copy at the finger (`PanePictures.menu`); a
/// picture from the web, or in a link, keeps WebKit's.
///
/// The script runs in node on the model of the pane's page (`ModelPage`);
/// the pane, UIKit and WebKit, is read from its source.
final class PictureHoldTests: XCTestCase {

    private typealias Tap = PanePictures.Tap

    private let photo = Attachment(id: "2", filename: "IMG_0412.jpeg", mimeType: "image/jpeg", size: 2_400_000,
                                   contentID: "8F3B2A10-77C4-4E0B-9C61-2D5A0F1E3B47", isInline: true)
    private let logo = Attachment(id: "3", filename: "logo.png", mimeType: "image/png", size: 7_500,
                                  contentID: "sig-logo", isInline: true)
    private let pdf = Attachment(id: "5", filename: "rates.pdf", mimeType: "application/pdf", size: 90_000)

    private func letter(_ id: String, html: String? = nil, attachments: [Attachment]) -> Message {
        Message(id: id, mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                senderAddress: "sam@example.com", to: [], cc: [], subject: "The garden",
                date: Date(timeIntervalSince1970: 1_790_000_000), textBody: nil,
                htmlBody: html, attachments: attachments)
    }

    private func address(_ contentID: String) -> String {
        InlineImageRewriter.scheme + "://" + InlineImageRewriter.escapedHost(contentID)
    }

    // MARK: - What the script posts

    /// A hold is read as the script posts it: a tap's fields, `hold` true,
    /// and the finger's place, numbers as WebKit hands them over or as
    /// Swift holds them. `hold` false is a tap. A hold with no place, or
    /// one not a number, and a `hold` that is not true or false, are
    /// nothing.
    func testAHoldIsReadAsTheScriptPostsIt() throws {
        let tap: [String: Any] = ["src": address(photo.contentID!), "section": "m1_5",
                                  "width": NSNumber(value: 1_200), "height": NSNumber(value: 900),
                                  "drawnWidth": NSNumber(value: 640), "drawnHeight": NSNumber(value: 480)]
        var hold = tap
        hold["hold"] = NSNumber(value: true)
        hold["x"] = NSNumber(value: 312.5)
        hold["y"] = NSNumber(value: 401)
        let read = try XCTUnwrap(Tap(hold))
        XCTAssertTrue(read.isHold)
        XCTAssertEqual(read.x, 312.5)
        XCTAssertEqual(read.y, 401)
        XCTAssertEqual(read.contentID, photo.contentID)
        XCTAssertEqual(read.section, "m1_5")

        var swift = hold
        swift["hold"] = true
        swift["x"] = 10
        XCTAssertEqual(Tap(swift)?.isHold, true)
        XCTAssertEqual(Tap(swift)?.x, 10)

        let plain = try XCTUnwrap(Tap(tap))
        XCTAssertFalse(plain.isHold)
        XCTAssertEqual(plain.x, 0)
        var notHeld = tap
        notHeld["hold"] = false
        XCTAssertEqual(Tap(notHeld), plain)

        for (key, value) in [("x", nil), ("y", nil), ("x", "312"), ("y", Double.nan), ("x", Double.infinity),
                             ("hold", "yes")] as [(String, Any?)] {
            var changed = hold
            changed[key] = value
            XCTAssertNil(Tap(changed as [String: Any]), "\(key) \(String(describing: value))")
        }
    }

    // MARK: - The menu

    /// Mail's menu for a file of the letter's, in its order, less Look Up:
    /// Quick Look, Markup and Reply (B-171), Save Image, Save to Files,
    /// Share, Copy. Save Image and Copy put nothing over the pane.
    func testTheMenuIsMailsInMailsOrder() {
        XCTAssertEqual(PanePictures.menu.map(\.title),
                       ["Quick Look", "Markup and Reply", "Save Image", "Save to Files", "Share", "Copy"])
        XCTAssertEqual(PanePictures.menu, PanePictures.Item.allCases)
        XCTAssertEqual(PanePictures.menu.filter(\.presents), [.quickLook, .markupAndReply, .saveToFiles, .share])
    }

    /// A hold has the menu for any picture of the letter's own, his logo
    /// drawn small and a picture not yet come among them, where a tap
    /// opens neither (B-122, as it was); never one the letter has no part
    /// for, nor in a stack one of a letter not come.
    func testAHoldHasTheMenuForAnyPictureOfTheLettersOwn() {
        let m = letter("1/5", attachments: [photo, logo, pdf])
        func held(_ contentID: String, own: (Double, Double), drawn: (Double, Double),
                  section: String = "") -> Tap {
            Tap(contentID: contentID, section: section, width: own.0, height: own.1, drawnWidth: drawn.0,
                drawnHeight: drawn.1, isHold: true, x: 300, y: 200)
        }
        func tapped(_ t: Tap) -> Tap {
            Tap(contentID: t.contentID, section: t.section, width: t.width, height: t.height,
                drawnWidth: t.drawnWidth, drawnHeight: t.drawnHeight)
        }
        for (name, t, part) in [
            ("the photo", held(photo.contentID!, own: (3_024, 4_032), drawn: (640, 853)), photo),
            ("his logo, drawn small", held("sig-logo", own: (210, 156), drawn: (35, 25)), logo),
            ("the photo not come yet", held(photo.contentID!, own: (0, 0), drawn: (16, 16)), photo),
        ] {
            XCTAssertEqual(PanePictures.opening(t, inStack: false, alone: m, stack: [:], his: { _ in nil })?.part,
                           part, name)
        }
        XCTAssertNil(PanePictures.opening(tapped(held("sig-logo", own: (210, 156), drawn: (35, 25))),
                                          inStack: false, alone: m, stack: [:], his: { _ in nil }),
                     "a tap on the logo opens nothing, as before")
        XCTAssertNil(PanePictures.opening(held("image009.png@01DA", own: (800, 600), drawn: (400, 300)),
                                          inStack: false, alone: m, stack: [:], his: { _ in nil }))
        XCTAssertNil(PanePictures.opening(held(photo.contentID!, own: (800, 600), drawn: (400, 300), section: "m1_9"),
                                          inStack: true, alone: m, stack: ["1/5": m], his: { _ in nil }),
                     "a letter of the stack not come")
        XCTAssertEqual(PanePictures.opening(held(photo.contentID!, own: (800, 600), drawn: (400, 300),
                                                 section: "m1_5"),
                                            inStack: true, alone: nil, stack: ["1/5": m], his: { _ in nil })?
                        .letter.id, "1/5")
    }

    /// What a download landing is opened for is what the last tap on it
    /// asked: a picture tapped, then held and Save Image chosen while it
    /// still comes, is saved as it lands, not shown; a tap after that
    /// shows it. Another file tapped since still lets it go.
    func testTheLastTapOnAFileSaysWhatItIsOpenedFor() {
        var taps = FileTaps()
        let picture = FileTaps.File(letter: "1/5", part: "2", shown: 1)
        let other = FileTaps.File(letter: "1/5", part: "5", shown: 1)
        XCTAssertNil(taps.item(of: picture))
        XCTAssertTrue(taps.tapped(picture))
        XCTAssertEqual(taps.item(of: picture), .quickLook)
        XCTAssertFalse(taps.tapped(picture, for: .saveImage), "running: no second download")
        XCTAssertEqual(taps.item(of: picture), .saveImage)
        XCTAssertTrue(taps.opens(picture))
        XCTAssertFalse(taps.tapped(picture, for: .quickLook))
        XCTAssertEqual(taps.item(of: picture), .quickLook)
        XCTAssertTrue(taps.tapped(other, for: .copy))
        XCTAssertFalse(taps.opens(picture))
        XCTAssertTrue(taps.opens(other))
        XCTAssertEqual(taps.item(of: other), .copy)
        taps.ended(picture)
        XCTAssertNil(taps.item(of: picture))
    }

    // MARK: - The script, on the model of the page

    private func run(_ page: String, _ steps: [ModelPage.Step], end: Int = 3_000) throws -> ModelPage.Run {
        do {
            return try ModelPage.run(ConversationDocument.script, page: page, steps: steps, end: end)
        } catch is ModelPage.NoNode {
            throw XCTSkip("node is not on this host")
        }
    }

    private func img(_ id: String, _ src: String, own: (Int, Int) = (3_024, 4_032),
                     drawn: (Int, Int) = (640, 853)) -> String {
        "<img id=\"\(id)\" src=\"\(src)\" data-nw=\"\(own.0)\" data-nh=\"\(own.1)\" "
            + "data-dw=\"\(drawn.0)\" data-dh=\"\(drawn.1)\">"
    }

    private var ownPage: (Message, String) {
        get throws {
            let html = "<p>Our new garden.</p>" + img("photo", "cid:\(photo.contentID!)")
                + "<p><a href=\"https://example.com/garden\">" + img("linked", "cid:\(photo.contentID!)") + "</a></p>"
                + img("web", "https://example.com/garden.jpg")
                + "<div class=\"bm-signature\">" + img("logo", "cid:sig-logo", own: (210, 156), drawn: (35, 25))
                + "</div>"
            let m = letter("7/3", html: html, attachments: [photo, logo])
            return (m, try XCTUnwrap(PanePage.letter(m, style: .init(inset: 26, bodyPointSize: 17,
                                                                        lineHeight: 1.41))))
        }
    }

    /// On a letter's own page: a finger held half a second on the photo
    /// tells the pane of the hold, once, with where the finger is, and the
    /// lift stops WebKit's own tap; the click after it, if WebKit made one,
    /// opens nothing, and a tap after that opens it, as before. His logo
    /// held, the same. A picture in a link and one from the web held tell
    /// it nothing. Each picture of the letter's own has WebKit's menu and
    /// selection kept off it; the linked one and the web one have not.
    func testAFingerHeldOnAPictureTellsThePaneAndKeepsWebKitsMenuOff() throws {
        let (m, page) = try ownPage
        let run = try run(page, [
            .down(100, on: "photo", y: 240), .up(700), .click(701, "photo"),
            .down(900, on: "photo", y: 240), .up(1_000), .click(1_001, "photo"),
            .down(1_200, on: "logo", y: 600), .up(1_800),
            .down(2_000, on: "linked", y: 400), .up(2_600),
            .down(2_700, on: "web", y: 500), .up(2_900),
        ])
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.posts, [])
        XCTAssertEqual(run.pictures.map(\.hold), [true, nil, true])
        XCTAssertEqual(run.pictures.map(\.src), [address(photo.contentID!), address(photo.contentID!),
                                                 address("sig-logo")])
        XCTAssertEqual(run.pictures.first?.x, 300)
        XCTAssertEqual(run.pictures.first?.y, 240)
        XCTAssertEqual(run.stopped, 2, "the lift of each hold, and no other")

        let posted = run.pictures.compactMap { Tap($0.body) }
        XCTAssertEqual(posted.map(\.isHold), [true, false, true])
        XCTAssertEqual(posted.map { PanePictures.opening($0, inStack: false, alone: m, stack: [:],
                                                         his: { _ in nil })?.part },
                       [photo, photo, logo])

        let off = ["-webkit-touch-callout": "none !important", "-webkit-user-select": "none !important"]
        XCTAssertEqual(run.styles, ["photo": off, "logo": off])
    }

    /// No hold: a lift before the half second, which is a tap and opens
    /// the photo, and a finger that moves more than 10 px, neither stopped.
    /// One that moves 8 px is held.
    func testAShortTouchOrAMoveIsNoHold() throws {
        let (_, page) = try ownPage
        let run = try run(page, [
            .down(100, on: "photo", y: 240), .up(499), .click(500, "photo"),
            .down(700, on: "photo", y: 240), .move(800, y: 260), .up(1_400),
            .down(1_500, on: "photo", y: 240), .move(1_600, y: 248), .up(2_200),
        ])
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.pictures.map(\.hold), [nil, true], "the tap, and the hold that moved 8 px")
        XCTAssertEqual(run.stopped, 1)
    }

    /// In a stack, a hold on a picture in a body `bmFill` put in names the
    /// section of its letter, as a tap does, and opens or closes no letter.
    func testInAStackAHoldNamesTheSectionOfItsLetter() throws {
        let entries = [
            ConversationDocument.Entry(id: "1/3", sender: "Sam <sam@example.com>",
                                       date: Date(timeIntervalSince1970: 1_700_000_000), body: nil,
                                       isExpanded: true, preview: "first"),
            ConversationDocument.Entry(id: "1/5", sender: "Sam <sam@example.com>",
                                       date: Date(timeIntervalSince1970: 1_700_000_600), body: nil,
                                       isExpanded: true, preview: "second"),
        ]
        let page = ConversationDocument.html(entries: entries, inset: 20, bodyPointSize: 17, lineHeight: 1.4)
        let run = try run(page, [
            .fill(50, ConversationDocument.Fill(sectionID: "m1_5", body: .init(
                html: "<p data-h=\"300\">Again</p>" + img("second", address(photo.contentID!)), isHTML: true))),
            .down(200, on: "second", y: 500), .up(800),
        ])
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.pictures.map(\.section), ["m1_5"])
        XCTAssertEqual(run.pictures.map(\.hold), [true])
        XCTAssertEqual(run.posts, [], "no letter opened or closed")
        XCTAssertEqual(run.styles["second"]?["-webkit-touch-callout"], "none !important")
    }

    /// A finger put on the letter to stop it coasting lands on a page still
    /// scrolling, and only stops it, as UIKit gives such a touch to the
    /// scroll view: held there on a photo, it is no hold, as on a line it
    /// is no tap. On a letter's own page, where the stack's script wires
    /// nothing, as in a stack. Once the page is still, a hold on the photo
    /// has the menu, as before.
    func testAFingerThatStopsTheLetterCoastingIsNoHold() throws {
        // A letter's own page taller than the pane: the model's page draws
        // each of the body's children 38 px, so blank ones after the
        // letter, `#bm`, make room to scroll.
        let own = "<html><head></head><body><div id=\"bm\"><p>Our new garden.</p>"
            + img("photo", address(photo.contentID!)) + "</div>"
            + String(repeating: "<div></div>", count: 30) + "</body></html>"
        let entries = [
            ConversationDocument.Entry(id: "1/5", sender: "Sam <sam@example.com>",
                                       date: Date(timeIntervalSince1970: 1_700_000_600), body: nil,
                                       isExpanded: true, preview: "second"),
        ]
        let stack = ConversationDocument.html(entries: entries, inset: 20, bodyPointSize: 17, lineHeight: 1.4)
        let fill = ConversationDocument.Fill(sectionID: "m1_5", body: .init(
            html: "<p data-h=\"1500\">Again</p>" + img("photo", address(photo.contentID!)), isHTML: true))
        let flick: [ModelPage.Step] = [.down(100, y: 600), .move(120, y: 500), .move(140, y: 400),
                                       .up(160, coast: 1.0)]
        for (name, page, first) in [("a letter's own page", own, [ModelPage.Step]()),
                                    ("a stack", stack, [.fill(50, fill)])] {
            let run = try run(page, first + flick + [
                .down(300, on: "photo", y: 300), .up(1_000),
                .down(1_500, on: "photo", y: 300), .up(2_100),
            ])
            XCTAssertEqual(run.errors, [], name)
            XCTAssertTrue(run.frames.contains { $0.t > 160 && $0.t < 300 && $0.coasting }, name)
            XCTAssertEqual(run.pictures.map(\.hold), [true], "\(name): the still page's hold alone")
            XCTAssertEqual(run.stopped, 1, name)
            XCTAssertEqual(run.posts, [], name)
        }
    }

    // MARK: - The pane

    /// The pane, read: a hold goes to `holdPicture`, a tap to
    /// `openPicture`; the menu is `PanePictures.menu`, at the finger, for
    /// the picture `PanePictures.opening` finds, each item through
    /// `openAttachment` for that item while the pane still shows what it
    /// did; what lands is opened for the last tap's item; Save Image asks
    /// to add to Photos alone; Save to Files is Files' own export sheet.
    /// The app has the words iOS asks with for adding to Photos (B-067).
    func testThePanePutsUpTheMenuAndDoesWhatItSays() throws {
        let code = try source("Sources/Blackmail/UI/MessageDetailViewController.swift")
        XCTAssertTrue(code.contains("if let tap = PanePictures.Tap(scriptMessage.body) { "
                                        + "if tap.isHold { holdPicture(tap) } else { openPicture(tap) } } return"))
        XCTAssertTrue(code.contains(
            "private func holdPicture(_ tap: PanePictures.Tap) { guard presentedViewController == nil, "
                + "let opening = PanePictures.opening(tap, inStack: !threadSummaries.isEmpty, alone: message, "
                + "stack: loaded, his: { related.letter(inSection: $0) }) else { return }"))
        XCTAssertTrue(code.contains("for item in PanePictures.menu { sheet.addAction(UIAlertAction(title: item.title, "
                                        + "style: .default) { [weak self] _ in "
                                        + "guard let self, self.loads.stillShows(shown) else { return } "
                                        + "self.pictureSpot = spot "
                                        + "self.openAttachment(opening.part, of: opening.letter, for: item) }) }"))
        XCTAssertTrue(code.contains("sheet.popoverPresentationController?.sourceView = webView "
                                        + "sheet.popoverPresentationController?.sourceRect = spot"))
        XCTAssertTrue(code.contains("guard fileTaps.tapped(file, for: item) else { return }"))
        XCTAssertTrue(code.contains("guard fileTaps.opens(file) else { return } "
                                        + "let use = fileTaps.item(of: file) ?? item "
                                        + "if !use.presents { keep(data, of: attachment, by: use) return } "
                                        + "guard presentedViewController == nil else { return }"))
        XCTAssertTrue(code.contains("PHPhotoLibrary.requestAuthorization(for: .addOnly)"))
        XCTAssertFalse(code.contains("requestAuthorization(for: .readWrite)"))
        XCTAssertTrue(code.contains("PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, "
                                        + "options: nil)"))
        XCTAssertTrue(code.contains("UIDocumentPickerViewController(forExporting: [url], asCopy: true)"))
        XCTAssertTrue(code.contains("share.popoverPresentationController?.sourceRect = pictureSpot"))

        let plist = try source("Resources/Info.plist")
        XCTAssertTrue(plist.contains("<key>NSPhotoLibraryAddUsageDescription</key>"))
    }

    /// The script, read: the pictures it wires for a tap have WebKit's menu
    /// and selection kept off them, important; a hold is a lone finger kept
    /// within 10 px for half a second; its lift stops WebKit's tap, and the
    /// click of the touch that held opens nothing; heard on the window on
    /// every page.
    func testTheScriptKeepsWebKitsMenuOffAndHearsAHold() {
        let script = flat(ConversationDocument.script)
        for wiring in [
            "if (!bmOwnPicture(pictures[i])) continue; pictures[i].addEventListener('click', bmPictureTapped); "
                + "pictures[i].style.setProperty('-webkit-touch-callout', 'none', 'important'); "
                + "pictures[i].style.setProperty('-webkit-user-select', 'none', 'important');",
            "var bmPictureHold = 500;",
            "if (event.touches.length !== 1 || performance.now() - bmScrolled < 200) return; "
                + "var img = event.target; "
                + "if (!img || String(img.tagName || '').toLowerCase() !== 'img' || !bmOwnPicture(img)) return;",
            "if (bmPictureHeld && event.touches.length === 0) event.preventDefault();",
            "if (bmPictureHeld === img) { bmPictureHeld = null; return; }",
            "drawnWidth: drawn.width, drawnHeight: drawn.height, hold: true,",
            "window.addEventListener('touchend', bmPictureUp, { capture: true, passive: false });",
            "(function () { if (document.body) bmWirePictures(document.body); "
                + "window.addEventListener('scroll', bmScroll, { passive: true }); "
                + "window.addEventListener('touchstart', bmPictureDown, { capture: true, passive: true });",
        ] {
            XCTAssertTrue(script.contains(wiring), wiring)
        }
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
        return flat(text)
    }

    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }
}
