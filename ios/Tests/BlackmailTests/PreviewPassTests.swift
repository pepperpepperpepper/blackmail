import XCTest
@testable import Blackmail

/// The order the list asks for previews in, and when it stops. The whole of
/// the list's preview loop apart from the cells it patches.
final class PreviewPassTests: XCTestCase {

    private func row(_ id: String, in mailboxID: String) -> MessageSummary {
        MessageSummary(id: id, mailboxID: mailboxID, sender: "Sam Example", subject: id,
                       preview: "", date: Date(timeIntervalSince1970: 0),
                       isRead: true, isFlagged: false)
    }

    private var searchResults: [MessageSummary] {
        [row("1", in: "All Mail"), row("2", in: "Trash"), row("3", in: "All Mail"),
         row("4", in: "Spam"), row("5", in: "Trash")]
    }

    func testGroupsFollowTheOrderTheRowsAreDrawnIn() {
        XCTAssertEqual(PreviewPass.groups(for: searchResults), [
            PreviewPass.Group(mailboxID: "All Mail", ids: ["1", "3"]),
            PreviewPass.Group(mailboxID: "Trash", ids: ["2", "5"]),
            PreviewPass.Group(mailboxID: "Spam", ids: ["4"]),
        ])
        XCTAssertEqual(PreviewPass.groups(for: []), [])
    }

    func testEachGroupIsFinishedBeforeTheNextIsAskedFor() async {
        var asked: [String] = []
        var inFlight = 0
        var mostAtOnce = 0
        var applied: [String: String] = [:]

        await PreviewPass.run(PreviewPass.groups(for: searchResults),
                              fetch: { ids, mailboxID in
                                  asked.append(mailboxID)
                                  inFlight += 1
                                  mostAtOnce = max(mostAtOnce, inFlight)
                                  await Task.yield()
                                  inFlight -= 1
                                  return Dictionary(uniqueKeysWithValues: ids.map { ($0, mailboxID) })
                              },
                              isCurrent: { true },
                              apply: { applied.merge($0) { a, _ in a } })

        XCTAssertEqual(asked, ["All Mail", "Trash", "Spam"])
        XCTAssertEqual(mostAtOnce, 1)
        XCTAssertEqual(applied, ["1": "All Mail", "2": "Trash", "3": "All Mail",
                                 "4": "Spam", "5": "Trash"])
    }

    func testTheListBeingReplacedStopsThePassAndDropsWhatWasInFlight() async {
        var asked: [String] = []
        var applied: [String] = []
        var current = true

        await PreviewPass.run(PreviewPass.groups(for: searchResults),
                              fetch: { ids, mailboxID in
                                  asked.append(mailboxID)
                                  // The list is replaced while Trash's
                                  // previews are on their way.
                                  if mailboxID == "Trash" { current = false }
                                  return [ids[0]: "text"]
                              },
                              isCurrent: { current },
                              apply: { applied += $0.keys })

        XCTAssertEqual(asked, ["All Mail", "Trash"], "Spam belongs to rows no longer on screen")
        XCTAssertEqual(applied, ["1"], "Trash's answer arrived after the list it was for had gone")
    }

    func testAGroupThatFailsCostsOnlyItsOwnPreviews() async {
        var applied: [String] = []

        await PreviewPass.run(PreviewPass.groups(for: searchResults),
                              fetch: { ids, mailboxID in
                                  if mailboxID == "Trash" { throw MailError.cannotConnect }
                                  return Dictionary(uniqueKeysWithValues: ids.map { ($0, "text") })
                              },
                              isCurrent: { true },
                              apply: { applied += $0.keys.sorted() })

        XCTAssertEqual(applied, ["1", "3", "4"])
    }
}
