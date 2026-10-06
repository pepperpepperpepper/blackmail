import XCTest
@testable import Blackmail

/// The panes as they move (B-066, B-077): where each picture of a pane
/// starts and ends, that the pictures meet with no seam at every instant,
/// that only the real screen meant to be seen shows through them, that
/// they move as Mail's columns and its navigation do, and on what clock.
/// The container that moves them is UIKit and never runs on this host;
/// `PaneArrangementTests` reads its source.
final class PaneMoveTests: XCTestCase {

    private let widths: [CGFloat] = [1024, 1080, 1112, 1133, 1180, 1194, 1210, 1366, 1376]
    private let d = Theme.paneDividerWidth
    /// Each point of the motion the rules are checked at, 0 to 1.
    private let instants: [CGFloat] = stride(from: 0, through: 20, by: 1).map { CGFloat($0) / 20 }

    private static let three = PaneArrangement(launching: .three)
    private static let listInFront = PaneArrangement(launching: .two)
    private static var foldersInFront: PaneArrangement {
        var panes = PaneArrangement(launching: .two)
        panes.back()
        return panes
    }
    private static func switched(_ panes: PaneArrangement) -> PaneArrangement {
        var after = panes
        after.switchPanes()
        return after
    }

    /// The three switches the view button can make, from where it is made.
    private var switches: [(from: PaneArrangement, to: PaneArrangement, kind: PaneMove.Kind)] {
        [(Self.three, Self.switched(Self.three), .listOverFolders),
         (Self.listInFront, Self.switched(Self.listInFront), .listOffFolders),
         (Self.foldersInFront, Self.switched(Self.foldersInFront), .middleOpens)]
    }

    /// A folder tapped in two panes, and "< Mailboxes".
    private var stack: [(from: PaneArrangement, to: PaneArrangement, kind: PaneMove.Kind)] {
        [(Self.foldersInFront, Self.listInFront, .listSlidesIn),
         (Self.listInFront, Self.foldersInFront, .listSlidesOff)]
    }

    private func move(_ from: PaneArrangement, _ to: PaneArrangement, _ w: CGFloat,
                      reading: PaneMove.Reading = .words, crossFading: Bool = false,
                      file: StaticString = #filePath, line: UInt = #line) throws -> PaneMove {
        try XCTUnwrap(PaneMove.switching(from: from, to: to, screenWidth: w, reading: reading,
                                         crossFading: crossFading),
                      "\(w)", file: file, line: line)
    }

    /// Where a pane is in an arrangement, worked out from the columns alone
    /// and not from the move: x and width, or nil when it is not on screen.
    private func span(of pane: PaneMove.Pane, in panes: PaneArrangement,
                      _ w: CGFloat) -> (x: CGFloat, width: CGFloat)? {
        let columns = PaneArrangement.columns(panes.panes, screenWidth: w)
        switch pane {
        case .mailboxes:
            return panes.mailboxesOnScreen ? (0, columns.mailboxes) : nil
        case .list:
            guard panes.listOnScreen else { return nil }
            return (panes.listAtScreenEdge ? 0 : columns.mailboxes + d, columns.list)
        case .message:
            return (w - columns.message, columns.message)
        }
    }

    private func picture(_ pane: PaneMove.Pane, of move: PaneMove,
                         file: StaticString = #filePath, line: UInt = #line) throws -> PaneMove.Strip {
        try XCTUnwrap(move.strips.first { $0.pane == pane }, "\(pane)", file: file, line: line)
    }

    // MARK: - Which changes move

    /// The view button's three switches move as Mail's split view does,
    /// and a folder tapped in two panes and "< Mailboxes" as its
    /// navigation does (B-077). Nothing moves when nothing changes, nor
    /// for a change the buttons cannot make.
    func testWhatMoves() {
        for w in widths {
            for reading in [PaneMove.Reading.words, .nothing] {
                for crossFading in [false, true] {
                    func switching(_ from: PaneArrangement, _ to: PaneArrangement) -> PaneMove? {
                        PaneMove.switching(from: from, to: to, screenWidth: w, reading: reading,
                                           crossFading: crossFading)
                    }
                    for panes in [Self.three, Self.listInFront, Self.foldersInFront] {
                        XCTAssertNil(switching(panes, panes), "\(w)")
                    }
                    // A switch the button cannot make: from three it lands on the list.
                    XCTAssertNil(switching(Self.three, Self.foldersInFront))
                    for (from, to, kind) in switches + stack {
                        XCTAssertEqual(switching(from, to)?.kind, kind, "\(w)")
                    }
                }
            }
        }
        XCTAssertEqual(Self.switched(Self.three), Self.listInFront)
        for (_, _, kind) in switches { XCTAssertTrue(kind.isViewButtons) }
        for (_, _, kind) in stack { XCTAssertFalse(kind.isViewButtons) }
    }

    // MARK: - The moves, written out

    /// Three to two on the 11-inch and the 13-inch: the folders, as they
    /// were, going half the list's travel left and darkening; the list, as
    /// laid out in two, from where its right edge meets the letter to the
    /// screen's edge, a shadow coming on its leading edge; the letter's
    /// edge from 581 to 375.5; each divider riding its edge; the backdrop
    /// under it all.
    func testThreeToTwoWrittenOut() throws {
        XCTAssertEqual(try move(Self.three, Self.listInFront, 1194), PaneMove(
            kind: .listOverFolders, motion: .spring, screenWidth: 1194,
            strips: [
                .init(pane: .mailboxes, taken: .before, x: 0, width: 250, toX: -102.75,
                      toShownWidth: 250, patchesViewButton: true, underBar: false,
                      dim: 0, toDim: 0.1, shadow: 0, toShadow: 0),
                .init(pane: .list, taken: .after, x: 205.5, width: 375, toX: 0, toShownWidth: 375,
                      patchesViewButton: true, underBar: false,
                      dim: 0, toDim: 0, shadow: 0, toShadow: 1),
                .init(pane: .message, taken: .before, x: 581, width: 613, toX: 375.5,
                      toShownWidth: 613, patchesViewButton: false, underBar: false,
                      dim: 0, toDim: 0, shadow: 0, toShadow: 0),
            ],
            lines: [.init(x: 205, toX: -0.5), .init(x: 580.5, toX: 375)],
            backdrop: 0...1194, column: nil, bars: nil, actionsPlateX: 581, placeholder: nil,
            looked: [.mailboxes, .list, .message]))
        XCTAssertEqual(try move(Self.three, Self.listInFront, 1366), PaneMove(
            kind: .listOverFolders, motion: .spring, screenWidth: 1366,
            strips: [
                .init(pane: .mailboxes, taken: .before, x: 0, width: 285, toX: -143.75,
                      toShownWidth: 285, patchesViewButton: true, underBar: false,
                      dim: 0, toDim: 0.1, shadow: 0, toShadow: 0),
                .init(pane: .list, taken: .after, x: 287.5, width: 375, toX: 0, toShownWidth: 375,
                      patchesViewButton: true, underBar: false,
                      dim: 0, toDim: 0, shadow: 0, toShadow: 1),
                .init(pane: .message, taken: .before, x: 663, width: 703, toX: 375.5,
                      toShownWidth: 703, patchesViewButton: false, underBar: false,
                      dim: 0, toDim: 0, shadow: 0, toShadow: 0),
            ],
            lines: [.init(x: 287, toX: -0.5), .init(x: 662.5, toX: 375)],
            backdrop: 0...1366, column: nil, bars: nil, actionsPlateX: 663, placeholder: nil,
            looked: [.mailboxes, .list, .message]))
    }

