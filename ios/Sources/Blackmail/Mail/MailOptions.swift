import Foundation

/// Mail's options that no app can read off his iPad (B-167): the rows of
/// iPadOS 18's Settings > Apps > Mail that Blackmail follows, and his Gmail
/// account's Move Discarded Messages Into, each kept here and nowhere else.
///
/// The owner's ruling of 2026-10-26 (D-024): where what Mail does follows a
/// setting of his iPad, Mail's value from the factory until his own is
/// known, and his own cannot be read before the install. So each is a row of
/// Blackmail's Settings, laid out as Mail's page lays them out and in its
/// words (`page`), at Mail's factory value until it is set there, so that
/// whoever installs the app can set them to his from his Mail settings page
/// in two minutes.
///
/// Each value is read where the app read it before: Swipe Options and Move
/// Discarded Messages Into by `SwipeOptions.his`, Delete or Move Message
/// Action by `NextLetter.action`, Organize by Thread and Complete Threads by
/// `ConversationSettings`. Mail's factory values are what the app did before
/// B-167, but for Move Discarded Messages Into: see `moveDiscardedMessagesInto`.
///
/// Some of Mail's values Blackmail does not have (`built`). Their rows are
/// drawn greyed, at their value, with what Blackmail does in their place
/// (`Option.instead`), and set nothing. Ask Before Deleting and Privacy
/// Protection's Block All Remote Content are built by B-168, under the keys
/// its branch gave them, and kept here alone: `DiscardQuestion` reads the
/// first at each tap, `RemoteContent` and `RemotePictures` the second at
/// each thing the pane shows (int19; B-168's `MessagesOptions` folded in).
///
/// Foundation only, so the values, their words and the page's order are
/// tested on the Linux host; the rows are drawn by `MailOptionsView`.
enum MailOptions {

    /// Posted once a row of Settings has changed a value, the option as its
    /// object: the reading pane draws its Delete again by it.
    static let changed = Notification.Name("blackmail.mailOptionChanged")

    // MARK: - The values

    /// Message List > Preview: how many lines of each letter's words a row
    /// shows, 0 for None. Mail's is 2, and Blackmail's rows show 2 whatever
    /// this says (`built`).
    static var previewLines: Int {
        get {
            (defaults.object(forKey: Option.preview.key) as? Int)
                .flatMap { (0...5).contains($0) ? $0 : nil } ?? 2
        }
        set { defaults.set(newValue, forKey: Option.preview.key) }
    }

    /// Message List > Show To/Cc Labels. Off from the factory; not built.
    static var showToCcLabels: Bool {
        get { Option.showToCcLabels.isOn }
        set { Option.showToCcLabels.isOn = newValue }
    }

    /// Message List > Swipe Options > Swipe Left. Flag from the factory.
    static var swipeLeft: SwipeOptions.Choice {
        get { stored(.swipeLeft) ?? .flag }
        set { defaults.set(newValue.rawValue, forKey: Option.swipeLeft.key) }
    }

    /// Message List > Swipe Options > Swipe Right. Mark as Read from the
    /// factory.
    static var swipeRight: SwipeOptions.Choice {
        get { stored(.swipeRight) ?? .mark }
        set { defaults.set(newValue.rawValue, forKey: Option.swipeRight.key) }
    }

    /// Message List > Delete or Move Message Action, since iOS 18.4. View
    /// Next Message from the factory. Under the key B-158 kept it in, and
    /// in its words, so a value written before B-167 stays his.
    static var deleteOrMoveMessageAction: NextLetter.Action {
        get { stored(.deleteOrMoveMessageAction) ?? .viewNextMessage }
        set { defaults.set(newValue.rawValue, forKey: Option.deleteOrMoveMessageAction.key) }
    }

    /// Messages > Ask Before Deleting. Off from the factory. Built by B-168:
    /// on, a Trash or an Archive of a letter asks first, with Mail's words,
    /// but for a full drag on a row, which goes at once (`DiscardQuestion`).
    /// Off by third-party guides; Apple's own guide, telling how to turn it
    /// off, reads as if it were on, and his is matched on the day whichever
    /// it is. The question before an erase inside Trash (`EraseQuestion`) is
    /// asked whatever this says, as it always was.
    static var askBeforeDeleting: Bool {
        get { Option.askBeforeDeleting.isOn }
        set { Option.askBeforeDeleting.isOn = newValue }
    }

