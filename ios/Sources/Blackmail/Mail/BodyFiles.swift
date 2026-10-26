import Foundation

/// A file sent among a letter's words, drawn where it sat (B-113).
///
/// Apple Mail on an iPhone or an iPad sends a file put in the middle of a
/// letter between two parts of its HTML, and draws it there: the words,
/// the file, the words after it. The decoder joins the parts and leaves a
/// mark where the file was (`MIMEDecoder.joined`): a comment, which no page
/// draws and a reply's quote takes out with every other comment
/// (`QuotedMarkup`), so the mark never goes on to anyone. The pane makes
/// the mark of a file the header lists (`Message.listedAttachments`) into
/// its row, once: its name and size as the header's row has them, a link
/// that opens it as a tap on that row does (`PaneNavigation`'s
/// `openFile`). The header no longer lists it (`inHeader`, B-148): Mail
/// lists such a file once, where it sat. It kept its row there, from the
/// tap as before (B-101), until 2026-10-26, so a PDF among the words had
/// two. The row among the words shows its file coming as the header's
/// row did (`Busy`).
///
/// A mark of anything else stays a comment: a picture the body shows by
/// `cid:`, a file the letter does not have, or a mark the sender wrote,
/// which can name nothing but the letter's own files. A plain letter has
/// no marks, and draws no row among its words.
enum BodyFiles {

    /// The scheme of a row's link, which never leaves the pane.
    static let scheme = "bmfile"

    private static let open = Array("<!--bm-file:".utf8)
    private static let close = Array("-->".utf8)

    /// The mark of the file at `section`.
    static func mark(_ section: String) -> String {
        "<!--bm-file:" + section + "-->"
    }

