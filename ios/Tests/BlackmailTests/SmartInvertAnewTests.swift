import XCTest
@testable import Blackmail

/// The page shown built anew as the iPad's Smart Invert goes off over
/// pictures with a filter of their own (B-179, round r6-s-copy of
/// 2026-10-30): which pages are built anew and which not, the place kept
/// for the page built anew and given back once, and the log's line. What
/// the script answers and how it puts the place back is run in node in
/// `SmartInvertPicturesTests`.
final class SmartInvertAnewTests: XCTestCase {

    /// Stands for one of WebKit's navigations, by its identity.
    private final class Navigation {}

    private let place = SmartInvert.Place(x: 0, y: 1234, width: 768, height: 954)

    private func off(_ pictures: Int) -> SmartInvert.Off {
        SmartInvert.Off(pictures: pictures, place: place)
    }

    // MARK: - The answer

    /// The script's answer read as WebKit hands it back, numbers as
    /// `NSNumber`, or as Swift's own; nothing for the switch going on,
    /// which answers 0, for an answer with a number missing, or none.
    func testTheAnswerIsReadOffTheScriptsDictionary() {
        let webKit: [String: Any] = ["pictures": NSNumber(value: 2), "x": NSNumber(value: 0),
                                     "y": NSNumber(value: 1234.5), "width": NSNumber(value: 768),
                                     "height": NSNumber(value: 954)]
        XCTAssertEqual(SmartInvert.Off(answer: webKit),
                       SmartInvert.Off(pictures: 2, place: .init(x: 0, y: 1234.5, width: 768, height: 954)))
        let swift: [String: Any] = ["pictures": 0, "x": 0, "y": 10.0, "width": 768, "height": 954]
        XCTAssertEqual(SmartInvert.Off(answer: swift)?.pictures, 0)
        XCTAssertEqual(SmartInvert.Off(answer: swift)?.place.y, 10)
        XCTAssertNil(SmartInvert.Off(answer: 0))
        XCTAssertNil(SmartInvert.Off(answer: nil))
        XCTAssertNil(SmartInvert.Off(answer: ["pictures": 1, "x": 0, "y": 0, "width": 768] as [String: Any]))
        XCTAssertNil(SmartInvert.Off(answer: ["pictures": "1", "x": 0, "y": 0, "width": 768,
                                              "height": 954] as [String: Any]))
    }

    /// The place given to the script by name, as `bmPutPlace` takes it.
    func testThePlaceIsGivenToTheScript() {
        XCTAssertEqual(SmartInvert.Place.script, "return bmPutPlace(x, y, width, height)")
        let arguments = place.arguments
        XCTAssertEqual(arguments["x"] as? Double, 0)
        XCTAssertEqual(arguments["y"] as? Double, 1234)
        XCTAssertEqual(arguments["width"] as? Double, 768)
        XCTAssertEqual(arguments["height"] as? Double, 954)
        XCTAssertEqual(arguments.count, 4)
    }

    // MARK: - Which pages

    /// A page with a picture that carries a filter of its own is owed a
    /// build anew; one with none is not, the class going being enough
    /// there; and no answer at all owes nothing.
    func testOnlyAPageWithSuchPicturesIsBuiltAnew() {
        var anew = SmartInvert.Anew()
        XCTAssertFalse(anew.switchedOff(off(0), shown: 0, stillOff: true))
        XCTAssertNil(anew.owed)
        XCTAssertFalse(anew.switchedOff(nil, shown: 0, stillOff: true))
        XCTAssertNil(anew.owed)
        XCTAssertTrue(anew.switchedOff(off(3), shown: 0, stillOff: true))
        XCTAssertEqual(anew.owed, off(3))
    }

    /// The answer for a page the pane has replaced since, or with the
    /// switch told on again since, owes nothing.
    func testAnAnswerForAnotherPageOrAfterOnOwesNothing() {
        var anew = SmartInvert.Anew()
        let shown = anew.shown
        anew.given(ObjectIdentifier(Navigation()), anew: false)
        XCTAssertFalse(anew.switchedOff(off(2), shown: shown, stillOff: true))
        XCTAssertFalse(anew.switchedOff(off(2), shown: anew.shown, stillOff: false))
        XCTAssertNil(anew.owed)
        XCTAssertTrue(anew.switchedOff(off(2), shown: anew.shown, stillOff: true))
    }

