import XCTest
#if canImport(Glibc)
import Glibc
#endif
@testable import Blackmail

/// Send streams the letter from its files (B-070), through `Submission`, the
/// shipping SMTP client and a scripted submission server: the letter that
/// arrives is the reference builder's, byte for byte, with SIZE its count
/// and the progress in the steps it always was; a file changed while it
/// goes never ends the letter, which has no dot and no QUIT; a file taken
/// away after it was opened still goes whole; and a file that cannot go is
/// refused before any server is reached. Nothing is sent anywhere.
final class StreamingSendTests: XCTestCase {

    private let account = MailAccount(address: "owner@example.com", username: "owner@example.com",
                                      displayName: "Sam Example")
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private let messageID = "<b070-stream@example.com>"
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        Diagnostics.clear()
        removeTranscripts()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StreamingSendTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        removeTranscripts()
        super.tearDown()
    }

    private nonisolated func transcript(_ outcome: String) -> String {
        (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
    }

    private nonisolated func removeTranscripts() {
        for outcome in ["ok", "fail"] { try? FileManager.default.removeItem(atPath: transcript(outcome)) }
    }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    /// The connection let go of and its transcript written.
    private func lettingGo(_ server: ScriptedSubmission, outcome: String) async throws {
        try await until {
            await server.isClosed && FileManager.default.fileExists(atPath: self.transcript(outcome))
        }
    }

    private var draft: Draft {
        var draft = Draft()
        draft.to = ["Carlo <carlo@example.org>"]
        draft.subject = "Sunday's video"
        draft.body = "Dear Carlo,\n.\nHere it is.\n"
        return draft
    }

    private let markup = "<div>Dear Carlo,<br>Here it is.</div><img src=\"cid:sig-logo\">"

    /// A file of `data` in the test's directory.
    private func file(_ name: String, _ data: Data) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    /// The letter `Submission` makes of these files, made by the builder as
    /// it was before B-070.
    private func reference(_ files: [(String, String, Data)]) -> Data {
        ReferenceBuilder.build(draft: draft, from: account, date: date, messageID: messageID,
                               attachments: files, htmlBody: markup,
                               inlineImages: [LetterCorpus.logo], boundaryToken: Counting().next)
    }

    /// Sends `draft` with `files` from the disk to `server`, as the app's
    /// repository and the share sheet do.
    private func send(_ files: [(String, String, URL)], to server: ScriptedSubmission,
                      opened: Flag = Flag(),
                      beforeData: (@Sendable () async throws -> Void)? = nil,
                      progress: UploadProgress? = nil,
                      opening: ([LetterSource]) throws -> LetterFiles = { try LetterFiles(opening: $0) })
        async throws {
        let sizes = try files.map { file -> Int64 in
            let values = try FileManager.default.attributesOfItem(atPath: file.2.path)
            return (values[.size] as? NSNumber)?.int64Value ?? 0
        }
        try await Submission.send(
            draft, from: account, password: "app-password",
            through: SMTPClient(account: account, transport: { _, _ in opened.set(); return server }),
            threadHeaders: nil,
            attachments: {
                zip(files, sizes).map { ($0.0, $0.1, .disk($0.2, attachedSize: $1)) }
            },
            htmlBody: markup, inlineImages: [LetterCorpus.logo], messageID: messageID,
            beforeData: beforeData, progress: progress, date: date,
            boundaryToken: Counting().next, opening: opening)
    }

    private var lines: [String] { Diagnostics.entries.map(\.text) }

    // MARK: - The letter as it was

    /// A video and a note from the disk arrive as the reference letter, its
    /// DATA the old payload of it. SIZE is the letter's count. The progress
    /// is the 64 KiB steps it always was, to the payload. The rehearsal
    /// comes before the server, the latch before the write's end, and each
    /// file's CRC is its bytes'.
    func testALetterOfFilesArrivesAsTheReferenceLetter() async throws {
        let video = LetterCorpus.bytes(300_007, seed: 1)
        let notes = LetterCorpus.bytes(1_234, seed: 2)
        let videoURL = try file("IMG_0001.MOV", video)
        let notesURL = try file("Notes.txt", notes)
        let server = ScriptedSubmission()
        let heard = Heard()

        try await send([("IMG_0001.MOV", "video/quicktime", videoURL),
                        ("Notes.txt", "text/plain", notesURL)],
                       to: server, progress: { heard.add($0, $1) })

        let raw = reference([("IMG_0001.MOV", "video/quicktime", video),
                             ("Notes.txt", "text/plain", notes)])
        let payload = SMTPClient.dataPayload(raw)
        let letters = await server.letters
        XCTAssertEqual(letters.count, 1)
        XCTAssertEqual((letters.first ?? Data()) + Data(".\r\n".utf8), payload)
        let digests = await server.letterDigests
        XCTAssertEqual(digests.first?.count, payload.count - 3)

        let commands = await server.commands
        let mailFrom = try XCTUnwrap(commands.first { $0.hasPrefix("MAIL FROM") })
        XCTAssertTrue(mailFrom.hasSuffix(" SIZE=\(raw.count)"), mailFrom)

        let piece = TransportDeadline.writeChunkBytes
        XCTAssertEqual(heard.all.map(\.written),
                       Array(stride(from: piece, to: payload.count, by: piece)) + [payload.count])
        XCTAssertEqual(Set(heard.all.map(\.total)), [payload.count])

        func at(_ prefix: String) -> Int { lines.firstIndex { $0.hasPrefix(prefix) } ?? -1 }
        let data = lines.firstIndex { $0 == "DATA" } ?? -1
        XCTAssertLessThan(at("LETTER-PLAN"), at("LETTER-FILE 1"))
        XCTAssertLessThan(at("LETTER-FILE 2"), at("ENVELOPE"))
        XCTAssertLessThan(at("ENVELOPE"), data)
        XCTAssertLessThan(data, at("LETTER-LATCH ok"))
        XCTAssertLessThan(at("LETTER-LATCH ok"), at("WIRE-ACK err=none"))
        XCTAssertLessThan(at("WIRE-ACK err=none"), at("DATA-REPLY-CODE"))
        XCTAssertEqual(lines.filter { $0.hasPrefix("WIRE-OUT") }, ["WIRE-OUT bytes=\(payload.count)"])
        XCTAssertEqual(lines.filter { $0.hasPrefix("WIRE-ACK") }, ["WIRE-ACK err=none"])
        let plan = lines.first { $0.hasPrefix("LETTER-PLAN") } ?? ""
        XCTAssertTrue(plan.hasPrefix("LETTER-PLAN files=2 file-bytes=\(video.count + notes.count) "
                                     + "raw=\(raw.count) payload=\(payload.count) ms="), plan)
        var crc = CRC32()
        crc.update(video)
        XCTAssertTrue(lines.contains("LETTER-FILE 1 bytes=\(video.count) crc=\(CRC32.hex(crc.value))"))
        XCTAssertTrue(lines.contains("LETTER-LATCH ok raw=\(raw.count) payload=\(payload.count)"))
        try await lettingGo(server, outcome: "ok")
    }

    /// SIZE is the letter's own count, which the rehearsal knows before
    /// the connection: a letter one byte over what the server advertises
    /// is refused before MAIL FROM, "too big", with nothing of it sent; one
    /// exactly at it goes.
    func testALetterOverTheServersSizeIsRefusedBeforeMailFrom() async throws {
        let video = LetterCorpus.bytes(100_000, seed: 6)
        let url = try file("IMG_0004.MOV", video)
        let raw = reference([("IMG_0004.MOV", "video/quicktime", video)])

        let small = ScriptedSubmission(advertisedSize: raw.count - 1)
        do {
            try await send([("IMG_0004.MOV", "video/quicktime", url)], to: small)
            XCTFail("a letter over SIZE went")
        } catch let error as MailError {
            XCTAssertEqual(error, .messageTooLarge)
        }
        let refused = await small.commands
        XCTAssertFalse(refused.contains { $0.hasPrefix("MAIL FROM") }, "\(refused)")
        XCTAssertTrue(lines.contains("refusing locally: \(raw.count) bytes exceeds the server's SIZE \(raw.count - 1)"))
        try await lettingGo(small, outcome: "fail")

        removeTranscripts()
        let exact = ScriptedSubmission(advertisedSize: raw.count)
        try await send([("IMG_0004.MOV", "video/quicktime", url)], to: exact)
        let letters = await exact.letters
        XCTAssertEqual(letters.count, 1)
        try await lettingGo(exact, outcome: "ok")
    }

    // MARK: - Never a letter changed on its way

    /// The file changed after the rehearsal, before DATA, three ways: cut
    /// short, grown, and rewritten at the same size. Each time the letter
    /// is never ended: nothing arrives, no dot, the transport is closed,
    /// no QUIT is written into it, and he reads "Message was not sent.".
    func testAFileChangedAfterTheRehearsalNeverEndsTheLetter() async throws {
        let ways: [(String, String, @Sendable (URL) throws -> Void)] = [
            ("cut short", "short read", { url in
                let handle = try FileHandle(forWritingTo: url)
                try handle.truncate(atOffset: 150_000)
                try handle.close()
            }),
            ("grown", "longer than its size", { url in
                let handle = try FileHandle(forWritingTo: url)
                _ = try handle.seekToEnd()
                try handle.write(contentsOf: Data("more".utf8))
                try handle.close()
            }),
            ("rewritten at the same size", "changed since the rehearsal", { url in
                let handle = try FileHandle(forWritingTo: url)
                try handle.seek(toOffset: 200_000)
                try handle.write(contentsOf: Data(repeating: 0x55, count: 3))
                try handle.close()
            }),
        ]
        for (way, reason, change) in ways {
            Diagnostics.clear()
            removeTranscripts()
            let url = try file("IMG_0002-\(way.count).MOV", LetterCorpus.bytes(300_000, seed: 3))
            let server = ScriptedSubmission()
            do {
                try await send([("IMG_0002.MOV", "video/quicktime", url)], to: server,
                               beforeData: { try change(url) })
                XCTFail("\(way): sent")
            } catch let error as MailError {
                XCTAssertEqual(error, .notSent, way)
            }
            let letters = await server.letters
            let sawTerminator = await server.sawTerminator
            let closed = await server.isClosed
            let quits = await server.quitAttempts
            XCTAssertEqual(letters.count, 0, way)
            XCTAssertFalse(sawTerminator, "\(way): no dot")
            XCTAssertTrue(closed, way)
            XCTAssertEqual(quits, 0, "\(way): no QUIT written into the letter")
            XCTAssertTrue(lines.contains { $0.hasPrefix("LETTER-LATCH withheld file=1 reason=\(reason)") },
                          "\(way): \(lines.filter { $0.hasPrefix("LETTER") })")
            XCTAssertFalse(lines.contains { $0.hasPrefix("LETTER-LATCH ok") }, way)
            XCTAssertTrue(lines.contains("WIRE-ACK err=source"), way)
            try await lettingGo(server, outcome: "fail")
        }
    }

    /// A file taken away once the letter has opened it, a second share's
    /// purge or a letter's folder tidied, goes whole all the same: it is
    /// read by its descriptor, never again by its name.
    func testAFileRemovedAfterOpeningStillGoesWhole() async throws {
        let video = LetterCorpus.bytes(200_000, seed: 4)
        let url = try file("IMG_0003.MOV", video)
        let server = ScriptedSubmission()
        try await send([("IMG_0003.MOV", "video/quicktime", url)], to: server,
                       beforeData: { try FileManager.default.removeItem(at: url) })
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let letters = await server.letters
        XCTAssertEqual((letters.first ?? Data()) + Data(".\r\n".utf8),
                       SMTPClient.dataPayload(reference([("IMG_0003.MOV", "video/quicktime", video)])))
        try await lettingGo(server, outcome: "ok")
    }

    // MARK: - Refused before the server

    /// A file that is not there, a directory, a pipe, a file not the size
    /// it was attached at, and one that reads short in the rehearsal: each
    /// is "Message was not sent.", said in the log by its number, and no
    /// server is ever reached.
    func testAFileThatCannotGoReachesNoServer() async throws {
        let missing = directory.appendingPathComponent("gone.MOV")
        let folder = directory.appendingPathComponent("A folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pipe = directory.appendingPathComponent("pipe")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        let good = try file("good.bin", LetterCorpus.bytes(100_000, seed: 5))

        let cases: [(String, [(String, String, LetterSource)], String,
                     (([LetterSource]) throws -> LetterFiles)?)] = [
            ("missing", [("gone.MOV", "video/quicktime", .disk(missing, attachedSize: 10))],
             "LETTER-FILE 1 refused not openable errno=\(ENOENT)", nil),
            ("a directory", [("good.bin", "application/octet-stream", .disk(good, attachedSize: 100_000)),
                             ("A folder", "application/octet-stream", .disk(folder, attachedSize: nil))],
             "LETTER-FILE 2 refused not a file", nil),
            ("a pipe", [("pipe", "application/octet-stream", .disk(pipe, attachedSize: nil))],
             "LETTER-FILE 1 refused not a file", nil),
            ("not its size", [("good.bin", "application/octet-stream", .disk(good, attachedSize: 99_999))],
             "LETTER-FILE 1 refused size 100000 attached 99999", nil),
            ("short in the rehearsal",
             [("good.bin", "application/octet-stream", .disk(good, attachedSize: 100_000))],
             "LETTER-FILE 1 refused short read 58368 of 100000", { sources in
                let files = try LetterFiles(opening: sources)
                files.cut = { _, offset, asked in offset >= 58_368 ? 0 : asked }
                return files
             }),
        ]
        for (label, files, said, opening) in cases {
            Diagnostics.clear()
            let server = ScriptedSubmission()
            let opened = Flag()
            do {
                try await Submission.send(
                    draft, from: account, password: "app-password",
                    through: SMTPClient(account: account,
                                        transport: { _, _ in opened.set(); return server }),
                    threadHeaders: nil, attachments: { files }, htmlBody: nil, inlineImages: [],
                    progress: nil, opening: opening ?? { try LetterFiles(opening: $0) })
                XCTFail("\(label): sent")
            } catch let error as MailError {
                XCTAssertEqual(error, .notSent, label)
            }
            XCTAssertFalse(opened.isSet, "\(label): a server was reached")
            let commands = await server.commands
            XCTAssertEqual(commands, [], label)
            XCTAssertTrue(lines.contains(said), "\(label): \(lines)")
            XCTAssertFalse(lines.contains { $0.hasPrefix("ENVELOPE") || $0.hasPrefix("LETTER-PLAN") },
                           label)
        }
    }

    /// A file whose size when attached is not known goes, its size not
    /// checked, and its line in the log says so; a file checked beside it
    /// keeps its line as it was. Nothing in the log looks checked that
    /// was not.
    func testAFileOfNoKnownSizeGoesAndTheLogSaysItWasNotChecked() async throws {
        let video = LetterCorpus.bytes(120_000, seed: 7)
        let notes = LetterCorpus.bytes(1_234, seed: 8)
        let videoURL = try file("IMG_0005.MOV", video)
        let notesURL = try file("Notes.txt", notes)
        let server = ScriptedSubmission()
        try await Submission.send(
            draft, from: account, password: "app-password",
            through: SMTPClient(account: account, transport: { _, _ in server }),
            threadHeaders: nil,
            attachments: { [("IMG_0005.MOV", "video/quicktime", .disk(videoURL, attachedSize: nil)),
                            ("Notes.txt", "text/plain",
                             .disk(notesURL, attachedSize: Int64(notes.count)))] },
            htmlBody: markup, inlineImages: [LetterCorpus.logo], messageID: messageID,
            progress: nil, date: date, boundaryToken: Counting().next)

        let letters = await server.letters
        XCTAssertEqual((letters.first ?? Data()) + Data(".\r\n".utf8),
                       SMTPClient.dataPayload(reference([("IMG_0005.MOV", "video/quicktime", video),
                                                         ("Notes.txt", "text/plain", notes)])))
        func crc(_ data: Data) -> String {
            var crc = CRC32()
            crc.update(data)
            return CRC32.hex(crc.value)
        }
        XCTAssertEqual(lines.filter { $0.hasPrefix("LETTER-FILE") },
                       ["LETTER-FILE 1 bytes=\(video.count) crc=\(crc(video)) attached=- not checked",
                        "LETTER-FILE 2 bytes=\(notes.count) crc=\(crc(notes))"])
        try await lettingGo(server, outcome: "ok")
    }

    // MARK: - Read from the source

    /// The app's source, comment lines out and runs of white space as one.
    private func source(_ path: String) throws -> String {
        try String(contentsOf: sources.appendingPathComponent(path), encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    private var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail")
    }

    private func count(_ step: String, in code: String) -> Int {
        code.components(separatedBy: step).count - 1
    }

    /// Send reads no file whole: not in `Submission`, the share sheet, or
    /// the files, bytes and stream that make the letter; only a draft's
    /// APPEND does, in the repository. No file is given a protection
    /// stronger than class C anywhere, so a letter can be read while the
    /// iPad is locked; and every staged file is made class C, by `write`,
    /// `copy` and the share's `stage`.
    func testSendReadsNoFileWholeAndProtectsNothingBeyondClassC() throws {
        for path in ["SMTP/Submission.swift", "Share/ShareSheet.swift", "MIME/LetterFiles.swift",
                     "MIME/LetterBytes.swift", "SMTP/DataStream.swift"] {
            XCTAssertEqual(count("Data(contentsOf:", in: try source(path)), 0, path)
        }
        XCTAssertEqual(count("Data(contentsOf:", in: try source("Mail/IMAPMailRepository.swift")), 1,
                       "the draft's APPEND alone")

        let stronger = try NSRegularExpression(
            pattern: "(\\.complete|completeFileProtection|\\.completeUnlessOpen|completeFileProtectionUnlessOpen)(?![A-Za-z0-9_])")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 50)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let found = stronger.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            XCTAssertEqual(found, 0, file.lastPathComponent)
        }

        let store = try source("Mail/AttachmentStore.swift")
        for function in ["static func write(", "static func copy("] {
            let start = try XCTUnwrap(store.range(of: function))
            let end = store.range(of: "static func", range: start.upperBound..<store.endIndex)?.lowerBound
                ?? store.endIndex
            XCTAssertTrue(store[start.lowerBound..<end].contains("readableWhileLocked(url)"), function)
        }
        XCTAssertTrue(store.contains("[.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]"))
        let items = try source("Share/ShareItems.swift")
        let stage = try XCTUnwrap(items.range(of: "private func stage("))
        let after = items[stage.upperBound...]
        let body = after[..<(after.range(of: "return .file(")?.lowerBound ?? after.endIndex)]
        XCTAssertTrue(body.contains("AttachmentStore.readableWhileLocked(url)"))
    }
}

/// Progress reports, from any thread.
final class Heard: @unchecked Sendable {
    private let lock = NSLock()
    private var reports: [(written: Int, total: Int)] = []
    func add(_ written: Int, _ total: Int) { lock.lock(); reports.append((written, total)); lock.unlock() }
    var all: [(written: Int, total: Int)] { lock.lock(); defer { lock.unlock() }; return reports }
}