    /// Two with the list in front, to three: the exact reverse. The list,
    /// as laid out in three, slides right off the folders, its shadow
    /// going; the folders, as laid out in three, come back from half the
    /// list's travel to the left, lightening; the letter's edge goes out
    /// to 581. Nothing of the real screen shows.
    func testListInFrontToThreeWrittenOut() throws {
        let at1194 = try move(Self.listInFront, Self.three, 1194)
        XCTAssertEqual(at1194, PaneMove(
            kind: .listOffFolders, motion: .spring, screenWidth: 1194,
            strips: [
                .init(pane: .mailboxes, taken: .after, x: -102.75, width: 250, toX: 0,
                      toShownWidth: 250, patchesViewButton: true, underBar: false,
                      dim: 0.1, toDim: 0, shadow: 0, toShadow: 0),
                .init(pane: .list, taken: .after, x: 45, width: 330, toX: 250.5, toShownWidth: 330,
                      patchesViewButton: false, underBar: false,
                      dim: 0, toDim: 0, shadow: 1, toShadow: 0),
                .init(pane: .message, taken: .before, x: 375.5, width: 818.5, toX: 581,
                      toShownWidth: 818.5, patchesViewButton: false, underBar: false,
                      dim: 0, toDim: 0, shadow: 0, toShadow: 0),
            ],
            lines: [.init(x: 44.5, toX: 250), .init(x: 375, toX: 580.5)],
            backdrop: nil, column: nil, bars: nil, actionsPlateX: 581, placeholder: nil,
            looked: [.mailboxes, .list, .message]))
        XCTAssertNil(at1194.revealed)
        let at1366 = try move(Self.listInFront, Self.three, 1366)
        XCTAssertEqual(at1366, PaneMove(
            kind: .listOffFolders, motion: .spring, screenWidth: 1366,
            strips: [
                .init(pane: .mailboxes, taken: .after, x: -143.75, width: 285, toX: 0,
                      toShownWidth: 285, patchesViewButton: true, underBar: false,
                      dim: 0.1, toDim: 0, shadow: 0, toShadow: 0),
                .init(pane: .list, taken: .after, x: -2, width: 377, toX: 285.5, toShownWidth: 377,
                      patchesViewButton: false, underBar: false,
                      dim: 0, toDim: 0, shadow: 1, toShadow: 0),
                .init(pane: .message, taken: .before, x: 375.5, width: 990.5, toX: 663,
                      toShownWidth: 990.5, patchesViewButton: false, underBar: false,
                      dim: 0, toDim: 0, shadow: 0, toShadow: 0),
            ],
            lines: [.init(x: -2.5, toX: 285), .init(x: 375, toX: 662.5)],
            backdrop: nil, column: nil, bars: nil, actionsPlateX: 663, placeholder: nil,
            looked: [.mailboxes, .list, .message]))
    }

    /// Two with the folders in front, to three, which Mail has no switch
    /// for: the folders' column draws in from 375 to its three-pane width,
    /// as it was, the letter's edge goes out, and the list is let through
    /// between the two lines, which start on the same point and part.
    func testFoldersInFrontToThreeWrittenOut() throws {
        let at1194 = try move(Self.foldersInFront, Self.three, 1194)
        XCTAssertEqual(at1194, PaneMove(
            kind: .middleOpens, motion: .spring, screenWidth: 1194,
            strips: [
                .init(pane: .mailboxes, taken: .before, x: 0, width: 375, toX: 0, toShownWidth: 250,
                      patchesViewButton: true, underBar: false,
                      dim: 0, toDim: 0, shadow: 0, toShadow: 0),
                .init(pane: .message, taken: .before, x: 375.5, width: 818.5, toX: 581,
                      toShownWidth: 818.5, patchesViewButton: false, underBar: false,
                      dim: 0, toDim: 0, shadow: 0, toShadow: 0),
            ],
            lines: [.init(x: 375, toX: 250), .init(x: 375, toX: 580.5)],
            backdrop: nil, column: nil, bars: nil, actionsPlateX: 581, placeholder: nil,
            looked: [.mailboxes, .message]))
        XCTAssertEqual(at1194.revealed, 250.5...580.5)
        let at1366 = try move(Self.foldersInFront, Self.three, 1366)
        XCTAssertEqual(at1366.strips.map(\.toShownWidth), [285, 990.5])
        XCTAssertEqual(at1366.lines, [.init(x: 375, toX: 285), .init(x: 375, toX: 662.5)])
        XCTAssertEqual(at1366.revealed, 285.5...662.5)
    }