    /// Messages > Privacy Protection > Block All Remote Content, which Mail
    /// shows once Protect Mail Activity is off. Off from the factory, and
    /// off there until it is turned on, whichever way Mail's first launch
    /// was answered. Protect Mail Activity itself is not kept: Blackmail
    /// cannot load a picture through Apple whatever it says, and with it
    /// on, or with this off, pictures from the web show, in Mail as here
    /// (the copy-Mail decisions, item 7386). Built by B-168: on, a letter's
    /// pictures and the rest of its content from the web are not loaded,
    /// the line "Message contains unloaded images." over the letter and
    /// "Load All Images" on it (`RemoteContent`).
    static var blockAllRemoteContent: Bool {
        get { Option.blockAllRemoteContent.isOn }
        set { Option.blockAllRemoteContent.isOn = newValue }
    }

    /// Whether a letter's pictures from the web load, as Mail's Load Remote
    /// Images said before iOS 15: unless Block All Remote Content is on
    /// (item 7386's case D), for a reader that asks the other way round.
    static var loadRemoteImages: Bool { !blockAllRemoteContent }

    /// Threading > Organize by Thread. On from the factory, under the key it
    /// always had (`ConversationSettings`).
    static var organizeByThread: Bool {
        get { Option.organizeByThread.isOn }
        set { Option.organizeByThread.isOn = newValue }
    }

    /// Threading > Collapse Read Messages. On from the factory, as
    /// Blackmail's conversations are always drawn (B-074); not built.
    static var collapseReadMessages: Bool {
        get { Option.collapseReadMessages.isOn }
        set { Option.collapseReadMessages.isOn = newValue }
    }

    /// Threading > Most Recent Message on Top. Off from the factory, as
    /// Blackmail's conversations are always drawn (B-074); not built.
    static var mostRecentMessageOnTop: Bool {
        get { Option.mostRecentMessageOnTop.isOn }
        set { Option.mostRecentMessageOnTop.isOn = newValue }
    }

    /// Threading > Complete Threads. On from the factory, under the key it
    /// always had (`ConversationSettings`, B-104).
    static var completeThreads: Bool {
        get { Option.completeThreads.isOn }
        set { Option.completeThreads.isOn = newValue }
    }

    /// The Gmail account's Advanced > Move Discarded Messages Into: Deleted
    /// Mailbox, the Trash, or Archive Mailbox, All Mail.
    ///
    /// Deleted Mailbox until set, which is what Blackmail's Delete has always
    /// done. Mail's own for a Gmail account added as Google is said to be
    /// Archive Mailbox (the copy-Mail decisions, items 7554 and 7557), and
    /// his iPad is not known to have it: his Trash takes about ten letters a
    /// day and he has never archived (TODO's gap review, 2026-09-30), which
    /// is what Deleted Mailbox does. To be read off his iPad and set here.
    static var moveDiscardedMessagesInto: SwipeOptions.Discard {
        get { stored(.moveDiscardedMessagesInto) ?? .trash }
        set { defaults.set(newValue.rawValue, forKey: Option.moveDiscardedMessagesInto.key) }
    }

    /// Where they are kept: the app's own, which the screens read.
    static var defaults: UserDefaults { .standard }

    private static func stored<T: RawRepresentable>(_ option: Option) -> T?
    where T.RawValue == String {
        defaults.string(forKey: option.key).flatMap(T.init(rawValue:))
    }

    // MARK: - The rows

    /// A row of Mail's page, by what it sets.
    enum Option: String, CaseIterable {
        case moveDiscardedMessagesInto
        case preview
        case showToCcLabels
        case swipeLeft
        case swipeRight
        case deleteOrMoveMessageAction
        case askBeforeDeleting
        case blockAllRemoteContent
        case organizeByThread
        case collapseReadMessages
        case mostRecentMessageOnTop
        case completeThreads

        /// Mail's words for it, beside its switch or over its value.
        var title: String {
            switch self {
            case .moveDiscardedMessagesInto: return "Move Discarded Messages Into"
            case .preview: return "Preview"
            case .showToCcLabels: return "Show To/Cc Labels"
            case .swipeLeft: return "Swipe Left"
            case .swipeRight: return "Swipe Right"
            case .deleteOrMoveMessageAction: return "Delete or Move Message Action"
            case .askBeforeDeleting: return "Ask Before Deleting"
            case .blockAllRemoteContent: return "Block All Remote Content"
            case .organizeByThread: return "Organize by Thread"
            case .collapseReadMessages: return "Collapse Read Messages"
            case .mostRecentMessageOnTop: return "Most Recent Message on Top"
            case .completeThreads: return "Complete Threads"
            }
        }

