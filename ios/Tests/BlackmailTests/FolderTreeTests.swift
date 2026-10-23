import XCTest
@testable import Blackmail

/// The Mailboxes pane's order, names and indent, from LIST (B-116).
///
/// With labels in the account, Gmail's Important and Starred were sorted by
/// name among them, one step in, so that each read as a folder inside the
/// label above it, and a label inside another was drawn under whichever
/// label came before it by the last part of its name. And a label called
/// "Drafts" opened Gmail's Drafts. These run the test account's own LIST,
/// with labels in the shapes of his, as the client reads it; and one with no
/// labels, which must come out as it did before, row for row.
final class FolderTreeTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "FolderTreeTests"

    /// The tests' language for the order of the names, so that they do not
    /// depend on the host's. The iPad uses its own, as Mail does.
    private let english = Locale(identifier: "en_US")

    override func tearDown() {
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        super.tearDown()
    }

    // MARK: - The test account's LIST

    /// The test account's LIST on 2026-10-23, with the labels in the shapes
    /// of his own, in Gmail's order. "Unopened 4/17/17" is one label whose
    /// name holds slashes, which Gmail splits into `\Noselect` parents.
    /// "Drafts" is a label, and "[Gmail]/Sent Messages" a label inside
    /// "[Gmail]"; "[Gmail]All Mail", "[Gmail]Drafts", "[Gmail]Spam" and
    /// "[Gmail]Trash" are labels whose names begin with "[Gmail]".
    static let testAccountsList = [
        #"* LIST (\HasNoChildren) "/" "Bank""#,
        #"* LIST (\HasNoChildren) "/" "Books""#,
        #"* LIST (\HasNoChildren) "/" "Church""#,
        #"* LIST (\HasNoChildren) "/" "Deleted Messages""#,
        #"* LIST (\HasNoChildren) "/" "Doctor""#,
        #"* LIST (\HasNoChildren) "/" "Drafts""#,
        #"* LIST (\HasNoChildren) "/" "Family""#,
        #"* LIST (\HasNoChildren) "/" "Friends""#,
        #"* LIST (\HasNoChildren) "/" "Garden""#,
        #"* LIST (\HasNoChildren) "/" "House""#,
        #"* LIST (\HasNoChildren) "/" "INBOX""#,
        #"* LIST (\HasChildren) "/" "Junk E-mail""#,
        #"* LIST (\HasNoChildren) "/" "Junk E-mail/Drafts""#,
        #"* LIST (\HasNoChildren) "/" "Note to Self: Letters to Himself""#,
        #"* LIST (\HasNoChildren) "/" "Notes""#,
        #"* LIST (\HasNoChildren) "/" "Old Mail""#,
        #"* LIST (\HasNoChildren) "/" "Photos""#,
        #"* LIST (\HasNoChildren) "/" "Recipes""#,
        #"* LIST (\HasNoChildren) "/" "Taxes""#,
        #"* LIST (\HasNoChildren) "/" "Travel 2017""#,
        #"* LIST (\HasChildren \Noselect) "/" "Unopened 4""#,
        #"* LIST (\HasChildren \Noselect) "/" "Unopened 4/17""#,
        #"* LIST (\HasNoChildren) "/" "Unopened 4/17/17""#,
        #"* LIST (\HasChildren \Noselect) "/" "[Gmail]""#,
        #"* LIST (\All \HasNoChildren) "/" "[Gmail]/All Mail""#,
        #"* LIST (\Drafts \HasNoChildren) "/" "[Gmail]/Drafts""#,
        #"* LIST (\HasNoChildren \Important) "/" "[Gmail]/Important""#,
        #"* LIST (\HasNoChildren \Sent) "/" "[Gmail]/Sent Mail""#,
        #"* LIST (\HasNoChildren) "/" "[Gmail]/Sent Messages""#,
        #"* LIST (\HasNoChildren \Junk) "/" "[Gmail]/Spam""#,
        #"* LIST (\Flagged \HasNoChildren) "/" "[Gmail]/Starred""#,
        #"* LIST (\HasNoChildren \Trash) "/" "[Gmail]/Trash""#,
        #"* LIST (\HasChildren) "/" "[Gmail]All Mail""#,
        #"* LIST (\HasNoChildren) "/" "[Gmail]All Mail/Trip 2017""#,
        #"* LIST (\HasNoChildren) "/" "[Gmail]Drafts""#,
        #"* LIST (\HasNoChildren) "/" "[Gmail]Spam""#,
        #"* LIST (\HasNoChildren) "/" "[Gmail]Trash""#,
    ]

    /// The same account before the labels: what the round of 2026-10-23
    /// logged at its start, its fourteen labels left out.
    static let noLabelsList = [
        #"* LIST (\HasNoChildren) "/" "INBOX""#,
        #"* LIST (\HasChildren \Noselect) "/" "[Gmail]""#,
        #"* LIST (\All \HasNoChildren) "/" "[Gmail]/All Mail""#,
        #"* LIST (\Drafts \HasNoChildren) "/" "[Gmail]/Drafts""#,
        #"* LIST (\HasNoChildren \Important) "/" "[Gmail]/Important""#,
        #"* LIST (\HasNoChildren \Sent) "/" "[Gmail]/Sent Mail""#,
        #"* LIST (\HasNoChildren \Junk) "/" "[Gmail]/Spam""#,
        #"* LIST (\Flagged \HasNoChildren) "/" "[Gmail]/Starred""#,
        #"* LIST (\HasNoChildren \Trash) "/" "[Gmail]/Trash""#,
    ]

    /// Their unread counts as STATUS gave them that morning.
    static let noLabelsUnread = ["INBOX": 13, "[Gmail]/All Mail": 13, "[Gmail]/Important": 1,
                                 "[Gmail]/Sent Mail": 11, "[Gmail]/Trash": 165]

    /// Each row as the pane draws it: the server's name, which a tap opens,
    /// the name drawn, the steps in, and the role.
    private struct Row: Equatable, CustomStringConvertible {
        let id: String
        let name: String
        let depth: Int
        let role: Mailbox.Role?

        init(_ id: String, _ name: String, _ depth: Int, _ role: Mailbox.Role? = nil) {
            self.id = id
            self.name = name
            self.depth = depth
            self.role = role
        }

        init(_ mailbox: Mailbox) {
            self.init(mailbox.id, mailbox.name, mailbox.depth, mailbox.role)
        }

        var description: String {
            "\(String(repeating: "  ", count: depth))\(name) [\(id)]\(role.map { " \($0)" } ?? "")"
        }
    }

    /// The test account's pane, top to bottom.
    private static let testAccountsPane = [
        // The Inbox, then the roles, as before.
        Row("INBOX", "INBOX", 0, .inbox),
        Row("[Gmail]/Drafts", "Drafts", 1, .drafts),
        Row("[Gmail]/Sent Mail", "Sent Mail", 1, .sent),
        Row("[Gmail]/Spam", "Spam", 1, .junk),
        Row("[Gmail]/Trash", "Trash", 1, .trash),
        Row("[Gmail]/All Mail", "All Mail", 1, .archive),
        // Gmail's others inside "[Gmail]", by name, with them.
        Row("[Gmail]/Important", "Important", 1),
        Row("[Gmail]/Sent Messages", "Sent Messages", 1),
        Row("[Gmail]/Starred", "Starred", 1),
        // The labels, a tree, each level by name: "[" before the letters,
        // as Mail sorts in English.
        Row("[Gmail]All Mail", "[Gmail]All Mail", 0),
        Row("[Gmail]All Mail/Trip 2017", "Trip 2017", 1),
        Row("[Gmail]Drafts", "[Gmail]Drafts", 0),
        Row("[Gmail]Spam", "[Gmail]Spam", 0),
        Row("[Gmail]Trash", "[Gmail]Trash", 0),
        Row("Bank", "Bank", 0),
        Row("Books", "Books", 0),
        Row("Church", "Church", 0),
        Row("Deleted Messages", "Deleted Messages", 0),
        Row("Doctor", "Doctor", 0),
        Row("Drafts", "Drafts", 0),
        Row("Family", "Family", 0),
        Row("Friends", "Friends", 0),
        Row("Garden", "Garden", 0),
        Row("House", "House", 0),
        Row("Junk E-mail", "Junk E-mail", 0),
        Row("Junk E-mail/Drafts", "Drafts", 1),
        Row("Note to Self: Letters to Himself", "Note to Self: Letters to Himself", 0),
        Row("Notes", "Notes", 0),
        Row("Old Mail", "Old Mail", 0),
        Row("Photos", "Photos", 0),
        Row("Recipes", "Recipes", 0),
        Row("Taxes", "Taxes", 0),
        Row("Travel 2017", "Travel 2017", 0),
        // Inside two folders that are not drawn: its path, at the left edge.
        Row("Unopened 4/17/17", "Unopened 4/17/17", 0),
    ]

    private static func listings(_ lines: [String]) -> [IMAPMailboxListing] {
        IMAPParser.parseList(lines.map { IMAPResponseLine(text: $0, literals: []) })
    }

    func testTheTestAccountsLabelsAreDrawnAsATreeAfterGmailsOwnFolders() {
        let listed = Self.listings(Self.testAccountsList)
        XCTAssertEqual(listed.count, 37, "the parser read every line")
        let pane = FolderTree.mailboxes(from: listed, unread: [:], locale: english).map(Row.init)
        XCTAssertEqual(pane, Self.testAccountsPane,
                       "\n" + pane.map(\.description).joined(separator: "\n"))
        // What the screenshot of the round showed, now otherwise: neither
        // Important nor Starred is drawn under a label.
        let important = pane.firstIndex { $0.id == "[Gmail]/Important" }!
        let starred = pane.firstIndex { $0.id == "[Gmail]/Starred" }!
        let firstLabel = pane.firstIndex { $0.role == nil && !$0.id.hasPrefix("[Gmail]/") }!
        XCTAssertLessThan(important, firstLabel)
        XCTAssertLessThan(starred, firstLabel)
    }

    func testTheOrderDoesNotDependOnTheOrderLISTGivesThem() {
        let listed = Self.listings(Self.testAccountsList)
        let expected = FolderTree.mailboxes(from: listed, unread: [:], locale: english)
        XCTAssertEqual(FolderTree.mailboxes(from: Array(listed.reversed()), unread: [:],
                                            locale: english), expected, "reversed")
        // Every child before its parent, and the containers last.
        let byDepth = listed.sorted { a, b in
            let da = a.name.filter { $0 == "/" }.count, db = b.name.filter { $0 == "/" }.count
            return da != db ? da > db : a.name > b.name
        }
        XCTAssertEqual(FolderTree.mailboxes(from: byDepth, unread: [:], locale: english),
                       expected, "children first")
    }

    /// Were the folders "Unopened 4/17/17" is inside folders that can be
    /// opened, labels of their own, it would be drawn under them, two steps
    /// in, by the last part of its name: a tree, however deep, in any order
    /// LIST gives it.
    func testALabelInsideDrawnLabelsIsDrawnUnderThem() {
        let lines = Self.testAccountsList.map {
            $0.replacingOccurrences(of: #"(\HasChildren \Noselect) "/" "Unopened"#,
                                    with: #"(\HasChildren) "/" "Unopened"#)
        }
        let listed = Self.listings(lines)
        let expected = Self.testAccountsPane.dropLast() + [Row("Unopened 4", "Unopened 4", 0),
                                                           Row("Unopened 4/17", "17", 1),
                                                           Row("Unopened 4/17/17", "17", 2)]
        XCTAssertEqual(FolderTree.mailboxes(from: listed, unread: [:], locale: english)
                        .map(Row.init), Array(expected))
        XCTAssertEqual(FolderTree.mailboxes(from: Array(listed.reversed()), unread: [:],
                                            locale: english).map(Row.init), Array(expected))
    }

    /// Were "[Gmail]" a folder that can be opened, it would be a label like
    /// any other, drawn among them, with Gmail's others under it by name,
    /// as Mail draws its "[Gmail]" row; the roles stay where they are.
    func testAContainerThatCanBeOpenedIsDrawnWithItsOwnUnderIt() {
        let lines = Self.testAccountsList.map {
            $0.replacingOccurrences(of: #"(\HasChildren \Noselect) "/" "[Gmail]""#,
                                    with: #"(\HasChildren) "/" "[Gmail]""#)
        }
        let listed = Self.listings(lines)
        let others = Self.testAccountsPane[6...8].map { Row($0.id, $0.name, 1) }
        let expected = Array(Self.testAccountsPane[..<6]) + [Row("[Gmail]", "[Gmail]", 0)] + others
            + Array(Self.testAccountsPane[9...])
        XCTAssertEqual(FolderTree.mailboxes(from: listed, unread: [:], locale: english)
                        .map(Row.init), expected)
        XCTAssertEqual(FolderTree.mailboxes(from: Array(listed.reversed()), unread: [:],
                                            locale: english).map(Row.init), expected)
    }

    func testEveryRowIsTheFolderItsTapOpensWithItsCount() {
        let listed = Self.listings(Self.testAccountsList)
        let unread = Dictionary(uniqueKeysWithValues: listed.enumerated().map {
            ($0.element.name, $0.offset)
        })
        let pane = FolderTree.mailboxes(from: listed, unread: unread, locale: english)
        // One row for every folder that can be opened, and none for the three
        // that cannot; each row's id the LIST name, its count that folder's.
        XCTAssertEqual(Set(pane.map(\.id)),
                       Set(listed.filter(\.isSelectable).map(\.name)))
        XCTAssertEqual(pane.count, 34)
        for row in pane { XCTAssertEqual(row.unreadCount, unread[row.id], row.id) }
        XCTAssertFalse(pane.contains { ["[Gmail]", "Unopened 4", "Unopened 4/17"].contains($0.id) })
    }

    // MARK: - With no labels, as before

    /// The order and depth as they were before B-116, kept here to compare
    /// with: every folder by the last part of its name, the roles in a
    /// fixed order, everything else by name.
    private static func asBefore(_ listings: [IMAPMailboxListing], unread: [String: Int]) -> [Mailbox] {
        var out: [Mailbox] = []
        for l in listings where l.isSelectable {
            let delimiter = l.delimiter ?? "/"
            let components = delimiter.isEmpty ? [l.name] : l.name.components(separatedBy: delimiter)
            out.append(Mailbox(id: l.name, name: components.last ?? l.name,
                               unreadCount: unread[l.name] ?? 0, role: l.specialUse,
                               depth: max(0, components.count - 1)))
        }
        let rank: [Mailbox.Role: Int] = [.inbox: 0, .drafts: 1, .sent: 2, .junk: 3, .trash: 4,
                                         .archive: 5]
        out.sort { a, b in
            let ra = a.role.flatMap { rank[$0] } ?? 100
            let rb = b.role.flatMap { rank[$0] } ?? 100
            if ra != rb { return ra < rb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return out
    }

    func testWithNoLabelsThePaneIsAsItWasRowForRow() {
        let listed = Self.listings(Self.noLabelsList)
        let pane = FolderTree.mailboxes(from: listed, unread: Self.noLabelsUnread, locale: english)
        XCTAssertEqual(pane, Self.asBefore(listed, unread: Self.noLabelsUnread))
        XCTAssertEqual(pane, [
            Mailbox(id: "INBOX", name: "INBOX", unreadCount: 13, role: .inbox, depth: 0),
            Mailbox(id: "[Gmail]/Drafts", name: "Drafts", unreadCount: 0, role: .drafts, depth: 1),
            Mailbox(id: "[Gmail]/Sent Mail", name: "Sent Mail", unreadCount: 11, role: .sent,
                    depth: 1),
            Mailbox(id: "[Gmail]/Spam", name: "Spam", unreadCount: 0, role: .junk, depth: 1),
            Mailbox(id: "[Gmail]/Trash", name: "Trash", unreadCount: 165, role: .trash, depth: 1),
            Mailbox(id: "[Gmail]/All Mail", name: "All Mail", unreadCount: 13, role: .archive,
                    depth: 1),
            Mailbox(id: "[Gmail]/Important", name: "Important", unreadCount: 1, role: nil, depth: 1),
            Mailbox(id: "[Gmail]/Starred", name: "Starred", unreadCount: 0, role: nil, depth: 1),
        ])
        // In any order LIST gives them.
        XCTAssertEqual(FolderTree.mailboxes(from: Array(listed.reversed()),
                                            unread: Self.noLabelsUnread, locale: english), pane)
    }

    /// The scripted server's account, which has no Important and no labels,
    /// as the shipping repository lists it, against the order before.
    func testTheScriptedAccountIsListedAsItWas() async throws {
        let server = ScriptedIMAPServer()
        let repository = makeRepository(server)
        let pane = try await repository.listMailboxes()
        let lines = [#"* LIST (\HasNoChildren) "/" "INBOX""#,
                     #"* LIST (\HasChildren \Noselect) "/" "[Gmail]""#,
                     #"* LIST (\All \HasNoChildren) "/" "[Gmail]/All Mail""#,
                     #"* LIST (\Drafts \HasNoChildren) "/" "[Gmail]/Drafts""#,
                     #"* LIST (\HasNoChildren \Sent) "/" "[Gmail]/Sent Mail""#,
                     #"* LIST (\HasNoChildren \Junk) "/" "[Gmail]/Spam""#,
                     #"* LIST (\Flagged \HasNoChildren) "/" "[Gmail]/Starred""#,
                     #"* LIST (\HasNoChildren \Trash) "/" "[Gmail]/Trash""#]
        let counts = Dictionary(uniqueKeysWithValues: pane.map { ($0.id, $0.unreadCount) })
        XCTAssertEqual(pane, Self.asBefore(Self.listings(lines), unread: counts))
        XCTAssertEqual(server.violations, [])
    }

    // MARK: - A role from the flags alone

    func testNoLabelIsTakenForARoleByItsName() {
        let pane = FolderTree.mailboxes(from: Self.listings(Self.testAccountsList), unread: [:],
                                        locale: english)
        let roles = pane.filter { $0.role != nil }.map { "\($0.id) \($0.role!)" }
        XCTAssertEqual(roles, ["INBOX inbox", "[Gmail]/Drafts drafts", "[Gmail]/Sent Mail sent",
                               "[Gmail]/Spam junk", "[Gmail]/Trash trash",
                               "[Gmail]/All Mail archive"])
        for id in ["Drafts", "[Gmail]Drafts", "[Gmail]/Sent Messages", "Junk E-mail",
                   "Junk E-mail/Drafts", "Deleted Messages", "[Gmail]Spam", "[Gmail]Trash",
                   "[Gmail]All Mail"] {
            XCTAssertNil(Mailbox.Role(word: id), id)
        }
        // The app's own words, and INBOX however it is spelt.
        XCTAssertEqual(Mailbox.Role(word: "drafts"), .drafts)
        XCTAssertEqual(Mailbox.Role(word: "trash"), .trash)
        XCTAssertEqual(Mailbox.Role(word: "inbox"), .inbox)
        XCTAssertEqual(Mailbox.Role(word: "INBOX"), .inbox)
    }

    /// A label "Drafts" these folders do not hold, as before a sweep has
    /// listed it, is in none of them: not in Gmail's Drafts, by its name.
    func testALabelsIdIsNeverMatchedToARoleFolderByItsName() {
        let folders = FolderTree.mailboxes(from: Self.listings(Self.noLabelsList), unread: [:],
                                           locale: english)
        XCTAssertNil(folders.firstIndex(matchingMailboxID: "Drafts"))
        XCTAssertNil(folders.role(of: "Drafts"))
        XCTAssertNil(folders.role(of: "Junk E-mail/Drafts"))
        // The app's own word still finds the folder playing it.
        XCTAssertEqual(folders.firstIndex(matchingMailboxID: "drafts"), 1)
        XCTAssertEqual(folders.role(of: "drafts"), .drafts)
        XCTAssertEqual(folders.firstIndex(matchingMailboxID: "inbox"), 0)
        // Listed, the label is itself, and has no role.
        let all = FolderTree.mailboxes(from: Self.listings(Self.testAccountsList), unread: [:],
                                       locale: english)
        XCTAssertEqual(all.firstIndex(matchingMailboxID: "Drafts").map { all[$0].id }, "Drafts")
        XCTAssertNil(all.role(of: "Drafts"))
    }

    func testALabelsNameIsTheFolderTheRepositoryOpens() {
        let listed = Self.listings(Self.testAccountsList)
        let roles: [Mailbox.Role: String] = [.inbox: "INBOX", .drafts: "[Gmail]/Drafts",
                                             .sent: "[Gmail]/Sent Mail", .junk: "[Gmail]/Spam",
                                             .trash: "[Gmail]/Trash", .archive: "[Gmail]/All Mail"]
        for id in ["Drafts", "Junk E-mail/Drafts", "[Gmail]Drafts", "[Gmail]/Sent Messages",
                   "Deleted Messages", "Junk E-mail", "Unopened 4/17/17"] {
            XCTAssertEqual(IMAPMailRepository.serverName(for: id, listed: listed, roles: roles), id)
        }
        // Not listed either: passed through, never a role's folder.
        XCTAssertEqual(IMAPMailRepository.serverName(for: "Drafts",
                                                     listed: Self.listings(Self.noLabelsList),
                                                     roles: roles), "Drafts")
        // The app's own words.
        XCTAssertEqual(IMAPMailRepository.serverName(for: "drafts", listed: listed, roles: roles),
                       "[Gmail]/Drafts")
        XCTAssertEqual(IMAPMailRepository.serverName(for: "inbox", listed: listed, roles: roles),
                       "INBOX")
        XCTAssertEqual(IMAPMailRepository.serverName(for: "inbox", listed: [], roles: [:]), "INBOX")
        // A folder LIST names is that folder, whatever the roles say.
        XCTAssertEqual(IMAPMailRepository.serverName(for: "INBOX", listed: listed,
                                                     roles: [.inbox: "[Gmail]/All Mail"]), "INBOX")
    }

    // MARK: - Over the wire

    /// The test account's folders on the scripted server, beside its own.
    private func testAccountsServer() -> ScriptedIMAPServer {
        let server = ScriptedIMAPServer()
        let known: Set<String> = [Server.inbox, "[Gmail]", Server.allMail, Server.drafts,
                                  Server.sent, Server.spam, Server.starred, Server.trash]
        var validity: UInt32 = 700_000
        for l in Self.listings(Self.testAccountsList) where !known.contains(l.name) {
            validity += 1
            let label = l.attributes.contains("\\Important") ? "\\Important" : l.name
            server.addFolder(l.name, attributes: l.attributes, label: label, validity: validity,
                             firstUID: 10, selectable: l.isSelectable)
        }
        return server
    }

    private func makeRepository(_ server: ScriptedIMAPServer) -> IMAPMailRepository {
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        return IMAPMailRepository(account: server.account, password: server.password,
                                  transport: server.transportFactory,
                                  recipients: RecipientBook(defaults: defaults),
                                  shelf: keptShelf(for: server.account))
    }

    /// The pane the repository gives, the names alone and after a sweep, and
    /// the copy kept on the iPad for the next launch's first frame: the same
    /// rows in the same order, with the counts the sweep gave.
    func testTheRepositoryListsTheTestAccountInThePanesOrderAndKeepsIt() async throws {
        let server = testAccountsServer()
        let repository = makeRepository(server)

        let names = try await repository.folders()
        XCTAssertEqual(names.map(Row.init), Self.testAccountsPane,
                       "\n" + names.map(Row.init).map(\.description).joined(separator: "\n"))

        let swept = try await repository.listMailboxes()
        XCTAssertEqual(swept.map(Row.init), Self.testAccountsPane)
        XCTAssertEqual(swept.first?.unreadCount, 6, "the Inbox's count")
        // No count asked for a folder that cannot be opened.
        let statuses = server.log.filter { $0.verb == "STATUS" }.map(\.command)
        XCTAssertEqual(statuses.count, 34)
        XCTAssertFalse(statuses.contains { $0.hasPrefix("STATUS \"Unopened 4\" ")
                                           || $0.hasPrefix("STATUS \"Unopened 4/17\" ") })

        // The kept copy, read back as the next launch reads it.
        let kept = try XCTUnwrap(keptShelf(for: server.account).folders)
        XCTAssertEqual(kept, swept)
        // Its blocks: the Inbox alone, then the rest in this order.
        var counts = FolderCounts()
        counts.take(kept)
        XCTAssertEqual(counts.blocks(outbox: 0).map { $0.map(\.id) },
                       [["INBOX"], Self.testAccountsPane.dropFirst().map(\.id)])
        XCTAssertEqual(server.violations, [])
    }

    /// A tap on each folder that has a role's name, or is inside one, opens
    /// that folder and nothing else; Gmail's Drafts opens as before; and a
    /// letter moved to the label "Drafts" goes there.
    func testATapOnALabelWithARolesNameOpensThatLabel() async throws {
        let server = testAccountsServer()
        let repository = makeRepository(server)
        _ = try await repository.listMailboxes()

        // Gmail's Drafts by the app's word first, then the label of that
        // name: taken for the role, it would find Gmail's Drafts open
        // already and SELECT nothing.
        for id in ["drafts", "Drafts", "Junk E-mail/Drafts", "[Gmail]Drafts",
                   "[Gmail]/Sent Messages", "[Gmail]/Starred", "Deleted Messages",
                   "Unopened 4/17/17", "[Gmail]/Drafts"] {
            let before = server.log.count
            _ = try await repository.listMessages(in: id, beforeUID: nil, limit: 10)
            let selected = server.log.dropFirst(before).filter { $0.verb == "SELECT" }.map(\.command)
            let expected = id == "drafts" ? "[Gmail]/Drafts" : id
            XCTAssertEqual(selected, ["SELECT \"\(expected)\""], id)
        }

        let inbox = try await repository.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        let letter = try XCTUnwrap(inbox.first)
        let draftsBefore = server.uids(in: Server.drafts).count
        try await repository.move(letter, to: "Drafts")
        XCTAssertEqual(server.uids(in: "Drafts").count, 1, "in the label")
        XCTAssertEqual(server.uids(in: Server.drafts).count, draftsBefore, "not in Gmail's Drafts")
        let moves = server.log.filter { ["UID MOVE", "UID COPY"].contains($0.verb) }.map(\.command)
        XCTAssertFalse(moves.isEmpty)
        for move in moves { XCTAssertTrue(move.hasSuffix(" \"Drafts\""), move) }
        XCTAssertEqual(server.violations, [])
    }

    /// The kept folder list names the folder a row's id stands for by the
    /// same rule: the label "Drafts" kept is itself; a label not kept is
    /// passed through, not taken for Gmail's Drafts.
    func testTheKeptCopyNamesALabelByItsOwnName() async throws {
        let server = testAccountsServer()
        let repository = makeRepository(server)
        _ = try await repository.listMailboxes()
        let shelf = keptShelf(for: server.account)
        XCTAssertEqual(shelf.folderName(for: "Drafts"), "Drafts")
        XCTAssertEqual(shelf.folderName(for: "drafts"), "[Gmail]/Drafts")
        XCTAssertEqual(shelf.folderName(for: "inbox"), "INBOX")

        let plain = ScriptedIMAPServer(username: "other@example.com")
        let other = makeRepository(plain)
        _ = try await other.listMailboxes()
        XCTAssertEqual(keptShelf(for: plain.account).folderName(for: "Drafts"), "Drafts")
        XCTAssertEqual(server.violations, [])
        XCTAssertEqual(plain.violations, [])
    }
}
