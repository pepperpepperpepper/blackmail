import XCTest
@testable import Blackmail

/// A large letter's files come as it opens, as Mail's do (B-176): Mail on
/// the test iPad fetched a large letter's files by itself, each tile with
/// a ring and "Downloading" while its file came (round r6-i-compare,
/// C-13e); Blackmail's tiles said "Tap to Download" until he tapped one.
/// Which files, where each stands, the tile and the page's script are run
/// here; the pane, UIKit, is read from its source.
final class FilesAheadTests: XCTestCase {

    private let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)

    private func file(_ id: String, _ name: String, _ type: String, size: Int64?) -> Attachment {
        Attachment(id: id, filename: name, mimeType: type, size: size)
    }

    private func letter(_ files: [Attachment], left: Bool = true, html: String? = nil) -> Message {
        var m = Message(id: "7/3", mailboxID: "INBOX", sender: "Xan Files <xan@example.com>",
                        senderAddress: "xan@example.com", to: [], cc: [], subject: "Large",
                        date: Date(timeIntervalSince1970: 1_792_679_717), textBody: "The words.",
                        htmlBody: html, attachments: files)
        m.filesLeftOnServer = left
        return m
    }

    private var pdf: Attachment { file("4", "R6 B-170 large.pdf", "application/pdf", size: 316_000) }

    // MARK: - Which files

    /// The files of a letter opened without them that its page draws as
    /// tiles, in its order, each no larger than a letter fetched whole
    /// (`most`, 5 MB): not a picture, which the page asks for itself, not
    /// one too large or of no size known, which wait for a tap; and none
    /// of a letter fetched whole.
    func testWhichFilesComeAsTheLetterOpens() {
        XCTAssertEqual(FilesAhead.most, 5 << 20)
        let photo = file("2", "l-photo-1.jpg", "image/jpeg", size: 3_500_000)
        let heic = file("3", "IMG_1.HEIC", "image/heic", size: 2_300_000)
        let doc = file("5", "notes.docx", "application/octet-stream", size: FilesAhead.most)
        let huge = file("6", "scan.pdf", "application/pdf", size: FilesAhead.most + 1)
        let unknown = file("7", "a.ics", "text/calendar", size: nil)
        let m = letter([photo, heic, pdf, doc, huge, unknown])
        XCTAssertEqual(FilesAhead.planned(m), [pdf, doc])
        for (f, comes) in [(photo, false), (heic, false), (pdf, true), (doc, true), (huge, false), (unknown, false)] {
            XCTAssertEqual(FilesAhead.fetches(f, of: m), comes, f.filename)
        }
        XCTAssertEqual(FilesAhead.planned(letter([pdf, doc], left: false)), [])
        XCTAssertFalse(FilesAhead.fetches(pdf, of: letter([pdf], left: false)))

        // Shown in part: the files it lists, as its page draws them.
        let shown = Attachment(id: "8", filename: "inline.pdf", mimeType: "application/pdf", size: 900,
                               contentID: "x", isInline: true)
        var cut = letter([pdf, shown])
        XCTAssertEqual(FilesAhead.planned(cut), [pdf, shown])
        cut.isShortened = true
        XCTAssertEqual(cut.listedAttachments, [pdf, shown].filter { !$0.isShownInBody })
        XCTAssertEqual(FilesAhead.planned(cut), cut.listedAttachments.filter { FilesAhead.fetches($0, of: cut) })
    }

    /// The tile of a file coming as the letter opens says "Downloading"
    /// with Mail's ring in its icon's place, in the icon's box, so nothing
    /// in the tile moves; one too large says "Tap to Download" with its
    /// icon; on paper neither. On a letter's own page and in a stack's body.
    func testItsTileSaysDownloadingWithTheRing() throws {
        let huge = file("6", "scan.pdf", "application/pdf", size: FilesAhead.most + 1)
        let m = letter([pdf, huge])
        let page = try XCTUnwrap(PanePage.letter(m, style: style))
        let coming = BodyFiles.tile(pdf, of: m, on: .dark)
        XCTAssertTrue(page.contains(coming))
        XCTAssertTrue(coming.contains(BodyFiles.ring + "<span"))
        XCTAssertTrue(coming.contains(">Downloading</span></span></a>"))
        XCTAssertTrue(PanePage.stackBody(m).html.contains(">Downloading</span></span></a>"))
        let waits = BodyFiles.tile(huge, of: m, on: .dark)
        XCTAssertTrue(page.contains(waits))
        XCTAssertTrue(waits.contains(">Tap to Download</span></span></a>"))
        XCTAssertFalse(waits.contains("bm-file-ring"))
        XCTAssertFalse(BodyFiles.tile(pdf, of: m, on: .paper).contains("bm-file-ring"))

        // The ring in the icon's own box: 37 by 48, 8 under it, as the icon.
        let box = "width=\"37\" height=\"48\" viewBox=\"0 0 37 48\" style=\"display: block; margin: 0 auto 8px auto;\""
        XCTAssertTrue(BodyFiles.ring.hasPrefix("<svg class=\"bm-file-ring\" " + box + ">"))
        XCTAssertTrue(BodyFiles.icon(pdf).hasPrefix("<svg " + box + ">"))
        XCTAssertTrue(BodyFiles.ring.contains("stroke=\"currentColor\""))
        XCTAssertTrue(BodyFiles.ring.contains("animation: bm-file-turn 1s linear infinite"), "turning, by no script")
        XCTAssertFalse(BodyFiles.ring.contains("<script"))
        XCTAssertEqual(BodyFiles.downloading, "Downloading")

        let landed = BodyFiles.Landed(pdf, of: m.id, inHand: true)
        XCTAssertEqual(landed.link, BodyFiles.link("4", of: "7/3"))
        XCTAssertEqual(landed.icon, BodyFiles.icon(pdf))
        XCTAssertEqual(landed.words, "\u{00A0}", "says nothing, its line kept")
        XCTAssertEqual(BodyFiles.saysNothing.unicodeScalars.map(\.value), [0xA0], "a no-break space, never collapsed")
        XCTAssertEqual(BodyFiles.Landed(pdf, of: m.id, inHand: false).words, "Tap to Download")
        XCTAssertEqual(BodyFiles.Landed.script,
                       "if (typeof bmFileLanded === 'function') bmFileLanded(link, icon, words); "
                       + "else (window.bmFilesWaiting = window.bmFilesWaiting || []).push([link, icon, words]);")
    }

    /// The ring turns from its first frame, the one drawn with the page
    /// as the one a tap puts in by script (found on the test iPad,
    /// 2026-10-28): by CSS, its rule and keyframes in the drawing's own
    /// `<style>`, which both carry, and not by SMIL, whose animations in
    /// SVG parsed with the page WebKit starts only at the page's load
    /// event, after the letter's pictures; on 16.5.1 the large letter's
    /// ring stood still while its photos came. Once a second, steadily,
    /// about the drawing's middle, which is the circle's centre, so the
    /// grey circle turned looks as it was; the drawing's box, size and
    /// place as before. On paper no ring.
    func testTheRingTurnsFromItsFirstFrame() throws {
        let ring = BodyFiles.ring
        XCTAssertFalse(ring.contains("<animate"), "no SMIL")
        XCTAssertFalse(ring.contains("repeatCount"))
        XCTAssertFalse(ring.contains("<script"))
        let box = "<svg class=\"bm-file-ring\" width=\"37\" height=\"48\" viewBox=\"0 0 37 48\""
            + " style=\"display: block; margin: 0 auto 8px auto;\">"
        XCTAssertTrue(ring.hasPrefix(box + "<style>@keyframes bm-file-turn { to { transform: rotate(360deg); } }"
                                     + " svg.bm-file-ring { animation: bm-file-turn 1s linear infinite !important; }"
                                     + "</style><circle "), ring)
        XCTAssertEqual(BodyFiles.ringTurn, "bm-file-turn")
        XCTAssertEqual(ring.components(separatedBy: "<style>").count - 1, 1)
        XCTAssertEqual(ring.components(separatedBy: "animation:").count - 1, 1)
        XCTAssertTrue(ring.contains("<circle cx=\"18.5\" cy=\"24\" r=\"14\""), "the middle of 37 by 48")
        XCTAssertTrue(ring.hasSuffix("<path d=\"M18.5 10A14 14 0 0 1 32.5 24\" fill=\"none\" stroke=\"currentColor\""
                                     + " stroke-width=\"2\" stroke-linecap=\"round\"></path></svg>"))

        // The page as loaded, a stack's body and a tap's script all carry
        // the same drawing, rule and all; paper none.
        let m = letter([pdf])
        let page = try XCTUnwrap(PanePage.letter(m, style: style))
        XCTAssertEqual(page.components(separatedBy: ring).count - 1, 1)
        XCTAssertEqual(PanePage.stackBody(m).html.components(separatedBy: ring).count - 1, 1)
        XCTAssertEqual(BodyFiles.Busy("4", of: m.id, busy: true).arguments["ring"] as? String, ring)
        XCTAssertFalse(BodyFiles.tile(pdf, of: m, on: .paper).contains("bm-file-turn"))

        // Put in by the tap's script on the model of the page: the drawing
        // in the icon's place is the ring.
        let tapped = letter([pdf], left: false)
        let drawn = try XCTUnwrap(PanePage.letter(tapped, style: style))
        XCTAssertFalse(drawn.contains("bm-file-turn"), "a letter fetched whole: its icon")
        let run = try model(drawn, [.busy(50, BodyFiles.Busy("4", of: tapped.id, busy: true))])
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.files.map(\.icon), ["bm-file-ring"])
    }

    // MARK: - Where each stands

    /// A file drawn is fetched once, in its turn; drawn again while it
    /// comes, nothing; come, or not, its tile is made so. A tap reads one
    /// come, waits for one coming, and fetches one whose turn has not come
    /// or that could not be, which then comes no second time in its turn;
    /// any other file is fetched as ever. The pane given something else,
    /// every file is forgotten, those come handed back to be removed, and
    /// one that comes after is not kept.
    func testWhereEachFileStands() {
        var ahead = FilesAhead()
        let a = FilesAhead.Key(letter: "7/3", part: "4")
        let b = FilesAhead.Key(letter: "7/3", part: "5")
        let c = FilesAhead.Key(letter: "7/3", part: "6")
        XCTAssertEqual(ahead.drawn(a), .fetch)
        XCTAssertEqual(ahead.drawn(a), .nothing, "drawn again: waiting")
        XCTAssertEqual(ahead.drawn(b), .fetch)
        XCTAssertTrue(ahead.turn(a))
        XCTAssertFalse(ahead.turn(a), "once")
        XCTAssertEqual(ahead.drawn(a), .nothing, "coming")
        XCTAssertEqual(ahead.taking(a), .wait)
        let url = URL(fileURLWithPath: "/staged/1/R6 B-170 large.pdf")
        XCTAssertTrue(ahead.landed(a, at: url))
        XCTAssertEqual(ahead.drawn(a), .show(inHand: true))
        XCTAssertEqual(ahead.taking(a), .read(url))

        XCTAssertEqual(ahead.taking(b), .fetch(lands: true), "its turn not come: the tap's")
        XCTAssertFalse(ahead.turn(b), "taken by the tap")
        XCTAssertEqual(ahead.taking(b), .wait)
        ahead.failed(b)
        XCTAssertEqual(ahead.drawn(b), .show(inHand: false))
        XCTAssertEqual(ahead.taking(b), .fetch(lands: true), "failed: fetched for a tap")

        XCTAssertEqual(ahead.taking(c), .fetch(lands: false), "not planned")
        XCTAssertEqual(ahead.states[c], nil)

        // Tapped before the pane asked for it: the tap's, and not fetched
        // again when the pane asks for its letter's files. A guard: the
        // pane asks for them as it gives the page or the body, before a
        // tile can be tapped.
        let d = FilesAhead.Key(letter: "7/3", part: "7")
        XCTAssertEqual(ahead.taking(d, planned: true), .fetch(lands: true), "planned, not yet asked for")
        XCTAssertEqual(ahead.drawn(d), .nothing, "the pane asks for its letter's files: coming, the tap's")
        XCTAssertFalse(ahead.turn(d))
        XCTAssertTrue(ahead.landed(d, at: nil))
        XCTAssertEqual(ahead.drawn(d), .show(inHand: false))
        XCTAssertFalse(ahead.landed(c, at: url))
        ahead.failed(c)
        XCTAssertEqual(ahead.states[c], nil)

        XCTAssertEqual(ahead.forget(), [url])
        XCTAssertEqual(ahead.states, [:])
        XCTAssertFalse(ahead.landed(a, at: url), "come after: removed, not kept")
        XCTAssertEqual(ahead.drawn(a), .fetch, "a new page: fetched again")
        XCTAssertTrue(ahead.landed(a, at: nil))
        XCTAssertEqual(ahead.states[a], .failed, "not written: as not fetched")
    }

    // MARK: - The page's script

    /// The script, run in node on the model of the page: the tile drawn
    /// coming keeps its ring and "Downloading" until the pane says the file
    /// has come, and then has its icon and says nothing, as a tile of a
    /// letter fetched whole, its last line still there, a no-break space,
    /// so the lines above it stay where they were; or, not fetched, its
    /// icon and "Tap to Download". A tap on it while it comes leaves it so, and as the tap
    /// ends it is as the file left it. A tap on it after shows the ring
    /// and "Downloading", and then the icon again. Another letter's file
    /// changes nothing.
    func testTheTileComesAsTheFileComes() throws {
        let m = letter([pdf])
        let page = try XCTUnwrap(PanePage.letter(m, style: style))
        let link = BodyFiles.link("4", of: m.id)
        let coming = ModelPage.Run.File(href: link, style: [:], status: "Downloading", icon: "bm-file-ring")
        let inHand = ModelPage.Run.File(href: link, style: [:], status: "\u{00A0}", icon: "")
        let failed = ModelPage.Run.File(href: link, style: [:], status: "Tap to Download", icon: "")
        let landed = BodyFiles.Landed(pdf, of: m.id, inHand: true)
        let notLanded = BodyFiles.Landed(pdf, of: m.id, inHand: false)
        let tap = BodyFiles.Busy("4", of: m.id, busy: true)
        let done = BodyFiles.Busy("4", of: m.id, busy: false)

        var run = try model(page, [])
        XCTAssertEqual(run.files, [coming], "drawn coming")
        run = try model(page, [.landed(100, landed)])
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.files, [inHand])
        run = try model(page, [.landed(100, notLanded)])
        XCTAssertEqual(run.files, [failed])
        run = try model(page, [.landed(100, BodyFiles.Landed(pdf, of: "7/9", inHand: true))])
        XCTAssertEqual(run.files, [coming], "another letter's")

        run = try model(page, [.busy(50, tap), .landed(100, landed)])
        XCTAssertEqual(run.files, [coming], "the tap's still")
        run = try model(page, [.busy(50, tap), .landed(100, landed), .busy(200, done)])
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.files, [inHand], "as the file left it")
        run = try model(page, [.busy(50, tap), .landed(100, notLanded), .busy(200, done)])
        XCTAssertEqual(run.files, [failed])
        run = try model(page, [.landed(50, landed), .busy(100, tap)])
        XCTAssertEqual(run.files, [coming], "tapped after: the ring")
        run = try model(page, [.landed(50, landed), .busy(100, tap), .busy(200, done)])
        XCTAssertEqual(run.files, [inHand])

        // In a stack's body.
        let entry = ConversationDocument.Entry(id: m.id, sender: m.sender, date: m.date,
                                               body: nil, isExpanded: true, preview: "Large")
        let stack = ConversationDocument.html(entries: [entry], inset: 20, bodyPointSize: 17, lineHeight: 1.4)
        let fill = ConversationDocument.Fill(sectionID: ConversationDocument.sectionID(for: m.id),
                                             body: PanePage.stackBody(m))
        run = try model(stack, [.fill(50, fill), .landed(100, landed)])
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.files, [inHand])
    }

    // MARK: - The pane

    /// The pane, read: a letter's own page loaded, or a body put in its
    /// section, has its files fetched as it opens; each after the one
    /// before, in its turn, by its section, as a tap fetches it, not once
    /// the pane shows something else; what came written to the iPad and
    /// its tile told, or, not fetched, told so; a tap's bytes through
    /// `fileData`, which reads, waits or fetches as `FilesAhead` says, a
    /// file to come and not yet asked for kept as the tap's, and nothing
    /// fetched after a wait once the pane has been given something else
    /// (the tap let go with nothing said, as `openAttachment`'s catch
    /// says nothing for a pane moved on); and
    /// the pane given something else, every fetch called off and what came
    /// removed. The pane's loads tell it so after calling off their own.
    func testThePaneFetchesThemAndLetsThemGo() throws {
        let pane = try source("UI/MessageDetailViewController.swift")
        for wiring in [
            "loads.superseded = { [weak self] in self?.letAheadGo() }",
            "load(page, as: .letter(m, page: page), anew: anew) fetchAhead(m) }",
            "if let m = loaded.values.first(where: { ConversationDocument.sectionID(for: $0.id) == fill.sectionID }) "
                + "?? related.letter(inSection: fill.sectionID) { fetchAhead(m) }",
            "for file in FilesAhead.planned(m) { let key = FilesAhead.Key(letter: m.id, part: file.id) "
                + "switch ahead.drawn(key) { case .fetch: aheadFetches[key] = fetchAhead(file, of: m, key: key, "
                + "shown: shown) case .show(let inHand): run(BodyFiles.Landed(file, of: m.id, inHand: inHand)) "
                + "case .nothing: break } }",
            "let before = aheadLast",
            "await before?.value guard let self, !Task.isCancelled, self.loads.stillShows(shown), "
                + "self.ahead.turn(key) else { return }",
            "let data = try await repository.fetchAttachmentData(file.id, of: m.id, mailboxID: m.mailboxID) "
                + "guard !Task.isCancelled, self.loads.stillShows(shown) else { return } "
                + "self.land(data, file, of: m, key: key)",
            "self.ahead.failed(key) self.run(BodyFiles.Landed(file, of: m.id, inHand: false))",
            "aheadLast = fetch return fetch",
            "let url = try? AttachmentStore.write(data, named: file.filename) "
                + "guard ahead.landed(key, at: url) else { if let url { AttachmentStore.removeStaged(url) } return } "
                + "run(BodyFiles.Landed(file, of: m.id, inHand: url != nil))",
            "var taking = ahead.taking(key, planned: FilesAhead.fetches(file, of: m)) "
                + "if taking == .wait { await aheadFetches[key]?.value "
                + "guard loads.stillShows(shown) else { throw CancellationError() } "
                + "taking = ahead.taking(key) } "
                + "if case let .read(url) = taking, let data = try? Data(contentsOf: url) { return data }",
            "let data = try await fileData(attachment, of: m, shown: shown)",
            "} catch { guard loads.stillShows(shown), fileTaps.opens(file) else { return } "
                + "ErrorPresenter.show(.attachmentFailed, on: self) }",
            "for fetch in aheadFetches.values { fetch.cancel() } aheadFetches = [:] aheadLast?.cancel() "
                + "aheadLast = nil for url in ahead.forget() { AttachmentStore.removeStaged(url) }",
            "private func run(_ landed: BodyFiles.Landed) { guard let landed = document.tile(landed) "
                + "else { return } tell(landed) } private func tell(_ landed: BodyFiles.Landed) { "
                + "webView.callAsyncJavaScript(BodyFiles.Landed.script, arguments: landed.arguments, "
                + "in: nil, in: .defaultClient) }",
        ] {
            XCTAssertTrue(pane.contains(wiring), wiring)
        }
        XCTAssertEqual(pane.components(separatedBy: "repository.fetchAttachmentData(").count - 1, 3,
                       "the ahead fetch, a tap's in fileData, and the loader's")
        let loads = try source("Mail/PaneLoads.swift")
        XCTAssertTrue(loads.contains("running = [:] for task in called { task.cancel() } superseded?() }"))
    }

    /// A tile tapped while it says "Downloading", before its letter's page
    /// has finished, and then another letter opened (the check's step 6,
    /// found on the test iPad, 2026-10-28): the large letter's PDF was
    /// FETCHed 1.1 s after the other letter was shown, as the photo on the
    /// wire ended. That FETCH was the tap's, asked for at the tap, before
    /// the pane moved on, and waiting its turn on the one connection
    /// behind the page's photo: `fileData` asks the repository at once for
    /// a file to come and not yet asked for, nothing awaited before it but
    /// a fetch ahead already running, and a tap's download is never called
    /// off (B-122), only the fetches ahead are; it ends, and is let go,
    /// nothing shown, written or said. What 60d5671 stopped, a fetch begun
    /// after a wait once the pane has moved on, is not this. Nor can one
    /// be: from the tap to `fileData` nothing is awaited, and `fileData`
    /// checks the pane first, for a pane given something else between the
    /// tap and its task, and after its one wait, nothing awaited between
    /// either check and the fetch. Read from the pane's source.
    func testATapsFetchAskedBeforeThePaneMovedOnEnds() throws {
        let pane = try source("UI/MessageDetailViewController.swift")
        let start = try XCTUnwrap(pane.range(of: "private func fileData("))
        let asked = try XCTUnwrap(pane.range(of: "let data = try await repository.fetchAttachmentData(",
                                             range: start.upperBound..<pane.endIndex))
        let before = String(pane[start.upperBound..<asked.lowerBound])
        XCTAssertEqual(before.components(separatedBy: "await").count - 1, 1, before)
        XCTAssertTrue(before.contains("if taking == .wait { await aheadFetches[key]?.value "
                                      + "guard loads.stillShows(shown) else { throw CancellationError() }"), before)
        XCTAssertFalse(before.contains("Task.yield"))
        XCTAssertTrue(before.hasPrefix("_ file: Attachment, of m: Message, shown: Int) async throws -> Data { "
                                       + "guard loads.stillShows(shown) else { throw CancellationError() } "
                                       + "let key = FilesAhead.Key(letter: m.id, part: file.id) "
                                       + "var taking = ahead.taking("), before)

        // From the tap to `fileData`, nothing awaited: not the files ahead
        // (`aheadLast`), not a turn of the main actor.
        let tapped = try XCTUnwrap(pane.range(of: "filesOpening += 1 Task { @MainActor in"))
        let taken = try XCTUnwrap(pane.range(of: "let data = try await fileData(attachment, of: m, shown: shown)",
                                             range: tapped.upperBound..<pane.endIndex))
        let path = String(pane[tapped.upperBound..<taken.lowerBound])
        XCTAssertFalse(path.contains("await"), path)
        XCTAssertTrue(path.hasSuffix("self.run(BodyFiles.Busy(attachment.id, of: m.id, busy: false)) } do { "), path)

        // The tap's task is the pane's to forget, not to call off: nothing
        // keeps it, and the pane given something else cancels only the
        // fetches ahead.
        XCTAssertTrue(pane.contains("filesOpening += 1 Task { @MainActor in"))
        XCTAssertFalse(pane.contains("= Task { @MainActor in var handedOver"))
        XCTAssertEqual(pane.components(separatedBy: ".cancel()").count - 1, 2, "the fetches ahead alone")
        XCTAssertTrue(pane.contains("private func letAheadGo() { for fetch in aheadFetches.values { fetch.cancel() } "
                                    + "aheadFetches = [:] aheadLast?.cancel()"))
        XCTAssertTrue(pane.contains("let data = try await fileData(attachment, of: m, shown: shown) "
                                    + "guard loads.stillShows(shown) else { return }"))
    }

    /// A letter's own page asks for its files as its words go in, as a
    /// stack's body does, and not once the page has loaded, which waits
    /// for its pictures (found on the test iPad, 2026-10-28: the large
    /// letter's PDF was FETCHed after both of its photos; Mail, C-13e, had
    /// the PDF drawn while a photo still came). Read from the pane: the
    /// loader pointed at the letter's pictures, the page given to WebKit,
    /// and its files asked for at once, nothing awaited before the first
    /// file's fetch, so it is asked before the page has finished and
    /// usually before WebKit has asked for a picture; then each in its turn
    /// on the one line, first come first served with the pictures
    /// (`ExchangeGateTests`), so B-160's and B-151's go between two files;
    /// the page finished asks for nothing. Only these two ask for files.
    /// And on the pane's document, each file asked once.
    func testALettersOwnPageAsksForItsFilesAsItsWordsGoIn() throws {
        let pane = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(pane.contains("private func draw(_ m: Message, page: String?, anew: Bool = false) { "
                                    + "prepareInlineImages(for: [m]) "
                                    + "guard let page else { renderNotice(MailText.emptyBodyNotice) return } "
                                    + "load(page, as: .letter(m, page: page), anew: anew) fetchAhead(m) }"))
        XCTAssertEqual(pane.components(separatedBy: "fetchAhead(m)").count - 1, 2, "the page given, and a body in")
        XCTAssertTrue(pane.contains("webView.callAsyncJavaScript(ConversationDocument.Fill.script, "
                                    + "arguments: fill.arguments, in: nil, in: .defaultClient)"))

        let finish = try XCTUnwrap(pane.range(of: "func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {"))
        let finishEnd = try XCTUnwrap(pane.range(of: "func webViewWebContentProcessDidTerminate(",
                                                 range: finish.upperBound..<pane.endIndex))
        let finished = String(pane[finish.upperBound..<finishEnd.lowerBound])
        XCTAssertFalse(finished.contains("fetchAhead"), finished)
        XCTAssertTrue(finished.contains("for landed in finished.tiles { tell(landed) } }"), finished)

        // From the page given to the first file's FETCH, nothing awaited
        // but the file before it, which the first has none of.
        let ahead = try XCTUnwrap(pane.range(of: "let fetch = Task { @MainActor [weak self] in"))
        let asked = try XCTUnwrap(pane.range(of: "let data = try await repository.fetchAttachmentData(",
                                             range: ahead.upperBound..<pane.endIndex))
        let before = String(pane[ahead.upperBound..<asked.lowerBound])
        XCTAssertEqual(before.components(separatedBy: "await").count - 1, 1, before)
        XCTAssertTrue(before.hasPrefix(" await before?.value guard let self, !Task.isCancelled, "
                                       + "self.loads.stillShows(shown), self.ahead.turn(key) else { return } do { "),
                      before)
        XCTAssertTrue(pane.contains("let before = aheadLast let repository = self.repository"))

        // Asked once, and not again when drawn again: a letter's page
        // given to the pane's document, each of its files asked for as
        // `fetchAhead` asks (`drawn`); the page committed and finished
        // handing nothing back to ask for; drawn again, nothing more. The
        // order, the files asked before the page's load ends, is pinned
        // from the pane's source above, not here.
        final class Navigation {}
        let page = Navigation()
        let m = letter([pdf, file("5", "notes.docx", "application/octet-stream", size: 9_000)])
        var document = PaneDocument()
        var files = FilesAhead()
        document.loaded(.letter(m, page: "<p>x</p>"), navigation: ObjectIdentifier(page))
        XCTAssertEqual(FilesAhead.planned(m).map { files.drawn(.init(letter: m.id, part: $0.id)) },
                       [.fetch, .fetch], "the page given: each asked")
        XCTAssertEqual(document.didCommit(ObjectIdentifier(page)), [])
        XCTAssertEqual(document.didFinish(ObjectIdentifier(page)), PaneDocument.Finished(),
                       "the page finished: nothing handed back")
        XCTAssertEqual(FilesAhead.planned(m).map { files.drawn(.init(letter: m.id, part: $0.id)) },
                       [.nothing, .nothing], "drawn again: asked once")
    }

    /// A file asked for as its letter's page goes in can come before
    /// WebKit has committed the page, when a script would run in the page
    /// before it and its tile say "Downloading" for good, or before the
    /// page's own script has run, at its document's end, with no
    /// `bmFileLanded` to call. Neither is lost. The pane holds the tile's
    /// script until the page given last is committed, and hands it back
    /// then, once, in its order (`PaneDocument.tile`, `didCommit`), or at
    /// its end should the commit not be heard; another page given first
    /// takes the held ones with it, its tiles told afresh as the pane
    /// gives it (`FilesAhead.drawn`); a page with no navigation, or one
    /// committed, runs it at once; WebKit's process lost, held. And the
    /// script, run before the page's own, keeps it, which the page's script
    /// tells as it ends: on the model of the page the tile has its icon and
    /// says nothing, or "Tap to Download", as when it lands later, a tap
    /// after it as ever. The pane, read: every tile's script through the
    /// hold, told at the commit and at the end.
    func testAFileLandingBeforeThePageIsReadyIsDrawnOnceItIs() throws {
        final class Navigation {}
        let m = letter([pdf])
        let landed = BodyFiles.Landed(pdf, of: m.id, inHand: true)
        let other = BodyFiles.Landed(file("5", "notes.docx", "application/octet-stream", size: 9), of: m.id,
                                     inHand: false)
        let first = Navigation(), second = Navigation(), third = Navigation()
        var document = PaneDocument()
        XCTAssertEqual(document.tile(landed), landed, "nothing given yet: at once")
        document.loaded(.letter(m, page: "<p>x</p>"), navigation: ObjectIdentifier(first))
        XCTAssertNil(document.tile(landed), "not committed: held")
        XCTAssertNil(document.tile(other))
        XCTAssertEqual(document.didCommit(ObjectIdentifier(second)), [], "another page's")
        XCTAssertEqual(document.didCommit(ObjectIdentifier(first)), [landed, other], "in their order")
        XCTAssertEqual(document.didCommit(ObjectIdentifier(first)), [], "once")
        XCTAssertEqual(document.tile(landed), landed, "committed: at once")
        XCTAssertEqual(document.didFinish(ObjectIdentifier(first)), PaneDocument.Finished())

        document.loaded(.letter(m, page: "<p>x</p>"), navigation: ObjectIdentifier(second))
        XCTAssertNil(document.tile(landed))
        document.loaded(.letter(m, page: "<p>y</p>"), navigation: ObjectIdentifier(third))
        XCTAssertEqual(document.didCommit(ObjectIdentifier(third)), [], "gone with the page it was held for")
        document.loaded(.letter(m, page: "<p>x</p>"), navigation: ObjectIdentifier(first))
        XCTAssertNil(document.tile(other))
        XCTAssertEqual(document.didFinish(ObjectIdentifier(first)).tiles, [other], "the commit not heard")
        XCTAssertEqual(document.tile(landed), landed)

        document.loaded(.notice(["Loading…"]), navigation: nil)
        XCTAssertEqual(document.tile(landed), landed, "no navigation: at once")
        document.loaded(.letter(m, page: "<p>x</p>"), navigation: ObjectIdentifier(second))
        _ = document.didCommit(ObjectIdentifier(second))
        document.contentProcessEnded()
        XCTAssertNil(document.tile(landed), "WebKit's process lost: held for no page")

        // Before the page's own script: kept, and told as it ends.
        let page = try XCTUnwrap(PanePage.letter(m, style: style))
        let link = BodyFiles.link("4", of: m.id)
        let inHand = ModelPage.Run.File(href: link, style: [:], status: "\u{00A0}", icon: "")
        let failed = ModelPage.Run.File(href: link, style: [:], status: "Tap to Download", icon: "")
        let coming = ModelPage.Run.File(href: link, style: [:], status: "Downloading", icon: "bm-file-ring")
        var run = try model(page, [.landed(-1, landed)])
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.files, [inHand])
        run = try model(page, [.landed(-1, BodyFiles.Landed(pdf, of: m.id, inHand: false))])
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.files, [failed])
        run = try model(page, [.landed(-2, BodyFiles.Landed(pdf, of: m.id, inHand: false)), .landed(-1, landed)])
        XCTAssertEqual(run.files, [inHand], "in their order")
        run = try model(page, [.landed(-1, BodyFiles.Landed(pdf, of: "7/9", inHand: true))])
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.files, [coming], "another letter's")
        let tap = BodyFiles.Busy("4", of: m.id, busy: true), done = BodyFiles.Busy("4", of: m.id, busy: false)
        run = try model(page, [.landed(-1, landed), .busy(50, tap)])
        XCTAssertEqual(run.files, [coming], "tapped after: the ring")
        run = try model(page, [.landed(-1, landed), .busy(50, tap), .busy(100, done)])
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.files, [inHand])
        let script = ConversationDocument.script
        XCTAssertTrue(script.hasSuffix("""
            (function () {
              var waiting = window.bmFilesWaiting;
              window.bmFilesWaiting = null;
              if (!waiting) return;
              for (var i = 0; i < waiting.length; i++) bmFileLanded(waiting[i][0], waiting[i][1], waiting[i][2]);
            })();
            """), "told as the script ends, with everything it needs defined")

        // The pane, read.
        let pane = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(pane.contains("func webView(_ w: WKWebView, didCommit navigation: WKNavigation!) { "
                                    + "guard let navigation else { return } "
                                    + "paneCover.committed(ObjectIdentifier(navigation)) "
                                    + "for landed in document.didCommit(ObjectIdentifier(navigation)) { tell(landed) } }"))
        XCTAssertEqual(pane.components(separatedBy: "tell(landed)").count - 1, 3, "the hold, the commit, the end")
        XCTAssertEqual(pane.components(separatedBy: "BodyFiles.Landed.script").count - 1, 1)
    }

    // MARK: - Helpers

    private func model(_ page: String, _ steps: [ModelPage.Step], end: Int = 400) throws -> ModelPage.Run {
        do {
            return try ModelPage.run(ConversationDocument.script, page: page, steps: steps, end: end)
        } catch is ModelPage.NoNode {
            throw XCTSkip("node is not on this host")
        }
    }

    /// A file under `Sources/Blackmail`, comments out and its white space
    /// one space.
    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/" + file)
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }
}
