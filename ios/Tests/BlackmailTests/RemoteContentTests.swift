import XCTest
@testable import Blackmail

/// Mail's Block All Remote Content (B-168): off from the factory, and the
/// pages as they always were; on, a letter's pictures from the web held
/// back in the reading pane, a conversation's stack and on paper, with
/// Mail's line, "Message contains unloaded images.", and "Load All Images",
/// which loads that letter's alone; its own pictures drawn as ever.
///
/// What WebKit makes of the list and the markup is the iPad's to show; here
/// are the setting, the markup, the pages, the state, and the wiring, read
/// from the source as `PrintWiringTests` reads it.
final class RemoteContentTests: XCTestCase {

    private let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: MessagesOptions.blockAllRemoteContentKey)
        super.tearDown()
    }

    private func letter(id: String = "7/3", html: String?, text: String? = nil,
                        attachments: [Attachment] = []) -> Message {
        Message(id: id, mailboxID: "INBOX", sender: "Sam <sam@example.com>", senderAddress: "sam@example.com",
                to: [], cc: [], subject: "News", date: Date(timeIntervalSince1970: 1_790_000_000),
                textBody: text, htmlBody: html, attachments: attachments)
    }

    /// A newsletter: a picture from the web and its tracking pixel, a style
    /// sheet's picture, a link, an address in its words, and a picture of
    /// its own by `cid:`.
    private let newsletter = """
        <html><head><title>News</title></head><body>
        <table background="https://cdn.example.com/bg.png"><tr><td>
        <img src="https://cdn.example.com/hero.jpg" width="600">
        <p style="background-image: url('https://cdn.example.com/dots.png')">Spring is here.</p>
        <a href="https://example.com/read">Read on</a> or see https://example.com/words
        <img src="cid:logo@example.com">
        <img src="http://track.example.com/open.gif?u=1" width="1" height="1">
        </td></tr></table></body></html>
        """

    private var logo: Attachment {
        Attachment(id: "2", filename: "logo.png", mimeType: "image/png", size: 1, contentID: "logo@example.com")
    }

    // MARK: - The setting

    /// Off from the factory, read from one place under its own key; a value
    /// written is read back; one written as something else is the factory's.
    func testBlockAllRemoteContentIsOffFromTheFactoryReadFromOnePlace() {
        XCTAssertEqual(MessagesOptions.blockAllRemoteContentKey, "blackmail.blockAllRemoteContent")
        UserDefaults.standard.removeObject(forKey: MessagesOptions.blockAllRemoteContentKey)
        XCTAssertFalse(MessagesOptions.blockAllRemoteContent)
        MessagesOptions.blockAllRemoteContent = true
        XCTAssertEqual(UserDefaults.standard.object(forKey: MessagesOptions.blockAllRemoteContentKey) as? Bool,
                       true)
        XCTAssertTrue(MessagesOptions.blockAllRemoteContent)
        MessagesOptions.blockAllRemoteContent = false
        XCTAssertFalse(MessagesOptions.blockAllRemoteContent)
        UserDefaults.standard.set("on", forKey: MessagesOptions.blockAllRemoteContentKey)
        XCTAssertFalse(MessagesOptions.blockAllRemoteContent)
        // Not a view setting a safe start takes back.
        XCTAssertFalse(SafeStart.viewSettings.contains(MessagesOptions.blockAllRemoteContentKey))
    }

    // MARK: - The markup

    /// Each place a page loads from: a picture, its sizes, a table's
    /// background, a style's `url()`, a style sheet, its `@import`, a
    /// `<base>`, SVG's picture, a video's poster and a picture's sources;
    /// in any case, with or without the slashes, quoted or not.
    func testAReferenceToTheWebIsFoundWhereAPageLoadsFrom() {
        for html in [
            "<img src=\"https://example.com/a.png\">",
            "<IMG SRC='HTTP://example.com/a.png'>",
            "<img src=https://example.com/a.png alt=x>",
            "<img src=\" https:example.com/a.png\">",
            "<img srcset=\"a.png 1x, https://example.com/a2.png 2x\">",
            "<table background=\"http://example.com/bg.png\"></table>",
            "<td style=\"background: url(https://example.com/bg.png)\">",
            "<div style='background-image:url(&quot;https://example.com/a.png&quot;)'>",
            "<style>p { background: url(\"https://example.com/a.png\") }</style>",
            "<style>@import \"https://example.com/more.css\";</style>",
            "<link rel=\"stylesheet\" href=\"https://example.com/a.css\">",
            "<base href=\"https://example.com/\"><img src=\"a.png\">",
            "<svg><image href=\"https://example.com/a.png\"/></svg>",
            "<svg><use xlink:href=\"https://example.com/s.svg#i\"/></svg>",
            "<svg><rect fill=\"url(https://example.com/s.svg#g)\"/></svg>",
            "<video poster=\"https://example.com/p.jpg\"></video>",
            "<picture><source srcset=\"https://example.com/a.webp\"><img src=\"cid:a\"></picture>",
            "<object data=\"https://example.com/a.swf\"></object>",
            "<iframe style=\"background:url(https://example.com/a.png)\" src=\"cid:x\"></iframe>",
        ] {
            XCTAssertTrue(RemoteContent.asksTheWeb(html), html)
        }
    }

    /// Not a link, his words, an address in them, a comment, the text of a
    /// script, a title or a frame, a frame's own address, which the pane
    /// cancels, a refresh, nor the letter's own pictures or one by `data:`;
    /// nor a scheme that only ends in the letters, or one held back already.
    func testLinksWordsCommentsAndOwnPicturesAskTheWebForNothing() {
        for html in [
            "<a href=\"https://example.com/\">https://example.com/</a>",
            "<area href=\"http://example.com/\">",
            "<svg><a xlink:href=\"https://example.com/\"><text>x</text></a></svg>",
            "See https://example.com/page and http://example.com/other.",
            "<!-- <img src=\"https://example.com/a.png\"> -->",
            "<!--[if mso]><v:fill src=\"https://example.com/a.png\"/><![endif]-->",
            "<script src=\"cid:x\">var a = '<img src=\"https://example.com/a.png\">';</script>",
            "<title>https://example.com/</title>",
            "<textarea><img src=\"https://example.com/a.png\"></textarea>",
            "<iframe src=\"https://example.com/frame\"></iframe>",
            "<meta http-equiv=\"refresh\" content=\"0;url=https://example.com/\">",
            "<img src=\"cid:logo@example.com\"><img src=\"bmcid://logo\">",
            "<img src=\"data:image/png;base64,AAAA\">",
            "<img src=\"xhttps://example.com/a.png\"><img src=\"web+http://example.com\">",
            "<img src=\"bmoffhttps://example.com/a.png\">",
            "<p>5 < 6 and https: as a word</p>",
            "",
        ] {
            XCTAssertFalse(RemoteContent.asksTheWeb(html), html)
            XCTAssertEqual(RemoteContent.blocked(html), html, html)
        }
    }

    /// Held back: `bmoff` before each reference and nowhere else, so the
    /// markup with it taken out is the letter's own again; twice is once.
    func testBlockedHoldsBackEachReferenceAndChangesNothingElse() {
        let held = RemoteContent.blocked(newsletter)
        XCTAssertEqual(held.components(separatedBy: "bmoffhttp").count - 1, 4)
        for reference in ["background=\"bmoffhttps://cdn.example.com/bg.png\"",
                          "src=\"bmoffhttps://cdn.example.com/hero.jpg\"",
                          "url('bmoffhttps://cdn.example.com/dots.png')",
                          "src=\"bmoffhttp://track.example.com/open.gif?u=1\""] {
            XCTAssertTrue(held.contains(reference), reference)
        }
        // The link, the words and the picture of its own are as they were.
        XCTAssertTrue(held.contains("<a href=\"https://example.com/read\">Read on</a> "
                                    + "or see https://example.com/words"))
        XCTAssertTrue(held.contains("<img src=\"cid:logo@example.com\">"))
        XCTAssertEqual(held.replacingOccurrences(of: "bmoff", with: ""), newsletter)
        XCTAssertEqual(RemoteContent.blocked(held), held)
        XCTAssertEqual(RemoteContent.references(in: newsletter).count, 4)
        XCTAssertEqual(RemoteContent.references(in: newsletter, stoppingAtFirst: true).count, 1)
        // A tag left open, or a value never closed, ends the markup.
        XCTAssertEqual(RemoteContent.blocked("<img src=\"https://example.com/a"),
                       "<img src=\"bmoffhttps://example.com/a")
        XCTAssertEqual(RemoteContent.blocked("<style>a{b:url(http://e.com/x)"),
                       "<style>a{b:url(bmoffhttp://e.com/x)")
    }

    // MARK: - The pages

    /// On a page of its own, held back: Mail's line at the top of the
    /// letter, its button naming the letter, then the letter with nothing
    /// from the web in it, its own picture pointed at the loader, its link
    /// and its words' address made a link as ever.
    func testTheLetterHeldBackHasMailsLineAndItsOwnPicturesStill() throws {
        let m = letter(html: newsletter, attachments: [logo])
        let page = try XCTUnwrap(PanePage.letter(m, style: style, heldBack: true))
        let line = RemoteContent.line(for: "7/3")
        XCTAssertTrue(page.contains("<div id=\"bm\">" + line), page)
        XCTAssertTrue(line.contains(">Message contains unloaded images.</span>"))
        XCTAssertTrue(line.contains(">Load All Images</a></div>"))
        XCTAssertTrue(line.contains("href=\"bmimages:?letter=7/3\""), line)
        XCTAssertEqual(page.components(separatedBy: "Load All Images").count - 1, 1)
        for never in ["src=\"https:", "src=\"http:", "url('https:", "background=\"https:"] {
            XCTAssertFalse(page.contains(never), never)
        }
        XCTAssertTrue(page.contains("<img src=\"bmcid://logo%40example.com\">"))
        XCTAssertTrue(page.contains("<a href=\"https://example.com/read\">Read on</a>"))
        XCTAssertTrue(page.contains("<a href=\"https://example.com/words\">https://example.com/words</a>"))
    }

    /// Not held back, or held back with nothing from the web in it, a page
    /// is byte for byte the page it always was; so is a plain letter's,
    /// which never asks the web for anything.
    func testAPageNotHeldBackIsThePageItAlwaysWas() throws {
        let news = letter(html: newsletter, attachments: [logo])
        XCTAssertEqual(PanePage.letter(news, style: style, heldBack: false), PanePage.letter(news, style: style))
        XCTAssertTrue(try XCTUnwrap(PanePage.letter(news, style: style)).contains(
            "<img src=\"https://cdn.example.com/hero.jpg\" width=\"600\">"))
        let own = letter(html: "<p>Hello</p><img src=\"cid:logo@example.com\"><a href=\"https://e.com\">x</a>",
                         attachments: [logo])
        XCTAssertEqual(PanePage.letter(own, style: style, heldBack: true), PanePage.letter(own, style: style))
        let plain = letter(html: nil, text: "See https://example.com/a.png\n")
        XCTAssertEqual(PanePage.letter(plain, style: style, heldBack: true), PanePage.letter(plain, style: style))
        XCTAssertEqual(PanePage.held(plain, as: "7/3"), "")
    }

    /// In a stack, held back by its entry: the line at the top of its
    /// section naming the entry, his letter from Sent Mail by its "r", over
    /// a shortened letter's own line; nothing from the web. Not held back,
    /// the body it always was.
    func testAStackBodyHeldBackNamesItsEntry() {
        let m = letter(html: newsletter, attachments: [logo])
        let held = PanePage.stackBody(m, heldBack: "r7/3")
        XCTAssertTrue(held.isHTML)
        XCTAssertTrue(held.html.hasPrefix(RemoteContent.line(for: "r7/3")), held.html)
        XCTAssertTrue(held.html.contains("href=\"bmimages:?letter=r7/3\""))
        XCTAssertFalse(held.html.contains("src=\"https:"))
        XCTAssertTrue(held.html.contains("<img src=\"bmcid://logo%40example.com\">"))
        XCTAssertEqual(PanePage.stackBody(m, heldBack: nil), PanePage.stackBody(m))
        XCTAssertTrue(PanePage.stackBody(m).html.contains("src=\"https://cdn.example.com/hero.jpg\""))
        let plain = letter(html: nil, text: "Hello.")
        XCTAssertEqual(PanePage.stackBody(plain, heldBack: "7/3"), PanePage.stackBody(plain))
        let empty = letter(html: "<p> </p>")
        XCTAssertEqual(PanePage.stackBody(empty, heldBack: "7/3"), PanePage.stackBody(empty))
    }

    /// On paper, held back: nothing from the web, its own picture, and no
    /// line, the paper having no button; not held back, as ever.
    func testAPrintHeldBackHasNoLineAndNothingFromTheWeb() {
        let m = letter(html: newsletter, attachments: [logo])
        let print = PrintPage.Style(senderPointSize: 17, metaPointSize: 15, subjectPointSize: 17,
                                    bodyPointSize: 17, lineHeight: 1.41)
        let size: (Int64) -> String = { "\($0) bytes" }
        let held = PrintPage.made(m, style: print, size: size, heldBack: true)
        XCTAssertFalse(held.page.contains("src=\"https:"))
        XCTAssertTrue(held.page.contains("src=\"bmoffhttps://cdn.example.com/hero.jpg\""))
        XCTAssertFalse(held.page.contains(RemoteContent.unloaded))
        XCTAssertFalse(held.page.contains(RemoteContent.scheme))
        let shown = PrintPage.made(m, style: print, size: size)
        XCTAssertEqual(PrintPage.made(m, style: print, size: size, heldBack: false).page, shown.page)
        XCTAssertTrue(shown.page.contains("src=\"https://cdn.example.com/hero.jpg\""))
        XCTAssertEqual(held.words, shown.words)
    }

    // MARK: - The button

    /// A tap on the button loads the letter it names, by its id or its
    /// entry's, and goes nowhere; the same address not tapped, or naming no
    /// letter, goes nowhere and loads nothing.
    func testTheButtonLoadsTheLetterItNames() throws {
        for id in ["7/3", "r1234/56", "a b&c"] {
            let url = try XCTUnwrap(URL(string: RemoteContent.link(for: id)), id)
            XCTAssertEqual(RemoteContent.letter(of: url), id)
            XCTAssertEqual(PaneNavigation.decide(.linkActivated, mainFrame: true, url: url),
                           .loadImages(letter: id))
            XCTAssertEqual(PaneNavigation.decide(.linkActivated, mainFrame: nil, url: url),
                           .loadImages(letter: id))
            for kind: PaneNavigation.Kind in [.other, .formSubmitted, .reload, .unknown] {
                XCTAssertEqual(PaneNavigation.decide(kind, mainFrame: true, url: url), .cancel)
            }
        }
        for address in ["bmimages:", "bmimages:?letter=", "BMIMAGES:?other=7/3", "bmimages://x"] {
            let url = try XCTUnwrap(URL(string: address), address)
            XCTAssertNil(RemoteContent.letter(of: url), address)
            XCTAssertEqual(PaneNavigation.decide(.linkActivated, mainFrame: true, url: url), .cancel, address)
        }
        let other = try XCTUnwrap(URL(string: "https://example.com/?letter=7/3"))
        XCTAssertNil(RemoteContent.letter(of: other))
    }

    // MARK: - The state

    /// Held back under the setting until the letter's button, that letter
    /// alone; WebKit's list on until a letter of the page has been loaded;
    /// off, nothing held back and no list.
    func testRemotePicturesHoldsBackUntilItsButtonAndTheListThenComesOff() {
        var remote = RemotePictures()
        XCTAssertTrue(remote.holdsBack("7/3", blocking: true))
        XCTAssertTrue(remote.listOn(blocking: true))
        XCTAssertFalse(remote.holdsBack("7/3", blocking: false))
        XCTAssertFalse(remote.listOn(blocking: false))
        remote.load("7/3")
        XCTAssertFalse(remote.holdsBack("7/3", blocking: true))
        XCTAssertTrue(remote.holdsBack("7/4", blocking: true))
        XCTAssertTrue(remote.holdsBack("r7/3", blocking: true))
        XCTAssertFalse(remote.listOn(blocking: true))
        XCTAssertEqual(remote.loaded, ["7/3"])
        XCTAssertEqual(RemotePictures(), RemotePictures())
        // The setting read where none is handed in.
        UserDefaults.standard.removeObject(forKey: MessagesOptions.blockAllRemoteContentKey)
        XCTAssertFalse(RemotePictures().holdsBack("7/3"))
        MessagesOptions.blockAllRemoteContent = true
        XCTAssertTrue(RemotePictures().holdsBack("7/3"))
        XCTAssertTrue(RemotePictures().listOn())
    }

    /// WebKit's list: one rule, every request to `http:` or `https:` of any
    /// kind blocked, under its own name.
    func testWebKitsListBlocksEveryRequestToTheWeb() throws {
        XCTAssertEqual(RemoteContent.ruleListID, "blackmail.blockAllRemoteContent")
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(RemoteContent.ruleList.utf8)) as? [[String: [String: String]]])
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0]["trigger"], ["url-filter": "^https?:"])
        XCTAssertEqual(rules[0]["action"], ["type": "block"])
    }

    // MARK: - The wiring

    /// The pane: held back afresh at each thing it shows and as it empties,
    /// the list set before anything is given to the web view; each page
    /// and body built held back by the letter's id or its entry's; the
    /// button handled as a link of the pane's own, loading the letter on
    /// its own again from the top or the body in its section, the list off
    /// first; a print held back as the pane holds the letter. The list made
    /// once, and only once one is wanted on.
    func testThePaneHoldsBackWhatItShowsAndTheButtonLoadsOneLetter() throws {
        let pane = try source("UI/MessageDetailViewController.swift")
        for line in [
            "self.remoteList = RemoteBlockList(on: config.userContentController)",
            "func showEmpty() { loads.supersede() liftCover() holdBackTheWeb()",
            "private func holdBackTheWeb() { remote = RemotePictures() remoteList.on = remote.listOn() }",
            "prepare: { [style = pageStyle, held = remote.holdsBack(summary.id)] m in "
                + "(m, PanePage.letter(m, style: style, heldBack: held)) },",
            "let newestHeld = remote.holdsBack(newest.id) ? newest.id : nil",
            "prepare: { m in (m, PanePage.stackBody(m, heldBack: newestHeld)) },",
            "let held = remote.holdsBack(id) ? id : nil loads.start({ try await repository.openLetter(row) }, "
                + "prepare: { m in (m, PanePage.stackBody(m, heldBack: held)) },",
            "case .loadImages(let letter): decisionHandler(.cancel) loadImages(of: letter) }",
            "private func loadImages(of id: String) { guard remote.holdsBack(id) else { return } "
                + "if threadSummaries.isEmpty { guard let m = message, m.id == id else { return } "
                + "remote.load(id) remoteList.on = remote.listOn() let style = pageStyle "
                + "loads.start({ m }, prepare: { m in (m, PanePage.letter(m, style: style)) }, "
                + "settle: { [weak self] result in guard let self, case .success(let (m, page)) = result, "
                + "self.message?.id == m.id else { return } self.draw(m, page: page) }) return }",
            "guard let m = loaded[id] ?? related.letter(inSection: ConversationDocument.sectionID(for: id)) "
                + "else { return } remote.load(id) remoteList.on = remote.listOn() "
                + "loads.start({ m }, prepare: { m in PanePage.stackBody(m) }, "
                + "settle: { [weak self] result in guard case .success(let body) = result else { return } "
                + "self?.fill(id, body) }) }",
            "letter: m, heldBack: remote.holdsBack(m.id), repository: repository,",
        ] {
            XCTAssertTrue(pane.contains(line), line)
        }
        XCTAssertEqual(pane.components(separatedBy: "holdBackTheWeb()").count - 1, 4, "defined, emptied, two shows")
        XCTAssertEqual(pane.components(separatedBy: "PanePage.stackBody(m").count - 1, 4)
        XCTAssertEqual(pane.components(separatedBy: "remote.load(").count - 1, 2)

        let list = try source("UI/RemoteBlockList.swift")
        for line in [
            "guard let list = Self.made else { if on { Self.make(for: self) } return }",
            "if on, !added { controller.add(list) added = true } else if !on, added { "
                + "controller.remove(list) added = false }",
            "guard !making, let store = WKContentRuleListStore.default() else { return } making = true",
            "store.compileContentRuleList(forIdentifier: RemoteContent.ruleListID, "
                + "encodedContentRuleList: RemoteContent.ruleList)",
        ] {
            XCTAssertTrue(list.contains(line), line)
        }
        let job = try source("UI/LetterPrint.swift")
        XCTAssertTrue(job.contains("PrintPage.made(m, style: style, size: size, heldBack: heldBack)"))
        XCTAssertTrue(job.contains("if heldBack, let list = RemoteBlockList.list { "
                                   + "config.userContentController.add(list) }"))
    }

    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }
}
