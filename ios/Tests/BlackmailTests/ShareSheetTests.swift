import XCTest
@testable import Blackmail

/// The share extension's sheet without the sheet (B-036): a shared link
/// sent through the app's own `Submission` to a scripted submission server, in
/// `ComposeActions`' order. One letter however many taps, the share ended
/// once the letter has gone, everything as it was when it has not, and
/// Cancel refused while a letter is on its way. Nothing is sent anywhere.
@MainActor
final class ShareSheetTests: XCTestCase {

    private let account = MailAccount(address: "owner@example.com", username: "owner@example.com",
                                      displayName: "Sam", signature: "Sam\n1 Example Street",
                                      signatureHTML: "<table><tr><td><img src=\"cid:sig-logo\">"
                                          + "</td><td>Sam</td></tr></table>")
    private let page = URL(string: "https://en.wikipedia.org/wiki/Mercury_(planet)?wprov=sfti1")!
    private let logoBytes = Data((0..<300).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) })

    private var log: [String] = []
    private var draws: [ComposeActions.Look] = []
    private var errors: [MailError] = []
    private var noted: [[String]] = []
    private var files: [URL: Data] = [:]

    override func setUp() {
        super.setUp()
        removeTranscripts()
    }

    override func tearDown() {
        removeTranscripts()
        super.tearDown()
    }

    /// Where `CaptureProbe` puts a send's transcript, the last one's.
    private nonisolated func transcript(_ outcome: String) -> String {
        (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
    }

    /// A send leaves its transcript in the temporary directory, as it does
    /// on the device, where that is the evidence. Here it is litter.
    private nonisolated func removeTranscripts() {
        for outcome in ["ok", "fail"] { try? FileManager.default.removeItem(atPath: transcript(outcome)) }
    }

    /// Waits, a millisecond at a time and never for more than a second,
    /// until `condition` holds.
    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    /// The connection a letter went on, let go of after `send` returned,
    /// and its transcript written, so the test leaves neither behind.
    private func lettingGo(_ server: ScriptedSubmission, outcome: String = "ok") async throws {
        try await until {
            await server.isClosed && FileManager.default.fileExists(atPath: self.transcript(outcome))
        }
    }

    private func sheet(_ server: ScriptedSubmission,
                       recipients: [KnownRecipient] = [],
                       signatureImages: [SignatureImages.InlineImage] = [],
                       memory: @escaping @Sendable () -> SharedPhoto.Memory = { .init() })
        -> ShareSheet {
        let shared = ShareMirror.Shared(account: account, password: "app-password",
                                        signatureImages: signatureImages, recipients: recipients)
        return ShareSheet(
            shared: shared,
            transport: { _, _ in server },
            openFile: { [unowned self] attachment in
                guard case let .localFile(url) = attachment.source, let data = files[url] else {
                    throw MailError.attachmentFailed
                }
                return .bytes(data)
            },
            memory: memory,
            noteSent: { [unowned self] in noted.append($0) },
            finish: { [unowned self] in log.append("finish") },
            cancel: { [unowned self] in log.append("cancel") },
            showError: { [unowned self] in errors.append($0); log.append("error") },
            draw: { [unowned self] in draws.append($0) },
            background: BackgroundTime(begin: { _, _ in nil }, end: { _ in }))
    }

    /// A file as `ShareItems.Staging` hands one over: staged, here in
    /// memory, where the sheet's `openFile` finds it at Send.
    private func file(_ data: Data, _ filename: String, _ mimeType: String) -> SharedItem {
        let url = URL(fileURLWithPath: "/staged/\(files.count)/\(filename)")
        files[url] = data
        return .file(url, filename: filename, mimeType: mimeType, size: Int64(data.count))
    }

    private func letter(_ sheet: ShareSheet, to: [String] = ["owner@example.net"],
                        _ items: [SharedItem]) -> Draft {
        var draft = sheet.letter(from: items)
        draft.to = to
        return draft
    }

    // MARK: - The letter on the wire

    /// A link and a photo, shared: on the wire, the title as the subject,
    /// the address in the plain part, a link to it in the HTML twin, his
    /// signature in both, and the photo's bytes. Signed in as the account
    /// the app handed over, with its password.
    func testASharedLinkAndPhotoArriveWhole() async throws {
        let server = ScriptedSubmission()
        let sheet = sheet(server)
        let jpeg = Data((0..<600).map { UInt8($0 % 251) })
        let draft = letter(sheet, [.link(page, title: "Mercury - Wikipedia"),
                                   file(jpeg, "Garden.jpg", "image/jpeg")])

        await sheet.send { draft }?.value

        let letters = await server.letters
        XCTAssertEqual(letters.count, 1)
        let wire = try XCTUnwrap(letters.first)
        let headers = MIMEDecoder.parseHeaders(wire)
        XCTAssertEqual(MIMEDecoder.headerValue("Subject", in: headers).map(MIMEDecoder.decodeWord),
                       "Mercury - Wikipedia")
        let decoded = MIMEDecoder.decodeMessage(wire)
        let text = try XCTUnwrap(decoded.text)
        XCTAssertTrue(text.hasPrefix(page.absoluteString), text)
        XCTAssertTrue(text.contains("1 Example Street"))
        let html = try XCTUnwrap(decoded.html)
        XCTAssertTrue(html.contains("<a href=\"\(page.absoluteString)\">"), html)
        XCTAssertTrue(html.contains("Sam"))
        XCTAssertEqual(decoded.attachments.map(\.filename), ["Garden.jpg"])
        let bytes = MIMEDecoder.parse(wire).bodies.values
            .map { MIMEDecoder.decodeTransfer($0, encoding: "base64") }
        XCTAssertTrue(bytes.contains(jpeg), "the photo's bytes, unchanged")

        let commands = await server.commands
        let auth = try XCTUnwrap(commands.first { $0.hasPrefix("AUTH PLAIN ") })
        XCTAssertEqual(Data(base64Encoded: String(auth.dropFirst("AUTH PLAIN ".count))),
                       Data("\0owner@example.com\0app-password".utf8),
                       "signed in with the password the app handed over")
        XCTAssertTrue(commands.contains("RCPT TO:<owner@example.net>"), "\(commands)")
        XCTAssertEqual(log, ["finish"], "the share ends once the letter has gone")
        XCTAssertEqual(noted, [["owner@example.net"]], "and the app hears who it went to")
        try await lettingGo(server)
    }

    /// His signature's pictures, as the app mirrored them, go with the
    /// letter as inline parts under the Content-ID its markup names, as
    /// they do from the app.
    func testTheSignaturesPicturesGoWithTheLetter() async throws {
        let server = ScriptedSubmission()
        let logo = SignatureImages.InlineImage(contentID: "sig-logo", filename: "logo.png",
                                               mimeType: "image/png",
                                               dataBase64: logoBytes.base64EncodedString())
        let sheet = sheet(server, signatureImages: [logo])
        let draft = letter(sheet, [.link(page, title: nil)])

        await sheet.send { draft }?.value

        let letters = await server.letters
        let wire = try XCTUnwrap(letters.first)
        let parsed = MIMEDecoder.parse(wire)
        let inline = MIMEDecoder.decodeMessage(wire).attachments.filter { $0.contentID == "sig-logo" }
        XCTAssertEqual(inline.count, 1, "the logo, once")
        let part = try XCTUnwrap(inline.first)
        XCTAssertTrue(part.isInline)
        let encoding = MIMEDecoder.part(at: part.id, in: parsed.structure)?.encoding ?? "7bit"
        XCTAssertEqual(MIMEDecoder.decodeTransfer(parsed.bodies[part.id] ?? Data(), encoding: encoding),
                       logoBytes)
        XCTAssertTrue(try XCTUnwrap(MIMEDecoder.decodeMessage(wire).html).contains("cid:sig-logo"))
        try await lettingGo(server)
    }

    /// An address picked or typed with a name on it goes to the app's book
    /// as the bare address, the form its entries are kept in.
    func testWhoItWentToIsNotedAsBareAddresses() async throws {
        let server = ScriptedSubmission()
        let sheet = sheet(server)
        var draft = letter(sheet, to: ["Carlo <carlo@example.org>"], [.link(page, title: nil)])
        draft.cc = [" owner@example.net "]

        await sheet.send { draft }?.value

        XCTAssertEqual(noted, [["carlo@example.org", "owner@example.net"]])
        let commands = await server.commands
        XCTAssertTrue(commands.contains("RCPT TO:<carlo@example.org>"), "\(commands)")
        try await lettingGo(server)
    }

    /// At Send, the memory the extension has left goes in the log three
    /// times: with the files read, in the rehearsal before the server is
    /// reached; once the envelope is taken, before DATA; and once it has
    /// gone, with the least there was at any step of its progress while it
    /// went (B-070). The least since the extension started goes with each.
    /// Numbers only.
    func testSendLogsTheMemoryLeftAroundTheBuilding() async throws {
        Diagnostics.clear()
        let server = ScriptedSubmission()
        // The rehearsal, DATA, the letter's one piece, and the 250.
        let left = Remaining([90_000_000, 61_000_000, 57_000_000, 88_000_000])
        let sheet = sheet(server, memory: { left.next() })
        let jpeg = Data((0..<600).map { UInt8($0 % 251) })
        let draft = letter(sheet, [file(jpeg, "IMG_0776.JPG", "image/jpeg"),
                                   file(Data(count: 40), "image0.png", "image/png")])

        await sheet.send { draft }?.value

        let lines = Diagnostics.entries.map(\.text)
        let notes = lines.filter { $0.hasPrefix("SHARE-SEND") }
        XCTAssertEqual(notes, [
            "SHARE-SEND files read, 2 files 640 bytes, 90 MB available, 40 MB at the least",
            "SHARE-SEND built, 61 MB available, 40 MB at the least",
            "SHARE-SEND sent, 88 MB available, 40 MB at the least, 57 MB at the least while it went",
        ])
        func at(_ text: String) -> Int { lines.firstIndex { $0.hasPrefix(text) } ?? -1 }
        XCTAssertLessThan(at("SHARE-SEND files read"), at("ENVELOPE"), "before the letter is built")
        XCTAssertLessThan(at("RCPT TO"), at("SHARE-SEND built"))
        XCTAssertLessThan(at("SHARE-SEND built"), at("DATA"))
        XCTAssertLessThan(at("DATA-REPLY-CODE"), at("SHARE-SEND sent"))
        for line in notes {
            XCTAssertFalse(line.contains("IMG_0776"), "no name")
            XCTAssertFalse(line.contains("owner@"), "no one")
        }
        XCTAssertEqual(log, ["finish"])
        try await lettingGo(server)
    }

    // MARK: - From the disk (B-070)

    /// A sheet over the extension's own staging: each file read at Send
    /// from where `ShareItems.Staging` put it, as the letter goes
    /// (`ShareSheet.staged`).
    private func stagedSheet(_ server: ScriptedSubmission,
                             memory: @escaping @Sendable () -> SharedPhoto.Memory) -> ShareSheet {
        let shared = ShareMirror.Shared(account: account, password: "app-password",
                                        signatureImages: [], recipients: [])
        return ShareSheet(
            shared: shared,
            transport: { _, _ in server },
            memory: memory,
            noteSent: { [unowned self] in noted.append($0) },
            finish: { [unowned self] in log.append("finish") },
            cancel: { [unowned self] in log.append("cancel") },
            showError: { [unowned self] in errors.append($0); log.append("error") },
            draw: { [unowned self] in draws.append($0) },
            background: BackgroundTime(begin: { _, _ in nil }, end: { _ in }))
    }

    /// A file Photos hands over, staged by copy as the extension stages it.
    private func staged(_ data: Data, _ filename: String, _ mimeType: String) throws -> SharedItem {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareSheetTests-\(UUID().uuidString)-\(filename)")
        try data.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let item = try XCTUnwrap(ShareItems.Staging().file(at: source, size: Int64(data.count),
                                                           named: filename, mimeType: mimeType))
        if case let .file(url, _, _, _) = item { stagedHere.append(url) }
        return item
    }

    private var stagedHere: [URL] = []

    /// A video from Photos, staged on the disk, goes as itself: under its
    /// own name, as QuickTime, its base64 the file's to the byte, read from
    /// the disk as it went. The three lines keep their words and their
    /// order, and the last says the least memory there was while it went.
    func testAVideoGoesFromItsStagedFileWhole() async throws {
        defer { for url in stagedHere { AttachmentStore.removeStaged(url) } }
        Diagnostics.clear()
        let server = ScriptedSubmission()
        let left = Figures([90_000_000, 61_000_000, 80_000_000, 55_000_000, 80_000_000])
        let sheet = stagedSheet(server, memory: { left.next() })
        let video = LetterCorpus.bytes(300_001, seed: 11)
        let draft = letter(sheet, [try staged(video, "IMG_0001.MOV", "video/quicktime")])

        await sheet.send { draft }?.value

        XCTAssertEqual(log, ["finish"])
        let letters = await server.letters
        let wire = String(decoding: try XCTUnwrap(letters.first), as: UTF8.self)
        let part = "Content-Type: video/quicktime; name=\"IMG_0001.MOV\"\r\n"
            + "Content-Transfer-Encoding: base64\r\n"
            + "Content-Disposition: attachment; filename=\"IMG_0001.MOV\"\r\n\r\n"
            + RFC5322Builder.base64Wrapped(video) + "\r\n--"
        XCTAssertTrue(wire.contains(part), "the video's part, whole")
        XCTAssertEqual(MIMEDecoder.decodeMessage(Data(wire.utf8)).attachments.map(\.filename),
                       ["IMG_0001.MOV"])

        let lines = Diagnostics.entries.map(\.text)
        let notes = lines.filter { $0.hasPrefix("SHARE-SEND") }
        XCTAssertEqual(notes, [
            "SHARE-SEND files read, 1 files 300001 bytes, 90 MB available, 40 MB at the least",
            "SHARE-SEND built, 61 MB available, 40 MB at the least",
            "SHARE-SEND sent, 80 MB available, 40 MB at the least, 55 MB at the least while it went",
        ])
        func at(_ text: String) -> Int { lines.firstIndex { $0.hasPrefix(text) } ?? -1 }
        XCTAssertLessThan(at("LETTER-FILE 1"), at("SHARE-SEND files read"))
        XCTAssertLessThan(at("SHARE-SEND files read"), at("ENVELOPE"))
        XCTAssertLessThan(at("SHARE-SEND built"), at("LETTER-LATCH ok"))
        XCTAssertLessThan(at("DATA-REPLY-CODE"), at("SHARE-SEND sent"))
        try await lettingGo(server)
    }

    /// A staged file that is no longer what was staged, cut short since,
    /// is "Message was not sent." before any server is reached, and the
    /// sheet stays as it was, his letter in it.
    func testAStagedFileChangedSinceIsNotSentAndTheSheetStays() async throws {
        defer { for url in stagedHere { AttachmentStore.removeStaged(url) } }
        Diagnostics.clear()
        let server = ScriptedSubmission()
        let opened = Flag()
        let shared = ShareMirror.Shared(account: account, password: "app-password",
                                        signatureImages: [], recipients: [])
        let sheet = ShareSheet(
            shared: shared, transport: { _, _ in opened.set(); return server },
            noteSent: { [unowned self] in noted.append($0) },
            finish: { [unowned self] in log.append("finish") },
            cancel: { [unowned self] in log.append("cancel") },
            showError: { [unowned self] in errors.append($0); log.append("error") },
            draw: { [unowned self] in draws.append($0) },
            background: BackgroundTime(begin: { _, _ in nil }, end: { _ in }))
        let item = try staged(LetterCorpus.bytes(10_000, seed: 12), "IMG_0002.MOV", "video/quicktime")
        let draft = letter(sheet, [item])
        if case let .file(url, _, _, _) = item {
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 5_000)
            try handle.close()
        }

        await sheet.send { draft }?.value

        XCTAssertEqual(errors, [.notSent])
        XCTAssertEqual(log, ["error"], "the sheet stays")
        XCTAssertFalse(opened.isSet, "no server reached")
        XCTAssertTrue(Diagnostics.entries.map(\.text)
            .contains("LETTER-FILE 1 refused size 5000 attached 10000"))
        XCTAssertFalse(sheet.isSending)
    }

    // MARK: - ComposeActions' order

    /// Send tapped again while the letter goes, and after: one letter, one
    /// finish. "Sending…" at the tap, as the composer shows it.
    func testOneLetterHoweverManyTaps() async throws {
        let server = ScriptedSubmission()
        let sheet = sheet(server)
        let draft = letter(sheet, [.link(page, title: nil)])

        let first = try XCTUnwrap(sheet.send { draft })
        XCTAssertEqual(draws, [.sending("Sending…")])
        XCTAssertTrue(sheet.isSending)
        XCTAssertNil(sheet.send { draft }, "a second tap while it goes")
        await first.value
        XCTAssertNil(sheet.send { draft }, "a tap after it has gone")

        let letters = await server.letters
        XCTAssertEqual(letters.count, 1)
        XCTAssertEqual(log, ["finish"])
        try await lettingGo(server)
    }

    /// A letter that did not go: the sheet stays, Send is back, he is told
    /// why, the share is not ended and nobody is noted as written to. A tap
    /// then sends it again.
    func testALetterThatDidNotGoLeavesTheSheetAsItWas() async throws {
        let refused = ScriptedSubmission(failsToOpen: true)
        let sheet = sheet(refused)
        let draft = letter(sheet, [.link(page, title: nil)])

        await sheet.send { draft }?.value

        XCTAssertEqual(draws, [.sending("Sending…"), .writing])
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(log, ["error"], "not finished, not cancelled")
        XCTAssertTrue(noted.isEmpty)
        XCTAssertFalse(sheet.isSending)
        let again = try XCTUnwrap(sheet.send { draft }, "Send works again")
        await again.value
        XCTAssertEqual(errors.count, 2)
    }

    /// Cancel while the letter goes does nothing: the letter is on its way
    /// and the share ends when it has gone, not before and not twice.
    func testCancelWhileTheLetterGoesDoesNothing() async throws {
        let server = ScriptedSubmission()
        let sheet = sheet(server)
        let draft = letter(sheet, [.link(page, title: nil)])

        let sending = try XCTUnwrap(sheet.send { draft })
        XCTAssertNil(sheet.cancel())
        await sending.value
        XCTAssertNil(sheet.cancel(), "nor after it has gone")
        XCTAssertEqual(log, ["finish"])
        try await lettingGo(server)
    }

    /// Cancel before anything is sent puts the share away, once, and a
    /// Send after it sends nothing.
    func testCancelPutsTheShareAway() async throws {
        let server = ScriptedSubmission()
        let sheet = sheet(server)
        let draft = letter(sheet, [.link(page, title: nil)])

        await sheet.cancel()?.value
        XCTAssertNil(sheet.send { draft })
        XCTAssertNil(sheet.cancel())
        let letters = await server.letters
        XCTAssertTrue(letters.isEmpty)
        XCTAssertEqual(log, ["cancel"])
    }

    /// Nobody to send to is refused before a connection is made, as in the
    /// app, and says so. The shared file is never read for it.
    func testALetterToNobodyIsNotSent() async throws {
        let server = ScriptedSubmission()
        let sheet = sheet(server)
        let draft = letter(sheet, to: [" "], [.link(page, title: nil),
                                              file(Data([1, 2, 3]), "Garden.jpg", "image/jpeg")])
        // Gone from the disk, so reading it would fail, and say so.
        files.removeAll()

        await sheet.send { draft }?.value
        let commands = await server.commands
        XCTAssertTrue(commands.isEmpty)
        XCTAssertEqual(errors.map(\.errorDescription), [MailError.notSent.errorDescription],
                       "nobody to send to, not a file that could not be read")
    }

    // MARK: - Cancel asks first

    /// Cancel asks before throwing away anything of his: words above his
    /// signature, an address, a subject of his own. What the share began
    /// with is not his, and goes without a question.
    func testCancelAsksOnceAnythingOfHisIsInIt() {
        let sheet = sheet(ScriptedSubmission())
        let started = sheet.letter(from: [.link(page, title: "Mercury - Wikipedia")])
        XCTAssertFalse(sheet.asksBeforeCancelling(started), "as the share began it")

        var words = started
        words.body = "Look at this\n" + started.body
        XCTAssertTrue(sheet.asksBeforeCancelling(words))

        var addressed = started
        addressed.to = ["owner@example.net"]
        XCTAssertTrue(sheet.asksBeforeCancelling(addressed))

        var retitled = started
        retitled.subject = "Mercury, for Sunday"
        XCTAssertTrue(sheet.asksBeforeCancelling(retitled))
    }

    /// After a Send that did not go, his letter is still his and still
    /// unsent: Cancel asks, as it did before the Send. What was handed to
    /// Send is not what the question is measured against.
    func testCancelStillAsksAfterASendThatDidNotGo() async throws {
        let sheet = sheet(ScriptedSubmission(failsToOpen: true))
        var written = sheet.letter(from: [.link(page, title: nil)])
        written.to = ["owner@example.net"]
        written.body = "Look at this\n" + written.body

        await sheet.send { written }?.value

        XCTAssertEqual(log, ["error"])
        XCTAssertTrue(sheet.asksBeforeCancelling(written))
    }

    // MARK: - Suggestions

    /// The app's book as it was mirrored: his most used first when nothing
    /// is typed, a match for what he has typed after the last comma, and
    /// nothing once that is a whole address.
    func testTheAddressFieldsOfferTheAppsBook() {
        let seen = Date(timeIntervalSince1970: 1_700_000_000)
        let sheet = sheet(ScriptedSubmission(), recipients: [
            KnownRecipient(address: "carlo@example.org", name: "Carlo", uses: 3, lastSeen: seen),
            KnownRecipient(address: "owner@example.net", name: nil, uses: 40, lastSeen: seen),
        ])
        XCTAssertEqual(sheet.suggestions(for: "").map(\.address).first, "owner@example.net")
        XCTAssertEqual(sheet.suggestions(for: "owner@example.net, car").map(\.address),
                       ["carlo@example.org"])
        XCTAssertTrue(sheet.suggestions(for: "carlo@example.org").isEmpty)
    }
}

/// The memory a test's extension says it has left, one figure each time it
/// is asked and the last of them from then on, the least so far held at
/// 40 MB.
private final class Figures: @unchecked Sendable {
    private var figures: [Int64]
    private let lock = NSLock()

    init(_ figures: [Int64]) { self.figures = figures }

    func next() -> SharedPhoto.Memory {
        lock.lock()
        defer { lock.unlock() }
        let available = figures.count > 1 ? figures.removeFirst() : figures.first
        return SharedPhoto.Memory(available: available, least: 40_000_000)
    }
}

/// The memory a test's extension says it has left, one figure each time it
/// is asked, the least of them so far held at 40 MB.
private final class Remaining: @unchecked Sendable {
    private var figures: [Int64]
    private let lock = NSLock()

    init(_ figures: [Int64]) { self.figures = figures }

    func next() -> SharedPhoto.Memory {
        lock.lock()
        defer { lock.unlock() }
        let available = figures.isEmpty ? nil : figures.removeFirst()
        return SharedPhoto.Memory(available: available, least: 40_000_000)
    }
}