    /// A folder tapped in two panes and "< Mailboxes" on the 11-inch: the
    /// list, as laid out, slides in from the column's right edge over the
    /// folders, as they were, which go 30% of the column left and darken;
    /// and back, the folders as laid out coming from 30% left. Only the
    /// content under the bars moves: the bar going slides half the column
    /// toward where the list goes and fades, the bar coming from as far
    /// the other way. Cut off at the column; the letter and the divider
    /// beside it are the real screen.
    func testAFolderTapAndMailboxesWrittenOut() throws {
        let tapped = try move(Self.foldersInFront, Self.listInFront, 1194)
        XCTAssertEqual(tapped, PaneMove(
            kind: .listSlidesIn, motion: .spring, screenWidth: 1194,
            strips: [
                .init(pane: .mailboxes, taken: .before, x: 0, width: 375, toX: -112.5,
                      toShownWidth: 375, patchesViewButton: false, underBar: true,
                      dim: 0, toDim: 0.1, shadow: 0, toShadow: 0),
                .init(pane: .list, taken: .after, x: 375, width: 375, toX: 0, toShownWidth: 375,
                      patchesViewButton: false, underBar: true,
                      dim: 0, toDim: 0, shadow: 1, toShadow: 1),
            ],
            lines: [], backdrop: 0...375, column: 375,
            bars: .init(going: .mailboxes, coming: .list, travel: -187.5),
            actionsPlateX: nil, placeholder: nil, looked: [.mailboxes, .list]))
        XCTAssertEqual(tapped.revealed, 375...1194)

        let back = try move(Self.listInFront, Self.foldersInFront, 1194)
        XCTAssertEqual(back, PaneMove(
            kind: .listSlidesOff, motion: .spring, screenWidth: 1194,
            strips: [
                .init(pane: .mailboxes, taken: .after, x: -112.5, width: 375, toX: 0,
                      toShownWidth: 375, patchesViewButton: false, underBar: true,
                      dim: 0.1, toDim: 0, shadow: 0, toShadow: 0),
                .init(pane: .list, taken: .before, x: 0, width: 375, toX: 375, toShownWidth: 375,
                      patchesViewButton: false, underBar: true,
                      dim: 0, toDim: 0, shadow: 1, toShadow: 0),
            ],
            lines: [], backdrop: 0...375, column: 375,
            bars: .init(going: .list, coming: .mailboxes, travel: 187.5),
            actionsPlateX: nil, placeholder: nil, looked: [.mailboxes, .list]))
        XCTAssertEqual(back.revealed, 375...1194)

        // The same at every width: the column is 375 wide on every iPad.
        for w in widths {
            for (from, to, _) in stack {
                let move = try move(from, to, w)
                XCTAssertEqual(PaneMove(kind: move.kind, motion: move.motion, screenWidth: 1194,
                                        strips: move.strips, lines: move.lines,
                                        backdrop: move.backdrop, column: move.column,
                                        bars: move.bars, actionsPlateX: move.actionsPlateX,
                                        placeholder: move.placeholder, looked: move.looked),
                               try self.move(from, to, 1194), "\(w)")
                XCTAssertEqual(move.revealed, 375...w)
            }
        }
    }

    /// With Prefer Cross-Fade Transitions, a folder tap and "< Mailboxes"
    /// do not slide: the column as it was, its content and its bar, fades
    /// where it is over the column as it is, and nothing else is pictured.
    func testWithCrossFadesTheColumnFadesWhereItIs() throws {
        for w in widths {
            for (from, to, kind) in stack {
                let move = try move(from, to, w, crossFading: true)
                let going: PaneMove.Pane = kind == .listSlidesIn ? .mailboxes : .list
                XCTAssertEqual(move, PaneMove(
                    kind: kind, motion: .crossFade, screenWidth: w,
                    strips: [.init(pane: going, taken: .before, x: 0, width: 375, toX: 0,
                                   toShownWidth: 375, patchesViewButton: false, underBar: true,
                                   dim: 0, toDim: 0, shadow: 0, toShadow: 0)],
                    lines: [], backdrop: nil, column: 375,
                    bars: .init(going: going, coming: nil, travel: 0),
                    actionsPlateX: nil, placeholder: nil, looked: [going]), "\(kind) \(w)")
                XCTAssertEqual(move.uncovered(at: 0.5), [375...w])
            }
        }
    }

    // MARK: - As Mail's move

    /// The view button's switch, as the split view's: the list keeps its
    /// width all the way, and its right edge rides the letter's left
    /// edge, a divider between them, at every instant, so the two go
    /// together. From three to two it is the width the list ends at, and
    /// it starts with its right edge on the letter's; from two to three
    /// the reverse.
    func testTheListKeepsItsWidthAndTheLetterGoesWithIt() throws {
        for w in widths {
            for (from, to, kind) in switches where kind != .middleOpens {
                let move = try move(from, to, w)
                let list = try picture(.list, of: move)
                let letter = try picture(.message, of: move)
                let now = try XCTUnwrap(span(of: .list, in: to, w))
                XCTAssertEqual(list.width, now.width, "\(kind) \(w)")
                XCTAssertEqual(list.toShownWidth, list.width, "\(kind) \(w)")
                for p in instants {
                    XCTAssertEqual(list.left(at: p) + list.width + d, letter.left(at: p),
                                   accuracy: 1e-9, "\(kind) at \(w), \(p)")
                }
                XCTAssertEqual(list.toX - list.x, letter.toX - letter.x, accuracy: 1e-9)
            }
        }
    }

    /// The folders go at half the list's speed under it, the same way, as
    /// the split view's sidebar does; under a list pushed over them, 30%
    /// of the column, as the navigation's screen pushed over does. The
    /// list slides the whole column there.
    func testTheFoldersGoAtTheirShareOfTheListsSpeed() throws {
        for w in widths {
            for (from, to, kind) in switches where kind != .middleOpens {
                let move = try move(from, to, w)
                let list = try picture(.list, of: move), folders = try picture(.mailboxes, of: move)
                XCTAssertEqual(folders.toX - folders.x, (list.toX - list.x) / 2, accuracy: 1e-9,
                               "\(kind) \(w)")
                XCTAssertEqual(folders.width, folders.toShownWidth)
            }
            for (from, to, kind) in stack {
                let move = try move(from, to, w)
                let list = try picture(.list, of: move), folders = try picture(.mailboxes, of: move)
                XCTAssertEqual(abs(folders.toX - folders.x), 375 * 0.3, accuracy: 1e-9, "\(kind)")
                XCTAssertEqual(abs(list.toX - list.x), 375, "\(kind)")
                XCTAssertEqual((folders.toX - folders.x).sign, (list.toX - list.x).sign)
                // The folders are at the column's edge when in front, and
                // the list over them is at it, or off it, at the other end.
                XCTAssertEqual(kind == .listSlidesIn ? folders.x : folders.toX, 0)
                XCTAssertEqual(kind == .listSlidesIn ? list.toX : list.x, 0)
            }
        }
        XCTAssertEqual(Theme.paneSidebarParallax, 0.5)
        XCTAssertEqual(Theme.paneStackParallax, 0.3)
    }

