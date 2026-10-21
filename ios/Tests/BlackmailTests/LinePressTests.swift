import XCTest
@testable import Blackmail

/// A finger on a line of a conversation's stack (B-095).
///
/// Seen on the test iPad 2026-10-21: a finger held a second on a closed
/// letter's line never lit it, nor did a tap, and at about 0.7 s WebKit
/// began to select a word in it, its Copy menu at 1.4 s. WebKit paints no
/// tap highlight on an element as wide as the pane, and the line was text
/// to select. Now a line is not text to select, as Mail's are not; the
/// stack's script lights it from the touch until the finger lifts; and a
/// touch that stays still and lifts within the hold is its tap, the letter
/// toggled by the script and WebKit's own tap stopped, so it never toggles
/// twice. The host has no WebKit: these read the document and the script,
/// as the stack's other tests do.
final class LinePressTests: XCTestCase {

    private var css: String {
        flat(ConversationDocument.html(entries: [], inset: 20, bodyPointSize: 17, lineHeight: 1.4))
    }

    private var script: String { flat(ConversationDocument.script) }

    /// No selection and no callout on the stack's lines and anything in
    /// them; nothing else in the document is made so, the letters' bodies
    /// least of all. WebKit's own tap highlight, never painted on a line,
    /// is off, so it cannot be painted over the script's.
    func testALineIsNotTextToSelectAndALetterIs() {
        XCTAssertTrue(css.contains(
            "body > .bm-letter > .bm-head, body > .bm-letter > .bm-head * { "
                + "-webkit-user-select: none; user-select: none; -webkit-touch-callout: none; }"), css)
        XCTAssertEqual(css.components(separatedBy: "-webkit-user-select").count, 2, css)
        XCTAssertEqual(css.components(separatedBy: "touch-callout").count, 2, css)
        XCTAssertTrue(css.contains("-webkit-tap-highlight-color: transparent;"), css)
        XCTAssertFalse(css.contains("-webkit-tap-highlight-color: rgba"), css)
    }

    /// Lit from the touch, by a class of the script's, and the light goes
    /// at the lift, a cancel, a finger that moves or a second finger, a
    /// scroll of the page, and at the end of the hold.
    func testTheLineIsLitFromTheTouchUntilItLifts() {
        XCTAssertTrue(css.contains(
            "body > .bm-letter > .bm-head.bm-press { background: rgba(255,255,255,0.08); }"), css)
        for wiring in [
            "var touch = event.touches[0]; head.classList.add('bm-press');",
            "function bmUnpress() { if (!bmPress) return; clearTimeout(bmPress.timer); "
                + "bmPress.head.classList.remove('bm-press'); bmPress = null; }",
            "timer: setTimeout(function () { head.classList.remove('bm-press'); }, bmHold) };",
            "function bmPressUp(event) { var press = bmPress; if (!press) return; bmUnpress();",
            "function bmPressMove(event) { if (bmPress && (event.touches.length !== 1 "
                + "|| !bmStill(bmPress, event.touches[0]))) bmUnpress(); }",
            "function bmScroll() { if (bmMine !== null && Math.abs(window.pageYOffset - bmMine) <= 1) return; "
                + "bmScrolled = performance.now(); bmUnpress(); }",
            "window.addEventListener('touchstart', bmPressDown, { capture: true, passive: true });",
            "window.addEventListener('touchmove', bmPressMove, { capture: true, passive: true });",
            "window.addEventListener('touchcancel', bmUnpress, { capture: true, passive: true });",
            "window.addEventListener('scroll', bmScroll, { passive: true });",
        ] {
            XCTAssertTrue(script.contains(wiring), wiring)
        }
    }

