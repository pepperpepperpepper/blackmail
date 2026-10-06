import Foundation

/// What the composer's form decides by itself, in the app and in the share
/// sheet (B-069): the title over the letter, whether Send is live, whether
/// Cancel asks, and what an address field offers under it.
///
/// Apple Mail on the iPad is the model for each. Out of the two sheets so
/// the suite can run it; the sheets are UIKit.
enum ComposeForm {

    // MARK: - The title

    /// The title over the sheet: the subject as he types it, or "New
    /// Message" while there is none, as Mail's is.
    static func title(subject: String) -> String {
        let words = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? "New Message" : words
    }

    // MARK: - Send

    /// Whether Send is live: To, Cc or Bcc holds an address. Mail greys
    /// Send out until one does. The rule is the send's own, which refuses a
    /// letter to nobody (`Submission.recipients`), so Send is never live for
    /// a letter that would only say "Message was not sent."
    static func canSend(to: String, cc: String, bcc: String) -> Bool {
        var letter = Draft()
        letter.to = MailFormat.addresses(in: to)
        letter.cc = MailFormat.addresses(in: cc)
        letter.bcc = MailFormat.addresses(in: bcc)
        return !Submission.recipients(of: letter).isEmpty
    }

    // MARK: - Cancel

    /// Whether Cancel asks Save Draft or Delete Draft: when the letter is not
    /// as it opened, and has something in it.
    ///
    /// Mail closes a letter he never touched without a word, a new one, a
    /// reply or a forward alike. A new letter opens with his signature in
    /// it, so asking whenever the body had words asked every time. A letter
    /// emptied by hand closes without asking too, as it did before: there is
    /// nothing in it to keep.
    static func asksBeforeClosing(_ letter: Draft, opened: Draft) -> Bool {
        if letter.isEmptyLetter && Submission.recipients(of: letter).isEmpty { return false }
        return !isAsOpened(letter, opened)
    }

    /// The letter is as it opened: the same people in each field, the same
    /// subject, the same body to the character, and the same files.
    static func isAsOpened(_ letter: Draft, _ opened: Draft) -> Bool {
        people(letter.to) == people(opened.to)
            && people(letter.cc) == people(opened.cc)
            && people(letter.bcc) == people(opened.bcc)
            && letter.subject == opened.subject
            && letter.body == opened.body
            && sameFiles(letter, opened)
    }

    /// The same files, in the same order, from the same places.
    static func sameFiles(_ a: Draft, _ b: Draft) -> Bool {
        a.attachments.map(fileKey) == b.attachments.map(fileKey)
    }

    private static func people(_ field: [String]) -> [String] {
        field.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func fileKey(_ file: DraftAttachment) -> String {
        let place: String
        switch file.source {
        case let .localFile(url):
            place = url.standardizedFileURL.path
        case let .messagePart(messageID, mailboxID, section, letter):
            place = "\(mailboxID)\n\(messageID)\n\(section)\n\(letter.map(String.init) ?? "")"
        }
        return [place, file.filename, file.mimeType, file.size.map(String.init) ?? ""]
            .joined(separator: "\n")
    }

    // MARK: - Suggestions

    /// What has just happened in an address field. Only `typed` can offer
    /// anything (B-073).
    enum FieldEvent {
        /// He has gone into it. Offers nothing, as in Mail.
        case entered
        /// He has typed in it, or taken something out.
        case typed
        /// He has picked an address from the list under it. Offers
        /// nothing until he types again.
        case picked
    }

    /// The rows the address field offers under it, from `book`, after
    /// `event`, with `field` as it now reads.
    ///
    /// Mail offers addresses only while he types a name or an address.
    /// Going into a field offers nothing, empty or not, and so does a pick:
    /// the list closes and comes back only when he types again. Taking out
    /// what he typed, back to nothing, closes it too. So only typing offers
    /// anything, and only with something typed after the last comma.
    ///
    /// Until B-073 an empty field offered his most used as he went into it,
    /// to make his own second address one tap. The owner chose Mail's way
    /// on 2026-10-06. `RecipientBook.rank` still offers everyone for an
    /// empty query; it is never asked one from here.
    ///
    /// Nothing is offered once what he has typed holds an "@", and no
    /// address already in the field is offered again, in any spelling
    /// (B-069).
    static func suggestions(_ book: [KnownRecipient], field: String, after event: FieldEvent,
                            limit: Int = RecipientBook.suggestionLimit) -> [KnownRecipient] {
        guard event == .typed else { return [] }
        let typed = MailFormat.currentRecipientToken(in: field)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, !typed.contains("@") else { return [] }
        let present = Set(MailFormat.addresses(in: field)
            .map { MailFormat.bareAddress($0).lowercased() }
            .filter { !$0.isEmpty })
        return RecipientBook.rank(book.filter { !present.contains($0.address.lowercased()) },
                                  matching: typed, limit: limit)
    }
}
