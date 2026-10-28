import Foundation

/// A letter's files, drawn in its body as Apple Mail draws them (B-170).
///
/// Mail has no list of files above a letter: every file is in the body,
/// where it sits in the letter, and the files after the words at its end; a
/// picture at its size, and any other file as Mail's tile, about 160 by 120
/// with its icon, its name, its size, and "Tap to Download" for one not
/// downloaded (iOS 18.6: MessageUI writes each file as WebKit's attachment
/// element, and MobileMailUI's script gives it its words; the tile's
/// values from a style sheet left in MobileMailUI, `attachments.css`, which
/// stands in for WebKit's drawing of it). Here a file had a row in the
/// header's list from B-101, and a file put among the words a row there as
/// well from B-113, until B-148 left that one out of the header.
///
/// Apple Mail on an iPhone or an iPad sends a file put in the middle of a
/// letter between two parts of its HTML. The decoder joins the parts and
/// leaves a mark where a file sat with words after it, among them or above
/// them (`MIMEDecoder.joined`): a comment, which no page draws and a reply's
/// quote takes out with every other comment (`QuotedMarkup`), so the mark
/// never goes on to anyone. The pane makes the first mark of each file the
/// letter lists (`Message.listedAttachments`) into the file, and draws every
/// file with no mark after the words: those after all of them, and those of
/// a plain letter, whose words carry no marks. A picture the letter's HTML
/// shows by `cid:` is drawn there by the letter, and not again; one sent to
/// be shown so that the body shown does not show, the pane draws as a file,
/// as Mail draws a picture its page does not name.
///
/// A mark of anything else stays a comment: a picture the body shows by
/// `cid:`, a file the letter does not have, a second mark of a file, or a
/// mark the sender wrote, which can name nothing but the letter's own
/// parts.
enum BodyFiles {

    /// The scheme of a tile's link, which never leaves the pane.
    static let scheme = "bmfile"

    private static let open = Array("<!--bm-file:".utf8)
    private static let close = Array("-->".utf8)

    /// The mark of the file at `section`.
    static func mark(_ section: String) -> String {
        "<!--bm-file:" + section + "-->"
    }

    /// Where a body is drawn: what colours its tiles are written in, and
    /// whether a tile says "Tap to Download".
    enum Page: Sendable {
        /// The pane's page of an HTML letter, on its own or in a stack: in
        /// Mail's light colours, as the letter's own are written, which the
        /// page's invert turns with them.
        case light
        /// The pane's page of a plain letter, light words on the pane's
        /// black and not inverted: in the dark ones.
        case dark
        /// A printed letter, on white (`PrintPage`): in the light colours,
        /// printed as written, and with no "Tap to Download", which is
        /// nothing to do on paper.
        case paper
    }

    /// `content`, the markup of `m`'s body that a page draws, with every
    /// file `m` lists drawn once: each where its first mark is, and the
    /// rest after the words, together, on lines of their own. Above the
    /// words instead, where a page draws the pane's line, when the body is
    /// `cut`, shown or printed only in part: the sender's markup ends
    /// wherever the cut fell, inside a table, a link or a comment, and
    /// anything after it would be drawn inside that, or not at all
    /// (`PanePage.shortened`). As it came when `m` has no file.
    ///
    /// And a picture sent to be shown by `cid:` (`Attachment.isShownInBody`)
    /// that `content` does not show, as a file: a plain letter's, or one
    /// its HTML never names. Mail's script draws "an image that isn't
    /// referenced in the DOM" (MobileMailUI, iOS 18.6,
    /// `imageAttachmentNodeFinishedDownloading`). Not for a body `cut`,
    /// whose HTML shows them, as often as not, in what was not fetched or
    /// printed, as it does the words after the cut.
    ///
    /// One pass over the bytes for the marks, as `InlineImageRewriter`'s: a
    /// search from each mark for the next would read the rest of the letter
    /// for every one, and a sender can write a hundred thousand.
    static func drawn(in content: String, of m: Message, on page: Page, cut: Bool) -> String {
        let listed = cut ? m.listedAttachments : m.attachments
        guard !listed.isEmpty else { return content }
        let shown = shownByTheLetter(listed, in: content)
        let files = listed.filter { !shown.contains($0.id) }
        guard !files.isEmpty else { return content }
        var drawn = Set<String>()
        let marked = marks(in: content, of: m, files: files, on: page, drawn: &drawn)
        let rest = files.filter { !drawn.contains($0.id) }
        guard !rest.isEmpty else { return marked }
        let after = "<div style=\"margin: 0; white-space: normal;\">"
            + rest.map { file($0, of: m, on: page) }.joined() + "</div>"
        return cut ? after + marked : marked + after
    }

