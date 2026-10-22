import XCTest
@testable import Blackmail

/// His line from Sent Mail going into the stack while a finger drags it
/// (B-104), on the stack's own script run on a model page (`ModelPage`).
///
/// Seen on the test iPad 2026-10-22: with a finger dragging the reading
/// pane as his reply's line went in, J's newest letter dropped by one line,
/// and went on with the finger from there. The script's `scrollBy`, which
/// keeps the letter he is reading where it is, was lost while the scroll
/// view followed the finger. Now what goes into the stack is held while the
/// stack moves under a finger or coasts after it, and goes in once it has
/// been still for a quarter of a second, as it goes in at rest. The model
/// replaces an offset the script sets while the finger or the coast moves
/// the stack, as the iPad did, so these fail on the script as it was.
///
/// The stack is the usual one: J1, read, closed to its line, J2, the
/// newest, open, the pane opened at J1's line; and his reply A1 between
/// them, found late.
final class HisLineUnderTheFingerTests: XCTestCase {

    private typealias Step = ModelPage.Step

    private static let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func inbox(_ n: Int, read: Bool = true) -> MessageSummary {
        MessageSummary(id: "1/\(n)", mailboxID: "INBOX", sender: "Jane Example <jane@example.com>",
                       subject: "Re: the roof", preview: "letter \(n)",
                       date: Self.base.addingTimeInterval(Double(n) * 60),
                       isRead: read, isFlagged: false, threadID: "1700000000000000042",
                       gmailMessageID: UInt64(9_000 + n),
                       arrived: Self.base.addingTimeInterval(Double(n) * 60))
    }

    private func his(_ n: Int) -> ConversationDocument.Entry {
        ConversationDocument.entry(forHis: MessageSummary(
            id: "6/\(n)", mailboxID: "[Gmail]/Sent Mail", sender: "owner@example.com",
            subject: "Re: the roof", preview: "mine \(n)",
            date: Self.base.addingTimeInterval(Double(n) * 60),
            isRead: true, isFlagged: false, threadID: "1700000000000000042",
            gmailMessageID: UInt64(8_000 + n), arrived: Self.base.addingTimeInterval(Double(n) * 60)),
            foundIn: "Sent Mail")
    }

    /// J1 above J2, as the pane draws them, the pane opened at J1's line.
    private var page: String {
        let stack = ConversationDocument.stack(of: MessageThread(messages: [inbox(5), inbox(3)]))
        return ConversationDocument.html(entries: stack, inset: 20, bodyPointSize: 17, lineHeight: 1.4)
    }

    private let j1 = "m1_3", j2 = "m1_5", a1 = "mr6_4"

    /// A1's line, to go in before J2.
    private var a1BeforeJ2: ConversationDocument.Insert { .init([his(4)], before: "1/5") }

    /// J2's body, 1,500 px of it, which comes before the lookup starts.
    private func j2Body(_ at: Int, height: Int = 1_500) -> Step {
        .fill(at, ConversationDocument.Fill(sectionID: j2, body: .init(html: "<p data-h=\"\(height)\">Dear Carlo,</p>",
                                                                       isHTML: false)))
    }

    /// A finger landing on J2's body at `start`, and dragging the stack up
    /// `by` px at an even pace over `ms`, a move each frame.
    private func drag(from start: Int, y: Int = 480, by dy: Int, over ms: Int) -> [Step] {
        let moves = ms / 16
        return [.down(start, y: y)] + (1...moves).map { i in
            .move(start + i * 16, y: y - Int((Double(dy) * Double(i) / Double(moves)).rounded()))
        }
    }

    private func run(_ steps: [Step], end: Int = 4_000,
                     script: String = ConversationDocument.script) throws -> ModelPage.Run {
        do {
            return try ModelPage.run(script, page: page, steps: steps, end: end)
        } catch is ModelPage.NoNode {
            throw XCTSkip("node is not on this host")
        }
    }

    // MARK: - Under a finger

