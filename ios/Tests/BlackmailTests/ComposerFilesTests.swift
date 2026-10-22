import XCTest
@testable import Blackmail

/// Files and videos in the composer (B-108): Photo Library and Attach File
/// through the share sheet's own intake, a room that starts from the
/// letter's rows, the document picker's Inbox emptied, each load bounded at
/// three minutes, what could not be attached said, and a Send that never
/// goes without something he picked unless he has been told.
///
/// The intake (`ComposeIntake`) and the composer's actions
/// (`ComposeActions`) are the shipping ones, the loads the test's own: each
/// counts itself as `ShareItems.read` counts what it reads, and is answered
/// when the test says. The bound's clock is the test's too.
@MainActor
final class ComposerFilesTests: XCTestCase {

    private var log: [String] = []
    private var draws: [ComposeActions.Look] = []
    private var told: [String] = []
    /// The letter's rows, as the composer's `draft.attachments` holds them.
    private var rows: [DraftAttachment] = []
    private var sends = 0
    private var saves = 0
    private var background = FakeBackground()
    private var bound = FakeBound()
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        log = []
        draws = []
        told = []
        rows = []
        sends = 0
        saves = 0
        background = FakeBackground()
        bound = FakeBound()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ComposerFilesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        bound.cancelAll()
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeActions() -> ComposeActions {
        ComposeActions(
            sendLetter: { [unowned self] _, _ in
                sends += 1
                log.append("send with \(rows.map(\.filename))")
            },
            saveDraft: { [unowned self] draft in
                saves += 1
                log.append("save with \(draft.attachments.map(\.filename))")
            },
            deleteDraft: { _, _ in },
            dismiss: { [unowned self] in log.append("dismiss") },
            showError: { [unowned self] _ in log.append("error") },
            draw: { [unowned self] in draws.append($0) },
            background: background.time)
    }

    private func makeIntake(_ actions: ComposeActions) -> ComposeIntake {
        let bound = self.bound
        return ComposeIntake(
            actions: actions,
            rows: { [unowned self] in rows },
            landed: { [unowned self] _, row in
                rows.append(row)
                log.append("landed \(row.filename)")
            },
            changed: {},
            tell: { [unowned self] in
                told.append($0)
                log.append("told \($0)")
            },
            sleep: { try await bound.sleep($0) })
    }

    /// The letter as the composer hands it over: its rows now.
    private func letter() -> Draft {
        var draft = Draft()
        draft.to = ["carlo@example.org"]
        draft.subject = "Sunday"
        draft.attachments = rows
        return draft
    }

    private enum Kind { case picture, video, file }

    /// One thing picked whose load waits for the test: counted as
    /// `ShareItems.read` counts it as it begins, a picture or a video, and
    /// answered by `land` or `fail`.
    private final class Load {
        var staging: ShareItems.Staging?
        var tally: ShareItems.Tally?
        var done: ((SharedItem?) -> Void)?
        var begun: Bool { done != nil }
    }

    private func item(_ name: String, _ kind: Kind, _ load: Load) -> ComposeIntake.Item {
        ComposeIntake.Item(name: name) { staging, tally, done in
            switch kind {
            case .picture: tally.pictures += 1
            case .video: tally.videos += 1
            case .file: break
            }
            load.staging = staging
            load.tally = tally
            load.done = done
        }
    }

    /// The load answered with `bytes` staged as `name`, counted as
    /// attached as the share sheet counts it. Returns the staged file.
    @discardableResult
    private func land(_ load: Load, _ name: String, _ kind: Kind, bytes: Int = 100) -> URL? {
        let staged = load.staging?.photo(Data(repeating: 7, count: bytes), named: name,
                                         mimeType: kind == .video ? "video/quicktime" : "image/jpeg")
        if staged != nil {
            switch kind {
            case .picture: load.tally?.attached += 1
            case .video: load.tally?.videosAttached += 1
            case .file: break
            }
        }
        load.done?(staged)
        return ComposeIntake.file(staged)
    }

    private func fail(_ load: Load) {
        load.done?(nil)
    }

