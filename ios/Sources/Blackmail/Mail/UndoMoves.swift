import Foundation

/// One step of Mail's Undo (B-157): a Trash or a Move the server has taken,
/// from a drag on a row, Edit mode's bar or the reading pane, which a shake
/// of the iPad, iPadOS's three-finger gesture or Command-Z on a keyboard
/// undoes. UIKit asks first, in its own words from `actionName`, "Undo
/// Trash" or "Undo Move", with Cancel and Undo, as Mail's alert reads
/// (NYT 2016, Macworld; not seen on iPadOS 18, item 334a).
///
/// The letters the server took, each with where it went (`MoveLanding`),
/// in the order they were sent, the oldest first (B-084), so that moved
/// back in that order they keep their order in the folder they go back to.
/// A batch is one step, as one tap made it.
///
/// Held by the screens' undo manager in memory, and nowhere else: after a
/// relaunch there is nothing to undo.
struct UndoableMove: Equatable {

    enum Kind: Equatable {
        /// A Delete, which moved the letters to Gmail's Trash.
        case trash
        /// A Move, the Move sheet's or an Archive.
        case move
    }

    struct Letter: Equatable {
        /// The row as the list had it at the tap: the folder it was taken
        /// from, and the id it was taken under.
        let row: MessageSummary
        let landing: MoveLanding
    }

    let kind: Kind
    let letters: [Letter]

    /// What UIKit puts after "Undo" in its alert and in the three-finger
    /// gesture's banner.
    var actionName: String {
        switch kind {
        case .trash: return EditBar.trash
        case .move: return "Move"
        }
    }

    /// The step for `action` on `letters`, those the server took, each with
    /// where it went (`landings`, by id); nil when there is nothing to undo.
    ///
    /// Not undone, as there is nothing to move back or nothing safe to: a
    /// letter erased inside Trash, which has no landing; a Flag, which is
    /// a step of its own (`UndoableFlag`), and a read mark, which nothing
    /// says Mail undoes; a letter of Drafts, which Gmail does not bring
    /// back from Trash as a draft; one kept on this iPad, which never went
    /// to the server; a Move that leaves its row on the list, a letter
    /// filed from All Mail into a folder, which stays in All Mail; and a
    /// letter with no Gmail id, which cannot be made sure of where it went
    /// (`MailRepository.moveBack`).
    static func after(_ action: PaneAction, took letters: [MessageSummary],
                      landings: [String: MoveLanding],
                      role: (String) -> Mailbox.Role?) -> UndoableMove? {
        let kind: Kind
        switch action {
        case .delete: kind = .trash
        case .move: kind = .move
        case .flag, .read: return nil
        }
        let undone = letters.compactMap { row -> Letter? in
            guard let landing = landings[row.id], landing.letter != nil,
                  LocalDraft.key(ofRow: row.id) == nil else { return nil }
            let from = role(row.mailboxID)
            guard from != .drafts, from != .outbox,
                  PaneActions.effect(of: action, onLetterIn: from).removesRow else { return nil }
            return Letter(row: row, landing: landing)
        }
        return undone.isEmpty ? nil : UndoableMove(kind: kind, letters: undone)
    }
}

/// One step of Mail's Undo for a Flag or an Unflag (B-157): Mail's
/// "Undo Flag", which one guide of 2023 lists with its "Undo Trash" and
/// "Undo Archive" (macReports); nothing says Mail undoes a read mark, and
/// nothing here does. The letters whose flag the server took, from a drag,
/// More or the reading pane, and the flag that was set on them: Undo sets
/// the other back, on those letters alone. Not seen: the alert's words
/// after an Unflag.
struct UndoableFlag: Equatable {
    /// The flag set: true for a Flag, false for an Unflag.
    let flagged: Bool
    let letters: [MessageSummary]

    /// "Undo Flag", or "Undo Unflag", in UIKit's alert.
    var actionName: String { flagged ? "Flag" : "Unflag" }

    /// The step for `action` on `letters`, those the server took it on;
    /// nil for anything but a Flag or an Unflag, and when there is nothing
    /// to undo. Not a letter kept on this iPad, which has no flag on the
    /// server.
    static func after(_ action: PaneAction, took letters: [MessageSummary]) -> UndoableFlag? {
        guard case .flag(let flagged) = action else { return nil }
        let undone = letters.filter { LocalDraft.key(ofRow: $0.id) == nil }
        return undone.isEmpty ? nil : UndoableFlag(flagged: flagged, letters: undone)
    }
}

/// A step of Mail's Undo (B-157), as the screens' undo manager holds it: a
/// Trash or a Move, or a Flag or an Unflag.
enum Undoable: Equatable {
    case move(UndoableMove)
    case flag(UndoableFlag)