    /// The iPad's case, as checked there: the finger lands 50 ms after the
    /// tap and drags the stack slowly up for 1.5 s, and A1 is found at 0.6
    /// s, mid-drag. J2 moves with the finger and nothing else, through the
    /// drag, the lift and A1 going in; A1 goes in once the finger has let
    /// go, within a quarter of a second of the stack being still and the
    /// next look a tenth after, directly above J2, once. With J2's line
    /// still on the glass at the lift, A1 takes the place of J1's line
    /// above it, and with J2's line gone above the glass it goes in out of
    /// sight; J2 stays either way.
    func testHisLineGoesInOnceTheFingerHasLetGoAndJ2MovesOnlyWithTheFinger() throws {
        for dy in [30, 100] {
            let steps = [j2Body(40)] + drag(from: 50, by: dy, over: 1_500) + [.up(1_550), .insert(600, a1BeforeJ2)]
            let run = try run(steps)
            let name = "a drag of \(dy) px"
            XCTAssertEqual(run.jumps(of: j2).map(\.by), [], name)
            XCTAssertEqual(run.calls.first { $0.action == "insert" }?.changedAtOnce, false, name)
            let came = try XCTUnwrap(run.firstFrame(with: a1), name)
            XCTAssertGreaterThan(came, 1_550, "not while the finger is down: \(name)")
            XCTAssertLessThanOrEqual(came, 1_550 + 250 + 100 + 16, "and soon after it lifts: \(name)")
            XCTAssertEqual(run.order, [j1, a1, j2], name)
            let last = try XCTUnwrap(run.frames.last)
            XCTAssertEqual(try XCTUnwrap(last.top(a1)), try XCTUnwrap(last.top(j2)) - 38, name)
            XCTAssertEqual(run.errors, [], name)
            XCTAssertEqual(run.held, 0, "nothing left held: \(name)")
        }
    }

    /// The finger flicks the stack and lifts, and it coasts on; A1 comes
    /// while it coasts. J2 moves with the coast and nothing else, and A1
    /// goes in once the stack has stopped.
    func testWhileTheStackCoastsItIsHeldTooUntilTheStackHasStopped() throws {
        let steps = [j2Body(40)] + drag(from: 50, by: 60, over: 560) + [.up(610, coast: 0.8), .insert(700, a1BeforeJ2)]
        let run = try run(steps)
        XCTAssertEqual(run.jumps(of: j2).map(\.by), [])
        let stopped = try XCTUnwrap(run.frames.last { $0.coasting }?.t)
        XCTAssertGreaterThan(stopped, 700, "A1 came while the stack coasted")
        let came = try XCTUnwrap(run.firstFrame(with: a1))
        XCTAssertGreaterThan(came, stopped)
        XCTAssertLessThanOrEqual(came, stopped + 16 + 250 + 100 + 16)
        XCTAssertEqual(run.order, [j1, a1, j2])
        XCTAssertEqual(run.errors, [])
    }

    /// A finger still on the glass in the middle of a drag holds it: the
    /// next move would replace the script's offset. Held still 0.8 s, A1
    /// coming meanwhile, then dragged on: J2 moves only with the finger,
    /// and A1 goes in after the lift.
    func testAFingerStillInTheMiddleOfADragHoldsItToo() throws {
        let first = drag(from: 50, by: 40, over: 496)
        let second = drag(from: 1_346, y: 440, by: 40, over: 496).dropFirst()
        let run = try run([j2Body(40)] + first + second + [.up(1_850), .insert(800, a1BeforeJ2)])
        XCTAssertEqual(run.jumps(of: j2).map(\.by), [])
        XCTAssertGreaterThan(try XCTUnwrap(run.firstFrame(with: a1)), 1_850)
        XCTAssertEqual(run.order, [j1, a1, j2])
    }

    /// A lift WebKit never sends, or a finger resting on the glass, holds
    /// it two seconds from the finger's last move and no longer: it goes
    /// in then, whatever else happens, and J2 does not move.
    func testALiftNeverHeardHoldsItTwoSecondsAtMost() throws {
        let dragging = drag(from: 50, by: 60, over: 1_500)
        let lastMove = try XCTUnwrap(dragging.last?.at)
        let run = try run([j2Body(40)] + dragging + [.up(1_550, silent: true), .insert(600, a1BeforeJ2)],
                          end: 5_000)
        XCTAssertEqual(run.jumps(of: j2).map(\.by), [])
        let came = try XCTUnwrap(run.firstFrame(with: a1), "it goes in")
        XCTAssertGreaterThanOrEqual(came, Double(lastMove + 2_000))
        XCTAssertLessThanOrEqual(came, Double(lastMove + 2_000 + 100 + 16))
        XCTAssertEqual(run.order, [j1, a1, j2])
        XCTAssertEqual(run.held, 0)
    }

    // MARK: - With nothing moving the stack

