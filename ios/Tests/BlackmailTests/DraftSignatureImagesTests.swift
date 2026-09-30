import XCTest
@testable import Blackmail

/// A letter with the signature's logo in it, saved as a draft, picked up
/// again, and sent (B-046).
///
/// A saved draft carries the logo as an inline part, so the stored markup's
/// `cid:` resolves, and saving and sending both add it afresh from
/// `SignatureImages`. Reopening used to take that stored copy up as a file
/// he had attached: a "logo.png" row in the composer, a second copy stapled
/// under the letter he sent, and one copy more with every save. These run
/// the shipping repository over the scripted server, with a submission
/// server on port 465 that keeps the letter it is given, so what is checked
/// is the bytes that would have gone.
final class DraftSignatureImagesTests: XCTestCase {

    private typealias Server = ScriptedIMAPServer

    /// The recipient book's own store, so a run neither reads nor writes
    /// this machine's standard defaults.
    private static let suite = "DraftSignatureImagesTests"

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var submission: Submissions!
    /// Where the photograph he attaches is staged. A directory of this
    /// test's own rather than `AttachmentStore`'s: that one is the same
    /// directory for every run of the suite on the machine, and
    /// `AttachmentStoreTests` empties it, so a photo staged there by one run
    /// could be gone before another run's send read it.
    private var staging: URL!