    /// What UIKit puts after "Undo".
    var actionName: String {
        switch self {
        case .move(let step): return step.actionName
        case .flag(let step): return step.actionName
        }
    }
}

/// Runs an `UndoableMove` (B-157): each letter moved back to the folder it
/// was taken from (`MailRepository.moveBack`), and its row put back on the
/// list where it stood (`ListLetters.restore`).
///
/// Out of `RootViewController` for the reason `ListBatch` is: the
/// controller is UIKit and does not exist on the machine the suite runs on.
@MainActor
enum UndoMoves {

    struct Outcome: Equatable {
        /// The letters moved back, by the id each was taken under.
        var back: [String] = []
        /// Moved back, and not put back on the list, which no longer holds
        /// the rows they were taken from: the list is to be fetched afresh.
        var unplaced: [String] = []
        /// Not where they went any more (`MoveLanding.Gone`): left where
        /// they are, nothing written, and nothing said.
        var gone: [String] = []
        /// What was not tried after a failure, the failed letter first,
        /// to undo again: one more shake tries it.
        var left: UndoableMove?
        /// What the alert says, nil when nothing failed.
        var refusal: MailError?
    }

    /// Moves `step`'s letters back, one at a time, the oldest first, as
    /// they went. The first failure stops the rest, as for Edit mode's
    /// batch (`ListBatch`): it is nearly always the connection or the
    /// password, which the next letter would meet too. A letter that is
    /// not where it went is passed over, and the rest go on. Nothing is
    /// sent but each letter's MOVE back and the question before it.
    ///
    /// `list` is the list the letters were taken from, while it is on the
    /// screen; nil once another folder has replaced it. The counts are
    /// swept if any letter that went back was unread: the folder it went
    /// back to and the one it left both change, as for the Move itself
    /// (`PaneActions.effect`).
    static func run(_ step: UndoableMove, repository: MailRepository, list: ListLetters?,
                    requestSweep: @MainActor () -> Void) async -> Outcome {
        var outcome = Outcome()
        var sweepOwed = false
        for (i, letter) in step.letters.enumerated() {
            let id: String?
            do {
                id = try await repository.moveBack(letter.landing, to: letter.row.mailboxID)
            } catch is MoveLanding.Gone {
                outcome.gone.append(letter.row.id)
                continue
            } catch {
                outcome.refusal = (error as? MailError) ?? .cannotConnect
                outcome.left = UndoableMove(kind: step.kind, letters: Array(step.letters[i...]))
                break
            }
            outcome.back.append(letter.row.id)
            if !(id.map { list?.restore(letter.row, as: $0) ?? false } ?? false) {
                outcome.unplaced.append(letter.row.id)
            }
            if !letter.row.isRead { sweepOwed = true }
        }
        if sweepOwed { requestSweep() }
        return outcome
    }

    /// What became of an Undo of a Flag.
    struct FlagOutcome: Equatable {
        /// The letters whose flag went back, by the id each has now.
        var back: [String] = []
        /// What was not put back after a failure, to undo again: one more
        /// shake tries it. The step as it was while a Flag on one of its
        /// letters is still on its way, with nothing sent.
        var left: UndoableFlag?
        var refusal: MailError?
    }

    /// Puts back the flag `step` changed, as Edit mode's batch goes
    /// (`ListBatch`): the rows' flag at once, a STORE a letter at a time,
    /// the first failure stopping the rest and putting back what was not
    /// taken. Nothing is sent but each letter's STORE.
    ///
    /// Each letter as `list` shows it now, where it does: a letter trashed
    /// after its Flag and brought back by that step's Undo is in its folder
    /// under a new id (`ListLetters.shownRow`). Where the list no longer
    /// shows it, or has gone, by the id it had, which the repository makes
    /// sure of before the STORE goes. Not while a Flag on any of them is on
    /// its way, as a drag and the pane wait for their own: the step is
    /// left, nothing sent, for the next shake.
    static func run(_ step: UndoableFlag, repository: MailRepository, list: ListLetters?,
                    requestSweep: @MainActor () -> Void) async -> FlagOutcome {
        let letters = step.letters.map { list?.shownRow(of: $0) ?? $0 }
        if let list, letters.contains(where: { list.flagOnItsWay($0.id) }) {
            return FlagOutcome(left: step)
        }
        // A Flag's effect does not hang on the folder's role
        // (`PaneActions.effect`).
        let outcome = await ListBatch.run(.flag(!step.flagged), on: letters, role: { _ in nil },
                                          list: list, repository: repository,
                                          requestSweep: requestSweep)
        let left = letters.filter { outcome.notTaken.contains($0.id) }
        return FlagOutcome(back: outcome.taken,
                           left: outcome.refusal == nil || left.isEmpty
                               ? nil : UndoableFlag(flagged: step.flagged, letters: left),
                           refusal: outcome.refusal)
    }
}
