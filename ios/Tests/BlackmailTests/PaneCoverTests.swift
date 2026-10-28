import XCTest
@testable import Blackmail

/// The cover over the reading pane from a tap on another letter until
/// WebKit has painted what goes in its place, half a second at most
/// (B-149, `PaneCover`).
///
/// The test iPad showed the letter he had left under the new letter's
/// header for one or two frames in 3 taps of 7 (B-098): the header is
/// UIKit's and changes at the tap, the web view shows what it painted last
/// until it has painted the next document. Mail covers its letter while
/// the next loads, by the names in its code. The cover is drawn by the
/// pane, which is UIKit and does not build here: what it goes by runs
/// here, and its wiring is read from the source.
final class PaneCoverTests: XCTestCase {

    /// Navigations as WebKit hands them over, by object.
    private final class Navigation {}

    private let loading = Navigation()
    private let page = Navigation()
    private let before = Navigation()

    private func id(_ n: Navigation) -> ObjectIdentifier { ObjectIdentifier(n) }

    // MARK: - Up and down

    /// Up at the tap; down at the first paint of the document the pane gave
    /// the web view after it, once that has committed, and not before: a
    /// paint heard before the commit is the letter he left, still on
    /// screen, and so is one of a document given before the tap.
    func testTheCoverIsUpFromTheTapUntilTheNewDocumentIsPainted() {
        var cover = PaneCover()
        XCTAssertFalse(cover.isUp)
        XCTAssertFalse(cover.rendered(PaneCover.painted), "nothing to lift")

        cover.committed(id(before))
        _ = cover.tapped()
        XCTAssertTrue(cover.isUp)
        XCTAssertFalse(cover.rendered(PaneCover.firstMeaningfulPaint), "the letter before's paint")
        cover.committed(id(before))
        XCTAssertFalse(cover.rendered(PaneCover.firstMeaningfulPaint), "a document from before the tap")

        cover.loaded(id(loading))
        XCTAssertFalse(cover.rendered(PaneCover.firstMeaningfulPaint), "not committed")
        XCTAssertTrue(cover.isUp)
        cover.committed(id(loading))
        XCTAssertTrue(cover.isUp, "committed, not yet painted")
        XCTAssertTrue(cover.rendered(PaneCover.firstMeaningfulPaint))
        XCTAssertFalse(cover.isUp)
        XCTAssertFalse(cover.rendered(PaneCover.firstMeaningfulPaint), "down once")
    }

    /// "Loading…" given, and the letter's page given before "Loading…" was
    /// painted, a letter kept on the iPad: the cover waits for the page, the
    /// last given, and a commit or paint of "Loading…" lifts nothing.
    func testTheCoverWaitsForTheLastDocumentGiven() {
        var cover = PaneCover()
        _ = cover.tapped()
        cover.loaded(id(loading))
        cover.loaded(id(page))
        cover.committed(id(loading))
        XCTAssertFalse(cover.rendered(PaneCover.painted))
        cover.committed(id(page))
        XCTAssertTrue(cover.rendered(PaneCover.firstMeaningfulPaint))
        XCTAssertFalse(cover.isUp)
    }

    /// The two painting milestones WebKit sends with the layers lift it,
    /// alone or with others, and nothing else WebKit says: not its first
    /// layout, which comes before anything is painted, nor its first
    /// paint, nor the others. The bits as WebKit's `_WKRenderingProgressEvents`
    /// has them, and the names reached.
    func testEachPaintingMilestoneLiftsItAndNothingElse() {
        XCTAssertEqual(PaneCover.firstVisuallyNonEmptyLayout, 2)
        XCTAssertEqual(PaneCover.firstPaintWithSignificantArea, 4)
        XCTAssertEqual(PaneCover.firstPaint, 64)
        XCTAssertEqual(PaneCover.firstMeaningfulPaint, 256)
        XCTAssertEqual(PaneCover.painted, 4 | 256)
        XCTAssertEqual(PaneCover.callback, "_webView:renderingProgressDidChange:")
        XCTAssertEqual(PaneCover.setter, "_setObservedRenderingProgressEvents:")
        XCTAssertEqual("_set" + PaneCover.key.prefix(1).uppercased() + PaneCover.key.dropFirst() + ":",
                       PaneCover.setter, "the key reaches the setter, `_set<Key>:`")

        for events: UInt in [4, 256, 4 | 2, 256 | 64, 0xFFFF] {
            var cover = PaneCover()
            _ = cover.tapped()
            cover.loaded(id(page))
            cover.committed(id(page))
            XCTAssertTrue(cover.rendered(events), "\(events)")
        }
        for events: UInt in [0, 1, 2, 8, 16, 32, 64, 128, 2 | 64, 1 | 2 | 8 | 16 | 32 | 64 | 128] {
            var cover = PaneCover()
            _ = cover.tapped()
            cover.loaded(id(page))
            cover.committed(id(page))
            XCTAssertFalse(cover.rendered(events), "\(events)")
            XCTAssertTrue(cover.isUp)
        }
    }

