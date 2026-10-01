import Foundation

/// The folders the pane lists, with their unread counts as it shows them
/// between sweeps, and where each one is drawn (B-059).
///
/// Out of `MailboxListViewController` for the reason `SweepCoalescer` is:
/// the controller is UIKit and does not exist on the machine the suite runs
/// on, and both of the count bugs this answers were in it.
///
/// **Where a folder is drawn.** The pane draws its folders in blocks: the
/// Inbox, then the rest, then the Outbox while letters wait (`blocks`). A
/// read mark's count was patched at the row a folder has in the flat list,
/// in the first block, which holds only the Inbox: every other folder's
/// cell was missed, and All Mail, Important and Sent Mail kept their old
/// number on screen until the next sweep (`place`).
///
/// **A sweep that left before a read mark.** A count changed here by his
/// read or unread mark, or an unread letter he has binned, once the server
/// has it, is numbered with what it did to the count (`adjust`). A sweep
/// notes the number it starts at (`mark`). If it lands after a later
/// change, the STATUS it asked of that folder may have gone before the
/// change reached the server, and its count would put the letter back: the
/// Inbox read 1, then 2, then 1 when the sweep after it landed. So where
/// the sweep's count of a folder is exactly the pane's before the changes
/// made since it left, it did not see them, and they are put on its count
/// (`land`). Anything else it says is taken, as before: new mail it saw,
/// or a count kept from the last launch that the server has gone on from,
/// which holding would have drawn too low, saying there was no new mail
/// when there was. The sweep the pane asks for after the change starts
/// after it and says what the server has.
struct FolderCounts {

    /// The folders, in the order the repository ranked them, with the
    /// counts the pane shows.
    private(set) var folders: [Mailbox] = []

    /// Local changes made so far.
    private var changes = 0
    /// For each folder, by its id in `folders`, the local changes a sweep
    /// may not have seen: each one's number, and what it did to the count,
    /// which is less than asked at none.
    private var changedAt: [String: [(at: Int, by: Int)]] = [:]

    /// Where a sweep starting now stands: after every local change made
    /// so far.
    var mark: Int { changes }

    /// The folders to draw in place of these: the names alone while the
    /// first sweep is out, their counts noughts, or the folders kept from
    /// the last sweep. Neither is a sweep, and nothing changed here is put
    /// on either. A nought that is no count is put a change on as any
    /// count: a sweep is only given it when it says that same nought.
    mutating func take(_ fresh: [Mailbox]) {
        folders = fresh
        changedAt = [:]
    }

    /// `delta` on the count of each of `mailboxIDs`, matched as the pane
    /// matches them, never below none: one off for a letter he has read or
    /// an unread one binned, one back for one marked unread. Returns the
    /// folders whose number changed, each of which is numbered with what it
    /// did.
    mutating func adjust(_ mailboxIDs: [String], by delta: Int) -> [Mailbox] {
        changes += 1
        var changed: [Mailbox] = []
        for id in mailboxIDs {
            guard let i = folders.firstIndex(matchingMailboxID: id) else { continue }
            let updated = max(0, folders[i].unreadCount + delta)
            guard updated != folders[i].unreadCount else { continue }
            changedAt[folders[i].id, default: []]
                .append((at: changes, by: updated - folders[i].unreadCount))
            folders[i].unreadCount = updated
            changed.append(folders[i])
        }
        return changed
    }

    /// A sweep's folders in place of these, the sweep having started at
    /// `mark`; but a folder changed here since, whose count in the sweep is
    /// exactly the pane's before those changes, gets them put on it: the
    /// sweep asked before they reached the server. Returns how many folders
    /// that was: the kept copy, which the repository has just given the
    /// sweep's counts, is then to be given these (D-016).
    @discardableResult
    mutating func land(_ fresh: [Mailbox], sweptFrom mark: Int) -> Int {
        var landed = fresh
        var held = 0
        for i in landed.indices {
            let since = (changedAt[landed[i].id] ?? []).filter { $0.at > mark }
            let by = since.reduce(0) { $0 + $1.by }
            guard by != 0,
                  let here = folders.first(where: { $0.id == landed[i].id }),
                  landed[i].unreadCount == here.unreadCount - by else { continue }
            landed[i].unreadCount = here.unreadCount
            held += 1
        }
        folders = landed
        // Sweeps run one at a time: the next starts after this one, at a
        // mark no lower than every change it has seen.
        changedAt = changedAt
            .mapValues { $0.filter { $0.at > mark } }
            .filter { !$0.value.isEmpty }
        return held
    }

    /// The pane's blocks: the Inbox, then everything else, in the order the
    /// repository ranked them, then the Outbox's row while `outbox` letters
    /// wait. Empty blocks are dropped.
    func blocks(outbox: Int) -> [[Mailbox]] {
        let inbox = folders.filter { $0.role == .inbox }
        let rest = folders.filter { $0.role != .inbox }
        // Even with no folders listed, as after a launch with no
        // connection, when it is the one thing here worth seeing.
        let waiting = outbox > 0 ? [Outbox.mailbox(holding: outbox)] : []
        return [inbox, rest, waiting].filter { !$0.isEmpty }
    }

    /// Where the folder `mailboxID` is drawn among `blocks`: its block and
    /// its row in it, matched as the pane matches. Nil for one not there.
    static func place(of mailboxID: String,
                      in blocks: [[Mailbox]]) -> (section: Int, row: Int)? {
        for (section, block) in blocks.enumerated() {
            if let row = block.firstIndex(matchingMailboxID: mailboxID) {
                return (section, row)
            }
        }
        return nil
    }
}
