import XCTest
@testable import Blackmail

/// A ";" between addresses, as Mail takes it (B-081): it separates them as
/// a "," does, and one at the end, or two together, is nothing. A letter To
/// "jane@example.com;" went `RCPT TO:<jane@example.com;>`, which Gmail
/// answered 553 5.1.3, "not a valid RFC 5321 address", and he saw "Message
/// was not sent." Here the field, the bubbles, the send's recipients, the
/// letter's header and a header read back, as pure functions.
final class SemicolonLikeMailTests: XCTestCase {

    // MARK: - The field

    /// What he typed, split as the composer splits it: at a ";" as at a ",",
    /// a separator at the end or two together leaving nothing behind.
    func testASemicolonSeparatesAddressesInTheField() {
        let cases: [(String, [String])] = [
            ("jane@example.com;", ["jane@example.com"]),
            ("Jane Example <jane@example.com>;", ["Jane Example <jane@example.com>"]),
            ("a@example.com; b@example.com;", ["a@example.com", "b@example.com"]),
            ("a@example.com;b@example.com", ["a@example.com", "b@example.com"]),
            ("a@example.com;;b@example.com", ["a@example.com", "b@example.com"]),
            ("a@example.com,;b@example.com", ["a@example.com", "b@example.com"]),
            ("a@example.com; , b@example.com ,", ["a@example.com", "b@example.com"]),
            (";jane@example.com", ["jane@example.com"]),
            (";", []),
            (" ; ", []),
            (",;", []),
            ("; ,;; ,", []),
            ("", []),
        ]
        for (field, entries) in cases {
            XCTAssertEqual(MailFormat.addresses(in: field), entries, field)
        }
    }

    /// A ";" inside a quoted name, `<…>` or a comment is part of it, as a ","
    /// there is (B-061).
    func testASemicolonInsideANameOrAnAddressIsKept() {
        XCTAssertEqual(MailFormat.addresses(in: "\"Example; Jane\" <jane@example.com>; sam@example.com"),
                       ["\"Example; Jane\" <jane@example.com>", "sam@example.com"])
        XCTAssertEqual(MailFormat.addresses(in: "<\"a;b\"@example.com>; sam@example.com"),
                       ["<\"a;b\"@example.com>", "sam@example.com"])
        XCTAssertEqual(MailFormat.addresses(in: "jane@example.com (Jane; at home); sam@example.com"),
                       ["jane@example.com (Jane; at home)", "sam@example.com"])
    }

    /// A quote never closed splits the field at every separator, a ";" as a
    /// "," has always been split there.
    func testAQuoteNeverClosedSplitsAtEverySemicolonAsAtEveryComma() {
        XCTAssertEqual(MailFormat.addresses(in: "\"Sam; jane@example.com"),
                       ["\"Sam", "jane@example.com"])
        XCTAssertEqual(MailFormat.addresses(in: "\"Sam, jane@example.com"),
                       ["\"Sam", "jane@example.com"])
    }

    /// What is not an address is kept for him to see, without the
    /// separator, and refused at Send as it always was.
    func testWhatIsNotAnAddressIsKept() {
        XCTAssertEqual(MailFormat.addresses(in: "jan;"), ["jan"])
        XCTAssertEqual(MailFormat.addresses(in: "jan; sam@example.com"), ["jan", "sam@example.com"])
        XCTAssertTrue(ComposeForm.canSend(to: ["jan;"], cc: [], bcc: []))
    }

    // MARK: - The bubbles

    /// A ";" typed ends a recipient as a "," does: a bubble of what was
    /// before it, nothing for a ";" alone.
    func testASemicolonTypedMakesABubbleAsACommaDoes() {
        let cases: [(String, [String], String)] = [
            ("jane@example.com;", ["jane@example.com"], ""),
            ("Jane Example <jane@example.com>;", ["Jane Example <jane@example.com>"], ""),
            ("a@example.com; b@example.com;", ["a@example.com", "b@example.com"], ""),
            ("a@example.com; b@exa", ["a@example.com"], "b@exa"),
            ("a@example.com,;b@example.com;", ["a@example.com", "b@example.com"], ""),
            (";", [], ""),
            (" ; ", [], ""),
            (",;", [], ""),
            ("\"Example; Jane\" <jane@exa", [], "\"Example; Jane\" <jane@exa"),
        ]
        for (typed, entries, rest) in cases {
            var field = RecipientBubbles()
            field.type(typed)
            XCTAssertEqual(field.entries, entries, typed)
            XCTAssertEqual(field.typed, rest, typed)
            XCTAssertEqual(field.recipients, entries + MailFormat.addresses(in: rest), typed)
        }
        // A quote still open: the ";" in it ends nothing as he types, and
        // what he is typing reads as the field's text reads, a ";" as a
        // comma.
        var open = RecipientBubbles()
        open.type("\"Example; Jane\" <jane@exa")
        var comma = RecipientBubbles()
        comma.type("\"Example, Jane\" <jane@exa")
        XCTAssertEqual(open.entries, [])
        XCTAssertEqual(open.recipients, ["\"Example", "Jane\" <jane@exa"])
        XCTAssertEqual(comma.recipients, ["\"Example", "Jane\" <jane@exa"])
        // The same typed a character at a time, as he types.
        var field = RecipientBubbles()
        var line = ""
        for c in "Jane Example <jane@example.com>; sam@example.com;" {
            line.append(c)
            field.type(line)
            line = field.typed
        }
        XCTAssertEqual(field.entries, ["Jane Example <jane@example.com>", "sam@example.com"])
        XCTAssertEqual(field.typed, "")
        XCTAssertEqual(field.entries.map(RecipientBubbles.words(for:)), ["Jane Example", "sam@example.com"])
    }

