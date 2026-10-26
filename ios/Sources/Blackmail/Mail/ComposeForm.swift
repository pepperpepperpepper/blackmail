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

    /// The rows the address field offers under it, from `book` and his
    /// Contacts (`contacts`, B-162, ranked by `AddressSuggestions`), after
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
    static func suggestions(_ book: [KnownRecipient], contacts: [ContactCard] = [], field: String,
                            after event: FieldEvent,
                            limit: Int = RecipientBook.suggestionLimit) -> [KnownRecipient] {
        suggestions(book, contacts: contacts, present: MailFormat.addresses(in: field), typing: field,
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
    static func suggestions(_ book: [KnownRecipient], contacts: [ContactCard] = [],
                            in field: RecipientBubbles, after event: FieldEvent,
                            limit: Int = RecipientBook.suggestionLimit) -> [KnownRecipient] {
        guard field.selected == nil else { return [] }
        return suggestions(book, contacts: contacts, present: field.recipients, typing: field.typed,
                           after: event, limit: limit)
    }

    /// The rows for `typing`, its last recipient begun the query, leaving
    /// out everyone `present`. His Contacts by the same rules as the book:
    /// nothing until he types, nothing once he has typed an "@", nobody
    /// already in the field (B-162).
    private static func suggestions(_ book: [KnownRecipient], contacts: [ContactCard], present: [String],
                                     typing: String, after event: FieldEvent,
                                     limit: Int) -> [KnownRecipient] {
        guard event == .typed else { return [] }
        let typed = MailFormat.currentRecipientToken(in: typing)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, !typed.contains("@") else { return [] }
        let present = Set(present
            .map { MailFormat.bareAddress($0).lowercased() }
            .filter { !$0.isEmpty })
        return AddressSuggestions.rank(book: book, contacts: contacts, matching: typed,
                                       besides: present, limit: limit)
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

    // MARK: - How much of a letter the composer is given

    /// The most of any letter the app's composer is given: 128 KiB of
    /// UTF-8, about sixty pages, as much as Print prints of a plain letter
    /// (`PrintPage.textLimit`). Twice a quote's own ceiling
    /// (`QuotedOriginal.largestWords`), so a reply or a forward made here,
    /// his words and signature above its quote, comes under it whole.
    ///
    /// The composer's body is a text view as tall as its words, laid out
    /// and drawn whole as the sheet comes up; given about 1.7 MB of a
    /// letter's words, the sheet never came and the app took no touch for
    /// ten minutes (B-140). A reply or a forward bounds its quote as it is
    /// made. This is for every other letter the composer opens on: a draft
    /// reopened from Drafts, one written in another client or saved by a
    /// build before the bound, a letter kept on the iPad or waiting in the
    /// Outbox, a `mailto:` link's body.
    static let largestBody = 128 << 10

    /// The most lines of any letter the composer is given, under
    /// `largestBody` too: 4,000, twice a quote's (`QuotedOriginal.
    /// largestLines`), so a reply or a forward made here comes under it
    /// whole. The text view does some work for every line whatever its
    /// length, and 128 KiB of one-letter lines is some 65,000 of them,
    /// more than the 55,000 that froze the app. Chosen, not measured
    /// (B-140's check times the composer at each bound).
    static let largestLines = 4_000

    /// `draft` as the composer opens on it: its body bounded
    /// (`bounded(body:)`), all else as it is. A quote it carries no longer
    /// ends the body once the body is cut, so the letter's HTML is made
    /// from the words he sees (`QuotedOriginal.isIntact`).
    static func bounded(_ draft: Draft) -> Draft {
        var bounded = draft
        bounded.body = Self.bounded(body: draft.body)
        return bounded
    }

    /// `body` whole when it fits in `largestBody` and `largestLines`; else
    /// the whole lines of it that fit (`QuotedOriginal.cut`), and under
    /// them a blank line and "Only the beginning of this message is shown."
    /// (`QuotedOriginal.shortenedEnding`), both after "> " when the last
    /// line kept is a quote's, as a reply's quote of a letter shown in part
    /// ends. `more` when `body` is itself only the beginning of the
    /// letter's words (`Message.quotableText(within:)`): it is cut and
    /// ended so even when it fits.
    ///
    /// What is cut off is not kept anywhere for him. Sent, or saved over
    /// the draft, the letter is what the composer showed, as with any
    /// change he makes; closed untouched, nothing is saved, and the copy in
    /// Drafts keeps all of it. A body cut here is nearly always a quote's
    /// end: his own words would have to run to sixty pages first.
    static func bounded(body: String, more: Bool = false) -> String {
        // Lines counted only of a body whose bytes fit, so no further
        // than `largestBody`.
        if !more, body.utf8.count <= largestBody,
           body.utf8.lazy.filter({ $0 == 0x0A }).count < largestLines {
            return body
        }
        let ending = QuotedOriginal.shortenedEnding
        // Room for the ending, and for the two "> " it can be given; its
        // two lines among the most.
        let room = largestBody - ending.utf8.count - 4
        let kept = QuotedOriginal.cut(body, within: room, lines: largestLines - 2, more: more) ?? body
        let bytes = kept.utf8
        let lastLine = bytes.lastIndex(of: 0x0A).map { bytes.index(after: $0) } ?? bytes.startIndex
        let quoted = bytes[lastLine...].first == UInt8(ascii: ">")
        return kept + (quoted ? ending.replacingOccurrences(of: "\n", with: "\n> ") : ending)
    }
}
