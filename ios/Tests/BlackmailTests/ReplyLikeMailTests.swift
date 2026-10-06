import XCTest
@testable import Blackmail

/// Reply as Mail's (B-076): his addresses as Mail's account lists them
/// under Email, the header's names, and the composers' name bubbles.
///
/// Whom a reply goes to is pinned in `ReplyAddressingTests`; this holds what
/// B-076 adds around it. The two sheets are UIKit and never build on this
/// host, so their wiring is read from their source, as
/// `ComposeLikeMailTests` reads it.
final class ReplyLikeMailTests: XCTestCase {

    private static let owner = "owner_example@gmail.com"
    private static let second = "Owner@Example.net"

    private func account(_ others: [String] = []) -> MailAccount {
        MailAccount(address: Self.owner, username: Self.owner, otherAddresses: others)
    }

    private func letter(from: String = "Jane Example <jane@example.com>", replyTo: [String] = [],
                        to: [String], cc: [String] = []) -> Message {
        Message(id: "1/9", mailboxID: "INBOX", sender: from,
                senderAddress: MailFormat.bareAddress(from),
                to: to, cc: cc, replyTo: replyTo, from: [from], subject: "Lunch",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                textBody: "hi", htmlBody: nil, attachments: [])
    }

    // MARK: - His addresses

    /// Mail's list: the account's own first, then each added, each once
    /// in any letter case, blanks and spaces round them left out.
    func testHisAddressesAreTheAccountsFirstThenEachAdded() {
        let a = account([" owner@example.net ", "", "OWNER@EXAMPLE.NET", "Owner_Example@Gmail.com",
                         "carlo.owner@example.org"])
        XCTAssertEqual(a.ownAddresses, [Self.owner, "owner@example.net", "carlo.owner@example.org"])
        XCTAssertEqual(account().ownAddresses, [Self.owner])
    }

    /// "Add Another Email…": an address, trimmed, under the others; never
    /// one already there in any letter case, nor anything not an address.
    func testAddAnotherEmailTakesAnAddressOnce() throws {
        let added = try account().adding("  owner@example.net ").get()
        XCTAssertEqual(added.otherAddresses, ["owner@example.net"])
        XCTAssertEqual(try added.adding("sam.owner@example.org").get().ownAddresses,
                       [Self.owner, "owner@example.net", "sam.owner@example.org"])
        for again in ["OWNER@example.NET", "Owner_Example@GMAIL.com"] {
            XCTAssertEqual(added.adding(again), .failure(.alreadyListed), again)
        }
        for junk in ["", "  ", "owner", "@example.net", "owner@", "owner @example.net",
                     "Owner <owner@example.net>", "a@b.com, c@d.com", "x@y;"] {
            XCTAssertEqual(added.adding(junk), .failure(.notAnAddress), junk)
        }
        // Letters still go from the account's own.
        XCTAssertEqual(added.address, Self.owner)
    }

    /// Each added one can be taken off, in any letter case; the account's
    /// own cannot, as in Mail.
    func testAnAddedAddressCanBeRemovedAndTheAccountsCannot() {
        let a = account(["owner@example.net", "sam.owner@example.org"])
        XCTAssertEqual(a.removing("OWNER@example.net").ownAddresses, [Self.owner, "sam.owner@example.org"])
        XCTAssertEqual(a.removing(Self.owner).ownAddresses, a.ownAddresses)
        XCTAssertEqual(a.removing("nobody@example.com"), a)
    }