    /// `html`, a page's markup of `m`, with each mark of a file the header
    /// lists made the file's row, the first mark of each only; as it came
    /// when there is none.
    ///
    /// One pass over the bytes, as `InlineImageRewriter`'s: a search from
    /// each mark for the next would read the rest of the letter for every
    /// one, and a sender can write a hundred thousand.
    static func rows(in html: String, of m: Message) -> String {
        let files = m.listedAttachments
        guard !files.isEmpty else { return html }
        let listed = Dictionary(files.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var drawn = Set<String>()
        var contiguous = html
        let out = contiguous.withUTF8 { bytes -> [UInt8]? in
            let n = bytes.count
            var out: [UInt8] = []
            var copied = 0
            var i = 0
            while i + open.count <= n {
                guard bytes[i] == open[0], starts(open, in: bytes, at: i) else {
                    i += 1
                    continue
                }
                var end = i + open.count
                while end < n, bytes[end] == 0x2E || (bytes[end] >= 0x30 && bytes[end] <= 0x39) {
                    end += 1
                }
                guard end > i + open.count, starts(close, in: bytes, at: end) else {
                    i += 1
                    continue
                }
                let section = String(decoding: UnsafeBufferPointer(rebasing: bytes[(i + open.count)..<end]),
                                     as: UTF8.self)
                if let file = listed[section], drawn.insert(section).inserted {
                    if out.isEmpty { out.reserveCapacity(n + 256) }
                    out.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[copied..<i]))
                    out.append(contentsOf: row(file, of: m).utf8)
                    copied = end + close.count
                }
                i = end + close.count
            }
            guard copied > 0 else { return nil }
            out.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[copied..<n]))
            return out
        }
        return out.map { String(decoding: $0, as: UTF8.self) } ?? html
    }

    /// A file's row among the words: its name and size as the header's row
    /// writes them (`MessageHeaderView`), on a line of its own, in the
    /// letter's link colour, 44 pt tall to the finger.
    static func row(_ file: Attachment, of m: Message) -> String {
        let size = file.size.map {
            " (" + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) + ")"
        } ?? ""
        return "<div style=\"margin: 0;\"><a href=\""
            + QuotedMarkup.attributeEscaped(link(file.id, of: m.id))
            + "\" style=\"display: inline-block; padding: 10px 0; text-decoration: none;\">"
            + QuotedMarkup.escaped(file.filename + size) + "</a></div>"
    }

    /// A file's row among the words shown coming while its file downloads,
    /// and as it was once it has opened or been let go (B-148):
    /// `ConversationDocument.script`'s `bmFileBusy`, called through
    /// `callAsyncJavaScript` with the row's link, whether it is coming,
    /// and the words it says so with.
    ///
    /// The header's row has its spinner for this, and a file among the
    /// words has had no row there since B-148: a PDF of 20 MB tapped there
    /// took six seconds with nothing on the screen to say the tap had
    /// landed. Nor did a row of a letter of the conversation the header is
    /// not on ever have one. Coming, the row is dimmed, as the header's row
    /// is greyed, and "Loading…" follows its name, the pane's word for
    /// what is on its way, where the header's row has its spinner. Every
    /// row with the link, so a file with a row in the header too, after a
    /// cut, has both shown. A link the page has no row for changes
    /// nothing: a picture's, or a page drawn since.
    struct Busy: Equatable {
        let link: String
        let busy: Bool

        init(_ section: String, of letter: String, busy: Bool) {
            link = BodyFiles.link(section, of: letter)
            self.busy = busy
        }

        /// What `callAsyncJavaScript` runs, in the app's content world,
        /// where `ConversationDocument.script` defined `bmFileBusy`.
        static let script = "bmFileBusy(link, busy, words)"

        var arguments: [String: Any] { ["link": link, "busy": busy, "words": PaneNotice.loading] }
    }

    /// The files the reading pane's header lists for `m` (B-148): every
    /// file it lists (`Message.listedAttachments`) but the ones its page
    /// draws among the words, each of which has its row there and only
    /// there, as Mail lists a file once, where it sat.
    ///
    /// Which those are is the letter's structure's to say
    /// (`Attachment.isAmongWords`, `MIMEDecoder.filesAmongWords`), so the
    /// header drawn at the tap, from the row, before a byte of the body has
    /// come (`Message.heading(for:)`), leaves out the files the body will
    /// draw, and does not change height when the body comes. Once the body
    /// has come, a file the page does not draw among the words after all
    /// keeps its row: the page is the pane's words for a letter with
    /// nothing in it (`PanePage.isEmpty`), or the plain words, the HTML
    /// refused by the server, or its mark is not in the HTML that came.
    /// The header then grows by that row when the body comes: once the
    /// body has come, a file is never left with no row anywhere. Until
    /// then it has none: a letter that could not be downloaded keeps the
    /// header drawn from its row, its files grey and none for such a file,
    /// under "This message could not be downloaded.", until a tap on it
    /// fetches it again. The grey row it had there before could not open
    /// it either.
    static func inHeader(_ m: Message) -> [Attachment] {
        let listed = m.listedAttachments
        guard listed.contains(where: \.isAmongWords) else { return listed }
        // Drawn from the row: no body yet, nothing to look at but the
        // structure.
        guard m.htmlBody != nil || m.textBody != nil || m.isShortened else {
            return listed.filter { !$0.isAmongWords }
        }
        let html = PanePage.isEmpty(m) ? nil : m.htmlBody
        return listed.filter { file in
            guard file.isAmongWords, let html else { return true }
            return !html.contains(mark(file.id))
        }
    }

    /// The link of the file at `section` of the letter `letter`.
    static func link(_ section: String, of letter: String) -> String {
        var parts = URLComponents()
        parts.scheme = scheme
        parts.path = section
        parts.queryItems = [URLQueryItem(name: "letter", value: letter)]
        return parts.string ?? scheme + ":" + section
    }

    /// The letter and the part a row's link opens; nil for any other link.
    static func opening(_ url: URL) -> (letter: String, section: String)? {
        guard url.scheme?.lowercased() == scheme,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let letter = parts.queryItems?.first(where: { $0.name == "letter" })?.value,
              !letter.isEmpty, !parts.path.isEmpty,
              parts.path.utf8.allSatisfy({ $0 == 0x2E || ($0 >= 0x30 && $0 <= 0x39) })
        else { return nil }
        return (letter, parts.path)
    }

    private static func starts(_ needle: [UInt8], in bytes: UnsafeBufferPointer<UInt8>,
                               at index: Int) -> Bool {
        guard index + needle.count <= bytes.count else { return false }
        for k in 0..<needle.count where bytes[index + k] != needle[k] { return false }
        return true
    }
}
