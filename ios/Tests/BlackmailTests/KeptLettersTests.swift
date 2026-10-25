import XCTest
@testable import Blackmail

/// The letters he opened, kept on the iPad (`KeptLetters`, D-016's phase 2,
/// B-111), on their own, through the shelf that makes them, in a directory
/// of the test's own laid out as Application Support is: which four keys a
/// letter is read back under, the bounds and the order of eviction, the
/// check at every read, a damaged or foreign index, the sweep at the first
/// use, a relaunch, the wipe and the discard and a keep on its way through
/// either, another account, the floor and its reading held (B-136), a disk
/// that will not write, the keeps
/// waiting for the disk, what the server takes away, the flush, the shelf's
/// life, the backup marks, the log, and the time a 5 MB letter takes. What
/// the repository keeps and shows, and when, is `KeptLetterOpeningTests`.
final class KeptLettersTests: XCTestCase {

    private var base: URL!
    private var support: URL { base.appendingPathComponent("Application Support", isDirectory: true) }
    private var kept: URL { support.appendingPathComponent("Kept", isDirectory: true) }

    private static let inbox = "INBOX"
    private static let allMail = "[Gmail]/All Mail"
    private static let trash = "[Gmail]/Trash"

    override func setUp() {
        super.setUp()
        base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("KeptLettersTests-\(UUID().uuidString)", isDirectory: true)
        Diagnostics.clear()
    }

    override func tearDown() {
        if let base {
            MailShelf.wipe(root: kept)
            try? FileManager.default.removeItem(at: base)
        }
        base = nil
        super.tearDown()
    }

    private func shelf(for address: String = "owner@example.com",
                       options: KeptLetters.Options = KeptLetters.Options()) -> MailShelf {
        MailShelf(root: kept, address: address, host: "imap.gmail.com", letters: options)
    }

    /// Bounds a test can reach in kilobytes: `letters` letters, `bytes` in
    /// all, none over `letter`.
    private func small(letters: Int = 300, bytes: Int = 64 << 20,
                       letter: Int = IMAPMailRepository.largeLetterBytes) -> KeptLetters.Options {
        var options = KeptLetters.Options()
        options.bounds.letters = letters
        options.bounds.bytes = bytes
        options.bounds.letter = letter
        return options
    }

    /// A letter's bytes, `size` of them, saying which it is.
    private func raw(_ n: Int, size: Int = 600) -> Data {
        var text = "From: Sam Example <sam@example.com>\r\nSubject: Letter \(n)\r\n\r\n"
        text += "The garden, letter \(n).\r\n"
        var data = Data(text.utf8)
        if data.count < size {
            data.append(Data((0..<(size - data.count)).map { UInt8(97 + ($0 + n) % 26) }))
        }
        return data
    }

    private func message(_ n: Int) -> UInt64 { 1_800_000_000_000_000_000 + UInt64(n) }

    /// Letter `n`, kept in `folder` under UIDVALIDITY 1 and UID 1000 + n.
    private func keep(_ n: Int, in folder: String = inbox, on shelf: MailShelf, size: Int = 600) {
        shelf.letters.keep(raw(n, size: size), in: folder, validity: 1, uid: UInt32(1_000 + n),
                           message: message(n))
    }

    private func read(_ n: Int, in folder: String = inbox, on shelf: MailShelf,
                      touch: Bool = false) -> Data? {
        shelf.letters.letter(in: folder, validity: 1, uid: UInt32(1_000 + n), message: message(n),
                             touch: touch)
    }

    /// Which letters are kept, oldest opened first: what the next read finds.
    private func keptNumbers(_ shelf: MailShelf) -> [Int] {
        shelf.letters.records.map { Int($0.uid) - 1_000 }
    }

    private func file(_ n: Int, in folder: String = inbox, on shelf: MailShelf) -> URL {
        shelf.letters.files.appendingPathComponent(
            KeptLetters.fileName(folder, 1, UInt32(1_000 + n), message(n)))
    }

