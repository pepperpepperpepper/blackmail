import XCTest
@testable import Blackmail

/// A letter's pictures as the iPad's Smart Invert goes on and off under an
/// open letter (B-179, round r6-q-copy of 2026-10-30): the photos of a
/// letter inverted drawn anew as the switch goes off, as they were left
/// hue-turned until the letter was opened again; and a light letter's
/// pictures each in an element whose invert draws, while the switch is
/// on, as Mail's come out inverted, the page's markup as it was once it
/// goes off.
///
/// The pane's script (`ConversationDocument.script`) runs in node on a
/// model of the page, as `ModelPage` runs it for the stack. A model, not
/// WebKit: the page's head is the pane's own, parsed from the page the pane
/// builds, its body markup of the test's. A picture's filter is the pane's
/// for it: the invert's second turn, `invert(1) hue-rotate(180deg)`, in a
/// letter inverted (`#bm` on a page whose head has the invert's rule, or a
/// `.bm-html` body) while the root has no class for the switch, none
/// otherwise. Its `display`, its float and any other property are its
/// `style` attribute's, or a sender's sheet's in the body, matched by
/// tag, id, class, attribute and parent; or its `data-display`, or its
/// tag's; its position and its place on the page are its `data-`
/// attributes'. WebKit lays the page out when the script reads a size or
/// a place, a width or a height of its style among them, and makes a
/// picture anew when its `display` has changed since the last layout or
/// it has been moved; a layout with a picture not drawn pulls the page up
/// to 100, as a page grown shorter would. The page is laid out once as it
/// loads and once at the run's end, as WebKit draws it. Moving a node
/// before one its parent does not hold throws, as the DOM's does.
///
/// Run only where node is; elsewhere these tests skip, and the script's
/// pins in `SmartInvertLikeMailTests` still hold it.
final class SmartInvertPicturesTests: XCTestCase {