    /// Return, or leaving the field, with a ";" in what he typed.
    func testReturnSplitsAtASemicolon() {
        var field = RecipientBubbles()
        field.type("\"Example; Jane\" <jane@example.com>")
        field.finish()
        XCTAssertEqual(field.entries, ["\"Example; Jane\" <jane@example.com>"])
        XCTAssertEqual(RecipientBubbles.words(for: field.entries[0]), "Example; Jane")
    }

    /// A field opened from a draft, a letter in the Outbox or a link, whose
    /// entries were kept with a ";" in them: a bubble for each address, none
    /// for a ";" alone.
    func testAFieldOpenedWithSemicolonsHasABubbleForEachAddress() {
        let field = RecipientBubbles(entries: ["jane@example.com;", ";", " ; ",
                                               "a@example.com; b@example.com;", ",;",
                                               "Sam Example <sam@example.com>;"])
        XCTAssertEqual(field.entries, ["jane@example.com", "a@example.com", "b@example.com",
                                       "Sam Example <sam@example.com>"])
        XCTAssertEqual(field.recipients, field.entries)
    }

    /// A pick whose entry has a ";" after it, as a book kept by an earlier
    /// build could offer one, makes the bubble of its address.
    func testAPickWithASemicolonIsItsAddress() {
        var field = RecipientBubbles()
        field.type("ja")
        field.pick("jane@example.com;")
        XCTAssertEqual(field.entries, ["jane@example.com"])
        field.pick(";")
        XCTAssertEqual(field.entries, ["jane@example.com"])
    }

    /// Send is live for an address with a ";" after it, and not for a ";"
    /// alone, which is nobody.
    func testSendIsGreyForASemicolonAlone() {
        XCTAssertFalse(ComposeForm.canSend(to: [";"], cc: [], bcc: []))
        XCTAssertFalse(ComposeForm.canSend(to: [" ; ", ",;"], cc: [";"], bcc: [" ;; "]))
        XCTAssertTrue(ComposeForm.canSend(to: ["jane@example.com;"], cc: [], bcc: []))
        XCTAssertFalse(ComposeForm.canSend(to: ";", cc: "", bcc: ""))
        XCTAssertTrue(ComposeForm.canSend(to: "jane@example.com;", cc: "", bcc: ""))
    }

    // MARK: - The letter

    private let account = MailAccount(address: "owner@example.com", username: "owner@example.com",
                                      displayName: "Carlo", signature: "")

    private func letter(to: [String], cc: [String] = [], bcc: [String] = []) -> Draft {
        var draft = Draft()
        draft.to = to
        draft.cc = cc
        draft.bcc = bcc
        draft.subject = "Lunch"
        draft.body = "One o'clock."
        return draft
    }

    /// Whom the letter goes to, To, Cc and Bcc: each address once for each
    /// time it is written, never a ";", never a blank.
    func testTheSendsRecipientsAreTheAddressesAlone() {
        let draft = letter(to: ["jane@example.com;", ";", "Jane Example <jane@example.org>;"],
                           cc: ["a@example.com; b@example.com;", " ; "],
                           bcc: [",;", "sam@example.com;;"])
        XCTAssertEqual(Submission.recipients(of: draft),
                       ["jane@example.com", "Jane Example <jane@example.org>",
                        "a@example.com", "b@example.com", "sam@example.com"])
        XCTAssertEqual(Submission.recipients(of: letter(to: [";", " ; ", ",;"])), [])
    }

    /// The letter's own header: To and Cc name exactly the recipients,
    /// joined by commas, with no ";" left in them, and a draft's Bcc the
    /// same.
    func testTheHeaderNamesExactlyTheRecipients() {
        let draft = letter(to: ["jane@example.com;", ";"],
                           cc: ["a@example.com; b@example.com;", "Sam Example <sam@example.com>;"],
                           bcc: ["pat@example.com;", ",;"])
        for includeBcc in [false, true] {
            let raw = RFC5322Builder.build(draft: draft, from: account, includeBcc: includeBcc)
            let headers = MIMEDecoder.parseHeaders(raw)
            XCTAssertEqual(MIMEDecoder.headerValue("To", in: headers), "jane@example.com")
            XCTAssertEqual(MIMEDecoder.headerValue("Cc", in: headers),
                           "a@example.com, b@example.com, Sam Example <sam@example.com>")
            XCTAssertEqual(MIMEDecoder.headerValue("Bcc", in: headers), includeBcc ? "pat@example.com" : nil)
        }
        // Nobody in To, a ";" alone: no To at all.
        let nobody = RFC5322Builder.build(draft: letter(to: [";"], cc: ["sam@example.com"]), from: account)
        XCTAssertNil(MIMEDecoder.headerValue("To", in: MIMEDecoder.parseHeaders(nobody)))
    }