    /// What goes under is darkened, by black at a tenth, as UIKit darkens
    /// the sidebar and the screen pushed over, and lightens as it comes
    /// out; what goes over carries a shadow on its leading edge, coming on
    /// as the list goes over the folders and going as it comes off them,
    /// and held while a pushed list comes in. Nothing else is darkened or
    /// shadowed, and nothing as the middle opens.
    func testWhatIsDarkenedAndWhatCastsAShadow() throws {
        for w in widths {
            for (from, to, kind) in switches + stack {
                let move = try move(from, to, w)
                for strip in move.strips {
                    let context = "\(kind) \(strip.pane) at \(w)"
                    let covered: Bool
                    switch kind {
                    case .listOverFolders, .listSlidesIn: covered = true
                    case .listOffFolders, .listSlidesOff, .middleOpens: covered = false
                    }
                    switch (strip.pane, kind) {
                    case (.mailboxes, .middleOpens), (.message, _):
                        XCTAssertEqual([strip.dim, strip.toDim, strip.shadow, strip.toShadow],
                                       [0, 0, 0, 0], context)
                    case (.mailboxes, _):
                        XCTAssertEqual([strip.dim, strip.toDim], covered ? [0, 0.1] : [0.1, 0], context)
                        XCTAssertEqual([strip.shadow, strip.toShadow], [0, 0], context)
                    case (.list, .listSlidesIn):
                        XCTAssertEqual([strip.shadow, strip.toShadow], [1, 1], context)
                    case (.list, _):
                        XCTAssertEqual([strip.shadow, strip.toShadow], covered ? [0, 1] : [1, 0],
                                       context)
                        XCTAssertEqual([strip.dim, strip.toDim], [0, 0], context)
                    }
                    // The darkening and the shadow go on the same clock as the
                    // pictures, in a straight line from start to end.
                    XCTAssertEqual(strip.dim(at: 0.5), (strip.dim + strip.toDim) / 2, context)
                    XCTAssertEqual(strip.shadow(at: 0.5), (strip.shadow + strip.toShadow) / 2, context)
                }
            }
        }
        XCTAssertEqual(Theme.paneCoveredDim, 0.1)
        // The shadow: a band of 8 pt, black at 4% against the edge, as
        // faint as UIKit's.
        XCTAssertEqual(Theme.paneEdgeShadowWidth, 8)
        XCTAssertEqual(Theme.paneEdgeShadowOpacity, 0.04)
    }

    /// What is pictured as it was and what as laid out anew. What arrives
    /// or stays is laid out anew, as UIKit lays its columns out before it
    /// moves them; what goes or is cut off, and the letter, which WebKit
    /// wraps again in its own time, as it was. So every picture as laid
    /// out ends where its pane is now and as wide, and every picture as it
    /// was starts where its pane was and as wide.
    func testWhatIsPicturedAsItWasAndWhatAsLaidOut() throws {
        for w in widths {
            for (from, to, kind) in switches + stack {
                let move = try move(from, to, w)
                for strip in move.strips {
                    let context = "\(kind) \(strip.pane) at \(w)"
                    if strip.pane == .message {
                        XCTAssertEqual(strip.taken, .before, context)
                    }
                    let laidOut = (kind == .listOverFolders && strip.pane == .list)
                        || kind == .listOffFolders && strip.pane != .message
                        || kind == .listSlidesIn && strip.pane == .list
                        || kind == .listSlidesOff && strip.pane == .mailboxes
                    XCTAssertEqual(strip.taken, laidOut ? .after : .before, context)
                    switch strip.taken {
                    case .before:
                        let was = try XCTUnwrap(span(of: strip.pane, in: from, w), context)
                        XCTAssertEqual(strip.x, was.x, context)
                        XCTAssertEqual(strip.width, was.width, context)
                    case .after:
                        let now = try XCTUnwrap(span(of: strip.pane, in: to, w), context)
                        XCTAssertEqual(strip.toX, now.x, context)
                        XCTAssertEqual(strip.toShownWidth, now.width, context)
                        XCTAssertEqual(strip.width, now.width, context)
                    }
                }
                if let bars = move.bars {
                    XCTAssertEqual(span(of: bars.going, in: from, w)?.x, 0)
                    if let coming = bars.coming { XCTAssertEqual(span(of: coming, in: to, w)?.x, 0) }
                }
            }
        }
    }

    /// At the end every picture but the letter's is the screen beneath, or
    /// wholly under one that is, or past the column's edge where it is cut
    /// off: so the pictures go with nothing changing
    /// but the letter's line ends, and, as the middle opens, the folders'
    /// column, cut off as it was. At the start every picture as it was is
    /// the screen as it was.
    func testTheLastFrameIsTheScreenBeneath() throws {
        for w in widths {
            for (from, to, kind) in switches + stack {
                let move = try move(from, to, w)
                for (i, strip) in move.strips.enumerated() {
                    let context = "\(kind) \(strip.pane) at \(w)"
                    if let now = span(of: strip.pane, in: to, w) {
                        XCTAssertEqual(strip.left(at: 1), now.x, context)
                        if strip.taken == .after || strip.pane == .message {
                            XCTAssertEqual(strip.toShownWidth, strip.pane == .message
                                           ? strip.width : now.width, context)
                        }
                    } else if strip.left(at: 1) >= (move.column ?? w) {
                        // Gone: past the column's edge, where it is cut off.
                        continue
                    } else {
                        // Gone: under a picture above it that is the screen.
                        let above = move.strips[(i + 1)...].filter { $0.taken == .after }
                        XCTAssertTrue(above.contains {
                            $0.left(at: 1) <= max(strip.left(at: 1), 0)
                                && $0.left(at: 1) + $0.shownWidth(at: 1)
                                    >= strip.left(at: 1) + strip.shownWidth(at: 1)
                        }, context)
                    }
                }
            }
        }
    }

    // MARK: - The pieces meet