    /// `content` with the first mark of each of `files` made the file,
    /// each one drawn put in `drawn`. A mark of a file the letter draws
    /// itself, by `cid:`, is left a comment.
    private static func marks(in content: String, of m: Message, files: [Attachment], on page: Page,
                              drawn: inout Set<String>) -> String {
        let listed = Dictionary(files.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var contiguous = content
        var done = Set<String>()
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
                if let file = listed[section], done.insert(section).inserted {
                    if out.isEmpty { out.reserveCapacity(n + 1_024) }
                    out.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[copied..<i]))
                    out.append(contentsOf: Self.file(file, of: m, on: page).utf8)
                    copied = end + close.count
                }
                i = end + close.count
            }
            guard copied > 0 else { return nil }
            out.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[copied..<n]))
            return out
        }
        drawn = done
        return out.map { String(decoding: $0, as: UTF8.self) } ?? content
    }

    /// Which of `files` the letter's HTML draws itself: a picture it shows
    /// by `cid:`, its reference pointed at the loader (`InlineImageRewriter`),
    /// sent to be shown so or with no word that it is inline. Each is drawn
    /// there, and not a second time. One pass over the bytes, each address
    /// read whole, to the first byte that cannot be in one, so that `cid:a`
    /// is not taken for `cid:ab`; none for a letter with no picture sent
    /// with a `Content-ID`.
    private static func shownByTheLetter(_ files: [Attachment], in content: String) -> Set<String> {
        var wanted: [String: [String]] = [:]
        for file in files where file.mimeType.lowercased().hasPrefix("image/") {
            guard let cid = file.contentID else { continue }
            wanted[InlineImageRewriter.escapedHost(cid), default: []].append(file.id)
        }
        guard !wanted.isEmpty else { return [] }
        let address = Array((InlineImageRewriter.scheme + "://").utf8)
        var found = Set<String>()
        var contiguous = content
        contiguous.withUTF8 { bytes in
            let n = bytes.count
            var i = 0
            while i + address.count <= n {
                guard bytes[i] == address[0], starts(address, in: bytes, at: i) else {
                    i += 1
                    continue
                }
                var end = i + address.count
                while end < n, inAddress(bytes[end]) { end += 1 }
                let host = String(decoding: UnsafeBufferPointer(rebasing: bytes[(i + address.count)..<end]),
                                  as: UTF8.self)
                if let ids = wanted[host] { found.formUnion(ids) }
                i = end
            }
        }
        return found
    }

    /// The bytes `InlineImageRewriter.escapedHost` writes an address with:
    /// letters and digits, a letter of another alphabet among them, `-._~`,
    /// and `%` for every other.
    private static func inAddress(_ c: UInt8) -> Bool {
        (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c >= 0x80
            || c == 0x2D || c == 0x2E || c == 0x5F || c == 0x7E || c == 0x25
    }

    /// A file as a body draws it: a picture WebKit draws at its size
    /// (`picture`), any other file as Mail's tile (`tile`).
    static func file(_ file: Attachment, of m: Message, on page: Page) -> String {
        isPicture(file) ? picture(file, of: m) : tile(file, of: m, on: page)
    }

    /// The kinds of picture drawn at their size: those WebKit draws on
    /// iPadOS 16 and 18 alike, and HEIC, an iPhone's photo, as Mail draws
    /// it on 16.5.1 as on 17 and 18 (B-176). WebKit draws HEIC only from
    /// iPadOS 17; below it the loader serves a JPEG made of it
    /// (`HEICPicture`, B-171), as for one the letter shows by `cid:`. Any
    /// other picture, a TIFF say, is a tile.
    static let pictureKinds = Set([
        "image/jpeg", "image/jpg", "image/pjpeg", "image/png", "image/gif", "image/webp", "image/bmp",
    ]).union(HEICPicture.kinds)

    /// Whether `file` is drawn as a picture.
    static func isPicture(_ file: Attachment) -> Bool {
        pictureKinds.contains(file.mimeType.lowercased())
    }

    /// A picture file at its size, no wider than the letter (the page's own
    /// rule for every picture), from the loader as the letter's own
    /// pictures come (`PanePage.pictures`), by `pictureID`. Its name is its
    /// words where it could not be drawn, and a tap on them opens it. A tap
    /// on it opens it in Quick Look, and a finger held on it gives the
    /// menu a held photo gives (`PanePictures`, B-122, B-150).
    static func picture(_ file: Attachment, of m: Message) -> String {
        "<img src=\"" + InlineImageRewriter.scheme + "://"
            + InlineImageRewriter.escapedHost(pictureID(file.id, of: m.id))
            + "\" alt=\"" + QuotedMarkup.attributeEscaped(file.filename) + "\">"
    }

    /// The address the loader is asked for a picture file by: no
    /// `Content-ID` the letter can have, as the file may have none, and its
    /// letter's in it, since one loader serves every letter of a stack and
    /// nearly every letter has a part "2". Read back by
    /// `PanePictures.part(_:of:)`.
    static func pictureID(_ section: String, of letter: String) -> String {
        "bmfile-" + ConversationDocument.sectionID(for: letter) + "-" + section
    }

    /// A file as Mail's tile: a box of 160 by 120 inside a hairline border
    /// rounded at 15, 5 apart, with its icon, 37 by 48, its name, its size,
    /// and "Tap to Download" for a file of a letter opened without them
    /// (`Message.filesLeftOnServer`) too large to come unasked, or
    /// "Downloading" with a ring in its icon's place for one fetched as the
    /// letter opens (`FilesAhead`, B-176), each on a line of its own, centred,
    /// and cut short with an ellipsis where it is too long. The values of
    /// a style sheet left in MobileMailUI (iOS 18.6, `attachments.css`),
    /// which nothing in it names any more: Mail's tile is WebKit's own
    /// drawing of its attachment element now, and the sheet stands in for
    /// it. The name and the size in the grey caption, as the sheet's two
    /// labels for them and WebKit's own element have them, and the last
    /// line in the bold footnote, Mail's blue.
    ///
    /// Their sizes written out, 12 and 13, the caption's and the
    /// footnote's at the iPad's default text size, and not the keywords
    /// Mail's sheet has, which WebKit sizes by the text size in Settings:
    /// no text of the pane moves with it (D-007, B-071), and the box,
    /// whose size is written out as Mail's, would cut the lines at the
    /// larger sizes. B-166 had the pane's text move with the text size,
    /// and the page's head scale the whole tile with it (`sizeRule`;
    /// int19); since 2026-10-27 the pane is drawn at Large whatever the
    /// iPad's size (`TextSize.drawn`), as before, and the tile with it.
    ///
    /// A link of the pane's own (`link`): a tap opens the file in Quick
    /// Look (`PaneNavigation`'s `openFile`), and its last line says
    /// "Downloading" with a ring in its icon's place while the file comes
    /// (`Busy`), Mail's words and Mail's ring (B-176), where it said
    /// "Loading…" in a tile dimmed. The tile's colour Mail's blue, which
    /// no line of it takes, for the ring's arc (`ring`). No callout and no
    /// selection, as Mail's sheet has, and no drag, so a finger held on it
    /// gives the pane's menu for the file (`ConversationDocument.script`'s
    /// hold) and not WebKit's for a link.
    ///
    /// Every rule inline, so the tile is the same on a letter's own page,
    /// in a stack and on paper; those that make it a tile important, which
    /// no rule of the sender's outranks. No white space between its tags,
    /// which a plain letter's page would draw.
    static func tile(_ file: Attachment, of m: Message, on page: Page) -> String {
        let light = page != .dark
        let border = light ? "rgba(0, 0, 0, 0.3)" : "rgba(255, 255, 255, 0.3)"
        let grey = light ? "rgba(4, 4, 15, 0.45)" : "#8e8e93"
        let blue = light ? "#007AFF" : "#0A84FF"
        let paper = page == .paper ? " -webkit-print-color-adjust: exact; break-inside: avoid;" : ""
        let size = file.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
        let coming = page != .paper && FilesAhead.fetches(file, of: m)
        let status = page == .paper || !m.filesLeftOnServer ? "" : coming ? downloading : tapToDownload
        let label = "display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;"
        return "<a class=\"" + tileClass + "\" href=\"" + QuotedMarkup.attributeEscaped(link(file.id, of: m.id))
            + "\" style=\""
            + "display: inline-block !important; box-sizing: content-box !important;"
            + " width: 160px !important; height: 120px !important; margin: 5px !important;"
            + " padding: 3px !important; border: 1px solid " + border + " !important;"
            + " border-radius: 15px !important; overflow: hidden !important; vertical-align: top;"
            + " text-align: center; text-decoration: none; white-space: nowrap; line-height: normal;"
            + " color: " + blue + ";"
            + " -webkit-tap-highlight-color: rgba(0, 0, 0, 0);"
            + " -webkit-touch-callout: none !important; -webkit-user-select: none !important;"
            + " -webkit-user-drag: none !important;" + paper
            + "\"><span style=\"display: block; position: relative; top: 50%;"
            + " transform: translateY(-50%);\">"
            + (coming ? ring : icon(file))
            + "<span style=\"" + label + " " + caption + " color: " + grey + ";\">"
            + QuotedMarkup.escaped(file.filename) + "</span>"
            + "<span style=\"" + label + " " + caption + " color: " + grey + ";\">"
            + QuotedMarkup.escaped(size) + "</span>"
            + "<span class=\"bm-file-status\" style=\"" + label + " " + footnote + " color: " + blue + ";\">"
            + status + "</span></span></a>"
    }

    /// The tile's class, for the page's head to size it (`sizeRule`).
    static let tileClass = "bm-tile"

    /// The head's rule that draws every tile of a page at the pane's text
    /// size (B-166; "" since 2026-10-27, the pane being drawn at Large
    /// whatever the iPad's size, `TextSize.drawn`): the box, its icon and its
    /// lines scaled together by the pane's body size over its size at Large,
    /// 17, the scale the rest of the pane's CSS has (`Theme.textScale`), as
    /// WebKit scales its own element in Mail by the text size, box and lines,
    /// never below the default (`attachmentDynamicTypeScaleFactor`). Not
    /// WebKit's keywords for the caption and the footnote, which follow the
    /// iPad's size whatever the app's restyle says, and would outgrow the
    /// box: one scale for the box and its words. "" at Large and below, so
    /// the page is as it was there. In the head, not on the tile, so a stack
    /// drawn again at a new size, its bodies put back as they came, has its
    /// tiles at the new size (int19).
    ///
    /// No more than twice the size at Large, `maxTileZoom`: a tile is 178
    /// points wide with its margin, and the letter's column, which keeps
    /// its width at every size, is about 382 in two panes in portrait on
    /// the 10.2-inch iPad. At the larger accessibility sizes, 2.353 at AX3
    /// to 3.118 at AX5, a tile was wider than the letter, which then
    /// scrolled sideways, and on paper, 540 wide, it was cut (int19).
    static func sizeRule(bodyPointSize: Int) -> String {
        guard bodyPointSize > 17 else { return "" }
        let scale = (min(Double(bodyPointSize) / 17, maxTileZoom) * 1000).rounded() / 1000
        return "a.\(tileClass) { zoom: \(scale) !important; }"
    }

    /// The most `sizeRule` scales a tile by: 356 points with its margin,
    /// within the narrowest column a letter is drawn in.
    static let maxTileZoom = 2.0

    /// The type of a tile's name and size: the caption's, at its size at
    /// the iPad's default text size.
    static let caption = "font: 12px -apple-system, sans-serif;"

    /// The type of a tile's last line: the footnote's, bold, at its size
    /// at the iPad's default text size.
    static let footnote = "font: bold 13px -apple-system, sans-serif;"

    /// Mail's words under a file not yet downloaded.
    static let tapToDownload = "Tap to Download"

    /// Mail's words under a file on its way (`DOWNLOADING_STATUS`, B-176),
    /// as its tile said them on the test iPad.
    static let downloading = "Downloading"

    /// The last line of a tile drawn with one, its file come as its letter
    /// opened (`Landed`, B-176): a no-break space, which says nothing and
    /// keeps the line's height. Emptied, the line had none, and the icon,
    /// the name and the size, centred in the box, dropped half a line.
    static let saysNothing = "\u{00A0}"

    /// Mail's ring in a tile's icon's place while its file comes (B-176):
    /// in the icon's box, 37 by 48 with 8 under it, so nothing in the tile
    /// moves; a grey circle, the icon's grey, and an arc of the tile's
    /// blue turning on it, by the drawing's own animation, which needs no
    /// script. Mail's ring fills as the file comes; a fetch here says
    /// nothing of how far it has got, so the arc turns.
    static let ring = "<svg class=\"bm-file-ring\" width=\"37\" height=\"48\" viewBox=\"0 0 37 48\""
        + " style=\"display: block; margin: 0 auto 8px auto;\">"
        + "<circle cx=\"18.5\" cy=\"24\" r=\"14\" fill=\"none\" stroke=\"#c7c7cc\" stroke-width=\"2\"></circle>"
        + "<path d=\"M18.5 10A14 14 0 0 1 32.5 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\""
        + " stroke-linecap=\"round\"><animateTransform attributeName=\"transform\" type=\"rotate\""
        + " from=\"0 18.5 24\" to=\"360 18.5 24\" dur=\"1s\" repeatCount=\"indefinite\"></animateTransform>"
        + "</path></svg>"

    /// A file's icon on its tile, 37 by 48 with 8 under it, as Mail's
    /// sheet has it: a sheet of paper with its corner turned, and the
    /// file's kind on it, from the end of its name, as iOS's own icons
    /// have. Not iOS's icon itself, nor Mail's preview of the file's first
    /// page, which the page cannot ask iOS for. White in both colourings,
    /// as iOS's sheets are: the page's invert turns it back, as it turns
    /// the letter's own drawings (`SignatureSheet.invert`).
    static func icon(_ file: Attachment) -> String {
        let name = file.filename
        let dot = name.lastIndex(of: ".")
        let kind = dot.map { String(name[name.index(after: $0)...]).uppercased() } ?? ""
        let shown = kind.count <= 4 && kind.allSatisfy({ $0.isLetter || $0.isNumber }) ? kind : ""
        return "<svg width=\"37\" height=\"48\" viewBox=\"0 0 37 48\""
            + " style=\"display: block; margin: 0 auto 8px auto;\">"
            + "<path d=\"M1.5 1.5H25.5L35.5 11.5V46.5H1.5Z\" fill=\"#fff\" stroke=\"#c7c7cc\"/>"
            + "<path d=\"M25.5 1.5V11.5H35.5\" fill=\"none\" stroke=\"#c7c7cc\"/>"
            + (shown.isEmpty ? "" : "<text x=\"18.5\" y=\"37\" text-anchor=\"middle\""
                + " font-family=\"-apple-system, sans-serif\" font-size=\"9\" font-weight=\"bold\""
                + " fill=\"#8e8e93\">" + QuotedMarkup.escaped(shown) + "</text>")
            + "</svg>"
    }

    /// A file's tile shown coming while its file downloads, and as it was
    /// once it has opened or been let go (B-148, B-170):
    /// `ConversationDocument.script`'s `bmFileBusy`, called through
    /// `callAsyncJavaScript` with the tile's link, whether it is coming,
    /// and the words it says so with.
    ///
    /// A PDF of 20 MB took six seconds with nothing on the screen to say
    /// the tap had landed. Coming, its icon is Mail's ring (`ring`), and
    /// its last line, where Mail's says "Tap to Download", says
    /// "Downloading", as Mail's tile says while its file comes (B-176);
    /// it was dimmed and said "Loading…" until then. Then it is as it
    /// was. Every tile with the link. A link the page has no tile for
    /// changes nothing: a picture's, or a page drawn since.
    struct Busy: Equatable {
        let link: String
        let busy: Bool

        init(_ section: String, of letter: String, busy: Bool) {
            link = BodyFiles.link(section, of: letter)
            self.busy = busy
        }

        /// What `callAsyncJavaScript` runs, in the app's content world,
        /// where `ConversationDocument.script` defined `bmFileBusy`.
        static let script = "bmFileBusy(link, busy, words, ring)"

        var arguments: [String: Any] {
            ["link": link, "busy": busy, "words": BodyFiles.downloading, "ring": BodyFiles.ring]
        }
    }

    /// A file fetched as its letter opened has come, or could not be
    /// (`FilesAhead`, B-176): `ConversationDocument.script`'s
    /// `bmFileLanded`, called with the tile's link, its icon, and the
    /// words of its last line: none for a file in hand, as a tile of a
    /// letter fetched whole says, the line kept (`saysNothing`), so nothing
    /// in the tile moves; and "Tap to Download" for one that could not be
    /// fetched. The ring the tile was drawn with gives way to the icon. A
    /// tile shown coming for a tap meanwhile (`Busy`) is left as it is, and
    /// is put back so.
    struct Landed: Equatable {
        let link: String
        let icon: String
        let words: String

        init(_ file: Attachment, of letter: String, inHand: Bool) {
            link = BodyFiles.link(file.id, of: letter)
            icon = BodyFiles.icon(file)
            words = inHand ? BodyFiles.saysNothing : BodyFiles.tapToDownload
        }

        /// What `callAsyncJavaScript` runs, in the app's content world.
        static let script = "bmFileLanded(link, icon, words)"

        var arguments: [String: Any] { ["link": link, "icon": icon, "words": words] }
    }

    /// A finger held on a file's tile, as the script posts it to the
    /// pane's picture handler (B-170): the file its link names, and where
    /// the finger is in the web view, in points, for the menu a held photo
    /// gives (`PanePictures.menu(for:)`).
    struct Hold: Equatable {
        let letter: String
        let section: String
        let x: Double
        let y: Double

        /// What the script posted, nil for anything else: a tap on a
        /// picture, a link that is no tile's, or a place missing, not a
        /// number or not finite.
        init?(_ body: Any) {
            guard let fields = body as? [String: Any],
                  let link = fields["file"] as? String,
                  let url = URL(string: link),
                  let file = BodyFiles.opening(url),
                  let hold = fields["hold"],
                  (hold as? Bool) ?? (hold as? NSNumber)?.boolValue ?? false,
                  let x = Self.number(fields["x"]), let y = Self.number(fields["y"]),
                  x.isFinite, y.isFinite
            else { return nil }
            letter = file.letter
            section = file.section
            self.x = x
            self.y = y
        }

        /// A number as WebKit hands one over, an `NSNumber`, or as Swift
        /// holds one.
        private static func number(_ value: Any?) -> Double? {
            if let n = value as? NSNumber { return n.doubleValue }
            if let d = value as? Double { return d }
            if let i = value as? Int { return Double(i) }
            return nil
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

    /// The letter and the part a tile's link opens; nil for any other link.
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
