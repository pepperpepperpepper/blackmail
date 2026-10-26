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
    /// Each alert's title, beside its words in `told`: Mail's "Unable to
    /// Attach" over a file's (B-144), none over the share sheet's.
    private var titles: [String?] = []
    /// The letter's rows, as the composer's `draft.attachments` holds them.
    private var rows: [DraftAttachment] = []
    private var sends = 0
    private var saves = 0
    /// The letters kept on the iPad while he writes, by their rows' names.
    private var keeps: [[String]] = []
    private var background = FakeBackground()
    private var bound = FakeBound()
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        log = []
        draws = []
        told = []
        titles = []
        rows = []
        sends = 0
        saves = 0
        keeps = []
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
            background: background.time,
            keeping: DraftKeeping(
                keep: { [unowned self] draft, finished in
                    if !finished { keeps.append(draft.attachments.map(\.filename)) }
                },
                forget: {}, abandon: {}, letGo: {}))
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
                told.append($0.message)
                titles.append($0.title)
                log.append("told \($0.message)")
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

    private typealias Kind = ComposeIntake.Kind

    /// One thing picked whose load waits for the test: counted as
    /// `ShareItems.read` counts it as it begins, a picture or a video, and
    /// answered by `land` or `fail`. `cancellable`, as Photo Library's
    /// reads are, it hands back a `ShareItems.Loading` for each read, which
    /// `away` calls off (B-142); not, as Attach File's, it hands back none.
    /// Begun again, `done`, `staging` and `tally` are the latest read's.
    private final class Load {
        let cancellable: Bool
        var staging: ShareItems.Staging?
        var tally: ShareItems.Tally?
        var done: ((SharedItem?) -> Void)?
        /// Each read's own, in the order begun.
        var loadings: [ShareItems.Loading] = []
        var begins = 0
        var begun: Bool { done != nil }
        init(cancellable: Bool = false) { self.cancellable = cancellable }
        /// Whether read `n`, from 0, has been called off; nil when it was
        /// never begun.
        func calledOff(_ n: Int) -> Bool? {
            loadings.indices.contains(n) ? loadings[n].isCancelled : nil
        }
    }

    private func item(_ name: String, _ kind: Kind, _ load: Load) -> ComposeIntake.Item {
        ComposeIntake.Item(name: name, kind: kind) { staging, tally, done in
            switch kind {
            case .picture: tally.pictures += 1
            case .video: tally.videos += 1
            case .file: break
            }
            load.staging = staging
            load.tally = tally
            load.done = done
            load.begins += 1
            guard load.cancellable else { return nil }
            let loading = ShareItems.Loading()
            load.loadings.append(loading)
            return loading
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

    private final class Flag {
        var on = false
    }

    /// Whether `task` ends, given a second or so: a test whose wait has no
    /// end fails, rather than hanging the suite.
    private func ends(_ task: Task<Void, Never>, file: StaticString = #filePath,
                      line: UInt = #line) async throws -> Bool {
        let over = Flag()
        Task { @MainActor in
            await task.value
            over.on = true
        }
        try await until(file: file, line: line) { over.on }
        return over.on
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
    /// that did land meanwhile, and the words said. The letter is kept on
    /// the iPad at the tap, as it stands (B-142), and again as it is then,
    /// that row and all, and counts as changed, so leaving the app keeps
    /// it again. His second Send goes without the one counted out, because
    /// he chose to.
    func testSendDoesNotGoWhenALoadIsCountedOutWhileItWaits() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let photo = Load(), video = Load()
        intake.take([item("IMG_0301", .picture, photo), item("IMG_0302", .video, video)])
        let sending = try XCTUnwrap(actions.send({ [unowned self] in letter() }, then: nil))
        await settled()
        land(photo, "IMG_0301.JPG", .picture)
        try await until { video.begun }
        // The video's own bound, and the wait's.
        try await until { bound.waiting == 2 }
        bound.pass()
        await sending.value
        XCTAssertEqual(sends, 0, "sendLetter never called")
        XCTAssertEqual(draws, [.sending("Sending…"), .writing])
        XCTAssertEqual(told, ["1 video could not be attached."])
        XCTAssertEqual(rows.map(\.filename), ["IMG_0301.JPG"], "the row that landed stays")
        XCTAssertTrue(actions.isWriting)
        XCTAssertFalse(log.contains("dismiss"))
        XCTAssertEqual(background.ended, [1], "its time given back")
        XCTAssertEqual(keeps, [[], ["IMG_0301.JPG"]],
                       "kept at the tap, and as it is now, with the row from the wait")
        XCTAssertNil(actions.putAside { [unowned self] in letter() })
        XCTAssertEqual(keeps.count, 3, "changed, so kept again as he leaves the app")

        await actions.send({ [unowned self] in letter() }, then: nil)?.value
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(log.last(where: { $0.hasPrefix("send") }), "send with [\"IMG_0301.JPG\"]")
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// Send's wait as a whole is bounded from the tap, not each thing one
    /// after another. Three photos and a file, none of which ever comes,
    /// in two picks; Send 100 s after them. The first is counted out at
    /// its own bound, 180 s after it began, nothing said yet, its pick not
    /// ended; the second begins with its own. At the tap's bound, 280 s,
    /// the second, the third and the file, which never began, are counted
    /// out at once, by what each is, and said in one alert. Nothing is
    /// sent, and the sheet is his again. One after another, it was 720 s.
    func testSendWaitsOneBoundFromTheTapForEverythingStillComing() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let loads = [Load(), Load(), Load()], plans = Load()
        intake.take(loads.enumerated().map { item("IMG_070\($0.offset)", .picture, $0.element) })
        intake.take([item("Plans.pdf", .file, plans)])
        try await until { bound.waiting == 1 }
        bound.advance(by: .seconds(100))
        let sending = try XCTUnwrap(actions.send({ [unowned self] in letter() }, then: nil))
        try await until { bound.waiting == 2 }

        bound.advance(by: .seconds(80))
        try await until { loads[1].begun }
        try await until { bound.waiting == 2 }
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0701", "IMG_0702", "Plans.pdf"])
        XCTAssertEqual(told, [], "its pick not ended")
        XCTAssertEqual(draws, [.sending("Sending…")])
        XCTAssertTrue(actions.isSending)

        bound.advance(by: .seconds(99))
        await settled()
        XCTAssertEqual(intake.coming.count, 3, "not before the tap's bound")
        bound.advance(by: .seconds(1))
        guard try await ends(sending) else { return }
        XCTAssertFalse(loads[2].begun, "the third never began")
        XCTAssertFalse(plans.begun)
        XCTAssertEqual(intake.coming, [])
        XCTAssertEqual(told, ["One or more attachments failed to load."], "one alert")
        XCTAssertEqual(titles, ["Unable to Attach"], "Mail's, a file among them (B-144)")
        XCTAssertEqual(sends, 0, "sendLetter never called")
        XCTAssertEqual(draws, [.sending("Sending…"), .writing])
        XCTAssertTrue(actions.isWriting)
        XCTAssertFalse(actions.asksAnyway)
        XCTAssertEqual(background.ended, [1])
        try await until { bound.waiting == 0 }

        // Come after all, each is thrown away.
        let late = try XCTUnwrap(land(loads[1], "IMG_0701.JPG", .picture))
        await settled()
        XCTAssertFalse(FileManager.default.fileExists(atPath: late.path))
        XCTAssertEqual(rows, [])
        XCTAssertEqual(told.count, 1)
    }

    /// Save Draft's wait is bounded from the tap as Send's is: two photos
    /// that never come, Save Draft 50 s after them; both are counted out
    /// by 230 s, and the draft is kept without them.
    func testSaveDraftWaitsOneBoundFromTheTap() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let first = Load(), second = Load()
        intake.take([item("IMG_0801", .picture, first), item("IMG_0802", .picture, second)])
        try await until { bound.waiting == 1 }
        bound.advance(by: .seconds(50))
        let saving = try XCTUnwrap(actions.saveAndClose({ [unowned self] in letter() }, then: nil))
        try await until { bound.waiting == 2 }
        bound.advance(by: .seconds(130))
        try await until { second.begun }
        XCTAssertEqual(saves, 0)
        bound.advance(by: .seconds(50))
        guard try await ends(saving) else { return }
        XCTAssertEqual(log.filter { $0.hasPrefix("save") }, ["save with []"])
        XCTAssertEqual(told, ["The photos could not be attached."])
        XCTAssertEqual(sends, 0)
    }

    /// No bound runs while the app is away: a read that cannot be called
    /// off (B-142), as a file Attach File handed over, and takes longer
    /// than three minutes while he is in another app is in the letter when
    /// he comes back, not counted out. Back, each has its bound again from
    /// then, and so does a Send that was waiting.
    func testTheBoundDoesNotRunWhileTheAppIsAway() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let video = Load()
        intake.take([item("IMG_0901", .video, video)])
        try await until { bound.waiting == 1 }
        intake.away()
        try await until { bound.waiting == 0 }
        bound.advance(by: .seconds(600))
        await settled()
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0901"], "not counted out")
        land(video, "IMG_0901.MOV", .video)
        try await until { intake.coming.isEmpty }
        intake.back()
        XCTAssertEqual(rows.map(\.filename), ["IMG_0901.MOV"])
        XCTAssertEqual(told, [])
        XCTAssertEqual(bound.asked, [.seconds(180)])

        let photo = Load()
        intake.take([item("IMG_0902", .picture, photo)])
        let sending = try XCTUnwrap(actions.send({ [unowned self] in letter() }, then: nil))
        try await until { bound.waiting == 2 }
        intake.away()
        try await until { bound.waiting == 0 }
        bound.advance(by: .seconds(1_000))
        await settled()
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(told, [])
        intake.back()
        try await until { bound.waiting == 2 }
        XCTAssertEqual(bound.asked.count, 5, "the photo's and the wait's again, from now")
        bound.advance(by: .seconds(180))
        guard try await ends(sending) else { return }
        XCTAssertEqual(told, ["The photo could not be attached."])
        XCTAssertEqual(sends, 0)
        XCTAssertTrue(actions.isWriting)
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// A bound that ran out just as he left the app, its turn on the main
    /// thread not yet come: cancelled as the app went, it counts nothing
    /// out, and the one it was for has its bound again from his return.
    func testABoundCancelledAfterItRanOutCountsNothingOut() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let video = Load()
        intake.take([item("IMG_1101", .video, video)])
        try await until { bound.waiting == 1 }
        bound.advance(by: .seconds(180))
        intake.away()
        intake.back()
        await settled()
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_1101"], "not counted out")
        XCTAssertEqual(told, [])
        try await until { bound.waiting == 1 }
        XCTAssertEqual(bound.asked, [.seconds(180), .seconds(180)])
        land(video, "IMG_1101.MOV", .video)
        try await until { intake.coming.isEmpty }
        XCTAssertEqual(rows.map(\.filename), ["IMG_1101.MOV"])
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// The composer gone with something still coming: what comes after it
    /// is removed from the disk, there being no letter to put it in.
    func testWhatComesAfterTheComposerHasGoneIsRemoved() async throws {
        let actions = makeActions()
        var intake: ComposeIntake? = makeIntake(actions)
        weak var gone = intake
        let photo = Load()
        intake?.take([item("IMG_1001", .picture, photo)])
        XCTAssertTrue(photo.begun)
        intake = nil
        XCTAssertNil(gone, "nothing else holds it")
        let late = try XCTUnwrap(land(photo, "IMG_1001.JPG", .picture))
        try await until { !FileManager.default.fileExists(atPath: late.path) }
        XCTAssertEqual(rows, [])
    }

    // MARK: - Set aside as the app goes (B-142)

    /// The intake's lines in the log, in order.
    private func itemNotes() -> [String] {
        Diagnostics.entries.filter { $0.direction == .note }.map(\.text)
            .filter { $0.hasPrefix("COMPOSE-ITEM") }
    }

    /// The round's case: a 1.39 GB video still coming as he locks the
    /// iPad. Its read is called off as the app goes, its row still turning,
    /// nothing counted out and nothing said; the called-off read's nothing
    /// changes nothing and is not taken for a load come after its bound;
    /// nothing is begun while the app is away, however long. On his return
    /// it is read again from the start, with a staging and a tally of its
    /// own and three minutes from then, and goes in.
    func testAVideoComingIsSetAsideAsTheAppGoesAndReadAgainOnItsReturn() async throws {
        Diagnostics.clear()
        let actions = makeActions()
        let intake = makeIntake(actions)
        let video = Load(cancellable: true)
        intake.take([item("IMG_0712", .video, video)])
        try await until { bound.waiting == 1 }
        XCTAssertEqual(video.begins, 1)
        XCTAssertTrue(intake.isReading)
        let calledOff = try XCTUnwrap(video.done)
        let firstStaging = try XCTUnwrap(video.staging)
        bound.advance(by: .seconds(30))

        intake.away()
        XCTAssertEqual(video.calledOff(0), true, "called off as the app goes")
        XCTAssertFalse(intake.isReading)
        try await until { bound.waiting == 0 }
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0712"], "its row still turning")
        XCTAssertTrue(actions.asksAnyway, "still coming, so Cancel still asks")
        calledOff(nil)
        await settled()
        bound.advance(by: .seconds(600))
        await settled()
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0712"])
        XCTAssertEqual(video.begins, 1, "not begun again while the app is away")
        XCTAssertEqual(told, [], "nothing counted out, nothing said")
        XCTAssertEqual(rows, [])
        XCTAssertTrue(actions.asksAnyway)

        intake.back()
        XCTAssertEqual(video.begins, 2, "read again on his return")
        XCTAssertTrue(intake.isReading)
        XCTAssertEqual(video.calledOff(1), false)
        XCTAssertFalse(video.staging === firstStaging, "a staging of its own")
        XCTAssertEqual(video.tally?.videos, 1, "a tally of its own")
        try await until { bound.waiting == 1 }
        XCTAssertEqual(bound.asked, [.seconds(180), .seconds(180)], "three minutes again")
        land(video, "IMG_0712.MOV", .video)
        try await until { intake.coming.isEmpty }
        XCTAssertEqual(rows.map(\.filename), ["IMG_0712.MOV"])
        XCTAssertEqual(told, [])
        XCTAssertFalse(actions.asksAnyway)
        XCTAssertEqual(itemNotes(), ["COMPOSE-ITEM set aside as the app went, called off",
                                     "COMPOSE-ITEM set aside, its read ended with nothing"])
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// A called-off read calls back once, whenever iOS lets it: after his
    /// return too, the video being read again. Its nothing then changes
    /// nothing. What it read, should it have ended before it was called
    /// off, goes in, counted as attached, and the read under way of the
    /// same row is called off: the file has come, and a provider read again
    /// may not bring it again. What that later read brings after is thrown
    /// away. Set aside twice before either call back comes, read three
    /// times, the video goes in once.
    func testACalledOffReadsFileIsTakenWhileTheVideoIsReadAgain() async throws {
        Diagnostics.clear()
        let actions = makeActions()
        let intake = makeIntake(actions)
        let video = Load(cancellable: true)
        intake.take([item("IMG_0713", .video, video)])
        let first = try XCTUnwrap(video.done)
        let firstStaging = try XCTUnwrap(video.staging)
        let firstTally = try XCTUnwrap(video.tally)
        intake.away()
        intake.back()
        XCTAssertEqual(video.begins, 2)
        let second = try XCTUnwrap(video.done)
        let secondStaging = try XCTUnwrap(video.staging)
        try await until { bound.waiting == 1 }

        // The first read ended before it was called off: its file goes in.
        let read = firstStaging.photo(Data(repeating: 1, count: 50), named: "IMG_0713.MOV",
                                      mimeType: "video/quicktime")
        firstTally.videosAttached += 1
        first(read)
        try await until { intake.coming.isEmpty }
        XCTAssertEqual(rows.map(\.filename), ["IMG_0713.MOV"])
        XCTAssertEqual(video.calledOff(1), true, "the read under way called off")
        XCTAssertFalse(intake.isReading)
        XCTAssertEqual(told, [], "counted as attached")
        XCTAssertFalse(actions.asksAnyway)
        try await until { bound.waiting == 0 }
        XCTAssertEqual(video.begins, 2, "not read a third time")

        // The second read, called off, ended first all the same: thrown away.
        let late = try XCTUnwrap(ComposeIntake.file(
            secondStaging.photo(Data(repeating: 2, count: 50), named: "IMG_0713.MOV",
                                mimeType: "video/quicktime")))
        second(.file(late, filename: "IMG_0713.MOV", mimeType: "video/quicktime", size: 50))
        try await until { !FileManager.default.fileExists(atPath: late.path) }
        XCTAssertEqual(rows.map(\.filename), ["IMG_0713.MOV"], "in once")
        XCTAssertEqual(told, [])
        XCTAssertEqual(itemNotes(), [
            "COMPOSE-ITEM set aside as the app went, called off",
            "COMPOSE-ITEM set aside and come while it was read again, taken, the read again called off",
            "COMPOSE-ITEM came after an earlier read of it came, thrown away"])

        // Its nothing, the second read called off, changes nothing.
        let clip = Load(cancellable: true)
        intake.take([item("IMG_0714", .video, clip)])
        let one = try XCTUnwrap(clip.done)
        let oneStaging = try XCTUnwrap(clip.staging)
        let oneTally = try XCTUnwrap(clip.tally)
        intake.away()
        intake.back()
        let two = try XCTUnwrap(clip.done)
        oneTally.videosAttached += 1
        one(oneStaging.photo(Data(repeating: 3, count: 50), named: "IMG_0714.MOV",
                             mimeType: "video/quicktime"))
        try await until { intake.coming.isEmpty }
        two(nil)
        await settled()
        XCTAssertEqual(rows.map(\.filename), ["IMG_0713.MOV", "IMG_0714.MOV"])
        XCTAssertEqual(clip.begins, 2)

        // Set aside twice before either call back comes, each read under a
        // number of its own: both nothings change nothing, and the third
        // read is neither ended nor counted by them.
        let film = Load(cancellable: true)
        intake.take([item("IMG_0715", .video, film)])
        let three = try XCTUnwrap(film.done)
        intake.away()
        intake.back()
        let four = try XCTUnwrap(film.done)
        intake.away()
        intake.back()
        XCTAssertEqual(film.begins, 3)
        three(nil)
        four(nil)
        await settled()
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0715"])
        XCTAssertTrue(intake.isReading, "the third read goes on")
        XCTAssertEqual(film.calledOff(2), false)
        XCTAssertEqual(told, [])
        land(film, "IMG_0715.MOV", .video)
        try await until { intake.coming.isEmpty }
        XCTAssertEqual(rows.map(\.filename), ["IMG_0713.MOV", "IMG_0714.MOV", "IMG_0715.MOV"])
        XCTAssertEqual(told, [])
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// A read that ended just as the app went, too late to be called off:
    /// what it read goes in, while the app is away, counted as it was
    /// read, and is not read again; the one after it waits for his return.
    func testAReadSetAsideThatEndedFirstGoesInAndIsNotReadAgain() async throws {
        Diagnostics.clear()
        let actions = makeActions()
        let intake = makeIntake(actions)
        let first = Load(cancellable: true), second = Load(cancellable: true)
        intake.take([item("IMG_0201", .picture, first), item("IMG_0202", .picture, second)])
        intake.away()
        XCTAssertEqual(first.calledOff(0), true)
        land(first, "IMG_0201.JPG", .picture)
        try await until { intake.coming.count == 1 }
        XCTAssertEqual(rows.map(\.filename), ["IMG_0201.JPG"])
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0202"])
        XCTAssertFalse(second.begun, "nothing begun while the app is away")
        XCTAssertFalse(intake.isReading)

        intake.back()
        XCTAssertEqual(first.begins, 1, "not read again")
        XCTAssertEqual(second.begins, 1)
        land(second, "IMG_0202.JPG", .picture)
        try await until { intake.coming.isEmpty }
        XCTAssertEqual(rows.map(\.filename), ["IMG_0201.JPG", "IMG_0202.JPG"])
        XCTAssertEqual(told, [], "both counted as attached")
        XCTAssertFalse(actions.asksAnyway)
        XCTAssertEqual(itemNotes(), ["COMPOSE-ITEM set aside as the app went, called off",
                                     "COMPOSE-ITEM set aside and come all the same"])
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// The bound of a video set aside 170 s into its three minutes runs
    /// again whole from his return, not from where it stopped: counted out
    /// at 180 s after it, not before, and said, and its second read called
    /// off there, so Photos' copy and its claim on the app end with it;
    /// what that read brings after all, having ended first, is thrown away,
    /// as any load come after its bound.
    func testASetAsideVideoHasThreeMinutesFromHisReturn() async throws {
        Diagnostics.clear()
        let actions = makeActions()
        let intake = makeIntake(actions)
        let video = Load(cancellable: true)
        intake.take([item("IMG_0714", .video, video)])
        try await until { bound.waiting == 1 }
        bound.advance(by: .seconds(170))
        let calledOff = try XCTUnwrap(video.done)
        intake.away()
        calledOff(nil)
        bound.advance(by: .seconds(1_000))
        await settled()
        intake.back()
        try await until { bound.waiting == 1 }
        bound.advance(by: .seconds(179))
        await settled()
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0714"], "not at 179 s")
        XCTAssertEqual(told, [])
        XCTAssertEqual(video.calledOff(1), false)
        bound.advance(by: .seconds(1))
        try await until { intake.coming.isEmpty }
        XCTAssertEqual(told, ["The video could not be attached."])
        XCTAssertEqual(video.calledOff(1), true, "called off at its bound")
        XCTAssertFalse(actions.asksAnyway)
        let late = try XCTUnwrap(land(video, "IMG_0714.MOV", .video))
        try await until { !FileManager.default.fileExists(atPath: late.path) }
        XCTAssertEqual(rows, [])
        XCTAssertEqual(itemNotes(), ["COMPOSE-ITEM set aside as the app went, called off",
                                     "COMPOSE-ITEM set aside, its read ended with nothing",
                                     "COMPOSE-ITEM counted out after 180 s",
                                     "COMPOSE-ITEM came after its bound, thrown away"])
    }

    /// Several picks waiting as he leaves: the video under way set aside at
    /// the head of the queue, nothing else begun while the app is away,
    /// and on his return everything read in his order, each with the room
    /// the rows before it leave, a pick's words said once as it ends.
    func testSeveralPicksWaitingAreReadInHisOrderOnHisReturn() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let video = Load(cancellable: true), photo = Load(cancellable: true)
        let later = Load(cancellable: true)
        intake.take([item("IMG_0301", .video, video), item("IMG_0302", .picture, photo)])
        intake.take([item("IMG_0303", .picture, later)])
        let calledOff = try XCTUnwrap(video.done)
        intake.away()
        calledOff(nil)
        bound.advance(by: .seconds(600))
        await settled()
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0301", "IMG_0302", "IMG_0303"])
        XCTAssertFalse(photo.begun)
        XCTAssertFalse(later.begun)
        XCTAssertTrue(actions.asksAnyway)

        intake.back()
        XCTAssertEqual(video.begins, 2, "the video first, again")
        XCTAssertFalse(photo.begun)
        XCTAssertEqual(video.staging?.room, ShareItems.Staging.budget)
        land(video, "IMG_0301.MOV", .video, bytes: 5_000_000)
        try await until { photo.begun }
        XCTAssertEqual(photo.staging?.room, 20_000_000, "with the video's row in")
        XCTAssertFalse(later.begun)
        fail(photo)
        try await until { later.begun }
        try await until { told.count == 1 }
        XCTAssertEqual(told, ["1 photo could not be attached."], "the first pick ends")
        land(later, "IMG_0303.JPG", .picture)
        try await until { intake.coming.isEmpty }
        XCTAssertEqual(rows.map(\.filename), ["IMG_0301.MOV", "IMG_0303.JPG"])
        XCTAssertEqual(told.count, 1, "the second pick came whole")
        XCTAssertFalse(actions.asksAnyway)
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// Leaving the app with a video coming keeps the letter at once and
    /// gives the background time back at once: nothing set aside is waited
    /// for, so iOS suspends the app rather than ending it.
    func testLeavingTheAppHoldsNoTimeForWhatIsSetAside() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let video = Load(cancellable: true)
        intake.take([item("IMG_0401", .video, video)])
        actions.edited { [unowned self] in letter() }
        try await until { bound.waiting == 1 }
        intake.away()
        XCTAssertEqual(video.calledOff(0), true, "nothing waits for it: called off at once")
        XCTAssertNil(actions.putAside { [unowned self] in letter() }, "nothing to wait for")
        XCTAssertEqual(background.begun, ["Keep Draft"])
        XCTAssertEqual(background.ended, [1], "given back at once")
        XCTAssertEqual(keeps, [[]], "the letter kept as it is")
        await settled()
        XCTAssertEqual(bound.asked, [.seconds(180)], "no grace with nothing waiting")
        intake.back()
        land(video, "IMG_0401.MOV", .video)
        try await until { intake.coming.isEmpty }
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// Send tapped with a photo still coming, then the iPad locked: the
    /// letter is kept on the iPad at the tap, and the photo's read is let
    /// run its 20 s as the app goes, not called off, so a photo a moment
    /// from coming lands while he is away and the letter goes with it,
    /// inside the Send's own background time, as before B-142.
    func testASendWaitingLetsTheReadRunItsGraceAsTheAppGoes() async throws {
        Diagnostics.clear()
        let actions = makeActions()
        let intake = makeIntake(actions)
        let photo = Load(cancellable: true)
        intake.take([item("IMG_0411", .picture, photo)])
        let sending = try XCTUnwrap(actions.send({ [unowned self] in letter() }, then: nil))
        XCTAssertEqual(keeps, [[]], "kept at the tap")
        try await until { bound.waiting == 2 }
        intake.away()
        XCTAssertNil(actions.putAside { [unowned self] in letter() })
        XCTAssertEqual(photo.calledOff(0), false, "let run")
        XCTAssertTrue(intake.isReading)
        try await until { bound.asked.last == ComposeIntake.grace && bound.waiting == 1 }
        XCTAssertEqual(ComposeIntake.grace, .seconds(20))
        bound.advance(by: .seconds(19))
        await settled()
        XCTAssertEqual(photo.calledOff(0), false, "not at 19 s")
        land(photo, "IMG_0411.JPG", .picture)
        guard try await ends(sending) else { return }
        XCTAssertEqual(sends, 1, "gone while he is away")
        XCTAssertEqual(log.last(where: { $0.hasPrefix("send") }), "send with [\"IMG_0411.JPG\"]")
        XCTAssertEqual(background.begun, ["Send"], "held throughout")
        XCTAssertEqual(background.ended, [1])
        try await until { bound.waiting == 0 }
        XCTAssertEqual(itemNotes(), ["COMPOSE-ITEM let run 20 s as the app went, a Send or Save Draft waiting"])
        XCTAssertEqual(told, [])
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// Send tapped with a long video still coming, then the iPad locked:
    /// the letter is kept on the iPad at the tap, before any waiting; the
    /// read is let run 20 s, then called off and set aside, well inside
    /// the 30 s iOS gives Photos' claim, and the Send's background time is
    /// given back, so iOS suspends the app. The Send goes on waiting,
    /// "Sending…", nothing sent and nothing said while he is away. On his
    /// return the video is read again, the Send asks for its time again,
    /// and goes with the video once it is in.
    func testASendWaitingThroughLeavingTheAppIsKeptAndGoesOnHisReturn() async throws {
        Diagnostics.clear()
        let actions = makeActions()
        let intake = makeIntake(actions)
        let video = Load(cancellable: true)
        intake.take([item("IMG_0412", .video, video)])
        let calledOff = try XCTUnwrap(video.done)
        let sending = try XCTUnwrap(actions.send({ [unowned self] in letter() }, then: nil))
        XCTAssertEqual(keeps, [[]], "kept at the tap, before any waiting")
        try await until { bound.waiting == 2 }
        intake.away()
        XCTAssertNil(actions.putAside { [unowned self] in letter() })
        try await until { bound.asked.last == ComposeIntake.grace && bound.waiting == 1 }
        await settled()
        XCTAssertEqual(background.ended, [], "the Send's time held while it is read")
        bound.advance(by: .seconds(20))
        try await until { video.calledOff(0) == true }
        XCTAssertFalse(intake.isReading)
        try await until { background.ended == [1] }
        calledOff(nil)
        bound.advance(by: .seconds(1_000))
        await settled()
        XCTAssertEqual(sends, 0, "still waiting")
        XCTAssertEqual(draws, [.sending("Sending…")])
        XCTAssertEqual(told, [])
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0412"])
        XCTAssertEqual(background.begun, ["Send"])
        XCTAssertEqual(keeps, [[]])

        intake.back()
        XCTAssertEqual(video.begins, 2, "read again on his return")
        try await until { background.begun == ["Send", "Send"] }
        land(video, "IMG_0412.MOV", .video)
        guard try await ends(sending) else { return }
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(log.last(where: { $0.hasPrefix("send") }), "send with [\"IMG_0412.MOV\"]")
        XCTAssertEqual(background.ended, [1, 2])
        XCTAssertEqual(told, [])
        XCTAssertEqual(itemNotes(), [
            "COMPOSE-ITEM let run 20 s as the app went, a Send or Save Draft waiting",
            "COMPOSE-ITEM set aside 20 s after the app went, called off",
            "COMPOSE-ITEM set aside, its read ended with nothing"])
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// Save Draft the same, the sheet already gone: the video let run 20 s
    /// as the app goes, then set aside and the save's time given back; on
    /// his return read again, the time asked for again, and the draft saved
    /// with it. A Save Draft does not call the read off as the sheet goes.
    func testASaveDraftWaitingThroughLeavingTheAppSavesOnHisReturn() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let video = Load(cancellable: true)
        intake.take([item("IMG_0413", .video, video)])
        let saving = try XCTUnwrap(actions.saveAndClose({ [unowned self] in letter() }, then: nil))
        XCTAssertEqual(log, ["dismiss"])
        XCTAssertEqual(video.calledOff(0), false, "not called off as the sheet goes")
        try await until { bound.waiting == 2 }
        intake.away()
        try await until { bound.asked.last == ComposeIntake.grace && bound.waiting == 1 }
        bound.advance(by: .seconds(20))
        try await until { background.ended == [1] }
        XCTAssertEqual(video.calledOff(0), true)
        XCTAssertEqual(saves, 0)
        intake.back()
        try await until { background.begun == ["Save Draft", "Save Draft"] }
        land(video, "IMG_0413.MOV", .video)
        guard try await ends(saving) else { return }
        XCTAssertEqual(log.filter { $0.hasPrefix("save") }, ["save with [\"IMG_0413.MOV\"]"])
        XCTAssertEqual(background.ended, [1, 2])
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// A read counted out is called off there, at its own bound and at a
    /// Send's: Photos' copy and its claim on the app end with it, and
    /// leaving the app after "The video could not be attached." no longer
    /// finds a copy still running (B-142). Its call back then, nothing or
    /// a file it ended with first, changes nothing. A video, then a photo
    /// in a pick of its own, Send 100 s in: the video counted out at its
    /// own bound, 180 s, the photo at the Send's, 280 s.
    func testACountedOutReadIsCalledOff() async throws {
        Diagnostics.clear()
        let actions = makeActions()
        let intake = makeIntake(actions)
        let video = Load(cancellable: true), photo = Load(cancellable: true)
        intake.take([item("IMG_0421", .video, video)])
        intake.take([item("IMG_0422", .picture, photo)])
        let calledOff = try XCTUnwrap(video.done)
        try await until { bound.waiting == 1 }
        bound.advance(by: .seconds(100))
        let sending = try XCTUnwrap(actions.send({ [unowned self] in letter() }, then: nil))
        try await until { bound.waiting == 2 }
        XCTAssertEqual(video.calledOff(0), false)
        bound.advance(by: .seconds(80))
        try await until { photo.begun }
        XCTAssertEqual(video.calledOff(0), true, "called off at its own bound")
        XCTAssertEqual(told, ["The video could not be attached."])
        calledOff(nil)
        await settled()
        XCTAssertEqual(told.count, 1, "its nothing changes nothing")
        XCTAssertTrue(intake.isReading, "the photo goes on")
        XCTAssertEqual(photo.calledOff(0), false)

        try await until { bound.waiting == 2 }
        bound.advance(by: .seconds(99))
        await settled()
        XCTAssertEqual(photo.calledOff(0), false, "not before the Send's bound")
        bound.advance(by: .seconds(1))
        guard try await ends(sending) else { return }
        XCTAssertEqual(photo.calledOff(0), true, "called off at the Send's bound")
        XCTAssertEqual(told, ["The video could not be attached.", "The photo could not be attached."])
        XCTAssertEqual(sends, 0)
        let late = try XCTUnwrap(land(photo, "IMG_0422.JPG", .picture))
        try await until { !FileManager.default.fileExists(atPath: late.path) }
        XCTAssertEqual(rows, [])
        XCTAssertEqual(told.count, 2)
        XCTAssertEqual(itemNotes(), ["COMPOSE-ITEM counted out after 180 s",
                                     "COMPOSE-ITEM came after its bound, thrown away"])
    }

    /// The sheet closed with something still coming, nothing waiting for
    /// it: Delete Draft, a Cancel that asks nothing, the sheet put away.
    /// The read under way is called off, its bound let go, and nothing
    /// after it begun; its call back then changes nothing, and a file it
    /// ended with first is thrown away. A Send that has gone closes it too.
    func testClosingTheSheetCallsOffTheReadUnderWay() async throws {
        Diagnostics.clear()
        let actions = makeActions()
        let intake = makeIntake(actions)
        let video = Load(cancellable: true), photo = Load(cancellable: true)
        intake.take([item("IMG_0431", .video, video), item("IMG_0432", .picture, photo)])
        try await until { bound.waiting == 1 }
        XCTAssertNotNil(actions.deleteAndClose(nil, letter: nil, then: nil))
        XCTAssertEqual(video.calledOff(0), true, "called off with Delete Draft")
        XCTAssertFalse(intake.isReading)
        try await until { bound.waiting == 0 }
        let late = try XCTUnwrap(land(video, "IMG_0431.MOV", .video))
        try await until { !FileManager.default.fileExists(atPath: late.path) }
        await settled()
        XCTAssertFalse(photo.begun, "nothing more begun")
        XCTAssertEqual(rows, [])
        XCTAssertEqual(told, [])
        XCTAssertEqual(itemNotes(), ["COMPOSE-ITEM called off, the letter closed",
                                     "COMPOSE-ITEM came after the letter closed, thrown away"])

        let swiped = makeActions()
        let other = makeIntake(swiped)
        let film = Load(cancellable: true)
        other.take([item("IMG_0433", .video, film)])
        swiped.sheetGone { [unowned self] in letter() }
        XCTAssertEqual(film.calledOff(0), true, "called off with the sheet put away")

        let asked = makeActions()
        let third = makeIntake(asked)
        let clip = Load(cancellable: true)
        third.take([item("IMG_0434", .video, clip)])
        asked.closeWithoutAsking { [unowned self] in letter() }
        XCTAssertEqual(clip.calledOff(0), true, "called off with a Cancel that asked nothing")

        let sent = makeActions()
        let fourth = makeIntake(sent)
        await sent.send({ [unowned self] in letter() }, then: nil)?.value
        let after = Load(cancellable: true)
        fourth.take([item("IMG_0435", .picture, after)])
        XCTAssertFalse(after.begun, "a Send gone closes it too")
    }

    /// A set-aside read that lands is counted with the rest of its pick:
    /// two videos in one pick, the first ended before it could be called
    /// off and in while the app is away, the second counted out after his
    /// return, say one video, not the video. And two photos, the first's
    /// set-aside read landing while it is read again and the second
    /// failing, say one photo.
    func testASetAsideReadThatLandsIsCountedWithTheRestOfItsPick() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let first = Load(cancellable: true), second = Load(cancellable: true)
        intake.take([item("IMG_0441", .video, first), item("IMG_0442", .video, second)])
        intake.away()
        land(first, "IMG_0441.MOV", .video)
        try await until { intake.coming.count == 1 }
        intake.back()
        XCTAssertEqual(second.begins, 1)
        try await until { bound.waiting == 1 }
        bound.advance(by: .seconds(180))
        try await until { intake.coming.isEmpty }
        XCTAssertEqual(rows.map(\.filename), ["IMG_0441.MOV"])
        XCTAssertEqual(told, ["1 video could not be attached."])

        let one = Load(cancellable: true), two = Load(cancellable: true)
        intake.take([item("IMG_0443", .picture, one), item("IMG_0444", .picture, two)])
        let earlier = try XCTUnwrap(one.done)
        let earlierStaging = try XCTUnwrap(one.staging)
        let earlierTally = try XCTUnwrap(one.tally)
        intake.away()
        intake.back()
        XCTAssertEqual(one.begins, 2)
        earlierTally.attached += 1
        earlier(earlierStaging.photo(Data(repeating: 4, count: 100), named: "IMG_0443.JPG",
                                     mimeType: "image/jpeg"))
        try await until { two.begun }
        fail(two)
        try await until { intake.coming.isEmpty }
        XCTAssertEqual(rows.map(\.filename), ["IMG_0441.MOV", "IMG_0443.JPG"])
        XCTAssertEqual(told, ["1 video could not be attached.", "1 photo could not be attached."])
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// A read that cannot be called off, a file from Attach File, goes on
    /// as he leaves, and the keep waits for it alone: once it is in, the
    /// letter is kept again with it and the time given back, though a
    /// video after it is still to come, which is not begun while the app is
    /// away. A keep left waiting while he came back and went again, the
    /// video begun meanwhile and set aside as he went, waits no longer.
    func testLeavingTheAppWaitsOnlyForAReadThatGoesOn() async throws {
        let actions = makeActions()
        let intake = makeIntake(actions)
        let plans = Load(), video = Load(cancellable: true)
        intake.take([item("Plans.pdf", .file, plans), item("IMG_0501", .video, video)])
        actions.edited { [unowned self] in letter() }
        intake.away()
        XCTAssertTrue(intake.isReading, "the file goes on")
        let keeping = try XCTUnwrap(actions.putAside { [unowned self] in letter() })
        XCTAssertEqual(keeps, [[]])
        land(plans, "Plans.pdf", .file)
        guard try await ends(keeping) else { return }
        XCTAssertEqual(keeps, [[], ["Plans.pdf"]], "kept again with the file")
        XCTAssertEqual(background.ended, [1])
        XCTAssertFalse(video.begun, "not begun while the app is away")
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0501"])
        intake.back()
        XCTAssertEqual(video.begins, 1)
        land(video, "IMG_0501.MOV", .video)
        try await until { intake.coming.isEmpty }

        // Away with a file being read, back before it lands, and the video
        // after it begun in front: the first keep waits on.
        let report = Load(), film = Load(cancellable: true)
        intake.take([item("Report.pdf", .file, report), item("IMG_0502", .video, film)])
        intake.away()
        let first = try XCTUnwrap(actions.putAside { [unowned self] in letter() })
        intake.back()
        land(report, "Report.pdf", .file)
        try await until { film.begun }
        await settled()
        XCTAssertEqual(background.ended, [1], "the video is being read: still waiting")
        intake.away()
        XCTAssertEqual(film.calledOff(0), true)
        guard try await ends(first) else { return }
        XCTAssertEqual(background.ended, [1, 2])
        XCTAssertNil(actions.putAside { [unowned self] in letter() })
        XCTAssertEqual(background.ended, [1, 2, 3])
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0502"])
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    // MARK: - A video made H.264 in the app (B-142, again)

    /// A Send waiting as the app goes, a video's conversion under way in
    /// its 20 seconds' grace, and AVFoundation stopping it, as it does an
    /// app's encoder in the background: the read hands back its original,
    /// marked. It is not taken: thrown away, the row set aside, its grace
    /// let go and the Send's time given back, nothing sent, counted out or
    /// said however long he is away. On his return it is read again and
    /// made H.264, and the Send goes with that.
    func testAConversionStoppedInTheGraceIsSetAsideAndMadeOnHisReturn() async throws {
        Diagnostics.clear()
        let actions = makeActions()
        let intake = makeIntake(actions)
        let video = Load(cancellable: true)
        intake.take([item("IMG_0195", .video, video)])
        let sending = try XCTUnwrap(actions.send({ [unowned self] in letter() }, then: nil))
        try await until { bound.waiting == 2 }
        intake.away()
        try await until { bound.asked.last == ComposeIntake.grace && bound.waiting == 1 }
        await settled()
        XCTAssertEqual(background.ended, [], "the Send's time held while it is read")

        video.loadings[0].interrupted()
        let original = try XCTUnwrap(land(video, "IMG_0195.MOV", .video))
        try await until { !FileManager.default.fileExists(atPath: original.path) }
        try await until { background.ended == [1] }
        try await until { bound.waiting == 0 }
        XCTAssertFalse(intake.isReading)
        XCTAssertEqual(video.calledOff(0), false, "ended, nothing to call off")
        bound.advance(by: .seconds(1_000))
        await settled()
        XCTAssertEqual(sends, 0, "still waiting")
        XCTAssertEqual(told, [])
        XCTAssertEqual(rows, [])
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0195"])
        XCTAssertEqual(video.begins, 1, "not begun again while the app is away")

        intake.back()
        XCTAssertEqual(video.begins, 2, "read again on his return")
        try await until { background.begun == ["Send", "Send"] }
        land(video, "IMG_0195.MOV", .video)
        guard try await ends(sending) else { return }
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(log.last(where: { $0.hasPrefix("send") }), "send with [\"IMG_0195.MOV\"]")
        XCTAssertEqual(told, [])
        XCTAssertEqual(itemNotes(), [
            "COMPOSE-ITEM let run 20 s as the app went, a Send or Save Draft waiting",
            "COMPOSE-ITEM set aside, its conversion stopped as the app went"])
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// A conversion stopped whose read was set aside first, the app gone
    /// with nothing waiting: what it brings, its original, is thrown away,
    /// and its row is read again on his return. A conversion stopped while
    /// the app is still in front, its call back come before the app's
    /// going was heard, or after his return: never its original, thrown
    /// away, and the row read again at once; the app's going then sets that
    /// read aside. Stopped a second time in front, the app not having gone
    /// between, it is left out and said, and not read round and round; the
    /// app going clears that count.
    func testAConversionStoppedOutsideTheGraceIsNeverTakenAndIsReadAgain() async throws {
        Diagnostics.clear()
        let actions = makeActions()
        let intake = makeIntake(actions)
        let video = Load(cancellable: true)
        intake.take([item("IMG_0196", .video, video)])
        intake.away()
        XCTAssertEqual(video.calledOff(0), true)
        video.loadings[0].interrupted()
        let original = try XCTUnwrap(land(video, "IMG_0196.MOV", .video))
        try await until { !FileManager.default.fileExists(atPath: original.path) }
        XCTAssertEqual(rows, [])
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0196"])
        intake.back()
        XCTAssertEqual(video.begins, 2, "read again on his return")
        land(video, "IMG_0196.MOV", .video)
        try await until { intake.coming.isEmpty }
        XCTAssertEqual(rows.map(\.filename), ["IMG_0196.MOV"])

        // In front: the stop heard before the app's going.
        let film = Load(cancellable: true)
        intake.take([item("IMG_0197", .video, film)])
        film.loadings[0].interrupted()
        let first = try XCTUnwrap(land(film, "IMG_0197.MOV", .video))
        try await until { film.begins == 2 }
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path), "its original thrown away")
        XCTAssertEqual(rows.map(\.filename), ["IMG_0196.MOV"], "not taken")
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0197"])
        XCTAssertTrue(intake.isReading, "read again at once")
        intake.away()
        XCTAssertEqual(film.calledOff(1), true, "the read again set aside as the app goes")
        fail(film)
        await settled()
        intake.back()
        XCTAssertEqual(film.begins, 3)
        // In front again, after a going: read again, not left out.
        try XCTUnwrap(film.loadings.dropFirst(2).first).interrupted()
        land(film, "IMG_0197.MOV", .video)
        try await until { film.begins == 4 }
        XCTAssertEqual(told, [])
        land(film, "IMG_0197.MOV", .video)
        try await until { intake.coming.isEmpty }
        XCTAssertEqual(rows.map(\.filename), ["IMG_0196.MOV", "IMG_0197.MOV"])

        // Stopped twice in front, nothing between: left out, and said.
        let clip = Load(cancellable: true)
        intake.take([item("IMG_0198", .video, clip)])
        clip.loadings[0].interrupted()
        let once = try XCTUnwrap(land(clip, "IMG_0198.MOV", .video))
        try await until { clip.begins == 2 }
        try XCTUnwrap(clip.loadings.dropFirst(1).first).interrupted()
        let twice = try XCTUnwrap(land(clip, "IMG_0198.MOV", .video))
        try await until { told == ["The video could not be attached."] }
        XCTAssertEqual(clip.begins, 2, "not read a third time")
        XCTAssertFalse(FileManager.default.fileExists(atPath: once.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: twice.path))
        XCTAssertEqual(rows.map(\.filename), ["IMG_0196.MOV", "IMG_0197.MOV"])
        XCTAssertTrue(intake.coming.isEmpty)
        XCTAssertEqual(itemNotes(), [
            "COMPOSE-ITEM set aside as the app went, called off",
            "COMPOSE-ITEM set aside, its conversion stopped as the app went, thrown away",
            "COMPOSE-ITEM its conversion stopped in front, read again",
            "COMPOSE-ITEM set aside as the app went, called off",
            "COMPOSE-ITEM set aside, its read ended with nothing",
            "COMPOSE-ITEM its conversion stopped in front, read again",
            "COMPOSE-ITEM its conversion stopped in front, read again",
            "COMPOSE-ITEM its conversion stopped again in front, left out"])
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// Through the shipping read's staging and conversion
    /// (`ShareItems.stageRead`, `compatible`), with the test's own
    /// conversion: a video's conversion is called off with its read as the
    /// app goes, at its count-out and as the letter closes; called off, it
    /// leaves nothing on the disk; read again on his return, it is made
    /// H.264, and the copy is the row.
    func testAVideosConversionIsCalledOffWithItsRead() async throws {
        Diagnostics.clear()
        let actions = makeActions()
        let intake = makeIntake(actions)
        let conversion = FakeVideoConversion()
        let given = try file("IMG_0195.MOV", bytes: 1_000)
        func video(_ name: String) -> ComposeIntake.Item {
            ComposeIntake.Item(name: name, kind: .video) { staging, tally, done in
                tally.videos += 1
                let loading = ShareItems.Loading()
                ShareItems.stageRead(given, size: 1_000, type: "com.apple.quicktime-movie",
                                     suggested: true, name: name + ".MOV",
                                     mimeType: "video/quicktime", videos: conversion.videos,
                                     staging: staging, loading: loading) { item in
                    if item != nil { tally.videosAttached += 1 }
                    done(item)
                }
                return loading
            }
        }

        intake.take([video("IMG_0195")])
        XCTAssertEqual(conversion.asked.count, 1)
        let first = try XCTUnwrap(conversion.asked.last)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.from.path))
        intake.away()
        XCTAssertEqual(conversion.calledOff, 1, "called off as the app goes")
        conversion.end(.cancelled)
        try await until { !FileManager.default.fileExists(atPath: first.from.path) }
        await settled()
        XCTAssertEqual(rows, [])
        XCTAssertEqual(intake.coming.map(\.name), ["IMG_0195"])

        intake.back()
        XCTAssertEqual(conversion.asked.count, 2, "read again, and made again")
        let second = try XCTUnwrap(conversion.asked.last)
        try conversion.make(bytes: 1_500)
        try await until { intake.coming.isEmpty }
        XCTAssertEqual(rows.map(\.filename), ["IMG_0195.MOV"])
        XCTAssertEqual(rows.map(\.size), [1_500], "the H.264 copy")
        XCTAssertEqual(rows.map(\.source), [.localFile(second.to)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.from.path))

        try await until { bound.waiting == 0 }
        intake.take([video("IMG_0198")])
        try await until { bound.waiting == 1 }
        XCTAssertEqual(conversion.asked.count, 3)
        bound.advance(by: .seconds(180))
        try await until { told == ["The video could not be attached."] }
        XCTAssertEqual(conversion.calledOff, 2, "called off at its count-out")
        conversion.end(.cancelled)

        intake.take([video("IMG_0226")])
        XCTAssertEqual(conversion.asked.count, 4)
        XCTAssertNotNil(actions.deleteAndClose(nil, letter: nil, then: nil))
        XCTAssertEqual(conversion.calledOff, 3, "called off as the letter closes")
        let last = try XCTUnwrap(conversion.asked.last)
        try conversion.make(bytes: 1_200)
        await settled()
        XCTAssertFalse(FileManager.default.fileExists(atPath: last.to.path), "nothing left")
        XCTAssertFalse(FileManager.default.fileExists(atPath: last.from.path))
        XCTAssertEqual(rows.map(\.filename), ["IMG_0195.MOV"])
        XCTAssertEqual(Diagnostics.entries.filter { $0.direction == .note }.map(\.text)
                        .filter { $0.hasPrefix("SHARE-VIDEO") },
                       ["SHARE-VIDEO called off",
                        "SHARE-VIDEO made H.264, bytes=1500 from=1000 codec=avc1",
                        "SHARE-VIDEO called off", "SHARE-VIDEO called off"])
        for case .localFile(let url) in rows.map(\.source) { AttachmentStore.removeStaged(url) }
    }

    /// The handle a read is called off by: every load it has begun called
    /// off, in whatever order they were handed over, a picture's next way
    /// handed over before the one it follows; and one begun after it
    /// called off as it is handed over.
    func testALoadingCallsOffTheLoadUnderWayAndAnyAfter() {
        let loading = ShareItems.Loading()
        let next = Progress(totalUnitCount: 1)
        let first = Progress(totalUnitCount: 1)
        loading.track(next)
        loading.track(first)
        XCTAssertFalse(loading.isCancelled)
        XCTAssertFalse(first.isCancelled)
        XCTAssertFalse(next.isCancelled)
        loading.cancel()
        XCTAssertTrue(loading.isCancelled)
        XCTAssertTrue(next.isCancelled, "the load under way, handed over first")
        XCTAssertTrue(first.isCancelled, "and the one it followed")
        let third = Progress(totalUnitCount: 1)
        loading.track(third)
        XCTAssertTrue(third.isCancelled, "begun after, called off at once")
        XCTAssertEqual(ShareItems.fileNote(read: "com.apple.quicktime-movie", suggested: false,
                                           name: "", mimeType: "-", bytes: 0, went: .calledOff),
                       "SHARE-FILE read=com.apple.quicktime-movie name=none \"{0 chars}\" mime=- "
                        + "bytes=0 went=called off")
    }

    /// What a pick from Photo Library is, by the types it offers, as the
    /// share sheet's reading takes it: a picture first, a video next,
    /// anything else a picture. A row with no name says what it is.
    func testWhatAPickIsAndTheNameOfOneWithNone() {
        let isMovie: (String) -> Bool = { $0.hasSuffix("-movie") || $0 == "public.movie" }
        XCTAssertEqual(ComposeIntake.kind(offered: ["public.jpeg"], isMovie: isMovie), .picture)
        XCTAssertEqual(ComposeIntake.kind(offered: ["public.heic", "com.apple.quicktime-movie"],
                                          isMovie: isMovie), .picture, "a Live Photo is a photo")
        XCTAssertEqual(ComposeIntake.kind(offered: ["com.apple.quicktime-movie"], isMovie: isMovie),
                       .video)
        XCTAssertEqual(ComposeIntake.kind(offered: ["public.mpeg-4"], isMovie: { _ in false }), .video)
        XCTAssertEqual(ComposeIntake.kind(offered: ["org.example.other-movie"], isMovie: isMovie),
                       .video)
        XCTAssertEqual(ComposeIntake.kind(offered: ["org.example.thing"], isMovie: isMovie), .picture)
        XCTAssertEqual(ComposeIntake.kind(offered: [], isMovie: isMovie), .picture)

        let noLoad: (ShareItems.Staging, ShareItems.Tally,
                     @escaping (SharedItem?) -> Void) -> ShareItems.Loading? = { _, _, _ in nil }
        XCTAssertEqual(ComposeIntake.Item(name: nil, kind: .picture, load: noLoad).name, "Photo")
        XCTAssertEqual(ComposeIntake.Item(name: "", kind: .video, load: noLoad).name, "Video")
        XCTAssertEqual(ComposeIntake.Item(name: "  ", kind: .picture, load: noLoad).name, "Photo")
        XCTAssertEqual(ComposeIntake.Item(name: "IMG_0001", kind: .video, load: noLoad).name,
                       "IMG_0001")
        XCTAssertEqual(ComposeIntake.Item(name: "Plans.pdf", kind: .file, load: noLoad).name,
                       "Plans.pdf")
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
        XCTAssertEqual(told, ["One or more attachments failed to load."])
        XCTAssertEqual(titles, ["Unable to Attach"])
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
        // Its own bound, and the wait's.
        try await until { bound.waiting == 2 }
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
    /// moved, is removed from the Inbox, and is said. One outside the
    /// Inbox is copied in and left where it is, and one of those too large
    /// is left where it is too.
    func testAFileFromAttachFileIsMovedNamedAndTypedOrLeftOutAndRemoved() async throws {
        let inbox = try XCTUnwrap(AttachmentStore.inbox(in: directory, bundle: "org.example.blackmail"))
        let pdf = try file("Plans: May.pdf", bytes: 4_000, in: inbox)
        let video = try file("Garden.mov", bytes: 9_000, in: inbox)
        let elsewhere = try file("Notes.txt", bytes: 500)
        let large = try file("Minutes.txt", bytes: 2_000)
        let types = ["pdf": "application/pdf", "txt": "text/plain"]
        let actions = makeActions()
        let intake = makeIntake(actions)
        rows = [row("Forwarded.pdf", size: ShareItems.Staging.budget - 5_000)]
        let items = [pdf, video, elsewhere, large].map {
            ComposeIntake.file(at: $0, inbox: inbox, mimeType: { types[$0] })
        }
        XCTAssertEqual(items.map(\.name), ["Plans May.pdf", "Garden.mov", "Notes.txt", "Minutes.txt"])
        XCTAssertEqual(items.map(\.moves), [true, true, false, false])
        XCTAssertEqual(items.map(\.kind), [.file, .file, .file, .file])
        intake.take(items)
        try await until { intake.coming.isEmpty }

        XCTAssertEqual(rows.dropFirst().map(\.filename), ["Plans May.pdf", "Notes.txt"])
        XCTAssertEqual(rows.dropFirst().map(\.mimeType), ["application/pdf", "text/plain"])
        XCTAssertEqual(rows.dropFirst().map(\.size), [4_000, 500])
        XCTAssertEqual(rows.count, 3)
        guard rows.count == 3, case .localFile(let moved) = rows[1].source,
              case .localFile(let copied) = rows[2].source else { return XCTFail("two files") }
        XCTAssertNotNil(AttachmentStore.stagingDirectory(of: moved))
        XCTAssertNotNil(AttachmentStore.stagingDirectory(of: copied), "copied into the staging")
        XCTAssertEqual(try Data(contentsOf: copied), try Data(contentsOf: elsewhere))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pdf.path), "moved out of the Inbox")
        XCTAssertFalse(FileManager.default.fileExists(atPath: video.path), "and the one left out removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: elsewhere.path), "the copied one left")
        XCTAssertTrue(FileManager.default.fileExists(atPath: large.path), "nothing outside it removed")
        XCTAssertEqual(told, ["One or more attachments failed to load."])
        XCTAssertEqual(titles, ["Unable to Attach"])
        AttachmentStore.removeStaged(moved)
        AttachmentStore.removeStaged(copied)

        // A folder is no file.
        rows = []
        let folder = inbox.appendingPathComponent("Folder.pdf", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        intake.take([ComposeIntake.file(at: folder, inbox: inbox, mimeType: { types[$0] })])
        try await until { told.count == 2 }
        XCTAssertEqual(told.last, "One or more attachments failed to load.")
        XCTAssertEqual(titles.last, "Unable to Attach")
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
    /// videos, alone and with no title, and Mail's alert wherever a file
    /// is missing, a mix too (B-144).
    func testTheWordsForEveryCombination() {
        func alert(_ p: Int, _ a: Int, _ v: Int, _ va: Int, _ f: Int = 0, _ fa: Int = 0) -> MailAlert? {
            ComposeIntake.words(pictures: p, attached: a, videos: v, videosAttached: va,
                                files: f, filesAttached: fa)
        }
        func words(_ p: Int, _ a: Int, _ v: Int, _ va: Int, _ f: Int = 0, _ fa: Int = 0) -> String? {
            guard let said = alert(p, a, v, va, f, fa) else { return nil }
            XCTAssertNil(said.title, "the share sheet's words have no title")
            XCTAssertFalse(said.offersSettings)
            return said.message
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

        // Mail's, word for word, for any file missing, alone or in a mix.
        XCTAssertEqual(ComposeIntake.unableToAttach.title, "Unable to Attach")
        XCTAssertEqual(ComposeIntake.unableToAttach.message, "One or more attachments failed to load.")
        XCTAssertFalse(ComposeIntake.unableToAttach.offersSettings)
        for (p, a, v, va, f, fa) in [(0, 0, 0, 0, 1, 0), (0, 0, 0, 0, 2, 0), (0, 0, 0, 0, 3, 2),
                                     (0, 0, 0, 0, 5, 1), (1, 1, 0, 0, 1, 0), (0, 0, 1, 1, 2, 0),
                                     (1, 0, 0, 0, 1, 0), (0, 0, 2, 0, 3, 0), (2, 1, 1, 0, 1, 0)] {
            XCTAssertEqual(alert(p, a, v, va, f, fa), ComposeIntake.unableToAttach,
                           "\((p, a, v, va, f, fa))")
        }
    }
}

/// The bound's clock as a test moves it: each wait is parked until the
/// test says the time has passed, and one cancelled ends at once. Each ends
/// at the clock's time as it began, plus what it asked (`advance`).
@MainActor
final class FakeBound {
    private(set) var asked: [Duration] = []
    private var parked: [Int: CheckedContinuation<Void, Error>] = [:]
    private var ends: [Int: Duration] = [:]
    private var next = 0
    /// The clock: how long the test has said has passed.
    private(set) var now: Duration = .zero

    nonisolated init() {}

    var waiting: Int { parked.count }

    func sleep(_ duration: Duration) async throws {
        asked.append(duration)
        next += 1
        let id = next
        let end = now + duration
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                parked[id] = $0
                ends[id] = end
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    /// Every bound waiting has passed.
    func pass() {
        let all = parked
        parked = [:]
        ends = [:]
        for continuation in all.values { continuation.resume() }
    }

    /// `time` has passed: every wait that ends by then is over, the
    /// earliest first.
    func advance(by time: Duration) {
        now += time
        let due = ends.filter { $0.value <= now }.sorted { $0.value < $1.value }.map(\.key)
        for id in due {
            ends.removeValue(forKey: id)
            parked.removeValue(forKey: id)?.resume()
        }
    }

    func cancelAll() {
        let all = parked
        parked = [:]
        ends = [:]
        for continuation in all.values { continuation.resume(throwing: CancellationError()) }
    }

    private func cancel(_ id: Int) {
        ends.removeValue(forKey: id)
        parked.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}
