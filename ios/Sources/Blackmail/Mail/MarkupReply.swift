import Foundation

/// Markup and Reply on a picture held in a letter (B-171), as Mail's menu
/// for a file of the letter's has it, second, after Quick Look: the picture
/// opened in iOS's own Markup, and what he draws on it put in a Reply to
/// the letter, under his words, as a photo he adds goes (B-109).
///
/// Mail's own is the private MarkupUI, which MobileMailUI soft-links for
/// its "Markup and Reply" (`MARKUP_DOCUMENT`, iOS 18.6); an app has no way
/// to it. Mail's composer marks up a file in Quick Look, and so does this:
/// `QLPreviewController`, its item's editing mode `createCopy`, the copy
/// of what he drew handed to its delegate
/// (`previewController(_:didSaveEditedCopyOf:at:)`), as iOS 13 made public
/// and MessageUI on iOS 18.6 uses. The photo full screen, with Quick
/// Look's Markup button; he draws, and Done closes it. A copy saved, the
/// Reply opens with it as it closes; none, and he is back at the letter
/// with nothing made.
///
/// What Quick Look saves is copied at once to where the composer's photos
/// are staged (`AttachmentStore`), since the file it hands over is its own
/// and temporary, and only the last copy is kept: Apple's documentation
/// says it may hand over a copy each time he saves. The reply is the app's
/// own Reply, whom it goes to, its subject, its quote and his signature as
/// the Reply button's (`Draft.replying`, `ReplyAddressing`), and the copy
/// lands in it as a photo he picks lands (`ComposeViewController.landing`):
/// a row of his own with its weight and its Remove, and in the letter under
/// his words and above his signature. Nothing goes unless he taps Send.
///
/// Out of `MessageDetailViewController` for the reason `PaneNavigation`
/// is: the controller is UIKit, and the suite runs where there is none.
struct MarkupReply: Equatable {

    /// Where a picture's marking up stands. `preview` is the Quick Look it
    /// was opened in (`ObjectIdentifier` of the `QLPreviewController`):
    /// what another hands over or says is taken for nothing.
    enum State: Equatable {
        /// None under way.
        case idle
        /// Quick Look is up with Markup, holding the last copy saved of
        /// what he drew, nil before any.
        case marking(preview: ObjectIdentifier, DraftAttachment?)
        /// Quick Look closed with no copy, at `since`: a copy saved within
        /// `late` of it still makes the reply.
        case closed(preview: ObjectIdentifier, since: Date)
        /// The copy handed to the reply, at `since`, whose composer is not
        /// up yet: Quick Look may still be over the pane (`ended`).
        case replying(since: Date)
    }

    private(set) var state = State.idle

    /// How long after Quick Look has closed with no copy a copy is still
    /// taken for the reply. Quick Look gets what was drawn from its own
    /// process before it closes, by its name for that
    /// (`isObtainingEditsFromServiceBeforeDismissing`), so the copy comes
    /// first; an order not seen on the iPad is not counted on. And the
    /// longest a reply is waited for without word that it has opened.
    static let late: TimeInterval = 5

    /// A picture opened for Markup in the Quick Look `preview`: what was
    /// under way ends, and a copy it held, never put in a reply, is handed
    /// back to be let go.
    mutating func begin(_ preview: ObjectIdentifier) -> DraftAttachment? {
        let unused: DraftAttachment?
        if case let .marking(_, copy) = state { unused = copy } else { unused = nil }
        state = .marking(preview: preview, nil)
        return unused
    }

    /// Whether Quick Look `preview` has Markup: the one a picture was
    /// opened in for Markup and Reply (`begin`), while it is up. Any other,
    /// a tap's or the held menu's Quick Look, has none, as Mail's Quick
    /// Look of a picture in a letter has none (B-171).
    func marks(in preview: ObjectIdentifier) -> Bool {
        if case let .marking(open, _) = state { return open == preview }
        return false
    }

    /// Quick Look `preview` saved a copy of what he drew. While it is up,
    /// the copy is kept, and the one before it handed back to be let go.
    /// Once it has closed with none, within `late`, it is the reply's.
    /// Anything else, none under way, too late, or another Quick Look's,
    /// is handed back to be let go.
    mutating func saved(_ copy: DraftAttachment, from preview: ObjectIdentifier, at now: Date)
        -> (reply: DraftAttachment?, unused: DraftAttachment?) {
        switch state {
        case let .marking(open, before) where open == preview:
            state = .marking(preview: open, copy)
            return (nil, before)
        case let .closed(open, since) where open == preview && now.timeIntervalSince(since) <= Self.late:
            state = .replying(since: now)
            return (copy, nil)
        case .marking, .closed, .replying, .idle:
            return (nil, copy)
        }
    }

