import Foundation

/// The red number on the app's icon and the banners for new mail, as Apple
/// Mail gives them from the factory (B-161).
///
/// Mail puts the number of unread letters in the Inbox on its icon, and a
/// banner for each new letter while it is not in front: the sender as its
/// title, the subject under it and the first words of the letter, a tap on
/// it opening that letter. It shows no banner for mail that comes while it
/// is in front. His Gmail account is fetched, not pushed (Gmail offers Mail
/// no push), and Mail's factory Fetch, Automatically, fetches in the
/// background only while the iPad is charging and on Wi-Fi (Apple's support
/// article 102578): from the factory, his banners and number change while
/// he is away only then.
///
/// Blackmail has no server and nothing pushes to it, so it is iOS's own
/// background refresh that wakes it, when iOS chooses (`interval`), and it
/// checks only on charge and Wi-Fi, as Mail fetches (`NewMailTask`): one
/// check on a short connection of its own (`InboxCheck`), a banner for each
/// unread letter that reached the Inbox after he left the app, and the
/// Inbox's unread count on the icon. In front, the number follows the
/// folder pane's count for the Inbox (`AppBadge`). Both need his yes to
/// iOS's own question, asked once (`BannerQuestion`); with a no there is
/// neither, and no check is made.
///
/// Out here, and not with the UIKit half that registers the check and
/// posts the banners (`NewMailTask`), so the suite runs the check against
/// the scripted server as the app runs it.
enum NewMailBanners {

    /// The check's name for iOS. Info.plist lists it under
    /// `BGTaskSchedulerPermittedIdentifiers`, and iOS ends, at every launch,
    /// an app that registers a name the list does not have.
    static let taskIdentifier = "wtf.uhoh.blackmail.new-mail"

    /// The soonest the next check is asked for, after he leaves the app and
    /// after each check. iOS decides when it runs, from how he uses the
    /// app, the battery and the network, and may leave it for hours; Low
    /// Power Mode, and Background App Refresh switched off, leave it out.
    static let interval: TimeInterval = 15 * 60

    /// How long a check may take before it is ended. iOS gives an app
    /// refresh about thirty seconds and ends an app that overruns them.
    static let allowance: TimeInterval = 25

    /// At most this many banners from one check, for the newest letters:
    /// after a day away, a banner for every letter would be a column of
    /// them for mail he will see on the list. A departure from Mail, which
    /// puts one up for every letter and lets iOS stack them.
    static let most = 20

    /// The longest line of a letter's words a banner carries. iOS cuts the
    /// banner to its few lines itself.
    static let longestLine = 400

    /// A banner for one new letter, as Mail's says it.
    struct Banner: Equatable {
        /// The letter's id on the Inbox's list, "<uidvalidity>/<uid>".
        var id: String
        /// Gmail's id for it, when the server gave one.
        var gmailMessageID: UInt64?
        /// Who it is from, as the list's row names them.
        var title: String
        /// Its subject, or the row's words for none.
        var subtitle: String
        /// The first of its words, as the row's grey lines have them.
        var body: String

        /// What a tap on it hands back (`Tapped`): strings alone, as a
        /// banner's user info is kept.
        var userInfo: [String: String] {
            var info = [Tapped.letterKey: id]
            if let gmailMessageID { info[Tapped.gmailKey] = String(gmailMessageID) }
            return info
        }

        /// iOS's name for it: a second banner for the same letter takes the
        /// first one's place rather than standing beside it.
        var identifier: String { "INBOX/" + id }
    }

    /// The letter a tapped banner names.
    struct Tapped: Equatable {
        static let letterKey = "blackmail.letter"
        static let gmailKey = "blackmail.gmail"

        var id: String
        var gmailMessageID: UInt64?

        init(id: String, gmailMessageID: UInt64?) {
            self.id = id
            self.gmailMessageID = gmailMessageID
        }

        /// Nil for a banner this app did not make, or whose letter is not
        /// named as a row of the Inbox's list is.
        init?(userInfo: [AnyHashable: Any]) {
            guard let id = userInfo[Self.letterKey] as? String else { return nil }
            let parts = id.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, UInt32(parts[0]) != nil, UInt32(parts[1]) != nil else {
                return nil
            }
            self.id = id
            gmailMessageID = (userInfo[Self.gmailKey] as? String).flatMap { UInt64($0) }
        }
    }

