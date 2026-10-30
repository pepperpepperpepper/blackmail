import Foundation

/// A letter in the reading pane under the iPad's Smart Invert, as Mail's
/// comes out under it (B-179).
///
/// The comparison with Mail 16.5.1 on the test iPad of 2026-10-29 (round
/// r6-n-compare, C-1d and C-1e) found Mail's letter, under Smart Invert,
/// the system's plain inversion of its Dark Mode page, pictures and all,
/// for a letter Mail turns to the dark; and a light letter as on paper,
/// its page white, its words black and its link blue, its pictures
/// inverted. Blackmail's pane came out the system's inversion too, but its
/// photos in a letter it inverts hue-turned, their lightness kept, and a
/// light letter's page black with white words: the photos drawn with one
/// of the pane's two inverts where the page means two, and the light page
/// inverted by the system with nothing to undo it.
///
/// So under the switch, and only under it: a letter the pane inverts
/// keeps its invert, and its photos, `img` and `video`, have no filter
/// (`inverted`); a light
/// letter's markup and its white are inverted plainly, `invert(1)` with no
/// half turn of the hue, which the system's inversion undoes, so its page
/// is white, its words black and its link `#007AFF`, as Mail's; its
/// pictures have no filter of the pane's, and Mail's line over it, when
/// its pictures from the web are held back (B-168), is inverted back, so
/// it stays the pane's colour under the system's inversion (`light`). A
/// plain letter, a letter in its own colours, a notice, the printed page
/// and Quick Look are as they were.
///
/// The switch is iOS's (`UIAccessibility.isInvertColorsEnabled`), read by
/// the pane, which follows it while it is open
/// (`MessageDetailViewController`). Apple documents it as Classic
/// Invert's; whether it is true under Smart Invert on 16.5.1 and on 18 is
/// not known, so the pane writes what it read in its log (`note`) for the
/// device check to see. If it is false under Smart Invert, none of this
/// is drawn. Not WebKit's own `@media
/// (inverted-colors)`: the light letter's pictures, with no filter of the
/// app's on them, came out inverted, so WebKit's rule for that query does
/// not take in the pane's web view.
///
/// **Found on the test iPad, 2026-10-29 (r6-p-copy).** The switch is
/// true under Smart Invert on 16.5.1. The photos still came out
/// hue-turned, and a light letter's pictures natural: a filter of a
/// photo's own does not draw under the switch, so taking the pane's
/// second invert off them changed nothing, and the page's invert above
/// them still turns their hue. So, under the switch, a letter the pane
/// inverts is made dark by WebKit's colour filter instead, as Mail's is,
/// where the page says it takes it (`ColourFilter`): with the second class
/// on the root (`colourFilterClass`) and its rules in a sheet of their own
/// (`colourFilter(in:)`), no filter on the letter or its pictures, the
/// pictures drawn as they are and inverted by the system, as Mail's. Where
/// the page does not take it, the page is as before. A light letter's
/// photos are inverted by a filter of their own under the switch, a try:
/// if that filter does not draw either, they stay natural, as before.
///
/// **Found on the test iPad, 2026-10-30 (r6-q-copy).** The colour filter
/// took, the photos inverted as Mail's. The try did not: a light letter's
/// pictures stayed natural, so they are inverted by an element put round
/// each while the switch is on (`wrapperTag`). And with the switch turned
/// off under an open letter its photos stayed hue-turned until it was
/// opened again. Taken then for a picture drawn while the switch was on
/// that went on being drawn without its own filter after the class came
/// off, the script had WebKit draw each such picture anew as the switch
/// went off, nothing moved; that redraw went at r6-s-copy.
///
/// **Found on the test iPad, 2026-10-30 (r6-r-copy).** The photos stayed
/// hue-turned with the switch off: the script chose them, but changed
/// their `display` and put it back in one turn, which did not draw them
/// anew. A picture out of what WebKit draws for a frame and put back drew
/// natural, as did a page built anew. So each was taken out until a frame
/// had been drawn without it, a box of its size in its place, and put
/// back.
///
/// **Found on the test iPad, 2026-10-30 (r6-s-copy).** That changed
/// nothing: the pictures were drawn anew 14 ms after the off and stayed
/// hue-turned, the same at 2 s, 21 s and 100 s, the one out of sight too.
/// Not a stale drawing of the pictures: after the off the page's own
/// invert on `#bm` does not reach them. Every way that drew them natural
/// built that filtered ancestor anew: a page built anew, a stack letter's
/// body closed and opened. So the script draws nothing anew now; going
/// off, it answers how many pictures have a filter of their own and where
/// the page is (`Off`), and the pane builds the page shown anew for the
/// switch as it is, from what it holds, nothing fetched, its place kept
/// (`Anew`, `Place`).
///
/// Off, every page is byte for byte as it was. On, a page is built with
/// the class on its `<html>` and its rules in a sheet of their own in its
/// head (`root`, `sheet`); a change of the switch while a page is shown
/// puts the class on or takes it off by the pane's script, the sheet put
/// in if the page has none (`Toggle`), so nothing scrolls; and the
/// elements round a light letter's pictures go and come with the class.
/// Going off under a page whose pictures have a filter of their own, the
/// page is built anew besides.
///
/// Pure, so the suite on Linux tests it.
enum SmartInvert {

