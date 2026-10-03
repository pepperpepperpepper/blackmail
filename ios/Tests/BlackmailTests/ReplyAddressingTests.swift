import XCTest
@testable import Blackmail

/// Whom Reply and Reply All go to (B-061): the letter's Reply-To before its
/// From, a letter of his own answered to whom it went, his own addresses in
/// every spelling Gmail delivers to him left out, each recipient once and
/// with the name the letter gave it.
///
/// A wrongly addressed letter cannot be called back, and none of this shows
/// on the sending screen until it has gone, so every rule in
/// `ReplyAddressing` is pinned here on its own, and then all of them at once
/// over thousands of letters made up from awkward addresses.
///
/// Gmail addresses here have an underscore in the name, which Gmail does not
/// allow in one, so none of them is anybody's.
final class ReplyAddressingTests: XCTestCase {

    private static let owner = "owner_example@gmail.com"
    private let mine = OwnAddresses([ReplyAddressingTests.owner])

    /// A letter as the repository draws one: `from` and `alsoFrom` its
    /// From's entries, which `sender` holds as one, and none for a letter
    /// with no From.
    private func letter(from: String? = "Jane Example <jane@example.com>", alsoFrom: [String] = [],
                        replyTo: [String] = [], to: [String] = [ReplyAddressingTests.owner],
                        cc: [String] = []) -> Message {
        let authors = from.map { [$0] + alsoFrom } ?? []
        let sender = from == nil ? "(unknown sender)" : authors.joined(separator: ", ")
        return Message(id: "1/9", mailboxID: "INBOX", sender: sender,
                       senderAddress: MailFormat.bareAddress(sender),
                       to: to, cc: cc, replyTo: replyTo, from: authors, subject: "Lunch",
                       date: Date(timeIntervalSince1970: 1_700_000_000),
                       textBody: "hi", htmlBody: nil, attachments: [])
    }

    private func reply(_ m: Message, all: Bool = false) -> ReplyAddressing {
        ReplyAddressing.reply(to: m, all: all, mine: mine)
    }

    // MARK: - Reply-To

    /// A list sets Reply-To to the list: Reply goes there, and not to the
    /// member who wrote.
    func testReplyGoesToTheReplyTo() {
        let m = letter(replyTo: ["Garden Club <club@example.org>"],
                       to: ["club@example.org"])
        XCTAssertEqual(reply(m), ReplyAddressing(to: ["Garden Club <club@example.org>"], cc: []))
    }

    func testReplyGoesToTheFromWhenThereIsNoReplyTo() {
        XCTAssertEqual(reply(letter()), ReplyAddressing(to: ["Jane Example <jane@example.com>"],
                                                        cc: []))
    }

    func testReplyGoesToEveryReplyToInItsOrder() {
        let m = letter(replyTo: ["sam@example.org", "Carlo <carlo@example.org>"])
        XCTAssertEqual(reply(m).to, ["sam@example.org", "Carlo <carlo@example.org>"])
    }

    /// A Reply-To that is the From written another way is one recipient.
    func testAReplyToThatIsTheFromIsOneRecipient() {
        let m = letter(replyTo: ["JANE@Example.com"], cc: ["jane@example.com"])
        XCTAssertEqual(reply(m), ReplyAddressing(to: ["JANE@Example.com"], cc: []))
        XCTAssertEqual(reply(m, all: true),
                       ReplyAddressing(to: ["JANE@Example.com"], cc: []))
    }

    /// A Reply-To with no address in it is no Reply-To.
    func testAReplyToWithNoAddressInItLeavesTheFrom() {
        let m = letter(replyTo: ["undisclosed-recipients:;"])
        XCTAssertEqual(reply(m).to, ["Jane Example <jane@example.com>"])
    }

    /// Reply All goes to the Reply-To in place of the From, and to the
    /// letter's To in To and its Cc in Cc, as Mail addresses it.
    func testReplyAllGoesToTheReplyToTheToAndTheCc() {
        let m = letter(replyTo: ["Garden Club <club@example.org>"],
                       to: ["club@example.org", Self.owner, "Sam Example <sam@example.org>"],
                       cc: ["carlo@example.org"])
        XCTAssertEqual(reply(m, all: true),
                       ReplyAddressing(to: ["Garden Club <club@example.org>",
                                            "Sam Example <sam@example.org>"],
                                       cc: ["carlo@example.org"]))
    }

    func testReplyAllWithNoReplyToGoesToTheFromFirst() {
        let m = letter(to: [Self.owner, "sam@example.org"], cc: ["carlo@example.org"])
        XCTAssertEqual(reply(m, all: true),
                       ReplyAddressing(to: ["Jane Example <jane@example.com>", "sam@example.org"],
                                       cc: ["carlo@example.org"]))
    }

    // MARK: - His own letter

    /// The fault the gap review found: his own letter, in Sent Mail or in a
    /// conversation, was answered to himself.
    func testReplyToHisOwnLetterGoesToWhomItWent() {
        let m = letter(from: "Owner <\(Self.owner)>", to: ["Jane Example <jane@example.com>"])
        XCTAssertEqual(reply(m), ReplyAddressing(to: ["Jane Example <jane@example.com>"], cc: []))
        XCTAssertEqual(reply(m, all: true),
                       ReplyAddressing(to: ["Jane Example <jane@example.com>"], cc: []))
    }

    /// Written as Gmail might show it in another spelling of his address,
    /// it is still his.
    func testHisOwnLetterIsKnownInEverySpellingOfHisAddress() {
        for from in ["Owner_Example@GMAIL.com", "o.wner_example@gmail.com",
                     "owner_example+lists@googlemail.com", "Owner <OWNER_EXAMPLE@googlemail.com>"] {
            let m = letter(from: from, to: ["sam@example.org"])
            XCTAssertEqual(reply(m).to, ["sam@example.org"], from)
        }
    }

