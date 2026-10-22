import XCTest
@testable import Blackmail

/// Mail's recent searches (B-105): three at most, newest first, each kept a
/// week from its last use, in a file of their own that a password saved
/// and a safe start's second stage take away; shown under the search field
/// while it is focused and empty, a tap searching at once.
///
/// The list and its file over a directory made for each test, on a clock
/// the test sets. The band and the list are UIKit, which never builds on
/// this host, so their wiring is read from the source, as
/// `SteadyChromeTests` reads the band's: comment lines out, and runs of
/// white space as one space.
final class RecentSearchesTests: XCTestCase {

    private var base: URL!
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    override func setUpWithError() throws {
        try super.setUpWithError()
        base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("RecentSearchesTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let base { try? FileManager.default.removeItem(at: base) }
        base = nil
        try super.tearDownWithError()
    }

    /// Where the app's would be, `Application Support/`, not yet made.
    private var file: URL {
        base.appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Recent Searches.json")
    }

    private func texts(at now: Date) -> [String] {
        RecentSearches.load(from: file, at: now).map(\.text)
    }

    // MARK: - The list

    /// Three at most, the newest first: a fourth search pushes the oldest
    /// off.
    func testThreeAtMostNewestFirst() {
        XCTAssertEqual(texts(at: start), [])
        for (minute, text) in ["margaret", "garden", "invoice", "birthday"].enumerated() {
            RecentSearches.note(text, at: start + Double(minute) * 60, in: file)
        }
        XCTAssertEqual(texts(at: start + 600), ["birthday", "invoice", "garden"])
        XCTAssertEqual(RecentSearches.most, 3)
        XCTAssertEqual(RecentSearches.load(from: file, at: start + 600).map(\.lastUsed),
                       [start + 180, start + 120, start + 60])
    }

    /// Kept a week from the last use, Mail's 604,800 seconds, and gone a
    /// second after. Used again within the week, a search starts its week
    /// again.
    func testAWeekFromItsLastUse() {
        XCTAssertEqual(RecentSearches.keptFor, 604_800)
        RecentSearches.note("margaret", at: start, in: file)
        RecentSearches.note("garden", at: start + day, in: file)
        XCTAssertEqual(texts(at: start + 7 * day), ["garden", "margaret"])
        XCTAssertEqual(texts(at: start + 7 * day + 1), ["garden"])
        XCTAssertEqual(texts(at: start + 8 * day), ["garden"])
        XCTAssertEqual(texts(at: start + 8 * day + 1), [])

        RecentSearches.note("margaret", at: start + 20 * day, in: file)
        RecentSearches.note("margaret", at: start + 26 * day, in: file)
        XCTAssertEqual(texts(at: start + 33 * day), ["margaret"])
        XCTAssertEqual(texts(at: start + 33 * day + 1), [])
    }

    /// The same words in any case are one search: the newer takes the
    /// older's place, at the top, as he typed it this time.
    func testTheSameWordsInAnyCaseReplaceTheOlder() {
        RecentSearches.note("Margaret", at: start, in: file)
        RecentSearches.note("garden", at: start + 60, in: file)
        RecentSearches.note("MARGARET", at: start + 120, in: file)
        XCTAssertEqual(texts(at: start + 180), ["MARGARET", "garden"])
        RecentSearches.note("  garden \n", at: start + 240, in: file)
        XCTAssertEqual(texts(at: start + 300), ["garden", "MARGARET"])
        // Kept one line: runs of white space one space each.
        RecentSearches.note("plan\n  b", at: start + 360, in: file)
        RecentSearches.note("Plan B", at: start + 420, in: file)
        XCTAssertEqual(texts(at: start + 480), ["Plan B", "garden", "MARGARET"])
    }

    /// A search over 200 characters is not kept, and the ones before it
    /// stand. Two hundred is.
    func testTheTwoHundredCharacterCap() {
        RecentSearches.note("margaret", at: start, in: file)
        let long = String(repeating: "garden ", count: 40)
        RecentSearches.note(long, at: start + 60, in: file)
        XCTAssertEqual(texts(at: start + 120), ["margaret"])
        let most = String(repeating: "é", count: 200)
        RecentSearches.note(most, at: start + 180, in: file)
        XCTAssertEqual(texts(at: start + 240), [most, "margaret"])
        RecentSearches.note(most + "e", at: start + 300, in: file)
        XCTAssertEqual(texts(at: start + 360), [most, "margaret"])
        XCTAssertEqual(RecentSearches.longest, 200)
    }

    /// Blank text is no search, and keeps nothing.
    func testBlankTextIsNotKept() {
        RecentSearches.note("   \n", at: start, in: file)
        RecentSearches.note("", at: start, in: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(texts(at: start), [])
    }

    /// A file that cannot be read is no recent searches: empty, cut short,
    /// another shape, or not JSON. The next search writes it afresh.
    func testACorruptOrEmptyFileIsNoRecentSearches() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        for bytes in ["", "[", "{\"text\":\"margaret\"}", "[{\"text\":7}]", "\u{0}\u{1}garbage",
                      "[{\"text\":\"margaret\",\"lastUsed\":\"yesterday\"}]"] {
            try Data(bytes.utf8).write(to: file)
            XCTAssertEqual(texts(at: start), [], bytes)
        }
        RecentSearches.note("garden", at: start, in: file)
        XCTAssertEqual(texts(at: start), ["garden"])
    }

    /// What is read is held to the rules whatever the file says: a list
    /// written by hand with five entries, a repeat, a blank one and one too
    /// long shows three, once each.
    func testAFileOutsideTheRulesIsReadWithinThem() throws {
        let entries = [
            RecentSearches.Entry(text: "margaret", lastUsed: start),
            RecentSearches.Entry(text: "  ", lastUsed: start),
            RecentSearches.Entry(text: "MARGARET", lastUsed: start),
            RecentSearches.Entry(text: String(repeating: "x", count: 201), lastUsed: start),
            RecentSearches.Entry(text: "garden", lastUsed: start),
            RecentSearches.Entry(text: "invoice", lastUsed: start),
            RecentSearches.Entry(text: "birthday", lastUsed: start),
        ]
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: file)
        XCTAssertEqual(texts(at: start), ["margaret", "garden", "invoice"])
    }