    /// The test iPad, 2026-10-27: a letter kept on the iPad, its page given
    /// within milliseconds of "Loading…", and WebKit's word of its first
    /// layout coming before its pixels; lifted on it, the letter before
    /// showed under the new header for one or two frames. The cover stays
    /// up through the layout and lifts at the paint WebKit sends with the
    /// layers, or at the limit if none comes.
    func testTheFirstLayoutAloneLeavesTheCoverUpUntilThePaintOrTheLimit() {
        var cover = PaneCover()
        let tap = cover.tapped()
        cover.loaded(id(loading))
        cover.loaded(id(page))
        cover.committed(id(page))
        XCTAssertFalse(cover.rendered(PaneCover.firstVisuallyNonEmptyLayout), "laid out, not painted")
        XCTAssertTrue(cover.isUp)
        XCTAssertTrue(cover.rendered(PaneCover.firstPaintWithSignificantArea | PaneCover.firstMeaningfulPaint))
        XCTAssertFalse(cover.isUp)
        XCTAssertFalse(cover.limitPassed(tap), "painted first")

        let next = cover.tapped()
        cover.loaded(id(page))
        cover.committed(id(page))
        XCTAssertFalse(cover.rendered(PaneCover.firstVisuallyNonEmptyLayout | PaneCover.firstPaint))
        XCTAssertTrue(cover.isUp, "no paint with the layers")
        XCTAssertTrue(cover.limitPassed(next), "the limit lifts it")
        XCTAssertFalse(cover.isUp)
    }

    // MARK: - Never long

    /// Never longer than half a second: the limit of the last tap lifts
    /// it, whatever WebKit has said; the limit of a tap before lifts
    /// nothing, the cover of the tap after it waiting for its own.
    func testTheLimitLiftsItAndOnlyTheLastTapsLimit() {
        XCTAssertEqual(PaneCover.limit, 0.5)
        var cover = PaneCover()
        let first = cover.tapped()
        cover.loaded(id(loading))
        let second = cover.tapped()
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(cover.limitPassed(first), "an earlier tap's")
        XCTAssertTrue(cover.isUp)
        XCTAssertTrue(cover.limitPassed(second))
        XCTAssertFalse(cover.isUp)
        XCTAssertFalse(cover.limitPassed(second), "down once")

        // Painted first: its limit then lifts nothing.
        let third = cover.tapped()
        cover.loaded(id(page))
        cover.committed(id(page))
        XCTAssertTrue(cover.rendered(PaneCover.firstMeaningfulPaint))
        XCTAssertFalse(cover.limitPassed(third))
    }

    /// Where WebKit tells nothing of its paint, the cover lifts at the end
    /// of the document awaited, and only then; where it does, the end lifts
    /// nothing, since it can come before the paint. A document the pane
    /// gave no navigation for waits for the limit.
    func testWithNoWordOfThePaintTheEndOfTheDocumentLiftsIt() {
        var cover = PaneCover()
        _ = cover.tapped()
        cover.loaded(id(page))
        XCTAssertFalse(cover.finished(id(loading), painting: false), "another document")
        XCTAssertFalse(cover.finished(id(page), painting: true), "the paint is to come")
        XCTAssertTrue(cover.isUp)
        XCTAssertTrue(cover.finished(id(page), painting: false))
        XCTAssertFalse(cover.isUp)

        let tap = cover.tapped()
        cover.loaded(nil)
        cover.committed(id(page))
        XCTAssertFalse(cover.rendered(PaneCover.painted))
        XCTAssertFalse(cover.finished(id(page), painting: false))
        XCTAssertTrue(cover.limitPassed(tap))
    }

    /// A document given before the tap is not waited for: one given while
    /// the cover was down, after the pane emptied, and one given under the
    /// cover of a tap before, a row tapped and another at once, which
    /// commits and paints after the second tap. Each tap's cover waits for
    /// the document given after it.
    func testADocumentGivenBeforeTheTapIsNotWaitedFor() {
        var cover = PaneCover()
        _ = cover.tapped()
        cover.lift()
        XCTAssertFalse(cover.isUp)
        cover.loaded(id(page))
        _ = cover.tapped()
        cover.committed(id(page))
        XCTAssertFalse(cover.rendered(PaneCover.painted), "given while it was down")
        cover.loaded(id(loading))
        cover.committed(id(loading))
        XCTAssertTrue(cover.rendered(PaneCover.painted))

        _ = cover.tapped()
        cover.loaded(id(before))
        _ = cover.tapped()
        cover.committed(id(before))
        XCTAssertFalse(cover.rendered(PaneCover.painted), "given under the tap before")
        XCTAssertTrue(cover.isUp)
        cover.loaded(id(page))
        cover.committed(id(page))
        XCTAssertTrue(cover.rendered(PaneCover.painted))
    }