    func testReplyAllToHisOwnLetterKeepsItsToAndCc() {
        let m = letter(from: Self.owner, replyTo: ["elsewhere@example.org"],
                       to: ["jane@example.com", "Sam Example <sam@example.org>"],
                       cc: ["carlo@example.org"])
        XCTAssertEqual(reply(m), ReplyAddressing(to: ["jane@example.com",
                                                      "Sam Example <sam@example.org>"], cc: []))
        // Its Reply-To is where he asked others to answer him; his own
        // answer does not go there.
        XCTAssertEqual(reply(m, all: true),
                       ReplyAddressing(to: ["jane@example.com", "Sam Example <sam@example.org>"],
                                       cc: ["carlo@example.org"]))
    }

    /// A letter he sent himself is answered to himself: he is the only one
    /// it can go to.
    func testHisLetterToHimselfIsAnsweredToHimself() {
        let m = letter(from: Self.owner, to: [Self.owner])
        XCTAssertEqual(reply(m), ReplyAddressing(to: [Self.owner], cc: []))
        XCTAssertEqual(reply(m, all: true), ReplyAddressing(to: [Self.owner], cc: []))
    }

    func testHisLetterToHimselfAndJaneIsAnsweredToJane() {
        let m = letter(from: Self.owner, to: [Self.owner, "jane@example.com"])
        XCTAssertEqual(reply(m).to, ["jane@example.com"])
    }

    /// His letter with nobody in To: Reply goes to its Cc.
    func testHisLetterWithOnlyACcIsAnsweredToTheCc() {
        let m = letter(from: Self.owner, to: [], cc: ["carlo@example.org"])
        XCTAssertEqual(reply(m), ReplyAddressing(to: ["carlo@example.org"], cc: []))
        XCTAssertEqual(reply(m, all: true), ReplyAddressing(to: ["carlo@example.org"], cc: []))
    }

    /// His letter sent by Bcc alone names nobody: it is answered to him.
    func testHisLetterToNobodyNamedIsAnsweredToHim() {
        let m = letter(from: "Owner <\(Self.owner)>", to: ["undisclosed-recipients:;"])
        XCTAssertEqual(reply(m), ReplyAddressing(to: ["Owner <\(Self.owner)>"], cc: []))
        XCTAssertEqual(reply(m, all: true), ReplyAddressing(to: ["Owner <\(Self.owner)>"], cc: []))
    }

    /// His letter to himself with Jane in Cc: Reply All goes to Jane, in
    /// To, not to him with Jane in Cc, nor to nobody in To.
    func testACcLeftAloneMovesUpToTo() {
        let m = letter(from: Self.owner, to: [Self.owner], cc: ["jane@example.com"])
        XCTAssertEqual(reply(m, all: true), ReplyAddressing(to: ["jane@example.com"], cc: []))
        XCTAssertEqual(reply(m), ReplyAddressing(to: [Self.owner], cc: []))
    }

    // MARK: - A From of several

    /// A letter written by several is answered to every one of them, as
    /// RFC 5322 has it with no Reply-To, each with their name. The From
    /// read as one entry, as `sender` holds it, went to all of them by
    /// accident, or with names to the last alone.
    func testALetterFromSeveralIsAnsweredToEachOfThem() {
        let m = letter(from: "jane@example.com", alsoFrom: ["Sam Example <sam@example.org>"],
                       to: [Self.owner, "carlo@example.org"])
        XCTAssertEqual(m.sender, "jane@example.com, Sam Example <sam@example.org>")
        XCTAssertEqual(reply(m), ReplyAddressing(to: ["jane@example.com", "Sam Example <sam@example.org>"],
                                                 cc: []))
        XCTAssertEqual(reply(m, all: true),
                       ReplyAddressing(to: ["jane@example.com", "Sam Example <sam@example.org>",
                                            "carlo@example.org"], cc: []))
        let named = letter(from: "Jane Example <jane@example.com>",
                           alsoFrom: ["\"Example, Sam\" <sam@example.org>"])
        XCTAssertEqual(reply(named).to, ["Jane Example <jane@example.com>",
                                         "\"Example, Sam\" <sam@example.org>"])
        // A Reply-To still comes first.
        XCTAssertEqual(reply(letter(from: "jane@example.com", alsoFrom: ["sam@example.org"],
                                    replyTo: ["club@example.org"])).to, ["club@example.org"])
    }

    /// A letter with his address anywhere in its From is his own, and is
    /// answered to whom it went; sent by Bcc alone, to him, and not to
    /// whoever wrote it with him.
    func testALetterHeWroteWithSomeoneElseIsHisOwn() {
        let m = letter(from: "Jane Example <jane@example.com>", alsoFrom: ["Owner <\(Self.owner)>"],
                       to: ["carlo@example.org"], cc: ["sam@example.org"])
        XCTAssertEqual(reply(m), ReplyAddressing(to: ["carlo@example.org"], cc: []))
        XCTAssertEqual(reply(m, all: true),
                       ReplyAddressing(to: ["carlo@example.org"], cc: ["sam@example.org"]))
        let byBcc = letter(from: "Jane Example <jane@example.com>", alsoFrom: ["Owner <\(Self.owner)>"],
                           to: [])
        XCTAssertEqual(reply(byBcc), ReplyAddressing(to: ["Owner <\(Self.owner)>"], cc: []))
        XCTAssertEqual(reply(byBcc, all: true), ReplyAddressing(to: ["Owner <\(Self.owner)>"], cc: []))
    }

    // MARK: - Names broken over lines