    private func names(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    private var letterNotes: [String] {
        Diagnostics.entries.map(\.text).filter { $0.hasPrefix("KEPT-LETTER") }
    }

    // MARK: - The four keys

    /// A letter is read back only under the folder, UIDVALIDITY, UID and
    /// Gmail message id it was kept under, byte for byte; any one of them
    /// different, and nothing.
    func testALetterIsReadBackOnlyUnderItsFolderUIDValidityUIDAndGmailID() {
        let shelf = shelf()
        keep(1, on: shelf)
        XCTAssertEqual(read(1, on: shelf), raw(1))
        let letters = shelf.letters
        XCTAssertNil(letters.letter(in: Self.allMail, validity: 1, uid: 1_001, message: message(1),
                                    touch: false), "another folder")
        XCTAssertNil(letters.letter(in: Self.inbox, validity: 2, uid: 1_001, message: message(1),
                                    touch: false), "another UIDVALIDITY")
        XCTAssertNil(letters.letter(in: Self.inbox, validity: 1, uid: 1_002, message: message(1),
                                    touch: false), "another UID")
        XCTAssertNil(letters.letter(in: Self.inbox, validity: 1, uid: 1_001, message: message(2),
                                    touch: false), "another letter")
        XCTAssertEqual(read(1, on: shelf), raw(1), "and none of those took it away")
        XCTAssertEqual(names(in: shelf.letters.files),
                       [KeptLetters.fileName(Self.inbox, 1, 1_001, message(1))])
        XCTAssertTrue(KeptLetters.fileName(Self.inbox, 1, 1_001, message(1))
            .allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") })
        XCTAssertFalse(KeptLetters.fileName(Self.inbox, 1, 1_001, message(1)).contains("INBOX"))
    }

    // MARK: - The bounds

    /// The bounds are D-016's, and the largest letter is the size above
    /// which a letter is opened in parts.
    func testTheBoundsAreThreeHundredLettersSixtyFourMegabytesAndFiveALetter() {
        let bounds = KeptLetters.Bounds()
        XCTAssertEqual(bounds.letters, 300)
        XCTAssertEqual(bounds.bytes, 64 << 20)
        XCTAssertEqual(bounds.letter, 5 << 20)
        XCTAssertEqual(bounds.letter, IMAPMailRepository.largeLetterBytes)
        XCTAssertEqual(bounds.waiting, 16 << 20)
        XCTAssertEqual(bounds.floor, 512 << 20)
        XCTAssertEqual(KeptLetters.format, 1)
    }

    /// The 301st letter takes the one opened least recently, which a
    /// showing makes the newest: the first, shown again before the 301st,
    /// stays, and the second goes. A second keep of a letter kept already
    /// only touches it, and nothing else goes.
    func testThe301stTakesTheLeastRecentlyOpenedAndAShowingMakesALetterTheNewest() {
        let shelf = shelf()
        for n in 1...300 { keep(n, on: shelf) }
        XCTAssertEqual(keptNumbers(shelf), Array(1...300))
        XCTAssertNotNil(read(1, on: shelf, touch: true))
        keep(301, on: shelf)
        XCTAssertEqual(keptNumbers(shelf), Array(3...300) + [1, 301])
        XCTAssertNil(read(2, on: shelf))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(2, on: shelf).path))
        XCTAssertEqual(names(in: shelf.letters.files).count, 300)

        keep(3, on: shelf)
        XCTAssertEqual(keptNumbers(shelf), Array(4...300) + [1, 301, 3], "touched, nothing gone")
        XCTAssertEqual(names(in: shelf.letters.files).count, 300)
    }

    /// The bytes bound the store as the count does: letters go, the least
    /// recently opened first, until the new one fits. A letter over the
    /// largest kept is not kept and takes nothing.
    func testTheBytesAreBoundedAndALetterOverTheLargestIsNotKeptAndTakesNothing() {
        let shelf = shelf(options: small(bytes: 10_000, letter: 4_000))
        for n in 1...3 { keep(n, on: shelf, size: 3_000) }
        XCTAssertEqual(keptNumbers(shelf), [1, 2, 3])
        keep(4, on: shelf, size: 2_000)
        XCTAssertEqual(keptNumbers(shelf), [2, 3, 4], "9,000 bytes would have been 11,000")
        keep(5, on: shelf, size: 4_001)
        XCTAssertEqual(keptNumbers(shelf), [2, 3, 4], "over the largest: nothing kept or taken")
        XCTAssertEqual(shelf.letters.records.reduce(0) { $0 + $1.bytes }, 8_000)

        MailShelf.wipe(root: kept)
        let app = self.shelf()
        app.letters.keep(Data(count: (5 << 20) + 1), in: Self.inbox, validity: 1, uid: 9,
                         message: message(9))
        app.letters.keep(Data(repeating: 7, count: 5 << 20), in: Self.inbox, validity: 1, uid: 10,
                         message: message(10))
        XCTAssertEqual(app.letters.records.map(\.uid), [10], "5 MB is kept, a byte more is not")
    }

    // MARK: - The check at every read

    /// A file changed by a byte, cut short, grown or missing is nothing,
    /// and goes, record and file, saying so; the rest stay and read.
    func testAFileChangedCutShortGrownOrMissingIsNothingAndGoes() throws {
        let shelf = shelf()
        for n in 1...5 { keep(n, on: shelf) }
        XCTAssertEqual(keptNumbers(shelf), [1, 2, 3, 4, 5])
        var changed = raw(1)
        changed[changed.count - 3] ^= 0x01
        try changed.write(to: file(1, on: shelf))
        try raw(2).prefix(500).write(to: file(2, on: shelf))
        try (raw(3) + Data("more".utf8)).write(to: file(3, on: shelf))
        try FileManager.default.removeItem(at: file(4, on: shelf))

        for n in 1...4 { XCTAssertNil(read(n, on: shelf), "letter \(n)") }
        XCTAssertEqual(read(5, on: shelf), raw(5))
        XCTAssertEqual(keptNumbers(shelf), [5])
        XCTAssertEqual(names(in: shelf.letters.files), [file(5, on: shelf).lastPathComponent])
        XCTAssertEqual(letterNotes.filter { !$0.hasPrefix("KEPT-LETTER kept") },
                       Array(repeating: "KEPT-LETTER dropped reason=check", count: 4))
        shelf.flush()
        XCTAssertEqual(keptNumbers(self.shelf()), [5], "and the index says so")
    }

    /// A changed byte with the CRC-32 alone to find it: the size is right.
    func testAChangedByteIsFoundByTheCRCAlone() throws {
        let shelf = shelf()
        keep(1, on: shelf)
        XCTAssertEqual(keptNumbers(shelf), [1])
        var changed = raw(1)
        changed[40] = changed[40] == 65 ? 66 : 65
        XCTAssertEqual(changed.count, raw(1).count)
        try changed.write(to: file(1, on: shelf))
        XCTAssertNil(read(1, on: shelf))
        XCTAssertEqual(keptNumbers(shelf), [])
    }

    // MARK: - A bad index

