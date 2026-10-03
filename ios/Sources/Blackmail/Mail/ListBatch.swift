import Foundation

/// Edit mode's Delete and Move, of every letter he ticked (B-062).
///
/// Both used to send each write with `try?`, wait for all of them, and then
/// fetch the list again. A write the server refused said nothing: the
/// letter came back with the fetch, if the fetch worked, or stayed off the
/// list as if it had gone, if it did not. And Delete said nothing while it
/// worked, his ticks still on the rows, for as long as the writes and the
/// fetch took.
///
/// Now they go as the reading pane's Delete and Move go, a letter at a
/// time, by the same rules (`PaneActions`): every row he ticked comes off
/// at the tap, each letter is billed to the folder counts once the server
/// has taken it, and a refused letter's row comes back where it stood. The
/// list is not fetched again, so his place in it, a search and a day
/// jumped to stay as they were. The controller says what is under way on
/// the status line, and the refusal, if there is one, in the app's alert.
///
/// Out of `MessageListViewController` for the reason `SearchAnswer` is: the
/// controller is UIKit and does not exist on the machine the suite runs on.
@MainActor
enum ListBatch {

    /// What became of the letters.
    struct Outcome: Equatable {
        /// The letters the server took, by id, in the order sent.
        var taken: [String] = []
        /// The letters it did not take, or that were not sent once one had
        /// failed. Back on the list, but for a row kept on the iPad that the
        /// server said was another letter, which comes off as it does from
        /// the pane (`PaneActions.notTheKeptLetter`).
        var notTaken: [String] = []
        /// What the alert says: the failure that stopped the rest, or else
        /// the first refusal; nil when every letter went.
        var refusal: MailError?
    }

    /// The letters of the rows he ticked, `rows`, in list order: the rows
    /// from the top down, a conversation's letters in the order it holds
    /// them, and each letter once. UIKit gives the ticked rows in the
    /// order he ticked them, and taken as they came, the batch went in that
    /// order rather than the list's.
    ///
    /// Each letter once even though a row can no longer be ticked twice:
    /// two conversations that merge on the next page would otherwise give
    /// the same letter twice to a Delete.
    static func letters(ticked rows: [Int], in threads: [MessageThread]) -> [MessageSummary] {
        var seen = Set<String>()
        var out: [MessageSummary] = []
        for row in Set(rows).sorted() where threads.indices.contains(row) {
            for m in threads[row].messages where seen.insert(m.id).inserted { out.append(m) }
        }
        return out
    }

    /// Takes every one of `letters` off the list, or flags it, at once, and
    /// then sends the writes one at a time, in the order given, which is
    /// the list's (`letters(ticked:in:)`). `role` is the role of the folder
    /// a letter was listed from, which for an All Mailboxes hit is not the
    /// list's.
    ///
    /// The first refusal stops the rest: they are put back, unsent. A
    /// refusal is nearly always the connection or the password, which the
    /// next letter would meet too, each after a connect of its own that can
    /// take the read deadline, half a minute, with "Deleting…" on the line
    /// throughout; and a refused password must not be sent again for every
    /// letter, since Google counts each against the account. The exception
    /// is a row kept on the iPad that the server says is another letter
    /// now, which says nothing of the rest and has sent nothing: the rest
    /// go on.
    ///
    /// The counts are swept once at the end, if any letter called for it,
    /// rather than once for each.
    static func run(_ action: PaneAction, on letters: [MessageSummary],
                    role: (String) -> Mailbox.Role?, list: PaneActionList?,
                    repository: MailRepository,
                    requestSweep: @MainActor () -> Void) async -> Outcome {
        let started = letters.map {
            PaneActions.start(action, on: $0, inFolderWithRole: role($0.mailboxID), list: list)
        }
        var outcome = Outcome()
        var sweepOwed = false
        var stopped = false
        for (letter, step) in zip(letters, started) {
            if stopped {
                PaneActions.withdraw(step)
                outcome.notTaken.append(letter.id)
                continue
            }
            do {
                try await PaneActions.send(action, on: letter, repository: repository)
            } catch {
                let said = PaneActions.finish(step, failure: error, requestSweep: {})
                outcome.notTaken.append(letter.id)
                if error is MailShelf.NotTheKeptLetter {
                    outcome.refusal = outcome.refusal ?? said
                } else {
                    outcome.refusal = said
                    stopped = true
                }
                continue
            }
            PaneActions.finish(step, failure: nil, requestSweep: { sweepOwed = true })
            outcome.taken.append(letter.id)
        }
        if sweepOwed { requestSweep() }
        return outcome
    }
}