    /// The banner for a letter, from its summary as FETCH gives it and the
    /// line of words fetched for it.
    static func banner(id: String, gmailMessageID: UInt64?, envelope: IMAPEnvelope?,
                       preview: String) -> Banner {
        let sender = envelope?.from.first?.formatted ?? "(unknown sender)"
        let subject = envelope?.subject ?? ""
        let words = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return Banner(id: id, gmailMessageID: gmailMessageID,
                      title: MailFormat.displayName(sender),
                      subtitle: subject.isEmpty ? "(no subject)" : subject,
                      body: String(words.prefix(longestLine)))
    }
}

/// iOS's own question, whether the app may put up banners and a number on
/// its icon, asked once, the first time the Inbox's list has come, at a
/// moment that interrupts nothing: with nothing over the mail, no finger
/// on the list, and the app in front. Until then it waits for the next
/// check of the watch, half a minute on, as the warning before the app
/// stops opening waits (B-137). Once iOS has an answer, yes or no, it is
/// never asked again: iOS asks only once in any case.
struct BannerQuestion: Equatable {

    /// iOS has an answer, or the question is up.
    private(set) var settled = false

    /// Whether the question goes now. `inboxListed`: the Inbox's list is in
    /// front, fetched from the server from its newest letter.
    mutating func due(inboxListed: Bool, sheetUp: Bool, inHand: Bool, inFront: Bool) -> Bool {
        guard !settled, inboxListed, !sheetUp, !inHand, inFront else { return false }
        settled = true
        return true
    }
}

/// The red number on the app's icon (B-161): the Inbox's unread count, as
/// the folder pane shows it, set each time the app learns it, a sweep of
/// the counts landing, a read mark, and set again as he leaves; the check
/// in the background sets it from the server's count. A count not known
/// sets nothing: the number stays as last set rather than going.
@MainActor
final class AppBadge {

    private let set: (Int) -> Void
    /// The count last set, nil before any.
    private(set) var known: Int?

    /// `set` puts the number on the icon; the app's asks iOS
    /// (`AppBadge.app`), a test's writes it down.
    init(set: @escaping (Int) -> Void) {
        self.set = set
    }

    func counted(_ unread: Int?) {
        guard let unread else { return }
        let count = max(0, unread)
        known = count
        set(count)
    }

    /// The last count set again: as he leaves the app, and once he has
    /// said yes to iOS's question, which a count set before it never
    /// reached.
    func again() {
        guard let known else { return }
        set(known)
    }
}

/// The Inbox's highest letter a check has looked at, by its UID under the
/// UIDVALIDITY it was given in.
struct InboxMark: Codable, Equatable {
    var validity: UInt32
    var uid: UInt32
}

/// What the checks keep between them, and what the app tells them.
struct BannerState: Codable, Equatable {
    /// Where the last check left the Inbox: only letters above it are new
    /// to the next.
    var mark: InboxMark?
    /// When the app last went from in front of him. A letter that reached
    /// the Inbox before then was on the list, or could have been, and has
    /// no banner, as Mail puts up none for mail that comes while it is in
    /// front. None before the app has ever been left: no banner at all.
    var leftAt: Date?
    /// A check's sign-in refused: no check signs in again until he has
    /// been back in the app, where the refusal is said and mended.
    var refusedAt: Date?
    /// When a check last had the Inbox's count from the server.
    var checkedAt: Date?

    /// A check has had the count since he left: the counts are swept as he
    /// comes back, so the folder pane and the number agree with the server.
    var checkedSinceLeaving: Bool {
        guard let checkedAt else { return false }
        return leftAt.map { checkedAt > $0 } ?? true
    }
}

/// `BannerState` in a file of its own, written whole or not at all, out of
/// his backup: `Application Support/New Mail/state.json`. A file and not
/// `UserDefaults`, for `SafeStart`'s reason: the mark is written before a
/// letter is fetched, so a letter that ends the check is not fetched again,
/// and a write to the defaults can be lost to the crash it is there for.
final class BannerStore: @unchecked Sendable {

    let file: URL
    private let lock = NSLock()

    init(file: URL) {
        self.file = file
    }

