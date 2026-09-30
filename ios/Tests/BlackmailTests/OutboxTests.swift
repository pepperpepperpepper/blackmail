import XCTest
@testable import Blackmail

/// One letter handed to the submission server by `Outbox`, which the app's
/// repository and the share extension both send through (B-036): what it
/// refuses before anything is fetched, and what the repository's call
/// hands it for a reply. Against a scripted submission server; nothing is
/// sent anywhere.
final class OutboxTests: XCTestCase {

    private static let suite = "OutboxTests"
    private let account = MailAccount(address: "owner@example.com", username: "owner@example.com")

    override func setUp() {
        super.setUp()
        removeTranscripts()
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
    }

    override func tearDown() {
        removeTranscripts()
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        super.tearDown()
    }

    private func transcript(_ outcome: String) -> String {
        (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
    }

    /// A send leaves its transcript in the temporary directory, as it does
    /// on the device, where that is the evidence. Here it is litter.
    private func removeTranscripts() {
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

    /// A letter addressed to nobody is refused before its files are asked
    /// for: a forward's would be downloaded for a letter that cannot go.
    func testALetterToNobodyIsRefusedBeforeItsFilesAreFetched() async throws {
        let server = ScriptedSubmission()
        var draft = Draft(to: [" "], subject: "Fwd: The garden")
        draft.cc = [""]
        var fetched = false

        do {
            try await Outbox.send(draft, from: account, password: "app-password",
                                  through: SMTPClient(account: account, transport: { _, _ in server }),
                                  threadHeaders: nil,
                                  attachments: { fetched = true; return [] },
                                  htmlBody: nil, inlineImages: [], progress: nil)
            XCTFail("a letter to nobody went")
        } catch MailError.notSent {
        } catch {
            XCTFail("\(error)")
        }
        XCTAssertFalse(fetched, "its files were fetched for nothing")
        let commands = await server.commands
        XCTAssertTrue(commands.isEmpty)
    }

    /// A reply sent through the repository keeps its thread: In-Reply-To
    /// its parent, and References the ancestry with the parent last. The
    /// builder has done this since it was fixed; what is checked here is
    /// the repository's call, which once handed it nothing, so that every
    /// reply started a new conversation.
    func testAReplySentThroughTheRepositoryKeepsItsThread() async throws {
        let server = ScriptedSubmission()
        let repository = IMAPMailRepository(
            account: account, password: "app-password", transport: { _, _ in server },
            recipients: RecipientBook(defaults: UserDefaults(suiteName: Self.suite)!),
            signatureImages: { [] })
        var draft = Draft(to: ["carlo@example.org"], subject: "Re: Sunday", body: "One o'clock.")
        draft.inReplyTo = "<parent@example.org>"
        draft.references = "<root@example.org>"

        try await repository.send(draft, progress: nil)

        let letters = await server.letters
        let wire = String(decoding: try XCTUnwrap(letters.first), as: UTF8.self)
        let headers = wire.components(separatedBy: "\r\n\r\n").first ?? ""
        XCTAssertTrue(headers.contains("\r\nIn-Reply-To: <parent@example.org>\r\n"), headers)
        XCTAssertTrue(headers.contains("\r\nReferences: <root@example.org> <parent@example.org>\r\n"),
                      headers)
        try await until {
            await server.isClosed && FileManager.default.fileExists(atPath: self.transcript("ok"))
        }
    }
}
