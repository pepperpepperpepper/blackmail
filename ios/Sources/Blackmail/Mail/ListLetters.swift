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
    /// The previews the hits have drawn, for the next answer's hits as he
    /// types, and the letters drawn with no words, the folder's too
    /// (`SearchPreviews`, B-135).
    private var drawn = SearchPreviews()

    /// Drafts only: the letters kept on the iPad that the server does not
    /// have yet, as rows, and the ids of the server's copies they replace,
    /// each with Gmail's id for the letter named there. See
    /// `keep(_:replacing:)`.
    private(set) var kept: [MessageSummary] = []
    private var replaced: [String: UInt64?] = [:]

    /// A letter the pane changed, or took off or put back: the rows are to
    /// be regrouped and redrawn. Which of the three, so that a row put back
    /// can go back where it stood (`TakenRows`, B-093).
    var changed: (ListChange) -> Void = { _ in }
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
    /// to blank every preview and fetch them all again. A letter drawn with
    /// no words, as an empty draft is, is not asked for again either
    /// (`toDraw`): its row has no preview to carry, and every Refresh, and
    /// every page the watch fetched afresh, asked for it again, to be
    /// answered with nothing (B-135's check). And what was taken off by
    /// hand, the server now has the say on (`RemovedLetters`).
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
        return toDraw(folder)
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
    /// His own read marks and flags stay on over it, and a letter drawn
    /// with no words is not asked for again, as in `fetchedAfresh`.
    func fetchedUnderSearch(_ page: [MessageSummary], asked: Int? = nil) -> [MessageSummary] {
        folder = holdingHisMarks(ListEdit.carryingPreviews(from: folder, into: page), asked: asked)
        fromShelf = false
        dropNews()
        return toDraw(folder)
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
    /// A page of hits comes with the previews already drawn for its letters,
    /// as a search's first page does (`showResults`). Its previews still to
    /// be asked for, the folder's page's too, are `toDraw(_:)` of it.
    func appendPage(_ page: [MessageSummary], toResults: Bool) -> [MessageSummary] {
        let known = Set(visible.map(\.id))
        var fresh = page.filter { !known.contains($0.id) }
        if toResults {
            fresh = drawn.carrying(into: fresh, from: everything)
            let drew = fresh.filter { drawn.hasDrawn($0) }
            drawn.note(drew)
            results?.append(contentsOf: fresh)
        } else {
            folder.append(contentsOf: fresh)
        }
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

    /// A search's answer, in place of the hits or over the folder's
    /// letters. Returns the hits whose previews still have to be fetched.
    ///
    /// A hit takes the preview already drawn for its letter, among the
    /// folder's letters, the hits it replaces, or those the hits before them
    /// drew (`SearchPreviews`, B-135), and only the rest are asked for. Each
    /// pause in his typing brings an answer, and every hit of each was
    /// asked for again, though most are the letters the last answer found
    /// and drew a moment before. A hit whose letter was drawn with no words,
    /// as an empty draft is, is drawn, and is not asked for either.
    @discardableResult
    func showResults(_ hits: [MessageSummary]) -> [MessageSummary] {
        let carried = drawn.carrying(into: hits, from: everything)
        let drew = carried.filter { drawn.hasDrawn($0) }
        drawn.note(drew)
        results = carried
        return toDraw(carried)
    }

    /// `rows` whose previews are still to be asked for: those with none,
    /// less those whose letters were drawn with no words (`SearchPreviews`,
    /// B-135's check). A row shows no preview the same either way, and
    /// asking again for a letter drawn with none is answered with none. A
    /// row with none whose letter was drawn with words is asked for: the
    /// words kept are for the hits to take, and the folder's rows never
    /// take them (`SearchPreviews.hasDrawn`).
    func toDraw(_ rows: [MessageSummary]) -> [MessageSummary] {
        rows.filter { !drawn.hasDrawn($0) }
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
    /// folder row's too, under the same folder and id
    /// (`apply(previews:in:)` fills both)
    /// or, for an All Mailboxes hit, under All Mail's
    /// (`ListEdit.carryingPreviews(fromTwins:into:)`). Letters taken off by
    /// hand are not asked for, nor letters drawn with no words (`toDraw`).
    @discardableResult
    func endSearch() -> [MessageSummary] {
        let hits = results ?? []
        results = nil
        folder = ListEdit.carryingPreviews(fromTwins: hits, into: folder)
        return toDraw(shown)
    }

    /// A group's previews, come for its rows of `mailboxID` (`PreviewPass`):
    /// drawn into the rows of that folder under those ids, the folder's own
    /// and the hits, and the hits' kept for the next answer (B-135). Not
    /// into a row of another folder under the same id: an id is a folder's
    /// UIDVALIDITY and UID, and another folder can give another letter the
    /// same, as `previewsCameLate` holds too. Drawn by id alone, an All
    /// Mail answer could fill a Trash hit, and the words kept under it
    /// would then be carried into every answer after.
    ///
    /// An empty preview in the answer is a letter drawn with no words
    /// (`MailRepository.previews`): kept as drawn, the folder's rows' too,
    /// so that no pass asks for it again (`toDraw`, B-135's check).
    func apply(previews: [String: String], in mailboxID: String) {
        var drew: [MessageSummary] = []
        for i in folder.indices where folder[i].mailboxID == mailboxID {
            guard let text = previews[folder[i].id] else { continue }
            folder[i].preview = text
            if text.isEmpty { drew.append(folder[i]) }
        }
        guard var hits = results else {
            drawn.note(drew)
            return
        }
        for i in hits.indices where hits[i].mailboxID == mailboxID {
            guard let text = previews[hits[i].id] else { continue }
            hits[i].preview = text
            drew.append(hits[i])
        }
        results = hits
        drawn.note(drew)
    }

    /// Previews that came for `rows` of `mailboxID` after the list had been
    /// replaced, by the next answer as he typed or a Refresh: drawn by no
    /// row, and kept for the hits of the next answer, which can be the same
    /// letters (B-135). They are the server's for those rows' letters as
    /// much as if they had come in time, an empty one a letter drawn with
    /// no words.
    func previewsCameLate(_ previews: [String: String], in mailboxID: String,
                          for rows: [MessageSummary]) {
        drawn.note(rows.compactMap { row -> MessageSummary? in
            guard row.mailboxID == mailboxID, let text = previews[row.id] else { return nil }
            var drew = row
            drew.preview = text
            return drew
        })
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
        let fresh = news.arrived.filter { !known.contains($0.id) }.map(withHisRead)
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

    /// A letter the watch has brought, with his read mark on it where he
    /// has made one on the letter that is still held (`reads`): on its way
    /// to the server, or taken and not yet seen by a listing asked after.
    /// Under its own id, or on another copy with the same Gmail message
    /// id: the All Mailboxes hit he read it from. The last he made, where
    /// there are two. A listing's rows take it the same way
    /// (`holdingHisMarks`), once the marks that listing has seen are gone:
    /// the Inbox's page asked before the STORE and come after it can bring
    /// a copy the list did not have when he read the hit.
    ///
    /// The check that brought it may have been asked before the STORE and
    /// come after it, with the letter as the server had it before: unread.
    /// Held, and put on at the top as it came, the Inbox's row had its dot
    /// back, though the letter was read and the counts had gone down for
    /// it (B-089). Held from here on as the copy's own mark, and put back
    /// with the others if the server refuses it (`readAnswered`).
    private func withHisRead(_ letter: MessageSummary) -> MessageSummary {
        let made = reads.filter { id, mark in
            id == letter.id
                ? ListEdit.sameLetter(mark.letter, letter.gmailMessageID)
                : mark.letter != nil && mark.letter == letter.gmailMessageID
        }.max { $0.value.order < $1.value.order }
        guard let (on, mark) = made else { return letter }
        reads[letter.id] = Mark(value: mark.value, before: letter.isRead,
                                letter: letter.gmailMessageID, takenAt: mark.takenAt,
                                order: mark.order)
        // Written back whole, not as `marking[tap]?.append(letter.id)`. A
        // change made in place inside a Dictionary compiles, with this
        // toolchain, to a coroutine that needs `swift_coroFrameAlloc`, which
        // the iOS 16 runtime does not have, and the device link fails.
        if mark.takenAt == nil,
           let tap = marking.first(where: { $0.value.contains(on) })?.key,
           let ids = marking[tap], !ids.contains(letter.id) {
            marking[tap] = ids + [letter.id]
        }
        var letter = letter
        letter.isRead = mark.value
        return letter
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

    /// His read mark on its way to the server: the dot now, wherever the
    /// list holds the letter, and held over what a listing brings until
    /// the server has answered (`readAnswered`) and a listing asked after
    /// that has come. See `holdingHisMarks`.
    ///
    /// On the letter and on its copies under other mailboxes' ids, by its
    /// Gmail message id (`ListEdit.copies`), as a flag is (`setFlagged`).
    /// Read from an All Mailboxes hit, the Inbox's row under the search
    /// kept its dot, though the server had the letter as read and the
    /// Inbox's count had gone down; cancelling the search puts that row
    /// back without a round trip, so the dot stayed until the Inbox was
    /// fetched again (B-089). Matched from the list's copy, falling back to
    /// the letter itself when the list has no row with its id: one the
    /// reading pane opens from a hit after the search has ended.
    ///
    /// The watch's news held for the list (`arriving`) too: the Inbox's
    /// copy of a letter that came while he was scrolled down, which he
    /// then read from its hit, went on at the top with its dot. A copy the
    /// watch brings after the mark is made takes it as it comes
    /// (`withHisRead`).
    func reading(_ letter: MessageSummary, read: Bool) {
        let known = self.letter(letter.id) ?? letter
        let copies = [known] + ListEdit.copies(of: known, among: everything + arriving)
        marksMade += 1
        for copy in copies {
            reads[copy.id] = Mark(value: read, before: copy.isRead, letter: copy.gmailMessageID,
                                  order: marksMade)
            change(copy.id, ifStill: copy.gmailMessageID) { $0.isRead = read }
        }
        marking[letter.id] = copies.map(\.id)
    }

    /// The server has answered his read mark on `id`. Taken, it stays on
    /// over a listing asked before now, and one asked after has the say.
    /// Refused, the dot goes back as it was, on every copy it was made on
    /// that is still that letter and not on another the same id names now,
    /// the watch's news held among them, and nothing is held.
    func readAnswered(_ id: String, landed: Bool) {
        for copy in marking.removeValue(forKey: id) ?? [id] {
            guard var mark = reads[copy] else { continue }
            if landed {
                mark.takenAt = asked
                reads[copy] = mark
            } else {
                reads[copy] = nil
                change(copy, ifStill: mark.letter) { $0.isRead = mark.before }
            }
        }
    }

    /// The reading pane's Mark as Unread or Mark as Read, at the tap
    /// (B-106): the dot as a tap on a row changes it, on the letter and its
    /// copies, held over a listing until the server has answered
    /// (`reading`), and the rows redrawn, as for a Flag.
    func setRead(_ read: Bool, on letter: MessageSummary) {
        reading(letter, read: read)
        changed(.marked)
    }

    /// The server has taken a read mark made on `letter`, the list's copy
    /// of it as it was before the mark: from Edit mode's Mark, which makes
    /// the mark once the STORE has landed, or from the reading pane's,
    /// which made it at the tap. Held over a listing asked before now
    /// (`readAnswered`), and billed: one off every folder the letter is
    /// counted in, once per letter however often it is asked (`read`), or
    /// one back on, and its billing forgotten (`unread`), so reading it
    /// again takes the one off again, once.
    ///
    /// Nothing comes off or goes on when the list had the letter so
    /// already: the count was right before the STORE. Edit mode marks only
    /// the letters whose dot says otherwise, so for it this is the
    /// bookkeeping it always did. The pane's sheet offers its item by the
    /// row's dot (`dot(on:)`), but the dot can change between the sheet
    /// opening and the item's tap, the read mark of the tap that opened the
    /// letter refused and put back meanwhile: a Mark as Unread then put one
    /// on for a letter that was counted already, one too many until the
    /// next sweep.
    func readTaken(_ letter: MessageSummary, read: Bool) {
        readAnswered(letter.id, landed: true)
        guard letter.isRead != read else { return }
        if read { self.read(letter) } else { unread(letter) }
    }

    /// The server refused the reading pane's read mark on `letter`, or it
    /// was never sent: the dot back as it was, on every copy it was made
    /// on that is still that letter (`readAnswered`), and the rows redrawn.
    func readRefused(_ letter: MessageSummary) {
        readAnswered(letter.id, landed: false)
        changed(.marked)
    }

    /// The dot on the list's row for a letter the reading pane shows, for
    /// its Flag button's sheet to offer Mark as Unread or Mark as Read by
    /// (B-106), as Mail's item follows the letter: read or not as the row
    /// says, and whether a read mark made on it, or on a copy of it under
    /// another mailbox's id, is still on its way to the server.
    ///
    /// The row's and not the pane's. The row's changes at the tap that
    /// opens the letter, at Edit mode's Mark, which leaves the pane as it
    /// was, and back again when the server refuses either, and the pane is
    /// told of none of them.
    ///
    /// Nil when the list has no row under the letter's id, a hit after its
    /// search has ended, or the row there is another letter now, a row
    /// kept on the iPad that a listing has put another letter under
    /// (`ListEdit.sameLetter`).
    func dot(on letter: MessageSummary) -> FlagMenu.Dot? {
        guard let row = self.letter(letter.id), ListEdit.sameLetter(row, letter) else { return nil }
        return FlagMenu.Dot(read: row.isRead,
                            onItsWay: marking.values.contains { $0.contains(letter.id) })
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
    /// The ids each read mark on its way was made on: the letter's, and
    /// its copies' under other mailboxes' ids (`reading`).
    private var marking: [String: [String]] = [:]
    /// The ids each Flag on its way was set on: the letter's, and its
    /// copies' under other mailboxes' ids (`setFlagged`).
    private var flagging: [String: [String]] = [:]
    /// Listings from the top asked for this list, counted, so a mark knows
    /// which of them were asked after the server took it.
    private var asked = 0
    /// Read marks made, counted, so the last of them on a letter is known.
    private var marksMade = 0

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
        /// `marksMade` when he made it; for a read mark only.
        var order = 0

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
            var row = withHisRead(row)
            if let mark = flags[row.id], ListEdit.sameLetter(mark.letter, row.gmailMessageID) {
                row.isFlagged = mark.value
            }
            return row
        }
    }

    /// The server has the letter as read: one off every folder it is
    /// counted in, once per letter however often it is asked, and on
    /// whichever of its copies (`ReadBilling`).
    func read(_ letter: MessageSummary) {
        guard let folders = billing.read(letter) else { return }
        onUnreadCountChanged(folders, -1)
    }

    /// The server has the letter as unread again: one back on, and its
    /// billing forgotten on every copy of it.
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
        changed(.taken(letter.id))
    }

    func putBack(_ letter: MessageSummary) {
        removed.putBack(letter.id)
        changed(.putBack(letter.id))
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
        changed(.marked)
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
        if !landed { changed(.marked) }
    }

    func shows(_ letter: MessageSummary) -> Bool {
        self.letter(letter.id) != nil && !removed.hides(letter.id) && !leaving.contains(letter.id)
    }

    /// Held as the watch's news of a letter gone elsewhere is (`hold`),
    /// with its twins among the hits and the folder's rows when it has
    /// left every folder: the folder's rows go with the rest when he is
    /// back at the top (`showNews`). A hit stays among the hits; they go
    /// as the search ends.
    func holdGone(_ letter: MessageSummary, fromEveryFolder: Bool) {
        let twins = fromEveryFolder ? ListEdit.twins(of: letter, among: everything) : []
        hold(FolderNews(gone: ([letter] + twins).map(\.id)))
    }

    /// The server has taken the mark written once a reply or a forward
    /// went (`OriginalLetter`, B-152): Mail's grey arrow on every row of
    /// that letter this list holds, by Gmail's id for it, the folder's, the
    /// hits and the news held to go on, as the next listing would draw it
    /// from the server's flags (B-102). Nothing for a list that holds none.
    func originalMarked(_ original: OriginalLetter) {
        guard (everything + arriving).contains(where: { $0.gmailMessageID == original.letter })
        else { return }
        folder = folder.map { $0.marking(original) }
        arriving = arriving.map { $0.marking(original) }
        results = results?.map { $0.marking(original) }
        changed(.marked)
    }

    /// Whether a Flag set on the letter `id` is on its way to the server:
    /// a swipe's Flag waits for it, as the pane's does (`PaneWrites`).
    func flagOnItsWay(_ id: String) -> Bool {
        flagging.values.contains { $0.contains(id) }
    }

    /// The flag on the list's row for a letter the reading pane shows, and
    /// whether a Flag set on it is on its way, as `dot(on:)` has the read
    /// mark: the Flag button's sheet offers Flag or Unflag by it. A drag's
    /// Flag or More's on the row (B-156) changes the row and not the pane.
    /// Nil where the list has no row that is the letter.
    func flag(on letter: MessageSummary) -> FlagMenu.Flag? {
        guard let row = self.letter(letter.id), ListEdit.sameLetter(row, letter) else { return nil }
        return FlagMenu.Flag(flagged: row.isFlagged, onItsWay: flagOnItsWay(letter.id))
    }

    /// The row the list shows now that is `letter`: under its id, or, in
    /// the same folder, under another id with its Gmail id, as a letter
    /// trashed and brought back by an Undo comes back under a new UID
    /// (B-157). Nil where it shows none.
    func shownRow(of letter: MessageSummary) -> MessageSummary? {
        let rows = shown
        if let same = rows.first(where: { $0.id == letter.id && $0.mailboxID == letter.mailboxID }) {
            return same
        }
        guard let gmail = letter.gmailMessageID else { return nil }
        return rows.first { $0.gmailMessageID == gmail && $0.mailboxID == letter.mailboxID }
    }

    /// A letter taken off by a Delete or a Move that its Undo has moved
    /// back to the folder it was taken from (B-157), `id` its id there now,
    /// a new UID: its row back where it stood, under `id`, in front of the
    /// one it was taken under, which stays hidden and still marks where
    /// paging has got to (`RemovedLetters`). Among a search's hits too,
    /// where it was one. Its read billing forgotten, so reading it again
    /// takes one off again; an unread letter whose leaving every folder
    /// took one off them (`removalLanded`) has it put back on, and the
    /// counts are swept besides by the Undo (`UndoMoves`).
    ///
    /// Returns false, with nothing changed, when the list no longer holds
    /// the row it was taken under: fetched afresh since, which the server
    /// has had the say on. The letter is in the folder all the same, and
    /// shows at the next listing, at the top, as Gmail gives it the next
    /// UID there (B-084).
    @discardableResult
    func restore(_ row: MessageSummary, as id: String) -> Bool {
        let back = row.renamed(id)
        var placed = false
        func put(_ letters: inout [MessageSummary]) {
            guard !letters.contains(where: { $0.id == id && $0.mailboxID == row.mailboxID }),
                  let at = letters.firstIndex(where: { $0.id == row.id
                                                      && $0.mailboxID == row.mailboxID })
            else { return }
            letters.insert(back, at: at)
            placed = true
        }
        put(&folder)
        if var hits = results {
            put(&hits)
            results = hits
        }
        guard placed else { return false }
        if !back.isRead, let folders = billing.returned(back) { onUnreadCountChanged(folders, 1) }
        changed(.putBack(row.id))
        return true
    }

    func addCountedFolder(_ name: String, to id: String) {
        change(id) { letter in
            guard !letter.countedFolderIDs.contains(name) else { return }
            letter.countedFolderIDs = ReadBilling.folders(of: letter) + [name]
        }
        changed(.marked)
    }

    /// Changes the letter with `id` wherever this list holds it, the
    /// folder's letters, the hits, and the watch's news held to go on.
    private func change(_ id: String, _ edit: (inout MessageSummary) -> Void) {
        ListEdit.change(&folder, id: id, edit)
        ListEdit.change(&arriving, id: id, edit)
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

/// What the reading pane, or Edit mode, has done to the list's letters, as
/// `ListLetters.changed` tells the controller.
enum ListChange: Equatable {
    /// The letter's row taken off at the tap of a Delete or a Move
    /// (`ListLetters.take`), by the letter's id.
    case taken(String)
    /// The letter's row put back, its Delete or Move refused or never sent
    /// (`ListLetters.putBack`), or moved back by its Undo (B-157,
    /// `ListLetters.restore`): by the id it was taken under.
    case putBack(String)
    /// A flag set or put back, or a folder the letter is filed in: no row
    /// in or out.
    case marked
}
