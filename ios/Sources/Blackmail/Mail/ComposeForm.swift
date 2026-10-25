import Foundation

/// What the composer's form decides by itself, in the app and in the share
/// sheet (B-069): the title over the letter, whether Send is live, whether
/// Cancel asks, what an address field offers under it, and where the
/// letter opens ready to type (B-120).
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
        canSend(to: MailFormat.addresses(in: to), cc: MailFormat.addresses(in: cc),
                bcc: MailFormat.addresses(in: bcc))
    }

    /// The same, for fields read a recipient at a time, as the composers'
    /// bubbles are (`RecipientBubbles.recipients`).
    static func canSend(to: [String], cc: [String], bcc: [String]) -> Bool {
        var letter = Draft()
        letter.to = to
        letter.cc = cc
        letter.bcc = bcc
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
        /// He has tapped a bubble in it, its menu going up. Offers
        /// nothing: the list closes, so it is never under the menu, as
        /// Mail never has a person's card and the list up at once
        /// (B-134). Letters typed after it take the bubble's place and
        /// offer again (`RecipientBubbles.typingTakesThePicked`).
        case bubbleTapped
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
        suggestions(book, present: MailFormat.addresses(in: field), typing: field,
                    after: event, limit: limit)
    }

    /// The same, for a field of bubbles (B-076): matched against what he
    /// is typing after the bubbles, and nobody offered who is already in a
    /// bubble or typed (`RecipientBubbles.recipients`), a bubble counted as
    /// one recipient however its words read.
    ///
    /// Nothing while a bubble is picked out (B-134), which with letters on
    /// the line is a bubble whose menu is up: the list would open under the
    /// menu, only its lowest row in sight. Mail's field has no list while
    /// its selection is a recipient. Letters typed over the bubble take
    /// its place (`RecipientBubbles.typingTakesThePicked`), its menu goes,
    /// and the list is offered for them; whatever else changes the line
    /// under the menu, a comma in the middle of it or a letter taken back,
    /// offers nothing until the menu goes.
    static func suggestions(_ book: [KnownRecipient], in field: RecipientBubbles, after event: FieldEvent,
                            limit: Int = RecipientBook.suggestionLimit) -> [KnownRecipient] {
        guard field.selected == nil else { return [] }
        return suggestions(book, present: field.recipients, typing: field.typed, after: event, limit: limit)
    }

    /// The rows for `typing`, its last recipient begun the query, leaving
    /// out everyone `present`.
    private static func suggestions(_ book: [KnownRecipient], present: [String], typing: String,
                                     after event: FieldEvent, limit: Int) -> [KnownRecipient] {
        guard event == .typed else { return [] }
        let typed = MailFormat.currentRecipientToken(in: typing)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, !typed.contains("@") else { return [] }
        let present = Set(present
            .map { MailFormat.bareAddress($0).lowercased() }
            .filter { !$0.isEmpty })
        return RecipientBook.rank(book.filter { !present.contains($0.address.lowercased()) },
                                  matching: typed, limit: limit)
    }

    // MARK: - Cc and Bcc

    /// Whether Cc and Bcc stand open as the caret goes into a field, the
    /// "Cc/Bcc" row gone while they do, or are folded back into that row
    /// (B-134). `inCcOrBcc` is whether the field is Cc or Bcc; `cc` and
    /// `bcc` the people in them as the fields hold them.
    ///
    /// Mail's rule, read from its composer in iOS 18.6 (MessageUI,
    /// `-[MFMailComposeView viewDidBecomeFirstResponder:]` and
    /// `_updateOptionalHeaderVisibilityForceVisible:`), but for one thing:
    /// each time a field takes the caret, Cc and Bcc show while the caret
    /// is in one of them or Cc holds someone, and fold back otherwise.
    /// While they show, its "Cc/Bcc, From:" row is hidden (alpha 0 in its
    /// layout); its tap shows them and puts the caret in Cc
    /// (`_multiFieldClicked`). There is no From row here: the app sends
    /// from the one account.
    ///
    /// The one thing: Mail counts someone in Bcc only once its Bcc differs
    /// from the one the letter opened with
    /// (`-[MFMailComposeController bccAddressesDirtied]`, against
    /// `_originalBccAddresses`, as Always Bcc Myself or a draft opened
    /// again gives it), and folds an unchanged Bcc out of sight. Here
    /// anyone in Bcc keeps them open, on purpose, as the composer always
    /// has: a Bcc he cannot see is a copy going somewhere he never agreed
    /// to.
    static func showsCcAndBcc(inCcOrBcc: Bool, cc: [String], bcc: [String]) -> Bool {
        inCcOrBcc || !people(cc).isEmpty || !people(bcc).isEmpty
    }

    // MARK: - Ready to type

    /// Where a letter opens, the caret in it and the keyboard up (B-120).
    enum FirstField: Equatable {
        /// To: a new letter, a forward, any letter to nobody yet.
        case to
        /// Subject: a letter to someone that has no subject yet.
        case subject
        /// The body, the caret at its start, above his signature and a
        /// reply's quote.
        case body
    }

    /// Mail's own choice, read from its composer in iOS 18.6
    /// (`-[MFMailComposeController pickInitialFirstResponder]`, MessageUI):
    /// To while it holds no one; then Subject while it is empty; then the
    /// body, the caret at the body's start (`placeCaretAtStartOfBodyField`).
    /// Mail has no case of its own for a reply, a forward, its share sheet
    /// or a draft reopened from Drafts: each is these three questions, so a
    /// reply opens in the body above the quote and a forward in To.
    ///
    /// `to` is To's recipients as the field holds them, `subject` Subject's
    /// text as it is: Mail asks whether its length is nought, so a subject
    /// of spaces is a subject.
    static func firstField(to: [String], subject: String) -> FirstField {
        if people(to).isEmpty { return .to }
        if subject.isEmpty { return .subject }
        return .body
    }

    /// Whether the sheet is made ready to type as it appears: the first time
    /// only (`done` is whether that time has come and gone), never with an
    /// alert or another sheet up over it (`covered`), and never once he is
    /// in a field himself (`inAField`), so the caret he has put somewhere
    /// is never moved.
    static func readiesOnAppearing(done: Bool, covered: Bool, inAField: Bool) -> Bool {
        !done && !covered && !inAField
    }
}