    /// At every instant each line is glued to the edge it stands for: the
    /// Mailboxes' divider to the list's left edge, or, as the folders'
    /// column draws in, to where it is cut off; the list's divider to the
    /// letter's left edge. And the letter is always the picture on top.
    func testTheLinesRideTheirEdges() throws {
        for w in widths {
            for (from, to, kind) in switches {
                let move = try move(from, to, w)
                let letter = try picture(.message, of: move)
                XCTAssertEqual(move.strips.last, letter, "\(kind) \(w)")
                for p in instants {
                    let context = "\(kind) at \(w), \(p)"
                    let line1 = move.lines[0].left(at: p), line2 = move.lines[1].left(at: p)
                    XCTAssertEqual(line2 + d, letter.left(at: p), accuracy: 1e-9, context)
                    if kind == .middleOpens {
                        let folders = try picture(.mailboxes, of: move)
                        XCTAssertEqual(line1, folders.left(at: p) + folders.shownWidth(at: p),
                                       accuracy: 1e-9, context)
                    } else {
                        XCTAssertEqual(line1 + d, try picture(.list, of: move).left(at: p),
                                       accuracy: 1e-9, context)
                    }
                }
                // Each line ends where its divider is, or off the screen's left
                // edge with the list's when two panes have none.
                let mailboxes3 = PaneArrangement.columns(.three, screenWidth: w).mailboxes
                XCTAssertEqual(move.lines[0].toX, to.mailboxDividerOnScreen ? mailboxes3 : -d)
            }
            // In the stack the column's divider does not move, and is the
            // real one.
            for (from, to, _) in stack { XCTAssertEqual(try move(from, to, w).lines, []) }
        }
    }

    /// Whole columns, moved sideways only. No picture changes its width:
    /// the folders' column in the middle opening is cut off, never
    /// squeezed. In each change every picture goes the same way, or stays.
    /// And there is nothing in the model to move anything up or down with.
    func testRigidAndSideways() throws {
        for w in widths {
            for (from, to, kind) in switches + stack {
                let move = try move(from, to, w)
                for strip in move.strips {
                    if kind == .middleOpens, strip.pane == .mailboxes {
                        XCTAssertLessThan(strip.toShownWidth, strip.width)
                    } else {
                        XCTAssertEqual(strip.toShownWidth, strip.width, "\(kind) \(w)")
                    }
                    for p in instants {
                        XCTAssertLessThanOrEqual(strip.shownWidth(at: p), strip.width)
                    }
                }
                let moving = move.strips.filter { $0.toX != $0.x }
                let ways = Set(moving.map { ($0.toX - $0.x).sign })
                XCTAssertEqual(ways.count, 1, "\(kind) \(w)")
                let left = kind == .listOverFolders || kind == .listSlidesIn
                XCTAssertEqual(ways.first, left ? .minus : .plus, "\(kind) \(w)")
            }
        }
        let stripMembers = Mirror(reflecting: PaneMove.Strip(
            pane: .list, taken: .before, x: 0, width: 1, toX: 0, toShownWidth: 1,
            patchesViewButton: false, underBar: false, dim: 0, toDim: 0, shadow: 0, toShadow: 0))
            .children.compactMap(\.label)
        XCTAssertEqual(stripMembers, ["pane", "taken", "x", "width", "toX", "toShownWidth",
                                      "patchesViewButton", "underBar", "dim", "toDim",
                                      "shadow", "toShadow"])
        XCTAssertEqual(Mirror(reflecting: PaneMove.Line(x: 0, toX: 1)).children.compactMap(\.label),
                       ["x", "toX"])
    }

    // MARK: - What shows through

    /// At every instant every point across the screen is under a picture,
    /// a line or the backdrop, or in the stretch of the real screen meant
    /// to show: none for the view button but the list between the folders
    /// and the letter as the middle opens, and beside the column in the
    /// stack. By the end exactly that stretch shows. Checked point by point
    /// every half point, and by the model's own reckoning.
    func testOnlyWhatIsMeantShowsThrough() throws {
        for w in widths {
            for (from, to, kind) in switches + stack {
                let move = try move(from, to, w)
                let edge = move.column ?? w
                for p in instants {
                    let context = "\(kind) at \(w), \(p)"
                    for x in stride(from: CGFloat(0.25), to: w, by: 0.5) {
                        let pictured = x <= edge && move.strips.contains {
                            $0.left(at: p) <= x && x <= $0.left(at: p) + $0.shownWidth(at: p)
                        }
                        let lined = move.lines.contains { $0.left(at: p) <= x && x <= $0.left(at: p) + d }
                        let backed = move.backdrop?.contains(x) ?? false
                        let meant = move.revealed?.contains(x) ?? false
                        if !(pictured || lined || backed || meant) {
                            XCTFail("\(x) uncovered, \(context)")
                            break
                        }
                    }
                    let uncovered = move.uncovered(at: p)
                    if let revealed = move.revealed {
                        for gap in uncovered {
                            XCTAssertGreaterThanOrEqual(gap.lowerBound, revealed.lowerBound, context)
                            XCTAssertLessThanOrEqual(gap.upperBound, revealed.upperBound, context)
                        }
                    } else {
                        XCTAssertEqual(uncovered, [], context)
                    }
                }
                if let revealed = move.revealed {
                    XCTAssertEqual(move.uncovered(at: 1), [revealed], "\(kind) \(w)")
                }
                if kind.isViewButtons { XCTAssertEqual(move.uncovered(at: 0), [], "\(kind) \(w)") }
            }
        }
    }

    /// From three to two the letter's picture, as it was, is narrower than
    /// the pane it ends in by the edge's travel, and the backdrop is under
    /// that stretch at the right until the pictures go; the other way it
    /// goes off the screen's right edge, and nothing is needed.
    func testTheLettersPictureAndTheBackdrop() throws {
        for w in widths {
            let three = PaneArrangement.columns(.three, screenWidth: w)
            let travel = (three.mailboxes + three.list + 2 * d) - (Theme.twoPaneLeftColumnWidth + d)
            let over = try move(Self.three, Self.listInFront, w)
            let letter = try picture(.message, of: over)
            XCTAssertEqual(w - (letter.left(at: 1) + letter.width), travel, accuracy: 1e-9)
            XCTAssertEqual(over.backdrop, 0...w)
            let off = try move(Self.listInFront, Self.three, w)
            let wider = try picture(.message, of: off)
            XCTAssertGreaterThanOrEqual(wider.left(at: 1) + wider.width, w)
            XCTAssertNil(off.backdrop)
        }
    }

    // MARK: - The still plates