    /// Untouched, A1 goes in at once, as before: the hold the stack opened
    /// with passes to A1's line, at the top of the pane where J1's was, and
    /// J2 stays one line below it. And after a drag, once the stack has
    /// been still a second: at once, J2 where the drag left it.
    func testWithNothingMovingTheStackItGoesInAtOnceAsBefore() throws {
        let untouched = try run([j2Body(40), .insert(600, a1BeforeJ2)])
        XCTAssertEqual(untouched.calls.first { $0.action == "insert" }?.changedAtOnce, true)
        XCTAssertEqual(untouched.jumps(of: j2).map(\.by), [])
        let last = try XCTUnwrap(untouched.frames.last)
        XCTAssertEqual(last.top(a1), 0)
        XCTAssertEqual(last.top(j2), 38)
        XCTAssertEqual(untouched.order, [j1, a1, j2])

        let still = try run([j2Body(40)] + drag(from: 50, by: 60, over: 1_500)
                            + [.up(1_550), .insert(2_550, a1BeforeJ2)])
        XCTAssertEqual(still.calls.first { $0.action == "insert" }?.changedAtOnce, true)
        XCTAssertEqual(still.jumps(of: j2).map(\.by), [])
        XCTAssertEqual(still.order, [j1, a1, j2])
    }

    // MARK: - What comes meanwhile

    /// What comes while his line is held goes in after it, in the order it
    /// came, so the stack on the page is the stack the pane holds
    /// (`PaneDocument`): his letter after the newest, held, then a letter
    /// that came into the conversation, put in at the bottom after it, and
    /// that letter's body, into its section once it is there. A body for a
    /// letter already on the page goes in at once; one for a section that
    /// never comes is dropped, as before.
    func testWhatComesWhileItIsHeldGoesInAfterItInTheOrderItCame() throws {
        let arrival = ConversationDocument.entry(for: inbox(7, read: false), open: true)
        let steps = [j2Body(40)] + drag(from: 50, by: 60, over: 1_500) + [
            .up(1_550),
            .insert(600, ConversationDocument.Insert([his(6)], before: nil)),
            .append(700, ConversationDocument.Append([arrival])),
            .fill(800, ConversationDocument.Fill(sectionID: "m1_7",
                                                 body: .init(html: "<p data-h=\"222\">Hi</p>", isHTML: false))),
            .fill(820, ConversationDocument.Fill(sectionID: "m1_99",
                                                 body: .init(html: "<p data-h=\"9\">gone</p>", isHTML: false))),
            j2Body(900, height: 1_600),
        ]
        let run = try run(steps)
        XCTAssertEqual(run.order, [j1, j2, "mr6_6", "m1_7"])
        let last = try XCTUnwrap(run.frames.last)
        XCTAssertEqual(last.sections.first { $0.id == "m1_7" }?.body, "222")
        XCTAssertEqual(run.calls.filter { $0.action != "fill" }.map(\.changedAtOnce), [false, false],
                       "his letter and the one that came, held")
        let soon = try XCTUnwrap(run.frames.first { $0.t > 900 })
        XCTAssertEqual(soon.sections.first { $0.id == j2 }?.body, "1600", "J2's body at once")
        XCTAssertNil(soon.top("m1_7"), "the letter that came, held behind his")
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.held, 0)
    }

    /// One change held that throws takes none of the others with it.
    func testOneThatFailsDoesNotTakeTheRestWithIt() throws {
        let arrival = ConversationDocument.entry(for: inbox(7, read: false), open: false)
        let steps = [j2Body(40)] + drag(from: 50, by: 60, over: 1_500) + [
            .up(1_550), .breakNextInsert(590), .insert(600, a1BeforeJ2),
            .append(700, ConversationDocument.Append([arrival])),
        ]
        let run = try run(steps)
        XCTAssertEqual(run.order, [j1, j2, "m1_7"])
        XCTAssertEqual(run.errors, [])
        XCTAssertEqual(run.held, 0)
    }

    /// A tap on J1's line while A1 is held: the line is still under the
    /// finger at the lift, so the tap opens J1, once, and A1 goes in after
    /// it, between J1 and J2, J1's line staying at the top. On the script as
    /// it was, A1 went in under the finger and moved J1's line from under
    /// it, and the lift opened nothing.
    func testATapOnALineWhileItIsHeldOpensThatLetterOnce() throws {
        let run = try run([j2Body(40), .down(500, y: 20), .insert(550, a1BeforeJ2), .up(650)])
        XCTAssertEqual(run.posts, [ModelPage.Run.Post(id: j1, open: true)])
        XCTAssertEqual(Set(run.frames.compactMap { $0.top(j1) }), [0])
        XCTAssertGreaterThan(try XCTUnwrap(run.firstFrame(with: a1)), 650)
        XCTAssertEqual(run.order, [j1, a1, j2])
        XCTAssertEqual(run.errors, [])
    }
}