        /// Where its value is kept. Organize by Thread, Complete Threads and
        /// Delete or Move Message Action keep the keys they had before B-167,
        /// so a value set before stays, and a safe start still puts the
        /// first two back (`SafeStart.viewSettings`); Ask Before Deleting and
        /// Block All Remote Content have the keys B-168's branch gives them,
        /// so the two branches read one value.
        var key: String {
            switch self {
            case .organizeByThread, .completeThreads, .deleteOrMoveMessageAction,
                 .askBeforeDeleting, .blockAllRemoteContent:
                return "blackmail." + rawValue
            default:
                return "blackmail.mail." + rawValue
            }
        }

        /// The words of its values, in the order Mail lists them; none for
        /// a switch.
        var choices: [String] {
            switch self {
            case .moveDiscardedMessagesInto: return SwipeOptions.Discard.allCases.map(\.word)
            case .preview: return (0...5).map(MailOptions.previewWord)
            case .swipeLeft, .swipeRight: return SwipeOptions.Choice.allCases.map(\.word)
            case .deleteOrMoveMessageAction: return NextLetter.Action.allCases.map(\.word)
            default: return []
            }
        }

        var isSwitch: Bool { choices.isEmpty }

        /// A switch's value from the factory, Mail's.
        var factoryOn: Bool {
            switch self {
            case .organizeByThread, .collapseReadMessages, .completeThreads:
                return true
            default:
                return false
            }
        }

        /// A switch's value: as set, or Mail's from the factory where it has
        /// never been. Read with `object(forKey:)`, as `bool(forKey:)`
        /// answers false for a key never written, and an absent value and an
        /// explicit off must not mean the same.
        var isOn: Bool {
            get { MailOptions.defaults.object(forKey: key) as? Bool ?? factoryOn }
            nonmutating set { MailOptions.defaults.set(newValue, forKey: key) }
        }

        /// A choice's value, as the place of its word in `choices`. A place
        /// out of their range sets nothing.
        var chosen: Int {
            get {
                switch self {
                case .moveDiscardedMessagesInto:
                    return SwipeOptions.Discard.allCases.firstIndex(
                        of: MailOptions.moveDiscardedMessagesInto) ?? 0
                case .preview:
                    return MailOptions.previewLines
                case .swipeLeft:
                    return SwipeOptions.Choice.allCases.firstIndex(of: MailOptions.swipeLeft) ?? 0
                case .swipeRight:
                    return SwipeOptions.Choice.allCases.firstIndex(of: MailOptions.swipeRight) ?? 0
                case .deleteOrMoveMessageAction:
                    return NextLetter.Action.allCases.firstIndex(
                        of: MailOptions.deleteOrMoveMessageAction) ?? 0
                default:
                    return 0
                }
            }
            nonmutating set {
                guard choices.indices.contains(newValue) else { return }
                switch self {
                case .moveDiscardedMessagesInto:
                    MailOptions.moveDiscardedMessagesInto = SwipeOptions.Discard.allCases[newValue]
                case .preview:
                    MailOptions.previewLines = newValue
                case .swipeLeft:
                    MailOptions.swipeLeft = SwipeOptions.Choice.allCases[newValue]
                case .swipeRight:
                    MailOptions.swipeRight = SwipeOptions.Choice.allCases[newValue]
                case .deleteOrMoveMessageAction:
                    MailOptions.deleteOrMoveMessageAction = NextLetter.Action.allCases[newValue]
                default:
                    break
                }
            }
        }

        /// What is drawn after its title: a choice's word, nil for a switch.
        var value: String? {
            isSwitch ? nil : choices[chosen]
        }

        /// What Blackmail does in its place, under a row Blackmail does not
        /// have every value of (`built`); nil for one it has.
        var instead: String? {
            guard !MailOptions.built.contains(self) else { return nil }
            switch self {
            case .preview: return "Blackmail always shows 2 lines."
            case .showToCcLabels: return "Blackmail shows no labels."
            case .askBeforeDeleting:
                return "Blackmail asks only before a delete in the Trash, which cannot be undone."
            case .blockAllRemoteContent: return "Blackmail always loads pictures from the web."
            case .collapseReadMessages:
                return "Blackmail always closes the letters you have read in a conversation."
            case .mostRecentMessageOnTop:
                return "Blackmail always puts the newest letter of a conversation at the bottom."
            default: return nil
            }
        }
    }

    /// The options Blackmail has every value of: their rows set them. The
    /// rest are drawn greyed, at their value, and set nothing. Ask Before
    /// Deleting and Block All Remote Content are B-168's.
    static let built: Set<Option> = [
        .moveDiscardedMessagesInto, .swipeLeft, .swipeRight, .deleteOrMoveMessageAction,
        .askBeforeDeleting, .blockAllRemoteContent, .organizeByThread, .completeThreads,
    ]

