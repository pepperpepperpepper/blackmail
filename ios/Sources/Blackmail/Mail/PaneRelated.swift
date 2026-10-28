import Foundation

/// His own letters from Sent Mail in the conversation the reading pane
/// shows (B-104), as the pane holds them: which they are, by the ids of
/// their entries in the stack, which of their bodies have come, what is
/// fetched when he opens one and which section its body goes into, which
/// letter a picture tapped in one is of (B-122), and whether the lookup for
/// them is still to start.
///
/// Out of `MessageDetailViewController` for the reason `PaneLoads` is: the
/// controller is UIKit and does not exist on the machine the suite runs on,
/// and a pane where none of his letters could ever be opened, or where one
/// opened into another letter's section, passed every test while this
/// lived there.
///
/// Apart from the conversation's own letters on purpose: none of these is
/// ever in the pane's `threadSummaries`, `stackLetters` or `loaded`, or the
/// letter the header, the toolbar or the list's read marks act on. Read
/// only; held while the pane shows the conversation, and no longer.
struct PaneRelated {

    /// What opening one of his letters fetches: the letter itself, from
    /// its own folder, by its id there and Gmail's id for it, which the
    /// fetch checks (D-016); and the stack's entry its body goes into.
    /// `row` is his letter's line, which the reading pane opens as it opens
    /// a row (`MailRepository.openLetter`), from the copy kept on the iPad
    /// when it is there, and kept there once its body has come (B-159).
    struct Load: Equatable {
        let entryID: String
        let id: String
        let gmailMessageID: UInt64?
        let mailboxID: String
        let row: MessageSummary
    }

    /// His letters of the conversation shown, by their entries' ids, "r"
    /// and the letter's id (`ConversationDocument.relatedID`).
    private var letters: [String: MessageSummary] = [:]
    /// Those whose bodies have come and are in their sections.
    private var came: Set<String> = []
    /// Those letters as they came, by their entries' ids, for a picture
    /// tapped in one (B-122), which opens from that letter's own parts.
    private var opened: [String: Message] = [:]
    /// The conversation to look his letters up for once its newest letter
    /// has come, nil when no lookup is to start.
    private var due: UInt64?

    /// The pane shows something else, or nothing.
    mutating func clear() {
        letters = [:]
        came = []
        opened = [:]
        due = nil
    }

    /// A conversation shown, `stack` its letters, the oldest first, and
    /// `completing` its Gmail thread number when his letters of it are
    /// wanted (`CompleteThreads.thread(toComplete:)`). `remembered` is what
    /// the repository found for it in the last ten minutes, if anything:
    /// returned less the stack's own, for the stack's first frame. With
    /// nothing remembered, the lookup is due, to start once the newest
    /// letter has come (`lookUp(afterTheNewestCame:)`).
    ///
    /// `kept` is what the copy kept on the iPad holds for it (B-159), the
    /// last lookup's answer from any launch: with nothing remembered it is
    /// returned instead, for the stack's first frame, as Mail draws his
    /// replies from what it has downloaded, and the lookup is still due,
    /// so with a connection the server's answer adds what has come since
    /// (`take`). With none, a lookup gives none and they stay.
    mutating func show(_ stack: [MessageSummary], completing: UInt64?,
                       remembered: RelatedLetters?,
                       kept: RelatedLetters? = nil) -> RelatedLetters? {
        clear()
        guard let completing else { return nil }
        if remembered == nil { due = completing }
        guard let first = remembered ?? kept else { return nil }
        let his = Self.apart(first, from: stack)
        for letter in his.letters { letters[ConversationDocument.relatedID(of: letter)] = letter }
        return his
    }

    /// The conversation's newest letter has settled: the thread number to
    /// look his letters up for, once, if it came and the lookup is due; nil
    /// otherwise. After the newest letter and not with it, so the lookup
    /// never takes the connection ahead of the letter he opened, and finds
    /// the connection that letter's fetch made: started as the stack
    /// opened, it found none after a while away, gave none, and his letters
    /// came at the next opening and not this one.
    mutating func lookUp(afterTheNewestCame newestCame: Bool) -> UInt64? {
        defer { due = nil }
        return newestCame ? due : nil
    }

