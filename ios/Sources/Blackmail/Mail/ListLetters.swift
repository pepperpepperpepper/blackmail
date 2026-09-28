import Foundation

/// The letters the message list holds: the folder's pages, a search's hits
/// over them, the letters taken off by hand, and which reads have been
/// billed to the folder counts. What the list's rows are cut from, and what
/// paging reads its place from.
///
/// Out of `MessageListViewController` for the reason `SearchAnswer` is: the
/// controller is UIKit and does not exist on the machine the suite runs on.
/// The reading pane's Delete, Move and Flag edit these letters, and while
/// the edits lived in the controller the suite could only check a copy of
/// them, so any of them could be reverted with every test green. The
/// controller owns one, groups `shown` into its rows, and redraws when told.
///
/// Nothing here redraws by itself. The pages, the searches and the
/// previews change the letters and leave the redraw to the controller, which
/// has a scroll position to look after while it does; the edits the pane
/// makes, which the controller does not see coming, call `changed`.
@MainActor
final class ListLetters: PaneActionList {

    /// The folder's letters, newest first, page by page.
    private(set) var folder: [MessageSummary] = []
    /// A search's hits, drawn in place of the folder's letters; nil when
    /// no search is showing.
    private(set) var results: [MessageSummary]?

    private var removed = RemovedLetters()
    private var billing = ReadBilling()

    /// A letter the pane changed, or took off or put back: the rows are to
    /// be regrouped and redrawn.
    var changed: () -> Void = {}
    /// The reading pane has let a letter go. See `letGo`.
    var onLetGo: (MessageSummary) -> Void = { _ in }
    /// The folder counts to change, and by how much.
    var onUnreadCountChanged: ([String], Int) -> Void = { _, _ in }

    var isSearching: Bool { results != nil }

    /// What paging walks and what the rows are cut from: the hits while a
    /// search is showing, the folder otherwise.
    var visible: [MessageSummary] { results ?? folder }

    /// `visible` without the letters taken off by hand: the rows.
    var shown: [MessageSummary] { removed.remaining(visible) }

    /// Where the next page down is asked for from: the last letter the last
    /// page gave, even when it has since been binned. See `RemovedLetters`.
    var cursor: String? { visible.last?.id }

    /// Every copy this list holds, the folder's and the hits', which can be
    /// the same letter under two mailboxes' ids (`ListEdit.twins`).
    private var everything: [MessageSummary] { folder + (results ?? []) }

    // MARK: - Pages and searches

    /// The folder's newest page, fetched afresh from the top, in place of
    /// everything: the pages below it and any search. Returns the letters
    /// whose previews still have to be fetched.
    ///
    /// Previews already drawn go across to the same letters, by id, and only
    /// the rest are asked for (`ListEdit.carryingPreviews`). A refresh used
    /// to blank every preview and fetch them all again. And what was taken
    /// off by hand, the server now has the say on (`RemovedLetters`).
    func fetchedAfresh(_ page: [MessageSummary]) -> [MessageSummary] {
        folder = ListEdit.carryingPreviews(from: everything, into: page)
        results = nil
        removed.listReplaced()
        return folder.filter { $0.preview.isEmpty }
    }

    /// The mail around a day, in place of everything.
    func showWindow(_ letters: [MessageSummary]) {
        folder = letters
        results = nil
    }

    /// A page from further down, after the folder's letters or the hits'.
    /// Returns the letters it added: not the ones already here, which a
    /// letter moved in by another client can be, twice across two pages.
    func appendPage(_ page: [MessageSummary], toResults: Bool) -> [MessageSummary] {
        let known = Set(visible.map(\.id))
        let fresh = page.filter { !known.contains($0.id) }
        if toResults { results?.append(contentsOf: fresh) }
        else { folder.append(contentsOf: fresh) }
        return fresh
    }

    /// A page from further up the folder, after a date jump. Returns the
    /// letters it added.
    func prependPage(_ page: [MessageSummary]) -> [MessageSummary] {
        let known = Set(folder.map(\.id))
        let fresh = page.filter { !known.contains($0.id) }
        folder.insert(contentsOf: fresh, at: 0)
        return fresh
    }

    func showResults(_ hits: [MessageSummary]) {
        results = hits
    }

