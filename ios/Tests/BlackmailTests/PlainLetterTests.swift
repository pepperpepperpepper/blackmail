import XCTest
@testable import Blackmail

/// A letter with no HTML twin and no files is one part, plain text, and its
/// body is his words and nothing else (B-068).
///
/// The builder wrote the plain part's own two header lines, Content-Type and
/// Content-Transfer-Encoding, under a message header that already said both.
/// They arrived as the first two lines of the letter, in the list, in the
/// pane and in every reader's client, and a draft reopened took them up as
/// words and wrapped them once more at each save. The test iPad never showed
/// it: its signature has a picture, so every letter there has an HTML twin.
///
/// Read back here with the app's own reader, `MIMEDecoder`, as the pane and
/// the list read a letter: built alone, sent and saved through the shipping
/// repository over the scripted servers, and sent from the share sheet. The
/// shapes with more than one part are pinned byte for byte as they were
/// before the fix.
final class PlainLetterTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    /// The recipient book's own store, so a run neither reads nor writes
    /// this machine's standard defaults.
    private static let suite = "PlainLetterTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var submissions: PlainSubmissions!

    /// What he typed above his sign-off.
    private let typed = "Dear Carlo,\n\nSee you on Sunday at one."
    /// A signature of words alone, as account setup leaves one with no
    /// picture in it.
    private let plainSignature = "Sam Example\n555-555-0142"

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer(username: "sam@example.com")
        submissions = PlainSubmissions()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        removeTranscripts()
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        removeTranscripts()
        server = nil
        submissions = nil
        book = nil
        super.tearDown()
    }

    /// Where `CaptureProbe` puts a send's transcript. A send leaves one in
    /// the temporary directory, as it does on the device.
    private nonisolated func transcript(_ outcome: String) -> String {
        (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
    }

    private nonisolated func removeTranscripts() {
        for outcome in ["ok", "fail"] {
            try? FileManager.default.removeItem(atPath: transcript(outcome))
        }
    }

    // MARK: - Helpers

    /// His account with no signature, as a fresh install has it, or with
    /// one of words alone. Neither gives a letter an HTML twin.
    private func account(signature: String = "") -> MailAccount {
        MailAccount(address: server.username, imapPort: server.port,
                    username: server.username, displayName: "Sam Example",
                    signature: signature)
    }

    private func makeRepository(_ account: MailAccount) -> IMAPMailRepository {
        let imap = server.transportFactory
        let submissions = self.submissions!
        return IMAPMailRepository(
            account: account, password: server.password,
            transport: { host, port in port == 465 ? submissions.next() : imap(host, port) },
            recipients: book,
            signatureImages: { [] },
            shelf: keptShelf(for: account))
    }

    /// A new letter as the composer makes one: his words above the
    /// signature it put there.
    private func newLetter(_ account: MailAccount) -> Draft {
        var draft = Draft.blank(signature: account.signature)
        draft.to = ["carlo@example.org"]
        draft.subject = "Sunday"
        draft.body = typed + draft.body
        return draft
    }

    /// The text the reading pane shows of `raw`.
    private func paneText(_ raw: Data) -> String? {
        MIMEDecoder.decodeMessage(raw).text
    }

    /// The preview a list row shows of `raw`, by the steps the list takes:
    /// the part it previews, transfer-decoded, then made one line.
    private func listPreview(_ raw: Data) -> String? {
        let parsed = MIMEDecoder.parse(raw)
        guard let part = MIMEDecoder.previewPart(parsed.structure),
              let bytes = parsed.bodies[part.section] else { return nil }
        let text = MIMEDecoder.decodeText(bytes, encoding: part.encoding,
                                          charset: MIMEDecoder.parameter("charset",
                                                                         in: part.parameters))
        return part.subtype == "html" ? PreviewText.fromHTML(text) : PreviewText.fromPlainText(text)
    }

    /// How many times a header line named `name` begins a line of `raw`,
    /// header and body together.
    private func lines(named name: String, in raw: Data) -> Int {
        String(decoding: raw, as: UTF8.self).components(separatedBy: "\r\n")
            .filter { $0.lowercased().hasPrefix(name.lowercased() + ":") }.count
    }

    /// Asserts `raw` is one part, plain text in quoted-printable, its
    /// Content-Type and transfer encoding said once, in the message header.
    private func assertOnePlainPart(_ raw: Data, _ label: String = "",
                                    file: StaticString = #filePath, line: UInt = #line) {
        let structure = MIMEDecoder.parse(raw).structure
        XCTAssertEqual(structure.type, "text", label, file: file, line: line)
        XCTAssertEqual(structure.subtype, "plain", label, file: file, line: line)
        XCTAssertEqual(structure.encoding, "quoted-printable", label, file: file, line: line)
        XCTAssertTrue(structure.children.isEmpty, label, file: file, line: line)
        XCTAssertEqual(lines(named: "Content-Type", in: raw), 1, label, file: file, line: line)
        XCTAssertEqual(lines(named: "Content-Transfer-Encoding", in: raw), 1, label,
                       file: file, line: line)
    }

    // MARK: - Built and read back

    /// Built and read back by the pane's reader, a plain letter is what he
    /// typed, to the character: line breaks, blank lines, a space at a
    /// line's end, `=`, a long line, letters outside ASCII, a line of one
    /// full stop, and nothing at all.
    func testAPlainLetterReadsBackAsExactlyWhatHeTyped() {
        let bodies = [
            typed,
            "One line",
            "",
            "Ends in a new line\n",
            "\n\nBegins with two\n",
            "A space at the end \nof a line, and a tab\t\nand = signs == 3",
            "Café at 10 € — " + String(repeating: "a long line of words ", count: 12),
            "one\n.\ntwo",
            // His own words that look like a header are words.
            "Content-Type: text/plain; charset=utf-8\nis what the letter said",
        ]
        for body in bodies {
            var draft = Draft()
            draft.to = ["carlo@example.org"]
            draft.subject = "Sunday"
            draft.body = body
            let raw = RFC5322Builder.build(draft: draft, from: account())
            XCTAssertEqual(paneText(raw), body, body)
        }
    }

    func testAPlainLetterIsOnePartAndItsWordsComeFirst() {
        var draft = Draft()
        draft.to = ["carlo@example.org"]
        draft.body = typed
        let raw = RFC5322Builder.build(draft: draft, from: account())
        assertOnePlainPart(raw)
        XCTAssertEqual(listPreview(raw), "Dear Carlo, See you on Sunday at one.")
        let text = String(decoding: raw, as: UTF8.self)
        let body = text.components(separatedBy: "\r\n\r\n").dropFirst().joined(separator: "\r\n\r\n")
        XCTAssertTrue(body.hasPrefix("Dear Carlo,\r\n"), body)
    }

    /// A signature of words alone gives no HTML twin, sent or saved, so the
    /// letter goes as one part, and comes back as he wrote it, sign-off and
    /// all.
    func testAPlainSignatureLeavesALetterOfOnePartThatReadsBackExactly() {
        let account = account(signature: plainSignature)
        let draft = newLetter(account)
        XCTAssertNil(AppleMailHTML.letter(for: draft, account: account).html)
        XCTAssertNil(AppleMailHTML.letter(for: draft, account: account, forDraft: true).html)

        let raw = RFC5322Builder.build(draft: draft, from: account,
                                       htmlBody: AppleMailHTML.part(for: draft, account: account))
        assertOnePlainPart(raw)
        XCTAssertEqual(paneText(raw), "Dear Carlo,\n\nSee you on Sunday at one.\n\n\n"
                       + "Sam Example\n555-555-0142")
        XCTAssertEqual(listPreview(raw),
                       "Dear Carlo, See you on Sunday at one. Sam Example 555-555-0142")
    }

    /// A signature with a picture, taken out of the letter: no HTML twin,
    /// one part. The way the test iPad, whose signature has a logo, takes
    /// this path.
    func testASignatureWithAPictureTakenOutLeavesTheLetterPlain() {
        let account = MailAccount(address: "sam@example.com", username: "sam@example.com",
                                  displayName: "Sam Example", signature: plainSignature,
                                  signatureHTML: "<div><img src=\"cid:sig-logo\"> Sam</div>")
        var draft = newLetter(account)
        XCTAssertNotNil(AppleMailHTML.part(for: draft, account: account))

        draft.body = typed
        XCTAssertNil(AppleMailHTML.part(for: draft, account: account))
        let raw = RFC5322Builder.build(draft: draft, from: account,
                                       htmlBody: AppleMailHTML.part(for: draft, account: account))
        assertOnePlainPart(raw)
        XCTAssertEqual(paneText(raw), typed)
    }

    // MARK: - Sent

    /// Sent through the repository, a plain letter is one part whose words
    /// come first. SMTP ends the last line, so the copy that arrives has one
    /// line break after his last word when it had none.
    func testAPlainLetterSentIsHisWords() async throws {
        for signature in ["", plainSignature] {
            let account = account(signature: signature)
            let draft = newLetter(account)
            let before = await submissions.letters().count
            try await makeRepository(account).send(draft)

            let letters = await submissions.letters()
            XCTAssertEqual(letters.count, before + 1)
            let raw = try XCTUnwrap(letters.last)
            assertOnePlainPart(raw, "signature \(signature.debugDescription)")
            let ended = draft.body.hasSuffix("\n") ? draft.body : draft.body + "\n"
            XCTAssertEqual(paneText(raw), ended)
            XCTAssertEqual(listPreview(raw)?.hasPrefix("Dear Carlo, See you on Sunday at one."),
                           true, listPreview(raw) ?? "nil")
        }
    }

    /// From the share sheet, words shared from Notes with a signature of
    /// words alone: the same one part, through the same builder.
    @MainActor
    func testWordsSharedGoAsOnePartWithTheWordsFirst() async throws {
        let smtp = ScriptedSubmission()
        let account = MailAccount(address: "owner@example.com", username: "owner@example.com",
                                  displayName: "Sam", signature: plainSignature)
        let shared = ShareMirror.Shared(account: account, password: "app-password",
                                        signatureImages: [], recipients: [])
        var log: [String] = []
        let sheet = ShareSheet(
            shared: shared,
            transport: { _, _ in smtp },
            readFile: { _ in throw MailError.attachmentFailed },
            noteSent: { _ in },
            finish: { log.append("finish") },
            cancel: { log.append("cancel") },
            showError: { _ in log.append("error") },
            draw: { _ in },
            background: BackgroundTime(begin: { _, _ in nil }, end: { _ in }))
        var draft = sheet.letter(from: [.text("Milk, eggs, bread.")])
        draft.to = ["owner@example.net"]
        XCTAssertNil(ShareLetter.html(for: draft, account: account))

        await sheet.send { draft }?.value

        let letters = await smtp.letters
        XCTAssertEqual(letters.count, 1)
        let raw = try XCTUnwrap(letters.first)
        assertOnePlainPart(raw)
        let text = try XCTUnwrap(paneText(raw))
        XCTAssertTrue(text.hasPrefix("Milk, eggs, bread."), text)
        XCTAssertEqual(text, draft.body + "\n")
        XCTAssertEqual(log, ["finish"])

        // The connection let go of and its transcript written, so the test
        // leaves neither behind.
        for _ in 0..<1_000 {
            if await smtp.isClosed, FileManager.default.fileExists(atPath: transcript("ok")) {
                break
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    // MARK: - Saved and reopened

    /// Saved to Drafts, reopened, saved again unchanged and reopened again,
    /// three times over: each time the copy is one part, its words first,
    /// and the draft comes back as he left it. With no signature, as on a
    /// fresh install, and with one of words alone.
    func testADraftSavedAndReopenedKeepsItsBody() async throws {
        for signature in ["", plainSignature] {
            let account = account(signature: signature)
            let repository = makeRepository(account)
            var draft = newLetter(account)
            draft.subject = "Sunday \(signature.isEmpty ? "unsigned" : "signed")"
            let body = draft.body

            for round in 1...3 {
                let label = "\(draft.subject), round \(round)"
                let saved = try await repository.saveDraft(draft)
                let id = try XCTUnwrap(saved, label)
                let uid = try XCTUnwrap(UInt32(id.split(separator: "/").last ?? ""), label)
                let stored = try XCTUnwrap(server.letter(uid: uid, in: Server.drafts)?.text, label)
                XCTAssertTrue(stored.hasPrefix("Dear Carlo,\r\n"), "\(label): \(stored)")
                XCTAssertFalse(stored.contains("Content-"), "\(label): \(stored)")

                draft = try await repository.loadDraft(id: id, mailboxID: Server.drafts)
                XCTAssertEqual(draft.body, body, label)
            }

            // One copy in Drafts, the last.
            let copies = server.uids(in: Server.drafts).filter {
                server.letter(uid: $0, in: Server.drafts)?.subject == draft.subject
            }
            XCTAssertEqual(copies.count, 1, draft.subject)
        }
    }

    /// A draft he changes between saves keeps each change and nothing more.
    func testADraftChangedBetweenSavesKeepsEachChangeAndNothingElse() async throws {
        let account = account()
        let repository = makeRepository(account)
        var draft = newLetter(account)
        for round in 1...3 {
            draft.body = "Round \(round). " + draft.body
            let expected = draft.body
            let saved = try await repository.saveDraft(draft)
            let id = try XCTUnwrap(saved, "round \(round)")
            draft = try await repository.loadDraft(id: id, mailboxID: Server.drafts)
            XCTAssertEqual(draft.body, expected, "round \(round)")
        }
        XCTAssertTrue(draft.body.hasPrefix("Round 3. Round 2. Round 1. Dear Carlo,"), draft.body)
    }

    // MARK: - Every shape, byte for byte

    /// Randomness that can be replayed: 32 hex digits counting up.
    private final class Tokens {
        private(set) var drawn = 0

        func next() -> String {
            drawn += 1
            let hex = String(0x68_0000 + drawn, radix: 16, uppercase: true)
            return String(repeating: "0", count: 32 - hex.count) + hex
        }
    }

    private let when = Date(timeIntervalSince1970: 1_791_200_000)
    private let markup = "<div dir=\"ltr\">Dear Carlo,<br><br>See you on Sunday at one.</div>"
        + "<img src=\"cid:sig-logo\">"
    private let notes = [(filename: "Notes.txt", mimeType: "text/plain", data: Data("notes".utf8))]
    private let logo = [(contentID: "sig-logo", filename: "logo.png", mimeType: "image/png",
                         data: Data([1, 2, 3]))]

    /// The letter built with a fixed date, id and randomness. The Date line
    /// is in this machine's time zone, so it reads `DATE`.
    private func shape(html: String?,
                       files: [(filename: String, mimeType: String, data: Data)] = [],
                       inline: [(contentID: String, filename: String,
                                 mimeType: String, data: Data)] = []) -> String {
        var draft = Draft()
        draft.to = ["Carlo <carlo@example.org>"]
        draft.subject = "Sunday"
        draft.body = "Dear Carlo,\n\nSee you on Sunday at one.\n\nOwner"
        let tokens = Tokens()
        let raw = RFC5322Builder.build(draft: draft, from: MailAccount(
                                           address: "owner@example.com",
                                           username: "owner@example.com",
                                           displayName: "Owner Example"),
                                       date: when, messageID: "<b068@example.com>",
                                       attachments: files, htmlBody: html, inlineImages: inline,
                                       boundaryToken: tokens.next)
        return String(decoding: raw, as: UTF8.self)
            .replacingOccurrences(of: RFC5322Builder.rfc5322Date(when), with: "DATE")
    }

    /// `text` with every line break CRLF, as the builder writes them all.
    private func wire(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "\r\n")
    }

    private let header = """
        From: Owner Example <owner@example.com>
        To: Carlo <carlo@example.org>
        Subject: Sunday
        Date: DATE
        Message-ID: <b068@example.com>
        MIME-Version: 1.0
        """

    private let words = """
        Dear Carlo,

        See you on Sunday at one.

        Owner
        """

    private var plainPart: String {
        """
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        \(words)
        """
    }

    private let htmlPart = """
        Content-Type: text/html; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        <div dir=3D"ltr">Dear Carlo,<br><br>See you on Sunday at one.</div><img s=
        rc=3D"cid:sig-logo">
        """

    private let notesPart = """
        Content-Type: text/plain; name="Notes.txt"
        Content-Transfer-Encoding: base64
        Content-Disposition: attachment; filename="Notes.txt"

        bm90ZXM=
        """

    private let logoPart = """
        Content-Type: image/png; name="logo.png"
        Content-Transfer-Encoding: base64
        Content-ID: <sig-logo>
        Content-Disposition: inline; filename="logo.png"

        AQID
        """

    private func boundary(_ n: Int) -> String {
        "=_Blackmail_0000000000000000000000000068000\(n)_="
    }

    /// The plain text and the markup as alternatives, under boundary `n`.
    private func alternatives(_ n: Int) -> String {
        """
        --\(boundary(n))
        \(plainPart)
        --\(boundary(n))
        \(htmlPart)
        --\(boundary(n))--
        """
    }

    /// One part, plain text: the header, then his words. Nothing after his
    /// last word, so a draft comes back as he left it.
    func testThePlainShapeIsHisWordsUnderTheHeader() {
        XCTAssertEqual(shape(html: nil), wire("""
            \(header)
            Content-Type: text/plain; charset=utf-8
            Content-Transfer-Encoding: quoted-printable

            \(words)
            """))
    }

    /// Plain text and a file: the part keeps its own header, as it must
    /// inside multipart/mixed. As before the fix, byte for byte.
    func testTheMixedShapeIsAsItWas() {
        XCTAssertEqual(shape(html: nil, files: notes), wire("""
            \(header)
            Content-Type: multipart/mixed;
             boundary="\(boundary(1))"

            --\(boundary(1))
            \(plainPart)
            --\(boundary(1))
            \(notesPart)
            --\(boundary(1))--

            """))
    }

    func testTheAlternativeShapeIsAsItWas() {
        XCTAssertEqual(shape(html: markup), wire("""
            \(header)
            Content-Type: multipart/alternative;
             boundary="\(boundary(1))"

            \(alternatives(1))

            """))
    }

    func testTheRelatedShapeIsAsItWas() {
        XCTAssertEqual(shape(html: markup, inline: logo), wire("""
            \(header)
            Content-Type: multipart/related;
             boundary="\(boundary(2))";
             type="multipart/alternative"

            --\(boundary(2))
            Content-Type: multipart/alternative;
             boundary="\(boundary(1))"

            \(alternatives(1))
            --\(boundary(2))
            \(logoPart)
            --\(boundary(2))--

            """))
    }

    func testTheAlternativesWithAFileAreAsTheyWere() {
        XCTAssertEqual(shape(html: markup, files: notes), wire("""
            \(header)
            Content-Type: multipart/mixed;
             boundary="\(boundary(2))"

            --\(boundary(2))
            Content-Type: multipart/alternative;
             boundary="\(boundary(1))"

            \(alternatives(1))
            --\(boundary(2))
            \(notesPart)
            --\(boundary(2))--

            """))
    }

    func testEverythingTogetherIsAsItWas() {
        XCTAssertEqual(shape(html: markup, files: notes, inline: logo), wire("""
            \(header)
            Content-Type: multipart/mixed;
             boundary="\(boundary(3))"

            --\(boundary(3))
            Content-Type: multipart/related;
             boundary="\(boundary(2))";
             type="multipart/alternative"

            --\(boundary(2))
            Content-Type: multipart/alternative;
             boundary="\(boundary(1))"

            \(alternatives(1))
            --\(boundary(2))
            \(logoPart)
            --\(boundary(2))--
            --\(boundary(3))
            \(notesPart)
            --\(boundary(3))--

            """))
    }
}

/// A scripted submission server per connection, keeping each letter that
/// went, its leading dots unstuffed.
private final class PlainSubmissions: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [ScriptedSubmission] = []

    func next() -> ScriptedSubmission {
        let server = ScriptedSubmission()
        lock.lock()
        made.append(server)
        lock.unlock()
        return server
    }

    private func servers() -> [ScriptedSubmission] {
        lock.lock()
        defer { lock.unlock() }
        return made
    }

    func letters() async -> [Data] {
        var all: [Data] = []
        for server in servers() {
            for stuffed in await server.letters {
                var letter = String(decoding: stuffed, as: UTF8.self)
                    .replacingOccurrences(of: "\r\n..", with: "\r\n.")
                if letter.hasPrefix("..") { letter.removeFirst() }
                all.append(Data(letter.utf8))
            }
        }
        return all
    }
}