    /// Stored with the account. An account kept by an older build, with no
    /// list, still opens, with none.
    func testTheListIsStoredWithTheAccount() throws {
        let a = account(["owner@example.net"])
        let back = try JSONDecoder().decode(MailAccount.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(back, a)
        XCTAssertEqual(back.otherAddresses, ["owner@example.net"])
        let old = #"{"address":"owner@example.com","username":"owner@example.com","signature":"Sam"}"#
        let older = try JSONDecoder().decode(MailAccount.self, from: Data(old.utf8))
        XCTAssertEqual(older.otherAddresses, [])
        XCTAssertEqual(older.ownAddresses, ["owner@example.com"])
    }

    /// The share extension has the list as it has the account, through
    /// the mirror.
    func testTheListReachesTheShareExtension() throws {
        let keychain = MemoryKeychain()
        let mirror = ShareMirror(keychain: keychain)
        let a = account(["owner@example.net"])
        mirror.publish(account: a, password: "app-password")
        let shared = try XCTUnwrap(mirror.load())
        XCTAssertEqual(shared.account.ownAddresses, [Self.owner, "owner@example.net"])
        XCTAssertEqual(shared.account, a)
        // Taken off in Settings, and saved: the extension's copy follows.
        mirror.publish(account: a.removing("owner@example.net"), password: "app-password")
        XCTAssertEqual(try XCTUnwrap(mirror.load()).account.ownAddresses, [Self.owner])
    }

    /// The one place the app asks whether an address is his: every one in
    /// the list, and the login, in any letter case; nothing else, Gmail's
    /// other spellings of his mailbox included.
    func testOwnAddressesAreTheListAndTheLogin() {
        var a = account(["owner@example.net"])
        a.username = "owner.login@example.org"
        let his = OwnAddresses(account: a)
        for yes in [Self.owner, "OWNER_EXAMPLE@gmail.com", "Owner <owner@EXAMPLE.net>",
                    "owner.login@example.org"] {
            XCTAssertTrue(his.contains(yes), yes)
        }
        for no in ["o.wner_example@gmail.com", "owner_example+x@gmail.com",
                   "owner_example@googlemail.com", "owner@example.org", "jane@example.com", "owner"] {
            XCTAssertFalse(his.contains(no), no)
        }
        XCTAssertFalse(OwnAddresses(account: nil).contains(Self.owner))
    }

    /// His second address, listed, is left out of a Reply All in any
    /// letter case, from To and from Cc. Not listed, it is someone else,
    /// as in Mail, and gets a copy.
    func testHisSecondAddressListedIsLeftOutOfReplyAll() {
        let m = letter(to: [Self.owner, "Owner <OWNER@example.NET>", "sam@example.org"],
                       cc: ["owner@example.net", "carlo@example.org"])
        let listed = Draft.replying(to: m, all: true, mine: OwnAddresses(account: account([Self.second])))
        XCTAssertEqual(listed.to, ["Jane Example <jane@example.com>"])
        XCTAssertEqual(listed.cc, ["sam@example.org", "carlo@example.org"])
        let unlisted = Draft.replying(to: m, all: true, mine: OwnAddresses(account: account()))
        XCTAssertEqual(unlisted.cc, ["Owner <OWNER@example.NET>", "sam@example.org", "carlo@example.org"])
    }

    /// A letter from his second address, listed, is his own: answered to
    /// whom it went, not to him. Not listed, to its From, as anyone's.
    func testALetterFromHisSecondAddressListedIsHisOwn() {
        let m = letter(from: "Owner <owner@example.net>", to: ["Sam Example <sam@example.org>"],
                       cc: ["carlo@example.org"])
        let mine = OwnAddresses(account: account([Self.second]))
        XCTAssertEqual(Draft.replying(to: m, all: false, mine: mine).to, ["Sam Example <sam@example.org>"])
        // His own letter's Reply All, as B-061 built it, kept (B-076).
        let all = Draft.replying(to: m, all: true, mine: mine)
        XCTAssertEqual(all.to, ["Sam Example <sam@example.org>"])
        XCTAssertEqual(all.cc, ["carlo@example.org"])
        XCTAssertEqual(Draft.replying(to: m, all: false, mine: OwnAddresses(account: account())).to,
                       ["Owner <owner@example.net>"])
    }

    /// His letter to his second address alone, with it listed, is
    /// answered to him, as a letter to himself is.
    func testHisLetterToHisSecondAddressAloneIsAnsweredToHim() {
        let m = letter(from: Self.owner, to: ["owner@example.net"])
        let mine = OwnAddresses(account: account([Self.second]))
        XCTAssertEqual(Draft.replying(to: m, all: false, mine: mine).to, ["owner@example.net"])
        XCTAssertEqual(Draft.replying(to: m, all: true, mine: mine).to, ["owner@example.net"])
    }

    /// Nothing is put in the list by itself, as Mail puts nothing: the
    /// only code that writes it is the account's own and its store's, and
    /// Settings changes it only through `adding` and `removing`. A letter
    /// from his second address in Sent Mail does not make it his.
    func testNothingFillsTheListByItself() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 50)
        let naming = try files.filter { try String(contentsOf: $0, encoding: .utf8).contains("otherAddresses") }
            .map(\.lastPathComponent).sorted()
        XCTAssertEqual(naming, ["CredentialStore.swift", "MailWireTypes.swift"])
    }

    // MARK: - The header

    /// "Name <address>" whenever a real name is known; the address alone
    /// when the letter's name is the address again, in any letter case, or
    /// there is none, as Mail sends it.
    func testTheHeaderNamesAPersonAndNeverAnAddressAgain() {
        for (entry, kept) in [
            ("Jane Example <jane@example.com>", "Jane Example <jane@example.com>"),
            ("\"jane@example.com\" <jane@example.com>", "jane@example.com"),
            ("\"JANE@Example.COM\" <jane@example.com>", "jane@example.com"),
            ("Jane@Example.com <jane@example.com>", "jane@example.com"),
            ("'jane@example.com' <jane@example.com>", "jane@example.com"),
            ("jane@example.com", "jane@example.com"),
            ("<jane@example.com>", "jane@example.com"),
        ] {
            XCTAssertEqual(MailFormat.recipient(in: entry)?.entry, kept, entry)
        }
        XCTAssertEqual(MailFormat.recipientEntry(name: "JANE@example.com", address: "jane@example.com"),
                       "jane@example.com")
        // A reply to such a letter, and the header it sends.
        let m = letter(from: "\"Jane@Example.com\" <jane@example.com>", to: [Self.owner],
                       cc: ["\"SAM@example.org\" <sam@example.org>", "Pat Example <pat@example.com>"])
        var draft = Draft.replying(to: m, all: true, mine: OwnAddresses([Self.owner]))
        XCTAssertEqual(draft.to, ["jane@example.com"])
        XCTAssertEqual(draft.cc, ["sam@example.org", "Pat Example <pat@example.com>"])
        draft.body = "Yes."
        let raw = RFC5322Builder.build(draft: draft, from: account())
        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertTrue(text.contains("\r\nTo: jane@example.com\r\n"), text)
        XCTAssertTrue(text.contains("\r\nCc: sam@example.org, Pat Example <pat@example.com>\r\n"), text)
        // Typed or kept so in a draft, it still goes out bare.
        var typed = Draft()
        typed.to = ["\"JANE@example.com\" <jane@example.com>", "Jane@Example.com <jane@example.com>"]
        typed.body = "x"
        XCTAssertTrue(String(decoding: RFC5322Builder.build(draft: typed, from: account()), as: UTF8.self)
            .contains("\r\nTo: jane@example.com, jane@example.com\r\n"))
    }

    // MARK: - The bubbles

    /// A reply's recipients, a bubble each, read a bubble at a time, so
    /// Send, Cancel and the letter have the people the bubbles show.
    func testABubbleForEachRecipientAndTheSamePeopleUnderneath() {
        let to = ["Jane Example <jane@example.com>", "\"Example, Pat\" <pat@example.com>",
                  "sam@example.org", "Jane"]
        let field = RecipientBubbles(entries: to)
        XCTAssertEqual(field.entries, to)
        XCTAssertEqual(field.typed, "")
        XCTAssertEqual(field.recipients, to)
        XCTAssertEqual(field.entries.map(RecipientBubbles.words(for:)),
                       ["Jane Example", "Example, Pat", "sam@example.org", "Jane"])
        XCTAssertEqual(field.entries.map(RecipientBubbles.address(for:)),
                       ["jane@example.com", "pat@example.com", "sam@example.org", nil])
        XCTAssertTrue(ComposeForm.canSend(to: field.recipients, cc: [], bcc: []))
        XCTAssertEqual(RecipientBubbles(entries: []).recipients, [])
        XCTAssertFalse(ComposeForm.canSend(to: RecipientBubbles(entries: []).recipients, cc: [], bcc: []))
        XCTAssertFalse(ComposeForm.canSend(to: [" "], cc: [], bcc: [""]))
        // An entry as a field held it, several in one, split as it was.
        XCTAssertEqual(RecipientBubbles(entries: ["a@example.com, b@example.com"]).entries,
                       ["a@example.com", "b@example.com"])
    }

    /// The words on a bubble: the name, or the address where there is no
    /// name or the name is the address again. An entry broken over lines
    /// says its first line, which is all the letter reads of it
    /// (`RFC5322Builder.recipientLine`): no address there, none under the
    /// bubble either, so the tap shows him there is nobody to send to.
    func testABubbleSaysTheNameOrTheAddress() {
        for (entry, words, address) in [
            ("Jane Example <jane@example.com>", "Jane Example", "jane@example.com"),
            ("\"JANE@example.com\" <jane@example.com>", "jane@example.com", "jane@example.com"),
            ("jane@example.com (Jane Example)", "Jane Example", "jane@example.com"),
            ("<jane@example.com>", "jane@example.com", "jane@example.com"),
            ("Jane\u{2028}Example <jane@example.com>", "Jane", nil),
            ("undisclosed-recipients:;", "undisclosed-recipients:;", nil),
            ("Jane\nExample", "Jane", nil),
            ("Jane\tExample <jane@example.com>", "Jane Example", "jane@example.com"),
        ] as [(String, String, String?)] {
            XCTAssertEqual(RecipientBubbles.words(for: entry), words, entry.debugDescription)
            XCTAssertEqual(RecipientBubbles.address(for: entry), address, entry.debugDescription)
        }
    }

    /// An address he types and ends with a comma becomes a bubble; a comma
    /// inside a quoted name or `<…>` ends nothing.
    func testACommaMakesABubble() {
        var field = RecipientBubbles()
        field.type("jane@exa")
        XCTAssertEqual(field.entries, [])
        XCTAssertEqual(field.typed, "jane@exa")
        XCTAssertEqual(field.recipients, ["jane@exa"])
        field.type("jane@example.com,")
        XCTAssertEqual(field.entries, ["jane@example.com"])
        XCTAssertEqual(field.typed, "")
        field.type(" \"Example, Pat\" <pat@exa")
        XCTAssertEqual(field.entries, ["jane@example.com"])
        XCTAssertEqual(field.typed, "\"Example, Pat\" <pat@exa")
        field.type("\"Example, Pat\" <pat@example.com>, sam@example.org, carlo")
        XCTAssertEqual(field.entries, ["jane@example.com", "\"Example, Pat\" <pat@example.com>",
                                       "sam@example.org"])
        XCTAssertEqual(field.typed, "carlo")
        XCTAssertEqual(field.recipients, ["jane@example.com", "\"Example, Pat\" <pat@example.com>",
                                          "sam@example.org", "carlo"])
        // Commas alone make nothing.
        field.type(" , ,")
        XCTAssertEqual(field.entries.count, 3)
        XCTAssertEqual(field.typed, "")
    }

    /// Return, or leaving the field, makes a bubble of what he typed; a
    /// blank makes none.
    func testReturnOrLeavingMakesABubble() {
        var field = RecipientBubbles(entries: ["jane@example.com"])
        field.type("sam@example.org")
        field.finish()
        XCTAssertEqual(field.entries, ["jane@example.com", "sam@example.org"])
        XCTAssertEqual(field.typed, "")
        field.type("  ")
        field.finish(leaving: true)
        XCTAssertEqual(field.entries, ["jane@example.com", "sam@example.org"])
        // A quote never closed is split as the field's text always was,
        // so the bubbles are what the letter would have gone to.
        field.type("\"Example, pat@example.com")
        field.finish()
        XCTAssertEqual(field.entries, ["jane@example.com", "sam@example.org", "\"Example", "pat@example.com"])
        XCTAssertEqual(field.recipients, field.entries)
    }

    /// A pick is a bubble in place of what he typed, and the field offers
    /// nothing after it, nor that address again (B-069, B-073).
    func testAPickIsABubbleAndTheSuggestionRulesStand() {
        let book = [KnownRecipient(address: "jane@example.com", name: "Jane Example", uses: 3,
                                   lastSeen: Date(timeIntervalSince1970: 0)),
                    KnownRecipient(address: "janet@example.org", name: nil, uses: 1,
                                   lastSeen: Date(timeIntervalSince1970: 0))]
        var field = RecipientBubbles()
        XCTAssertEqual(ComposeForm.suggestions(book, in: field, after: .entered), [])
        field.type("ja")
        XCTAssertEqual(ComposeForm.suggestions(book, in: field, after: .typed).map(\.address),
                       ["jane@example.com", "janet@example.org"])
        field.pick(MailFormat.recipient(name: book[0].name, address: book[0].address).entry)
        XCTAssertEqual(field.entries, ["Jane Example <jane@example.com>"])
        XCTAssertEqual(RecipientBubbles.words(for: field.entries[0]), "Jane Example")
        XCTAssertEqual(ComposeForm.suggestions(book, in: field, after: .picked), [])
        XCTAssertEqual(ComposeForm.suggestions(book, in: field, after: .typed), [])
        field.type("ja")
        XCTAssertEqual(ComposeForm.suggestions(book, in: field, after: .typed).map(\.address),
                       ["janet@example.org"], "no repeats")
        field.type("janet@")
        XCTAssertEqual(ComposeForm.suggestions(book, in: field, after: .typed), [],
                       "nothing once it holds an @")
        // A name with no name in the book is a bubble of its address.
        field.pick(MailFormat.recipient(name: book[1].name, address: book[1].address).entry)
        XCTAssertEqual(field.entries, ["Jane Example <jane@example.com>", "janet@example.org"])
        XCTAssertEqual(field.typed, "")
    }

    /// Leaving the field as a tap on the list lands makes a bubble of the
    /// half-typed name, and the pick takes its place, rather than leaving
    /// "ja" behind as a recipient.
    func testAPickRightAfterLeavingTakesThePlaceOfWhatWasTyped() {
        var field = RecipientBubbles(entries: ["sam@example.org"])
        field.type("ja")
        field.finish(leaving: true)
        XCTAssertEqual(field.entries, ["sam@example.org", "ja"])
        field.pick("Jane Example <jane@example.com>")
        XCTAssertEqual(field.entries, ["sam@example.org", "Jane Example <jane@example.com>"])
        // Return is no leaving: what it made stays.
        field.type("carlo@example.org")
        field.finish()
        field.pick("pat@example.com")
        XCTAssertEqual(field.entries, ["sam@example.org", "Jane Example <jane@example.com>",
                                       "carlo@example.org", "pat@example.com"])
        // Nor does a bubble made by leaving outlast anything done after it.
        field.type("lee")
        field.finish(leaving: true)
        field.backspace()
        field.select(nil)
        field.pick("jerome@example.com")
        XCTAssertEqual(field.entries.suffix(2), ["lee", "jerome@example.com"])
    }

    /// Backspace with nothing typed picks out the last bubble, and a
    /// second takes it off, as in Mail. A tapped bubble is the one a
    /// backspace takes off; typing puts a picked-out bubble back.
    func testBackspacePicksOutThenTakesOff() {
        var field = RecipientBubbles(entries: ["Jane Example <jane@example.com>", "sam@example.org"])
        XCTAssertTrue(field.backspace())
        XCTAssertEqual(field.selected, 1)
        XCTAssertEqual(field.entries.count, 2, "picked out, not yet taken off")
        XCTAssertTrue(field.backspace())
        XCTAssertEqual(field.entries, ["Jane Example <jane@example.com>"])
        XCTAssertNil(field.selected)
        XCTAssertEqual(field.recipients, ["Jane Example <jane@example.com>"])

        field.backspace()
        field.type("c")
        XCTAssertNil(field.selected, "typing puts it back")
        XCTAssertEqual(field.entries.count, 1)

        var tapped = RecipientBubbles(entries: ["a@example.com", "b@example.com", "c@example.com"])
        tapped.select(0)
        XCTAssertEqual(tapped.selected, 0)
        tapped.backspace()
        XCTAssertEqual(tapped.entries, ["b@example.com", "c@example.com"])
        tapped.select(7)
        XCTAssertNil(tapped.selected)
        tapped.remove(at: 1)
        XCTAssertEqual(tapped.entries, ["b@example.com"])
        tapped.remove(at: 5)
        XCTAssertEqual(tapped.entries, ["b@example.com"])

        var empty = RecipientBubbles()
        XCTAssertFalse(empty.backspace())
        XCTAssertNil(empty.selected)
    }

    /// The untouched-letter rule reads the same people through the
    /// bubbles: a reply as it opened is not asked about, a bubble taken off
    /// is.
    func testCancelReadsThePeopleThroughTheBubbles() {
        let m = letter(to: [Self.owner, "sam@example.org"], cc: ["carlo@example.org"])
        let opened = Draft.replying(to: m, all: true, mine: OwnAddresses([Self.owner]))
        var letter = opened
        letter.to = RecipientBubbles(entries: opened.to).recipients
        letter.cc = RecipientBubbles(entries: opened.cc).recipients
        XCTAssertFalse(ComposeForm.asksBeforeClosing(letter, opened: opened))
        var cc = RecipientBubbles(entries: opened.cc)
        cc.backspace()
        cc.backspace()
        letter.cc = cc.recipients
        XCTAssertTrue(ComposeForm.asksBeforeClosing(letter, opened: opened))
    }

    /// A bubble names whom the letter goes to: its words, the address its
    /// menu shows and VoiceOver reads are read from the entry's first line,
    /// as the header and the envelope read it (B-061). A `mailto:` link can
    /// put a line break in an entry; the bubble read all of it, and showed
    /// other@example.net on a letter that went to sam@example.org.
    func testABubbleNamesWhomTheLetterGoesTo() throws {
        let link = "mailto:sam@example.org%0A%3Cother@example.net%3E"
            + "?cc=Pat%20Example%20%3Cpat@example.com%3E%E2%80%A8%3Cother@example.net%3E"
        var draft = try XCTUnwrap(MailtoLink.draft(from: try XCTUnwrap(URL(string: link)), signature: ""))
        draft.to.append("carlo@example.org\u{0085}Carlo <other@example.net>")
        draft.body = "Hello."
        let to = RecipientBubbles(entries: draft.to)
        let cc = RecipientBubbles(entries: draft.cc)
        XCTAssertEqual(to.entries.count, 2)
        XCTAssertEqual(to.entries.map(RecipientBubbles.address(for:)), ["sam@example.org", "carlo@example.org"])
        XCTAssertEqual(to.entries.map(RecipientBubbles.words(for:)), ["sam@example.org", "carlo@example.org"])
        XCTAssertEqual(cc.entries.map(RecipientBubbles.address(for:)), ["pat@example.com"])
        XCTAssertEqual(cc.entries.map(RecipientBubbles.words(for:)), ["Pat Example"])
        for entry in to.entries + cc.entries {
            XCTAssertFalse(RecipientBubbles.words(for: entry).contains("other@"), entry.debugDescription)
        }
        // The same addresses the letter's header names.
        draft.to = to.recipients
        draft.cc = cc.recipients
        let text = String(decoding: RFC5322Builder.build(draft: draft, from: account()), as: UTF8.self)
        XCTAssertTrue(text.contains("\r\nTo: sam@example.org, carlo@example.org\r\n"), text)
        XCTAssertTrue(text.contains("\r\nCc: Pat Example <pat@example.com>\r\n"), text)
        // With no address on the first line, the first line as it is.
        XCTAssertEqual(RecipientBubbles.words(for: "Sam\n<other@example.net>"), "Sam")
        XCTAssertNil(RecipientBubbles.address(for: "Sam\n<other@example.net>"))
    }

    /// Each bubble takes a tap on the whole height of its line and at
    /// least 44 points across, though drawn 30 tall: D-007 binds every
    /// tappable control to 44 by 44. A tap a few points above or below the
    /// pill raised the keyboard.
    func testABubbleTakesATapOnItsWholeLine() throws {
        XCTAssertEqual(RecipientBubbles.touchArea(of: CGRect(x: 0, y: 0, width: 35, height: 30), atLeast: 44),
                       CGRect(x: -4.5, y: -7, width: 44, height: 44))
        XCTAssertEqual(RecipientBubbles.touchArea(of: CGRect(x: 0, y: 0, width: 120, height: 30), atLeast: 44),
                       CGRect(x: 0, y: -7, width: 120, height: 44))
        XCTAssertEqual(RecipientBubbles.touchArea(of: CGRect(x: 0, y: 0, width: 50, height: 50), atLeast: 44),
                       CGRect(x: 0, y: 0, width: 50, height: 50))
        let code = try source(Self.field)
        for line in ["final class BubbleButton: UIButton { override func point(inside point: CGPoint, "
                        + "with event: UIEvent?) -> Bool { RecipientBubbles.touchArea(of: bounds, "
                        + "atLeast: Theme.minHitTarget).contains(point) } }",
                     "let b = BubbleButton(type: .system)",
                     "let w = min(max(ceil(b.intrinsicContentSize.width), Theme.minHitTarget), width)",
                     "b.frame = CGRect(x: x, y: CGFloat(row) * line + (line - tall) / 2, width: w, height: tall)",
                     "let line = Theme.minHitTarget",
                     "menu.popoverPresentationController?.sourceView = sender "
                        + "menu.popoverPresentationController?.sourceRect = sender.bounds"] {
            XCTAssertTrue(code.contains(line), line)
        }
        XCTAssertFalse(code.contains("UIButton(type: .system)"), "every bubble a BubbleButton")
    }

    /// The same people keep their buttons when the field changes, so the
    /// bubble a menu hangs from stays where it is when a comma or Return
    /// makes another under the menu. Every button was made again.
    func testTheSamePeopleKeepTheirButtons() throws {
        let three = ["a@example.com", "b@example.com", "c@example.com"]
        for (old, new, head, tail) in [
            (three, three + ["d@example.com"], 3, 0),
            (three, three + ["d@example.com", "e@example.com"], 3, 0),
            ([], ["a@example.com"], 0, 0),
            (three, Array(three.prefix(2)), 2, 0),
            (three, [three[0], three[2]], 1, 1),
            (three, Array(three.suffix(2)), 0, 2),
            (three, three, 3, 0),
            (three, [], 0, 0),
            (["a@example.com"], ["b@example.com"], 0, 0),
            (["a@example.com", "a@example.com"], ["a@example.com"], 1, 0),
            (["a@example.com"], ["a@example.com", "b@example.com", "a@example.com"], 1, 0),
            (three, [three[0], "x@example.com", three[2]], 1, 1),
        ] as [([String], [String], Int, Int)] {
            let kept = RecipientBubbles.unchanged(from: old, to: new)
            XCTAssertEqual(kept.head, head, "\(old) -> \(new)")
            XCTAssertEqual(kept.tail, tail, "\(old) -> \(new)")
            XCTAssertLessThanOrEqual(kept.head + kept.tail, min(old.count, new.count))
        }
        let code = try source(Self.field)
        for line in ["let (head, tail) = RecipientBubbles.unchanged(from: shown, to: now)",
                     "for b in buttons[head ..< buttons.count - tail] { b.removeFromSuperview() }",
                     "let made: [UIButton] = (head ..< now.count - tail).map",
                     "buttons = Array(buttons[..<head]) + made + Array(buttons[(buttons.count - tail)...])",
                     // The bubble whose menu is up stays picked out, whatever
                     // he types, ends or leaves under it, and goes with its
                     // menu if a backspace takes it off.
                     "bubbles.type(input.text ?? \"\") keepMenu()",
                     "bubbles.finish() keepMenu()",
                     "bubbles.finish(leaving: true) keepMenu()",
                     "if bubbles.entries.indices.contains(i), bubbles.entries[i] == menuEntry { bubbles.select(i) } "
                        + "else { menuFor = nil menuEntry = nil menu?.dismiss(animated: true) }"] {
            XCTAssertTrue(code.contains(line), line)
        }
        XCTAssertFalse(code.contains("for b in buttons { b.removeFromSuperview() }"))
    }

    /// What the bubbles show is whom the letter goes to: each bubble one
    /// recipient, whatever is in it. The field was written out as text and
    /// split again, and one bubble with a quote never closed in it split
    /// every bubble at its commas: two bubbles, three recipients, the first
    /// of them `"Example`, which no server takes.
    func testWhatTheBubblesShowIsWhomTheLetterGoesTo() throws {
        var cc = RecipientBubbles(entries: ["\"Example, Pat\" <pat@example.com>"])
        cc.type("\"Sam")
        cc.finish(leaving: true)
        XCTAssertEqual(cc.entries.map(RecipientBubbles.words(for:)), ["Example, Pat", "\"Sam"])
        XCTAssertEqual(cc.recipients, ["\"Example, Pat\" <pat@example.com>", "\"Sam"])
        XCTAssertTrue(ComposeForm.canSend(to: [], cc: cc.recipients, bcc: []))
        // Kept in a draft and opened again: the same two bubbles.
        XCTAssertEqual(RecipientBubbles(entries: cc.recipients).entries, cc.entries)
        // And the header names Pat as one.
        var draft = Draft()
        draft.cc = cc.recipients
        draft.body = "x"
        let text = String(decoding: RFC5322Builder.build(draft: draft, from: account()), as: UTF8.self)
        XCTAssertTrue(text.contains("\"Example, Pat\" <pat@example.com>"), text)
        // What he is still typing counts, split as typed text always was.
        var to = RecipientBubbles(entries: ["jane@example.com"])
        to.type("\"Example, Sam")
        XCTAssertEqual(to.recipients, ["jane@example.com", "\"Example", "Sam"])
        // The suggestions leave out each bubble's address, and match what he
        // types after them.
        let book = [KnownRecipient(address: "pat@example.com", name: "Pat Example", uses: 2,
                                   lastSeen: Date(timeIntervalSince1970: 0)),
                    KnownRecipient(address: "patrick@example.org", name: nil, uses: 1,
                                   lastSeen: Date(timeIntervalSince1970: 0))]
        cc.type("pa")
        XCTAssertEqual(ComposeForm.suggestions(book, in: cc, after: .typed).map(\.address),
                       ["patrick@example.org"])
    }

    // MARK: - The wiring, read from the source

    /// Both composers: To, Cc and Bcc are bubble fields, filled with the
    /// letter's entries, a pick a bubble with its name, and the fields read
    /// a bubble at a time by Send, the suggestions and the letter, never
    /// written out as text and split again.
    func testBothComposersShowBubbles() throws {
        for file in [Self.composer, Self.share] {
            let code = try source(file)
            for line in ["private let toField = RecipientField()",
                         "private let ccField = RecipientField()",
                         "private let bccField = RecipientField()",
                         "private weak var activeAddressField: RecipientField?",
                         "field.show(entries)",
                         "let picked = suggestions[ip.row] "
                            + "field.pick(MailFormat.recipient(name: picked.name, address: picked.address).entry)",
                         "draft.to = toField.recipients",
                         "draft.cc = ccField.recipients",
                         "draft.bcc = bccField.recipients",
                         "sendItem.isEnabled = ComposeForm.canSend(to: toField.recipients, "
                            + "cc: ccField.recipients, bcc: bccField.recipients)",
                         "field.topAnchor.constraint(equalTo: container.topAnchor)",
                         "field.bottomAnchor.constraint(equalTo: container.bottomAnchor)"] {
                XCTAssertTrue(code.contains(line), "\(file): \(line)")
            }
            XCTAssertFalse(code.contains("replacingRecipientToken"), file)
            XCTAssertFalse(code.contains("joined(separator: \", \")))"), file)
            XCTAssertFalse(code.contains("UISearchTextField"), file)
            for text in ["toField.text", "ccField.text", "bccField.text", "field.text ??"] {
                XCTAssertFalse(code.contains(text), "\(file): \(text)")
            }
        }
        XCTAssertTrue(try source(Self.composer).contains("suggestions = ComposeForm.suggestions("
            + "RecipientBook.shared.snapshot(), in: field.bubbles, after: event)"))
        XCTAssertTrue(try source(Self.share).contains("suggestions = sheet.suggestions(in: field.bubbles, "
            + "after: event)"))
        let composer = try source(Self.composer)
        XCTAssertTrue(composer.contains("addressRow(label: \"To:\", field: toField, entries: draft.to)"))
        XCTAssertTrue(composer.contains("addressRow(label: \"Cc:\", field: ccField, entries: draft.cc)"))
        XCTAssertTrue(composer.contains("addressRow(label: \"Bcc:\", field: bccField, entries: draft.bcc)"))
        XCTAssertTrue(composer.contains("field.addTarget(self, action: #selector(letterEdited), "
            + "for: .editingChanged) field.addTarget(self, action: #selector(addressEditingChanged(_:)), "
            + "for: .editingChanged)"))
        let share = try source(Self.share)
        XCTAssertTrue(share.contains("addressRow(\"To:\", toField, draft.to)"))
        XCTAssertTrue(share.contains("ccRow = addressRow(\"Cc:\", ccField, draft.cc) "
            + "bccRow = addressRow(\"Bcc:\", bccField, draft.bcc)"))
    }

    /// The field: backspace with nothing typed goes to the bubbles, Return
    /// and leaving make one, a comma as he types, a tap shows the address
    /// and Remove, and each change he makes is told to the sheet. Plain
    /// UIKit, no search field's tokens. Fonts fixed and the sheet's dark.
    func testTheFieldDoesWhatMailsDoes() throws {
        let code = try source(Self.field)
        for line in ["final class RecipientField: UIControl, UITextFieldDelegate",
                     "override func deleteBackward() { if (text ?? \"\").isEmpty, markedTextRange == nil, "
                        + "let backspaceWhenEmpty { backspaceWhenEmpty() return } super.deleteBackward() }",
                     "input.backspaceWhenEmpty = { [weak self] in self?.backspace() }",
                     "let before = bubbles.entries guard bubbles.backspace() else { return } keepMenu() "
                        + "rebuild() if bubbles.entries != before { sendActions(for: .editingChanged) }",
                     "bubbles.type(input.text ?? \"\")",
                     "bubbles.finish(leaving: true)",
                     "func textFieldShouldReturn(_ textField: UITextField) -> Bool { "
                        + "let before = (bubbles.entries, bubbles.typed) bubbles.finish() keepMenu()",
                     "var recipients: [String] { bubbles.recipients }",
                     "input.keyboardType = .emailAddress",
                     "let menu = UIAlertController(title: words, message: address == words ? nil : address, "
                        + "preferredStyle: .actionSheet)",
                     "UIAlertAction(title: \"Remove\", style: .destructive)",
                     "bubbles.remove(at: index) rebuild() sendActions(for: .editingChanged)",
                     "menu.overrideUserInterfaceStyle = .dark",
                     "look.background.backgroundColor = selected ? Theme.tintBlue : Theme.recipientBubbleFill",
                     "title.foregroundColor = Theme.primaryText",
                     "let tall = CGFloat(lines) * Theme.minHitTarget"] {
            XCTAssertTrue(code.contains(line), line)
        }
        XCTAssertFalse(code.contains("UISearchTextField("))
        XCTAssertFalse(code.contains("var text:"), "read a bubble at a time, not as text")
        XCTAssertFalse(code.contains("UIFontMetrics"), "fixed sizes (D-007)")
        XCTAssertFalse(code.contains("preferredFont"), "fixed sizes (D-007)")
    }

    /// Settings: Mail's list under the account, the account's own first
    /// and alone without Remove, "Add Another Email…", saved with the
    /// account, which the mirror hands the share extension.
    func testSettingsHasMailsListOfHisAddresses() throws {
        let code = try source(Self.settings)
        for line in ["addEmail.setTitle(\"Add Another Email…\", for: .normal)",
                     "for (index, address) in account.ownAddresses.enumerated()",
                     "if index > 0 { let remove = UIButton(type: .system) remove.setTitle(\"Remove\", for: .normal)",
                     "switch account.adding(typed) { case .success(let added): account = added",
                     "account = account.removing(address)",
                     "field.keyboardType = .emailAddress",
                     "var updated = account"] {
            XCTAssertTrue(code.contains(line), line)
        }
        let store = try source("Sources/Blackmail/Mail/CredentialStore.swift")
        XCTAssertTrue(store.contains("out.otherAddresses = Array(out.ownAddresses.dropFirst())"))
        XCTAssertTrue(store.contains("mirror.publish(account: clean, password: password)"))
        // The app's Reply asks the account for every address of his.
        let pane = try source("Sources/Blackmail/UI/MessageDetailViewController.swift")
        XCTAssertTrue(pane.contains("mine: OwnAddresses(account: account)"))
        let own = try source("Sources/Blackmail/Model/ReplyAddressing.swift")
        XCTAssertTrue(own.contains("self.init((account?.ownAddresses ?? []) + "
            + "[account?.username].compactMap { $0 })"))
    }

    // MARK: - Helpers

    private static let composer = "Sources/Blackmail/UI/ComposeViewController.swift"
    private static let share = "Sources/Blackmail/Share/ShareViewController.swift"
    private static let field = "Sources/Blackmail/UI/RecipientField.swift"
    private static let settings = "Sources/Blackmail/UI/SettingsViewController.swift"

    private final class MemoryKeychain: SharedKeychain {
        var items: [String: Data] = [:]
        func data(named name: String) -> Data? { items[name] }
        func store(_ data: Data, named name: String) -> Bool {
            items[name] = data
            return true
        }
        func remove(named name: String) { items[name] = nil }
        func names() -> [String] { Array(items.keys) }
    }

    private func count(_ needle: String, in code: String) -> Int {
        code.components(separatedBy: needle).count - 1
    }

    /// The file's code with its comment lines dropped and its spacing
    /// made single, so a line is found however it is wrapped.
    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }
}