    /// Back to the folder's letters, as they were, without a round trip.
    /// Returns the ones whose previews still have to be fetched.
    ///
    /// A search replaces the list, and a preview pass stops as soon as its
    /// list is replaced (`PreviewPass`), so whatever the folder's pass had
    /// not fetched when the search began was never fetched: cancelling the
    /// search put the folder back with those rows blank until the next
    /// Refresh. They are asked for again now, less any the search has
    /// already brought: a hit is the same letter, and its preview is the
    /// folder row's too, under the same id (`apply(previews:)` fills both)
    /// or, for an All Mailboxes hit, under All Mail's
    /// (`ListEdit.carryingPreviews(fromTwins:into:)`). Letters taken off by
    /// hand are not asked for.
    @discardableResult
    func endSearch() -> [MessageSummary] {
        let hits = results ?? []
        results = nil
        folder = ListEdit.carryingPreviews(fromTwins: hits, into: folder)
        return shown.filter { $0.preview.isEmpty }
    }

    func apply(previews: [String: String]) {
        for i in folder.indices {
            if let text = previews[folder[i].id] { folder[i].preview = text }
        }
        guard var hits = results else { return }
        for i in hits.indices {
            if let text = previews[hits[i].id] { hits[i].preview = text }
        }
        results = hits
    }

    // MARK: - Read and unread

    /// The dot, wherever the list holds the letter.
    func setRead(_ id: String, read: Bool) {
        change(id) { $0.isRead = read }
    }

    /// The server has the letter as read: one off every folder it is
    /// counted in, once per letter however often it is asked (`ReadBilling`).
    func read(_ letter: MessageSummary) {
        guard let folders = billing.read(letter) else { return }
        onUnreadCountChanged(folders, -1)
    }

    /// The server has the letter as unread again: one back on.
    func unread(_ letter: MessageSummary) {
        onUnreadCountChanged(billing.unread(letter), 1)
    }

    // MARK: - Edits from the reading pane

    func letter(_ id: String) -> MessageSummary? {
        results?.first { $0.id == id } ?? folder.first { $0.id == id }
    }

    func letGo(_ letter: MessageSummary) {
        onLetGo(letter)
    }

    func take(_ letter: MessageSummary, fromEveryFolder: Bool) {
        let twins = fromEveryFolder ? ListEdit.twins(of: letter, among: everything).map(\.id) : []
        removed.take(letter.id, with: twins)
        changed()
    }

    func putBack(_ letter: MessageSummary) {
        removed.putBack(letter.id)
        changed()
    }

    func removalLanded(_ letter: MessageSummary, fromEveryFolder: Bool) {
        removed.land(letter.id)
        guard fromEveryFolder else { return }
        let twins = ListEdit.twins(of: letter, among: everything)
        if let folders = billing.left(letter, twins: twins) {
            onUnreadCountChanged(folders, -1)
        }
    }

    /// On the letter and on its copies under other mailboxes' ids. A flag
    /// is the letter's, not the mailbox's: Gmail stars the one message
    /// whichever label it is reached through. Flagged from an All Mailboxes
    /// hit, the Inbox row under the search used to keep the old flag, and
    /// cancelling the search puts that row back without a round trip, so
    /// it said the letter was not flagged until the next Refresh.
    ///
    /// Matched from the letter the pane holds, falling back to it when this
    /// list no longer has a row with its id. Unflagged from a hit after the
    /// search had been cancelled, the lookup by id found nothing, so nothing
    /// was patched and the Inbox row kept its flag until the next Refresh
    /// (seen on the iPad; the STORE itself had landed).
    func setFlagged(_ flagged: Bool, on letter: MessageSummary) {
        let known = self.letter(letter.id) ?? letter
        let twins = ListEdit.twins(of: known, among: everything)
        for copy in [letter.id] + twins.map(\.id) {
            change(copy) { $0.isFlagged = flagged }
        }
        changed()
    }

    func addCountedFolder(_ name: String, to id: String) {
        change(id) { letter in
            guard !letter.countedFolderIDs.contains(name) else { return }
            letter.countedFolderIDs = ReadBilling.folders(of: letter) + [name]
        }
        changed()
    }

    /// Changes the letter with `id` wherever this list holds it, the
    /// folder's letters and the hits.
    private func change(_ id: String, _ edit: (inout MessageSummary) -> Void) {
        ListEdit.change(&folder, id: id, edit)
        guard var hits = results else { return }
        ListEdit.change(&hits, id: id, edit)
        results = hits
    }
}