    // MARK: - A header read back

    /// A header with a ";" between its addresses, as some clients write it
    /// and as this app wrote a ";" he typed: an entry for each, so Reply
    /// All knows each person, his own address among them. A group still
    /// ends at its ";" (RFC 5322), and an empty one is still nobody.
    func testAHeaderReadsASemicolonBetweenAddressesAsAComma() {
        let cases: [(String, [String])] = [
            ("jane@example.com;", ["jane@example.com"]),
            ("Jane Example <jane@example.com>; Sam Example <sam@example.com>",
             ["Jane Example <jane@example.com>", "Sam Example <sam@example.com>"]),
            ("a@example.com; b@example.com;", ["a@example.com", "b@example.com"]),
            ("\"Re: Jane\" <jane@example.com>; sam@example.com",
             ["\"Re: Jane\" <jane@example.com>", "sam@example.com"]),
            ("undisclosed-recipients:;", ["undisclosed-recipients:;"]),
            ("Friends: jane@example.com, sam@example.com;",
             ["Friends: jane@example.com", "sam@example.com;"]),
            ("Friends: jane@example.com; Others: sam@example.com;",
             ["Friends: jane@example.com;", "Others: sam@example.com;"]),
            ("Friends:;, sam@example.com; pat@example.com",
             ["Friends:;", "sam@example.com", "pat@example.com"]),
        ]
        for (header, entries) in cases {
            XCTAssertEqual(MailFormat.addressList(header), entries, header)
        }
        // Each still names the person in it.
        XCTAssertEqual(MailFormat.addressList("Friends: jane@example.com; Others: sam@example.com;")
                        .compactMap { MailFormat.recipient(in: $0)?.address },
                       ["jane@example.com", "sam@example.com"])
        XCTAssertNil(MailFormat.recipient(in: "undisclosed-recipients:;"))
    }

    /// A letter's malformed `<a;b@example.com>`, one address in brackets
    /// with a ";" in it: Reply All keeps it one recipient, in its brackets,
    /// so the field does not split it and the reply never goes to
    /// "b@example.com", whom the letter did not name. It goes as the one
    /// address it is, and the server refuses it as it would have.
    func testAnAddressWithASemicolonInsideItsBracketsStaysOne() {
        XCTAssertEqual(MailFormat.recipientEntry(name: nil, address: "a;b@example.com"), "<a;b@example.com>")
        XCTAssertEqual(MailFormat.recipientEntry(name: nil, address: "a,b@example.com"), "<a,b@example.com>")
        XCTAssertEqual(MailFormat.recipientEntry(name: nil, address: "\"a;b\"@example.com"),
                       "\"a;b\"@example.com")
        XCTAssertEqual(MailFormat.recipientEntry(name: nil, address: "jane@example.com;"), "jane@example.com;")
        // Addresses alone between the separators: a list, left for the
        // field to split, as a book of an earlier build can hold one.
        XCTAssertEqual(MailFormat.recipientEntry(name: nil, address: "a@example.com; b@example.com"),
                       "a@example.com; b@example.com")
        var picked = RecipientBubbles()
        picked.pick(MailFormat.recipient(name: nil, address: "a@example.com; b@example.com").entry)
        XCTAssertEqual(picked.entries, ["a@example.com", "b@example.com"])
        XCTAssertEqual(MailFormat.recipientEntry(name: "Jane", address: "a;b@example.com"),
                       "Jane <a;b@example.com>")

        let m = Message(id: "1/9", mailboxID: "INBOX", sender: "Pat Example <pat@example.com>",
                        senderAddress: "pat@example.com",
                        to: MailFormat.addressList("<a;b@example.com>, owner@example.com"),
                        cc: [], replyTo: [], from: ["Pat Example <pat@example.com>"], subject: "Lunch",
                        date: Date(timeIntervalSince1970: 1_700_000_000),
                        textBody: "hi", htmlBody: nil, attachments: [])
        let all = ReplyAddressing.reply(to: m, all: true, mine: OwnAddresses(["owner@example.com"]))
        XCTAssertEqual(all.cc, ["<a;b@example.com>"])
        XCTAssertEqual(RecipientBubbles(entries: all.cc).entries, all.cc)
        XCTAssertEqual(RecipientBubbles.words(for: all.cc[0]), "a;b@example.com")
        var draft = letter(to: all.to, cc: all.cc)
        draft.body = "Yes."
        XCTAssertEqual(Submission.recipients(of: draft), ["Pat Example <pat@example.com>", "<a;b@example.com>"])
        let raw = RFC5322Builder.build(draft: draft, from: account)
        let cc = MIMEDecoder.headerValue("Cc", in: MIMEDecoder.parseHeaders(raw))
        XCTAssertEqual(cc, "<a;b@example.com>")
        XCTAssertEqual(MailFormat.addressList(cc ?? ""), ["<a;b@example.com>"], "read back as one")
    }