    // MARK: - The pane

    /// The pane, read: the cover over the web view, under the words of an
    /// empty pane, in the pane's own colour and hidden at first; up first
    /// thing in each `show`, before the header is given the letter, and
    /// nowhere else, so never for a letter opened by its line, a body, his
    /// letters, a letter come into the conversation or a page drawn again;
    /// down when the pane empties; each document the pane gives the web
    /// view told to it; WebKit's commit, its paint by the private name, and
    /// a document's end where there is no paint; the limit by `limit`, the
    /// last tap's. The events asked for by the private setter, only where
    /// the web view has it.
    func testThePaneCoversAtATapAndAtNothingElse() throws {
        let code = try source("UI/MessageDetailViewController.swift")
        XCTAssertTrue(code.contains("view.addSubview(header) view.addSubview(webView) view.addSubview(cover) "
                                        + "view.addSubview(placeholder)"))
        XCTAssertTrue(code.contains("cover.backgroundColor = Theme.canvas cover.isHidden = true"))
        for edge in ["top", "leading", "trailing", "bottom"] {
            XCTAssertTrue(code.contains("cover.\(edge)Anchor.constraint(equalTo: webView.\(edge)Anchor)"), edge)
        }
        // Then the pictures from the web held back afresh (B-168), before
        // anything else.
        XCTAssertTrue(code.contains("func show(summary: MessageSummary) { coverPane() holdBackTheWeb() "
                                        + "self.summary = summary"))
        XCTAssertTrue(code.contains("func show(thread: MessageThread, completing: UInt64?) { coverPane() "
                                        + "holdBackTheWeb() summary = thread.newest"))
        XCTAssertEqual(code.components(separatedBy: "coverPane()").count - 1, 3, "defined, and in each show")
        XCTAssertEqual(code.components(separatedBy: "paneCover.tapped()").count - 1, 1)
        XCTAssertTrue(code.contains("func showEmpty() { loads.supersede() liftCover()"))
        XCTAssertTrue(code.contains(
            "let navigation = webView.loadHTMLString(html, baseURL: nil) "
                + "document.loaded(content, navigation: navigation.map(ObjectIdentifier.init)) "
                + "paneCover.loaded(navigation.map(ObjectIdentifier.init)) }"))
        XCTAssertEqual(code.components(separatedBy: "loadHTMLString(").count - 1, 1, "every document by `load`")
        XCTAssertTrue(code.contains(
            "private func coverPane() { let tap = paneCover.tapped() cover.isHidden = false "
                + "DispatchQueue.main.asyncAfter(deadline: .now() + PaneCover.limit) { [weak self] in "
                + "guard let self, self.paneCover.limitPassed(tap) else { return } self.cover.isHidden = true "
                + "Diagnostics.log(.note, \"pane: cover lifted by its limit\") } }"))
        XCTAssertTrue(code.contains("func webView(_ w: WKWebView, didCommit navigation: WKNavigation!) { "
                                        + "guard let navigation else { return } "
                                        + "paneCover.committed(ObjectIdentifier(navigation)) "
                                        + "for landed in document.didCommit(ObjectIdentifier(navigation)) "
                                        + "{ tell(landed) } }"))
        XCTAssertTrue(code.contains("@objc(\(PaneCover.callback)) "
                                        + "func webView(_ w: WKWebView, renderingProgressDidChange events: UInt) { "
                                        + "if paneCover.rendered(events) { cover.isHidden = true } }"))
        XCTAssertTrue(code.contains("guard let navigation else { return } if paneCover.finished("
                                        + "ObjectIdentifier(navigation), painting: painting) { cover.isHidden = true } "
                                        + "let finished = document.didFinish(ObjectIdentifier(navigation))"))
        XCTAssertTrue(code.contains(
            "let painting = webView.responds(to: NSSelectorFromString(PaneCover.setter)) "
                + "if painting { webView.setValue(NSNumber(value: PaneCover.painted), forKey: PaneCover.key) } "
                + "self.painting = painting super.init(nibName: nil, bundle: nil)"))
        // Where the cover is never put up: a letter opened by its line, a
        // body, his letters, arrivals, a page drawn again.
        for name in ["private func loadBody(", "private func fill(", "func takeArrivals(",
                     "private func takeRelated(", "private func drawAgain()", "private func focusRow("] {
            let start = try XCTUnwrap(code.range(of: name), name)
            let rest = code[start.upperBound...]
            let end = rest.range(of: " func ")?.lowerBound ?? rest.endIndex
            XCTAssertFalse(rest[..<end].contains("coverPane"), name)
        }
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
        return text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }
}