    /// The letter's actions are pictured once, from the letter's left edge
    /// in three panes to the screen's right, and never move. Wide enough at
    /// every width for the actions of the letter's own picture to stay
    /// under it as that picture slides, and no divider ever comes into it.
    /// The letter is not pictured in the stack, and has no plate there.
    func testTheActionsPlateHoldsStill() throws {
        for w in widths {
            let columns = PaneArrangement.columns(.three, screenWidth: w)
            let letterInThree = columns.mailboxes + columns.list + 2 * d
            let letterInTwo = Theme.twoPaneLeftColumnWidth + d
            for (from, to, kind) in switches {
                let move = try move(from, to, w)
                XCTAssertEqual(move.actionsPlateX, letterInThree, "\(kind) \(w)")
                XCTAssertGreaterThanOrEqual((w - letterInThree) - (letterInThree - letterInTwo), 300,
                                            "\(w)")
                for p in instants {
                    XCTAssertLessThanOrEqual(move.lines[1].left(at: p) + d,
                                             try XCTUnwrap(move.actionsPlateX) + 1e-9,
                                             "\(kind) at \(w), \(p)")
                }
            }
            for (from, to, kind) in stack {
                let move = try move(from, to, w)
                XCTAssertNil(move.actionsPlateX, "\(kind)")
                XCTAssertFalse(move.strips.contains { $0.pane == .message }, "\(kind)")
            }
        }
    }

    /// The view button's glyph stays in the corner: every picture with one
    /// in its bar has it painted over, the folders' in the view button's
    /// switches and the list's from three to two; in the stack the bars
    /// go on their own, and the pictures are of the content beneath them.
    func testTheViewButtonsInThePicturesArePaintedOver() throws {
        for w in widths {
            for (from, to, kind) in switches + stack {
                let move = try move(from, to, w)
                let painted = move.strips.filter(\.patchesViewButton).map(\.pane)
                switch kind {
                case .listOverFolders: XCTAssertEqual(painted, [.mailboxes, .list])
                case .listOffFolders, .middleOpens: XCTAssertEqual(painted, [.mailboxes])
                case .listSlidesIn, .listSlidesOff:
                    XCTAssertEqual(painted, [])
                    XCTAssertTrue(move.strips.allSatisfy(\.underBar))
                }
                if kind.isViewButtons { XCTAssertFalse(move.strips.contains(where: \.underBar)) }
            }
        }
    }

    // MARK: - The letter, and what is fastened elsewhere in it

    /// The letter's picture goes the whole of its left edge's travel, in
    /// one piece, whatever the pane holds: its words are fastened to that
    /// edge, and land where they now are. With a letter, a conversation or
    /// a notice in the pane nothing is cut out of it; an empty pane is the
    /// same move in every other part, with only its words carried apart.
    func testTheLetterGoesWithItsLeftEdge() throws {
        for w in widths {
            for (from, to, kind) in switches {
                let words = try move(from, to, w, reading: .words)
                let empty = try move(from, to, w, reading: .nothing)
                let context = "\(kind) at \(w)"
                let letter = try picture(.message, of: words)
                let was = try XCTUnwrap(span(of: .message, in: from, w))
                let now = try XCTUnwrap(span(of: .message, in: to, w))
                XCTAssertEqual(letter.toX - letter.x, now.x - was.x, context)
                XCTAssertEqual(letter.toShownWidth, letter.width, context)
                XCTAssertNil(words.placeholder, context)

                XCTAssertNotNil(empty.placeholder, context)
                XCTAssertEqual(PaneMove(kind: empty.kind, motion: empty.motion,
                                        screenWidth: empty.screenWidth,
                                        strips: empty.strips, lines: empty.lines,
                                        backdrop: empty.backdrop, column: empty.column,
                                        bars: empty.bars, actionsPlateX: empty.actionsPlateX,
                                        placeholder: nil, looked: empty.looked),
                               words, context)
            }
            for (from, to, _) in stack {
                XCTAssertNil(try move(from, to, w, reading: .nothing).placeholder)
            }
        }
    }

    /// "No message selected" is centred in the letter's column, whose left
    /// edge moves and whose right edge is the screen's, so it goes half as
    /// far as the edge. Its picture starts in the middle of the column as
    /// it was and ends in the middle of the column as it is, worked out
    /// here from the columns alone, and is in the middle of the column at
    /// every instant between, as the words of a column moving in UIKit
    /// would be; so it is never beside the column, and lands on the words
    /// beneath.
    func testAnEmptyPanesWordsRideTheMiddleOfTheLetter() throws {
        for w in widths {
            for (from, to, kind) in switches {
                let move = try move(from, to, w, reading: .nothing)
                let context = "\(kind) at \(w)"
                let middle = try XCTUnwrap(move.placeholder, context)
                let was = try XCTUnwrap(span(of: .message, in: from, w))
                let now = try XCTUnwrap(span(of: .message, in: to, w))
                XCTAssertEqual(middle.at(0), was.x + was.width / 2, context)
                XCTAssertEqual(middle.at(1), now.x + now.width / 2, context)

                let letter = try picture(.message, of: move)
                XCTAssertEqual(middle.toX - middle.x, (letter.toX - letter.x) / 2, context)
                for p in instants {
                    let edge = letter.left(at: p)
                    XCTAssertEqual(middle.at(p), (edge + w) / 2, accuracy: 1e-9, "\(context), \(p)")
                    XCTAssertGreaterThanOrEqual(middle.at(p) - edge, 150, "\(context), \(p)")
                    XCTAssertGreaterThanOrEqual(w - middle.at(p), 150, "\(context), \(p)")
                }
            }
        }
        let at1194 = try move(Self.three, Self.listInFront, 1194, reading: .nothing)
        XCTAssertEqual(at1194.placeholder, PaneMove.Middle(x: 887.5, toX: 784.75))
        let at1366 = try move(Self.listInFront, Self.three, 1366, reading: .nothing)
        XCTAssertEqual(at1366.placeholder, PaneMove.Middle(x: 870.75, toX: 1014.5))
    }

    // MARK: - Looked at for a bounce

