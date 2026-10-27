import XCTest
@testable import Blackmail

/// Mail's options in Blackmail's Settings (B-167): the parts of iPadOS 18's
/// Settings > Apps > Mail that Blackmail follows, in Mail's order and words,
/// each kept in one place (`MailOptions`) at Mail's factory value, which
/// leaves the app as it was, and read where the app read it before; the
/// rows Blackmail does not have greyed with what it does instead; and
/// Mail's Archive in the Trash's place, in a drag, the Edit bar and the
/// reading pane, where the account discards into the Archive.
///
/// The values, the words, the page and the rules are run here. Settings,
/// the list and the pane are UIKit and built only for the device, so how
/// they use them is read from their source, comment lines out, as
/// `EditBarTests` reads it.
final class MailOptionsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        forget()
    }

    override func tearDown() {
        forget()
        super.tearDown()
    }

    /// Every value as never set.
    private func forget() {
        for option in MailOptions.Option.allCases {
            UserDefaults.standard.removeObject(forKey: option.key)
        }
    }

    private func letter(_ id: String, in mailbox: String) -> MessageSummary {
        MessageSummary(id: id, mailboxID: mailbox, sender: "Sam Example <sam@example.com>",
                       subject: "Lunch on Sunday", preview: "", date: ScriptedIMAPServer.newestDate,
                       isRead: false, isFlagged: false)
    }

    private let allMail = Mailbox(id: "[Gmail]/All Mail", name: "All Mail", unreadCount: 0,
                                  role: .archive)

    private var archiving: SwipeOptions {
        SwipeOptions(swipeLeft: .flag, swipeRight: .mark, discardInto: .archive)
    }

    // MARK: - Mail's factory values

    /// Never set, each is Mail's from the factory, and the app reads what it
    /// read before B-167: Swipe Left Flag, Swipe Right Mark as Read, the
    /// Trash for what he discards, View Next Message, Organize by Thread and
    /// Complete Threads on, and pictures from the web loading.
    func testEveryValueIsMailsFromTheFactoryAndTheAppIsAsItWas() {
        XCTAssertEqual(MailOptions.previewLines, 2)
        XCTAssertFalse(MailOptions.showToCcLabels)
        XCTAssertEqual(MailOptions.swipeLeft, .flag)
        XCTAssertEqual(MailOptions.swipeRight, .mark)
        XCTAssertEqual(MailOptions.deleteOrMoveMessageAction, .viewNextMessage)
        XCTAssertFalse(MailOptions.askBeforeDeleting)
        XCTAssertFalse(MailOptions.blockAllRemoteContent)
        XCTAssertTrue(MailOptions.loadRemoteImages)
        XCTAssertTrue(MailOptions.organizeByThread)
        XCTAssertTrue(MailOptions.collapseReadMessages)
        XCTAssertFalse(MailOptions.mostRecentMessageOnTop)
        XCTAssertTrue(MailOptions.completeThreads)
        XCTAssertEqual(MailOptions.moveDiscardedMessagesInto, .trash)

        XCTAssertEqual(SwipeOptions.his, SwipeOptions.factory)
        XCTAssertEqual(NextLetter.action, .viewNextMessage)
        XCTAssertTrue(ConversationSettings.organizeByThread)
        XCTAssertTrue(ConversationSettings.completeThreads)
        XCTAssertEqual(EditBar.deleteTitle(inFolderWithRole: .inbox, canArchive: true), "Trash")
        XCTAssertNil(SwipeOptions.his.archive(fromFolderWithRole: .inbox, into: allMail))
        let inbox = [letter("1/1", in: "INBOX"), letter("1/2", in: "INBOX")]
        let discard = EditBar.discarding(inbox, role: { _ in .inbox }, allMail: allMail)
        XCTAssertEqual(discard.archived, [])
        XCTAssertEqual(discard.deleted, inbox)
    }

    // MARK: - Mail's page

    /// The parts in the order of Settings > Apps > Mail, the account's Move
    /// Discarded Messages Into first, as Mail Accounts is above Message
    /// List; their rows in Mail's order and words; Swipe Options and Privacy
    /// Protection pages of their own; every option on the page once.
    func testThePageIsMailsInItsOrderAndWords() throws {
        let page = MailOptions.page
        XCTAssertEqual(page.map(\.heading), ["Move Discarded Messages Into:", "Message List",
                                             "Messages", "Threading"])
        XCTAssertEqual(page[0].rows, [.values(.moveDiscardedMessagesInto)])
        XCTAssertEqual(page[0].footer, "In Mail: Mail Accounts > Gmail > Account > Advanced.")
        XCTAssertEqual(page[1].rows, [
            .option(.preview), .option(.showToCcLabels),
            .page("Swipe Options", [MailOptions.Section(heading: nil, rows: [.option(.swipeLeft),
                                                                           .option(.swipeRight)])]),
            .option(.deleteOrMoveMessageAction),
        ])
        XCTAssertEqual(page[2].rows, [
            .option(.askBeforeDeleting),
            .page("Privacy Protection",
                  [MailOptions.Section(heading: nil, rows: [.option(.blockAllRemoteContent)],
                                       footer: "In Mail, shown when Protect Mail Activity is "
                                           + "off. Blackmail never loads pictures through Apple.")]),
        ])
        XCTAssertEqual(page[3].rows, [.option(.organizeByThread), .option(.collapseReadMessages),
                                      .option(.mostRecentMessageOnTop), .option(.completeThreads)])
        XCTAssertEqual(MailOptions.options(on: page), [
            .moveDiscardedMessagesInto, .preview, .showToCcLabels, .swipeLeft, .swipeRight,
            .deleteOrMoveMessageAction, .askBeforeDeleting, .blockAllRemoteContent,
            .organizeByThread, .collapseReadMessages, .mostRecentMessageOnTop, .completeThreads,
        ])
        XCTAssertEqual(Set(MailOptions.options(on: page)), Set(MailOptions.Option.allCases))

        XCTAssertEqual(MailOptions.Option.allCases.map(\.title), [
            "Move Discarded Messages Into", "Preview", "Show To/Cc Labels", "Swipe Left",
            "Swipe Right", "Delete or Move Message Action", "Ask Before Deleting",
            "Block All Remote Content", "Organize by Thread", "Collapse Read Messages",
            "Most Recent Message on Top", "Complete Threads",
        ])
        XCTAssertEqual(MailOptions.Option.moveDiscardedMessagesInto.choices,
                       ["Deleted Mailbox", "Archive Mailbox"])
        XCTAssertEqual(MailOptions.Option.preview.choices,
                       ["None", "1 Line", "2 Lines", "3 Lines", "4 Lines", "5 Lines"])
        for side in [MailOptions.Option.swipeLeft, .swipeRight] {
            XCTAssertEqual(side.choices, ["None", "Mark as Read", "Flag", "Move Message", "Archive"])
        }
        XCTAssertEqual(MailOptions.Option.deleteOrMoveMessageAction.choices,
                       ["View Next Message", "Don’t Select a Message"])
        let switches = MailOptions.Option.allCases.filter(\.isSwitch)
        XCTAssertEqual(switches, [.showToCcLabels, .askBeforeDeleting, .blockAllRemoteContent,
                                  .organizeByThread, .collapseReadMessages,
                                  .mostRecentMessageOnTop, .completeThreads])
        XCTAssertEqual(switches.filter(\.factoryOn), [.organizeByThread, .collapseReadMessages,
                                                      .completeThreads])
        XCTAssertEqual(MailOptions.Option.preview.value, "2 Lines")
        XCTAssertEqual(MailOptions.Option.swipeLeft.value, "Flag")
        XCTAssertEqual(MailOptions.Option.swipeRight.value, "Mark as Read")
        XCTAssertEqual(MailOptions.Option.deleteOrMoveMessageAction.value, "View Next Message")
        XCTAssertEqual(MailOptions.Option.moveDiscardedMessagesInto.value, "Deleted Mailbox")
        XCTAssertNil(MailOptions.Option.organizeByThread.value)
        XCTAssertEqual(MailOptions.valuesPage(of: .preview),
                       [MailOptions.Section(heading: nil, rows: [.values(.preview)])])
    }

    // MARK: - One place each

    /// Each row is kept in one place, under its own key, Organize by Thread,
    /// Complete Threads and Delete or Move Message Action under the keys
    /// they had, so a value set before B-167 stays, and Ask Before Deleting
    /// and Block All Remote Content under B-168's; and what a row sets is
    /// what the app reads, where it read it before.
    func testEachRowIsKeptInOnePlaceAndReadWhereTheAppReadsIt() {
        let keys = MailOptions.Option.allCases.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(MailOptions.Option.organizeByThread.key, "blackmail.organizeByThread")
        XCTAssertEqual(MailOptions.Option.completeThreads.key, "blackmail.completeThreads")
        XCTAssertEqual(MailOptions.Option.deleteOrMoveMessageAction.key,
                       "blackmail.deleteOrMoveMessageAction")
        XCTAssertEqual(ConversationSettings.key, MailOptions.Option.organizeByThread.key)
        XCTAssertEqual(ConversationSettings.completeThreadsKey, MailOptions.Option.completeThreads.key)
        XCTAssertEqual(NextLetter.key, MailOptions.Option.deleteOrMoveMessageAction.key)
        XCTAssertEqual(MailOptions.Option.askBeforeDeleting.key, "blackmail.askBeforeDeleting")
        XCTAssertEqual(MailOptions.Option.blockAllRemoteContent.key,
                       "blackmail.blockAllRemoteContent")
        XCTAssertEqual(MailOptions.Option.swipeLeft.key, "blackmail.mail.swipeLeft")

        // Set by the rows, as Settings sets them.
        MailOptions.Option.swipeLeft.chosen = 0
        MailOptions.Option.swipeRight.chosen = 3
        MailOptions.Option.moveDiscardedMessagesInto.chosen = 1
        MailOptions.Option.deleteOrMoveMessageAction.chosen = 1
        MailOptions.Option.organizeByThread.isOn = false
        MailOptions.Option.completeThreads.isOn = false
        XCTAssertEqual(SwipeOptions.his, SwipeOptions(swipeLeft: .none, swipeRight: .move,
                                                      discardInto: .archive))
        XCTAssertEqual(NextLetter.action, .dontSelectAMessage)
        XCTAssertFalse(ConversationSettings.organizeByThread)
        XCTAssertFalse(ConversationSettings.completeThreads)
        XCTAssertEqual(UserDefaults.standard.string(forKey: NextLetter.key), "dontSelectAMessage")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "blackmail.mail.swipeRight"), "move")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "blackmail.mail.moveDiscardedMessagesInto"),
                       "archive")
        XCTAssertEqual(MailOptions.Option.swipeRight.value, "Move Message")
        XCTAssertEqual(MailOptions.Option.moveDiscardedMessagesInto.value, "Archive Mailbox")
        XCTAssertEqual(MailOptions.Option.deleteOrMoveMessageAction.value, "Don’t Select a Message")

        // Read by the app where it read them: the drags, More, the Edit bar.
        let row = RowSwipes.Row(read: true, flagged: false, role: .inbox, onThisIPadOnly: false,
                                canArchive: true)
        XCTAssertEqual(RowSwipes.sides(for: row, editing: false),
                       RowSwipes.Sides(left: [.archive, .more], right: [.move]))
        XCTAssertEqual(RowMore.items(for: row)[3], .archiveMessage)
        XCTAssertEqual(EditBar.deleteTitle(inFolderWithRole: .inbox, canArchive: true), "Archive")

        // Set back, through the readers' own setters.
        NextLetter.action = .viewNextMessage
        ConversationSettings.organizeByThread = true
        XCTAssertEqual(MailOptions.deleteOrMoveMessageAction, .viewNextMessage)
        XCTAssertTrue(MailOptions.organizeByThread)

        // A place out of range sets nothing; a value this build does not
        // know is the factory's.
        MailOptions.Option.swipeLeft.chosen = 9
        XCTAssertEqual(MailOptions.swipeLeft, .none)
        UserDefaults.standard.set("sideways", forKey: MailOptions.Option.swipeLeft.key)
        XCTAssertEqual(MailOptions.swipeLeft, .flag)
        UserDefaults.standard.set(7, forKey: MailOptions.Option.preview.key)
        XCTAssertEqual(MailOptions.previewLines, 2)
        MailOptions.Option.preview.chosen = 0
        XCTAssertEqual(MailOptions.previewLines, 0)
        XCTAssertEqual(MailOptions.Option.preview.value, "None")
        UserDefaults.standard.set(false, forKey: MailOptions.Option.collapseReadMessages.key)
        XCTAssertFalse(MailOptions.collapseReadMessages, "an explicit off is not the factory's on")
        MailOptions.blockAllRemoteContent = true
        XCTAssertFalse(MailOptions.loadRemoteImages)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "blackmail.blockAllRemoteContent") as? Bool,
                       true)
    }

    // MARK: - What Blackmail has

    /// The rows Blackmail has every value of set what they say; the rest
    /// are greyed, with what Blackmail does in their place. Ask Before
    /// Deleting and Block All Remote Content live since B-168's merge, each
    /// row setting the value its reader reads (int19).
    func testRowsBlackmailDoesNotHaveAreGreyedWithWhatItDoesInstead() {
        XCTAssertEqual(MailOptions.built, [.moveDiscardedMessagesInto, .swipeLeft, .swipeRight,
                                           .deleteOrMoveMessageAction, .askBeforeDeleting,
                                           .blockAllRemoteContent, .organizeByThread,
                                           .completeThreads])
        XCTAssertNil(MailOptions.Option.askBeforeDeleting.instead)
        XCTAssertNil(MailOptions.Option.blockAllRemoteContent.instead)
        let ask = MailOptions.Option.askBeforeDeleting
        let block = MailOptions.Option.blockAllRemoteContent
        defer {
            UserDefaults.standard.removeObject(forKey: ask.key)
            UserDefaults.standard.removeObject(forKey: block.key)
        }
        ask.isOn = true
        XCTAssertEqual(DiscardQuestion.before(.trash, letters: 1, from: .pane)?.button, "Trash Message")
        ask.isOn = false
        XCTAssertNil(DiscardQuestion.before(.trash, letters: 1, from: .pane))
        block.isOn = true
        XCTAssertTrue(RemotePictures().listOn())
        block.isOn = false
        XCTAssertFalse(RemotePictures().listOn())
        for option in MailOptions.Option.allCases {
            XCTAssertEqual(option.instead == nil, MailOptions.built.contains(option), "\(option)")
        }
        XCTAssertEqual(MailOptions.Option.preview.instead, "Blackmail always shows 2 lines.")
        XCTAssertEqual(MailOptions.Option.mostRecentMessageOnTop.instead,
                       "Blackmail always puts the newest letter of a conversation at the bottom.")
        XCTAssertEqual(MailOptions.Option.collapseReadMessages.instead,
                       "Blackmail always closes the letters you have read in a conversation.")
    }

    // MARK: - Mail's Archive

    /// Where the account discards into the Archive, a letter of any folder
    /// but Trash, All Mail, Drafts and the Outbox is archived, by a drag,
    /// More, the Edit bar or the pane, where there is an All Mail; Delete
    /// inside Trash still erases, and anywhere else, or with no All Mail, it
    /// goes to the Trash, as with Deleted Mailbox everywhere.
    func testTheArchiveTakesTheTrashsPlaceWhereTheAccountDiscardsIntoIt() {
        let trashing = SwipeOptions.factory
        for role: Mailbox.Role? in [.inbox, .sent, .junk, nil] {
            XCTAssertEqual(archiving.discard(fromFolderWithRole: role, canArchive: true), .archive)
            XCTAssertEqual(archiving.discard(fromFolderWithRole: role, canArchive: false), .trash)
            XCTAssertEqual(trashing.discard(fromFolderWithRole: role, canArchive: true), .trash)
            XCTAssertEqual(archiving.archive(fromFolderWithRole: role, into: allMail), allMail)
            XCTAssertNil(archiving.archive(fromFolderWithRole: role, into: nil))
            XCTAssertNil(trashing.archive(fromFolderWithRole: role, into: allMail))
            XCTAssertEqual(EditBar.deleteTitle(inFolderWithRole: role, canArchive: true,
                                               options: archiving), "Archive")
            XCTAssertEqual(EditBar.deleteTitle(inFolderWithRole: role, canArchive: false,
                                               options: archiving), "Trash")
        }
        for role: Mailbox.Role in [.drafts, .outbox] {
            XCTAssertEqual(archiving.discard(fromFolderWithRole: role, canArchive: true), .trash)
            XCTAssertNil(archiving.archive(fromFolderWithRole: role, into: allMail))
            XCTAssertEqual(EditBar.deleteTitle(inFolderWithRole: role, canArchive: true,
                                               options: archiving), "Trash")
        }
        XCTAssertEqual(archiving.discard(fromFolderWithRole: .trash, canArchive: true), .delete)
        XCTAssertEqual(EditBar.deleteTitle(inFolderWithRole: .trash, canArchive: true,
                                           options: archiving), "Delete")
        XCTAssertNil(archiving.archive(fromFolderWithRole: .trash, into: allMail))
        XCTAssertNil(archiving.archive(fromFolderWithRole: .archive, into: allMail))
        XCTAssertEqual(RowSwipes.Action.archive.title, "Archive")

        // A drag on a draft's row in Drafts: the Trash, as the Edit bar there.
        let draft = RowSwipes.Row(read: true, flagged: false, role: .drafts, onThisIPadOnly: false,
                                  canArchive: true)
        XCTAssertEqual(RowSwipes.sides(for: draft, editing: false, options: archiving).left.first,
                       .trash)

        // The Edit bar's tap, letter by letter, by each one's own folder: an
        // All Mailboxes search's hits from Spam archived, from All Mail to
        // the Trash, from Trash erased by Delete after the question.
        let folders: [String: Mailbox.Role] = ["INBOX": .inbox, "[Gmail]/Spam": .junk,
                                               "[Gmail]/All Mail": .archive,
                                               "[Gmail]/Trash": .trash]
        let inbox = letter("1/1", in: "INBOX")
        let spam = letter("2/1", in: "[Gmail]/Spam")
        let all = letter("3/1", in: "[Gmail]/All Mail")
        let bin = letter("4/1", in: "[Gmail]/Trash")
        let split = EditBar.discarding([inbox, spam, all, bin], role: { folders[$0] },
                                       allMail: allMail, options: archiving)
        XCTAssertEqual(split.archived, [inbox, spam])
        XCTAssertEqual(split.deleted, [all, bin])
        let none = EditBar.discarding([inbox, spam], role: { folders[$0] }, allMail: nil,
                                      options: archiving)
        XCTAssertEqual(none.archived, [])
        XCTAssertEqual(none.deleted, [inbox, spam])
    }

    /// A Swipe Left or Swipe Right set to Archive goes by the discard's rule
    /// (`SwipeOptions.archives`): no Archive on a row in Drafts or Trash,
    /// whichever Move Discarded Messages Into says, so a drag there neither
    /// files a draft in All Mail nor takes a letter out of Trash; in the
    /// Inbox, Junk or a folder of his own, Archive on both sides.
    func testASwipeSetToArchiveGoesByTheDiscardsRule() {
        func row(_ role: Mailbox.Role?) -> RowSwipes.Row {
            RowSwipes.Row(read: true, flagged: false, role: role, onThisIPadOnly: false,
                          canArchive: true)
        }
        for discard in SwipeOptions.Discard.allCases {
            let options = SwipeOptions(swipeLeft: .archive, swipeRight: .archive,
                                       discardInto: discard)
            XCTAssertEqual(RowSwipes.sides(for: row(.drafts), editing: false, options: options),
                           RowSwipes.Sides(left: [.trash, .more], right: []), "\(discard)")
            XCTAssertEqual(RowSwipes.sides(for: row(.trash), editing: false, options: options),
                           RowSwipes.Sides(left: [.delete, .more], right: []), "\(discard)")
            for role: Mailbox.Role? in [.inbox, .junk, nil] {
                let sides = RowSwipes.sides(for: row(role), editing: false, options: options)
                XCTAssertEqual(sides.right, [.archive], "\(discard) \(String(describing: role))")
                XCTAssertTrue(sides.left.contains(.archive))
            }
        }
        for role: Mailbox.Role in [.drafts, .outbox, .trash] {
            XCTAssertFalse(SwipeOptions.archives(role: role, canArchive: true))
            XCTAssertNil(RowSwipes.action(for: .archive, on: row(role)))
        }
        XCTAssertFalse(SwipeOptions.archives(role: .inbox, canArchive: false))
        XCTAssertTrue(SwipeOptions.archives(role: .inbox, canArchive: true))
    }

    /// Under "Archive", what the Edit bar asks before its tap counts only
    /// the letters it deletes: an All Mailboxes search with four hits from
    /// the Inbox and one from Trash archives the four and asks of the one
    /// alone; with a hit from All Mail too, which goes to the Trash, of
    /// both. With Deleted Mailbox, of all five, as before B-167.
    func testTheEditBarsQuestionCountsOnlyTheLettersItDeletes() {
        let folders: [String: Mailbox.Role] = ["INBOX": .inbox, "[Gmail]/All Mail": .archive,
                                               "[Gmail]/Trash": .trash]
        let mixed = (1...4).map { letter("1/\($0)", in: "INBOX") }
            + [letter("2/1", in: "[Gmail]/Trash")]
        let archived = EditBar.question(before: mixed, role: { folders[$0] }, allMail: allMail,
                                        options: archiving)
        XCTAssertEqual(archived?.title, "Delete Message?")
        XCTAssertEqual(archived?.message,
                       "This message will be deleted immediately. You can't undo this action.")
        let withAllMail = EditBar.question(before: mixed + [letter("3/1", in: "[Gmail]/All Mail")],
                                           role: { folders[$0] }, allMail: allMail,
                                           options: archiving)
        XCTAssertEqual(withAllMail?.title, "Delete 2 Messages?")
        XCTAssertEqual(withAllMail?.message, "1 of them is in the Trash and will be deleted "
                           + "immediately. You can't undo this action.")
        let trashed = EditBar.question(before: mixed, role: { folders[$0] }, allMail: allMail,
                                       options: .factory)
        XCTAssertEqual(trashed, EraseQuestion.before(deleting: mixed, role: { folders[$0] }))
        XCTAssertEqual(trashed?.title, "Delete 5 Messages?")
        XCTAssertNil(EditBar.question(before: Array(mixed.prefix(4)), role: { folders[$0] },
                                      allMail: allMail, options: archiving))
    }

    // MARK: - The wiring, read from the source

    /// Mail's part of Settings at the text size, as Mail's own Settings page
    /// follows it (B-166): its heading, its line, every row's title, value
    /// and line, and its chevrons and ticks, again when the size changes
    /// with Settings open. The rest of Settings keeps its sizes (B-166's
    /// "Not changed"). Integration, int19.
    func testMailsRowsFollowTheTextSize() throws {
        let view = try source("UI/MailOptionsView.swift")
        for line in [
            "restyles.keep { [weak label] in label?.font = .systemFont(ofSize: Theme.scaled(size)) }",
            "NotificationCenter.default.addObserver(self, selector: #selector(textSizeChanged), "
                + "name: TextSizes.didChange, object: nil)",
            "@objc private func textSizeChanged() { restyles.again() setNeedsLayout() }",
            "func restyle() { titleLabel.font = .systemFont(ofSize: Theme.scaled(17)) "
                + "valueLabel.font = .systemFont(ofSize: Theme.scaled(17)) mark.image = Theme.symbol(symbol) }",
        ] {
            XCTAssertTrue(view.contains(line), line)
        }
        XCTAssertEqual(view.components(separatedBy: "restyles.keep { [weak control] in control?.restyle() }")
                           .count - 1, 3, "every kind of row")
        XCTAssertFalse(view.contains(".systemFont(ofSize: 17)"))
        let settings = try source("UI/SettingsViewController.swift")
        for line in [
            "@objc private func sizeMailWords() { mailHeading.font = .systemFont(ofSize: Theme.scaled(18), "
                + "weight: .semibold) mailCaption.font = .systemFont(ofSize: Theme.scaled(14)) }",
            "self, selector: #selector(sizeMailWords), name: TextSizes.didChange, object: nil)",
        ] {
            XCTAssertTrue(settings.contains(line), line)
        }
    }

    /// Settings draws Mail's page under its password, before Bring Back,
    /// and draws it again on coming back from one of its pages; a row sets
    /// its value at once and says so; a greyed row takes no tap.
    func testSettingsDrawsMailsPageAndARowSetsItsValueAtOnce() throws {
        let settings = try source("UI/SettingsViewController.swift")
        inOrder(["stack.addArrangedSubview(statusLabel)",
                 "stack.addArrangedSubview(mailHeading) mailCaption.text = Self.mailCaption",
                 "mailOptions.onChange = { [weak self] option in if option == .organizeByThread { "
                    + "self?.onOrganizeByThreadChanged?() } } stack.addArrangedSubview(mailOptions)",
                 "stack.addArrangedSubview(bringBackButton)"], in: settings)
        XCTAssertTrue(settings.contains("override func viewWillAppear(_ animated: Bool) { "
                                        + "super.viewWillAppear(animated) mailOptions.redraw() }"))
        XCTAssertTrue(settings.contains("private static let mailCaption = \"As in Settings > "
                                        + "Apps > Mail. \" + \"Set them as they are set for Mail "
                                        + "on this iPad.\""))
        XCTAssertFalse(settings.contains("organizeSwitch"))
        XCTAssertFalse(settings.contains("completeSwitch"))

        let view = try source("UI/MailOptionsView.swift")
        for line in [
            "let live = MailOptions.built.contains(option) let toggle = UISwitch() "
                + "toggle.isOn = option.isOn toggle.isEnabled = live",
            "let control = OptionRow(title: option.title, value: option.value, opens: live, "
                + "live: live) control.isEnabled = live",
            "control.ticked = option.chosen == index control.isEnabled = live",
            "guard option.chosen != index else { return } option.chosen = index "
                + "self?.changed(option) self?.redraw()",
            "private func changed(_ option: MailOptions.Option) { onChange?(option) "
                + "NotificationCenter.default.post(name: MailOptions.changed, object: option) }",
            "host?.navigationController?.pushViewController(page, animated: true)",
            "guard let instead = option.instead else { return }",
        ] {
            XCTAssertTrue(view.contains(line), line)
        }
    }

    /// The pane's Delete archives into All Mail where the container says it
    /// does, with Delete's guards, and is drawn as Mail's Archive there,
    /// again when Settings changes it; the container says so by the role of
    /// the letter's own folder, as a drag on its row.
    func testThePanesDeleteArchivesWhereTheAccountDiscardsIntoTheArchive() throws {
        let pane = try source("UI/MessageDetailViewController.swift")
        for line in [
            "var archiveTarget: ((MessageSummary?) -> Mailbox?)?",
            "private var summary: MessageSummary? { didSet { drawDiscardButton() } }",
            "NotificationCenter.default.addObserver(self, selector: #selector(drawDiscardButton), "
                + "name: MailOptions.changed, object: nil)",
            "private var discardArchives = false",
            "@objc private func drawDiscardButton() { guard let item = actionItems[.delete] else { "
                + "return } let archives = archiveTarget?(summary) != nil guard archives != "
                + "discardArchives else { return } discardArchives = archives item.image = "
                + "Theme.symbol(archives ? \"archivebox\" : \"trash\") item.accessibilityLabel = "
                + "archives ? RowSwipes.Action.archive.title : \"Delete\" }",
            "let action = archiveTarget?(s).map { PaneAction.move(to: $0) } ?? .delete "
                + "showEmpty() Task { @MainActor in let refused = await self.performed(action, on: s)",
        ] {
            XCTAssertTrue(pane.contains(line), line)
        }
        let root = try source("UI/RootViewController.swift")
        XCTAssertTrue(root.contains(
            "detail.archiveTarget = { [weak self] letter in guard let self else { return nil } "
                + "let folders = [self.list.shownMailbox] + self.mailboxList.folders "
                + "let role = letter.map { folders.role(of: $0.mailboxID) } ?? "
                + "self.list.shownMailbox.role return SwipeOptions.his.archive(fromFolderWithRole: "
                + "role, into: self.mailboxList.mailbox(for: .archive)) }"))
        let swipes = try source("Mail/RowSwipes.swift")
        XCTAssertTrue(swipes.contains("static var his: SwipeOptions { SwipeOptions(swipeLeft: "
                                      + "MailOptions.swipeLeft, swipeRight: MailOptions.swipeRight, "
                                      + "discardInto: MailOptions.moveDiscardedMessagesInto) }"))
        XCTAssertTrue(swipes.contains("static func discard(for row: Row, options: SwipeOptions = "
                                      + ".his) -> Action { options.discard(fromFolderWithRole: "
                                      + "row.role, canArchive: row.canArchive) }"))
    }

    // MARK: - Reading the source

    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    /// Each of `steps` in `code`, in that order.
    private func inOrder(_ steps: [String], in code: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        var from = code.startIndex
        for step in steps {
            guard let found = code.range(of: step, range: from..<code.endIndex) else {
                XCTFail("not in order: \(step)", file: file, line: line)
                return
            }
            from = found.upperBound
        }
    }
}
