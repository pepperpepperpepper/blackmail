import Foundation

/// Two panes or three, and what the left column shows in two. D-015.
///
/// Out of `RootViewController` for the reason `Sitting` is: the controller
/// is UIKit and does not exist on the machine the suite runs on. The
/// controller sizes the panes, hides and shows them, and dresses the bars
/// as this says, one property to one setting, and what each button and tap
/// does to it is decided in `PaneShell`.
///
/// Three panes, Mailboxes | list | message, as D-009 measured them, unless
/// he has chosen two with the view button in the top-left corner: the
/// button iOS 10 Mail had on the 12.9-inch iPad, which added and removed the
/// Mailboxes column. In two, D-003's arrangement: the left column holds the
/// Mailboxes or a folder's list in turn, "< Mailboxes" goes back from the
/// list to the folders, and the message takes the rest.
///
/// A switch changes where things are and nothing else. The folder open, its
/// list, a search in it and the letter in the pane stay what they were:
/// nothing here opens a folder except a tap on one, so nothing is fetched
/// because of a switch or a "< Mailboxes".
struct PaneArrangement: Equatable {

    enum Panes: String {
        /// Mailboxes | list | message. The default.
        case three
        /// The Mailboxes or a folder's list, in one column, beside the
        /// message.
        case two
    }

    /// One of the two things the left column holds in two panes.
    enum Column: Equatable {
        case mailboxes
        case list
    }

    /// What the container does with a tap on a folder.
    enum FolderTap: Equatable {
        /// Opens it: a new list, which fetches the folder's first page.
        /// What a tap in the three-pane sidebar always does.
        case open
        /// Opens nothing: the folder tapped is the one the list already
        /// shows, and the list comes back in front as he left it.
        case showList
    }

    private(set) var panes: Panes
    /// Which of the two is in front in two panes. `.list` whenever three
    /// panes show both, so that a switch to two always lands on the list.
    private var front: Column

    /// At launch, in the arrangement he last chose. In two panes with the
    /// list in front: the app opens into the Inbox (`PRODUCT_SPEC.md`), and
    /// in two panes that is the Inbox's list with "< Mailboxes" over it,
    /// which is how iOS 10 Mail opened.
    init(launching panes: Panes) {
        self.panes = panes
        front = .list
    }

    /// What the left column shows: the Mailboxes in three panes, and in two
    /// whichever of the Mailboxes and the list is in front.
    var leftColumn: Column { panes == .three ? .mailboxes : front }

    var mailboxesOnScreen: Bool { panes == .three || front == .mailboxes }
    var listOnScreen: Bool { panes == .three || front == .list }

    /// Whether the list's left edge is the screen's, where it shares the
    /// column with the Mailboxes, rather than the Mailboxes' divider.
    var listAtScreenEdge: Bool { panes == .two }
    /// The divider between the Mailboxes and the list. Two panes have none:
    /// the two take turns in one column, and the list's own divider is the
    /// column's edge.
    var mailboxDividerOnScreen: Bool { panes == .three }

    /// A control the container puts in the list's bar.
    enum BarItem: Equatable {
        /// The view button, the twin of the one in the Mailboxes' bar.
        case viewButton
        /// "< Mailboxes".
        case back
    }

    /// What goes before the calendar in the list's bar, left to right. In
    /// two panes the view button first, at the screen's edge, in the corner
    /// where the Mailboxes' bar has its own, then "< Mailboxes"; only there
    /// do the folders go out of sight and need a way back. In three
    /// nothing, since the list is in the middle and the corner belongs to
    /// the Mailboxes' bar. The calendar is the list's own and always last,
    /// beside the title (D-012).
    var itemsBeforeCalendar: [BarItem] { panes == .two ? [.viewButton, .back] : [] }

    /// What VoiceOver reads for the view button: what a tap on it does.
    var viewButtonLabel: String {
        panes == .three ? "Hide Mailboxes" : "Show Mailboxes"
    }

    // MARK: - What he does

    /// The view button. From three to two the list stays in front, where he
    /// was reading, with the folders behind "< Mailboxes". From two to three
    /// the folders come back on the left and the open folder's list goes
    /// back in the middle, whichever of them the column was showing.
    mutating func switchPanes() {
        panes = panes == .three ? .two : .three
        front = .list
    }

    /// "< Mailboxes": the folders, in front of the list. Three panes have
    /// no such button, and nothing to go back to.
    mutating func back() {
        guard panes == .two else { return }
        front = .mailboxes
    }

    /// A folder tapped in the Mailboxes. In three panes it opens, as a tap
    /// there always has, the one already open included, which is how he
    /// fetches it again from the top. In two, its list comes in front: a new
    /// one for another folder, loaded exactly as the three-pane tap loads
    /// it, and for the folder already open the list he left, where he left
    /// it, with nothing fetched. He went back to look at the folders, not
    /// to have his list thrown away.
    mutating func tapped(_ folder: Mailbox, showing shown: Mailbox) -> FolderTap {
        guard panes == .two else { return .open }
        front = .list
        return Self.isShowing(folder, in: shown) ? .showList : .open
    }