    /// The tap: one finger, still to 10 px, lifted within 1.2 s, the line
    /// where it was under it. The script toggles the letter and stops
    /// WebKit's tap, which waits on a touchend a listener may cancel, so
    /// the listener is not passive. Past the hold, or the line moved, the
    /// lift does nothing, and WebKit's tap is stopped too. A click on a line
    /// within a second of a touch the script took is let pass, one only.
    func testAStillTouchLiftedWithinTheHoldIsTheTapAndOnlyOnce() {
        for wiring in [
            "var bmHold = 1200;",
            "function bmStill(press, touch) { return !!touch && Math.abs(touch.clientX - press.x) <= 10 "
                + "&& Math.abs(touch.clientY - press.y) <= 10; }",
            "if (event.touches.length !== 0 || !bmStill(press, event.changedTouches[0])) return; "
                + "event.preventDefault(); bmQuiet = performance.now() + 1000; "
                + "if (performance.now() - press.at > bmHold) return; "
                + "if (Math.abs(press.head.getBoundingClientRect().top - press.top) > 10) return; "
                + "bmToggle(press.head.parentNode); }",
            "window.addEventListener('touchend', bmPressUp, { capture: true, passive: false });",
            "head.addEventListener('click', function (event) { "
                + "if (performance.now() < bmQuiet) { bmQuiet = 0; return; } "
                + "bmToggle(event.currentTarget.parentNode); });",
        ] {
            XCTAssertTrue(script.contains(wiring), wiring)
        }
        XCTAssertEqual(script.components(separatedBy: "preventDefault").count, 2, "one, at the tap")
        XCTAssertEqual(script.components(separatedBy: "bmToggle(").count, 4,
                       "defined, the click, the tap")
    }

    /// A touch that lands on a page still scrolling only stops it, as in
    /// WebKit, which takes no tap then; a second finger is a pinch. Neither
    /// is lit, and WebKit decides.
    func testATouchOnAScrollingPageOrWithASecondFingerIsNotATap() {
        XCTAssertTrue(script.contains(
            "function bmPressDown(event) { bmUnpress(); "
                + "if (event.touches.length !== 1 || performance.now() - bmScrolled < 200) return;"), script)
    }

    /// The script's own scroll, keeping his place as a letter above him
    /// grows, moves nothing under the finger, and does not end the press.
    func testTheScriptsOwnScrollDoesNotEndAPress() {
        XCTAssertTrue(script.contains("var bmMine = null;"), script)
        XCTAssertTrue(script.contains(
            "if (moved !== 0) window.scrollBy(0, moved); } bmMine = window.pageYOffset; bmTake(); }"), script)
    }

    /// VoiceOver's activation of a line is the click it was. WebKit sends
    /// an element a touch in place of the click when it or a node above it
    /// has a touch listener, so the touches are heard on the window, which
    /// is not a node, and on nothing else.
    func testTheTouchesAreHeardOnTheWindowSoVoiceOverStillClicks() {
        let touchListeners = script.components(separatedBy: "addEventListener('touch").count - 1
        XCTAssertEqual(touchListeners, 4, script)
        XCTAssertEqual(script.components(separatedBy: "window.addEventListener('touch").count - 1,
                       touchListeners, script)
        XCTAssertFalse(script.contains("document.addEventListener"), script)
        XCTAssertFalse(script.contains("body.addEventListener"), script)
        XCTAssertEqual(script.components(separatedBy: "head.addEventListener(").count - 1, 1,
                       "the click alone on a line")
    }

    /// Lines put in at the bottom later are lit and tapped as the first
    /// ones are: a line is one `bmWire` wired, and `bmAppend` wires them.
    /// A line drawn by a letter's own markup is never wired, and is not.
    func testLinesPutInLaterAreLitAndTappedAsTheFirstAndALettersOwnAreNot() {
        for wiring in [
            "function bmWire(head) { bmLines.push(head);",
            "var head = section.querySelector('.bm-head'); if (head) bmWire(head);",
            "function bmLineAt(node) { for (; node && node !== document.body; node = node.parentNode) { "
                + "if (bmLines.indexOf(node) !== -1) return node; } return null; }",
            "var head = bmLineAt(event.target); if (!head) return;",
            "bmToggle(press.head.parentNode);",
        ] {
            XCTAssertTrue(script.contains(wiring), wiring)
        }
        XCTAssertEqual(script.components(separatedBy: "bmLines.push(").count - 1, 1, script)
        XCTAssertEqual(script.components(separatedBy: "bmWire(").count - 1, 3,
                       "defined, the first lines, those put in later")
    }

    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }
}