    static let app = BannerStore(file: appFile)

    static var appFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("New Mail", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    /// What is kept, or nothing kept when the file is not there or cannot
    /// be read: the next check then looks, as the first one does.
    func load() -> BannerState {
        lock.lock()
        defer { lock.unlock() }
        return read()
    }

    /// `change` made to what is kept, and written.
    func update(_ change: (inout BannerState) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var state = read()
        change(&state)
        let files = FileManager.default
        let folder = file.deletingLastPathComponent()
        if !files.fileExists(atPath: folder.path) {
            try? files.createDirectory(at: folder, withIntermediateDirectories: true)
            #if os(iOS)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = folder
            try? url.setResourceValues(values)
            #endif
        }
        guard let data = try? Self.encoder.encode(state) else { return }
        try? data.write(to: file, options: .atomic)
    }

    private func read() -> BannerState {
        guard let data = try? Data(contentsOf: file),
              let state = try? Self.decoder.decode(BannerState.self, from: data) else {
            return BannerState()
        }
        return state
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// One check of the Inbox for new mail, made while the app is in the
/// background (B-161), on a connection of its own that it closes as it
/// ends: never the app's, which may be in the middle of something.
///
/// What it sends: LOGIN, and `STATUS "INBOX" (UNSEEN UIDNEXT
/// UIDVALIDITY)`, the count for the icon and how far the Inbox goes. With
/// nothing above the last check's mark, that is all, and LOGOUT. Above it,
/// a SELECT of the Inbox and `UID SEARCH UNSEEN UID n:*`, the unread
/// letters above the mark, or after the first check and a renumbered Inbox
/// `UNSEEN SINCE` the day before he left; a `UID FETCH` of the newest
/// `most` letters' summaries, and of the first of their words, PEEK, as
/// the list fetches its previews. Nothing marks a letter read, moves it or
/// writes anything: no STORE, MOVE, EXPUNGE or APPEND, and no SMTP. Nothing
/// it fetches is kept, the copy of his mail and the address book included.
///
/// The mark is written as soon as STATUS has said how far the Inbox goes,
/// before any letter is fetched: a letter whose summary ends the check is
/// never fetched by a check again, and a letter is bannered once. So a
/// letter a check had passed when it was ended, at its allowance on a slow
/// network or as he opened the app, never has a banner.
///
/// A banner only for a letter still unread, that reached the Inbox after
/// he last left the app (`BannerState.leftAt`): mail that came while he was
/// in the app was on the list, as in Mail, which puts up no banner for it.
///
/// A sign-in refused is not tried again until he has been back in the app
/// (`BannerState.refusedAt`): Gmail locks out an account that keeps
/// failing to sign in, and the app's own checks never send a refused
/// password again either.
struct InboxCheck {

    let account: MailAccount
    let password: String
    let transport: MailTransportFactory
    let store: BannerStore
    var now: @Sendable () -> Date = { Date() }

    /// What a check found.
    struct Found: Equatable {
        /// The Inbox's unread count, for the icon; nil when STATUS gave none.
        var unread: Int?
        /// The new letters' banners, oldest first, so the newest is on top.
        var banners: [NewMailBanners.Banner]
    }

    /// The check, start to end. Nil when nothing was had from the server:
    /// no connection, a refused sign-in, a check called off.
    func run() async -> Found? {
        let state = store.load()
        guard state.refusedAt == nil else {
            Diagnostics.log(.note, "NEW-MAIL held refused-before")
            return nil
        }
        let client = IMAPClient(account: account, transport: transport, now: now)
        do {
            let found = try await check(client, state: state)
            await client.disconnect()
            Diagnostics.log(.note, "NEW-MAIL unread=\(found.unread.map(String.init) ?? "-") "
                            + "banners=\(found.banners.count)")
            return found
        } catch {
            if MailError.refusesSignIn(error) {
                store.update { $0.refusedAt = now() }
                Diagnostics.log(.note, "NEW-MAIL sign-in refused; none until the app is opened")
            } else {
                Diagnostics.log(.note, "NEW-MAIL failed cancelled=\(Task.isCancelled)")
            }
            await client.disconnect()
            return nil
        }
    }

    private func check(_ client: IMAPClient, state: BannerState) async throws -> Found {
        try await client.connect(password: password)
        try Task.checkCancellation()
        let status = try await client.status("INBOX", items: ["UNSEEN", "UIDNEXT", "UIDVALIDITY"])
        let unread = status["UNSEEN"].map { Int($0) }
        guard let validity = status["UIDVALIDITY"], let next = status["UIDNEXT"], next > 1 else {
            store.update { $0.checkedAt = now() }
            return Found(unread: unread, banners: [])
        }
        let highest = next - 1
        let before = state.mark.flatMap { $0.validity == validity ? $0 : nil }
        store.update {
            $0.mark = InboxMark(validity: validity, uid: highest)
            $0.checkedAt = now()
        }
        // Never left the app yet, so nothing has come since: the mark is
        // where the next check starts from.
        guard let left = state.leftAt else { return Found(unread: unread, banners: []) }
        let criteria: String
        if let before {
            guard highest > before.uid else { return Found(unread: unread, banners: []) }
            criteria = "UNSEEN UID \(before.uid + 1):*"
        } else {
            criteria = "UNSEEN SINCE \(IMAPDate.criteriaValue(for: left.addingTimeInterval(-86_400)))"
        }
        try Task.checkCancellation()
        let found = try await client.search(criteria, in: "INBOX")
        // Renumbered between the STATUS and the SELECT: the next check
        // starts afresh from the day he left.
        guard found.validity == validity else { return Found(unread: unread, banners: []) }
        // Not above `highest`: a letter come since the STATUS is above the
        // mark, and the next check's. `n:*` names the highest UID even
        // below `n`, so the mark is applied here as well.
        let newest = found.uids
            .filter { $0 <= highest && $0 > (before?.uid ?? 0) }
            .sorted(by: >)
            .prefix(NewMailBanners.most)
        guard !newest.isEmpty else { return Found(unread: unread, banners: []) }
        try Task.checkCancellation()
        let fetched = try await client.fetchSummaries(uids: Array(newest), in: "INBOX",
                                                      validity: validity)
            .filter { r in
                guard r.uid != nil, !r.isSeen, let arrived = r.internalDate else { return false }
                return arrived > left
            }
        guard !fetched.isEmpty else { return Found(unread: unread, banners: []) }
        try Task.checkCancellation()
        let words = await previews(of: fetched, validity: validity, client: client)
        try Task.checkCancellation()
        let banners = fetched
            .sorted { ($0.uid ?? 0) < ($1.uid ?? 0) }
            .compactMap { r -> NewMailBanners.Banner? in
                guard let uid = r.uid else { return nil }
                return NewMailBanners.banner(id: "\(validity)/\(uid)",
                                             gmailMessageID: r.gmailMessageID,
                                             envelope: r.envelope, preview: words[uid] ?? "")
            }
        return Found(unread: unread, banners: banners)
    }

    /// The first of each letter's words, from the part and window the list
    /// takes its grey lines from, one FETCH for each part and window. A
    /// letter whose words could not be had has its banner without them.
    private func previews(of letters: [IMAPFetchResult], validity: UInt32,
                          client: IMAPClient) async -> [UInt32: String] {
        struct Window: Hashable {
            let section: String
            let bytes: Int
        }
        var parts: [UInt32: MIMEPart] = [:]
        var windows: [Window: [UInt32]] = [:]
        for r in letters {
            guard let uid = r.uid, let structure = r.bodyStructure,
                  let part = MIMEDecoder.previewPart(structure), part.size != 0 else { continue }
            parts[uid] = part
            let bytes = part.subtype == "html" ? IMAPMailRepository.htmlPreviewBytes
                : IMAPMailRepository.plainPreviewBytes
            windows[Window(section: part.fetchSection, bytes: bytes), default: []].append(uid)
        }
        var out: [UInt32: String] = [:]
        for (window, uids) in windows {
            guard !Task.isCancelled,
                  let bodies = try? await client.fetchPartialBodies(
                    uids: uids, section: window.section, byteCount: window.bytes,
                    in: "INBOX", validity: validity) else { continue }
            for (uid, raw) in bodies {
                guard let part = parts[uid] else { continue }
                out[uid] = IMAPMailRepository.preview(from: raw, part: part)
            }
        }
        return out
    }
}