    /// The list put in front with no tap on a folder: back after a while
    /// away, which lands him in the Inbox (`Sitting`), and the date jump
    /// across all mailboxes, which opens All Mail. Two panes stay two: a
    /// return to the app is not a switch, and must not undo one (B-037).
    mutating func showList() {
        front = .list
    }

    /// Whether `tapped` is the folder the list shows. By id, and by role for
    /// the Inbox the list opens on at launch, before LIST has named it,
    /// whose id is the role word (`Mailbox.inboxBeforeListing`).
    static func isShowing(_ tapped: Mailbox, in shown: Mailbox) -> Bool {
        tapped.id == shown.id
            || (shown.id == Mailbox.inboxBeforeListing.id && tapped.role == .inbox)
    }

    // MARK: - Widths

    /// Each pane's width, in points: what the container gives each width
    /// constraint, one to one.
    struct Columns: Equatable {
        /// The Mailboxes: the left column in both.
        let mailboxes: CGFloat
        /// The list: the middle column in three panes, and in two the left,
        /// the same width as the Mailboxes it takes turns with. Never zero:
        /// the pane not in front is hidden, not squeezed (B-027).
        let list: CGFloat
        /// The message: what is left once the columns and their dividers
        /// have had theirs.
        let message: CGFloat
    }

    /// Three panes at D-009's widths, two at D-003's; see `Theme`.
    static func columns(_ panes: Panes, screenWidth w: CGFloat) -> Columns {
        switch panes {
        case .three:
            let mailboxes = Theme.mailboxColumnWidth(forScreenWidth: w)
            let list = Theme.listColumnWidth(forScreenWidth: w)
            return Columns(mailboxes: mailboxes, list: list,
                           message: w - mailboxes - list - 2 * Theme.paneDividerWidth)
        case .two:
            let left = Theme.twoPaneLeftColumnWidth
            return Columns(mailboxes: left, list: left,
                           message: w - left - Theme.paneDividerWidth)
        }
    }

    // MARK: - Kept

    static let key = "blackmail.panes"

    /// Three unless he has chosen two, kept across launches.
    ///
    /// `object(forKey:)` and a raw value, as `ConversationSettings` does it:
    /// a missing key, or anything that is not one of the two words, is
    /// three panes, so an update never opens in an arrangement he did not
    /// choose.
    static var saved: Panes {
        get {
            (UserDefaults.standard.object(forKey: key) as? String)
                .flatMap(Panes.init(rawValue:)) ?? .three
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}

/// What each button and tap does to the arrangement, and which of them opens
/// a folder. D-015.
///
/// `RootViewController` gives this the two things only UIKit can do, a new
/// list for a folder and the panes laid out, and calls it from the view
/// button, "< Mailboxes", a tap on a folder, and every other place a folder
/// is opened or the list is put in front. So which of them fetches is
/// decided here, where the suite runs it against the scripted server, and
/// not in the controller, which the host never compiles.
@MainActor
final class PaneShell {

    private(set) var arrangement: PaneArrangement

    /// A new list for the folder, in place of the one there. The only thing
    /// here that fetches: the new list loads the folder's first page.
    var openList: (Mailbox) -> Void = { _ in }
    /// The panes laid out as `arrangement` says, at once.
    var layOut: (PaneArrangement) -> Void = { _ in }

    init(launching panes: PaneArrangement.Panes) {
        arrangement = PaneArrangement(launching: panes)
    }

    /// The view button: two panes or three, kept for the next launch.
    /// Nothing is opened, so nothing is fetched.
    func switchPanes() {
        arrangement.switchPanes()
        PaneArrangement.saved = arrangement.panes
        layOut(arrangement)
    }

    /// "< Mailboxes": the folders in front, the list kept behind them as it
    /// was, nothing opened.
    func back() {
        arrangement.back()
        layOut(arrangement)
    }

    /// A folder tapped in the Mailboxes, with `shown` the one the list is
    /// showing. Opened, or its list put back in front; see
    /// `PaneArrangement.tapped`.
    func tapped(_ folder: Mailbox, showing shown: Mailbox) {
        switch arrangement.tapped(folder, showing: shown) {
        case .open: open(folder)
        case .showList: layOut(arrangement)
        }
    }

    /// A folder opened, by a tap, by a return from a while away to another
    /// folder (B-003's Inbox), or by the date jump across mailboxes (All
    /// Mail). The new list comes in front in two panes: left behind the
    /// folders it would load out of sight, and a return from a while away
    /// would land him in the folders rather than the Inbox.
    func open(_ folder: Mailbox) {
        openList(folder)
        arrangement.showList()
        layOut(arrangement)
    }

    /// The list put in front with nothing opened: back from a while away to
    /// the Inbox already showing, which is fetched again from the top where
    /// it is. Two panes stay two (B-037).
    func showList() {
        arrangement.showList()
        layOut(arrangement)
    }
}