    /// Quick Look `preview` has closed: the reply's copy, the last saved,
    /// or nil, for nothing drawn, nothing under way, or another Quick
    /// Look's closing.
    mutating func closed(_ preview: ObjectIdentifier, at now: Date) -> DraftAttachment? {
        guard case let .marking(open, copy) = state, open == preview else { return nil }
        guard let copy else {
            state = .closed(preview: open, since: now)
            return nil
        }
        state = .replying(since: now)
        return copy
    }

    /// The reply's composer has opened, or its copy has been let go:
    /// nothing under way. A picture opened for Markup since is left.
    mutating func ended() {
        if case .replying = state { state = .idle }
    }

    /// Whether a marking up is under way: Quick Look up, closed with no
    /// copy less than `late` ago, or its copy handed to a reply not yet
    /// opened, for `late` at most. The warning before the app stops
    /// opening waits for it (`isOpeningFile`, B-137), whose alert up would
    /// keep the reply's composer off the screen, and his drawing with it.
    func isBusy(at now: Date) -> Bool {
        switch state {
        case .idle: return false
        case .marking: return true
        case let .closed(_, since), let .replying(since):
            return now.timeIntervalSince(since) <= Self.late
        }
    }

    // MARK: - The copy

    /// What the copy goes in the reply as: its name and its kind as it
    /// came, and the name of a JPEG to be made of it first, nil for none.
    struct Picture: Equatable {
        let name: String
        let mimeType: String
        let jpegName: String?
    }

    /// The copy of `original`, a picture of the letter's of kind
    /// `originalType`, that Quick Look saved at `copy`: the picture's own
    /// name with the copy's extension, which Apple's documentation says may
    /// differ from the original's, and the kind that extension names
    /// (`lookup`), or the picture's own where it names none.
    ///
    /// A JPEG, PNG or GIF goes as it is, and in the letter under his words
    /// (`DraftAttachment.isBodyPicture`); any other kind, a HEIC say, is
    /// made a JPEG of first, under the same name ending ".jpg", so that it
    /// goes there too, where every mail program shows it, as his Apple
    /// Mail letters' pictures went (B-109).
    static func picture(original: String, originalType: String, copy: URL,
                        lookup: (String) -> String?) -> Picture {
        let base = AttachmentStore.safeFilename(original)
        let stem = stem(of: base)
        let ext = copy.pathExtension
        let name = ext.isEmpty ? base : stem + "." + ext
        var type = AttachmentStore.mimeType(of: name, lookup: lookup)
        if type == AttachmentStore.octetStream { type = originalType }
        let kind = type.trimmingCharacters(in: .whitespaces).lowercased()
        let goes = DraftAttachment.bodyPictureTypes.contains(kind)
        return Picture(name: name, mimeType: goes ? kind : type, jpegName: goes ? nil : stem + ".jpg")
    }

    /// `name` without its extension; the whole of it for a name with none,
    /// or one that is only an extension, ".jpg".
    private static func stem(of name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }

    /// The copy Quick Look saved at `copy`, staged as the composer's photos
    /// are (`AttachmentStore`): the row the reply carries. A JPEG made of
    /// it by `jpeg` where `picture` names one, at the share sheet's quality
    /// (`SharedPhoto.quality`) on the iPad; where none can be made, from
    /// a file no picture can be read from, the copy as it came, under its
    /// own kind, which goes as a file. Throws when nothing can be staged.
    static func stage(_ copy: URL, as picture: Picture, jpeg: (URL) -> Data?) throws -> DraftAttachment {
        let staged: URL
        let name: String
        let type: String
        if let jpegName = picture.jpegName, let data = jpeg(copy) {
            staged = try AttachmentStore.write(data, named: jpegName)
            (name, type) = (jpegName, "image/jpeg")
        } else {
            staged = try AttachmentStore.copy(copy, named: picture.name)
            (name, type) = (picture.name, picture.mimeType)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: staged.path)[.size] as? NSNumber)
            .map { $0.int64Value }
        return DraftAttachment(source: .localFile(staged), filename: name, mimeType: type, size: size)
    }

    /// Lets a copy go that will be in no reply: its staged file and its
    /// directory, and nothing that was not staged (`AttachmentStore.removeStaged`).
    static func letGo(_ copy: DraftAttachment?) {
        guard let copy, case let .localFile(url) = copy.source else { return }
        AttachmentStore.removeStaged(url)
    }
}
