import Foundation

/// The message list's preview pass, without the table view: which previews
/// to ask for, in what order, and when to stop.
///
/// Out of `MessageListViewController` so it can be TESTED. The controller is
/// UIKit and does not exist on the machine the suite runs on, so while this
/// loop lived there, reverting it left every test green.
///
/// Rows are asked for by the mailbox they belong to, not the one on screen,
/// because an "All Mailboxes" search returns rows from All Mail, Trash and
/// Spam at once, each carrying its own mailbox's UIDs. Asking the Inbox for
/// them fetches whatever happens to wear those numbers there, or nothing.
///
/// And one mailbox at a time. The list used to start a task per mailbox,
/// and the groups raced: each one's SELECT and the FETCH after it take the
/// connection separately, so another group's SELECT could land between
/// them and the FETCH asked the wrong folder for those UIDs. Under an "All
/// Mailboxes" search that left most previews blank. Going one after another
/// removes the race between the groups. It does not stop a SELECT from
/// anything else, the next page's previews included, landing in the same
/// gap; that needs the SELECT and the FETCH to share one hold on the
/// connection.
enum PreviewPass {

    struct Group: Equatable {
        let mailboxID: String
        let ids: [String]
    }

    /// The rows' ids by mailbox, in the order the rows are drawn, so the
    /// group holding the top of the list fills first. `Dictionary(grouping:)`
    /// has no order.
    static func groups(for rows: [MessageSummary]) -> [Group] {
        var order: [String] = []
        var ids: [String: [String]] = [:]
        for row in rows {
            if ids[row.mailboxID] == nil { order.append(row.mailboxID) }
            ids[row.mailboxID, default: []].append(row.id)
        }
        return order.map { Group(mailboxID: $0, ids: ids[$0] ?? []) }
    }

    /// Asks for each group's previews in turn, each finished before the next
    /// is asked for, and hands each answer to `apply` as it lands.
    ///
    /// `isCurrent` is asked before every request and before every `apply`.
    /// Once it says no, the list has been replaced while this was waiting:
    /// these previews belong to rows no longer on screen, and so does every
    /// group after this one, so the pass stops rather than spending the
    /// connection on them.
    ///
    /// A group that fails costs its own previews and not the rest. A blank
    /// preview is two grey lines; an alert about one would be the app
    /// interrupting him about work he never asked for.
    static func run(_ groups: [Group],
                    fetch: (_ ids: [String], _ mailboxID: String) async throws -> [String: String],
                    isCurrent: () async -> Bool,
                    apply: ([String: String]) async -> Void) async {
        for group in groups {
            guard await isCurrent() else { return }
            guard let previews = try? await fetch(group.ids, group.mailboxID),
                  !previews.isEmpty else { continue }
            guard await isCurrent() else { return }
            await apply(previews)
        }
    }
}