    /// A clock moved back only keeps them longer. The search made after it
    /// is still the newest, first and kept, though its date is before the
    /// others'; theirs, now in the future, are not taken for old.
    func testAClockMovedBackOnlyKeepsThemLonger() {
        RecentSearches.note("margaret", at: start, in: file)
        RecentSearches.note("garden", at: start + 60, in: file)
        RecentSearches.note("invoice", at: start + 120, in: file)
        let back = start - 30 * day
        RecentSearches.note("birthday", at: back, in: file)
        XCTAssertEqual(texts(at: back), ["birthday", "invoice", "garden"])
        XCTAssertEqual(texts(at: back + 7 * day), ["birthday", "invoice", "garden"])
        XCTAssertEqual(texts(at: back + 7 * day + 1), ["invoice", "garden"])
        XCTAssertEqual(texts(at: start + 60 + 7 * day + 1), ["invoice"])
    }

    /// Taken away whole, and a wipe with no file is nothing.
    func testAWipeTakesThemAway() {
        RecentSearches.note("margaret", at: start, in: file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        RecentSearches.wipe(file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(texts(at: start), [])
        RecentSearches.wipe(file)
        XCTAssertEqual(texts(at: start), [])
    }

    /// The words on screen, Mail's, held to his approval: a change is this
    /// line.
    func testTheWords() {
        XCTAssertEqual(RecentSearches.heading, "Recent Searches")
        XCTAssertEqual(RecentSearches.spoken("Plan B"), "Recent search, Plan B")
        XCTAssertEqual(RecentSearches.appFile.lastPathComponent, "Recent Searches.json")
        XCTAssertEqual(RecentSearches.appFile.deletingLastPathComponent(),
                       MailShelf.appRoot.deletingLastPathComponent())
    }

    // MARK: - The file, as written

    /// Written whole or not at all, and out of backup after every write:
    /// an atomic write is a new file, which does not carry the old one's
    /// flag.
    func testTheFileIsWrittenWholeAndKeptOutOfBackup() throws {
        let code = try source("Mail/RecentSearches.swift")
        let write = try XCTUnwrap(place(of: "try JSONEncoder().encode(after).write(to: file, options: .atomic) "
                                            + "excludeFromBackup(file)", in: code))
        XCTAssertNotNil(place(of: "values.isExcludedFromBackup = true var url = url "
                                  + "try? url.setResourceValues(values)", in: code))
        XCTAssertLessThan(try XCTUnwrap(place(of: "static func note(", in: code)), write)
    }

    // MARK: - Where they go

    /// A password saved, and the account taken out, take them away with
    /// the copy of his mail; a safe start's second stage too (run in
    /// `SafeStartTests`), over the app's file.
    func testAPasswordSavedOrTheAccountTakenOutWipesThem() throws {
        let store = try source("Mail/CredentialStore.swift")
        XCTAssertNotNil(place(of: "MailShelf.wipe(root: MailShelf.appRoot) "
                                  + "RecentSearches.wipe(RecentSearches.appFile) "
                                  + "LocalDraftStore.notePasswordSaved(in: LocalDraftStore.appRoot)",
                              in: store))
        XCTAssertNotNil(place(of: "defaults.removeObject(forKey: accountDefaultsKey) "
                                  + "MailShelf.wipe(root: MailShelf.appRoot) "
                                  + "RecentSearches.wipe(RecentSearches.appFile) "
                                  + "ShareMirror.app?.clear()", in: store))
        XCTAssertEqual(count("RecentSearches.wipe(", in: store), 2)
        let start = try source("Mail/SafeStart.swift")
        XCTAssertNotNil(place(of: "if steps.forgetsKeptState { MailShelf.wipe(root: kept) "
                                  + "RecentSearches.wipe(searches)", in: start))
        XCTAssertNotNil(place(of: "searches: RecentSearches.appFile,", in: start))
    }

    // MARK: - The band and the list

    /// Shown only while the field is focused AND empty AND there are some,
    /// asked for afresh each time; the band's height has their rows in it,
    /// and changes as the scope bar's does.
    func testShownOnlyWhileTheFieldIsFocusedAndEmpty() throws {
        let band = try source("UI/SearchHeaderView.swift")
        XCTAssertNotNil(place(of: "let empty = (field.text ?? \"\").isEmpty "
                                  + "let expanded = field.isEditing || !empty "
                                  + "let recents = field.isEditing && empty "
                                  + "? Array((recentSearches?() ?? []).prefix(recentRows.count)) : [] "
                                  + "guard expanded != isExpanded || recents != shownRecents else { return }",
                              in: band))
        XCTAssertNotNil(place(of: "recentHeading.isHidden = recents.isEmpty", in: band))
        XCTAssertNotNil(place(of: "row.isHidden = index >= recents.count", in: band))
        XCTAssertNotNil(place(of: "frame.size.height = wantedHeight setNeedsLayout() onHeightChanged?() }",
                              in: band))
        XCTAssertNotNil(place(of: "Theme.searchBarHeight + (isExpanded ? Theme.searchScopeBarHeight : 0) "
                                  + "+ recentsHeight", in: band))
        XCTAssertNotNil(place(of: "guard !shownRecents.isEmpty else { return 0 } "
                                  + "return Theme.scaled(Theme.searchRecentHeadingHeight) "
                                  + "+ CGFloat(shownRecents.count) * Theme.scaled(Theme.searchRecentRowHeight)",
                              in: band))
        // Asked again at every change of the field: focus, typing, its end,
        // and the clear button.
        for asked in ["@objc private func editingChanged() { updatePlaceholder() refreshExpansion()",
                      "func textFieldDidBeginEditing(_ t: UITextField) { updatePlaceholder() refreshExpansion() }",
                      "func textFieldDidEndEditing(_ t: UITextField) { updatePlaceholder() refreshExpansion() }",
                      "self.updatePlaceholder() self.refreshExpansion()"] {
            XCTAssertNotNil(place(of: asked, in: band))
        }
        XCTAssertNotNil(place(of: "private let recentRows = (0..<RecentSearches.most).map { _ in RecentSearchRow() }",
                              in: band))
        XCTAssertNotNil(place(of: "recentHeading.text = RecentSearches.heading", in: band))
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertNotNil(place(of: "searchBar.recentSearches = { "
                                  + "RecentSearches.load(from: RecentSearches.appFile, at: Date()).map(\\.text) }",
                              in: list))
    }

    /// Each row a button to VoiceOver, called "Recent search," and its
    /// words; its clock a fixed size, as the band's magnifier is.
    func testEachRowIsAButtonCalledRecentSearch() throws {
        let band = try source("UI/SearchHeaderView.swift")
        XCTAssertNotNil(place(of: "private final class RecentSearchRow: UIControl {", in: band))
        XCTAssertNotNil(place(of: "label.text = text accessibilityLabel = RecentSearches.spoken(text)", in: band))
        XCTAssertNotNil(place(of: "isAccessibilityElement = true accessibilityTraits = .button", in: band))
        XCTAssertNotNil(place(of: "UIImage(systemName: \"clock\", withConfiguration: "
                                  + "UIImage.SymbolConfiguration(font: Theme.fontListSubject))", in: band))
    }

    /// A tap puts its words in the field, takes the keyboard down and
    /// tells the list, which searches at once: no wait on the debounce, in
    /// the scope the band shows, through the task a keystroke or Cancel
    /// calls off; and it is the newest search again.
    func testATapSearchesAtOnce() throws {
        let band = try source("UI/SearchHeaderView.swift")
        XCTAssertNotNil(place(of: "@objc private func recentTapped(_ row: RecentSearchRow) { "
                                  + "let text = row.text guard !text.isEmpty else { return } "
                                  + "field.text = text field.resignFirstResponder() updatePlaceholder() "
                                  + "refreshExpansion() onRecentChosen?(text) }", in: band))
        XCTAssertNotNil(place(of: "row.addTarget(self, action: #selector(recentTapped(_:)), for: .touchUpInside)",
                              in: band))
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertNotNil(place(of: "searchBar.onRecentChosen = { [weak self] text in self?.recentChosen(text) }",
                              in: list))
        let chosen = try XCTUnwrap(place(of: "private func recentChosen(_ text: String) { "
                                             + "searchQuery = text searchDebounce?.cancel() keepSearch(text) "
                                             + "searchDebounce = Task { @MainActor [weak self] in "
                                             + "guard !Task.isCancelled else { return } "
                                             + "await self?.runSearch(text) } }", in: list))
        let body = String(list[chosen...].prefix(400))
        XCTAssertFalse(body.contains("searchDelay"), body)
        XCTAssertFalse(body.contains("queryChanged"), body)
        // The scope is the one the band shows: `runSearch` reads it.
        XCTAssertNotNil(place(of: "private func runSearch(_ text: String) async { listGeneration += 1 "
                                  + "let generation = listGeneration let scope = searchScope", in: list))
    }

    /// Search on the keyboard keeps what is in the field; a letter opened
    /// from the results keeps the words whose results they are. Nothing
    /// else keeps one, a keystroke least of all.
    func testSearchOnTheKeyboardAndALetterOpenedKeepTheSearch() throws {
        let band = try source("UI/SearchHeaderView.swift")
        XCTAssertNotNil(place(of: "func textFieldShouldReturn(_ t: UITextField) -> Bool { "
                                  + "t.resignFirstResponder() onSearchKey?(t.text ?? \"\") return true }",
                              in: band))
        XCTAssertEqual(count("onSearchKey?(", in: band), 1)
        let list = try source("UI/MessageListViewController.swift")
        XCTAssertNotNil(place(of: "searchBar.onSearchKey = { [weak self] text in self?.keepSearch(text) }",
                              in: list))
        XCTAssertNotNil(place(of: "guard !t.isEditing else { updateSelectAllTitle(); return } "
                                  + "if letters.isSearching { keepSearch(searchShown) }", in: list))
        XCTAssertNotNil(place(of: "searchFailed = false searchShown = text let move = showingResults() "
                                  + "letters.showResults(hits)", in: list))
        XCTAssertNotNil(place(of: "private func keepSearch(_ text: String) { "
                                  + "RecentSearches.note(text, at: Date(), in: RecentSearches.appFile) }",
                              in: list))
        XCTAssertEqual(count("keepSearch(", in: list), 4, "the three callers and the function")
        XCTAssertEqual(count("RecentSearches.note(", in: list), 1)
        // Not at a keystroke.
        let typed = try XCTUnwrap(place(of: "private func queryChanged(_ text: String) {", in: list))
        let rest = String(list[typed...].prefix(700))
        XCTAssertFalse(rest.contains("keepSearch"), rest)
    }

    // MARK: - Reading the source

    /// `path` is under `Sources/Blackmail`.
    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    /// Where `text` first is in `code`, failing if it is not there.
    private func place(of text: String, in code: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String.Index? {
        let found = code.range(of: text)?.lowerBound
        XCTAssertNotNil(found, text, file: file, line: line)
        return found
    }

    private func count(_ text: String, in code: String) -> Int {
        code.components(separatedBy: text).count - 1
    }
}