    /// Every line break and control character in a name is a space, and
    /// any in an address is taken out, so each entry is one line and its
    /// last `<…>` is the address compared. A Windows "…" sent as
    /// ISO-8859-1 decodes as U+0085, NEXT LINE, with nobody meaning harm.
    func testANameBrokenOverLinesIsOneLine() {
        for (entry, kept) in [
            ("Jane\nExample <jane@example.com>", "Jane Example <jane@example.com>"),
            ("Jane\r\nExample <jane@example.com>", "Jane Example <jane@example.com>"),
            ("Jane\u{2028}Example <jane@example.com>", "Jane Example <jane@example.com>"),
            ("Jane\u{2029}Example <jane@example.com>", "Jane Example <jane@example.com>"),
            ("Jane\u{0085}Example <jane@example.com>", "Jane Example <jane@example.com>"),
            ("Jane\u{000B}\u{000C}\tExample <jane@example.com>", "Jane Example <jane@example.com>"),
            ("Jane\u{007F}\u{009B}Example <jane@example.com>", "Jane Example <jane@example.com>"),
            ("Jane\u{0000}Example <jane@example.com>", "Jane Example <jane@example.com>"),
            ("<other@example.net>\nSam <sam@example.org>", "\"<other@example.net> Sam\" <sam@example.org>"),
            ("<other@example.net>\u{2028}Sam <sam@example.org>",
             "\"<other@example.net> Sam\" <sam@example.org>"),
            ("\"Example,\u{0085}Jane\" <jane@example.com>", "\"Example, Jane\" <jane@example.com>"),
            ("jane@example.com (Jane\u{2028}Example)", "Jane Example <jane@example.com>"),
            ("Friends:\njane@example.com;", "jane@example.com"),
            ("Jane <jane@exa\u{2028}mple.com\u{0085}>", "Jane <jane@example.com>"),
            ("\u{2028}<jane@example.com>", "jane@example.com"),
        ] {
            let r = MailFormat.recipient(in: entry)
            XCTAssertEqual(r?.entry, kept, entry.debugDescription)
            XCTAssertEqual(MailFormat.fieldEntry(entry), kept, entry.debugDescription)
            XCTAssertEqual(r.map { MailFormat.bareAddress(RFC5322Builder.recipientLine($0.entry)) },
                           r?.address, "the envelope's address is the one compared")
        }
        // An entry with no address in it is left for him to see, on one
        // line.
        XCTAssertEqual(MailFormat.fieldEntry("Jane\u{2028}\u{2028}Example\n"), "Jane Example")
        XCTAssertEqual(MailFormat.oneLine("a\r\n\u{0085}b\u{2029}c"), "a b c")
    }

    /// A reply to a letter whose names are broken over lines, From, To and
    /// Cc, is addressed on one line, every entry.
    func testAReplyToNamesBrokenOverLinesIsAllOneLine() {
        for gap in ["\n", "\r\n", "\u{2028}", "\u{0085}"] {
            let m = letter(from: "Jane\(gap)Example <jane@example.com>",
                           to: [Self.owner, "<other@example.net>\(gap)Sam <sam@example.org>"],
                           cc: ["Pat\(gap)Example <pat@example.com>"])
            XCTAssertEqual(reply(m), ReplyAddressing(to: ["Jane Example <jane@example.com>"], cc: []),
                           gap.debugDescription)
            XCTAssertEqual(reply(m, all: true),
                           ReplyAddressing(to: ["Jane Example <jane@example.com>",
                                                "\"<other@example.net> Sam\" <sam@example.org>"],
                                           cc: ["Pat Example <pat@example.com>"]), gap.debugDescription)
        }
    }

    // MARK: - His own addresses

    /// Every spelling Gmail delivers to him is left out of a Reply All.
    func testReplyAllLeavesOutEverySpellingOfHisAddress() {
        let m = letter(to: ["Owner_Example@Gmail.com", "o.wner_example@gmail.com", "sam@example.org"],
                       cc: ["owner_example+lists@googlemail.com", "Owner <OWNER_EXAMPLE@GOOGLEMAIL.COM>",
                            "carlo@example.org"])
        XCTAssertEqual(reply(m, all: true),
                       ReplyAddressing(to: ["Jane Example <jane@example.com>", "sam@example.org"],
                                       cc: ["carlo@example.org"]))
    }

    /// Only Gmail's own domains: elsewhere a dot or a tag may be another
    /// person, and taking a stranger for him would leave the stranger out,
    /// unseen.
    func testAnotherDomainsSpellingsAreOtherPeople() {
        let his = OwnAddresses(["sam.example@example.org"])
        XCTAssertTrue(his.contains("SAM.Example@Example.org"))
        XCTAssertTrue(his.contains("Sam <sam.example@example.org>"))
        for other in ["samexample@example.org", "sam.example+x@example.org",
                      "sam.example@example.com"] {
            XCTAssertFalse(his.contains(other), other)
        }
        let m = letter(to: ["sam.example@example.org", "samexample@example.org"],
                       cc: ["sam.example+x@example.org"])
        XCTAssertEqual(ReplyAddressing.reply(to: m, all: true, mine: his),
                       ReplyAddressing(to: ["Jane Example <jane@example.com>", "samexample@example.org"],
                                       cc: ["sam.example+x@example.org"]))
    }

    func testGmailsSpellingsAreOneMailbox() {
        XCTAssertEqual(OwnAddresses.key("O.Wner_Example+news@GoogleMail.com"), "owner_example@gmail.com")
        XCTAssertEqual(OwnAddresses.key("Owner <owner_example@gmail.com>"), "owner_example@gmail.com")
        // Nothing left of the name but dots and a tag: as written.
        XCTAssertEqual(OwnAddresses.key(".+x@gmail.com"), ".+x@gmail.com")
        XCTAssertNil(OwnAddresses.key("Owner"))
        XCTAssertNil(OwnAddresses.key("@gmail.com"))
        XCTAssertNil(OwnAddresses.key(""))
    }

    /// The account's login is his too, where it differs from the address.
    func testTheAccountsLoginIsHisToo() {
        let account = MailAccount(address: "owner@example.com", username: Self.owner)
        let his = OwnAddresses(account: account)
        XCTAssertTrue(his.contains("owner@example.com"))
        XCTAssertTrue(his.contains("o.wner_example@googlemail.com"))
        XCTAssertFalse(his.contains("jane@example.com"))
        XCTAssertFalse(OwnAddresses(account: nil).contains("owner@example.com"))
    }

    /// A Reply-To of his on someone else's letter is where its sender asked
    /// to be answered: Reply goes there.
    func testAReplyToOfHisIsFollowed() {
        let m = letter(replyTo: [Self.owner], to: [Self.owner])
        XCTAssertEqual(reply(m).to, [Self.owner])
    }

    func testReplyAllToALetterOnlyToHimGoesToTheSenderAlone() {
        XCTAssertEqual(reply(letter(), all: true),
                       ReplyAddressing(to: ["Jane Example <jane@example.com>"], cc: []))
    }