    /// Owed and not yet built: the switch on again, or the pane given
    /// another letter or emptied, lets it go, so nothing is built that
    /// need not be.
    func testOnAgainOrAnotherLetterLetsTheBuildGo() {
        var anew = SmartInvert.Anew()
        XCTAssertTrue(anew.switchedOff(off(1), shown: 0, stillOff: true))
        anew.switchedOn()
        XCTAssertNil(anew.owed)
        XCTAssertNil(anew.build(textSize: false))

        XCTAssertTrue(anew.switchedOff(off(1), shown: 0, stillOff: true))
        anew.shownElse()
        XCTAssertNil(anew.owed)
        XCTAssertNil(anew.build(textSize: false))
        XCTAssertNil(anew.building)
    }

    // MARK: - The place

    /// Built: the log's line, once; the place kept for the page the
    /// rebuild gives, and handed back once that page has finished, once,
    /// and for no other navigation.
    func testThePlaceGoesWithThePageBuiltAnewAndComesBackOnce() {
        var anew = SmartInvert.Anew()
        XCTAssertTrue(anew.switchedOff(off(2), shown: 0, stillOff: true))
        XCTAssertEqual(anew.build(textSize: false), "pane: Smart Invert off, page built anew (2 pictures)")
        XCTAssertNil(anew.owed)
        XCTAssertEqual(anew.building, place)
        XCTAssertNil(anew.build(textSize: false), "built once")
        XCTAssertNil(anew.building)

        XCTAssertTrue(anew.switchedOff(off(2), shown: 0, stillOff: true))
        _ = anew.build(textSize: false)
        let built = Navigation(), other = Navigation()
        anew.given(ObjectIdentifier(built), anew: true)
        XCTAssertNil(anew.building)
        XCTAssertNil(anew.finished(ObjectIdentifier(other)))
        XCTAssertEqual(anew.finished(ObjectIdentifier(built)), place)
        XCTAssertNil(anew.finished(ObjectIdentifier(built)), "once")
    }

    /// Another page given before the one built anew, or after it before
    /// it has finished, or the pane emptied: the place goes, and no page
    /// is scrolled to it.
    func testAnyOtherPageLetsThePlaceGo() {
        var anew = SmartInvert.Anew()
        XCTAssertTrue(anew.switchedOff(off(1), shown: 0, stillOff: true))
        _ = anew.build(textSize: false)
        let loading = Navigation(), letter = Navigation()
        anew.given(ObjectIdentifier(loading), anew: false)
        anew.given(ObjectIdentifier(letter), anew: true)
        XCTAssertNil(anew.finished(ObjectIdentifier(loading)))
        XCTAssertNil(anew.finished(ObjectIdentifier(letter)))

        XCTAssertTrue(anew.switchedOff(off(1), shown: anew.shown, stillOff: true))
        _ = anew.build(textSize: false)
        let built = Navigation(), next = Navigation()
        anew.given(ObjectIdentifier(built), anew: true)
        anew.given(ObjectIdentifier(next), anew: false)
        XCTAssertNil(anew.finished(ObjectIdentifier(built)))
        XCTAssertNil(anew.finished(ObjectIdentifier(next)))

        XCTAssertTrue(anew.switchedOff(off(1), shown: anew.shown, stillOff: true))
        _ = anew.build(textSize: false)
        let emptied = Navigation()
        anew.given(ObjectIdentifier(emptied), anew: true)
        anew.shownElse()
        XCTAssertNil(anew.finished(ObjectIdentifier(emptied)))
    }