    /// The class the page's `<html>` has while Smart Invert is on.
    static let className = "bm-si"

    /// The id of the sheet in the page's head that holds the rules.
    static let sheetID = "bm-si"

    /// The photos of a letter inside `scope`, under the class: `img` and
    /// `video` alone of what the pane's invert names as pictures
    /// (`PanePage.letter`, `ConversationDocument.html`). The round measured
    /// an `img` photo, drawn with one of the page's two inverts under
    /// Smart Invert; the PDF tile's `svg` sheet came out with both, black on
    /// the light tile as Mail's page is the inversion, and would go white
    /// on white with no filter. So `svg`, `picture` and an element with a
    /// `background-image`, the busy ring among them, keep the pane's own
    /// rule, as with the switch off.
    static func pictures(in scope: String) -> String {
        ["img", "video"]
            .map { "html.\(className) \(scope) \($0)" }.joined(separator: ", ")
    }

    /// The rule for a letter the pane inverts inside `scope`, `#bm` on its
    /// page or `.bm-html` in a stack: its photos with no filter. The page
    /// keeps its invert.
    static func inverted(in scope: String) -> String {
        pictures(in: scope) + " { filter: none; }"
    }

    /// The rules for a light letter, `scope` the element that holds its
    /// markup and its white, `#bm` on its page or `.bm-light` in a stack:
    /// inverted plainly, and Mail's line in it (`RemoteContent.line`)
    /// inverted back, so it is the pane's colour as before. Its pictures,
    /// `img` and `video`, inverted once more by the element the pane's
    /// script puts round each while the switch is on (`wrapper(in:)`), so
    /// that with the system's inversion they come out inverted, as Mail's.
    static func light(in scope: String) -> String {
        "html.\(className) \(scope) { filter: invert(1); }\n"
            + "html.\(className) \(scope) .\(RemoteContent.lineClass) { filter: invert(1); }\n"
            + wrapper(in: scope)
    }

    /// The element the pane's script puts round each picture of a light
    /// letter while the switch is on, and takes off as it goes off
    /// (`ConversationDocument.script`'s `bmWrapPictures`).
    ///
    /// **Found on the test iPad, 2026-10-30 (r6-q-copy).** A light
    /// letter's pictures stayed natural under the switch with a filter of
    /// their own, `invert(1)` on `img` and `video`, where Mail's come out
    /// inverted: a picture's own filter does not draw under it, while the
    /// page's filter on a picture's ancestors does. So the invert is on
    /// an element round the picture: inline, or a block round a picture
    /// drawn as a block, as the picture is; every property its parent's
    /// or as from the factory (`all: unset`), so it has no box of its own
    /// to draw. A sender's rule that names the picture by its parent or
    /// its siblings (`td > img`, `img + br`) stops matching it inside the
    /// element; the script takes the element off where the picture's
    /// computed box, its `display`, size, margins, padding, borders,
    /// `vertical-align`, float, position or `box-sizing`, or the
    /// `display` of the elements beside it changed, or where the picture
    /// or what holds it moved or changed size. Another property such a
    /// rule sets, a colour or a radius, is not read, and changes under
    /// the switch. A tag no letter uses, so no sender's rule names it.
    static let wrapperTag = "bm-si-picture"

    /// The rule for the element round a light letter's picture inside
    /// `scope`, under the class: its own properties its parent's, and the
    /// invert. The script puts the element round a picture only where the
    /// page's sheet for the switch has this rule.
    static func wrapper(in scope: String) -> String {
        "html.\(className) \(scope) \(wrapperTag) { all: unset; filter: invert(1); }"
    }

