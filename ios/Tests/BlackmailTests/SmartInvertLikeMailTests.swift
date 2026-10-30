import XCTest
@testable import Blackmail

/// A letter in the reading pane under the iPad's Smart Invert as Mail's
/// comes out under it (B-179), as the comparison with Mail 16.5.1 on the
/// test iPad of 2026-10-29 found it (r6-n-compare, C-1d and C-1e): a
/// letter the pane inverts keeps its invert and its photos have no
/// filter; a light letter's sheet is inverted plainly, its pictures with
/// no filter of the pane's, Mail's line over it inverted back; a plain
/// letter, one in its own colours and every page with the switch off are
/// as they were, byte for byte.
final class SmartInvertLikeMailTests: XCTestCase {

    private let off = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)
    private let on = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41, smartInvert: true)

    private func letter(_ html: String?, text: String? = nil, id: String = "7/3",
                        files: [Attachment] = []) -> Message {
        Message(id: id, mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                senderAddress: "sam@example.com", to: ["me@example.com"], cc: [],
                subject: "The garden", date: Date(timeIntervalSince1970: 1_790_000_000),
                textBody: text, htmlBody: html, attachments: files)
    }

    /// A letter Mail turns to the dark: no scheme, no picture from the web,
    /// a photo of its own by `cid:` and a PDF after its words.
    private var photos: Message {
        letter("<p>The roses.</p><img src=\"cid:p1@example.com\" width=\"480\">",
               files: [Attachment(id: "2", filename: "h-photo.jpg", mimeType: "image/jpeg", size: 1000,
                                  contentID: "p1@example.com", isInline: true),
                       Attachment(id: "3", filename: "notes.pdf", mimeType: "application/pdf", size: 1000)])
    }

    /// A letter Mail draws light: a picture from the web in it.
    private var light: Message { letter(DarkLikeMailTests.withAWebPicture, id: "7/4") }
    private var own: Message { letter(DarkLikeMailTests.darkReady, id: "7/5") }
    private var plain: Message { letter(nil, text: "Hi\n> The garden is ready.", id: "7/6") }

    /// The page's sheet for the switch, from its `<style id="bm-si">` to
    /// its `</style>`.
    private func sheet(of page: String) throws -> String {
        let start = try XCTUnwrap(page.range(of: "<style id=\"\(SmartInvert.sheetID)\">"))
        let end = try XCTUnwrap(page.range(of: "</style>", range: start.upperBound..<page.endIndex))
        return String(page[start.upperBound..<end.lowerBound])
    }

    /// `page` with what the switch put in it taken out: the class on its
    /// root and its sheet. What is left must be the page built with the
    /// switch off, to the byte.
    private func withoutTheSwitch(_ page: String, rules: String) -> String {
        page.replacingOccurrences(of: SmartInvert.onStart, with: "<!DOCTYPE html><html>")
            .replacingOccurrences(of: SmartInvert.sheet(on: true, rules: rules), with: "")
    }

    private func stack(_ letters: [Message], smartInvert: Bool) -> String {
        ConversationDocument.html(
            entries: letters.map { m in
                .init(id: m.id, sender: m.sender, date: m.date, body: PanePage.stackBody(m, heldBack: m.id),
                      isExpanded: true, preview: "")
            },
            inset: 26, bodyPointSize: 17, lineHeight: 1.41, smartInvert: smartInvert)
    }

    /// Under the switch, a letter the pane inverts keeps its invert, and
    /// its pictures, which the pane inverted a second time, have no
    /// filter: Mail's photos came out the system's plain inversion
    /// (C-1d), Blackmail's hue-turned. The rule weighs over the pane's
    /// own for pictures, by its class and by coming after it, and nothing
    /// else of the page changes.
    func testAnInvertedLettersPicturesHaveNoFilterUnderSmartInvert() throws {
        let m = photos
        XCTAssertEqual(LetterScheme.of(html: m.htmlBody!), .inverted)
        let page = try XCTUnwrap(PanePage.letter(m, style: on))
        XCTAssertTrue(page.hasPrefix("<!DOCTYPE html><html class=\"bm-si\"><head>"), page)
        let rules = try sheet(of: page)
        XCTAssertEqual(rules, "\nhtml.bm-si #bm img, html.bm-si #bm video { filter: none; }\n")
        XCTAssertFalse(rules.contains("invert"), rules)
        // The page keeps its invert, and its own rule for pictures, which
        // the sheet comes after.
        XCTAssertTrue(page.contains(PanePage.invertedRule))
        let own = try XCTUnwrap(page.range(of: "#bm img, #bm video, #bm svg"))
        let si = try XCTUnwrap(page.range(of: "<style id=\"bm-si\">"))
        XCTAssertLessThan(own.lowerBound, si.lowerBound)
        XCTAssertLessThan(si.lowerBound, try XCTUnwrap(page.range(of: "</head>")).lowerBound)
        XCTAssertEqual(withoutTheSwitch(page, rules: SmartInvert.rules(for: .inverted)),
                       PanePage.letter(m, style: off))
    }

    /// Under the switch only the photos, `img` and `video`, lose the
    /// pane's filter: the round's PDF tile's `svg` sheet came out black on
    /// the light tile with both inverts (C-1f, SAME), and with no filter
    /// would go white on white; `svg`, `picture` and an element with a
    /// `background-image`, the busy ring among them, keep the pane's own
    /// rule. Neither sheet names them, on a letter's page or in a stack.
    func testOnlyThePhotosLoseTheFilterUnderSmartInvert() throws {
        let page = try XCTUnwrap(PanePage.letter(photos, style: on))
        let stacked = stack([photos, light], smartInvert: true)
        for sheet in [try sheet(of: page), try sheet(of: stacked)] {
            let rules = sheet.replacingOccurrences(of: SmartInvert.wrapperTag, with: "")
            for kept in ["svg", "picture", "background-image"] {
                XCTAssertFalse(rules.contains(kept), "\(kept): \(rules)")
            }
            XCTAssertTrue(rules.contains(" img, "), rules)
            XCTAssertTrue(rules.contains(" video { filter: none; }"), rules)
        }
        // The pane's own rule for them is in the page as it was.
        XCTAssertTrue(page.contains("#bm img, #bm video, #bm svg, #bm picture, #bm [style*=\"background-image\"]"))
    }

    /// The pane's log line for the switch as iOS answers it, for the
    /// device check: a page with rules built, and a change.
    func testTheLogSaysWhatTheSwitchAnswered() {
        XCTAssertEqual(SmartInvert.note(on: true, built: true), "pane: isInvertColorsEnabled true, page built")
        XCTAssertEqual(SmartInvert.note(on: false, built: false), "pane: isInvertColorsEnabled false, changed")
    }

    /// Under the switch, a light letter's markup and its white are
    /// inverted plainly, no half turn of the hue, which the system's
    /// inversion undoes: its page white, its words black and its link
    /// `#007AFF`, as Mail's (C-1e), where Blackmail's was black with white
    /// words and an orange link. Its pictures have no filter of the
    /// pane's; Mail's line over it, held back, is inverted back, so it is
    /// the pane's colour under the system's inversion, as before. Its
    /// pictures are inverted once more by the element the pane's script
    /// puts round each (`SmartInvert.wrapperTag`), whose filter draws where
    /// a picture's own did not (r6-q-copy), with nothing of its own but
    /// the invert; no rule names a picture itself.
    func testALightLettersSheetIsInvertedPlainlyUnderSmartInvert() throws {
        let m = light
        XCTAssertEqual(LetterScheme.of(html: m.htmlBody!), .light)
        for held in [false, true] {
            let page = try XCTUnwrap(PanePage.letter(m, style: on, heldBack: held))
            XCTAssertTrue(page.hasPrefix(SmartInvert.onStart), page)
            let rules = try sheet(of: page)
            XCTAssertEqual(rules, "\nhtml.bm-si #bm { filter: invert(1); }\n"
                            + "html.bm-si #bm .bm-unloaded { filter: invert(1); }\n"
                            + "html.bm-si #bm bm-si-picture { all: unset; filter: invert(1); }\n")
            XCTAssertFalse(rules.contains("hue-rotate"), rules)
            XCTAssertFalse(rules.contains("svg") || rules.contains("img") || rules.contains("video"), rules)
            XCTAssertTrue(page.contains(PanePage.lightRule))
            XCTAssertEqual(page.contains("class=\"\(RemoteContent.lineClass)\""), held)
            XCTAssertEqual(withoutTheSwitch(page, rules: SmartInvert.rules(for: .light)),
                           PanePage.letter(m, style: off, heldBack: held))
        }
    }

    /// A plain letter and one in its own colours are as they were under the
    /// switch, held back or not, as the comparison found a plain letter
    /// (C-1a) and saw none in its own colours.
    func testPlainAndOwnLettersAreAsTheyWereUnderSmartInvert() throws {
        for m in [plain, own, letter(nil, text: PanePage.invertedRule, id: "7/7")] {
            for held in [false, true] {
                let page = try XCTUnwrap(PanePage.letter(m, style: on, heldBack: held))
                XCTAssertEqual(page, PanePage.letter(m, style: off, heldBack: held), m.id)
                XCTAssertFalse(page.contains("\"bm-si\""), m.id)
            }
        }
    }

    /// With the switch off every page is as it was: no class, no sheet, the
    /// page built by a style that does not name the switch.
    func testWithTheSwitchOffEveryPageIsAsItWas() throws {
        let plainStyle = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)
        for m in [photos, light, own, plain] {
            for held in [false, true] {
                let page = try XCTUnwrap(PanePage.letter(m, style: off, heldBack: held))
                XCTAssertTrue(page.hasPrefix("<!DOCTYPE html><html><head>"), m.id)
                XCTAssertFalse(page.contains("\"bm-si\""), m.id)
                XCTAssertEqual(page, PanePage.letter(m, style: plainStyle, heldBack: held))
            }
        }
        let page = stack([photos, light, own, plain], smartInvert: false)
        XCTAssertTrue(page.hasPrefix("<!DOCTYPE html><html><head>"))
        XCTAssertFalse(page.contains("\"bm-si\""))
        XCTAssertEqual(page, ConversationDocument.html(
            entries: [photos, light, own, plain].map { m in
                .init(id: m.id, sender: m.sender, date: m.date, body: PanePage.stackBody(m, heldBack: m.id),
                      isExpanded: true, preview: "")
            },
            inset: 26, bodyPointSize: 17, lineHeight: 1.41))
    }

    /// A conversation's stack under the switch: the class on its root and
    /// the rules for both kinds of body that change, an inverted letter's
    /// pictures with no filter and a light letter's body inverted plainly,
    /// Mail's line in it inverted back; as a letter alone has them. The
    /// bodies themselves are as they were, so a body put in later is
    /// drawn for the switch by the class alone.
    func testTheStackUnderSmartInvert() throws {
        let letters = [photos, light, own, plain]
        let page = stack(letters, smartInvert: true)
        XCTAssertTrue(page.hasPrefix(SmartInvert.onStart))
        let rules = try sheet(of: page)
        XCTAssertEqual(rules, "\nhtml.bm-si .bm-html img, html.bm-si .bm-html video { filter: none; }\n"
                        + "html.bm-si .bm-light { filter: invert(1); }\n"
                        + "html.bm-si .bm-light .bm-unloaded { filter: invert(1); }\n"
                        + "html.bm-si .bm-light bm-si-picture { all: unset; filter: invert(1); }\n")
        XCTAssertFalse(rules.contains(".bm-own") || rules.contains(".bm-text"), rules)
        let own = try XCTUnwrap(page.range(of: ".bm-html img, .bm-html video"))
        XCTAssertLessThan(own.lowerBound, try XCTUnwrap(page.range(of: "<style id=\"bm-si\">")).lowerBound)
        XCTAssertEqual(withoutTheSwitch(page, rules: SmartInvert.stack), stack(letters, smartInvert: false))
    }

    /// The page says what it is for the switch, by its head alone, the
    /// app's: a letter inverted or light, a stack, each its rules; a plain
    /// letter, one in its own colours, a notice, and a plain letter whose
    /// words are the invert's rule, none. And whether it was built with the
    /// switch on.
    func testThePageSaysWhatItIsForTheSwitch() throws {
        for style in [off, on] {
            XCTAssertEqual(SmartInvert.rules(ofPage: try XCTUnwrap(PanePage.letter(photos, style: style))),
                           SmartInvert.rules(for: .inverted))
            XCTAssertEqual(SmartInvert.rules(ofPage: try XCTUnwrap(PanePage.letter(light, style: style))),
                           SmartInvert.rules(for: .light))
            XCTAssertEqual(SmartInvert.rules(ofPage: stack([plain, photos], smartInvert: style.smartInvert)),
                           SmartInvert.stack)
            for m in [plain, own, letter(nil, text: PanePage.invertedRule, id: "7/7")] {
                XCTAssertEqual(SmartInvert.rules(ofPage: try XCTUnwrap(PanePage.letter(m, style: style))), "")
            }
            XCTAssertEqual(SmartInvert.isOn(inPage: try XCTUnwrap(PanePage.letter(photos, style: style))),
                           style.smartInvert)
            XCTAssertEqual(SmartInvert.isOn(inPage: stack([photos], smartInvert: style.smartInvert)),
                           style.smartInvert)
        }
        XCTAssertEqual(SmartInvert.rules(ofPage: PaneNotice.html(["Loading…"])), "")
        XCTAssertEqual(SmartInvert.rules(ofPage: PaneNotice.html([])), "")
        XCTAssertFalse(SmartInvert.isOn(inPage: PaneNotice.html([])))
    }

    /// The pane reads the switch from iOS for every page it builds, and
    /// follows it while a page is shown: when iOS says it changed, when
    /// the app comes back to the front, and when a page has loaded, which
    /// may have been built before the change or told of it while it
    /// loaded. Each page's rules are read off it as it is given to WebKit,
    /// and what iOS answered is written in the log for a page with rules
    /// and at a change of the answer. WebKit's colour filter follows the
    /// switch before the script runs, the page is asked once whether it
    /// takes it, and on its yes the script is given its rules (B-179,
    /// r6-p-copy); the pictures it took out to be drawn anew going off are
    /// written in the log (r6-r-copy).
    func testThePaneFollowsTheSwitch() throws {
        let pane = try TextSizeTests.source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(pane.contains("lineHeight: Theme.detailBodyLineHeight, "
                                    + "smartInvert: UIAccessibility.isInvertColorsEnabled, "
                                    + "colourFilter: colourFilterTaken == true && colourFilterReadsOn) }"))
        XCTAssertTrue(pane.contains("for name in [UIAccessibility.invertColorsStatusDidChangeNotification, "
                                    + "UIApplication.didBecomeActiveNotification] { "
                                    + "NotificationCenter.default.addObserver(self, selector: "
                                    + "#selector(followSmartInvert), name: name, object: nil) }"))
        XCTAssertTrue(pane.contains("@objc private func followSmartInvert() { "
                                    + "let on = UIAccessibility.isInvertColorsEnabled "
                                    + "let filterOn = colourFilterFollows(on) "
                                    + "if on != invertNoted { invertNoted = on "
                                    + "Diagnostics.log(.note, SmartInvert.note(on: on, built: false)) } "
                                    + "if on { askColourFilter(filterOn) } "
                                    + "let filtered = on && filterOn && colourFilterTaken == true "
                                    + "&& !invertColourFilter.isEmpty "
                                    + "guard !invertRules.isEmpty, on != invertShown || filtered != colourFilterShown "
                                    + "else { return } "
                                    + "invertShown = on colourFilterShown = filtered "
                                    + "let toggle = SmartInvert.Toggle(on: on, rules: invertRules, "
                                    + "colourFilter: filtered ? invertColourFilter : \"\") "
                                    + "webView.callAsyncJavaScript(SmartInvert.Toggle.script, "
                                    + "arguments: toggle.arguments, in: nil, in: .defaultClient) { result in "
                                    + "guard case .success(let answer) = result, let count = answer as? Int, "
                                    + "let line = SmartInvert.redrawn(count) else { return } "
                                    + "Diagnostics.log(.note, line) } }"))
        XCTAssertTrue(pane.contains("private func load(_ page: String, as content: PaneDocument.Content) { "
                                    + "let html = colourFilterReadsOn ? page : SmartInvert.withoutColourFilter(page) "
                                    + "invertRules = SmartInvert.rules(ofPage: html) "
                                    + "invertColourFilter = SmartInvert.colourFilter(ofPage: html) "
                                    + "invertBuiltOn = SmartInvert.isOn(inPage: html) "
                                    + "colourFilterBuiltOn = SmartInvert.hasColourFilter(inPage: html) "
                                    + "invertShown = invertBuiltOn colourFilterShown = colourFilterBuiltOn "
                                    + "if !invertRules.isEmpty { invertNoted = invertBuiltOn "
                                    + "Diagnostics.log(.note, SmartInvert.note(on: invertBuiltOn, built: true)) } "
                                    + "let navigation = webView.loadHTMLString(html, baseURL: nil)"))
        XCTAssertTrue(pane.contains("func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) { "
                                    + "invertShown = invertBuiltOn colourFilterShown = colourFilterBuiltOn "
                                    + "followSmartInvert() guard let navigation else { return }"))
        XCTAssertEqual(pane.components(separatedBy: "followSmartInvert()").count - 1, 3,
                       "defined, at a page's end, and at the page's answer")
        XCTAssertEqual(pane.components(separatedBy: "UIAccessibility.isInvertColorsEnabled").count - 1, 3,
                       "at init, for a page, and at a change")
    }

    /// The pane's script follows the switch on any page: the class on the
    /// root or off it, and the page's rules put in its head, in a sheet of
    /// the id the page is built with, where it has none.
    func testTheScriptFollowsTheSwitch() {
        let script = ConversationDocument.script.split(whereSeparator: { $0 == " " || $0 == "\n" })
            .joined(separator: " ")
        XCTAssertTrue(script.contains("function bmSmartInvert(on, rules, colourFilter) {"))
        XCTAssertTrue(script.contains("!document.head.querySelector('style#\(SmartInvert.sheetID)')"))
        XCTAssertTrue(script.contains("sheet.id = '\(SmartInvert.sheetID)'; sheet.textContent = rules; "
                                      + "document.head.appendChild(sheet); }"))
        XCTAssertTrue(script.contains("if (on) root.classList.add('\(SmartInvert.className)'); "
                                      + "else root.classList.remove('\(SmartInvert.className)');"))
        XCTAssertEqual(SmartInvert.Toggle.script, "return bmSmartInvert(on, rules, colourFilter)")
        let toggle = SmartInvert.Toggle(on: true, rules: SmartInvert.stack)
        XCTAssertEqual(toggle.arguments["on"] as? Bool, true)
        XCTAssertEqual(toggle.arguments["rules"] as? String, SmartInvert.stack)
        XCTAssertEqual(toggle.arguments["colourFilter"] as? String, "")
    }

    /// The script, read: going on, it puts a light letter's pictures in
    /// the element of `SmartInvert.wrapperTag`, inside a scope whose rule
    /// for it the switch's sheet has; going off, it takes every such
    /// element off and has WebKit draw anew the pictures left with a
    /// filter of their own (r6-q-copy, 2026-10-30). And it puts them in as
    /// the page ends, as `bmFill` puts a body in and as a letter goes into
    /// the stack. What it does is run in node in
    /// `SmartInvertPicturesTests`; this holds it where there is no node.
    func testTheScriptDrawsPicturesAnewAndWrapsALightLetters() {
        let script = ConversationDocument.script.split(whereSeparator: { $0 == " " || $0 == "\n" })
            .joined(separator: " ")
        XCTAssertTrue(script.contains("if (filter) root.classList.add('\(SmartInvert.colourFilterClass)'); "
                                      + "else root.classList.remove('\(SmartInvert.colourFilterClass)'); "
                                      + "if (on) { bmWrapPictures(document.body); return 0; } "
                                      + "bmUnwrapPictures(); return bmRepaintPictures(); }"), script)
        XCTAssertTrue(script.contains("return rules.indexOf('html.\(SmartInvert.className) ' + scope + ' "
                                      + "\(SmartInvert.wrapperTag) {') >= 0;"))
        XCTAssertTrue(SmartInvert.wrapper(in: "#bm").hasPrefix("html.\(SmartInvert.className) #bm "
                                                               + "\(SmartInvert.wrapperTag) {"))
        XCTAssertTrue(SmartInvert.wrapper(in: ".bm-light").hasPrefix("html.\(SmartInvert.className) .bm-light "
                                                                     + "\(SmartInvert.wrapperTag) {"))
        XCTAssertTrue(script.contains("return ['#bm', '.bm-light'].filter("))
        XCTAssertTrue(script.contains("var wrapper = document.createElement('\(SmartInvert.wrapperTag)');"))
        XCTAssertTrue(script.contains("var wrappers = document.querySelectorAll('\(SmartInvert.wrapperTag)');"))
        XCTAssertTrue(script.contains("body.innerHTML = html; bmWirePictures(body); bmWrapPictures(body); }"))
        XCTAssertTrue(script.contains("if (head) bmWire(head); bmWrapPictures(section); }"))
        XCTAssertTrue(script.contains("if (head) bmWire(head); bmWrapPictures(last); }"))
        XCTAssertTrue(script.contains("if (document.body) bmWirePictures(document.body); "
                                      + "if (document.body) bmWrapPictures(document.body);"))
        XCTAssertTrue(script.contains("if (shown.getPropertyValue('filter') === 'none' || display === 'none') continue;"))
        XCTAssertTrue(script.contains("if (!drawn.length) return 0;"))
        XCTAssertTrue(script.contains("var place = document.createElement('\(SmartInvert.placeTag)');"))
        XCTAssertTrue(script.contains("requestAnimationFrame(function () { "
                                      + "requestAnimationFrame(function () { bmPutPicturesBack(run); }); });"))
        XCTAssertTrue(script.contains("run.timer = setTimeout(function () { "
                                      + "if (!document.hidden) bmPutPicturesBack(run); }, 1000);"))
        XCTAssertTrue(script.contains("window.addEventListener('visibilitychange', bmShown);"))
        XCTAssertTrue(script.contains("function bmSmartInvert(on, rules, colourFilter) { bmPutPicturesBack();"))
    }

    /// The pane's log line for the pictures taken out to be drawn anew as
    /// the switch goes off (r6-r-copy): none for none.
    func testTheLogNamesThePicturesDrawnAnew() {
        XCTAssertEqual(SmartInvert.redrawn(3), "pane: Smart Invert off, 3 pictures drawn anew")
        XCTAssertEqual(SmartInvert.redrawn(1), "pane: Smart Invert off, 1 picture drawn anew")
        XCTAssertNil(SmartInvert.redrawn(0))
        XCTAssertNotEqual(SmartInvert.placeTag, SmartInvert.wrapperTag)
    }
}