    /// What the lookup found, for the conversation as `stack` has it now,
    /// the oldest first: his letters less the stack's own, and less those
    /// in it already, from the copy kept on the iPad (`show`), in runs,
    /// each as the stack's entries to put in before its letter `before`,
    /// nil for after the last (`PaneDocument.insert`).
    mutating func take(_ found: RelatedLetters,
                       stack: [MessageSummary]) -> [(entries: [ConversationDocument.Entry], before: String?)] {
        guard !stack.isEmpty else { return [] }
        var his = Self.apart(found, from: stack)
        his.letters.removeAll { letters[ConversationDocument.relatedID(of: $0)] != nil }
        return ConversationDocument.places(of: his.letters, among: stack).map { place in
            for letter in place.letters { letters[ConversationDocument.relatedID(of: letter)] = letter }
            return (place.letters.map { ConversationDocument.entry(forHis: $0, foundIn: his.folderName) },
                    place.before)
        }
    }

    /// The entry of his letter whose line is the section `sectionID`, nil
    /// for any other section: a letter of the conversation's.
    func entryID(forSection sectionID: String) -> String? {
        letters.keys.first { ConversationDocument.sectionID(for: $0) == sectionID }
    }

    /// What opening his entry `entryID` fetches; nil for an entry not his,
    /// or one whose body is in its section already.
    func load(for entryID: String) -> Load? {
        guard let letter = letters[entryID], !came.contains(entryID) else { return nil }
        return Load(entryID: entryID, id: letter.id, gmailMessageID: letter.gmailMessageID,
                    mailboxID: letter.mailboxID, row: letter)
    }

    /// The body `load` fetched has come: the entry it goes into, his own,
    /// whose section is "mr…", and never the letter's id, which can be an
    /// Inbox letter's too. Not fetched again.
    mutating func bodyCame(for load: Load) -> String {
        came.insert(load.entryID)
        return load.entryID
    }

    /// The letter `load` fetched has come, `m`: kept while the pane shows
    /// the conversation, for a picture tapped in it (B-122). Only the letter
    /// asked for, by its id, and only an entry of the conversation shown.
    /// Kept with its row's arrival in Sent Mail, which a Markup and Reply
    /// on a file of it goes by, as the pane's letters do
    /// (`Message.headerDate`, B-178).
    mutating func keep(_ m: Message, for load: Load) {
        guard m.id == load.id, letters[load.entryID] != nil else { return }
        opened[load.entryID] = m.arriving(as: load.row)
    }

    /// His letter whose section is `sectionID` and has come, nil for any
    /// other: a letter of the conversation's, or his not opened yet.
    func letter(inSection sectionID: String) -> Message? {
        entryID(forSection: sectionID).flatMap { opened[$0] }
    }

    /// His letter `id` if it has come, nil for any other: for a file's row
    /// among its words (`BodyFiles`), whose link names the letter by its
    /// id. Unambiguous, as `apart` leaves out any of his letters whose id
    /// is a stack letter's.
    func letter(withID id: String) -> Message? {
        opened.values.first { $0.id == id }
    }

    /// Of `found`, the letters that are not the stack's own: by Gmail's id,
    /// or by id, since each folder has a UIDVALIDITY of its own and nothing
    /// says a Sent Mail id is never an Inbox one. With his letter and one of
    /// the conversation's under the same id, the repository, which knows the
    /// letter it fetched last by its id alone when a picture or a file of it
    /// is asked for (`fetchAttachmentData`), would hand the one's in place
    /// of the other's.
    static func apart(_ found: RelatedLetters, from stack: [MessageSummary]) -> RelatedLetters {
        RelatedLetters(folderName: found.folderName,
                       letters: CompleteThreads.shown(found.letters,
                                                      besides: Set(stack.compactMap(\.gmailMessageID)),
                                                      apartFrom: Set(stack.map(\.id))))
    }
}