    /// Returns once everything already queued on the main actor has run.
    private func settled() async {
        for _ in 0..<5 { await Task { @MainActor in }.value }
    }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    private func file(_ name: String, bytes: Int, in folder: URL? = nil) throws -> URL {
        let folder = folder ?? directory!
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(repeating: 3, count: bytes).write(to: url)
        return url
    }

    private func row(_ name: String, size: Int64?) -> DraftAttachment {
        DraftAttachment(source: .messagePart(messageID: "INBOX/1/7", mailboxID: "INBOX",
                                             section: "2"),
                        filename: name, mimeType: "application/pdf", size: size)
    }

    // MARK: - The room

    /// What the letter's rows leave of the 25 MB: all of it with none, less
    /// each row's weight, nothing once they weigh more, and nothing at all
    /// with a row whose weight is not known, a forward's part with no size.
    func testTheRoomIsWhatTheLettersRowsLeave() {
        let budget = ShareItems.Staging.budget
        XCTAssertEqual(budget, 25_000_000)
        XCTAssertEqual(ShareItems.Staging.room(after: []), budget)
        XCTAssertEqual(ShareItems.Staging.room(after: [row("a.pdf", size: 4_000_000),
                                                       row("b.pdf", size: 1_000_000)]),
                       20_000_000)
        XCTAssertEqual(ShareItems.Staging.room(after: [row("a.pdf", size: 30_000_000)]), 0)
        XCTAssertEqual(ShareItems.Staging.room(after: [row("a.pdf", size: 1_000),
                                                       row("b.pdf", size: nil)]), 0)
        XCTAssertEqual(ShareItems.Staging.room(after: [row("a.pdf", size: -5)]), budget)
    }

    /// A staging that begins below the whole: a file that fits is copied
    /// and counted, one that does not is not even copied, and a room of
    /// nothing, a forward's unknown row, takes nothing at all, a photo's
    /// bytes or a file written straight onto the disk either. A share's
    /// staging still begins with all of it.
    func testAStagingBeginsWithTheRoomItIsGiven() throws {
        var copies = 0
        func staging(_ room: Int64) -> ShareItems.Staging {
            ShareItems.Staging(room: room, copy: { source, name in
                copies += 1
                return try AttachmentStore.copy(source, named: name)
            })
        }
        let small = try file("Notes.pdf", bytes: 3_000)
        let large = try file("Plans.pdf", bytes: 6_000)

        let some = staging(5_000)
        XCTAssertEqual(some.limit, 5_000)
        let fits = try XCTUnwrap(some.file(at: small, size: 3_000, named: "Notes.pdf",
                                           mimeType: "application/pdf"))
        XCTAssertEqual(some.room, 2_000)
        XCTAssertNil(some.file(at: large, size: 6_000, named: "Plans.pdf",
                               mimeType: "application/pdf"))
        XCTAssertEqual(copies, 1, "not copied without the room for it")
        XCTAssertEqual(some.room, 2_000)
        if let url = ComposeIntake.file(fits) { AttachmentStore.removeStaged(url) }

        let none = staging(ShareItems.Staging.room(after: [row("Forwarded.pdf", size: nil)]))
        XCTAssertEqual(none.room, 0)
        XCTAssertNil(none.file(at: small, size: 3_000, named: "Notes.pdf", mimeType: "application/pdf"))
        XCTAssertNil(none.photo(Data([1]), named: "IMG_0001.jpg"))
        XCTAssertNil(none.written(named: "IMG_0002.JPG", mimeType: "image/jpeg", expected: 1) { _ in
            XCTFail("nothing written without room")
            return true
        })
        XCTAssertEqual(copies, 1)

        XCTAssertEqual(staging(90_000_000).limit, ShareItems.Staging.budget, "never more than 25 MB")
        XCTAssertEqual(staging(-1).limit, 0)
        XCTAssertEqual(ShareItems.Staging().room, ShareItems.Staging.budget)
        XCTAssertEqual(ShareItems.Staging().unnamed, 0)
        XCTAssertEqual(ShareItems.Staging(unnamed: 2).unnamed, 2)
    }

    // MARK: - The document picker's Inbox

