import XCTest
@testable import Blackmail

/// A letter the pane inverts, under the iPad's Smart Invert, made dark by
/// WebKit's colour filter as Mail's is (B-179, found again in round
/// r6-p-copy, 2026-10-29): its photos came out hue-turned under the pane's
/// invert whatever filter the pane gave them, as a photo's own filter does
/// not draw under the switch. Under both classes, and only where the page
/// said it takes the filter: no filter on the letter or any picture, the
/// pane's black behind it, Mail's quote bars and its line out of the
/// filter in Mail's own colours, his signature's white as written. Without
/// the filter's answer, and with the switch off, every page is as before,
/// byte for byte.
final class ColourFilterLikeMailTests: XCTestCase {

    private let off = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)
    private let on = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41, smartInvert: true)
    private let filtered = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41,
                                          smartInvert: true, colourFilter: true)
    private let offFiltered = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41,
                                             smartInvert: false, colourFilter: true)

    private func letter(_ html: String?, text: String? = nil, id: String = "7/3",
                        files: [Attachment] = []) -> Message {
        Message(id: id, mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                senderAddress: "sam@example.com", to: ["me@example.com"], cc: [],
                subject: "The garden", date: Date(timeIntervalSince1970: 1_790_000_000),
                textBody: text, htmlBody: html, attachments: files)
    }

    /// A letter Mail turns to the dark: a photo of its own, a PDF, a quote
    /// with its "wrote:" line and his signature's sheet.
    private var photos: Message {
        letter("<p>The roses.</p><img src=\"cid:p1@example.com\" width=\"480\">"
               + "<p>On Monday, Sam wrote:</p><blockquote type=\"cite\">Lunch?</blockquote>"
               + "<div class=\"bm-signature\" style=\"background-color: #ffffff\">Sam Example</div>",
               files: [Attachment(id: "2", filename: "h-photo.jpg", mimeType: "image/jpeg", size: 1000,
                                  contentID: "p1@example.com", isInline: true),
                       Attachment(id: "3", filename: "notes.pdf", mimeType: "application/pdf", size: 1000)])
    }

    private var light: Message { letter(DarkLikeMailTests.withAWebPicture, id: "7/4") }
    private var own: Message { letter(DarkLikeMailTests.darkReady, id: "7/5") }
    private var plain: Message { letter(nil, text: "Hi\n> The garden is ready.", id: "7/6") }

    private func sheet(_ id: String, of page: String) throws -> String {
        let start = try XCTUnwrap(page.range(of: "<style id=\"\(id)\">"), id)
        let end = try XCTUnwrap(page.range(of: "</style>", range: start.upperBound..<page.endIndex))
        return String(page[start.upperBound..<end.lowerBound])
    }

    private func stack(_ letters: [Message], smartInvert: Bool, colourFilter: Bool) -> String {
        ConversationDocument.html(
            entries: letters.map { m in
                .init(id: m.id, sender: m.sender, date: m.date, body: PanePage.stackBody(m, heldBack: m.id),
                      isExpanded: true, preview: "")
            },
            inset: 26, bodyPointSize: 17, lineHeight: 1.41, smartInvert: smartInvert,
            colourFilter: colourFilter)
    }

    /// Every selector of `rules`, split at its commas outside brackets.
    private func selectors(of rules: String) -> [String] {
        var found: [String] = []
        for block in rules.components(separatedBy: "}") {
            guard let brace = block.firstIndex(of: "{") else { continue }
            var depth = 0
            var current = ""
            for c in block[..<brace] {
                if c == "(" || c == "[" { depth += 1 }
                if c == ")" || c == "]" { depth -= 1 }
                if c == "," && depth == 0 {
                    found.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    current = ""
                } else {
                    current.append(c)
                }
            }
            found.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return found
    }

    /// The setting, the property and the log line by their names, as
    /// WebKit's source and the device check have them: the key reaches the
    /// setter and the getter by key-value coding.
    func testTheColourFiltersNamesArePinned() {
        XCTAssertEqual(ColourFilter.setter, "_setColorFilterEnabled:")
        XCTAssertEqual(ColourFilter.getter, "_colorFilterEnabled")
        XCTAssertEqual(ColourFilter.key, "colorFilterEnabled")
        XCTAssertEqual("_set" + ColourFilter.key.prefix(1).uppercased() + ColourFilter.key.dropFirst() + ":",
                       ColourFilter.setter)
        XCTAssertEqual("_" + ColourFilter.key, ColourFilter.getter)
        XCTAssertEqual(ColourFilter.property, "-apple-color-filter")
        XCTAssertEqual(ColourFilter.value, "apple-invert-lightness()")
        XCTAssertEqual(ColourFilter.test, "CSS.supports('-apple-color-filter', 'apple-invert-lightness()')")
        XCTAssertEqual(ColourFilter.question, "return CSS.supports('-apple-color-filter', 'apple-invert-lightness()');")
        XCTAssertEqual(ColourFilter.note(.supported), "pane: colour filter supported true")
        XCTAssertEqual(ColourFilter.note(.unsupported), "pane: colour filter supported false")
        XCTAssertEqual(ColourFilter.note(.absent), "pane: colour filter supported absent")
        XCTAssertEqual(SmartInvert.colourFilterClass, "bm-cf")
        XCTAssertEqual(SmartInvert.colourFilterSheetID, "bm-cf")
    }

    /// A letter the pane inverts, under the switch with the filter taken:
    /// both classes on its root, the colour filter's sheet after the
    /// switch's, every rule of it under both classes; the letter with no
    /// filter and no white of its own, made dark by the colour filter; no
    /// filter on any of the five kinds of picture.
    func testAnInvertedLetterIsMadeDarkByTheColourFilter() throws {
        let page = try XCTUnwrap(PanePage.letter(photos, style: filtered))
        XCTAssertTrue(page.hasPrefix("<!DOCTYPE html><html class=\"bm-si bm-cf\"><head>"), page)
        let si = try XCTUnwrap(page.range(of: "<style id=\"bm-si\">"))
        let cf = try XCTUnwrap(page.range(of: "<style id=\"bm-cf\">"))
        XCTAssertLessThan(si.lowerBound, cf.lowerBound)
        XCTAssertLessThan(cf.lowerBound, try XCTUnwrap(page.range(of: "</head>")).lowerBound)
        XCTAssertEqual(try sheet("bm-si", of: page), "\n" + SmartInvert.rules(for: .inverted) + "\n")
        let rules = try sheet("bm-cf", of: page)
        XCTAssertEqual(rules, "\n" + SmartInvert.colourFilter(in: "#bm") + "\n")
        let all = selectors(of: rules)
        XCTAssertGreaterThan(all.count, 10)
        for selector in all {
            XCTAssertTrue(selector.hasPrefix("html.bm-si.bm-cf #bm"), selector)
        }
        XCTAssertTrue(rules.contains("html.bm-si.bm-cf #bm { filter: none; background: transparent; "
                                     + "-apple-color-filter: apple-invert-lightness(); }"), rules)
        XCTAssertTrue(rules.contains("html.bm-si.bm-cf #bm img, html.bm-si.bm-cf #bm video, "
                                     + "html.bm-si.bm-cf #bm picture, html.bm-si.bm-cf #bm svg, "
                                     + "html.bm-si.bm-cf #bm [style*=\"background-image\"] { filter: none; }"), rules)
        XCTAssertFalse(rules.contains("invert(1)") || rules.contains("hue-rotate"), rules)
        // The page's own rules are as they were, the filter's over them.
        XCTAssertTrue(page.contains(PanePage.invertedRule))
    }

    /// Mail's quote bars, the "wrote:" line before a quote and Mail's line
    /// over held-back pictures are out of the colour filter, which cannot
    /// reach Mail's dark colours, and in them as drawn: the bars and the
    /// line before a quote Mail's dark palette, Mail's line its own
    /// colours. His signature's sheet and its white borders are the white
    /// they declare, which the colour filter makes Mail's grey.
    func testMailsOwnColoursAreOutOfTheColourFilter() throws {
        let page = try XCTUnwrap(PanePage.letter(photos, style: filtered))
        let rules = try sheet("bm-cf", of: page)
        let s = "html.bm-si.bm-cf #bm"
        XCTAssertTrue(rules.contains("\(s) \(QuoteBars.quote), \(s) .bm-attribution, \(s) .bm-unloaded "
                                     + "{ -apple-color-filter: none; }"), rules)
        XCTAssertTrue(rules.contains(QuoteBars.css(in: s, palette: QuoteBars.dark)), rules)
        XCTAssertTrue(rules.contains("\(s) \(QuoteBars.quote) { padding-left: 5px !important; margin: 0 !important; "
                                     + "border-left: 1px solid rgb(191, 90, 242) !important; "
                                     + "color: rgb(191, 90, 242) !important; }"), rules)
        XCTAssertTrue(rules.contains("\(s) .bm-attribution { padding-left: 5px !important; "
                                     + "border-left: 1px solid rgb(191, 90, 242) !important; "
                                     + "color: rgb(191, 90, 242) !important; }"), rules)
        XCTAssertTrue(rules.contains("\(s) .bm-unloaded { background-color: #000 !important; "
                                     + "border-bottom-color: #38383a !important; } "
                                     + "\(s) .bm-unloaded span { color: #fff !important; } "
                                     + "\(s) .bm-unloaded a { color: #0A84FF !important; }"), rules)
        XCTAssertTrue(rules.contains("\(s) .bm-signature[style*=\"background-color: #ffffff\"], "), rules)
        XCTAssertTrue(rules.contains("{ background-color: rgb(255, 255, 255) !important; } "
                                     + "\(s) .bm-signature [style*=\"solid rgb(255, 255, 255)\"] "
                                     + "{ border-color: rgb(255, 255, 255) !important; }"), rules)
        for drop in QuoteBars.inverted + [SignatureSheet.underInvert, "#1597FF"] {
            XCTAssertFalse(rules.contains(drop), drop)
        }
    }

    /// Without the page's yes the colour filter's flag changes nothing:
    /// its class, sheet and property nowhere in the page, and with the
    /// switch off the page with the flag is the page without it. A plain
    /// letter and one in its own colours are under the switch as with it
    /// off, as `SmartInvertLikeMailTests` pins them too.
    func testWithoutTheFiltersAnswerEveryPageIsAsBefore() throws {
        for m in [own, plain] {
            for held in [false, true] {
                XCTAssertEqual(PanePage.letter(m, style: on, heldBack: held),
                               PanePage.letter(m, style: off, heldBack: held), m.id)
            }
        }
        for m in [photos, light, own, plain] {
            for held in [false, true] {
                let before = try XCTUnwrap(PanePage.letter(m, style: on, heldBack: held))
                XCTAssertFalse(before.contains("bm-cf") || before.contains("apple-color-filter"), m.id)
                XCTAssertEqual(PanePage.letter(m, style: offFiltered, heldBack: held),
                               PanePage.letter(m, style: off, heldBack: held), m.id)
                XCTAssertEqual(SmartInvert.withoutColourFilter(before), before)
            }
        }
        let before = stack([photos, light, own, plain], smartInvert: true, colourFilter: false)
        XCTAssertFalse(before.contains("bm-cf") || before.contains("apple-color-filter"))
        XCTAssertEqual(before, ConversationDocument.html(
            entries: [photos, light, own, plain].map { m in
                .init(id: m.id, sender: m.sender, date: m.date, body: PanePage.stackBody(m, heldBack: m.id),
                      isExpanded: true, preview: "")
            },
            inset: 26, bodyPointSize: 17, lineHeight: 1.41, smartInvert: true))
        XCTAssertEqual(stack([photos, light], smartInvert: false, colourFilter: true),
                       stack([photos, light], smartInvert: false, colourFilter: false))
    }

    /// Inside a quote or a "wrote:" line, whatever carries a colour of its
    /// own is back in the colour filter, as `-apple-color-filter` is
    /// inherited and the quote's `none` would reach it: a sender's black
    /// there, Apple Mail's forwarded labels, Gmail's `rgb(34,34,34)`,
    /// Outlook's `<font color>`, would be drawn as written on the pane's
    /// black. Never a quote, such a line or Mail's line itself, which stay
    /// out of it in Mail's colours; a quote inside one is `none` again.
    func testOwnColoursInAQuoteAreBackInTheColourFilter() throws {
        let s = "html.bm-si.bm-cf #bm"
        let rule = "\(s) :is(\(QuoteBars.quote), .bm-attribution) "
            + ":is([style*=\"color\" i], font[color], [bgcolor], a)"
            + ":not(\(QuoteBars.quote)):not(.bm-attribution):not(.bm-unloaded) "
            + "{ -apple-color-filter: apple-invert-lightness(); }"
        let page = try XCTUnwrap(PanePage.letter(photos, style: filtered))
        let rules = try sheet("bm-cf", of: page)
        let none = try XCTUnwrap(rules.range(of: "\(s) \(QuoteBars.quote), \(s) .bm-attribution, "
                                              + "\(s) .bm-unloaded { -apple-color-filter: none; }"))
        let back = try XCTUnwrap(rules.range(of: rule), rules)
        XCTAssertLessThan(none.lowerBound, back.lowerBound)
        let stacked = try sheet("bm-cf", of: stack([photos], smartInvert: true, colourFilter: true))
        XCTAssertTrue(stacked.contains(rule.replacingOccurrences(of: "#bm", with: ".bm-html")), stacked)
    }

    /// Only a letter the pane inverts is made dark by the colour filter: a
    /// light letter, a plain one and one in its own colours are built as
    /// without it, the filter's answer or not.
    func testOnlyAnInvertedLetterTakesTheColourFilter() throws {
        for m in [light, own, plain] {
            for held in [false, true] {
                XCTAssertEqual(PanePage.letter(m, style: filtered, heldBack: held),
                               PanePage.letter(m, style: on, heldBack: held), m.id)
            }
        }
        XCTAssertEqual(SmartInvert.colourFilter(for: .light), "")
        XCTAssertEqual(SmartInvert.colourFilter(for: .own), "")
        XCTAssertEqual(SmartInvert.colourFilter(for: nil), "")
        // The page built with it is the page built without it but for its
        // class and its sheet.
        let page = try XCTUnwrap(PanePage.letter(photos, style: filtered))
        let without = page.replacingOccurrences(of: SmartInvert.onStartColourFilter, with: SmartInvert.onStart)
            .replacingOccurrences(of: "<style id=\"bm-cf\">\n" + SmartInvert.colourFilter(in: "#bm") + "\n</style>",
                                  with: "")
        XCTAssertEqual(without, PanePage.letter(photos, style: on))
    }

    /// A conversation's stack with the filter taken: both classes, the
    /// colour filter's rules for its HTML letters inverted, `.bm-html`,
    /// every one under both classes, after the switch's sheet.
    func testTheStackIsMadeDarkByTheColourFilter() throws {
        let page = stack([photos, light, own, plain], smartInvert: true, colourFilter: true)
        XCTAssertTrue(page.hasPrefix(SmartInvert.onStartColourFilter))
        XCTAssertEqual(try sheet("bm-si", of: page), "\n" + SmartInvert.stack + "\n")
        let rules = try sheet("bm-cf", of: page)
        XCTAssertEqual(rules, "\n" + SmartInvert.stackColourFilter + "\n")
        for selector in selectors(of: rules) {
            XCTAssertTrue(selector.hasPrefix("html.bm-si.bm-cf .bm-html"), selector)
        }
        XCTAssertTrue(rules.contains("html.bm-si.bm-cf .bm-html { filter: none; background: transparent; "
                                     + "-apple-color-filter: apple-invert-lightness(); }"))
        XCTAssertFalse(rules.contains(".bm-light") || rules.contains(".bm-own") || rules.contains(".bm-text"))
        XCTAssertLessThan(try XCTUnwrap(page.range(of: "<style id=\"bm-si\">")).lowerBound,
                          try XCTUnwrap(page.range(of: "<style id=\"bm-cf\">")).lowerBound)
        let without = page.replacingOccurrences(of: SmartInvert.onStartColourFilter, with: SmartInvert.onStart)
            .replacingOccurrences(of: "<style id=\"bm-cf\">\n" + SmartInvert.stackColourFilter + "\n</style>",
                                  with: "")
        XCTAssertEqual(without, stack([photos, light, own, plain], smartInvert: true, colourFilter: false))
    }

    /// The page says what it is with the colour filter's class too: on,
    /// with the filter, its rules and the filter's; and a page built with
    /// it, given when the setting no longer reads on, loses the class and
    /// the sheet, which WebKit would read with the setting off and keep
    /// without its colour filter: the page built without them, byte for
    /// byte, a letter's and a stack's.
    func testThePageSaysWhatItIsWithTheColourFilter() throws {
        let page = try XCTUnwrap(PanePage.letter(photos, style: filtered))
        let plainOn = try XCTUnwrap(PanePage.letter(photos, style: on))
        XCTAssertTrue(SmartInvert.isOn(inPage: page))
        XCTAssertTrue(SmartInvert.isOn(inPage: plainOn))
        XCTAssertTrue(SmartInvert.hasColourFilter(inPage: page))
        XCTAssertFalse(SmartInvert.hasColourFilter(inPage: plainOn))
        XCTAssertFalse(SmartInvert.isOn(inPage: try XCTUnwrap(PanePage.letter(photos, style: off))))
        XCTAssertEqual(SmartInvert.rules(ofPage: page), SmartInvert.rules(for: .inverted))
        XCTAssertEqual(SmartInvert.colourFilter(ofPage: page), SmartInvert.colourFilter(in: "#bm"))
        XCTAssertEqual(SmartInvert.colourFilter(ofPage: plainOn), SmartInvert.colourFilter(in: "#bm"))
        let stacked = stack([photos, plain], smartInvert: true, colourFilter: true)
        XCTAssertTrue(SmartInvert.isOn(inPage: stacked))
        XCTAssertEqual(SmartInvert.rules(ofPage: stacked), SmartInvert.stack)
        XCTAssertEqual(SmartInvert.colourFilter(ofPage: stacked), SmartInvert.stackColourFilter)
        for m in [light, own, plain] {
            XCTAssertEqual(SmartInvert.colourFilter(ofPage: try XCTUnwrap(PanePage.letter(m, style: filtered))), "")
        }
        XCTAssertEqual(SmartInvert.colourFilter(ofPage: PaneNotice.html([])), "")
        let given = SmartInvert.withoutColourFilter(page)
        XCTAssertTrue(given.hasPrefix(SmartInvert.onStart + "<head>"), given)
        XCTAssertFalse(SmartInvert.hasColourFilter(inPage: given))
        XCTAssertTrue(SmartInvert.isOn(inPage: given))
        XCTAssertFalse(given.contains("<style id=\"bm-cf\">"), given)
        XCTAssertEqual(given, plainOn)
        XCTAssertEqual(SmartInvert.withoutColourFilter(stacked),
                       stack([photos, plain], smartInvert: true, colourFilter: false))
        XCTAssertEqual(SmartInvert.withoutColourFilter(given), given)
    }

    /// The script follows the switch with the colour filter: it asks the
    /// page itself whether its CSS takes it, puts its rules in a sheet of
    /// their own in place of any the head has, read again with the setting
    /// as it is now, and puts its class on only on that yes; the class
    /// goes with the switch's, and when not given.
    func testTheScriptAsksThePageForTheColourFilter() {
        let script = ConversationDocument.script.split(whereSeparator: { $0 == " " || $0 == "\n" })
            .joined(separator: " ")
        XCTAssertTrue(script.contains("var filter = !!(on && rules && colourFilter && window.CSS && CSS.supports "
                                      + "&& \(ColourFilter.test));"), script)
        XCTAssertTrue(script.contains("if (filter && document.head) { "
                                      + "var old = document.head.querySelector("
                                      + "'style#\(SmartInvert.colourFilterSheetID)'); "
                                      + "if (old) old.parentNode.removeChild(old); "
                                      + "var filters = document.createElement('style'); "
                                      + "filters.id = '\(SmartInvert.colourFilterSheetID)'; "
                                      + "filters.textContent = colourFilter; document.head.appendChild(filters); }"))
        XCTAssertTrue(script.contains("if (filter) root.classList.add('\(SmartInvert.colourFilterClass)'); "
                                      + "else root.classList.remove('\(SmartInvert.colourFilterClass)'); }"))
        let toggle = SmartInvert.Toggle(on: true, rules: SmartInvert.stack, colourFilter: SmartInvert.stackColourFilter)
        XCTAssertEqual(toggle.arguments["colourFilter"] as? String, SmartInvert.stackColourFilter)
        XCTAssertEqual(SmartInvert.Toggle(on: true, rules: "").colourFilter, "")
    }

    /// The pane holds the web view's preferences, asks them for the
    /// setting's setter and getter by name, sets it with the switch at
    /// init and before each turn, reads it back, and asks the page once,
    /// writing its answer in the log.
    func testThePaneSetsTheColourFilterWithTheSwitch() throws {
        let pane = try TextSizeTests.source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(pane.contains("let preferences = webView.configuration.preferences "
                                    + "self.preferences = preferences "
                                    + "self.colourFilterSettable = preferences.responds(to: "
                                    + "NSSelectorFromString(ColourFilter.setter)) && preferences.responds(to: "
                                    + "NSSelectorFromString(ColourFilter.getter))"))
        XCTAssertTrue(pane.contains("super.init(nibName: nil, bundle: nil) "
                                    + "colourFilterFollows(UIAccessibility.isInvertColorsEnabled)"))
        XCTAssertTrue(pane.contains("private func colourFilterFollows(_ on: Bool) -> Bool { "
                                    + "guard colourFilterSettable else { return false } "
                                    + "if colourFilterReadsOn != on { preferences.setValue(on, forKey: ColourFilter.key) } "
                                    + "return colourFilterReadsOn }"))
        XCTAssertTrue(pane.contains("private var colourFilterReadsOn: Bool { colourFilterSettable "
                                    + "&& (preferences.value(forKey: ColourFilter.key) as? Bool) == true }"))
        XCTAssertTrue(pane.contains("private func askColourFilter(_ filterOn: Bool) { "
                                    + "guard !colourFilterAsked else { return } colourFilterAsked = true "
                                    + "guard filterOn else { colourFilterTaken = false "
                                    + "Diagnostics.log(.note, ColourFilter.note(.absent)) return } "
                                    + "webView.callAsyncJavaScript(ColourFilter.question, arguments: [:], in: nil, "
                                    + "in: .defaultClient) { [weak self] result in"))
        XCTAssertTrue(pane.contains("let taken = (answer as? Bool) == true self.colourFilterTaken = taken "
                                    + "Diagnostics.log(.note, ColourFilter.note(taken ? .supported : .unsupported)) "
                                    + "self.followSmartInvert() }"))
    }
}