    private let on = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41, smartInvert: true)
    private let off = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)

    private func letter(_ html: String, id: String) -> Message {
        Message(id: id, mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                senderAddress: "sam@example.com", to: ["me@example.com"], cc: [],
                subject: "The garden", date: Date(timeIntervalSince1970: 1_790_000_000),
                textBody: nil, htmlBody: html, attachments: [])
    }

    /// The head of the page the pane builds for `m`, to its `<body>`, with
    /// the test's own body after it.
    private func page(_ m: Message, style: PanePage.Style, body: String) throws -> String {
        let built = try XCTUnwrap(PanePage.letter(m, style: style))
        let head = try XCTUnwrap(built.range(of: "<body>"))
        return String(built[..<head.upperBound]) + "<div id=\"bm\">" + body + "</div></body></html>"
    }

    private var inverted: Message { letter("<p>The roses.</p><img src=\"cid:p1@example.com\">", id: "7/3") }
    private var light: Message { letter(DarkLikeMailTests.withAWebPicture, id: "7/4") }

    /// The stack's head, under the switch or not, with the test's letters.
    private func stack(smartInvert: Bool, body: String) throws -> String {
        let built = ConversationDocument.html(entries: [], inset: 26, bodyPointSize: 17, lineHeight: 1.41,
                                              smartInvert: smartInvert)
        let head = try XCTUnwrap(built.range(of: "<body>"))
        return String(built[..<head.upperBound]) + body + "</body></html>"
    }

    // MARK: - Going off

    /// Smart Invert turned off under an open letter inverted, scrolled
    /// down: each photo made anew, drawn another way and then as it was,
    /// so it is drawn with the filter it has again; its `style` attribute
    /// as it was, to the byte, and none where it had none; the page where it was, though a picture drawn
    /// another way for a moment pulled it up; the root's classes off and
    /// the body's markup as before. A picture not drawn is left alone.
    func testGoingOffDrawsAnInvertedLettersPhotosAnew() throws {
        let body = "<p>The roses.</p><img id=\"a\" src=\"cid:a@example.com\" data-rect=\"0,40,480,360\">"
            + "<img id=\"b\" src=\"cid:b@example.com\" style=\"width: 480px; display: block\">"
            + "<span><img id=\"c\" src=\"cid:c@example.com\" data-display=\"table-cell\"></span>"
            + "<img id=\"d\" src=\"cid:d@example.com\" style=\"display: none\">"
        let html = try page(inverted, style: on, body: body)
        let run = try model(html, [.scroll(500), .snapshot("on"),
                                   .toggle(on: false, rules: SmartInvert.rules(for: .inverted)),
                                   .snapshot("off")])
        XCTAssertEqual(run.made, ["a": 2, "b": 2, "c": 2, "d": 0], run.log)
        XCTAssertEqual(run.snapshots["off"], run.snapshots["on"])
        XCTAssertEqual(run.scrollY, 500)
        XCTAssertEqual(run.pulledUp, true, "the model's page pulled up and put back")
        XCTAssertEqual(run.root, "")
        XCTAssertEqual(run.displays, ["a": "inline", "b": "block", "c": "table-cell", "d": "none"])
    }

    /// The same in a conversation's stack: an inverted letter's photo made
    /// anew; a light letter's picture, in its element while the switch
    /// was on, taken out of it and not made anew, and a plain letter's,
    /// with no filter once the switch is off, left as they are.
    func testGoingOffInAStackDrawsOnlyThePhotosWithAFilter() throws {
        let body = "<div class=\"bm-letter bm-open\" id=\"m1\"><div class=\"bm-head\"></div>"
            + "<div class=\"bm-body bm-html\"><img id=\"a\" src=\"cid:a@example.com\"></div></div>"
            + "<div class=\"bm-letter bm-open\" id=\"m2\"><div class=\"bm-head\"></div>"
            + "<div class=\"bm-body bm-text\"><img id=\"t\" src=\"cid:t@example.com\"></div></div>"
            + "<div class=\"bm-letter bm-open\" id=\"m3\"><div class=\"bm-head\"></div>"
            + "<div class=\"bm-body bm-light\"><img id=\"l\" src=\"cid:l@example.com\"></div></div>"
        let html = try stack(smartInvert: true, body: body)
        let run = try model(html, [.snapshot("on"), .toggle(on: false, rules: SmartInvert.stack)])
        XCTAssertTrue(try XCTUnwrap(run.snapshots["on"]).contains("<bm-si-picture><img id=\"l\""), run.log)
        XCTAssertEqual(run.made, ["a": 2, "t": 0, "l": 0], run.log)
        XCTAssertEqual(run.wrappers, 0, run.log)
        XCTAssertEqual(run.scrolledTo, 0)
    }

    /// A page with no picture that has a filter once the switch is off is
    /// not touched as it goes off: no layout asked of WebKit, nothing
    /// scrolled, its markup as it was. A letter inverted with words alone,
    /// and a light letter, whose pictures have no filter with the switch
    /// off: only their elements taken off.
    func testGoingOffTouchesNothingOnAPageWithoutSuchPictures() throws {
        let words = try page(inverted, style: on, body: "<p>The roses.</p>")
        let run = try model(words, [.snapshot("on"), .toggle(on: false, rules: SmartInvert.rules(for: .inverted)),
                                    .snapshot("off")])
        XCTAssertEqual(run.layoutsAsked, 0, run.log)
        XCTAssertEqual(run.scrolledTo, 0)
        XCTAssertEqual(run.snapshots["off"], run.snapshots["on"])

        let photo = "<p>The roses.</p><img id=\"rose\" src=\"cid:r@example.com\">"
        let lit = try model(try page(light, style: on, body: photo),
                            [.snapshot("on"), .toggle(on: false, rules: SmartInvert.rules(for: .light)),
                             .snapshot("off")])
        XCTAssertTrue(try XCTUnwrap(lit.snapshots["on"]).contains("<bm-si-picture><img id=\"rose\""), lit.log)
        XCTAssertEqual(lit.layoutsAsked, 0, lit.log)
        XCTAssertEqual(lit.scrolledTo, 0)
        XCTAssertEqual(lit.made, ["rose": 0], lit.log)
        XCTAssertEqual(lit.wrappers, 0, lit.log)
        XCTAssertTrue(try XCTUnwrap(lit.snapshots["off"]).hasSuffix(
            "<div id=\"bm\">" + photo + "</div></body>"), lit.log)
    }

    // MARK: - A light letter's pictures

    /// The light letter's markup as the test gives it, every kind of
    /// picture in it.
    private let lightBody = "<div dir=\"ltr\">Look at the roses.<br>"
        + "<img id=\"web\" src=\"https://example.com/roses.jpg\" width=\"480\" data-rect=\"26,60,480,360\">"
        + "</div><p data-rect=\"26,430,700,300\"><img id=\"block\" src=\"cid:b@example.com\" "
        + "style=\"display: block\" data-rect=\"26,430,700,300\"></p>"
        + "<img id=\"float\" src=\"cid:f@example.com\" style=\"float: left\">"
        + "<img id=\"placed\" src=\"cid:p@example.com\" data-position=\"absolute\">"
        + "<picture id=\"pic\"><source srcset=\"cid:s@example.com\"><img id=\"inpic\" src=\"cid:i@example.com\"></picture>"
        + "<video id=\"still\" src=\"cid:v@example.com\"></video>"
        + "<video id=\"playing\" src=\"cid:w@example.com\" data-playing=\"\"></video>"
        + "<span><img id=\"moves\" src=\"cid:m@example.com\" data-moves=\"\"></span>"

    /// A light letter's page built under the switch: as the script ends,
    /// each picture drawn inline or as a block put in the element whose
    /// invert draws, an inline one for an inline picture with no `style`
    /// of its own, a block for a block picture; a `<picture>`'s image by
    /// its `<picture>`, so its sources stay with it; a picture that
    /// floats or is placed, a video playing, and one that moved once the
    /// element was round it, left as they were.
    func testALightLettersPicturesAreWrappedOnAPageBuiltUnderTheSwitch() throws {
        let html = try page(light, style: on, body: lightBody)
        let run = try model(html, [])
        XCTAssertEqual(run.wrapped, [
            "web": "<bm-si-picture>",
            "block": "<bm-si-picture style=\"display: block;\">",
            "pic": "<bm-si-picture>",
            "still": "<bm-si-picture>",
        ], run.log)
        XCTAssertEqual(run.root, "bm-si")
    }

    /// The same page with the switch turned off and on again while it is
    /// open: off, every element taken off and the body's markup as it was
    /// built, to the byte; on, put back; and a page built with the switch
    /// off, its sheet put in by the script as it goes on, the same. Never
    /// a scroll.
    func testALightLettersPicturesFollowTheSwitch() throws {
        let rules = SmartInvert.rules(for: .light)
        let built = try page(light, style: on, body: lightBody)
        let run = try model(built, [.toggle(on: false, rules: rules), .snapshot("off"),
                                    .toggle(on: true, rules: rules), .snapshot("on")])
        let plain = try model(try page(light, style: off, body: lightBody),
                              [.snapshot("off"), .toggle(on: true, rules: rules), .snapshot("on"),
                               .toggle(on: false, rules: rules), .snapshot("offAgain")])
        XCTAssertEqual(run.snapshots["off"], plain.snapshots["off"])
        XCTAssertEqual(plain.snapshots["offAgain"], plain.snapshots["off"])
        XCTAssertEqual(run.snapshots["on"], plain.snapshots["on"])
        XCTAssertNotEqual(run.snapshots["on"], run.snapshots["off"])
        XCTAssertEqual(plain.wrapped, [:], plain.log)
        XCTAssertEqual(run.wrapped.keys.sorted(), ["block", "pic", "still", "web"], run.log)
        XCTAssertTrue(try XCTUnwrap(plain.snapshots["on"]).contains(
            "<bm-si-picture><img id=\"web\""), plain.log)
        XCTAssertEqual(run.scrolledTo + plain.scrolledTo, 0)
        XCTAssertEqual(plain.root, "")
        XCTAssertEqual(run.root, "bm-si")
    }

    /// Only a light letter's pictures: a letter inverted under the switch
    /// has none of the elements, its sheet having no rule for them.
    func testALetterInvertedHasNoWrapper() throws {
        let html = try page(inverted, style: on, body: lightBody)
        let run = try model(html, [.toggle(on: true, rules: SmartInvert.rules(for: .inverted))])
        XCTAssertEqual(run.wrapped, [:], run.log)
    }

    /// In a stack under the switch: a light body put in by `bmFill`, and
    /// a light letter put in by `bmAppend`, have their pictures put in the
    /// element; a body inverted does not.
    func testAStacksLightBodiesAreWrappedAsTheyGoIn() throws {
        let body = "<div class=\"bm-letter bm-open\" id=\"m1\"><div class=\"bm-head\"></div>"
            + "<div class=\"bm-body bm-text\">Loading…</div></div>"
            + "<div class=\"bm-letter bm-open\" id=\"m2\"><div class=\"bm-head\"></div>"
            + "<div class=\"bm-body bm-text\">Loading…</div></div>"
        let html = try stack(smartInvert: true, body: body)
        let run = try model(html, [
            .fill(id: "m1", html: "<p>a</p><img id=\"lightpic\" src=\"cid:a@example.com\">", scheme: "bm-light"),
            .fill(id: "m2", html: "<p>b</p><img id=\"darkpic\" src=\"cid:b@example.com\">", scheme: "bm-html"),
            .append("<div class=\"bm-letter bm-open\" id=\"m3\"><div class=\"bm-head\"></div>"
                    + "<div class=\"bm-body bm-light\"><img id=\"later\" src=\"cid:c@example.com\"></div></div>"),
        ])
        XCTAssertEqual(run.wrapped, ["lightpic": "<bm-si-picture>", "later": "<bm-si-picture>"], run.log)
    }

    /// The switch's on told again to a page whose pictures are already
    /// in their elements, as the pane does when the colour filter's
    /// answer comes after a page built under the switch: no picture put
    /// in a second element, none inside another. A light letter's page,
    /// and a stack's light body put in by `bmFill`.
    func testOnAgainPutsNoPictureInASecondElement() throws {
        let rules = SmartInvert.rules(for: .light)
        let first = try model(try page(light, style: on, body: lightBody), [])
        let again = try model(try page(light, style: on, body: lightBody), [.toggle(on: true, rules: rules)])
        XCTAssertEqual(again.wrapped, first.wrapped, again.log)
        XCTAssertEqual(again.wrappers, 4, again.log)

        let body = "<div class=\"bm-letter bm-open\" id=\"m1\"><div class=\"bm-head\"></div>"
            + "<div class=\"bm-body bm-text\">Loading…</div></div>"
        let fill = Step.fill(id: "m1", html: "<p>a</p><img id=\"lightpic\" src=\"cid:a@example.com\">",
                             scheme: "bm-light")
        let stacked = try model(try stack(smartInvert: true, body: body),
                                [fill, .toggle(on: true, rules: SmartInvert.stack)])
        XCTAssertEqual(stacked.wrapped, ["lightpic": "<bm-si-picture>"], stacked.log)
        XCTAssertEqual(stacked.wrappers, 1, stacked.log)
    }

    /// A sender's rule that names a picture by its parent, in a light
    /// letter laid out at no size, a stack's letter folded shut, whose
    /// place and size read the same with the element round it or not:
    /// the element taken off a picture whose own look changed, `td > img`
    /// drawn as a block and `a > img` no taller than 40 px, and left on
    /// a picture no rule of the kind names. In the page built under the
    /// switch, and in a body `bmFill` puts in a letter folded shut.
    func testASendersRuleByThePicturesParentKeepsItsLook() throws {
        let sheet = "<style>td > img { display: block; } a > img { max-height: 40px; }</style>"
        func letter(_ id: String, _ suffix: String) -> String {
            sheet + "<table><tr><td><img id=\"slice" + suffix + "\" src=\"cid:s@example.com\"></td></tr></table>"
                + "<a href=\"https://example.com/\"><img id=\"logo" + suffix + "\" src=\"cid:l@example.com\"></a>"
                + "<img id=\"free" + suffix + "\" src=\"cid:f@example.com\">"
        }
        let body = "<div class=\"bm-letter\" id=\"m1\"><div class=\"bm-head\"></div>"
            + "<div class=\"bm-body bm-light\">" + letter("m1", "") + "</div></div>"
            + "<div class=\"bm-letter\" id=\"m2\"><div class=\"bm-head\"></div>"
            + "<div class=\"bm-body bm-text\">Loading…</div></div>"
        let run = try model(try stack(smartInvert: true, body: body),
                            [.fill(id: "m2", html: letter("m2", "2"), scheme: "bm-light")])
        XCTAssertEqual(run.wrapped, ["free": "<bm-si-picture>", "free2": "<bm-si-picture>"], run.log)
        XCTAssertEqual(run.displays["slice"], "block", run.log)
        XCTAssertEqual(run.displays["slice2"], "block", run.log)
    }

    /// A `<picture>` that holds two images, as a sender's markup can: put
    /// in one element, and the pictures after it each in theirs.
    func testAPictureOfTwoImagesStopsNoOther() throws {
        let body = "<p>x<picture id=\"pic\"><img id=\"one\" src=\"cid:a@example.com\">"
            + "<img id=\"two\" src=\"cid:b@example.com\"></picture>"
            + "<img id=\"c\" src=\"cid:c@example.com\"><img id=\"d\" src=\"cid:d@example.com\"></p>"
        let run = try model(try page(light, style: on, body: body), [])
        XCTAssertEqual(run.wrapped, ["pic": "<bm-si-picture>", "c": "<bm-si-picture>", "d": "<bm-si-picture>"],
                       run.log)
        XCTAssertEqual(run.wrappers, 3, run.log)
    }

    /// The switch going on under a light letter scrolled down, where the
    /// element round a picture stops a rule of its sender's and the page
    /// grows shorter for it: the element taken off, and the page put back
    /// where it was.
    func testOnLeavesThePageWhereItWas() throws {
        let body = "<style>img { display: none; } p > img { display: inline; }</style>"
            + "<p>The roses.<img id=\"rose\" src=\"cid:r@example.com\"></p>"
        let run = try model(try page(light, style: off, body: body),
                            [.scroll(500), .toggle(on: true, rules: SmartInvert.rules(for: .light))])
        XCTAssertEqual(run.wrapped, [:], run.log)
        XCTAssertEqual(run.pulledUp, true, "the model's page pulled up and put back")
        XCTAssertEqual(run.scrollY, 500)
    }

    // MARK: - The model

    private struct Step: Encodable {
        let action: String
        var on: Bool? = nil
        var rules: String? = nil
        var y: Int? = nil
        var name: String? = nil
        var id: String? = nil
        var html: String? = nil
        var scheme: String? = nil

        static func toggle(on: Bool, rules: String) -> Step { Step(action: "toggle", on: on, rules: rules) }
        static func scroll(_ y: Int) -> Step { Step(action: "scroll", y: y) }
        static func snapshot(_ name: String) -> Step { Step(action: "snapshot", name: name) }
        static func fill(id: String, html: String, scheme: String) -> Step {
            Step(action: "fill", id: id, html: html, scheme: scheme)
        }
        static func append(_ html: String) -> Step { Step(action: "append", html: html) }
    }

    private struct Run: Decodable {
        /// Each picture by its id: how many times WebKit made it anew
        /// after the page loaded, apart from a move.
        let made: [String: Int]
        /// Each picture's `display` at the run's end.
        let displays: [String: String]
        /// Each picture put in an element of the wrapper's tag, by its id
        /// (a `<picture>` by its own): that element's opening tag.
        let wrapped: [String: String]
        /// How many elements of the wrapper's tag the page has at the
        /// run's end.
        let wrappers: Int
        let snapshots: [String: String]
        let root: String
        let scrollY: Double
        let scrolledTo: Int
        let pulledUp: Bool
        let layoutsAsked: Int
        let log: String
    }

    private func model(_ page: String, _ steps: [Step]) throws -> Run {
        struct Input: Encodable { let script: String; let page: String; let steps: [Step]; let invertedRule: String }
        let input = try JSONEncoder().encode(Input(script: ConversationDocument.script, page: page,
                                                   steps: steps, invertedRule: PanePage.invertedRule))
        let out = try runNode(Self.program, input: input)
        return try JSONDecoder().decode(Run.self, from: out)
    }

    private static let program = #"""
    const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
    const VOID = ['img', 'meta', 'br', 'source', 'link', 'hr', 'input'];
    const RAW = ['style', 'script', 'title'];
    let layoutsAsked = 0, loaded = false, pulledUp = false, scrollX = 0, scrollY = 0, scrolledTo = 0;
    const log = [];
    class Text {
      constructor(text) { this.nodeType = 3; this.text = text; this.parentNode = null; }
    }
    function parseStyle(text) {
      const out = [];
      for (const part of String(text || '').split(';')) {
        const at = part.indexOf(':');
        if (at < 0) continue;
        let value = part.slice(at + 1).trim(), priority = '';
        if (/!important$/.test(value)) { priority = 'important'; value = value.replace(/\s*!important$/, ''); }
        out.push([part.slice(0, at).trim().toLowerCase(), value, priority]);
      }
      return out;
    }
    class Style {
      constructor(el) { this.el = el; }
      get list() { return parseStyle(this.el.getAttribute('style')); }
      write(list) {
        this.el.setAttribute('style', list.map(function (p) {
          return p[0] + ': ' + p[1] + (p[2] ? ' !important' : '') + ';';
        }).join(' '));
      }
      getPropertyValue(n) { const p = this.list.find(function (p) { return p[0] === n; }); return p ? p[1] : ''; }
      getPropertyPriority(n) { const p = this.list.find(function (p) { return p[0] === n; }); return p ? p[2] : ''; }
      setProperty(n, v, priority) {
        const list = this.list, p = list.find(function (p) { return p[0] === n; });
        if (p) { p[1] = v; p[2] = priority || ''; } else list.push([n, v, priority || '']);
        this.write(list);
      }
      removeProperty(n) { this.write(this.list.filter(function (p) { return p[0] !== n; })); }
    }
    class Element {
      constructor(tag) {
        this.nodeType = 1; this.tagName = tag.toUpperCase(); this.attrs = []; this.children = [];
        this.parentNode = null; this.raw = ''; this.made = 0; this.drawnAs = undefined; this.drawnIn = undefined;
      }
      getAttribute(n) { const a = this.attrs.find(function (a) { return a[0] === n; }); return a ? a[1] : null; }
      setAttribute(n, v) {
        const a = this.attrs.find(function (a) { return a[0] === n; });
        if (a) a[1] = String(v); else this.attrs.push([n, String(v)]);
      }
      removeAttribute(n) { this.attrs = this.attrs.filter(function (a) { return a[0] !== n; }); }
      get id() { return this.getAttribute('id') || ''; }
      set id(v) { this.setAttribute('id', v); }
      get className() { return this.getAttribute('class') || ''; }
      set className(v) { this.setAttribute('class', v); }
      get classList() {
        const el = this;
        const names = function () { return el.className.split(/\s+/).filter(Boolean); };
        return {
          contains: function (c) { return names().indexOf(c) >= 0; },
          add: function (c) { if (names().indexOf(c) < 0) el.className = names().concat([c]).join(' '); },
          remove: function (c) {
            if (names().indexOf(c) < 0) return;
            const left = names().filter(function (n) { return n !== c; });
            if (left.length) el.className = left.join(' '); else el.removeAttribute('class');
          },
          toggle: function (c) { if (this.contains(c)) this.remove(c); else this.add(c); },
        };
      }
      get style() { return new Style(this); }
      get textContent() { return this.raw; }
      set textContent(v) { this.raw = String(v); }
      get firstChild() { return this.children[0] || null; }
      get firstElementChild() { return this.children.find(function (c) { return c.nodeType === 1; }) || null; }
      get nextElementSibling() {
        if (!this.parentNode) return null;
        const list = this.parentNode.children;
        for (let i = list.indexOf(this) + 1; i < list.length; i++) if (list[i].nodeType === 1) return list[i];
        return null;
      }
      get previousElementSibling() {
        if (!this.parentNode) return null;
        const list = this.parentNode.children;
        for (let i = list.indexOf(this) - 1; i >= 0; i--) if (list[i].nodeType === 1) return list[i];
        return null;
      }
      get paused() { return this.getAttribute('data-playing') === null; }
      insertBefore(child, ref) {
        if (ref && this.children.indexOf(ref) < 0) throw new Error('NotFoundError');
        if (child.parentNode) child.parentNode.removeChild(child);
        const at = ref ? this.children.indexOf(ref) : -1;
        if (at < 0) this.children.push(child); else this.children.splice(at, 0, child);
        child.parentNode = this;
        return child;
      }
      appendChild(child) { return this.insertBefore(child, null); }
      removeChild(child) {
        this.children = this.children.filter(function (c) { return c !== child; });
        child.parentNode = null;
        return child;
      }
      descendants() {
        const out = [];
        (function walk(el) {
          for (const c of el.children) if (c.nodeType === 1) { out.push(c); walk(c); }
        })(this);
        return out;
      }
      querySelectorAll(selector) {
        return this.descendants().filter(function (el) { return matches(el, selector); });
      }
      querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
      getBoundingClientRect() {
        layout(true);
        const r = String(this.getAttribute('data-rect') || '0,0,0,0').split(',').map(Number);
        const moved = this.getAttribute('data-moves') !== null && this.parentNode
          && this.parentNode.tagName === 'BM-SI-PICTURE' ? 7 : 0;
        return { left: r[0], top: r[1] + moved - scrollY, width: r[2], height: r[3],
                 right: r[0] + r[2], bottom: r[1] + moved + r[3] - scrollY };
      }
      get offsetHeight() { layout(true); return 0; }
      set innerHTML(html) {
        for (const c of this.children.slice()) this.removeChild(c);
        parseInto(this, html);
      }
      addEventListener() {}
    }
    function compound(el, text) {
      const m = /^([a-zA-Z0-9-]*|\*)((?:[#.][a-zA-Z0-9_-]+|\[[^\]]+\])*)$/.exec(text);
      if (!m) throw new Error('selector ' + text);
      if (m[1] && m[1] !== '*' && el.tagName !== m[1].toUpperCase()) return false;
      const parts = m[2].match(/[#.][a-zA-Z0-9_-]+|\[[^\]]+\]/g) || [];
      for (const p of parts) {
        if (p[0] === '#' && el.id !== p.slice(1)) return false;
        if (p[0] === '.' && !el.classList.contains(p.slice(1))) return false;
        if (p[0] === '[') {
          const a = /^\[([a-zA-Z-]+)(?:="([^"]*)")?\]$/.exec(p);
          if (el.getAttribute(a[1]) === null || (a[2] !== undefined && el.getAttribute(a[1]) !== a[2])) return false;
        }
      }
      return true;
    }
    function complex(el, parts) {
      if (!compound(el, parts[parts.length - 1])) return false;
      if (parts.length === 1) return true;
      const combinator = parts[parts.length - 2], rest = parts.slice(0, -2);
      if (combinator === '>') return el.parentNode instanceof Element && complex(el.parentNode, rest);
      for (let up = el.parentNode; up instanceof Element; up = up.parentNode) if (complex(up, rest)) return true;
      return false;
    }
    function matches(el, selector) {
      return selector.split(',').some(function (one) {
        const parts = one.trim().replace(/\s*>\s*/g, ' > ').split(/\s+/)
          .reduce(function (out, p) {
            if (p === '>') out.push('>'); else { if (out.length && out[out.length - 1] !== '>') out.push(' '); out.push(p); }
            return out;
          }, []);
        return complex(el, parts);
      });
    }
    function parseInto(parent, html) {
      const tag = /<!--[\s\S]*?-->|<![^>]*>|<\/([a-zA-Z0-9-]+)\s*>|<([a-zA-Z0-9-]+)((?:\s+[^\s=>\/]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?)*)\s*\/?>/g;
      let at = 0, open = parent, m;
      while ((m = tag.exec(html))) {
        if (m.index > at) open.appendChild(new Text(html.slice(at, m.index)));
        at = tag.lastIndex;
        if (m[1]) {
          for (let up = open; up && up !== parent.parentNode; up = up.parentNode) {
            if (up.tagName === m[1].toUpperCase()) { open = up.parentNode; break; }
          }
          continue;
        }
        if (!m[2]) continue;
        const el = new Element(m[2]);
        const attr = /([^\s=>\/]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
        let a;
        while ((a = attr.exec(m[3] || ''))) {
          el.setAttribute(a[1].toLowerCase(), a[2] !== undefined ? a[2] : a[3] !== undefined ? a[3] : a[4] || '');
        }
        open.appendChild(el);
        const name = m[2].toLowerCase();
        if (RAW.indexOf(name) >= 0) {
          const end = html.toLowerCase().indexOf('</' + name, at);
          el.raw = html.slice(at, end < 0 ? html.length : end);
          if (end >= 0) { at = html.indexOf('>', end) + 1; tag.lastIndex = at; }
          continue;
        }
        if (VOID.indexOf(name) < 0) open = el;
      }
      if (at < html.length) open.appendChild(new Text(html.slice(at)));
    }
    const top = new Element('#document');
    parseInto(top, input.page);
    const documentElement = top.children.find(function (c) { return c.tagName === 'HTML'; });
    const head = documentElement.querySelector('head');
    const body = documentElement.querySelector('body');
    function ancestors(el) { const out = []; for (let up = el.parentNode; up instanceof Element; up = up.parentNode) out.push(up); return out; }
    function isPicture(el) { return el.tagName === 'IMG' || el.tagName === 'VIDEO'; }
    function senderRules() {
      const out = [];
      for (const sheet of body.querySelectorAll('style')) {
        const rule = /([^{}]+)\{([^}]*)\}/g;
        let m;
        while ((m = rule.exec(sheet.raw))) out.push([m[1].trim(), parseStyle(m[2])]);
      }
      return out;
    }
    function own(el, name) {
      const inline = el.style.getPropertyValue(name);
      if (inline) return inline;
      let value = '';
      for (const rule of senderRules()) {
        if (!matches(el, rule[0])) continue;
        const p = rule[1].find(function (p) { return p[0] === name; });
        if (p) value = p[1];
      }
      return value;
    }
    function computed(el) {
      const style = el.style;
      const display = own(el, 'display') || el.getAttribute('data-display')
        || (['DIV', 'P', 'BODY', 'HTML', 'HEAD', 'TABLE', 'TR', 'TD'].indexOf(el.tagName) >= 0 ? 'block' : 'inline');
      let filter = 'none';
      const pageInverted = head.querySelectorAll('style').some(function (s) { return s.raw.indexOf(input.invertedRule) >= 0; });
      const up = ancestors(el);
      const invertedLetter = up.some(function (a) { return a.classList.contains('bm-html') || (a.id === 'bm' && pageInverted); });
      if (isPicture(el) && invertedLetter && !documentElement.classList.contains('bm-si')) filter = 'invert(1) hue-rotate(180deg)';
      const values = { display: display, filter: filter,
                       float: own(el, 'float') || 'none',
                       position: el.getAttribute('data-position') || 'static' };
      return { getPropertyValue: function (n) {
        if (n === 'width' || n === 'height') layout(true);
        return values[n] || own(el, n);
      } };
    }
    function layout(asked) {
      if (asked && loaded) layoutsAsked++;
      let hidden = false;
      for (const el of documentElement.descendants()) {
        if (!isPicture(el)) continue;
        const display = computed(el).getPropertyValue('display');
        if (el.drawnIn !== undefined && el.drawnIn === el.parentNode && el.drawnAs !== display) el.made++;
        el.drawnAs = display;
        el.drawnIn = el.parentNode;
        if (display === 'none' && el.getAttribute('style') !== 'display: none') hidden = true;
      }
      if (hidden && scrollY > 100) { scrollY = 100; pulledUp = true; }
    }
    function serialize(node) {
      if (node.nodeType === 3) return node.text;
      const name = node.tagName.toLowerCase();
      const attrs = node.attrs.map(function (a) { return ' ' + a[0] + '="' + a[1] + '"'; }).join('');
      if (VOID.indexOf(name) >= 0) return '<' + name + attrs + '>';
      return '<' + name + attrs + '>' + node.raw + node.children.map(serialize).join('') + '</' + name + '>';
    }
    global.document = {
      documentElement: documentElement, head: head, body: body,
      createElement: function (tag) { return new Element(tag); },
      getElementById: function (id) { return documentElement.descendants().find(function (el) { return el.id === id; }) || null; },
      querySelectorAll: function (s) { return documentElement.querySelectorAll(s); },
      querySelector: function (s) { return documentElement.querySelector(s); },
    };
    global.window = {
      get pageXOffset() { return scrollX; }, get pageYOffset() { return scrollY; },
      innerHeight: 700,
      scrollTo: function (x, y) { scrollX = x; scrollY = y; scrolledTo++; },
      scrollBy: function (x, y) { scrollX += x; scrollY += y; scrolledTo++; },
      addEventListener: function () {},
      getComputedStyle: computed,
      CSS: { supports: function () { return false; } },
    };
    global.getComputedStyle = computed;
    global.performance = { now: function () { return 0; } };
    (0, eval)(input.script);
    layout(false);
    loaded = true;
    const snapshots = {};
    for (const step of input.steps) {
      if (step.action === 'toggle') bmSmartInvert(step.on, step.rules, '');
      if (step.action === 'scroll') scrollY = step.y;
      if (step.action === 'snapshot') snapshots[step.name] = serialize(body);
      if (step.action === 'fill') bmFill(step.id, step.html, true, step.scheme);
      if (step.action === 'append') bmAppend(step.html);
      log.push(step.action + ': ' + serialize(body));
    }
    layout(false);
    const made = {}, displays = {}, wrapped = {};
    for (const el of documentElement.descendants()) {
      if (isPicture(el) && el.id) {
        made[el.id] = el.made;
        displays[el.id] = computed(el).getPropertyValue('display');
      }
      if (el.tagName === 'BM-SI-PICTURE') {
        const inside = el.firstElementChild;
        const opening = serialize(el);
        wrapped[inside ? inside.id : '?'] = opening.slice(0, opening.indexOf('>') + 1);
      }
    }
    process.stdout.write(JSON.stringify({
      made: made, displays: displays, wrapped: wrapped, snapshots: snapshots,
      wrappers: documentElement.querySelectorAll('bm-si-picture').length,
      root: documentElement.className, scrollY: scrollY, scrolledTo: scrolledTo, pulledUp: pulledUp,
      layoutsAsked: layoutsAsked, log: log.join('\n') }));
    """#

    /// Runs `program` in node with `input` on its standard input, and
    /// returns what it wrote; skips where there is no node.
    private func runNode(_ program: String, input: Data) throws -> Data {
        let node = Process()
        node.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        node.arguments = ["node", "-e", program]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        node.standardInput = stdin
        node.standardOutput = stdout
        node.standardError = stderr
        do { try node.run() } catch { throw XCTSkip("no node on this host") }
        stdin.fileHandleForWriting.write(input)
        try stdin.fileHandleForWriting.close()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        node.waitUntilExit()
        if node.terminationStatus == 127 { throw XCTSkip("no node on this host") }
        XCTAssertEqual(node.terminationStatus, 0, String(data: err, encoding: .utf8) ?? "")
        return out
    }
}
