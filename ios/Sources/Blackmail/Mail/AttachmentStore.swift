import Foundation

/// Puts a downloaded attachment somewhere the system can open it.
///
/// QuickLook and the share sheet both work in file URLs, not bytes, so an
/// attachment has to reach the disk before it can be read or saved. That
/// makes this the one place in the app that creates a file whose NAME a
/// stranger chose, which is why the sanitising below is not decoration.
///
/// Foundation-only, so the name handling is tested on the host rather than
/// through a build, sign and deploy cycle.
enum AttachmentStore {

    /// Where everything written by this type lives, so it can all be thrown
    /// away in one call.
    static var root: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
    }

    /// A sender-supplied filename reduced to something safe to create.
    ///
    /// Three separate ways a name can escape the directory it is appended
    /// to, and all three arrive from outside:
    ///
    /// 1. Path separators. `MIMEDecoder` already strips them out of a
    ///    `filename=` parameter, but this is the function that actually
    ///    touches the filesystem and it does not get to assume its caller.
    /// 2. `.` and `..`, which survive every character filter — neither
    ///    contains anything illegal — and both name a DIRECTORY, so
    ///    `appendingPathComponent("..")` hands back the parent.
    /// 3. Control characters and colons, which are legal in a POSIX name and
    ///    make a mess of every picker that later shows it.
    static func safeFilename(_ raw: String) -> String {
        var name = raw
        if let separator = name.lastIndex(where: { $0 == "/" || $0 == "\\" }) {
            name = String(name[name.index(after: separator)...])
        }
        name = String(name.unicodeScalars.filter { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7F
                && scalar != "/" && scalar != "\\" && scalar != ":"
        }.map(Character.init)).trimmingCharacters(in: .whitespaces)

        guard !name.isEmpty, name != ".", name != ".." else { return "attachment" }
        // Long enough for any real filename and short of every filesystem's
        // limit. Truncating the FRONT would be wrong — the extension is at
        // the back and is what decides whether QuickLook can open it.
        return String(name.prefix(120))
    }

    /// Writes the bytes and hands back the URL to open.
    ///
    /// A fresh UUID directory per file rather than a unique filename: two
    /// attachments genuinely called "scan.pdf" must not collide, and the
    /// name the reader sees at the top of the preview should be the name the
    /// sender gave it, not "scan-2.pdf".
    static func write(_ data: Data, named filename: String) throws -> URL {
        let url = try place(for: filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// A file another app handed over, copied in the way `write` writes
    /// bytes, without being read into memory on the way: a share extension
    /// is allowed far less of it than the app, and a shared file can be
    /// larger than all of it.
    static func copy(_ source: URL, named filename: String) throws -> URL {
        let url = try place(for: filename)
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }

    private static func place(for filename: String) throws -> URL {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(safeFilename(filename))
    }

    /// Deletes everything written so far.
    ///
    /// Called at launch. The temporary directory is the system's to reclaim
    /// and it will do so eventually, but "eventually" on a device that is
    /// never restarted and holds one person's entire correspondence is not a
    /// bound. Launch is the only moment nothing can be open.
    static func purge() {
        try? FileManager.default.removeItem(at: root)
    }
}