    /// The second class the page's `<html>` has, with `className`, while
    /// a letter it inverts is made dark by WebKit's colour filter
    /// (`ColourFilter`), and the id of the sheet of its rules.
    static let colourFilterClass = "bm-cf"
    static let colourFilterSheetID = "bm-cf"

    /// What the colour filter's rules take off a letter's pictures: every
    /// kind the pane's invert names (`PanePage.letter`,
    /// `ConversationDocument.html`).
    static let allPictures = ["img", "video", "picture", "svg", "[style*=\"background-image\"]"]

    /// The rules for a letter the pane inverts inside `scope`, `#bm` on its
    /// page or `.bm-html` in a stack, made dark by WebKit's colour filter
    /// as Mail's is, under both classes alone (r6-p-copy, 2026-10-29):
    /// - the letter: no filter, no white of its own, so the pane's black
    ///   is behind it, and the colour filter, whose white is rgb(51, 51,
    ///   51), not black;
    /// - its pictures, every kind: no filter, drawn as they are, so the
    ///   system's inversion inverts them, as Mail's;
    /// - Mail's quote bars and the line before a quote: Mail's dark
    ///   colours as they are, out of the colour filter, which cannot reach
    ///   them, as Mail's are in its Dark Mode; and inside them, whatever
    ///   carries a colour of its own, back in the colour filter
    ///   (`quotedOwnColours`);
    /// - Mail's line over held-back pictures: Mail's own colours, out of
    ///   the colour filter;
    /// - his signature's sheet: its white as written, which the colour
    ///   filter makes Mail's grey, rgb(51, 51, 51), by itself.
    /// Links and the sender's own colours are left to the colour filter,
    /// as Mail's are.
    static func colourFilter(in scope: String) -> String {
        let s = "html.\(className).\(colourFilterClass) \(scope)"
        return [
            "\(s) { filter: none; background: transparent; \(ColourFilter.property): \(ColourFilter.value); }",
            allPictures.map { "\(s) \($0)" }.joined(separator: ", ") + " { filter: none; }",
            QuoteBars.css(in: s, palette: QuoteBars.dark),
            QuoteBars.attributionCSS(in: s, palette: QuoteBars.dark),
            "\(s) \(QuoteBars.quote), \(s) .\(QuoteBars.attributionClass), "
                + "\(s) .\(RemoteContent.lineClass) { \(ColourFilter.property): none; }",
            quotedOwnColours(in: s),
            RemoteContent.colourRule(in: s, inverted: false),
            SignatureSheet.css(in: s, colour: SignatureSheet.white),
        ].joined(separator: "\n")
    }

    /// What carries a colour of its own inside a quote or a "wrote:"
    /// line: a style that names a colour, a ground or a border's among
    /// them, a `<font color>`, a `bgcolor`, and a link.
    static let ownColours = ":is([style*=\"color\" i], font[color], [bgcolor], a)"

    /// The colour filter put back, under `s`, on what carries a colour of
    /// its own (`ownColours`) inside a quote or a "wrote:" line, but never
    /// on a quote, such a line or Mail's line itself. WebKit's
    /// `-apple-color-filter` is inherited (its `CSSProperties.json`), so the
    /// quote's `none` reaches everything in it: a sender's own black in a
    /// quote, Apple Mail's forwarded labels or Outlook's `color:black`,
    /// was drawn as written on the pane's black, and so white on white on
    /// screen. With this it is turned as out of a quote, as before at
    /// 7803dbb: light in the render, dark on screen. A quote inside one is
    /// `none` again by its own rule, so its bar and colour stay Mail's.
    static func quotedOwnColours(in s: String) -> String {
        let quoted = ":is(\(QuoteBars.quote), .\(QuoteBars.attributionClass))"
        let notMails = ":not(\(QuoteBars.quote)):not(.\(QuoteBars.attributionClass))"
            + ":not(.\(RemoteContent.lineClass))"
        return "\(s) \(quoted) \(ownColours)\(notMails) "
            + "{ \(ColourFilter.property): \(ColourFilter.value); }"
    }

    /// The colour filter's rules for a letter's own page drawn `scheme`:
    /// a letter inverted alone has them.
    static func colourFilter(for scheme: LetterScheme?) -> String {
        scheme == .inverted ? colourFilter(in: "#bm") : ""
    }

    /// The same for a conversation's stack: its HTML letters inverted.
    static let stackColourFilter = colourFilter(in: ".bm-html")