    /// Reply All on a letter whose To has ";" between its people: each of
    /// them in Cc, in order, each a bubble, his own address left out. Read
    /// as one entry, Jane was lost, the entry's address being Sam's, and
    /// his own address went in Cc inside it.
    func testReplyAllToAHeaderWithSemicolonsKnowsEachPerson() {
        let to = MailFormat.addressList("Jane Example <jane@example.com>; owner@example.com; "
                                        + "Sam Example <sam@example.com>;")
        let m = Message(id: "1/9", mailboxID: "INBOX", sender: "Pat Example <pat@example.com>",
                        senderAddress: "pat@example.com", to: to, cc: [], replyTo: [],
                        from: ["Pat Example <pat@example.com>"], subject: "Lunch",
                        date: Date(timeIntervalSince1970: 1_700_000_000),
                        textBody: "hi", htmlBody: nil, attachments: [])
        let all = ReplyAddressing.reply(to: m, all: true, mine: OwnAddresses(["owner@example.com"]))
        XCTAssertEqual(all.to, ["Pat Example <pat@example.com>"])
        XCTAssertEqual(all.cc, ["Jane Example <jane@example.com>", "Sam Example <sam@example.com>"])
        XCTAssertEqual(RecipientBubbles(entries: all.cc).entries, all.cc)
    }

    // MARK: - An empty group

    /// An empty group, `undisclosed-recipients:;`, as a draft written in
    /// another client can have in its To: one entry in the field, its ";"
    /// with it, as in a header. Split at its ";", the bubble read
    /// "undisclosed-recipients:", and the header went out with a group
    /// begun and never ended. A group with someone in it still ends at its
    /// ";" in the field, as any address there does.
    func testAnEmptyGroupStaysOneEntryInTheField() {
        let cases: [(String, [String])] = [
            ("undisclosed-recipients:;", ["undisclosed-recipients:;"]),
            ("undisclosed-recipients: ;", ["undisclosed-recipients: ;"]),
            ("undisclosed-recipients: ;, pat@example.com;", ["undisclosed-recipients: ;", "pat@example.com"]),
            ("undisclosed-recipients: (nobody) ;", ["undisclosed-recipients: (nobody) ;"]),
            ("Friends: jane@example.com; sam@example.com;", ["Friends: jane@example.com", "sam@example.com"]),
            ("Friends: jane@example.com, sam@example.com;", ["Friends: jane@example.com", "sam@example.com"]),
            ("\"Re: Jane\" <jane@example.com>;", ["\"Re: Jane\" <jane@example.com>"]),
            ("Re: Jane <jane@example.com>;", ["Re: Jane <jane@example.com>"]),
        ]
        for (field, entries) in cases {
            XCTAssertEqual(MailFormat.addresses(in: field), entries, field)
        }
        // A header reads it as it did.
        XCTAssertEqual(MailFormat.addressList("undisclosed-recipients: ;, pat@example.com;"),
                       ["undisclosed-recipients: ;", "pat@example.com"])
        XCTAssertEqual(RecipientBubbles(entries: ["undisclosed-recipients:;"]).entries,
                       ["undisclosed-recipients:;"])
        // Typed, a letter at a time: its ";" makes the bubble, and stays on
        // it, as the field keeps it.
        for (typed, entries) in cases {
            var field = RecipientBubbles()
            var line = ""
            for c in typed {
                line.append(c)
                field.type(line)
                line = field.typed
            }
            XCTAssertEqual(field.entries, entries, typed)
            XCTAssertEqual(field.typed, "", typed)
        }
    }

    /// A draft written in another client, To the empty group and Bcc Pat,
    /// reopened: its bubble reads the group whole, the letter goes to Pat,
    /// and its header's To is the group, ended, as before B-081.
    func testADraftToAnEmptyGroupKeepsItWhole() {
        let m = Message(id: "600003/301", mailboxID: "[Gmail]/Drafts", sender: "Carlo",
                        senderAddress: "owner@example.com",
                        to: MailFormat.addressList("undisclosed-recipients:;"), cc: [],
                        bcc: MailFormat.addressList("pat@example.com"),
                        subject: "Lunch", date: Date(timeIntervalSince1970: 1_700_000_000),
                        textBody: "One o'clock.", htmlBody: nil, attachments: [])
        let draft = Draft.reopening(m, signatureImages: [])
        XCTAssertEqual(draft.to, ["undisclosed-recipients:;"])
        let to = RecipientBubbles(entries: draft.to)
        XCTAssertEqual(to.entries, ["undisclosed-recipients:;"])
        XCTAssertEqual(RecipientBubbles.words(for: to.entries[0]), "undisclosed-recipients:;")
        var opened = draft
        opened.to = to.recipients
        opened.bcc = RecipientBubbles(entries: draft.bcc).recipients
        // The group stays in the header, and names nobody to the server.
        XCTAssertEqual(Submission.recipients(of: opened), ["pat@example.com"])
        for includeBcc in [false, true] {
            let raw = RFC5322Builder.build(draft: opened, from: account, includeBcc: includeBcc)
            let headers = MIMEDecoder.parseHeaders(raw)
            XCTAssertEqual(MIMEDecoder.headerValue("To", in: headers), "undisclosed-recipients:;")
            XCTAssertEqual(MIMEDecoder.headerValue("Bcc", in: headers), includeBcc ? "pat@example.com" : nil)
        }
    }
}