    // MARK: - Once each, with names

    func testEachAddressOnceToBeforeCcWithTheFirstNameGiven() {
        let m = letter(to: [Self.owner, "sam@example.org", "Carlo <carlo@example.org>"],
                       cc: ["Sam Example <SAM@example.org>", "CARLO@example.org", "jane@EXAMPLE.com",
                            "pat@example.com", "Pat Example <pat@example.com>"])
        XCTAssertEqual(reply(m, all: true),
                       ReplyAddressing(to: ["Jane Example <jane@example.com>",
                                            "Sam Example <sam@example.org>",
                                            "Carlo <carlo@example.org>"],
                                       cc: ["Pat Example <pat@example.com>"]))
    }

    /// Every way a header names a recipient, as the composer's field keeps
    /// it: the name quoted where it holds a comma or a quote, the address
    /// alone where there is no name.
    func testEveryFormOfARecipientIsKeptWithItsName() {
        for (entry, kept) in [
            ("Jane Example <jane@example.com>", "Jane Example <jane@example.com>"),
            ("\"Example, Jane\" <jane@example.com>", "\"Example, Jane\" <jane@example.com>"),
            ("Example, Jane <jane@example.com>", "\"Example, Jane\" <jane@example.com>"),
            ("\"Sam \\\"The Gardener\\\" Example\" <sam@example.org>",
             "\"Sam \\\"The Gardener\\\" Example\" <sam@example.org>"),
            ("'Jane Example' <jane@example.com>", "Jane Example <jane@example.com>"),
            ("\"\" <jane@example.com>", "jane@example.com"),
            ("<jane@example.com>", "jane@example.com"),
            ("jane@example.com <jane@example.com>", "jane@example.com"),
            ("  jane@example.com  ", "jane@example.com"),
            ("jane@example.com (Jane Example)", "Jane Example <jane@example.com>"),
            ("Friends: jane@example.com", "jane@example.com"),
            ("sam@example.org;", "sam@example.org"),
            ("\"Re: Jane\" <jane@example.com>", "\"Re: Jane\" <jane@example.com>"),
            ("J\u{00E9}r\u{00F4}me Example <jerome@example.com>",
             "J\u{00E9}r\u{00F4}me Example <jerome@example.com>"),
        ] {
            XCTAssertEqual(MailFormat.recipient(in: entry)?.entry, kept, entry)
            XCTAssertEqual(MailFormat.fieldEntry(entry), kept, entry)
            XCTAssertEqual(MailFormat.fieldEntry(kept), kept, "once kept, kept so: \(kept)")
        }
        for nobody in ["undisclosed-recipients:;", "Jane", "(unknown sender)", "", "Friends:;"] {
            XCTAssertNil(MailFormat.recipient(in: nobody), nobody)
            XCTAssertEqual(MailFormat.fieldEntry(nobody), nobody, "his to see and mend")
        }
    }

    /// The composer's field splits between recipients and never inside a
    /// quoted name, so a reply's recipients come out of it as they went in.
    func testTheComposersFieldKeepsEachRecipientWhole() {
        let to = ["\"Example, Jane\" <jane@example.com>", "Sam Example <sam@example.org>",
                  "\"Sam \\\"The Gardener\\\", Example\" <sam@example.com>", "carlo@example.org"]
        XCTAssertEqual(MailFormat.addresses(in: to.joined(separator: ", ")), to)
        XCTAssertEqual(MailFormat.addresses(in: to.joined(separator: ", ") + ", "), to)
        // A quote never closed is split at every comma, as before.
        XCTAssertEqual(MailFormat.addresses(in: "\"Example, jane@example.com, sam@example.org"),
                       ["\"Example", "jane@example.com", "sam@example.org"])
    }

    /// The names go out in the letter's header as the field has them, a
    /// quoted pair once and not with its backslash doubled, and a name
    /// with a comma, encoded, comes back as one recipient.
    func testTheNamesGoOutInTheHeaderAsKept() throws {
        let account = MailAccount(address: Self.owner, username: Self.owner)
        func built(_ m: Message, all: Bool = false) -> Data {
            var draft = Draft.replying(to: m, all: all, mine: mine)
            draft.body = "Yes."
            return RFC5322Builder.build(draft: draft, from: account)
        }
        let gardener = String(decoding: built(letter(
            from: "\"Sam \\\"The Gardener\\\" Example\" <sam@example.org>")), as: UTF8.self)
        XCTAssertTrue(gardener.contains("\r\nTo: \"Sam \\\"The Gardener\\\" Example\" <sam@example.org>\r\n"),
                      gardener)

        let raw = built(letter(to: [Self.owner, "Example, J\u{00E9}r\u{00F4}me <jerome@example.com>"],
                               cc: ["\"Example, Pat\" <pat@example.com>"]), all: true)
        XCTAssertEqual(ReplyAddressingTests.recipients("To", in: raw),
                       [MailFormat.Recipient(name: "Jane Example", address: "jane@example.com"),
                        MailFormat.Recipient(name: "Example, J\u{00E9}r\u{00F4}me",
                                             address: "jerome@example.com")])
        XCTAssertEqual(ReplyAddressingTests.recipients("Cc", in: raw),
                       [MailFormat.Recipient(name: "Example, Pat", address: "pat@example.com")])
    }

    /// A header of a built letter, read back as the repository reads one.
    static func recipients(_ name: String, in raw: Data) -> [MailFormat.Recipient] {
        let headers = MIMEDecoder.parseHeaders(raw)
        return MailFormat.addressList(MIMEDecoder.headerValue(name, in: headers) ?? "")
            .map(MIMEDecoder.decodeWord)
            .compactMap { MailFormat.recipient(in: $0) }
    }

    // MARK: - A letter with no From