    /// The rules for a letter's own page drawn `scheme`: "" for a letter in
    /// its own colours and a plain one (`nil`), whose pages are as they
    /// were.
    static func rules(for scheme: LetterScheme?) -> String {
        switch scheme {
        case .inverted?: return inverted(in: "#bm")
        case .light?: return light(in: "#bm")
        case .own?, nil: return ""
        }
    }

    /// The rules for a conversation's stack, for each kind of body in it.
    static let stack = inverted(in: ".bm-html") + "\n" + light(in: ".bm-light")

    /// The page's `<html>` tag: with the class while the switch is on and
    /// the page has rules, as it always was otherwise; and with the colour
    /// filter's class too when it is given the colour filter's rules,
    /// `colourFilter`, which the pane gives only once the page has said it
    /// takes them.
    static func root(on: Bool, rules: String, colourFilter: String = "") -> String {
        guard on && !rules.isEmpty else { return "<html>" }
        return colourFilter.isEmpty
            ? "<html class=\"\(className)\">" : "<html class=\"\(className) \(colourFilterClass)\">"
    }

    /// The sheet of `rules` for the page's head while the switch is on, and
    /// after it the colour filter's, when given; "" otherwise.
    static func sheet(on: Bool, rules: String, colourFilter: String = "") -> String {
        guard on && !rules.isEmpty else { return "" }
        return "<style id=\"\(sheetID)\">\n" + rules + "\n</style>"
            + (colourFilter.isEmpty
                ? "" : "<style id=\"\(colourFilterSheetID)\">\n" + colourFilter + "\n</style>")
    }

    /// The pane's log line for the switch as iOS answered it (B-179's
    /// check): `built`, as a page with rules for it was built; otherwise
    /// when the answer changed. What the check reads to know whether the
    /// switch took under Smart Invert, before it reads the photos.
    static func note(on: Bool, built: Bool) -> String {
        "pane: isInvertColorsEnabled \(on)" + (built ? ", page built" : ", changed")
    }

    /// The start of every page the pane builds, to the end of its `<html>`
    /// tag, with the class; and with the colour filter's too.
    static let onStart = "<!DOCTYPE html><html class=\"\(className)\">"
    static let onStartColourFilter = "<!DOCTYPE html><html class=\"\(className) \(colourFilterClass)\">"

    /// Whether `page` was built with the switch on, with the colour filter
    /// or without.
    static func isOn(inPage page: String) -> Bool {
        page.hasPrefix(onStart) || page.hasPrefix(onStartColourFilter)
    }

    /// Whether `page` was built with the colour filter's class on.
    static func hasColourFilter(inPage page: String) -> Bool { page.hasPrefix(onStartColourFilter) }

    /// `page` with the colour filter's class taken off its root and its
    /// sheet out of its head: for a page built with it that the pane gives
    /// WebKit when the setting no longer reads on, so its letter is never
    /// drawn with its white taken off and no colour filter to make its
    /// words light. The sheet goes too: WebKit, reading it with the setting
    /// off, would keep its `filter: none` and `background: transparent`
    /// and drop every colour filter of it, and the script, finding a sheet
    /// there when the switch came back on, would put the class on over
    /// that, the letter's black words on the pane's black (B-179). The
    /// page is then the page built without the filter, byte for byte.
    static func withoutColourFilter(_ page: String) -> String {
        guard hasColourFilter(inPage: page) else { return page }
        let rest = page.dropFirst(onStartColourFilter.count)
        let start = rest.prefix(65_536)
        let head = start.range(of: "</head>").map { start[..<$0.lowerBound] } ?? start
        guard let open = head.range(of: "<style id=\"\(colourFilterSheetID)\">"),
              let close = head.range(of: "</style>", range: open.upperBound..<head.endIndex)
        else { return onStart + rest }
        return onStart + rest[..<open.lowerBound] + rest[close.upperBound...]
    }

    /// The rules for `page`, a page the pane built, read off its head,
    /// which is the app's alone: a letter's page inverted or light, or a
    /// stack; "" for any other, a plain letter's, one in its own colours,
    /// a notice. For a change of the switch while the page is shown. Read
    /// in its first 64 K characters, which hold the app's head with room
    /// to spare, so a letter of a megabyte is not searched through on the
    /// main thread.
    static func rules(ofPage page: String) -> String {
        let start = page.prefix(65_536)
        let head = start.range(of: "</head>").map { start[..<$0.lowerBound] } ?? start
        if head.contains(PanePage.invertedRule) { return rules(for: .inverted) }
        if head.contains(PanePage.lightRule) { return rules(for: .light) }
        if head.contains(ConversationDocument.invertedRule) { return stack }
        return ""
    }