    /// The panes looked at for a bounce before anything is touched: every
    /// one pictured, on the screen at the tap or hidden. A change made at
    /// once because a pane was bouncing hides it while it still springs
    /// back, and the next change can come within the half second: the
    /// folders coming back from behind the list, and a list coming in
    /// front, are pictured as laid out then, and would jump as the
    /// pictures go.
    func testEveryPanePicturedIsLookedAtForABounce() throws {
        for w in widths {
            XCTAssertEqual(try move(Self.three, Self.listInFront, w).looked,
                           [.mailboxes, .list, .message])
            XCTAssertEqual(try move(Self.listInFront, Self.three, w).looked,
                           [.mailboxes, .list, .message])
            XCTAssertEqual(try move(Self.foldersInFront, Self.three, w).looked,
                           [.mailboxes, .message])
            XCTAssertEqual(try move(Self.foldersInFront, Self.listInFront, w).looked,
                           [.mailboxes, .list])
            XCTAssertEqual(try move(Self.listInFront, Self.foldersInFront, w).looked,
                           [.mailboxes, .list])
            // With cross-fades only the column going is pictured.
            XCTAssertEqual(try move(Self.foldersInFront, Self.listInFront, w,
                                    crossFading: true).looked, [.mailboxes])
            XCTAssertEqual(try move(Self.listInFront, Self.foldersInFront, w,
                                    crossFading: true).looked, [.list])
            for reading in [PaneMove.Reading.words, .nothing] {
                for crossFading in [false, true] {
                    for (from, to, kind) in switches + stack {
                        let move = try move(from, to, w, reading: reading, crossFading: crossFading)
                        XCTAssertEqual(move.looked, move.strips.map(\.pane), "\(kind) \(w)")
                    }
                }
            }
        }
    }

    // MARK: - Holding still

    /// Where a list or a letter comes to rest, from its content, its size
    /// and its insets: from the top end, under the bar, to the bottom end,
    /// and the same sideways; the top end at the bottom too when the
    /// content is shorter than the view. Inside the ends it is coasting or
    /// still; past either by more than half a point it is bouncing, and the
    /// change is made at once. A bounce of less than that is taken as at
    /// its end, and brought there by no more than half a point.
    func testWhereAListOrALetterComesToRest() {
        func ends(_ rest: PaneMove.Rest) -> [CGFloat] { [rest.top, rest.bottom, rest.left, rest.right] }
        // The list: 2000 pt of rows in a 900 pt view under a 74 pt bar.
        let list = PaneMove.Rest(contentSize: CGSize(width: 330, height: 2000),
                                 viewSize: CGSize(width: 330, height: 900),
                                 insetTop: 74, insetLeft: 0, insetBottom: 0, insetRight: 0)
        XCTAssertEqual(ends(list), [-74, 1100, 0, 0])
        for y: CGFloat in [-74, 0, 500, 1100, -74.5, 1100.5] {
            XCTAssertTrue(list.holds(CGPoint(x: 0, y: y)), "\(y)")
        }
        for y: CGFloat in [-74.6, -104, -300, 1100.6, 1130] {
            XCTAssertFalse(list.holds(CGPoint(x: 0, y: y)), "\(y)")
        }
        for x: CGFloat in [-0.6, -12, 0.6, 12] {
            XCTAssertFalse(list.holds(CGPoint(x: x, y: 500)), "\(x)")
        }
        XCTAssertEqual(list.clamped(CGPoint(x: 0, y: 500)), CGPoint(x: 0, y: 500))
        XCTAssertEqual(list.clamped(CGPoint(x: 0.25, y: 1100.5)), CGPoint(x: 0, y: 1100))
        XCTAssertEqual(list.clamped(CGPoint(x: -0.5, y: -74.5)), CGPoint(x: 0, y: -74))

        // The Mailboxes: fewer folders than room, so the top end is the
        // bottom one, and any pull down or up is a bounce.
        let folders = PaneMove.Rest(contentSize: CGSize(width: 250, height: 400),
                                    viewSize: CGSize(width: 250, height: 900),
                                    insetTop: 74, insetLeft: 0, insetBottom: 20, insetRight: 0)
        XCTAssertEqual(ends(folders), [-74, -74, 0, 0])
        XCTAssertTrue(folders.holds(CGPoint(x: 0, y: -74)))
        XCTAssertFalse(folders.holds(CGPoint(x: 0, y: -60)))
        XCTAssertFalse(folders.holds(CGPoint(x: 0, y: -90)))

        // A letter wider than its pane, as a newsletter can be, with the
        // insets on all four sides that WebKit can give it.
        let letter = PaneMove.Rest(contentSize: CGSize(width: 700, height: 3000),
                                   viewSize: CGSize(width: 613, height: 800),
                                   insetTop: 10, insetLeft: 4, insetBottom: 30, insetRight: 6)
        XCTAssertEqual(ends(letter), [-10, 2230, -4, 93])
        XCTAssertTrue(letter.holds(CGPoint(x: 93, y: 2230)))
        XCTAssertTrue(letter.holds(CGPoint(x: -4, y: -10)))
        XCTAssertFalse(letter.holds(CGPoint(x: 100, y: 1000)))
        XCTAssertFalse(letter.holds(CGPoint(x: -20, y: 1000)))
        XCTAssertFalse(letter.holds(CGPoint(x: 0, y: 2260)))

        XCTAssertEqual(PaneMove.Rest.slack, 0.5)
    }

    // MARK: - Time

    /// UIKit's spring, as its split view and its navigation move their
    /// views on iPadOS 18.6: half a second, a mass of 3 and a stiffness of
    /// 1000, critically damped, so nothing goes past its end. The damping
    /// is the critical one, not UIKit's 500, which iPadOS 18 was measured
    /// running as critical and an older iPadOS may not.
    func testTheSpring() {
        XCTAssertEqual(Theme.paneMoveDuration, 0.5)
        XCTAssertEqual(Theme.paneSpringMass, 3)
        XCTAssertEqual(Theme.paneSpringStiffness, 1000)
        let damping = Theme.paneSpringDamping
        XCTAssertEqual(damping * damping, 4 * Theme.paneSpringMass * Theme.paneSpringStiffness,
                       accuracy: 1e-6)
        XCTAssertEqual(damping, 109.545, accuracy: 0.001)
        XCTAssertNotEqual(damping, 500)
    }

