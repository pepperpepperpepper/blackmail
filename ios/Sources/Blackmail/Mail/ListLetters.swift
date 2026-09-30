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

    /// Drafts only: the letters kept on the iPad that the server does not
    /// have yet, as rows, and the ids of the server's copies they replace,
    /// each with Gmail's id for the letter named there. See
    /// `keep(_:replacing:)`.
    private(set) var kept: [MessageSummary] = []
    private var replaced: [String: UInt64?] = [:]

    /// A letter the pane changed, or took off or put back: the rows are to
    /// be regrouped and redrawn.
    var changed: () -> Void = {}
    /// The reading pane has let a letter go. See `letGo`.
    var onLetGo: (MessageSummary) -> Void = { _ in }
    /// The folder counts to change, and by how much.
    var onUnreadCountChanged: ([String], Int) -> Void = { _, _ in }

    var isSearching: Bool { results != nil }

    /// The folder's letters are its page kept on the iPad (D-016), drawn
    /// before the server has been heard from, and not yet replaced by the
    /// page it gives now. Paging is off while they are, and the watch
    /// checks only the Inbox's count: the kept rows are an earlier launch's,
    /// and nothing is searched for below them until the fresh page has
    /// landed.
    private(set) var fromShelf = false

    /// What paging walks and what the rows are cut from: the hits while a
    /// search is showing, the folder otherwise.
    var visible: [MessageSummary] { results ?? folder }

    /// `visible` without the letters taken off by hand: the rows. Under the
    /// letters kept on the iPad, when no search is showing.
    var shown: [MessageSummary] {
        guard !isSearching, !kept.isEmpty || !replaced.isEmpty else {
            return removed.remaining(visible)
        }
        return removed.remaining(kept + folder.filter { !isReplaced($0) })
    }

    /// Whether a letter kept on the iPad stands in for `row`: it names the
    /// row's id as its copy and, where both it and the listing name Gmail's
    /// id for the letter there, the same letter. Another draft under that
    /// UID, in a Drafts renumbered under the same UIDVALIDITY or another
    /// mailbox under the same address (B-051), is not its copy and stays.
    private func isReplaced(_ row: MessageSummary) -> Bool {
        guard let copy = replaced[row.id] else { return false }
        guard let named = copy, let listed = row.gmailMessageID else { return true }
        return named == listed
    }

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
    ///
    /// His own read marks and flags stay on over it where the listing was
    /// asked before the server had them (`asked`, from `askingAfresh`; by
    /// default a listing asked now). See `holdingHisMarks`.
    func fetchedAfresh(_ page: [MessageSummary], asked: Int? = nil) -> [MessageSummary] {
        folder = holdingHisMarks(ListEdit.carryingPreviews(from: everything, into: page),
                                 asked: asked)
        results = nil
        fromShelf = false
        removed.listReplaced()
        dropNews()
        return folder.filter { $0.preview.isEmpty }
    }

    /// The folder's page kept on the iPad, in place of everything, before
    /// the server has been asked (D-016).
    func showKept(_ page: [MessageSummary]) {
        folder = page
        results = nil
        fromShelf = true
        dropNews()
    }

    /// The folder's newest page, fetched afresh while a search is showing
    /// or being typed over its kept page: in place of the folder's letters
    /// under the search, which is left as it is, hits, field and all. The
    /// folder comes back as this page when the search ends. Returns the
    /// letters whose previews still have to be fetched.
    ///
    /// What was taken off by hand stays off until the list is next fetched
    /// afresh with no search showing: the hits can hold the same letters.
    /// His own read marks and flags stay on over it, as in `fetchedAfresh`.
    func fetchedUnderSearch(_ page: [MessageSummary], asked: Int? = nil) -> [MessageSummary] {
        folder = holdingHisMarks(ListEdit.carryingPreviews(from: folder, into: page), asked: asked)
        fromShelf = false
        dropNews()
        return folder.filter { $0.preview.isEmpty }
    }

    /// The mail around a day, in place of everything.
    func showWindow(_ letters: [MessageSummary]) {
        folder = letters
        results = nil
        fromShelf = false
        dropNews()
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

    /// Drafts' letters kept on the iPad and not yet on the server
    /// (`LocalDrafts`), at the top, newest first, above the folder's own
    /// letters, and in place of the copies on the server they will replace
    /// (`replacing`, the `savedID` of each, with its `savedLetter`): a letter
    /// reopened from Drafts and saved again without a connection is one
    /// letter, not two. A row whose listing names another letter than the
    /// one the kept letter names there is not replaced (`isReplaced`).
    ///
    /// Only ever above the folder's letters, whose order it leaves alone,
    /// and never among a search's hits. Paging walks the folder's letters
    /// as before (`cursor`), since these are not the server's to page.
    func keep(_ rows: [MessageSummary], replacing: [String: UInt64?]) {
        kept = rows
        replaced = replacing
    }

    /// Drafts: a letter kept on the iPad has reached the server as `copy`
    /// (`LocalDrafts`), and the copies in `gone` have been removed from
    /// Drafts, those it replaced or those a letter sent or deleted left.
    ///
    /// The copies that went are taken off, from a search's hits as well,
    /// until the list is next fetched afresh, as a removal of his own is
    /// (`RemovedLetters`). The new copy stands where the one it replaced
    /// stood among the hits, and at the top of the folder's letters when
    /// they start at the top (`atTop`), since it is the newest there. None
    /// of it is fetched. The newest page used to be fetched again after
    /// every landing, which he had not asked for: it ended his search,
    /// left the copy just removed among the hits of one it could not end,
    /// and replaced the pages he had scrolled through with the first,
    /// taking him back up to it.
    func landed(_ copy: MessageSummary?, replacing gone: [String], atTop: Bool) {
        for id in gone {
            removed.take(id)
            removed.land(id)
        }
        guard let copy else { return }
        if var hits = results, !hits.contains(where: { $0.id == copy.id }),
           let at = hits.firstIndex(where: { gone.contains($0.id) }) {
            hits.insert(copy, at: at)
            results = hits
        }
        if atTop, !folder.contains(where: { $0.id == copy.id }) {
            folder.insert(copy, at: 0)
        }
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

    // MARK: - News from the watch

    /// Letters that have come into the folder since it was fetched, newest
    /// first, and ones taken out of it elsewhere, found by the watch
    /// (`MailWatch`) and not on the list yet: held while he is anywhere but
    /// at the top of the folder's letters with nothing ticked
    /// (`ListPlaces.showsNews`), and put on by `showNews`.
    private var arriving: [MessageSummary] = []
    private var leaving: Set<String> = []

    /// The list is to be fetched afresh rather than added to, when he is
    /// back at the top (`FolderNews.refetch`).
    private(set) var refetchOwed = false

    var holdsNews: Bool { !arriving.isEmpty || !leaving.isEmpty || refetchOwed }

    /// Every letter of the folder the list holds, the ones it has not drawn
    /// yet included: what the watch checks the folder against, so a letter
    /// held is not fetched again, and the next one is fetched on its own.
    var watched: [String] { arriving.map(\.id) + folder.map(\.id) }

    /// `watched`, when the watch is to check the folder's letters, or nil
    /// when it is to check only the Inbox's count: a list whose top is not
    /// the folder's newest letter (`fromNewest`), one whose first page never
    /// came (`fetched`, false, and nothing on it), and one showing a search.
    /// What a check found could not go on until the search ended, and an All
    /// Mailboxes search leaves All Mail open on the connection: the check
    /// would SELECT the Inbox every half minute, and each page of results
    /// after it would SELECT All Mail again. The first check after the
    /// search ends finds what came meanwhile.
    ///
    /// Nor for the folder's page kept on the iPad (D-016), whose rows are an
    /// earlier launch's word: a check would search from the lowest of them
    /// and put new letters on top of a page the server has not vouched for.
    /// The first check that reaches the server fetches the page afresh
    /// instead (`MessageListViewController.checked`).
    func toWatch(fromNewest: Bool, fetched: Bool) -> [String]? {
        guard fromNewest, !isSearching, !fromShelf, fetched || !folder.isEmpty else { return nil }
        return watched
    }

    /// The watch's news, for this list if it still starts at the folder's
    /// newest letter (`fromNewest`): held, to go on when he is at the top
    /// (`putNewsOn`). A day jumped to while the check was out has another
    /// top, and does not take it; the next check searches for it again.
    func take(_ news: FolderNews, fromNewest: Bool) -> NewsTaken {
        guard fromNewest else { return .notTaken }
        return hold(news) ? .new : .known
    }

    /// Takes the watch's news, to go on the list when `showNews` is called.
    /// Returns whether any of it was news to the list. A letter already
    /// held, or already on the list, is not, and nor is a letter gone that
    /// is already off it: the watch reports it again whenever something
    /// else changes, since it goes by the letters the list holds, and a
    /// letter taken off is still held for paging (`RemovedLetters`).
    @discardableResult
    func hold(_ news: FolderNews) -> Bool {
        var changed = false
        if news.refetch, !refetchOwed {
            refetchOwed = true
            changed = true
        }
        let known = Set(watched)
        let fresh = news.arrived.filter { !known.contains($0.id) }
        if !fresh.isEmpty {
            arriving = fresh + arriving
            changed = true
        }
        for id in news.gone {
            if let held = arriving.firstIndex(where: { $0.id == id }) {
                // Came and went while he was scrolled down: never shown.
                arriving.remove(at: held)
                changed = true
            } else if folder.contains(where: { $0.id == id }), !removed.hides(id),
                      leaving.insert(id).inserted {
                changed = true
            }
        }
        return changed
    }

    /// What becomes of the news held, with him where he is now.
    enum NewsStep: Equatable {
        /// Nothing yet: nothing is held, or he is somewhere it would move
        /// something under him (`ListPlaces.showsNews`).
        case wait
        /// The list is to be fetched afresh (`refetchOwed`), which puts on
        /// what is held with the rest.
        case refetch
        /// The new letters have gone on, these, whose previews are still to
        /// be fetched, and the ones gone elsewhere have come off.
        case shown([MessageSummary])
    }

    /// Puts what is held on the list if he is where that moves nothing under
    /// him: at the top of the folder's letters, no search showing or typed,
    /// nothing ticked, no finger on the list. For the message list at every
    /// check, and whenever one of those may have just become true.
    func putNewsOn(atTop: Bool, searching: Bool, ticked: Bool, touching: Bool) -> NewsStep {
        guard holdsNews,
              ListPlaces.showsNews(atTop: atTop, searching: searching, ticked: ticked,
                                   touching: touching) else { return .wait }
        if refetchOwed { return .refetch }
        return .shown(showNews())
    }

    /// Puts what is held on the list: the new letters at the top of the
    /// folder's, and the ones gone elsewhere off it. Returns the letters put
    /// on, whose previews are still to be fetched.
    ///
    /// A letter gone is taken off as a removal the server has made, the way
    /// a Delete from the reading pane is once its MOVE has landed: hidden,
    /// and kept for paging, which asks for the next page from the last
    /// letter the last page gave (`RemovedLetters`). The next Refresh has
    /// the say, as it has over every letter taken off.
    @discardableResult
    func showNews() -> [MessageSummary] {
        let added = arriving
        folder.insert(contentsOf: added, at: 0)
        for id in leaving {
            removed.take(id)
            removed.land(id)
        }
        arriving = []
        leaving = []
        return added
    }

    /// The list fetched afresh, or replaced by a day: whatever was held
    /// belongs to letters that are gone, and the new list has its own.
    private func dropNews() {
        arriving = []
        leaving = []
        refetchOwed = false
    }

    // MARK: - Read and unread

    /// The dot, wherever the list holds the letter.
    func setRead(_ id: String, read: Bool) {
        change(id) { $0.isRead = read }
    }

    /// His read mark on its way to the server: the dot now, wherever the
    /// list holds the letter, and held over what a listing brings until
    /// the server has answered (`readAnswered`) and a listing asked after
    /// that has come. See `holdingHisMarks`.
    func reading(_ id: String, read: Bool) {
        let row = letter(id)
        reads[id] = Mark(value: read, before: row?.isRead ?? !read, letter: row?.gmailMessageID)
        setRead(id, read: read)
    }

    /// The server has answered his read mark on `id`. Taken, it stays on
    /// over a listing asked before now, and one asked after has the say.
    /// Refused, the dot goes back as it was, on the letter he made it on
    /// and not on another the same id names now, and nothing is held.
    func readAnswered(_ id: String, landed: Bool) {
        guard var mark = reads[id] else { return }
        guard !landed else {
            mark.takenAt = asked
            reads[id] = mark
            return
        }
        reads[id] = nil
        change(id, ifStill: mark.letter) { $0.isRead = mark.before }
    }

    // MARK: - His own marks over a listing

    /// His read marks and flags on the list's letters, by id, from the
    /// moment he makes each until a listing from the top asked after the
    /// server took it has come.
    ///
    /// A listing asked before brings the letter's flags from before his
    /// STORE, and fetched afresh it put the unread dot back on the letter
    /// he had just opened, or took off the flag he had just set, while the
    /// server had what he did; the dot stayed until the next Refresh. A
    /// Refresh made while a STORE was on its way did it; with the copy kept
    /// on the iPad (D-016) it is the ordinary launch, a tap on a kept row
    /// made while the first page is on the wire, and the STORE queued
    /// behind it.
    private var reads: [String: Mark] = [:]
    private var flags: [String: Mark] = [:]
    /// The ids each Flag on its way was set on: the letter's, and its
    /// copies' under other mailboxes' ids (`setFlagged`).
    private var flagging: [String: [String]] = [:]
    /// Listings from the top asked for this list, counted, so a mark knows
    /// which of them were asked after the server took it.
    private var asked = 0

    private struct Mark {
        /// What he made it, and what the row said before, for a refusal.
        var value: Bool
        var before: Bool
        /// Gmail's id for the letter he made it on: it goes on that letter
        /// alone, and not on another the same id names in a listing that
        /// has thrown a kept page away (`ListEdit.sameLetter`).
        var letter: UInt64?
        /// `asked` when the server took it; nil while it is on its way.
        var takenAt: Int?

        /// Whether the listing `asked` was asked after the server took it,
        /// and so brings it: the listing has the say from then on.
        func seen(by asked: Int) -> Bool {
            takenAt.map { asked > $0 } ?? false
        }
    }

    /// A listing of the folder from the top is being asked for: what it
    /// brings goes to `fetchedAfresh` or `fetchedUnderSearch` with this.
    func askingAfresh() -> Int {
        asked += 1
        return asked
    }

    /// `page`, with his marks on it where the listing it came from was
    /// asked before the server took them, or while they are still on their
    /// way; the marks a listing asked since has seen go, and it has the
    /// say. Only on the letter each was made on.
    private func holdingHisMarks(_ page: [MessageSummary], asked listing: Int?) -> [MessageSummary] {
        let listing = listing ?? asked + 1
        reads = reads.filter { !$0.value.seen(by: listing) }
        flags = flags.filter { !$0.value.seen(by: listing) }
        guard !reads.isEmpty || !flags.isEmpty else { return page }
        return page.map { row in
            var row = row
            if let mark = reads[row.id], ListEdit.sameLetter(mark.letter, row.gmailMessageID) {
                row.isRead = mark.value
            }
            if let mark = flags[row.id], ListEdit.sameLetter(mark.letter, row.gmailMessageID) {
                row.isFlagged = mark.value
            }
            return row
        }
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
    ///
    /// Held over what a listing brings, as a read mark is (`reading`),
    /// until the server has answered (`flagAnswered`).
    func setFlagged(_ flagged: Bool, on letter: MessageSummary) {
        let known = self.letter(letter.id) ?? letter
        let twins = ListEdit.twins(of: known, among: everything)
        for copy in [known] + twins {
            flags[copy.id] = Mark(value: flagged, before: copy.isFlagged, letter: copy.gmailMessageID)
            change(copy.id) { $0.isFlagged = flagged }
        }
        flagging[letter.id] = [known.id] + twins.map(\.id)
        changed()
    }

    /// The server has answered his Flag on `letter`. Taken, it stays on
    /// over a listing asked before now. Refused, it goes back as it was on
    /// every copy it was set on that is still that letter, and nothing is
    /// held.
    func flagAnswered(_ letter: MessageSummary, landed: Bool) {
        for id in flagging.removeValue(forKey: letter.id) ?? [letter.id] {
            guard var mark = flags[id] else { continue }
            if landed {
                mark.takenAt = asked
                flags[id] = mark
            } else {
                flags[id] = nil
                change(id, ifStill: mark.letter) { $0.isFlagged = mark.before }
            }
        }
        if !landed { changed() }
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

    /// `change`, where the row under `id` is still the letter `letter`.
    private func change(_ id: String, ifStill letter: UInt64?,
                        _ edit: (inout MessageSummary) -> Void) {
        change(id) { row in
            if ListEdit.sameLetter(letter, row.gmailMessageID) { edit(&row) }
        }
    }
}