    /// The signature as account setup leaves it: the words, the markup that
    /// names the logo by `cid:`, and the logo's bytes.
    private let signature = "Sam Example\n555-555-0142"
    private let signatureHTML = "<div dir=\"ltr\"><table><tr><td><img src=\"cid:sig-logo\" "
        + "width=\"35\" height=\"25\"></td><td><b>Sam Example</b></td></tr></table></div>"
    private let logoBytes = Data((0..<900).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) })
    /// A photograph he attached from the composer.
    private let photoBytes = Data((0..<1500).map { UInt8(truncatingIfNeeded: $0 &* 13 &+ 1) })

    private var logo: SignatureImages.InlineImage {
        SignatureImages.InlineImage(contentID: "sig-logo", filename: "logo.png",
                                    mimeType: "image/png",
                                    dataBase64: logoBytes.base64EncodedString())
    }

    private var account: MailAccount {
        MailAccount(address: server.username, imapPort: server.port,
                    username: server.username, displayName: "Sam Example",
                    signature: signature, signatureHTML: signatureHTML)
    }

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer(username: "sam@example.com")
        submission = Submissions()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        staging = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("DraftSignatureImagesTests-\(UUID().uuidString)",
                                    isDirectory: true)
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        // The staged photograph, and the transcript `send` leaves in the
        // temporary directory as it does on the device.
        if let staging { try? FileManager.default.removeItem(at: staging) }
        for outcome in ["ok", "fail"] {
            let transcript = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
            try? FileManager.default.removeItem(atPath: transcript)
        }
        server = nil
        submission = nil
        book = nil
        staging = nil
        super.tearDown()
    }

    private func makeRepository() -> IMAPMailRepository {
        let imap = server.transportFactory
        let submission = self.submission!
        let logo = self.logo
        return IMAPMailRepository(
            account: account, password: server.password,
            transport: { host, port in port == 465 ? submission.next() : imap(host, port) },
            recipients: book,
            signatureImages: { [logo] },
            shelf: keptShelf(for: account))
    }

    /// A new letter as the composer makes one: his words above the
    /// signature it put there, and a photograph attached, a file on disk
    /// as the composer's is.
    private func newLetter() throws -> Draft {
        var draft = Draft.blank(signature: signature)
        draft.to = ["carlo@example.org"]
        draft.subject = "Sunday"
        draft.body = "Lunch at one?" + draft.body
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let url = staging.appendingPathComponent("Garden.jpg")
        try photoBytes.write(to: url)
        draft.attachments = [DraftAttachment(source: .localFile(url), filename: "Garden.jpg",
                                             mimeType: "image/jpeg",
                                             size: Int64(photoBytes.count))]
        return draft
    }

    /// One part of a letter, decoded to the bytes it carries.
    private struct Part: Equatable {
        let filename: String
        let contentID: String?
        let isInline: Bool
        let data: Data
    }

    /// Every part but the words, as a reader's client would take them.
    private func parts(of raw: Data) -> [Part] {
        let parsed = MIMEDecoder.parse(raw)
        return MIMEDecoder.decodeMessage(raw).attachments.map { a in
            let encoding = MIMEDecoder.part(at: a.id, in: parsed.structure)?.encoding ?? "7bit"
            return Part(filename: a.filename, contentID: a.contentID, isInline: a.isInline,
                        data: MIMEDecoder.decodeTransfer(parsed.bodies[a.id] ?? Data(),
                                                         encoding: encoding))
        }
    }

    /// The parts of the copy the server holds under `id`, read back through
    /// the repository.
    private func storedParts(_ id: String, _ repository: IMAPMailRepository) async throws -> [Part] {
        let stored = try await repository.loadMessage(id: id, mailboxID: Server.drafts)
        var out: [Part] = []
        for a in stored.attachments {
            let data = try await repository.fetchAttachmentData(a.id, of: id,
                                                                mailboxID: Server.drafts)
            out.append(Part(filename: a.filename, contentID: a.contentID,
                            isInline: a.isInline, data: data))
        }
        return out
    }

    // MARK: - Reopening

    func testAReopenedDraftListsTheFileHeAttachedAndNotTheSignaturesLogo() async throws {
        let repository = makeRepository()
        let saved = try await repository.saveDraft(try newLetter())
        let id = try XCTUnwrap(saved, "APPENDUID should have named the new copy")

        // The stored copy does carry the logo, inline under its cid:, which
        // is what makes the saved markup show it.
        let stored = try await storedParts(id, repository)
        XCTAssertEqual(stored.filter { $0.data == logoBytes }.map(\.contentID), ["sig-logo"])

        let reopened = try await repository.loadDraft(id: id, mailboxID: Server.drafts)
        XCTAssertEqual(reopened.attachments.map(\.filename), ["Garden.jpg"],
                       "the logo is the signature's, not a file he attached")
        XCTAssertEqual(reopened.savedID, id)
    }

    // MARK: - Sending

    func testTheReopenedDraftGoesOutWithTheLogoOnceInlineAndThePhotoOnce() async throws {
        let repository = makeRepository()
        let saved = try await repository.saveDraft(try newLetter())
        let id = try XCTUnwrap(saved, "APPENDUID should have named the new copy")
        let reopened = try await repository.loadDraft(id: id, mailboxID: Server.drafts)

        try await repository.send(reopened)
        let letters = await submission.letters()
        let sent = parts(of: try XCTUnwrap(letters.last))

        XCTAssertEqual(sent.filter { $0.data == logoBytes }.map(\.contentID), ["sig-logo"],
                       "the logo once, in the signature, and no second copy as a file")
        XCTAssertEqual(sent.filter { $0.data == logoBytes }.map(\.isInline), [true])
        XCTAssertEqual(sent.filter { $0.data == photoBytes }.map(\.filename), ["Garden.jpg"])
        XCTAssertEqual(sent.filter { $0.data == photoBytes }.map(\.isInline), [false])
        XCTAssertEqual(sent.count, 2, "\(sent.map(\.filename))")
        // What raises a paperclip in the list and a file row in the header.
        XCTAssertEqual(sent.filter { !$0.isInline }.map(\.filename), ["Garden.jpg"])
    }

    func testTheReopenedDraftSendsTheSameLetterAsTheFreshOneWould() async throws {
        // Measured on the iPad: 18,134 bytes sent fresh, 28,883 from the
        // reopened draft, about one more base64 copy of the logo.
        let repository = makeRepository()
        let letter = try newLetter()
        try await repository.send(letter)
        let saved = try await repository.saveDraft(letter)
        let id = try XCTUnwrap(saved)
        try await repository.send(try await repository.loadDraft(id: id, mailboxID: Server.drafts))

        let letters = await submission.letters()
        XCTAssertEqual(letters.count, 2)
        guard letters.count == 2 else { return }
        XCTAssertEqual(parts(of: letters[1]), parts(of: letters[0]))
        XCTAssertLessThan(abs(letters[1].count - letters[0].count), 64,
                          "\(letters[0].count) fresh, \(letters[1].count) reopened")
    }

    // MARK: - Put down and picked up again

    func testSavingAndReopeningAgainAndAgainAddsNothing() async throws {
        let repository = makeRepository()
        var draft = try newLetter()

        for round in 1...3 {
            let saved = try await repository.saveDraft(draft)
            let id = try XCTUnwrap(saved, "round \(round)")
            let stored = try await storedParts(id, repository)
            XCTAssertEqual(stored.filter { $0.data == logoBytes }.count, 1,
                           "round \(round): \(stored.map(\.filename))")
            XCTAssertEqual(stored.filter { $0.data == photoBytes }.count, 1,
                           "round \(round): \(stored.map(\.filename))")
            XCTAssertEqual(stored.count, 2, "round \(round): \(stored.map(\.filename))")

            draft = try await repository.loadDraft(id: id, mailboxID: Server.drafts)
            XCTAssertEqual(draft.attachments.map(\.filename), ["Garden.jpg"], "round \(round)")
            draft.body = "Round \(round). " + draft.body
        }

        // Still one letter in Drafts, the latest.
        let copies = server.uids(in: Server.drafts).filter {
            server.letter(uid: $0, in: Server.drafts)?.subject == "Sunday"
        }
        XCTAssertEqual(copies.count, 1)
    }

    // MARK: - A draft begun somewhere else

    func testADraftBegunElsewhereKeepsItsOwnPictureAndItsFileAsFiles() async throws {
        // A photograph placed in the body by another client has nowhere to
        // go in a plain composer (D-013), so it comes back as a file row and
        // goes as a file rather than being lost. Only the signature's own
        // picture is left for the signature to bring.
        let porch = Data((0..<700).map { UInt8(truncatingIfNeeded: $0 &* 5 &+ 9) })
        let quote = Data("%PDF-1.4 quote for the roof".utf8)
        let uid = try XCTUnwrap(server.deliver(Server.Letter(
            from: Server.Address(name: "Sam Example", address: "sam@example.com"),
            to: [Server.carlo], subject: "The roof",
            date: Server.newestDate,
            text: "Here is the porch.\r\n\r\nSam Example\r\n555-555-0142\r\n",
            html: "<p>Here is the porch.<img src=\"cid:ii_porch1\"></p>",
            flags: ["\\Draft", "\\Seen"], messageID: "<elsewhere-1@example.com>",
            files: [Server.File(name: "Porch.jpg", type: "IMAGE", subtype: "JPEG",
                                bytes: porch, contentID: "ii_porch1"),
                    Server.File(name: "Quote.pdf", type: "APPLICATION", subtype: "PDF",
                                bytes: quote)]),
            to: [Server.drafts])[Server.drafts])
        let repository = makeRepository()
        let id = "\(server.uidValidity(of: Server.drafts))/\(uid)"

        let reopened = try await repository.loadDraft(id: id, mailboxID: Server.drafts)
        XCTAssertEqual(reopened.attachments.map(\.filename), ["Porch.jpg", "Quote.pdf"])

        try await repository.send(reopened)
        let letters = await submission.letters()
        let sent = parts(of: try XCTUnwrap(letters.last))
        XCTAssertEqual(sent.filter { $0.data == porch }.map(\.filename), ["Porch.jpg"])
        XCTAssertEqual(sent.filter { $0.data == quote }.map(\.filename), ["Quote.pdf"])
        XCTAssertEqual(sent.filter { $0.data == logoBytes }.map(\.contentID), ["sig-logo"])
        XCTAssertEqual(sent.count, 3, "\(sent.map(\.filename))")
    }

    // MARK: - The rule itself

    private func message(_ attachments: [Attachment]) -> Message {
        Message(id: "600003/301", mailboxID: Server.drafts, sender: "Sam Example",
                senderAddress: "sam@example.com", to: ["carlo@example.org"], cc: [],
                subject: "Sunday", date: Server.newestDate, textBody: "Lunch at one?",
                htmlBody: nil, attachments: attachments)
    }

    func testOnlyTheSignaturesOwnContentIDIsLeftOut() {
        let m = message([
            Attachment(id: "1.2", filename: "logo.png", mimeType: "image/png", size: 900,
                       contentID: "sig-logo", isInline: true),
            Attachment(id: "1.3", filename: "Porch.jpg", mimeType: "image/jpeg", size: 700,
                       contentID: "ii_porch1", isInline: true),
            // Called the same as the logo, but a file: no Content-ID.
            Attachment(id: "2", filename: "logo.png", mimeType: "image/png", size: 4096),
        ])
        let draft = Draft.reopening(m, signatureImages: [logo])
        XCTAssertEqual(draft.attachments.map(\.filename), ["Porch.jpg", "logo.png"])
        XCTAssertEqual(draft.attachments.map(\.size), [700, 4096])
    }

    func testEverythingElseInTheDraftComesBackAsItWasSaved() throws {
        // A Bcc lost here would send the letter without the person he had
        // copied in secret, and nothing on the sending screen would say so.
        let m = Message(id: "600003/301", mailboxID: Server.drafts, sender: "Sam Example",
                        senderAddress: "sam@example.com", to: ["carlo@example.org"],
                        cc: ["owner@example.com"], bcc: ["sam@example.com"],
                        subject: "Sunday", date: Server.newestDate,
                        textBody: "Lunch at one?\n\nSam Example", htmlBody: nil,
                        attachments: [Attachment(id: "2", filename: "Garden.jpg",
                                                 mimeType: "image/jpeg", size: 1500)])
        let draft = Draft.reopening(m, signatureImages: [logo])
        XCTAssertEqual(draft.to, ["carlo@example.org"])
        XCTAssertEqual(draft.cc, ["owner@example.com"])
        XCTAssertEqual(draft.bcc, ["sam@example.com"])
        XCTAssertEqual(draft.subject, "Sunday")
        XCTAssertEqual(draft.body, "Lunch at one?\n\nSam Example")
        XCTAssertEqual(draft.savedID, "600003/301")

        // The photo is named, not copied: fetched from the saved copy at send.
        let photo = try XCTUnwrap(draft.attachments.first)
        guard case let .messagePart(messageID, mailboxID, section, _) = photo.source else {
            return XCTFail("\(photo.source)")
        }
        XCTAssertEqual([messageID, mailboxID, section], ["600003/301", Server.drafts, "2"])
        XCTAssertEqual(photo.filename, "Garden.jpg")
        XCTAssertEqual(photo.mimeType, "image/jpeg")
        XCTAssertEqual(photo.size, 1500)
    }

    func testADraftWrittenAsHTMLAloneReopensWithItsWords() {
        let m = Message(id: "600003/302", mailboxID: Server.drafts, sender: "Sam Example",
                        senderAddress: "sam@example.com", to: ["carlo@example.org"], cc: [],
                        subject: "Sunday", date: Server.newestDate, textBody: nil,
                        htmlBody: "<p>Lunch at one?</p>", attachments: [])
        XCTAssertTrue(Draft.reopening(m, signatureImages: [logo]).body.contains("Lunch at one?"))
    }

    func testWithNoSignaturePicturesEveryPartComesBack() {
        let m = message([
            Attachment(id: "1.2", filename: "logo.png", mimeType: "image/png", size: 900,
                       contentID: "sig-logo", isInline: true),
        ])
        XCTAssertEqual(Draft.reopening(m, signatureImages: []).attachments.map(\.filename),
                       ["logo.png"])
    }

    func testTheSignaturesIDIsComparedAsTheReaderSpellsIt() {
        // Stored with brackets by hand in the defaults, it still names the
        // same part: the builder strips them before writing the header.
        let bracketed = SignatureImages.InlineImage(contentID: "<sig-logo>", filename: "logo.png",
                                                    mimeType: "image/png",
                                                    dataBase64: logo.dataBase64)
        let m = message([
            Attachment(id: "1.2", filename: "logo.png", mimeType: "image/png", size: 900,
                       contentID: "sig-logo", isInline: true),
        ])
        XCTAssertTrue(Draft.reopening(m, signatureImages: [bracketed]).attachments.isEmpty)
    }
}

/// One scripted submission server per connection, as Gmail gives each send
/// its own, with every letter they were sent in the order they came, the
/// dot-stuffing on the wire taken off again.
private final class Submissions: @unchecked Sendable {
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