    func testALetterWithNoFromIsAnsweredToItsReplyToOrToNobody() {
        XCTAssertEqual(reply(letter(from: nil)), ReplyAddressing(to: [], cc: []))
        XCTAssertEqual(reply(letter(from: nil, replyTo: ["sam@example.org"])).to, ["sam@example.org"])
        XCTAssertEqual(reply(letter(from: nil, to: [Self.owner, "carlo@example.org"]), all: true),
                       ReplyAddressing(to: ["carlo@example.org"], cc: []))
        // Never "(unknown sender)", which used to be put in To.
        XCTAssertEqual(Draft.replying(to: letter(from: nil), all: false, mine: mine).to, [])
    }

    // MARK: - Forward

    func testForwardStillGoesToNobody() {
        let m = letter(replyTo: ["club@example.org"], to: [Self.owner, "sam@example.org"],
                       cc: ["carlo@example.org"])
        let draft = Draft.forwarding(m)
        XCTAssertEqual(draft.to, [])
        XCTAssertEqual(draft.cc, [])
        XCTAssertEqual(draft.bcc, [])
    }

    // MARK: - All of it at once

    /// Letters made up from awkward entries, seeded so a failure is the
    /// same letter every run: the rules hold for every one of them, Reply
    /// and Reply All, his own letters and other people's.
    func testEveryRuleHoldsOverManyLetters() throws {
        let his = ["owner_example@gmail.com", "Owner_Example@GMAIL.com",
                   "owner_example+lists@googlemail.com", "o.wner_example@gmail.com",
                   "Owner <owner_example@gmail.com>"]
        let others = ["jane@example.com", "Jane Example <JANE@example.com>",
                      "\"Example, Jane\" <jane@example.com>", "Example, Jane <jane@example.com>",
                      "sam@example.org", "Sam Example <sam@example.org>",
                      "\"Sam \\\"The Gardener\\\" Example\" <sam@example.org>",
                      "carlo@example.org", "pat@example.com (Pat Example)", "Garden Club <club@example.org>",
                      "club@example.org", "sam.example@example.org", "samexample@example.org",
                      "sam.example+x@example.org", "J\u{00E9}r\u{00F4}me <jerome@example.com>",
                      "Jane\u{2028}Example <jane@example.com>", "<other@example.net>\nSam <sam@example.org>",
                      "Pat\u{0085}Example <pat@example.com>", "Carlo\r\nExample <carlo@example.org>"]
        let nobody = ["undisclosed-recipients:;", "Jane", "Friends:;"]
        let pool = his + others + nobody

        var seed: UInt64 = 0x0B1A_C4A1_1061
        func next(_ n: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(n))
        }
        func some(_ most: Int) -> [String] { (0..<next(most + 1)).map { _ in pool[next(pool.count)] } }
        func address(_ entry: String) -> String? { MailFormat.recipient(in: entry)?.address.lowercased() }
        func addresses(_ entries: [String]) -> Set<String> { Set(entries.compactMap(address)) }
        func isHis(_ a: String) -> Bool { mine.contains(a) }
        func breaksLine(_ s: Unicode.Scalar) -> Bool {
            s.value < 0x20 || (0x7F...0x9F).contains(s.value) || s.value == 0x2028 || s.value == 0x2029
        }

        // Each rule broken, with the first letter that broke it: one
        // failure for the lot, rather than one for every letter.
        var broken: [String: String] = [:]
        var letters = 0
        for _ in 0..<3_000 {
            let fromChoice = next(pool.count + 2)
            let from: String? = fromChoice < pool.count ? pool[fromChoice]
                : fromChoice == pool.count ? nil : his[next(his.count)]
            // Now and then a letter written by two.
            let alsoFrom = from != nil && next(5) == 0 ? [pool[next(pool.count)]] : []
            let m = letter(from: from, alsoFrom: alsoFrom, replyTo: next(3) == 0 ? some(2) : [],
                           to: some(4), cc: some(3))
            let fromAddresses = addresses(m.from)
            let own = fromAddresses.contains(where: isHis)
            let replyTo = addresses(m.replyTo)
            let to = addresses(m.to)
            let cc = addresses(m.cc)
            let author = own ? [] : (replyTo.isEmpty ? fromAddresses : replyTo)

            for all in [false, true] {
                letters += 1
                let r = reply(m, all: all)
                let what = "\(all ? "Reply All" : "Reply") to \(m.from) / \(m.replyTo) / \(m.to) / "
                    + "\(m.cc) gave \(r.to) / \(r.cc)"
                func check(_ rule: String, _ holds: Bool) {
                    if !holds, broken[rule] == nil { broken[rule] = what }
                }
                let outTo = r.to.compactMap(address)
                let outCc = r.cc.compactMap(address)
                let out = outTo + outCc
                check("every entry an address", outTo.count == r.to.count && outCc.count == r.cc.count)
                check("every entry one line, the envelope's address the one compared",
                      (r.to + r.cc).allSatisfy { e in
                          !e.unicodeScalars.contains(where: breaksLine)
                              && MailFormat.bareAddress(RFC5322Builder.recipientLine(e)).lowercased()
                                == address(e)
                      })

                let offered = to.union(cc).union(replyTo).union(fromAddresses)
                check("nothing invented", Set(out).isSubset(of: offered))
                check("nothing twice", Set(out).count == out.count)
                check("him only when there is nobody else",
                      !out.contains(where: isHis) || out.allSatisfy(isHis))
                check("a To whenever there is a Cc", !outTo.isEmpty || outCc.isEmpty)

                let expected: Set<String>
                if own {
                    expected = all ? to.union(cc) : (to.isEmpty ? cc : to)
                    check("his own letter's Reply-To not followed",
                          Set(out).isSubset(of: to.union(cc).union(fromAddresses)))
                    check("his own letter to nobody named answered to him alone",
                          !expected.isEmpty || (out.count == 1 && isHis(out[0])))
                } else {
                    expected = all ? author.union(to).union(cc) : author
                    for f in fromAddresses where !replyTo.isEmpty && !expected.contains(f) {
                        check("the From gives way to the Reply-To", !out.contains(f))
                    }
                }
                let others = expected.filter { !isHis($0) }
                check("everyone it should reach, and no one else",
                      Set(out.filter { !isHis($0) }) == others)
                check("a letter to him alone answered to him",
                      !(others.isEmpty && !expected.isEmpty) || !out.isEmpty)
                if all, !outTo.isEmpty, !outCc.isEmpty {
                    check("Reply All keeps the author and the letter's To in To",
                          author.union(to).filter { !isHis($0) }.isSubset(of: Set(outTo)))
                }

                // Out of the composer's field as they went in, and once
                // more as they were.
                check("the field gives them back",
                      MailFormat.addresses(in: r.to.joined(separator: ", ")) == r.to
                        && MailFormat.addresses(in: r.cc.joined(separator: ", ")) == r.cc)
                check("kept as kept", (r.to + r.cc).map(MailFormat.fieldEntry) == r.to + r.cc)
            }
        }
        XCTAssertEqual(letters, 6_000)
        XCTAssertEqual(broken, [:])
    }
}

