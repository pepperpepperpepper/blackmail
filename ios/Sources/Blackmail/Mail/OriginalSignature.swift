import Foundation

/// His signature as it was first set on this iPad, the text, its formatted
/// twin and the pictures the twin shows, kept once and never written again:
/// what "Restore Original Signature" in Settings puts back.
///
/// The formatted signature reaches the iPad only from outside the app (B-035)
/// and nothing in the app can set it, so anything that took it away took it
/// for good: "Send my signature as plain text instead", an emptied box
/// saved, or setup shown again and saving a new account over the stored
/// one. Every letter he sends, about seventy a day, would then go with a
/// bare line of text or nothing, for the rest of the install.
///
/// A file of its own in Application Support, written whole or not at all,
/// and not in `UserDefaults` beside the account, whose write a crash can
/// lose, nor under `Kept/`, which goes whenever a password is saved. Kept by
/// the first launch, or the first save, that finds a signature, and never
/// changed after, whatever becomes of the account's: a signature typed in
/// Settings before the formatted one is put on the iPad would be the
/// original, so the formatted one goes on first.
struct OriginalSignature: Codable, Equatable {
    var signature: String
    var signatureHTML: String
    var images: [SignatureImages.InlineImage]

    /// The app's: `Application Support/Original Signature/`.
    static var appRoot: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Original Signature", isDirectory: true)
    }

    private static let fileName = "signature.json"

    /// One check-and-write at a time, from the launch's queue and from
    /// Settings alike, so two first saves cannot both find no file.
    private static let lock = NSLock()

    /// Keeps `account`'s signature, with `images`, as the original, if none
    /// has been kept in `root` and the account has one. Never replaces a
    /// file that is there, whatever it holds. Returns whether it wrote.
    @discardableResult
    static func keepIfFirst(_ account: MailAccount, images: [SignatureImages.InlineImage],
                            in root: URL) -> Bool {
        guard account.hasSignature else { return false }
        lock.lock()
        defer { lock.unlock() }
        let url = root.appendingPathComponent(fileName)
        let files = FileManager.default
        guard !files.fileExists(atPath: url.path) else { return false }
        let original = OriginalSignature(signature: account.signature,
                                         signatureHTML: account.signatureHTML, images: images)
        do {
            try files.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONEncoder().encode(original).write(to: url, options: .atomic)
            return true
        } catch {
            // A full disk: the next launch or save tries again.
            return false
        }
    }

    /// The original kept in `root`, nil if none has been.
    static func load(from root: URL) -> OriginalSignature? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent(fileName)) else {
            return nil
        }
        return try? JSONDecoder().decode(OriginalSignature.self, from: data)
    }

    /// `account` signing with this signature in place of its own. The
    /// pictures are saved apart from the account (`SignatureImages`).
    func restored(into account: MailAccount) -> MailAccount {
        var out = account
        out.signature = signature
        out.signatureHTML = signatureHTML
        return out
    }
}

extension MailAccount {

    /// Some signature is set: text, or its formatted twin.
    var hasSignature: Bool {
        !signature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !signatureHTML.isEmpty
    }

    /// Whether saving `edited` in this account's place takes its signature
    /// away altogether, which Settings asks about before it saves. An empty
    /// text is no signature at all, the formatted twin included: the twin
    /// goes into a letter only where the text is found at its foot
    /// (`AppleMailHTML.isNeeded`).
    func losesSignature(to edited: MailAccount) -> Bool {
        hasSignature && edited.signature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
