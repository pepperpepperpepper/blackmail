import XCTest
@testable import Blackmail

/// The view button's switch as it moves (B-066): where each picture of a
/// pane starts and ends, that the pictures meet with no seam at every
/// instant, that only the real screen meant to be seen shows through them,
/// and how long it all takes. The container that moves them is UIKit and
/// never runs on this host; `PaneArrangementTests` reads its source.
final class PaneMoveTests: XCTestCase {

    private let widths: [CGFloat] = [1024, 1080, 1112, 1133, 1180, 1194, 1210, 1366, 1376]
    private let d = Theme.paneDividerWidth
    /// Each point of the slide the rules are checked at, 0 to 1.
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

    private func move(_ from: PaneArrangement, _ to: PaneArrangement, _ w: CGFloat,
                      reading: PaneMove.Reading = .words,
                      file: StaticString = #filePath, line: UInt = #line) throws -> PaneMove {
        try XCTUnwrap(PaneMove.switching(from: from, to: to, screenWidth: w, reading: reading),
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

    /// Where the list's divider is, beside the list wherever it is laid
    /// out, hidden or not.
    private func listDivider(in panes: PaneArrangement, _ w: CGFloat) -> CGFloat {
        let columns = PaneArrangement.columns(panes.panes, screenWidth: w)
        return (panes.listAtScreenEdge ? 0 : columns.mailboxes + d) + columns.list
    }

    private func picture(_ pane: PaneMove.Pane, of move: PaneMove,
                         file: StaticString = #filePath, line: UInt = #line) throws -> PaneMove.Strip {
        try XCTUnwrap(move.strips.first { $0.pane == pane }, "\(pane)", file: file, line: line)
    }

    // MARK: - Which switches move

    /// Only the view button's three switches move. "< Mailboxes" and a
    /// folder tapped in two panes change what the left column holds, not
    /// how many panes there are, and stay instant, as do the launch, a
    /// return and a folder opened.
    func testOnlyTheViewButtonsSwitchesMove() {
        let foldersShown = Self.foldersInFront
        var listShownAgain = foldersShown
        listShownAgain.showList()
        for w in widths {
            for reading in [PaneMove.Reading.words, .nothing] {
                func switching(_ from: PaneArrangement, _ to: PaneArrangement) -> PaneMove? {
                    PaneMove.switching(from: from, to: to, screenWidth: w, reading: reading)
                }
                for panes in [Self.three, Self.listInFront, foldersShown] {
                    XCTAssertNil(switching(panes, panes), "\(w)")
                }
                // "< Mailboxes", and a folder tapped there.
                XCTAssertNil(switching(Self.listInFront, foldersShown))
                XCTAssertNil(switching(foldersShown, listShownAgain))
                // A switch the button cannot make: from three it lands on the list.
                XCTAssertNil(switching(Self.three, foldersShown))

                for (from, to, kind) in switches {
                    XCTAssertEqual(switching(from, to)?.kind, kind, "\(w)")
                }
            }
        }
        XCTAssertEqual(Self.switched(Self.three), Self.listInFront)
    }

    // MARK: - The moves, written out

    /// Three to two on the 11-inch and the 13-inch: the folders still, the
    /// list from beside them to the screen's edge, the letter's edge from
    /// 581 to 375.5, each divider riding its edge, the backdrop under it
    /// all.
    func testThreeToTwoWrittenOut() throws {
        XCTAssertEqual(try move(Self.three, Self.listInFront, 1194), PaneMove(
            kind: .listOverFolders, screenWidth: 1194,
            strips: [
                .init(pane: .mailboxes, x: 0, width: 250, toX: 0, toShownWidth: 250,
                      patchesViewButton: false),
                .init(pane: .list, x: 250.5, width: 330, toX: 0, toShownWidth: 330,
                      patchesViewButton: false),
                .init(pane: .message, x: 581, width: 613, toX: 375.5, toShownWidth: 613,
                      patchesViewButton: false),
            ],
            lines: [.init(x: 250, toX: -0.5), .init(x: 580.5, toX: 375)],
            backdropFrom: 0, actionsPlateX: 581, placeholder: nil))
        XCTAssertEqual(try move(Self.three, Self.listInFront, 1366), PaneMove(
            kind: .listOverFolders, screenWidth: 1366,
            strips: [
                .init(pane: .mailboxes, x: 0, width: 285, toX: 0, toShownWidth: 285,
                      patchesViewButton: false),
                .init(pane: .list, x: 285.5, width: 377, toX: 0, toShownWidth: 377,
                      patchesViewButton: false),
                .init(pane: .message, x: 663, width: 703, toX: 375.5, toShownWidth: 703,
                      patchesViewButton: false),
            ],
            lines: [.init(x: 285, toX: -0.5), .init(x: 662.5, toX: 375)],
            backdropFrom: 0, actionsPlateX: 663, placeholder: nil))
    }

    /// Two with the list in front, to three: the list from the screen's
    /// edge to beside the folders, its twin view button painted over, the
    /// letter's edge out to 581, and the folders let through on the left.
    func testListInFrontToThreeWrittenOut() throws {
        let at1194 = try move(Self.listInFront, Self.three, 1194)
        XCTAssertEqual(at1194, PaneMove(
            kind: .listOffFolders, screenWidth: 1194,
            strips: [
                .init(pane: .list, x: 0, width: 375, toX: 250.5, toShownWidth: 375,
                      patchesViewButton: true),
                .init(pane: .message, x: 375.5, width: 818.5, toX: 581, toShownWidth: 818.5,
                      patchesViewButton: false),
            ],
            lines: [.init(x: -0.5, toX: 250), .init(x: 375, toX: 580.5)],
            backdropFrom: 250.5, actionsPlateX: 581, placeholder: nil))
        XCTAssertEqual(at1194.revealed, 0...250)
        let at1366 = try move(Self.listInFront, Self.three, 1366)
        XCTAssertEqual(at1366, PaneMove(
            kind: .listOffFolders, screenWidth: 1366,
            strips: [
                .init(pane: .list, x: 0, width: 375, toX: 285.5, toShownWidth: 375,
                      patchesViewButton: true),
                .init(pane: .message, x: 375.5, width: 990.5, toX: 663, toShownWidth: 990.5,
                      patchesViewButton: false),
            ],
            lines: [.init(x: -0.5, toX: 285), .init(x: 375, toX: 662.5)],
            backdropFrom: 285.5, actionsPlateX: 663, placeholder: nil))
        XCTAssertEqual(at1366.revealed, 0...285)
    }

    /// Two with the folders in front, to three: the folders' column draws
    /// in from 375 to its three-pane width, the letter's edge goes out, and
    /// the list is let through between the two lines, which start on the
    /// same point and part.
    func testFoldersInFrontToThreeWrittenOut() throws {
        let at1194 = try move(Self.foldersInFront, Self.three, 1194)
        XCTAssertEqual(at1194, PaneMove(
            kind: .middleOpens, screenWidth: 1194,
            strips: [
                .init(pane: .mailboxes, x: 0, width: 375, toX: 0, toShownWidth: 250,
                      patchesViewButton: false),
                .init(pane: .message, x: 375.5, width: 818.5, toX: 581, toShownWidth: 818.5,
                      patchesViewButton: false),
            ],
            lines: [.init(x: 375, toX: 250), .init(x: 375, toX: 580.5)],
            backdropFrom: nil, actionsPlateX: 581, placeholder: nil))
        XCTAssertEqual(at1194.revealed, 250.5...580.5)
        let at1366 = try move(Self.foldersInFront, Self.three, 1366)
        XCTAssertEqual(at1366, PaneMove(
            kind: .middleOpens, screenWidth: 1366,
            strips: [
                .init(pane: .mailboxes, x: 0, width: 375, toX: 0, toShownWidth: 285,
                      patchesViewButton: false),
                .init(pane: .message, x: 375.5, width: 990.5, toX: 663, toShownWidth: 990.5,
                      patchesViewButton: false),
            ],
            lines: [.init(x: 375, toX: 285), .init(x: 375, toX: 662.5)],
            backdropFrom: nil, actionsPlateX: 663, placeholder: nil))
        XCTAssertEqual(at1366.revealed, 285.5...662.5)
    }

    // MARK: - Where it starts and where it ends

    /// At the start every picture is where its pane is on the screen, and
    /// every divider's line where the divider is, or off the screen's left
    /// edge with the list's when two panes have none; so the first frame is
    /// the screen as it was. At the end each picture's left edge is where
    /// its pane now is, the folders' column cut to its new width, and the
    /// one pane that has gone, the folders in three to two, is wholly under
    /// the list's picture. All worked out here from the columns, not from
    /// the move.
    func testEachPictureStartsWhereItsPaneWasAndEndsWhereItIs() throws {
        for w in widths {
            for (from, to, kind) in switches {
                let move = try move(from, to, w)
                let context = "\(kind) at \(w)"

                // The pictures are of the panes on screen, every one of them.
                let onScreen = [PaneMove.Pane.mailboxes, .list, .message]
                    .filter { span(of: $0, in: from, w) != nil }
                XCTAssertEqual(move.strips.map(\.pane).sorted { "\($0)" < "\($1)" },
                               onScreen.sorted { "\($0)" < "\($1)" }, context)

                for strip in move.strips {
                    let was = try XCTUnwrap(span(of: strip.pane, in: from, w), context)
                    XCTAssertEqual(strip.left(at: 0), was.x, "\(strip.pane) \(context)")
                    XCTAssertEqual(strip.shownWidth(at: 0), was.width, "\(strip.pane) \(context)")
                    if let now = span(of: strip.pane, in: to, w) {
                        XCTAssertEqual(strip.left(at: 1), now.x, "\(strip.pane) \(context)")
                    } else {
                        // Gone: under the list's picture, which is above it.
                        let list = try picture(.list, of: move)
                        XCTAssertGreaterThanOrEqual(strip.left(at: 1), list.left(at: 1), context)
                        XCTAssertLessThanOrEqual(strip.left(at: 1) + strip.shownWidth(at: 1),
                                                 list.left(at: 1) + list.shownWidth(at: 1), context)
                        XCTAssertGreaterThan(move.strips.firstIndex(of: list)!,
                                             move.strips.firstIndex(of: strip)!, context)
                    }
                }
                if kind == .middleOpens {
                    XCTAssertEqual(try picture(.mailboxes, of: move).shownWidth(at: 1),
                                   try XCTUnwrap(span(of: .mailboxes, in: to, w)).width, context)
                }

                // The Mailboxes' divider: where it is in three panes, and in
                // two, off the left edge with the list or at the column's
                // edge with the folders.
                let mailboxes3 = PaneArrangement.columns(.three, screenWidth: w).mailboxes
                func divider1(_ panes: PaneArrangement) -> CGFloat? {
                    panes.mailboxDividerOnScreen ? mailboxes3 : nil
                }
                let line1 = move.lines[0], line2 = move.lines[1]
                if let x = divider1(from) {
                    XCTAssertEqual(line1.left(at: 0), x, context)
                } else if from.leftColumn == .list {
                    XCTAssertLessThanOrEqual(line1.left(at: 0) + d, 0, context)
                } else {
                    XCTAssertEqual(line1.left(at: 0), listDivider(in: from, w), context)
                }
                if let x = divider1(to) {
                    XCTAssertEqual(line1.left(at: 1), x, context)
                } else {
                    XCTAssertLessThanOrEqual(line1.left(at: 1) + d, 0, context)
                }
                XCTAssertEqual(line2.left(at: 0), listDivider(in: from, w), context)
                XCTAssertEqual(line2.left(at: 1), listDivider(in: to, w), context)
            }
        }
    }

    // MARK: - The pieces meet

    /// At every instant each line is glued to the edge it stands for: the
    /// Mailboxes' divider to the list's left edge, or, as the folders'
    /// column draws in, to where it is cut off; the list's divider to the
    /// letter's left edge. And the letter is always the picture on top, so
    /// where the list slides under it, the list is the one hidden.
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
            }
        }
    }

    /// Whole columns, moved sideways only. No picture changes its width:
    /// the folders' column in the middle opening is cut off, never
    /// squeezed. In each switch every picture goes the same way, or stays.
    /// And there is nothing in the model to move anything up or down with.
    func testRigidAndSideways() throws {
        for w in widths {
            for (from, to, kind) in switches {
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
                XCTAssertEqual(ways.first, kind == .listOverFolders ? .minus : .plus, "\(kind) \(w)")
            }
        }
        let stripMembers = Mirror(reflecting: PaneMove.Strip(
            pane: .list, x: 0, width: 1, toX: 0, toShownWidth: 1, patchesViewButton: false))
            .children.compactMap(\.label)
        XCTAssertEqual(stripMembers, ["pane", "x", "width", "toX", "toShownWidth",
                                      "patchesViewButton"])
        XCTAssertEqual(Mirror(reflecting: PaneMove.Line(x: 0, toX: 1)).children.compactMap(\.label),
                       ["x", "toX"])
    }

    // MARK: - What shows through

    /// At every instant every point across the screen is under a picture,
    /// a line or the backdrop, or in the stretch of the real screen meant
    /// to show: none from three to two, the folders where they already are
    /// as the list leaves them, and the list between the folders and the
    /// letter as the middle opens. By the end of the slide exactly that
    /// stretch shows. Checked point by point every half point, and by the
    /// model's own reckoning.
    func testOnlyWhatIsMeantShowsThrough() throws {
        for w in widths {
            for (from, to, kind) in switches {
                let move = try move(from, to, w)
                for p in instants {
                    let context = "\(kind) at \(w), \(p)"
                    for x in stride(from: CGFloat(0.25), to: w, by: 0.5) {
                        let pictured = move.strips.contains {
                            $0.left(at: p) <= x && x <= $0.left(at: p) + $0.shownWidth(at: p)
                        }
                        let lined = move.lines.contains { $0.left(at: p) <= x && x <= $0.left(at: p) + d }
                        let backed = move.backdropFrom.map { x >= $0 } ?? false
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
                switch kind {
                case .listOverFolders:
                    XCTAssertNil(move.revealed)
                    XCTAssertEqual(move.uncovered(at: 1), [])
                case .listOffFolders, .middleOpens:
                    XCTAssertEqual(move.uncovered(at: 1), [try XCTUnwrap(move.revealed)], "\(kind) \(w)")
                }
                XCTAssertEqual(move.uncovered(at: 0), [], "\(kind) \(w)")
            }
        }
    }

    /// Where the list's picture and the letter's do not meet, the backdrop
    /// shows, never more of it than the difference between the list's
    /// width in three panes and the column in two: 45 pt on the 11-inch
    /// from three to two, 2 pt on the 13-inch the other way.
    func testTheGapIsNeverMoreThanTheListsChangeOfWidth() throws {
        for w in widths {
            let l = PaneArrangement.columns(.three, screenWidth: w).list
            let c = Theme.twoPaneLeftColumnWidth
            for (from, to, kind) in switches where kind != .middleOpens {
                let move = try move(from, to, w)
                let list = try picture(.list, of: move)
                func gap(_ p: CGFloat) -> CGFloat {
                    max(0, move.lines[1].left(at: p) - (list.left(at: p) + list.shownWidth(at: p)))
                }
                for p in instants {
                    XCTAssertLessThanOrEqual(gap(p), abs(l - c) + 1e-9, "\(kind) at \(w), \(p)")
                }
                XCTAssertEqual(gap(1), max(0, kind == .listOverFolders ? c - l : l - c),
                               accuracy: 1e-9, "\(kind) \(w)")
            }
        }
        XCTAssertEqual(try move(Self.three, Self.listInFront, 1194).lines[1].left(at: 1)
                       - 330, 45)
    }

    // MARK: - The still plates

    /// The letter's actions are pictured once, from the letter's left edge
    /// in three panes to the screen's right, and never move. Wide enough at
    /// every width for the actions of the letter's own picture to stay
    /// under it as that picture slides, and no divider ever comes into it.
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
                    XCTAssertLessThanOrEqual(move.lines[1].left(at: p) + d, move.actionsPlateX + 1e-9,
                                             "\(kind) at \(w), \(p)")
                }
                // Only the list's picture from two panes carries the twin
                // view button, which is painted over.
                XCTAssertEqual(move.strips.filter(\.patchesViewButton).map(\.pane),
                               kind == .listOffFolders ? [.list] : [], "\(kind) \(w)")
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
                XCTAssertEqual(PaneMove(kind: empty.kind, screenWidth: empty.screenWidth,
                                        strips: empty.strips, lines: empty.lines,
                                        backdropFrom: empty.backdropFrom,
                                        actionsPlateX: empty.actionsPlateX, placeholder: nil),
                               words, context)
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
    /// beneath. Carried in the letter's picture, it would have gone the
    /// whole way and landed 102.75 pt from them on the 11-inch and
    /// 143.75 pt on the 13-inch, and jumped back as the pictures faded.
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
                    // Room either side for words up to 300 pt wide, clear of
                    // the divider and the screen's edge.
                    XCTAssertGreaterThanOrEqual(middle.at(p) - edge, 150, "\(context), \(p)")
                    XCTAssertGreaterThanOrEqual(w - middle.at(p), 150, "\(context), \(p)")
                }
            }
        }
        let at1194 = try move(Self.three, Self.listInFront, 1194, reading: .nothing)
        XCTAssertEqual(at1194.placeholder, PaneMove.Middle(x: 887.5, toX: 784.75))
        let letter1194 = try picture(.message, of: at1194)
        XCTAssertEqual((letter1194.toX - letter1194.x) - (784.75 - 887.5), -102.75)
        let at1366 = try move(Self.listInFront, Self.three, 1366, reading: .nothing)
        XCTAssertEqual(at1366.placeholder, PaneMove.Middle(x: 870.75, toX: 1014.5))
        let letter1366 = try picture(.message, of: at1366)
        XCTAssertEqual((letter1366.toX - letter1366.x) - (1014.5 - 870.75), 143.75)
    }

    // MARK: - Holding still

    /// Where a list or a letter comes to rest, from its content, its size
    /// and its insets: from the top end, under the bar, to the bottom end,
    /// and the same sideways; the top end at the bottom too when the
    /// content is shorter than the view. Inside the ends it is coasting or
    /// still; past either by more than half a point it is bouncing, and the
    /// switch is made at once. A bounce of less than that is taken as at
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

    /// 0.4 s of slide, then 0.2 s of settle, from `Theme`; a dissolve of
    /// 0.3 s alone with Reduce Motion or Prefer Cross-Fade Transitions.
    func testTheTimeline() {
        XCTAssertEqual(PaneMove.timeline(dissolving: false),
                       [.slide(Theme.paneSlideDuration), .settle(Theme.paneSettleDuration)])
        XCTAssertEqual(Theme.paneSlideDuration, 0.4)
        XCTAssertEqual(Theme.paneSettleDuration, 0.2)
        XCTAssertLessThanOrEqual(PaneMove.timeline(dissolving: false).map(\.duration).reduce(0, +),
                                 0.6 + 1e-9)
        XCTAssertEqual(PaneMove.timeline(dissolving: true), [.dissolve(0.3)])
        XCTAssertEqual(Theme.paneDissolveDuration, 0.3)
    }
}