// MARK: - Over the scripted server

/// A letter's Reply-To as the shipping repository reads it, and a reply as
/// it goes, and as it comes back from Drafts.
final class ReplyAddressingRepositoryTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    private static let suite = "ReplyAddressingRepositoryTests"

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
            recipients: RecipientBook(defaults: UserDefaults(suiteName: Self.suite)!),
            shelf: keptShelf(for: server.account))
    }

    private var mine: OwnAddresses { OwnAddresses(account: server.account) }

    /// Every connection to the submission server so far.
    private func made() -> [ScriptedSubmission] {
        lock.lock()
        defer { lock.unlock() }
        return submissions
    }

    private func load(_ repository: IMAPMailRepository, _ letter: Server.Letter,
                      in folder: String = Server.inbox) async throws -> Message {
        let uid = try XCTUnwrap(server.deliver(letter, to: [folder])[folder])
        return try await repository.loadMessage(id: "\(server.uidValidity(of: folder))/\(uid)",
                                                mailboxID: folder)
    }

    private func garden(replyTo: [Server.Address] = []) -> Server.Letter {
        Server.Letter(from: Server.Address(name: "Jane Example", address: "jane@example.com"),
                      to: [Server.owner,
                           Server.Address(name: "=?UTF-8?Q?Ex=C3=A4mple=2C_Sam?=",
                                          address: "sam@example.org")],
                      cc: [Server.Address(name: "\"Example, Pat\"", address: "pat@example.com"),
                           Server.Address(name: nil, address: "OWNER@example.com")],
                      subject: "The garden", date: Server.newestDate, text: "Roses.\r\n",
                      messageID: "<garden-reply-to-\(replyTo.count)@example.com>",
                      replyTo: replyTo)
    }

    /// The Reply-To is read from the letter's header. With none, it is
    /// empty, though the ENVELOPE the list is fetched with carries the From
    /// in its place.
    func testALettersReplyToIsReadFromItsHeader() async throws {
        let repository = makeRepository()
        let with = try await load(repository, garden(replyTo: [
            Server.Address(name: "Garden Club", address: "club@example.org"), Server.sam]))
        XCTAssertEqual(with.replyTo, ["Garden Club <club@example.org>", "Sam Example <sam@example.com>"])
        let without = try await load(repository, garden())
        XCTAssertEqual(without.replyTo, [])
        XCTAssertEqual(Draft.replying(to: with, all: false, mine: mine).to,
                       ["Garden Club <club@example.org>", "Sam Example <sam@example.com>"])
        XCTAssertEqual(Draft.replying(to: without, all: false, mine: mine).to,
                       ["Jane Example <jane@example.com>"])
    }

    /// Reply All sent: the RCPT TOs are the Reply-To, the letter's other
    /// recipients and nobody else, not him in any spelling, and the
    /// letter's To and Cc carry their names.
    func testASentReplyAllGoesWhereItShouldWithItsNames() async throws {
        let repository = makeRepository()
        let m = try await load(repository, garden(replyTo: [
            Server.Address(name: "Garden Club", address: "club@example.org")]))
        var draft = Draft.replying(to: m, all: true, mine: mine)
        draft.body = "Yes, Thursday."
        try await repository.send(draft)

        let sent = made()
        XCTAssertEqual(sent.count, 1)
        let submission = try XCTUnwrap(sent.first)
        let rcpt = await submission.commands.filter { $0.hasPrefix("RCPT TO:") }
        XCTAssertEqual(rcpt, ["RCPT TO:<club@example.org>", "RCPT TO:<sam@example.org>",
                              "RCPT TO:<pat@example.com>"])
        let letters = await submission.letters
        let letter = try XCTUnwrap(letters.first)
        XCTAssertEqual(ReplyAddressingTests.recipients("To", in: letter),
                       [MailFormat.Recipient(name: "Garden Club", address: "club@example.org"),
                        MailFormat.Recipient(name: "Ex\u{00E4}mple, Sam", address: "sam@example.org")])
        XCTAssertEqual(ReplyAddressingTests.recipients("Cc", in: letter),
                       [MailFormat.Recipient(name: "Example, Pat", address: "pat@example.com")])
    }

    /// His own letter in Sent Mail is answered to whom it went.
    func testHisOwnLetterInSentMailIsAnsweredToWhomItWent() async throws {
        let repository = makeRepository()
        let m = try await load(repository, Server.Letter(
            from: Server.owner, to: [Server.Address(name: "Jane Example", address: "jane@example.com")],
            cc: [Server.sam], subject: "Thursday", date: Server.newestDate, text: "Shall we?\r\n",
            messageID: "<his-own@example.com>"), in: Server.sent)
        XCTAssertEqual(Draft.replying(to: m, all: false, mine: mine).to,
                       ["Jane Example <jane@example.com>"])
        let all = Draft.replying(to: m, all: true, mine: mine)
        XCTAssertEqual(all.to, ["Jane Example <jane@example.com>"])
        XCTAssertEqual(all.cc, ["Sam Example <sam@example.com>"])
    }

    /// A reply put down as a draft comes back from Drafts with each
    /// recipient once, a name whose comma came out of an encoded word
    /// included, and sends to the same people.
    func testAReplysDraftComesBackWithEachRecipientOnce() async throws {
        let repository = makeRepository()
        let m = try await load(repository, garden())
        var draft = Draft.replying(to: m, all: true, mine: mine)
        XCTAssertEqual(draft.to, ["Jane Example <jane@example.com>",
                                  "\"Ex\u{00E4}mple, Sam\" <sam@example.org>"])
        XCTAssertEqual(draft.cc, ["\"Example, Pat\" <pat@example.com>"])
        draft.body = "Half a thought."
        let id = try await XCTUnwrapAsync(try await repository.saveDraft(draft))
        let back = try await repository.loadDraft(id: id, gmailMessageID: nil, mailboxID: Server.drafts)
        XCTAssertEqual(back.to, draft.to)
        XCTAssertEqual(back.cc, draft.cc)
        // As the composer's field gives them back at Send.
        XCTAssertEqual(MailFormat.addresses(in: back.to.joined(separator: ", ")), draft.to)
        XCTAssertEqual(Submission.recipients(of: back).map(MailFormat.bareAddress),
                       ["jane@example.com", "sam@example.org", "pat@example.com"])
    }

    /// What one send put on the wire: its RCPT TOs' addresses, and the
    /// addresses its header's To and Cc name.
    private func wire(of submission: ScriptedSubmission) async throws
        -> (rcpt: [String], to: [String], cc: [String]) {
        let rcpt = await submission.commands.filter { $0.hasPrefix("RCPT TO:") }
            .map { String($0.dropFirst("RCPT TO:".count)) }
        let letters = await submission.letters
        let letter = try XCTUnwrap(letters.first)
        return (rcpt,
                ReplyAddressingTests.recipients("To", in: letter).map(\.address),
                ReplyAddressingTests.recipients("Cc", in: letter).map(\.address))
    }

    /// Whether `entry` has a line break or a control character in it.
    private func breaksLine(_ entry: String) -> Bool {
        entry.unicodeScalars.contains {
            $0.value < 0x20 || (0x7F...0x9F).contains($0.value) || $0.value == 0x2028 || $0.value == 0x2029
        }
    }

    /// Names broken over lines in a letter's From, To and Cc, as encoded
    /// words carry them: a line feed, U+2028 LINE SEPARATOR, and U+0085
    /// NEXT LINE, which is what a Windows "…" sent as ISO-8859-1 decodes
    /// to. Replied to and sent, every RCPT TO is the angle address of its
    /// entry, the header names the same people, and no entry of the reply
    /// holds a line break. Kept on two lines, the envelope read the first
    /// of them: `RCPT TO:<Jane>` for the From, and
    /// `RCPT TO:<other@example.net>`, a stranger written into Sam's name,
    /// for the To.
    func testNamesBrokenOverLinesAreSentToTheirAddresses() async throws {
        let repository = makeRepository()
        for (charset, gap) in [("UTF-8", "=0A"), ("UTF-8", "=E2=80=A8"), ("ISO-8859-1", "=85")] {
            func name(_ q: String) -> String { "=?\(charset)?Q?\(q)?=" }
            let m = try await load(repository, Server.Letter(
                from: Server.Address(name: name("Jane\(gap)Example"), address: "jane@example.com"),
                to: [Server.owner,
                     Server.Address(name: name("=3Cother=40example=2Enet=3E\(gap)Sam"),
                                    address: "sam@example.org")],
                cc: [Server.Address(name: name("Pat\(gap)Example"), address: "pat@example.com")],
                subject: "Broken names", date: Server.newestDate, text: "Hello.\r\n",
                messageID: "<broken-\(charset)-\(gap)@example.com>"))
            let what = "\(charset) \(gap)"
            // The names reach the letter broken, as the header gave them.
            XCTAssertTrue(breaksLine(m.sender), what)
            XCTAssertTrue(m.to.contains(where: breaksLine), what)
            XCTAssertTrue(m.cc.contains(where: breaksLine), what)

            for all in [false, true] {
                var draft = Draft.replying(to: m, all: all, mine: mine)
                XCTAssertFalse((draft.to + draft.cc).contains(where: breaksLine), "\(what): \(draft.to) \(draft.cc)")
                XCTAssertEqual(draft.to, all ? ["Jane Example <jane@example.com>",
                                                "\"<other@example.net> Sam\" <sam@example.org>"]
                                             : ["Jane Example <jane@example.com>"], what)
                XCTAssertEqual(draft.cc, all ? ["Pat Example <pat@example.com>"] : [], what)
                // As the composer's field gives them back at Send.
                draft.to = MailFormat.addresses(in: draft.to.joined(separator: ", "))
                draft.cc = MailFormat.addresses(in: draft.cc.joined(separator: ", "))
                draft.body = "Yes."
                let before = made().count
                try await repository.send(draft)
                let sent = made()
                XCTAssertEqual(sent.count, before + 1, what)
                let on = try await wire(of: try XCTUnwrap(sent.last))
                XCTAssertEqual(on.rcpt, all ? ["<jane@example.com>", "<sam@example.org>", "<pat@example.com>"]
                                            : ["<jane@example.com>"], what)
                XCTAssertEqual(on.to, all ? ["jane@example.com", "sam@example.org"] : ["jane@example.com"], what)
                XCTAssertEqual(on.cc, all ? ["pat@example.com"] : [], what)
            }
        }
    }

    /// A draft another client saved with a name broken over lines comes
    /// back from Drafts with every entry on one line, an entry with no
    /// address in it as well, kept for him to see, and sends to the
    /// addresses its field shows.
    func testADraftWithNamesBrokenOverLinesComesBackOnOneLine() async throws {
        let repository = makeRepository()
        let uid = try XCTUnwrap(server.deliver(Server.Letter(
            from: Server.owner,
            to: [Server.Address(name: "=?UTF-8?Q?=3Cother=40example=2Enet=3E=E2=80=A8Sam?=",
                                address: "sam@example.org"),
                 Server.Address(name: "=?ISO-8859-1?Q?Jane=85Example?=", address: "jane@example.com"),
                 Server.Address(name: nil, address: "=?UTF-8?Q?Carlo=E2=80=A8Example?=")],
            cc: [Server.Address(name: "=?UTF-8?Q?Pat=0AExample?=", address: "pat@example.com")],
            subject: "Half a thought", date: Server.newestDate, text: "Not yet.\r\n",
            messageID: "<broken-draft@example.com>"), to: [Server.drafts])[Server.drafts])
        var back = try await repository.loadDraft(id: "\(server.uidValidity(of: Server.drafts))/\(uid)",
                                                  gmailMessageID: nil, mailboxID: Server.drafts)
        XCTAssertEqual(back.to, ["\"<other@example.net> Sam\" <sam@example.org>",
                                 "Jane Example <jane@example.com>", "Carlo Example"])
        XCTAssertEqual(back.cc, ["Pat Example <pat@example.com>"])
        // He takes out the name with no address, as the field leaves him to.
        back.to.removeLast()
        back.body = "Now."
        try await repository.send(back)
        let on = try await wire(of: try XCTUnwrap(made().last))
        XCTAssertEqual(on.rcpt, ["<sam@example.org>", "<jane@example.com>", "<pat@example.com>"])
        XCTAssertEqual(on.to, ["sam@example.org", "jane@example.com"])
        XCTAssertEqual(on.cc, ["pat@example.com"])
    }

    /// Whatever else puts a line break in a field, a `mailto:` link's
    /// `%0A` among them, the letter's header names whom its envelope sends
    /// to: both read the entry's first line (`RFC5322Builder.recipientLine`).
    /// The header used to read all of it, and named other@example.net
    /// where the letter went to Sam.
    func testTheHeaderNamesWhomTheEnvelopeSendsTo() async throws {
        let repository = makeRepository()
        let link = "mailto:sam@example.org%0A%3Cother@example.net%3E"
            + "?cc=Pat%20Example%20%3Cpat@example.com%3E%E2%80%A8%3Cother@example.net%3E"
        var draft = try XCTUnwrap(MailtoLink.draft(from: try XCTUnwrap(URL(string: link)), signature: ""))
        draft.to.append("carlo@example.org\u{0085}Carlo <other@example.net>")
        XCTAssertTrue((draft.to + draft.cc).allSatisfy(breaksLine), "\(draft.to) \(draft.cc)")
        draft.body = "Hello."
        try await repository.send(draft)
        let on = try await wire(of: try XCTUnwrap(made().last))
        XCTAssertEqual(on.rcpt, ["<sam@example.org>", "<carlo@example.org>", "<pat@example.com>"])
        XCTAssertEqual(on.to, ["sam@example.org", "carlo@example.org"])
        XCTAssertEqual(on.cc, ["pat@example.com"])
    }

    /// A letter written by several, its From split as its To is, before
    /// the encoded words are decoded, so a name whose comma came out of
    /// one is still one author: a Reply goes to them all. And one he wrote
    /// with someone else, in Sent Mail, is his own.
    func testALetterFromSeveralIsReadAsSeveral() async throws {
        let repository = makeRepository()
        var garden = Server.Letter(
            from: Server.Address(name: "=?UTF-8?Q?Example=2C_Jane?=", address: "jane@example.com"),
            to: [Server.owner, Server.Address(name: nil, address: "carlo@example.org")],
            subject: "Thursday", date: Server.newestDate, text: "Both of us.\r\n",
            messageID: "<two-authors@example.com>")
        garden.alsoFrom = [Server.sam]
        let m = try await load(repository, garden)
        XCTAssertEqual(m.from, ["Example, Jane <jane@example.com>", "Sam Example <sam@example.com>"])
        var draft = Draft.replying(to: m, all: false, mine: mine)
        XCTAssertEqual(draft.to, ["\"Example, Jane\" <jane@example.com>", "Sam Example <sam@example.com>"])
        draft.body = "Thursday it is."
        try await repository.send(draft)
        let on = try await wire(of: try XCTUnwrap(made().last))
        XCTAssertEqual(on.rcpt, ["<jane@example.com>", "<sam@example.com>"])
        XCTAssertEqual(on.to, ["jane@example.com", "sam@example.com"])

        var his = Server.Letter(
            from: Server.Address(name: "Jane Example", address: "jane@example.com"),
            to: [Server.Address(name: nil, address: "carlo@example.org")],
            subject: "From us both", date: Server.newestDate, text: "Love.\r\n",
            messageID: "<his-and-janes@example.com>")
        his.alsoFrom = [Server.owner]
        let sent = try await load(repository, his, in: Server.sent)
        XCTAssertEqual(Draft.replying(to: sent, all: true, mine: mine).to, ["carlo@example.org"])
    }

    private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath,
                                   line: UInt = #line) async throws -> T {
        try XCTUnwrap(value, file: file, line: line)
    }
}