    /// The colour filter's rules for `page`, read off its head as `rules`
    /// are: a letter's page inverted, a stack; "" for any other.
    static func colourFilter(ofPage page: String) -> String {
        let start = page.prefix(65_536)
        let head = start.range(of: "</head>").map { start[..<$0.lowerBound] } ?? start
        if head.contains(PanePage.invertedRule) { return colourFilter(for: .inverted) }
        if head.contains(ConversationDocument.invertedRule) { return stackColourFilter }
        return ""
    }

    /// What the pane tells the page's script when the switch changes, or
    /// when a page built before the change has loaded: the class on or
    /// off, and the page's rules, put in its head if it has no sheet of
    /// them. Run by `callAsyncJavaScript` in the app's content world, where
    /// `ConversationDocument.script` defined `bmSmartInvert`; the page's
    /// `<html>` is the same element in every world.
    ///
    /// `colourFilter` is the page's colour filter rules, given only while
    /// the switch is on and the page has said it takes the filter, ""
    /// otherwise: the script asks the page again
    /// (`ColourFilter.test`), puts them in a sheet of their own, in place
    /// of any the head has, so WebKit reads them with the setting as it is
    /// now, and puts the colour filter's class on only if it answers yes;
    /// it takes the class off with the switch, or when not given them.
    ///
    /// With the class it puts the element round a light letter's pictures
    /// (`wrapperTag`), and takes it off. Going on, it answers 0; going
    /// off, what the pane needs to know whether to build the page anew,
    /// and where to put it back (`Off`).
    struct Toggle: Equatable {
        let on: Bool
        let rules: String
        var colourFilter: String = ""

        static let script = "return bmSmartInvert(on, rules, colourFilter)"

        var arguments: [String: Any] { ["on": on, "rules": rules, "colourFilter": colourFilter] }
    }

    /// Where the page was as the switch went off: its scroll, `x` and
    /// `y`, and its layout viewport, `width` by `height`, the root's
    /// `clientWidth` and `clientHeight`, which a pinch does not change, in
    /// CSS pixels, as the script read them before it changed anything
    /// (r6-s-copy).
    ///
    /// Put back on the page built anew (`ConversationDocument.script`'s
    /// `bmPutPlace`, run by `script` in the app's content world), once it
    /// has finished, the bodies of a stack in, and its pictures loaded or
    /// a second gone by: scrolled to `x`, `y` only while its layout
    /// viewport is still `width` by `height`, as 3671253's rule had it; a
    /// pane laid out anew meanwhile, the iPad turned, keeps the place
    /// WebKit gives it, as the place was measured in the old layout. A
    /// letter pinched at the off comes back at its place unzoomed: the
    /// zoom is not kept. A stack's hold on the letter it opens at is let
    /// go first, and its keeping then holds the letter at the top where it
    /// is (`bmKeep`). The script answers after two frames more, or half a
    /// second if they do not come, so what the pane lays over the page
    /// while it is built (the pane's still) lifts once the page is drawn
    /// there.
    struct Place: Equatable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        static let script = "return bmPutPlace(x, y, width, height)"