    /// How far along the spring the panes are, against the probe of
    /// 2026-10-06, which measured UIKit's columns at half the way by 0.09
    /// to 0.10 s, 90% by 0.21, 99% by 0.37 and done at 0.5 s; and against
    /// the curve itself, 1 - (1 + wt)e^(-wt) at w = √(1000 / 3). It never
    /// goes back and never goes past the end.
    func testTheCurve() {
        func when(_ q: CGFloat) -> TimeInterval {
            var t: TimeInterval = 0
            while PaneMove.progress(at: t) < q { t += 0.0005 }
            return t
        }
        XCTAssertEqual(when(0.5), 0.092, accuracy: 0.003)
        XCTAssertEqual(when(0.9), 0.213, accuracy: 0.003)
        XCTAssertEqual(when(0.99), 0.364, accuracy: 0.003)
        XCTAssertTrue((0.09...0.10).contains(when(0.5)))
        XCTAssertTrue((0.20...0.22).contains(when(0.9)))
        XCTAssertTrue((0.35...0.37).contains(when(0.99)))
        XCTAssertEqual(PaneMove.progress(at: 0), 0)
        XCTAssertEqual(PaneMove.progress(at: 0.4999), 0.9989, accuracy: 0.0002)
        XCTAssertEqual(PaneMove.progress(at: 0.5), 1)
        XCTAssertEqual(PaneMove.progress(at: 2), 1)
        let w = (1000.0 / 3.0).squareRoot()
        var last: CGFloat = 0
        for k in 1..<500 {
            let t = Double(k) / 1000
            let p = PaneMove.progress(at: t)
            XCTAssertEqual(Double(p), 1 - (1 + w * t) * exp(-w * t), accuracy: 1e-9)
            XCTAssertGreaterThan(p, last)
            XCTAssertLessThan(p, 1)
            last = p
        }
        // About a twentieth of the way in the first frame at 60 a second:
        // it starts at speed, with no ease in to speak of.
        XCTAssertGreaterThan(PaneMove.progress(at: 1.0 / 60), 0.03)
    }

    /// The bar's titles and buttons in the stack: 0.35 s on UIKit's bar
    /// curve, half the column's width each way; with Prefer Cross-Fade
    /// Transitions, the column fades for half a second on UIKit's ease in
    /// and out, its bar on the bar curve.
    func testTheBarsAndTheCrossFade() throws {
        XCTAssertEqual(Theme.paneBarDuration, 0.35)
        XCTAssertEqual(Theme.paneBarCurve, [0.25, 0.1, 0.25, 1])
        XCTAssertEqual(Theme.paneBarTravel, 0.5)
        XCTAssertEqual(Theme.paneCrossFadeCurve, [0.42, 0, 0.58, 1])
        XCTAssertLessThan(Theme.paneBarDuration, Theme.paneMoveDuration)
        XCTAssertEqual(try move(Self.foldersInFront, Self.listInFront, 1194).bars?.travel,
                       -375 * Theme.paneBarTravel)
        XCTAssertEqual(try move(Self.listInFront, Self.foldersInFront, 1194).bars?.travel,
                       375 * Theme.paneBarTravel)
    }

    /// Mail's rule for Reduce Motion and Prefer Cross-Fade Transitions, as
    /// UIKit has it on iPadOS 18.6: the split view's columns slide whatever
    /// is set, so the view button's switch always slides; the navigation's
    /// push and pop fade with Prefer Cross-Fade Transitions, which iOS
    /// gives only with Reduce Motion on as well, and slide with Reduce
    /// Motion alone. Reduce Motion is not even asked: the rule has no place
    /// for it.
    func testReduceMotionAndCrossFadesAsMailHasThem() throws {
        for (_, _, kind) in switches {
            XCTAssertEqual(PaneMove.motion(for: kind, crossFading: false), .spring)
            XCTAssertEqual(PaneMove.motion(for: kind, crossFading: true), .spring)
        }
        for (_, _, kind) in stack {
            XCTAssertEqual(PaneMove.motion(for: kind, crossFading: false), .spring)
            XCTAssertEqual(PaneMove.motion(for: kind, crossFading: true), .crossFade)
        }
        for w in widths {
            for (from, to, kind) in switches {
                XCTAssertEqual(try move(from, to, w, crossFading: true),
                               try move(from, to, w, crossFading: false), "\(kind)")
            }
            for (from, to, _) in stack {
                let fade = try move(from, to, w, crossFading: true)
                XCTAssertEqual(fade.motion, .crossFade)
                for strip in fade.strips { XCTAssertEqual(strip.x, strip.toX) }
                XCTAssertNil(fade.bars?.coming)
                XCTAssertEqual(fade.bars?.travel, 0)
            }
        }
    }

    // MARK: - The product spec

    /// The product spec's rule for moving panes says what is built, so it
    /// is not read as a breach of it: B-066's 0.6 s with no dimming, and
    /// nothing moving but the view button's switch, went with B-077. The
    /// rule, under "Do not animate panes dramatically.", read here against
    /// `Theme` and the model.
    func testTheProductSpecSaysHowThePanesMove() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .deletingLastPathComponent()     // the repository
            .appendingPathComponent("spec/docs/UI_SPEC.md")
        let spec = try String(contentsOf: url, encoding: .utf8)
        let head = "- Do not animate panes dramatically.\n"
        let start = try XCTUnwrap(spec.range(of: head))
        let rule = spec[start.upperBound...].prefix { $0 != "#" }
            .split(separator: "\n").prefix { $0.hasPrefix("  ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        XCTAssertTrue(rule.contains(
            "The view button's switch, \"< Mailboxes\" and a folder tap in two panes move as "
                + "Mail's do (B-066, B-077, D-015)"), rule)
        XCTAssertTrue(rule.contains("Nothing else moves the panes."), rule)
        for (from, to, kind) in switches + stack {
            XCTAssertNotNil(PaneMove.switching(from: from, to: to, screenWidth: 1194,
                                               reading: .words, crossFading: false), "\(kind)")
        }
        XCTAssertTrue(rule.contains("half a second on UIKit's spring"), rule)
        XCTAssertEqual(Theme.paneMoveDuration, 0.5)
        XCTAssertTrue(rule.contains("no bounce and no scaling"), rule)
        XCTAssertTrue(rule.contains("A column going under another darkens, black at a tenth."), rule)
        XCTAssertEqual(Theme.paneCoveredDim, 0.1)
        XCTAssertTrue(rule.contains("With Prefer Cross-Fade Transitions, \"< Mailboxes\" and a "
                                    + "folder tap fade for half a second instead."), rule)
        for (_, _, kind) in stack {
            XCTAssertEqual(PaneMove.motion(for: kind, crossFading: true), .crossFade)
        }
        for word in ["0.6 s", "no dimming", "0.4 s", "0.3 s", "settle"] {
            XCTAssertFalse(rule.contains(word), word)
        }
    }
}