// MARK: - The wiring

/// `MessageDetailViewController` is UIKit and never builds on this host, so
/// its wiring is read from its source, as `ReadingPaneCcTests` reads the
/// header's.
final class ReplyAddressingWiringTests: XCTestCase {

    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/UI/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    /// Reply answers the letter the pane shows, which in a conversation is
    /// the one opened last, and knows every address of his the account
    /// has; the composer reads its fields back a recipient at a time.
    func testReplyIsWiredToTheLetterShownAndHisAddresses() throws {
        let pane = try source("MessageDetailViewController.swift")
        for wiring in [
            "@objc private func replyTapped() { guard let m = message else { return }",
            "self?.openCompose(replyTo: m, all: false, forward: false)",
            "self?.openCompose(replyTo: m, all: true, forward: false)",
            "self?.openCompose(replyTo: m, all: false, forward: true)",
            ": .replying(to: m, all: all, mine: OwnAddresses(account: account), signature: signature)",
            "private func focusLetter(_ m: Message) { focused = m.id message = m",
        ] {
            XCTAssertTrue(pane.contains(wiring), wiring)
        }
        XCTAssertFalse(pane.contains("myAddress:"))

        let composer = try source("ComposeViewController.swift")
        for field in ["draft.to = MailFormat.addresses(in: toField.text ?? \"\")",
                      "draft.cc = MailFormat.addresses(in: ccField.text ?? \"\")",
                      "draft.bcc = MailFormat.addresses(in: bccField.text ?? \"\")"] {
            XCTAssertTrue(composer.contains(field), field)
        }
    }
}