    /// A file moved, not copied: into a directory of its own in the staging,
    /// where `removeStaged` finds it, under its name made safe, and gone
    /// from where it was.
    func testMoveTakesTheFileOutOfTheInboxIntoADirectoryOfItsOwn() throws {
        let inbox = directory.appendingPathComponent("org.example.blackmail-Inbox")
        let source = try file("Re:port.pdf", bytes: 2_000, in: inbox)
        let moved = try AttachmentStore.move(source, named: "../Re:port.pdf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path), "moved, not copied")
        XCTAssertEqual(moved.lastPathComponent, "Report.pdf")
        XCTAssertEqual(try Data(contentsOf: moved), Data(repeating: 3, count: 2_000))
        let folder = try XCTUnwrap(AttachmentStore.stagingDirectory(of: moved))
        XCTAssertNotNil(UUID(uuidString: folder.lastPathComponent))
        XCTAssertEqual(folder.deletingLastPathComponent().standardizedFileURL.path,
                       AttachmentStore.root.standardizedFileURL.path)
        AttachmentStore.removeStaged(moved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))

        // A move that fails leaves no directory behind it.
        let before = (try? FileManager.default.contentsOfDirectory(atPath: AttachmentStore.root.path)) ?? []
        XCTAssertThrowsError(try AttachmentStore.move(inbox.appendingPathComponent("gone.pdf"),
                                                      named: "gone.pdf"))
        let after = (try? FileManager.default.contentsOfDirectory(atPath: AttachmentStore.root.path)) ?? []
        XCTAssertEqual(Set(after), Set(before))
    }