    /// A new text size owed as well: the page built once, at the size,
    /// the line still written, and its place not kept, as for a text size
    /// alone. A rebuild for a text size alone keeps no place and writes
    /// no line.
    func testWithANewTextSizeThePlaceIsNotKept() {
        var anew = SmartInvert.Anew()
        XCTAssertTrue(anew.switchedOff(off(1), shown: 0, stillOff: true))
        XCTAssertEqual(anew.build(textSize: true), "pane: Smart Invert off, page built anew (1 picture)")
        XCTAssertNil(anew.building)
        let built = Navigation()
        anew.given(ObjectIdentifier(built), anew: true)
        XCTAssertNil(anew.finished(ObjectIdentifier(built)))

        XCTAssertNil(anew.build(textSize: true))
        let sized = Navigation()
        anew.given(ObjectIdentifier(sized), anew: true)
        XCTAssertNil(anew.finished(ObjectIdentifier(sized)))
    }

    /// The log's line, one picture or more.
    func testTheLogNamesThePageBuiltAnew() {
        XCTAssertEqual(SmartInvert.Anew.line(1), "pane: Smart Invert off, page built anew (1 picture)")
        XCTAssertEqual(SmartInvert.Anew.line(4), "pane: Smart Invert off, page built anew (4 pictures)")
    }

    // MARK: - The pane

    /// The pane, read: the rebuild a text size has builds the page anew
    /// too, waiting as it does for the app in front and the pane on
    /// screen, its line written as it starts, the letter and the stack
    /// given with `anew`; the still laid over the web view for the page
    /// built anew and lifted by any other page; the place put back once
    /// that page has finished, after its letters from Sent Mail, its
    /// bodies and its dates; a new letter, a conversation and the pane
    /// emptied letting it all go.
    func testThePaneBuildsThePageAnewAndPutsItBack() throws {
        let pane = try TextSizeTests.source("UI/MessageDetailViewController.swift")
        for wiring in [
            "guard restyleOwed || builtAnew.owed != nil, UIApplication.shared.applicationState == .active, "
                + "viewIfLoaded?.window != nil else { return } "
                + "if let line = builtAnew.build(textSize: restyleOwed) { Diagnostics.log(.note, line) } "
                + "restyleOwed = false",
            "self.message?.id == m.id else { return } self.draw(m, page: page, anew: true) })",
            "renderConversation(entries, anew: true) for (id, body) in again.bodies { fill(id, body) }",
            "let navigation = webView.loadHTMLString(html, baseURL: nil) "
                + "document.loaded(content, navigation: navigation.map(ObjectIdentifier.init)) "
                + "paneCover.loaded(navigation.map(ObjectIdentifier.init)) "
                + "if anew && builtAnew.building != nil { holdStill() } else { liftStill() } "
                + "builtAnew.given(navigation.map(ObjectIdentifier.init), anew: anew) }",
            "for insert in finished.inserts { run(insert) } for fill in finished.fills { run(fill) } "
                + "if let dates = finished.dates { run(dates) } "
                + "if let place = builtAnew.finished(ObjectIdentifier(navigation)) { putBack(place) }",
            "webView.callAsyncJavaScript(SmartInvert.Place.script, arguments: place.arguments, "
                + "in: nil, in: .defaultClient) { [weak self] _ in "
                + "guard let self, self.stills == held else { return } self.liftStill() }",
            "guard let shot = webView.snapshotView(afterScreenUpdates: false) else { return }",
            "view.insertSubview(shot, aboveSubview: webView)",
            "DispatchQueue.main.asyncAfter(deadline: .now() + SmartInvert.Anew.stillLimit) { [weak self] in "
                + "guard let self, self.stills == held else { return } self.liftStill() }",
            "func showEmpty() { loads.supersede() liftCover() holdBackTheWeb() builtAnew.shownElse() liftStill()",
            "webView.isHidden = false setActionsEnabled(true) builtAnew.shownElse() let repository",
            "webView.isHidden = false setActionsEnabled(true) builtAnew.shownElse() let besides",
            "Diagnostics.log(.note, \"webview: content process ended\") liftStill()",
        ] {
            XCTAssertTrue(pane.contains(wiring), wiring)
        }
        XCTAssertFalse(pane.contains("redrawn"))
        XCTAssertEqual(pane.components(separatedBy: "anew: true").count - 1, 2, "the letter and the stack")
    }
}