/// The book of addresses (B-081). A build before B-081 learned an address
/// with the ";" typed after it, "jane@example.com;", and two with a ";"
/// between them as one. Kept so, the list offered Jane twice, and offered
/// "jane@example.com;" again once Jane was a bubble, and the pick made a
/// second bubble for her, so the letter named her twice. Each is filed
/// under its own address as the book loads and as it learns.
final class SemicolonBookTests: XCTestCase {

    private static let suite = "SemicolonBookTests"
    private static let key = "blackmail.recipients"
    private let then = Date(timeIntervalSince1970: 1_700_000_000)

    private var defaults: UserDefaults { UserDefaults(suiteName: Self.suite)! }

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        super.tearDown()
    }

    /// A book as a build before B-081 could have written it.
    private var earlier: [KnownRecipient] {
        [KnownRecipient(address: "jane@example.com;", name: nil, uses: 3, lastSeen: then.addingTimeInterval(60)),
         KnownRecipient(address: "jane@example.com", name: "Jane Example", uses: 1, lastSeen: then),
         KnownRecipient(address: "a@example.com; b@example.com", name: "Both", uses: 2, lastSeen: then),
         KnownRecipient(address: "a;b@example.com", name: nil, uses: 0, lastSeen: then)]
    }

    private func store(_ book: [KnownRecipient]) throws {
        defaults.set(try JSONEncoder().encode(book), forKey: Self.key)
    }

    private func stored() throws -> [KnownRecipient] {
        try JSONDecoder().decode([KnownRecipient].self, from: XCTUnwrap(defaults.data(forKey: Self.key)))
    }

    /// Filed again as it loads: Jane once, her name kept, her uses added;
    /// the two in one each with their uses and no name; the malformed
    /// "a;b@example.com" whole, as nobody's but its own. Written out so at
    /// the next flush, and read the same by a book made after.
    func testABookKeptBeforeB081IsFiledAgainAsItLoads() throws {
        try store(earlier)
        let book = RecipientBook(defaults: defaults)
        let filed = book.snapshot().sorted { $0.address < $1.address }
        XCTAssertEqual(filed.map(\.address), ["a;b@example.com", "a@example.com", "b@example.com", "jane@example.com"])
        let jane = try XCTUnwrap(filed.last)
        XCTAssertEqual(jane.name, "Jane Example")
        XCTAssertEqual(jane.uses, 4)
        XCTAssertEqual(jane.lastSeen, then.addingTimeInterval(60))
        XCTAssertEqual(filed.filter { $0.address.hasPrefix("a@") || $0.address.hasPrefix("b@") }.map(\.uses), [2, 2])
        XCTAssertEqual(filed.filter { $0.address.hasPrefix("a@") || $0.address.hasPrefix("b@") }.map(\.name), [nil, nil])

        // Another book on the same store, before it is written: the same.
        XCTAssertEqual(RecipientBook(defaults: defaults).snapshot().sorted { $0.address < $1.address }, filed)
        book.flush()
        XCTAssertEqual(try stored().map(\.address).sorted(), filed.map(\.address))
        XCTAssertEqual(RecipientBook(defaults: defaults).snapshot().sorted { $0.address < $1.address }, filed)
    }

    /// Two entries for one address become one, named by the entry that was
    /// that address alone when it has a name, whichever came first; or else
    /// by the other.
    func testTwoEntriesForOneAddressTakeTheCleanOnesName() {
        let dirty = KnownRecipient(address: "sam@example.com;", name: "S.", uses: 1, lastSeen: then)
        let clean = KnownRecipient(address: "sam@example.com", name: "Sam Example", uses: 2, lastSeen: then)
        let bare = KnownRecipient(address: "sam@example.com", name: nil, uses: 2, lastSeen: then)
        let blank = KnownRecipient(address: "sam@example.com", name: "", uses: 2, lastSeen: then)
        for (stored, name) in [([dirty, clean], "Sam Example"), ([clean, dirty], "Sam Example"),
                               ([dirty, bare], "S."), ([bare, dirty], "S."), ([blank, dirty], "S.")] {
            let filed = RecipientBook.filed(stored)
            XCTAssertEqual(filed.map(\.address), ["sam@example.com"], "\(stored)")
            XCTAssertEqual(filed.first?.name, name, "\(stored)")
            XCTAssertEqual(filed.first?.uses, 3, "\(stored)")
        }
    }

    /// A book with nothing to file again loads as it was, and is not
    /// written out again for it.
    func testABookWithNothingToFileIsAsItWas() throws {
        let clean = [KnownRecipient(address: "jane@example.com", name: "Jane Example", uses: 1, lastSeen: then),
                     KnownRecipient(address: "sam@example.com", name: "", uses: 0, lastSeen: then),
                     KnownRecipient(address: "a;b@example.com", name: nil, uses: 2, lastSeen: then)]
        XCTAssertEqual(RecipientBook.filed(clean), clean)
        try store(clean)
        let book = RecipientBook(defaults: defaults)
        defaults.removeObject(forKey: Self.key)
        book.flush()
        XCTAssertNil(defaults.data(forKey: Self.key), "nothing changed, nothing written")
    }

    /// He picks Jane and types "ja" again: nothing is offered, where the
    /// book of an earlier build offered "jane@example.com;" and its pick
    /// made a second bubble for her. Before she is a bubble, one row.
    func testJaneIsOfferedOnceAndNotAgainOnceABubble() throws {
        try store(earlier)
        let book = RecipientBook(defaults: defaults)
        var field = RecipientBubbles()
        field.type("ja")
        let rows = ComposeForm.suggestions(book.snapshot(), in: field, after: .typed)
        XCTAssertEqual(rows.map(\.address), ["jane@example.com"])
        XCTAssertEqual(rows.map(\.display), ["Jane Example"])
        let jane = try XCTUnwrap(rows.first)
        field.pick(MailFormat.recipient(name: jane.name, address: jane.address).entry)
        XCTAssertEqual(field.entries, ["Jane Example <jane@example.com>"])
        field.type("ja")
        XCTAssertEqual(ComposeForm.suggestions(book.snapshot(), in: field, after: .typed), [])
    }

    /// What it learns is filed the same way: a use of "jane@example.com;",
    /// as a share sent by an earlier build hands it to the app, is Jane's;
    /// two in one are each, without the name; the malformed one is whole.
    func testWhatTheBookLearnsIsFiledUnderEachAddress() {
        let book = RecipientBook(defaults: defaults)
        book.used(address: "jane@example.com;")
        book.note(address: "Jane@Example.com", name: "Jane Example")
        book.note(address: "a@example.com, b@example.com;", name: "Both")
        book.note(address: "a;b@example.com")
        book.used(address: "sam@example.com; sam@example.com")
        book.used(address: ";")
        let known = book.snapshot().sorted { $0.address < $1.address }
        XCTAssertEqual(known.map(\.address),
                       ["a;b@example.com", "a@example.com", "b@example.com", "jane@example.com", "sam@example.com"])
        XCTAssertEqual(known.map(\.name), [nil, nil, nil, "Jane Example", nil])
        XCTAssertEqual(known.map(\.uses), [0, 0, 0, 1, 1])
    }
}