    /// `letters.json` of another format, cut short, or not JSON at all:
    /// nothing is kept, the index and every letter's file go at the first
    /// use, and a keep after works as on a launch with nothing kept.
    func testAnIndexOfAnotherFormatOrADamagedOneIsNothingKeptAndTheFilesGo() throws {
        for damage in ["format", "cut", "garbage"] {
            let writing = shelf()
            for n in 1...3 { keep(n, on: writing) }
            writing.flush()
            let index = writing.directory.appendingPathComponent("letters.json")
            let whole = try Data(contentsOf: index)
            switch damage {
            case "format":
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: whole) as? [String: Any])
                object["format"] = KeptLetters.format + 1
                try JSONSerialization.data(withJSONObject: object).write(to: index)
            case "cut":
                try whole.prefix(whole.count / 2).write(to: index)
            default:
                try Data("not json".utf8).write(to: index)
            }

            let next = shelf()
            XCTAssertNil(read(1, on: next), damage)
            XCTAssertEqual(keptNumbers(next), [], damage)
            XCTAssertFalse(FileManager.default.fileExists(atPath: index.path), damage)
            XCTAssertEqual(names(in: next.letters.files), [], damage)
            keep(4, on: next)
            XCTAssertEqual(read(4, on: next), raw(4), damage)
            next.flush()
            XCTAssertEqual(keptNumbers(shelf()), [4], damage)
            MailShelf.wipe(root: kept)
        }
    }

    /// The index is read within its rules, whatever is in it: a record
    /// naming a file that is not its own, one for a letter twice, and more
    /// letters than are kept. The records are dropped and the files swept.
    func testAnIndexOutsideTheRulesIsReadWithinThem() throws {
        let writing = shelf()
        for n in 1...4 { keep(n, on: writing) }
        writing.flush()
        let index = writing.directory.appendingPathComponent("letters.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: index))
                                    as? [String: Any])
        var letters = try XCTUnwrap(object["letters"] as? [[String: Any]])
        letters[0]["file"] = "../../folders.json"
        letters.append(letters[1])
        object["letters"] = letters
        try JSONSerialization.data(withJSONObject: object).write(to: index)

        let next = shelf(options: small(letters: 2))
        XCTAssertEqual(keptNumbers(next), [3, 4])
        XCTAssertNil(read(1, on: next))
        XCTAssertNil(read(2, on: next), "past the bound, the oldest go")
        XCTAssertEqual(read(4, on: next), raw(4))
        XCTAssertEqual(names(in: next.letters.files).count, 2)
    }

    // MARK: - The first use

    /// At the first use of a launch, every file in `letters/` that no record
    /// names goes, an atomic write's leftover among them, and every record
    /// whose file is missing is dropped. Nothing is read before then: a
    /// shelf made over them touches nothing.
    func testFilesNoRecordNamesGoAtTheFirstUseAndRecordsWithoutFilesAreDropped() throws {
        let writing = shelf()
        for n in 1...3 { keep(n, on: writing) }
        writing.flush()
        let files = writing.letters.files
        let stray = files.appendingPathComponent(KeptLetters.fileName(Self.inbox, 1, 1_009, message(9)))
        try raw(9).write(to: stray)
        try Data("half".utf8).write(to: files.appendingPathComponent(".letter.tmp-1"))
        try FileManager.default.removeItem(at: file(2, on: writing))

        let next = shelf()
        XCTAssertEqual(names(in: files).count, 4, "nothing touched as the shelf is made")
        XCTAssertEqual(keptNumbers(next), [1, 3])
        XCTAssertEqual(names(in: files), [file(1, on: next), file(3, on: next)]
                        .map(\.lastPathComponent).sorted())
        XCTAssertNil(next.letters.letter(in: Self.inbox, validity: 1, uid: 1_009,
                                         message: message(9), touch: false))
        next.flush()
        XCTAssertEqual(keptNumbers(shelf()), [1, 3], "and the index written without the missing one")
    }

    /// A relaunch, a new shelf over the same root, reads them back in the
    /// order they were opened, and the counter goes on from there: a letter
    /// kept now is the newest.
    func testARelaunchReadsThemBackInTheOrderTheyWereOpenedAndTheCounterGoesOn() {
        let first = shelf()
        for n in 1...4 { keep(n, on: first) }
        XCTAssertNotNil(read(2, on: first, touch: true))
        XCTAssertNotNil(read(1, on: first, touch: true))
        first.flush()

        let second = shelf()
        XCTAssertEqual(keptNumbers(second), [3, 4, 2, 1])
        keep(5, on: second)
        XCTAssertNotNil(read(3, on: second, touch: true))
        second.flush()
        XCTAssertEqual(keptNumbers(shelf()), [4, 2, 1, 5, 3])
        let opened = shelf().letters.records.map(\.opened)
        XCTAssertEqual(opened, opened.sorted())
        XCTAssertEqual(Set(opened).count, opened.count)
    }

    // MARK: - Thrown away

    /// A password saved, the account taken out, or a safe start: the wipe
    /// takes the letters with `Kept/`, the shelf that was running keeps and
    /// shows none after it, and a keep on its way when it came lands
    /// nowhere. The next shelf starts with none.
    func testAWipeTakesThemAndAKeepOnItsWayLandsNowhere() {
        let queue = DispatchQueue(label: "KeptLettersTests.wipe", target: MailShelf.disk)
        var options = KeptLetters.Options()
        options.disk = queue
        let running = shelf(options: options)
        keep(1, on: running)
        XCTAssertEqual(read(1, on: running), raw(1))

        queue.suspend()
        keep(2, on: running)
        MailShelf.wipe(root: kept)
        queue.resume()
        XCTAssertNil(read(1, on: running))
        XCTAssertNil(read(2, on: running))
        running.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: kept.path), "the keep landed nowhere")
        keep(3, on: running)
        running.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: kept.path), "and keeps nothing more")

        let next = shelf()
        XCTAssertEqual(keptNumbers(next), [])
        keep(4, on: next)
        XCTAssertEqual(read(4, on: next), raw(4))
    }

    /// A first page that disowns the copy takes the letters with it, from
    /// memory and from the disk, and a keep on its way when it came lands
    /// nowhere. The shelf goes on keeping after it.
    func testADiscardTakesThemAndAKeepOnItsWayLandsNowhere() {
        let queue = DispatchQueue(label: "KeptLettersTests.discard", target: MailShelf.disk)
        var options = KeptLetters.Options()
        options.disk = queue
        let shelf = shelf(options: options)
        shelf.took(page: [], of: Self.inbox, validity: 1)
        keep(1, on: shelf)
        XCTAssertEqual(read(1, on: shelf), raw(1))

        queue.suspend()
        keep(2, on: shelf)
        XCTAssertEqual(shelf.took(page: [], of: Self.inbox, validity: 2), .renumbered)
        queue.resume()
        XCTAssertNil(read(1, on: shelf))
        XCTAssertNil(read(2, on: shelf))
        XCTAssertEqual(keptNumbers(shelf), [])
        XCTAssertEqual(names(in: shelf.letters.files), [], "the keep landed nowhere")

        keep(3, on: shelf)
        XCTAssertEqual(read(3, on: shelf), raw(3))
        shelf.flush()
        XCTAssertEqual(keptNumbers(self.shelf()), [3])
    }

    /// The discard that comes while a keep's files are being written: the
    /// files are on the disk, the index not yet in memory, and the discard
    /// empties memory and waits on the disk queue for the keep to finish.
    /// The keep looks at the epoch again before memory takes its index, so
    /// it takes nothing, and the directory goes after it with its files.
    func testADiscardBetweenAKeepsFilesAndItsMemoryLeavesNothing() throws {
        let written = DispatchSemaphore(value: 0)
        let go = DispatchSemaphore(value: 0)
        let holding = HeldFlag()
        var options = KeptLetters.Options()
        options.afterFiles = {
            guard holding.isSet else { return }
            written.signal()
            go.wait()
        }
        let shelf = shelf(options: options)
        shelf.took(page: [], of: Self.inbox, validity: 1)
        keep(1, on: shelf)
        XCTAssertEqual(read(1, on: shelf), raw(1))
        let before = shelf.letters.epochNow

        holding.set()
        keep(2, on: shelf)
        written.wait()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file(2, on: shelf).path))
        let discarded = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = shelf.took(page: [], of: Self.inbox, validity: 2)
            discarded.signal()
        }
        // The discard empties memory first, then waits on the disk queue.
        var waited = 0
        while shelf.letters.epochNow == before, waited < 2_000 {
            usleep(1_000)
            waited += 1
        }
        XCTAssertNotEqual(shelf.letters.epochNow, before, "the discard forgot the letters")
        go.signal()
        discarded.wait()
        holding.clear()

        XCTAssertNil(read(2, on: shelf))
        XCTAssertNil(read(1, on: shelf))
        XCTAssertEqual(keptNumbers(shelf), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(2, on: shelf).path))
        XCTAssertEqual(letterNotes.filter { $0.hasPrefix("KEPT-LETTER kept") }.count, 1,
                       "it said it kept the first, and never the second")
    }

    /// Another account's letters go as the shelf is made, with its pages.
    func testAnotherAccountsLettersGoAsTheShelfIsMade() {
        let theirs = shelf(for: "carlo@example.org")
        keep(1, on: theirs)
        theirs.flush()
        XCTAssertEqual(names(in: theirs.letters.files).count, 1)
        let mine = shelf()
        XCTAssertFalse(FileManager.default.fileExists(atPath: theirs.directory.path))
        XCTAssertNil(read(1, on: mine))
        XCTAssertNotEqual(mine.directory, theirs.directory)
    }

    // MARK: - The floor

    /// A letter that would leave the iPad under 512 MB free is not kept,
    /// the kept letters all go, said once, and nothing more is kept in that
    /// launch even with room again. The next launch keeps. Free space that
    /// cannot be read keeps.
    func testUnderTheFloorNothingIsKeptTheLettersGoAndNothingMoreIsKeptThatLaunch() {
        let free = Measure(Int64(512 << 20) + 1_000)
        var options = KeptLetters.Options()
        options.freeSpace = { free.value }
        let shelf = shelf(options: options)
        keep(1, on: shelf)
        XCTAssertEqual(read(1, on: shelf), raw(1))

        free.value = Int64(512 << 20) + 500
        keep(2, on: shelf)
        XCTAssertNil(read(2, on: shelf))
        XCTAssertNil(read(1, on: shelf), "the letters given back")
        XCTAssertFalse(FileManager.default.fileExists(atPath: shelf.letters.files.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: shelf.directory.appendingPathComponent("letters.json").path))

        free.value = Int64(4) << 30
        keep(3, on: shelf)
        XCTAssertNil(read(3, on: shelf), "nothing more in that launch")
        XCTAssertEqual(letterNotes.filter { $0.hasPrefix("KEPT-LETTER cleared") },
                       ["KEPT-LETTER cleared reason=space"])

        let next = self.shelf(options: options)
        keep(4, on: next)
        XCTAssertEqual(read(4, on: next), raw(4))

        var unknown = KeptLetters.Options()
        unknown.freeSpace = { nil }
        let unread = self.shelf(options: unknown)
        keep(5, on: unread)
        XCTAssertEqual(read(5, on: unread), raw(5), "nil free space keeps")
    }

    /// The note of a keep that read the free space, as the first keep of a
    /// launch does (B-136), gives the reading's own time beside the keep's
    /// whole time, so the iPad's check can tell what the reading costs from
    /// what the write costs. And the app's reading makes its
    /// URLs afresh each time, read from the source since the reading is
    /// iOS's: a URL held from one reading to the next can answer from what
    /// it read the first time.
    func testTheKeptNoteTimesTheFreeSpaceReadingOnItsOwnAndEachReadingIsAfresh() throws {
        var options = KeptLetters.Options()
        options.freeSpace = {
            Thread.sleep(forTimeInterval: 0.05)
            return Int64(4) << 30
        }
        let shelf = shelf(options: options)
        keep(1, on: shelf)
        XCTAssertEqual(read(1, on: shelf), raw(1))
        let note = try XCTUnwrap(letterNotes.first { $0.hasPrefix("KEPT-LETTER kept") })
        let fields = Dictionary(uniqueKeysWithValues: note.split(separator: " ").dropFirst(2)
            .compactMap { field -> (String, Int)? in
                let pair = field.split(separator: "=")
                guard pair.count == 2, let n = Int(pair[1]) else { return nil }
                return (String(pair[0]), n)
            })
        XCTAssertEqual(Set(fields.keys), ["bytes", "ms", "free-ms"], note)
        let reading = try XCTUnwrap(fields["free-ms"], note)
        XCTAssertGreaterThanOrEqual(reading, 50, note)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(fields["ms"]), reading, note)

        let letters = try source("Mail/KeptLetters.swift")
        let app = try section(of: letters,
                              from: "static func freeSpace(near root: URL) -> @Sendable () -> Int64? {",
                              to: "#else")
        let closure = try section(of: app, from: "return {", to: "return nil")
        XCTAssertTrue(closure.contains("let kept = URL(fileURLWithPath: path, isDirectory: true)"))
        XCTAssertFalse(closure.contains("root"), "the URL made once and held")
    }

    // MARK: - The reading held (B-136)

    /// Options reading the free space as `free` says, each reading counted
    /// in `readings`, at a clock in seconds that the test moves.
    private func held(free: Measure, readings: Measure, clock: Measure,
                      unreadable: Bool = false) -> KeptLetters.Options {
        var options = KeptLetters.Options()
        options.freeSpace = {
            readings.value += 1
            return unreadable ? nil : free.value
        }
        options.now = { Date(timeIntervalSince1970: TimeInterval(clock.value)) }
        return options
    }

    /// Letter `n` kept, and its turn on the disk queue waited for, so the
    /// clock the test moves next is after it.
    private func keepNow(_ n: Int, on shelf: MailShelf, size: Int = 600) {
        keep(n, on: shelf, size: size)
        _ = shelf.letters.records
    }

    /// Which kept notes read the free space, in order.
    private var keptReading: [Bool] {
        letterNotes.filter { $0.hasPrefix("KEPT-LETTER kept") }.map { $0.contains(" free-ms=") }
    }

    /// With room to spare, the free space is read at the first keep of a
    /// launch and held: not read again until a keep five minutes after the
    /// reading, then held again; the next launch reads at its first keep.
    /// Only a keep that read it gives `free-ms`. A 5 MB letter is not large
    /// beside gigabytes free.
    func testTheFreeSpaceIsReadAtALaunchsFirstKeepAndAgainAfterFiveMinutes() {
        XCTAssertEqual(KeptLetters.Bounds().freeAge, 5 * 60)
        XCTAssertEqual(KeptLetters.Bounds().freeRoom, 1 << 30)
        let free = Measure(Int64(8) << 30), readings = Measure(0), clock = Measure(1_790_000_000)
        let options = held(free: free, readings: readings, clock: clock)
        let shelf = shelf(options: options)
        keepNow(1, on: shelf)
        XCTAssertEqual(readings.value, 1)
        clock.value += 60
        keepNow(2, on: shelf, size: 5 << 20)
        clock.value += 239
        keepNow(3, on: shelf)
        XCTAssertEqual(readings.value, 1, "held for 299 s")
        clock.value += 1
        keepNow(4, on: shelf)
        XCTAssertEqual(readings.value, 2, "read again at five minutes")
        clock.value += 299
        keepNow(5, on: shelf)
        XCTAssertEqual(readings.value, 2)
        XCTAssertEqual(keptNumbers(shelf), [1, 2, 3, 4, 5])
        XCTAssertEqual(read(2, on: shelf)?.count, 5 << 20)
        XCTAssertEqual(keptReading, [true, false, false, true, false])

        let next = self.shelf(options: options)
        keepNow(6, on: next)
        XCTAssertEqual(readings.value, 3, "the next launch's first keep")
    }

    /// A clock set back past the reading reads again, and the new reading
    /// is held from the time it was taken.
    func testAClockSetBackReadsAgain() {
        let free = Measure(Int64(8) << 30), readings = Measure(0), clock = Measure(1_790_000_000)
        let shelf = shelf(options: held(free: free, readings: readings, clock: clock))
        keepNow(1, on: shelf)
        clock.value -= 3_600
        keepNow(2, on: shelf)
        XCTAssertEqual(readings.value, 2)
        clock.value += 60
        keepNow(3, on: shelf)
        XCTAssertEqual(readings.value, 2)
        XCTAssertEqual(keptNumbers(shelf), [1, 2, 3])
    }

    /// The reading answers only with a gigabyte to spare above the floor
    /// after every letter kept since it and the letter now: 2,000 bytes
    /// more than that hold for three letters of 600 and not a fourth, and
    /// a letter of 3,000 reads first. A gigabyte or less above the floor,
    /// every keep reads, as every keep did, and one that would leave less
    /// than the floor clears the letters as before.
    func testNearTheFloorTheLettersKeptSinceAndALargeLetterReadAgain() {
        let floor = KeptLetters.Bounds().floor, room = KeptLetters.Bounds().freeRoom
        let free = Measure(floor + room + 2_000), readings = Measure(0), clock = Measure(1_790_000_000)
        let shelf = shelf(options: held(free: free, readings: readings, clock: clock))
        for n in 1...4 { keepNow(n, on: shelf) }
        XCTAssertEqual(readings.value, 2)
        XCTAssertEqual(keptReading, [true, false, false, true])
        keepNow(5, on: shelf, size: 3_000)
        XCTAssertEqual(readings.value, 3, "large beside the room left")
        XCTAssertEqual(keptNumbers(shelf), [1, 2, 3, 4, 5])

        free.value = floor + room
        for n in 6...8 { keepNow(n, on: shelf) }
        XCTAssertEqual(readings.value, 6, "every keep near the floor reads")
        free.value = floor + 500
        keepNow(9, on: shelf)
        XCTAssertEqual(readings.value, 7)
        XCTAssertEqual(keptNumbers(shelf), [])
        XCTAssertEqual(letterNotes.last, "KEPT-LETTER cleared reason=space")
    }

    /// A write that fails lets the reading held go, though it showed
    /// gigabytes to spare: another app can have filled the disk since. The
    /// next keep reads the free space, finds it under the floor and clears
    /// the letters, as the keep that met the full disk did when every keep
    /// read. So for the letter's file and for the index, each on a shelf
    /// of its own.
    func testAWriteThatFailsLetsTheReadingGoAndTheNextKeepMeetsTheFloor() throws {
        let floor = KeptLetters.Bounds().floor
        let manager = FileManager.default
        for (failing, address) in [("letters", "owner@example.com"),
                                   ("letters.json", "second@example.com")] {
            let free = Measure(Int64(8) << 30), readings = Measure(0)
            let clock = Measure(1_790_000_000)
            let shelf = shelf(for: address,
                              options: held(free: free, readings: readings, clock: clock))
            keepNow(1, on: shelf)
            shelf.flush()
            XCTAssertEqual(readings.value, 1, failing)

            // The disk filled by another app, and the write fails.
            free.value = floor - 1
            let path = shelf.directory.appendingPathComponent(failing)
            let aside = shelf.directory.appendingPathComponent(failing + ".aside")
            try manager.moveItem(at: path, to: aside)
            if failing == "letters" {
                try Data("in the way".utf8).write(to: path)
            } else {
                try manager.createDirectory(at: path, withIntermediateDirectories: false)
            }
            clock.value += 60
            keepNow(2, on: shelf)
            XCTAssertEqual(readings.value, 1, "\(failing): the reading held answered")
            XCTAssertEqual(letterNotes.last, "KEPT-LETTER not-kept reason=disk", failing)

            clock.value += 60
            keepNow(3, on: shelf)
            XCTAssertEqual(readings.value, 2, "\(failing): read again after the failed write")
            XCTAssertEqual(letterNotes.last, "KEPT-LETTER cleared reason=space", failing)
            XCTAssertEqual(keptNumbers(shelf), [], failing)
            XCTAssertNil(read(1, on: shelf), failing)
        }
    }

    /// Free space that cannot be read keeps, as before, and is not asked
    /// again at every keep: held for five minutes as a reading is.
    func testFreeSpaceThatCannotBeReadIsHeldForFiveMinutesToo() {
        let free = Measure(0), readings = Measure(0), clock = Measure(1_790_000_000)
        let shelf = shelf(options: held(free: free, readings: readings, clock: clock,
                                        unreadable: true))
        keepNow(1, on: shelf)
        keepNow(2, on: shelf)
        XCTAssertEqual(readings.value, 1)
        clock.value += 300
        keepNow(3, on: shelf)
        XCTAssertEqual(readings.value, 2)
        XCTAssertEqual(keptNumbers(shelf), [1, 2, 3])
    }

    // MARK: - A disk that will not write

    /// A file where `letters/` goes: the keep writes nothing, and the
    /// letters kept before it are as they were once `letters/` is back.
    func testAWriteThatFailsKeepsNothingAndTheEarlierLettersStillRead() throws {
        let shelf = shelf()
        keep(1, on: shelf)
        XCTAssertEqual(read(1, on: shelf), raw(1))
        let files = shelf.letters.files
        let aside = shelf.directory.appendingPathComponent("aside")
        try FileManager.default.moveItem(at: files, to: aside)
        try Data("in the way".utf8).write(to: files)

        keep(2, on: shelf)
        XCTAssertEqual(keptNumbers(shelf), [1])
        XCTAssertEqual(letterNotes.last, "KEPT-LETTER not-kept reason=disk")

        try FileManager.default.removeItem(at: files)
        try FileManager.default.moveItem(at: aside, to: files)
        XCTAssertEqual(read(1, on: shelf), raw(1))
        XCTAssertNil(read(2, on: shelf))
        shelf.flush()
        XCTAssertEqual(keptNumbers(self.shelf()), [1])
    }

    /// An index that cannot be written takes the new letter's file back,
    /// and leaves the index on disk and in memory as they were.
    func testAnIndexWriteThatFailsTakesTheNewFileBackAndLeavesTheIndexAsItWas() throws {
        let shelf = shelf()
        keep(1, on: shelf)
        XCTAssertEqual(read(1, on: shelf), raw(1))
        shelf.flush()
        let index = shelf.directory.appendingPathComponent("letters.json")
        let aside = shelf.directory.appendingPathComponent("letters.aside")
        try FileManager.default.moveItem(at: index, to: aside)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)

        keep(2, on: shelf)
        XCTAssertEqual(keptNumbers(shelf), [1])
        XCTAssertNil(read(2, on: shelf))
        XCTAssertEqual(names(in: shelf.letters.files), [file(1, on: shelf).lastPathComponent],
                       "its file taken back")
        XCTAssertEqual(read(1, on: shelf), raw(1))

        try FileManager.default.removeItem(at: index)
        try FileManager.default.moveItem(at: aside, to: index)
        XCTAssertEqual(keptNumbers(self.shelf()), [1])
    }

    // MARK: - Keeps waiting for the disk

    /// With the disk queue held, keeps wait counted against 16 MB, and the
    /// one past it is dropped, saying so; the rest are kept once the queue
    /// goes on.
    func testKeepsPastSixteenMegabytesWaitingAreDropped() {
        let queue = DispatchQueue(label: "KeptLettersTests.waiting", target: MailShelf.disk)
        var options = KeptLetters.Options()
        options.disk = queue
        let shelf = shelf(options: options)
        queue.suspend()
        for n in 1...5 { keep(n, on: shelf, size: 4 << 20) }
        XCTAssertEqual(shelf.letters.waitingBytes, 16 << 20)
        XCTAssertEqual(letterNotes, ["KEPT-LETTER not-kept reason=waiting"])
        queue.resume()
        XCTAssertEqual(keptNumbers(shelf), [1, 2, 3, 4])
        XCTAssertEqual(shelf.letters.waitingBytes, 0)
        keep(5, on: shelf, size: 4 << 20)
        XCTAssertEqual(keptNumbers(shelf), [1, 2, 3, 4, 5], "a keep after the wait goes")
    }

    // MARK: - What the server takes away

    /// Taken out of a folder by UID, whatever Gmail id it was kept with:
    /// the letter kept there goes, and the same letter kept in another
    /// folder stays. Binned or marked as spam: every letter kept with its
    /// Gmail id goes but the one in the bin. A move from All Mail to a
    /// label, which the repository sends as no gone, takes nothing.
    func testGoneByUIDAndABinnedLetterFromEveryFolderButTheBin() {
        let shelf = shelf()
        keep(1, on: shelf)
        keep(1, in: Self.allMail, on: shelf)
        keep(2, on: shelf)
        keep(2, in: Self.allMail, on: shelf)
        keep(2, in: Self.trash, on: shelf)
        keep(3, on: shelf)

        shelf.gone("1/1001", from: Self.inbox)
        XCTAssertNil(read(1, on: shelf))
        XCTAssertNotNil(read(1, in: Self.allMail, on: shelf), "out of the Inbox alone")

        shelf.gone("1/1002", letter: message(2), from: Self.inbox, andEveryFolderBut: Self.trash)
        XCTAssertNil(read(2, on: shelf))
        XCTAssertNil(read(2, in: Self.allMail, on: shelf))
        XCTAssertNotNil(read(2, in: Self.trash, on: shelf), "in the bin it went to")
        XCTAssertNotNil(read(3, on: shelf))
        XCTAssertEqual(names(in: shelf.letters.files).count, 3)
        shelf.flush()
        XCTAssertEqual(self.shelf().letters.records.count, 3)
    }

    /// The server has said the UID is not the letter kept: that letter
    /// goes, and another under the same UID with another id stays.
    func testARefusalTakesTheLetterKeptUnderThatUIDAsThatLetter() {
        let shelf = shelf()
        keep(1, on: shelf)
        shelf.letters.keep(raw(5), in: Self.inbox, validity: 1, uid: 1_001, message: message(5))
        shelf.refuse("1/1001", in: Self.inbox, keptAs: message(1))
        XCTAssertNil(read(1, on: shelf))
        XCTAssertEqual(shelf.letters.letter(in: Self.inbox, validity: 1, uid: 1_001,
                                            message: message(5), touch: false), raw(5))
    }

    /// A showing's touch is written behind, and at once by the flush, as
    /// the app goes into the background.
    func testTheFlushWritesTheLettersIndex() throws {
        let shelf = shelf()
        keep(1, on: shelf)
        keep(2, on: shelf)
        XCTAssertNotNil(read(1, on: shelf, touch: true))
        shelf.flush()
        let index = shelf.directory.appendingPathComponent("letters.json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: index))
                                    as? [String: Any])
        XCTAssertEqual(object["format"] as? Int, 1)
        let letters = try XCTUnwrap(object["letters"] as? [[String: Any]])
        let opened = letters.sorted { ($0["opened"] as? Int ?? 0) < ($1["opened"] as? Int ?? 0) }
        XCTAssertEqual(opened.map { $0["uid"] as? Int }, [1_002, 1_001])
        XCTAssertEqual(Set(letters[0].keys),
                       ["folder", "validity", "uid", "message", "bytes", "crc", "opened", "file"])
        XCTAssertEqual(letters.first { $0["uid"] as? Int == 1_001 }?["message"] as? UInt64,
                       message(1))
    }

    // MARK: - The shelf's life

    /// A shelf nothing else holds is freed, and its letters with it: their
    /// test of the shelf's life holds no shelf.
    func testAShelfIsFreedAndItsLettersWithIt() {
        weak var gone: MailShelf?
        weak var letters: KeptLetters?
        do {
            let shelf = shelf()
            keep(1, on: shelf)
            XCTAssertNotNil(read(1, on: shelf, touch: true))
            shelf.flush()
            gone = shelf
            letters = shelf.letters
        }
        XCTAssertNil(gone)
        XCTAssertNil(letters)
    }

    // MARK: - Out of backup

    /// A store that makes the directories itself, `Kept/`, the account's and
    /// `letters/`, with no page kept first: all three made, and each marked
    /// out of backup as it is made by the helper the shelf's own writes use,
    /// which sets `isExcludedFromBackup`. Read from the source, since the
    /// mark is iOS's.
    func testTheDirectoriesItMakesAreMarkedOutOfBackupByTheShelfsHelper() throws {
        let shelf = shelf()
        keep(1, on: shelf)
        shelf.flush()
        for url in [kept, shelf.directory, shelf.letters.files] {
            var directory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &directory))
            XCTAssertTrue(directory.boolValue)
        }
        XCTAssertEqual(names(in: shelf.directory), ["letters", "letters.json"])

        let letters = try source("Mail/KeptLetters.swift")
        let make = try section(of: letters, from: "private func makeDirectories() throws {",
                               to: "var records: [Record] {")
        XCTAssertTrue(make.contains("for url in [root, directory, files] where "
                                    + "!manager.fileExists(atPath: url.path) {"))
        XCTAssertTrue(make.contains("try manager.createDirectory(at: url, "
                                    + "withIntermediateDirectories: true) MailShelf.excludeFromBackup(url)"))
        let store = try section(of: letters, from: "private func store(", to: "private static func evict(")
        XCTAssertTrue(store.contains("try makeDirectories() try raw.write(to: file, options: .atomic)"))
        let write = try section(of: letters, from: "private func writeIndex() {",
                                to: "private func loadIfNeeded() {")
        XCTAssertTrue(write.contains("try makeDirectories() try JSONEncoder().encode(snapshot)"))
        XCTAssertEqual(letters.components(separatedBy: ".write(to:").count - 1, 3,
                       "the letter, its index, and the index behind")

        let shelfSource = try source("Mail/MailShelf.swift")
        let helper = try section(of: shelfSource, from: "static func excludeFromBackup(_ url: URL) {",
                                 to: "private func record(of folder: String)")
        XCTAssertTrue(helper.contains("values.isExcludedFromBackup = true"))
    }

    // MARK: - The log

    /// Nothing of a letter in the log: its notes say what happened in
    /// numbers alone, never a folder, a UID, a subject or a name.
    func testNothingOfALetterIsWrittenToTheLog() {
        let shelf = shelf(options: small(letters: 1))
        let words = "From: Margaret Example <margaret@example.net>\r\nSubject: The Tuesday visit\r\n\r\n"
            + "Dear Walter, about the orchard.\r\n"
        shelf.letters.keep(Data(words.utf8), in: "Family/Margaret", validity: 77, uid: 4_242,
                           message: 1_888_000_000_000_000_042)
        XCTAssertNotNil(shelf.letters.letter(in: "Family/Margaret", validity: 77, uid: 4_242,
                                             message: 1_888_000_000_000_000_042, touch: true))
        keep(1, on: shelf)
        XCTAssertEqual(keptNumbers(shelf), [1])
        try? Data("x".utf8).write(to: file(1, on: shelf))
        XCTAssertNil(read(1, on: shelf))
        for entry in Diagnostics.entries {
            for word in ["Margaret", "margaret@", "Tuesday", "orchard", "Family", "4242", "1888",
                         "INBOX", "1001", "Walter"] {
                XCTAssertFalse(entry.text.contains(word), entry.text)
            }
        }
        let shape = try? NSRegularExpression(
            pattern: "^KEPT-LETTER (shown|kept|not-kept|dropped|cleared)"
                + "( reason=[a-z]+)?( bytes=[0-9]+)?( ms=[0-9]+)?( free-ms=[0-9]+)?$")
        XCTAssertFalse(letterNotes.isEmpty)
        for note in letterNotes {
            let whole = NSRange(note.startIndex..., in: note)
            XCTAssertEqual(shape?.firstMatch(in: note, range: whole)?.range, whole, note)
        }
    }

    // MARK: - The time a letter takes

    /// A kept 5 MB letter read back and checked, as a showing reads it,
    /// timed fifteen times in the debug build the suite runs, and printed
    /// for PERFORMANCE.md beside the keep's own time. Not asserted, for the
    /// reason the shelf's launch read is not.
    func testAKeptFiveMegabyteLetterReadAndCheckedIsTimed() {
        let shelf = shelf()
        let big = Data((0..<(5 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        let kept = ContinuousClock.now
        shelf.letters.keep(big, in: Self.inbox, validity: 1, uid: 1, message: message(1))
        XCTAssertEqual(shelf.letters.records.count, 1)
        let keeping = ContinuousClock.now - kept
        var times: [Duration] = []
        for _ in 0..<15 {
            let started = ContinuousClock.now
            let read = shelf.letters.letter(in: Self.inbox, validity: 1, uid: 1, message: message(1),
                                            touch: true)
            times.append(ContinuousClock.now - started)
            XCTAssertEqual(read?.count, big.count)
        }
        let median = times.sorted()[times.count / 2]
        print("KeptLetters 5 MB letter: kept in \(keeping); read and checked median \(median), "
              + "fastest \(times.min()!), slowest \(times.max()!)")
    }

    // MARK: - Helpers

    private func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }

    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Blackmail/\(file)")
        let text = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        return flat(text)
    }

    private func section(of code: String, from start: String, to end: String) throws -> String {
        let from = try XCTUnwrap(code.range(of: start), start)
        let to = try XCTUnwrap(code.range(of: end, range: from.upperBound..<code.endIndex), end)
        return String(code[from.lowerBound..<to.lowerBound])
    }
}

/// A flag set and read from any thread.
private final class HeldFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var on = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return on }
    func set() { lock.lock(); on = true; lock.unlock() }
    func clear() { lock.lock(); on = false; lock.unlock() }
}

/// A number a test moves, read from any thread.
private final class Measure: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Int64
    init(_ value: Int64) { current = value }
    var value: Int64 {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); current = newValue; lock.unlock() }
    }
}