    /// Preview's word for `lines`, Mail's.
    static func previewWord(_ lines: Int) -> String {
        switch lines {
        case 0: return "None"
        case 1: return "1 Line"
        default: return "\(lines) Lines"
        }
    }

    // MARK: - The page

    /// A part of Mail's page: its heading, drawn in capitals as Mail's are,
    /// its rows, and the line under it where Mail has one.
    struct Section: Equatable {
        var heading: String?
        var rows: [Row]
        var footer: String? = nil
    }

    /// A row of a part.
    indirect enum Row: Equatable {
        /// A switch; or a choice, its value after its title, which opens a
        /// page of its values.
        case option(Option)
        /// A choice's values, each a row, the chosen one ticked, as on
        /// Mail's page of them and its account's Advanced page.
        case values(Option)
        /// One of Mail's pages, by its title: its row opens it.
        case page(String, [Section])
    }

    /// Settings > Apps > Mail as Blackmail lays it out, in the order of
    /// Mail's page, the account first as Mail Accounts is above Message
    /// List, and in its words: the parts of it Blackmail follows. The
    /// account's part has the heading of its Advanced page, colon and all,
    /// as its users quote it. Mail's other rows (Flag Style, Follow Up
    /// Suggestions, Blocked Sender Options, Muted Thread Action, Composing,
    /// Undo Send Delay) are not here; nor Privacy Protection's Protect Mail
    /// Activity and Hide IP Address, which Blackmail cannot do
    /// (`blockAllRemoteContent`): the line under Block All Remote Content
    /// says where Mail shows it.
    static let page: [Section] = [
        Section(heading: Option.moveDiscardedMessagesInto.title + ":",
                rows: [.values(.moveDiscardedMessagesInto)],
                footer: "In Mail: Mail Accounts > Gmail > Account > Advanced."),
        Section(heading: "Message List",
                rows: [.option(.preview), .option(.showToCcLabels),
                       .page("Swipe Options",
                             [Section(heading: nil, rows: [.option(.swipeLeft),
                                                           .option(.swipeRight)])]),
                       .option(.deleteOrMoveMessageAction)]),
        Section(heading: "Messages",
                rows: [.option(.askBeforeDeleting),
                       .page("Privacy Protection",
                             [Section(heading: nil, rows: [.option(.blockAllRemoteContent)],
                                      footer: privacyFooter)])]),
        Section(heading: "Threading",
                rows: [.option(.organizeByThread), .option(.collapseReadMessages),
                       .option(.mostRecentMessageOnTop), .option(.completeThreads)],
                footer: completeThreadsFooter),
    ]

    /// Under Block All Remote Content, where Mail has it, and what Blackmail
    /// cannot do. Blackmail's words.
    static let privacyFooter = "In Mail, shown when Protect Mail Activity is off. "
        + "Blackmail never loads pictures through Apple."

    /// Mail's line under Threading, of Complete Threads (B-104).
    static let completeThreadsFooter =
        "Show all the messages in a thread, even if some have been moved to other mailboxes."

    /// The page a choice's row opens: its values, under its title.
    static func valuesPage(of option: Option) -> [Section] {
        [Section(heading: nil, rows: [.values(option)])]
    }

    /// Every option on `sections`, and on the pages their rows open, in
    /// order.
    static func options(on sections: [Section]) -> [Option] {
        sections.flatMap(\.rows).flatMap { row -> [Option] in
            switch row {
            case .option(let option), .values(let option): return [option]
            case .page(_, let inner): return options(on: inner)
            }
        }
    }
}

// MARK: - Mail's words for the values

extension SwipeOptions.Choice {
    /// Mail's word for it on its Swipe Left and Swipe Right pages.
    var word: String {
        switch self {
        case .none: return "None"
        case .mark: return "Mark as Read"
        case .flag: return "Flag"
        case .move: return "Move Message"
        case .archive: return "Archive"
        }
    }
}

extension SwipeOptions.Discard {
    /// Mail's word for it on the account's Advanced page.
    var word: String {
        switch self {
        case .trash: return "Deleted Mailbox"
        case .archive: return "Archive Mailbox"
        }
    }
}

extension NextLetter.Action {
    /// Mail's word for it on its Delete or Move Message Action page, with
    /// Mail's apostrophe, as B-144's "Don’t Include".
    var word: String {
        switch self {
        case .viewNextMessage: return "View Next Message"
        case .dontSelectAMessage: return "Don’t Select a Message"
        }
    }
}