/// The send path over the scripted servers (B-081): a letter To an address
/// with a ";" after it goes, once, to exactly its addresses, and its header
/// names them; a draft kept with one comes back and goes the same; the
/// letter sent is answered to the same people.
final class SemicolonSendTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "SemicolonSendTests"

    private var server: ScriptedIMAPServer!
    private var submissions: [ScriptedSubmission] = []
    private let lock = NSLock()

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        for outcome in ["ok", "fail"] {
            let transcript = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
            try? FileManager.default.removeItem(atPath: transcript)
        }
        server = nil
        submissions = []
        super.tearDown()
    }

    private var book: RecipientBook { RecipientBook(defaults: UserDefaults(suiteName: Self.suite)!) }

    private func makeRepository() -> IMAPMailRepository {
        let imap = server.transportFactory
        return IMAPMailRepository(
            account: server.account, password: server.password,
            transport: { [self] host, port in
                guard port == 465 else { return imap(host, port) }
                let submission = ScriptedSubmission()
                lock.lock()
                submissions.append(submission)
                lock.unlock()
                return submission
            },
            recipients: book,
            shelf: keptShelf(for: server.account))
    }

    private func made() -> [ScriptedSubmission] {
        lock.lock()
        defer { lock.unlock() }
        return submissions
    }

    private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath,
                                   line: UInt = #line) async throws -> T {
        try XCTUnwrap(value, file: file, line: line)
    }

    private func letter(to: [String], cc: [String] = [], bcc: [String] = []) -> Draft {
        var draft = Draft()
        draft.to = to
        draft.cc = cc
        draft.bcc = bcc
        draft.subject = "B-081 semicolon"
        draft.body = "One o'clock."
        return draft
    }

    /// What one send put on the wire: its RCPT TOs, and its header's To and
    /// Cc as written.
    private func wire(_ submission: ScriptedSubmission) async throws
        -> (rcpt: [String], to: String?, cc: String?, letter: Data) {
        let rcpt = await submission.commands.filter { $0.hasPrefix("RCPT TO:") }
        let letters = await submission.letters
        XCTAssertEqual(letters.count, 1)
        let raw = try XCTUnwrap(letters.first)
        let headers = MIMEDecoder.parseHeaders(raw)
        return (rcpt, MIMEDecoder.headerValue("To", in: headers),
                MIMEDecoder.headerValue("Cc", in: headers), raw)
    }

    /// Send on a letter To an address with a ";" after it, and the other
    /// shapes of it: it goes, once, its RCPT TOs exactly its addresses, none
    /// with a ";" and none empty, and its header names them alone. Before,
    /// `RCPT TO:<jane@example.com;>`, which Gmail refuses 553, and the
    /// letter did not go.
    func testALetterToAnAddressWithASemicolonGoesToItsAddresses() async throws {
        let cases: [(to: [String], cc: [String], bcc: [String], rcpt: [String], header: String, cch: String?)] = [
            (["jane@example.com;"], [], [], ["jane@example.com"], "jane@example.com", nil),
            (["Jane Example <jane@example.com>;"], [], [], ["jane@example.com"],
             "Jane Example <jane@example.com>", nil),
            (["a@example.com; b@example.com;"], [], [], ["a@example.com", "b@example.com"],
             "a@example.com, b@example.com", nil),
            (["jane@example.com", ";"], [" ; "], [",;"], ["jane@example.com"], "jane@example.com", nil),
            (["jane@example.com,;"], ["sam@example.com;"], ["pat@example.com;"],
             ["jane@example.com", "sam@example.com", "pat@example.com"], "jane@example.com",
             "sam@example.com"),
        ]
        let repository = makeRepository()
        for c in cases {
            let what = "\(c.to) \(c.cc) \(c.bcc)"
            let before = made().count
            try await repository.send(letter(to: c.to, cc: c.cc, bcc: c.bcc))
            let sent = made()
            XCTAssertEqual(sent.count, before + 1, what)
            let on = try await wire(try XCTUnwrap(sent.last))
            XCTAssertEqual(on.rcpt, c.rcpt.map { "RCPT TO:<\($0)>" }, what)
            XCTAssertEqual(on.to, c.header, what)
            XCTAssertEqual(on.cc, c.cch, what)
            XCTAssertNil(MIMEDecoder.headerValue("Bcc", in: MIMEDecoder.parseHeaders(on.letter)), what)
        }
        // The book learns the addresses, not the ";".
        let known = book.snapshot().map(\.address).sorted()
        XCTAssertEqual(known.filter { $0 != server.account.address.lowercased() },
                       ["a@example.com", "b@example.com", "jane@example.com", "pat@example.com",
                        "sam@example.com"])
    }

    /// A ";" alone, To nobody: refused before the server is reached, as a
    /// letter to nobody always was.
    func testALetterToASemicolonAloneIsALetterToNobody() async throws {
        let repository = makeRepository()
        do {
            try await repository.send(letter(to: [";", " ; "]))
            XCTFail("sent to nobody")
        } catch {
            XCTAssertEqual(error as? MailError, .notSent)
        }
        XCTAssertEqual(made().count, 0, "the server never reached")
    }

    /// An empty group alone, To nobody: refused before the server is
    /// reached, as a letter to nobody always was, and never offered as an
    /// address.
    func testALetterToAnEmptyGroupAloneIsALetterToNobody() async throws {
        let repository = makeRepository()
        do {
            try await repository.send(letter(to: ["undisclosed-recipients:;"],
                                             cc: ["undisclosed-recipients: (nobody) ;"]))
            XCTFail("sent to nobody")
        } catch {
            XCTAssertEqual(error as? MailError, .notSent)
        }
        XCTAssertEqual(made().count, 0, "the server never reached")
    }

    /// Only an empty group is left out of the envelope: an address, one
    /// with a ";" inside its brackets, a name in quotes with a ";" or a
    /// colon in it, and a word that is no address all stay, as Send has
    /// always had them.
    func testOnlyAnEmptyGroupIsLeftOutOfTheEnvelope() {
        for entry in ["undisclosed-recipients:;", " undisclosed-recipients: ; ",
                      "undisclosed-recipients: (nobody) ;"] {
            XCTAssertTrue(MailFormat.isEmptyGroup(entry), entry)
        }
        for entry in ["jane@example.com", "<a;b@example.com>", "\"Re: Jane; Sam\" <jane@example.com>",
                      "jan", "Friends: jane@example.com", ""] {
            XCTAssertFalse(MailFormat.isEmptyGroup(entry), entry)
        }
        var draft = Draft()
        draft.to = ["undisclosed-recipients:;", "Jane Example <jane@example.com>"]
        draft.cc = ["<a;b@example.com>"]
        draft.bcc = ["undisclosed-recipients: ;"]
        XCTAssertEqual(Submission.recipients(of: draft), ["Jane Example <jane@example.com>", "<a;b@example.com>"])
    }

    /// A draft kept with a ";" in its To, as a build before this one kept
    /// what he typed: saved to Drafts its header names the addresses alone,
    /// it comes back a bubble each, and Send from it goes to them.
    func testADraftWithASemicolonComesBackAndGoes() async throws {
        let repository = makeRepository()
        var draft = letter(to: ["jane@example.com;", "a@example.com; b@example.com;"],
                           cc: ["Sam Example <sam@example.com>;"], bcc: ["pat@example.com;"])
        draft.body = "Half a thought."
        let id = try await XCTUnwrapAsync(try await repository.saveDraft(draft))
        let back = try await repository.loadDraft(id: id, gmailMessageID: nil, mailboxID: Server.drafts)
        XCTAssertEqual(back.to, ["jane@example.com", "a@example.com", "b@example.com"])
        XCTAssertEqual(back.cc, ["Sam Example <sam@example.com>"])
        XCTAssertEqual(back.bcc, ["pat@example.com"])
        // Opened in the composer, a bubble each, and Send.
        var opened = back
        opened.to = RecipientBubbles(entries: back.to).recipients
        opened.cc = RecipientBubbles(entries: back.cc).recipients
        opened.bcc = RecipientBubbles(entries: back.bcc).recipients
        XCTAssertEqual(opened.to, back.to)
        try await repository.send(opened)
        let on = try await wire(try XCTUnwrap(made().last))
        XCTAssertEqual(on.rcpt, ["jane@example.com", "a@example.com", "b@example.com",
                                 "sam@example.com", "pat@example.com"].map { "RCPT TO:<\($0)>" })
        XCTAssertEqual(on.to, "jane@example.com, a@example.com, b@example.com")
        XCTAssertEqual(on.cc, "Sam Example <sam@example.com>")
    }

    /// A draft To the empty group `undisclosed-recipients:;` with Pat in
    /// Bcc, as another client writes one: saved and read back, its To the
    /// group whole; opened, one bubble that reads it whole; sent, it goes
    /// to Pat once, and its header's To is the group, ended. The group
    /// names nobody, so it is not offered to the server.
    func testADraftToAnEmptyGroupGoesToItsBcc() async throws {
        let repository = makeRepository()
        let draft = letter(to: ["undisclosed-recipients:;"], bcc: ["pat@example.com"])
        let id = try await XCTUnwrapAsync(try await repository.saveDraft(draft))
        let back = try await repository.loadDraft(id: id, gmailMessageID: nil, mailboxID: Server.drafts)
        XCTAssertEqual(back.to, ["undisclosed-recipients:;"])
        XCTAssertEqual(back.bcc, ["pat@example.com"])
        var opened = back
        opened.to = RecipientBubbles(entries: back.to).recipients
        opened.bcc = RecipientBubbles(entries: back.bcc).recipients
        XCTAssertEqual(opened.to, ["undisclosed-recipients:;"])
        try await repository.send(opened)
        XCTAssertEqual(made().count, 1)
        let on = try await wire(try XCTUnwrap(made().last))
        XCTAssertEqual(on.rcpt, ["RCPT TO:<pat@example.com>"])
        XCTAssertEqual(on.to, "undisclosed-recipients:;")
        XCTAssertNil(on.cc)
        XCTAssertNil(MIMEDecoder.headerValue("Bcc", in: MIMEDecoder.parseHeaders(on.letter)))
    }

    /// The letter sent To "jane@example.com;" is his own letter to Jane:
    /// read back from its header, Reply and Reply All go to her alone.
    func testTheLetterSentIsAnsweredToTheSamePeople() async throws {
        let repository = makeRepository()
        try await repository.send(letter(to: ["Jane Example <jane@example.com>;"],
                                         cc: ["sam@example.com;"]))
        let on = try await wire(try XCTUnwrap(made().last))
        let headers = MIMEDecoder.parseHeaders(on.letter)
        let to = MailFormat.addressList(MIMEDecoder.headerValue("To", in: headers) ?? "")
        let cc = MailFormat.addressList(MIMEDecoder.headerValue("Cc", in: headers) ?? "")
        XCTAssertEqual(to, ["Jane Example <jane@example.com>"])
        XCTAssertEqual(cc, ["sam@example.com"])
        let owner = server.account.address
        let m = Message(id: "1/9", mailboxID: Server.sent, sender: owner, senderAddress: owner,
                        to: to, cc: cc, replyTo: [], from: [owner], subject: "B-081 semicolon",
                        date: Date(timeIntervalSince1970: 1_700_000_000),
                        textBody: "One o'clock.", htmlBody: nil, attachments: [])
        let mine = OwnAddresses(account: server.account)
        XCTAssertEqual(ReplyAddressing.reply(to: m, all: false, mine: mine).to,
                       ["Jane Example <jane@example.com>"])
        XCTAssertEqual(ReplyAddressing.reply(to: m, all: true, mine: mine),
                       ReplyAddressing(to: ["Jane Example <jane@example.com>"], cc: ["sam@example.com"]))
    }
}