        var arguments: [String: Any] { ["x": x, "y": y, "width": width, "height": height] }
    }

    /// What the script answered as the switch went off (`Toggle`): how
    /// many pictures on the page carry a filter of their own, `img` and
    /// `video`, read by their computed `filter` once the classes are off
    /// (an inverted letter's photos, under the page's invert on `#bm` or
    /// `.bm-html`), and the pictures of a light letter whose elements it
    /// took off (`wrapperTag`), each once; and where the page was.
    struct Off: Equatable {
        let pictures: Int
        let place: Place

        init(pictures: Int, place: Place) {
            self.pictures = pictures
            self.place = place
        }

        /// The script's answer as WebKit hands it back, a dictionary of
        /// numbers; nil for any other, the switch going on answering 0,
        /// or a page whose script did not answer.
        init?(answer: Any?) {
            guard let answer = answer as? [String: Any],
                  let pictures = Self.number(answer["pictures"]), let x = Self.number(answer["x"]),
                  let y = Self.number(answer["y"]), let width = Self.number(answer["width"]),
                  let height = Self.number(answer["height"]) else { return nil }
            self.init(pictures: Int(pictures), place: Place(x: x, y: y, width: width, height: height))
        }

        private static func number(_ value: Any?) -> Double? {
            if let value = value as? Double { return value }
            if let value = value as? Int { return Double(value) }
            if let value = value as? NSNumber { return value.doubleValue }
            return nil
        }
    }

    /// The page shown built anew as the switch goes off (r6-s-copy, B-179),
    /// as the pane keeps it.
    ///
    /// Owed when the script's answer for the off has a picture with a
    /// filter of its own (`switchedOff`): only on a page with rules for
    /// the switch, as only such a page is told (a letter inverted, a
    /// light letter, a stack), and only while the pane still shows the
    /// page the script was run on, committed by WebKit as the script was
    /// sent, and the switch is still off: sent before the commit, the
    /// script ran in the page before it, and its answer, that page's
    /// pictures and place, is not this page's; the page's own end tells it
    /// of the switch again (`MessageDetailViewController`'s `didFinish`).
    /// A page with no such picture is not built anew: the class going is
    /// enough there, as the rounds saw. The switch going on again before
    /// it is built (`switchedOn`), or the pane given something else,
    /// emptied, or drawing again what WebKit lost (`shownElse`), lets it
    /// go. Built by the pane's rebuild for a new
    /// text size (`MessageDetailViewController.restyleIfOwed`), which waits
    /// for the app in front and the pane on screen, so a page under Quick
    /// Look or with the app away is built as they come back, once.
    ///
    /// Its place (`Place`) goes with the page the rebuild gives WebKit
    /// (`given`), and comes back as that page has finished (`finished`),
    /// once; any other page given meanwhile lets it go. With a new text
    /// size owed as well the page is built once, at the size, and its
    /// place not kept, as for a text size alone.
    struct Anew {
        /// The off's answer while the page is owed.
        private(set) var owed: Off?
        /// The place for the page the rebuild is building, until it is
        /// given to WebKit.
        private(set) var building: Place?
        /// The place for the page given, by its navigation.
        private var placing: (navigation: ObjectIdentifier?, place: Place)?
        /// How many pages have been given to WebKit: the script's answer
        /// for an earlier one is not this page's.
        private(set) var shown = 0

        /// The script's answer as the switch went off on the page `shown`
        /// counted, `off` nil for none; `committed` whether WebKit had
        /// committed that page as the script was sent; `stillOff` false
        /// when the switch has been told on since. Whether the page is
        /// owed now.
        mutating func switchedOff(_ off: Off?, shown: Int, committed: Bool, stillOff: Bool) -> Bool {
            guard let off, off.pictures > 0, shown == self.shown, committed, stillOff else { return false }
            owed = off
            return true
        }

        mutating func switchedOn() { owed = nil }

        mutating func shownElse() {
            owed = nil
            building = nil
            placing = nil
        }

        /// The rebuild starting, `textSize` when a new text size is owed
        /// too: the log's line when it builds the page anew for the
        /// switch, nil otherwise.
        mutating func build(textSize: Bool) -> String? {
            guard let off = owed else {
                building = nil
                return nil
            }
            owed = nil
            building = textSize ? nil : off.place
            return Self.line(off.pictures)
        }

        /// A page given to WebKit, `anew` when the rebuild gives it: its
        /// place kept for it, if the rebuild has one.
        mutating func given(_ navigation: ObjectIdentifier?, anew: Bool) {
            shown += 1
            placing = anew ? building.map { (navigation, $0) } : nil
            building = nil
        }

        /// A page has finished: its place, once, if it is the rebuild's.
        mutating func finished(_ navigation: ObjectIdentifier) -> Place? {
            guard let placing, placing.navigation == navigation else { return nil }
            self.placing = nil
            return placing.place
        }

        /// The pane's log line for the page built anew, after the line
        /// for the switch's change (`note`), so a check sees it ran.
        static func line(_ pictures: Int) -> String {
            "pane: Smart Invert off, page built anew (\(pictures) picture\(pictures == 1 ? "" : "s"))"
        }

        /// The pane's log line for the script's answer on the page built
        /// anew (`Place`): whether it put the place back, `placed` nil for
        /// no answer.
        static func putBack(_ placed: Bool?) -> String {
            "pane: page built anew put back (" + (placed.map { "\($0)" } ?? "no answer") + ")"
        }

        /// The pane's log line for the still lifted by its limit
        /// (`stillLimit`), before the page built anew was put back.
        static let stillLifted = "pane: still lifted at its limit"

        /// How long the pane's still of the page as it was can stay over
        /// the page built anew, in seconds, whatever WebKit does: then the
        /// page is shown as it is.
        static let stillLimit: TimeInterval = 2
    }
}