    /// The Inbox is `<bundle id>-Inbox` in the temporary directory, as iOS
    /// names the document picker's; only what is in it is moved or
    /// removed, and nothing outside it, however the path is written.
    func testOnlyWhatIsInTheInboxIsMovedOrRemoved() throws {
        let tmp = directory!
        let inbox = try XCTUnwrap(AttachmentStore.inbox(in: tmp, bundle: "org.example.blackmail"))
        XCTAssertEqual(inbox.lastPathComponent, "org.example.blackmail-Inbox")
        XCTAssertEqual(inbox.deletingLastPathComponent().standardizedFileURL.path,
                       tmp.standardizedFileURL.path)
        XCTAssertNil(AttachmentStore.inbox(in: tmp, bundle: nil))
        XCTAssertNil(AttachmentStore.inbox(in: tmp, bundle: ""))
        XCTAssertNil(AttachmentStore.inbox(in: tmp, bundle: "a/b"))

        let inside = try file("Plans.pdf", bytes: 10, in: inbox)
        let deeper = try file("Notes.pdf", bytes: 10, in: inbox.appendingPathComponent("1"))
        let outside = try file("Plans.pdf", bytes: 10, in: tmp.appendingPathComponent("Elsewhere"))
        let sneaking = URL(fileURLWithPath: inbox.path + "/../Elsewhere/Plans.pdf")
        let neighbour = try file("Plans.pdf", bytes: 10,
                                 in: tmp.appendingPathComponent("org.example.blackmail-Inbox2"))
        XCTAssertTrue(AttachmentStore.isInInbox(inside, inbox: inbox))
        XCTAssertTrue(AttachmentStore.isInInbox(deeper, inbox: inbox))
        XCTAssertFalse(AttachmentStore.isInInbox(outside, inbox: inbox))
        XCTAssertFalse(AttachmentStore.isInInbox(sneaking, inbox: inbox))
        XCTAssertFalse(AttachmentStore.isInInbox(neighbour, inbox: inbox))
        XCTAssertFalse(AttachmentStore.isInInbox(inbox, inbox: inbox), "the Inbox itself")
        XCTAssertFalse(AttachmentStore.isInInbox(inside, inbox: nil))

        for url in [outside, sneaking, neighbour] {
            AttachmentStore.removeFromInbox(url, inbox: inbox)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: neighbour.path))
        AttachmentStore.removeFromInbox(inside, inbox: inbox)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inside.path))
    }

    /// The purge at launch takes the Inbox with the staging: a file picked
    /// and not moved out, the app ended between, does not stay for years.
    func testThePurgeAtLaunchClearsTheInboxToo() throws {
        let inbox = try XCTUnwrap(AttachmentStore.inbox(in: directory, bundle: "org.example.blackmail"))
        let left = try file("Plans.pdf", bytes: 10, in: inbox)
        let staged = try AttachmentStore.write(Data([1, 2, 3]), named: "IMG_0001.jpg")
        let beside = try file("Kept.txt", bytes: 10)
        AttachmentStore.purge(inbox: inbox)
        XCTAssertFalse(FileManager.default.fileExists(atPath: left.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: beside.path), "nothing else in tmp")
    }

    /// A file's type from its name's extension as the iPad's types know it,
    /// and `application/octet-stream` when there is none or it is not known.
    func testTheMIMETypeComesFromTheExtension() {
        var asked: [String] = []
        let known = ["pdf": "application/pdf", "PDF": "application/pdf",
                     "m4a": "audio/mp4", "docx": "application/vnd.openxmlformats-"
                        + "officedocument.wordprocessingml.document"]
        let lookup: (String) -> String? = { asked.append($0); return known[$0] }
        XCTAssertEqual(AttachmentStore.mimeType(of: "Plans.pdf", lookup: lookup), "application/pdf")
        XCTAssertEqual(AttachmentStore.mimeType(of: "SCAN.PDF", lookup: lookup), "application/pdf")
        XCTAssertEqual(AttachmentStore.mimeType(of: "Voice memo.m4a", lookup: lookup), "audio/mp4")
        XCTAssertEqual(AttachmentStore.mimeType(of: "Letter.v2.docx", lookup: lookup),
                       known["docx"])
        XCTAssertEqual(asked, ["pdf", "PDF", "m4a", "docx"])
        for name in ["README", "notes.", ".profile", "photo.xyz", ""] {
            XCTAssertEqual(AttachmentStore.mimeType(of: name, lookup: lookup),
                           "application/octet-stream", name)
        }
        XCTAssertEqual(AttachmentStore.mimeType(of: "a.pdf", lookup: { _ in "" }),
                       "application/octet-stream")
    }

    // MARK: - One at a time, each with the room left

    /// A pick read one thing at a time, in his order, each counted in the
    /// actions from the pick and given the room the rows before it leave;
    /// a second pick after the first, never beside it.
    func testPicksAreReadOneAtATimeEachWithTheRoomLeft() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        rows = [row("Forwarded.pdf", size: 5_000_000)]
        let first = Load(), second = Load(), third = Load()
        intake.take([item("IMG_0001", .picture, first), item("IMG_0002", .video, second)])
        intake.take([item("Plans", .picture, third)])
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0001", "IMG_0002", "Plans"])
        XCTAssertTrue(actions.asksAnyway, "counted from the pick")
        XCTAssertTrue(first.begun)
        XCTAssertFalse(second.begun)
        XCTAssertFalse(third.begun)
        XCTAssertEqual(first.staging?.room, 20_000_000)

        land(first, "IMG_0001.JPG", .picture, bytes: 4_000_000)
        try await until { second.begun }
        XCTAssertEqual(second.staging?.room, 16_000_000, "with the first one's row in")
        XCTAssertFalse(third.begun)
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0002", "Plans"])
        land(second, "IMG_0002.MOV", .video, bytes: 1_000)
        try await until { third.begun }
        land(third, "Plans.jpg", .picture)
        try await until { intake.coming.isEmpty }
        XCTAssertEqual(rows.map(\.filename), ["Forwarded.pdf", "IMG_0001.JPG", "IMG_0002.MOV",
                                              "Plans.jpg"])
        XCTAssertFalse(actions.asksAnyway)
        XCTAssertEqual(told, [], "everything came")
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// What could not be attached, said once, as its pick ends, in the
    /// share sheet's words: one photo of three, and a pick of one.
    func testWhatCouldNotBeAttachedIsSaidOnceAsItsPickEnds() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let loads = [Load(), Load(), Load()]
        intake.take(loads.enumerated().map { item("IMG_000\($0.offset)", .picture, $0.element) })
        land(loads[0], "IMG_0000.JPG", .picture)
        try await until { loads[1].begun }
        fail(loads[1])
        try await until { loads[2].begun }
        XCTAssertEqual(told, [], "not until the pick ends")
        land(loads[2], "IMG_0002.JPG", .picture)
        try await until { !told.isEmpty }
        XCTAssertEqual(told, ["1 photo could not be attached."])

        let alone = Load()
        intake.take([item("IMG_0009", .video, alone)])
        try await until { alone.begun }
        fail(alone)
        try await until { told.count == 2 }
        XCTAssertEqual(told.last, "The video could not be attached.")
        XCTAssertEqual(rows.count, 2)
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    // MARK: - Bounded at three minutes

    /// A load that never returns: given three minutes from when it begins,
    /// then counted out, its row gone, said, and the next begun. Come after
    /// all, it is thrown away and its file removed.
    func testALoadThatNeverReturnsIsCountedOutAtThreeMinutes() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let stuck = Load(), next = Load()
        intake.take([item("IMG_0101", .picture, stuck), item("IMG_0102", .picture, next)])
        try await until { bound.waiting == 1 }
        XCTAssertEqual(bound.asked, [.seconds(180)])
        XCTAssertEqual(ComposeIntake.bound, .seconds(180))
        XCTAssertFalse(next.begun, "its bound runs while it is the one being read")

        bound.pass()
        try await until { next.begun }
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0102"])
        try await until { bound.waiting == 1 }
        XCTAssertEqual(bound.asked, [.seconds(180), .seconds(180)], "the next has its own")
        land(next, "IMG_0102.JPG", .picture)
        try await until { intake.coming.isEmpty }
        XCTAssertEqual(told, ["1 photo could not be attached."])
        XCTAssertFalse(actions.asksAnyway)
        // The bound of one that came is let go.
        try await until { bound.waiting == 0 }

        let late = try XCTUnwrap(land(stuck, "IMG_0101.JPG", .picture))
        await settled()
        XCTAssertFalse(FileManager.default.fileExists(atPath: late.path), "thrown away")
        XCTAssertEqual(rows.map(\.filename), ["IMG_0102.JPG"])
        XCTAssertEqual(told.count, 1)
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    // MARK: - Send and Save Draft

    /// Send tapped while a load is coming: the spinner, nothing sent, and
    /// once it lands, the letter goes with it.
    func testSendWaitsForALoadAndGoesWithIt() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let video = Load()
        intake.take([item("IMG_0201", .video, video)])
        let sending = try XCTUnwrap(actions.send({ [unowned self] in letter() }, then: nil))
        await settled()
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(draws, [.sending("Sending…")])
        land(video, "IMG_0201.MOV", .video)
        await sending.value
        XCTAssertEqual(log, ["landed IMG_0201.MOV", "send with [\"IMG_0201.MOV\"]", "dismiss"])
        XCTAssertEqual(told, [])
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// Send tapped while a load is coming, and the load counted out while
    /// it waits: nothing sent, the sheet put back as it was with the row
    /// that did land, and the words said. His second Send goes without the
    /// one counted out, because he chose to.
    func testSendDoesNotGoWhenALoadIsCountedOutWhileItWaits() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let photo = Load(), video = Load()
        intake.take([item("IMG_0301", .picture, photo), item("IMG_0302", .video, video)])
        land(photo, "IMG_0301.JPG", .picture)
        try await until { video.begun }
        let sending = try XCTUnwrap(actions.send({ [unowned self] in letter() }, then: nil))
        await settled()
        try await until { bound.waiting == 1 }
        bound.pass()
        await sending.value
        XCTAssertEqual(sends, 0, "sendLetter never called")
        XCTAssertEqual(draws, [.sending("Sending…"), .writing])
        XCTAssertEqual(told, ["1 video could not be attached."])
        XCTAssertEqual(rows.map(\.filename), ["IMG_0301.JPG"], "the row that landed stays")
        XCTAssertTrue(actions.isWriting)
        XCTAssertFalse(log.contains("dismiss"))
        XCTAssertEqual(background.ended, [1], "its time given back")

        await actions.send({ [unowned self] in letter() }, then: nil)?.value
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(log.last(where: { $0.hasPrefix("send") }), "send with [\"IMG_0301.JPG\"]")
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// The same for a load that fails while Send waits, which the spec
    /// left to go: the letter would have gone without it, and the words
    /// over a sheet closing.
    func testSendDoesNotGoWhenALoadFailsWhileItWaits() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let file = Load()
        intake.take([item("Plans.pdf", .file, file)])
        let sending = try XCTUnwrap(actions.send({ [unowned self] in letter() }, then: nil))
        await settled()
        fail(file)
        await sending.value
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(draws, [.sending("Sending…"), .writing])
        XCTAssertEqual(told, ["The file could not be attached."])
    }

    /// Something that failed before the tap, its pick ended and said, does
    /// not hold a later Send: he was told, and sends without it. One that
    /// failed before the tap in a pick still coming is said only as the
    /// pick ends, during the wait, and that Send does not go.
    func testSendGoesWithoutWhatHeWasToldOfBefore() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let alone = Load()
        intake.take([item("IMG_0401", .picture, alone)])
        fail(alone)
        try await until { told.count == 1 }
        await actions.send({ [unowned self] in letter() }, then: nil)?.value
        XCTAssertEqual(sends, 1)

        log = []
        draws = []
        sends = 0
        let other = makeActions()
        let more = makeIntake(other)
        let failed = Load(), coming = Load()
        more.take([item("IMG_0402", .picture, failed), item("IMG_0403", .picture, coming)])
        fail(failed)
        try await until { coming.begun }
        let sending = try XCTUnwrap(other.send({ [unowned self] in letter() }, then: nil))
        await settled()
        land(coming, "IMG_0403.JPG", .picture)
        await sending.value
        XCTAssertEqual(sends, 0, "he had not been told before the tap")
        XCTAssertEqual(told.last, "1 photo could not be attached.")
        XCTAssertEqual(draws, [.sending("Sending…"), .writing])
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// Save Draft while a load is coming that is counted out: the sheet
    /// has gone, the draft is kept without it, and nothing is sent.
    func testSaveDraftWithALoadCountedOutKeepsTheDraftWithoutIt() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let photo = Load(), stuck = Load()
        intake.take([item("IMG_0501", .picture, photo), item("IMG_0502", .picture, stuck)])
        land(photo, "IMG_0501.JPG", .picture)
        try await until { stuck.begun }
        let saving = try XCTUnwrap(actions.saveAndClose({ [unowned self] in letter() }, then: nil))
        await settled()
        XCTAssertEqual(saves, 0, "waiting for it")
        try await until { bound.waiting == 1 }
        bound.pass()
        await saving.value
        XCTAssertEqual(log.filter { $0.hasPrefix("save") }, ["save with [\"IMG_0501.JPG\"]"])
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(log.first(where: { $0 == "dismiss" }), "dismiss")
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    // MARK: - Attach File

    /// A file from Attach File: moved out of the Inbox into the staging,
    /// under its own name made safe, its type from its extension, its row
    /// what the disk measured. One too large for the room left is not
    /// moved, is removed from the Inbox, and is said.
    func testAFileFromAttachFileIsMovedNamedAndTypedOrLeftOutAndRemoved() async throws {
        let inbox = try XCTUnwrap(AttachmentStore.inbox(in: directory, bundle: "org.example.blackmail"))
        let pdf = try file("Plans: May.pdf", bytes: 4_000, in: inbox)
        let video = try file("Garden.mov", bytes: 9_000, in: inbox)
        let elsewhere = try file("Notes.txt", bytes: 2_000)
        let types = ["pdf": "application/pdf", "txt": "text/plain"]
        let actions = makeActions()
        let intake = makeIntake(actions)
        rows = [row("Forwarded.pdf", size: ShareItems.Staging.budget - 5_000)]
        let items = [pdf, video, elsewhere].map {
            ComposeIntake.file(at: $0, inbox: inbox, mimeType: { types[$0] })
        }
        XCTAssertEqual(items.map(\.name), ["Plans May.pdf", "Garden.mov", "Notes.txt"])
        XCTAssertEqual(items.map(\.moves), [true, true, false])
        intake.take(items)
        try await until { intake.coming.isEmpty }

        XCTAssertEqual(rows.dropFirst().map(\.filename), ["Plans May.pdf"])
        XCTAssertEqual(rows.last?.mimeType, "application/pdf")
        XCTAssertEqual(rows.last?.size, 4_000)
        guard case .localFile(let moved)? = rows.last?.source else { return XCTFail("a file") }
        XCTAssertNotNil(AttachmentStore.stagingDirectory(of: moved))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pdf.path), "moved out of the Inbox")
        XCTAssertFalse(FileManager.default.fileExists(atPath: video.path), "and the one left out removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: elsewhere.path), "nothing outside it")
        XCTAssertEqual(told, ["2 files could not be attached."])
        AttachmentStore.removeStaged(moved)

        // A folder is no file.
        rows = []
        let folder = inbox.appendingPathComponent("Folder.pdf", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        intake.take([ComposeIntake.file(at: folder, inbox: inbox, mimeType: { types[$0] })])
        try await until { told.count == 2 }
        XCTAssertEqual(told.last, "The file could not be attached.")
        XCTAssertEqual(rows, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    /// Pictures with no name are numbered on from pick to pick, as Mail
    /// numbers them in a letter.
    func testUnnamedPicturesAreNumberedOnFromPickToPick() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let first = Load(), second = Load()
        intake.take([item("", .picture, first)])
        XCTAssertEqual(first.staging?.unnamed, 0)
        let staged = first.staging?.photo(Data([9]), named: "image0.jpeg", unnamed: true)
        first.tally?.attached += 1
        first.done?(staged)
        try await until { intake.coming.isEmpty }
        intake.take([item("", .picture, second)])
        XCTAssertEqual(second.staging?.unnamed, 1)
        fail(second)
        try await until { told.count == 1 }
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    // MARK: - A name with a quote or a backslash

    /// A file named with `"` or `\` in it, which inside the quoted
    /// `name=` and `filename=` would end the string early: the builder has
    /// left both out of the name since its first version, for a file and a
    /// picture sent inline alike (`RFC5322Builder.plan`), so the header is
    /// well formed. Pinned: each such header holds one quoted name and
    /// nothing after it, and the app's own parser reads the name back as
    /// it went, whatever else is in it.
    func testANameWithAQuoteOrABackslashGoesWellFormed() throws {
        let account = MailAccount(address: "owner@example.com", username: "owner@example.com",
                                  displayName: "Sam")
        var draft = Draft()
        draft.to = ["carlo@example.org"]
        draft.body = "Attached."
        let files: [(sent: String, goes: String)] = [
            ("re\"port.pdf", "report.pdf"), ("back\\slash.pdf", "backslash.pdf"),
            ("\"\\\".pdf", ".pdf"), ("Caf\u{E9} \"menu\".pdf", "Caf\u{E9} menu.pdf"),
            ("\"\"", "attachment"),
        ]
        let raw = RFC5322Builder.build(
            draft: draft, from: account,
            attachments: files.map { ($0.sent, "application/pdf", Data([1, 2, 3])) },
            htmlBody: "<p>Attached.</p><img src=\"cid:logo@example\">",
            inlineImages: [(contentID: "logo@example", filename: "lo\"go\\.png",
                            mimeType: "image/png", data: Data([4, 5, 6]))])
        let text = String(decoding: raw, as: UTF8.self)

        // Each header line naming a file, unfolded: `name="…"` or
        // `filename="…"` once, its quotes the only two, nothing after them.
        let unfolded = text.replacingOccurrences(of: "\r\n ", with: " ")
            .components(separatedBy: "\r\n")
        let named = unfolded.filter { $0.contains("name=\"") }
        XCTAssertEqual(named.count, 2 * (files.count + 1), "a type and a disposition each")
        for line in named {
            XCTAssertEqual(line.filter { $0 == "\"" }.count, 2, line)
            XCTAssertFalse(line.contains("\\"), line)
            XCTAssertTrue(line.hasSuffix("\""), line)
        }

        // The app's parser: every part's name, from its type and its
        // disposition both, as it went.
        var leaves: [MIMEPart] = []
        func walk(_ part: MIMEPart) {
            if part.isMultipart { part.children.forEach(walk) } else { leaves.append(part) }
        }
        walk(MIMEDecoder.parse(raw).structure)
        let parts = leaves.filter { $0.filename != nil }
        XCTAssertEqual(parts.map { $0.parameters["name"].map(MIMEDecoder.decodeWord) },
                       ["logo.png"] + files.map(\.goes))
        XCTAssertEqual(parts.map { $0.dispositionParameters["filename"].map(MIMEDecoder.decodeWord) },
                       ["logo.png"] + files.map(\.goes))
        XCTAssertEqual(parts.map(\.disposition), ["inline"] + files.map { _ in "attachment" })
        XCTAssertEqual(MIMEDecoder.decodeMessage(raw).attachments.map(\.filename),
                       ["logo.png"] + files.map(\.goes))
    }

    // MARK: - The words

    /// Every combination: the share sheet's own words for photos and
    /// videos, the owner's for files, and a list for a mix.
    func testTheWordsForEveryCombination() {
        func words(_ p: Int, _ a: Int, _ v: Int, _ va: Int, _ f: Int = 0, _ fa: Int = 0) -> String? {
            ComposeIntake.words(pictures: p, attached: a, videos: v, videosAttached: va,
                                files: f, filesAttached: fa)
        }
        XCTAssertNil(words(0, 0, 0, 0))
        XCTAssertNil(words(3, 3, 2, 2, 1, 1))
        XCTAssertEqual(words(1, 0, 0, 0), "The photo could not be attached.")
        XCTAssertEqual(words(3, 0, 0, 0), "The photos could not be attached.")
        XCTAssertEqual(words(0, 0, 1, 0), "The video could not be attached.")
        XCTAssertEqual(words(0, 0, 2, 0), "The videos could not be attached.")
        XCTAssertEqual(words(1, 0, 1, 0), "The photo and the video could not be attached.")
        XCTAssertEqual(words(1, 0, 2, 0), "The photo and the videos could not be attached.")
        XCTAssertEqual(words(2, 0, 1, 0), "The photos and the video could not be attached.")
        XCTAssertEqual(words(2, 0, 2, 0), "The photos and videos could not be attached.")
        XCTAssertEqual(words(3, 2, 0, 0), "1 photo could not be attached.")
        XCTAssertEqual(words(4, 1, 0, 0), "3 photos could not be attached.")
        XCTAssertEqual(words(2, 2, 2, 1), "1 video could not be attached.")
        XCTAssertEqual(words(3, 1, 3, 1), "2 photos and 2 videos could not be attached.")
        XCTAssertEqual(words(1, 0, 1, 1), "1 photo could not be attached.")
        XCTAssertEqual(words(1, 0, 0, 0, 1, 1), "1 photo could not be attached.",
                       "a file came, so not 'The photo'")
        XCTAssertEqual(words(0, 0, 0, 0, 1, 0), "The file could not be attached.")
        XCTAssertEqual(words(0, 0, 0, 0, 2, 0), "2 files could not be attached.")
        XCTAssertEqual(words(0, 0, 0, 0, 3, 2), "1 file could not be attached.")
        XCTAssertEqual(words(0, 0, 0, 0, 5, 1), "4 files could not be attached.")
        XCTAssertEqual(words(1, 1, 0, 0, 1, 0), "1 file could not be attached.")
        XCTAssertEqual(words(0, 0, 1, 1, 2, 0), "2 files could not be attached.")
        XCTAssertEqual(words(1, 0, 0, 0, 1, 0), "1 photo and 1 file could not be attached.")
        XCTAssertEqual(words(0, 0, 2, 0, 3, 0), "2 videos and 3 files could not be attached.")
        XCTAssertEqual(words(2, 1, 1, 0, 1, 0), "1 photo, 1 video and 1 file could not be attached.")
    }
}

/// The bound's clock as a test moves it: each wait is parked until the
/// test says the time has passed, and one cancelled ends at once.
@MainActor
final class FakeBound {
    private(set) var asked: [Duration] = []
    private var parked: [Int: CheckedContinuation<Void, Error>] = [:]
    private var next = 0

    nonisolated init() {}

    var waiting: Int { parked.count }

    func sleep(_ duration: Duration) async throws {
        asked.append(duration)
        next += 1
        let id = next
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { parked[id] = $0 }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    /// Every bound waiting has passed.
    func pass() {
        let all = parked
        parked = [:]
        for continuation in all.values { continuation.resume() }
    }

    func cancelAll() {
        let all = parked
        parked = [:]
        for continuation in all.values { continuation.resume(throwing: CancellationError()) }
    }

    private func cancel(_ id: Int) {
        parked.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}
